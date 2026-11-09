#!/usr/bin/env python3
"""A person releases one stop on another visit's movement, end to end, on S27 in site policy mode.

    python3 tests/e2e/further_release_check.py [--url http://localhost:52773] [--container NAME] [--timeout 180]

S27's transfer stops because the same patient was admitted under another visit number. The check reads the rows as the case
page does; the operator is refused; a wrong digest and a missing reason are refused; the approver releases, and the write then
waits for a person's approval. A further message on a third visit voids the release at the dispatch gate, with nothing sent.
The approver reads the new rows and releases again, approves, and the receiver holds the one write. It plays a scenario, so
don't run it on an instance someone else is using. Exit status 1 when a check fails. Standard library only.
"""
import argparse
import os
import subprocess
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scenario_check import Session, downstream_encounter, wait  # noqa: E402

FAILURES = []
KEY = "PAS^HOSP^MRN1027^ENC-1027^transfer^2026-10-15T08:20:00Z"


def check(what, ok, detail=""):
    print(f"{'ok' if ok else 'NOT OK'}  {what}{f': {detail}' if detail and not ok else ''}", flush=True)
    if not ok:
        FAILURES.append(what)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--url", default=os.environ.get("IRIS_URL", "http://localhost:52773"))
    p.add_argument("--container", default=os.environ.get("CTR", "shutter"))
    p.add_argument("--namespace", default="SHUTTER")
    p.add_argument("--timeout", type=int, default=180)
    p.add_argument("--password", default=os.environ.get("SHUTTER_PASSWORD", "shutter"))
    args = p.parse_args()
    operator = Session(args.url).sign_in("operator", args.password)
    approver = Session(args.url).sign_in("approver", args.password)

    def state_of(case_id):
        _, c = operator.call("GET", f"/cases/{case_id}")
        return c or {}

    def stopped(case_id):
        return wait(f"{case_id}: stopped", lambda: state_of(case_id) if state_of(case_id).get("state") == "blocked" else None, args.timeout)

    def asks(case_id):
        return wait(f"{case_id}: asks an approver", lambda: state_of(case_id) if state_of(case_id).get("state") == "awaiting_approval" else None, args.timeout)

    def approve(case_id):
        c = state_of(case_id)
        _, view = operator.call("GET", f"/cases/{case_id}/plan")
        return approver.call("POST", f"/cases/{case_id}/approvals", {"decision": "approve", "planDigest": view["plan"]["digest"], "expectedVersion": c["version"], "comment": "further release check"}, idempotent=True)

    before = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    status, _ = operator.call("POST", "/scenarios/S27/run", {"mode": "policy"}, idempotent=True)
    check("S27 starts in site policy mode", status in (200, 202), str(status))

    def the_case():
        _, body = operator.call("GET", "/cases?scenario=S27&limit=5")
        found = [c for c in (body or {}).get("items", []) if c.get("openedAt", "") >= before and c.get("operationKey") == KEY]
        return found[0] if found else None

    case_id = urllib.parse.quote(wait("S27: its case", the_case, args.timeout)["caseId"])
    stopped(case_id)
    _, reason = operator.call("GET", f"/cases/{case_id}/blocked-reason")
    check("the case stops for FURTHER_MOVEMENT", (reason or {}).get("code") == "FURTHER_MOVEMENT", str(reason))

    status, stop = operator.call("GET", f"/cases/{case_id}/further-stop")
    check("the rows are read", status == 200 and len(stop["rows"]) == 1 and "ENC-2027" in stop["rows"][0]["line"], str(stop))
    check("and can be released", stop["releasable"] is True and stop["digest"].startswith("sha256:"), str(stop))

    status, body = operator.call("POST", f"/cases/{case_id}/further-release", {"digest": stop["digest"], "reason": "I read both"}, idempotent=True)
    check("an operator is refused", status == 403, f"{status} {body}")
    status, body = approver.call("POST", f"/cases/{case_id}/further-release", {"digest": "sha256:other", "reason": "I read both"}, idempotent=True)
    check("a wrong digest is refused", status == 409 and body.get("error") == "rows_changed", f"{status} {body}")
    status, body = approver.call("POST", f"/cases/{case_id}/further-release", {"digest": stop["digest"], "reason": "  "}, idempotent=True)
    check("no reason is refused", status == 400 and body.get("field") == "reason", f"{status} {body}")
    check("nothing moved", state_of(case_id).get("state") == "blocked")

    status, body = approver.call("POST", f"/cases/{case_id}/further-release", {"digest": stop["digest"], "reason": "A separate spell: I read both visits"}, idempotent=True)
    check("the approver releases the rows they read", status == 202, f"{status} {body}")
    asks(case_id)
    check("the write still waits for a person's approval", True)

    # A further message on a third visit, as the index would hold it: the dispatch gate reads it and the release is void.
    code = ('Set r = ##class(Shutter.Index.Message).%New(), r.DocId = "UT-RELEASE-1", r.PatientId = "MRN1027", r.PatientIdAuthority = "HOSP", '
            'r.VisitNumber = "ENC-3027", r.Event = "admit", r.MessageType = "ADT_A01", r.ControlId = "RELEASE-1", r.EventTime = "2026-10-15T09:40:00Z", '
            'r.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3) Set sc = r.%Save() Write !,"RESULT: ",sc,! Halt')
    # A terminal takes a licence unit, and the community licence's few are often held for a while by what ran before.
    for _ in range(18):
        done = subprocess.run(["docker", "exec", "-i", args.container, "iris", "session", "IRIS", "-U", args.namespace], input=code + "\n", capture_output=True, text=True, timeout=120)
        if "LICENSE LIMIT" not in done.stdout + done.stderr:
            break
        time.sleep(20)
    check("a further message arrives", "RESULT: 1" in done.stdout, done.stdout[-300:] + done.stderr[-300:])
    if FAILURES:
        raise SystemExit("; ".join(FAILURES) + ": stopping before the approval, which would write")
    status, body = approve(case_id)
    check("the approval is taken", status == 202, f"{status} {body}")
    stopped(case_id)
    _, reason = operator.call("GET", f"/cases/{case_id}/blocked-reason")
    check("the further message voids the release at the gate", (reason or {}).get("code") == "FURTHER_MOVEMENT", str(reason))
    held = downstream_encounter(args.url, "_SYSTEM", "SYS", "ENC-1027")
    check("and nothing was sent", held.get("ward") == "WARD-A", str(held))
    status, again = operator.call("GET", f"/cases/{case_id}/further-stop")
    check("the page shows both rows and that the release no longer holds", len(again["rows"]) == 2 and again["release"]["stands"] is False and again["digest"] != stop["digest"], str(again))

    status, body = approver.call("POST", f"/cases/{case_id}/further-release", {"digest": again["digest"], "reason": "Read the third visit too: separate"}, idempotent=True)
    check("the approver releases the new rows", status == 202, f"{status} {body}")
    asks(case_id)
    status, body = approve(case_id)
    check("and approves", status == 202, f"{status} {body}")
    final = wait(f"{case_id}: resolved", lambda: state_of(case_id) if state_of(case_id).get("state") in ("resolved", "blocked", "escalated", "failed") else None, args.timeout)
    check("the case resolves", final.get("state") == "resolved", str(final.get("headline")))
    held = downstream_encounter(args.url, "_SYSTEM", "SYS", "ENC-1027")
    check("the receiver holds the write", held.get("ward") == "WARD-B", str(held))
    _, attempts = operator.call("GET", f"/cases/{case_id}/attempts")
    writes = sum(1 for a in attempts or [] if (a.get("attempt") or {}).get("outcome") in ("applied", "already_committed"))
    check("once", writes == 1, str(writes))
    _, events = operator.call("GET", f"/cases/{case_id}/events")
    said = " ".join(e.get("text", "") for e in (events.get("events") if isinstance(events, dict) else events) or [])
    check("the reasons are on the case", "A separate spell" in said and "Read the third visit too" in said)

    if FAILURES:
        print(f"{len(FAILURES)} check(s) failed: " + "; ".join(FAILURES))
        return 1
    print("every check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
