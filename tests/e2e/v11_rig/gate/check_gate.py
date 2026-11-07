#!/usr/bin/env python3
"""The gate's check of the engine's hands, on the rig: a stock HL7 TCP operation with a receiver that has an API too, so one
approval could deliver a message by both routes. Every plan comes through real intake. No model is called.

    python3 tests/e2e/v11_rig/gate/check_gate.py --ctr NAME --port PORT --image IMAGE [--module core] [--reuse] [--keep]
                                                 [--before FILE] [--only a,b]

--before names a Gate.cls without the check (the tree's previous one): the double delivery is then run on it first, and the
tree's Gate.cls goes back with a stop and start proven by job number. Run from a copy of the tree. Exit status: 0 all ok; 1 a check
failed; 3 the rig broke. Every name and answer is made up.
"""
import argparse
import base64
import http.cookiejar
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from rig import PW, HOME, Rig, RigBroken  # noqa: E402

API = {"base": "/beds/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}", "capabilities": "/capabilities", "operations": "/operations"}
FEATURES = {"conditional_writes": True, "receipts": True, "history": True, "dry_run": True}
REFUSES_E = ":?E=C,:?R=RF,:~=S,:?A=C,:*=S"
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


class Site:
    """One sign-in for the whole run, of Shutter's API and of the receiver's: a Community instance holds a licence unit for a while
    after each session, so signing in for every read runs it out and a terminal session is refused."""

    def __init__(self, r):
        self.r = r
        self.client = None
        self.beds_opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def api(self):
        if self.client is None:
            self.client = self.r.api()
            self.client.sign_in()
        return self.client

    def sign_out(self):
        if self.client is not None:
            self.client.sign_out()
            self.client = None

    def beds(self):
        """The receiver's API, in its own namespace, as a person would give it one."""
        r = self.r
        r.session(r.SHUTTER, 'Write ##class(Shutter.Setup).CreateNamespace("BEDS")')
        out = r.session("BEDS", f'''Set sc=$SYSTEM.OBJ.LoadDir("{HOME}/pkg/src/Downstream/","ck-d",,1) Write !,"[beds] ",sc,!
Set sc=##class(Downstream.Installer).Install(0) Write !,"[beds] ",sc,!
Set $NAMESPACE="%SYS"
Set sc=##class(Security.Roles).Create("Beds_Client","The receiver's API client","Downstream_API:U,%DB_BEDS:RW") Write !,"[beds] ",sc,!
Set sc=##class(Security.Users).Create("beds-client","Beds_Client","{PW}","The receiver's API client","BEDS","","",0,1) Write !,"[beds] ",sc,!
Kill a Set a("NameSpace")="BEDS",a("Description")="A receiver's API",a("Enabled")=1,a("AutheEnabled")=32,a("DispatchClass")="Downstream.API",a("Resource")="Downstream_API",a("UseCookies")=2,a("CookiePath")="/beds/api/"
Set sc=##class(Security.Applications).Create("/beds/api",.a) Write !,"[beds] ",sc,!''')
        print("  the receiver's API:", out.count("[beds] 1"), "of 5 steps ok", flush=True)
        r.session(r.SHUTTER, f'Do ##class(Ens.Config.Credentials).SetCredential("DownstreamAPI","beds-client","{PW}",1)')

    def profile(self, names, **extra):
        """Fills these receivers in as a person would, tier 2 on approval, each with an API; extra goes on every one."""
        a = self.api()
        code, prof = a.get("/site-profile")
        if code != 200:
            raise RigBroken(f"the profile did not read: {code}")
        body = prof["profile"]
        kept = [x for x in body.get("receivers", []) if x["name"] not in names]
        for name in names:
            kept.append(dict({"name": name, "system": "a made-up receiver", "category": "current_state", "tier": 2, "applies": "arrival_order", "resend_timestamp": "original", "cancels": False, "merges": False, "api": API, "features": FEATURES}, **extra))
        body["receivers"] = kept
        body["policy"]["2"]["single"] = "approval"
        body["expectedVersion"] = prof["version"]
        code, saved = a.call("PUT", "/site-profile", body)
        if code != 200:
            raise RigBroken(f"the profile was refused: {code} {str(saved)[:500]}")

    def connector(self, name):
        got = self.r.obj(self.r.SHUTTER, f'##class(Shutter.Setup).OnboardReceiverItem("{name}","127.0.0.1","52773","DownstreamAPI")')
        if not got.get("ok"):
            raise RigBroken(f"no connector for {name}: {got}")

    def case_of(self, control, seconds=120, item=""):
        """The case for this message, at this receiver if named, once it has stopped moving, or None."""
        enc = f"ENC-{control}"
        end = time.time() + seconds
        a = self.api()
        while time.time() < end:
            _, got = a.get("/cases?limit=500")
            for c in (got.get("items", []) if isinstance(got, dict) else []):
                if c.get("encounterId") == enc and (not item or c.get("receiver") == item) and c.get("state") in ("awaiting_approval", "blocked", "escalated", "resolved", "failed"):
                    return c["caseId"]
            time.sleep(2)
        return None

    def read(self, case_id):
        a = self.api()
        _, c = a.get(f"/cases/{case_id}")
        _, ev = a.get(f"/cases/{case_id}/events")
        _, why = a.get(f"/cases/{case_id}/blocked-reason")
        return c, json.dumps(ev) + json.dumps(why)

    def settled(self, case_id, seconds=120, away_from=()):
        end = time.time() + seconds
        while time.time() < end:
            c, words = self.read(case_id)
            if c.get("state") in ("awaiting_approval", "blocked", "escalated", "resolved", "failed") and c.get("state") not in away_from:
                return c, words
            time.sleep(2)
        return self.read(case_id)

    def receiver_holds(self, control):
        """Whether the API holds this encounter, which is a write by Shutter since the engine can't reach it."""
        req = urllib.request.Request(f"http://127.0.0.1:{self.r.port}/beds/api/encounters/ENC-{control}", headers={"Authorization": "Basic " + base64.b64encode(f"beds-client:{PW}".encode()).decode()})
        try:
            with self.beds_opener.open(req, timeout=30) as resp:
                return resp.status == 200
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return False
            raise RigBroken(f"the API read {e.code}") from e

    def approve(self, case_id):
        a = self.api()
        _, c = a.get(f"/cases/{case_id}")
        _, pl = a.get(f"/cases/{case_id}/plan")
        return a.post(f"/cases/{case_id}/approvals", {"decision": "approve", "planDigest": pl["plan"]["digest"], "expectedVersion": c.get("version", 0)})[0]

    def reopen(self, case_id):
        return self.api().post(f"/cases/{case_id}/reinvestigate", {"reason": "a person looks again"})[0]

    def drain(self, ns, item, port):
        r = self.r
        if not r.listening(port):
            r.listener_up(port, {"mode": "up"})
        r.listener_spec(port, {"mode": "up"})
        r.wait_until(lambda: r.queue(ns, item) == 0, 60)
        time.sleep(3)
        r.listener_down(port)
        time.sleep(4)


