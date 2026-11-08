#!/usr/bin/env python3
"""The outage routes, the Doctor's outage lines, the install's item and the reset, on a real instance, read through the REST API
as a person's browser reads it. Every receiver is a fake on the loopback address of a test instance, with a made-up name.

    python3 tests/e2e/v11_rig/api/check_api.py --ctr NAME --port PORT --image IMAGE [--module core] [--keep] [--reuse] [--only a,b]

Run from a copy of the repository's tree. Exit status: 0 all ok; 1 a check failed; 3 the rig broke.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from rig import PW, ROOT, Client, Rig, RigBroken  # noqa: E402

PLAIN = "RIGPLAIN"
RETRY, NORETRY, BOUNDED = "Retry Out", "NoRetry Out", "Bounded Out"
PORT = {RETRY: 7711, NORETRY: 7712, BOUNDED: 7713}
IN = {RETRY: 7611, NORETRY: 7612, BOUNDED: 7613}
CALL = "Made-up lab duty desk, 01632 960123"
RUNBOOK = "Restart the made-up listener from its console"
NOSEND = "Shutter will not send these messages. Review them in the Message Viewer using the site's recovery procedure."
CRITICAL = "Shutter does not assess clinical urgency. If delayed reporting may require clinical action, contact the laboratory using the site's critical-results and downtime procedure. Do not re-enter or amend a result solely from this page."
OUTAGE_KEYS = ["id", "receiver", "namespace", "item", "state", "kind", "openedAt", "drainedAt", "closedAt", "runbook", "call", "approvers", "pausedUntil", "overdueAt", "readings", "window", "settled", "alerts", "lists", "openCases", "version", "set", "approvable", "approval", "sentByShutter", "acts", "words"]
READING_KEYS = ["receiver", "namespace", "item", "reading", "status", "adapterState", "queue", "headHeaderId", "activeMessage", "failureTimeout", "retry", "defCharEncoding", "replyCodeActions", "getReply", "settingSources", "checkedAt", "unknownFields"]

failed, passed = [], 0
tag = time.strftime("%H%M%S")


# One signed-in client per user for the whole run: a session that signed out still holds a licence unit until it times out,
# so a client per step would run a Community instance out of them.
CLIENTS = {}


def client(r, user="appr1"):
    if user not in CLIENTS:
        c = Client(r.url, user, PW)
        c.sign_in()
        CLIENTS[user] = c
    return CLIENTS[user]


class same:
    """with same(r, user) as a: the run's one client for that user, left signed in for the next step."""

    def __init__(self, r, user="appr1"):
        self.c = client(r, user)

    def __enter__(self):
        return self.c

    def __exit__(self, *exc):
        return False


def sign_out_all():
    for c in CLIENTS.values():
        try:
            c.sign_out()
        except Exception:
            pass
    CLIENTS.clear()


def check(name, ok, detail=""):
    global passed
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {str(detail)[:1500]}"), flush=True)
    if ok:
        passed += 1
    else:
        failed.append(name)


def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


def raw(r, method, path, body=None, headers=None, client=None):
    """One request with exactly these headers: no CSRF header unless given, and the client's cookie when one is given."""
    data = (body if isinstance(body, bytes) else json.dumps(body).encode()) if body is not None else None
    h = {"Content-Type": "application/json"}
    h.update(headers or {})
    req = urllib.request.Request(r.url + path, data=data, method=method, headers=h)
    opener = client.opener if client else urllib.request.build_opener()
    try:
        with opener.open(req, timeout=60) as resp:
            text, code = resp.read().decode(), resp.status
    except urllib.error.HTTPError as e:
        text, code = e.read().decode(), e.code
    try:
        return code, json.loads(text)
    except ValueError:
        return code, text


def make_user(r, user, role):
    r.session("SHUTTER", f'''Set $NAMESPACE="%SYS"
If '##class(Security.Users).Exists("{user}") Set a=##class(Security.Users).Create("{user}","{role}","{PW}","A made-up user","SHUTTER","","",0,1)''')


