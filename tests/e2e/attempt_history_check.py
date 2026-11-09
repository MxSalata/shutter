#!/usr/bin/env python3
"""Whether the engine's records show every attempt it made to a receiver, played on a real instance on stock classes.

    python3 tests/e2e/attempt_history_check.py [--image IMAGE] [--port 52797] [--ctr attempt-check] [--keep] [--module core]

The set (Shutter.Util.ResendSet) offers a failed message to be sent again only when every Error row the engine kept for it
says the connection never opened. That holds only if every attempt that reached the receiver left such a row. Read in the
engine's source (Ens.BusinessOperation's MessageHeaderHandler): inside one job's handling of a message, an attempt's error is
logged whenever its words differ from the attempt before, so a reached attempt always leaves a row; but an attempt cut off by
a stop or a crash leaves none, and the engine then puts the message back on its queue unmarked. This plays both sides at a
stock EnsLib.HL7.Operation.TCPOperation and a fake receiver that records every frame it is given:

  A  a clean outage: two messages, the listener down throughout. Each has its own never-opened rows (repeats are suppressed
     inside one message, never across messages), nothing was heard, and the set offers both.
  B  a reached attempt between attempts that never opened, in one job: the read timeout is logged, so the set reads it as
     reached and does not offer it. (A receiver that closes the connection while the engine waits is logged too, as a lost
     read; the stop and the crash below keep the connection open, as a hung receiver does.)
  C  a forced production stop while an attempt waits for the reply, then attempts that never open: the receiver holds the
     frame, every Error row says never opened (the hazard is real), and the set refuses it as interrupted, at the list and at
     Engine Resend's check before each send.
  D  the same with the instance killed (a crash), recovered and started again.
  E  a stock purge of the event log: a header whose rows are gone is not offered.

The container is removed at the end unless --keep. Needs Docker and no API key. Run from the repository's root. Exit status 0
when every check passed, 1 when one failed, 3 when the rig itself broke. Standard library only.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

HOME = "/home/irisowner"
NS = "PROBE"
CTR = "attempt-check"
FAILED = []
LONG, SHORT = ("Probe Out", 7600), ("Probe Short Out", 7601)

PRODUCTION = """Class Probe.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="Probe.Production" TestingEnabled="true" LogGeneralTraceEvents="false">
  <ActorPoolSize>1</ActorPoolSize>
  <Item Name="Probe Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7600</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">3</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">60</Setting>
    <Setting Target="Host" Name="FailureTimeout">25</Setting>
    <Setting Target="Host" Name="RetryInterval">3</Setting>
  </Item>
  <Item Name="Probe Short Out" ClassName="EnsLib.HL7.Operation.TCPOperation" PoolSize="1" Enabled="true">
    <Setting Target="Adapter" Name="IPAddress">127.0.0.1</Setting>
    <Setting Target="Adapter" Name="Port">7601</Setting>
    <Setting Target="Adapter" Name="ConnectTimeout">3</Setting>
    <Setting Target="Adapter" Name="ResponseTimeout">3</Setting>
    <Setting Target="Host" Name="FailureTimeout">30</Setting>
    <Setting Target="Host" Name="RetryInterval">3</Setting>
  </Item>
