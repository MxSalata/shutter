#!/usr/bin/env python3
"""Plays the held-out cases through Shutter's REST API, once per case, mode and repetition, and keeps everything each
run left: the case, the plan and the gate's decisions, the attempts, the events, the snapshot, the receiver's final read.

    python3 tests/fair_test/play.py --url URL --play-root PATH --container-root PATH --out DIR --set-fixtures CMD
        [--modes rules,policy] [--repeat 1] [--day 2026-11-05] [--seed N] [--timeout 300] [F01 F02 ...]

Nothing is proposed or decided here, and no model is called by this script. Whether agents can run is the instance's
own setting (no key: replay), and the run ends by reading GET /costs into its record. For each run:

- The fixtures are copied into a play folder with every date shifted by one fixed number of days (--day is where 18
  November lands), because the product treats an event time in the future as implausible and blocks every write, and
  under an opaque scenario id, because the scenario id is part of what a model is shown (README.md).
- --set-fixtures is a command run with the folder's path inside the container as its one argument: it points
  ^Shutter.Config("fixtures") at it. No product code knows about these cases.
- The site profile's fields a case sets go in with PUT /site-profile before the run, and the shipped profile goes back
  after it; each run records the profile version it saw.
- A plan that waits for approval is approved as the approver once the steps are done, as scenario_check.py --approve
  does, and the run's record says so.
- Reading the first investigation after the steps: the shipped Case Workflow waits SettleSeconds (15) before collecting
  evidence. A case whose decisive message arrives after the failure (F09) records whether that message was indexed when
  the snapshot was taken, so a run that read too early is declared rather than scored.

Signs in as the demo users `operator` and `approver` (password from SHUTTER_PASSWORD, default "shutter"). Each run
resets the receiver: don't use an instance someone else is using. Standard library only.
"""
import argparse
import datetime
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "e2e"))
from scenario_check import Session, downstream_encounter, wait, wait_until_idle  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SEALED_DAY = datetime.date(2026, 11, 18)
RECEIVER = "Downstream Out"
CLOSED = {"resolved", "blocked", "escalated", "failed"}
HOLDS = {"WAITING_FOR_OCCUPANT_CASE", "NEWER_MESSAGE_PENDING"}
OPAQUE = re.compile(r"X[0-9A-F]{7}")


def shifter(day):
    """A function that moves every date in a text by the fixed distance from the sealed day to day."""
    delta = day - SEALED_DAY

    def compact(match):
        d = datetime.date(int(match[1]), int(match[2]), int(match[3])) + delta
        return d.strftime("%Y%m%d")

    def dashed(match):
        d = datetime.date(int(match[1]), int(match[2]), int(match[3])) + delta
        return d.isoformat()

    def shift(text):
        text = re.sub(r"\b(2026)(11)(\d\d)(?=\d{6}|\|)", compact, text)
        return re.sub(r"\b(2026)-(11)-(\d\d)", dashed, text)

    return shift


def opaque_id(case, secret):
    """A scenario id that says nothing about the case. Stable within one --seed."""
    return "X" + hashlib.sha256(f"{secret}:{case}".encode()).hexdigest()[:7].upper()


def check_day(day, today):
    """The sealed day's latest event is in the afternoon, and the grader tells a fixture's date from the run's clock by
    this: the day must be over, or an event can be future and a stamp can pass for a fixture's."""
    if day >= today:
        raise SystemExit(f"--day must be before today ({today}): an event still to come would be blocked as implausible")


def check_play_root(root):
    """Replacing the play folder deletes it, so it must be new, empty, or hold exactly what this script writes there."""
    if not os.path.lexists(root):
        return
    if not os.path.isdir(root) or os.path.islink(root):
        raise SystemExit(f"--play-root is not a plain folder, so it is left alone: {root}")
    names = set(os.listdir(root))
    strays = {n for n in names - {"scenarios.json"}
              if not (OPAQUE.fullmatch(n) and os.path.isdir(os.path.join(root, n)))}
    if strays or (names and "scenarios.json" not in names):
        raise SystemExit(f"--play-root holds files this script did not write, so it is left alone: {root}")


