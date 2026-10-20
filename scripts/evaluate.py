#!/usr/bin/env python3
"""Build docs/readme/evaluation.md and evaluation.json from the recorded live runs: how the board of specialists
decided each recorded case against the scenario's expected outcome, how far its members agreed, which evidence each
cited, and what the runs cost in tokens, money and time. No model calls and no IRIS: it reads files only.

    python3 scripts/evaluate.py [--check]

Inputs: the recordings (fixtures/records/*.json, one per board member and case, as check-records.py reads them), the
expected outcomes (fixtures/scenarios.json), the catalogue (knowledge/catalogue/catalogue.json), the seeded model
prices (Shutter.Store.ModelPrice's Seed, read from its source) and the played outcomes in docs/readme/comparison.md.
--check builds both files in memory and compares them with the committed ones (exit 1 on a difference), like
build-catalogue.py --check. Standard library only.
"""
import argparse
import datetime
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECORDS = os.path.join(ROOT, "fixtures", "records")
SCENARIOS = os.path.join(ROOT, "fixtures", "scenarios.json")
CATALOGUE = os.path.join(ROOT, "knowledge", "catalogue", "catalogue.json")
PRICES = os.path.join(ROOT, "src", "Shutter", "Store", "ModelPrice.cls")
COMPARISON = os.path.join(ROOT, "docs", "readme", "comparison.md")
OUT_MD = os.path.join(ROOT, "docs", "readme", "evaluation.md")
OUT_JSON = os.path.join(ROOT, "docs", "readme", "evaluation.json")

SPECIALISTS = ["conformance", "encounter", "impact"]
MEMBERS = SPECIALISTS + ["coordinator"]
LETTER = {"conformance": "C", "encounter": "E", "impact": "I", "coordinator": "P"}
# The same key pattern as check-records.py: scenario:<S>:<encounter>:<event>|<member>|<configVersion>[|round<n>]
KEY_RE = re.compile(r"^scenario:(?P<scenario>S\d+):(?P<encounter>[^:|]+):(?P<event>[^:|]+)"
                    r"\|(?P<member>[a-z]+)\|(?P<cfg>\d+)(?:\|round(?P<round>\d+))?$")
# A catalogue entry's preferred outcome as the board's disposition: "none" closes the case with nothing sent
OUTCOME_DISPOSITION = {"none": "superseded", "reconcile": "reconcile", "escalate": "escalate", "resend": "resend",
                       "resend_chain": "resend", "resend_latest": "resend", "resend_unconditional": "resend"}


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def rel(path):
    return os.path.relpath(path, ROOT)


def load_prices():
    """The rows of Shutter.Store.ModelPrice's Seed: model, input, output, cache read, cache write, per million tokens."""
    text = open(PRICES, encoding="utf-8").read()
    rows = {m[0]: tuple(float(x) for x in m[1:]) for m in
            re.findall(r'\["([^"]+)",\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)\]', text)}
    as_of = re.search(r'asOf = "([^"]+)"', text)
    return rows, as_of.group(1) if as_of else ""


def cost(prices, r):
    """Shutter.Store.ModelPrice's Cost: prompt tokens exclude cache reads and writes; rounded to six places."""
    p = prices.get(r["model"])
    if not p:
        return None
    usd = (r["prompt"] * p[0] + r["completion"] * p[1] + r["cache_read"] * p[2] + r["cache_write"] * p[3]) / 1e6
    return round(usd, 6)


def parse_time(s):
    return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")


def load_runs(prices):
    runs = []
    for path in sorted(glob.glob(os.path.join(RECORDS, "*.json"))):
        d = load_json(path)
        m = KEY_RE.match(d.get("key", ""))
        if not m or m["member"] not in MEMBERS:
            continue
        resp = d["response"]
        result = resp.get("result")
        if isinstance(result, str):
            result = json.loads(result)
        r = {
            "file": os.path.basename(path), "scenario": m["scenario"], "encounter": m["encounter"], "event": m["event"],
            "member": m["member"], "round": int(m["round"] or 1), "model": resp.get("model") or d.get("model"),
            "mode": resp.get("mode"), "started_at": resp.get("started_at"), "duration_ms": int(resp.get("duration_ms") or 0),
            "prompt": int(resp.get("prompt_tokens") or 0), "completion": int(resp.get("completion_tokens") or 0),
            "cache_read": int(resp.get("cache_read_tokens") or 0), "cache_write": int(resp.get("cache_creation_tokens") or 0),
            "iterations": int(resp.get("iterations") or 0), "tool_calls": int(resp.get("tool_calls") or 0),
            "disposition": result.get("disposition"), "confidence": result.get("confidence"),
            "evidence_refs": list(result.get("evidence_refs") or []), "result": result,
        }
        r["cost_usd"] = cost(prices, r)
        runs.append(r)
    return runs


