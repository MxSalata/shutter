# Changelog

Versions follow `major.minor.patch`: a minor release for new features, a patch release for fixes and dependency
updates. The version in both `module.xml` files (the one the package manager publishes) is always the version of the
GitHub tag on the same commit; `scripts/check-versions.py` checks every place the version is written.

## 1.1.2 (8 November 2026)

What 1.1.2 holds: the fix for the null bed that held a settled case for a person, an incident of any size under one
approval, a supported uninstall and upgrade, a further-movement default that shows another visit on the plan instead of
stopping the resend, one trace line per tool call in a replay, and pages on running the board on another provider, on
AI Hub features measured with no model call and on the publisher from an MCP client. The README is restructured.

- **A receipt whose bed is null says nothing about the bed.** The receipt check read a JSON null bed as a different bed
  (`RECEIPT_PAYLOAD_DIFFERS`), so a person got a case the receipt had settled (held-out case F03). Beds are now compared
  only when both the receipt and the operation state one; a null, missing or empty bed reads as not stated, and a stated
  different bed still stops the close. A unit test covers each. With this check loaded over 1.1.1's code, the board's
  reconcile closed F03 in all three held-out runs, with nothing written (8 Nov 2026, AI Hub build 109).
- **Per-call trace lines in a replay.** A replayed run writes one trace line per recorded tool call, as a live run does,
  with the tool, ok, denied or failed, the milliseconds and the word replay, and no argument, result or error text, so
  each call is a step of its own in the Visual Trace. The tracing walk-through shows the steps and the page size that
  keeps a pass on one page.
- **Uninstall and upgrade.** `zpm "uninstall iris-shutter"` takes off everything the install and the onboarding added, in
  every namespace, and stops no production of the site's: a site production Shutter went into is updated in place and its
  own alert item gets its name back. `SELECT Shutter_Util.Uninstall_Plan()` says what would go. The uninstall refuses,
  changing nothing, while a production it did not wire still names a Shutter class, or while a hospital's namespace holds a
  class of the site's in the `Hospital` or `Downstream` package. A `zpm "load"` of a newer tree over an installed release
  is an upgrade that keeps the production, its cases and the site profile; restart `Shutter.Production` afterwards. Two
  checks, `tests/e2e/uninstall_check.py` and `tests/e2e/upgrade_check.py`, prove both on build 154, the upgrade over
  1.0.0 and 1.1.1.
- **An incident is one approval at any size.** The shared approval task's Workflow message holds 2,000 characters, and
  1.1.1 abandoned an incident above about four chains, with every case `failed`. The task now lists the first chains that
  fit, says how many it leaves out and points to the incident page; the digest is whole and one approval binds every
  chain. An error raising the task leaves the incident waiting for a person and tries again every 5 minutes. The incident
  page lists six chains with the rest behind one button. A storm check proves it at 40, 200 and 1,000 failures
  (`docs/readme/storm-at-scale.md`).
- **Another visit's movement shows on the plan by default.** `further_messages.in_patient_movement` is `show` in the
  shipped profile and when a profile doesn't say: an in-patient movement on another visit goes on the plan beside the
  resend instead of stopping it, while a cancel, merge or discharge on the case's own visit, or a change to the record,
  still stops it. A site that wants the stop sets `stop`. A fresh demo install keeps the stop, labelled in its profile,
  the live hospital's included, so S27, S31 and S32 stop as before. A stored profile that doesn't name the setting reads
  `show` after the upgrade, also on a demo whose profile a person or the onboarding saved (`docs/INSTALL.md`, section
  8). A write that shows such a movement is never released by policy: at a tier whose policy is `automatic` it waits
  for a person, and an incident's chain that shows one leaves the shared approval for its case's own path. A
  movement that arrives after the approval is compared with the approved plan at dispatch, and a new one holds the write
  (`FURTHER_MOVEMENT_NEW`) until the plan is read again and approved again.
