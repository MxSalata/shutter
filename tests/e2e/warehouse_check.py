#!/usr/bin/env python3
"""Checks warehouse history (docs/warehouse-history.md) over HTTP, and that switching it on changes no decision.

    python3 tests/e2e/warehouse_check.py --ctr CONTAINER [--url http://localhost:52773] [--ns SHUTTER]
                                         [--plays board:S1,S2;policy:S11] [--control]
    python3 tests/e2e/warehouse_check.py --static

--static only compares the specification's SQL with the statements in the classes, and needs no instance.

Otherwise, in order, on an instance nobody else is using (it plays scenarios and creates the reader):

1. Off by default: the case route says enabled false, a read is refused 409, signed out 401, without the CSRF header 403,
   and the reader's web application does not exist.
2. The differential's first half: each scenario in --plays is played with it off, and each of its cases is written down:
   its state, events, plan, gate decisions, approvals, attempts, verifications and closure, with times and ids taken out.
3. Install and Enable, and rows published for every patient those cases named. The reader answers its user over HTTP, and
   refuses no password, another user's password and a request with no patient; a patient value written as SQL is only a
   value. The profile's version has not moved.
4. The differential's second half: the same plays, with a person reading the panel as hard as they can throughout, on every
   open case. Every case must be written down the same, the reads must have happened, and they must have returned rows.
5. The panel's reads say what they read, and the case's timeline does not grow when it is read.

--control plays the first half twice before anything is installed, which shows how much two runs differ with nothing
changed: nothing, or the comparison would be noise. Exit status 1 when a check fails. Standard library only, and
scenario_check.py beside it.
"""
import argparse
import base64
import json
import os
import re
import secrets
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scenario_check  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATASET = "E2E-WH"
READER = "ShutterWarehouseReader"
READER_PATH = "/api/shutter-warehouse"
PLAYS = "board:S1,S2,S3,S4,S5,S6,S7,S8,S9,S10,S13,S15,S16,S21,S22,S23a,S23b,S23c,S24,S25;policy:S11,S12,S17,S18,S19;rules:S20"
CLOSED = {"resolved", "blocked", "escalated", "failed"}
# Times, ids and digests differ between any two runs, and digests bind times and ids, so what they bind is compared instead.
# So does the receiver's epoch, which every reset moves, and the count of precedents, which grows with each run played.
VOLATILE_KEY = re.compile(r"(^id$|id$|at$|time|digest|duration|latency|^ms$|millis|elapsed|expires|session|token|^run|^key$|attempt$|taskid|cost|tokens"
                          r"|^seq$|^links$|^ref$|epoch|^precedents$|^counts$)", re.IGNORECASE)
