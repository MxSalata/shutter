#!/usr/bin/env python3
"""A storm at scale: many failures to one receiver, through the intake route, judged from outside the code under test.

    python3 tests/e2e/storm_scale_check.py --size S|M|L --ctr NAME --url http://127.0.0.1:PORT --out DIR
    python3 tests/e2e/storm_scale_check.py --size S --ctr NAME --boot --image IMAGE --port PORT --out DIR
    python3 tests/e2e/storm_scale_check.py --size S --plan-only
    python3 tests/e2e/storm_scale_check.py --control 8 --ctr NAME --boot --image IMAGE --port PORT --out DIR

Sizes: S 40 cases, M 200, L 1,000; half the patients' count in chains of two (an admission, then a transfer). One post at
a time as the forwarder, with source.namespace set and no mode, so a watched production's default (policy) decides. L
does not run its whole release: it stops at the 50th resolved item, or 20 minutes after the approval, and the whole
release is stated as an extrapolation from those items.

--boot makes a fresh instance first, the way CI does (`docker rm -f` of NAME, which must be this run's own). The instance
needs the demo users, the demo receiver and Docker on the machine this runs on: run it beside the container. --board
(an AI Hub build with tests/mock enabled, S only) posts the same cases with mode board and judges the boards convened.

It writes to DIR as it goes: posts.jsonl (each post's send and reply time), calls.jsonl (every other call's status),
samples.jsonl (case states and incident state), memory.jsonl (docker stats and the machine's free memory) and, at each
phase and at the end, result.json and result.md. Exit status: 0 the size passed, 1 it failed, 2 the run is invalid.

The licence is 8 units and a call with no cookie takes one, so the REST calls go through one signed-in session per role
and the SQL through one Atelier cookie, at most one statement a minute until the release's measurements start. The
receiver's own API takes no session, so its reads come last, paced, after the licence has been read.

The receiver runs in the same instance on loopback, so it shares CPU, memory and licence with Shutter: the times are
conservative for a site with a separate receiver. Standard library only.
"""
import argparse
import base64
import contextlib
import datetime as dt
import http.cookiejar
import io
import json
import os
import re
import socket
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import eventlog_check  # noqa: E402
import lineage_check  # noqa: E402
from scenario_check import Session  # noqa: E402

SIZES = {
    "S": {"cases": 40, "approval_limit": 300, "release_limit": 600, "give_up": 1200, "stop_at": None},
    "M": {"cases": 200, "approval_limit": 300, "release_limit": 3000, "give_up": 4500, "stop_at": None},
    "L": {"cases": 1000, "approval_limit": 600, "release_limit": None, "give_up": 1200, "stop_at": 50},
}
RECEIVER = "Downstream Out"
NOT_YET_DECIDED = {"detected", "collecting", "investigating"}
CLOSED = {"resolved", "blocked", "escalated", "failed"}
PASSWORD = os.environ.get("SHUTTER_PASSWORD", "shutter")
ADMIN = (os.environ.get("IRIS_USER", "_SYSTEM"), os.environ.get("IRIS_PASSWORD", "SYS"))


def utc_now():
    return dt.datetime.now(dt.timezone.utc)


def stamp(moment=None):
    return (moment or utc_now()).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def parse_at(text):
    """A store's or the harness's UTC timestamp as a datetime, or None."""
    if not text:
        return None
    m = re.match(r"(\d{4}-\d\d-\d\d)[T ](\d\d:\d\d:\d\d)(\.\d+)?", str(text))
    if not m:
        return None
    moment = dt.datetime.strptime(m.group(1) + " " + m.group(2), "%Y-%m-%d %H:%M:%S").replace(tzinfo=dt.timezone.utc)
    return moment + dt.timedelta(seconds=float(m.group(3) or 0))


def seconds_between(a, b):
    a, b = parse_at(a), parse_at(b)
    return round((b - a).total_seconds(), 1) if a and b else None


# ---- The storm


def storm_plan(cases, base, order="admits-first"):
    """The messages, in posting order: per patient an A01 then an A02 from the S2 fixtures, with a unique patient,
    visit number, control id and bed, event times two seconds apart in posting order, all of them in the past."""
    with open(os.path.join(REPO, "fixtures", "S2", "S2-01-A01.hl7"), newline="") as f:
        admit = f.read()
    with open(os.path.join(REPO, "fixtures", "S2", "S2-02-A02.hl7"), newline="") as f:
        transfer = f.read()
    count = cases // 2
    if order == "interleaved":
        sequence = [(p, kind) for p in range(1, count + 1) for kind in ("admit", "transfer")]
    else:
        sequence = [(p, "admit") for p in range(1, count + 1)] + [(p, "transfer") for p in range(1, count + 1)]
    when = {}
    for i, step in enumerate(sequence):
        when[step] = (base + dt.timedelta(seconds=2 * i)).strftime("%Y%m%d%H%M%S")
    out = []
    for i, (p, kind) in enumerate(sequence, 1):
        ids = (("MRN1002", f"MRN7{p:06d}"), ("9991002006", f"999{p:07d}"), ("ENC-1002", f"ENC-7{p:06d}"))
        admitted = when[(p, "admit")]
        bay, bed = p // 30 + 1, p % 30 + 1
        if kind == "admit":
            text = admit.replace("MSG00201", f"STORM{i:05d}").replace("WARD-A^BAY1^01^HOSP", f"WARD-A^A{bay}^{bed:02d}^HOSP")
            text = text.replace("20261015090000", admitted)
        else:
            text = transfer.replace("MSG00202", f"STORM{i:05d}").replace("WARD-B^BAY2^04^HOSP", f"WARD-B^B{bay}^{bed:02d}^HOSP")
            text = text.replace("WARD-A^BAY1^01^HOSP", f"WARD-A^A{bay}^{bed:02d}^HOSP")
            text = text.replace("20261015092000", when[(p, kind)]).replace("20261015090000", admitted)
        for old, new in ids:
            text = text.replace(old, new)
        out.append({"index": i, "patient": p, "event": kind, "encounter": f"ENC-7{p:06d}", "text": text})
    return out


def intake_body(step, board):
    body = {
        "source": {"namespace": "HOSPITAL", "production": "Hospital.Production", "route": "PAS to Downstream",
                   "header_id": str(100000 + step["index"])},
        "receiver": RECEIVER,
        "failure": {"kind": "delivery_failed", "text": "HTTP 503 from the receiver: not accepted", "outcome": "unavailable",
                    "http_status": 503, "reason_code": ""},
        "message": step["text"],
        "schema_category": "2.5.1",
    }
    if board:
        body["mode"] = "board"
    return body


def check_plan(plan, cases):
    """The generator's own promises, checked before anything is sent."""
    problems = []
    if len(plan) != cases:
        problems.append(f"{len(plan)} messages for {cases} cases")
    for field, pattern in (("control id", r"\|(STORM\d+)\|P\|"), ("encounter", r"\|(ENC-7\d+)\|"), ("patient", r"\|(MRN7\d+)\^")):
        seen = [m.group(1) for step in plan for m in [re.search(pattern, step["text"])] if m]
        if len(seen) != cases:
            problems.append(f"{field} found in {len(seen)} of {cases} messages")
    controls = [re.search(r"\|(STORM\d+)\|P\|", step["text"]).group(1) for step in plan]
    if len(set(controls)) != cases:
        problems.append("a control id is used twice")
    if any("MRN1002" in step["text"] or "ENC-1002" in step["text"] or "MSG002" in step["text"] for step in plan):
        problems.append("a template's identifier survived")
    beds = {}
    for step in plan:
        pv1 = next(s for s in step["text"].split("\r") if s.startswith("PV1"))
        beds.setdefault(pv1.split("|")[3], set()).add(step["encounter"])
    if any(len(holders) > 1 for holders in beds.values()):
        problems.append("two patients share a bed")
    for step in plan:
        if not step["text"].startswith("MSH") or "\r" not in step["text"]:
            problems.append("a message is not carriage-return separated HL7")
            break
    return problems