- **Further messages in an onboarded namespace read the feed's zone.** The read of a patient's further messages runs in the
  watched namespace, which maps only Shutter's intake and utility classes, so a message time with no UTC offset looked up
  the feed's zone in a class that namespace can't reach, the read failed and the write stopped for a person
  (`FURTHER_NOT_READ`), with nothing written. The read now carries the zone from Shutter's namespace (`Shutter.Util.Time`,
  `Shutter.Util.FurtherMessages`), and a unit test reads a time in a namespace with no zone of its own. On build 154 the onboarding check
  passed 238 of 238 and the 26 scenarios played as expected with the fix.
- **Another provider, by hand.** `docs/readme/another-provider.md`: the board run on OpenAI's `gpt-4.1` through AI Hub on
  build 109, S2 and S8 as expected twice, with the steps as tested and their undo, runs unpriced and outside the day's
  budget, and the places the install assumes Anthropic. Current OpenAI models refuse the `max_tokens` the runner sends.
- **AI Hub notes and issues.** `docs/readme/building-on-ai-hub.md` adds skills, `response_format`, knowledge base search and
  `CreateFromConfig`, each measured on builds 154 and 109 against a local stub with no model call, and links the issues
  filed on 8 November 2026: #22 (a tool argument's schema), #23 (the Config Store descriptor), #24 (`max_tokens`), and a
  comment on #4 for 109. `docs/readme/mcp.md` is a transcript of the publisher from an MCP client: the tools listed,
  `GetCase` with its audit row, and the refusal without `Shutter_Publish`.
- **The README, restructured.** A first screen under 750 words with the judges' path, one sign-in table and the measured
  figures, every term defined; six limits inline and the rest in `docs/readme/limits.md` as a table of effect, workaround
  and status; the fuller rows in `docs/edge-cases.md`; a pilot in the order it works in `first-steps.md`; and the
  held-out cases on release 1.1.1 in `fair-test.md`.
- **The trial's judges' path.** The S8 card plays in the chosen mode and says so, `?trial=judge` opens Scenarios in Rules
  only on the S8 card with no welcome, and the Rules only note says S8 is exempted on purpose and that the gate holds the
  resend on a real case. The Evaluation page puts the held-out fair test above the board's own score, with always
  escalating, both single investigator figures and release 1.1.1's board; **Explore on my own** keeps the welcome away
  for the visit, and the boundary table's scroll area takes the focus where it scrolls sideways.
- **The README review fixes.** The trial route has its own line, the first screen is shorter, only the identifiers
  Shutter knows for the case are said to become tokens, and `SELECT Shutter.Setup_ClearProvider()`, which an install
  keeps, is the way to send nothing out; the pilot maps the trust's users to the two roles first.
- **The production review's agent never reads a patient's words.** An error group's signature goes to it as an IRIS
  error code or a digest, never the logged text, and a case aggregate's key goes as it is only when Shutter knows the
  word (an item of the production, a failure kind or state, an outcome or reason code Shutter writes, an acknowledgement
  code or an HTTP status); anything else, a surname or a postcode included, goes as its digest with its count. The
  stored review keeps every word, and the record key and `SnapshotDigest` don't move. The scenario routes
  (`POST /scenarios/reset` and `/scenarios/{id}/run`) answer 403 `not_a_demo_instance` and change nothing off the demo,
  and an end-to-end check plays two patients no fixture holds in Board mode with no key: nothing is written.
- **The MCP page.** The forwarder's `tool_not_found` is credited to the MCP Inspector's own tool-list check, with the
  sidecar's `isError` answer to a `tools/call` sent anyway.
- **Docs truth for 1.1.2.** The README's first screen gives the trial first, then the online demo, then
  `./install.sh --replay`, and a Measured box with each figure's release; `docs/readme/model-fails.md` maps each agent
  run status to what the case does, with the real bounds; the safety and limits pages say what 1.1.2 does as shipped;
  the F03 null-bed runs are published with the fair test; contracts v1.48. `docs/INSTALL.md` shows `InstallInto` with a
  site's own production name.
