#!/usr/bin/env python3
"""Run the FHIR conformance exchanges over HTTP against a FHIR R4 server: IRIS for Health's own, or the test FHIR server.

    python3 tests/conformance/fhir_conformance.py --base URL --target iris|facade [--user U] [--prefix P] [--file F]
                                                   [--proof FILE]

Sends every exchange of tests/conformance/fhir-facade-v1.json whose targets include --target, in order, and checks each
answer against what was measured on IRIS. --base is the endpoint's base URL (http://host:port/fhir/r4). The password
comes from FHIR_PASSWORD (with --user; no Authorization header without --user). --prefix goes in front of every id and
identifier value the file uses, so a run on a server that already holds an earlier run's resources stays apart; it
defaults to a fresh one for iris, and to none for facade, whose run starts with POST {base}/admin/reset (the user needs
the reset resource). Prints a line per exchange and exits 1 when one differs. Standard library only.

--proof FILE writes the proof document that Shutter.Store.FHIRProof imports for a receiver: the file's name and the
SHA-256 of its bytes, the target, the base, the time, the server software and FHIR version the run's own GET metadata
answered, the number of exchanges, and the three measurements with the exchange each rests on. It is written only when
no exchange differs; when one does, or when the run cannot name the software or lacks a measurement, nothing is written,
a file already at FILE is removed so that no earlier run's proof is left standing, and the exit status is 1.
"""
import argparse
import base64
import datetime
import hashlib
import json
import os
import pathlib
import secrets
import sys
import urllib.error
import urllib.request

FILE = pathlib.Path(__file__).resolve().parent / "fhir-facade-v1.json"
# The proof's measurements, each resting on exactly one exchange of the file.
MEASUREMENTS = (("if_match_stale_refused", "m3-update-stale"), ("if_match_unknown_id_refused", "m5-if-match-unknown-id"),
                ("tags_kept", "m8-history-tags"))


def subst(text, vars_):
    for name, value in vars_.items():
        text = text.replace("{" + name + "}", value)
    return text


def walk(doc, path):
    """(value, found) at a path such as meta.tag[0].code."""
    here = doc
    for part in path.split("."):
        name, _, index = part.partition("[")
        if name:
            if not isinstance(here, dict) or name not in here:
                return None, False
            here = here[name]
        if index:
            i = int(index.rstrip("]"))
            if not isinstance(here, list) or i >= len(here):
                return None, False
            here = here[i]
    return here, True


def canon(value, vars_):
    return json.loads(subst(json.dumps(value, ensure_ascii=False), vars_))


def proof_document(kit, kit_sha256, target, base, measured_at, metadata, results):
    """(document, "") for a run in which nothing differed, or (None, why). results is {exchange id: passed} for every
    exchange that ran; metadata is the body the run's own GET metadata answered."""
    differ = sum(1 for passed in results.values() if not passed)
    if differ:
        return None, "exchanges that differ: %d" % differ
    try:
        statement = json.loads(metadata)
    except (TypeError, ValueError):
        statement = None
    if not isinstance(statement, dict):
        return None, "the run read no CapabilityStatement"
    software = statement.get("software") if isinstance(statement.get("software"), dict) else {}
    name, version, fhir_version = software.get("name"), software.get("version"), statement.get("fhirVersion")
    for label, value in (("software.name", name), ("software.version", version), ("fhirVersion", fhir_version)):
        if not isinstance(value, str) or not value:
            return None, "the CapabilityStatement has no " + label
    measurements = {}
    for key, exchange in MEASUREMENTS:
        if exchange not in results:
            return None, "the run did not include the exchange %s" % exchange
        measurements[key] = {"exchange": exchange, "passed": True}
    return {"kit": kit, "kit_sha256": kit_sha256, "target": target, "base": base, "measured_at": measured_at,
            "software": {"name": name, "version": version}, "fhir_version": fhir_version, "exchanges": len(results),
            "differ": 0, "measurements": measurements}, ""


def header(headers, name):
    for k, v in headers.items():
        if k.lower() == name.lower():
            return v
    return ""


