#!/usr/bin/env python3
"""Records GET /api/shutter/catalogue and GET /api/shutter/site-profile from a demo install of this tree, signed in as
the demo's operator, and prints what web/src/mocks/catalogue-recorded.json holds: the trial's GET /catalogue serves that
answer, and web/src/mocks/atReceivers.test.ts holds the mock's atReceivers to it.

    python3 scripts/record-catalogue.py http://127.0.0.1:52773 > web/src/mocks/catalogue-recorded.json

Run it on an instance just after the iris job's setup steps (namespace, load, install, hospital, records), before any
test changes the site profile. Standard library only."""
import http.cookiejar
import json
import sys
import urllib.request

url = sys.argv[1].rstrip("/") + "/api/shutter"
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Requested-With", "XMLHttpRequest")
    with opener.open(req, timeout=60) as r:
        return json.loads(r.read().decode())


call("POST", "/session", {"username": "operator", "password": "shutter"})
health = call("GET", "/health")
profile = call("GET", "/site-profile")
catalogue = call("GET", "/catalogue")
out = {
    "note": (
        "GET /api/shutter/catalogue and GET /api/shutter/site-profile as a demo install of this tree answered them, "
        "signed in as the demo's operator, with no site entry. Recorded on a stock IRIS for Health Community 2026.2 "
        "container: the iris job's setup steps (namespace, load, install, hospital, records), then one sign-in and the two "
        "reads (scripts/record-catalogue.py). Record again whenever the shipped catalogue or Matcher.AtReceiver changes: atReceivers.test.ts says when."
    ),
    "release": health.get("version", ""),
    "gatePolicyVersion": health.get("gate_policy_version", ""),
    "siteProfile": profile,
    "catalogue": catalogue,
}
print(json.dumps(out, indent=1, ensure_ascii=False))
