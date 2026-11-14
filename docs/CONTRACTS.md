# Contracts between Shutter's parts

Version 1.65, 14 November 2026. These are the interfaces the parts of Shutter are built against. Change the version and the date when something here changes, and say what changed at the end.

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
- `bed` is optional (v1.24): the bed within the ward, PV1-3's bed component, for an `admit` or `transfer` only (null or absent otherwise, or 422 `invalid_request`), and when given a string of 1 to 64 characters (anything else, a number or an empty string included, is 422 `invalid_request`). A bed is named within its ward, so `B2` on Ward B and `B2` on Ward C are two beds. `ward` stays the ward. A placement without a bed is ward-level, as every placement was before v1.24, and never conflicts with anyone. A placement into a bed that another admitted encounter holds is refused with 409 `bed_occupied` (below), in a dry run too; the encounter's own bed is never a conflict, so a transfer into the bed it already holds applies as any other transfer does. A discharge, or a transfer to another bed or to ward level, frees the bed the encounter held.
- A receiver that declares `cancels: true` in its site profile entry (6.4) also takes `cancel_admit`, `cancel_transfer` and `cancel_discharge`, each the reversal of the named event on the encounter; one that declares `merges: true` takes `merge`, with `prior_patient_id`, `prior_patient_id_authority` and `prior_encounter_id` beside the fields above (v1.14). The demo receiver declares neither and refuses them with 422 `invalid_request`; Shutter never sends them to it (section 2).
- `event_time` is the source event's time (see section 2), in ISO 8601 UTC with a `Z`. The downstream system stores it but **does not order by it**: operations are applied in arrival order. That is the receiver contract, and it is why a stale transfer applied late moves a patient backwards.
- `expected_version` is optional. When present, the operation applies only if the encounter's current version equals it. Normal traffic omits it; recovery always sends it.
- `payload_digest` is the sender's SHA-256 of the canonical payload (section 1.6). The downstream system computes its own and compares them when an operation key is reused.
- `dry_run: true` runs the whole validation and the write inside a transaction that is always rolled back, and reports what would have happened. Nothing is committed, no receipt is stored, no event is appended.
- A rehearsal's response also carries what it was checked against (v1.5): `encounter_before`, the encounter as the downstream system held it before the dry run (null when the downstream system has never seen it), `encounter_after` when it would apply, and `epoch`. The case workflow takes the receiver version an approval binds from `encounter_before.version`, never from `encounter_after`.
- Shutter writes only after a dry run of the same plan (v1.21): the dispatch gate's rehearsal check (6.5) requires the approval's bound rehearsal to be of this plan, to have reported `would_apply`, and to have been checked against the version, epoch and payload the write carries; otherwise `DRY_RUN_MISSING`, `DRY_RUN_FAILED` or `DRY_RUN_STALE` blocks the dispatch. The receiver keeps nothing of a dry run: a write is protected by its own `expected_version`, so a dry run at version 2 says nothing about a write at version 3. A receiver that answers a dry run with 201, or with 200 and `applied: true`, does not honour `dry_run`: Shutter records that rehearsal as an execution attempt (its `rehearsalId` names it), raises an alert in the event log, and verifies the effect; it never reports it as rolled back.

Responses:

| Status | Body | When |
|---|---|---|
| 201 | `{"applied": true, "receipt": {…}, "encounter": {…}}` | Applied and committed |
| 200 | `{"applied": false, "reason": "already_committed", "receipt": {…}, "encounter": {…}}` | The same operation key was committed before, with the same payload digest |
| 200 | `{"applied": false, "rehearsal": true, "would_apply": true, "encounter_after": {…}}` or `{"applied": false, "rehearsal": true, "would_apply": false, "reason": "<one of the error codes below>", …}` | `dry_run`; `reason` covers every refusal but `bed_occupied`, which a rehearsal answers as the 409 itself (v1.24) |
| 409 | `{"error": "version_conflict", "expected_version": 1, "current_version": 2}` | `expected_version` present and different from the current version |
| 409 | `{"error": "key_reused_with_different_payload", "operation_key": "…"}` | The key was committed with another payload digest |
| 409 | `{"error": "bed_occupied", "detail": "…", "ward": "…", "bed": "…", "occupant": {…}, "operation_key": "…", "applied": false}` | The placement's bed is held by another admitted encounter (v1.24, below); a dry run answers the same |
| 422 | `{"error": "invalid_transition", "state": "discharged", "event": "transfer"}` | The transition is not allowed (section 1.4) |
| 422 | `{"error": "unknown_encounter", "encounter_id": "…"}` | `transfer`, `discharge` or `update` for an encounter the downstream system has never admitted |
| 422 | `{"error": "patient_mismatch", "encounter_id": "…"}` | The encounter exists for another patient (identity never silently changes) |
| 422 | `{"error": "payload_digest_mismatch"}` | The sender's `payload_digest` differs from the downstream system's own computation |
| 422 | `{"error": "invalid_request", "detail": "…"}` | Missing or malformed fields |
| 503 | `{"error": "ward_unavailable"}` | Fault `fail_before_accept` is on (section 1.5); nothing was validated or written. Since v1.35 every 503 carries `Retry-After: 20` (delta seconds), as a real receiver may |
| 504 | empty body | Fault `commit_drop_response` is on: the operation **was committed** and the receipt stored, then the response was lost |

**Retry-After as a minimum wait (v1.35).** When a receiver answers a delivery 503 or 429 with `Retry-After` in the
delta-seconds form, Shutter's connector keeps it on the result (`retryAfterSeconds`, 1 to 3600; the HTTP-date form and
anything else are ignored), the feed's intake carries it (`retry_after_seconds` in the connector's answer) and the case keeps
until when the receiver asked not to retry (`retryAfterUntil`). The resend's first read of the receiver, the preflight after
the approval or the automatic release, waits for what is left of it, 300 s at most, with a note on the case ("The receiver
asked for a pause before a retry (Retry-After, until ...); the preflight read waits N s"), and the wait is spent once: the
field is cleared when the wait is armed. A case whose approval comes later than the receiver asked waits nothing (the field is cleared then too). A preflight read
that itself fails with a `Retry-After` waits the longer of its own backoff (10, 20, 40 s) and the header, 300 s at most,
before it is read again. A case from another production (11) carries none: the forward has no header field.

Decided with the downstream system (15 Oct): faults apply to real operations only, never to a dry run; a dry run reports a refusal as 200 with `would_apply` false, except `bed_occupied`, which it answers as the 409 itself (v1.24); a discharge sets `ward` to null; for an `admit`, `expected_version` 0 means "not yet seen"; the per-encounter lock waits 10 s and then answers 503 `ward_unavailable`; a reset answers 200 `{"reset": true}`; the dry run relies on a transaction rollback, so the database must be journaled (the default).

The order of checks for a non-dry run: fault `fail_before_accept`; request validity (including `patient_mismatch` and `payload_digest_mismatch`); a committed receipt for this key (return it, 200, before any version check, so a retry of an identical committed operation never looks like a version conflict); key reuse with a different digest (409); encounter existence (422); `expected_version` (409); transition (422); the bed (409 `bed_occupied`, v1.24); then, in one transaction: update the encounter, append the event, increment the version, store the receipt, commit; then fault `commit_drop_response` (504) or the 201.

**The bed occupied (v1.24).** The refusal is the receiver's own answer, the HL7 AE or AR of a bed-management system: it understood the placement and said no. It answers the same, HTTP 409 and this body, to a real operation and to a dry run, so a rehearsal never reports a placement as one that would apply while the bed is held:

```json
{
  "error": "bed_occupied",
  "detail": "Bed WARD-B/B2 is occupied by encounter ENC-1231 since 2026-10-15T08:10:00Z",
  "ward": "WARD-B",
  "bed": "B2",
  "occupant": {"encounter_id": "ENC-1231", "since": "2026-10-15T08:10:00Z", "version": 3},
  "operation_key": "<the refused operation's key>",
  "applied": false
}
```

Nothing is applied, no receipt is stored and the encounter's version does not move (a first admission that is refused leaves no encounter). `occupant` names the other encounter by its own id only, never by patient identifiers; Shutter's evidence tokenises it before any model sees it (9). `since` is the event time of the placement that put the occupant in that bed, the oldest of its admissions and transfers into it since it last held another place (an `update` moves nothing), and `version` is the occupant's current version. Two placements into one bed are taken one at a time: the bed is locked from the check to the commit or the rollback, with the same 10 s wait and 503 `ward_unavailable` as the encounter's lock. The bed an operation leaves (a transfer out or a discharge) is locked too, because a dry run's write can be read by other operations until it is rolled back: without that lock a placement could take a bed that a rehearsed transfer out seemed to free. An operation takes its beds' locks in one fixed order, so two operations never wait on each other.

### 1.2 Read an encounter

`GET /downstream/api/encounters/{encounter_id}`

```json
{
  "encounter_id": "ENC-1001",
  "patient_id": "MRN1001",
  "patient_id_authority": "HOSP",
  "state": "admitted",
  "ward": "WARD-C",
  "bed": null,
  "version": 3,
  "updated_at": "2026-10-15T09:45:02Z",
  "history": [
    {"version_after": 1, "event": "admit", "ward": "WARD-A", "bed": "A4", "event_time": "2026-10-15T09:00:00Z", "applied_at": "…", "operation_key": "…"},
    {"version_after": 2, "event": "transfer", "ward": "WARD-C", "bed": null, "event_time": "2026-10-15T09:45:00Z", "applied_at": "…", "operation_key": "…"}
  ]
}
```

404 `{"error": "unknown_encounter"}` when the downstream system has never seen it. `state` is `admitted` or `discharged`. `history` is in application order, oldest first, and is immutable. `bed` (v1.24) is the bed the encounter holds, null for a ward-level placement and once discharged; each history row carries the bed its operation placed the patient in, null for a ward-level placement, a discharge and an update.

### 1.3 Read a receipt

`GET /downstream/api/receipts/{operation_key}` (URL-encode the key)

```json
{
  "operation_key": "…",
  "encounter_id": "ENC-1001",
  "event": "transfer",
  "ward": "WARD-B",
  "bed": "B2",
  "event_time": "…",
  "applied_at": "…",
  "version_before": 1,
  "version_after": 2,
  "payload_digest": "sha256:…",
  "status": "committed"
}
```

`bed` (v1.24) is the committed operation's bed, null when it had none. 404 `{"error": "no_receipt"}` when nothing was committed under that key. Absence of a receipt is the downstream system's statement that the operation was not committed under that key, within its retention (unbounded in the demo).

A 404 describes what is committed at the moment the downstream system answers (v1.21). A write whose answer was lost may still be in flight, so the verifier reads a missing receipt as unknown and reads again until its settle window (the Verifier's `UncertainSettleSeconds`, 60 s by default since v1.42: the attempt is recorded when the connector gives up at its 15 s response timeout, so 60 s covers a receiver that commits up to a minute after that, and the case's last read, at about 70 s, is the one that judges) has passed since the attempt; it then stays unknown, and a person checks, since time alone proves nothing (5.1). It says not committed only once the version has moved past the one the write was conditional on, by something other than this write, so the conditional write can no longer apply. A site whose receiver can take longer to commit after a lost answer raises the setting.

Shutter takes a 200 from this path as a receipt only with `operation_key` the case's own, and a 404 as an absence only with this `error`; the same goes for the encounter path, a 200 with a `version`, a 404 with `unknown_encounter`. Anything else, such as a gateway's sign-in page or its own 404, says nothing about the receiver, and reads as could not be read (`receivers[].strict_answers`, 6.4).

### 1.4 Transitions and versions

| From | `admit` | `transfer` | `discharge` | `update` |
|---|---|---|---|---|
| (unknown) | admitted, version 1 | invalid (`unknown_encounter`) | invalid | invalid |
| admitted | invalid (`invalid_transition`) | admitted, ward changes | discharged | admitted, no change except the version |
| discharged | invalid | invalid | invalid | invalid |

For a receiver that takes them (1.1, v1.14): `cancel_admit` and `cancel_transfer` from `admitted`, `cancel_discharge` from `discharged`, `merge` from any state the receiver knows; the gate and the matcher judge a write of them by the same rule, and the demo receiver takes none. Every applied operation increments the version by one. A transfer to the ward the patient is already in is still an applied operation (version increments, event appended).

### 1.5 Faults, for the demos

`POST /downstream/api/faults` `{"mode": "off" | "fail_before_accept" | "commit_drop_response" | "commit_then_409" | "misleading_duplicate_error" | "receipt_lookup_unavailable" | "delay_response", "operation_key": "…", "seconds": n}`. With `operation_key` the fault applies to that key only; without it, to every operation until `off`. Returns 200 `{"mode": …, "operation_key": …}`. `GET /downstream/api/faults` returns the current setting. `POST /downstream/api/faults` also requires the resource `Downstream_Admin` (v1.39), which the downstream system's installer creates beside `Downstream_API` and grants to no role of Shutter's: a caller with `Downstream_API` alone, the production's client among them, is answered 403 `{"error": "forbidden", "detail": "This needs Downstream_Admin"}` and nothing changes; `GET /downstream/api/faults` needs only the web application's resource.

- `fail_before_accept`: 503 before any validation or write.
- `commit_drop_response`: the operation is committed, then the response is a 504 with no body.
- `commit_then_409`: the operation is committed, then the response is a 409 `{"error": "version_conflict"}`, as when a proxy answers for the receiver. A retry finds the receipt.
- `misleading_duplicate_error`: with an `operation_key`, the downstream system answers 409 `{"error": "duplicate_message"}` for that key whatever the version, and writes nothing; without a key, it answers that way when `expected_version` mismatches, instead of `version_conflict`. (A buggy receiver that reports the wrong reason. Nothing else changes.)
- `delay_response` (v1.33): each real operation (never a dry run) is held for `seconds` (a whole number from 1 to 60, 12 when not given; 422 otherwise), then applied and answered as usual. A slow receiver: a sender whose timeout is shorter gives up on an operation that is still applied, and the sender's next message for the receiver waits behind it. `GET /faults` reports `seconds` with the mode. A scenario's fault step passes `seconds` through (4.3).

### 1.6 Canonical payload and digest

The canonical payload is the JSON object with exactly these keys in this order, no whitespace, strings as given, null for absent `ward`: `operation_key`, `encounter_id`, `patient_id`, `patient_id_authority`, `event`, `ward`, `event_time`, `source_system`. `payload_digest` is `"sha256:"` followed by the lower-case hex SHA-256 of that UTF-8 string. `source_message_id`, `expected_version` and `dry_run` are not part of it, so a resend of the same business operation from a different message has the same digest. Nor is `bed` (v1.24): a ward-level operation's digest is what it was before beds, and Shutter's own digest of a key, already recorded on its cases and approvals, still matches the receiver's. The key and the ward bind the business operation; a resend under a committed key that names another bed answers `already_committed` with the receipt, whose `bed` shows what was committed, and a sender compares that rather than relying on a digest mismatch.

### 1.7 Reset

`POST /downstream/api/reset` clears encounters, events, receipts and faults. 403 `{"error": "not_a_demo_instance"}` unless the installer has marked the instance as a demo (`^Downstream.Config("demo") = 1`). It also requires `Downstream_Admin` (v1.39), checked first: a caller without it is answered 403 `{"error": "forbidden"}` whether or not the instance is a demo, so the production's client credentials cannot reset the receiver; the scenario runner and the live player reset in process through `Downstream.Service` and never pass here. The web application's password authentication applies.

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

The gate's capability check requires `conditional_writes`, `receipts`, `history` and `dry_run` for a write (v1.21; `history` since policy version 2026-11-06.1): a receiver that reports no dry run blocks every resend with `DRY_RUN_UNSUPPORTED`, and one that offers no history with `HISTORY_UNSUPPORTED` (a receiver without conditional writes answers `CONNECTOR_INCAPABLE`, which comes first and alone); reconcile and superseded stay open. A write needs a history because a move made outside the feed shows nowhere else, and because the verifier reads the operation there: a resend to a receiver without one could only end `failed`, after the write. An endpoint that does not mention `history` takes the entry's own `features.history` (6.4), and neither saying so means none. An encounter read (200) whose `history` is not an array answers unknown, `HISTORY_UNREADABLE`, even from a receiver that offers one; a 404 for an admission has no history to read. The connector is the second line: it refuses to send a dry run to a receiver whose site profile entry declares `dry_run: false` (outcome `refused`, reason `dry_run_unsupported`, nothing sent), and the case then blocks at the rehearsal as for any refusal.

- `POST /downstream/api/capabilities` `{"conditional_writes": false}` is the demo switch (demo instances only, like the reset, and with `Downstream_Admin`, v1.39): afterwards any operation that carries `expected_version` is refused with 422 `{"error": "unsupported_precondition"}`, and the read says `"conditional_writes": false`. `{"conditional_writes": true}` restores it; the reset restores it too.
- `epoch` is an integer that increments at every reset. It appears here, in every encounter read (`"epoch"` beside `"version"`) and in every receipt. An approval binds the epoch it was given, so an approval from before a reset cannot authorise a dispatch after it even when the version numbers happen to match. An approval under an incident binds the plan's epoch.
- `last_contract_check` is whatever the downstream system recorded last (the HTTP check writes it); null when never run.
- `POST /downstream/api/capabilities` also takes `last_contract_check` as `{"at": "<ISO 8601 UTC>", "result": "<text>"}`, both fields required (v1.5): the test tools write it after a contract check. Any other field is refused with 422 `{"error": "invalid_request"}`, and nothing changes when any part of a request is refused. On an instance that is not a demo the POST answers 403 `{"error": "not_a_demo_instance"}`.

### 1.9 Receipt lookup unavailable (v1.4)

Fault mode `receipt_lookup_unavailable`, with an `operation_key`: `GET /downstream/api/receipts/{key}` answers 503 `{"error": "ward_unavailable"}` for that key while the commit, the encounter read and the history stand. It shows that the absence of a readable receipt is not evidence that nothing was committed: the gate's effect check answers unknown, and no write is dispatched.

### 1.10 Roles and credentials

The web application `/downstream/api` requires password authentication and the resource `Downstream_API` (the role of the same name carries it, created by the downstream system's installer; the production's credentials hold it, the demo users operator, approver and demo do not, corrected v1.39); the demo controls take `Downstream_Admin` as well (1.5, 1.7, 1.8), which no role of Shutter's holds, so an administrator (%All) or a role a site gives both resources calls them. The production reaches it through an `EnsLib.HTTP.OutboundAdapter` with the Ens credentials entry `DownstreamAPI`.

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
| `bed` | the bed component PV1-3.3, prefixed by the room PV1-3.2 when one is given (`BAY1-01`: beds are numbered within a bay, and a bed is named within its ward), for `admit` and `transfer`, at most 64 characters; null otherwise, and null when PV1-3 names no bed component (v1.28). Beside the canonical payload, so no digest changes; the ward message sends it to the receiver (1.1), the case keeps it (`bed`) and the headline names it |
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
- PID-3 `MRN1001^^^HOSP^MR~9991001018^^^NHS^NH` (v1.19): the hospital number, typed MR, which Shutter keys on, then an NHS number, typed NH, from the 999 range kept for test data with a valid modulus 11 check digit; the model view gives it a token (`NHS-T1`) and `tests/privacy_check.py` fails when one reaches a recording or the demo's agent output. PID-5 synthetic names (no real people); PID-7 a date of birth; PID-8 a sex code.
- PV1-2 `I`; PV1-3 `WARD-A^BAY1^01^HOSP` (point of care, room, bed, facility), the patient's location as the PAS holds it after the event, on the A08 and A03 too (v1.19: an update names the current ward and a discharge the ward left); PV1-6 on a transfer, the location the PAS moves the patient from (a transfer after an earlier transfer is from the earlier one's ward, whether or not the downstream system took it); PV1-19 `ENC-1001`; PV1-44 the admit time.
- Free text that must reach the agents as data (the injected instruction in S4) goes in an OBX segment after PV1, `OBX|1|TX|NOTE^Transfer note^L||<text>||||||F`, which the ADT_A02 structure allows. No NTE segments in A02.
- Every scenario's timeline is one patient and one encounter, except S9 (v1.5): its third message opens a second encounter of the same patient, `ENC-2009`, listed as `expected.other_encounter`, which the recovery must leave untouched. Since 6 Nov 2026 its plan must name that visit (`expected.names`): an out-patient attendance doesn't stop a resend and shows on the plan. S27 and S31 have a new in-patient admission on a second visit, which does stop it. Admit to Ward A applied; the 09:20 transfer to Ward B fails; at 09:30 the same patient is registered for an outpatient clinic under another visit number (v1.19: an ADT^A04 with PV1-2 `O` and PV1-3 `OPD-3^ROOM2^^HOSP`, indexed and not delivered, since an inpatient has one open spell; it was an A01 to Ward C). That attendance belongs to another encounter and supersedes nothing: the transfer is still due. Times are the same day, `2026-10-15`, 09:00 onwards, except S21 (v1.19), played on Sunday `2026-10-25`, the night British clocks go back: its transfer is timed 01:30 local with no offset, an hour that happens twice, so the matcher's `event_time` is `clock_change` and the gate blocks any write (`EVENT_TIME_IMPLAUSIBLE`).
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

Step kinds: `file` (drop the file into the ADT In folder; `expect` is `delivered` by default, `delivery_fails`, `withheld` (a merge or a cancel Shutter withholds, which opens a case, as in S15 and S16) or `indexed` (v1.19: the HL7 index records it and nothing is delivered, as S9's outpatient attendance); it describes the step for a reader, and the runner does not check it; with `"route": "hospital"` (v1.16) the file goes into the demo hospital's inbound folder instead, so the failure happens in `Hospital.Production` and reaches Shutter through its forwarder, as S19's does; with `"route": "fhir_ward"` (v1.64) the file goes into the demo hospital's FHIR ward feed (`FHIR Ward In`, the folder in `^Shutter.Config("fhirWardIn")`), whose stock HL7 TCP operation `FHIR Ward Out` never opens a connection (port 6662 on the loopback interface, `FailureTimeout` 0, `AlertOnError` 1), so the failure reaches Shutter through the hospital's alert intake (`Ens.Alert`, section 11) and the case runs in the site's watched mode (6.3), as S35's does. With the feed not installed the run ends at the step with the error "the step's route is the demo hospital's FHIR ward feed, which is not installed (^Shutter.Config("fhirWardIn") is not set)"), `fault` (section 1.5, with an optional `operation_key`), `wait` (`seconds`). The runner leaves at least two seconds between files so the production applies them in order. Two more (v1.4 and v1.5): `wait_for_state` (section 4.1), and `capabilities`, an object the runner applies through `Downstream.Service.SetCapabilities` in process (section 1.8; no `Downstream_Admin` is needed), as S10 does with `{"capabilities": {"conditional_writes": false}}`; and `manual` (v1.17, section 4.3), a change a person enters in the downstream system by hand. Besides the outcome, `expected` may name `modes` (the run modes the scenario is defined for; the others are skipped), `blocked_by` (a reason code the case meets on the way, in any round), `source` (v1.16: `namespace`, `production` and `route` a forwarded case must name, section 11), and `final_reason` and `last_operation_key` (v1.17, section 4.3); and `by_mode` (v1.19), a mode's additions to the expected outcome, as S21's rules mode adds the gate's block that site policy, escalating on E13 before any write is planned, never meets.

## 4. The scenario runner

`Shutter.Scenarios.Runner`, class methods marked `SqlProc` so the app and the scripts can call them through SQL:

- `List() As %String`: the scenarios as JSON (the `scenarios.json` content with the fixture files resolved).
- `Run(scenario As %String, mode As %String = "board") As %String`: resets the downstream system (section 1.7), sets the run mode for the case workflow (`board`, `single`, `rules` or `policy`, by writing `^Shutter.Config("mode")`) and the running scenario (`^Shutter.Config("scenario")` = the scenario id, which the case intake stamps on the case, so that recorded agent runs replay by scenario on any instance, and `^Shutter.Config("scenarioRun")`, the same id, which only this runner sets, so that a case opening under it records `ScenarioRecorded` for the gate's Rules only exemption), then executes the steps: faults through the downstream API, files copied into the production's inbound folder (`^Shutter.Config("adtIn")`, set by `Shutter.Setup`), waits. Returns JSON `{"scenario": "S1", "started_at": "…", "files": [...]}`. It does not wait for the case; the production and the app do the rest.
- `Reset() As %String`: the downstream system's reset, the inbound and archive folders emptied (the demo hospital's too, when it is installed), `^Shutter.Config("mode")` back to `board`, `^Shutter.Config("scenario")` and `^Shutter.Config("scenarioRun")` cleared, the live hospital's bed map cleared unless a story is playing (4.4), the answer's `live` saying `cleared`, `playing`, `none` (v1.39) or `not cleared` (v1.42: the map could not be touched, which leaves the rest of the reset whole), and `^Shutter.Config("resetAt")` set to the ISO UTC time of the reset. Since v1.64, where `FHIRFacade.Service` is compiled and `FHIR Ward Out` is a FHIR receiver in the stored site profile (6.4; the demo install's, S35), the reset also resets the test FHIR server and seeds it from `fixtures/fhir/seed.json` (the Locations `ward-a` and `ward-b`, the Patient `pat-1035`, the Encounter `enc-1035` at version 1), revokes every approval not yet revoked whose case has a FHIR binding and is not closed ("system: scenario reset", so `FHIR Out` refuses it as `fhir_approval_void`), and marks every one-write fence row (`Shutter.Store.FHIRAttempt`) that was sent and has no outcome `uncertain` ("the test FHIR server was reset by the scenario runner while this update's answer was outstanding"); an unsent row needs nothing, its approval being revoked. That part answers under the existing `receivers` member, `receivers["FHIR Ward Out"]` = `{"reset": true, "seeded": 4, "revoked": n, "settled": n}` (with an `error` text added when a part failed, and `reset` false when the server could not be reset), so the reset's JSON keeps its shape and `docs/api/openapi.json` (`ScenarioReset`, whose `receivers` has no schema) is unchanged. The FHIR ward feed's folders (`fhirWardIn`, `fhirWardArchive`) are emptied with the demo hospital's. Encounter ids are fixed per scenario, so the evidence collector ignores message-store events older than `resetAt`; the downstream system's own history is per run already.
- The runner may call `Downstream.Service` in process for the reset, the faults, the capabilities and a manual step's operation (4.3); the production always goes through HTTP.
- Settings the runner reads, set by `Shutter.Setup`: `^Shutter.Config("fixtures")` (the fixtures directory), `("adtIn")`, `("adtArchive")`; and, set by `Hospital.Setup` when the demo hospital is installed, `("hospitalIn")` and `("hospitalArchive")`, and since v1.64 `("fhirWardIn")` and `("fhirWardArchive")` for the FHIR ward feed (S35). The ADT In service and the hospital's PAS In and FHIR Ward In take `*.hl7` and archive what they have read.
- The run mode (`board`, `single`, `rules`) is the investigation mode. Whether agents run live, record or replay is the production's setting on the agent items, independent of it.

**The API mimic (v1.17).** A test fixture in `tests/mock` (in neither IPM module nor the image) answers the live runner's model calls without a model, so AI Hub's own agent loop, tools, policies, sessions and the Visual Trace run at no cost. `Shutter.Mock.Setup_Enable()` creates the web application `/shutter-mock` (an OpenAI-compatible chat completions API that answers loopback callers only), the Config Store configuration `AI.LLM.ShutterMock` (provider `openai`, a `base_url` at that application, a placeholder key) and the switch `^Shutter.Config("aihub","mock")`, which `Shutter.Setup.MockConfig()` returns; `Disable()` removes them, and a failed `Enable()` removes what it had made and clears the switch, so the mimic is on or off and never half set up (v1.21). **The switch counts on a demo instance only (v1.21):** where `^Shutter.Config("demo")` is not set, `MockConfig()` answers `""` whatever the global holds, so every reading of the switch (the mode an item resolves to, the run's spec, `RecordAgentMode`, `GET /settings`) ignores it, and `Enable()` refuses there. Whenever the switch is set, the production's start (`Shutter.Production.OnStart`) logs a warning saying whether it is honoured (a demo) or ignored (a site), and `Shutter.Setup.Doctor()` reports it as `mock_config`. While the switch is set on a demo:

- an agent item set to `auto` resolves to `live` (`Shutter.Bridge.Operation.Agent.ResolveMode`), whatever the instance's recorded mode; an item's explicit mode stands, and switching the mimic off brings back what the instance says;
- the live runner sets the mimic's provider on the agent before `%Init`, so the agent class's own `AI.LLM.Shutter` is never read, with the run's context as the API key (`smk1.` and base64url JSON: the replay key, the case, the member, the terminal tool and the production message); a provider that cannot be made fails the run, and no other provider is tried. That `%Init` leaves a provider set before it alone is proven by the mock's `SelfTest` on build 154, not documented by the framework, so after `%Init` the runner checks that the agent's provider is still the one it set (the mimic's, or an item's `ProviderConfig`) and otherwise ends the run with status `error`, `The agent replaced the runner's provider`, before any model call (v1.21);
- the switch is read once per run, by `Shutter.Bridge.RunSpec.FromRequest`, which resolves the mode with that reading and keeps it in the spec's `MockConfig`; the runner follows the spec, not the switch, so a run resolved under the mimic goes to it (or fails) even if the switch goes before the run starts;
- every run is labelled model `mock` with `ProviderConfig` `ShutterMock`, its `CostUSD` is 0, and `GET /costs` counts it in `totals.mockRuns`, not in `liveRuns` (the production reviews' agent runs are counted apart, `totals.reviewRuns` and `byReview`, 13.5); `GET /settings` says so (v1.21): `mock` true, `mockConfig` the configuration's name, `mockModel` the model id sent on the wire, and each agent item that resolves to `live` carries `answeredBy: "the API mimic"` (`effectiveMode` stays `live`, the mode the runs record, so the Settings page, the runs and `/costs` agree). With the mimic off, `mock` is false, `mockConfig` and `mockModel` are empty, and a `live` or `record` item's `answeredBy` is its provider configuration (the item's `ProviderConfig`, under `AI.LLM` when it has fewer than three parts, else the instance's `AI.LLM.Shutter`); a replaying item has none;
- record mode is refused: the runner answers status `refused`, `RecordAgentMode("record")` answers `refused: the API mimic is on` and leaves the mode as it was (the production's start logs that answer when `SHUTTER_AGENT_MODE` asked for a mode it did not get, v1.21), `Shutter.Bridge.Record.Store`, `ImportJSON` and `ImportDir` refuse a recording the mimic answered (`Record.IsMock`: model `mock`, or a response whose `model` is `mock` or whose `provider_config` is `ShutterMock`; `ImportJSON` answers `ERROR: ...`, `ImportDir` a failed status naming the file; the imports since v1.21), and `scripts/check-records.py` fails on a recording file whose `model` or `response.model` is `mock` or whose `provider_config` is `ShutterMock`.

The mimic replays the member's recording turn by turn when the case's material facts (scenario, event, catalogue entry, outcome, matches and conditions, the receiver's version and state, the receipt, conditional writes and the specialists' dispositions) are the recorded case's, and otherwise answers from the catalogue match the evidence carries; every text it writes starts with `[mock]`. How to use it: `tests/mock/README.md`. The mimic does not answer production review runs (v1.22, section 13): `Shutter.Mock.Turns.Heading` has no `review` entry, so a run of `Shutter.Agent.Review` under it is refused as `context_mismatch`, and the review's tests run with `agent: false` or in replay against a recording.

The live runner's `TestRun(case, member, mode, budget)` (v1.21), a check over SQL, takes mode `live` or `record` only (`{"error": "mode must be live or record"}` otherwise, so a replay never runs live by mistake), keys each run's tool calls `test:<case>:<member>:<n>` with a counter, one key per run (`run_key` in its answer; a member's runs are found with `LIKE 'test:<case>:<member>:%'`), says in `mock` whether the mimic answered. Since 1.4.6 the day's budget admits it as it admits the Agent item's runs (`Shutter.Bridge.Runner.Diagnostic`, `Budget.Admit`, charged to the SQL caller): refused, it answers `{"error": <the refusal's words>, "status": <the status>}` before any provider is contacted, the status being `budget_exhausted` or, since 1.4.7, `budget_busy` when the budget could not be checked in time (9); admitted, what it spent or that it failed is recorded as an `AgentRun` row with `Purpose` `diagnostic` and no case, snapshot or question (`run_id` in its answer), which the day's spend, the caller's share and `GET /costs` count and no case's runs, events or counts read, and its reservation is settled once that row is saved.

An agent item's `ProviderConfig` (v1.17) names a Config Store configuration resolved as the agent class's `@{config:...}` is (a name of fewer than three parts is under `AI.LLM`, secrets resolved) and is made with `%AI.Provider.Create`, before `%Init`; the run's model is the item's `Model`, else the configuration's `model`, else the class's. Build 154 has no `%AI.Provider.CreateFromConfig`, which the runner called before.

**Two receivers** (v1.25). The production feeds every receiver the site profile lists (the demo: the bed manager, Downstream
Out, and the patient records system, Records Out, each a connector and a feed process), so one message makes one delivery
per receiver, and **a case is one failed delivery to one receiver**: the open-case lookup is by operation key and receiver
(`Shutter.Store.Case.FindOpen`), the evidence, the rehearsal, the preflight read and the write go to the case's receiver
(`Shutter.Process.CaseWorkflow.WardTargetFor`), and the incident detector already groups by receiver. A fault step names
the receivers it applies to, `{"fault": "fail_before_accept", "receivers": ["Downstream Out", "Records Out"]}`; without the
list it applies to the bed manager alone, so S1 to S21 keep their meaning. The reset resets every receiver whose entry
names a demo namespace (6.4), and its answer lists them under `receivers`. A scenario's expectations may be given per
receiver under `expected.by_receiver` (`scenario_check.py` reads them); `expected.modes` names the modes the scenario is
played in, and a scenario played in policy mode only needs no board recordings. S22, "One overtaken transfer, two
systems", fails the same 10:20 transfer at both receivers after the admission and before the 10:45 transfer applies at
both: the bed manager's case (category `current_state`) closes superseded with no write (E1 preferred); the records
system's case (category `history_of_record`) escalates with the correcting steps (E1 alternative 1, `correct_history`).

## 4.1 Scenario steps that wait (v1.4)

A step `{"wait_for_state": "awaiting_approval", "timeout": 120}` makes the runner wait until the newest case of the running scenario reaches that state, or one of several separated by `|` (S26), or the timeout passes, which the runner reports. The runner reads the case in the same namespace:

```sql
SELECT TOP 1 State FROM Shutter_Store."Case" WHERE Scenario = ? ORDER BY ID DESC
```

Scenario S7 (a later transfer arriving while the plan awaits approval) is written with it. The web app reads case state through the REST API instead (section 5).

## 4.2 Running a scenario from the API (v1.5)

`POST /api/shutter/scenarios/{id}/run` with `{"mode": "board" | "single" | "rules" | "policy"}` (default `board`; 400 `bad_request` for any other value) answers 202 and the run record; `GET /api/shutter/scenarios` carries the current record as `run`. With the production's **Scenario Player** item enabled, the route writes a record in state `queued` and sends an `Shutter.Msg.ScenarioRun` through the `Shutter API` service to the player, which plays the steps in its own job (the same checks and reset as `Runner.Start`) and moves the record through `running` to `done` or `failed`; a run therefore never needs a new process, and it shows in the trace with the cases it causes. A second POST while a record is `queued` or `running` answers 409 `wrong_state`, whoever sends it: one run at a time, a judge's included (v1.57). The player is sent the user who asked (`RequestedBy`), and the run records it for the share (9). **A replay-only run** (v1.58): the route reads in the caller's own process whether the caller holds `Shutter_LiveAgents` and sends it with the run (`Shutter.Msg.ScenarioRun` `LiveAllowed`); `Runner.Begin` takes the caller's own right when nobody passes one. A starter without it (the public demo's role) runs replay only: `^Shutter.Config("scenarioReplay")` says so (the reset clears it), a case the run opens keeps it (`Shutter.Store.Case` `ScenarioReplay`, not in the API's JSON) and carries the line "Replayed: this scenario run was started by a sign-in without the live agents, ..." on its trail from its opening, and every agent request of that case carries `ModeOverride` `replay`, so each agent answers from its recording with no provider call and nothing counted against the day's budget or any share (9), even where the board otherwise answers live; a case with no recording for a member escalates for a person, as a keyless install's does (6.6), saying the run replays and the case has none. A reopening or a board convened on such a case goes by its own requester's right (5). The run record and the 202 carry `replay` (`true` for such a run). The single investigator was never recorded, so a replay-only starter's run in mode `single` is refused 409 `not_recorded`, before anything is queued or reset (`Runner.NotRecorded`, which `Begin` checks too); the app greys that mode out for such a sign-in, as the trial does. Without the player the route calls `Runner.Start`, which uses a background job, or plays inline when none can start.

## 4.3 A change made by hand in the downstream system (v1.17)

When the feed fails, clinicians enter what happened in the downstream system directly. A step `{"manual": {"encounter_id": "ENC-1020", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-15T08:40:00Z"}}` is such an entry: a person on the ward moves the patient in the bed-management system itself, not through the feed. The runner applies it through `Downstream.Service` in process as section 1.1's operation, with `dry_run` false and no `expected_version` (a person's entry is not conditional), its own source system (`WARD`, unless the step names `source_system`) and its own operation key in section 2's form, `WARD^HOSP^MRN1020^ENC-1020^transfer^2026-10-15T08:40:00Z`. The patient is the encounter's own as the downstream system holds it, unless the step names `patient_id` and `patient_id_authority` (an admission by hand must); `event_time` is the step's, or the time the step runs when it gives none; `ward` follows section 1.1. The downstream system applies it like any operation: the version moves, the history records the key and a receipt is stored. A fault set for every operation applies to it too, so a scenario switches its fault off first. Any answer but a 201 fails the run with the downstream system's answer.

Scenario S20 is written with it: S2's start, a `wait_for_state` for `awaiting_approval`, then the nurse's transfer to Ward C at 09:40, while the PAS's 09:20 transfer to Ward B waits for its resend to be approved. Shutter's write is conditional on the receiver's version and its approval is bound to that version, so it can never write over the nurse's entry: at dispatch the fresh read finds version 2 where the approval bound version 1, the gate blocks the dispatch (`APPROVAL_RECEIVER_CHANGED`, `RECEIVER_CHANGED`), the approval is void and the case is planned once more on fresh evidence, whose receiver history shows the later transfer. The re-plan after a receiver change happens once per investigation (v1.21): a second change before the write, found at the dispatch gate or as a version conflict at the write, blocks the case for a person, so a receiver that keeps changing costs at most one more board run; a reinvestigate starts the count again. Rules alone propose the resend again at version 2, and the gate's ordering check blocks it (`SUPERSEDED_BY_LATER_EVENT`, a later event "(receiver history)"): nothing is written and Ward C stands. Two `expected` fields say so: `final_reason`, the code the closed case names (`GET /cases/{id}/blocked-reason`), and `last_operation_key`, the key the encounter's history ends with, here the nurse's own. The expected disposition is `superseded`, as S7's is, with `resend` in `expected.acceptable`: the resend rules alone propose is stopped before it reaches the receiver. S20 is defined for `rules` until the board's runs for it are recorded.

## 4.4 The live hospital (v1.34)

The public demo runs a hospital that never stops. The HOSPITAL production's item **Live PAS** (`Hospital.LivePlayer`, a
business service on `Ens.InboundAdapter` with `CallInterval` 60, disabled in `Hospital.Production`) plays one of Shutter's
scenarios every `EveryMinutes` with fresh synthetic patients at present times and the scenario's faults applied to the
receivers, so the errors are real, and between stories writes one ordinary message a minute (an admission to a free bed, a
transfer, a demographic update or a discharge that frees the bed), so the feed looks like a working hospital. It writes HL7
files into the hospital's own inbound folder (`^Hospital.Config("dir","in")`), where PAS In reads them: the path a real
hospital has. It never resets anything; the scenario runner's Reset (and so every Run) clears the feed's bed map (v1.39), so the ordinary feed admits fresh patients after the receiver forgot the old ones, except while a story is playing (`^Hospital.Live("playing")`, a mark older than 30 minutes counting as a dead job); the player records the receivers a story faulted (`^Hospital.Live("faulted", name)`) before applying them and turns them off at the story's end and at its next job's start, so a story cut off by a restart leaves no fault behind (a storm's own outage is left to run to `receiverDownUntil`).

- **After a start.** The player sends nothing until Shutter's API service is registered (v1.42, `ShutterListening`): the two productions start side by side, and a story's failure sent earlier would get 503 `no_service` from the intake and never open a case.
- **On and off.** The hospital install sets `^Hospital.Config("live")` from `SHUTTER_LIVE=1` and enables the item, and every
  start of Shutter's production applies the container's `SHUTTER_LIVE` the same way (`Setup.ApplyEnvironment`, 12: through
  `Hospital.Setup.SetLive` once the hospital's production runs, from a background job while it is still starting); Shutter's
  install, told the same, sets the shipped profile's policy for tier 2, single chains to `approval` (`Setup.LiveProfilePolicy`;
  decided on 1 Nov 2026), so the live hospital's visitors always have a case to approve; the profile's source then
  reads "(live hospital)" and the seed leaves it alone; a profile a person saved is never touched;
  `SELECT Hospital.Setup_SetLive(1)` (or `0`) in the hospital's namespace switches it without an install. Off, the item is
  disabled and a task that still runs does nothing. The install compiles `Hospital.Production` in the hospital's namespace
  on every run, so an upgrade's new items reach that namespace's production definition before `UpdateProduction`.
- **"Break the feed", the storm** (v1.35). `POST /api/shutter/live/storm` (`Shutter_Operate`, `X-Requested-With`, an
  `Idempotency-Key` honoured, body optional) asks the live hospital for a storm and answers 202 `{stormId, state
  "requested", startedAt, requestedBy, patients 4, movements 8, sent 0, receiverDownSeconds 60, pickupWithinSeconds 5,
  endsAt, cooldownUntil}`; 409 `live_off` when the live hospital is off, 409 `storm_in_progress` `{stormId, startedAt,
  endsAt, state}` while one plays (one at a time for the whole demo), 409 `cooldown` `{until, retryAfterSeconds}` within
  `^Shutter.Config("stormCooldownMinutes")` of the last storm's start (10 by default; the Doctor's `storm_cooldown_minutes`);
  503 `no_service` with no hospital namespace recorded. The route writes the request (state `requested`) in Shutter's own
  namespace, `^Shutter.Live("storm","request")`, since the API's users write nothing in the hospital's database; the
  player (its adapter calls every 5 s since v1.35, the ordinary feed paced by `OrdinaryEverySeconds` 60) takes it on its
  next call into its own record, `^Hospital.Live("storm")` in the hospital's namespace, and plays it: the receiver goes down (`fail_before_accept` on
  `Downstream Out`, 1.5, for `StormReceiverDownSeconds` 60), then eight movements for four fresh patients go out about
  three seconds apart, admissions to free beds first and then each patient's transfer to another ward, control ids
  `STORM<n>-01` to `-08`, each failing in the hospital's production and handed to Shutter by its process as
  `delivery_failed`; Shutter opens the cases (stamped scenario `storm`), the detector opens one incident at the threshold
  and the rest join it, one chain per encounter in arrival order; when the outage is over the player brings the receiver
  back, the incident's recovery check releases the chains in order under the site's policy, and every resend is rehearsed
  and verified. The state moves `requested`, `sending`, `waiting_receiver`, `releasing`, `done` (the incident closed, or
  ten minutes after the press), or `failed` with `error`. `GET /settings` and the Doctor carry `live.storm`: the player's
  record (`stormId`, `state`, `startedAt`, `receiverDownUntil`, `receiverUpAt`, `sent`, `movements`, `patients` as
  `[{mrn, encounterId, ward, toWard, movements}]`, `endsAt`, `endedAt`) with Shutter's own view added (`Setup.StormCounts`:
  `incidentId` and `incidentState`, the incident the storm's cases joined, one the detector opened for them or one already
  open for the receiver, null before any; `cases` and `resolved` for the storm's cases;
  `cooldownUntil`). The rotation and the ordinary feed pause from the press until `done`, and the next story is then due
  `EveryMinutes` later. No model is needed for the story: the chains follow the policy, and a board convenes only where it
  says `board`. Fresh patients and beds mean the storm never collides with a story already playing.
- **Settings** of `Hospital.LivePlayer`: `EveryMinutes` 7; `Scenarios` `S2,S8,S1,S23a,S3,S24,S15`, played round robin
  (empty means every scenario of `fixtures/scenarios.json` but S13, S20 and S21, which need an operator or the records; S11
  is out of the rotation since v1.38, its board chain would convene a board every round, and the storm shows an incident on
  demand); the build's `SHUTTER_LIVE_SCENARIOS` (read at every production start into `^Hospital.Config("liveScenarios")`;
  `default` or no valid id clears it) overrides the setting;
  `Faults` 1; `OrdinaryFeed` 1; `MaxWait` 30, the longest a `wait` step is given; `ShutterNamespace` `SHUTTER`.
- **A story** (`Shutter.Util.LiveFeed`: pure functions over the HL7 text, covered by `Shutter.Test.LiveFeed`). The scenario's
  steps come from `fixtures/scenarios.json` and its files from `fixtures/<S>/` under Shutter's root. Every patient of the
  scenario (PID-3's MR repetition, MRG-1) and every encounter (PV1-19, MRG-5) is mapped once to a fresh one: hospital numbers
  `MRN500001` upwards from a counter in the hospital's namespace, encounters `ENC-<the same number>`, NHS numbers in the 999
  test range with a valid modulus 11 check digit (as `fixtures/generate.py` makes them), a name from two word lists, a date
  of birth and a sex. The times (MSH-7, EVN-2, EVN-6, PV1-44, PV1-45) are shifted by one delta so that the scenario's last
  event is at now in the feed's zone and its intervals are kept; the control id is `LIVE<n>-<k>`; the room of every placement
  (PV1-3.2 and PV1-6.2) is `BAY<100+n>`, a room of the play's own, since the stories' patients are never discharged and a
  repeated room would find its bed taken. A fault step's `operation_key` is rewritten with the mapped patient and encounter
  and the time Shutter will read from the shifted message in the live profile's zone (the fixtures' keys were made in
  Europe/London), so the fault lands on the message meant; `wait` steps are honoured up to `MaxWait`; faults are set through
  `Shutter.Scenarios.Runner.InReceiver` in Shutter's namespace, and every fault the story set is turned off when it ends,
  whatever happened. While a story plays, `^Shutter.Config("scenario")` carries its id, so the cases it opens carry the
  scenario as the runner's do and its suggested conversations apply to them; the ordinary feed clears the stamp. A story's stamp also clears `^Shutter.Config("scenarioRun")`: a story is not a recorded run, so it gets no Rules only exemption.
- **The ordinary feed** keeps its patients in `^Hospital.Live("adm", mrn)` and their beds in `^Hospital.Live("bed", ward, room,
  bed)`: rooms `LIVE1` to `LIVE3` of `WARD-A` to `WARD-D`, beds `01` to `08`. An admission while fewer than 4 patients are in
  (and every third turn while fewer than 24), else by turn a transfer to another ward, an A08 update or a discharge that frees
  the bed. These messages succeed, so they leave no case; one that does carries no scenario.
- **The record.** `^Hospital.Live("played", n)` holds `{scenario, title, at, n, patients, messages[, error]}` per story, and
  `^Hospital.Live("status")` `{enabled, every_minutes, scenarios, last_played, next: {scenario, at}, last_ordinary}`, which
  Shutter reads across namespaces (`^Shutter.Config("hospitalNamespace")`) as `live` in the Doctor and in `GET /settings`,
  for the app's banner; `{enabled: false}` when there is no hospital or no player. Since 1.4.2 a copy of the switch and the cadence alone, `^Shutter.Live("public")` `{enabled, every_minutes, at}` in Shutter's own namespace (`Shutter.Util.LivePublic`), is written by the player on every round, by `SetLive` and the hospital's install, and by `Setup.LiveStatus` whenever it reads the hospital and the copy says otherwise, for a caller who may not read the hospital's database (12). The item logs one trace line per story
  ("Live story n: S with k message(s) for p patient(s)") and a warning when a story or a fault fails.

## 4.5 The pathology paths on the demo (v1.62)

Two optional paths besides the scenarios, on the demo hospital's results route, offered on a demo install with the
hospital (never in the trial, whose outage routes answer `not_in_trial`): **P1**, one ORU^R01 result the demo's results
system refuses, and **P2**, an outage of that receiver. They are `fixtures/pathology.json`, a file of their own, so every
reader of `scenarios.json` (the evaluation, the recordings, the fair test, CI's evaluation step, the live hospital) never
sees them and the scenarios are the same without them (36 at v1.62, 37 since S35, v1.64). No agent runs on them and no model is called.

- **The route** (`Hospital.Production`, category Lab): `Lab In` (`Hospital.Service.LabFeed`, PoolSize 0) sends a result to
  `Lab Results Out`, a stock `EnsLib.HL7.Operation.TCPOperation` on 127.0.0.1 (`FailureTimeout` 0, `AlertOnError`, stock
  `ReplyCodeActions`), which `Ens.Alert` lists beside `Downstream Out`. Its receiver is `Results System In`
  (`Hospital.Service.LabReceiver`, an HL7 TCP service with no target), a stand-in inside the instance that listens on the
  loopback interface only (`LocalInterface` 127.0.0.1), on the port `^Hospital.Config("labPort")` (default 7650, a default
  setting): it answers AA, or AE with "Test code not recognised:
  <code>" for an OBX-3 code outside its list, files nothing, and records each frame it answered in `^Hospital.Lab("heard")`
  (`HeardList()`). It keeps the inbound body with no header, so no outage set ever reads it. A played result gets a fresh
  MSH-7, MSH-10, PID-3 first identifier (a 999 number with a valid check digit) and placer and filler numbers, so two runs
  never share a message or a patient.
- **The profile entry.** `Hospital.Setup`'s install records the three items in `^Shutter.Config` (`labFeed`, `labReceiver`,
  `labListener`) and calls `Shutter.Setup.DemoLabReceiver`, which adds `Lab Results Out` to a demo's profile while its
  source is still the seed's (or the demo's or the live hospital's mark on it), as a new version with that source:
  `orders_results`, tier 3, `watch` on the hospital's namespace, `engine_resend`, `ack_level` `commit` and `duplicates`
  `unknown`. A profile a person saved and a site install get nothing.
- **The steps.** A file step with `"route": "lab"` plays through `Lab In`; `{"lab_receiver": "down"}` and `"up"` switch
  `Results System In` off and on through `Ens.Director.EnableConfigItem`, as the production, only when it runs otherwise.
  Whether it runs is read from the running production (the item's runtime record, `LabReceiver.Listening()`), never from
  the definition's flag; a definition that already says so is put into effect by the update alone, and an update that
  fails puts the definition back, so the two never disagree. A process that may not update the production (`MaySwitch`:
  the interoperability user, `%All`, or USE on `%Ens_ProductionRun` or `%Ens_ConfigItemRun`) changes neither; `{"wait_for_outage":
  "offered", "receiver": "Lab Results Out", "timeout": 240}` waits for the receiver's outage that is not closed to reach
  the state (`|` separates several). Each hospital step runs as a process of its own in the hospital's namespace
  (`LabFeed.Step`), so the Scenario Player's job is never left registered in that production.
- **The run.** `Prepare` finds a path when the route is installed (`LabReady`). `Begin` sets `^Shutter.Config("scenario")`
  and never `scenarioRun` (`Tag`), so a path's cases are tagged and never `ScenarioRecorded`, and the gate's Rules only
  baseline cannot see them; an `orders_results` case goes to a person in every mode anyway. P1: the case at
  `Lab Results Out` escalates with no resend, its findings naming the OBX and the receiver's words. P2: three results fail
  with the stand-in down (each Error, the connection never opened), the stand-in comes back, and the outage (17) offers the
  three; one approval of the existing kind (17.8: the digest, the note, the receiver check, the recovery stop and shadow
  mode) has the engine send them again unchanged.
- **P2's start** is refused, before the reset and with nothing changed, while the demo results receiver has an outage that
  is not closed ("... is still open on the Incidents page: approve its resend or close it there with a reason", or while
  it is `sending`, "... is still sending its approved resend"), and for the receiver's `window_minutes` and half a minute
  after the last P2 run played its results (`^Shutter.Scenarios("pathology", "played")`), so the next outage's window
  cannot list them. `POST /scenarios/P2/run` answers those as 409 `wrong_state` before anything is queued. A start sent again with its `Idempotency-Key` is answered from the key first (1.4.7), before this refusal and before the recording check, so the retry of a start that began is given the first reply and not the refusal that the first start's own outage would raise; a start with a new key is checked as before. No start and no
  reset closes, changes or deletes an outage, its events, its readings or its ledger (17.7 stands); a person finishes or
  closes the last run's outage on its card.
- **The reset** switches `Results System In` back on when it does not run (a P2 run cut short) and the caller may update
  the hospital's production, and says so as `lab` (`on`, `already on`, `none`, or `not switched: ...` with why). Every
  run's start resets as the Scenario Player, which may, so the next run of any scenario or path puts it back. `POST
  /scenarios/reset` runs as the person who asks (an operator or an approver; judges and the demo sign-in may not reset),
  who may not: it answers `not switched: this sign-in may not update the demo hospital's production; ...` and leaves the
  stand-in, its definition and a P2 run in play as they were. That reset does not wait for a run in play: during P2's
  down window it leaves the stand-in down, and P2's own `up` step brings it back. Nothing else.
- `ListPathology()` lists the paths; `GET /scenarios` carries them as `pathology` (an empty list where the route is not
  installed), each with `kind` `pathology`, `latestCase` as a scenario has it and `latestOutage` (`{ "id", "state",
  "openedAt" }` of the receiver's newest outage, for P2; otherwise null).
- **A path's waits** read only the cases its own run opens (`WaitForState` with the newest case row before the run), since
  a path's cases keep its tag from one run to the next.

## 5. The REST API for the app

The API as built is `src/Shutter/API/Dispatch.cls` (its UrlMap lists the routes; sign-in through `POST /session` and the CSP session cookie, and `DELETE /session` signs out and ends the IRIS session, so the licence connection the sign-in took is freed with that request rather than at the application's timeout (1.2.0); every change carries `X-Requested-With: Shutter`, the idempotent ones an `Idempotency-Key`; errors are JSON with `error` and `detail`). The web application's notes on using it are in `web/README.md`. Workflow tasks come back in camelCase with ISO 8601 UTC times (v1.5).

**Who may call what** (v1.17). Every route checks the caller's resources on the server: 401 `unauthenticated` when no
one is signed in, 403 `forbidden` (detail "This needs <resource>") without the resource, and 403 `csrf` for a change
without `X-Requested-With`. The installer's roles hold them: `Shutter_Operator` has `Shutter_Operate`,
`Shutter_Approver` has `Shutter_Operate` and `Shutter_Approve`, `Shutter_Forwarder` has `Shutter_Intake`. The three
also hold SQL SELECT on Shutter's schemas (`docs/INSTALL.md`; since v1.39 the public demo's `Shutter_Demo` and `Shutter_Judge` hold it too, since they read the same routes), so a cached query the API has to compile again in the
caller's process passes; the operator and the approver read the watched hospital's databases too, and since v1.42 write its data database and the demo records system's, since their Reset clears the live feed's bed map and resets that receiver. `Shutter_Demo` and `Shutter_Judge` only read the hospital's.

| Resource | Routes |
| --- | --- |
| none | `POST` and `DELETE /session`; `GET /health` (its summary; the full report needs `Shutter_Operate`) |
| signed in | `GET /me`, which answers `{username, operator, approver, can: {operate, approve, configure, scenarios, reset, liveAgents, stopRecovery}}` from the resources the user holds (`can` since v1.34: the app shows only what the user may do; `scenarios` is `Shutter_Scenarios` and, since v1.57, `reset` is `Shutter_ScenarioReset`, so the app shows a judge Run on and Reset off; `liveAgents` is `Shutter_LiveAgents`, below); `GET /access` (v1.2.0), what each role Shutter installs may do beside what the caller may, for the Settings page's Your access table: `{demo, portalHardened, read, recordedAt?, roles: [{role, installed}], rows: [{id, needs, available, roles, you}]}`, read only, naming roles and resources and never a user (`Shutter.API.Access`; the roles' columns from Security.Roles for a caller with `%Admin_Secure`, `read` `now`, otherwise from the record the install, the portal's hardening and each start write, `recorded` with `recordedAt`, or `none` before any) |
| `Shutter_Operate` | every other `GET`; `POST /cases/{id}/bundle`; `POST /cases/{id}/preview-blind-resend`, `/reinvestigate` (v1.39: the reopened case's agent runs count against the requester's share, and without `Shutter_LiveAgents`, or while the provider refuses the key, they answer from recordings only, `ModeOverride` `replay` as a question's do in 14, and a board with no recording leaves the case escalated for a person, with the reason, and plans nothing; the 202 `{caseId, state: "reopening", requestedBy, liveAgents}` says which) and `/close` (unless the site keeps the two-person rule, below); `POST /cases/{id}/escalations`, `PATCH /cases/{id}/escalations/{seq}` and `POST /cases/{id}/escalations/{seq}/send`; `GET /production-reviews`, `GET /production-reviews/targets` and `GET /production-reviews/{id}`; `POST /production-reviews` (section 13: the review reads only; its agent part takes `Shutter_LiveAgents`, below, and is skipped without it); `GET /cases/{id}/whatif`, `GET /cases/{id}/questions`, `GET /cases/{id}/questions/suggested`, `GET /cases/{id}/questions/{qid}` and `POST /cases/{id}/questions` (section 14: a question reads only, and a live run spends model credit); `GET /settings/schemas` (section 12) |
| `Shutter_Approve` | `POST /cases/{id}/approvals`; `POST /incidents/{id}/approvals` and `/incidents/{id}/chains/{seq}/approvals`; `POST /cases/{id}/close` where the site profile's `approvers.close_needs_approver` is true; `POST /cases/{id}/abandon` (always an approver's); `POST /cases/{id}/further-release` (6.5); `POST /cases/{id}/bundle-unredacted` |
| `Shutter_Scenarios` | `POST /scenarios/{id}/run` (v1.34: the demo controls; the operator and approver roles hold it, since v1.57 the role `Shutter_Judge` too, and since v1.58 the public demo's role `Shutter_Demo`, whose runs replay, as it has no `Shutter_LiveAgents` (4.2); on an instance that is not a demo, `^Shutter.Config("demo")` 0, the route answers 403 `not_a_demo_instance` and changes nothing). A run is one at a time (409 `wrong_state` while one is queued or playing, 4.2), and the cases it opens carry who started it, so their live agent runs count against that user's share of the day's budget, as a convened board does (9, v1.57); a starter without `Shutter_LiveAgents` runs replay only, with no model call and nothing spent, and is refused the single investigator, 409 `not_recorded` (4.2, v1.58) |
| `Shutter_ScenarioReset` | `POST /scenarios/reset` and `Shutter.Setup_PurgeStore` (v1.57: resetting the shared demo and emptying its store were `Shutter_Scenarios` before; the operator and approver roles hold it, the roles `Shutter_Judge` and `Shutter_Demo` do not, so one judge never clears the demo under another; on an instance that is not a demo the reset answers 403 `not_a_demo_instance` and the purge refuses, changing nothing). An install or an upgrade creates it and gives it to the operator and the approver, so an upgraded operator keeps resetting; the uninstall removes it with Shutter's other resources |
| `Shutter_LiveAgents` | Spending the model budget (v1.34, the judges): `POST /cases/{id}/board` (the board convenes live on a blocked, escalated or failed case, 14.5), `POST /cases/{id}/questions` running live, the agent part of `POST /production-reviews` (13.5, v1.39: skipped without it, never refused) and a reinvestigation's live runs (v1.39: recordings only without it); without it a question is answered from recordings only, and one with no recording is refused `409 no_recorded_answer` at once. Operators, approvers and the role `Shutter_Judge` (the public demo's role plus this; both hold `Shutter_Scenarios`, the judge's since v1.57 and the demo's since v1.58) hold it; `Shutter_Demo` does not, so a scenario run it starts replays (4.2). Every live run counts against the day's budget and the caller's share (9) |
| `Shutter_Configure` | `PUT /site-profile`; `PATCH /library/{code}`; `POST /settings/schemas` (section 12); `GET /settings/namespaces` and the routes under it (11.1; an apply and a removal need `%Admin_Manage` as well); `POST /production-reviews/{id}/annotations` and `DELETE /production-reviews/annotations/{annotationId}` (section 13) (v1.34: what changes the site; the approver role holds it, the public demo's role does not) |
| `Shutter_StopRecovery` | `POST /recovery-control/stop` (18; operators and approvers hold it, the public demo's roles do not). `POST /recovery-control/clear` needs `Shutter_Configure` and `Shutter_Approve` |
| `Shutter_Intake` | `POST /intake` (section 11) |

So the person on call (an operator) escalates a case and, once the team that corrects the systems has done so, marks
it handled; the escalation is the sign-off. Which agents sit on the board is an approver's change, as the site profile
is. A site that keeps the two-person rule for closing a case by hand says so in the site profile (6.4): then only an
approver closes it, and an operator's `POST /cases/{id}/close` answers 403 `forbidden` with a detail that says the site
needs an approver, before the body or the case's state is read.

**Who decided** (v1.21). The approver of record for `POST /cases/{id}/approvals`, `POST /incidents/{id}/approvals` and
`POST /incidents/{id}/chains/{seq}/approvals` is the signed-in user: the body names no user, and a field that tries to
is ignored. The route assigns the case's or the incident's open Workflow task to that user, writes the body's
`planDigest` into the task's `PlanDigest` form value and completes it; the case or incident workflow then checks that
digest against the plan (6.4, 7.3). The 202 reply carries `approver`. For a signed-in holder of `Shutter_Approve` who is
not a member of the task's Workflow role (`Shutter Approvers`) the route answers 403 `forbidden` with a detail naming
the role, and for a task another approver has accepted in the Workflow inbox 409 `wrong_state` naming them. A decision
that lands while the Workflow engine is still distributing a new task to the role's members (the case awaits approval
from just before the task is sent, so a poller can answer within milliseconds of the task's save) waits up to 2 s for
the engine's worklist row for the user before assigning, and assigns once more if its own row still meets the engine's
(v1.36; before it, that collision was a 409 `wrong_state` carrying the engine's "ID key not unique" error). The same
step from SQL is `Shutter.Util.Workflow.Decide(caseId, action, digest, comment)` (`SELECT
Shutter_Util.Workflow_Decide(...)`): the actor is the SQL session's user, never an argument, the same role check
applies, and an approval with an empty digest is refused (`no_digest`). An approver who decides in the Management
Portal's Workflow inbox pastes the plan digest from the task's message into its `PlanDigest` field; the task's form
starts empty, so pressing Approve without it binds nothing and the case blocks (or the incident's chains are rejected). The body of `POST /cases/{id}/approvals` is `{decision: "approve" | "reject", planDigest, expectedVersion, comment?}` (v1.39, written down): `expectedVersion` is the case's `version` the caller read and is required; 400 `bad_request` for a decision outside the two; 409 `wrong_state` (with `approval` when a decision was already taken) unless the case awaits approval, and also when another decision reached the case's Workflow task first, another approver has accepted the task, or no task is open: two decisions on one task at the same instant are taken one at a time, so one stands, and the other's 409 carries `approval` with the decision, approver and time of the one that stands; 409 `stale_version` with `currentDigest` when `planDigest` is not the current plan's digest, and with `currentVersion` when `expectedVersion` is missing or is not the case's version, so the caller reads the case again and decides on what it sees.

**The case bundle.** `POST /cases/{id}/bundle` (`Shutter_Operate`, `X-Requested-With`; it writes, so it is not a `GET` a link could set off) answers 200 with one JSON file for audit or a support handoff, `Content-Disposition: attachment; filename="shutter-case-<id>-redacted.json"`: `redaction`, alone on the file's first line and starting `REDACTED:`, then `format` (`shutter-case-bundle/1`), `generatedAt`, `generatedBy`, `case` (operational fields and the operation key), `evidence` (every snapshot with its summary and items), `plans`, `gateDecisions`, `approvals`, `attempts`, `verifications`, `receipt` (what `GET /cases/{id}/closure` answers, or null while the case is open) and `notIncluded`. The case's event log, the agents' runs and escalation emails are not in it. Everything passes through the model view (section 9), read from the stored rows, with the same tokens and the map staying in IRIS. Three things go further, since a file leaves with no one to ask: note text stays out whatever `model_content.free_text` says; what a person typed (an approval's `comment`, which becomes `commentPresent`, and a hand closure's or an abandon's reason in `outcome`) stays out, since no map covers it; and a last sweep of the finished object refuses the file if a value of the map is left in a string, a number or a key. Wards, beds, times, message control ids and staff user names remain, and the first line says so. Each file leaves a `note` event on the case, naming who took it and the file's SHA-256; the case's version does not move. A case that cannot be redacted (its message cannot be read, so its names are unknown) answers 409 `not_redactable` with the reason, and nothing is recorded; so does a download whose record cannot be written. A plan's `action` keeps its `type` and `expected_version` as well as what the view's operation allowlist keeps. The digests in the file are of the unredacted rows, so they identify them and cannot be recomputed from it.

**The unredacted bundle.** `POST /cases/{id}/bundle-unredacted` (`Shutter_Approve`, `X-Requested-With`; body `{reason}`, typed by the person, else 400 `bad_request` with `field: "reason"`) answers 200 with the same parts read from the same rows and passed through no view, `Content-Disposition: attachment; filename="shutter-case-<id>-UNREDACTED.json"`: `redaction`, alone on the first line and starting `UNREDACTED:`, which says the file holds identifiable data, then `format` (`shutter-case-bundle-unredacted/1`), `generatedAt`, `generatedBy`, `reason`, `case`, the parts and `notIncluded` (the case's event log, the agents' runs, escalation emails). An operator is refused 403. It calls no model and learns no token. The reason, who took it and the file's SHA-256 go on the case as a `note` event; the case's version does not move, and a download whose record cannot be written answers 409 `not_recorded` with no file. Agents reading the events through the publisher (15) see that a file was taken and not the reason. `POST /cases/{id}/bundle` is unchanged and stays the default.

A download of either kind carries the event ref `bundle:redacted` or `bundle:unredacted`, and the closure receipt's `actors` leave those out, so taking a file doesn't change a closed case's receipt.

`POST /cases/{id}/close` with `{reason}` (v1.14; `Shutter_Operate`, `X-Requested-With`, an `Idempotency-Key`) answers 202 `{caseId, state: "closing", requestedBy, reason}` and sends `Shutter.Msg.CaseClose` to the Case Workflow item: the case resolves with disposition `handled_by_hand`, its state event names the reason and the latest escalation, the current approval is revoked and an open approval task is cancelled; 400 `bad_request` when the body is not a JSON object or `reason` is empty, 404 `not_found`, 409 `wrong_state` unless the case is escalated, blocked or failed, and 409 `stale_version` (with `currentVersion`) when the body's optional `expectedVersion` is not the case's version. Every draft or queued escalation email of the case is cancelled, whatever its seq, so the team is not asked to correct a case already handled, and the state event says how many ("; 2 pending emails cancelled"); a failed one stays failed as history; and no escalation of a case that is no longer blocked, escalated or failed can be edited or sent (`PATCH` and `send` answer 409 `wrong_state`, naming the case's state) (v1.21). It is how a case the team corrected by hand (a withheld merge or cancel, an escalation the PAS team acted on) is closed; `reinvestigate` stays for a correction the receiver's state can prove. The record of a hand closure is the
state event (its actor is who closed it, its time when, its text the reason and the escalation followed, its `ref` that
escalation), the case's `outcome` ("Handled by hand, recorded by <who>: <reason>") and the closure's `closedAt` and
`actors`.

**Abandoning a case the workflow left behind** (v1.21). A case can be left in a working state (detected, collecting, investigating, grouped, proposed, gated, rehearsing, awaiting_approval, approved, executing or verifying) when the answer its workflow instance waits for never comes: a container killed in the middle of a scenario, an alarm or a delivered request lost with it. `POST /cases/{id}/abandon` with `{reason, expectedVersion?}` (`Shutter_Approve` only, whatever the site profile says; `X-Requested-With`; an `Idempotency-Key`) answers 202 `{caseId, state: "abandoning", requestedBy, reason}` and sends `Shutter.Msg.CaseAbandon` to the Case Workflow item, as `/close` and `/reinvestigate` go through it, so the abandon shows in the trace. There a fresh instance fails the case (`Shutter.Store.Case.Abandon`): state `failed`, disposition `abandoned`, headline "Abandoned by <who>. <reason>" (the reason clipped to 200), outcome "Abandoned, recorded by <who>: <reason>. The workflow stopped in <state>; nothing more is sent", the current approval revoked, every draft or queued escalation email cancelled, and an open approval task completed as cancelled (an `approval` event "Approval task <id> cancelled: the case was abandoned"). The record is the state event: its actor is the approver, its time when, its text "Abandoned from <state>: <reason>" (with "; N pending emails cancelled" when any were). The case keeps its `workflowSessionId`, so the trace link still shows where it stopped; the old instance, if it ever answers, finds the case closed and ignores the answer. A failed case reopens with `/reinvestigate`, so a wrong abandon is recoverable. Errors: 400 `bad_request` when the body is not a JSON object or `reason` is empty; 404 `not_found`; 409 `wrong_state` for a closed case (resolved, blocked, escalated or failed), whose detail says a closed case is marked handled (`/close`) or reopened (`/reinvestigate`); 409 `stale_version` with `currentVersion` when `expectedVersion` is not the case's version; 409 `busy` with `{state, inFlight, newestAt, deferred}` while the case's workflow has a message in flight. The in-flight rule (`Shutter.Store.Case.InFlight`): the case's workflow session (for a grouped case, its incident's) is busy while any `Ens.MessageHeader` of the session is Created, Queued or Deferred, or Delivered with `TimeCreated` within the last N minutes; a case with no session yet is busy while its last state event is younger than N minutes. `inFlight` is the count, `newestAt` the newest header's time (the state event's for a case with no session), and `deferred: true` means an approval task is waiting for a person: the case is not stuck, reject the plan through `POST /cases/{id}/approvals` instead (the detail says so). N is `^Shutter.Config("abandonAfterMinutes")`, 15 by default; a value of 10 or less reads as 11, since N must exceed the 600 s board timeout, the longest wait the workflow arms. Age is never judged by `updatedAt`, which a note writes (the start sweep's note, below, would make every stranded case look fresh). The 202 is given before the transition: when the instance moves the case between the route's check and the workflow's transition, the version check refuses the abandon (logged, case unchanged) and the approver re-reads the case and tries again.


**The cases list's query** (`open` since v1.59, `resolved` since v1.60). `GET /cases?state=&scenario=&open=&resolved=&limit=&offset=`
answers `{items, total}`, newest first: `state` keeps the cases in that one state, `scenario` those a scenario opened,
`open=1` leaves out the closed cases, those whose state is `resolved`, `blocked`, `escalated` or `failed` (what
`Shutter.Store.Case.IsClosed` and the app's `CLOSED_STATES` call closed), so what is left is still being worked on or
waits for an approval, and `resolved=0` leaves out the cases whose state is `resolved` and no other, so the blocked,
escalated and failed ones, which are closed and still need a person, stay with the ones being worked on. The four
combine with AND, so `open=1` beside a closed `state`, or `resolved=0` beside `state=resolved`, matches nothing, and
`open=1` with `resolved=0` is `open=1`; any other value of `open` or of `resolved` filters nothing (`resolved=1` does not
list the resolved cases alone: `state=resolved` does). Every filter is part of the query itself
(`Shutter.API.Dispatch.CasesWhere`), so `total` counts the filter's rows and `limit` (50; 1 to 500) and `offset` (0 to
100000) page through the same rows. The Cases page's **Hide resolved** switch sends `resolved=0` and keeps it in its own
address, as it keeps `state`, `scenario` and `page`; choosing a closed outcome's tile or the resolved state there turns
it off, and a blocked, escalated or failed state stays beside it. The page reads 1.4.5's address, `open=1`, as the switch
on, and never sends `open=1` itself. The list's closed-outcome tiles are counted in the browser over the 100 newest cases
(`limit=100`), which the page says when there are more ("7 matches among the 100 most recent cases. Older cases have not
been searched."); its Failed tile takes the abandoned cases off among the 100 newest failed ones, and reads "at most"
when more than that failed, as do the count of cases that need a person beside Cases in the navigation and on Home,
which add that figure.

**What an empty list says** (v1.59; no new field). With no filter on and no case, the Cases page chooses its words from
what the install says of itself, never from its hostname or the signed-in name: the trial (the build, or `?trial`) offers a
recorded scenario; a demo (`GET /health`, `demo` true) offers a scenario, to someone `GET /me` says may run one
(`can.scenarios`), and otherwise says who can; a site (`demo` false) with a namespace in the report's
`watched_namespaces` that is `onboarded`, not `removed` and has its `forwarder` (11.1) says that no failed delivery has
reached Shutter yet, names what it watches and points at Health, naming instead a namespace whose row is not `ok`; a site
with no such namespace whose `shutter_production` is not `Shutter.Production` (shape B, 12: Shutter's items in the site's
own production) says that Shutter's items run there and that a case opens when its HL7 process or a forwarder reports a
failed delivery, and points at Health, never at the Watched namespaces page; any other site with no such namespace says
that no watched namespace reports its failures here, with the Watched namespaces page for someone who may configure the
site (`can.configure`) and Health for anyone else; and when the report could not be read, or has no `demo` or no
`watched_namespaces` (a server before v1.42) and names no production of the site's, it says only "No cases yet." and
points at Health. A site is never told to play a scenario. The page asks for the report only when its list is empty, and
keeps its loader until the report answers.

**Writes and verification on the list** (v1.24). Each `GET /cases` item carries `writes`, the number of its attempts that
reached the receiver and may have landed (outcome `applied`, `already_committed` or `uncertain`, as the case page's receipt
counts them; a refusal, a version conflict or an error is not a write), and `verification`, the outcome of its latest
verification (`verified`, `not_committed`, `unresolved`, `failed`) or `""` when it has none.

**Who made the plan** (v1.18). `GET /cases` and `GET /cases/{id}` carry `planCreatedBy` when the case has a plan: the
current plan's `createdBy`, `run:<id>` for the coordinator's or the single investigator's run, `policy:<entry>` for the
catalogue and the site's policy, `rules` for rules alone, `withheld` for a withheld merge or cancel that no single
catalogue entry matched (no agent runs; a person decides). The cases list shows it as who investigated the case.

**What Technical shows** (8 Nov 2026, the Technical detail). `GET /cases` items and `GET /cases/{id}` carry, each only
when the server has it and read only from what the production already holds (no new stored field): `messageType`, the
source message's type and trigger as MSH-9 gives them (`ADT^A02`, without the structure), read from Shutter's copy of the
message by `sourceHeaderId`; `production` and `sourceItem`, the production and the item the message came in by (for a
forwarded case the forwarding production and its route, `sourceProduction` and `sourceRoute`; otherwise Shutter's
production and the source header's sender); `receiverClass`, the class of the receiver's item, for a case of the feed in
Shutter's own production only; `failedAt`, when the feed reported the failure: the time of the case intake's header in
the case's session for its receiver, ISO UTC to the millisecond; `planVersion`, `planDigest` and `catalogueEntry`, the
current plan's; and on the list's items too, `links` (`visualTrace`, `workflowTrace`), as `GET /cases/{id}` has always
sent them. None of them names the patient: of the message they read MSH-9 only. The cases list and the case header show
them with the Detail switch on Technical, beside the failure's `failureHttpStatus` and `failureReasonCode`, the control id
`sourceMessageId` and the session and header ids; Plain shows none of them.

**The blind-resend preview** (v1.21). `POST /cases/{id}/preview-blind-resend` answers 409 `dry_run_unsupported`, and sends nothing, when the case's evidence shows no readable capability profile or `dry_run` false (a case with no snapshot yet gets the same answer); otherwise 200 `{wouldApply, outcome, reason, encounterAfter, checkedAgainst: {version, epoch}, expectedVersion: null, applied, note}`. `checkedAgainst` is the receiver version and epoch the dry run was checked against (null when the receiver reported none); `expectedVersion` is null because a preview is conditional on nothing; `applied` true means the receiver wrote during the preview and does not honour `dry_run`: the case then carries an `execution` event saying so, an alert is logged, the note says it, and, since nobody released that write, the write goes on the record as an attempt and the case blocks for a person (`WRITE_NOT_RELEASED`; the answer's `state` says so). The preview is not stored as a rehearsal and never satisfies the gate's rehearsal check (6.5); the case keeps a note with the outcome and what it was checked against.

**A FHIR case** (v1.63). A case whose receiver is a FHIR receiver (6.4) has `kind: "fhir_r4"` in the `route` item of its evidence, beside the capability flags that item took from the server's CapabilityStatement and not from the profile (20). The route reports no dry run, so `POST /cases/{id}/preview-blind-resend` answers 409 `dry_run_unsupported` and sends nothing. The plan, the approval and the attempt of a FHIR case carry no numeric `expectedVersion` (it reads empty): the version its one update is conditional on is the Encounter's ETag, a string, sealed with the plan in a `Shutter.Store.FHIRBinding` and tied to the approval when a person gives it (20.1, 20.3). The case's `reason` is the code its stopping event ends with (20.2). No route, request body or status code changes.

### 5.1 Attempts and verification (v1.21)

**The attempt.** One `Shutter.Store.ExecutionAttempt` per dispatch of an approved plan: the operation key, the version the write was conditional on (`expectedVersion`), the HTTP status, the receipt the receiver returned and the outcome: `applied` (201), `already_committed` (200 with the receipt; a 200 with no receipt and no `applied: true` is not a delivery, so it reads as `uncertain`, on the feed too, and the case reads the receipt and the history), `version_conflict` (409; the approval is void and the case is planned once more on fresh evidence), `refused` (any other refusal; the case blocks), `uncertain` (no HTTP answer other than a refused connection, a 504, or another 5xx: the answer was lost and the write may or may not have landed), `error` (nothing was sent; the case blocks with "outcome is unknown"). `GET /cases/{id}/attempts` pairs each attempt with its verification; a verification without an attempt belongs to a non-write disposition (reconcile, superseded).

**The verification.** The Verifier (`Shutter.Operation.Verify`) reads the encounter and the receipt and judges them with `Judge`, a pure function of what was read (`Context`: the disposition, the attempt, the two reads, the later events of 6.1 and the clock), recorded as `Shutter.Store.Verification` with its `detail` (everything judged, with `verdict`, `retry`, `attempt_outcome`, `seconds_since_attempt`, `version_moved`). The outcomes:

- `verified`: the receiver holds what the plan intends. For a resend or a reconcile, the operation is committed: the receipt (200) and the history agree, or, for a receiver that keeps no receipts (6.4), the history shows the operation. For a superseded closure, the stale operation has no receipt and is not in the history, and a later event supports the closure: a later transfer or discharge in the receiver's history, else a later transfer the feed sent whose delivery failed or is uncertain (6.1), else the matched catalogue entry whose outcome is none (`CLOSED_BY_CATALOGUE`), with the encounter still at the version that entry was judged on. A later event in the history with the stale operation there too, and no receipt for it, still closes the case, and its verdict is `committed`: the operation reached the receiver before the later event overtook it.
- `not_committed`: proven. A write whose answer was lost (`uncertain`) shows no sign of being applied: the receiver holds no receipt for the operation and its history does not show it, and the version has moved past the one the write was conditional on by something other than this write, so the conditional write can no longer apply. The text begins "Not committed:". A receiver with no receipts whose history names no operation keys can't show the move was something else, so that reads as `unresolved`.
- `unresolved`: nothing is established. `detail.retry` says whether another read could settle it: true when a lookup failed (no answer, or a status that is neither 200 nor 404 for the encounter, neither 200, 404 nor -1 for the receipt, in a superseded closure too) or when no receipt is there yet inside the settle window after a lost answer ("the write may still be in flight"); false when a person must decide (no sign of the write by the last read, past the settle window with the version unchanged, whose text ends "Nothing shows it was applied; a slower receiver can still commit it"; the receiver no longer knows the encounter; no later event supports a supersession; an encounter that moved since a catalogue closure was judged; a patient-level case; a disposition with nothing to verify).
- `failed`: the receiver contradicts itself or the plan: a receipt whose operation is missing from the history, a receipt or history entry holding other content than the case's operation (another payload digest, ward or bed, unless the receiver's entry says `strict_answers: false`), an acknowledged write (201 or 200) without a receipt and without its history entry, a history entry without a receipt (on a resend or a reconcile), a stale operation with a receipt after all, or a reconcile whose receipt is gone ("Nothing to reconcile: the receiver holds no receipt for the operation, though the evidence showed one"). A contradiction never claims that nothing was committed.

`verdict` is what holds of the operation at the receiver: `committed`, `not_committed` or `unknown`; the words "not committed" are written only when they are the verdict.

**What the case does.** The first verification runs at once after the attempt (a lost answer whose write landed, as S3's 504, resolves on the first read). `verified` resolves the case, unless the attempt has no approval, which is a write the receiver made during a rehearsal: nobody released it, so the case escalates with the headline "Escalated: the receiver wrote during a rehearsal, with no release" (`WRITE_NOT_RELEASED`). While `detail.retry` is true the case workflow verifies again after 10, 20 and 40 s (`MaxRefreshes`, 3: reads at about 0, 10, 30 and 70 s after the attempt, the 70 s read being the first past the default settle window). `not_committed` escalates the case: the approval is revoked (it authorised one write, and that write is spent), the headline is "Escalated: the resend was not committed", and the state event reads "Not verified (not_committed): <summary>. The approval is revoked, and nothing is resent without a person: a reinvestigation plans again on fresh evidence" (block reason `WRITE_NOT_COMMITTED`). `unresolved` with `verdict: unknown` after the last read, for a resend, revokes the approval too and escalates with the headline "Escalated: the resend's outcome is unknown" and "Not verified (unknown): <summary>. Whether the receiver applied the resend is unknown; a person must check at the receiver before anything is resent" (`WRITE_OUTCOME_UNKNOWN`). Any other outcome escalates as "Not verified (<outcome>): <summary>". Nothing is ever dispatched or re-planned from a verification: a person reinvestigates, which collects fresh evidence, makes a new plan and asks for a new approval. The settle window applies to every receiver the site profile describes, with or without a receipt endpoint (6.4).

**A FHIR case's attempt and verification** (v1.63; the flow is section 20). The attempt is written by `Shutter.FHIR.Flow` once per fence row (20.3), as `ExecutionAttempt.Create(case, plan, approval, "", httpStatus, outcome, response, error, .e)`: `outcome` is one of `applied`, `version_conflict`, `refused`, `uncertain` and `error` (never `already_committed`), `httpStatus` the answer's status or 0 when there was none, `expectedVersion` empty because the plan has none, no rehearsal because no dry run exists, and `response`

```json
{"kind": "fhir", "sent": true, "reason_code": "", "diagnostics": "",
 "receipt": {"kind": "fhir", "encounter": "Encounter/<id>", "expected_etag": "...", "response_etag": "...",
             "response_location": "...", "body_digest": "...", "operation_id": "...", "marker_system": "..."}}
```

`Create` copies `response.receipt` into the attempt's `receipt`. `sent` is whether the update left, and `reason_code` and `diagnostics` are the write's (20.3). A fence row that already names its attempt gets no second one. A fence row marked sent whose case stopped before its attempt was written gets one afterwards (`Shutter.FHIR.Flow.Backfill`): the outcome and answer the fence kept, or `uncertain` when it kept none, with an `error` that says it was recorded afterwards.

The verification is written by `Shutter.Operation.FHIRVerify` from `Shutter.FHIR.Judge` (20.4), as `Verification.Create(case, attempt, outcome, summary, detail, .v)`: `summary` is the Judge's sentence unchanged, and `detail` is the Judge's detail with `kind` "fhir", `judge_outcome` (the Judge's own word), `disposition` "resend" and `case_code` replaced by the FHIR code in the table ("" for none). A FHIR verification has no `verdict` key, which the case workflow and the case page read as the other receivers' verdict.

| Judge | `Verification.Outcome` | Case ends | Code (in `detail.case_code` and the event's text) |
| --- | --- | --- | --- |
| `verified` | `verified` | resolved | none |
| `verified_continued` | `verified` | resolved | none |
| `committed_review` | `unresolved` | escalated | `FHIR_COMMITTED_NEEDS_REVIEW` |
| `unknown`, another read asked for | `unresolved` | verifying (read again) | none |
| `unknown`, final | `unresolved` | escalated | `FHIR_WRITE_OUTCOME_UNKNOWN` |
| `not_found` | `not_committed` | escalated | `FHIR_WRITE_NOT_FOUND` |
| `failed` | `failed` | escalated | `FHIR_WRITE_CONTRADICTED` |

Only `verified` and `verified_continued` resolve the case. A result whose `detail.retry` is true is read again before it ends the case, whatever its word (20.4). The Judge's own `case_code` (`WRITE_NOT_COMMITTED`, `WRITE_OUTCOME_UNKNOWN`) is replaced in the stored detail, so nothing keyed on the ADT codes sees a FHIR case.

### 5.2 What to check at the receiver

`GET /cases/{id}/receiver-check` (`Shutter_Operate`; 404 `not_found`, and 404 `not_stopped` unless the case is blocked,
escalated or failed) answers a person's guide for a stopped case, built by `Shutter.Util.ReceiverCheck` with no model call,
no receiver call and no write. It reads the case's own fields, named values of the snapshot, the receiver's line in the site
profile, and TXA or OBR of the stored message. It is an allowlist, never a serialised snapshot: it reads no OBX, no NTE and no
name, and leaves out the failure text and the bed conflict, since a refusal can name the patient in the bed. No gate check,
catalogue entry or plan reads it.

`{caseId, caseVersion, snapshotId, profileVersion, guideVersion, guideDigest, variant, receiverEvidence: read | unavailable,
evidenceNote, receiverRead: {at, state, ward, bed} | null, identity: {patientId, authority, encounterId, receiver, sourceSystem,
messageType, controlId, timeLabel, time, messageRef, sourceRoute, collectedAt}, messageRequest: {kind, summary, note, fields:
[{label, value, source: message | doubtful | unavailable}]}, laterMovement: {summary, source} | null, queueWarning, checks: [{id,
where, compare: [text], meanings: [{answer: present | absent | different | cannot_tell, label, text}]}], siteRunbook: text | null,
unknown: [text], limitations: [text], report}`. There is no verified, safe-to-resend or action field: what a person finds is their
report, recorded in the reason of the existing hand close. A missing value reads "Not available from this message".

`variant`, first match: `withheld` (a merge or a cancel); `document` (MDM^T02: TXA-12, TXA-2, TXA-4, TXA-17) and `result` (ORU^R01:
OBR-3, else OBR-2, ORC-3, ORC-2; OBR-4, OBR-7, OBR-25), with a limitation when the message carries more than one item; on a document
case (11.2) those rows come from the block, by the reader's right, and the stored message is not read, so the number and the status
show, and the type, the test and the times read as missing;
`other_message` (any other message that isn't ADT: general words, no check of its own); `uncertain` (the latest write has no answer);
`already_applied` (a receipt from the receiver naming this operation, or `ALREADY_COMMITTED`, never a matching location); `uncertain`
(the failure's own outcome); `identity_or_time` (unmappable, unreadable, E11, E12, E13, E18, or those gate codes); `refusal`; `history_correction`
(the plan has correction steps); `later_movement`; `manual_compare`. `guideDigest` is the SHA-256 of the versioned words, the class's
`Words` block.

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
| `delivery` | `failed`, `rejected`, `uncertain`, `unmappable`, `withheld`, `unreadable` | the case's failure kind (1.1: 503 and connection failures are `failed`; 409 and 422 are `rejected`; 504 is `uncertain`; a message Shutter could not map to an operation is `unmappable`, v1.9); a merge or a cancel the feed withheld under the site profile or the receiver's entry is `withheld` (v1.14, section 2); a message held because its schema category was not loaded where it was read is `unreadable` (never sent, `receiver_answer: none`), before and after the schema is loaded: the catalogue's entry for a held message proposes the resend, which the gate blocks `SCHEMA_UNKNOWN` until the schema is there (v1.34, section 12) |
| `receiver_answer` | `unavailable`, `timeout`, `duplicate`, `version_conflict`, `refused`, `unread`, `none` | the error item's reason code, else its HTTP status (504 `timeout`, 409 and 422 `refused`, 503 `unavailable`); an uncertain delivery with no code reads `timeout`; the alert intake's code `alert` (11) names no answer of the receiver's, so the status and the outcome decide (v1.39); its code `alert_unread`, for words the intake does not know, reads `unread`, which no entry names |
| `event` | `admit`, `transfer`, `discharge`, `update`, `merge`, `cancel`, `other` | the case's event word (v1.14): the three cancel words fold to `cancel`; an unmapped trigger is `other` (no case carries `register`: a registration is indexed only, or is an `admit`). A withheld case reads `delivery: withheld` and `receiver_answer: none` (no receiver was asked) |
| `receipt` | `present`, `absent`, `unreadable`, `none` | the receipt lookup: 200, 404, anything else (1.9); `none` when the receiver has no receipt endpoint (6.4), which is a fact about the receiver, not a failed lookup |
| `later_applied` | `none`, `cancel_other`, `cancelled`, `merge`, `transfer`, `discharge`, `admit`, `update` | among the applied events for the encounter whose event time is later than the failed operation's (the downstream system's history and the timeline), by precedence: `cancel_other` when a `cancel_*` was applied at or after the failed event's time that reverses another movement (policy version 2026-11-06.1: another kind of event, or another time; no catalogue entry matches it, so it reaches the board or a person), else `cancelled` when the `cancel_*` of this event was applied at its time (v1.14: a cancel carries the time of the event it reverses, and the case's own operation never counts), else `merge` when a merge was applied later, else `discharge` if any was applied later, else `transfer`, else `admit` (a later admission, v1.11), else `update` (an A08), else `none`. Since v1.16 a later transfer the feed sent whose delivery failed or is uncertain as well (a failure the connector recorded, not an indexed message or one in flight) counts as later too, for any failed operation but an admission and only when the case is not in an ordered or interleaved chain (the incident sends a chain's failures in event order); a later discharge that failed does not (the encounter is still admitted at the receiver, and the discharge's own case follows a resend of the earlier movement); and an event whose time is not plausible (the `event_time` rule below) counts for nothing. `Shutter.Catalogue.Matcher.Later` lists these events; the gate's ordering check reads the same list. Each event it lists carries `operation_key` and, when a case was opened for that key, `case_id` (v1.21). The gate's ordering detail and the verifier's closure describe an event in one voice (`Shutter.Catalogue.Matcher.Describe`): `transfer to WARD-C at <time>` or `discharge at <time>`, with ` (receiver history)` when it comes from the receiver, and for a later transfer the feed sent whose delivery failed or is uncertain `transfer to WARD-C at <time>, sent as <key> (its delivery failed or is uncertain; its case C-0000NN recovers it)`, or `its own case recovers it` when no case is known for the key |
| `later_delivery` | `applied`, `sent`, `none` | how the event that gave `later_applied` its word reached the downstream system (v1.21): `applied` when a plausible later event with that word is in the receiver's history or was applied in the timeline, `sent` when the only one is a later transfer the feed sent whose delivery failed or is uncertain (its own case recovers it; the location is that case's to recover whatever its fate), `none` when `later_applied` is `none`. An entry that lists `later_applied: transfer` alone matches both; one that wants only a movement the receiver applied adds `later_delivery: applied` |
| `event_time` | `plausible`, `before_admission`, `future`, `far_from_recorded`, `clock_change`, `later_event_future` | the failed event's time (v1.11, T28): before the admission the message (PV1-44) or the receiver's first history entry names, for anything but an admission; more than five minutes after the message was sent, the engine received it (`received_at`, the header's own time, since one clock stamps the event and MSH-7) or the evidence was taken; more than a day from the recording time (EVN-2); without an offset, and within an hour of a clock change in the feed's zone (`Shutter.Util.Time.NearClockChange`: London by its own rule, any other IANA zone through `zoneinfo`; the order of two events is then not safe); `later_event_future` (v1.16) when the failed event's own time passes these checks but a later event it would be ordered against lies more than five minutes after the feed sent it, the receiver applied it or the evidence was taken, and believing it would change the reading (no plausible later transfer, discharge or cancel settles the order already, the event outranks `later_applied` and it is not an update), so a wrong time could make a genuine failure look overtaken; plausible otherwise. The gate's ordering check blocks a write and a superseded closure on any value but `plausible` (`EVENT_TIME_IMPLAUSIBLE`). Since v1.21 a settled order (a plausible later transfer, discharge or cancel) stands whatever else is doubtful, with one exception: a cancel with a doubtful time behind a settled transfer or discharge is `later_event_future`, since it may have reversed the very event that settles the order (a second doubtful cancel behind a settled cancel changes nothing) |
| `encounter_state` | `admitted`, `discharged`, `not_found`, `unknown` | the downstream system's state; `not_found` when the receiver answers 404 (it does not know the encounter); `unknown` when the receiver can't be read |
| `transition` | `allowed`, `invalid`, `unknown` | the failed event from the encounter's current state (1.4): a transfer after a discharge is `invalid` |
| `patient_match` | `yes`, `no`, `unknown` | the message's PID-3 against the downstream system's patient for the encounter |
| `simultaneous_sources` | `yes`, `no` | an applied movement for the encounter (any event but `update`, which moves nobody) from another source system, within the site profile's `feed.source_skew_seconds` of the failed operation's event time, either way, or at a time that can't be read (S8) |
| `conditional_writes` | `yes`, `no`, `unknown` | the route's capability profile (1.8) |
| `free_text` | `yes`, `no` | the message carries free text (an OBX note or an NTE) |
| `chain` | `single`, `ordered`, `interleaved` | section 7; a case outside an incident is `single` |
| `receiver_category` | `current_state`, `history_of_record`, `orders_results` | the case's receiver's category in the site profile (6.4, v1.23); `current_state` when its entry names none |
| `bed_conflict` | `none`, `occupant_leaving`, `occupant_left`, `occupant_staying`, `unknown` | who holds the bed a `bed_occupied` refusal (1.1) named, from the `bed_conflict` section the evidence adds for such a refusal (v1.28): `occupant_left` (the occupant's encounter is discharged or placed elsewhere now), `occupant_leaving` (a transfer or discharge of the occupant after `since` was sent and not applied: failed, uncertain or pending, in another case when one was opened), `occupant_staying` (they still hold the bed and no movement out is known), `unknown` (no occupant named, or they could not be read, or the refusal named no ward or bed to compare the read with, v1.35); `none` without such a refusal. The fact `occupant_case` names the case about the occupant's movement, or is empty |
| `death_recorded` | `no`, `yes`, `cleared`, `unreadable` | the failed message's PID-29 and PID-30, as the word the evidence's message section carries: `yes` when PID-30 says Y or PID-29 holds a time, `cleared` when either holds the HL7 null, `unreadable` when a read fails, `no` otherwise. The entry that names it (E19) answers alone, whatever else matches, and goes to a person in Board and Site policy mode; Rules only is unchanged. Only this message's own fields are read |

**Flags read per receiver** (v1.23). An entry's `when` names a flag (`history_policy: correct`, `authoritative_source:
other_source`). The matcher's facts carry `history_policy` and `receiver_category` for the case's receiver, from its site
profile entry at evidence time, and `WhenHolds` reads a fact of the flag's name before the profile's site-wide flag, so
the catalogue, the gate and the model view judge the receiver the case went to, as the snapshot recorded it, and a
profile edit later does not flip a decided case.

**Times the matcher reads** (v1.21). The plausibility rule compares an event's time with the time the feed sent it (`sent_at`), the receiver applied it (`applied_at`) and the evidence was taken (`observed_at`). A time in the ISO 8601 UTC form with a `Z` (a fraction allowed) or in the message store's ODBC form (`2026-10-15 09:20:00.123`, written in UTC) is read; a time with an offset (`2026-10-15T10:20:00+01:00`) or in any other form is never read as UTC: a `sent_at` or `applied_at` of that shape skips its own check, as an empty one does, so one receiver's odd clock form never makes every later event implausible, while an event time the matcher cannot read is implausible and supersedes nothing (and raises `later_event_future` when believing it would change the reading). `Shutter_Catalogue.Matcher_ForCase(caseId, chainKind)` evaluates the stored snapshot again for checks over SQL; since v1.21 it takes the case's stored chain kind (`Shutter.Store.ChainItem.KindFor`, `single` outside a chain) when the caller gives none, so it agrees with the stored match for a chain item.

**A schema this namespace does not hold** (v1.32). The conformance check reads the evidence's `validation.schema_known`: a
message whose `DocType` category is not loaded here (a forwarded message naming its source's own schema, a site variant not yet
imported) cannot be validated at all, so the check blocks with `SCHEMA_UNKNOWN` naming the category and the fix, never with
`PARSE_FAILED`; the evidence's `validation` then says `parsed: false`, `error: "unknown schema: ..."`, `schema_known: false`,
`schema_category` and `schema_fix`. A person imports the schema (12) and reinvestigates the case.

**Further messages for the patient** (`Shutter.Util.FurtherMessages`). `ResendGuard` and the matcher read one visit. Before
every write Shutter also reads the patient: any message for the same identifier and assigning authority, on any visit, that
reached the engine after the case's own or is timed after it, sent, queued or pending, from Shutter's index, the newest headers
the index hasn't walked yet, and the HL7 messages of the namespace the case came from (paged to the last header, for at most the profile's `further_messages.scan_seconds` a read). The evidence
carries `further_messages`: `{identifier: read|unreadable, stops: [...], shows: [...], unread}`, each row `{why, event, message_type,
visit_number, event_time, sent_at, control_id, location, where}`. A row stops a write when it is an in-patient movement on another
visit (`why: other_visit`: an A01, A02, A03 or cancel of any patient class but E or O, or an A04 or A05 of class I, unless that A05 was on file before the case's message, which is a date on a waiting list and shows), a change to the record (`record_changed`:
A06, A07, A23, A29, A37, A44, A45, A47, A49, A50, A51), a merge naming the patient on either side, a cancel of this visit the receiver
did not apply (`cancel`), or for an admission outside a chain a discharge of this visit the receiver did not apply (`discharge`).
An `other_visit` row stops only where the site profile says `further_messages.in_patient_movement: stop`; the shipped profile says
`show` (v1.47), so there it goes on the plan as a shown row and stops nothing, and the demo's profile keeps `stop` (6.4).
The gate's ordering check blocks with `FURTHER_MOVEMENT`, naming both visits; `PATIENT_UNREADABLE` when the case has no identifier;
`FURTHER_NOT_READ` when a namespace's read failed or ran out of its time with headers left. These come before `NEWER_MESSAGE_PENDING` in the checks, and the case
blocks for a person at once, with no wait. Any other ADT message for the patient, such as an out-patient A04 or an emergency department's A03, passes
(`NO_FURTHER_MOVEMENT`) and goes on a resend's plan as a precondition line and in the approval task. The gate reads the snapshot
at the proposal and reads again at dispatch, and the connector reads once more at the moment of the write, answering `refused`
with reason `further_movement`. Where `other_visit` rows show, the dispatch gate and the connector also compare the rows they read
with the snapshot's `shows`, by control id and visit: an `other_visit` row the snapshot didn't show reached the engine after the plan
was made, so no approval of that plan covers it. The gate answers `unknown` with `FURTHER_MOVEMENT_NEW`, naming the new visit and the
case's own; the case workflow collects the evidence again as for stale evidence, the fresh snapshot shows the row, its material
digest changes and the approval is revoked, and the case is planned again (a second approval where the policy asks for one). The
connector refuses such a row too (`further_movement`). An admission the receiver answers 404 for isn't released by the site's policy (a 404 doesn't
prove there's no record entered by hand under another number): it waits for a person, and the plan says to check the system's own
screen. Inside an incident too (policy version 2026-11-07.1): the chain goes under the incident's one approval (7.3), whose task asks the same, and a release that still finds a 404 asks a person for that case. A site chooses with `further_messages` (6.4). **What this
can't see:** a change made by hand at the receiver; a message on a route Shutter's index doesn't watch, once the index has passed it;
a further message that lands between the connector's read and the receiver's answer; and a merge of a merge. Nothing holds the feed
during a correction: a hold or a laboratory route can call `Find` as it stands. Proof: S27 to S32, S9, and `Shutter.Test.FurtherMessages`.

**A person releases another visit's stop** (policy version 2026-11-07.1). `GET /cases/{id}/further-stop` (signed in) reads the patient
afresh: `{rows: [{line, visit}], digest, releasable, whyNot, release}`, with `release` `{digest, by, at, reason, stands}` or null. `POST
/cases/{id}/further-release` (`Shutter_Approve`, `X-Requested-With`; body `{digest, reason}`, both required, else 400 `bad_request` with
`field`) takes the digest of the rows the person read and why. It answers 409 `wrong_state` unless the case is blocked, `not_releasable`
unless every row is another visit's movement (`why: other_visit`) with the identifier read and every namespace read in full, and
`rows_changed` when a fresh read gives another digest; otherwise it records who, when and why on the case and sends the case through fresh
evidence (202). The digest is SHA-256 over each stopping row's visit, control id, event and why, sorted, so the same message read from another store
gives the same digest. Each read before the write, the proposal's snapshot, the dispatch gate's and the connector's, passes the stop
(`FURTHER_MOVEMENT_RELEASED`) only when it gives that digest: another relevant message voids the release, and the case stops again with
both rows to read. It covers no unreadable identifier, `FURTHER_NOT_READ`, cancel, merge or change to the record, and releases nothing else:
every other check runs, and the write needs a person's approval even where the site's policy would release it. The approver may be the
person who released. Proof: `Shutter.Test.Gate` and `tests/e2e/further_release_check.py`.

**The failsafe at the point of the resend** (v1.29; the requirement of 26 Oct 2026). A resend is already a conditional
write bound to the version the preflight read, so a PAS message applied at the receiver in between is refused as a version
conflict, and one that lands after applies in order. What the version cannot see is a newer message of the same encounter
inside Shutter's own pipeline: received after the case's own and not yet delivered to the receiver, queued for it with no
answer yet, or indexed and not yet routed. The evidence lists them in `pending_messages` (`Shutter.Util.ResendGuard`:
`[{event, event_time, operation_key, control_id, ens_header_id, sent_at, receiver, where}]`, oldest first, from the feed's
deliveries without an answer and the exact index's rows without a delivery, both after the case's own message's arrival), and
the gate's ordering check blocks a write with `NEWER_MESSAGE_PENDING` while one is pending, and since v1.34 a superseded plan
too when no delivered later event supports it and a message is pending (the later event the plan rests on is still on its
way: the case waits and is judged again, instead of `SUPERSESSION_UNSUPPORTED` sending a person); the case blocks with
`waitsOnMessage` naming the first (its MSH-10 control id), and the connector's answer to that message, whatever it is,
reopens the case on fresh evidence, where the later event now shows as applied, or as its own case, and the gate decides. The
connector checks again at the moment of a recovery write (`Shutter.Operation.Ward`) and answers `refused` with reason
`newer_message_pending` without sending when a message became pending after the gate, so the write never goes first. The
resend itself goes straight to the connector's queue, ahead of feed messages not yet dequeued, so no priority plumbing is
needed. The residual window is a message received but not yet routed and not yet indexed (the index lags a few seconds);
the receiver's version protects that case. Gate policy version `2026-11-01.1` (this change's; the gate is at `2026-11-07.1` since v1.50), so an approval given under `2026-10-26.2` and
not yet dispatched is void at dispatch.

**The occupied bed** (v1.28). For a `bed_occupied` refusal (1.1) the evidence reads the occupant's encounter on the case's
receiver and the feed's deliveries for it (`Shutter.Index.Timeline.Deliveries`) and adds the section `bed_conflict`
(`Shutter.Util.BedConflict`): `{refused, ward, bed, since, occupant: {encounter_id, version, read_http_status, state?, ward?,
bed?} | null, occupant_movement: {event, ward, bed, event_time, operation_key, delivery: applied | failed | uncertain |
pending, outcome?, case_id?} | null, status, note}`; the condition `bed_conflict` is its `status`. The gate's ordering check
reads it for a write: `OCCUPANT_MOVED_OUT` passes (the occupant has left; the resend stays conditional on the case's own
version, and the receiver refuses it again if the bed is held after all), `WAITING_FOR_OCCUPANT_CASE` blocks while the case
about the occupant's movement is still working or the movement's delivery has no case yet, `OCCUPANT_CASE_FAILED` blocks when
that case ended (resolved, blocked, escalated or failed) without freeing the bed, and `BED_OCCUPIED` blocks a write into a bed
whose occupant stays or could not be read (a resend can only fail again or double-book). The workflow turns the first block
into a wait: the case blocks with `waitsOn` naming the other case (5), and when that case closes (`Shutter.Store.Case.Transition`
to a closed state) every case waiting on it is reinvestigated on fresh evidence (`Shutter.Msg.Reinvestigate` through the API
service), so it resends once the occupant has left or escalates at once (`OCCUPANT_CASE_FAILED`) for the bed manager. A
reopening clears `waitsOn`. Gate policy version `2026-10-26.2`, so an approval given under `2026-10-26.1` and not yet
dispatched is void at dispatch.

**The gate's ordering check and the later case** (v1.21). For a write, `SUPERSEDED_BY_LATER_EVENT` blocks on a later applied transfer or discharge, and also on a later applied cancel of the event ("cancel of the event at ..."), merge ("merge at ...") or admission ("admission at ..."), the words `later_applied` counts, so the gate and the matcher agree on all of them; `NO_LATER_EVENT` reads "No later transfer or discharge was applied for this encounter, nor a later cancel, merge or admission". A superseded closure is supported by a later transfer or discharge alone (a cancel there passes through the catalogue, `CLOSED_BY_CATALOGUE`). The verifier reads the same list on the snapshot's timeline and the encounter as read at verification, with the snapshot's observation time and chain kind, so it never cites an event the gate refused: it accepts a later transfer or discharge from the receiver's history, else a plausible later transfer the feed sent whose delivery failed or is uncertain, in the gate's words. When a case closes as superseded on such a transfer and its case is known, that later case gets a note ("Case C-0000AA was closed as superseded on this case's account: its transfer to WARD-B at <time> is not resent, because this case's later movement supersedes it; this case recovers the patient's location"), and the closed case's verification names the key and the case; the patient's location is the later case's to recover whatever its fate, and the two notes are the record.

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
  superseded), `reconcile`, `none`, `escalate`, `resend_unconditional` (never automatic; needs the site flag `unconditional_resend: allowed`, the only value besides `forbidden` the profile validator accepts), `correct_history` (always escalated, with the correcting steps on the plan), `resend_after_occupant` (v1.28: a resend into a bed whose occupant is leaving, which waits for the case about their movement; the policy path's plan carries `waits_on` and the precondition, and the gate holds the write with `WAITING_FOR_OCCUPANT_CASE` until that case closes).
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
- `policy`: the rules below (chosen per run; the installed default, and the mode after every scenario reset, is `board`;
  a failure from a watched production (11) runs in the site's watched mode, `^Shutter.Config("watchedMode")`, `policy`
  unless the site set another, whatever mode the scenarios run in, since v1.38: on the demo the live hospital's cases and
  a storm's are settled by the catalogue and the site profile, and a scenario run or reset cannot flip them to the board;
  `GET /settings` carries `watchedMode`);
- `board`: the board always runs, the match in its evidence; the comparison's board column keeps its meaning;
- `single`: the single investigator always runs;
- `rules`: no agents and no catalogue path: a plain resend for the gate to judge.

In `policy` mode the matcher's decision is:
- **One match, `decides: policy`:** the case takes the site's policy path (6.4) with the entry's outcome. No board. The
  outcome is the preferred one, unless an alternative's `when` names a flag (`history_policy`, `authoritative_source`,
  `unconditional_resend`) that holds for the case's receiver: then that alternative applies (v1.25; the plan names it
  `alternative:<n>` as the board would, and `outcome_ref` in the match says which). `when: always` marks a board option,
  never a policy.
- **One match, `decides: board`, or several matches:** the board runs; the coordinator's plan names `catalogue_entry`
  and `outcome` (`preferred` or `alternative:<n>`) with `why`.
- **One match, `decides: person`:** the case is escalated at once, naming the entry; the board does not run.
- **No match:** the board runs so that the person gets an analysis, and the gate marks the plan `NEW_PATTERN`; the case
  is escalated and flagged as a candidate entry for a reviewer.
- **A withheld case (v1.14), in every mode:** no board and no investigator. One match takes the person path above; otherwise
  the workflow adopts an escalate plan naming the feed's reason, and the gate appends `MERGE_WITHHELD` or
  `CANCEL_UNSUPPORTED`. A withheld message costs no model run, however many arrive.
- **A receiver of category `orders_results` (v1.23), in every mode:** no board and no investigator: the workflow adopts an
  escalate plan, and the gate appends `RECEIVER_NOT_MODELLED`, so nothing is resent from the case. Since v1.51 the case
  carries its findings (who holds the message, the receiver's own words and the result they name) for the person who
  handles it; at a receiver whose entry says `engine_resend`, an outage's messages that never arrived are offered for one
  approval and sent again by the engine (17.8).
- **`correct_history` at a `history_of_record` receiver (v1.23):** the policy path's plan escalates with
  `correction_steps` (section 10, with the drafted sequence's structure from v1.50) and the case carries a note "Correcting the history: ...".
- The matches, with every condition's observed value, are stored on the case (`catalogue` in the snapshot summary) and
  shown in the app.
- Recording keys for replays name the case within its scenario: `scenario:<S>:<encounter>:<event>[:<receiver>]|<member>|<cfg>[|round<n>]`
  (the receiver when it is not the production's default, `Shutter.Production`'s `RECEIVER`, so two receivers' cases of one
  movement record apart and the earlier recordings keep their keys; v1.34). The round suffix counts the re-plans of one
  investigation (a changed receiver at dispatch, a version conflict on the write); a convening after a release, which is a
  reinvestigation, reuses the keys of the first, so a recording holds the latest convening's answers (a known limit, 1 Nov
  2026: S23a's and S24's board recordings keep their second convening's; replays converge because those answers suit the
  first convening too; the snapshot's sequence would make a sound round number at the price of recording them again); The production review's recordings use the form `review:<namespace>:<production>|review|<CONFIGVERSION>|<fingerprint>` (13.6).
  the replay runner falls back to the older `scenario:<S>|<member>|<cfg>` form, which the first recordings use.

### 6.4 The site profile and the policy path

The questionnaire's answers are the site profile (`knowledge/site/profile.json`, versioned; defaults shipped). The core
reads it through `Shutter.Store.SiteProfile`. A non-demo install takes the file through `SiteProfile.ForSite`: the demo's
receivers (`Downstream Out`, `Records Out`) leave it, a list left empty gets one draft to fill in, and every `automatic`
in its policy reads `approval`, so it starts with no automatic release. A profile a person saved is never changed.

```json
{
  "version": 1,
  "receivers": [
    {"name": "Downstream Out", "system": "the demo bed-management system", "category": "current_state", "tier": 2,
     "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false,
     "api": {"base": "/downstream/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}",
             "capabilities": "/capabilities", "operations": "/operations"},
     "features": {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}}
  ],
  "authoritative_source": "",
  "unconditional_resend": "forbidden",
  "merges": "forbidden",
  "policy": {
    "1": {"single": "approval", "ordered": "approval", "interleaved": "board"},
    "2": {"single": "approval", "ordered": "approval", "interleaved": "board"},
    "3": {"single": "approval", "ordered": "approval", "interleaved": "board"}
  },
  "approvers": {"role": "Shutter Approvers", "escalation": "the integration team's on-call",
                "close_needs_approver": false},
  "incident": {"threshold": 5, "window_minutes": 10, "quiet_seconds": 60},
  "model_content": {"free_text": false},
  "feed": {"time_zone": "Europe/London", "prevent_failures": false, "source_skew_seconds": 300},
  "further_messages": {"in_patient_movement": "show", "admission_not_found": "person", "scan_seconds": 30}
}
```

**The shipped policy asks a person at every tier** (v1.47): `approval` for single and ordered chains at tiers 1 to 3, the board for interleaved ones,
whose plan a person then approves. A site that wants a tier released by policy says so in its own profile. **The demo keeps
the earlier table as its own setting:** a demo install (`Shutter.Setup.Install` with `demo` 1) whose profile is still the
seed's stores `Shutter.Store.SiteProfile.DemoPolicy()` (tiers 1 and 2 single and tier 1 ordered `automatic`, tier 2 ordered
`approval`, tier 3 `approval` and `per_chain`, interleaved `board`) with the seed's path and `" (demo)"` as the profile's
source (`Shutter.Setup.DemoProfilePolicy`); the live hospital's rule (4.4) then marks it `" (demo) (live hospital)"` and makes
tier 2 single an approval. The Site profile page labels such a profile "Demo's answers" instead of "Shipped answers". A
profile a person saved is never touched, and a reinstall leaves both marked sources alone, but for one setting: the demo
keeps `further_messages.in_patient_movement: stop`, which a demo install writes into its profile, the live hospital's included
(v1.47), so S27, S31 and S32 stop as they did while the shipped profile says `show`.

(`teams` and `mail`, optional, are in section 10. The shipped seed profile has both: the integration and PAS teams, and
`mail.allowed_domains` set to their mailboxes' domain, `example.nhs.uk`.)

- A tier is the receiver's; a policy is read by tier and chain kind.
- **The receiver's category** (v1.23), asked at onboarding: `current_state` (a bed manager, whiteboard or portering
  system: only the present placement matters, so an overtaken failed movement closes with no write), `history_of_record`
  (a PAS, EPR or clinical data warehouse: the movement history must be complete, so an overtaken failed movement is not
  "no action": the case escalates with the correcting steps on its plan, section 10) or `orders_results` (order
  communications or a LIMS: each order or result is its own record; declared and validated, its cases escalate with their
  findings before any model runs, and the gate blocks every write from a case with `RECEIVER_NOT_MODELLED`; an outage's
  messages that never arrived go again only through the outage resend, 17.8). An entry without a
  category is `current_state`, which is what every profile written before v1.23 meant. `receivers[].history_policy`
  (`current` | `correct`) is derived from the category (`history_of_record` -> `correct`, the others -> `current`) and may
  be set on the entry to override it. The site-wide `history_policy` is deprecated: still accepted, read only for an entry
  with neither a category nor its own policy, and no longer in the seed (profile version 5).
- **A receiver's runbook line** (`receivers[].manual_check.runbook`, optional): one line of plain text, 300 characters at most, on
  where to look at this receiver, shown on its stopped cases as a navigation hint and never as evidence (5.2). No HTML, links,
  credentials, control characters or runs of six digits. It is saved with the profile, and the core reads it as nothing else: no
  command, mapping or capability.
- **A demo receiver's namespace** (v1.25): `receivers[].demo.namespace` names the namespace a demo receiver runs in, where
  the scenario runner resets it and sets its faults (`Shutter.Store.SiteProfile.ReceiverNamespace`); absent, the receiver
  is the namespace's own. The shipped seed (profile version 6) lists two receivers: Downstream Out (`current_state`) and
  Records Out (`history_of_record`, `/records/api`, `demo.namespace` RECORDS), and the PAS team takes Records Out's
  escalations.
- **A gated history correction is planned, not in this version.** It would be a receiver feature `history_correction`
  and an operation (1.1 with `"correction": true`) that inserts the movement into the history at its own time without
  changing the current placement, bumps the version, stores a receipt and honours `dry_run` and `expected_version`; a plan
  disposition `correct` that always needs an approval and a rehearsal showing the placement unchanged; the gate and the
  verifier reading the history for the inserted movement. Practice (IHE PAM) corrects a past movement only through a
  historic-movement update where the receiver supports it, never by resending the original message.
- **A receiver's outages** (v1.47): optional keys on a receiver entry. Each is checked only when present, an entry with none
  of them validates as it always did, and a block whose feature is not in the build validates and does nothing.
  `watch` `{"namespace", "item"}`, both required: the production item Shutter watches, read only; with no `watch` the receiver
  is not watched. `runbook` and `call`: the site's own words, what to do and who to call. `approvers`: an array of names.
  `ack_level`: `connection` (the default), `commit` or `application`, on any category: what a Completed header proves at
  this receiver, as the site declares it. `duplicates` `{"behaviour", "code", "phrase", "refers_to"}`: `behaviour` is `refuses`,
  `files_twice` or `unknown` (the default); `refuses` needs `code` (ERR-3, as a string) or `phrase` (the exact MSA-3 text); `refers_to`
  is `message`, `order`, `result` or `unknown` (the default). `engine_resend` (true or false): true is accepted on
  `orders_results`, on `current_state` or `history_of_record` only beside `ack_level: application`, and never beside
  `resend_timestamp` `rewritten` or the questionnaire's `fresh`, since the stored message goes out unchanged. `hold` `{"minutes"}`,
  1 to 60, default 10: on `current_state` and `history_of_record` only, refused on `orders_results`. `mail` `{"to", "on"}`, both
  required: `to` an array of bare addresses inside `mail.allowed_domains` (section 10), `on` an array of `open`, `needs_person`
  and `closed`. `resend_approval_minutes` (default 15), `settle_minutes` (default 10) and `window_minutes` (default 5): whole
  numbers of 1 or more. `Shutter.Store.SiteProfile.ReceiverWatchProblem` and `validateProfile` in
  `web/src/features/site-profile/profile.ts` give the same words; `tests/unit/Shutter/Test/ProfileWatch.cls` holds the one
  table both run. The readers `WatchedReceivers`, `ReceiverAckLevel`, `ReceiverDuplicates`, `ReceiverMinutes` and
  `ReceiverHoldMinutes` give the defaults.
- **The receiver description** (v1.8): each receiver entry carries `api` (its `base` path and the paths of its `state`,
  `receipt`, `capabilities` and `operations` endpoints, with the placeholders `{encounter}` and `{key}`) and
  `features` (what the site declares it can do: `conditional_writes`, `receipts`, `history`, `dry_run`). The evidence
  collector, the verifier and the connector read their paths from the entry named by the case's receiver (the
  production item that delivered to it), so a second receiver is configuration, not code. Given an `api`, its `state`
  and `operations` paths are required; a `receipt` or `capabilities` path left empty means the receiver has no such
  endpoint: no receipt lookup, and the capabilities are the declared features, which the route item records as
  `capabilities_source`. A second entry with a name already taken is refused (`.name: must be unique`). An entry with `features` and no `api` is a receiver with no API of its own, such as a plain
  MLLP system (v1.40): it has no paths, so nothing is read in its place, and with its features declared false the gate
  blocks any write. So is an entry of category `orders_results` with no `api` (v1.54): a laboratory or order system has no
  receiver API Shutter reads, so it has no paths and its label names no address. An entry with neither reads the default
  paths, as a profile from before v1.8 does. An entry with neither a capabilities endpoint nor declared features reads as capabilities unread (`capabilities_source` "not declared by the site profile", status 0), and the gate answers `CAPABILITIES_UNREADABLE` (v1.39). An entry without `api` takes the downstream system's paths. `dry_run: false` in a receiver's declared features, or in
  its capability profile, means the gate offers no resend to it (`DRY_RUN_UNSUPPORTED`) and the connector refuses to send
  a dry run to it (v1.21). Declare all four flags: for a receiver with no capabilities endpoint the route takes the
  declared features, and a flag left out reads as false there (the connector alone reads an absent flag as true, so the
  gate is the stricter of the two).
- `further_messages` (6.5), how rigid a site wants the patient-level check. `in_patient_movement`: `stop`, or `show` to let a
  movement on another visit through with a line on the plan; a cancel, merge or discharge the receiver didn't apply on this visit
  stops either way. `admission_not_found`: `person`, or `policy` to let the tier's own policy release a lost admission on a 404.
  `scan_seconds`: how long, from 1 to 600 seconds, one read of a namespace's messages may take at a write; a read that runs out with
  headers left blocks the write (`FURTHER_NOT_READ`). Absent means `show`, `person` and 30, and the shipped profile says the same
  (`show` since v1.47; it was `stop`). A site that wants another visit's movement to stop the write for a person sets
  `in_patient_movement` to `stop` in the profile's JSON (`PUT /api/shutter/site-profile`; the Site profile page has no question for it
  and keeps what is stored); the demo's profile says `stop`.
- `feed.prove_origin`: `true` or `false`, `true` when absent and in the shipped profile: an automatic release needs the case's source proved (section 11). A site whose forwarder reports from another instance turns it off.
- `feed.prevent_failures` (v1.34; "prevent failures", decided on 1 Nov 2026, section 12): `true` or `false`, `false` when
  absent and in the shipped profile. On, the feed holds a message whose HL7 schema category is not loaded here as a case of
  kind `unreadable` instead of delivering what it read by position, and the demo hospital's `PAS In` validates and hands a
  refused message to the forwarder (`Hospital.Setup.PreventFailures`, called by every store of the profile; a real site sets
  its services itself, INSTALL.md section 5). The induction question for it is the last of the first setup's.
- `PUT /site-profile` refuses a profile that has not this shape, naming the field (unknown top-level fields and
  unknown keys under `receivers[].api`, `receivers[].features`, `approvers`, `feed`, `model_content`, `mail`, `teams[]`
  and `incident` are refused too, each named in the 400 `bad_request` detail, v1.21); every stored version is kept with who stored it and from where,
  `GET /site-profile/history` lists them (v1.9). `feed.time_zone` (v1.11) names the zone of timestamps without an
  offset: `UTC`, `Europe/London` or a fixed offset; the built-in default (`SiteProfile.Default()`, in force only while no
  profile row is stored) is `Europe/London`, a stored profile that does not answer keeps `UTC` (the reading before v1.11),
  and the shipped seed profile says `Europe/London` (v1.12), so the fixtures' times read as British Summer Time (09:20 on
  15 October is 08:20Z). Since v1.30 the zone may also be any IANA zone name this IRIS knows (`Europe/Paris`, `America/New_York`), read through Embedded Python's `zoneinfo` (`Shutter.Util.Time.PyOffset`, a method in Python; `KnownZone`, `PythonZones`); UTC, Europe/London and fixed offsets keep Shutter's own rules, and on an IRIS without Embedded Python or the IANA database such a zone is refused by the validator and read as UTC with a warning, as before. A zone outside these that reaches the reader anyway (the profile's check refuses one, so only a zone
  set by hand in the namespace's cached `feedZone`, or one passed to the time probe) is read as `UTC` with a warning in the event log, once per job and zone, and the evidence's note says so (v1.16). A date that does not exist (30 February, month 13, 24:00:00) reads as no time on every path, the UTC one, the zone one and the own-offset one alike, and `SecondsBetween` answers "" for it rather than an error (v1.39). `feed.source_skew_seconds` is how far apart, in whole seconds from 0 to 3600, two source systems' events still count as simultaneous (`simultaneous_sources`, E7): 300 when the profile doesn't say, the five minutes the time checks already allow a clock, and 0 keeps the exact second. The questionnaire page asks for `teams` and `mail` (question 9: the mail domains first, since a team mailbox needs
  one; an empty or absent `mail.allowed_domains` allows no address, v1.21), `feed` (10) and `model_content` (11)
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
- `approval`: one Workflow task for the case, or for the whole incident (section 7). The task's `PlanDigest` form
  value is empty: the decider supplies the digest (the API from the body it checked, an approver in the Workflow inbox
  by pasting it from the task's message), and an approval with no digest, or another one, blocks the case (v1.21;
  before, the value was pre-filled with the plan's digest, so an inbox approval always matched).
- `per_chain`: one Workflow task per chain of the incident.
- `board` for a chain kind means the board runs whatever the match says.
- A tier 3 receiver never takes `automatic` unless the profile says so explicitly; the shipped default does not.
- `approvers.close_needs_approver` (v1.17): the two-person rule some trusts keep for closing a case by hand. `false`
  (the default, and what an absent answer means) lets an operator mark a case handled by the team; `true` leaves it to
  an approver (section 5). It checks the closer's resource only: the server does not compare the closer with whoever
  sent the case's escalation, and `Shutter_Approver` holds `Shutter_Operate` too, so one approver may escalate and close
  a case, or close one that was never escalated, as the case page offers for a withheld case. The validator accepts only
  `true` or `false`, and refuses any other key under `approvers` (`approvers.<key>: unknown setting`; `role` and
  `escalation` must be strings), so a misspelt switch cannot pass as off (v1.21). It belongs to question 7, who approves what, so the questionnaire still has twelve questions; the
  shipped seed profile answers `false` and names `example.nhs.uk` as its only allowed mail domain (its file's `version`
  is 4 since v1.20). `Shutter.Store.SiteProfile.CloseNeedsApprover()`
  reads it. `approvers.role` and `approvers.escalation` stay on record only: the permissions themselves are the
  resources of section 5.
- A receiver entry's `strict_answers` (boolean, default true): whether Shutter checks that receiver's answers against this contract. A read counts only with the kind's own field or error (1.3), a 200 is a delivery only with its receipt or `applied: true` (5.1), and a receipt or history entry closes a case only if it holds the operation's own payload digest, ward and bed; a receipt that names none of them has nothing to compare, and passes. A site whose receiver answers another way, having looked at what it sends, sets it to false: its answers are then read on their status alone, so a gateway's page or a corrected message can read as delivered or committed. A cancel since the receipt (the gate's `RECEIPT_THEN_CANCELLED`) is the feed's own record, and counts either way.
- `merges` (v1.14): `forbidden` (the default when absent) or `allowed`, the only values the validator accepts. A receiver entry's `merges` and `cancels` (booleans, default false) say what it takes (1.1). A merge is delivered only under `allowed` to a receiver with `merges: true`; the gate's `MERGE_WITHHELD` blocks any write of a merge otherwise, so the exact repeat of a merge the receiver already holds (a receipt present) is E3's reconcile, and no other merge is ever resent by Shutter. `Shutter.Store.SiteProfile.MergesAllowed()` and `ReceiverFlag(name, flag)` read them.

**A FHIR R4 receiver's entry** (v1.63). A receiver entry may carry a `fhir` object, and an entry without one validates exactly as before. An entry whose `fhir` object passes the validation below is a FHIR receiver, and is reached for recovery through its FHIR R4 API and no other way (20). The entry is named after the production item that delivered the failed message, as every entry is:

```json
{"name": "FHIR Ward Out", "system": "the ward system (FHIR R4)", "category": "current_state", "tier": 3,
 "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false,
 "fhir": {"base": "/fhir-facade/r4", "recovery_enabled": true,
          "encounter_identifier": {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49"},
          "patient_identifier": {"system": "urn:shutter:demo:mrn", "hl7_authority": "HOSP"},
          "marker": {"system": "urn:shutter:recovery"},
          "location_map": [
            {"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}},
            {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}
```

`base` is the path in front of every request; the server, port, TLS configuration and credential are adapter settings of the FHIR items (12), never of the profile. `recovery_enabled` is the site's switch (absent reads false). `encounter_identifier.system` is the identifier system the visit number is searched under. `patient_identifier` maps the message's patient: the Patient must carry the case's patient id under `system`, and the case's assigning authority must be `hl7_authority`. `marker.system` is the system of the tag the update adds. `location_map` maps each ward code to its Location resource and to the identifier that resource must carry, 2 to 25 wards. One FHIR receiver per install in this version.

**Validation.** `Shutter.FHIR.Profile.SettingsProblem(r, receivers, index)` answers "" or the problem as a suffix that starts with a dot, and `SiteProfile.Validate` calls it for an entry that has a `fhir` key, after the `documents` check, and answers `receivers[i]` followed by the suffix (`PUT /site-profile` then answers 400 `bad_request`):

| Rule | Message after `receivers[i]` |
| --- | --- |
| `fhir` is an object | `.fhir: must be an object` |
| the keys of `fhir` are `base`, `recovery_enabled`, `encounter_identifier`, `patient_identifier`, `marker` and `location_map` only | `.fhir.<key>: unknown setting` |
| `base` is a string that starts with `/` | `.fhir.base: must be a path starting with /` |
| `recovery_enabled`, when present, is a boolean | `.fhir.recovery_enabled: must be true or false` |
| `encounter_identifier` is an object with `system` only, a non-empty string | `.fhir.encounter_identifier.system: required`, or `.fhir.encounter_identifier.<key>: unknown setting` |
| `patient_identifier` is an object with `system` and `hl7_authority` only, non-empty strings | `.fhir.patient_identifier.<key>: required`, or `.fhir.patient_identifier.<key>: unknown setting` |
| `marker` is an object with `system` only, a non-empty string | `.fhir.marker.system: required`, or `.fhir.marker.<key>: unknown setting` |
| `location_map` is an array of 2 to 25 objects | `.fhir.location_map: must be an array of 2 to 25 wards` |
| each map entry j has `ward`, `location` and `identifier` only; `ward` is non-empty and unique; `location` matches `Location/{id}` (letters, digits, `.` and `-`, 1 to 64 characters) and is unique; `identifier` is an object with `system` and `value` only, non-empty strings | `.fhir.location_map[j].ward: required` or `: must be unique`; `.location: required`, `: must be Location/{id}` or `: must be unique`; `.identifier.system: required` or `.identifier.value: required`; `.<key>: unknown setting` (also under `.identifier`) |
| beside `fhir`: no `api` | `.fhir: an entry with a fhir block has no api` |
| no `features` | `.fhir: capability is read from the server, so features is refused` |
| `engine_resend` is not true | `.engine_resend: refused beside fhir, one write route per receiver` |
| `category` is absent or `current_state` | `.category: must be current_state beside fhir` |
| `strict_answers` is not false | `.strict_answers: refused beside fhir` |
| no `documents` | `.documents: refused beside fhir` |
| `history_policy` is not `correct` | `.history_policy: refused beside fhir` |
| no earlier entry of `receivers` has `fhir` | `.fhir: one FHIR receiver per install in this version` |

**What the rest of the profile code reads from it.** `SiteProfile.ReceiverKind(name)` answers `fhir_r4` for a FHIR receiver, an entry whose `fhir` object passes `Shutter.FHIR.Profile.SettingsProblem` where the entry stands in the profile's list, which is what a save asks of it, the one-receiver rule included (`Shutter.FHIR.Profile.IsReceiver(r, receivers, index)`: an entry after another that has a `fhir` key is none), and "" otherwise. A FHIR receiver has no paths of its own and its label names no address (`HasNoApi`), declares none of the four features (`ReceiverFeatures` answers all false: what it can do is read from the server and recorded in the route), and has the history policy `current` whatever else the profile says. The incident detector never groups its cases (7.1). An entry whose `fhir` key holds anything a save would refuse reads as its other keys make it: its API paths, features, label, category, history policy and incidents; nothing of the FHIR flow runs for it, the Doctor (12) does not list it, and the profile cannot be saved again until the key is corrected or removed.

`Shutter.FHIR.Profile` also holds `Parameter POLICYVERSION = "fhir-2026-11-14.1"` (the FHIR gate's policy version, which the gate, the flow, the write and the Doctor all read there) and `Parameter ITEMS = "FHIR Receiver,FHIR Out,FHIR Gate,FHIR Verifier"`, and its readers, class methods that are pure over the stored profile: `Block(name)` (the FHIR receiver's `fhir` object, or "" when the entry is no FHIR receiver), `Enabled(name)` (`recovery_enabled` is true), `LocationOf(block, ward)` (the map entry, or ""), `WardOf(block, reference)` (the ward code of a `Location/{id}`, or "") and `MappingDigest(block)` (`Shutter.Util.Digest.OfObject(block)`).

**Precedents** (v1.35). What approvers decided before on the same evidence at the same receiver, and whether it held.
When a person's approval is verified at the receiver (the case resolves), and when an approver rejects a plan, the case
writes a precedent (`Shutter.Store.Precedent`): the receiver; the signature, the SHA-256 of the snapshot's condition
vocabulary (6.1) in canonical JSON, so the match is exact, as the message index is; the catalogue entry and outcome; the
plan's disposition and digest; the approver; the decision (`approved` or `rejected`); and the policy, site profile and
catalogue versions in force. An automatic release (approver `policy`) writes none: it is the policy, not a precedent. The
evidence collector adds `precedents` to every snapshot summary, `{approved, rejected, lastDecision, lastApprover, lastAt,
lastCaseId, samePolicy, windowDays, signature}`: the active rows of the last `windowDays` days
(`^Shutter.Config("precedentDays")`, 1 to 3650, 180 by default; the Doctor's `precedent_days`), and `samePolicy` says
whether the last decision was taken under the policy and site profile versions in force now. A board member who gave no usable answer is on the plan as `absent_members`, by name and under the plan's digest (a follower's plan carries its leader's); such a plan that writes nothing goes to a person (escalated) and doesn't close (policy version 2026-11-07.1), and one that writes goes on as built, and the approval task's text names them ("Not every board member's review stands behind this plan: ... did not answer."). The approval task's text
quotes it ("Precedents: approved and verified 2 times, rejected 0 times in the last 180 days; last approved by approver on
2026-11-02 (case C-000301)", or "Precedents: none; these conditions at this receiver have not reached an approver in the
last 180 days."), and the case's events note each precedent written. It is for the person and the app: the model view's
allowlist (9) leaves `precedents` out of what a board member reads, so a run of approvals cannot anchor a model, and the
material digest (A7) never includes it, so a new precedent changes nothing an approval binds. `GET /cases/{id}/precedents`
(`Shutter_Operate`) answers `{receiver, conditions, summary, precedents: [...]}`, the rows newest first, retired ones
included with `active` false; `POST /precedents/{id}/retire` (`Shutter_Approve`, `X-Requested-With`, body `{reason}`, required: 400
`bad_request` with `field` `reason` without one) retires one, which stays on record and counts for nothing (404 `not_found`;
409 `already_retired` with `retiredBy`, `retiredAt` and `retiredReason`). A precedent informs the approver and never releases anything: only the policy path above releases without a
person.

**The reminder for cases left open** (`reminders` in the site profile; absent means off; the addresses as in section 10). A scheduled mail, once a quarter of an hour, by the task "Shutter case reminders" (`Shutter.Util.CaseReminderTask`), through the `Escalation Mail` operation's mail server and `mail.from`. Which cases: `awaiting_approval`, `blocked`, `escalated` and `failed`, leaving out the disposition `abandoned`. Who: at `team_hours` (default 4) the case's team as an escalation picks it, its `mailbox` and not its `cc`; at `officer_hours` (default 8, later than `team_hours`) `officer_address`, named `officer_name`, one bare address in `mail.allowed_domains`. When: open time is elapsed time since `openedAt`; a mail goes only in the window, `window_start` (default 08:00) up to but not including `window_end` (default 18:00) on `days` (default `mon` to `fri`), in `feed.time_zone`, so a case left overnight is in the first mail of the morning. A site's bank holidays are not known. At most one digest an hour to one address, and each case once per threshold (`Shutter.Store.CaseReminder`, unique on the case and the threshold, written when the mail server accepts the digest, so it survives a restart; it records that acceptance and never that a person read it, and the digest's state is `queued`, `accepted` or `failed`). A threshold passed outside the window waits for it: a case left on a Friday evening is in Monday's first mail unless `days` says otherwise, and the mail says so. What it holds: counts, the oldest age, the receiver (a name in the profile's `receivers` or a team's `receivers`, else "a receiver the site profile does not list") and the failure type (the store's word), the case numbers each with its age (100 listed, the rest counted), the subject and text saying the mail waited for the window when a threshold passed before today's window opened, and `sign_in_url`. No failure text, gate reason or other free text. `patient_detail`: `none`, `identifiers` (the default: hospital number with its authority, and visit number) or `identifiers_initial` (and the first letter of the first name, PID-5.2, read from the stored message for the mail and not kept). Never a full name, date of birth, address or NHS number, whatever the setting: a hospital number that is an NHS number by its shape or authority, or that does not read as one word with a digit in it, reads "not shown", as does such a visit number. No identifier goes in the subject. This mail goes out with nobody reviewing it, an exception to the rule that a person reads mail carrying identifiers: it is the site's information governance decision. It writes to no receiver, calls no model and has no effect on the gate, a plan or a closure. Each reminder is a `note` event on the case (ref `reminder:<digest id>`), written without touching the case row. The operation checks once more before it sends (on, in the window, built within half an hour, the address allowed), and then reads again whether the patient detail is the one the text was built at and each case still needs a person, has not had this reminder and is still for this recipient; if not, the digest fails without a warning and the next run builds what is due. A failed send, or none possible, is logged, records nothing, and goes again at the next run; with no mail server nothing is written, not even the `.eml` an escalation falls back on. The text of a digest goes when its send is over; the row keeps who, which case numbers and the answer for 90 days. The Doctor's `case_reminders`: `{enabled}` when off; when on also `warnings` (no mail server, no allowed domain, no officer address, no team, no sign-in address, no task, no run for over an hour, the last run's fault), `patient_detail`, `zone`, `last_run`, `last_accepted` and `last_error`. A reminder does not establish that anyone has taken a case on, and a named officer may be away: Shutter holds no rota.

### 6.5 The gate's catalogue checks

A new check, `catalogue`, with these reason codes (in `knowledge/block-reasons.json`):
- `ENTRY_UNKNOWN`: the plan names an entry that is not in the catalogue at the plan's catalogue version (block);
- `PATTERN_NOT_MATCHED`: the entry's pattern does not hold on the snapshot (block);
- `OUTCOME_NOT_ALLOWED`: the chosen alternative's `when` does not hold for this site (block);
- `NEW_PATTERN`: no entry matches (block; the case escalates as a candidate entry);
- `ENTRY_NOT_NAMED_WRITE`: a write names no entry while an entry the evidence matched calls for no resend, by the outcome the matcher chose for its one match, or by the preferred outcome of any of several (block). Only explicit Rules only in a recorded scenario passes it, a `rules` plan on a case in mode `rules` that the scenario runner played (the case's `ScenarioRecorded`, set when it opens; a live story's stamp doesn't set it), which is the baseline kept to show what a plain resend does; a real case in that mode is blocked: every other write with no entry passes as `ENTRY_NOT_NAMED` when all its matches resend;
- `POLICY_REQUIRES_APPROVAL`: an automatic release where the profile requires an approval (block; an internal guard).
- `APPROVAL_ORIGIN_NOT_PROVED`: an automatic release of a case whose source is not proved (block; section 11; an internal guard, since the policy path has asked a person by then).
The plan's `catalogue_entry` and `outcome` are bound by the approval's digest like every other field of the plan. The incident plan's digest binds each item's catalogue entry and outcome the same way (7.2). A receiver the site profile does not describe gets no write (v1.39): when the case names a receiver and the profile has no entry for it, the proposal gate blocks with `RECEIVER_NOT_IN_PROFILE` before any rehearsal, since the connector would otherwise send the write to the production's default receiver; the evidence was read at the default API, and the note says so; the block reason is in `knowledge/block-reasons.json`.

Two `intent` checks for withheld cases (v1.14, policy version 2026-10-19.3), appended for every plan on a case of kind `withheld` as `UNMAPPABLE` is, and as guards on any write of a merge or a cancel: `MERGE_WITHHELD` (the case's event is `merge` and the site profile does not allow merges, or the receiver does not take them) and `CANCEL_UNSUPPORTED` (a `cancel_*` event to a receiver whose entry says `cancels: false`). The identity check answers `NO_ENCOUNTER` (pass) for a case whose encounter piece is `-`, and the state-transition and concurrency checks answer `PATIENT_LEVEL_WRITE` (block) for a write on such a case: there is no encounter state or version to check, so a person decides, and nothing is retried.

**The rehearsal check** (v1.21, policy version 2026-10-25.1), between authorization and concurrency: `NOT_APPLICABLE` (pass) for a plan that writes nothing, `NOT_YET_REQUIRED` (pass) at the proposal, and at dispatch `REHEARSED` (pass: the approval's bound rehearsal is of this plan, reported `would_apply`, and was checked against the plan's expected version, the receiver's epoch and the evidence's payload digest), `DRY_RUN_MISSING` (block: no rehearsal bound, or one of another plan), `DRY_RUN_FAILED` (block: the bound rehearsal reported it would not apply) and `DRY_RUN_STALE` (block: checked against another version, a rehearsal with no version from the receiver included, against another epoch than the preflight's, against another payload digest than the evidence's, or sent with an expected version other than the plan's). The capability check adds `DRY_RUN_UNSUPPORTED` (block: the capability profile reports no dry run). The approval binds the latest rehearsal of its plan, not the case's latest. The rehearsal record carries `expectedVersion` and `payloadDigest`, what was sent; the execution attempt carries `rehearsalId`, the approval's bound rehearsal, or the rehearsal itself when the receiver applied it. An approval given under 2026-10-20.1 and not yet dispatched is void at dispatch (`APPROVAL_POLICY_CHANGED`).

**The engine check** (v1.47, `Shutter.Util.EngineCheck`). For a write on a case with a source namespace and an origin header,
the gate's ordering check reads first: `ENGINE_NOT_IN_SCOPE` (pass, the target is not a stock HL7 TCP operation),
`ENGINE_STILL_TRYING` (block, the case waits on `waitsOnEngine`), `ENGINE_DELIVERED` (block, on any route but the
acknowledgement feed; the case resolves with the engine's words, or stays with a person where acceptance can't be
established), `RECEIVER_MAY_HOLD_IT` (block, a person), `ENGINE_UNREADABLE` (unknown, refreshed, then a person),
`ENGINE_SETTLED` (pass). The reason codes are in `knowledge/block-reasons.json`, with `HOLD_EXPIRED`, `ENGINE_ROUTE`,
`ENGINE_ROUTE_ABSENT`, `ENGINE_ROUTE_REFUSED` and `ENGINE_ROUTE_NO_API`, which this build does not emit. The Case Releaser
judges a case waiting on the engine again (8.1).

**A FHIR case** (v1.63). A case whose receiver is a FHIR receiver (6.4) is judged by the FHIR gate of section 20 (`Shutter.Operation.FHIRGate`), never by this one: none of the checks above runs for it, and `Shutter.Operation.Gate` is unchanged. The FHIR gate copies this gate's conformance, intent, further-message, later-event, engine and `catalogue` reads where they still apply, and adds its own (20.1).

### 6.6 The board and the catalogue

The board has no catalogue tool (v1.6 named a `search_catalogue` tool; it was never built, and the coordinator stopped
naming it in v1.7). The matches reach it in the evidence, in the snapshot summary's `catalogue` section, each with its
entry's prose, so that the board cites entries by id. The coordinator's instructions say the plan names the entry and
the outcome, or leaves `catalogue_entry` empty when no entry fits (a new pattern). The members' knowledge tools are the
four collections under `knowledge/` (`search_contracts`, `search_lifecycle`, `search_effects`, `search_playbooks`); the
fifth collection, `review`, is the production review agent's (13.6) and reaches a board member only through a row whose
`KnowledgeCollection` is `all` (the single investigator's).

**An approval wait is bounded (v1.35).** The Case Workflow's `ApprovalWaitSeconds` (24 hours by default; 0 waits without
limit) arms an `Ens.Alarm` beside each approval task, keyed by the plan's round. When it fires and the case still waits for
that round's plan, the task is cancelled (`Cancel`, with the reason in its comment) and the case escalates with "No approval
within N hours; a person must decide"; the task's text says so in advance. A decision taken meanwhile, or a later round,
leaves the alarm with nothing to do. An incident's approval task (7.4) is not bounded this way: its chains wait on the
incident.

**Boards per minute are capped (v1.35; the review's B1 stopgap).** The Case Workflow's `BoardsPerMinute` (6 by default; 0 for
no cap) counts the boards convened in the current UTC minute (`Shutter.Util.BoardSlots`, a global node per minute); a case
whose turn finds the minute full does not convene at once: it notes "The board is busy: N convened this minute, the cap is M a
minute; this case waits S s for a slot" (60 to 89 s), an `Ens.Alarm` keyed by the round brings it back (`board:defer`), and
it convenes then, on its snapshot's summary, if it still waits and the round is the same. Both convening paths (the board on
fresh evidence and the policy's `board`, which asks for the full board whatever the case's mode) go through one method,
which builds every member's request first (a case the model view refuses, or one with no member to convene, spends no slot)
and then takes the slot atomically (`BoardSlots.TryTake`: the count goes up and comes back down past the cap, so two cases
cannot both pass a last slot); a deferred case keeps who asked and which members (`DeferredBy`, `DeferredMode`). A storm of failures therefore costs at most the cap a minute,
each case waits its turn and none is lost.

**One board per failure signature (v1.35; the review's B1 in full).** A storm of the same failure buys one board, not one
per message. When a case reaches the board, its failure signature is computed (`Shutter.Util.Signature`: the receiver, the
failure kind, the receiver's answer and the delivery word of the condition vocabulary (6.1), the catalogue entry and outcome
the match chose, the connector's error sentence with its numbers and digests normalised, the policy version, and the
scenario stamp, so a demo's scenarios never coalesce with each other). The first case of a signature convenes the board and
**leads** it (`Shutter.Store.BoardLead`: the signature, the leader, `running`, the window's end); a case of the same
signature arriving within the window (`^Shutter.Config("leadWindowSeconds")`, 600 by default, 0 for no coalescing; the
Doctor's `lead_window_seconds`) **follows**: it convenes no board. While the leader's board runs the follower waits in
`investigating` with `followsCase` set and a note; when the leader adopts its plan (from its board, or from the rules path
when nobody could answer) the lead is finished `done` with the plan, the plan's `createdBy` as `decidedBy` and the members' verdicts (member, role, disposition,
confidence; no text), and every waiting follower is told (`Shutter.Msg.LeadReady`, a fresh instance as a reinvestigation).
The follower then takes the decision through its own evidence: the disposition and action type, the catalogue entry and
outcome when its own match shows that entry, and the verdicts in the plan's `why`; the operation key, the receiver version
and the payload digest are its own, and not a word of the leader's text crosses (it carries the leader's patient). The plan's
`createdBy` is `lead:<leader case>`, and the follower keeps its own gate at the proposal, its rehearsal, its approval, its
preflight and its dispatch gate, as any case. A follower arriving after the leader decided takes the decision at once. A
lead whose plan came from the rules (`decidedBy` `rules`) passes on no decision, since no board took one: the follower has
no board answer, below. A lead whose board ended without a plan (no findings, no coordinator, a timeout, the model view's
refusal, a case with no board answer that went to a person) is `failed` and attracts no followers; a follower waiting on it,
or on a leader whose board never ended within twice the board timeout and a minute, has no board answer. **No board answer**
(`CaseWorkflow.NoBoard`): when every member refused or has no recording (`budget_exhausted`, `provider_auth`, `no_record`),
no member can be convened, or the board a case followed decided nothing, a case outside mode `rules` whose catalogue decision
is `board` or `person` with at least one match goes straight to `escalated`, disposition `escalate`, with no plan and the
reason `NO_BOARD_ANSWER`: the event and the headline name the entries and why nobody answered, and a leader's lead is
`failed`. Any other case (a `policy` decision, a new pattern, no catalogue) falls to the rules path with a note, and mode
`rules` always takes it, so S8's Rules only pass still resends. A lead begun before the last scenario reset, or in the same second as it, counts for nothing, as the incident
detector's window. A judge's forced board and an incident's released chain items never follow. A lead whose leader fails (a workflow error, or an escalation with no summary when its board slot comes), is abandoned or is closed by hand is finished as failed at once (v1.39), so a case of the signature that arrives afterwards leads itself and every case waiting on it takes the rules path without waiting out the bound. The lead's row keeps how
many followed; `GET /cases/{id}` shows `followsCase` and `leadSignature`. Approvals stay with the existing mechanisms: an
incident's one task for its chains (7), else one per case.

**One model call is bounded (v1.35).** The runner gives the provider an HTTP request timeout, `Shutter.Setup.ProviderTimeoutSeconds`
(`^Shutter.Config("providerTimeoutSeconds")`, `SHUTTER_PROVIDER_TIMEOUT_SECONDS` at a start, 120 s unless set, held to 10
to 600), and a connect timeout of 10 s, as `http_config` on the provider's configuration unless the site's own configuration
sets one. The runner builds the provider itself for the item's `ProviderConfig`, for the mimic, and for Shutter's own
configuration (`^Shutter.Config("aihub", "provider")`, written by `ConfigureProvider`), so the bound holds on the default live
path too; only an agent class run with none of these falls back to its own `PROVIDERCONFIG` parameter. Without it a hung provider held a board member until the board's 600 s timeout, since the run's deadline is checked
only between the model's turns; with it the call fails, the run ends with status `timeout` and the board goes on without that member. Measured on build 154
against a server that never answers: AI Hub retries the call, so the run ends after about four times the bound plus a few
seconds (44 s at 10, 84 s at 20); at the default 120 s that is about eight minutes, inside the board's 600 s. The Doctor
reports `provider_timeout_seconds`.

**Hostile and malformed output (v1.35).** The schema checks refuse what is not an object, a disposition outside the list
(whatever its case, with nothing hidden inside it), a confidence that is not a number from 0 to 1, a `summary` or `why` over
2,000 characters, and the shapes section 6.6 names; a table of such outputs (`Shutter.Test.Hostile`, run on the AI Hub build,
skipped where the schema classes are not loaded) keeps it so, and asserts that the checks never throw and accept ordinary
Unicode. What a model wrote and the checks accepted is cleaned when it is restored for the store (9).

**Findings and plans cite only what they were given (v1.35).** `evidence_refs` on a finding or a plan must name keys of the
evidence object the run received, or keys one level down in it (`operation`, `failure`, `message`, `validation`, `ward_state`, `receipt`,
`timeline`, `route`, `bed_conflict`, `catalogue`, and so on), or `findings` for the coordinator; the names the prompts used before v1.39 for two of those keys, `error` for `failure` and `later_event` for `timeline`, stay citable while the evidence has the key they stand for, so the recordings made before v1.35 and the evaluation table pass the check, and the rules of the house, the SubmitFindings and SubmitPlan descriptions and the Goal line now name the keys rather than snapshot item kinds or identifiers (v1.39), with no change to the record keys, which carry the member's configuration version; the runner lists them for the terminal
tool (`CiteIds`, as the question tools already have), `Shutter.Schema.Findings.CheckRefs` refuses the submission with the
unknown names and the keys that are allowed, and the model repairs it in the same run. A reference to evidence that is not
there is therefore never stored.

### 6.7 The Second Parser (v1.34)

When IRIS cannot read a message (the validation's `parsed` is false: no parse, or a schema category this namespace has not
loaded, 12), the Evidence Collector asks an independent parser before the gate speaks: the item **Second Parser**, an
`EnsLib.PEX.BusinessOperation` running `shutter.pex.SecondParser` in Java through PEX (`pex/src`), which reads the message with
the HAPI HL7 library (2.6.0) and answers a `Shutter.Msg.ParseRequest` (`Raw`, `HeaderId`) with a `Shutter.Msg.ParseReport`
(`ReportJSON`, `Parser`). The report, under `validation.second_parser` in the snapshot, is `{parser, declared_version,
version_known, read_as, message_type, control_id, parsed, valid, structure, errors: [{code, message, segment, field,
component}], segments: [{name, fields, populated}], segments_declared, notes, available: true, item}`. Every message is read with
the 2.5.1 structures (HAPI's canonical model) whatever version it declares, so a 2.3.1 or 2.4 message and a site category
such as `MYSITE_2.5.1` are read too, and the report says both versions. The gate's `SCHEMA_UNKNOWN` and `PARSE_FAILED` words
gain the verdict (`Shutter.Util.SecondParser.Verdict`): "reads it as a well-formed ADT^A02^ADT_A02 with the 2.5.1
structures (it declares MYSITE_2.5.1): the message is sound, and the schema is what this namespace lacks", or "also finds it
invalid at PID-7 (Primitive value '1980-01-X1' requires to be empty or a HL7 datetime string): the message is malformed, not
merely of an unknown schema". The agents and the app see the same report. Without the jar (a site without Java, the replay
edition, a build with no network) nothing fails: `Shutter.Setup.SyncSecondParser` leaves the item disabled, the evidence
carries `second_parser: {available: false, item, reason}`, the verdict is empty and the Doctor's `second_parser` says why
(`{item, available, jar, classpath_jars, probe, parser}`; `probe` is `ok` when the Java gateway answers a one-line message).
The Evidence Collector's setting `SecondParserTarget` names the item (empty never asks); a slow or failing item leaves
`available: false` after 20 s and the gate judges without it. `pex/build.sh` downloads HAPI and its dependencies from Maven
Central, checks each against its pinned SHA-256 in the same step, finds IRIS's PEX framework jar by what it holds (the one
jar under `dev/java` with `com.intersystems.enslib.pex`: `intersystems-utils-<v>.jar` on IRIS 2026.2,
`intersystems-pex-<v>-shaded.jar` on the AI Hub images; names and versions differ between builds), compiles the two classes
against it with the image's own JDK (Temurin 11) and writes `shutter-pex.jar` and `framework.txt` (the framework jar's path)
under the manager directory as `pex/`, beside `shutter/` and outside the image's data volume, so an upgraded container runs
its own image's jar. The item, `Shutter.Operation.SecondParser` (an `EnsLib.PEX.BusinessOperation` of Shutter's), sets its own
`%gatewayExtraClasspaths` at start from `framework.txt` and the jars when the setting is empty, so nothing written into the
production's definition is needed, and a recompile of `Shutter.Production`, which writes the definition again from the XData,
cannot drop it (an item whose classpath the install had written died at its next start, core, 1 Nov 2026);
`SyncSecondParser` only enables or disables the item as the jar is there or not. The build never fails the image: without a JDK, a framework, network or a matching checksum it prints why, leaves
no jar and the item stays off (`PEX_STRICT=1`, CI's image job, turns such a skip into a failure on an image known to carry
the framework). The Dockerfile runs it, and a site with Java runs it once by hand.

## 7. Incidents: many failures to one receiver (v1.6, as built in v1.7)

### 7.1 Detection and grouping

- The connector counts delivery failures and refusals (not uncertain outcomes) per receiver in a sliding window. At the
  profile's threshold (default 5 within 10 minutes) an incident opens for that receiver.
- A case opened while an incident is open for its receiver joins it (case state `grouped`) instead of starting its own
  investigation. When the incident opens, it also adopts the burst's earlier cases for that receiver that are still before
  their proposal gate (settling, collecting or investigating), so the first failures are not left outside it. The
  incident's intake closes after `quiet_seconds` with no new failure, or once it has been open for
  `max_intake_seconds` (optional, 1800 by default, 0 for none) with the newest failure a refusal: a receiver that is up
  and steadily refusing new messages would otherwise hold every other failure to it. A receiver that answers nothing
  keeps the wait, since a release would only block against it.
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
- The incident's plan lists every chain with its kind, who decides it, its policy, its entries and its items in order
  (case id, event, event time, operation key, payload digest, catalogue entry, outcome, who decides, and the receiver
  version the item goes at: the chain's first expected version for the first item of a chain a person approves, null
  otherwise, since the rest go at the version the previous item's verified receipt reports and an automatic or board
  chain's first item goes on fresh evidence), with the receiver's epoch and the catalogue, site profile and gate policy
  versions. Its digest is the SHA-256 of that plan as recorded, in canonical JSON (keys sorted, arrays in order, no
  whitespace), the construction the case plan's digest uses, so `GET /incidents/{id}` `plan` without its `digest`
  member recomputes it (v1.21; until v1.18 it was a line format over the operation keys, payload digests, first
  expected versions, epoch and versions alone, so an item's case, entry and outcome were not bound).

### 7.3 Approval

- The site's policy per tier and chain kind decides: `automatic` (no task), `approval` (one Workflow task for the
  incident's policy chains), `per_chain` (one task per chain). Board chains are approved as single cases are today.
  A chain holding a lost admission, one the receiver answers 404 for, is never `automatic` (policy version 2026-11-07.1;
  6.5): it goes under the one task, on that item's line the question of a record entered by hand, unless the site's
  `further_messages.admission_not_found` says `policy`. An outage of lost admissions asks one person once.
- The task says what is bound and what is not: "resend these, in this order; each one is rehearsed, gated and verified
  just before it goes; the chain stops at the first surprise, and the rest comes back to you".
- The incident's approval binds the plan's digest: for every item, the case, the operation and its payload, the
  catalogue entry and outcome the approver read, and the receiver version it goes at; and the rule for later items:
  each item after the first goes at exactly the version the previous item's verified receipt reports. The task says
  so, and that each operation goes only under the catalogue entry and outcome listed for it.
- The approval also binds the catalogue, site profile and gate policy versions on the plan (policy version 2026-11-07.1): if
  any has changed at a dispatch, the gate answers `APPROVAL_CATALOGUE_CHANGED`, `APPROVAL_SITE_PROFILE_CHANGED` or
  `APPROVAL_POLICY_CHANGED`, that item blocks, nothing is sent, and its chain's rest comes back to a person. So an upgrade
  during an open incident stops each chain still to be released at its next write: writes already verified stand, an item that
  writes nothing still closes, and each stopped case can be reinvestigated under the versions now in force. A chain with no
  person's approval has no approval to void: the new versions decide it on fresh evidence.
- Task subjects: `Shutter I-nnnnnn: approve the release of N chain(s) to <receiver>` for the shared approval, and
  `Shutter I-nnnnnn/<seq>: ...` per chain; both carry the `PlanDigest` and `Comment` form fields, `PlanDigest` empty
  until the decider fills it (v1.21; before, it was pre-filled with the plan's digest, so an inbox approval always
  matched). An approval with another digest, or none, rejects the chains it covers: their cases are escalated with the
  reason.
- A task's message holds 2,000 characters (`EnsLib.Workflow.TaskRequest.%Message`). It lists every chain and item when
  they fit; otherwise the first whole chains, how many chains and operations it leaves out, and the incident page
  (`/shutter/index.html#/incidents/I-nnnnnn`), which has them all. The digest is always whole, and an approval binds every chain the
  plan holds, listed in the message or not.
- An error raising a task, or the Workflow item answering its call with an error, closes nothing: the chains stay
  `awaiting_approval`, no case fails, an `error` event and an alert name the incident, once for each cause, and the workflow
  tries again every 5 minutes, reading the approval target afresh. While the task is missing, the incident's automatic and
  board chains still go, and once they are done the incident moves from releasing back to awaiting_approval, saying that
  no approval task is open, so GET /incidents?state=awaiting_approval and list_incidents still list it. Until a task exists an approval answers 409 `wrong_state`.
  The Workflow item defers its reply before it makes the task, so an error inside it never answers the call: the workflow
  makes no call while the target's Workflow role is not defined, and 30 seconds after a call it checks that the item made
  the task. A request the item finished with, 10 seconds or more before, and no task made from it is that error; a request
  still queued is checked again 5 minutes later, so a slow item never gets a second task.

### 7.4 Release

- The incident releases chains one at a time (or side by side, when the profile allows), and within a chain one item at
  a time: it tells the case the version to expect, the case runs its own stages (the proposal gate, the rehearsal, the
  approval it stands under, the preflight read, the dispatch gate with its rehearsal check, the write, the verification)
  and reports back.
- The dispatch gate's concurrency check compares the receiver's version with the expected one; any other write in
  between stops the chain: the remaining items go to a person with the reason, and the incident's record says which
  item stopped and why.
- A released item whose case is blocked while it waits on another case (`waitsOn`, the occupied bed) or on a newer message
  of its encounter (`waitsOnMessage`) is still working for the chain (v1.29): the chain waits with it, the incident is told once,
  and the item is judged when the case closes after its release. An escalated item stops the chain as before. So does a wait on
  a case this incident still holds back for another of its chains, which could only go once this chain had stopped: the chain
  stops, the incident says why, the other chains go on, and that case's closing reopens the waiting one, which plans alone on
  fresh evidence under the site's policy for a single case.
- Every item keeps its own trace, approval record and closure; the incident's record lists each chain's outcome:
  `resolved`, `stopped` (with the item), `escalated` (a board chain or a no-match).
- Chain states: `pending`, `awaiting_approval`, `approved`, `rejected`, `releasing`, `resolved`, `stopped`, `escalated`;
  item states: `pending`, `released`, `resolved`, `blocked`, `escalated`, `failed`, `stopped` (never released). An item's
  expected version is the previous item's verified version: the `version_after` of its write's receipt, or of the receipt
  the verification read (a write whose answer was lost, a reconcile); on a receiver with no receipts, the write's answer or
  the history entry with the operation's key; and only an item closed with none of these (superseded, nothing written)
  takes the encounter as the verification read it. So a reconcile whose receipt is older than the encounter stops the next
  item for a person. The first item of a chain a person approved goes at the
  chain's first expected version from the plan, and the first item of an automatic or board chain goes on fresh
  evidence. A released case whose fresh evidence shows another version blocks (the sequence rule) and its chain stops.
  Chains are released one at a time in sequence order; approved chains go while the others' approvals are pending. A
  released case under the incident's approval records an approval by the approving user, naming the task, the
  incident plan's digest and the entry and outcome that plan bound for the item (`incidentPlanDigest`, `boundEntry`,
  `boundOutcome` on the approval), so the gate treats it as a person's. Before the item is planned, a fresh match that
  reads another entry or outcome than the approval bound blocks the case ("Not covered by the incident's approval") and
  its chain stops. At dispatch the gate's authorization check refuses the approval when the case's plan or its fresh
  evidence names another entry or outcome (`APPROVAL_ITEM_CHANGED`) or the incident's plan digest is no longer the one
  it bound, or the case no longer belongs to the incident (`APPROVAL_INCIDENT_PLAN_CHANGED`): the case blocks and the
  chain stops at that item (v1.21).
- Any error in the incident's workflow during a release, other than one raising an approval task (7.3), abandons the
  whole incident (`IncidentWorkflow.OnResponse`, `OnError`): a released case it can't find again ("Released case ... not
  found"), or a failure moving on to the next item, stops its open chains, fails its cases still `detected`,
  `collecting`, `investigating` or `grouped` with the reason, and closes it. As built in 1.2.0 (v1.48).
- A receiver that goes down again during a release stops each remaining chain in turn: the released item's preflight
  read, tried `MaxRefreshes` + 1 times (4 by default), or its write finds the receiver down, the case stops for a person,
  the chain's later items are escalated ("Not released: ..."), and the next chain is released and stops the same way. No
  write is retried blindly, so nothing is written twice. As built in 1.2.0 (v1.48).

### 7.5 The API

- `GET /incidents` (`?state=`, `?limit=`, default 50, at most 500): `items` and `total`; each item is the incident (id,
  receiver, mode, state (`open`, `classified`, `awaiting_approval`, `releasing`, `closed`), times, the plan's digest and
  the versions it binds, the approval) with `progress`: `chains`, `cases`, `byKind` and `byState`.
- `GET /incidents/{id}`: the chains with their items (case ids, position, kind, entry, outcome, the expected version
  rule), the plan's digest (the plan is recorded in full and its digest is recomputable from it, 7.2), the approvals,
  progress.
- `POST /incidents/{id}/approvals` with `planDigest`, `decision` (`approve` or `reject`; `action` is accepted too),
  `comment`; `Idempotency-Key`; 409 `plan_changed` when the digest moved, 409 `wrong_state` when nothing awaits approval, and when another decision reached the incident's or chain's task first (its `approval` names that decision, approver and time); the 202 reply carries `approver`, the signed-in user (section 5).
  `POST /incidents/{id}/chains/{seq}/approvals` for `per_chain`.
- `GET /incidents/{id}/events`; `GET /incidents/{id}/approvals`. `GET /incidents/{id}` also carries the plan, the
  approvals, the Workflow tasks and the workflow trace link.
- A case carries `incidentId` and `incident` (`incident_id`, `incident_state`, `chain_seq`, `position`, `chain_kind`,
  `decides`, `chain_policy`, `item_state`, `expected_version`); its events say whether it was released automatically,
  under the incident's approval, or stopped. An approval given under an incident's carries `incidentPlanDigest`,
  `boundEntry` and `boundOutcome` in `GET /cases/{id}/approvals` (v1.21).
- `GET /site-profile` (`Shutter_Operate`, as every read) returns the current profile with its version; `PUT /site-profile`
  (`Shutter_Configure`, `X-Requested-With`) replaces it with the body, which must have the shape of 6.4 (400 `bad_request`
  naming the field otherwise), and answers the same object as the GET with the new version; the questionnaire page writes
  it. Every version is kept as a `Shutter.Store.SiteProfileVersion` row with who stored it and from where
  (`GET /site-profile/history`).

### 7.6 Scenario S11, an outage burst

Eight failures for six patients to the downstream system, in one burst (the fault `fail_before_accept` on, the files,
the fault off): P1 one failed A02 (E2, single); P2 A02 and A03 failed (E4, ordered); P3 A02 failed, A08 applied, a later
A02 applied, A03 failed (E5, interleaved, board); P4 A02 failed, then a later A02 applied (E1, superseded); P5 A02
failed after an applied A03 (E6); P6 a failed A01 (E2, single, admit). Expected: the policy chains resolved without the
board at tier 2 (automatic single, approval ordered, and P6 approval, since policy never releases a lost admission), P3 by the board, and the downstream system's final state per
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
- `Shutter.Index.Indexer` (production item "HL7 Index"), a service driven by Shutter's own inbound adapter `Shutter.Index.Adapter` (v1.31: the adapter does the reading, as an adapter should; its `CallInterval` is 5 s, and its settings `Routes`, `BatchSize`, `LagSeconds`, `BackfillHours` and `MaxBatchesPerTask` say what it walks; each task it hands the service the next batches of headers as `Shutter.Index.Batch` objects through `ProcessInput`, and moves the mark once a batch is taken), walks
  `Ens.MessageHeader` by id from a high-water mark (`^Shutter.Index("hwm")`), `BatchSize` headers a pass, only HL7
  bodies on the `Routes` (business service config names; empty means every route), and only headers older than
  `LagSeconds`, because an id is taken before its row is written. The first start begins at the oldest header within
  `BackfillHours`, or just after the newest header when none is that recent (v1.39: it is not indexed by the first walk, and an old, quiet store is never walked from header 1). Defaults: `Routes` "ADT In", `BatchSize` 200, `LagSeconds` 5, `BackfillHours` 168; one call runs up to 20 passes while the walk is behind. A header whose message could not be indexed is recorded in `^Shutter.Index("failed")` (`GET /index` counts them as `failed_headers`) and cleared when `Rebuild` indexes it. A body already indexed is skipped, so a site may also name the class as a host's Search Table
  Class. `Rebuild(fromId, toId, routes)` walks a range again (SQL procedure, `Shutter_Operate`).
- `Shutter.Operation.Releaser` (production item "Case Releaser", v1.35), a service on `Ens.InboundAdapter` (`CallInterval` 5 s)
  that releases the cases no other host can: a case blocked or escalated while a newer message of its encounter was in
  flight at a watched production (`waitsOnMessage`; that production's connector knows nothing of Shutter), a case
  held for a schema not loaded when its message was read (`heldSchema`, 11), and a case blocked while the engine was still
  trying its message (`waitsOnEngine`, 6.5). Each sweep counts the candidates first; when
  there are any it opens a run row, `Shutter.Store.ReleaseRun` (`startedAt`, `endedAt`, `state` running, done, failed or
  interrupted, `waitingChecked`, `waitingReleased`, `heldChecked`, `heldReleased`, `error`, `job`), runs
  `ResendGuard.ReleaseDeliveredWaits` and `Schemas.ReleaseHeld`, then `Releaser.ReleaseEngineWaits`, which reads the marked
  header and resolves a case the engine delivered (the gate's own words and rules), plans one again when the engine has
  settled it, with every blocked case on that header and never an escalated one, and leaves one still with the engine or
  unreadable; its counts join the waiting counts on the run row. Each release goes from this host to the Case
  Workflow as an id-only `Shutter.Msg.Reinvestigate` (`caseId`, `requestedBy` system, `reason`); the sweep then ends the row: the
  host is the one writer that ends a run. A quiet sweep writes no row, only its time. At start every run still open is
  marked interrupted, since the host starting again means a restart cut it. The newest 500 runs are kept (`KeepRuns`).
  `GET /index` carries `releases` `{host, started_at, last_sweep_at, sweeps, last_run, runs, interrupted_runs, candidates
  {waiting, held, engine}, engine_unreadable}`, the last the number of waits on the engine the last sweep could not read (all of
  them when the sweep stopped before reading them), and the Doctor `release_sweep`. Until v1.35 the HL7 Index adapter's task ran the two checks beside its
  walk; the adapter now only reads, and a site that installed Shutter earlier gets the item from the installer's item list.
- The index is a finder, never a second source of truth: every decision still opens the message or asks the receiver.

### 8.2 The timeline

- `Shutter.Index.Timeline.ForCase(case)` builds the snapshot's `timeline`: the feed's operations for the encounter
  since the last reset, from Shutter's typed messages with their delivery outcome (`source: "feed"`), merged by event
  time with the index's rows for the same visit number that the feed did not carry (`source: "index"`, with `route`,
  `message_type` and a `note`). An indexed message's `outcome` is `unknown`: the gate's supersession check and the
  matcher's `later_applied` count only `applied` and `already_committed`, and outside a chain a later transfer of the
  feed's own whose failure the connector recorded (6.1, v1.16), so it supersedes nothing by itself; the receiver's
  history decides. The board sees it and can say so.
- Both keep to the case's patient and authority: a visit number can be reissued or numbered by two authorities, and another
  patient's message under it is no word on this patient's place, so it can't close the case. The deliveries (`Deliveries`,
  a bed's occupant) and the pending messages (6.5) still read the whole visit, so another patient's message in flight holds
  a write. A patient's later rows under another identifier after a merge the receiver hasn't taken aren't counted either.
- S14 plays a later movement on a route Shutter does not own, found only by the index: the demo item `Other Route In` (`Shutter.Scenarios.Route`, Rules only and Site policy) sends it to `Case Intake Store`, so its header is walked and nothing reaches the receiver. The item types the message under the category its MSH-12 names when that is loaded, as an inbound item's category would. A site's production never gets the item, nor the route in its `HL7 Index` (`Setup.SiteRoutes`).
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

The rule (19 Oct 2026): only what is needed goes to the model. The stored snapshot is complete and stays inside
IRIS (the gate, the matcher, the verifier and the app read it); what a model receives is a reduced copy made by
`Shutter.Util.ModelView.Reduce` at the two places anything of a case leaves: the agent request's context
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
  also the visit number is one token); a value that itself looks like a token is left as it is, and a value shorter than three characters is never tokenised, except a name part, which is from two (v1.16: a surname such as Li or Ng; a single initial is left, since as a token it would replace every standalone letter). Values of three characters or more are matched whatever their letter case (v1.16: `SMITH` in the message, `Smith` in an error echo); a two-letter name part only as written, so a short word of the summary's own text (`no`, `to`) is never taken for a name. The view fails closed (v1.16): `ModelView.Learn` returns an error when the case names a message that cannot be read or a value's token cannot be stored, and the case workflow then builds no agent request, sends nothing and escalates the case; `ModelView.Reduce` answers `{"error": ...}` instead of a view for a case whose own patient or encounter has no token, and `BuildAgentRequest` then builds no request either: the case is escalated with that text and nothing is sent (v1.21).
- **Demographics never go**: `patient_name`, `name`, `given_name`, `family_name`, `date_of_birth`, `dob`, `sex`,
  `gender`, `address`, `phone`, `email`, `next_of_kin` and the like are dropped wherever they occur.
- **Free text never goes.** Each OBX or NTE note becomes `{segment, position, observation_id, value_type,
  free_text_present, instruction_like, note}`, where `note` says the text stays in IRIS (or that a binary or reference
  value is never sent); the text stays in IRIS. `instruction_like` is a word-list flag (ignore, override, you must, resend, approve and the like),
  not a verdict. The site profile's `model_content.free_text: true` sends the text; the default is off.
- **Pending messages are operational rows** (v1.29). The `pending_messages` section keeps each row's event, time,
  operation key, control id, header id, arrival, receiver and where it waits; no content of the message.
- **The bed's occupant is a token** (v1.28). The `bed_conflict` section names the occupant by their encounter id only,
  which the collector learns as one of the case's tokens (`ENC-T2`); the occupant's state read keeps `state`, `ward`, `bed`
  and `version`, and nothing of their patient record is read or kept.
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

**Denied tool calls** (v1.35). A call the scope policy refuses before it runs (another case's evidence, a tool outside the
role) never reaches the audit policy's `%LogExecution` on build 154; it reaches `%LogDenial`, and Shutter writes it as a
tool-call row of its own: `denied` true, `ok` false, `durationMs` 0 and the reason in `error`, with a "denied" trace line
in the Visual Trace. The case page lists it with the run's other calls (`GET /cases/{id}/runs`, `toolCalls`), so a prompt
that tries to reach past its case leaves a mark, and `Shutter.Bridge.ToolCall.DeniedCount(runKey)` counts a run's refusals.

- A merge's prior identifiers (v1.14: `prior_patient_id`, `prior_encounter_id`, `prior_patient_identifier`, `prior_visit_number`, and every MRG group's in `prior_identifiers`, each paired with the surviving patient identifier of its PATIENT group as `into`) are tokens like the case's own (PID or MRN or NHS by the identifier type, ENC, VISIT; the prior name's parts NAME); `merge_groups`, `patient_class` and the validation's version fields pass through.

**The production review's agent** (v1.22; 13.6) is the one other place something leaves for a model, and it does not go through `ModelView.Reduce`: there is nothing to tokenise, by construction. Its context holds the review id, the namespace, the production and its state, the window, the summary, the findings without `evidence.example`, `annotationId`, `rank` and `explanation` (an `ERRORS_GROUPED` signature, the event log's own text before its first colon, which an application can fill with a name, reaches the model only as an IRIS error code such as `ERROR #5001` or `ERROR <Ens>ErrBPTerminated`, and otherwise as `[withheld text <12 hex digits of its SHA-256>]` in `found` and in the words that quote it; the stored finding keeps it), and the case aggregates per item (counts by failure kind, outcome, reason code and state; the newest case ids). The aggregates' keys come from the cases' own fields, which `POST /intake` and a connector's `reason_code` can fill with any text, as free text or as one word that looks like a code (a surname, a postcode), so the model reads only what Shutter itself knows as it is: an item key that names an item of the production (or `(none)`), a failure kind or a state from the case's own lists, an outcome of the connector's or the intake's (`applied`, `uncertain`, `rejected`, `error`, ... and an acknowledgement's code such as `AR`), and a reason code that Shutter, its connector or the downstream contract writes (`alert`, `schema_unknown`, `merge`, `cancel_unsupported`, `ward_unavailable`, `duplicate_message`, ..., `ack_AE`, `ack_AR`, `ack_CE` and `ack_CR`), with `HTTP_` and three digits for either of the last two; every other key, a code's shape included, goes as the same `[withheld text ...]` digest, with its count. A site's receiver with codes of its own sees them as digests, still counted apart; the stored review keeps every key. The words of a check fill their placeholders in one pass, so a signature that holds `(s)` or `{count}` stands in them as in `found` and is withheld there too. The sweep never reads `CaseEvent.Text`, the operation key's patient and encounter pieces, `FailureText` or message content, so none can reach the context; item names, setting values, counts, header ids and case ids are operational identifiers, as the board's evidence carries them, and the error example text stays in the operator's `GET`. Nothing comes back to restore: the agent speaks in finding ids.

**The day's model budget (v1.34).** `SHUTTER_DAILY_BUDGET_USD`, read by the installer and at every start of the production
(`Setup.ApplyEnvironment`, 12) into `^Shutter.Config("dailyBudgetUsd")`
(`Shutter.Util.Budget`; 0, unset or not a number means no cap), caps what the live and record agent runs may spend between one
00:00 UTC and the next. Before a run that would call a model, the Agent item asks for admission (`Budget.Admit`, below), which sums the day's
`AgentRun` rows' `CostUSD` as `GET /costs` does (a replay or a run the API mimic answered spent nothing); once the spend has
reached the cap, or the run's estimate no longer fits (1.4.6), the run is not sent, and the response's status is `budget_exhausted` with an error naming the cap, the spend
and when it resets. A board whose members all answered so has no board answer (6.6), as when replay mode has no recording
(the case says which); a question or a review fails with the status. `GET
/settings` and the Doctor carry `budget: {dailyUsd, spentTodayUsd, exhausted, since, resetsAt, perUserUsd}`, and `GET /settings`
adds the caller's own `spentByMeUsd` and `shareExhausted`. The public demo sets the cap with an API key of its own; the cap bounds
spend plus estimates, not the provider's invoice (below). **Each user's share** (`SHUTTER_JUDGE_BUDGET_USD` into `^Shutter.Config("judgeBudgetUsd")`,
0 or unset means none): every agent request carries who asked (`RequestedBy`: a question's asker, a judge who convened the
board, since v1.57 the user who started the scenario run that opened the case (`Shutter.Store.Case` `ScenarioBy`, from
`^Shutter.Config("scenarioBy")`, which the runner's Begin writes and its Reset clears), `system` for the feed's own runs), the run keeps it, and a run for a user whose live runs today have reached the share is
refused `budget_exhausted` with "Your share of the day's model budget ... is spent", so one judge cannot spend the day. A replay-only scenario run's runs (v1.58, 4.2) are replays: the Agent item asks the budget nothing and reserves nothing for them, and they cost 0, so they count against neither the cap nor the starter's share.
**Whether the live agents can run (v1.37).** `GET /settings` carries `live.agents = {available, reason, until, detail}`
(`Shutter.Util.LiveAgents`), one signal for the web's notice: `reason` is `budget` when the day's cap or the caller's share
is spent, or since 1.4.6 has less left than the next run's estimate (`until` = `budget.resetsAt`; `detail` then says which limit, "Your share ..." for the share), `provider_auth` when a live run failed with an authentication error (a 401, a bad or
deactivated key) within the last 15 minutes (`until` = the next 00:00 UTC, when a key a site deactivates for the day comes
back; the flag clears on the next live run the provider accepts, and after 15 minutes one run tries again), and null when
live runs can go; `detail` is the sentence to show. As built in 1.2.0 (v1.48), the flag is set only by a run whose status is `error` with an authentication
error's words (`LiveAgents.NoteRun`), and the live runner reports a provider's own error as `model_error` (`AIHub.cls`, its
`Catch`), so a key the provider refuses doesn't set it yet: each run still calls the provider and ends `model_error`. While the provider refuses the key the Agent item refuses runs that would
call a model with the status `provider_auth` and makes no call (a board whose members were all refused so has no board
answer, 6.6, as for `budget_exhausted`), `POST /cases/{id}/board` answers `409 live_unavailable` with `live`
(the availability object) before the budget is looked at, and a question from a caller with the live agents is answered from
its recording when it has one and refused `409 live_unavailable` when it has none. **The demo's budget note** (v1.37):
`SHUTTER_DEMO_BUDGET_USD` and `SHUTTER_DEMO_BUDGET_PERIOD` (`day` or `hour`, day by default), read at the install and at every
production start like the cap, set `live.budgetNote = {amountUsd, period}` in `GET /settings` for the live banner, which says it
to a caller with `Shutter_LiveAgents` only (the judges; the public demo's role reads the board's line instead): the figure
the demo's owner spends on live runs, which a site may enforce outside Shutter (a key deactivated at the figure) while the
cap here guards a burst; absent when unset (an empty, zero or non-numeric value clears it), and the web shows the cap then.

**Reserve, then settle (v1.35).** A run in flight has no `AgentRun` row yet, so three members running at once were not
counted against the cap until they finished. The Agent item now reserves an estimate for each live run it starts
(`Budget.Reserve`, keyed by the run) and settles it when the run ends whatever its outcome (`Budget.Settle`); the day's state
carries `reservedUsd` and `inFlight`, `GET /settings` adds the caller's `reservedByMeUsd`, and a run is refused once spend plus
reservations reach the cap (or spend plus the user's own reservations the share), the refusal naming the runs in flight. **Admission (1.4.6).** `Budget.Admit(key, user)` admits a run only when the day's spend plus the reservations plus the run's own estimate stay within the cap and, for a user other than `system`, the user's spend plus their reservations plus the estimate within the share, and reserves it in the same step, under one lock (`^Shutter.Budget("admit")`, which `Reserve` takes too; nothing in src calls `Reserve`, the unit tests use it, and since 1.4.7 it writes nothing when the lock is not free in time), so two runs cannot both be admitted on the same remaining allowance; refused, nothing is reserved and the refusal says what is left and the estimate. `AllowsFor`, which `POST /cases/{id}/board` and `live.agents` ask, applies the same rule with nothing reserved, and the budget object it returns carries `estimateUsd`. This bounds spend plus estimates, not the bill: a run can cost more than its estimate, a reservation older than twenty minutes is released whether or not its run has ended, the Agent item settles a run before the workflow writes its row, and a production review's cost is kept on `Shutter.Store.Review`, which the day's spend does not read. With nothing spent or reserved under a limit (the day's cap, or the user's share), one run is admitted whatever its estimate (1.4.7, `Budget.Short`): the estimate moves only when live runs land, so a cap or a share smaller than one run's estimate would otherwise refuse every run for good; once anything is spent or in flight under it, the estimate counts again, so such a limit admits about one run a day (a user's share, one run of theirs). An admission that cannot take the lock within 10 seconds (`ADMITLOCKSECONDS`; another admission holding it) is refused with its own status, `budget_busy` (1.4.7; `budget_exhausted` in 1.4.6), whatever the cap, with words that say the budget could not be checked in time and to try again: nothing is spent, and a case counts it as a failed run (6.6), not a spent budget. The
estimate is `^Shutter.Config("budgetReserveUsd")` when the site sets it, else the mean cost of the last twenty live runs that
cost anything, else 0.50 USD, never below 0.01; a reservation older than twenty minutes was left by a job that died and is
dropped when next counted.

**Invisible characters are stripped (v1.35).** `ModelView.Restore` removes from everything a model wrote, before the store
keeps it, the zero-width characters (U+200B to U+200F, U+2060 to U+2064, U+FEFF), the bidirectional controls (U+202A to U+202E,
U+2066 to U+2069) and the control characters other than tab, line feed and carriage return, as characters and as JSON escapes
(`ModelView.Clean`); tabs, line breaks and ordinary Unicode stay. So a summary an approver reads on the case page or in an
escalation email reads as it is, with nothing hidden in it and nothing that reverses a line.

**The run's own clock (v1.35).** Every run row keeps `startedAtMs`, the start to the millisecond, beside `startedAt`, and
the three counters AI Hub's session returns on build 154 when it does: `llmMs` (time inside the model's calls), `toolMs`
(time inside the tools) and `reasoningTokens`; a replay or a build that gives none leaves them empty, never zero. With the
tool-call rows' `at` and `durationMs`, the case page can draw a run as a timeline (the run bar, the tool bars, the model's
turns as the gaps between them) from stored rows alone, and the DPI-I-689 queries can split a run's time.

**A FHIR case** (v1.63). No agent plans or reviews a FHIR plan: `Shutter.FHIR.Flow.Plan` makes it, from the catalogue's one matching entry when that says resend (Rules only proposes the update whatever the catalogue matched), and asks for a person otherwise; a board that was asked for is declined with a note on the case (20). A question about a FHIR case (14) may still run. In its model view the summary's `fhir` object is left out, since the summary allowlist (`ModelView.SUMMARYKEEP`) does not name it, and `ward_state` is the projection of the Encounter in the shape every reader of a receiver's state takes (visit number, patient, state, ward, version).

## 10. Escalation by email (v1.11)

**Correcting the history** (v1.23, v1.50). When a `history_of_record` receiver's case escalates with the outcome
`correct_history`, the plan carries `correction_steps`: `{receiver, system, category, encounter, missing: {event, ward,
event_time, source_message_id, operation_key, after}, later: [{event, ward, event_time, operation_key, source_message_id,
ens_header_id}], current: {state, ward, version}, receipt, steps: [text], sequence}`, built by
`Shutter.Util.HistoryCorrection` from the case and the snapshot. The eight steps, in order: hold the case and never resend
the original message; confirm the current placement, reading only; confirm the gap and where the movement belongs; have the
correction approved and recorded; correct the record through the receiver's own records procedure, one write by one person
(a Z99 historic-movement update can't add a movement the receiver never got, so none is offered); under that procedure keep
the current placement; read the history back and have a second person check it; record it on the case and close the case by
hand. The escalation draft prints them as a section "CORRECTING THE HISTORY"; the case page shows them from the plan.

**The drafted sequence** (v1.50). Beside the receiver's own procedure, Shutter may draw the exact cancel-and-replay sequence
a person could send. It sends nothing: there is no Send button and no write path, and the gate, the verifier and the
approvals never read it. For k later movements it is 2k + 1 messages: k cancels, newest first (A12 for a transfer, A13 for a
discharge), then the failed movement, then the later movements, oldest first, because a cancel reaches only what is current
at that step. A replay is the stored message exactly as IRIS gives it back. A cancel is built by a fixed table from the
message it cancels: MSH-3 to 6, MSH-11, MSH-12, PID, PV1-1, PV1-2, PV1-19 and PV1-44 copied; on an A12 PV1-3 is the cancelled
message's PV1-6 (HL7: the location before the original transfer), PV1-6 its PV1-3 (Shutter's choice, as the fixtures do) and
PV1-45 copied; on an A13 PV1-3 is the discharge message's PV1-3, with PV1-6 and PV1-45 empty; MSH-7, MSH-10, EVN-2 and EVN-6
are placeholders a person fills (`[SENDER: ...]`, `[SITE: ...]`). MSH-9 is `ADT^A12^ADT_A12` or `ADT^A13^ADT_A01`, the
structure HL7 2.5.1 gives each.

`correction_steps.sequence` is structure only, with no message text, name or address, because the plan is sent, reduced, to a
model (section 9): `{drawn, reason_code, reason, k, count, receiver_version, observed_at, cancels_flag (true, false, or null
when the profile has no entry), resend_timestamp, steps: [{n, kind (cancel, replay), trigger, cancels?: {event, ward,
event_time, operation_key, source_message_id, ens_header_id}, event?, ward?, event_time?, operation_key?, source_message_id?,
ens_header_id?, body_digest? (of the stored text as IRIS gives it back), non_ascii, after: {by_source, by_receiver}}],
end: {ward, history}, checked_at}`.

Only E1 and E6 are drawn. The first of these that holds draws nothing, with `reason_code` and a line that starts "No
sequence:", and the eight steps stay: `not_e1_e6` (another entry, or a failed movement that isn't a transfer); `cancels_false`
(the profile says false, or has no entry for the receiver: the seed says false for both demo receivers, so a shipped S22 draws
none); `identifier_unreadable`; `merge_seen`; `forwarded_case` (a case forwarded from another namespace, whose feed isn't indexed here); `feed_not_indexed` (the index behind:
not yet, not no, so its line starts "No sequence yet:", an approver is offered the read, and every read decides again);
`pending_message`; `further_message`; `later_undelivered`; `later_not_movement` (a later admission, merge or cancel);
`history_mismatch` (the receiver's rows and the feed's don't match one for one by operation key); `k_zero`; `time_in_doubt`;
`history_mismatch` again (the receiver's current placement isn't the last movement of its history, so the first cancel wouldn't
reach what is current); `body_unreadable`; `pv1_6_empty`; `zbe_present`; `cancel_non_ascii` (what a cancel copies holds a
character above ASCII: the copy may not match the bytes sent, and a cancel isn't in the message store to resend);
`receipt_present`. A replay above ASCII doesn't stop it: its text is withheld with a line saying to resend it from the message
store.

`further_message` is the patient-level check (`Shutter.Index.Message.ForPatient`, asked for every identifier in the failed
message's PID-3; it respects each identifier's authority, and a row or an identifier with no authority can't be told apart and
counts): any message for this patient since the reset, on any encounter, that the failed movement and the later
movements don't account for, with an event time at or after the failed one, received after the failed message or after the
snapshot, or with no readable time. An earlier stay is not a further message. An update (A08) is a further message like any
other, inside the span or after it, and one before the failed movement isn't. The check can't see a change made by hand at the receiver, a
message on a route the index doesn't cover, or a message the index keeps under an identifier the failed message doesn't hold (the
index keeps one per message: the repetition typed MR, else the first); there is no match on a name or a date of birth, because a
different patient must not match. The draft says so.

`GET /cases/{id}/correction-draft` (`Shutter_Approve`, an approver's, because this is raw HL7 with a name and an address; 401
signed out, 403 `forbidden` naming the resource for an operator) gives the text. 404 `not_found`; 404 `no_plan`; 409
`wrong_outcome` when the plan has no `correction_steps`. Otherwise 200 `{caseId, drawn, reason_code, reason, header: [line],
messages: [{n, kind, trigger, label, text (null when withheld), withheld, after, body_digest}], cannot_know: [{what, why, does}],
never: [line], digest, checked_at}`; with `drawn` false the lists are empty. `text` is the message with
segments ended by a carriage return, as IRIS gives it. Every read runs the checks again on the live index and pending list, so
`drawn` here wins over the plan's, which is the state at plan time. It never reads the receiver. A read with `drawn` true appends
a `note` event to the case, "Correction draft read by <user>: <n> messages, digest <digest>", with no message text; a read
with `drawn` false appends nothing. The email carries one line and none of the text: "A drafted sequence of <n> messages is on
the case, for an approver to read on the case page; this email carries none of it." or, with `feed_not_indexed`, "No message sequence has been
drafted yet: the index hadn't caught up with the feed when the plan was made. An approver can read it on the case page, which
checks again on every read; this email carries none of it." or "No message sequence was drafted: <the reason>."

A blocked, escalated or failed case can be handed to the people who correct systems by hand. The draft is built from
the stored case without a model (`Shutter.Util.EscalationDraft`): the hospital number and NHS number, the date of birth,
the event (what, where, when, the operation key), what failed, why Shutter stopped (the block reason and the failing
checks), what the receiver holds with its history, the encounter's timeline from the feed and the index, what Shutter
sent, and references. No name, address or note text. A person reviews it, chooses the team and sends it; the send is
bound to the digest of the text the person read. Its last section asks the team, once corrected, to mark the case as
handled: Reinvestigate collects fresh evidence and can plan another resend, which a site's policy may release with no
person, so it is never offered as a check of the correction; with no state endpoint, or for a message Shutter does not
model, the draft says Shutter cannot verify a correction.

- The site profile's `teams` (array of `{id, name, mailbox, cc?: [...], receivers?: [...], sources?: [...]}` (v1.14: `sources` lists sending applications, MSH-3, such as `PAS`; a merge goes first to the team whose `sources` lists the case's source system, then to the receiver's team, then to the first team; the draft words a merge "Merge of <prior identifier> into <patient identifier>" and a cancel "Cancellation of the transfer at ..."; a cancel carries no ward, section 2); a withheld case's draft says Shutter withheld the message and asks the team to mark the case handled rather than to reinvestigate; `id`, `name` and
  `mailbox` required, ids unique) and `mail` (`allowed_domains`, a list of domain names such as `example.nhs.uk`, required before any email can go: every team `mailbox` and `cc`, and every `to` and `cc` a person types, is one bare address, `local@domain`, with exactly one `@`, no display name, brackets or spaces, no line break or other control character, and a domain equal to one of the list or a subdomain of one (`trust.nhs.net` under `nhs.net`), compared without regard to case; an empty or absent list allows no address, so a profile that names a team mailbox without one is refused (400 `bad_request`, `teams[i].mailbox: no allowed mail domains are set in the site profile (mail.allowed_domains)`), and each entry must be a domain name (`mail.allowed_domains[j]: must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)`); the addresses are checked when the profile is saved, at `PATCH`, at the send and once more by the operation before it writes or sends (v1.21). `from`: the sender of the emails when set, an address of the same shape (the profile is refused otherwise), else the `Escalation Mail` operation's `From` setting, default `shutter@localhost`. The shipped seed profile sets `allowed_domains` to `["example.nhs.uk"]`, the domain of its teams' mailboxes, and no `from`, v1.21). The team for a case is the one whose `receivers` names the case's receiver, else the first, else the
  profile's `approvers.escalation` text with no mailbox (the person fills one in).
- The reminder for cases left open goes by this mail server and `mail.from`, with nobody reviewing it: section 6.4, "The reminder for cases left open".
- `GET /cases/{id}/escalations`; `POST /cases/{id}/escalations` with `{teamId?}` answers 201 with the draft (409
  `wrong_state` unless the case is blocked, escalated or failed; 500 `draft_failed` when `teamId` names no team of the
  profile); `PATCH /cases/{id}/escalations/{seq}` (404 `not_found` for an unknown seq; 400 `bad_request` when the body is
  not a JSON object, when one of `subject`, `body`, `to` and `cc` is not a string, or when one is longer than its
  column: the subject 500 characters, `to` and `cc` 2000) with `{subject?, body?, to?, cc?}` edits a draft or a failed
  email of a case that is blocked, escalated or failed (409 `wrong_state` otherwise, the detail naming the case's state
  or the escalation's) and moves `bodyDigest`, the SHA-256 of `to`, `cc`, `subject` and `body` together, so a change of
  recipient alone moves it; `POST /cases/{id}/escalations/{seq}/send` with `{bodyDigest}` answers 202 with the queued
  escalation, 409 `wrong_state` when the case is no longer blocked, escalated or failed (closed by hand, or reopened) or
  the escalation is neither a draft nor a failed one, 409 `body_changed` when the digest is not the current text's, 409
  `no_recipient` when `to` is empty, 422 `address_not_allowed` (with `field`: `to` or `cc`) when an address is not one
  bare address, lies outside the allowed domains or the profile sets no allowed domain, and 422 `subject_not_allowed`
  (with `field`: `subject`) when the subject carries a line break or a control character; `PATCH` answers the same 422s
  for the email as it would stand after the edit (a `to` the edit leaves empty is 422 `address_not_allowed` too)
  (v1.21). All need
  `Shutter_Operate`; the writes need `X-Requested-With` and take an `Idempotency-Key`. The escalation keeps who drafted,
  edited and sent it (`draftedBy` and `draftedAt`, `editedBy` and `editedAt`, `sentBy`, the person who pressed send, and
  `sentAt` when the operation sent it through the mail server, or since v1.53 `savedAt` when it saved it as a file), and
  the case event of the send names who queued it, for whom and, since v1.17, the digest of the text ("Escalation 1 queued
  by operator for ...; digest of the text queued <bodyDigest>" since v1.53; it read "sent by ... digest of the text sent"
  before the transport was known).
- The `Escalation Mail` operation (`Shutter.Operation.EscalationMail`, `EnsLib.EMail.OutboundAdapter`) sends through the
  site's mail server when the adapter's `SMTPServer` is set (first-time configuration; the NHS relay at most trusts),
  and otherwise writes an `.eml` file to its `OutputFolder` (default `<mgr>/shutter/out/mail`), so the demo and CI need
  no mail server. **An escalation written as a file reads `saved`, not `sent`** (v1.53): nobody was emailed, and its case
  event says "Escalation 1 saved as an email file, not delivered: <path>. No mail server is set, so nobody was emailed."
  One the mail server accepted reads `sent`, its event "Escalation 1 sent through the mail server: <the server's words>"
  (the server's acceptance shows no person has read it, and the words say so). A row stored before v1.53 with `transport`
  `file` and `state` `sent` reads `saved`, with `savedAt` from its `sentAt`, on every route and in every count, so nothing
  is migrated; the shadow report's `notification_deliveries` counts `sent` alone. A `saved` escalation can be sent again,
  as a draft or a failed one can, once a mail server is set; a case is closed by hand after an escalation that was sent or
  saved, and the close's words name its state. Before writing or sending, it checks the subject and the addresses once more against the profile as it
  stands and marks the escalation `failed` with `Refused before sending, <field>: <problem>` when they no longer pass
  (the domains changed after the send was accepted, or the row was changed outside the API); a failed escalation can be
  edited and sent again. In the `.eml` every header value is one line: tab, CR and LF become spaces and other control
  characters are removed, and a header longer than 78 characters is folded at a space or a comma with CRLF and one
  space (RFC 5322 2.2.3); the SMTP message's subject and addresses go through the same cleaning (v1.21). States:
  `draft`, `queued`, `sent`, `saved` (v1.53), `failed` and `cancelled` (closing the case by hand, `POST /cases/{id}/close` in 5, cancels
  every draft or queued email of the case); each step is a case event of kind `escalation`. Then
  `POST /cases/{id}/close` marks the manual correction as handled; `POST /cases/{id}/reinvestigate` collects fresh evidence and can plan another resend.
- Retention (v1.21). The daily task "Shutter retention" removes the text of an escalation (`body`, the one copy of the
  NHS number and the date of birth outside the message store) and its `.eml` file `EscalationDays` days after the case
  closed (the task's setting; the installer sets it from `SHUTTER_ESCALATION_DAYS`, else `SHUTTER_MESSAGE_DAYS`, else
  90; `0` keeps them), for every state but `queued`. The row stays: `state`, `to`, `cc`, `subject`, `bodyDigest`, who
  drafted, edited and sent it and when, `transport` and `result`; `body` is empty and `purgedAt` says when, and the case
  gets an `escalation` event ("Escalation 1: the email's text was removed 90 days after the case closed; the digest of
  the text sent, the recipients and who sent it stay on record"). `PATCH` and `send` on a purged escalation answer 409
  `wrong_state`. A reopened case's escalations are left until it closes again. When a site switches the case purge on, it takes finished cases only: resolved, which covers handled by hand, and abandoned. A blocked, escalated or failed case nobody acted on stays, whatever its age, and so does an incident that holds one. A
  purged case's escalation rows and `.eml` files go with it, and the task removes escalation rows whose case went
  before this rule.

## 11. The case intake from another production (v1.15)

Shutter can open a case for a delivery that failed in a production it does not own (the install document's shape A,
`docs/INSTALL.md`). The intake is self-contained and Shutter keeps its own copy of the message; the watched namespace
needs only the packages `Shutter.Intake` and `Shutter.Util` for the forwarder and the alert intake (11.1 maps them).

- `POST /api/shutter/intake`, resource `Shutter_Intake` (the role `Shutter_Forwarder` carries it, and only it: the
  forwarder's user can call no other route; the demo user is `forwarder`, password `shutter`, the `SHUTTER_DEMO_PASSWORD`
  rule as for the others). The caller signs in with HTTP Basic authentication and sends `X-Requested-With: Shutter`; an
  `Idempotency-Key` is honoured as on the other POSTs. The body: `{"source": {"namespace", "production", "route",
  "header_id"}, "receiver": "<the item that delivered; the receiver's name in the site profile>", "failure": {"kind":
  "delivery_failed" | "rejected" | "uncertain_outcome" | "unmappable" | "unreadable", "text", "outcome": "unavailable" | "error" |
  "uncertain" | "rejected" | "", "http_status", "reason_code"}, "message": "<the HL7 text, segments separated by
  carriage returns>", "schema_category": "2.5.1", "mode": "board"}` (the last two optional). Answers 202 `{"caseId",
  "state", "opened"}` (`opened` false when a case for the same operation key is already open, as the feed's own
  intake); 400 `bad_request` naming the field (no JSON object, no message, an unknown kind); 413 `too_large` for a body over
  2 MB (v1.35); 401; 403; 503 `no_service` or `not_queued`.
- Inside the production: the API service sends `Shutter.Msg.ExternalIntake` (the body's fields as properties:
  `SourceNamespace`, `SourceProduction`, `SourceRoute`, `OriginHeaderId`, `Receiver`, `FailureKind`, `FailureText`,
  `FailureOutcome`, `FailureHttpStatus`, `FailureReasonCode`, `MessageText`, `SchemaCategory`, `Mode`, and `SignedInUser`, the user signed in to the route, which the case records in a note) synchronously to
  the item **Case Intake** (`Shutter.Process.Intake`), which parses the text (`EnsLib.HL7.Message.ImportFromString`, the
  DocType resolved from the category, 2.5.1 when none), sends the message to **Case Intake Store**
  (`Shutter.Operation.IntakeStore`, an adapterless operation that only answers) so that the copy has an
  `Ens.MessageHeader` in Shutter's namespace, builds the operation with `OperationKey.FromHL7` (or `Unmapped`, with the
  kind `unmappable`, when it does not map), and sends `Shutter.Msg.CaseIntake` to **Case Workflow** with the failure, the
  stored copy's header as `SourceHeaderId`, and the receiver and source fields. The case workflow answers as soon as the
  case row is saved (`Reply`), so the route carries the case id within seconds. The HL7 Index's `Routes` names
  `Case Intake` beside `ADT In`, so the stored copies are indexed.
- The case carries `bed` (PV1-3's room and bed components for an admission or a transfer, else null; v1.28), `waitsOn` (the case it
  waits on while the gate holds its write with `WAITING_FOR_OCCUPANT_CASE`, 6.5; null otherwise; cleared by a reopening) and
  `waitsOnMessage` (the control id of the newer message it waits for under `NEWER_MESSAGE_PENDING`, 6.5, v1.29; null otherwise;
  cleared by a reopening) and `waitsOnEngine` (`namespace:header id` of the header the engine still holds, under
  `ENGINE_STILL_TRYING`, 6.5; null otherwise; cleared by a reopening; v1.47), on `GET /cases` items and `GET /cases/{id}` alike; `GET /cases/{id}` adds `waitedOnBy`, the ids of the
  cases whose `waitsOn` names it (v1.29).
- The case carries `receiver` (the intake's, else the connector item), `sourceNamespace`, `sourceProduction`,
  `sourceRoute` and `originHeaderId`; the evidence snapshot has an item of kind `source` and the summary a `source`
  object `{namespace, production, route, header_id}` (kept for the model view, since it carries no patient data). The
  gate's receiver and the policy's tier follow the case's receiver. Everything else (the evidence against the receiver's
  API from the site profile's entry, the matcher, the board, the gate, approvals, the escalation) is as for the feed's
  own cases; a resend goes through Shutter's connector item, so a forwarded case's receiver is normally the name of
  that item (`Downstream Out` in the demo).
- **An automatic release needs a proved source** (`Shutter.Operation.Origin`). The route takes what a holder of `Shutter_Intake` posts, so before the policy
  path releases a case with no person, and again at the dispatch gate (`APPROVAL_ORIGIN_NOT_PROVED`, 6.5): `sourceNamespace` must be readable and hold the header `originHeaderId`
  names, that header's HL7 message must be the text received (line ends aside), and its session must have sent something to the receiver (with or without the forwarder's
  prefix on the name; a held message of kind `unreadable` went to the forwarder, so that part is not asked). Otherwise the case goes to a person, with "Source not verified" and the reason in its notes and the
  approval task. A case the feed opened itself has nothing to prove; the route with no source namespace does not prove. It does not stop a genuine message being posted again. The site profile's
  `feed.prove_origin` false turns it off, for a forwarder that reports from another instance.
- **The forwarder.** `Shutter.Intake.Forwarder` is the item a watched production adds: a business operation on
  `EnsLib.HTTP.OutboundAdapter` (queue). Request `Shutter.Intake.Forward`: `HeaderId` (the failed HL7 message's header
  in the sending namespace), `Receiver`, `FailureKind`, `FailureText`, `FailureOutcome`, `FailureHttpStatus`,
  `FailureReasonCode`, `Route` (empty takes the header's `SourceConfigName`). Response `Shutter.Intake.Forwarded`:
  `CaseId`, `State`, `Opened`, `Error` (empty on a 202 naming a case; otherwise the HTTP status and body, or the connection error; a 202 with no case id is a
  refusal). A forward nobody answered, or answered 502, 503 or 504, stays in the item's queue and is tried again until `FailureTimeout` (300 s on this class; 0 tries
  once; -1 never gives up), quietly, and only then refused; any other answer is refused at once. Settings: `IntakePath` (default `/api/shutter/intake`), `SourceProduction` (default the running production's
  name), `SourceNamespace` (default the namespace), `SchemaCategory` (default the message's own category, else 2.5.1);
  the adapter's server, port, credentials (HTTP Basic as the forwarder's user) and SSL configuration are the site's.
  `ReceiverPrefix` (v1.42; default empty) goes in front of every receiver's name in the body, so that a namespace's item of
  the same name as another namespace's is another receiver. The sending production's process calls it on a failed delivery
  with the failure as its connector reported it; the packages `Shutter.Intake` and `Shutter.Util` are mapped into that
  namespace (the demo hospital also maps `Shutter.Msg`, `Shutter.Store` and `Hospital` for its own process).
- **A refused message, held** (v1.34, "prevent failures"; section 12). The forwarder is also an HL7 service's
  `BadMessageHandler`: a message the service refused before routing it (its `Validation`, say `dm`) arrives as an
  `EnsLib.HL7.Message` and is forwarded (`Shutter.Intake.Forwarder.ForwardFor`) with kind `unreadable`, reason
  `schema_unknown` and a text beginning "Held:" when the message's schema category (its document type's, else the receiving item's
  `MessageSchemaCategory`, else MSH-12) is
  not loaded in that namespace, or reason `invalid_message` when it does not validate against a schema that is loaded (a
  single bad message, not a wrong interface: no `heldSchema`, and the case reads as any refused message); the
  route is the service, the receiver the forwarder's `HeldReceiver` setting (empty: Shutter's connector item), and
  `schema_category` the category it was held for. Nothing was delivered: the engine held the message. The intake keeps the
  kind, parses Shutter's copy under 2.5.1 when the category does not resolve here, and the case carries `heldSchema` and
  `sourceNamespace`: the gate blocks it `SCHEMA_UNKNOWN` naming that namespace while the schema is missing there, the
  matcher says `delivery: unreadable`, no incident counts it, and the Case Releaser's sweep (8.1) releases it (a reinvestigation with the
  reason on the case) once the category is loaded in that namespace, after which it is a failed delivery to the catalogue
  and goes out through Shutter's connector under the site's policy. A production whose delivering process is its own code
  (the demo hospital's `PAS to Downstream`) does the check itself: while `^Hospital.Config("preventFailures")` is set
  (`Hospital.Setup.PreventFailures(1|0)`, called by every store of Shutter's profile and by the install from the profile's
  value), it reads each message's category before mapping it and hands one that is not loaded in its namespace to the
  forwarder as the held message above (`Forwarder.ForwardFor`), delivering nothing. The HL7 service's `Validation` is not a
  setting on this build and only a routing engine has a `BadMessageHandler`, so a site with a routing engine points that at
  the forwarder, and one with its own process adds the check.
- **The alert intake** (v1.35). A production whose delivering process does nothing on a failure beyond the error IRIS
  logs can still hand Shutter the failure, with no change to its own code: `Shutter.Intake.AlertProcess`, added as the
  production's `Ens.Alert` item (the name the engine sends alerts to), receives every `Ens.AlertRequest` an item raises
  (`AlertOnError`, a queue alert, an inactivity alert). Every alert is first passed on to `PassTo`, the site's own alert
  consumer renamed (an alert operation, an email), so Shutter adds to a production's alerting and never replaces it; an alert that
  consumer raised itself is not, or its failure would alert it without end;
  with `PassTo` empty the alert ends here, as it would with no `Ens.Alert` item at all. Then, for an alert from one of its
  `Receivers` (the connector items, comma-separated; empty takes any item) whose session holds an HL7 message, it finds
  that message (the header the alerting item was sent, so a DTL's change is kept; for an item that takes no HL7, the session's first header with an `EnsLib.HL7.Message` body, the
  receiving service's) and sends the
  forwarder (`ForwarderTarget`, default `Shutter Forwarder`) a `Forward` for it: `HeaderId`, `Route` the session's service,
  `Receiver` the alerting item, `FailureKind` from the alert's words (`rejected` for an AE or AR, a reject, a refusal, a NACK or an HTTP 4xx; `delivery_failed` for a connection that
  never opened or an HTTP 503; `uncertain_outcome` for a timeout, no response or
  an uncertain answer, and for anything else),
  `FailureOutcome` to match (`uncertain`, `rejected`, `error`), `FailureHttpStatus` when the text names one ("HTTP 503"),
  `FailureReasonCode` `alert`, or `alert_unread` for words it does not know and a connection lost after the frame went (the matcher reads that as `receiver_answer: unread`, 6.1, so no entry that resends matches), `FailureText` "Alert from <item> at <time> UTC: <text>". One forward per session and alerting item (v1.39; the item since onboarding, so a message routed to two receivers that both fail gives two): the pair is pending while the forward is out (`^Shutter.AlertIntake("pending", session, item)`, ten minutes at most) and seen (`^Shutter.AlertIntake("seen", session, item)`, kept a day) only once Shutter has taken the message, so a connector's retries alert the site each time but reach Shutter once, while a forward Shutter refused or that failed is built again from that item's next alert.
  An alert does not name its message, so a session that sent the item several different HL7 messages, or, for an item that takes no HL7, whose messages name more than one patient, opens no case: a warning and an alert to `PassTo` name the messages by control id and header, once per session and item (`^Shutter.AlertIntake("several", session, item)`, kept a day).
  An alert whose session has no HL7 message, from an item outside `Receivers`, or from the forwarder itself is passed on only,
  as is (v1.52) a queue alert (`QueueWaitAlert` or `QueueCountAlert` leading its words) on a message whose header to the alerting
  item still reads Created, Queued or Delivered: the engine is still trying it, so nothing failed and no case opens.
  **Shutter's own resend opens no case** (v1.53): a forward whose header in its source namespace is a clone one of
  Shutter's runs made (`Shutter.Store.ResendRecord.NewHeaderId`), or an origin with a ledger row that has started, is
  answered by Case Intake with 202 and the message's earlier case (`opened` false, `ownResend` true; `caseId` empty when it has none, which the forwarder takes only beside `ownResend`), so the
  session is marked seen, and the alert's words go on that case as an event of kind `resend` ("the engine alerted on
  Shutter's resend: ..."), or with no case on the outage as an alert line (17.8). The alert itself was passed on to the
  site's consumer first, as every alert is. No other
  alert is judged by the header's status, since the engine can raise one before it marks the header; both sends are
  asynchronous, so the feed never waits. The forwarder's refusal is a warning in the event log, as for the sending
  process, and an `Ens.AlertRequest` to the production's `Ens.Alert`, so the site's own consumer hears of a failure that has no case. The demo hospital's production carries the item with `Receivers` `Downstream Out`, `Lab Results Out` (v1.62, 4.5) and `FHIR Ward Out` (v1.64, 4), and its connector raises an alert
  for a delivery the ward system could not take or did not answer (`unavailable`, `uncertain`), as a real connector's
  would, so the alert path plays in the demo; its process forwards the same failure (above), and the intake answers the
  alert's forward with the case already open (`opened` false), so a failure reaches Shutter once as a case and twice in the
  message trace. `PAS to Downstream` stays out of `Receivers`. The production review's `NO_ALERT_CONSUMER` (13) names the
  item.
- **An application acknowledgement on its own feed** (v1.43). `Shutter.Intake.AckMatch.ForwardFor(ack, receiver, .problem, .session, lookback)`, called
  by a site's process on the feed (`tests/e2e/onboard_site/OnbAck.AckProcess.cls`; the service needs `IgnoreInboundAck` 0 and `AckMode`
  `Never`), reads MSA-1, MSA-2 and MSA-3 (else ERR-8) by position. AA and CA give no forward. AE, AR, CE and CR look among the last
  `lookback` messages (default 5000) whose header targets `receiver` for the newest with that MSH-10 (`FindSent`), and give a `Forward`:
  `HeaderId` the header found, `Route` the session's service, `Receiver`, `FailureKind` and `FailureOutcome` `rejected`, `FailureReasonCode`
  `ack_<code>`, `FailureText` the code, the control id, the receiver and the words. It shares the alert intake's pending and seen marks,
  so one message at one receiver reaches Shutter once by either route (the process passes `session` as the completion key and calls
  `AlertProcess.ForwardAnswered`). `problem` says why a code that needed a forward has none; the process raises it. Nothing waits for an
  acknowledgement that never comes.
- **The demo hospital** (shape A as a judge sees it): the image also creates the namespace `HOSPITAL` (`src/Shutter/Installer.cls`;
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

### 11.1 Onboarding a namespace (v1.42)

`Shutter.Util.Onboard`, through `Shutter.Setup`, in Shutter's namespace. Reads and answers JSON; the steps for a person are
`docs/INSTALL.md`, section 9.

- `SELECT Shutter.Setup_OnboardPlan(namespace, options)` changes nothing: `{namespace, production, production_state, productions,
  services, routers, operations: [{name, class, reported_as, alert_on_error, get_reply, reply_code_actions, reply_code_actions_from,
  proves, in_profile, has_api, draft}], other_operations,
  schemas: [{category, named_by, in_namespace, standard, in_shutter, shutter_name, action}], wired, receiver_prefix, actions: [{do,
  says, ...}], todo, warnings, error}`. `do` is `map_package`, `import_schema`, `add_forwarder`, `rename_alert`,
  `add_alert_intake`, `set_alert_receivers`, `set_alert_on_error`, `draft_receiver`, `set_document_receivers` or `enable_documents`. Options: `production`, `shutter_host`,
  `shutter_port`, `ssl_config`, `credential`, `receivers`, `alert_on_error`, `document_receivers` (item names, comma-separated: both switches of 11.2; a name that isn't a chosen receiver is a warning; taking the namespace off turns off what it turned on). Options that are not a JSON object answer `{ok: false, error}` in
  the plan, the apply and the removal, and change nothing. A `receivers` name that matches no item is a warning; with no item chosen the plan warns and
  has no `add_alert_intake`, since an empty `Receivers` means any item. Reading a namespace (`Onboard.Read`) calls only Ens, %SQL,
  %Dictionary and %SYS classes while it is there, as `ProductionReader` does, since no Shutter class resolves there yet.
- **What a completed message proves** (v1.43). Per operation, the values that apply, the item's, else the default settings', else the
  class's: `get_reply` (the adapter's `GetReply`; null when the adapter has no such setting), `reply_code_actions`, and
  `reply_code_actions_from` (`item`, `default_settings`, `class`, or `engine_default` when all of those are empty, which the engine reads as
  `:?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C`). `proves` is one plain line from them (`Onboard.CompletedProves`, with the review's
  `ReplyAction`). A class's own `OnGetReplyAction` is not read. `tests/e2e/onboard_check.py` measures the lines against a listener;
  `docs/INSTALL.md` 9.9 has the table.
- `SELECT Shutter.Setup_OnboardApply(namespace, options)` (`%Admin_Manage`) runs that plan's `actions` and no others: `{ok, changed,
  unchanged, todo, warnings, error}`; a second run changes nothing. It never stops a production: `Ens.Director.UpdateProduction(30, 0)`
  on a running one. What it did is kept under `^Shutter.Config("onboard", namespace)` (the production at the root; `mappings`, `schemas`,
  `items`, `renamed`, `alertOnError`, `receivers`, `drafted`, `credential`).
- A draft receiver's entry: `{name, system, tier: 3, features: all false, draft: true, namespace, item}` and no `api`, so 6.4's rule for a
  receiver with no API holds and the gate blocks any write. Validation ignores `draft`, `namespace` and `item`; a person removes `draft`
  on saving. Its name is the item's, or `ReceiverPrefix` and the item's when another namespace holds the name or the profile has that name with an `api` and no `namespace`, which the plan warns of (`Onboard.TakenElsewhere`). The prefix is settled when the
  forwarder is added: a wired namespace keeps its names, and the plan warns when an operation added later takes a name another reports.
- `Do ##class(Shutter.Setup).OnboardCredential(namespace, user, password, credential)` makes the user with `Shutter_Forwarder` when it does
  not exist (one that exists must sign in with that password and hold the role), stores the credential in that namespace, and prints no password; with no
  password it asks with the echo off. Not an SQL procedure.
- `SELECT Shutter.Setup_OnboardTest(namespace)` posts, with the forwarder's settings and credential, an ORU^R01 with MSH-11 `T` and no
  patient, `failure.reason_code` `onboarding_test` (`Process.Intake` keeps its text as it came), receiver and route `Onboarding test`,
  and answers `{ok, case, http_status, advice, error}`. An ORU's key is `UNMAPPED^<header>`, so the gate blocks `UNMAPPABLE` and no model runs.
- `SELECT Shutter.Setup_OnboardRemove(namespace, options)` (`%Admin_Manage`) undoes the record: `{ok, removed, kept, error}`. Options:
  `unmap` (take the mappings although messages of Shutter's classes are left in that namespace; otherwise they stay, recorded under
  `^Shutter.Config("onboardKept", namespace)`, and a later call takes them) and `credential` (v1.44: the credential the credential step stored
  there, recorded under `^Shutter.Config("onboardMade")` so a removal without it and a later apply do not lose the record; the user only when the
  step made it and no other namespace onboarded here signs in with it, else `kept` says why; a namespace already off may be called for this alone).
- `SELECT Shutter.Setup_OnboardReceiverItem(name, host, port, credential, ssl)` (`%Admin_Manage`) adds a `Shutter.Operation.Ward` item of the
  receiver's name to Shutter's production for a receiver the profile gives an `api`, records it under `^Shutter.Config("receiverItems")`, and
  a site install puts it back after compiling the production (`RestoreReceiverItems`). Refused for a receiver with no `api`, and, naming both, for an item that exists with other settings.
- **Schemas.** `Schemas.ImportNeeded(namespace, category, .as)` answers `none` (one digest of IRIS's export, or its alias is loaded),
  `import`, or `import_as` with `<NAMESPACE>_<CATEGORY>`; `ImportFrom` exports there and imports here, recording an alias under
  `^Shutter.Config("schemaAlias", namespace, category)`, which `Process.Intake` follows (`LocalName`), so a forwarder keeps naming its own
  category and a held case's `heldSchema` keeps the source's name.
- **A category not loaded when the forward comes** (v1.42; it read as 2.5.1 with no sign of the category, `schema_known` true): the stored copy stays
  typed 2.5.1 for its identity, and notes the named category in the message's `UserValues` (`Schemas.NamedUnloaded`). The evidence
  reports `schema_category` that name and `schema_known` false, so the gate blocks `SCHEMA_UNKNOWN`; once it is loaded, a reinvestigation
  types the copy under it in memory and validates. The category is listed in the Doctor's `missing` from
  `^Shutter.Config("schemaNamed", category)` until an import clears it. A held forward (kind `unreadable`) keeps its own path above.
- **The Doctor** adds `watched_namespaces` (each namespace onboarded or named by a case, read there: `{namespace, onboarded, exists, production,
  production_state, forwarder, alert_intake, pass_to, classes, credential, last_forward, last_forward_error, refused_72h, last_refused,
  last_case, last_case_at, schemas_missing, operations_unwatched, documents_mismatch, removed, problems, ok}`; `documents_mismatch` says, also among the `problems`, each item the forwarder's `DocumentReceivers` names whose profile has `documents.enabled` off, and each the other way round (11.2); `problems` names an alert intake or forwarder that is disabled wherever it is, and for a namespace onboarded here an item named `Ens.Alert` that is missing or of another class, so `ok` is false then; `failure_timeout` in the plan's reading is the effective value: the item's, the default settings', else the class's; a namespace taken off is recorded under `^Shutter.Config("onboardRemoved", namespace)` and reads `removed` with no problems) and `receivers_without_item`; `credentials` tries each onboarded namespace's forwarder credential and each
  connector item's; `hl7_schemas.needed` adds the watched namespaces' missing categories. `AlertProcess.Classify` reads a TCP connect
  timeout (`ErrOutConnectExpired`) as `delivery_failed`: nothing was sent.

### 11.2 Document exceptions

A failed MDM T01 to T11, or a failed ORU carrying a report as an attachment, at a receiver with a document profile becomes the ordinary case with its no-recovery path and a document block. Nothing is resent, no catalogue entry matches it, no agent is convened, and no copy of the message is kept in Shutter. A receiver with no profile behaves exactly as before. The HL7 version pinned is v2.5.1, chapters 7 and 9.

**Switching it on takes both ends.** The receiver's entry in the site profile (6.4) gets `documents`, and the forwarder's `DocumentReceivers` setting names the item. The onboarding option `document_receivers` sets both, and the Doctor's `documents_mismatch` lists where they disagree (section 11.1). The forwarder reads the delivery there and posts metadata only. With the forwarder not naming it, a whole message posted for such a receiver is read by the route and its text dropped; one over 2 MB is still refused 413. With the profile off, the route answers an envelope `409 documents_off` and the forwarder sends the message the ordinary way.

**`documents` in a receiver's entry.** Every key is named, so a misspelt switch is refused.

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `false` | The switch |
| `recovery` | `"none"` | The only value this version accepts |
| `source_namespaces`, `supported_versions` | `[]` | For a later sender. Nothing reads them yet |
| `ack_level` | `"connection"` | `connection` or `application`. For a later sender |
| `owner_accepts_acknowledged_recovery` | `false` | For a later sender |
| `duplicates` | `"unknown"` | `unknown`, `rejects_exact`, `rejects_number`, `replaces` or `files_again`: what the receiver's owner declares |
| `allowed_completion`, `allowed_confidentiality`, `allowed_availability` | `[]` | An empty list allows nothing. For a later sender |
| `missing_status_policy` | `"stop"` | The only value |
| `max_recovery_bytes`, `approval_minutes` | `0`, `15` | For a later sender |
| `email_details` | `"minimal"` | `minimal`, or `identifiers` to add the hospital number and the document number to the email of a document that isn't restricted |
| `readback` | `"disabled"` | The only value |
| `chain_read_limit` | `5000` | Messages to the receiver read for a chain |
| `report_structures` | `["ORU^R01"]` | The ORU message types (MSH-9) that count as reports here. `[]`: none, so this receiver's ORUs take the ordinary path |

**`POST /intake` with `kind: "document_failure"`** (`Shutter_Intake`): `source` (`namespace`, `production`, `route`, `header_id`, `item`), `receiver`, `failure` as in section 11, `delivery`, `facts` and `chain`, with no text of the message. 202 `{caseId, state, opened}`; 400 `bad_request` naming the field; 409 `documents_off`.

**What is read, by position, from the delivery body:** MSH-3 to -7, -9, -10, -12; every PID-3 repetition; PV1-19; TXA-12, -13, -17, -18, -19. Read from the header of the session's request to the receiver's item, not the session's first message, so a transformation on the route shows what the operation was given. The walk stops at TXA, so no OBX, NTE, name, title, file name or type is read for the fields. The size comes from the engine's own chunk count, and the two digests from a sink the engine writes into one stored piece at a time (at most about 3.6 MB), which keeps nothing.

**The operation key** is `mdm-v1:` and a hash of the receiver, the source namespace, the delivery header, TXA-12, TXA-13, the trigger, the patient binding and the body's digest. It binds one stored delivery. It carries no identifier and is not a document version: a new transmission under a new header is a new case. A missing TXA-12 leaves the identity empty, and nothing stands in for it. The standard lets a sender put a file name in TXA-16 when it has no number; Shutter doesn't use it.

**`GET /cases/{id}` adds `document`,** by the reader's right: `headline`, `trigger`, `document` (`id`, `parent`, `completion`, `confidentiality`, `availability`), `patient.keys`, `size`, `delivery`, `refusal`, `reasons`, `chain`, `sent_nothing`, `body_stored_in_shutter` and `source_verified`. The receiver's own words (`refusal.text`) and a restricted document's identity need `Shutter_Approve`. Without it the answer has `refusal.text_withheld` and, for a restricted document, `identity_withheld`, with the identity gone.

**Restricted** means TXA-18 is V, R or a value the standard doesn't list, on the message or any message of its chain. The case's own columns then carry no patient, and the snapshot and email carry no identity. An absent TXA-18 isn't restricted, since the field is optional, and it does stop a sender.

**The chain** is read live from the source's message store: the requests to the receiver's item, newest first, up to the limit, by the forwarder when it forwards and again by the evidence where this instance has that namespace. There is no index, so no lag. `chain.complete` is false, and the case says why, when the limit is reached, a body can't be read, there are over 50 linked messages, the document has no number, or the namespace isn't here. A complete read still covers only what was read, back to its `since`, on that item. A whole text posted by a forwarder not naming the receiver has digests of that text: its session's delivery under the same control id counts as the message itself, and other rows are compared with what that delivery stored. With no such row in the chain, a route's changes read as different content, and the case says the comparison was with the posted text.

**The reason table.** No catalogue entry; deterministic, from the block.

| Code | Shown | When |
| --- | --- | --- |
| `DOC_ID_MISSING` | yes | No usable TXA-12 |
| `DOC_RESTRICTED` | yes | As above |
| `DOC_CHAIN_INCOMPLETE` | yes | `chain.complete` false |
| `DOC_CANCELLED` | yes | A T11 names it, or TXA-19 is CA |
| `DOC_REPLACED_OR_EDITED` | yes | A T07 or T08 on it, a T09 or T10 naming it as parent, or TXA-19 OB |
| `DOC_VERSION_CONFLICT` | yes | Its number or control id on other content |
| `DOC_PARENT_UNPROVEN` | yes | A T05, T06, T09 or T10: the parent is absent, or only known to be in the source's store |
| `DOC_PATIENT_CHANGED` | yes | Its number on other patient identifiers |
| `DOC_STATUS_UNPROVEN` | yes | TXA-17 missing, a status outside the standard's tables, or TXA-18 and -19 both absent |
| `DOC_ENGINE_OWNS_DELIVERY` | yes | The header is Created, Queued, Delivered or Deferred |
| `DOC_DELIVERY_UNCERTAIN` | yes | An uncertain outcome |
| `DOC_BODY_UNAVAILABLE` | yes | The source no longer holds the message |
| `DOC_DUPLICATE_UNDECLARED`, `DOC_RECOVERY_OFF`, `DOC_NOT_ORIGINAL_T02` | no | A sender's check only |

**`Shutter.Util.DocumentEligibility.Check(block, settings, delivery)`** is the one question a later sender must ask, before every send. It answers a code. With `recovery` `none`, it answers `DOC_RECOVERY_OFF`; with no `delivery` object from an engine reader, `DOC_DELIVERY_UNCERTAIN`. Only with every check passing does it answer the code that lets a sender go on, which appears on no screen, email or API answer. Merges and identifier changes aren't read here: the sender's `delivery` must say they were checked and clear.

**A report carried as an attachment.** An ORU counts when any OBX says ED or RP in OBX-2. The value type decides, and nothing clinical is read. An ORU with only numbers or text, or with no OBX, takes the ordinary path, unchanged, at any receiver; so does base64 sent under TX or ST, which reads as text.

- **What is read:** MSH as above; OBR-2, OBR-3 and OBR-25; every PID-3 repetition and PV1-19 before the first attachment; and each OBX's first 64 characters, for OBX-2 alone, held for no longer than the check. Each stored segment is read directly from where the engine keeps it, so a value of any size isn't materialised. The block gets `kind: "report"` and `report` (`placer`, `filler`, `result_status`, `attachment`, `orders`), with `document.id` the OBR-3, else the OBR-2. No OBX-3, OBX-5, NTE, name or title reaches it. An ORU has no confidentiality field, so it has no restricted view.
- **Several orders in one message:** the identity is the OBR before the first attachment, and the chain's words say how many orders the message has.
- **The operation key** is `oru-v1:` and a hash of the same fields, with OBR-2 in TXA-13's place.
- **The one chain rule:** the ORU messages to the same item that name its OBR-3 or its OBR-2, in any OBR and with or without an attachment, are read as above. One with another OBR-25, a missing one included, adds `DOC_RESULT_STATUS_CHANGED` and a sentence naming both statuses in table 0123's words. It doesn't say which message stands, and it reads nothing of the results. No MDM rule applies: the version, patient, status and parent codes are never raised for a report.
- **The reasons shown** are `DOC_ID_MISSING` (no OBR-2 or OBR-3), `DOC_CHAIN_INCOMPLETE`, `DOC_RESULT_STATUS_CHANGED`, `DOC_ENGINE_OWNS_DELIVERY`, `DOC_DELIVERY_UNCERTAIN` and `DOC_BODY_UNAVAILABLE`.
- **A profile not taking the type** answers an envelope `409 documents_off`, as a profile that's off does, and the forwarder sends the message the ordinary way.

**Where the document stays:** in the source's message store, under its retention. A receiver's words and a restricted identity are in `Case.DocumentJSON`, which goes with the case's own purge. The snapshot, the events, the email and the model's view hold neither.

### 11.3 The Settings screen for watched namespaces

`Shutter.API.Onboarding`, routes of the REST API that call the same helpers as 11.1 and leave what they do unchanged. All need `Shutter_Configure`; each POST needs
`X-Requested-With`. The forwarder's password never comes through these routes: `OnboardCredential` stays a terminal command.

- `GET /settings/namespaces` -> `{shutterNamespace, canApply, watched, available}`. `watched` is the Doctor's `watched_namespaces`; `available` is `[{namespace}]`,
  those with Interoperability enabled, not watched, and neither Shutter's own nor the instance's; `canApply` is whether this user holds `%Admin_Manage`.
- `POST /settings/namespaces/{ns}/plan` `{options}` -> `{plan, digest}`, and changes nothing. `plan` is 11.1's. `digest` is a SHA-256 of the plan's production, `actions`,
  `warnings` and `todo` and of the options it was read with. 400 `bad_request` for a body that is not a JSON object, options that are not one, an option 11.1 does not list, or
  one that is not a plain value, so a slip never runs on the defaults. A namespace that can't be planned answers 200 with `plan.error`.
- `POST /settings/namespaces/{ns}/apply` `{options, digest}` (`%Admin_Manage`) -> 11.1's apply answer. 400 `bad_request` with no digest. 409 `plan_changed`, with the fresh
  `{plan, digest}` and nothing changed, when the digest is not the plan's now. The check runs just before the apply and is not one transaction with it; the apply runs that namespace's plan as 11.1 says.
- `POST /settings/namespaces/{ns}/test` -> 11.1's test answer.
- `GET /settings/namespaces/{ns}/removal` -> `{namespace, onboarded, production, renamed, items, alertOnError, mappings, drafted}`, read from the record the apply kept, changing
  nothing. A mapping or a draft listed may still stay; the removal's `kept` then says why.
- `POST /settings/namespaces/{ns}/remove` `{unmap, credential}` (`%Admin_Manage`) -> 11.1's removal answer. 400 `bad_request` for any other key.

`tests/e2e/onboard_api_check.py` plays these on real productions, and `--record` writes the answers the trial replays (`web/src/mocks/onboarding.json`).

## 12. The install (v1.15)

**A namespace running another production refuses the install** (v1.42): with no `production` named, `InstallStatus` fails at
once with `Setup.LiveNamespaceProblem`'s words when a production other than `Shutter.Production` is running there, since
`StartProduction` would stop it. **On a site install a receiver the profile does not name has no API** (v1.42):
`SiteProfile.ReceiverPath` answers empty and `ReceiverFeatures` all false (6.4), where a demo still falls back to its own receiver's
paths.

**A demo load on a plain instance** (a person's `zpm`, with no image build before it): `Shutter.Setup.InstallStatus` makes
`RECORDS` and `HOSPITAL` when they are missing (`Installer.EnsureDemoNamespaces`, before the roles read them) and installs
the hospital once Shutter's production has started (`InstallDemoHospital`; an image build leaves that to `iris.script`).
Every call to `Ens.Director` there runs outside IPM's transaction (`LeaveTransaction`): a lock released inside a transaction
stays held until the commit, and the production's start would wait 30 seconds for it and fail. The level is restored for
IPM's own commit. `scripts/stock-install-check.sh` runs this path.

**The demo records system** (v1.25): `Shutter.Installer`'s manifest makes a third namespace, `RECORDS`, with the demo
receiver package (`Downstream`) mapped from Shutter's code database and its own data database, so the same code serves
two systems from two namespaces; `Shutter.Installer.RunRecords('SHUTTER')` makes it alone on an instance that has Shutter
(CI, a development instance; run again it only renews what follows). `Shutter.Setup.InstallRecords` makes the web
application `/records/api` (dispatch class `Downstream.API`, resource `Downstream_API`) on that namespace, sets its demo
flag, and refreshes the roles: the production's client of the receivers' APIs (`Shutter_DownstreamClient`) takes the
records namespace's data read-write and its code read. The production's "ADT to Records" and "Records Out" items are
demo items, switched off on a site install with the others.

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
  process that runs it (the Dockerfile passes them as build arguments from `.env`, and the demo password as a BuildKit
  secret since v1.38, so the build log and the image's history never carry it; a `zpm load` by hand reads the shell's). The task is made once: an existing instance changes it in the Task Manager. The Doctor reports
  `purge_task` and `message_days`.
- **The start sweep.** `Shutter.Production.OnStart` calls `Shutter.Store.Case.MarkOpenAtStart()`: every case not in a closed state gets one `error`-kind event by `system` (ref `start:<time>`): "The production started at <UTC> while this case was <state>. Work in flight resumes when the production was stopped cleanly; if the case does not move on within N minutes, an approver can abandon it (POST /cases/<id>/abandon, or "Abandon the case" on the case page)". It never closes a case: a clean stop and start keeps queued requests and reloads suspended alarms, so the work resumes and the note is the audit trail of the restart. When the count is above 0 the event log carries an info entry with it. Only `Shutter.Production` runs the sweep: a site's own production filled by `InstallInto` (shape B) gets none, and `POST /cases/{id}/abandon` still works there. The Doctor and `GET /health` (for `Shutter_Operate` callers) carry `working_cases`, the count of cases not in a closed state, and `abandon_after_minutes`, `python_zoneinfo` (v1.30), N as read.
- **Escalation retention** (v1.21). The retention task is always made, with `EscalationDays` from
  `SHUTTER_ESCALATION_DAYS` (else the message days, else 90; `0` keeps the texts; the Dockerfile passes it as a build
  argument from `.env`); an existing task keeps its settings and runs the class default, 90, until changed in the Task
  Manager. `Shutter.Setup.EnsureRetentionTasks(ns, days, purge, escalationDays)` returns `retention created (escalation
  texts N days|kept)` or `retention exists`. The Doctor reports `escalation_days`. The demo's `PurgeStore` removes the
  `.eml` files of the rows it drops, never the folder. Since v1.22 it also empties the production review's two stores,
  `Shutter.Store.Review` and `Shutter.Store.ReviewAnnotation` (13.4), and the review counter goes with the other counters
  it clears, so the next review is `PR-000001` again. Since v1.39 it also empties `Shutter.Store.Precedent` and `Shutter.Store.BoardLead`,
  since the case counter starts again at `C-000001` and their rows would name cases that never existed; since v1.1.0 the three outage stores too (17.7); and it sets
  `^Shutter.Config("resetAt")` to the time of the purge, as a scenario reset does, so nothing from before it is read as
  this instance's history.
- **The aihub module's install** (v1.21) fails when the environment carries a provider key (`ANTHROPIC_API_KEY`, or
  since v1.61 `OPENAI_API_KEY`) and the provider could not be configured from it, so a live edition is never built on a
  key that does not work; the image build has no key and is unaffected.
- **The provider the install configures** (v1.61): Anthropic or OpenAI, one at a time, as the one configuration
  `AI.LLM.Shutter`. `Shutter.Setup.ProviderChoice` decides from `SHUTTER_PROVIDER` and the two keys: the provider named
  (`anthropic` or `openai`) when its key is set; with none named, the one whose key is set, Anthropic when both are. A
  provider named with its key empty, or a name that is neither, configures nothing while a key is set, and the other
  provider's key is never used in its place: the install fails as above, and the production's start logs a warning and
  leaves the instance as it was. `ConfigureProvider(key, model, provider)` writes the wallet secret (`Shutter.Anthropic`,
  or `Shutter.OpenAI`), then `AI.LLM.Shutter` with `model_provider`, the model (`SHUTTER_MODEL`, else
  `claude-opus-5-5`, or `gpt-4.1` on OpenAI) and the key by reference, removes the other provider's secret and records
  the provider in `^Shutter.Config("aihub", "modelProvider")`; a record without it is Anthropic's. It refuses, before
  changing anything, a provider it does not configure and a model whose name is plainly the other provider's
  (one beginning with the family of the other provider's default model, `claude-opus-5-5` on OpenAI, `gpt-4.1` on Anthropic). The two-argument call is Anthropic's, as it was. `ClearProvider`
  removes the configuration, both secrets and the record. The price list (`Shutter.Store.ModelPrice`) holds Anthropic's
  models only, so a run on another model has no cost and the budgets (9) do not limit what it spends; since 1.4.7 the status
  line says so for a model with no price row (`Setup.UnpricedNote`: `; unpriced: ...`, after the model).
- **Shape B: Shutter's items inside a site's own production.** `Shutter.Setup.InstallInto(production, root)`
  (`SELECT Shutter.Setup_InstallInto('Your.Production', '/path/to/module/')`, or `zpm "load <dir> -Ddemo=0
  -Dproduction=Your.Production"`), in that production's namespace with the core classes loaded: refuses an empty name or a
  production that does not exist, records it in `^Shutter.Config("production")`, runs the namespace-level parts of a
  non-demo install (no message purge), and adds to the production, when it has none of that name, each of Shutter's
  items as `Shutter.Production` defines it (`Setup.INSTALLITEMS`: HL7 Index, Case Releaser, Receiver Watch (17), Escalation Mail, Case Workflow, Case Review (13), Failure Census (19), Incident
  Workflow, Evidence Collector, the agent items when their class is compiled, Gate, Shutter Approvers, Shutter API,
  Verifier, Case Intake, Case Intake Store; never the feed or the demo items), writes the default settings keyed to it
  (the receiver's address on Evidence Collector and Verifier, no wildcard row) and, when it is running, updates it in
  place; it never stops a production and never sets the auto-start production. The health route and the Doctor then
  name that production (`shutter_production`), and `StartProduction` leaves a shape-B namespace alone. Run again after
  an upgrade, it adds the items that are new.


**Custom HL7 schemas** (v1.32). `Shutter.Util.Schemas` knows the categories this namespace holds (the class query
`EnsLib.HL7.Schema:TypeCategories`), the categories the productions' items name in `MessageSchemaCategory` and the newest
messages in the store carry in `DocType`, and imports a site's schema XML through IRIS's own importer
(`EnsLib.HL7.SchemaXML.Import`). The Doctor reports `hl7_schemas: {loaded: [{category, standard, base}], needed: [{category,
where, known}], missing: [category], fix}`; `SELECT Shutter.Setup_ImportSchema('<path>')` (Shutter_Approve) imports a file
on the server and answers `{ok, category, loaded, error}`; `GET /settings/schemas` answers the Doctor's object and
`POST /settings/schemas` `{path}` imports (200 `{ok, category, loaded, importedBy}`; 400 `bad_request` without a path; 422
`import_failed` with the importer's words: a file that is not there, not `.xml`, or not a schema). The install guide's
section 7 says how a site loads its schema and what a case says meanwhile (6.5, `SCHEMA_UNKNOWN`).

**The edition decides itself** (v1.35). The image build's `WITH_AIHUB` argument defaults to `auto`: `iris.script` loads the
full package (the root module, the core and the live agents) when the base image has the `%AI` package and the core module
alone (`core/module.xml`) when it does not (the replay edition), saying which; `1` requires AI Hub and fails the build on an
image without it, `0` loads the core alone. The Doctor reports `edition`: `aihub`, `core`, or
`broken: ...` when the package and the module disagree, which an install should never leave.

**What was last observed** (v1.35). The Doctor and `GET /health` (its anonymous answer too) carry `last_live_run`: the newest run
that reached a model (`live` or `record`, never the API mimic) as `{at, status, member, model, mode}`, or null when none
has, so a capped or failing afternoon shows as such beside the configured mode. The image's compose file has a healthcheck
on the health route's `"ok": true` (the production running; `wget`, since the image has no `curl`), so `docker compose ps`
says healthy and `docker compose up --wait` returns when Shutter is ready.

**What each receiver last answered** (v1.50). `ok` stays the production's, since the healthcheck above must not turn on another system's
health. The Doctor adds `receivers`: for each receiver in the site profile `{name, has_api, state, at, http_status, from, error,
last_answer_at, last_failure_at, failures_hour, incident}`, from the connector's newest `Shutter.Msg.WardResult` that made a call
and the evidence's newest `ward_state` items (`from`: `connector` or `evidence`; the status alone, never the body), with no probe. `state` is
`no_answer`, `server_error` (5xx), `refused` (401 or 403), `failing` (a delivery failed after its newest answer, or in the last hour when
nothing has read it), `answering`, `not_read` or `no_api`. `receivers_ok` is false when any is in the first four, true when none is
and one answered, and null when nothing is known; `receivers_state` is `read` or the reading's error; `watched_ok` is false when a
watched namespace's `ok` is. `GET /health` carries `receivers_ok` and `watched_ok` in its anonymous answer too, and no receiver's name. Its anonymous answer also carries `live` with only `enabled` and `every_minutes` (the live hospital's switch and its cadence), so the sign-in page can say what stands behind it; nothing else of the player. Since 1.4.2, when the caller may not read the hospital's database (the hardened demo's UnknownUser holds no roles), they come from the public copy in Shutter's own namespace (4.4), which counts as unknown once older than three of the player's periods (`every_minutes`, else 7), and with neither the hospital nor a current copy the answer has no `live` key.
The Health page keeps Ready out of its hero while either is false ("Needs a look", naming the first two and counting the rest, all of them in its Other group), and adds nothing to its first
layer otherwise.

**Before an install** (v1.50). `Shutter.Util.SiteCheck.Report(namespaces)` (and `Print`, in lines) reads an instance with no Shutter on it,
with only itself and `Shutter.Util.Onboard` loaded, and changes nothing: `{verdict, says, instance, checks, namespaces: [{namespace,
production, production_state, checks, operations, verdict}], not_checked}`; `verdict` is `blocked`, `changes_needed` or `works`, a check is
`{id, result, says, guide}` with `result` `pass`, `warn`, `fail` or `info`. INSTALL, "Before you install".

**The environment at a start** (v1.34). `Shutter.Production`'s `OnStart` calls `Shutter.Setup.ApplyEnvironment(120)`, which
reads the container's `SHUTTER_DAILY_BUDGET_USD`, `SHUTTER_JUDGE_BUDGET_USD`, `SHUTTER_PUBLIC_DEMO_PASSWORD`,
`SHUTTER_TRACE_PASSWORD`, `SHUTTER_JUDGE_PASSWORD` and `SHUTTER_LIVE` and applies each that is not empty: the budget's cap and
share (9), the three public logins made or brought back to their definition and the demo's and judge's Workflow membership (5),
the live profile policy (4.4) and the hospital's switch (`Hospital.Setup.SetLive`, at once when its production runs, else from a
background job that waits up to the seconds given). An empty variable leaves the setting as it is, so an approver's later change
survives a restart that does not name it. The install reads the same variables (its own semantics: an empty budget means no
cap), so the image's build arguments stay the two the installer alone reads, with the demo password as a build secret
(INSTALL.md section 3). The call returns JSON
naming what was applied, with `errors` when a step failed, and the event log carries it; `SELECT Shutter.Setup_ApplyEnvironment()`
runs it by hand. `ApplyRuntime(...)` is the same on given values, for the tests. At every start (v1.39) the production checks that the wallet secret and the Config Store entry still exist, not only the key's digest, and writes them again from the environment's key (`ANTHROPIC_API_KEY`, or `OPENAI_API_KEY`) when either is missing, and since v1.61 when the environment asks for the other provider than the record's (`Shutter.Setup.ProviderNeedsRewrite`; a container recreated on the same volume loses both, since they live in IRISSYS while the record lives in the volume); the Doctor reports `provider`, `wallet_secret` (the recorded provider's own secret) and `provider_config`, each true, false or null where the edition has no such class or this process may not read it: the wallet answers a reader without `Shutter_Secrets` as if the secret were gone and the Config Store refuses one without `%Admin_ConfigStore`, so each probe checks its resource first and a signed-in operator or judge is told nothing rather than "gone" (the v0.2.6 rehearsal); the production's own process, which wrote them, reads them. `SHUTTER_DEMO_PORTAL` is read with them (v1.39): `1` applies `HardenPortal` (14.5's read-only portal) at every start of the production, since that hardening lives in IRISSYS and a recreated container would come back with the portal open, and records the time as `^Shutter.Config("portalHardened")`. The record stands for the latest start alone: it is cleared before each attempt, and a start whose hardening fails leaves no stamp and records its errors as `^Shutter.Config("portalHardeningErrors")`. The Doctor reports `portal_hardened` and `portal_hardened_at` from the stamp and `portal_hardening_errors` from the errors node ("" when the latest start's hardening succeeded or was never asked for). Never from the demo flag alone: a local demo keeps the portal as IRIS made it. Since 1.2.0 `HardenPortal` also sets the `/api/shutter` application's session timeout to `Shutter.Setup.#DEMOAPISESSIONSECONDS`, 120 s in place of IRIS's 900: every signed-in web session holds one licence connection until it ends, and the Community licence refuses every new login, Management Portal and terminal included, once the instance holds 8, which the demo reached at its 8th sign-in. The shorter timeout shortens the lock rather than preventing it: 8 or more sign-ins within 120 s without signing out (the 8th of 10 back-to-back sign-ins, or of 14 visitors 12 s apart, on 8 Nov 2026) still refuse the portal, until 120 s after the last of them; the operator waits that out or restarts the container (troubleshooting.md). A visible tab with the live hospital on, as on the public demo, keeps its session by the live banner's poll (every 30 s at most, on every page). A hidden tab polls nothing, so a tab hidden, or idle on a page that polls nothing, for more than 120 s is signed out: its next request sends it to sign in, and anything not yet sent, such as an approval being written, is lost. A closed tab's session ends 120 s after its last request. `PortalState` reports `api_session_timeout` and is `hardened` only when it is set and no longer than that.

**Prevent failures** (v1.34; decided on 1 Nov 2026: an interface deployed without its schema would read every field from the
wrong place, so Shutter "would actually stop an incident waiting to happen until the schema is imported"). With the site
profile's `feed.prevent_failures` true (6.4; off by default and in the shipped profile, so every scenario plays as before),
`ADT In`'s process checks each message's schema category before mapping it (`Shutter.Util.Schemas.CategoryOf`: the document
type's category the route set; else the receiving item's own `MessageSchemaCategory`, since an item whose category is not
loaded leaves the message untyped; else MSH-12) and, when the category is not loaded here (`Known`), opens a case of kind
`unreadable`, reason `schema_unknown`, with `heldSchema` the category and the headline "Held: the schema X is not loaded here;
import it and set the inbound item's category, and the case is released", and delivers nothing; the message is handled, not
failed, so the feed goes on. The case's identity (patient, encounter, event, key) comes from a reading of the message as
standard 2.5.1 (`Schemas.Canonical`, `OperationKey.FromCanonical`; a message with no 2.5.1 structure gets an `UNMAPPED^` key,
which the gate blocks `UNMAPPABLE`), never saved and never delivered from. The evidence's validation says `schema_known`
false and the Second Parser gives its reading (6.7); the gate blocks with `SCHEMA_UNKNOWN`; the matcher's `delivery` is
`unreadable` (6.1), so no catalogue entry matches and the case escalates with the fix on it; the incident detector does not
count the kind. Release: the Case Releaser's sweep (8.1; every few seconds, beside the delivered waits of 6.5) runs `Schemas.ReleaseHeld`,
which reinvestigates every blocked or escalated `unreadable` case whose `heldSchema` is loaded now where the message was read
(`sourceNamespace`, else here), with the reason "the schema X is loaded in NS now, found by the Case Releaser's sweep" on the case
and its `heldSchema` cleared, so a case is released once (a re-plan the gate blocks for another reason leaves a blocked case,
not a held one, and `held_messages` counts only cases still waiting);
the fresh evidence types the message under its schema (in memory; the stored copy stays as it arrived, untyped by a route
that lacked the schema) and validates it, the matcher still says `delivery: unreadable`, the catalogue's entry for a held
message proposes the resend (until the catalogue has one, the gate's `NEW_PATTERN` sends the case to a person), and the resend
goes through the gate, rehearsal and the site's policy and approvals as any recovered case. `Known` is cached per
process behind `^Shutter.Config("schemaEpoch")`, which an import (`Schemas.Changed`) moves, so the production's jobs see a
schema imported by another process; a schema imported outside Shutter is seen by the release check, which moves the epoch
too. The Doctor reports `prevent_failures` and `held_messages: {count, categories: [{category, namespace, count, oldest}]}`
(the open `unreadable` cases by category), `GET /settings` the same as `preventFailures` and `heldMessages`. A watched
production's refused messages reach the same hold through the forwarder (11). Scenario S25 (a message with a site Z segment,
PARSE_FAILED) is unchanged: it plays with the setting off.

**The FHIR items** (v1.63; the receiver is section 20). The four production items of a FHIR receiver are placed by a call and are not part of `Shutter.Production`: an install whose site never made the call has no FHIR item, no new job, and no change to `Production.cls`, `Setup.INSTALLITEMS` or the Doctor's item check. `Shutter.FHIR.Install` (abstract) does it, on the pattern of `Shutter.Util.Onboard`'s receiver items:

- `PlaceItems(host = "127.0.0.1", port = "", credential = "", ssl = "")` answers `{ok, added, updated, warnings, error}`. An empty port is the instance's own web port (`Shutter.Util.Onboard.WebPort()`). A port that is not a number from 1 to 65535, or one of the four classes not compiled here, ends with `error` and changes nothing. Otherwise it records `^Shutter.Config("fhirItems") = $LISTBUILD(host, port, credential, ssl)`, places the items, and warns (it does not refuse) when no credential is named, the named credential is not in the namespace, the site profile has no entry with a `fhir` object yet, or `Problem` is not empty.
- `RestoreItems(.added, production = "")` does nothing while that record is absent. Otherwise, in `production` (default `Shutter.Setup.ProductionName()`), it adds each missing item (pool size 1, enabled, category `Recovery`) and rewrites the four server settings of `FHIR Receiver` and `FHIR Out` when those are there already on Shutter's class, so a second call cannot leave the two on different servers; a setting with no value is not written. Then it saves the production and its class and, only when that production is the one running, updates it. The install calls it after compiling the production, so a load or an upgrade puts the items back.

| Item | Class | Settings |
| --- | --- | --- |
| `FHIR Receiver` | `Shutter.Operation.FHIRReceiver` | adapter `HTTPServer`, `HTTPPort`, `Credentials`, `SSLConfig`, `ResponseTimeout` 15, `ConnectTimeout` 5; host `FailureTimeout` 0 |
| `FHIR Out` | `Shutter.Operation.FHIRExecute` | the same |
| `FHIR Gate` | `Shutter.Operation.FHIRGate` | none |
| `FHIR Verifier` | `Shutter.Operation.FHIRVerify` | none |

- `Problem(production = "")` answers "" when all four items are in the production, on their classes and enabled, and `FHIR Receiver` and `FHIR Out` have the same `HTTPServer`, `HTTPPort`, `SSLConfig` and `Credentials`. Otherwise it answers sentences joined by full stops: `Missing from <production>: <items>`, `Not on Shutter's class: <items>`, `Disabled: <items>`, `FHIR Receiver and FHIR Out name different servers` (or `No production <name>`). The flow stops a case on it (20.2, stop 1).
- `RemoveItems(production = "")` takes out the items that are on Shutter's class for their names; a site's own item under one of the names stays. From Shutter's own production it also forgets the record, so the next load does not place them again.
- `KillStores()` empties the three stores that hang on a case (`Shutter.Store.FHIRAttempt`, `FHIRSealedRead` and `FHIRBinding`) for the demo's whole-store purge; a receiver's proof (`FHIRProof`) stays. A case's own purge (`Case.PurgeCase`) removes its rows.
- `Doctor()` answers `{"receivers": []}` when the stored profile has no FHIR receiver (6.4: an entry whose `fhir` object passes the save's validation), and otherwise `{policy_version, items_problem, endpoints_agree, receivers: [{receiver, recovery_enabled, proof, proof_measured_at, credential}]}`, from what is stored and with no call to the server. `policy_version` is `Shutter.FHIR.Profile`'s, `items_problem` is `Problem`'s, `endpoints_agree` says whether the two items name the same server, `proof` is `none` (no conformance run on record), `other_software` (the server has since named software other than the one measured) or `matches` (a run is on record; before any case has read the server that is all it says), and `credential` says whether the credential the reader is set to use exists in the namespace. An error reads `{"receivers": [], "error": <text>}`. The Doctor reports it as `fhir`.

A site stores the entry (with `recovery_enabled` false), saves the credential (`Ens.Config.Credentials.SetCredential`), calls `PlaceItems`, runs the conformance run (`tests/conformance/fhir_conformance.py`) against a test instance of the server software and imports its proof document with `Shutter.Store.FHIRProof.ImportFile(receiver, path)`, then sets `recovery_enabled`. The import is refused unless the document is a whole run of this release's kit in which nothing differed and each of the three measurements passed on its own exchange; it is not signed, so whoever imports one vouches that the run took place. The end-to-end check (`tests/e2e/fhir_receiver_check.py`) does the same on the demo. The unit test of `Shutter.FHIR.Install` works on a scratch `Ens.Config.Production` that never runs, since the suite never places an item into the running production; the live placement is proved by the end-to-end check.

**The test FHIR server on a demo install** (v1.63). `FHIRFacade.Installer.Install(ns)` (and `InstallSql(ns)` for scripts that reach IRIS through SQL), called by the install of a demo namespace only and safe to run again, serves the test FHIR R4 server (`FHIRFacade.Service` behind `FHIRFacade.API`) that the demo's FHIR items read and write. It creates what is missing and brings the rest to this definition:

- the resources `FHIRFacade_API` (`READ` to read, `WRITE` to write) and `FHIRFacade_Admin` (`USE` for the demo controls), the names `FHIRFacade.API` checks; the controls' resource is granted to no role, and an administrator holds it through `%All`;
- the role `Shutter_FHIRFacadeClient` with `FHIRFacade_API:RW`, and the user `fhir-client` (comment "Used by the production's HTTP operation") with that role and the one that carries the namespace's databases, `Shutter_DownstreamClient` (`Shutter_Operator` when that role is absent), and the password `SHUTTER_DEMO_PASSWORD` or `shutter`, set on every run so that the credential always matches the user; never `FHIRFacade_Admin`;
- the credential `FHIRFacade` in `ns` for that user;
- the web application `/fhir-facade/r4`: namespace `ns`, enabled, password authentication (`AutheEnabled` 32), dispatch class `FHIRFacade.API`, no resource and no matching roles (the class checks the resources itself and answers a caller without them with an empty 403, as IRIS's own FHIR server does), `UseCookies` 2 and `CookiePath` `/fhir-facade/r4/`; then `^Shutter.Config("webapp", "/fhir-facade/r4") = 1` in `ns`.

The test server also takes controls for a client's tests (v1.63), behind `FHIRFacade_Admin` `USE`, on routes ahead of the catch-all ones in `FHIRFacade.API`:

- `POST /admin/fault`, body `{"modes": [..], "times": 1}` (`Service.SetFault(modes, times = 1)`: a comma list, "" clears; a name that is not a mode, or a `times` that is not a whole number from 1, is refused with 400 and leaves the fault as it was), and `GET /admin/stats` (`Service.Stats()`), both answering `{puts_received, puts_refused, fault, fault_left}`: every PUT of a resource counts as received (the seed's included), one that wrote nothing also as refused, `fault` is the comma list still set and `fault_left` the times it still fires. The state is under `^FHIRFacade.Data("fault")` and `("stats")`, so a reset clears both, and `Store.Reset` takes `Lock +^FHIRFacade.Data:10`.
- The fault modes, each firing once per request on an Encounter PUT that carries a well-formed `If-Match` and a body the server would store, `times` times, and combining: `ignore_if_match` (the version in `If-Match` is not compared, so a stale or unknown one is written; a malformed one is still the 405); `commit_drop_response` (the version is written, and the answer is a 500 with an empty `text/html` body and no ETag, Location or Last-Modified); `second_writer_between_read_and_write` (before the comparison another writer puts the stored current body again, which makes a new version, so the request's ETag is stale and the answer is the 412). No other mode is built.
- `Shutter.Test.FakeFhir` (`tests/unit/Shutter/Test/FakeFhir.cls`) extends `EnsLib.HTTP.OutboundAdapter` and overrides `SendFormDataArray` so that the FHIR operations can be driven in process: it hands the verb, the address less its `Base` property, the request's `If-Match`, `Accept`, `Prefer`, content type and entity body to `FHIRFacade.Service.Handle`, and answers a `%Net.HttpResponse` with the status, the headers and the body as UTF-8 bytes. It logs each request in `Requests(n) = $LISTBUILD(verb, path, ifMatch, body)`, with the request's redirect setting in `Follow(n)`, the bytes its response stream took in `Handed(n)` and that stream's limit in `Bound(n)`; `Canned(verb, path) = $LISTBUILD(status, contentType, etag, location, body)` answers that request instead of the server (a page behind a 200, a plain 404, and with status 0 no answer), and `Slow(verb, path)` delays the body.

**The demo's FHIR receiver** (v1.64; scenario S35). A demo install (`demo` 1, with `FHIRFacade.Kit` compiled) also sets the profile up against its test FHIR server, once the production is compiled and the FHIR items restored: `Shutter.FHIR.Install.Demo(seedPath)` calls `DemoEntry`, which adds the entry of 6.4 as `FHIR Ward Out` to the demo's stored site profile as a new version with the same source, only to a profile whose source is the seed's, the demo's or the live hospital's mark on it and never to a person's, and nothing when an entry of that name, or any other entry, has a `fhir` object already (one FHIR receiver per install, so a second run stores no new version). When the stored profile has that entry as a FHIR receiver (6.4), it then places the four FHIR items with the `FHIRFacade` credential (`PlaceItems("127.0.0.1", "", "FHIRFacade", "")`, the instance's own web port) and imports a proof made by `FHIRFacade.Kit.Measure`, with `Shutter.Store.FHIRProof.Import`: an in-process run of the 244 exchanges of the conformance file that target the test server (the file holds 245), `"base": "in-process:FHIRFacade.Service"`, on a server it resets before and after. A site install does none of it. The demo hospital's production gains `FHIR Ward In` and `FHIR Ward Out` (4), and the scenario's reset of the test server and its approvals is in 4.

**The uninstall** (v1.63). `Shutter.Util.Uninstall` also takes what a FHIR receiver's set-up and the test FHIR server leave: the user `fhir-client` and the credential `FHIRFacade` (`USERNAMES`, `CREDENTIALS`), and the resources `FHIRFacade_API` and `FHIRFacade_Admin` (`OwnSecurityName`); the role `Shutter_FHIRFacadeClient` is covered by its `Shutter_` prefix, the web application by the node it records, and the data by the `^FHIRFacade.` global prefix. `OwnItem` asks a new `FHIRItem(name, className)` first, which is true only where `^Shutter.Config("fhirItems")` is set and the item has the name and the class `PlaceItems` gives it; elsewhere an item called `FHIR Out` is the site's. The four items are on Shutter's classes and in no production of Shutter's own, so without that they would be neither taken nor tolerated on a site's own production; `TakeItemsFrom` and the refusal both read `OwnItem`. Proof: `Shutter.Test.Uninstall`, `Shutter.Test.FHIRInstall`.

## 13. The production review (v1.22)

A **review** is one read-only pass over one production: its items' effective settings, its event log's errors and its messages' failures over a window (7 days by default, 1 to 90), tied to the cases Shutter opened for it. It never changes the production; a person applies any change in the Management Portal. The checks are deterministic (13.2), and the report they make stands on its own. One AI Hub agent then **ranks the findings within their severity tiers and explains each** against the case history (13.6), seeing item and setting names, values, counts, header ids, the checks' own words and per-item case aggregates (counts and case ids), never the error example text, note text, operation-key pieces or failure text. The deterministic report stands whole when the agent fails, replays with no recording or is skipped. A finding keeps **severity** (how bad the hazard is) and **confidence** (how the evidence was read) apart, counts unique cases apart from retries, and says "consistent with" unless a mechanism was traced; "intended" is a Shutter **annotation** bound to the finding's exact value (13.3), never a production edit, and the finding reopens when the value changes or the annotation expires or is revoked.

### 13.1 Where it runs, and on what

**On request only.** `POST /production-reviews` (13.5) is the one way a review starts: never at the production's start, never in the Doctor or `GET /health`, never on a timer. The reads are indexed and bounded by the window (the event log at most 50 groups), so a review of the demo's data takes a few seconds.

**The targets.** Shutter's own production (`Shutter.Setup.ProductionName()` in its namespace), the hospital's (`^Shutter.Config("hospitalNamespace")`: its running production, or every production defined there when none runs, the namespace's foundation production excepted) and every namespace and production that has sent Shutter a case (the distinct `SourceNamespace`, `SourceProduction` pairs), without repeats: `Shutter.Review.Sweep.Targets()` gives `[{namespace, production, productionState, own, watched}]`, which `GET /production-reviews/targets` lists. A review runs only on a target (`Sweep.IsTarget`, the namespace compared without regard to case; the route answers 400 otherwise, and the Case Review item checks once more), so a caller's string never becomes a `$NAMESPACE` switch.

**In a production job, not in the REST process.** The route sends `Shutter.Msg.ReviewRequest` (`Namespace`, `Production`, `WindowDays`, `Agent`, `RequestedBy`; v1.39: `Agent` is false for a caller without `Shutter_LiveAgents`, and `RequestedBy` goes on to the agent's run as its requester, so the run counts against that person's share, 9) through the Shutter API service to the item **Case Review** (`Shutter.Process.Review`, category Recovery, beside Case Workflow; in `Setup.INSTALLITEMS`, so a shape-B install adds it). The item refuses a review of a production still sweeping or ranking, opens the review row and answers at once with `Shutter.Msg.ReviewStarted` (`ReviewId`, `State`, `Error`), as the case workflow answers an intake with `CaseStarted`; then, in the production job, which runs as the production's user and can read the watched namespace and `%SYS` where the REST caller cannot, it runs the sweep and stores it. A sweep that throws fails the review with the reason; a namespace that cannot be read gives one finding `NAMESPACE_UNREADABLE` with `unreadable` true, never a 500. When the request asks for the agent and there are findings in a readable namespace, the item asks the agent (13.6) and the review is `ranking` until the answer or the alarm; the review is `done` in every path, and the oldest reviews beyond 50 per production are deleted. The run shows in the Visual Trace like `/close` and `/reinvestigate`: the `ReviewRequest`, the Case Review item, the Agent Board request and the alarm.

**The reader** (`Shutter.Util.ProductionReader`). Only `Shutter.Intake`, `Shutter.Util`, `Shutter.Msg`, `Shutter.Store` and `Hospital` are mapped into the hospital's namespace, so the namespace-local reader lives in `Shutter.Util`, and the checks (`Shutter.Review.*`, not mapped) run back in Shutter's namespace on the data it returns. A review reads a production in its own namespace, never the copy another namespace holds (SHUTTER holds a stale copy of `Hospital.Production`, which says stopped: the hospital's review reads in HOSPITAL). `ProductionReader.Read(namespace, production, windowFrom, .data)` switches namespace inside a Try (`New $NAMESPACE`), checks that the namespace exists first, reads only (the production is opened with concurrency 0, the state comes from the `Production_ProductionStatus()` query, no lock is taken; inside the switched namespace only `Ens`, `%SQL`, `%Dictionary` and `%SYS` classes are called) and returns plain data: the items with the settings their definition sets (`settings: [{name, target, value}]`, the overrides only), the system default settings (`Ens_Config.DefaultSettings` for the production and for `*`), the class defaults (`%Dictionary.CompiledProperty.InitialExpression`, quotes removed) of `FailureTimeout`, `RetryInterval`, `ReplyCodeActions`, `AlertOnError`, `AlertGroups`, `QueueCountAlert`, `QueueWaitAlert`, `InactivityTimeout`, `ArchiveIO`, `Framing`, `NoFailWhileDisconnected`, `ResponseTimeout`, `IPAddress` and `Port` for every item and adapter class present, whether an `Ens.Alert` item exists, the production's state (`running`, `stopped`, `suspended`, `troubled`, or `another production running`), the event log's errors in the window (`Ens_Util.Log` Type 2, at most 50 groups by item, source class, source method and signature, each with its count, latest id, latest time and the latest text clipped to 500), the headers that ended suspended, aborted or in error in the window (`Ens.MessageHeader` Status 5, 7 and 8, by target, source and status), the queues (`Ens.Queue_Enumerate()`), the rule log's errors (`Ens_Rule.Log` with `IsError`, by rule and rule set) and the message purge task (`%SYS.Task`, class `Ens.Util.Tasks.Purge`, for the namespace: present, suspended, days to keep, bodies too, keep integrity, types, last finished). Times are ISO UTC. A namespace or production that cannot be read gives `data.error` and a failed status, never an exception; the purge task is null when `%SYS` could not be read. **The error signature** is the event log text before its first colon, and before a hash that does not start an error number (a process's instance number is cut, an error number such as `#5001` is kept), clipped to 120 characters: the demo's `ERROR <Ens>ErrBPTerminated: Terminating BP ADT to Downstream # due to error: ...` has the signature `ERROR <Ens>ErrBPTerminated`.

### 13.2 The checks

The checks (`Shutter.Review.Sweep.Evaluate`) are a pure function of the reader's data, so the unit tests fabricate a production. Every setting's **effective value** is resolved in three explicit steps and the finding says which answered (`source`): the item's own settings (`item`), the nearest system default setting (`default_setting`: this production's rows before `*`, the item's name before `*`, the host or adapter class before `*`), the host or adapter class's `InitialExpression` (`class_default`); `observed` marks a count or the purge task. A value left at its class default is not a finding by itself. The **feed path** is the operator's own grouping: the items whose `Category` names `Feed`, every item whose class is an `EnsLib.HL7.*` class, and, when no item of the production has a category at all, every item. The HL7 checks run only for items whose class extends `EnsLib.HL7.Operation.Standard` (by a name list, and `%Extends` when the class is compiled here); neither demo production has one, so the page says "no HL7 TCP item in this production" for them, not "no finding".

| Code | Subject | Fires when | Severity | Confidence |
|---|---|---|---|---|
| `RETRY_FOREVER` | an operation or process | effective `FailureTimeout` -1: nothing fails forward | high | confirmed |
| `GIVES_UP_EARLY` | an operation or process with retries | 0 < `FailureTimeout` < 2 x `RetryInterval`: it fails before a second try | medium | confirmed |
| `REPLY_CODES_LENIENT` | an HL7 operation | `ReplyCodeActions` resolves AE or AR to C or W with no S, F or D (an error treated as sent) | high | confirmed |
| `REPLY_CODES_SUSPEND_UNWATCHED` | an HL7 operation | AE or AR resolves to an action with S and `AlertOnError` is 0; an empty `ReplyCodeActions` resolves through the documented default `:?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C`, marked as documented | medium | consistent |
| `FRAMING_MISMATCH` | an HL7 TCP operation | it points at this instance (no `IPAddress`, `localhost`, `127.0.0.1`, `::1`, `0.0.0.0` or the host's name) on the port of an HL7 TCP service here and their `Framing` differ, neither `Flexible` | high | confirmed |
| `NO_ALERT_CONSUMER` | the production | no item of class `Ens.Alert` (or extending it, or named so): `AlertOnError` has nowhere to go | medium | confirmed |
| `ALERTING_OFF` | the production, one finding | feed-path items with `AlertOnError` 0 or no `AlertGroups`, listed in `found` as `name (AlertOnError 0, class default, no AlertGroups); ...`, whether or not an `Ens.Alert` item exists | medium | confirmed |
| `QUEUE_ALERTS_OFF` | the production, one finding | feed-path operations with `QueueCountAlert` 0 and `QueueWaitAlert` 0, listed in `found` | low | confirmed |
| `FEED_SILENCE_UNWATCHED` | a feed-path service with an inbound adapter (not the adapterless kind, not Shutter's own) | `InactivityTimeout` 0: a silent feed is never noticed | low | consistent |
| `ARCHIVE_IO_ON` | any item | `ArchiveIO` 1: raw I/O kept; check retention and disclosure | low | confirmed |
| `POOL_SIZE_REORDERS` | an HL7 operation or a feed-path process | `PoolSize` > 1 on an ordered feed | high | confirmed |
| `ITEM_DISABLED` | a feed-path item | `Enabled` 0 | high | confirmed |
| `PURGE_MISSING`, `PURGE_SUSPENDED` | the namespace, the purge task | no `Ens.Util.Tasks.Purge` task for the namespace; the task suspended | high | confirmed |
| `PURGE_SHORT`, `PURGE_LONG`, `BODIES_KEPT` | the purge task | `NumberOfDaysToKeep` < 7; > 365; `BodiesToo` 0 | medium, low, low | confirmed |
| `SUSPENDED_MESSAGES` | an item (the target) | headers with Status 5 in the window, one finding per target | high | confirmed |
| `QUEUE_BACKLOG` | an item | its queue above `QueueCountAlert`, or above 100 when none is set; high above 1000 | medium, high | confirmed |
| `ERRORS_GROUPED` | an item and an error signature (`found`) | event log errors in the window, with the count, the latest header id and the latest example (clipped, for the API only); `why` adds that the item is no longer in the production, or that the errors are the production's own when they carry no item | medium | indicative |
| `RULE_ERRORS` | a rule (`found` names the rule set) or, when the rule log is empty, a transform class parsed from an error text's stack location (`found` is `from the error text`) | rule log rows with `IsError` in the window | medium | indicative |
| `MESSAGE_ERRORS` | an item (the target; `found` names the source) | headers with Status 8 (`in Error`) or 7 (`aborted`) in the window, with the count and the latest id | medium | indicative |
| `NAMESPACE_UNREADABLE` | the namespace | the read failed (missing, rights); `found` is the error | info | confirmed |

Each finding: `{id, code, severity, confidence, item, itemClass, setting, found, source, suggested, why, action, cases: {count, unique, latest: [caseId...]}, evidence: {count, latestHeaderId, latestLogId, latestRuleLogId, latestAt, example}, status, annotationId, rank, explanation}`; `latestHeaderId` is a message header id and only that (the failed messages, the suspended ones, the error group's latest message when the log names one), `latestLogId` an event log row (an error group, or a transform read from an error text), `latestRuleLogId` a rule log row (`RULE_ERRORS` from the rule log), each `""` when it does not apply (v1.22); `found` is always a string, and `item` is `""` for a finding about the production or the namespace. Severity (`high`, `medium`, `low`, `info`) and confidence (`confirmed`: read from the configuration; `consistent`: the configuration is consistent with the pattern; `indicative`: a count nobody has read yet) are kept apart; the words say "consistent with", never "caused". `evidence.example` (the latest error text) is for the operator's `GET` only and never reaches the agent. The checks' words (`why`, `suggested`, `action`) live in `Shutter.Review.Checks`, one row per code (23 codes), as JSON in an XData.

### 13.3 The sweep: cases, fingerprint, baseline rank, annotations

**Cases.** For Shutter's own production, the cases its own feed opened in the window, by `Receiver` (the connector item); for a watched production, the cases it forwarded, by `SourceRoute` (the item that received the message there): `caseAggregates` is `{"<item>": {count, unique, byFailureKind, byOutcome, byReasonCode, byState, latest: [the newest 5 case ids]}, "_total": {...}}`, with `"(none)"` for cases with no receiver. `unique` counts distinct operation keys (a reopened case is not a second patient). No case text, operation key or failure text leaves the store: counts and case ids only. A finding about an item carries that item's block in `cases`; one about the production carries `_total`. Case ids are operational identifiers, as the board's evidence already carries them (9).

**Fingerprint.** The SHA-256 (lower-case hex) of the sorted lines `code|item|setting|found` of the findings whose confidence is `confirmed` or `consistent`, the volatile codes left out (`ERRORS_GROUPED`, `RULE_ERRORS`, `MESSAGE_ERRORS`, `SUSPENDED_MESSAGES`, `QUEUE_BACKLOG`, `NAMESPACE_UNREADABLE`); `""` when there is none. It moves with a setting value (renaming an item or adding one to the feed moves it) and never with counts, ids or times, so it is the same on every instance that reaches the same configuration: the agent's record key and the annotations bind to it.

**Baseline rank.** Severity tier (`high`, `medium`, `low`, `info`), then unique cases descending, then the evidence's latest time descending, then code and item; ids `F1` onwards in that order. The agent may reorder within a tier only (13.6).

**Annotations.** A finding whose code, item, setting and value fingerprint (the SHA-256 hex of `code|item|setting|found`, `Sweep.ValueFingerprint`) match an unexpired, unrevoked annotation (`Shutter.Store.ReviewAnnotation.StatusFor`, the newest first) carries its status (`intended`, `accepted_risk`, `false_positive`) and `annotationId`; one that no longer matches is `new` again. The match is computed when a review is read, not stored with it (13.4). `summary.intended` counts the findings with a status other than `new`.

**One run** (`Sweep.Run(namespace, production, windowDays, .result)`, 1 to 90 days, 7 by default): `{namespace, production, productionState, window: {days, from, to}, fingerprint, summary: {bySeverity: {high, medium, low, info}, findings, intended, items, hl7Operations, hl7TcpItems, errorsInWindow, messageErrorsInWindow}, findings, caseAggregates, readAt, unreadable}`; `hl7Operations` counts the items that are the reply-code checks' subject (HL7 operations) and `hl7TcpItems` the HL7 TCP operations and services (the framing check's), so a page can say "no HL7 item in this production" rather than "nothing found" when either is 0 (v1.22); `errorsInWindow` sums the `ERRORS_GROUPED` counts, `messageErrorsInWindow` the Status 8 headers. A namespace that cannot be read gives one `NAMESPACE_UNREADABLE` finding, `unreadable` true, `fingerprint` `""` and a good status: the review is still a result. From SQL, for a check on an instance: `SELECT Shutter_Review.Sweep_RunJSON('HOSPITAL', 'Hospital.Production', 7)` and `SELECT Shutter_Review.Sweep_TargetsJSON()`; neither stores anything.

### 13.4 The store

`Shutter.Store.Review`: `ReviewId` (`PR-000001`, six digits from `^Shutter.Counter("review")`), `Namespace`, `Production`, `ProductionState`, `WindowDays`, `WindowFrom`, `WindowTo`, `StartedAt`, `FinishedAt`, `State` (`sweeping`, `ranking`, `done`, `failed`), `Fingerprint`, `FindingsJSON` (the findings in baseline order: the agent's exact input), `SummaryJSON`, `CaseAggregatesJSON`, `Unreadable`, `RequestedBy`, `Error`; the agent's part: `AgentState` (`pending`, `ok`, `no_record`, `skipped`, `schema_failed`, `error`), `Mode`, `Model`, `ProviderConfig`, the four token counts, `CostUSD` (`Shutter.Store.ModelPrice.Cost`; 0 for a replay or a mimic run), `DurationMs`, `RankingJSON` (the accepted ranking, summary and unknowns; empty unless `ok`), `SessionId`, `EnsMessageId`, `RecordKey`, `AgentError`. Why a store: the agent's run needs the exact input it ranked, the ranking and its cost must survive and show, and the page shows the last review; `Shutter.Store.AgentRun` cannot hold a review run (its `Case` is required), so the review row carries the run's own columns and `GET /costs` adds them (13.5). The last 50 per production are kept (`Trim`, after every path). A review still `sweeping` or `ranking` 20 minutes after it started was left behind (a restart in the middle of it, or an answer that never came): it no longer counts as running (`Running`), and the next review of the production fails it with the reason (`CloseStale`) before it opens.

`Shutter.Store.ReviewAnnotation`: `ReviewId` and `FindingId` (where it was made, for the record), `Code`, `Namespace`, `Production`, `Item`, `Setting`, `ValueFingerprint`, `Status` (`intended`, `accepted_risk`, `false_positive`), `Reason`, `Owner`, `ExpiresAt`, `CreatedBy`, `CreatedAt`, `Revoked`, `RevokedAt`, `RevokedBy`. An annotation is a Shutter record, never a production edit. It is matched at read time (13.3), so one annotation applies to every review of the production, past and future, and a revoked or expired annotation, or a changed value, reopens the finding as `new` everywhere. Both stores are emptied by the demo's `PurgeStore` (12).

### 13.5 The API

All routes under `Shutter_Operate` unless said (5); `X-Requested-With: Shutter` and an `Idempotency-Key` on every POST, as today; errors in the shared shape `{error, detail}`.

- `GET /production-reviews/targets` -> `{items: [{namespace, production, productionState, own, watched}]}`: the targets of 13.1.
- `POST /production-reviews` `{namespace?, production?, windowDays? (7; 1 to 90), agent? (true)}` (the namespace defaults to Shutter's own, the production to `Shutter.Setup.ProductionName()`) -> 202 `{reviewId, state: "sweeping", requestedBy, agent}` (v1.39: `agent` is false, and the review ranks by its baseline alone with `agentState` `skipped`, for a caller without `Shutter_LiveAgents` or while the provider refuses the key, never a 403, since the web app sends no `agent` field); 400 `bad_request` for a target not in `/targets`, a window that is not a whole number from 1 to 90, or a body that is not a JSON object; 409 `wrong_state` (with `reviewId` and `state`) while a review of the same production is still `sweeping` or `ranking`; 503 `no_service` when the production is not running, 503 `not_queued` when the item did not take the request, 502 `no_answer` when it did not answer, 500 `review_failed` when no review was opened; `GET /production-reviews/targets` answers 500 `targets_failed` when the targets cannot be listed, and the annotation routes 500 `annotation_failed` when the store cannot be written. The review reads only, and a live agent run spends model credit as a scenario run does, so an operator starts one.
- `GET /production-reviews?namespace=&production=&limit=` (50; 1 to 500) -> `{items: [{reviewId, namespace, production, productionState, startedAt, finishedAt, state, agentState, summary, requestedBy}], total}`, newest first; `total` counts the filter's rows.
- `GET /production-reviews/{id}` -> `{reviewId, namespace, production, productionState, requestedBy, startedAt, finishedAt, state, error, window: {days, from, to}, fingerprint, unreadable, summary: {bySeverity: {high, medium, low, info}, findings, intended, items, hl7Operations, hl7TcpItems, errorsInWindow, messageErrorsInWindow}, findings: [...], caseAggregates, agent: {state, mode, model, providerConfig, costUsd, promptTokens, completionTokens, cacheReadTokens, cacheCreationTokens, durationMs, recordKey, ensMessageId, error, summary, unknowns, explained, unexplained, dropped, recordedEntries}}`; 404 `not_found`. `explained` is how many of the review's findings carry the agent's explanation, `unexplained` how many do not, `dropped` how many of the ranking's entries matched no finding here and `recordedEntries` how many it had (13.6); all four are null until the agent answered. Once it has, every finding carries a `rank`: within each severity tier the explained findings first, in the agent's order, then the unexplained ones in baseline order, the ranks running 1 to n. The findings have 13.2's shape and come in baseline order, `rank` and `explanation` filled when the agent answered (`rank` null and `explanation` `""` otherwise) and `status` and `annotationId` as the annotations stand now; `finishedAt` is null until the review is `done` or `failed`; `error` is the sweep's failure text, `""` otherwise. The agent's values from `mode` to `durationMs` are null until it answered, `recordKey` and `ensMessageId` null until set, `error` `""` or text, `summary` `""` or the agent's, `unknowns` an array. A review still `sweeping` or `ranking` shows what is stored so far (while sweeping, `findings` is `[]` and `summary` `{}`); the page polls while it is (the sweep takes seconds, the agent up to 600 s).
- `POST /production-reviews/{id}/annotations` (`Shutter_Configure`) `{findingId, status, reason, expiresAt?, owner?}` -> 201 `{annotationId, code, item, setting, valueFingerprint, status, reason, owner, expiresAt, createdAt}`; 400 `bad_request` for a status outside the three, no `findingId`, no `reason`, or an `expiresAt` that is not an ISO 8601 UTC date or time (`YYYY-MM-DD`, or `YYYY-MM-DDTHH:MM[:SS]Z`); 404 `not_found` for an unknown review or finding id. `owner` defaults to the signed-in user, who is always `createdBy`; `annotationId` is the row's id, as a string.
- `DELETE /production-reviews/annotations/{annotationId}` (`Shutter_Configure`) -> 204 with no body (revoked, kept for the record; a second DELETE is 204 too); 404 `not_found`.
- `GET /costs` adds `totals.reviewRuns` (the reviews whose agent answered, in any mode) and `byReview: [{reviewId, production, model, mode, costUsd, startedAt}]`, and `totals.spentUsd` now includes what the reviews' live runs spent (a replay or a mimic run spends nothing); `liveRuns`, `replayedRuns`, `mockRuns` and `byModel` stay the board's runs.

### 13.6 The agent

**The request.** When the sweep is stored, the request asked for the agent and there are findings in a readable namespace, the Case Review item sends `Shutter.Bridge.Msg.AgentRequest` to the **Agent Board** item (the item's `AgentTarget`; completion key `review`) and arms an `Ens.AlarmRequest` (`review:timeout`, the item's `AgentTimeoutSeconds`, 600 s). The request: `Role` and `MemberCode` `review`, `AgentClass` `Shutter.Agent.Review`, `TerminalTool` `SubmitReview`, `ResultClass` `Shutter.Schema.Review`, `ConfigVersion` `1`, `CorrelationKey` the review id (the Scope policy keys on it), `SnapshotDigest` the fingerprint, `RecordKey` (below), `TokenBudget` 60000 and `MaxIterations` 4 (the item's settings; `MaxIterations` is new on `AgentRequest`, and `Shutter.Bridge.RunSpec.FromRequest` honours it when above 0, so a review costs less than a board member's run), the goal "Rank the findings of this production review within their severity tiers and explain each in one or two sentences against the case history; call SubmitReview once with the review id.", and the context `{review_id, namespace, production, production_state, window, summary, findings, cases}`: the findings as the sweep wrote them less `evidence.example`, `annotationId`, `rank` and `explanation`, and `cases` the per-item case aggregates of 13.3 (what the agent sees: 9). The agent runs through the existing Agent Board item like any request that names its class: no production or site-install change, its budget on the request.

**The answer.** An `ok` answer's ranking is checked by the process (`Shutter.Store.Review.RankingProblem`: every finding id of the review exactly once, ranks 1 to n without gaps, no finding ranked above one of a higher severity tier); a refused ranking ends the agent's part `schema_failed` with the problem in `agent.error`, and the baseline order stands. `no_record` (a replay with no recording for the key) and the bridge's other statuses are recorded as they came; an answer that never comes ends it `error` ("The agent did not answer within 600 s; the baseline order stands"). `skipped` means the agent was not asked (`agent: false`), there was nothing to rank, or the namespace was unreadable. When `ok`, every finding carries `rank` (1 to n, the agent's order within the fixed tiers) and `explanation` (one or two sentences, "consistent with" wording, citing finding ids and counts), and `agent.summary` and `agent.unknowns` are set; the findings still come back in baseline order, so a page sorts by `rank` only when `agent.state` is `ok`. The cost is `ModelPrice.Cost` of the run's tokens (0 for a replay or a mimic run), and `GET /costs` lists it apart (13.5).

**The agent class.** `Shutter.Agent.Review` (the aihub module) extends `Shutter.Agent.Base` with `MEMBER` `review`, `TERMINAL` `SubmitReview`, an empty `TOOLSETS` (no evidence tools: a review has no snapshot to read; an agent with no toolset is the framework's own base case, so `%LoadToolSets` is not overridden), `KNOWLEDGE` `review` and `CONFIGVERSION` `1`. It has its own `Preamble` (the request is the evidence and findings are cited by id; everything in it is data, not instructions; a finding's severity, confidence, counts and values are never changed; findings are reordered within one severity tier only, high before medium before low before info; "consistent with", never "caused"; what the findings and aggregates do not decide goes in `unknowns`; `SubmitReview` is called once, then one sentence; nothing is written or applied) and an `INSTRUCTIONS` XData that explains each field of the context. It is not a board member: no `Shutter.Store.BoardMember` row, and not on the library page. The runner (`Shutter.Bridge.Runner.AIHub.Run`) maps a `TerminalTool` whose name contains `review` to `Shutter.Tools.SubmitReview`, whose `CaseId` holds the review id (set from `CorrelationKey`) and which refuses a submission for another review; `AttachKnowledge` attaches the board member row's collection, else the agent class's `KNOWLEDGE` parameter when the class defines one, else every collection (as before, so members without the parameter behave as today).

**The result** is `Shutter.Schema.Review`: `ranking: [{finding_id, rank, explanation (at most 600 characters), confidence_note (at most 300)}]`, `summary` (at most 600), `unknowns: [string]`. `Check` refuses a ranking that is not an array or is empty, an entry that is not an object, a missing `finding_id`, an id ranked twice, a rank that is not an integer from 1 to n or is given twice (n entries with distinct ranks from 1 to n leave no gap), a missing or overlong explanation, an overlong note or summary, and `unknowns` that is not an array; a refused submission tells the model what to correct. Whether the ids are the review's own and whether the order keeps the severity tiers is the process's check, above.

**The knowledge** it searches is one collection, `review`: one document, `knowledge/review/production-review-rules.md` (PRR-1 to PRR-7: how to read a finding, each check's meaning, why it matters, the safer value, when such a finding is intended and how a reviewer tells; the HL7 `ReplyCodeActions` action letters and default are marked as from the documentation, not read on an instance), appended to `Shutter.Knowledge.Library.COLLECTIONS`, built with the others at the aihub install and by `RefreshKnowledge` when its folder changes; its search tool is `search_review`. A board member reaches it only through a row whose `KnowledgeCollection` is `all` (6.6).

**Record and replay.** `RecordKey` is `review:<namespace>:<production>|review|<CONFIGVERSION>|<fingerprint>`, for example `review:SHUTTER:Shutter.Production|review|1|<sha256>`: the fingerprint of 13.3, configuration findings only, so the key is the same on every instance that reaches the same configuration and does not move with counts or times (and ends with `|` when a production has no configuration finding). On an instance with no provider the Agent Board item replays: with a recording under that key the explanation is the recorded one (`mode` `replay`, cost 0), and the page says the explanation is recorded and when; with none the agent's part is `no_record` and the page shows the deterministic findings alone. The demo's recordings are made in record mode on the AI Hub instance, on the canonical state after the regression, one per target; the fixture checks (`scripts/check-records.py`, `scripts/evaluate.py`) must accept the review's key form beside the `scenario:` keys, and the file name follows `Record.ExportDir` (`review-SHUTTER-Shutter.Production-review-1-<fingerprint>.json`). The mimic does not answer review runs (4); the review's tests run with `agent: false` or in replay.

**Matching a recorded ranking (v1.22).** The agent's ranking entries carry the finding's `code`, `item` and `setting` beside the `finding_id` (`Shutter.Schema.ReviewRank`; `Check` requires a non-empty `code` and `item` and `setting` present as strings, `""` allowed); the agent's instructions make it copy them from the finding and write explanations without numbers from the findings (no counts, ids, dates or versions: "the count shown", "the cases of this item in the window"), so a recorded explanation reads right on another instance of the same configuration whose counts differ. When the agent answers, live or replayed, `Shutter.Store.Review.MatchRanking` matches each entry, in rank order, to the first unmatched current finding with the same code, item and setting (an entry without them matches by `finding_id`, as before); the matched entries keep their recorded order, re-ranked 1 to m, and are what the review stores; an entry matching nothing is dropped and a finding with no entry stays unexplained. The whole ranking is refused (`schema_failed`, the baseline order stands) when it is not a ranking, names a finding twice, puts a lower tier above a higher one among the matched entries, or matches nothing at all. So the record key covers the configuration findings and the recording made on one instance explains the configuration findings of every instance that reaches the same configuration, and the volatile findings where the same item has the same error groups; the recording is made on an instance with a provider after the scenario set the demo plays, and the page says how many findings the recorded run explains. The agent's explanations name another finding by its code and item, never by its id, for the same reason. A run whose `SubmitReview` was accepted ends `ok` even when its turns ran out before the closing sentence (the runner notes the stop in `error`); the request gives it 4 turns.

## 14. Ask about this case (v1.26, v1.27)

### 14.1 The deterministic card (v1.26)

`GET /cases/{id}/whatif` (Shutter_Operate; 404 `not_found`) answers, with no model and from the case's snapshot and the
site profile alone, what the case's outcome turned on and what it would have done under the catalogue's alternatives
(`Shutter.Util.WhatIf`): `{case_id, receiver, category, entry, outcome, outcome_ref, disposition, profile_version, note,
facts: [...]}`. Each fact is `{id: "W<n>", kind: "alternative" | "policy", role: "setting" | "alternative" | "policy",
flag, field, receiver?, current, from, to, holds_now, would, alternative?: {n, outcome, disposition, when, why}, affects:
[text], suggested_change: {field, receiver?, from, to, why, affects, valid, problem?, stale}}`. For the matched entry, every
alternative whose `when` names a profile flag is a fact: `history_policy` reads the receiver's `receivers[].category` (or
its `history_policy` override), `authoritative_source` the site's with the other source the facts saw, the others the
site's flag; a fact that holds now is the setting behind the outcome (`role: setting`), and its change undoes it;
otherwise the change is what would make the alternative apply and `would` says what the case would have done (the gate's
disposition for the outcome). When the case wrote, the tier's approval policy is a fact one step stricter. A change is
validated by applying it to a copy of the profile and running the validator (`valid`, `problem`), and is `stale` when its
`from` no longer matches the profile. The fields a change may name: `receivers[].category`, `receivers[].history_policy`,
`receivers[].tier`, `receivers[].cancels`, `receivers[].merges`, `authoritative_source`, `unconditional_resend`, `merges`,
`policy.<tier>.<kind>`. Nothing here writes: the page pre-fills a draft on the Site profile page, which an approver saves
under that page's rules. The case chat's agents (the Explain agent and the board's question mode, `case-chat` hand-off)
receive these facts and may name no other setting or change.

### 14.2 Questions (v1.27)

A question about a case is a turn of a conversation, stored as `Shutter.Store.CaseQuestion` (`Q-nnnnnn`): `conversation`
(a suggested conversation's id from the scenario's file, or, for a free question that starts one, the question's own id),
`turn` (1-based within the conversation), `tier` (`explain`: the Explain agent alone, plain words from the evidence; `board`:
every enabled default specialist, then the coordinator's synthesis), `source` (`suggested`: a turn of
`knowledge/questions/<S>.json`, recorded and replayable; `free`: live only), the question's text (1 to 2000 characters),
`state` (`pending`, `answering`, `answered`, `schema_failed` when the core refused the answer, `failed` when none came: the
agent's status, a timeout, an error; a question left `pending` or `answering` for 15 minutes is marked `failed` by the next
list), the what-if facts handed to the agents, the accepted answer with the case's identifiers restored, the members' answers
of a board question, the resolved change (14.4), the record key of the answering run, its mode and model, the question's
runs and their cost, and the Visual Trace link (`ensMessageId`). Nothing a question does writes to the case or to a receiver,
whatever its text says: the agents hold no write tool, and the question's text is data (14.3).

**In a production job.** `POST /cases/{id}/questions` sends `Shutter.Msg.QuestionRequest` (`CaseId`, `Tier`, `Source`,
`Text`, `Conversation`, `Turn`, `AskedBy`) through the Shutter API service to the item **Case Question**
(`Shutter.Process.Question`, category Recovery, beside Case Review; in `Setup.INSTALLITEMS`). The item opens the question
row and answers at once with `Shutter.Msg.QuestionStarted` (`QuestionId`, `Conversation`, `Turn`, `State`, `Error`), then
builds the context (14.3) and asks the agents through their Agent Board items with `Shutter.Bridge.Msg.AgentRequest`: for
`explain`, one request (`Role` `explain`, `MemberCode` `explain`, `AgentClass` `Shutter.Agent.Explain`, `TerminalTool`
`SubmitAnswer`, `ResultClass` `Shutter.Schema.Answer`, 30000 tokens, 3 iterations; `ConfigVersion` the class's
`CONFIGVERSION` when the aihub module is installed, else `1`); for `board`, one request per enabled default specialist
(`Role` `member`, the member's code, class, `ConfigVersion` and `ConfigItem`, `SubmitAnswer`, `Shutter.Schema.Answer`, 50000
tokens, 4 iterations), and when every member has answered or failed, the coordinator's (`Role` `coordinator`,
`SubmitBoardAnswer`, `Shutter.Schema.BoardAnswer`, 50000 tokens, 3 iterations) with the members' accepted answers added to
the context as `member_answers`. A member that fails or is refused is noted on the question and the coordinator goes on with
the rest; with no usable member answer the question fails. One alarm (`AgentTimeoutSeconds`, 600 s) fails the question with
what is missing. Every run is a `Shutter.Store.AgentRun` row naming its question (`questionId`), so the case's runs and
`GET /costs` carry it (`byQuestion`: `[{questionId, caseId, runs, replayedRuns, costUsd}]`, `totals.questionRuns`).

**Record keys.** `question:<S>:<encounter>:<event>[:<receiver>]|<tier>|<member>|<conversation>.<turn>|<cfg>` for a suggested turn of a
case with a scenario (`receiver` when the case names one, so the two cases of one movement to different receivers in S22
record apart; `member` is `explain`, a specialist's code or `coordinator`; `cfg` that agent's configuration version);
a free question, or a free follow-up inside a recorded conversation, has no key and runs live only (the mimic does not answer
questions). Replay follows the same path turn by turn, each turn's context carrying the recorded earlier turns.

### 14.3 What the agents see (v1.27)

The request's `Context` is one JSON object, every text through the model view (section 9): `{tier, question: {text (the
question with the case's identifiers as tokens), source, instruction_like, note}, case_id, case (the reduced snapshot
summary), gate: [{stage, outcome, policy_version, summary, checks}], findings (the board's findings of the current snapshot,
reduced), plan (the plan as stored, reduced), whatif: {entry, outcome, outcome_ref, disposition, category, receiver,
profile_version, facts (14.1's facts), note}, conversation: {id, turn, earlier: [{turn, tier, question, answer}]},
member_answers?: [{member, answer}]}`. `earlier` carries the last three answered turns of the same conversation, oldest first,
their texts and answers through the model view; a first turn has `[]`. `member_answers` is on the coordinator's request
only. `instruction_like` is true when the question reads like an instruction (`ModelView.InstructionLike`); the `note` says
the question is data and that no tool writes. The what-if facts are the only settings, alternatives and changes an agent may
name (14.4).

### 14.4 What the core checks on the way back (v1.27)

The answering run's result (the Explain agent's, or the coordinator's) is restored (section 9) and checked
(`Shutter.Store.CaseQuestion.CheckAnswer`) before it is stored: `answer` is present and at most 1200 characters;
`confidence`, when given, is `high`, `medium` or `low`; each entry of `cites` is a fact id (`W<n>`) of the question's facts
or an evidence id of the model view (a top-level key of the reduced summary, alone or followed by a path: `message`,
`message.notes`, `history[2]`); and, for the board, `setting`, `under_alternative` and `suggested_change`, when given, each
name a fact id of the facts (`{fact: "W<n>", why?}`). A refusal ends the question `schema_failed` with the problem in `error`,
as a refused review ranking does; the members' answers are checked the same way (without the board rule) and a refused one
is noted, not used. What is stored as `resolved` comes from the core's own facts, never from the agent's text: `setting` and
`under_alternative` are the named facts whole, `suggested_change` the fact's typed change (14.1) with the agent's `why`.

### 14.5 Routes (v1.27)

**Who may run live (v1.34, the judges).** `POST /cases/{id}/questions` runs the agents live only for a caller who holds
`Shutter_LiveAgents` (operators, approvers, judges); for anyone else (the public demo's user) the request carries
`LiveAllowed` false, the agent requests get `ModeOverride` `replay`, and a question that has no recording is refused before
anything runs: `409 no_recorded_answer`, "This question has no recorded answer; a judge can ask it live" (a free question
always; a suggested turn when no `question:` recording matches its conversation and turn). **Convening the board:**
`POST /cases/{id}/board` (`Shutter_Operate` and `Shutter_LiveAgents`; body optional) reopens a blocked, escalated or failed case
as a reinvestigation does (`Shutter.Msg.Reinvestigate` with `ForceBoard`), takes fresh evidence and convenes the board whatever
the site policy says, the plan then going through the gate, rehearsal and approvals as any plan (v1.39: in policy mode a catalogue decision of person convenes the board instead of escalating the case again, and the board's plan is a board's plan, approved by a person even where the site policy for the entry's tier is automatic, so the gate never blocks it as `plan_origin`; a withheld operation and an orders_results receiver stay a person's decision whatever the request); `202 {caseId, state:
"evidence", requestedBy}`; `403 forbidden` without the resource; `409 wrong_state` for any other state (a case awaiting approval
is approved or rejected first); `409 budget_exhausted` with the budget object when the day's cap or the caller's share is spent; `409 live_unavailable` with `live` (the availability object) while the model provider refuses the key (v1.37)
(9). The case notes "Board convened by <user>", and the board's runs carry the user for the share.

- `POST /cases/{id}/questions` (`Shutter_Operate`; `X-Requested-With`; `Idempotency-Key`) `{tier: "explain" | "board",
  question | suggested: {conversation, turn}, conversation?}` -> 202 `{questionId, conversation, turn, tier, source, state,
  askedBy}`. A suggested turn takes its text, and its tier when the body gives none, from the scenario's file; a free question
  starts a conversation, or continues the one named (its turn is the next). 400 `bad_request` for a body that is not what
  is listed (a tier outside the two, no question and no suggested turn, a question over 2000 characters, a conversation over
  64); 404 `not_found` for the case, 404 `unknown_suggested` for a turn the file does not have; 409 `no_evidence` while the
  case's evidence is not collected; 503 `no_service` and `not_queued`, 502 `no_answer`, 500 `question_failed` as the review's
  route answers them.
- `GET /cases/{id}/questions` -> `{items: [...], total}`, oldest first, each `{questionId, caseId, conversation, turn, tier,
  source, question, state, askedBy, askedAt, answeredAt, error, mode, model, costUsd, runs, recordKey, ensMessageId,
  answer}` (`answer` the accepted `Shutter.Schema.Answer` or `BoardAnswer`, null until answered; `answeredAt`, `mode`,
  `model`, `recordKey` and `ensMessageId` null until set).
- `GET /cases/{id}/questions/suggested` -> `{scenario, conversations: [{id, turns: [{turn, tier, text, asked: {questionId,
  state} | null}]}]}` from `knowledge/questions/<S>.json` under the module root (`{"scenario": "S8", "conversations":
  [{"id": "c1", "turns": [{"turn": 1, "tier": "explain", "text": "..."}]}]}`), each turn with the newest question asked for it;
  a case without a scenario, or a scenario without a file, has `conversations: []`.
- `GET /cases/{id}/questions/{qid}` -> the list's fields and `facts` (14.1's facts as handed over), `memberAnswers:
  [{member, status, answer?, error?}]`, `resolved: {setting?, under_alternative?, suggested_change?}` (14.4) and `agentRuns:
  [{runId, role, member, status, mode, model, costUsd, durationMs, ensMessageId, error}]`; 404 `not_found` for a question
  that is not this case's.

### 14.6 Ask Shutter: a question about a page (v1.49)

The web app's Ask Shutter panel (the header's button, on every page) is a chat about what is on the screen. On a case page
it is Ask about this case (14.2 to 14.5, unchanged: the same routes, tiers and rules; "Ask about this case" and each
suggested question open the panel and ask the question for the reader). On every other page it asks about the page through
one read-only route, under the same rules as a live case question: nothing is written but the question's own row and its
run, nothing is recorded, and the route spends only as a live case question does.

**The question.** `Shutter.Store.PageQuestion` (`P-nnnnnn`): `page` (the page's name as the web app sends it: a lower-case
word with hyphens, at most 40 characters), the question (1 to 500 characters, trimmed, control characters removed), the
summary of the screen as the agent got it, `state` (as 14.2's; a question left `pending` or `answering` for 10 minutes is
marked `failed` when it is read), who asked, the accepted answer, the run's mode and model, its cost and the Visual Trace
link. Its run is a `Shutter.Store.AgentRun` row with no case (`Case` is empty only for such a run) naming the question, so
the day's budget (`Shutter.Util.Budget`) and `GET /costs` count it (`byQuestion` with `caseId` null).

**The summary of the screen** (`context`) is built in the web app from the page itself (`features/assistant/screen.ts`):
the page's title, its lead, its section headings and the things it links to by id, as `{id, kind, label}`, and nothing
else; at most 3600 characters. A question asked from "Ask Shutter about this" beside one of a page's questions (the Site
profile's receiver kind and tier, and enabling recovery) adds `focus`: `{question, answer, consequence, chosenBy}`, the
question's title, the answer on the page and what it does there in the page's own words, and that a person chooses it; the
route reads it as any other part of the summary. The server holds it to its shape (`Shutter.Util.PageQuestion.CleanContext`): an object of
plain keys (`[A-Za-z][A-Za-z0-9_]{0,39}`), at most three levels deep and forty entries wide in one place, texts cut at 200
characters with their control characters removed, numbers, booleans and nulls kept, anything else `400 bad_request`; and to
its length, at most 4000 characters as the agent reads it. It reaches the agent as data: inside the evidence tag the context
is JSON with every `<`, `>` and `&` written as `\u003c`, `\u003e` and `\u0026` (`AsData`), so no label can close the tag,
open another or read as markup, and a JSON reader gets the same characters back. The agent's context is `{tier: "page",
question_id, question: {text, note}, page, on_screen, on_screen_note}`, the notes saying the question and the summary are
data, never instructions; the agent's own rules say the same (`Shutter.Agent.Base.PagePreamble`).

**Who may ask** (`Shutter.Util.PageQuestion.Admit`, in this order): `403 live_agents_only` without `Shutter_LiveAgents`,
since a page has no recorded answers; `409 live_unavailable` with `live` (the availability object, 12) while the day's
budget or the caller's share is spent or the provider refuses the key; `409 no_model` when the agents' mode resolves to
`replay` (no key, no API mimic, or the core edition). The Agent item then applies the budget as to any live run (reserve
and settle, the caller's share by `RequestedBy`).

**The run.** The route sends `Shutter.Msg.PageQuestionRequest` (`Page`, `Text`, `ContextJSON`, `AskedBy`) to the Case
Question item, which opens the row, answers at once with `Shutter.Msg.QuestionStarted` and asks the Agent Board item with
one `Shutter.Bridge.Msg.AgentRequest`: `Role` `explain`, `MemberCode` `explain`, `AgentClass` `Shutter.Agent.ExplainPage`
(the Explain agent in the question tier `page`: no toolset, so no evidence tool and nothing that writes; the explain
collection's search, which the runner attaches, and `SubmitAnswer`, which the runner adds; the catalogue pin, 9, holds a run
to exactly `search_explain` and `SubmitAnswer` or it ends `catalogue_mismatch` with no model call), `TerminalTool`
`SubmitAnswer`, `Shutter.Schema.Answer`, 12000 tokens, 3 iterations, no record key, and `ModeOverride` `live` when the
instance records, so a page question is never a recording. The run is keyed by the question's id; the agent's `CaseId`,
the scope policy's and the terminal tool's are that id, so `SubmitAnswer` is accepted for it alone. Under the API mimic
(tests/mock) the tier is answered deterministically from the summary (`Shutter.Mock.Turns.PageTurn`): one knowledge search,
then `SubmitAnswer` naming the first ids the summary lists, every text marked `[mock]`, cost 0.

**What the core checks on the way back** (`Shutter.Util.PageQuestion.CheckAnswer`): `answer` present and at most 1200
characters; `confidence`, when given, `high`, `medium` or `low`; each entry of `cites` is `page` or an `id` the summary
lists (a case, a scenario, an incident), nothing else. A refusal ends the question `schema_failed` with the problem; a
missing answer `failed`; the item's alarm (600 s) fails it with what is missing.

**Routes.**

- `POST /page-questions` (`Shutter_Operate`; `X-Requested-With`; `Idempotency-Key`) `{page, question, context}` -> 202
  `{questionId, page, state, askedBy}`; `400 bad_request` for a body over 16000 characters, a page's name that is not one,
  a question missing or over 500 characters, or a context out of shape or over 4000 characters; then 403 and 409 as above;
  503 `no_service` and `not_queued`, 502 `no_answer`, 500 `question_failed` as the case question's route answers them.
- `GET /page-questions/{qid}` -> `{questionId, tier: "page", page, question, state, askedBy, askedAt, answeredAt, error,
  mode, model, costUsd, ensMessageId, answer}` for the one who asked it; `404 not_found` for anyone else, as for an id that
  is not there. The summary is not sent back: the asker sent it.

**The web app.** Without `Shutter_LiveAgents` the panel shows the page's written guide (`features/assistant/guides.ts`:
what the page is and what to try next, with links) and says live answers need the judges' account; with no model key and
no mimic it says so and shows the guide. On the Site profile, "Ask Shutter about this" beside a receiver's kind and tier
and beside enabling recovery asks about that question once for the reader where a live answer can be given (in the panel
from 1200 px, under the question below it, so the form stays in view); wherever none can be given it shows the question's
written explanation instead, and asking changes nothing in the profile. The trial answers each page's suggested
questions from its mock (`mocks/pageQuestions.ts`) and labels them as sample answers until they are recordings
(`PAGE_ANSWERS_RECORDED`). Open or closed is remembered per tab; the panel sits beside the page from 1200 px and is a
drawer below, the whole screen on a phone.

## Repository layout

The published IPM package is the repository root (`module.xml`, name `iris-shutter`, sources under `src/`): the whole of Shutter for an AI Hub build, 2026.3 or later with Interoperability (`SystemRequirements`, the organisers' line of 2 Nov 2026), the live runner, the agents, tools, the publisher, schemas, policies and knowledge bases included, since they need the `%AI` package. The core alone is `core/module.xml` (name `iris-shutter-core`, `SourcesRoot ../src`, the same resources without the agents' classes), loaded by path on a 2026.2 Community image and in CI, never published; it compiles there and replays recorded runs. Both modules contribute classes to the `Shutter` package; nothing under `src/` may reference `%AI`.

## 15. The publisher (v1.35)

Shutter publishes what an operator may read, for an MCP client, through IRIS's own MCP gateway; it publishes no write.
The AI Hub build only: the core edition has no `%AI.MCP.Service`, and the Doctor's `publish.available` says which.

- **The tools**, `Shutter.Publish.Tools` (`src/Shutter/Publish/`, a `%AI.Tool`: every public ClassMethod is a
  stateless tool, its description from the method's comment): `ListCases(state, receiver, limit)`, `GetCase(caseId)`
  (the public fields, the current plan's digest, disposition and summary, the approval of record, the place in the
  incident, the precedents summary, `version`), `GetEvidence(caseId)`, `GetFailure(caseId)` and `GetTimeline(caseId)`
  (the board's own evidence tools, 9), `GetPlan(caseId)` (the plan, the gate's decisions, the rehearsal's outcome),
  `GetEvents(caseId, limit)`, `ListIncidents(state, limit)`, `GetIncident(incidentId)` (the chains and their cases),
  `GetPrecedents(caseId)` (6.4) and `Health()`. No patient or encounter identifier leaves: the rows carry none, and
  every text (headlines, outcomes, plan summaries, gate details, events) goes through the model view's tokens (9), as
  the board's does. An unknown case or incident answers `{error: "not_found"}`.
- **The audit.** Every call writes a `Shutter.Store.PublishCall` row: `at`, `user` (the IRIS user the gateway
  authenticated), `tool`, `target` (the case or incident id, or the list's filter), `version` (the case's version when it
  was read) and `durationMs`; never the answer. The Doctor's `publish.calls_today` counts them; `Health()` reports the
  same.
- **The gateway**, `Shutter.Publish.Service` (a `%AI.MCP.Service`): `SPECIFICATION` `Shutter.Publish.Tools`; its
  `OnAuthenticate` requires `Shutter_Publish` of the caller the application signed in (and can sign an anonymous caller
  in from an HTTP Basic header, should a site run the application unauthenticated). It answers `GET
  /mcp/shutter/v1/health`, `GET /v1/services`, `POST /v1/tool_call` and `WS /v1/ws` to `iris-mcp-server` only: a direct
  call gets 502 `GATEWAY_REQUIRED`, and the gateway checks the service's identity header before trusting its tools.
- **The resource and the application.** `Shutter_Publish` (12) is held by `Shutter_Operator` and, through it,
  `Shutter_Approver`; the forwarder and the public demo's visitors have no such access. `Setup.InstallAIHub` makes the
  web application `/mcp/shutter` (`Setup.EnsurePublishApp`: an MCP Server application, `Type` 18 as the portal's "Edit MCP
  Server" page makes them; password authentication; `DispatchClass` `Shutter.Publish.Service`; the resource
  `Shutter_Publish` on the application too) where `%AI.MCP.Service` and the publisher's classes are compiled, and records
  it in `^Shutter.Config("webapp","/mcp/shutter")`; the Doctor carries `publish {available, webapp, calls_today}`.
- **The sidecar.** `iris-mcp-server`, shipped in the image at `/usr/irissys/bin/iris-mcp-server`, bridges an MCP client to
  the gateway and passes the client's own credentials through: a client that sends HTTP Basic (or a bearer) to the
  sidecar is signed in to `/mcp/shutter` as that user, so each person reads as themselves and the audit names them. Run it
  with an HTTP or SSE transport, `iris-mcp-server -c shutter-mcp.toml --transport http://127.0.0.1:8765 run --iris-host
  127.0.0.1 --iris-port 1972 --iris-endpoint /mcp/shutter`, the TOML naming the instance (`[[iris]] name`, `[iris.server]
  host, port, username, password` for the sidecar's own connection to the superserver) and the endpoint (`[[iris.endpoints]]
  path = "/mcp/shutter"`); the client's MCP address is then `http://127.0.0.1:8765/mcp`. A stdio transport carries no client
  credentials, so its calls reach the application anonymous and are refused: use HTTP or SSE. A user without
  `Shutter_Publish`, or with a wrong password, sees only the sidecar's own `iris_status` tool. Proven on the AI Hub build
  (2 Nov 2026): eleven tools listed, `ListCases`, `GetCase` and `Health` answered, the forwarder refused. The install does
  not start the sidecar: a site's MCP client configuration does (`docs/INSTALL.md`).

## 16. The demo's portal page (v1.41)

`Shutter.Portal.Guide`, a `%CSP.Page` in the Management Portal's own web application of the namespace
(`/csp/healthshare/shutter/Shutter.Portal.Guide.cls` on the public demo), is the demo's way into IRIS: what is running, the
board's case in the Visual Trace, the latest cases, and links to the portal's pages the demo leaves open.

- **Who gets it.** A demo instance only (`^Shutter.Config("demo")`), and a holder of `Shutter_Portal` or `Shutter_Operate`;
  anyone else 404. It reads Shutter's tables through `%ExecDirectNoPriv`, fixed queries and no more than the app's public
  sign-in can read, since `demo-trace` holds no SQL privilege on them; so a site's portal users, whose cases hold real
  messages, never reach it.
- **What it does.** `GET` and `HEAD` only, 405 otherwise. No broker, script or form: inline CSS and SVG, no timed refresh,
  which would take a screen reader back to the top of the page (WCAG 2.2.1), but a plain Refresh link to the page itself
  beside the time it was read, `Cache-Control: no-store` and a Content-Security-Policy that allows nothing else.
  Everything from a case is escaped, since it began in a message.
- **What it reads.** The productions' state from `^Ens.Runtime` in each namespace, never `Ens.Director.GetProductionStatus`,
  which takes the runtime lock. Messages and errors in the last hour and the messages queued, through the tables' indices.
  The newest escalated S8 case the agents ran on, by query, since its number changes with each build; the agents' last
  runs. A figure it can't read leaves its tile out, and with no S8 case the box says so.
- **The production's operations.** Two panels read the running production's items (`Shutter.Production` when none runs) from
  `Ens_Config.Item` and each item's settings in effect (`Ens.Config.Item`'s `PopulateVirtualSettings`: the production's
  value, else the system default setting, else the class's), opened with no lock; an item's enabled and pool size are a
  system default setting's when one is set, as `Ens.Director` starts the item (a pool size only when it is a whole number
  above nought). **Agents**: every item of `Shutter.Bridge.Operation.Agent` or a subclass, with enabled, pool size, the
  model in effect and where it comes from (as the live runner picks it: the API mimic's while it is on; else the item's
  `Model`, then its configuration's model, the item's `ProviderConfig` or else the instance's `AI.LLM.Shutter`, whose model
  is `SHUTTER_MODEL`; then the agent class's `MODEL`), the provider configuration and its `model_provider` (a
  `ProviderConfig` is checked as typed, before `AI.LLM.` goes in front of it, and one that looks like a key reads "hidden"
  and is not looked up), the mode in effect (`ResolveMode`; while it is replay, the model reads "<model> when live; none
  while replaying", since a replay calls no model; a mode set to anything but `auto`, `live`, `record` or `replay` reads
  "not valid"), `MaxIterations`, `TokenBudget`, `RequestTimeoutSeconds` (each "not valid" when not a number) and the item's
  last run (by the run's request header); a line says where a model is set, and another that a run's request can set its own
  mode and limits (`RunSpec.FromRequest`: `ModeOverride` replay on a reopened case's runs and, since v1.58, a replay-only scenario run's, `CaseWorkflow.Stamp`, and a
  question's, `Question.BuildRequest`, when the person who asked is without `Shutter_LiveAgents` or the provider refuses the
  key; `MaxIterations` and `TokenBudget` from `Shutter.Process.Question` and `Shutter.Process.Review`). **Operations**:
  every other business operation, with enabled, pool size, class and only the settings `OPERATIONSETTINGS` names (timeouts,
  retry, reply codes, alerts), each only in its own form (a number; 0 or 1 for `AlertOnError`; the engine's pattern=actions
  list for `ReplyCodeActions`), never one whose name or value looks like a credential, key, certificate, server, address or
  file. Hidden, in any case: a value holding `sk-` or `hf_` where a word starts (so `task-runner` shows), or `sk-ant`,
  `ghp_`, `gho_`, `github_pat_`, `xox`, `sk_live_`, `sk_test_`, `rk_live_`, `rk_test_`, `glpat-`, `-----BEGIN`, `secret://`,
  `password`, `bearer `, `://` or `@` anywhere, a credential written as its name and value (`key=`, `token=`, `apikey:`,
  `secret=` and the like), or `basic` and a base64 run. Hidden, with case kept: `eyJ`, `AKIA` or `ASIA` followed by sixteen
  capitals or digits, or `AIza` followed by ten more. Hidden too: one run of 24 or more letters and digits holding both, as
  a random key is. A name is read as its words, so `SSLConfig` and `ApiKey` stay off and `UncertainSettleSeconds` shows. The
  same check hides a `Model`, `ProviderConfig` or `AgentClass` that looks like a key. Of a configuration it reads only
  `model` and `model_provider`, with no secret resolved, and only with `%Admin_ConfigStore`; without it, `AI.LLM.Shutter`'s
  model comes from Shutter's record and another configuration reads "not readable". An item it can't read is a row that says
  so. A card's column is 300 px or the whole width, whichever is less, so the page never scrolls sideways at 320 px.
- **Sessions.** A request with no session behind it ends the one it opened, so a caller that keeps no cookie can't use up
  the licence units; a visitor already in a portal session keeps it.

## 17. Receiver outages (v1.47)

One incident per watched receiver: an outage, opened and closed by a read-only poll from Shutter's own production job, never
by a connection to the receiver. It is a store of its own, `Shutter.Store.Outage`, beside `Shutter.Store.OutageEvent` (what
happened to it, append only: `{at, kind, detail, by}`, `kind` one of `opened`, `kind`, `draining`, `open`, `closing`, `closed`,
`needs_person`, `paused` and `overdue`, and the send's own kinds of 17.8) and `Shutter.Store.ReceiverReading` (the last reading per watched receiver, overwritten by each
poll). A receiver is watched when its profile entry has a `watch` block (6.4); with none, the item `Receiver Watch` does
nothing, and every route below answers empty lists.

### 17.1 The item

`Receiver Watch` (`Shutter.Operation.ReceiverWatch`, a business service on `Ens.InboundAdapter`, `CallInterval` 5,
`PoolSize` 1) is in `Shutter.Production` and in `Setup.INSTALLITEMS`, so a site's own production gets it from
`InstallInto` (12) and the Doctor's `missing_items` names it when it is absent. Per watched receiver it reads, in the
watched namespace, the production's state, the item's status, adapter state, queue, head message (the oldest header to the
item reading Delivered) and the job list's active message as a check, and the item's `FailureTimeout`, `DefCharEncoding`,
`ReplyCodeActions`, `GetReply` and `StayConnected` through `EngineRead.ItemSetting` (a class default only on the engine's
exact "No Setting" answer at a stock HL7 TCP operation; anything else reads unknown). Every value is stamped, and a failed
read is stored as unknown, never as healthy.

### 17.2 The states

`retry` is read off the item: `unlimited` (`FailureTimeout` -1), `bounded` (above 0: it retries, then gives up) and `none`
(0). "The no-retry path" means an item that finishes with a message by itself, `bounded` or `none`, or whose setting can't be
read. Durations are elapsed time, never a number of polls. This table is the one definition of the states.

| State | Meaning | Enters on | Leaves on |
| --- | --- | --- | --- |
| `open` | Down, Refusing, Not answering or Can't tell; the engine owns everything queued | every poll across 30 s reading `Status` Error or Retry with the adapter disconnected; the Refusing or Not answering reading (the head unchanged across two polls with the rows below); at a no-retry item, one new Error header whose every attempt says the connection never opened | the retry path: connected and `Status` OK (`draining`); the no-retry path: queue 0, no head message, no header of the window Queued or Delivered, on two polls 5 s apart (`closing`), whatever `Status` and the adapter read; on the same path, `settle_minutes` (10) since the open with the two quiet polls never seen (`needs_person`, a busy feed); a person marks it down on purpose (`paused`) |
| `draining` | The engine is making progress through the backlog | connected and `Status` OK, with no Refusing or Not answering reading | queue 0 and no header of the window Queued or Delivered, twice (`closing`); `Status` Error or Retry or disconnected (`open`, the quiet clock reset); `settle_minutes` with the queue never at 0 (`needs_person`) |
| `closing` | Every header of the window settled and read; the set computed where the build has a set gate | the drain rule, the no-retry path, or Read again | with a set gate: `offered` when the set lists a message that never reached the receiver, otherwise as with none, `set.reason` naming the condition when the set was not computed. With no set gate: no Error header of the window, `closed`; any, `needs_person` ("N messages failed and were not offered; a person reads the trace", `set.status` `not_computed`, `set.reason` "no set gate in this build") |
| `offered` | The never-opened list is on the card; at a receiver with `engine_resend` an approval is offered | `closing` | approval given (`sending`); the set's digest moved (recomputed, stays `offered`); a person closes with a reason (`closed`); a dirty read (`open`) |
| `sending` | One at a time, each row of the ledger written before the call | approval | run done (`closed`); a send not Completed, a stop or a restart mid-run (`needs_person`) |
| `needs_person` | Something a person must do: a stopped run, a busy feed, an unreadable check, an expired approval | as above | read again and offer again (`closing`); a person closes (`closed`). With no approval on the row (nothing was sent), the poll computes it again every minute as it does an `offered` row (v1.54): while the engine still tries something of the window it stays here, its set and lists read as they are now, with no event; once nothing is tried it moves on as a close does. After an approved run stopped, only a person's Read again computes it |
| `paused` | Down on purpose until a time | a person's act | the time, or a person (`open` or `closed`) |
| `closed` | | | never |

`kind` (`down`, `refusing`, `not_answering`, `cant_tell`) can change between polls. A dirty read during `draining` or
`offered` returns the row to `open`; `closed` is reached only from `closing` or by a person. The window runs from the open
minus `window_minutes` (5) to the drain; its headers are those to the item with `TimeCreated` inside it. Every change of
state runs under `LOCK ^Shutter.Outage(id)` on the row's `Version`, and a stale copy changes nothing.

### 17.3 The routes

All under `/api/shutter`, JSON in and out.

- `GET /outages?state=open|all` (`Shutter_Operate`; `open`, the default, is every row not `closed`) answers
  `{ "items": [Outage], "receivers": [Reading] }`, newest first. 400 `bad_request` for another state.
- `Reading`, the always-on line, one per watched receiver: `{ "receiver", "namespace", "item", "reading":
  "healthy|slow|down|refusing|not_answering|cant_tell|unknown", "status", "adapterState", "queue", "headHeaderId",
  "activeMessage", "failureTimeout", "retry": "unlimited|bounded|none|unknown", "defCharEncoding", "replyCodeActions",
  "replyCodeActionsStock", "getReply", "stayConnected", "settingSources": { "<setting>": "item|class_default|unknown" },
  "checkedAt", "unknownFields": [..], "why" }`. `replyCodeActions` is the item's resolved string and
  `replyCodeActionsStock` true when it is the engine's default; `why` says why a reading is unknown. A receiver not read
  yet reads `unknown` with `why` "not read yet"; a row its watcher has not written for 60 s reads `unknown` with its last
  `checkedAt`.
- `GET /outages/:id` (`Shutter_Operate`) answers one `Outage`, 404 `not_found` for another id: `{ "id", "receiver",
  "namespace", "item", "state", "kind", "openedAt", "drainedAt", "closedAt", "runbook", "call", "approvers": [..],
  "pausedUntil", "overdueAt", "readings": Reading, "window": { "from", "to" }, "settled": { "completed", "suspended",
  "error", "other" }, "alerts": [ { "at", "kind", "text" } ], "lists": { "queued": [Row], "offered": [Row], "reached":
  [Row], "refused": [Row] }, "openCases": [ { "caseId", "reason", "owner" } ], "linkedCases": [ { "caseId", "state",
  "headerId", "resolved" } ], "outcome", "version", "set": { "digest", "computedAt",
  "setPolicyVersion", "status": "computed|not_computed|withheld", "reason" }, "approvable": false, "approval": null,
  "sentByShutter": 0, "acts": ["pause", "close"], "resends": [Resend], "words": { "first", "do", "call", "critical" }
  }`, with `lists.closed` (v1.53) beside the other four. `Row` is `{ "headerId", "controlId", "timeCreated", "status",
  "attempts", "reason", "patient": { "id", "authority" }, "sibling": { "headerId", "status", "at" }, "acts": [..],
  "closure", "closedBy", "closedAt" }`; `acts`, `closure`, `closedBy` and `closedAt` are v1.53's (17.8): `acts` is empty and
  the other three null except where 17.8 sets them. `Resend` is one row of the ledger (17.8). Every field is present from the first moment: empty lists, zero counts, null where
  nothing has filled it. `linkedCases` is every case linked by receiver and time at the close, `resolved` true for one this
  close resolved; `openCases` is read again on every read (v1.54): a case finished since (resolved, by Shutter's resend or
  by hand, or failed) leaves it, and so does one whose message the card lists already (the ledger, and while the row is
  not closed `lists.offered` and `lists.closed`), each `reason` in plain words as the case reads now; `outcome` is the close's words, such as "Transport outage closed. 2 delivery exceptions still need review."
  or "5 messages failed and were not offered; a person reads the trace.", or null. `Outage.ToJSON()` serialises the row, and
  the route adds `words`.
- `set.status` and `set.reason` are the one name for the set's state on every surface: `not_computed` with its reason ("no
  set gate in this build", or the condition that failed), `withheld` with "down on purpose", `computed` with its digest.
- `acts` holds `pause` and `close` while the row is not closed, and nothing once it is or while it is `sending` (v1.54: a
  pause or a close would not stop the send, so the route refuses them then); a build with the set gate
  (`Shutter.Util.ResendSet`) lists `["pause", "read_again", "close"]`. `read_again` marks the row (`ReadAgainAt`, an event
  `read_again` naming the person) and answers the row at once: the REST process never switches to the watched namespace, so
  the next poll of `Receiver Watch` (every 5 s), a production job, computes the set there and clears the mark. An `offered`
  row is computed again by the poll every minute, so a member resent by hand moves the digest; a message of the window
  tried again sends the row back to `open` with the set withdrawn (`set.reason` "the engine is trying a message of the
  window again"), `lists.offered` empty and no digest (v1.53), so nothing reads as offered while the engine tries. A page shows only the acts the row lists. `approvable` is true only when the build has the send and the
  receiver has `engine_resend`; `approval`, when present, is `{ "id", "by", "givenAt", "goodUntil", "digest", "note" }`. A
  list of what to send again is `lists.offered[].controlId` in order. While a row is `offered` at a receiver whose
  `duplicates.behaviour` is `unknown` or `files_twice`, or that declares none, `acts` also lists `handled_by_hand` (v1.53,
  17.8).
- `POST /outages/:id/acts` (`Shutter_Approve`, the CSRF header) with `{ "act": "pause", "until": "<UTC time>" }`, `{
  "act": "close", "reason": "..." }`, `{ "act": "read_again" }` or (v1.53, 17.8) `{ "act": "handled_by_hand", "headerId",
  "note" }`, and optionally `"version"`. 200 with the outage as `GET /outages/:id` gives it; 400
  `bad_request` for an act the row doesn't list or one it lists that this build's route doesn't handle (the row is left as it was), a pause with no time, or one not in the future, or a close with no reason or
  one over 1,000 characters; 409 `wrong_state` on a closed row, `version_changed` (with `currentVersion`) on a stale
  version; 413 `too_large` for a body over 8,192 characters, refused before it is parsed. A pause moves the row to
  `paused`, sets `pausedUntil`, and withholds any set (`set.status` `withheld`, `set.reason` "down on purpose"); a close
  records the reason and the person. The person is the signed-in user, never a name from the body. An `Idempotency-Key`
  replays the stored reply (5). An operator's session reads every route and is refused here with 403.

### 17.4 The card's words

`words` is composed on every read from the row, its reading, the receiver's profile entry and what the build holds, so the
words follow the build (`Shutter.API.Outages.Words`, a pure method with a table test):

- `first`, by kind. Down: since when, what is queued, then what the engine does, from the setting as read: at `unlimited`
  "At this operation the engine retries without limit (FailureTimeout -1, read off the item): it goes on attempting them, in
  order, when the listener is back; a refusal, a stopped production or a changed setting can still stop one."; at `none` or
  `bounded` that the engine does not retry, or retries for at most N s, and that the failed messages will not go by
  themselves, then by tier: with `approvable` the one approval; without it "Shutter will not send these messages. Review them
  in the Message Viewer using the site's recovery procedure.", and with no set gate in the build "N messages failed and were
  not offered; a person reads the trace." Where the setting could not be read: "Whether this operation retries could not be
  read: treat them as not going by themselves until a person checks the item." Refusing: the head message refused, the
  engine trying it again, "Shutter resends nothing". Not answering: the head message "has been written to it at least once
  and may already be held there". Can't tell: "Whether the listener is back cannot be read from the engine at this receiver:
  it will show on the next send.", then by tier as Down. On return: "The engine's connection recovered at HH:MM." (only at a
  retrying item, where the adapter read connected), "Delivery backlog drained at HH:MM. Application processing has not been
  independently checked.", "Nothing remains queued. N deliveries Completed; M was Suspended and still needs action." (v1.54:
  "Nothing remains queued." only while the receiver's reading shows its queue at 0, else "N messages are still queued.";
  after a send, what Shutter's ledger did with each message by its last row: "Shutter sent N again, each new header
  Completed", "N the receiver already held", "N handled by hand", "N failed when Shutter sent them again and still need
  action", (v1.55) "N sent again whose result is not known yet: Shutter reads their new headers again and a person reads
  the trace", "N not sent and still need action", and only the Error headers the ledger does not account for "ended in
  Error"; a later run's row on a message, or on Shutter's own clone sent in its place, is that message's last row). Closed:
  "Transport outage closed.", with "N delivery exceptions still need review." while cases stay open. Where the item's
  `ReplyCodeActions` is not the engine's default, the string is printed with "This operation's reply actions are the site's
  own: what an AE, AR or timeout does here follows this string". Always last: "Recovery attempts initiated by Shutter: 0." (v1.54: `sentByShutter` counts every message this outage's
  runs sent again, whatever came of it, from the ledger),
  with "The integration engine may still be delivering or retrying." while messages are queued or a head message is read, and "Nothing
  is sent to the receiver to check this."
- `do`: "Do: " and the site's runbook line; closed, "Do: nothing more for this outage." only while no message's last ledger
  row is `failed` or `unknown` (v1.55: else "Do: read in the Message Viewer the message listed below whose resend failed
  ...; Shutter sends nothing more for it."); at Refusing "Do: a person decides in the Message Viewer; Shutter does not
  suspend or discard."; while paused, "Down on purpose until ..." in its place. At a retrying receiver (`unlimited` or
  `bounded`): "Entering one by hand first is your downtime procedure's call; at this receiver a duplicate is" refused, with
  its words, filed twice, or unknown, from the profile's `duplicates`. Open an hour or more: "Down longer than the site's
  limit: the lab's downtime procedure applies."
- `call`: "Call: " and the site's call line as written, who may approve here (the entry's `approvers`, else
  `approvers.escalation`), and "An operator can do nothing here, which is safe."
- `critical`, at an `orders_results` receiver: "Shutter does not assess clinical urgency. If delayed reporting may require
  clinical action, contact the laboratory using the site's critical-results and downtime procedure. Do not re-enter or amend
  a result solely from this page." Null elsewhere.

No word names a supplier, a patient, a result value or "Verified".

### 17.5 Forwarded endpoints, and the one security contract

`/summaries` goes to `Shutter.API.Summaries` and `/assist` to `Shutter.API.Assist` (`Map Prefix ... Forward` in the
`UrlMap`). A build without the class answers 404 `not_in_build` on its prefix (`Dispatch.OnPreDispatch`), and the other routes
are unaffected. A class reached by `Forward` inherits none of `Dispatch`'s checks, so every route here and every forwarded
endpoint keeps one contract:

- it applies the same server-side session and resource checks as the main API, through
  `##class(Shutter.API.Dispatch).Allow(resource, change)`: no session 401, the wrong resource 403;
- every changing request requires the CSRF header `X-Requested-With: Shutter` (403 `csrf` without it);
- an idempotent action uses the existing `Idempotency-Key`, and a replayed key answers the stored reply;
- a body is bounded before it is parsed;
- the server selects the agent item, the subject type and the storing method from an allowlist, never from the request.

### 17.6 The Doctor's lines

The Doctor's `outages`: `{ "open", "by_state", "receivers": [ { "receiver", "namespace", "item", "reading", "checkedAt",
"defCharEncoding", "replyCodeActions", "replyCodeActionsStock", "reply_actions_note", "failureTimeout", "retry", "getReply",
"settingSources", "saveReplies", "saveRepliesSource" } ], "approvers_missing": [receiver], "policy_version",
"set_policy_version", "hold", "routers_validating": [ { "namespace", "item", "validation" } ], "alert_on_error_off": [ {
"namespace", "item" } ], "declared_not_in_build": [ { "receiver", "block", "state" } ] }`. `receivers` is empty on a profile
with no watch block. The watched items' settings come from the stored reading; `SaveReplies`, the routers and `AlertOnError`
are read in the watched namespace, and where the calling process may not switch there they read unknown with the reason.
`set_policy_version` is the set gate's `SETPOLICYVERSION` beside the gate's `POLICYVERSION`, and "" when the build has no
`Shutter.Util.ResendSet`; `hold` is the hold store's `DoctorLine()` (held count, the oldest hold's age, the site's item and
shim present), and "" when the build has no `Shutter.Store.HoldEntry`. `declared_not_in_build` names each `engine_resend`
(true), `hold` or `mail` block a profile declares, with "declared; not in this build" when no part of the build acts on it,
so a block never appears to enable recovery.

### 17.7 The reset

The demo's `PurgeStore` empties `Shutter.Store.OutageEvent`, `Shutter.Store.Outage` and `Shutter.Store.ReceiverReading`
with the other stores, and since v1.53 `Shutter.Store.ResendRecord`: the purge resets the case counters, so a ledger row's
`CaseId` left behind would name a new case of the same id.

### 17.8 The send (v1.51 to v1.54)

At a receiver whose profile entry says `engine_resend`, in a build with `Shutter.Operation.EngineResend`, a person's one
approval of an offered set has the engine send each message again, in order, from Shutter's production. Design and rule
examples: `docs/design-1.4.0.md`.

**The set** (`Shutter.Util.ResendSet`, computed by the poll in the watched namespace). The item first: the production
running, the item enabled, its queue at 0, its `Status` not Retry, no head message, and its `FailureTimeout` read and not
-1; a failed condition gives `set.status` `not_computed` with the reason. Then each origin header to the item in the window,
in header id order, goes to one list, by the first rule that places it:

1. Queued or Delivered: `queued`. Completed: no list. Any status but Error: `refused`.
2. (v1.53) A ledger row for it `closed_as_present` or `handled_by_hand`: `closed`, with `closure` `already_delivered` or
   `handled_by_hand`, `closedBy` and `closedAt`.
3. Its copies in the session: a copy resent by hand is `queued` while tried and `refused` after; a clone of Shutter's
   whose every attempt never opened stands in the origin's place; any other clone of Shutter's is `refused` ("Shutter
   resent it at HH:MM and that copy reads <status>").
4. Every retained attempt a connection that never opened (`Shutter.Util.EngineWords.Attempts`); a reached attempt is
   `reached`, words it can't read are `refused`.
5. The log reaching back past it.
6. No production start and no active message put back on a queue since it was created (`EngineRead.Interrupted`, v1.53).
7. The patient check passes; a message it holds is `refused` with "held by the patient check: <why>".

The rest are `offered`. `set.digest` is the SHA-256 of `SETPOLICYVERSION` and the offered header ids in order, so a new
rule version voids an approval not yet sent.

**The patient check** (`Shutter.Util.PatientCheck.Check(ns, item, originHeaderId, receiver, exclude, members)`;
`exclude` the set's and the run's case ids, `members` the set's or the run's header ids). It reads every PID by name and
every PID-3 repetition as a key, identifier and authority (PID-3.4.1, then PID-3.4); the message's body unreadable, no
PID, or a key with a blank authority holds it. Its answer: `{ "hold", "scope": "order|patient", "patients": [ { "pid",
"keys", "hold", "rule", "why", "newer", "cases" } ], "why", "read_ms", "headers_read" }`, `rule` one of `same_order`,
`linked_order`, `same_patient`, `replacement`, `identity`, `open_case`, `unreadable` or `cap`.

- **The patient-wide rule** (`scope` `patient`): ADT and every other message, an order or result with no order number,
  and any message at a receiver whose category is not `orders_results`. It holds the message when a newer header to the
  item (less this run's own clones, at most 2,000 read) is Queued, Delivered or Completed and its body shares a key, or
  when Shutter has an unresolved case (any state but `resolved`, less `exclude`) for a key at this receiver. Since v1.53 a
  newer body that can't be read holds it too.
- **The order rule** (`scope` `order`, v1.53): an ORM, OML, OMG, OMI, ORU or OUL at an `orders_results` receiver with an
  order number. Every ORC and OBR gives a placer (ORC-2, else OBR-2), a filler (ORC-3, else OBR-3) and its parents (ORC-8
  and OBR-29). Two numbers are the same when their identifiers are equal and their namespaces equal or either blank; a
  placer is compared with placers and a filler with fillers. Two order groups are related when any number or parent is
  the same, and proven distinct when not related and both carry a placer or both a filler. A message is about other
  orders when each side has an order group and every pair is proven distinct. It holds the message when:
  1. a newer header to the item, of any status and any patient, not in `members`, has a related order group
     (`same_order` or `linked_order`): "a newer message on the same order (placer ORD1) reached the receiver at 03:13
     (control id ...)", or, one not reached, "... header 812, reads Suspended: a person decides the order's messages
     together";
  2. a newer header to the item, Queued, Delivered or Completed, shares a patient key and is not about other orders, or
     carries a replacement in ORC-1 (RP, RU, RO, RQ, RR, XO, XR, XX) (`same_patient`, `replacement`); a result of another
     order for the same patient does not hold it;
  3. a body of the namespace newer than the message's, to any item, is an ADT merge or identity change (A18, A24, A30, A34,
     A35, A36, A37, A39, A40, A41, A42, A44, A45, A46, A47, A48, A49, A50 or A51) naming a key in PID-3 or MRG-1, or one of
     Shutter's cases on such an event naming a key was opened after the message was created (`identity`); more than 5,000
     ADT bodies read, or a failed read, holds every candidate (`cap`, `unreadable`);
  4. Shutter has an unresolved case at this receiver for a key, less `exclude`, whose stored copy is not about other orders
     or can't be read (`open_case`);
  5. a newer body or a case's copy can't be read (`unreadable`).
  A merge that never passes through the watched namespace is not seen, and the card says so.

**The approval.** `POST /outages/:id/approvals` (`Shutter_Approve`, the CSRF header, an `Idempotency-Key`) with `{
"digest", "note", "version"?, "receiverChecked"? }`. 409 `wrong_state` unless the row is `offered` with `set.status`
`computed` and something offered; 409 `not_approvable`; 409 `set_changed` with `currentDigest`; 409 `version_changed`
with `currentVersion`; (v1.53) 409 `receiver_check_needed` at a receiver whose `duplicates.behaviour` is not `refuses`
when `receiverChecked` is not true ("At this receiver a duplicate is unknown: check the receiver for these messages
first, and say so with the approval."); 400 `bad_request` with no digest or no note, or a note over 1,000 characters;
(v1.54) 409 `recovery_stopped` while Shutter recovery is stopped, `recovery_shadow` while the site is in shadow mode and
`control_unreadable` when the recovery control can't be read (18), asked once the row, its version and its digest hold,
with words a person reads ("Shutter recovery is stopped, so this resend can't be approved, and nothing was recorded. The
messages stay offered: approve them once an approver has cleared the stop in Settings."; "Shadow mode: recovery is off at
this site, so Shutter will not resend these messages, and nothing was recorded. ..."): no approval, no ledger row, the
row still `offered` at its version. Otherwise it records `approval` (`goodUntil` 15 minutes on), writes the run's ledger
rows `approved` in the set's order, and moves the row to `sending`.

**The ledger** (`Shutter.Store.ResendRecord`): one row per message, `state` `approved`, `sending`, `completed`, `failed`,
`closed_as_present`, `handled_by_hand`, `stopped` or `unknown`, with `ControlId` and `RecordedBy` (v1.53). `resends` on the
outage (v1.53) gives its rows in position order: `{ "runId", "position", "headerId", "controlId", "newHeaderId", "state",
"closure", "words", "by", "at", "caseId", "halt" }` (`halt` v1.54: `recovery_stopped`, `recovery_shadow`,
`control_unavailable` or `control_unreadable` on a row the recovery control halted, else null), `closure` `sent`, `already_delivered`, `handled_by_hand`, `failed` or
`unknown`, and null while approved, sending or stopped; `by` the approver, or the person who recorded a hand closure.
`GET /cases/{id}` carries `resends` too (v1.53): the rows on the case's origin header.

**Engine Resend** (`Shutter.Operation.EngineResend`, a business service polling for `sending` rows). Before each message it
reads the item's gate, the settings the approval bound (`DefCharEncoding`, `IPAddress`, `Port`) and the set's rules again;
it writes the row `sending`, calls the stock `Ens.MessageHeader.ResendDuplicatedMessage` (the stored body, unchanged),
and reads the new header until it settles, within the item's `FailureTimeout` and `ConnectTimeout` and 10 s. A row found
`sending` (a restart mid-call) stops the run with nothing more sent.

- (v1.54) **The recovery control, last before every message** (18): after the gate, the settings and the set's rules, and
  before the row is written `sending`, Engine Resend takes the control's lock (`RecoveryControl.HoldForResend`) and reads
  the stop and the mode; it keeps the lock until `ResendDuplicatedMessage` has returned, a write to the engine's own
  queue, never a network call, so a stop commits either before the check or after the hand-over. Stopped, in shadow mode,
  or a control that is busy for 5 s or can't be read: the run halts. That message and every row not sent read `stopped`
  with `halt` the code and words such as "not sent: Shutter recovery was stopped by appr1 at <time>, so the run halted
  before this message", nothing is handed to the engine, and the outage goes to `needs_person` with an event ("...,
  so the resend halted before header N: 2 sent before it, 3 not sent. Nothing more goes on this approval: once an approver
  has cleared the stop in Settings, read the set again and approve it again."). While `needs_person`, `words.first` leads
  with "The resend halted because Shutter recovery was stopped: 2 of 5 messages were sent and 3 not sent. The rest go
  only by a new approval once an approver has cleared the stop in Settings: read the set again, then approve it."
  (shadow mode: "because the site is in shadow mode, with recovery off", "once the site enables recovery in its site
  profile"). The run never resumes by itself: `read_again` offers the set again, and a new approval goes once the stop is
  cleared and recovery enabled. A message handed over before the stop committed may still reach the receiver; the card
  reads it as sending, then as it settled. It holds no permit, so it is not in the stop's `outstanding`.

- Completed: the row `completed`, the message's case resolved with what was sent.
- Error or Suspended with the receiver's declared duplicate answer: the row `closed_as_present`; since v1.53 the
  message's own cases are resolved with disposition `already_delivered`: "Already delivered: the receiver reported it
  already holds this message (MSA-3: <its words>); the engine never delivered it by this route, and a hand entry would
  explain it. Shutter has not compared the stored result or amendment." Only that message's cases, never every case
  linked to it. The answer is declared when MSA-1 is AE or AR and an ERR-3 equals `duplicates.code`, or MSA-3 (trimmed)
  equals `duplicates.phrase` or, since v1.53, starts with it and the next character is neither a letter nor a digit.
- Anything else: the row `failed`, every row not sent `stopped`, the outage `needs_person`; since v1.53 the message's case
  gains an event of kind `resend` ("Shutter's resend of this message failed at HH:MM: new header N ended <status> (<the
  receiver's words>). Nothing more was sent; the outage waits for a person."), its state unchanged. Read again, a failed
  message is `refused` by rule 3, so it is never offered again.
- Not settled within the wait: the row `unknown` ("new header N had not settled in S s"), every row not sent `stopped`,
  the outage `needs_person`. (v1.55) The new header is read again by Engine Resend's poll for 7 days: once the engine shows
  it settled, the row ends as the rules above would have ended it in time (Completed: `completed` with "...; new header N
  Completed, read at HH:MM after the send's wait had run out." and the message's case resolved; the declared duplicate
  answer: `closed_as_present`; any other end: `failed` with an event of kind `resend` on its case), and the outage gains
  an event of kind `resend_settled`; its state is left as it is, and nothing is sent again. A header still Queued or
  Delivered, or one that can't be read, stays `unknown`. The card and its counts read each message by its last row.
- A patient the check holds is skipped (`stopped`, "not sent: <why>") and the run goes on; a copy resent by someone else
  stops it.

**Already handled by hand** (v1.53). `POST /outages/:id/acts` with `{ "act": "handled_by_hand", "headerId", "note",
"version"? }`, where the row is `offered` and the header's Row in `lists.offered` lists the act (a receiver whose
`duplicates.behaviour` is `unknown` or `files_twice`, or that declares none). 400 `bad_request` for a header not offered,
a row that doesn't list the act, or a note empty or over 1,000 characters; 409 `wrong_state` unless `offered`; 409
`version_changed`. Under the row's lock and version it writes a ledger row `handled_by_hand` (`RunId` "H" and the outage id,
`RecordedBy` the signed-in user, `EndedAt` now, `Words` "Handled by hand, recorded by <user> at HH:MM: <note>. Shutter sent
nothing for it."), moves the Row from `offered` to `closed` with `closure`, `closedBy` and `closedAt`, computes the digest
over what stays offered, writes an event `handled_by_hand`, marks the row to read again, and closes the message's own
cases by hand (`Shutter.Store.Case.CloseByHand`) with the same words. Nothing is sent: an approval given before it stops at
that message's recheck. Since it sends nothing, neither the stop nor shadow mode refuses it (18, v1.54): a person can
record a message entered by hand while recovery is stopped. The card's `do` line at such a receiver says to check the receiver before approving, and that
Already handled by hand sends nothing for a message.

## 18. Shadow mode and the recovery stop (v1.50)

Two different things. **Shadow mode** is a setting: the site profile's `recovery.mode`, `shadow` or `enabled`. Shutter investigates and records what it would propose, and sends no rehearsal, recovery write, blind-resend preview or outage resend (17.8, v1.54). **The stop** is a latch a person sets, named "Stop Shutter recovery": no new recovery call is admitted until a person clears it. It is kept in the data database, so a restart, a reinstall or a reseed leaves it as it is.

**The mode.**
- Only an explicit `enabled` enables. A profile with no `recovery`, with no `mode`, or with a value that isn't one of the two reads as shadow, and `PUT /site-profile` refuses such a value, naming it (400).
- So a new install with no demo starts in shadow, since the shipped `knowledge/site/profile.json` says nothing of it. **An upgrade from a version before this one also comes up in shadow**, unless its profile says otherwise: enabling is a decision, in the normal save of the profile (`Shutter_Configure`). No environment variable enables it.
- The demo seeds `enabled` explicitly, whenever the seed fills or follows the stored profile, so its behaviour is unchanged. So does a demo profile stored under the seed's marked sources, `" (demo)"`, `" (live hospital)"` or both (6.4, 4.4), which an upgrade from 1.1.0 finds with no `recovery`. A profile a person saved on the demo keeps what it says.
- Each change of the mode moves the generation on, like a clear.

**What it covers.** Every call of `Shutter.Operation.Ward` other than a read passes one admission (`Shutter.Util.RecoveryControl.Admit`), immediately before the POST:

| Call | Sender | While shadow or stopped |
| --- | --- | --- |
| Rehearsal | `CaseWorkflow.OnGateProposal` | Not sent. The workflow checks first, and the case is escalated |
| Recovery write | `CaseWorkflow.OnGateDispatch` | Refused at the connector, and the case blocks |
| Blind-resend preview | `POST /cases/{id}/preview-blind-resend` | 409, and refused at the connector if it gets that far |
| Outage resend (v1.54) | `POST /outages/:id/approvals`, then `Shutter.Operation.EngineResend` | The approval 409, nothing recorded; a run under way halts before its next message (17.8) |
| FHIR update (v1.63) | `Shutter.FHIR.Flow` (`OnGateProposal`), then `Shutter.Operation.FHIRExecute` | Not sent. The flow escalates before it asks for an approval (`ShadowObservation.Words`), and FHIR Out refuses with the admission's code if it gets that far (20.3) |
| Any other kind | | Refused always: `unknown_action` |

A FHIR update (v1.63) passes the same admission, `RecoveryControl.Admit`, in `Shutter.Operation.FHIRExecute`: after its fence row is open and before its first request to the receiver (its own read of the Encounter). The entry's switch, shadow mode and the stop are asked once more after that read, before the fence row goes to sent, and the permit is finished on every path (20.3).

The outage resend doesn't pass through `Shutter.Operation.Ward`: the engine sends the stored message itself. Its check is
the same control under the same lock (`HoldForResend`), held from the read until the engine has the message, and its
record is the outage's ledger (`Shutter.Store.ResendRecord`, 17.8) rather than a permit. "Already handled by hand" sends
nothing and stays allowed.

The refusal is `Outcome` `refused` with `ReasonCode` `recovery_shadow`, `recovery_stopped`, `plan_predates_control`, `plan_unbound`, `control_unavailable` (no lock within 5 s), `control_unreadable` or `unknown_action`. `POST /cases/{id}/approvals` answers 409 with that code to an approve, or `plan_predates_control` when the plan is at or below the floor, once its own state, digest and version checks have passed, so nothing goes on the record. Such a plan stays void, so the words say to reject it and reinvestigate: a case waiting for approval can't be reinvestigated until it is rejected. The incident approvals answer the same codes while shadow or stopped, and say only that it waits: an incident holds no plan row, and each item gathers fresh evidence and makes its plan when released. A reject still goes.

**What it does not cover.** The hospital's ordinary feed and its retries, other systems or people writing to a receiver, Shutter's own records, and reads: preflight, evidence and verification go on, so an earlier attempt's outcome can still be read back. A feed message passes only when it is purpose `normal` with a source header and no case, from an item whose class is `Shutter.Process.ADTToWard` or extends it; the purpose alone isn't enough (`not_original_feed`), and a site's own process that calls the connector directly must extend that class. This pass reads nothing of the control, so nothing that happens to it reaches the feed. A connector other than `Shutter.Operation.Ward` and, since v1.63, `Shutter.Operation.FHIRExecute` isn't covered: none ships.

**What it promises.** No recovery call is admitted after a stop commits, and no outage message is handed to the engine after it (17.8). `Stop` and `Admit` take one short lock, never held across a network call. A call admitted before the stop may still reach the receiver and may still complete; stopping doesn't cancel it. It is listed as outstanding, in the stop's event too.

**A record of every call.** Each admitted call has a `Shutter.Store.DispatchPermit`, committed before the POST, with the SHA-256 of the whole body, bed included. The sender holds a lock on it until the call ends.
- A call that gets no answer that settles it (`uncertain`, 1.3) has a permit of state `uncertain`. The case reads it back as before, and recovery isn't stopped.
- A permit still `admitted` whose lock has gone was cut off by a restart or a lost job. It becomes `uncertain`, never "not sent", at the next admission or read of the control, and that **latches the stop**, by `system`. If the message comes round again it is refused, so it is not retried.

**Clearing.** `POST /recovery-control/clear` needs `Shutter_Configure` and `Shutter_Approve`, `reason` and `expectedGeneration` (409 `stale_version` on a generation that moved, 409 `wrong_state` when not stopped). It enables nothing: the mode stays as the profile says. It releases nothing: the control's plan floor rises to the newest plan id at each stop, clear and mode change, and a write under a plan at or below it is refused (`plan_predates_control`), so the case needs fresh evidence and a new plan. Clearing records who saw the calls a restart cut off. They stay `uncertain`: nobody has shown they weren't applied.

A demo reset (`Runner.Reset`, demo only) clears a stop too, with the event `demo_reset`, since it starts the receivers afresh. A site has no such route.

**Routes.**
- `GET /recovery-control`: `{mode, generation, stopped, stoppedAt, stoppedBy, stopReason, outstanding, outstandingCount, readable, covers, doesNotCover}`. `covers` reads "Rehearsals, recovery writes, blind-resend previews and outage resends that Shutter itself starts; a resend under way halts before its next message." (v1.54). A control that can't be read answers `stopped` true and `readable` false.
- `POST /recovery-control/stop`: `{reason}`, required. A second stop changes nothing. The actor is the signed-in user; a name in the body is ignored.
- `GET /shadow-observations?from=&to=&receiver=` and `GET /shadow-observations.csv`: the report. `Shutter_Operate`.
- `Shutter.Store.RecoveryControlEvent` keeps every stop, clear and mode change, with who, why and what was outstanding.

**Email.** In shadow mode, `Escalation Mail` sends nothing and writes no file: the escalation is marked failed, saying why ("Not sent: shadow mode sends no email, ..."), its line on the case page reads Not sent (v1.55, the word the escalation dialog promises), and enabling recovery doesn't send it. `notifications.shadow_delivery: "enabled"` in the profile lets them go. A reminder for cases left open (6.4) follows the same rule: in shadow mode none is built or sent, the run logs that it was due, its cases count as not reminded, and the first run after enabling or after that setting sends what is due. A stop doesn't touch email.

**The report.** One row per case that reached Shutter in the period, with its latest observation (`Shutter.Store.ShadowObservation`, one per plan at the proposal gate). The denominator is **cases reaching Shutter**, not all failed deliveries: a failure that never became a case is not in it, and a case not yet investigated stays in it as unobserved. A resend proposal whose proposal gate passed is a **candidate for rehearsal**, and no more: neither a rehearsal nor a dispatch was tested. `recovery_calls_sent`, `rehearsal_performed`, `final_dispatch_tested` and `notification_deliveries` are counted from the permits and the escalations, not assumed from the mode. Patients appear as a reference local to this deployment, a hash keyed by a value the control row keeps and no route returns, since `deployment_id` is printed on every row, so a list of hospital numbers can't re-identify a row; no message text. Shutter keeps no list from a reference back to a patient, so a person who needs the patient behind a row keeps that link, within the run, from the row's `case_id`. Human review of a proposal isn't built, so the report says nothing about whether a proposal was right. **A report authorises nothing:** it enables nothing, releases no plan and closes no uncertain write.

## 19. The failure coverage census (v1.50)

An observer for a pilot's review: of a watched receiver's delivery failures in a window, which have a traceable Shutter case? It runs
on demand and is off unless the site turns it on. It never opens or closes a case, never resends, and changes nothing in the
watched namespace. It compares what the engine shows with what Shutter holds, so it says nothing about a message the engine
completed and the receiving application later lost, and a completed transport acknowledgement stays outside the failure count. It
is not a replacement for the index (8) or the production review (13), and it does not backfill: a failure it finds with no case
stays a line in its report.

**The profile.** `failure_census` in the site profile (6.4), absent in the shipped one: `{"enabled": false, "max_window_hours": 24,
"max_headers": 10000, "retention_days": 30, "settle_seconds": 120}`. An unknown setting or a value out of range is refused when the
profile is saved. `retention_days`: each run takes away runs older than this. `settle_seconds`: a failure younger than this with no
case may still be on its way through the forwarder, so it counts as unassessable.

**The scope.** A receiver onboarded from a namespace on this instance (11.1), or a profile entry naming its `namespace` and `item`:
the caller names the receiver and the window, never a namespace or SQL text. Shutter's own namespace is not a source. The read runs in
the **Failure Census** item (`Shutter.Operation.FailureCensus`), since a caller's role need not reach the watched namespace's database.

**What counts.** A delivery is an `Ens.MessageHeader` of type request whose target is the receiver's item, created in the window. A
failure is one whose status at the read is error, suspended, aborted or discarded, or completed with `IsError` set. Other statuses
are counted as `notFinished`. A failure whose session holds no HL7 message is `excluded`, since the intake (11) takes HL7 only.

**The link.** Each failure is keyed by source namespace, delivery header and target. The candidates are the cases of that namespace and
that receiver since the window opened, from the case rows and from `Shutter.Msg.ExternalIntake` with the `CaseStarted` in its session,
since a further failure of an open case's operation goes on that case (`Case.Open`) and the row keeps only the first origin.

| Quality | Code | When |
|---|---|---|
| `exact` | `origin_is_this_delivery` | the case's origin header is this delivery |
| `exact` | `only_delivery_in_session` | the origin is in this delivery's session, and the session sent the item one message (a resend of one body stays one) |
| `ambiguous` | `several_deliveries_in_session` | the origin is in the session, and the session sent the item several different messages: the candidates are named, none chosen |
| `none` | `no_case` | no candidate names this delivery or its session |

A control id plays no part. Several failures on one case are many-to-one: each is linked, and `distinctCases` counts the case once.
`FailureCensus.ResolvedDelivery` is where a resolver of the delivery header goes in for a forward that names some other header of
the session.

**Eligibility.** `in_scope`, `excluded` or `unknown`. `unknown` codes: `body_missing` (no case, and the delivery's body is gone),
`settling` (no case, and younger than `settle_seconds`), `case_origin_purged` (a case opened in the window whose origin header is gone:
its row names the case and the origin, with no delivery).

**Completeness.** `unknown` when the source cannot be read: a namespace that is gone or dismounted, or a query refused. Every total is
then null, never 0, with the reason in `sourceError`. `incomplete` for any of these in `reasons`: `header_cap_hit`, `case_cap_hit`,
`header_ids_missing` (ids are issued upwards, so a hole around the window is a purge or a delete), `window_older_than_kept_headers`,
`own_messages_purged` (Shutter's own store no longer reaches the window's start, so a further failure's trail may be gone),
`case_origin_purged`, `body_missing`, `settling`. `complete` otherwise. No percentage is given.

**Routes**, all `Shutter_Operate`; POST with `X-Requested-With: Shutter` and an optional `Idempotency-Key`.

- `GET /failure-census` -> `{enabled, statement, maxWindowHours, maxHeaders, scopes: [{receiver, namespace, item}], items: [the latest 50 reports, without rows]}`.
- `POST /failure-census` `{receiver, from?, to?}` (ISO UTC; `to` defaults to now, `from` to the longest window before it) -> 201 the report without rows, whatever it found; 409 `not_enabled`; 400 `bad_request` for a receiver not registered or a window refused (not whole times, backwards, over the limit, or ending more than a minute from now); 503 `no_service` and `not_queued`, 502 `no_answer`, 500 `census_failed`.
- `GET /failure-census/{id}` -> `{runId, receiver, namespace, item, window: {from, to}, cutoff, sourceRead: ok | unavailable, sourceError, completeness, complete, reasons, scanned, truncated, maxHeaders, configVersion, productVersion, requestedBy, startedAt, finishedAt, statement, totals: {deliveries, completed, notFinished, failures, eligible, exact, none, ambiguous, excluded, unassessable, missingIds, evidenceGaps, distinctCases}, items: [{sourceNamespace, deliveryHeaderId, target, sessionId, originHeaderId, timeCreated, sourceStatus, bodyClass, family, resendOf, caseIds, linkQuality, eligibility, explanation}]}`; 404 `not_found`. `eligible` is `exact` + `none` + `ambiguous`. `resendOf` is the header the engine records this one as resent from. A status is as it stood at `cutoff`.
- `GET /failure-census/{id}.csv` -> `text/csv`: `record_type,run_id,receiver,source_namespace,target,delivery_header_id,session_id,origin_header_id,time_created,source_status,body_class,message_family,resend_of,link_quality,case_ids,eligibility,explanation`. The first row is `run`, with the read's status under `source_status`, the completeness under `eligibility` and the reasons under `explanation`, so a file read alone says what it is worth; then one `item` row each. A cell a spreadsheet would run as a formula starts with an apostrophe.

No message content is copied: the rows hold ids, codes, the body's class and the HL7 structure's family (ADT, ORU).

## 20. The FHIR R4 receiver profile (v1.63)

A FHIR receiver (6.4: an entry whose `fhir` object passes the save's validation) is reached for recovery through its FHIR R4 API and no other way. Shutter makes one change there: on an existing Encounter that is in progress it completes the open ward-level `location` entry at the failed transfer's event time and appends an active entry for the target ward, with a marker tag naming the operation. The FHIR gate (policy `fhir-2026-11-14.1`) decides at the proposal and again at dispatch, and an unknown blocks. A write goes only on a person's approval of that one case, bound to the version read (its ETag), the exact body (its digest) and the Patient and Location versions; the dispatch gate reads them all again and compares them as strings. No dry run exists for this receiver, and the rehearsal row of every decision says so and says what stands in its place. At most one PUT is sent per approval, with `If-Match`; a second request for the same approval sends nothing. The verifier reads the history, the current record, the Patient and every bound Location, and the committed version by id when the receiver's answer named it, and only 'verified' and 'verified, a later change followed' resolve the case. A FHIR case is planned by `Shutter.FHIR.Flow` and never by an agent (9), never joins an incident, and is released only by a person's approval of that case.

**What is read.** `FHIR Receiver` (`Shutter.Operation.FHIRReceiver`) only reads. Every request is a GET with `Accept: application/fhir+json` that follows no redirect, and each answer is carried as a part with the status it can be trusted with (`Shutter.FHIR.Trust`: a gateway's page behind a 200, a plain 404, a body of another kind or a media type other than FHIR JSON reads as no answer). A request names a case and a purpose, not a server: the path in front of every request is the `base` of the case's own receiver, so a request can borrow no other entry's settings. By purpose, `evidence` reads the CapabilityStatement, the search by visit number under the entry's identifier system, the Encounter, its Patient, every Location of the map and the Encounter's history; `dispatch` (the read just before the write) the same without the search, for the Encounter and the Patient and Locations the binding names; `verify` the Encounter, the Patient, the bound Locations and the history, and the version the answer to the update named, by id. Of a Patient and a Location only what the checks read is kept: no name, birth date, address or telecom. One request reads for at most 45 seconds, and a body of more than a million characters is not trusted. The case's evidence keeps the projection of these reads (`Shutter.FHIR.Reader`): the summary's `fhir` view holds identifiers, statuses, references and version ids and never a body, the snapshot item `fhir` holds the Encounter's body digest, ETag and version id, and the Encounter as read is kept beside the snapshot (`Shutter.Store.FHIRSealedRead`) for the gate and the binding to build from. The snapshot's material digest includes the view's ETags, so the same evidence read twice gives one digest and a changed version gives another.

### 20.1 The FHIR gate's rows

`Shutter.Operation.FHIRGate` (item `FHIR Gate`, request `Shutter.Msg.FHIRGateRequest` with stage `proposal` or `dispatch`) stands beside `Shutter.Operation.Gate` and is not a subclass of it. `Facts` makes every read and `Decide` gives the rows from those facts alone. The decision is stored as any gate decision, its outcome the worst row. A read the gate cannot make (no case, plan or snapshot, or a failed read before the write) answers an error with no decision, which the flow treats as an item's failure (stops 12 and 13 below) and not as a verdict.

**Rows, in order.** "w" = only for a plan that writes (`plan.IsWrite()`); otherwise the row is `pass NOT_APPLICABLE`. Codes without the `FHIR_` prefix are the main gate's, with its meaning.

| Check | Pass | Block (b) or unknown (u) |
| --- | --- | --- |
| `identity` | `FHIR_IDENTITY_MATCHES` | b `FHIR_ENCOUNTER_NOT_FOUND` (the evidence has no `fhir` view, the words saying that the message names no visit number when the case has none; or the search found no match; or the Encounter read was a 404); u `FHIR_RECEIVER_UNREADABLE` (the search or the Encounter read has no status or one other than 200 and 404); b `FHIR_ENCOUNTER_AMBIGUOUS` (several matches; u when the search came in pages); b `FHIR_IDENTIFIER_UNMAPPED` (the case's patient assigning authority is not `hl7_authority`, or `encounter.identifier_ok` is false: the Encounter does not carry the visit number under the mapped system); b `FHIR_SUBJECT_UNRESOLVED` (the subject is not a literal `Patient/{id}`; u when that Patient could not be read, or the Patient read is not the subject); b `FHIR_PATIENT_MISMATCH` (the Patient does not carry the case's patient id); b `FHIR_PATIENT_LINKED` (a `link`, or `active` false) |
| `conformance` | `PARSED` | as the main gate's: `UNMAPPABLE`, `SCHEMA_UNKNOWN`, `PARSE_FAILED` |
| `intent` | `EXACT_OPERATION` (detail "The plan makes the one change the failed message asked for; the HL7 message is not sent again"), `NO_WRITE` | as the main gate's, without its two lines about a receiver the profile does not describe or does not model: `MERGE_WITHHELD`, `CANCEL_UNSUPPORTED`, `UNKNOWN_DISPOSITION`, `DIFFERENT_OPERATION`, `PAYLOAD_CHANGED`; and for a write b `FHIR_EVENT_UNSUPPORTED` (`case.Event` is not `transfer`), b `FHIR_FAILURE_KIND_UNSUPPORTED` (`case.FailureKind` is neither `delivery_failed` nor `uncertain_outcome`) |
| `enablement` w | `FHIR_RECOVERY_ENABLED` | b `FHIR_RECOVERY_DISABLED` (`Profile.Enabled` is false) |
| `representation` w | `FHIR_REPRESENTATION_WHOLE` | the first that applies of b `FHIR_REPRESENTATION_PARTIAL` (marked SUBSETTED), `FHIR_MODIFIER_EXTENSION` (a `modifierExtension` or `implicitRules`), `FHIR_NARRATIVE_PRESENT`, `FHIR_RESTRICTED` (`meta.security` present), `FHIR_NO_ETAG` (`etag_usable` false: no ETag, or one that does not name the version read) |
| `state_transition` w | `TRANSITION_ALLOWED` | b `FHIR_STATUS_NOT_IN_PROGRESS`, `FHIR_ALREADY_THERE` (an open entry is already on the target ward) |
| `ordering` w, several rows | `ENGINE_SETTLED`, `NO_FURTHER_MOVEMENT`, `FURTHER_MOVEMENT_RELEASED`, `NO_LATER_EVENT`, `FHIR_ORDER_HOLDS` | the engine row (below); the further-message rows as the main gate gives them, b `PATIENT_UNREADABLE`, `FURTHER_MOVEMENT`, `FURTHER_NOT_READ`, and u `FURTHER_MOVEMENT_NEW` at dispatch only; b `NEWER_MESSAGE_PENDING` (its words promise no wait); b `EVENT_TIME_IMPLAUSIBLE`, `SUPERSEDED_BY_LATER_EVENT` (the later-event reads of the main gate, copied); then the receiver's own record: u `FHIR_TIME_UNREADABLE` (the event time, or a `location` entry's start, that `Shutter.Util.Time.FromFHIR` cannot read), b `FHIR_LATER_MOVE_AT_RECEIVER` (an entry whose start, as `FromFHIR` seconds, is at or after the event time's), `FHIR_PRIOR_LOCATION_DIFFERS` (b when there is not exactly one open entry or its ward is not `prior_ward`; u when `prior_ward` is ""); `FHIR_ORDER_HOLDS` when none of those three applied |
| `mapping` w | `FHIR_LOCATIONS_CHECKED` | b `FHIR_LOCATION_UNMAPPED` (the prior or the target ward is not in the map); u `FHIR_LOCATION_UNREADABLE` (a mapped Location's read is not 200); b `FHIR_LOCATION_MISMATCH` (a mapped Location is not `active`, or `identifier_ok` is false) |
| `plan_shape` w | `FHIR_PLAN_BOUNDED` | `Shutter.FHIR.Proposal.Prepare`'s code, b `FHIR_BED_MOVE_UNSUPPORTED`, `FHIR_LOCATION_UNMAPPED`, `FHIR_SHAPE_UNSUPPORTED`, `FHIR_DIFF_OUT_OF_BOUNDS` (a code another row already gave is not repeated); u `FHIR_RECEIVER_UNREADABLE` (the Encounter as read is not on file with the evidence); at dispatch b `FHIR_BODY_CHANGED` when the body built from the read just before the write has not the binding's digest |
| `concurrency` w | `NOT_YET_REQUIRED` at proposal; `FHIR_VERSION_MATCHES` | at dispatch, strings compared as strings: b `FHIR_NO_BINDING`; u `FHIR_RECEIVER_UNREADABLE` (the Encounter, the Patient or a bound Location was not read, or the Patient or a Location came with no ETag, which is no version); b `FHIR_RECEIVER_CHANGED` (the Encounter's ETag), `FHIR_PATIENT_CHANGED`, `FHIR_LOCATION_CHANGED` (any bound Location's ETag) |
| `earlier_write` w | `FHIR_NO_EARLIER_WRITE` | at both stages u `FHIR_EARLIER_WRITE_UNRESOLVED` when an update of this case that was sent, conditional on this same ETag, has a recorded outcome that is none, `uncertain` or `applied`: it may yet land, or its answer was wrong about the version. Not refreshable |
| `capability` w | `FHIR_CAPABLE` | u `FHIR_CAPABILITIES_UNREADABLE`; b `FHIR_NO_HISTORY` (`interactions` lack `read`, `vread`, `update` or `history-instance`, or `read_history` is false); b `FHIR_VERSIONING_UNPROVEN` (`versioning` is not `versioned-update`; or no `FHIRProof` row for the receiver; or `Matches(software.name, software.version)` is false; or any of its three measurements is false) |
| `history` w | `FHIR_HISTORY_READ` | u `FHIR_HISTORY_UNAVAILABLE` (not 200, or a `next` link); b `FHIR_HISTORY_HEAD_DIFFERS` (the newest version is not the version read); b `FHIR_ALREADY_WRITTEN` (`sent_marker_version` is not "": a version carries the marker of an update this case sent) |
| `authorization` | `NOT_YET_REQUIRED` at proposal; `APPROVAL_VALID` | at dispatch: b `NO_APPROVAL`; b `FHIR_APPROVAL_NOT_PERSONAL` (`approval.Approver = "policy"`, or `approval.IncidentPlanDigest` is not "": the named line that refuses automatic, tier and incident release); b `APPROVAL_<REASON>` from `approval.InvalidReason(plan, case.CurrentSnapshot, policyVersion, "", "")`; b `FHIR_NO_BINDING` (the binding's `ApprovalId` is not this approval) |
| `evidence` | `FRESH` | u `STALE_EVIDENCE`: at proposal `snapshot.IsFresh()` is false; at dispatch the read's `observed_at` is older than 120 seconds, or missing |
| `catalogue` | as the main gate's | exactly the main gate's rows, with its `OutcomeConsistency` copied |
| `rehearsal` | `FHIR_NO_DRY_RUN_SUBSTITUTED` on every decision, at both stages, written or not | none. For a write the detail is "No dry run exists for this receiver. Substituted: a complete versioned read, a bounded change, If-Match on the version read, this case's own approval by a person, and a search of the returned history for the marked version, read back by id when the answer named it."; otherwise "No dry run exists for this receiver. This plan sends nothing." |

When `identity` read no Encounter, the rows that need one (`representation`, `state_transition`, the receiver rows of `ordering`, `plan_shape` and `history`) are each u with the code `identity` gave, and say so.

**The engine row.** The engine's reads are `Shutter.Util.EngineCheck.Read`. `facts("engine")` is "" (the case has no source header): u `FHIR_ENGINE_NOT_IN_SCOPE` ("no source header to read the engine by"; not refreshable, since it can never clear). Else its `scope` of `"no"` gives u `FHIR_ENGINE_NOT_IN_SCOPE`; `"base"` gives u `FHIR_ENGINE_SUBCLASS_UNPROVEN`; otherwise the row is `##class(Shutter.Util.EngineCheck).Judge(<those facts>)` (`ENGINE_STILL_TRYING`, `ENGINE_DELIVERED`, `RECEIVER_MAY_HOLD_IT`, `ENGINE_UNREADABLE`, `ENGINE_SETTLED`), with two refusals laid over a pass, because the FHIR write is a second route to a system the engine can still reach: any header of custody `delivered` gives b `FHIR_ENGINE_DELIVERED` (the main gate passes it on the acknowledgement route), and any header whose `status` is `Suspended` gives b `FHIR_ENGINE_HOLDS_SUSPENDED` (the main gate reads Suspended as settled, and a suspended message can be resubmitted after the FHIR write). The gate never calls `EngineCheck.Settle`: a case blocked because the engine is still trying, or because a newer message is pending, does not wait, and its words (`Shutter.Store.BlockReason`) say to reinvestigate once the engine has finished or the message has been delivered.

**Unknowns a fresh read can answer.** `STALE_EVIDENCE`, `FHIR_RECEIVER_UNREADABLE`, `FHIR_CAPABILITIES_UNREADABLE`, `FHIR_HISTORY_UNAVAILABLE`, `FHIR_LOCATION_UNREADABLE` and `ENGINE_UNREADABLE`. When every row that did not pass is one of these, the flow waits 10, 20 and 40 s and reads again, up to three times (`MaxRefreshes`): at the proposal it collects the evidence again and plans afresh, at dispatch it repeats the read before the write. Any other row that did not pass ends the stage (stops 3 and 8).

### 20.2 The stops of the flow

**Every stop of the flow, with its exact text.** The case's reason is read from the newest stopping event's text (`Shutter.API.Dispatch.ReasonFromEvent`, which the escalation draft also reads): a trailing " (FHIR_...)" is the reason, except in a rejection's words and after an escalated plan's " (the gate noted: ...)". So a stop that no failing gate row explains ends " (CODE)", and a stop that a gate row explains carries no code in its text. Words taken into a text from somewhere else (an error, a diagnostic) never carry a code of the flow's own: "(FHIR_" in them is written "(fhir_". "Revoke" = `approval.Revoke("system: <why>")` on the approval of `p.ApprovalId` when there is one.

| # | When | Revoke | State | Headline | Transition text |
| --- | --- | --- | --- | --- | --- |
| 1 | `Install.Problem()` is not "" (at the proposal, and at the dispatch) | at the dispatch, when an approval stands ("the FHIR items are missing or disagree"); none at the proposal | `blocked` | "Blocked: the FHIR items are missing or disagree" | at the proposal "The production cannot reach this FHIR receiver: <problem>. Nothing was read or sent (FHIR_ITEMS_MISSING)"; at the dispatch "The production cannot reach this FHIR receiver: <problem>. The approval is void and nothing was sent (FHIR_ITEMS_MISSING)" |
| 2 | an `escalate` or `more_evidence` plan, after the proposal gate | | `escalated` | the headline the plan was adopted with | "The plan asks for a person: <plan.Summary>", then " (the gate noted: <summary>)" when the gate did not pass; the summary carries "(FHIR_PLAN_NEEDS_PERSON)" |
| 3 | the proposal gate did not pass (after the refreshes of 20.1) | | `blocked` | "Blocked by the FHIR gate: <result.Summary>" | "The FHIR gate did not pass the plan; a person must decide" |
| 4 | a pass on a plan that writes nothing | | `escalated` | "Escalated: over FHIR nothing closes by itself" | "Over FHIR Shutter closes no case without a person or a verified update; a person decides (FHIR_PLAN_NEEDS_PERSON)" |
| 5 | shadow mode or the stop | | `escalated` | `ShadowObservation.Words` | the same words |
| 6 | the update could not be sealed for approval: `SealBinding` failed, the approval could not be tied to the seal, or the seal is missing when the read before the write or the dispatch needs it | when an approval stands | `blocked` | "Blocked: the update could not be sealed for approval" | "The update could not be sealed for approval: <reason> (<Prepare's code, or FHIR_NO_BINDING>)" |
| 7 | the read before the write failed after its retries | yes | `blocked` | "Blocked at dispatch: the receiver could not be read" | "The receiver could not be read just before the write, in <n> tries. The approval is void and nothing was sent (FHIR_RECEIVER_UNREADABLE)" |
| 8 | the dispatch gate did not pass (after the refreshes of 20.1) | yes | `blocked` | "Blocked at dispatch: <result.Summary>" | "The FHIR gate did not pass the plan at dispatch. The approval is void; a reinvestigation reads fresh evidence and asks again" |
| 9 | the write answered `version_conflict` | yes | `blocked` | "Blocked: the Encounter changed before the update" | "The receiver refused the update: the Encounter changed after it was read (HTTP <n>). The approval is void and nothing is sent again without fresh evidence and a new approval (FHIR_WRITE_CONFLICT)" |
| 10 | the write answered `refused` or `error`, or the call to FHIR Out failed with the fence not `sent` | yes | `blocked` | "Blocked: the update was not applied" | "The update was not applied: <reason code, or the outcome>, HTTP <n> or 'no HTTP answer' (FHIR_WRITE_REFUSED)" |
| 11 | a verification that does not resolve | 20.4 | `escalated` | 20.4 | the Judge's sentence, then " (<code of 20.4>)" |
| 12 | an error from a FHIR item other than FHIR Out, or inside the flow, before anything was sent (fence absent or `unsent`) | yes | `blocked` | "Blocked: a FHIR item failed" | "A FHIR item answered with an error before anything was sent: <text> (FHIR_ITEM_ERROR)" |
| 13 | an error from the verifier, from any FHIR item other than FHIR Out, or inside the flow, with the fence `sent` | yes | `escalated` | "Escalated: the update's outcome is unknown" | "A FHIR item failed after the update was sent: <text>. Whether the receiver applied it is unknown; a person checks at the receiver (FHIR_WRITE_OUTCOME_UNKNOWN)" |

A failed call to FHIR Out with the fence `sent` is no stop: the flow records an `uncertain` attempt (reason `fhir_item_error`) and goes to the verification, like any answer that was lost. Rejection, a missing or another plan digest, the approval timeout, abandon and close are the workflow's own handlers and words, unchanged.

### 20.3 The write

The binding, the fence row and the proof are stores of their own. `Shutter.Store.FHIRBinding` is sealed when the proposal gate passes a plan that writes (one per plan) and tied to the approval when a person gives it: the Encounter id and ETag read, the Patient and every mapped Location with their ETags, the Encounter as read and the approved body with its digest, the operation id, the marker system, the digest of the `fhir` block, and the profile and policy versions. The body is the Encounter as read with one change (`Shutter.FHIR.Plan.Build`, through `Shutter.FHIR.Proposal.Prepare`): the open `location` entry gets `status` `completed` and `period.end` the event time, an entry `{"location": {"reference": <target>}, "status": "active", "period": {"start": <event time>}}` is appended, and `meta.tag` gains `{"system": <marker.system>, "code": <operation id>}`, the operation id being the first 32 hex characters of the SHA-256 of `<case id>|<plan digest>|<ETag read>`. `Plan.Diff` refuses any other changed path (`FHIR_DIFF_OUT_OF_BOUNDS`), and a message that names a bed is never written (`FHIR_BED_MOVE_UNSUPPORTED`). `Shutter.Store.FHIRAttempt` is the fence: one row per approval (unique), `unsent` until the update is about to leave, then `sent`, with the answer recorded on it. `Shutter.Store.FHIRProof` holds a receiver's conformance run (12).

**`Shutter.Operation.FHIRExecute`** (item `FHIR Out`): `Ens.BusinessOperation` on `EnsLib.HTTP.OutboundAdapter`, `Method OnWrite(request As Shutter.Msg.FHIRWrite, Output response As Shutter.Msg.FHIRWriteResult) As %Status`, never an error status for a refusal. `FHIRWrite` carries `CaseId`, `PlanId`, `ApprovalId`, `BindingId` and `DecisionId`; `FHIRWriteResult` carries `Outcome`, `HttpStatus`, `Sent`, `ResponseEtag`, `ResponseLocation`, `ReasonCode`, `Diagnostics` and `Error`. It trusts nothing of the gate's moment: a request can wait in its queue across a disabled item or a production stop. In order:

1. Open the case, the binding (`request.BindingId`), the approval, the plan and the decision (`request.DecisionId`). Refuse (`Outcome = "refused"`, `Sent = 0`, `Error` beginning "Not sent:") with `ReasonCode`:
   - `fhir_binding_missing`: no such case or binding; the binding is not this case's; its `ApprovalId` is not `request.ApprovalId`; the approval is not this case's; its `PlanId` is not the case's current plan's id (or `request.PlanId` names another);
   - then, if the fence row of this binding is already `sent`, answer it as step 3 does, before the checks that follow;
   - `fhir_recovery_disabled`: `ReceiverKind(case.Receiver)` is not `fhir_r4`, or `Profile.Enabled` is false;
   - `fhir_endpoint_differs`: the receiver's `fhir` block no longer has the `MappingDigest` the approval was given against (its base, map, marker and identifier systems);
   - `fhir_approval_not_personal` (`approval.Approver = "policy"` or `approval.IncidentPlanDigest` is not ""), asked before the next so that a policy's or an incident's approval is named as what it is;
   - `fhir_approval_void` (`approval.InvalidReason(plan, case.CurrentSnapshot, policyVersion, "", "")` is not "");
   - `fhir_dispatch_stale` (no such decision, or it is not this case's and plan's `dispatch` decision with outcome `pass`, or its `At` is more than 120 seconds old);
   - `fhir_body_changed` (`Plan.BodyDigest(binding.ApprovedBody)` is not `binding.ApprovedBodyDigest`).
2. The two last lines of `Shutter.Operation.Ward`'s write, copied and read at the moment of the write: `newer_message_pending`, `further_movement`.
3. The fence: `FHIRAttempt.Open(case, binding, .a, .created)`. An existing row in state `sent` sends nothing and is answered as what it is, a write that may have landed: with `AnsweredAt` empty, `Outcome = "uncertain"`, `Sent = 1`, `HttpStatus = 0`; with an answer, the recorded outcome, status, ETag, Location and diagnostics again; `ReasonCode = "fhir_already_sent"` either way. Never `refused`.
4. `Shutter.Util.RecoveryControl.Admit("recovery", case.CaseId, case.Receiver, plan.OperationKey, "sha256:" _ binding.ApprovedBodyDigest, .permit, .code, .text)`; not admitted: refuse with `ReasonCode = code`, `Error = text`.
5. Its own read, through its own adapter, because the checks read through `FHIR Receiver` and the write leaves through this item, each with its own server settings: `GET <base>/Encounter/<id>`, bounded to 30 seconds and a million characters, no redirect, judged by `Shutter.FHIR.Trust.Part`. Refuse (`Sent = 0`, `fhir_endpoint_differs`) unless the answer is a trusted 200 whose ETag equals `binding.ExpectedEtag` byte for byte and whose body has the `Plan.BodyDigest` of `binding.BaseBody`. On the main route the item that writes is the item that read; this step keeps that. Then the entry's switch (`fhir_recovery_disabled`) and `RecoveryControl.Refusal` (shadow mode or the stop; its code) are asked once more, since the read can take a while.
6. `a.MarkSent()` (a synchronous commit, so that the row reads `sent` after a crash too); false: if the row is not `sent` the item fails (`Outcome = "error"`, `Sent = 0`, reason `fhir_item_error`), otherwise answer as step 3.
7. One request: `PUT <base>/Encounter/<id>` with `If-Match: <binding.ExpectedEtag>` byte for byte, `Content-Type: application/fhir+json`, `Accept: application/fhir+json`, `Prefer: return=minimal`, no redirect, the body `$ZCONVERT(binding.ApprovedBody, "O", "UTF8")`, through `..Adapter.SendFormDataArray(.resp, "PUT", http, "", "", path)`, with `http.ReadRawMode = 1` and `http.WriteRawMode = 1` (so the bytes are not translated a second time), then `Set ..Retry = 0`. The answer goes into a bounded stream (60 seconds, three bytes for each of a million characters): an answer cut short is still an answer to an update that left, so its status and headers stand, and it is never read as applied.
8. Classify, `a.Answer(...)` (an ETag longer than 200 characters or a Location longer than 500 is recorded as empty, since a cut one would read as another version), then `RecoveryControl.Finish(permit, adapter)` where `adapter` is an unsaved `Shutter.Msg.WardResult` carrying only `Outcome` and `HttpStatus`. Every path after step 4 reaches `Finish`: a permit left `admitted` latches the stop for the whole deployment (18).

Something that fails inside the item is answered by the fence row: `sent` is the step 3 answer with reason `fhir_item_error` (and the row answered `uncertain` if it was marked and had no answer), anything else `Outcome = "error"`, `Sent = 0`, reason `fhir_item_error`.

**The classifier**, `ClassMethod Classify(sc As %Status, status As %Integer, etag As %String, location As %String, contentType As %String, body As %String, encounterId As %String, Output reason As %String, Output diagnostics As %String) As %String`. The default is `uncertain`: the main connector's default for an answer nobody named is `refused`, which here would say "not applied" of a write that may have landed.

| Answer | Outcome |
| --- | --- |
| no response and the error says the connection never opened (status code 6059, or the message says refused, unable to connect, connect failed, no route or unable to open the socket) | `error` |
| no response otherwise (a timeout, a dropped connection) | `uncertain` |
| 200 with an ETag that names a version, and a body that is empty or a FHIR JSON Encounter with this id whose `meta.versionId` is the ETag's version, and a `Location` that is absent or ends `_history/<that version>` | `applied` |
| any other 200 (no ETag, a page, an OperationOutcome) | `uncertain` |
| 201 with an ETag that names a version | `applied`, reason `update_created` (the Judge fails it) |
| 201 without one | `uncertain`, reason `update_created` |
| any other 2xx (202, 204), any 3xx | `uncertain` |
| 412, 409 | `version_conflict` |
| 405 | `refused`, reason `invalid_if_match` when the body is an OperationOutcome |
| 400, 404, 410, 422 with a FHIR JSON OperationOutcome | `refused`, the first issue's `diagnostics` to 300 characters |
| 404 without one | `uncertain`, reason `credentials_or_proxy` |
| 401, 403 | `refused`, reason `credentials` |
| any other 4xx | `refused` |
| any 5xx, and any answer no row names | `uncertain` |

Nothing retries. The content type of a 200 is never read (IRIS answers an empty `text/html`).

### 20.4 The verifier

**The settle schedule** is the verifier's own: a result whose `detail.retry` is true raises `Refreshes` and arms `fhir:verify:retry` after `Shutter.Operation.FHIRVerify.RetryWait(p.Refreshes + 1)` seconds, read from `Parameter RETRYWAITS = "10,20,40"`, whatever Case Workflow's `MaxRefreshes` is; so the walks are at about 0, 10, 30 and 70 s after the update was sent (`SETTLEFINALSECONDS`, 70, is the sum of the waits, where the Judge's settle window ends and a read is final); `Refreshes` was set to 0 when the dispatch gate passed. A `retry` after the schedule's last wait is final: the result stands as it is, so an `unknown` ends as the final unknown below and a `committed_review` as its own row says, each with its code in the event's text; the stored verification of an `unknown` walk that asked for a retry keeps no code. `MaxRefreshes` bounds the evidence refreshes and the read before the write (20.1), not the verification.

**The Location rule.** The verification holds every mapped Location to the gate's rule (20.1, `mapping`): `active`, and carrying the identifier the site profile recorded, that value and no other under its system (`Judge.LocationsProblem`, `HoldsIdentifier`; the binding stores each Location's `{system, value}`). A Location read that fails it is `committed_review` with `detail.reason` `location_changed` and `detail.retry` false, and is not read again. A Location that could not be read, or whose answer is not the bound Location, keeps `detail.retry` true inside the settle window and is `location_changed` once the window has ended, as the Patient's read is `patient_changed`.

**The Judge's six outcomes.**

| Judge | `Verification.Outcome` | The flow | Case ends | Code (in `detail.case_code` and the event's text) |
| --- | --- | --- | --- | --- |
| `verified` | `verified` | `case.Outcome` = the sentence; `resolved` with the sentence as it is | resolved | none |
| `verified_continued` | `verified` | the same | resolved | none |
| `committed_review` | `unresolved` | the approval stands; `escalated`, headline "Escalated: the update is present, the current record needs review". When `detail.retry` is true (the current record, the Patient or a bound Location could not be read inside the settle window, or the history did not yet show the current version) it is read again first | escalated | `FHIR_COMMITTED_NEEDS_REVIEW` |
| `unknown`, retry left | `unresolved` | the retry alarm | verifying | none |
| `unknown`, final | `unresolved` | the approval revoked ("system: the update's outcome is unknown, and its one write is spent"); `escalated`, headline "Escalated: the update's outcome is unknown" | escalated | `FHIR_WRITE_OUTCOME_UNKNOWN` |
| `not_found` | `not_committed` | the approval revoked; `escalated`, headline "Escalated: the update is not in the history read"; nothing automatic follows | escalated | `FHIR_WRITE_NOT_FOUND` |
| `failed` | `failed` | the approval revoked; `escalated`, headline "Escalated: the receiver's record contradicts the update"; nothing automatic follows | escalated | `FHIR_WRITE_CONTRADICTED` |

The case's `Outcome` is the Judge's sentence on every final result. Every stop's transition text is the Judge's sentence followed by " (<code>)" (stop 11 of 20.2). `Judge.Words` is not edited. The Judge's own `case_code` (the ADT words `WRITE_NOT_COMMITTED`, `WRITE_OUTCOME_UNKNOWN`) is replaced in the stored detail by the FHIR code, so nothing keyed on the ADT codes sees a FHIR case. A reinvestigation after an unknown or not-found outcome meets the gate's `earlier_write` row (20.1): while the Encounter is still at the version the earlier update was conditional on, nothing more is sent, which keeps the Judge's own promise ("Shutter will not repeat it until its committed history can be established").

### 20.5 Never claimed

That `If-Match` or an approval makes the write idempotent; that a verified version proves where the patient is or that any downstream saw the change; that an AuditEvent, a Provenance, a 200, a newer ETag or `meta.lastUpdated` is a receipt; that `$validate` or any pre-check is a dry run; that version ids are numbers, increase by one or can be ordered; "conditional update" for the `If-Match` write, "FHIR support", "idempotent"; that the proof holds on any server but the one named; that the test server's run shows any server's behaviour; that the ADT path changed, or that leaving `Gate.cls` unedited means no change or risk to it; that no `next` link proves an intact history, or that "the whole history" was read; that adjacent history entries prove adjacent commits; that the Patient and Location reads are an atomic precondition; that a Location ETag prevents another Encounter taking a bed; that different ETags alone prove one version later than another; that an ignored normalisation path means nothing clinically relevant changed; that a settled engine proves the receiver holds no queued work, or that nobody will resend the HL7 message later; that the marker proves who wrote; that a surviving entry proves the move was not corrected; that a build string proves the endpoint passed Shutter's checks; that a fence row or a permit alone guarantees one PUT; that the receiver will refuse a changed version (it did when measured); that a repository update proves the ward application accepted the move; that Shutter's FHIR credentials can change only Encounters; that the board reviewed a FHIR plan; that any FHIR R4 server is supported; that a branch is the released application.

## Changes

- v1.65, 14 Nov 2026 (the FHIR review's fixes): 20.2: stop 1 is split by stage: at the proposal it is as it was ("Nothing
  was read or sent", no approval to revoke), and at the dispatch it revokes the approval and says "The approval is void and
  nothing was sent". 20.4: the settle schedule is the verifier's own (10, 20 and 40 s, `RETRYWAITS`), whatever Case
  Workflow's `MaxRefreshes` is, and a result still unsettled after its last wait ends as its own row says; the verification
  holds every mapped Location to the gate's rule (`active`, and that identifier and no other under its system), and a
  Location that fails it is `committed_review` with `location_changed` and is not read again. 6.4: a FHIR receiver is an
  entry whose `fhir` object passes what a save asks of it, the one-receiver rule included (`Profile.IsReceiver`);
  `ReceiverKind` and `Block` answer by that rule alone, and an entry whose key does not pass reads as its other keys make it.
  4, 5, 6.5, 12, 20: the places that said an entry "carries" or "has" a `fhir` object say a FHIR receiver, and the Doctor
  lists a receiver by the same rule. 4: the SQL test run answers `budget_busy` as well as `budget_exhausted`. 4.5: a P2
  start sent again with its `Idempotency-Key` is answered from the key before its refusals. No route, no OpenAPI path and
  no schema changed.

- v1.64, 14 Nov 2026 (scenario S35, a FHIR R4 ward system on the demo): 4: the step route `fhir_ward`, which plays a transfer
  through the demo hospital's FHIR ward feed (`FHIR Ward In`, `FHIR Ward Out`); the reset of the test FHIR server, answered under
  `receivers["FHIR Ward Out"]`, with the approvals of open FHIR cases revoked and the updates sent without an answer marked
  uncertain; the settings `fhirWardIn` and `fhirWardArchive`. 4.5: the scenarios number 37 with S35. 11: the hospital's
  `Ens.Alert` item lists the ward feed's connector among its `Receivers`. 12: the demo install's FHIR entry, items and
  in-process proof. No route, no OpenAPI path and no schema changed.

- v1.63, 14 Nov 2026 (the FHIR R4 receiver profile): section 20, one ward move on an existing, in-progress Encounter at
  InterSystems IRIS for Health's FHIR R4 server, off until a site's receiver entry carries a `fhir` object that turns it on
  (6.4); its own gate (`Shutter.Operation.FHIRGate`, policy `fhir-2026-11-14.1`), at most one person-approved update with
  `If-Match` per approval, no dry run and said so on every decision, verified from the receiver's history. 5: a FHIR
  case's route `kind`, and no numeric `expectedVersion`. 5.1: the FHIR attempt, its receipt and the verdict mapping. 6.4:
  the `fhir` entry, its validation and what else the profile reads from it. 6.5: a FHIR case is not judged here. 9: no
  agent plans or reviews a FHIR plan. 12: the four FHIR items placed by a call, the test FHIR server on a demo install, the
  uninstall's additions. 18: the same admission before a FHIR write, and FHIR Out as a second connector it covers. No
  route and no OpenAPI path changed; the receiver schema documents the `fhir` object and an attempt's FHIR receipt.

- v1.62, 14 Nov 2026 (the pathology paths on the demo): section 4.5, P1 and P2 on the demo hospital's results route, with
  the runner's three steps, P2's refusals, the reset's `lab` and `GET /scenarios`'s `pathology`. Whether the stand-in runs
  is read from the running production, a reset through the API (whose caller may not update the hospital's production)
  answers `not switched` and changes nothing, the stand-in listens on loopback only, and a path's wait reads only its own
  run's cases. No outage contract changed.

- v1.61, 14 Nov 2026 (OpenAI as a second provider the install configures): the install and the production's start
  read `OPENAI_API_KEY` and `SHUTTER_PROVIDER` beside `ANTHROPIC_API_KEY` and `SHUTTER_MODEL`
  (`Shutter.Setup.EnvironmentProvider`, `ProviderChoice`): the provider named, else the one whose key is set, Anthropic
  when both are; a named provider with no key, or an unknown name, configures nothing and is said, never replaced by the
  other key. `ConfigureProvider` takes the provider as a third argument (the two-argument call stays Anthropic's),
  keeps each provider's key in a wallet secret of its own (`Shutter.Anthropic`, `Shutter.OpenAI`), writes
  `AI.LLM.Shutter` with that provider's `model_provider`, removes the other provider's secret, and refuses a model that
  is plainly the other provider's. The record names its provider (`modelProvider`; none means Anthropic), so
  `ProviderNeedsRewrite`, the Doctor's `wallet_secret` and `ClearProvider` follow whichever was configured. The status
  line is `ok: AI.LLM.Shutter, <provider>, model <model>` (it named no provider before). No prompt, agent, tool or gate
  changed, and no evaluation has run on OpenAI through the install yet (12;
  `tests/unit/Shutter/Test/Provider.cls`).

- v1.60, 13 Nov 2026 (the Cases list hides the resolved cases only): `GET /cases` takes `resolved=0`, which leaves out
  the cases whose state is `resolved` and no other, in the query itself (`Shutter.API.Dispatch.CasesWhere`), so `total`
  and the pages count the same rows; any other value filters nothing, and it combines with `state`, `scenario` and
  `open` with AND (5; `tests/unit/Shutter/Test/CasesOpen.cls`). `open=1` keeps its v1.59 meaning. The Cases page's switch
  is now **Hide resolved**: it sends `resolved=0` and keeps it in its address, since a blocked, an escalated and a
  failed case are closed and still need a person; a closed outcome's tile or the resolved state turns it off, the other
  states stay beside it, and an address with 1.4.5's `open=1` reads as the switch on. The page no longer sends
  `open=1`; the trial's API takes both parameters. The count of cases that need a person, beside Cases in the
  navigation and on Home, reads "at most" when more than 100 cases failed, as the Failed tile does (5).

- v1.59, 13 Nov 2026 (the Cases list: hiding the closed cases, and saying what it searched): `GET /cases` takes
  `open=1`, which leaves out the cases that are resolved, blocked, escalated or failed, in the query itself
  (`Shutter.API.Dispatch.CasesWhere`), so `total` and the pages are of the open cases; any other value filters nothing,
  and a list read without it is unchanged (5; `tests/unit/Shutter/Test/CasesOpen.cls`). The Cases page has a **Hide
  closed** switch that sends it and keeps `open=1` in its address, turned off by choosing a closed outcome's tile or a
  closed state; the trial's API takes the same parameter. A closed outcome chosen where there are more than 100 cases
  says how many match "among the 100 most recent cases" and that older cases have not been searched, the Failed tile
  reads "at most" when more than 100 cases failed, and an empty list's words come from the install's own report
  (`demo`, `watched_namespaces`, `shutter_production`) and the caller's rights, with no new field (5).

- v1.58, 11 Nov 2026 (for 1.4.4, so the public demo's account plays the scenarios): the role `Shutter_Demo` holds
  `Shutter_Scenarios` and still neither `Shutter_ScenarioReset` nor `Shutter_LiveAgents`, so it runs the scenarios and
  never resets the demo or purges its store (5). A run started by someone without `Shutter_LiveAgents` is replay only:
  the route reads that right in the starter's own process and sends it with the run, the runner records it, the cases
  the run opens keep it and say so on their trail, and every agent request of such a case carries `ModeOverride`
  `replay`, so no provider is called and nothing counts against the day's budget or a share, even where the board answers
  live; a reopening or a convened board goes by its own requester's right (4.2, 9, 16). The run record and the 202 carry
  `replay`. The single investigator was never recorded, so such a run in mode `single` is 409 `not_recorded` (4.2). A
  judge's run, with the live agents, is unchanged.

- v1.57, 10 Nov 2026 (for 1.4.3, so the judges run the scenarios): running a scenario and resetting the
  shared demo are two resources. `Shutter_Scenarios` guards `POST /scenarios/{id}/run` only, and the role `Shutter_Judge`
  holds it; the new `Shutter_ScenarioReset` guards `POST /scenarios/reset` and `Shutter.Setup_PurgeStore`, held by the
  operator and approver roles and by neither public demo role (5). An install or an upgrade creates it and gives it to the
  operator and the approver. `GET /me`'s `can` gains `reset`, and `GET /access` a `reset` row. A scenario run's cases carry
  who started it, and their live agent runs count against that user's share (4.2, 9). The words for an `orders_results`
  receiver say what 1.4.x does: the case gets its findings and goes to a person with no resend from it, and at a receiver
  set up for it an outage's undelivered messages can be resent after one approval (6.3, 6.4, 17.8).

- v1.56, 10 Nov 2026 (for 1.4.2, found on the public demo): the anonymous `GET /health` reads the live hospital's switch
  and cadence from a public copy in Shutter's own namespace when it may not read the hospital's database, a copy older
  than three of the player's periods counting as unknown (4.4, 12). No other field changes.

- v1.55, 10 Nov 2026 (for 1.4.1, the 1.4.0 recheck's leftovers): an `unknown` resend is read again by Engine Resend's poll
  and settles by the send's own rules once its new header settles, with an outage event `resend_settled` (17.8); the
  card's settled words count an unknown result as its own, each message by its last row (a clone sent in its place
  included), and a closed card says what still needs a person (17.4). A shadow-mode escalation's line reads Not sent (18).
  A message Shutter does not model is described as not resent from its case, with the outage resend named where its
  receiver is set up for one, and words stored before keep their meaning on every read (no stored text is rewritten).

- v1.54, 9 Nov 2026 (for 1.4.0, the hands-on test's finding): shadow mode and the recovery stop hold the outage resend
  (17.8, 18). `POST /outages/:id/approvals` answers 409 `recovery_stopped`, `recovery_shadow` or `control_unreadable` once
  its own checks hold, recording nothing; Engine Resend reads the control under its lock last before every message and
  halts the run, its unsent rows `stopped` with `halt` and the reason, the outage `needs_person`, and `words.first` saying
  so; a new approval resumes it once the stop is cleared. `resends[].halt`. Already handled by hand stays allowed. Shadow
  mode's words and `covers` name the outage resend. Proof: `Shutter.Test.EngineResend`, `Shutter.Test.RecoveryControl`
  and `tests/e2e/outage_stop_check.py` on build 154.
- v1.53, 9 Nov 2026 (for 1.4.0, measured on build 154): the set gate refuses a message whose life crosses a stop or a
  crash (`set_policy_version` 2026-11-09.2). Inside one job's handling of a message the engine logs every change of an
  attempt's words, so an attempt that reached the receiver always leaves an Error row; an attempt cut off by a forced stop or
  a crash leaves none, and the engine puts the message back on its queue unmarked, so its later attempts can all say the
  connection never opened while the receiver holds the frame. `Shutter.Util.EngineRead.Interrupted` reads the namespace's
  event log, from the header's creation on, for a row of `Ens.Job` `RecoverActiveMessage` or `MarkDeadJobs` or of
  `Ens.Director` `StartProduction`, by the engine's class and method columns since the words are translated; such a message
  goes to `refused` with the reason, at the list and at Engine Resend's check before each send. A clean restart during an
  outage refuses its messages too: a person sends them. Proof: `tests/e2e/attempt_history_check.py`. A message's cases in
  a watched namespace are those with that `sourceNamespace` and `originHeaderId` (a case's `sourceHeaderId` is Shutter's own
  copy and is never matched against another namespace's header), for the patient check's own cases and for what a send
  resolves. Also for 1.4.0 (`docs/design-1.4.0.md`): the patient check narrowed for orders and results to the same or a
  linked order, with merges, replacements, unresolved cases on the same order and anything unread still holding, and a
  newer body that can't be read holding on both paths (17.8, `set_policy_version` moves again when built); `lists.closed`,
  a Row's `acts`, `closure`, `closedBy` and `closedAt`, `resends` on the outage and the case, and the act
  `handled_by_hand` (17.3, 17.8); the approval's `receiverChecked` and 409 `receiver_check_needed` where a receiver's
  duplicates are not refused; the declared phrase matched as the start of MSA-3 at a word's end; an already-held message's
  cases resolved `already_delivered`; a failed resend's event on its case; no case opened for Shutter's own resend (11);
  an escalation saved as a file reads `saved`, not `sent`, with `savedAt`, and the send's case event says queued (10);
  `ResendRecord` in the demo's purge (17.7). Storage slots appended: `Escalation.SavedAt`, `ResendRecord.ControlId` and
  `RecordedBy`, `Outage.ListClosed`. No route is added or removed.
- v1.54, 9 Nov 2026 (for 1.4.0, the hands-on test's should-fix findings): an outage's `openCases` is read again on every
  read, and its reasons are plain words (17.3); `sentByShutter` and the card's settled words count what Shutter's ledger did
  (17.4); a `sending` row lists no act (17.3); a `needs_person` row with no approval is computed again every minute (17.2).
  An orders and results receiver the site gave no `api` has no receiver API: no paths and no address in its label (6.4), so
  the evidence asks nothing of the demo receiver's address for it, and the gate's identity check reads not applicable
  (`NOT_APPLICABLE`) rather than unreadable. The evidence's route names a forwarded message's own route. An order or
  result case's blocked reason gives its own next step. No route, field or storage slot is added or removed.
- v1.52, 9 Nov 2026 (for 1.4.0, found on the Pathology rig): `findings` is a snapshot item kind, so an order or result
  case's evidence no longer fails when it adds the item (before, every such case ended `failed` with no snapshot). The
  character finding adds `shared` (`failures`, `of_failures`, `characters`, or `why`): how many of the receiver's failures in
  the last 7 days hold one of the message's characters in any field, a run stored as UTF-8 bytes counted as the character it
  encodes, and its sentence leads with that count. The receiver's words are read from the engine's log row: its
  "response N@EnsLib.HL7.Message" is an object reference in the operation's process, not a stored id, and is no longer
  opened. The alert intake passes on a queue alert on a message the engine still holds (11). No route or field is removed.
- v1.51, 9 Nov 2026 (for 1.3.0: Pathology's set gate and findings): `Shutter.Util.ResendSet` computes an outage's four
  lists at the close (17), so a row can read `offered`, and `acts` gains `read_again`, served by the next poll rather than by
  a reader item; `Outage.ReadAgainAt` is new, its storage slot appended after the 1.2.0 ones, with the storage now in the
  source. An order or result case's evidence carries a `findings` item and `summary.findings` (the custody, the receiver's
  words by field, characters above ASCII and the OBX the words name); ModelView's allowlists leave both out, and the
  escalation draft takes only the parts with no free text. An ADT, SIU or MDM case's evidence is unchanged. The ledger
  `Shutter.Store.ResendRecord` and the messages `EngineResendRequest` and `EngineResendResult` exist with no writer or sender.
- v1.50, 9 Nov 2026 (the features of the 1.2.0 work, built as v1.48 on the features branch on 8 Nov, joined onto 1.47 and release 1.1.1; they reach the release here, after 1.2.0's own v1.48 and v1.49): shadow mode and the recovery stop, section 18, with
  `Shutter_StopRecovery` (5) and `recovery` and `notifications` in the site profile; the failure coverage census, section 19,
  with `failure_census` (6.4) and Failure Census in INSTALLITEMS (12); the case bundle and the unredacted bundle with a typed
  reason, neither moving a closed case's receipt (5); what to check at the receiver (5.2); a person's release of another
  visit's stop, `GET /cases/{id}/further-stop`, `POST /cases/{id}/further-release` and `FURTHER_MOVEMENT_RELEASED` (6.1, 6.5);
  a non-demo install through `SiteProfile.ForSite` (6.4), beside the shipped policy and the demo's own table; the reminder for
  cases left open, `reminders` (6.4), which shadow mode holds; `further_messages.a08_location`, `stop` or `show`, with
  `UPDATE_LOCATION_DIFFERS` and `UPDATE_LOCATION_SHOWN` (6.4, 6.5); a lost admission never released by policy inside an
  incident either, a partial board's plan that writes nothing escalated, and an incident's approval void when the catalogue,
  site profile or gate policy version moved, `APPROVAL_CATALOGUE_CHANGED`, `APPROVAL_SITE_PROFILE_CHANGED` and
  `APPROVAL_POLICY_CHANGED` (6.1, 6.4, 7.3), gate policy version 2026-11-07.1, so an approval given under 1.47's 2026-11-06.1 and
  not yet dispatched is void at dispatch; the drafted correction sequence, stopped by every further message for the patient
  (10); document exceptions, an ORU counted as a report by OBX-2 alone (11.2); the Settings screen for watched namespaces
  (11.3) and `documents_mismatch` (11.1); what each receiver last answered and the report before an install (12); S14 and
  S26 (4.1, 8.2) and the fault `commit_then_409` (1.5). The sections these brought as 17 and 18 are 18 and 19 here, after 1.47's
  receiver outages.
- v1.50, 9 Nov 2026 (as v1.48 on the features branch on 7 Nov: a storm of 200 failures, measured; the release carries the same behaviour since v1.47, below): the shared approval task's message lists the first chains that fit in its 2,000 characters and points to the incident page; an error raising a task no longer abandons the incident, which waits for a person and tries again every 5 minutes (7.3). No API field changes. The incident page lists six chains and offers the rest behind one button.
- v1.49, 8 Nov 2026 (Ask Shutter): a question about a page of the web app (14.6): `Shutter.Store.PageQuestion` (`P-nnnnnn`),
  `POST /page-questions` and `GET /page-questions/{qid}`, the Explain agent in the question tier `page`
  (`Shutter.Agent.ExplainPage`: the explain collection's search and `SubmitAnswer`, no evidence tool, 12000 tokens, 3
  iterations, never recorded), the summary of the screen held to its shape and written as data inside the evidence tag,
  the checks on the answer (`page` or an id the summary lists), who may ask (`Shutter_LiveAgents`, the day's budget, a
  model to answer) and the API mimic's page turn. An `AgentRun` may have no case (such a run only), and `GET /costs`
  `byQuestion` lists it with `caseId` null. The case questions (14.2 to 14.5) are unchanged.
- 8 Nov 2026 (the Technical detail on the cases): `GET /cases` items and `GET /cases/{id}` carry `messageType`,
  `production`, `sourceItem`, `receiverClass`, `failedAt`, `planVersion`, `planDigest` and `catalogueEntry`, and the list's
  items `links`, read only and never a patient field (5).
- 9 Nov 2026, release 1.2.0 (v1.48): a page question (14.6) follows the Agent Board item's own Mode and is never recorded or replayed; its cites name a listed id, with any path after it kept out of the core; page questions are purged on the cases' retention days. An approval timeout cancels the task only under the decision lock, and the case keeps waiting until then.
- 8 Nov 2026, release 1.2.0 (v1.48): a policy release that meets another visit's new movement at dispatch is refreshed and planned again like a person's approval (6.5), and the policy is asked again on the fresh snapshot, which shows the movement and so asks a person. An approval task counts as decided only when its claim says so; a busy or failed claim reads the task again and cancels it, recorded on the case.
- 8 Nov 2026, release 1.2.0 (v1.48): a receiver declared with no API (a draft entry) keeps the code `RECEIVER_UNREADABLE`; the gate's detail, the blocked reason's text and next action, the escalation email and the case page say it was declared with no API and name it by its item and namespace.
- 8 Nov 2026, release 1.2.0 (v1.48): two release behaviours stated as built (7.4): any error in an incident's workflow
  during a release, other than raising an approval task, abandons the incident; a receiver that goes down again during a
  release stops each remaining chain in turn at its next item, with nothing written twice; and `provider_auth` (12) stated
  as built: only a run with status `error` sets it, so a key the provider refuses, which ends `model_error`, doesn't set it yet.
- 8 Nov 2026, release 1.2.0 (v1.47): the receipt check compares beds only when the receipt and the operation both state
  one: a bed that is JSON null, missing or empty is not stated, so a receipt whose bed is null no longer reads as a
  different bed (`RECEIPT_PAYLOAD_DIFFERS`), and a stated different bed still does. A replayed run writes one trace line per
  recorded tool call (the tool; ok, denied or failed; the milliseconds; the word replay; no argument, result or error text),
  so each call is a step of its own in the Visual Trace, as a live run's are (9); this corrects v1.40's "A replayed run
  writes one trace line naming its tool calls". `zpm "uninstall iris-shutter"` runs `Shutter.Util.Uninstall` before the
  classes go: everything the install and the onboarding added, in every namespace, with no production of the site's
  stopped and a site production Shutter went into updated in place; `Shutter_Util.Uninstall_Plan()` says what would go and
  changes nothing; it refuses, changing nothing, while a production it did not wire names a Shutter class or a hospital's
  namespace holds a class of the site's in the `Hospital` or `Downstream` package; `HardenPortal` records each portal
  application's earlier roles and resource for it to put back (12). An incident's approval task lists what fits in its
  2,000 characters and binds every chain, and an error raising it closes nothing and is tried again every 5 minutes
  (7.3); the incident page lists six chains with the rest behind one button. `further_messages.in_patient_movement` is
  `show` when absent and in the shipped profile, an `other_visit` row stops only where the profile says `stop`, and a demo
  install writes `stop` into its profile, the live hospital's included (6.4, 6.5). No interface change from the pages on
  another provider, AI Hub's features, the publisher from an MCP client, or the README.
- 8 Nov 2026, release 1.1.1 (no interface change): the model view reads a route item as a route before a receiver's body, so
  the route's capability profile reaches the agents whether or not the route says the receiver offers history (9).
  The demo's portal page lists the production's agents and its other operations with their settings, read with
  `Ens.Config.Item`, and of a provider configuration only `model` and `model_provider`, with no secret resolved; a replaying
  item names no model, a line says what a run's request sets, more secret shapes stay hidden and the cards fit 320 px (16).
  A key-shaped `ProviderConfig` is checked before `AI.LLM.` goes in front of it, a mode that isn't one reads "not valid",
  a listed operation setting shows only in its own form, and the page has a Refresh link in place of its 30-second meta
  refresh (16).
- v1.47, 8 Nov 2026 (the engine check): the gate's ordering check reads the engine first for a write on a case with a source
  namespace and an origin header, with `ENGINE_NOT_IN_SCOPE`, `ENGINE_STILL_TRYING`, `ENGINE_DELIVERED`, `RECEIVER_MAY_HOLD_IT`,
  `ENGINE_UNREADABLE` and `ENGINE_SETTLED` (6.5); the case carries `waitsOnEngine` (11); eleven reason codes appended to
  `knowledge/block-reasons.json`, of which `HOLD_EXPIRED`, `ENGINE_ROUTE`, `ENGINE_ROUTE_ABSENT`, `ENGINE_ROUTE_REFUSED` and
  `ENGINE_ROUTE_NO_API` are not emitted by this build.
- v1.47, 8 Nov 2026 (receiver outages): a receiver entry may carry `watch`, `runbook`, `call`, `approvers`, `ack_level`,
  `duplicates`, `engine_resend`, `hold`, `mail`, `resend_approval_minutes`, `settle_minutes` and `window_minutes` (6.4); an entry
  with none of them validates as before. Section 17, receiver outages: Receiver Watch, the states, `GET /outages`,
  `GET /outages/:id`, `POST /outages/:id/acts`, the card's words, the forwarded /summaries and /assist with one security
  contract, the Doctor's outages lines and the reset; Receiver Watch in INSTALLITEMS (12). The Outage carries `linkedCases`
  and `outcome`, and the outage's events their kinds (17).
- v1.47, 8 Nov 2026 (the Case Releaser's third pass): `Releaser.ReleaseEngineWaits` judges each case waiting on the engine
  from its marked header, resolves it when the engine delivered, plans it again when settled, and leaves it while the engine
  still holds it or its record can't be read; `GET /index` `releases.candidates` gains `engine`, and `releases` gains
  `engine_unreadable` (8.1).
- v1.47, 8 Nov 2026 (the approval default): the shipped
  site profile's policy is `approval` for single and ordered chains at every tier, the board for interleaved ones; a demo
  install keeps the earlier table as the demo's own, labelled setting, marked in the profile's source and on the Site profile
  page (6.4, 4.4).
- v1.47, 8 Nov 2026 (what the receiver must honestly offer): a receipt or history entry closes a case only if it holds the
  operation's own digest, ward and bed (`RECEIPT_PAYLOAD_DIFFERS`); a cancel since the receipt stops it
  (`RECEIPT_THEN_CANCELLED`). A read counts only as the receiver's own answer, and a 200 is a delivery only with its receipt
  or applied; `receivers[].strict_answers`, default true, turns these off for one receiver. A receiver that offers no readable
  history gets no resend (`HISTORY_UNSUPPORTED`). No sign of a write by the last read is unknown, and `not_committed` needs the
  version moved by something else. A write during a rehearsal or preview never resolves (`WRITE_NOT_RELEASED`). The case purge
  takes only finished cases.
- v1.47, 8 Nov 2026 (who and when): `feed.source_skew_seconds` (6.4, default 300); `simultaneous_sources` counts another
  source's movement within it, or at a time that can't be read, and never an update (6.1); `event_time` future also reads the
  engine's `received_at`, and `clock_change` reads the feed's own zone (6.1); new condition `death_recorded` and entry E19
  (6.1); the timeline keeps to the case's patient and authority (8.2); E1 v5 needs `event: transfer` and
  `simultaneous_sources: no`; E7 v3, E13 v5; an unreadable event time doesn't map (E12).
- v1.47, 8 Nov 2026 (an incident's chains): a chain's next item goes at the version in the previous item's receipt, or the
  receipt the verification read; only an item with no receipt takes the encounter as read (7.4). An approval under an
  incident binds the plan's epoch, so a reset voids it with `APPROVAL_RECEIVER_RESET` (1.8). A chain waiting on a case its
  incident still holds back stops, and the incident goes on (7.4).
- v1.47, 8 Nov 2026 (further messages for the patient): the evidence's `further_messages`, `Shutter.Util.FurtherMessages` and
  `Index.Message.ForPatient` (6.1); gate reasons `FURTHER_MOVEMENT`, `NO_FURTHER_MOVEMENT`, `PATIENT_UNREADABLE` and
  `FURTHER_NOT_READ`; the connector's `further_movement`; the site profile's `further_messages` (6.4); a lost admission on a
  404 isn't released by policy outside an incident. New scenarios S27 to S32.
- v1.47, 8 Nov 2026 (what reaches Shutter): the alert route and the acknowledgement route carry the message the failing item
  was sent, with the session's service as the route (11); a session that sent one item several different messages, or an
  item that takes no HL7 in a session naming several patients, opens no case from an alert and raises an alert naming the
  messages (11); alert words the intake does not know, and ErrOutConnectionLost, are `uncertain_outcome` with reason
  `alert_unread`, which the matcher reads as `receiver_answer` unread (6.1, 11); a 202 with no case id is a refusal, and a
  forward with no answer or a 502, 503 or 504 is tried again for the forwarder's `FailureTimeout`, 300 s by default and as
  onboarding sets it (11); an automatic release needs the case's source proved, `APPROVAL_ORIGIN_NOT_PROVED`,
  `feed.prove_origin` (6.4, 6.5, 11); the intake records the signed-in user (11).
- v1.47, 8 Nov 2026 (a case with no board answer): `CaseWorkflow.NoBoard` (6.6): outside mode `rules`, a catalogue decision
  of `board` or `person` with a match goes to `escalated`, disposition `escalate`, no plan, reason `NO_BOARD_ANSWER`, for every
  member refused or with no recording, no member to convene, and a follower whose board decided nothing; other cases keep the
  rules path, and mode `rules` is unchanged. `BoardLead.decidedBy`: a lead whose plan came from the rules passes on no
  decision. `ENTRY_NOT_NAMED_WRITE` (6.5): a write naming no entry while a matched entry calls for no resend is blocked,
  except a `rules` plan in mode `rules` that the scenario runner played. Gate policy version 2026-11-06.1, so an approval
  given under 2026-11-01.1 and not yet dispatched is void at dispatch.
- v1.46, 5 Nov 2026 (a review of this version): `not_committed` says "by the last read" and that a slower receiver can still commit the write (5.1); a write call that answers with an error records its attempt as `uncertain`, and reads as `WRITE_OUTCOME_UNKNOWN`; `GET /cases/{id}/blocked-reason` reads a rehearsal with no usable answer as `BLOCKED`, and a lost write's reason is no longer hidden by an earlier round's gate decision; a reinvestigation without `Shutter_LiveAgents`, or while the provider refuses the key, whose board has no recording leaves the case escalated, with the reason, instead of taking the rules path. Onboarding: an alert the site's own consumer raised is not passed back to it (11); options that are not a JSON object answer `{ok: false, error}` in the plan, the apply and the removal; a `receivers` name matching no item is a warning, and with no item chosen the plan has no `add_alert_intake`; a profile entry with an `api` and no `namespace` counts as taken, with a warning; `OnboardReceiverItem` refuses, naming both, an item that exists with other settings (11.1); a `receivers` option that chooses no item adds no forwarder. The web app keeps the Cases filter and page and the Scenarios mode and filter in the address.
- v1.45, 5 Nov 2026 (measured on a stock operation): a case for an order, a result or a document keeps `failureKind` `unmappable`,
  E12 and its escalation, and nothing is sent; its failure text, headline, plan and gate detail stop saying the message could not
  be mapped, and say what the receiver did from `failureOutcome`, since the message may be sound. No API field changes.
- v1.44, 5 Nov 2026 (a second cold run of the guide): a wired namespace keeps its receiver names when another comes on, so the action `set_prefix` is
  gone and the plan warns of a later clash; `credential` on a removal no longer depends on which namespace made the user, and the last one takes it (11).
- v1.43, 5 Nov 2026 (an integration lead's point that a transport ACK does not mean a message was processed): the plan reports each HL7
  operation's acknowledgement settings and what a completed message proves there (11.1); `Shutter.Intake.AckMatch` turns a negative
  application acknowledgement on its own feed into a forward (11).
- v1.42, 5 Nov 2026 (a real instance's failure paths, reviewed on 5 Nov): a request the receiver never answered is classified as no answer, which the connector's +StatusCode had made unreachable. A write timed out reads `uncertain` and goes to verification instead of `error`, refused and "nothing changed" (1.3, 5.1); only a socket that never opened is `unavailable`; a preflight read that got no answer is `unavailable`; a feed delivery timed out opens as `uncertain_outcome` rather than `delivery_failed`, at Shutter's connector and the demo hospital's. The audit line and the failure text no longer name HTTP 0. `UncertainSettleSeconds` is 60 s, so not committed is said at the last read, about 70 s after the attempt, and no longer at 30 s while a slow receiver may still commit (1.3, 5.1). A rehearsal with no usable answer no longer says the action would not apply; the receiver's own refusal of it (a 409 or 422) still does. A request nobody answered that may have been applied says so, with the adapter's words in brackets after it, and the catalogue reads a reason code only from a parenthesis ahead of the failure text's first colon. The audit trail, the gate's details and the forwarder's log say "no answer" where a status would read 0. `Shutter_Operator` and `Shutter_Approver` write the hospital's data database and the records system's, so Reset works for them and reaches every demo receiver; `ResetLive` answers `not cleared` rather than failing the reset halfway (4). An approval wait that runs out names `system` on its audit event, and a coordinator refused for the day's budget leaves the headline "No plan: the day's model budget is spent" (5). The live hospital holds its stories until Shutter's API service is registered, so a story at the first start is no longer lost (4.4).
- v1.42, 5 Nov 2026 (a request for a hospital's several namespaces, and a run of the install on three of them): onboarding a
  namespace (11.1); a forward naming a category not loaded here says so and can be repaired; a same-named category is imported under an
  alias; `ReceiverPrefix`; a site's unnamed receiver has no API; a namespace running another production refuses the install (12); the Doctor
  reports each watched namespace.
- v1.41, 4 Nov 2026 (the choice of a page drawn by IRIS over the static guide): the demo's portal page (section 16).
- v1.40, 4 Nov 2026 (a stock TCP operation tried as a receiver, and the README's walk-through followed as written): an entry with
  `features` and no `api` is a receiver with no API of its own and has no paths (6.4); it read the demo receiver in its place
  and believed that receiver's capabilities. `Shutter_Approver` carries `%Ens_EventLog` (E2), since the Visual Trace's event
  diamonds refused the user the README signs in. A replayed run writes one trace line naming its tool calls.

- v1.39, 3 Nov 2026 (the sweep of 3 Nov: the public demo's user could spend the model budget): the agent part of
  `POST /production-reviews` takes `Shutter_LiveAgents` and is skipped without it, or while the provider refuses the key (the
  202 says `agent` false, the review ranks by its baseline with `agentState` `skipped`); the review's run carries the
  requester, so it counts against that person's share, as a question's does (5, 13.5); a reinvestigation's runs carry the
  person who reopened the case, not "system", and without `Shutter_LiveAgents` (or with the provider refusing the key) they
  answer from recordings only, `ModeOverride` `replay`, so a board with no recording takes the rules path (the 202 carries
  `liveAgents`; `Shutter.Msg.Reinvestigate.LiveAllowed`); a judge's forced board keeps its convener (5, 14.5). The forced board
  itself (the same sweep): in policy mode it is honoured before the catalogue's person path, which escalated the case again
  with no board, and its plan goes to a person's approval even on an automatic tier, where the site policy released it and
  the gate then blocked it as `plan_origin` (14.5). Two corrections of the text: `PUT /site-profile` and the review
  annotations take `Shutter_Configure`, as the code always did (7.5, 13.5), and the approvals body with `expectedVersion`
  and its `409 stale_version` is written down (5).
  The provider key is written again at a start whose wallet secret or Config Store entry is gone, not only when the
  digest changed (12); the Doctor reports both.
  Also from the sweep: the scenario runner's reset clears the live hospital's bed map unless a story plays, and a story cut
  off leaves no fault behind (4.4); `heldSchema` is cleared with NULL, not `''` (which stored a null character); the Case
  Releaser's two checks throw their errors so the run row records them; the unit runner reports skipped methods (`skipped`,
  `skips`); `SHUTTER_DEMO_PORTAL` hardens the portal at every start and the Doctor says so (12); the demo's `PurgeStore`
  empties the precedents and board leads too and stamps `resetAt` (12).
  The alert intake marks a session seen only once Shutter took its message, pending meanwhile (11); a board lead whose
  leader fails, is abandoned or is closed by hand ends at once for its followers (6.6).
  The prompts name the evidence keys and the earlier names stay citable (6.1); an alert's reason code reads as no
  answer of the receiver's, so the status and the outcome decide the match (11); a receiver entry with neither a
  capabilities endpoint nor declared features reads as capabilities unread, `CAPABILITIES_UNREADABLE` (6.4).
  A first index walk with no header inside the back-fill window starts after the newest header (8.1); a scenario run the
  API service could not take leaves no queued record behind (4).
  An impossible date reads as no time on every path (the time rules); the receiver's demo controls (faults, reset, the
  capability switch) take the new resource `Downstream_Admin`, granted to no role of Shutter's (1.5, 1.7, 1.8).
  A receiver the site profile does not describe is blocked at the proposal gate, `RECEIVER_NOT_IN_PROFILE`, instead of
  being written at the default receiver (6.5).
  The Doctor's `wallet_secret` and `provider_config` are null, not false, for a reader without the right to look (12).
- v1.38, 2 and 3 Nov 2026 (the demo rehearsal's storm, whose cases all convened boards): a watched production's failures run in the
  site's watched mode, policy by default, whatever mode the scenarios run in (6.3, 11); a case the alert intake opened
  takes the production's own report of the failure when it arrives before the evidence is collected, so the catalogue
  reads the connector's answer (11); the alert's time in the failure text is read as the engine's UTC timestamp (11);
  the tool catalogue pinned at a run's start, `Shutter.Bridge.Catalogue`: what the framework discovered must be exactly the
  agent's evidence tools, its terminal tool and its attached collections' search tools, or the run ends with the status
  `catalogue_mismatch` before any model call (9); the demo's Management Portal made read only for the demo's harden script,
  `Shutter.Setup.HardenPortal` and `PortalState`: the portal applications of both namespaces lose the MatchRoles that gave
  every signed-in user the data databases read and write, require the resource `Shutter_Portal`, which `Shutter_Trace`
  alone holds, and the trace role reads the HealthShare and both namespaces' databases and writes none, so demo-trace can
  no longer switch items off or save settings and demo and judge cannot sign in to the portal (12); two words put right: the rehearsal check blocks at dispatch, the only
  stage that sends it (6.5), and a deferred board waits 60 to 89 s (6.6); the live hospital's rotation drops S11 and takes `SHUTTER_LIVE_SCENARIOS` (4.4); the demo users'
  password reaches the image build as a BuildKit secret, never a build argument, and CI proves it is in neither the build
  log nor the image's history (12, 13); the Doctor tries the stored credentials (DownstreamAPI here, the demo hospital's
  DownstreamAPI and ShutterIntake) against their users by a login in a background job, never a web request; the
  production keeps the result cached ten minutes (its start and the Case Releaser's sweep), a request that cannot write the
  database only reads it (the hardened demo's anonymous health report has no roles), `GET /health?refresh=1` recomputes
  for an operator who may write, and the Doctor reports `credentials`, `credentials_ok`, `credentials_state` (fresh,
  refreshed, stale, unchecked) and `credentials_checked_at`; the anonymous health report carries `credentials_ok` (12).
- v1.37, 2 Nov 2026: whether the live agents can run, `live.agents` in `GET /settings` with reasons `budget` and `provider_auth`,
  the Agent item's `provider_auth` refusal while the provider refuses the key, and `409 live_unavailable` on the board and a
  live question (12), for the demo's notice to visitors; `live.budgetNote` from `SHUTTER_DEMO_BUDGET_USD` and
  `SHUTTER_DEMO_BUDGET_PERIOD` for the banner (12).
- v1.36, 2 Nov 2026: a decision that lands while the Workflow engine is still distributing the task waits for the engine's
  worklist row and assigns again when its own row meets the engine's (5; a CI run's 409 "ID key not unique" of 2 Nov).
- v1.35, 2 Nov 2026 (the items of a review of competing entries' code): denied tool calls
  recorded as rows with `denied` true and a trace line (9); the run's millisecond start and AI Hub's own counters
  (`startedAtMs`, `llmMs`, `toolMs`, `reasoningTokens`) on the response and the run row (9); a bound on one model call,
  `provider_timeout_seconds` (6.6, 12); the compose healthcheck and `last_live_run` in the Doctor and the health route (12); the agent operation's start-up line in
  the event log, with a warning for live mode without a provider (6.6); findings and plans cite only the evidence they were
  given (6.6); the image's `WITH_AIHUB` defaults to `auto` and the Doctor reports `edition` (12); a repeated decision answers with the
  approval taken, an inactive Workflow user is no approver, and the intake refuses a body over 2 MB (5, 11, 14.5); an approval
  wait is bounded, `ApprovalWaitSeconds` (6.4); boards per minute are capped, `BoardsPerMinute`, the storm stopgap (6.6); invisible
  characters stripped from agent text, text caps and a hostile-output table (6.6, 9); precedents, a person's decision on the
  same conditions at the same receiver, counted in the approval task's text, the snapshot summary and
  `GET /cases/{id}/precedents` (6.4); the releases of waiting and held cases moved out of the index adapter into the Case
  Releaser item, one sweep every few seconds with a run row when there are candidates (8.1); the alert intake,
  `Shutter.Intake.AlertProcess` as a watched production's `Ens.Alert` item, which hands a delivery failure's message to
  Shutter from the alert alone and passes every alert on to the site's consumer (11, 13); the storm, `POST /live/storm`,
  eight failed movements for four fresh patients in the live hospital with the receiver down for a minute, followed on
  `live.storm` (4.4); the budget reserves an estimate for each run in flight and settles it when the run ends (9); a receiver's
  `Retry-After` on a 503 or 429 is a minimum wait before the resend's preflight read, and the demo receiver sends one (1);
  one board per failure signature, the first case leading and the rest taking its decision through their own evidence,
  gate, rehearsal and approval (6.6); the published IPM package is the whole of Shutter for an AI Hub build (2026.3 or
  later, the organisers' requirement) and the core alone moved to `core/module.xml`, loaded by path (12);
  the publisher, Shutter's read-only tools for an MCP client through IRIS's own gateway, with an audit row per call, on
  the AI Hub build (15); each item of the review that lands adds its line here.
- v1.34, 1 Nov 2026: the public demo's roles (5, 12), for the live hospital: the resources `Shutter_Scenarios` (the demo controls:
  run, reset, purge) and `Shutter_Configure` (the site's writes: the profile, the library, a schema import, the review
  annotations), held by the operator and the approver as before; the role `Shutter_Demo` (reads, reinvestigates, approves and
  asks, holds neither) and the user `demo` made only when `SHUTTER_PUBLIC_DEMO_PASSWORD` is set, a member of the Workflow role;
  the role `Shutter_Trace` (the Visual Trace and the messages in the Management Portal, read only, nothing of Shutter's) and
  the user `demo-trace` made only when `SHUTTER_TRACE_PASSWORD` is set; `GET /me` answers `can: {operate, approve, configure,
  scenarios}`. The live hospital (4.4): the HOSPITAL production's item Live PAS (`Hospital.LivePlayer`) plays a scenario every
  7 minutes with fresh patients at present times and real faults, and an ordinary message a minute between stories, through
  the hospital's own inbound folder; `Shutter.Util.LiveFeed` does the text (`Shutter.Test.LiveFeed`); `SHUTTER_LIVE=1` at
  the install or `Hospital.Setup_SetLive(1)` turns it on; `^Hospital.Live` records the plays and the status that the Doctor
  and `GET /settings` carry as `live`; the hospital install compiles the production class in its namespace on every run. The
  board's coordinator and members have 50000-token budgets, and a suggested question's record key base names the case's
  receiver (`question:<S>:<encounter>:<event>[:<receiver>]`, 14.2), so S22's two cases record apart. The day's model budget
  (9): `SHUTTER_DAILY_BUDGET_USD` into `^Shutter.Config("dailyBudgetUsd")` (`Shutter.Util.Budget`), a live or record run
  refused with `budget_exhausted` once the day's spend reaches it, the board on the rules path then, `budget` in `GET
  /settings` and the Doctor. A case forwarded from a watched production (11) reads the refusal that named the bed's occupant
  and the occupant's deliveries in that production's namespace as well as Shutter's (`Timeline.LastRefusal`, `Deliveries` with
  the case's `SourceNamespace`), so its bed conflict (6.1) is judged as a case of Shutter's own feed is; before, the forwarded
  refusal read as unknown and E17 escalated it. The case's timeline (8.2, `Timeline.ForCase`) takes that production's
  deliveries for the encounter too, each row with `namespace`, so a forwarded case's evidence, `later_events` and the case
  page's encounter timeline show the admission before the failure and the movements after it, where before they held the
  forwarded failure alone. From the board's first live runs of S21 to S25: a scenario recording's key names the case's
  receiver when it is not the default (4), the board's plan at a history-of-record receiver gets the correcting steps as the
  policy path's does (`CaseWorkflow.AttachCorrectionSteps`), and the gate holds a superseded plan with
  `NEWER_MESSAGE_PENDING` while the later event it rests on is still on its way (6.5). The Second Parser item is
  `Shutter.Operation.SecondParser`, which sets its classpath at start (6.7). The live hospital's install sets tier 2 single
  chains to approval (4.4), and the recording round rule is written down (4). The judges (decided on 1 Nov 2026):
  the resource `Shutter_LiveAgents` (operators, approvers and the new role `Shutter_Judge`, the public demo's role plus it;
  `Shutter_Demo` never spends), the user `judge` made only when `SHUTTER_JUDGE_PASSWORD` is set, `GET /me` `can.liveAgents`,
  questions running live only for those who hold it and refused `no_recorded_answer` otherwise, `POST /cases/{id}/board`
  convening the board on a case (14.5), each user's share of the day's budget from `SHUTTER_JUDGE_BUDGET_USD` with
  `RequestedBy` on every agent request and run (9). "Prevent failures" (decided on 1 Nov 2026, option c of the
  morning bundle): `feed.prevent_failures` in the site profile (6.4, off by default), the case kind `unreadable` with
  `heldSchema`, the hold in `ADT In`'s process on a canonical 2.5.1 reading, the forwarder as a bad-message handler with
  `HeldReceiver` and the intake's fifth kind (11), the matcher's `delivery: unreadable` (6.1), the gate's `SCHEMA_UNKNOWN`
  for a watched namespace and `UNMAPPABLE` for an `UNMAPPED^` key, the release by the index's check, the epoch behind the
  known-categories cache, the Doctor's `prevent_failures` and `held_messages`, `GET /settings` `preventFailures` and
  `heldMessages`, and the demo hospital's `Hospital.Setup.PreventFailures` (12). The container's environment applied at every
  start of the production (`Setup.ApplyEnvironment`: the budget, the three public logins, the live hospital; 12), so the
  image's `docker compose up` needs no build argument for them. The install (12): the installer's data database variable is `SHUTTERDATADIR`, since `DATADIR` is a name
  `%Installer` predefines (the install directory) and a Default never replaces an existing variable, so builds before this
  kept SHUTTERDATA at `/usr/irissys/`, inside the image and outside the volume, and lost every case on `docker compose
  down` or a rebuild (found by the upgrade proof of 1 Nov 2026; the hospital's and the records' data databases, under other
  names, were in the volume all along); `Setup.StartProduction` compiles `Shutter.Production` in its namespace before
  updating or starting it, so an upgrade's new items reach a kept production definition, as the hospital's install does;
  upgrading in place is INSTALL.md section 8. The resend failsafe (6.5) reads that namespace's deliveries as well: a
  ward operation of the encounter queued or in flight there with no result yet is a pending newer message, so a forwarded
  case blocks with `NEWER_MESSAGE_PENDING` and waits as a case of Shutter's own feed does; before, the failsafe saw only
  Shutter's own queue and resent while the watched production's newer message was in flight. Such a case is released when the
  watched production has delivered the message: the HL7 Index item's adapter asks `ResendGuard.ReleaseDeliveredWaits` every
  few seconds, since that production's connector knows nothing of Shutter (the Ward item releases the cases of Shutter's own
  feed as it delivers). The same check covers every waiting case: one whose plan took time (the board's minute) may begin
  to wait after the message was delivered, when the gate judged the snapshot's pending messages and the Ward's release found
  no case waiting yet, and would wait for ever (S24 on the board, 1 Nov 2026); the check releases it within seconds. The Second Parser (6.7): a PEX business operation in Java (HAPI) asked when IRIS cannot
  read a message, its report under `validation.second_parser`, the gate's `SCHEMA_UNKNOWN` and `PARSE_FAILED` words with its
  verdict, the item in `INSTALLITEMS` enabled only where `shutter-pex.jar` is installed (`SyncSecondParser`), the Doctor's
  `second_parser`, `pex/build.sh` in the Dockerfile.
- v1.33, 1 Nov 2026: the demo receiver's fault `delay_response` (1.5): a real operation is held for `seconds`, then applied
  and answered as usual, so a newer message can be on its way to the receiver while a case is about to resend (S24); the
  scenario runner's fault step passes `seconds`.
- v1.32, 1 Nov 2026: custom HL7 schemas (2, 5, 6.5, 12): `Shutter.Util.Schemas` (the loaded categories, the needed ones from
  the productions' `MessageSchemaCategory` settings and the newest messages' `DocType`, the import through
  `EnsLib.HL7.SchemaXML`); the evidence's `validation.schema_known`, `schema_fix` and the `unknown schema` verdict; the gate's
  `SCHEMA_UNKNOWN` in place of `PARSE_FAILED` for a category not loaded; the Doctor's `hl7_schemas`;
  `Shutter.Setup.ImportSchema`; `GET` and `POST /settings/schemas`; INSTALL.md section 7.
- v1.31, 1 Nov 2026: the index walk is an inbound adapter of Shutter's own (8.1): `Shutter.Index.Adapter` reads the next batches
  of HL7 headers after the high-water mark on each task and hands them to `Shutter.Index.Indexer` as `Shutter.Index.Batch`
  objects, moving the mark once a batch is taken; the walk's settings (`Routes`, `BatchSize`, `LagSeconds`, `BackfillHours`,
  `MaxBatchesPerTask`) are the adapter's (the production item's `Routes` moves from the host to the adapter); `Rebuild`,
  `Status` (now naming the adapter) and the index's shape are unchanged.
  The Doctor (12) gains `missing_items` and `disabled_items` (INSTALLITEMS against the production), `gate_policy_version`,
  `catalogue_entries` and `catalogue_ids`, `records_namespace` and `records_webapp`, `index_adapter` and `questions`, so a
  fresh install and an upgrade from the 25 Oct build show the same.
- v1.30, 1 Nov 2026: IANA time zones through Embedded Python (6.4, 12): `feed.time_zone` may name any zone the IRIS image's
  database knows, read by `Shutter.Util.Time.PyOffset` (a Python method) beside the native rules for UTC, Europe/London and
  fixed offsets; the validator asks `KnownZone`; the Doctor reports `python_zoneinfo`; `Time_Probe` shows `python_zones` and
  `zone_offset`. Without Embedded Python or the database the native rules stand alone.
- v1.29, 1 Nov 2026: the failsafe at the point of the resend (6.5, 5, 9): the evidence's `pending_messages` (`Shutter.Util.ResendGuard`:
  the encounter's messages received after the case's own and not yet delivered to the receiver), the gate's
  `NEWER_MESSAGE_PENDING` (policy version 2026-11-01.1), the case's `waitsOnMessage` released by that message's delivery, and
  the connector's own check at the moment of a recovery write (`refused`, `newer_message_pending`); the resend goes straight
  to the connector's queue, so no priority plumbing. The scenario S24 is the knowledge side of the same change. Also (7.4, 5):
  an incident's released item whose case is blocked while it waits on another case or a message is still working for the chain,
  which waits with it and is told once, instead of stopping; `GET /cases/{id}` lists `waitedOnBy`, the cases that wait on this one.
- v1.28, 26 Oct 2026: the occupied bed, Shutter's side (2, 5, 6.1, 6.3, 6.5, 9): PV1-3's bed component becomes the
  operation's `bed` beside the canonical payload (digests unchanged), carried by the ward message, the case, the evidence, the
  rehearsal and the recovery write, kept by the model view; for a `bed_occupied` refusal the evidence reads the occupant's
  encounter and the feed's deliveries for it and adds the `bed_conflict` section (`Shutter.Util.BedConflict`), the matcher's
  condition `bed_conflict` and fact `occupant_case`, the outcome `resend_after_occupant` (`waits_on` on the plan), the gate's
  `OCCUPANT_MOVED_OUT`, `WAITING_FOR_OCCUPANT_CASE`, `OCCUPANT_CASE_FAILED` and `BED_OCCUPIED` (policy version 2026-10-26.2),
  the case's `waitsOn` with the release of waiting cases when the awaited case closes; a case's timeline lists its own
  receiver's deliveries (`receiver` on each row) and the correction steps count a movement once. The catalogue entries (E16,
  E17), the block reasons and the scenarios S23a and S23b are the knowledge side of the same change.
- v1.27, 26 Oct 2026: questions about a case (14.2 to 14.5): `Shutter.Store.CaseQuestion` (a turn of a conversation: tier,
  source, state, the facts handed over, the answer, the members' answers, the resolved change, the runs), the Case Question
  item (`Shutter.Process.Question`, in `INSTALLITEMS`) asking the Explain agent or the board's members and coordinator through
  the Agent Board items with the context of 14.3, the record keys `question:<S>:<encounter>:<event>[:<receiver>]|<tier>|<member>|<conversation>.<turn>|<cfg>`
  for suggested turns, the checks of 14.4 (cites, confidence, fact ids; `schema_failed`), the routes under
  `/cases/{id}/questions` with the scenario's suggested conversations (5, 14.5), `questionId` on agent runs and `byQuestion`
  and `totals.questionRuns` in `GET /costs`; the question table in the case purge and `PurgeStore` (12).
- v1.26, 26 Oct 2026: the deterministic card for "Ask about this case" (14): `GET /cases/{id}/whatif`, the facts the case
  chat's agents may name, the typed suggested change validated against the profile schema.
- v1.25, 26 Oct 2026: two receivers (4, 6.3, 6.4, 12): the demo patient records system (namespace RECORDS, `/records/api`,
  Records Out, category history_of_record) fed beside the bed manager; a case is one failed delivery to one receiver
  (the open-case lookup by key and receiver; the workflow's reads, rehearsals and writes go to the case's receiver); fault
  steps name their receivers, the reset covers every demo receiver, `expected.by_receiver`, `expected.modes`; the policy
  path takes a flag alternative whose `when` holds for the case's receiver (`outcome_ref`); `receivers[].demo.namespace`;
  the seed's second receiver (profile version 6); S22.
- v1.24, 26 Oct 2026: beds at the receiver (1.1 to 1.4, 1.6): the operation's optional `bed` (PV1-3's bed component, for an
  admission or a transfer only; `ward` stays the ward); the refusal 409 `bed_occupied` with the occupant named by its
  encounter id, its `since` and its version, answered the same to a dry run, with nothing applied, no receipt and the
  version unchanged; the lock on the bed taken and on the bed left; a bed is a string of 1 to 64 characters, named within its ward; `bed` on the encounter read, its history rows and the receipt, null for a ward-level
  placement; a discharge or a transfer out frees the bed, and the encounter's own bed never conflicts. The bed is not part
  of the canonical payload, so every digest from before is unchanged. Shutter's side (the mapping of PV1-3's bed, the
  evidence, the matcher and the gate) is not built yet; and `writes` and `verification` on each `GET /cases` item (5).
- v1.23, 25 Oct 2026: system categories per receiver (6.1, 6.3, 6.4, 6.5, 10): `receivers[].category` (`current_state`,
  `history_of_record`, `orders_results`; `current_state` when absent) with `receivers[].history_policy` derived from it
  and overridable; the site-wide `history_policy` deprecated and out of the seed (profile version 5); the condition
  `receiver_category` and the facts `history_policy` and `receiver_category` read from the case's receiver, which the
  catalogue's `when`, the gate and the model view (route `category`, `history_policy`) use; `correct_history` escalates
  with `correction_steps` on the plan; an `orders_results` case escalates before any model runs and the gate appends
  `RECEIVER_NOT_MODELLED` to any write to such a receiver; gate policy version 2026-10-26.1. The gated history correction
  is written down as the planned next step, not built.
- v1.22, 25 Oct 2026: the production review (13): one read-only pass over a production Shutter knows (its own, or a watched one) through the new Case Review item (`Shutter.Process.Review`), on request only, never at the production's start, in the Doctor or on a timer. `Shutter.Util.ProductionReader` reads one production in its own namespace as plain data (the items and their settings, the system default settings, the class defaults, the event log's errors and the headers' failures over a window, the queues, the rule log and the message purge task); `Shutter.Review.Checks` holds the 23 checks' severities, confidences and words, and `Shutter.Review.Sweep` lists the targets, resolves every effective value in three explicit steps, runs the checks, ties the findings to the window's cases per item, computes the configuration fingerprint and the baseline rank and applies the annotations (`Shutter_Review.Sweep_RunJSON` and `Sweep_TargetsJSON` from SQL). The review is stored as `Shutter.Store.Review` (the last 50 per production; a review left sweeping or ranking for 20 minutes is failed by the next one) with the findings in baseline order, the fingerprint and the agent's ranking, cost and record key; approver annotations (`Shutter.Store.ReviewAnnotation`: intended, accepted risk, false positive) bind the finding's code, item, setting and effective value, are applied at read time and reopen on a changed value, an expiry or a revoke. The review's agent, `Shutter.Agent.Review` (no toolset, `KNOWLEDGE` `review`, `CONFIGVERSION` `1`, its own preamble and instructions), is asked through the Agent Board item with `MaxIterations` 3 and a 60000-token budget (`MaxIterations` is new on `AgentRequest`), answers through `Shutter.Tools.SubmitReview` and `Shutter.Schema.Review` with `Check`, and its ranking is refused (`schema_failed`) when it moves a finding above a higher severity tier; the runner maps a terminal name containing `review` to it and `AttachKnowledge` reads the agent class's `KNOWLEDGE` parameter when no board member row names a collection; the knowledge collection `review` (`knowledge/review/production-review-rules.md`, `search_review`; 6.6). The routes under `/production-reviews` (5, 13.5) and the reviews' runs in `GET /costs` (`totals.reviewRuns`, `byReview`, and `totals.spentUsd` with the reviews' live cost); the mimic does not answer review runs (4); what the review's agent sees (9); the item in `INSTALLITEMS` and the two stores in `PurgeStore` (12).
- v1.21, 25 Oct 2026: the build of 25 October. Gate policy version 2026-10-25.1, so an approval given under 2026-10-20.1 and not yet dispatched is void at dispatch (`APPROVAL_POLICY_CHANGED`). Verification after a write whose answer was lost (1.3, 5.1): the verifier's verdict is a pure function of what was read (`Judge`); a missing receipt straight after an uncertain write is unknown and read again on the retry schedule, not committed only after the settle window (`UncertainSettleSeconds`, 30 s) with the version unchanged or once the version moved past the one the write was conditional on; an acknowledged write without a receipt is a contradiction (never "not committed"), and a reconcile whose receipt is gone claims nothing about what was committed; the case escalates on not committed with the approval revoked and on unknown after the last read, never resends from a verification, and the block reasons `WRITE_NOT_COMMITTED` and `WRITE_OUTCOME_UNKNOWN` name the next action. Supersession (6.1): the matcher's later events carry `operation_key` and `case_id`; `later_delivery` (`applied`, `sent`, `none`); a time with an offset or in another form is never read as UTC and an unreadable reference time skips its own check; a doubtful cancel behind a settled transfer or discharge is a doubt; `Matcher_ForCase` takes the stored chain kind; the gate blocks a write after a later applied cancel, merge or admission and, with the verifier, names an undelivered later transfer by its key and case, whose case is told; the verifier's superseded branch reads the matcher's list, so the three agree. A write stands on its own dry run (1.1, 1.8, 6.5): the gate's rehearsal check (`REHEARSED`, `DRY_RUN_MISSING`, `DRY_RUN_FAILED`, `DRY_RUN_STALE`) releases a write only after a dry run of the same plan at the same version, epoch and payload, and the capability check's `DRY_RUN_UNSUPPORTED` refuses a resend to a receiver without dry runs; the rehearsal records what was sent (`expectedVersion`, `payloadDigest`) and the execution attempt names its rehearsal (`rehearsalId`); the approval binds the latest rehearsal of its plan; a receiver that applies a dry run is recorded as an execution, alerted and verified, never reported as rolled back; the connector refuses a dry run to a receiver whose entry declares none (6.4); the blind-resend preview refuses a receiver without dry runs (409 `dry_run_unsupported`) and reports `checkedAgainst`, `expectedVersion: null` and `applied` (5). Who decided (5): the approver of record is the signed-in user; `Shutter.Util.Workflow.Decide` takes the digest instead of a user name, refuses an approver outside the Workflow role (403 `forbidden` over the API), an empty digest and a task another approver holds (409 `wrong_state`); the approval tasks' `PlanDigest` form value is no longer pre-filled, so an inbox approver pastes it (6.4, 7.3); the 202 reply of the approval routes carries `approver`. The incident's approval binds each item (7.2 to 7.5): the incident plan's digest is the SHA-256 of the plan as recorded in canonical JSON, so each item's case, catalogue entry, outcome, who decides and expected version are bound; a released item whose fresh match names another entry or outcome than the approval bound blocks before planning and, at dispatch, `APPROVAL_ITEM_CHANGED` and `APPROVAL_INCIDENT_PLAN_CHANGED`; the case approval's `incidentPlanDigest`, `boundEntry` and `boundOutcome`. Escalation addresses (10): one bare address per recipient with one `@` and no control characters, a domain in `mail.allowed_domains` or under one; an empty or absent list allows no address, and a profile naming a team mailbox without one is refused; `mail.from` and each domain entry are checked; `subject_not_allowed`; `PATCH` requires strings and answers 400 for a value longer than its column; the operation's last check before writing or sending, and the `.eml`'s header hygiene. Escalation retention (10, 12): `purgedAt`, the text and the `.eml` removed `EscalationDays` days after the case closed (`SHUTTER_ESCALATION_DAYS`, default the message days, 90, on by default on an upgraded instance), 409 `wrong_state` for editing or sending a purged one, the case purge takes escalations and their files, the Doctor's `escalation_days`. The hand close cancels every draft or queued email and says how many, and `PATCH` and `send` refuse a case no longer blocked, escalated or failed (5, 10). Unknown keys under `approvers` and the other sections are refused by name (6.4). The API mimic (4): its switch counts on a demo instance only, a site ignoring a stray one, and `Enable` refuses there and leaves nothing behind when it fails; `GET /settings` names it (`mock`, `mockConfig`, `mockModel`, each item's `answeredBy`), `Setup.Doctor` reports `mock_config`, and the production's start logs a set switch and a `SHUTTER_AGENT_MODE` it did not apply; `Record.ImportJSON` and `ImportDir` refuse a mock recording as `Store` does (`Record.IsMock`); the live runner ends a run whose agent replaced its provider before any model call, and its `TestRun` keys each run's tool calls apart (`test:<case>:<member>:<n>`, `run_key`, `mock`) and takes `live` or `record` only; the aihub install fails when a key in the environment could not configure the provider (12). The re-plan after a receiver change happens once per investigation, and a second change blocks the case for a person (4.3); the cases list reads `planCreatedBy` from the plan row in its own query (the values it sends are unchanged); the plan, gate decision, agent run, case token, finding and approval records refer to their case by id, so a save of any of them never writes the case; a board member's request is not built, and the case is escalated, when the model view fails closed on the evidence or the findings (9). Abandoning a case the workflow left behind (5): `POST /cases/{id}/abandon` for approvers, `Shutter.Msg.CaseAbandon`, the error code `busy` with `{state, inFlight, newestAt, deferred}`, the in-flight rule and `^Shutter.Config("abandonAfterMinutes")` (15); the disposition `abandoned`; the production-start sweep and the Doctor's `working_cases` and `abandon_after_minutes` (12).
- v1.20, 25 Oct 2026: the shipped seed profile sets `mail.allowed_domains` to `example.nhs.uk`, the domain of its
  teams' mailboxes, so an escalation from the demo goes only to those mailboxes' domain; its file's `version` is 4 (6.4,
  10). Nothing in the server changes.
- v1.19, 25 Oct 2026: the fixtures (3): an NHS number as PID-3's second repetition (typed NH, 999 range, valid check digit); PV1-3 on the A08 and A03 and PV1-6 on every transfer as the PAS holds them; S9's other encounter an outpatient attendance (A04) rather than a second inpatient spell; S21, a transfer at 01:30 on the night the clocks go back; `expected.by_mode`; the step kinds' `withheld` and `indexed`.
- v1.18, 20 Oct 2026: `planCreatedBy` on the case and the cases list (5).
- v1.17, 20 Oct 2026: the roles (5). Who may call each route, in one table; changing the agent library (`PATCH /library/{code}`) needs `Shutter_Approve`, as saving the site profile does; the site profile's `approvers.close_needs_approver` (6.4; `false` by default and in the shipped seed, whose file's `version` is 3), with which closing a case by hand needs an approver and an operator's `POST /cases/{id}/close` answers 403 `forbidden`; the record of a hand closure (5) and the send's case event naming the digest of the text sent (10). The scenario runner's `manual` step, a change a person enters in the downstream system by hand, with its own source (`WARD`) and operation key, applied in process through `Downstream.Service` (4.3); scenario S20, a nurse's move while a resend awaits approval, which the version-bound approval stops at dispatch; `expected.final_reason` and `expected.last_operation_key` (3, 4.3). The API mimic (section 4): the switch `^Shutter.Config("aihub","mock")` and `Shutter.Setup.MockConfig()`; `auto` resolves to `live` while it is set; the live runner's mimic provider before `%Init`; model `mock` at cost 0 and `totals.mockRuns` in `GET /costs`; the switch read once per run, into `RunSpec.MockConfig`; record mode refused by the runner (status `refused`), by `RecordAgentMode` and by `Record.Store`, and mock recordings failed by `check-records.py`. An agent item's `ProviderConfig` is made with `%AI.Provider.Create` from the resolved configuration, with its model, as build 154 has no `CreateFromConfig`.
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
  with the message trace, header, content and event log viewing resources, never `%EnsRole_Operator`, so an approver
  reads traces, their events and the Workflow inbox and approves, and cannot start, stop or purge the production; `Setup.EnsureSecurity` applies
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
- v1.6, 17 Oct 2026: the scenario catalogue and the deterministic matcher, the condition vocabulary, the site profile and the policy path (automatic, approval, per chain), the gate's catalogue checks, the board's `search_catalogue` tool (6); incidents: detection, chains and their kinds, the plan and its approval binding the sequence rule, the ordered release through each case's own dispatch, the API, scenario S11 (7). From the decisions of 17 Oct and the T19 points (a) to (f), all taken.
- v1.5, 16 Oct 2026: rehearsal responses carry `encounter_before` and `epoch` (1.1); `POST /capabilities` takes `last_contract_check` (1.8); S8's second source system `BEDMGR` (2, 3); S9's second encounter `ENC-2009` (3); the `capabilities` step kind (3); the scenario player and the run states (4.2); section 5 points at the API as built. Points (a) to (e) were accepted on 15 Oct.
- v1.4, 15 Oct 2026: the capabilities read and the demo switch, the epoch, the receipt-lookup fault (1.8, 1.9); scenario steps that wait for a case state (4.1). From the triage of the feature documents (T9, T10, A1, A2, A5).
- v1.3, 15 Oct 2026: `misleading_duplicate_error` with an `operation_key` (1.5); `resetAt`, the runner's settings and the mode semantics (section 4), from the scenario work.
- v1.2, 15 Oct 2026: the ward decisions of 15 Oct recorded (section 1.1), with `patient_mismatch` and `payload_digest_mismatch` as their own codes.
- v1.1, 15 Oct 2026: the runner sets `^Shutter.Config("scenario")` (section 4); the repository layout.
- v1, 15 Oct 2026: first version (sections 1 to 4).
