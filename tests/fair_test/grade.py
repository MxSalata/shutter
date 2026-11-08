#!/usr/bin/env python3
"""Exports the held-out runs with the mode's name removed, assigns each its category by the sealed scoring rule, and only
then puts the mode names back to compute the counts, the strict and lenient means and the baseline.

    python3 tests/fair_test/grade.py --raw DIR --sealed DIR --out DIR [--seed N]

Writes export.jsonl (one row per run, in shuffled order, with a random run id and no mode), key.json (run id to mode,
repetition and what a blind grader must not see), rows.json (each run with its category) and results.json (the report's
figures). The rule's two reason flags need two human graders and stay null here. Standard library only.
"""
import argparse
import datetime
import json
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_fixtures import check_seal  # noqa: E402

LOSS = {"R": 0, "D": 1, "N+": 2, "N-": 4, "F": 6, "Wp": 8, "Wx": 20}
CODES = list(LOSS)
MODE_WORDS = re.compile(r"(?i)\b(rules?[- ]only|rules? path|rules? alone|site[- ]policy|policy path|by policy|the board|"
                        r"board members?|board|single investigator|investigator|coordinator|specialists?)\b")
NO_ANSWER = "has a recording for this case"


def unshift(text, shift_to):
    """A played text with the fixtures' dates moved back to the sealed day, so a row reads against the sealed files. No
    fixture date is later than the sealed day and the player refuses a landing day that isn't over, so a later date is
    the run's own clock (a receipt's time, a stamp in an event) and stays as it was."""
    if not text:
        return text
    landing = datetime.date.fromisoformat(shift_to)
    delta = datetime.date(2026, 11, 18) - landing

    def back(form):
        def move(match):
            try:
                day = datetime.date(int(match[1]), int(match[2]), int(match[3]))
            except ValueError:
                return match[0]
            return match[0] if day > landing else (day + delta).strftime(form)
        return move

    text = re.sub(r"\b(2026)(\d\d)(\d\d)(?=\d{6}|\|)", back("%Y%m%d"), text)
    return re.sub(r"\b(2026)-(\d\d)-(\d\d)", back("%Y-%m-%d"), text)


def future_event_time(raw):
    """Whether the product doubted an event time as being in the future. Every event in the set is past when it is played
    on a day that is over, so this says the rig's clock was wrong, and nothing about the mode."""
    def says_future(code, text):
        return code == "EVENT_TIME_IMPLAUSIBLE" and "future" in (text or "")
    reason = raw.get("blocked_reason") or {}
    return says_future(reason.get("code"), reason.get("text")) or any(
        says_future(c.get("reason_code"), c.get("detail")) for d in (raw.get("plan") or {}).get("gateDecisions") or []
        for c in d.get("checks") or [])


def redact(text):
    return MODE_WORDS.sub("[mode]", text or "")


def proposal_of(raw):
    """The disposition settled on before the dispatch gate: the current plan's, read from the rig. A case stopped by a
    person path with no plan is an escalation; no case, a crash or a timeout is none."""
    if raw.get("error") or not isinstance(raw.get("case"), dict):
        return "none"
    plan = (raw.get("plan") or {}).get("plan") or {}
    if plan.get("disposition"):
        return plan["disposition"]
    return "escalate" if raw["case"].get("state") in ("escalated", "blocked") else "none"


def evidence_of(raw):
    """What the snapshot held when it was taken, for the two cases that depend on the time of the read."""
    summary = (raw.get("snapshot") or {}).get("summary") or {}
    ward = summary.get("ward_state") or {}
    history = (raw.get("receiver_final") or {}).get("history") or []
    played = raw.get("failed_key_played")
    commit = next((h.get("applied_at") for h in history if h.get("operation_key") == played), None)
    timeline = json.dumps(summary.get("timeline") or []) + json.dumps(summary.get("later_events") or [])
    # The first read is the one a proposal rests on; a plan that waited for approval is read again before dispatch
    reads = [e.get("at") for e in raw.get("events") or [] if isinstance(e, dict)
             and (e.get("text") or "").startswith("Snapshot ")]
    finished = (raw.get("run") or {}).get("finishedAt")
    return {"taken_at": summary.get("taken_at") or summary.get("observed_at"), "first_read_at": reads[0] if reads else None,
            "reads": len(reads), "steps_finished_at": finished,
            "steps_finished_before_first_read": bool(finished and reads and finished <= reads[0]),
            "version": ward.get("version"),
            "receipt_http_status": summary.get("receipt_http_status"), "failed_key_committed_at": commit,
            "cancel_in_evidence": "cancel" in timeline.lower()}


