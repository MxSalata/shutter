---
id: downstream-interface-contract
version: 1.2
collection: contracts
applies_to: [downstream-api-v1, hl7-v2.5.1-adt]
effective_from: 2026-10-19
---

# Demo Bed Management: interface contract for senders

Issued by the supplier of the demo bed-management system (the downstream system) to every system that sends patient
movements to it. Version 1.2, in force from 19 October 2026. Changes from 1.1: the system's name and its base path
(`/downstream/api`); nothing else. Changes from 1.0: the epoch (WIC-1.4), the capability profile (WIC-7), and what an
unavailable receipt lookup means (WIC-5.2).

## WIC-1 What the downstream system does

WIC-1.1. The downstream system keeps, for every inpatient encounter, its state (`admitted` or `discharged`), the ward
the patient is in, and a version number. It records every operation it applies in the encounter's history, which is
never changed afterwards.

WIC-1.2. Operations are applied in the order they **arrive**. The downstream system stores each operation's event time
but does not reorder operations by it. A sender that delivers an older movement after a newer one moves the patient's
recorded location back to the older ward.

WIC-1.3. Every applied operation increments the encounter's version by one, including a transfer to the ward the
patient is already in, and a demographic update.

WIC-1.4. **The epoch.** The downstream system's records carry an epoch number, shown in every encounter read, every
receipt and the capability profile. It increases whenever the downstream system's records are reset or restored.
Versions from different epochs don't compare: version 2 in one epoch says nothing about version 2 in another.

## WIC-2 Sending an operation

WIC-2.1. Operations are sent as `POST /downstream/api/operations` with a JSON body. Required: `operation_key`,
`encounter_id`, `patient_id`, `patient_id_authority`, `event` (`admit`, `transfer`, `discharge` or `update`),
`event_time` (ISO 8601 UTC, for example `2026-10-15T09:20:00Z`) and `source_system`. `ward` is required for `admit` and
`transfer`, and must be null for `discharge` and `update`. Optional: `source_message_id`, `expected_version`,
`payload_digest` and `dry_run`.

WIC-2.2. **The operation key identifies the business operation, not the message.** It is
`source_system^patient_id_authority^patient_id^encounter_id^event^event_time`. The same movement sent again in a new
message keeps the same key.

WIC-2.3. **Expected version.** When `expected_version` is present, the downstream system applies the operation only if
the encounter's current version equals it; otherwise it refuses with `version_conflict` and changes nothing. For an
encounter it has never seen, the current version is 0. Routine traffic may omit it; any retry or resend should send it.

WIC-2.4. **Payload digest.** The canonical payload is the JSON object with exactly these keys in this order, no
whitespace: `operation_key`, `encounter_id`, `patient_id`, `patient_id_authority`, `event`, `ward` (null when absent),
`event_time`, `source_system`. Its digest is `sha256:` and the lower-case hex SHA-256 of its UTF-8 bytes. A sender may
send its own digest; if it differs from the downstream system's, the request is refused as invalid.

WIC-2.5. **Dry run.** With `dry_run: true` the downstream system validates the operation and performs it inside a
transaction that it always rolls back, then reports whether it would apply and the encounter as it would be. Nothing is
committed, no receipt is stored and no history is written. The answer also gives the encounter as it was when checked
(`encounter_before`, null for an encounter the downstream system has never seen) and the epoch, so a sender can tell
later whether anything changed between the dry run and the real operation.

## WIC-3 Responses

