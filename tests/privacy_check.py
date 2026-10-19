#!/usr/bin/env python3
"""Checks that nothing personal from the HL7 fixtures reaches what the agents saw: the recorded runs' transcripts,
tool calls and responses (and, with --demo, the names, dates of birth and notes in the web demo's recorded answers).

    python3 tests/privacy_check.py [--fixtures fixtures] [--records fixtures/records] [--demo web/src/mocks/fixtures.json]

The fixtures are synthetic, but the rule is the real one: the model gets tokens for the identifiers and the event's
facts, never the patient's identifiers (PID-3, the visit number PV1-19), name or any part of it (PID-5), date of birth
(PID-7), address (PID-11), phone numbers (PID-13, PID-14) or the free text of notes (OBX-5 of a TX, ST or FT
observation, NTE-3). Every such value found in a fixture is looked for in what the model saw, in the forms a summary
would write it ("SYNTH, ADA", "Ada Synth", "1968-10-02", "02/10/1968", "2 October 1968"), in any case; values match as
whole words, so a token like MRN-T1 doesn't count. A recording's key, correlation key and label are Shutter's own
bookkeeping and are not checked. In the web demo the operator's evidence view (each case's snapshot) shows the
patient by design, and the scenario list holds the test data, so --demo checks the rest (the agents' runs, plans,
findings and events, and the incidents) for names, dates of birth and note text; identifiers are shown there by design
too. Prints each hit and exits 1 when there is any. Standard library only.
"""
import argparse
import glob
import json
import os
import re
import sys


MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
          "December"]


def segments(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    return [s for s in re.split(r"\r\n|\r|\n", text) if s]


def field(seg, n):
    parts = seg.split("|")
    return parts[n] if len(parts) > n else ""


def personal_values(fixture_dir):
    """Every personal value in the fixtures, as (kind, value as written, forms to look for)."""
    found = {}

    def add(kind, value, forms):
        value = value.strip()
        if len(value) < 4:
            return
        found.setdefault((kind, value), set()).update(f for f in forms if len(f) >= 4)

    for path in glob.glob(os.path.join(fixture_dir, "**", "*.hl7"), recursive=True):
        for seg in segments(path):
            kind = seg[:3]
            if kind == "PID":
                for rep in field(seg, 3).split("~"):
                    add("identifier", rep.split("^")[0], [rep.split("^")[0]])
                name = field(seg, 5).split("~")[0].split("^")
                family, given = (name + ["", ""])[:2]
                if family and given:
                    add("name", f"{family}^{given}", [f"{family}^{given}", f"{family}, {given}", f"{given} {family}"])
                    # A given name or a family name on its own (shorter ones only within the forms above, since three
                    # letters as a word would also be "dev" or "uri")
                    add("name part", given, [given])
                    add("name part", family, [family])
                dob = field(seg, 7)[:8]
                if re.fullmatch(r"\d{8}", dob):
                    y, m, d = dob[:4], dob[4:6], dob[6:]
                    month = MONTHS[int(m) - 1]
                    add("date of birth", dob, [dob, f"{y}-{m}-{d}", f"{d}/{m}/{y}", f"{int(d)} {month} {y}",
                                               f"{month} {int(d)}, {y}"])
                address = field(seg, 11).split("~")[0]
                if address.strip("^"):
                    add("address", address, [p for p in address.split("^") if len(p) >= 6])
                for n in (13, 14):
                    for phone in re.findall(r"\d{8,}", field(seg, n)):
                        add("phone", phone, [phone])
            elif kind == "PV1":
                add("identifier", field(seg, 19).split("^")[0], [field(seg, 19).split("^")[0]])
            elif kind == "OBX" and field(seg, 2) in ("TX", "ST", "FT"):
                add("note text", field(seg, 5), [field(seg, 5)])
            elif kind == "NTE":
                add("note text", field(seg, 3), [field(seg, 3)])
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--fixtures", default="fixtures")
    parser.add_argument("--records", default="fixtures/records")
    parser.add_argument("--demo", help="also check the web demo's recorded answers (web/src/mocks/fixtures.json)")
    args = parser.parse_args()
    values = personal_values(args.fixtures)
    files = sorted(glob.glob(os.path.join(args.records, "*.json")))
    if args.demo:
        files.append(args.demo)
    hits = 0
    for path in files:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        demo = path == args.demo
        # What the model saw (and said): not the recording's own key, correlation key or label
        if demo:
            seen_by_model = {
                "cases": {cid: {k: v for k, v in case.items() if k != "snapshot"}
                          for cid, case in data.get("cases", {}).items()},
                "incidents": data.get("incidents"),
            }
        else:
            seen_by_model = {k: data.get(k) for k in ("transcript", "toolCalls", "response")}
        text = json.dumps(seen_by_model, ensure_ascii=False)
        for (kind, value), forms in sorted(values.items()):
            if demo and kind == "identifier":
                continue
            seen = sorted(f for f in forms if re.search(rf"(?<![\w-]){re.escape(f)}(?![\w-])", text, re.IGNORECASE))
            if seen:
                hits += 1
                print(f"{os.path.relpath(path)}: {kind} {value!r} (as {', '.join(repr(s) for s in seen)})")
    print(f"{len(values)} personal values from the fixtures, {len(files)} files checked, {hits} findings")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
