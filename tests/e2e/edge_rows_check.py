#!/usr/bin/env python3
"""Plays the rows of docs/edge-cases.md that need the production, on an instance with the repository mounted whole.

    python3 tests/e2e/edge_rows_check.py --url http://localhost:52773 [--ns SHUTTER] [S22b S2 S11 ...]

  S2   The write lands, and the answer says conflict (the demo receiver's commit_then_409): one write. In site policy the
       case resolves from the receipt; in rules only it stops for a person, saying the receiver already committed it.
  S11  Someone resends by hand while the incident waits: that chain stops at the sequence rule, nothing more goes to it,
       and the other chains carry on.
  S22b A write to one of two receivers: the other's version doesn't move, and its own plan still waits.
  S6b, S22c, S3b, S1b, S2b, S25b, S25c
       Variants of the listed scenarios (tests/e2e/edge-fixtures, made by its generate.py), judged by scenario_check's own
       comparison plus the history where the scenario asks for it.

The variants sit apart from fixtures/, so the demo's list stays as it is: the check points the runner at them with
Shutter_Test.EdgeFixtures_Use, which needs tests/unit loaded and tests/e2e/edge-fixtures in the container, as in CI (the
compose demo mounts neither, and the check stops at once there). It points the runner back when it ends, and first, in
case an earlier run was killed before it could. Signs in as the demo users
`operator` and `approver` (password from SHUTTER_PASSWORD, default "shutter"). Each run resets the receivers, so don't run it
on an instance someone else is using. Exit status 1 when a check fails. Standard library only.
"""
import argparse
import base64
import copy
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

from iris_query import query
from scenario_check import (CLOSED, DEFAULT_BASE, Session, downstream_encounter, play, play_incident, receiver_base, wait,
                            wait_until_idle)

FAILURES = []
VARIANTS = ["S6b", "S22c", "S3b", "S1b", "S2b", "S25b", "S25c"]


def check(what, ok, detail=""):
    print(f"{'ok' if ok else 'NOT OK'}  {what}{f': {detail}' if detail and not ok else ''}", flush=True)
    if not ok:
        FAILURES.append(what)


def receiver_call(args, method, path, body=None, base=DEFAULT_BASE):
    """A call on a demo receiver's API, as its administrator."""
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(args.url.rstrip("/") + base + path, data=data, method=method)
    token = base64.b64encode(f"{args.downstream_user}:{args.downstream_password}".encode()).decode()
    request.add_header("Authorization", "Basic " + token)
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            text = response.read().decode()
            return response.status, json.loads(text) if text else None
    except urllib.error.HTTPError as error:
        text = error.read().decode()
        return error.code, text


def case_path(case):
    return "/cases/" + urllib.parse.quote(case["caseId"])


def start(operator, scenario, mode, timeout):
    wait_until_idle(operator, timeout)
    status, started = operator.call("POST", f"/scenarios/{scenario}/run", {"mode": mode}, idempotent=True)
    if status not in (200, 202):
        raise RuntimeError(f"{scenario} was refused: HTTP {status} {started}")
    return max(started.get("startedAt") or "", started.get("queuedAt") or "")


def approve(approver, operator, case, comment):
    path = case_path(case)
    _, current = operator.call("GET", path)
    _, view = operator.call("GET", path + "/plan")
    decision = {"decision": "approve", "planDigest": view["plan"]["digest"], "expectedVersion": current["version"],
                "comment": comment}
    status, body = approver.call("POST", path + "/approvals", decision, idempotent=True)
    if status != 202:
        raise RuntimeError(f"the approval of {case['caseId']} was refused: HTTP {status} {body}")


def closed_case(operator, case, timeout):
    def closed():
        _, c = operator.call("GET", case_path(case))
        return c if c["state"] in CLOSED else None

    return wait(f"{case['caseId']}: closed", closed, timeout)


