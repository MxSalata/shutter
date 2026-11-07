#!/usr/bin/env python3
"""The Case Releaser's third pass, on the rig: a case blocked while the engine tries its message, at a stock HL7 TCP operation, and
what each sweep does with it from what the engine shows, with nobody reopening the case. Every plan comes through real intake. No
model is called.

    python3 tests/e2e/v11_rig/releaser/check_releaser.py --ctr NAME --port PORT --image IMAGE [--module core] [--reuse] [--keep] [--only a,b]

Run from a copy of the tree. Exit status: 0 all ok; 1 a check failed; 3 the rig broke. Every name and answer is made up.
"""
import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "gate"))
from rig import RigBroken, Rig  # noqa: E402
from check_gate import REFUSES_E, Site  # noqa: E402

STOCK = ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C"
SWEEP = 45
failed, passed = [], 0


def check(name, ok, detail=""):
    global passed
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {str(detail)[:1500]}"), flush=True)
    if ok:
        passed += 1
    else:
        failed.append(name)


def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


def fresh_bed(r, control):
    """A bed of its own: an earlier scene's admission can hold the rig's usual one."""
    bed = f"{sum(map(ord, control)) % 90 + 10}"
    return r.adt("A01", control).replace(b"BAY1^01", f"BAY8^{bed}".encode())


def waiting_case(s, ns, item, service, port, tag):
    """A message the engine is still trying, its case blocked on the engine: (control, case id), or (control, None)."""
    r = s.r
    s.drain(ns, item, port)
    control = f"{tag}{int(time.time()) % 10000}"
    r.send(service, fresh_bed(r, control), control)
    case_id = s.case_of(control, item=item)
    check(f"{tag}: a case opens", bool(case_id))
    if not case_id:
        return control, None
    c, words = s.read(case_id)
    print("        ", json.dumps({k: c.get(k) for k in ("state", "failureKind", "waitsOnEngine", "headline")})[:400], flush=True)
    check(f"{tag}: blocked, waiting on the engine", c.get("state") == "blocked" and (c.get("waitsOnEngine") or "").startswith(ns + ":"), (c.get("state"), c.get("waitsOnEngine"), words[:500]))
    return control, case_id


def moved(s, case_id, wanted, seconds=SWEEP):
    """The case once wanted(case) holds, or as it is when the time runs out. Nobody reopens it."""
    end = time.time() + seconds
    while True:
        c, words = s.read(case_id)
        if wanted(c) or time.time() > end:
            return c, words
        time.sleep(1)


def delivered_by_itself(s, ns, item, service, port, tag, ack_level, words):
    """Waits; the listener returns; the next sweep resolves it, in the words of the receiver's declared level."""
    r = s.r
    step(f"{tag}: declared {ack_level or 'nothing'}, the engine delivers by itself")
    s.profile([item], **({"ack_level": ack_level} if ack_level else {}))
    control, case_id = waiting_case(s, ns, item, service, port, tag)
    if not case_id:
        return
    time.sleep(10)
    c, _ = s.read(case_id)
    check(f"{tag}: sweeps go by, and it stays waiting: the header reads Delivered", c.get("state") == "blocked" and bool(c.get("waitsOnEngine")), c.get("state"))
    r.listener_up(port, {"mode": "up"})
    c, ev = moved(s, case_id, lambda x: x.get("state") == "resolved", 90)
    print("        ", json.dumps({k: c.get(k) for k in ("state", "outcome", "headline", "disposition", "waitsOnEngine")})[:500], flush=True)
    check(f"{tag}: resolved by the sweep, with nobody reopening it", c.get("state") == "resolved", (c.get("state"), c.get("headline"), ev[-500:]))
    check(f"{tag}: Outcome is the shared sentence", "Delivered by the engine" in (c.get("outcome") or "") and words in (c.get("outcome") or "") and "nothing was resent by Shutter" in (c.get("outcome") or ""), c.get("outcome"))
    check(f"{tag}: the plan's disposition kept", c.get("disposition") == "resend", c.get("disposition"))
    check(f"{tag}: the marker cleared", not c.get("waitsOnEngine"), c.get("waitsOnEngine"))
    whole = json.dumps(c) + ev
    check(f"{tag}: 'Verified' appears nowhere on the case", "Verified" not in whole, whole[:600])
    check(f"{tag}: one frame", r.heard(port).count(control) == 1, r.heard(port))
    check(f"{tag}: no API write", not s.receiver_holds(control))
    r.listener_down(port)
    s.profile([item])


