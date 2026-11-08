#!/usr/bin/env python3
"""The Receiver Watch on a real instance: what each reading is, when an outage opens and when it doesn't, reading the store
directly, since the routes are another part's. Every receiver is a fake on the loopback address of a test instance.

    python3 tests/e2e/v11_rig/watch/check_watch.py --ctr NAME --port PORT --image IMAGE [--module core] [--keep] [--reuse]

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
RETRY, NORETRY, BOUNDED, ONESHOT = "Retry Out", "NoRetry Out", "Bounded Out", "OneShot Out"
PORT = {RETRY: 7711, NORETRY: 7712, BOUNDED: 7713, ONESHOT: 7714}
IN = {RETRY: 7611, NORETRY: 7612, BOUNDED: 7613, ONESHOT: 7614}
RECEIVERS = (RETRY, NORETRY, ONESHOT)
STOCK_ACTIONS = ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C"

failed, passed = [], 0
tag = time.strftime("%H%M%S")


def check(name, ok, detail=""):
    global passed
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {str(detail)[:1500]}"), flush=True)
    if ok:
        passed += 1
    else:
        failed.append(name)


def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


class Watch:
    def __init__(self, r):
        self.r = r

    def reading(self, receiver):
        return self.r.obj("SHUTTER", f'##class(Shutter.Store.ReceiverReading).Last("{receiver}").%ToJSON()')

    def outages(self, receiver):
        """Rows of this receiver that are not closed."""
        code = f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM Shutter_Store.Outage WHERE Receiver='{receiver}' AND State<>'closed' ORDER BY ID") While rs.%Next() {{ Write !,"<<<",##class(Shutter.Store.Outage).%OpenId(rs.%Get("ID")).ToJSON().%ToJSON(),">>>",! }}"""
        return [json.loads(x) for x in self.r.read_rows("SHUTTER", code)]

    def counts(self):
        code = """For t="ReceiverReading","Outage","OutageEvent" { Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n FROM Shutter_Store."_t) Do rs.%Next() Write !,"<<<",t,"|",rs.%Get("n"),">>>",! }"""
        return dict(x.split("|") for x in self.r.read_rows("SHUTTER", code))

    def close_all(self, receiver):
        for o in self.outages(receiver):
            self.r.session("SHUTTER", f'Set sc=##class(Shutter.Store.Outage).%OpenId({o["id"]}).Close("the check goes on","the check") Write:\'sc $SYSTEM.Status.GetErrorText(sc)')

    def declare(self, names, items=None, runbook="start the listener"):
        """items: a receiver's item where it isn't the receiver's own name."""
        items = items or {}
        receivers = ",".join(json.dumps({"name": n, "system": "Made-up LIMS", "category": "orders_results", "tier": 3, "watch": {"namespace": PLAIN, "item": items.get(n, n)}, "runbook": runbook, "call": "01632 960123"}) for n in names)
        text = '{"receivers":[' + receivers + "]}"
        path = self.r.put_file(text.encode(), "watch-profile.json")
        out = self.r.session("SHUTTER", f'''Set s=##class(%Stream.FileCharacter).%New() Do s.LinkToFile("{path}") Set p=##class(Shutter.Store.SiteProfile).Current() Set d={{}}.%FromJSON(s) Set p.receivers=d.receivers Set sc=##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(),"the watch check","the check") Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!''')
        if "<<<ok>>>" not in out:
            raise RigBroken("the profile was refused: " + out[-500:])

    def wait_reading(self, receiver, wanted, seconds, every=2):
        wanted = (wanted,) if isinstance(wanted, str) else wanted
        got = {}
        end = time.time() + seconds
        while time.time() < end:
            got = self.reading(receiver)
            if got.get("reading") in wanted:
                return got
            time.sleep(every)
        return got


def order(r, control):
    return r.order(control)


def fresh(r, w, receiver, spec=None):
    """A listener as asked, the queue empty and the receiver's outage closed, before a scenario. Headers of the last one stay."""
    port = PORT[receiver]
    if r.listening(port):
        r.listener_down(port)
    r.listener_up(port, spec or {"mode": "up"})
    r.wait_until(lambda: r.queue(PLAIN, receiver) == 0, 120)
    time.sleep(6)
    w.close_all(receiver)


