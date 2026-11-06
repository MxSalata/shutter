#!/usr/bin/env python3
"""The will-this-work-here report on a stock instance, then the Doctor and the health route with a dead receiver.

    python3 tests/e2e/doctor_check.py --ctr NAME --port PORT --image IMAGE [--module core] [--keep]

Starts a stock image with nothing of Shutter on it. Gives it a namespace with a running production and loads only the two
classes the report needs: it says what it finds, by name, and changes nothing. Then installs the demo in USER, points the
connector and the evidence at a closed port, and plays a scenario: the Doctor names the dead receiver and when it last answered,
the anonymous health route still says ok (the production runs) with receivers_ok false, and it clears on the next answer.
Last, the demo hospital's alert intake is disabled and the watched namespace reads as not ok. It needs Docker and no API key: no
model is called. Run from the repository's root. Exit status 1 when a check fails.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

HOME = "/home/irisowner"
ap = argparse.ArgumentParser()
ap.add_argument("--ctr", required=True)
ap.add_argument("--port", type=int, required=True)
ap.add_argument("--image", required=True)
ap.add_argument("--module", default="", help="a folder of the repository to load, core on 2026.2")
ap.add_argument("--keep", action="store_true")
args = ap.parse_args()
CTR = args.ctr
URL = f"http://127.0.0.1:{args.port}/api/shutter"
RECEIVER = "Downstream Out"
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


def session(ns, code, timeout=500):
    r = subprocess.run(["docker", "exec", "-i", CTR, "iris", "session", "IRIS", "-U", ns], input=code + "\nHalt\n", capture_output=True, text=True, timeout=timeout, errors="replace")
    return r.stdout


def value(ns, expr):
    out = session(ns, f'Set %v = {expr}\nWrite !,"<<<",%v,">>>",!')
    m = re.findall(r"<<<(.*?)>>>", out, re.S)
    if not m:
        raise RuntimeError(f"no value for {expr} in {ns}: {out[-800:]}")
    return m[-1]


def health():
    with urllib.request.urlopen(URL + "/health", timeout=60) as r:
        return json.loads(r.read().decode())


def call(method, path, body=None, user="operator", password="shutter"):
    import base64

    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, method=method, headers={"X-Requested-With": "Shutter", "Content-Type": "application/json"})
    req.add_header("Authorization", "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode())
    req.add_header("Idempotency-Key", f"doctor-{time.time()}")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def doctor():
    return json.loads(value("USER", "##class(Shutter.Setup).Doctor(0)"))


def receiver(d):
    return next((r for r in d.get("receivers", []) if r["name"] == RECEIVER), None)


def set_port(port):
    """The connector and the evidence, at a port, through the production's own settings; the items restart."""
    code = f'''Set prod=##class(Ens.Config.Production).%OpenId("Shutter.Production")
For i=1:1:prod.Items.Count() {{ Set item=prod.Items.GetAt(i) If (item.Name="{RECEIVER}")||(item.Name="Evidence Collector")||(item.Name="Verifier") {{ Set done=0 For j=1:1:item.Settings.Count() {{ Set s=item.Settings.GetAt(j) If s.Name="HTTPPort" {{ Set s.Value="{port}",done=1 }} }} If 'done {{ Set s=##class(Ens.Config.Setting).%New(),s.Name="HTTPPort",s.Target="Adapter",s.Value="{port}" Do item.Settings.Insert(s) }} }} }}
Set sc=prod.%Save() Write !,"[save] ",sc,!
Set sc=##class(Ens.Config.Production).SaveToClass(prod) Write !,"[class] ",sc,!
Set sc=##class(Ens.Director).UpdateProduction(60,1) Write !,"[update] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!'''
    return session("USER", code)


def play(scenario, seconds=240):
    """Plays a scenario through the API, and waits until its run stops."""
    code, started = call("POST", f"/scenarios/{scenario}/run", {"mode": "rules"})
    check(f"{scenario} starts", code in (200, 201, 202), started)
    end = time.time() + seconds
    while time.time() < end:
        _, body = call("GET", "/scenarios")
        run = body.get("run") if isinstance(body, dict) else None
        if isinstance(run, dict) and run.get("state") in ("done", "failed"):
            return run
        time.sleep(3)
    return None


def wait_receiver(pred, seconds=180):
    end = time.time() + seconds
    r = None
    while time.time() < end:
        r = receiver(doctor())
        if r and pred(r):
            return r
        time.sleep(5)
    return r


# ---- before any install ----
step(f"A stock {args.image}: nothing of Shutter on it")
subprocess.run(["docker", "rm", "-f", CTR], capture_output=True)
subprocess.run(["docker", "run", "-d", "--name", CTR, "-p", f"127.0.0.1:{args.port}:52773", args.image, "--check-caps", "false", "--ISCAgent", "false"], check=True, capture_output=True)
for _ in range(60):
    if "running" in subprocess.run(["docker", "exec", CTR, "iris", "qlist", "IRIS"], capture_output=True, text=True).stdout:
        break
    time.sleep(5)