def not_established(s, ns, production, item, service, port, tag):
    """Declared application, the item completing a refusal: Completed is no acceptance, so the sweep clears the marker and a person has it."""
    r = s.r
    step(f"{tag}: declared application, the item carrying :?E=C, the engine completes a refusal")
    s.profile([item], ack_level="application")
    control, case_id = waiting_case(s, ns, item, service, port, tag)
    if case_id:
        r.set_item(ns, production, item, ReplyCodeActions=REFUSES_E)
        r.listener_up(port, {"mode": "answer", "code": "AE", "words": "A made-up refusal"})
        c, _ = moved(s, case_id, lambda x: not x.get("waitsOnEngine"), 90)
        print("        ", json.dumps({k: c.get(k) for k in ("state", "outcome", "headline", "waitsOnEngine")})[:500], flush=True)
        check(f"{tag}: the marker clears, blocked for a person, not resolved", c.get("state") == "blocked" and not c.get("waitsOnEngine"), (c.get("state"), c.get("waitsOnEngine")))
        check(f"{tag}: the words say acceptance isn't established, the pattern printed", "Receiver acceptance has not been established." in (c.get("outcome") or "") and ":?E=C" in (c.get("outcome") or ""), c.get("outcome"))
        check(f"{tag}: never a write", not s.receiver_holds(control))
        time.sleep(12)
        c, _ = s.read(case_id)
        check(f"{tag}: and the sweep leaves it there", c.get("state") == "blocked", c.get("state"))
        r.listener_down(port)
    r.set_item(ns, production, item, ReplyCodeActions=STOCK)
    s.profile([item])


def ack_case(s, ns, item, service, port, tag):
    """A case from the application-ACK feed, marked by a wait: a Completed header says nothing of the application's refusal."""
    r = s.r
    step(f"{tag}: an ack_ case whose marked header completes")
    _, case_id = waiting_case(s, ns, item, service, port, tag)
    if not case_id:
        return
    out = r.session(r.SHUTTER, f'Set c=##class(Shutter.Store.Case).ByCaseId("{case_id}") Set c.FailureReasonCode="ack_AE" Write !,"[set] ",c.%Save(),!')
    check(f"{tag}: the case reads as the feed's", "[set] 1" in out, out[-300:])
    r.listener_up(port, {"mode": "up"})
    c, ev = moved(s, case_id, lambda x: not x.get("waitsOnEngine"), 90)
    time.sleep(3)
    c, ev = s.settled(case_id)
    print("        ", json.dumps({k: c.get(k) for k in ("state", "outcome", "headline", "waitsOnEngine")})[:500], flush=True)
    check(f"{tag}: the marker clears, and it isn't resolved by the header", not c.get("waitsOnEngine") and "Delivered by the engine" not in (c.get("outcome") or "") and c.get("state") != "resolved", (c.get("state"), c.get("outcome"), c.get("waitsOnEngine")))
    check(f"{tag}: it is planned again on fresh evidence", "the engine has finished with header" in ev, ev[-500:])
    r.listener_down(port)