def declare(r):
    entries = [
        {"name": RETRY, "system": "Made-up LIMS", "category": "orders_results", "tier": 3, "watch": {"namespace": PLAIN, "item": RETRY}, "runbook": RUNBOOK, "call": CALL, "duplicates": {"behaviour": "refuses", "phrase": "ALREADY HELD"}},
        {"name": NORETRY, "system": "Made-up LIMS", "category": "orders_results", "tier": 3, "watch": {"namespace": PLAIN, "item": NORETRY}, "runbook": RUNBOOK, "call": CALL, "engine_resend": True},
        {"name": BOUNDED, "system": "Made-up LIMS", "category": "orders_results", "tier": 3, "watch": {"namespace": PLAIN, "item": BOUNDED}, "runbook": RUNBOOK, "call": CALL},
    ]
    path = r.put_file(json.dumps({"receivers": entries}).encode(), "api-profile.json")
    out = r.session("SHUTTER", f'''Set s=##class(%Stream.FileCharacter).%New() Do s.LinkToFile("{path}") Set p=##class(Shutter.Store.SiteProfile).Current() Set d={{}}.%FromJSON(s) Set p.receivers=d.receivers Set sc=##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(),"the api check","the check") Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!''')
    if "<<<ok>>>" not in out:
        raise RigBroken("the profile was refused: " + out[-500:])


def doctor(r):
    return r.obj("SHUTTER", "##class(Shutter.Setup).Doctor()")


def outage_of(a, receiver, seconds):
    end = time.time() + seconds
    while time.time() < end:
        code, body = a.get("/outages")
        if code == 200:
            mine = [o for o in body["items"] if o["receiver"] == receiver]
            if mine:
                return mine[0]
        time.sleep(3)
    return None


def routes_from_source():
    text = open(os.path.join(ROOT, "src/Shutter/API/Dispatch.cls")).read()
    return re.findall(r'<Route Url="([^"]+)" Method="([A-Z]+)" Call="([A-Za-z]+)"/>', text)


def unwatched(r):
    step("Unwatched: the Doctor's outage lines name no receiver, the list is empty, and the item is counted present")
    d = doctor(r)
    o = d.get("outages") or {}
    check("the Doctor has its outages section", isinstance(o, dict) and "receivers" in o and "error" not in o, o)
    check("no receiver lines without a watch block", o.get("receivers") == [], o.get("receivers"))
    check("set_policy_version is blank on this build", o.get("set_policy_version") == "", o.get("set_policy_version"))
    check("the hold's line is blank on this build", o.get("hold") == "", o.get("hold"))
    check("policy_version beside it", bool(o.get("policy_version")), o.get("policy_version"))
    check("Receiver Watch is not missing from Shutter's production", "Receiver Watch" not in d.get("missing_items", []), d.get("missing_items"))
    a = client(r)
    code, body = a.get("/outages")
    check("GET /outages: 200, no items, no readings", code == 200 and body == {"items": [], "receivers": []}, (code, body))


def routes(r):
    step("Every other route of the UrlMap still answers, and the forwarded prefixes answer 404 on this build")
    found = routes_from_source()
    old = [x for x in found if not x[0].startswith("/outages")]
    check("the UrlMap holds 59 routes beside the outage ones", len(old) == 59 and len(found) == 62, (len(old), len(found)))
    with same(r) as a:
        miss = raw(r, "GET", "/no-such-route-" + tag, client=a)
        print(f"        a route that isn't there answers {miss[0]} {str(miss[1])[:200]}", flush=True)
        bad = []
        for url, method, call in old:
            if (url, method) in (("/session", "DELETE"), ("/session", "POST")):
                continue
            path = re.sub(r":[A-Za-z]+", "x" + tag, url)
            # A change goes without the CSRF header, so the route's own check answers and nothing moves.
            got = raw(r, method, path, {} if method != "GET" else None, client=a)
            if got == miss or got[0] >= 500:
                bad.append((method, url, got[0], str(got[1])[:150]))
        check("each of them answers its own handler, none the framework's miss or a 5xx", bad == [], bad)
        for prefix in ("/summaries/x", "/assist/x", "/summaries", "/assist"):
            got = raw(r, "GET", prefix, client=a)
            check(f"GET {prefix}: 404 not_in_build", got[0] == 404 and isinstance(got[1], dict) and got[1].get("error") == "not_in_build", got)
        got = raw(r, "POST", "/assist/x", {}, {"X-Requested-With": "Shutter"}, client=a)
        check("POST /assist/x: 404 not_in_build", got[0] == 404 and got[1].get("error") == "not_in_build", got)
        got = raw(r, "GET", "/assistant", client=a)
        check("/assistant is no forwarded prefix", got[0] == 404 and not (isinstance(got[1], dict) and got[1].get("error") == "not_in_build"), got)


