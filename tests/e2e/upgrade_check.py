#!/usr/bin/env python3
"""An upgrade through the package manager, on a stock instance: an earlier release is installed and used, then this tree
is loaded over it from the same folder, as a site does after pulling the repository. Nothing of the site's is lost and the
uninstall (the module's Clean phase) never runs.

    python3 tests/e2e/upgrade_check.py --image IMAGE --ctr NAME --old DIR [--port N] [--shape site|demo|into] [--as-version V] [--keep]

DIR is the earlier release's tree (git archive v1.0.0, say). The shapes:

    site  A hospital namespace runs its own production and is onboarded; Shutter, with the demo off, has its own namespace.
          A case is opened through the onboarding's marked test failure and a person saves the site profile.
    demo  The demo in USER, as a plain load does; a scenario opens a case and a person saves the site profile.
    into  Shutter's items inside a hospital's own running production (-Ddemo=0 -Dproduction=), in the hospital's namespace;
          a case is opened in the store and a person saves the site profile. The site's own items must come through the
          install's second run over its production unchanged.

After the upgrade it checks the case (the count, and that the first one still opens with its state), the profile, the running productions (a site's production keeps its job numbers),
the module's version, and then that a real uninstall still takes Shutter off the upgraded instance. It needs Docker and
no API key: no model is called. Run from the repository's root. Exit status 1 when a check fails.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SITE = os.path.join(HERE, "onboard_site")
ROOT = os.path.dirname(os.path.dirname(HERE))
HOME = "/home/irisowner"
PKG = f"{HOME}/pkg"
# The names of the items an install into a site's production adds (Setup.cls, INSTALLITEMS, in 1.0.0 and since).
INSTALL_ITEMS = ["HL7 Index", "Case Releaser", "Receiver Watch", "Escalation Mail", "Case Workflow", "Case Review", "Case Question", "Incident Workflow", "Evidence Collector", "Agent Conformance", "Agent Encounter", "Agent Impact", "Agent Coordinator", "Agent Board", "Gate", "Shutter Approvers", "Shutter API", "Verifier", "Case Intake", "Case Intake Store", "Second Parser"]
PW = "Upgrade-2026x"

ap = argparse.ArgumentParser()
ap.add_argument("--image", required=True)
ap.add_argument("--ctr", required=True)
ap.add_argument("--old", required=True)
ap.add_argument("--port", type=int, default=0)
ap.add_argument("--shape", choices=["site", "demo", "into"], default="site")
ap.add_argument("--as-version", default="", help="the version this tree's module.xml is given in the container, as a release would bump it")
ap.add_argument("--keep", action="store_true")
args = ap.parse_args()
CTR = args.ctr
failed = []
passed = 0


def check(name, ok, detail=""):
    global passed
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {str(detail)[:6000]}"), flush=True)
    if ok:
        passed += 1
    else:
        failed.append(name)


def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


def session(ns, code, timeout=560):
    """Lines of ObjectScript in a session of their own. A licence refusal is retried: it says nothing about the code."""
    for _ in range(30):
        r = subprocess.run(["docker", "exec", "-i", CTR, "iris", "session", "IRIS", "-U", ns], input=code + "\nHalt\n", capture_output=True, text=True, timeout=timeout, errors="replace")
        if r.returncode != 133 and "LICENSE LIMIT" not in r.stdout:
            return r.stdout
        time.sleep(10)
    raise RuntimeError("no licence for a session in 5 minutes")


def value(ns, expr):
    out = session(ns, f'Set %v = {expr}\nWrite !,"<<<",%v,">>>",!')
    m = re.findall(r"<<<(.*?)>>>", out, re.S)
    if not m:
        raise RuntimeError(f"no value for {expr} in {ns}: {out[-800:]}")
    return m[-1]


def obj(ns, expr):
    return json.loads(value(ns, expr))


def jobs(ns):
    out = session(ns, 'Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate") Do rs.Execute() While rs.Next() { Write !,"<<<",rs.Get("ConfigName"),"|",rs.Get("Job"),">>>",! }')
    return dict(x.split("|", 1) for x in re.findall(r"<<<(.*?)>>>", out))


def status(ns):
    return value(ns, '$CASE(##class(Ens.Director).GetProductionStatus(.n,.s),1:$GET(n)_"|"_$GET(s),:"")')


def put_tree(src):
    """The folder the module loads from, emptied and filled with one tree, as a pull over the same clone leaves it."""
    subprocess.run(["docker", "exec", "-u", "root", CTR, "sh", "-c", f"rm -rf {PKG} && mkdir -p {PKG}"], check=True)
    tar = subprocess.Popen(["tar", "-C", src, "-cf", "-", "--exclude=.git", "--exclude=node_modules", "--exclude=web", "--exclude=run.log", "--exclude=./old", "."], stdout=subprocess.PIPE)
    subprocess.run(["docker", "exec", "-i", "-u", "root", CTR, "sh", "-c", f"tar -xf - -C {PKG} && chown -R irisowner:irisowner {PKG}"], stdin=tar.stdout, check=True)
    tar.wait()


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
    subprocess.run(["docker", "cp", os.path.join(ROOT, "vendor/ipm/zpm-0.10.10.xml"), f"{CTR}:/tmp/zpm.xml"], check=True)
    subprocess.run(["docker", "cp", SITE + "/.", f"{CTR}:/tmp/onb_site"], check=True)
    subprocess.run(["docker", "exec", "-u", "root", CTR, "chown", "-R", "irisowner:irisowner", "/tmp/onb_site"], check=True)


def load(ns, extra=""):
    start = time.time()
    out = session(ns, f'Set sc=##class(%IPM.Main).Shell("load {PKG}{extra} -v") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 900)
    check(f"zpm load{extra} in {ns} ends ok, {int(time.time() - start)} s", "RESULT: ok" in out, out[-1500:])
    return out


def module_version(ns):
    return value(ns, '##class(%IPM.Storage.Module).NameOpen("iris-shutter").VersionString')


def case_line(ns):
    out = session(ns, 'Set rs=##class(%SQL.Statement).%ExecDirectNoPriv(,"SELECT COUNT(*), MAX(ID) FROM Shutter_Store.""Case""") Do rs.%Next() Write !,"<<<",rs.%GetData(1),"|",rs.%GetData(2),">>>",!')
    m = re.findall(r"<<<(.*?)>>>", out)
    return m[-1] if m else out[-400:]


