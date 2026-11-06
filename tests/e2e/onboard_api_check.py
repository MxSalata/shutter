#!/usr/bin/env python3
"""The Settings screen's routes for watched namespaces, played on real productions: the plan first and nothing changed, an old
plan refused, the apply with the production running, the test failure, and the removal, each answering as the helpers do.

    python3 tests/e2e/onboard_check.py --only ack --keep --ctr CTR --port PORT --image IMAGE
    python3 tests/e2e/onboard_api_check.py --ctr CTR --port PORT [--record web/src/mocks/onboarding.json]

The first line leaves a stock instance with Shutter installed and hospital namespaces running their own productions, of which
this script onboards PATHOLOGY and DOCUMENTS through the REST API. --record writes the answers the trial replays. It needs
Docker and no API key: no model is called. Exit status 1 when a check fails.
"""
import argparse
import atexit
import http.cookiejar
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

PW = "Onboard-2026x"

ap = argparse.ArgumentParser()
ap.add_argument("--ctr", required=True)
ap.add_argument("--port", type=int, required=True)
ap.add_argument("--record", default="")
args = ap.parse_args()
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


def session(ns, code, timeout=300):
    # A community instance refuses a terminal while its licence units are taken: wait, then judge what came back
    for _ in range(12):
        r = subprocess.run(["docker", "exec", "-i", args.ctr, "iris", "session", "IRIS", "-U", ns], input=code + "\nHalt\n", capture_output=True, text=True, timeout=timeout, errors="replace")
        if "LICENSE LIMIT" not in r.stdout:
            break
        time.sleep(15)
    return r.stdout


def value(ns, expr):
    out = session(ns, f'Set %v = {expr}\nWrite !,"<<<",%v,">>>",!')
    m = re.findall(r"<<<(.*?)>>>", out, re.S)
    if not m:
        raise RuntimeError(f"no value for {expr} in {ns}: {out[-800:]}")
    return m[-1]


def obj(ns, expr):
    return json.loads(value(ns, expr))


class Client:
    def __init__(self):
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, method, path, body=None, csrf=True):
        data = None if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode())
        headers = {"Content-Type": "application/json"}
        if csrf:
            headers["X-Requested-With"] = "Shutter"
        req = urllib.request.Request(URL + path, data=data, method=method, headers=headers)
        for attempt in range(4):
            try:
                with self.opener.open(req, timeout=120) as r:
                    text, code = r.read().decode(), r.status
            except urllib.error.HTTPError as e:
                text, code = e.read().decode(), e.code
            # A busy community instance can refuse a request for want of a licence unit: once more, then judge it
            if code != 503 or "icen" not in text:
                break
            time.sleep(10)
        try:
            return code, json.loads(text)
        except ValueError:
            return code, text

    def sign_in(self, user):
        code, _ = self.call("POST", "/session", {"username": user, "password": PW})
        check(f"{user} signs in", code in (200, 201), code)
        # A web session holds a licence unit, and a community instance has few: give it back however this ends
        atexit.register(self.call, "DELETE", "/session")


def untouched(ns):
    return value(ns, '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Intake.Forwarder")') == "0" and value("SHUTTER", f'$DATA(^Shutter.Config("onboard","{ns}"))') == "0"


session("SHUTTER", f'''Set $NAMESPACE="%SYS"
Set a=##class(Security.Users).Create("onbowner","Shutter_Approver,%All","{PW}","An administrator","SHUTTER","","",0,1)
Set $NAMESPACE="SHUTTER"''')

step("Who may ask")
nobody = Client()
code, _ = nobody.call("GET", "/settings/namespaces")
check("signed out: 401", code == 401, code)
appr = Client()
appr.sign_in("appr1")
code, lst = appr.call("GET", "/settings/namespaces")
check("an approver reads the list", code == 200 and lst["canApply"] is False, (code, lst))
code, pl = appr.call("POST", "/settings/namespaces/PATHOLOGY/plan", {})
print("  approver's plan:", code, json.dumps(pl.get("plan", pl) if isinstance(pl, dict) else pl)[:400])
check("an approver's plan answers, and says it cannot read a namespace its role has no database resource for", code == 200 and "Could not read" in pl["plan"]["error"], (code, pl))
code, ans = appr.call("POST", "/settings/namespaces/PATHOLOGY/apply", {"digest": "x"})
check("an approver may not apply", code == 403 and "%Admin_Manage" in ans["detail"], (code, ans))
code, ans = appr.call("POST", "/settings/namespaces/PATHOLOGY/remove", {})
check("nor take off", code == 403, (code, ans))

