#!/usr/bin/env python3
"""The close of a receiver's outage on a real instance: the drain, a dirty read during it, the headers listed at the close, the
engine's own alerts beside the record, a busy feed, and the cases linked by receiver and time, each judged from its own
delivery header. It reads the store directly, since the routes are another part's. Every receiver is a fake on the loopback
address of a test instance. The cases here are written straight into the store with the fields the intake gives them, since
the rig's productions have no intake of Shutter's.

    python3 tests/e2e/v11_rig/close/check_close.py --ctr NAME --port PORT --image IMAGE [--module core] [--keep] [--reuse] [--only a,b]

Run from a copy of the repository's tree. Exit status: 0 all ok; 1 a check failed; 3 the rig broke.
"""
import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from rig import Rig, RigBroken  # noqa: E402

PLAIN, PROD = "RIGPLAIN", "V11Rig.Plain"
RETRY, NORETRY = "Retry Out", "NoRetry Out"
PORT = {RETRY: 7711, NORETRY: 7712}
IN = {RETRY: 7611, NORETRY: 7612}
CLOSE_WITHIN = 60

failed, passed = [], 0
tag = time.strftime("%H%M%S")
seq = [0]


def check(name, ok, detail=""):
    global passed
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {str(detail)[:1500]}"), flush=True)
    if ok:
        passed += 1
    else:
        failed.append(name)


def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


def note(text):
    print(f"        {text}", flush=True)


class Close:
    def __init__(self, r):
        self.r = r

    def rows(self, receiver, everything=False):
        where = f"Receiver='{receiver}'" + ("" if everything else " AND State<>'closed'")
        code = f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM Shutter_Store.Outage WHERE {where} ORDER BY ID") While rs.%Next() {{ Write !,"<<<",##class(Shutter.Store.Outage).%OpenId(rs.%Get("ID")).ToJSON().%ToJSON(),">>>",! }}"""
        return [json.loads(x) for x in self.r.read_rows("SHUTTER", code)]

    def row(self, oid):
        return self.r.obj("SHUTTER", f"##class(Shutter.Store.Outage).%OpenId({oid}).ToJSON().%ToJSON()")

    def events(self, oid):
        return json.loads(self.r.value("SHUTTER", f"##class(Shutter.Store.OutageEvent).Of({oid}).%ToJSON()"))

    def kinds(self, oid):
        return [e["kind"] for e in self.events(oid)]

    def close_all(self, receiver):
        for o in self.rows(receiver):
            self.r.session("SHUTTER", f'Set sc=##class(Shutter.Store.Outage).%OpenId({o["id"]}).Close("the check goes on","the check") Write:\'sc $SYSTEM.Status.GetErrorText(sc)')

    def declare(self, extra=None):
        """Both receivers watched; extra: {receiver: {key: value}} added to its entry."""
        extra = extra or {}
        entries = []
        for n in (RETRY, NORETRY):
            e = {"name": n, "system": "Made-up LIMS", "category": "orders_results", "tier": 3, "watch": {"namespace": PLAIN, "item": n}, "runbook": "start the listener", "call": "01632 960123", "approvers": ["duty approver"]}
            e.update(extra.get(n, {}))
            entries.append(e)
        path = self.r.put_file(json.dumps({"receivers": entries}).encode(), "close-profile.json")
        out = self.r.session("SHUTTER", f'''Set s=##class(%Stream.FileCharacter).%New() Do s.LinkToFile("{path}") Set p=##class(Shutter.Store.SiteProfile).Current() Set d={{}}.%FromJSON(s) Set p.receivers=d.receivers Set sc=##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(),"the close check","the check") Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!''')
        if "<<<ok>>>" not in out:
            raise RigBroken("the profile was refused: " + out[-500:])

    def add_case(self, receiver, header, kind="delivery_failed", code="", state="blocked"):
        """A case as the intake leaves one: its receiver, its origin header in the plain namespace, its kind and route."""
        seq[0] += 1
        cid = f"C-K{tag}{seq[0]}"
        code_line = f'Set c=##class(Shutter.Store.Case).%New() Set c.CaseId="{cid}",c.OperationKey="close-check-{cid}",c.Receiver="{receiver}",c.FailureKind="{kind}",c.FailureReasonCode="{code}",c.State="{state}",c.SourceNamespace="{PLAIN}",c.SourceProduction="{PROD}",c.OriginHeaderId="{header}",c.OpenedAt=##class(Shutter.Util.Time).NowUTC(),c.UpdatedAt=c.OpenedAt Set sc=c.%Save() Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!'
        out = self.r.session("SHUTTER", code_line)
        if "<<<ok>>>" not in out:
            raise RigBroken("the case did not save: " + out[-400:])
        return cid

    def case(self, cid):
        code = f'Set c=##class(Shutter.Store.Case).ByCaseId("{cid}") Write !,"<<<",{{"state":(c.State),"outcome":(c.Outcome),"headline":(c.Headline)}}.%ToJSON(),">>>",!'
        return json.loads(self.r.read_rows("SHUTTER", code)[0])

    def case_events(self, cid):
        code = f'''Set c=##class(Shutter.Store.Case).ByCaseId("{cid}") Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Kind, Text FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? ORDER BY ID",c.%Id()) If rs.%SQLCODE<0 {{ Write !,"<<<SQL ",rs.%SQLCODE,">>>",! }} While rs.%Next() {{ Write !,"<<<",rs.%Get("Kind"),"|",$TRANSLATE(rs.%Get("Text"),$CHAR(10)," "),">>>",! }}'''
        return self.r.read_rows("SHUTTER", code)


