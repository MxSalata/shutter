#!/usr/bin/env python3
"""Check recording files (fixtures/records/*.json) offline: the key, the member, the agent class, and the
result's shape as the core stores it (Shutter.Schema.Findings for specialists, Shutter.Schema.Plan for the
coordinator and the generalist, Shutter.Schema.Review for the production review's agent). Mirrors the schema
classes' Check methods. A run the API mimic answered (model mock, tests/mock) is a problem: no model made it.

    python3 scripts/check-records.py [fixtures/records] [--scenarios fixtures/scenarios.json]
    python3 scripts/check-records.py --self-test

Exit code 1 when any file has a problem. With --scenarios it also lists, per scenario in that file, the
members whose round-1 recording is missing, per case (scenario:S11:ENC-1101:transfer|member|cfg). A key in the older
form without the encounter and event (scenario:S2|member|cfg) is a problem: Shutter.Bridge.Record looks up the long key
only, so such a recording never replays. A scenario that opens an incident needs recordings only for the encounters
whose chain the board decides; a withheld merge or cancel, and a scenario played only in site-policy mode, need none.
A suggested question's recording (question:<S>:<encounter>:<event>[:<receiver>]|<tier>|<member>|<conversation>.<turn>|<cfg>)
is checked for its member, agent class, file name and answer shape (Shutter.Schema.Answer or BoardAnswer).
A production review's recording (review:SHUTTER:Shutter.Production|review|1|<fingerprint>) is checked the same way, is
named as Shutter.Bridge.Record.ExportDir names it, and is not counted towards any scenario's board set.
"""
import argparse
import decimal
import glob
import json
import os
import re
import sys

DISPOSITIONS = {"resend", "reconcile", "superseded", "more_evidence", "escalate"}
MEMBERS = {
    "conformance": ("Shutter.Agent.Conformance", "findings"),
    "encounter": ("Shutter.Agent.Encounter", "findings"),
    "impact": ("Shutter.Agent.Impact", "findings"),
    "coordinator": ("Shutter.Agent.Coordinator", "plan"),
    "generalist": ("Shutter.Agent.Generalist", "plan"),
    "review": ("Shutter.Agent.Review", "review"),
}
# scenario:<S>:<encounter>:<event>|<member>|<configVersion>[|round<n>], as CaseWorkflow writes it. The pattern still parses
# the older form without the encounter and event, so that check_file can say why such a recording is refused.
KEY_RE = re.compile(r"^scenario:(?P<scenario>S\d+)(?::(?P<encounter>[^:|]+):(?P<event>[^:|]+))?"
                    r"\|(?P<member>[a-z]+)\|(?P<cfg>\d+)(?:\|round(?P<round>\d+))?$")
# review:<namespace>:<production>|review|1|<fingerprint>, as Shutter.Process.Review.RecordKeyFor writes it: the
# fingerprint is the configuration findings' SHA-256 in lower-case hex, empty when the production has none
REVIEW_KEY_RE = re.compile(r"^review:(?P<namespace>[A-Za-z0-9_%]+):(?P<production>[A-Za-z0-9_.]+)"
                           r"\|(?P<member>review)\|(?P<cfg>1)\|(?P<fingerprint>[0-9a-f]{64}|)$")
# The review's agent has no evidence tools: its knowledge search and its terminal are all it can call
REVIEW_TOOLS = {"search_review", "SubmitReview"}
# question:<S>:<encounter>:<event>[:<receiver>]|<tier>|<member>|<conversation>.<turn>|<cfg>, as Shutter.Process.Question
# writes it for a suggested turn (CONTRACTS 14.2); its file is named as a review's: each of ":|/\\ " becomes "-"
QUESTION_KEY_RE = re.compile(r"^question:(?P<scenario>S\d+[a-z]?):(?P<encounter>[^:|]+):(?P<event>[^:|]+)(?::(?P<receiver>[^|]+))?"
                             r"\|(?P<tier>explain|board)\|(?P<member>[a-z]+)\|(?P<conversation>[A-Za-z0-9_-]+)\.(?P<turn>\d+)\|(?P<cfg>\d+)$")
# A question's answering agents: the Explain agent, or a board member answering from its perspective, or the coordinator
QUESTION_MEMBERS = {
    "explain": "Shutter.Agent.Explain",
    "conformance": "Shutter.Agent.Conformance",
    "encounter": "Shutter.Agent.Encounter",
    "impact": "Shutter.Agent.Impact",
    "coordinator": "Shutter.Agent.Coordinator",
}


