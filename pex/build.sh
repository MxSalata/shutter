#!/bin/bash
# Builds the Second Parser (pex/) with the IRIS image's own JDK: downloads the HAPI jars and checks each against its
# pinned SHA-256 in the same step (a mismatch stops the build and leaves no jar behind), compiles the Java sources against
# the PEX classes in IRIS's intersystems-utils and writes shutter-pex.jar. Usage: pex/build.sh [DEST]; DEST is the folder
# that holds lib/ (the jars) and shutter-pex.jar, /usr/irissys/mgr/shutter/pex by default (the production item's classpath).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-/usr/irissys/mgr/shutter/pex}"
IRIS_LIB="${IRIS_JAVA_LIB:-/usr/irissys/dev/java/lib/1.8}"
mkdir -p "$DEST/lib" "$DEST/classes"
# name  url  sha256
JARS='
hapi-base-2.6.0.jar https://repo1.maven.org/maven2/ca/uhn/hapi/hapi-base/2.6.0/hapi-base-2.6.0.jar 8e91877df2d0d5a0bd3bb3b670f624fe060344fc74e618e24d80aa0e86b31259
hapi-structures-v251-2.6.0.jar https://repo1.maven.org/maven2/ca/uhn/hapi/hapi-structures-v251/2.6.0/hapi-structures-v251-2.6.0.jar 5bfe9672f60b0d0a6a1455f2c173fb49b895dd17e19e675a2c932546defd5b01
slf4j-api-1.7.36.jar https://repo1.maven.org/maven2/org/slf4j/slf4j-api/1.7.36/slf4j-api-1.7.36.jar d3ef575e3e4979678dc01bf1dcce51021493b4d11fb7f1be8ad982877c16a1c0
commons-lang3-3.12.0.jar https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.12.0/commons-lang3-3.12.0.jar d919d904486c037f8d193412da0c92e22a9fa24230b9d67a57855c5c31c7e94e
joda-time-2.1.jar https://repo1.maven.org/maven2/joda-time/joda-time/2.1/joda-time-2.1.jar 5bce965a5e1dc1add255f1791a18521a7a5ecf36e436acb7ce2e5eda9d1a8e10
'
echo "$JARS" | while read -r name url sha; do
  [ -z "$name" ] && continue
  target="$DEST/lib/$name"
  if [ -f "$target" ] && echo "$sha  $target" | sha256sum -c --quiet - 2>/dev/null; then echo "kept $name"; continue; fi
  tmp="$target.part"; rm -f "$tmp"
  python3 - "$url" "$tmp" <<'PY'
import sys, urllib.request
url, out = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url, timeout=120) as r, open(out, "wb") as f:
    f.write(r.read())
PY
  if echo "$sha  $tmp" | sha256sum -c --quiet -; then mv "$tmp" "$target"; echo "downloaded $name (SHA-256 matches)"; else rm -f "$tmp"; echo "SHA-256 mismatch for $name: not kept" >&2; exit 1; fi
done
CP="$IRIS_LIB/intersystems-utils-4.2.3.jar:$IRIS_LIB/intersystems-jdbc-3.10.5.jar"
for j in "$DEST"/lib/*.jar; do CP="$CP:$j"; done
rm -rf "$DEST/classes"/*
javac --release 11 -Xlint:all -Werror -cp "$CP" -d "$DEST/classes" "$HERE"/src/shutter/pex/*.java
jar cf "$DEST/shutter-pex.jar.part" -C "$DEST/classes" .
mv "$DEST/shutter-pex.jar.part" "$DEST/shutter-pex.jar"
echo "built $DEST/shutter-pex.jar"
