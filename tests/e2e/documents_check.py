#!/usr/bin/env python3
"""Document-aware exceptions played on a real instance, on stock classes (docs/CONTRACTS.md 11.2, docs/INSTALL.md 9.10).

    python3 tests/e2e/documents_check.py --ctr NAME --port PORT --image IMAGE [--reuse] [--keep] [--only D07,D15]

Starts a stock IRIS for Health image, installs Shutter without the demo in its own namespace, gives the instance a documents
namespace with its own running production and stock TCP operations, onboards it, and plays the fixtures: an MDM failure opens a
case that shows the document's identity, its parent, its patient and the delivery, with no copy of the document, large or small;
the case says what the message store holds for the document's chain, or that the chain's coverage is incomplete; nothing is ever
sent. It needs Docker and no API key: no model is called. Exit status 1 when a check fails.
"""
import argparse
import base64
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
SITE = os.path.join(HERE, "documents_site")
ONB = os.path.join(HERE, "onboard_site")
ROOT = os.path.dirname(os.path.dirname(HERE))
PW = "Documents-2026x"
HOME = "/home/irisowner"
NS = "DOCSITE"

ap = argparse.ArgumentParser()
ap.add_argument("--reuse", action="store_true")
ap.add_argument("--keep", action="store_true")
ap.add_argument("--port", type=int, required=True)
ap.add_argument("--ctr", required=True)
ap.add_argument("--image", required=True)
ap.add_argument("--module", default="")
ap.add_argument("--only", default="")
args = ap.parse_args()
CTR = args.ctr
URL = f"http://127.0.0.1:{args.port}/api/shutter"
ONLY = set(x for x in args.only.split(",") if x)
failed, passed = [], 0
PASTED = {}

CANARIES = {
    "pdf_bytes": "CANARYPDFBYTES",
    "base64_text": "CANARYBASE64TEXT",
    "obx_text": "CANARYOBXTEXT",
    "document_title": "CANARYTITLE",
    "patient_name": "CANARYNAME",
    "receiver_diagnostic": "CANARYDIAG",
    "restricted_metadata": "CANARYRESTRICTED",
}
PDF_B64 = base64.b64encode(b"%PDF-1.4 CANARYPDFBYTES synthetic").decode()


def check(name, ok, detail=""):
    global passed
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {str(detail)[:1400]}"), flush=True)
    if ok:
        passed += 1
    else:
        failed.append(name)


def step(title):
    print(f"\n[{time.strftime('%H:%M:%S')}] {title}", flush=True)


def wanted(code):
    return not ONLY or code in ONLY


def session(ns, code, timeout=400):
    # A community licence's seats run out for a moment after a restart: a refused session did nothing, so it is asked again.
    for _ in range(12):
        r = subprocess.run(["docker", "exec", "-i", CTR, "iris", "session", "IRIS", "-U", ns], input=code + "\nHalt\n", capture_output=True, text=True, timeout=timeout, errors="replace")
        if r.returncode != 133 and "LICENSE LIMIT" not in r.stdout:
            break
        time.sleep(10)
    return r.stdout


def value(ns, expr, timeout=300):
    out = session(ns, f'Set %v = {expr}\nWrite !,"<<<",%v,">>>",!', timeout)
    m = re.findall(r"<<<(.*?)>>>", out, re.S)
    if not m:
        raise RuntimeError(f"no value for {expr} in {ns}: {out[-800:]}")
    return m[-1]


jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
jar2 = http.cookiejar.CookieJar()
opener2 = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar2))


def call(op, method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, method=method, headers={"X-Requested-With": "Shutter", "Content-Type": "application/json"})
    try:
        with op.open(req, timeout=120) as r:
            text, code = r.read().decode(), r.status
    except urllib.error.HTTPError as e:
        text, code = e.read().decode(), e.code
    try:
        return code, json.loads(text)
    except ValueError:
        return code, text


def api(method, path, body=None):
    """As the approver, who may read a restricted document's identity."""
    return call(opener, method, path, body)


def op_api(method, path, body=None):
    """As an operator, who may not."""
    return call(opener2, method, path, body)


def post_intake(body):
    req = urllib.request.Request(URL + "/intake", data=json.dumps(body).encode(), method="POST", headers={"X-Requested-With": "Shutter", "Content-Type": "application/json"})
    req.add_header("Authorization", "Basic " + base64.b64encode(f"shutter-fwd:{PW}".encode()).decode())
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def mdm(trigger, control, doc="DOC-1^DMS", parent="", app="DOWN", mrn="MRN7001", completion="AU", conf="U", avail="AV", obx="OBX|1|TX|DOC^Letter||Synthetic letter text", name="SYNTH^PAT", filename="", no_txa=False):
    now = time.strftime("%Y%m%d%H%M%S", time.gmtime(time.time() - 60))
    segs = [
        f"MSH|^~\\&|DOCSRC|HOSP|{app}|HOSP|{now}||MDM^{trigger}^{'MDM_T02' if trigger in ('T02', 'T04', 'T06', 'T08', 'T10') else 'MDM_T01'}|{control}|P|2.5.1",
        f"EVN|{trigger}|{now}",
        f"PID|1||{mrn}^^^HOSP^MR~9990001001^^^NHS^NH||{name}||19800101|F",
        "PV1|1|O|CLINIC1^^^HOSP||||||||||||||||VISIT-7001",
    ]
    if not no_txa:
        segs.append(f"TXA|1|CN|TX|{now}||||||||{doc}|{parent}|||{filename}|{completion}|{conf}|{avail}")
    if obx and trigger in ("T02", "T04", "T06", "T08", "T10"):
        segs.append(obx)
    return segs


