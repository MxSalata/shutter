# Shutter: failed hospital messages put right safely, with nothing written to a clinical system until it is proven, approved and verified

[![CI](https://github.com/MxSalata/shutter/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/MxSalata/shutter/actions/workflows/ci.yml) [![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](https://github.com/MxSalata/shutter/blob/main/LICENSE)

When an HL7 delivery fails in a hospital, the usual fix is a resend from the Message Viewer. If the patient has moved since, that resend moves them back. Shutter turns each failed delivery into a case instead. A board of IRIS AI Hub agents reads sealed evidence and proposes what to do. A deterministic gate checks the plan. A person, or the site's own written policy, releases it. Shutter then makes one conditional write and checks the receiving system's own history to prove it landed. The AI board proposes; the gate disposes.

[screenshot: the Scenarios start page with the three scenarios to try first]

[screenshot: the S8 case page, rules alone beside the board, with what each did at the receiver]

![The Visual Trace of S8 in board mode: the failed delivery, the case workflow, the evidence collector, the three specialists, the coordinator and the gate, each in its own lane](https://raw.githubusercontent.com/MxSalata/shutter/main/web/public/s8-visual-trace.png)

**In three lines:**

- **S8, the case a gate cannot catch.** Two systems move one patient in the same minute. Rules alone pass every check and write WARD-B over the bed manager's WARD-C. The board sees that the evidence cannot say which movement is current, and escalates to a person.
- **The board gets 11 of the 11 single cases it is convened for, live and in replay. Rules alone get 4 of those 11.** The table is in [docs/readme/comparison.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/comparison.md); it was played on 19 October 2026 (5.31 USD for that recording) and is played again when the demo is re-recorded. The evaluation below uses the recordings of 25 October 2026.
- **0.34 to 0.44 USD and 24 to 32 seconds a board pass** with `claude-opus-5-5`, the three specialists running in parallel. Without an API key the board replays its own recorded live runs, so trying it costs nothing.

## Try it in five minutes

**Online demo:** [planned: ONLINE-DEMO-LINK, a live IRIS instance running Shutter in replay mode]. Sign in with **Try the demo**, or as `approver` / `shutter`.

**On your machine:** you need Docker and the IRIS for Health AI Hub image (build 154) from InterSystems' Early Access portal. Load it, tag it and start Shutter:

```sh
docker image load -i irishealth-community-2026.3.0AI.154.0-docker.tar.gz
docker tag docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0 irishealth-community:2026.3.0AI.154.0
git clone https://github.com/MxSalata/shutter.git && cd shutter
cp .env.example .env
docker compose up -d
```

Open http://localhost:52773/shutter/index.html and sign in as `approver` / `shutter`. The first build takes about 10 to 15 minutes. No Early Access file? See [Run it](https://github.com/MxSalata/shutter#run-it) for the replay edition on the public IRIS for Health Community image.

## What the judges should look at

Open **Scenarios**. Each card is a real kind of failure, with what should happen.

- **S2, a transfer that never arrived.** The board proposes a resend, the gate passes it, the receiver's dry run says it would apply. **Approve**: one conditional write, then "Verified" from the receiver's history.
- **S8, the case a gate cannot catch.** Run it in Rules only mode and approve: the resend overwrites the bed manager's newer placement. Run it in board mode: the board escalates. The case page sets the two side by side.
- **S20, a nurse moves the patient by hand.** While the resend waits for approval, a nurse moves the patient to Ward C in the downstream system itself. The approval is bound to the receiver's version, so nothing is sent (`APPROVAL_RECEIVER_CHANGED`), the case is planned again, and the nurse's entry stands. Plays in Rules only mode until the board's runs for it are recorded.
- **S22, one failure, two kinds of system.** The same overtaken transfer fails at the bed manager and at a patient records system. The bed manager only needs the current state, so its case closes with no write. The records system needs an accurate history, so its case escalates with the steps to correct it. S22 plays in Site policy mode; it has no board recordings.
- **S23, bed already occupied (planned, not built yet).** The demo receiver already refuses with `409 bed_occupied`; the evidence, the matcher, the catalogue entry and the board's part are still to come. The receiver refuses a transfer because the bed is taken. Either the occupant's move out failed in another case (recover that first, then resend) or two patients really are allocated one bed (escalate to the bed manager). Telling them apart is the board's job.
- **Ask about this case (in progress).** Built on main: the server routes for questions, the deterministic What-if card (`GET /cases/{id}/whatif`) and the two agent tiers, Explain and the board's question mode ([docs/CONTRACTS.md](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md), section 14). The chat panel on the case page is on a branch and not merged yet, and its example answers are sample data until the live re-record. The design: **Explain** gives a confused user the plain-words answer: what happened, what Shutter did and why. **Ask the board** sends the question to the four agents. When the outcome turns on a site profile setting, the answer ends with a **What-if card**: what this case would have done under the alternative, and a suggested profile change that opens as a draft on the Site profile page for an approver to review. Without a key, each showcase case will open with a recorded example conversation, labelled with its model and date.
- **Production review.** One read-only pass over a production's effective settings, its message purge task and the window's errors, tied to the cases Shutter opened. Each finding names the setting, where its value came from and the safer value. With a key, an agent ranks the findings within their severity tiers and explains each against the case history. Nothing in the production is changed.
- **Evaluation.** How the board decides, from the recorded runs: each member's disposition and confidence per case, where they disagreed and why the plan overruled them, and what each pass cost. It also says plainly what has not been measured.

The catalogue has 21 scenarios: S1 to S13 and S15 to S22 (there is no S14), with S23 planned. Every scenario, step by step, with a checklist of where each part of the contest's task shows: [docs/readme/scenarios.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/scenarios.md).

## How it works

[diagram: failed delivery, case, evidence snapshot, the board (three specialists in parallel, then the coordinator), the gate, release by a person or the site's policy, a dry run, a fresh read and a second gate, one conditional write, verification in the receiver's history]

1. **A failed delivery becomes a case.** The feed fails forward (`FailureTimeout` 0), so the next patient's message is not stuck behind the failure. A hospital's own production can hand its failures to Shutter through the intake, and the case names where it came from.
2. **Evidence, sealed.** The Evidence Collector builds one immutable snapshot: the message, the receiver's state, history and receipt, every other operation for the encounter, the receiver's capabilities and the catalogue match. It is sealed with a digest. Before anything reaches a model, every patient and encounter identifier becomes a per-case token (`MRN-T1`, `ENC-T1`), demographics are dropped and note text becomes a flag.
3. **The board decides.** Three specialists (conformance, encounter, impact) review the evidence in parallel, each from its own view. A coordinator writes one plan and records every specialist it overruled and why.
4. **The gate checks.** Identity, conformance, intent, ordering, state transition, effect, authorisation, concurrency, evidence freshness, the receiver's capabilities and the catalogue. An unknown blocks a write as surely as a failed check. A patient merge or a cancel the receiver cannot take is withheld before any agent runs.
5. **Release.** A person approves the exact plan: the approval is bound to the plan's digest, the evidence, the gate's policy and the receiver's version, and the API refuses a decision on a plan that has changed. In Site policy mode, the site's written profile releases the cases its catalogue settles, and the case records the entry and the policy that released it.
6. **One conditional write, then verification.** A dry run, a fresh read, a second gate, one write at the expected version, then a check of the receiver's committed history. "Acknowledged" and "Verified" are never the same label, and a write whose answer was lost is read again, never resent.

Many failures to one receiver become one **incident**: a chain per encounter in event order, one approval, release one operation at a time at the version the one before verified, and a stop at the first surprise.

## AI Hub inside Shutter

Each agent on the board is a business operation in the production. Its reasoning is a lane in the Visual Trace, and it runs live or replays a recording with no change to the flow.

| AI Hub feature | Where |
| --- | --- |
| `%AI.Agent`: three specialists, a coordinator and a single investigator | [aihub/src/Shutter/Agent](https://github.com/MxSalata/shutter/tree/main/aihub/src/Shutter/Agent) |
| `%AI.Agent` for the production review, with the review rules as its RAG collection and one typed terminal tool, `SubmitReview` | [aihub/src/Shutter/Agent/Review.cls](https://github.com/MxSalata/shutter/blob/main/aihub/src/Shutter/Agent/Review.cls) |
| `%AI.Tool` with typed arguments: the evidence drill-downs, `SubmitFindings`, `SubmitPlan`, `SubmitReview` | [aihub/src/Shutter/Tools](https://github.com/MxSalata/shutter/tree/main/aihub/src/Shutter/Tools), [aihub/src/Shutter/Schema](https://github.com/MxSalata/shutter/tree/main/aihub/src/Shutter/Schema) |
| `%AI.Policy.Authorization` holds every run to its own case; `%AI.Policy.Audit` writes each tool call to the Visual Trace's log | [aihub/src/Shutter/Bridge/Policy](https://github.com/MxSalata/shutter/tree/main/aihub/src/Shutter/Bridge/Policy) |
| RAG on `%AI.RAG.VectorStore.IRIS` with FastEmbed (384 dimensions): the interface contract, the encounter lifecycle, each operation's effects and a recovery playbook per board member | [aihub/src/Shutter/Knowledge/Library.cls](https://github.com/MxSalata/shutter/blob/main/aihub/src/Shutter/Knowledge/Library.cls) |
| The provider key in the IRIS wallet, the provider in the Config Store (`AI.LLM.Shutter`) | [src/Shutter/Setup.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Setup.cls) |
| Agent sessions with prompt caching; tokens and cost recorded per run | [aihub/src/Shutter/Bridge/Runner/AIHub.cls](https://github.com/MxSalata/shutter/blob/main/aihub/src/Shutter/Bridge/Runner/AIHub.cls) |
| `Model`, `ProviderConfig`, `TokenBudget` and `MaxIterations` as settings of each board item | [src/Shutter/Bridge/Operation/Agent.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Bridge/Operation/Agent.cls) |

Not used, on purpose: nested agents (the case workflow gives the board its parallelism and its Visual Trace lanes), a generic SQL tool (the agents see tokens, never rows), and skills or planning (the catalogue and the playbooks carry that knowledge).

## How it is tested

- **On a real IRIS, on every push to `main` that changes code:** the full install on IRIS for Health Community 2026.2, the receiving system's 35 contract tests, Shutter's 155 unit tests (counted as test methods in `tests/unit`), and 21 scenarios end to end through the REST API, one of them through the demo hospital's own production.
- **The approval boundary, attacked over HTTP:** an approval naming another plan or a stale version (409), an operator's approval (403), one approval sent twice (one write), the receiver changed after approval (S20, no write), and a resend of a delivery the receiver already holds (S3, no write).
- **Privacy:** CI fails when a recording carries a name, date of birth, address, phone number, note text or raw identifier.
- **The web app:** 458 component tests and 200 browser tests, with axe-core on 14 screens in 5 appearances.
- **The live agents** run on the AI Hub build, which CI cannot download. The board was recorded live on 25 October 2026 (56 agent runs, 5.38 USD at list prices), and CI replays those recordings on every push.

## Limits, plainly

- Without an API key the agents replay recorded runs. A case with no recording, such as one from your own HL7 file, takes the rules path: the gate alone decides, and a resend still waits for a person.
- The receiving system is a demo bed-management system built for the scenarios. Shutter resends only to a receiver whose API the site profile describes; any other receiver is investigated and escalated, never resent.
- The shipped site profile is a demo profile: it releases the single cases the catalogue settles at tier 2 without asking a person. A real site answers the profile's induction questions first.
- Order communications and results systems are declared but not modelled: a case for one escalates before any model runs.
- The evaluation is one recording per board member and case, with one model. It does not show how often the board reaches the same answer on a repeat run, and the catalogue the agents read was written alongside these scenarios.
- The one injected instruction (S4) stays in IRIS: the agents see only the flag that note text is present and reads like an instruction. That shows they notice the flag, not that they would resist the text.
- Uncertain outcomes (timeouts) never form incidents, so a storm of timeouts convenes one paid board pass per message. A token budget limits each run; nothing limits the total.

## Run it

Shutter runs on IRIS for Health Community with AI Hub, build `2026.3.0AI.154.0`, from InterSystems' Early Access programme. Allow about 25 GB of free disk.

### With the AI Hub image (live agents)

```sh
docker image load -i irishealth-community-2026.3.0AI.154.0-docker.tar.gz
docker images
docker tag docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0 irishealth-community:2026.3.0AI.154.0
git clone https://github.com/MxSalata/shutter.git
cd shutter
cp .env.example .env
docker compose up -d
docker compose ps
curl http://localhost:52773/api/shutter/health
```

If `docker images` shows the image much smaller than 11 GB, run the load again. The health report says `"ok":true` once the production is running. For live agents, set `ANTHROPIC_API_KEY` in `.env` before `docker compose up`; the model is `claude-opus-5-5` (`SHUTTER_MODEL`). A full live pass of every scenario costs about 5 USD on your own key.

### The replay edition (no AI Hub image, no key)

The same production, gate, catalogue, scenarios and recorded board on the public image, with no live agents and no knowledge search:

```sh
git clone https://github.com/MxSalata/shutter.git
cd shutter
cp .env.example .env
sed -i.bak -e 's|^SHUTTER_IMAGE=.*|SHUTTER_IMAGE=containers.intersystems.com/intersystems/irishealth-community:2026.2|' -e 's|^SHUTTER_WITH_AIHUB=.*|SHUTTER_WITH_AIHUB=0|' .env
docker compose up -d --build
```

More about running it (the data volume, the escalation email, the feed's time zone, a site install, merges and cancellations, and the limits not listed above): [docs/readme/running.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/running.md).

To switch between the two editions, run `docker compose down -v` first: it removes the instance's data.

### Open it

| What | Address | Sign in |
| --- | --- | --- |
| The web application | http://localhost:52773/shutter/index.html | `operator` or `approver`, password `shutter` |
| The health report | http://localhost:52773/api/shutter/health | none |
| The Management Portal | http://localhost:52773/csp/sys/UtilHome.csp (namespace `SHUTTER`, production `Shutter.Production`) | `_SYSTEM` / `SYS` |

`operator` views cases, runs scenarios and drafts escalations; `approver` can also approve plans, save the site profile and annotate review findings. The ports are published on `127.0.0.1` only. Installing on a hospital's own IRIS for Health, beside or inside an existing production: [docs/INSTALL.md](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md).

## Why I built this

[placeholder: the owner's own words go here, to be written by the owner]

## About the contest

Shutter is an entry to the InterSystems Programming Contest "AI Agents in Interoperability Workflows" (Open Exchange contest 49): an IRIS Interoperability workflow that uses IRIS AI Hub agents for a decision-making task.

- Contest page: https://openexchange.intersystems.com/contest/49
- Announcement: https://community.intersystems.com/post/intersystems-programming-contest-ai-agents-interoperability-workflows