def still_trying_then_delivered(s, ns, item, service, port, tag, also_up=0):
    """Engine and approval both on one message: refused while the engine tries, one frame when the listener returns, then a re-plan
    that sees the delivery."""
    r = s.r
    step(f"{tag}: {item}, retrying for ever, nothing listening, the receiver's API up")
    s.drain(ns, item, port)
    if also_up and not r.listening(also_up):
        r.listener_up(also_up, {"mode": "up"})
    control = f"{tag}{int(time.time()) % 10000}"
    r.send(service, r.adt("A01", control), control)
    case_id = s.case_of(control, item=item)
    check(f"{tag}: a case opens", bool(case_id))
    if not case_id:
        return
    c, words = s.read(case_id)
    print("        ", json.dumps({k: c.get(k) for k in ("state", "failureKind", "originHeaderId", "waitsOnEngine", "headline", "receiver")})[:500], flush=True)
    print("        headers to the item:", r.headers(ns, item)[-2:], flush=True)
    check(f"{tag}: refused ENGINE_STILL_TRYING", "ENGINE_STILL_TRYING" in words, words[:800])
    check(f"{tag}: the case is blocked", c.get("state") == "blocked", c.get("state"))
    check(f"{tag}: headline 'Waiting for the engine'", (c.get("headline") or "").startswith("Waiting for the engine"), c.get("headline"))
    check(f"{tag}: WaitsOnEngine is set", (c.get("waitsOnEngine") or "").startswith(ns + ":"), c.get("waitsOnEngine"))
    check(f"{tag}: nothing written through the API", not s.receiver_holds(control))
    r.listener_up(port, {"mode": "up"})
    r.wait_until(lambda: control in r.heard(port), 60)
    time.sleep(8)
    check(f"{tag}: exactly one frame at the listener when it returns", r.heard(port).count(control) == 1, r.heard(port))
    check(f"{tag}: and the API holds nothing", not s.receiver_holds(control))
    code = s.reopen(case_id)
    time.sleep(3)
    c, words = s.settled(case_id, away_from=("blocked",))
    check(f"{tag}: the re-plan is blocked ENGINE_DELIVERED", "ENGINE_DELIVERED" in words, (code, words[-800:]))
    check(f"{tag}: and the case resolved", c.get("state") == "resolved", (c.get("state"), c.get("headline")))
    check(f"{tag}: Outcome is the engine's words", "accepted on the connection; nothing was resent by Shutter" in (c.get("outcome") or ""), c.get("outcome"))
    check(f"{tag}: never 'a person must decide'", "a person must decide" not in json.dumps(c), c.get("headline"))
    check(f"{tag}: the plan's disposition kept", c.get("disposition") == "resend", c.get("disposition"))
    check(f"{tag}: a person's reopen left WaitsOnEngine empty", not c.get("waitsOnEngine"), c.get("waitsOnEngine"))
    check(f"{tag}: still one frame", r.heard(port).count(control) == 1, r.heard(port))
    r.listener_down(port)


