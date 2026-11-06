#!/usr/bin/env python3
"""A message under a key the receiver already holds, played through the feed against the demo receiver.

    python3 tests/e2e/same_key_check.py [--url http://localhost:52773]

A receipt shows that a key is taken, not that this message is what the receiver holds. Three messages, each in Site policy
mode and each opening on a key already committed with no model involved, must end blocked for a person with the receiver unchanged:

- a corrected ward under the same source, patient, visit, event and event time: the receiver refuses it, 409
  key_reused_with_different_payload, and the case's plan to reconcile is blocked RECEIPT_PAYLOAD_DIFFERS;
- a corrected bed, which sits outside the digest: the receiver answers 200 already_committed with the old bed, and the case
  opens all the same;
- a re-issue after a cancel of that movement, withheld by the demo receiver: 200 already_committed, and blocked
  RECEIPT_THEN_CANCELLED.

Last, a plain duplicate opens no case. Signs in as the demo user operator (password from SHUTTER_PASSWORD, default "shutter");
reads the receiver as _SYSTEM / SYS. It resets the downstream system and drops files into the feed, so don't run it on an
instance someone else is using. Exits 1 if anything differs. Standard library only.
"""
import argparse
import os
import sys
import time

from iris_query import query
from scenario_check import Session, downstream_encounter, wait, wait_until_idle

FAILED = []
PID = "PID|1||{mrn}^^^HOSP^MR||SYNTH^SAME||19760221|M"


def check(what, ok, detail=""):
    print(f"{'ok     ' if ok else 'DIFFERS'} {what}{f': {detail}' if detail and not ok else ''}", flush=True)
    if not ok:
        FAILED.append(what)


def message(trigger, control, when, mrn, visit, ward, bed="01"):
    """An ADT message in the fixtures' shape, the bay named after the visit so that no two patients share a bed."""
    structure = {"A01": "ADT_A01", "A02": "ADT_A02", "A12": "ADT_A12"}[trigger]
    location = f"{ward}^BAY{visit[-1]}^{bed}^HOSP"
    return "<CR>".join([
        f"MSH|^~\\&|PAS|HOSP|DOWNSTREAM|HOSP|{when}||ADT^{trigger}^{structure}|{control}|P|2.5.1",
        f"EVN|{trigger}|{when}||||{when}",
        PID.format(mrn=mrn),
        f"PV1|1|I|{location}||||||||||||||||{visit}|||||||||||||||||||||||||20261015080000",
    ])


class Feed:
    def __init__(self, args):
        self.args = args
        self.n = 0

    def drop(self, text):
        self.n += 1
        name = f"samekey-{int(time.time())}-{self.n}.hl7"
        rows = query(self.args.url, "SHUTTER", "SELECT Shutter_Test.Feed_Drop(?, ?) AS r", [name, text])
        got = rows[0]["r"]
        if str(got).startswith("error"):
            raise SystemExit(f"the feed took nothing: {got}")


