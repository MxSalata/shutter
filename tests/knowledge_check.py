#!/usr/bin/env python3
"""Checks that every reason code the gate can give (knowledge/block-reasons.json) is explained in plain words in the
explain collection (knowledge/explain/shutter-in-plain-words.md, section SPW-5), with the reason's own title, text and
next action, in the reasons' order and numbered SPW-5.1 onwards. The Explain agent searches that collection for the
plain meaning of a gate check, and the collection indexes only Markdown, so a code missing here, or explained with
older words, is one the agent cannot explain as the gate decides it.

    python3 tests/knowledge_check.py [--reasons knowledge/block-reasons.json] [--explain knowledge/explain/shutter-in-plain-words.md]
    python3 tests/knowledge_check.py --self-test

Each SPW-5 line is "SPW-5.n. **CODE: title.** text Next: next_action", as scripts/build-explain.py writes it. Prints
each code that is missing, whose line differs from the reason (with both texts), that the explain file has and the
reasons do not, or that is out of order or misnumbered, and exits 1 when there is any. --self-test runs the check over
synthetic inputs instead. Standard library only.
"""
import argparse
import json
import re
import sys

LINE = re.compile(r"^SPW-5\.(\d+)\. \*\*([A-Z_]+): (.*)$", re.MULTILINE)


def expected_line(reason):
    return f"{reason['title']}.** {reason['text']} Next: {reason['next_action']}"


def problems(reasons, explain_text):
    """What SPW-5 of explain_text gets wrong about reasons: one line each, none when it is right."""
    out = []
    found = [(int(n), code, rest) for n, code, rest in LINE.findall(explain_text)]
    by_code = {}
    for n, code, rest in found:
        if code in by_code:
            out.append(f"{code}: explained twice")
            continue
        by_code[code] = (n, rest)
    codes = [r["code"] for r in reasons]
    for i, reason in enumerate(reasons, 1):
        code = reason["code"]
        if code not in by_code:
            out.append(f"{code}: missing from the explain file")
            continue
        n, rest = by_code[code]
        want = expected_line(reason)
        if rest != want:
            out.append(f"{code}: text differs\n  explain: {rest}\n  reasons: {want}")
        if n != i:
            out.append(f"{code}: numbered SPW-5.{n}, expected SPW-5.{i} (the reasons' order)")
    for n, code, rest in found:
        if code not in codes:
            out.append(f"{code}: explained, but not a reason in block-reasons.json")
    return out


def self_test():
    reasons = [
        {"code": "A_CODE", "title": "The first", "text": "What it means.", "next_action": "Do this."},
        {"code": "B_CODE", "title": "The second", "text": "What else.", "next_action": "Do that."},
    ]
    good = "## SPW-5 Heading\n\nIntro.\n\nSPW-5.1. **A_CODE: The first.** What it means. Next: Do this.\n\nSPW-5.2. **B_CODE: The second.** What else. Next: Do that.\n"
    cases = [
        (good, []),
        (good.replace("\n\nSPW-5.2. **B_CODE: The second.** What else. Next: Do that.", ""), ["B_CODE: missing"]),
        (good.replace("What it means.", "What it meant."), ["A_CODE: text differs"]),
        (good.replace("SPW-5.2. **B_CODE", "SPW-5.3. **B_CODE"), ["B_CODE: numbered SPW-5.3"]),
        (good + "\nSPW-5.3. **C_CODE: A third.** Gone. Next: Nothing.\n", ["C_CODE: explained, but not a reason"]),
        (good + "\nSPW-5.3. **A_CODE: The first.** What it means. Next: Do this.\n", ["A_CODE: explained twice"]),
    ]
    failed = 0
    for text, want in cases:
        got = problems(reasons, text)
        if len(got) != len(want) or any(not g.startswith(w) for g, w in zip(got, want)):
            failed += 1
            print(f"self-test: expected {want!r}, got {got!r}")
    print(f"self-test: {len(cases)} cases, {failed} failed")
    return 1 if failed else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--reasons", default="knowledge/block-reasons.json")
    ap.add_argument("--explain", default="knowledge/explain/shutter-in-plain-words.md")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    with open(args.reasons, encoding="utf-8") as f:
        reasons = json.load(f)["reasons"]
    with open(args.explain, encoding="utf-8") as f:
        explain_text = f.read()
    found = problems(reasons, explain_text)
    for p in found:
        print("-", p)
    if found:
        print(f"{len(reasons)} reasons, {len(found)} problem(s)")
        return 1
    print(f"{len(reasons)} reasons, each explained as block-reasons.json gives it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
