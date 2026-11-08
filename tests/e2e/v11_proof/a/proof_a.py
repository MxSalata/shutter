#!/usr/bin/env python3
"""Tier A's proof rows, measured on the rig: what the engine shows at a receiver's outage, and what the outage record and the
intake do with it. Each row prints what it read, then a stated PASS or STOP and the decision the reading settles. A STOP is a
real answer: the design's words on that point change, as the row says. Every receiver is a fake on the loopback address of a
test instance, and every name is made up. Nothing here calls a model or needs an API key.

    python3 tests/e2e/v11_proof/a/proof_a.py --ctr NAME --port PORT --image IMAGE [--module core] [--keep] [--reuse] [--only 9,2,3]

Rows: 9 a 30 s blip at a no-retry receiver; 2 that receiver idle once the listener is back; 3 one refusal at a no-retry receiver,
then silence; 4 which reading carries the head message through a refusal loop and a read-timeout loop at a retrying one; 12
whether a header completed after retries keeps its earlier rows; 13 a message for the patient arriving between a check and an
enqueue; 15 an operation's inactivity alert, and a listener that flaps. Run from a copy of the repository's tree. Exit status:
0 every row passed; 1 a row stopped; 3 the rig broke.
"""
import argparse
import json
import os
import re
import statistics
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(HERE))))
sys.path.insert(0, os.path.join(ROOT, "tests", "e2e", "v11_rig"))
from rig import Rig, RigBroken, in_sql_string  # noqa: E402

PLAIN, PROD = "RIGPLAIN", "V11Rig.Plain"
RETRY, NORETRY = "Retry Out", "NoRetry Out"
PORT = {RETRY: 7711, NORETRY: 7712}
IN = {RETRY: 7611, NORETRY: 7612}
ALERT_SOURCE = os.path.join(ROOT, "src", "Shutter", "Intake", "AlertProcess.cls")
TRIES = 20

tag = time.strftime("%H%M%S")
results = []


# ---- Verdicts: pure, with table tests in test_proof_a.py ----

def head_carriers(stuck_header, status, oldest_delivered, active_message):
    """Which of the three readings named the stuck message's header. Status names no message, so it carries the head only as
    the word Retry beside one of the others; the list says which held the id."""
    out = []
    if stuck_header and str(oldest_delivered) == str(stuck_header):
        out.append("oldest Delivered header")
    if stuck_header and str(active_message) == str(stuck_header):
        out.append("ActiveMessage")
    if out and status == "Retry":
        out.append("Status (Retry)")
    return out


