#!/usr/bin/env python3
"""Check that the repository's text has no em dash (U+2014) and no en dash (U+2013).

    python3 scripts/check-text.py [--messages REV_RANGE]

Reads every text file git tracks, except the built web application (www/, made from web/, which is read) and the
vendored package manager installer (vendor/). With --messages, also reads the messages of the commits in REV_RANGE
(for example the commits a push brings). Prints each finding with its file and line, and exits 1 when there is one.
Standard library only.
"""
import argparse
import subprocess
import sys

SKIP = ("www/", "vendor/")
DASHES = {"\u2014": "em dash", "\u2013": "en dash"}


def findings(text):
    """(line, what) for each em or en dash in text, once per line and kind."""
    out = []
    for n, line in enumerate(text.split("\n"), 1):
        for c, what in DASHES.items():
            if c in line:
                out.append((n, what))
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
    read = f"{len(files)} files" + (f" and {commits} commit messages" if args.messages else "")
    print(f"{read} have no em or en dash")
    return 0


if __name__ == "__main__":
    sys.exit(main())