def older_case(s, ns, item, service, port, second, tag):
    """A routed production, where the first header of a session is the service's and the delivery header is another: a case that
    still carries the first as its origin, as a case opened before the alert route preferred the delivery header does."""
    r = s.r
    step(f"{tag}: the origin header is the service's, not the delivery header")
    s.drain(ns, item, port)
    if not r.listening(second):
        r.listener_up(second, {"mode": "up"})
    control = f"{tag}01"
    r.send(service, r.adt("A01", control), control)
    case_id = s.case_of(control, item=item)
    check(f"{tag}: a case opens", bool(case_id))
    if not case_id:
        return
    delivery = [h["id"] for h in r.headers(ns, item) if h["control"] == control][0]
    first = r.read_rows(ns, f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 1 ID FROM Ens.MessageHeader WHERE SessionId=(SELECT SessionId FROM Ens.MessageHeader WHERE ID={delivery}) ORDER BY ID") While rs.%Next() {{ Write !,"<<<",rs.%Get("ID"),">>>",! }}""")[0]
    check(f"{tag}: the origin and the delivery header differ", first != delivery, (first, delivery))
    r.session(r.SHUTTER, f"""Set c=##class(Shutter.Store.Case).ByCaseId("{case_id}") Set c.OriginHeaderId="{first}" Write !,c.%Save(),!""")
    s.reopen(case_id)
    time.sleep(3)
    s.settled(case_id, away_from=("awaiting_approval",))
    c, words = s.settled(case_id)
    check(f"{tag}: read on the delivery header: still trying", c.get("waitsOnEngine") == f"{ns}:{delivery}", (c.get("waitsOnEngine"), c.get("headline"), words[-400:]))
    r.listener_up(port, {"mode": "up"})
    r.wait_until(lambda: control in r.heard(port), 60)
    time.sleep(6)
    s.reopen(case_id)
    time.sleep(3)
    c, words = s.settled(case_id, away_from=("blocked",))
    check(f"{tag}: and then delivered, resolved", c.get("state") == "resolved" and f"(header {delivery})" in (c.get("outcome") or ""), (c.get("state"), c.get("outcome")))
    check(f"{tag}: one frame", r.heard(port).count(control) == 1, r.heard(port))
    r.listener_down(port)


def delivers_twice_before(s, ns, item, service, port, tag):
    """The measured double delivery, on a Gate.cls with no check."""
    r = s.r
    step(f"{tag}, before: {item}, retrying for ever, the check not in the gate")
    s.drain(ns, item, port)
    control = f"{tag}01"
    r.send(service, r.adt("A01", control), control)
    case_id = s.case_of(control)
    check(f"{tag} before: a case opens", bool(case_id))
    if not case_id:
        return
    c, _ = s.read(case_id)
    check(f"{tag} before: it waits for an approval", c.get("state") == "awaiting_approval", (c.get("state"), c.get("headline")))
    print("         approve:", s.approve(case_id), flush=True)
    c, _ = s.settled(case_id, away_from=("awaiting_approval",))
    check(f"{tag} before: approved, the API holds it", s.receiver_holds(control), (c.get("state"), c.get("headline")))
    r.listener_up(port, {"mode": "up"})
    r.wait_until(lambda: control in r.heard(port), 60)
    time.sleep(5)
    check(f"{tag} before: and the engine delivers it too: both routes", r.heard(port).count(control) == 1 and s.receiver_holds(control), r.heard(port))
    r.listener_down(port)


