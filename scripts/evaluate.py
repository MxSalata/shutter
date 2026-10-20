#!/usr/bin/env python3
"""Build docs/readme/evaluation.md and evaluation.json from the recorded live runs: how the board of specialists
decided each recorded case against the scenario's expected outcome, how far its members agreed, which evidence each
cited, and what the runs cost in tokens, money and time. No model calls and no IRIS: it reads files only.

    python3 scripts/evaluate.py [--check]

Inputs: the recordings (fixtures/records/*.json, one per board member and case, as check-records.py reads them, with
the evidence snapshot each run received in its transcript; files that are not a board member's are listed apart), the
expected outcomes (fixtures/scenarios.json), the catalogue (knowledge/catalogue/catalogue.json), the seeded model
prices (Shutter.Store.ModelPrice's Seed, read from its source) and the played outcomes in docs/readme/comparison.md.
--check builds both files in memory and compares them with the committed ones (exit 1 on a difference), like
build-catalogue.py --check. Standard library only.
"""
import argparse
import datetime
import decimal
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


def evidence_of(d):
    """The case's evidence snapshot as the run received it: the JSON inside the first <evidence-...> block of the
    transcript's messages, or None."""
    try:
        messages = json.loads(d.get("transcript") or "{}").get("messages") or []
    except ValueError:
        return None
    for msg in messages:
        text = msg.get("content")
        if not isinstance(text, str) or "<evidence-" not in text:
            continue
        start = text.find("{", text.find("<evidence-"))
        try:
            obj = json.JSONDecoder().raw_decode(text[start:])[0]
        except ValueError:
            return None
        return obj.get("evidence") if isinstance(obj.get("evidence"), dict) else obj
    return None


def load_runs(prices):
    """The board members' recordings, and the files not used here with the reason for each."""
    runs, others = [], []
    for path in sorted(glob.glob(os.path.join(RECORDS, "*.json"))):
        text = open(path, encoding="utf-8").read()
        d = json.loads(text)
        key = d.get("key", "")
        m = KEY_RE.match(key)
        if not m:
            why = ("a key in the older form without the encounter and event" if re.match(r"^scenario:S\d+\|", key)
                   else "a key that is not a scenario recording's")
            others.append({"file": os.path.basename(path), "key": key, "member": d.get("memberCode") or "", "why": why})
            continue
        if m["member"] not in MEMBERS:
            why = ("a generalist run (the single investigator), not a board member's" if m["member"] == "generalist"
                   else f"member {m['member']!r} is not on the board")
            others.append({"file": os.path.basename(path), "key": key, "member": m["member"], "why": why})
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
            "text": text, "evidence": evidence_of(d) or {},
        }
        r["cost_usd"] = cost(prices, r)
        runs.append(r)
    return runs, others


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


def latest_failed_event(keys, encounter):
    """The event of an encounter's latest failed operation by event time, from operation keys
    (...^<encounter>^<event>^<event time>); None when there are none or two share the latest time."""
    items = [k.split("^")[-2:] for k in keys if f"^{encounter}^" in k]
    if not items:
        return None
    last = max(t for _, t in items)
    at = [e for e, t in items if t == last]
    return at[0] if len(at) == 1 else None


def round_half_up(x, places=0):
    """Round once, half up, for the figures shown: Python's round() and format() round half to even."""
    q = decimal.Decimal(1).scaleb(-places)
    return float(decimal.Decimal(repr(x)).quantize(q, rounding=decimal.ROUND_HALF_UP))


def expected_label(expected):
    alts = [a for a in expected.get("acceptable", []) if a != expected["disposition"]]
    return expected["disposition"] + (f" (or {', '.join(alts)})" if alts else "")


