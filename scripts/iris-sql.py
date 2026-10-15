#!/usr/bin/env python3
"""Run a SQL statement in an IRIS namespace through the Atelier REST API and print the rows.

    python3 scripts/iris-sql.py [--url http://localhost:52773] [--ns INTERLOCK] [--json] "SELECT ..." [param ...]

Class methods marked [ SqlProc ] are called as functions: "SELECT Interlock.Setup_Install() AS result".
Credentials come from IRIS_USER and IRIS_PASSWORD (defaults _SYSTEM / SYS).
"""
import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request


def opener_for(url):
    """An opener that keeps the CSP session cookie between calls, so repeated calls share one
    licence unit instead of opening a session each (which exhausts a Community licence)."""
    import http.cookiejar
    import hashlib
    cache = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "interlock")
    os.makedirs(cache, exist_ok=True)
    jar = http.cookiejar.MozillaCookieJar(os.path.join(cache, "cookies-" + hashlib.sha1(url.encode()).hexdigest()[:12] + ".txt"))
    try:
        jar.load(ignore_discard=True, ignore_expires=True)
    except (FileNotFoundError, http.cookiejar.LoadError):
        pass
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    return opener, jar



def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sql")
    ap.add_argument("params", nargs="*")
    ap.add_argument("--url", default=os.environ.get("IRIS_URL", "http://localhost:52773"))
    ap.add_argument("--ns", default=os.environ.get("IRIS_NAMESPACE", "INTERLOCK"))
    ap.add_argument("--json", action="store_true", help="print the result rows as JSON")
    args = ap.parse_args()

    user = os.environ.get("IRIS_USER", "_SYSTEM")
    password = os.environ.get("IRIS_PASSWORD", "SYS")
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    url = args.url.rstrip("/") + "/api/atelier/v1/" + args.ns + "/action/query"
    body = json.dumps({"query": args.sql, "parameters": args.params}).encode()
    req = urllib.request.Request(url, data=body, method="POST",
                                 headers={"Authorization": "Basic " + token, "Content-Type": "application/json"})
    opener, jar = opener_for(args.url)
    try:
        with opener.open(req, timeout=600) as resp:
            raw = resp.read().decode(errors="replace")
        try:
            jar.save(ignore_discard=True, ignore_expires=True)
        except OSError:
            pass
        try:
            result = json.loads(raw)
        except ValueError:
            raise SystemExit("not a JSON response: " + raw[:800])
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code}: {e.read().decode(errors='replace')[:800]}")

    errors = result.get("status", {}).get("errors", [])
    if errors:
        for e in errors:
            print("SQL ERROR: " + e.get("error", str(e)), file=sys.stderr)
        return 1
    rows = result.get("result", {}).get("content", [])
    if args.json:
        print(json.dumps(rows, indent=1))
        return 0
    if not rows:
        print("(no rows)")
        return 0
    cols = list(rows[0].keys())
    widths = [max(len(c), *(len(str(r.get(c, ""))) for r in rows)) for c in cols]
    print(" | ".join(c.ljust(w) for c, w in zip(cols, widths)))
    print("-+-".join("-" * w for w in widths))
    for r in rows:
        print(" | ".join(str(r.get(c, "")).ljust(w) for c, w in zip(cols, widths)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
