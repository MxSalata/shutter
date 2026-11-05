#!/usr/bin/env python3
"""install.sh's refusals, run against a stand-in for docker, so no check needs Docker, an image or a build.

    python3 tests/install_check.py

Each case copies install.sh and .env.example into an empty folder, puts a fake docker first on the PATH (it logs its
arguments, says yes to everything it is asked, and reports a healthy container), holds any ports the case asks for, and
reads the output and what the run left behind. Exits 1 when a case fails. Standard library only.
"""
import os
import shutil
import socket
import stat
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE_DOCKER = r"""#!/usr/bin/env bash
echo "docker $*" >> "$FAKE_DOCKER_LOG"
case "$1 $2" in
  "info --format")
    case "$3" in
      *MemTotal*) echo 17179869184 ;;
      *DockerRootDir*) echo / ;;
      *Architecture*) echo x86_64 ;;
    esac ;;
  "version --format") echo 29.1.3 ;;
  "compose version") echo 2.40.3 ;;
  "compose ps")
    # Up only once the fake "compose up" has run
    if [ -f compose-up ]; then
      case "$*" in *-q*) echo fake-id ;; *) echo shutter ;; esac
    fi ;;
  "compose port")
    if [ -f compose-up ] && [ -n "${FAKE_LIVE_PORT:-}" ]; then echo "127.0.0.1:$FAKE_LIVE_PORT"; fi ;;
  "compose up")
    if [ -n "${FAKE_COMPOSE_UP_ERROR:-}" ]; then echo "$FAKE_COMPOSE_UP_ERROR"; exit 1; fi
    sleep "${FAKE_BUILD_SECONDS:-0}"
    echo built; touch compose-up ;;
  "inspect --format") echo healthy ;;
  "image inspect")
    [ -z "${FAKE_NO_IMAGE:-}" ] || exit 1
    case "$*" in *--format*Size*) echo 5400000000 ;; *--format*Architecture*) echo amd64 ;; esac ;;
  "images --format") : ;;
esac
exit 0
"""


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Run:
    def __init__(self, args=(), env=None, hold=(), dotenv=None, running=False):
        self.folder = tempfile.mkdtemp(prefix="install-check-")
        try:
            for name in ("install.sh", ".env.example"):
                shutil.copy(os.path.join(ROOT, name), self.folder)
            fake = os.path.join(self.folder, "bin")
            os.mkdir(fake)
            docker = os.path.join(fake, "docker")
            with open(docker, "w") as f:
                f.write(FAKE_DOCKER)
            os.chmod(docker, os.stat(docker).st_mode | stat.S_IEXEC)
            if dotenv is not None:
                with open(os.path.join(self.folder, ".env"), "w") as f:
                    f.write(dotenv)
            if running:
                open(os.path.join(self.folder, "compose-up"), "w").close()
            full = dict(os.environ, PATH=fake + os.pathsep + os.environ["PATH"], FAKE_DOCKER_LOG=os.path.join(self.folder, "docker.log"))
            for name in ("SHUTTER_WEB_PORT", "SHUTTER_SUPERSERVER_PORT"):
                full.pop(name, None)
            full.update(env or {})
            holders = []
            for port in hold:
                s = socket.socket()
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.bind(("127.0.0.1", port))
                s.listen()
                holders.append(s)
            try:
                done = subprocess.run(
                    ["bash", "install.sh", *args], cwd=self.folder, env=full, stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60,
                )
            finally:
                for s in holders:
                    s.close()
            self.code, self.out = done.returncode, done.stdout
            self.dotenv = self._read(".env")
            self.docker_log = self._read("docker.log") or ""
        finally:
            shutil.rmtree(self.folder, ignore_errors=True)

    def _read(self, name):
        try:
            with open(os.path.join(self.folder, name)) as f:
                return f.read()
        except FileNotFoundError:
            return None

    @property
    def built(self):
        return "compose up" in self.docker_log


failures = []


def check(case, condition, what, run):
    if condition:
        print(f"ok    {case}: {what}")
    else:
        failures.append(case)
        print(f"FAIL  {case}: {what}\n--- exit {run.code}, output:\n{run.out}\n---")


