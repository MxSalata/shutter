#!/usr/bin/env python3
"""A resend whose answer never came: the receiver applies it after Shutter's connector has given up.

    python3 tests/e2e/lost_answer_check.py [--url http://localhost:52773] [--seconds 50] [--mode rules]

Plays S2 until its plan waits for approval, makes the demo receiver hold that one operation for --seconds (the connector
gives up at 15 s, and the receiver then applies it, CONTRACTS 1.5), and approves. The product's central promise is on the
line: a write nobody answered must never read as nothing sent. So the check asks for one write attempt recorded as
uncertain, no verification that says not committed before the receiver's write landed, the case resolved as verified and
never blocked, no event that says the write was refused, and the receiver holding the transfer exactly once. With
--seconds at 50 the write lands 35 s after the attempt is recorded, past the read at 30 s, so the settle window is on
trial too (CONTRACTS 1.3 and 5.1). The default is 50 because a hold of 60 s can tie with the web gateway's own timeout
of 60 s: one run in four at 60 s never wrote, and five in five at 50 s did.

Signs in as the demo users `operator` and `approver` (password from SHUTTER_PASSWORD, default "shutter"); the receiver
is read and faulted through its API (--downstream-user and --downstream-password, default _SYSTEM / SYS). It plays a
scenario, which resets the receiver, so don't run it on an instance someone else is using. Exit status 1 when a check
fails. Standard library only.
"""
import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

from scenario_check import Session, downstream_encounter, wait, wait_until_idle

CLOSED = {"resolved", "blocked", "escalated", "failed"}
FAILURES = []


def check(what, ok, detail=""):
    print(f"{'ok' if ok else 'NOT OK'}  {what}{f': {detail}' if detail and not ok else ''}", flush=True)
    if not ok:
        FAILURES.append(what)


def set_fault(args, body):
    """Sets a fault on the demo receiver; only a user holding its admin resource may."""
    request = urllib.request.Request(args.url.rstrip("/") + "/downstream/api/faults", data=json.dumps(body).encode(),
                                     method="POST")
    token = base64.b64encode(f"{args.downstream_user}:{args.downstream_password}".encode()).decode()
    request.add_header("Authorization", "Basic " + token)
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--seconds", type=int, default=50, help="how long the receiver holds the write, above 15")
    p.add_argument("--mode", default="rules", help="the mode S2 is played in; rules needs no recordings")
    p.add_argument("--timeout", type=int, default=300, help="seconds to wait for each step")
    p.add_argument("--downstream-user", default="_SYSTEM")
    p.add_argument("--downstream-password", default="SYS")
    args = p.parse_args()

    password = os.environ.get("SHUTTER_PASSWORD", "shutter")
    operator = Session(args.url).sign_in("operator", password)
    approver = Session(args.url).sign_in("approver", password)

    wait_until_idle(operator, args.timeout)
    status, started = operator.call("POST", "/scenarios/S2/run", {"mode": args.mode}, idempotent=True)
    if status not in (200, 202):
        raise SystemExit(f"the run was refused: HTTP {status} {started}")
    floor = max(started.get("startedAt") or "", started.get("queuedAt") or "")

    def waiting_case():
        _, body = operator.call("GET", "/scenarios")
        if ((body or {}).get("run") or {}).get("state") == "running":
            return None
        _, listing = operator.call("GET", "/cases?scenario=S2&limit=5")
        for c in (listing or {}).get("items", []):
            if c.get("openedAt", "") >= floor and c.get("state") == "awaiting_approval":
                return c
        return None

    case = wait("S2's plan waiting for approval", waiting_case, args.timeout)
    path = "/cases/" + urllib.parse.quote(case["caseId"])
    print(f"case {case['caseId']}, {case['encounterId']}, operation {case['operationKey']}", flush=True)
    before = downstream_encounter(args.url, args.downstream_user, args.downstream_password, case["encounterId"])

    status = set_fault(args, {"mode": "delay_response", "seconds": args.seconds, "operation_key": case["operationKey"]})
    check("the receiver takes the fault", status == 200, f"HTTP {status}")

    _, current = operator.call("GET", path)
    _, view = operator.call("GET", path + "/plan")
    decision = {"decision": "approve", "planDigest": view["plan"]["digest"], "expectedVersion": current["version"],
                "comment": "lost answer check"}
    status, body = approver.call("POST", path + "/approvals", decision, idempotent=True)
    if status != 202:
        raise SystemExit(f"the approval was refused: HTTP {status} {body}")

    def closed():
        _, c = operator.call("GET", path)
        return c if c["state"] in CLOSED else None

    final = wait(f"{case['caseId']}: closed", closed, args.timeout)
    set_fault(args, {"mode": "off"})

    _, attempts = operator.call("GET", path + "/attempts")
    attempts = attempts or []
    outcomes = [(x.get("attempt") or {}).get("outcome") for x in attempts]
    check("one write attempt, recorded as uncertain", outcomes == ["uncertain"], str(outcomes))
    check("the case resolved", final["state"] == "resolved", f"{final['state']}: {final.get('headline')}")
    check("its outcome is the receiver's committed write", "Committed" in (final.get("outcome") or ""),
          str(final.get("outcome")))

    _, reason = operator.call("GET", path + "/blocked-reason")
    text = json.dumps(reason or {}).lower()
    check("no reason says the write was refused or nothing changed",
          "refused" not in text and "nothing changed" not in text, text[:300])

    _, events = operator.call("GET", path + "/events?limit=200")
    rows = events if isinstance(events, list) else (events or {}).get("items", [])
    words = [str(e.get("text") or e.get("detail") or "") for e in rows]
    said = [w for w in words if "write was refused" in w or "Dispatch refused" in w or w.startswith("Dispatch: error")]
    check("no event calls the lost answer a refusal", not said, "; ".join(said)[:300])
    premature = [w for w in words if w.startswith("Verification: not_committed")]
    check("no verification said not committed", not premature, "; ".join(premature)[:300])

    held = downstream_encounter(args.url, args.downstream_user, args.downstream_password, case["encounterId"])
    entries = [h for h in held.get("history", []) if h.get("operation_key") == case["operationKey"]]
    check("the receiver holds the write exactly once", len(entries) == 1, str(entries)[:300])
    check("the receiver moved one version", held.get("version") == (before.get("version") or 0) + 1,
          f"{before.get('version')} to {held.get('version')}")

    print(f"{len(FAILURES)} failed" if FAILURES else "all as expected", flush=True)
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
