# Contracts between Shutter's parts

Version 1.16, 20 October 2026. These are the interfaces the parts of Shutter are built against. Change the version and the date when something here changes, and say what changed at the end.

## 1. The downstream system's API

The downstream system (`Downstream.*`), a demo bed-management system, stands in for a hospital's bed-management system. It is the only receiver the production delivers to, for normal traffic, rehearsals and recovery alike. Base path `/downstream/api`, JSON in and out, IRIS password authentication.

### 1.1 Apply an operation

`POST /downstream/api/operations`

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
- A receiver that declares `cancels: true` in its site profile entry (6.4) also takes `cancel_admit`, `cancel_transfer` and `cancel_discharge`, each the reversal of the named event on the encounter; one that declares `merges: true` takes `merge`, with `prior_patient_id`, `prior_patient_id_authority` and `prior_encounter_id` beside the fields above (v1.14). The demo receiver declares neither and refuses them with 422 `invalid_request`; Shutter never sends them to it (section 2).
- `event_time` is the source event's time (see section 2), in ISO 8601 UTC with a `Z`. The downstream system stores it but **does not order by it**: operations are applied in arrival order. That is the receiver contract, and it is why a stale transfer applied late moves a patient backwards.
- `expected_version` is optional. When present, the operation applies only if the encounter's current version equals it. Normal traffic omits it; recovery always sends it.
- `payload_digest` is the sender's SHA-256 of the canonical payload (section 1.6). The downstream system computes its own and compares them when an operation key is reused.
- `dry_run: true` runs the whole validation and the write inside a transaction that is always rolled back, and reports what would have happened. Nothing is committed, no receipt is stored, no event is appended.
- A rehearsal's response also carries what it was checked against (v1.5): `encounter_before`, the encounter as the downstream system held it before the dry run (null when the downstream system has never seen it), `encounter_after` when it would apply, and `epoch`. The case workflow takes the receiver version an approval binds from `encounter_before.version`, never from `encounter_after`.

Responses:

| Status | Body | When |
|---|---|---|
| 201 | `{"applied": true, "receipt": {…}, "encounter": {…}}` | Applied and committed |
| 200 | `{"applied": false, "reason": "already_committed", "receipt": {…}, "encounter": {…}}` | The same operation key was committed before, with the same payload digest |
| 200 | `{"applied": false, "rehearsal": true, "would_apply": true, "encounter_after": {…}}` or `{"applied": false, "rehearsal": true, "would_apply": false, "reason": "<one of the error codes below>", …}` | `dry_run` |
| 409 | `{"error": "version_conflict", "expected_version": 1, "current_version": 2}` | `expected_version` present and different from the current version |
| 409 | `{"error": "key_reused_with_different_payload", "operation_key": "…"}` | The key was committed with another payload digest |
| 422 | `{"error": "invalid_transition", "state": "discharged", "event": "transfer"}` | The transition is not allowed (section 1.4) |
| 422 | `{"error": "unknown_encounter", "encounter_id": "…"}` | `transfer`, `discharge` or `update` for an encounter the downstream system has never admitted |
| 422 | `{"error": "patient_mismatch", "encounter_id": "…"}` | The encounter exists for another patient (identity never silently changes) |
| 422 | `{"error": "payload_digest_mismatch"}` | The sender's `payload_digest` differs from the downstream system's own computation |
| 422 | `{"error": "invalid_request", "detail": "…"}` | Missing or malformed fields |
| 503 | `{"error": "ward_unavailable"}` | Fault `fail_before_accept` is on (section 1.5); nothing was validated or written |
| 504 | empty body | Fault `commit_drop_response` is on: the operation **was committed** and the receipt stored, then the response was lost |

Decided with the downstream system (15 Oct): faults apply to real operations only, never to a dry run; a discharge sets `ward` to null; for an `admit`, `expected_version` 0 means "not yet seen"; the per-encounter lock waits 10 s and then answers 503 `ward_unavailable`; a reset answers 200 `{"reset": true}`; the dry run relies on a transaction rollback, so the database must be journaled (the default).

The order of checks for a non-dry run: fault `fail_before_accept`; request validity (including `patient_mismatch` and `payload_digest_mismatch`); a committed receipt for this key (return it, 200, before any version check, so a retry of an identical committed operation never looks like a version conflict); key reuse with a different digest (409); encounter existence (422); `expected_version` (409); transition (422); then, in one transaction: update the encounter, append the event, increment the version, store the receipt, commit; then fault `commit_drop_response` (504) or the 201.

### 1.2 Read an encounter

`GET /downstream/api/encounters/{encounter_id}`

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

404 `{"error": "unknown_encounter"}` when the downstream system has never seen it. `state` is `admitted` or `discharged`. `history` is in application order, oldest first, and is immutable.

### 1.3 Read a receipt

`GET /downstream/api/receipts/{operation_key}` (URL-encode the key)

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

404 `{"error": "no_receipt"}` when nothing was committed under that key. Absence of a receipt is the downstream system's statement that the operation was not committed under that key, within its retention (unbounded in the demo).

### 1.4 Transitions and versions

| From | `admit` | `transfer` | `discharge` | `update` |
|---|---|---|---|---|
| (unknown) | admitted, version 1 | invalid (`unknown_encounter`) | invalid | invalid |
| admitted | invalid (`invalid_transition`) | admitted, ward changes | discharged | admitted, no change except the version |
| discharged | invalid | invalid | invalid | invalid |

For a receiver that takes them (1.1, v1.14): `cancel_admit` and `cancel_transfer` from `admitted`, `cancel_discharge` from `discharged`, `merge` from any state the receiver knows; the gate and the matcher judge a write of them by the same rule, and the demo receiver takes none. Every applied operation increments the version by one. A transfer to the ward the patient is already in is still an applied operation (version increments, event appended).

### 1.5 Faults, for the demos

`POST /downstream/api/faults` `{"mode": "off" | "fail_before_accept" | "commit_drop_response" | "misleading_duplicate_error", "operation_key": "…"}`. With `operation_key` the fault applies to that key only; without it, to every operation until `off`. Returns 200 `{"mode": …, "operation_key": …}`. `GET /downstream/api/faults` returns the current setting.

- `fail_before_accept`: 503 before any validation or write.
- `commit_drop_response`: the operation is committed, then the response is a 504 with no body.
- `misleading_duplicate_error`: with an `operation_key`, the downstream system answers 409 `{"error": "duplicate_message"}` for that key whatever the version, and writes nothing; without a key, it answers that way when `expected_version` mismatches, instead of `version_conflict`. (A buggy receiver that reports the wrong reason. Nothing else changes.)

### 1.6 Canonical payload and digest

The canonical payload is the JSON object with exactly these keys in this order, no whitespace, strings as given, null for absent `ward`: `operation_key`, `encounter_id`, `patient_id`, `patient_id_authority`, `event`, `ward`, `event_time`, `source_system`. `payload_digest` is `"sha256:"` followed by the lower-case hex SHA-256 of that UTF-8 string. `source_message_id`, `expected_version` and `dry_run` are not part of it, so a resend of the same business operation from a different message has the same digest.

### 1.7 Reset

`POST /downstream/api/reset` clears encounters, events, receipts and faults. 403 `{"error": "not_a_demo_instance"}` unless the installer has marked the instance as a demo (`^Downstream.Config("demo") = 1`). The web application's password authentication applies.

### 1.8 Capabilities (v1.4)

`GET /downstream/api/capabilities` says what the downstream system guarantees, so that the gate's connector-capability check reads something real:

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

- `POST /downstream/api/capabilities` `{"conditional_writes": false}` is the demo switch (demo instances only, like the reset): afterwards any operation that carries `expected_version` is refused with 422 `{"error": "unsupported_precondition"}`, and the read says `"conditional_writes": false`. `{"conditional_writes": true}` restores it; the reset restores it too.
- `epoch` is an integer that increments at every reset. It appears here, in every encounter read (`"epoch"` beside `"version"`) and in every receipt. An approval binds the epoch it was given, so an approval from before a reset cannot authorise a dispatch after it even when the version numbers happen to match.
- `last_contract_check` is whatever the downstream system recorded last (the HTTP check writes it); null when never run.
- `POST /downstream/api/capabilities` also takes `last_contract_check` as `{"at": "<ISO 8601 UTC>", "result": "<text>"}`, both fields required (v1.5): the test tools write it after a contract check. Any other field is refused with 422 `{"error": "invalid_request"}`, and nothing changes when any part of a request is refused. On an instance that is not a demo the POST answers 403 `{"error": "not_a_demo_instance"}`.

### 1.9 Receipt lookup unavailable (v1.4)

Fault mode `receipt_lookup_unavailable`, with an `operation_key`: `GET /downstream/api/receipts/{key}` answers 503 `{"error": "ward_unavailable"}` for that key while the commit, the encounter read and the history stand. It shows that the absence of a readable receipt is not evidence that nothing was committed: the gate's effect check answers unknown, and no write is dispatched.

### 1.10 Roles and credentials

The web application `/downstream/api` requires password authentication and the role `Downstream_API` (created by the downstream system's installer; the demo users and the production's credentials get it). The production reaches it through an `EnsLib.HTTP.OutboundAdapter` with the Ens credentials entry `DownstreamAPI`.

## 2. The operation key and the HL7 mapping

