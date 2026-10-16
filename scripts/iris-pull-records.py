#!/usr/bin/env python3
"""Pull agent-run recordings from an IRIS instance into fixtures/records, one file per recording in the fixture
shape (response as an object; transcript and toolCalls as JSON text), named scenario-<S>-<member>-<cfg>[-roundN].json.

    python3 scripts/iris-pull-records.py --url http://host:52773 --ns INTERLOCK [--like 'scenario:S2|%'] [--dir fixtures/records]

Only recordings whose key starts with "scenario:" are written (the demo scenarios); others are listed.
"""
import argparse
import base64
import json
import os
import re
import sys
import urllib.request

KEY_RE = re.compile(r"^scenario:(S\d+)\|([a-z]+)\|(\d+)(\|round(\d+))?$")


def query(url, ns, user, password, sql, params):
    body = json.dumps({"query": sql, "parameters": params}).encode()
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    req = urllib.request.Request(url.rstrip("/") + f"/api/atelier/v1/{ns}/action/query", data=body, method="POST",
                                 headers={"Authorization": "Basic " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as resp:
        out = json.loads(resp.read().decode())
    errors = out.get("status", {}).get("errors", [])
    if errors:
        raise RuntimeError(json.dumps(errors)[:500])
    return out.get("result", {}).get("content", [])


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", default=os.environ.get("IRIS_URL", "http://localhost:52773"))
    ap.add_argument("--ns", default="INTERLOCK")
    ap.add_argument("--user", default=os.environ.get("IRIS_USER", "_SYSTEM"))
    ap.add_argument("--password", default=os.environ.get("IRIS_PASSWORD", "SYS"))
    ap.add_argument("--like", default="scenario:%", help="SQL LIKE pattern on the key")
    ap.add_argument("--dir", default="fixtures/records")
    args = ap.parse_args()
    rows = query(args.url, args.ns, args.user, args.password,
                 'SELECT ID, "Key" FROM Interlock_Bridge.Record WHERE "Key" LIKE ? ORDER BY "Key"', [args.like])
    os.makedirs(args.dir, exist_ok=True)
    written, skipped = [], []
    for row in rows:
        m = KEY_RE.match(row["Key"])
        if not m:
            skipped.append(row["Key"])
            continue
        out = query(args.url, args.ns, args.user, args.password,
                    "SELECT Interlock_Util.Json_Export('Interlock.Bridge.Record', ?) AS j", [str(row["ID"])])
        j = out[0]["j"]
        d = json.loads(j) if isinstance(j, str) else j
        if isinstance(d.get("response"), str):
            d["response"] = json.loads(d["response"])
        if isinstance(d["response"].get("result"), str) and d["response"]["result"].startswith("{"):
            d["response"]["result"] = json.loads(d["response"]["result"])
        d.pop("id", None)
        ordered = {k: d[k] for k in ("key", "agentClass", "configVersion", "memberCode", "snapshotDigest", "correlationKey",
                                     "model", "response", "transcript", "toolCalls", "recordedAt", "label") if k in d}
        name = f"scenario-{m.group(1)}-{m.group(2)}-{m.group(3)}" + (f"-round{m.group(5)}" if m.group(5) else "") + ".json"
        path = os.path.join(args.dir, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(ordered, f, indent=1, ensure_ascii=False)
            f.write("\n")
        written.append((name, ordered.get("model"), len(ordered.get("transcript") or "")))
    for name, model, tlen in written:
        print(f"wrote {name}  ({model}, transcript {tlen} chars)")
    if skipped:
        print("not scenario recordings, left alone:", ", ".join(skipped))
    print(f"{len(written)} written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
