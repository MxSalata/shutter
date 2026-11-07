#!/usr/bin/env python3
"""Whether the rig stands, on a real instance. It proves no product behaviour: only that each listener mode does what it says over
the instance's loopback, that the install puts the productions up and signs its REST sessions out, that the routed production's
rule calls its function, and that a stop and start that did not happen is reported as such and fails the run.

    python3 tests/e2e/v11_rig/check_rig.py --ctr NAME --port PORT --image IMAGE [--module core] [--keep]

Run from a copy of the repository's tree. Exit status: 0 all ok; 1 a check failed; 3 the rig broke before it could answer.
"""
import argparse
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from rig import PW, Rig, RigBroken, RestartNotProven  # noqa: E402, F401

failed = []
passed = 0
# Ports for the mode checks alone: no item of either production dials them.
P_DOWN, P_UP, P_AE, P_AR, P_DIE, P_HANG, P_HEX = 7801, 7802, 7803, 7804, 7805, 7806, 7807


def check(name, ok, detail=""):
    global passed
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {str(detail)[:1200]}"), flush=True)
    if ok:
        passed += 1
    else:
        failed.append(name)


def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


def listener_modes(r):
    step("Each listener mode, over the instance's own loopback")
    got = r.probe(P_DOWN)
    check("down refuses the connect", got == "REFUSED", got)

    r.listener_up(P_UP, {"mode": "up"})
    got = r.probe(P_UP, r.adt("A01", "UP1"))
    check("up answers AA", got.startswith("MSA|AA|UP1"), got)

    r.listener_up(P_AE, {"mode": "answer", "code": "AE", "words": "Test code not recognised: XQ9", "err": ["ERR|||204|E|||Unknown code"]})
    got = r.probe(P_AE, r.result("AE1"))
    check("AE carries the chosen words", got == "MSA|AE|AE1|Test code not recognised: XQ9 ERR|||204|E|||Unknown code", got)

    r.listener_up(P_AR, {"mode": "answer", "code": "AR", "words": "Patient not found"})
    got = r.probe(P_AR, r.order("AR1"))
    check("AR carries the chosen words", got == "MSA|AR|AR1|Patient not found", got)

    r.listener_up(P_DIE, {"mode": "take_and_die"})
    got = r.probe(P_DIE, r.adt("A01", "DIE1"))
    frames = r.frames(P_DIE)
    check("take_and_die reads the frame and closes with no answer", got == "CLOSED" and [f["ctl"] for f in frames] == ["DIE1"] and frames[0]["answer"] == "NONE", (got, frames))
    time.sleep(1)
    got = r.probe(P_DIE)
    check("and the port then refuses", got == "REFUSED", got)

    r.listener_up(P_HANG, {"mode": "hang"})
    got = r.probe(P_HANG, r.adt("A01", "HANG1"), wait=3)
    frames = r.frames(P_HANG)
    check("hang accepts and never answers", got == "TIMEOUT" and [f["answer"] for f in frames] == ["NONE"], (got, frames))

    data = r.result("HEX1").replace(b"SYNTH^", b"SYNTH\xe8^")
    r.listener_up(P_HEX, {"mode": "log_hex"})
    got = r.probe(P_HEX, data)
    frames = r.frames(P_HEX)
    check("log_hex writes the bytes", got.startswith("MSA|AA|HEX1") and frames and bytes.fromhex(frames[0].get("hex", "")) == data and frames[0]["high"] == "e8", (got, frames))

    for port in (P_UP, P_AE, P_AR, P_HANG, P_HEX):
        r.listener_down(port)
    got = r.probe(P_UP)
    check("a listener taken down refuses again", got == "REFUSED", got)


def install_read(r):
    step("What the install left")
    for ns, production in r.PRODUCTIONS.items():
        got = r.production(ns)
        check(f"{production} is up in {ns}", got == (production, "1"), got)
    got = r.production(r.SHUTTER)
    check("Shutter.Production is up", got == ("Shutter.Production", "1"), got)
    before = r.licence_units()
    seen = r.prove_sign_out()
    check("a REST session signs out: GET /me 200, then 401 on the same cookie", seen[:2] == (200, 401), seen)
    print(f"        licence units consumed: {before} before that sign-in, {seen[2]} after its sign-out", flush=True)


def routed(r):
    step("The routed production: the rule calls its function")
    for port in (r.LIMS, r.SECOND, r.ASIDE):
        r.listener_up(port, {"mode": "up"})
    calls = int(r.value(r.ROUTED, "$GET(^V11Rig.Calls)+0"))
    r.send(r.ROUTED_IN, r.adt("A01", "RT1"), "rt1")
    check("an unheld message reaches LIMS Out and Second Out", r.wait_until(lambda: "RT1" in r.heard(r.LIMS) and "RT1" in r.heard(r.SECOND), 60), (r.heard(r.LIMS), r.heard(r.SECOND)))
    after = int(r.value(r.ROUTED, "$GET(^V11Rig.Calls)+0"))
    check("the rule called the function", after == calls + 1, (calls, after))
    r.session(r.ROUTED, 'Set ^V11Rig.Hold("LIMS Out","MRNHELD1")=1')
    r.send(r.ROUTED_IN, r.adt("A03", "RT2", patient="MRNHELD1"), "rt2")
    check("the function's answer steers the message: aside and second", r.wait_until(lambda: "RT2" in r.heard(r.ASIDE) and "RT2" in r.heard(r.SECOND), 60), (r.heard(r.ASIDE), r.heard(r.SECOND)))
    time.sleep(3)
    check("and not LIMS Out", "RT2" not in r.heard(r.LIMS), r.heard(r.LIMS))
    r.session(r.ROUTED, 'Kill ^V11Rig.Hold')