An operation key identifies a **business operation**, not a message. The same transfer resent under a new message control id has the same key.

`<source_system>^<patient_id_authority>^<patient_id>^<encounter_id>^<event>^<event_time>`

From an HL7 v2 ADT message (2.3.1, 2.4 or 2.5.1: the fields sit at the same positions, and the route's schema category decides the parse, see the version note below):

| Field | HL7 |
|---|---|
| `source_system` | MSH-3 (sending application) |
| `patient_id` and `patient_id_authority` | PID-3, the repetition typed MR (PID-3.5), else the first: the ID and the assigning authority (`MRN1001^^^HOSP^MR` gives `MRN1001` and `HOSP`) |
| `encounter_id` | PV1-19 (visit number); required for the delivered events; for the indexed events and a merge, the literal `-` when absent, never empty (v1.14) |
| `event` | MSH-9.2, by the trigger table below (v1.14): A01 `admit`, A02 `transfer`, A03 `discharge`, A04 `register`, A05 `preadmit`, A06 and A07 `update`, A08 `update`, A11 `cancel_admit`, A12 `cancel_transfer`, A13 `cancel_discharge`, A28 `person_add`, A31 `person_update`, A40 `merge`; anything else does not map (an `unmappable` case) |
| `ward` | PV1-3.1 (assigned patient location, point of care) for `admit` and `transfer`; null otherwise |
| `prior_patient_id`, `prior_patient_id_authority`, `prior_encounter_id`, `merge_groups` | a merge only (v1.14): MRG-1 (the repetition typed MR, else the first), MRG-5, and the number of MRG segments; carried on the case and, for a delivered merge, in the request body outside the payload digest (1.6); a message with several PATIENT groups is one merge case whose evidence lists every group |
| `event_time` | EVN-6 (event occurred) if present, else EVN-2 (recorded), as ISO 8601 UTC |
| `source_message_id` | MSH-10 |

Scenario S8's third message comes from a second source system, `BEDMGR` (MSH-3), for the same encounter (v1.5): its operation key starts `BEDMGR^HOSP^…`, so it is a different operation from the PAS messages even when it describes the same movement. Admit to Ward A applied; the 09:20 transfer to Ward B fails; the bed manager's own transfer to Ward C, also timed 09:20, applies. Neither event is later than the other, so supersession is unknown: nothing is resent.

**The trigger table and what is delivered** (v1.14). `Shutter.Util.OperationKey.DeliveryOf(event)` classes every event word: `deliver` (`admit`, `transfer`, `discharge`, `update`) goes to the receiver as before; `index` (`register`, `preadmit`, `person_add`, `person_update`) is recorded by the HL7 index with its event word and never delivered, with no case (an A04 is `register` unless PV1-2 is `I` and PV1-3.1 is present, when it is an `admit`); `cancel` is delivered only to a receiver whose entry says `cancels: true`; `merge` only when the site profile says `merges: allowed` and the receiver's entry says `merges: true`. A cancel or a merge that is not delivered opens a case of kind `withheld` with `FailureReasonCode` `cancel_unsupported` or `merge`; the gate blocks every plan on it (`CANCEL_UNSUPPORTED`, `MERGE_WITHHELD`, 6.5) and the case goes to a person (E15, E14). The fields are read wherever the message structure puts the segment (a merge's PID and PV1 sit in the PATIENT group of ADT_A39): `OperationKey.Value(message, segment, path)`.

