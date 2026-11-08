#!/usr/bin/env python3
"""Builds the held-out cases' playable fixtures from the sealed case file, and checks the seal first.

    python3 tests/fair_test/build_fixtures.py --sealed DIR [--out tests/fair_test/fixtures] [--check]

DIR holds cases.md, expected.json, scoring.md and manifest.sha256, none of which this changes. Every message goes out
byte for byte as cases.md prints it, with segments ended by carriage returns (CONTRACTS 3). The steps below are the
case file's build recipes in the runner's step vocabulary, with two additions the file leaves to the builder: a 5 s wait
before a fault is switched off, so that the file service has read the failing message by then, and F08's delay, which is
45 s and not the recipe's 30 s (README.md, What the rig changes). With --check it writes nothing and exits 1 when what
is on disk differs. Standard library only.
"""
import argparse
import hashlib
import json
import os
import re
import sys

SEAL = {
    "cases.md": "01b89c903cb3d24d7b3d4e9e3a41518ac0ae94dd32580cefa18ea7552e34752d",
    "expected.json": "5bc5edfc4b7d5f0cf20cf2cd9743b9f60003a4916f0eeabf68d8c6d93e644a31",
    "scoring.md": "1a029ad9f047ecd46cb27bbd912e9999cfdd1094ea70880ba18c1fb8c933d858",
}
F08_DELAY = 45


def fail(key):
    return [{"fault": "fail_before_accept", "operation_key": key}]


def fault_off(wait=5):
    return [{"wait": wait}, {"fault": "off"}]


def manual(encounter, event, time, ward=None, source=None):
    entry = {"encounter_id": encounter, "event": event, "event_time": time}
    if ward:
        entry["ward"] = ward
    if source:
        entry["source_system"] = source
    return {"manual": entry}


def recipes():
    """Per case, the steps: a number is the case's nth message in cases.md (1 first), anything else a runner step.
    failed is the failed operation's key, profile what the case sets in the site profile."""
    day = "2026-11-18"
    k = {c: f"EPR^NVH^{p}^{v}^transfer^{day}T{t}:00Z" for c, p, v, t in (
        ("F01", "N0048213", "V26-00417", "10:05"), ("F02", "N0052871", "V26-00433", "14:10"),
        ("F03", "N0039540", "V26-00451", "11:05"), ("F04", "N0061127", "V26-00462", "11:05"),
        ("F05", "N0045719", "V26-00479", "09:30"), ("F06", "N0058302", "V26-00488", "00:50"),
        ("F07", "N0042966", "V26-00512", "10:15"), ("F08", "N0063481", "V26-00527", "12:10"),
        ("F09", "N0037215", "V26-00539", "12:00"), ("F10", "N0056608", "V26-00546", "13:20"),
        ("F11", "N0049377", "V26-00558", "15:00"), ("F12", "N0067732", "V26-00744", "09:30"))}
    return {
        "F01": {"steps": [1, 2, *fail(k["F01"]), 3, *fault_off()], "failed": k["F01"]},
        "F02": {"steps": [1, manual("V26-00433", "discharge", f"{day}T16:30:00Z"), 2], "failed": k["F02"]},
        "F03": {"steps": [1, manual("V26-00451", "transfer", f"{day}T11:05:00Z", "SAU", "EPR"),
                          manual("V26-00451", "transfer", f"{day}T11:40:00Z", "CCU", "EPR"),
                          *fail(k["F03"]), 2, *fault_off(), 3], "failed": k["F03"]},
        "F04": {"steps": [1, 2, 3], "failed": k["F04"]},
        "F05": {"steps": [1, manual("V26-00479", "transfer", f"{day}T09:30:00Z", "CCU", "FLOW"),
                          *fail(k["F05"]), 2, *fault_off()], "failed": k["F05"],
                "profile": {"authoritative_source": "EPR"}},
        "F06": {"steps": [1, manual("V26-00488", "transfer", f"{day}T01:00:00Z", "SAU", "FLOW"),
                          *fail(k["F06"]), 2, *fault_off()], "failed": k["F06"]},
        "F07": {"steps": [1, 2, 3, *fail(k["F07"]), 4, *fault_off()], "failed": k["F07"],
                "other_encounter": "V26-00388"},
        "F08": {"steps": [1, {"fault": "delay_response", "operation_key": k["F08"], "seconds": F08_DELAY}, 2,
                          *fault_off(F08_DELAY + 5)], "failed": k["F08"], "read_before_commit": True},
        "F09": {"steps": [1, *fail(k["F09"]), 2, 3, *fault_off()], "failed": k["F09"], "must_see_before_reading": 3},
        "F10": {"steps": [1, *fail(k["F10"]), 2, *fault_off()], "failed": k["F10"],
                "profile": {"model_content": {"free_text": True}}},
        "F11": {"steps": [1, *fail(k["F11"]), 2, *fault_off()], "failed": k["F11"]},
        "F12": {"steps": [1, 2], "failed": k["F12"]},
    }


def check_seal(sealed):
    """Exits unless the three sealed files are the ones hashed before any run."""
    bad = []
    for name, want in SEAL.items():
        with open(os.path.join(sealed, name), "rb") as f:
            if hashlib.sha256(f.read()).hexdigest() != want:
                bad.append(name)
    if bad:
        raise SystemExit(f"the seal is broken: {', '.join(bad)} differ from the hashes written before any run")


def messages(cases_text):
    """{case id: [message text as printed, ...]}: the fenced blocks that start with MSH, in the order they appear."""
    found = {}
    for section in re.split(r"(?m)^## (?=F\d\d\.)", cases_text)[1:]:
        found[section[:3]] = [b.strip("\n") for b in re.findall(r"(?ms)^```\n(MSH.*?)^```$", section)]
    return found


def build(sealed):
    """{relative path: bytes}: every fixture file and scenarios.json."""
    with open(os.path.join(sealed, "cases.md"), encoding="utf-8") as f:
        printed = messages(f.read())
    files, scenarios = {}, []
    for case, recipe in recipes().items():
        names = []
        for n, text in enumerate(printed[case], 1):
            trigger = text.split("\n", 1)[0].split("|")[8].split("^")[1]
            name = f"{case}-{n:02d}-{trigger}.hl7"
            names.append(name)
            files[f"{case}/{name}"] = ("\r".join(text.split("\n")) + "\r").encode("ascii")
        steps = []
        for step in recipe["steps"]:
            if isinstance(step, int):
                steps.append({"file": names[step - 1]})
            else:
                steps.append(step)
        scenario = {"id": case, "title": "Held-out case", "summary": "", "steps": steps, "expected": {},
                    "rig": {k: v for k, v in recipe.items() if k != "steps"}}
        scenarios.append(scenario)
    files["scenarios.json"] = (json.dumps(scenarios, indent=1) + "\n").encode("ascii")
    return files


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--sealed", required=True)
    p.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures"))
    p.add_argument("--check", action="store_true")
    args = p.parse_args()
    check_seal(args.sealed)
    differs = []
    for rel, data in build(args.sealed).items():
        path = os.path.join(args.out, rel)
        if args.check:
            if not os.path.exists(path) or open(path, "rb").read() != data:
                differs.append(rel)
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
    if differs:
        print("differs from the sealed case file:", ", ".join(differs))
        return 1
    print("the seal holds; fixtures " + ("match" if args.check else "written"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