# ---- Reaching the instance


class Log:
    """The run's files, each line stamped."""

    def __init__(self, folder):
        os.makedirs(folder, exist_ok=True)
        self.folder = folder
        self.lock = threading.Lock()

    def line(self, name, **fields):
        fields.setdefault("at", stamp())
        with self.lock, open(os.path.join(self.folder, name), "a") as f:
            f.write(json.dumps(fields) + "\n")


class Role:
    """One signed-in user's REST session: one cookie, a new sign-in only when the session has expired."""

    def __init__(self, url, user, log):
        self.url, self.user, self.log = url, user, log
        self.signins = 0
        self.session = None
        self.sign_in()

    def sign_in(self):
        self.session = Session(self.url).sign_in(self.user, PASSWORD)
        self.signins += 1
        self.signed_in = time.monotonic()
        self.log.line("calls.jsonl", role=self.user, method="POST", path="/session", status=200)

    def call(self, method, path, body=None, idempotent=False):
        """(status, parsed body, seconds, bytes). Status 0: no answer at all."""
        for attempt in (1, 2):
            started = time.monotonic()
            status, parsed, size = self._send(method, path, body, idempotent)
            took = round(time.monotonic() - started, 2)
            self.log.line("calls.jsonl", role=self.user, method=method, path=path, status=status, seconds=took, bytes=size)
            if status == 401 and attempt == 1:
                self.sign_in()
                continue
            return status, parsed, took, size
        return status, parsed, took, size

    def _send(self, method, path, body, idempotent):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.session.base + path, data=data, method=method)
        request.add_header("Accept", "application/json")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        if method != "GET":
            request.add_header("X-Requested-With", "Shutter")
        if idempotent:
            request.add_header("Idempotency-Key", os.urandom(16).hex())
        try:
            with self.session.opener.open(request, timeout=300) as response:
                raw = response.read()
                status = response.status
        except urllib.error.HTTPError as error:
            raw = error.read()
            status = error.code
        except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as error:
            return 0, {"unreachable": str(error)[:200]}, 0
        try:
            return status, (json.loads(raw.decode()) if raw else None), len(raw)
        except (ValueError, UnicodeDecodeError):
            return status, {"unparsed": raw[:200].decode(errors="replace")}, len(raw)

    def sign_out(self):
        self.call("DELETE", "/session")


class Sql:
    """SQL through the Atelier API with one cookie, so it holds one licence unit. While `rationed` is set, statements
    are at least 60 s apart."""

    def __init__(self, url, log):
        self.url = url.rstrip("/")
        self.log = log
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        self.rationed = False
        self.last = 0.0
        self.count = 0

    def query(self, _url, ns, statement, params=()):
        if self.rationed and time.monotonic() - self.last < 60:
            time.sleep(60 - (time.monotonic() - self.last))
        self.last = time.monotonic()
        self.count += 1
        token = base64.b64encode(f"{ADMIN[0]}:{ADMIN[1]}".encode()).decode()
        body = json.dumps({"query": statement, "parameters": list(params)}).encode()
        request = urllib.request.Request(f"{self.url}/api/atelier/v1/{ns}/action/query", data=body, method="POST",
                                         headers={"Authorization": "Basic " + token, "Content-Type": "application/json"})
        last = None
        for attempt in range(6):
            try:
                with self.opener.open(request, timeout=300) as response:
                    raw = response.read().decode(errors="replace")
                break
            except urllib.error.HTTPError as error:
                last = f"HTTP {error.code}"
                self.log.line("calls.jsonl", role="sql", method="POST", path="query", status=error.code)
                if error.code not in (500, 503):
                    raise RuntimeError(f"SQL refused: {last}") from error
                time.sleep(15)
        else:
            raise RuntimeError(f"SQL refused after retries: {last}")
        start = raw.rfind('{"status":')
        result = json.loads(raw[start:] if start > 0 else raw)
        errors = result.get("status", {}).get("errors", [])
        if errors:
            raise RuntimeError("SQL error: " + "; ".join(e.get("error", str(e)) for e in errors))
        return result.get("result", {}).get("content", [])

    def one(self, ns, statement, params=()):
        rows = self.query(None, ns, statement, params)
        return rows[0] if rows else {}


def docker(*args, stdin=None, timeout=300):
    done = subprocess.run(["docker", *args], input=stdin, capture_output=True, text=True, timeout=timeout)
    return done.returncode, done.stdout, done.stderr


def iris_session(ctr, ns, code):
    """Runs ObjectScript in a terminal session and returns its output; a licence refusal (exit 133) is tried again."""
    for attempt in range(8):
        rc, out, err = docker("exec", "-i", ctr, "iris", "session", "IRIS", "-U", ns, stdin=code + "\nHalt\n")
        if rc != 133 and "LICENSE LIMIT" not in (out + err).upper():
            return out
        time.sleep(15)
    raise RuntimeError(f"iris session refused by the licence, {attempt + 1} tries")


def between_marks(text):
    m = re.search(r"<<<(.*?)>>>", text, re.DOTALL)
    return m.group(1).strip() if m else ""


def board_nodes(ctr):
    """^Shutter.Board("convened", minute) as {minute: count}. Earlier minutes' nodes go when a later minute convenes."""
    code = ('Set k="" Write "<<<",! For { Set k=$ORDER(^Shutter.Board("convened",k)) Quit:k=""  '
            'Write k,"=",^Shutter.Board("convened",k),! } Write ">>>",!')
    nodes = {}
    for row in between_marks(iris_session(ctr, "SHUTTER", code)).split():
        if "=" in row:
            minute, count = row.split("=", 1)
            nodes[minute] = int(count or 0)
    return nodes


