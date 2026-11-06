#!/usr/bin/env python3
"""S8, the case the catalogue gives to the board, when nobody on the board can answer.

    python3 tests/e2e/no_board_answer_check.py [--url http://localhost:52773] [--container shutter]

Three ways for no board member to answer, each making no model call: no recording (S8's are set aside, and put back at the
end), the day's budget spent, and the provider refusing the key (both in a session inside the container, with the Agent
items' mode set to live: the Agent item refuses such a run before anything is sent). In Board and Site policy mode each
must end escalated, with no write and the receiver's WARD-C kept, under the reason NO_BOARD_ANSWER. Rules only must still
write WARD-B over WARD-C: it is the baseline, and it does not change.

Signs in as the demo user operator (password from SHUTTER_PASSWORD, default "shutter"). It plays a scenario, which resets
the downstream system, and changes the instance's budget and provider state for its own run, so don't run it on an
instance someone else is using. Exits 1 at the first difference.
"""
import argparse
import os
import subprocess
import sys
import time

from iris_query import query
from scenario_check import Session

HERE = os.path.dirname(os.path.abspath(__file__))
FAILED = []


def check(what, ok, detail=""):
    print(f"{'ok     ' if ok else 'DIFFERS'} {what}{f': {detail}' if detail and not ok else ''}")
    if not ok:
        FAILED.append(what)


def session(container, line):
    """One line in an IRIS session in SHUTTER inside the container. A licence refusal (exit 133) is waited out."""
    for _ in range(24):
        done = subprocess.run(["docker", "exec", "-i", container, "iris", "session", "IRIS", "-U", "SHUTTER"],
                              input=f"{line}\nHalt\n", capture_output=True, text=True, check=False)
        if done.returncode == 0 and "LICENSE LIMIT" not in done.stdout:
            return
        time.sleep(5)
    raise SystemExit(f"the session failed ({done.returncode}): {done.stdout[-400:]}")


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
    p.add_argument("--container", default=os.environ.get("CTR", "shutter"))
    args = p.parse_args()
    operator = Session(args.url).sign_in("operator", os.environ.get("SHUTTER_PASSWORD", "shutter"))
    aside = "UPDATE Shutter_Bridge.Record SET \"Key\" = 'aside:' || \"Key\" WHERE \"Key\" %STARTSWITH 'scenario:S8'"
    back = "UPDATE Shutter_Bridge.Record SET \"Key\" = SUBSTRING(\"Key\", 7) WHERE \"Key\" %STARTSWITH 'aside:scenario:S8'"
    clear = ('Kill ^Shutter.Budget("reserve","no-board-check"),^Shutter.Config("aihub","mode"),'
             '^Shutter.Config("dailyBudgetUsd"),^Shutter.Config("budgetReserveUsd"),^Shutter.Config("provider")')
    query(args.url, "SHUTTER", aside)
    try:
        stops(args, operator, "no recording")
        session(args.container, 'Set ^Shutter.Config("aihub","mode")="live",^Shutter.Config("dailyBudgetUsd")=1,'
                                '^Shutter.Config("budgetReserveUsd")=100 '
                                'Do ##class(Shutter.Util.Budget).Reserve("no-board-check")')
        stops(args, operator, "the budget spent")
        session(args.container, clear)
        session(args.container, 'Set ^Shutter.Config("aihub","mode")="live",'
                                '^Shutter.Config("provider","authFailedAt")=##class(Shutter.Util.Time).NowUTC(),'
                                '^Shutter.Config("provider","authFailedText")="a refused key, for this check"')
        stops(args, operator, "the key refused")
        session(args.container, clear)
        done = play(args, "rules")
        check("Rules only still writes WARD-B over WARD-C",
              "resolved, resend, one write, downstream admitted WARD-B" in done.stdout, done.stdout[-500:])
    finally:
        query(args.url, "SHUTTER", back)
        session(args.container, clear)
    if FAILED:
        print(f"{len(FAILED)} differ")
        return 1
    print("all as expected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
