#!/usr/bin/env python3
"""Failed deliveries Shutter has never seen, on an instance with no recording for them and no model provider.

    python3 tests/e2e/unseen_input_check.py [--url http://localhost:52773] [--timeout 300]

Replay answers a board member only from a recording under that run's key, and the recordings are made for the scenarios'
cases. This plays patients and visits that no fixture holds, through the feed and not as a scenario, in Board mode:

- plain: admitted to WARD-A, then a transfer to WARD-B that the receiver refuses before accepting it, and nothing since.
  With no board answer the rules path proposes the plain resend, and the gate and a dry run pass it: the case must wait for
  an approver, with the exact plan and an approval task, and nothing written;
- the board's case: the same, then the bed manager's own transfer to WARD-C, timed the same minute, applies. Neither event
  is later, so the catalogue gives it to the board, and with no board answer the case must close for a person as
  NO_BOARD_ANSWER, with WARD-C kept.

For each case it checks and prints:

- the case is no scenario's, so no scenario's recording can be used for it, and each board member's run looked up its
  own key, found no recording (no_record) and was not live, at no cost and with no tokens; no tool was called, and the
  recordings on the instance are the same before and after, so no model provider was called and nothing was recorded;
- the reason the case fell back, from its own events;
- nothing was written: no write attempt on the case, and the receiver holds the patient where it did, at the same version;
- the outcome is a person's to act on: an approval task for the exact plan, or a closed case with a reason code and a
  headline that says why.

Signs in as the demo user operator (password from SHUTTER_PASSWORD, default "shutter"); the receiver is read and faulted
through its API as _SYSTEM / SYS (--downstream-user, --downstream-password). It resets the instance first, like a scenario,
so don't run it on an instance someone else is using. It refuses to run on an instance with a model provider configured or
the API mimic switched on, since a live board would answer there. Exit status 1 when a check fails. Standard library only.
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

from iris_query import query
from scenario_check import Session, downstream_encounter, wait, wait_until_idle

FAILED = []
SETTLED = ("awaiting_approval", "blocked", "escalated", "resolved", "failed")


def check(what, ok, detail=""):
    print(f"{'ok     ' if ok else 'DIFFERS'} {what}{f': {detail}' if detail and not ok else ''}", flush=True)
    if not ok:
        FAILED.append(what)


def note(what):
    print(f"        {what}", flush=True)


def message(sender, trigger, control, when, mrn, visit, ward, bed):
    """An ADT message in the fixtures' shape, for a patient no fixture has."""
    structure = {"A01": "ADT_A01", "A02": "ADT_A02"}[trigger]
    return "<CR>".join([
        f"MSH|^~\\&|{sender}|HOSP|DOWNSTREAM|HOSP|{when}||ADT^{trigger}^{structure}|{control}|P|2.5.1",
        f"EVN|{trigger}|{when}||||{when}",
        f"PID|1||{mrn}^^^HOSP^MR||UNSEEN^NEWCOMER||19810314|F",
        f"PV1|1|I|{ward}^{bed}^HOSP||||||||||||||||{visit}|||||||||||||||||||||||||20261015090000",
    ])


def set_fault(args, mode):
    """Sets a fault on the demo receiver; only a user holding its admin resource may."""
    request = urllib.request.Request(args.url.rstrip("/") + "/downstream/api/faults", data=json.dumps({"mode": mode}).encode(),
                                     method="POST")
    token = base64.b64encode(f"{args.downstream_user}:{args.downstream_password}".encode()).decode()
    request.add_header("Authorization", "Basic " + token)
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def drop(args, name, text):
    got = query(args.url, "SHUTTER", "SELECT Shutter_Test.Feed_Drop(?, ?) AS r", [name, text])[0]["r"]
    if str(got).startswith("error"):
        raise SystemExit(f"the feed took nothing: {got}")


def count(args, sql, params=()):
    return int(query(args.url, "SHUTTER", sql, params)[0]["n"])


