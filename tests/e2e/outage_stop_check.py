#!/usr/bin/env python3
"""Shadow mode and Stop Shutter recovery hold an outage's resend (CONTRACTS 17.8 and 18), counted at a real receiver.

    python3 tests/e2e/outage_stop_check.py [--image IMAGE] [--port 52797] [--ctr outage-stop] [--keep] [--reuse] [--module core]

It builds the Pathology rig's instance (pathology_check.py's setup, a site install with no demo, which starts in shadow mode)
and plays one receiver, "Quillon O6 Out", with five results that never reached it. What it reads is what the rig reads: the
frames the fake receiver heard, and the routes' own answers.

  S  shadow mode: the set is offered, the approval answers 409 recovery_shadow, nothing is recorded, and the receiver hears
     nothing for 30 s;
  P  recovery enabled and stopped: the approval answers 409 recovery_stopped, nothing is recorded, "already handled by hand"
     still closes a message (it sends nothing), and the receiver hears nothing for 30 s;
  T  the stop cleared, one approval, and the stop set again while the receiver holds its answer to the first message: the
     receiver hears that one and nothing more for 40 s; the rest read not sent with halt recovery_stopped, the outage needs a
     person, and its card leads with the halt;
  R  the stop cleared and the set read again: a new approval sends the rest, each exactly once, in order, and never the one
     handled by hand.

It changes the instance and needs the docker CLI: a throwaway one only. Exit 0 when every check is ok, 1 when one fails, 3
when the rig itself fails. Run from the repository's root. Standard library only. pathology_check.py is read, never changed.
"""
import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pathology_check as pc  # noqa: E402

SVC, TARGET, RX = 7506, "Quillon O6 Out", 7406
results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}{'' if ok else ': ' + str(detail)[:900]}", flush=True)


def call(method, path, body=None):
    code, r = pc.api(method, path, body)
    if code == 401:
        pc.sign_in()
        code, r = pc.api(method, path, body)
    return code, r


def declare(mode):
    """The receiver as a site writes it, with duplicates unknown (so a message can be closed by hand), and recovery.mode."""
    _, current = pc.read_api("/site-profile")
    profile = current["profile"]
    entry = {"name": TARGET, "system": "Quillon Lab", "category": "orders_results", "tier": 3,
             "watch": {"namespace": pc.LAB, "item": TARGET}, "runbook": pc.TODO, "call": pc.WHO,
             "duplicates": {"behaviour": "unknown"}, "engine_resend": True}
    profile["receivers"] = [r for r in profile.get("receivers", []) if r.get("name") != TARGET] + [entry]
    profile["recovery"] = {"mode": mode}
    profile["expectedVersion"] = str(current["version"])
    code, answer = call("PUT", "/site-profile", profile)
    if not 200 <= code < 300:
        raise pc.RigBroken(f"the site profile refused the receiver: {code} {str(answer)[:400]}")


def outage():
    _, r = pc.read_api("/outages")
    for o in r.get("items", []):
        if o.get("receiver") == TARGET and o.get("state") != "closed":
            return o
    return None


def offered():
    o = outage()
    return [x.get("controlId") for x in ((o or {}).get("lists") or {}).get("offered", [])]


def wait_offered(want, seconds=pc.OFFER_WITHIN):
    end = time.time() + seconds
    while time.time() < end:
        if offered() == want:
            return True
        time.sleep(5)
    return False


def approve():
    o = outage()
    body = {"digest": (o.get("set") or {}).get("digest"), "version": o.get("version"), "note": "checked at the receiver with the duty desk", "receiverChecked": True}
    return call("POST", f"/outages/{o['id']}/approvals", body)


def runs(o):
    return [r for r in (o.get("resends") or []) if str(r.get("runId", "")).startswith("R")]


def control():
    _, c = pc.read_api("/recovery-control")
    return c


def stop(reason):
    code, c = call("POST", "/recovery-control/stop", {"reason": reason})
    if code != 200 or not c.get("stopped"):
        raise pc.RigBroken(f"the stop was not taken: {code} {str(c)[:300]}")


def clear(reason):
    c = control()
    code, r = call("POST", "/recovery-control/clear", {"reason": reason, "expectedGeneration": c.get("generation")})
    if code != 200 or r.get("stopped"):
        raise pc.RigBroken(f"the clear was not taken: {code} {str(r)[:300]}")