def boot(args, log):
    """A fresh instance, by CI's steps: every class is loaded before the production first starts, so no item holds old code."""
    print(f"booting {args.ctr} on {args.image}, port {args.port}", flush=True)
    docker("rm", "-f", args.ctr)
    rc, _, err = docker("run", "-d", "--name", args.ctr, "-p", f"127.0.0.1:{args.port}:52773", "-v",
                        f"{REPO}:/home/irisowner/dev:ro", args.image, "--check-caps", "false", "--ISCAgent", "false")
    if rc:
        raise RuntimeError("docker run failed: " + err[:400])
    for _ in range(90):
        rc, _, _ = docker("exec", args.ctr, "iris", "session", "IRIS", "-U", "%SYS",
                          '##class(Security.Users).UnExpireUserPasswords("*")')
        if rc == 0:
            break
        time.sleep(5)
    else:
        raise RuntimeError("IRIS took no command in 450 s")
    token = base64.b64encode(f"{ADMIN[0]}:{ADMIN[1]}".encode()).decode()
    for _ in range(60):
        try:
            request = urllib.request.Request(args.url + "/api/atelier/", headers={"Authorization": "Basic " + token})
            with urllib.request.urlopen(request, timeout=20) as response:
                if response.status == 200:
                    break
        except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError):
            pass
        time.sleep(5)
    else:
        raise RuntimeError("the Atelier API did not come up")

    def load(ns, *paths):
        done = subprocess.run([sys.executable, os.path.join(REPO, "scripts", "iris-load.py"), "--url", args.url, "--ns", ns, *paths],
                              capture_output=True, text=True, cwd=REPO, timeout=1500)
        if done.returncode:
            raise RuntimeError(f"loading into {ns} failed: " + done.stdout[-600:] + done.stderr[-300:])

    def terminal(ns, call):
        for _ in range(8):
            out = iris_session(args.ctr, ns, f'Set r = {call} Write !,"RESULT: ",r,!')
            if re.search(r"^RESULT: ok", out, re.MULTILINE):
                return
            if "LICENSE" not in out.upper():
                break
            time.sleep(15)
        raise RuntimeError(f"{call} did not answer ok: " + out[-800:])

    load("USER", "src/Shutter/Setup.cls")
    terminal("USER", '##class(Shutter.Setup).CreateNamespace("SHUTTER")')
    sources = subprocess.run([sys.executable, os.path.join(REPO, "scripts", "module-sources.py"), "core/module.xml"],
                             capture_output=True, text=True, cwd=REPO, check=True).stdout.split()
    load("SHUTTER", *sources)
    terminal("SHUTTER", '##class(Shutter.Setup).Install("/home/irisowner/dev/")')
    terminal("SHUTTER", '##class(Shutter.Installer).RunHospital("SHUTTER")')
    terminal("HOSPITAL", '##class(Hospital.Setup).Install("SHUTTER")')
    terminal("SHUTTER", '##class(Shutter.Installer).RunRecords("SHUTTER")')
    wait_healthy(args.url)
    log.line("calls.jsonl", role="boot", method="-", path="instance ready", status=200)


def wait_healthy(url, timeout=420):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url.rstrip("/") + "/api/shutter/health", timeout=20) as response:
                body = json.loads(response.read().decode())
                if body.get("ok") is True:
                    return
                last = body
        except (urllib.error.URLError, ValueError, socket.timeout, TimeoutError, ConnectionError) as error:
            last = str(error)
        time.sleep(5)
    raise RuntimeError(f"the health route never said ok: {last}")


class Sampler(threading.Thread):
    """Instance memory every minute, and in board mode the boards convened every 20 s."""

    def __init__(self, ctr, log, board):
        super().__init__(daemon=True)
        self.ctr, self.log, self.board = ctr, log, board
        self.stop_now = threading.Event()
        self.convened = {}

    def memory(self, label=""):
        rc, out, _ = docker("stats", "--no-stream", "--format", "{{.MemUsage}}", self.ctr)
        fields = {"instance": out.strip() if rc == 0 else "unavailable", "label": label, "machine_available_mb": available_mb()}
        self.log.line("memory.jsonl", **fields)
        return fields

    def run(self):
        last_memory = 0.0
        while not self.stop_now.wait(20 if self.board else 60):
            if time.monotonic() - last_memory >= 59:
                last_memory = time.monotonic()
                self.memory()
            if self.board:
                try:
                    for minute, count in board_nodes(self.ctr).items():
                        self.convened[minute] = max(self.convened.get(minute, 0), count)
                except RuntimeError:
                    pass


def available_mb():
    try:
        with open("/proc/meminfo") as f:
            return int(re.search(r"MemAvailable:\s+(\d+)", f.read()).group(1)) // 1024
    except (OSError, AttributeError):
        return None


# ---- The judgement


class Result:
    def __init__(self, args, folder):
        self.folder = folder
        self.doc = {"size": args.size, "cases": SIZES[args.size]["cases"], "image": args.image, "container": args.ctr,
                    "mode": "board" if args.board else "policy", "order": args.order, "started": stamp(), "rules": [],
                    "invalid": [], "reported": {}, "verdict": "unfinished"}

    def rule(self, group, name, ok, detail=""):
        """group: never (one occurrence fails the size), count (a judged count) or surface (reported as failed, no effect)."""
        self.doc["rules"].append({"group": group, "name": name, "ok": bool(ok), "detail": str(detail)[:1500]})
        print(f"{'ok  ' if ok else 'FAIL'} [{group}] {name}: {str(detail)[:300]}", flush=True)
        self.save()

    def invalid(self, reason):
        self.doc["invalid"].append(reason)
        print("INVALID " + reason, flush=True)
        self.save()

    def report(self, name, value):
        self.doc["reported"][name] = value
        print(f"reported {name}: {str(value)[:300]}", flush=True)
        self.save()

    def finish(self):
        failed = [r for r in self.doc["rules"] if not r["ok"] and r["group"] in ("never", "count")]
        self.doc["verdict"] = "INVALID" if self.doc["invalid"] else ("FAIL" if failed else "PASS")
        self.doc["finished"] = stamp()
        self.save()
        return {"PASS": 0, "FAIL": 1, "INVALID": 2}[self.doc["verdict"]]

    def save(self):
        with open(os.path.join(self.folder, "result.json"), "w") as f:
            json.dump(self.doc, f, indent=1)
        lines = [f"# Storm, size {self.doc['size']} ({self.doc['cases']} cases, {self.doc['mode']})", "",
                 f"Verdict: **{self.doc['verdict']}**. Image {self.doc['image'] or 'not named'}, container {self.doc['container']}, "
                 f"{self.doc['started']} to {self.doc.get('finished', 'running')}. Posting order: {self.doc['order']}.", ""]
        if self.doc["invalid"]:
            lines += ["## Invalid, so not judged", ""] + [f"- {x}" for x in self.doc["invalid"]] + [""]
        lines += ["## Rules", "", "| Group | Rule | Held | Detail |", "| --- | --- | --- | --- |"]
        for r in self.doc["rules"]:
            detail = r["detail"].replace("|", "/").replace("\n", " ")
            lines.append(f"| {r['group']} | {r['name']} | {'yes' if r['ok'] else '**no**'} | {detail} |")
        lines += ["", "## Reported, no pass mark", ""]
        for name, value in self.doc["reported"].items():
            lines.append(f"- {name}: `{json.dumps(value)[:900]}`")
        with open(os.path.join(self.folder, "result.md"), "w") as f:
            f.write("\n".join(lines) + "\n")


def generate(args, plan, forwarder, result, log):
    """One post at a time. Returns ({case ids of the 202s}, first send, last 202)."""
    ids, last_reply, largest_gap = {}, None, 0.0
    first_send = None
    not_opened = 0
    for step in plan:
        sent = utc_now()
        first_send = first_send or sent
        status, body, took, _ = forwarder.call("POST", "/intake", intake_body(step, args.board))
        replied = utc_now()
        log.line("posts.jsonl", index=step["index"], event=step["event"], encounter=step["encounter"], sent=stamp(sent),
                 replied=stamp(replied), status=status, seconds=took, reply=body)
        if status == 202:
            ids[(body or {}).get("caseId")] = step
            if body.get("opened") is False:
                not_opened += 1
            if last_reply is not None:
                largest_gap = max(largest_gap, (replied - last_reply).total_seconds())
            last_reply = replied
        elif 400 <= status < 500:
            result.invalid(f"HTTP {status} to a post (message {step['index']}): {body}")
            break
        else:
            result.rule("never", "no 503 from the API while the storm is posted", False, f"HTTP {status} at message {step['index']}: {body}")
    result.report("generator", {"posted": len(plan), "accepted": len(ids), "opened_false": not_opened,
                                "largest_gap_s": round(largest_gap, 2), "first_send": stamp(first_send),
                                "last_202": stamp(last_reply) if last_reply else None,
                                "post_seconds_per_case": round(((last_reply - first_send).total_seconds() / max(1, len(ids))), 3) if last_reply else None})
    if largest_gap > 30:
        result.invalid(f"a gap of {largest_gap:.1f} s between 202s (over 30 s)")
    return ids, first_send, last_reply, largest_gap


