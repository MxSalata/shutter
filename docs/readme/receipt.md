# A fresh clone on AI Hub build 154

CI builds Shutter's core on the public IRIS for Health image, because the AI Hub build comes only from InterSystems' Early Access portal. This page is the record of the step CI cannot take: a fresh clone installed on build 154 with `install.sh`, then checked. It is made again for each release.

**When and what:** 2 November 2026, 17:05 UTC, commit `b8cfca6`, on a Linux VM with 12 threads and 12 GB of memory (Docker 29.1.3, Compose 2.40.3) that was running another build at the same time, with `irishealth-community:2026.3.0AI.154.0` already loaded. No `.env` was there before the run. The build installs the one IPM package, `iris-shutter` (the core and the agents, for IRIS 2026.3 and later); `zpm "list"` shows `iris-shutter 0.1.0` alone.

## The install

```text
$ ./install.sh
Checking (nothing is changed yet):
  [ok]  Docker 29.1.3 is running
  [ok]  Docker Compose 2.40.3+ds1-0ubuntu1
  [ok]  Docker has about 11 GB of memory
  [ok]  Docker's disk has about 73 GB free
  [ok]  Port 52773 is free
  [ok]  The AI Hub image irishealth-community:2026.3.0AI.154.0 is loaded
  [ok]  .env will be created from .env.example

Every check passed. Installing:
  created .env
  building and starting (2 to 15 minutes the first time)
     ...
     Container shutter  Started

Shutter is ready after 12 s:
  the web app:   http://localhost:52773/shutter/index.html  (approver / shutter, or operator / shutter)
  ...

real	2m54.870s
```

## The Doctor

`SELECT Shutter.Setup_Doctor()` (or `Write ##class(Shutter.Setup).Doctor()` in the namespace `SHUTTER`), the fields that show the AI Hub module compiled and the production is complete:

| Field | Value |
| --- | --- |
| `edition` | `aihub` |
| `ai_hub_present`, `aihub_runner` | `true`, `true` |
| `board_members` | 5 |
| `recordings` | 174 |
| `missing_items` | `[]` |
| `disabled_items` | `[]` |
| `production_state` | `running` |
| `catalogue_entries` | 18 (E1 to E18) |
| `second_parser` | `available: true`, `probe: ok`, `parser: HAPI 2.6.0 (Java, PEX)` |
| `publish` | `available: true`, `webapp: true` (the read-only MCP tools) |
| `python_zoneinfo` | `true` |
| `records_namespace`, `api_webapp`, `ui_webapp`, `wards_webapp`, `records_webapp`, `purge_task` | all `true` |

## Three scenarios, then the checks CI runs

```text
$ python3 tests/e2e/scenario_check.py S2 S8 S25 --modes board --approve
ok      S2 board: C-000001 resolved, resend, one write, downstream admitted WARD-B
ok      S8 board: C-000002 escalated, escalate, no write, downstream admitted WARD-C
ok      S25 board: C-000003 blocked, resend, no write, downstream admitted WARD-A
all 3 as expected

$ python3 tests/e2e/lineage_check.py
3 cases checked: every write came after the gate and a rehearsal, and every resolved resend was verified

$ python3 tests/e2e/eventlog_check.py
SHUTTER: 3 error and warning rows read
HOSPITAL: 0 error and warning rows read
no runtime errors in the Event Log
```

With no key in `.env`, the board replayed its recorded live runs. S25's case is blocked as designed: the Second Parser finds the message sound, so what is missing is the site's schema for its ZZZ segment.
