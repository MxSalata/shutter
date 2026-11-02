#!/usr/bin/env python3
"""Print the source files an IPM module's class resources name, one per line, for a load by path that must leave the other
module's classes out (the plain 2026.2 image cannot compile the agents' classes, which need the %AI package).

    python3 scripts/module-sources.py core/module.xml

A resource X.Y.PKG is every .cls under <SourcesRoot>/X/Y/; a resource X.Y.CLS is <SourcesRoot>/X/Y.cls. Folder resources
(/knowledge/ and the like) are not sources and are left out. Paths are printed relative to the repository root, so the
output goes straight to scripts/iris-load.py. Exit status 1 when a named file is missing.
"""
import os
import sys
import xml.etree.ElementTree as ET


def main():
    if len(sys.argv) != 2:
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    manifest = sys.argv[1]
    here = os.path.dirname(os.path.abspath(manifest))
    repo = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    module = ET.parse(manifest).getroot().find("./Document/Module")
    root = os.path.normpath(os.path.join(here, module.findtext("SourcesRoot") or "src"))
    missing = 0
    for res in module.findall("Resource"):
        name = res.get("Name", "")
        if name.startswith("/"):
            continue
        if name.endswith(".PKG"):
            folder = os.path.join(root, *name[:-4].split("."))
            if not os.path.isdir(folder):
                print(f"missing package folder: {folder}", file=sys.stderr)
                missing += 1
                continue
            for dirpath, _, files in sorted(os.walk(folder)):
                for f in sorted(files):
                    if f.endswith(".cls"):
                        print(os.path.relpath(os.path.join(dirpath, f), repo))
        elif name.endswith(".CLS"):
            path = os.path.join(root, *name[:-4].split(".")) + ".cls"
            if not os.path.isfile(path):
                print(f"missing class file: {path}", file=sys.stderr)
                missing += 1
                continue
            print(os.path.relpath(path, repo))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