def qn(r, item):
    """The item's queue count, 0 for an item whose queue the engine hasn't made yet."""
    return int(r.value(PLAIN, f'##class(Ens.Queue).GetCount("{item}")+0'))


def mine(r, item, controls):
    return [h for h in r.headers(PLAIN, item) if h["control"] in controls]


def down(r, port):
    if r.listening(port):
        r.listener_down(port)


def ready(r, c, receiver, spec=None):
    """A listener as asked, the queue empty and nothing open for the receiver."""
    down(r, PORT[receiver])
    r.listener_up(PORT[receiver], spec or {"mode": "up"})
    r.wait_until(lambda: qn(r, receiver) == 0, 120)
    time.sleep(6)
    c.close_all(receiver)
    time.sleep(6)


def open_one(r, c, receiver, controls, within=75):
    down(r, PORT[receiver])
    time.sleep(1)
    for x in controls:
        r.send(IN[receiver], r.order(x), x)
    r.wait_until(lambda: len(c.rows(receiver)) >= 1, within, 1)
    rows = c.rows(receiver)
    if len(rows) != 1:
        raise RigBroken(f"no single outage opened for {receiver}: {rows}")
    return rows[0]


def watch_drain(r, c, receiver, oid, controls, seconds):
    """Reads the row and the queue every second until the row closes or the time runs out: [(t, state, queue, head)]."""
    seen, end = [], time.time() + seconds
    while time.time() < end:
        o = c.row(oid)
        q = qn(r, receiver)
        seen.append((time.time(), o["state"], q, (o.get("readings") or {}).get("headHeaderId")))
        if o["state"] in ("closed", "needs_person"):
            break
        time.sleep(1)
    return seen


def drained_at(seen):
    for t, state, q, head in seen:
        if q == 0:
            return t
    return None