def first_case(ns):
    """The first case, opened as an object: its id and state. A storage change that left the rows unreadable shows here."""
    out = session(ns, 'Set rs=##class(%SQL.Statement).%ExecDirectNoPriv(,"SELECT MIN(ID) FROM Shutter_Store.""Case""") Do rs.%Next() Set c=##class(Shutter.Store.Case).%OpenId(rs.%GetData(1)) Write !,"<<<",$SELECT($ISOBJECT(c):c.CaseId_"|"_c.State_"|"_c.FailureKind,1:"no row"),">>>",!')
    m = re.findall(r"<<<(.*?)>>>", out)
    return m[-1] if m else out[-400:]


def same_case(ns, before):
    """The first case after the upgrade: the same id and failure kind. Its state is printed, not compared: a running
    production carries on working the case while the upgrade loads."""
    after = first_case(ns)
    b, a = before.split("|"), after.split("|")
    check("the first case still opens: the same case and failure kind", before != "no row" and len(a) == 3 and (a[0], a[2]) == (b[0], b[2]), (before, after))
    print(f"  note  its state before and after: {b[1] if len(b) == 3 else '?'} and {a[1] if len(a) == 3 else '?'}", flush=True)


def receiver_watch(ns, production):
    """The item new in 1.1 is in the production's definition after the upgrade. Whether it runs before a restart is printed."""
    got = value(ns, f'##class(%SQL.Statement).%ExecDirectNoPriv(,"SELECT ID FROM Ens_Config.Item WHERE Production = \'{production}\' AND Name = \'Receiver Watch\'").%Next()')
    check(f"the Receiver Watch is in {production}'s definition after the upgrade", got == "1", got)
    print(f"  note  the Receiver Watch runs before any restart: {'yes' if 'Receiver Watch' in jobs(ns) else 'no'}", flush=True)