def security(r):
    step("The security contract on /outages: no session 401, wrong resource 403, an operator reads and cannot act")
    check("no session: GET /outages 401", raw(r, "GET", "/outages")[0] == 401, raw(r, "GET", "/outages"))
    check("no session: POST acts 401", raw(r, "POST", "/outages/1/acts", {"act": "close", "reason": "x"}, {"X-Requested-With": "Shutter"})[0] == 401)
    make_user(r, "fwd1", "Shutter_Forwarder")
    with same(r, "fwd1") as f:
        got = f.get("/outages")
        check("the wrong resource: 403", got[0] == 403, got)
    make_user(r, "op1", "Shutter_Operator")
    with same(r, "op1") as op:
        check("an operator reads the list", op.get("/outages")[0] == 200, op.get("/outages"))


def watched(r):
    step("Watched: three receivers declared; the Doctor's lines and the always-on readings")
    declare(r)
    with same(r) as a:
        end = time.time() + 60
        while time.time() < end:
            code, body = a.get("/outages")
            if code == 200 and len(body["receivers"]) == 3 and all(x.get("checkedAt") for x in body["receivers"]):
                break
            time.sleep(3)
        check("three readings, each read", code == 200 and len(body["receivers"]) == 3 and all(x.get("checkedAt") for x in body["receivers"]), body)
        for x in body["receivers"]:
            check(f"{x['receiver']}: every Reading field", all(k in x for k in READING_KEYS), [k for k in READING_KEYS if k not in x])
    d = doctor(r)
    o = d["outages"]
    by = {x["receiver"]: x for x in o["receivers"]}
    check("the Doctor has a line per watched item", sorted(by) == sorted([RETRY, NORETRY, BOUNDED]), list(by))
    for name, timeout in ((RETRY, -1), (NORETRY, 0), (BOUNDED, 25)):
        x = by.get(name, {})
        check(f"{name}: FailureTimeout {timeout}, DefCharEncoding, ReplyCodeActions and SaveReplies read", x.get("failureTimeout") == timeout and "defCharEncoding" in x and x.get("replyCodeActions") and x.get("saveRepliesSource") in ("item", "class_default"), x)
    check("the policy version, and the set's blank", o["policy_version"] and o["set_policy_version"] == "", o)
    nib = o["declared_not_in_build"]
    check("engine_resend with no sender: declared; not in this build", {"receiver": NORETRY, "block": "engine_resend", "state": "declared; not in this build"} in nib, nib)
    check("approvers named on each (the escalation line)", o["approvers_missing"] == [], o["approvers_missing"])
    check("routers and AlertOnError read in the watched namespace", isinstance(o["routers_validating"], list) and not any("unknown" in q for q in o["alert_on_error_off"]), o)


def retrying(r):
    step("A retrying receiver's outage: the JSON, the words with the declared duplicate words, nothing approvable")
    if r.listening(PORT[RETRY]):
        r.listener_down(PORT[RETRY])
    for i in range(1, 4):
        r.send(IN[RETRY], r.order(f"A1{tag}{i}"), f"a1{i}")
    with same(r) as a:
        row = outage_of(a, RETRY, 90)
        check("the outage is listed", row is not None, row)
        if not row:
            return
        code, one = a.get(f"/outages/{row['id']}")
        check("GET /outages/:id 200", code == 200, (code, one))
        check("every field name as the design writes it", all(k in one for k in OUTAGE_KEYS), [k for k in OUTAGE_KEYS if k not in one])
        check("settled counts, empty lists, stamps", one["settled"] == {"completed": 0, "suspended": 0, "error": 0, "other": 0} and one["lists"] == {"queued": [], "offered": [], "reached": [], "refused": []} and one["openedAt"] and one["window"]["from"], one)
        check("set.status not_computed with set.reason", one["set"]["status"] == "not_computed" and one["set"]["reason"] == "no set gate in this build", one["set"])
        check("acts ['pause', 'close'], approvable false", one["acts"] == ["pause", "close"] and one["approvable"] is False, (one["acts"], one["approvable"]))
        check("readings carry replyCodeActions and getReply", "replyCodeActions" in one["readings"] and "getReply" in one["readings"], one["readings"])
        w = one["words"]
        print("        words: " + json.dumps(w)[:900], flush=True)
        check("first: the engine retries without limit", "retries without limit" in w["first"] and "Recovery attempts initiated by Shutter: 0." in w["first"], w["first"])
        check("do: the site's runbook and the duplicate line with its words", RUNBOOK in w["do"] and 'a duplicate is refused, with its words "ALREADY HELD"' in w["do"], w["do"])
        check("call: the site's line as written", CALL in w["call"], w["call"])
        check("critical: the laboratory line", w["critical"] == CRITICAL, w["critical"])
        check("no promise of a send", "for one approval" not in json.dumps(w), w)
        check("zero sends", one["sentByShutter"] == 0, one["sentByShutter"])