def drain(r, c):
    step("O2: a retry-forever outage drains by itself; draining with a delivery at the head; closed within a minute of the drain")
    ready(r, c, RETRY)
    sent = [f"D{tag}{i}" for i in range(1, 7)]
    o = open_one(r, c, RETRY, sent)
    r.listener_up(PORT[RETRY], {"mode": "up", "delay": 2})
    seen = watch_drain(r, c, RETRY, o["id"], sent, 240)
    t0 = drained_at(seen)
    end = [s for s in seen if s[1] == "closed"]
    took = (end[0][0] - t0) if end and t0 else None
    note(f"states seen: {sorted(set(s[1] for s in seen))}; closed {took and round(took)} s after the queue first read 0")
    check("O2.c: closed by itself, with no person's act", bool(end), seen[-3:])
    check("O2.c: within a minute of the drain", took is not None and took <= CLOSE_WITHIN, took)
    check("O2.d: never closed while the queue held anything", not [s for s in seen if s[1] == "closed" and s[2] > 0], [s for s in seen if s[1] == "closed"][:3])
    check("draining while a delivery is active at the head", any(s[1] == "draining" and s[3] for s in seen), seen[:20])
    kinds = c.kinds(o["id"])
    check("its events: opened, draining, closing, closed", kinds[0] == "opened" and kinds[-2:] == ["closing", "closed"] and "draining" in kinds, kinds)
    row = c.row(o["id"])
    note(f"outcome: {row.get('outcome')}")
    check("every header of the window read: the six Completed counted", row["settled"]["completed"] >= 6 and row["settled"]["error"] == 0, row["settled"])
    check("nothing in any list", all(row["lists"][k] == [] for k in ("queued", "offered", "reached", "refused")), row["lists"])
    check("the words say drained and never verified", "Delivery backlog drained" in (row.get("outcome") or "") and "Verified" not in (row.get("outcome") or ""), row.get("outcome"))
    check("the set not computed, with the build's reason", row["set"]["status"] == "not_computed" and row["set"]["reason"] == "no set gate in this build", row["set"])
    check("nothing sent by Shutter: one header each, heard once each", len(mine(r, RETRY, sent)) == 6 and sorted(r.heard(PORT[RETRY])).count(sent[0]) == 1, mine(r, RETRY, sent))


def again(r, c):
    step("O3: down again during the drain: back to open, one row, closed only from closing")
    ready(r, c, RETRY)
    sent = [f"A{tag}{i}" for i in range(1, 7)]
    o = open_one(r, c, RETRY, sent)
    down(r, PORT[RETRY])
    # Slow enough answers that a poll sees the drain before the listener dies.
    r.listener_up(PORT[RETRY], {"mode": "take_and_die", "after": 3, "delay": 4})
    seen = []
    end = time.time() + 70
    while time.time() < end:
        rows = c.rows(RETRY, everything=True)
        mine_rows = [x for x in rows if int(x["id"]) >= int(o["id"])]
        seen.append((time.time(), [(x["id"], x["state"]) for x in mine_rows], qn(r, RETRY)))
        time.sleep(2)
    kinds = c.kinds(o["id"])
    note(f"events so far: {kinds}")
    check("O3.b: the same one row throughout, never closed", all(len(s[1]) == 1 and s[1][0][0] == o["id"] and s[1][0][1] != "closed" for s in seen), seen[-5:])
    check("O3.b: back to open after draining", "draining" in kinds and kinds[kinds.index("draining") + 1:].count("open") >= 1, kinds)
    check("the queue still held the rest", seen[-1][2] >= 1, seen[-1])
    down(r, PORT[RETRY])
    r.listener_up(PORT[RETRY], {"mode": "up"})
    done = watch_drain(r, c, RETRY, o["id"], sent, 240)
    t0 = drained_at(done)
    closed = [s for s in done if s[1] == "closed"]
    took = (closed[0][0] - t0) if closed and t0 else None
    check("O3.d: only now closed, within a minute of the drain", took is not None and took <= CLOSE_WITHIN, (took, done[-3:]))
    kinds = c.kinds(o["id"])
    check("O3.d: closed only from closing", kinds[-2:] == ["closing", "closed"], kinds)
    check("one row for the receiver", len([x for x in c.rows(RETRY, everything=True) if int(x["id"]) >= int(o["id"])]) == 1, c.rows(RETRY, everything=True))
    row = c.row(o["id"])
    note(f"outcome: {row.get('outcome')}")
    note(f"headers: {[(h['control'], h['status'], h['description']) for h in mine(r, RETRY, sent)]}")