def no_watch(r, w):
    step("No watch block: the item logs nothing, stores nothing and opens nothing")
    time.sleep(16)
    c = w.counts()
    check("no reading, outage or event is stored", c == {"ReceiverReading": "0", "Outage": "0", "OutageEvent": "0"}, c)
    logged = r.log_rows("SHUTTER", "Receiver Watch")
    check("the item logged nothing", [x for x in logged if x["type"] in ("Error", "Warning", "Alert")] == [], logged[:5])
    check("the item is running", any("Receiver Watch" in str(j) for j in r.jobs("SHUTTER")), r.jobs("SHUTTER"))


def retry_outage(r, w):
    step("A retry-forever outage: one outage within 30 s of polls, nothing sent, the reading down")
    if r.listening(PORT[RETRY]):
        r.listener_down(PORT[RETRY])
    sent = [f"W1{tag}{i}" for i in range(1, 7)]
    for c in sent:
        r.send(IN[RETRY], r.order(c), c)
    first = time.time()
    r.wait_until(lambda: w.reading(RETRY).get("reading") == "down", 60)
    down_at = time.time()
    early = w.outages(RETRY)
    check("not open before 30 s of polls", not early and time.time() - down_at < 25, early)
    r.wait_until(lambda: len(w.outages(RETRY)) >= 1, 60, 1)
    opened = w.outages(RETRY)
    took = time.time() - down_at
    print(f"        the reading went down {down_at - first:.0f} s after the first send; the outage opened {took:.0f} s after that", flush=True)
    check("exactly one outage, kind down", len(opened) == 1 and opened[0]["kind"] == "down", opened)
    check("it took about 30 s of polls", 20 <= took <= 50, took)
    one = opened[0]
    check("the row carries the site's lines", one["runbook"] == "start the listener" and one["call"] == "01632 960123", one)
    check("Recovery attempts by Shutter: 0", one["sentByShutter"] == 0, one)
    read = w.reading(RETRY)
    check("the reading is down", read["reading"] == "down" and read["retry"] == "unlimited" and read["queue"] >= 1, read)
    time.sleep(30)
    check("still one row after 30 s more", [o["id"] for o in w.outages(RETRY)] == [one["id"]], w.outages(RETRY))
    h = [x for x in r.headers(PLAIN, RETRY) if x["control"] in sent]
    check("zero sends: one header per message", len(h) == len(sent) and all(x["resent"] in ("", "0") for x in h), h)
    fresh_field_names(one)
    fresh(r, w, RETRY)
    check("every message then went by the engine, once", sorted(r.heard(PORT[RETRY])) == sorted(set(r.heard(PORT[RETRY]))) and set(sent) <= set(r.heard(PORT[RETRY])), r.heard(PORT[RETRY]))


def fresh_field_names(o):
    names = "id receiver namespace item state kind openedAt drainedAt closedAt runbook call approvers pausedUntil overdueAt readings window settled alerts lists openCases version set approvable approval sentByShutter acts words".split()
    check("a real row answers every field", all(n in o for n in names), [n for n in names if n not in o])
    check("set not computed, lists empty", o["set"]["status"] == "not_computed" and all(o["lists"][k] == [] for k in ("queued", "offered", "reached", "refused")), o)


def refusing(r, w):
    step("An AR loop at -1 reads refusing, with the head from the oldest Delivered header")
    fresh(r, w, RETRY, {"mode": "answer", "code": "AR", "words": "Made-up refusal"})
    w.wait_reading(RETRY, ("healthy",), 40)
    control = f"WAR{tag}"
    r.send(IN[RETRY], r.order(control), control)
    got = w.wait_reading(RETRY, "refusing", 60, 2)
    delivered = [x for x in r.headers(PLAIN, RETRY) if x["status"] == "Delivered"]
    check("reads refusing, not down", got.get("reading") == "refusing", got)
    check("the head is the oldest Delivered header", bool(delivered) and got.get("headHeaderId") == int(delivered[0]["id"]) or str(got.get("headHeaderId")) == (delivered[0]["id"] if delivered else None), (got, delivered))
    print(f"        Status {got.get('status')!r}, AdapterState {got.get('adapterState')!r}, ActiveMessage {got.get('activeMessage')!r}", flush=True)
    check("the job list's active message agrees with the head", str(got.get("activeMessage")) == str(got.get("headHeaderId")) and not got.get("why"), got)
    r.wait_until(lambda: len(w.outages(RETRY)) == 1, 15, 1)
    o = w.outages(RETRY)
    check("one outage, kind refusing", len(o) == 1 and o[0]["kind"] == "refusing", o)
    r.listener_spec(PORT[RETRY], {"mode": "up"})
    fresh(r, w, RETRY)