appr.call("DELETE", "/session")
admin = Client()
admin.sign_in("onbowner")
code, ans = admin.call("POST", "/settings/namespaces/PATHOLOGY/plan", {}, csrf=False)
check("no CSRF header: 403", code == 403 and ans["error"] == "csrf", (code, ans))
code, lst = admin.call("GET", "/settings/namespaces")
print("  list:", json.dumps({"available": lst.get("available"), "watched": [w["namespace"] for w in lst.get("watched", [])]}))
names = [a["namespace"] for a in lst["available"]]
check("an administrator may apply", lst["canApply"] is True, lst)
check("the hospital's namespaces are offered", {"PATHOLOGY", "DOCUMENTS", "PAS"} <= set(names), names)
check("Shutter's and the instance's are not", not {"SHUTTER", "%SYS", "HSLIB", "HSSYS", "HSCUSTOM"} & set(names) and not any(n.startswith("^") for n in names), names)
check("one watched already is listed as watched, not offered", "ORDERS" not in names and "ORDERS" in [w["namespace"] for w in lst["watched"]], lst)

step("The plan changes nothing")
code, first = admin.call("POST", "/settings/namespaces/PATHOLOGY/plan", {})
check("it answers with a digest", code == 200 and first["digest"].startswith("sha256:"), (code, first))
sql = obj("SHUTTER", '##class(Shutter.Setup).OnboardPlan("PATHOLOGY")')
check("the same actions as the SQL form", first["plan"]["actions"] == sql["actions"], (first["plan"]["actions"], sql["actions"]))
check("nothing changed", untouched("PATHOLOGY"))
code, again = admin.call("POST", "/settings/namespaces/PATHOLOGY/plan", {})
check("read twice, the digest is the same", again["digest"] == first["digest"], (again["digest"], first["digest"]))
code, ans = admin.call("POST", "/settings/namespaces/PATHOLOGY/plan", {"options": {"recievers": "LIMS Out"}})
check("a misspelt option is refused by name", code == 400 and "recievers" in ans["detail"], (code, ans))
code, ans = admin.call("POST", "/settings/namespaces/PATHOLOGY/plan", b'{"options": ')
check("a body that does not parse is refused", code == 400, (code, ans))
code, ans = admin.call("POST", "/settings/namespaces/SHUTTER/plan", {})
check("Shutter's own: the helper's words", code == 200 and "own namespace" in ans["plan"]["error"], (code, ans))
code, ans = admin.call("POST", "/settings/namespaces/NOSUCHNS/plan", {})
check("one that is not there: the helper's words", code == 200 and "No namespace" in ans["plan"]["error"], (code, ans))

step("Only the plan that was read may run")
code, ans = admin.call("POST", "/settings/namespaces/PATHOLOGY/apply", {})
check("no digest: refused", code == 400, (code, ans))
code, ans = admin.call("POST", "/settings/namespaces/PATHOLOGY/apply", {"digest": "0" * 64})
check("another digest: 409 with the fresh plan", code == 409 and ans["error"] == "plan_changed" and ans["digest"] == first["digest"] and ans["plan"]["actions"], (code, ans))
code, ans = admin.call("POST", "/settings/namespaces/PATHOLOGY/apply", {"digest": first["digest"], "options": {"alert_on_error": True}})
check("the digest with other options: 409", code == 409, (code, ans))
check("nothing changed", untouched("PATHOLOGY"))