def incidents_of(operator):
    status, body, _, _ = operator.call("GET", "/incidents?limit=20")
    return [i for i in (body or {}).get("items", []) if i.get("receiver") == RECEIVER] if status == 200 else None


def state_counts(operator, states):
    counts = {}
    for state in states:
        status, body, _, _ = operator.call("GET", f"/cases?state={state}&limit=1")
        counts[state] = (body or {}).get("total") if status == 200 else None
    return counts


def main_incident(found):
    """The incident this storm opened, the largest if there are several."""
    return max(found, key=lambda i: (i.get("progress") or {}).get("cases") or 0) if found else None


def wait_for_approval(operator, size, last_202, log):
    """Polls until the approval task is raised, the incident closes or the time is up, sampling the evidence backlog."""
    limit = size["approval_limit"] + 300
    deadline = time.monotonic() + limit
    samples, incident = [], None
    while time.monotonic() < deadline:
        found = incidents_of(operator) or []
        incident = main_incident(found)
        counts = state_counts(operator, sorted(NOT_YET_DECIDED))
        sample = {"at": stamp(), "backlog": counts, "incidents": len(found), "state": (incident or {}).get("state"),
                  "progress": (incident or {}).get("progress")}
        samples.append(sample)
        log.line("samples.jsonl", **sample)
        if incident and incident.get("state") in ("awaiting_approval", "releasing", "closed"):
            return incident, samples
        time.sleep(5)
    return incident, samples


def approve(args, operator, incident, result, log):
    """Signs the approver in, reads the plan's digest now and approves. Returns the approval's time, or None."""
    iid = incident["incidentId"]
    path = "/incidents/" + urllib.parse.quote(iid)
    status, detail, took, size = operator.call("GET", path)
    surface_ok = status == 200 and took <= 60 and size > 0
    result.rule("surface", "GET /incidents/{id} after classification answers within 60 s", surface_ok, f"HTTP {status}, {took} s, {size} bytes")
    result.report("get_incident_after_classification", {"status": status, "seconds": took, "bytes": size})
    digest = None
    tasks = None
    if status == 200 and isinstance(detail, dict):
        digest = (detail.get("plan") or {}).get("digest")
        tasks = detail.get("tasks")
    if not digest:
        digest = incident.get("planDigest")
        result.report("digest_source", "the incident summary, as GET /incidents/{id} gave none")
    if tasks is not None:
        result.rule("count", "approval tasks raised: 1, shared", len(tasks) == 1, f"{len(tasks)} task(s)")
    else:
        result.rule("count", "approval tasks raised: 1, shared", False, "GET /incidents/{id} gave no tasks to count")
    approver = Role(args.url, "approver", log)
    status, reply, took, _ = approver.call("POST", path + "/approvals", {"planDigest": digest, "decision": "approve", "comment": "storm check"},
                                           idempotent=True)
    at = stamp()
    log.line("samples.jsonl", approval_status=status, approval_reply=reply, approval_seconds=took)
    if status in (401, 403, 409):
        result.invalid(f"the approval was refused: HTTP {status} {reply}")
        approver.sign_out()
        return None, detail
    result.rule("count", "approval accepted: 202, by the test approver", status == 202 and (reply or {}).get("approver") == "approver",
                f"HTTP {status} {reply}")
    approver.sign_out()
    return at if status == 202 else None, detail


def wait_for_release(operator, size, log):
    """Polls until the incident closes (S, M), the stop item (L) or the time is up. Returns why it stopped."""
    deadline = time.monotonic() + size["give_up"]
    while time.monotonic() < deadline:
        found = incidents_of(operator) or []
        incident = main_incident(found)
        counts = state_counts(operator, ["resolved", "blocked", "escalated", "failed"])
        sample = {"at": stamp(), "cases": counts, "state": (incident or {}).get("state"), "byState": ((incident or {}).get("progress") or {}).get("byState")}
        log.line("samples.jsonl", **sample)
        if size["stop_at"] and (counts.get("resolved") or 0) >= size["stop_at"]:
            return "stop item resolved"
        if incident and incident.get("state") == "closed":
            return "incident closed"
        time.sleep(15)
    return f"gave up after {size['give_up']} s"


def event_at(events, pattern):
    for e in events:
        if re.search(pattern, e.get("text") or ""):
            return e
    return None


def all_cases(operator):
    out, offset = {}, 0
    first_page = None
    while True:
        status, body, took, size = operator.call("GET", f"/cases?limit=500&offset={offset}")
        if status != 200:
            return None, first_page
        first_page = first_page or {"seconds": took, "bytes": size}
        items = body.get("items", [])
        for c in items:
            out[c["caseId"]] = c
        offset += 500
        if not items or offset >= (body.get("total") or 0):
            return out, first_page


def chain_items(chains):
    return [(chain, item) for chain in chains for item in chain.get("items") or []]


def read_encounters(url, plan, chains_before, chains_after, pace, log):
    """Every patient's encounter as the receiver holds it, through its own API, paced. These calls take no session, so
    they run after the licence has been read. (encounter, what was held, lower bound of events expected, and the upper
    bound from chains_after.)"""
    token = base64.b64encode(f"{ADMIN[0]}:{ADMIN[1]}".encode()).decode()
    done = {(c.get("encounterId")): sum(1 for i in c.get("items") or [] if i.get("state") == "resolved") for c in chains_before}
    begun = {(c.get("encounterId")): sum(1 for i in c.get("items") or [] if i.get("releasedAt")) for c in chains_after}
    out = []
    for encounter in sorted({step["encounter"] for step in plan}):
        request = urllib.request.Request(url.rstrip("/") + "/downstream/api/encounters/" + urllib.parse.quote(encounter, safe=""),
                                         headers={"Authorization": "Basic " + token})
        held = None
        for _ in range(8):
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    held = json.loads(response.read().decode())
                break
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    held = {"http_status": 404}
                    break
                log.line("calls.jsonl", role="receiver", method="GET", path=encounter, status=error.code)
                time.sleep(15)
        out.append((encounter, held, done.get(encounter, 0), begun.get(encounter, 0)))
        time.sleep(pace)
    return out


def judge_final_state(result, plan, reads, whole_release):
    wards = {step["encounter"]: re.search(r"PV1\|1\|I\|([^^]+)", step["text"]).group(1) for step in plan if step["event"] == "transfer"}
    wrong = []
    for encounter, held, low, high in reads:
        if held is None:
            wrong.append(f"{encounter}: no answer")
            continue
        events = held.get("history") or []
        count = len(events)
        if whole_release:
            low, high = 2, 2
        if not low <= count <= high:
            wrong.append(f"{encounter}: {count} events, expected {low} to {high}")
            continue
        if count == 0 and held.get("http_status") != 404:
            wrong.append(f"{encounter}: no event, yet answered {held.get('http_status') or 'with a record'}")
        names = [e.get("event") for e in events]
        if names != ["admit", "transfer"][:count]:
            wrong.append(f"{encounter}: events {names}")
        keys = [e.get("operation_key") for e in events]
        if len(set(keys)) != len(keys):
            wrong.append(f"{encounter}: an operation key twice in its history")
        if count == 2 and (held.get("ward") != wards.get(encounter) or held.get("version") != 2):
            wrong.append(f"{encounter}: ward {held.get('ward')}, version {held.get('version')}")
    result.rule("count", "final state at the receiver: wards, versions and history counts", not wrong,
                f"{len(reads)} encounters read through the receiver's API; " + ("; ".join(wrong[:12]) if wrong else "all as expected"))
    # A missing event is the count above; only one more than was sent, or a key twice, is a duplicate.
    extra = [f"{encounter}: {len(held.get('history') or [])} events" for encounter, held, _, _ in reads
             if held and len(held.get("history") or []) > 2]
    twice = [w for w in wrong if "twice" in w]
    result.rule("never", "no duplicate write: no encounter holds more than the events sent", not extra and not twice,
                "; ".join((extra + twice)[:6]) or "none extra")