**The schema category and the version note** (v1.14). Each HL7 service parses with its own `MessageSchemaCategory` (a category per message type is also an IRIS setting); IRIS resolves the structure from MSH-9.1 and 9.2 under that category and reads neither MSH-9.3 nor MSH-12 for it. The fields above sit at the same positions in 2.3.1, 2.4 and 2.5.1. The evidence's validation item records `message_version` (MSH-12.1), `route_category` (the message's `DocTypeCategory`), `route_standard` (the category's standard ancestor, by `Base` through `EnsLib.HL7.Schema:TypeCategories`) and `version_agrees`, with a `version_note` when they differ ("The message says HL7 2.4; the route parses it as 2.5.1"); it is a note, never a failure, and the conformance review cites it.

The business process that builds the downstream operation and delivers it is `Shutter.Process.ADTToWard`; the mapping it uses is the class method `Shutter.Util.OperationKey.FromHL7(message)`, shared with the evidence collector, the index and the fixtures. The same mapping, as an ObjectScript class method, is `Shutter.Util.OperationKey.FromHL7(message)` so the evidence collector and the fixtures agree.

## 3. HL7 fixtures

- HL7 v2.5.1 unless the scenario says otherwise (v1.14: S17 is 2.4 and S18 is 2.3.1, played through the 2.5.1 route), one message per file, segments separated by carriage returns (`\r`), files under `fixtures/<scenario>/`, named `<scenario>-<nn>-<event>.hl7` (for example `S1-02-A02.hl7`). UTF-8, ASCII content.
- MSH-3 `PAS` (S8's third message: `BEDMGR`, a bed management system; v1.5), MSH-4 `HOSP`, MSH-5 `DOWNSTREAM`, MSH-6 `HOSP`, MSH-9 `ADT^A02^ADT_A02` (MSH-9.3 the structure name of the message's version, from `generate.py`'s table; IRIS does not read it), MSH-10 unique across all fixtures (`MSG` plus five digits), MSH-11 `P`, MSH-12 the scenario's version, `2.5.1` by default.
- EVN-1 the trigger, EVN-2 the recorded time, EVN-6 the event time (both `YYYYMMDDHHMMSS`; a value with an offset is shifted to UTC, one without is read in the site profile's `feed.time_zone`, v1.11).
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

Step kinds: `file` (drop the file into the ADT In folder; `expect` is `delivered` by default or `delivery_fails`; with `"route": "hospital"` (v1.16) the file goes into the demo hospital's inbound folder instead, so the failure happens in `Hospital.Production` and reaches Shutter through its forwarder, as S19's does), `fault` (section 1.5, with an optional `operation_key`), `wait` (`seconds`). The runner leaves at least two seconds between files so the production applies them in order. Two more (v1.4 and v1.5): `wait_for_state` (section 4.1), and `capabilities`, an object the runner posts to `/downstream/api/capabilities` (section 1.8), as S10 does with `{"capabilities": {"conditional_writes": false}}`. Besides the outcome, `expected` may name `modes` (the run modes the scenario is defined for; the others are skipped) and `source` (v1.16: `namespace`, `production` and `route` a forwarded case must name, section 11).

## 4. The scenario runner

`Shutter.Scenarios.Runner`, class methods marked `SqlProc` so the app and the scripts can call them through SQL:

- `List() As %String`: the scenarios as JSON (the `scenarios.json` content with the fixture files resolved).
- `Run(scenario As %String, mode As %String = "board") As %String`: resets the downstream system (section 1.7), sets the run mode for the case workflow (`board`, `single`, `rules` or `policy`, by writing `^Shutter.Config("mode")`) and the running scenario (`^Shutter.Config("scenario")` = the scenario id, which the case intake stamps on the case, so that recorded agent runs replay by scenario on any instance), then executes the steps: faults through the downstream API, files copied into the production's inbound folder (`^Shutter.Config("adtIn")`, set by `Shutter.Setup`), waits. Returns JSON `{"scenario": "S1", "started_at": "…", "files": [...]}`. It does not wait for the case; the production and the app do the rest.
- `Reset() As %String`: the downstream system's reset, the inbound and archive folders emptied (the demo hospital's too, when it is installed), `^Shutter.Config("mode")` back to `board`, `^Shutter.Config("scenario")` cleared, and `^Shutter.Config("resetAt")` set to the ISO UTC time of the reset. Encounter ids are fixed per scenario, so the evidence collector ignores message-store events older than `resetAt`; the downstream system's own history is per run already.
- The runner may call `Downstream.Service` in process for the reset and the faults; the production always goes through HTTP.
- Settings the runner reads, set by `Shutter.Setup`: `^Shutter.Config("fixtures")` (the fixtures directory), `("adtIn")`, `("adtArchive")`; and, set by `Hospital.Setup` when the demo hospital is installed, `("hospitalIn")` and `("hospitalArchive")`. The ADT In service and the hospital's PAS In take `*.hl7` and archive what they have read.
- The run mode (`board`, `single`, `rules`) is the investigation mode. Whether agents run live, record or replay is the production's setting on the agent items, independent of it.

## 4.1 Scenario steps that wait (v1.4)

A step `{"wait_for_state": "awaiting_approval", "timeout": 120}` makes the runner wait until the newest case of the running scenario reaches that state (or the timeout passes, which the runner reports). The runner reads the case in the same namespace:

```sql
SELECT TOP 1 State FROM Shutter_Store."Case" WHERE Scenario = ? ORDER BY ID DESC
```

Scenario S7 (a later transfer arriving while the plan awaits approval) is written with it. The web app reads case state through the REST API instead (section 5).

## 4.2 Running a scenario from the API (v1.5)

`POST /api/shutter/scenarios/{id}/run` with `{"mode": "board" | "single" | "rules" | "policy"}` (default `board`; 400 `bad_request` for any other value) answers 202 and the run record; `GET /api/shutter/scenarios` carries the current record as `run`. With the production's **Scenario Player** item enabled, the route writes a record in state `queued` and sends an `Shutter.Msg.ScenarioRun` through the `Shutter API` service to the player, which plays the steps in its own job (the same checks and reset as `Runner.Start`) and moves the record through `running` to `done` or `failed`; a run therefore never needs a new process, and it shows in the trace with the cases it causes. A second POST while a record is `queued` or `running` answers 409 `wrong_state`. Without the player the route calls `Runner.Start`, which uses a background job, or plays inline when none can start.

## 5. The REST API for the app

The API as built is `src/Shutter/API/Dispatch.cls` (its UrlMap lists the routes; sign-in through `POST /session` and the CSP session cookie; every change carries `X-Requested-With: Shutter`, the idempotent ones an `Idempotency-Key`; errors are JSON with `error` and `detail`). The web application's notes on using it are in `web/README.md`. Workflow tasks come back in camelCase with ISO 8601 UTC times (v1.5).

`POST /cases/{id}/close` with `{reason}` (v1.14; `Shutter_Operate`, `X-Requested-With`, an `Idempotency-Key`) answers 202 `{caseId, state: "closing", requestedBy, reason}` and sends `Shutter.Msg.CaseClose` to the Case Workflow item: the case resolves with disposition `handled_by_hand`, its state event names the reason and the latest escalation, the current approval is revoked and an open approval task is cancelled; 400 `bad_request` when the body is not a JSON object or `reason` is empty, 404 `not_found`, 409 `wrong_state` unless the case is escalated, blocked or failed, and 409 `stale_version` (with `currentVersion`) when the body's optional `expectedVersion` is not the case's version. A draft or queued escalation email of the case is cancelled, so the team is not asked to correct a case already handled. It is how a case the team corrected by hand (a withheld merge or cancel, an escalation the PAS team acted on) is closed; `reinvestigate` stays for a correction the receiver's state can prove.

## 6. The scenario catalogue and the matcher (v1.6)

The catalogue is the knowledge base's core: every failure pattern Shutter knows, each with a preferred outcome and its
alternatives (`knowledge/catalogue/E<n>.md`). A deterministic matcher in the core reads each entry's front matter and
evaluates it against a case's evidence snapshot, with no model. The board, when it runs, chooses among an entry's outcomes
rather than inventing one.

### 6.1 The condition vocabulary

Every condition is computed by the core from the snapshot the evidence collector took (section 1 and the gate's checks),
so an entry's pattern can be checked by machine and the same values are shown to people. An entry lists only the
conditions that matter; an unlisted condition is a wildcard. A listed condition takes one value or a list of allowed values.

| Condition | Values | Computed from |
| --- | --- | --- |
| `delivery` | `failed`, `rejected`, `uncertain`, `unmappable`, `withheld` | the case's failure kind (1.1: 503 and connection failures are `failed`; 409 and 422 are `rejected`; 504 is `uncertain`; a message Shutter could not map to an operation is `unmappable`, v1.9); a merge or a cancel the feed withheld under the site profile or the receiver's entry is `withheld` (v1.14, section 2) |
| `receiver_answer` | `unavailable`, `timeout`, `duplicate`, `version_conflict`, `refused`, `none` | the error item's reason code, else its HTTP status (504 `timeout`, 409 and 422 `refused`, 503 `unavailable`); an uncertain delivery with no code reads `timeout` |
| `event` | `admit`, `transfer`, `discharge`, `update`, `merge`, `cancel`, `other` | the case's event word (v1.14): the three cancel words fold to `cancel`; an unmapped trigger is `other` (no case carries `register`: a registration is indexed only, or is an `admit`). A withheld case reads `delivery: withheld` and `receiver_answer: none` (no receiver was asked) |
| `receipt` | `present`, `absent`, `unreadable`, `none` | the receipt lookup: 200, 404, anything else (1.9); `none` when the receiver has no receipt endpoint (6.4), which is a fact about the receiver, not a failed lookup |
| `later_applied` | `none`, `cancelled`, `merge`, `transfer`, `discharge`, `admit`, `update` | among the applied events for the encounter whose event time is later than the failed operation's (the downstream system's history and the timeline), by precedence: `cancelled` when a `cancel_*` was applied at or after the failed event's time (v1.14: a cancel carries the time of the event it reverses, and the case's own operation never counts), else `merge` when a merge was applied later, else `discharge` if any was applied later, else `transfer`, else `admit` (a later admission, v1.11), else `update` (an A08), else `none`. Since v1.16 a later transfer the feed sent whose delivery failed or is uncertain as well (a failure the connector recorded, not an indexed message or one in flight) counts as later too, for any failed operation but an admission and only when the case is not in an ordered or interleaved chain (the incident sends a chain's failures in event order); a later discharge that failed does not (the encounter is still admitted at the receiver, and the discharge's own case follows a resend of the earlier movement); and an event whose time is not plausible (the `event_time` rule below) counts for nothing. `Shutter.Catalogue.Matcher.Later` lists these events; the gate's ordering check reads the same list |
| `event_time` | `plausible`, `before_admission`, `future`, `far_from_recorded`, `clock_change`, `later_event_future` | the failed event's time (v1.11, T28): before the admission the message (PV1-44) or the receiver's first history entry names, for anything but an admission; more than five minutes after the message was sent or the evidence was taken; more than a day from the recording time (EVN-2); without an offset, read in `Europe/London`, and within an hour of a British clock change (the order of two events is then not safe); `later_event_future` (v1.16) when the failed event's own time passes these checks but a later event it would be ordered against lies more than five minutes after the feed sent it, the receiver applied it or the evidence was taken, and believing it would change the reading (no plausible later transfer, discharge or cancel settles the order already, the event outranks `later_applied` and it is not an update), so a wrong time could make a genuine failure look overtaken; plausible otherwise. The gate's ordering check blocks a write and a superseded closure on any value but `plausible` (`EVENT_TIME_IMPLAUSIBLE`) |
| `encounter_state` | `admitted`, `discharged`, `not_found`, `unknown` | the downstream system's state; `not_found` when the receiver answers 404 (it does not know the encounter); `unknown` when the receiver can't be read |
| `transition` | `allowed`, `invalid`, `unknown` | the failed event from the encounter's current state (1.4): a transfer after a discharge is `invalid` |
| `patient_match` | `yes`, `no`, `unknown` | the message's PID-3 against the downstream system's patient for the encounter |
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
  superseded), `reconcile`, `none`, `escalate`, `resend_unconditional` (never automatic; needs the site flag `unconditional_resend: allowed`, the only value besides `forbidden` the profile validator accepts), `correct_history` (not implemented: always escalated with the steps named).
- An alternative has `outcome`, `why` and `when`: `always` for a choice left to the board, or a site profile condition
  `<flag>: <value>` such as `history_policy: correct` or `unconditional_resend: allowed`. The value may be the
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
- `policy`: the rules below (chosen per run; the installed default, and the mode after every scenario reset, is `board`);
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
- **A withheld case (v1.14), in every mode:** no board and no investigator. One match takes the person path above; otherwise
  the workflow adopts an escalate plan naming the feed's reason, and the gate appends `MERGE_WITHHELD` or
  `CANCEL_UNSUPPORTED`. A withheld message costs no model run, however many arrive.
- The matches, with every condition's observed value, are stored on the case (`catalogue` in the snapshot summary) and
  shown in the app.
- Recording keys for replays name the case within its scenario: `scenario:<S>:<encounter>:<event>|<member>|<cfg>[|round<n>]`;
  the replay runner falls back to the older `scenario:<S>|<member>|<cfg>` form, which the first recordings use.

### 6.4 The site profile and the policy path

The questionnaire's answers are the site profile (`knowledge/site/profile.json`, versioned; defaults shipped). The core
reads it through `Shutter.Store.SiteProfile`.

```json
{
  "version": 1,
  "receivers": [
    {"name": "Downstream Out", "system": "the demo bed-management system", "tier": 2,
     "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false,
     "api": {"base": "/downstream/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}",
             "capabilities": "/capabilities", "operations": "/operations"},
     "features": {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}}
  ],
  "history_policy": "current",
  "authoritative_source": "",
  "unconditional_resend": "forbidden",
  "merges": "forbidden",
  "policy": {
    "1": {"single": "automatic", "ordered": "automatic", "interleaved": "board"},
    "2": {"single": "automatic", "ordered": "approval", "interleaved": "board"},
    "3": {"single": "approval", "ordered": "per_chain", "interleaved": "board"}
  },
  "approvers": {"role": "Shutter Approvers", "escalation": "the integration team's on-call"},
  "incident": {"threshold": 5, "window_minutes": 10, "quiet_seconds": 60},
  "model_content": {"free_text": false},
  "feed": {"time_zone": "Europe/London"}
}
```

(`teams` and `mail`, optional, are in section 10.)

- A tier is the receiver's; a policy is read by tier and chain kind.
- **The receiver description** (v1.8): each receiver entry carries `api` (its `base` path and the paths of its `state`,
  `receipt`, `capabilities` and `operations` endpoints, with the placeholders `{encounter}` and `{key}`) and
  `features` (what the site declares it can do: `conditional_writes`, `receipts`, `history`, `dry_run`). The evidence
  collector, the verifier and the connector read their paths from the entry named by the case's receiver (the
  production item that delivered to it), so a second receiver is configuration, not code. A path left empty means the
  receiver has no such endpoint: no receipt lookup, and the capabilities are the declared features, which the route
  item records as `capabilities_source`. An entry without `api` takes the downstream system's paths.
