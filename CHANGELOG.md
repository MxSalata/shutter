# Changelog

Versions follow `major.minor.patch`: a minor release for new features, a patch release for fixes and dependency
updates. The version in both `module.xml` files (the one the package manager publishes) is always the version of the
GitHub tag on the same commit; `scripts/check-versions.py` checks every place the version is written.

## Unreleased

What the first release holds: Shutter, supervised recovery of failed deliveries in an InterSystems IRIS
Interoperability production, with a board of IRIS AI Hub agents.

- **A failed delivery is a case, not a retry.** When a delivery from an HL7 ADT feed fails, Shutter opens a case,
  gathers the evidence (the message, the receiver's state, receipt and history) and decides what should happen:
  resend it, reconcile it because it already arrived, leave it because a later event superseded it, or escalate it.
- **A board of AI Hub agents** (the `iris-shutter-aihub` module): three specialists review a case in parallel and a
  coordinator proposes one plan, each agent a business operation in `Shutter.Production`, with their tools, schemas
  and knowledge bases. Without an API key or the AI Hub build, the agents replay recorded runs.
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
- **Scenarios** S1 to S21 (S14 aside) that play each kind of failure end to end on the demo downstream system, a
  demo hospital production in its own namespace that Shutter watches (S19), a nurse's move entered by hand in the
  downstream system while a resend waits for approval: the approval is bound to the receiver's version, so the resend
  never writes over her entry (S20), and a transfer timed in the hour that happens twice when British clocks go back,
  which nothing writes (S21). Their messages carry what a real PAS feed sends: an NHS number beside the hospital
  number in PID-3, the prior location of a transfer and the location on an update or a discharge.
- **A case the workflow left behind can be abandoned.** The production's start notes every case still in a working state (an error-kind event saying when it started and the way out), and an approver abandons a case whose workflow has had nothing in flight for 15 minutes (`POST /cases/{id}/abandon`; 409 `busy` while it has, with what is in flight): the case fails with disposition `abandoned`, its approval is revoked, its pending escalation emails and open approval task are cancelled, and it can be reinvestigated. The Doctor and `GET /health` report `working_cases` and `abandon_after_minutes`.
- **The case record is written only by its own transitions:** the plan, the gate decision, the agent run, the case
  token, the finding and the approval refer to their case by id, so saving one never writes the case whole, and the
  cases list reads each case's plan origin with the case ids in one query.
- **The boundary, tried over HTTP:** `tests/e2e/boundary_check.py` approves with another plan digest, a stale case
  version and as an operator, sends one approval twice with its Idempotency-Key and then reuses the key, approves S20
  after the nurse's move and lets rules alone resend S3, and checks each is refused with nothing written; CI runs it
  after the roles check, and the Evaluation page lists the attempts from `docs/readme/boundary.json`, which the script
  writes.
- **Install:** the `iris-shutter` and `iris-shutter-aihub` IPM modules, a Dockerfile and `docker compose up`, and a
  site install into an existing production.

## 1.0.0

To be dated at release: the entries above move here when 1.0.0 is tagged and released on Open Exchange.
