#!/usr/bin/env bash
# Installs Shutter with Docker: checks everything first, and changes nothing until every check passes.
#
#   ./install.sh                         the AI Hub edition (build 2027.1.0AI.109.0, or 2026.3.0AI.154.0 if that is the
#                                        one loaded): live agents with ANTHROPIC_API_KEY in .env, the recorded board
#                                        without one
#   ./install.sh --image-file FILE       the same, loading the AI Hub image from the Early Access file first
#   ./install.sh --replay                the replay edition on the public IRIS for Health image (no AI Hub, no key)
#
# Then it builds and starts the container (the whole build log goes to install-build.log) and waits until the container
# reports healthy (2 to 15 minutes the first time). A Shutter that is already running and healthy is left as it is.
# Another port: SHUTTER_WEB_PORT=8080 SHUTTER_SUPERSERVER_PORT=1973 ./install.sh (kept in the .env it creates).
# Works with bash 3.2 (macOS) too.
set -euo pipefail

# The AI Hub builds Shutter is verified on, newest first: the Early Access portal offers 2027.1.0AI.109.0 since 2 Nov 2026
# and no longer 2026.3.0AI.154.0, the contest's first build, which still works if it is the one loaded.
AIHUB_BUILDS="2027.1.0AI.109.0 2026.3.0AI.154.0"
AIHUB_IMAGE="irishealth-community:2027.1.0AI.109.0"
AIHUB_FILE="irishealth-community-2027.1.0AI.109.0-docker.tar.gz"
PUBLIC_IMAGE="containers.intersystems.com/intersystems/irishealth-community:2026.2"
MIN_MEMORY_GB=5
MIN_DISK_GB=25
edition=aihub
image_file=""

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --replay) edition=replay ;;
    --image-file) image_file="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done
cd "$(dirname "$0")"

# The same command, for a [fix] to quote
rerun=./install.sh
[ "$edition" = replay ] && rerun="$rerun --replay"
[ -n "$image_file" ] && rerun="$rerun --image-file $image_file"

problems=0
fail() { problems=$((problems + 1)); printf '  [fix] %s\n' "$1"; shift; for line in "$@"; do printf '        %s\n' "$line"; done; }
ok() { printf '  [ok]  %s\n' "$1"; }
note() { printf '  [..]  %s\n' "$1"; }

# The name an Early Access image loads under, for one build: docker.iscinternal.com/.../irishealth-community:<build>, or
# the ARM64 file's irishealth_arm64-community:<build>
loaded_as() {
  local re
  re=$(printf '%s' "$1" | sed 's/\./\\./g')
  docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "(^|/)irishealth(_arm64)?-community:${re}\$" | head -1 || true
}

# A value from .env (or .env.example when .env is not there yet), without sourcing either file
setting() {
  local file=.env
  [ -f "$file" ] || file=.env.example
  [ -f "$file" ] || return 0
  sed -n "s/^$1=//p" "$file" | tail -1
}

# The container's own healthcheck (docker-compose.yml: wget against the health route inside the container), so the host
# needs neither curl nor wget: healthy, unhealthy, starting, or empty when the container is not there. The status is read
# from the engine (docker inspect), not from docker compose ps --format, whose Go templates older Compose versions reject.
shutter_id() { docker compose ps -q shutter 2> /dev/null | head -1 || true; }
healthy() {
  id=$(shutter_id)
  [ -n "$id" ] && [ "$(docker inspect --format '{{.State.Health.Status}}' "$id" 2> /dev/null)" = healthy ]
}

# The shell's value comes first, because docker compose itself prefers the shell to .env; a value set but empty also
# beats .env there, and then the compose file's default applies.
port=${SHUTTER_WEB_PORT-$(setting SHUTTER_WEB_PORT)}; port=${port:-52773}
superserver_port=${SHUTTER_SUPERSERVER_PORT-$(setting SHUTTER_SUPERSERVER_PORT)}; superserver_port=${superserver_port:-1972}
health_url="http://localhost:${port}/api/shutter/health"

shutter_up=""
echo "Checking (nothing is changed yet):"

# 1. Docker and Compose
if ! command -v docker > /dev/null 2>&1; then
  fail "Docker is not installed." "Install Docker Desktop or Docker Engine, then run ./install.sh again."
elif ! docker info > /dev/null 2>&1; then
  fail "Docker is installed but not running, or this user may not use it." \
    "Start Docker (Docker Desktop, or: sudo systemctl start docker), or add yourself to the docker group, then run ./install.sh again."