def unseen(args, n):
    """A patient number and a visit number that no fixture file and no case on the instance holds; the beds are the nth."""
    stamp = int(time.time()) % 100000
    mrn, visit = f"MRN6{stamp:05d}{n}", f"ENC-6{stamp:05d}{n}"
    root = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "fixtures")
    for folder, _, files in os.walk(root):
        for name in files:
            try:
                with open(os.path.join(folder, name), encoding="utf-8", errors="replace") as f:
                    text = f.read()
            except OSError:
                continue
            if mrn in text or visit in text:
                raise SystemExit(f"{visit} or {mrn} is in {os.path.join(folder, name)}: not unseen")
    if count(args, "SELECT COUNT(*) AS n FROM Shutter_Store.\"Case\" WHERE EncounterId = ?", [visit]):
        raise SystemExit(f"{visit} already has a case")
    return mrn, visit


def play(args, operator, shape, n):
    mrn, visit = unseen(args, n)
    print(f"-- {shape}: patient {mrn}, visit {visit}, Board mode", flush=True)
    query(args.url, "SHUTTER", "SELECT Shutter_Test.Feed_Mode('board') AS r")
    held = lambda: downstream_encounter(args.url, args.downstream_user, args.downstream_password, visit)
    drop(args, f"unseen-{visit}-1.hl7", message("PAS", "A01", f"{visit}-1", "20261015090000", mrn, visit, "WARD-A", f"BAY9^0{n + 1}"))
    wait(f"{visit} admitted at WARD-A", lambda: held().get("ward") == "WARD-A" or None, 60)
    status = set_fault(args, "fail_before_accept")
    check(f"{shape}: the receiver takes the fault", status == 200, str(status))
    try:
        drop(args, f"unseen-{visit}-2.hl7", message("PAS", "A02", f"{visit}-2", "20261015092000", mrn, visit, "WARD-B", f"BAY8^0{n + 1}"))
        time.sleep(6)
    finally:
        set_fault(args, "off")
    ward = "WARD-A"
    if shape == "board's case":
        drop(args, f"unseen-{visit}-3.hl7", message("BEDMGR", "A02", f"{visit}-3", "20261015092000", mrn, visit, "WARD-C", f"BAY7^0{n + 1}"))
        wait(f"{visit} at WARD-C by the bed manager's own transfer", lambda: held().get("ward") == "WARD-C" or None, 60)
        ward = "WARD-C"
    before = held()

    def settled():
        _, listing = operator.call("GET", "/cases?limit=20")
        for c in (listing or {}).get("items", []):
            if c.get("encounterId") == visit and c.get("state") in SETTLED:
                return c
        return None

    case = wait(f"{visit}: a case that waits for a person or is closed", settled, args.timeout)
    case_id = case["caseId"]
    time.sleep(3)
    _, full = operator.call("GET", f"/cases/{case_id}")
    full = full or {}
    note(f"{case_id}: state {full.get('state')}, plan by {full.get('planCreatedBy')!r}, headline {full.get('headline')!r}")
    check(f"{shape}: {case_id} is no scenario's case", not full.get("scenario"), str(full.get("scenario")))

    # Recording selection: each member's run looked up its own key, found none, and no provider was called.
    runs = query(args.url, "SHUTTER", "SELECT MemberCode AS member, Mode AS mode, Status AS status, CostUSD AS cost, "
                 "PromptTokens AS prompt, CompletionTokens AS completion, ToolCallCount AS tools, Error AS error "
                 "FROM Shutter_Store.AgentRun WHERE \"Case\"->CaseId = ? ORDER BY ID", [case_id])
    for r in runs:
        note(f"run {r['member']}: mode {r['mode']}, status {r['status']}, cost {r['cost']}, "
             f"tokens {r['prompt'] or 0}/{r['completion'] or 0}: {str(r['error'] or '')[:170]}")
    check(f"{shape}: the board was asked", len(runs) > 0, "no agent run")
    check(f"{shape}: no run was live", all((r["mode"] or "") == "replay" for r in runs), str([r["mode"] for r in runs]))
    check(f"{shape}: every run found no recording", all(r["status"] == "no_record" for r in runs), str([r["status"] for r in runs]))
    check(f"{shape}: each looked up a key of this case's own evidence, not a scenario's",
          all("No recording for digest:" in str(r["error"] or "") and "scenario:" not in str(r["error"] or "") for r in runs),
          str([r["error"] for r in runs])[:400])
    check(f"{shape}: no run cost anything, used a token or called a tool",
          all(not float(r["cost"] or 0) and not int(r["prompt"] or 0) and not int(r["completion"] or 0)
              and not int(r["tools"] or 0) for r in runs), str(runs)[:300])
    _, events = operator.call("GET", f"/cases/{case_id}/events")
    events = events if isinstance(events, list) else (events or {}).get("items", [])
    texts = [str(e.get("text") or "") for e in events]
    fallback = next((t for t in texts if "has no recording" in t), "")
    note(f"fallback: {fallback[-300:]}")
    check(f"{shape}: the case says why it fell back", bool(fallback), str(texts)[-400:])

    # No write.
    _, attempts = operator.call("GET", f"/cases/{case_id}/attempts")
    writes = [x for x in attempts or [] if x.get("attempt")]
    check(f"{shape}: no write attempt", not writes, str(writes)[:300])
    stored = count(args, "SELECT COUNT(*) AS n FROM Shutter_Store.ExecutionAttempt WHERE \"Case\"->CaseId = ?", [case_id])
    check(f"{shape}: no execution attempt is stored", stored == 0, str(stored))
    now = held()
    check(f"{shape}: the receiver still holds {visit} at {ward}", now.get("ward") == ward, str(now)[:300])
    check(f"{shape}: at the same version", now.get("version") == before.get("version"),
          f"{before.get('version')} then {now.get('version')}")

    # A person's outcome.
    if shape == "plain":
        check(f"{shape}: the case waits for an approver", full.get("state") == "awaiting_approval", str(full.get("state")))
        check(f"{shape}: with the plan the rules proposed", full.get("planCreatedBy") == "rules", str(full.get("planCreatedBy")))
        _, approvals = operator.call("GET", f"/cases/{case_id}/approvals")
        tasks = [t for t in (approvals or {}).get("tasks", []) if not t.get("complete")]
        note(f"approval task: {tasks[0].get('subject') if tasks else None}, for {tasks[0].get('role') if tasks else None}")
        check(f"{shape}: an approval task waits for the approvers", bool(tasks) and case_id in tasks[0].get("subject", ""),
              str(approvals)[:300])
        check(f"{shape}: and nobody has approved", not (approvals or {}).get("approvals"), str(approvals)[:300])
    else:
        check(f"{shape}: the case is closed for a person", full.get("state") in ("escalated", "blocked"), str(full.get("state")))
        _, reason = operator.call("GET", f"/cases/{case_id}/blocked-reason")
        reason = reason or {}
        note(f"reason {reason.get('code')}: {reason.get('headline')}")
        check(f"{shape}: it names NO_BOARD_ANSWER", reason.get("code") == "NO_BOARD_ANSWER", str(reason)[:300])
        check(f"{shape}: and says why in words", len(reason.get("headline") or "") > 20, str(reason)[:300])
    return case_id


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--timeout", type=int, default=300)
    p.add_argument("--downstream-user", default="_SYSTEM")
    p.add_argument("--downstream-password", default="SYS")
    args = p.parse_args()
    operator = Session(args.url).sign_in("operator", os.environ.get("SHUTTER_PASSWORD", "shutter"))
    _, health = operator.call("GET", "/health")
    health = health or {}
    note(f"instance: version {health.get('version')}, edition {health.get('edition')}, demo {health.get('demo')}, "
         f"provider {health.get('provider')!r}, mimic {health.get('mock_config')!r}")
    if health.get("provider") or health.get("mock_config"):
        raise SystemExit("this instance has a model provider or the API mimic set: a live board would answer, so the check does not run")
    wait_until_idle(operator, 300)
    code, body = operator.call("POST", "/scenarios/reset", {})
    if code != 200:
        raise SystemExit(f"the reset was refused: HTTP {code} {body}")
    recordings = count(args, "SELECT COUNT(*) AS n FROM Shutter_Bridge.Record")
    note(f"{recordings} recordings on the instance")
    for n, shape in enumerate(("plain", "board's case")):
        play(args, operator, shape, n)
    after = count(args, "SELECT COUNT(*) AS n FROM Shutter_Bridge.Record")
    check("no recording was added or removed", after == recordings, f"{recordings} then {after}")
    print(f"{len(FAILED)} differ" if FAILED else "all as expected", flush=True)
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
