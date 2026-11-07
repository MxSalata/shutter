#!/usr/bin/env python3
"""The conformance kit's own tests, with no IRIS: its correct stub passes, every mutant fails its check, and what it must
refuse it refuses.

    python3 tests/conformance/test_kit.py

Standard library only. The TLS test needs the openssl command and is skipped without it.
"""
import importlib.util
import io
import json
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
from contextlib import redirect_stderr, redirect_stdout
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent.parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


kit = load("receiver_conformance", ROOT / "scripts" / "receiver-conformance.py")
stubs = load("receiver_stub", ROOT / "tests" / "conformance" / "stubs" / "receiver_stub.py")


def manifest_for(url, run_id="t1", scope="none"):
    return kit.make_manifest(run_id, url, "stub", "test", scope, "unit test")


def run_against(mutant=None, only=None, **options):
    receiver = stubs.Receiver(mutant=mutant).start()
    try:
        with tempfile.TemporaryDirectory() as folder:
            manifest = manifest_for(f"http://127.0.0.1:{receiver.port}/downstream/api")
            report = kit.execute(manifest, folder, only=only, **options)
            return report, list(receiver.requests), Path(folder, "journal.jsonl").read_text(), Path(folder, "report.txt").read_text()
    finally:
        receiver.stop()


def status(report, number):
    return next(c["status"] for c in report["checks"] if c["id"] == number)