def plain(r):
    step("The plain production: each pair passes a message")
    pairs = (("Retry Out", r.RETRY_IN, r.RETRY), ("NoRetry Out", r.NORETRY_IN, r.NORETRY), ("Bounded Out", r.BOUNDED_IN, r.BOUNDED), ("OneShot Out", r.ONESHOT_IN, r.ONESHOT))
    for item, service, port in pairs:
        r.listener_up(port, {"mode": "up"})
        control = "PL" + item.split()[0].upper()
        r.send(service, r.order(control), control)
        check(f"{item} delivers", r.wait_until(lambda: control in r.heard(port), 60), r.heard(port))
    step("The engine's readings the rig offers, on a stock failure")
    r.listener_down(r.NORETRY)
    r.wait_until(lambda: not r.listening(r.NORETRY), 10)
    r.send(r.NORETRY_IN, r.order("PLFAIL1"), "plfail1")
    def errored():
        return [h for h in r.headers(r.PLAIN, "NoRetry Out") if h["control"] == "PLFAIL1" and h["status"] == "Error"]
    check("headers reads a header's status and control id", r.wait_until(errored, 60), r.headers(r.PLAIN, "NoRetry Out"))
    rows = r.log_rows(r.PLAIN, "NoRetry Out", "ErrOutConnectExpired")
    check("log_rows reads the log's rows", bool(rows), r.log_rows(r.PLAIN, "NoRetry Out"))
    host = r.host(r.PLAIN, "NoRetry Out")
    check("host reads the engine's own row", bool(host.get("status")), host)
    print("        NoRetry Out:", json.dumps(host), "queue", r.queue(r.PLAIN, "NoRetry Out"), flush=True)
    r.set_item(r.PLAIN, "V11Rig.Plain", "Bounded Out", FailureTimeout=30)
    got = r.value(r.PLAIN, '##class(Ens.Director).GetItemSettingValue("V11Rig.Plain||Bounded Out","Host","FailureTimeout",.sc)')
    check("set_item changes a setting on the running production", got == "30", got)
    r.listener_up(r.NORETRY, {"mode": "up"})


def restarts(r):
    step("A stop and start, proven by the Gate's job number")
    jobs = r.jobs(r.SHUTTER)
    check("the Gate has a job to compare", bool(jobs.get("Gate")), jobs)
    try:
        r.restart_production(r.SHUTTER, "Shutter.Production", "Gate", stop_and_start=False)
        check("a stop and start that did not happen raises", False, "no exception")
    except RestartNotProven as e:
        check("a stop and start that did not happen raises, saying so", "did not happen" in str(e), e)
        print(f"        {e}", flush=True)
    cli = subprocess.run([sys.executable, os.path.join(HERE, "rig.py"), "restart", "--ctr", r.ctr, "--ns", r.SHUTTER, "--production", "Shutter.Production", "--watch", "Gate", "--no-stop-and-start"], capture_output=True, text=True)
    check("and fails the run: exit status 3, with the job named", cli.returncode == 3 and "did not happen" in cli.stderr, (cli.returncode, cli.stderr))
    print(f"        {cli.stderr.strip()}", flush=True)
    before, after = r.restart_production(r.SHUTTER, "Shutter.Production", "Gate")
    print(f"        Gate: job {before} before, job {after} after", flush=True)
    check("a real stop and start gives the Gate a new job", before != after, (before, after))
    check("and the production is up again", r.production(r.SHUTTER) == ("Shutter.Production", "1"), r.production(r.SHUTTER))
    before, after = r.restart_production(r.ROUTED, "V11Rig.Routed", "LIMS Out")
    print(f"        LIMS Out: job {before} before, job {after} after", flush=True)
    check("the same proof works on a site's production", before != after, (before, after))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--ctr", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--module", default="")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--reuse", action="store_true", help="keep a running container and what it has")
    args = ap.parse_args()
    r = Rig(args.ctr, args.port, args.image, args.module)
    try:
        if not args.reuse:
            step(f"A stock instance, {args.image}, Shutter and the site's productions")
            r.start()
            r.install()
        install_read(r)
        listener_modes(r)
        routed(r)
        plain(r)
        restarts(r)
    except RigBroken as e:
        print(f"\nRIG BROKEN: {e}", flush=True)
        return 3
    finally:
        if not args.keep:
            r.remove()
    print(f"\n{passed} passed, {len(failed)} failed" + (": " + "; ".join(failed) if failed else ""), flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