time.sleep(10)
# A folder with no history (a copy on a sandbox) goes as it is.
archive = subprocess.run(["git", "archive", "HEAD"] if os.path.isdir(".git") or os.path.isfile(".git") else ["tar", "-cf", "-", "."], capture_output=True, check=True).stdout
subprocess.run(["docker", "exec", "-i", "-u", "root", CTR, "sh", "-c", f"mkdir -p {HOME}/pkg && tar -xf - -C {HOME}/pkg && chown -R irisowner:irisowner {HOME}/pkg"], input=archive, check=True)
check("no Shutter class here", value("USER", '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Setup")') == "0")

step("A hospital's namespace, with its production running")
SITE = r'''Class Site.Production Extends Ens.Production
{
XData ProductionDefinition
{
<Production Name="Site.Production" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Lab Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7999</Setting>
    <Setting Target="Host" Name="FailureTimeout">0</Setting>
    <Setting Target="Host" Name="AlertOnError">0</Setting>
  </Item>
  <Item Name="Bed Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7998</Setting>
    <Setting Target="Host" Name="AlertOnError">1</Setting>
    <Setting Target="Host" Name="FailureTimeout">-1</Setting>
  </Item>
  <Item Name="Ens.Alert" ClassName="EnsLib.EMail.AlertOperation" PoolSize="1" Enabled="false"/>
</Production>
}
}
'''
subprocess.run(["docker", "exec", "-i", CTR, "sh", "-c", "cat > /tmp/Site.Production.cls"], input=SITE, text=True, check=True)
out = session("USER", f'''Set sc=$SYSTEM.OBJ.Load("{HOME}/pkg/src/Shutter/Setup.cls","ck-d") Write !,"[setup] ",sc,!
Write ##class(Shutter.Setup).CreateNamespace("PATHLAB"),!
Set sc=$SYSTEM.OBJ.Delete("Shutter.Setup","-d") Write !,"[gone] ",sc,!''')
check("the namespace is made", "PATHLAB" in value("%SYS", '$SELECT(##class(%SYS.Namespace).Exists("PATHLAB"):"PATHLAB",1:"none")'), out[-500:])
out = session("PATHLAB", '''Set sc=$SYSTEM.OBJ.Load("/tmp/Site.Production.cls","ck-d") Write !,"[load] ",sc,!
Set sc=##class(Ens.Director).StartProduction("Site.Production") Write !,"[start] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!''')
check("its production runs", "[start] ok" in out, out[-600:])

step("Only the two classes the report needs, in USER")
out = session("USER", f'''Set sc=$SYSTEM.OBJ.Load("{HOME}/pkg/src/Shutter/Util/Onboard.cls","ck-d") Set sc2=$SYSTEM.OBJ.Load("{HOME}/pkg/src/Shutter/Util/SiteCheck.cls","ck-d") Write !,"[load] ",$SELECT(sc&&sc2:"ok",1:$SYSTEM.Status.GetErrorText(sc)_$SYSTEM.Status.GetErrorText(sc2)),!''')
check("they load and compile alone", "[load] ok" in out, out[-1500:])


def row():
    out = session("PATHLAB", 'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Name,ClassName,Enabled FROM Ens_Config.Item ORDER BY Name") While rs.%Next() { Write !,"<<<",rs.%Get("Name"),"|",rs.%Get("ClassName"),"|",rs.%Get("Enabled"),">>>" }')
    return re.findall(r"<<<(.*?)>>>", out)


was = row()
report = json.loads(value("USER", '##class(Shutter.Util.SiteCheck).Report("PATHLAB,NOSUCH")'))
print(json.dumps(report, indent=1)[:4000])
ns = {n["namespace"]: n for n in report["namespaces"]}
said = " | ".join(c["says"] for c in ns["PATHLAB"]["checks"])
check("a namespace not there blocks, by name", ns["NOSUCH"]["verdict"] == "blocked" and report["verdict"] == "blocked", report["verdict"])
check("it reads the running production", ns["PATHLAB"]["production"] == "Site.Production" and ns["PATHLAB"]["production_state"] == "running", ns["PATHLAB"])
check("names the operation with AlertOnError off", "Lab Out raises no alert" in said, said)
check("names the one retrying forever", "Bed Out retries forever" in said, said)
check("says the site's own Ens.Alert is kept", "Site Alerts" in said, said)
check("says the verdict for the namespace", ns["PATHLAB"]["verdict"] == "changes_needed", ns["PATHLAB"]["verdict"])
check("and what it did not check", len(report["not_checked"]) >= 3, report)
check("the version fits", any(c["id"] == "version" and c["result"] == "pass" for c in report["checks"]), report["checks"])
check("the production's items are as they were", row() == was, (was, row()))
check("and the production still runs", value("PATHLAB", '##class(Ens.Director).GetProductionStatus(.n,.s) _ ":" _ s').endswith(":1"))
empty = json.loads(value("USER", '##class(Shutter.Util.SiteCheck).Report()'))
check("named no namespace, it finds the one with a production", [n["namespace"] for n in empty["namespaces"]] == ["PATHLAB"], [n["namespace"] for n in empty["namespaces"]])
printed = session("USER", 'Do ##class(Shutter.Util.SiteCheck).Print("PATHLAB")')
print(printed[-1800:])
check("the terminal form says it in lines", "Not checked:" in printed and "WARN" in printed, printed[-500:])
session("PATHLAB", 'Set sc=##class(Ens.Director).StopProduction(30,1)')
session("USER", 'Do $SYSTEM.OBJ.Delete("Shutter.Util.SiteCheck,Shutter.Util.Onboard","-d")')