def outcomes_of(operator, case):
    _, attempts = operator.call("GET", case_path(case) + "/attempts")
    return [(x.get("attempt") or {}).get("outcome") for x in attempts or []]


def conflict_after_commit(args, operator, approver, mode):
    """S2's resend reaches the receiver and commits, and the answer is a 409. In site policy the case then finds the receipt
    and closes by itself; in rules only, which always plans a resend, the gate refuses that plan and a person decides."""
    print(f"-- the write lands, and the answer says conflict ({mode})", flush=True)
    floor = start(operator, "S2", mode, args.timeout)

    def opened():
        _, body = operator.call("GET", "/scenarios")
        if ((body or {}).get("run") or {}).get("state") == "running":
            return None
        _, listing = operator.call("GET", "/cases?scenario=S2&limit=5")
        mine = [c for c in (listing or {}).get("items", []) if c.get("openedAt", "") >= floor]
        return mine[0] if mine else None

    # The scenario's own steps end with the faults off, so this one goes on after them, before the case sends anything
    case = wait("S2's case", opened, args.timeout, every=1)
    before = downstream_encounter(args.url, args.downstream_user, args.downstream_password, case["encounterId"])
    status, _ = receiver_call(args, "POST", "/faults", {"mode": "commit_then_409", "operation_key": case["operationKey"]})
    check("the receiver takes the fault", status == 200, f"HTTP {status}")
    approved = set()

    def closed_or_approved():
        _, c = operator.call("GET", case_path(case))
        if c["state"] in CLOSED:
            return c
        if c["state"] == "awaiting_approval" and c["version"] not in approved:
            approved.add(c["version"])
            approve(approver, operator, case, "edge rows check")
        return None

    final = wait(f"{case['caseId']}: closed", closed_or_approved, args.timeout)
    receiver_call(args, "POST", "/faults", {"mode": "off"})
    outcomes = outcomes_of(operator, case)
    print(f"   {case['caseId']}: {final['state']}, {final.get('disposition')}, attempts {outcomes}", flush=True)
    check("the write was answered with the conflict", outcomes[:1] == ["version_conflict"], str(outcomes))
    if mode == "policy":
        check("the case resolved", final["state"] == "resolved", f"{final['state']}: {final.get('headline')}")
        check("by reconciling", final.get("disposition") == "reconcile", str(final.get("disposition")))
        check("from the receiver's receipt", "Committed" in (final.get("outcome") or ""), str(final.get("outcome")))
    else:
        _, reason = operator.call("GET", case_path(case) + "/blocked-reason")
        check("the case stops for a person", final["state"] == "blocked", f"{final['state']}: {final.get('headline')}")
        check("and says the receiver already committed it", (reason or {}).get("code") == "ALREADY_COMMITTED", str(reason)[:200])
    check("no attempt reads as applied by the answer it got", "applied" not in outcomes, str(outcomes))
    held = downstream_encounter(args.url, args.downstream_user, args.downstream_password, case["encounterId"])
    entries = [h for h in held.get("history", []) if h.get("operation_key") == case["operationKey"]]
    check("the receiver holds the write exactly once", len(entries) == 1, str(entries)[:300])
    check("the receiver moved one version", held.get("version") == (before.get("version") or 0) + 1,
          f"{before.get('version')} to {held.get('version')}")


class HandFirst:
    """The approver, except that the first approval of an incident is preceded by a person's hand resend at the receiver."""

    def __init__(self, approver, hand):
        self.approver, self.hand, self.done = approver, hand, False

    def call(self, method, path, body=None, idempotent=False):
        if not self.done and method == "POST" and path.startswith("/incidents/") and path.endswith("/approvals"):
            self.done = True
            self.hand()
        return self.approver.call(method, path, body, idempotent)