- **The health page.** Each group lists its checks first and its facts apart under **Details**.
- **The API page.** `docs/api/openapi.json` describes every route (an OpenAPI 3.1 file that CI checks against the
  dispatcher), and the Technical view gains an API page listing each route with its parameters, its role and an example.
- **Fixes found in review before the release.**
  - The decision lock is given back when cancelling an approval task fails, and a refused second decision names the
    decision that stands.
  - An incident's approval task is checked for the role before it is raised and after, and an incident whose task can't
    be raised goes back to awaiting approval once its other chains are done, so it stays listed.
  - The task text counts a chain as shown only when all of it fits.
  - Another visit's movement is never released by policy, leaves an incident's shared approval, and a new one after the
    approval holds the write at dispatch.
  - The uninstall also takes the messages, process rows, queues, saved engine state and Workflow index entries that
    Shutter's items left, and nothing of the site's; it stops at the first failed step with Shutter's configuration
    kept, and refuses when a namespace can't be read.
  - The installer refuses a production in the demo's `Hospital`, `Downstream` or `Shutter` packages.
  - The scenario runner plays on a demo instance only, over SQL and the terminal as over REST.
  - A key shown anywhere (agent start lines, refusals, settings, stored runs) is masked by one rule, and a model id
    written as a name and a version is shown as it is, not masked.
  - The production review withholds an error signature without blanking the same word elsewhere in its text, and the
    judges' address is set once.

## 1.1.1 (8 November 2026)

A fix found by the live board on build 109 at 1.1.0 (`docs/readme/receipt-109.md`, "The board live on build 109, release 1.1.0"):

- The route item an agent reads kept only its history and epoch, because the model view that reduces every item before it leaves IRIS read a route that says whether the receiver offers history as a receiver's body. The specialists then could not see that the receiver takes conditional writes and dry runs, and the live board held every resend for more evidence. The view now reads a route as a route, keeps its capability profile and the history field, and a unit test holds it there. Replay was not affected: a recording answers in the model's place.
- The README's testing figures name the 1.1.0 run; the install notes say which build a plain install takes when both are loaded, how to choose, and how to change the port; the first step says which case id a fresh install shows.
- The Shutter in IRIS page lists the production's agents, the model each runs when live and where it comes from, its mode, turns, budget and last run, and the other operations with the settings that hold no secret. It no longer reloads itself every 30 seconds, which took a screen reader back to the top: a Refresh link beside the time reloads it.

## 1.1.0 (8 November 2026)

What 1.1.0 holds: Shutter watches configured HL7 TCP operations without contacting their receivers. It groups outages,
shows whether the engine is retrying or messages have settled, preserves unresolved exceptions, and shows the site's next
action and contact. It sends no orders or results. At supported stock TCP routes, it also prevents Shutter's ADT API
recovery from competing with the engine's delivery. And the shipped site profile now asks a person before every resend.

- **A person approves at every tier by default.** The shipped site profile's policy is approval for single and ordered
  chains at tiers 1 to 3, and the board for interleaved ones; a site that wants a tier released by its policy says so in its
  own profile. A demo install keeps the earlier table (tiers 1 and 2 released by policy for single chains, tier 1 for ordered
  ones) as the demo's own setting, marked in the profile's source and labelled on the Site profile page; the online demo
  also asks a person at tier 2 for single chains. A profile a person saved is never changed.
- **A receiver's outage is one incident.** A receiver whose site profile entry has a `watch` block is read by the new item
  `Receiver Watch` every 5 seconds: the production's state, the operation's status, adapter state, queue, head message and
  settings, in the watched namespace, with no connection to the receiver and nothing written there. One outage opens per
  receiver, drains, closes when every header of its window has settled, or goes to a person, with the engine's own alerts
  beside the record and the cases of the outage listed with it. A linked case is resolved only from its own delivery header.
  The routes `GET /outages`, `GET /outages/{id}` and `POST /outages/{id}/acts` (pause and close) carry the outage's words:
  what the engine is doing, the site's runbook and call lines, who may approve, and at an orders and results receiver the
  critical-results sentence. The Doctor's `outages` reads each watched item's settings and names what a profile declares that
  the build does not act on (`docs/INSTALL.md` section 11).
