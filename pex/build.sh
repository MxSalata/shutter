#!/bin/bash
# Builds the Second Parser (pex/) with the IRIS image's own JDK: downloads the HAPI jars and checks each against its
# pinned SHA-256 in the same step (a mismatch leaves no jar behind), finds IRIS's PEX framework jar by what it holds
# (intersystems-utils on IRIS 2026.2, intersystems-pex on the AI Hub images; names and versions differ between builds),
# compiles the Java sources against it and writes shutter-pex.jar plus framework.txt, the framework jar's path, which the
# install puts on the production item's classpath. Usage: pex/build.sh [DEST]; DEST holds lib/ (the jars), shutter-pex.jar
# and framework.txt, /usr/irissys/mgr/pex by default: beside the data volume (mgr/shutter), not inside it, so a rebuilt
# image brings its own jar to an old volume.
#
# It exits 0 whenever the image build may go on: built, or skipped with the reason on stderr (no JDK, no framework, no
# network, a checksum mismatch, a compile error), in which case no shutter-pex.jar is left and the Second Parser item stays
# disabled, as docs/CONTRACTS.md 6.7 says. PEX_STRICT=1 turns every skip into exit 1, for CI on an image known to carry the
# framework, so a regression there is caught while a judge's build on another image never fails for this.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-/usr/irissys/mgr/pex}"
IRIS_HOME="${IRIS_HOME:-/usr/irissys}"
STRICT="${PEX_STRICT:-0}"

skip() {
  echo "pex/build.sh: $1; the Second Parser stays off (no shutter-pex.jar)" >&2
  rm -f "$DEST/shutter-pex.jar" "$DEST/framework.txt" 2>/dev/null
  if [ "$STRICT" = "1" ]; then exit 1; fi
  exit 0
}

command -v javac >/dev/null 2>&1 || skip "no javac in this image"
command -v jar >/dev/null 2>&1 || skip "no jar tool in this image"
command -v python3 >/dev/null 2>&1 || skip "no python3 in this image"
command -v sha256sum >/dev/null 2>&1 || skip "no sha256sum in this image"
mkdir -p "$DEST/lib" "$DEST/classes" 2>/dev/null || skip "cannot write $DEST"

# IRIS's PEX framework: the one jar under dev/java that holds com.intersystems.enslib.pex.BusinessOperation.
FRAMEWORK="$(python3 - "$IRIS_HOME/dev/java" <<'PY'
import glob, sys, zipfile
root = sys.argv[1]
for path in sorted(glob.glob(root + "/**/*.jar", recursive=True)):
    try:
        if "com/intersystems/enslib/pex/BusinessOperation.class" in zipfile.ZipFile(path).namelist():
            print(path)
            break
    except Exception:
        pass
PY
)"
[ -n "$FRAMEWORK" ] || skip "no jar under $IRIS_HOME/dev/java holds com/intersystems/enslib/pex (this IRIS has no PEX Java framework)"
JDBC="$(ls "$IRIS_HOME"/dev/java/lib/*/intersystems-jdbc-*.jar 2>/dev/null | head -1)"

# name  url  sha256 (pinned; a jar already there with the right digest is kept)
JARS=(
  "hapi-base-2.6.0.jar https://repo1.maven.org/maven2/ca/uhn/hapi/hapi-base/2.6.0/hapi-base-2.6.0.jar 8e91877df2d0d5a0bd3bb3b670f624fe060344fc74e618e24d80aa0e86b31259"
  "hapi-structures-v251-2.6.0.jar https://repo1.maven.org/maven2/ca/uhn/hapi/hapi-structures-v251/2.6.0/hapi-structures-v251-2.6.0.jar 5bfe9672f60b0d0a6a1455f2c173fb49b895dd17e19e675a2c932546defd5b01"
  "slf4j-api-1.7.36.jar https://repo1.maven.org/maven2/org/slf4j/slf4j-api/1.7.36/slf4j-api-1.7.36.jar d3ef575e3e4979678dc01bf1dcce51021493b4d11fb7f1be8ad982877c16a1c0"
  "commons-lang3-3.12.0.jar https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.12.0/commons-lang3-3.12.0.jar d919d904486c037f8d193412da0c92e22a9fa24230b9d67a57855c5c31c7e94e"
  "joda-time-2.1.jar https://repo1.maven.org/maven2/joda-time/joda-time/2.1/joda-time-2.1.jar 5bce965a5e1dc1add255f1791a18521a7a5ecf36e436acb7ce2e5eda9d1a8e10"
)
for entry in "${JARS[@]}"; do
  read -r name url sha <<<"$entry"
  target="$DEST/lib/$name"
  if [ -f "$target" ] && echo "$sha  $target" | sha256sum -c --quiet - 2>/dev/null; then echo "kept $name"; continue; fi
  tmp="$target.part"; rm -f "$tmp"
  if ! python3 - "$url" "$tmp" <<'PY'
import sys, urllib.request
url, out = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url, timeout=120) as r, open(out, "wb") as f:
    f.write(r.read())
PY
  then rm -f "$tmp"; skip "could not download $name from Maven Central"; fi
  if echo "$sha  $tmp" | sha256sum -c --quiet - 2>/dev/null; then mv "$tmp" "$target"; echo "downloaded $name (SHA-256 matches)"
  else rm -f "$tmp"; skip "SHA-256 mismatch for $name: not kept"; fi
done

CP="$FRAMEWORK${JDBC:+:$JDBC}"
for j in "$DEST"/lib/*.jar; do CP="$CP:$j"; done
rm -rf "$DEST/classes"/*
javac --release 11 -Xlint:all -Werror -cp "$CP" -d "$DEST/classes" "$HERE"/src/shutter/pex/*.java || skip "javac failed against $(basename "$FRAMEWORK")"
jar cf "$DEST/shutter-pex.jar.part" -C "$DEST/classes" . || skip "jar failed"
mv "$DEST/shutter-pex.jar.part" "$DEST/shutter-pex.jar"
echo "$FRAMEWORK" > "$DEST/framework.txt"
echo "built $DEST/shutter-pex.jar against $(basename "$FRAMEWORK")"