def hung(r, w):
    step("A hung listener reads not answering")
    fresh(r, w, RETRY, {"mode": "hang"})
    control = f"WHG{tag}"
    r.send(IN[RETRY], r.order(control), control)
    got = w.wait_reading(RETRY, "not_answering", 120, 2)
    print(f"        Status {got.get('status')!r}, AdapterState {got.get('adapterState')!r}, ActiveMessage {got.get('activeMessage')!r}", flush=True)
    check("reads not answering", got.get("reading") == "not_answering", got)
    r.wait_until(lambda: len(w.outages(RETRY)) == 1, 15, 1)
    o = w.outages(RETRY)
    check("one outage, kind not_answering", len(o) == 1 and o[0]["kind"] == "not_answering", o)
    seen = set()
    for _ in range(12):
        seen.add(w.reading(RETRY).get("reading"))
        time.sleep(5)
    print(f"        the readings over a further minute: {sorted(seen)}", flush=True)
    check("it does not fall back to healthy", "healthy" not in seen and "slow" not in seen, seen)
    r.listener_spec(PORT[RETRY], {"mode": "up"})
    fresh(r, w, RETRY)


def one_ar_then_silence(r, w):
    step("One AR at FailureTimeout 0, then silence, opens nothing")
    fresh(r, w, NORETRY, {"mode": "answer", "code": "AR", "words": "Made-up refusal"})
    w.wait_reading(NORETRY, "healthy", 40)
    control = f"WE2{tag}"
    r.send(IN[NORETRY], r.order(control), control)
    r.wait_until(lambda: any(x["control"] == control and x["status"] == "Error" for x in r.headers(PLAIN, NORETRY)), 30)
    time.sleep(45)
    got = w.reading(NORETRY)
    print(f"        Status {got.get('status')!r}, AdapterState {got.get('adapterState')!r}, reading {got.get('reading')!r}", flush=True)
    check("no outage", w.outages(NORETRY) == [], w.outages(NORETRY))
    check("reads healthy on the always-on line, the Status beside it", got.get("reading") == "healthy" and got.get("queue") == 0, got)


def quiet_no_retry(r, w):
    step("A quiet no-retry item, connected and OK, reads healthy")
    fresh(r, w, NORETRY)
    control = f"WOK{tag}"
    r.send(IN[NORETRY], r.order(control), control)
    got = w.wait_reading(NORETRY, "healthy", 40)
    time.sleep(12)
    got = w.reading(NORETRY)
    check("connected, OK and quiet: healthy", got.get("reading") == "healthy" and got.get("status") == "OK", got)
    check("nothing open", w.outages(NORETRY) == [], w.outages(NORETRY))


def blip(r, w):
    step("A blip at a no-retry receiver opens at once on the first never-opened Error header")
    r.listener_down(PORT[NORETRY])
    time.sleep(1)
    control = f"WB1{tag}"
    t0 = time.time()
    r.send(IN[NORETRY], r.order(control), control)
    r.wait_until(lambda: any(x["control"] == control and x["status"] == "Error" for x in r.headers(PLAIN, NORETRY)), 30, 1)
    failed_at = time.time()
    r.wait_until(lambda: len(w.outages(NORETRY)) >= 1, 25, 1)
    took = time.time() - failed_at
    o = w.outages(NORETRY)
    print(f"        the header failed {failed_at - t0:.0f} s after the send; the outage opened {took:.0f} s after that", flush=True)
    check("open, well inside the 30 s", len(o) == 1 and took < 15, (o, took))
    r.listener_up(PORT[NORETRY], {"mode": "up"})
    got = w.wait_reading(NORETRY, "cant_tell", 25)
    check("quiet with an outage open: can't tell", got.get("reading") == "cant_tell" and o[0]["sentByShutter"] == 0, got)
    check("nothing resent", r.heard(PORT[NORETRY]).count(control) == 0, r.heard(PORT[NORETRY]))
    w.close_all(NORETRY)
    time.sleep(12)
    check("the old header opens nothing again", w.outages(NORETRY) == [], w.outages(NORETRY))
    got = w.wait_reading(NORETRY, "healthy", 40)
    check("closed, connected and quiet: back to healthy", got.get("reading") == "healthy", got)


