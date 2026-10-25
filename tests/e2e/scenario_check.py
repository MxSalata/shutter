#!/usr/bin/env python3
"""Plays scenarios through Shutter's REST API and compares each case's outcome with the scenario's expected outcome.

    python3 tests/e2e/scenario_check.py [--url http://localhost:52773] [--modes board,rules] [--approve]
                                        [--markdown comparison.md] S1 S2 S3

Each scenario is played once per mode (board, single, rules; default board), so the same failures can be compared
across the board of specialists, the single investigator and rules alone. --markdown writes the comparison as a
table.

Signs in as the demo users `operator` and `approver` (password from SHUTTER_PASSWORD, default "shutter"). With
--approve, a plan waiting for approval is approved as the approver once the scenario's own steps have finished (S7
and S20 change the downstream system while its plan waits). The downstream system's final state is read through its API
(--downstream-user and --downstream-password, default _SYSTEM / SYS). The expected outcomes are in
fixtures/scenarios.json. Prints one line per scenario and exits 1 when any differs. Standard library only.

A scenario whose expected outcome says "incident" (S11) has several cases: the check follows the incident the run
opens, approves its plan and its cases' plans with --approve, and compares each encounter's chain (kind, who decided,
the catalogue entries), its writes and the downstream system's final state with expected.encounters.

A scenario that names the modes it is defined for (expected.modes: S7, S11, S12, S17, S18, S19, S20, S21) is skipped in
the others. S7 is not defined for site policy, which resends without asking anyone, so no plan waits for its later
transfer; S20 is defined for rules only and S21 for rules and site policy until the board's runs for them are recorded.
expected.by_mode adds to or replaces the expected outcome in one mode (S21: rules alone propose the resend and the gate
blocks it, where site policy escalates on the catalogue's E13 before any write is planned).

Besides the outcome, expected.blocked_by is a reason code the case met on the way (in any round, so a dispatch block
that led to a re-plan counts), expected.final_reason the code the closed case names for stopping (GET
/cases/{id}/blocked-reason), and expected.last_operation_key the operation the downstream system's history for the
encounter ends with (S20: the nurse's own entry still stands).

It plays scenarios: each run resets the downstream system. Don't run it on an instance someone else is using.
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
# The calls the API refused, newest last, so a wait that times out can say what it was answered.
REFUSED = []


class Session:
    """One signed-in user of the REST API: a cookie jar and JSON in and out."""

    def __init__(self, url):
        self.base = url.rstrip("/") + "/api/shutter"
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, method, path, body=None, idempotent=False):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=data, method=method)
        request.add_header("Accept", "application/json")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        if method != "GET":
            request.add_header("X-Requested-With", "Shutter")
        if idempotent:
            request.add_header("Idempotency-Key", str(uuid.uuid4()))
        try:
            with self.opener.open(request, timeout=300) as response:
                text = response.read().decode()
                return response.status, (json.loads(text) if text else None)
        except urllib.error.HTTPError as error:
            text = error.read().decode()
            REFUSED.append(f"HTTP {error.code} {method} {path}")
            try:
                return error.code, json.loads(text) if text else None
            except json.JSONDecodeError:
                return error.code, {"unparsed": text[:200]}

    def sign_in(self, user, password):
        status, body = self.call("POST", "/session", {"username": user, "password": password})
        if status != 200:
            raise SystemExit(f"sign-in as {user} failed: HTTP {status} {body}")
        return self


def downstream_encounter(url, user, password, encounter_id):
    request = urllib.request.Request(url.rstrip("/") + "/downstream/api/encounters/" + urllib.parse.quote(encounter_id, safe=""))
    request.add_header("Authorization", "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode())
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        return {"http_status": error.code}


def wait(what, check, timeout, every=2):
    """Calls check() until it returns something truthy, or raises after timeout seconds."""
    deadline = time.monotonic() + timeout
    refused = len(REFUSED)
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(every)
    since = REFUSED[refused:]
    raise TimeoutError(f"{what}: nothing after {timeout} s"
                       + (f" (meanwhile {len(since)} refused calls, the last: {since[-1]})" if since else ""))


def wait_until_idle(operator, timeout):
    """Waits until no scenario run is queued or playing: one run at a time."""

    def idle():
        _, body = operator.call("GET", "/scenarios")
        return ((body or {}).get("run") or {}).get("state") not in ("queued", "running")

    wait("the previous run to finish", idle, timeout)


def play(args, operator, approver, scenario, mode):
    """Plays one scenario in one mode and returns (as_expected, line, outcome)."""
    expected = scenario["expected"]
    if expected.get("incident"):
        return play_incident(args, operator, approver, scenario, mode)
    if mode not in expected.get("modes", [mode]):
        return True, f"skipped {scenario['id']} {mode}: defined for {', '.join(expected['modes'])}", "not defined"
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


def path_of(chain):
    """Who released a chain, as expected.encounters names it: automatic, approval, per_chain or board."""
    return chain.get("policy") if chain.get("decides") == "policy" else chain.get("decides")


def play_incident(args, operator, approver, scenario, mode):
    """Plays a scenario that opens an incident, approves what waits with --approve, and judges every encounter."""
    expected = scenario["expected"]
    if mode not in expected.get("modes", [mode]):
        return True, f"skipped {scenario['id']} {mode}: defined for {', '.join(expected['modes'])}", "not defined"
    wait_until_idle(operator, args.timeout)
    before = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    status, started = operator.call("POST", f"/scenarios/{scenario['id']}/run", {"mode": mode}, idempotent=True)
    if status not in (200, 202):
        return False, f"DIFFERS {scenario['id']} {mode}: the run was refused: HTTP {status} {started}", "run refused"
    started_at = max(started.get("startedAt") or "", started.get("queuedAt") or "", before)

    def run_state():
        _, body = operator.call("GET", "/scenarios")
        run = (body or {}).get("run") or {}
        return run.get("state") if run.get("scenario") == scenario["id"] else None

    def run_incidents():
        # The incidents this run's own cases joined. One can be older than the run: failures from scenarios played
        # just before count towards the same window, and an incident still taking cases adopts the new ones.
        _, body = operator.call("GET", f"/cases?scenario={scenario['id']}&limit=50")
        mine = [c for c in (body or {}).get("items", []) if (c.get("openedAt") or "") >= started_at]
        return sorted({c["incidentId"] for c in mine if c.get("incidentId")})

    wait(f"{scenario['id']}: an incident for its cases", run_incidents, args.timeout)
    decided = set()

    def approve_waiting(incident_id, inc):
        if incident_id not in decided and any(not t.get("complete") for t in inc.get("tasks") or []):
            body = {"planDigest": (inc.get("plan") or {}).get("digest"), "decision": "approve",
                    "comment": "scenario check"}
            status, out = approver.call("POST", f"/incidents/{urllib.parse.quote(incident_id)}/approvals", body,
                                        idempotent=True)
            if status != 202:
                raise RuntimeError(f"the approval of {incident_id} was refused: HTTP {status} {out}")
            decided.add(incident_id)
        for chain in inc.get("chains") or []:
            for item in chain.get("items") or []:
                caseid = item.get("caseId")
                if caseid in decided or item.get("caseState") != "awaiting_approval":
                    continue
                _, c = operator.call("GET", f"/cases/{urllib.parse.quote(caseid)}")
                _, view = operator.call("GET", f"/cases/{urllib.parse.quote(caseid)}/plan")
                body = {"decision": "approve", "planDigest": view["plan"]["digest"], "expectedVersion": c["version"],
                        "comment": "scenario check"}
                status, out = approver.call("POST", f"/cases/{urllib.parse.quote(caseid)}/approvals", body,
                                            idempotent=True)
                if status != 202:
                    raise RuntimeError(f"the approval of {caseid} was refused: HTTP {status} {out}")
                decided.add(caseid)

    def all_closed():
        incidents = []
        for incident_id in run_incidents():
            _, inc = operator.call("GET", f"/incidents/{urllib.parse.quote(incident_id)}")
            if not inc:
                return None
            if inc.get("state") != "closed" and args.approve and run_state() != "running":
                approve_waiting(incident_id, inc)
            incidents.append(inc)
        return incidents if incidents and all(i.get("state") == "closed" for i in incidents) else None

    # A burst and its quiet period take longer than one case: allow for every encounter.
    incidents = wait(f"{scenario['id']}: its incidents to close", all_closed,
                     args.timeout * max(1, len(expected["encounters"])))
    incident = {"incidentId": ",".join(i.get("incidentId") for i in incidents), "state": "closed",
                "chains": [c for i in incidents for c in i.get("chains") or []]}
    chains = {c.get("encounterId"): c for c in incident.get("chains") or []}
    differences, parts = [], []
    for want in expected["encounters"]:
        enc = want["encounter"]
        chain = chains.get(enc)
        if not chain:
            differences.append(f"{enc}: no chain")
            continue
        items = chain.get("items") or []
        entries = sorted({i.get("releaseEntry") or i.get("entry") for i in items} - {None, ""})
        writes = 0
        for item in items:
            _, attempts = operator.call("GET", f"/cases/{urllib.parse.quote(item['caseId'])}/attempts")
            writes += sum(1 for a in attempts or []
                          if (a.get("attempt") or {}).get("outcome") in ("applied", "already_committed"))
        held = downstream_encounter(args.url, args.downstream_user, args.downstream_password, enc)
        problems = []
        if chain.get("kind") != want["chain"]:
            problems.append(f"chain {chain.get('kind')}, expected {want['chain']}")
        if path_of(chain) != want["path"]:
            problems.append(f"decided by {path_of(chain)}, expected {want['path']}")
        if entries != sorted(want["entries"]):
            problems.append(f"entries {','.join(entries) or 'none'}, expected {','.join(sorted(want['entries']))}")
        if writes != want["writes"]:
            problems.append(f"{writes} writes, expected {want['writes']}")
        if held.get("state") != want["final_state"] or held.get("ward") != want["final_ward"]:
            problems.append(f"the downstream system holds {held.get('state')} {held.get('ward')}, "
                            f"expected {want['final_state']} {want['final_ward']}")
        parts.append(f"{enc} {chain.get('kind')} {path_of(chain)} {','.join(entries)} {writes}w {chain.get('state')}")
        differences += [f"{enc}: {x}" for x in problems]
    outcome = f"{incident['incidentId']} {incident.get('state')}: " + "; ".join(parts)
    summary = f"{scenario['id']} {mode}: {outcome}"
    if differences:
        return False, f"DIFFERS {summary}: " + "; ".join(differences), outcome + " (" + "; ".join(differences) + ")"
    return True, f"ok      {summary}", outcome


def judge(args, operator, scenario, mode, final):
    """Compares a settled case with the scenario's expected outcome; returns (as_expected, line, outcome)."""
    expected = {**scenario["expected"], **scenario["expected"].get("by_mode", {}).get(mode, {})}
    caseid = urllib.parse.quote(final["caseId"])
    _, attempts = operator.call("GET", f"/cases/{caseid}/attempts")
    wrote = any((a.get("attempt") or {}).get("outcome") in ("applied", "already_committed") for a in attempts or [])
    _, view = operator.call("GET", f"/cases/{caseid}/plan")
    codes = {chk.get("reason_code") for d in ((view or {}).get("gateDecisions") or [])
             for chk in (d.get("checks") or []) if chk.get("result") != "pass"}
    final_reason = None
    if final["state"] in ("blocked", "escalated"):
        status, reason = operator.call("GET", f"/cases/{caseid}/blocked-reason")
        if status == 200 and reason:
            final_reason = reason.get("code")
            codes.add(final_reason)
    # A code from an earlier round (a dispatch block that led to a re-plan) is in the case's events only
    _, events = operator.call("GET", f"/cases/{caseid}/events")
    for event in events or []:
        codes.update(re.findall(r"\b[A-Z][A-Z_]{5,}[A-Z]\b", event.get("text") or ""))
    held = downstream_encounter(args.url, args.downstream_user, args.downstream_password, final["encounterId"])

    differences = []
    allowed = set([expected["disposition"]] + expected.get("acceptable", []))
    if final.get("disposition") not in allowed:
        differences.append(f"disposition {final.get('disposition')}, expected {' or '.join(sorted(allowed))}")
    if wrote != expected["write"]:
        differences.append("wrote to the downstream system" if wrote else "wrote nothing, expected one conditional write")
    if held.get("state") != expected["final_state"] or held.get("ward") != expected["final_ward"]:
        differences.append(f"the downstream system holds {held.get('state')} {held.get('ward')}, "
                           f"expected {expected['final_state']} {expected['final_ward']}")
    if expected.get("blocked_by") and expected["blocked_by"] not in codes:
        differences.append(f"no {expected['blocked_by']} among {sorted(c for c in codes if c) or 'no reason codes'}")
    if expected.get("final_reason") and final_reason != expected["final_reason"]:
        differences.append(f"the case names {final_reason or 'no reason'}, expected {expected['final_reason']}")
    if expected.get("last_operation_key"):
        history = held.get("history") or []
        last = history[-1].get("operation_key") if history else None
        if last != expected["last_operation_key"]:
            differences.append(f"the downstream system's history ends with {last or 'nothing'}, "
                               f"expected {expected['last_operation_key']}")
    if expected.get("source"):
        # A case forwarded from another production names where it came from (CONTRACTS 11)
        _, case = operator.call("GET", f"/cases/{caseid}")
        case = case or {}
        for field, key in (("namespace", "sourceNamespace"), ("production", "sourceProduction"), ("route", "sourceRoute")):
            want = expected["source"].get(field)
            if want and case.get(key) != want:
                differences.append(f"{key} {case.get(key) or 'empty'}, expected {want}")
        if not case.get("originHeaderId"):
            differences.append("no originHeaderId: the case does not name the source's message")
    outcome = (f"{final['state']}, {final.get('disposition') or 'no plan'}, {'one write' if wrote else 'no write'}, "
               f"downstream {held.get('state')} {held.get('ward')}")
    summary = f"{scenario['id']} {mode}: {final['caseId']} {outcome}"
    if differences:
        return False, f"DIFFERS {summary}: " + "; ".join(differences), outcome + " (" + "; ".join(differences) + ")"
    return True, f"ok      {summary}", outcome