def site_items(ns, production):
    """The site's own items in its production's definition: name, class, enabled, pool size and settings."""
    names = ",".join("'" + x + "'" for x in INSTALL_ITEMS + ["Shutter Forwarder"])
    out = session(ns, f'Set rs=##class(%SQL.Statement).%ExecDirectNoPriv(,"SELECT ID FROM Ens_Config.Item WHERE Production = \'{production}\' AND Name NOT IN ({names})") While rs.%Next() {{ Set i=##class(Ens.Config.Item).%OpenId(rs.%GetData(1)) Set t="" For n=1:1:i.Settings.Count() {{ Set t=t_i.Settings.GetAt(n).Target_"."_i.Settings.GetAt(n).Name_"="_i.Settings.GetAt(n).Value_";" }} Write !,"<<<",i.Name,"|",i.ClassName,"|",i.Enabled,"|",i.PoolSize,"|",t,">>>",! }}')
    return sorted(re.findall(r"<<<(.*?)>>>", out))


def save_profile(ns):
    """A person saves the site profile: the current one, stored again under a person's source."""
    out = session(ns, 'Set row=##class(Shutter.Store.SiteProfile).Row() Set sc=##class(Shutter.Store.SiteProfile).Store(row.Json,"saved by a person","siteapprover","",.v) Write !,"<<<",sc,"|",v,">>>",!')
    check("a person saves the site profile", "<<<1|" in out, out[-500:])
    return profile_line(ns)


def profile_line(ns):
    return value(ns, '##class(Shutter.Store.SiteProfile).Row().Source_"|"_##class(Shutter.Store.SiteProfile).Row().Version_"|"_$LENGTH(##class(Shutter.Store.SiteProfile).Row().Json)')


def the_upgrade(ns, extra, old_version):
    step(f"The upgrade: this tree in the same folder, then zpm load{extra} -v over {old_version}")
    put_tree(ROOT)
    new_version = re.search(r"<Version>([^<]+)</Version>", open(os.path.join(ROOT, "module.xml")).read()).group(1)
    if args.as_version:
        subprocess.run(["docker", "exec", CTR, "sed", "-i", f"0,/<Version>[^<]*<\\/Version>/s//<Version>{args.as_version}<\\/Version>/", f"{PKG}/module.xml"], check=True)
        new_version = args.as_version
    out = load(ns, extra)
    removed = [x for x in out.splitlines() if x.strip().startswith("removed:") or x.strip().startswith("kept:")]
    check("the uninstall did not run: no line of what it removed", not removed, removed[:20])
    phases = [x.strip() for x in out.splitlines() if re.search(r"\b(START|SUCCESS|FAILURE)\s*$", x)]
    print("phases:", phases, flush=True)
    clean = [x for x in phases if re.search(r"\bClean\b", x)]
    check("the package manager ran no Clean phase", phases and not clean, clean[:20] or "no phase lines in the output")
    check(f"the module is now {new_version}", module_version(ns) == new_version, module_version(ns))
    check("the uninstall is there for later", value(ns, '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Util.Uninstall")') == "1")
    return out