def ae(r, c):
    step("One AE in the drain: closed as settled, the Suspended header in the fourth list")
    ready(r, c, RETRY)
    sent = [f"E{tag}{i}" for i in range(1, 4)]
    o = open_one(r, c, RETRY, sent)
    down(r, PORT[RETRY])
    r.listener_up(PORT[RETRY], {"mode": "answer", "code": "AA", "by_control": {sent[1]: {"code": "AE", "words": "Made-up application error"}}})
    done = watch_drain(r, c, RETRY, o["id"], sent, 180)
    row = c.row(o["id"])
    note(f"outcome: {row.get('outcome')}")
    check("closed", row["state"] == "closed", (row["state"], row.get("outcome")))
    refused = [x for x in row["lists"]["refused"] if x["controlId"] == sent[1]]
    check("the AE's header is in the fourth list, Suspended", len(refused) == 1 and refused[0]["status"] == "Suspended", row["lists"])
    check("counted as suspended, and said", row["settled"]["suspended"] >= 1 and "Suspended and still need" in (row.get("outcome") or ""), (row["settled"], row.get("outcome")))


def aborted(r, c):
    step("A header a person aborted: in the fourth list with its status word, waited for by nobody")
    ready(r, c, RETRY)
    sent = [f"B{tag}{i}" for i in range(1, 4)]
    o = open_one(r, c, RETRY, sent)
    last = [h for h in mine(r, RETRY, sent) if h["control"] == sent[2]][0]
    # The stock act the Message Viewer's Abort takes on a queued message: Ens.Queue's AbortItem at the message's place in the queue.
    out = r.session(PLAIN, f'''Set sc="not queued",q="{RETRY}",p="" For {{ Set p=$ORDER(^Ens.Queue(q,p)) Quit:p=""  Continue:p=0  Set i="" For {{ Set i=$ORDER(^Ens.Queue(q,p,i)) Quit:i=""  If ^Ens.Queue(q,p,i)={last["id"]} {{ Set sc=##class(Ens.Queue).AbortItem(q,p,i) }} }} }} Write !,"<<<",$SELECT(sc="not queued":sc,sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!''')
    status = [h["status"] for h in mine(r, RETRY, sent) if h["control"] == sent[2]]
    note(f"abort: {out.strip()[-200:]}; the header now reads {status}")
    if status != ["Aborted"]:
        raise RigBroken(f"the header did not read Aborted: {status} {out[-300:]}")
    down(r, PORT[RETRY])
    r.listener_up(PORT[RETRY], {"mode": "up"})
    watch_drain(r, c, RETRY, o["id"], sent, 180)
    row = c.row(o["id"])
    refused = [x for x in row["lists"]["refused"] if x["controlId"] == sent[2]]
    check("closed without waiting for the aborted one", row["state"] == "closed", (row["state"], row.get("outcome")))
    check("the Aborted header listed with its word", len(refused) == 1 and refused[0]["status"] == "Aborted" and "Aborted" in refused[0]["reason"], row["lists"])
    check("never sent", sent[2] not in r.heard(PORT[RETRY]), r.heard(PORT[RETRY]))


