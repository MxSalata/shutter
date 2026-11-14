# FHIR R4: one profile, proved on a test server

## What it does

In this release the receiver must be InterSystems IRIS for Health's own FHIR R4 server. The capability check reads a proof document as `tests/conformance/fhir_conformance.py` writes it after a run with no differing exchange, and the conformance file holds that server's answers. The document is not signed: whoever imports one vouches that the run took place. No other FHIR server can pass it, except Shutter's own test server, which is held to those answers. A run compares the status, the headers and the fields the file records for each exchange, not the whole answer.

What this profile does: for a receiver entry that carries a `fhir` object, a failed A02 (transfer) that names no bed, whose HL7 delivery a stock `EnsLib.HL7.Operation.TCPOperation` gave up on before a connection opened, becomes at most one person-approved `PUT Encounter/{id}` with `If-Match`. Before closing the case Shutter finds the version carrying its marker in the Encounter's history as the receiver returned it, reads that version back by its version id when the receiver's answer named one, checks it against the approved base, and checks that the current record has not undone the move.

The one operation: complete the open ward-level `location` entry at the event time, append one active entry for the target ward, add Shutter's marker tag. Nothing else in the body changes.

### The site profile entry

The entry is named after the engine item that failed (the stock TCP operation), as every entry is. It has no `api` and no `features`: capability is read from the server. The server, port, TLS and credential are adapter settings of the FHIR items, and `base` is the path in front of every request. One FHIR receiver per install in this version, and the validator refuses a second.

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

### Turning it on at a site

```
# 1. The entry: GET /api/shutter/site-profile, add the receiver entry of fhir.md with "recovery_enabled": false, PUT it back.
# 2. In a terminal, in Shutter's namespace: the credential and the four items.
Do ##class(Ens.Config.Credentials).SetCredential("FHIRServer", "<user>", "<password>", 1)
Write ##class(Shutter.FHIR.Install).PlaceItems("<host>", "<port>", "FHIRServer", "<TLS configuration, or empty>").%ToJSON()
# 3. The conformance run, against a TEST instance of the same server software: it creates and deletes resources.
FHIR_PASSWORD=<password> python3 tests/conformance/fhir_conformance.py --base https://<test host>/<base> --target iris --user <user> --proof proof.json
Do $SYSTEM.Status.DisplayError(##class(Shutter.Store.FHIRProof).ImportFile("<receiver name>", "<path>/proof.json"))
# 4. Confirm (items_problem empty, endpoints_agree true, proof "matches"), then PUT the entry again with "recovery_enabled": true.
Write ##class(Shutter.FHIR.Install).Doctor().%ToJSON()
```

## What stops it

Every stop names its reason, and an unknown blocks. The FHIR gate (policy `fhir-2026-11-14.1`) decides at the proposal and again at dispatch; the codes below are the FHIR profile's own, grouped by what they guard, with the words a case shows. The gate also keeps main's rows where they apply (the message's conformance, the plan's intent, further and pending messages, the approval, fresh evidence, the catalogue), with main's codes and meanings.

### Before anything is read or planned

| Code | What the case says |
| --- | --- |
| `FHIR_ITEMS_MISSING` | The site profile describes a FHIR receiver, but the production's FHIR items are missing, switched off or set to different servers, so nothing was read or sent. |
| `FHIR_ITEM_ERROR` | A FHIR item of the production answered with an error before anything was sent. Nothing was written. |
| `FHIR_PLAN_NEEDS_PERSON` | For a FHIR receiver Shutter proposes one thing only, the ward move the failed message asked for: in Rules only mode always, in every other mode when one catalogue entry says to send it. Here that did not hold, or the plan asks for a person, so a person decides. |

### Finding the record

| Code | What the case says |
| --- | --- |
| `FHIR_RECEIVER_UNREADABLE` | The FHIR server did not answer, or answered with something that is not its own answer for this request (a sign-in page, a plain 404, another media type). Nothing is assumed about the record. |
| `FHIR_ENCOUNTER_NOT_FOUND` | No Encounter carries this visit number under the identifier system the site profile names. |
| `FHIR_ENCOUNTER_AMBIGUOUS` | More than one Encounter carries this visit number, or the search came in pages, so which record the message meant is not known. |
| `FHIR_IDENTIFIER_UNMAPPED` | The message's patient identifier does not come from the assigning authority the site profile maps to the FHIR identifier system, or the Encounter read does not carry the visit number that was searched. |
| `FHIR_SUBJECT_UNRESOLVED` | The Encounter's subject is not a literal reference to a Patient, or that Patient could not be read. |
| `FHIR_PATIENT_MISMATCH` | The Encounter belongs to a Patient who does not carry the message's patient identifier. |
| `FHIR_PATIENT_LINKED` | The Patient record is linked to another or is not active, which often means a merge. A person decides. |