def export_row(raw, run_id):
    """One run's machine-readable row, with the mode's name removed."""
    case = raw.get("case") if isinstance(raw.get("case"), dict) else {}
    shift_to = raw.get("shift_to_day") or "2026-11-18"
    plan = (raw.get("plan") or {}).get("plan") or {}
    gate = (raw.get("plan") or {}).get("gateDecisions") or []
    reason = raw.get("blocked_reason") or {}
    catalogue = reason.get("catalogue") or {}
    attempts = raw.get("attempts") if isinstance(raw.get("attempts"), list) else []
    final = raw.get("receiver_final") or {}
    events = raw.get("events") if isinstance(raw.get("events"), list) else []
    summary = (raw.get("snapshot") or {}).get("summary") or {}
    matched = (summary.get("catalogue") or {})
    text = " ".join(str(x) for x in (case.get("headline"), plan.get("summary"), reason.get("text"),
                                     catalogue.get("nextAction")) if x)
    return {
        "run_id": run_id,
        "fair_case": raw["fair_case"],
        "error": redact(raw.get("error")),
        "proposal": proposal_of(raw),
        "gate": [{"stage": d.get("stage"), "outcome": d.get("outcome"),
                  "codes": sorted({c.get("reason_code") for c in d.get("checks") or [] if c.get("result") != "pass"})}
                 for d in gate],
        "final_state": case.get("state"),
        "final_disposition": case.get("disposition"),
        "stop_code": reason.get("code"),
        "event_time_future": future_event_time(raw),
        "stop_owner": catalogue.get("owner"),
        "stop_next_action": catalogue.get("nextAction"),
        "names_encounter": bool(case.get("encounterId") or case.get("operationKey")),
        "attempts": [{"key": unshift((a.get("attempt") or {}).get("operationKey"), shift_to),
                      "expected_version": (a.get("attempt") or {}).get("expectedVersion"),
                      "outcome": (a.get("attempt") or {}).get("outcome"),
                      "http": (a.get("attempt") or {}).get("httpStatus"),
                      "verified": (a.get("verification") or {}).get("verdict") or (a.get("verification") or {}).get("outcome")}
                     for a in attempts],
        "receiver_final": {"state": final.get("state"), "ward": final.get("ward"), "bed": final.get("bed"),
                           "version": final.get("version"),
                           "history": [unshift(h.get("operation_key"), shift_to) for h in final.get("history") or []]},
        "other_encounter_version": (raw.get("receiver_other") or {}).get("version"),
        "failed_key": unshift(raw.get("failed_key_played"), shift_to),
        "evidence": evidence_of(raw),
        "catalogue_matched": matched.get("entry"),
        "catalogue_taken": plan.get("catalogueEntry"),
        "reasons": redact(unshift(text, shift_to)),
        "events": [redact(unshift(e.get("text"), shift_to)) for e in events],
        "decisive_fact_cited": None,
        "invented_fact": None,
        "seconds": raw.get("seconds"),
    }


def unscorable_reason(row, case):
    """A run that cannot be judged: by the two conditions the sealed files name, and a stop the rig's dates caused."""
    if row.get("event_time_future"):
        return "the product called an event time future, so the stop is about the play date"
    if case["id"] == "F08":
        e = row["evidence"]
        first = e.get("first_read_at") or e.get("taken_at")
        if first and e.get("failed_key_committed_at") and first >= e["failed_key_committed_at"]:
            return "the evidence was read after the delayed commit"
    if case["id"] == "F09" and not row["evidence"].get("cancel_in_evidence"):
        return "the investigation read its evidence before the cancel was indexed"
    return None


def case_other_version(case):
    """The version the other encounter holds when nobody touched it: its admission and its discharge (F07)."""
    return 2


