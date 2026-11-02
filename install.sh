#!/usr/bin/env bash
# Installs Shutter with Docker: checks everything first, and changes nothing until every check passes.
#
#   ./install.sh                         the AI Hub edition (build 154): live agents with ANTHROPIC_API_KEY in .env,
#                                        the recorded board without one
#   ./install.sh --image-file FILE       the same, loading the AI Hub image from the Early Access file first
#   ./install.sh --replay                the replay edition on the public IRIS for Health image (no AI Hub, no key)
#
# Then it builds and starts the container and waits until Shutter's health report says it is ready (2 to 15 minutes
# the first time). A Shutter that is already running and healthy is left as it is. Works with bash 3.2 (macOS) too.
set -euo pipefail

AIHUB_IMAGE="irishealth-community:2026.3.0AI.154.0"
PUBLIC_IMAGE="containers.intersystems.com/intersystems/irishealth-community:2026.2"
MIN_MEMORY_GB=5
MIN_DISK_GB=25
edition=aihub
image_file=""

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }
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

problems=0
fail() { problems=$((problems + 1)); printf '  [fix] %s\n' "$1"; shift; for line in "$@"; do printf '        %s\n' "$line"; done; }
ok() { printf '  [ok]  %s\n' "$1"; }
note() { printf '  [..]  %s\n' "$1"; }

# A value from .env (or .env.example when .env is not there yet), without sourcing either file
setting() {
  local file=.env
  [ -f "$file" ] || file=.env.example
  [ -f "$file" ] || return 0
  sed -n "s/^$1=//p" "$file" | tail -1
}

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
  fi

  # 2. Memory and disk available to Docker
  mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
  mem_gb=$((mem / 1024 / 1024 / 1024))
  if [ "$mem_gb" -lt "$MIN_MEMORY_GB" ]; then
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

# 3. Already running?
port=$(setting SHUTTER_WEB_PORT); port=${port:-52773}
health_url="http://localhost:${port}/api/shutter/health"
if [ "$problems" -eq 0 ] && docker compose ps --status running --services 2> /dev/null | grep -qx shutter; then
  if curl -fsS -m 10 "$health_url" 2> /dev/null | grep -q '"ok":true'; then
    echo
    echo "Shutter is already running and healthy: http://localhost:${port}/shutter/index.html (approver / shutter)."
    echo "Nothing was changed."
    exit 0
  fi
  note "Shutter's container is running but not healthy yet; it will be built and started again"
elif (exec 3<> "/dev/tcp/127.0.0.1/${port}") 2> /dev/null; then
  fail "Port ${port} is already in use by something else." \
    "Stop what uses it, or set SHUTTER_WEB_PORT to a free port in .env, then run ./install.sh again."
else
  ok "Port ${port} is free"
fi