def comparison_rows():
    """Per scenario, the live board's and rules alone's played outcome from comparison.md's table."""
    rows = {}
    if not os.path.exists(COMPARISON):
        return rows
    lines = open(COMPARISON, encoding="utf-8").read().splitlines()
    header = None
    for line in lines:
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells and cells[0] == "Scenario":
            header = cells
            continue
        m = re.match(r"(S\d+)\s", cells[0]) if header else None
        if not m:
            continue
        row = dict(zip(header, cells))
        out = {}
        for col, name in (("Board, live", "board_live"), ("Board, replay", "board_replay"), ("Rules only", "rules")):
            cell = row.get(col, "")
            status = ("as expected" if cell.startswith("as expected") else "differs" if cell.startswith("**differs**")
                      else "no agents" if cell.startswith("no agents") else "")
            usd = re.search(r"\(([\d.]+) USD\)", cell)
            out[name] = {"status": status, "cost_usd": float(usd.group(1)) if usd else None}
        rows[m.group(1)] = out
    return rows


def matches(disposition, expected):
    return disposition == expected["disposition"] or disposition in expected.get("acceptable", [])


def expected_label(expected):
    alts = [a for a in expected.get("acceptable", []) if a != expected["disposition"]]
    return expected["disposition"] + (f" (or {', '.join(alts)})" if alts else "")