def noretry_five(r, c):
    step("A no-retry outage, five never-opened failures with AlertOnError on: closing within 10 s of the last, then a person, never closed")
    ready(r, c, NORETRY)
    before = {o["id"] for o in c.rows(NORETRY, everything=True)}
    down(r, PORT[NORETRY])
    time.sleep(1)
    sent = [f"N{tag}{i}" for i in range(1, 6)]
    for x in sent:
        r.send(IN[NORETRY], r.order(x), x)
    cases, last_error = {}, None
    end = time.time() + 90
    while time.time() < end and len(cases) < 5:
        for h in mine(r, NORETRY, sent):
            if h["status"] == "Error" and h["control"] not in cases:
                cases[h["control"]] = c.add_case(NORETRY, h["id"], "delivery_failed", "", "escalated")
                last_error = time.time()
        time.sleep(0.5)
    rows = [x for x in c.rows(NORETRY, everything=True) if x["id"] not in before]
    if len(rows) != 1:
        raise RigBroken(f"no single outage at {NORETRY}: {rows}")
    oid = rows[0]["id"]
    end = time.time() + 40
    while time.time() < end and c.row(oid)["state"] in ("open", "closing"):
        time.sleep(0.5)
    reached = time.time()
    row = c.row(oid)
    events = c.events(oid)
    note(f"state {row['state']} {reached - last_error:.1f} s after the last header failed; events {[e['kind'] for e in events]}")
    note(f"outcome: {row.get('outcome')}")
    check("five Error headers, nothing queued", len([h for h in mine(r, NORETRY, sent) if h["status"] == "Error"]) == 5 and qn(r, NORETRY) == 0, mine(r, NORETRY, sent))
    check("reached closing within 10 s of the last header settling", "closing" in [e["kind"] for e in events] and reached - last_error <= 10, reached - last_error)
    check("then needs_person, never closed", row["state"] == "needs_person" and "closed" not in [e["kind"] for e in events], row["state"])
    check("'5 messages failed and were not offered'", (row.get("outcome") or "").startswith("5 messages failed and were not offered"), row.get("outcome"))
    listed = [x for x in row["lists"]["refused"] if x["controlId"] in sent]
    check("the five listed with their status", len(listed) == 5 and all(x["status"] == "Error" and x["attempts"] == "never_opened" for x in listed), row["lists"])
    check("set not computed, no set gate", row["set"]["status"] == "not_computed" and row["set"]["reason"] == "no set gate in this build", row["set"])
    linked = {x["caseId"] for x in row["linkedCases"]}
    check("the five cases linked to the one outage", set(cases.values()) <= linked, (cases, row["linkedCases"]))
    check("none a second outage", len([x for x in c.rows(NORETRY, everything=True) if x["id"] not in before]) == 1, c.rows(NORETRY, everything=True))
    check("none resolved: their headers read Error", all(c.case(x)["state"] == "escalated" for x in cases.values()) and len([x for x in row["openCases"] if x["caseId"] in cases.values()]) == 5, row["openCases"])
    kinds = [a["kind"] for a in row["alerts"]]
    note(f"alerts on the row: {[(a['at'], a['kind']) for a in row['alerts']][:8]}")
    check("the engine's error alerts listed beside the record, by time and kind", kinds.count("AlertOnError") >= 5 and all(a["at"] for a in row["alerts"]), row["alerts"][:6])
    check("the row's state unmoved by them", [e["kind"] for e in events if e["kind"] not in ("kind", "overdue")] == ["opened", "closing", "needs_person"], [e["kind"] for e in events])
    r.listener_up(PORT[NORETRY], {"mode": "up"})
    c.close_all(NORETRY)
    return cases


