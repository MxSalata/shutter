#!/usr/bin/env python3
"""Put the provider key into an IRIS instance's wallet and Config Store (AI.LLM.Shutter), from a file.

    python3 scripts/iris-set-key.py --url http://host:52773 --ns SHUTTER [--key-file <file>] [--model claude-opus-5-5]
    python3 scripts/iris-set-key.py --url http://host:52773 --ns SHUTTER --provider openai --key-file <file> [--model gpt-4.1]

The key travels as a SQL parameter in the request body, never in the query text or on the screen;
the instance's Shutter.Setup_ConfigureProvider stores it and answers with a status line only.
--provider is anthropic (the default) or openai; with no --model the instance takes the provider's own default.
A key set this way lasts until the production's next start finds another key, or another provider, in the
container's environment and writes that one instead.
Caveat: with SQL statement auditing switched on (off by default) IRIS would log the parameter value;
on such an instance set ANTHROPIC_API_KEY or OPENAI_API_KEY in the container's environment instead and restart the
production (Shutter.Production.OnStart writes the configuration from it).
"""
import argparse
import base64
import json
import os
import sys
import urllib.request


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", default=os.environ.get("IRIS_URL", "http://localhost:52773"))
    ap.add_argument("--ns", default="SHUTTER")
    ap.add_argument("--user", default=os.environ.get("IRIS_USER", "_SYSTEM"))
    ap.add_argument("--password", default=os.environ.get("IRIS_PASSWORD", "SYS"))
    ap.add_argument("--provider", default="anthropic", choices=["anthropic", "openai"], help="the provider the key is for; default anthropic")
    ap.add_argument("--key-file", default="", help="file holding the key (first line); default ~/.secrets/anthropic-api-key, or ~/.secrets/openai-api-key with --provider openai")
    ap.add_argument("--model", default="", help="the model; default the provider's own (claude-opus-5-5, or gpt-4.1 on OpenAI)")
    args = ap.parse_args()
    key_file = args.key_file or f"~/.secrets/{args.provider}-api-key"
    with open(os.path.expanduser(key_file), encoding="utf-8") as f:
        key = f.readline().strip()
    if not key:
        print("the key file is empty", file=sys.stderr)
        return 2
    # Anthropic's default model is named here as it always was; OpenAI's is left to the instance (an empty model).
    model = args.model or ("claude-opus-5-5" if args.provider == "anthropic" else "")
    body = json.dumps({"query": "SELECT Shutter.Setup_ConfigureProvider(?, ?, ?) AS r", "parameters": [key, model, args.provider]}).encode()
    token = base64.b64encode(f"{args.user}:{args.password}".encode()).decode()
    req = urllib.request.Request(args.url.rstrip("/") + f"/api/atelier/v1/{args.ns}/action/query", data=body, method="POST",
                                 headers={"Authorization": "Basic " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        out = json.loads(resp.read().decode())
    rows = out.get("result", {}).get("content", [])
    errors = out.get("status", {}).get("errors", [])
    if errors:
        print("IRIS:", json.dumps(errors)[:500], file=sys.stderr)
        return 1
    print(rows[0]["r"] if rows else out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