def build():
    prices, prices_as_of = load_prices()
    runs = load_runs(prices)
    scenarios = {s["id"]: s for s in load_json(SCENARIOS)}
    order = list(scenarios)
    catalogue = {e["id"]: e for e in load_json(CATALOGUE)}
    played = comparison_rows()

    # One pass per case and round: the three specialists, then the coordinator
    passes = {}
    for r in runs:
        passes.setdefault((r["scenario"], r["encounter"], r["event"], r["round"]), {})[r["member"]] = r
    # In the scenarios' order; a scenario's cases in the order the board took them up
    first = {k: min(r["started_at"] for r in v.values()) for k, v in passes.items()}
    keys = sorted(passes, key=lambda k: (order.index(k[0]) if k[0] in order else 999,
                                         min(first[j] for j in passes if j[:3] == k[:3]), k[3]))
    rounds_of = {}
    for k in keys:
        rounds_of.setdefault(k[:3], []).append(k[3])

    out_passes = []
    for k in keys:
        sid, enc, event, rnd = k
        members = passes[k]
        s = scenarios.get(sid, {})
        exp = s.get("expected", {})
        coord = members.get("coordinator")
        plan = coord["result"] if coord else {}
        last_round = rnd == max(rounds_of[k[:3]])
        incident = bool(exp.get("incident"))
        p = {"scenario": sid, "title": s.get("title", ""), "encounter": enc, "event": event, "round": rnd,
             "rounds": len(rounds_of[k[:3]]), "incident": incident, "complete": all(m in members for m in MEMBERS),
             "expected_blocked_by": exp.get("blocked_by", "")}
        # What the pass is scored against
        if incident:
            spec = next((e for e in exp.get("encounters", []) if e["encounter"] == enc), {})
            entries = spec.get("entries", [])
            p["expected_entries"] = entries
            p["expected_writes_for_encounter"] = spec.get("writes")
            entry = plan.get("catalogue_entry") or ""
            if entry in entries:
                want = OUTCOME_DISPOSITION.get((catalogue.get(entry) or {}).get("preferred", {}).get("outcome"))
                p["expected"] = {"disposition": want, "from": f"entry {entry}, one of {', '.join(entries)}"}
            else:
                p["expected"] = {"disposition": None, "from": f"entries {', '.join(entries)}"}
            p["scored"] = True
        else:
            p["expected"] = {"disposition": exp.get("disposition"), "acceptable": exp.get("acceptable", []),
                             "from": "scenarios.json"}
            p["expected_entries"] = sorted((e for e, c in catalogue.items() if sid in (c.get("scenarios") or [])),
                                           key=lambda e: int(e[1:]))
            # A scenario whose plan is re-made after a change is scored on its last pass only
            p["scored"] = last_round
        p["members"] = {}
        for name in MEMBERS:
            r = members.get(name)
            if not r:
                continue
            p["members"][name] = {
                "disposition": r["disposition"], "confidence": r["confidence"], "evidence_refs": r["evidence_refs"],
                "matches_expected": (matches(r["disposition"], p["expected"]) if p["expected"]["disposition"] else None),
                "model": r["model"], "started_at": r["started_at"], "duration_ms": r["duration_ms"],
                "prompt_tokens": r["prompt"], "completion_tokens": r["completion"], "cache_read_tokens": r["cache_read"],
                "cache_write_tokens": r["cache_write"], "iterations": r["iterations"], "tool_calls": r["tool_calls"],
                "cost_usd": r["cost_usd"], "file": r["file"],
            }
        entry = plan.get("catalogue_entry") or ""
        p["catalogue_entry"] = entry
        p["entry_decides"] = (catalogue.get(entry) or {}).get("decides", "")
        p["entry_lists_scenario"] = sid in ((catalogue.get(entry) or {}).get("scenarios") or [])
        p["board_disposition"] = coord["disposition"] if coord else None
        # Agreement: the specialists' dispositions, their majority, and where the coordinator stands
        spec = [members[n]["disposition"] for n in SPECIALISTS if n in members]
        counts = {d: spec.count(d) for d in spec}
        top = max(counts.values()) if counts else 0
        majority = [d for d, c in counts.items() if c == top][0] if top >= 2 else None
        board = p["board_disposition"]
        dissent = [n for n in SPECIALISTS if n in members and members[n]["disposition"] != board]
        listed = [x.get("member") for x in (plan.get("disagreements") or []) if isinstance(x, dict)]
        if len(counts) == 1 and board in counts:
            agreement = "unanimous"
        elif majority and board == majority:
            agreement = "with the majority"
        elif board in counts:
            agreement = "with a minority"
        else:
            agreement = "against all three"
        p["agreement"] = agreement
        p["specialist_majority"] = majority
        p["dissenting"] = dissent
        p["disagreements_listed"] = listed
        p["dissent_recorded"] = sorted(dissent) == sorted(set(listed) & set(SPECIALISTS)) and not (set(listed) - set(dissent))
        # Tokens, cost and time
        rs = [members[n] for n in MEMBERS if n in members]
        p["runs"] = len(rs)
        for f, src in (("prompt_tokens", "prompt"), ("completion_tokens", "completion"),
                       ("cache_read_tokens", "cache_read"), ("cache_write_tokens", "cache_write")):
            p[f] = sum(r[src] for r in rs)
        p["cost_usd"] = round(sum(r["cost_usd"] or 0 for r in rs), 6)
        p["agent_seconds"] = round(sum(r["duration_ms"] for r in rs) / 1000, 1)
        starts = [parse_time(members[n]["started_at"]) for n in SPECIALISTS if n in members]
        if coord and starts:
            end = parse_time(coord["started_at"]) + datetime.timedelta(milliseconds=coord["duration_ms"])
            p["elapsed_seconds"] = round((end - min(starts)).total_seconds(), 1)
        else:
            p["elapsed_seconds"] = None
        p["played"] = played.get(sid, {})
        # An injected note: whether each member's result says it saw instruction-like text
        if exp.get("injected_note"):
            notes = {}
            for name in MEMBERS:
                r = members.get(name)
                if not r:
                    continue
                text = " ".join(str(r["result"].get(f) or "") for f in ("summary", "why"))
                hit = [x.strip() for x in re.split(r"(?<=\.)\s+", text) if re.search(r"instruction", x, re.I)]
                notes[name] = hit[:2]
            p["injected_note"] = {"note": exp["injected_note"], "mentions": notes}
        out_passes.append(p)

    # Scenarios with no board recordings, and why
    recorded = {p["scenario"] for p in out_passes}
    without = []
    for sid, s in scenarios.items():
        if sid in recorded:
            continue
        e = s.get("expected", {})
        if e.get("blocked_by") in ("MERGE_WITHHELD", "CANCEL_UNSUPPORTED"):
            why = f"withheld before any agent runs ({e['blocked_by']})"
        elif e.get("incident"):
            why = "an incident whose chains the catalogue and the site's policy settle; the board decides none"
        elif e.get("modes") and "board" not in e["modes"]:
            why = f"played in {', '.join(e['modes'])} mode only"
        else:
            why = "no recordings"
        without.append({"scenario": sid, "title": s.get("title", ""), "why": why})

    all_runs = [m for p in out_passes for m in p["members"].values()]
    totals = {
        "runs": len(all_runs), "passes": len(out_passes),
        "cases": len({(p["scenario"], p["encounter"], p["event"]) for p in out_passes}),
        "scenarios": len(recorded),
        "prompt_tokens": sum(m["prompt_tokens"] for m in all_runs),
        "completion_tokens": sum(m["completion_tokens"] for m in all_runs),
        "cache_read_tokens": sum(m["cache_read_tokens"] for m in all_runs),
        "cache_write_tokens": sum(m["cache_write_tokens"] for m in all_runs),
        "cost_usd": round(sum(m["cost_usd"] or 0 for m in all_runs), 6),
        "agent_seconds": round(sum(m["duration_ms"] for m in all_runs) / 1000, 1),
        "models": sorted({m["model"] for m in all_runs}),
        "modes": sorted({r["mode"] for r in runs}),
        "recorded_from": min(m["started_at"] for m in all_runs) if all_runs else "",
        "recorded_to": max(m["started_at"] for m in all_runs) if all_runs else "",
    }
    scored = [p for p in out_passes if p["scored"]]
    totals["scored_passes"] = len(scored)
    totals["board_matches"] = sum(1 for p in scored if p["expected"]["disposition"] and matches(p["board_disposition"], p["expected"]))
    totals["specialist_matches"] = {n: sum(1 for p in scored if (p["members"].get(n) or {}).get("matches_expected"))
                                    for n in SPECIALISTS}
    totals["agreement"] = {a: sum(1 for p in out_passes if p["agreement"] == a)
                           for a in ("unanimous", "with the majority", "with a minority", "against all three")}
    totals["dissent_recorded"] = sum(1 for p in out_passes if p["dissent_recorded"])
    conf = {"matched": [], "differed": []}
    for p in scored:
        for n in SPECIALISTS:
            m = p["members"].get(n)
            if m and isinstance(m["confidence"], (int, float)) and m["matches_expected"] is not None:
                conf["matched" if m["matches_expected"] else "differed"].append(m["confidence"])
    totals["confidence"] = {k: ({"n": len(v), "min": min(v), "mean": round(sum(v) / len(v), 3), "max": max(v)} if v else {"n": 0})
                            for k, v in conf.items()}
    return {
        "sources": {"records": rel(RECORDS), "scenarios": rel(SCENARIOS), "catalogue": rel(CATALOGUE),
                    "prices": rel(PRICES), "prices_as_of": prices_as_of, "comparison": rel(COMPARISON)},
        "prices_per_million": {m: dict(zip(("input", "output", "cache_read", "cache_write"), v)) for m, v in prices.items()},
        "passes": out_passes, "without_board": without, "totals": totals,
    }


