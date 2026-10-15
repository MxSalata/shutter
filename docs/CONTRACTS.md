# Contracts between Interlock's parts

Version 1.4, 15 October 2026. These are the interfaces the parts of Interlock are built against. Change the version and the date when something here changes, and say what changed at the end.

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

The DTL that builds the ward operation lives in `Interlock.DTL.ADTToWard`. The same mapping, as an ObjectScript class method, is `Interlock.Util.OperationKey.FromHL7(message)` so the evidence collector and the fixtures agree.

## 3. HL7 fixtures

- HL7 v2.5.1, one message per file, segments separated by carriage returns (`\r`), files under `fixtures/<scenario>/`, named `<scenario>-<nn>-<event>.hl7` (for example `S1-02-A02.hl7`). UTF-8, ASCII content.
- MSH-3 `PAS`, MSH-4 `HOSP`, MSH-5 `WARDS`, MSH-6 `HOSP`, MSH-9 `ADT^A02^ADT_A02`, MSH-10 unique across all fixtures (`MSG` plus five digits), MSH-11 `P`, MSH-12 `2.5.1`.
- EVN-1 the trigger, EVN-2 the recorded time, EVN-6 the event time (both `YYYYMMDDHHMMSS`, interpreted as UTC).
- PID-3 `MRN1001^^^HOSP^MR`; PID-5 synthetic names (no real people); PID-7 a date of birth; PID-8 a sex code.
- PV1-2 `I`; PV1-3 `WARD-A^BAY1^01^HOSP` (point of care, room, bed, facility); PV1-19 `ENC-1001`; PV1-44 the admit time.
- Free text that must reach the agents as data (the injected instruction in S4) goes in an OBX segment after PV1, `OBX|1|TX|NOTE^Transfer note^L||<text>||||||F`, which the ADT_A02 structure allows. No NTE segments in A02.
- Every scenario's timeline is one patient and one encounter, except S6 if it needs a second. Times are the same day, `2026-10-15`, 09:00 onwards.
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

Step kinds: `file` (drop the file into the ADT In folder; `expect` is `delivered` by default or `delivery_fails`), `fault` (section 1.5, with an optional `operation_key`), `wait` (`seconds`). The runner leaves at least two seconds between files so the production applies them in order.

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

## 5. The REST API for the app

Version 2 of this document, once the store and the workflow exist. The shape will follow the review file's section 5.8: cases, a case's timeline and artefacts, investigations, approvals, executions, scenarios and settings, with an expected case version and an idempotency key on every change.

## Repository layout

The core IPM module is the repository root (`module.xml`, sources under `src/`): it compiles on any 2026.2 Community image and replays recorded runs. The aihub module is `aihub/` (`aihub/module.xml`, sources under `aihub/src/`): the live runner, the agents, tools, schemas, policies and knowledge bases, which need the `%AI` package. Both modules contribute classes to the `Interlock` package; nothing under `src/` may reference `%AI`.

## Changes

- v1.4, 15 Oct 2026: the capabilities read and the demo switch, the epoch, the receipt-lookup fault (1.8, 1.9); scenario steps that wait for a case state (4.1). From House's triage of the owner's feature documents (T9, T10, A1, A2, A5).
- v1.3, 15 Oct 2026: `misleading_duplicate_error` with an `operation_key` (1.5); `resetAt`, the runner's settings and the mode semantics (section 4), from the scenario work.
- v1.2, 15 Oct 2026: the ward decisions of 15 Oct recorded (section 1.1), with `patient_mismatch` and `payload_digest_mismatch` as their own codes.
- v1.1, 15 Oct 2026: the runner sets `^Interlock.Config("scenario")` (section 4); the repository layout.
- v1, 15 Oct 2026: first version (sections 1 to 4).