def bounded(r):
    step("A bounded receiver with no duplicates declared: the duplicate line says unknown")
    if r.listening(PORT[BOUNDED]):
        r.listener_down(PORT[BOUNDED])
    r.send(IN[BOUNDED], r.order(f"B1{tag}"), "b1")
    with same(r) as a:
        row = outage_of(a, BOUNDED, 120)
        check("the outage is listed", row is not None, row)
        if row:
            w = a.get(f"/outages/{row['id']}")[1]["words"]
            check("do: a duplicate is unknown", "a duplicate is unknown." in w["do"], w["do"])
            check("first: bounded, not 'no retry'", "retries here for at most 25 s" in w["first"], w["first"])


def no_retry(r):
    step("A no-retry receiver: 'Shutter will not send these messages', never 'for one approval'")
    if r.listening(PORT[NORETRY]):
        r.listener_down(PORT[NORETRY])
    r.send(IN[NORETRY], r.order(f"N1{tag}"), "n1")
    with same(r) as a:
        row = outage_of(a, NORETRY, 60)
        check("the outage opens", row is not None, row)
        if not row:
            return
        one = a.get(f"/outages/{row['id']}")[1]
        w = one["words"]
        print("        words: " + json.dumps(w)[:900], flush=True)
        check("first: Shutter will not send these messages", NOSEND in w["first"], w["first"])
        check("first: not offered, a person reads the trace", "not offered; a person reads the trace" in w["first"], w["first"])
        check("never 'for one approval'", "for one approval" not in w["first"], w["first"])
        check("approvable false though engine_resend is declared", one["approvable"] is False, one["approvable"])
        check("no duplicate line at a no-retry receiver", "duplicate is" not in w["do"], w["do"])


