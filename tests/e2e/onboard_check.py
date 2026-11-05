#!/usr/bin/env python3
"""The whole multi-namespace onboarding (docs/INSTALL.md section 9), played on a real instance, on stock classes.

    python3 tests/e2e/onboard_check.py [--reuse] [--keep] [--port 52790] [--ctr onb-check] [--image IMAGE] [--module core] [--only ack|fanout]

Starts a stock IRIS for Health image, installs Shutter without the demo in its own namespace, gives the instance hospital
namespaces with their own productions already running (order comms and a LIMS, documents, a PAS, and two for the later sections), and onboards them with
Shutter.Setup_OnboardPlan, _OnboardApply, OnboardCredential and _OnboardTest: the plan changes nothing; the apply wires the
namespace and a second apply has nothing to do; no production stops; an item and a schema category named alike in two
namespaces stay apart; the Doctor reports each namespace; failures open cases with nothing sent; a person fills in one
receiver's API and a recovery reaches it; a reload keeps it; a message routed to two receivers opens a case for each, and the
Doctor keeps what a refused forward and a later operation leave behind; a reply of each code is sent to a listener to see what
completes, and an application NACK on its own feed opens a case; and _OnboardRemove takes the namespaces off again. It needs
Docker and no API key: no model is called. Run from the repository's root. --reuse keeps a running container and what it
has (for repeating a later step while building it); --keep leaves the container; --module loads that folder of the repository
(core, on 2026.2); --only plays one of the last two sections and stops. Exit status 1 when a check fails.
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
SITE = os.path.join(HERE, "onboard_site")
ROOT = os.path.dirname(os.path.dirname(HERE))
PW = "Onboard-2026x"
HOME = "/home/irisowner"

ap = argparse.ArgumentParser()
ap.add_argument("--reuse", action="store_true")
ap.add_argument("--keep", action="store_true")
ap.add_argument("--port", type=int, default=52790)
ap.add_argument("--ctr", default="onb-check")
ap.add_argument("--image", default="irishealth-community:2027.1.0AI.109.0")
ap.add_argument("--module", default="")
ap.add_argument("--only", choices=["ack", "fanout"])
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
    """One ObjectScript expression's value, on a line of its own."""
    out = session(ns, f'Set %v = {expr}\nWrite !,"<<<",%v,">>>",!', timeout)
    m = re.findall(r"<<<(.*?)>>>", out, re.S)
    if not m:
        raise RuntimeError(f"no value for {expr} in {ns}: {out[-800:]}")
    return m[-1]


def obj(ns, expr, timeout=300):
    return json.loads(value(ns, expr, timeout))


def status(ns, expr, timeout=300):
    """Runs an expression that gives a %Status; "ok" or its text."""
    return value(ns, f'$SELECT(({expr}): "ok", 1: $SYSTEM.Status.GetErrorText($GET(%st)))', timeout)


jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, method=method, headers={"X-Requested-With": "Shutter", "Content-Type": "application/json"})
    try:
        with opener.open(req, timeout=60) as r:
            text, code = r.read().decode(), r.status
    except urllib.error.HTTPError as e:
        text, code = e.read().decode(), e.code
    try:
        return code, json.loads(text)
    except ValueError:
        return code, text


