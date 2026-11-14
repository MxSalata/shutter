#!/usr/bin/env python3
"""The pathology paths on the demo (1.4.6): a result the demo's results system refuses (P1), and an outage of that
receiver (P2), played by the Scenario Player through the demo hospital's results route, on a demo install.

    python3 tests/e2e/demo_pathology_check.py [--url http://localhost:52773]

Signs in as operator and approver (password from SHUTTER_PASSWORD, default "shutter"), and as judge and demo when
SHUTTER_JUDGE_PASSWORD and SHUTTER_PUBLIC_DEMO_PASSWORD name their passwords. What the receiver heard is read from the
stand-in itself (Hospital.Service.LabReceiver, HeardList, in the hospital's namespace), and the stored messages over SQL
(IRIS_USER and IRIS_PASSWORD, default _SYSTEM / SYS). In order:

  R  an operator's reset: the stand-in runs and its definition agrees, and no outage, event, reading or ledger row
     changes;
  P1 one result the stand-in answers AE: one case at Lab Results Out, a person's, with no resend; its findings name the OBX
     and the receiver's words; the stand-in heard it once and nothing more;
  P2 three results fail with the stand-in down and it comes back: the outage offers exactly those three, in order, none of
     them heard; P2 again is refused while the outage is open; another run's start (S2), P1 and an operator's reset leave
     the outage as it was (state, digest, list, ledger); the approval is refused while Shutter recovery is stopped and
     without the receiver check, recording nothing; with it, the stand-in hears each once, in order, byte for byte, each
     resend reads Completed, the card says what that proves, and the outage closes; P2 again is refused inside the window;
  D  once the window has passed, P2 again with an operator's reset in its down window: the reset may not switch the
     stand-in and leaves it down in both the running production and its definition, P2 plays to the end and brings it
     back, its outage offers its own three, and the approved resend has the stand-in hear each once;
  A  the judge and the demo sign-ins approve and run but never reset, and GET /access is what it was;
  N  no row of the four outage stores is ever removed: their counts never fall.

It changes the instance (cases, outages, the hospital's messages): run it on a throwaway demo install only. Exit 0 when
every check is ok, 1 when one fails, 3 when the instance can't run it. Standard library only.
"""
import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scenario_check as sc  # noqa: E402
from iris_query import query  # noqa: E402

RECEIVER = "Lab Results Out"
results = []


class Broken(Exception):
    """The instance can't run the check: no demo, no results route, a run that never finished."""


def check(name, ok, detail=""):
    results.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}{'' if ok else ': ' + str(detail)[:900]}", flush=True)


def step(title):
    print(f"\n{title}", flush=True)


