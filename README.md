# Shutter: AI Hub agents for failed HL7 deliveries

**When a hospital's HL7 delivery fails, the usual fix is Resend, and if the patient has moved since, that resend moves them back. Shutter's IRIS AI Hub agents decide how to put the failure right; a deterministic gate decides whether anything is written.**

[![CI](https://github.com/MxSalata/shutter/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/MxSalata/shutter/actions/workflows/ci.yml) [![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](https://github.com/MxSalata/shutter/blob/main/LICENSE)

**Jump to:** [Try it](https://github.com/MxSalata/shutter#try-it) · [What to look at](https://github.com/MxSalata/shutter#what-to-look-at) · [How it works](https://github.com/MxSalata/shutter#how-it-works) · [AI Hub](https://github.com/MxSalata/shutter#ai-hub-inside-shutter) · [Bonuses](https://github.com/MxSalata/shutter#technology-bonuses) · [Testing](https://github.com/MxSalata/shutter#how-it-is-tested) · [Limits](https://github.com/MxSalata/shutter#limits-plainly) · [Run details](https://github.com/MxSalata/shutter#run-details) · [Troubleshooting](https://github.com/MxSalata/shutter#troubleshooting)

**Trial** [link at submission] | **Online demo** [link at submission] | **Video** [link at submission] | **Articles** [link at submission] | **Open Exchange** [link at submission]

*Why I built it:* real testing of an integration only happens in production, where a receiver behaves in a way nobody foresaw, a message arrives out of order, or someone fixes something by hand. Shutter is a safety net for those cases, made for a clinical setting, where a wrong write has a patient on the other end.

Instead of a **Resend** in the Message Viewer, Shutter makes each failed delivery a case. The board, four AI Hub agents (three specialists and a coordinator), reads the case's sealed evidence, one snapshot of the message and the receiver's state fixed by its digest, and proposes a plan. The gate, a set of deterministic checks, decides whether the plan may write; a person or the site's written policy releases it; and one conditional write follows, proven from the receiver's history. The AI board proposes; the gate disposes.

**S8 shows why the agents are there.** Two systems move one patient in the same minute. Rules alone pass every check and write WARD-B over the bed manager's WARD-C; the board sees the evidence cannot say which move is current and escalates. On Shutter's own scenarios, of the 11 single cases the board is convened for, it gets all 11 right; rules alone get 4 ([comparison](https://github.com/MxSalata/shutter/blob/main/docs/readme/comparison.md); [what that does and does not show](https://github.com/MxSalata/shutter/blob/main/docs/readme/evaluation.md)).

![S8 in plain terms: the bed manager has the patient in Ward C; rules alone move them back to Ward B, the board leaves them in Ward C and asks a person](https://raw.githubusercontent.com/MxSalata/shutter/main/docs/readme/images/s8-plain.png)

**What can happen to a failed delivery:**

| Shutter decides | For example | What is written |
| --- | --- | --- |
| Resend | S2: a transfer that never arrived | One conditional write once a person or the site's written policy releases it, verified from the receiver's history |
| Superseded | S1: a later transfer has already moved the patient | Nothing; the closure is checked against the receiver's history |
| Reconcile | S3: the receiver holds the message; only its acknowledgement was lost | Nothing; the receipt is checked |
| Escalate | S8: two moves in one minute | Nothing; a person decides |
| Withheld | S15: a patient merge, for the PAS team | Nothing; no agent runs |
| An incident | S11: an outage, eight failures to one receiver | Each chain in event order, released by the site's policy or an approval, each item verified, stopping at the first surprise |

![S2's case in the web app, waiting for approval: the failed delivery, the stages from evidence to rehearsal done, and what needs a person now: approve or reject plan v1](https://raw.githubusercontent.com/MxSalata/shutter/main/docs/readme/images/case-s2-approval.png)

## Where the agents sit

The three specialists (conformance, encounter and impact) and the coordinator are business operations in the production. The case workflow calls the specialists in parallel, then the coordinator, who writes the plan. A pass takes 24 to 47 seconds and costs 0.34 to 0.50 USD, most passes 0.34 to 0.44: four agents read the evidence through typed tools on a frontier model, `claude-opus-5-5`, a setting of each board item. With `ANTHROPIC_API_KEY` in `.env` they run live; without a key they replay recorded live runs at no cost. The agents hold no write tool: their tools read the sealed evidence and submit a finding, a plan or an answer, and only the gate's checked, released plan is ever written. Its cases, evidence and plans are also read-only MCP tools through IRIS's own MCP gateway, identifiers tokenised, each tool call audited under the caller's IRIS user ([CONTRACTS.md](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#15-the-publisher-v135)).

| The contest's task | In Shutter |
| --- | --- |
| An AI Hub agent handles a decision | Each board member is a `%AI.Agent` with typed tools; the coordinator's `SubmitPlan` is the decision ([src/Shutter/Agent](https://github.com/MxSalata/shutter/tree/main/src/Shutter/Agent)) |
| As one step in a production | `Shutter.Process.CaseWorkflow` in `Shutter.Production`; in S19 the failure comes from a hospital's own production |
| At run time | The board is convened when a delivery fails, on that failure's sealed evidence |
| A person in the loop | An `EnsLib.Workflow` task for the role "Shutter Approvers", bound to the plan's digest |
| Seeing what the agent did | Each board member's lane in the Visual Trace, its `AgentResponse` (model, tokens, time, tool calls) and the [walk-through](https://github.com/MxSalata/shutter#tracing-ai-agents-with-interoperability-dpi-i-689) |

![The Visual Trace of S8 in board mode, replaying its recorded run: the case workflow, the evidence, each board member in its own lane, then the gate](https://raw.githubusercontent.com/MxSalata/shutter/main/web/public/s8-visual-trace.png)

## Try it

**Fastest, with no key and no cost:** the trial in the browser (the quick tour: 9 steps, about 4 minutes), then the replay edition on your machine, `./install.sh --replay`, built and healthy in 2 min 4 s from a fresh copy once the 6 GB public image is pulled. With the AI Hub file, a fresh clone was healthy in 3 min 21 s on build 109 ([receipt](https://github.com/MxSalata/shutter/blob/main/docs/readme/receipt-109.md)). Both on a 12-thread VM.

**In the browser, nothing to install:** the trial [link at submission] opens signed in on the demo hospital's recorded runs. Every action replays the recording, and nothing leaves the browser. Two tours start from an address: the quick tour [link at submission, `?trial=tour`], 9 steps in about 4 minutes, and the engineers' tour [link at submission, `?trial=engineer`], 6 steps in about 3 minutes with Detail on Technical.

**Online demo:** [link at submission]: my fictional hospital, live, with made-up patients. A new failure arrives every 7 minutes and Shutter recovers it under the site's written policy. Sign in as `demo` / `shutter`. The Management Portal's Visual Trace, read only: `demo-trace` / `Shutter-Demo-IRIS-Portal`. The portal's address (`/csp/`) may first ask for your email address and send a one-time code to it; then that sign-in. The demo runs on AI Hub build `2026.3.0AI.154.0`; on your machine, use `2027.1.0AI.109.0` (below). The board runs live for the judges' account, within a model budget of 15 USD a day; everyone can see its recorded runs in the trial.

**On your machine:** Docker, then one command. `install.sh` checks Docker, Compose, memory, disk, the port and the image first and changes nothing until every check passes; then it builds, starts and waits until Shutter is healthy. On Windows, run it in Git Bash or a WSL 2 shell; from PowerShell, use the [Run details](https://github.com/MxSalata/shutter#run-details) commands.

```sh
git clone https://github.com/MxSalata/shutter.git && cd shutter

# The AI Hub edition (live agents), with the image file from InterSystems' Early Access portal:
./install.sh --image-file irishealth-community-2027.1.0AI.109.0-docker.tar.gz

# Or the replay edition: the public IRIS for Health image, no Early Access file, no key:
./install.sh --replay
```

It ends with what to open:

```text
Shutter is ready after 10 s:
  the web app:   http://localhost:52773/shutter/index.html  (approver / shutter, or operator / shutter)
  first steps:   Scenarios, run S2 in Board mode, then approve its case (the README's "On your machine or in the trial, first")
  the portal:    http://localhost:52773/csp/sys/UtilHome.csp  (_SYSTEM / SYS, namespace SHUTTER)
```

- **Builds:** Shutter is verified on the AI Hub Community builds `2027.1.0AI.109.0`, the one the [Early Access portal](https://evaluation.intersystems.com/Eval/early-access/AIHub) offers since 2 November 2026, and `2026.3.0AI.154.0`, the contest's first ([receipt on 109](https://github.com/MxSalata/shutter/blob/main/docs/readme/receipt-109.md), [receipt on 154](https://github.com/MxSalata/shutter/blob/main/docs/readme/receipt.md)). `install.sh` loads and tags either, from the file or already loaded; judges, please use 109.
- For live agents, set `ANTHROPIC_API_KEY` in `.env`; without a key the board replays its recorded live runs. The live board uses Anthropic's API only, so with another provider's key it replays too. The case page's board panel marks each run Live or Replay, and so does each `AgentResponse` in the Visual Trace (`Mode`). The replay edition is the same without live agents or knowledge search.
- The first build takes 2 to 15 minutes. Allow Docker at least 5 GB of memory and about 25 GB of free disk. Then open http://localhost:52773/shutter/index.html.
- **Sign-ins on your machine:** the web app as `approver` / `shutter` (approves) or `operator` / `shutter`; the Management Portal as `_SYSTEM` / `SYS`, namespace `SHUTTER`.

### On the online demo, first

1. Press **Break the feed** on the hospital's banner. Its bed manager goes down for a minute and eight movements for four new patients fail; a strip follows Shutter grouping them into one incident and, once the bed manager is back, releasing them in order. In the demo's rehearsal on 3 November 2026 that came to **one incident waiting for one approval, and no model call**; on the build before, each of the eight cases convened a board of its own. Unlike a Resend of each message, each item goes in event order at the version the previous one's verified receipt reports, stopping at the first surprise. Step 4 shows the agents decide.
2. Open a case that **waits for approval** and **Approve** it: one conditional write, then "Verified" from the receiver's history.
3. On any case, **In IRIS: Message trace** opens its session in the Visual Trace (`demo-trace`).
4. **See the agents decide.** The hospital's own stories are settled by its policy, with no board. With the judges' account, **Convene the board** on an escalated or blocked case: the board investigates it again, live, on fresh evidence. Without it, **See the board decide**, under the banner, opens S8's recorded board in the trial.

### On your machine or in the trial, first

1. In **Scenarios**, run **S2** in **Board** mode. About 20 seconds later (a minute live) its case waits for approval. **Approve** it: one conditional write, then "Verified".
2. Run **S8** in **Rules only** and approve (in the trial its recorded case is already approved and written): WARD-B overwrites the bed manager's WARD-C. In **Board** it escalates, writing nothing. The case page sets the two side by side.

## What to look at

![The Scenarios page: six steps and three scenarios to try first](https://raw.githubusercontent.com/MxSalata/shutter/main/docs/readme/images/scenarios-start.png)

- **S2, a transfer that never arrived.** The gate passes the board's resend, the receiver's dry run says it would apply, and the approval waits as a Workflow task. "Acknowledged" is never "Verified". The web app's Approve completes that same `EnsLib.Workflow` task as the signed-in approver; from the IRIS Workflow inbox, paste the plan's digest into the task's `PlanDigest` field.

![S2's approval waits as a task in the IRIS Workflow inbox, for the role Shutter Approvers](https://raw.githubusercontent.com/MxSalata/shutter/main/docs/readme/images/workflow-inbox-s2.png)

- **S8, the case a gate cannot catch.** The plan records the conformance specialist's dissent and why it was overruled. The case page sets rules alone and the board side by side:

![S8 played twice: rules alone overwrite WARD-C; the board escalates and writes nothing](https://raw.githubusercontent.com/MxSalata/shutter/main/docs/readme/images/s8-rules-and-board.png)

- **S20, a nurse moves the patient by hand** while S2's resend awaits approval. The approval is bound to the receiver's version, so nothing is sent (`APPROVAL_RECEIVER_CHANGED`) and her entry stands: the binding alone stops it, so S20 plays in Rules only mode.
- **Beside the cases:** Ask about this case (agents that cannot write), a read-only review of a production, precedents, each agent's timeline and the evaluation.

![Incident I-000001 from S11: eight failed deliveries to Downstream Out, six chains, five released by the site's policy and one by the board, all verified at the receiver in 1 min 42 s](https://raw.githubusercontent.com/MxSalata/shutter/main/docs/readme/images/incident-s11.png)

All 26 scenarios, step by step, and where each part of the task shows: [docs/readme/scenarios.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/scenarios.md).

## How it works

![A case's life, from the failed delivery to verification](https://raw.githubusercontent.com/MxSalata/shutter/main/docs/readme/images/case-lifecycle.png)

1. **A failed delivery becomes a case.** The feed fails forward (`FailureTimeout` 0), so no later message is stuck behind it. A hospital's own production hands its failures to Shutter through its `Shutter Forwarder`, or through its alerts with `Shutter.Intake.AlertProcess` as its `Ens.Alert` item, which still passes every alert to its own consumer first ([to put Shutter behind your own production](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md)).
2. **Evidence, sealed.** One immutable snapshot with a digest: the message, the receiver's state, history, receipt and capabilities, the encounter's other operations and the catalogue match. Before a model sees it, identifiers become per-case tokens (`MRN-T1`), demographics are dropped and note text becomes a flag.
3. **The board decides.** Each specialist reviews the evidence from its own view; the coordinator's one plan records every specialist it overruled and why.
4. **The gate checks** identity, conformance, intent, ordering, state transition, effect, authorisation, rehearsal, concurrency, evidence freshness, the receiver's capabilities and the catalogue. An unknown blocks a write as surely as a failed check. Patient merges, and cancels the receiver cannot take, are withheld before any agent runs.
5. **Release.** A person approves the exact plan, bound to its digest, the evidence, the gate's policy and the receiver's version. In Site policy mode, the site's written profile releases the cases its catalogue settles instead.
6. **One conditional write, then verification.** A dry run, a fresh read, a second gate, one write at the expected version, then a check of the receiver's committed history. A write whose answer was lost is read again, not resent.

The case and incident workflows are written in ObjectScript rather than BPL, by choice: they wait on a board answering in parallel, timeouts, re-plans and approvals that expire, they are unit-tested and versioned with the gate, and every step is still a production message, so the Visual Trace above shows each case step by step.

**The two productions, item by item.** The demo hospital's own production (namespace `HOSPITAL`) hands its failed deliveries to Shutter's (namespace `SHUTTER`); Shutter's feed, recovery, board and verification are all production items.

![Hospital.Production and Shutter.Production: the hospital's feed and forwarder, Shutter's ways in, recovery items, the board of AI Hub agents and the feed to the demo receivers](https://raw.githubusercontent.com/MxSalata/shutter/main/docs/readme/images/production.png)

## AI Hub inside Shutter

| AI Hub feature | Where |
| --- | --- |
| `%AI.Agent`: three specialists, a coordinator, a single investigator, the production review agent, the Explain agent and the board's question mode | [Agent](https://github.com/MxSalata/shutter/tree/main/src/Shutter/Agent) |
| `%AI.Tool` with typed arguments: the evidence drill-downs and the terminal tools (`SubmitFindings`, `SubmitPlan`, `SubmitReview`, `SubmitAnswer`, `SubmitBoardAnswer`); the answer tools refuse a setting that is not among the case's facts | [Tools](https://github.com/MxSalata/shutter/tree/main/src/Shutter/Tools), [Schema](https://github.com/MxSalata/shutter/tree/main/src/Shutter/Schema) |
| `%AI.Policy.Authorization` holds each run to its own case; `%AI.Policy.Audit` writes each tool call to the trace's log | [Policy](https://github.com/MxSalata/shutter/tree/main/src/Shutter/Bridge/Policy) |
| RAG on `%AI.RAG.VectorStore.IRIS` with FastEmbed: the interface contract, encounter lifecycle, operation effects, member playbooks and review rules | [Library.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Knowledge/Library.cls) |
| The provider key in the IRIS wallet, named in the Config Store as `secret://Shutter.Anthropic#key` (`AI.LLM.Shutter`); only holders of `Shutter_LiveAgents` may run the board live, and each live run is charged to its requester within the day's budget; sessions with prompt caching; tokens and cost per run | [Setup.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Setup.cls), [AIHub.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Bridge/Runner/AIHub.cls) |
| `Model`, `ProviderConfig`, `TokenBudget` and `MaxIterations` as settings of each board item | [Agent.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Bridge/Operation/Agent.cls) |
| The tool catalogue, pinned: before any model call a run checks that `%Discover` names exactly its declared tools, and any other catalogue ends it as `catalogue_mismatch` | [Catalogue.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Bridge/Catalogue.cls) |
| Findings checked on the way back: each must cite evidence the run was given (`evidence_refs`), or the model repairs it in the same run; precedents (what approvers decided before) are shown to the person and never to an agent | [Findings.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Schema/Findings.cls), [CONTRACTS.md](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#64-the-site-profile-and-the-policy-path) |

## Technology bonuses

| Bonus | Where to see it |
| --- | --- |
| Workflow Engine | Each approval is an `EnsLib.Workflow` task for the role "Shutter Approvers", bound to the plan's digest; S2's waits in the Workflow inbox ([CaseWorkflow.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Process/CaseWorkflow.cls), [IncidentWorkflow.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Process/IncidentWorkflow.cls)). For a hospital: approvers work in the inbox IRIS already has, and an approval can never be reused for a different plan |
| IRIS Vector Search | The agents' knowledge bases are IRIS vector tables (`%AI.RAG.VectorStore.IRIS`, FastEmbed `AllMiniLML6V2`, 384 dimensions), one per collection, from `Shutter_Knowledge.contracts` (26 chunks) to `Shutter_Knowledge.explain` (76), searched by the agents' `search_*` tools ([Library.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Knowledge/Library.cls)). In the SQL page (namespace `SHUTTER`) a judge can rank the stored chunks by `VECTOR_COSINE` ([the query, run on build 109](https://github.com/MxSalata/shutter/blob/main/docs/readme/running.md#the-knowledge-in-iris-vector-tables)). For a hospital: the agents look up the site's own interface contract and encounter rules, kept inside IRIS, instead of guessing |
| Embedded Python | Any IANA feed time zone, through Python's `zoneinfo` ([Time.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Util/Time.cls), `PyOffset`). In SHUTTER: `SELECT Shutter_Util.Time_Probe('20261015092000', 'Europe/Paris')` answers `"iso":"2026-10-15T07:20:00Z"`. For a hospital: a feed in any IANA time zone other than Europe/London (whose rules Shutter keeps in ObjectScript) is put in true event order, summer time included, and the site profile accepts a feed time zone only when `zoneinfo` knows it ([SiteProfile.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Store/SiteProfile.cls)) |
| Custom Adapter | The HL7 index walk is Shutter's own inbound adapter, handing batches of message headers to the HL7 Index item ([Index/Adapter.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Index/Adapter.cls)). For a hospital: Shutter knows each encounter's other messages, so it can tell an old resend from the latest state |
| PEX (Java) | The Second Parser, a Java business operation (`EnsLib.PEX.BusinessOperation` with HAPI 2.6.0): when IRIS can't read a failed message, it says whether the message is sound or malformed. See S25 ([pex/](https://github.com/MxSalata/shutter/tree/main/pex)). For a hospital: it says whether the sender or the site's schema has to be fixed. To check it built, `SELECT Shutter.Setup_Doctor()` reports `second_parser` |
| Docker | `install.sh`, or `docker compose up` ([docker-compose.yml](https://github.com/MxSalata/shutter/blob/main/docker-compose.yml), [Dockerfile](https://github.com/MxSalata/shutter/blob/main/Dockerfile)). For a hospital: a full trial on a laptop, away from the live production |
| IPM | One package for the AI Hub builds, `iris-shutter`, requiring IRIS 2026.3 or later with Interoperability, as the organisers ask: `zpm "install iris-shutter"` once it is published, or `zpm "load"` from a clone, as the image build does on 109 and 154 ([module.xml](https://github.com/MxSalata/shutter/blob/main/module.xml)). The replay edition's core alone: [core/module.xml](https://github.com/MxSalata/shutter/blob/main/core/module.xml). For a hospital: one install on its own IRIS for Health with AI Hub |
| Community Opportunity idea [DPI-I-689](https://ideas.intersystems.com/ideas/DPI-I-689) | Interoperability as the traceability tool for AI agents: the walk-through below. For a hospital: an integration team audits an agent with the Visual Trace and SQL it already knows |
| AI Hub bug reports | [#11](https://github.com/intersystems-community/ai-hub-eap-bugreports/issues/11): `%AI.Agent.Run()` takes three arguments, not four; [#12](https://github.com/intersystems-community/ai-hub-eap-bugreports/issues/12): `Run()` never calls `OnIterationStart` or `OnIterationComplete` |
| Embedded Python bug reports | [#26](https://github.com/intersystems-community/python-bugreports/issues/26): signal 11 after catching an SQL error in a Python SQL function under dynamic SQL; [#27](https://github.com/intersystems-community/python-bugreports/issues/27): defaults pasted into the Python source |
| Online demo | The live hospital, [link at submission]: a new failure every 7 minutes, recovered under the site's written policy; the sign-ins are under [Try it](https://github.com/MxSalata/shutter#try-it). The trial on GitHub Pages is its offline companion, recorded runs only |
| YouTube video | [link at submission] |
| Developer Community articles | [link at submission] |

### Tracing AI agents with Interoperability (DPI-I-689)

The idea asks whether Interoperability could do the job of a tracing tool such as Langfuse. In Shutter every agent run is a message, so the production's own trace serves.

**Follow one decision, step by step,** on your own instance (the replay edition is enough: no key, no cost) or in the online demo's Visual Trace:

1. Open http://localhost:52773/shutter/index.html as `operator` / `shutter`. In **Scenarios**, run **S8** in **Board** mode.
2. On S8's case page, **In IRIS: Message trace (session N)** opens the case's session in the Management Portal's Visual Trace. Each production item has its own lane: `Case Workflow`, `Evidence Collector`, then `Agent Conformance`, `Agent Encounter` and `Agent Impact` in parallel, then `Agent Coordinator` and the `Gate`.
3. Click an `AgentResponse` arrow. Its contents are the generation: `Model`, `Mode` (live or replay), `PromptTokens`, `CompletionTokens`, `CacheReadTokens`, `Iterations`, `ToolCalls`, `DurationMs` split into `LlmMs` and `ToolMs`, and `ConfigVersion`, the prompt's version.

   ![One board member's run as an AgentResponse in the Visual Trace: model, mode, tokens, iterations and tool calls](https://raw.githubusercontent.com/MxSalata/shutter/main/docs/readme/images/trace-agentresponse.png)

4. In the Management Portal's SQL page (namespace `SHUTTER`), run the second query below with that session number: every tool call of the pass, in order, with its duration, whether it was allowed, and the board member that made it.
5. On the case page, **When each agent worked** draws the same rows as a timeline, and the Costs page sums them by case.

| A tracing tool records | In Shutter |
| --- | --- |
| A trace (one end-to-end run) | The case's session in the Visual Trace, one lane per step and agent |
| A generation (one model call) | One `AgentRequest` and `AgentResponse` pair per run, with model, tokens, cost and duration, kept as an `AgentRun` |
| Tool calls and retrieval | Each tool call, knowledge searches and refused calls included, as a `ToolCall` row and in the trace's log (`%AI.Policy.Audit`) |
| Cost | The Costs page and `GET /costs`, by case, review and question |
| The prompt's version | The agent class's configuration version, in the request and each recording's key |
| Replay | Recordings keyed by encounter, event, member and configuration version, replayed by CI on every push |
| Spans and timing | Each run's start to the millisecond, its model and tool time, and each tool call's time and duration |

```sql
-- Agent runs, tokens and cost by board member, model and mode
SELECT %EXACT(MemberCode) AS Member, %EXACT(Model) AS Model, %EXACT(Mode) AS Mode, COUNT(*) AS Runs,
       SUM(PromptTokens) AS Prompt, SUM(CompletionTokens) AS Completion, ROUND(SUM(CostUSD), 4) AS CostUSD
FROM Shutter_Store.AgentRun
GROUP BY %EXACT(MemberCode), %EXACT(Model), %EXACT(Mode)
ORDER BY Member, Mode
```

```sql
-- One session's tool calls in order, with the board member that made each (? is the session number)
SELECT t.Seq, %EXACT(t.Name) AS Tool, t.DurationMs, t.Ok, %EXACT(h.TargetConfigName) AS Member
FROM Shutter_Bridge.ToolCall t JOIN Ens.MessageHeader h ON h.ID = t.RunKey
WHERE h.SessionId = ?
ORDER BY h.ID, t.Seq
```

### Building on AI Hub and Interoperability: what worked, what was hard

What I found building Shutter, measured on build `2026.3.0AI.154.0`; the longer story is article 1 [link at submission].

- **Worked well:** typed tools (a `%JSON.Adaptor` parameter gives the model a full JSON Schema and arrives as an instance, so a terminal tool refuses a bad result with reasons); the two policies, a few lines each; FastEmbed knowledge bases, built from Markdown in about 11 seconds; prompt caching.
- **Hard:** `agent.Run()` takes three arguments (the guide shows four) and calls only `OnRunStart` and `OnRunComplete`, so a token budget is judged after the run, and `MaxIterations` and the provider's timeout bound the loop.
- **Hard:** a provider must be named `@{config:<Name>}`, and a fresh Config Store needs `%ConfigStore.DescriptorManager.RebuildRegistry()` before `AI.LLM` has a descriptor.
- **Hard:** `%LogExecution` must be declared `As %Status`, which the guide doesn't show; the image has no IPM, so the build installs it; when two properties of a tool's argument share one schema class, the rest reach the model as a bare `object`, so the description spells out their fields; the Community licence's 8 units run out under cookie-less HTTP bursts, so scripts keep one cookie.
- **Interoperability, worked well:** every agent run and approval is a production message and each tool call is in the trace's log, so the Visual Trace and the Message Viewer already show a case end to end; `FailureTimeout` 0 makes a feed fail forward, so no later message waits behind a failed one.
- **Interoperability, hard:** a production sends its alerts to the one item named `Ens.Alert`, so the alert intake has to take that name and pass every alert on to the site's own consumer; a Workflow task's form fields are filled by the approver, so the plan's digest starts empty and an inbox approval must paste it, or it binds nothing.
- **Would like to see:** `Run()` calling `OnIterationStart` and `OnIterationComplete` ([#12](https://github.com/intersystems-community/ai-hub-eap-bugreports/issues/12)), so a token budget can stop a run between turns rather than after it.

## How it is tested

- **On a real IRIS, every push to `main` that changes code:** the full install on IRIS for Health Community 2026.2, the receiver's 36 contract tests, 250 unit tests (test methods in `tests/unit`; 7 more run only on an AI Hub build) and 26 scenarios end to end through the REST API, one through the demo hospital's production.
- **The approval boundary, attacked over HTTP:** an approval naming another plan or a stale version (409), an operator's approval (403), one approval sent twice (one write), the receiver changed after approval (S20, no write), and a resend of a delivery the receiver already holds (S3, no write).
- **Privacy, and a question that tries to act:** [evaluation.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/evaluation.md#what-the-agents-see-and-a-question-that-tries-to-act).
- **The web app:** 1219 component and 652 browser tests (`npm test`, `npm run test:e2e`), axe-core on 67 screens and states in 5 appearances.
- **The AI Hub module:** CI can't download an Early Access build, so it builds the core on the public image. The AI Hub module is proven by fresh clones installed with `install.sh` on builds 109 and 154 (each Doctor clean, the Second Parser running), every scenario on 109, 29 plays across the three modes ([receipt on 109](https://github.com/MxSalata/shutter/blob/main/docs/readme/receipt-109.md), [receipt on 154](https://github.com/MxSalata/shutter/blob/main/docs/readme/receipt.md)), the board recorded live on build 154 on 25 October and 1 November 2026 (100 agent runs, 10.00 USD at list prices), which CI replays on every push, and run live on build 109 on 3 November (S2, four runs, 0.42 USD).

## Limits, plainly

- Without an API key the agents replay recorded runs. A case with no recording, such as one from your own HL7 file, takes the rules path: the gate alone decides and a resend waits for a person.
- The receiver is a demo bed-management system built for the scenarios. Shutter resends only to a receiver whose API the site profile describes; any other, a plain MLLP receiver included, gets the board's diagnosis and an escalation, never a resend: an ACK says a message arrived, not what the receiver now holds.
- No local-model profile, on purpose: the board works through typed tool calls, which a frontier model makes reliably on evidence this detailed. A site's own model behind an API would be a provider in the Config Store; that is untested.
- The evaluation is one recording per board member and case, with one model: it can't show how often a repeat run agrees, and the catalogue was written alongside these scenarios. The injected instruction (S4) reaches the agents only as a flag, so S4 shows they notice it, not that they would resist the text.
- Spend: a storm of one kind convenes one board, which the other cases with its failure signature follow, each through its own gate and approval; `SHUTTER_DAILY_BUDGET_USD` caps a day's live spend, after which cases take the rules path ([more](https://github.com/MxSalata/shutter/blob/main/docs/readme/running.md#more-about-running-it)). The online demo's instance resets every hour; its live spend is capped at 5 USD an hour, 2 USD of it per judge, and 15 USD a day.

## Run details

What the organisers ask each README to give: the image and build, the load and retag steps, the provider and its key's variable, and the commands to start and check. `install.sh` above does these steps for you.

```sh
docker image load -i irishealth-community-2027.1.0AI.109.0-docker.tar.gz
docker tag docker.iscinternal.com/docker-intersystems/intersystems/irishealth-community:2027.1.0AI.109.0 irishealth-community:2027.1.0AI.109.0
git clone https://github.com/MxSalata/shutter.git && cd shutter
cp .env.example .env       # SHUTTER_IMAGE names the build; ANTHROPIC_API_KEY for live agents (model claude-opus-5-5)
docker compose up -d
docker compose ps          # again until it says healthy
curl http://localhost:52773/api/shutter/health
```

For build 154, use its file and the tag `irishealth-community:2026.3.0AI.154.0`, and set `SHUTTER_IMAGE` to it. If `docker image load` prints another name, tag that one. The health report says `"ok":true` once the production runs. Recording the board live for every scenario that convenes it cost 10.00 USD at list prices ([evaluation](https://github.com/MxSalata/shutter/blob/main/docs/readme/evaluation.md): 100 agent runs). The replay edition: in `.env`, set `SHUTTER_IMAGE=containers.intersystems.com/intersystems/irishealth-community:2026.2`, then `docker compose up -d --build`. To switch editions, run `docker compose down -v` first: it removes the instance's data.

**Open it:** the web application and the Management Portal at http://localhost:52773/csp/sys/UtilHome.csp, with the sign-ins under [Try it](https://github.com/MxSalata/shutter#try-it) (production `Shutter.Production`; the demo hospital's is `Hospital.Production` in `HOSPITAL`). Ports are published on `127.0.0.1` only. More in [docs/readme/running.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/running.md) and, for a hospital's own IRIS for Health, [docs/INSTALL.md](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md).

## Troubleshooting

- **`install.sh` stops at a check.** It prints `[fix]` with what to do for each one, and changes nothing until every check passes. A port in use: set `SHUTTER_WEB_PORT` in `.env`.
- **Not healthy after 25 minutes.** `install.sh` prints the last 30 lines of the log and the health address; `curl http://localhost:52773/api/shutter/health` is the report to read.
- **The Doctor.** In the Management Portal's SQL page (namespace `SHUTTER`), `SELECT Shutter.Setup_Doctor()`: `missing_items` and `disabled_items` should be `[]`, `production_state` `running`, `board_members` 5, `recordings` more than 0 and `second_parser` `probe: ok` ([the values on build 109](https://github.com/MxSalata/shutter/blob/main/docs/readme/receipt-109.md)).
- **"License limit exceeded" or "Service Unavailable".** The Community licence's 8 units are used up, usually by calls to the API without a session cookie; restarting the container (`docker compose restart`) frees them.
- **On the first start,** `ERROR #5002 ... Sharding` and "Error trading CSP licenses" come from the IRIS image and are harmless.
- **`install.sh` says the AI Hub image is too small.** The load was cut short; load the file again (a complete load is about 5.4 GB of content).

## About the contest

Shutter is an entry to the InterSystems Programming Contest "AI Agents in Interoperability Workflows" (Open Exchange contest 49): an IRIS Interoperability workflow that uses IRIS AI Hub agents for a decision-making task.

- Contest page: https://openexchange.intersystems.com/contest/49
- Announcement: https://community.intersystems.com/post/intersystems-programming-contest-ai-agents-interoperability-workflows
