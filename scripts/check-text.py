#!/usr/bin/env python3
"""Check the repository's text against its writing rules: no em dash (U+2014) or en dash (U+2013) anywhere, and no
Co-Authored-By trailer.

    python3 scripts/check-text.py [--messages REV_RANGE]

Reads every text file git tracks, except the built web application (www/, made from web/, which is read) and the
vendored package manager installer (vendor/). With --messages, also reads the messages of the commits in REV_RANGE
(for example the commits a push brings). Prints each finding with its file and line, and exits 1 when there is one.
Standard library only.
"""
import argparse
import re
import subprocess
import sys

SKIP = ("www/", "vendor/")
DASHES = {"\u2014": "em dash", "\u2013": "en dash"}
TRAILER = re.compile(r"^\s*co-authored-by:", re.IGNORECASE | re.MULTILINE)


def findings(text):
    """(line, what) for each break of the rules in text."""
    out = []
    for n, line in enumerate(text.split("\n"), 1):
        for c, what in DASHES.items():
            if c in line:
                out.append((n, what))
    for m in TRAILER.finditer(text):
        out.append((text.count("\n", 0, m.start()) + 1, "a Co-Authored-By trailer"))
    return out


def tracked_files():
    names = subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=True).stdout.decode().split("\0")
    return [n for n in names if n and not n.startswith(SKIP)]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--messages", metavar="REV_RANGE", help="also check these commits' messages")
    args = parser.parse_args()
    bad = 0
    files = tracked_files()
    for path in files:
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
            continue
        for n, what in findings(text):
            print(f"{path}:{n}: {what}")
            bad += 1
    commits = 0
    if args.messages:
        log = subprocess.run(["git", "log", "--format=%H%x00%B%x01", args.messages], capture_output=True, check=True)
        for entry in log.stdout.decode().split("\x01"):
            sha, _, body = entry.strip("\n").partition("\x00")
            if not sha:
                continue
            commits += 1
            for n, what in findings(body):
                print(f"commit {sha[:7]}, message line {n}: {what}")
                bad += 1
    if bad:
        print(f"{bad} finding(s)")
        return 1
    print(f"{len(files)} files" + (f" and {commits} commit messages" if args.messages else "") + " keep the rules")
    return 0


if __name__ == "__main__":
    sys.exit(main())