def build():
    prices, prices_as_of = load_prices()
    runs, others = load_runs(prices)
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
            # The entry the catalogue's matcher found in the case's own evidence, not the one the plan cites
            found = sorted({x.get("id") for r in members.values()
                            for x in ((r["evidence"].get("catalogue") or {}).get("matches") or []) if isinstance(x, dict)})
            p["matcher_entries"] = found
            matched = [e for e in found if e in entries]
            if len(matched) == 1:
                entry = matched[0]
                outcome = (catalogue.get(entry) or {}).get("preferred", {}).get("outcome")
                want, why = OUTCOME_DISPOSITION.get(outcome), f"entry {entry}, matched in the case's evidence"
                if outcome == "resend_latest":
                    # Only the chain's latest failed item is resent; the earlier ones are superseded
                    latest = latest_failed_event(exp.get("failed_operation_keys", []), enc)
                    if latest is None:
                        want = None
                    elif event != latest:
                        want, why = "superseded", why + f", not the chain's latest ({latest})"
                    else:
                        why += ", the chain's latest"
                p["expected"] = {"disposition": want, "from": why}
            else:
                p["expected"] = {"disposition": None, "from": f"entries {', '.join(entries)}"}
            p["plan_cites_matched_entry"] = (len(matched) == 1 and plan.get("catalogue_entry") == matched[0])
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
        p["agent_ms"] = sum(r["duration_ms"] for r in rs)
        starts = [parse_time(members[n]["started_at"]) for n in SPECIALISTS if n in members]
        if coord and starts:
            end = parse_time(coord["started_at"]) + datetime.timedelta(milliseconds=coord["duration_ms"])
            p["elapsed_ms"] = (end - min(starts)) // datetime.timedelta(milliseconds=1)
        else:
            p["elapsed_ms"] = None
        p["played"] = played.get(sid, {})
        # An injected note: whether its text reached each member (anywhere in the recording: the evidence, the tool
        # results, the transcript), the flags the core put in its place, and the member's sentences about it
        if exp.get("injected_note"):
            seen = {}
            for name in MEMBERS:
                r = members.get(name)
                if not r:
                    continue
                flags = [{**{k: x.get(k) for k in ("segment", "position", "free_text_present", "instruction_like", "note")},
                          "text_sent": "text" in x}
                         for x in ((r["evidence"].get("message") or {}).get("notes") or []) if isinstance(x, dict)]
                text = " ".join(str(r["result"].get(f) or "") for f in ("summary", "why"))
                hit = [x.strip() for x in re.split(r"(?<=\.)\s+", text) if re.search(r"instruction", x, re.I)]
                seen[name] = {"text_in_recording": exp["injected_note"] in r["text"], "flags": flags, "mentions": hit[:2]}
            p["injected_note"] = {"note": exp["injected_note"], "members": seen}
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
        "files": len(runs) + len(others), "not_used": len(others),
        "generalist_runs": sum(1 for o in others if o["member"] == "generalist"),
        "runs": len(all_runs), "passes": len(out_passes),
        "cases": len({(p["scenario"], p["encounter"], p["event"]) for p in out_passes}),
        "scenarios": len(recorded),
        "prompt_tokens": sum(m["prompt_tokens"] for m in all_runs),
        "completion_tokens": sum(m["completion_tokens"] for m in all_runs),
        "cache_read_tokens": sum(m["cache_read_tokens"] for m in all_runs),
        "cache_write_tokens": sum(m["cache_write_tokens"] for m in all_runs),
        "cost_usd": round(sum(m["cost_usd"] or 0 for m in all_runs), 6),
        "agent_ms": sum(m["duration_ms"] for m in all_runs),
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
    # A specialist whose view differs from the case's outcome, and whether the plan's disagreements names it
    outweighed = [(p, n) for p in scored for n in SPECIALISTS if (p["members"].get(n) or {}).get("matches_expected") is False]
    totals["specialist_differs"] = len(outweighed)
    totals["specialist_differs_listed"] = sum(1 for p, n in outweighed if n in p["disagreements_listed"])
    incident = [p for p in scored if p["incident"]]
    totals["incident_passes"] = len(incident)
    totals["incident_plans_cite_matched_entry"] = sum(1 for p in incident if p.get("plan_cites_matched_entry"))
    # Per incident encounter: the resends the board's plans propose against the writes the scenario expects
    writes = {}
    for p in incident:
        w = writes.setdefault((p["scenario"], p["encounter"]), {"scenario": p["scenario"], "encounter": p["encounter"],
                                                                 "cases": 0, "resends": 0,
                                                                 "expected_writes": p["expected_writes_for_encounter"]})
        w["cases"] += 1
        w["resends"] += p["board_disposition"] == "resend"
    totals["incident_writes"] = list(writes.values())
    totals["agreement"] = {a: sum(1 for p in out_passes if p["agreement"] == a)
                           for a in ("unanimous", "with the majority", "with a minority", "against all three")}
    totals["dissent_recorded"] = sum(1 for p in out_passes if p["dissent_recorded"])
    conf = {"matched": [], "differed": []}
    for p in scored:
        for n in SPECIALISTS:
            m = p["members"].get(n)
            if m and isinstance(m["confidence"], (int, float)) and m["matches_expected"] is not None:
                conf["matched" if m["matches_expected"] else "differed"].append(m["confidence"])
    totals["confidence"] = {k: ({"n": len(v), "min": min(v), "mean": round(sum(v) / len(v), 6), "max": max(v)} if v else {"n": 0})
                            for k, v in conf.items()}
    return {
        "sources": {"records": rel(RECORDS), "scenarios": rel(SCENARIOS), "catalogue": rel(CATALOGUE),
                    "prices": rel(PRICES), "prices_as_of": prices_as_of, "comparison": rel(COMPARISON)},
        "prices_per_million": {m: dict(zip(("input", "output", "cache_read", "cache_write"), v)) for m, v in prices.items()},
        "passes": out_passes, "without_board": without, "not_used": others, "totals": totals,
    }


