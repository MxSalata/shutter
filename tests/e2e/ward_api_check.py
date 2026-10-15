#!/usr/bin/env python3
"""Checks the ward system's REST API over HTTP against docs/CONTRACTS.md, section 1.

    python3 tests/e2e/ward_api_check.py [--url http://localhost:52773] [--user _SYSTEM] [--password SYS]
                                        [--second-user operator --second-password interlock]

Uses its own encounter ids (ENC-HT-<time>-n), sets faults only for its own operation keys and puts the previous
fault back, and never resets the ward, so it can run on an instance that holds other data. Exit status 1 when a
check fails. Standard library only.
"""
import argparse
import base64
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


class Ward:
    def __init__(self, url, user, password):
        self.base = url.rstrip("/") + "/wards/api"
        self.auth = None if user is None else "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()

    def call(self, method, path, body=None, raw=None):
        data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
        request = urllib.request.Request(self.base + path, data=data, method=method)
        request.add_header("Content-Type", "application/json")
        if self.auth:
            request.add_header("Authorization", self.auth)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.status, response.read().decode()
        except urllib.error.HTTPError as error:
            return error.code, error.read().decode()


def parse(text):
    try:
        return json.loads(text) if text else None
    except json.JSONDecodeError:
        return {"unparsed": text[:200]}


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--user", default="_SYSTEM")
    p.add_argument("--password", default="SYS")
    p.add_argument("--second-user")
    p.add_argument("--second-password")
    args = p.parse_args()

    ward = Ward(args.url, args.user, args.password)
    failures = []

    def check(name, condition, detail=""):
        print(("ok   " if condition else "FAIL ") + name + ("" if condition else f"  ({detail})"))
        if not condition:
            failures.append(name)

    prefix = "ENC-HT-" + time.strftime("%H%M%S")

    def operation(n, event, ward_name, at, **extra):
        encounter = f"{prefix}-{n}"
        body = {
            "operation_key": f"PAS^HOSP^MRN-HT^{encounter}^{event}^2026-10-15T{at}:00Z",
            "encounter_id": encounter, "patient_id": "MRN-HT", "patient_id_authority": "HOSP",
            "event": event, "ward": ward_name, "event_time": f"2026-10-15T{at}:00Z",
            "source_system": "PAS", "source_message_id": "MSG-HT",
        }
        body.update(extra)
        return body

    status, text = Ward(args.url, None, None).call("GET", "/faults")
    check("no credentials: 401", status == 401, status)

    status, text = ward.call("GET", "/faults")
    saved = parse(text)
    check("GET /faults: 200 with a mode", status == 200 and saved and "mode" in saved, f"{status} {text[:120]}")

    admit = operation(1, "admit", "WARD-A", "09:00")
    status, text = ward.call("POST", "/operations", admit)
    body = parse(text) or {}
    check("admit: 201", status == 201 and body.get("applied") is True, f"{status} {text[:160]}")

    status, text = ward.call("POST", "/operations", admit)
    body = parse(text) or {}
    check("the same key again: 200 already_committed", status == 200 and body.get("reason") == "already_committed", f"{status} {text[:160]}")

    status, text = ward.call("GET", f"/encounters/{admit['encounter_id']}")
    body = parse(text) or {}
    check("GET /encounters: version 1, one event", status == 200 and body.get("version") == 1 and len(body.get("history", [])) == 1, f"{status} {text[:160]}")

    key = urllib.parse.quote(admit["operation_key"], safe="")
    status, text = ward.call("GET", f"/receipts/{key}")
    body = parse(text) or {}
    check("GET /receipts with the key URL-encoded: 200 committed", status == 200 and body.get("status") == "committed", f"{status} {text[:160]}")

    status, text = ward.call("GET", "/receipts/" + urllib.parse.quote("PAS^HOSP^MRN-HT^nothing^admit^2026-10-15T09:00:00Z", safe=""))
    check("an unknown receipt: 404 no_receipt", status == 404 and (parse(text) or {}).get("error") == "no_receipt", f"{status} {text[:120]}")

    status, text = ward.call("POST", "/operations", raw=b"{not json")
    check("a body that isn't JSON: 422 invalid_request", status == 422 and (parse(text) or {}).get("error") == "invalid_request", f"{status} {text[:120]}")

    stale = operation(1, "transfer", "WARD-B", "09:20", expected_version=5)
    status, text = ward.call("POST", "/operations", stale)
    body = parse(text) or {}
    check("a stale expected version: 409 version_conflict", status == 409 and body.get("error") == "version_conflict" and body.get("current_version") == 1, f"{status} {text[:160]}")

    rehearsal = operation(1, "transfer", "WARD-B", "09:20", expected_version=1, dry_run=True)
    status, text = ward.call("POST", "/operations", rehearsal)
    body = parse(text) or {}
    check("a dry run: 200, would apply, Ward B after", status == 200 and body.get("would_apply") is True and (body.get("encounter_after") or {}).get("ward") == "WARD-B", f"{status} {text[:200]}")
    status, text = ward.call("GET", f"/encounters/{admit['encounter_id']}")
    check("and nothing changed", (parse(text) or {}).get("ward") == "WARD-A", text[:160])

    dropped = operation(1, "transfer", "WARD-B", "09:20", expected_version=1)
    ward.call("POST", "/faults", {"mode": "commit_drop_response", "operation_key": dropped["operation_key"]})
    status, text = ward.call("POST", "/operations", dropped)
    ward.call("POST", "/faults", saved)
    check("commit_drop_response: 504 with no body", status == 504 and text == "", f"{status} {text[:120]}")
    status, text = ward.call("GET", "/receipts/" + urllib.parse.quote(dropped["operation_key"], safe=""))
    check("but the receipt exists", status == 200, f"{status} {text[:120]}")

    discharge = operation(1, "discharge", None, "11:00")
    status, text = ward.call("POST", "/operations", discharge)
    check("discharge: 201", status == 201, f"{status} {text[:160]}")
    late = operation(1, "transfer", "WARD-C", "09:45")
    status, text = ward.call("POST", "/operations", late)
    check("a transfer after the discharge: 422 invalid_transition", status == 422 and (parse(text) or {}).get("error") == "invalid_transition", f"{status} {text[:160]}")

    status, text = ward.call("GET", "/faults")
    check("the fault setting is back as it was", parse(text) == saved, f"{text[:160]} vs {saved}")

    if args.second_user:
        status, text = Ward(args.url, args.second_user, args.second_password).call("GET", "/faults")
        check(f"{args.second_user} (Wards_API role): GET /faults 200", status == 200, f"{status} {text[:120]}")

    print(f"{len(failures)} failed" if failures else "all checks passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