def refuses(case, run, *words):
    check(case, run.code == 1 and "Nothing was changed." in run.out, "refuses and says nothing was changed", run)
    check(case, not run.built, "starts no build", run)
    check(case, run.dotenv is None, "writes no .env", run)
    for w in words:
        check(case, w in run.out, f"says {w!r}", run)


def main():
    web, sup = free_port(), free_port()
    ports = {"SHUTTER_WEB_PORT": str(web), "SHUTTER_SUPERSERVER_PORT": str(sup)}

    # The two ports, one at a time and together
    run = Run(["--replay"], env=ports, hold=[sup])
    refuses("superserver busy", run, f"Port {sup} (IRIS's superserver) is already in use",
            f"SHUTTER_WEB_PORT={web} SHUTTER_SUPERSERVER_PORT=<free port> ./install.sh --replay")
    check("superserver busy", "The build failed" not in run.out, "doesn't call it a failed build", run)
    check("superserver busy", f"Port {web} (the web app) is free" in run.out, "still reports the web port", run)

    run = Run(["--replay"], env=ports, hold=[web])
    refuses("web busy", run, f"Port {web} (the web app) is already in use",
            f"SHUTTER_WEB_PORT=<free port> SHUTTER_SUPERSERVER_PORT={sup} ./install.sh --replay")

    # A command for one port at a time would be refused for the other, and the next [fix] would forget the first choice
    run = Run(["--replay"], env=ports, hold=[web, sup])
    both = "SHUTTER_WEB_PORT=<free port> SHUTTER_SUPERSERVER_PORT=<free port> ./install.sh --replay"
    refuses("both busy", run, "2 thing(s) to fix first", f"Port {web} (the web app)", f"Port {sup} (IRIS's superserver)", both)
    commands = [line for line in run.out.splitlines() if "<free port>" in line]
    check("both busy", len(commands) == 1 and both in commands[0], "gives one command, naming both", run)

    # One busy at its default: the other port, also at its default, needs no mention
    run = Run(["--replay"], env={"SHUTTER_SUPERSERVER_PORT": str(sup), "SHUTTER_WEB_PORT": "52773"}, hold=[sup])
    if "Port 52773 (the web app) is free" in run.out:
        refuses("one busy, other at default", run, ": SHUTTER_SUPERSERVER_PORT=<free port> ./install.sh --replay")
    else:
        print("skip  one busy, other at default: this machine already uses 52773")

    # A port that is not a number can't go in the command as it is
    run = Run(["--replay"], env=dict(ports, SHUTTER_WEB_PORT="80a"), hold=[sup])
    refuses("bad port and a busy one", run, "SHUTTER_WEB_PORT=<free port> SHUTTER_SUPERSERVER_PORT=<free port> ./install.sh --replay")

    # A Shutter that is already up is reported where it listens, not at a port the shell asked for and nothing has applied
    live = free_port()
    run = Run(["--replay"], env={"SHUTTER_WEB_PORT": str(free_port()), "FAKE_LIVE_PORT": str(live)}, running=True)
    check("already running", run.code == 0 and "already running and healthy" in run.out, "says so", run)
    check("already running", f"http://localhost:{live}/shutter/index.html" in run.out, "gives the port it listens on", run)
    check("already running", not run.built and run.dotenv is None, "changes nothing", run)
    run = Run(["--replay"], env=ports, running=True)
    check("already running, no answer", run.code == 0 and f"http://localhost:{web}/shutter/index.html" in run.out, "falls back to the port it was given", run)

    # With a port busy the [fix] used to send people to .env, which --replay then refused as the AI Hub edition's
    run = Run(["--replay"], env=ports)
    check("shell ports, replay", run.code == 0, "installs", run)
    check("shell ports, replay", f"SHUTTER_WEB_PORT={web}\n" in (run.dotenv or ""), "keeps the web port in the new .env", run)
    check("shell ports, replay", f"SHUTTER_SUPERSERVER_PORT={sup}\n" in (run.dotenv or ""), "keeps the superserver port in the new .env", run)
    check("shell ports, replay", "SHUTTER_WITH_AIHUB=0\n" in (run.dotenv or ""), "still writes the replay edition", run)
    check("shell ports, replay", f"http://localhost:{web}/shutter/index.html" in run.out, "points at the chosen port", run)

    # .env's ports are read when the shell has none, and the [fix] then names .env
    dotenv = f"SHUTTER_IMAGE=containers.intersystems.com/intersystems/irishealth-community:2026.2\nSHUTTER_WITH_AIHUB=0\nSHUTTER_WEB_PORT={web}\nSHUTTER_SUPERSERVER_PORT={sup}\n"
    run = Run(["--replay"], hold=[sup], dotenv=dotenv)
    check("port from .env", run.code == 1 and f"Port {sup} (IRIS's superserver) is already in use" in run.out, "checks .env's superserver port", run)
    check("port from .env", "set SHUTTER_SUPERSERVER_PORT to a free port in .env, then run ./install.sh --replay again" in run.out, "says to change .env", run)
    check("port from .env", run.dotenv == dotenv and not run.built, "changes nothing", run)

    # The shell beats .env, as it does for docker compose, and the run says so
    other = free_port()
    run = Run(["--replay"], env={"SHUTTER_WEB_PORT": str(other)}, dotenv=dotenv)
    check("shell over .env", run.code == 0 and f"SHUTTER_WEB_PORT={other} from your shell is used for this run" in run.out, "warns that .env differs", run)
    check("shell over .env", run.dotenv == dotenv, "keeps .env as it is", run)
    check("shell over .env", f"http://localhost:{other}/" in run.out, "points at the shell's port", run)

    # Values that can't be ports would otherwise look free
    for bad in ("80a", "0", "70000", "1972\r", "9999999999999999999999"):
        run = Run(["--replay"], env=dict(ports, SHUTTER_WEB_PORT=bad))
        refuses(f"bad port {bad!r}", run, "which is not a port number")
    run = Run(["--replay"], env=dict(ports, SHUTTER_WEB_PORT=str(sup)))
    refuses("same port twice", run, f"are both {sup}")

    # A port taken after the check is named as that, not as a build that lacked a network
    run = Run(["--replay"], env=dict(ports, FAKE_COMPOSE_UP_ERROR="Error: driver failed: Bind for 127.0.0.1:1972 failed: port is already allocated"))
    check("port taken later", run.code == 1 and "could not take its port" in run.out and "port is already allocated" in run.out, "names the port", run)
    check("port taken later", "Maven Central" not in run.out and "The build failed" not in run.out, "doesn't blame the network", run)
    run = Run(["--replay"], env=dict(ports, FAKE_COMPOSE_UP_ERROR="Error response from daemon: Ports are not available: exposing port TCP 127.0.0.1:1972"))
    check("port taken later, capitalised", run.code == 1 and "could not take its port" in run.out and "Ports are not available" in run.out, "names the port", run)
    check("port taken later, capitalised", "Maven Central" not in run.out and "The build failed" not in run.out, "doesn't blame the network", run)
    run = Run(["--replay"], env=dict(ports, FAKE_COMPOSE_UP_ERROR="ERROR: failed to solve: network unreachable"))
    check("a real build failure", run.code == 1 and "The build failed" in run.out and "Maven Central" in run.out, "still reads as a build failure", run)

    # The time reported includes the build
    run = Run(["--replay"], env=dict(ports, FAKE_BUILD_SECONDS="2"))
    check("time", run.code == 0, "installs", run)
    line = next((l for l in run.out.splitlines() if l.startswith("Shutter is ready after")), "")
    seconds = line.split("after ")[-1].split(" s:")[0]
    check("time", seconds.isdigit() and int(seconds) >= 2, f"counts the build ({line!r})", run)

    # The refusals around editions still stand
    run = Run(["--replay"], env=ports, dotenv="SHUTTER_WEB_PORT=8080\n")
    check("edition guard", run.code == 1 and "set up for the AI Hub edition" in run.out and not run.built, "an .env of the other edition is still refused", run)
    run = Run([], env=dict(ports, FAKE_NO_IMAGE="1"))
    refuses("no image", run, "The AI Hub image (irishealth-community:2027.1.0AI.109.0) is not loaded")

    # The help still shows the whole header and nothing of the code
    run = Run(["--help"])
    check("help", "Another port: SHUTTER_WEB_PORT=8080" in run.out and "set -euo" not in run.out, "prints the header", run)

    print(f"\n{len(failures)} failed" if failures else "\nall passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
