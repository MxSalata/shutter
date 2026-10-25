# Shutter: failed HL7 deliveries recovered under supervision, never resent blind

[![CI](https://github.com/MxSalata/shutter/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/MxSalata/shutter/actions/workflows/ci.yml) [![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](https://github.com/MxSalata/shutter/blob/main/LICENSE)

**A failed delivery becomes a case, not a retry.** Shutter is an InterSystems IRIS for Health Interoperability production in which each IRIS AI Hub agent on its board is a business operation: its reasoning is a lane in the Visual Trace, and it runs live or replays a recording with no change to the flow. The agents read a sealed evidence snapshot in which every patient identifier is a per-case token. A deterministic gate checks their plan, the approval is bound to the plan's digest, the evidence, the gate's policy and the receiver's version, and Shutter makes one conditional write and then verifies it in the receiving system's own history.

**The result, in three lines:**

- **S8, the case a gate can't catch:** two systems move one patient in the same minute. Rules alone pass every check and write WARD-B over the bed manager's WARD-C; the board sees that the evidence can't decide which movement is current, and escalates to a person.
- **The board gets 11 of the 11 single cases it is convened for, live and in replay; rules alone get 4 of those 11.** S15 and S16 (a patient merge and a cancel the receiver can't take) are withheld by rule before either. The table: [comparison](https://github.com/MxSalata/shutter/blob/main/docs/readme/comparison.md); how well the agents decide: [Evaluation](https://github.com/MxSalata/shutter/blob/main/docs/readme/evaluation.md).
- **About 0.38 USD a board pass, and 27 to 39 seconds from the board's start to the coordinator's plan** with `claude-opus-5-5` (the three specialists run in parallel). Without an API key the board replays its own recorded live runs, so the demo costs nothing.

**Links:**

- Online demo (recorded runs, no install): ONLINE-DEMO-LINK
- Video: VIDEO-LINK
- Code: https://github.com/MxSalata/shutter
- Run it on your machine: [Run it](https://github.com/MxSalata/shutter#run-it)

## The problem

A hospital's patient administration system (PAS) sends ADT messages (HL7 v2 admission, discharge and transfer events) to every system that needs to know where a patient is.

When a delivery fails, the usual fix is a resend from the Message Viewer: the same message again, whatever has happened since. If a later transfer has already moved the patient, the resend moves them back; if the first attempt did arrive and only the acknowledgement was lost, the event applies twice. A patient merge (ADT^A40, which moves one record's history into another) sent blind can attach a history to the wrong person.

Shutter's feed fails forward instead of holding its queue: the connector's `FailureTimeout` is 0 and the case opens asynchronously, so the next patient's message is not stuck behind a failure. A hospital's own production that hands its failures to Shutter needs the same setting on its outbound operation, as the demo hospital's has.

## What is technically interesting

- **The board as business operations.** Each agent is an item of `Shutter.Bridge.Operation.Agent` with a live runner (AI Hub) and a replay runner (recordings keyed by scenario, case, member and configuration version). The three specialists get their requests asynchronously, so they work in parallel, each in its own Visual Trace lane, before the coordinator writes one plan.
- **Sealed evidence.** The Evidence Collector builds one immutable snapshot (the message, the receiver's state, history and receipt lookup, every other operation for the encounter, the receiver's capabilities, the catalogue match) and seals it with a digest. The agents' evidence tools read that snapshot, never the live systems.
- **Approvals bound to what was approved.** An approval names the plan's digest, the evidence, the gate's policy and the receiver's version; the API refuses a decision on a plan that has changed.
- **One conditional write, then verification.** A dry run first, then a fresh read and a second gate, one write at the expected version, and a check of the receiver's committed history. "Acknowledged" and "Verified" are never the same label.
- **Per-case tokens.** Identifiers become `MRN-T1`, `ENC-T1` before anything reaches a model, and real values return only inside IRIS. `SELECT Shutter_Util.ModelView_Preview('<case id>')` shows what a model would see.
- **An exact index of the feed.** `Shutter.Index.Message` is an `Ens.CustomSearchTable` over the HL7 traffic: the evidence finds every message for an encounter without opening messages by time range or touching the site's search table settings.
- **Incidents with ordered chains.** Many failures to one receiver become one incident: a chain per encounter in event order, one approval, release one operation at a time at the version the one before verified, and a stop at the first surprise.

## AI Hub inside Shutter

| AI Hub feature | Where |
| --- | --- |
| `%AI.Agent`: three specialists, a coordinator and a single investigator | [aihub/src/Shutter/Agent](https://github.com/MxSalata/shutter/tree/main/aihub/src/Shutter/Agent) |
| `%AI.Tool` with typed arguments: the evidence drill-downs, `SubmitFindings` and `SubmitPlan` | [aihub/src/Shutter/Tools](https://github.com/MxSalata/shutter/tree/main/aihub/src/Shutter/Tools), [aihub/src/Shutter/Schema](https://github.com/MxSalata/shutter/tree/main/aihub/src/Shutter/Schema) |
| `%AI.Policy.Authorization` holds every run to its own case; `%AI.Policy.Audit` writes each tool call to the Visual Trace's log | [aihub/src/Shutter/Bridge/Policy](https://github.com/MxSalata/shutter/tree/main/aihub/src/Shutter/Bridge/Policy) |
| RAG: FastEmbed embeddings in `%AI.RAG.VectorStore.IRIS` (384 dimensions, tables `Shutter_Knowledge.*`): the interface contract, the encounter lifecycle, the effects of each operation and the recovery playbooks, one for each board member's perspective | [aihub/src/Shutter/Knowledge/Library.cls](https://github.com/MxSalata/shutter/blob/main/aihub/src/Shutter/Knowledge/Library.cls) |
| The provider key in the IRIS wallet and the provider in the Config Store (`AI.LLM.Shutter`) | [src/Shutter/Setup.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Setup.cls) |
| Agent sessions with prompt caching; tokens and cost recorded per run | [aihub/src/Shutter/Bridge/Runner/AIHub.cls](https://github.com/MxSalata/shutter/blob/main/aihub/src/Shutter/Bridge/Runner/AIHub.cls) |
| `Model`, `ProviderConfig`, `TokenBudget` and `MaxIterations` as settings of each board item | [src/Shutter/Bridge/Operation/Agent.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Bridge/Operation/Agent.cls) |

Not used, on purpose: nested agents (the case workflow gives the board its parallelism and its Visual Trace lanes), a generic SQL tool (the agents see tokens, never rows), and skills or planning (the scenario catalogue and the recovery playbooks carry that knowledge).

## For judges

### Five minutes with Shutter

Sign in to your own instance as `approver` / `shutter`, or to the online demo with **Try the demo**, and open **Scenarios**. The online demo shows the recorded outcomes and holds S2's case at its approval, so **Approve** in step 1 works there too (it replays the recorded outcome); the approvals in steps 3 and 5 need your own instance.

1. **S2, board mode.** A transfer never arrived. Three specialists review the evidence, the coordinator proposes a resend, the gate passes it and the receiver's dry run says it would apply. **Approve**: one conditional write, then "Verified" from the receiver's history.
2. **S1, board mode, then Rules only.** A later transfer has overtaken the failed one. The board closes the case as superseded and writes nothing; rules alone propose a resend, and the gate blocks it.
3. **S8, Rules only, then board mode.** Rules alone pass every check; **Approve** the plan and the resend overwrites the bed manager's WARD-C with WARD-B. In board mode the board escalates. This is the case the gate alone can't catch.
4. **S15, any mode.** A patient merge: the gate blocks every plan (`MERGE_WITHHELD`), the board is not convened, **Escalate** drafts the email to the PAS team, and **Mark as handled by the team** closes the case with what they did.
5. **S11, Site policy mode.** The receiver goes down twice and eight deliveries fail: one incident, a chain per encounter, the single chains settled by the site's policy, the ordered chain waiting for one approval.
6. **S19, Site policy mode.** The same transfer fails inside the demo hospital's own production (namespace `HOSPITAL`), which Shutter does not own. Its forwarder hands the failure to Shutter, the case names where it came from, and the resend goes through Shutter's connector.

In the Management Portal, the Visual Trace of a case shows each step as a message. Every scenario, step by step, and a checklist of what to look for: [docs/readme/scenarios.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/scenarios.md).

### Bonuses (a draft, scored again when the contest's list is published)

| Bonus | Where to see it | Status |
| --- | --- | --- |
| Docker | `docker compose up` ([Run it](https://github.com/MxSalata/shutter#run-it)) | Ready |
| LLM AI | The board of AI Hub agents with `claude-opus-5-5` through Anthropic | Ready |
| Vector search | The knowledge bases on `%AI.RAG.VectorStore.IRIS` (the AI Hub build) | Ready |
| IPM | The modules `iris-shutter` and `iris-shutter-aihub` load with `zpm "load"` today | Registry install after publication |
| Online demo | ONLINE-DEMO-LINK | After publication |

### How it is tested

- CI runs on every push to `main` that changes code (a push of only the README or `docs/` runs nothing). On a real IRIS for Health Community 2026.2 it runs the full install, the receiving system's 23 contract tests and Shutter's 61 unit tests (the trigger table, the gate, the matcher's conditions, supersession, the model view and the case's writes), and 20 scenarios end to end through the REST API, one of them through the demo hospital's own production.
- CI also checks the recordings and the demo's data for privacy, and runs axe-core on 14 screens (the sign-in page and 13 of the app) in 5 appearances of the web app's demo build. Third-party actions are pinned by commit SHA.
- The live edition (the aihub module) needs the AI Hub build, which CI can't download, so it is checked by hand on that build, and its recorded runs are what CI replays.
- The live path itself (AI Hub's agent loop, the tools, the policies, the Visual Trace) also runs on that build with no model, against an API mimic: a test fixture in [tests/mock](https://github.com/MxSalata/shutter/tree/main/tests/mock), in neither module nor the image, whose runs are labelled model `mock`, cost nothing and are never recorded.

### Limits, plainly

- Without an API key the agents replay recorded runs: the live board's own runs with `claude-opus-5-5` on 19 October 2026, one per board member and case (`fixtures/records`). A case with no recording, such as one from an HL7 file of your own, takes the rules path: the gate alone decides, and a resend still waits for a person.
- The receiving system is a demo bed-management system (`Downstream.*`) built for the scenarios. Shutter resends only to a receiver whose API the site profile describes; a receiver without one is investigated and escalated, never resent.
- The shipped site profile is a demo profile: it releases the single cases the catalogue settles at tier 2 without asking a person. A site answers the profile's induction questions first.
- A06 and A07 (a change of patient class) are delivered as an update with no location, although an A06 can carry a new location in PV1-3.
- Uncertain outcomes (timeouts) never form incidents, and each board item runs one request at a time, so a storm of timeouts convenes one paid board pass per message, one after another. A token budget limits each run; nothing limits the total.
- A case left in a working state by a restart in the middle of a scenario has no route to abandon it yet: "Mark as handled" accepts only escalated, blocked or failed cases.

## Run it

Shutter runs on InterSystems IRIS for Health Community with AI Hub, build `2026.3.0AI.154.0`, from InterSystems' Early Access programme. That image is not on a public registry: you load the file once and tag it, and `docker compose up` does the rest.

### With the AI Hub image (the main route, live agents)

1. From the Early Access portal, download the IRIS for Health Community image: `irishealth-community-2026.3.0AI.154.0-docker.tar.gz` for x64. ARM64 machines (Apple silicon) need the `irishealth_arm64-community` file of the same build; Shutter has not been tried on ARM64.
2. Load it, check the name it loaded as, tag it with the short name the build expects, and start Shutter:

```sh
docker image load -i irishealth-community-2026.3.0AI.154.0-docker.tar.gz
docker images
docker tag docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0 irishealth-community:2026.3.0AI.154.0
git clone https://github.com/MxSalata/shutter.git
cd shutter
cp .env.example .env
docker compose up -d
```

The x64 file loads as `docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2026.3.0AI.154.0`; if `docker images` shows another name, tag that one. No Dockerfile edit is needed: its base image comes from the build argument `IRIS_IMAGE`, which defaults to `irishealth-community:2026.3.0AI.154.0`.

3. The first `up` builds the image, which takes a few minutes. Check it:

```sh
docker compose ps
curl http://localhost:52773/api/shutter/health
```

The health report says `"ok":true` once the production is running.

**The model.** The provider is Anthropic and the model `claude-opus-5-5` (`SHUTTER_MODEL` in `.env`). For live agents, set `ANTHROPIC_API_KEY` in `.env` before `docker compose up`; without a key the agents replay recorded runs and nothing is charged. The recording of every scenario on 19 October 2026 took 56 agent runs and cost 5.31 USD, so a full live pass on your own key costs about 5 USD.

### The replay edition (no AI Hub image, no key)

Without the Early Access file, build the replay edition on InterSystems' public IRIS for Health Community 2026.2 image. It has the same production, gate, catalogue, scenarios and recorded board, but no live agents and no knowledge search. It is built on your machine and is never pushed to a registry:

```sh
git clone https://github.com/MxSalata/shutter.git
cd shutter
cp .env.example .env
SHUTTER_IMAGE=containers.intersystems.com/intersystems/irishealth-community:2026.2 SHUTTER_WITH_AIHUB=0 docker compose up -d --build
```

It is the image CI builds and plays S2 and S19 on.

### Open it

| What | Address | Sign in |
| --- | --- | --- |
| The web application | http://localhost:52773/shutter/index.html (the bare `/shutter/` answers 404) | `operator` or `approver`, password `shutter` |
| The health report | http://localhost:52773/api/shutter/health | none for the summary |
| The Management Portal | http://localhost:52773/csp/sys/UtilHome.csp (namespace `SHUTTER`, production `Shutter.Production`) | `_SYSTEM` / `SYS` |

| User | Can |
| --- | --- |
| `operator` | View cases and incidents, run scenarios, reinvestigate a case, draft and send escalations, mark a case handled by the team (unless the site profile keeps the two-person rule), and start a production review |
| `approver` | Everything `operator` can, and approve or reject plans and incident releases, read the message traces and the Workflow inbox, save the site profile, change the agent library, mark a case handled where the site profile needs an approver for it, and mark a review's finding intended |

Neither user starts, stops or purges the production. The ports are published on `127.0.0.1` only, because the demo's passwords are well known; from another machine, use an SSH tunnel (`ssh -L 52773:localhost:52773 <the Docker host>`). `SHUTTER_WEB_PORT` and `SHUTTER_SUPERSERVER_PORT` in `.env` change the ports.

To feed a message of your own, copy an HL7 file (one message, `.hl7`) into the production's inbound folder in the data volume: `docker cp my-message.hl7 shutter:/usr/irissys/mgr/shutter/in/`. Without a key, a failure it causes takes the rules path (see [Limits, plainly](https://github.com/MxSalata/shutter#limits-plainly)).

## More about running it

The first `up` creates the `SHUTTER` namespace, installs the InterSystems Package Manager (from the pinned installer kept in `vendor/ipm`, so the build does not depend on the package registry) and loads the `iris-shutter` module (the production, the case store, the gate, the downstream system, the web application and the recorded agent runs) and, on the AI Hub image, the `iris-shutter-aihub` module (the live agents and their knowledge bases). A step that fails stops the build with `BUILD FAILED` and the reason. The production starts with the container, and as it starts it clears two known startup alerts (the build host's "failover" message and the preview build's own startup error), so Docker's health check reflects the instance's real state; any other alert stays.

To watch a case unfold, run a scenario from the web application's Scenarios page (S1 to S13 and S15 to S21; S11 and S12 are the outage scenarios that open an incident, S19 fails in the demo hospital's own production, in S20 a nurse moves the patient by hand in the downstream system while the resend waits for approval, and S21's transfer is timed in the hour that happens twice when the clocks go back): each one feeds synthetic ADT messages into the production, makes one delivery fail in a particular way, and opens a case. With an `ANTHROPIC_API_KEY` in `.env`, the production writes the provider configuration from it when it starts, and the agent items, set to `auto`, then run live (`SHUTTER_AGENT_MODE` forces `live`, `record` or `replay`). Measured on 19 October 2026 with `claude-opus-5-5`: one board pass (three specialists and the coordinator) uses about 72,000 input and 4,200 output tokens, roughly 0.38 USD at list prices, and takes 27 to 39 seconds from the board's start to the coordinator's plan, because the three specialists run in parallel; the Settings page shows the figures per run, whose durations add up to more.

What you make stays: the cases, approvals, incidents, the site profile and Shutter's record of the provider configuration live in a data database inside the `shutter-mgr` volume (the image keeps only the code), so `docker compose down` and `up` keep them, a rebuilt image brings new code to the same data (a build that changes the gate's policy version, as this one does with `2026-10-25.1`, voids approvals given before it and not yet dispatched: such a case blocks at dispatch with `APPROVAL_POLICY_CHANGED`; reinvestigate it), and `docker compose down -v` starts afresh. A volume made by a build from before 18 October 2026 has no data database, and one from before 19 October 2026 keeps the downstream system's records under its earlier name, which newer builds don't read, and one made by an earlier build without the demo hospital has no `HOSPITAL` namespace: remove such a volume once (`docker compose down -v`) before the first `up` of a newer build. The compose file gives the container two minutes to stop (`stop_grace_period`), so IRIS writes its journal and write image out cleanly; a container killed mid-write recovers from the journal at the next start, which is what the "abnormal shutdown" alert in the console log then says. When the production starts it re-reads the knowledge files that changed (block reasons, catalogue, site profile seed, recordings, and the documents the agents search), so a rebuilt image's knowledge reaches the kept data; a site profile saved from the app is never overwritten by the seed. Installing again over an instance that already has Shutter (a rebuilt image on the kept volume, or `zpm "load"` again) brings the roles to their current definition and the demo users `operator`, `approver`, `forwarder` and `downstream-client` back to the demo's role, password and enabled state, and rewrites the `DownstreamAPI` credential; a non-demo install only adds roles to users that exist. Every install also removes what the downstream system was called before 19 October 2026: its web application, resource, roles, user, credential and classes, when they are there.

**What reaches the model.** Only what is needed leaves IRIS: before the evidence or a tool result goes to an agent, every patient and encounter identifier is replaced by a per-case token (`MRN-T1`, `ENC-T1` and the like, mapped back only inside IRIS), the demographics (names, date of birth, sex, address) are dropped, and each OBX or NTE note becomes a flag saying that free text is present and whether it reads like an instruction; the text itself goes only when the site profile's `model_content.free_text` is true. `SELECT Shutter_Util.ModelView_Preview('C-000012')` shows what the model would see of a case, and `tests/privacy_check.py` fails when a recording carries a name, a date of birth or a raw identifier.

**Escalation by email.** When Shutter cannot recover a case (blocked, escalated or failed), the case page drafts an email for the team that owns the receiving system, from the stored case and without a model: the hospital number, the NHS number and the date of birth, the event and its operation key, what failed, why Shutter stopped, what the receiver holds, the encounter's timeline and what Shutter sent; no name, address or note text. A person edits it, picks the team (the site profile's `teams`) and sends it; the send is bound to the digest of the text they read. The `Escalation Mail` operation sends through the site's mail server when its `SMTPServer`, port, TLS and credentials are set in the production (first-time configuration; the NHS relay at most trusts), and otherwise writes an `.eml` file under `<mgr>/shutter/out/mail`, so the demo and CI need no mail server. Every recipient must be one bare address inside the site's allowed mail domains (`mail.allowed_domains`; with none set no email can go; the shipped profile allows `example.nhs.uk`, its teams' domain), a subject with a line break is refused, and nothing is sent about a case once it is closed or reopened. Ninety days after the case closes (`SHUTTER_ESCALATION_DAYS`; `0` keeps them) the retention task removes the email's text and the `.eml` file; the escalation stays on record with its digest, recipients and who sent it.

**The feed's time zone.** HL7 timestamps that carry no offset are read in the site profile's `feed.time_zone`: `Europe/London` (the shipped profile, with British Summer Time, so 09:20 on 15 October is 08:20Z), `UTC` or a fixed offset such as `+01:00`. The zone changes every operation key, so set it before the first case; the matcher's `event_time` condition and the gate then block a resend whose event time precedes its admission, lies in the future, is far from when it was recorded, or sits within an hour of a clock change. Such a time is not simply bad data, so a person decides (E13): one more than a day before it was recorded is usually a retrospective entry (paper notes typed in later), one in the future or before the admission a clock fault or a mistyped time, and one without an offset near a clock change may be an hour that night holds twice (or never), so only the source can say when it was.

**A site install (no demo).** The image is the demo. On a hospital's own IRIS for Health, create the `SHUTTER` namespace (`Installer.cls`, or `SELECT Shutter.Setup_CreateNamespace('SHUTTER')`) and load the module with the demo switched off: `zpm "load /path/to/shutter -Ddemo=0"`. That install creates the resources and roles, the web applications `/api/shutter` and `/shutter`, the Workflow role "Shutter Approvers" and the retention task, and starts `Shutter.Production` with its demo items (`ADT In`, `ADT to Downstream`, `Downstream Out`, `Scenario Player`) switched off; it makes no demo users and nothing of the demo receiver, imports no recorded runs, and creates no message purge task unless `SHUTTER_MESSAGE_PURGE=1` (the purge keeps `SHUTTER_MESSAGE_DAYS` days, 90 by default; the installer reads both when it runs, the image build from `.env` through the compose file's build arguments). The hospital's own productions then hand Shutter their failed deliveries: each adds `Shutter.Intake.Forwarder`, which posts a failed message with its context to `POST /api/shutter/intake` as a user holding `Shutter_Forwarder`, and Shutter opens the case with the source recorded. The full guide for an integration team, both shapes, is [docs/INSTALL.md](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md).

**Shutter watching a production it does not own.** The image also creates the `HOSPITAL` namespace, the demo hospital whose production is not Shutter's: `PAS In` on `<mgr>/shutter/hospital/in`, `PAS to Downstream`, `Downstream Out` to the demo bed-management system, and `Shutter Forwarder`. It starts with the container; a delivery that fails there appears in Shutter as a case that names its source (namespace, production, route and the message's header), with Shutter's own copy of the message in its evidence, and a resend goes through Shutter's connector. Its messages and settings live in a data database of their own in the same volume. To see it, run S19 in Site policy mode, then open the Management Portal in the namespace `HOSPITAL`, production `Hospital.Production`: the transfer's Visual Trace shows `PAS In`, `PAS to Downstream`, the failed call of `Downstream Out` and the `Shutter Forwarder`'s post to Shutter's intake.

**A production review.** One read-only pass over a production Shutter runs or watches (its own `Shutter.Production`, the demo hospital's `Hospital.Production`, any that has sent it a case): the effective value of every setting that decides whether a failure fails forward, is seen and stays in order (`FailureTimeout`, `RetryInterval`, `ReplyCodeActions`, `Framing`, `AlertOnError` and `AlertGroups`, the queue alerts, `InactivityTimeout`, `ArchiveIO`, `PoolSize`, `Enabled`), resolved through the item, the system default settings and the class default and saying which answered; the message purge task; and the window's suspended and failed messages, event log errors grouped by signature and rule errors, each tied to the cases Shutter opened for the item. Twenty-three checks, each with a severity and, kept apart, an evidence confidence (confirmed, consistent, indicative), in a deterministic order (severity tier, unique cases, recency); with an API key the review agent ranks them within their tiers and explains each against the case history, and without one the deterministic order stands and the answer says so. An approver can mark a finding intended, bound to a fingerprint of the exact configuration, so it stays quiet until the value moves. The review never changes a production: a person applies any change in the Management Portal. To try it, as `operator`: `GET /api/shutter/production-reviews/targets` lists the productions a review may be asked for, and `POST /api/shutter/production-reviews` with `{"production": "Shutter.Production"}` (or `{"namespace": "HOSPITAL", "production": "Hospital.Production"}`, the hospital's production read in its own namespace), with `X-Requested-With: Shutter` and an `Idempotency-Key` as on every POST, starts one and answers its id; `GET /api/shutter/production-reviews/{id}` shows the findings once its `state` is `done`, and `POST /api/shutter/production-reviews/{id}/annotations` as `approver` marks one intended. In the Management Portal the run is the `Case Review` item's message in the Visual Trace.

**Inside a production you already run.** Shutter's items can live in an existing production instead of `Shutter.Production`: load the core classes into that namespace and run `SELECT Shutter.Setup_InstallInto('Your.Production', '/path/to/shutter/')` (or `zpm "load /path/to/shutter -Ddemo=0 -Dproduction=Your.Production"`). It adds the case workflow, the incident workflow, the evidence collector, the gate, the verifier, the escalation mail, the Workflow operation, the API service, the index, the intake and the agent operations to that production as `Shutter.Production` defines them, writes their default settings for it and updates it in place when it is running; it never stops it, creates no demo users or receiver and no message purge. The health report then names that production.

**The HL7 schema and the triggers.** Each HL7 service parses with its own schema category, as IRIS does (the demo's `ADT In` uses 2.5.1; a site's route sets 2.3.1, 2.4 or its own custom category, or one category per message type), and Shutter reads the fields it needs by position, which are the same in 2.3.1, 2.4 and 2.5.1: MSH, EVN, PID-3, PV1-2, -3, -19 and -44, MRG for a merge. The evidence notes when the message's own version (MSH-12) differs from the route's category; it is a note for the conformance review, never a failure. The feed maps these ADT triggers: A01, A02, A03 and A08 are delivered to the downstream system as the admission, transfer, discharge and update they are, A06 and A07 (a change of patient class) as updates that carry no location (an A06's new location in PV1-3 is not passed on), and an A04 registration as an admission only when it names an inpatient with a bed; registrations without a bed, pre-admissions (A05) and person events (A28, A31) are recorded in the exact index, where the case page's timeline shows them between the movements, and are not delivered. Any other trigger opens a case that says the message could not be mapped, and that includes common ones: A15 and A16 (a pending transfer or discharge), A17 (a swap of two patients' beds), A21 and A22 (leave of absence and the return from it), A47 (a change of patient identifier) and A54 (a change of attending doctor).

**Merges and cancellations.** By default Shutter never touches an ADT^A40 merge: the message is withheld, a case opens with the surviving and prior identifiers, the gate refuses any resend (`MERGE_WITHHELD`), and the escalation draft goes to the team the site profile names for the sending application (`teams[].sources`), the PAS team as a rule. A site whose risk tolerance allows it sets `merges: allowed` in the profile and `merges: true` on a receiver that takes merges. Cancellations (A11, A12, A13) are delivered only to a receiver whose entry says `cancels: true`; the demo's downstream system cannot reverse an event, so a cancellation is withheld and escalated (`CANCEL_UNSUPPORTED`). Once a team has corrected the receiver by hand, `POST /cases/{id}/close` with a reason (the case page's "Mark as handled by the team") closes the case with the reason and who closed it on its record. An operator closes it, since the escalation is the sign-off; a site that keeps the two-person rule sets `approvers.close_needs_approver` in the site profile, and then only an approver does. The case page's evidence shows the version note as `message_version`, `route_category`, `route_standard` and `version_agrees`, and the timeline names registrations, pre-admissions and person events by those words. A withheld case never convenes the board, whatever the mode.

Other settings are in `.env.example`: the published ports, the agents' mode and model, and the installer's demo password and message purge.

## About the contest

Shutter is an entry to the InterSystems Programming Contest "AI Agents in Interoperability Workflows" (Open Exchange contest 49), whose task is an InterSystems IRIS Interoperability workflow that uses an IRIS AI Hub agent to handle a decision-making task.

- Contest page: https://openexchange.intersystems.com/contest/49
- Announcement: https://community.intersystems.com/post/intersystems-programming-contest-ai-agents-interoperability-workflows
