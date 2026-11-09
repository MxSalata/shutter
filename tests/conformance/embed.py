#!/usr/bin/env python3
"""Copy the FHIR conformance file into the unit test that runs it in process, or check that the copy is current.

    python3 tests/conformance/embed.py [--check]

The unit runner on a stock-install container cannot read the repository, so Shutter.Test.FHIRFacadeConformance carries
the exchanges in its XData Cases block, one exchange to a line. Without --check the block is rewritten from
tests/conformance/fhir-facade-v1.json; with it, nothing is written and the exit status is 1 when the two differ.
Standard library only.
"""
import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tests/conformance/fhir-facade-v1.json"
TARGET = ROOT / "tests/unit/Shutter/Test/FHIRFacadeConformance.cls"
OPEN = "XData Cases [ MimeType = application/json ]\n{\n"


def block(doc):
    """The XData body: the document's other members on the first line, then one exchange per line."""
    head = {k: v for k, v in doc.items() if k != "exchanges"}
    lines = [json.dumps(head, separators=(",", ":"), ensure_ascii=True)[:-1] + ',"exchanges":[']
    for i, x in enumerate(doc["exchanges"]):
        lines.append(json.dumps(x, separators=(",", ":"), ensure_ascii=True) + ("," if i < len(doc["exchanges"]) - 1 else ""))
    lines.append("]}")
    return "\n".join(lines) + "\n"


def split(text):
    start = text.index(OPEN) + len(OPEN)
    end = text.index("\n}\n", start - 1)
    return text[:start], text[start:end + 1], text[end + 1:]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    doc = json.loads(SOURCE.read_text(encoding="utf-8"))
    text = TARGET.read_text(encoding="utf-8")
    before, current, after = split(text)
    if args.check:
        try:
            same = json.loads(current) == doc
        except ValueError:
            same = False
        print("XData Cases is current" if same else "XData Cases differs from " + str(SOURCE.relative_to(ROOT)))
        return 0 if same else 1
    TARGET.write_text(before + block(doc) + after, encoding="utf-8")
    print("wrote %d exchanges into %s" % (len(doc["exchanges"]), TARGET.relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