else
  ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null) is running"
  compose=$(docker compose version --short 2>/dev/null || true)
  if [ -z "$compose" ]; then
    fail "Docker Compose v2 is missing (the \"docker compose\" command)." "Install the Compose plugin (Docker Desktop includes it), then run ./install.sh again."
  else
    ok "Docker Compose $compose"
    # Before the memory and disk checks, which are for a build: the install itself can take the disk below their figure,
    # and a running Shutter holds its own ports.
    if docker compose ps --status running --services 2> /dev/null | grep -qx shutter; then
      shutter_up=yes
      if healthy; then
        # Where it really listens: a port from the shell or an edited .env moves nothing until the container is created again
        live=$(docker compose port shutter 52773 2> /dev/null | sed 's/.*://' | head -1 || true)
        echo
        echo "Shutter is already running and healthy: http://localhost:${live:-$port}/shutter/index.html (approver / shutter)."
        echo "Nothing was changed."
        exit 0
      fi
    fi
  fi

  # 2. Memory and disk available to Docker
  # Docker Desktop's VM reports a little less than its memory setting (the kernel's own share), so a setting of exactly
  # MIN_MEMORY_GB passes: the comparison is in MiB with a 512 MiB margin, and the printed figure is rounded.
  mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
  mem_mb=$((mem / 1024 / 1024))
  mem_gb=$(( (mem_mb + 512) / 1024 ))
  if [ "$mem_mb" -lt $((MIN_MEMORY_GB * 1024 - 512)) ]; then
    fail "Docker has about ${mem_gb} GB of memory; Shutter's first build needs at least ${MIN_MEMORY_GB} GB." \
      "Docker Desktop: Settings, Resources, Memory: ${MIN_MEMORY_GB} GB or more. Then run ./install.sh again."
  else
    ok "Docker has about ${mem_gb} GB of memory"
  fi
  root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)
  free_kb=$(df -Pk "$root" 2>/dev/null | awk 'NR == 2 { print $4 }' || true)
  if [ -n "$free_kb" ]; then
    free_gb=$((free_kb / 1024 / 1024))
    if [ "$free_gb" -lt "$MIN_DISK_GB" ]; then
      fail "Docker's disk ($root) has about ${free_gb} GB free; allow about ${MIN_DISK_GB} GB." \
        "Free space (docker system prune removes unused images and build cache), then run ./install.sh again."
    else
      ok "Docker's disk has about ${free_gb} GB free"
    fi
  else
    note "Docker's disk is inside its own VM here, so its free space can't be read: allow about ${MIN_DISK_GB} GB"
  fi
fi

# A port docker compose would publish must be free. A connection that succeeds means something holds it. Another IRIS on
# 1972 is the usual case, and without this check it would surface only after the whole build, as a failed "compose up".
not_a_port() {
  case "$1" in ''|*[!0-9]*) return 0 ;; esac
  [ "${#1}" -gt 5 ] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]
}
port_taken() { (exec 3<> "/dev/tcp/127.0.0.1/${1}") 2> /dev/null; }

# Both ports have to be right in the same command: naming one at a time, each [fix] was refused for the other port, and
# the next run forgot the port the first [fix] had chosen.
one_port_command() {
  local name=$1 value=$2 default=$3
  if not_a_port "$value" || port_taken "$value"; then printf '%s=<free port> ' "$name"
  elif [ "$value" != "$default" ]; then printf '%s=%s ' "$name" "$value"
  fi
}
both_ports_command=""
check_port() {
  local name=$1 value=$2 what=$3
  if not_a_port "$value"; then
    fail "$name is \"$value\", which is not a port number." "Give it a number from 1 to 65535, then run $rerun again."
  elif port_taken "$value"; then
    if [ -f .env ]; then
      fail "Port ${value} ($what) is already in use by something else." \
        "Stop what uses it, or set $name to a free port in .env, then run $rerun again."
    elif [ -n "$both_ports_command" ]; then
      fail "Port ${value} ($what) is already in use by something else." "Stop what uses it, or choose a free port in the command above."
    else
      both_ports_command="$(one_port_command SHUTTER_WEB_PORT "$port" 52773)$(one_port_command SHUTTER_SUPERSERVER_PORT "$superserver_port" 1972)$rerun"
      fail "Port ${value} ($what) is already in use by something else." \
        "Stop what uses it, or choose a free port: $both_ports_command" \
        "That command keeps its ports in the .env it creates."
    fi
  else
    ok "Port ${value} ($what) is free"
  fi
}

