#!/usr/bin/env python3
"""Copy the FHIR conformance file into the classes that carry it, or check that the copies are current.

    python3 tests/conformance/embed.py [--check]

The unit runner on a stock-install container cannot read the repository, so Shutter.Test.FHIRFacadeConformance carries
the exchanges in its XData Cases block, one exchange to a line. Shutter.Store.FHIRProof carries what a proof document
must name to be imported: the file's name, the SHA-256 of its bytes and the number of exchanges for each target, in its
four KIT parameters. Without --check both are rewritten from tests/conformance/fhir-facade-v1.json; with it, nothing is
written and the exit status is 1 when either differs. Standard library only.
"""
import argparse
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tests/conformance/fhir-facade-v1.json"
TARGET = ROOT / "tests/unit/Shutter/Test/FHIRFacadeConformance.cls"
PROOF = ROOT / "src/Shutter/Store/FHIRProof.cls"
OPEN = "XData Cases [ MimeType = application/json ]\n{\n"
PARAMETER = re.compile(r"^Parameter (KITNAME|KITSHA256|KITFACADE|KITIRIS) = (.*);$", re.MULTILINE)


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


def parameters(raw, doc):
    """The four KIT parameters of Shutter.Store.FHIRProof, each as the text after its equals sign."""
    count = {t: sum(1 for x in doc["exchanges"] if t in x["targets"]) for t in ("facade", "iris")}
    return {"KITNAME": '"%s"' % SOURCE.name, "KITSHA256": '"%s"' % hashlib.sha256(raw).hexdigest(),
            "KITFACADE": str(count["facade"]), "KITIRIS": str(count["iris"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    raw = SOURCE.read_bytes()
    doc = json.loads(raw.decode("utf-8"))
    text = TARGET.read_text(encoding="utf-8")
    before, current, after = split(text)
    want = parameters(raw, doc)
    proof = PROOF.read_text(encoding="utf-8")
    found = PARAMETER.findall(proof)
    if args.check:
        try:
            same = json.loads(current) == doc
        except ValueError:
            same = False
        print("XData Cases is current" if same else "XData Cases differs from " + str(SOURCE.relative_to(ROOT)))
        kit = sorted(found) == sorted(want.items())
        print("The KIT parameters of %s %s" % (PROOF.relative_to(ROOT), "are current" if kit else "differ from " + str(SOURCE.relative_to(ROOT))))
        return 0 if same and kit else 1
    if sorted(name for name, _ in found) != sorted(want):
        print("%s does not have each of the four KIT parameters once" % PROOF.relative_to(ROOT))
        return 1
    TARGET.write_text(before + block(doc) + after, encoding="utf-8")
    print("wrote %d exchanges into %s" % (len(doc["exchanges"]), TARGET.relative_to(ROOT)))
    PROOF.write_text(PARAMETER.sub(lambda m: "Parameter %s = %s;" % (m.group(1), want[m.group(1)]), proof), encoding="utf-8")
    print("wrote the kit's digest and counts into %s" % PROOF.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