def linked(r, c, noretry_header):
    step("Queue alerts beside the record, and linked cases judged each from its own delivery header (O13.h's resolve)")
    ready(r, c, RETRY)
    r.set_item(PLAIN, PROD, RETRY, QueueWaitAlert=30, QueueCountAlert=2)
    try:
        sent = [f"Q{tag}{i}" for i in range(1, 5)]
        o = open_one(r, c, RETRY, sent)
        before = c.kinds(o["id"])
        heads = {h["control"]: h["id"] for h in mine(r, RETRY, sent)}
        waited = c.add_case(RETRY, heads[sent[0]], "delivery_failed", "", "blocked")
        ack = c.add_case(RETRY, heads[sent[1]], "delivery_failed", "ack_AE", "blocked")
        refused = c.add_case(RETRY, heads[sent[2]], "rejected", "", "escalated")
        other = c.add_case(RETRY, noretry_header, "delivery_failed", "", "blocked") if noretry_header else None
        r.wait_until(lambda: {"QueueWaitAlert", "QueueCountAlert"} <= {a["kind"] for a in c.row(o["id"])["alerts"]}, 120, 3)
        row = c.row(o["id"])
        note(f"alerts on the row: {[(a['at'], a['kind']) for a in row['alerts']]}")
        check("the row's alerts name the queue wait and count alerts with their time", {"QueueWaitAlert", "QueueCountAlert"} <= {a["kind"] for a in row["alerts"]} and all(a["at"] and a["text"] for a in row["alerts"]), row["alerts"])
        check("the outage's state unmoved by them", row["state"] == "open" and c.kinds(o["id"]) == before, (row["state"], c.kinds(o["id"]), before))
        down(r, PORT[RETRY])
        r.listener_up(PORT[RETRY], {"mode": "up"})
        watch_drain(r, c, RETRY, o["id"], sent, 180)
        row = c.row(o["id"])
        note(f"outcome: {row.get('outcome')}")
        w = c.case(waited)
        check("O13.h: the waiting case resolved with the shared sentence, its header Completed", w["state"] == "resolved" and (w["outcome"] or "").startswith("Delivered by the engine at"), w)
        check("O13.h: never offered", row["lists"]["offered"] == [], row["lists"]["offered"])
        a = c.case(ack)
        check("an ack_AE case whose header reads Completed stays open, in openCases", a["state"] == "blocked" and ack in [x["caseId"] for x in row["openCases"]], (a, row["openCases"]))
        f = c.case(refused)
        check("a rejected case the same", f["state"] == "escalated" and refused in [x["caseId"] for x in row["openCases"]], (f, row["openCases"]))
        if other:
            x = c.case(other)
            check("a case linked by time whose delivery header is another message's is not resolved", x["state"] == "blocked" and other in [y["caseId"] for y in row["openCases"]], (x, row["openCases"]))
        n = len(row["openCases"])
        check("the closed row is not green over open work", row["state"] == "closed" and (row.get("outcome") or "").startswith(f"Transport outage closed. {n} delivery exception"), row.get("outcome"))
        check("each open case has its owner and why", all(x["owner"] == "duty approver" and x["reason"] for x in row["openCases"]), row["openCases"])
        check("every linked case on the row", {waited, ack, refused} <= {x["caseId"] for x in row["linkedCases"]}, row["linkedCases"])
        check("the engine delivered each once", all(r.heard(PORT[RETRY]).count(x) == 1 for x in sent), r.heard(PORT[RETRY]))
    finally:
        r.set_item(PLAIN, PROD, RETRY, QueueWaitAlert=0, QueueCountAlert=0)


def get_reply_off(r, c):
    step("A linked case at GetReply off stays open with the sentence on it")
    ready(r, c, RETRY)
    r.set_item(PLAIN, PROD, RETRY, GetReply=0)
    try:
        sent = [f"G{tag}1"]
        o = open_one(r, c, RETRY, sent)
        head = mine(r, RETRY, sent)[0]["id"]
        cid = c.add_case(RETRY, head, "delivery_failed", "", "blocked")
        down(r, PORT[RETRY])
        r.listener_up(PORT[RETRY], {"mode": "up"})
        watch_drain(r, c, RETRY, o["id"], sent, 180)
        row = c.row(o["id"])
        x = c.case(cid)
        notes = [e for e in c.case_events(cid) if "Completed without waiting" in e]
        note(f"case: {x}")
        check("closed, and the case stays open", row["state"] == "closed" and x["state"] == "blocked" and cid in [y["caseId"] for y in row["openCases"]], (row["state"], x, row["openCases"]))
        check("with the sentence on it", (x["outcome"] or "").startswith("IRIS marked the delivery Completed without waiting for an acknowledgement") and len(notes) == 1, (x, notes))
    finally:
        r.set_item(PLAIN, PROD, RETRY, GetReply=1)


