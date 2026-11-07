#!/usr/bin/env python3
"""The failure coverage census (docs/CONTRACTS.md, section 17) on real failures in a real watched namespace, on stock classes.

    python3 tests/e2e/census_check.py [--port 52880] [--ctr census-check] [--image IMAGE] [--module core] [--keep]

Starts a stock IRIS for Health image, installs Shutter without the demo, gives the instance a namespace with its own production and
a listener that answers by control id, and onboards it. The fixture: ten deliveries to one receiver, four failed, two exactly
linked, one never forwarded, one ambiguous in a two-message session; the report must give those categories, as JSON and as CSV,
and leave the cases, the source and the receiver as they were. The negative controls: off by default, roles, a window and a
receiver refused, one control id at two receivers, several failures on one case, a cap hit, a header deleted, the namespace's
database dismounted and a real message purge. No model is called and no key is needed. Run from the repository's root. Exit
status 1 when a check fails.
"""
import argparse
import base64
import csv
import datetime
import http.cookiejar
import io
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PW = "Census-2026x"
HOME = "/home/irisowner"

ap = argparse.ArgumentParser()
ap.add_argument("--keep", action="store_true")
ap.add_argument("--port", type=int, default=52880)
ap.add_argument("--ctr", default="census-check")
ap.add_argument("--image", default="irishealth-community:2027.1.0AI.109.0")
ap.add_argument("--module", default="")
args = ap.parse_args()
CTR = args.ctr
TARGET = f"{HOME}/pkg/{args.module}" if args.module else f"{HOME}/pkg"
URL = f"http://127.0.0.1:{args.port}/api/shutter"
failed = []
passed = 0


def check(name, ok, detail=""):
    global passed
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {str(detail)[:1500]}"), flush=True)
    if ok:
        passed += 1
    else:
        failed.append(name)


def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


def session(ns, code, timeout=400):
    r = subprocess.run(["docker", "exec", "-i", CTR, "iris", "session", "IRIS", "-U", ns], input=code + "\nHalt\n", capture_output=True, text=True, timeout=timeout, errors="replace")
    return r.stdout


def value(ns, expr, timeout=300):
    out = session(ns, f'Set %v = {expr}\nWrite !,"<<<",%v,">>>",!', timeout)
    m = re.findall(r"<<<(.*?)>>>", out, re.S)
    if not m:
        raise RuntimeError(f"no value for {expr} in {ns}: {out[-800:]}")
    return m[-1]


def sql_rows(ns, query, columns):
    """Rows of a read, as lists of strings."""
    gets = ',"|",'.join(f'rs.%Get("{c}")' for c in columns)
    query = query.replace('"', '""')
    out = session(ns, f'Set rs=##class(%SQL.Statement).%ExecDirect(,"{query}") While rs.%Next() {{ Write !,"<<<",{gets},">>>",! }}')
    return [row.split("|") for row in re.findall(r"<<<(.*?)>>>", out)]


class Client:
    def __init__(self):
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, method, path, body=None, csrf=True):
        data = json.dumps(body).encode() if body is not None else None
        headers = {"Content-Type": "application/json"}
        if csrf:
            headers["X-Requested-With"] = "Shutter"
        req = urllib.request.Request(URL + path, data=data, method=method, headers=headers)
        try:
            with self.opener.open(req, timeout=180) as r:
                text, code = r.read().decode(), r.status
        except urllib.error.HTTPError as e:
            text, code = e.read().decode(), e.code
        try:
            return code, json.loads(text)
        except ValueError:
            return code, text


oper = Client()
appr = Client()


def post_intake(body):
    req = urllib.request.Request(URL + "/intake", data=json.dumps(body).encode(), method="POST", headers={"X-Requested-With": "Shutter", "Content-Type": "application/json"})
    req.add_header("Authorization", "Basic " + base64.b64encode(f"shutter-fwd:{PW}".encode()).decode())
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def iso(offset=0):
    return (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=offset)).strftime("%Y-%m-%dT%H:%M:%SZ")


