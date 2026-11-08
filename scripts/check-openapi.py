#!/usr/bin/env python3
"""Check docs/api/openapi.json, the REST API's description, against src/Shutter/API/Dispatch.cls, the code that serves it:
every route of the UrlMap has an operation (its method, and its path with the /api/shutter base and {param} for :param)
and every operation has a route; the document is valid JSON with the fields its readers need (openapi 3.1, info.title,
info.version, and for every operation a summary, one tag the document declares, a response and the x-required-resource,
x-writes and x-contract fields); each operation's x-required-resource and x-writes say what the route's own Allow(...)
call in Dispatch says; every $ref resolves; every x-contract names a section docs/CONTRACTS.md has; and every {param} of
a path is declared as a path parameter.

    python3 scripts/check-openapi.py [--root DIR]

Prints each finding and exits 1 when there is one. Standard library only.
"""
import argparse
import json
import os
import re
import sys

BASE = "/api/shutter"
METHODS = ("get", "post", "put", "patch", "delete")
ROUTE = re.compile(r'<Route Url="([^"]+)" Method="(\w+)" Call="(\w+)"/>')
ALLOW = re.compile(r"\.\.Allow\(([^)]*)\)")
CALL = re.compile(r"\.\.(\w+)\(")
# The helpers a route calls that never hold its Allow: following them would find nothing, or another route's check.
PLUMBING = {
    "Allow", "Fail", "Json", "Body", "Idempotent", "Remember", "Project", "Rows", "User", "Require", "CaseOr404",
    "IncidentOr404", "OutageOr404", "PortalPath", "Me", "Health", "SiteProfileGet", "IdempotencyKey", "ClosureLimit",
    "PreviewWrote", "StoppedAfterTheGate", "ReasonFromEvent", "EscalationRefused", "IncidentSummary", "PlayerEnabled",
}


def methods_of(source):
    """Each ClassMethod of the class and its body text."""
    parts = re.split(r"\nClassMethod ", source)
    out = {}
    for part in parts[1:]:
        m = re.match(r"(\w+)\(", part)
        if m:
            out[m.group(1)] = part
    return out


def guard_of(name, methods, depth=0):
    """(resource, change) of a route method's Allow(...) call, following one delegation (IncidentApprove -> IncidentDecide).
    Allow() checks its default, Shutter_Operate; Allow("") checks only that someone is signed in, so its resource is None."""
    body = methods.get(name, "")
    m = ALLOW.search(body)
    if m:
        args = [a.strip() for a in m.group(1).split(",")] if m.group(1).strip() else []
        if not args or not args[0]:
            resource = "Shutter_Operate"
        else:
            resource = args[0].strip('"') or None
        change = len(args) > 1 and args[1] == "1"
        return resource, change
    if depth == 0:
        for called in CALL.findall(body):
            if called in methods and called not in PLUMBING and called != name:
                found = guard_of(called, methods, 1)
                if found is not None:
                    return found
    return None


def route_path(url):
    return BASE + re.sub(r":(\w+)", r"{\1}", url)


