#!/usr/bin/env python3
"""Build knowledge/catalogue/catalogue.json from the entries' Markdown (knowledge/catalogue/E*.md): the front matter
(CONTRACTS 6.2) checked against the condition vocabulary (6.1), plus the prose. The core seeds Shutter.Catalogue.Entry
from the JSON at install; the board's knowledge base indexes the Markdown.

    python3 scripts/build-catalogue.py [knowledge/catalogue] [--check]

--check only validates and compares with the committed JSON (exit 1 on a problem or a difference), for CI.
The front matter is a YAML subset: "key: value", "key: [a, b]", nested maps by two-space indentation, and lists of
maps as "- key: value" items; strings may be quoted. Standard library only.
"""
import argparse
import glob
import json
import os
import re
import sys

CONDITIONS = {
    "event": {"admit", "transfer", "discharge", "update", "merge", "cancel", "other"},
    "delivery": {"failed", "rejected", "uncertain", "unmappable", "withheld", "unreadable"},
    "receiver_answer": {"unavailable", "timeout", "duplicate", "version_conflict", "refused", "none"},
    "receipt": {"present", "absent", "unreadable", "none"},
    "later_applied": {"none", "transfer", "discharge", "update", "admit", "cancelled", "merge"},
    "later_delivery": {"applied", "sent", "none"},
    "event_time": {"plausible", "before_admission", "future", "far_from_recorded", "clock_change", "later_event_future"},
    "encounter_state": {"admitted", "discharged", "not_found", "unknown"},
    "transition": {"allowed", "invalid", "unknown"},
    "patient_match": {"yes", "no", "unknown"},
    "simultaneous_sources": {"yes", "no"},
    "conditional_writes": {"yes", "no", "unknown"},
    "free_text": {"yes", "no"},
    "chain": {"single", "ordered", "interleaved"},
    "receiver_category": {"current_state", "history_of_record", "orders_results"},
    "bed_conflict": {"none", "occupant_leaving", "occupant_left", "occupant_staying", "unknown"},
    "death_recorded": {"no", "yes", "cleared"},
}
OUTCOMES = {"resend", "resend_chain", "resend_latest", "reconcile", "none", "escalate", "resend_unconditional", "correct_history", "resend_after_occupant"}
DECIDES = {"policy", "board", "person"}
GATE_CHECKS = {"identity", "conformance", "intent", "ordering", "state_transition", "effect", "authorization", "concurrency", "evidence", "capability", "catalogue"}


def scalar(text):
    t = text.strip()
    if t.startswith("[") and t.endswith("]"):
        inner = t[1:-1].strip()
        return [scalar(x) for x in split_top(inner)] if inner else []
    if (t.startswith('"') and t.endswith('"')) or (t.startswith("'") and t.endswith("'")):
        return t[1:-1]
    if t in ("true", "yes"):
        return True if t == "true" else "yes"
    if t in ("false", "no"):
        return False if t == "false" else "no"
    if re.fullmatch(r"-?\d+", t):
        return int(t)
    return t


def split_top(text):
    parts, depth, cur = [], 0, ""
    for ch in text:
        if ch in "[{":
            depth += 1
        elif ch in "]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts]


def parse_block(lines, indent):
    """Parse lines at a given indentation into a dict or a list; returns (value, next_index)."""
    result = None
    i = 0
    while i < len(lines):
        raw = lines[i]
        if not raw.strip():
            i += 1
            continue
        ind = len(raw) - len(raw.lstrip(" "))
        if ind < indent:
            break
        if ind > indent:
            raise ValueError(f"unexpected indentation at: {raw!r}")
        line = raw.strip()
        if line.startswith("- "):
            if result is None:
                result = []
            if not isinstance(result, list):
                raise ValueError(f"list item inside a map at: {raw!r}")
            item_line = line[2:]
            # a list of maps: "- key: value" then deeper keys at indent+2
            sub = [(" " * (indent + 2)) + item_line] + lines[i + 1:]
            value, used = parse_block(sub, indent + 2)
            result.append(value)
            i += used  # used counts the synthetic first line too
            continue
        if ":" not in line:
            raise ValueError(f"not a key: value line: {raw!r}")
        key, _, rest = line.partition(":")
        key = key.strip()
        if result is None:
            result = {}
        if not isinstance(result, dict):
            raise ValueError(f"map key inside a list at: {raw!r}")
        if rest.strip():
            result[key] = scalar(rest)
            i += 1
        else:
            value, used = parse_block(lines[i + 1:], indent + 2)
            result[key] = value if value is not None else {}
            i += 1 + used
    return result, i


