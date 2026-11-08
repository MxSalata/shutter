#!/usr/bin/env python3
"""A real uninstall, on a stock instance: everything the install added goes, and a watched production keeps running.

    python3 tests/e2e/uninstall_check.py --image IMAGE --ctr NAME [--shape site|demo|into] [--module .|core] [--keep]

It records the instance before the install (namespaces, databases, mappings, resources, roles, users, web applications,
tasks, every global, every class, the Interoperability configuration, the folders under the manager directory, and each
global that mentions the product's name), installs, wires things up, runs the uninstall the way a person does
(zpm "uninstall iris-shutter"), records the instance again and compares. Whatever is new is something left behind, and
whatever is missing is something of the site's it took.

    site  Shutter without the demo in a namespace of its own; a hospital namespace with a running production is onboarded.
    demo  The demo, in USER, as a plain zpm load does; a site's user that shares a demo user's name stays.
    into  Shutter's items inside the site's own running production (-Dproduction=), in the site's namespace.

It also reloads over a live install first, since a reload must never run the uninstall, and installs again afterwards.
It needs Docker and no API key: no model is called. Run from the repository's root. Exit status 1 when a check fails.
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

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.join(HERE, "onboard_site")
ROOT = os.path.dirname(os.path.dirname(HERE))
HOME = "/home/irisowner"
PW = "Uninstall-2026x"
# The body classes that are Shutter's in its own namespace, with the demo.
DEMOPREFIXES = ("Shutter.", "Hospital.", "Downstream.")

ap = argparse.ArgumentParser()
ap.add_argument("--image", required=True)
ap.add_argument("--ctr", required=True)
ap.add_argument("--port", type=int, default=0)
ap.add_argument("--shape", choices=["site", "demo", "into"], default="site")
ap.add_argument("--module", default=".")
ap.add_argument("--keep", action="store_true")
args = ap.parse_args()
CTR = args.ctr
TARGET = f"{HOME}/pkg" if args.module == "." else f"{HOME}/pkg/{args.module}"
MODULE = "iris-shutter" if args.module == "." else "iris-shutter-core"
failed = []
passed = 0


def check(name, ok, detail=""):
    global passed
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {str(detail)[:9000]}"), flush=True)
    if ok:
        passed += 1
    else:
        failed.append(name)


def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


def session(ns, code, timeout=500):
    """Lines of ObjectScript in a session of their own. A licence refusal is retried: it says nothing about the code."""
    for _ in range(30):
        r = subprocess.run(["docker", "exec", "-i", CTR, "iris", "session", "IRIS", "-U", ns], input=code + "\nHalt\n", capture_output=True, text=True, timeout=timeout, errors="replace")
        if r.returncode != 133 and "LICENSE LIMIT" not in r.stdout:
            return r.stdout
        time.sleep(10)
    raise RuntimeError("no licence for a session in 5 minutes")


def value(ns, expr, timeout=500):
    out = session(ns, f'Set %v = {expr}\nWrite !,"<<<",%v,">>>",!', timeout)
    m = re.findall(r"<<<(.*?)>>>", out, re.S)
    if not m:
        raise RuntimeError(f"no value for {expr} in {ns}: {out[-800:]}")
    return m[-1]


def obj(ns, expr, timeout=500):
    return json.loads(value(ns, expr, timeout))


def rows(ns, section, sql):
    """Lines "section|ns|value" from a query whose one column is the value; none when the table is not readable."""
    line = f'Try {{ Set rs=##class(%SQL.Statement).%ExecDirectNoPriv(,"{sql}") While rs.%Next() {{ Write !,"<<<{section}|{ns}|",rs.%GetData(1),">>>" }} }} Catch e {{ Write !,"<<<{section}|{ns}|ERROR ",e.DisplayString(),">>>" }}'
    return line


def snapshot(namespaces):
    """The instance as sets of lines, one set per kind of thing."""
    code = [
        rows("%SYS", "namespace", "SELECT Name FROM Config.Namespaces"),
        rows("%SYS", "database", "SELECT Name FROM Config.Databases"),
        rows("%SYS", "mapping", "SELECT Namespace||'/'||Name FROM Config.MapPackages"),
        rows("%SYS", "resource", "SELECT Name FROM Security.Resources"),
        rows("%SYS", "role", "SELECT Name FROM Security.Roles"),
        rows("%SYS", "user", "SELECT Name FROM Security.Users"),
        rows("%SYS", "application", "SELECT Name||'='||Resource||'='||MatchRoles FROM Security.Applications"),
        rows("%SYS", "task", "SELECT Name FROM %SYS.Task"),
        'Set w=$SELECT(##class(%Dictionary.CompiledClass).%ExistsId("%Wallet.KeyValue"):$CLASSMETHOD("%Wallet.KeyValue","Exists","Shutter.Anthropic"),1:0) If w Write !,"<<<wallet|%SYS|Shutter.Anthropic>>>"',
    ]
    out = session("%SYS", "\n".join(code + [mention_scan("%SYS")]), 900)
    for ns in namespaces:
        code = [
            'Set g="" For { Set g=$ORDER(^$GLOBAL(g)) Quit:g=""  Write !,"<<<global|' + ns + '|",g,">>>" }',
            rows(ns, "class", "SELECT Name FROM %Dictionary.ClassDefinition WHERE Name NOT %STARTSWITH '%' AND Name NOT %STARTSWITH 'Ens' AND Name NOT %STARTSWITH 'HS' AND Name NOT %STARTSWITH 'SYS' AND Name NOT %STARTSWITH 'CSP' AND Name NOT %STARTSWITH 'INFORMATION' AND Name NOT %STARTSWITH 'Hub'"),
            rows(ns, "production", "SELECT Name FROM Ens_Config.Production"),
            rows(ns, "sql_table", "SELECT TABLE_SCHEMA||'.'||TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA %STARTSWITH 'Shutter' OR TABLE_SCHEMA %STARTSWITH 'Hospital' OR TABLE_SCHEMA %STARTSWITH 'Downstream'"),
            rows(ns, "item", "SELECT Production||'/'||Name||'/'||ClassName FROM Ens_Config.Item"),
            rows(ns, "default_setting", "SELECT ID FROM Ens_Config.DefaultSettings"),
            rows(ns, "credential", "SELECT ID FROM Ens_Config.Credentials"),
            rows(ns, "workflow_role", "SELECT Name FROM EnsLib_Workflow.RoleDefinition"),
            rows(ns, "workflow_user", "SELECT Name FROM EnsLib_Workflow.UserDefinition"),
            rows(ns, "workflow_task", "SELECT DISTINCT %RoleName FROM EnsLib_Workflow.TaskResponse"),
            rows(ns, "message_body_class", "SELECT DISTINCT MessageBodyClassName FROM Ens.MessageHeader WHERE MessageBodyClassName %STARTSWITH 'Shutter' OR MessageBodyClassName %STARTSWITH 'Hospital' OR MessageBodyClassName %STARTSWITH 'Downstream'"),
            'Set g="" For { Set g=$ORDER(^EnsHL7.Schema(g)) Quit:g=""  Write !,"<<<hl7_category|' + ns + '|",g,">>>" }',
            'Do ##class(Ens.Director).GetProductionStatus(.n,.s) If $GET(s)=1 Write !,"<<<running|' + ns + '|",$GET(n),">>>"',
            'Write !,"<<<autostart|' + ns + '|",$GET(^Ens.AutoStart),">>>"',
            mention_scan(ns),
        ]
        out += session(ns, "\n".join(code), 900)
    lines = set(re.findall(r"<<<(.*?)>>>", out))
    files = subprocess.run(["docker", "exec", CTR, "sh", "-c", "cd /usr/irissys/mgr && ls -1 && ls -1 shutter 2>/dev/null"], capture_output=True, text=True).stdout
    lines |= {"folder|mgr|" + f for f in files.split() if not re.search(r"^(iris\.|messages\.log|alerts\.log|journal|\d{8}|IRIS\.|stream|ilock|startup\.last|.*\.log$)", f)}
    return lines


def mention_scan(ns):
    """A line per global that holds the product's name anywhere, in a subscript or a value. No value is written."""
    return ('Set g="" For { Set g=$ORDER(^$GLOBAL(g)) Quit:g=""  Continue:($EXTRACT(g,1,2)="^%")&&(g\'="^%SYS")  Continue:g="^ROUTINE"  Continue:g="^rOBJ"  Continue:g="^rINDEX"  Continue:g="^rMAC"  '
            'Set c=0,k=0,q=g Try { If $DATA(@q)#2,$GET(@q)["Shutter" { Set c=1 } For { Set q=$QUERY(@q) Quit:q=""  Set k=k+1 Quit:k>400000  If (q\'["""HistoryD"""),(q\'["""NSMAPSUB"""),(q["Shutter")||($GET(@q)["Shutter") Set c=c+1 } } Catch e { Set c=-1 } If c Write !,"<<<mentions|' + ns + '|",g,">>>" }')


