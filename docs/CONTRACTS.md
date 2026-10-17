# Contracts between Interlock's parts

Version 1.6, 17 October 2026. These are the interfaces the parts of Interlock are built against. Change the version and the date when something here changes, and say what changed at the end.

## 1. The ward system's API

The synthetic ward system (`Wards.*`) stands in for a downstream bed-management system. It is the only receiver the production delivers to, for normal traffic, rehearsals and recovery alike. Base path `/wards/api`, JSON in and out, IRIS password authentication.

### 1.1 Apply an operation

`POST /wards/api/operations`

```json
{
  "operation_key": "PAS^HOSP^MRN1001^ENC-1001^transfer^2026-10-15T09:20:00Z",
  "encounter_id": "ENC-1001",
  "patient_id": "MRN1001",
  "patient_id_authority": "HOSP",
  "event": "transfer",
  "ward": "WARD-B",
  "event_time": "2026-10-15T09:20:00Z",
  "source_system": "PAS",
  "source_message_id": "MSG00002",
  "expected_version": 1,
  "payload_digest": "sha256:…",
  "dry_run": false
}
```

- `event` is one of `admit`, `transfer`, `discharge`, `update`. `ward` is required for `admit` and `transfer` and must be null for `discharge` and `update`.
- `event_time` is the source event's time (see section 2), in ISO 8601 UTC with a `Z`. The ward stores it but **does not order by it**: operations are applied in arrival order. That is the receiver contract, and it is why a stale transfer applied late moves a patient backwards.
- `expected_version` is optional. When present, the operation applies only if the encounter's current version equals it. Normal traffic omits it; recovery always sends it.
- `payload_digest` is the sender's SHA-256 of the canonical payload (section 1.6). The ward computes its own and compares them when an operation key is reused.
- `dry_run: true` runs the whole validation and the write inside a transaction that is always rolled back, and reports what would have happened. Nothing is committed, no receipt is stored, no event is appended.
- A rehearsal's response also carries what it was checked against (v1.5): `encounter_before`, the encounter as the ward held it before the dry run (null when the ward has never seen it), `encounter_after` when it would apply, and `epoch`. The case workflow takes the receiver version an approval binds from `encounter_before.version`, never from `encounter_after`.

Responses:

| Status | Body | When |
|---|---|---|
| 201 | `{"applied": true, "receipt": {…}, "encounter": {…}}` | Applied and committed |
| 200 | `{"applied": false, "reason": "already_committed", "receipt": {…}, "encounter": {…}}` | The same operation key was committed before, with the same payload digest |
| 200 | `{"applied": false, "rehearsal": true, "would_apply": true, "encounter_after": {…}}` or `{"applied": false, "rehearsal": true, "would_apply": false, "reason": "<one of the error codes below>", …}` | `dry_run` |
| 409 | `{"error": "version_conflict", "expected_version": 1, "current_version": 2}` | `expected_version` present and different from the current version |
| 409 | `{"error": "key_reused_with_different_payload", "operation_key": "…"}` | The key was committed with another payload digest |
| 422 | `{"error": "invalid_transition", "state": "discharged", "event": "transfer"}` | The transition is not allowed (section 1.4) |
| 422 | `{"error": "unknown_encounter", "encounter_id": "…"}` | `transfer`, `discharge` or `update` for an encounter the ward has never admitted |
| 422 | `{"error": "patient_mismatch", "encounter_id": "…"}` | The encounter exists for another patient (identity never silently changes) |
| 422 | `{"error": "payload_digest_mismatch"}` | The sender's `payload_digest` differs from the ward's own computation |
| 422 | `{"error": "invalid_request", "detail": "…"}` | Missing or malformed fields |
| 503 | `{"error": "ward_unavailable"}` | Fault `fail_before_accept` is on (section 1.5); nothing was validated or written |
| 504 | empty body | Fault `commit_drop_response` is on: the operation **was committed** and the receipt stored, then the response was lost |

Decided with the ward system (15 Oct): faults apply to real operations only, never to a dry run; a discharge sets `ward` to null; for an `admit`, `expected_version` 0 means "not yet seen"; the per-encounter lock waits 10 s and then answers 503 `ward_unavailable`; a reset answers 200 `{"reset": true}`; the dry run relies on a transaction rollback, so the database must be journaled (the default).

