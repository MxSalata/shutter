#!/usr/bin/env python3
"""Checks that nothing personal from the HL7 fixtures reaches what the agents saw: the recorded runs' transcripts,
tool calls and responses (and, with --demo, the names, dates of birth and notes in the web demo's recorded answers).

    python3 tests/privacy_check.py [--fixtures fixtures] [--records fixtures/records] [--demo web/src/mocks/fixtures.json]
    python3 tests/privacy_check.py --self-test

The fixtures are synthetic, but the rule is the real one: the model gets tokens for the identifiers and the event's
facts, never the patient's identifiers (PID-3, the visit number PV1-19), name or any part of it (PID-5), date of birth
(PID-7), address (PID-11), phone numbers (PID-13, PID-14), a merge's prior patient, visit and name (MRG-1, MRG-5,
MRG-7) or the free text of notes (OBX-5 of a TX, ST or FT
observation, NTE-3). Every such value found in a fixture is looked for in what the model saw, in the forms a summary
would write it ("SYNTH, ADA", "Ada Synth", "1968-10-02", "02/10/1968", "2 October 1968"), in any case; values match as
whole words, so a token like MRN-T1 doesn't count. A recording's key, correlation key and label are Shutter's own
bookkeeping and are not checked. In the web demo the operator's evidence view (each case's snapshot) shows the
patient by design, and the scenario list holds the test data, so --demo checks the rest (the agents' runs, plans,
findings and events, and the incidents) for names, dates of birth and note text; identifiers are shown there by design
too, except the NHS number. NHS numbers (PID-3 typed NH) are looked for everywhere, as written and as "999 100 1018",
and so is anything shaped like one: ten digits, plain or spaced 3 3 4, whose modulus 11 check digit is valid, so a real
NHS number fails the check even when no fixture holds it. A production review's recording (key review:...) is checked
the same way, and more strictly: its agent sees item names, setting values, counts, header ids and case ids, never a
case's evidence, so not even a case's token for an identifier (MRN-T1, ENC-T1) may appear in it; that rule reads the
recording's strings decoded (JSON text within them too), as every rule here does, so a value or token after a newline
or a tab is found. Prints each hit and exits 1 when there is any. --self-test runs the case-token rule over synthetic
recordings instead. Standard library only.
"""
import argparse
import glob
import json
import os
import re
import sys


MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
          "December"]


# Ten digits, plain or spaced (or hyphenated) 3 3 4, as an NHS number is written
NHS_SHAPE = re.compile(r"(?<![\w-])(\d{3})[ -]?(\d{3})[ -]?(\d{4})(?![\w-])")
# A case's token for an identifier (Shutter.Store.CaseToken): what a board member sees in place of the value
CASE_TOKEN = re.compile(r"(?<![\w-])(?:MRN|NHS|PID|ENC|VISIT|NAME|DOB)-T\d+(?![\w-])")


def nhs_valid(digits):
    """Whether ten digits carry a valid NHS number check digit (modulus 11; a remainder giving 10 is never issued)."""
    check = (11 - sum(int(d) * (10 - i) for i, d in enumerate(digits[:9])) % 11) % 11
    return check != 10 and check == int(digits[9])


def nhs_shaped(text):
    """Every NHS number in a text, by its shape and check digit, as (as written, digits)."""
    return [(m.group(0), "".join(m.groups())) for m in NHS_SHAPE.finditer(text) if nhs_valid("".join(m.groups()))]


def decoded_text(value):
    """Every string in a value as the model read it, one per line: a string that is JSON text (a transcript or the
    tool calls as recorded) is decoded and walked too, so a newline or tab before a value stays a newline or tab rather
    than the escape json.dumps would write in its place."""
    leaves = []

    def walk(v):
        if isinstance(v, dict):
            for x in v.values():
                walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)
        elif isinstance(v, str):
            t = v.strip()
            if t[:1] in ("[", "{", '"'):
                try:
                    decoded = json.loads(t)
                except ValueError:
                    decoded = None
                if decoded is not None and decoded != v:
                    walk(decoded)
                    return
            leaves.append(v)
        elif v is not None:
            leaves.append(str(v))

    walk(value)
    return "\n".join(leaves)


