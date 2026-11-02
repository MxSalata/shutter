#!/usr/bin/env python3
"""Check that Shutter's version is the same everywhere it is written, and that it equals a release tag when given one.
The IPM version must equal the GitHub tag: Open Exchange publishes module.xml's version to the package manager, and the
tag names the same commit.

    python3 scripts/check-versions.py [--root DIR] [--tag vX.Y.Z]
    python3 scripts/check-versions.py --print
    python3 scripts/check-versions.py --set X.Y.Z
    python3 scripts/check-versions.py --blank PATH < file

The places (a file that is missing, or a field it does not carry, is reported and fails the check, except the two
marked optional):
  module.xml                 the full package's <Version> (iris-shutter, the AI Hub build)
  core/module.xml            the core module's <Version> (iris-shutter-core, loaded by path on 2026.2)
  src/Shutter/Setup.cls      Parameter VERSION (optional), which the install records and /health reports
  web/package.json           "version"
  web/package-lock.json      "version" and packages[""].version
  web/src/mocks/fixtures.json  health.version (optional), the version the recorded demo shows
  www/                       the version the built web application embeds, only while web/src uses __APP_VERSION__

--print prints the version when every place agrees. --set writes X.Y.Z into every place (the release jobs in ci.yml use
it), changing nothing else in each file. --blank reads a file's text on stdin and prints it with its version fields
emptied, so that two copies can be compared beyond their version. Standard library only.
"""
import argparse
import glob
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

SEMVER = re.compile(r"\d+\.\d+\.\d+")

# Each pattern's first group ends just before the version and its second group starts just after it, so that --set and
# --blank change the version and nothing else. A module's <Version> follows its <Name>; so does a dependency's.
XML_VERSION = r"(<Name>(?:iris-shutter|iris-shutter-core)</Name>\s*<Version>)[^<]*(</Version>)"
PATTERNS = {
    "module.xml": [XML_VERSION],
    "core/module.xml": [XML_VERSION],
    "src/Shutter/Setup.cls": [r'(^Parameter VERSION = ")[^"]*(";)'],
    # The top-level "version" is the first one at two spaces' indent.
    "web/package.json": [r'(^  "version": ")[^"]*(")'],
    "web/package-lock.json": [r'(^  "version": ")[^"]*(")', r'(^  "packages": \{\s*"": \{\s*"name": "[^"]*",\s*"version": ")[^"]*(")'],
    # health holds only scalars before its version, so the match cannot leave the object.
    "web/src/mocks/fixtures.json": [r'(^ "health": \{[^{}]*?"version": ")[^"]*(")'],
}
OPTIONAL = {"src/Shutter/Setup.cls", "web/src/mocks/fixtures.json"}


def read(root, rel):
    path = os.path.join(root, rel)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def found(root):
    """Every place and the version it holds: a list of (place, version or None, note)."""
    out = []

    for rel, name in (("module.xml", "iris-shutter"), ("core/module.xml", "iris-shutter-core")):
        text = read(root, rel)
        if text is None:
            out.append((rel, None, "file missing"))
            continue
        try:
            module = ET.fromstring(text.encode("utf-8")).find("./Document/Module")
        except ET.ParseError as e:
            out.append((rel, None, f"not XML: {e}"))
            continue
        if module is None or module.findtext("Name") != name:
            out.append((rel, None, f"no <Module> named {name}"))
            continue
        out.append((f"{rel} <Version>", (module.findtext("Version") or "").strip(), ""))

    text = read(root, "src/Shutter/Setup.cls")
    m = re.search(PATTERNS["src/Shutter/Setup.cls"][0], text or "", re.M)
    if m:
        out.append(("src/Shutter/Setup.cls VERSION", text[m.end(1):m.start(2)], ""))

    for rel, fields in (("web/package.json", ["version"]), ("web/package-lock.json", ["version", "packages..version"])):
        text = read(root, rel)
        if text is None:
            out.append((rel, None, "file missing"))
            continue
        data = json.loads(text)
        out.append((f"{rel} version", data.get("version"), ""))
        if "packages..version" in fields:
            out.append((f'{rel} packages[""].version', data.get("packages", {}).get("", {}).get("version"), ""))

    text = read(root, "web/src/mocks/fixtures.json")
    if text is not None:
        health = json.loads(text).get("health")
        if isinstance(health, dict) and "version" in health:
            out.append(("web/src/mocks/fixtures.json health.version", health["version"], ""))

    # The build embeds the version only where the source reads __APP_VERSION__ (vite.config.ts defines it).
    uses = False
    for path in glob.glob(os.path.join(root, "web/src/**/*.ts*"), recursive=True):
        if path.endswith(".d.ts"):
            continue
        with open(path, encoding="utf-8") as f:
            if "__APP_VERSION__" in f.read():
                uses = True
                break
    if uses:
        pkg = json.loads(read(root, "web/package.json") or "{}").get("version", "")
        held = False
        for path in glob.glob(os.path.join(root, "www/assets/*.js")):
            with open(path, encoding="utf-8") as f:
                if f'"{pkg}"' in f.read():
                    held = True
                    break
        out.append(("www/ build", pkg if held and pkg else None, "" if held else "rebuild it: npm run build:www in web/"))
    return out


