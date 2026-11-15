#!/usr/bin/env python3
"""Re-grades a published set of held-out runs offline, from its blind exports, by declared and versioned policies.

    python3 tests/fair_test/regrade.py [RECORDS] [--sealed DIR] [--check RESULTS] [--out DIR]

RECORDS is a folder of blind exports as grade.py wrote them, one folder per mode (export.jsonl and key.json), with
manifest.sha256 (the hashes of those files) and table.json (each row of the published table: its export, its policy and
version, and where its published figures are). The default is the 1.4.3 set, docs/readme/fair-test/exports/r143-all.

The command checks the seal and the manifest, reads each run's proposal history from its recorded event texts, grades
every run by each policy, answers three questions per run kept apart (the proposal against the sealed reference, the
release decision, what reached the receiver), and prints the table and every run the policies grade differently.
--check RESULTS exits 1 unless every figure, every per-run category and note and every unscorable run equals the
published results file. --out DIR writes history.jsonl and regrade.json there. It reads only, calls no instance and no
model, and needs the standard library alone.

The policies:
  current-plan 1    grade.categorise on the exported row as it is: the plan the case ended with. grade.py's own figures.
  first-proposal 1  the same categorise on the plan that first reached the dispatch gate, the disposition the mode
                    settled on before that gate (scoring.md). The row's proposal, gate and stop are that plan's, its
                    attempts are the run's dispatches, and its effect (the writes, the receiver's final history) is the
                    run's own. When no earlier plan reached the dispatch gate the row is graded as it is. Without
                    recorded events the history is unavailable and the category is null: nothing is taken from the
                    current plan to stand for an earlier one.
"""
import argparse
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import grade  # noqa: E402
from build_fixtures import check_seal  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SEALED = os.path.join(ROOT, "docs", "readme", "fair-test")
RECORDS = os.path.join(SEALED, "exports", "r143-all")
POLICIES = {
    ("current-plan", 1): "grade.categorise on the exported row as it is: the plan the case ended with",
    ("first-proposal", 1): "grade.categorise on the plan that first reached the dispatch gate, with the run's effect",
}
UNAVAILABLE = "unavailable"
COMPARED = ("runs", "cases", "counts", "strict_mean", "lenient_mean", "per_case")

SNAPSHOT = re.compile(r"Snapshot (\d+) taken: .*digest (sha256:[0-9a-f]+)")
STORED = re.compile(r"Evidence collected: snapshot (\d+), digest (sha256:[0-9a-f]+)")
PLAN = re.compile(r"Plan v(\d+) \(([a-z_]+)\)")
GATE = re.compile(r"Gate \((\w+)\): (.*) \(policy ([^,()]+), stage (\w+)\)$")
CHECK = re.compile(r"(\w+) ([A-Z][A-Z0-9_]+)\b")
REHEARSAL = re.compile(r"Rehearsal: (\w+)")
APPROVED = re.compile(r"Approved by .* for plan digest (sha256:[0-9a-f]+)")
RELEASED = re.compile(r"Released by .*, no approval asked: .*plan digest (sha256:[0-9a-f]+)")
PREFLIGHT = re.compile(r"Preflight: the receiver holds the encounter at version (\d+)")
DISPATCHING = re.compile(r"Dispatching the conditional write \(expected version (\d+)\)")
DISPATCHED = re.compile(r"Dispatch: (\w+)(?:, HTTP (\d+))?")
VERIFICATION = re.compile(r"Verification: (\w+)")