def compare(before, after, allowed_new=(), allowed_gone=()):
    # The engine's own working globals appear wherever a production has run. A row in one that names Shutter is still caught,
    # by the mentions line for that global and by the rows read above.
    engine = [r"^global\|[^|]*\|\^(Ens\.|EnsHL7\.Segment|IRIS\.Temp|IRIS\.Metrics\.|CacheTemp|EnsLib\.)", r"^autostart\|[^|]*\|$"]
    # IRIS for Health sets these up once, the first time a namespace is enabled for Interoperability. They are the engine's.
    # The engine's own records of what ran, which keep a name as a log does: the event log, the audit log, its interface
    # metrics, the SQL statement and catalogue indexes (no table shows: the sql_table rows), the source journal, its temporary globals and a package's name.
    engine += [r"^mentions\|[^|]*\|\^(Ens\.Util\.LogD|IRIS\.AuditD|IRIS\.Metrics\.|IRIS\.Temp|rINDEXSQL|rINDEXEXT|ISC\.Src\.Jrn|oddPKG|IPM\.General\.History)"]
    engine += [r"^(database|namespace)\|%SYS\|FHIR_Validation_Server$", r"^resource\|%SYS\|%HS(Admin_|_BFC_|_FHIRServer_)", r"^role\|%SYS\|%HS_BFC_", r"^task\|%SYS\|FHIR Purge "]
    new = sorted(x for x in after - before if not any(re.search(p, x) for p in list(allowed_new) + engine))
    gone = sorted(x for x in before - after if not any(re.search(p, x) for p in list(allowed_gone) + engine))
    check("nothing of Shutter's is left: nothing is new since before the install", not new, "\n        ".join(new))
    check("nothing of the site's was taken: nothing that was there has gone", not gone, "\n        ".join(gone))


def jobs(ns):
    out = session(ns, 'Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate") Do rs.Execute() While rs.Next() { Write !,"<<<",rs.Get("ConfigName"),"|",rs.Get("Job"),">>>",! }')
    return dict(x.split("|", 1) for x in re.findall(r"<<<(.*?)>>>", out))


def start_instance():
    step(f"A stock instance of {args.image}")
    subprocess.run(["docker", "rm", "-f", CTR], capture_output=True)
    ports = ["-p", f"127.0.0.1:{args.port}:52773"] if args.port else ["-p", "127.0.0.1::52773"]
    subprocess.run(["docker", "run", "-d", "--name", CTR, *ports, args.image, "--check-caps", "false", "--ISCAgent", "false"], check=True, capture_output=True)
    for _ in range(80):
        if b"^running" in subprocess.run(["docker", "exec", CTR, "iris", "qlist", "IRIS"], capture_output=True).stdout:
            break
        time.sleep(3)
    time.sleep(5)
    tar = subprocess.Popen(["tar", "-C", ROOT, "-cf", "-", "--exclude=.git", "--exclude=node_modules", "--exclude=web", "--exclude=run.log", "."], stdout=subprocess.PIPE)
    subprocess.run(["docker", "exec", "-i", "-u", "root", CTR, "sh", "-c", f"mkdir -p {HOME}/pkg && tar -xf - -C {HOME}/pkg && chown -R irisowner:irisowner {HOME}/pkg"], stdin=tar.stdout, check=True)
    subprocess.run(["docker", "cp", os.path.join(ROOT, "vendor/ipm/zpm-0.10.10.xml"), f"{CTR}:/tmp/zpm.xml"], check=True)
    subprocess.run(["docker", "cp", SITE + "/.", f"{CTR}:/tmp/onb_site"], check=True)
    subprocess.run(["docker", "exec", "-u", "root", CTR, "chown", "-R", "irisowner:irisowner", "/tmp/onb_site"], check=True)


