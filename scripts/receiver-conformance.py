#!/usr/bin/env python3
"""Tests Shutter's published recovery contract (docs/CONTRACTS.md, section 1) against one declared test endpoint.

    python3 scripts/receiver-conformance.py init --run-id ID --base-url URL --receiver-identity TEXT \
        --receiver-build TEXT --credential-scope TEXT --attestation TEXT > manifest.json
    python3 scripts/receiver-conformance.py run --manifest manifest.json --out DIR \
        [--confirm-origin ORIGIN] [--operator NAME] [--ca-file PEM] [--prior-report report.json]

It reports what this endpoint demonstrated on this build and configuration, check by check: pass, fail, not_run or
not_supported. It certifies nothing and enables nothing: a report has no authority over Shutter's gate.

What it refuses, whatever it is told (docs/receiver-conformance.md): anything but environment TEST and an origin confirmed
exactly; a redirect, an origin change or a failed TLS check; a path, a body or an identity it did not generate from the
manifest; an encounter or key that already exists; and every reset, fault or capability write. It deletes nothing, so what
it created stays on the endpoint, and the report lists it.

The credential comes from SHUTTER_CONFORMANCE_USER and SHUTTER_CONFORMANCE_PASSWORD, never from the manifest, and reaches
neither the journal nor the report. Exit status: 0 all required checks passed, 1 they did not, 2 the run was refused.
Standard library only.
"""
import argparse
import base64
import hashlib
import http.client
import importlib.util
import ipaddress
import json
import os
import re
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HERE = ROOT / "tests" / "conformance"
SCHEMA_FILE = HERE / "manifest.schema.json"
CONTRACTS_FILE = HERE / "contracts-v1.json"
STUB_FILE = HERE / "stubs" / "receiver_stub.py"

REQUIRED_ENCOUNTERS = 60
REQUIRED_BEDS = 40
MAX_BODY = 4 * 1024 * 1024
TIMEOUT = 30
INCONCLUSIVE_WAIT = 30
TIME_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z")
DIGEST_RE = re.compile(r"sha256:[0-9a-f]{64}")
OWN_CAPABILITIES = ("conditional_writes", "receipts", "history", "dry_run")

STATEMENT = "This report does not enable recovery, and it certifies nothing about the receiver."
LIMITATIONS = [
    "The kit cannot establish from a URL or a confirmation that the endpoint holds no real patients; isolation is the operator's and the supplier's responsibility.",
    "A pass describes this endpoint, build and configuration during this run, and nothing after it. Review it when the receiver, its adapter or the contract changes.",
    "Checks 17 to 19 send requests at the same moment from this machine; the kit cannot see whether they overlapped inside the receiver. A pass means no wrong result in the rounds run.",
    "Checks 22 and 23 lose and hold answers in the kit's own loopback proxy, which is not a network failure inside the receiver. They do not exercise Shutter's own read-back: tests/e2e/lost_answer_check.py and scenario S3 do.",
    "Check 23's timing is what was observed in this run; no maximum commit delay follows from it.",
    "Retention beyond the run remains the receiver's declaration (check 26).",
    "Cancels and merges are a declared extension. They are not sent and not claimed.",
]


class Refusal(Exception):
    """The run must not go ahead. Nothing further is sent."""


class StopRun(Exception):
    """A rule was broken mid-run: the check in hand fails and the rest are not run."""


class Inconclusive(Exception):
    """No answer to a direct read: the check in hand and the rest are not run, never passed."""


class Malformed(Exception):
    """An answer that is not what the contract gives: the check in hand fails."""


# --- the manifest -----------------------------------------------------------------------------------------------------


def schema_errors(value, schema, where="manifest"):
    """The subset of JSON Schema the manifest's schema uses."""
    errors = []
    if "const" in schema and value != schema["const"]:
        errors.append(f"{where} must be {schema['const']!r}")
    kind = schema.get("type")
    if kind == "object":
        if not isinstance(value, dict):
            return [f"{where} must be an object"]
        for name in schema.get("required", []):
            if name not in value:
                errors.append(f"{where}.{name} is required")
        for name, item in value.items():
            if name in schema.get("properties", {}):
                errors += schema_errors(item, schema["properties"][name], f"{where}.{name}")
            elif schema.get("additionalProperties") is False:
                errors.append(f"{where}.{name} is not a manifest field")
    elif kind == "array":
        if not isinstance(value, list):
            return [f"{where} must be a list"]
        if len(value) < schema.get("minItems", 0):
            errors.append(f"{where} needs at least {schema['minItems']}")
        if schema.get("uniqueItems") and len({json.dumps(v, sort_keys=True) for v in value}) != len(value):
            errors.append(f"{where} has a repeat")
        for n, item in enumerate(value):
            errors += schema_errors(item, schema.get("items", {}), f"{where}[{n}]")
    elif kind == "string":
        if not isinstance(value, str):
            return [f"{where} must be a string"]
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errors.append(f"{where} does not have the required form")
    return errors


def origin_of(url):
    parts = urllib.parse.urlsplit(url)
    return f"{parts.scheme}://{parts.netloc}"


def is_loopback(host):
    if host == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def check_manifest(manifest):
    """Refuses anything but a complete, self-consistent TEST manifest (rules 1, 2 and 4)."""
    errors = schema_errors(manifest, json.loads(SCHEMA_FILE.read_text()))
    if errors:
        raise Refusal("The manifest is refused: " + "; ".join(errors))
    parts = urllib.parse.urlsplit(manifest["base_url"])
    if parts.scheme == "http" and not is_loopback(parts.hostname or ""):
        raise Refusal("Plain http is refused except on loopback: a credential would cross the network unprotected")
    if origin_of(manifest["base_url"]) != manifest["allowed_origin"]:
        raise Refusal(f"The base URL's origin {origin_of(manifest['base_url'])} is not the allowed origin {manifest['allowed_origin']}")
    if len(manifest["encounters"]) < REQUIRED_ENCOUNTERS:
        raise Refusal(f"A run needs {REQUIRED_ENCOUNTERS} declared encounters; the manifest has {len(manifest['encounters'])}")
    if len(manifest["beds"]) < REQUIRED_BEDS:
        raise Refusal(f"A run needs {REQUIRED_BEDS} declared beds; the manifest has {len(manifest['beds'])}")
    ids = [e["id"] for e in manifest["encounters"]]
    patients = [e["patient_id"] for e in manifest["encounters"]]
    if len(set(ids)) != len(ids) or len(set(patients)) != len(patients):
        raise Refusal("Each declared encounter needs its own id and its own synthetic patient")


def make_manifest(run_id, base_url, receiver_identity, receiver_build, credential_scope, attestation):
    tag = re.sub(r"[^A-Za-z0-9._-]", "-", run_id)
    return {
        "environment": "TEST",
        "base_url": base_url.rstrip("/"),
        "allowed_origin": origin_of(base_url),
        "receiver_identity": receiver_identity,
        "receiver_build": receiver_build,
        "contract_version": "shutter-recovery-v1",
        "run_id": run_id,
        "source_system": "SHUTTER-CONFORMANCE",
        "patient_authority": "SHUTTER-TEST",
        "encounters": [{"id": f"SHUTTER-TEST-{tag}-{n:03d}", "patient_id": f"SYNTHETIC-{tag}-{n:03d}"} for n in range(1, REQUIRED_ENCOUNTERS + 1)],
        # The run's own wards and beds as well: nothing is cleaned up, so a bed from an earlier run stays occupied.
        "wards": [f"SHUTTER-TEST-{tag}-A", f"SHUTTER-TEST-{tag}-B"],
        "beds": [f"TEST-{tag}-{n:02d}" for n in range(1, REQUIRED_BEDS + 1)],
        "credential_scope": credential_scope,
        "isolation_attestation": attestation,
    }


def digest_text(text):
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()


def canonical(body):
    """The canonical payload of 1.6: these keys in this order, no whitespace, null for no ward."""
    fields = {name: body.get(name) for name in ("operation_key", "encounter_id", "patient_id", "patient_id_authority", "event")}
    fields["ward"] = body.get("ward") or None
    fields["event_time"] = body.get("event_time")
    fields["source_system"] = body.get("source_system")
    return json.dumps(fields, separators=(",", ":"), ensure_ascii=False)


# --- strict reading of an answer --------------------------------------------------------------------------------------


def no_repeats(pairs):
    out = {}
    for name, value in pairs:
        if name in out:
            raise ValueError(f"the key {name} appears twice")
        out[name] = value
    return out


def no_constants(name):
    raise ValueError(f"{name} is not JSON")


def strict_json(raw, content_type):
    """A JSON object from a JSON answer, or Malformed: no HTML page, repeated key, bare NaN or list passes."""
    if not content_type.lower().startswith("application/json"):
        raise Malformed(f"Content-Type is {content_type or 'absent'}, not JSON")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=no_repeats, parse_constant=no_constants)
    except ValueError as error:
        raise Malformed(f"not valid JSON: {error}") from None
    if not isinstance(value, dict):
        raise Malformed("not a JSON object")
    return value


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def optional_text(value):
    return value is None or isinstance(value, str)


def require(condition, what):
    if not condition:
        raise Malformed(what)


