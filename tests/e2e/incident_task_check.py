#!/usr/bin/env python3
"""An incident's approval task, over the limit its Workflow message used to break, on a running instance.

    python3 tests/e2e/incident_task_check.py --url http://127.0.0.1:PORT --ctr NAME --out DIR

Two storms through the intake route, each with its own patients, on an instance nobody else is using:

- 24 failures in 12 chains: one task is raised and its message fits; the digest is read from the message, as an approver
  in the Workflow inbox reads it, and the task is completed through the engine with that digest, as the inbox's Approve
  does; every case resolves.
- 8 failures with the approval target missing: no task can be raised, and the incident waits for a person instead of
  closing: no case fails, its timeline and an alert name the incident. The target comes back, the next try raises the
  task, the API approves, and every case resolves.

Writes DIR/result.json as it goes. Exit status: 0 held, 1 a line failed. Standard library only.
"""
import argparse
import datetime as dt
import json
import os
import re
import sys
import time
import types
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import storm_scale_check as storm  # noqa: E402

RETRY_SECONDS = 300
MISSING_TARGET = "No Such Approvers"


def own_patients(plan, first_digit):
    """The same storm with its own control ids, patients and encounters, so a second storm is not the first one again."""
    out = []
    for step in plan:
        text = step["text"].replace("STORM", f"STOR{first_digit}").replace("MRN7", f"MRN{first_digit}").replace("ENC-7", f"ENC-{first_digit}")
        out.append({**step, "text": text, "encounter": step["encounter"].replace("ENC-7", f"ENC-{first_digit}")})
    return out


def set_target(ctr, value):
    """Sets or clears the Incident Workflow's approval target and updates the running production."""
    code = "\n".join([
        'Set p = ##class(Ens.Config.Production).%OpenId("Shutter.Production")',
        'Set item = p.FindItemByConfigName("Incident Workflow")',
        'For i = item.Settings.Count():-1:1 { If item.Settings.GetAt(i).Name = "ApprovalTarget" { Do item.Settings.RemoveAt(i) } }',
        f'If "{value}" \'= "" {{ Set s = ##class(Ens.Config.Setting).%New(), s.Name = "ApprovalTarget", s.Target = "Host", s.Value = "{value}" Do item.Settings.Insert(s) }}',
        'Set sc = item.%Save() If sc Set sc = p.%Save()',
        'If sc Set sc = ##class(Ens.Director).UpdateProduction(60)',
        'Write !,"RESULT: ",$SELECT($SYSTEM.Status.IsOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc)),!',
    ])
    out = storm.iris_session(ctr, "SHUTTER", code)
    if "RESULT: ok" not in out:
        raise SystemExit("the production's update failed: " + out[-400:])


def open_task_message(ctr, incident_id):
    """The open task's message, read where the inbox reads it, between markers."""
    code = f'Set t = ##class(Shutter.Util.Workflow).OpenTaskFor("{incident_id}") If $ISOBJECT(t) {{ Write !,"<<<",t.%Message,">>>",! }} Else {{ Write !,"<<<>>>",! }}'
    out = storm.iris_session(ctr, "SHUTTER", code)
    m = re.search(r"<<<(.*?)>>>", out, re.DOTALL)
    return m.group(1) if m else ""




def complete_in_inbox(ctr, incident_id, digest):
    """As the inbox's Approve does, the digest typed into the form (tests/e2e/inbox_check.py)."""
    code = "\n".join([
        f'Set t = ##class(Shutter.Util.Workflow).OpenTaskFor("{incident_id}")',
        'Set sc = ##class(Shutter.Util.Workflow).Assign(t, "approver")',
        f'Do t.%FormValues.SetAt("{digest}", "PlanDigest")',
        'If $SYSTEM.Status.IsOK(sc) { Set sc = t.%Save() }',
        'If $SYSTEM.Status.IsOK(sc) { Set sc = ##class(EnsLib.Workflow.Engine).CompleteTask(t, "Approve") }',
        'Write !,"RESULT: ",$SELECT($SYSTEM.Status.IsOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc)),!',
    ])
    return "RESULT: ok" in storm.iris_session(ctr, "SHUTTER", code)


def post(args, plan, log):
    forwarder = storm.Role(args.url, "forwarder", log)
    result = types.SimpleNamespace(rule=lambda *a, **k: None, invalid=lambda r: print("INVALID", r), report=lambda *a: None)
    ids, *_ = storm.generate(types.SimpleNamespace(board=False), plan, forwarder, result, log)
    forwarder.sign_out()
    return ids


def newest_incident(operator, before):
    _, listing, _, _ = operator.call("GET", "/incidents?limit=50")
    items = [i for i in (listing or {}).get("items", []) if i["incidentId"] not in before]
    return items[0] if items else None