def refs_in(node, out):
    if isinstance(node, dict):
        if isinstance(node.get("$ref"), str):
            out.append(node["$ref"])
        for v in node.values():
            refs_in(v, out)
    elif isinstance(node, list):
        for v in node:
            refs_in(v, out)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    args = ap.parse_args()
    root = args.root
    doc_path = os.path.join(root, "docs", "api", "openapi.json")
    bad = []

    with open(os.path.join(root, "src", "Shutter", "API", "Dispatch.cls"), encoding="utf-8") as f:
        source = f.read()
    routes = ROUTE.findall(source)
    methods = methods_of(source)
    with open(os.path.join(root, "docs", "CONTRACTS.md"), encoding="utf-8") as f:
        sections = set(re.findall(r"^#{2,3} (\d+(?:\.\d+)?)[ .]", f.read(), re.M))

    try:
        with open(doc_path, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, ValueError) as e:
        print(f"docs/api/openapi.json: not valid JSON: {e}")
        return 1

    if not str(doc.get("openapi", "")).startswith("3.1"):
        bad.append(f"openapi is {doc.get('openapi')!r}, not 3.1.x")
    info = doc.get("info") or {}
    if not info.get("title"):
        bad.append("info.title is missing")
    if not re.fullmatch(r"\d+\.\d+\.\d+", str(info.get("version", ""))):
        bad.append(f"info.version is {info.get('version')!r}, not X.Y.Z")
    tags = {t.get("name") for t in doc.get("tags", []) if isinstance(t, dict)}

    operations = {}
    for path, item in (doc.get("paths") or {}).items():
        if not path.startswith(BASE + "/"):
            bad.append(f"{path}: not under {BASE}")
        for method, op in item.items():
            if method not in METHODS:
                continue
            key = (method.upper(), path)
            operations[key] = op
            where = f"{method.upper()} {path}"
            if not op.get("summary"):
                bad.append(f"{where}: no summary")
            op_tags = op.get("tags") or []
            if len(op_tags) != 1:
                bad.append(f"{where}: {len(op_tags)} tags, expected one")
            elif op_tags[0] not in tags:
                bad.append(f"{where}: tag {op_tags[0]!r} is not declared in the document's tags")
            responses = op.get("responses") or {}
            if not any(code.startswith("2") for code in responses):
                bad.append(f"{where}: no 2xx response")
            for code, response in responses.items():
                if not isinstance(response, dict) or not response.get("description"):
                    bad.append(f"{where}: response {code} has no description")
            if not isinstance(op.get("x-writes"), bool):
                bad.append(f"{where}: x-writes is not true or false")
            if "x-required-resource" not in op:
                bad.append(f"{where}: no x-required-resource (null when the route checks none)")
            contract = op.get("x-contract") or ""
            m = re.search(r"section (\d+(?:\.\d+)?)$", contract)
            if not m:
                bad.append(f"{where}: x-contract {contract!r} does not name a CONTRACTS section")
            elif m.group(1) not in sections:
                bad.append(f"{where}: x-contract names section {m.group(1)}, which docs/CONTRACTS.md has not")
            declared = set()
            for p in (item.get("parameters") or []) + (op.get("parameters") or []):
                if isinstance(p, dict) and isinstance(p.get("$ref"), str):
                    p = (doc.get("components", {}).get("parameters") or {}).get(p["$ref"].split("/")[-1], {})
                if p.get("in") == "path":
                    declared.add(p.get("name"))
                    if not p.get("required"):
                        bad.append(f"{where}: path parameter {p.get('name')} is not required")
            for name in re.findall(r"\{(\w+)\}", path):
                if name not in declared:
                    bad.append(f"{where}: {{{name}}} is not declared as a path parameter")

    wanted = {}
    for url, method, call in routes:
        wanted[(method, route_path(url))] = call
    for key, call in wanted.items():
        if key not in operations:
            bad.append(f"{key[0]} {key[1]} (Dispatch.{call}): no operation in the document")
            continue
        op = operations[key]
        where = f"{key[0]} {key[1]}"
        guard = guard_of(call, methods)
        resource = op.get("x-required-resource")
        resources = set(resource) if isinstance(resource, list) else ({resource} if resource else set())
        if guard is None:
            if resources:
                bad.append(f"{where}: x-required-resource {sorted(resources)} but Dispatch.{call} calls no Allow")
            if op.get("x-writes"):
                bad.append(f"{where}: x-writes true but Dispatch.{call} calls no Allow")
        else:
            want_resource, want_change = guard
            if want_resource is None:
                if resources:
                    bad.append(f"{where}: x-required-resource {sorted(resources)} but Dispatch.{call} needs only a sign-in")
            elif want_resource not in resources:
                bad.append(f"{where}: x-required-resource {sorted(resources)} but Dispatch.{call} needs {want_resource}")
            if bool(op.get("x-writes")) != want_change:
                bad.append(f"{where}: x-writes {op.get('x-writes')} but Dispatch.{call} is {'a change' if want_change else 'a read'}")
    for key in operations:
        if key not in wanted:
            bad.append(f"{key[0]} {key[1]}: no such route in Dispatch.cls")

    components = doc.get("components") or {}
    for ref in sorted(set(refs_in(doc, []))):
        m = re.fullmatch(r"#/components/(\w+)/([\w.-]+)", ref)
        if not m or m.group(2) not in (components.get(m.group(1)) or {}):
            bad.append(f"{ref}: does not resolve")

    for line in bad:
        print(line)
    if bad:
        print(f"{len(bad)} finding{'s' if len(bad) != 1 else ''}")
        return 1
    print(f"{len(wanted)} routes in Dispatch.cls, {len(operations)} operations in docs/api/openapi.json: they match")
    return 0


if __name__ == "__main__":
    sys.exit(main())