def settled_bounded(s, ns, item, service, port, tag):
    """FailureTimeout 25, nothing listening: the engine gives up with every attempt never opened, and the sweep plans it again."""
    r = s.r
    step(f"{tag}: bounded retry runs out, nothing ever listening")
    control, case_id = waiting_case(s, ns, item, service, port, tag)
    if not case_id:
        return
    c, ev = moved(s, case_id, lambda x: x.get("state") == "awaiting_approval" or (not x.get("waitsOnEngine") and x.get("state") != "blocked"), 120)
    print("        ", json.dumps({k: c.get(k) for k in ("state", "headline", "waitsOnEngine")})[:400], flush=True)
    print("         the header:", [h for h in r.headers(ns, item) if h["control"] == control], flush=True)
    check(f"{tag}: the sweep plans it again, and it reaches a person's approval", c.get("state") == "awaiting_approval" and not c.get("waitsOnEngine"), (c.get("state"), c.get("waitsOnEngine"), ev[-500:]))
    check(f"{tag}: reopened by the sweep's words", "the engine has finished with header" in ev, ev[-500:])
    check(f"{tag}: nothing written", not s.receiver_holds(control))


def settled_may_hold(s, ns, item, service, port, tag):
    """FailureTimeout 25, a listener that takes the frame and dies: Error after a reached attempt, so the re-plan stops for a person."""
    r = s.r
    step(f"{tag}: bounded retry runs out after the receiver took the frame")
    control, case_id = waiting_case(s, ns, item, service, port, tag)
    if not case_id:
        return
    r.listener_up(port, {"mode": "take_and_die"})
    c, ev = moved(s, case_id, lambda x: not x.get("waitsOnEngine") and "own screen" in (x.get("headline") or ""), 120)
    print("        ", json.dumps({k: c.get(k) for k in ("state", "headline", "waitsOnEngine")})[:400], flush=True)
    print("         the header:", [h for h in r.headers(ns, item) if h["control"] == control], flush=True)
    check(f"{tag}: re-planned, blocked RECEIVER_MAY_HOLD_IT", c.get("state") == "blocked" and "RECEIVER_MAY_HOLD_IT" in ev, (c.get("state"), c.get("headline"), ev[-500:]))
    check(f"{tag}: no write", not s.receiver_holds(control))
    check(f"{tag}: one frame", r.heard(port).count(control) == 1, r.heard(port))
    if r.listening(port):
        r.listener_down(port)


def first_look_race(s, ns, item, service, port, tag):
    """FailureTimeout 0: if the case's first look finds the header still Delivered it waits, and a sweep plans it again. Either way it
    reaches a person's approval with nobody reopening it."""
    r = s.r
    step(f"{tag}: FailureTimeout 0, nothing listening, the first look's race")
    s.drain(ns, item, port)
    control = f"{tag}{int(time.time()) % 10000}"
    r.send(service, fresh_bed(r, control), control)
    case_id = s.case_of(control, item=item)
    check(f"{tag}: a case opens", bool(case_id))
    if not case_id:
        return
    c, ev = moved(s, case_id, lambda x: x.get("state") == "awaiting_approval", 60)
    print("         waited on the first look:", "the engine has finished with header" in ev, flush=True)
    check(f"{tag}: it reaches a person's approval", c.get("state") == "awaiting_approval" and not c.get("waitsOnEngine"), (c.get("state"), c.get("waitsOnEngine"), c.get("headline")))


def unreadable(s, ns, production, item, service, port, tag):
    """The source production stops under a waiting case: nothing can be read, so it is left, and counted in what the Doctor prints."""
    r = s.r
    step(f"{tag}: the source production stops under a waiting case")
    control, case_id = waiting_case(s, ns, item, service, port, tag)
    if not case_id:
        return
    r.asked_until_done(ns, "StopProduction(60,1)", "stop")
    sweep = {}
    end = time.time() + SWEEP
    while time.time() < end:
        sweep = r.obj(r.SHUTTER, "##class(Shutter.Setup).Doctor(1)").get("release_sweep", {})
        if sweep.get("engine_unreadable", 0) >= 1:
            break
        time.sleep(5)
    print("         release_sweep:", json.dumps(sweep)[:500], flush=True)
    check(f"{tag}: the Doctor's release_sweep counts it", sweep.get("engine_unreadable", 0) >= 1, sweep)
    check(f"{tag}: and the candidates name it", sweep.get("candidates", {}).get("engine", 0) >= 1, sweep)
    c, _ = s.read(case_id)
    check(f"{tag}: the case is left as it was", c.get("state") == "blocked" and bool(c.get("waitsOnEngine")), (c.get("state"), c.get("waitsOnEngine")))
    r.listener_up(port, {"mode": "up"})
    r.asked_until_done(ns, f'StartProduction("{production}")', "start")
    c, _ = moved(s, case_id, lambda x: x.get("state") == "resolved", 120)
    print("        ", json.dumps({k: c.get(k) for k in ("state", "outcome", "waitsOnEngine")})[:400], flush=True)
    check(f"{tag}: back up, the engine delivers it and the sweep resolves it", c.get("state") == "resolved", (c.get("state"), c.get("headline")))
    check(f"{tag}: one frame", r.heard(port).count(control) == 1, r.heard(port))
    time.sleep(8)
    sweep = r.obj(r.SHUTTER, "##class(Shutter.Setup).Doctor(1)").get("release_sweep", {})
    check(f"{tag}: and the count falls back to none", sweep.get("engine_unreadable") == 0, sweep)
    r.listener_down(port)