def acts(r):
    step("The acts: CSRF, an operator, the bound, pause, close, the stored reply, 404")
    with same(r) as a:
        row = outage_of(a, RETRY, 10)
        nrow = outage_of(a, NORETRY, 10)
        if not row or not nrow:
            check("both outages are there for the acts", False, (row, nrow))
            return
        rid, nid = row["id"], nrow["id"]
        until = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 3600))
        got = raw(r, "POST", f"/outages/{rid}/acts", {"act": "pause", "until": until}, client=a)
        check("no CSRF header: 403", got[0] == 403 and got[1].get("error") == "csrf", got)
        with same(r, "op1") as op:
            got = op.post(f"/outages/{rid}/acts", {"act": "pause", "until": until})
            check("an operator cannot act: 403", got[0] == 403, got)
            check("an operator reads the outage", op.get(f"/outages/{rid}")[0] == 200)
        got = raw(r, "POST", f"/outages/{rid}/acts", {"act": "close", "reason": "x" * 9000}, {"X-Requested-With": "Shutter"}, client=a)
        check("a body over the bound: 413 before it is parsed", got[0] == 413, got)
        got = a.post(f"/outages/{rid}/acts", {"act": "read_again"})
        check("an act the row doesn't list: 400", got[0] == 400, got)
        got = a.post(f"/outages/{rid}/acts", {"act": "close"})
        check("a close with no reason: 400", got[0] == 400, got)
        before = a.get(f"/outages/{rid}")[1]["words"]["do"]
        got = a.post(f"/outages/{rid}/acts", {"act": "pause", "until": until})
        check("pause: 200, paused", got[0] == 200 and got[1]["state"] == "paused" and got[1]["pausedUntil"] == until, got)
        if got[0] == 200:
            check("set.status withheld, set.reason down on purpose", got[1]["set"] == {**got[1]["set"], "status": "withheld", "reason": "down on purpose"}, got[1]["set"])
            check("the Do line swapped", got[1]["words"]["do"].startswith("Down on purpose until") and got[1]["words"]["do"] != before, got[1]["words"]["do"])
        key = {"X-Requested-With": "Shutter", "Idempotency-Key": "close-" + tag}
        first = raw(r, "POST", f"/outages/{nid}/acts", {"act": "close", "reason": "the listener is back, checked by hand"}, key, client=a)
        check("close with a reason: 200, closed", first[0] == 200 and first[1]["state"] == "closed" and first[1]["acts"] == [], first)
        again = raw(r, "POST", f"/outages/{nid}/acts", {"act": "close", "reason": "the listener is back, checked by hand"}, key, client=a)
        check("the replayed Idempotency-Key answers the stored reply", again == first, (again[0], str(again[1])[:300]))
        fresh = a.post(f"/outages/{nid}/acts", {"act": "close", "reason": "once more"})
        check("without the key, a closed row: 409", fresh[0] == 409, fresh)
        code, body = a.get("/outages")
        check("state open leaves the closed row out", all(o["id"] != nid for o in body["items"]), [o["id"] for o in body["items"]])
        code, body = a.get("/outages?state=all")
        check("state all keeps it", any(o["id"] == nid and o["state"] == "closed" for o in body["items"]), [o["id"] for o in body["items"]])
        check("another state: 400", a.get("/outages?state=closed")[0] == 400)
        check("an id that isn't there: 404", a.get("/outages/999999")[0] == 404 and a.get("/outages/abc")[0] == 404)


def stale(r):
    step("A watcher stopped for 60 s reads unknown with its last checkedAt")
    r.session("SHUTTER", 'Set sc=##class(Ens.Director).EnableConfigItem("Receiver Watch",0,1)')
    time.sleep(6)
    with same(r) as a:
        last = {x["receiver"]: x["checkedAt"] for x in a.get("/outages")[1]["receivers"]}
    time.sleep(64)
    with same(r) as a:
        now = a.get("/outages")[1]["receivers"]
    check("every reading unknown, with its last stamp", now and all(x["reading"] == "unknown" and x["checkedAt"] == last[x["receiver"]] for x in now), now)
    r.session("SHUTTER", 'Set sc=##class(Ens.Director).EnableConfigItem("Receiver Watch",1,1)')


def set_gate_stub(r):
    step("The Doctor's SETPOLICYVERSION line shows a set gate's version once one is compiled, and is blank again without it")
    cls = 'Class Shutter.Util.ResendSet\n{\n\nParameter SETPOLICYVERSION = "stub-for-the-check";\n\n}\n'
    path = r.put_file(cls.encode(), "Shutter.Util.ResendSet.cls")
    out = r.session("SHUTTER", f'Set sc=$SYSTEM.OBJ.Load("{path}","ck-d") Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!')
    check("a stand-in set gate compiles", "<<<ok>>>" in out, out[-300:])
    check("set_policy_version is its version", doctor(r)["outages"]["set_policy_version"] == "stub-for-the-check")
    out = r.session("SHUTTER", 'Set sc=$SYSTEM.OBJ.Delete("Shutter.Util.ResendSet","-d") Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!')
    check("it is removed", "<<<ok>>>" in out, out[-300:])
    check("set_policy_version is blank again", doctor(r)["outages"]["set_policy_version"] == "")