### The message and the switch

| Code | What the case says |
| --- | --- |
| `FHIR_EVENT_UNSUPPORTED` | Over FHIR Shutter makes one kind of change, a ward move on an existing Encounter. This message is another kind of event. |
| `FHIR_FAILURE_KIND_UNSUPPORTED` | Over FHIR Shutter repairs only a delivery that failed or whose outcome is uncertain. This message was rejected, withheld or could not be read, so the receiver or the site already said no to it. |
| `FHIR_RECOVERY_DISABLED` | The receiver's entry in the site profile does not turn recovery on (fhir.recovery_enabled), so nothing is written to it. |

### The record as read

| Code | What the case says |
| --- | --- |
| `FHIR_REPRESENTATION_PARTIAL` | The server returned a reduced copy of the Encounter (marked SUBSETTED). A change built on part of a record would remove the rest. |
| `FHIR_MODIFIER_EXTENSION` | The Encounter carries a modifierExtension, which can change what its other fields mean. Shutter does not change such a record. |
| `FHIR_NARRATIVE_PRESENT` | The Encounter carries a narrative text, which the server does not regenerate. After the move it would describe the old ward. |
| `FHIR_RESTRICTED` | The Encounter carries a security label. Shutter does not change a labelled record. |
| `FHIR_NO_ETAG` | The read came with no ETag, or one that does not name the version read, so a write could not be made conditional on it. |
| `FHIR_STATUS_NOT_IN_PROGRESS` | The Encounter is not in progress, so a ward move no longer applies to it. |
| `FHIR_ALREADY_THERE` | The Encounter already shows the patient on the ward the message moves them to. Shutter cannot tell who made that change, so it takes no credit and sends nothing. |

### Order, time and the engine

| Code | What the case says |
| --- | --- |
| `FHIR_LATER_MOVE_AT_RECEIVER` | The Encounter shows a location that starts at or after the failed message's event time. Sending the older move would undo it. |
| `FHIR_PRIOR_LOCATION_DIFFERS` | The Encounter's open location is not the ward the message says the patient came from, or the message names none. |
| `FHIR_TIME_UNREADABLE` | A location entry's start is not a time with an offset that Shutter can order against the message's event time. |
| `FHIR_ENGINE_NOT_IN_SCOPE` | The delivery that failed did not go through a stock HL7 TCP operation, so whether the engine is still trying it cannot be read. Unknown is not nothing pending. |
| `FHIR_ENGINE_SUBCLASS_UNPROVEN` | The delivery went through a subclass of the stock HL7 TCP operation. What the engine's record proves was measured for the stock class only. |
| `FHIR_ENGINE_DELIVERED` | The engine delivered this message over HL7. Whatever the receiver then answered, it was handed the move once, so Shutter does not write it again over FHIR. |
| `FHIR_ENGINE_HOLDS_SUSPENDED` | The engine holds this message suspended, and anyone can send it again. Discard it in the source production, then reinvestigate. |

### The wards

| Code | What the case says |
| --- | --- |
| `FHIR_LOCATION_UNMAPPED` | The ward the message names has no Location in the site profile's map. |
| `FHIR_LOCATION_UNREADABLE` | A mapped Location could not be read, so it could not be checked. |
| `FHIR_LOCATION_MISMATCH` | A mapped Location is not active, or does not carry the identifier the site profile recorded for it. |

### The change

| Code | What the case says |
| --- | --- |
| `FHIR_SHAPE_UNSUPPORTED` | The Encounter's location entries are not the one shape Shutter changes: exactly one open, mapped, ward-level entry. |
| `FHIR_BED_MOVE_UNSUPPORTED` | The message names a bed. An Encounter's version does not reserve a bed, so this version moves wards only and sends nothing for a move that names one. |
| `FHIR_DIFF_OUT_OF_BOUNDS` | The change Shutter built touches more than the closed entry, the new entry and its marker. Nothing is sent. |
| `FHIR_BODY_CHANGED` | The update built from the read made just before the write is not the one the person approved. |

### The approval and the versions it is bound to