SCENES = ("connection", "none", "application", "commit", "not_established", "ack", "routed", "bounded", "may_hold", "race", "unreadable")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ctr", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--module", default="")
    ap.add_argument("--reuse", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--only", default=",".join(SCENES))
    args = ap.parse_args()
    only = args.only.split(",")
    r = Rig(args.ctr, args.port, args.image, args.module)
    s = Site(r)
    try:
        if not args.reuse:
            step("A fresh instance, Shutter without the demo, the rig's productions")
            r.start()
            r.install()
            s.beds()
            names = ["Retry Out", "NoRetry Out", "Bounded Out", "LIMS Out"]
            s.profile(names)
            for name in names:
                s.connector(name)
            print("  restarted:", r.restart_production(r.SHUTTER, "Shutter.Production", "Case Releaser"), flush=True)
        plain = (s, r.PLAIN, "Retry Out", r.RETRY_IN, r.RETRY)
        if "connection" in only:
            delivered_by_itself(*plain, "CN", "connection", "accepted on the connection")
        if "none" in only:
            delivered_by_itself(*plain, "ND", "", "accepted on the connection")
        if "application" in only:
            delivered_by_itself(*plain, "AP", "application", "accepted by the receiver's application (its ACK), as declared in the site profile")
        if "commit" in only:
            delivered_by_itself(*plain, "CM", "commit", "accepted by the receiver's transport; processing not confirmed")
        # A receiver's fifth failure in a few minutes joins an incident instead of waiting alone, so no receiver takes more than four here.
        routed = (s, r.ROUTED, "LIMS Out", r.ROUTED_IN, r.LIMS)
        if not r.listening(r.SECOND):
            r.listener_up(r.SECOND, {"mode": "up"})
        if "routed" in only:
            delivered_by_itself(*routed, "RT", "", "accepted on the connection")
        if "not_established" in only:
            not_established(s, r.ROUTED, "V11Rig.Routed", "LIMS Out", r.ROUTED_IN, r.LIMS, "NE")
        if "ack" in only:
            ack_case(*routed, "AK")
        if "bounded" in only:
            settled_bounded(s, r.PLAIN, "Bounded Out", r.BOUNDED_IN, r.BOUNDED, "BD")
        if "may_hold" in only:
            settled_may_hold(s, r.PLAIN, "Bounded Out", r.BOUNDED_IN, r.BOUNDED, "BH")
        if "race" in only:
            first_look_race(s, r.PLAIN, "NoRetry Out", r.NORETRY_IN, r.NORETRY, "FR")
        if "unreadable" in only:
            unreadable(s, r.ROUTED, "V11Rig.Routed", "LIMS Out", r.ROUTED_IN, r.LIMS, "UR")
    except RigBroken as e:
        print(f"RIG BROKEN: {e}", flush=True)
        return 3
    finally:
        try:
            s.sign_out()
        except (OSError, ValueError):
            pass
        if not args.keep:
            r.remove()
    print(f"\n{passed} ok, {len(failed)} failed: {failed}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