The order of checks for a non-dry run: fault `fail_before_accept`; request validity (including `patient_mismatch` and `payload_digest_mismatch`); a committed receipt for this key (return it, 200, before any version check, so a retry of an identical committed operation never looks like a version conflict); key reuse with a different digest (409); encounter existence (422); `expected_version` (409); transition (422); then, in one transaction: update the encounter, append the event, increment the version, store the receipt, commit; then fault `commit_drop_response` (504) or the 201.

### 1.2 Read an encounter

`GET /wards/api/encounters/{encounter_id}`

```json
{
  "encounter_id": "ENC-1001",
  "patient_id": "MRN1001",
  "patient_id_authority": "HOSP",
  "state": "admitted",
  "ward": "WARD-C",
  "version": 3,
  "updated_at": "2026-10-15T09:45:02Z",
  "history": [
    {"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-15T09:00:00Z", "applied_at": "…", "operation_key": "…"},
    {"version_after": 2, "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-15T09:45:00Z", "applied_at": "…", "operation_key": "…"}
  ]
}
```

404 `{"error": "unknown_encounter"}` when the ward has never seen it. `state` is `admitted` or `discharged`. `history` is in application order, oldest first, and is immutable.

### 1.3 Read a receipt

`GET /wards/api/receipts/{operation_key}` (URL-encode the key)

```json
{
  "operation_key": "…",
  "encounter_id": "ENC-1001",
  "event": "transfer",
  "ward": "WARD-B",
  "event_time": "…",
  "applied_at": "…",
  "version_before": 1,
  "version_after": 2,
  "payload_digest": "sha256:…",
  "status": "committed"
}
```

404 `{"error": "no_receipt"}` when nothing was committed under that key. Absence of a receipt is the ward's statement that the operation was not committed under that key, within its retention (unbounded in the demo).

### 1.4 Transitions and versions

| From | `admit` | `transfer` | `discharge` | `update` |
|---|---|---|---|---|
| (unknown) | admitted, version 1 | invalid (`unknown_encounter`) | invalid | invalid |
| admitted | invalid (`invalid_transition`) | admitted, ward changes | discharged | admitted, no change except the version |
| discharged | invalid | invalid | invalid | invalid |

Every applied operation increments the version by one. A transfer to the ward the patient is already in is still an applied operation (version increments, event appended).

### 1.5 Faults, for the demos

`POST /wards/api/faults` `{"mode": "off" | "fail_before_accept" | "commit_drop_response" | "misleading_duplicate_error", "operation_key": "…"}`. With `operation_key` the fault applies to that key only; without it, to every operation until `off`. Returns 200 `{"mode": …, "operation_key": …}`. `GET /wards/api/faults` returns the current setting.

- `fail_before_accept`: 503 before any validation or write.
- `commit_drop_response`: the operation is committed, then the response is a 504 with no body.
- `misleading_duplicate_error`: with an `operation_key`, the ward answers 409 `{"error": "duplicate_message"}` for that key whatever the version, and writes nothing; without a key, it answers that way when `expected_version` mismatches, instead of `version_conflict`. (A buggy receiver that reports the wrong reason. Nothing else changes.)

### 1.6 Canonical payload and digest

The canonical payload is the JSON object with exactly these keys in this order, no whitespace, strings as given, null for absent `ward`: `operation_key`, `encounter_id`, `patient_id`, `patient_id_authority`, `event`, `ward`, `event_time`, `source_system`. `payload_digest` is `"sha256:"` followed by the lower-case hex SHA-256 of that UTF-8 string. `source_message_id`, `expected_version` and `dry_run` are not part of it, so a resend of the same business operation from a different message has the same digest.

### 1.7 Reset

`POST /wards/api/reset` clears encounters, events, receipts and faults. 403 `{"error": "not_a_demo_instance"}` unless the installer has marked the instance as a demo (`^Wards.Config("demo") = 1`). The web application's password authentication applies.

### 1.8 Capabilities (v1.4)