def prepare(scenarios, root, day, secret):
    """Writes the play folder under root: scenarios.json and one folder per opaque id. Returns {case: play scenario}."""
    check_play_root(root)
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(root)
    shift = shifter(day)
    out, played = [], {}
    for s in scenarios:
        pid = opaque_id(s["id"], secret)
        os.makedirs(os.path.join(root, pid))
        steps = []
        for step in s["steps"]:
            step = json.loads(shift(json.dumps(step)))
            if "file" in step:
                name = step["file"].replace(s["id"], pid, 1)
                with open(os.path.join(HERE, "fixtures", s["id"], step["file"]), encoding="ascii", newline="") as f:
                    text = shift(f.read())
                with open(os.path.join(root, pid, name), "w", encoding="ascii", newline="") as f:
                    f.write(text)
                os.chmod(os.path.join(root, pid, name), 0o644)
                step["file"] = name
            steps.append(step)
        record = {"id": pid, "title": "Held-out case", "summary": "", "steps": steps, "expected": {}}
        out.append(record)
        played[s["id"]] = {**record, "rig": json.loads(shift(json.dumps(s["rig"])))}
    with open(os.path.join(root, "scenarios.json"), "w", encoding="ascii") as f:
        json.dump(out, f, indent=1)
    os.chmod(root, 0o755)
    for pid in os.listdir(root):
        if os.path.isdir(os.path.join(root, pid)):
            os.chmod(os.path.join(root, pid), 0o755)
    return played


def merged(profile, change):
    out = json.loads(json.dumps(profile))
    for key, value in change.items():
        if isinstance(value, dict):
            out[key] = {**(out.get(key) or {}), **value}
        else:
            out[key] = value
    return out


def put_profile(approver, profile):
    status, body = approver.call("PUT", "/site-profile", profile, idempotent=True)
    if status not in (200, 201):
        raise RuntimeError(f"the site profile was refused: HTTP {status} {body}")


def case_get(session, case_id, part=""):
    status, body = session.call("GET", f"/cases/{urllib.parse.quote(case_id)}{part}")
    return body if status == 200 else {"http_status": status, "body": body}


