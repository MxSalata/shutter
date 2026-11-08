#!/bin/bash
# Points a container's ^Shutter.Config("fixtures") at a folder inside it. CTR names the container.
set -eu
printf '%s\n' "Set ^Shutter.Config(\"fixtures\") = \"$1\" Write !,\"RESULT: ok\",!" 'Halt' \
  | docker exec -i "${CTR:?container}" iris session IRIS -U SHUTTER | grep -q '^RESULT: ok'
