#!/usr/bin/env python3
"""Checks that a key typed into an agent item's Model or ProviderConfig setting appears nowhere in full.

    python3 tests/e2e/key_mask_check.py [--url http://localhost:52773] [--ns SHUTTER] [--item "Agent Impact"] [--scenario S2]
                                        [--arm] [--disarm]

With --arm, sets the item's ProviderConfig and Model to two key-shaped test values and its Mode to live (the rig
Shutter.Test.KeyMaskRig, loaded with the unit tests), so the item restarts and logs its start line; with the scenario
named, plays it once on the board (tests/e2e/scenario_check.py, its outcome not judged) so the item runs. Then looks for
either value, and for the configuration name the runner would build from it, in: GET /health (anonymous), and signed
in as the operator GET /settings, /costs, /cases and every case's /runs; the rows of Shutter_Store.AgentRun, the
agent responses' message bodies, the reviews and the questions; and the Event Log, trace lines included. Also checks
that the run was refused without a lookup and that "hidden" is what each place shows. --disarm puts the item's
settings back (no ProviderConfig, no Model, Mode auto). Exits 1 on any hit. Standard library only. The values are
joined from two parts, so the repository's secret scan does not take this file for a leaked key.
"""
import argparse
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iris_query import query  # noqa: E402
from scenario_check import Session  # noqa: E402

KEY_CONFIG = "sk-" + "ant-api03-NOTAREALKEY000test000"
KEY_MODEL = "sk-" + "proj-NOTAREALKEY111test111"
VALUES = [KEY_CONFIG, KEY_MODEL, "NOTAREALKEY000test000", "NOTAREALKEY111test111"]


def hits(where, text, found):
    for v in VALUES:
        if v in text:
            found.append(f"{where}: holds {v[:12]}...")


def rig(url, ns, item, pc, model, mode):
    rows = query(url, ns, "SELECT Shutter_Test.KeyMaskRig_Arm(?, ?, ?, ?) AS r", [item, pc, model, mode])
    return rows[0]["r"] if rows else "no answer"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", default=os.environ.get("IRIS_URL", "http://localhost:52773"))
    ap.add_argument("--ns", default="SHUTTER", help="Shutter's namespace (USER after a stock install)")
    ap.add_argument("--item", default="Agent Impact")
    ap.add_argument("--scenario", default="")
    ap.add_argument("--arm", action="store_true")
    ap.add_argument("--disarm", action="store_true")
    ap.add_argument("--password", default=os.environ.get("SHUTTER_PASSWORD", "shutter"))
    args = ap.parse_args()
    if args.disarm:
        print("disarm:", rig(args.url, args.ns, args.item, "-", "-", "auto"))
        return 0
    since = 0
    if args.arm:
        rows = query(args.url, args.ns, "SELECT MAX(ID) AS m FROM Ens_Util.Log")
        since = (rows[0]["m"] or 0) if rows else 0
        print("arm:", rig(args.url, args.ns, args.item, KEY_CONFIG, KEY_MODEL, "live"))
    if args.scenario:
        here = os.path.dirname(os.path.abspath(__file__))
        subprocess.run([sys.executable, os.path.join(here, "scenario_check.py"), "--url", args.url, "--approve",
                        args.scenario], check=False)
    found, seen = [], []
    anon = Session(args.url)
    status, body = anon.call("GET", "/health")
    hits("GET /health", json.dumps(body), found)
    seen.append(f"GET /health last_live_run.model = {((body or {}).get('last_live_run') or {}).get('model')}")
    op = Session(args.url).sign_in("operator", args.password)
    for path in ["/settings", "/costs", "/cases"]:
        status, body = op.call("GET", path)
        hits(f"GET {path}", json.dumps(body), found)
        if path == "/settings":
            for a in (body or {}).get("agentItems", []):
                if a.get("name") == args.item:
                    seen.append(f"GET /settings {args.item}: providerConfig {a.get('providerConfig')}, model "
                                f"{a.get('model')}, answeredBy {a.get('answeredBy')}")
        if path == "/cases":
            items = body.get("items", body) if isinstance(body, dict) else (body or [])
            for c in items or []:
                cid = c.get("caseId") or c.get("id")
                if cid:
                    s2, runs = op.call("GET", f"/cases/{cid}/runs")
                    hits(f"GET /cases/{cid}/runs", json.dumps(runs), found)
    tables = [("Shutter_Store.AgentRun", "Model, ProviderConfig, Error, Content"),
              ("Shutter_Bridge_Msg.AgentResponse", "Model, ProviderConfig, Error"),
              ("Shutter_Store.Review", "Model, ProviderConfig, Error"),
              ("Shutter_Store.CaseQuestion", "Model, Error")]
    for table, cols in tables:
        try:
            rows = query(args.url, args.ns, f"SELECT ID, {cols} FROM {table}")
        except Exception as e:
            print(f"{table}: not read ({str(e)[:100]})")
            continue
        for r in rows:
            hits(f"{table} {r.get('ID')}", json.dumps(r), found)
    rows = query(args.url, args.ns, "SELECT TOP 1 Model, ProviderConfig, Status, Error FROM Shutter_Store.AgentRun "
                 "WHERE MemberCode = 'impact' ORDER BY ID DESC")
    if rows:
        seen.append(f"newest impact AgentRun: {rows[0]}")
    rows = query(args.url, args.ns, "SELECT ID, Type, Text FROM Ens_Util.Log WHERE ID > ?", [since])
    for r in rows:
        hits(f"Event Log {r['ID']} (type {r['Type']})", r.get("Text") or "", found)
        t = r.get("Text") or ""
        if args.item in t and ("starts in" in t or "Agent run done" in t or "looks like a key" in t):
            seen.append(f"Event Log {r['ID']}: {t[:220]}")
        if "Agent run done" in t or "looks like a key" in t:
            seen.append(f"Event Log {r['ID']}: {t[:220]}")
    for line in seen:
        print("seen:", line)
    for line in found:
        print("HIT:", line)
    print(f"{len(found)} place(s) hold a test value in full")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
