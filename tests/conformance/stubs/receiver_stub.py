#!/usr/bin/env python3
"""A receiver in memory, for the conformance kit's own tests: correct by default, wrong in one named way as a mutant.

It follows docs/CONTRACTS.md, section 1, in the order of checks 1.1 gives. MUTANTS maps each mutant to the numbered check
that must fail against it; a run of the kit against a mutant is a negative control of the kit, never evidence about any
real receiver. Standard library only, loopback only, nothing kept on disk.
"""
import hashlib
import json
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

BASE = "/downstream/api"
EVENTS = ("admit", "transfer", "discharge", "update")

# Mutant name -> the check that must fail. Checks 22 and 23 mark their operations through source_message_id ("-C22-").
MUTANTS = {
    "caps_html_200": 1,
    "caps_malformed": 1,
    "caps_no_dry_run": 1,
    "caps_no_epoch": 1,
    "redirects": 1,
    "absent_html_404": 2,
    "absent_receipt_wrong_error": 2,
    "absent_receipt_503": 2,
    "dry_run_commits": 3,
    "dry_run_no_before": 3,
    "admit_version_two": 4,
    "admit_double_history": 4,
    "admit_200": 4,
    "mismatched_receipt": 4,
    "malformed_json_encounter": 4,
    "wrong_identity": 4,
    "repeat_reapplies": 5,
    "repeat_version_conflict": 5,
    "repeat_new_receipt": 5,
    "key_reuse_accepted": 6,
    "digest_ignored": 7,
    "version_ignored": 8,
    "version_wrong_current": 8,
    "patient_overwritten": 9,
    "unknown_creates": 10,
    "accepts_bad_bed": 11,
    "accepts_ward_on_update": 11,
    "accepts_missing_source": 11,
    "refusal_leaves_receipt": 11,
    "update_moves": 12,
    "discharge_keeps_bed": 12,
    "partial_history": 12,
    "readmit_allowed": 13,
    "transfer_after_discharge": 13,
    "bed_unchecked": 14,
    "bed_dry_run_200": 14,
    "occupant_leaks_patient": 14,
    "outsider_occupant": 14,
    "bed_never_freed": 15,
    "bed_name_global": 15,
    "own_bed_conflict": 15,
    "ward_level_conflict": 15,
    "bed_changes_on_repeat": 16,
    "race_version": 17,
    "race_key": 18,
    "race_bed": 19,
    "dry_run_frees_bed": 19,
    "dry_refusal_would_apply": 20,
    "dry_refusal_real_status": 20,
    "dry_refusal_leaves_receipt": 20,
    "receipt_event_time_wrong": 21,
    "history_event_time_wrong": 21,
    "forget_lost_answer": 22,
    "forget_held_write": 23,
    "history_rewritten_later": 26,
    "receipt_vanishes_later": 26,
}
RACES = ("race_version", "race_key", "race_bed")


def canonical(request):
    """The canonical payload of 1.6."""
    fields = {}
    for name in ("operation_key", "encounter_id", "patient_id", "patient_id_authority", "event"):
        fields[name] = request.get(name)
    fields["ward"] = request.get("ward") or None
    fields["event_time"] = request.get("event_time")
    fields["source_system"] = request.get("source_system")
    return json.dumps(fields, separators=(",", ":"), ensure_ascii=False)


