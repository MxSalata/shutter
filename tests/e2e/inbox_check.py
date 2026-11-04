#!/usr/bin/env python3
"""The approval through the IRIS Workflow inbox, as an approver completes it there.

    python3 tests/e2e/inbox_check.py [--url http://localhost:52773] [--container shutter]

The web application always names the plan's digest; the inbox's form starts empty, so what the approver types is what the
case workflow receives. This plays S2 on the board up to its approval and completes the Workflow task through the engine,
in a session inside the container, as the inbox's Approve does:

- with PlanDigest empty: the case blocks, says why, and writes nothing;
- after a reinvestigation, with another digest: the same;
- after another, with the plan's digest: one write, verified from the receiver's history.

Signs in as the demo users operator and approver (password from SHUTTER_PASSWORD, default "shutter"). It plays a scenario,
which resets the downstream system, so don't run it on an instance someone else is using. Exits 1 at the first difference.
"""
import argparse
import os
import subprocess
import sys

from scenario_check import Session, wait


def complete_task(container, case_id, digest):
    """EnsLib.Workflow.Engine.CompleteTask on the case's open task, with this PlanDigest, as the inbox's Approve does."""
    script = "\n".join([
        f'Set t = ##class(Shutter.Util.Workflow).OpenTaskFor("{case_id}")',
        'If \'$ISOBJECT(t) { Write !,"RESULT: no open task",! Halt }',
        'Set sc = ##class(Shutter.Util.Workflow).Assign(t, "approver")',
        f'Do t.%FormValues.SetAt("{digest}", "PlanDigest")',
        'If $SYSTEM.Status.IsOK(sc) { Set sc = t.%Save() }',
        'If $SYSTEM.Status.IsOK(sc) { Set sc = ##class(EnsLib.Workflow.Engine).CompleteTask(t, "Approve") }',
        'Write !,"RESULT: ",$SELECT($SYSTEM.Status.IsOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc)),!',
        "Halt",
    ]) + "\n"
    done = subprocess.run(["docker", "exec", "-i", container, "iris", "session", "IRIS", "-U", "SHUTTER"],
                          input=script, capture_output=True, text=True, timeout=120)
    lines = [line for line in done.stdout.splitlines() if line.startswith("RESULT: ")]
    if lines != ["RESULT: ok"]:
        raise SystemExit(f"completing the task of {case_id} failed: {lines or done.stdout[-400:]}")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--container", default=os.environ.get("CTR", "shutter"))
    p.add_argument("--timeout", type=int, default=240)
    args = p.parse_args()
    password = os.environ.get("SHUTTER_PASSWORD", "shutter")
    operator = Session(args.url).sign_in("operator", password)
    approver = Session(args.url).sign_in("approver", password)

    def state_of(case_id):
        _, body = operator.call("GET", f"/cases/{case_id}")
        return (body or {}).get("state")

    def wait_for(case_id, state):
        wait(f"{case_id} to reach {state}", lambda: state_of(case_id) == state, args.timeout)

    def last_text(case_id):
        _, body = operator.call("GET", f"/cases/{case_id}/events")
        events = body if isinstance(body, list) else (body or {}).get("events") or []
        states = [e for e in events if e.get("toState")]
        return states[-1].get("text", "") if states else ""

    def attempts(case_id):
        _, body = operator.call("GET", f"/cases/{case_id}/attempts")
        return len(body if isinstance(body, list) else (body or {}).get("attempts") or [])

    def reinvestigate(case_id):
        status, body = approver.call("POST", f"/cases/{case_id}/reinvestigate", {"reason": "inbox check"}, idempotent=True)
        if status != 202:
            raise SystemExit(f"reinvestigating {case_id} was refused: HTTP {status} {body}")
        wait_for(case_id, "awaiting_approval")

    def blocks(case_id, digest, words, what):
        complete_task(args.container, case_id, digest)
        wait_for(case_id, "blocked")
        text = last_text(case_id)
        if words not in text:
            raise SystemExit(f"{what}: the case blocked, but says {text!r}, not {words!r}")
        if attempts(case_id):
            raise SystemExit(f"{what}: the case blocked, but {attempts(case_id)} write attempts were made")
        print(f"ok      {what}: blocked, no write: {text}", flush=True)

    status, started = operator.call("POST", "/scenarios/S2/run", {"mode": "board"}, idempotent=True)
    if status not in (200, 202):
        raise SystemExit(f"S2 was refused: HTTP {status} {started}")
    floor = max(started.get("startedAt") or "", started.get("queuedAt") or "")

    def newest():
        _, body = operator.call("GET", "/cases?scenario=S2&limit=5")
        items = [c for c in (body or {}).get("items", []) if c.get("openedAt", "") >= floor]
        return items[0] if items else None

    case_id = wait("S2's case", newest, args.timeout)["caseId"]
    wait_for(case_id, "awaiting_approval")

    blocks(case_id, "", "binds nothing", "an empty PlanDigest")
    reinvestigate(case_id)
    blocks(case_id, "sha256:" + "0" * 64, "another plan digest", "another plan's digest")
    reinvestigate(case_id)

    _, plan = operator.call("GET", f"/cases/{case_id}/plan")
    digest = (plan or {}).get("digest") or ((plan or {}).get("plan") or {}).get("digest")
    if not digest:
        raise SystemExit(f"no digest in the plan of {case_id}: {str(plan)[:200]}")
    complete_task(args.container, case_id, digest)
    wait_for(case_id, "resolved")
    if attempts(case_id) != 1:
        raise SystemExit(f"the plan's digest: resolved, but {attempts(case_id)} write attempts were made")
    print(f"ok      the plan's digest: one write, verified: {last_text(case_id)}", flush=True)
    print("the Workflow inbox's approval binds the plan's digest, or nothing is dispatched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