def send(segs, name, wait=25):
    text = "\r".join(segs) + "\r"
    subprocess.run(["docker", "exec", "-i", CTR, "sh", "-c", f"cat > /tmp/doc_site/{name}.hl7"], input=text, text=True, check=True, errors="replace")
    return subprocess.run(["docker", "exec", "-e", f"MLLP_WAIT={wait}", CTR, "python3", "/tmp/doc_site/mllp.py", "7311", f"/tmp/doc_site/{name}.hl7"], capture_output=True, text=True, timeout=240).stdout.strip()


def case_of(control, seconds=75, receiver=None):
    """The case whose source message id is the control id, once its workflow has stopped moving."""
    end = time.time() + seconds
    found = None
    while time.time() < end:
        code, r = api("GET", "/cases?limit=200")
        if code == 200:
            for c in r.get("items", []):
                if c.get("sourceMessageId") == control and (receiver is None or c.get("receiver") == receiver):
                    found = c
                    break
        if found:
            _, full = api("GET", "/cases/" + found["caseId"])
            if full.get("state") in ("escalated", "blocked", "resolved", "failed"):
                return full
        time.sleep(2)
    return found


def reasons(c):
    return [r["code"] for r in (c or {}).get("document", {}).get("reasons", [])]


def says(c):
    return " ".join((c or {}).get("document", {}).get("chain", {}).get("says", []))


def heard(port):
    r = subprocess.run(["docker", "exec", CTR, "sh", "-c", f"cat /tmp/doc_site/heard-{port}.log 2>/dev/null"], capture_output=True, text=True)
    return r.stdout.split()


def session_count():
    out = session("SHUTTER", """Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n FROM EnsLib_HL7.Message") Do rs.%Next() Write !,"<<<",rs.%Get("n"),">>>",!""")
    return re.findall(r"<<<(.*?)>>>", out)[-1]


def external_rows():
    out = session("SHUTTER", """Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) AS n FROM Shutter_Msg.ExternalIntake") Do rs.%Next() Write !,"<<<",rs.%Get("n"),">>>",!""")
    return re.findall(r"<<<(.*?)>>>", out)[-1]


def set_forwarder(names):
    code = f'''Set p=##class(Ens.Config.Production).%OpenId("DocSite.Production"),i=p.FindItemByConfigName("Shutter Forwarder")
Set s=##class(Ens.Config.Setting).%New(),s.Name="DocumentReceivers",s.Target="Host",s.Value="{names}"
Do i.Settings.Insert(s)
Write !,"<<<",p.%Save(),p.SaveToClass(),">>>",!
Write !,"<<<",##class(Ens.Director).UpdateProduction(),">>>",!'''
    return session(NS, code)


def profile_with_documents():
    """The site profile with the two document receivers switched on, as an approver saves it."""
    code, r = api("GET", "/site-profile")
    p = r["profile"]
    names = [x["name"] for x in p["receivers"]]
    for rc in p["receivers"]:
        if rc["name"].endswith("Docs Out") or rc["name"].endswith("Docs Refuse Out"):
            rc["documents"] = {"enabled": True}
    code, r2 = api("PUT", "/site-profile", p)
    return code, names, r2