def delayed(s, ns, item, service, port, tag):
    """K1's delayed form: the alert raised, the listener returns, the engine delivers, and only then does the intake open the case."""
    r = s.r
    step(f"{tag}: the case opens after the engine delivered")
    s.drain(ns, item, port)
    r.session(ns, 'Set sc=##class(Ens.Director).EnableConfigItem("Shutter Forwarder",0,1) Write !,sc,!')
    control = f"{tag}01"
    r.send(service, r.adt("A01", control), control)
    r.wait_until(lambda: len([x for x in r.log_rows(ns, item, "ErrOutConnect")]) > 0, 30)
    time.sleep(12)
    r.listener_up(port, {"mode": "up"})
    r.wait_until(lambda: control in r.heard(port), 60)
    time.sleep(3)
    print("         before the case:", [h for h in r.headers(ns, item) if h["control"] == control], flush=True)
    r.session(ns, 'Set sc=##class(Ens.Director).EnableConfigItem("Shutter Forwarder",1,1) Write !,sc,!')
    case_id = s.case_of(control, 180)
    check(f"{tag}: the case opens", bool(case_id))
    if not case_id:
        r.listener_down(port)
        return
    c, words = s.read(case_id)
    check(f"{tag}: blocked ENGINE_DELIVERED", "ENGINE_DELIVERED" in words, words[:800])
    check(f"{tag}: and resolved with Outcome written", c.get("state") == "resolved" and "nothing was resent by Shutter" in (c.get("outcome") or ""), (c.get("state"), c.get("outcome")))
    check(f"{tag}: no API write", not s.receiver_holds(control))
    check(f"{tag}: one frame", r.heard(port).count(control) == 1, r.heard(port))
    r.listener_down(port)


def not_established(s, ns, production, item, service, port, tag):
    """A receiver declared application whose item completes a refusal: Completed is no acceptance, so a person keeps the case."""
    r = s.r
    step(f"{tag}: declared application, the item carrying :?E=C")
    s.drain(ns, item, port)
    s.profile([item], ack_level="application")
    control = f"{tag}01"
    r.send(service, r.adt("A01", control), control)
    case_id = s.case_of(control)
    check(f"{tag}: a case opens, waiting", bool(case_id))
    if not case_id:
        return
    r.set_item(ns, production, item, ReplyCodeActions=REFUSES_E)
    r.listener_up(port, {"mode": "answer", "code": "AE", "words": "A made-up refusal"})
    r.wait_until(lambda: control in r.heard(port), 60)
    time.sleep(8)
    print("         the header:", [h for h in r.headers(ns, item) if h["control"] == control], flush=True)
    s.reopen(case_id)
    time.sleep(3)
    c, words = s.settled(case_id, away_from=("awaiting_approval",))
    check(f"{tag}: blocked, not resolved", c.get("state") == "blocked" and "ENGINE_DELIVERED" in words, (c.get("state"), words[-600:]))
    check(f"{tag}: Outcome says acceptance isn't established", "IRIS marked this delivery Completed. Receiver acceptance has not been established." in (c.get("outcome") or ""), c.get("outcome"))
    check(f"{tag}: with the pattern printed", ":?E=C" in (c.get("outcome") or ""), c.get("outcome"))
    r.listener_down(port)
    r.set_item(ns, production, item, ReplyCodeActions=":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C")
    s.profile([item])


def may_hold(s, ns, item, service, port, tag):
    """A take-and-die listener at FailureTimeout 0: the frame was written and the answer lost, and the operation gave up."""
    r = s.r
    step(f"{tag}: {item}, FailureTimeout 0, the listener takes the frame and dies")
    s.drain(ns, item, port)
    r.listener_up(port, {"mode": "take_and_die"})
    control = f"{tag}01"
    r.send(service, r.adt("A01", control), control)
    case_id = s.case_of(control)
    check(f"{tag}: a case opens", bool(case_id))
    if not case_id:
        return
    c, words = s.settled(case_id)
    print("        ", json.dumps({k: c.get(k) for k in ("state", "failureKind", "headline")})[:400], flush=True)
    check(f"{tag}: blocked RECEIVER_MAY_HOLD_IT", c.get("state") == "blocked" and "RECEIVER_MAY_HOLD_IT" in words, (c.get("state"), words[:800]))
    check(f"{tag}: the words name the receiver's screen", "own screen" in (c.get("headline") or ""), c.get("headline"))
    check(f"{tag}: no API write", not s.receiver_holds(control))
    check(f"{tag}: one frame only", r.heard(port).count(control) == 1, r.heard(port))
    if r.listening(port):
        r.listener_down(port)