def uninstall_after(ns):
    step("A real uninstall of the upgraded instance")
    start = time.time()
    out = session(ns, 'Set sc=##class(%IPM.Main).Shell("uninstall iris-shutter") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 900)
    print(out[-2500:], flush=True)
    check(f'zpm "uninstall iris-shutter" in {ns} ends ok, {int(time.time() - start)} s', "RESULT: ok" in out, out[-1200:])
    check("no module is left", value(ns, '##class(%IPM.Storage.Module).NameExists("iris-shutter")') == "0")


def site_shape():
    step("A hospital namespace running its own production, and the namespace Shutter will go in")
    for ns in ("PATHOLOGY", "SHUTTER"):
        out = session("USER", f'''Set sc=$SYSTEM.OBJ.Load("{HOME}/old/src/Shutter/Setup.cls","ck-d")
Write !,"[ns] ",##class(Shutter.Setup).CreateNamespace("{ns}"),"|",!
Set sc=$SYSTEM.OBJ.Delete("Shutter.Setup","-d")''')
        check(f"the namespace {ns} is made", "ok|" in out, out[-500:])
    session("%SYS", f'Set sc=##class(Security.Users).Create("siteapprover","%Developer","{PW}","A person of the site","USER","","",0,1) Write !,sc,!')
    lines = ['Set sc=##class(EnsLib.HL7.SchemaXML).Import("/tmp/onb_site/TRUSTLAB-pathology.xml") Write !,"[s] ",sc,!']
    for f in ["OnbSite.AlertLog", "OnbPath.Rule", "OnbPath.Production"]:
        lines.append(f'Set sc=$SYSTEM.OBJ.Load("/tmp/onb_site/{f}.cls","ck-d") Write !,"[c] ",sc,!')
    lines.append('Set sc=##class(Ens.Director).StartProduction("OnbPath.Production") Write !,"[start] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
    out = session("PATHOLOGY", "\n".join(lines))
    check("PATHOLOGY runs OnbPath.Production", "[start] ok" in out, out[-600:])
    out = session("SHUTTER", 'Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck") Write !,"[ipm] ",sc,!')
    check("IPM is there", "[ipm] 1" in out, out[-400:])

    step("The earlier release, with the demo off, onboarded and used")
    load("SHUTTER", " -Ddemo=0")
    old_version = module_version("SHUTTER")
    print("installed:", old_version, flush=True)
    r = obj("SHUTTER", '##class(Shutter.Setup).OnboardApply("PATHOLOGY","")')
    check("PATHOLOGY is onboarded", r.get("ok") is True, r)
    out = session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("PATHOLOGY","shutter-fwd","{PW}")')
    check("its credential is stored", '"ok":true' in out, out[-500:])
    time.sleep(3)
    r = obj("SHUTTER", '##class(Shutter.Setup).OnboardTest("PATHOLOGY")')
    check("a marked test failure opens a case", r.get("ok") is True, r)
    time.sleep(5)
    before_cases = case_line("SHUTTER")
    check("the store holds the case", not before_cases.startswith("0|") and "|" in before_cases, before_cases)
    before_first = first_case("SHUTTER")
    before_profile = save_profile("SHUTTER")
    before_status = status("SHUTTER")
    check("Shutter.Production runs", before_status == "Shutter.Production|1", before_status)
    site_jobs = jobs("PATHOLOGY")
    gate_before = jobs("SHUTTER").get("Gate")
    before_onboard = value("SHUTTER", '$GET(^Shutter.Config("onboard","PATHOLOGY"))')
    print("before:", before_cases, before_profile, before_status, before_onboard, site_jobs, flush=True)

    the_upgrade("SHUTTER", " -Ddemo=0", old_version)
    check("the case is still there", case_line("SHUTTER") == before_cases, (before_cases, case_line("SHUTTER")))
    same_case("SHUTTER", before_first)
    receiver_watch("SHUTTER", "Shutter.Production")
    check("the person's site profile is still the current one, unchanged", profile_line("SHUTTER") == before_profile, (before_profile, profile_line("SHUTTER")))
    check("Shutter.Production runs after the upgrade", status("SHUTTER") == "Shutter.Production|1", status("SHUTTER"))
    print("the Gate's job before and after the upgrade (a new one means the new code runs):", gate_before, jobs("SHUTTER").get("Gate"), flush=True)
    check("PATHOLOGY's onboarding is still recorded", value("SHUTTER", '$GET(^Shutter.Config("onboard","PATHOLOGY"))') == before_onboard, before_onboard)
    check("OnbPath.Production still runs", status("PATHOLOGY") == "OnbPath.Production|1", status("PATHOLOGY"))
    now = jobs("PATHOLOGY")
    same = {k: (site_jobs.get(k), now.get(k)) for k in ("OrderComms In", "Path Router", "LIMS Out")}
    check("the site's items were not restarted: the same job numbers", all(a and a == b for a, b in same.values()), same)
    check("the onboarded forwarder is still in the site's production", "Shutter Forwarder" in now, now)
    r = obj("SHUTTER", '##class(Shutter.Setup).OnboardTest("PATHOLOGY")')
    check("a marked test failure still opens a case after the upgrade", r.get("ok") is True, r)

    uninstall_after("SHUTTER")
    check("OnbPath.Production still runs after the uninstall", status("PATHOLOGY") == "OnbPath.Production|1", status("PATHOLOGY"))
    now = jobs("PATHOLOGY")
    same = {k: (site_jobs.get(k), now.get(k)) for k in ("OrderComms In", "Path Router", "LIMS Out")}
    check("and its items keep their job numbers", all(a and a == b for a, b in same.values()), same)
    check("none of Shutter's items run there", "Shutter Forwarder" not in now, now)


def demo_shape():
    out = session("USER", 'Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck") Write !,"[ipm] ",sc,!')
    check("IPM is there", "[ipm] 1" in out, out[-400:])
    step("The earlier release's demo, as a plain load does it, and a scenario played")
    load("USER")
    old_version = module_version("USER")
    print("installed:", old_version, flush=True)
    session("%SYS", f'Set sc=##class(Security.Users).Create("siteapprover","%Developer","{PW}","A person of the site","USER","","",0,1) Write !,sc,!')
    r = obj("USER", '##class(Shutter.Scenarios.Runner).Run("S1","board")')
    check("scenario S1 plays", "error" not in r, r)
    time.sleep(5)
    before_cases = case_line("USER")
    check("the store holds a case", not before_cases.startswith("0|") and "|" in before_cases, before_cases)
    before_first = first_case("USER")
    before_profile = save_profile("USER")
    check("Shutter.Production runs", status("USER") == "Shutter.Production|1", status("USER"))
    check("the demo hospital runs", status("HOSPITAL").startswith("Hospital.Production|1"), status("HOSPITAL"))
    print("before:", before_cases, before_profile, flush=True)

    the_upgrade("USER", "", old_version)
    check("the cases are still there", case_line("USER") == before_cases, (before_cases, case_line("USER")))
    same_case("USER", before_first)
    receiver_watch("USER", "Shutter.Production")
    check("the person's site profile is still the current one, unchanged", profile_line("USER") == before_profile, (before_profile, profile_line("USER")))
    check("Shutter.Production runs after the upgrade", status("USER") == "Shutter.Production|1", status("USER"))
    check("the demo hospital still runs", status("HOSPITAL").startswith("Hospital.Production|1"), status("HOSPITAL"))
    check("the HOSPITAL namespace is still there", value("%SYS", '##class(Config.Namespaces).Exists("HOSPITAL")') == "1")
    uninstall_after("USER")
    check("the HOSPITAL namespace went with the demo", value("%SYS", '##class(Config.Namespaces).Exists("HOSPITAL")') == "0")


def into_shape():
    step("A hospital namespace running its own production, which Shutter's items will go inside")
    out = session("USER", f'''Set sc=$SYSTEM.OBJ.Load("{HOME}/old/src/Shutter/Setup.cls","ck-d")
Write !,"[ns] ",##class(Shutter.Setup).CreateNamespace("PATHOLOGY"),"|",!
Set sc=$SYSTEM.OBJ.Delete("Shutter.Setup","-d")''')
    check("the namespace PATHOLOGY is made", "ok|" in out, out[-500:])
    session("%SYS", f'Set sc=##class(Security.Users).Create("siteapprover","%Developer","{PW}","A person of the site","USER","","",0,1) Write !,sc,!')
    lines = ['Set sc=##class(EnsLib.HL7.SchemaXML).Import("/tmp/onb_site/TRUSTLAB-pathology.xml") Write !,"[s] ",sc,!']
    for f in ["OnbSite.AlertLog", "OnbPath.Rule", "OnbPath.Production"]:
        lines.append(f'Set sc=$SYSTEM.OBJ.Load("/tmp/onb_site/{f}.cls","ck-d") Write !,"[c] ",sc,!')
    lines.append('Set sc=##class(Ens.Director).StartProduction("OnbPath.Production") Write !,"[start] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
    lines.append('Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck") Write !,"[ipm] ",sc,!')
    out = session("PATHOLOGY", "\n".join(lines))
    check("PATHOLOGY runs OnbPath.Production, and IPM is there", "[start] ok" in out and "[ipm] 1" in out, out[-600:])
    site_before = site_items("PATHOLOGY", "OnbPath.Production")
    check("the site's own items are read", len(site_before) >= 3, site_before)

    step("The earlier release, inside the site's production, and used")
    extra = " -Ddemo=0 -Dproduction=OnbPath.Production"
    load("PATHOLOGY", extra)
    old_version = module_version("PATHOLOGY")
    print("installed:", old_version, flush=True)
    check("Shutter's items run inside the site's production", "Gate" in jobs("PATHOLOGY"), jobs("PATHOLOGY"))
    # A case in the store, as the intake opens one: a delivery failure of one operation.
    out = session("PATHOLOGY", 'Set op={"operation_key":"upgrade-check-1","encounter_id":"E1","patient_id":"P1","patient_id_authority":"HOSP","source_system":"PAS","event":"A01","event_time":"2026-11-08T10:00:00Z"} Set sc=##class(Shutter.Store.Case).Open(op,"delivery_failed","The receiver refused the connection","","","board",.c,.o) Write !,"[case] ",sc,"|",$SELECT($ISOBJECT(c):c.CaseId,1:""),!')
    check("a case is opened in the store", "[case] 1|" in out, out[-500:])
    before_cases = case_line("PATHOLOGY")
    before_first = first_case("PATHOLOGY")
    before_profile = save_profile("PATHOLOGY")
    site_jobs = jobs("PATHOLOGY")
    site_mid = site_items("PATHOLOGY", "OnbPath.Production")
    check("the install left the site's own items as they were", site_mid == site_before, (site_before, site_mid))
    print("before:", before_cases, before_first, before_profile, site_jobs, flush=True)

    the_upgrade("PATHOLOGY", extra, old_version)
    check("the case is still there", case_line("PATHOLOGY") == before_cases, (before_cases, case_line("PATHOLOGY")))
    same_case("PATHOLOGY", before_first)
    check("the person's site profile is still the current one, unchanged", profile_line("PATHOLOGY") == before_profile, (before_profile, profile_line("PATHOLOGY")))
    check("OnbPath.Production still runs", status("PATHOLOGY") == "OnbPath.Production|1", status("PATHOLOGY"))
    now = jobs("PATHOLOGY")
    same = {k: (site_jobs.get(k), now.get(k)) for k in ("OrderComms In", "Path Router", "LIMS Out")}
    check("the site's items were not restarted: the same job numbers", all(a and a == b for a, b in same.values()), same)
    site_after = site_items("PATHOLOGY", "OnbPath.Production")
    check("the site's own items are unchanged in the definition: names, classes, enabled, pool sizes and settings", site_after == site_before, (site_before, site_after))
    check("Shutter's Gate still runs inside it", "Gate" in now, now)
    receiver_watch("PATHOLOGY", "OnbPath.Production")

    uninstall_after("PATHOLOGY")
    check("OnbPath.Production still runs after the uninstall", status("PATHOLOGY") == "OnbPath.Production|1", status("PATHOLOGY"))
    now = jobs("PATHOLOGY")
    same = {k: (site_jobs.get(k), now.get(k)) for k in ("OrderComms In", "Path Router", "LIMS Out")}
    check("and its items keep their job numbers", all(a and a == b for a, b in same.values()), same)
    check("none of Shutter's items run there", not [k for k in now if k in INSTALL_ITEMS], now)
    check("the site's own items are still as they were", site_items("PATHOLOGY", "OnbPath.Production") == site_before, site_items("PATHOLOGY", "OnbPath.Production"))


start_instance()
print(session("USER", 'Write !,"<<<",$ZVERSION,">>>",!')[-200:], flush=True)
# The earlier tree, in the folder the module loads from and a copy for the namespace helper.
put_tree(os.path.abspath(args.old))
subprocess.run(["docker", "exec", "-u", "root", CTR, "sh", "-c", f"cp -r {PKG} {HOME}/old && chown -R irisowner:irisowner {HOME}/old"], check=True)
{"site": site_shape, "demo": demo_shape, "into": into_shape}[args.shape]()
print(f"\n{passed} passed, {len(failed)} failed")
for f in failed:
    print("  FAILED:", f)
if not args.keep:
    subprocess.run(["docker", "rm", "-f", CTR], capture_output=True)
sys.exit(1 if failed else 0)