# ---- the stock instance ----
if not args.reuse:
    step("A stock instance, with Shutter installed without the demo, and a documents namespace running its own production")
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
    target = f"{HOME}/pkg/{args.module}" if args.module else f"{HOME}/pkg"
    out = session("SHUTTER", f'Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck")\nSet sc=##class(%IPM.Main).Shell("load {target} -Ddemo=0") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 580)
    check("the load finishes", "RESULT: ok" in out, out[-800:])
    session("SHUTTER", f'Write ##class(Shutter.Setup).CreateNamespace("{NS}")')
    subprocess.run(["docker", "exec", "-u", "root", CTR, "mkdir", "-p", "/tmp/doc_site"], check=True)
    subprocess.run(["docker", "cp", SITE + "/.", f"{CTR}:/tmp/doc_site"], check=True)
    subprocess.run(["docker", "cp", os.path.join(ONB, "mllp.py"), f"{CTR}:/tmp/doc_site/mllp.py"], check=True)
    subprocess.run(["docker", "exec", "-u", "root", CTR, "chown", "-R", "irisowner:irisowner", "/tmp/doc_site"], check=True)
    lines = [f'Set sc=$SYSTEM.OBJ.Load("/tmp/doc_site/{f}.cls","ck-d") Write !,"[c] ",sc,!' for f in ("DocSite.Swap", "DocSite.Rule", "DocSite.Production")]
    lines.append('Set sc=##class(Ens.Director).StartProduction("DocSite.Production") Write !,"[start] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
    out = session(NS, "\n".join(lines))
    check(f"{NS} runs DocSite.Production", "[start] ok" in out, out[-600:])
    session("SHUTTER", f'''Set $NAMESPACE="%SYS"
Set a=##class(Security.Users).Create("appr1","Shutter_Approver","{PW}","An approver","SHUTTER","","",0,1)
Set a=##class(Security.Users).Create("oper1","Shutter_Operator","{PW}","An operator","SHUTTER","","",0,1)
Set $NAMESPACE="SHUTTER"
Set d=##class(EnsLib.Workflow.UserDefinition).CreateUser("appr1","An approver")
Set e=##class(EnsLib.Workflow.RoleDefinition).AddUserToRole("Shutter Approvers","appr1",1,"Approver")''')
    out = session("SHUTTER", f'''Write ##class(Shutter.Setup).OnboardApply("{NS}","{{}}"),!''')
    print(out[-700:])
    out = session("SHUTTER", f'Do ##class(Shutter.Setup).OnboardCredential("{NS}","shutter-fwd","{PW}")')
    check("the credential is stored", '"ok":true' in out, out[-300:])
    time.sleep(3)

code, _ = api("POST", "/session", {"username": "appr1", "password": PW})
check("the approver signs in", code in (200, 201), code)
code, _ = op_api("POST", "/session", {"username": "oper1", "password": PW})
check("the operator signs in", code in (200, 201), code)

if not args.reuse:
    step("Document profiles on two receivers, off everywhere else; the forwarder names three, one of them with no profile")
    code, names, answer = profile_with_documents()
    print("  receivers:", names)
    check("the approver saves the profile", code == 200, answer)
    print(set_forwarder("Docs Out,Docs Refuse Out,Docs Half Out")[-200:])
    time.sleep(3)

if subprocess.run(["docker", "exec", CTR, "pgrep", "-f", "doc_listener.py"], capture_output=True).returncode != 0:
    subprocess.Popen(["docker", "exec", CTR, "python3", "/tmp/doc_site/doc_listener.py", "7313", "/tmp/doc_site/heard-7313.log", "3400"])
    time.sleep(1)

tag = time.strftime("%H%M%S")
RECEIVER = "Docs Out"

# ---- the fixtures ----
if wanted("D26"):
    step("D26: a receiver with no document profile: what it does today, unchanged")
    before = external_rows()
    ctl = f"D26-{tag}"
    send(mdm("T02", ctl, doc=f"D26DOC^DMS", app="PLAIN"), "d26")
    c = case_of(ctl)
    check("it opens the ordinary case", c and c.get("failureKind") == "unmappable", c)
    check("with no document block", c and "document" not in c, c and c.get("document"))
    check("through the ordinary intake, one more stored copy", external_rows() != before, (before, external_rows()))
    _, snap = api("GET", f"/cases/{c['caseId']}/snapshot") if c else (0, {})
    check("and its snapshot still copies the OBX, as v1.0.0 does", "Synthetic letter text" in json.dumps(snap), json.dumps(snap)[:300])
    ctl = f"D26H-{tag}"
    send(mdm("T02", ctl, doc="D26HDOC^DMS", app="HALF"), "d26h")
    c = case_of(ctl)
    check("a forwarder that names a receiver with no profile falls back to the ordinary intake", c and c.get("failureKind") == "unmappable" and "document" not in c, c)

if wanted("BASE"):
    step("The block: identity, parent, patient, delivery; no copy of the document")
    rows = session_count()
    ctl = f"BASE-{tag}"
    send(mdm("T02", ctl, doc=f"BASE{tag}^DMS^1.2.3^ISO"), "base")
    c = case_of(ctl)
    d = (c or {}).get("document", {})
    check("a document case opens and goes to a person", c and c.get("state") == "escalated", c)
    check("it says Shutter has sent nothing", d.get("sent_nothing") is True and (c or {}).get("counts", {}).get("attempts") == 0, d)
    check("full TXA-12, all four parts", d.get("document", {}).get("id") == f"BASE{tag}^DMS^1.2.3^ISO", d.get("document"))
    keys = [k["id"] for k in d.get("patient", {}).get("keys", [])]
    check("every PID-3 repetition", keys == ["MRN7001", "9990001001"], d.get("patient"))
    check("the trigger, TXA-17, -18 and -19", d.get("trigger") == "T02" and d.get("document", {}).get("completion") == "AU" and d.get("document", {}).get("confidentiality") == "U" and d.get("document", {}).get("availability") == "AV", d)
    check("the delivery evidence: the engine's status at the operation", d.get("delivery", {}).get("status") in ("Error", "Suspended", "Discarded"), d.get("delivery"))
    check("no stored HL7 copy in Shutter's namespace", session_count() == rows, (rows, session_count()))
    check("and says so", d.get("body_stored_in_shutter") is False, d)
    check("the operation key is no key of the ADT form", (c or {}).get("operationKey", "").startswith("mdm-v1:"), (c or {}).get("operationKey"))
    _, snap = api("GET", f"/cases/{c['caseId']}/snapshot") if c else (0, {})
    check("no OBX in the snapshot", "Synthetic letter text" not in json.dumps(snap) and '"notes"' not in json.dumps(snap), json.dumps(snap)[:400])
    a = op_api("POST", f"/cases/{c['caseId']}/board", {})
    time.sleep(3)
    _, again = api("GET", "/cases/" + c["caseId"])
    check("asking for the board runs no agent", again["counts"]["runs"] == 0, (a, again["counts"]))
    a = api("POST", f"/cases/{c['caseId']}/approvals", {"decision": "approve", "planDigest": "sha256:x"})
    check("an approval is refused", a[0] in (403, 409), a)

if wanted("D06"):
    step("D06: a receiver's AE and AR: the exact refusal, no resend, no edit")
    for code in ("AE", "AR"):
        ctl = f"{code}-{tag}"
        send(mdm("T02", ctl, doc=f"D06{code}{tag}^DMS", app="REFUSE"), "d06" + code)
        c = case_of(ctl)
        d = (c or {}).get("document", {})
        print("  refusal seen by the approver:", json.dumps(d.get("refusal"))[:400])
        check(f"{code}: the code is shown", d.get("refusal", {}).get("ack_code") == code, d.get("refusal"))
        check(f"{code}: an authorised reviewer reads the receiver's words", "CANARYDIAG" in json.dumps(d.get("refusal")), d.get("refusal"))
        _, o = op_api("GET", "/cases/" + (c or {}).get("caseId", "x"))
        check(f"{code}: an operator gets the code and not the words", "CANARYDIAG" not in json.dumps(o) and o.get("document", {}).get("refusal", {}).get("ack_code") == code, o.get("document", {}).get("refusal"))
        n = heard(7313).count(ctl)
        time.sleep(4)
        check(f"{code}: the listener heard no more from Shutter", heard(7313).count(ctl) == n and n >= 1, (n, heard(7313)))

if wanted("D07"):
    step("D07: 10 MB and 40 MB base64 documents: a metadata case, with no copy and no large value in memory")
    for mb in (10, 40):
        rows, ext = session_count(), external_rows()
        ctl = f"D07{mb}-{tag}"
        payload = base64.b64encode(os.urandom(mb * 1024 * 1024 * 3 // 4)).decode()
        o = send(mdm("T02", ctl, doc=f"D07{mb}{tag}^DMS", obx=f"OBX|1|ED|DOC^Letter||^application^pdf^Base64^{payload}"), f"d07{mb}", wait=120)
        print("  sent:", o[:200])
        c = case_of(ctl, 150)
        d = (c or {}).get("document", {})
        print("  size:", d.get("size"), "state:", (c or {}).get("state"))
        check(f"{mb} MB: a case opens", bool(c) and c.get("state") == "escalated", c)
        check(f"{mb} MB: the size is recorded, over the intake's limit", d.get("size", {}).get("stored_bytes", 0) >= mb * 1024 * 1024 and d.get("size", {}).get("over_intake_limit") is True, d.get("size"))
        check(f"{mb} MB: no copy in Shutter", session_count() == rows and external_rows() == ext, (rows, session_count(), ext, external_rows()))
        block = value("SHUTTER", f'$LENGTH(##class(Shutter.Store.Case).ByCaseId("{(c or {}).get("caseId", "x")}").DocumentJSON)')
        print("  block length:", block)
        check(f"{mb} MB: the case's block stays small", int(block) < 30000, block)
        hid = d.get("delivery", {}).get("header_id", "0")
        code = f'''Set h=##class(Ens.MessageHeader).%OpenId("{hid}"),m=##class(EnsLib.HL7.Message).%OpenId(h.MessageBodyId)
Set $ZSTORAGE=4096
Set r=$ZSTORAGE,before=$STORAGE
Try {{ Set f=##class(Shutter.Util.DocumentFacts).FromMessage(m,.sc) Write !,"<<<facts:",$SELECT($ISOBJECT(f):f.trigger,1:"none"),":",$SELECT($ISOBJECT(f)&&$ISOBJECT(f.digests):$L(f.digests.body),1:0),":",before-$STORAGE,">>>",! }} Catch e {{ Write !,"<<<facts:error:",e.DisplayString(),">>>",! }}
Try {{ Set s=m.OutputToString(,,.osc) Write !,"<<<string:",$L(s),":",$SYSTEM.Status.GetErrorText(osc),">>>",! }} Catch e {{ Write !,"<<<string:error:",e.Name,">>>",! }}'''
        out = re.findall(r"<<<(.*?)>>>", session(NS, code, 300), re.S)
        print("  under a 4 MB process limit:", [x[:160] for x in out])
        check(f"{mb} MB: the extraction and its digest run under a 4 MB process limit", out and out[0].startswith("facts:T02:64:"), out)
        check(f"{mb} MB: the control, the whole message as a string, does not", len(out) > 1 and (out[1].startswith("string:error") or "MAXSTRING" in out[1] or "STORE" in out[1] or out[1].startswith("string:0")), out)
    ctl = f"D07F-{tag}"
    code, r = post_intake({"source": {"namespace": NS, "production": "DocSite.Production", "route": "Docs In", "header_id": "1"}, "receiver": "Docs Out", "failure": {"kind": "delivery_failed", "text": "t", "outcome": "error"}, "message": "\r".join(mdm("T02", ctl, doc="D07F^DMS")) + "\r"})
    c = case_of(ctl)
    check("a forwarder that posts the whole text to a receiver with a profile: no copy kept, a document case", code == 202 and c and "document" in c and session_count() == rows, (code, r, c))

if wanted("D08"):
    step("D08: no TXA-12, and no TXA at all")
    for name, segs in (("blank", mdm("T02", f"D08A-{tag}", doc="")), ("absent", mdm("T02", f"D08B-{tag}", no_txa=True))):
        ctl = segs[0].split("|")[9]
        send(segs, "d08" + name)
        c = case_of(ctl)
        d = (c or {}).get("document", {})
        check(f"{name}: a case opens, with reason DOC_ID_MISSING", "DOC_ID_MISSING" in reasons(c), c)
        check(f"{name}: it invents no document key", not d.get("document", {}).get("id") and ctl not in json.dumps(d.get("document", {})), d.get("document"))
        check(f"{name}: it says so", "no usable document identifier" in (c or {}).get("headline", ""), (c or {}).get("headline"))
        check(f"{name}: chain coverage is incomplete, not empty", d.get("chain", {}).get("complete") is False and "cannot establish" in says(c).lower(), d.get("chain"))

if wanted("D09"):
    step("D09: a T02 and a T08 share TXA-12 with different content")
    doc = f"D09{tag}^DMS"
    a, b = f"D09A-{tag}", f"D09B-{tag}"
    send(mdm("T02", a, doc=doc), "d09a")
    ca = case_of(a)
    send(mdm("T08", b, doc=doc, obx="OBX|1|TX|DOC^Letter||Edited text"), "d09b")
    cb = case_of(b)
    check("two cases, two operation keys", ca and cb and ca["caseId"] != cb["caseId"] and ca["operationKey"] != cb["operationKey"], (ca, cb))
    check("the T08's case finds the T02 in its chain", "T02" in says(cb) and "DOC_VERSION_CONFLICT" in reasons(cb) or "DOC_REPLACED_OR_EDITED" in reasons(cb), (reasons(cb), says(cb)))
    api("POST", f"/cases/{ca['caseId']}/reinvestigate", {"reason": "check"})
    time.sleep(22)
    ca = case_of(a, 60)
    check("the T02's case, read again, says a T08 exists", "DOC_REPLACED_OR_EDITED" in reasons(ca) and "T08" in says(ca), (reasons(ca), says(ca)))

if wanted("D10"):
    step("D10: a T10 with its own number names the failed T02 as its parent")
    parent = f"D10P{tag}^DMS"
    a, b = f"D10A-{tag}", f"D10B-{tag}"
    send(mdm("T02", a, doc=parent), "d10a")
    ca = case_of(a)
    send(mdm("T10", b, doc=f"D10N{tag}^DMS", parent=parent), "d10b")
    cb = case_of(b)
    check("the T10's block shows the parent", (cb or {}).get("document", {}).get("document", {}).get("parent") == parent, (cb or {}).get("document"))
    api("POST", f"/cases/{ca['caseId']}/reinvestigate", {"reason": "check"})
    time.sleep(22)
    ca = case_of(a, 60)
    check("the T02's case says a T10 replaces it", "DOC_REPLACED_OR_EDITED" in reasons(ca) and "T10" in says(ca), (reasons(ca), says(ca)))
    check("the T10 itself is held as unproven parent", "DOC_PARENT_UNPROVEN" in reasons(cb), reasons(cb))
    check("neither was sent by Shutter", ca["counts"]["attempts"] == 0 and cb["counts"]["attempts"] == 0)

if wanted("D11"):
    step("D11: a T11 follows a failed T02, and fails too")
    doc = f"D11{tag}^DMS"
    a, b = f"D11A-{tag}", f"D11B-{tag}"
    send(mdm("T02", a, doc=doc), "d11a")
    ca = case_of(a)
    send(mdm("T11", b, doc=doc, avail="CA"), "d11b")
    cb = case_of(b)
    api("POST", f"/cases/{ca['caseId']}/reinvestigate", {"reason": "check"})
    time.sleep(22)
    ca = case_of(a, 60)
    check("the T02's case says a T11 names it", "DOC_CANCELLED" in reasons(ca) and "T11" in says(ca), (reasons(ca), says(ca)))
    check("the words do not claim the document is deleted", "deleted" not in says(ca).lower(), says(ca))

if wanted("D12"):
    step("D12: a T06 before its parent, the parent absent")
    b = f"D12-{tag}"
    send(mdm("T06", b, doc=f"D12N{tag}^DMS", parent=f"D12ABSENT{tag}^DMS"), "d12")
    c = case_of(b)
    check("parent unproven", "DOC_PARENT_UNPROVEN" in reasons(c), reasons(c))
    check("it says the parent was not found", "not found" in says(c).lower(), says(c))
    b = f"D12B-{tag}"
    send(mdm("T06", b, doc=f"D12M{tag}^DMS"), "d12b")
    c = case_of(b)
    check("a T06 with no TXA-13: parent unproven too, as the standard requires one", "DOC_PARENT_UNPROVEN" in reasons(c), reasons(c))

if wanted("D13"):
    step("D13: one document number on two patients")
    doc = f"D13{tag}^DMS"
    a, b = f"D13A-{tag}", f"D13B-{tag}"
    send(mdm("T02", a, doc=doc, mrn="MRN1301"), "d13a")
    case_of(a)
    send(mdm("T02", b, doc=doc, mrn="MRN1302"), "d13b")
    c = case_of(b)
    check("a patient-binding conflict", "DOC_PATIENT_CHANGED" in reasons(c), reasons(c))
    check("and nothing is reassigned or sent", c and c["counts"]["attempts"] == 0 and c["patientId"] == "MRN1302", c)

if wanted("D15"):
    step("D15: restricted, cancelled, obsolete, unknown and missing status values")
    rows = [("R", "AV", "AU", "DOC_RESTRICTED", True), ("V", "AV", "AU", "DOC_RESTRICTED", True), ("ZZ", "AV", "AU", "DOC_RESTRICTED", True), ("U", "CA", "AU", "DOC_CANCELLED", False), ("U", "OB", "AU", "DOC_REPLACED_OR_EDITED", False), ("U", "ZZ", "AU", "DOC_STATUS_UNPROVEN", False), ("U", "AV", "", "DOC_STATUS_UNPROVEN", False), ("", "", "AU", "DOC_STATUS_UNPROVEN", False)]
    for i, (conf, avail, comp, want, restricted) in enumerate(rows):
        ctl = f"D15{i}-{tag}"
        send(mdm("T02", ctl, doc=f"CANARYRESTRICTED{i}{tag}^DMS" if restricted else f"D15{i}{tag}^DMS", mrn=f"CANARYRESTRICTEDMRN{i}" if restricted else "MRN1500", conf=conf, avail=avail, completion=comp), f"d15{i}")
        c = case_of(ctl)
        print(f"  TXA-18 {conf or '-'} TXA-19 {avail or '-'} TXA-17 {comp or '-'}: {reasons(c)}")
        check(f"{conf or 'none'}/{avail or 'none'}/{comp or 'none'}: {want}", want in reasons(c), reasons(c))
        code, esc = op_api("POST", f"/cases/{(c or {}).get('caseId', 'x')}/escalations", {})
        body = json.dumps(esc)
        check(f"{conf or 'none'}/{avail or 'none'}/{comp or 'none'}: the email carries no identifier", "MRN1500" not in body and "CANARYRESTRICTED" not in body and "D15" not in body.replace((c or {}).get("caseId", ""), "") and "Synthetic" not in body, body[:500])
        if restricted:
            check("restricted: the email says an authorised reviewer", "authorised reviewer" in body, body[:500])
            _, o = op_api("GET", "/cases/" + c["caseId"])
            check("restricted: an operator sees no identity at all", "CANARYRESTRICTED" not in json.dumps(o), json.dumps(o)[:500])
            check("restricted: the headline says so", "authorised reviewer" in o.get("headline", ""), o.get("headline"))
            _, a = api("GET", "/cases/" + c["caseId"])
            check("restricted: an approver sees the identity", "CANARYRESTRICTED" in json.dumps(a.get("document")), a.get("document"))
            for path in ("/snapshot", "/events", "/plan"):
                _, s = api("GET", f"/cases/{c['caseId']}{path}")
                check(f"restricted: nothing in {path}, even for the approver", "CANARYRESTRICTED" not in json.dumps(s), json.dumps(s)[:300])

if wanted("D17"):
    step("D17: the same control id with changed content; the same content under a new control id")
    doc = f"D17{tag}^DMS"
    a = f"D17A-{tag}"
    send(mdm("T02", a, doc=doc), "d17a")
    ca = case_of(a)
    send(mdm("T02", a, doc=doc, obx="OBX|1|TX|DOC^Letter||Changed text"), "d17b")
    time.sleep(20)
    code, r = api("GET", "/cases?limit=200")
    same = [x for x in r["items"] if x.get("sourceMessageId") == a]
    check("two cases: the second is no duplicate of the first", len(same) == 2 and same[0]["operationKey"] != same[1]["operationKey"], same)
    newest = case_of(a, 60) if not same else api("GET", "/cases/" + same[0]["caseId"])[1]
    check("the conflict is named", "DOC_VERSION_CONFLICT" in reasons(newest), (reasons(newest), says(newest)))
    b = f"D17C-{tag}"
    send(mdm("T02", b, doc=doc), "d17c")
    cb = case_of(b)
    check("the same content under a new control id: its own case, not merged", cb and cb["caseId"] != ca["caseId"], cb)
    check("and the chain calls it a possible retransmission", "retransmission" in says(cb), says(cb))

if wanted("D18"):
    step("D18: a DTL changes the patient and the document before the operation")
    ctl = f"D18-{tag}"
    send(mdm("T02", ctl, doc="SERVICEDOC^DMS", mrn="SERVICEMRN", app="DTL"), "d18")
    c = case_of(ctl)
    d = (c or {}).get("document", {})
    check("the case shows what the operation was given", d.get("document", {}).get("id") == "DELIVEREDDOC^DMS" and d.get("patient", {}).get("keys", [{}])[0].get("id") == "DELIVEREDMRN", d)
    check("not the service's values", "SERVICEDOC" not in json.dumps(c) and "SERVICEMRN" not in json.dumps(c), c)

if wanted("D28"):
    step("D28: extraction failure, cap hit and a namespace that isn't here; a chain read live has no index to lag")
    doc = f"D28{tag}^DMS"
    a = f"D28A-{tag}"
    send(mdm("T02", a, doc=doc), "d28a")
    c = case_of(a)
    check("first, a complete read says what it covered", (c or {}).get("document", {}).get("chain", {}).get("complete") is True and "messages to" in says(c), (c or {}).get("document", {}).get("chain"))
    # the cap: one message read, by the profile's limit
    code, r = api("GET", "/site-profile")
    p = r["profile"]
    for rc in p["receivers"]:
        if rc["name"].endswith("Docs Out"):
            rc["documents"]["chain_read_limit"] = 1
    code, ans = api("PUT", "/site-profile", p)
    check("the limit saves", code == 200, ans)
    api("POST", f"/cases/{c['caseId']}/reinvestigate", {"reason": "check"})
    time.sleep(22)
    c = case_of(a, 60)
    check("cap hit: chain coverage incomplete", "DOC_CHAIN_INCOMPLETE" in reasons(c) and "incomplete" in says(c).lower(), (reasons(c), says(c)))
    code, r = api("GET", "/site-profile")
    p = r["profile"]
    for rc in p["receivers"]:
        if rc["name"].endswith("Docs Out"):
            rc["documents"].pop("chain_read_limit", None)
    api("PUT", "/site-profile", p)
    # an unreadable body among the messages to the receiver
    b = f"D28B-{tag}"
    send(mdm("T02", b, doc=f"D28X{tag}^DMS"), "d28b")
    cb = case_of(b)
    hid = (cb or {}).get("document", {}).get("delivery", {}).get("header_id", "0")
    out = session(NS, f'Set h=##class(Ens.MessageHeader).%OpenId("{hid}"),old=h.MessageBodyId,h.MessageBodyId="99999999" Write !,"<<<",h.%Save(),">>>",!')
    api("POST", f"/cases/{c['caseId']}/reinvestigate", {"reason": "check"})
    time.sleep(22)
    c = case_of(a, 60)
    check("extraction failure: chain coverage incomplete", "DOC_CHAIN_INCOMPLETE" in reasons(c) and "could not be read" in says(c), (reasons(c), says(c)))
    # a namespace that is not on this instance, and an envelope with no chain
    ctl = f"D28C-{tag}"
    code, r = post_intake({"kind": "document_failure", "source": {"namespace": "NOSUCH", "production": "Remote", "route": "x", "header_id": "1", "item": "Docs Out"}, "receiver": "Docs Out", "failure": {"kind": "delivery_failed", "text": "t", "outcome": "error"}, "facts": {"trigger": "T02", "structure": "MDM_T02", "control_id": ctl, "document": {"id": "REMOTE^DMS", "parent": "", "completion": "AU", "confidentiality": "U", "availability": "AV"}, "patient": {"keys": [], "binding": ""}, "digests": {"body": "x", "content": "x"}, "size": {"stored_bytes": 10}}})
    check("the intake takes the envelope", code == 202, r)
    c = case_of(ctl)
    check("missing namespace: chain coverage incomplete", "DOC_CHAIN_INCOMPLETE" in reasons(c) and "NOSUCH" in says(c), (reasons(c), says(c)))
    check("and the source is marked unverified", (c or {}).get("document", {}).get("source_verified") is False, (c or {}).get("document"))

if wanted("PRIVACY"):
    step("Canaries: one document carrying each, and every surface read")
    ctl = f"AE-CAN-{tag}"
    obx = f"OBX|1|ED|DOC^CANARYTITLE^L||^application^pdf^Base64^{PDF_B64}CANARYBASE64TEXT"
    segs = mdm("T02", ctl, doc=f"CANARYRESTRICTED{tag}^DMS", mrn="CANARYRESTRICTEDMRN", conf="R", app="REFUSE", name="CANARYNAME^CANARYNAME", filename="CANARYTITLE.pdf", obx=obx)
    segs.append("OBX|2|TX|NOTE^CANARYTITLE^L||CANARYOBXTEXT")
    send(segs, "can")
    c = case_of(ctl)
    ctl2 = f"AE-CAN2-{tag}"
    segs = mdm("T02", ctl2, doc=f"PLAIN{tag}^DMS", mrn="MRN8800", conf="U", app="REFUSE", name="CANARYNAME^CANARYNAME", filename="CANARYTITLE.pdf", obx=obx)
    segs.append("OBX|2|TX|NOTE^CANARYTITLE^L||CANARYOBXTEXT")
    send(segs, "can2")
    c2 = case_of(ctl2)
    allowed_in_store = {"receiver_diagnostic", "restricted_metadata"}
    for label, cc in (("restricted", c), ("usual", c2)):
        cid = (cc or {}).get("caseId", "x")
        print(f"  {label}: {cid}, reasons {reasons(cc)}")
        surfaces = {}
        for path in ("", "/events", "/snapshot", "/plan", "/blocked-reason", "/runs", "/whatif", "/escalations", "/closure"):
            surfaces["operator API " + (path or "/case")] = json.dumps(op_api("GET", f"/cases/{cid}{path}")[1])
        code, esc = op_api("POST", f"/cases/{cid}/escalations", {})
        surfaces["email draft"] = json.dumps(esc)
        surfaces["operator API /cases"] = json.dumps(op_api("GET", "/cases?limit=200")[1])
        out = session("SHUTTER", f'''Write !,"<<<",##class(Shutter.Util.ModelView).Preview("{cid}"),">>>",!''')
        preview = re.findall(r"<<<(.*?)>>>", out, re.S)
        surfaces["model request"] = preview[-1] if preview else out[-400:]
        check(f"{label}: the model's view of the case was built", bool(preview) and "case_id" in surfaces["model request"], out[-300:])
        for surface, text in surfaces.items():
            hits = [n for n, canary in CANARIES.items() if canary in text]
            check(f"{label}: {surface} holds no canary", not hits, (hits, text[:300]))
        _, snap = api("GET", f"/cases/{cid}/snapshot")
        hits = [n for n, canary in CANARIES.items() if canary in json.dumps(snap)]
        check(f"{label}: the snapshot holds none, for an approver too", not hits, hits)
        check(f"{label}: no agent ran", api("GET", "/cases/" + cid)[1]["counts"]["runs"] == 0)
    step("Every global of Shutter's namespace searched for each canary, and the source's message store")
    code = r'''Set rs=##class(%ResultSet).%New("%SYS.GlobalQuery:NameSpaceListChui") Do rs.Execute($NAMESPACE,"*",0,,,1)
For { Quit:'rs.Next()  Set g="^"_rs.GetData(1) Continue:(g="^IRIS.Temp")  Set n=g,seen=0 For c=1:1:2000000 { Set n=$QUERY(@n) Quit:n=""  If $QLENGTH(n)'<0,$GET(@n)["CANARY" { Set v=@n Set p=$FIND(v,"CANARY") Write !,"<<<",g,"|",$E(v,p-6,p+14),">>>" Set seen=seen+1 Quit:seen>12 } } }
Write !,"<<<END>>>",!'''
    out = session("SHUTTER", code, 500)
    rows = [x for x in re.findall(r"<<<(.*?)>>>", out) if x != "END"]
    by = {}
    for r in rows:
        g, v = r.split("|", 1)
        by.setdefault(g, set()).add(re.match(r"CANARY[A-Z0-9]*", v).group(0) if re.match(r"CANARY[A-Z0-9]*", v) else v)
    print("  in Shutter's namespace:", json.dumps({k: sorted(v) for k, v in by.items()}, indent=1))
    check("the walk finished", "<<<END>>>" in out, out[-500:])
    content = ("CANARYPDFBYTES", "CANARYBASE64TEXT", "CANARYOBXTEXT", "CANARYTITLE", "CANARYNAME")
    bad = {k: [x for x in v if x.startswith(content)] for k, v in by.items()}
    check("no document content or patient name anywhere in Shutter's namespace", not any(bad.values()), bad)
    out = session(NS, r'''Set found="" Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TOP 40 ID,MessageBodyId FROM Ens.MessageHeader WHERE TargetConfigName='Docs Refuse Out' ORDER BY ID DESC") While rs.%Next() { Set m=##class(EnsLib.HL7.Message).%OpenId(rs.%Get("MessageBodyId")) Continue:'$ISOBJECT(m)  Set s=m.OutputToString() For w="CANARYBASE64TEXT","CANARYOBXTEXT","CANARYTITLE","CANARYNAME" { If s[w Set found(w)="" } }
Set k="" For { Set k=$ORDER(found(k)) Quit:k=""  Write !,"<<<",k,">>>",! }''')
    src = re.findall(r"<<<(CANARY.*?)>>>", out)
    print("  in the source namespace's message store:", sorted(set(src)))
    check("the content does remain: in the hospital's own message store, subject to its retention", {"CANARYBASE64TEXT", "CANARYOBXTEXT", "CANARYNAME"} <= set(src), out[-300:])

# A community licence counts each signed-in session until it times out.
api("DELETE", "/session")
op_api("DELETE", "/session")
print(f"\n{passed} checks passed, {len(failed)} failed")
for f in failed:
    print("  FAILED:", f)
if not args.keep:
    subprocess.run(["docker", "rm", "-f", CTR], capture_output=True)
sys.exit(1 if failed else 0)