def judge_writes(result, sql, plan):
    dup = sql.query(None, "SHUTTER", "SELECT %EXACT(OperationKey) AS K, COUNT(*) AS N FROM Downstream.Receipt GROUP BY %EXACT(OperationKey) HAVING COUNT(*) > 1")
    result.rule("never", "no operation key committed twice", not dup, f"{len(dup)} key(s) twice")
    receipts = sql.query(None, "SHUTTER", "SELECT %EXACT(OperationKey) AS K, %EXACT(EncounterId) AS E, %EXACT(Event) AS Ev, "
                         "VersionBefore AS B, VersionAfter AS A FROM Downstream.Receipt")
    known = {step["encounter"] for step in plan}
    per = {}
    foreign = []
    for r in receipts:
        if r["E"] in known:
            per.setdefault(r["E"], {})[r["Ev"]] = r
        else:
            foreign.append(r["K"])
    wrong = []
    for encounter, events in per.items():
        admit, transfer = events.get("admit"), events.get("transfer")
        if admit and int(admit["B"]) != 0:
            wrong.append(f"{encounter}: admit at version {admit['B']}")
        if transfer and not admit:
            wrong.append(f"{encounter}: a transfer with no admission")
        if admit and transfer and int(transfer["B"]) != int(admit["A"]):
            wrong.append(f"{encounter}: transfer at {transfer['B']}, admit left {admit['A']}")
    early = sql.query(None, "SHUTTER", 'SELECT i2.ID AS Item, %EXACT(a.OperationKey) AS K FROM Shutter_Store.ChainItem i2 '
                      'JOIN Shutter_Store.ChainItem i1 ON i1.Chain = i2.Chain AND i1.Position = 1 '
                      'JOIN Shutter_Store.ExecutionAttempt a ON a."Case" = i2."Case" '
                      "WHERE i2.Position = 2 AND a.Outcome = 'applied' AND i1.State <> 'resolved'")
    result.rule("never", "no write out of event order within an encounter", not wrong and not early,
                f"{len(per)} encounters in the receipts, {len(receipts)} rows; {wrong[:6]}; applied second items before their first resolved: {len(early)}")
    attempts = sql.query(None, "SHUTTER", 'SELECT %EXACT(a.OperationKey) AS K, a."At" AS T, %EXACT(a.Outcome) AS O, %EXACT(c.CaseId) AS CaseId, '
                         '(SELECT MIN(g."At") FROM Shutter_Store.GateDecision g WHERE g."Case" = a."Case") AS Gate, '
                         '(SELECT MIN(r."At") FROM Shutter_Store.Rehearsal r WHERE r."Case" = a."Case") AS Rehearsal '
                         'FROM Shutter_Store.ExecutionAttempt a JOIN Shutter_Store."Case" c ON c.ID = a."Case"')
    by_key = {}
    for a in attempts:
        by_key.setdefault(a["K"], []).append(a)
    unguarded = []
    for r in receipts:
        if r["E"] not in known:
            continue
        rows = by_key.get(r["K"])
        if not rows:
            unguarded.append(f"{r['K']}: a receipt with no attempt")
            continue
        for a in rows:
            if not a["Gate"] or not a["Rehearsal"] or a["Gate"] > a["T"] or a["Rehearsal"] > a["T"]:
                unguarded.append(f"{a['CaseId']}: attempt {a['T']}, gate {a['Gate']}, rehearsal {a['Rehearsal']}")
    result.rule("never", "each storm receipt has a gate decision and a rehearsal before its attempt", not unguarded,
                "; ".join(unguarded[:6]) if unguarded else f"{len(receipts)} receipts")
    if foreign:
        result.invalid(f"{len(foreign)} receipts for encounters this run did not send")
    return receipts


def judge_cases(result, sql, operator, ids, last_202, chains, events, cases):
    """Every 202's case is a case row and ends in the incident, gone from it with its note, or closed."""
    in_chain = {i.get("caseId") for _, i in chain_items(chains)}
    left = {}
    for e in events:
        m = re.match(r"Case (\S+) left: (.*)", e.get("text") or "")
        if m:
            left[m.group(1)] = m.group(2)
    missing = [c for c in ids if c not in cases]
    both = [c for c in ids if c in in_chain and c in left]
    astray = []
    for c in ids:
        row = cases.get(c)
        if not row or c in in_chain or c in left or row.get("state") in CLOSED:
            continue
        astray.append(f"{c} {row.get('state')}")
    result.rule("never", "no lost case", not missing and not both and not astray,
                f"{len(ids)} 202s; missing from the API {missing[:6]}; in a chain and gone {both[:6]}; neither in the incident nor closed {astray[:6]}")
    rows = sql.query(None, "SHUTTER", 'SELECT %EXACT(c.CaseId) AS CaseId, %EXACT(c.State) AS S, %EXACT(c.Disposition) AS D, %EXACT(c.Outcome) AS O, '
                     '(SELECT COUNT(*) FROM Shutter_Store.GateDecision g WHERE g."Case" = c.ID) AS Gates, '
                     "(SELECT COUNT(*) FROM Shutter_Store.GateDecision g WHERE g.\"Case\" = c.ID AND g.Stage = 'proposal') AS Proposal, "
                     "(SELECT COUNT(*) FROM Shutter_Store.ExecutionAttempt a WHERE a.\"Case\" = c.ID AND a.Outcome IN ('applied', 'already_committed')) AS Writes "
                     'FROM Shutter_Store."Case" c')
    no_gate, surprises = [], []
    for r in rows:
        if r["CaseId"] not in ids or r["S"] != "resolved":
            continue
        if int(r["Writes"] or 0):
            if not int(r["Gates"] or 0):
                no_gate.append(r["CaseId"])
        else:
            surprises.append(f"{r['CaseId']} ({r['D']}): {(r['O'] or '')[:80]}")
            if not int(r["Proposal"] or 0) and not r["O"]:
                no_gate.append(r["CaseId"])
    result.rule("never", "no case decided without a gate", not no_gate, f"{no_gate[:6]}")
    result.report("resolved_without_a_write", surprises[:20])
    return left


