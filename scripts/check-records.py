#!/usr/bin/env python3
"""Check recording files (fixtures/records/*.json) offline: the key, the member, the agent class, and the
result's shape as the core stores it (Interlock.Schema.Findings for specialists, Interlock.Schema.Plan for the
coordinator and the generalist). Mirrors the schema classes' Check methods.

    python3 scripts/check-records.py [fixtures/records] [--scenarios fixtures/scenarios.json]

Exit code 1 when any file has a problem. With --scenarios it also lists, per scenario in that file, the
members whose round-1 recording is missing: per case when the keys name the encounter and event
(scenario:S11:ENC-1101:transfer|member|cfg), per scenario for the older keys without them (scenario:S2|member|cfg). A
scenario that opens an incident needs recordings only for the encounters whose chain the board decides.
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
# scenario:<S>[:<encounter>:<event>]|<member>|<configVersion>[|round<n>]: the core writes the long form since the
# incident work (CaseWorkflow), and Interlock.Bridge.Record falls back to the short one the first recordings use.
KEY_RE = re.compile(r"^scenario:(?P<scenario>S\d+)(?::(?P<encounter>[^:|]+):(?P<event>[^:|]+))?"
                    r"\|(?P<member>[a-z]+)\|(?P<cfg>\d+)(?:\|round(?P<round>\d+))?$")


def file_name(m):
    """The fixture file for a key: scenario-S2-coordinator-1.json, scenario-S11-ENC-1101-transfer-coordinator-1.json."""
    case = [m["encounter"], m["event"]] if m["encounter"] else []
    parts = [re.sub(r"[^A-Za-z0-9._-]", "_", x) for x in ["scenario", m["scenario"], *case, m["member"], m["cfg"]]]
    return "-".join(parts) + (f"-round{m['round']}" if m["round"] else "") + ".json"


def case_of(m):
    """What a full board set is counted over: the case (scenario, encounter, event), or the scenario alone."""
    return (m["scenario"], m["encounter"], m["event"])


FINDINGS_FIELDS = {"disposition", "confidence", "summary", "violations", "unknowns", "evidence_refs"}
PLAN_FIELDS = {"disposition", "summary", "action", "preconditions", "evidence_refs", "disagreements",
               "catalogue_entry", "outcome", "why"}


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
    entry, outcome = r.get("catalogue_entry") or "", r.get("outcome") or ""
    if entry and outcome != "preferred" and not str(outcome).startswith("alternative:"):
        p.append("outcome must be preferred or alternative:<n> when a catalogue_entry is named")
    if not entry and outcome:
        p.append("outcome needs a catalogue_entry")
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
        problems.append(f"key {key!r} is not scenario:S<n>[:<encounter>:<event>]|<member>|<configVersion>[|round<n>]")
        member = d.get("memberCode")
    else:
        member, cfg = m["member"], m["cfg"]
        if d.get("memberCode") != member:
            problems.append(f"memberCode {d.get('memberCode')!r} differs from the key's member {member!r}")
        if str(d.get("configVersion")) != cfg:
            problems.append(f"configVersion {d.get('configVersion')!r} differs from the key's {cfg!r}")
        expected_name = file_name(m)
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
            present.setdefault(case_of(m), set()).add(m["member"] + (f"|round{m['round']}" if m["round"] else ""))
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
            expected = s.get("expected") or {}
            if expected.get("incident"):
                # an incident's cases need recordings only where the board decides their chain (expected path "board")
                encounters = [e["encounter"] for e in expected.get("encounters", []) if e.get("path") == "board"]
                if not encounters:
                    print(f"{s['id']}: the board decides none of its cases")
                    continue
                cases = sorted((c for c in present if c[0] == s["id"] and c[1] in encounters),
                               key=lambda c: (c[1] or "", c[2] or ""))
                cases += [(s["id"], e, None) for e in encounters if not any(c[1] == e for c in cases)]
            else:
                # every case that has recordings needs a full set; a scenario with none at all is missing the whole board
                cases = sorted((c for c in present if c[0] == s["id"]), key=lambda c: (c[1] or "", c[2] or "")) or [(s["id"], None, None)]
            for case in cases:
                have = present.get(case, set())
                missing = sorted(board - have)
                label = " ".join(x for x in case if x)
                rounds = sorted(x for x in have if "round" in x)
                print(f"{label}: " + ("board round 1 complete" if not missing else "missing " + ", ".join(missing))
                      + (" (+ " + ", ".join(rounds) + ")" if rounds else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