def play_one(args, operator, approver, shipped, case, played, mode):
    """One run. Returns its raw record; nothing in it is interpreted."""
    rig = played["rig"]
    change = rig.get("profile")
    if change:
        put_profile(approver, merged(shipped, change))
    try:
        _, view = operator.call("GET", "/site-profile")
        wait_until_idle(operator, args.timeout)
        floor = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        status, started = operator.call("POST", f"/scenarios/{played['id']}/run", {"mode": mode}, idempotent=True)
        if status not in (200, 202):
            return {"error": f"the run was refused: HTTP {status} {started}"}
        since = max(started.get("startedAt") or "", started.get("queuedAt") or "", floor)

        def theirs():
            _, body = operator.call("GET", f"/cases?scenario={played['id']}&limit=20")
            return [c for c in (body or {}).get("items", []) if (c.get("openedAt") or "") >= since]

        def own_case():
            for c in theirs():
                if c.get("operationKey") == rig["failed"] and c.get("receiver") == RECEIVER:
                    return c
            return None

        def steps_finished():
            _, body = operator.call("GET", "/scenarios")
            run = (body or {}).get("run") or {}
            return run if run.get("scenario") == played["id"] and run.get("state") not in ("queued", "running") else None

        outcome = {"error": None}
        try:
            opened = wait(f"{case}: its case", own_case, args.timeout)
        except TimeoutError as error:
            return {"error": str(error), "cases": theirs(), "profile_version": (view or {}).get("version")}

        approved = []

        def settled():
            c = case_get(operator, opened["caseId"])
            if c.get("state") == "blocked":
                reason = case_get(operator, opened["caseId"], "/blocked-reason")
                if reason.get("code") in HOLDS:
                    return None
            if c.get("state") in CLOSED:
                return c
            if c.get("state") == "awaiting_approval" and not approved and steps_finished():
                # As scenario_check.py --approve does: a plan the gate passed is approved, so that what it would do at
                # the receiver is measured and not always stopped at the approval task
                view = case_get(operator, opened["caseId"], "/plan")
                decision = {"decision": "approve", "planDigest": view["plan"]["digest"],
                            "expectedVersion": c["version"], "comment": "held-out run"}
                status, body = approver.call("POST", f"/cases/{urllib.parse.quote(opened['caseId'])}/approvals", decision,
                                             idempotent=True)
                if status != 202:
                    raise RuntimeError(f"the approval was refused: HTTP {status} {body}")
                approved.append(True)
            return None

        try:
            final = wait(f"{case} {opened['caseId']}: its outcome", settled, args.timeout)
        except TimeoutError as error:
            outcome["error"] = str(error)
            final = case_get(operator, opened["caseId"])
        run = wait(f"{case}: the steps", steps_finished, args.timeout)
        cid = opened["caseId"]
        # A write that was still settling when the case closed, and the delayed commit of a slow receiver, both show here
        time.sleep(2)
        final = case_get(operator, cid)
        encounter = final.get("encounterId") or opened.get("encounterId")
        record = {
            "error": outcome["error"], "run": run, "since": since, "profile_version": (view or {}).get("version"),
            "approved_by_rig": bool(approved),
            "case": final, "plan": case_get(operator, cid, "/plan"), "attempts": case_get(operator, cid, "/attempts"),
            "events": case_get(operator, cid, "/events"), "snapshot": case_get(operator, cid, "/snapshot"),
            "agent_runs": case_get(operator, cid, "/runs"), "blocked_reason": case_get(operator, cid, "/blocked-reason"),
            "closure": case_get(operator, cid, "/closure"), "escalations": case_get(operator, cid, "/escalations"),
            "receiver_final": downstream_encounter(args.url, args.downstream_user, args.downstream_password, encounter),
        }
        if rig.get("other_encounter"):
            record["receiver_other"] = downstream_encounter(args.url, args.downstream_user, args.downstream_password,
                                                            rig["other_encounter"])
        # The rest of the run's cases: the second demo receiver's, and a withheld message's own. Not judged, but a case
        # left open would swallow the next repetition's failure of the same key.
        record["other_cases"] = []
        for other in theirs():
            if other["caseId"] == cid:
                continue
            record["other_cases"].append({k: other.get(k) for k in
                                          ("caseId", "receiver", "operationKey", "state", "disposition", "failureKind")})
            if other.get("state") not in CLOSED:
                operator.call("POST", f"/cases/{urllib.parse.quote(other['caseId'])}/abandon",
                              {"reason": "held-out run finished"}, idempotent=True)
        if final.get("state") not in CLOSED:
            operator.call("POST", f"/cases/{urllib.parse.quote(cid)}/abandon", {"reason": "held-out run finished"},
                          idempotent=True)
        return record
    finally:
        if change:
            put_profile(approver, shipped)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("cases", nargs="*")
    p.add_argument("--url", default="http://localhost:52773")
    p.add_argument("--modes", default="rules,policy")
    p.add_argument("--repeat", type=int, default=1)
    p.add_argument("--day", default="2026-11-05", help="where the sealed 18 November lands; a day that is over")
    p.add_argument("--seed", type=int, default=20261106)
    p.add_argument("--timeout", type=int, default=300)
    p.add_argument("--play-root", required=True, help="the play folder, as this script sees it")
    p.add_argument("--container-root", required=True, help="the same folder, as IRIS sees it")
    p.add_argument("--set-fixtures", required=True, help="a command that points the instance at a fixtures folder")
    p.add_argument("--out", required=True)
    p.add_argument("--downstream-user", default="_SYSTEM")
    p.add_argument("--downstream-password", default="SYS")
    args = p.parse_args()

    with open(os.path.join(HERE, "fixtures", "scenarios.json"), encoding="ascii") as f:
        scenarios = json.load(f)
    day = datetime.date.fromisoformat(args.day)
    check_day(day, datetime.datetime.now(datetime.timezone.utc).date())
    played = prepare(scenarios, args.play_root, day, args.seed)
    subprocess.run([args.set_fixtures, args.container_root], check=True)

    password = os.environ.get("SHUTTER_PASSWORD", "shutter")
    operator = Session(args.url).sign_in("operator", password)
    approver = Session(args.url).sign_in("approver", password)
    _, seen = operator.call("GET", "/site-profile")
    shipped = seen["profile"]
    os.makedirs(args.out, exist_ok=True)
    plan = [(c, m, r) for c in (args.cases or list(played)) for m in args.modes.split(",") for r in range(args.repeat)]
    random.Random(args.seed).shuffle(plan)
    for case, mode, rep in plan:
        name = f"{case}-{mode}-{rep + 1}"
        target = os.path.join(args.out, name + ".json")
        if os.path.exists(target):
            continue
        began = time.time()
        try:
            record = play_one(args, operator, approver, shipped, case, played[case], mode)
        except Exception as error:  # kept per run: a broken run is a result ("none"), and the next must still play
            record = {"error": f"{type(error).__name__}: {error}"}
        record.update({"fair_case": case, "mode": mode, "repetition": rep + 1, "play_id": played[case]["id"],
                       "seconds": round(time.time() - began, 1), "shift_to_day": args.day,
                       "failed_key_played": played[case]["rig"]["failed"]})
        with open(target, "w", encoding="utf-8") as f:
            json.dump(record, f, indent=1)
        print(name, (record.get("case") or {}).get("state"), (record.get("case") or {}).get("disposition"),
              record.get("error") or "", flush=True)
    _, costs = operator.call("GET", "/costs")
    _, settings = operator.call("GET", "/settings")
    with open(os.path.join(args.out, "instance.json"), "w", encoding="utf-8") as f:
        json.dump({"costs": costs, "settings": settings, "seed": args.seed, "plan": plan}, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