def write_markdown(path, modes, rows):
    """The comparison as a table: one row per scenario, its expected outcome, then each mode's outcome."""
    names = {"board": "Board of specialists", "single": "Single investigator", "rules": "Rules only",
             "policy": "Site policy"}
    lines = ["| Scenario | Expected | " + " | ".join(names[m] for m in modes) + " |",
             "| --- | --- | " + " | ".join("---" for _ in modes) + " |"]
    for row in rows:
        s, e = row["scenario"], row["scenario"]["expected"]
        if e.get("incident"):
            expected = "; ".join(f"{x['encounter']} {x['chain']} {x['path']} {x['writes']}w" for x in e["encounters"])
        else:
            expected = f"{e['disposition']}, {'one write' if e['write'] else 'no write'}, downstream {e['final_state']} {e['final_ward'] or ''}".strip()
        cells = [("as expected: " if ok else "**differs**: ") + outcome for ok, outcome in (row["results"][m] for m in modes)]
        lines.append(f"| {s['id']} {s['title']} | {expected} | " + " | ".join(cells) + " |")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("scenarios", nargs="+")
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--modes", default="board", help="comma-separated: board, single, rules, policy")
    p.add_argument("--markdown", help="write the comparison to this file as a Markdown table")
    p.add_argument("--approve", action="store_true", help="approve plans that wait for approval, as the approver")
    p.add_argument("--timeout", type=int, default=240, help="seconds to wait for each case")
    p.add_argument("--downstream-user", default="_SYSTEM")
    p.add_argument("--downstream-password", default="SYS")
    args = p.parse_args()

    password = os.environ.get("SHUTTER_PASSWORD", "shutter")
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