class TheCorrectStub(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report, cls.requests, cls.journal, cls.text = run_against()

    def test_every_check_passes_but_the_one_the_kit_cannot_run(self):
        for check in self.report["checks"]:
            detail = [s for s in check["subchecks"] if s["status"] == "fail"]
            self.assertEqual(check["status"], "not_run" if check["id"] == 25 else "pass", (check["id"], detail))
        self.assertTrue(self.report["summary"]["all_required_passed"])
        self.assertEqual(self.report["summary"]["required_total"], 25)

    def test_only_the_routes_it_may_call_were_called(self):
        for method, path in self.requests:
            allowed = (method, path) in (("GET", "/downstream/api/capabilities"), ("POST", "/downstream/api/operations"))
            allowed = allowed or (method == "GET" and re.match(r"/downstream/api/(encounters|receipts)/", path))
            self.assertTrue(allowed, (method, path))
        self.assertFalse([r for r in self.requests if "reset" in r[1] or "faults" in r[1] or r[0] in ("DELETE", "PUT")])

    def test_the_report_says_what_it_is(self):
        self.assertIn("does not enable recovery", self.text)
        self.assertIn("All required checks passed", self.text)
        self.assertIn("cancels: not_run", self.text)
        self.assertIn("merges: not_run", self.text)
        for name in ("run_id", "manifest_digest", "journal_digest", "receiver_identity", "receiver_build", "shutter_commit", "contract_version", "started", "ended", "fixtures_left_behind", "limitations", "deviations"):
            self.assertIn(name, self.report)
        self.assertTrue(self.report["fixtures_left_behind"]["encounters"])

    def test_the_journal_is_one_json_line_per_exchange(self):
        lines = self.journal.splitlines()
        self.assertEqual([json.loads(line)["seq"] for line in lines], list(range(1, len(lines) + 1)))

    def test_check_25_says_why_it_was_not_run(self):
        names = [s["name"] for c in self.report["checks"] if c["id"] == 25 for s in c["subchecks"]]
        self.assertTrue(any("Shutter refuses" in n for n in names))

    def test_check_22_does_not_claim_shutters_read_back(self):
        subs = [s for c in self.report["checks"] if c["id"] == 22 for s in c["subchecks"]]
        self.assertIn("not_run", [s["status"] for s in subs])


class EveryMutant(unittest.TestCase):
    def test_every_mutant_fails_its_check(self):
        for mutant, number in stubs.MUTANTS.items():
            only = {1, 2, number}
            if number in (21, 26):
                only |= {12}
            if number == 26:
                only |= {21}
            with self.subTest(mutant=mutant, check=number):
                report, _, _, _ = run_against(mutant, only=only)
                self.assertEqual(status(report, number), "fail", [c for c in report["checks"] if c["id"] == number])
                self.assertFalse(report["summary"]["all_required_passed"])

    def test_every_check_a_mutant_can_reach_has_one(self):
        self.assertEqual(sorted(set(stubs.MUTANTS.values())), [n for n in range(1, 27) if n not in (24, 25)])

    def test_a_kit_that_passes_everything_fails_check_24(self):
        def everything_passes(stub_module, mutant, only):
            return {"checks": [{"id": n, "status": "pass"} for n in only]}

        with mock.patch.object(kit, "against_stub", everything_passes):
            report, _, _, _ = run_against(only={24})
        self.assertEqual(status(report, 24), "fail")

    def test_a_kit_that_fails_the_correct_stub_fails_check_24(self):
        def everything_fails(stub_module, mutant, only):
            return {"checks": [{"id": n, "status": "fail"} for n in only]}

        with mock.patch.object(kit, "against_stub", everything_fails):
            report, _, _, _ = run_against(only={24})
        self.assertEqual(status(report, 24), "fail")

    def test_a_missing_capability_leaves_the_rest_not_supported(self):
        report, requests, _, _ = run_against("caps_no_dry_run")
        self.assertEqual(status(report, 1), "fail")
        self.assertEqual(status(report, 4), "not_supported")
        self.assertFalse([r for r in requests if r[0] == "POST"])

    def test_an_identity_breach_stops_the_run(self):
        report, _, _, _ = run_against("wrong_identity")
        self.assertEqual(status(report, 4), "fail")
        self.assertEqual(status(report, 5), "not_run")

    def test_an_outside_occupant_stops_the_run(self):
        report, _, _, _ = run_against("outsider_occupant")
        self.assertEqual(status(report, 14), "fail")
        self.assertEqual(status(report, 15), "not_run")

    def test_a_redirect_is_never_followed(self):
        hits = []

        class Elsewhere(BaseHTTPRequestHandler):
            def do_GET(self):
                hits.append(self.path)
                self.send_response(200)
                self.end_headers()

            def log_message(self, *args):
                pass

        other = HTTPServer(("127.0.0.1", 0), Elsewhere)
        threading.Thread(target=other.serve_forever, daemon=True).start()
        receiver = stubs.Receiver(mutant="redirects").start()
        try:
            original = receiver.route
            receiver.route = lambda m, p, r: (302, "text/plain", b"", {"Location": f"http://127.0.0.1:{other.server_address[1]}/x"})
            with tempfile.TemporaryDirectory() as folder:
                report = kit.execute(manifest_for(f"http://127.0.0.1:{receiver.port}/downstream/api"), folder)
            receiver.route = original
        finally:
            receiver.stop()
            other.shutdown()
            other.server_close()
        self.assertEqual(status(report, 1), "fail")
        self.assertEqual(hits, [])
        self.assertEqual(status(report, 3), "not_run")

    def test_a_silent_receiver_is_not_run_never_a_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            report = kit.execute(manifest_for("http://127.0.0.1:9/downstream/api"), folder)
        self.assertEqual({c["status"] for c in report["checks"] if c["id"] not in (24, 25)}, {"not_run"})
        self.assertFalse(report["summary"]["all_required_passed"])


class TheRefusals(unittest.TestCase):
    def refused(self, manifest, **options):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(kit.Refusal) as caught:
                kit.execute(manifest, folder, **options)
            self.assertFalse(Path(folder, "journal.jsonl").exists(), "nothing is sent before the manifest passes")
        return str(caught.exception)

    def base(self):
        return manifest_for("http://127.0.0.1:1/downstream/api")

    def test_only_a_test_environment(self):
        self.assertIn("environment", self.refused(dict(self.base(), environment="PRODUCTION")))

    def test_plain_http_only_on_loopback(self):
        manifest = dict(self.base(), base_url="http://receiver.example.invalid/api", allowed_origin="http://receiver.example.invalid")
        self.assertIn("Plain http", self.refused(manifest))

    def test_the_origin_must_match(self):
        self.assertIn("allowed origin", self.refused(dict(self.base(), allowed_origin="http://127.0.0.1:2")))

    def test_no_user_query_or_fragment_in_the_url(self):
        for url in ("http://me:pw@127.0.0.1:1/x", "http://127.0.0.1:1/x?y=1", "http://127.0.0.1:1/x#y"):
            self.refused(dict(self.base(), base_url=url))

    def test_no_field_can_carry_a_request(self):
        for name, value in (("path", "/reset"), ("request", {"method": "POST"}), ("body", "{}"), ("password", "x")):
            self.refused(dict(self.base(), **{name: value}))

    def test_synthetic_identities_only(self):
        manifest = self.base()
        manifest["encounters"] = [dict(e, id="ENC-1001") for e in manifest["encounters"]]
        self.refused(manifest)
        manifest = self.base()
        manifest["encounters"][0] = dict(manifest["encounters"][0], patient_id="MRN1001")
        self.refused(manifest)

    def test_enough_declared(self):
        manifest = self.base()
        manifest["encounters"] = manifest["encounters"][:3]
        self.assertIn("declared encounters", self.refused(manifest))

    def test_an_existing_encounter_is_refused_and_nothing_written(self):
        receiver = stubs.Receiver().start()
        try:
            manifest = manifest_for(f"http://127.0.0.1:{receiver.port}/downstream/api")
            target = manifest["encounters"][30]
            receiver.encounters[target["id"]] = {"encounter_id": target["id"], "patient_id": target["patient_id"], "patient_id_authority": "SHUTTER-TEST", "state": "admitted", "ward": None, "bed": None, "version": 1, "updated_at": "2026-01-01T00:00:00Z", "history": [{"version_after": 1, "event": "admit", "ward": None, "bed": None, "event_time": "2026-01-01T00:00:00Z", "applied_at": "2026-01-01T00:00:00Z", "operation_key": "k"}]}
            with tempfile.TemporaryDirectory() as folder:
                report = kit.execute(manifest, folder)
            self.assertIn("already exists", report["summary"]["refused"])
            self.assertFalse([r for r in receiver.requests if r[0] == "POST"])
            self.assertEqual(status(report, 4), "not_run")
        finally:
            receiver.stop()

    def test_the_route_list_refuses_everything_else(self):
        with tempfile.TemporaryDirectory() as folder:
            manifest = self.base()
            journal = kit.Journal(Path(folder, "j"), [])
            self.addCleanup(journal.close)
            transport = kit.Transport(manifest, journal, None)
            for method, path in (("POST", "/reset"), ("POST", "/faults"), ("GET", "/faults"), ("POST", "/capabilities"), ("DELETE", "/encounters/x"), ("GET", "/encounters/ENC-1001"), ("GET", "/receipts/undeclared"), ("GET", "/capabilities/../reset")):
                with self.assertRaises(kit.StopRun):
                    transport.request(method, path)

    def test_an_undeclared_ward_or_bed_or_key_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            manifest = self.base()
            run = kit.Run(manifest, folder)
            self.addCleanup(run.journal.close)
            encounter = manifest["encounters"][0]["id"]
            good = run.build(encounter, "admit", manifest["wards"][0], manifest["beds"][0], 0)
            for change in ({"ward": "WARD-A"}, {"bed": "B2"}, {"operation_key": "someone's"}, {"encounter_id": "ENC-1"}, {"patient_id": "MRN1"}):
                with self.assertRaises(kit.StopRun):
                    run.guard(dict(good, **change))

    def test_the_command_line_confirms_the_exact_origin(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder, "m.json")
            path.write_text(json.dumps(self.base()))
            with redirect_stderr(io.StringIO()) as err:
                code = kit.main(["run", "--manifest", str(path), "--out", str(Path(folder, "o")), "--confirm-origin", "http://127.0.0.1:2"])
            self.assertEqual(code, 2)
            self.assertIn("not the manifest's origin", err.getvalue())
            self.assertFalse(Path(folder, "o").exists())

    def test_no_confirmation_with_no_terminal_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder, "m.json")
            path.write_text(json.dumps(self.base()))
            with redirect_stderr(io.StringIO()) as err, mock.patch("sys.stdin", io.StringIO("")):
                code = kit.main(["run", "--manifest", str(path), "--out", str(Path(folder, "o"))])
            self.assertEqual(code, 2)
            self.assertIn("No terminal", err.getvalue())

    def test_a_used_folder_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            Path(folder, "journal.jsonl").write_text("x")
            with self.assertRaises(kit.Refusal):
                kit.prepare_out(folder)

    def test_a_credential_is_required_unless_declared_none(self):
        manifest = dict(self.base(), credential_scope="a test user")
        with mock.patch.dict("os.environ", {}, clear=True), self.assertRaises(kit.Refusal):
            kit.credential_from_environment(manifest)

    def test_the_credential_reaches_neither_journal_nor_report(self):
        receiver = stubs.Receiver().start()
        try:
            manifest = manifest_for(f"http://127.0.0.1:{receiver.port}/downstream/api", scope="a test user")
            with tempfile.TemporaryDirectory() as folder:
                kit.execute(manifest, folder, credential=("conformance-user", "pw-that-must-not-appear"), only={1, 2})
                for name in ("journal.jsonl", "report.json", "report.txt"):
                    text = Path(folder, name).read_text()
                    self.assertNotIn("pw-that-must-not-appear", text)
                    self.assertNotIn("Authorization", text)
        finally:
            receiver.stop()

    def test_the_command_line_runs_end_to_end(self):
        receiver = stubs.Receiver().start()
        try:
            url = f"http://127.0.0.1:{receiver.port}/downstream/api"
            with tempfile.TemporaryDirectory() as folder:
                path = Path(folder, "m.json")
                printed = io.StringIO()
                with redirect_stdout(printed):
                    self.assertEqual(kit.main(["init", "--run-id", "cli", "--base-url", url, "--receiver-identity", "stub", "--receiver-build", "t", "--credential-scope", "none", "--attestation", "unit test"]), 0)
                path.write_text(printed.getvalue())
                with redirect_stdout(io.StringIO()) as out:
                    code = kit.main(["run", "--manifest", str(path), "--out", str(Path(folder, "o")), "--confirm-origin", f"http://127.0.0.1:{receiver.port}", "--operator", "unit test"])
                self.assertEqual(code, 0, out.getvalue())
                report = json.loads(Path(folder, "o", "report.json").read_text())
                self.assertEqual(report["operator"], "unit test")
                self.assertTrue(report["deviations"], "a flag instead of a typed confirmation is recorded")
        finally:
            receiver.stop()