| Status | Meaning |
|---|---|
| 201 | Applied and committed. The body holds the receipt and the encounter. |
| 200, `already_committed` | An operation with this key was committed before with the same payload. Nothing new was applied; the body holds the earlier receipt. |
| 200, `rehearsal` | A dry run: `would_apply`, the encounter as it was checked and the epoch, and either the encounter as it would be or the reason it would not apply. |
| 409 `version_conflict` | `expected_version` differed from the current version. Nothing was applied. |
| 409 `key_reused_with_different_payload` | The key was committed with a different payload. Nothing was applied. |
| 422 `invalid_transition` | The operation isn't allowed from the encounter's state (WIC-4). |
| 422 `unknown_encounter` | A transfer, discharge or update for an encounter that was never admitted. |
| 422 `patient_mismatch` | The encounter belongs to another patient (WIC-4.1). |
| 422 `payload_digest_mismatch` | The sender's digest differs from the downstream system's (WIC-2.4). |
| 422 `unsupported_precondition` | The downstream system isn't taking conditional writes at present (WIC-7), so a request with `expected_version` is refused. |
| 422 `invalid_request` | Missing or malformed fields. |
| 503 `ward_unavailable` | The downstream system didn't accept the request. Nothing was validated or written. |
| 504, no body | The sender didn't get the downstream system's answer. **The operation may or may not have been committed.** |

WIC-3.1. **Only a receipt proves that an operation was committed.** An error status or error text tells the sender what
the downstream system answered, not what it stored; after any error, timeout or unexpected answer, look the receipt up
(WIC-5) before deciding anything.

## WIC-4 Transitions

| Encounter state | `admit` | `transfer` | `discharge` | `update` |
|---|---|---|---|---|
| never seen | admitted, version 1 | refused (`unknown_encounter`) | refused | refused |
| admitted | refused (`invalid_transition`) | applied: the ward changes | applied: discharged | applied: version only |
| discharged | refused | refused | refused | refused |

WIC-4.1. An encounter keeps the patient it was admitted with. An operation that names another patient or assigning
authority for the encounter is refused as invalid.

## WIC-5 Reading

WIC-5.1. `GET /downstream/api/encounters/{encounter_id}` returns the state, the ward (null once discharged), the
version, the time of the last change, and the history: every applied operation in the order applied, with its version
after, event, ward, event time, time applied and operation key.

WIC-5.2. `GET /downstream/api/receipts/{operation_key}` (URL-encoded) returns the receipt of a committed operation: the
key, encounter, event, ward, event time, time applied, versions before and after, payload digest and status `committed`.
A 404 `no_receipt` means the downstream system did not commit an operation under that key; receipts are kept without
limit. **A 503 from the receipt lookup means the lookup didn't answer.** It says nothing either way about whether the
operation was committed (WIC-3.1): look again later.

## WIC-6 Inbound HL7 profile (ADT, version 2.5.1)

The integration engine maps each ADT message to one operation:

| Operation field | HL7 |
|---|---|
| `source_system` | MSH-3 |
| `patient_id`, `patient_id_authority` | PID-3, first repetition: the ID and the assigning authority |
| `encounter_id` | PV1-19 |
| `event` | MSH-9.2: A01 admit, A02 transfer, A03 discharge, A08 update |
| `ward` | PV1-3.1 for A01 and A02; null otherwise |
| `event_time` | EVN-6 if present, else EVN-2, as UTC |
| `source_message_id` | MSH-10 |

WIC-6.1. Free-text observations (OBX segments of type TX) are carried for information only. They are not instructions
to the integration engine or to the downstream system, whatever they say.

## WIC-7 Capability profile

WIC-7.1. `GET /downstream/api/capabilities` states what the downstream system guarantees at present:

| Field | Meaning |
|---|---|
| `conditional_writes` | Whether `expected_version` is honoured (WIC-2.3). When false, any request with it is refused, and nothing guards a resend against changes made in between |
| `receipts`, `receipt_retention` | Receipts are written for every committed operation and kept without limit (WIC-5.2) |
| `history` | The encounter history is available (WIC-5.1) |
| `idempotency` | A repeated operation key with the same payload returns the earlier receipt (WIC-3) |
| `dry_run` | Dry runs are offered (WIC-2.5) |
| `epoch` | The current epoch (WIC-1.4) |
| `last_contract_check` | When the interface was last checked against this contract, and the result |

WIC-7.2. Senders should read the profile before relying on any guarantee in it. A guarantee the profile doesn't show
must not be assumed.