# 3. The ports
if [ -n "$shutter_up" ]; then
  note "Shutter's container is running but not healthy yet; it will be built and started again"
elif [ "$port" = "$superserver_port" ]; then
  fail "SHUTTER_WEB_PORT and SHUTTER_SUPERSERVER_PORT are both ${port}." "Give them different ports, then run $rerun again."
else
  check_port SHUTTER_WEB_PORT "$port" "the web app"
  check_port SHUTTER_SUPERSERVER_PORT "$superserver_port" "IRIS's superserver"
fi

# 4. The image: .env's when there is one; else the build of --image-file's name; else a verified build already loaded
image=""
with=""
env_image=""
if [ -f .env ]; then image=$(setting SHUTTER_IMAGE); with=$(setting SHUTTER_WITH_AIHUB); env_image=$image; fi
# .env written for the replay edition (by ./install.sh --replay, or by hand): the AI Hub edition must not build on it
env_replay=""
if [ "$edition" = aihub ] && [ -f .env ]; then
  if [ "${with:-auto}" = 0 ]; then env_replay=yes; fi
  case "$image" in ""|irishealth-community:*) ;; *) env_replay=yes ;; esac
fi
file_build=""
if [ -n "$image_file" ]; then
  file_build=$(basename "$image_file" | sed -n 's/^irishealth\(_arm64\)\{0,1\}-community-\(.*\)-docker\.tar\.gz$/\2/p')
fi
if [ -z "$image" ] && [ -n "$file_build" ]; then
  image="irishealth-community:$file_build"
elif [ -n "$file_build" ] && [ -z "$env_replay" ] && [ "$image" != "irishealth-community:$file_build" ]; then
  # .env may be a deliberate choice, so neither side wins quietly
  fail "The file $image_file is build $file_build, but .env names the image $image." \
    "Keep .env's image (run ./install.sh without --image-file), or switch to the file's build: if an instance ran before, run docker compose down -v first (it removes that instance's data); then set SHUTTER_IMAGE=irishealth-community:$file_build in .env and run ./install.sh --image-file $image_file again."
fi
if [ -z "$image" ] && [ "$edition" = aihub ] && docker info > /dev/null 2>&1; then
  for b in $AIHUB_BUILDS; do
    if docker image inspect "irishealth-community:$b" > /dev/null 2>&1 || [ -n "$(loaded_as "$b")" ]; then image="irishealth-community:$b"; break; fi
  done
fi
[ "$edition" = replay ] && image="$PUBLIC_IMAGE"
image=${image:-$AIHUB_IMAGE}
build=${image#irishealth-community:}
plan_load=""
plan_tag=""
if [ "$problems" -eq 0 ] && [ "$edition" = aihub ] && [ -z "$env_replay" ]; then
  verified=no
  for b in $AIHUB_BUILDS; do [ "$build" = "$b" ] && verified=yes; done
  [ "$verified" = no ] && note "$image is not one of the builds Shutter is verified on ($AIHUB_BUILDS); trying it anyway"
  if docker image inspect "$image" > /dev/null 2>&1; then
    ok "The AI Hub image $image is loaded"
  else
    loaded=""
    # An Early Access image loads under its long internal name: it is tagged with the short name the build uses
    case "$image" in irishealth-community:*) loaded=$(loaded_as "$build") ;; esac
    if [ -z "$loaded" ] && [ -z "$image_file" ] && [ "$image" != "$AIHUB_IMAGE" ]; then
      fail ".env names the image $image, which is not loaded." \
        "Load that image, or set SHUTTER_IMAGE=$AIHUB_IMAGE in .env, then run ./install.sh again."
    elif [ -n "$loaded" ]; then
      plan_tag="$loaded"
      ok "The AI Hub image is loaded as $loaded (it will be tagged $image)"
    elif [ -n "$image_file" ] && [ -f "$image_file" ]; then
      plan_load="$image_file"
      ok "The AI Hub image will be loaded from $image_file"
    elif [ -n "$image_file" ]; then
      fail "No file at $image_file." "Give the path of $AIHUB_FILE (or another AI Hub Community file), as downloaded."
    else
      fail "The AI Hub image ($image) is not loaded." \
        "Download $AIHUB_FILE from InterSystems' Early Access portal" \
        "(https://evaluation.intersystems.com/Eval/early-access/AIHub), then: ./install.sh --image-file <that file>." \
        "No Early Access file? ./install.sh --replay runs the replay edition on the public image."
    fi
  fi
  if docker image inspect "$image" > /dev/null 2>&1; then
    size=$(docker image inspect --format '{{.Size}}' "$image")
    if [ "$size" -lt 4000000000 ]; then
      case "$image" in
        irishealth-community:*) again="Load it again: docker image load -i irishealth-community-$build-docker.tar.gz" ;;
        *) again="Load it again from its Early Access file: docker image load -i <that file>" ;;
      esac
      fail "The AI Hub image is only $((size / 1000000)) MB; a complete load is about 5.4 GB of content." "$again"
    fi
    arch=$(docker image inspect --format '{{.Architecture}}' "$image")
    host=$(docker info --format '{{.Architecture}}')
    case "$host/$arch" in
      x86_64/amd64|amd64/amd64|aarch64/arm64|arm64/arm64) ;;
      *) fail "The image is for $arch and Docker runs on $host." "Download the Early Access file for your machine's architecture." ;;
    esac
  fi