class Check:
    def __init__(self, url):
        self.url = url
        password = os.environ.get("SHUTTER_PASSWORD", "shutter")
        self.operator = sc.Session(url).sign_in("operator", password)
        self.approver = sc.Session(url).sign_in("approver", password)
        judge = os.environ.get("SHUTTER_JUDGE_PASSWORD", "")
        demo = os.environ.get("SHUTTER_PUBLIC_DEMO_PASSWORD", "")
        self.judge = sc.Session(url).sign_in("judge", judge) if judge else None
        self.demo = sc.Session(url).sign_in("demo", demo) if demo else None
        self.counts = []
        self.hospital = os.environ.get("HOSPITAL_NS", "HOSPITAL")

    def close(self):
        for s in (self.operator, self.approver, self.judge, self.demo):
            if s:
                s.call("DELETE", "/session")

    def sql(self, ns, text, params=()):
        return query(self.url, ns, text, params)

    def heard(self):
        rows = self.sql(self.hospital, "SELECT Hospital_Service.LabReceiver_HeardList() AS h")
        h = rows[0]["h"] or "[]"
        return json.loads(h) if isinstance(h, str) else h

    def heard_since(self, n):
        return [h for h in self.heard() if h["n"] > n]

    def lab_headers(self, after):
        return self.sql(self.hospital, "SELECT ID, Status FROM Ens.MessageHeader WHERE SourceConfigName = 'Lab In' "
                        "AND TargetConfigName = ? AND ID > ? ORDER BY ID", [RECEIVER, after])

    def last_header(self):
        rows = self.sql(self.hospital, "SELECT MAX(ID) AS m FROM Ens.MessageHeader")
        return int(rows[0]["m"] or 0)

    def digest(self, header):
        rows = self.sql(self.hospital, "SELECT Hospital_Service.LabReceiver_BodyDigest(?) AS d", [header])
        return rows[0]["d"]

    def store_counts(self):
        out = {}
        for table in ("Outage", "OutageEvent", "ReceiverReading", "ResendRecord"):
            out[table] = int(self.sql("SHUTTER", f"SELECT COUNT(*) AS n FROM Shutter_Store.{table}")[0]["n"])
        self.counts.append(out)
        return out

    def outage(self):
        _, r = self.operator.call("GET", "/outages")
        for o in (r or {}).get("items", []):
            if o.get("receiver") == RECEIVER and o.get("state") != "closed":
                return o
        return None

    def outage_by_id(self, oid):
        _, o = self.operator.call("GET", f"/outages/{oid}")
        return o

    def listener(self):
        """The stand-in as the running production has it, and as its definition says: (1|0, 1|0)."""
        run = self.sql(self.hospital, "SELECT Hospital_Service.LabReceiver_Listening() AS l")
        defined = self.sql(self.hospital, "SELECT Enabled FROM Ens_Config.Item WHERE Production = 'Hospital.Production' AND Name = 'Results System In'")
        return (int(run[0]["l"] or 0) if run else None, int(defined[0]["Enabled"] in (True, 1, "1")) if defined else None)

    def paths(self):
        _, r = self.operator.call("GET", "/scenarios")
        return {p["id"]: p for p in (r or {}).get("pathology", [])}, (r or {}).get("run")

    def run(self, who, scenario, mode="board", seconds=420):
        """Starts a run and waits for it to end. Returns (start status, start body, the run record)."""
        sc.wait("the last run to finish", lambda: (self.paths()[1] or {}).get("state") not in ("queued", "running"), 600)
        code, started = who.call("POST", f"/scenarios/{scenario}/run", {"mode": mode}, idempotent=True)
        if code != 202:
            return code, started, None
        end = time.time() + seconds
        while time.time() < end:
            run = self.paths()[1] or {}
            if run.get("scenario") == scenario and run.get("state") not in ("queued", "running"):
                return code, started, run
            time.sleep(3)
        raise Broken(f"the run of {scenario} did not finish within {seconds} s")

    def snapshot(self, o):
        """What must not move on an offered outage: its state, its set's digest, its offered list and its ledger."""
        return (o.get("state"), (o.get("set") or {}).get("digest"), [x.get("headerId") for x in (o.get("lists") or {}).get("offered", [])], len(o.get("resends") or []))