`GET /wards/api/capabilities` says what the ward guarantees, so that the gate's connector-capability check reads something real:

```json
{
  "conditional_writes": true,
  "receipts": true,
  "receipt_retention": "unbounded",
  "history": true,
  "idempotency": "by operation key and payload digest",
  "dry_run": true,
  "epoch": 7,
  "last_contract_check": {"at": "2026-10-15T14:00:00Z", "result": "17 of 17 passed"}
}
```

- `POST /wards/api/capabilities` `{"conditional_writes": false}` is the demo switch (demo instances only, like the reset): afterwards any operation that carries `expected_version` is refused with 422 `{"error": "unsupported_precondition"}`, and the read says `"conditional_writes": false`. `{"conditional_writes": true}` restores it; the reset restores it too.
- `epoch` is an integer that increments at every reset. It appears here, in every encounter read (`"epoch"` beside `"version"`) and in every receipt. An approval binds the epoch it was given, so an approval from before a reset cannot authorise a dispatch after it even when the version numbers happen to match.
- `last_contract_check` is whatever the ward recorded last (the HTTP check writes it); null when never run.
- `POST /wards/api/capabilities` also takes `last_contract_check` as `{"at": "<ISO 8601 UTC>", "result": "<text>"}`, both fields required (v1.5): the test tools write it after a contract check. Any other field is refused with 422 `{"error": "invalid_request"}`, and nothing changes when any part of a request is refused. On an instance that is not a demo the POST answers 403 `{"error": "not_a_demo_instance"}`.

### 1.9 Receipt lookup unavailable (v1.4)

Fault mode `receipt_lookup_unavailable`, with an `operation_key`: `GET /wards/api/receipts/{key}` answers 503 `{"error": "ward_unavailable"}` for that key while the commit, the encounter read and the history stand. It shows that the absence of a readable receipt is not evidence that nothing was committed: the gate's effect check answers unknown, and no write is dispatched.

### 1.10 Roles and credentials