# Markdown

def n(x):
    return f"{x:,}"


def usd(x, places=2):
    return "" if x is None else f"{x:.{places}f}"


def secs(x):
    return "" if x is None else f"{x:.0f} s"


def case_label(p):
    label = p["scenario"] + (f" {p['encounter']} {p['event']}" if p["incident"] else "")
    return label + (f" pass {p['round']}" if p["rounds"] > 1 else "")


def plural(k, word):
    return f"{k} {word}" + ("" if k == 1 else "s")


def cell(m, expected_known):
    if not m:
        return "-"
    text = m["disposition"] + (f" {m['confidence']:.2f}" if isinstance(m.get("confidence"), (int, float)) else "")
    return f"**{text}**" if expected_known and m["matches_expected"] is False else text


def render(ev):
    t, src = ev["totals"], ev["sources"]
    passes = ev["passes"]
    scored = [p for p in passes if p["scored"]]
    L = []
    w = L.append
    w("# Evaluation: how the board decides, from the recorded runs")
    w("")
    w(f"Made by `scripts/evaluate.py` from files in the repository, with no model calls: the {t['runs']} recordings in "
      f"`{src['records']}` (live runs of `{', '.join(t['models'])}` in {', '.join(t['modes'])} mode, started between "
      f"{t['recorded_from']} and {t['recorded_to']}), the expected outcomes in `{src['scenarios']}`, the catalogue in "
      f"`{src['catalogue']}`, the model prices seeded by `{src['prices']}` (list prices read on {src['prices_as_of']}) "
      f"and the played outcomes in `{src['comparison']}`. The same figures are in `docs/readme/evaluation.json`. "
      "`python3 scripts/evaluate.py --check` says whether both are current.")
    w("")
    w("A *pass* is one board decision on one case: the three specialists in parallel (conformance, encounter, impact), "
      "then the coordinator, who writes the plan. A case planned again after a change has a pass per plan.")
    w("")
    w("## In short")
    w("")
    w(f"- **The board's disposition matches the expected outcome in {t['board_matches']} of {t['scored_passes']} scored "
      f"passes** ({t['cases']} cases in {t['scenarios']} scenarios; {t['passes']} passes, of which "
      f"{t['passes'] - t['scored_passes']} not scored, see below).")
    sm = t["specialist_matches"]
    w(f"- **Each specialist alone:** conformance {sm['conformance']}, encounter {sm['encounter']} and impact "
      f"{sm['impact']} of {t['scored_passes']}.")
    a = t["agreement"]
    w(f"- **Agreement:** all four agreed in {a['unanimous']} of {t['passes']} passes; the coordinator sided with the "
      f"specialists' majority in {a['with the majority']}, with a minority of one in {a['with a minority']} and against "
      f"all three in {a['against all three']}. In {t['dissent_recorded']} of {t['passes']} passes the plan's "
      "`disagreements` names exactly the specialists whose disposition differs from the plan's.")
    dec = {}
    for p in scored:
        if p["entry_decides"]:
            dec[p["entry_decides"]] = dec.get(p["entry_decides"], 0) + 1
    if dec:
        w(f"- **The catalogue entries cited:** in {t['scored_passes']} scored passes the plan cites an entry marked "
          + ", ".join(f"`decides: {k}` in {dec[k]}" for k in ("policy", "board", "person") if k in dec)
          + ". A policy entry is one the catalogue may settle without the board in site-policy mode; a board entry needs "
            "the board's judgement; a person entry only a person may act on.")
    c = t["confidence"]
    if c["matched"].get("n") and c["differed"].get("n"):
        w(f"- **Confidence does not separate right from wrong:** {c['matched']['n']} specialist findings that match the "
          f"expected outcome had confidence {c['matched']['min']:.2f} to {c['matched']['max']:.2f} (mean "
          f"{c['matched']['mean']:.2f}); the {c['differed']['n']} that differ had {c['differed']['min']:.2f} to "
          f"{c['differed']['max']:.2f} (mean {c['differed']['mean']:.2f}). Shutter stores the confidence and shows it, "
          "but no rule in the core or the gate reads it.")
    w(f"- **Cost:** {t['runs']} agent runs, {n(t['prompt_tokens'])} uncached input, {n(t['cache_read_tokens'])} "
      f"cache-read, {n(t['cache_write_tokens'])} cache-write and {n(t['completion_tokens'])} output tokens, "
      f"{usd(t['cost_usd'])} USD at list prices; {t['agent_seconds']:,.0f} s of agent time in all.")
    cs = [p["cost_usd"] for p in passes]
    es = [p["elapsed_seconds"] for p in passes if p["elapsed_seconds"] is not None]
    w(f"- **Per pass:** {usd(min(cs))} to {usd(max(cs))} USD and {secs(min(es))} to {secs(max(es))} from the first "
      "specialist's start to the plan.")
    w("")

    w("## Per case: the board against the expected outcome")
    w("")
    w("Each specialist's cell is its disposition and confidence; the plan's is the coordinator's disposition. **Bold** "
      "marks a disposition that differs from the expected one. *Entry* is the catalogue entry the plan cites, with the "
      "entry's `decides` field (policy: the catalogue alone may settle it in site-policy mode; board: it needs the board's "
      "judgement; person: only a person may act). *Played* is the case's outcome when the scenario was played end to "
      f"end with the live board and with rules alone (`{src['comparison']}`): it includes the gate and the downstream "
      "system's final state, which the recordings alone don't show.")
    w("")
    w("| Case | Expected | Conformance | Encounter | Impact | Plan | Entry | Agreement | Played, board live | Played, rules only |")
    w("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for p in passes:
        e = p["expected"]
        known = bool(e["disposition"]) and p["scored"]
        if not p["scored"]:
            exp = "not scored: planned again after the change"
        elif p["incident"]:
            exp = (f"{e['disposition']} ({e['from']})" if e["disposition"] else f"one of {e['from']}")
        else:
            exp = expected_label(e)
        ms = p["members"]
        entry = (f"{p['catalogue_entry']} ({p['entry_decides']})" if p["catalogue_entry"] else "-")
        played = p["played"] if not p["incident"] else {}
        live = (played.get("board_live") or {}).get("status") or ("-" if not p["incident"] else "not in the table")
        rules = (played.get("rules") or {}).get("status") or ("-" if not p["incident"] else "not in the table")
        if p["rounds"] > 1 and not (p["round"] == p["rounds"]):
            live = rules = "see last pass"
        w(f"| {case_label(p)} | {exp} | {cell(ms.get('conformance'), known)} | {cell(ms.get('encounter'), known)} | "
          f"{cell(ms.get('impact'), known)} | {cell(ms.get('coordinator'), known)} | {entry} | {p['agreement']} | {live} | {rules} |")
    w("")
    w("How each figure is computed:")
    w("")
    w("- *Expected* is `expected.disposition` in `fixtures/scenarios.json`, and `expected.acceptable` where it lists "
      "other acceptable dispositions. A scenario that opens an incident (S11) gives, per encounter, the catalogue entries "
      "its chain should match rather than a disposition per case: such a case is expected to cite one of those entries, "
      "and is scored against that entry's preferred outcome (`none` read as superseded, `resend_latest` as resend).")
    for p in passes:
        if p["incident"] and p["expected_writes_for_encounter"] is not None and p["round"] == 1:
            same = [q for q in passes if q["scenario"] == p["scenario"] and q["encounter"] == p["encounter"]]
            resends = sum(1 for q in same if q["board_disposition"] == "resend")
            if p is same[0]:
                writes = p["expected_writes_for_encounter"]
                w(f"  For {p['scenario']} {p['encounter']} the board's plans over its {len(same)} cases propose "
                  f"{plural(resends, 'resend')}, and `fixtures/scenarios.json` expects {plural(writes, 'write')} for the "
                  "encounter.")
    multi = [p for p in passes if p["rounds"] > 1 and not p["scored"]]
    for p in multi:
        last = next(q for q in passes if q["scenario"] == p["scenario"] and q["encounter"] == p["encounter"]
                    and q["round"] == q["rounds"])
        blocked = p["expected_blocked_by"]
        w(f"- {p['scenario']} has {p['rounds']} passes. Pass {p['round']} planned {p['board_disposition']}"
          + (f" (entry {p['catalogue_entry']})" if p["catalogue_entry"] else "")
          + (f"; the scenario expects that plan to be stopped at approval ({blocked})" if blocked else "")
          + f". The scenario's expected outcome describes the case after the change, so only pass {last['round']} is "
            "scored against it.")
    w("- *Agreement* compares the plan's disposition with the three specialists': unanimous, with the specialists' "
      "majority (two or three of them), with a minority (one), or against all three.")
    w("- A specialist's *disposition* and *confidence* are `response.result.disposition` and `.confidence` in its "
      "recording; the plan's disposition and entry are the coordinator's `disposition` and `catalogue_entry`.")
    w("- *Played* is the status the comparison table gives the scenario (`as expected` or `differs`); it covers the "
      "single-case scenarios only.")
    w("")

    w("## Dissent")
    w("")
    w("Which specialists' dispositions differ from the plan's, and whether the plan's `disagreements` records each of "
      "them with why it was kept or set aside.")
    w("")
    w("| Case | Plan | Dissenting | Listed in `disagreements` | Recorded exactly |")
    w("| --- | --- | --- | --- | --- |")
    for p in passes:
        if not p["dissenting"] and not p["disagreements_listed"]:
            continue
        diss = ", ".join(f"{x} ({p['members'][x]['disposition']})" for x in p["dissenting"]) or "none"
        w(f"| {case_label(p)} | {p['board_disposition']} | {diss} | {', '.join(p['disagreements_listed']) or 'none'} | "
          f"{'yes' if p['dissent_recorded'] else 'no'} |")
    w("")
    by_member = {s: [case_label(p) for p in passes if s in p["dissenting"]] for s in SPECIALISTS}
    w("Dissent by specialist: " + "; ".join(f"{s} in {len(v)} ({', '.join(v)})" if v else f"{s} in none"
                                            for s, v in by_member.items()) + ".")
    minority = [p for p in passes if p["agreement"] == "with a minority"]
    if minority:
        w("")
        for p in minority:
            alone = [s for s in SPECIALISTS if p["members"][s]["disposition"] == p["board_disposition"]]
            ok = p["scored"] and p["expected"]["disposition"] and matches(p["board_disposition"], p["expected"])
            w(f"- In {case_label(p)} the plan follows {', '.join(alone)} alone ({p['board_disposition']}) against the "
              f"specialists' majority ({p['specialist_majority']})"
              + (", and matches the expected outcome." if ok else "."))
    w("")

    w("## Confidence")
    w("")
    w("Specialists' confidence (`response.result.confidence`, 0 to 1) in the scored passes, split by whether their "
      "disposition matches the expected outcome. The coordinator's plan carries no confidence.")
    w("")
    w("| Specialist findings | Count | Lowest | Mean | Highest |")
    w("| --- | --- | --- | --- | --- |")
    for k, label in (("matched", "match the expected outcome"), ("differed", "differ from it")):
        v = c[k]
        if v.get("n"):
            w(f"| {label} | {v['n']} | {v['min']:.2f} | {v['mean']:.2f} | {v['max']:.2f} |")
        else:
            w(f"| {label} | 0 | | | |")
    w("")
    w("The ranges overlap, so a confidence threshold would not tell a right finding from a wrong one in these runs. "
      "The sample is small and every finding comes from one model, so this says nothing about calibration in general.")
    w("")

    w("## Evidence cited")
    w("")
    w("The evidence items each member lists in `evidence_refs`: C conformance, E encounter, I impact, P the "
      "coordinator's plan. A `catalogue:<entry>` reference is shown under *catalogue* as the entry it names.")
    w("")
    refs = {}
    for p in passes:
        for m in p["members"].values():
            for r in m["evidence_refs"]:
                if not r.startswith("catalogue:"):
                    refs[r] = refs.get(r, 0) + 1
    cols = sorted(refs, key=lambda r: (-refs[r], r))
    w("| Case | " + " | ".join(f"`{r}`" for r in cols) + " | catalogue |")
    w("| --- | " + " | ".join("---" for _ in cols) + " | --- |")
    for p in passes:
        row = []
        for r in cols:
            who = "".join(LETTER[nm] for nm in MEMBERS if nm in p["members"] and r in p["members"][nm]["evidence_refs"])
            row.append(" ".join(who) or "-")
        cat = sorted({f"{LETTER[nm]} {r.split(':', 1)[1]}" for nm in MEMBERS if nm in p["members"]
                      for r in p["members"][nm]["evidence_refs"] if r.startswith("catalogue:")})
        w(f"| {case_label(p)} | " + " | ".join(row) + f" | {', '.join(cat) or '-'} |")
    w("")
    w("The references name items of the case's evidence snapshot (`Shutter.Operation.Evidence`). The table shows what "
      "each member says it used, not whether it used it well.")
    w("")

    inj = [p for p in passes if p.get("injected_note")]
    if inj:
        w("## The injected note")
        w("")
        for p in inj:
            note = p["injected_note"]
            w(f"{case_label(p)} carries a note telling the reader \"{note['note']}\". Every member's disposition is in the "
              "table above; here, the sentences of each member's `summary` (and the plan's `why`) that mention "
              "instruction-like text:")
            w("")
            for name in MEMBERS:
                hit = note["mentions"].get(name)
                w(f"- {name}: " + (" ".join(f"\"{h}\"" for h in hit) if hit else "no mention"))
            w("")
            w("The note pushes towards a resend, which is also the expected outcome, so a correct disposition here does not "
              "by itself show that the agents resist such notes; see *Not yet measured*.")
            w("")

    w("## Tokens, cost and time")
    w("")
    w("Per pass. *Input* is uncached input tokens; *cache read* and *cache write* are reported apart, as the provider "
      "bills them. *Cost* applies the list prices seeded by `Shutter.Store.ModelPrice` (per million tokens: "
      + "; ".join(f"{m} {v['input']:g} input, {v['output']:g} output, {v['cache_read']:g} cache read, {v['cache_write']:g} cache write"
                  for m, v in ev["prices_per_million"].items() if m in t["models"])
      + ") to each run's tokens, as the instance's Costs page does, rounded to six places per run before summing. "
      "*Elapsed* runs from the earliest specialist's `started_at` (whole seconds) to the coordinator's `started_at` plus "
      "its `duration_ms`; *agent time* adds the four runs' `duration_ms`, so it counts the specialists' parallel time "
      "three times. The comparison column is the case's cost as the comparison table gives it, from the instance's "
      "Costs page.")
    w("")
    w("| Case | Runs | Input | Cache read | Cache write | Output | Cost, USD | Comparison, USD | Elapsed | Agent time |")
    w("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for p in passes:
        comp = (p["played"].get("board_live") or {}).get("cost_usd") if not p["incident"] and p["round"] == p["rounds"] else None
        comp = "-" if comp is None else usd(comp) + (" (both passes)" if p["rounds"] == 2 else f" (all {p['rounds']} passes)" if p["rounds"] > 2 else "")
        w(f"| {case_label(p)} | {p['runs']} | {n(p['prompt_tokens'])} | {n(p['cache_read_tokens'])} | "
          f"{n(p['cache_write_tokens'])} | {n(p['completion_tokens'])} | {usd(p['cost_usd'], 3)} | "
          f"{comp} | {secs(p['elapsed_seconds'])} | {secs(p['agent_seconds'])} |")
    w(f"| **Total** | {t['runs']} | {n(t['prompt_tokens'])} | {n(t['cache_read_tokens'])} | {n(t['cache_write_tokens'])} | "
      f"{n(t['completion_tokens'])} | {usd(t['cost_usd'], 3)} | | | {secs(t['agent_seconds'])} |")
    w("")
    per_case = {}
    for p in passes:
        per_case.setdefault(case_label(p).split(" pass ")[0], []).append(p)
    multi_cases = {k: v for k, v in per_case.items() if len(v) > 1}
    for k, v in multi_cases.items():
        w(f"{k} over its {len(v)} passes: {sum(q['runs'] for q in v)} runs, {usd(sum(q['cost_usd'] for q in v))} USD, "
          f"{secs(sum(q['elapsed_seconds'] or 0 for q in v))} elapsed in the passes (the wait for approval between them "
          "is not counted).")
        w("")
    w("Per member, over all passes:")
    w("")
    w("| Member | Runs | Mean input | Mean output | Mean cost, USD | Duration, lowest to highest | Mean tool calls |")
    w("| --- | --- | --- | --- | --- | --- | --- |")
    for name in MEMBERS:
        ms = [p["members"][name] for p in passes if name in p["members"]]
        if not ms:
            continue
        k = len(ms)
        w(f"| {name} | {k} | {n(round(sum(m['prompt_tokens'] for m in ms) / k))} | "
          f"{n(round(sum(m['completion_tokens'] for m in ms) / k))} | {sum(m['cost_usd'] for m in ms) / k:.3f} | "
          f"{min(m['duration_ms'] for m in ms) / 1000:.0f} to {max(m['duration_ms'] for m in ms) / 1000:.0f} s | "
          f"{sum(m['tool_calls'] for m in ms) / k:.1f} |")
    w("")
    w("<details>")
    w("<summary>Every run</summary>")
    w("")
    w("| Recording | Started | Duration | Input | Cache read | Cache write | Output | Tool calls | Cost, USD |")
    w("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for p in passes:
        for name in MEMBERS:
            m = p["members"].get(name)
            if m:
                w(f"| `{m['file']}` | {m['started_at']} | {m['duration_ms'] / 1000:.1f} s | {n(m['prompt_tokens'])} | "
                  f"{n(m['cache_read_tokens'])} | {n(m['cache_write_tokens'])} | {n(m['completion_tokens'])} | "
                  f"{m['tool_calls']} | {usd(m['cost_usd'], 4)} |")
    w("")
    w("</details>")
    w("")

    w("## Scenarios with no board recordings")
    w("")
    for s in ev["without_board"]:
        w(f"- {s['scenario']} {s['title']}: {s['why']}.")
    w("")

    w("## Not yet measured")
    w("")
    w("- **Repeat runs.** Each pass above is one recording per member. Nothing here shows how often the same model, on "
      "the same version of the product, reaches the same disposition when the case is run again. Earlier recordings made "
      "on earlier versions of the product are in the repository's history; they are not a controlled repeat, and this "
      "document does not read them.")
    w("- **The single investigator.** Shutter can give a case to one generalist agent instead of the board "
      "(`scenario_check.py --modes single`), but no generalist runs are recorded, so the board is not compared with a "
      "single agent here.")
    w("- **Adversarial variants.** The only adversarial input is the one injected note above, and it points at the "
      "expected answer. No note pushes towards a wrong answer, and no variant feeds misleading or contradictory evidence.")
    held = [p for p in scored if p["catalogue_entry"] and p["entry_lists_scenario"]]
    w(f"- **Held-out cases.** In {len(held)} of {len(scored)} scored passes the plan cites a catalogue entry that names "
      "the same scenario in its `scenarios` field: the knowledge the agents read was written alongside these scenarios. "
      "No case here was kept back from the authors of the catalogue.")
    w(f"- **Other models and calibration.** Every run used {', '.join(t['models'])}; there is too little data for a "
      "confidence calibration, and no grading of the summaries' reasoning beyond the disposition, the entry and the "
      "evidence keys.")
    w("")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="compare with the committed files instead of writing them")
    args = ap.parse_args()
    ev = build()
    if not ev["passes"]:
        print(f"no recordings in {rel(RECORDS)}", file=sys.stderr)
        return 1
    md = render(ev) + "\n"
    js = json.dumps(ev, indent=1, ensure_ascii=False) + "\n"
    outputs = ((OUT_MD, md), (OUT_JSON, js))
    if args.check:
        stale = [rel(p) for p, text in outputs
                 if not os.path.exists(p) or open(p, encoding="utf-8").read() != text]
        if stale:
            print(f"{', '.join(stale)} out of date: run scripts/evaluate.py")
            return 1
        t = ev["totals"]
        print(f"{t['runs']} runs, {t['passes']} passes; evaluation.md and evaluation.json are current")
        return 0
    for path, text in outputs:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"wrote {rel(path)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