def a01(app, control, encounter=None, when=None):
    when = when or time.strftime("%Y%m%d%H%M%S", time.gmtime(time.time() - 120))
    enc = encounter or re.sub(r"\W", "", control)
    return "\r".join([f"MSH|^~\\&|{app}|HOSP|BEDS|HOSP|{when}||ADT^A01^ADT_A01|{control}|P|2.5.1", f"EVN|A01|{when}||||{when}", f"PID|1||MRN{enc}^^^HOSP^MR~9997001001^^^NHS^NH||SYNTH^{enc}||19751120|F", f"PV1|1|I|WARD-A^BAY1^{enc[-2:]}^HOSP||||||||||||||||ENC-{enc}|||||||||||||||||||||||||{when}"]) + "\r"


def send(text, name):
    subprocess.run(["docker", "exec", "-i", CTR, "sh", "-c", f"cat > /tmp/cen_site/{name}.hl7"], input=text, text=True, check=True)
    r = subprocess.run(["docker", "exec", "-e", "MLLP_WAIT=15", CTR, "python3", "/tmp/cen_site/mllp.py", "7401", f"/tmp/cen_site/{name}.hl7"], capture_output=True, text=True, timeout=60)
    return r.stdout.strip()


def deliveries(target):
    """(header id, session, status) of each request header to the item; completed with the error flag reads as error."""
    rows = sql_rows("CENSUS", f"SELECT ID, SessionId, Status, IsError FROM Ens.MessageHeader WHERE Type = 1 AND TargetConfigName = '{target}' ORDER BY ID", ["ID", "SessionId", "Status", "IsError"])
    return [[r[0], r[1], 8 if r[3] == "1" and r[2] == "9" else int(r[2])] for r in rows]


def wait_deliveries(target, n, seconds=60):
    end = time.time() + seconds
    while time.time() < end:
        d = deliveries(target)
        if len(d) >= n and all(x[2] in (4, 5, 7, 8, 9) for x in d):
            return d
        time.sleep(1)
    return deliveries(target)


def cases(receiver=None):
    _, r = appr.call("GET", "/cases")
    items = r.get("items", []) if isinstance(r, dict) else []
    return [c for c in items if c.get("sourceNamespace") == "CENSUS" and (receiver is None or c.get("receiver") == receiver)]


def wait_cases(receiver, n, seconds=45):
    end = time.time() + seconds
    while time.time() < end:
        if len(cases(receiver)) >= n:
            return cases(receiver)
        time.sleep(1)
    return cases(receiver)


def state_of_things():
    """Everything a run may not touch: the cases, their events and attempts, the source's headers, what the listener heard."""
    rows = sql_rows("SHUTTER", 'SELECT COUNT(*) AS N, SUM(Version) AS V FROM Shutter_Store."Case"', ["N", "V"])[0]
    events = sql_rows("SHUTTER", "SELECT COUNT(*) AS N FROM Shutter_Store.CaseEvent", ["N"])[0][0]
    attempts = sql_rows("SHUTTER", "SELECT COUNT(*) AS N FROM Shutter_Store.ExecutionAttempt", ["N"])[0][0]
    headers = sql_rows("CENSUS", "SELECT COUNT(*) AS N, MAX(ID) AS M FROM Ens.MessageHeader", ["N", "M"])[0]
    heard = subprocess.run(["docker", "exec", CTR, "sh", "-c", "wc -l < /tmp/cen_site/heard.log"], capture_output=True, text=True).stdout.strip()
    return {"cases": rows, "events": events, "attempts": attempts, "headers": headers, "heard": heard}


def settled_state(seconds=120):
    """The state once the cases have stopped moving, read twice."""
    end = time.time() + seconds
    last = state_of_things()
    while time.time() < end:
        time.sleep(6)
        now = state_of_things()
        if now == last:
            return now
        last = now
    return last