</Production>
}

}
"""

# A test request through the engine's own testing service, and the header to an item that carries a control id.
UTIL = """Class Probe.Util
{

ClassMethod Send(item As %String, ctl As %String) As %String
{
    Set m = ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\\&|FAKESEND|SITE|FAKELIMS|LAB|20261109080000||ORU^R01|" _ ctl _ "|P|2.4" _ $CHAR(13) _ "PID|1||" _ ctl _ "^^^HOSP^MR||Probe^" _ ctl _ "||19800101|U" _ $CHAR(13) _ "OBR|1|" _ ctl _ "||FBC^Full blood count^L" _ $CHAR(13), .sc)
    Quit:$$$ISERR(sc) $SYSTEM.Status.GetErrorText(sc)
    Set sc = ##class(EnsLib.Testing.Service).SendTestRequest(item, m, .resp, .sid, 0)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

ClassMethod HeaderOf(item As %String, ctl As %String) As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, MessageBodyId FROM Ens.MessageHeader WHERE TargetConfigName = ? AND MessageBodyClassName = 'EnsLib.HL7.Message' ORDER BY ID", item)
    While rs.%Next() {
        Set m = ##class(EnsLib.HL7.Message).%OpenId(rs.MessageBodyId)
        If $ISOBJECT(m) && (m.GetValueAt("1:10") = ctl) Return rs.ID
    }
    Quit ""
}

ClassMethod Status(id As %String) As %String
{
    Set h = ##class(Ens.MessageHeader).%OpenId(id)
    Quit $SELECT($ISOBJECT(h): ##class(Ens.DataType.MessageStatus).LogicalToDisplay(h.Status), 1: "")
}

}
"""

LISTENER = r'''import socket, sys, threading
port, log = int(sys.argv[1]), sys.argv[2]
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", port)); s.listen(5)
def serve(c):
    buf = b""
    while True:
        try:
            d = c.recv(65536)
        except Exception:
            return
        if not d:
            return
        buf += d
        while b"\x1c\r" in buf:
            frame, buf = buf.split(b"\x1c\r", 1)
            with open(log, "a") as f:
                f.write(frame.lstrip(b"\x0b").split(b"\r")[0].split(b"|")[9].decode() + "\n")
while True:
    c, _ = s.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
'''


class RigBroken(Exception):
    pass


def check(what, ok, detail=""):
    print(f"  {'ok' if ok else 'FAIL':10}  {what}", flush=True)
    if not ok:
        print(f"        {str(detail)[:1500]}", flush=True)
        FAILED.append(what)


def step(text):
    print(f"\n[{time.strftime('%H:%M:%S')}] {text}", flush=True)


def docker(*args, check=True, **kw):
    return subprocess.run(["docker", *args], capture_output=True, text=True, check=check, **kw)


def session(ns, code, timeout=600):
    r = subprocess.run(["docker", "exec", "-i", CTR, "iris", "session", "IRIS", "-U", ns], input=code + "\nHalt\n", capture_output=True, text=True, timeout=timeout, errors="replace")
    return r.stdout


def value(ns, expr):
    out = session(ns, f'Set %v = {expr}\nWrite !,"<<<",%v,">>>",!')
    m = re.findall(r"<<<(.*?)>>>", out, re.S)
    if not m:
        raise RigBroken(f"no value for {expr} in {ns}: {out[-800:]}")
    return m[-1]


def obj(ns, expr):
    return json.loads(value(ns, expr))


def wait_up():
    for _ in range(100):
        if "^running" in docker("exec", CTR, "iris", "qlist", "IRIS", check=False).stdout:
            return
        time.sleep(3)
    raise RigBroken("the instance did not come up")


def listener(item, on):
    port = item[1]
    docker("exec", CTR, "pkill", "-f", f"listener.py {port}", check=False)
    if on:
        docker("exec", "-d", CTR, "python3", "/tmp/listener.py", str(port), f"/tmp/heard-{port}")
        for _ in range(20):
            if f"127.0.0.1:{port}" in docker("exec", CTR, "sh", "-c", "ss -ltn", check=False).stdout:
                return
            time.sleep(0.5)
        raise RigBroken(f"the listener on {port} did not start")


def heard(item):
    r = docker("exec", CTR, "cat", f"/tmp/heard-{item[1]}", check=False)
    return r.stdout.split() if r.returncode == 0 else []


def wait_for(what, fn, seconds, every=2):
    end = time.time() + seconds
    while time.time() < end:
        got = fn()
        if got:
            return got
        time.sleep(every)
    raise RigBroken(f"{what} did not happen within {seconds} s")


def send(item, ctl):
    if value(NS, f'##class(Probe.Util).Send("{item[0]}","{ctl}")') != "ok":
        raise RigBroken(f"{ctl} could not be sent")
    return wait_for(f"{ctl}'s header", lambda: value(NS, f'##class(Probe.Util).HeaderOf("{item[0]}","{ctl}")'), 30)


def status(h):
    return value(NS, f'##class(Probe.Util).Status({h})')


def shutter_reads(h, item):
    """What Shutter's set and Engine Resend's check read of one header: rule 3's answer, the interruption read, where the set
    places it and why, and the recheck's verdict."""
    code = (f'Set h={h}\nSet a=##class(Shutter.Util.ResendSet).AttemptsOf("{NS}",h)\n'
            f'Set c=##class(Shutter.Util.EngineRead).Interrupted("{NS}",h)\n'
            f'Set hd=##class(Shutter.Operation.EngineResend).Header("{NS}",h) Set row=##class(Shutter.Util.ResendSet).Row("{NS}",hd)\n'
            f'Set p=##class(Shutter.Util.ResendSet).Place("{NS}",hd,row)\n'
            f'Set r=##class(Shutter.Operation.EngineResend).Recheck("{NS}","{item[0]}",h,"{item[0]}","")\n'
            'Set out={"attempts":(a),"interrupted":(c),"place":(p),"reason":(row.reason),"recheck":(r.verdict),"recheckWhy":(r.why)}\n'
            'Write !,"<<<",out.%ToJSON(),">>>",!')
    out = session("SHUTTER", code)
    m = re.findall(r"<<<(.*?)>>>", out, re.S)
    if not m:
        raise RigBroken(f"Shutter's reads of header {h} failed: {out[-800:]}")
    return json.loads(m[-1])


def error_rows(h):
    out = session(NS, f'Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT l.Text FROM Ens_Util.Log l, Ens.MessageHeader h WHERE h.ID = ? AND l.SessionId = h.SessionId AND l.MessageId = ? AND l.Type IN (2, 6) ORDER BY l.ID",{h},{h}) While rs.%Next() {{ Write !,"<<<",rs.Text,">>>" }}')
    return re.findall(r"<<<(.*?)>>>", out, re.S)


def settle(h, seconds=120):
    return wait_for(f"header {h} to end Error", lambda: status(h) == "Error", seconds, 3)


def setup(args, root):
    step(f"A stock instance ({args.image}), Shutter in SHUTTER, and a production with two stock HL7 TCP operations in {NS}")
    docker("rm", "-f", CTR, check=False)
    docker("run", "-d", "--name", CTR, "-p", f"127.0.0.1:{args.port}:52773", args.image, "--check-caps", "false", "--ISCAgent", "false")
    wait_up()
    time.sleep(5)
    tar = subprocess.Popen(["tar", "-C", root, "-cf", "-", "--exclude=.git", "--exclude=node_modules", "--exclude=web", "."], stdout=subprocess.PIPE)
    subprocess.run(["docker", "exec", "-i", "-u", "root", CTR, "sh", "-c", f"mkdir -p {HOME}/pkg && tar -xf - -C {HOME}/pkg && chown -R irisowner:irisowner {HOME}/pkg"], stdin=tar.stdout, check=True)
    docker("cp", os.path.join(root, "vendor/ipm/zpm-0.10.10.xml"), f"{CTR}:/tmp/zpm.xml")
    out = session("USER", f'Set sc=$SYSTEM.OBJ.Load("{HOME}/pkg/src/Shutter/Setup.cls","ck") Write !,"[ns] ",##class(Shutter.Setup).CreateNamespace("SHUTTER"),"|",!')
    if "ok|" not in out:
        raise RigBroken("Setup.cls did not reach CreateNamespace: " + out[-500:])
    target = f"{HOME}/pkg/{args.module}" if args.module else f"{HOME}/pkg"
    out = session("SHUTTER", f'Set sc=$SYSTEM.OBJ.Load("/tmp/zpm.xml","ck")\nSet sc=##class(%IPM.Main).Shell("load {target} -Ddemo=0") Write !,"RESULT: ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!', 900)
    if "RESULT: ok" not in out:
        raise RigBroken("the load failed: " + out[-800:])
    if value("SHUTTER", f'##class(Shutter.Setup).CreateNamespace("{NS}")') != "ok":
        raise RigBroken(f"{NS} was not created")
    for name, text in (("Probe.Production", PRODUCTION), ("Probe.Util", UTIL)):
        subprocess.run(["docker", "exec", "-i", CTR, "sh", "-c", f"cat > /tmp/{name}.cls"], input=text, text=True, check=True)
        if value(NS, f'$SYSTEM.OBJ.Load("/tmp/{name}.cls","ck-d")') != "1":
            raise RigBroken(f"{name} did not compile")
    subprocess.run(["docker", "exec", "-i", CTR, "sh", "-c", "cat > /tmp/listener.py"], input=LISTENER, text=True, check=True)
    start()


def start():
    out = session(NS, 'Set sc=##class(Ens.Director).StartProduction("Probe.Production") Write !,"[start] ",$SELECT(sc:"ok",1:$SYSTEM.Status.GetErrorText(sc)),!')
    if "[start] ok" not in out:
        raise RigBroken("the production did not start: " + out[-500:])


def case_a(tag):
    step("A: a clean outage, two messages, the listener down throughout")
    listener(LONG, False)
    ids = [send(LONG, f"A{tag}{i}") for i in (1, 2)]
    for h in ids:
        settle(h)
    reads = [shutter_reads(h, LONG) for h in ids]
    rows = [error_rows(h) for h in ids]
    check("A.a  each message has its own Error rows, all a connection that never opened, and nothing was heard",
          all(r and all("ErrOutConnectExpired" in t for t in r) for r in rows) and heard(LONG) == [], (rows, heard(LONG)))
    check("A.b  Shutter reads both as never opened and not interrupted, and the set offers both (candidate), as Engine Resend's check does (go)",
          all(r["attempts"] == "never_opened" and r["interrupted"]["answer"] == "no" and r["place"] == "candidate" and r["recheck"] == "go" for r in reads), reads)


def case_b(tag):
    step("B: in one job, never opened, then a frame taken with no reply (read timeout), then never opened")
    listener(SHORT, False)
    ctl = f"B{tag}"
    h = send(SHORT, ctl)
    wait_for("a first attempt that never opened", lambda: any("ErrOutConnectExpired" in t for t in error_rows(h)), 30)
    listener(SHORT, True)
    wait_for(f"the listener to hear {ctl}", lambda: ctl in heard(SHORT), 30, 1)
    wait_for("the read timeout's row", lambda: len(error_rows(h)) >= 2, 30)
    listener(SHORT, False)
    settle(h)
    rows, r = error_rows(h), shutter_reads(h, SHORT)
    # The engine tries it again after the read timeout, so the listener can hear it more than once before it goes down.
    check("B.a  the receiver heard it, and the log holds a row for each change of words: never opened, the read timeout, never opened again",
          heard(SHORT) and set(heard(SHORT)) == {ctl} and len(rows) >= 3 and "ErrOutConnectExpired" in rows[0] and any("ErrOutConnectExpired" not in t and "ErrFailureTimeout" not in t for t in rows), (heard(SHORT), rows))
    check("B.b  Shutter reads it as reached, and the set does not offer it", r["attempts"] == "reached_receiver" and r["place"] == "reached" and r["recheck"] == "stop", r)


def cut_off(tag, letter, how):
    listener(LONG, False)
    ctl = f"{letter}{tag}"
    h = send(LONG, ctl)
    wait_for("a first attempt that never opened", lambda: error_rows(h), 30)
    listener(LONG, True)
    wait_for(f"the listener to hear {ctl}", lambda: ctl in heard(LONG), 30, 1)
    time.sleep(2)
    if status(h) != "Delivered":
        raise RigBroken(f"header {h} read {status(h)} while the engine waited for the reply")
    # The listener stays up through the stop: closing it first would end the read with a lost connection, which the engine
    # logs (a row that reads reached), and the case would not be the one on trial.
    how()
    settle(h, 180)
    return ctl, h


def judged(letter, ctl, h, by):
    rows, r = error_rows(h), shutter_reads(h, LONG)
    check(f"{letter}.a  the receiver holds the frame, and every Error row the engine kept says the connection never opened: the attempt that reached it left none",
          ctl in heard(LONG) and rows and all("ErrOutConnectExpired" in t for t in rows), (heard(LONG), rows))
    check(f"{letter}.b  so rule 3 alone reads it as never opened (what the set would offer without the interruption rule)", r["attempts"] == "never_opened", r)
    check(f"{letter}.c  the interruption read finds {by} after the header was created", r["interrupted"]["answer"] == "yes" and r["interrupted"]["by"] in by.split(" or "), r["interrupted"])
    check(f"{letter}.d  the set refuses it as interrupted, and Engine Resend's check before a send stops on it",
          r["place"] == "refused" and "stop or a crash" in r["reason"] and r["recheck"] == "stop", r)


def case_c(tag):
    step("C: a forced production stop while the engine waits for the receiver's reply, then attempts that never open")

    def forced():
        out = session(NS, 'Set sc=##class(Ens.Director).StopProduction(1,1) Write !,"[stop] ",sc,!')
        if "[stop] 1" not in out:
            raise RigBroken("the forced stop failed: " + out[-400:])
        listener(LONG, False)
        start()
    ctl, h = cut_off(tag, "C", forced)
    judged("C", ctl, h, "Ens.Job:RecoverActiveMessage or Ens.Director:StartProduction")


def case_d(tag):
    step("D: the instance killed while the engine waits for the reply (a crash), recovered and started, then attempts that never open")

    def crash():
        docker("kill", CTR)
        docker("start", CTR)
        listener(LONG, False)
        wait_up()
        time.sleep(5)
        out = session(NS, 'Set sc=##class(Ens.Director).RecoverProduction() Write !,"[recover] ",sc,!')
        if "[recover] 1" not in out:
            raise RigBroken("the recovery failed: " + out[-400:])
        start()
    ctl, h = cut_off(tag, "D", crash)
    judged("D", ctl, h, "Ens.Job:RecoverActiveMessage or Ens.Director:StartProduction")


def case_e(tag):
    step("E: a stock purge of the event log")
    listener(LONG, False)
    h = send(LONG, f"E{tag}")
    settle(h)
    out = session(NS, 'Set sc=##class(Ens.Util.Log).Purge(.n,0) Write !,"[purge] ",sc," ",n,!')
    if "[purge] 1" not in out:
        raise RigBroken("the purge failed: " + out[-400:])
    r = shutter_reads(h, LONG)
    check("E.a  a header whose rows the purge took is not offered", r["place"] == "refused" and r["recheck"] == "stop", r)


def main():
    global CTR
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--image", default="irishealth-community:2026.3.0AI.154.0")
    ap.add_argument("--port", type=int, default=52797)
    ap.add_argument("--ctr", default=CTR)
    ap.add_argument("--module", default="")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    args = ap.parse_args()
    CTR = args.ctr
    tag = time.strftime("%H%M%S")
    try:
        setup(args, args.repo)
        for case in (case_a, case_b, case_c, case_d, case_e):
            case(tag)
    except RigBroken as e:
        print(f"\nRIG BROKEN: {e}", flush=True)
        return 3
    finally:
        if not args.keep:
            docker("rm", "-f", CTR, check=False)
    step("Results")
    print(f"{len(FAILED)} failed" + (": " + ", ".join(FAILED) if FAILED else ""), flush=True)
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