def check_answer(r, board):
    """A question's answer: Shutter.Schema.Answer, or Shutter.Schema.BoardAnswer for the coordinator (CONTRACTS 14.2, 14.4)."""
    if not isinstance(r, dict):
        return ["the answer must be a JSON object"]
    p = []
    a = r.get("answer")
    if not isinstance(a, str) or not a.strip():
        p.append("answer needs the answer in plain words")
    elif len(a) > 1200:
        p.append("answer is longer than 1200 characters")
    cites = r.get("cites")
    if cites is not None and (not isinstance(cites, list) or any(not isinstance(c, str) or not c for c in cites)):
        p.append("cites must be a list of evidence ids and fact ids")
    if r.get("confidence") not in (None, "", "high", "medium", "low"):
        p.append("confidence must be high, medium or low")
    if board:
        for f in ("setting", "under_alternative", "suggested_change"):
            v = r.get(f)
            if v is not None and not (isinstance(v, dict) and re.fullmatch(r"W\d+", str(v.get("fact") or ""))):
                p.append(f"{f} must name a fact id W<n>")
    return p


def file_name(m):
    """The fixture file for a key: scenario-S2-coordinator-1.json, scenario-S11-ENC-1101-transfer-coordinator-1.json."""
    case = [m["encounter"], m["event"]] if m["encounter"] else []
    parts = [re.sub(r"[^A-Za-z0-9._-]", "_", x) for x in ["scenario", m["scenario"], *case, m["member"], m["cfg"]]]
    return "-".join(parts) + (f"-round{m['round']}" if m["round"] else "") + ".json"


def review_file_name(key):
    """The fixture file for a review key, as Shutter.Bridge.Record.ExportDir names it: each of ":|/\\ " becomes "-"."""
    return key.translate(str.maketrans(":|/\\ ", "-----")) + ".json"


def case_of(m):
    """What a full board set is counted over: the case (scenario, encounter, event), or the scenario alone."""
    return (m["scenario"], m["encounter"], m["event"])


# The gate's codes for an operation Shutter never sends (CONTRACTS 2, v1.14)
WITHHELD = {"MERGE_WITHHELD", "CANCEL_UNSUPPORTED"}

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


def os_text(v):
    """A JSON value as Shutter.Util.Json.Str reads it: "" for null, 1 or 0 for a boolean, a number in its canonical
    form (2.0 is "2", 0.5 is ".5"), a string as it is; None for an object or an array."""
    if isinstance(v, (dict, list)):
        return None
    if v is None:
        return ""
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        t = format(decimal.Decimal(repr(v)), "f")
        if "." in t:
            t = t.rstrip("0").rstrip(".")
        t = t.replace("-0.", "-.") if t.startswith("-0.") else (t[1:] if t.startswith("0.") else t)
        return "0" if t in ("", "-0") else t
    return v


def os_len(s):
    """$LENGTH: characters outside the BMP count as two."""
    return len(s.encode("utf-16-le")) // 2


def check_review(r):
    """Shutter.Schema.Review.Check, message for message: every finding id once, ranks 1 to n with none twice, an
    explanation of at most 600 characters, a note of at most 300, a summary of at most 600 and unknowns an array."""
    if not isinstance(r, dict):
        return ["review must be a JSON object"]
    if not isinstance(r.get("ranking"), list):
        return ["ranking must be an array of {finding_id, rank, explanation, confidence_note}"]
    p = []
    ranking = r["ranking"]
    n = len(ranking)
    if n == 0:
        p.append("ranking must list every finding of the review")
    seen, taken = set(), set()
    for i, e in enumerate(ranking):
        if not isinstance(e, dict):
            p.append(f"ranking[{i}] must be an object")
            continue
        fid = os_text(e.get("finding_id"))
        # An object as the id is a distinct id each time, as an object reference is
        label = fid if fid is not None else f"<object {i}>"
        if label == "":
            p.append(f"ranking[{i}] needs a finding_id")
        elif label in seen:
            p.append(f"finding {label} is ranked more than once")
        else:
            seen.add(label)
        # rank must be the canonical form of an integer from 1 to n: "+rank" reads 2 from "2" but "02" is not 2
        rank = os_text(e.get("rank")) or ""
        if not re.fullmatch(r"[1-9]\d*", rank) or int(rank) > n:
            p.append(f"ranking[{i}] rank must be an integer from 1 to {n}, the number of findings ranked")
        elif int(rank) in taken:
            p.append(f"rank {int(rank)} is given twice: ranks run 1 to {n} without a gap")
        else:
            taken.add(int(rank))
        named = label if label != "" else f"ranking[{i}]"
        # The finding's code, item and setting (v1.22): the code a non-empty string, item and setting strings or absent
        if not isinstance(e.get("code"), str) or e.get("code") == "":
            p.append(f"ranking[{i}] needs the finding's code, copied from the finding")
        for field in ("item", "setting"):
            if field in e and e[field] is not None and not isinstance(e[field], str):
                p.append(f"ranking[{i}] {field} must be a string, the finding's own")
        explanation = os_text(e.get("explanation")) or ""
        # $ZSTRIP(x, "<>W"): tab, space and the no-break space
        if explanation.strip("\t \u00a0") == "":
            p.append(f"ranking[{i}] needs an explanation" + (f" for {label}" if label != "" else ""))
        elif os_len(explanation) > 600:
            p.append(f"the explanation of {named} is longer than 600 characters")
        note = os_text(e.get("confidence_note")) or ""
        if os_len(note) > 300:
            p.append(f"the confidence_note of {named} is longer than 300 characters")
    summary = os_text(r.get("summary"))
    if summary is None:
        p.append("summary must be text")
    elif os_len(summary) > 600:
        p.append("summary is longer than 600 characters")
    if "unknowns" in r and r["unknowns"] is not None and not isinstance(r["unknowns"], list):
        p.append("unknowns must be an array of strings")
    return p


