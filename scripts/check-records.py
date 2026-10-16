#!/usr/bin/env python3
"""Check recording files (fixtures/records/*.json) offline: the key, the member, the agent class, and the
result's shape as the core stores it (Interlock.Schema.Findings for specialists, Interlock.Schema.Plan for the
coordinator and the generalist). Mirrors the schema classes' Check methods.

    python3 scripts/check-records.py [fixtures/records] [--scenarios fixtures/scenarios.json]

Exit code 1 when any file has a problem. With --scenarios it also lists, per scenario in that file, the
members whose round-1 recording is missing.
"""
import argparse
import glob
import json
import os
import re
import sys

DISPOSITIONS = {"resend", "reconcile", "superseded", "more_evidence", "escalate"}
MEMBERS = {
    "conformance": ("Interlock.Agent.Conformance", "findings"),
    "encounter": ("Interlock.Agent.Encounter", "findings"),
    "impact": ("Interlock.Agent.Impact", "findings"),
    "coordinator": ("Interlock.Agent.Coordinator", "plan"),
    "generalist": ("Interlock.Agent.Generalist", "plan"),
}
KEY_RE = re.compile(r"^scenario:(S\d+)\|([a-z]+)\|(\d+)(\|round(\d+))?$")


FINDINGS_FIELDS = {"disposition", "confidence", "summary", "violations", "unknowns", "evidence_refs"}
PLAN_FIELDS = {"disposition", "summary", "action", "preconditions", "evidence_refs", "disagreements"}


def unknown_fields(r, allowed):
    extra = sorted(set(r) - allowed)
    return [f"fields the live agents cannot submit: {', '.join(extra)} (the schema has {', '.join(sorted(allowed))})"] if extra else []


def check_findings(r):
    p = []
    if not isinstance(r, dict):
        return ["result must be an object"]
    p += unknown_fields(r, FINDINGS_FIELDS)
    if r.get("disposition") not in DISPOSITIONS:
        p.append("disposition must be one of " + ", ".join(sorted(DISPOSITIONS)))
    c = r.get("confidence")
    if not isinstance(c, (int, float)) or isinstance(c, bool) or not 0 <= c <= 1:
        p.append("confidence must be a number from 0 to 1")
    if not r.get("summary"):
        p.append("summary is required")
    for f in ("violations", "unknowns", "evidence_refs"):
        if f in r and not (isinstance(r[f], list) and all(isinstance(x, str) for x in r[f])):
            p.append(f"{f} must be an array of strings")
    if not isinstance(r.get("evidence_refs"), list):
        p.append("evidence_refs must list the evidence used")
    return p


def check_plan(r):
    p = []
    if not isinstance(r, dict):
        return ["result must be an object"]
    p += unknown_fields(r, PLAN_FIELDS)
    d = r.get("disposition")
    if d not in DISPOSITIONS:
        p.append("disposition must be one of " + ", ".join(sorted(DISPOSITIONS)))
    if not r.get("summary"):
        p.append("summary is required")
    a = r.get("action")
    if not isinstance(a, dict):
        p.append("action is required: {type: resend | reconcile | none, operation_key, expected_version}")
    else:
        t = a.get("type")
        if t not in ("resend", "reconcile", "none"):
            p.append("action.type must be resend, reconcile or none")
        if t == "resend":
            if not a.get("operation_key"):
                p.append("a resend names the case's operation_key")
            if not isinstance(a.get("expected_version"), int) or isinstance(a.get("expected_version"), bool):
                p.append("a resend carries expected_version, an integer")
            if d != "resend":
                p.append("action.type resend needs disposition resend")
        if t == "none" and d == "resend":
            p.append("disposition resend needs action.type resend")
        if t == "reconcile" and d != "reconcile":
            p.append("action.type reconcile needs disposition reconcile")
    if not isinstance(r.get("evidence_refs"), list):
        p.append("evidence_refs must list the evidence used")
    dis = r.get("disagreements")
    if dis is not None:
        if not isinstance(dis, list):
            p.append("disagreements must be an array")
        else:
            for i, x in enumerate(dis):
                if not isinstance(x, dict) or not all(x.get(k) for k in ("member", "said", "why_kept")):
                    p.append(f"disagreements[{i}] needs member, said and why_kept")
    return p


def check_file(path):
    problems = []
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError) as e:
        return [f"not readable as JSON: {e}"], None
    key = d.get("key", "")
    m = KEY_RE.match(key)
    if not m:
        problems.append(f"key {key!r} is not scenario:S<n>|<member>|<configVersion>[|round<n>]")
        member = d.get("memberCode")
    else:
        scenario, member, cfg = m.group(1), m.group(2), m.group(3)
        if d.get("memberCode") != member:
            problems.append(f"memberCode {d.get('memberCode')!r} differs from the key's member {member!r}")
        if str(d.get("configVersion")) != cfg:
            problems.append(f"configVersion {d.get('configVersion')!r} differs from the key's {cfg!r}")
        expected_name = f"scenario-{scenario}-{member}-{cfg}" + (f"-round{m.group(5)}" if m.group(5) else "") + ".json"
        if os.path.basename(path) != expected_name:
            problems.append(f"file name should be {expected_name}")
    if member not in MEMBERS:
        problems.append(f"unknown member {member!r}")
        return problems, m
    agent_class, kind = MEMBERS[member]
    if d.get("agentClass") != agent_class:
        problems.append(f"agentClass should be {agent_class}")
    resp = d.get("response")
    if not isinstance(resp, dict):
        problems.append("response must be an object")
        return problems, m
    if resp.get("status") != "ok":
        problems.append("response.status should be ok for a usable recording")
    result = resp.get("result")
    if isinstance(result, str):
        try:
            result = json.loads(result)
        except ValueError:
            problems.append("response.result is not JSON")
            return problems, m
    problems += (check_findings(result) if kind == "findings" else check_plan(result))
    for f in ("transcript", "toolCalls"):
        v = d.get(f)
        if isinstance(v, str) and v.strip() and not v.strip().startswith(("[", "{")):
            problems.append(f"{f} should be JSON text or empty")
    return problems, m


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("directory", nargs="?", default="fixtures/records")
    ap.add_argument("--scenarios", help="fixtures/scenarios.json, to list the scenarios without a full round-1 set")
    args = ap.parse_args()
    files = sorted(glob.glob(os.path.join(args.directory, "*.json")))
    if not files:
        print(f"no recordings in {args.directory}", file=sys.stderr)
        return 1
    bad = 0
    present = {}
    for path in files:
        problems, m = check_file(path)
        if m:
            present.setdefault(m.group(1), set()).add(m.group(2) + (f"|round{m.group(5)}" if m.group(5) else ""))
        if problems:
            bad += 1
            print(f"{path}:")
            for p in problems:
                print(f"  - {p}")
    print(f"{len(files)} files, {len(files) - bad} fine, {bad} with problems")
    if args.scenarios:
        with open(args.scenarios, encoding="utf-8") as f:
            scenarios = json.load(f)
        board = {"conformance", "encounter", "impact", "coordinator"}
        for s in scenarios:
            have = present.get(s["id"], set())
            missing = sorted(board - have)
            print(f"{s['id']}: " + ("board round 1 complete" if not missing else "missing " + ", ".join(missing)) + (" (+ " + ", ".join(sorted(x for x in have if "round" in x)) + ")" if any("round" in x for x in have) else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
