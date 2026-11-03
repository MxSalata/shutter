# A fresh clone on AI Hub build 109

Since 2 November 2026 InterSystems' Early Access portal offers the AI Hub build `2027.1.0AI.109.0` (Community) and no longer `2026.3.0AI.154.0`, the contest's first build; the organisers asked entries to say which build they use. This page is the record of Shutter on build 109: a fresh copy installed with `install.sh` from the downloaded file, then checked as on build 154 ([receipt on 154](https://github.com/MxSalata/shutter/blob/main/docs/readme/receipt.md)). No code changed for the new build; only the installer's defaults name it.

**When and what:** 3 November 2026, 15:11 UTC, commit `35284e1`, on a Linux VM with 12 threads and 11 GB of memory (Docker 29.1.3, Compose 2.40.3), starting with no `.env`, no Shutter image and the AI Hub image not loaded, only its file, `irishealth-community-2027.1.0AI.109.0-docker.tar.gz` (5.5 GB). IRIS reports `2027.1.0AI (Build 109U) Fri Oct 30 2026`. The build installs the one IPM package, `iris-shutter` (the core and the agents); `zpm "list"` shows `iris-shutter 0.1.0`.

## The install

```text
$ ./install.sh --image-file irishealth-community-2027.1.0AI.109.0-docker.tar.gz
Checking (nothing is changed yet):
  [ok]  Docker 29.1.3 is running
  [ok]  Docker Compose 2.40.3+ds1-0ubuntu1
  [ok]  Docker has about 11 GB of memory
  [ok]  Docker's disk has about 105 GB free
  [ok]  Port 52773 is free
  [ok]  The AI Hub image will be loaded from irishealth-community-2027.1.0AI.109.0-docker.tar.gz
  [ok]  .env will be created from .env.example

Every check passed. Installing:
  loading the AI Hub image (a few minutes)
    Loaded image: docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0
  tagged docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0 as irishealth-community:2027.1.0AI.109.0
  created .env
  building and starting (2 to 15 minutes the first time)
     ...

Shutter is ready after 10 s:
  the web app:   http://localhost:52773/shutter/index.html  (approver / shutter, or operator / shutter)
  ...

real	3m21.343s
```

The build log says "AI Hub is in this image: loading the full package (the core and the live agents)", and the AI Hub install reports the descriptor registry, six knowledge bases (contracts, lifecycle, effects, playbooks, review, explain) and the publisher's `/mcp/shutter`.

## The Doctor

`SELECT Shutter.Setup_Doctor()` (or `Write ##class(Shutter.Setup).Doctor()` in the namespace `SHUTTER`):

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
| `credentials_ok`, `credentials_state` | `true`, `fresh` |
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

## Every scenario on build 109

Earlier the same afternoon, on the same VM, commit `7d85c18` built on build 109 with `docker compose` (2 minutes 40 seconds) and played every scenario through the REST API, as CI does on IRIS for Health Community 2026.2:

- On the board, with the recorded runs: S1 to S10, S13, S15, S16, S21 and S25, all 15 as expected.
- In Site policy mode: S11 and S12 (incidents, every chain verified), S17, S18, S19, S21, S22 (both receivers), S23a to S23c, S24 and S25, all 12 as expected.
- In Rules only mode: S20 (the nurse's entry stands, no write) and S21, both as expected.
- `lineage_check.py`: 47 cases, every write after the gate and a rehearsal, every resolved resend verified; `eventlog_check.py`: no runtime errors.

With no key in `.env`, the board replayed its live runs recorded on build 154. The live board was not run on build 109 for this receipt.