- **The site profile takes a receiver's outage keys:** `watch`, `runbook`, `call`, `approvers`, `ack_level`, `duplicates` and
  the minutes, checked in the same words by the server and the page; `engine_resend`, `hold` and `mail` validate and do
  nothing in this release.
- **No write while the engine still has the message.** At a stock HL7 TCP operation, a write waits while the engine is
  still trying its message (`ENGINE_STILL_TRYING`), resolves when the engine delivered it (`ENGINE_DELIVERED`), and is blocked
  for a person when the receiver may already hold it (`RECEIVER_MAY_HOLD_IT`) or the engine's record can't be read
  (`ENGINE_UNREADABLE`). The Case Releaser judges each waiting case again every few seconds. This closes a double delivery
  measured on 1.0.0: an approved API write, then the engine's own delivery when the listener returned.
- **No claim of verification without a receipt.** A case with no receipt says the receiver was not checked, with the words
  its declared acknowledgement level allows, and the escalation email promises no check of a receiver Shutter can't read.
- **Further messages for the patient.** Before a write Shutter reads the patient on every visit it can see: a further
  in-patient movement on another visit stops the write and names both visits, a lost admission waits for a person, and the
  read walks every header since the case's own, for as long as the profile's `further_messages.scan_seconds` allows.
- **An automatic release needs the case's source proved:** the named namespace must hold the named header with the text
  received, sent to that receiver; otherwise a person approves (`feed.prove_origin`).
- **What reaches Shutter.** An alert or a negative acknowledgement carries the message the failing item was sent; a session
  with several messages to one item opens no case on a guess and says so; alert words Shutter does not know read as an
  uncertain outcome, never as not delivered; a forward nobody answered waits in the forwarder's queue and is tried again for
  its `FailureTimeout` (300 seconds as onboarding now sets it).
- **What the receiver must honestly offer.** A resend needs a readable history; a read counts only when it is the receiver's
  own answer, a 200 is a delivery only with its receipt, and a receipt closes a case only when it holds the message's own
  content (`strict_answers`). A write a receiver made during a rehearsal goes on the record and stops the case.
- **The verifier and the purge.** No sign of a write by the last read is unknown, not "not committed"; the case purge takes
  only finished cases.
- **Incidents.** An approval under an incident binds the plan's receiver epoch; the next item of a chain goes at the version
  in the previous item's receipt; a chain waiting on a bed held in a later chain of the same incident stops; the intake of an
  incident closes at a maximum time while the receiver keeps refusing.
- **The catalogue.** E19, new, sends a case with a death on the message to a person; E1 closes a failed transfer only; E7
  takes a movement from another source within `feed.source_skew_seconds`; E13 is revised. A case the catalogue gives to the
  board or a person goes to a person when no board member can answer. Policy version 2026-11-06.1.
- **The approval dialogs** name the case, the patient with authority, the event time and the bed, and hold the plan they
  opened on.
- **Upgrading:** run the install once and restart the production. Approvals given before the upgrade and not yet dispatched
  are refused (the policy and catalogue versions moved), precedents recorded before it are not found under the new policy
  version, and saving the profile voids approvals not yet dispatched (`docs/INSTALL.md` section 8).
- **Not in this release:** a list of messages to send again, a resend of orders or results, named findings, an agent's
  summary of an outage, a profile assistant, the outage email and the hold on a patient's ADT traffic. The limits are
  `docs/INSTALL.md` section 11.7.

## 1.0.0 (6 November 2026)

What the first release holds: Shutter, supervised recovery of failed deliveries in an InterSystems IRIS
Interoperability production, with a board of IRIS AI Hub agents.

