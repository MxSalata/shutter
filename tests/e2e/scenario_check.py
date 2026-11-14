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
fixtures/scenarios.json. Prints one line per scenario and exits 1 when any differs. A scenario skipped in a mode it is
not defined for is no pass: the summary counts skips apart ("all 7 as expected (2 skipped)"), and when every requested
scenario is skipped in every mode nothing was proved, so the check exits 1. Standard library only.

A scenario whose expected outcome says "incident" (S11) has several cases: the check follows the incident the run
opens, approves its plan and its cases' plans with --approve, and compares each encounter's chain (kind, who decided,
the catalogue entries), its writes and the downstream system's final state with expected.encounters.

A scenario that names the modes it is defined for (expected.modes: S4, S7, S11, S12, S14, S17 to S22, S23a to S23c, S24 to
S26) is skipped in the others. S4 is not defined for single, whose stop is kept with its reason in expected.not_defined; S7 is not defined for site policy, which resends without asking anyone, so no plan waits for
its later transfer; S20 is defined for rules only; S21 for the board, rules and site policy; S22 to S25 for the board
and site policy; S14 and S26 for rules and site policy; S27 to S31 and S33 and S34 for site policy, S27 to S29 and S32 to S34 for rules, S35 for site policy.
expected.by_mode adds to or replaces the expected outcome in one mode (S21: rules alone propose the resend and the gate
blocks it, where site policy escalates on the catalogue's E13 before any write is planned). S21's rules pass is the
gate's catch, not a right answer from rules: S13's identical rules run, judged by its own expectation, differs. So
--markdown labels a cell judged by its mode's own expectation, which a count of what rules alone get right leaves out.

Besides the outcome, expected.blocked_by is a reason code the case met on the way (in any round, so a dispatch block
that led to a re-plan counts), expected.final_reason the code the closed case names for stopping (GET
/cases/{id}/blocked-reason), and expected.last_operation_key the operation the downstream system's history for the
encounter ends with (S20: the nurse's own entry still stands). A case blocked only until another case closes
(WAITING_FOR_OCCUPANT_CASE, S23a) or a newer message's delivery (NEWER_MESSAGE_PENDING, S24) is waited for, not judged, and with --approve the other case is approved when its tier
asks; expected.waits_on_key is the operation key of the case it waited on (waitsOn), and expected.case_by_key judges the
case of expected.failed_operation_key rather than the run's newest.

expected.names lists words the plan's view (its preconditions and its gate decisions' details) must show: the other visit a
person has to read (S9, S27), and expected.person_approves says a person, not the site's policy, approved the write (S30).

A scenario whose message goes to several receivers and fails at more than one (S22) gives its expectations per receiver
under expected.by_receiver: one case per failed delivery and receiver, each judged by its receiver's own disposition,
outcome (the catalogue outcome the plan took, such as none or correct_history), write, final state and ward. Each receiver's
state is read through its own API, at the base path its entry in the site profile names (GET /site-profile).

expected.held (S26) marks a case that blocks while its schema is missing and is released by the run's own import, so it is
judged only once the run's steps have finished; expected.failure_kind is the kind the case opened with. expected.index_later
(S14) is a row the case's timeline must carry from the exact index: from a route Shutter does not own, later than the
failure, with its outcome unknown.

A scenario whose receiver is a FHIR R4 server (expected.fhir, S35) is judged at that server instead of the downstream
system's API: GET Encounter/{id} and its _history at the base path the receiver's site profile entry names (the test
FHIR server's /fhir-facade/r4 when none is named), as the FHIR client user (--fhir-user, default fhir-client; its
password is --fhir-password, default FHIR_CLIENT_PASSWORD, else the demo users' SHUTTER_PASSWORD, else "shutter"). It
differs when the Encounter's open location is not expected.fhir.final_location, its status is not expected.final_state,
its history does not hold expected.fhir.versions versions, or the marker's tag (the entry's marker system,
urn:shutter:recovery when none is named) is not on expected.fhir.marked_version alone. Version ids are compared as the
server gave them, never as numbers. --self-test checks that judgement on made-up reads, with no instance.

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
            # A key of the caller's own (a string) sends a request again; True makes a fresh one.
            request.add_header("Idempotency-Key", idempotent if isinstance(idempotent, str) else str(uuid.uuid4()))
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


DEFAULT_BASE = "/downstream/api"


def downstream_encounter(url, user, password, encounter_id, base=DEFAULT_BASE):
    """The encounter as a receiver holds it, read through that receiver's API at its base path."""
    request = urllib.request.Request(url.rstrip("/") + base.rstrip("/") + "/encounters/"
                                     + urllib.parse.quote(encounter_id, safe=""))
    request.add_header("Authorization", "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode())
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        return {"http_status": error.code}


FHIR_BASE = "/fhir-facade/r4"
FHIR_MARKER = "urn:shutter:recovery"


def fhir_read(url, base, path, user, password):
    """One read at a FHIR server as the FHIR client user: the HTTP status (None when nothing answered) and the body as
    JSON (None when it is not JSON)."""
    request = urllib.request.Request(url.rstrip("/") + base.rstrip("/") + path)
    request.add_header("Accept", "application/fhir+json")
    request.add_header("Authorization", "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode())
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            status, raw = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, raw = error.code, error.read()
    except (urllib.error.URLError, OSError):
        return None, None
    try:
        return status, json.loads(raw.decode("utf-8", "replace"))
    except ValueError:
        return status, None


def fhir_block(operator, receiver):
    """The fhir object of the receiver's entry in the site profile (GET /site-profile), or {} when there is none."""
    _, view = operator.call("GET", "/site-profile")
    for entry in ((view or {}).get("profile") or {}).get("receivers") or []:
        if entry.get("name") == receiver and isinstance(entry.get("fhir"), dict):
            return entry["fhir"]
    return {}


def answered(status):
    """What a FHIR read that gave no resource answered, in a few words."""
    if status is None:
        return "nothing (no connection)"
    return f"HTTP {status}" + (" with no FHIR resource" if status == 200 else "")


def fhir_judge(want, final_state, block, current, history):
    """Judges a FHIR scenario's Encounter as the server holds it. want is expected.fhir; block the receiver's fhir
    entry ({} when none); current and history the (status, body) of GET Encounter/{id} and of its _history. Returns
    what the server holds (state, ward, location, versions, marked) and the differences from the expected outcome."""
    marker = ((block.get("marker") or {}).get("system")) or FHIR_MARKER
    status, encounter = current
    encounter = encounter if status == 200 and isinstance(encounter, dict) else {}
    open_at = [((e.get("location") or {}).get("reference")) for e in encounter.get("location") or []
               if isinstance(e, dict) and not (e.get("period") or {}).get("end")]
    wards = {m.get("location"): m.get("ward") for m in block.get("location_map") or [] if isinstance(m, dict)}
    location = open_at[0] if len(open_at) == 1 else None
    h_status, bundle = history
    bundle = bundle if h_status == 200 and isinstance(bundle, dict) else {}
    versions = {}
    for item in bundle.get("entry") or []:
        resource = (item or {}).get("resource") or {}
        versions[str((resource.get("meta") or {}).get("versionId"))] = resource
    marked = sorted(v for v, r in versions.items()
                    if any(t.get("system") == marker for t in (r.get("meta") or {}).get("tag") or [] if isinstance(t, dict)))
    held = {"state": encounter.get("status"), "ward": wards.get(location, location), "location": location,
            "versions": sorted(versions), "marked": marked}
    differences = []
    if not encounter:
        differences.append(f"GET Encounter/{want['encounter']} answered {answered(status)}")
    else:
        if open_at != [want["final_location"]]:
            differences.append(f"the Encounter's open location is {', '.join(str(x) for x in open_at) or 'none'}, "
                               f"expected {want['final_location']}")
        if encounter.get("status") != final_state:
            differences.append(f"the Encounter is {encounter.get('status') or 'without a status'}, expected {final_state}")
    if not bundle:
        differences.append(f"GET Encounter/{want['encounter']}/_history answered {answered(h_status)}")
    else:
        if len(versions) != want["versions"]:
            differences.append(f"its history holds {len(versions)} version{'' if len(versions) == 1 else 's'} "
                               f"({', '.join(sorted(versions)) or 'none'}), expected {want['versions']}")
        if marked != [str(want["marked_version"])]:
            differences.append(f"the marker {marker} is on {', '.join(marked) or 'no version'}, "
                               f"expected on version \"{want['marked_version']}\" alone")
    return held, differences


def fhir_self_test():
    """The FHIR judgement on made-up reads: the expected Encounter passes, and each way it can differ is named."""
    want = {"receiver": "FHIR Ward Out", "encounter": "enc-1035", "final_location": "Location/ward-b",
            "versions": 2, "marked_version": "2"}
    block = {"marker": {"system": FHIR_MARKER},
             "location_map": [{"ward": "WARD-A", "location": "Location/ward-a"},
                              {"ward": "WARD-B", "location": "Location/ward-b"}]}

    def encounter(status="in-progress", open_ref="Location/ward-b", version="2", tag=True):
        closed = {"location": {"reference": "Location/ward-a"}, "status": "completed",
                  "period": {"start": "2026-10-15T08:00:00Z", "end": "2026-10-15T08:20:00Z"}}
        moved = {"location": {"reference": open_ref}, "status": "active", "period": {"start": "2026-10-15T08:20:00Z"}}
        meta = {"versionId": version, "tag": [{"system": FHIR_MARKER, "code": "op-1"}] if tag else []}
        return {"resourceType": "Encounter", "id": "enc-1035", "status": status, "meta": meta, "location": [closed, moved]}

    first = {"resourceType": "Encounter", "id": "enc-1035", "status": "in-progress", "meta": {"versionId": "1"},
             "location": [{"location": {"reference": "Location/ward-a"}, "status": "active",
                           "period": {"start": "2026-10-15T08:00:00Z"}}]}

    def bundle(*resources):
        return 200, {"resourceType": "Bundle", "type": "history", "entry": [{"resource": r} for r in resources]}

    good = encounter()
    cases = [
        ("as expected", (200, good), bundle(good, first), "in-progress", []),
        ("the move not made", (200, first), bundle(first), "in-progress",
         ["open location is Location/ward-a", "holds 1 version (1)", "on no version"]),
        ("another status", (200, encounter(status="finished")), bundle(encounter(status="finished"), first),
         "in-progress", ["the Encounter is finished"]),
        ("another ward", (200, encounter(open_ref="Location/ward-c")), bundle(encounter(open_ref="Location/ward-c"), first),
         "in-progress", ["open location is Location/ward-c"]),
        ("the marker on both versions", (200, good),
         bundle(good, dict(first, meta={"versionId": "1", "tag": [{"system": FHIR_MARKER, "code": "x"}]})),
         "in-progress", ["is on 1, 2"]),
        ("a third version", (200, encounter(version="3", tag=False)),
         bundle(encounter(version="3", tag=False), good, first), "in-progress", ["holds 3 versions"]),
        ("another system's tag only", (200, good),
         bundle(dict(good, meta={"versionId": "2", "tag": [{"system": "urn:other", "code": "x"}]}), first),
         "in-progress", ["on no version"]),
        ("no Encounter", (404, {"resourceType": "OperationOutcome"}), (404, None), "in-progress",
         ["GET Encounter/enc-1035 answered HTTP 404", "_history answered HTTP 404"]),
        ("no answer", (None, None), (None, None), "in-progress", ["answered nothing (no connection)"]),
        ("not JSON", (200, None), (200, None), "in-progress", ["answered HTTP 200 with no FHIR resource"]),
    ]
    failed = 0
    for name, current, history, final_state, words in cases:
        held, differences = fhir_judge(want, final_state, block, current, history)
        text = "; ".join(differences)
        ok = (not differences) if not words else all(w in text for w in words)
        if name == "as expected":
            ok = ok and held == {"state": "in-progress", "ward": "WARD-B", "location": "Location/ward-b",
                                 "versions": ["1", "2"], "marked": ["2"]}
        print(f"{'ok  ' if ok else 'FAIL'} {name}: {text or 'no difference'}")
        failed += 0 if ok else 1
    print(f"self-test: {len(cases) - failed} of {len(cases)} as expected")
    return 1 if failed else 0


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
    """Plays one scenario in one mode and returns (as_expected, line, outcome); as_expected is None for a scenario not
    defined in that mode, which is skipped."""
    expected = scenario["expected"]
    if expected.get("incident"):
        return play_incident(args, operator, approver, scenario, mode)
    if mode not in expected.get("modes", [mode]):
        return None, f"skipped {scenario['id']} {mode}: defined for {', '.join(expected['modes'])}", "not defined"
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
        if expected.get("case_by_key"):
            # Two patients' cases (S23a): the one judged is the failed operation's own
            items = [c for c in items if c.get("operationKey") == expected["failed_operation_key"]]
        return items[0] if items else None

    by_receiver = expected.get("by_receiver")
    if by_receiver:
        def cases_per_receiver():
            # One case per failed delivery and receiver; the newest of each receiver this run opened
            _, body = operator.call("GET", f"/cases?scenario={scenario['id']}&limit=20")
            found = {}
            for c in (body or {}).get("items", []):
                if c.get("openedAt", "") >= started_at and c.get("receiver") in by_receiver:
                    found.setdefault(c["receiver"], c)
            return found if len(found) == len(by_receiver) else None

        cases = wait(f"{scenario['id']}: a case at each of {', '.join(by_receiver)}", cases_per_receiver, args.timeout)
        results = []
        for receiver in by_receiver:
            final = settle(args, operator, approver, scenario, cases[receiver], run_state)
            results.append(judge(args, operator, scenario, mode, final, receiver))
        ok = all(r[0] for r in results)
        line = "\n".join(r[1] for r in results)
        return ok, line, "; ".join(f"{receiver}: {r[2]}" for receiver, r in zip(by_receiver, results))

    case = wait(f"{scenario['id']}: a case", newest_case, args.timeout)
    final = settle(args, operator, approver, scenario, case, run_state)
    return judge(args, operator, scenario, mode, final)


def settle(args, operator, approver, scenario, case, run_state):
    """Waits for a case to close (or to wait for approval without --approve), approving it with --approve."""
    approved = False

    others = set()

    def settled():
        nonlocal approved
        # S26: blocked is the hold, not the end, until the run has imported the schema that releases the case
        if scenario["expected"].get("held") and run_state() in ("queued", "running"):
            return None
        _, c = operator.call("GET", f"/cases/{urllib.parse.quote(case['caseId'])}")
        if c["state"] == "blocked" and waiting_on_another(operator, case["caseId"]):
            # S23a: the case waits for the case about its bed's occupant, and is released when that one closes. With
            # --approve, that case is approved as this one would be.
            if args.approve and run_state() != "running":
                approve_others(operator, approver, scenario, case["caseId"], others)
            return None
        if c["state"] in CLOSED:
            return c
        if c["state"] == "awaiting_approval" and args.approve and not approved and run_state() != "running":
            _, view = operator.call("GET", f"/cases/{urllib.parse.quote(case['caseId'])}/plan")
            # The body names someone else: the approver of record must still be the signed-in user
            decision = {"decision": "approve", "planDigest": view["plan"]["digest"], "expectedVersion": c["version"],
                        "comment": "scenario check", "user": "mallory"}
            status, body = approver.call("POST", f"/cases/{urllib.parse.quote(case['caseId'])}/approvals", decision,
                                         idempotent=True)
            if status != 202:
                raise RuntimeError(f"the approval was refused: HTTP {status} {body}")
            if (body or {}).get("approver") != "approver":
                raise RuntimeError(f"the approval was recorded for {(body or {}).get('approver')!r}, not approver")
            approved = True
        if c["state"] == "awaiting_approval" and not args.approve:
            return c
        return None

    final = wait(f"{scenario['id']} {case['caseId']}: the outcome", settled, args.timeout)
    if approved:
        approver_of_record(operator, case["caseId"])
    return final


WAITS = {"WAITING_FOR_OCCUPANT_CASE", "NEWER_MESSAGE_PENDING"}


def waiting_on_another(operator, case_id):
    """Whether a blocked case is held only until another case closes (WAITING_FOR_OCCUPANT_CASE) or a newer message
    is delivered (NEWER_MESSAGE_PENDING): it is released by itself, so it is waited for, not judged."""
    status, reason = operator.call("GET", f"/cases/{urllib.parse.quote(case_id)}/blocked-reason")
    return status == 200 and (reason or {}).get("code") in WAITS


def approve_others(operator, approver, scenario, case_id, done):
    """Approves the scenario's other cases that wait for approval (the occupant's case in S23a), once each."""
    _, body = operator.call("GET", f"/cases?scenario={scenario['id']}&limit=20")
    for other in (body or {}).get("items", []):
        oid = other.get("caseId")
        if oid == case_id or oid in done or other.get("state") != "awaiting_approval":
            continue
        _, c = operator.call("GET", f"/cases/{urllib.parse.quote(oid)}")
        _, view = operator.call("GET", f"/cases/{urllib.parse.quote(oid)}/plan")
        decision = {"decision": "approve", "planDigest": view["plan"]["digest"], "expectedVersion": c["version"],
                    "comment": "scenario check"}
        status, out = approver.call("POST", f"/cases/{urllib.parse.quote(oid)}/approvals", decision, idempotent=True)
        if status != 202:
            raise RuntimeError(f"the approval of {oid} was refused: HTTP {status} {out}")
        done.add(oid)


def approver_of_record(operator, case_id):
    """Raises unless the case's approval, and the Workflow task it completed, name the signed-in approver."""
    _, a = operator.call("GET", f"/cases/{urllib.parse.quote(case_id)}/approvals")
    approvals = (a or {}).get("approvals") or []
    # The one that stands; a verification that found the write not committed revokes it, which leaves the last one
    current = [x for x in approvals if not x.get("revoked")] or approvals
    if not current or current[-1].get("approver") != "approver":
        raise RuntimeError(f"the approval of record is not approver: {current[-1:]}")
    tasks = {str(t.get("taskId")): t for t in (a or {}).get("tasks") or []}
    task = tasks.get(str(current[-1].get("workflowTaskId")))
    if not task or task.get("userName") != "approver":
        raise RuntimeError(f"the approval's task is not approver's: {task}")


def path_of(chain):
    """Who released a chain, as expected.encounters names it: automatic, approval, per_chain or board."""
    return chain.get("policy") if chain.get("decides") == "policy" else chain.get("decides")


def play_incident(args, operator, approver, scenario, mode):
    """Plays a scenario that opens an incident, approves what waits with --approve, and judges every encounter."""
    expected = scenario["expected"]
    if mode not in expected.get("modes", [mode]):
        return None, f"skipped {scenario['id']} {mode}: defined for {', '.join(expected['modes'])}", "not defined"
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


def receiver_base(operator, receiver):
    """The base path of a receiver's API as its site profile entry names it; the bed manager's when none is named."""
    if receiver not in BASES:
        _, view = operator.call("GET", "/site-profile")
        for entry in ((view or {}).get("profile") or {}).get("receivers") or []:
            BASES[entry.get("name")] = (entry.get("api") or {}).get("base") or DEFAULT_BASE
    return BASES.get(receiver) or DEFAULT_BASE


BASES = {}


def outcome_taken(plan_view, snapshot):
    """The catalogue outcome the plan took (none, correct_history, ...): its outcome reference read in the matched entry."""
    plan = (plan_view or {}).get("plan") or {}
    ref, entry = plan.get("outcome") or "", plan.get("catalogueEntry") or ""
    matches = (((snapshot or {}).get("summary") or {}).get("catalogue") or {}).get("matches") or []
    match = next((m for m in matches if m.get("id") == entry), None)
    if not match or not ref:
        return ref or None
    if ref == "preferred":
        return (match.get("preferred") or {}).get("outcome")
    m = re.fullmatch(r"alternative:(\d+)", ref)
    alternatives = match.get("alternatives") or []
    if m and 0 < int(m.group(1)) <= len(alternatives):
        return alternatives[int(m.group(1)) - 1].get("outcome")
    return ref


def judge(args, operator, scenario, mode, final, receiver=None):
    """Compares a settled case with the scenario's expected outcome, or with its receiver's under expected.by_receiver;
    returns (as_expected, line, outcome)."""
    expected = {**scenario["expected"], **scenario["expected"].get("by_mode", {}).get(mode, {})}
    if receiver:
        expected = {**expected, **expected["by_receiver"][receiver]}
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
    fhir = expected.get("fhir")
    differences = []
    if fhir:
        # A FHIR R4 receiver (S35): the Encounter and its history as the FHIR server holds them, not the downstream API
        block = fhir_block(operator, fhir["receiver"])
        base = block.get("base") or FHIR_BASE
        enc = urllib.parse.quote(fhir["encounter"], safe="")
        current = fhir_read(args.url, base, f"/Encounter/{enc}", args.fhir_user, args.fhir_password)
        history = fhir_read(args.url, base, f"/Encounter/{enc}/_history", args.fhir_user, args.fhir_password)
        held, found = fhir_judge(fhir, expected["final_state"], block, current, history)
        system = f"{fhir['receiver']} ({base})"
    else:
        base = receiver_base(operator, receiver) if receiver else DEFAULT_BASE
        held = downstream_encounter(args.url, args.downstream_user, args.downstream_password, final["encounterId"], base)
        system = f"{receiver} ({base})" if receiver else "the downstream system"

    allowed = set([expected["disposition"]] + expected.get("acceptable", []))
    if final.get("disposition") not in allowed:
        differences.append(f"disposition {final.get('disposition')}, expected {' or '.join(sorted(allowed))}")
    if wrote != expected["write"]:
        differences.append(f"wrote to {system}" if wrote else
                           f"wrote nothing, expected {'one update with If-Match' if fhir else 'one conditional write'}")
    if fhir:
        differences += [f"at {system}: {x}" for x in found]
    elif held.get("state") != expected["final_state"] or held.get("ward") != expected["final_ward"]:
        differences.append(f"{system} holds {held.get('state')} {held.get('ward')}, "
                           f"expected {expected['final_state']} {expected['final_ward']}")
    taken = None
    if expected.get("outcome"):
        _, snapshot = operator.call("GET", f"/cases/{caseid}/snapshot")
        taken = outcome_taken(view, snapshot)
        if taken != expected["outcome"]:
            differences.append(f"outcome {taken or 'none named'}, expected {expected['outcome']}")
        # A history correction is escalated with the steps that make it (CONTRACTS 10)
        steps = (((view or {}).get("plan") or {}).get("plan") or {}).get("correction_steps") or {}
        if expected["outcome"] == "correct_history" and not steps.get("steps"):
            differences.append("no correction_steps on the plan")
    if expected.get("blocked_by") and expected["blocked_by"] not in codes:
        differences.append(f"no {expected['blocked_by']} among {sorted(c for c in codes if c) or 'no reason codes'}")
    if expected.get("final_reason") and final_reason != expected["final_reason"]:
        differences.append(f"the case names {final_reason or 'no reason'}, expected {expected['final_reason']}")
    plan_view = json.dumps(view or {})
    for word in expected.get("names", []):
        if word not in plan_view:
            differences.append(f"the plan's view does not name {word}")
    if expected.get("person_approves"):
        _, a = operator.call("GET", f"/cases/{caseid}/approvals")
        who = [x.get("approver") for x in (a or {}).get("approvals") or []]
        if not who or "policy" in who:
            differences.append(f"approved by {who or 'nobody'}, expected a person")
    if expected.get("last_operation_key"):
        history = held.get("history") or []
        last = history[-1].get("operation_key") if history else None
        if last != expected["last_operation_key"]:
            differences.append(f"the downstream system's history ends with {last or 'nothing'}, "
                               f"expected {expected['last_operation_key']}")
    if expected.get("waits_on_key"):
        # The case it waited on (S23a): the case about the occupant's movement, named by that movement's operation key
        _, c = operator.call("GET", f"/cases/{caseid}")
        other = (c or {}).get("waitsOn")
        if not other:
            differences.append("the case names no case it waited on (waitsOn)")
        else:
            _, o = operator.call("GET", f"/cases/{urllib.parse.quote(other)}")
            if (o or {}).get("operationKey") != expected["waits_on_key"]:
                differences.append(f"waited on {other} ({(o or {}).get('operationKey')}), expected the case of "
                                   f"{expected['waits_on_key']}")
    if expected.get("failure_kind") and final.get("failureKind") != expected["failure_kind"]:
        differences.append(f"failure kind {final.get('failureKind')}, expected {expected['failure_kind']}")
    if expected.get("index_later"):
        # Only the exact index saw it (CONTRACTS 8.2): on the timeline from its route, later, and of unknown outcome
        want = expected["index_later"]
        _, snapshot = operator.call("GET", f"/cases/{caseid}/snapshot")
        rows = ((snapshot or {}).get("summary") or {}).get("timeline") or []
        row = next((r for r in rows if r.get("operation_key") == want["operation_key"]), None)
        if not row:
            differences.append(f"no row for {want['operation_key']} on the timeline")
        else:
            seen = {"source": row.get("source"), "route": row.get("route"), "event": row.get("event"),
                    "ward": row.get("ward"), "outcome": row.get("outcome"), "later": row.get("later")}
            wanted = {"source": "index", "route": want["route"], "event": want["event"], "ward": want["ward"],
                      "outcome": "unknown", "later": True}
            if seen != wanted:
                differences.append(f"the index's row reads {seen}, expected {wanted}")
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
    where = (f"at {fhir['receiver']}" if fhir else "at the receiver" if receiver else "downstream")
    outcome = (f"{final['state']}, {final.get('disposition') or 'no plan'}{f' ({taken})' if taken else ''}, "
               f"{'one write' if wrote else 'no write'}, {where} {held.get('state')} {held.get('ward')}")
    if fhir:
        outcome += (f" ({held.get('location')}, versions {', '.join(held.get('versions') or []) or 'none'}, "
                    f"marked {', '.join(held.get('marked') or []) or 'none'})")
    summary = f"{scenario['id']} {mode}: {final['caseId']}{f' {receiver}' if receiver else ''} {outcome}"
    if differences:
        return False, f"DIFFERS {summary}: " + "; ".join(differences), outcome + " (" + "; ".join(differences) + ")"
    return True, f"ok      {summary}", outcome


def expected_text(x):
    """One receiver's expected outcome in a few words."""
    outcome = f" ({x['outcome']})" if x.get("outcome") else ""
    write = "one write" if x["write"] else "no write"
    return f"{x['disposition']}{outcome}, {write}, {x['final_state']} {x['final_ward'] or ''}".strip()


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
        elif e.get("by_receiver"):
            expected = "; ".join(f"{name}: {expected_text(x)}" for name, x in e["by_receiver"].items())
        else:
            expected = f"{e['disposition']}, {'one write' if e['write'] else 'no write'}, downstream {e['final_state']} {e['final_ward'] or ''}".strip()
        cells = []
        for m in modes:
            ok, outcome = row["results"][m]
            # A pass by the mode's own expectation (S21's rules: the gate's catch) is no pass by the Expected column
            own = m in e.get("by_mode", {})
            label = ("skipped" if ok is None else "**differs**" if not ok
                     else "as this mode's own expectation says" if own else "as expected")
            cells.append(f"{label}: {outcome}")
        lines.append(f"| {s['id']} {s['title']} | {expected} | " + " | ".join(cells) + " |")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("scenarios", nargs="*")
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--modes", default="board", help="comma-separated: board, single, rules, policy")
    p.add_argument("--markdown", help="write the comparison to this file as a Markdown table")
    p.add_argument("--approve", action="store_true", help="approve plans that wait for approval, as the approver")
    p.add_argument("--timeout", type=int, default=240, help="seconds to wait for each case")
    p.add_argument("--downstream-user", default="_SYSTEM")
    p.add_argument("--downstream-password", default="SYS")
    p.add_argument("--fhir-user", default="fhir-client", help="the FHIR client user that reads a FHIR scenario's Encounter")
    # The demo install gives the FHIR client user the demo users' password (FHIRFacade.Installer)
    p.add_argument("--fhir-password", default=os.environ.get("FHIR_CLIENT_PASSWORD") or os.environ.get("SHUTTER_PASSWORD", "shutter"),
                   help="its password (default FHIR_CLIENT_PASSWORD, else SHUTTER_PASSWORD, else shutter)")
    p.add_argument("--self-test", action="store_true", help="check the FHIR judgement on made-up reads, then stop")
    args = p.parse_args()
    if args.self_test:
        return fhir_self_test()
    if not args.scenarios:
        p.error("the following arguments are required: scenarios")

    password = os.environ.get("SHUTTER_PASSWORD", "shutter")
    operator = Session(args.url).sign_in("operator", password)
    approver = Session(args.url).sign_in("approver", password)
    _, listing = operator.call("GET", "/scenarios")
    known = {s["id"]: s for s in (listing or {}).get("scenarios", [])}
    modes = [m.strip() for m in args.modes.split(",") if m.strip()]
    unknown_modes = [m for m in modes if m not in ("board", "single", "rules", "policy")]
    if unknown_modes:
        raise SystemExit(f"unknown mode {', '.join(unknown_modes)}: use board, single, rules or policy")
    failures, skipped, rows = 0, 0, []
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
            if ok is None:
                skipped += 1
            elif not ok:
                failures += 1
            row["results"][mode] = (ok, outcome)
        rows.append(row)
    if args.markdown:
        write_markdown(args.markdown, modes, rows)
    runs = len(args.scenarios) * len(modes)
    counted = f" ({skipped} skipped)" if skipped else ""
    if skipped == runs:
        # Every requested scenario was skipped in every mode: nothing was played, so nothing is proved
        print(f"DIFFERS: all {runs} skipped, none of {', '.join(args.scenarios)} is defined for {', '.join(modes)}")
        return 1
    print(f"{failures} of {runs} differ{counted}" if failures else f"all {runs} as expected{counted}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
