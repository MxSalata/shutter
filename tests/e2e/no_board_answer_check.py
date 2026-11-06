#!/usr/bin/env python3
"""S8, the case the catalogue gives to the board, when nobody on the board can answer.

    python3 tests/e2e/no_board_answer_check.py [--url http://localhost:52773]

S8's recordings are set aside, and put back at the end, so no board member has anything to answer with and no model is
called. In Board and Site policy mode the case must end escalated, with no write and the receiver's WARD-C kept, under the
reason NO_BOARD_ANSWER. Rules only must still write WARD-B over WARD-C: it is the baseline, and it does not change. The day's
budget and a refused key end the same way (the unit tests of Shutter.Test.BoardLead give each its status).

Signs in as the demo user operator (password from SHUTTER_PASSWORD, default "shutter"). It plays a scenario, which resets
the downstream system, so don't run it on an instance someone else is using. Exits 1 at the first difference.
"""
import argparse
import os
import subprocess
import sys

from iris_query import query
from scenario_check import Session

HERE = os.path.dirname(os.path.abspath(__file__))
FAILED = []


def check(what, ok, detail=""):
    print(f"{'ok     ' if ok else 'DIFFERS'} {what}{f': {detail}' if detail and not ok else ''}")
    if not ok:
        FAILED.append(what)


def play(args, modes):
    return subprocess.run([sys.executable, os.path.join(HERE, "scenario_check.py"), "--url", args.url, "--modes", modes,
                           "--approve", "S8"], capture_output=True, text=True, check=False)


def stops(args, operator, route):
    done = play(args, "board,policy")
    check(f"{route}: S8 in Board and Site policy mode stops with no write", done.returncode == 0, done.stdout[-500:])
    _, cases = operator.call("GET", "/cases?limit=2")
    for case in (cases.get("items", []) if isinstance(cases, dict) else cases)[:2]:
        _, reason = operator.call("GET", f"/cases/{case['caseId']}/blocked-reason")
        check(f"{route}: {case['caseId']} names NO_BOARD_ANSWER and E7",
              reason.get("code") == "NO_BOARD_ANSWER" and "E7" in reason.get("headline", ""), str(reason)[:300])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--url", default="http://localhost:52773")
    args = p.parse_args()
    operator = Session(args.url).sign_in("operator", os.environ.get("SHUTTER_PASSWORD", "shutter"))
    aside = "UPDATE Shutter_Bridge.Record SET \"Key\" = 'aside:' || \"Key\" WHERE \"Key\" %STARTSWITH 'scenario:S8'"
    back = "UPDATE Shutter_Bridge.Record SET \"Key\" = SUBSTRING(\"Key\", 7) WHERE \"Key\" %STARTSWITH 'aside:scenario:S8'"
    query(args.url, "SHUTTER", aside)
    try:
        stops(args, operator, "no recording")
        done = play(args, "rules")
        check("Rules only still writes WARD-B over WARD-C",
              "resolved, resend, one write, downstream admitted WARD-B" in done.stdout, done.stdout[-500:])
    finally:
        query(args.url, "SHUTTER", back)
    if FAILED:
        print(f"{len(FAILED)} differ")
        return 1
    print("all as expected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