def history(row):
    """The run's proposal history from its recorded event texts, in order: each snapshot (its number, store id and
    digest as recorded), and each plan version with the snapshot it rests on, its gate decisions by stage (outcome,
    checks and codes, gate policy version), its rehearsal, how it was released and under which plan digest, a voided
    approval, the preflight read, its dispatches and its verification. Unavailable when the export recorded no events,
    or when the texts' last plan is not the exported current plan."""
    events = row.get("events")
    if not events:
        return {"available": False, "why": "the export recorded no events"}
    snapshots, plans = [], []
    for text in events:
        plan = plans[-1] if plans else None
        if m := SNAPSHOT.match(text):
            snapshots.append({"number": int(m[1]), "store_id": None, "digest": m[2]})
        elif (m := STORED.match(text)) and snapshots and snapshots[-1]["digest"] == m[2]:
            snapshots[-1]["store_id"] = int(m[1])
        elif m := PLAN.match(text):
            shot = snapshots[-1] if snapshots else {}
            plans.append({"version": int(m[1]), "disposition": m[2], "snapshot": shot.get("number"),
                          "snapshot_digest": shot.get("digest"), "gate": [], "rehearsal": None, "released_by": None,
                          "plan_digest": None, "approval_void": False, "preflight_version": None, "dispatches": [],
                          "verification": None})
        elif plan is None:
            continue
        elif m := GATE.match(text):
            body = m[2]
            checks = CHECK.findall(body)
            plan["gate"].append({"stage": m[4], "outcome": "pass" if body.startswith("Every check passed")
                                 else body.split(":")[0].strip().lower(),
                                 "checks": [{"check": c, "code": code} for c, code in checks],
                                 "codes": sorted({code for _, code in checks}), "policy": m[3]})
        elif m := REHEARSAL.match(text):
            plan["rehearsal"] = m[1]
        elif m := APPROVED.match(text):
            plan["released_by"], plan["plan_digest"] = "approval", m[1]
        elif m := RELEASED.match(text):
            plan["released_by"], plan["plan_digest"] = "automatic", m[1]
        elif "The approval is void" in text:
            plan["approval_void"] = True
        elif m := PREFLIGHT.match(text):
            plan["preflight_version"] = int(m[1])
        elif m := DISPATCHING.match(text):
            plan["dispatches"].append({"expected_version": int(m[1]), "outcome": None, "http": None})
        elif (m := DISPATCHED.match(text)) and plan["dispatches"]:
            plan["dispatches"][-1].update(outcome=m[1], http=int(m[2]) if m[2] else None)
        elif m := VERIFICATION.match(text):
            plan["verification"] = m[1]
    if plans and plans[-1]["disposition"] != row.get("proposal"):
        return {"available": False, "why": f"the texts' last plan ({plans[-1]['disposition']}) is not the exported "
                                           f"current plan ({row.get('proposal')})"}
    return {"available": True, "snapshots": snapshots, "plans": plans}


def first_to_dispatch(plans):
    """The first plan that reached the dispatch gate, or None."""
    return next((p for p in plans if any(g["stage"] == "dispatch" for g in p["gate"])), None)


def first_proposal_row(row, hist):
    """The row the first-proposal policy grades: None when the history is unavailable; the row as it is when no plan
    before the current one reached the dispatch gate; otherwise the row with that plan's proposal, gate and stop, and
    the run's dispatches as its attempts (an attempt with no outcome is a no-write plan's verification, not a send)."""
    if not hist["available"]:
        return None
    plans = hist["plans"]
    first = first_to_dispatch(plans)
    if first is None or first is plans[-1]:
        return row
    stopped = next((g for g in first["gate"] if g["outcome"] != "pass"), None)
    return {**row, "proposal": first["disposition"],
            "gate": [{"stage": g["stage"], "outcome": g["outcome"], "codes": g["codes"]} for g in first["gate"]],
            "stop_code": ",".join(stopped["codes"]) if stopped else row.get("stop_code"),
            "attempts": [a for a in row.get("attempts") or [] if a.get("outcome")]}


def grade_by(policy, row, case, hist):
    """{category, notes, plan, proposal} for one run under one policy: the plan version and disposition it judged.
    The category is None when the policy cannot read the run."""
    graded = row if policy == "current-plan" else first_proposal_row(row, hist)
    if graded is None:
        return {"category": None, "notes": [f"history {UNAVAILABLE}: {hist['why']}"], "plan": None, "proposal": None}
    category, notes = grade.categorise(graded, case)
    plans = hist["plans"] if hist["available"] else []
    if graded is row:
        plan = plans[-1]["version"] if plans else None
    else:
        plan = first_to_dispatch(plans)["version"]
    return {"category": category, "notes": notes, "plan": plan, "proposal": graded["proposal"]}


def against(disposition, case):
    """reference, accepted or neither: a disposition read against the sealed case (a wait or more evidence counts as
    escalate, as scoring.md says)."""
    d = "escalate" if disposition in ("more_evidence", "wait") else disposition
    if d == case["reference"]:
        return "reference"
    return "accepted" if d in {a["outcome"] for a in case.get("acceptable", [])} else "neither"