class Reply:
    def __init__(self, status, raw, content_type, seq, seconds):
        self.status, self.raw, self.content_type, self.seq, self.seconds = status, raw, content_type, seq, seconds

    def json(self):
        return strict_json(self.raw, self.content_type)

    def error(self):
        try:
            return self.json().get("error")
        except Malformed:
            return None


def valid_history_row(row):
    require(isinstance(row, dict), "a history row is not an object")
    for name in ("version_after", "event", "event_time", "applied_at", "operation_key"):
        require(name in row, f"a history row has no {name}")
    require(is_int(row["version_after"]), "version_after is not a whole number")
    require(row["event"] in ("admit", "transfer", "discharge", "update"), "a history row's event is not one of the four")
    require(optional_text(row.get("ward")) and optional_text(row.get("bed")), "a history row's ward or bed is not text or null")
    require(isinstance(row["event_time"], str) and TIME_RE.fullmatch(row["event_time"]), "a history row's event_time is not ISO 8601 UTC")
    require("ward" in row and "bed" in row, "a history row has no ward or bed")


def valid_encounter(obj, encounter_id, patient_id, authority):
    """Rule 7: another identity stops the run. A wrong shape, or a history with a gap, fails the check."""
    require(isinstance(obj, dict), "the encounter is not an object")
    if obj.get("encounter_id") != encounter_id:
        raise StopRun(f"Asked for {encounter_id}, the receiver answered for {obj.get('encounter_id')!r}: the run stops")
    if obj.get("patient_id") != patient_id or obj.get("patient_id_authority") != authority:
        raise StopRun(f"The encounter {encounter_id} answered with another patient identity: the run stops")
    require(obj.get("state") in ("admitted", "discharged"), "state is not admitted or discharged")
    require(is_int(obj.get("version")) and obj["version"] >= 1, "version is not a whole number from 1")
    require(is_int(obj.get("epoch")), "the encounter has no integer epoch (1.8)")
    require("ward" in obj and "bed" in obj, "the encounter has no ward or bed field")
    require(optional_text(obj["ward"]) and optional_text(obj["bed"]), "ward or bed is not text or null")
    require(isinstance(obj.get("updated_at"), str), "updated_at is not text")
    history = obj.get("history")
    require(isinstance(history, list), "history is not a list")
    for row in history:
        valid_history_row(row)
    require([row["version_after"] for row in history] == list(range(1, obj["version"] + 1)), "the history is not versions 1 to the encounter's version, in order")
    if obj["state"] == "discharged":
        require(obj["ward"] is None and obj["bed"] is None, "a discharged encounter still has a ward or bed")
    return obj


def valid_receipt(obj, key):
    require(isinstance(obj, dict), "the receipt is not an object")
    if obj.get("operation_key") != key:
        raise StopRun(f"Asked for the receipt of {key}, the receiver answered for {obj.get('operation_key')!r}: the run stops")
    for name in ("encounter_id", "event", "event_time", "applied_at", "payload_digest", "status"):
        require(isinstance(obj.get(name), str), f"the receipt has no {name}")
    require("ward" in obj and "bed" in obj, "the receipt has no ward or bed field")
    require(optional_text(obj["ward"]) and optional_text(obj["bed"]), "the receipt's ward or bed is not text or null")
    require(is_int(obj.get("version_before")) and is_int(obj.get("version_after")), "the receipt's versions are not whole numbers")
    require(obj["version_after"] == obj["version_before"] + 1, "the receipt's versions are not one apart")
    require(DIGEST_RE.fullmatch(obj["payload_digest"]), "the receipt's digest is not sha256:<hex>")
    require(obj["status"] == "committed", "the receipt's status is not committed")
    require(is_int(obj.get("epoch")), "the receipt has no integer epoch (1.8)")
    return obj


def classify_receipt(reply, key):
    """present, absent or unknown. Only the exact 404 is absence: a 503, an HTML page or no answer at all says nothing."""
    if reply is None:
        return "unknown", None
    if reply.status == 200:
        return "present", valid_receipt(reply.json(), key)
    if reply.status == 404:
        try:
            if reply.json().get("error") == "no_receipt":
                return "absent", None
        except Malformed:
            pass
    return "unknown", None


# --- the only way out to the receiver ---------------------------------------------------------------------------------