class Runner:
    def __init__(self, base, user, password, prefix):
        self.base = base.rstrip("/")
        self.auth = None
        if user:
            self.auth = "Basic " + base64.b64encode(("%s:%s" % (user, password)).encode()).decode()
        self.vars = {"p": prefix, "P": prefix.upper()}

    def send(self, method, path, headers, body):
        url = self.base + "/" + path if path else self.base + "/"
        data = body.encode("utf-8") if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Accept", "application/fhir+json")
        for k, v in headers.items():
            req.add_header(k, v)
        if self.auth:
            req.add_header("Authorization", self.auth)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return resp.status, dict(resp.headers.items()), resp.read().decode("utf-8")
        except urllib.error.HTTPError as err:
            return err.code, dict(err.headers.items()), err.read().decode("utf-8", "replace")

    def exchange(self, x):
        r = x["request"]
        if r["method"] == "RESET":
            status, headers, body = self.send("POST", "admin/reset", {}, "")
            return status, headers, body
        path = subst(r["path"], self.vars)
        hdrs = {k: subst(v, self.vars) for k, v in r.get("headers", {}).items()}
        body = subst(r["body"], self.vars) if "body" in r else None
        return self.send(r["method"], path, hdrs, body)

    def capture(self, x, headers, body):
        for name, how in x.get("capture", {}).items():
            if how == "etag_vid":
                etag = header(headers, "ETag")
                self.vars[name] = etag[3:-1] if etag.startswith('W/"') and etag.endswith('"') else ""
            elif how == "body":
                self.vars[name] = body
            elif how == "link_next":
                url = ""
                try:
                    url = next((l["url"] for l in json.loads(body).get("link", []) if l.get("relation") == "next"), "")
                except ValueError:
                    pass
                if url.startswith(self.base + "/"):
                    url = url[len(self.base) + 1:]
                self.vars[name] = url

    def check(self, expect, status, headers, raw):
        out = []
        v = self.vars
        if "status" in expect and status != expect["status"]:
            out.append("status %s, expected %s: %s" % (status, expect["status"], raw[:300]))
        for name, want in expect.get("headers", {}).items():
            actual = header(headers, name)
            if isinstance(want, dict):
                if want.get("absent") and actual:
                    out.append("%s is %s, expected none" % (name, actual))
                if want.get("present") and not actual:
                    out.append("%s is missing" % name)
                if "endswith" in want and not actual.endswith(subst(want["endswith"], v)):
                    out.append("%s is %s, expected it to end %s" % (name, actual, subst(want["endswith"], v)))
            elif name == "Content-Type":
                if actual.split(";")[0].strip().lower() != want.lower():
                    out.append("%s is %s, expected %s" % (name, actual, want))
            elif actual != subst(want, v):
                out.append("%s is %s, expected %s" % (name, actual, subst(want, v)))
        want = expect.get("body")
        if not want:
            return out
        if want.get("empty") and raw:
            out.append("the body is not empty: " + raw[:200])
        for text in want.get("contains", []):
            if subst(text, v) not in raw:
                out.append("the body does not contain %s: %s" % (subst(text, v), raw[:600]))
        if "same_as" in want and raw != v.get(want["same_as"]):
            out.append("the body differs from %s" % want["same_as"])
        if not any(k in want for k in ("outcome", "has", "absent", "keys", "resource", "bundle", "capability")):
            return out
        try:
            doc = json.loads(raw)
        except ValueError:
            return out + ["the body is not JSON: " + raw[:200]]
        if "outcome" in want:
            issue, found = walk(doc, "issue[0]")
            if not found:
                out.append("no OperationOutcome issue: " + raw[:200])
            else:
                for key, value in want["outcome"].items():
                    actual = issue.get("details", {}).get("text") if key == "text" else issue.get(key)
                    value = canon(value, v)
                    if actual != value:
                        out.append("issue %s is %r, expected %r" % (key, actual, value))
        for path, value in want.get("has", {}).items():
            actual, found = walk(doc, path)
            if not found:
                out.append(path + " is missing")
            elif actual != canon(value, v):
                out.append("%s is %s, expected %s" % (path, json.dumps(actual), json.dumps(canon(value, v))))
        for path in want.get("absent", []):
            if walk(doc, path)[1]:
                out.append(path + " is present")
        if "keys" in want and list(doc) != want["keys"]:
            out.append("the keys are %s, expected %s" % (list(doc), want["keys"]))
        if "resource" in want:
            masked = json.loads(raw, object_pairs_hook=lambda pairs: pairs)
            expected = json.loads(json.dumps(canon(want["resource"], v)), object_pairs_hook=lambda pairs: pairs)

            def mask(pairs):
                return [(k, [(mk, "*" if mk == "lastUpdated" else mv) for mk, mv in val] if k == "meta" and isinstance(val, list) else val) for k, val in pairs]
            if mask(masked) != expected:
                out.append("the resource differs: %s" % raw[:600])
        if "bundle" in want:
            out += self.check_bundle(want["bundle"], doc)
        for rtype, fields in want.get("capability", {}).items():
            entry = next((r for r in walk(doc, "rest[0].resource")[0] or [] if r.get("type") == rtype), None)
            if entry is None:
                out.append("the CapabilityStatement has no " + rtype)
                continue
            for name, value in fields.items():
                actual = [i.get("code") for i in entry.get("interaction", [])] if name == "interaction" else entry.get(name)
                if actual != value:
                    out.append("%s %s is %r, expected %r" % (rtype, name, actual, value))
        return out

    def check_bundle(self, want, doc):
        out = []
        entries = doc.get("entry", [])
        if "type" in want and doc.get("type") != want["type"]:
            out.append("Bundle type %s, expected %s" % (doc.get("type"), want["type"]))
        if "total" in want and doc.get("total") != want["total"]:
            out.append("Bundle total %s, expected %s" % (doc.get("total"), want["total"]))
        if "count" in want and len(entries) != want["count"]:
            out.append("Bundle has %d entries, expected %d" % (len(entries), want["count"]))
        if "links" in want:
            rels = [l.get("relation") for l in doc.get("link", [])]
            if rels != want["links"]:
                out.append("Bundle links %s, expected %s" % (rels, want["links"]))
        for i, w in enumerate(want.get("entries", [])):
            if i >= len(entries):
                out.append("entry %d is missing" % i)
                continue
            e = entries[i]
            res = e.get("resource", {})
            got = {"id": res.get("id"), "versionId": res.get("meta", {}).get("versionId"), "method": e.get("request", {}).get("method"),
                   "url": e.get("request", {}).get("url"), "status": e.get("response", {}).get("status"), "mode": e.get("search", {}).get("mode"),
                   "resource": "resource" in e, "fullUrl": "fullUrl" in e, "etag": "etag" in e.get("response", {}),
                   "tags": ["%s|%s" % (t.get("system"), t.get("code")) for t in res.get("meta", {}).get("tag", [])]}
            for name, value in w.items():
                value = canon(value, self.vars)
                if got.get(name) != value:
                    out.append("entry %d %s is %r, expected %r" % (i, name, got.get(name), value))
        return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", required=True)
    parser.add_argument("--target", required=True, choices=("iris", "facade"))
    parser.add_argument("--user")
    parser.add_argument("--prefix")
    parser.add_argument("--file", default=str(FILE))
    parser.add_argument("--proof", metavar="FILE", help="write the proof document here when no exchange differs")
    args = parser.parse_args()
    prefix = args.prefix if args.prefix is not None else ("r" + secrets.token_hex(3) + "-" if args.target == "iris" else "")
    raw = pathlib.Path(args.file).read_bytes()
    doc = json.loads(raw.decode("utf-8"))
    runner = Runner(args.base, args.user, os.environ.get("FHIR_PASSWORD", ""), prefix)
    if args.target == "facade":
        status = runner.send("POST", "admin/reset", {}, "")[0]
        if status != 200:
            print("the reset answered %s" % status)
            return 1
    ran = failed = 0
    results, metadata = {}, None
    for x in doc["exchanges"]:
        if args.target not in x["targets"]:
            continue
        ran += 1
        status, headers, body = runner.exchange(x)
        problems = runner.check(x["expect"], status, headers, body)
        runner.capture(x, headers, body)
        results[x["id"]] = not problems
        if x["request"]["method"] == "GET" and x["request"].get("path") == "metadata" and status == 200:
            metadata = body
        print(("ok    " if not problems else "DIFF  ") + x["id"] + ("" if not problems else ": " + "; ".join(problems)))
        failed += bool(problems)
    print("%d exchanges against %s (%s), prefix %r: %d as measured, %d differ" % (ran, args.base, args.target, prefix, ran - failed, failed))
    if args.proof and not write_proof(args, runner, raw, results, metadata):
        return 1
    return 1 if failed else 0


def write_proof(args, runner, raw, results, metadata):
    """Writes the proof document, or removes the file and says why it was not written."""
    path = pathlib.Path(args.proof)
    if metadata is None and not any(not passed for passed in results.values()):
        status, _, body = runner.send("GET", "metadata", {}, None)
        metadata = body if status == 200 else None
    measured_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    document, why = proof_document(pathlib.Path(args.file).name, hashlib.sha256(raw).hexdigest(), args.target, runner.base,
                                   measured_at, metadata, results)
    if document is None:
        if path.exists():
            path.unlink()
        print("no proof written to %s: %s" % (path, why))
        return False
    path.write_text(json.dumps(document, indent=1, ensure_ascii=True) + "\n", encoding="utf-8")
    print("proof written to %s: %s %s, %d exchanges, none differ" % (path, document["software"]["name"], document["software"]["version"], document["exchanges"]))
    return True


if __name__ == "__main__":
    sys.exit(main())