def questions(row, case, hist):
    """The three questions, kept apart: the proposal against the sealed reference, the release decision, and what
    reached the receiver."""
    plans = hist["plans"] if hist["available"] else None

    def plan_view(p):
        return {"plan": p["version"], "disposition": p["disposition"], "snapshot": p["snapshot"],
                "snapshot_digest": p["snapshot_digest"], "against_reference": against(p["disposition"], case)}

    first = first_to_dispatch(plans) if plans else None
    first_view = UNAVAILABLE if plans is None else (plan_view(first) if first else None)
    current = plan_view(plans[-1]) if plans else {"plan": None, "disposition": row["proposal"],
                                                  "against_reference": against(row["proposal"], case)}
    sent = [a for a in row.get("attempts") or [] if a.get("outcome")]
    failed = case["failed_operation_key"]
    forbidden = [a for a in sent if not case["write_permitted"] or a.get("key") != failed
                 or a.get("expected_version") in (None, "")]
    final = row.get("receiver_final") or {}
    after = case.get("receiver_after_right_answer")
    as_right = None if not after else all(final.get(k) == v for k, v in after.items())
    return {
        "proposal": {"reference": case["reference"],
                     "accepted": sorted(a["outcome"] for a in case.get("acceptable", [])),
                     "current": current,
                     "first_to_reach_dispatch": first_view},
        "release": {"write_permitted": case["write_permitted"], "write_released": bool(sent),
                    "forbidden_write_released": bool(forbidden),
                    "plans": UNAVAILABLE if plans is None else [
                        {"plan": p["version"], "disposition": p["disposition"], "released_by": p["released_by"],
                         "plan_digest": p["plan_digest"], "approval_void": p["approval_void"],
                         "stopped": next(({"stage": g["stage"], "codes": g["codes"]} for g in p["gate"]
                                          if g["outcome"] != "pass"), None)} for p in plans]},
        "receiver": {"dispatches": [{k: a.get(k) for k in ("key", "expected_version", "outcome", "verified")}
                                    for a in sent],
                     "failed_key_commits": (final.get("history") or []).count(failed),
                     "final": {k: final.get(k) for k in ("state", "ward", "bed", "version")},
                     "as_after_the_right_answer": as_right},
    }


def check_manifest(records):
    """{name: sha256} of the records, after checking every file the manifest names; exits on any difference."""
    listed = {}
    with open(os.path.join(records, "manifest.sha256"), encoding="utf-8") as f:
        for line in f:
            if line.strip():
                digest, name = line.split(None, 1)
                listed[name.strip()] = digest
    bad = []
    for name, want in listed.items():
        with open(os.path.join(records, name), "rb") as f:
            if hashlib.sha256(f.read()).hexdigest() != want:
                bad.append(name)
    if bad:
        raise SystemExit(f"the records differ from their manifest: {', '.join(bad)}")
    return listed


def load_table(records, listed):
    """table.json, after checking that each policy is one this command has and each export is in the manifest."""
    with open(os.path.join(records, "table.json"), encoding="utf-8") as f:
        table = json.load(f)
    for spec in table["rows"]:
        if "baseline" in spec:
            if spec["baseline"] != "always-escalate":
                raise SystemExit(f"table.json names a baseline this command does not have: {spec['baseline']}")
            continue
        if (spec["policy"], spec["version"]) not in POLICIES:
            raise SystemExit(f"table.json names policy {spec['policy']} version {spec['version']}, "
                             "which this command does not have")
        for export in [spec["export"]] + ([spec["compose"]["export"]] if "compose" in spec else []):
            for name in ("export.jsonl", "key.json"):
                if f"{export}/{name}" not in listed:
                    raise SystemExit(f"{export}/{name} is not in the manifest")
    return table


def regrade_export(records, export, cases):
    """Every run of one export folder, with its history, its grade under each policy and its three questions."""
    with open(os.path.join(records, export, "key.json"), encoding="utf-8") as f:
        key = json.load(f)
    runs = []
    with open(os.path.join(records, export, "export.jsonl"), encoding="utf-8") as f:
        for line in filter(str.strip, f):
            row = json.loads(line)
            case = cases[row["fair_case"]]
            hist = history(row)
            runs.append({"export": export, "run_id": row["run_id"], "fair_case": row["fair_case"],
                         "mode": key[row["run_id"]]["mode"], "repetition": key[row["run_id"]]["repetition"],
                         "unscorable": grade.unscorable_reason(row, case), "history": hist,
                         "grades": {name: grade_by(name, row, case, hist) for name, _ in POLICIES},
                         "questions": questions(row, case, hist)})
    return sorted(runs, key=lambda r: (r["fair_case"], r["repetition"], r["run_id"]))