class ASecondRun(unittest.TestCase):
    def test_a_new_run_id_needs_no_reset_on_one_endpoint(self):
        receiver = stubs.Receiver().start()
        try:
            url = f"http://127.0.0.1:{receiver.port}/downstream/api"
            for run_id in ("first", "second"):
                with tempfile.TemporaryDirectory() as folder:
                    report = kit.execute(manifest_for(url, run_id=run_id), folder, only={1, 2, 4, 14, 15})
                for number in (1, 2, 4, 14, 15):
                    self.assertEqual(status(report, number), "pass", (run_id, number, [c["subchecks"] for c in report["checks"] if c["id"] == number]))
        finally:
            receiver.stop()

    def test_the_longest_run_id_still_gives_a_bed_the_contract_takes(self):
        manifest = manifest_for("http://127.0.0.1:1/downstream/api", run_id="R" * 40)
        kit.check_manifest(manifest)
        self.assertLessEqual(max(len(bed) for bed in manifest["beds"]), 64)
        manifest = manifest_for("http://127.0.0.1:1/downstream/api", run_id="R" * 41)
        with self.assertRaises(kit.Refusal):
            kit.check_manifest(manifest)


class TheEpochComparison(unittest.TestCase):
    def prior(self, folder, epoch, identity="stub"):
        path = Path(folder, "prior.json")
        path.write_text(json.dumps({"receiver_identity": identity, "capabilities": {"epoch": epoch}}))
        return str(path)

    def run_with(self, epoch_now, prior_epoch):
        receiver = stubs.Receiver(epoch=epoch_now).start()
        try:
            with tempfile.TemporaryDirectory() as folder, tempfile.TemporaryDirectory() as out:
                report = kit.execute(manifest_for(f"http://127.0.0.1:{receiver.port}/downstream/api"), out, prior_report=self.prior(folder, prior_epoch), only={1, 25})
            return next(c for c in report["checks"] if c["id"] == 25)
        finally:
            receiver.stop()

    def test_a_moved_epoch_alone_stays_not_run(self):
        check = self.run_with(5, 4)
        self.assertEqual(check["status"], "not_run")
        self.assertIn("pass", [s["status"] for s in check["subchecks"]])
        self.assertIn("not_run", [s["status"] for s in check["subchecks"]])

    def test_an_epoch_that_did_not_move_fails(self):
        self.assertEqual(self.run_with(4, 4)["status"], "fail")


