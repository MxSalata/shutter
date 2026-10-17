#!/usr/bin/env python3
"""Plays scenarios through Interlock's REST API and compares each case's outcome with the scenario's expected outcome.

    python3 tests/e2e/scenario_check.py [--url http://localhost:52773] [--modes board,rules] [--approve]
                                        [--markdown comparison.md] S1 S2 S3

Each scenario is played once per mode (board, single, rules; default board), so the same failures can be compared
across the board of specialists, the single investigator and rules alone. --markdown writes the comparison as a
table.

Signs in as the demo users `operator` and `approver` (password from INTERLOCK_PASSWORD, default "interlock"). With
--approve, a plan waiting for approval is approved as the approver once the scenario's own steps have finished (S7
changes the ward while its plan waits). The ward's final state is read through the ward's API (--ward-user and
--ward-password, default _SYSTEM / SYS). The expected outcomes are in fixtures/scenarios.json. Prints one line per
scenario and exits 1 when any differs. Standard library only.

It plays scenarios: each run resets the ward. Don't run it on an instance someone else is using.
"""
import argparse
import base64
import http.cookiejar
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

CLOSED = {"resolved", "blocked", "escalated", "failed"}


class Session:
    """One signed-in user of the REST API: a cookie jar and JSON in and out."""

    def __init__(self, url):
        self.base = url.rstrip("/") + "/api/interlock"
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, method, path, body=None, idempotent=False):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=data, method=method)
        request.add_header("Accept", "application/json")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        if method != "GET":
            request.add_header("X-Requested-With", "Interlock")
        if idempotent:
            request.add_header("Idempotency-Key", str(uuid.uuid4()))
        try:
            with self.opener.open(request, timeout=300) as response:
                text = response.read().decode()
                return response.status, (json.loads(text) if text else None)
        except urllib.error.HTTPError as error:
            text = error.read().decode()
            try:
                return error.code, json.loads(text) if text else None
            except json.JSONDecodeError:
                return error.code, {"unparsed": text[:200]}

    def sign_in(self, user, password):
        status, body = self.call("POST", "/session", {"username": user, "password": password})
        if status != 200:
            raise SystemExit(f"sign-in as {user} failed: HTTP {status} {body}")
        return self


