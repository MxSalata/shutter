# Changelog

Versions follow `major.minor.patch`: a minor release for new features, a patch release for fixes and dependency
updates. The version in both `module.xml` files (the one the package manager publishes) is always the version of the
GitHub tag on the same commit; `scripts/check-versions.py` checks every place the version is written.

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