| Code | What the case says |
| --- | --- |
| `FHIR_NO_BINDING` | The approval is not tied to a sealed record of what it approved (the version, the body, the Locations), so it authorises nothing. |
| `FHIR_APPROVAL_NOT_PERSONAL` | A FHIR update goes only on a person's approval of this one case. This approval came from a policy or an incident. |
| `FHIR_RECEIVER_CHANGED` | The Encounter is at another version than the one the person approved against. The approval is void. |
| `FHIR_PATIENT_CHANGED` | The Patient record changed after the approval. The approval is void. |
| `FHIR_LOCATION_CHANGED` | A mapped Location changed after the approval. The approval is void. |
| `FHIR_EARLIER_WRITE_UNRESOLVED` | An earlier update of this case, conditional on this same version, has no known outcome and may yet land. Nothing is sent until the record moves on or a person settles it. |

### The server and its history

| Code | What the case says |
| --- | --- |
| `FHIR_CAPABILITIES_UNREADABLE` | The server's CapabilityStatement could not be read, so what it guarantees is not known. |
| `FHIR_NO_HISTORY` | The server does not offer read, version read, update and instance history for Encounters, so a write could not be checked afterwards. |
| `FHIR_VERSIONING_UNPROVEN` | No conformance run recorded for this server software shows that it refuses a stale and an unknown If-Match and keeps a version's tags on that version, or the server now names other software or another version than the run measured. |
| `FHIR_HISTORY_UNAVAILABLE` | The Encounter's history could not be read whole. |
| `FHIR_HISTORY_HEAD_DIFFERS` | The newest version in the Encounter's history is not the version that was read. |
| `FHIR_ALREADY_WRITTEN` | A version in the Encounter's history carries the marker of an update this case already sent. Nothing is sent again. |

### After the write

| Code | What the case says |
| --- | --- |
| `FHIR_WRITE_REFUSED` | The update was not applied: the receiver refused it, or Shutter's own last checks stopped it before anything was sent. |
| `FHIR_WRITE_CONFLICT` | The receiver refused the update because the Encounter changed after it was read (412). It is not retried: any further write needs fresh evidence and a new approval. |
| `FHIR_WRITE_OUTCOME_UNKNOWN` | What became of the update cannot be established from what the receiver returned. Shutter does not repeat it. A person checks at the receiver. |
| `FHIR_WRITE_NOT_FOUND` | No version of this update is in the history the receiver returned. A returned history is not a proof that none was committed. The approval is spent. |
| `FHIR_COMMITTED_NEEDS_REVIEW` | The approved update is in the Encounter's history, but the current record no longer shows it as it was written. The case stays open for a person. |
| `FHIR_WRITE_CONTRADICTED` | The receiver's record contradicts the update, for example a version that carries Shutter's marker but does not follow the version the write was conditional on. A person checks at the receiver. |

## What the case shows

- **The base ETag.** The approval is bound to the version read, by its ETag as the server gave it, to the exact body by its digest, and to the Patient and Location versions. The dispatch gate reads them all again and compares them as strings. The approver's task names the ETag verbatim.
- **No dry run exists for this receiver.** Every decision of the FHIR gate carries the row `FHIR_NO_DRY_RUN_SUBSTITUTED`, at both stages, and says what stands in its place: "No dry run exists for this receiver. Substituted: a complete versioned read, a bounded change, If-Match on the version read, this case's own approval by a person, and a search of the returned history for the marked version, read back by id when the answer named it." A plan that sends nothing reads "No dry run exists for this receiver. This plan sends nothing." The case's headline and the approver's task say so too.
- **Version ids are quoted.** They are kept as the server gave them and never read as numbers, so the case shows `"2"`, not 2.
- **The six verdicts,** in the verifier's own sentences (a value in angle brackets is the version id or the reason as read):

| Verdict | What the case reads | The case |
| --- | --- | --- |
| verified | Verified in Encounter version "&lt;v&gt;": the approved location update is present, carrying Shutter's marker; no other field changed from version "&lt;base&gt;", the version the write was conditional on. | resolved |
| verified, a later change followed | Verified in Encounter version "&lt;v&gt;": the approved location update is present, carrying Shutter's marker. The current resource is version "&lt;current&gt;"; a later change followed. | resolved |
| committed, for review | The approved update is present in version "&lt;v&gt;". The current record needs review: &lt;why&gt;. A person checks at the receiver. | escalated, `FHIR_COMMITTED_NEEDS_REVIEW` |
| unknown | The update's outcome is unknown: &lt;why&gt;. Shutter will not repeat it until its committed history can be established. | read again at about 10, 30 and 70 seconds; then escalated, `FHIR_WRITE_OUTCOME_UNKNOWN` |
| not found | No version of this update was found in the history the receiver returned, from version "&lt;head&gt;" back to the base "&lt;base&gt;"; the receiver's history is not a proof that none was committed. | escalated, `FHIR_WRITE_NOT_FOUND` |
| failed | The receiver's record contradicts the update: &lt;why&gt;. A person checks at the receiver. | escalated, `FHIR_WRITE_CONTRADICTED` |

