#!/usr/bin/env python3
"""The rig's own rules with no instance and no Docker: each listener mode over this machine's loopback, the verdict on a stop and
start, and a licence refusal. Run anywhere: python3 tests/e2e/v11_rig/test_rig.py. Exit status 1 when one fails."""
import json
import os
import socket
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rig as rigmod  # noqa: E402

failed = []


def check(name, ok, detail=""):
    print(("  ok    " if ok else "  FAIL  ") + name + ("" if ok else f"\n        {detail}"), flush=True)
    if not ok:
        failed.append(name)


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class Local:
    """A listener and the probe, as the rig runs them in the container, here."""

    def __init__(self, workdir, spec):
        self.workdir, self.port = workdir, free_port()
        with open(os.path.join(workdir, f"mode-{self.port}"), "w") as f:
            json.dump(spec, f)
        self.proc = subprocess.Popen([sys.executable, os.path.join(HERE, "listener.py"), str(self.port), workdir, "60"])
        for _ in range(50):
            with open("/proc/net/tcp") as f:
                if rigmod.listening_in(f.read(), self.port):
                    return
            time.sleep(0.1)
        raise RuntimeError("the listener did not start")

    def probe(self, data, wait=1.5):
        path = os.path.join(self.workdir, "m.hl7")
        with open(path, "wb") as f:
            f.write(data)
        return probe(self.port, path, wait)

    def spec(self, spec):
        with open(os.path.join(self.workdir, f"mode-{self.port}"), "w") as f:
            json.dump(spec, f)

    def events(self):
        with open(os.path.join(self.workdir, f"rx-{self.port}.jsonl")) as f:
            return [json.loads(x) for x in f if x.strip()]

    def frames(self):
        return [e for e in self.events() if e["event"] == "frame"]

    def stop(self):
        open(os.path.join(self.workdir, f"stop-{self.port}"), "w").close()
        self.proc.wait(timeout=10)


def probe(port, path="-", wait=1.5):
    return subprocess.run([sys.executable, os.path.join(HERE, "probe.py"), str(port), path, str(wait)], capture_output=True, text=True, timeout=30).stdout.strip()


def message(control, extra=b""):
    return f"MSH|^~\\&|A|H|B|H|20261106000000||ADT^A01|{control}|P|2.5.1\rPID|1||X1^^^HOSP^MR||SYNTH^T".encode() + extra + b"\r"


def listener_modes(workdir):
    port = free_port()
    check("down: nothing listening refuses the connect", probe(port) == "REFUSED", probe(port))

    r = Local(workdir, {"mode": "up"})
    got = r.probe(message("C1"))
    check("up answers AA", got.startswith("MSA|AA|C1"), got)
    r.spec({"mode": "answer", "code": "AE", "words": "Test code not recognised", "err": ["ERR|||204|E"]})
    got = r.probe(message("C2"))
    check("AE carries the chosen words and ERR, with no reconnect or restart", got == "MSA|AE|C2|Test code not recognised ERR|||204|E", got)
    r.spec({"mode": "answer", "code": "AR", "words": "Patient not found"})
    got = r.probe(message("C3"))
    check("AR carries the chosen words", got == "MSA|AR|C3|Patient not found", got)
    r.spec({"mode": "answer", "by_control": {"C5": {"code": "AE", "words": "That one"}}})
    got = r.probe(message("C4")), r.probe(message("C5"))
    check("by_control answers that message, and AA to the rest", got[0].startswith("MSA|AA|C4") and got[1] == "MSA|AE|C5|That one", got)
    r.spec({"mode": "answer", "nonascii": {"words": "Invalid character"}})
    got = r.probe(message("C6")), r.probe(message("C7", b"\xe8"))
    check("nonascii refuses a byte above 0x7F only", got[0].startswith("MSA|AA|C6") and got[1] == "MSA|AE|C7|Invalid character", got)
    r.spec({"mode": "hang"})
    got = r.probe(message("C8"))
    last = r.frames()[-1]
    check("hang accepts, reads and never answers", got == "TIMEOUT" and last["ctl"] == "C8" and last["answer"] == "NONE", (got, last))
    r.spec({"mode": "log_hex"})
    data = message("C9", b"\xe8")
    got = r.probe(data)
    last = r.frames()[-1]
    check("log_hex answers AA and writes the frame's bytes", got.startswith("MSA|AA|C9") and bytes.fromhex(last["hex"]) == data and last["high"] == "e8", (got, last))
    r.spec({"mode": "up"})
    r.probe(message("C9"))
    check("the next frame carries no hex, and counts a second copy", "hex" not in r.frames()[-1] and r.frames()[-1]["copy"] == 2, r.frames()[-1])
    check("a connection that sends nothing is logged as one and hears no frame", probe(r.port) == "CONNECTED", "")
    r.stop()
    check("a stopped listener refuses", probe(r.port) == "REFUSED", probe(r.port))
    n = len(r.events())
    r2 = Local.__new__(Local)
    r2.workdir, r2.port = workdir, r.port
    r2.proc = subprocess.Popen([sys.executable, os.path.join(HERE, "listener.py"), str(r.port), workdir, "60"])
    time.sleep(0.6)
    r2.probe(message("C1"))
    check("what it heard is kept across a restart, and copies go on counting", len(r2.events()) > n and r2.frames()[-1]["copy"] == 2, r2.frames()[-1])
    r2.stop()

    r = Local(workdir, {"mode": "take_and_die"})
    got = r.probe(message("D1"))
    r.proc.wait(timeout=5)
    check("take_and_die reads the frame and closes with no answer", got == "CLOSED" and r.frames()[-1]["ctl"] == "D1" and r.frames()[-1]["answer"] == "NONE", (got, r.events()))
    check("and the port then refuses", probe(r.port) == "REFUSED", "")

    r = Local(workdir, {"mode": "take_and_die", "after": 2})
    got = r.probe(message("D2")), r.probe(message("D3"))
    r.proc.wait(timeout=5)
    check("after 2 answers the first and dies on the second", got[0].startswith("MSA|AA|D2") and got[1] == "CLOSED", got)

    r = Local(workdir, {"mode": "noaccept"})
    # The kernel completes a connect into the backlog though nothing accepts: the frame goes nowhere, no answer comes.
    got = r.probe(message("N1"), 1)
    check("noaccept listens, takes no frame and never answers", got == "TIMEOUT" and not os.path.getsize(os.path.join(workdir, f"rx-{r.port}.jsonl")), got)
    r.stop()