record = {"namespaces": {}}
for ns in ("PATHOLOGY", "DOCUMENTS"):
    step(f"{ns}: the apply, the credential, the test")
    rec = {}
    code, plan = admin.call("POST", f"/settings/namespaces/{ns}/plan", {})
    rec["plan"] = plan
    start = time.time()
    code, a = admin.call("POST", f"/settings/namespaces/{ns}/apply", {"digest": plan["digest"]})
    print(f"  apply took {time.time() - start:.1f} s:", json.dumps(a)[:1200])
    rec["apply"] = a
    check("the apply is ok", code == 200 and a["ok"] and a["changed"], (code, a))
    check("each action of the plan is in what changed", all(x["says"] in a["changed"] for x in plan["plan"]["actions"]), (plan["plan"]["actions"], a["changed"]))
    state = value(ns, '##class(Ens.Director).GetProductionStatus(.n,.s)_"|"_$GET(s)')
    check("the production runs", state.endswith("|1"), state)
    code, after = admin.call("POST", f"/settings/namespaces/{ns}/plan", {})
    rec["planAfter"] = after
    check("a second plan has nothing to do", code == 200 and after["plan"]["actions"] == [], after["plan"]["actions"])
    code, again = admin.call("POST", f"/settings/namespaces/{ns}/apply", {"digest": after["digest"]})
    check("and a second apply changes nothing", again["ok"] and again["changed"] == [] and "Nothing to do" in again["unchanged"], again)
    code, t0 = admin.call("POST", f"/settings/namespaces/{ns}/test", {})
    check("the test names the missing credential", code == 200 and not t0["ok"] and "OnboardCredential" in t0["error"], (code, t0))
    rec["testNoCredential"] = t0
    c = session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("{ns}","shutter-fwd","{PW}")')
    check("the credential, in a terminal", '"ok":true' in c, c[-300:])
    code, t1 = admin.call("POST", f"/settings/namespaces/{ns}/test", {})
    print("  test:", json.dumps(t1)[:500])
    check("the test opens a case", code == 200 and t1["ok"] and t1["case"], (code, t1))
    rec["test"] = t1
    code, lst = admin.call("GET", "/settings/namespaces")
    w = next(x for x in lst["watched"] if x["namespace"] == ns)
    check("the list reads it as watched", w["onboarded"] and w["forwarder"] and w["alert_intake"] and w["credential"], w)
    check("and no longer offers it", ns not in [x["namespace"] for x in lst["available"]], lst["available"])
    rec["watched"] = w
    code, prev = admin.call("GET", f"/settings/namespaces/{ns}/removal")
    print("  removal:", json.dumps(prev)[:500])
    check("the removal's preview lists the items", code == 200 and prev["onboarded"] and "Shutter Forwarder" in prev["items"], (code, prev))
    rec["removal"] = prev
    check("reading it changed nothing", value("SHUTTER", f'$DATA(^Shutter.Config("onboard","{ns}"))') != "0")
    record["namespaces"][ns] = rec

step("Taking PATHOLOGY off")
code, ans = admin.call("POST", "/settings/namespaces/PATHOLOGY/remove", {"nosuch": True})
check("an option nobody knows is refused", code == 400 and "nosuch" in ans["detail"], (code, ans))
check("and it stays on", value("SHUTTER", '$DATA(^Shutter.Config("onboard","PATHOLOGY"))') != "0")
for ns in ("PATHOLOGY", "DOCUMENTS"):
    code, r = admin.call("POST", f"/settings/namespaces/{ns}/remove", {})
    print(f"  {ns} remove:", json.dumps(r)[:900])
    check(f"{ns} comes off", code == 200 and r["ok"] and r["removed"], (code, r))
    record["namespaces"][ns]["remove"] = r
    state = value(ns, '##class(Ens.Director).GetProductionStatus(.n,.s)_"|"_$GET(s)')
    check("its production still runs", state.endswith("|1"), state)
    code, plan = admin.call("POST", f"/settings/namespaces/{ns}/plan", {})
    check("and a plan would wire it again", code == 200 and any(a["do"] == "add_forwarder" for a in plan["plan"]["actions"]), plan["plan"]["actions"])
code, lst = admin.call("GET", "/settings/namespaces")
check("the list offers it again", "PATHOLOGY" in [x["namespace"] for x in lst["available"]], lst["available"])

if args.record:
    record["recordedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    record["build"] = value("SHUTTER", "$ZVERSION")
    with open(args.record, "w") as f:
        json.dump(record, f, indent=2)
        f.write("\n")

print(f"\n{passed} checks passed, {len(failed)} failed")
for f in failed:
    print("  FAILED:", f)
sys.exit(1 if failed else 0)