- `PUT /site-profile` refuses a profile that has not this shape, naming the field (unknown top-level fields and
  unknown `api` paths or `features` are refused too); every stored version is kept with who stored it and from where,
  `GET /site-profile/history` lists them (v1.9). `feed.time_zone` (v1.11) names the zone of timestamps without an
  offset: `UTC`, `Europe/London` or a fixed offset; the built-in default (`SiteProfile.Default()`, in force only while no
  profile row is stored) is `Europe/London`, a stored profile that does not answer keeps `UTC` (the reading before v1.11),
  and the shipped seed profile says `Europe/London` (v1.12), so the fixtures' times read as British Summer Time (09:20 on
  15 October is 08:20Z). A zone outside these that reaches the reader anyway (the profile's check refuses one, so only a zone
  set by hand in the namespace's cached `feedZone`, or one passed to the time probe) is read as `UTC` with a warning in the event log, once per job and zone, and the evidence's note says so (v1.16). The questionnaire page asks for `teams` and `mail` (question 9), `feed` (10) and `model_content` (11)
  since v1.12, and since v1.14 for `merges` (12), each receiver's `merges` beside its `cancels` (5) and each team's
  `sources` (9). The body may carry
  `expectedVersion` (the version the caller read, not
  part of the profile): when the stored version has moved, the answer is 409 `stale_version` with `currentVersion`, so
  a page never overwrites another person's change unseen; the check and the write happen under one lock (v1.10). An
  `api` entry must name at least its `state` and `operations` paths. The shipped seed profile fills an empty store and
  follows its own file; once a person has saved a profile from the app, a reinstall or a restart never replaces it.
- `automatic`: the case (or the chain) is released with no Workflow task. It is still gated at the proposal and at the
  dispatch, rehearsed and verified, exactly as an approved case. The case records an approval whose approver is
  `policy`, with the profile's version, the tier, the chain kind and the entry, so the authorization check and the
  closure read as for a person's approval, and the app shows "automatic by site policy".
- `approval`: one Workflow task for the case, or for the whole incident (section 7).
- `per_chain`: one Workflow task per chain of the incident.
- `board` for a chain kind means the board runs whatever the match says.
- A tier 3 receiver never takes `automatic` unless the profile says so explicitly; the shipped default does not.
- `merges` (v1.14): `forbidden` (the default when absent) or `allowed`, the only values the validator accepts. A receiver entry's `merges` and `cancels` (booleans, default false) say what it takes (1.1). A merge is delivered only under `allowed` to a receiver with `merges: true`; the gate's `MERGE_WITHHELD` blocks any write of a merge otherwise, so the exact repeat of a merge the receiver already holds (a receipt present) is E3's reconcile, and no other merge is ever resent by Shutter. `Shutter.Store.SiteProfile.MergesAllowed()` and `ReceiverFlag(name, flag)` read them.

### 6.5 The gate's catalogue checks

A new check, `catalogue`, with these reason codes (in `knowledge/block-reasons.json`):
- `ENTRY_UNKNOWN`: the plan names an entry that is not in the catalogue at the plan's catalogue version (block);
- `PATTERN_NOT_MATCHED`: the entry's pattern does not hold on the snapshot (block);
- `OUTCOME_NOT_ALLOWED`: the chosen alternative's `when` does not hold for this site (block);
- `NEW_PATTERN`: no entry matches (block; the case escalates as a candidate entry);
- `POLICY_REQUIRES_APPROVAL`: an automatic release where the profile requires an approval (block; an internal guard).
The plan's `catalogue_entry` and `outcome` are bound by the approval's digest like every other field of the plan.

Two `intent` checks for withheld cases (v1.14, policy version 2026-10-19.3), appended for every plan on a case of kind `withheld` as `UNMAPPABLE` is, and as guards on any write of a merge or a cancel: `MERGE_WITHHELD` (the case's event is `merge` and the site profile does not allow merges, or the receiver does not take them) and `CANCEL_UNSUPPORTED` (a `cancel_*` event to a receiver whose entry says `cancels: false`). The identity check answers `NO_ENCOUNTER` (pass) for a case whose encounter piece is `-`, and the state-transition and concurrency checks answer `PATIENT_LEVEL_WRITE` (block) for a write on such a case: there is no encounter state or version to check, so a person decides, and nothing is retried.

### 6.6 The board and the catalogue

The board has no catalogue tool (v1.6 named a `search_catalogue` tool; it was never built, and the coordinator stopped
naming it in v1.7). The matches reach it in the evidence, in the snapshot summary's `catalogue` section, each with its
entry's prose, so that the board cites entries by id. The coordinator's instructions say the plan names the entry and
the outcome, or leaves `catalogue_entry` empty when no entry fits (a new pattern). The members' knowledge tools are the
four collections under `knowledge/` (`search_contracts`, `search_lifecycle`, `search_effects`, `search_playbooks`).

## 7. Incidents: many failures to one receiver (v1.6, as built in v1.7)

### 7.1 Detection and grouping

- The connector counts delivery failures and refusals (not uncertain outcomes) per receiver in a sliding window. At the
  profile's threshold (default 5 within 10 minutes) an incident opens for that receiver.
- A case opened while an incident is open for its receiver joins it (case state `grouped`) instead of starting its own
  investigation. When the incident opens, it also adopts the burst's earlier cases for that receiver that are still before
  their proposal gate (settling, collecting or investigating), so the first failures are not left outside it. The
  incident's intake closes after `quiet_seconds` with no new failure.
- Only failures and refusals to the receiver that no incident holds count towards the threshold. A case joins with its
  evidence still to collect and parks in `grouped` once its snapshot and match are in the store (after the board, when
  the incident adopted it mid-investigation: the plan stays on the case, and the release plans again). Once the intake
  has closed, the chains form when every case has parked, or after 180 s: a case still collecting then leaves the
  incident and continues alone.
- Chains form per encounter (PV1-19), oldest event time first. Chains of one patient (PID-3) are linked for the page; the
  link imposes no order across encounters.
- A chain's kind: `single` (one failure, nothing later applied), `ordered` (several failures, no successful delivery for
  the encounter between them), `interleaved` (successful deliveries between the failures, or a later applied event).
- Each case in a chain gets its own evidence snapshot as today. The matcher runs per case with `chain` set.
- `withheld` and `unmappable` cases never count towards or join an incident (the detector counts `delivery_failed` and `rejected` only); a rejected merge at a site that allows merges does, and its release is gated like any write (v1.14).

### 7.2 Classification and the plan

- A chain whose cases all match one entry with `decides: policy` is a policy chain: `single` and `ordered` chains with
  `resend` or `resend_chain` take the policy path; `none` and `reconcile` outcomes close their cases without a write.
- Any other chain is a board chain: the board runs for each of its cases, as today, with `chain` in the evidence.
- Each chain carries the site's policy for the receiver's tier and its kind (`automatic`, `approval`, `per_chain`; `path`
  for a chain whose cases run their own path). Outside policy mode every chain is a board chain (6.3), and a profile
  policy of `board` makes a chain a board chain.
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
- Task subjects: `Shutter I-nnnnnn: approve the release of N chain(s) to <receiver>` for the shared approval, and
  `Shutter I-nnnnnn/<seq>: ...` per chain; both carry the `PlanDigest` and `Comment` form fields. An approval with
  another digest, or none, rejects the chains it covers: their cases are escalated with the reason.

### 7.4 Release

- The incident releases chains one at a time (or side by side, when the profile allows), and within a chain one item at
  a time: it tells the case the version to expect, the case runs its own dispatch stage (the preflight read, the
  dispatch gate, the rehearsal, the write, the verification) and reports back.
- The dispatch gate's concurrency check compares the receiver's version with the expected one; any other write in
  between stops the chain: the remaining items go to a person with the reason, and the incident's record says which
  item stopped and why.
- Every item keeps its own trace, approval record and closure; the incident's record lists each chain's outcome:
  `resolved`, `stopped` (with the item), `escalated` (a board chain or a no-match).
- Chain states: `pending`, `awaiting_approval`, `approved`, `rejected`, `releasing`, `resolved`, `stopped`, `escalated`;
  item states: `pending`, `released`, `resolved`, `blocked`, `escalated`, `failed`, `stopped` (never released). An item's
  expected version is the previous item's verified version; the first item of a chain a person approved goes at the
  chain's first expected version from the plan, and the first item of an automatic or board chain goes on fresh
  evidence. A released case whose fresh evidence shows another version blocks (the sequence rule) and its chain stops.
  Chains are released one at a time in sequence order; approved chains go while the others' approvals are pending. A
  released case under the incident's approval records an approval by the approving user, naming the task and the
  incident plan's digest, so the gate treats it as a person's.

### 7.5 The API

- `GET /incidents` (`?state=`, `?limit=`, default 50, at most 500): `items` and `total`; each item is the incident (id,
  receiver, mode, state (`open`, `classified`, `awaiting_approval`, `releasing`, `closed`), times, the plan's digest and
  the versions it binds, the approval) with `progress`: `chains`, `cases`, `byKind` and `byState`.
- `GET /incidents/{id}`: the chains with their items (case ids, position, kind, entry, outcome, the expected version
  rule), the plan's digest, the approvals, progress.
- `POST /incidents/{id}/approvals` with `planDigest`, `decision` (`approve` or `reject`; `action` is accepted too),
  `comment`; `Idempotency-Key`; 409 `plan_changed` when the digest moved, 409 `wrong_state` when nothing awaits approval.
  `POST /incidents/{id}/chains/{seq}/approvals` for `per_chain`.
- `GET /incidents/{id}/events`; `GET /incidents/{id}/approvals`. `GET /incidents/{id}` also carries the plan, the
  approvals, the Workflow tasks and the workflow trace link.
- A case carries `incidentId` and `incident` (`incident_id`, `incident_state`, `chain_seq`, `position`, `chain_kind`,
  `decides`, `chain_policy`, `item_state`, `expected_version`); its events say whether it was released automatically,
  under the incident's approval, or stopped.
- `GET /site-profile` (`Shutter_Operate`, as every read) returns the current profile with its version; `PUT /site-profile`
  (`Shutter_Approve`, `X-Requested-With`) replaces it with the body, which must have the shape of 6.4 (400 `bad_request`
  naming the field otherwise), and answers the same object as the GET with the new version; the questionnaire page writes
  it. Every version is kept as a `Shutter.Store.SiteProfileVersion` row with who stored it and from where
  (`GET /site-profile/history`).

### 7.6 Scenario S11, an outage burst

Eight failures for six patients to the downstream system, in one burst (the fault `fail_before_accept` on, the files,
the fault off): P1 one failed A02 (E2, single); P2 A02 and A03 failed (E4, ordered); P3 A02 failed, A08 applied, a later
A02 applied, A03 failed (E5, interleaved, board); P4 A02 failed, then a later A02 applied (E1, superseded); P5 A02
failed after an applied A03 (E6); P6 a failed A01 (E2, single, admit). Expected: the policy chains resolved without the
board at tier 2 (automatic single, approval ordered), P3 by the board, and the downstream system's final state per
patient listed in `fixtures/scenarios.json`. Its recordings are hand-written until a key is available.

## 8. The exact index (v1.9)

Shutter's own index of the HL7 traffic it watches, so the evidence can find the other messages for an encounter or a
patient without opening every message in a time range, and without touching the site's Search Table Class settings.
A near match would be a wrong patient or a double write, so this index is exact; similarity (precedents) is a
separate, later tool.

### 8.1 The index and the indexer

- `Shutter.Index.Message` is an `Ens.CustomSearchTable` over `EnsLib.HL7.Message`: one row per message body (`DocId`),
  with `VisitNumber` (PV1-19.1), `PatientId` and `PatientIdAuthority` (PID-3), `MessageType` (MSH-9), `Event`
  (Shutter's word, else the trigger), `ControlId` (MSH-10), `EventTime` (EVN-6, else EVN-2, else MSH-7, ISO UTC),
  `Location` (PV1-3.1), `SourceSystem` (MSH-3), `OperationKey` (Shutter's key when the message maps), and the first
  header's id, source, target and time. Indexed: visit number, patient, operation key, control id, event time,
  message type and source (bitmaps). IRIS removes a row when its message is purged.
- `Shutter.Index.Indexer` (production item "HL7 Index", a service on the plain `Ens.InboundAdapter`, whose `CallInterval` is 5 s) walks
  `Ens.MessageHeader` by id from a high-water mark (`^Shutter.Index("hwm")`), `BatchSize` headers a pass, only HL7
  bodies on the `Routes` (business service config names; empty means every route), and only headers older than
  `LagSeconds`, because an id is taken before its row is written. The first start begins at the oldest header within
  `BackfillHours`. Defaults: `Routes` "ADT In", `BatchSize` 200, `LagSeconds` 5, `BackfillHours` 168; one call runs up to 20 passes while the walk is behind. A header whose message could not be indexed is recorded in `^Shutter.Index("failed")` (`GET /index` counts them as `failed_headers`) and cleared when `Rebuild` indexes it. A body already indexed is skipped, so a site may also name the class as a host's Search Table
  Class. `Rebuild(fromId, toId, routes)` walks a range again (SQL procedure, `Shutter_Operate`).
- The index is a finder, never a second source of truth: every decision still opens the message or asks the receiver.

### 8.2 The timeline

- `Shutter.Index.Timeline.ForCase(case)` builds the snapshot's `timeline`: the feed's operations for the encounter
  since the last reset, from Shutter's typed messages with their delivery outcome (`source: "feed"`), merged by event
  time with the index's rows for the same visit number that the feed did not carry (`source: "index"`, with `route`,
  `message_type` and a `note`). An indexed message's `outcome` is `unknown`: the gate's supersession check and the
  matcher's `later_applied` count only `applied` and `already_committed`, and outside a chain a later transfer of the
  feed's own whose failure the connector recorded (6.1, v1.16), so it supersedes nothing by itself; the receiver's
  history decides. The board sees it and can say so.
- A scenario for a later movement on a route Shutter does not own, found only by the index, is planned; it is not in `fixtures/scenarios.json` yet.
- The index row's `Event` is the key's event word (v1.14: `register`, `preadmit`, `person_add`, `person_update`, the cancel words and `merge` included, 32 characters), so registrations, pre-admissions and person updates show between the movements; its `VisitNumber` is `-` for a mapped message with no PV1-19 (an unmappable message without one keeps an empty visit number), and the timeline and the index answer nothing for an encounter of `-` or empty.

### 8.3 The API

- `GET /index`: `rows`, `high_water_mark`, `started_at`, `last_pass_at`, `last_indexed_at`, `indexed_total`, `newest_header`, `hl7_headers_behind`, `caught_up` and `failed_headers`.
- `GET /index/messages?encounter=…|patient=…|key=…`: `items` (the indexed messages, at most 500, event time ascending) and `total`; 400 `bad_request` when none of the three is given.
- `GET /index/messages?encounter=…|patient=…|key=…`: the indexed messages (at most 500), event time ascending.

### 8.4 Limits

- Messages from before the back-fill window are indexed only by `Rebuild`.
- The Message Viewer may or may not offer the columns of a search table no host names in its setting (to check);
  Shutter's own pages carry the search.

## 9. What leaves IRIS for a model (v1.11)

The owner's rule (19 Oct 2026): only what is needed goes to the model. The stored snapshot is complete and stays inside
IRIS (the gate, the matcher, the verifier and the app read it); what a model receives is a reduced copy made by
`Shutter.Util.ModelView.Reduce` at the two places anything leaves: the agent request's context
(`CaseWorkflow.BuildAgentRequest`: the evidence and the specialists' findings) and every answer of the evidence tools
(`Shutter.Tools.Evidence`). The reduction:

- **Identifiers become per-case tokens.** The MRN, the NHS number and any other PID-3 identifier, the encounter id,
  the visit number, the name parts (PID-5) and the date of birth (PID-7, as written and as ISO) are replaced by
  `MRN-T1`, `NHS-T1`, `PID-T1`, `ENC-T1`, `VISIT-T1`, `NAME-T1`, `DOB-T1`. The map (`Shutter.Store.CaseToken`, in the
  data database, never leaving IRIS) is built once per case by the business process in a canonical order: the case's
  own patient and encounter first (always T1), then the message's values, then every identifier found in the
  evidence (id keys, the first piece of `patient_identifier`, the patient and encounter pieces of every operation
  key), sorted by kind and value, so the same fixture gives the same tokens in every run. The replacement happens
  inside every string value of the reduced object at identifier boundaries (a number equal to an identifier becomes
  the token), so operation keys (`PAS^HOSP^MRN-T1^ENC-T1^transfer^...`), history entries, timeline rows and error
  echoes carry the tokens too. A value already mapped keeps its token whatever kind asks (an encounter id that is
  also the visit number is one token); a value that itself looks like a token is left as it is, and a value shorter than three characters is never tokenised, except a name part, which is from two (v1.16: a surname such as Li or Ng; a single initial is left, since as a token it would replace every standalone letter). Values of three characters or more are matched whatever their letter case (v1.16: `SMITH` in the message, `Smith` in an error echo); a two-letter name part only as written, so a short word of the summary's own text (`no`, `to`) is never taken for a name. The view fails closed (v1.16): `ModelView.Learn` returns an error when the case names a message that cannot be read or a value's token cannot be stored, and the case workflow then builds no agent request, sends nothing and escalates the case; `ModelView.Reduce` answers `{"error": ...}` instead of a view for a case whose own patient or encounter has no token.
- **Demographics never go**: `patient_name`, `name`, `given_name`, `family_name`, `date_of_birth`, `dob`, `sex`,
  `gender`, `address`, `phone`, `email`, `next_of_kin` and the like are dropped wherever they occur.
- **Free text never goes.** Each OBX or NTE note becomes `{segment, position, observation_id, value_type,
  free_text_present, instruction_like, note}`, where `note` says the text stays in IRIS (or that a binary or reference
  value is never sent); the text stays in IRIS. `instruction_like` is a word-list flag (ignore, override, you must, resend, approve and the like),
  not a verdict. The site profile's `model_content.free_text: true` sends the text; the default is off.
- **Allowlists by shape.** The summary, the operation, the message (`message_control_id`, `message_type`, the
  sending and receiving applications, the times, `patient_identifier`, `patient_class`, `assigned_location`,
  `visit_number`, `admit_time`, `notes`, `segment_count`, `doc_type`, `error`), the validation, a receiver's body
  (`encounter_id`, `patient_id`, `patient_id_authority`, `state`, `ward`, `location`, `version`, `epoch`, `history`,
  `error`), a history entry (`event`, `ward`, `event_time`, `applied_at`, `version_after`, `operation_key`), a
  receipt (all of its fields), the failure (`kind`, `outcome`, `reason_code`, `http_status`, `text`,
  `ens_session_id`, `source_header_id`), a timeline row and the route each keep a named set of keys; anything else
  keeps everything but the denied keys (`headline` among them). Strings that came from outside (`text`, `error`,
  `message`, `detail`) are capped at 1000 characters and carry `instruction_like: true` when they read like an
  instruction.
- **OBX and NTE** are read wherever they sit in the message (grouped segments included, 50 at most), with `segment`,
  `position`, `observation_id` and `value_type`; the stored snapshot keeps the text. With the switch on, the text goes
  tokenised and capped at 500 characters, never an ED or RP value, and the case records that it went.

**Coming back:** the model speaks in tokens. `ModelView.Restore` puts the identifiers back before a run, a finding or a
plan is stored (`AgentRun.FromResponse` for the result, the text and the error; `CaseWorkflow.OnMember` and
`OnCoordinator` before they parse the result), so people and the gate read real ids; a token the case has no value for
stays as written and is noted on the case. The recordings and the tool-call rows keep the tokens, since that is what
left IRIS. A recording made before this rule replays with real ids in its result; `Restore` finds no token and leaves
it. `GetFailure` answers a fresh failure object and the error item, never the case headline. `SELECT Shutter_Util.ModelView_Preview('C-000012')`
shows what the model would see of a case.

- A merge's prior identifiers (v1.14: `prior_patient_id`, `prior_encounter_id`, `prior_patient_identifier`, `prior_visit_number`, and every MRG group's in `prior_identifiers`, each paired with the surviving patient identifier of its PATIENT group as `into`) are tokens like the case's own (PID or MRN or NHS by the identifier type, ENC, VISIT; the prior name's parts NAME); `merge_groups`, `patient_class` and the validation's version fields pass through.

## 10. Escalation by email (v1.11)

A blocked, escalated or failed case can be handed to the people who correct systems by hand. The draft is built from
the stored case without a model (`Shutter.Util.EscalationDraft`): the hospital number and NHS number, the date of birth,
the event (what, where, when, the operation key), what failed, why Shutter stopped (the block reason and the failing
checks), what the receiver holds with its history, the encounter's timeline from the feed and the index, what Shutter
sent, and references. No name, address or note text. A person reviews it, chooses the team and sends it; the send is
bound to the digest of the text the person read.

- The site profile's `teams` (array of `{id, name, mailbox, cc?: [...], receivers?: [...], sources?: [...]}` (v1.14: `sources` lists sending applications, MSH-3, such as `PAS`; a merge goes first to the team whose `sources` lists the case's source system, then to the receiver's team, then to the first team; the draft words a merge "Merge of <prior identifier> into <patient identifier>" and a cancel "Cancellation of the transfer at ..."; a cancel carries no ward, section 2); a withheld case's draft says Shutter withheld the message and asks the team to mark the case handled rather than to reinvestigate; `id`, `name` and
  `mailbox` required, ids unique) and `mail` (`allowed_domains`: every mailbox and cc must end in one of them when set, checked when the profile is saved and again at `PATCH` and at the send; `from`: the sender of the emails when set, else the `Escalation Mail` operation's `From` setting, default `shutter@localhost`). The team for a case is the one whose `receivers` names the case's receiver, else the first, else the
  profile's `approvers.escalation` text with no mailbox (the person fills one in).
- `GET /cases/{id}/escalations`; `POST /cases/{id}/escalations` with `{teamId?}` answers 201 with the draft (409
  `wrong_state` unless the case is blocked, escalated or failed; 500 `draft_failed` when `teamId` names no team of the
  profile); `PATCH /cases/{id}/escalations/{seq}` (404 `not_found` for an unknown seq; 400 `bad_request` when the body is
  not a JSON object) with `{subject?, body?, to?, cc?}` edits a draft or a failed email (409 otherwise) and moves
  `bodyDigest`, the SHA-256 of `to`, `cc`, `subject` and `body` together, so a change of recipient alone moves it;
  `POST /cases/{id}/escalations/{seq}/send` with `{bodyDigest}` answers 202 with the queued escalation, 409
  `body_changed` when the digest is not the current text's, 409 `no_recipient` when `to` is empty, and 422
  `address_not_allowed` (with `field`: `to` or `cc`) when an address is not an address or lies outside the allowed
  domains; `PATCH` answers the same 422 for a `to` or `cc` it is given. All need
  `Shutter_Operate`; the writes need `X-Requested-With` and take an `Idempotency-Key`.
- The `Escalation Mail` operation (`Shutter.Operation.EscalationMail`, `EnsLib.EMail.OutboundAdapter`) sends through the
  site's mail server when the adapter's `SMTPServer` is set (first-time configuration; the NHS relay at most trusts),
  and otherwise writes an `.eml` file to its `OutputFolder` (default `<mgr>/shutter/out/mail`), so the demo and CI need
  no mail server. States: `draft`, `queued`, `sent`, `failed` and `cancelled` (closing the case by hand, `POST /cases/{id}/close` in 5, cancels a draft or queued email);
  each step is a case event of kind
  `escalation`. Then `POST /cases/{id}/reinvestigate` verifies the manual correction.

## 11. The case intake from another production (v1.15)

Shutter can open a case for a delivery that failed in a production it does not own (the install document's shape A,
`docs/INSTALL.md`). Nothing is mapped across namespaces for it: the intake is self-contained, and Shutter keeps its own
copy of the message.

- `POST /api/shutter/intake`, resource `Shutter_Intake` (the role `Shutter_Forwarder` carries it, and only it: the
  forwarder's user can call no other route; the demo user is `forwarder`, password `shutter`, the `SHUTTER_DEMO_PASSWORD`
  rule as for the others). The caller signs in with HTTP Basic authentication and sends `X-Requested-With: Shutter`; an
  `Idempotency-Key` is honoured as on the other POSTs. The body: `{"source": {"namespace", "production", "route",
  "header_id"}, "receiver": "<the item that delivered; the receiver's name in the site profile>", "failure": {"kind":
  "delivery_failed" | "rejected" | "uncertain_outcome" | "unmappable", "text", "outcome": "unavailable" | "error" |
  "uncertain" | "rejected" | "", "http_status", "reason_code"}, "message": "<the HL7 text, segments separated by
  carriage returns>", "schema_category": "2.5.1", "mode": "board"}` (the last two optional). Answers 202 `{"caseId",
  "state", "opened"}` (`opened` false when a case for the same operation key is already open, as the feed's own
  intake); 400 `bad_request` naming the field (no JSON object, no message, an unknown kind); 401; 403; 503 `no_service`
  or `not_queued`.
- Inside the production: the API service sends `Shutter.Msg.ExternalIntake` (the body's fields as properties:
  `SourceNamespace`, `SourceProduction`, `SourceRoute`, `OriginHeaderId`, `Receiver`, `FailureKind`, `FailureText`,
  `FailureOutcome`, `FailureHttpStatus`, `FailureReasonCode`, `MessageText`, `SchemaCategory`, `Mode`) synchronously to
  the item **Case Intake** (`Shutter.Process.Intake`), which parses the text (`EnsLib.HL7.Message.ImportFromString`, the
  DocType resolved from the category, 2.5.1 when none), sends the message to **Case Intake Store**
  (`Shutter.Operation.IntakeStore`, an adapterless operation that only answers) so that the copy has an
  `Ens.MessageHeader` in Shutter's namespace, builds the operation with `OperationKey.FromHL7` (or `Unmapped`, with the
  kind `unmappable`, when it does not map), and sends `Shutter.Msg.CaseIntake` to **Case Workflow** with the failure, the
  stored copy's header as `SourceHeaderId`, and the receiver and source fields. The case workflow answers as soon as the
  case row is saved (`Reply`), so the route carries the case id within seconds. The HL7 Index's `Routes` names
  `Case Intake` beside `ADT In`, so the stored copies are indexed.
