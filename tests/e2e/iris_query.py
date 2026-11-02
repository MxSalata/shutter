"""SQL over the Atelier REST API for the e2e checkers (the same call as scripts/iris-sql.py, as a function)."""
import base64
import json
import os
import urllib.request


def query(url, ns, sql, params=()):
    """Rows of one SQL statement as dicts. Credentials from IRIS_USER and IRIS_PASSWORD (defaults _SYSTEM / SYS)."""
    user = os.environ.get("IRIS_USER", "_SYSTEM")
    password = os.environ.get("IRIS_PASSWORD", "SYS")
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    body = json.dumps({"query": sql, "parameters": list(params)}).encode()
    req = urllib.request.Request(url.rstrip("/") + f"/api/atelier/v1/{ns}/action/query", data=body, method="POST",
                                 headers={"Authorization": "Basic " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as resp:
        raw = resp.read().decode(errors="replace")
    start = raw.rfind('{"status":')
    result = json.loads(raw[start:] if start > 0 else raw)
    errors = result.get("status", {}).get("errors", [])
    if errors:
        raise RuntimeError("SQL error: " + "; ".join(e.get("error", str(e)) for e in errors))
    return result.get("result", {}).get("content", [])