elif [ "$problems" -eq 0 ] && [ "$edition" = replay ]; then
  ok "The replay edition builds on the public image $PUBLIC_IMAGE (pulled during the build)"
fi

# 5. .env
plan_env=""
if [ -f .env ]; then
  if [ "$edition" = replay ] && [ "${with:-1}" != 0 ]; then
    fail ".env is set up for the AI Hub edition, and you asked for the replay edition." \
      "Remove .env (or set SHUTTER_IMAGE=$PUBLIC_IMAGE and SHUTTER_WITH_AIHUB=0 in it). If an instance ran before, run docker compose down -v first: it removes that instance's data. Then run ./install.sh --replay again."
  elif [ -n "$env_replay" ]; then
    # The mirror of the guard above: after ./install.sh --replay, a plain ./install.sh or --image-file would otherwise
    # build the replay edition again while saying the AI Hub image is loaded
    again="./install.sh"; [ -n "$image_file" ] && again="./install.sh --image-file $image_file"
    fail ".env is set up for the replay edition (SHUTTER_IMAGE=${env_image:-unset}, SHUTTER_WITH_AIHUB=${with:-auto}), and you asked for the AI Hub edition." \
      "If an instance ran before, run docker compose down -v first: it removes that instance's data. Then remove .env (or set SHUTTER_IMAGE=${AIHUB_IMAGE} and SHUTTER_WITH_AIHUB=auto in it) and run $again again."
  else
    ok ".env is there and is kept as it is"
    # Compose takes the shell's value over .env's for this run only, so a later plain "docker compose up" would move the port
    env_port=$(setting SHUTTER_WEB_PORT); env_superserver=$(setting SHUTTER_SUPERSERVER_PORT)
    [ "$port" = "${env_port:-52773}" ] || note "SHUTTER_WEB_PORT=$port from your shell is used for this run; .env says ${env_port:-52773}, so change it there to keep it"
    [ "$superserver_port" = "${env_superserver:-1972}" ] || note "SHUTTER_SUPERSERVER_PORT=$superserver_port from your shell is used for this run; .env says ${env_superserver:-1972}, so change it there to keep it"
  fi
elif [ ! -f .env.example ]; then
  fail ".env.example is missing: this is not a complete copy of the repository." "Clone it again: git clone https://github.com/MxSalata/shutter.git"
elif [ ! -w . ]; then
  fail "This folder is not writable, so .env can't be created." "Clone the repository into a folder of your own."
else
  plan_env=yes
  ok ".env will be created from .env.example"
fi

if [ "$problems" -gt 0 ]; then
  echo
  echo "$problems thing(s) to fix first. Nothing was changed."
  exit 1
fi

echo
echo "Every check passed. Installing:"
# The time a person waits, the image's load and build included: counted from here it was the seconds after the build,
# and a first install reported "ready after 10 s".
start=$(date +%s)
elapsed() {
  local s=$(( $(date +%s) - start ))
  if [ "$s" -lt 60 ]; then echo "$s s"; else echo "$((s / 60)) min $((s % 60)) s"; fi
}
if [ -n "$plan_load" ]; then
  echo "  loading the AI Hub image (a few minutes)"
  out=$(docker image load -i "$plan_load")
  echo "$out" | sed 's/^/    /'
  loaded=$(echo "$out" | sed -n 's/^Loaded image: //p' | grep -E "irishealth(_arm64)?-community:" | head -1 || true)
  if [ -n "$loaded" ] && [ "$loaded" != "$image" ]; then plan_tag="$loaded"; fi