def review_tokens(data):
    """The case tokens in a production review's recording, read from the decoded transcript, tool calls and response."""
    return sorted(set(CASE_TOKEN.findall(decoded_text({k: data.get(k) for k in ("transcript", "toolCalls", "response")}))))


def self_test():
    """Synthetic recordings that prove the case-token rule, a token after a newline or a tab included."""
    cases = [
        ({"transcript": json.dumps([{"role": "tool", "content": "header 7\nMRN-T1 on it"}])}, ["MRN-T1"]),
        ({"toolCalls": json.dumps([{"name": "search_review", "arguments": {"q": "x\tENC-T2"}}])}, ["ENC-T2"]),
        ({"response": {"result": json.dumps({"summary": "line one\nNHS-T3"})}}, ["NHS-T3"]),
        ({"transcript": json.dumps([{"role": "tool", "content": "3 cases, header 7, setting RetryInterval"}])}, []),
        ({"transcript": "XMRN-T1 and MRN-T1x"}, []),
    ]
    failed = 0
    for data, want in cases:
        got = review_tokens(data)
        if got != want:
            failed += 1
            print(f"self-test: {data!r} gave {got!r}, expected {want!r}")
    print(f"self-test: {len(cases)} cases, {failed} failed")
    return 1 if failed else 0


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
                    value, kind_code = rep.split("^")[0], (rep.split("^") + [""] * 5)[4].upper()
                    if kind_code in ("NH", "NHS", "NI") and re.fullmatch(r"\d{10}", value):
                        add("NHS number", value, [value, f"{value[:3]} {value[3:6]} {value[6:]}"])
                    else:
                        add("identifier", value, [value])
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
            elif kind == "MRG":
                # A merge's prior patient (every MRG-1 repetition), prior visit (MRG-5) and prior name (MRG-7)
                for rep in field(seg, 1).split("~"):
                    add("identifier", rep.split("^")[0], [rep.split("^")[0]])
                add("identifier", field(seg, 5).split("^")[0], [field(seg, 5).split("^")[0]])
                name = field(seg, 7).split("~")[0].split("^")
                family, given = (name + ["", ""])[:2]
                if family and given:
                    add("name", f"{family}^{given}", [f"{family}^{given}", f"{family}, {given}", f"{given} {family}"])
                    add("name part", given, [given])
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
    parser.add_argument("--self-test", action="store_true", help="check the case-token rule on synthetic recordings")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
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
        # Read decoded, so that a value after a newline or a tab in a transcript is still a whole word
        text = decoded_text(seen_by_model)
        reported = set()
        for (kind, value), forms in sorted(values.items()):
            if demo and kind == "identifier":
                continue
            seen = sorted(f for f in forms if re.search(rf"(?<![\w-]){re.escape(f)}(?![\w-])", text, re.IGNORECASE))
            if seen:
                hits += 1
                print(f"{os.path.relpath(path)}: {kind} {value!r} (as {', '.join(repr(s) for s in seen)})")
                reported.add(value)
        # Any other NHS number, by its shape: one no fixture holds is still a patient's
        for written, digits in sorted(set(nhs_shaped(text))):
            if digits not in reported:
                hits += 1
                print(f"{os.path.relpath(path)}: NHS number {digits!r} by its shape and check digit (as {written!r})")
        # A review's context carries no case evidence, so a token there means a case's identifiers reached it
        if not demo and str(data.get("key", "")).startswith("review:"):
            for token in sorted(set(CASE_TOKEN.findall(text))):
                hits += 1
                print(f"{os.path.relpath(path)}: case token {token!r} in a production review's recording")
    print(f"{len(values)} personal values from the fixtures, {len(files)} files checked, {hits} findings")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