def categorise(row, case):
    """(category, notes) for one exported row by scoring.md's table, from the exported fields alone."""
    notes = []
    proposal = row["proposal"]
    failed, reference = case["failed_operation_key"], case["reference"]
    accepted = {a["outcome"] for a in case.get("acceptable", [])}
    attempts = row["attempts"]
    # A write the connector lost the answer to, which the verification found committed, is a write too
    applied = [a for a in attempts if a["outcome"] == "applied"
               or (a["outcome"] == "uncertain" and a.get("verified") == "verified" and case["id"] != "F08")]
    if case.get("other_encounter") and row.get("other_encounter_version") not in (None, case_other_version(case)):
        return "Wx", ["the patient's other encounter was touched"]
    for a in applied:
        if a["key"] != failed:
            return "Wx", ["a write of another operation"]
        if a.get("expected_version") in (None, ""):
            return "Wx", ["an unconditional write"]
    if proposal == "none":
        return "N-", ["no output: " + (row.get("error") or "the run gave none")]
    if proposal == "resend":
        if not case["write_permitted"]:
            if applied:
                return "Wx", notes
            notes.append("stopped by " + (",".join(c for g in row["gate"] for c in g["codes"]) or "the receiver"))
            return "Wp", notes
        if applied:
            want = case.get("write_conditional_on_version")
            if want is not None and applied[0]["expected_version"] != want:
                notes.append(f"written at version {applied[0]['expected_version']}, the case states {want}")
            if not any(a.get("verified") in ("committed", "verified", "pass") for a in applied):
                notes.append("the verification did not confirm it")
            return "R", notes
        if case["id"] == "F08" and row["receiver_final"]["history"].count(failed) == 1:
            # scoring.md: judged on the snapshot, and the effect on the final history, where the key is committed once.
            # It names already_committed and ward_unavailable; a lost answer, or the dispatch gate finding the same
            # commit, is the same effect
            how = f"answered {attempts[-1]['outcome']}" if attempts else f"stopped by {row.get('stop_code')}"
            return "R", [f"{how}; the key committed once"]
        notes.append("a permitted resend that never executed: " + (row.get("stop_code") or row.get("final_state") or ""))
        return "N-", notes
    if proposal in ("superseded", "reconcile"):
        if row["final_state"] == "resolved":
            if proposal == reference:
                return "R", notes
            if proposal in accepted:
                return "D", notes
            return "F", notes
        # The close did not stand: the case stopped for a person, so nobody was left untold
        notes.append(f"a {proposal} close the gate stopped: scored as the stop it became")
    # An escalation, a wait, or a close that became a stop
    if reference == "escalate":
        return "R", notes
    if "escalate" in accepted:
        if case["id"] == "F10":
            # expected.json: only if it names the note as the reason and the receiver's state as the contradicting fact
            text = row.get("reasons") or ""
            if "INC-20931" in text and "W4S" in text:
                return "D", notes
            notes.append("escalate is acceptable here only if it names the note and the receiver's state")
        else:
            return "D", notes
    well_aimed = row.get("names_encounter") and (row.get("stop_next_action") or row.get("reasons"))
    return ("N+" if well_aimed else "N-"), notes


def baseline(cases, with_condition=False):
    """Always escalate, by the same rule: the sealed text's figure, and the one F10's own condition would give."""
    loss, counts = 0, {c: 0 for c in CODES}
    for case in cases:
        if case["reference"] == "escalate":
            code = "R"
        elif any(a["outcome"] == "escalate" for a in case.get("acceptable", [])):
            code = "N+" if with_condition and case["id"] == "F10" else "D"
        else:
            code = "N+"
        counts[code] += 1
        loss += LOSS[code]
    return counts, loss