fi
if [ -n "$plan_tag" ]; then
  docker tag "$plan_tag" "$image"
  echo "  tagged $plan_tag as $image"
fi
if [ -n "$plan_env" ]; then
  cp .env.example .env
  if [ "$edition" = replay ]; then
    sed -i.bak -e "s|^SHUTTER_IMAGE=.*|SHUTTER_IMAGE=$PUBLIC_IMAGE|" -e 's|^SHUTTER_WITH_AIHUB=.*|SHUTTER_WITH_AIHUB=0|' .env
    rm -f .env.bak
  elif [ "$(setting SHUTTER_IMAGE)" != "$image" ]; then
    # The AI Hub build that was found or loaded, which may not be .env.example's
    sed -i.bak -e "s|^SHUTTER_IMAGE=.*|SHUTTER_IMAGE=$image|" .env
    rm -f .env.bak
  fi
  # A port chosen in the shell has to outlast this run: the next ./install.sh or docker compose up reads it from here
  sed -i.bak -e "s|^SHUTTER_WEB_PORT=.*|SHUTTER_WEB_PORT=$port|" -e "s|^SHUTTER_SUPERSERVER_PORT=.*|SHUTTER_SUPERSERVER_PORT=$superserver_port|" .env
  rm -f .env.bak
  echo "  created .env"
fi
echo "  building and starting (2 to 15 minutes the first time; the whole log goes to install-build.log)"
if docker compose up -d --build > install-build.log 2>&1; then
  tail -5 install-build.log | sed 's/^/    /'
else
  echo
  # A port taken after the check, or one a connection can't see: the build itself was fine, so don't send them to the network
  port_clash=$(grep -iE 'port is already allocated|address already in use|ports are not available' install-build.log | tail -1 || true)
  if [ -n "$port_clash" ]; then
    echo "The image is built, but the container could not take its port:"
    echo "$port_clash" | sed 's/^/    /'
    echo
    fail "Shutter was not started: a port it publishes (${port} or ${superserver_port}) is taken." \
      "Stop what uses it, or set SHUTTER_WEB_PORT or SHUTTER_SUPERSERVER_PORT to a free port in .env, then run $rerun again."
    exit 1
  fi
  echo "The build failed. The whole log is in install-build.log; its last lines:"
  tail -30 install-build.log | sed 's/^/    /'
  # The lines that name the reason: iris.script's BUILD FAILED, the Second Parser's build, BuildKit's ERROR
  reason=$(grep -n 'BUILD FAILED\|pex/build.sh\|ERROR' install-build.log | tail -8 || true)
  if [ -n "$reason" ]; then
    echo "The lines that name the reason (line numbers in install-build.log):"
    echo "$reason" | sed 's/^/    /'
  fi
  echo
  fail "The build failed, so Shutter was not started." "Fix what install-build.log names (no network for the image, the package or Maven Central is the usual cause), then run ./install.sh again."
  exit 1
fi

# The 25 minutes are the wait for healthy alone, so a slow image download can't use them up.
deadline=$(( $(date +%s) + 25 * 60 ))
while :; do
  if healthy; then
    echo
    echo "Shutter is ready after $(elapsed):"
    echo "  the web app:   http://localhost:${port}/shutter/index.html  (approver / shutter, or operator / shutter)"
    echo "  first steps:   Scenarios, run S2 in Board mode, then approve its case (the README's \"On your machine or in the trial, first\")"
    echo "  the portal:    http://localhost:${port}/csp/sys/UtilHome.csp  (_SYSTEM / SYS, namespace SHUTTER)"
    exit 0
  fi
  if [ "$(date +%s)" -gt "$deadline" ]; then
    echo
    echo "Shutter did not report healthy within 25 minutes. The last lines of its log:"
    docker compose logs --tail 30 shutter 2>&1 | sed 's/^/    /'
    if command -v curl > /dev/null 2>&1; then echo "Its health report: curl $health_url"; else echo "Its health report: $health_url (open it in a browser)"; fi
    exit 1
  fi
  id=$(shutter_id); state=""
  [ -n "$id" ] && state=$(docker inspect --format '{{.State.Status}}' "$id" 2> /dev/null || true)
  printf '  waiting: %s, container %s\n' "$(elapsed)" "${state:-starting}"
  sleep 10
done
