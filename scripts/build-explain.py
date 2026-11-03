#!/usr/bin/env python3
"""Build section SPW-5 of knowledge/explain/shutter-in-plain-words.md (the gate's checks, by reason code) from
knowledge/block-reasons.json: one line per reason, in the file's order, as "SPW-5.n. **CODE: title.** text Next:
next_action". The Explain agent searches the explain collection for the plain meaning of a gate check, and the
collection indexes only Markdown, so every reason the gate can give must be written here as block-reasons.json gives it.

    python3 scripts/build-explain.py [--reasons knowledge/block-reasons.json] [--explain knowledge/explain/shutter-in-plain-words.md] [--check]

The front matter, the sections before SPW-5 and SPW-5's own heading and introduction are kept as they are; everything
after the introduction is rewritten. --check only compares the file with what it would write (exit 1 on a difference),
for CI; tests/knowledge_check.py checks the same thing code by code and says which differs. When the output changes,
bump the version in the front matter and the body line that repeats it by hand, and rebuild the knowledge library
(Shutter.Knowledge.Library.BuildAll, which the production's start does when the folder's files changed). Standard
library only.
"""
import argparse
import json
import re
import sys

HEADING = re.compile(r"^## SPW-5 ", re.MULTILINE)


def reason_line(n, reason):
    return f"SPW-5.{n}. **{reason['code']}: {reason['title']}.** {reason['text']} Next: {reason['next_action']}"


def build(explain_text, reasons):
    """The explain file's text with SPW-5's lines rebuilt from the reasons."""
    m = HEADING.search(explain_text)
    if not m:
        raise ValueError("no '## SPW-5' heading in the explain file")
    heading_end = explain_text.index("\n", m.start()) + 1
    # The introduction is the paragraph after the heading, up to its blank line
    intro_end = explain_text.index("\n\n", heading_end) + 2
    head = explain_text[:intro_end]
    lines = [reason_line(n, r) for n, r in enumerate(reasons, 1)]
    return head + "\n\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--reasons", default="knowledge/block-reasons.json")
    ap.add_argument("--explain", default="knowledge/explain/shutter-in-plain-words.md")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    with open(args.reasons, encoding="utf-8") as f:
        reasons = json.load(f)["reasons"]
    with open(args.explain, encoding="utf-8") as f:
        current = f.read()
    try:
        text = build(current, reasons)
    except ValueError as e:
        print(f"{args.explain}: {e}")
        return 1
    if args.check:
        if current != text:
            print(f"{args.explain} is out of date: run scripts/build-explain.py")
            return 1
        print(f"{len(reasons)} reasons fine; SPW-5 is current")
        return 0
    if current == text:
        print(f"{args.explain} unchanged: {len(reasons)} reasons")
        return 0
    with open(args.explain, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"wrote {args.explain}: {len(reasons)} reasons")
    return 0


if __name__ == "__main__":
    sys.exit(main())