def old_failures(r, w):
    step("More than 50 old Error headers on the day a watch block is added open nothing, and a new failure still opens")
    w.declare([RETRY, ONESHOT])
    time.sleep(6)
    r.session("SHUTTER", f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM Shutter_Store.ReceiverReading WHERE Receiver='{NORETRY}'")""")
    if r.listening(PORT[NORETRY]):
        r.listener_down(PORT[NORETRY])
    r.listener_up(PORT[NORETRY], {"mode": "answer", "code": "AR", "words": "Made-up refusal"})
    before = len([x for x in r.headers(PLAIN, NORETRY) if x["status"] == "Error"])
    for i in range(1, 64):
        c = f"WO{tag}{i}"
        r.send(IN[NORETRY], r.order(c), c)
    r.wait_until(lambda: r.queue(PLAIN, NORETRY) == 0, 60)
    time.sleep(3)
    errors = [int(x["id"]) for x in r.headers(PLAIN, NORETRY) if x["status"] == "Error"]
    check("more than 50 settled Error headers", len(errors) - before >= 60 and len(errors) > 50, len(errors))
    r.listener_spec(PORT[NORETRY], {"mode": "up"})
    w.declare(RECEIVERS)
    r.wait_until(lambda: w.reading(NORETRY).get("checkedAt"), 30, 1)
    mark = lambda: r.value("SHUTTER", f'##class(Shutter.Store.ReceiverReading).Find("{NORETRY}").ErrorHeaderMark')
    check("the first poll's mark is the highest Error header", str(mark()) == str(max(errors)), (mark(), max(errors)))
    time.sleep(16)
    check("no outage over three more polls", w.outages(NORETRY) == [], w.outages(NORETRY))
    r.listener_down(PORT[NORETRY])
    time.sleep(1)
    c = f"WO{tag}N"
    r.send(IN[NORETRY], r.order(c), c)
    r.wait_until(lambda: len(w.outages(NORETRY)) >= 1, 30, 1)
    check("a new never-opened header above the mark still opens", len(w.outages(NORETRY)) == 1, w.outages(NORETRY))
    r.listener_up(PORT[NORETRY], {"mode": "up"})
    w.close_all(NORETRY)
    time.sleep(12)
    check("and once closed, it stays closed", w.outages(NORETRY) == [], w.outages(NORETRY))