def ward_encounter(url, user, password, encounter_id):
    request = urllib.request.Request(url.rstrip("/") + "/wards/api/encounters/" + urllib.parse.quote(encounter_id, safe=""))
    request.add_header("Authorization", "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode())
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        return {"http_status": error.code}


def wait(what, check, timeout, every=2):
    """Calls check() until it returns something truthy, or raises after timeout seconds."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(every)
    raise TimeoutError(f"{what}: nothing after {timeout} s")


def wait_until_idle(operator, timeout):
    """Waits until no scenario run is queued or playing: one run at a time."""

    def idle():
        _, body = operator.call("GET", "/scenarios")
        return ((body or {}).get("run") or {}).get("state") not in ("queued", "running")

    wait("the previous run to finish", idle, timeout)


def play(args, operator, approver, scenario, mode):
    """Plays one scenario in one mode and returns (as_expected, line, outcome)."""
    wait_until_idle(operator, args.timeout)
    before = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    status, started = operator.call("POST", f"/scenarios/{scenario['id']}/run", {"mode": mode}, idempotent=True)
    if status not in (200, 202):
        return False, f"DIFFERS {scenario['id']} {mode}: the run was refused: HTTP {status} {started}", "run refused"
    # Only a case this run opened counts: the run answers with when it started, or with when it was queued for the
    # scenario player; the clock before the request is the floor either way.
    started_at = max(started.get("startedAt") or "", started.get("queuedAt") or "", before)

    def run_state():
        _, body = operator.call("GET", "/scenarios")
        run = (body or {}).get("run") or {}
        return run.get("state") if run.get("scenario") == scenario["id"] else None

    def newest_case():
        _, body = operator.call("GET", f"/cases?scenario={scenario['id']}&limit=5")
        items = [c for c in (body or {}).get("items", []) if c.get("openedAt", "") >= started_at]
        return items[0] if items else None

    case = wait(f"{scenario['id']}: a case", newest_case, args.timeout)
    approved = False

    def settled():
        nonlocal approved
        _, c = operator.call("GET", f"/cases/{urllib.parse.quote(case['caseId'])}")
        if c["state"] in CLOSED:
            return c
        if c["state"] == "awaiting_approval" and args.approve and not approved and run_state() != "running":
            _, view = operator.call("GET", f"/cases/{urllib.parse.quote(case['caseId'])}/plan")
            decision = {"decision": "approve", "planDigest": view["plan"]["digest"], "expectedVersion": c["version"],
                        "comment": "scenario check"}
            status, body = approver.call("POST", f"/cases/{urllib.parse.quote(case['caseId'])}/approvals", decision,
                                         idempotent=True)
            if status != 202:
                raise RuntimeError(f"the approval was refused: HTTP {status} {body}")
            approved = True
        if c["state"] == "awaiting_approval" and not args.approve:
            return c
        return None

    final = wait(f"{scenario['id']} {case['caseId']}: the outcome", settled, args.timeout)
    return judge(args, operator, scenario, mode, final)


def judge(args, operator, scenario, mode, final):
    """Compares a settled case with the scenario's expected outcome; returns (as_expected, line, outcome)."""
    expected = scenario["expected"]
    caseid = urllib.parse.quote(final["caseId"])
    _, attempts = operator.call("GET", f"/cases/{caseid}/attempts")
    wrote = any((a.get("attempt") or {}).get("outcome") in ("applied", "already_committed") for a in attempts or [])
    _, view = operator.call("GET", f"/cases/{caseid}/plan")
    codes = {chk.get("reason_code") for d in ((view or {}).get("gateDecisions") or [])
             for chk in (d.get("checks") or []) if chk.get("result") != "pass"}
    if final["state"] in ("blocked", "escalated"):
        status, reason = operator.call("GET", f"/cases/{caseid}/blocked-reason")
        if status == 200 and reason:
            codes.add(reason.get("code"))
    # A code from an earlier round (a dispatch block that led to a re-plan) is in the case's events only
    _, events = operator.call("GET", f"/cases/{caseid}/events")
    for event in events or []:
        codes.update(re.findall(r"\b[A-Z][A-Z_]{5,}[A-Z]\b", event.get("text") or ""))
    ward = ward_encounter(args.url, args.ward_user, args.ward_password, final["encounterId"])

    differences = []
    allowed = set([expected["disposition"]] + expected.get("acceptable", []))
    if final.get("disposition") not in allowed:
        differences.append(f"disposition {final.get('disposition')}, expected {' or '.join(sorted(allowed))}")
    if wrote != expected["write"]:
        differences.append("wrote to the ward" if wrote else "wrote nothing, expected one conditional write")
    if ward.get("state") != expected["final_state"] or ward.get("ward") != expected["final_ward"]:
        differences.append(f"the ward holds {ward.get('state')} {ward.get('ward')}, expected {expected['final_state']} "
                           f"{expected['final_ward']}")
    if expected.get("blocked_by") and expected["blocked_by"] not in codes:
        differences.append(f"no {expected['blocked_by']} among {sorted(c for c in codes if c) or 'no reason codes'}")
    outcome = (f"{final['state']}, {final.get('disposition') or 'no plan'}, {'one write' if wrote else 'no write'}, "
               f"ward {ward.get('state')} {ward.get('ward')}")
    summary = f"{scenario['id']} {mode}: {final['caseId']} {outcome}"
    if differences:
        return False, f"DIFFERS {summary}: " + "; ".join(differences), outcome + " (" + "; ".join(differences) + ")"
    return True, f"ok      {summary}", outcome


def write_markdown(path, modes, rows):
    """The comparison as a table: one row per scenario, its expected outcome, then each mode's outcome."""
    names = {"board": "Board of specialists", "single": "Single investigator", "rules": "Rules only"}
    lines = ["| Scenario | Expected | " + " | ".join(names[m] for m in modes) + " |",
             "| --- | --- | " + " | ".join("---" for _ in modes) + " |"]
    for row in rows:
        s, e = row["scenario"], row["scenario"]["expected"]
        expected = f"{e['disposition']}, {'one write' if e['write'] else 'no write'}, ward {e['final_state']} {e['final_ward'] or ''}".strip()
        cells = [("as expected: " if ok else "**differs**: ") + outcome for ok, outcome in (row["results"][m] for m in modes)]
        lines.append(f"| {s['id']} {s['title']} | {expected} | " + " | ".join(cells) + " |")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("scenarios", nargs="+")
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--modes", default="board", help="comma-separated: board, single, rules")
    p.add_argument("--markdown", help="write the comparison to this file as a Markdown table")
    p.add_argument("--approve", action="store_true", help="approve plans that wait for approval, as the approver")
    p.add_argument("--timeout", type=int, default=240, help="seconds to wait for each case")
    p.add_argument("--ward-user", default="_SYSTEM")
    p.add_argument("--ward-password", default="SYS")
    args = p.parse_args()

    password = os.environ.get("INTERLOCK_PASSWORD", "interlock")
    operator = Session(args.url).sign_in("operator", password)
    approver = Session(args.url).sign_in("approver", password)
    _, listing = operator.call("GET", "/scenarios")
    known = {s["id"]: s for s in (listing or {}).get("scenarios", [])}
    modes = [m.strip() for m in args.modes.split(",") if m.strip()]
    unknown_modes = [m for m in modes if m not in ("board", "single", "rules", "policy")]
    if unknown_modes:
        raise SystemExit(f"unknown mode {', '.join(unknown_modes)}: use board, single, rules or policy")
    failures, rows = 0, []
    for scenario_id in args.scenarios:
        if scenario_id not in known:
            print(f"DIFFERS {scenario_id}: no such scenario")
            failures += 1
            continue
        row = {"scenario": known[scenario_id], "results": {}}
        for mode in modes:
            try:
                ok, line, outcome = play(args, operator, approver, known[scenario_id], mode)
            except (TimeoutError, RuntimeError) as error:
                ok, line, outcome = False, f"DIFFERS {scenario_id} {mode}: {error}", str(error)
            print(line, flush=True)
            failures += 0 if ok else 1
            row["results"][mode] = (ok, outcome)
        rows.append(row)
    if args.markdown:
        write_markdown(args.markdown, modes, rows)
    runs = len(args.scenarios) * len(modes)
    print(f"{failures} of {runs} differ" if failures else f"all {runs} as expected")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
