#!/usr/bin/env python3
"""Copy the compiled Storage definition of each persistent class from an IRIS namespace back into its
source file, so that later property additions keep existing rows' columns in place.

    python3 scripts/iris-pull-storage.py [--url http://localhost:52773] [--ns INTERLOCK] PATH...

Without a Storage block in the source, every load regenerates the storage map in property order,
and a property added in the middle of a class shifts the data of rows saved before it. With the
block kept in the source, the compiler appends new properties to the existing map.
Credentials come from IRIS_USER and IRIS_PASSWORD (defaults _SYSTEM / SYS).
"""
import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request

CLASS_RE = re.compile(r"^\s*Class\s+([A-Za-z%][\w.]*)", re.MULTILINE)
STORAGE_RE = re.compile(r"^Storage\s+\w+\s*\n\{.*?\n\}\n", re.MULTILINE | re.DOTALL)


def fetch(url, ns, name, user, password):
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    req = urllib.request.Request(url.rstrip("/") + f"/api/atelier/v1/{ns}/doc/{name}",
                                 headers={"Authorization": "Basic " + token})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            doc = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return None, f"HTTP {e.code}"
    content = doc.get("result", {}).get("content", [])
    if not content:
        return None, "no content"
    return "\n".join(content), ""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--url", default=os.environ.get("IRIS_URL", "http://localhost:52773"))
    ap.add_argument("--ns", default=os.environ.get("IRIS_NAMESPACE", "INTERLOCK"))
    args = ap.parse_args()
    user, password = os.environ.get("IRIS_USER", "_SYSTEM"), os.environ.get("IRIS_PASSWORD", "SYS")

    files = []
    for p in args.paths:
        if os.path.isdir(p):
            for root, _d, names in os.walk(p):
                files += [os.path.join(root, n) for n in sorted(names) if n.endswith(".cls")]
        else:
            files.append(p)

    updated = added = unchanged = skipped = 0
    for f in files:
        with open(f, encoding="utf-8") as fh:
            local = fh.read()
        m = CLASS_RE.search(local)
        if not m:
            continue
        name = m.group(1)
        server, err = fetch(args.url, args.ns, name + ".cls", user, password)
        if server is None:
            print(f"skip {name}: {err}")
            skipped += 1
            continue
        sm = STORAGE_RE.search(server)
        if not sm:
            skipped += 1
            continue  # not persistent, or no storage yet
        storage = sm.group(0)
        lm = STORAGE_RE.search(local)
        if lm:
            if lm.group(0) == storage:
                unchanged += 1
                continue
            local = local[:lm.start()] + storage + local[lm.end():]
            updated += 1
        else:
            end = local.rstrip().rfind("}")
            local = local[:end].rstrip("\n") + "\n\n" + storage + "}\n"
            added += 1
        with open(f, "w", encoding="utf-8") as fh:
            fh.write(local)
        print(f"storage {'updated' if lm else 'added'}: {name}")
    print(f"added {added}, updated {updated}, unchanged {unchanged}, skipped {skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