def shape_b(r):
    step("Shape B on a copy of the oracle's site production: AddItemsTo adds Receiver Watch, and the Doctor counts it")
    src = open(os.path.join(ROOT, "tests/e2e/pathology_site/OraLab.Production.cls")).read()
    copy = src.replace("OraLab.Production", "V11Api.ShapeB")
    path = r.put_file(copy.encode(), "V11Api.ShapeB.cls")
    out = r.session("SHUTTER", f'Set sc=$SYSTEM.OBJ.Load("{path}","ck-d") Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!')
    check("the copy compiles in Shutter's namespace", "<<<ok>>>" in out, out[-400:])
    has = 'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n FROM Ens_Config.Item WHERE Production = ? AND Name = ?","V11Api.ShapeB","Receiver Watch") Do rs.%Next() Write !,"<<<",rs.%Get("n"),">>>",!'
    check("before: no Receiver Watch in it", r.rows("SHUTTER", has) == ["0"], r.rows("SHUTTER", has))
    out = r.session("SHUTTER", 'Set sc=##class(Shutter.Setup).AddItemsTo("V11Api.ShapeB",.added) Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),"|",added,">>>",!')
    check("AddItemsTo answers ok", "<<<ok|" in out, out[-400:])
    check("after: Receiver Watch is in the site's production", r.rows("SHUTTER", has) == ["1"], r.rows("SHUTTER", has))
    r.session("SHUTTER", 'Set ^V11Api("production")=$GET(^Shutter.Config("production")) Set ^Shutter.Config("production")="V11Api.ShapeB"')
    try:
        d = doctor(r)
        check("the Doctor counts it present there", d["shutter_production"] == "V11Api.ShapeB" and "Receiver Watch" not in d["missing_items"], (d["shutter_production"], d["missing_items"]))
        out = r.session("SHUTTER", '''Set p=##class(Ens.Config.Production).%OpenId("V11Api.ShapeB") For i=p.Items.Count():-1:1 { Set it=p.Items.GetAt(i) If it.Name="Receiver Watch" Do p.Items.RemoveAt(i) Do ##class(Ens.Config.Item).%DeleteId(it.%Id()) } Set sc=p.SaveToClass() Set sc2=p.%Save() Write !,"<<<",$SELECT(sc&&sc2:"ok",1:"failed"),">>>",!''')
        check("the item taken out again", "<<<ok>>>" in out, out[-300:])
        d = doctor(r)
        check("then the Doctor names it missing", "Receiver Watch" in d["missing_items"], d["missing_items"])
    finally:
        r.session("SHUTTER", 'Set ^Shutter.Config("production")=$GET(^V11Api("production")) Kill:^Shutter.Config("production")="" ^Shutter.Config("production") Kill ^V11Api')


def reset(r):
    step("The reset leaves no Outage, OutageEvent or ReceiverReading behind")
    count = 'For t="ReceiverReading","Outage","OutageEvent" { Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n FROM Shutter_Store."_t) Do rs.%Next() Write !,"<<<",t,"|",rs.%Get("n"),">>>",! }'
    before = dict(x.split("|") for x in r.rows("SHUTTER", count))
    check("there is something to reset", all(int(v) > 0 for v in before.values()), before)
    r.session("SHUTTER", 'Set sc=##class(Ens.Director).EnableConfigItem("Receiver Watch",0,1)')
    out = r.session("SHUTTER", 'Set was=$GET(^Shutter.Config("demo")) Set ^Shutter.Config("demo")=1 Set n=##class(Shutter.Setup).PurgeStore() Set ^Shutter.Config("demo")=was Write !,"<<<",n,">>>",!')
    check("the reset ran", re.search(r"<<<\d+>>>", out) is not None, out[-300:])
    after = dict(x.split("|") for x in r.rows("SHUTTER", count))
    check("nothing left in the three stores", after == {"ReceiverReading": "0", "Outage": "0", "OutageEvent": "0"}, after)


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
    try:
        if not a.reuse:
            step("Installing")
            r.start()
            r.install()
        for name, fn in (("unwatched", unwatched), ("routes", routes), ("security", security), ("watched", watched), ("retrying", retrying), ("bounded", bounded), ("noretry", no_retry), ("acts", acts), ("stale", stale), ("setgate", set_gate_stub), ("shapeb", shape_b), ("reset", reset)):
            if not a.only or name in a.only.split(","):
                fn(r)
    except RigBroken as e:
        print(f"RIG BROKEN: {e}", flush=True)
        sys.exit(3)
    finally:
        sign_out_all()
        if not a.keep:
            r.remove()
    print(f"\n{passed} ok, {len(failed)} failed" + (": " + ", ".join(failed) if failed else ""), flush=True)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