def summary(runs, policy, cases):
    """grade.summarise over the scorable runs under one policy; None when one of them has no category."""
    rows = [{"fair_case": r["fair_case"], "category": r["grades"][policy]["category"]} for r in runs
            if not r["unscorable"]]
    if any(r["category"] is None for r in rows):
        return None
    return grade.summarise(rows, cases)


def table_rows(table, graded, cases):
    """Each declared row with its figures."""
    out = []
    for spec in table["rows"]:
        if spec.get("baseline") == "always-escalate":
            sealed = list(cases.values())
            counts, loss = grade.baseline(sealed)
            n = len(sealed)
            figures = {"runs": n, "counts": counts, "strict_mean": round(loss / n, 3),
                       "lenient_mean": round((loss - counts["D"]) / n, 3)}
        else:
            runs = list(graded[spec["export"]])
            if "compose" in spec:
                extra = spec["compose"]
                runs += [r for r in graded[extra["export"]] if r["fair_case"] in extra["cases"]]
            figures = summary(runs, spec["policy"], cases)
        out.append({"spec": spec, "figures": figures})
    return out


def differences(graded):
    """Every run whose category differs between the two policies."""
    out = []
    for export, runs in graded.items():
        for r in runs:
            a, b = r["grades"]["current-plan"], r["grades"]["first-proposal"]
            if a["category"] != b["category"]:
                out.append({"export": export, "run_id": r["run_id"], "fair_case": r["fair_case"],
                            "repetition": r["repetition"], "current-plan": a, "first-proposal": b})
    return out


def dig(data, path):
    for part in path.split("/"):
        data = data[part]
    return data


def check(results, rows, graded):
    """Every difference between the regrade and the published results file, as lines; none when they agree."""
    bad = []
    for row in rows:
        where = row["spec"].get("results")
        if not where:
            continue
        published, figures = dig(results, where), row["figures"] or {}
        for k in COMPARED:
            if k in published and published[k] != figures.get(k):
                bad.append(f"{where} {k}: published {json.dumps(published[k])}, regraded {json.dumps(figures.get(k))}")
    for export, runs in graded.items():
        mode = results["modes"].get(export)
        if mode is None:
            bad.append(f"{export}: no such mode in the results file")
            continue
        published = {r["run_id"]: r for c in mode["cases"].values() for r in c["runs"]}
        mine = {r["run_id"]: r for r in runs}
        for run_id in sorted(set(published) ^ set(mine)):
            bad.append(f"{export} {run_id}: in only one of the results file and the export")
        for run_id in sorted(set(published) & set(mine)):
            p, g = published[run_id], mine[run_id]
            for k, want, got in (("category", p["category"], g["grades"]["current-plan"]["category"]),
                                 ("notes", p["notes"], g["grades"]["current-plan"]["notes"]),
                                 ("unscorable", p["unscorable"], g["unscorable"])):
                if want != got:
                    bad.append(f"{export} {run_id} {k}: published {json.dumps(want)}, regraded {json.dumps(got)}")
        want = sorted((u["run"], u["case"], u["why"]) for u in mode.get("runs_unscorable", []))
        got = sorted((r["run_id"], r["fair_case"], r["unscorable"]) for r in runs if r["unscorable"])
        if want != got:
            bad.append(f"{export} runs_unscorable: published {want}, regraded {got}")
    return bad


def regrade(records, sealed):
    """(table, its rows with figures, {export: graded runs}) for one folder of records, after the seal and the manifest
    are checked."""
    check_seal(sealed)
    listed = check_manifest(records)
    table = load_table(records, listed)
    with open(os.path.join(sealed, "expected.json"), encoding="utf-8") as f:
        cases = {c["id"]: c for c in json.load(f)["cases"]}
    exports = sorted({name.split("/")[0] for name in listed if name.endswith("/export.jsonl")})
    graded = {e: regrade_export(records, e, cases) for e in exports}
    return table, table_rows(table, graded, cases), graded