# Notes on the timeline depend on the clock (a Retry-After's countdown, the rate cap, a retry that came before the case
# closed), so the comparison keeps the events that are not notes.
STAMP = re.compile(r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?Z?")
CASE_ID = re.compile(r"\b(C|I|Q)-\d{6}\b")
TAIL_DIGITS = re.compile(r"\b\d{9,}\b")
# Row ids and digests written inside a sentence or a reference
INNER = re.compile(r"sha256:[0-9a-f]+|\b(run|ens|snapshot|finding|plan|approval|rehearsal|attempt|epoch|task)( |:)\d+\b")
PARTS = ("events", "snapshot", "plan", "approvals", "attempts", "closure", "blocked-reason")
fails = []


def check(ok, what):
    print(("ok   " if ok else "FAIL ") + what, flush=True)
    if not ok:
        fails.append(what)
    return ok


def normal_sql(text):
    return " ".join(text.split()).rstrip(";").strip()


def static_checks():
    """The statements in the specification are the ones the classes run, word for word."""
    with open(os.path.join(ROOT, "docs", "warehouse-history.md"), encoding="utf-8") as f:
        doc = f.read()
    blocks = re.findall(r"```sql\n(.*?)```", doc, re.S)
    ddl = [normal_sql(s) for s in blocks[0].split(";") if s.strip()]
    queries = [normal_sql(b) for b in blocks[1:]]
    with open(os.path.join(ROOT, "src", "Shutter", "Warehouse", "Setup.cls"), encoding="utf-8") as f:
        setup = f.read()
    with open(os.path.join(ROOT, "src", "Shutter", "Warehouse", "Reader.cls"), encoding="utf-8") as f:
        reader = f.read()
    # The class writes "(a, b)" on one line where the specification lays it out over several
    squeeze = lambda s: re.sub(r"\(\s+", "(", re.sub(r"\s+\)", ")", s))
    in_setup = [squeeze(normal_sql(s)) for s in re.findall(r'Quit "((?:CREATE) [^"]*)"', setup)]
    check([squeeze(s) for s in ddl] == in_setup, "the specification's tables are the ones Setup creates")
    in_reader = [normal_sql(s) for s in re.findall(r'\.\.Run\("(SELECT [^"]*)"', reader)]
    check(len(queries) == 3 and queries == in_reader, "the specification's three queries are the ones the reader runs")
    check(re.findall(r"INSERT|UPDATE|DELETE|DROP|%ExecDirectNoPriv|&sql", reader) == [], "the reader has no statement but its SELECTs")


class Iris:
    def __init__(self, ctr, ns):
        self.ctr, self.ns = ctr, ns

    def session(self, line):
        """One line in a terminal session in the namespace; what it wrote after RESULT: on the line."""
        script = f'{line}\nHalt\n'
        # A terminal can be refused while the web sessions hold the licence's units. No RESULT line means the line did not
        # run to its end, so ask again; a check sees the "no result" if it never does.
        found, out = [], ""
        for _ in range(40):
            out = subprocess.run(["docker", "exec", "-i", self.ctr, "iris", "session", "IRIS", "-U", self.ns],
                                 input=script, capture_output=True, text=True, timeout=300).stdout
            found = re.findall(r"^RESULT: (.*)$", out, re.M)
            if found:
                break
            time.sleep(5)
        return found[-1].strip() if found else "no result: " + out[-400:]

    def call(self, expression):
        return self.session(f'Set r = {expression} Write !,"RESULT: ",r,!')

    def sql(self, statement, *args):
        passed = "".join(", " + q(a) for a in args)
        return self.session(f'Set rs = ##class(%SQL.Statement).%ExecDirect(, {q(statement)}{passed}) Write !,"RESULT: ",rs.%SQLCODE," ",rs.%Message,!')


def q(value):
    return '"' + str(value).replace('"', '""') + '"'


def basic(url, path, user=None, password=None):
    request = urllib.request.Request(url.rstrip("/") + path)
    if user:
        request.add_header("Authorization", "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode())
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()


def normalise(value, key=""):
    if isinstance(value, dict):
        return {k: normalise(v, k) for k, v in sorted(value.items()) if not VOLATILE_KEY.search(k)}
    if isinstance(value, list):
        return [normalise(v) for v in value]
    if isinstance(value, str):
        return TAIL_DIGITS.sub("<n>", INNER.sub("<ref>", CASE_ID.sub("<case>", STAMP.sub("<time>", value))))
    return value


def case_record(operator, case_id):
    """What a case came to, with times and ids taken out."""
    quoted = urllib.parse.quote(case_id)
    _, case = operator.call("GET", f"/cases/{quoted}")
    record = {"case": normalise(case)}
    for part in PARTS:
        status, body = operator.call("GET", f"/cases/{quoted}/{part}")
        body = normalise(body)
        if part == "events" and isinstance(body, list):
            # The board's members run side by side and finish in either order
            body = sorted((e for e in body if e.get("kind") != "note"), key=lambda e: json.dumps(e, sort_keys=True))
        record[part] = {"status": status, "body": body}
    return record, case


def play_all(args, plays, operator, approver, known, read_while=None):
    """Plays each scenario; {scenario mode: {cases in the order opened}} and the patients the cases named."""
    out, patients = {}, set()
    for mode, ids in plays:
        for sid in ids:
            label = f"{sid} {mode}"
            _, listing = operator.call("GET", f"/cases?scenario={sid}&limit=50")
            seen = {c["caseId"] for c in (listing or {}).get("items", [])}
            try:
                ok, line, _ = scenario_check.play(args, operator, approver, known[sid], mode)
            except (TimeoutError, RuntimeError) as error:
                ok, line = False, f"{label}: {error}"
            print(("     " + line.replace("\n", "\n     ")), flush=True)
            # Something closing after the judged case: wait for the run's other cases to come to rest too
            scenario_check.wait_until_idle(operator, args.timeout)
            _, listing = operator.call("GET", f"/cases?scenario={sid}&limit=50")
            new = [c for c in (listing or {}).get("items", []) if c["caseId"] not in seen]
            records = []
            for summary in sorted(new, key=lambda c: (c.get("operationKey") or "", c.get("receiver") or "")):
                record, case = case_record(operator, summary["caseId"])
                records.append(record)
                if case.get("patientId") and case.get("patientIdAuthority"):
                    patients.add((case["patientIdAuthority"], case["patientId"]))
            out[label] = {"judged": bool(ok), "cases": records}
    return out, patients


def differences(a, b, path=""):
    if isinstance(a, dict) and isinstance(b, dict):
        found = []
        for key in sorted(set(a) | set(b)):
            if key not in a or key not in b:
                found.append(f"{path}.{key}: only in {'second' if key not in a else 'first'}")
            else:
                found += differences(a[key], b[key], f"{path}.{key}")
        return found
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            only = [json.dumps(x)[:300] for x in a if x not in b] + [json.dumps(x)[:300] for x in b if x not in a]
            return [f"{path}: {len(a)} items and {len(b)} items; in one only: {only[:4]}"]
        found = []
        for i, (x, y) in enumerate(zip(a, b)):
            found += differences(x, y, f"{path}[{i}]")
        return found
    return [] if a == b else [f"{path}: {json.dumps(a)[:160]} and {json.dumps(b)[:160]}"]


def compare(first, second, what):
    """Check the two runs of the plays came to the same thing."""
    same = 0
    for label in first:
        found = differences(first[label], second.get(label), label)
        if check(not found, f"{what}: {label}, {len(first[label]['cases'])} case(s) the same"):
            same += 1
        for line in found[:12]:
            print("     " + line, flush=True)
    return same


class Reading(threading.Thread):
    """A person reading the panel as hard as they can, on every case the scenarios open."""

    def __init__(self, url, password):
        super().__init__(daemon=True)
        self.session = scenario_check.Session(url).sign_in("operator", password)
        self.stop = threading.Event()
        self.reads, self.statuses, self.errors = 0, {}, []

    def run(self):
        while not self.stop.is_set():
            status, listing = self.session.call("GET", "/cases?limit=20")
            for case in (listing or {}).get("items", []):
                if case.get("state") in CLOSED and self.reads % 7:
                    continue
                code, body = self.session.call("POST", f"/cases/{urllib.parse.quote(case['caseId'])}/warehouse-history")
                self.reads += 1
                if code == 200:
                    s = body["read"]["status"]
                    self.statuses[s] = self.statuses.get(s, 0) + 1
                else:
                    self.errors.append(f"{case['caseId']}: HTTP {code} {body}")
            self.stop.wait(0.5)


def publish(iris, patients):
    """A ready batch with a row for each patient, watermark an hour ago."""
    now = time.gmtime(time.time() - 3600)
    stamp = time.strftime("%Y-%m-%d %H:%M:%S", now)
    rows = sorted(patients)
    result = iris.sql(
        "INSERT INTO ShutterWH.Batch (DatasetId,BatchId,BatchSequence,DatasetGeneration,SourceSystem,ReceiverReference,"
        "ExtractStartedAtUTC,ExtractFinishedAtUTC,SourceWatermarkUTC,WatermarkKnown,HistoryCompleteFromUTC,PublishedAtUTC,"
        "Ready,PublishedRows,SchemaVersion) VALUES (?,'B1',1,'G1','PAS','the demo receiver',?,?,?,1,'2020-01-01 00:00:00',?,0,?,1)",
        DATASET, stamp, stamp, stamp, stamp, len(rows))
    check(result.startswith("0"), f"a batch published: {result}")
    for n, (authority, patient) in enumerate(rows, 1):
        result = iris.sql(
            "INSERT INTO ShutterWH.Movement (DatasetId,BatchId,SourceEventId,Revision,RecordStatus,PatientAuthority,PatientId,"
            "EventKind,EventTimeUTC,TimePrecision,Ward) VALUES (?,'B1',?,1,'active',?,?,'transfer','2020-02-02 10:00:00','second','WARD-Z')",
            DATASET, f"E{n}", authority, patient)
        if not result.startswith("0"):
            check(False, f"row {n}: {result}")
    result = iris.sql("UPDATE ShutterWH.Batch SET Ready = 1 WHERE DatasetId = ? AND BatchId = 'B1'", DATASET)
    check(result.startswith("0"), "the batch marked ready, last")


def parse_plays(text):
    plays = []
    for part in text.split(";"):
        mode, _, ids = part.partition(":")
        plays.append((mode.strip(), [i.strip() for i in ids.split(",") if i.strip()]))
    return plays


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--ctr")
    p.add_argument("--ns", default="SHUTTER")
    p.add_argument("--plays", default=PLAYS)
    p.add_argument("--control", action="store_true")
    p.add_argument("--static", action="store_true")
    p.add_argument("--timeout", type=int, default=240)
    p.add_argument("--reader-port", type=int, default=52773, help="the web server's port inside the container")
    p.add_argument("--downstream-user", default="_SYSTEM")
    p.add_argument("--downstream-password", default="SYS")
    args = p.parse_args()
    args.approve = True

    static_checks()
    if args.static:
        return 1 if fails else 0
    if not args.ctr:
        raise SystemExit("--ctr names the container, for the terminal session the install needs")

    password = os.environ.get("SHUTTER_PASSWORD", "shutter")
    iris = Iris(args.ctr, args.ns)
    operator = scenario_check.Session(args.url).sign_in("operator", password)
    approver = scenario_check.Session(args.url).sign_in("approver", password)
    _, listing = operator.call("GET", "/scenarios")
    known = {s["id"]: s for s in (listing or {}).get("scenarios", [])}
    plays = parse_plays(args.plays)

    # A run that stopped half-way may have left this check's own dataset; never anything else
    exists = iris.call("##class(Shutter.Warehouse.Setup).TablesExist()")
    check(exists in ("0", "1"), f"the terminal answers: {exists}")
    if exists == "1":
        for table in ("Movement", "Batch"):
            result = iris.sql(f"DELETE FROM ShutterWH.{table} WHERE DatasetId = ?", DATASET)
            check(result.startswith(("0", "100")), f"this check's own rows of an earlier run cleared from {table}: {result}")

    # 1. Off by default
    status, _ = basic(args.url, READER_PATH + "/history?dataset=x&authority=y&patient=z", "_SYSTEM", "SYS")
    check(status == 404, f"no reader until a site asks for one: HTTP {status}")
    _, profile = operator.call("GET", "/site-profile")
    version_before = (profile or {}).get("version", (profile or {}).get("profile", {}).get("version"))

    # 2. The first half
    print("--- with it off", flush=True)
    off, patients = play_all(args, plays, operator, approver, known)
    check(all(v["cases"] for v in off.values()), "every play left at least one case")
    if args.control:
        print("--- with it off again, the control", flush=True)
        again, _ = play_all(args, plays, operator, approver, known)
        compare(off, again, "the control, two runs with nothing changed")

    _, listing = operator.call("GET", "/cases?limit=1")
    case_id = listing["items"][0]["caseId"]
    quoted = urllib.parse.quote(case_id)
    status, body = operator.call("GET", f"/cases/{quoted}/warehouse-history")
    check(status == 200 and body.get("enabled") is False and body.get("read") is None, f"off: the case route says so: {status} {body}")
    status, body = operator.call("POST", f"/cases/{quoted}/warehouse-history")
    check(status == 409 and (body or {}).get("error") == "warehouse_off", f"off: a read is refused: {status}")
    signed_out = scenario_check.Session(args.url)
    status, _ = signed_out.call("GET", f"/cases/{quoted}/warehouse-history")
    check(status == 401, f"signed out: {status}")
    request = urllib.request.Request(operator.base + f"/cases/{quoted}/warehouse-history", method="POST")
    try:
        with operator.opener.open(request, timeout=30) as response:
            status = response.status
    except urllib.error.HTTPError as error:
        status = error.code
    check(status == 403, f"without the CSRF header: {status}")

    # 3. Install and Enable
    print("--- switching it on", flush=True)
    secret = "Wh-" + secrets.token_urlsafe(18)
    check(iris.call(f'##class(Shutter.Warehouse.Setup).Install({q(secret)})') == "ok", "Install")
    check(iris.call(f'##class(Shutter.Warehouse.Setup).Enable({q(DATASET)}, 360, 0, "localhost", {args.reader_port})') == "ok", "Enable")
    publish(iris, patients or {("HOSP", "NOBODY")})
    _, profile = operator.call("GET", "/site-profile")
    version_after = (profile or {}).get("version", (profile or {}).get("profile", {}).get("version"))
    check(version_before == version_after, f"the site profile's version did not move: {version_before} and {version_after}")

    authority, patient = sorted(patients or {("HOSP", "NOBODY")})[0]
    query = "?" + urllib.parse.urlencode({"dataset": DATASET, "authority": authority, "patient": patient})
    status, text = basic(args.url, READER_PATH + "/history" + query, READER, secret)
    check(status == 200 and json.loads(text)["rows"], f"the reader answers its user with rows: {status} {text[:160]}")
    status, _ = basic(args.url, READER_PATH + "/history" + query)
    check(status in (401, 403), f"the reader refuses no password: {status}")
    status, _ = basic(args.url, READER_PATH + "/history" + query, "operator", password)
    check(status in (401, 403, 404), f"the reader refuses another user, one who can operate cases: {status}")
    status, _ = basic(args.url, READER_PATH + "/history?dataset=" + DATASET, READER, secret)
    check(status == 400, f"the reader needs a patient: {status}")
    injected = "?" + urllib.parse.urlencode({"dataset": DATASET, "authority": authority, "patient": "x' OR '1'='1"})
    status, text = basic(args.url, READER_PATH + "/history" + injected, READER, secret)
    check(status == 200 and json.loads(text)["rows"] == [], f"a patient written as SQL is only a value: {status}")
    status, _ = basic(args.url, READER_PATH + "/anything", READER, secret)
    check(status == 404, f"the reader has one route: {status}")

    # 4. The second half, read as hard as a person can
    print("--- with it on, and being read throughout", flush=True)
    reading = Reading(args.url, password)
    reading.start()
    on, _ = play_all(args, plays, operator, approver, known)
    time.sleep(2)
    reading.stop.set()
    reading.join(30)
    compare(off, on, "off and on")
    check(reading.reads > 0, f"the panel was read while they played: {reading.reads} reads, {reading.statuses}")
    check(reading.statuses.get("ok", 0) > 0, "and those reads returned rows")
    check(not reading.errors, f"and none failed: {reading.errors[:3]}")

    # 5. What a read says, and that it adds nothing to the case
    _, cases = operator.call("GET", "/cases?limit=50")
    named = [c for c in cases["items"] if c.get("patientId") == patient and c.get("patientIdAuthority") == authority]
    if check(named, f"a case of {authority} {patient}"):
        quoted = urllib.parse.quote(named[0]["caseId"])
        _, before = operator.call("GET", f"/cases/{quoted}/events")
        status, body = operator.call("POST", f"/cases/{quoted}/warehouse-history")
        read = (body or {}).get("read") or {}
        check(status == 200 and read.get("status") == "ok", f"a read: {status} {read.get('status')} {read.get('category')}")
        check(read.get("batch") == "B1" and read.get("generation") == "G1" and read.get("dataset") == DATASET, "it names its batch")
        check(read.get("freshness") == "within" and 55 <= (read.get("ageMinutes") or 0) <= 720, f"it says how old: {read.get('ageMinutes')} minutes")
        check(read.get("rows") and read["rows"][0].get("ward") == "WARD-Z", "it has the published row")
        check("patient_id" not in json.dumps(read), "it does not repeat the patient")
        check(read.get("readBy") == "operator", "it names who read")
        _, after = operator.call("GET", f"/cases/{quoted}/events")
        check(before == after, "the case's timeline did not grow")
        status, again = operator.call("GET", f"/cases/{quoted}/warehouse-history")
        check(status == 200 and again.get("enabled") is True and again["read"]["resultDigest"] == read["resultDigest"], "the page reads the same back")
        # A batch marked ready with its rows missing, then a newer one that is right
        iris.sql("UPDATE ShutterWH.Batch SET PublishedRows = PublishedRows + 5 WHERE DatasetId = ? AND BatchId = 'B1'", DATASET)
        _, body = operator.call("POST", f"/cases/{quoted}/warehouse-history")
        check(body["read"]["status"] == "invalid" and body["read"]["category"] == "row_count_mismatch" and not body["read"]["rows"], "a batch short of its rows is refused")
        iris.sql("UPDATE ShutterWH.Batch SET PublishedRows = PublishedRows - 5 WHERE DatasetId = ? AND BatchId = 'B1'", DATASET)

        # The reader not answering: the supplement says so, and the case is as it was
        check(iris.call(f'##class(Shutter.Warehouse.Setup).Enable({q(DATASET)}, 360, 0, "localhost", 1)') == "ok", "Enable, at a port nothing listens on")
        status, body = operator.call("POST", f"/cases/{quoted}/warehouse-history")
        check(status == 200 and body["read"]["status"] == "unavailable" and body["read"]["category"] == "unreachable", f"unavailable: {status}")
        _, after = operator.call("GET", f"/cases/{quoted}/events")
        check(before == after, "and the case's timeline did not grow")

    # Switched off again: the supplement goes, nothing else moves
    check(iris.call("##class(Shutter.Warehouse.Setup).Disable()") == "ok", "Disable")
    status, body = operator.call("GET", f"/cases/{urllib.parse.quote(case_id)}/warehouse-history")
    check(status == 200 and body.get("enabled") is False and body.get("read") is None, "off again: the panel has nothing to show")
    check(iris.call("##class(Shutter.Warehouse.Setup).Remove()") == "ok", "Remove")
    status, _ = basic(args.url, READER_PATH + "/history" + query, READER, secret)
    check(status in (401, 403, 404), f"removed: the reader is gone: {status}")
    check(iris.call('##class(Shutter.Warehouse.Setup).TablesExist()') == "1", "the tables, the site's own, stay")

    print(f"{len(fails)} failed" if fails else "all checks passed", flush=True)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