class TheClassifier(unittest.TestCase):
    def test_only_the_exact_404_is_absence(self):
        make = lambda status, raw, kind="application/json": kit.Reply(status, raw, kind, 0, 0)
        self.assertEqual(kit.classify_receipt(make(404, b'{"error": "no_receipt"}'), "k")[0], "absent")
        for reply in (make(404, b"<html></html>", "text/html"), make(404, b'{"error": "other"}'), make(503, b'{"error": "ward_unavailable"}'), make(500, b""), None):
            self.assertEqual(kit.classify_receipt(reply, "k")[0], "unknown")

    def test_strict_json_refuses(self):
        for raw, kind in ((b"<html>", "text/html"), (b"{", "application/json"), (b"[]", "application/json"), (b'{"a":1,"a":2}', "application/json"), (b'{"a":NaN}', "application/json"), (b"{}", "")):
            with self.assertRaises(kit.Malformed):
                kit.strict_json(raw, kind)

    def test_the_digest_follows_1_6(self):
        body = {"operation_key": "k", "encounter_id": "e", "patient_id": "p", "patient_id_authority": "a", "event": "update", "ward": None, "event_time": "t", "source_system": "s", "bed": "ignored", "expected_version": 1}
        self.assertEqual(kit.canonical(body), '{"operation_key":"k","encounter_id":"e","patient_id":"p","patient_id_authority":"a","event":"update","ward":null,"event_time":"t","source_system":"s"}')