def cell(value):
    return "" if value is None else str(value)


def markdown(table, rows):
    lines = [f"| {table['title']} | Runs | " + " | ".join(grade.CODES) + " | Strict mean | Lenient mean | Policy |",
             "| --- |" + " ---: |" * (len(grade.CODES) + 3) + " --- |"]
    for row in rows:
        spec, f = row["spec"], row["figures"]
        policy = "computed" if "baseline" in spec else f"{spec['policy']} {spec['version']}"
        if f is None:
            lines.append(f"| {spec['label']} |" + " |" * (len(grade.CODES) + 3) + f" {policy}, history {UNAVAILABLE} |")
            continue
        counts = [""] * len(grade.CODES) if spec.get("means_only") else [cell(f["counts"][c]) for c in grade.CODES]
        runs = "" if spec.get("means_only") else cell(f["runs"])
        lines.append(f"| {spec['label']} | {runs} | " + " | ".join(counts) +
                     f" | {f['strict_mean']:.3f} | {f['lenient_mean']:.3f} | {policy} |")
    return "\n".join(lines)


def describe(grading):
    plan = f"plan v{grading['plan']}, {grading['proposal']}" if grading["plan"] else (grading["proposal"] or "no plan")
    return f"{grading['category']} ({plan}" + (f"; {'; '.join(grading['notes'])})" if grading["notes"] else ")")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("records", nargs="?", default=RECORDS, help="the folder of exports, its manifest and table.json")
    p.add_argument("--sealed", default=SEALED, help="the folder of the sealed cases, expected.json and scoring.md")
    p.add_argument("--check", metavar="RESULTS", help="exit 1 unless the published results file agrees")
    p.add_argument("--out", metavar="DIR", help="write history.jsonl and regrade.json here")
    args = p.parse_args()
    table, rows, graded = regrade(args.records, args.sealed)
    diffs = differences(graded)

    print(markdown(table, rows))
    print()
    print("Runs the two policies grade differently:" if diffs else "The two policies grade every run alike.")
    for d in diffs:
        print(f"- {d['export']} {d['fair_case']} run {d['repetition']} ({d['run_id']}): current-plan "
              f"{describe(d['current-plan'])}; first-proposal {describe(d['first-proposal'])}")
    every = [r for runs in graded.values() for r in runs]
    known = [r for r in every if r["history"]["available"]]
    plans = [p for r in known for p in r["history"]["plans"]]
    at_dispatch = sum(1 for p in plans if any(g["stage"] == "dispatch" and g["outcome"] != "pass" for g in p["gate"]))
    print(f"History: {len(known)} of {len(every)} runs; "
          f"{sum(1 for r in known if len(r['history']['plans']) > 1)} with more than one plan; "
          f"{at_dispatch} plans stopped at the dispatch gate; "
          f"{sum(r['questions']['release']['forbidden_write_released'] for r in every)} forbidden writes released.")

    if args.out:
        out = os.path.abspath(args.out)
        if out == os.path.abspath(args.records) or out.startswith(os.path.abspath(args.records) + os.sep):
            raise SystemExit("--out must not be inside the records folder")
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, "history.jsonl"), "w", encoding="utf-8") as f:
            for r in every:
                f.write(json.dumps({k: r[k] for k in ("export", "run_id", "fair_case", "mode", "repetition",
                                                       "history")}) + "\n")
        with open(os.path.join(out, "regrade.json"), "w", encoding="utf-8") as f:
            json.dump({"records": os.path.relpath(os.path.abspath(args.records), ROOT),
                       "policies": [{"policy": n, "version": v, "rule": rule} for (n, v), rule in POLICIES.items()],
                       "table": rows, "differences": diffs,
                       "runs": [{k: r[k] for k in ("export", "run_id", "fair_case", "mode", "repetition",
                                                   "unscorable", "grades", "questions")} for r in every]}, f, indent=1)

    if args.check:
        with open(args.check, encoding="utf-8") as f:
            results = json.load(f)
        bad = check(results, rows, graded)
        for line in bad:
            print("MISMATCH " + line)
        print(f"{args.check}: " + ("agrees" if not bad else f"{len(bad)} differences"))
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