def parse_front_matter(text):
    if not text.startswith("---"):
        raise ValueError("no front matter")
    end = text.find("\n---", 3)
    if end < 0:
        raise ValueError("front matter not closed")
    fm_text = text[3:end].strip("\n")
    prose = text[end + 4:].lstrip("\n")
    value, _ = parse_block(fm_text.split("\n"), 0)
    return value or {}, prose


def check_entry(e, problems):
    eid = e.get("id", "?")
    for k in ("id", "version", "title", "pattern", "decides", "preferred"):
        if k not in e:
            problems.append(f"{eid}: missing {k}")
    if e.get("decides") not in DECIDES:
        problems.append(f"{eid}: decides must be policy, board or person")
    pattern = e.get("pattern") or {}
    if not isinstance(pattern, dict) or not pattern:
        problems.append(f"{eid}: pattern must be a non-empty map")
    else:
        for cond, allowed in pattern.items():
            if cond not in CONDITIONS:
                problems.append(f"{eid}: unknown condition {cond}")
                continue
            values = allowed if isinstance(allowed, list) else [allowed]
            for v in values:
                if str(v) not in CONDITIONS[cond]:
                    problems.append(f"{eid}: {cond} cannot be {v!r} (allowed: {', '.join(sorted(CONDITIONS[cond]))})")
    pref = e.get("preferred") or {}
    if pref.get("outcome") not in OUTCOMES:
        problems.append(f"{eid}: preferred.outcome must be one of {', '.join(sorted(OUTCOMES))}")
    if not pref.get("why"):
        problems.append(f"{eid}: preferred.why is required")
    for n, alt in enumerate(e.get("alternatives") or [], 1):
        if alt.get("outcome") not in OUTCOMES:
            problems.append(f"{eid}: alternative {n} outcome must be one of {', '.join(sorted(OUTCOMES))}")
        if not alt.get("when"):
            problems.append(f"{eid}: alternative {n} needs when")
    for c in e.get("checks") or []:
        if c not in GATE_CHECKS:
            problems.append(f"{eid}: unknown gate check {c}")
    if e.get("decides") == "policy" and pref.get("outcome") in ("resend_unconditional", "correct_history"):
        problems.append(f"{eid}: {pref.get('outcome')} can never be decided by policy")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("directory", nargs="?", default="knowledge/catalogue")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    files = sorted(glob.glob(os.path.join(args.directory, "E*.md")), key=lambda f: int(re.search(r"E(\d+)", os.path.basename(f)).group(1)))
    if not files:
        print(f"no entries in {args.directory}", file=sys.stderr)
        return 1
    entries, problems = [], []
    seen = set()
    for f in files:
        try:
            fm, prose = parse_front_matter(open(f, encoding="utf-8").read())
        except ValueError as e:
            problems.append(f"{os.path.basename(f)}: {e}")
            continue
        fm["prose"] = prose.strip()
        fm["source"] = os.path.basename(f)
        if fm.get("id") in seen:
            problems.append(f"{fm.get('id')}: duplicate id")
        seen.add(fm.get("id"))
        check_entry(fm, problems)
        entries.append(fm)
    out_path = os.path.join(args.directory, "catalogue.json")
    text = json.dumps(entries, indent=1, ensure_ascii=False) + "\n"
    for p in problems:
        print("-", p)
    if problems:
        print(f"{len(entries)} entries, {len(problems)} problem(s)")
        return 1
    if args.check:
        current = open(out_path, encoding="utf-8").read() if os.path.exists(out_path) else ""
        if current != text:
            print(f"{out_path} is out of date: run scripts/build-catalogue.py")
            return 1
        print(f"{len(entries)} entries fine; catalogue.json is current")
        return 0
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"wrote {out_path}: {len(entries)} entries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
