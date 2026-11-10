#!/bin/bash
# Starts a throwaway IRIS with this working copy mounted and installs Shutter as CI does (the core edition, no key, so
# agents can only replay), with the second demo receiver and without the demo hospital.
#
#   bash tests/fair_test/instance.sh CONTAINER IMAGE HOST_PORT
#
# Run it from the repository's root on a machine with Docker. It starts with `docker rm -f CONTAINER`, so name your own.
set -eu
CTR=${1:?container}; IMAGE=${2:?image}; PORT=${3:?host port}
URL="http://127.0.0.1:$PORT"
docker rm -f "$CTR" > /dev/null 2>&1 || true
docker run -d --name "$CTR" -p "127.0.0.1:$PORT:52773" -v "$PWD:/home/irisowner/dev:ro" "$IMAGE" --check-caps false --ISCAgent false > /dev/null
for i in $(seq 1 60); do
  docker exec "$CTR" iris session IRIS -U %SYS '##class(Security.Users).UnExpireUserPasswords("*")' > /dev/null 2>&1 && break
  sleep 5
done
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' -u _SYSTEM:SYS "$URL/api/atelier/" || true)" = 200 ] && break
  sleep 5
done
session() { # NAMESPACE COMMAND
  out=$(printf '%s\n' "$2" 'Halt' | docker exec -i "$CTR" iris session IRIS -U "$1")
  echo "$out" | tail -3
  grep -q '^RESULT: ok' <<<"$out"
}
python3 scripts/iris-load.py --url "$URL" --ns USER src/Shutter/Setup.cls
session USER 'Set r = ##class(Shutter.Setup).CreateNamespace("SHUTTER") Write !,"RESULT: ",r,!'
python3 scripts/iris-load.py --url "$URL" --ns SHUTTER $(python3 scripts/module-sources.py core/module.xml)
session SHUTTER 'Set r = ##class(Shutter.Setup).Install("/home/irisowner/dev/") Write !,"RESULT: ",r,!'
session SHUTTER 'Set r = ##class(Shutter.Installer).RunRecords("SHUTTER") Write !,"RESULT: ",r,!'
curl -s "$URL/api/shutter/health"; echo