def review_tool_problems(d):
    """The review's run calls its knowledge search and SubmitReview only, and calls SubmitReview. Tool calls that are
    empty, missing or not a list mean the run never reached SubmitReview either."""
    calls = d.get("toolCalls")
    if isinstance(calls, str):
        try:
            calls = json.loads(calls) if calls.strip() else []
        except ValueError:
            calls = None
    if not isinstance(calls, list):
        calls = []
    names = [c.get("name") for c in calls if isinstance(c, dict)]
    p = []
    other = sorted({str(x) for x in names} - REVIEW_TOOLS)
    if other:
        p.append(f"tool calls the review's agent does not have: {', '.join(other)} (it has {', '.join(sorted(REVIEW_TOOLS))})")
    if "SubmitReview" not in names:
        p.append("the run never called its terminal tool SubmitReview")
    return p


def mock_problems(d):
    """A run the API mimic answered (tests/mock): no model made it, so it is never a recording."""
    resp = d.get("response") if isinstance(d.get("response"), dict) else {}
    if "mock" in (d.get("model"), resp.get("model")) or "ShutterMock" in str(resp.get("provider_config") or ""):
        return ["made against the API mimic (model mock): no model answered it, so it is never a recording"]
    return []


def check_question(path, d, q, problems):
    """A suggested question's recording: the key's member and agent class, the configuration version, the file name, a
    usable response and an answer of the right shape."""
    member = q["member"]
    if member not in QUESTION_MEMBERS:
        return problems + [f"unknown member {member!r} for a question"]
    if q["tier"] == "explain" and member != "explain":
        problems.append("an explain question is answered by the explain agent only")
    if q["tier"] == "board" and member == "explain":
        problems.append("a board question is answered by the board's members and the coordinator")
    if d.get("memberCode") != member:
        problems.append(f"memberCode {d.get('memberCode')!r} differs from the key's member {member!r}")
    if d.get("agentClass") != QUESTION_MEMBERS[member]:
        problems.append(f"agentClass should be {QUESTION_MEMBERS[member]}")
    if str(d.get("configVersion")) != q["cfg"]:
        problems.append(f"configVersion {d.get('configVersion')!r} differs from the key's {q['cfg']!r}")
    expected_name = review_file_name(d.get("key", ""))
    if os.path.basename(path) != expected_name:
        problems.append(f"file name should be {expected_name}")
    resp = d.get("response")
    if not isinstance(resp, dict):
        return problems + ["response must be an object"]
    if resp.get("status") != "ok":
        problems.append("response.status should be ok for a usable recording")
    result = resp.get("result")
    if isinstance(result, str):
        try:
            result = json.loads(result)
        except ValueError:
            return problems + ["response.result is not JSON"]
    return problems + check_answer(result, member == "coordinator")


