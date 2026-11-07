#!/usr/bin/env python3
"""The rig for the checks of a receiver's outage: one stock instance, Shutter installed without the demo, two hospital namespaces
already running their own productions, and fake receivers on the instance's loopback address. See README.md here.

    from rig import Rig, RigBroken, RestartNotProven
    r = Rig(ctr="v11-x-o", port=52820, image="irishealth-community:2027.1.0AI.109.0")
    r.start(); r.install()
    r.listener_up(r.LIMS, {"mode": "answer", "code": "AE", "words": "Patient not found"})
    r.send(r.ROUTED_IN, r.adt("A01", "CTL1"), "ctl1")
    with r.api() as a:
        a.get("/cases")
    r.restart_production(r.SHUTTER, "Shutter.Production", "Gate")

From a shell, against a running container (exit status 3 when a restart isn't proven):

    python3 tests/e2e/v11_rig/rig.py jobs --ctr C --ns SHUTTER
    python3 tests/e2e/v11_rig/rig.py restart --ctr C --ns SHUTTER --production Shutter.Production --watch Gate

Needs Docker and no API key: no model is called. Standard library only. Every name in it is made up.
"""
import argparse
import http.cookiejar
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SITE = os.path.join(HERE, "site")
PW = "Onboard-2026x"
HOME = "/home/irisowner"
WORK = "/tmp/v11_site"
LICENCE_WAIT, LICENCE_POLL = 300, 15  # a Community instance can refuse a terminal session for minutes after a busy spell
RESTART_TRIES, RESTART_PAUSE = 30, 10


class RigBroken(Exception):
    """The rig could not set up what a check needs: this says nothing about the product."""


class RestartNotProven(RigBroken):
    """A stop and start that can't be shown to have happened: everything read after it would be false."""


def restart_verdict(before, after, watch):
    """Why these two readings of {host: job} don't show the watched host restarted, or "" when they do."""
    if not before.get(watch):
        return f"{watch} had no job before the restart: {before}"
    if not after.get(watch):
        return f"{watch} has no job after the restart: {after}"
    if before[watch] == after[watch]:
        return f"{watch} kept job {before[watch]}: the stop and start did not happen"
    return ""


def listening_in(proc_net_tcp, port):
    """Whether this text of /proc/net/tcp has a socket listening on the port. Reading it opens no connection at the receiver."""
    want = f":{port:04X}"
    for line in proc_net_tcp.splitlines()[1:]:
        fields = line.split()
        if len(fields) > 3 and fields[1].upper().endswith(want) and fields[3] == "0A":
            return True
    return False


def hl7_bytes(segments):
    return "\r".join(segments).encode("ascii") + b"\r"


def stamp():
    return time.strftime("%Y%m%d%H%M%S", time.gmtime(time.time() - 120))


class Client:
    """One signed-in user of the REST API, with its own cookie. Signed out when the with block ends, whatever happened: a session
    left open holds a licence unit on a Community instance, and a later terminal session is then refused."""

    def __init__(self, url, user, password):
        self.url, self.user, self.password = url, user, password
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.url + path, data=data, method=method, headers={"X-Requested-With": "Shutter", "Content-Type": "application/json"})
        try:
            with self.opener.open(req, timeout=60) as r:
                text, code = r.read().decode(), r.status
        except urllib.error.HTTPError as e:
            text, code = e.read().decode(), e.code
        try:
            return code, json.loads(text)
        except ValueError:
            return code, text

    def get(self, path):
        return self.call("GET", path)

    def post(self, path, body=None):
        return self.call("POST", path, body if body is not None else {})

    def sign_in(self):
        code, r = self.call("POST", "/session", {"username": self.user, "password": self.password})
        if code not in (200, 201):
            raise RigBroken(f"{self.user} could not sign in: {code} {str(r)[:300]}")

    def sign_out(self):
        return self.call("DELETE", "/session")[0]

    def __enter__(self):
        self.sign_in()
        return self

    def __exit__(self, *exc):
        self.sign_out()
        return False