def play(c):
    _, root = c.operator.call("GET", "/access")
    paths, _ = c.paths()
    if set(paths) != {"P1", "P2"}:
        raise Broken(f"GET /scenarios lists no pathology paths here ({sorted(paths)}): is this a demo install with the hospital?")
    if c.outage():
        raise Broken("the demo results receiver already has an outage open: run the check on a fresh demo install")

    step("R: an operator's reset")
    before = c.store_counts()
    code, r = c.operator.call("POST", "/scenarios/reset")
    check("R.a the reset goes", code == 200, (code, str(r)[:300]))
    check("R.b the results system's stand-in runs, and its definition agrees", c.listener() == (1, 1), c.listener())
    check("R.c the reset changed no outage store", c.store_counts() == before, (before, c.counts[-1]))

    step("P1: a result the receiver refuses")
    heard0 = len(c.heard())
    header0 = c.last_header()
    code, started, run = c.run(c.operator, "P1")
    check("P1.a the run starts and plays", code == 202 and run and run.get("state") == "done" and not run.get("timeouts"), (code, started, run))
    sent = c.lab_headers(header0)
    check("P1.b one result went to Lab Results Out, and the receiver refused it (Suspended)", [h["Status"] for h in sent] in (["Suspended"], [5], ["5"]), sent)
    paths, _ = c.paths()
    latest = (paths["P1"].get("latestCase") or {})
    case_id = latest.get("caseId")
    _, case = c.operator.call("GET", f"/cases/{case_id}") if case_id else (0, {})
    check("P1.c one case at Lab Results Out, a person's", case.get("receiver") == RECEIVER and case.get("state") == "escalated" and case.get("disposition") == "escalate", {k: case.get(k) for k in ("caseId", "receiver", "state", "disposition")})
    _, plan = c.operator.call("GET", f"/cases/{case_id}/plan")
    action = ((plan or {}).get("action") or (plan or {}).get("plan", {}).get("action") or {})
    check("P1.d the case offers no resend: its plan sends nothing and the case has no resend", (action.get("type") in (None, "none")) and not case.get("resends"), (action, case.get("resends")))
    _, snapshot = c.operator.call("GET", f"/cases/{case_id}/snapshot")
    text = json.dumps(snapshot) + json.dumps(case)
    check("P1.e its findings name the OBX and the receiver's own words", "set id OBX-1 = 5" in text and "Test code not recognised: ZZUNK" in text, text[:300])
    time.sleep(30)
    heard = c.heard()[heard0:]
    check("P1.f the receiver heard that one result once, and nothing more for 30 s", len(heard) == 1 and heard[0]["answer"] == "AE", heard)
    check("P1.g its case is tagged P1 and is not a recorded run", case.get("scenario") == "P1", case.get("scenario"))

    step("P2: the receiver down, three results, the receiver back")
    heard0 = len(c.heard())
    header0 = c.last_header()
    runner = c.judge or c.operator
    code, started, run = c.run(runner, "P2")
    check("P2.a the run starts and plays to an offered outage", code == 202 and run and run.get("state") == "done" and not run.get("timeouts"), (code, started, run))
    sent = c.lab_headers(header0)
    check("P2.b three results went to Lab Results Out and each ended in Error", len(sent) == 3 and all(str(h["Status"]) in ("Error", "8") for h in sent), sent)
    o = c.outage()
    if not o:
        raise Broken("no outage of Lab Results Out after P2")
    offered = (o.get("lists") or {}).get("offered", [])
    check("P2.c the outage offers exactly those three, in order, each never opened", [x["headerId"] for x in offered] == [int(h["ID"]) for h in sent] and all(x.get("attempts") == "never_opened" for x in offered), (offered, sent))
    check("P2.d each offered row names its control id", all(x.get("controlId") for x in offered) and len({x.get("controlId") for x in offered}) == 3, [x.get("controlId") for x in offered])
    check("P2.e the receiver heard none of them", c.heard()[heard0:] == [], c.heard()[heard0:])
    paths, _ = c.paths()
    check("P2.f GET /scenarios names the outage on P2", (paths["P2"].get("latestOutage") or {}).get("id") == int(o["id"]) and paths["P2"]["latestOutage"]["state"] == "offered", paths["P2"].get("latestOutage"))
    first = c.snapshot(o)
    c.store_counts()

    code, r = runner.call("POST", "/scenarios/P2/run", {"mode": "board"}, idempotent=True)
    check("P2.g P2 again is refused while its outage is open, with words that say where to finish it", code == 409 and "still open on the Incidents page" in (r or {}).get("detail", ""), (code, r))
    check("P2.h and the refusal moved nothing", c.snapshot(c.outage()) == first, (c.snapshot(c.outage()), first))

    other = c.judge or c.operator
    code, started, run = c.run(other, "S2", mode="rules")
    check("P2.i another run's start (S2) plays", code == 202 and run and run.get("state") == "done", (code, started, run))
    check("P2.j and leaves the outage as it was", c.snapshot(c.outage()) == first, (c.snapshot(c.outage()), first))
    code, started, run = c.run(c.operator, "P1")
    check("P2.k P1 played meanwhile leaves it as it was", run and run.get("state") == "done" and c.snapshot(c.outage()) == first, (run, c.snapshot(c.outage()), first))
    code, r = c.operator.call("POST", "/scenarios/reset")
    check("P2.l an operator's reset leaves it as it was", code == 200 and c.snapshot(c.outage()) == first, (code, c.snapshot(c.outage()), first))
    heard1 = len(c.heard())
    c.store_counts()

    approver = c.judge or c.approver
    code, r = c.approver.call("POST", "/recovery-control/stop", {"reason": "the lab asked us to hold every resend"})
    if code != 200:
        raise Broken(f"the stop was not taken: {code} {str(r)[:300]}")
    o = c.outage()
    body = {"digest": o["set"]["digest"], "version": o["version"], "note": "checked at the results system with the lab desk", "receiverChecked": True}
    code, r = approver.call("POST", f"/outages/{o['id']}/approvals", body, idempotent=True)
    check("P2.m while Shutter recovery is stopped the approval answers 409 recovery_stopped", code == 409 and (r or {}).get("error") == "recovery_stopped", (code, r))
    _, ctl = c.approver.call("GET", "/recovery-control")
    code, r = c.approver.call("POST", "/recovery-control/clear", {"reason": "the lab is ready", "expectedGeneration": (ctl or {}).get("generation")})
    if code != 200:
        raise Broken(f"the clear was not taken: {code} {str(r)[:300]}")
    o = c.outage()
    check("P2.n nothing was recorded and the receiver heard nothing", c.snapshot(o) == first and o.get("approval") is None and c.heard()[heard1:] == [], (c.snapshot(o), o.get("approval")))
    body = {"digest": o["set"]["digest"], "version": o["version"], "note": "approved without a check at the results system"}
    code, r = approver.call("POST", f"/outages/{o['id']}/approvals", body, idempotent=True)
    check("P2.o without the receiver check the approval answers 409 receiver_check_needed", code == 409 and (r or {}).get("error") == "receiver_check_needed", (code, r))
    o = c.outage()
    body = {"digest": o["set"]["digest"], "version": o["version"], "note": "checked at the results system with the lab desk", "receiverChecked": True}
    code, r = approver.call("POST", f"/outages/{o['id']}/approvals", body, idempotent=True)
    check("P2.p with it, the approval goes on the same digest", code == 200 and (r or {}).get("state") in ("sending", "closed") and (r.get("set") or {}).get("digest") == first[1], (code, str(r)[:300]))
    code, again = runner.call("POST", "/scenarios/P2/run", {"mode": "board"}, idempotent=True)
    check("P2.q P2 again is refused while the resend sends, or then inside the window", code == 409, (code, again))
    oid = o["id"]
    sc.wait("the outage to close", lambda: (c.outage_by_id(oid) or {}).get("state") == "closed", 180)
    o = c.outage_by_id(oid)
    heard = c.heard()[heard1:]
    want = [x["controlId"] for x in offered]
    check("P2.r the receiver heard each once, in order, and nothing else", [h["control"] for h in heard] == want and all(h["answer"] == "AA" for h in heard), (heard, want))
    check("P2.s byte for byte as the stored messages", [h["sha256"] for h in heard] == [c.digest(x["headerId"]) for x in offered], heard)
    runs = [x for x in (o.get("resends") or []) if str(x.get("runId", "")).startswith("R")]
    check("P2.t each resend reads Completed", len(runs) == 3 and all(x.get("state") == "completed" and x.get("closure") == "sent" for x in runs), [(x.get("controlId"), x.get("state")) for x in runs])
    first_line = (o.get("words") or {}).get("first", "")
    check("P2.u the card says the engine completed them and what that does not prove", "each new header Completed" in first_line and "has not been independently checked" in first_line, first_line)
    check("P2.v the outage closed", o.get("state") == "closed", o.get("state"))
    code, r = runner.call("POST", "/scenarios/P2/run", {"mode": "board"}, idempotent=True)
    check("P2.w P2 again inside the window is refused, with how long to wait", code == 409 and "inside the outage window" in (r or {}).get("detail", ""), (code, r))

    step("D: P2 again, with an operator's reset in its down window")
    detail = (r or {}).get("detail", "")
    wait = int("".join(ch for ch in detail.split(" for ", 1)[-1].split(" s", 1)[0] if ch.isdigit()) or 0) if "inside the outage window" in detail else 0
    time.sleep(min(wait, 400) + 2)
    heard0 = len(c.heard())
    header0 = c.last_header()
    code, started = c.operator.call("POST", "/scenarios/P2/run", {"mode": "board"}, idempotent=True)
    for _ in range(40):
        if code != 409 or "inside the outage window" not in (started or {}).get("detail", ""):
            break
        time.sleep(10)
        code, started = c.operator.call("POST", "/scenarios/P2/run", {"mode": "board"}, idempotent=True)
    check("D.a P2 starts again once the window has passed", code == 202, (code, started))
    if code != 202:
        raise Broken(f"P2 did not start after the window: {code} {str(started)[:300]}")
    end = time.time() + 120
    while time.time() < end and c.listener()[0] != 0:
        time.sleep(0.5)
    down = c.listener()
    code, r = c.operator.call("POST", "/scenarios/reset")
    lab = (r or {}).get("lab", "")
    run = c.paths()[1] or {}
    check("D.b an operator's reset in P2's down window goes, and says it may not switch the stand-in", down == (0, 0) and code == 200 and lab.startswith("not switched: this sign-in may not update") and run.get("state") == "running", (down, code, lab, run.get("state"), run.get("step")))
    check("D.c and leaves it down in the running production and in its definition", c.listener() == (0, 0), c.listener())
    end = time.time() + 420
    while time.time() < end:
        run = c.paths()[1] or {}
        if run.get("scenario") == "P2" and run.get("state") not in ("queued", "running"):
            break
        time.sleep(3)
    check("D.d P2 plays to an offered outage", run.get("state") == "done" and not run.get("timeouts"), run)
    check("D.e and brought the stand-in back: it runs, and its definition agrees", c.listener() == (1, 1), c.listener())
    sent = c.lab_headers(header0)
    o = c.outage()
    if not o:
        raise Broken("no outage of Lab Results Out after the second P2")
    offered = (o.get("lists") or {}).get("offered", [])
    check("D.f its outage offers its own three, in order, none heard", len(sent) == 3 and [x["headerId"] for x in offered] == [int(h["ID"]) for h in sent] and c.heard()[heard0:] == [], (offered, sent, c.heard()[heard0:]))
    body = {"digest": o["set"]["digest"], "version": o["version"], "note": "checked at the results system with the lab desk", "receiverChecked": True}
    code, r = c.approver.call("POST", f"/outages/{o['id']}/approvals", body, idempotent=True)
    check("D.g the approval goes", code == 200, (code, str(r)[:300]))
    oid = o["id"]
    sc.wait("the second outage to close", lambda: (c.outage_by_id(oid) or {}).get("state") == "closed", 180)
    heard = c.heard()[heard0:]
    want = [x["controlId"] for x in offered]
    check("D.h the stand-in heard each once, in order, byte for byte, and nothing else", [h["control"] for h in heard] == want and all(h["answer"] == "AA" for h in heard) and [h["sha256"] for h in heard] == [c.digest(x["headerId"]) for x in offered], (heard, want))
    c.store_counts()

    step("A: what the demo's sign-ins may do")
    for name, s in (("judge", c.judge), ("demo", c.demo)):
        if not s:
            print(f"  skip {name}: its password is not set")
            continue
        code, r = s.call("POST", "/scenarios/reset")
        check(f"A.{name} may not reset the scenarios", code == 403, (code, r))
    _, now = c.operator.call("GET", "/access")
    check("A.access GET /access is what it was", now == root, "changed")

    step("N: nothing in the outage stores was removed")
    c.store_counts()
    falls = [(a, b) for a, b in zip(c.counts, c.counts[1:]) if any(b[k] < a[k] for k in a)]
    check("N.a no count of Outage, OutageEvent, ReceiverReading or ResendRecord ever fell", not falls and c.counts[-1]["ResendRecord"] >= c.counts[0]["ResendRecord"] + 3, (falls, c.counts[0], c.counts[-1]))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", default=os.environ.get("IRIS_URL", "http://localhost:52773"))
    args = ap.parse_args()
    c = None
    code = 0
    try:
        c = Check(args.url)
        play(c)
    except Broken as e:
        print(f"\nTHE INSTANCE CAN'T RUN THE CHECK, which says nothing about the product: {e}")
        code = 3
    finally:
        if c:
            c.close()
    failed = [n for n, ok in results if not ok]
    print(f"\n{len(results) - len(failed)} ok, {len(failed)} failed")
    if code:
        return code
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