def restart_rules():
    check("a new job is a restart", rigmod.restart_verdict({"Gate": "101"}, {"Gate": "202"}, "Gate") == "")
    why = rigmod.restart_verdict({"Gate": "101"}, {"Gate": "101"}, "Gate")
    check("the same job is reported as not having happened", "did not happen" in why, why)
    check("no job before is no proof", rigmod.restart_verdict({}, {"Gate": "202"}, "Gate") != "")
    check("no job after is no proof", rigmod.restart_verdict({"Gate": "101"}, {}, "Gate") != "")

    r = rigmod.Rig("stub")
    jobs = iter([{"Gate": "7"}, {"Gate": "7"}])
    r.jobs = lambda ns: next(jobs)
    calls = []
    r.asked_until_done = lambda ns, call, word: calls.append(word)
    try:
        r.restart_production("SHUTTER", "P", "Gate")
        check("a start that left the same job raises", False, "no exception")
    except rigmod.RestartNotProven as e:
        check("a start that left the same job raises", "did not happen" in str(e) and calls == ["stop", "start"], (str(e), calls))

    class Done:
        def __init__(self, code, out):
            self.returncode, self.stdout, self.stderr = code, out, ""

    wait, poll = rigmod.LICENCE_WAIT, rigmod.LICENCE_POLL
    rigmod.LICENCE_WAIT, rigmod.LICENCE_POLL = 0.2, 0.01
    try:
        answers = iter([Done(133, ""), Done(0, "<LICENSE LIMIT EXCEEDED>"), Done(0, "<<<7>>>")])
        r = rigmod.Rig("stub")
        r.run_session = lambda ns, code, timeout: next(answers)
        check("a licence refusal is waited out", r.value("USER", "7") == "7")
        r.run_session = lambda ns, code, timeout: Done(133, "")
        try:
            r.session("USER", "Write 1")
            check("a licence refusal that lasts is a broken rig, not an empty answer", False, "no exception")
        except rigmod.RigBroken:
            check("a licence refusal that lasts is a broken rig, not an empty answer", True)
    finally:
        rigmod.LICENCE_WAIT, rigmod.LICENCE_POLL = wait, poll

    rigmod_pause = rigmod.RESTART_TRIES, rigmod.RESTART_PAUSE
    rigmod.RESTART_TRIES, rigmod.RESTART_PAUSE = 2, 0
    try:
        r = rigmod.Rig("stub")
        r.session = lambda ns, code, timeout=400: "[stop] ERROR something"
        try:
            r.asked_until_done("S", "StopProduction(60,1)", "stop")
            check("a stop that never says ok raises", False, "no exception")
        except rigmod.RestartNotProven:
            check("a stop that never says ok raises", True)
    finally:
        rigmod.RESTART_TRIES, rigmod.RESTART_PAUSE = rigmod_pause

    try:
        rigmod.Rig("")
        check("a container must be named", False, "no exception")
    except rigmod.RigBroken:
        check("a container must be named", True)

    tcp = "  sl  local_address rem_address   st\n   0: 0100007F:1E15 00000000:0000 0A\n   1: 0100007F:1E16 00000000:0000 01\n"
    check("/proc/net/tcp: a listening socket reads listening", rigmod.listening_in(tcp, 0x1E15))
    check("/proc/net/tcp: an established one does not", not rigmod.listening_in(tcp, 0x1E16))


def main():
    with tempfile.TemporaryDirectory() as workdir:
        listener_modes(workdir)
    restart_rules()
    print(f"\n{'FAILED: ' + ', '.join(failed) if failed else 'All passed'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