# 4. The image
image=$(setting SHUTTER_IMAGE)
[ "$edition" = replay ] && image="$PUBLIC_IMAGE"
image=${image:-$AIHUB_IMAGE}
plan_load=""
plan_tag=""
if [ "$problems" -eq 0 ] && [ "$edition" = aihub ]; then
  if docker image inspect "$image" > /dev/null 2>&1; then
    ok "The AI Hub image $image is loaded"
  else
    loaded=""
    # Only the tested build is tagged automatically, and only under the name .env.example expects
    if [ "$image" = "$AIHUB_IMAGE" ]; then
      loaded=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E "/irishealth-community:2026\.3\.0AI\.154\.0$" | head -1 || true)
    fi
    if [ "$image" != "$AIHUB_IMAGE" ] && [ -z "$image_file" ]; then
      fail ".env names the image $image, which is not loaded." \
        "Load that image, or set SHUTTER_IMAGE=$AIHUB_IMAGE in .env for the tested build 154, then run ./install.sh again."
    elif [ -n "$loaded" ]; then
      plan_tag="$loaded"
      ok "The AI Hub image is loaded as $loaded (it will be tagged $image)"
    elif [ -n "$image_file" ] && [ -f "$image_file" ]; then
      plan_load="$image_file"
      ok "The AI Hub image will be loaded from $image_file"
    elif [ -n "$image_file" ]; then
      fail "No file at $image_file." "Give the path of irishealth-community-2026.3.0AI.154.0-docker.tar.gz, as downloaded."
    else
      fail "The AI Hub image ($image) is not loaded." \
        "Download irishealth-community-2026.3.0AI.154.0-docker.tar.gz from InterSystems' Early Access portal" \
        "(https://evaluation.intersystems.com/Eval/early-access/AIHub), then: ./install.sh --image-file <that file>." \
        "No Early Access file? ./install.sh --replay runs the replay edition on the public image."
    fi
  fi
  if docker image inspect "$image" > /dev/null 2>&1; then
    size=$(docker image inspect --format '{{.Size}}' "$image")
    if [ "$size" -lt 4000000000 ]; then
      fail "The AI Hub image is only $((size / 1000000)) MB; a complete load is about 5.4 GB of content." \
        "Load it again: docker image load -i irishealth-community-2026.3.0AI.154.0-docker.tar.gz"
    fi
    arch=$(docker image inspect --format '{{.Architecture}}' "$image")
    host=$(docker info --format '{{.Architecture}}')
    case "$host/$arch" in
      x86_64/amd64|amd64/amd64|aarch64/arm64|arm64/arm64) ;;
      *) fail "The image is for $arch and Docker runs on $host." "Download the Early Access file for your machine's architecture." ;;
    esac
  fi
elif [ "$problems" -eq 0 ]; then
  ok "The replay edition builds on the public image $PUBLIC_IMAGE (pulled during the build)"
fi

# 5. .env
plan_env=""
if [ -f .env ]; then
  with=$(setting SHUTTER_WITH_AIHUB)
  if [ "$edition" = replay ] && [ "${with:-1}" != 0 ]; then
    fail ".env is set up for the AI Hub edition, and you asked for the replay edition." \
      "Remove .env (or set SHUTTER_IMAGE=$PUBLIC_IMAGE and SHUTTER_WITH_AIHUB=0 in it). If an instance ran before, run docker compose down -v first: it removes that instance's data. Then run ./install.sh --replay again."
  else
    ok ".env is there and is kept as it is"
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
if [ -n "$plan_load" ]; then
  echo "  loading the AI Hub image (a few minutes)"
  out=$(docker image load -i "$plan_load")
  echo "$out" | sed 's/^/    /'
  loaded=$(echo "$out" | sed -n 's/^Loaded image: //p' | grep -E "irishealth-community:2026\.3\.0AI\.154\.0$" | head -1)
  if [ -n "$loaded" ] && [ "$loaded" != "$image" ] && [ "$image" = "$AIHUB_IMAGE" ]; then plan_tag="$loaded"; fi
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
  fi
  echo "  created .env"
fi
echo "  building and starting (2 to 15 minutes the first time)"
docker compose up -d --build 2>&1 | tail -5 | sed 's/^/    /'

start=$(date +%s)
deadline=$((start + 25 * 60))
while :; do
  if curl -fsS -m 10 "$health_url" 2> /dev/null | grep -q '"ok":true'; then
    echo
    echo "Shutter is ready after $(( $(date +%s) - start )) s:"
    echo "  the web app:   http://localhost:${port}/shutter/index.html  (approver / shutter, or operator / shutter)"
    echo "  first steps:   Scenarios, run S2 in Board mode, then approve its case (the README's \"Your first two minutes\")"
    echo "  the portal:    http://localhost:${port}/csp/sys/UtilHome.csp  (_SYSTEM / SYS, namespace SHUTTER)"
    exit 0
  fi
  if [ "$(date +%s)" -gt "$deadline" ]; then
    echo
    echo "Shutter did not report healthy within 25 minutes. The last lines of its log:"
    docker compose logs --tail 30 shutter 2>&1 | sed 's/^/    /'
    echo "Its health report: curl $health_url"
    exit 1
  fi
  state=$(docker compose ps --format '{{.Status}}' shutter 2> /dev/null | head -1)
  printf '  waiting: %s s, container %s\n' "$(( $(date +%s) - start ))" "${state:-starting}"
  sleep 10
done