def corrected_block(r, w):
    step("A watch block corrected to the real item: its old failures open nothing, a new one still does, and a long runbook comes through")
    named, wrong = "Corrected Case", NORETRY + "t"
    long_runbook = "start the listener " * 111
    w.declare([RETRY, ONESHOT, named], {named: wrong}, long_runbook)
    r.wait_until(lambda: w.reading(named).get("checkedAt"), 30, 1)
    mark = lambda: r.value("SHUTTER", f'##class(Shutter.Store.ReceiverReading).Find("{named}").ErrorHeaderMark')
    if r.listening(PORT[NORETRY]):
        r.listener_down(PORT[NORETRY])
    time.sleep(1)
    sent = [f"WT{tag}{i}" for i in range(1, 4)]
    for c in sent:
        r.send(IN[NORETRY], r.order(c), c)
    r.wait_until(lambda: sum(x["control"] in sent and x["status"] == "Error" for x in r.headers(PLAIN, NORETRY)) == 3, 60, 1)
    errors = [int(x["id"]) for x in r.headers(PLAIN, NORETRY) if x["status"] == "Error"]
    time.sleep(6)
    check("the wrong name read successfully with a mark below the failures", int(mark() or 0) < max(errors), (mark(), max(errors)))
    r.listener_up(PORT[NORETRY], {"mode": "up"})
    time.sleep(2)
    w.declare([RETRY, ONESHOT, named], {named: NORETRY}, long_runbook)
    r.wait_until(lambda: str(mark()) == str(max(errors)), 20, 1)
    check("the corrected block's mark is the item's highest Error header", str(mark()) == str(max(errors)), (mark(), max(errors)))
    time.sleep(16)
    check("no outage from its old failures", w.outages(named) == [], w.outages(named))
    r.listener_down(PORT[NORETRY])
    time.sleep(1)
    c = f"WT{tag}N"
    r.send(IN[NORETRY], r.order(c), c)
    r.wait_until(lambda: len(w.outages(named)) >= 1, 30, 1)
    o = w.outages(named)
    check("a new never-opened header there still opens", len(o) == 1, o)
    check("a runbook over 2000 characters opens, whole", len(o) == 1 and o[0]["runbook"] == long_runbook and len(long_runbook) > 2000, [len(x["runbook"]) for x in o])
    w.close_all(named)
    r.listener_up(PORT[NORETRY], {"mode": "up"})
    r.session("SHUTTER", f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM Shutter_Store.ReceiverReading WHERE Receiver='{NORETRY}'")""")
    w.declare(RECEIVERS)
    r.wait_until(lambda: w.reading(NORETRY).get("checkedAt"), 30, 1)


def quiet_disconnected(r, w):
    step("A quiet no-retry item that reads disconnected reads can't tell and opens nothing")
    r.listener_down(PORT[NORETRY])
    got = w.wait_reading(NORETRY, "cant_tell", 40)
    time.sleep(36)
    got = w.reading(NORETRY)
    print(f"        Status {got.get('status')!r}, AdapterState {got.get('adapterState')!r}", flush=True)
    check("can't tell", got.get("reading") == "cant_tell", got)
    check("nothing opened with no message failed", w.outages(NORETRY) == [], w.outages(NORETRY))
    r.listener_up(PORT[NORETRY], {"mode": "up"})


def one_shot(r, w):
    step("StayConnected 0 reads can't tell whether up or down, and the 30 s rule never opens")
    if r.listening(PORT[ONESHOT]):
        r.listener_down(PORT[ONESHOT])
    r.listener_up(PORT[ONESHOT], {"mode": "up"})
    time.sleep(12)
    up = w.reading(ONESHOT)
    r.listener_down(PORT[ONESHOT])
    time.sleep(40)
    down = w.reading(ONESHOT)
    print(f"        up: {up.get('reading')!r} {up.get('adapterState')!r}; down: {down.get('reading')!r} {down.get('adapterState')!r}", flush=True)
    check("up: can't tell", up.get("reading") == "cant_tell", up)
    check("down: can't tell", down.get("reading") == "cant_tell", down)
    check("nothing opened", w.outages(ONESHOT) == [], w.outages(ONESHOT))
    control = f"WOS{tag}"
    r.send(IN[ONESHOT], r.order(control), control)
    r.wait_until(lambda: len(w.outages(ONESHOT)) == 1, 40, 1)
    check("a failed send there opens on the no-retry rule", len(w.outages(ONESHOT)) == 1, w.outages(ONESHOT))


