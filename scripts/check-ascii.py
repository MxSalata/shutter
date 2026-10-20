#!/usr/bin/env python3
"""Check that files are plain ASCII: printable characters, tabs and line ends only. Open Exchange's reader of module.xml
keeps only the low byte of each character, so a character outside ASCII breaks the publish to the package manager (an
en dash, U+2013, becomes 0x13, which XML does not allow: "invalid character 0x13").

    python3 scripts/check-ascii.py module.xml aihub/module.xml

Prints each character outside ASCII with its line and code point, and exits 1 when there is one. Standard library only.
"""
import sys


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: check-ascii.py FILE...")
    bad = 0
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8", newline="") as f:
            lines = f.read().split("\n")
        for n, line in enumerate(lines, 1):
            for c in line:
                if c not in "\t\r" and not " " <= c <= "~":
                    print(f"{path}:{n}: U+{ord(c):04X}")
                    bad += 1
    if bad:
        print(f"{bad} character(s) outside plain ASCII")
        return 1
    print("Plain ASCII: " + ", ".join(sys.argv[1:]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