def url():
    p = subprocess.run(["docker", "port", CTR, "52773/tcp"], capture_output=True, text=True).stdout.splitlines()[0].rsplit(":", 1)[1]
    return f"http://127.0.0.1:{p}"


def http_code(path):
    try:
        with urllib.request.urlopen(url() + path, timeout=20) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except OSError:
        return 0


def make_namespace(ns):
    """A plain namespace, with Interoperability on, made without any of the product's classes staying behind."""
    out = session("USER", f'''Set sc=$SYSTEM.OBJ.Load("{HOME}/pkg/src/Shutter/Setup.cls","ck-d")
Write !,"[ns] ",##class(Shutter.Setup).CreateNamespace("{ns}"),"|",!
Set sc=$SYSTEM.OBJ.Delete("Shutter.Setup","-d")''')
    check(f"the namespace {ns} is made", "ok|" in out, out[-500:])


def start_site_production(ns):
    lines = ['Set sc=##class(EnsLib.HL7.SchemaXML).Import("/tmp/onb_site/TRUSTLAB-pathology.xml") Write !,"[s] ",sc,!']
    for f in ["OnbSite.AlertLog", "OnbPath.Rule", "OnbPath.Production"]:
        lines.append(f'Set sc=$SYSTEM.OBJ.Load("/tmp/onb_site/{f}.cls","ck-d") Write !,"[c] ",sc,!')
    lines.append('Set sc=##class(Ens.Director).StartProduction("OnbPath.Production") Write !,"[start] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
    out = session(ns, "\n".join(lines))
    check(f"{ns} runs OnbPath.Production", "[start] ok" in out, out[-600:])


def load(ns, extra=""):
    start = time.time()
    out = session(ns, f'Set sc=##class(%IPM.Main).Shell("load {TARGET}{extra}") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 560)
    check(f"zpm load{extra} in {ns} ends ok, {int(time.time() - start)} s", "RESULT: ok" in out, out[-1200:])


def uninstall(ns):
    start = time.time()
    out = session(ns, f'Set sc=##class(%IPM.Main).Shell("uninstall {MODULE}") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 560)
    print(out[-2500:], flush=True)
    check(f'zpm "uninstall {MODULE}" in {ns} ends ok, {int(time.time() - start)} s', "RESULT: ok" in out, out[-1200:])


def send_order(ns, control):
    """An order through the site's own feed and router to its own LIMS: the production does its work."""
    now = time.strftime("%Y%m%d%H%M%S", time.gmtime())
    text = f"MSH|^~\\&|ORDERS|HOSP|LIMS|HOSP|{now}||ORM^O01^ORM_O01|{control}|P|2.5.1\rPID|1||MRN{control}^^^HOSP^MR||SYNTH^{control}||19751120|F\rORC|NW|{control}||||||||{now}\rOBR|1|{control}||FBC^Full blood count^L|||{now}\r"
    subprocess.run(["docker", "exec", "-i", CTR, "sh", "-c", f"cat > /tmp/onb_site/{control}.hl7"], input=text, text=True, check=True)
    r = subprocess.run(["docker", "exec", "-e", "MLLP_WAIT=20", CTR, "python3", "/tmp/onb_site/mllp.py", "7101", f"/tmp/onb_site/{control}.hl7"], capture_output=True, text=True, timeout=60)
    return r.stdout.strip() + r.stderr.strip()


def order_delivered(ns, control, seconds=40):
    """The listener at the LIMS's address has the order."""
    end = time.time() + seconds
    while time.time() < end:
        got = subprocess.run(["docker", "exec", CTR, "sh", "-c", f"cat /tmp/onb_site/lims-{ns}.log 2>/dev/null"], capture_output=True, text=True).stdout
        if control in got:
            return True
        time.sleep(1)
    return False


def lims_up(ns):
    subprocess.Popen(["docker", "exec", CTR, "python3", "/tmp/onb_site/ack_listener.py", "7201", f"/tmp/onb_site/lims-{ns}.log", "2000"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)


def production_runs(ns, production, keep_jobs):
    out = session(ns, 'Set sc=##class(Ens.Director).GetProductionStatus(.n,.s) Write !,"<<<",$GET(n),"|",$GET(s),">>>",!')
    state = re.findall(r"<<<(.*?)>>>", out)
    check(f"{production} still runs in {ns}", state and state[-1] == f"{production}|1", out[-300:])
    now = jobs(ns)
    same = {k: (keep_jobs.get(k), now.get(k)) for k in ("OrderComms In", "Path Router", "LIMS Out")}
    check("its items were not restarted: the same job numbers", all(a and a == b for a, b in same.values()), same)


def hand_item_refused(here, ns, production, name, cls, keep):
    """A second item on one of Shutter's classes, added by hand inside a production the uninstall only edits. The uninstall
    would not take it out, and it could not start once the classes are gone, so it must refuse. Definition rows only: the
    running production is not updated, so its job numbers still count."""
    out = session(ns, f'''Set p=##class(Ens.Config.Production).%OpenId("{production}") Set i=##class(Ens.Config.Item).%New() Set i.Name="{name}",i.ClassName="{cls}",i.Production=p Do p.Items.Insert(i) Set sc=p.%Save() Write !,"[hand] ",sc,!''')
    check(f"{production} has a hand-added {name} on {cls}", "[hand] 1" in out, out[-400:])
    refused = obj(here, "##class(Shutter.Util.Uninstall).Plan()")
    check(f"the plan says it would refuse, and names {name}", f"{name} in {production} ({ns})" in refused["refused"] and refused["ok"] is False, refused["refused"])
    out = session(here, f'Set sc=##class(%IPM.Main).Shell("uninstall {MODULE}") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 560)
    check("zpm uninstall fails and says why", name in out and "RESULT: ok" not in out, out[-600:])
    check("the module and the item it wired are still there", value(here, '##class(%IPM.Storage.Module).NameExists("' + MODULE + '")') == "1" and keep in jobs(ns), jobs(ns))
    out = session(ns, f'''Set p=##class(Ens.Config.Production).%OpenId("{production}") For n=p.Items.Count():-1:1 {{ Set i=p.Items.GetAt(n) If i.Name="{name}" {{ Set id=i.%Id() Do p.Items.RemoveAt(n) Do ##class(Ens.Config.Item).%DeleteId(id) }} }} Set sc=p.%Save() Write !,"[gone] ",sc,!''')
    check("the site takes it out", "[gone] 1" in out, out[-300:])


def site_globals(ns):
    """Globals of the site's whose names begin like the demo's. Neither the demo nor Shutter wrote them."""
    out = session(ns, 'Set ^Hospital.SiteOwn="site",^Wards.Beds="site",^Downstream.SiteOwn="site" Write !,"[own] ",^Wards.Beds,!')
    check(f"{ns} holds globals of its own named like the demo's", "[own] site" in out, out[-300:])


def site_globals_stay(ns):
    got = value(ns, '$GET(^Hospital.SiteOwn)_$GET(^Wards.Beds)_$GET(^Downstream.SiteOwn)')
    check(f"{ns} still holds them, where the demo was never installed", got == "sitesitesite", got)


def site_hospital_class(ns):
    """A class of the site's own called Hospital., with a message and an event log line of it. In a hospital's namespace the
    demo's prefixes are not Shutter's: the uninstall leaves all three."""
    cls = "Class Hospital.SiteNote Extends Ens.Request\n{\n\nProperty Text As %String;\n\n}\n"
    subprocess.run(["docker", "exec", "-i", CTR, "sh", "-c", "cat > /tmp/onb_site/Hospital.SiteNote.cls"], input=cls, text=True, check=True)
    out = session(ns, '''Set sc=$SYSTEM.OBJ.Load("/tmp/onb_site/Hospital.SiteNote.cls","ck-d") Write !,"[c] ",sc,!
Set b=##class(Hospital.SiteNote).%New() Set b.Text="site" Set sc=b.%Save() Write !,"<<<id|",b.%Id(),">>>",! Set h=##class(Ens.MessageHeader).%New() Set h.MessageBodyClassName="Hospital.SiteNote",h.MessageBodyId=b.%Id(),h.SourceConfigName="Site Notes",h.TargetConfigName="Site Notes" Set sc=h.%Save() Write !,"[m] ",sc,!
Do ##class(Ens.Util.Log).LogInfo("Hospital.SiteNote","Note","a line of the site's") Write !,"[l] 1",!''')
    check(f"{ns} holds a class of its own called Hospital.SiteNote, a message of it and a log line", "[c] 1" in out and "[m] 1" in out, out[-500:])
    m = re.findall(r"<<<id\|(.*?)>>>", out)
    return m[-1] if m else ""


def site_hospital_class_refused(ns):
    """The package manager's uninstall removes the module's whole Hospital and Downstream packages (its .PKG resources), so a
    class of the site's in them would go too. The uninstall refuses, with nothing changed, and names it; the site moves it out
    (exported, and deleted with its data kept), and the uninstall then runs."""
    plan = obj(ns, "##class(Shutter.Util.Uninstall).Plan()")
    check("the plan says it would refuse, and names Hospital.SiteNote", "Hospital.SiteNote" in plan["refused"] and plan["ok"] is False, plan["refused"])
    out = session(ns, f'Set sc=##class(%IPM.Main).Shell("uninstall {MODULE}") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 560)
    check("zpm uninstall fails and names the site's class", "Hospital.SiteNote" in out and "RESULT: ok" not in out, out[-800:])
    got = value(ns, '##class(%IPM.Storage.Module).NameExists("' + MODULE + '")_##class(%Dictionary.CompiledClass).%ExistsId("Hospital.SiteNote")_##class(%Dictionary.CompiledClass).%ExistsId("Hospital.Production")')
    check("the module, the site's class and the module's demo classes are all still there", got == "111", got)
    out = session(ns, 'Set sc=$SYSTEM.OBJ.Export("Hospital.SiteNote.CLS","/tmp/onb_site/SiteNote-moved.xml") Write !,"[x] ",sc,! Set sc=$SYSTEM.OBJ.Delete("Hospital.SiteNote","-d/deleteextent=0") Write !,"[d] ",sc,!')
    check("the site moves its class out of the way", "[x] 1" in out and "[d] 1" in out, out[-400:])


def site_hospital_class_stays(ns, body_id):
    """After the uninstall the site puts its class back: its message, its log line and the message's body are all still there."""
    out = session(ns, 'Set sc=$SYSTEM.OBJ.Load("/tmp/onb_site/SiteNote-moved.xml","ck-d") Write !,"[back] ",sc,!')
    check("the site's class goes back in", "[back] 1" in out, out[-400:])
    got = value(ns, f'$SELECT($ISOBJECT(##class(Hospital.SiteNote).%OpenId("{body_id}")):##class(Hospital.SiteNote).%OpenId("{body_id}").Text,1:"no row")')
    check("its message body opens, with its text", got == "site", got)
    out = session(ns, 'Set rs=##class(%SQL.Statement).%ExecDirectNoPriv(,"SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName = \'Hospital.SiteNote\'") Do rs.%Next() Write !,"<<<m|",rs.%GetData(1),">>>",! Set rs=##class(%SQL.Statement).%ExecDirectNoPriv(,"SELECT COUNT(*) FROM Ens_Util.Log WHERE SourceClass = \'Hospital.SiteNote\'") Do rs.%Next() Write !,"<<<l|",rs.%GetData(1),">>>",!')
    check("its message stays", "<<<m|1>>>" in out, out[-400:])
    check("its event log line stays", "<<<l|1>>>" in out, out[-400:])


# What of Shutter's runs the engine keeps in a namespace: every message header with whether its body is still there, the
# business process rows (Shutter's by the class each row names), the Workflow tasks and the queues.
LEFT = r"""Try { Set rs=##class(%SQL.Statement).%ExecDirectNoPriv(,"SELECT ID, MessageBodyClassName, MessageBodyId, SourceConfigName, TargetConfigName FROM Ens.MessageHeader") While rs.%Next() { Set bc=rs.%GetData(2),bi=rs.%GetData(3),ok=1 Try { Set:(bc'="")&&(bi'="") ok=+$CLASSMETHOD(bc,"%ExistsId",bi) } Catch e2 { Set ok="?" } Write !,"<<<hdr|",rs.%GetData(1),"|",bc,"|",rs.%GetData(4),"|",rs.%GetData(5),"|",ok,">>>" } } Catch e { Write !,"<<<hdr|ERROR ",e.DisplayString(),">>>" }
Set id="" For { Set id=$ORDER(^Ens.BusinessProcessD(id)) Quit:id=""  Set d=$GET(^Ens.BusinessProcessD(id)) Write !,"<<<bp|",id,"|",$SELECT((d["~Shutter.")||(d["Shutter.Process."):"shutter",1:"other"),">>>" }
Try { Set rs=##class(%SQL.Statement).%ExecDirectNoPriv(,"SELECT ID, %Subject FROM EnsLib_Workflow.TaskRequest") While rs.%Next() { Write !,"<<<taskreq|",rs.%GetData(1),"|",$TRANSLATE(rs.%GetData(2),"|<>","   "),">>>" } } Catch e { Write !,"<<<taskreq|ERROR>>>" }
Try { Set rs=##class(%SQL.Statement).%ExecDirectNoPriv(,"SELECT ID, %RoleName FROM EnsLib_Workflow.TaskResponse") While rs.%Next() { Write !,"<<<taskresp|",rs.%GetData(1),"|",rs.%GetData(2),">>>" } } Catch e { Write !,"<<<taskresp|ERROR>>>" }
Set q="" For { Set q=$ORDER(^Ens.Queue(q)) Quit:q=""  Write !,"<<<queue|",q,">>>" }"""


def shutter_items(ns, production):
    """The names of Shutter's items in a production, read while it is installed: all of Shutter.Production's, and in a
    site's production the ones its install put there."""
    out = session(ns, rows(ns, "it", f"SELECT Name FROM Ens_Config.Item WHERE Production = '{production}'"))
    names = {x.split("|", 2)[2] for x in re.findall(r"<<<(it\|.*?)>>>", out)}
    if production != "Shutter.Production":
        names &= set(value(ns, '$PARAMETER("Shutter.Setup","INSTALLITEMS")').split(","))
    return names


def leftovers(ns, items, prefixes):
    """Shutter's: headers through one of its items or of its body classes, process rows of its classes, approval tasks and
    its items' queues. The site's: every other header (and whether its body is still there) and process row."""
    left = {"headers": [], "site_headers": 0, "site_bodies_gone": [], "processes": 0, "site_processes": 0, "tasks": [], "queues": [], "errors": []}
    for x in re.findall(r"<<<(.*?)>>>", session(ns, LEFT, 900), re.S):
        p = x.split("|")
        if "ERROR" in x:
            left["errors"].append(x[:300])
        elif p[0] == "hdr" and len(p) >= 6:
            if p[2].startswith(prefixes) or p[3] in items or p[4] in items:
                left["headers"].append("|".join(p[2:5]))
            else:
                left["site_headers"] += 1
                # "?" is a body whose class is not compiled now (a site's class moved out of the way): not counted as gone.
                if p[5] == "0":
                    left["site_bodies_gone"].append("|".join(p[1:]))
        elif p[0] == "bp":
            left["processes" if p[2] == "shutter" else "site_processes"] += 1
        elif p[0] == "taskreq" and p[2].startswith("Shutter "):
            left["tasks"].append(p[2][:120])
        elif p[0] == "taskresp" and p[2] == "Shutter Approvers":
            left["tasks"].append("response " + p[1])
        elif p[0] == "queue" and p[1] in items:
            left["queues"].append(p[1])
    return left


def nothing_of_shutters_runs_left(ns, items, prefixes, before):
    """After the uninstall: none of Shutter's headers, process rows, approval tasks or queues; all of the site's, bodies too."""
    left = leftovers(ns, items, prefixes)
    check(f"{ns}: no message header of Shutter's is left, through its items or of its classes", not left["headers"], sorted(set(left["headers"]))[:30])
    check(f"{ns}: no business process row of Shutter's classes is left", left["processes"] == 0, left["processes"])
    check(f"{ns}: no approval task of Shutter's is left", not left["tasks"], left["tasks"][:10])
    check(f"{ns}: no queue of Shutter's items is left", not left["queues"], left["queues"])
    check(f"{ns}: the site's own message headers all stay", left["site_headers"] >= before["site_headers"], (before["site_headers"], left["site_headers"]))
    check(f"{ns}: each of the site's messages still has its body", not left["site_bodies_gone"], left["site_bodies_gone"][:10])
    check(f"{ns}: the site's own process rows all stay", left["site_processes"] >= before["site_processes"], (before["site_processes"], left["site_processes"]))
    check(f"{ns}: the engine's tables were all readable", not left["errors"], left["errors"])


def awaiting_approval(ns, scenario="S2"):
    """A scenario of the demo played until its case waits for a person's approval: a Workflow task open, the case's
    process waiting for the answer. No model is called: the board mode with no provider is scripted."""
    me = value(ns, "$USERNAME")
    out = session(ns, f'Set d=##class(EnsLib.Workflow.UserDefinition).CreateUser("{me}","uninstall check") Set e=##class(EnsLib.Workflow.RoleDefinition).AddUserToRole("Shutter Approvers","{me}",1,"Approver") Write !,"[wf] ",e,!')
    check("the terminal user joins the Workflow role", "[wf] 1" in out, out[-300:])
    out = session(ns, f'Write !,"<<<",##class(Shutter.Scenarios.Runner).Run("{scenario}","board"),">>>"', 1200)
    print("   ", (re.findall(r"<<<(.*?)>>>", out, re.S) or [out[-500:]])[-1][:600], flush=True)
    cases = '##class(%SQL.Statement).%ExecDirectNoPriv(,"SELECT COUNT(*) AS n FROM Shutter_Store.""Case"" WHERE State = \'awaiting_approval\'")'
    tasks = '##class(%SQL.Statement).%ExecDirectNoPriv(,"SELECT COUNT(*) AS n FROM EnsLib_Workflow.TaskResponse WHERE %RoleName = \'Shutter Approvers\'")'
    end, got = time.time() + 420, ""
    while time.time() < end:
        out = session(ns, f'Set a={cases} Do a.%Next() Set b={tasks} Do b.%Next() Write !,"<<<",a.%Get("n"),"|",b.%Get("n"),">>>",!')
        m = re.findall(r"<<<(.*?)>>>", out)
        got = m[-1] if m else out[-300:]
        if got == "1|1":
            break
        time.sleep(10)
    check(f"a case of {scenario} waits for approval, with its task open", got == "1|1", got)


def approval_task_by_hand(ns):
    """In the site's production there is no demo to play: a task such as a case's goes from Shutter's API item to its
    Workflow item, which keeps it open."""
    me = value(ns, "$USERNAME")
    out = session(ns, f"""Set d=##class(EnsLib.Workflow.UserDefinition).CreateUser("{me}","uninstall check") Set e=##class(EnsLib.Workflow.RoleDefinition).AddUserToRole("Shutter Approvers","{me}",1,"Approver")
Set sc=##class(Ens.Director).CreateBusinessService("Shutter API",.svc) Write !,"[svc] ",sc,!
Set t=##class(EnsLib.Workflow.TaskRequest).%New() Set t.%Actions="Approve,Reject",t.%Subject="Shutter C-CHECK-1: approve the resend of one movement",t.%Message="A check's task",t.%FormFields="PlanDigest,Comment"
Set sc=svc.SendRequestAsync("Shutter Approvers",t) Write !,"[sent] ",sc,! Kill svc Hang 3""")
    check("an approval task goes from Shutter API to Shutter Approvers", "[svc] 1" in out and "[sent] 1" in out, out[-500:])


def site_shape():
    step("A hospital namespace running its own production, and the namespace Shutter will go in")
    make_namespace("PATHOLOGY")
    make_namespace("SHUTTER")
    out = session("%SYS", f'Set sc=##class(Security.Users).Create("siteapprover","%Developer","{PW}","A person of the site","USER","","",0,1) Write !,sc,!')
    start_site_production("PATHOLOGY")
    out = session("SHUTTER", 'Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck") Write !,"[ipm] ",sc,!')
    check("IPM is there", "[ipm] 1" in out, out[-400:])
    lims_up("PATHOLOGY")
    check("the site's order reaches its LIMS before Shutter is there", "ERR" not in send_order("PATHOLOGY", "ORDA1") and order_delivered("PATHOLOGY", "ORDA1"))
    site_globals("SHUTTER")
    namespaces = ["USER", "PATHOLOGY", "SHUTTER"]
    step("The instance as it is before the install")
    before = snapshot(namespaces)
    print(len(before), "lines", flush=True)

    step("The install, with the demo off, and the namespace onboarded")
    load("SHUTTER", " -Ddemo=0")
    session("%SYS", 'Do ##class(Security.Users).AddRoles("siteapprover","Shutter_Approver")')
    out = session("SHUTTER", 'Set d=##class(EnsLib.Workflow.UserDefinition).CreateUser("siteapprover","A person of the site")\nSet e=##class(EnsLib.Workflow.RoleDefinition).AddUserToRole("Shutter Approvers","siteapprover",1,"Approver")\nWrite !,"[wf] ",e,!')
    check("the site's approver joins the Workflow role", "[wf] 1" in out, out[-300:])
    r = obj("SHUTTER", '##class(Shutter.Setup).OnboardApply("PATHOLOGY","")')
    check("PATHOLOGY is onboarded", r.get("ok") is True, r)
    out = session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("PATHOLOGY","shutter-fwd","{PW}")')
    check("its credential is stored", '"ok":true' in out, out[-500:])
    time.sleep(3)
    r = obj("SHUTTER", '##class(Shutter.Setup).OnboardTest("PATHOLOGY")')
    check("a marked test failure opens a case", r.get("ok") is True, r)
    forwarded = value("PATHOLOGY", "##class(%SQL.Statement).%ExecDirectNoPriv(,\"SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName %STARTSWITH 'Shutter.'\").%Next()")
    check("the watched namespace now holds messages of Shutter's classes", forwarded == "1", forwarded)
    if args.module == ".":
        out = session("SHUTTER", 'Write !,"[p] ",##class(Shutter.Setup).ConfigureProvider("placeholder-not-a-key-for-the-uninstall-check"),!')
        check("a provider is configured (a placeholder: nothing is called)", "[p] ok" in out, out[-300:])
    cases = value("SHUTTER", '$ORDER(^Shutter.Store.CaseD(""),-1)')

    step("A reload over a live install, then an upgrade to a higher version: the uninstall must not run")
    load("SHUTTER", " -Ddemo=0")
    subprocess.run(["docker", "exec", CTR, "sh", "-c", f"sed -i 's|<Version>[0-9.]*</Version>|<Version>99.0.0</Version>|' {TARGET}/module.xml"], check=True)
    load("SHUTTER", " -Ddemo=0")
    tree_version = re.search(r"<Version>([^<]+)</Version>", open(os.path.join(ROOT, args.module, "module.xml")).read()).group(1)
    subprocess.run(["docker", "exec", CTR, "sh", "-c", f"sed -i 's|<Version>99.0.0</Version>|<Version>{tree_version}</Version>|' {TARGET}/module.xml"], check=True)
    check("the case is still there", value("SHUTTER", '$ORDER(^Shutter.Store.CaseD(""),-1)') == cases, cases)
    check("PATHOLOGY is still wired", value("PATHOLOGY", '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Intake.Forwarder")') == "1")

    step("The plan says what would go, and changes nothing")
    try:
        plan = obj("SHUTTER", "##class(Shutter.Util.Uninstall).Plan()")
        print(json.dumps(plan, indent=1)[:3000], flush=True)
    except (RuntimeError, ValueError) as e:
        plan = {"removes": [], "error": str(e)[-400:]}
    check("it names the namespace, the web applications, the roles and the production", all(any(w in x for x in plan["removes"]) for w in ("PATHOLOGY", "/api/shutter", "Shutter_Operator", "Shutter.Production")), plan)
    check("the case is still there after the plan", value("SHUTTER", '$ORDER(^Shutter.Store.CaseD(""),-1)') == cases, cases)
    check("the item is still there after the plan", "Shutter Forwarder" in jobs("PATHOLOGY"))

    out = session("SHUTTER", """Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Shutter_Util.Uninstall_Plan() AS r") Do rs.%Next() Write !,"<<<",rs.%Get("r"),">>>",!""")
    check("the SQL form answers the same plan", json.loads(re.findall(r"<<<(.*?)>>>", out, re.S)[-1])["namespace"] == "SHUTTER", out[-300:])

    step("A forwarder added by hand, which the onboarding did not add: refused, with nothing changed")
    out = session("PATHOLOGY", '''Set p=##class(Ens.Config.Production).%New() Set p.Name="OnbHand.Production" Set i=##class(Ens.Config.Item).%New() Set i.Name="Hand Forwarder",i.ClassName="Shutter.Intake.Forwarder",i.Production=p Do p.Items.Insert(i) Set sc=p.%Save() Write !,"[hand] ",sc,!''')
    check("a production names Shutter's forwarder", "[hand] 1" in out, out[-400:])
    refused = obj("SHUTTER", "##class(Shutter.Util.Uninstall).Plan()")
    check("the plan says it would refuse, and names the item", "Hand Forwarder in OnbHand.Production (PATHOLOGY)" in refused["refused"] and refused["ok"] is False, refused["refused"])
    out = session("SHUTTER", f'Set sc=##class(%IPM.Main).Shell("uninstall {MODULE}") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 560)
    check("zpm uninstall fails and says why", "Hand Forwarder" in out and "RESULT: ok" not in out, out[-600:])
    check("the case, the item and the module are all still there", value("SHUTTER", '$ORDER(^Shutter.Store.CaseD(""),-1)') == cases and "Shutter Forwarder" in jobs("PATHOLOGY") and value("SHUTTER", '##class(%IPM.Storage.Module).NameExists("' + MODULE + '")') == "1")
    out = session("PATHOLOGY", 'Set sc=##class(Ens.Config.Production).%DeleteId("OnbHand.Production") Do ##class(%SQL.Statement).%ExecDirectNoPriv(,"DELETE FROM Ens_Config.Item WHERE Name = \'Hand Forwarder\'") Write !,"[gone] ",sc,!')
    check("the site takes it out", "[gone] 1" in out, out[-300:])

    step("A second forwarder added by hand inside the onboarded production: refused too, since only the recorded one is taken")
    hand_item_refused("SHUTTER", "PATHOLOGY", "OnbPath.Production", "Second Forwarder", "Shutter.Intake.Forwarder", "Shutter Forwarder")

    step("The comparison can see Shutter: the same record, while it is installed")
    during = snapshot(namespaces)
    check("the record finds the name in Shutter's own globals", "mentions|SHUTTER|^Shutter.Config" in during, sorted(x for x in during if x.startswith("mentions"))[:40])
    check("and the role, the item and the mapping", {"role|%SYS|Shutter_Operator", "mapping|%SYS|PATHOLOGY/Shutter.Intake", "item|PATHOLOGY|OnbPath.Production/Shutter Forwarder/Shutter.Intake.Forwarder"} <= during, sorted(x for x in during - before)[:60])
    if args.module == ".":
        check("and the key in the wallet", "wallet|%SYS|Shutter.Anthropic" in during)

    step("The uninstall")
    keep = jobs("PATHOLOGY")
    uninstall("SHUTTER")
    production_runs("PATHOLOGY", "OnbPath.Production", keep)
    site_globals_stay("SHUTTER")
    check("the site's order still reaches its LIMS", "ERR" not in send_order("PATHOLOGY", "ORDA2") and order_delivered("PATHOLOGY", "ORDA2"))
    check("the site's alert consumer has its name back", "Ens.Alert" in jobs("PATHOLOGY"), jobs("PATHOLOGY"))
    check("no class of Shutter's resolves in PATHOLOGY", value("PATHOLOGY", '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Intake.Forwarder")') == "0")
    check("no module is left", value("SHUTTER", '##class(%IPM.Storage.Module).NameExists("' + MODULE + '")') == "0")
    check("/shutter answers 404", http_code("/shutter/index.html") == 404, http_code("/shutter/index.html"))
    after = snapshot(namespaces)
    compare(before, after)
    r = session("%SYS", 'Kill p Do ##class(Security.Users).Get("siteapprover",.p) Write !,"<<<",p("Roles"),">>>",!')
    check("the site's own user stays, without Shutter's role", "<<<%Developer>>>" in r, r[-300:])

    step("It can be installed again, onboarded again and uninstalled again")
    load("SHUTTER", " -Ddemo=0")
    check("/shutter answers", http_code("/shutter/index.html") == 200, http_code("/shutter/index.html"))
    r = obj("SHUTTER", '##class(Shutter.Setup).OnboardApply("PATHOLOGY","")')
    check("PATHOLOGY is onboarded again", r.get("ok") is True, r)
    keep = jobs("PATHOLOGY")
    uninstall("SHUTTER")
    production_runs("PATHOLOGY", "OnbPath.Production", keep)
    compare(before, snapshot(namespaces))


def demo_shape():
    step("A site's own user with a demo user's name, then the instance as it is before the install")
    out = session("USER", 'Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck") Write !,"[ipm] ",sc,!')
    check("IPM is there", "[ipm] 1" in out, out[-400:])
    session("%SYS", f'Set sc=##class(Security.Users).Create("operator","%Developer","{PW}","Somebody of the site","USER","","",0,1,"Not ours") Write !,sc,!')
    namespaces = ["USER"]
    before = snapshot(namespaces)
    print(len(before), "lines", flush=True)

    step("The demo install, as a plain load does it")
    load("USER")
    check("/shutter answers", http_code("/shutter/index.html") == 200, http_code("/shutter/index.html"))
    check("the demo hospital runs", value("HOSPITAL", '$CASE(##class(Ens.Director).GetProductionStatus(.n,.s),1:$GET(n)_"|"_$GET(s),:"")').startswith("Hospital.Production|1"))
    cases = value("USER", '$ORDER(^Shutter.Store.CaseD(""),-1)')
    step("A reload over a live install: the uninstall must not run")
    load("USER")
    check("the hospital namespace is still there", value("%SYS", '##class(Config.Namespaces).Exists("HOSPITAL")') == "1")
    check("no case was lost", value("USER", '$ORDER(^Shutter.Store.CaseD(""),-1)') == cases, cases)

    out = session("USER", 'Write !,"<<<",##class(Shutter.Setup).HardenPortal(),">>>",!')
    check("the portal is hardened, as the public demo does", "Shutter_Portal" in out or "apps" in out, out[-500:])

    step("The plan names each demo namespace in a line of its own")
    plan = obj("USER", "##class(Shutter.Util.Uninstall).Plan()")
    for ns in ("HOSPITAL", "RECORDS"):
        check(f"the plan names {ns}", f"The namespace {ns} and its databases, made for the demo" in plan["removes"], plan["removes"])

    step("A case waiting for a person's approval as the uninstall comes")
    items = shutter_items("USER", "Shutter.Production")
    awaiting_approval("USER")
    during = leftovers("USER", items, DEMOPREFIXES)
    check("Shutter's runs are there to take: headers, a waiting process row and its task", during["headers"] and during["processes"] > 0 and during["tasks"], {k: (len(v) if isinstance(v, list) else v) for k, v in during.items()})

    step("The uninstall")
    uninstall("USER")
    check("/shutter answers 404", http_code("/shutter/index.html") == 404)
    nothing_of_shutters_runs_left("USER", items, DEMOPREFIXES, during)
    after = snapshot(namespaces)
    compare(before, after)
    r = session("%SYS", 'Kill p Do ##class(Security.Users).Get("operator",.p) Write !,"<<<",p("Roles"),"|",p("Comment"),">>>",!')
    check("the site's user named operator stays, without Shutter's role", "<<<%Developer|Not ours>>>" in r, r[-300:])

    step("It can be installed again, and uninstalled twice over with a case waiting: the uninstall's own run, then zpm's")
    load("USER")
    check("/shutter answers", http_code("/shutter/index.html") == 200)
    awaiting_approval("USER")
    during = leftovers("USER", items, DEMOPREFIXES)
    r = obj("USER", "##class(Shutter.Util.Uninstall).Run()")
    check("the uninstall's run, with the classes still there, ends ok", r.get("ok") is True, r.get("errors"))
    uninstall("USER")
    nothing_of_shutters_runs_left("USER", items, DEMOPREFIXES, during)
    compare(before, snapshot(namespaces))


def into_shape():
    step("A site's namespace running its own production, and Shutter's items to go inside it")
    make_namespace("PATHOLOGY")
    start_site_production("PATHOLOGY")
    out = session("PATHOLOGY", 'Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck") Write !,"[ipm] ",sc,!')
    check("IPM is there", "[ipm] 1" in out, out[-400:])
    lims_up("PATHOLOGY")
    site_globals("PATHOLOGY")
    body_id = site_hospital_class("PATHOLOGY")
    namespaces = ["USER", "PATHOLOGY"]
    before = snapshot(namespaces)
    print(len(before), "lines", flush=True)

    step("The install into the production")
    load("PATHOLOGY", " -Ddemo=0 -Dproduction=OnbPath.Production")
    check("Shutter's items are in the running production", "Gate" in jobs("PATHOLOGY"), jobs("PATHOLOGY"))

    step("The comparison can see Shutter: the same record, while it is installed")
    during = snapshot(namespaces)
    check("the record finds the name in Shutter's own globals", "mentions|PATHOLOGY|^Shutter.Config" in during, sorted(x for x in during if x.startswith("mentions"))[:40])
    check("and an item in the site's production", "item|PATHOLOGY|OnbPath.Production/Gate/Shutter.Operation.Gate" in during or any(x.startswith("item|PATHOLOGY|OnbPath.Production/Gate/") for x in during), sorted(during - before)[:40])

    step("A second gate added by hand inside the site's production: refused, since only Shutter's own items are taken")
    hand_item_refused("PATHOLOGY", "PATHOLOGY", "OnbPath.Production", "My Gate", "Shutter.Operation.Gate", "Gate")

    step("A class of the site's in the Hospital package: refused, since the package manager would take it with the package")
    site_hospital_class_refused("PATHOLOGY")

    step("An approval task open, and an order of the site's through its own items, as the uninstall comes")
    items = shutter_items("PATHOLOGY", "OnbPath.Production")
    approval_task_by_hand("PATHOLOGY")
    check("the site's order reaches its LIMS with Shutter there", "ERR" not in send_order("PATHOLOGY", "ORDB1") and order_delivered("PATHOLOGY", "ORDB1"))
    during = leftovers("PATHOLOGY", items, ("Shutter.",))
    check("Shutter's task is there to take, and the site has messages of its own", during["tasks"] and during["headers"] and during["site_headers"] > 0, {k: (len(v) if isinstance(v, list) else v) for k, v in during.items()})

    step("The uninstall")
    keep = jobs("PATHOLOGY")
    uninstall("PATHOLOGY")
    production_runs("PATHOLOGY", "OnbPath.Production", keep)
    nothing_of_shutters_runs_left("PATHOLOGY", items, ("Shutter.",), during)
    site_globals_stay("PATHOLOGY")
    site_hospital_class_stays("PATHOLOGY", body_id)
    check("none of Shutter's items run", not [k for k in jobs("PATHOLOGY") if k in ("Gate", "Verifier", "Shutter API", "HL7 Index")], jobs("PATHOLOGY"))
    check("the site's order still reaches its LIMS", "ERR" not in send_order("PATHOLOGY", "ORDA3") and order_delivered("PATHOLOGY", "ORDA3"))
    src = value("PATHOLOGY", '##class(%Dictionary.XDataDefinition).%OpenId("OnbPath.Production||ProductionDefinition").Data.Read(200000)["Shutter"')
    check("the production's class names nothing of Shutter's", src == "0", src)
    compare(before, snapshot(namespaces))

    step("A second uninstall, with nothing of Shutter's left, changes nothing of the site's")
    keep = jobs("PATHOLOGY")
    out = session("PATHOLOGY", f'Set sc=##class(%IPM.Main).Shell("uninstall {MODULE}") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 560)
    print(out[-600:], flush=True)
    production_runs("PATHOLOGY", "OnbPath.Production", keep)
    compare(before, snapshot(namespaces))


start_instance()
print(session("USER", 'Write !,"<<<",$ZVERSION,">>>",!')[-200:], flush=True)
{"site": site_shape, "demo": demo_shape, "into": into_shape}[args.shape]()
print(f"\n{passed} passed, {len(failed)} failed")
for f in failed:
    print("  FAILED:", f)
if not args.keep:
    subprocess.run(["docker", "rm", "-f", CTR], capture_output=True)
sys.exit(1 if failed else 0)