def hand_resend_in_incident(args, operator, approver, listing):
    """S11 until its incident waits for approval, then a person resends one chain's first item by hand."""
    print("-- someone resends by hand while the incident waits", flush=True)
    scenario = copy.deepcopy(listing["S11"])
    encounter = "ENC-1102"
    wants = scenario["expected"]["encounters"]
    want = next(w for w in wants if w["encounter"] == encounter)
    # The hand resend's receipt makes the first item E3's, and it stops there; the rest of the chain stays E4's
    want.update({"entries": ["E3", "E4"], "writes": 0, "final_state": "admitted", "final_ward": "WARD-B"})
    seen = {}

    def hand():
        _, body = operator.call("GET", f"/cases?scenario=S11&limit=50")
        mine = [c for c in (body or {}).get("items", []) if c.get("encounterId") == encounter and c.get("event") == "transfer"]
        case = mine[0]
        seen["case"] = case
        source, authority, patient, _, event, when = case["operationKey"].split("^")
        status, answer = receiver_call(args, "POST", "/operations", {
            "operation_key": case["operationKey"], "encounter_id": encounter, "patient_id": patient,
            "patient_id_authority": authority, "event": event, "ward": "WARD-B", "bed": "02", "event_time": when,
            "source_system": source, "expected_version": 1})
        check("the hand resend lands at the receiver", status == 201, f"HTTP {status} {answer}")

    ok, line, _ = play_incident(args, operator, HandFirst(approver, hand), scenario, "policy")
    print("   " + line, flush=True)
    check("the other chains carry on, and this one wrote nothing", bool(ok), line)
    if "case" not in seen:
        check("the incident waited for an approval", False)
        return
    _, c = operator.call("GET", case_path(seen["case"]))
    print(f"   {seen['case']['caseId']}: {c['state']}: {c.get('headline')}", flush=True)
    check("the first item stops at the sequence rule", c["state"] == "blocked" and "sequence rule" in (c.get("headline") or "").lower(),
          f"{c['state']}: {c.get('headline')}")
    _, listing_ = operator.call("GET", "/cases?scenario=S11&limit=50")
    others = [x for x in (listing_ or {}).get("items", []) if x.get("encounterId") == encounter and x["caseId"] != c["caseId"]]
    for other in others:
        check(f"the rest of the chain sends nothing ({other.get('event')})", not outcomes_of(operator, other),
              str(outcomes_of(operator, other)))
    held = downstream_encounter(args.url, args.downstream_user, args.downstream_password, encounter)
    keys = [h.get("operation_key") for h in held.get("history", [])]
    check("the receiver holds the admission and the hand resend, once", len(keys) == 2 and keys[1] == seen["case"]["operationKey"], str(keys))


def write_to_one(args, operator, approver):
    """A transfer failed at two receivers; approving one case writes to that receiver alone."""
    print("-- a write to one of two receivers", flush=True)
    floor = start(operator, "S22b", "rules", args.timeout)

    def waiting():
        _, body = operator.call("GET", "/scenarios")
        if ((body or {}).get("run") or {}).get("state") == "running":
            return None
        _, listing = operator.call("GET", "/cases?scenario=S22b&limit=10")
        found = {c.get("receiver"): c for c in (listing or {}).get("items", [])
                 if c.get("openedAt", "") >= floor and c.get("state") == "awaiting_approval"}
        return found if {"Downstream Out", "Records Out"} <= set(found) else None

    cases = wait("a plan waiting at each receiver", waiting, args.timeout)
    bed, records = cases["Downstream Out"], cases["Records Out"]
    records_base = receiver_base(operator, "Records Out")

    def held(base):
        return downstream_encounter(args.url, args.downstream_user, args.downstream_password, bed["encounterId"], base)

    check("both receivers start at version 1", held(DEFAULT_BASE).get("version") == 1 and held(records_base).get("version") == 1)
    approve(approver, operator, bed, "edge rows check")
    final = closed_case(operator, bed, args.timeout)
    check("the approved case resolved", final["state"] == "resolved", f"{final['state']}: {final.get('headline')}")
    now = held(DEFAULT_BASE)
    check("its receiver moved one version, to Ward B", now.get("version") == 2 and now.get("ward") == "WARD-B", str(now)[:200])
    other = held(records_base)
    check("the other receiver's version didn't move", other.get("version") == 1 and other.get("ward") == "WARD-A", str(other)[:200])
    status, _ = receiver_call(args, "GET", "/receipts/" + urllib.parse.quote(bed["operationKey"], safe=""), base=records_base)
    check("the other receiver holds no receipt for it", status == 404, f"HTTP {status}")
    _, still = operator.call("GET", case_path(records))
    check("and the other receiver's case still waits for its own approval", still["state"] == "awaiting_approval", still["state"])
    approve(approver, operator, records, "edge rows check")
    final = closed_case(operator, records, args.timeout)
    other = held(records_base)
    check("approved in turn, it writes there", final["state"] == "resolved" and other.get("version") == 2, f"{final['state']}, version {other.get('version')}")
    check("and the first receiver doesn't move again", held(DEFAULT_BASE).get("version") == 2)