# ---- the demo, and a dead receiver ----
step("The demo installed, and a receiver that answers")
subprocess.run(["docker", "exec", CTR, "sh", "-c", f"cp {HOME}/pkg/vendor/ipm/zpm-0.10.10.xml /tmp/zpm.xml"], check=True)
target = f"{HOME}/pkg/{args.module}" if args.module else f"{HOME}/pkg"
out = session("USER", f'''Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck-d") Write !,"[ipm] ",sc,!
Do ##class(%IPM.Main).Shell("load {target}") Write !,"[loaded]",!''', timeout=590)
check("the demo installs", "[loaded]" in out and "ERROR" not in out[-2000:], out[-1500:])
time.sleep(20)
d = doctor()
check("the Doctor carries the keys", "receivers" in d and "receivers_ok" in d and "watched_ok" in d, list(d)[:20])
check("a receiver nothing has read is not all clear", d["receivers_ok"] in (None, True), d["receivers_ok"])
run = play("S2")
check("S2 played", run is not None, run)
r = wait_receiver(lambda x: x["state"] == "answering")
check("after a scenario the receiver reads as answering, with a time", r and r["state"] == "answering" and r["at"], r)
answered_at = r and r["at"]
h = health()
check("health: ok and receivers_ok true", h["ok"] is True and h.get("receivers_ok") is True, h)

step("The receiver goes away: the connector and the evidence at a closed port")
WORKING_PORT = value("USER", '##class(Ens.Config.DefaultSettings).%GetSetting("Shutter.Production","Downstream Out","Shutter.Operation.Ward","Adapter","HTTPPort",.%p) _ ":" _ $GET(%p)').split(":")[-1] or "52773"
print("  the port it answers on:", WORKING_PORT)
out = set_port(1)
check("the settings took", "[update] ok" in out, out[-600:])
run = play("S2")
print("  the run:", json.dumps(run)[:300])
r = wait_receiver(lambda x: x["state"] == "no_answer")
print("  the reading:", json.dumps(r))
check("the Doctor says no answer", r and r["state"] == "no_answer", r)
check("with the time of the reading and of the last answer", r and r["at"] and r["last_answer_at"], r)
check("and the status 0 with the error", r and r["http_status"] == 0 and r["error"], r)
d = doctor()
check("receivers_ok is false", d["receivers_ok"] is False, d["receivers_ok"])
h = health()
print("  anonymous health:", json.dumps(h))
check("anonymous health: ok stays the production's", h["ok"] is True, h)
check("anonymous health: receivers_ok false, and no receiver's name", h.get("receivers_ok") is False and RECEIVER not in json.dumps(h), h)

step("It comes back")
out = set_port(WORKING_PORT)
check("the settings took", "[update] ok" in out, out[-600:])
run = play("S2")
r = wait_receiver(lambda x: x["state"] == "answering")
check("the next read clears it", r and r["state"] == "answering" and r["http_status"] > 0, r)
check("receivers_ok true again", doctor()["receivers_ok"] is True)

step("EC-126: the hospital's alert intake disabled")
w0 = next((w for w in doctor()["watched_namespaces"] if w["namespace"] == "HOSPITAL"), None)
check("HOSPITAL reads well first", w0 and w0["ok"], w0)
TOGGLE = '''Set prod=##class(Ens.Config.Production).%OpenId("Hospital.Production")
For i=1:1:prod.Items.Count() {{ Set item=prod.Items.GetAt(i) If item.Name="Ens.Alert" {{ Set item.Enabled={v} }} }}
Set sc=prod.%Save() Write !,"[save] ",sc,!'''
session("HOSPITAL", TOGGLE.format(v=0))
d = doctor()
w1 = next((w for w in d["watched_namespaces"] if w["namespace"] == "HOSPITAL"), None)
print("  HOSPITAL:", json.dumps(w1.get("problems") if w1 else None))
check("it reads not ok, and says the intake is disabled", w1 and not w1["ok"] and any("disabled" in p for p in w1["problems"]), w1)
check("watched_ok is false", d["watched_ok"] is False, d["watched_ok"])
check("anonymous health: watched_ok false, ok true", health().get("watched_ok") is False and health()["ok"] is True, health())
session("HOSPITAL", TOGGLE.format(v=1))
check("enabled again, it reads well", next(w for w in doctor()["watched_namespaces"] if w["namespace"] == "HOSPITAL")["ok"])

print(f"\n{passed} passed, {len(failed)} failed", flush=True)
for name in failed:
    print("  FAILED:", name)
if not args.keep:
    subprocess.run(["docker", "rm", "-f", CTR], capture_output=True)
sys.exit(1 if failed else 0)