def never_opened_passes(s, ns, item, service, port, tag):
    """FailureTimeout 0 with nothing listening: every attempt never opened, so the check passes and the plan goes on to a person."""
    r = s.r
    step(f"{tag}: {item}, FailureTimeout 0, nothing listening")
    s.drain(ns, item, port)
    control = f"{tag}01"
    # A bed of its own: an earlier scene's approved admission holds the rig's usual one.
    r.send(service, r.adt("A01", control).replace(b"BAY1^01", b"BAY9^09"), control)
    case_id = s.case_of(control)
    check(f"{tag}: a case opens", bool(case_id))
    if not case_id:
        return
    c, words = s.read(case_id)
    if c.get("waitsOnEngine"):
        # The case can open before the header reads Error: then it waited, and the sweep or a person plans it again.
        print("         it waited on the first look; planned again", flush=True)
        s.reopen(case_id)
        time.sleep(3)
        c, words = s.settled(case_id, away_from=("blocked",))
    print("        ", json.dumps({k: c.get(k) for k in ("state", "failureKind", "headline")})[:400], flush=True)
    check(f"{tag}: the plan reaches a person", c.get("state") == "awaiting_approval", (c.get("state"), c.get("headline"), words[-500:]))
    print("         approve:", s.approve(case_id), flush=True)
    c, words = s.settled(case_id, away_from=("awaiting_approval",))
    check(f"{tag}: and an approval goes through the API", s.receiver_holds(control) and c.get("state") == "resolved", (c.get("state"), c.get("headline")))


SCENES = ("before", "plain", "routed", "delayed", "not_established", "may_hold", "never_opened")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ctr", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--module", default="")
    ap.add_argument("--reuse", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--before", default="")
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
            names = ["Retry Out", "NoRetry Out", "LIMS Out"]
            s.profile(names)
            for name in names:
                s.connector(name)
            print("  restarted:", r.restart_production(r.SHUTTER, "Shutter.Production", "Gate"), flush=True)
        if args.before and "before" in only:
            subprocess.run(["docker", "cp", args.before, f"{r.ctr}:/tmp/GateBefore.cls"], check=True)
            r.session(r.SHUTTER, 'Set sc=$SYSTEM.OBJ.Load("/tmp/GateBefore.cls","ck-d") Write !,sc,!')
            print("  restarted on the earlier gate:", r.restart_production(r.SHUTTER, "Shutter.Production", "Gate"), flush=True)
            delivers_twice_before(s, r.PLAIN, "Retry Out", r.RETRY_IN, r.RETRY, "BF")
            r.session(r.SHUTTER, f'Set sc=$SYSTEM.OBJ.Load("{HOME}/pkg/src/Shutter/Operation/Gate.cls","ck-d") Write !,sc,!')
            print("  restarted on this gate:", r.restart_production(r.SHUTTER, "Shutter.Production", "Gate"), flush=True)
        if "plain" in only:
            still_trying_then_delivered(s, r.PLAIN, "Retry Out", r.RETRY_IN, r.RETRY, "PL")
        if "routed" in only:
            still_trying_then_delivered(s, r.ROUTED, "LIMS Out", r.ROUTED_IN, r.LIMS, "RT", also_up=r.SECOND)
            older_case(s, r.ROUTED, "LIMS Out", r.ROUTED_IN, r.LIMS, r.SECOND, "RO")
        if "delayed" in only:
            delayed(s, r.PLAIN, "Retry Out", r.RETRY_IN, r.RETRY, "DL")
        if "not_established" in only:
            not_established(s, r.PLAIN, "V11Rig.Plain", "Retry Out", r.RETRY_IN, r.RETRY, "NE")
        if "may_hold" in only:
            may_hold(s, r.PLAIN, "NoRetry Out", r.NORETRY_IN, r.NORETRY, "MH")
        if "never_opened" in only:
            never_opened_passes(s, r.PLAIN, "NoRetry Out", r.NORETRY_IN, r.NORETRY, "NO")
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