def post_intake(body, user="shutter-fwd", password=PW):
    # The forwarder's own route, with its own one-off sign-in: a separate opener, so the approver's cookie stays put.
    req = urllib.request.Request(URL + "/intake", data=json.dumps(body).encode(), method="POST", headers={"X-Requested-With": "Shutter", "Content-Type": "application/json"})
    import base64
    req.add_header("Authorization", "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode())
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def plan(ns, options=None):
    opt = json.dumps(options or {}).replace('"', '""')
    return obj("SHUTTER", f'##class(Shutter.Setup).OnboardPlan("{ns}","{opt}")')


def apply_(ns, options=None):
    opt = json.dumps(options or {}).replace('"', '""')
    return obj("SHUTTER", f'##class(Shutter.Setup).OnboardApply("{ns}","{opt}")')


def remove(ns, options=None):
    opt = json.dumps(options or {}).replace('"', '""')
    return obj("SHUTTER", f'##class(Shutter.Setup).OnboardRemove("{ns}","{opt}")')


def raw(proc, ns, options):
    """A procedure given the options exactly as written, slips included."""
    text = options.replace('"', '""')
    return obj("SHUTTER", f'##class(Shutter.Setup).{proc}("{ns}","{text}")')


def test_forward(ns):
    return obj("SHUTTER", f'##class(Shutter.Setup).OnboardTest("{ns}")')


def doctor():
    return obj("SHUTTER", "##class(Shutter.Setup).Doctor(1)")


def watched(ns):
    return next((w for w in doctor().get("watched_namespaces", []) if w["namespace"] == ns), None)


def jobs(ns):
    """The running hosts and their job numbers: a host that was not restarted keeps its job."""
    out = session(ns, 'Set rs=##class(%ResultSet).%New("Ens.Job:Enumerate") Do rs.Execute() While rs.Next() { Write !,"<<<",rs.Get("ConfigName"),"|",rs.Get("Job"),">>>",! }')
    return dict(x.split("|", 1) for x in re.findall(r"<<<(.*?)>>>", out))


def wait_case(pred, seconds=60):
    end = time.time() + seconds
    last = None
    while time.time() < end:
        code, r = api("GET", "/cases")
        last = r
        if code == 200:
            hit = [c for c in r.get("items", []) if pred(c)]
            if hit:
                return hit
        time.sleep(2)
    print("        no such case; the list:", json.dumps(last)[:600])
    return []


def settled(case_id, seconds=60):
    """The case once its workflow has stopped moving."""
    end = time.time() + seconds
    while time.time() < end:
        _, c = api("GET", "/cases/" + case_id)
        if c.get("state") in ("escalated", "blocked", "resolved", "failed", "awaiting_approval", "waiting"):
            return c
        time.sleep(2)
    return c


def gate_codes(case_id):
    _, r = api("GET", f"/cases/{case_id}/blocked-reason")
    return json.dumps(r)


def hl7(kind, control, seg_extra=""):
    now = time.strftime("%Y%m%d%H%M%S", time.gmtime(time.time() - 120))
    pid = f"PID|1||MRN{control}^^^HOSP^MR~9997001001^^^NHS^NH||SYNTH^{control}||19751120|F"
    pv1 = f"PV1|1|I|WARD-A^BAY1^{control[-2:]}^HOSP||||||||||||||||ENC-{control}|||||||||||||||||||||||||{now}"
    if kind == "orm":
        return [f"MSH|^~\\&|ICE|HOSP|LIMS|HOSP|{now}||ORM^O01^ORM_O01|{control}|P|2.5.1", pid, pv1, f"ORC|NW|{control}||||||||{now}", f"OBR|1|{control}||FBC^Full blood count^L|||{now}"]
    if kind == "oru":
        return [f"MSH|^~\\&|LIMS|HOSP|ICE|HOSP|{now}||ORU^R01^ORU_R01|{control}|P|2.5.1", pid, pv1, f"ORC|RE|{control}", f"OBR|1|{control}||FBC^Full blood count^L|||{now}", "OBX|1|NM|HB^Haemoglobin^L||132|g/L|||||F"] + ([seg_extra] if seg_extra else [])
    if kind == "a01":
        return [f"MSH|^~\\&|PAS|HOSP|BEDS|HOSP|{now}||ADT^A01^ADT_A01|{control}|P|2.5.1", f"EVN|A01|{now}||||{now}", pid, pv1]
    if kind == "a08":
        return [f"MSH|^~\\&|PAS|HOSP|X|HOSP|{now}||ADT^A08^ADT_A01|A08FIXED|P|2.5.1", f"EVN|A08|20261105010000||||20261105010000", "PID|1||MRN70^^^HOSP^MR||SYNTH^SAME||19751120|F", "PV1|1|I|WARD-A^BAY1^70^HOSP||||||||||||||||ENC-SAME"]
    raise ValueError(kind)


def send(port, segs, name, wait=20):
    text = "\r".join(segs) + "\r"
    subprocess.run(["docker", "exec", "-i", CTR, "sh", "-c", f"cat > /tmp/onb_site/{name}.hl7"], input=text, text=True, check=True)
    r = subprocess.run(["docker", "exec", "-e", f"MLLP_WAIT={wait}", CTR, "python3", "/tmp/onb_site/mllp.py", str(port), f"/tmp/onb_site/{name}.hl7"], capture_output=True, text=True, timeout=60)
    return r.stdout.strip()


def alert_log(ns, after=0):
    """What the site's own consumer has been given since entry number after: {number: "item | words"}."""
    out = session(ns, f'Set k={after} For {{ Set k=$ORDER(^OnbSite.Alerts(k),1,v) Quit:k=""  Write !,"<<<",k,"|",v,">>>",! }}')
    return {int(a.split("|", 1)[0]): a.split("|", 1)[1] for a in re.findall(r"<<<(.*?)>>>", out)}


def statuses(ns, targets, control):
    """{target: (status, error words)} of the message with this control id, from its headers to those items."""
    code = f"""Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 400 ID,TargetConfigName FROM Ens.MessageHeader WHERE MessageBodyClassName='EnsLib.HL7.Message' ORDER BY ID DESC") While rs.%Next() {{ Set h=##class(Ens.MessageHeader).%OpenId(rs.%Get("ID")),m=##class(EnsLib.HL7.Message).%OpenId(h.MessageBodyId) If $ISOBJECT(m),m.GetValueAt("1:10")="{control}" {{ Write !,"<<<",h.TargetConfigName,"|",##class(Ens.DataType.MessageStatus).LogicalToDisplay(h.Status),"|",$EXTRACT($SYSTEM.Status.GetErrorText(h.ErrorStatus),1,110),">>>",! }} }}"""
    out = session(ns, code)
    found = {}
    for row in re.findall(r"<<<(.*?)>>>", out):
        name, st, err = row.split("|", 2)
        if name in targets:
            found[name] = (st, err)
    return found


def settle_statuses(ns, targets, control, seconds=25):
    """The statuses once every target's copy has stopped moving."""
    end = time.time() + seconds
    while True:
        found = statuses(ns, targets, control)
        if (len(found) == len(targets) and all(v[0] not in ("Created", "Queued", "Delivered", "") for v in found.values())) or time.time() > end:
            return found
        time.sleep(1)


def ack_message(code, control, words=""):
    now = time.strftime("%Y%m%d%H%M%S", time.gmtime())
    return [f"MSH|^~\\&|APP|HOSP|OCS|HOSP|{now}||ACK|K{control}|P|2.5.1", f"MSA|{code}|{control}|{words}"]


def ack_levels():
    """What a completed message proves at a stock TCP operation, measured against a listener, and an application NACK on its own feed."""
    step("ORDERS: the plan says what a completed message proves, per operation")
    subprocess.run(["docker", "exec", CTR, "pkill", "-f", "ack_listener.py"], capture_output=True)
    for port in (7231, 7232):
        subprocess.Popen(["docker", "exec", CTR, "python3", "/tmp/onb_site/ack_listener.py", str(port), f"/tmp/onb_site/ack-{port}.log", "900"])
    time.sleep(1)
    p = plan("ORDERS")
    ops = {o["name"]: o for o in p["operations"]}
    for o in p["operations"]:
        print(json.dumps({k: o.get(k) for k in ("name", "get_reply", "reply_code_actions", "reply_code_actions_from", "alert_on_error", "proves")}))
    stock, off, strict = ops["Measure Stock Out"], ops["Measure Off Out"], ops["Measure Strict Out"]
    check("a stock operation: a reply is awaited, the engine's default codes", stock["get_reply"] is True and stock["reply_code_actions"] == ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C" and stock["reply_code_actions_from"] == "engine_default" and stock["alert_on_error"] is True, stock)
    check("and it says any positive code completes", "any positive code" in stock["proves"], stock["proves"])
    check("GetReply off: it says nothing is awaited", off["get_reply"] is False and "Nothing is awaited" in off["proves"], off)
    check("only AA completes: it says so, the item's own setting", strict["reply_code_actions_from"] == "item" and "only AA completes" in strict["proves"], strict)

    step("The same message to three operations, by the code the listener answers: stock, GetReply off, and CA not completing")
    targets = ("Measure Stock Out", "Measure Off Out", "Measure Strict Out")
    tag = time.strftime("%H%M%S")
    seen, sent = {}, []
    last_alert = max(alert_log("ORDERS") or [0])
    for kind in ("AA", "CA", "AE", "CE", "AR", "CR", "NM", "NR", "CL", "C2", "AA"):
        control = f"{kind}-{tag}{len(seen)}"
        sent.append(control)
        send(7134, hl7("orm", control), "measure")
        row = settle_statuses("ORDERS", targets, control)
        fresh = alert_log("ORDERS", last_alert)
        last_alert = max(list(fresh) + [last_alert])
        raised = sorted(set(a.split(" | ")[0].replace("Measure ", "") for a in fresh.values()))
        seen[kind if kind not in seen else kind + " after C2"] = row
        print(f"  {kind}: " + "; ".join(f"{t.replace('Measure ', '')}={row.get(t, ('none', ''))[0]}" for t in targets) + f"; alerts from {raised}", flush=True)
    done = lambda kind, t: seen[kind].get(t, ("none",))[0]
    check("stock: AA completes", done("AA", targets[0]) == "Completed", seen["AA"])
    check("stock: CA completes the same", done("CA", targets[0]) == "Completed", seen["CA"])
    check("stock: AE and CE do not complete", done("AE", targets[0]) != "Completed" and done("CE", targets[0]) != "Completed", (seen["AE"], seen["CE"]))
    check("stock: AR and CR do not complete", done("AR", targets[0]) != "Completed" and done("CR", targets[0]) != "Completed", (seen["AR"], seen["CR"]))
    check("stock: a reply with no MSA does not complete", done("NM", targets[0]) != "Completed", seen["NM"])
    check("stock: no reply does not complete", done("NR", targets[0]) != "Completed", seen["NR"])
    check("stock: a CA followed by an AE on the connection completes on the first", done("C2", targets[0]) == "Completed", seen["C2"])
    for kind in ("AA", "CA", "AE", "AR", "NM", "NR"):
        check(f"GetReply off: {kind} reads as complete", done(kind, targets[1]) == "Completed", seen[kind])
    c2 = next(k for k in sent if k.startswith("C2-"))
    heard = subprocess.run(["docker", "exec", CTR, "grep", "-c", c2, "/tmp/onb_site/ack-7232.log"], capture_output=True, text=True).stdout.strip()
    print(f"  the listener heard {c2} {heard} times, from three operations")
    check("GetReply off: after the receiver closed the connection, the next message reads as complete and never reached it", done("C2", targets[1]) == "Completed" and heard == "2", (seen["C2"], heard))
    check("GetReply off: the one after that fails on the write", done("AA after C2", targets[1]) == "Error", seen["AA after C2"])
    discarded = session("ORDERS", """Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Text FROM Ens_Util.Log WHERE ConfigName='Measure Stock Out' AND Text LIKE 'Discarding data found%' ORDER BY ID DESC") If rs.%Next() { Write !,"<<<",rs.%Get("Text"),">>>",! }""")
    check("stock: the AE behind the CA is thrown away before the next send, with a warning", f"MSA|AE|{c2}" in discarded.replace("\r", ""), discarded[-300:])
    check("stock: and the message stays complete", done("AA after C2", targets[0]) == "Completed", seen["AA after C2"])
    check("CA set not to complete: AA completes", done("AA", targets[2]) == "Completed", seen["AA"])
    check("CA set not to complete: CA does not", done("CA", targets[2]) != "Completed", seen["CA"])

    step("The apply wires ORDERS, and a message a listener takes and its application later refuses")
    a = apply_("ORDERS")
    check("the apply is ok", a["ok"], a)
    c = session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("ORDERS","shutter-fwd","{PW}")')
    check("the credential is stored", '"ok":true' in c, c[-300:])
    time.sleep(2)

    def order_cases():
        code, r = api("GET", "/cases")
        return [x["caseId"] for x in r.get("items", []) if x.get("sourceNamespace") == "ORDERS" and x.get("receiver") == "Order App Out"]

    control = f"ASYNC{tag}"
    print(send(7131, hl7("orm", control), "async"))
    row = settle_statuses("ORDERS", ("Order App Out",), control)
    check("the listener's commit ACK completes the message", row.get("Order App Out", ("",))[0] == "Completed", row)
    time.sleep(6)
    check("and Shutter has no case: no ACK has come, so nothing here is raised", order_cases() == [], order_cases())
    count = lambda: int(re.findall(r"<<<(\d+)>>>", session("ORDERS", """Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS N FROM Ens.MessageHeader WHERE TargetConfigName='App ACK Match' AND MessageBodyClassName='EnsLib.HL7.Message'") Do rs.%Next() Write !,"<<<",rs.%Get("N"),">>>",!"""))[-1])
    n0 = count()
    print("stock feed answers:", send(7133, ack_message("AE", control, "Not processed"), "stockfeed", 3))
    time.sleep(5)
    check("a stock service on the feed drops the AE: IgnoreInboundAck is on by default", count() == n0 and order_cases() == [], (count(), n0, order_cases()))
    print("feed answers:", send(7132, ack_message("AA", control), "feedaa", 1))
    time.sleep(5)
    check("an AA on the feed reaches the process and does nothing", count() == n0 + 1 and order_cases() == [], (count(), order_cases()))
    print("feed answers:", send(7132, ack_message("CA", control), "feedca", 1))
    time.sleep(4)
    check("a CA on the feed does nothing", order_cases() == [], order_cases())
    print("feed answers:", send(7132, ack_message("AE", control, "Patient not known to the application"), "feedae", 1))
    hit = wait_case(lambda x: x.get("sourceNamespace") == "ORDERS" and x.get("receiver") == "Order App Out", 30)
    check("an AE on the feed opens a case on the receiver", bool(hit), order_cases())
    if hit:
        cid = hit[0]["caseId"]
        c = settled(cid)
        print(json.dumps({k: c.get(k) for k in ("caseId", "state", "failureKind", "failureReasonCode", "sourceNamespace", "sourceRoute", "originHeaderId", "failureText")})[:900])
        check("it names the service and the original's header", c.get("sourceRoute") == "Orders In" and c.get("originHeaderId"), c)
        origin = value("ORDERS", f'##class(EnsLib.HL7.Message).%OpenId(##class(Ens.MessageHeader).%OpenId("{c.get("originHeaderId")}").MessageBodyId).GetValueAt("1:10")')
        check("and that header's message is the one the AE answered", origin == control, origin)
        words = c.get("failureText") or ""
        check("the text says AE, the control id and the receiver's words", "AE" in words and control in words and "Patient not known" in words, words)
        check("it escalates, with nothing sent", c.get("state") in ("escalated", "blocked"), c.get("state"))
    n = len(order_cases())
    print("feed answers:", send(7132, ack_message("AE", control, "Again"), "feedae2", 1))
    time.sleep(6)
    check("a second AE for that message opens no second case", len(order_cases()) == n, order_cases())
    last = max(alert_log("ORDERS") or [0])
    print("feed answers:", send(7132, ack_message("AR", "NOSUCH" + tag, "Rejected"), "feednone", 1))
    time.sleep(5)
    fresh = alert_log("ORDERS", last)
    check("an AR naming no message sent there opens nothing", len(order_cases()) == n, order_cases())
    check("and raises an alert saying so", any("App ACK Match" in a and "NOSUCH" + tag in a for a in fresh.values()), fresh)
    control = f"ADTAK{tag}"
    print(send(7131, hl7("a01", control), "asyncadt"))
    settle_statuses("ORDERS", ("Order App Out",), control)
    print("feed answers:", send(7132, ack_message("AR", control, "Encounter closed"), "feedadt", 1))
    end = time.time() + 30
    while time.time() < end and len(order_cases()) == n:
        time.sleep(2)
    fresh_ids = [x for x in order_cases()]
    check("an AR for an ADT opens a case too", len(fresh_ids) == n + 1, fresh_ids)
    if len(fresh_ids) == n + 1:
        adt = [settled(x) for x in fresh_ids]
        adt = [x for x in adt if x.get("failureKind") == "rejected" and control in (x.get("failureText") or "")]
        check("of the kind rejected, reason ack_AR, nothing resent to a draft", len(adt) == 1 and adt[0].get("state") in ("escalated", "blocked") and "RECEIVER_UNREADABLE" in gate_codes(adt[0]["caseId"]), [(x.get("failureKind"), x.get("state")) for x in adt])
    # An AE on the connection itself: the operation suspends it and alerts, so the alert intake opens the case; the feed's AE for it adds nothing.
    n = len(order_cases())
    control = f"AE-{tag}"
    print(send(7131, hl7("orm", control), "syncae"))
    row = settle_statuses("ORDERS", ("Order App Out",), control)
    check("an AE on the connection suspends the message", row.get("Order App Out", ("",))[0] == "Suspended", row)
    end = time.time() + 30
    while time.time() < end and len(order_cases()) == n:
        time.sleep(2)
    check("and the alert opens a case", len(order_cases()) == n + 1, order_cases())
    time.sleep(3)
    print("feed answers:", send(7132, ack_message("AE", control, "Again on the feed"), "feedsync", 1))
    time.sleep(6)
    check("the same message's AE on the feed opens no second case", len(order_cases()) == n + 1, order_cases())
    subprocess.run(["docker", "exec", CTR, "pkill", "-f", "ack_listener.py"], capture_output=True)


def fan_out():
    """A message routed to two receivers, an inherited retry-forever, a refused forward, a later operation, and a namespace taken off."""
    step("FANOUT: the plan warns of a retry-forever the operation inherits")
    p = plan("FANOUT")
    check("a stock operation with no FailureTimeout set gets the warning", any(w.startswith("Default Timeout Out retries forever") for w in p["warnings"]), p["warnings"])
    check("and one with its own setting does not", not any(w.startswith("Fan One") for w in p["warnings"]), p["warnings"])
    a = apply_("FANOUT")
    check("the apply is ok", a["ok"], a)
    c = session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("FANOUT","shutter-fwd","{PW}")')
    check("the credential is stored", '"ok":true' in c, c[-300:])
    u = session("SHUTTER", 'Set $NAMESPACE="%SYS"\nSet sc=##class(Security.Users).Get("shutter-fwd",.p) Write !,"<<<",$GET(p("PasswordNeverExpires")),">>>",!')
    check("the forwarder's password does not expire", "<<<1>>>" in u, u[-200:])

    step("One order routed to two dead receivers opens a case for each")
    tag = time.strftime("%H%M%S")

    def from_app(app, kind, control, extra=""):
        segs = hl7(kind, control)
        segs[0] = segs[0].replace("|ICE|", f"|{app}|", 1).replace("|PAS|", f"|{app}|", 1)
        if extra:
            segs.append(f"OBX|1|ED|DOC||{extra}")
        return segs

    print(send(7301, from_app("FAN", "orm", "FAN" + tag), "fan1"))
    both = wait_case(lambda x: x.get("sourceNamespace") == "FANOUT" and x.get("receiver") == "Fan One", 45), wait_case(lambda x: x.get("sourceNamespace") == "FANOUT" and x.get("receiver") == "Fan Two", 45)
    check("a case for Fan One and one for Fan Two", bool(both[0]) and bool(both[1]) and both[0][0]["caseId"] != both[1][0]["caseId"], both)
    fan_cases = lambda: [x["caseId"] for x in api("GET", "/cases")[1].get("items", []) if x.get("sourceNamespace") == "FANOUT"]
    n = len(fan_cases())
    time.sleep(8)
    check("and no more than those", len(fan_cases()) == n and n == 2, fan_cases())
    print(send(7301, from_app("PAS", "a01", "ONE" + tag), "fan2"))
    end = time.time() + 40
    while time.time() < end and len(fan_cases()) == n:
        time.sleep(2)
    time.sleep(6)
    check("a message to one receiver opens one", len(fan_cases()) == n + 1, fan_cases())

    step("An operation added after the apply is said, and a second apply takes it in")
    session("FANOUT", """Set p=##class(Ens.Config.Production).%OpenId("OnbFan.Production")
Set i=##class(Ens.Config.Item).%New(),i.Name="Late Out",i.ClassName="EnsLib.HL7.Operation.TCPOperation",i.Enabled=1,i.PoolSize=1
Set a=##class(Ens.Config.Setting).%New(),a.Name="IPAddress",a.Target="Adapter",a.Value="127.0.0.1" Do i.Settings.Insert(a)
Set a=##class(Ens.Config.Setting).%New(),a.Name="Port",a.Target="Adapter",a.Value="7314" Do i.Settings.Insert(a)
Set a=##class(Ens.Config.Setting).%New(),a.Name="AlertOnError",a.Target="Host",a.Value="1" Do i.Settings.Insert(a)
Set a=##class(Ens.Config.Setting).%New(),a.Name="FailureTimeout",a.Target="Host",a.Value="0" Do i.Settings.Insert(a)
Do p.Items.Insert(i) Set sc=p.%Save() Set sc=p.SaveToClass()
Set sc=##class(Ens.Director).UpdateProduction(30,0)""")
    w = watched("FANOUT")
    check("the Doctor lists it, as a problem", "Late Out" in (w.get("operations_unwatched") or []) and any("Late Out" in x for x in w["problems"]), w)
    a = apply_("FANOUT")
    check("the apply takes it in", a["ok"] and any("Late Out" in x for x in a["changed"]), a)
    w = watched("FANOUT")
    check("and the Doctor is clear of it", not w.get("operations_unwatched") and not any("Late Out" in x for x in w["problems"]), w)

    step("A forward Shutter refuses: an alert to the site, and the Doctor remembers it past the next good one")
    last = max(alert_log("FANOUT") or [0])
    n = len(fan_cases())
    print(send(7301, from_app("FAN", "orm", "BIG" + tag, "A" * (3 * 1024 * 1024)), "big"))
    time.sleep(20)
    fresh = alert_log("FANOUT", last)
    check("a 3 MB order opens no case", len(fan_cases()) == n, fan_cases())
    check("the site's consumer hears that Shutter did not take it", any(a.startswith("Shutter Forwarder | Shutter did not take a failed delivery") for a in fresh.values()), fresh)
    w = watched("FANOUT")
    print(json.dumps({k: w.get(k) for k in ("last_forward_error", "refused_72h", "last_refused", "problems", "ok")})[:700])
    check("the Doctor reports the refusal", w.get("last_forward_error") and int(w.get("refused_72h") or 0) >= 1 and not w["ok"], w)
    refused = int(w["refused_72h"])
    print(send(7301, from_app("PAS", "orm", "GOOD" + tag), "good"))
    time.sleep(15)
    w = watched("FANOUT")
    print(json.dumps({k: w.get(k) for k in ("last_forward_error", "refused_72h", "problems", "ok")})[:700])
    check("the next good forward clears the last error, and the count stays", not w.get("last_forward_error") and int(w.get("refused_72h") or 0) == refused and not w["ok"], w)
    settled_alerts = len(alert_log("FANOUT"))
    time.sleep(8)
    check("the refusal's alert does not loop", len(alert_log("FANOUT")) == settled_alerts, settled_alerts)

    step("The site's own consumer fails, with AlertOnError on: its alert is not passed back to it")
    heard = lambda: int(value("FANOUT", "$GET(^OnbSite.Alerts)+0"))
    session("FANOUT", "Set ^OnbSite.AlertFail=1")
    before = heard()
    print(send(7301, from_app("PAS", "orm", "LOOP" + tag), "loop"))
    time.sleep(15)
    after = heard()
    session("FANOUT", "Kill ^OnbSite.AlertFail")
    print(f"  the consumer was called {after - before} times in 15 s")
    check("it hears the operation's failure", after > before, (before, after))
    check("and not its own failure, turn after turn", after - before < 50, (before, after))

    step("Taken off: the Doctor says removed, and has no problems")
    r = remove("FANOUT")
    check("the removal is ok", r["ok"], r)
    r = remove("FANOUT", {"unmap": True})
    check("unmap says how many messages were left", r["ok"] and any("message" in x for x in r["kept"] + r["removed"]), r)
    w = watched("FANOUT")
    print(json.dumps({k: w.get(k) for k in ("removed", "onboarded", "problems", "ok")}) if w else "not listed")
    check("the Doctor reads removed, ok, no problems", w and w.get("removed") and w["problems"] == [] and w["ok"], w)


def finish():
    print(f"\n{passed} checks passed, {len(failed)} failed")
    for f in failed:
        print("  FAILED:", f)
    if not args.keep:
        subprocess.run(["docker", "rm", "-f", CTR], capture_output=True)
    sys.exit(1 if failed else 0)


# ---- the stock instance ----
if not args.reuse:
    step("A stock instance, with Shutter installed without the demo, in its own namespace")
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
    check("Setup.cls alone reaches CreateNamespace", "ok|" in out, out[-500:])
    start = time.time()
    out = session("SHUTTER", f'Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck")\nSet sc=##class(%IPM.Main).Shell("load {TARGET} -Ddemo=0") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 500)
    check(f"the load finishes in {int(time.time() - start)} s", "RESULT: ok" in out, out[-800:])

    step("The hospital's namespaces, already running their own productions")
    for ns in ("PATHOLOGY", "DOCUMENTS", "PAS", "BEDS", "ORDERS", "FANOUT"):
        session("SHUTTER", f'Write ##class(Shutter.Setup).CreateNamespace("{ns}")')
    subprocess.run(["docker", "cp", SITE + "/.", f"{CTR}:/tmp/onb_site"], check=True)
    subprocess.run(["docker", "exec", "-u", "root", CTR, "chown", "-R", "irisowner:irisowner", "/tmp/onb_site"], check=True)
    for ns, files, schema, prod in (
        ("PATHOLOGY", ["OnbSite.AlertLog", "OnbPath.Rule", "OnbPath.Production"], "TRUSTLAB-pathology", "OnbPath.Production"),
        ("DOCUMENTS", ["OnbDocs.Rule", "OnbDocs.Production"], "TRUSTLAB-documents", "OnbDocs.Production"),
        ("PAS", ["OnbPas.Production"], None, "OnbPas.Production"),
        ("ORDERS", ["OnbSite.AlertLog", "OnbAck.AckProcess", "OnbAck.Production"], None, "OnbAck.Production"),
        ("FANOUT", ["OnbSite.AlertLog", "OnbFan.Rule", "OnbFan.Production"], None, "OnbFan.Production"),
    ):
        lines = []
        if schema:
            lines.append(f'Set sc=##class(EnsLib.HL7.SchemaXML).Import("/tmp/onb_site/{schema}.xml") Write !,"[s] ",sc,!')
        for f in files:
            lines.append(f'Set sc=$SYSTEM.OBJ.Load("/tmp/onb_site/{f}.cls","ck-d") Write !,"[c] ",sc,!')
        lines.append(f'Set sc=##class(Ens.Director).StartProduction("{prod}") Write !,"[start] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
        out = session(ns, "\n".join(lines))
        check(f"{ns} runs {prod}", "[start] ok" in out, out[-600:])
    step("The people, as INSTALL says, and one sign-in from here on")
    session("SHUTTER", f'''Set $NAMESPACE="%SYS"
Set a=##class(Security.Users).Create("appr1","Shutter_Approver","{PW}","An approver","SHUTTER","","",0,1)
Set $NAMESPACE="SHUTTER"
Set d=##class(EnsLib.Workflow.UserDefinition).CreateUser("appr1","An approver")
Set e=##class(EnsLib.Workflow.RoleDefinition).AddUserToRole("Shutter Approvers","appr1",1,"Approver")''')

code, _ = api("POST", "/session", {"username": "appr1", "password": PW})
check("the approver signs in", code in (200, 201), code)
if args.only == "ack":
    ack_levels()
    finish()
if args.only == "fanout":
    fan_out()
    finish()

# ---- the plan ----
step("The plan for PATHOLOGY changes nothing and says what would change")
before_class = value("PATHOLOGY", '$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHA1Hash(##class(%Dictionary.XDataDefinition).%OpenId("OnbPath.Production||ProductionDefinition").Data.Read(100000)))')
p = plan("PATHOLOGY")
print(json.dumps({k: p.get(k) for k in ("production", "production_state", "actions", "todo", "warnings", "error")}, indent=1)[:3500])
check("it names the running production", p["production"] == "OnbPath.Production" and p["production_state"] == "running", p)
check("it lists the HL7 services and operations", sorted(s["name"] for s in p["services"]) == ["LIMS Results In", "OrderComms In"] and sorted(o["name"] for o in p["operations"]) == ["LIMS Out", "Results Out"], p)
sch = {s["category"]: s for s in p["schemas"]}
check("it sees the custom schema and what Shutter lacks", sch["TRUSTLAB"]["in_namespace"] and not sch["TRUSTLAB"]["in_shutter"] and sch["TRUSTLAB"]["action"] == "import" and sch["2.5.1"]["standard"], sch)
dos = [a["do"] for a in p["actions"]]
check("it would map, import, add, rename, add and draft", dos == ["map_package", "map_package", "import_schema", "add_forwarder", "rename_alert", "add_alert_intake", "draft_receiver", "draft_receiver"], dos)
check("it asks for the credential", any("OnboardCredential" in t for t in p["todo"]), p["todo"])
check("it warns of the retry-forever receiver", any("retries forever" in t for t in p["warnings"]), p["warnings"])
via_sql = session("SHUTTER", """Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT Shutter.Setup_OnboardPlan('PATHOLOGY') AS r") Do rs.%Next() Write !,"<<<",rs.%Get("r"),">>>",!""")
sql_json = json.loads(re.findall(r"<<<(.*?)>>>", via_sql, re.S)[-1])
check("the SQL form answers the same plan", sql_json["production"] == p["production"] and len(sql_json["actions"]) == len(p["actions"]), via_sql[-300:])
check("nothing changed: the class", value("PATHOLOGY", '$SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHA1Hash(##class(%Dictionary.XDataDefinition).%OpenId("OnbPath.Production||ProductionDefinition").Data.Read(100000)))') == before_class)
check("nothing changed: no mapping", value("PATHOLOGY", '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Intake.Forwarder")') == "0")
check("nothing changed: no schema in Shutter", value("SHUTTER", '##class(Shutter.Util.Schemas).Known("TRUSTLAB")') == "0")
check("nothing changed: no receiver in the profile", value("SHUTTER", '$ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver("LIMS Out"))') == "0")

step("Options that do not parse, and a receivers name that matches no item")
for bad in ('{"production":"NoSuch"', "{'production':'NoSuch'}", "plain words"):
    answers = [raw(proc, "PATHOLOGY", bad) for proc in ("OnboardPlan", "OnboardApply", "OnboardRemove")]
    check(f"the plan, the apply and the removal refuse: {bad}", all(a.get("ok") is False and "not a JSON object" in a["error"] for a in answers), answers)
check("and nothing changed", value("PATHOLOGY", '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Intake.Forwarder")') == "0" and value("SHUTTER", '$DATA(^Shutter.Config("onboard","PATHOLOGY"))') == "0")
p = plan("PATHOLOGY", {"receivers": "LIMS Oot"})
check("a name that matches no item is said, and no intake with an empty list is added", p["operations"] == [] and any("LIMS Oot" in w for w in p["warnings"]) and not any(a["do"] in ("add_alert_intake", "rename_alert") for a in p["actions"]), p)
p = plan("PATHOLOGY", {"receivers": "LIMS Out,Nosuch Out"})
check("one that matches and one that does not: the second is said, the first is wired", any("Nosuch Out" in w for w in p["warnings"]) and [a["receivers"] for a in p["actions"] if a["do"] == "add_alert_intake"] == ["LIMS Out"], p)
p = plan("PATHOLOGY", {"shutter_host": "shutter.example"})
check("a remote Shutter with no SSL configuration: it says the sign-in goes in clear", any("in clear" in w for w in p["warnings"]), p["warnings"])
p = plan("PATHOLOGY", {"shutter_host": "shutter.example", "ssl_config": "Any"})
check("and not with one", not any("in clear" in w for w in p["warnings"]), p["warnings"])

# ---- the apply ----
step("The apply wires PATHOLOGY without stopping it")
jobs_before = jobs("PATHOLOGY")
a = apply_("PATHOLOGY")
print(json.dumps(a, indent=1)[:2500])
check("the apply is ok", a["ok"], a)
check("it says what it changed", len(a["changed"]) >= 7, a["changed"])
jobs_after = jobs("PATHOLOGY")
check("an item it did not touch kept its job: the production was not stopped", jobs_before.get("OrderComms In") and jobs_before.get("OrderComms In") == jobs_after.get("OrderComms In"), (jobs_before, jobs_after))
check("the forwarder and the alert intake run", "Shutter Forwarder" in jobs_after and "Ens.Alert" in jobs_after and "Site Alerts" in jobs_after, jobs_after)
state = value("PATHOLOGY", '##class(Ens.Director).GetProductionStatus(.n,.s)_"|"_n_"|"_s')
check("the production runs", state.endswith("OnbPath.Production|1"), state)
pass_to = obj("SHUTTER", '##class(Shutter.Util.Onboard).Read("PATHOLOGY").alert.%ToJSON()')
check("the site's Ens.Alert is its PassTo", pass_to["is_shutter"] and pass_to["pass_to"] == "Site Alerts" and pass_to["receivers"] == "LIMS Out,Results Out", pass_to)
drafted = obj("SHUTTER", '##class(Shutter.Store.SiteProfile).Receiver("LIMS Out").%ToJSON()')
check("the receiver is drafted with no API and no features", drafted["draft"] and "api" not in drafted and not any(drafted["features"].values()) and drafted["namespace"] == "PATHOLOGY", drafted)
again = apply_("PATHOLOGY")
check("a second apply has nothing to do", again["ok"] and again["changed"] == [] and "Nothing to do" in again["unchanged"], again)
check("and no second forwarder", value("SHUTTER", '##class(Shutter.Util.Onboard).Plan("PATHOLOGY").actions.%Size()') == "0")

# ---- the credential and the test ----
step("The credential, and a test failure a person can send")
t0 = test_forward("PATHOLOGY")
check("the test says the credential is missing, by name", not t0["ok"] and "OnboardCredential" in t0["error"], t0)
listener = subprocess.Popen(["docker", "exec", CTR, "python3", "/tmp/onb_site/listener.py", "7202", "/tmp/onb_site/results-out.log", "1500"])
time.sleep(1)
c = session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("PATHOLOGY","shutter-fwd","{PW}")')
check("the credential is stored; the password is not printed", '"ok":true' in c and "user_created" in c and PW not in c.replace(f'"{PW}"', ""), c[-400:])
t1 = test_forward("PATHOLOGY")
print(json.dumps(t1))
check("the test opens a case", t1["ok"] and t1["http_status"] == "202" or t1["http_status"] == 202, t1)
case = settled(t1["case"])
print(json.dumps({k: case.get(k) for k in ("state", "receiver", "failureKind", "sourceNamespace", "sourceRoute", "headline", "failureText")})[:900])
check("it is clearly marked", "ONBOARDING TEST" in (case.get("failureText") or "") and case.get("receiver") == "Onboarding test" and case.get("sourceNamespace") == "PATHOLOGY", case)
check("it escalates with nothing to send", case.get("state") in ("escalated", "blocked"), case.get("state"))
_, attempts = api("GET", f"/cases/{t1['case']}/attempts")
check("no attempt to any receiver", (attempts.get("items") if isinstance(attempts, dict) else attempts) in ([], None), attempts)
_, runs = api("GET", f"/cases/{t1['case']}/runs")
check("no model ran", runs == [] or not [r for r in (runs.get("items", []) if isinstance(runs, dict) else runs) if r.get("mode") == "live"], runs)
time.sleep(2)
hits = subprocess.run(["docker", "exec", CTR, "sh", "-c", "cat /tmp/onb_site/results-out.log 2>/dev/null | wc -l"], capture_output=True, text=True).stdout.strip()
check("the receiver heard nothing", hits == "0", hits)
session("SHUTTER", f'Set $NAMESPACE="%SYS"\nSet x("Password")="Other-2026x" Set sc=##class(Security.Users).Modify("shutter-fwd",.x)')
t2 = test_forward("PATHOLOGY")
print(json.dumps(t2)[:500])
check("a wrong password says what to check", not t2["ok"] and str(t2["http_status"]) in ("401", "404") and "password" in t2["advice"].lower() or "sign" in t2["advice"].lower(), t2)
session("SHUTTER", f'Set $NAMESPACE="%SYS"\nSet x("Password")="{PW}" Set sc=##class(Security.Users).Modify("shutter-fwd",.x)')

# ---- real failures ----
step("Real failures through the running production, with the receiver down")
subprocess.run(["docker", "exec", CTR, "pkill", "-f", "listener.py"], capture_output=True)
listener.wait(timeout=10)
tag = time.strftime("%H%M%S")
alerts0 = value("PATHOLOGY", '$GET(^OnbSite.Alerts)+0')
print(send(7101, hl7("orm", "ORM" + tag), "orm"))
hit = wait_case(lambda c: c.get("sourceNamespace") == "PATHOLOGY" and c.get("receiver") == "LIMS Out")
check("an order to a dead LIMS opens a case in Shutter", bool(hit), "no case")
if hit:
    c = settled(hit[0]["caseId"])
    print(json.dumps({k: c.get(k) for k in ("caseId", "state", "failureKind", "sourceProduction", "sourceRoute", "originHeaderId", "failureText")})[:800])
    check("with where it came from", c.get("sourceProduction") == "OnbPath.Production" and c.get("sourceRoute") and c.get("originHeaderId"), c)
    check("a TCP connect timeout is no uncertain outcome: nothing was sent", "uncertain" not in (c.get("failureKind") or ""), c.get("failureKind"))
    check("it escalates: an order has no recovery", c.get("state") == "escalated", c.get("state"))
    check("and says so in words: no talk of a bad ADT trigger", "not ADT" in (c.get("failureText") or "") and "trigger" not in (c.get("failureText") or ""), c.get("failureText"))
    check("the headline blames no mapping", "resends only ADT" in (c.get("headline") or "") and "map the message" not in (c.get("headline") or ""), c.get("headline"))
    plan_view = api("GET", "/cases/" + c["caseId"] + "/plan")[1]
    check("the plan says the message may be sound and to check before re-entering it", "may be sound" in (plan_view.get("plan", {}).get("why") or "") and "re-enters" in (plan_view.get("plan", {}).get("why") or ""), plan_view.get("plan"))
    code_d, draft = api("POST", "/cases/" + c["caseId"] + "/escalations", {})
    body = json.dumps(draft)
    check("the draft asks to check before re-entering, not to correct it by hand", code_d in (200, 201) and "re-enters it" in body and "correct them by hand" not in body, (code_d, body[:600]))
time.sleep(3)
check("the site's own consumer still got the alert", int(value("PATHOLOGY", '$GET(^OnbSite.Alerts)+0')) > int(alerts0), value("PATHOLOGY", '$GET(^OnbSite.Alerts)+0'))
print(send(7102, hl7("oru", "ORU" + tag, "ZLB|AN-07|B3"), "oru"))
hit = wait_case(lambda c: c.get("sourceNamespace") == "PATHOLOGY" and c.get("receiver") == "Results Out")
check("a result with a Z segment opens a case", bool(hit))
if hit:
    settled(hit[0]["caseId"])
    _, snap = api("GET", f"/cases/{hit[0]['caseId']}/snapshot")
    v = (snap.get("summary") or snap).get("validation") or {}
    check("it validates under PATHOLOGY's schema, imported before it came", v.get("parsed") is True and v.get("schema_category") == "TRUSTLAB", v)

# ---- a second namespace, with the same names ----
step("DOCUMENTS: an item and a schema category named as PATHOLOGY's are")
p = plan("DOCUMENTS", {"alert_on_error": True})
print(json.dumps({k: p.get(k) for k in ("receiver_prefix", "actions", "todo", "warnings")}, indent=1)[:2500])
check("it keeps the receiver apart by a prefix", p["receiver_prefix"] == "DOCUMENTS" and p["operations"][0]["reported_as"] == "DOCUMENTS Results Out", p["operations"])
sch = {s["category"]: s for s in p["schemas"]}
check("it imports the same-named schema under an alias", sch["TRUSTLAB"]["action"] == "import_as" and sch["TRUSTLAB"]["shutter_name"] == "DOCUMENTS_TRUSTLAB", sch)
print_path = value("SHUTTER", '##class(Shutter.Util.Schemas).Fingerprint("","TRUSTLAB")')
a = apply_("DOCUMENTS", {"alert_on_error": True})
print(json.dumps(a["changed"], indent=1)[:1500])
check("the apply is ok", a["ok"], a)
check("PATHOLOGY's schema in Shutter is untouched", value("SHUTTER", '##class(Shutter.Util.Schemas).Fingerprint("","TRUSTLAB")') == print_path)
check("both are loaded", value("SHUTTER", '##class(Shutter.Util.Schemas).Known("DOCUMENTS_TRUSTLAB")') == "1")
check("a second apply has nothing to do", apply_("DOCUMENTS", {"alert_on_error": True})["changed"] == [])
again = plan("PATHOLOGY")
check("the first namespace keeps its names when the second comes on", again["receiver_prefix"] == "" and {o["reported_as"] for o in again["operations"]} == {"LIMS Out", "Results Out"}, again["operations"])
check("and its next apply renames and drafts nothing", apply_("PATHOLOGY")["changed"] == [], again["actions"])
c = session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("DOCUMENTS","shutter-fwd","{PW}")')
check("the same user serves a second namespace", '"ok":true' in c and '"user_created":false' in c, c[-300:])
prompted = session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("DOCUMENTS")\n{PW}')
check("with no password it asks, and takes the answer from the terminal", '"ok":true' in prompted and "Password for shutter-fwd" in prompted, prompted[-400:])
wrong = session("SHUTTER", 'Do ##class(Shutter.Setup).OnboardCredential("DOCUMENTS","shutter-fwd","Wrong-2026x")')
check("a wrong password for an existing user stores nothing", '"ok":false' in wrong and "Wrong-2026x" not in wrong.replace('"Wrong-2026x")', ""), wrong[-300:])
t3 = test_forward("DOCUMENTS")
check("its test opens a case", t3["ok"], t3)
print(send(7111, hl7("oru", "DOC" + tag, "ZDC|LETTER"), "doc"))
hit = wait_case(lambda c: c.get("sourceNamespace") == "DOCUMENTS" and c.get("receiver") == "DOCUMENTS Results Out")
check("a failure opens a case on the prefixed receiver", bool(hit))
if hit:
    settled(hit[0]["caseId"])
    _, snap = api("GET", f"/cases/{hit[0]['caseId']}/snapshot")
    v = (snap.get("summary") or snap).get("validation") or {}
    check("it validates under its own schema's alias", v.get("parsed") is True and v.get("schema_category") == "DOCUMENTS_TRUSTLAB", v)
# The same operation from the two namespaces: their cases stay apart.
same = "\r".join(hl7("a08", "x")) + "\r"
one = post_intake({"source": {"namespace": "PATHOLOGY", "production": "OnbPath.Production", "route": "x", "header_id": "1"}, "receiver": "Results Out", "failure": {"kind": "delivery_failed", "text": "t", "outcome": "error"}, "message": same})
two = post_intake({"source": {"namespace": "DOCUMENTS", "production": "OnbDocs.Production", "route": "x", "header_id": "2"}, "receiver": "DOCUMENTS Results Out", "failure": {"kind": "delivery_failed", "text": "t", "outcome": "error"}, "message": same})
check("one operation from two namespaces is two cases", one[0] == 202 and two[0] == 202 and one[1]["caseId"] != two[1]["caseId"] and two[1]["opened"], (one, two))
for cid in (one[1].get("caseId"), two[1].get("caseId")):
    c = settled(cid)
    g = gate_codes(cid)
    check(f"{cid}: a draft receiver blocks any write", c.get("state") in ("escalated", "blocked") and "RECEIVER_UNREADABLE" in g, (c.get("state"), g[:400]))

# ---- the Doctor ----
step("The Doctor reports each watched namespace")
d = doctor()
print(json.dumps(d.get("watched_namespaces"), indent=0)[:1600])
w = {x["namespace"]: x for x in d["watched_namespaces"]}
check("both are listed and well", w["PATHOLOGY"]["ok"] and w["DOCUMENTS"]["ok"], w)
check("each with its forwarder, last forward and last case", w["PATHOLOGY"]["forwarder"] and w["PATHOLOGY"]["last_forward"] and w["PATHOLOGY"]["last_case"], w["PATHOLOGY"])
check("no schema is missing", d["hl7_schemas"]["missing"] == [], d["hl7_schemas"]["missing"])
check("the credentials were tried", any(c.get("namespace") == "PATHOLOGY" and c.get("ok") for c in d.get("credentials", [])), d.get("credentials"))

# ---- a schema that comes late ----
step("A schema that comes late: unknown first, then read under it once it is imported")
session("PATHOLOGY", 'Set sc=##class(EnsLib.HL7.SchemaXML).Import("/tmp/onb_site/LATELAB.xml")')
late = "\r".join(hl7("oru", "LAT" + tag, "ZLB|AN-07|B3")) + "\r"
r = post_intake({"source": {"namespace": "PATHOLOGY", "production": "OnbPath.Production", "route": "LIMS Results In", "header_id": "3"}, "receiver": "Results Out", "failure": {"kind": "delivery_failed", "text": "t", "outcome": "error"}, "message": late, "schema_category": "LATELAB"})
check("the forward is taken", r[0] == 202, r)
cid = r[1]["caseId"]
c = settled(cid)
_, snap = api("GET", f"/cases/{cid}/snapshot")
v = (snap.get("summary") or snap).get("validation") or {}
print(json.dumps(v)[:500])
check("the evidence says unknown schema, naming it", v.get("schema_known") is False and v.get("schema_category") == "LATELAB", v)
check("the gate blocks SCHEMA_UNKNOWN", "SCHEMA_UNKNOWN" in gate_codes(cid), gate_codes(cid)[:400])
check("the Doctor lists it as missing", "LATELAB" in doctor()["hl7_schemas"]["missing"], doctor()["hl7_schemas"]["missing"])
imp = status("SHUTTER", '##class(Shutter.Util.Schemas).ImportFrom("PATHOLOGY","LATELAB")')
check("it imports from the namespace", imp == "ok", imp)
check("the Doctor no longer lists it", "LATELAB" not in doctor()["hl7_schemas"]["missing"], doctor()["hl7_schemas"]["missing"])
code, _ = api("POST", f"/cases/{cid}/reinvestigate", {})
check("the case reinvestigates", code in (200, 202), code)
time.sleep(6)
settled(cid)
_, snap = api("GET", f"/cases/{cid}/snapshot")
v = (snap.get("summary") or snap).get("validation") or {}
print(json.dumps(v)[:400])
check("the fresh evidence reads it under that schema", v.get("schema_known") is True and v.get("parsed") is True and v.get("doc_type", "").startswith("LATELAB:"), v)

# ---- a receiver a person fills in ----
step("PAS: a draft blocks; a person fills in the API; a recovery reaches the receiver")
a = apply_("PAS")
check("the apply is ok", a["ok"], a)
session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("PAS","shutter-fwd","{PW}")')
out = session("BEDS", f'''Set sc=$SYSTEM.OBJ.LoadDir("{HOME}/pkg/src/Downstream/","ck-d",,1) Write !,"[beds] ",sc,!
Set sc=##class(Downstream.Installer).Install(0) Write !,"[beds] ",sc,!
Set $NAMESPACE="%SYS"
Set sc=##class(Security.Roles).Create("Beds_Client","The bed system's API client","Downstream_API:U,%DB_BEDS:RW") Write !,"[beds] ",sc,!
Set sc=##class(Security.Users).Create("beds-client","Beds_Client","{PW}","The bed system's API client","BEDS","","",0,1) Write !,"[beds] ",sc,!
Kill a Set a("NameSpace")="BEDS",a("Description")="Bed management API",a("Enabled")=1,a("AutheEnabled")=32,a("DispatchClass")="Downstream.API",a("Resource")="Downstream_API",a("UseCookies")=2,a("CookiePath")="/beds/api/"
Set sc=##class(Security.Applications).Create("/beds/api",.a) Write !,"[beds] ",sc,!''')
check("the bed system's API exists", "[beds] 1" in out and "ERROR" not in out, out[-600:])
print(send(7121, hl7("a01", "A0a" + tag), "a01a"))
hit = wait_case(lambda c: c.get("sourceNamespace") == "PAS" and c.get("receiver") == "Bed Mgmt Out")
check("an A01 to the draft receiver opens a case", bool(hit))
if hit:
    c = settled(hit[0]["caseId"])
    check("it escalates: nothing was resent", c.get("state") in ("escalated", "blocked") and "RECEIVER_UNREADABLE" in gate_codes(c["caseId"]), (c.get("state"), gate_codes(c["caseId"])[:400]))
code, prof = api("GET", "/site-profile")
body = prof["profile"]
for r in body["receivers"]:
    if r["name"] == "Bed Mgmt Out":
        r.pop("draft", None)
        r["tier"] = 2
        r["system"] = "the bed management system"
        r["category"] = "current_state"
        r["api"] = {"base": "/beds/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}", "capabilities": "/capabilities", "operations": "/operations"}
        r["features"] = {"conditional_writes": True, "receipts": True, "history": True, "dry_run": True}
body["policy"]["2"]["single"] = "approval"
body["expectedVersion"] = prof["version"]
code, saved = api("PUT", "/site-profile", body)
check("the approver saves the filled-in receiver", code == 200, saved)
d = doctor()
check("the Doctor says its connector item is missing", d["receivers_without_item"] == ["Bed Mgmt Out"], d["receivers_without_item"])
session("SHUTTER", f'Do ##class(Ens.Config.Credentials).SetCredential("DownstreamAPI","beds-client","{PW}",1)')
item = obj("SHUTTER", '##class(Shutter.Setup).OnboardReceiverItem("Bed Mgmt Out","127.0.0.1","52773","DownstreamAPI")')
check("the connector item is added", item["ok"] and item["added"] == 1 and item["credential"], item)
check("and the Doctor is content", doctor()["receivers_without_item"] == [])
time.sleep(2)
print(send(7121, hl7("a01", "A0b" + tag), "a01b"))
hit = wait_case(lambda c: c.get("sourceNamespace") == "PAS" and c.get("receiver") == "Bed Mgmt Out" and "A0b" not in "" and c.get("state") == "waiting_approval" or (c.get("sourceNamespace") == "PAS" and c.get("state") in ("awaiting_approval", "waiting")), 60)
check("the next failure waits for a person's approval", bool(hit))
if hit:
    cid = hit[0]["caseId"]
    _, c = api("GET", "/cases/" + cid)
    _, pl = api("GET", f"/cases/{cid}/plan")
    print(json.dumps({"state": c.get("state"), "plan": pl.get("plan", {}).get("summary")})[:400])
    code, ans = api("POST", f"/cases/{cid}/approvals", {"decision": "approve", "planDigest": pl["plan"]["digest"], "expectedVersion": c.get("version", 0)})
    check("the approver approves", code in (200, 202), (code, ans))
    end = time.time() + 60
    while time.time() < end:
        _, c = api("GET", "/cases/" + cid)
        if c.get("state") in ("resolved", "failed", "escalated", "blocked"):
            break
        time.sleep(2)
    print(json.dumps({k: c.get(k) for k in ("state", "headline")})[:400])
    check("it resolves, verified at the receiver", c.get("state") == "resolved", c.get("state"))
    enc = api("GET", "/cases/" + cid)[1].get("encounterId")
    check("the case names the encounter", enc == f"ENC-A0b{tag}", enc)
    import base64
    req = urllib.request.Request(f"http://127.0.0.1:{args.port}/beds/api/encounters/{enc}", headers={"Authorization": "Basic " + base64.b64encode(f"beds-client:{PW}".encode()).decode()})
    with urllib.request.urlopen(req, timeout=30) as resp:
        at_receiver = json.loads(resp.read().decode())
    print(json.dumps(at_receiver)[:300])
    check("the bed system holds the admission", at_receiver.get("state") == "admitted" and at_receiver.get("ward") == "WARD-A", at_receiver)

# ---- the guard and the reload ----
step("A load in a live namespace is refused; a reload keeps everything")
out = session("DOCUMENTS", f'Set sc=$SYSTEM.OBJ.Load("{HOME}/pkg/src/Shutter/Setup.cls","ck-d")\nSet sc=##class(Shutter.Setup).InstallStatus("",1) Write !,"[guard] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!\nSet sc=$SYSTEM.OBJ.Delete("Shutter.Setup","-d")')
check("an install in DOCUMENTS refuses, and says why", "[guard] ERROR" in out and "would stop it" in out, out[-500:])
check("and DOCUMENTS still runs", value("DOCUMENTS", '##class(Ens.Director).GetProductionStatus(.n,.s)_n_"|"_s').endswith("OnbDocs.Production|1"))
jobs_before = jobs("PATHOLOGY")
out = session("SHUTTER", f'Set sc=##class(%IPM.Main).Shell("load {TARGET} -Ddemo=0") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 500)
check("the module loads again", "RESULT: ok" in out, out[-500:])
d = doctor()
check("the connector item came back by itself", d["receivers_without_item"] == [] and d["missing_items"] == [], (d["receivers_without_item"], d["missing_items"]))
check("the mapped classes kept PATHOLOGY running", jobs("PATHOLOGY").get("OrderComms In") == jobs_before.get("OrderComms In"))
w = {x["namespace"]: x for x in d["watched_namespaces"]}
check("the Doctor still finds each namespace well", w["PATHOLOGY"]["ok"] and w["DOCUMENTS"]["ok"] and w["PAS"]["ok"], w)

# ---- a message to two receivers, and what a refused forward leaves ----
fan_out()

# ---- what a completed message proves ----
ack_levels()

# ---- taking a namespace off ----
step("Taking the namespaces back off")
jobs_before = jobs("PATHOLOGY")
r = remove("PATHOLOGY")
print(json.dumps(r, indent=1)[:1800])
check("the removal is ok", r["ok"], r)
after = jobs("PATHOLOGY")
check("the items are gone and the production was not stopped", "Shutter Forwarder" not in after and after.get("OrderComms In") == jobs_before.get("OrderComms In") and "Site Alerts" not in after and "Ens.Alert" in after, after)
alert = obj("SHUTTER", '##class(Shutter.Util.Onboard).Read("PATHOLOGY").alert.%ToJSON()')
check("the site's own item has its name back", alert["class"] == "OnbSite.AlertLog", alert)
check("the drafts are gone from the profile", value("SHUTTER", '$ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver("LIMS Out"))') == "0")
check("a mapping stays while Shutter's messages do", any("mapping" in k for k in r["kept"]) and value("PATHOLOGY", '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Intake.Forward")') == "1", r["kept"])
check("the cases stay", wait_case(lambda c: c.get("sourceNamespace") == "PATHOLOGY", 5) != [])
w = watched("PATHOLOGY")
check("the Doctor says it has no forwarder now", w and not w["onboarded"] and not w["forwarder"], w)
def forwarder_user():
    return value("%SYS", '##class(Security.Users).Exists("shutter-fwd")')


r = remove("PATHOLOGY", {"unmap": True, "credential": True})
check("a second run with unmap takes the mappings", r["ok"] and any("mapping" in k for k in r["removed"]), r)
check("the credential goes, after a first removal that kept it", "The credential ShutterIntake in PATHOLOGY" in r["removed"], r)
check("the user stays while another namespace signs in with it", forwarder_user() == "1" and any("The user shutter-fwd" in k and "DOCUMENTS" in k for k in r["kept"]), r["kept"])
check("and that namespace's next test still opens a case", test_forward("DOCUMENTS")["http_status"] == 202)
check("no class left in PATHOLOGY", value("PATHOLOGY", '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Intake.Forwarder")') == "0")
r = remove("DOCUMENTS", {"unmap": True, "credential": True})
check("DOCUMENTS comes off", r["ok"], r)
print(json.dumps(r, indent=1)[:1200])
item = obj("SHUTTER", '##class(Shutter.Util.Onboard).Read("DOCUMENTS").%ToJSON()')
check("its AlertOnError is back", next(i for i in item["items"] if i["name"] == "Results Out")["alert_on_error"] is False and item["state"] == "running", item["items"])
check("PATHOLOGY can be onboarded again", apply_("PATHOLOGY")["ok"])
check("and comes off again", remove("PATHOLOGY", {"unmap": True})["ok"])
check("the user is there until the last of them comes off", forwarder_user() == "1")
for ns in ("PAS", "ORDERS"):
    r = remove(ns, {"unmap": True, "credential": True})
    check(f"{ns} comes off with its credential", r["ok"], r)
print(json.dumps(r, indent=1)[:1200])
check("the last one's removal takes the user", forwarder_user() == "0" and "The user shutter-fwd" in r["removed"], r)
r = remove("FANOUT", {"credential": True})
check("a namespace taken off earlier can still give up its credential", r["ok"] and "The credential ShutterIntake in FANOUT" in r["removed"], r)

finish()