class TheMap(unittest.TestCase):
    def setUp(self):
        self.map = json.loads((ROOT / "tests" / "conformance" / "contracts-v1.json").read_text())

    def test_twenty_six_numbered_checks(self):
        self.assertEqual([c["id"] for c in self.map["checks"]], list(range(1, 27)))
        self.assertEqual(sorted(kit.CHECKS), list(range(1, 27)))
        self.assertEqual(sorted(kit.ORDER), list(range(1, 27)))

    def test_every_section_named_is_a_heading_in_the_contract(self):
        text = (ROOT / "docs" / "CONTRACTS.md").read_text(encoding="utf-8")
        for entry in self.map["checks"] + self.map["extensions"]:
            for section in entry["sections"]:
                self.assertRegex(text, rf"(?m)^#+ {re.escape(section)}[. ]", (entry["id"], section))

    def test_the_document_lists_every_check(self):
        text = (ROOT / "docs" / "receiver-conformance.md").read_text(encoding="utf-8")
        for entry in self.map["checks"]:
            self.assertIn(f"| {entry['id']} | {entry['stimulus']} |", text)

    def test_extensions_are_declared_and_not_claimed(self):
        self.assertEqual([e["id"] for e in self.map["extensions"]], ["cancels", "merges"])
        self.assertEqual({e["status"] for e in self.map["extensions"]}, {"not_run"})

    def test_the_kit_never_builds_a_cancel_or_a_merge(self):
        report, requests, journal, _ = run_against()
        self.assertNotIn('"cancel_', journal.replace("\\", ""))
        self.assertNotIn('"merge', journal.replace("\\", ""))

    def test_the_kit_uses_the_standard_library_only(self):
        source = (ROOT / "scripts" / "receiver-conformance.py").read_text()
        modules = set(re.findall(r"(?m)^(?:import|from) ([a-z_0-9]+)", source))
        self.assertLessEqual(modules, set(sys.stdlib_module_names))


@unittest.skipUnless(shutil.which("openssl"), "needs the openssl command")
class TheCertificate(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        folder = self.folder.name
        self.cert, self.key = str(Path(folder, "c.pem")), str(Path(folder, "k.pem"))
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", self.key, "-out", self.cert, "-days", "1", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost"], check=True, capture_output=True)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, self.key)
        self.receiver = stubs.Receiver(tls_context=context).start()
        self.url = f"https://localhost:{self.receiver.port}/downstream/api"

    def tearDown(self):
        self.receiver.stop()
        self.folder.cleanup()

    def test_a_certificate_that_does_not_verify_is_refused(self):
        with tempfile.TemporaryDirectory() as out:
            report = kit.execute(manifest_for(self.url), out, only={1, 2})
        self.assertIn("TLS verification failed", report["summary"]["refused"])
        self.assertEqual(self.receiver.requests, [])

    def test_a_trusted_certificate_is_recorded(self):
        with tempfile.TemporaryDirectory() as out:
            report = kit.execute(manifest_for(self.url), out, ca_file=self.cert, only={1, 2})
        self.assertEqual(status(report, 1), "pass")
        self.assertRegex(report["certificate_sha256"], r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=1)