# Markdown

def n(x):
    return f"{x:,}"


def usd(x, places=2):
    return "" if x is None else f"{x:.{places}f}"


def secs(ms, places=0):
    """Milliseconds as seconds, rounded once and half up."""
    return "" if ms is None else f"{round_half_up(ms / 1000, places):,.{places}f} s"


def two(x):
    return f"{round_half_up(x, 2):.2f}"


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
    w(f"Made by `scripts/evaluate.py` from files in the repository, with no model calls: the {t['runs']} board members' "
      f"recordings in `{src['records']}`"
      + (f" ({t['not_used']} other {'file' if t['not_used'] == 1 else 'files'} there not used, see *Recordings not used*)"
         if t["not_used"] else "")
      + f" (live runs of `{', '.join(t['models'])}` in {', '.join(t['modes'])} mode, started between "
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
      f"{t['passes'] - t['scored_passes']} not scored, see below)."
      + (f" The {plural(t['incident_passes'], 'incident case')} are scored against the catalogue entry the matcher found "
         "in each case's own evidence, not the entry the plan cites; the plans cite that entry in "
         f"{t['incident_plans_cite_matched_entry']} of {t['incident_passes']}." if t["incident_passes"] else ""))
    sm = t["specialist_matches"]
    w("- **Each specialist's own view:** a specialist decides from its own view only (conformance: is the message "
      "acceptable; encounter: does the movement still hold; impact: can the write be made safely), so its disposition is "
      "what that view alone would decide, not a verdict on the case. It is the case's expected outcome for conformance "
      f"in {sm['conformance']}, encounter in {sm['encounter']} and impact in {sm['impact']} of {t['scored_passes']} "
      "scored passes."
      + (f" Where it is not ({plural(t['specialist_differs'], 'finding')}), the plan's `disagreements` names the "
         f"specialist and says why another view outweighed it in {t['specialist_differs_listed']}."
         if t["specialist_differs"] else ""))
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
        w(f"- **Confidence:** the {c['matched']['n']} specialist findings whose disposition is the case's outcome had "
          f"confidence {two(c['matched']['min'])} to {two(c['matched']['max'])} (mean {two(c['matched']['mean'])}); the "
          f"{c['differed']['n']} outweighed by another view had {two(c['differed']['min'])} to "
          f"{two(c['differed']['max'])} (mean {two(c['differed']['mean'])}). A confidence is the specialist's confidence "
          "in its own view's answer, not in the case's outcome. Shutter stores it and shows it, but no rule in the core or "
          "the gate reads it.")
    w(f"- **Cost:** {t['runs']} agent runs, {n(t['prompt_tokens'])} uncached input, {n(t['cache_read_tokens'])} "
      f"cache-read, {n(t['cache_write_tokens'])} cache-write and {n(t['completion_tokens'])} output tokens, "
      f"{usd(t['cost_usd'])} USD at list prices; {secs(t['agent_ms'])} of agent time in all.")
    cs = [p["cost_usd"] for p in passes]
    es = [p["elapsed_ms"] for p in passes if p["elapsed_ms"] is not None]
    w(f"- **Per pass:** {usd(min(cs))} to {usd(max(cs))} USD and {secs(min(es))} to {secs(max(es))} from the first "
      "specialist's start to the plan.")
    w("")

    w("## Per case: the board against the expected outcome")
    w("")
    w("Each specialist's cell is its disposition and confidence; the plan's is the coordinator's disposition. **Bold** "
      "marks a disposition that differs from the expected one: for a specialist, its own view's answer where the plan "
      "followed another view. *Entry* is the catalogue entry the plan cites, with the "
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
      "its chain should match rather than a disposition per case. Such a case is scored against the entry the "
      "catalogue's matcher found in the case's own evidence snapshot (`catalogue.matches`, among the scenario's entries "
      "for the encounter), not the entry the plan cites, and against that entry's preferred outcome: `none` is read as "
      "superseded, and `resend_latest` as resend for the chain's latest failed item by event time "
      "(`expected.failed_operation_keys`) and superseded for the earlier ones.")
    for x in t["incident_writes"]:
        same = [q for q in scored if q["incident"] and q["scenario"] == x["scenario"] and q["encounter"] == x["encounter"]]
        cite = sum(1 for q in same if q.get("plan_cites_matched_entry"))
        wr = x["expected_writes"]
        w(f"  For {x['scenario']} {x['encounter']} the plans cite the matched entry in {cite} of {x['cases']} cases and "
          f"propose {plural(x['resends'], 'resend')} in all; `fixtures/scenarios.json` expects "
          + (f"{plural(wr, 'write')} for the encounter, "
             + ("which the plans match." if wr == x["resends"] else "which the plans do not match.")
             if wr is not None else "no number of writes for the encounter."))
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
      "disposition is the case's expected outcome or was outweighed by another view. The coordinator's plan carries no "
      "confidence.")
    w("")
    w("| Specialist findings | Count | Lowest | Mean | Highest |")
    w("| --- | --- | --- | --- | --- |")
    for k, label in (("matched", "the case's outcome"), ("differed", "outweighed by another view")):
        v = c[k]
        if v.get("n"):
            w(f"| {label} | {v['n']} | {two(v['min'])} | {two(v['mean'])} | {two(v['max'])} |")
        else:
            w(f"| {label} | 0 | | | |")
    w("")
    w("Each specialist is told to decide from its own view only, and its confidence is in that view's answer, not in the "
      "case's outcome. An outweighed finding is not therefore a wrong one: conformance, for example, is told to resend a "
      "message that is valid, and the plan then follows a view that sees why the case should not be resent. So this "
      "split is not an error rate, and the figures say nothing about calibration: the sample is small and every finding "
      "comes from one model.")
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
            ms = note["members"]
            reached = [nm for nm in MEMBERS if nm in ms and ms[nm]["text_in_recording"]]
            flagged = [nm for nm in MEMBERS if nm in ms
                       and any(f.get("free_text_present") and f.get("instruction_like") for f in ms[nm]["flags"])]
            where = sorted({f"{f.get('segment')}-{f.get('position')}" for nm in MEMBERS if nm in ms for f in ms[nm]["flags"]})
            w(f"{case_label(p)}'s message carries a free-text note written as an instruction to the reader "
              "(`expected.injected_note` in `fixtures/scenarios.json`).")
            w("")
            withheld = all(not f["text_sent"] for nm in ms for f in ms[nm]["flags"])
            if reached:
                w(f"- **The text reached {', '.join(reached)}:** it appears in {'its' if len(reached) == 1 else 'their'} "
                  "recordings.")
            else:
                w(f"- **The text reached no agent:** it appears in none of the {len(ms)} recordings (evidence, tool "
                  "results or transcript)."
                  + (" The evidence carries flags with no text: with the site's free-text switch off, the core keeps the "
                     "text in IRIS and sends the flags in its place (`Shutter.Util.ModelView`, `FlagNotes`)."
                     if withheld else ""))
            if flagged:
                w(f"- **The flags:** the evidence's {', '.join(where)} note says `free_text_present` and "
                  f"`instruction_like` for {'all four members' if len(flagged) == len(MEMBERS) else ', '.join(flagged)}. "
                  "The core sets `instruction_like` (`InstructionLike`), not the agents.")
            w("")
            w("The sentences of each member's `summary` (and the plan's `why`) that mention it:")
            w("")
            for name in MEMBERS:
                hit = (ms.get(name) or {}).get("mentions")
                w(f"- {name}: " + (" ".join(f"\"{h}\"" for h in hit) if hit else "no mention"))
            w("")
            if not reached:
                w("So these runs show only that the agents notice the core's flag, which the sentences above restate. They "
                  "do not test whether the agents would resist the instruction itself, which they never read; and the "
                  "note pushes towards a resend, which is also the expected outcome. See *Not yet measured*.")
            else:
                w("The note pushes towards a resend, which is also the expected outcome, so a correct disposition here does "
                  "not by itself show that the agents resist such notes; see *Not yet measured*.")
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
      "three times. Times are added in milliseconds and rounded once, half up, for display. The comparison column is the case's cost as the comparison table gives it, from the instance's "
      "Costs page.")
    w("")
    w("| Case | Runs | Input | Cache read | Cache write | Output | Cost, USD | Comparison, USD | Elapsed | Agent time |")
    w("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for p in passes:
        comp = (p["played"].get("board_live") or {}).get("cost_usd") if not p["incident"] and p["round"] == p["rounds"] else None
        comp = "-" if comp is None else usd(comp) + (" (both passes)" if p["rounds"] == 2 else f" (all {p['rounds']} passes)" if p["rounds"] > 2 else "")
        w(f"| {case_label(p)} | {p['runs']} | {n(p['prompt_tokens'])} | {n(p['cache_read_tokens'])} | "
          f"{n(p['cache_write_tokens'])} | {n(p['completion_tokens'])} | {usd(p['cost_usd'], 3)} | "
          f"{comp} | {secs(p['elapsed_ms'])} | {secs(p['agent_ms'])} |")
    w(f"| **Total** | {t['runs']} | {n(t['prompt_tokens'])} | {n(t['cache_read_tokens'])} | {n(t['cache_write_tokens'])} | "
      f"{n(t['completion_tokens'])} | {usd(t['cost_usd'], 3)} | | | {secs(t['agent_ms'])} |")
    w("")
    per_case = {}
    for p in passes:
        per_case.setdefault(case_label(p).split(" pass ")[0], []).append(p)
    multi_cases = {k: v for k, v in per_case.items() if len(v) > 1}
    for k, v in multi_cases.items():
        w(f"{k} over its {len(v)} passes: {sum(q['runs'] for q in v)} runs, {usd(sum(q['cost_usd'] for q in v))} USD, "
          f"{secs(sum(q['elapsed_ms'] or 0 for q in v))} elapsed in the passes (the wait for approval between them "
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
          f"{secs(min(m['duration_ms'] for m in ms))[:-2]} to {secs(max(m['duration_ms'] for m in ms))} | "
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
                w(f"| `{m['file']}` | {m['started_at']} | {secs(m['duration_ms'], 1)} | {n(m['prompt_tokens'])} | "
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

    if ev["not_used"]:
        w("## Recordings not used")
        w("")
        w(f"{plural(t['not_used'], 'file')} in `{src['records']}` {'is' if t['not_used'] == 1 else 'are'} not read "
          "into the figures above:")
        w("")
        for o in ev["not_used"]:
            w(f"- `{o['file']}`: {o['why']}.")
        w("")

    w("## Not yet measured")
    w("")
    w("- **Repeat runs.** Each pass above is one recording per member. Nothing here shows how often the same model, on "
      "the same version of the product, reaches the same disposition when the case is run again. Earlier recordings made "
      "on earlier versions of the product are in the repository's history; they are not a controlled repeat, and this "
      "document does not read them.")
    if t["generalist_runs"]:
        w("- **The single investigator.** Shutter can give a case to one generalist agent instead of the board "
          f"(`scenario_check.py --modes single`). {plural(t['generalist_runs'], 'generalist recording')} "
          f"{'is' if t['generalist_runs'] == 1 else 'are'} in `{src['records']}` (see *Recordings not used*), but this "
          f"document does not yet compare {'it' if t['generalist_runs'] == 1 else 'them'} with the board.")
    else:
        w("- **The single investigator.** Shutter can give a case to one generalist agent instead of the board "
          f"(`scenario_check.py --modes single`), but no generalist runs are in `{src['records']}`, so the board is not "
          "compared with a single agent here.")
    reached_any = any(m["text_in_recording"] for p in inj for m in p["injected_note"]["members"].values())
    if inj and not reached_any:
        w("- **Adversarial variants.** No adversarial text reached any agent in these recordings: the one injected note "
          "stays in IRIS and the agents see only its flags, so what is shown is that they notice the flag, not that they "
          "resist an instruction. Earlier recordings in the repository's history were made with the note's text sent; "
          "this document does not read them. No note pushes towards a wrong answer, and no variant feeds misleading or "
          "contradictory evidence.")
    else:
        w("- **Adversarial variants.** The only adversarial input is the injected note above, and it points at the "
          "expected answer. No note pushes towards a wrong answer, and no variant feeds misleading or contradictory "
          "evidence.")
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
    for o in ev["not_used"]:
        print(f"not used: {rel(RECORDS)}/{o['file']}: {o['why']}", file=sys.stderr)
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