def play():
    ctl = [f"G{pc.tag}{i}" for i in range(1, 6)]

    pc.step("S: shadow mode, the set offered and the approval refused")
    declare("shadow")
    st = pc.fail_set(SVC, TARGET, {c: pc.result(c) for c in ctl})
    if not all(v == ["Error"] for v in st.values()):
        raise pc.RigBroken(f"the messages did not all fail: {st}")
    pc.rx_up(RX, {})
    check("S.a the five are offered in shadow mode", wait_offered(ctl), offered())
    check("S.b the mode reads shadow", control().get("mode") == "shadow", control())
    code, r = approve()
    check("S.c the approval answers 409 recovery_shadow, in words a person reads", code == 409 and r.get("error") == "recovery_shadow" and "nothing was recorded" in r.get("detail", ""), (code, r))
    o = outage()
    check("S.d nothing is recorded: still offered, no approval, no run", o.get("state") == "offered" and o.get("approval") is None and not runs(o), (o.get("state"), o.get("approval"), runs(o)))
    time.sleep(30)
    check("S.e the receiver hears nothing", pc.heard(RX, ctl) == [], pc.heard(RX, ctl))

    pc.step("P: recovery enabled and stopped")
    declare("enabled")
    stop("the laboratory asked us to hold every resend")
    check("P.a the control reads stopped", control().get("stopped") is True, control())
    if not wait_offered(ctl):
        raise pc.RigBroken(f"the set was not offered again after the profile was saved: {offered()}")
    code, r = approve()
    check("P.b the approval answers 409 recovery_stopped, in words a person reads", code == 409 and r.get("error") == "recovery_stopped" and "Shutter recovery is stopped" in r.get("detail", ""), (code, r))
    o = outage()
    check("P.c nothing is recorded: still offered, no approval, no run", o.get("state") == "offered" and o.get("approval") is None and not runs(o), (o.get("state"), o.get("approval"), runs(o)))
    last = [x for x in o["lists"]["offered"] if x.get("controlId") == ctl[4]][0]
    code, r = call("POST", f"/outages/{o['id']}/acts", {"act": "handled_by_hand", "headerId": last["headerId"], "note": "entered at the receiver by the duty desk", "version": o.get("version")})
    by_hand = [x for x in (r.get("resends") or []) if str(x.get("runId", "")).startswith("H")] if isinstance(r, dict) else []
    check("P.d already handled by hand still goes under the stop, and sends nothing", code == 200 and len(by_hand) == 1 and by_hand[0].get("closure") == "handled_by_hand", (code, str(r)[:300]))
    time.sleep(30)
    check("P.e the receiver hears nothing", pc.heard(RX, ctl) == [], pc.heard(RX, ctl))

    pc.step("T: the stop cleared, one approval, and the stop set again between two messages")
    clear("the laboratory is ready")
    pc.rx_spec(RX, {"delay": 8})  # the receiver holds its answer to each frame for 8 s: the stop lands inside the first
    if not wait_offered(ctl[:4]):
        raise pc.RigBroken(f"the four left were not offered: {offered()}")
    code, r = approve()
    check("T.a the approval goes once the stop is cleared", code == 200 and r.get("state") == "sending", (code, str(r)[:300]))
    end = time.time() + 180
    while time.time() < end and not pc.heard(RX, ctl):
        time.sleep(0.5)
    first = pc.heard(RX, ctl)
    stop("stopped while the receiver held its answer to the first message")
    time.sleep(40)
    h = pc.heard(RX, ctl)
    check("T.b the receiver heard the first message and nothing after the stop", first == ctl[:1] and h == ctl[:1], (first, h))
    o = outage()
    rows = runs(o)
    states = [(x.get("controlId"), x.get("state"), x.get("closure"), x.get("halt")) for x in rows]
    want = [(ctl[0], "completed", "sent", None)] + [(c, "stopped", None, "recovery_stopped") for c in ctl[1:4]]
    check("T.c the first sent, the rest not sent with halt recovery_stopped", states == want, states)
    check("T.d each message not sent says the stop halted it", all("Shutter recovery was stopped by" in (x.get("words") or "") and "so the run halted before this message" in (x.get("words") or "") for x in rows[1:]), [x.get("words") for x in rows])
    first_line = (o.get("words") or {}).get("first", "")
    check("T.e the outage needs a person, and its card leads with the halt", o.get("state") == "needs_person" and first_line.startswith("The resend halted because Shutter recovery was stopped: 1 of 4 messages were sent and 3 not sent."), (o.get("state"), first_line[:300]))

    pc.step("R: a new approval, once the stop is cleared, sends the rest")
    clear("the laboratory is ready again")
    pc.rx_spec(RX, {})
    code, r = call("POST", f"/outages/{o['id']}/acts", {"act": "read_again"})
    if code != 200:
        raise pc.RigBroken(f"read_again was refused: {code} {str(r)[:300]}")
    check("R.a the rest are offered again, and only they", wait_offered(ctl[1:4]), offered())
    code, r = approve()
    check("R.b the new approval goes", code == 200, (code, str(r)[:300]))
    pc.wait_until(lambda: len(pc.heard(RX, ctl)) >= 4, 120, 2)
    time.sleep(20)
    ok, why = pc.exactly_once_in_order(pc.heard(RX, ctl), ctl[:4])
    check("R.c each reached the receiver exactly once, in order, and the one handled by hand never", ok and ctl[4] not in pc.heard(RX, ctl), (why, pc.heard(RX, ctl)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--image", default="irishealth-community:2026.3.0AI.154.0")
    ap.add_argument("--port", type=int, default=52797)
    ap.add_argument("--ctr", default="outage-stop")
    ap.add_argument("--module", default="")
    ap.add_argument("--reuse", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(HERE)))
    args = ap.parse_args()
    pc.CTR = args.ctr
    code = 0
    try:
        pc.setup(args, args.repo)
        play()
    except pc.RigBroken as e:
        print(f"\nTHE RIG FAILED, which says nothing about the product: {e}")
        code = 3
    finally:
        try:
            pc.rx_down_if_up(RX)
        except Exception:
            pass
        if not args.keep and not args.reuse:
            pc.subprocess.run(["docker", "rm", "-f", args.ctr], capture_output=True)
    failed = [n for n, ok in results if not ok]
    print(f"\n{len(results) - len(failed)} ok, {len(failed)} failed")
    if code:
        return code
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