def digest_of(request):
    return "sha256:" + hashlib.sha256(canonical(request).encode("utf-8")).hexdigest()


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class Receiver:
    def __init__(self, mutant=None, tls_context=None, epoch=1):
        self.mutant = mutant
        self.encounters = {}
        self.receipts = {}
        self.epoch = epoch
        self.lock = threading.RLock()
        self.requests = []
        stub = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *args):
                pass

            def handle_one(self):
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b""
                stub.requests.append((self.command, self.path))
                status, content_type, body, extra = stub.route(self.command, self.path, raw)
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                for name, value in extra.items():
                    self.send_header(name, value)
                self.end_headers()
                self.wfile.write(body)
                self.close_connection = True

            do_GET = do_POST = do_DELETE = do_PUT = handle_one

        class Server(ThreadingHTTPServer):
            daemon_threads = True
            request_queue_size = 64

            def handle_error(self, request, client_address):
                pass

        self.server = Server(("127.0.0.1", 0), Handler)
        if tls_context is not None:
            self.server.socket = tls_context.wrap_socket(self.server.socket, server_side=True)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def start(self):
        self.thread.start()
        return self

    def stop(self):
        self.server.shutdown()
        self.server.server_close()

    # --- the routes -------------------------------------------------------------------------------------------------

    def route(self, method, path, raw):
        if self.mutant == "redirects":
            return 302, "text/plain", b"", {"Location": "http://127.0.0.1:9/elsewhere"}
        if not path.startswith(BASE + "/"):
            return 404, "text/html", b"<html>not here</html>", {}
        tail = path[len(BASE):]
        if method == "GET" and tail == "/capabilities":
            return self.capabilities()
        if method == "POST" and tail == "/operations":
            return self.post_operation(raw)
        match = re.fullmatch(r"/encounters/([^/]+)", tail)
        if method == "GET" and match:
            return self.read_encounter(match.group(1))
        match = re.fullmatch(r"/receipts/([^/]+)", tail)
        if method == "GET" and match:
            return self.read_receipt(unquote(match.group(1)))
        # The demo controls exist here so that a test can see the kit never calls them.
        if tail in ("/reset", "/faults", "/capabilities"):
            return self.reply(200, {"trap": True})
        return 404, "text/html", b"<html>not here</html>", {}

    def reply(self, status, body):
        return status, "application/json; charset=utf-8", json.dumps(body).encode(), {}

    def capabilities(self):
        if self.mutant == "caps_html_200":
            return 200, "text/html", b"<html>welcome</html>", {}
        if self.mutant == "caps_malformed":
            return 200, "application/json", b'{"conditional_writes": tru', {}
        caps = {
            "conditional_writes": True,
            "receipts": True,
            "receipt_retention": "unbounded",
            "history": True,
            "idempotency": "by operation key and payload digest",
            "dry_run": self.mutant != "caps_no_dry_run",
            "epoch": self.epoch,
            "last_contract_check": None,
        }
        if self.mutant == "caps_no_epoch":
            del caps["epoch"]
        return self.reply(200, caps)

    def read_encounter(self, encounter_id):
        with self.lock:
            encounter = self.encounters.get(encounter_id)
            if encounter is None:
                if self.mutant == "absent_html_404":
                    return 404, "text/html", b"<html>not here</html>", {}
                return self.reply(404, {"error": "unknown_encounter"})
            if self.mutant == "malformed_json_encounter":
                return 200, "application/json", b'{"encounter_id": ', {}
            return self.reply(200, self.encounter_json(encounter))

    def read_receipt(self, key):
        with self.lock:
            if self.mutant == "absent_receipt_503":
                return self.reply(503, {"error": "ward_unavailable"})
            receipt = self.receipts.get(key)
            if receipt is None or receipt.get("hidden"):
                if self.mutant == "absent_receipt_wrong_error":
                    return self.reply(404, {"error": "not_found"})
                return self.reply(404, {"error": "no_receipt"})
            shown = {name: value for name, value in receipt.items() if name not in ("hidden", "sent")}
            if self.mutant == "mismatched_receipt":
                shown["ward"] = "SHUTTER-TEST-SOMEWHERE-ELSE"
            if self.mutant == "receipt_event_time_wrong":
                shown["event_time"] = "1999-01-01T00:00:00Z"
            return self.reply(200, shown)

    def encounter_json(self, encounter):
        out = {name: value for name, value in encounter.items()}
        out["epoch"] = self.epoch
        out["history"] = [dict(row) for row in encounter["history"]]
        if self.mutant == "wrong_identity":
            out["encounter_id"] = "SHUTTER-TEST-SOMEONE-ELSE"
        if self.mutant == "partial_history" and len(out["history"]) > 1:
            del out["history"][0]
        if self.mutant == "history_event_time_wrong":
            for row in out["history"]:
                row["event_time"] = "1999-01-01T00:00:00Z"
        return out

    def post_operation(self, raw):
        try:
            request = json.loads(raw.decode("utf-8"))
            if not isinstance(request, dict):
                raise ValueError
        except ValueError:
            return self.reply(422, {"error": "invalid_request", "detail": "the body must be a JSON object"})
        return self.reply(*self.apply(request))

    # --- the operation, in the contract's order of checks -----------------------------------------------------------

    def validate(self, request):
        if self.mutant == "accepts_missing_source":
            required = ("operation_key", "encounter_id", "patient_id", "patient_id_authority", "event", "event_time")
        else:
            required = ("operation_key", "encounter_id", "patient_id", "patient_id_authority", "event", "event_time", "source_system")
        for name in required:
            if not request.get(name):
                return name + " is required"
        event = request["event"]
        if event not in EVENTS:
            return "event must be admit, transfer, discharge or update"
        if event in ("admit", "transfer"):
            if not request.get("ward"):
                return "ward is required for " + event
        elif request.get("ward") is not None and self.mutant != "accepts_ward_on_update":
            return "ward must be null for " + event
        bed = request.get("bed")
        if bed is not None and self.mutant != "accepts_bad_bed":
            if event not in ("admit", "transfer"):
                return "bed must be null for " + event
            if not isinstance(bed, str) or not 1 <= len(bed) <= 64:
                return "bed must be null or a bed name of 1 to 64 characters"
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", str(request.get("event_time"))):
            return "event_time must be ISO 8601 UTC"
        expected = request.get("expected_version")
        if expected is not None and not (isinstance(expected, int) or re.fullmatch(r"\d+", str(expected))):
            return "expected_version must be a whole number"
        return ""

    def refuse(self, dry, status, body, encounter_id=None):
        if self.mutant == "refusal_leaves_receipt" and not dry and body.get("error") == "invalid_request":
            key = str(body.get("key") or "")
            if key:
                self.receipts[key] = {"operation_key": key}
        body.pop("key", None)
        if not dry:
            return status, body
        if self.mutant == "dry_refusal_real_status":
            return status, body
        out = {"applied": False, "rehearsal": True, "would_apply": self.mutant == "dry_refusal_would_apply", "reason": body["error"]}
        out.update({name: value for name, value in body.items() if name != "error"})
        out["encounter_before"] = self.encounter_or_null(encounter_id)
        out["epoch"] = self.epoch
        return 200, out

    def encounter_or_null(self, encounter_id):
        encounter = self.encounters.get(encounter_id)
        return None if encounter is None else self.encounter_json(encounter)

    def apply(self, request):
        answer = self.apply_checked(request)
        if self.mutant == "dry_refusal_leaves_receipt" and request.get("dry_run") and answer[1].get("would_apply") is False and answer[1].get("reason") != "already_committed":
            key = request.get("operation_key")
            self.receipts.setdefault(key, {"operation_key": key, "encounter_id": request.get("encounter_id"), "event": "transfer", "ward": None, "bed": None, "event_time": "2026-01-01T00:00:00Z", "applied_at": now(), "version_before": 0, "version_after": 1, "payload_digest": "sha256:" + "0" * 64, "status": "committed", "epoch": self.epoch})
        return answer

    def apply_checked(self, request):
        dry = bool(request.get("dry_run"))
        problem = self.validate(request)
        key = request.get("operation_key")
        encounter_id = request.get("encounter_id")
        if problem:
            return self.refuse(dry, 422, {"error": "invalid_request", "detail": problem, "key": key}, encounter_id)
        digest = digest_of(request)
        given = request.get("payload_digest")
        if given and given != digest and self.mutant != "digest_ignored":
            return self.refuse(dry, 422, {"error": "payload_digest_mismatch"}, encounter_id)
        if self.mutant == "dry_run_frees_bed" and dry and request["event"] == "transfer":
            return self.visible_rehearsal(request)
        if self.mutant in RACES:
            return self.apply_locked(request, key, digest, dry)
        with self.lock:
            return self.apply_locked(request, key, digest, dry)

    def visible_rehearsal(self, request):
        """The fault of check 19: a rehearsal whose write other callers can see until it is rolled back."""
        with self.lock:
            encounter = self.encounters.get(request["encounter_id"])
            held = encounter["bed"] if encounter else None
            before = self.encounter_or_null(request["encounter_id"])
            if encounter:
                encounter["bed"] = None
        time.sleep(0.3)
        with self.lock:
            if encounter:
                encounter["bed"] = held
        return 200, {"applied": False, "rehearsal": True, "would_apply": True, "encounter_before": before, "encounter_after": before, "epoch": self.epoch}

    def apply_locked(self, request, key, digest, dry):
        encounter_id = request["encounter_id"]
        event = request["event"]
        encounter = self.encounters.get(encounter_id)
        if encounter is not None and encounter["patient_id"] != request["patient_id"]:
            if self.mutant != "patient_overwritten":
                return self.refuse(dry, 422, {"error": "patient_mismatch", "encounter_id": encounter_id}, encounter_id)
            encounter["patient_id"] = request["patient_id"]
        receipt = self.receipts.get(key)
        if receipt is not None and "payload_digest" in receipt:
            answer = self.committed_answer(request, key, digest, dry, encounter, receipt)
            if answer is not None:
                return answer
        current = encounter["version"] if encounter else 0
        if encounter is None and event != "admit" and self.mutant != "unknown_creates":
            return self.refuse(dry, 422, {"error": "unknown_encounter", "encounter_id": encounter_id}, encounter_id)
        expected = request.get("expected_version")
        if expected is not None and int(expected) != current and self.mutant != "version_ignored":
            reported = current + 7 if self.mutant == "version_wrong_current" else current
            return self.refuse(dry, 409, {"error": "version_conflict", "expected_version": int(expected), "current_version": reported}, encounter_id)
        if encounter is not None:
            discharged = encounter["state"] == "discharged"
            allowed = (discharged and self.mutant == "transfer_after_discharge" and event != "admit") or (event == "admit" and not discharged and self.mutant == "readmit_allowed")
            if (discharged or event == "admit") and not allowed:
                return self.refuse(dry, 422, {"error": "invalid_transition", "state": encounter["state"], "event": event}, encounter_id)
        placement = event in ("admit", "transfer")
        ward = request.get("ward") if placement else None
        bed = request.get("bed") if placement else None
        occupied = self.occupied(ward, bed, encounter_id, key)
        if occupied is not None:
            if self.mutant == "bed_dry_run_200" and dry:
                return 200, {"applied": False, "rehearsal": True, "would_apply": False, "reason": "bed_occupied"}
            return 409, occupied
        if self.mutant in RACES:
            time.sleep(0.15)
            current = (self.encounters.get(encounter_id) or {"version": current})["version"] if self.mutant == "race_key" else current
        return self.write(request, key, digest, dry, encounter, event, ward, bed, current)

    def committed_answer(self, request, key, digest, dry, encounter, receipt):
        if receipt["payload_digest"] != digest and self.mutant != "key_reuse_accepted":
            return self.refuse(dry, 409, {"error": "key_reused_with_different_payload", "operation_key": key}, request["encounter_id"])
        if dry:
            shown = {name: value for name, value in receipt.items() if name not in ("hidden", "sent")}
            return 200, {"applied": False, "rehearsal": True, "would_apply": False, "reason": "already_committed", "receipt": shown, "encounter_before": self.encounter_or_null(request["encounter_id"]), "epoch": self.epoch}
        if self.mutant == "repeat_reapplies":
            return None
        expected = request.get("expected_version")
        if self.mutant == "repeat_version_conflict" and expected is not None and encounter and int(expected) != encounter["version"]:
            return 409, {"error": "version_conflict", "expected_version": int(expected), "current_version": encounter["version"]}
        if self.mutant == "repeat_new_receipt":
            receipt["applied_at"] = "1999-01-01T00:00:00Z"
        if self.mutant == "bed_changes_on_repeat" and encounter and request.get("bed"):
            encounter["bed"] = request["bed"]
            receipt["bed"] = request["bed"]
        shown = {name: value for name, value in receipt.items() if name not in ("hidden", "sent")}
        return 200, {"applied": False, "reason": "already_committed", "receipt": shown, "encounter": self.encounter_json(encounter) if encounter else None}

    def occupied(self, ward, bed, encounter_id, key):
        if bed is None or self.mutant == "bed_unchecked":
            if bed is None and ward and self.mutant == "ward_level_conflict":
                for other in self.encounters.values():
                    if other["encounter_id"] != encounter_id and other["ward"] == ward and other["bed"] is None and other["state"] == "admitted":
                        return self.occupied_body(ward, "ward-level", other, key)
            return None
        if self.mutant == "own_bed_conflict":
            own = self.encounters.get(encounter_id)
            if own and own["ward"] == ward and own["bed"] == bed:
                return self.occupied_body(ward, bed, own, key)
        for other in self.encounters.values():
            if other["encounter_id"] == encounter_id or other["state"] != "admitted" or other["bed"] != bed:
                continue
            if other["ward"] == ward or self.mutant == "bed_name_global":
                return self.occupied_body(ward, bed, other, key)
        if self.mutant == "bed_never_freed":
            for other in self.encounters.values():
                for row in other["history"]:
                    if other["encounter_id"] != encounter_id and row["bed"] == bed and row["ward"] == ward:
                        return self.occupied_body(ward, bed, other, key)
        return None

    def occupied_body(self, ward, bed, other, key):
        since = other["history"][-1]["event_time"] if other["history"] else now()
        for row in reversed(other["history"]):
            if row["event"] == "update":
                continue
            if row["ward"] != other["ward"] or row["bed"] != other["bed"]:
                break
            since = row["event_time"]
        holder = {"encounter_id": other["encounter_id"], "since": since, "version": other["version"]}
        if self.mutant == "occupant_leaks_patient":
            holder["patient_id"] = other["patient_id"]
        if self.mutant == "outsider_occupant":
            holder["encounter_id"] = "REAL-PATIENT-ENCOUNTER"
        return {"error": "bed_occupied", "detail": "Bed " + ward + "/" + str(bed) + " is occupied", "ward": ward, "bed": bed, "occupant": holder, "operation_key": key, "applied": False}

    def write(self, request, key, digest, dry, encounter, event, ward, bed, current):
        encounter_id = request["encounter_id"]
        stamp = now()
        before = self.encounter_or_null(encounter_id)
        if self.mutant == "dry_run_no_before" and dry:
            before = {"encounter_id": encounter_id}
        row_version = current + 1
        if self.mutant == "admit_version_two" and event == "admit":
            row_version = current + 2
        history = list(encounter["history"]) if encounter else []
        row = {"version_after": row_version, "event": event, "ward": ward, "bed": bed, "event_time": request["event_time"], "applied_at": stamp, "operation_key": key}
        history.append(row)
        if self.mutant == "admit_double_history" and event == "admit":
            history.append(dict(row))
        after = {
            "encounter_id": encounter_id,
            "patient_id": request["patient_id"],
            "patient_id_authority": request["patient_id_authority"],
            "state": "discharged" if event == "discharge" else "admitted",
            "ward": encounter["ward"] if encounter and event == "update" else ward,
            "bed": encounter["bed"] if encounter and event == "update" else bed,
            "version": row_version,
            "updated_at": stamp,
            "history": history,
        }
        if self.mutant == "update_moves" and event == "update":
            after["ward"] = "SHUTTER-TEST-MOVED"
        if self.mutant == "discharge_keeps_bed" and event == "discharge":
            after["bed"] = encounter["bed"] if encounter else None
        if dry and self.mutant != "dry_run_commits":
            return 200, {"applied": False, "rehearsal": True, "would_apply": True, "encounter_before": before, "encounter_after": self.encounter_shape(after), "epoch": self.epoch}
        receipt = {"operation_key": key, "encounter_id": encounter_id, "event": event, "ward": ward, "bed": bed, "event_time": request["event_time"], "applied_at": stamp, "version_before": current, "version_after": row_version, "payload_digest": digest, "status": "committed", "epoch": self.epoch}
        if self.mutant == "race_key" and encounter is not None:
            after["history"] = list(encounter["history"]) + [row]
        marker = str(request.get("source_message_id") or "")
        forget = event != "admit" and ((self.mutant == "forget_lost_answer" and "-C22-" in marker) or (self.mutant == "forget_held_write" and "-C23-" in marker))
        if not forget:
            self.encounters[encounter_id] = after
            self.receipts[key] = receipt
            self.later_rewrites(encounter_id)
        if dry:
            return 200, {"applied": False, "rehearsal": True, "would_apply": True, "encounter_before": before, "encounter_after": self.encounter_shape(after), "epoch": self.epoch}
        status = 200 if self.mutant == "admit_200" else 201
        return status, {"applied": True, "receipt": receipt, "encounter": self.encounter_shape(after)}

    def later_rewrites(self, encounter_id):
        """The faults of check 26: an earlier entry changes, or goes, once a later operation lands on the encounter."""
        if self.mutant not in ("history_rewritten_later", "receipt_vanishes_later"):
            return
        encounter = self.encounters[encounter_id]
        if len(encounter["history"]) < 3:
            return
        first = encounter["history"][0]
        if self.mutant == "history_rewritten_later":
            first["ward"] = "SHUTTER-TEST-REWRITTEN"
        else:
            self.receipts[first["operation_key"]]["hidden"] = True

    def encounter_shape(self, encounter):
        return self.encounter_json(encounter)