- The case carries `receiver` (the intake's, else the connector item), `sourceNamespace`, `sourceProduction`,
  `sourceRoute` and `originHeaderId`; the evidence snapshot has an item of kind `source` and the summary a `source`
  object `{namespace, production, route, header_id}` (kept for the model view, since it carries no patient data). The
  gate's receiver and the policy's tier follow the case's receiver. Everything else (the evidence against the receiver's
  API from the site profile's entry, the matcher, the board, the gate, approvals, the escalation) is as for the feed's
  own cases; a resend goes through Shutter's connector item, so a forwarded case's receiver is normally the name of
  that item (`Downstream Out` in the demo).
- **The forwarder.** `Shutter.Intake.Forwarder` is the item a watched production adds: a business operation on
  `EnsLib.HTTP.OutboundAdapter` (queue). Request `Shutter.Intake.Forward`: `HeaderId` (the failed HL7 message's header
  in the sending namespace), `Receiver`, `FailureKind`, `FailureText`, `FailureOutcome`, `FailureHttpStatus`,
  `FailureReasonCode`, `Route` (empty takes the header's `SourceConfigName`). Response `Shutter.Intake.Forwarded`:
  `CaseId`, `State`, `Opened`, `Error` (empty on 202; otherwise the HTTP status and body, or the connection error; no
  retry). Settings: `IntakePath` (default `/api/shutter/intake`), `SourceProduction` (default the running production's
  name), `SourceNamespace` (default the namespace), `SchemaCategory` (default the message's own category, else 2.5.1);
  the adapter's server, port, credentials (HTTP Basic as the forwarder's user) and SSL configuration are the site's.
  The sending production's process calls it on a failed delivery with the failure as its connector reported it; the
  package `Shutter.Intake` (with `Shutter.Util` and `Shutter.Msg`) is mapped into that namespace.
- **The demo hospital** (shape A as a judge sees it): the image also creates the namespace `HOSPITAL` (`Installer.cls`;
  `SELECT Shutter.Installer_RunHospital('SHUTTER')` on an instance that has Shutter) with the packages `Shutter.Intake`,
  `Shutter.Util`, `Shutter.Msg`, `Shutter.Store` and `Hospital` mapped from Shutter's code database, and
  `Hospital.Setup.Install('SHUTTER')`, run there, makes its folders (`<mgr>/shutter/hospital/in`, `archive`, `work`),
  its credentials (`DownstreamAPI` as `downstream-client`, `ShutterIntake` as `forwarder`), copies Shutter's feed time
  zone into `^Shutter.Config("feedZone")` so both namespaces key a message alike, and starts `Hospital.Production`:
  `PAS In` (an HL7 file service on the hospital's folder), `PAS to Downstream` (`Hospital.Process.PASToDownstream`:
  the operation from `OperationKey.FromHL7`, delivered through `Downstream Out`, and on a failure a `Forward` to
  `Shutter Forwarder`), `Downstream Out` (`Hospital.Operation.DownstreamOut`, the connector's POST and classification
  without Shutter's store), `Shutter Forwarder`. The hospital's production registers its definition in its namespace by
  compiling the mapped class there once. A scenario drops files into the hospital's folder (`^Shutter.Config("hospitalIn")`
  in Shutter's namespace names it); the case in Shutter then names the source.

## 12. The install (v1.15)

- **The demo flag.** The module manifest declares the IPM parameters `demo` (default 1) and `production` (default empty)
  and invokes `Shutter.Setup.InstallStatus(${root}, ${demo}, ${production})`, whose `%Status` IPM checks: a failed install
  stops the load and the Docker build. `zpm "load <dir> -Ddemo=0"` installs for a site. Every install creates
  `^Shutter.Config` (root, demo, version, mode), the folders under `<mgr>/shutter/`, the resources `Shutter_Operate`,
  `Shutter_Approve` and `Shutter_Intake`, the roles `Shutter_Operator`, `Shutter_Approver`, `Shutter_DownstreamClient`,
  `Shutter_WebApp` and `Shutter_Forwarder`, the Workflow role "Shutter Approvers", the seeds (board members, model
  prices, block reasons, the site profile, the catalogue), the web applications `/api/shutter` and `/shutter`, the daily
  task "Shutter retention", the production's default settings, and starts `Shutter.Production` as the namespace's
  auto-start production (a different running production in that namespace is stopped first). With `demo = 1` it also
  creates the users `operator`, `approver` and `forwarder`, the demo receiver (its resource and role, `/downstream/api`,
  `downstream-client` and the `DownstreamAPI` credential), imports the recorded runs, and creates the message purge
  task. With `demo = 0` it makes none of those, and after the start switches off the demo and feed items of
  `Shutter.Production` (`ADT In`, `ADT to Downstream`, `Downstream Out`, `Scenario Player`): a site adds its own feed
  items or uses the intake route. `PurgeStore` and `RecordAgentMode` refuse a non-demo instance as before.
- **The message purge.** "Shutter message purge" (`Ens.Util.Tasks.Purge`, every message type in the namespace, bodies
  too, sessions kept whole) is created only when `SHUTTER_MESSAGE_PURGE` is 1, or, when unset, on a demo instance; it
  keeps `SHUTTER_MESSAGE_DAYS` days of messages (90 when unset). The installer reads both from the environment of the
  process that runs it (the Dockerfile passes them as build arguments from `.env`; a `zpm load` by hand reads the
  shell's). The task is made once: an existing instance changes it in the Task Manager. The Doctor reports
  `purge_task` and `message_days`.
- **Shape B: Shutter's items inside a site's own production.** `Shutter.Setup.InstallInto(production, root)`
  (`SELECT Shutter.Setup_InstallInto('Your.Production', '/path/to/module/')`, or `zpm "load <dir> -Ddemo=0
  -Dproduction=Your.Production"`), in that production's namespace with the core classes loaded: refuses an empty name or a
  production that does not exist, records it in `^Shutter.Config("production")`, runs the namespace-level parts of a
  non-demo install (no message purge), and adds to the production, when it has none of that name, each of Shutter's
  items as `Shutter.Production` defines it (`Setup.INSTALLITEMS`: HL7 Index, Escalation Mail, Case Workflow, Incident
  Workflow, Evidence Collector, the agent items when their class is compiled, Gate, Shutter Approvers, Shutter API,
  Verifier, Case Intake, Case Intake Store; never the feed or the demo items), writes the default settings keyed to it
  (the receiver's address on Evidence Collector and Verifier, no wildcard row) and, when it is running, updates it in
  place; it never stops a production and never sets the auto-start production. The health route and the Doctor then
  name that production (`shutter_production`), and `StartProduction` leaves a shape-B namespace alone. Run again after
  an upgrade, it adds the items that are new.

## Repository layout

The core IPM module is the repository root (`module.xml`, sources under `src/`): it compiles on any 2026.2 Community image and replays recorded runs. The aihub module is `aihub/` (`aihub/module.xml`, sources under `aihub/src/`): the live runner, the agents, tools, schemas, policies and knowledge bases, which need the `%AI` package. Both modules contribute classes to the `Shutter` package; nothing under `src/` may reference `%AI`.

## Changes

- v1.16, 20 Oct 2026: supersession, the model view and corrections. `later_applied` counts, outside a chain and for anything but an admission, a later transfer whose delivery failed or is uncertain as well, and no later event whose time is not plausible; `event_time` gains `later_event_future` for a later event whose doubtful time would change the reading (6.1; the gate's ordering check reads the matcher's own list of later events, so the two agree, and says "a later movement was sent after it" when the superseding movement was not delivered; policy version 2026-10-20.1, so an approval given under 2026-10-19.3 and not yet dispatched is void at dispatch). The model view tokenises name parts from two characters, matches values of three characters or more whatever their case, and fails closed (9). A case is never written whole from a copy older than the stored one: a transition takes the case's lock and refuses a copy whose version is no longer the stored one, a note writes only its time (the version still moves only on transitions, so the routes' `expectedVersion` checks are unchanged), and the incident membership and the current snapshot are written field by field. The scenario runner's `route: "hospital"` file step, the hospital's folders in its reset and the `expected.source` of a forwarded case (4; S19). Corrections: the board has no catalogue tool: the matches and their prose reach it in the evidence (6.6). Closing a case by hand cancels its draft or queued email, so the state `cancelled` is set (10). An unknown `feed.time_zone` is read as `UTC` with a warning (6.4).
- v1.15, 20 Oct 2026: the production-install story (T33). The case intake from another production (section 11: `POST /api/shutter/intake`, the resource `Shutter_Intake` and the role `Shutter_Forwarder`, the items Case Intake and Case Intake Store, the source fields on the case and the `source` item of the evidence, the forwarder `Shutter.Intake.Forwarder` for a watched production, the demo hospital in the namespace `HOSPITAL`); the install (section 12: the IPM parameters `demo` and `production`, a status-checked Invoke, what a non-demo install creates and omits, the demo items switched off, the message purge by `SHUTTER_MESSAGE_PURGE` and `SHUTTER_MESSAGE_DAYS` with a default of 90 days, `InstallInto` for a site's own production and `Setup.INSTALLITEMS`); the gate's receiver and the policy's tier follow the case's receiver; `Shutter.Util.Time` reads the namespace's cached feed zone before the store. The install guide for a hospital is `docs/INSTALL.md`.
- v1.14, 19 Oct 2026: other HL7 schemas and the trigger table (section 2: the events A04, A05, A06, A07, A11 to A13, A28, A31 and A40; what is delivered, indexed only or withheld; the `-` encounter piece; fields read wherever the structure puts the segment; the version note in the evidence); the A40 rule (`merges` in the site profile and the receiver entry, 6.4; the kind `withheld`; `MERGE_WITHHELD` and `CANCEL_UNSUPPORTED`, 6.5; the merge's prior fields, 2 and 9; the escalation's `sources` routing and wording, 10); the matcher's `event`, `delivery: withheld`, `receiver_answer: none` and `later_applied: cancelled | merge` (6.1); withheld and unmappable cases outside incidents (7.1); the index's event words and the `-` visit (8.2); `POST /cases/{id}/close` (5); the gate's policy version 2026-10-19.3 (an approval given under 2026-10-19.2 and not yet dispatched is void at dispatch, `APPROVAL_POLICY_CHANGED`: the case blocks and a person reinvestigates), its `NO_ENCOUNTER` identity answer and `PATIENT_LEVEL_WRITE`; a withheld case never convenes the board (6.3); the close route's `expectedVersion` and the cancelled emails (5). The catalogue entries E14 (a patient merge) and E15 (a cancel the receiver can't reverse) and the block reasons `MERGE_WITHHELD` and `CANCEL_UNSUPPORTED` are the knowledge side of the same change.
- v1.13, 19 Oct 2026: the receiving system is named the downstream system (a demo bed-management system): the package
  `Downstream.*` with its globals `^Downstream.*` (was `Wards.*`), the web application `/downstream/api`, the resource
  and role `Downstream_API`, the role `Shutter_DownstreamClient`, the user `downstream-client`, the Ens credential
  `DownstreamAPI`, the production items `Downstream Out` and `ADT to Downstream`, MSH-5 `DOWNSTREAM` in the fixtures
  (3), and the knowledge ids `downstream-interface-contract` and `downstream-api-v1`. The wire codes (`ward_unavailable`,
  `ward_error`), the snapshot keys (`ward_state`, `ward_state_http_status`, `ward_api`), the tool `GetWardState`, the
  readiness keys and the `ward` field (the patient's location) keep their names. The installer removes the names from
  before (`/wards/api`, `Wards_API`, `Shutter_WardClient`, `wards-client`, `WardsAPI` and the `Wards` classes) when it
  finds them. Nothing under `^Wards.*` is migrated: a volume from before this version is removed once
  (`docker compose down -v`) before the first `up` of a newer build. The production start also rebuilds the agents'
  search collections (contracts, lifecycle, effects, playbooks) when their files changed, and drops the chunks of a
  file that is gone, so a renamed or removed document no longer answers a search.
- v1.12, 19 Oct 2026: `mail.from` is the sender of escalation emails when set; the addresses a person types are checked
  against `mail.allowed_domains` at `PATCH` and at the send (422 `address_not_allowed`). The recordings re-made with the
  zone: the shipped seed profile says `Europe/London` (6.4), and the scenario S13 (a transfer timed before its
  admission) exercises E13 and `EVENT_TIME_IMPLAUSIBLE`. The questionnaire page asks questions 9 to 11 (teams and mail,
  the feed's zone, note text for the model).
- v1.11, 19 Oct 2026: what leaves IRIS for a model (9): per-case tokens for the identifiers, no demographics, no free
  text (a flag instead, and the site profile's `model_content.free_text` switch), the receiver's bodies and the failure
  reduced, the map-back inside IRIS; escalation by email (10): the profile's `teams` and `mail`, the four routes,
  the `Escalation Mail` operation and the `escalation` event kind. Event times (T28): the `event_time` condition
  (6.1) and `later_applied: admit` (a later admission is not an update); the gate's ordering check blocks a write,
  and a superseded closure, whose event time is not plausible (`EVENT_TIME_IMPLAUSIBLE`; policy version
  `2026-10-19.2`); timestamps without an offset are read in the site profile's `feed.time_zone` (`UTC`,
  `Europe/London` or a fixed offset; UTC when the profile does not say), the message section records
  `times_without_offset`, `times_with_offset`, `feed_time_zone` and `event_time_had_offset` (whether the key's own
  field carried one), and the case gets a note, once, when a message's times carried no offset.
- v1.10, 19 Oct 2026: from the review of the day's code. New gate codes: `CLOSED_BY_CATALOGUE` (a pass of the ordering
  check: the plan says superseded and the history shows no later event, but the matched entry's outcome on this
  evidence is none, so the case closes with nothing to send; the verifier accepts the same closure when the receiver
  holds neither a receipt nor the operation), `RECEIPT_NOT_AVAILABLE` (the receiver has no receipt endpoint: a
  reconcile passes only when the receiver's history shows the operation, otherwise it blocks; other dispositions pass
  and the capability check governs the write), `MATCHER_ERROR` (a block: the matcher failed, which is not "no entry");
  the `receipt: none` condition (6.1). The gate's policy version is `2026-10-19.1`, so approvals given under the
  earlier checks are void. An `Idempotency-Key` is scoped to the user, the method and the route, and may be
  at most 128 characters (400 beyond). The anonymous `GET /health` adds `production_state`, and its `ok` is true only
  when the production runs. `GET /cases` clamps a negative `offset` to 0 and caps it at 100000; on the case, history and incident lists a
  `limit` below 1 takes the default 50 and one above 500 is clamped to 500. A board timeout belongs to the investigation round that armed it; a reopened or released case
  is driven by its newest workflow instance only, and an answer that reaches an older one is recorded for its cost and
  changes nothing. A preflight that finds no encounter for a non-admission blocks the case (`UNKNOWN_ENCOUNTER`): a
  definite answer, not a failed read. A refreshable unknown at the proposal gate collects the evidence again (bounded,
  with a growing wait) instead of blocking. An incident whose workflow fails is abandoned (chains stopped, the cases it
  still holds failed, released cases left to finish), not merely closed; an
  incident whose released chains are done and that waits for approval tasks says `awaiting_approval`. Retention also
  purges closed incidents older than the cutoff (chains, items, events and the cases they held) and the tool calls of
  purged runs. The production start reconfigures the provider when the environment's key changed (compared by digest)
  and re-reads the knowledge files that changed.
- v1.9, 18 Oct 2026: the exact index (8): the custom search table, the indexer, the merged timeline, two routes; a plan
  records the catalogue version it was matched against and an approval the site profile's version, and the dispatch gate
  voids the approval when either changed (`APPROVAL_CATALOGUE_CHANGED`, `APPROVAL_SITE_PROFILE_CHANGED`); the
  `delivery: unmappable` condition and the `UNMAPPABLE` conformance block.
  The gate's catalogue check blocks `OUTCOME_MISMATCH` when the plan's disposition is not what its chosen outcome
  calls for (resend outcomes resend; reconcile reconciles; none is superseded; escalate, resend_unconditional and
  correct_history escalate). The profile is validated on `PUT` and its versions are kept (6.4).
  A further failure for an open case's key whose payload digest differs blocks the case (`PAYLOAD_CHANGED`). The
  patient identifier is the PID-3 repetition typed MR, else the first. In replay mode a case with no recording for
  any member takes the rules path instead of escalating, so the gate still judges.
  Roles (E2): the installer creates each role or brings it to its definition; `Shutter_Approver` carries `%EnsRole_Monitor`
  with the message trace, header and content viewing resources, never `%EnsRole_Operator`, so an approver reads traces
  and the Workflow inbox and approves, and cannot start, stop or purge the production; `Setup.EnsureSecurity` applies
  the definitions to an existing instance.
  The image's namespace has two databases: the code in `${MGRDIR}SHUTTER` (the image) and the data in
  `${MGRDIR}shutter/db/SHUTTERDATA` (the `shutter-mgr` volume), so a recreated container keeps its cases and a rebuilt
  image brings new code to the same data; the roles read the code database and read and write the data database.
- v1.8, 18 Oct 2026: the receiver description in the site profile (`api`, `features`), read by the evidence collector, the
  verifier and the connector (6.4).
- v1.7, 17 Oct 2026: incidents as built (7): adoption and the ready wait, the chain's policy, the task subjects, chain
  and item states, the expected-version rule, the approvals route and the case's `incident` fields; the gate's
  `APPROVAL_PLAN_ORIGIN` check (an approval by policy needs a plan from the policy path for its entry; policy version
  2026-10-17.2) and the chain kind in its policy check (6.4); `encounter_state: not_found` when the receiver answers 404 (6.1); a chain item's `releaseEntry` and `releaseOutcome` (7.5).
- v1.6, 17 Oct 2026: the scenario catalogue and the deterministic matcher, the condition vocabulary, the site profile and the policy path (automatic, approval, per chain), the gate's catalogue checks, the board's `search_catalogue` tool (6); incidents: detection, chains and their kinds, the plan and its approval binding the sequence rule, the ordered release through each case's own dispatch, the API, scenario S11 (7). From the owner's decisions of 17 Oct and the T19 points (a) to (f), all taken.
- v1.5, 16 Oct 2026: rehearsal responses carry `encounter_before` and `epoch` (1.1); `POST /capabilities` takes `last_contract_check` (1.8); S8's second source system `BEDMGR` (2, 3); S9's second encounter `ENC-2009` (3); the `capabilities` step kind (3); the scenario player and the run states (4.2); section 5 points at the API as built. Points (a) to (e) were accepted on 15 Oct.
- v1.4, 15 Oct 2026: the capabilities read and the demo switch, the epoch, the receipt-lookup fault (1.8, 1.9); scenario steps that wait for a case state (4.1). From the triage of the owner's feature documents (T9, T10, A1, A2, A5).
- v1.3, 15 Oct 2026: `misleading_duplicate_error` with an `operation_key` (1.5); `resetAt`, the runner's settings and the mode semantics (section 4), from the scenario work.
- v1.2, 15 Oct 2026: the ward decisions of 15 Oct recorded (section 1.1), with `patient_mismatch` and `payload_digest_mismatch` as their own codes.
- v1.1, 15 Oct 2026: the runner sets `^Shutter.Config("scenario")` (section 4); the repository layout.
- v1, 15 Oct 2026: first version (sections 1 to 4).