def profile_with(settings):
    blob = json.dumps(settings).replace('"', '""')
    return session("SHUTTER", f'''Set p=##class(Shutter.Store.SiteProfile).Current()
Do p.%Set("failure_census",##class(%DynamicObject).%FromJSON("{blob}"))
Set sc=##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(),"census check","census check")
Write !,"[profile] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!''')


def run(receiver, frm, to):
    return oper.call("POST", "/failure-census", {"receiver": receiver, "from": frm, "to": to})


def report(run_id):
    return oper.call("GET", f"/failure-census/{run_id}")[1]


def finish():
    print(f"\n{passed} checks passed, {len(failed)} failed")
    for f in failed:
        print("  FAILED:", f)
    if not args.keep:
        subprocess.run(["docker", "rm", "-f", CTR], capture_output=True)
    sys.exit(1 if failed else 0)


# ---- the stock instance ----
step("A stock instance, with Shutter installed without the demo")
subprocess.run(["docker", "rm", "-f", CTR], capture_output=True)
subprocess.run(["docker", "run", "-d", "--name", CTR, "-p", f"127.0.0.1:{args.port}:52773", args.image, "--check-caps", "false", "--ISCAgent", "false"], check=True, capture_output=True)
for _ in range(80):
    if b"^running" in subprocess.run(["docker", "exec", CTR, "iris", "qlist", "IRIS"], capture_output=True).stdout:
        break
    time.sleep(3)
