#!/usr/bin/env python3
"""Load ObjectScript sources into an IRIS namespace through the Atelier REST API and compile them.

    python3 scripts/iris-load.py [--url http://localhost:52773] [--ns SHUTTER] [--flags cuk] PATH...

Each PATH is a file or a directory searched for *.cls, *.inc and *.mac files. The document name comes from the
file's first `Class`, `ROUTINE` or `Include`-style header; a .cls file must start its class line with
`Class <Package.Name>`. Credentials come from IRIS_USER and IRIS_PASSWORD (defaults _SYSTEM / SYS).

Exit status 1 when a file fails to load or compile; the errors are printed.
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
ROUTINE_RE = re.compile(r"^\s*ROUTINE\s+([\w.]+)", re.MULTILINE)


def parse_api_json(raw):
    """The Atelier API's JSON, even when the call wrote to the console first: creating an interoperability
    namespace on IRIS for Health, for one, prints the HealthShare foundation's setup lines into the response
    body before the JSON. Returns (object, console_text)."""
    try:
        return json.loads(raw), ""
    except ValueError:
        pass
    start = raw.rfind('{"status":')
    if start < 0:
        start = raw.find("{")
    if start < 0:
        raise ValueError("no JSON in the response")
    return json.loads(raw[start:]), raw[:start].strip()


def opener_for(url):
    """An opener that keeps the CSP session cookie between calls, so repeated calls share one
    licence unit instead of opening a session each (which exhausts a Community licence)."""
    import http.cookiejar
    import hashlib
    cache = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "shutter")
    os.makedirs(cache, exist_ok=True)
    jar = http.cookiejar.MozillaCookieJar(os.path.join(cache, "cookies-" + hashlib.sha1(url.encode()).hexdigest()[:12] + ".txt"))
    try:
        jar.load(ignore_discard=True, ignore_expires=True)
    except (FileNotFoundError, http.cookiejar.LoadError):
        pass
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    return opener, jar


def doc_name(path, text):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".cls":
        m = CLASS_RE.search(text)
        if not m:
            raise ValueError(f"{path}: no 'Class <name>' line")
        return m.group(1) + ".cls"
    if ext in (".inc", ".mac", ".int"):
        m = ROUTINE_RE.search(text)
        base = m.group(1) if m else os.path.splitext(os.path.basename(path))[0]
        return base + ext
    raise ValueError(f"{path}: unsupported extension")


def collect(paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            for root, _dirs, names in os.walk(p):
                for n in sorted(names):
                    if n.lower().endswith((".cls", ".inc", ".mac", ".int")):
                        files.append(os.path.join(root, n))
        else:
            files.append(p)
    return files


class Atelier:
    def __init__(self, url, ns, user, password):
        self.base = url.rstrip("/") + "/api/atelier/v1/" + ns
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.headers = {"Authorization": "Basic " + token, "Content-Type": "application/json"}
        self.opener, self.jar = opener_for(url)

    def call(self, method, path, body=None, query=""):
        req = urllib.request.Request(self.base + path + query, method=method, headers=self.headers)
        data = json.dumps(body).encode() if body is not None else None
        try:
            with self.opener.open(req, data=data, timeout=300) as resp:
                result, console = parse_api_json(resp.read().decode(errors="replace"))
            if console:
                print(console[-2000:], file=sys.stderr)
            try:
                self.jar.save(ignore_discard=True, ignore_expires=True)
            except OSError:
                pass
            return result
        except urllib.error.HTTPError as e:
            payload = e.read().decode(errors="replace")
            try:
                return json.loads(payload)
            except ValueError:
                raise SystemExit(f"HTTP {e.code} on {method} {path}: {payload[:500]}")

    def put_doc(self, name, text):
        lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
        return self.call("PUT", "/doc/" + name, {"enc": False, "content": lines}, "?ignoreConflict=1")

    def compile(self, names, flags):
        return self.call("POST", "/action/compile", names, f"?flags={flags}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--url", default=os.environ.get("IRIS_URL", "http://localhost:52773"))
    ap.add_argument("--ns", default=os.environ.get("IRIS_NAMESPACE", "SHUTTER"))
    ap.add_argument("--flags", default="cuk", help="compile flags (default cuk)")
    ap.add_argument("--no-compile", action="store_true")
    args = ap.parse_args()

    api = Atelier(args.url, args.ns, os.environ.get("IRIS_USER", "_SYSTEM"), os.environ.get("IRIS_PASSWORD", "SYS"))
    files = collect(args.paths)
    if not files:
        raise SystemExit("nothing to load")

    names, failed = [], 0
    for f in files:
        with open(f, encoding="utf-8") as fh:
            text = fh.read()
        name = doc_name(f, text)
        result = api.put_doc(name, text)
        errors = result.get("status", {}).get("errors", [])
        if errors:
            failed += 1
            print(f"LOAD FAILED {name}: " + "; ".join(e.get("error", str(e)) for e in errors))
        else:
            names.append(name)
    print(f"loaded {len(names)} of {len(files)} documents into {args.ns}")

    if names and not args.no_compile:
        result = api.compile(names, args.flags)
        errors = result.get("status", {}).get("errors", [])
        console = result.get("console", [])
        bad = [line for line in console if "ERROR" in line or "error" in line.lower() and "0 error" not in line.lower()]
        for line in bad:
            print(line)
        if errors:
            failed += 1
            for e in errors:
                print("COMPILE ERROR: " + e.get("error", str(e)))
        if not errors and not bad:
            print(f"compiled {len(names)} documents ({args.flags})")
        elif bad and not errors:
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