def check_file(path):
    problems = []
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError) as e:
        return [f"not readable as JSON: {e}"], None
    if not isinstance(d, dict):
        return ["a recording must be a JSON object"], None
    problems += mock_problems(d)
    key = d.get("key", "")
    q = QUESTION_KEY_RE.match(key)
    if q:
        return check_question(path, d, q, problems), q
    m = KEY_RE.match(key) or REVIEW_KEY_RE.match(key)
    if not m:
        problems.append(f"key {key!r} is not scenario:S<n>[:<encounter>:<event>]|<member>|<configVersion>[|round<n>]"
                        " or review:<namespace>:<production>|review|1|<fingerprint>")
        member = d.get("memberCode")
    elif m.re is REVIEW_KEY_RE:
        member = m["member"]
        if d.get("memberCode") != member:
            problems.append(f"memberCode {d.get('memberCode')!r} differs from the key's member {member!r}")
        if str(d.get("configVersion")) != m["cfg"]:
            problems.append(f"configVersion {d.get('configVersion')!r} differs from the key's {m['cfg']!r}")
        # The review's request carries the fingerprint as its snapshot digest
        if (d.get("snapshotDigest") or "") != m["fingerprint"]:
            problems.append(f"snapshotDigest {d.get('snapshotDigest')!r} differs from the key's fingerprint")
        expected_name = review_file_name(key)
        if os.path.basename(path) != expected_name:
            problems.append(f"file name should be {expected_name}")
    else:
        member, cfg = m["member"], m["cfg"]
        if member == "review":
            problems.append(f"key {key!r} names the review under a scenario: a review records under"
                            " review:<namespace>:<production>|review|1|<fingerprint> only")
        if not m["encounter"]:
            problems.append(f"key {key!r} has no encounter and event: Shutter looks up scenario:<S>:<encounter>:<event>|..."
                            " only, so this recording never replays")
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
    if kind == "review":
        problems += check_review(result) + review_tool_problems(d)
    else:
        problems += (check_findings(result) if kind == "findings" else check_plan(result))
    for f in ("transcript", "toolCalls"):
        v = d.get(f)
        if isinstance(v, str) and v.strip() and not v.strip().startswith(("[", "{")):
            problems.append(f"{f} should be JSON text or empty")
    return problems, m


def self_test():
    """Synthetic review recordings that prove review_tool_problems: a run with no SubmitReview call is a problem, whether
    its tool calls are empty, missing, not a list or hold other calls only."""
    never = "the run never called its terminal tool SubmitReview"
    submit = json.dumps([{"name": "search_review", "arguments": {}}, {"name": "SubmitReview", "arguments": {}}])
    cases = [
        ({"toolCalls": submit}, []),
        ({"toolCalls": json.loads(submit)}, []),
        ({"toolCalls": ""}, [never]),
        ({"toolCalls": "[]"}, [never]),
        ({}, [never]),
        ({"toolCalls": None}, [never]),
        ({"toolCalls": "{}"}, [never]),
        ({"toolCalls": {"name": "SubmitReview"}}, [never]),
        ({"toolCalls": "not json"}, [never]),
        ({"toolCalls": json.dumps([{"name": "search_review"}])}, [never]),
    ]
    failed = 0
    for d, want in cases:
        got = review_tool_problems(d)
        if got != want:
            failed += 1
            print(f"self-test: {d!r} gave {got!r}, expected {want!r}")
    # The ranking's entries carry the finding's code (a non-empty string), and item and setting as strings when present
    entry = {"finding_id": "F1", "rank": 1, "explanation": "Consistent with the cases of this item.",
             "code": "ALERTING_OFF", "item": "", "setting": "AlertOnError"}
    code_missing = "ranking[0] needs the finding's code, copied from the finding"
    rankings = [
        (entry, []),
        ({k: v for k, v in entry.items() if k not in ("item", "setting")}, []),
        ({**entry, "item": None}, []),
        ({k: v for k, v in entry.items() if k != "code"}, [code_missing]),
        ({**entry, "code": ""}, [code_missing]),
        ({**entry, "code": 7}, [code_missing]),
        ({**entry, "setting": 3}, ["ranking[0] setting must be a string, the finding's own"]),
    ]
    for e, want in rankings:
        got = [x for x in check_review({"ranking": [e], "summary": "", "unknowns": []})
               if "code" in x or "must be a string" in x]
        cases.append(e)
        if got != want:
            failed += 1
            print(f"self-test: ranking entry {e!r} gave {got!r}, expected {want!r}")
    print(f"self-test: {len(cases)} cases, {failed} failed")
    return 1 if failed else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("directory", nargs="?", default="fixtures/records")
    ap.add_argument("--scenarios", help="fixtures/scenarios.json, to list the scenarios without a full round-1 set")
    ap.add_argument("--self-test", action="store_true", help="check the review's tool rule on synthetic recordings")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    files = sorted(glob.glob(os.path.join(args.directory, "*.json")))
    if not files:
        print(f"no recordings in {args.directory}", file=sys.stderr)
        return 1
    bad = 0
    present = {}
    for path in files:
        problems, m = check_file(path)
        if m and m.re is KEY_RE:
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
            # A withheld merge or cancel never convenes the board, and a scenario played only in site-policy mode is
            # decided by the catalogue: neither needs recordings
            if expected.get("blocked_by") in WITHHELD:
                print(f"{s['id']}: withheld ({expected['blocked_by']}), no board")
                continue
            if expected.get("modes") and "board" not in expected["modes"] and not expected.get("incident"):
                print(f"{s['id']}: played in {', '.join(expected['modes'])} only, no board")
                continue
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