def judge_incident(result, args, size, incident, detail, events, left, samples, approval_at, last_202, first_send, stop_reason, largest_gap, plan, incidents_total):
    n = size["cases"]
    result.rule("count", "incidents opened for the receiver: 1", incidents_total == 1, f"{incidents_total}; largest gap between 202s {largest_gap:.1f} s")
    closed = event_at(events, r"Intake closed after")
    m = re.search(r": (\d+) cases", (closed or {}).get("text") or "")
    held = int(m.group(1)) if m else None
    result.rule("count", f"cases in the incident at classification: {n}", held == n, (closed or {}).get("text") or "no Intake closed event")
    readiness = [c for c, why in left.items() if "not collected" in why]
    result.rule("count", "cases that left at the readiness limit: 0", not left, f"{len(left)} left ({len(readiness)} at the readiness limit): " + "; ".join(f"{c}: {w}" for c, w in list(left.items())[:6]))
    result.report("leavers", left)
    chains = detail.get("chains") or []
    shapes = {}
    for c in chains:
        key = f"{c.get('kind')}/{len(c.get('items') or [])} items/{c.get('decides')}/{c.get('policy')}/{c.get('entries')}"
        shapes[key] = shapes.get(key, 0) + 1
    result.report("chains", {"count": len(chains), "expected": n // 2, "shapes": shapes})
    auth = event_at(events, r"^Authorisation:")
    result.report("authorisation_note", (auth or {}).get("text"))
    raised = event_at(events, r"approval task\(s\) raised")
    took = seconds_between(stamp(last_202), (raised or {}).get("at"))
    result.rule("count", f"approval task raised within {size['approval_limit']} s of the last 202", took is not None and took <= size["approval_limit"],
                f"{took} s" if took is not None else "never raised")
    bad = [c for c in chains if c.get("state") in ("stopped", "escalated", "rejected")]
    result.rule("count", "chains stopped or escalated during release: 0", not bad,
                "; ".join(f"chain {c.get('seq')} {c.get('state')}: {c.get('outcome')}" for c in bad[:8]) or "none")
    items = [i for _, i in chain_items(chains)]
    resolved = [i for i in items if i.get("state") == "resolved"]
    in_flight = [i for i in items if i.get("state") == "released"]
    pending = [i for i in items if i.get("state") == "pending"]
    result.report("items", {"total": len(items), "resolved": len(resolved), "in_flight": len(in_flight), "pending": len(pending), "stopped_because": stop_reason})
    closed_at = sorted(i.get("closedAt") for i in resolved if i.get("closedAt"))
    if size["stop_at"]:
        result.rule("count", f"items released and resolved: {size['stop_at']} of those released", len(resolved) >= size["stop_at"] and not bad,
                    f"{len(resolved)} resolved, {len(in_flight)} in flight, {len(pending)} pending, of {len(items)}")
    else:
        result.rule("count", f"items released and resolved: {n} of {n}", len(resolved) == n, f"{len(resolved)} resolved, {len(in_flight)} in flight, {len(pending)} pending")
    gaps = []
    previous = approval_at
    for at in closed_at[:size["stop_at"] or len(closed_at)]:
        gap = seconds_between(previous, at)
        if gap is not None:
            gaps.append(gap)
        previous = at
    if gaps:
        result.report("seconds_per_released_item", {"min": min(gaps), "median": statistics.median(gaps), "max": max(gaps), "over": len(gaps)})
    if size["stop_at"]:
        last = closed_at[size["stop_at"] - 1] if len(closed_at) >= size["stop_at"] else None
        over = seconds_between(approval_at, last)
        if over is not None:
            result.report("whole_release_extrapolated", {
                "statement": f"{n} cases were opened, grouped and approved; {size['stop_at']} of the {n} items were released and verified; "
                             "the per-item time is from those items and the whole-release figure is an extrapolation, not a measurement.",
                "seconds_for_stop_items": over, "seconds_for_all_items_extrapolated": round(over * n / size["stop_at"])})
    else:
        last = closed_at[-1] if closed_at else None
        over = seconds_between(approval_at, last)
        result.rule("count", f"approval to the last case decided: at most {size['release_limit']} s", over is not None and over <= size["release_limit"] and len(closed_at) == n,
                    f"{over} s over {len(closed_at)} items")
    opened = event_at(events, r"^Incident opened") or (events[0] if events else None)
    result.report("seconds_from_first_post", {
        "incident_opened": seconds_between(stamp(first_send), (incident or {}).get("openedAt") or (opened or {}).get("at")),
        "intake_closed": seconds_between(stamp(first_send), (closed or {}).get("at")),
        "chains_formed": seconds_between(stamp(first_send), (event_at(events, r"chain\(s\) formed") or {}).get("at")),
        "approval_task": seconds_between(stamp(first_send), (raised or {}).get("at")),
    })
    if closed and samples:
        at_close = [s for s in samples if s["at"] <= closed.get("at", "") + "~"]
        if at_close:
            result.report("evidence_backlog_at_intake_close", {"sampled_at": at_close[-1]["at"], "closed_at": closed.get("at"), "states": at_close[-1]["backlog"]})
    result.report("largest_backlog", max((sum(v or 0 for v in s["backlog"].values()) for s in samples), default=None))


def database_mb(ctr):
    rc, out, _ = docker("exec", ctr, "du", "-sm", "/usr/irissys/mgr/shutter")
    return int(out.split()[0]) if rc == 0 and out.split() else None


def licence_lines(ctr):
    rc, out, _ = docker("exec", ctr, "grep", "-c", "License limit", "/usr/irissys/mgr/messages.log")
    return int(out.strip() or 0) if rc in (0, 1) else None


def run_checker(module, argv, sql):
    module.query = sql.query
    saved, sys.argv = sys.argv, argv
    buffer = io.StringIO()
    try:
        with contextlib.redirect_stdout(buffer):
            code = module.main()
    finally:
        sys.argv = saved
    return code, buffer.getvalue()


def board_run(args, operator, ids, sampler, result, log):
    """The board path: approve whatever waits for a person, as a person would, until every case has closed."""
    deadline = time.monotonic() + SIZES[args.size]["give_up"] * 2
    decided = set()
    while time.monotonic() < deadline:
        cases, _ = all_cases(operator)
        open_cases = [c for c in ids if not cases or cases.get(c, {}).get("state") not in CLOSED]
        if not open_cases:
            return "every case closed"
        found = incidents_of(operator) or []
        for incident in found:
            if incident.get("state") == "closed":
                continue
            path = "/incidents/" + urllib.parse.quote(incident["incidentId"])
            status, detail, _, _ = operator.call("GET", path)
            if status != 200 or incident["incidentId"] in decided:
                continue
            if any(not t.get("complete") for t in detail.get("tasks") or []):
                approver = Role(args.url, "approver", log)
                approver.call("POST", path + "/approvals", {"planDigest": (detail.get("plan") or {}).get("digest"), "decision": "approve", "comment": "storm check"},
                              idempotent=True)
                approver.sign_out()
                decided.add(incident["incidentId"])
        waiting = [c for c in open_cases if (cases or {}).get(c, {}).get("state") == "awaiting_approval" and c not in decided]
        if waiting:
            approver = Role(args.url, "approver", log)
            for c in waiting:
                _, row, _, _ = operator.call("GET", f"/cases/{c}")
                _, view, _, _ = operator.call("GET", f"/cases/{c}/plan")
                approver.call("POST", f"/cases/{c}/approvals", {"decision": "approve", "planDigest": view["plan"]["digest"], "expectedVersion": row["version"],
                                                                "comment": "storm check"}, idempotent=True)
                decided.add(c)
            approver.sign_out()
        time.sleep(20)
    return "gave up"


def judge_board(args, sql, sampler, result, before_mock):
    leads = sql.query(None, "SHUTTER", "SELECT %EXACT(Signature) AS Signature, %EXACT(LeaderCaseId) AS Leader, %EXACT(State) AS State FROM Shutter_Store.BoardLead")
    signatures = {r["Signature"] for r in leads}
    result.report("board_leads", leads[:20])
    result.rule("count", "boards convened at most the distinct failure signatures", len(leads) <= max(1, len(signatures)) and len(leads) <= 2,
                f"{len(leads)} leads, {len(signatures)} signatures")
    worst = max(sampler.convened.values(), default=0)
    result.rule("count", "never above 6 boards convened in a minute", worst <= 6, f"highest sampled {worst}, sampled every 20 s: {sampler.convened}")
    code = 'Set n=0,k="" For { Set k=$ORDER(^Shutter.MockLog(k)) Quit:k=""  Set n=n+1 } Write "<<<",n,">>>",!'
    calls = between_marks(iris_session(args.ctr, "SHUTTER", code))
    result.report("mimic_log_nodes", {"before": before_mock, "after": calls})


def run(args):
    """The whole run; a fault in this harness ends it as invalid, with what it had by then."""
    log = Log(args.out)
    result = Result(args, args.out)
    try:
        return storm(args, log, result)
    except (Exception, SystemExit) as error:
        result.invalid(f"the harness stopped: {type(error).__name__}: {error}")
        return result.finish()


def storm(args, log, result):
    size = SIZES[args.size]
    folder = args.out
    base = utc_now() - dt.timedelta(seconds=2 * size["cases"] + 300)
    plan = storm_plan(size["cases"], base, args.order)
    problems = check_plan(plan, size["cases"])
    if problems:
        result.invalid("a malformed plan: " + "; ".join(problems))
        return result.finish()
    if args.plan_only:
        print(f"{len(plan)} messages for {size['cases'] // 2} patients, none of the plan's own checks failed. First:")
        print(plan[0]["text"].replace("\r", "\n"))
        print(plan[len(plan) // 2].get("text").replace("\r", "\n"))
        return 0
    if args.boot:
        boot(args, log)
    wait_healthy(args.url)
    operator = forwarder = None
    for attempt in range(8):
        try:
            operator = Role(args.url, "operator", log)
            forwarder = Role(args.url, "forwarder", log)
            break
        except SystemExit as error:
            print(f"sign-in refused, retrying ({error})", flush=True)
            time.sleep(15)
    if not forwarder:
        result.invalid("the demo users could not sign in")
        return result.finish()
    sql = Sql(args.url, log)
    sampler = Sampler(args.ctr, log, args.board)

    # Clean start
    _, settings, _, _ = operator.call("GET", "/settings")
    settings = settings or {}
    if settings.get("watchedMode") != "policy":
        result.invalid(f"watchedMode is {settings.get('watchedMode')}, not policy")
    if (settings.get("live") or {}).get("enabled"):
        result.invalid("the live hospital is on")
    _, open_incidents, _, _ = operator.call("GET", "/incidents?state=open")
    if (open_incidents or {}).get("total"):
        result.invalid(f"{open_incidents.get('total')} open incident(s) before the storm")
    token = base64.b64encode(f"{ADMIN[0]}:{ADMIN[1]}".encode()).decode()
    request = urllib.request.Request(args.url + "/downstream/api/reset", data=b"{}", method="POST",
                                     headers={"Authorization": "Basic " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            log.line("calls.jsonl", role="receiver", method="POST", path="/downstream/api/reset", status=response.status)
    except urllib.error.URLError as error:
        result.invalid(f"the receiver's reset failed: {error}")
    prior = sql.one("SHUTTER", "SELECT COUNT(*) AS N FROM Downstream.Receipt")
    if int(prior.get("N") or 0):
        result.invalid(f"{prior['N']} receipts before the first post")
    runs_before = sql.one("SHUTTER", "SELECT COUNT(*) AS N FROM Shutter_Store.AgentRun")
    _, costs_before, _, _ = operator.call("GET", "/costs")
    _, incidents_before, _, _ = operator.call("GET", "/incidents")
    nodes_before = board_nodes(args.ctr)
    licence_before = licence_lines(args.ctr)
    db_before = database_mb(args.ctr)
    mock_before = between_marks(iris_session(args.ctr, "SHUTTER", 'Set n=0,k="" For { Set k=$ORDER(^Shutter.MockLog(k)) Quit:k=""  Set n=n+1 } Write "<<<",n,">>>",!')) if args.board else None
    memory = {"at_rest": sampler.memory("at rest")}
    result.report("clean_start", {"watchedMode": settings.get("watchedMode"), "live_enabled": (settings.get("live") or {}).get("enabled"),
                                  "open_incidents": (open_incidents or {}).get("total"), "database_mb": db_before,
                                  "incidents_before": (incidents_before or {}).get("total"), "licence_lines_before": licence_before,
                                  "board_nodes_before": nodes_before})
    if result.doc["invalid"]:
        return result.finish()
    sql.rationed = True
    sampler.start()

    # The storm
    ids, first_send, last_202, largest_gap = generate(args, plan, forwarder, result, log)
    memory["end_of_intake"] = sampler.memory("end of intake")
    forwarder.sign_out()
    if not ids or result.doc["invalid"]:
        sampler.stop_now.set()
        return result.finish()

    approval_at, samples, detail, stop_reason = None, [], None, "not reached"
    incident, samples = wait_for_approval(operator, size, last_202, log)
    if args.board:
        stop_reason = board_run(args, operator, ids, sampler, result, log)
    elif incident and incident.get("state") == "awaiting_approval":
        approval_at, detail = approve(args, operator, incident, result, log)
        if approval_at:
            stop_reason = wait_for_release(operator, size, log)
    else:
        result.rule("count", "approval tasks raised: 1, shared", False, f"the incident is {(incident or {}).get('state')}")
    if result.doc["invalid"]:
        sampler.stop_now.set()
        return result.finish()
    memory["end_of_release"] = sampler.memory("end of release")

    # Measurements. The licence first, while nothing here has made a cookie-less call since the reset before the first post.
    licence_at_release_end = licence_lines(args.ctr)
    status_rows = []
    with open(os.path.join(folder, "calls.jsonl")) as f:
        status_rows = [json.loads(x) for x in f]
    refused = [r for r in status_rows if r.get("status") == 503]
    sql.rationed = False
    log_licence = sql.one("SHUTTER", "SELECT COUNT(*) AS N FROM Ens_Util.Log WHERE Text LIKE '%License limit%'")
    grown = (licence_at_release_end or 0) - (licence_before or 0)
    result.rule("never", "no licence exhaustion by the product", not grown and not int(log_licence.get("N") or 0) and not refused,
                f"messages.log lines {licence_before} then {licence_at_release_end}; Event Log rows {log_licence.get('N')}; 503s to this run {len(refused)}")

    incident_path = "/incidents/" + urllib.parse.quote((incident or {}).get("incidentId") or "none")
    status, detail_end, took, size_bytes = operator.call("GET", incident_path)
    result.rule("surface", "GET /incidents/{id} at the end answers within 60 s", status == 200 and took <= 60 and size_bytes > 0, f"HTTP {status}, {took} s, {size_bytes} bytes")
    result.report("get_incident_at_end", {"status": status, "seconds": took, "bytes": size_bytes})
    detail_end = detail_end if status == 200 and isinstance(detail_end, dict) else (detail or {})
    _, events, took, events_bytes = operator.call("GET", incident_path + "/events")
    events = events if isinstance(events, list) else []
    result.report("get_incident_events", {"seconds": took, "bytes": events_bytes, "count": len(events)})
    result.report("incident_end", {"state": detail_end.get("state"), "summary": (detail_end.get("summary") or "")[:400],
                                   "errors": [e.get("text", "")[-300:] for e in events if e.get("kind") == "error"]})
    for name, body in (("incident-end.json", detail_end), ("incident-events.json", events)):
        with open(os.path.join(folder, name), "w") as f:
            json.dump(body, f, indent=1)

    cases, first_page = all_cases(operator)
    result.report("get_cases_first_page", first_page)
    states = {}
    for c in ids:
        state = (cases or {}).get(c, {}).get("state")
        states[state] = states.get(state, 0) + 1
    result.report("case_states_at_end", states)
    unattached = [c for c in ids if not (cases or {}).get(c, {}).get("incidentId") and (cases or {}).get(c, {}).get("state") in NOT_YET_DECIDED]
    while unattached and (utc_now() - last_202).total_seconds() < 600:
        time.sleep(20)
        cases, _ = all_cases(operator)
        unattached = [c for c in ids if not (cases or {}).get(c, {}).get("incidentId") and (cases or {}).get(c, {}).get("state") in NOT_YET_DECIDED]

    _, listing, _, _ = operator.call("GET", "/incidents?limit=500")
    incidents_total = len([i for i in (listing or {}).get("items", []) if i.get("receiver") == RECEIVER]) - len(
        [i for i in (incidents_before or {}).get("items", []) if i.get("receiver") == RECEIVER])

    left = judge_cases(result, sql, operator, ids, last_202, detail_end.get("chains") or [], events, cases or {})
    judge_writes(result, sql, plan)
    code, text = run_checker(lineage_check, ["lineage_check.py", "--url", args.url, "--ns", "SHUTTER", "--cases", ",".join(c for c in ids if c)], sql)
    result.rule("never", "lineage: no write before a gate decision and a rehearsal", code == 0, text.strip()[-600:])
    code, text = run_checker(eventlog_check, ["eventlog_check.py", "--url", args.url, "--ns", "SHUTTER"], sql)
    result.rule("never", "no runtime error in the Event Log", code == 0, text.strip()[-600:])
    ignored = sql.one("SHUTTER", "SELECT COUNT(*) AS N FROM Ens_Util.Log WHERE Text LIKE '%not grouped; the release from incident%'")
    result.rule("never", "a released case that is not grouped is never released again", not int(ignored.get("N") or 0), f"{ignored.get('N')} warning line(s)")

    if args.board:
        judge_board(args, sql, sampler, result, mock_before)
    else:
        judge_incident(result, args, size, incident, detail_end, events, left, samples, approval_at, last_202, first_send, stop_reason, largest_gap, plan, incidents_total)
        _, costs_after, _, _ = operator.call("GET", "/costs")
        runs_after = sql.one("SHUTTER", "SELECT COUNT(*) AS N FROM Shutter_Store.AgentRun")
        nodes_after = board_nodes(args.ctr)
        new_nodes = {k: v for k, v in nodes_after.items() if nodes_before.get(k) != v}
        totals = lambda c: {k: ((c or {}).get("totals") or {}).get(k) for k in ("liveRuns", "replayedRuns", "mockRuns")}  # noqa: E731
        result.rule("count", "agent runs during the run: 0", int(runs_after.get("N") or 0) == int(runs_before.get("N") or 0) and not new_nodes and totals(costs_before) == totals(costs_after),
                    f"AgentRun rows {runs_before.get('N')} then {runs_after.get('N')}; /costs {totals(costs_before)} then {totals(costs_after)}; new convened nodes {new_nodes}")

    # The receiver's API takes no session: last, paced.
    reads = read_encounters(args.url, plan, detail_end.get("chains") or [], [], args.encounter_pace, log)
    # A size that stops measuring early leaves its release running, so what has begun is read after the receiver's reads.
    _, detail_after, _, _ = operator.call("GET", incident_path)
    detail_after = detail_after if isinstance(detail_after, dict) else detail_end
    begun = {c.get("encounterId"): sum(1 for i in c.get("items") or [] if i.get("releasedAt")) for c in detail_after.get("chains") or []}
    reads = [(encounter, held, low, begun.get(encounter, 0)) for encounter, held, low, _ in reads]
    judge_final_state(result, plan, reads, whole_release=not SIZES[args.size]["stop_at"] and not args.board)

    rc, out, _ = docker("inspect", "--format", "{{.RestartCount}} {{.State.OOMKilled}} {{.State.Running}}", args.ctr)
    fields = out.split()
    result.rule("never", "no instance crash or restart", rc == 0 and fields[:2] == ["0", "false"] and fields[2:] == ["true"], out.strip())
    db_after = database_mb(args.ctr)
    per_hundred = round((db_after - db_before) / size["cases"] * 100, 1) if db_after is not None and db_before is not None else None
    result.report("database", {"before_mb": db_before, "after_mb": db_after, "growth_mb_per_100_cases": per_hundred})
    result.report("memory", memory)
    licence_end = licence_lines(args.ctr)
    if (licence_end or 0) != (licence_at_release_end or 0):
        result.report("licence_after_the_measurement", f"messages.log went from {licence_at_release_end} to {licence_end} lines during this run's own final reads: this harness's, not the product's")
    result.report("harness_calls", {"sql_statements": sql.count, "operator_sign_ins": operator.signins, "rest_calls": len(status_rows)})
    sampler.stop_now.set()
    operator.sign_out()
    if SIZES[args.size]["stop_at"]:
        docker("stop", "-t", "120", args.ctr, timeout=180)
        result.report("container", "stopped after the measurements, as the top size does not run its whole release")
    return result.finish()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--size", choices=sorted(SIZES))
    parser.add_argument("--control", type=int, metavar="CASES", help="a small even number of cases to prove the release path: a control, none of the three sizes")
    parser.add_argument("--ctr", help="the instance's container, this run's own name")
    parser.add_argument("--url", help="the instance's web port, for example http://127.0.0.1:52773")
    parser.add_argument("--out", help="a folder for the run's logs and result")
    parser.add_argument("--boot", action="store_true", help="make a fresh instance first; needs --image and --port")
    parser.add_argument("--image")
    parser.add_argument("--port", type=int)
    parser.add_argument("--order", choices=("admits-first", "interleaved"), default="admits-first")
    parser.add_argument("--board", action="store_true", help="mode board, S only, on an AI Hub build with tests/mock enabled")
    parser.add_argument("--encounter-pace", type=float, default=1.0, help="seconds between the receiver's final reads")
    parser.add_argument("--plan-only", action="store_true", help="build and check the messages, send nothing")
    args = parser.parse_args()
    if args.control:
        if args.size or args.control % 2 or args.control < 6:
            parser.error("--control takes an even number of cases, at least 6 (an incident opens at the 5th), and no --size")
        SIZES["control"] = {"cases": args.control, "approval_limit": 300, "release_limit": 600, "give_up": 1200, "stop_at": None}
        args.size = "control"
    if not args.size:
        parser.error("--size or --control is required")
    if args.plan_only:
        args.out = args.out or os.path.join(os.environ.get("TMPDIR", "/tmp"), f"storm-plan-{os.getpid()}")
    elif not (args.ctr and args.out and (args.url or args.port)):
        parser.error("--ctr, --out and --url (or --port) are required")
    if args.boot and not (args.image and args.port):
        parser.error("--boot needs --image and --port")
    if args.board and args.size not in ("S", "control"):
        parser.error("--board runs at size S only")
    args.url = (args.url or f"http://127.0.0.1:{args.port}").rstrip("/")
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