class Rig:
    SHUTTER, ROUTED, PLAIN = "SHUTTER", "RIGROUTED", "RIGPLAIN"
    # The service ports messages go in at.
    ROUTED_IN, RETRY_IN, NORETRY_IN, BOUNDED_IN, ONESHOT_IN = 7601, 7611, 7612, 7613, 7614
    # The ports the operations dial: LIMS Out, Second Out and Aside Out in the routed namespace; Retry Out, NoRetry Out, Bounded
    # Out and OneShot Out in the plain one.
    LIMS, SECOND, ASIDE, RETRY, NORETRY, BOUNDED, ONESHOT = 7701, 7702, 7703, 7711, 7712, 7713, 7714
    PRODUCTIONS = {ROUTED: "V11Rig.Routed", PLAIN: "V11Rig.Plain"}
    SITE_CLASSES = {ROUTED: ("V11Rig.AlertLog", "V11Rig.RuleFn", "V11Rig.Routed", "V11Rig.Rule"), PLAIN: ("V11Rig.AlertLog", "V11Rig.Plain")}

    def __init__(self, ctr, port=0, image="irishealth-community:2027.1.0AI.109.0", module="", root=ROOT):
        if not ctr:
            raise RigBroken("name the container: a default would be shared")
        self.ctr, self.port, self.image, self.module, self.root = ctr, port, image, module, root
        self.url = f"http://127.0.0.1:{port}/api/shutter"

    # ---- Terminal sessions ----

    def run_session(self, ns, code, timeout):
        return subprocess.run(["docker", "exec", "-i", self.ctr, "iris", "session", "IRIS", "-U", ns], input=code + "\nHalt\n", capture_output=True, text=True, timeout=timeout, errors="replace")

    def session(self, ns, code, timeout=400):
        """Runs ObjectScript. A licence refusal exits 133 at once with no output, which no caller could tell from an empty answer, so it waits, then says so."""
        end = time.time() + LICENCE_WAIT
        while True:
            r = self.run_session(ns, code, timeout)
            if r.returncode != 133 and "<LICENSE LIMIT EXCEEDED>" not in (r.stdout or ""):
                return r.stdout
            if time.time() >= end:
                raise RigBroken(f"iris session in {ns} was still refused after {LICENCE_WAIT} s: exit {r.returncode}, {(r.stdout or '')[-300:]} {(r.stderr or '')[-300:]}")
            time.sleep(LICENCE_POLL)

    def value(self, ns, expr, timeout=300):
        out = self.session(ns, f'Set %v = {expr}\nWrite !,"<<<",%v,">>>",!', timeout)
        m = re.findall(r"<<<(.*?)>>>", out, re.S)
        if not m:
            raise RigBroken(f"no value for {expr} in {ns}: {out[-800:]}")
        return m[-1]

    def obj(self, ns, expr, timeout=300):
        return json.loads(self.value(ns, expr, timeout))

    def rows(self, ns, code, timeout=400):
        """What code wrote between <<< and >>>, a piece each."""
        return re.findall(r"<<<(.*?)>>>", self.session(ns, code, timeout), re.S)

    # ---- The instance and the install ----

    def start(self):
        """A fresh stock instance on the rig's port. It removes only a container of its own name."""
        subprocess.run(["docker", "rm", "-f", self.ctr], capture_output=True)
        subprocess.run(["docker", "run", "-d", "--name", self.ctr, "-p", f"127.0.0.1:{self.port}:52773", self.image, "--check-caps", "false", "--ISCAgent", "false"], check=True, capture_output=True)
        for _ in range(80):
            if b"^running" in subprocess.run(["docker", "exec", self.ctr, "iris", "qlist", "IRIS"], capture_output=True).stdout:
                break
            time.sleep(3)
        else:
            raise RigBroken(f"{self.ctr} did not start")
        time.sleep(5)

    def remove(self):
        subprocess.run(["docker", "rm", "-f", self.ctr], capture_output=True)

    def install(self):
        """Shutter without the demo in its own namespace, the site's namespaces with their productions running, an approver, the
        apply and the forwarder's credential. Its REST sign-in ends signed out, and is shown to have."""
        target = f"{HOME}/pkg/{self.module}" if self.module else f"{HOME}/pkg"
        tar = subprocess.Popen(["tar", "-C", self.root, "-cf", "-", "--exclude=.git", "--exclude=node_modules", "--exclude=web", "."], stdout=subprocess.PIPE)
        subprocess.run(["docker", "exec", "-i", "-u", "root", self.ctr, "sh", "-c", f"mkdir -p {HOME}/pkg && tar -xf - -C {HOME}/pkg && chown -R irisowner:irisowner {HOME}/pkg"], stdin=tar.stdout, check=True)
        tar.wait()
        subprocess.run(["docker", "cp", os.path.join(self.root, "vendor/ipm/zpm-0.10.10.xml"), f"{self.ctr}:/tmp/zpm.xml"], check=True)
        out = self.session("USER", f'Set sc=$SYSTEM.OBJ.Load("{HOME}/pkg/src/Shutter/Setup.cls","ck") Write !,"[ns] ",##class(Shutter.Setup).CreateNamespace("{self.SHUTTER}"),"|",!')
        if "ok|" not in out:
            raise RigBroken("Setup.cls did not reach CreateNamespace: " + out[-500:])
        out = self.session(self.SHUTTER, f'Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck")\nSet sc=##class(%IPM.Main).Shell("load {target} -Ddemo=0") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 500)
        if "RESULT: ok" not in out:
            raise RigBroken("the load failed: " + out[-800:])
        subprocess.run(["docker", "exec", self.ctr, "mkdir", "-p", WORK], check=True)
        subprocess.run(["docker", "cp", SITE + "/.", f"{self.ctr}:{WORK}"], check=True)
        for name in ("listener.py", "probe.py", "mllp_send.py"):
            subprocess.run(["docker", "cp", os.path.join(HERE, name), f"{self.ctr}:{WORK}/{name}"], check=True)
        subprocess.run(["docker", "exec", "-u", "root", self.ctr, "chown", "-R", "irisowner:irisowner", WORK], check=True)
        for ns, production in self.PRODUCTIONS.items():
            self.session(self.SHUTTER, f'Write ##class(Shutter.Setup).CreateNamespace("{ns}")')
            self.load_classes(ns, self.SITE_CLASSES[ns])
            out = self.session(ns, f'Set sc=##class(Ens.Director).StartProduction("{production}") Write !,"[start] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
            if "[start] ok" not in out:
                raise RigBroken(f"{ns} did not start {production}: {out[-600:]}")
        self.session(self.SHUTTER, f'''Set $NAMESPACE="%SYS"
Set a=##class(Security.Users).Create("appr1","Shutter_Approver","{PW}","An approver","{self.SHUTTER}","","",0,1)
Set $NAMESPACE="{self.SHUTTER}"
Set d=##class(EnsLib.Workflow.UserDefinition).CreateUser("appr1","An approver")
Set e=##class(EnsLib.Workflow.RoleDefinition).AddUserToRole("Shutter Approvers","appr1",1,"Approver")''')
        for ns in self.PRODUCTIONS:
            a = self.obj(self.SHUTTER, f'##class(Shutter.Setup).OnboardApply("{ns}","{{}}")')
            if not a.get("ok"):
                raise RigBroken(f"the apply on {ns} failed: {a}")
            c = self.session(self.SHUTTER, f'Do ##class(Shutter.Setup).OnboardCredential("{ns}","shutter-fwd","{PW}")')
            if '"ok":true' not in c:
                raise RigBroken(f"the credential on {ns} failed: {c[-300:]}")
        self.prove_sign_out()

    def load_classes(self, ns, names, folder=WORK):
        """Compiles site classes, by name, from a folder in the container. A later check copies its own there with put_file."""
        lines = [f'Set sc=$SYSTEM.OBJ.Load("{folder}/{name}.cls","ck-d") Write !,"<<<{name}|",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!' for name in names]
        out = self.session(ns, "\n".join(lines))
        for name in names:
            if f"<<<{name}|ok>>>" not in out:
                raise RigBroken(f"{name} did not compile in {ns}: {out[-800:]}")

    def put_file(self, data, name):
        """Writes these bytes to the rig's folder in the container; returns the path."""
        path = f"{WORK}/{name}"
        subprocess.run(["docker", "exec", "-i", self.ctr, "sh", "-c", f"cat > {path}"], input=data, check=True)
        return path

    # ---- The REST API, signed out afterwards ----

    def api(self, user="appr1", password=PW):
        """with rig.api() as a: a.get(path); a.post(path, body). Signs in on entry and out on leaving."""
        return Client(self.url, user, password)

    def licence_units(self):
        return int(self.value("%SYS", "$SYSTEM.License.LUConsumed()"))

    def prove_sign_out(self):
        """Signs in and out once, and raises unless the same cookie then reads 401. (seen signed in, seen signed out, licence units)."""
        with self.api() as a:
            signed_in = a.get("/me")[0]
        signed_out = a.get("/me")[0]
        if signed_in != 200 or signed_out != 401:
            raise RigBroken(f"sign-out not shown: GET /me read {signed_in} signed in and {signed_out} signed out")
        return signed_in, signed_out, self.licence_units()

    # ---- Stop and start, proven by the job number ----

    def jobs(self, ns):
        """{host: job} for the running hosts: a host that was not restarted keeps its job."""
        out = self.session(ns, 'Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate") Do rs.Execute() While rs.Next() { Write !,"<<<",rs.Get("ConfigName"),"|",rs.Get("Job"),">>>",! }')
        return dict(x.split("|", 1) for x in re.findall(r"<<<(.*?)>>>", out))

    def asked_until_done(self, ns, call, word):
        """A licence refusal skips a stop or a start with no sign but the output, so it is asked until it says it did it."""
        last = ""
        for _ in range(RESTART_TRIES):
            last = self.session(ns, f'Set sc=##class(Ens.Director).{call} Write !,"[{word}] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
            if f"[{word}] ok" in last:
                return
            time.sleep(RESTART_PAUSE)
        raise RestartNotProven(f"{word} never said it was done: {last[-400:]}")

    def restart_production(self, ns, production, watch, stop_and_start=True):
        """Stops and starts a production and proves it by the watched host's job number: (job before, job after), or
        RestartNotProven, which ends the run. A long-lived host keeps its old code until this has happened. stop_and_start False
        leaves out the stop and the start, and exists so that a check can see the failure it should give."""
        before = self.jobs(ns)
        if stop_and_start:
            self.asked_until_done(ns, "StopProduction(60,1)", "stop")
            self.asked_until_done(ns, f'StartProduction("{production}")', "start")
        after = self.jobs(ns)
        why = restart_verdict(before, after, watch)
        if why:
            raise RestartNotProven(why)
        return before[watch], after[watch]

    def production(self, ns):
        """(name, state) of the namespace's production; state 1 is running."""
        name, state = self.value(ns, '$SELECT(##class(Ens.Director).GetProductionStatus(.n,.s):$GET(n)_"|"_$GET(s),1:"|")').split("|")
        return name, state

    # ---- Fake receivers, on the instance's loopback address ----

    def listener_spec(self, port, spec):
        """Changes what a receiver answers: read afresh for each frame."""
        data = json.dumps(spec).encode()
        subprocess.run(["docker", "exec", "-i", self.ctr, "sh", "-c", f"cat > {WORK}/mode-{port}.tmp && mv {WORK}/mode-{port}.tmp {WORK}/mode-{port}"], input=data, check=True)

    def listening(self, port):
        r = subprocess.run(["docker", "exec", self.ctr, "cat", "/proc/net/tcp"], capture_output=True, text=True)
        return listening_in(r.stdout, port)

    def listener_up(self, port, spec=None, seconds=7200):
        """Starts a receiver on this port. What it hears is kept across restarts."""
        self.listener_spec(port, spec or {"mode": "up"})
        subprocess.run(["docker", "exec", "-d", self.ctr, "python3", f"{WORK}/listener.py", str(port), WORK, str(seconds)], check=True)
        for _ in range(30):
            if self.listening(port):
                return
            time.sleep(0.5)
        raise RigBroken(f"the listener on {port} did not start")

    def listener_down(self, port):
        """Nothing listening: the port refuses the connect. Fine when there was none."""
        subprocess.run(["docker", "exec", self.ctr, "touch", f"{WORK}/stop-{port}"], check=True)
        for _ in range(30):
            if not self.listening(port):
                return
            time.sleep(0.5)
        raise RigBroken(f"the listener on {port} did not stop")

    def events(self, port):
        """Everything logged on this port, in order."""
        r = subprocess.run(["docker", "exec", self.ctr, "sh", "-c", f"cat {WORK}/rx-{port}.jsonl 2>/dev/null"], capture_output=True, text=True)
        return [json.loads(line) for line in r.stdout.splitlines() if line.strip()]

    def frames(self, port):
        return [e for e in self.events(port) if e.get("event") == "frame"]

    def heard(self, port):
        """The control ids this port has heard, in order, each repeat included."""
        return [f["ctl"] for f in self.frames(port)]

    def probe(self, port, data=None, wait=3):
        """One connect from the instance's own loopback, at most one frame: REFUSED, TIMEOUT, CLOSED, CONNECTED or the MSA and ERR lines."""
        path = self.put_file(data, f"probe-{port}.hl7") if data is not None else "-"
        r = subprocess.run(["docker", "exec", self.ctr, "python3", f"{WORK}/probe.py", str(port), path, str(wait)], capture_output=True, text=True, timeout=wait + 30)
        return r.stdout.strip() or ("ERROR " + r.stderr[-300:])

    def send(self, service_port, data, name):
        """Sends these bytes, unchanged, into a service's port; returns the MSA line."""
        path = self.put_file(data, f"{name}.hl7")
        r = subprocess.run(["docker", "exec", self.ctr, "python3", f"{WORK}/mllp_send.py", str(service_port), path, "20"], capture_output=True, text=True, timeout=60)
        if "MSA|" not in r.stdout:
            raise RigBroken(f"the service on {service_port} did not take {name}: {r.stdout} {r.stderr}")
        return r.stdout.strip()

    # ---- Made-up messages ----

    def adt(self, event, control, patient=None):
        now = stamp()
        patient = patient or f"MRN{control}"
        return hl7_bytes([
            f"MSH|^~\\&|PAS|HOSP|BEDS|HOSP|{now}||ADT^{event}^ADT_A01|{control}|P|2.5.1",
            f"EVN|{event}|{now}||||{now}",
            f"PID|1||{patient}^^^HOSP^MR~9997001001^^^NHS^NH||SYNTH^{control}||19751120|F",
            f"PV1|1|I|WARD-A^BAY1^01^HOSP||||||||||||||||ENC-{control}",
        ])

    def order(self, control, patient=None):
        now = stamp()
        patient = patient or f"MRN{control}"
        return hl7_bytes([
            f"MSH|^~\\&|ORDERS|HOSP|LAB|HOSP|{now}||ORM^O01^ORM_O01|{control}|P|2.5.1",
            f"PID|1||{patient}^^^HOSP^MR~9997001001^^^NHS^NH||SYNTH^{control}||19751120|F",
            f"PV1|1|I|WARD-A^BAY1^01^HOSP||||||||||||||||ENC-{control}",
            f"ORC|NW|{control}||||||||{now}",
            f"OBR|1|{control}||FBC^Full blood count^L|||{now}",
        ])

    def result(self, control, patient=None):
        now = stamp()
        patient = patient or f"MRN{control}"
        return hl7_bytes([
            f"MSH|^~\\&|LAB|HOSP|ORDERS|HOSP|{now}||ORU^R01^ORU_R01|{control}|P|2.5.1",
            f"PID|1||{patient}^^^HOSP^MR~9997001001^^^NHS^NH||SYNTH^{control}||19751120|F",
            f"PV1|1|I|WARD-A^BAY1^01^HOSP||||||||||||||||ENC-{control}",
            f"ORC|RE|{control}",
            f"OBR|1|{control}||FBC^Full blood count^L|||{now}",
            "OBX|1|NM|HB^Haemoglobin^L||132|g/L|||||F",
        ])

    # ---- What the engine shows ----

    def headers(self, ns, target):
        """Every header of an HL7 message to this item, oldest first: [{"id", "status", "resent", "description", "control"}]."""
        code = f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID FROM Ens.MessageHeader WHERE TargetConfigName='{target}' AND MessageBodyClassName='EnsLib.HL7.Message' ORDER BY ID") While rs.%Next() {{ Set h=##class(Ens.MessageHeader).%OpenId(rs.%Get("ID")) Set m=##class(EnsLib.HL7.Message).%OpenId(h.MessageBodyId) Write !,"<<<",rs.%Get("ID"),"|",h.Status,"|",h.Resent,"|",$TRANSLATE(h.Description,"|"," "),"|",$SELECT($ISOBJECT(m):m.GetValueAt("1:10"),1:""),">>>",! }}"""
        out = []
        for row in self.rows(ns, code):
            hid, status, resent, description, control = row.split("|", 4)
            out.append({"id": hid, "status": status, "resent": resent, "description": description, "control": control})
        return out

    def log_rows(self, ns, item, like=""):
        """The Ens_Util.Log rows of an item, oldest first, the words filter optional: [{"id", "type", "session", "message", "text"}]."""
        where = f"ConfigName='{item}'" + (f" AND Text LIKE '%{like}%'" if like else "")
        code = f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT ID,Type,SessionId,MessageId,Text FROM Ens_Util.Log WHERE {where} ORDER BY ID") While rs.%Next() {{ Write !,"<<<",rs.%Get("ID"),"|",rs.%Get("Type"),"|",rs.%Get("SessionId"),"|",rs.%Get("MessageId"),"|",rs.%Get("Text"),">>>",! }}"""
        out = []
        for row in self.rows(ns, code):
            rid, kind, session, message, text = row.split("|", 4)
            out.append({"id": rid, "type": kind, "session": session, "message": message, "text": text})
        return out

    def queue(self, ns, item):
        return int(self.value(ns, f'##class(Ens.Queue).GetCount("{item}")'))

    def host(self, ns, item):
        """The engine's own row for an item: {"status", "adapter_state", "queue"}, empty when it has none."""
        code = f"""Set rs=##class(%ResultSet).%New("Ens.Util.Statistics:EnumerateHostStatus") Do rs.Execute() While rs.Next() {{ If rs.Get("Name")="{item}" {{ Write !,"<<<",rs.Get("Status"),"|",rs.Get("AdapterState"),"|",rs.Get("Queue"),">>>",! }} }}"""
        found = self.rows(ns, code)
        if not found:
            return {}
        status, adapter_state, queue = found[-1].split("|", 2)
        return {"status": status, "adapter_state": adapter_state, "queue": queue}

    def set_item(self, ns, production, item, **settings):
        """Changes settings on one item of a running production and updates it. Raises when the update isn't confirmed."""
        adapter_settings = ("JobPerConnection", "StayConnected", "QSize", "ReadTimeout", "ConnectTimeout", "AllowedIPAddresses", "IPAddress", "Port")
        lines = [f'Set p=##class(Ens.Config.Production).%OpenId("{production}")', f'For i=1:1:p.Items.Count() {{ Set it=p.Items.GetAt(i) If it.Name="{item}" {{ Quit }} }}']
        for k, v in settings.items():
            target = "Adapter" if k in adapter_settings else "Host"
            lines.append(f'Set found=0 For j=1:1:it.Settings.Count() {{ Set s=it.Settings.GetAt(j) If s.Name="{k}" {{ Set s.Value="{v}",found=1 }} }}')
            lines.append(f"If 'found {{ Set n=##class(Ens.Config.Setting).%New() Set n.Name=\"{k}\",n.Target=\"{target}\",n.Value=\"{v}\" Do it.Settings.Insert(n) }}")
        lines.append('Set sc=p.%Save() Set sc=p.SaveToClass() Set sc=##class(Ens.Director).UpdateProduction(60,1) Write !,"<<<",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),">>>",!')
        found = self.rows(ns, "\n".join(lines))
        if not found or found[-1] != "ok":
            raise RigBroken(f"{item} in {ns} did not update: {found}")

    def wait_until(self, pred, seconds=120, every=2):
        end = time.time() + seconds
        while time.time() < end:
            if pred():
                return True
            time.sleep(every)
        return bool(pred())


def main():
    ap = argparse.ArgumentParser(description="Reads a running rig's job numbers, or restarts a production and proves it.")
    ap.add_argument("action", choices=["jobs", "restart"])
    ap.add_argument("--ctr", required=True)
    ap.add_argument("--ns", required=True)
    ap.add_argument("--production")
    ap.add_argument("--watch", default="Gate")
    ap.add_argument("--no-stop-and-start", action="store_true", help="read the job twice with nothing between: it must fail")
    args = ap.parse_args()
    rig = Rig(args.ctr)
    try:
        if args.action == "jobs":
            print(json.dumps(rig.jobs(args.ns), indent=1, sort_keys=True))
            return 0
        if not args.production:
            ap.error("restart needs --production")
        before, after = rig.restart_production(args.ns, args.production, args.watch, stop_and_start=not args.no_stop_and_start)
        print(f"{args.watch}: job {before} before, job {after} after")
        return 0
    except RigBroken as e:
        print(f"RIG BROKEN: {e}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())