def substitute(rel, text, version):
    """The text with every version field of the file set to version; an error if a field is not found."""
    for pattern in PATTERNS[rel]:
        text, n = re.subn(pattern, lambda m: m.group(1) + version + m.group(2), text, flags=re.M)
        expected = 1
        if n != expected:
            raise ValueError(f"{rel}: {n} matches of a version field, expected {expected}")
    return text


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    ap.add_argument("--tag", help="a release tag, vX.Y.Z: every place must hold X.Y.Z")
    ap.add_argument("--print", action="store_true", help="print the agreed version only")
    ap.add_argument("--set", metavar="X.Y.Z", help="write this version into every place")
    ap.add_argument("--blank", metavar="PATH", help="print stdin, as the file PATH, with its version fields emptied")
    args = ap.parse_args()

    if args.blank:
        if args.blank not in PATTERNS:
            sys.exit(f"--blank: no version fields known for {args.blank}")
        text = sys.stdin.read()
        try:
            text = substitute(args.blank, text, "")
        except ValueError as e:
            # An optional field the file no longer carries blanks nothing; the comparison still sees every other byte.
            if args.blank not in OPTIONAL:
                sys.exit(str(e))
        sys.stdout.write(text)
        return 0

    if args.set:
        if not SEMVER.fullmatch(args.set):
            sys.exit(f"--set: '{args.set}' is not X.Y.Z")
        for rel in PATTERNS:
            text = read(args.root, rel)
            if text is None:
                if rel in OPTIONAL:
                    continue
                sys.exit(f"--set: {rel} is missing")
            try:
                new = substitute(rel, text, args.set)
            except ValueError as e:
                if rel in OPTIONAL:
                    continue
                sys.exit(f"--set: {e}")
            if new != text:
                with open(os.path.join(args.root, rel), "w", encoding="utf-8", newline="") as f:
                    f.write(new)

    places = found(args.root)
    want = None
    if args.tag:
        if not re.fullmatch(r"v\d+\.\d+\.\d+", args.tag):
            sys.exit(f"--tag: '{args.tag}' is not vX.Y.Z")
        want = args.tag[1:]
    elif args.set:
        want = args.set

    versions = {v for _, v, _ in places if v is not None}
    missing = [p for p, v, _ in places if v is None]
    agreed = len(versions) == 1 and not missing and all(SEMVER.fullmatch(v) for v in versions)
    ok = agreed and (want is None or versions == {want})

    if args.print:
        if not ok:
            sys.exit("The versions do not agree: run scripts/check-versions.py for the list")
        print(next(iter(versions)))
        return 0

    common = want or (next(iter(versions)) if len(versions) == 1 else None)
    width = max(len(p) for p, _, _ in places)
    for place, version, note in places:
        mark = "ok" if version is not None and version == common else "DIFFERS"
        print(f"{place.ljust(width)}  {version if version is not None else '-'}  {mark}" + (f"  ({note})" if note else ""))
    if ok:
        print(f"Every place holds {next(iter(versions))}" + (", the tag's version" if args.tag else ""))
        return 0
    if missing:
        print("Missing: " + ", ".join(missing))
    if want and agreed:
        print(f"The version is {next(iter(versions))}, the tag says {want}")
    else:
        print("The versions differ: " + ", ".join(sorted(versions)))
    return 1


if __name__ == "__main__":
    sys.exit(main())
