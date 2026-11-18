#!/usr/bin/env python3
"""The approval through the IRIS Workflow inbox, as an approver completes it there.

    python3 tests/e2e/inbox_check.py [--url http://localhost:52773] [--container shutter]

The task is bound on the server when it is made: to the case and its version, the plan and its digest, the evidence, the
rehearsal, the receiver version and epoch, the gate's policy, the site profile and the catalogue. Its form shows the plan
read-only and takes only a comment, and its PlanDigest value stays empty for the web application's decider, so an
approver presses Accept and Approve with nothing pasted. This plays S2 on the board up to its approval, reads the task's
form, and completes the Workflow task through the engine, in a session inside the container, as the inbox's Approve does:

- the form: Comment its one field, Shutter's own form page, the plan's digest bound and shown read-only with the exact
  action, PlanDigest empty;
- with the case moved after its task was made (a transition, as another job's would): the case blocks, says what moved,
  and writes nothing, though the task's own copy of the binding is set to the case's new version, so the block shows the
  workflow checks the request it sent, not the answer;
- after a reinvestigation, an answer that names another digest (as the web application's decider writes one): the same;
- after another, with nothing pasted: one write, verified from the receiver's history.

Signs in as the demo users operator and approver (password from SHUTTER_PASSWORD, default "shutter"). It plays a scenario,
which resets the downstream system, so don't run it on an instance someone else is using. Exits 1 at the first difference.
"""
import argparse
import json
import os
import subprocess
import sys

from scenario_check import Session, wait


def session(container, lines):
    """Runs ObjectScript lines in a SHUTTER session inside the container; returns the lines it wrote after "RESULT: "."""
    script = "\n".join(lines + ["Halt"]) + "\n"
    done = subprocess.run(["docker", "exec", "-i", container, "iris", "session", "IRIS", "-U", "SHUTTER"],
                          input=script, capture_output=True, text=True, timeout=120)
    found = [line[len("RESULT: "):] for line in done.stdout.splitlines() if line.startswith("RESULT: ")]
    return found or [done.stdout[-400:]]


def complete_task(container, case_id, digest=None, forge=False):
    """EnsLib.Workflow.Engine.CompleteTask on the case's open task, as the inbox's Approve does: with the form's own
    values when digest is None, else with this PlanDigest, as the web application's decider writes one. With forge, the
    task's own copy of the binding is first set to the case's version now, so only the request the workflow sent still
    holds the version the task was made for."""
    lines = [
        f'Set t = ##class(Shutter.Util.Workflow).OpenTaskFor("{case_id}")',
        'If \'$ISOBJECT(t) { Write !,"RESULT: no open task",! Halt }',
        'Set sc = ##class(Shutter.Util.Workflow).Assign(t, "approver")',
    ]
    if digest is not None:
        lines.append(f'Do t.%FormValues.SetAt("{digest}", "PlanDigest")')
    if forge:
        lines.append(f'Do t.%FormValues.SetAt(##class(Shutter.Store.Case).ByCaseId("{case_id}").Version, "Shutter.CaseVersion")')
    lines += [
        'If $SYSTEM.Status.IsOK(sc) { Set sc = t.%Save() }',
        'If $SYSTEM.Status.IsOK(sc) { Set sc = ##class(EnsLib.Workflow.Engine).CompleteTask(t, "Approve") }',
        'Write !,"RESULT: ",$SELECT($SYSTEM.Status.IsOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc)),!',
    ]
    found = session(container, lines)
    if found != ["ok"]:
        raise SystemExit(f"completing the task of {case_id} failed: {found}")


def task_form(container, case_id):
    """The case's open task's form: its fields, its template, the PlanDigest it starts with and the digest it is bound to."""
    found = session(container, [
        f'Set t = ##class(Shutter.Util.Workflow).OpenTaskFor("{case_id}")',
        'If \'$ISOBJECT(t) { Write !,"RESULT: no open task",! Halt }',
        'Set o = {"fields": (t.%FormFields), "template": (t.%FormTemplate), "planDigest": (t.%FormValues.GetAt("PlanDigest")), '
        '"bound": (t.%FormValues.GetAt("Shutter.PlanDigest")), "html": (##class(Shutter.Process.ApprovalForm).FormHTML(t))}',
        'Write !,"RESULT: ",o.%ToJSON(),!',
    ])
    try:
        return json.loads(found[0])
    except (ValueError, IndexError):
        raise SystemExit(f"reading the task of {case_id} failed: {found}")


def move_case(container, case_id):
    """A transition of the case to the state it is in, as another job's would: its version moves, nothing else."""
    found = session(container, [
        f'Set c = ##class(Shutter.Store.Case).ByCaseId("{case_id}")',
        'Set sc = c.Transition(c.State, "The inbox check moves the case under its open task", "inbox_check")',
        'Write !,"RESULT: ",$SELECT($SYSTEM.Status.IsOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc)),!',
    ])
    if found != ["ok"]:
        raise SystemExit(f"moving {case_id} failed: {found}")


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

    def plan_digest(case_id):
        _, plan = operator.call("GET", f"/cases/{case_id}/plan")
        digest = (plan or {}).get("digest") or ((plan or {}).get("plan") or {}).get("digest")
        if not digest:
            raise SystemExit(f"no digest in the plan of {case_id}: {str(plan)[:200]}")
        return digest

    def blocks(case_id, digest, words, what, forge=False):
        complete_task(args.container, case_id, digest, forge)
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

    digest = plan_digest(case_id)
    form = task_form(args.container, case_id)
    want = {"fields": "Comment", "template": "Shutter.Process.ApprovalForm.cls", "planDigest": "", "bound": digest}
    got = {k: form.get(k) for k in want}
    if got != want:
        raise SystemExit(f"the task's form is {got}, not {want}")
    html = form.get("html") or ""
    if f'readonly aria-label="Plan digest" style="width:100%;max-width:78ch;box-sizing:border-box" value="{digest}"' not in html or html.count('name="') != 1 or 'name="Comment"' not in html:
        raise SystemExit(f"the task's form does not show the digest read-only with Comment its one field: {html[:600]}")
    if "<th scope=\"row\">Exact action</th><td>" not in html:
        raise SystemExit(f"the task's form does not show the exact action: {html[:600]}")
    print("ok      the task's form: Comment its one field, the plan and its digest bound and shown read-only", flush=True)

    move_case(args.container, case_id)
    blocks(case_id, None, "the case moved: version", "the case moved after its task was made, the task's own copy of the binding set to the case's new version", forge=True)
    reinvestigate(case_id)
    blocks(case_id, "sha256:" + "0" * 64, "another plan digest", "an answer naming another plan's digest")
    reinvestigate(case_id)

    digest = plan_digest(case_id)
    if task_form(args.container, case_id).get("bound") != digest:
        raise SystemExit(f"the new task of {case_id} is not bound to its plan's digest {digest}")
    complete_task(args.container, case_id)
    wait_for(case_id, "resolved")
    if attempts(case_id) != 1:
        raise SystemExit(f"nothing pasted: resolved, but {attempts(case_id)} write attempts were made")
    print(f"ok      nothing pasted: one write, verified: {last_text(case_id)}", flush=True)
    print("the Workflow inbox's approval is bound on the server to the plan, the case and the receiver, or nothing is dispatched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