time.sleep(5)
tar = subprocess.Popen(["tar", "-C", ROOT, "-cf", "-", "--exclude=.git", "--exclude=node_modules", "--exclude=web", "."], stdout=subprocess.PIPE)
subprocess.run(["docker", "exec", "-i", "-u", "root", CTR, "sh", "-c", f"mkdir -p {HOME}/pkg && tar -xf - -C {HOME}/pkg && chown -R irisowner:irisowner {HOME}/pkg"], stdin=tar.stdout, check=True)
subprocess.run(["docker", "cp", os.path.join(ROOT, "vendor/ipm/zpm-0.10.10.xml"), f"{CTR}:/tmp/zpm.xml"], check=True)
out = session("USER", f'Set sc=$SYSTEM.OBJ.Load("{HOME}/pkg/src/Shutter/Setup.cls","ck") Write !,"[ns] ",##class(Shutter.Setup).CreateNamespace("SHUTTER"),"|",!')
check("the namespace is made", "ok|" in out, out[-500:])
out = session("SHUTTER", f'Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck")\nSet sc=##class(%IPM.Main).Shell("load {TARGET} -Ddemo=0") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 500)
check("Shutter loads", "RESULT: ok" in out, out[-800:])
session("SHUTTER", f'Write ##class(Shutter.Setup).CreateNamespace("CENSUS")')
subprocess.run(["docker", "cp", os.path.join(HERE, "census_site") + "/.", f"{CTR}:/tmp/cen_site"], check=True)
for f in ("mllp.py", "ack_listener.py"):
    subprocess.run(["docker", "cp", os.path.join(HERE, "onboard_site", f), f"{CTR}:/tmp/cen_site/{f}"], check=True)
subprocess.run(["docker", "exec", "-u", "root", CTR, "chown", "-R", "irisowner:irisowner", "/tmp/cen_site"], check=True)
lines = [f'Set sc=$SYSTEM.OBJ.Load("/tmp/cen_site/{f}.cls","ck-d") Write !,"[c] ",sc,!' for f in ("CenSite.TwoSends", "CenSite.Rule", "CenSite.Production")]
lines.append('Set sc=##class(Ens.Director).StartProduction("CenSite.Production") Write !,"[start] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
out = session("CENSUS", "\n".join(lines))
check("CENSUS runs its own production", "[start] ok" in out, out[-600:])
subprocess.Popen(["docker", "exec", CTR, "python3", "/tmp/cen_site/ack_listener.py", "7411", "/tmp/cen_site/heard.log", "3000"])
time.sleep(2)
session("SHUTTER", f'''Set $NAMESPACE="%SYS"
Set a=##class(Security.Users).Create("oper1","Shutter_Operator","{PW}","An operator","SHUTTER","","",0,1)
Set a=##class(Security.Users).Create("appr1","Shutter_Approver","{PW}","An approver","SHUTTER","","",0,1)''')
code, _ = oper.call("POST", "/session", {"username": "oper1", "password": PW})
check("an operator signs in", code in (200, 201), code)
code, _ = appr.call("POST", "/session", {"username": "appr1", "password": PW})
check("an approver signs in", code in (200, 201), code)

# ---- the fixture ----
step("The fixture: one failure before Shutter watches, so it is never forwarded")
T0 = iso(-1)
print(send(a01("PAS", "AE-UNF1"), "unf"))
d = wait_deliveries("Cen Out", 1)
check("it failed in the engine", len(d) == 1 and d[0][2] in (5, 8), d)
UNFORWARDED = d[0][0]

step("Onboarding, and it is off by default")
a = json.loads(value("SHUTTER", '##class(Shutter.Setup).OnboardApply("CENSUS","")'))
check("the apply is ok", a["ok"], a)
c = session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("CENSUS","shutter-fwd","{PW}")')
check("the credential is stored", '"ok":true' in c, c[-300:])
code, r = oper.call("GET", "/failure-census")
check("the list says off, and names the scopes", code == 200 and r["enabled"] is False and {s["receiver"] for s in r["scopes"]} >= {"Cen Out", "Cen Two", "Cen Three"}, r)
check("it carries the statement of what it cannot see", "does not detect a message the engine completed" in r["statement"], r)
code, r = run("Cen Out", T0, iso())
check("a run while off is refused", code == 409 and r.get("error") == "not_enabled", (code, r))
check("and leaves no run", oper.call("GET", "/failure-census")[1]["items"] == [], "")

step("Nine more deliveries: five and one completed, two failed alone, one failed beside a completed one in its session")
for i in range(5):
    print(send(a01("PAS", f"AA-OK{i}"), f"ok{i}"))
print(send(a01("PAS", "AE-ONE1"), "one1"))
print(send(a01("PAS", "AE-ONE2"), "one2"))
print(send(a01("DBL", "DBL1"), "dbl1"))
d = wait_deliveries("Cen Out", 10)
check("ten deliveries reached their end", len(d) == 10 and all(x[2] in (5, 8, 9) for x in d), d)
failed_rows = [x for x in d if x[2] != 9]
check("four of them failed, six completed", len(failed_rows) == 4, d)
ONE1, ONE2, DOUBLE = failed_rows[1][0], failed_rows[2][0], failed_rows[3][0]
double_session = failed_rows[3][1]
heard = wait_cases("Cen Out", 2)
time.sleep(8)
heard = cases("Cen Out")
if len(heard) == 2:
    # The alert route may decline a session with several messages: the forward is then the process's own, naming the session's first header.
    first = sql_rows("CENSUS", f"SELECT TOP 1 ID FROM Ens.MessageHeader WHERE SessionId = {double_session} ORDER BY ID", ["ID"])[0][0]
    code, r = post_intake({"source": {"namespace": "CENSUS", "production": "CenSite.Production", "route": "Cen In", "header_id": first}, "receiver": "Cen Out", "failure": {"kind": "rejected", "text": "AE", "outcome": "rejected", "reason_code": "nack"}, "message": a01("DBL", "DBL1")})
    check("the two-message session's forward is taken", code == 202, (code, r))
heard = wait_cases("Cen Out", 3)
check("three cases, none for the failure before onboarding", len(heard) == 3, heard)
T1 = iso(2)
time.sleep(3)
by_origin = {c["originHeaderId"]: c["caseId"] for c in heard}

step("On, and the report gives the fixture's exact categories")
out = profile_with({"enabled": True, "settle_seconds": 0})
check("the profile takes the block", "[profile] ok" in out, out[-300:])
before = settled_state()
code, r = run("Cen Out", T0, T1)
check("the run answers 201", code == 201, (code, r))
FIX = r["runId"]
check("it is complete", r["completeness"] == "complete" and r["complete"] is True and r["reasons"] == [], r)
t = r["totals"]
print(json.dumps(t))
check("ten deliveries", t["deliveries"] == 10, t)
check("six completed, outside the denominator", t["completed"] == 6, t)
check("four eligible failures", t["eligible"] == 4, t)
check("two exactly linked", t["exact"] == 2, t)
check("one with no linked case", t["none"] == 1, t)
check("one ambiguous", t["ambiguous"] == 1, t)
check("none excluded or unassessable, no gap", t["excluded"] == 0 and t["unassessable"] == 0 and t["evidenceGaps"] == 0, t)
rep = report(FIX)
items = {i["deliveryHeaderId"]: i for i in rep["items"]}
check("a row per failure and none for a completed delivery", set(items) == {UNFORWARDED, ONE1, ONE2, DOUBLE}, items)
check("the unforwarded failure has no case", items[UNFORWARDED]["linkQuality"] == "none" and items[UNFORWARDED]["caseIds"] == "", items[UNFORWARDED])
check("each lone failure is exact, with its one case", all(items[x]["linkQuality"] == "exact" and items[x]["caseIds"] in by_origin.values() for x in (ONE1, ONE2)) and items[ONE1]["caseIds"] != items[ONE2]["caseIds"], items)
check("the two-message session is ambiguous, naming its candidate", items[DOUBLE]["linkQuality"] == "ambiguous" and items[DOUBLE]["explanation"] == "several_deliveries_in_session" and items[DOUBLE]["caseIds"] in by_origin.values(), items[DOUBLE])
check("a row says status, family and body class", items[UNFORWARDED]["sourceStatus"] in ("error", "suspended") and items[UNFORWARDED]["family"] == "ADT" and items[UNFORWARDED]["bodyClass"] == "EnsLib.HL7.Message", items[UNFORWARDED])
text = json.dumps(rep)
check("no message content in the report", "SYNTH" not in text and "MRN" not in text and "9997001001" not in text, text[:400])
code, c = oper.call("GET", f"/failure-census/{FIX}.csv")
parsed = list(csv.reader(io.StringIO(c)))
check("the CSV answers, with its columns", code == 200 and parsed[0][0] == "record_type" and "link_quality" in parsed[0], str(c)[:300])
check("its run row says complete", parsed[1][0] == "run" and parsed[1][parsed[0].index("eligibility")] == "complete", parsed[1])
col = parsed[0].index("link_quality")
check("and it has the same four rows", sorted(x[col] for x in parsed[2:]) == ["ambiguous", "exact", "exact", "none"], parsed[2:])
check("no message content in the CSV", "SYNTH" not in c and "MRN" not in c, c[:300])
after = settled_state()
check("nothing moved: cases, events, attempts, source headers, the listener", after == before, (before, after))

step("Who may, and what may be asked")
code, _ = Client().call("POST", "/failure-census", {"receiver": "Cen Out"})
check("no sign-in: 401", code == 401, code)
code, _ = oper.call("POST", "/failure-census", {"receiver": "Cen Out"}, csrf=False)
check("no CSRF header: 403", code == 403, code)
fwd = urllib.request.Request(URL + "/failure-census", method="GET")
fwd.add_header("Authorization", "Basic " + base64.b64encode(f"shutter-fwd:{PW}".encode()).decode())
try:
    code = urllib.request.urlopen(fwd, timeout=30).status
except urllib.error.HTTPError as e:
    code = e.code
check("the forwarder's user: 403", code == 403, code)
for bad, label in (({"receiver": "' OR 1=1 --", "from": T0, "to": T1}, "free text as a receiver"), ({"receiver": "Downstream Out", "from": T0, "to": T1}, "Shutter's own connector"), ({"receiver": "Cen Out", "from": iso(-90000), "to": iso()}, "over the longest window"), ({"receiver": "Cen Out", "from": T1, "to": T0}, "a window backwards"), ({"receiver": "Cen Out", "from": T0, "to": iso(3600)}, "a window not over yet"), ({"receiver": "Cen Out", "from": "x'; DROP", "to": T1}, "SQL as a time")):
    code, r = run(bad["receiver"], bad["from"], bad["to"])
    check(f"refused: {label}", code == 400 and r.get("error") == "bad_request", (code, r))
code, r = oper.call("POST", "/failure-census", {"receiver": "Cen Out", "namespace": "%SYS", "sql": "SELECT 1", "from": T0, "to": T1})
check("a namespace in the body is not read: it runs on the registered one", code == 201 and r["namespace"] == "CENSUS", (code, r))
code, r = oper.call("GET", "/failure-census/FC-999999")
check("an unknown run: 404", code == 404, (code, r))

step("One control id at two receivers, in one session and in two")
W2 = iso(-1)
print(send(a01("BOTH", "SAME-1"), "same1"))
print(send(a01("TWO", "SAME-2"), "same2"))
print(send(a01("THREE", "SAME-2"), "same3"))
wait_deliveries("Cen Two", 2)
wait_deliveries("Cen Three", 2)
wait_cases("Cen Two", 2)
time.sleep(6)
T2 = iso(2)
time.sleep(3)
check("Shutter has cases at Cen Two and none at Cen Three", len(cases("Cen Two")) == 2 and cases("Cen Three") == [], cases())
_, r = run("Cen Two", W2, T2)
check("Cen Two: two failures, both exact", r["totals"]["eligible"] == 2 and r["totals"]["exact"] == 2, r)
_, r = run("Cen Three", W2, T2)
check("Cen Three: two failures with no case, in spite of the same control ids and one shared session", r["totals"]["eligible"] == 2 and r["totals"]["none"] == 2 and r["totals"]["exact"] == 0 and r["totals"]["ambiguous"] == 0, r)
check("and a receiver with no alert is told apart by nothing but its missing case: complete", r["completeness"] == "complete", r)

step("Several failures on one case: many to one")
W3 = iso(-1)
when = time.strftime("%Y%m%d%H%M%S", time.gmtime(time.time() - 300))
threads = [threading.Thread(target=send, args=(a01("TWO", f"MANY-{i}", "MANYENC", when), f"many{i}")) for i in range(2)]
[x.start() for x in threads]
[x.join() for x in threads]
wait_deliveries("Cen Two", 4)
time.sleep(10)
T3 = iso(2)
time.sleep(3)
_, r = run("Cen Two", W3, T3)
print(json.dumps(r["totals"]))
check("two failures, both exact", r["totals"]["eligible"] == 2 and r["totals"]["exact"] == 2, r)
many = [c for c in cases("Cen Two") if "MANYENC" in json.dumps(c)]
if len(many) == 1:
    check("to one case, counted once", r["totals"]["distinctCases"] == 1, r)
else:
    print(f"  note: the first case had closed before the second failure ({len(many)} cases), so this is two cases")
    check("to as many cases as Shutter has", r["totals"]["distinctCases"] == len(many), (r, many))

step("A cap hit is incomplete")
profile_with({"enabled": True, "settle_seconds": 0, "max_headers": 3})
code, r = run("Cen Out", T0, T1)
check("incomplete, not a sample read as covered", code == 201 and r["completeness"] == "incomplete" and r["complete"] is False and "header_cap_hit" in r["reasons"], r)
check("it read three and says it stopped", r["scanned"] == 3 and r["truncated"] is True and r["totals"]["deliveries"] == 3, r)
profile_with({"enabled": True, "settle_seconds": 0})

step("Too new to say it has no case")
profile_with({"enabled": True, "settle_seconds": 86400})
code, r = run("Cen Three", W2, T2)
check("settling, not missing", r["totals"]["none"] == 0 and r["totals"]["unassessable"] == 2 and "settling" in r["reasons"] and r["completeness"] == "incomplete", r)
profile_with({"enabled": True, "settle_seconds": 0})

step("A header deleted from the store is an evidence gap")
gone_origin = next(o for o, cid in by_origin.items() if cid == items[ONE2]["caseIds"])
session("CENSUS", f"Write ##class(Ens.MessageHeader).%DeleteId({gone_origin})")
code, r = run("Cen Out", T0, T1)
print(json.dumps(r["reasons"]), json.dumps(r["totals"]))
check("incomplete, with the hole counted", r["completeness"] == "incomplete" and "header_ids_missing" in r["reasons"] and r["totals"]["missingIds"] == 1 and r["totals"]["evidenceGaps"] >= 1, r)
check("and the case whose origin is gone is said", "case_origin_purged" in r["reasons"], r)
rep = report(r["runId"])
check("a row for that case", any(i["explanation"] == "case_origin_purged" and i["caseIds"] == items[ONE2]["caseIds"] and i["eligibility"] == "unknown" for i in rep["items"]), rep["items"])

step("The namespace's database dismounted: unknown, never zero")
out = session("CENSUS", 'Set sc=##class(Ens.Director).StopProduction(60,1) Write !,"[stop] ",sc,!')
db = "/usr/irissys/mgr/census/"
out = session("%SYS", f'Set sc=##class(SYS.Database).DismountDatabase("{db}") Write !,"[dismount] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
check("it is dismounted", "[dismount] ok" in out, out[-400:])
code, r = run("Cen Out", T0, T1)
print(json.dumps({k: r.get(k) for k in ("completeness", "sourceRead", "sourceError", "reasons", "scanned")}))
check("the report is unknown", code == 201 and r["completeness"] == "unknown" and r["sourceRead"] == "unavailable" and r["reasons"] == ["source_unreadable"], (code, r))
check("every total is null, none is 0", all(v is None for v in r["totals"].values()) and r["scanned"] is None, r)
check("it says why", r["sourceError"] != "", r)
code, c = oper.call("GET", f"/failure-census/{r['runId']}.csv")
parsed = list(csv.reader(io.StringIO(c)))
check("the CSV's run row says unknown, and it has no rows", len(parsed) == 2 and parsed[1][parsed[0].index("eligibility")] == "unknown" and parsed[1][parsed[0].index("source_status")] == "unavailable", parsed)
out = session("%SYS", f'Set sc=##class(SYS.Database).MountDatabase("{db}") Write !,"[mount] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
check("it is mounted again", "[mount] ok" in out, out[-400:])
code, r = run("Cen Out", T0, T1)
check("and the census reads again", r["sourceRead"] == "ok" and r["totals"]["deliveries"] is not None, r)

step("A real message purge: the window is not zero failures")
out = session("CENSUS", 'Set sc=##class(Ens.MessageHeader).Purge(.n,0,0,1) Write !,"[purge] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc))," ",$GET(n),!')
check("the purge ran", "[purge] ok" in out, out[-400:])
left = int(sql_rows("CENSUS", "SELECT COUNT(*) AS N FROM Ens.MessageHeader", ["N"])[0][0])
print(f"  headers left: {left}")
code, r = run("Cen Out", T0, T1)
print(json.dumps(r["reasons"]), json.dumps(r["totals"]))
check("nothing read, and that is incomplete", r["completeness"] == "incomplete" and r["totals"]["deliveries"] == 0 and r["complete"] is False, r)
check("it says the window reaches past what is kept, and names the cases left with no evidence", ("window_older_than_kept_headers" in r["reasons"] or "header_ids_missing" in r["reasons"]) and "case_origin_purged" in r["reasons"], r)
check("those cases are unassessable", r["totals"]["unassessable"] >= 3, r)

finish()
