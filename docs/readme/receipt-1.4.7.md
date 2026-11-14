# A fresh install of release 1.4.7 on AI Hub build 154

The earlier receipts ([build 154](receipt.md) and [build 109](receipt-109.md)) were made on release 1.0.0 and later spot checks. This page is the same step for release 1.4.7: the exact commit installed fresh on an unmodified AI Hub build 154 container by following [the install guide](../INSTALL.md) as written, then a replay pass with no provider key, a site install with the demo off that starts in shadow mode, and the approval boundary checks. No model was called anywhere on this page.

**When and what:** 14 November 2026, 18:04 to 18:50 UTC (GMT), commit `efa2db3509f677c8f58e52a62b47f1aed795f41e`, on a Linux VM with 10 vCPUs and 22 GB of memory (Ubuntu 26.04.1 LTS, Docker 29.1.3, Compose 2.40.3, Python 3.14.4, curl 8.18.0), with `irishealth-community:2026.3.0AI.154.0` already loaded. Every instance was a new container from that image, with no volume from an earlier run and nothing of Shutter's on it. The run was made before the tag `v1.4.7` existed; to confirm the tag later, `git rev-parse v1.4.7^{commit}` must print the commit above.

## What was installed

| | |
| --- | --- |
| Release | 1.4.7 |
| Commit | `efa2db3509f677c8f58e52a62b47f1aed795f41e` (`main` on `origin` at the time, by `git ls-remote origin refs/heads/main`; no tag on it yet) |
| `module.xml` | `iris-shutter` 1.4.7, `SystemRequirements Version=">=2026.3" Interoperability="enabled"` |
| `core/module.xml` | `iris-shutter-core` 1.4.7, `SystemRequirements Version=">=2026.2" Interoperability="enabled"` |
| How the source reached the VM | `git archive efa2db35 \| ssh <vm> 'tar -xf - -C ~/shutter'`: 39,096,320 bytes, 1,823 files. The archive's own commit header (`git archive efa2db35 \| git get-tar-commit-id`) is the commit above |
| How it reached the container | INSTALL's own form, `tar -cf - . \| docker exec -i -u root <container> sh -c 'mkdir -p /home/irisowner/pkg && tar -xf - -C /home/irisowner/pkg && chown -R irisowner:irisowner /home/irisowner/pkg'`, so `<module>` is `/home/irisowner/pkg` |
| Identity of the installed tree | `find . -type f -print0 \| LC_ALL=C sort -z \| xargs -0 sha256sum \| sha256sum` prints `31539cd679178a5038ff7985b5c573e8327d91c5ab52244c115eb77d0d61aec4` for `git archive efa2db35` unpacked on the build host, for the VM's copy, and for `/home/irisowner/pkg` inside the container (1,823 files each) |
| Image | `irishealth-community:2026.3.0AI.154.0` (also tagged `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0`), image id `sha256:bbea4364ab6fbd7810219780fa76730fc2977d8cf76f3e01b92c5d4291a2feae`, linux/amd64, created 24 September 2026 18:02 UTC; its `RepoDigests` entries repeat the image id, so there is no registry digest to quote for it |
| Its `$ZVERSION` | `IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:04:49 EDT` |
| Secrets on the VM | None: no provider key, no GitHub key, no token |

Every instance here is IRIS for Health with AI Hub. Plain InterSystems IRIS was not tried.

## The results at a glance

| Run | Route | Namespace | Package | Time for INSTALL's block | Health | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| A | INSTALL 3.1's block with `zpm "load <module>"`, demo on | `SHUTTER` | `iris-shutter` 1.4.7, from the folder | 2 min 3 s | `"version":"1.4.7"`, `"demo":true`, `"ok":true` | Replay pass and boundary checks below |
| B | The same with `-Ddemo=0`, a site install | `SHUTTER` | `iris-shutter` 1.4.7, from the folder | 1 min 44 s | `"version":"1.4.7"`, `"demo":false`, `"ok":true` | Shadow mode; nothing sent |
| C | INSTALL 3.1's block as printed: `zpm "install iris-shutter -Ddemo=0"` | `SHUTTER` | `iris-shutter` **1.4.6**, from the public registry | 1 min 44 s | `"version":"1.4.6"`, `"ok":true` | The registry does not have 1.4.7 yet (run C, below) |

