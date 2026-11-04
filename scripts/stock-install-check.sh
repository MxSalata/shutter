#!/usr/bin/env bash
# A load on a stock instance: what a person's `zpm` does on a plain IRIS, in the USER namespace it lands in.
#
# Neither the image build nor install.sh goes this way: the image's installer has made the namespaces before the load,
# and SHUTTER_BUILD=1 starts no production, so an install that only works there can look green everywhere else. This
# starts the plain image, installs the pinned IPM from vendor/ipm, loads the module, checks /shutter answers and the
# production runs, and plays scenarios on it.
#
#   scripts/stock-install-check.sh IMAGE MODULE [--archive FILE] [--write-archive FILE] [SCENARIO...]
#
# IMAGE is a plain IRIS for Health image. MODULE is the module's folder in the repository: "." for the whole package
# (2026.3 or later) or "core" for the core alone (2026.2). --archive loads a package archive instead of the folder, the
# form the registry serves; --write-archive also writes one with `zpm package`. The scenarios default to S2.
# CTR names the container (default shutter-stock-check); KEEP=1 leaves it running. Run from the repository's root.
set -euo pipefail

image=${1:?usage: stock-install-check.sh IMAGE MODULE [--archive FILE] [--write-archive FILE] [SCENARIO...]}
module=${2:?usage: stock-install-check.sh IMAGE MODULE [--archive FILE] [--write-archive FILE] [SCENARIO...]}
shift 2
archive='' write_archive=''
scenarios=()
while [ $# -gt 0 ]; do
  case "$1" in
    --archive) archive=$2; shift 2 ;;
    --write-archive) write_archive=$2; shift 2 ;;
    *) scenarios+=("$1"); shift ;;
  esac
done
[ ${#scenarios[@]} -gt 0 ] || scenarios=(S2)

ctr=${CTR:-shutter-stock-check}
home=/home/irisowner
session() { docker exec -i "$ctr" iris session IRIS -U "$1"; }
cleanup() { [ "${KEEP:-0}" = 1 ] || docker rm -f "$ctr" > /dev/null 2>&1 || true; }
trap cleanup EXIT

docker rm -f "$ctr" > /dev/null 2>&1 || true
docker run -d --name "$ctr" -p 127.0.0.1::52773 "$image" --check-caps false --ISCAgent false > /dev/null
port=$(docker port "$ctr" 52773/tcp | head -1 | sed 's/.*://')
url="http://127.0.0.1:$port"

up=0
for _ in $(seq 1 60); do
  if docker exec "$ctr" iris qlist IRIS 2>/dev/null | grep -q '\^running'; then up=1; break; fi
  sleep 5
done
[ "$up" = 1 ] || { echo "the instance did not start"; docker logs "$ctr" 2>&1 | tail -50; exit 1; }
sleep 5

docker cp vendor/ipm/zpm-0.10.10.xml "$ctr:/tmp/zpm.xml"
out=$(printf '%s\n' 'Set sc = $SYSTEM.OBJ.Load("/tmp/zpm.xml", "ck") Write !,"RESULT: ",$SELECT(sc: "ok", 1: $SYSTEM.Status.GetErrorText(sc)),!' 'Halt' | session USER)
echo "$out" | grep -q '^RESULT: ok' || { echo "$out" | tail -30; echo "IPM did not install"; exit 1; }
echo "IPM 0.10.10 installed"

if [ -n "$archive" ]; then
  docker cp "$archive" "$ctr:$home/pkg.tgz"
  docker exec -u root "$ctr" chown irisowner:irisowner "$home/pkg.tgz"
  target="$home/pkg.tgz"
else
  tar -cf - --exclude=.git --exclude=node_modules . \
    | docker exec -i -u root "$ctr" sh -c "mkdir -p $home/pkg && tar -xf - -C $home/pkg && chown -R irisowner:irisowner $home/pkg"
  target="$home/pkg"
  [ "$module" = . ] || target="$home/pkg/$module"
fi

start=$SECONDS
out=$(printf '%s\n' "Set sc = ##class(%IPM.Main).Shell(\"load $target -v\") Write !,\"RESULT: \",\$SELECT(sc: \"ok\", 1: \$SYSTEM.Status.GetErrorText(sc)),!" 'Halt' | session USER)
echo "$out" | grep -q '^RESULT: ok' || { echo "$out" | tail -40; echo "the load failed on a stock instance"; exit 1; }
echo "loaded $target in USER in $((SECONDS - start)) s"

code=$(curl -s -m 20 -o /dev/null -w '%{http_code}' "$url/shutter/index.html" || true)
[ "$code" = 200 ] || { echo "/shutter answered HTTP $code"; exit 1; }
state=$(printf '%s\n' 'Set sc = ##class(Ens.Director).GetProductionStatus(.n, .s) Write !,"RESULT: ",$GET(n)," ",$GET(s),!' 'Halt' | session USER | grep '^RESULT: ' || true)
[ "$state" = 'RESULT: Shutter.Production 1' ] || { echo "the production is not running: $state"; exit 1; }
echo "/shutter answers and Shutter.Production runs"

if [ -n "$write_archive" ]; then
  name=$(sed -n 's:.*<Name>\(iris-[a-z-]*\)</Name>.*:\1:p' "$module/module.xml" | head -1)
  out=$(printf '%s\n' "Set sc = ##class(%IPM.Main).Shell(\"$name package -only -path /tmp/pkg\") Write !,\"RESULT: \",\$SELECT(sc: \"ok\", 1: \$SYSTEM.Status.GetErrorText(sc)),!" 'Halt' | session USER)
  echo "$out" | grep -q '^RESULT: ok' || { echo "$out" | tail -30; echo "the package was not written"; exit 1; }
  docker cp "$ctr:/tmp/pkg.tgz" "$write_archive"
  echo "wrote $write_archive"
fi

# scenario_check reads the demo receivers as _SYSTEM, whose stock password has expired; the app itself does not need it.
printf '%s\n' 'Do ##class(Security.Users).UnExpireUserPasswords("*")' 'Halt' | session %SYS > /dev/null
python3 tests/e2e/scenario_check.py --url "$url" --approve "${scenarios[@]}"