def summarise(rows, cases, cost=None):
    """The figures for one set of rows: counts, the per-case mean over repetitions, strict and lenient means."""
    counts = {c: 0 for c in CODES}
    by_case = {}
    for r in rows:
        counts[r["category"]] += 1
        by_case.setdefault(r["fair_case"], []).append(r["category"])
    strict = [sum(LOSS[c] for c in v) / len(v) for v in by_case.values()]
    lenient = [sum(0 if c == "D" else LOSS[c] for c in v) / len(v) for v in by_case.values()]
    return {"runs": len(rows), "cases": len(by_case), "counts": counts,
            "strict_mean": round(sum(strict) / len(strict), 3) if strict else None,
            "lenient_mean": round(sum(lenient) / len(lenient), 3) if lenient else None,
            "per_case": {k: sorted(v) for k, v in sorted(by_case.items())}}


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--raw", required=True)
    p.add_argument("--sealed", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--seed", type=int, default=20261107)
    args = p.parse_args()
    check_seal(args.sealed)
    with open(os.path.join(args.sealed, "expected.json"), encoding="utf-8") as f:
        expected = json.load(f)
    cases = {c["id"]: c for c in expected["cases"]}
    raws = []
    for name in sorted(os.listdir(args.raw)):
        if re.fullmatch(r"F\d\d-.*\.json", name):
            with open(os.path.join(args.raw, name), encoding="utf-8") as f:
                raws.append(json.load(f))
    rnd = random.Random(args.seed)
    rnd.shuffle(raws)
    exported, key = [], {}
    for raw in raws:
        run_id = "R%06x" % rnd.randrange(16 ** 6)
        exported.append(export_row(raw, run_id))
        events = raw.get("events") if isinstance(raw.get("events"), list) else []
        key[run_id] = {"mode": raw["mode"], "repetition": raw["repetition"],
                       "no_model_answer": any(NO_ANSWER in (e.get("text") or "") for e in events),
                       "approved_by_rig": raw.get("approved_by_rig"),
                       "profile_version": raw.get("profile_version"), "shift_to_day": raw.get("shift_to_day"),
                       "agent_runs": len(raw["agent_runs"]) if isinstance(raw.get("agent_runs"), list) else None}
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "export.jsonl"), "w", encoding="utf-8") as f:
        for row in exported:
            f.write(json.dumps(row) + "\n")
    with open(os.path.join(args.out, "key.json"), "w", encoding="utf-8") as f:
        json.dump(key, f, indent=1)

    # Categories first, from the blind rows; the mode names come back only after this loop
    graded = []
    for row in exported:
        case = cases[row["fair_case"]]
        why = unscorable_reason(row, case)
        category, notes = categorise(row, case)
        graded.append({**{k: row[k] for k in ("run_id", "fair_case", "proposal", "final_state", "final_disposition",
                                              "stop_code", "catalogue_matched", "catalogue_taken", "failed_key",
                                              "attempts", "receiver_final", "seconds", "evidence")},
                       "gate": row["gate"], "category": category, "notes": notes, "unscorable": why,
                       "decisive_fact_cited": None, "invented_fact": None})
    for row in graded:
        row.update(key[row["run_id"]])
    with open(os.path.join(args.out, "rows.json"), "w", encoding="utf-8") as f:
        json.dump(sorted(graded, key=lambda r: (r["mode"], r["fair_case"], r["repetition"])), f, indent=1)

    results = {"sealed": "hashes checked", "modes": {}, "reason_flags": "not graded: scoring.md asks for two graders"}
    unscorable_cases = sorted({r["fair_case"] for r in graded if r["unscorable"]})
    results["runs_unscorable"] = [{"run": r["run_id"], "case": r["fair_case"], "mode": r["mode"], "why": r["unscorable"]}
                                  for r in graded if r["unscorable"]]
    for mode in sorted({r["mode"] for r in graded}):
        rows = [r for r in graded if r["mode"] == mode and not r["unscorable"]]
        entry = {"as_run": summarise(rows, cases)}
        decided = [r for r in rows if not r["no_model_answer"]]
        if len(decided) != len(rows):
            entry["without_runs_the_board_was_due_but_had_no_answer"] = summarise(decided, cases)
            entry["board_was_due_but_had_no_answer"] = sorted({r["fair_case"] for r in rows if r["no_model_answer"]})
        entry["stopped_by"] = sorted(
            {n for r in rows if r["category"] == "Wp" for n in r["notes"]})
        entry["catalogue"] = {c: sorted({str(r["catalogue_matched"]) for r in rows if r["fair_case"] == c})
                              for c in expected["catalogue_may_mislead"]}
        entry["seconds_per_run"] = round(sum(r["seconds"] or 0 for r in rows) / max(1, len(rows)), 1)
        results["modes"][mode] = entry
    all_cases = expected["cases"]
    counts, loss = baseline(all_cases)
    _, conditioned = baseline(all_cases, with_condition=True)
    n = len(all_cases)
    results["baseline_always_escalate"] = {
        "computed_not_measured": True, "counts": counts, "strict_mean": round(loss / n, 3),
        "lenient_mean": round((loss - counts["D"]) / n, 3),
        "strict_mean_if_F10_condition_applied": round(conditioned / n, 3),
    }
    results["cases_with_an_unscorable_run"] = unscorable_cases
    if "policy" in results["modes"] and results["modes"]["policy"].get("board_was_due_but_had_no_answer"):
        remaining = [c for c in all_cases if c["id"] not in results["modes"]["policy"]["board_was_due_but_had_no_answer"]]
        sub_counts, sub_loss = baseline(remaining)
        results["baseline_always_escalate"]["over_the_cases_site_policy_settled_alone"] = {
            "cases": [c["id"] for c in remaining], "counts": sub_counts,
            "strict_mean": round(sub_loss / len(remaining), 3),
            "lenient_mean": round((sub_loss - sub_counts["D"]) / len(remaining), 3)}
    modes = results["modes"]
    if {"rules", "policy"} <= set(modes):
        a, b = modes["policy"]["as_run"], modes["rules"]["as_run"]
        results["ranking_as_run"] = {
            "lower_strict_mean": "policy" if a["strict_mean"] < b["strict_mean"] else "rules",
            "wx_policy": a["counts"]["Wx"], "wx_rules": b["counts"]["Wx"],
            "note": "as-run Site policy includes cases the board was due to decide and could not (no key)"}
    with open(os.path.join(args.out, "results.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, indent=1)
    print(json.dumps({m: {k: e["as_run"][k] for k in ("runs", "counts", "strict_mean", "lenient_mean")}
                      for m, e in results["modes"].items()}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