Only "verified" and "verified, a later change followed" resolve a case. After any other verdict the approval is spent and nothing automatic follows.

## The marker

On IRIS for Health (2026.2, 2026.3.0AI.154, 2027.1.0AI.109) the tag stays on Shutter's own version in the record's history; the next writer that does not send it back removes it from the current record. Shutter never removes it and never calls `$meta-delete`, which IRIS does not offer.

## How it was proved

- **Unit classes,** all green in the whole unit suite on IRIS for Health 2026.2 (1243 passed, 0 failed): `Shutter.Test.FHIRProfile` (the entry and its validator), `FHIRReader` and `FHIRTrust` (the reads, the projection and what counts as the receiver's own answer), `FHIRStores` (the binding, the one-write fence, the sealed read, the proof), `FHIRPlan`, `FHIRPlanJudge` and `FHIRProposal` (the one body), `FHIRGate` (every row, at both stages), `FHIRExecute` (the write, its classifier, the fence and the admission), `FHIRVerify` and `FHIRJudge` (the walk and the six verdicts), `FHIRFlow` (the case's path and its every stop), `FHIRInstall` (the four items), `FHIRFacade` and `FHIRFacadeConformance` (the test server), and `SnapshotMaterial` (every recorded snapshot's material digest unchanged).
- **End to end:** `tests/e2e/fhir_receiver_check.py` on a demo install against the test server, variants 0, A, B, C and D: no proof yet blocks, the move is approved by a person and verified, a lost answer is verified from the history, Shutter's update is refused with a 412 after another writer's change and is not retried, and a switched-off entry sends nothing.
- **The conformance file:** 245 exchanges in the conformance file, 244 for the test server and 236 for IRIS for Health. The test server's 244 were run over HTTP on 2026.2 with none differing, and that run wrote the proof file the gate reads.
- **What was measured about IRIS for Health's FHIR server,** on 2026.2, 2026.3.0AI.154 and 2027.1.0AI.109, identically: a stale or unknown ETag in `If-Match` answered 412 and wrote nothing; the ETag is `W/"versionId"`; a good write answers 200 with an empty body; each `PUT` replaces `meta.tag`; the smallest role that can write is `FHIR_API:RW`.
- **The engine:** what the engine's record proves was measured on 2026.2 only.
- Not tested: a restart of the production with a case in flight, the engine still retrying end to end, and history faults over HTTP.

## Limits

- One FHIR receiver per install.
- A move at the receiver within the site's source skew (300 seconds unless the profile says otherwise) of the failed message's event time stops the case for a person.
- An A02 that names a bed stops for a person: this version moves wards only.
- The failed delivery must be a stock HL7 TCP operation whose engine record can be read and whose attempts all failed before a connection opened; any other source stops for a person.
- After a FHIR update, do not resend the original HL7 message from the engine. Shutter stops while the engine holds the message suspended, and it cannot stop a message that is resent later by hand.
- A proof is a conformance run against the same server software and version as the endpoint names, not against the endpoint itself. Shutter checks the proof document's shape, not its origin: it is not signed, and whoever imports one vouches that the run took place.
- Turning the profile on takes the API and a terminal; the Site profile page shows a FHIR entry and does not edit it.
- Shutter signs in with a user name and password (an IRIS credential). OAuth is not supported, and TLS is passed to the adapter and was not measured.
- Shutter's FHIR credentials can write every resource type the endpoint allows them; a narrower grant is the site's to configure.
- A FHIR case is planned by Rules only, by the catalogue or by a person, never by the board.
- A later change to fields other than status and location is not judged.
- A login failure reads as an unreadable server, never as a missing Encounter; that answer was measured on IRIS for Health only.
- In the escalation draft the Encounter's first ward is listed as a transfer.

## Not built

- Replacing the active location entry, and bed-level shapes.
- Marker modes other than a required tag, and server-owned fields to ignore.
- Paged history.
- An automatic new plan after a 412: a person reinvestigates the case, which reads fresh evidence and asks for a new approval.
- A Receiver check variant for a FHIR update, and a FHIR panel on the case page.
- Further faults in the test server: a second writer making the same change, a history that answers 503, a dropped tag.
- A FHIR demo receiver in the seed, and a playable scenario on the Scenarios page and the online demo.
- Evaluation rows for FHIR cases, and precedents for FHIR approvals.
- A later automatic settle of an unknown write.
- OpenAPI schema notes.
- A second FHIR receiver in one install.