def busy(r, c):
    step("A busy feed never at queue 0 goes to a person at settle_minutes: from draining at a retrying receiver, from open at a no-retry one")
    c.declare({RETRY: {"settle_minutes": 1}, NORETRY: {"settle_minutes": 1}})
    try:
        ready(r, c, RETRY)
        o = open_one(r, c, RETRY, [f"R{tag}0"])
        down(r, PORT[RETRY])
        r.listener_up(PORT[RETRY], {"mode": "up", "delay": 3})
        t0, i, state = time.time(), 0, ""
        while time.time() - t0 < 110:
            i += 1
            r.send(IN[RETRY], r.order(f"R{tag}{i}"), f"R{tag}{i}")
            state = c.row(o["id"])["state"]
            if state == "needs_person":
                break
            time.sleep(1.5)
        row = c.row(o["id"])
        kinds = c.kinds(o["id"])
        note(f"retrying: {row['state']} after {time.time() - t0:.0f} s; events {kinds}; outcome {row.get('outcome')}")
        check("retrying: needs_person from draining at settle_minutes", row["state"] == "needs_person" and kinds[-2:] == ["draining", "needs_person"] and "busy feed" in (row.get("outcome") or ""), (row["state"], kinds, row.get("outcome")))
        r.listener_spec(PORT[RETRY], {"mode": "up"})
        r.wait_until(lambda: qn(r, RETRY) == 0, 240)
        c.close_all(RETRY)

        ready(r, c, NORETRY)
        before = {x["id"] for x in c.rows(NORETRY, everything=True)}
        down(r, PORT[NORETRY])
        time.sleep(1)
        t0, i, oid = time.time(), 0, None
        while time.time() - t0 < 120:
            i += 1
            r.send(IN[NORETRY], r.order(f"S{tag}{i}"), f"S{tag}{i}")
            rows = [x for x in c.rows(NORETRY, everything=True) if x["id"] not in before]
            if rows:
                oid = rows[0]["id"]
                if c.row(oid)["state"] == "needs_person":
                    break
            time.sleep(2)
        row = c.row(oid) if oid else {}
        kinds = c.kinds(oid) if oid else []
        note(f"no-retry: {row.get('state')} after {time.time() - t0:.0f} s; events {kinds}; outcome {row.get('outcome')}")
        check("no-retry: needs_person from open at settle_minutes", row.get("state") == "needs_person" and kinds[-2:] == ["opened", "needs_person"] and "busy feed" in (row.get("outcome") or ""), (row.get("state"), kinds))
        check("never closed", "closed" not in kinds, kinds)
        r.listener_up(PORT[NORETRY], {"mode": "up"})
        r.wait_until(lambda: qn(r, NORETRY) == 0, 240)
        c.close_all(NORETRY)
    finally:
        c.declare()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ctr", required=True)
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--image", required=True)
    p.add_argument("--module", default="")
    p.add_argument("--keep", action="store_true")
    p.add_argument("--reuse", action="store_true")
    p.add_argument("--only", default="")
    a = p.parse_args()
    r = Rig(a.ctr, a.port, a.image, a.module)
    c = Close(r)
    want = a.only.split(",") if a.only else None
    try:
        if not a.reuse:
            step("Installing")
            r.start()
            r.install()
        c.declare()
        noretry_header = None
        for name, fn in (("drain", drain), ("again", again), ("ae", ae), ("aborted", aborted), ("noretry", noretry_five), ("linked", None), ("getreply", get_reply_off), ("busy", busy)):
            if want and name not in want:
                continue
            if name == "noretry":
                fn(r, c)
                hs = [h for h in r.headers(PLAIN, NORETRY) if h["status"] == "Error"]
                noretry_header = hs[-1]["id"] if hs else None
            elif name == "linked":
                if noretry_header is None:
                    hs = [h for h in r.headers(PLAIN, NORETRY) if h["status"] == "Error"]
                    noretry_header = hs[-1]["id"] if hs else None
                linked(r, c, noretry_header)
            else:
                fn(r, c)
        logged = [x for x in r.log_rows("SHUTTER", "Receiver Watch") if x["type"] in ("Error", "Warning")]
        check("the watch logged no error or warning", logged == [], logged[:5])
    except RigBroken as e:
        print(f"RIG BROKEN: {e}", flush=True)
        sys.exit(3)
    finally:
        if not a.keep:
            r.remove()
    print(f"\n{passed} ok, {len(failed)} failed" + (": " + ", ".join(failed) if failed else ""), flush=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