def per_minute(samples):
    """samples: [(seconds since start, value)] -> {minute: sorted distinct values}, minute 0 being the first 60 s."""
    out = {}
    for at, v in samples:
        out.setdefault(int(at // 60), set()).add(v)
    return {m: sorted(vs) for m, vs in out.items()}


def card_word(readings):
    """The card's word for a no-retry receiver once its listener is back, from the watch's readings over the window: the last
    one, and whether it moved. down or cant_tell are the design's two candidates; anything else is named as it is."""
    if not readings:
        return "no reading"
    return readings[-1]


def trace_line(source_text, trace_text):
    """The line of AlertProcess.cls whose $$$TRACE wrote this trace text: its fixed words are matched, the variable parts
    ("Alert from " _ source _ ...) taken as anything. 0 when none matches."""
    for n, line in enumerate(source_text.splitlines(), 1):
        m = re.search(r'\$\$\$TRACE\((.*)\)\s*$', line.strip())
        if not m:
            continue
        pieces = re.findall(r'"((?:[^"]|"")*)"', m.group(1))
        if not pieces:
            continue
        pattern = ".*".join(re.escape(p.replace('""', '"')) for p in pieces)
        if re.search(pattern, trace_text):
            return n
    return 0


def first_order(heard, a, b):
    """Which of two control ids a receiver heard first: a, b, or '' when it heard neither."""
    ia = heard.index(a) if a in heard else None
    ib = heard.index(b) if b in heard else None
    if ia is None and ib is None:
        return ""
    if ib is None or (ia is not None and ia < ib):
        return a
    return b


# ---- Reporting ----

def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


def note(text):
    print(f"        {text}", flush=True)


def verdict(row, ok, reading, decision):
    word = "PASS" if ok else "STOP"
    results.append((row, word, reading, decision))
    print(f"  {word}  row {row}: {reading}\n        decision: {decision}", flush=True)


# ---- Reads of Shutter's store and the engine ----

class Store:
    def __init__(self, r):
        self.r = r

    def declare(self):
        entries = []
        for n in (RETRY, NORETRY):
            entries.append({"name": n, "system": "Made-up LIMS", "category": "orders_results", "tier": 3, "watch": {"namespace": PLAIN, "item": n}, "runbook": "start the listener", "call": "01632 960123", "approvers": ["duty approver"]})
        path = self.r.put_file(json.dumps({"receivers": entries}).encode(), "proof-a-profile.json")
        out = self.r.session("SHUTTER", f'''Set s=##class(%Stream.FileCharacter).%New() Do s.LinkToFile("{path}") Set p=##class(Shutter.Store.SiteProfile).Current() Set d={{}}.%FromJSON(s) Set p.receivers=d.receivers Set sc=##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(),"the tier A proof","the check") Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!''')
        if "<<<ok>>>" not in out:
            raise RigBroken("the profile was refused: " + out[-500:])

    def outages(self, receiver, everything=False, after=0):
        where = f"Receiver='{in_sql_string(receiver)}' AND ID>{int(after)}" + ("" if everything else " AND State<>'closed'")
        code = f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM Shutter_Store.Outage WHERE {where} ORDER BY ID") While rs.%Next() {{ Write !,"<<<",##class(Shutter.Store.Outage).%OpenId(rs.%Get("ID")).ToJSON().%ToJSON(),">>>",! }}"""
        return [json.loads(x) for x in self.r.read_rows("SHUTTER", code)]

    def outage(self, oid):
        return self.r.obj("SHUTTER", f"##class(Shutter.Store.Outage).%OpenId({oid}).ToJSON().%ToJSON()")

    def events(self, oid):
        return json.loads(self.r.value("SHUTTER", f"##class(Shutter.Store.OutageEvent).Of({oid}).%ToJSON()"))

    def close_all(self, receiver):
        for o in self.outages(receiver):
            self.r.session("SHUTTER", f'Set sc=##class(Shutter.Store.Outage).%OpenId({o["id"]}).Close("the proof goes on","the check") Write:\'sc $SYSTEM.Status.GetErrorText(sc)')

    def reading(self, receiver):
        return self.r.obj("SHUTTER", f'##class(Shutter.Store.ReceiverReading).Last("{receiver}").%ToJSON()')

    def _max(self, table, ns):
        rows = self.r.read_rows(ns, f'''Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT MAX(ID) AS n FROM {table}") If rs.%SQLCODE<0 {{ Write !,"<<<read failed|",rs.%SQLCODE," ",rs.%Message,">>>",! }} Do rs.%Next() Write !,"<<<",+rs.%Get("n"),">>>",!''')
        return int(rows[-1])

    def cases(self, receiver, after):
        code = f'''Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT CaseId, State, FailureKind, OpenedAt, OriginHeaderId FROM Shutter_Store.""Case"" WHERE Receiver = ? AND SourceNamespace = ? AND ID > ? ORDER BY ID","{receiver}","{PLAIN}",{int(after)}) If rs.%SQLCODE<0 {{ Write !,"<<<read failed|",rs.%SQLCODE," ",rs.%Message,">>>",! }} While rs.%Next() {{ Write !,"<<<",rs.%Get("CaseId"),"|",rs.%Get("State"),"|",rs.%Get("FailureKind"),"|",rs.%Get("OpenedAt"),"|",rs.%Get("OriginHeaderId"),">>>",! }}'''
        out = []
        for row in self.r.read_rows("SHUTTER", code):
            cid, state, kind, opened, origin = row.split("|", 4)
            out.append({"caseId": cid, "state": state, "kind": kind, "openedAt": opened, "origin": origin})
        return out


def jobs_active(r, item):
    """Ens.Job:Enumerate's rows for the item: [{column: value}], every column the build gives."""
    code = f'''Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate") Set sc=rs.Execute() If 'sc {{ Write !,"<<<read failed|",$SYSTEM.Status.GetErrorText(sc),">>>",! }} While rs.Next() {{ If rs.Get("ConfigName")="{item}" {{ Set l="" For i=1:1:rs.GetColumnCount() {{ Set l=l_$SELECT(i>1:$CHAR(1),1:"")_rs.GetColumnName(i)_"="_rs.GetData(i) }} Write !,"<<<",l,">>>",! }} }}'''
    out = []
    for row in r.read_rows(PLAIN, code):
        out.append(dict(p.split("=", 1) for p in row.split("\x01") if "=" in p))
    return out


def oldest_delivered(r, item):
    found = [h for h in r.headers(PLAIN, item) if h["status"] == "Delivered"]
    return found[0]["id"] if found else ""


def qn(r, item):
    return int(r.value(PLAIN, f'##class(Ens.Queue).GetCount("{item}")+0'))


def down(r, port):
    if r.listening(port):
        r.listener_down(port)


def up(r, port, spec=None):
    down(r, port)
    r.listener_up(port, spec or {"mode": "up"})


def fresh(r, s, item, spec=None):
    """The listener answering AA until the engine has nothing queued or in hand for the item, then as asked: the queue count
    leaves out the message being tried, so a header still Delivered is waited out too."""
    up(r, PORT[item])
    r.wait_until(lambda: qn(r, item) == 0 and not oldest_delivered(r, item), 180)
    if spec:
        r.listener_spec(PORT[item], spec)
    time.sleep(6)
    s.close_all(item)
    time.sleep(4)


def header_of(r, item, control):
    for h in r.headers(PLAIN, item):
        if h["control"] == control:
            return h
    return {}


# ---- Row 9 then row 2: the blip, and the receiver idle once it is back ----

def row9_and_2(r, s):
    step("Row 9 (a 30 s blip at a no-retry receiver) and row 2 (FailureTimeout 0, idle, listener back, 2 minutes)")
    fresh(r, s, NORETRY)
    before = s._max("Shutter_Store.Outage", "SHUTTER")
    connects_before = len([e for e in r.events(PORT[NORETRY]) if e.get("event") != "frame"])
    down(r, PORT[NORETRY])
    t0 = time.time()
    sent = [f"B{tag}{i}" for i in range(1, 4)]
    for x in sent:
        r.send(IN[NORETRY], r.order(x), x)
    r.wait_until(lambda: header_of(r, NORETRY, sent[0]).get("status") == "Error", 40, 0.5)
    failed_at = time.time()
    r.wait_until(lambda: len(s.outages(NORETRY, after=before)) >= 1, 30, 0.5)
    opened_at = time.time()
    rows = s.outages(NORETRY, after=before)
    took = opened_at - failed_at
    note(f"first header Error {failed_at - t0:.1f} s after the first send; the outage seen {took:.1f} s after that; rows {[(o['id'], o['state'], o['kind']) for o in rows]}")
    r.wait_until(lambda: time.time() - t0 >= 30, 40, 1)
    up(r, PORT[NORETRY])
    back = time.time()
    statuses, readings, samples = [], [], []
    while time.time() - back < 120:
        h = r.host(PLAIN, NORETRY)
        rd = s.reading(NORETRY)
        at = time.time() - back
        statuses.append((at, f"{h.get('status')} / {h.get('adapter_state')}"))
        readings.append(rd.get("reading"))
        samples.append((round(at), h.get("status"), h.get("adapter_state"), rd.get("reading")))
        time.sleep(10)
    connects = [e for e in r.events(PORT[NORETRY]) if e.get("event") != "frame"][connects_before:]
    frames = [f for f in r.frames(PORT[NORETRY]) if f.get("ctl") in sent]
    note("row 2 samples (seconds after the listener came back, Status, AdapterState, the watch's reading):")
    for x in samples:
        note(f"  {x}")
    note(f"row 2 by minute: {per_minute(statuses)}")
    note(f"connection events at the listener after it came back: {len(connects)} {[e.get('event') for e in connects][:10]}; frames of the three: {len(frames)}")
    ok9 = len(rows) == 1 and took <= 10
    verdict(9, ok9, f"one outage {'opened' if rows else 'did not open'}, {took:.1f} s after the first never-opened Error header (limit 10 s); rows {len(rows)}",
            "a short outage at a no-retry receiver is caught on the first failed header, so the 30 s rule is not what a blip needs" if ok9 else "the blip is not caught in time: the design's no-retry opening rule must change")
    word = card_word(readings)
    status_end = samples[-1][1] if samples else ""
    dialled = len(connects) > 0
    ok2 = word in ("down", "cant_tell") and not frames
    verdict(2, ok2, f"Status read {sorted(set(x[1] for x in samples))}, AdapterState {sorted(set(x[2] for x in samples))}, Status at 2 minutes {status_end!r}; the watch's reading {sorted(set(readings))}, last {word!r}; the idle operation {'dialled' if dialled else 'did not dial'} ({len(connects)} connection events); nothing resent ({len(frames)} frames of the three)",
            f"the card's word at a no-retry receiver whose listener is back is {word!r}" + (" ('can't tell': the engine does not show the return)" if word == "cant_tell" else "") + (f"; Status stays Error on a quiet feed, so no rule may wait for Status OK there" if status_end == "Error" else f"; Status came back to {status_end!r} on a quiet feed because the idle operation {'dialled' if dialled else 'reconnected'}, so Status OK there says the connection opened, not that any message went"))
    s.close_all(NORETRY)


# ---- Row 3: one refusal at FailureTimeout 0, then silence ----

def row3(r, s):
    step("Row 3: one AR at FailureTimeout 0, then silence, Status for 2 minutes")
    fresh(r, s, NORETRY, {"mode": "answer", "code": "AR", "words": "Made-up refusal"})
    before = s._max("Shutter_Store.Outage", "SHUTTER")
    control = f"R3{tag}"
    r.send(IN[NORETRY], r.order(control), control)
    r.wait_until(lambda: header_of(r, NORETRY, control).get("status") == "Error", 40, 1)
    t0 = time.time()
    samples = []
    while time.time() - t0 < 120:
        h = r.host(PLAIN, NORETRY)
        samples.append((round(time.time() - t0), h.get("status"), h.get("adapter_state"), s.reading(NORETRY).get("reading")))
        time.sleep(15)
    opened = s.outages(NORETRY, everything=True, after=before)
    for x in samples:
        note(f"  {x}")
    statuses = sorted(set(x[1] for x in samples))
    ok = opened == []
    verdict(3, ok, f"header {header_of(r, NORETRY, control).get('status')}; Status over 2 minutes {statuses}; readings {sorted(set(x[3] for x in samples))}; outages opened {len(opened)}",
            ("Status Error " + ("is" if "Error" in statuses else "is not") + " sticky after one refusal, and the watch opens nothing on it: one refusal on a quiet feed is the last message failing, not an outage") if ok else "one refusal opened an outage: the watch's rule for Status Error must need Retry or an active message")
    up(r, PORT[NORETRY])
    s.close_all(NORETRY)


# ---- Row 4: which reading carries the head ----

def head_loop(r, s, spec, label, seconds):
    fresh(r, s, RETRY, spec)
    control = f"H4{label[0]}{tag}"
    r.send(IN[RETRY], r.order(control), control)
    r.wait_until(lambda: header_of(r, RETRY, control).get("status") in ("Delivered", "Error"), 30, 1)
    stuck = header_of(r, RETRY, control).get("id", "")
    t0 = time.time()
    seen = []
    while time.time() - t0 < seconds:
        h = r.host(PLAIN, RETRY)
        active = ",".join(sorted({j.get("ActiveMessage", "") for j in jobs_active(r, RETRY)} - {""}))
        oldest = oldest_delivered(r, RETRY)
        rd = s.reading(RETRY)
        carriers = head_carriers(stuck, h.get("status"), oldest, active)
        seen.append({"at": round(time.time() - t0), "status": h.get("status"), "adapter": h.get("adapter_state"), "active": active, "oldest": oldest, "watchHead": rd.get("headHeaderId"), "reading": rd.get("reading"), "carriers": carriers})
        time.sleep(10)
    for x in seen:
        note(f"  {label}: {x}")
    up(r, PORT[RETRY])
    return stuck, seen


def row4(r, s):
    step("Row 4: Status, AdapterState, Ens.Job:Enumerate and the oldest Delivered header through an AR loop and a read-timeout loop at -1")
    stuck_ar, ar = head_loop(r, s, {"mode": "answer", "code": "AR", "words": "Made-up refusal"}, "AR loop", 70)
    s.close_all(RETRY)
    stuck_rt, rt = head_loop(r, s, {"mode": "hang"}, "read-timeout loop", 110)
    s.close_all(RETRY)

    def summary(seen):
        names = {}
        for x in seen:
            for c in x["carriers"]:
                names[c] = names.get(c, 0) + 1
        return names, len(seen)

    a, na = summary(ar)
    t, nt = summary(rt)
    ok = bool(a) and bool(t)
    verdict(4, ok, f"AR loop (header {stuck_ar}): carried by {a} of {na} reads; read-timeout loop (header {stuck_rt}): carried by {t} of {nt} reads; Status read {sorted({x['status'] for x in ar})} and {sorted({x['status'] for x in rt})}",
            ("the head is read from " + ", ".join(sorted(set(a) & set(t)) or sorted(set(a) | set(t))) + "; Status names no message and is only the word beside it") if ok else "no reading carried the head in one of the loops: the card cannot name the head message there")


# ---- Row 12: a header completed after retries keeps its rows ----

def row12(r, s):
    step("Row 12: a header Completed after retries: whether its earlier rows survive")
    fresh(r, s, RETRY)
    down(r, PORT[RETRY])
    control = f"C7{tag}"
    r.send(IN[RETRY], r.order(control), control)
    r.wait_until(lambda: bool(header_of(r, RETRY, control)), 20, 1)
    h = header_of(r, RETRY, control)
    session = r.value(PLAIN, f'##class(Ens.MessageHeader).%OpenId({h["id"]}).SessionId')
    r.wait_until(lambda: len([x for x in r.log_rows(PLAIN, RETRY) if x["session"] == session and x["type"] == "Error"]) >= 1, 60, 2)
    time.sleep(20)
    rows_before = [x for x in r.log_rows(PLAIN, RETRY) if x["session"] == session]
    up(r, PORT[RETRY])
    r.wait_until(lambda: header_of(r, RETRY, control).get("status") == "Completed", 90, 1)
    time.sleep(5)
    h = header_of(r, RETRY, control)
    rows_after = [x for x in r.log_rows(PLAIN, RETRY) if x["session"] == session]
    kept = {x["id"] for x in rows_before} <= {x["id"] for x in rows_after}
    errors = [x for x in rows_after if x["type"] == "Error"]
    note(f"before: {[(x['id'], x['type'], x['text'][:80]) for x in rows_before]}")
    note(f"after:  {[(x['id'], x['type'], x['text'][:80]) for x in rows_after]}")
    note(f"header {h.get('status')}, description {h.get('description')!r}")
    ok = h.get("status") == "Completed" and kept and bool(errors)
    verdict(12, ok, f"header {h.get('status')} ({h.get('description')!r}); {len(rows_before)} rows of its session before the return, {len(rows_after)} after, every earlier row {'kept' if kept else 'NOT kept'}, {len(errors)} Error rows",
            "a Completed header's earlier attempt rows stay in Ens_Util.Log, so the close can say a drained message was attempted before (and may have reached the receiver more than once); the rows are retained evidence, not a count" if ok else "the earlier rows do not survive, so a drained message's history must come from the header's description alone")
    s.close_all(RETRY)


# ---- Row 13: an arrival between the check and the enqueue ----

def row13(r, s):
    step(f"Row 13: a message for the patient arriving between a check and an EnQueue, {TRIES} tries")
    fresh(r, s, NORETRY)
    down(r, PORT[NORETRY])
    origins = [f"O{tag}{i}" for i in range(1, TRIES + 1)]
    arrivals = [f"A{tag}{i}" for i in range(1, TRIES + 1)]
    patients = [f"MRNP{tag}{i}" for i in range(1, TRIES + 1)]
    for c, p in zip(origins, patients):
        r.send(IN[NORETRY], r.order(c, p), c)
    r.wait_until(lambda: all(header_of(r, NORETRY, c).get("status") == "Error" for c in origins), 300, 3)
    heads = {c: header_of(r, NORETRY, c) for c in origins}
    if not all(h.get("status") == "Error" for h in heads.values()):
        raise RigBroken(f"the origins did not all fail: {[(c, h.get('status')) for c, h in heads.items()]}")
    up(r, PORT[NORETRY])
    time.sleep(3)
    for a, p in zip(arrivals, patients):
        r.put_file(r.order(a, p), f"{a}.hl7")
    window, rows = [], []
    for i, (c, a) in enumerate(zip(origins, arrivals)):
        origin = heads[c]["id"]
        path = f"/tmp/v11_site/{a}.hl7"
        code = f'''Set t0=$ZH Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT MAX(ID) AS n FROM Ens.MessageHeader WHERE TargetConfigName='NoRetry Out' AND ID > ?",{origin}) Do rs.%Next() Set seen=+rs.%Get("n") Set t1=$ZH
Set rc=$ZF(-100,"/SHELL /STDOUT=""/tmp/v11_site/arrive.out""","python3","/tmp/v11_site/mllp_send.py",{IN[NORETRY]},"{path}","20") Set t2=$ZH
Set sc=##class(Ens.MessageHeader).ResendDuplicatedMessage({origin},.new,"NoRetry Out") Set t3=$ZH
Write !,"<<<",seen,"|",$FNUMBER(t1-t0*1000,"",3),"|",$FNUMBER(t2-t1*1000,"",3),"|",$FNUMBER(t3-t2*1000,"",3),"|",$GET(new),"|",rc,"|",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!'''
        found = r.read_rows(PLAIN, code)
        seen, check_ms, arrive_ms, enqueue_ms, new, rc, sc = found[-1].split("|", 6)
        if sc != "ok" or rc != "0":
            raise RigBroken(f"try {i + 1}: the arrival exited {rc}, the resend answered {sc}")
        rows.append({"origin": c, "arrival": a, "checkSawUpTo": int(seen), "checkMs": float(check_ms), "arrivalMs": float(arrive_ms), "enqueueMs": float(enqueue_ms), "resent": new})
        r.wait_until(lambda: qn(r, NORETRY) == 0, 30, 0.5)
    # The window itself, with nothing put in it: from the end of the check to the end of the resend's enqueue.
    for i in range(TRIES):
        code = f'''Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n FROM Ens.MessageHeader WHERE TargetConfigName='NoRetry Out' AND ID > ?",{heads[origins[i]]["id"]}) Do rs.%Next() Set t1=$ZH Set sc=##class(Ens.MessageHeader).ResendDuplicatedMessage({heads[origins[i]]["id"]},.new,"NoRetry Out") Set t3=$ZH Write !,"<<<",$FNUMBER(t3-t1*1000,"",3),">>>",!'''
        window.append(float(r.read_rows(PLAIN, code)[-1]))
        r.wait_until(lambda: qn(r, NORETRY) == 0, 30, 0.5)
    time.sleep(5)
    heard = r.heard(PORT[NORETRY])
    first = [first_order(heard, x["arrival"], x["origin"]) for x in rows]
    arrival_first = sum(1 for x, f in zip(rows, first) if f == x["arrival"])
    origin_first = sum(1 for x, f in zip(rows, first) if f == x["origin"])
    hids = {}
    for h in r.headers(PLAIN, NORETRY):
        hids.setdefault(h["control"], []).append(int(h["id"]))
    # The check stands in for the patient check: the newest header to the item it could see. The arrival is unseen by it when the
    # arrival's own header is newer than that.
    unseen = sum(1 for x in rows if hids.get(x["arrival"]) and min(hids[x["arrival"]]) > x["checkSawUpTo"])
    enq_first = sum(1 for x in rows if hids.get(x["arrival"]) and int(x["resent"] or 0) and min(hids[x["arrival"]]) < int(x["resent"]))
    note(f"tries (newest header the check saw, check ms, arrival ms, enqueue ms): {[(x['checkSawUpTo'], x['checkMs'], x['arrivalMs'], x['enqueueMs']) for x in rows]}")
    note(f"the window with nothing in it (ms from the end of the check to the resend enqueued): median {statistics.median(window):.2f}, max {max(window):.2f}")
    note(f"the arrival's header made before the resend's in {enq_first} of {TRIES}; the check saw no arrival in {unseen} of {TRIES}")
    ok = arrival_first + origin_first == TRIES
    verdict(13, ok, f"with an arrival put in the window: the newer message reached the receiver first in {arrival_first} of {TRIES} tries, the older resend first in {origin_first}; the check saw the arrival in {TRIES - unseen} of {TRIES}; the window itself is {statistics.median(window):.1f} ms (median), {max(window):.1f} ms at most, over {TRIES}",
            ("an arrival before the enqueue goes ahead of the resend, unseen by the check, as the stock reading said: the window runs the other way from 'it sits behind', is milliseconds wide here, and a send must re-read after it and state any newer header that went first" if arrival_first else "the resend went first even with an arrival in the window: the queue order the design assumed holds here") if ok else "the receiver did not hear both messages of every try: the measurement is incomplete")
    s.close_all(NORETRY)


# ---- Row 15: the inactivity alert, and a flap ----

def trace_events(r, item, on):
    """LogTraceEvents is an attribute of the production's item, not one of its settings: set it, save, and update."""
    code = f'''Set p=##class(Ens.Config.Production).%OpenId("{PROD}") Set it="" For i=1:1:p.Items.Count() {{ If p.Items.GetAt(i).Name="{item}" {{ Set it=p.Items.GetAt(i) }} }}
If '$ISOBJECT(it) {{ Write !,"<<<no item>>>",! }} Else {{ Set it.LogTraceEvents={1 if on else 0} Set sc=p.%Save() Set:sc sc=p.SaveToClass() Set:sc sc=##class(Ens.Director).UpdateProduction(60,1) Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),"|",it.LogTraceEvents,">>>",! }}'''
    found = r.rows(PLAIN, code)
    if found != [f"ok|{1 if on else 0}"]:
        raise RigBroken(f"LogTraceEvents on {item} did not take: {found}")


def alerts_since(r, item, after):
    code = f'''Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID, SessionId, AlertText FROM Ens.AlertRequest WHERE ID > ? AND SourceConfigName = ? ORDER BY ID",{int(after)},"{item}") If rs.%SQLCODE<0 {{ Write !,"<<<read failed|",rs.%SQLCODE," ",rs.%Message,">>>",! }} While rs.%Next() {{ Write !,"<<<",rs.%Get("ID"),"|",rs.%Get("SessionId"),"|",$TRANSLATE($EXTRACT(rs.%Get("AlertText"),1,200),"|"_$CHAR(10,13),"   "),">>>",! }}'''
    out = []
    for row in r.read_rows(PLAIN, code):
        aid, session, text = row.split("|", 2)
        out.append({"id": int(aid), "session": session, "text": text})
    return out


def row15_inactivity(r, s):
    step("Row 15, first part: an operation's inactivity alert while its outage is open")
    fresh(r, s, NORETRY)
    with open(ALERT_SOURCE, encoding="utf-8") as f:
        source = f.read()
    trace_events(r, "Ens.Alert", True)
    try:
        down(r, PORT[NORETRY])
        control = f"I15{tag}"
        r.send(IN[NORETRY], r.order(control), control)
        r.wait_until(lambda: len(s.outages(NORETRY)) == 1 and s.outages(NORETRY)[0]["state"] in ("needs_person", "open"), 60, 1)
        time.sleep(15)
        up(r, PORT[NORETRY])
        o = s.outages(NORETRY)
        if len(o) != 1:
            raise RigBroken(f"no single outage for the inactivity part: {o}")
        oid = o[0]["id"]
        events_before = [e["kind"] for e in s.events(oid)]
        state_before = s.outage(oid)["state"]
        case_mark = s._max('Shutter_Store.""Case""', "SHUTTER")
        log_mark = s._max("Ens_Util.Log", PLAIN)
        alert_mark = s._max("Ens.AlertRequest", PLAIN)
        r.set_item(PLAIN, PROD, NORETRY, InactivityTimeout=20)
        r.wait_until(lambda: any("nactiv" in a["text"] for a in alerts_since(r, NORETRY, alert_mark)), 150, 5)
        time.sleep(15)
        alerts = [a for a in alerts_since(r, NORETRY, alert_mark) if "nactiv" in a["text"]]
        traces = [x for x in r.log_rows(PLAIN, "Ens.Alert") if int(x["id"]) > log_mark and NORETRY in x["text"]]
        lines = sorted({trace_line(source, x["text"]) for x in traces})
        cases = s.cases(NORETRY, case_mark)
        row = s.outage(oid)
        events_after = [e["kind"] for e in s.events(oid)]
        host = r.host(PLAIN, NORETRY)
        note(f"inactivity alerts: {alerts}")
        note(f"Ens.Alert's trace rows for it: {[(x['type'], x['text'][:120]) for x in traces]}; AlertProcess.cls lines {lines}")
        note(f"Status {host.get('status')!r}, the watch's reading {s.reading(NORETRY).get('reading')!r}; cases since: {cases}")
        note(f"outage {oid}: state {state_before} -> {row['state']}, events {events_before} -> {events_after}, row alerts {[(a.get('at'), a.get('kind')) for a in row.get('alerts', [])][-4:]}")
        new_outages = [x for x in s.outages(NORETRY, everything=True) if x["id"] != oid and x["state"] != "closed"]
        with_session = [a for a in alerts if a["session"] not in ("", "0")]
        ok = bool(alerts) and not cases and row["state"] == state_before and events_after == events_before and not new_outages
        verdict("15a", ok, f"{len(alerts)} inactivity alert(s), {'carrying a session' if with_session else 'session-less'}; stopped at AlertProcess.cls line(s) {lines or 'not traced'}; cases opened {len(cases)}; the outage's state {state_before} -> {row['state']}, events {'unmoved' if events_after == events_before else 'MOVED'}; second outages {len(new_outages)}",
                ("the inactivity alert is session-less, stops before any case is made and leaves the outage record alone: the card's line that the site's inactivity alert makes no case holds as measured" if not with_session else "the inactivity alert carries a session: it is the queue wait alert's shape, once per session") if ok else ("no inactivity alert came within 150 s: the row is unmeasured on this build" if not alerts else "the inactivity alert opened a case or moved the outage: the design's words on the site's alerts must change"))
    finally:
        r.set_item(PLAIN, PROD, NORETRY, InactivityTimeout=0)
        trace_events(r, "Ens.Alert", False)
        s.close_all(NORETRY)


def row15_flap(r, s):
    step("Row 15, second part: the listener down and up three times over 5 minutes, at a retrying item with QueueWaitAlert and at a no-retry item with AlertOnError on")
    fresh(r, s, RETRY)
    fresh(r, s, NORETRY)
    r.set_item(PLAIN, PROD, RETRY, QueueWaitAlert=30, AlertOnError=0)
    try:
        case_mark = s._max('Shutter_Store.""Case""', "SHUTTER")
        out_mark = s._max("Shutter_Store.Outage", "SHUTTER")
        sent = {RETRY: [], NORETRY: []}
        t0 = time.time()
        n = 0
        plan = [(0, "down"), (80, "up"), (100, "down"), (180, "up"), (200, "down"), (280, "up"), (300, "end")]
        done = set()
        while time.time() - t0 < 300:
            at = time.time() - t0
            for when, act in plan:
                if when <= at and when not in done:
                    done.add(when)
                    for item in (RETRY, NORETRY):
                        (down if act == "down" else up)(r, PORT[item])
                    note(f"{at:.0f} s: listeners {act}")
            n += 1
            for item, short in ((RETRY, "FR"), (NORETRY, "FN")):
                x = f"{short}{tag}{n}"
                r.send(IN[item], r.order(x), x)
                sent[item].append(x)
            time.sleep(10)
        for item in (RETRY, NORETRY):
            up(r, PORT[item])
        r.wait_until(lambda: qn(r, RETRY) == 0, 300, 5)
        r.wait_until(lambda: all(o["state"] in ("closed", "needs_person") for o in s.outages(RETRY, everything=True, after=out_mark) + s.outages(NORETRY, everything=True, after=out_mark)), 300, 5)
        time.sleep(10)
        lines, why = [], []
        ok = True
        for item in (RETRY, NORETRY):
            rows = s.outages(item, everything=True, after=out_mark)
            cases = s.cases(item, case_mark)
            linked = set()
            for o in rows:
                linked |= {x["caseId"] for x in s.outage(o["id"]).get("linkedCases", [])}
            kinds = [[e["kind"] for e in s.events(o["id"])] for o in rows]
            errors = len([h for h in r.headers(PLAIN, item) if h["control"] in sent[item] and h["status"] == "Error"])
            unlinked = [c["caseId"] for c in cases if c["caseId"] not in linked]
            note(f"{item}: outages {[(o['id'], o['state'], o['kind']) for o in rows]}, events {kinds}")
            note(f"{item}: {len(sent[item])} sent, {errors} ended Error, {len(cases)} cases {[(c['caseId'], c['kind'], c['state']) for c in cases]}, unlinked {unlinked}")
            moved_by_alert = [k for ks in kinds for k in ks if "alert" in k.lower()]
            good = len(rows) == 1 and not unlinked and not moved_by_alert
            ok = ok and good
            flips = sum(ks.count("kind") for ks in kinds)
            per_row = [len([c for c in cases if c["caseId"] in {x["caseId"] for x in s.outage(o["id"]).get("linkedCases", [])}]) for o in rows]
            lines.append(f"{item}: {len(rows)} outage row(s) (events {[[k for k in ks if k != 'kind'] for ks in kinds]}, {flips} kind changes), {len(cases)} case(s) opened, {len(cases) - len(unlinked)} linked ({per_row} per row), {len(unlinked)} unlinked, events naming an alert {len(moved_by_alert)}")
            if len(rows) > 1:
                why.append(f"at {item} each up window drained the queue and the row closed, so each down opened a new row ({len(rows)} in 5 minutes)")
            if unlinked:
                why.append(f"at {item} {len(unlinked)} cases opened after the row's close judgement are linked to no row: the link is made once, at closing")
            if moved_by_alert:
                why.append(f"at {item} an event names an alert")
        verdict("15b", ok, "; ".join(lines),
                "a flapping listener stays one outage per receiver and every case the site's alerts open is linked to it; the number of cases is as measured here, which the card says instead of 'one per outage'" if ok else "; ".join(why) + ". No event named an alert, so the alerts did not move the record; the card's 'one outage' and 'every case linked' do not hold over a flap as built")
    finally:
        r.set_item(PLAIN, PROD, RETRY, QueueWaitAlert=0, AlertOnError=1)
        for item in (RETRY, NORETRY):
            up(r, PORT[item])
        s.close_all(RETRY)
        s.close_all(NORETRY)


ROWS = (("9", row9_and_2), ("3", row3), ("4", row4), ("12", row12), ("13", row13), ("15", row15_inactivity), ("15", row15_flap))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ctr", required=True)
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--image", required=True)
    p.add_argument("--module", default="")
    p.add_argument("--keep", action="store_true")
    p.add_argument("--reuse", action="store_true")
    p.add_argument("--only", default="", help="rows, comma-separated: 9 (with 2), 3, 4, 12, 13, 15")
    a = p.parse_args()
    r = Rig(a.ctr, a.port, a.image, a.module, ROOT)
    s = Store(r)
    want = set(a.only.split(",")) if a.only else None
    try:
        if not a.reuse:
            step("Installing")
            r.start()
            r.install()
        s.declare()
        for name, fn in ROWS:
            if want and name not in want and not (name == "9" and "2" in want):
                continue
            fn(r, s)
        r.prove_sign_out()
    except RigBroken as e:
        print(f"RIG BROKEN: {e}", flush=True)
        sys.exit(3)
    finally:
        if not a.keep:
            r.remove()
    print("\nResults", flush=True)
    for row, word, reading, decision in results:
        print(f"  {word}  row {row}: {reading}\n        decision: {decision}", flush=True)
    sys.exit(0 if all(w == "PASS" for _, w, _, _ in results) else 1)


if __name__ == "__main__":
    main()