- **A failed delivery is a case, not a retry.** When a delivery from an HL7 ADT feed fails, Shutter opens a case,
  gathers the evidence (the message, the receiver's state, receipt and history) and decides what should happen:
  resend it, reconcile it because it already arrived, leave it because a later event superseded it, or escalate it.
- **A board of AI Hub agents** (in the `iris-shutter` package; the core module `iris-shutter-core` replays their
  recordings): three specialists review a case in parallel and a coordinator proposes one plan, each agent a business
  operation in `Shutter.Production`, with their tools, schemas and knowledge bases on IRIS Vector Search
  (`%AI.RAG.VectorStore.IRIS`). Without an API key or the AI Hub build, the agents replay recorded runs.
- **A deterministic gate** checks every plan (identity, conformance, intent, ordering, state transition, effect,
  authorization, rehearsal, concurrency, evidence freshness, the receiver's capabilities and the catalogue); an unknown blocks
  a write as surely as a failed check.
- **A person approves the exact action**, bound to the plan's digest, the evidence, the gate's policy and the
  receiver's version, or the site's policy does for the cases the scenario catalogue knows. Shutter then makes one
  conditional write and verifies it in the receiver's own history.
- **Who decided.** The approver of record for a case's or an incident's approval is the signed-in user, never a name
  in the request: the route assigns the Workflow task to that user, writes the digest the body named into the task and
  completes it, and answers who was recorded. An approver outside the Workflow role `Shutter Approvers` is refused
  (403), as is an approval with no digest and a task another approver holds. The approval tasks no longer pre-fill
  the plan digest: an approver who decides in the Management Portal's Workflow inbox pastes it from the task's text,
  so an approval from the inbox binds the digest as the API's does. The same step from SQL,
  `Shutter.Util.Workflow.Decide`, takes the digest instead of a user name.
- **A write stands on its own dry run.** The gate's rehearsal check releases a write only when the approval's bound
  rehearsal is of the same plan, reported it would apply, and was checked against the version, epoch and payload the
  write carries (`DRY_RUN_MISSING`, `DRY_RUN_FAILED`, `DRY_RUN_STALE`); a receiver whose capability profile offers no
  dry run gets no resend (`DRY_RUN_UNSUPPORTED`), and the connector sends it no dry run. A receiver that applies a dry
  run is recorded as an execution, alerted and verified, never reported as rolled back, and the blind-resend preview
  refuses such a receiver and reports what it was checked against. Policy version 2026-10-25.1: an approval given
  before it and not yet dispatched is void at dispatch.
- **No verdict from silence.** A write whose answer was lost is read again (10, 20, 40 s); the verifier says not
  committed only after its settle window (30 s by default) with the receiver's version unchanged, or once the version
  moved past the one the write was conditional on, and the case then escalates with the approval revoked
  (`WRITE_NOT_COMMITTED`; `WRITE_OUTCOME_UNKNOWN` when the reads could not settle it). An acknowledged write without a
  receipt is a contradiction, not "not committed", and nothing is ever resent from a verification. The matcher, the
  gate and the verifier agree on what supersedes: a later applied cancel, merge or admission blocks a resend, a later
  transfer the feed sent whose delivery failed is named by its key and case on both cases, and the condition
  `later_delivery` says whether the superseding event reached the receiver.
- **Incidents:** many failures to one receiver become chains per encounter, released in order under one approval,
  stopping at the first surprise.
- **The incident's approval binds each item.** The incident plan's digest is the SHA-256 of the whole recorded plan
  in canonical JSON, so every item's case, catalogue entry, outcome, who decides and the version it goes at are
  bound, and the digest is recomputable from `GET /incidents/{id}`. A released item whose fresh evidence reads another
  entry or outcome than the approval covered blocks before it is planned ("Not covered by the incident's approval")
  and its chain stops; the case's approval records the incident plan's digest and the bound entry and outcome
  (`incidentPlanDigest`, `boundEntry`, `boundOutcome`), and the dispatch gate refuses it with
  `APPROVAL_ITEM_CHANGED` or `APPROVAL_INCIDENT_PLAN_CHANGED` when they no longer hold.
- **The site profile:** the induction questions that decide what goes without a person, who approves what, the teams
  an escalation goes to, the feed's time zone and whether note text may reach the model, with every version kept.
- **Only what is needed reaches the model:** identifiers become per-case tokens, names, dates of birth and addresses
  are dropped, and CI fails when anything personal from the fixtures reaches a recording. When the reduced view of a
  case cannot be made, no request is built: the case is escalated with the reason and nothing reaches a model.
- **Merges** are withheld by default (the site profile can allow them for a receiver that takes them), and **cancels**
  the receiver cannot take are withheld; both are escalated, with an email drafted for the team the site profile names.
- **Escalation emails** go only to bare addresses inside the site profile's `mail.allowed_domains` (with none set no
  email can go), with no line break in the subject or an address, checked when the profile is saved, at the edit, at
  the send and by the mail operation before it writes; a hand close cancels every pending email and nothing is sent
  about a case that is closed or reopened; and the text of each email (the one copy of the NHS number and the date of
  birth outside the message store) and its `.eml` file are removed 90 days after the case closed
  (`SHUTTER_ESCALATION_DAYS`; `0` keeps them; on by default, an upgraded instance included), the row staying with its
  digest and recipients.
- **The web application:** scenarios, cases, incidents, the board's findings, the gate, approvals, verification, the
  site profile, the library, and costs and tokens per agent run; served by IRIS, and as an online demo of recorded
  runs.
- **Scenarios** S1 to S25 (S14 aside; S23 in three parts; 26 in all) that play each kind of failure end to end on the
  demo downstream system, a demo hospital production in its own namespace that Shutter watches (S19), a nurse's move entered by hand in the
  downstream system while a resend waits for approval: the approval is bound to the receiver's version, so the resend
  never writes over her entry (S20), and a transfer timed in the hour that happens twice when British clocks go back,
  which nothing writes (S21). Their messages carry what a real PAS feed sends: an NHS number beside the hospital
  number in PID-3, the prior location of a transfer and the location on an update or a discharge.
- **One transfer, two receivers** (S22): the same feed goes to the bed manager and to a demo patient records system
  (the `RECORDS` namespace behind `/records/api`, the items `ADT to Records` and `Records Out`, category
  `history_of_record`). A case is one failed delivery to one receiver, so the bed manager's case closes superseded with
  no write and the records system's escalates with the steps that correct its history.
- **The occupied bed** (S23a to S23c): for a `409 bed_occupied` refusal the evidence reads who holds the bed and whether
  they are leaving, and the gate answers `OCCUPANT_MOVED_OUT`, `WAITING_FOR_OCCUPANT_CASE`, `OCCUPANT_CASE_FAILED` or
  `BED_OCCUPIED`, a case waiting on the occupant's own case. **A newer message on its way** (S24): the gate holds a resend
  with `NEWER_MESSAGE_PENDING` while a later message for the encounter is still undelivered, and the connector checks
  again at the moment of the write. **A site's own segment** (S25): a message IRIS cannot read against the loaded schema
  is never resent (`PARSE_FAILED`, with the Second Parser's verdict). The gate's policy version in this release is
  `2026-11-01.1`; an approval given under an earlier version and not yet dispatched is void at dispatch
  (`APPROVAL_POLICY_CHANGED`).
- **The Second Parser:** a Java business operation through PEX (`Shutter.Operation.SecondParser`, HAPI 2.6.0, built by
  `pex/build.sh`) that the Evidence Collector asks when IRIS cannot read a message; it says whether the message is well
  formed and of a schema this namespace lacks, or malformed and where, and the gate's `SCHEMA_UNKNOWN` and `PARSE_FAILED`
  words carry its verdict. Without the jar the item is disabled and the Doctor's `second_parser` says so.
- **Custom HL7 schemas, and prevent failures:** the Doctor's `hl7_schemas` (loaded, needed, missing),
  `Shutter.Setup.ImportSchema` and `GET` and `POST /settings/schemas`; a message whose category is not loaded is
  `unknown schema`, blocked `SCHEMA_UNKNOWN` until the schema is there. With the site profile's `feed.prevent_failures`
  such a message is held as a case of kind `unreadable` instead of delivered, and the index's check releases it once the
  schema is imported (catalogue entry E18).
- **Onboarding a hospital's namespaces:** a plan that changes nothing (`Shutter.Setup_OnboardPlan`), an apply that does what it
  listed and never stops a production, a marked test failure per namespace, the Doctor's `watched_namespaces`, and a removal;
  an item or a schema category named alike in two namespaces stays apart, and a namespace keeps its receiver names when another
  comes on after it; the forwarder's user goes with the last namespace's removal, never before (`docs/INSTALL.md`, section 9). A forward naming a
  category not loaded here is reported as such and repaired once it is loaded, and a load in a namespace running another
  production is refused.
  A message routed to two receivers opens a case for each that fails. The plan warns of retry-forever whether the item sets it or
  inherits it, a refused forward also raises an alert to the site's consumer, and the Doctor counts refused forwards over 72 hours and
  lists HL7 operations added since the last apply.
  The plan says, per HL7 operation, what a completed message proves there, as measured against a listener: on the stock codes CA reads as
  AA. A negative application acknowledgement on a feed of its own can open a case, through a small process a site copies and
  `Shutter.Intake.AckMatch`. A message taken by a transport ACK and then lost downstream raises nothing.
- **The index walk is an adapter of Shutter's own** (`Shutter.Index.Adapter`, handing batches of message headers to
  the HL7 Index item), and **any IANA time zone** for the feed through Embedded Python's `zoneinfo`
  (`Shutter.Util.Time.PyOffset`), beside the native rules for UTC, Europe/London and fixed offsets.
- **Ask about this case:** a deterministic what-if card (`GET /cases/{id}/whatif`) and questions to the Explain agent or
  to the board (`/cases/{id}/questions`), answered from recorded conversations without a key; the agents cannot write.
- **A storm is survivable:** the alert intake (`Shutter.Intake.AlertProcess`, a watched production's `Ens.Alert` item,
  hands a failed delivery to Shutter from the alert alone); one board per failure signature (the first case leads, the
  rest take its decision through their own evidence, gate, rehearsal and approval); boards per minute capped
  (`BoardsPerMinute`); a bounded approval wait (`ApprovalWaitSeconds`); a bound on one model call
  (`SHUTTER_PROVIDER_TIMEOUT_SECONDS`); a receiver's `Retry-After` kept as a minimum wait before a resend; and the Case
  Releaser item, which releases waiting and held cases in a sweep of its own.
- **Precedents:** what approvers decided before on the same conditions at the same receiver, and whether it held,
  counted in the approval task's text and answered by `GET /cases/{id}/precedents`.
- **The tool catalogue is pinned** when a run starts (`Shutter.Bridge.Catalogue`): what the framework discovered must be
  exactly the agent's evidence tools, its terminal tool and its collections' search tools, or the run ends
  `catalogue_mismatch` before any model call. Findings and plans may cite only the evidence they were given, and
  invisible characters are stripped from everything a model wrote.
- **The live hospital and the storm:** with `SHUTTER_LIVE=1` the demo hospital's Live PAS item plays one of Shutter's
  scenarios every 7 minutes with fresh patients at present times and real faults, and writes an ordinary message a
  minute between stories; `POST /live/storm` ("Break the feed") fails eight movements for four fresh patients with the
  receiver down for a minute, so an incident can be watched on demand.
- **The public demo's users and the model budget:** `demo` (reads, reinvestigates, approves and asks; never spends),
  `demo-trace` (the Visual Trace and the messages in the Management Portal, read only) and `judge` (the demo's role plus
  the live agents), each made only when its password is set. `SHUTTER_DAILY_BUDGET_USD` caps what the live runs spend
  per day, with an estimate reserved for each run in flight, and `SHUTTER_JUDGE_BUDGET_USD` gives each user a share; at
  the cap a run is refused `budget_exhausted` and the board takes the rules path. `GET /settings` says whether the live
  agents can run (`live.agents`). The demo's Management Portal is read only: its applications require `Shutter_Portal`,
  which `Shutter_Trace` alone holds.
- **The publisher:** Shutter's cases, incidents, evidence, plans, events, precedents and health as read-only MCP tools
  (`Shutter.Publish.Tools`) through IRIS's own MCP gateway at `/mcp/shutter`, on the AI Hub build; identifiers
  tokenised, an audit row per call, nothing written.
- **A case the workflow left behind can be abandoned.** The production's start notes every case still in a working state (an error-kind event saying when it started and the way out), and an approver abandons a case whose workflow has had nothing in flight for 15 minutes (`POST /cases/{id}/abandon`; 409 `busy` while it has, with what is in flight): the case fails with disposition `abandoned`, its approval is revoked, its pending escalation emails and open approval task are cancelled, and it can be reinvestigated. The Doctor and `GET /health` report `working_cases` and `abandon_after_minutes`.
- **A production review, on request.** `POST /api/shutter/production-reviews` runs one read-only pass over a production
  Shutter knows (its own, or a watched one such as the demo hospital's) through the new Case Review item:
  `Shutter.Util.ProductionReader` reads the production in its own namespace as plain data, and `Shutter.Review.Sweep`
  runs 23 checks (`Shutter.Review.Checks`) over the items' effective settings, resolved through the item, the default
  settings and the class default, the event log's errors grouped by signature, the suspended, aborted and errored
  messages, the queues, the rule log and the message purge task, over a window of 1 to 90 days, each finding tied to the
  cases Shutter opened for that item. The review is stored (`PR-000001`, the last 50 per production) with the findings in
  a deterministic order (severity tier, unique cases, recency) and a fingerprint of the configuration findings. One AI
  Hub agent, `Shutter.Agent.Review`, asked through the Agent Board item with a smaller budget than a board member's (3
  turns, 60,000 tokens), ranks the findings within their severity tiers and explains each in one or two sentences
  against the case history, seeing item names, setting values, counts and case ids only, never message content or a
  patient identifier; it has no evidence tools and one knowledge collection, the production review rules
  (`knowledge/review/production-review-rules.md`: what each check means, why it matters, the safer value and when it is
  intended), and it calls one typed tool, `SubmitReview`, whose schema refuses a ranking that repeats a finding or
  leaves a gap in the ranks. The agent never changes a severity, a count or a value, and a ranking that misses one of
  the review's findings or puts a lower tier above a higher one is refused: the deterministic order stands, as it does
  when the agent fails, has no recording to replay or is skipped. An approver marks a finding intended, an accepted risk or a false positive; the annotation binds the
  finding's exact effective value and reopens when the value changes, it expires or it is revoked. Nothing writes to
  the production. `GET /costs` lists the reviews' agent runs apart.
- **The case record is written only by its own transitions:** the plan, the gate decision, the agent run, the case
  token, the finding and the approval refer to their case by id, so saving one never writes the case whole, and the
  cases list reads each case's plan origin with the case ids in one query.
- **The boundary, tried over HTTP:** `tests/e2e/boundary_check.py` approves with another plan digest, a stale case
  version and as an operator, sends one approval twice with its Idempotency-Key and then reuses the key, approves S20
  after the nurse's move and lets rules alone resend S3, and checks each is refused with nothing written; CI runs it
  after the roles check, and the Evaluation page lists the attempts from `docs/readme/boundary.json`, which the script
  writes.
- **Install:** the `iris-shutter` IPM package (the whole of Shutter for an AI Hub build, IRIS 2026.3 or later) and the
  `iris-shutter-core` module (loaded by path on IRIS for Health 2026.2, where the board replays its recordings),
  `install.sh`, a Dockerfile and `docker compose up` (the image decides its edition itself, `WITH_AIHUB=auto`, and the
  demo users' password reaches the build as a BuildKit secret), and a site install into an existing production. The
  data databases live on the `shutter-mgr` volume, so a rebuilt image upgrades in place (`docs/INSTALL.md`, section 8),
  and `Shutter.Setup.Doctor` reports what an install or an upgrade left (`missing_items`, `disabled_items`, `edition`,
  `second_parser`, `credentials_ok`).
