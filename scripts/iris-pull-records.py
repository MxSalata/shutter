#!/usr/bin/env python3
"""Pull agent-run recordings from an IRIS instance into fixtures/records, one file per recording in the fixture
shape (response as an object; transcript and toolCalls as JSON text), named scenario-<S>-<member>-<cfg>[-roundN].json, or
scenario-<S>-<encounter>-<event>-<member>-<cfg>[-roundN].json for the keys that name the case's encounter and event.

    python3 scripts/iris-pull-records.py --url http://host:52773 --ns SHUTTER [--like 'scenario:S2:%'] [--dir fixtures/records]

Only recordings whose key starts with "scenario:" are written (the demo scenarios); others are listed. The repository
has no em dashes, and models write them: in every text of a recording, a spaced em dash becomes a semicolon and any
other one a hyphen, also where the transcript's JSON text escapes it. Nothing else in a recording is changed.
"""
import argparse
import base64
import json
import os
import re
import sys
import urllib.request

# scenario:<S>[:<encounter>:<event>]|<member>|<configVersion>[|round<n>], as in scripts/check-records.py
KEY_RE = re.compile(r"^scenario:(?P<scenario>S\d+)(?::(?P<encounter>[^:|]+):(?P<event>[^:|]+))?"
                    r"\|(?P<member>[a-z]+)\|(?P<cfg>\d+)(?:\|round(?P<round>\d+))?$")


def plain(x):
    """x with its em dashes replaced, in every string it holds."""
    if isinstance(x, str):
        for dash in ("\u2014", "\\u2014"):
            x = x.replace(" " + dash + " ", "; ").replace(dash, "-")
        return x
    if isinstance(x, list):
        return [plain(v) for v in x]
    if isinstance(x, dict):
        return {k: plain(v) for k, v in x.items()}
    return x


def file_name(m):
    """The fixture file for a key (the same rule as scripts/check-records.py)."""
    case = [m["encounter"], m["event"]] if m["encounter"] else []
    parts = [re.sub(r"[^A-Za-z0-9._-]", "_", x) for x in ["scenario", m["scenario"], *case, m["member"], m["cfg"]]]
    return "-".join(parts) + (f"-round{m['round']}" if m["round"] else "") + ".json"


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
    ap.add_argument("--ns", default="SHUTTER")
    ap.add_argument("--user", default=os.environ.get("IRIS_USER", "_SYSTEM"))
    ap.add_argument("--password", default=os.environ.get("IRIS_PASSWORD", "SYS"))
    ap.add_argument("--like", default="scenario:%", help="SQL LIKE pattern on the key")
    ap.add_argument("--dir", default="fixtures/records")
    args = ap.parse_args()
    rows = query(args.url, args.ns, args.user, args.password,
                 'SELECT ID, "Key" FROM Shutter_Bridge.Record WHERE "Key" LIKE ? ORDER BY "Key"', [args.like])
    os.makedirs(args.dir, exist_ok=True)
    written, skipped = [], []
    for row in rows:
        m = KEY_RE.match(row["Key"])
        if not m:
            skipped.append(row["Key"])
            continue
        out = query(args.url, args.ns, args.user, args.password,
                    "SELECT Shutter_Util.Json_Export('Shutter.Bridge.Record', ?) AS j", [str(row["ID"])])
        j = out[0]["j"]
        d = json.loads(j) if isinstance(j, str) else j
        if isinstance(d.get("response"), str):
            d["response"] = json.loads(d["response"])
        if isinstance(d["response"].get("result"), str) and d["response"]["result"].startswith("{"):
            d["response"]["result"] = json.loads(d["response"]["result"])
        d.pop("id", None)
        ordered = {k: d[k] for k in ("key", "agentClass", "configVersion", "memberCode", "snapshotDigest", "correlationKey",
                                     "model", "response", "transcript", "toolCalls", "recordedAt", "label") if k in d}
        ordered = plain(ordered)
        name = file_name(m)
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