def blocked_with(operator, visit, code, url, floor):
    """Waits for this visit's newest case to be closed, and checks it stopped for a person under the code."""

    def closed():
        _, listing = operator.call("GET", "/cases?limit=20")
        for c in (listing or {}).get("items", []):
            if c.get("encounterId") == visit and c.get("openedAt", "") >= floor and c.get("state") in (
                    "blocked", "escalated", "resolved", "failed"):
                return c
        return None

    case = wait(f"{visit}: a closed case", closed, 180)
    check(f"{visit}: the case stops for a person", case["state"] == "blocked", f"{case['state']}: {case.get('headline')}")
    _, reason = operator.call("GET", f"/cases/{case['caseId']}/blocked-reason")
    check(f"{visit}: it names {code}", (reason or {}).get("code") == code, str(reason)[:300])
    _, attempts = operator.call("GET", f"/cases/{case['caseId']}/attempts")
    writes = [x for x in attempts or [] if x.get("attempt")]
    check(f"{visit}: nothing was written", not writes, str(writes)[:200])
    return case


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default="http://localhost:52773")
    args = p.parse_args()
    operator = Session(args.url).sign_in("operator", os.environ.get("SHUTTER_PASSWORD", "shutter"))
    wait_until_idle(operator, 300)
    status, body = operator.call("POST", "/scenarios/reset", {})
    if status != 200:
        raise SystemExit(f"the reset was refused: HTTP {status} {body}")
    query(args.url, "SHUTTER", "SELECT Shutter_Test.Feed_Mode('policy') AS r")
    feed = Feed(args)
    held = lambda visit: downstream_encounter(args.url, "_SYSTEM", "SYS", visit)

    def admitted(mrn, visit):
        feed.drop(message("A01", f"{visit}-1", "20261015080000", mrn, visit, "WARD-A"))
        wait(f"{visit} admitted", lambda: held(visit).get("state") == "admitted" or None, 60)

    # A corrected ward under one key: the receiver refuses it, and a receipt is there for the first.
    floor = time.strftime("%Y-%m-%d", time.gmtime())
    admitted("MRN7001", "ENC-7001")
    feed.drop(message("A02", "ENC-7001-2", "20261015090000", "MRN7001", "ENC-7001", "WARD-B"))
    wait("ENC-7001 at WARD-B", lambda: held("ENC-7001").get("ward") == "WARD-B" or None, 60)
    feed.drop(message("A02", "ENC-7001-3", "20261015090000", "MRN7001", "ENC-7001", "WARD-C"))
    blocked_with(operator, "ENC-7001", "RECEIPT_PAYLOAD_DIFFERS", args.url, floor)
    check("ENC-7001: the receiver keeps WARD-B", held("ENC-7001").get("ward") == "WARD-B", str(held("ENC-7001"))[:200])

    # A corrected bed: the same digest, so 200 already_committed.
    admitted("MRN7002", "ENC-7002")
    feed.drop(message("A02", "ENC-7002-2", "20261015090000", "MRN7002", "ENC-7002", "WARD-B"))
    wait("ENC-7002 at WARD-B", lambda: held("ENC-7002").get("ward") == "WARD-B" or None, 60)
    feed.drop(message("A02", "ENC-7002-3", "20261015090000", "MRN7002", "ENC-7002", "WARD-B", "02"))
    blocked_with(operator, "ENC-7002", "RECEIPT_PAYLOAD_DIFFERS", args.url, floor)

    # A re-issue after a cancel the demo receiver does not take: withheld, a person reverses by hand, and the re-issue
    # has the first one's key and digest.
    admitted("MRN7003", "ENC-7003")
    feed.drop(message("A02", "ENC-7003-2", "20261015090000", "MRN7003", "ENC-7003", "WARD-B"))
    wait("ENC-7003 at WARD-B", lambda: held("ENC-7003").get("ward") == "WARD-B" or None, 60)
    feed.drop(message("A12", "ENC-7003-3", "20261015091000", "MRN7003", "ENC-7003", "WARD-A"))

    def closed_on(word):
        """A closed case of this visit whose operation is the word's; each receiver of the feed has its own."""
        _, listing = operator.call("GET", "/cases?limit=20")
        return next((c for c in (listing or {}).get("items", []) if c.get("encounterId") == "ENC-7003"
                     and f"^{word}^" in c.get("operationKey", "")
                     and c.get("state") in ("blocked", "escalated", "resolved", "failed")), None)

    wait("the withheld cancel's case", lambda: closed_on("cancel_transfer"), 120)
    time.sleep(3)
    feed.drop(message("A02", "ENC-7003-4", "20261015090000", "MRN7003", "ENC-7003", "WARD-B"))

    case = wait("the re-issue's case", lambda: closed_on("transfer"), 180)
    check("ENC-7003: the re-issue stops for a person", case["state"] == "blocked", f"{case['state']}: {case.get('headline')}")
    _, reason = operator.call("GET", f"/cases/{case['caseId']}/blocked-reason")
    check("ENC-7003: it names RECEIPT_THEN_CANCELLED", (reason or {}).get("code") == "RECEIPT_THEN_CANCELLED", str(reason)[:300])

    # A plain duplicate is a delivery, as it always was.
    admitted("MRN7004", "ENC-7004")
    feed.drop(message("A02", "ENC-7004-2", "20261015090000", "MRN7004", "ENC-7004", "WARD-B"))
    wait("ENC-7004 at WARD-B", lambda: held("ENC-7004").get("ward") == "WARD-B" or None, 60)
    feed.drop(message("A02", "ENC-7004-3", "20261015090000", "MRN7004", "ENC-7004", "WARD-B"))
    time.sleep(15)
    _, listing = operator.call("GET", "/cases?limit=20")
    extra = [c["caseId"] for c in (listing or {}).get("items", []) if c.get("encounterId") == "ENC-7004"]
    check("ENC-7004: a plain duplicate opens no case", not extra, str(extra))

    print(f"{len(FAILED)} differ" if FAILED else "all as expected", flush=True)
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