## Run A: the demo, by path, on a fresh build 154 container

INSTALL names no route for a demo on an AI Hub instance beyond section 3.1's block, which says that without `-Ddemo=0` it installs the demo, and that for the exact version of a clone `zpm "load <module>"` replaces `zpm "install iris-shutter"` (the registry cannot serve 1.4.7 yet). The block was run as printed with that one change and without `repo -reset-defaults`, which `load` does not need. Container `v11-rel3-receipt-demo`, host port 52930.

| Step | Time | What it answered |
| --- | --- | --- |
| `docker run -d --name v11-rel3-receipt-demo -p 127.0.0.1:52930:52773 irishealth-community:2026.3.0AI.154.0 --check-caps false --ISCAgent false` | 0.2 s | |
| `until docker exec ... iris qlist IRIS \| grep -q '\^running'; do sleep 5; done; sleep 5` | 15.1 s | |
| the source into `/home/irisowner/pkg` | 0.2 s | |
| `USER`: "Before you install" (INSTALL's report): load `Onboard.cls` and `SiteCheck.cls`, `Do ##class(Shutter.Util.SiteCheck).Print()`, delete both | 0.2 s | "Shutter can go here, with the changes below." PASS "IRIS 2026.3 with AI Hub: the whole package fits"; PASS `%Admin_Manage`; INFO IPM is not in this namespace; INFO port 52773; PASS 7 licence units free; WARN no namespace has Interoperability on and a production (nothing to watch yet) |
| `USER`: `Do $SYSTEM.OBJ.Load("<module>/src/Shutter/Setup.cls", "ck")`, `Write ##class(Shutter.Setup).CreateNamespace("SHUTTER")`, `zn "SHUTTER"` | 54.1 s | "Install ok"; `$NAMESPACE` is `SHUTTER` |
| `SHUTTER`: `Do $SYSTEM.OBJ.Load("<module>/vendor/ipm/zpm-0.10.10.xml", "ck")` | 17.5 s | "Load finished successfully." |
| `SHUTTER`: `zpm "load /home/irisowner/pkg"`, then `zpm "list"` | 51.1 s | Every phase SUCCESS; `Shutter.Production` and `Hospital.Production` started; the AI Hub step reports `"ai_hub_present":true`, `"provider":"no key in the environment: the agents replay recordings"`, six knowledge bases and `created /mcp/shutter`. `zpm "list"`: `IPM (zpm) 0.10.10`, `iris-shutter 1.4.7` |
| `curl http://localhost:52930/api/shutter/health` | 0.5 s | HTTP 200 |

The block (the three steps that install Shutter) took 2 min 3 s; container start to health, 2 min 20 s. INSTALL's "about 2.5 minutes on clean 154 and 109 containers" held.

```json
{"demo":true,"version":"1.4.7","production":"Shutter.Production","production_state":"running","mode":"board","last_live_run":null,"credentials_ok":true,"credentials_state":"fresh","receivers_ok":null,"watched_ok":true,"ok":true,"live":{"enabled":false}}
```

### The Doctor

`SELECT Shutter.Setup_Doctor()` in `SHUTTER`:

| Field | Value |
| --- | --- |
| `version`, `demo`, `edition` | `1.4.7`, `true`, `aihub` |
| `ai_hub_present`, `aihub_runner` | `true`, `true` |
| `board_members`, `recordings` | 5, 174 |
| `missing_items`, `disabled_items` | `[]`, `[]` |
| `production_state` | `running` |
| `catalogue_entries` | 19 |
| `provider`, `provider_config`, `wallet_secret` | `""`, `false`, `false` |
| `last_live_run`, `budget.spentTodayUsd` | `null`, 0 |
| `second_parser` | `available: false`, "no jar: the Second Parser item stays disabled" (`pex/build.sh` was not run; INSTALL section 2 says so) |
| `fhir` | `FHIR Ward Out`: `recovery_enabled: true`, `proof: "matches"` |
| `publish` | `available: true`, `webapp: true` |
| `credentials_ok`, `credentials_state` | `true`, `fresh` |
| `python_zoneinfo`, `records_namespace`, `api_webapp`, `ui_webapp`, `wards_webapp`, `records_webapp`, `purge_task` | all `true` |

What the instance holds: `zpm "version"` lists `HSLIB> zpm 0.10.5-SNAPSHOT`, `SHUTTER> zpm 0.10.10` and `HSSYS> zpm 0.10.5-SNAPSHOT`; the demo users `operator`, `approver`, `forwarder`, `downstream-client` and `fhir-client` exist; `Shutter.Production` has 35 items, 34 enabled and `Second Parser` disabled; `RecoveryControl.Mode()` answers `enabled` (the demo seeds it); the tasks are "Shutter case reminders", "Shutter message purge" and "Shutter retention". The web app answers: `/shutter` 302 to `/shutter/index.html`, which answers 200.

### The no-key replay pass

`python3 tests/e2e/scenario_check.py --url http://127.0.0.1:52930 --modes <mode> --approve <ids>`, signed in as the demo's `operator` and `approver`, with no key anywhere: the board and single runs replay recordings, and the gate, the approval, the write to the demo receiver and its verification are IRIS's own work.

**The first attempt failed.** Right after the install:

```text
$ python3 tests/e2e/scenario_check.py --url http://127.0.0.1:52930 --modes board --approve S2 S3 S8
DIFFERS S2 board: C-000001 resolved, resend, one write, downstream None None: the downstream system holds None None, expected admitted WARD-B
DIFFERS S3 board: C-000002 resolved, reconcile, no write, downstream None None: the downstream system holds None None, expected admitted WARD-B
DIFFERS S8 board: C-000003 escalated, escalate, no write, downstream None None: the downstream system holds None None, expected admitted WARD-C
3 of 3 differ
```

The cases themselves resolved and escalated as expected; what failed was the check's read of the demo receiver as `_SYSTEM` / `SYS`. `curl -u _SYSTEM:SYS http://127.0.0.1:52930/downstream/api/encounters/probe` answered HTTP 401, and `Security.Users` showed `_SYSTEM` with `ChangePassword=1`, the stock image's flag. The Docker route and `scripts/stock-install-check.sh` clear it; a load by hand does not. The step that `scripts/stock-install-check.sh` and `iris.script` use, in `%SYS`:

```objectscript
Do ##class(Security.Users).UnExpireUserPasswords("*")
```

took 65 ms, after which the same read answered HTTP 404 (no such encounter), and the check ran as follows.

| Command (`--approve`) | Case ids | Result | Time |
| --- | --- | --- | --- |
| `--modes board S2 S3 S8` | C-000004 to C-000006 | `ok S2 board: resolved, resend, one write, downstream admitted WARD-B`; `ok S3 board: resolved, reconcile, no write, downstream admitted WARD-B`; `ok S8 board: escalated, escalate, no write, downstream admitted WARD-C`; **all 3 as expected** | 61 s |
| `--modes single S2 S3 S8` | C-000007 to C-000009 | S2 ok (resend, one write, WARD-B); **S3 differs**: `blocked, resend, no write ... disposition resend, expected reconcile`; S8 ok (escalate, no write, WARD-C); 1 of 3 differ | 60 s |
| `--modes rules S2 S3 S8` | C-000010 to C-000012 | S2 ok; **S3 differs**: `blocked, resend, no write ... expected reconcile`; **S8 differs**: `resolved, resend, one write ... downstream admitted WARD-B, expected WARD-C`; 2 of 3 differ | 66 s |
| `--modes policy S2 S3 S8 S35` | C-000013 to C-000016 | `ok S2 policy: resolved, resend, one write, downstream admitted WARD-B`; `ok S3 policy: resolved, reconcile, no write, downstream admitted WARD-B`; `ok S8 policy: escalated, escalate, no write, downstream admitted WARD-C`; `ok S35 policy: resolved, resend, one write, at FHIR Ward Out in-progress WARD-B (Location/ward-b, versions 1, 2, marked 2)`; **all 4 as expected** | 89 s |

The three differences, read from the cases: in single and rules modes S3's proposal is a resend, where `fixtures/scenarios.json` expects a reconcile, and the gate blocks it with `ALREADY_COMMITTED` ("The receiver already committed this operation; a resend would be a duplicate"), so nothing was written (C-000008 and C-000011 are `blocked`); in rules mode S8's resend was dispatched and wrote WARD-B over the bed manager's WARD-C (C-000012 resolved with one write), which is what the README shows for that run, since the recorded scenario is exempted on purpose from `ENTRY_NOT_NAMED_WRITE`. The board and site policy modes, the two CI counts, matched on S2, S3 and S8, and S35, the FHIR scenario, which a demo install places and which runs in site policy only, passed.

### The approval boundary checks, on the demo

```text
$ python3 tests/e2e/boundary_check.py --url http://127.0.0.1:52930
...
all 44 checks passed          (114 s, exit 0)
```

Cases C-000017 to C-000021. In order, each with the receiving system's record unchanged and no write attempt: an approval naming another plan digest is 409 `stale_version`; an approval at an older case version is 409 `stale_version`; the operator's approval is 403 `forbidden`; the approver's is 202; the same approval with the same `Idempotency-Key` gets the same reply, and the key with another body is 409 `idempotency_key_reused`; the case resolves as a resend with one write attempt, made after a dry run bound to the approval and under the policy the approval bound (2026-11-07.1); a fresh approval of the resolved case is 409 `wrong_state`; the approval records the signed-in approver, not a name in the body; two approvers at the same moment leave one decision and one write; S20's nurse moves the patient while the plan waits, the approval is voided at dispatch (`APPROVAL_RECEIVER_CHANGED`) with no write attempt and the nurse's entry (WARD-C) stands; S3's rules resend is blocked by `ALREADY_COMMITTED` with no write attempt.

### Shadow mode and the stop, counted on the wire (demo)

`tests/e2e/shadow_pilot_check.py` puts a counting proxy between the connector `Downstream Out` and the demo receiver, plays S2's messages under fresh identifiers, and reads what reached the wire. It changes the instance and restarts it, so it was run last on this throwaway container, with the checks above already recorded.

```text
$ python3 -u tests/e2e/shadow_pilot_check.py --ctr v11-rel3-receipt-demo --url http://127.0.0.1:52930 --ns SHUTTER
...
Shadow mode and the stop: as documented, counted on the wire.          (60 checks ok, 0 FAIL, exit 0)
```

In order: with recovery enabled, one rehearsal and one authorised write reach the wire and the case resolves; a stop needs a reason, an operator can stop but neither clear nor change the mode, the record names the signed-in user and not the name in the body, an approval is refused while stopped, the ordinary feed goes on, and no rehearsal or write reaches the wire; the stop outlives a production restart and an instance restart; a clear needs a reason and a current generation, and releases no earlier plan (its approval is refused until the plan is rejected and the case reinvestigated, after which it writes once); a write nobody answered reads as uncertain and recovery is not stopped; a write cut off by a restart stops recovery, is listed as uncertain, and is not retried on the wire; in shadow mode the ordinary feed goes on, the case goes to a person, no rehearsal and no write reaches the wire, a preview is refused, and the shadow report and its CSV count the case with a candidate for rehearsal and name no patient; enabling again releases nothing.

**The first attempt failed, and is kept.** Started at 18:24 right after the checks above, it printed `FAIL the connector goes through the counting proxy (<LICENSE LIMIT EXCEEDED>`, because the container's own `iris session` could not get a licence unit while the earlier checks' sign-ins held the Community licence's connections, and every step after it timed out (no case opened, the wire counts stayed 0). It was stopped at about 18:43. The second attempt, about 20 minutes later when those sign-ins had lapsed, passed all 60 checks.


## Run B: a site install, `-Ddemo=0`, on a fresh build 154 container

INSTALL section 3.1's block with `-Ddemo=0`, by path: the same commands as run A with `zpm "load /home/irisowner/pkg -Ddemo=0"`. Container `v11-rel3-receipt-site`, host port 52931.

| Step | Time |
| --- | --- |
| `docker run`; the `until ... qlist` wait; the source into `/home/irisowner/pkg` | 0.2 s, 15.1 s, 0.2 s |
| `USER`: load `Setup.cls`, `CreateNamespace("SHUTTER")`, `zn "SHUTTER"` | 50.5 s |
| `SHUTTER`: load `vendor/ipm/zpm-0.10.10.xml` | 17.4 s |
| `SHUTTER`: `zpm "load /home/irisowner/pkg -Ddemo=0"`, `zpm "list"` | 35.6 s |
| `curl http://localhost:52931/api/shutter/health` | 0.5 s |

The block took 103.5 s. `zpm "list"`: `IPM (zpm) 0.10.10`, `iris-shutter 1.4.7`. Health:

```json
{"demo":false,"version":"1.4.7","production":"Shutter.Production","production_state":"running","mode":"board","last_live_run":null,"credentials_ok":true,"credentials_state":"fresh","receivers_ok":null,"watched_ok":true,"ok":true}
```

What it holds, against INSTALL section 1's words for a non-demo install:

- **Shadow mode.** `##class(Shutter.Util.RecoveryControl).Mode()` answers `shadow`, and so does `GET /api/shutter/recovery-control` signed in as a user holding `Shutter_Operator`: `{"mode":"shadow","stopped":false,"generation":1,"outstandingCount":0,"readable":true}`. The stored site profile has no `recovery` field (CONTRACTS 18: absent reads as shadow). The health route's `"mode":"board"` is the scenario run mode, not this.
- **No demo users, receiver or data.** `Security.Users` holds only the stock image's ten users (`Admin`, `CSPSystem`, `HS_Services`, `IAM`, `SuperUser`, `UnknownUser`, `_Ensemble`, `_PUBLIC`, `_SYSTEM`, `irisowner`); namespaces `SHUTTER` and the stock ones only, no `RECORDS` or `HOSPITAL`; the Doctor says `"demo":false`, `"recordings":0`, `"records_namespace":false`, `"wards_webapp":false`, `"records_webapp":false`, `"purge_task":false`, `"credentials":[]`.
- **Items.** `ADT In`, `ADT to Downstream`, `ADT to Records`, `Downstream Out`, `Records Out` and `Scenario Player` are present and switched off, as is `Second Parser` (no jar); the other 24 are enabled (31 items in all) and `Shutter.Production` runs.
- **Web applications and tasks.** `/api/shutter`, `/shutter` and the publisher's `/mcp/shutter` are Shutter's; the tasks are "Shutter case reminders" and "Shutter retention" (no "Shutter message purge"). The web app answers: `/shutter` 302 to `/shutter/index.html`, which answers 200.
- **What the platform added, not Shutter.** Making the namespace on IRIS for Health also added the web applications `/csp/healthshare/shutter`, `.../bulkfhir`, `.../bulkfhir/api` and `.../services` and the credential `HS_Services`.
- **Left in `USER`.** `Shutter.Setup` stays compiled in `USER`, the namespace the install block was run from.
- **Doctor, selected:** `version` 1.4.7, `demo` false, `edition` `aihub`, `ai_hub_present` true, `board_members` 5, `missing_items` `[]`, `catalogue_entries` 19, `provider` `""`, `last_live_run` null, `publish` available, `receivers` one placeholder ("Your first receiver", `has_api` false).

### Boundary checks on the site install

`tests/e2e/boundary_check.py` signs in as the demo's `operator` and `approver` and plays scenarios against the demo receiver, so on this install it stopped at the first line:

```text
$ python3 tests/e2e/boundary_check.py --url http://127.0.0.1:52931 --timeout 60
sign-in as operator failed: HTTP 401 {'error': 'invalid_credentials', 'detail': 'The username or password is wrong'}          (exit 1)
```

In its place, the refusals were probed through the REST API as the users INSTALL section 5, step 3 asks for. INSTALL gives no commands for them; these were used, in `%SYS` for the users and in `SHUTTER` for the Workflow membership, with a throwaway password:

```objectscript
Do ##class(Security.Users).Create("site-operator","Shutter_Operator",pw,"Site operator","SHUTTER")
Do ##class(Security.Users).Create("site-approver","Shutter_Approver",pw,"Site approver","SHUTTER")
Do ##class(Security.Users).Create("site-approver-nowf","Shutter_Approver",pw,"Approver outside the role","SHUTTER")
Do ##class(Security.Users).Create("site-forwarder","Shutter_Forwarder",pw,"Site forwarder","SHUTTER")
Do ##class(EnsLib.Workflow.UserDefinition).CreateUser("site-approver","Site approver")
Do ##class(EnsLib.Workflow.RoleDefinition).AddUserToRole("Shutter Approvers","site-approver",1,"Approver")
```

(The first attempt ran the `Security.Users` lines from `SHUTTER` and answered `<CLASS DOES NOT EXIST> *Security.Users`; they belong in `%SYS`.) Then a short script of REST calls (`site-probes.py`, standard library only, kept with this run's logs) sent one failed `fixtures/S2/S2-02-A02.hl7` transfer to `POST /api/shutter/intake` as the forwarder and read the case and the refusals:

| # | Probe | Answer |
| --- | --- | --- |
| 1 | `GET /health`, nobody signed in | 200, `"version":"1.4.7"`, `"demo":false`, `"ok":true` |
| 2 | `GET /recovery-control`, operator | 200, `"mode":"shadow"`, `"stopped":false` |
| 3 | `GET /site-profile`, operator | 200, no `recovery` field, `receivers` empty |
| 4 | `PUT /site-profile` with `recovery` set to `enabled`, operator | 403 `forbidden`, "This needs Shutter_Configure" |
| 5 | `POST /recovery-control/clear`, operator | 403 `forbidden`, "This needs Shutter_Configure" |
| 6 | `POST /intake`, nobody signed in | 401 `unauthenticated` |
| 7 | `POST /intake` as the forwarder (Basic) | 202 `{"caseId":"C-000001","state":"detected","opened":true}` |
| 8 | `GET /cases`, forwarder | 403 (a forwarder opens cases and reads none) |
| 9 | the case, after about 10 s | `state` `blocked`, `disposition` `resend`, `mode` `policy`, `planCreatedBy` `rules`; blocked reason `RECEIVER_UNREADABLE`, with `RECEIVER_NOT_IN_PROFILE`, `CAPABILITIES_UNREADABLE` and `NEW_PATTERN` among the failing checks |
| 10 | `GET /cases/C-000001/attempts` | `[]`; `approvals` and `tasks` also `[]` |
| 11 | `POST /cases/C-000001/approvals`, operator | 403 `forbidden`, "This needs Shutter_Approve" |
| 12 | the same, approver in the Workflow role | 409 `wrong_state`, "The case is blocked, not awaiting approval" |
| 13 | the same, approver outside the Workflow role | 409 `wrong_state`, the same words (the state check comes first; the Workflow role's 403 needs a plan waiting, which this install cannot produce, see below) |
| 14 | `GET /shadow-observations`, operator | 200, one case reaching Shutter, proposed `resend` 1, proposal gate `block` 1, `candidatesForRehearsal` 0 |
| 15 | `GET /recovery-control` and the site profile after the probes | still `"mode":"shadow"`, `generation` 1; no `recovery` field |

Counted afterwards in `SHUTTER`: `Shutter_Store.DispatchPermit` 0 rows (no rehearsal or write was admitted), `Ens.MessageHeader` rows to `Downstream Out`, `Records Out` or `Engine Resend` 0, and `<mgr>/shutter/out/mail` does not exist (shadow mode wrote no escalation email). The case's counts: 18 events, 3 runs, 1 plan, 0 approvals, 0 attempts. Nothing was sent to any receiver and recovery was never enabled.

## Run C: the public registry, as INSTALL prints it

INSTALL section 3.1's block verbatim, including `zpm "repo -reset-defaults"` and `zpm "install iris-shutter -Ddemo=0"`, on a third fresh container (`v11-rel3-receipt-reg`, port 52932).

| Step | Time |
| --- | --- |
| `USER`: load `Setup.cls`, `CreateNamespace("SHUTTER")`; `SHUTTER`: load `zpm-0.10.10.xml` | 49.7 s, 17.4 s |
| `SHUTTER`: `zpm "repo -reset-defaults"`, `zpm "install iris-shutter -Ddemo=0"`, `zpm "list"` | 37.0 s |

IPM printed `WARNING: Using -password via the CLI is insecure. Use -password-stdin or -password-env.` for `repo -reset-defaults`, which passes no password. The registry is `https://pm.community.intersystems.com`; IPM reloaded the module from `/usr/irissys/ipm/iris-shutter/1.4.6/`; `zpm "list"` shows `iris-shutter 1.4.6` and health says `"version":"1.4.6"`. So **the command in INSTALL does not install 1.4.7**: the registry answered, from House, at 18:12 UTC:

```text
$ curl -s https://pm.community.intersystems.com/packages/iris-shutter      (HTTP 200)
version = 1.4.6      versions = 1.0.0, 1.1.1, 1.2.0, 1.2.1, 1.3.0, 1.3.2, 1.4.0 to 1.4.5, 1.4.6
url = https://pm.community.intersystems.com/download/iris-shutter/-/iris-shutter-1.4.6.tgz
size = 11,343,612 bytes     hash (SHA-1) = 3821b117a1281baa6a3da45c36fa7158ba5cd30c     publishTS = 14 Nov 2026 13:36:13 UTC
```

The archive downloaded from that address has that SHA-1 (SHA-256 `abb02c4a68137c6dd9b7c4f9c226c1a0db052f679bb3a7347532290a798ce761`), and the manifest of `/usr/irissys/ipm/iris-shutter/1.4.6` in the container equals the manifest of the archive unpacked (`98768e00...`, 1,823 files). That tree is **not the tag `v1.4.6`**: the tag (`f78cfd18...`, 1,779 files, 14 Nov 13:01 UTC) differs from it in 230 files, and the archive's tree is exactly the tree of the merge commit `ff42e469` ("Merge release 1.4.6 into main", 13:15 UTC), which already holds S35, the FHIR ward scenario (`"S35"` is in its `fixtures/scenarios.json` and not in the tag's). A working install from the registry therefore identifies a commit, not the release's tag. For 1.4.7 the same comparison has to be made once the tag and the registry copy exist.

## What was not run

- **A live model call: NOT RUN.** No provider key was on the VM. The Doctor says `"provider":""`, `"last_live_run":null` and the day's budget shows `"spentTodayUsd":0`. No live agent, typed tool call or trace was exercised.
- **`./install.sh` (the Docker route): NOT RUN.** This receipt follows INSTALL's IPM route; the installer uses a fixed container name and port 52773, outside the ports this run was given.
- **The registry route for 1.4.7: NOT POSSIBLE.** The registry serves 1.4.6 (run C).
- **AI Hub build 109: NOT RUN**, and **plain IRIS for Health 2026.2** with `iris-shutter-core`: NOT RUN.
- **The Second Parser's jar** (`pex/build.sh`): NOT RUN; the item is disabled on every instance here and the Doctor says so.
- **Enabling recovery** (INSTALL section 5, step 9) and **the Management Portal Workflow inbox: NOT RUN.** Run B stayed in shadow mode throughout. The approval of a plan by a user outside the Workflow role (403) was therefore not exercised on a site install; a site install with no receiver API produces no plan that waits for approval.
- **The uninstall and an upgrade over an older install: NOT RUN**; every install here was cold.
- **`scripts/stock-install-check.sh`: NOT RUN.**
- **A browser pass** over the web application: NOT RUN; only HTTP status codes were read (`/shutter` 302, `/shutter/index.html` 200, `/csp/sys/UtilHome.csp` 200 on all three instances).
- **Observed, not looked into:** the demo container read `(unhealthy)` in `docker ps` from about 18:07 onwards, after the install and during the scripted checks, while health and the web app answered throughout. `iris qlist` reported the instance's state as `alert` (`docker exec ... iris qlist \| cut -d^ -f9`), and `messages.log` says `License limit exceeded 26 times since Sat Nov 14 18:07:28 2026`, the Community licence's connections used by the checks' sign-ins (the troubleshooting page's "License limit exceeded"). The site and registry containers, which had no scripted sign-in burst, stayed `(healthy)`. The same licence limit made the first attempt of the shadow check fail (above); the demo container read `(healthy)` again after that check restarted it.

Where the install guide's words differ from what these runs did, the findings list kept with this receipt has each place with its exact fix.
