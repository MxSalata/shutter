#!/usr/bin/env python3
"""Tries to break the approval boundary of Shutter's REST API over HTTP, and checks each attempt is refused.

    python3 tests/e2e/boundary_check.py [--url http://localhost:52773] [--timeout 240]
    python3 tests/e2e/boundary_check.py --write-list docs/readme/boundary.json
    python3 tests/e2e/boundary_check.py --check-list docs/readme/boundary.json

Signs in as the demo users `operator` and `approver` (password from SHUTTER_PASSWORD, default "shutter") and plays
three scenarios in rules-only mode, which needs no recordings. S2's resend waits for approval: an approval naming
another plan digest, or a case version that is not the case's, is refused with 409 stale_version, and the operator's
approval with 403 forbidden, each with nothing stored, no write attempt and the receiving system's record unchanged.
The approver's approval is then sent twice with one Idempotency-Key: the same reply both times, and 409
idempotency_key_reused for that key with another body. The case resolves with one write attempt, made after a dry run
bound to the approval; the approval names the signed-in approver, never a name in the body, and a fresh approval of the
resolved case is refused (409 wrong_state). S20's nurse moves the patient while the plan waits: the approval is voided
at dispatch (APPROVAL_RECEIVER_CHANGED) with no write attempt, and the nurse's entry stands. S3's resend of a delivery
the receiver already holds is blocked by the gate (ALREADY_COMMITTED).

The receiving system's records are read through its API (--downstream-user and --downstream-password, default _SYSTEM /
SYS). It plays scenarios, and each run resets the receiving system, so don't run it on an instance someone else is
using. Exit status 1 when a check fails. Standard library only.

--write-list writes the checks and what each proves as JSON, which the Evaluation page shows; --check-list exits 1 when
that file is not what this script would write, so the page's list stays the one the script runs.
"""
import argparse
import base64
import http.cookiejar
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

# What each part of the check tries and proves; --write-list writes these for the Evaluation page.
CHECKS = [
    {
        "id": "plan_digest",
        "title": "An approval of a plan that is not the one shown",
        "scenario": "S2, rules only",
        "answer": "409 stale_version",
        "proves": "An approval names the digest of the plan the approver read. Any other digest is refused with the "
                  "current one named, and nothing is stored: no approval, no new case version, no write attempt, and "
                  "the receiving system's record unchanged.",
    },
    {
        "id": "case_version",
        "title": "An approval from a stale copy of the case",
        "scenario": "S2, rules only",
        "answer": "409 stale_version",
        "proves": "An approval also names the case version it was read at; an older one is refused, with nothing "
                  "stored and nothing written.",
    },
    {
        "id": "operator_approval",
        "title": "An approval by an operator",
        "scenario": "S2, rules only",
        "answer": "403 forbidden",
        "proves": "Only an approver approves. The operator's request is refused before anything is stored.",
    },
    {
        "id": "idempotent_replay",
        "title": "The same approval sent twice, and its key reused",
        "scenario": "S2, rules only",
        "answer": "the same 202, then 409 idempotency_key_reused",
        "proves": "A repeated request with the same Idempotency-Key gets the first reply again, before and after the "
                  "case resolves, and the same key with another body is refused. The case has one approval and one "
                  "write attempt, and the receiving system's history has the operation once. A fresh approval of the "
                  "resolved case is refused with 409 wrong_state.",
    },
    {
        "id": "decider",
        "title": "A name in the approval's body",
        "scenario": "S2, rules only",
        "answer": "ignored",
        "proves": "The approval records the signed-in approver, never a name the request carries.",
    },
    {
        "id": "rehearsed",
        "title": "A write without a dry run",
        "scenario": "S2, rules only",
        "answer": "REHEARSED before the write",
        "proves": "The approval binds the receiver's dry run of this exact plan, which would apply at the version the "
                  "write is conditional on, and the dispatch gate passed APPROVAL_VALID and REHEARSED under the same "
                  "policy version the approval bound. Without that dry run the gate blocks the write (DRY_RUN_MISSING, "
                  "DRY_RUN_FAILED, DRY_RUN_STALE: Shutter's unit tests).",
    },
    {
        "id": "receiver_changed",
        "title": "The receiving system changed after the approval",
        "scenario": "S20, rules only",
        "answer": "APPROVAL_RECEIVER_CHANGED, no write",
        "proves": "A nurse moves the patient by hand while the resend waits. The approval is bound to the receiver's "
                  "version, so the dispatch gate voids it, the case is planned again on fresh evidence and blocked, no "
                  "write is attempted, and the nurse's entry is the last in the receiving system's history.",
    },
    {
        "id": "already_committed",
        "title": "A resend of a delivery the receiver already holds",
        "scenario": "S3, rules only",
        "answer": "ALREADY_COMMITTED, no write",
        "proves": "Only the acknowledgement was lost. Rules alone propose a resend, the gate finds the receiver's "
                  "receipt for the operation and blocks it, and nothing is written.",
    },
]