def wait_state(operator, before, wanted, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        found = newest_incident(operator, before)
        if found and found.get("state") in wanted:
            return found
        time.sleep(3)
    return newest_incident(operator, before)


def case_states(operator, incident_id):
    _, detail, _, _ = operator.call("GET", "/incidents/" + urllib.parse.quote(incident_id))
    states = {}
    for chain in (detail or {}).get("chains", []):
        for item in chain.get("items", []):
            states[item.get("caseState") or item.get("state")] = states.get(item.get("caseState") or item.get("state"), 0) + 1
    return states, detail or {}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--url", required=True)
    parser.add_argument("--ctr", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    args.url = args.url.rstrip("/")
    log = storm.Log(args.out)
    lines = []

    def line(name, ok, detail=""):
        lines.append({"name": name, "ok": bool(ok), "detail": str(detail)[:600]})
        print(f"{'ok  ' if ok else 'FAIL'} {name}: {str(detail)[:300]}", flush=True)
        with open(os.path.join(args.out, "result.json"), "w") as f:
            json.dump(lines, f, indent=1)

    operator = storm.Role(args.url, "operator", log)

    def known():
        _, listing, _, _ = operator.call("GET", "/incidents?limit=500")
        return {i["incidentId"] for i in (listing or {}).get("items", [])}

    base = storm.utc_now() - dt.timedelta(seconds=400)

    # A long list, approved from the inbox.
    before = known()
    post(args, own_patients(storm.storm_plan(24, base), 6), log)
    incident = wait_state(operator, before, ("awaiting_approval", "closed"), 200)
    iid = (incident or {}).get("incidentId", "")
    line("24 failures raise a task", incident and incident["state"] == "awaiting_approval", incident and incident["state"])
    message = open_task_message(args.ctr, iid)
    with open(os.path.join(args.out, "task-message.txt"), "w") as f:
        f.write(message)
    line("its message fits", 0 < len(message) <= 2000, f"{len(message)} characters")
    line("it points to the incident page", "/shutter/incidents/" + iid in message)
    line("it says how many more", re.search(r"\d+ more chains", message), re.findall(r"Listed here:.*", message))
    typed = re.search(r"Plan digest: (\S+)", message)
    _, detail = case_states(operator, iid)
    line("the digest in the message is the plan's", typed and typed.group(1) == detail.get("planDigest"), typed and typed.group(1))
    line("completed through the engine with that digest", typed and complete_in_inbox(args.ctr, iid, typed.group(1)))
    incident = wait_state(operator, before, ("closed",), 300)
    states, detail = case_states(operator, iid)
    line("every chain resolved", {c.get("state") for c in detail.get("chains", [])} == {"resolved"} and len(detail.get("chains", [])) == 12, detail.get("summary"))

    # No task can be raised.
    set_target(args.ctr, MISSING_TARGET)
    before = known()
    post(args, own_patients(storm.storm_plan(8, base + dt.timedelta(seconds=100)), 5), log)
    incident = wait_state(operator, before, ("awaiting_approval", "closed"), 200)
    iid = (incident or {}).get("incidentId", "")
    line("with the target missing the incident is not closed", incident and incident["state"] == "awaiting_approval", incident and incident["state"])
    states, detail = case_states(operator, iid)
    line("no task is open", detail.get("tasks") == [], detail.get("tasks"))
    line("the chains wait", {c.get("state") for c in detail.get("chains", [])} == {"awaiting_approval"})
    _, cases, _, _ = operator.call("GET", "/cases?limit=500")
    held = [c for c in (cases or {}).get("items", []) if c.get("incidentId") == iid]
    line("no case failed", held and not [c for c in held if c.get("state") == "failed"], {c.get("state") for c in held})
    _, events, _, _ = operator.call("GET", "/incidents/" + urllib.parse.quote(iid) + "/events")
    errors = [e for e in (events or []) if e.get("kind") == "error"]
    with open(os.path.join(args.out, "no-task-events.json"), "w") as f:
        json.dump(events, f, indent=1)
    line("one error on the timeline names the incident", len(errors) == 1 and iid in errors[0]["text"], errors and errors[0]["text"])
    sql = storm.Sql(args.url, log)
    alert = sql.one("SHUTTER", "SELECT COUNT(*) AS N FROM Ens_Util.Log WHERE Text LIKE ?", ("No approval task could be raised for incident " + iid + "%",))
    line("an alert names the incident in the Event Log", int(alert.get("N") or 0) >= 1, alert)
    approver = storm.Role(args.url, "approver", log)
    status, reply, _, _ = approver.call("POST", "/incidents/" + urllib.parse.quote(iid) + "/approvals",
                                        {"planDigest": detail.get("planDigest"), "decision": "approve"}, idempotent=True)
    line("an approval with no task is refused and releases nothing", status == 409, f"HTTP {status} {reply}")

    set_target(args.ctr, "")
    deadline = time.monotonic() + RETRY_SECONDS + 120
    tasks = []
    while time.monotonic() < deadline and not tasks:
        time.sleep(10)
        _, detail = case_states(operator, iid)
        tasks = detail.get("tasks") or []
    line("the target back, the next try raises the task", len(tasks) == 1, [t.get("subject") for t in tasks])
    status, reply, _, _ = approver.call("POST", "/incidents/" + urllib.parse.quote(iid) + "/approvals",
                                        {"planDigest": detail.get("planDigest"), "decision": "approve"}, idempotent=True)
    line("the approval is taken", status == 202, f"HTTP {status} {reply}")
    approver.sign_out()
    incident = wait_state(operator, before, ("closed",), 200)
    _, detail = case_states(operator, iid)
    line("every chain resolved", {c.get("state") for c in detail.get("chains", [])} == {"resolved"}, detail.get("summary"))
    operator.sign_out()
    failed = [x["name"] for x in lines if not x["ok"]]
    print("FAILED: " + "; ".join(failed) if failed else "All held")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