The web application `/wards/api` requires password authentication and the role `Wards_API` (created by the ward installer; the demo users and the production's credentials get it). The production reaches it through an `EnsLib.HTTP.OutboundAdapter` with the Ens credentials entry `WardsAPI`.

## 2. The operation key and the HL7 mapping

An operation key identifies a **business operation**, not a message. The same transfer resent under a new message control id has the same key.

`<source_system>^<patient_id_authority>^<patient_id>^<encounter_id>^<event>^<event_time>`

From an HL7 v2.5.1 ADT message:

| Field | HL7 |
|---|---|
| `source_system` | MSH-3 (sending application) |
| `patient_id` and `patient_id_authority` | PID-3, first repetition: the ID and the assigning authority (`MRN1001^^^HOSP^MR` gives `MRN1001` and `HOSP`) |
| `encounter_id` | PV1-19 (visit number) |
| `event` | MSH-9.2: A01 → `admit`, A02 → `transfer`, A03 → `discharge`, A08 → `update` |
| `ward` | PV1-3.1 (assigned patient location, point of care) for A01 and A02; null otherwise |
| `event_time` | EVN-6 (event occurred) if present, else EVN-2 (recorded), as ISO 8601 UTC |
| `source_message_id` | MSH-10 |

Scenario S8's third message comes from a second source system, `BEDMGR` (MSH-3), for the same encounter (v1.5): its operation key starts `BEDMGR^HOSP^…`, so it is a different operation from the PAS messages even when it describes the same movement. Admit to Ward A applied; the 09:20 transfer to Ward B fails; the bed manager's own transfer to Ward C, also timed 09:20, applies. Neither event is later than the other, so supersession is unknown: nothing is resent.

The DTL that builds the ward operation lives in `Interlock.DTL.ADTToWard`. The same mapping, as an ObjectScript class method, is `Interlock.Util.OperationKey.FromHL7(message)` so the evidence collector and the fixtures agree.

## 3. HL7 fixtures

- HL7 v2.5.1, one message per file, segments separated by carriage returns (`\r`), files under `fixtures/<scenario>/`, named `<scenario>-<nn>-<event>.hl7` (for example `S1-02-A02.hl7`). UTF-8, ASCII content.
- MSH-3 `PAS` (S8's third message: `BEDMGR`, a bed management system; v1.5), MSH-4 `HOSP`, MSH-5 `WARDS`, MSH-6 `HOSP`, MSH-9 `ADT^A02^ADT_A02`, MSH-10 unique across all fixtures (`MSG` plus five digits), MSH-11 `P`, MSH-12 `2.5.1`.
- EVN-1 the trigger, EVN-2 the recorded time, EVN-6 the event time (both `YYYYMMDDHHMMSS`, interpreted as UTC).
- PID-3 `MRN1001^^^HOSP^MR`; PID-5 synthetic names (no real people); PID-7 a date of birth; PID-8 a sex code.
- PV1-2 `I`; PV1-3 `WARD-A^BAY1^01^HOSP` (point of care, room, bed, facility); PV1-19 `ENC-1001`; PV1-44 the admit time.
- Free text that must reach the agents as data (the injected instruction in S4) goes in an OBX segment after PV1, `OBX|1|TX|NOTE^Transfer note^L||<text>||||||F`, which the ADT_A02 structure allows. No NTE segments in A02.
- Every scenario's timeline is one patient and one encounter, except S9 (v1.5): its third message admits a second patient's encounter, `ENC-2009`, listed as `expected.other_encounter`, which the recovery must leave untouched. Admit to Ward A applied; the 09:20 transfer to Ward B fails; the same patient is admitted at 09:30 to Ward C under another visit number. That admission belongs to another encounter and supersedes nothing: the transfer is still due. Times are the same day, `2026-10-15`, 09:00 onwards.
- `fixtures/scenarios.json` lists the scenarios:

```json
[
  {
    "id": "S1",
    "title": "Stale transfer after a later transfer",
    "summary": "Admit to Ward A applied; the 09:20 transfer to Ward B fails before acceptance; the 09:45 transfer to Ward C applies. Resending the 09:20 message would move the patient backwards.",
    "steps": [
      {"file": "S1-01-A01.hl7"},
      {"fault": "fail_before_accept"},
      {"file": "S1-02-A02.hl7", "expect": "delivery_fails"},
      {"fault": "off"},
      {"file": "S1-03-A02.hl7"}
    ],
    "expected": {"disposition": "superseded", "write": false, "final_ward": "WARD-C"}
  }
]
```

Step kinds: `file` (drop the file into the ADT In folder; `expect` is `delivered` by default or `delivery_fails`), `fault` (section 1.5, with an optional `operation_key`), `wait` (`seconds`). The runner leaves at least two seconds between files so the production applies them in order. Two more (v1.4 and v1.5): `wait_for_state` (section 4.1), and `capabilities`, an object the runner posts to `/wards/api/capabilities` (section 1.8), as S10 does with `{"capabilities": {"conditional_writes": false}}`.

## 4. The scenario runner

`Interlock.Scenarios.Runner`, class methods marked `SqlProc` so the app and the scripts can call them through SQL:

- `List() As %String`: the scenarios as JSON (the `scenarios.json` content with the fixture files resolved).
- `Run(scenario As %String, mode As %String = "board") As %String`: resets the ward (section 1.7), sets the run mode for the case workflow (`board`, `single`, `rules`, by writing `^Interlock.Config("mode")`) and the running scenario (`^Interlock.Config("scenario")` = the scenario id, which the case intake stamps on the case, so that recorded agent runs replay by scenario on any instance), then executes the steps: faults through the ward API, files copied into the production's inbound folder (`^Interlock.Config("adtIn")`, set by `Interlock.Setup`), waits. Returns JSON `{"scenario": "S1", "started_at": "…", "files": [...]}`. It does not wait for the case; the production and the app do the rest.
- `Reset() As %String`: the ward reset, the inbound and archive folders emptied, `^Interlock.Config("mode")` back to `board`, `^Interlock.Config("scenario")` cleared, and `^Interlock.Config("resetAt")` set to the ISO UTC time of the reset. Encounter ids are fixed per scenario, so the evidence collector ignores message-store events older than `resetAt`; the ward's own history is per run already.
- The runner may call `Wards.Service` in process for the reset and the faults; the production always goes through HTTP.
- Settings the runner reads, all set by `Interlock.Setup`: `^Interlock.Config("fixtures")` (the fixtures directory), `("adtIn")`, `("adtArchive")`. The ADT In service takes `*.hl7` and archives what it has read.
- The run mode (`board`, `single`, `rules`) is the investigation mode. Whether agents run live, record or replay is the production's setting on the agent items, independent of it.

## 4.1 Scenario steps that wait (v1.4)

A step `{"wait_for_state": "awaiting_approval", "timeout": 120}` makes the runner wait until the newest case of the running scenario reaches that state (or the timeout passes, which the runner reports). The runner reads the case in the same namespace:

```sql
SELECT TOP 1 State FROM Interlock_Store."Case" WHERE Scenario = ? ORDER BY ID DESC
```

Scenario S7 (a later transfer arriving while the plan awaits approval) is written with it. The web app reads case state through the REST API instead (section 5).

## 4.2 Running a scenario from the API (v1.5)

`POST /api/interlock/scenarios/{id}/run` with `{"mode": "board" | "single" | "rules"}` answers 202 and the run record; `GET /api/interlock/scenarios` carries the current record as `run`. With the production's **Scenario Player** item enabled, the route writes a record in state `queued` and sends an `Interlock.Msg.ScenarioRun` through the `Interlock API` service to the player, which plays the steps in its own job (the same checks and reset as `Runner.Start`) and moves the record through `running` to `done` or `failed`; a run therefore never needs a new process, and it shows in the trace with the cases it causes. A second POST while a record is `queued` or `running` answers 409 `wrong_state`. Without the player the route calls `Runner.Start`, which uses a background job, or plays inline when none can start.

## 5. The REST API for the app

The API as built is `src/Interlock/API/Dispatch.cls` (its UrlMap lists the routes; sign-in through `POST /session` and the CSP session cookie; every change carries `X-Requested-With: Interlock`, the idempotent ones an `Idempotency-Key`; errors are JSON with `error` and `detail`). The web application's notes on using it are in `web/README.md`. Workflow tasks come back in camelCase with ISO 8601 UTC times (v1.5).

## 6. The scenario catalogue and the matcher (v1.6)

The catalogue is the knowledge base's core: every failure pattern Interlock knows, each with a preferred outcome and its
alternatives (`knowledge/catalogue/E<n>.md`). A deterministic matcher in the core reads each entry's front matter and
evaluates it against a case's evidence snapshot, with no model. The board, when it runs, chooses among an entry's outcomes
rather than inventing one.

### 6.1 The condition vocabulary

Every condition is computed by the core from the snapshot the evidence collector took (section 1 and the gate's checks),
so an entry's pattern can be checked by machine and the same values are shown to people. An entry lists only the
conditions that matter; an unlisted condition is a wildcard. A listed condition takes one value or a list of allowed values.

| Condition | Values | Computed from |
| --- | --- | --- |
| `delivery` | `failed`, `rejected`, `uncertain` | the case's failure kind (1.1: 503 and connection failures are `failed`; 409 and 422 are `rejected`; 504 is `uncertain`) |
| `receiver_answer` | `unavailable`, `timeout`, `duplicate`, `version_conflict`, `refused`, `none` | the error item's reason code |
| `receipt` | `present`, `absent`, `unreadable` | the receipt lookup: 200, 404, anything else (1.9) |
| `later_applied` | `none`, `transfer`, `discharge`, `update` | among the applied events for the encounter whose event time is later than the failed operation's (the ward history and the timeline), by precedence: `discharge` if any, else `transfer` if any, else `update` (an A08), else `none` |
| `encounter_state` | `admitted`, `discharged`, `unknown` | the ward's state; `unknown` when the encounter can't be read or is unknown to the ward |
| `transition` | `allowed`, `invalid`, `unknown` | the failed event from the encounter's current state (1.4): a transfer after a discharge is `invalid` |
| `patient_match` | `yes`, `no`, `unknown` | the message's PID-3 against the ward's patient for the encounter |
| `simultaneous_sources` | `yes`, `no` | an applied event for the encounter from another source system with the same event time as the failed operation (S8) |
| `conditional_writes` | `yes`, `no`, `unknown` | the route's capability profile (1.8) |
| `free_text` | `yes`, `no` | the message carries free text (an OBX note or an NTE) |
| `chain` | `single`, `ordered`, `interleaved` | section 7; a case outside an incident is `single` |

### 6.2 An entry's front matter

```yaml
id: E2
version: 1
title: Not delivered, still current
scenarios: [S2, S9]
pattern:
  delivery: [failed, rejected]
  receipt: absent
  later_applied: none
  transition: allowed
  patient_match: yes
  chain: single
decides: policy
preferred:
  outcome: resend
  why: The movement never reached the receiver and nothing later changed the encounter.
alternatives: []
checks: [ordering, effect, state_transition, identity, capability]
```

- `decides` says who settles a case that matches this entry alone: `policy` (the site's policy path, 6.4), `board`
  (the board chooses among the outcomes), `person` (always escalated, with the entry named).
- `outcome` is one of `resend` (the case's own operation, conditional on the receiver's version), `resend_chain` (every
  item of an ordered chain, in event order), `resend_latest` (the chain's latest item only; the earlier ones are
  superseded), `reconcile`, `none`, `escalate`, `resend_unconditional` (never automatic; needs the site flag
  `unconditional_resend: with_approval`), `correct_history` (not implemented: always escalated with the steps named).
- An alternative has `outcome`, `why` and `when`: `always` for a choice left to the board, or a site profile condition
  `<flag>: <value>` such as `history_policy: correct` or `unconditional_resend: with_approval`. The value may be the
  symbol `other_source`, which stands for the other source system of the simultaneous event the matcher found
  (`facts.other_source`), so `authoritative_source: other_source` holds when the site names that system as
  authoritative. Every alternative is decided by the board or a person, never automatically.
- `checks` names the gate checks that must pass for the preferred outcome; the gate runs them all anyway, so this is
  documentation for the reader and the board.
- The prose after the front matter is for the board: what the pattern means, how to tell it apart, what to cite.

### 6.3 Matching and the investigation modes

The matcher runs after the evidence is collected, before any agent, in every mode: its result (the conditions, the
facts, the matches) is part of the snapshot summary, so the board reads it and the gate checks the plan against it.
The investigation mode decides who settles the case:
- `policy` (the site's default once a catalogue is installed): the rules below;
- `board`: the board always runs, the match in its evidence; the comparison's board column keeps its meaning;
- `single`: the single investigator always runs;
- `rules`: no agents and no catalogue path: a plain resend for the gate to judge.

In `policy` mode the matcher's decision is:
- **One match, `decides: policy`:** the case takes the site's policy path (6.4) with the preferred outcome. No board.
- **One match, `decides: board`, or several matches:** the board runs; the coordinator's plan names `catalogue_entry`
  and `outcome` (`preferred` or `alternative:<n>`) with `why`.
- **One match, `decides: person`:** the case is escalated at once, naming the entry; the board does not run.
- **No match:** the board runs so that the person gets an analysis, and the gate marks the plan `NEW_PATTERN`; the case
  is escalated and flagged as a candidate entry for a reviewer.
- The matches, with every condition's observed value, are stored on the case (`catalogue` in the snapshot summary) and
  shown in the app.

### 6.4 The site profile and the policy path

The questionnaire's answers are the site profile (`knowledge/site/profile.json`, versioned; defaults shipped). The core
reads it through `Interlock.Store.SiteProfile`.

```json
{
  "version": 1,
  "receivers": [
    {"name": "Ward Out", "system": "the ward bed-management system", "tier": 2,
     "applies": "arrival_order", "resend_timestamp": "original", "cancels": false}
  ],
  "history_policy": "current",
  "authoritative_source": "",
  "unconditional_resend": "forbidden",
  "policy": {
    "1": {"single": "automatic", "ordered": "automatic", "interleaved": "board"},
    "2": {"single": "automatic", "ordered": "approval", "interleaved": "board"},
    "3": {"single": "approval", "ordered": "per_chain", "interleaved": "board"}
  },
  "approvers": {"role": "Interlock Approvers", "escalation": "the integration team's on-call"},
  "incident": {"threshold": 5, "window_minutes": 10, "quiet_seconds": 60}
}
```

- A tier is the receiver's; a policy is read by tier and chain kind.
- `automatic`: the case (or the chain) is released with no Workflow task. It is still gated at the proposal and at the
  dispatch, rehearsed and verified, exactly as an approved case. The case records an approval whose approver is
  `policy`, with the profile's version, the tier, the chain kind and the entry, so the authorization check and the
  closure read as for a person's approval, and the app shows "automatic by site policy".
- `approval`: one Workflow task for the case, or for the whole incident (section 7).
- `per_chain`: one Workflow task per chain of the incident.
- `board` for a chain kind means the board runs whatever the match says.
- A tier 3 receiver never takes `automatic` unless the profile says so explicitly; the shipped default does not.

### 6.5 The gate's catalogue checks

A new check, `catalogue`, with these reason codes (in `knowledge/block-reasons.json`):
- `ENTRY_UNKNOWN`: the plan names an entry that is not in the catalogue at the plan's catalogue version (block);
- `PATTERN_NOT_MATCHED`: the entry's pattern does not hold on the snapshot (block);
- `OUTCOME_NOT_ALLOWED`: the chosen alternative's `when` does not hold for this site (block);
- `NEW_PATTERN`: no entry matches (block; the case escalates as a candidate entry);
- `POLICY_REQUIRES_APPROVAL`: an automatic release where the profile requires an approval (block; an internal guard).
The plan's `catalogue_entry` and `outcome` are bound by the approval's digest like every other field of the plan.

### 6.6 The board's tool

`search_catalogue` is a knowledge-base tool over `knowledge/catalogue/`, attached to every member, so that the board
cites entries by id. The coordinator's instructions say the plan names the entry and the outcome.

## 7. Incidents: many failures to one receiver (v1.6)

### 7.1 Detection and grouping

- The connector counts delivery failures and refusals (not uncertain outcomes) per receiver in a sliding window. At the
  profile's threshold (default 5 within 10 minutes) an incident opens for that receiver.
- A case opened while an incident is open for its receiver joins it (case state `grouped`) instead of starting its own
  investigation. The incident's intake closes after `quiet_seconds` with no new failure.
- Chains form per encounter (PV1-19), oldest event time first. Chains of one patient (PID-3) are linked for the page; the
  link imposes no order across encounters.
- A chain's kind: `single` (one failure, nothing later applied), `ordered` (several failures, no successful delivery for
  the encounter between them), `interleaved` (successful deliveries between the failures, or a later applied event).
- Each case in a chain gets its own evidence snapshot as today. The matcher runs per case with `chain` set.

### 7.2 Classification and the plan

- A chain whose cases all match one entry with `decides: policy` is a policy chain: `single` and `ordered` chains with
  `resend` or `resend_chain` take the policy path; `none` and `reconcile` outcomes close their cases without a write.
- Any other chain is a board chain: the board runs for each of its cases, as today, with `chain` in the evidence.
- The incident's plan lists every chain with its kind, entry, outcome and items in order; its digest covers the chains'
  operation keys in order, each item's payload digest, the first item's expected version per chain, the receiver's epoch,
  the catalogue version, the site profile version and the gate's policy version.

### 7.3 Approval

- The site's policy per tier and chain kind decides: `automatic` (no task), `approval` (one Workflow task for the
  incident's policy chains), `per_chain` (one task per chain). Board chains are approved as single cases are today.
- The task says what is bound and what is not: "resend these, in this order; each one is rehearsed, gated and verified
  just before it goes; the chain stops at the first surprise, and the rest comes back to you".
- The incident's approval binds the plan's digest and the rule for later items: each item after the first goes at exactly
  the version the previous item's verified receipt reports.

### 7.4 Release

- The incident releases chains one at a time (or side by side, when the profile allows), and within a chain one item at
  a time: it tells the case the version to expect, the case runs its own dispatch stage (the preflight read, the
  dispatch gate, the rehearsal, the write, the verification) and reports back.
- The dispatch gate's concurrency check compares the receiver's version with the expected one; any other write in
  between stops the chain: the remaining items go to a person with the reason, and the incident's record says which
  item stopped and why.
- Every item keeps its own trace, approval record and closure; the incident's record lists each chain's outcome:
  `resolved`, `stopped` (with the item), `escalated` (a board chain or a no-match).

### 7.5 The API

- `GET /incidents`: id, receiver, openedAt, state (`open`, `classified`, `awaiting_approval`, `releasing`, `closed`),
  counts of chains by kind and outcome.
- `GET /incidents/{id}`: the chains with their items (case ids, position, kind, entry, outcome, the expected version
  rule), the plan's digest, the approvals, progress.
- `POST /incidents/{id}/approvals` with `planDigest`, `action` (`approve` or `reject`), `comment`; `Idempotency-Key`;
  409 `plan_changed` when the digest moved. `POST /incidents/{id}/chains/{n}/approvals` for `per_chain`.
- `GET /incidents/{id}/events`.
- A case carries `incidentId`, `chainId`, `chainPosition` and `chainKind`; a case's closure says whether it was
  released automatically, by an approval, or stopped.
- `GET /site-profile` (any signed-in user) returns the current profile with its version; `PUT /site-profile`
  (`Interlock_Approve`, `X-Requested-With`) replaces it with the body, which must have the shape of 6.4, and answers the
  new version; the questionnaire page writes it. Every change is recorded as a case-independent event with the user.

### 7.6 Scenario S11, an outage burst

Twelve failures for six patients to the ward, in one burst (the fault `fail_before_accept` on, the files, the fault off):
P1 one failed A02 (E2, single); P2 A02 and A03 failed (E4, ordered); P3 A02 failed, A08 applied, a later A02 applied, A03
failed (E5, interleaved, board); P4 A02 failed, then a later A02 applied (E1, superseded); P5 A02 failed after an applied
A03 (E6); P6 a failed A01 (E2, single, admit). Expected: the policy chains resolved without the board at tier 2
(automatic single, approval ordered), P3 by the board, and the final ward state per patient listed in
`fixtures/scenarios.json`. Its recordings are hand-written until a key is available.

## Repository layout

The core IPM module is the repository root (`module.xml`, sources under `src/`): it compiles on any 2026.2 Community image and replays recorded runs. The aihub module is `aihub/` (`aihub/module.xml`, sources under `aihub/src/`): the live runner, the agents, tools, schemas, policies and knowledge bases, which need the `%AI` package. Both modules contribute classes to the `Interlock` package; nothing under `src/` may reference `%AI`.

## Changes

- v1.6, 17 Oct 2026: the scenario catalogue and the deterministic matcher, the condition vocabulary, the site profile and the policy path (automatic, approval, per chain), the gate's catalogue checks, the board's `search_catalogue` tool (6); incidents: detection, chains and their kinds, the plan and its approval binding the sequence rule, the ordered release through each case's own dispatch, the API, scenario S11 (7). From the owner's decisions of 17 Oct, all taken.
- v1.5, 16 Oct 2026: rehearsal responses carry `encounter_before` and `epoch` (1.1); `POST /capabilities` takes `last_contract_check` (1.8); S8's second source system `BEDMGR` (2, 3); S9's second encounter `ENC-2009` (3); the `capabilities` step kind (3); the scenario player and the run states (4.2); section 5 points at the API as built. Points (a) to (e) are House's, accepted on 15 Oct.
- v1.4, 15 Oct 2026: the capabilities read and the demo switch, the epoch, the receipt-lookup fault (1.8, 1.9); scenario steps that wait for a case state (4.1). From House's triage of the owner's feature documents (T9, T10, A1, A2, A5).
- v1.3, 15 Oct 2026: `misleading_duplicate_error` with an `operation_key` (1.5); `resetAt`, the runner's settings and the mode semantics (section 4), from the scenario work.
- v1.2, 15 Oct 2026: the ward decisions of 15 Oct recorded (section 1.1), with `patient_mismatch` and `payload_digest_mismatch` as their own codes.
- v1.1, 15 Oct 2026: the runner sets `^Interlock.Config("scenario")` (section 4); the repository layout.
- v1, 15 Oct 2026: first version (sections 1 to 4).
