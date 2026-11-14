#!/usr/bin/env python3
"""Checks the productions' Event Log after the scenarios: no ObjectScript runtime error anywhere.

    python3 tests/e2e/eventlog_check.py [--url http://localhost:52773] [--ns SHUTTER,HOSPITAL] [--since ID]

The scenarios make deliveries fail on purpose, so the routing processes log ErrBPTerminated for each failed delivery,
and those are expected. What must never appear is a runtime error in Shutter's own code: <UNDEFINED>, <PARAMETER>, a
class, method or property that does not exist, <INVALID OREF>, <SUBSCRIPT>, or an "ERROR #5002: ObjectScript error"
(two such bugs on 18 and 20 Oct 2026 showed only there). Errors and warnings from items outside the expected ones are
listed too, without failing. A namespace that does not exist is skipped. Exit status 1 when a runtime error is found.
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iris_query import query  # noqa: E402

RUNTIME = re.compile(r"<(UNDEFINED|PARAMETER|METHOD DOES NOT EXIST|CLASS DOES NOT EXIST|PROPERTY DOES NOT EXIST|"
                     r"INVALID OREF|SUBSCRIPT|SYNTAX|LIST|COMMAND|DIVIDE|MAXSTRING|STORE|FRAMESTACK|ZSOAP|"
                     r"OBJECT DISPATCH|NOLINE|ILLEGAL VALUE)>|ERROR #5002\b")
# Items whose errors the scenarios cause on purpose: a routing process ends when its delivery fails (a case is opened),
# and S35's HL7 link to the demo hospital's FHIR ward system never opens a connection
EXPECTED = {"ADT to Downstream", "ADT to Records", "PAS to Downstream", "PAS to Records", "FHIR Ward Out"}


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", default=os.environ.get("IRIS_URL", "http://localhost:52773"))
    ap.add_argument("--ns", default="SHUTTER,HOSPITAL")
    ap.add_argument("--since", type=int, default=0, help="only Event Log rows after this ID")
    args = ap.parse_args()
    bad, other = [], {}
    for ns in [n.strip() for n in args.ns.split(",") if n.strip()]:
        try:
            rows = query(args.url, ns, "SELECT ID, %EXACT(ConfigName) AS Item, Type, Text FROM Ens_Util.Log "
                         "WHERE Type IN (2, 3) AND ID > ? ORDER BY ID", [args.since])
        except Exception as e:
            print(f"{ns}: skipped ({str(e)[:120]})")
            continue
        for r in rows:
            text = r.get("Text") or ""
            if RUNTIME.search(text):
                bad.append(f"{ns} #{r['ID']} {r['Item']}: {text[:300]}")
            elif r["Item"] not in EXPECTED:
                key = (ns, r["Item"], "error" if r["Type"] == 2 else "warning")
                other[key] = other.get(key, 0) + 1
        print(f"{ns}: {len(rows)} error and warning rows read")
    for (ns, item, kind), n in sorted(other.items()):
        print(f"note: {ns} {item}: {n} {kind}(s), not a runtime error")
    for b in bad:
        print("RUNTIME ERROR " + b)
    print(f"{len(bad)} runtime error(s)" if bad else "no runtime errors in the Event Log")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