CLOSED = {"resolved", "blocked", "escalated", "failed"}


def check_list():
    """The document --write-list writes."""
    return {
        "script": "tests/e2e/boundary_check.py",
        "runs": "CI's iris job on every push to main, after the roles check, on a real IRIS for Health",
        "checks": CHECKS,
    }


class Session:
    """One signed-in user of the REST API: a cookie jar and JSON in and out."""

    def __init__(self, url):
        self.base = url.rstrip("/") + "/api/shutter"
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, method, path, body=None, key=None):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=data, method=method)
        request.add_header("Accept", "application/json")
        if body is not None:
            request.add_header("Content-Type", "application/json")
        if method != "GET":
            request.add_header("X-Requested-With", "Shutter")
        if key:
            request.add_header("Idempotency-Key", key)
        try:
            with self.opener.open(request, timeout=120) as response:
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


def wait(check, timeout, every=2):
    """Calls check() until it returns something truthy, or returns None after timeout seconds."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(every)
    return None


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--timeout", type=int, default=240, help="seconds to wait for each case")
    p.add_argument("--downstream-user", default="_SYSTEM")
    p.add_argument("--downstream-password", default="SYS")
    p.add_argument("--write-list", metavar="PATH", help="write the checks as JSON and exit")
    p.add_argument("--check-list", metavar="PATH", help="exit 1 when PATH is not the JSON --write-list would write")
    args = p.parse_args()

    listing = json.dumps(check_list(), indent=2, ensure_ascii=False) + "\n"
    if args.write_list:
        with open(args.write_list, "w", encoding="utf-8") as f:
            f.write(listing)
        return 0
    if args.check_list:
        with open(args.check_list, encoding="utf-8") as f:
            same = f.read() == listing
        print(f"{args.check_list} {'lists' if same else 'does not list'} the checks the script runs"
              + ("" if same else f": run it with --write-list {args.check_list}"))
        return 0 if same else 1

    password = os.environ.get("SHUTTER_PASSWORD", "shutter")
    operator = Session(args.url).sign_in("operator", password)
    approver = Session(args.url).sign_in("approver", password)
    failures = []
    checks = [0]

    def check(name, condition, detail=""):
        checks[0] += 1
        print(("ok   " if condition else "FAIL ") + name + ("" if condition else f"  ({detail})"), flush=True)
        if not condition:
            failures.append(name)
        return condition

    def done():
        print(f"{len(failures)} of {checks[0]} failed" if failures else f"all {checks[0]} checks passed")
        return 1 if failures else 0

    def get(path):
        return operator.call("GET", path)[1]

    def q(caseid):
        return urllib.parse.quote(caseid)

    def downstream(encounter_id):
        request = urllib.request.Request(args.url.rstrip("/") + "/downstream/api/encounters/"
                                         + urllib.parse.quote(encounter_id, safe=""))
        token = base64.b64encode(f"{args.downstream_user}:{args.downstream_password}".encode()).decode()
        request.add_header("Authorization", "Basic " + token)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode())
        except urllib.error.HTTPError as error:
            return {"http_status": error.code}

    def writes(caseid):
        """The case's write attempts: verifications of a plan that wrote nothing carry no attempt."""
        return [a["attempt"] for a in get(f"/cases/{q(caseid)}/attempts") or [] if a.get("attempt")]

    def approvals(caseid):
        return (get(f"/cases/{q(caseid)}/approvals") or {}).get("approvals") or []

    def run_state(scenario):
        run = (get("/scenarios") or {}).get("run") or {}
        return run.get("state") if run.get("scenario") == scenario else None

    def play(scenario):
        """Plays a scenario in rules-only mode and returns the case it opened, or None."""
        if not wait(lambda: ((get("/scenarios") or {}).get("run") or {}).get("state") not in ("queued", "running"),
                    args.timeout):
            check(f"{scenario}: the previous run finishes", False, "still playing")
            return None
        before = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        status, started = operator.call("POST", f"/scenarios/{scenario}/run", {"mode": "rules"}, key=str(uuid.uuid4()))
        if not check(f"{scenario} in rules-only mode: the run starts", status in (200, 202), f"{status} {started}"):
            return None
        since = max(started.get("startedAt") or "", started.get("queuedAt") or "", before)

        def newest():
            items = (get(f"/cases?scenario={scenario}&limit=5") or {}).get("items") or []
            items = [c for c in items if (c.get("openedAt") or "") >= since]
            return items[0] if items else None

        case = wait(newest, args.timeout)
        check(f"{scenario}: a case opens", bool(case), "none")
        return case

    def settle(caseid, scenario, until):
        """Waits until the scenario's own steps have finished and the case reaches one of the states in until."""
        def reached():
            c = get(f"/cases/{q(caseid)}") or {}
            if c.get("state") in until and run_state(scenario) not in ("queued", "running"):
                return c
            return None

        return wait(reached, args.timeout)

    # ---- S2: a resend waiting for approval ----
    case = play("S2")
    if not case:
        return done()
    caseid, encounter = case["caseId"], case["encounterId"]
    c = settle(caseid, "S2", {"awaiting_approval"} | CLOSED)
    if not check(f"S2 {caseid} waits for approval", (c or {}).get("state") == "awaiting_approval", (c or {}).get("state")):
        return done()
    view = get(f"/cases/{q(caseid)}/plan") or {}
    digest, version = view["plan"]["digest"], c["version"]
    held = downstream(encounter)

    def unchanged(what):
        now = get(f"/cases/{q(caseid)}") or {}
        after = downstream(encounter)
        check(f"and nothing is stored or written after {what}",
              (now.get("state"), now.get("version")) == ("awaiting_approval", version) and not approvals(caseid)
              and not writes(caseid) and after.get("version") == held.get("version")
              and after.get("ward") == held.get("ward"),
              f"case {now.get('state')} v{now.get('version')}, {len(approvals(caseid))} approvals, "
              f"{len(writes(caseid))} attempts, receiver v{after.get('version')} {after.get('ward')}")

    # Another plan's digest: one character of the shown digest changed
    other = digest[:-1] + ("0" if digest[-1] != "0" else "1")
    status, body = approver.call("POST", f"/cases/{q(caseid)}/approvals",
                                 {"decision": "approve", "planDigest": other, "expectedVersion": version,
                                  "comment": "boundary check: another digest"}, key=str(uuid.uuid4()))
    check("approver: an approval with a changed planDigest is 409 stale_version, naming the current digest",
          status == 409 and (body or {}).get("error") == "stale_version" and (body or {}).get("currentDigest") == digest,
          f"{status} {body}")
    unchanged("the changed digest")

    status, body = approver.call("POST", f"/cases/{q(caseid)}/approvals",
                                 {"decision": "approve", "planDigest": digest, "expectedVersion": version - 1,
                                  "comment": "boundary check: a stale case version"}, key=str(uuid.uuid4()))
    check("approver: an approval at an older case version is 409 stale_version",
          status == 409 and (body or {}).get("error") == "stale_version" and (body or {}).get("currentVersion") == version,
          f"{status} {body}")
    unchanged("the stale version")

    status, body = operator.call("POST", f"/cases/{q(caseid)}/approvals",
                                 {"decision": "approve", "planDigest": digest, "expectedVersion": version,
                                  "comment": "boundary check: the operator"}, key=str(uuid.uuid4()))
    check("operator: an approval is 403 forbidden", status == 403 and (body or {}).get("error") == "forbidden",
          f"{status} {body}")
    unchanged("the operator's approval")

    # The approval, sent twice with one key; the body names another approver, which the route ignores
    key = str(uuid.uuid4())
    decision = {"decision": "approve", "planDigest": digest, "expectedVersion": version,
                "comment": "boundary check", "approver": "someone-else", "user": "someone-else"}
    first = approver.call("POST", f"/cases/{q(caseid)}/approvals", decision, key=key)
    check("approver: the approval is 202 accepted", first[0] == 202 and (first[1] or {}).get("decision") == "approve",
          f"{first[0]} {first[1]}")
    again = approver.call("POST", f"/cases/{q(caseid)}/approvals", decision, key=key)
    check("the same approval with the same Idempotency-Key gets the same reply", again == first, f"{again} after {first}")
    status, body = approver.call("POST", f"/cases/{q(caseid)}/approvals", {**decision, "comment": "another body"},
                                 key=key)
    check("the same key with another body is 409 idempotency_key_reused",
          status == 409 and (body or {}).get("error") == "idempotency_key_reused", f"{status} {body}")

    final = settle(caseid, "S2", CLOSED) or {}
    check(f"S2 {caseid} resolves as a resend", (final.get("state"), final.get("disposition")) == ("resolved", "resend"),
          f"{final.get('state')} {final.get('disposition')}")
    late = approver.call("POST", f"/cases/{q(caseid)}/approvals", decision, key=key)
    check("after it resolves, the same key still gets the first reply", late == first, f"{late} after {first}")
    status, body = approver.call("POST", f"/cases/{q(caseid)}/approvals", decision, key=str(uuid.uuid4()))
    check("a fresh approval of the resolved case is 409 wrong_state",
          status == 409 and (body or {}).get("error") == "wrong_state", f"{status} {body}")
    attempts = writes(caseid)
    stored = approvals(caseid)
    check("the case has one approval and one write attempt, which applied",
          len(stored) == 1 and len(attempts) == 1 and attempts[0].get("outcome") == "applied",
          f"{len(stored)} approvals, attempts {[a.get('outcome') for a in attempts]}")
    history = downstream(encounter).get("history") or []
    operation = (view.get("plan") or {}).get("operationKey")
    check("the receiving system's history has the operation once",
          bool(operation) and sum(1 for h in history if h.get("operation_key") == operation) == 1,
          f"{operation} in {[h.get('operation_key') for h in history]}")
    approval = stored[0] if stored else {}
    check("the approval records the signed-in approver, not the name in the body",
          approval.get("approver") == "approver" and (first[1] or {}).get("approver") == "approver",
          f"{approval.get('approver')} / {(first[1] or {}).get('approver')}")

    # The write went only after a dry run bound to the approval
    after = get(f"/cases/{q(caseid)}/plan") or {}
    rehearsal = after.get("rehearsal") or {}
    plan = after.get("plan") or {}
    written_at = attempts[0].get("expectedVersion") if attempts else None
    check("the approval binds the plan's dry run, which would apply at the version the write expects",
          bool(rehearsal) and approval.get("rehearsalId") == rehearsal.get("id") and rehearsal.get("wouldApply") is True
          and rehearsal.get("receiverVersion") == plan.get("expectedVersion") == written_at,
          f"approval's rehearsal {approval.get('rehearsalId')}, rehearsal {rehearsal.get('id')} would apply "
          f"{rehearsal.get('wouldApply')} at v{rehearsal.get('receiverVersion')}, write at v{written_at}")
    gates = [d for d in after.get("gateDecisions") or [] if d.get("stage") == "dispatch"]
    passed = {(x.get("check"), x.get("reason_code")) for x in (gates[-1].get("checks") if gates else []) or []
              if x.get("result") == "pass"}
    policy = approval.get("policyVersion")
    check(f"the dispatch gate passed APPROVAL_VALID and REHEARSED under the policy the approval bound ({policy})",
          bool(gates) and bool(policy) and gates[-1].get("policyVersion") == policy
          and {("authorization", "APPROVAL_VALID"), ("rehearsal", "REHEARSED")} <= passed,
          f"{gates[-1].get('policyVersion') if gates else 'no dispatch gate'}, passed {sorted(passed)}")

    # ---- S20: the receiving system changes after the approval ----
    expected = next((s.get("expected") or {} for s in (get("/scenarios") or {}).get("scenarios") or []
                     if s.get("id") == "S20"), {})
    case = play("S20")
    if case:
        caseid, encounter = case["caseId"], case["encounterId"]
        c = settle(caseid, "S20", {"awaiting_approval"} | CLOSED) or {}
        if check(f"S20 {caseid} waits for approval after the nurse's move", c.get("state") == "awaiting_approval",
                 c.get("state")):
            digest = (get(f"/cases/{q(caseid)}/plan") or {})["plan"]["digest"]
            status, body = approver.call("POST", f"/cases/{q(caseid)}/approvals",
                                         {"decision": "approve", "planDigest": digest, "expectedVersion": c["version"],
                                          "comment": "boundary check"}, key=str(uuid.uuid4()))
            check("approver: the approval is 202 accepted", status == 202, f"{status} {body}")
            final = settle(caseid, "S20", CLOSED) or {}
            check(f"S20 {caseid} ends blocked", final.get("state") == "blocked", final.get("state"))
            events = " ".join(e.get("text") or "" for e in get(f"/cases/{q(caseid)}/events") or [])
            check("the dispatch gate refused it: APPROVAL_RECEIVER_CHANGED", "APPROVAL_RECEIVER_CHANGED" in events,
                  "not in the case's events")
            stored = approvals(caseid)
            check("and voided the approval", len(stored) == 1 and stored[0].get("revoked") is True,
                  [(a.get("approver"), a.get("revoked")) for a in stored])
            check("with no write attempt", not writes(caseid), f"{len(writes(caseid))} attempts")
            held = downstream(encounter)
            history = held.get("history") or []
            last = history[-1].get("operation_key") if history else None
            check(f"the nurse's entry stands: {held.get('ward')}, the history ending with it",
                  held.get("ward") == expected.get("final_ward") and last == expected.get("last_operation_key"),
                  f"{held.get('ward')}, ends with {last}")

    # ---- S3: a resend of a delivery the receiver already holds ----
    case = play("S3")
    if case:
        caseid = case["caseId"]
        final = settle(caseid, "S3", CLOSED) or {}
        view = get(f"/cases/{q(caseid)}/plan") or {}
        blocks = {x.get("reason_code") for d in view.get("gateDecisions") or [] for x in d.get("checks") or []
                  if x.get("result") == "block"}
        check(f"S3 {caseid}: the rules' resend is blocked by the gate: ALREADY_COMMITTED",
              final.get("state") == "blocked" and (view.get("plan") or {}).get("disposition") == "resend"
              and "ALREADY_COMMITTED" in blocks, f"{final.get('state')}, blocks {sorted(b for b in blocks if b)}")
        check("with no write attempt", not writes(caseid), f"{len(writes(caseid))} attempts")

    return done()


if __name__ == "__main__":
    sys.exit(main())
