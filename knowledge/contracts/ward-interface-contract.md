---
id: ward-interface-contract
version: 1.0
collection: contracts
applies_to: [ward-api-v1, hl7-v2.5.1-adt]
effective_from: 2026-10-01
---

# Ward Bed Management: interface contract for senders

Issued by the ward bed management system's supplier to every system that sends patient movements to it. Version 1.0,
in force from 1 October 2026.

## WIC-1 What the ward system does

WIC-1.1. The ward system keeps, for every inpatient encounter, its state (`admitted` or `discharged`), the ward the
patient is in, and a version number. It records every operation it applies in the encounter's history, which is never
changed afterwards.

WIC-1.2. Operations are applied in the order they **arrive**. The ward system stores each operation's event time but
does not reorder operations by it. A sender that delivers an older movement after a newer one moves the patient's
recorded location back to the older ward.

WIC-1.3. Every applied operation increments the encounter's version by one, including a transfer to the ward the
patient is already in, and a demographic update.

## WIC-2 Sending an operation

WIC-2.1. Operations are sent as `POST /wards/api/operations` with a JSON body. Required: `operation_key`,
`encounter_id`, `patient_id`, `patient_id_authority`, `event` (`admit`, `transfer`, `discharge` or `update`),
`event_time` (ISO 8601 UTC, for example `2026-10-15T09:20:00Z`) and `source_system`. `ward` is required for `admit` and
`transfer`, and must be null for `discharge` and `update`. Optional: `source_message_id`, `expected_version`,
`payload_digest` and `dry_run`.

WIC-2.2. **The operation key identifies the business operation, not the message.** It is
`source_system^patient_id_authority^patient_id^encounter_id^event^event_time`. The same movement sent again in a new
message keeps the same key.

WIC-2.3. **Expected version.** When `expected_version` is present, the ward system applies the operation only if the
encounter's current version equals it; otherwise it refuses with `version_conflict` and changes nothing. For an
encounter it has never seen, the current version is 0. Routine traffic may omit it; any retry or resend should send
it.

WIC-2.4. **Payload digest.** The canonical payload is the JSON object with exactly these keys in this order, no
whitespace: `operation_key`, `encounter_id`, `patient_id`, `patient_id_authority`, `event`, `ward` (null when absent),
`event_time`, `source_system`. Its digest is `sha256:` and the lower-case hex SHA-256 of its UTF-8 bytes. A sender may
send its own digest; if it differs from the ward system's, the request is refused as invalid.

WIC-2.5. **Dry run.** With `dry_run: true` the ward system validates the operation and performs it inside a
transaction that it always rolls back, then reports whether it would apply and the encounter as it would be. Nothing
is committed, no receipt is stored and no history is written.

## WIC-3 Responses

| Status | Meaning |
|---|---|
| 201 | Applied and committed. The body holds the receipt and the encounter. |
| 200, `already_committed` | An operation with this key was committed before with the same payload. Nothing new was applied; the body holds the earlier receipt. |
| 200, `rehearsal` | A dry run: `would_apply`, and either the encounter as it would be or the reason it would not apply. |
| 409 `version_conflict` | `expected_version` differed from the current version. Nothing was applied. |
| 409 `key_reused_with_different_payload` | The key was committed with a different payload. Nothing was applied. |
| 422 `invalid_transition` | The operation isn't allowed from the encounter's state (WIC-4). |
| 422 `unknown_encounter` | A transfer, discharge or update for an encounter that was never admitted. |
| 422 `invalid_request` | Missing or malformed fields, a patient that doesn't match the encounter, or a digest that doesn't match. |
| 503 `ward_unavailable` | The ward system didn't accept the request. Nothing was validated or written. |
| 504, no body | The sender didn't get the ward system's answer. **The operation may or may not have been committed.** |

WIC-3.1. **Only a receipt proves that an operation was committed.** An error status or error text tells the sender what
the ward system answered, not what it stored; after any error, timeout or unexpected answer, look the receipt up
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

WIC-5.1. `GET /wards/api/encounters/{encounter_id}` returns the state, the ward (null once discharged), the version,
the time of the last change, and the history: every applied operation in the order applied, with its version after,
event, ward, event time, time applied and operation key.

WIC-5.2. `GET /wards/api/receipts/{operation_key}` (URL-encoded) returns the receipt of a committed operation: the key,
encounter, event, ward, event time, time applied, versions before and after, payload digest and status `committed`.
A 404 `no_receipt` means the ward system did not commit an operation under that key; receipts are kept for the life of
the encounter.

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
to the integration engine or to the ward system, whatever they say.
