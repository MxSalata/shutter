#!/usr/bin/env python3
"""Fails when a credential appears in the repository: in a tracked file, or in what the last commits added.

    python3 scripts/secret-scan.py [--commits 20]

Looks for the token formats that leak most often (Anthropic, OpenAI, GitHub, AWS, Google, Slack keys and private key
blocks) and for a committed `.env` (only `.env.example` belongs in the repository). The demo's published passwords
(the README's Online demo line) are public on purpose and not matched. A finding prints its file, line or commit and the
kind of secret, with the value masked. Exit status 1 when anything is found. Standard library only.
"""
import argparse
import re
import subprocess
import sys

PATTERNS = {
    "Anthropic API key": re.compile(r"sk-ant-[A-Za-z0-9_-]{20,}"),
    "OpenAI API key": re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9]{32,}"),
    "GitHub token": re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}\b|\bgithub_pat_[A-Za-z0-9_]{40,}"),
    "AWS access key id": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "Google API key": re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
    "Slack token": re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"),
    "Private key": re.compile(r"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----"),
}


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def mask(value):
    return value[:6] + "..." + f"({len(value)} characters)"


def scan_text(text):
    for n, line in enumerate(text.splitlines(), 1):
        for kind, pattern in PATTERNS.items():
            for m in pattern.finditer(line):
                yield n, kind, mask(m.group(0))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--commits", type=int, default=20, help="how many recent commits' additions to scan (default 20)")
    args = ap.parse_args()
    found = []
    for path in git("ls-files", "-z").split("\0"):
        if not path:
            continue
        name = path.rsplit("/", 1)[-1]
        if name == ".env" or (name.startswith(".env.") and name != ".env.example"):
            found.append(f"{path}: a committed environment file (only .env.example belongs here)")
            continue
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
            continue
        for n, kind, value in scan_text(text):
            found.append(f"{path}:{n}: {kind} {value}")
    # What the recent commits added, so a secret committed and then removed is caught while it is still recent
    count = int(git("rev-list", "--count", "HEAD").strip() or 0)
    if count:
        log = git("log", f"-{min(args.commits, count)}", "-p", "--no-color", "--format=commit %H", "--unified=0")
        commit = ""
        for line in log.splitlines():
            if line.startswith("commit "):
                commit = line[7:19]
            elif line.startswith("+") and not line.startswith("+++"):
                for _, kind, value in scan_text(line[1:]):
                    found.append(f"commit {commit}: {kind} {value}")
    for f in found:
        print(f)
    print(f"{len(found)} finding(s)" if found else "no secrets found")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