def variant(args, operator, approver, listing, sid, mode):
    print(f"-- {sid}: {listing[sid]['title']}", flush=True)
    ok, line, _ = play(args, operator, approver, listing[sid], mode)
    print("   " + line.replace("\n", "\n   "), flush=True)
    check(f"{sid} as expected", bool(ok), line)
    key = listing[sid]["expected"].get("history_once")
    if key:
        encounter = key.split("^")[3]
        held = downstream_encounter(args.url, args.downstream_user, args.downstream_password, encounter)
        keys = [h.get("operation_key") for h in held.get("history", [])]
        check(f"{sid}: the receiver holds the sender's repeat and nothing of Shutter's", keys[1:] == [key], str(keys))


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("only", nargs="*", help="the rows to play: S2, S11, S22b or a variant; all of them when none is named")
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--ns", default="SHUTTER")
    p.add_argument("--timeout", type=int, default=240, help="seconds to wait for each step")
    p.add_argument("--downstream-user", default="_SYSTEM")
    p.add_argument("--downstream-password", default="SYS")
    args = p.parse_args()
    args.approve = True
    wanted = args.only or ["S2", "S11", "S22b"] + VARIANTS

    password = os.environ.get("SHUTTER_PASSWORD", "shutter")
    operator = Session(args.url).sign_in("operator", password)
    approver = Session(args.url).sign_in("approver", password)

    def listed():
        _, body = operator.call("GET", "/scenarios")
        return {s["id"]: s for s in (body or {}).get("scenarios", [])}

    use = "SELECT Shutter_Test.EdgeFixtures_Use(?) AS r"
    query(args.url, args.ns, use, (0,))
    try:
        for row, run in (("S2", lambda: (conflict_after_commit(args, operator, approver, "policy"),
                                         conflict_after_commit(args, operator, approver, "rules"))),
                         ("S11", lambda: hand_resend_in_incident(args, operator, approver, listed()))):
            if row in wanted:
                try:
                    run()
                except (TimeoutError, RuntimeError) as error:
                    check(f"{row} played to its end", False, str(error))
        rest = [w for w in wanted if w not in ("S2", "S11")]
        if rest:
            where = query(args.url, args.ns, use, (1,))[0]["r"]
            if where.startswith("no scenarios.json"):
                raise SystemExit(f"the variants can't be read: {where}")
            print(f"-- the runner reads {where}", flush=True)
            listing = listed()
            for sid in rest:
                try:
                    if sid == "S22b":
                        write_to_one(args, operator, approver)
                    else:
                        variant(args, operator, approver, listing, sid, listing[sid]["expected"]["modes"][0])
                except (TimeoutError, RuntimeError, KeyError) as error:
                    check(f"{sid} played to its end", False, repr(error))
    finally:
        query(args.url, args.ns, use, (0,))
    print(f"{len(FAILURES)} failed: " + "; ".join(FAILURES) if FAILURES else "all as expected", flush=True)
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