class Journal:
    """Append-only: one JSON line per exchange, chained by digest, with the credential never written."""

    def __init__(self, path, secrets):
        self.file = open(path, "x", encoding="utf-8")
        self.secrets = [s for s in secrets if s]
        self.lock = threading.Lock()
        self.seq = 0
        self.chain = hashlib.sha256(b"receiver-conformance").hexdigest()

    def redact(self, text):
        for secret in self.secrets:
            text = text.replace(secret, "[redacted]")
        return text

    def write(self, entry):
        with self.lock:
            self.seq += 1
            entry = dict(entry, seq=self.seq, at=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"))
            line = self.redact(json.dumps(entry, ensure_ascii=False, sort_keys=True))
            self.chain = hashlib.sha256((self.chain + line).encode("utf-8")).hexdigest()
            self.file.write(line + "\n")
            self.file.flush()
            return self.seq

    def close(self):
        self.file.close()


class Transport:
    """Method and path are checked against what the kit may ever do; a redirect is refused and never followed."""

    def __init__(self, manifest, journal, credential, ca_file=None):
        parts = urllib.parse.urlsplit(manifest["base_url"])
        self.https = parts.scheme == "https"
        self.host, self.port = parts.hostname, parts.port or (443 if self.https else 80)
        self.base = parts.path.rstrip("/")
        self.journal = journal
        self.auth = None
        if credential:
            self.auth = "Basic " + base64.b64encode(f"{credential[0]}:{credential[1]}".encode()).decode()
        self.encounters = {e["id"] for e in manifest["encounters"]}
        self.keys = set()
        self.fingerprint = None
        self.tls = None
        if self.https:
            self.tls = ssl.create_default_context(cafile=ca_file)

    def allowed(self, method, path):
        if method == "GET" and path == "/capabilities":
            return True
        if method == "POST" and path == "/operations":
            return True
        if method == "GET" and path.startswith("/encounters/"):
            return urllib.parse.unquote(path[len("/encounters/"):]) in self.encounters
        if method == "GET" and path.startswith("/receipts/"):
            return urllib.parse.unquote(path[len("/receipts/"):]) in self.keys
        return False

    def connection(self, timeout):
        if self.https:
            return http.client.HTTPSConnection(self.host, self.port, timeout=timeout, context=self.tls)
        return http.client.HTTPConnection(self.host, self.port, timeout=timeout)

    def request(self, method, path, body=None, timeout=TIMEOUT, via="direct"):
        if not self.allowed(method, path):
            raise StopRun(f"The kit refuses {method} {path}: not a route it may call, or an identity it did not declare")
        headers = {"Accept": "application/json", "Connection": "close"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        if self.auth:
            headers["Authorization"] = self.auth
        started = time.monotonic()
        connection = self.connection(timeout)
        sent = None if body is None else body.decode("utf-8", "replace")
        try:
            connection.request(method, self.base + path, body=body, headers=headers)
            self.pin(connection)
            response = connection.getresponse()
            raw = response.read(MAX_BODY + 1)
        except ssl.SSLCertVerificationError as error:
            self.journal.write({"method": method, "path": path, "via": via, "body": sent, "failure": f"TLS: {error.verify_message}"})
            raise Refusal(f"TLS verification failed for {self.host}: {error.verify_message}") from None
        except (OSError, http.client.HTTPException) as error:
            seq = self.journal.write({"method": method, "path": path, "via": via, "body": sent, "failure": type(error).__name__, "seconds": round(time.monotonic() - started, 3)})
            raise Inconclusive(f"No answer to {method} {path} ({type(error).__name__}; journal {seq})") from None
        finally:
            connection.close()
        seconds = round(time.monotonic() - started, 3)
        content_type = response.getheader("Content-Type") or ""
        location = response.getheader("Location")
        seq = self.journal.write({"method": method, "path": path, "via": via, "body": sent, "status": response.status, "content_type": content_type, "location": location, "answer": raw[:MAX_BODY].decode("utf-8", "replace"), "seconds": seconds})
        if len(raw) > MAX_BODY:
            raise Malformed(f"The answer is over {MAX_BODY} bytes")
        if 300 <= response.status < 400:
            raise StopRun(f"The receiver answered {response.status} to {location!r}: a redirect is refused and was not followed")
        if response.status in (401, 403, 407):
            raise StopRun(f"The receiver answered {response.status}: the credential is not accepted for this route")
        return Reply(response.status, raw, content_type, seq, seconds)

    def pin(self, connection):
        """The certificate of the first answer stays for the run: another one is an origin change."""
        if not self.https or connection.sock is None:
            return
        seen = hashlib.sha256(connection.sock.getpeercert(True)).hexdigest()
        if self.fingerprint is None:
            self.fingerprint = seen
        elif seen != self.fingerprint:
            raise StopRun("The receiver's certificate changed during the run: refused")


class Proxy:
    """A loopback hand between the kit and the receiver, for checks 22 and 23: it loses or holds answers."""

    def __init__(self, transport, mode, hold=0):
        proxy = self
        self.finished = threading.Event()

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def answer(self, reply):
                try:
                    self.send_response(reply[0])
                    self.send_header("Content-Type", reply[2])
                    self.send_header("Content-Length", str(len(reply[1])))
                    self.send_header("Connection", "close")
                    self.end_headers()
                    self.wfile.write(reply[1])
                except OSError:
                    pass

            def forward(self, body):
                try:
                    got = transport.request(self.command, self.path, body=body, via=f"proxy:{mode}")
                    return (got.status, got.raw, got.content_type)
                finally:
                    proxy.finished.set()

            def serve(self):
                length = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(length) if length else None
                self.close_connection = True
                if mode == "drop":
                    self.forward(body)
                elif mode == "hold_write":
                    time.sleep(hold)
                    self.answer(self.forward(body))
                elif mode == "hold_answer":
                    reply = self.forward(body)
                    time.sleep(hold)
                    self.answer(reply)
                elif mode == "receipt_503" and self.path.startswith("/receipts/"):
                    self.answer((503, b'{"error": "ward_unavailable"}', "application/json"))
                else:
                    self.answer(self.forward(body))

            do_GET = do_POST = serve

        class Server(ThreadingHTTPServer):
            daemon_threads = True

            def handle_error(self, request, client_address):
                pass

        self.server = Server(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def call(self, method, path, body=None, timeout=TIMEOUT):
        """What the sender sees: a Reply, or None when no answer came."""
        started = time.monotonic()
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_address[1], timeout=timeout)
        try:
            connection.request(method, path, body=body, headers={"Content-Type": "application/json"} if body else {})
            response = connection.getresponse()
            return Reply(response.status, response.read(), response.getheader("Content-Type") or "", 0, round(time.monotonic() - started, 3))
        except (OSError, http.client.HTTPException):
            return None
        finally:
            connection.close()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


# --- the run ----------------------------------------------------------------------------------------------------------


class Run:
    def __init__(self, manifest, out, credential=None, ca_file=None, prior_report=None, confirmation="unit"):
        self.manifest = manifest
        self.out = Path(out)
        self.confirmation = confirmation
        self.prior_report = prior_report
        self.journal = Journal(self.out / "journal.jsonl", list(credential or []))
        self.api = Transport(manifest, self.journal, credential, ca_file)
        self.patients = {e["id"]: e["patient_id"] for e in manifest["encounters"]}
        self.free_encounters = list(self.patients)
        self.free_beds = list(manifest["beds"])
        self.wards = manifest["wards"]
        self.clock = datetime(2026, 1, 1, tzinfo=timezone.utc)
        self.counter = 0
        self.check_id = 0
        self.subs = []
        self.ledger = []
        self.versions = {}
        self.touched = []
        self.confirmed_absent = set()
        self.capabilities = None
        self.lock = threading.Lock()

    # Identities

    def encounter(self):
        if not self.free_encounters:
            raise Refusal("The declared encounters ran out")
        encounter = self.free_encounters.pop(0)
        self.touched.append(encounter)
        return encounter

    def bed(self):
        if not self.free_beds:
            raise Refusal("The declared beds ran out")
        return self.free_beds.pop(0)

    def tick(self):
        self.clock += timedelta(minutes=1)
        return self.clock.strftime("%Y-%m-%dT%H:%M:%SZ")

    def build(self, encounter, event, ward=None, bed=None, expected=None, dry=False, digest=None):
        """An operation from the manifest's identities, with its own generated key (rules 3 and 4)."""
        with self.lock:
            self.counter += 1
            when = self.tick()
            serial = self.counter
        patient = self.patients[encounter]
        key = "^".join((self.manifest["source_system"], self.manifest["patient_authority"], patient, encounter, event, when))
        require(len(key) <= 255, "the generated key is over 255 characters")
        body = {
            "operation_key": key,
            "encounter_id": encounter,
            "patient_id": patient,
            "patient_id_authority": self.manifest["patient_authority"],
            "event": event,
            "ward": ward,
            "event_time": when,
            "source_system": self.manifest["source_system"],
            "source_message_id": f"{self.manifest['run_id']}-C{self.check_id:02d}-{serial}",
            "dry_run": dry,
        }
        if bed is not None:
            body["bed"] = bed
        if expected is not None:
            body["expected_version"] = expected
        body["payload_digest"] = digest or digest_text(canonical(body))
        self.api.keys.add(key)
        return body

    def guard(self, body):
        """Rule 4: only declared pairs, wards and beds and generated keys leave the kit."""
        encounter, patient = body["encounter_id"], body["patient_id"]
        if encounter not in self.patients or patient not in self.patients.values():
            raise StopRun(f"The kit refuses an undeclared identity: {encounter}, {patient}")
        if body.get("ward") is not None and body["ward"] not in self.wards:
            raise StopRun(f"The kit refuses an undeclared ward: {body['ward']}")
        if body.get("bed") is not None and body["bed"] not in self.manifest["beds"]:
            raise StopRun(f"The kit refuses an undeclared bed: {body['bed']}")
        if body["operation_key"] not in self.api.keys:
            raise StopRun("The kit refuses a key it did not generate")

    def ensure_absent(self, key):
        """Rule 5: a key is shown to be absent before anything can create it."""
        if key in self.confirmed_absent:
            return
        state, _ = classify_receipt(self.api.request("GET", self.receipt_path(key)), key)
        if state != "absent":
            raise StopRun(f"The generated key {key} could not be shown absent ({state}): the run stops")
        self.confirmed_absent.add(key)

    # Reads

    def receipt_path(self, key):
        return "/receipts/" + urllib.parse.quote(key, safe="")

    def read_encounter(self, encounter):
        """The encounter, or None for the exact 404. Anything else fails the check."""
        reply = self.api.request("GET", "/encounters/" + urllib.parse.quote(encounter, safe=""))
        if reply.status == 200:
            return valid_encounter(reply.json(), encounter, self.patients[encounter], self.manifest["patient_authority"])
        require(reply.status == 404, f"reading an encounter answered {reply.status}")
        require(reply.json().get("error") == "unknown_encounter", "the 404 is not unknown_encounter")
        return None

    def read_receipt(self, key):
        """The receipt, or None for the exact 404. Anything else fails the check."""
        reply = self.api.request("GET", self.receipt_path(key))
        state, receipt = classify_receipt(reply, key)
        require(state != "unknown", f"reading a receipt answered {reply.status} {reply.raw[:80]!r}")
        return receipt

    # Writes

    def post(self, body):
        self.guard(body)
        if not body.get("dry_run"):
            self.ensure_absent(body["operation_key"])
        return self.send(body)

    def send(self, body):
        reply = self.api.request("POST", "/operations", json.dumps(body, ensure_ascii=False).encode("utf-8"))
        self.check_occupant(reply)
        return reply

    def check_occupant(self, reply):
        """Rule 8: an occupied bed held by anyone undeclared means this is not the isolated endpoint it was said to be."""
        if reply.status != 409 or reply.error() != "bed_occupied":
            return
        holder = reply.json().get("occupant")
        require(isinstance(holder, dict), "bed_occupied has no occupant")
        if holder.get("encounter_id") not in self.patients:
            raise StopRun(f"An occupied bed names {holder.get('encounter_id')!r}, outside the declared set: the run stops")

    def record(self, body):
        """Reads back a committed operation and keeps what was seen, for checks 21 and 26."""
        encounter = self.read_encounter(body["encounter_id"])
        receipt = self.read_receipt(body["operation_key"])
        require(encounter is not None, "a committed operation's encounter cannot be read")
        require(receipt is not None, "a committed operation has no receipt")
        self.versions[body["encounter_id"]] = encounter["version"]
        rows = [row for row in encounter["history"] if row["operation_key"] == body["operation_key"]]
        self.ledger.append({"body": body, "receipt": receipt, "encounter": encounter, "rows": rows})
        return encounter, receipt

    def commit(self, body):
        """A write the check needs to succeed: 201, or the check fails."""
        reply = self.post(body)
        require(reply.status == 201, f"{body['event']} of {body['encounter_id']} answered {reply.status}, not 201: {reply.raw[:160]!r}")
        answer = reply.json()
        require(answer.get("applied") is True, "the 201 does not say applied true")
        valid_receipt(answer.get("receipt"), body["operation_key"])
        valid_encounter(answer.get("encounter"), body["encounter_id"], self.patients[body["encounter_id"]], self.manifest["patient_authority"])
        encounter, receipt = self.record(body)
        return encounter, receipt, answer

    def place(self, encounter, event, ward=None, bed=None):
        return self.commit(self.build(encounter, event, ward, bed, self.versions.get(encounter, 0)))

    def admitted(self, ward=None, bed=None):
        encounter = self.encounter()
        return (encounter, *self.place(encounter, "admit", ward or self.wards[0], bed)[:2])

    # Results

    def sub(self, name, ok, detail=""):
        self.subs.append({"name": name, "status": "pass" if ok else "fail", "detail": "" if ok else str(detail)})
        return ok

    def note(self, text):
        self.subs.append({"name": text, "status": "note", "detail": ""})

    def not_run(self, name, detail=""):
        self.subs.append({"name": name, "status": "not_run", "detail": detail})

    def snapshot(self, encounter):
        return encounter, self.read_encounter(encounter)

    def unchanged(self, name, snap, *absent_keys):
        now = self.read_encounter(snap[0])
        self.sub(f"{name}: the encounter is unchanged", now == snap[1], f"was {snap[1]}, now {now}")
        for key in absent_keys:
            self.sub(f"{name}: no receipt", self.read_receipt(key) is None, key)

    def refused(self, name, reply, status, error):
        answer = None
        try:
            answer = reply.json()
        except Malformed as problem:
            self.sub(f"{name}: {status} {error}", False, problem)
            return {}
        self.sub(f"{name}: {status} {error}", reply.status == status and answer.get("error") == error, f"{reply.status} {reply.raw[:160]!r}")
        return answer

    def would_not(self, name, reply, reason):
        try:
            answer = reply.json()
        except Malformed as problem:
            self.sub(f"{name}: would not apply", False, problem)
            return
        ok = reply.status == 200 and answer.get("rehearsal") is True and answer.get("would_apply") is False and answer.get("applied") is False and answer.get("reason") == reason and is_int(answer.get("epoch"))
        self.sub(f"{name}: 200, would not apply, {reason}", ok, f"{reply.status} {reply.raw[:200]!r}")

    def together(self, *calls, stagger=(0, 0)):
        """Runs the calls at one moment, each on its own connection. A call's exception comes back as its result."""
        barrier = threading.Barrier(len(calls))
        results = [None] * len(calls)

        def one(n, call):
            barrier.wait()
            if stagger[n]:
                time.sleep(stagger[n])
            try:
                results[n] = call()
            except (StopRun, Inconclusive, Malformed, Refusal) as problem:
                results[n] = problem

        threads = [threading.Thread(target=one, args=(n, call)) for n, call in enumerate(calls)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        for result in results:
            if isinstance(result, Exception):
                raise result
        return results


# --- the numbered checks ----------------------------------------------------------------------------------------------


def c01(r):
    reply = r.api.request("GET", "/capabilities")
    require(reply.status == 200, f"GET /capabilities answered {reply.status}")
    caps = reply.json()
    r.capabilities = caps
    for name in OWN_CAPABILITIES:
        r.sub(f"declares {name}", caps.get(name) is True, caps.get(name))
    r.sub("an integer epoch", is_int(caps.get("epoch")), caps.get("epoch"))
    r.sub("a retention statement", isinstance(caps.get("receipt_retention"), str) and caps["receipt_retention"] != "", caps.get("receipt_retention"))
    r.sub("an idempotency statement", isinstance(caps.get("idempotency"), str) and caps["idempotency"] != "", caps.get("idempotency"))
    r.note(f"declared retention: {caps.get('receipt_retention')}; epoch {caps.get('epoch')}")


def c02(r):
    encounter = r.free_encounters[0]
    key = "^".join((r.manifest["source_system"], r.manifest["patient_authority"], r.patients[encounter], encounter, "admit", "2026-01-01T00:00:00Z"))
    r.api.keys.add(key)
    r.sub("an unknown encounter answers exactly 404 unknown_encounter", r.read_encounter(encounter) is None)
    r.sub("an unknown receipt answers exactly 404 no_receipt", r.read_receipt(key) is None)


def c03(r):
    encounter = r.encounter()
    bed = r.bed()
    body = r.build(encounter, "admit", r.wards[0], bed, 0, dry=True)
    reply = r.post(body)
    require(reply.status == 200, f"the dry run answered {reply.status}, not 200")
    answer = reply.json()
    r.sub("rehearsal, would apply, not applied", answer.get("rehearsal") is True and answer.get("would_apply") is True and answer.get("applied") is False, answer)
    r.sub("the state before is absent", "encounter_before" in answer and answer["encounter_before"] is None, answer.get("encounter_before"))
    after = answer.get("encounter_after")
    r.sub("the predicted state is consistent", isinstance(after, dict) and after.get("state") == "admitted" and after.get("ward") == r.wards[0] and after.get("bed") == bed and after.get("version") == 1, after)
    r.sub("an integer epoch", is_int(answer.get("epoch")), answer.get("epoch"))
    r.sub("afterwards no encounter", r.read_encounter(encounter) is None)
    r.sub("afterwards no receipt", r.read_receipt(body["operation_key"]) is None)


def matches_sent(body, receipt):
    """The fields a receipt must carry from what was sent; check 21 compares more."""
    return (
        receipt["encounter_id"] == body["encounter_id"]
        and receipt["event"] == body["event"]
        and receipt["ward"] == body["ward"]
        and receipt["bed"] == body.get("bed")
    )


def c04(r):
    encounter = r.encounter()
    bed = r.bed()
    body = r.build(encounter, "admit", r.wards[0], bed, 0)
    reply = r.post(body)
    r.sub("201", reply.status == 201, reply.status)
    answer = reply.json()
    r.sub("applied true", answer.get("applied") is True, answer.get("applied"))
    returned = valid_receipt(answer.get("receipt"), body["operation_key"])
    r.sub("the answer's receipt matches what was sent", matches_sent(body, returned), returned)
    held, receipt = r.record(body)
    r.sub("one admitted state at version 1", held["state"] == "admitted" and held["version"] == 1 and held["ward"] == r.wards[0] and held["bed"] == bed, held)
    r.sub("one history row", len(held["history"]) == 1 and held["history"][0]["operation_key"] == body["operation_key"], held["history"])
    r.sub("the receipt read matches what was sent", matches_sent(body, receipt), receipt)
    r.sub("the receipt is versions 0 to 1", receipt["version_before"] == 0 and receipt["version_after"] == 1, receipt)
    r.sub("the receipt carries the sent digest", receipt["payload_digest"] == body["payload_digest"], receipt["payload_digest"])
    r.sub("the answer and the read agree", returned == receipt, f"{returned} / {receipt}")


def c05(r):
    encounter = r.encounter()
    body = r.build(encounter, "admit", r.wards[0], r.bed(), 0)
    held, first, _ = r.commit(body)
    r.versions[encounter] = held["version"]
    r.place(encounter, "update")
    before = r.read_encounter(encounter)
    repeat = dict(body, source_message_id=body["source_message_id"] + "-again", expected_version=0)
    reply = r.post(repeat)
    r.sub("200", reply.status == 200, f"{reply.status} {reply.raw[:160]!r}")
    if reply.status == 200:
        answer = reply.json()
        r.sub("already_committed, not applied", answer.get("applied") is False and answer.get("reason") == "already_committed", answer)
        r.sub("the original receipt", answer.get("receipt") == first, f"{answer.get('receipt')} / {first}")
    after = r.read_encounter(encounter)
    r.sub("no new version or history row", after == before, f"{before} / {after}")
    r.sub("the receipt read is unchanged", r.read_receipt(body["operation_key"]) == first)


def c06(r):
    encounter = r.encounter()
    body = r.build(encounter, "admit", r.wards[0], None, 0)
    _, first, _ = r.commit(body)
    snap = r.snapshot(encounter)
    changed = dict(body, ward=r.wards[1])
    changed["payload_digest"] = digest_text(canonical(changed))
    answer = r.refused("the same key, another ward", r.post(changed), 409, "key_reused_with_different_payload")
    r.sub("names the key", answer.get("operation_key") == body["operation_key"], answer)
    r.unchanged("after the refusal", snap)
    r.sub("the receipt is unchanged", r.read_receipt(body["operation_key"]) == first)


def c07(r):
    encounter = r.encounter()
    r.place(encounter, "admit", r.wards[0])
    snap = r.snapshot(encounter)
    body = r.build(encounter, "transfer", r.wards[1], None, 1, digest="sha256:" + "0" * 64)
    r.refused("a wrong digest", r.post(body), 422, "payload_digest_mismatch")
    r.unchanged("after the refusal", snap, body["operation_key"])


def c08(r):
    encounter = r.encounter()
    r.place(encounter, "admit", r.wards[0])
    snap = r.snapshot(encounter)
    body = r.build(encounter, "transfer", r.wards[1], None, 5)
    answer = r.refused("the wrong version", r.post(body), 409, "version_conflict")
    r.sub("reports the expected version", answer.get("expected_version") == 5, answer)
    r.sub("reports the correct current version", answer.get("current_version") == 1, answer)
    r.unchanged("after the refusal", snap, body["operation_key"])


def c09(r):
    encounter = r.encounter()
    other = r.encounter()
    r.place(encounter, "admit", r.wards[0])
    snap = r.snapshot(encounter)
    body = r.build(encounter, "transfer", r.wards[1], None, 1)
    body["patient_id"] = r.patients[other]
    body["payload_digest"] = digest_text(canonical(body))
    answer = r.refused("another declared patient", r.post(body), 422, "patient_mismatch")
    r.sub("names the encounter", answer.get("encounter_id") == encounter, answer)
    r.unchanged("after the refusal", snap, body["operation_key"])


def c10(r):
    for event, ward in (("transfer", r.wards[0]), ("update", None), ("discharge", None)):
        encounter = r.encounter()
        body = r.build(encounter, event, ward)
        answer = r.refused(event, r.post(body), 422, "unknown_encounter")
        r.sub(f"{event}: names the encounter", answer.get("encounter_id") == encounter, answer)
        r.sub(f"{event}: no encounter is created", r.read_encounter(encounter) is None)
        r.sub(f"{event}: no receipt", r.read_receipt(body["operation_key"]) is None)


def c11(r):
    encounter = r.encounter()
    r.place(encounter, "admit", r.wards[0])
    fresh = r.encounter()
    snap = r.snapshot(encounter)

    def template(event="transfer", who=encounter, ward=r.wards[1], **changes):
        body = r.build(who, event, ward)
        body.pop("payload_digest")
        body.update(changes)
        return body

    cases = [(f"missing {name}", {name: None}) for name in ("encounter_id", "patient_id", "patient_id_authority", "event", "event_time", "source_system", "operation_key")]
    for name, changes in cases:
        body = template()
        key = body["operation_key"]
        for field in changes:
            del body[field]
        r.refused(name, malformed(r, body), 422, "invalid_request")
        r.unchanged(name, snap, *([] if "operation_key" in changes else [key]))
    long_bed = "B" * 65
    for name, body in (
        ("an event that is not one of the four", template(event="relocate")),
        ("a transfer with no ward", template(ward=None)),
        ("an update with a ward", template(event="update")),
        ("a discharge with a ward", template(event="discharge")),
        ("a bed that is a number", template(bed=7)),
        ("a bed that is empty", template(bed="")),
        ("a bed of 65 characters", template(bed=long_bed)),
        ("an update with a bed", template(event="update", ward=None, bed=r.manifest["beds"][-1])),
        ("a discharge with a bed", template(event="discharge", ward=None, bed=r.manifest["beds"][-1])),
        ("an event time with no Z", template(event_time="2026-01-01T00:00:00")),
        ("an expected version that is not a number", template(expected_version="soon")),
    ):
        r.refused(name, malformed(r, body), 422, "invalid_request")
        r.unchanged(name, snap, body["operation_key"])
    admit = template(event="admit", who=fresh, ward=None)
    r.refused("an admission with no ward", malformed(r, admit), 422, "invalid_request")
    r.sub("an admission with no ward: no encounter", r.read_encounter(fresh) is None)
    for name, raw in (("a body that is not JSON", b"not json"), ("a body that is a list", b"[]")):
        r.refused(name, r.send_raw(raw), 422, "invalid_request")
        r.unchanged(name, snap)


def malformed(r, body):
    """A deliberately wrong request from the table above: declared identities and a generated key, and never a repeat."""
    key = body.get("operation_key")
    if key is not None:
        r.ensure_absent(key)
    reply = r.api.request("POST", "/operations", json.dumps(body, ensure_ascii=False).encode("utf-8"))
    r.check_occupant(reply)
    return reply


def send_raw(self, raw):
    return self.api.request("POST", "/operations", raw)


Run.send_raw = send_raw


def c12(r):
    encounter = r.encounter()
    bed_one, bed_two = r.bed(), r.bed()
    r.place(encounter, "admit", r.wards[0], bed_one)
    held, receipt, _ = r.place(encounter, "transfer", r.wards[1], bed_two)
    r.sub("a transfer changes the placement", held["ward"] == r.wards[1] and held["bed"] == bed_two and held["version"] == 2, held)
    r.sub("a transfer's receipt", receipt["version_before"] == 1 and receipt["version_after"] == 2 and receipt["bed"] == bed_two, receipt)
    held, receipt, _ = r.place(encounter, "update")
    r.sub("an update changes no placement", held["ward"] == r.wards[1] and held["bed"] == bed_two and held["version"] == 3, held)
    r.sub("an update's history row has no ward or bed", held["history"][2]["ward"] is None and held["history"][2]["bed"] is None, held["history"][2])
    held, receipt, _ = r.place(encounter, "discharge")
    r.sub("a discharge clears the placement", held["state"] == "discharged" and held["ward"] is None and held["bed"] is None and held["version"] == 4, held)
    r.sub("four rows in order", [row["event"] for row in held["history"]] == ["admit", "transfer", "update", "discharge"], held["history"])


def c13(r):
    encounter = r.encounter()
    r.place(encounter, "admit", r.wards[0])
    snap = r.snapshot(encounter)
    body = r.build(encounter, "admit", r.wards[1], None, 1)
    answer = r.refused("admit an admitted encounter", r.post(body), 422, "invalid_transition")
    r.sub("names state and event", answer.get("state") == "admitted" and answer.get("event") == "admit", answer)
    r.unchanged("after the refusal", snap, body["operation_key"])
    r.place(encounter, "discharge")
    snap = r.snapshot(encounter)
    for event, ward in (("transfer", r.wards[1]), ("update", None), ("discharge", None), ("admit", r.wards[0])):
        body = r.build(encounter, event, ward, None, 2)
        answer = r.refused(f"{event} after a discharge", r.post(body), 422, "invalid_transition")
        r.sub(f"{event} after a discharge: names state and event", answer.get("state") == "discharged" and answer.get("event") == event, answer)
        r.unchanged(f"{event} after a discharge", snap, body["operation_key"])


def c14(r):
    holder, bed = r.encounter(), r.bed()
    ward = r.wards[0]
    held, _, _ = r.place(holder, "admit", ward, bed)
    held, _, _ = r.place(holder, "update")
    placement_time = held["history"][0]["event_time"]
    snap = r.snapshot(holder)
    newcomer = r.encounter()
    for name, dry in (("a real placement", False), ("a dry run", True)):
        body = r.build(newcomer, "admit", ward, bed, 0, dry=dry)
        answer = r.refused(name, r.post(body), 409, "bed_occupied")
        holder_seen = answer.get("occupant") or {}
        r.sub(f"{name}: names the occupant", holder_seen.get("encounter_id") == holder, answer)
        r.sub(f"{name}: the occupant's since is its placement", holder_seen.get("since") == placement_time, holder_seen)
        r.sub(f"{name}: the occupant's version", holder_seen.get("version") == held["version"], holder_seen)
        r.sub(f"{name}: no patient identifiers", set(holder_seen) <= {"encounter_id", "since", "version"}, holder_seen)
        r.sub(f"{name}: ward, bed, key, not applied", answer.get("ward") == ward and answer.get("bed") == bed and answer.get("operation_key") == body["operation_key"] and answer.get("applied") is False, answer)
        r.unchanged(name, snap, body["operation_key"])
        r.sub(f"{name}: the newcomer has no record", r.read_encounter(newcomer) is None)


def c15(r):
    ward, other_ward = r.wards[0], r.wards[1]
    first, second = r.encounter(), r.encounter()
    bed_x, bed_y = r.bed(), r.bed()
    r.place(first, "admit", ward, bed_x)
    r.place(first, "transfer", ward, bed_y)
    held, _, _ = r.place(second, "admit", ward, bed_x)
    r.sub("a transfer out frees the bed", held["bed"] == bed_x, held)
    held, _, _ = r.place(second, "transfer", ward, bed_x)
    r.sub("the encounter's own bed is no conflict, and the version still moves", held["bed"] == bed_x and held["version"] == 2, held)
    r.place(first, "transfer", ward)
    third = r.encounter()
    held, _, _ = r.place(third, "admit", ward, bed_y)
    r.sub("a transfer to ward level frees the bed", held["bed"] == bed_y, held)
    level_one, level_two = r.encounter(), r.encounter()
    r.place(level_one, "admit", ward)
    held, _, _ = r.place(level_two, "admit", ward)
    r.sub("two ward-level placements never conflict", held["bed"] is None, held)
    shared = r.bed()
    here, there = r.encounter(), r.encounter()
    r.place(here, "admit", ward, shared)
    held, _, _ = r.place(there, "admit", other_ward, shared)
    r.sub("the same bed name on another ward is another bed", held["ward"] == other_ward and held["bed"] == shared, held)
    r.place(here, "discharge")
    after = r.encounter()
    held, _, _ = r.place(after, "admit", ward, shared)
    r.sub("a discharge frees the bed", held["bed"] == shared, held)


def c16(r):
    encounter = r.encounter()
    original, other = r.bed(), r.bed()
    body = r.build(encounter, "admit", r.wards[0], original, 0)
    _, first, _ = r.commit(body)
    before = r.read_encounter(encounter)
    repeat = dict(body, bed=other)
    reply = r.post(repeat)
    r.sub("200", reply.status == 200, f"{reply.status} {reply.raw[:160]!r}")
    if reply.status == 200:
        answer = reply.json()
        r.sub("already_committed", answer.get("reason") == "already_committed" and answer.get("applied") is False, answer)
        r.sub("the receipt shows the original bed", (answer.get("receipt") or {}).get("bed") == original, answer.get("receipt"))
    r.sub("the encounter keeps the original bed", r.read_encounter(encounter) == before)
    r.sub("the receipt read is unchanged", r.read_receipt(body["operation_key"]) == first)
    r.note("The bed is outside the payload digest (1.6), so a conforming receiver answers this as a repeat. A sender must compare the receipt's bed: conforming here does not make such a sender safe.")


def c17(r):
    encounter = r.encounter()
    r.place(encounter, "admit", r.wards[0])
    for round_number in range(1, 4):
        version = r.versions[encounter]
        one = r.build(encounter, "transfer", r.wards[1], None, version)
        two = r.build(encounter, "transfer", r.wards[0], None, version)
        r.ensure_absent(one["operation_key"])
        r.ensure_absent(two["operation_key"])
        replies = r.together(lambda: r.send(one), lambda: r.send(two))
        statuses = sorted(reply.status for reply in replies)
        wins = [body for body, reply in zip((one, two), replies) if reply.status == 201]
        r.sub(f"round {round_number}: exactly one commits", len(wins) == 1, statuses)
        for body, reply in zip((one, two), replies):
            if reply.status != 201:
                r.sub(f"round {round_number}: the other is version_conflict or ward_unavailable", (reply.status, reply.error()) in ((409, "version_conflict"), (503, "ward_unavailable")), f"{reply.status} {reply.raw[:160]!r}")
        held = r.read_encounter(encounter)
        r.sub(f"round {round_number}: one version and one row", held["version"] == version + 1 and len(held["history"]) == version + 1, held)
        for body in (one, two):
            if body in wins:
                r.record(body)
            else:
                r.sub(f"round {round_number}: no receipt for the loser", r.read_receipt(body["operation_key"]) is None, body["operation_key"])
        r.versions[encounter] = held["version"]


def c18(r):
    encounter = r.encounter()
    r.place(encounter, "admit", r.wards[0])
    for round_number in range(1, 4):
        version = r.versions[encounter]
        body = r.build(encounter, "transfer", r.wards[(round_number) % 2], None, version)
        r.ensure_absent(body["operation_key"])
        replies = r.together(lambda: r.send(body), lambda: r.send(body))
        statuses = sorted(reply.status for reply in replies)
        r.sub(f"round {round_number}: one 201, the other a repeat or unavailable", statuses in ([200, 201], [201, 503]), statuses)
        held = r.read_encounter(encounter)
        rows = [row for row in held["history"] if row["operation_key"] == body["operation_key"]]
        r.sub(f"round {round_number}: one business effect", held["version"] == version + 1 and len(rows) == 1, held)
        receipts = [reply.json().get("receipt") for reply in replies if reply.status in (200, 201)]
        r.sub(f"round {round_number}: one receipt", all(receipt == receipts[0] for receipt in receipts), receipts)
        r.record(body)
        r.versions[encounter] = held["version"]


def c19(r):
    ward = r.wards[0]
    for round_number in range(1, 4):
        one, two, bed = r.encounter(), r.encounter(), r.bed()
        first = r.build(one, "admit", ward, bed, 0)
        second = r.build(two, "admit", ward, bed, 0)
        r.ensure_absent(first["operation_key"])
        r.ensure_absent(second["operation_key"])
        replies = r.together(lambda: r.send(first), lambda: r.send(second))
        statuses = sorted(reply.status for reply in replies)
        wins = [body for body, reply in zip((first, second), replies) if reply.status == 201]
        r.sub(f"placements, round {round_number}: exactly one takes the bed", len(wins) == 1, statuses)
        for body, reply in zip((first, second), replies):
            if reply.status == 201:
                r.record(body)
            else:
                r.sub(f"placements, round {round_number}: the other is refused", (reply.status, reply.error()) in ((409, "bed_occupied"), (503, "ward_unavailable")), f"{reply.status} {reply.raw[:160]!r}")
        held = [e for e in (r.read_encounter(one), r.read_encounter(two)) if e and e["bed"] == bed]
        r.sub(f"placements, round {round_number}: one occupant", len(held) == 1, held)
    holder, bed = r.encounter(), r.bed()
    r.place(holder, "admit", ward, bed)
    newcomer = r.encounter()
    version = r.versions[holder]
    snap = r.snapshot(holder)
    refused = 0
    for round_number, offset in enumerate((0, 0.01, 0.03, 0.06), 1):
        rehearsal = r.build(holder, "transfer", r.wards[1], None, version, dry=True)
        placement = r.build(newcomer, "admit", ward, bed, 0)
        r.ensure_absent(placement["operation_key"])
        replies = r.together(lambda: r.send(rehearsal), lambda: r.send(placement), stagger=(0, offset))
        r.sub(f"dry run and placement, round {round_number}: the dry run applies nothing", replies[0].status in (200, 503), f"{replies[0].status} {replies[0].raw[:160]!r}")
        r.sub(f"dry run and placement, round {round_number}: the bed is not taken", replies[1].status != 201, f"{replies[1].status} {replies[1].raw[:160]!r}")
        refused += replies[1].status == 409
        r.unchanged(f"dry run and placement, round {round_number}", snap, placement["operation_key"], rehearsal["operation_key"])
        if r.read_encounter(newcomer) is not None:
            r.sub(f"dry run and placement, round {round_number}: the newcomer has no record", False)
            break
    r.note(f"Dry run and placement: {refused} of 4 placements were answered 409 bed_occupied; the rest 503 ward_unavailable or as failed above.")


def c20(r):
    encounter, bed = r.encounter(), r.bed()
    body = r.build(encounter, "admit", r.wards[0], bed, 0)
    r.commit(body)
    snap = r.snapshot(encounter)
    other = r.encounter()

    def dry(*args, **changes):
        built = r.build(*args, dry=True)
        built.update(changes)
        return built

    wrong_patient = dry(encounter, "transfer", r.wards[1], None, 1, patient_id=r.patients[other])
    wrong_patient["payload_digest"] = digest_text(canonical(wrong_patient))
    reused = dict(body, ward=r.wards[1], dry_run=True)
    reused["payload_digest"] = digest_text(canonical(reused))
    for name, attempt, reason in (
        ("the wrong version", dry(encounter, "transfer", r.wards[1], None, 9), "version_conflict"),
        ("another patient", wrong_patient, "patient_mismatch"),
        ("a wrong digest", dry(encounter, "transfer", r.wards[1], None, 1, payload_digest="sha256:" + "0" * 64), "payload_digest_mismatch"),
        ("a transition not allowed", dry(encounter, "admit", r.wards[1], None, 1), "invalid_transition"),
        ("a malformed field", dry(encounter, "update", r.wards[1], None, 1), "invalid_request"),
        ("a reused key", reused, "key_reused_with_different_payload"),
    ):
        r.would_not(name, r.post(attempt), reason)
        r.unchanged(name, snap, *([] if attempt is reused else [attempt["operation_key"]]))
    unknown = r.encounter()
    attempt = r.build(unknown, "transfer", r.wards[0], None, None, dry=True)
    r.would_not("an unknown encounter", r.post(attempt), "unknown_encounter")
    r.sub("an unknown encounter: no record", r.read_encounter(unknown) is None)
    r.sub("an unknown encounter: no receipt", r.read_receipt(attempt["operation_key"]) is None)
    repeat = dict(body, dry_run=True)
    r.would_not("a committed key", r.post(repeat), "already_committed")
    r.unchanged("a committed key", snap)


def c21(r):
    require(r.ledger, "no operation was committed to compare")
    for n, entry in enumerate(r.ledger, 1):
        body, receipt, encounter, rows = entry["body"], entry["receipt"], entry["encounter"], entry["rows"]
        name = f"operation {n} ({body['event']} {body['encounter_id']})"
        wanted = {"operation_key": body["operation_key"], "encounter_id": body["encounter_id"], "event": body["event"], "ward": body.get("ward"), "bed": body.get("bed"), "event_time": body["event_time"], "payload_digest": body["payload_digest"]}
        seen = {name_: receipt.get(name_) for name_ in wanted}
        r.sub(f"{name}: the receipt", seen == wanted, f"sent {wanted}, read {seen}")
        r.sub(f"{name}: one history row", len(rows) == 1, rows)
        if rows:
            row = rows[0]
            same = row["event"] == body["event"] and row["ward"] == body.get("ward") and row["bed"] == body.get("bed") and row["event_time"] == body["event_time"] and row["version_after"] == receipt["version_after"]
            r.sub(f"{name}: the history row", same, f"sent {wanted}, row {row}")
        r.sub(f"{name}: patient and authority on the encounter", encounter["patient_id"] == r.patients[body["encounter_id"]] and encounter["patient_id_authority"] == r.manifest["patient_authority"], encounter)
        r.sub(f"{name}: the encounter's version covers the receipt", encounter["version"] >= receipt["version_after"], encounter["version"])


def c22(r):
    encounter = r.encounter()
    r.place(encounter, "admit", r.wards[0])
    body = r.build(encounter, "transfer", r.wards[1], None, 1)
    r.ensure_absent(body["operation_key"])
    proxy = Proxy(r.api, "drop")
    try:
        seen = proxy.call("POST", "/operations", json.dumps(body).encode("utf-8"))
    finally:
        proxy.close()
    r.sub("the sender saw no answer", seen is None, seen and seen.status)
    receipt = r.read_receipt(body["operation_key"])
    r.sub("the committed operation is found by its receipt", receipt is not None)
    held = r.read_encounter(encounter)
    rows = [row for row in held["history"] if row["operation_key"] == body["operation_key"]] if held else []
    r.sub("it is in the history, once", len(rows) == 1, rows)
    r.sub("one version moved, with no second write", held is not None and held["version"] == 2, held)
    if receipt is not None and rows:
        r.record(body)
    r.not_run("Shutter's own read-back after a lost answer", "The kit runs no Shutter: tests/e2e/lost_answer_check.py and scenario S3 exercise it.")


def wait_for_receipt(r, key, limit=INCONCLUSIVE_WAIT):
    started = time.monotonic()
    while time.monotonic() - started < limit:
        receipt = r.read_receipt(key)
        if receipt is not None:
            return receipt, round(time.monotonic() - started, 3)
        time.sleep(0.25)
    return None, round(time.monotonic() - started, 3)


def c23(r):
    encounter = r.encounter()
    r.place(encounter, "admit", r.wards[0])
    held_write = r.build(encounter, "transfer", r.wards[1], None, 1)
    r.ensure_absent(held_write["operation_key"])
    proxy = Proxy(r.api, "hold_write", hold=2)
    try:
        started = time.monotonic()
        seen = proxy.call("POST", "/operations", json.dumps(held_write).encode("utf-8"), timeout=0.5)
        r.sub("a held write: the sender timed out with no answer", seen is None, seen and seen.status)
        early = r.read_receipt(held_write["operation_key"])
        r.note(f"A held write: a receipt read just after the sender gave up was {'present' if early else 'an exact 404'}; that read is not final (1.3).")
        receipt, _ = wait_for_receipt(r, held_write["operation_key"])
        r.sub("a held write: it landed after the sender gave up", receipt is not None)
        proxy.finished.wait(10)
        r.note(f"A held write: the receipt was first seen {round(time.monotonic() - started, 2)} s after sending, with the proxy holding for 2 s. No maximum commit delay follows from this.")
    finally:
        proxy.close()
    if receipt is not None:
        r.record(held_write)
    state = r.read_encounter(encounter)
    r.sub("a held write: applied once", state["version"] == 2, state)
    held_answer = r.build(encounter, "transfer", r.wards[0], None, 2)
    r.ensure_absent(held_answer["operation_key"])
    proxy = Proxy(r.api, "hold_answer", hold=1)
    try:
        seen = proxy.call("POST", "/operations", json.dumps(held_answer).encode("utf-8"), timeout=0.3)
        r.sub("a held answer: the sender timed out with no answer", seen is None, seen and seen.status)
        proxy.finished.wait(10)
    finally:
        proxy.close()
    r.sub("a held answer: the operation is found", r.read_receipt(held_answer["operation_key"]) is not None)
    if r.read_receipt(held_answer["operation_key"]) is not None:
        r.record(held_answer)
    proxy = Proxy(r.api, "receipt_503")
    try:
        seen = proxy.call("GET", r.receipt_path(held_answer["operation_key"]))
    finally:
        proxy.close()
    r.note("The proxy makes the 503 itself, so the receiver never sees that lookup. The kit's reading of it is exercised in check 24; what this check takes from the receiver is the direct read.")
    r.sub("a lookup the proxy answered 503 reads as unknown, and the direct read still finds the commit", classify_receipt(seen, held_answer["operation_key"])[0] == "unknown" and r.read_receipt(held_answer["operation_key"]) is not None, seen and seen.status)


# The negative controls of check 24: the five kinds the check names, each with the check that must fail against it.
CONTROLS = (("caps_html_200", 1), ("malformed_json_encounter", 4), ("wrong_identity", 4), ("partial_history", 12), ("mismatched_receipt", 4))


def load_stubs():
    spec = importlib.util.spec_from_file_location("receiver_stub", STUB_FILE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def against_stub(stub_module, mutant, only):
    """One run of the kit against a stub on loopback, in its own temporary folder."""
    receiver = stub_module.Receiver(mutant=mutant).start()
    try:
        with tempfile.TemporaryDirectory() as folder:
            manifest = make_manifest(f"control-{mutant or 'clean'}", f"http://127.0.0.1:{receiver.port}/downstream/api", "kit stub", mutant or "clean", "none", "the kit's own stub")
            return execute(manifest, folder, only=only)
    finally:
        receiver.stop()


def c24(r):
    if not STUB_FILE.exists():
        r.not_run("The kit's negative controls", f"{STUB_FILE.name} is not beside the kit")
        return
    stubs = load_stubs()
    # After the test for the stub, or these would turn a check that could not run into a pass (status_of)
    r.sub("no answer reads as unknown, not absent", classify_receipt(None, "k")[0] == "unknown")
    r.sub("a 503 reads as unknown, not absent", classify_receipt(Reply(503, b'{"error": "ward_unavailable"}', "application/json", 0, 0), "k")[0] == "unknown")
    r.sub("an HTML 404 reads as unknown, not absent", classify_receipt(Reply(404, b"<html></html>", "text/html", 0, 0), "k")[0] == "unknown")
    for mutant, check in CONTROLS:
        report = against_stub(stubs, mutant, (1, 2, check))
        status = next(c["status"] for c in report["checks"] if c["id"] == check)
        r.sub(f"{mutant} fails check {check}", status == "fail", status)
    report = against_stub(stubs, None, (1, 2, 4, 12))
    bad = [c["id"] for c in report["checks"] if c["id"] in (1, 2, 4, 12) and c["status"] != "pass"]
    r.sub("the correct stub passes the same checks", not bad, bad)
    r.note("These are negative controls of the kit, on loopback. They are not evidence about the receiver.")


def c25(r):
    r.not_run("Shutter refuses an approval from before the reset", "The kit runs no Shutter and issues no reset: an operator does this in a disposable environment.")
    if r.prior_report is None:
        r.not_run("The epoch moved since an earlier report", "Pass --prior-report after a reset made outside the kit.")
        return
    if r.capabilities is None:
        r.not_run("The epoch moved since an earlier report", "The receiver's capabilities could not be read (check 1), so there is no epoch to compare.")
        return
    prior = json.loads(Path(r.prior_report).read_text())
    if prior.get("receiver_identity") != r.manifest["receiver_identity"]:
        r.not_run("The epoch moved since an earlier report", "The earlier report is for another receiver.")
        return
    before = (prior.get("capabilities") or {}).get("epoch")
    now = r.capabilities.get("epoch")
    r.sub(f"the epoch moved from {before} to {now}", is_int(before) and is_int(now) and now > before, f"{before} to {now}")


def c26(r):
    require(r.ledger, "no operation was committed to read again")
    for n, entry in enumerate(r.ledger, 1):
        body = entry["body"]
        name = f"operation {n} ({body['event']} {body['encounter_id']})"
        r.sub(f"{name}: the receipt", r.read_receipt(body["operation_key"]) == entry["receipt"], body["operation_key"])
        now = r.read_encounter(body["encounter_id"])
        earlier = entry["encounter"]["history"]
        r.sub(f"{name}: the history", now is not None and now["history"][: len(earlier)] == earlier, f"was {earlier}, now {now and now['history']}")


CHECKS = {1: c01, 2: c02, 3: c03, 4: c04, 5: c05, 6: c06, 7: c07, 8: c08, 9: c09, 10: c10, 11: c11, 12: c12, 13: c13, 14: c14, 15: c15, 16: c16, 17: c17, 18: c18, 19: c19, 20: c20, 21: c21, 22: c22, 23: c23, 24: c24, 25: c25, 26: c26}
# Checks 21 and 26 read back everything the others committed, so they come last.
ORDER = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 22, 23, 21, 26, 24, 25)
OFFLINE = (24, 25)


def preflight(r):
    """Rules 5 and 6: every declared encounter is shown absent before anything is written. There is no resume."""
    for encounter in r.free_encounters:
        if r.read_encounter(encounter) is not None:
            raise Refusal(f"The declared encounter {encounter} already exists: the kit refuses to touch it. Declare new ones for a new run.")


def status_of(subs):
    """Any failure fails. A passed check may carry a not_run subcheck, which the report shows beside it (check 22)."""
    states = [s["status"] for s in subs]
    if "fail" in states:
        return "fail"
    if "not_run" in states and "pass" not in states:
        return "not_run"
    return "pass" if "pass" in states else "not_run"


def execute(manifest, out, credential=None, ca_file=None, prior_report=None, only=None, confirmation="unit", operator=None):
    """One run. Refusals before anything is sent raise; a refusal mid-run ends it and is reported."""
    check_manifest(manifest)
    contracts = json.loads(CONTRACTS_FILE.read_text())
    started = datetime.now(timezone.utc)
    r = Run(manifest, out, credential, ca_file, prior_report, confirmation)
    results = {}
    stopped = None
    refused = None
    for number in ORDER:
        if only is not None and number not in only:
            continue
        if stopped is not None and number not in OFFLINE:
            results[number] = {"status": "not_run", "subs": [{"name": stopped, "status": "not_run", "detail": ""}], "from": None, "to": None}
            continue
        if number not in (1, 2) and number not in OFFLINE and (r.capabilities is None or not all(r.capabilities.get(name) is True for name in OWN_CAPABILITIES)):
            why = "The receiver's capabilities could not be read (check 1)"
            if r.capabilities is not None:
                why = "The receiver does not declare " + ", ".join(name for name in OWN_CAPABILITIES if r.capabilities.get(name) is not True)
            results[number] = {"status": "not_supported", "subs": [{"name": why, "status": "not_supported", "detail": ""}], "from": None, "to": None}
            continue
        r.check_id = number
        r.subs = []
        first = r.journal.seq + 1
        status = None
        try:
            CHECKS[number](r)
        except Malformed as problem:
            r.subs.append({"name": str(problem), "status": "fail", "detail": ""})
        except StopRun as problem:
            r.subs.append({"name": str(problem), "status": "fail", "detail": ""})
            stopped = f"Not run: {problem}"
        except Inconclusive as problem:
            r.subs.append({"name": str(problem), "status": "not_run", "detail": ""})
            status = "not_run"
            stopped = f"Not run: {problem}"
        except Refusal as problem:
            r.subs.append({"name": str(problem), "status": "fail", "detail": ""})
            refused = str(problem)
            stopped = f"Not run: {problem}"
        status = status or status_of(r.subs)
        if number == 25 and status == "pass":
            status = "not_run"  # A moved epoch is half of this check; the kit cannot run the other half
        results[number] = {"status": status, "subs": r.subs, "from": first, "to": r.journal.seq}
        if number == 2:
            if results[2]["status"] != "pass" and stopped is None:
                stopped = "Not run: absence could not be established (check 2), so nothing was written"
            elif stopped is None:
                try:
                    preflight(r)
                except Refusal as problem:
                    refused = str(problem)
                    stopped = f"Not run: {problem}"
                except (Malformed, StopRun, Inconclusive) as problem:
                    stopped = f"Not run: declared encounters could not be shown absent: {problem}"
    return write_report(r, contracts, results, started, refused, only, operator)


def shutter_commit():
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], capture_output=True, text=True, timeout=10)
        return out.stdout.strip() if out.returncode == 0 else "unknown"
    except (OSError, subprocess.SubprocessError):
        return "unknown"


def contract_document_version():
    try:
        match = re.search(r"^Version ([0-9.]+),", (ROOT / "docs" / "CONTRACTS.md").read_text(encoding="utf-8"), re.MULTILINE)
        return match.group(1) if match else "unknown"
    except OSError:
        return "unknown"


def write_report(r, contracts, results, started, refused, only, operator):
    r.journal.close()
    manifest_text = json.dumps(r.manifest, sort_keys=True, separators=(",", ":"))
    checks = []
    for entry in contracts["checks"]:
        result = results.get(entry["id"], {"status": "not_run", "subs": [{"name": "Not part of this run", "status": "not_run", "detail": ""}], "from": None, "to": None})
        checks.append({
            "id": entry["id"],
            "stimulus": entry["stimulus"],
            "pass_condition": entry["pass_condition"],
            "sections": entry["sections"],
            "required": entry["required"],
            "evidence_about": entry["evidence_about"],
            "status": result["status"],
            "subchecks": result["subs"],
            "journal": None if result["from"] is None or result["to"] < result["from"] else [result["from"], result["to"]],
        })
    required = [c for c in checks if c["required"]]
    counts = {name: sum(1 for c in checks if c["status"] == name) for name in ("pass", "fail", "not_run", "not_supported")}
    all_passed = refused is None and all(c["status"] == "pass" for c in required)
    report = {
        "statement": STATEMENT,
        "run_id": r.manifest["run_id"],
        "manifest_digest": digest_text(manifest_text),
        "journal_digest": "sha256:" + r.journal.chain,
        "endpoint": r.manifest["base_url"],
        "allowed_origin": r.manifest["allowed_origin"],
        "certificate_sha256": r.api.fingerprint,
        "receiver_identity": r.manifest["receiver_identity"],
        "receiver_build": r.manifest["receiver_build"],
        "credential_scope": r.manifest["credential_scope"],
        "isolation_attestation": r.manifest["isolation_attestation"],
        "operator": operator,
        "shutter_commit": shutter_commit(),
        "contract_version": r.manifest["contract_version"],
        "contract_document_version": contract_document_version(),
        "started": started.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "ended": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "capabilities": r.capabilities,
        "summary": {
            "required_passed": sum(1 for c in required if c["status"] == "pass"),
            "required_total": len(required),
            "counts": counts,
            "all_required_passed": all_passed,
            "words": ("All required checks passed." if all_passed else "Not all required checks passed."),
            "refused": refused,
        },
        "checks": checks,
        "extensions": contracts["extensions"],
        "fixtures_left_behind": {"encounters": r.touched, "operation_keys": sorted(r.api.keys)},
        "limitations": LIMITATIONS,
        "deviations": ["The origin was confirmed with --confirm-origin, not typed at a terminal."] if r.confirmation == "flag" else [],
    }
    (r.out / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (r.out / "report.txt").write_text(readable(report), encoding="utf-8")
    return report


def readable(report):
    lines = ["Receiver conformance report", "", report["statement"], "", f"Run {report['run_id']} against {report['endpoint']}"]
    lines += [f"Receiver: {report['receiver_identity']}, build {report['receiver_build']}", f"Shutter commit {report['shutter_commit']}, contract {report['contract_version']} (CONTRACTS {report['contract_document_version']})"]
    lines += [f"From {report['started']} to {report['ended']}", f"Manifest {report['manifest_digest']}", f"Journal {report['journal_digest']}"]
    if report["certificate_sha256"]:
        lines.append(f"Certificate sha256 {report['certificate_sha256']}")
    summary = report["summary"]
    lines += ["", summary["words"], f"Required checks passed: {summary['required_passed']} of {summary['required_total']}. Pass {summary['counts']['pass']}, fail {summary['counts']['fail']}, not run {summary['counts']['not_run']}, not supported {summary['counts']['not_supported']}."]
    if summary["refused"]:
        lines.append(f"Refused: {summary['refused']}")
    lines.append("")
    for check in report["checks"]:
        about = ", evidence about the kit" if check["evidence_about"] == "kit" else ""
        journal = f", journal {check['journal'][0]}-{check['journal'][1]}" if check["journal"] else ""
        lines.append(f"{check['id']:>2}  {check['status'].upper():<13} {check['stimulus']} [{', '.join(check['sections'])}{about}{journal}]")
        shown = [s for s in check["subchecks"] if s["status"] in ("fail", "not_run", "not_supported", "note")]
        for sub in shown:
            lines.append(f"      {sub['status']}: {sub['name']}" + (f" ({sub['detail']})" if sub["detail"] else ""))
    lines += ["", "Declared extensions, not claimed:"]
    for extension in report["extensions"]:
        lines.append(f"  {extension['id']}: {extension['status']}. {extension['note']}")
    lines += ["", f"Left on the endpoint: {len(report['fixtures_left_behind']['encounters'])} encounters and up to {len(report['fixtures_left_behind']['operation_keys'])} operation keys (report.json lists them). The kit deletes nothing.", "", "Limitations:"]
    lines += [f"  - {item}" for item in report["limitations"]]
    if report["deviations"]:
        lines += ["", "Deviations:"] + [f"  - {item}" for item in report["deviations"]]
    return "\n".join(lines) + "\n"


# --- the command line -------------------------------------------------------------------------------------------------


def confirm(manifest, flag):
    """Rule 1: the exact origin and scope, typed at a terminal or given with --confirm-origin. Returns how it was given."""
    origin = manifest["allowed_origin"]
    if flag is not None:
        if flag != origin:
            raise Refusal(f"--confirm-origin {flag} is not the manifest's origin {origin}")
        return "flag"
    if not sys.stdin.isatty():
        raise Refusal(f"No terminal to confirm at: pass --confirm-origin {origin} to say this endpoint is the one meant")
    print(f"Environment TEST, origin {origin}, receiver {manifest['receiver_identity']}, scope {manifest['isolation_attestation']}")
    print("The run creates synthetic encounters there and deletes nothing. Type the origin to go ahead:")
    if input("> ").strip() != origin:
        raise Refusal("The origin typed is not the manifest's")
    return "typed"


def credential_from_environment(manifest):
    """Rule 12: from the environment, or none only when the manifest says the endpoint takes none."""
    user, password = os.environ.get("SHUTTER_CONFORMANCE_USER"), os.environ.get("SHUTTER_CONFORMANCE_PASSWORD")
    if manifest["credential_scope"] == "none":
        return None
    if not user or not password:
        raise Refusal("Set SHUTTER_CONFORMANCE_USER and SHUTTER_CONFORMANCE_PASSWORD to a scoped test credential, or declare credential_scope \"none\"")
    return user, password


def prepare_out(path):
    out = Path(path)
    out.mkdir(parents=True, exist_ok=True)
    if any(out.iterdir()):
        raise Refusal(f"{out} is not empty: a journal is never written over")
    return out


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init", help="print a manifest with generated synthetic identities")
    init.add_argument("--run-id", required=True)
    init.add_argument("--base-url", required=True)
    init.add_argument("--receiver-identity", required=True)
    init.add_argument("--receiver-build", required=True)
    init.add_argument("--credential-scope", required=True)
    init.add_argument("--attestation", required=True)
    run = commands.add_parser("run", help="run the checks against the manifest's endpoint")
    run.add_argument("--manifest", required=True)
    run.add_argument("--out", required=True)
    run.add_argument("--confirm-origin")
    run.add_argument("--operator")
    run.add_argument("--ca-file")
    run.add_argument("--prior-report")
    args = parser.parse_args(argv)
    try:
        if args.command == "init":
            manifest = make_manifest(args.run_id, args.base_url, args.receiver_identity, args.receiver_build, args.credential_scope, args.attestation)
            check_manifest(manifest)
            print(json.dumps(manifest, indent=2))
            return 0
        manifest = json.loads(Path(args.manifest).read_text())
        check_manifest(manifest)
        how = confirm(manifest, args.confirm_origin)
        credential = credential_from_environment(manifest)
        out = prepare_out(args.out)
        report = execute(manifest, out, credential, args.ca_file, args.prior_report, confirmation=how, operator=args.operator)
    except Refusal as refusal:
        print(f"Refused: {refusal}", file=sys.stderr)
        return 2
    print((Path(args.out) / "report.txt").read_text(), end="")
    if report["summary"]["refused"]:
        return 2
    return 0 if report["summary"]["all_required_passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