def settings(r, w):
    step("Reply code actions are read, never assumed")
    got = w.reading(RETRY)
    check("the stock default is the effective string and marked so", got.get("replyCodeActions") == STOCK_ACTIONS and got.get("replyCodeActionsStock") is True, got)
    check("GetReply is carried", got.get("getReply") == 1, got)
    r.set_item(PLAIN, PROD, RETRY, ReplyCodeActions=":?R=F,:?E=S,:~=S,:?A=C,:*=S")
    time.sleep(8)
    got = w.reading(RETRY)
    check("a changed string is stored and marked changed", got.get("replyCodeActions") == ":?R=F,:?E=S,:~=S,:?A=C,:*=S" and got.get("replyCodeActionsStock") is False and got["settingSources"]["ReplyCodeActions"] == "item", got)
    r.set_item(PLAIN, PROD, RETRY, ReplyCodeActions="")
    step("A class that is not stock: a setting it doesn't set reads unknown, and the reading says so")
    src = """Class V11Rig.WatchSub Extends EnsLib.HL7.Operation.TCPOperation
{
Property FailureTimeout As %Numeric [ InitialExpression = 7 ];
}
""".encode()
    r.put_file(src, "V11Rig.WatchSub.cls")
    r.load_classes(PLAIN, ["V11Rig.WatchSub"])
    code = f'''Set p=##class(Ens.Config.Production).%OpenId("{PROD}") Set i=##class(Ens.Config.Item).%New() Set i.Name="Sub Out",i.ClassName="V11Rig.WatchSub",i.PoolSize=1,i.Enabled=1 Do p.Items.Insert(i) Set sc=p.%Save() Set:sc sc=p.SaveToClass() Set:sc sc=##class(Ens.Director).UpdateProduction(60,1) Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!'''
    out = r.session(PLAIN, code)
    if "<<<ok>>>" not in out:
        raise RigBroken("the item did not go in: " + out[-400:])
    w.declare(list(RECEIVERS) + ["Sub Out"])
    r.wait_until(lambda: w.reading("Sub Out").get("checkedAt"), 30)
    time.sleep(7)
    got = w.reading("Sub Out")
    check("its FailureTimeout reads unknown, not its value", got["settingSources"].get("FailureTimeout") == "unknown" and got.get("failureTimeout") is None and got.get("retry") == "unknown" and "FailureTimeout" in got.get("unknownFields", []), got)


def disabled_and_stopped(r, w):
    step("The item disabled or the source production stopped reads unknown, never healthy")
    got = w.wait_reading(RETRY, "healthy", 30)
    r.session(PLAIN, f'Set sc=##class(Ens.Director).EnableConfigItem("{RETRY}",0,1)')
    got = w.wait_reading(RETRY, "unknown", 25)
    check("disabled: unknown", got.get("reading") == "unknown" and got.get("checkedAt"), got)
    r.session(PLAIN, f'Set sc=##class(Ens.Director).EnableConfigItem("{RETRY}",1,1)')
    w.wait_reading(RETRY, "healthy", 40)
    r.session(PLAIN, "Set sc=##class(Ens.Director).StopProduction(60,1) Write sc")
    got = w.wait_reading(RETRY, "unknown", 25)
    check("the production stopped: unknown", got.get("reading") == "unknown" and "running" in (got.get("why") or ""), got)
    check("nothing opened by it", w.outages(RETRY) == [], w.outages(RETRY))
    r.session(PLAIN, f'Set sc=##class(Ens.Director).StartProduction("{PROD}") Write sc')
    w.wait_reading(RETRY, "healthy", 40)


def stamps(r, w):
    step("The stored reading's stamp moves every poll, and a stopped watcher's reading goes stale")
    a = w.reading(RETRY)
    time.sleep(7)
    b = w.reading(RETRY)
    check("checkedAt moved", a.get("checkedAt") != b.get("checkedAt"), (a, b))
    r.session("SHUTTER", 'Set sc=##class(Ens.Director).EnableConfigItem("Receiver Watch",0,1)')
    time.sleep(6)
    last = w.reading(RETRY).get("checkedAt")
    time.sleep(62)
    got = w.reading(RETRY)
    check("stale: unknown, with its last stamp", got.get("reading") == "unknown" and got.get("checkedAt") == last, got)
    r.session("SHUTTER", 'Set sc=##class(Ens.Director).EnableConfigItem("Receiver Watch",1,1)')
    got = w.wait_reading(RETRY, "healthy", 40)
    check("the watcher back: fresh again", got.get("reading") == "healthy", got)


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
    w = Watch(r)
    try:
        if not a.reuse:
            step("Installing")
            r.start()
            r.install()
            no_watch(r, w)
            w.declare(RECEIVERS)
        for name, fn in (("retry", retry_outage), ("refusing", refusing), ("hung", hung), ("e02", one_ar_then_silence), ("quiet", quiet_no_retry), ("blip", blip), ("old", old_failures), ("corrected", corrected_block), ("quietoff", quiet_disconnected), ("oneshot", one_shot), ("settings", settings), ("disabled", disabled_and_stopped), ("stamps", stamps)):
            if not a.only or name in a.only.split(","):
                fn(r, w)
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
