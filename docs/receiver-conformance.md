# Receiver conformance kit

Before a site adds a recovery API to a receiver's profile, and after that receiver, its adapter or the contract changes, an interface engineer and the receiver's supplier need one answer: which parts of Shutter's recovery contract did this declared test endpoint demonstrate, on this build and configuration?

The kit answers that and nothing more. It does not certify a supplier, does not enable recovery and changes nothing in Shutter: a report has no authority over the gate, and no route or profile field reads one. A pass describes one endpoint during one run.

```
python3 scripts/receiver-conformance.py init --run-id SITE-TEST-01 \
    --base-url https://receiver-test.example.invalid/downstream/api \
    --receiver-identity "the test instance's id" --receiver-build "its build and configuration" \
    --credential-scope "a test user with the API role only" --attestation "reference to the approved test scope" > manifest.json

export SHUTTER_CONFORMANCE_USER=... SHUTTER_CONFORMANCE_PASSWORD=...
python3 scripts/receiver-conformance.py run --manifest manifest.json --out report-01 --operator "your name"
```

The second command asks you to type the origin. With no terminal, `--confirm-origin` must give it exactly, and the report records that as a deviation. `--ca-file` names a private CA. It needs Python 3 and nothing else, and writes three files into an empty folder: `report.txt`, `report.json` and `journal.jsonl`.

Exit status: 0 all required checks passed, 1 they did not, 2 the run was refused.

## The manifest

`tests/conformance/manifest.schema.json` is the whole of it, and no field can carry a path, a request or a credential. `init` writes one with generated identities. Every encounter, patient, ward and bed must be declared before the run, and a run needs at least 60 encounters and 40 beds. Encounters start `SHUTTER-TEST-`, patients `SYNTHETIC-`, wards `SHUTTER-TEST-` and beds `TEST-`. A second run on one endpoint needs a new run id, and so new identities: encounters, wards and beds are never reused, because the kit deletes nothing and an earlier run's beds stay occupied. A manifest that reuses a ward and bed an earlier run still holds stops at rule 8.

## What it refuses

1. Anything but `environment: TEST` and the exact origin confirmed.
2. A redirect (never followed), an origin other than the manifest's, a certificate that fails to verify or changes during the run, and plain http except on loopback.
3. Any path or body it did not generate. The routes it can call are `GET /capabilities`, `POST /operations`, and `GET /encounters/...` and `GET /receipts/...` for declared encounters and generated keys. Check 11's wrong requests are its own fixed table.
4. An undeclared encounter, patient, ward or bed, or a key it did not generate.
5. A key or encounter it cannot show to be absent first, by the exact 404 of check 2.
6. An encounter that already exists. There is no resume: start again with new identities.
7. An answer about another identity: the run stops.
8. An occupied bed held by an encounter outside the declared set: the run stops, since the endpoint is not the isolated one it was said to be.
9. `POST /reset`, `POST /faults` and `POST /capabilities`, always. Faults are made in the kit's own loopback proxy instead.
10. Deleting anything. What it created stays, and the report lists it.
11. Writing over a journal. The journal is append-only and chained by digest, and its digest is in the report. The credential reaches neither the journal nor the report.
12. Running with no credential, unless the manifest declares `credential_scope: "none"`. Use a test credential scoped to the API alone: for the demo receiver, one with `Downstream_API` and not `Downstream_Admin` (`docs/CONTRACTS.md`, 1.10).

These rules limit what the kit sends. They cannot establish from a URL or a confirmation that the server holds no real patients. Isolation stays with the operator and the supplier.

## The report

Each check reads `pass`, `fail`, `not_run` or `not_supported`, with its subchecks and the journal lines that are its evidence. The summary says "All required checks passed" only when every required check reads `pass`. `not_run` is never counted as a pass. A receiver that doesn't declare conditional writes, receipts, history and dry run, or whose capabilities can't be read, fails check 1, and the checks that write read `not_supported`, since nothing is sent to it.

Check 24 is evidence about the kit, not the receiver. Check 25 is not required: the kit issues no reset and runs no Shutter, so it reads `not_run`, even after an operator's reset in a disposable environment and `--prior-report` showing that the epoch moved. If the epoch has not moved, it fails. Check 22 reads `pass` on the receiver's half and shows Shutter's own read-back as a `not_run` subcheck: `tests/e2e/lost_answer_check.py` and scenario S3 exercise that, on an installation with Shutter.

**Conforming isn't the same as being safe to recover to.** A receiver can answer check 16 exactly as the contract says, returning the original receipt for a repeated key that names another bed, and a sender that fails to compare the bed is still wrong for that case.

## Cancels and merges

These are a declared extension of a receiver whose site profile says `cancels: true` or `merges: true` (`docs/CONTRACTS.md`, 1.1). The kit sends neither and claims nothing about them, and the report lists both as `not_run`.

## The checks

| # | Stimulus | Passes when | Contract |
|---|---|---|---|
| 1 | GET /capabilities | A strict JSON object that declares conditional_writes, receipts, history and dry_run true, an integer epoch, and a retention and idempotency statement, which the report records. A receiver without one of them, or whose answer cannot be read, is not tested further: the other checks read not_supported. | 1.8 |
| 2 | GET an unknown encounter and an unknown receipt | Exactly 404 unknown_encounter and 404 no_receipt as JSON, not an HTML page or an unrelated 404. Until this passes absence cannot be established, so nothing is written. | 1.2, 1.3 |
| 3 | Dry run of an admission at expected version 0 | 200, would_apply true, encounter_before null, encounter_after consistent with the plan. Afterwards there is still no encounter, history or receipt. | 1.1, 1.4 |
| 4 | Real admission at expected version 0 | 201, applied true, one admitted state at version 1, one history row and a matching committed receipt, in the answer and in the reads. | 1.1, 1.2, 1.3, 1.4 |
| 5 | Repeat a committed operation, with another source_message_id and the old expected version | 200 already_committed with the original receipt; no new history row or version. | 1.1, 1.6 |
| 6 | The committed key with another ward and a correctly recomputed digest | 409 key_reused_with_different_payload; nothing changes. | 1.1, 1.6 |
| 7 | A new key with an incorrect payload digest | 422 payload_digest_mismatch; no change and no receipt. | 1.1, 1.6 |
| 8 | A new operation at the wrong expected version | 409 version_conflict that reports the expected and the correct current version; no change and no receipt. | 1.1, 1.4 |
| 9 | An operation for an encounter with another declared synthetic patient | 422 patient_mismatch; the encounter's identity does not change. | 1.1, 1.2 |
| 10 | Transfer, update and discharge of a declared encounter the receiver has never seen | 422 unknown_encounter each time; no encounter and no receipt. | 1.1, 1.4 |
| 11 | Missing fields, an invalid event, malformed beds and times, a ward or bed where none belongs, a body that is not an object | 422 invalid_request for each, reported as its own subcheck; nothing is written. | 1.1 |
| 12 | A valid transfer, update and discharge in turn | A transfer changes the placement, an update does not, a discharge clears it; each adds one version and one history row with the exact operation. | 1.1, 1.2, 1.3, 1.4 |
| 13 | Admit an admitted encounter; transfer, update, discharge and admit after a discharge | 422 invalid_transition with state and event; state, history and receipts do not change. | 1.1, 1.4 |
| 14 | Place a second encounter in an occupied bed, as a real call and as a dry run | 409 bed_occupied both times, naming the declared occupant by encounter id, since and version and no patient identifiers; neither encounter changes. An occupant outside the declared set stops the run. | 1.1 |
| 15 | Bed freeing and conflict scope: transfer out, discharge, transfer to ward level, own bed, ward level, the same bed name on another ward | A freed bed can be taken; the encounter's own bed, a ward-level placement and the same name on another ward never conflict. | 1.1, 1.2 |
| 16 | Repeat a committed key with only the bed changed | 200 already_committed, with the receipt and encounter still showing the original bed. The bed is outside the payload digest, so a sender must compare it: conforming here does not make such a sender safe. | 1.1, 1.6 |
| 17 | Two different operations at once at the same expected version | Exactly one commits; the other is 409 version_conflict or 503 ward_unavailable; no partial state or duplicate version. | 1.1, 1.4 |
| 18 | Two identical operations at once | One business effect, one history row and one receipt, whichever answer arrives first. | 1.1, 1.3 |
| 19 | Two placements at once into one bed; a dry-run transfer out of a bed at the same time as a real placement into it | Never two occupants, and never a placement into a bed that only an uncommitted dry run seemed to free. A pass means no such result in the rounds run, not that none is possible. | 1.1 |
| 20 | Dry runs that would be refused | 200 would_apply false with the refusal as reason (bed_occupied is 409 itself, check 14); nothing persists and no receipt appears. | 1.1 |
| 21 | Compare what was sent with the receipt, the history row and the encounter for every committed operation | Key, encounter, event, event time, ward, bed, digest and versions agree on the receipt and the history row, patient and authority on the encounter (the receipt carries no patient). A matching key alone is not enough. | 1.2, 1.3, 1.6 |
| 22 | The kit's loopback proxy drops the answer after the receiver has answered | The sender saw no answer; the committed operation is found by receipt and in the history, without a second write. Shutter's own read-back is not exercised by the kit. | 1.3, 5.1 |
| 23 | The proxy holds a write past the sender's timeout, holds an answer, and answers a receipt lookup with 503 | No answer is unknown, never absence, and after the proxy's own 503 the direct read still finds the commit; a 404 read while a write is in flight is not final. The report gives the observed timing and infers no maximum commit delay. | 1.3, 1.9, 5.1 |
| 24 | The kit against its own mutant stubs: an HTML 200, malformed JSON, a wrong identity, partial history, a mismatched receipt; and its own reading of no answer, a 503 and an HTML 404 | The kit rejects each, reads those three as unknown, and passes the correct stub. This is evidence about the kit, not about the receiver. | 1.1, 1.2, 1.3 |
| 25 | An operator's reset or restore outside the kit, in a disposable environment | The epoch has moved since an earlier report, and Shutter refuses old approvals in its own integration test. The kit issues no reset and runs no Shutter, so this is not_run unless the epoch comparison fails. | 1.7, 1.8 |
| 26 | Read earlier committed history and receipts again after later operations | They have not changed during the run. Retention beyond the run remains the receiver's declaration. | 1.2, 1.3 |

`tests/conformance/contracts-v1.json` is this table as data.

## Its own tests

`python3 tests/conformance/test_kit.py` needs no IRIS. `tests/conformance/stubs/receiver_stub.py` is a receiver in memory: correct by default, and wrong in one named way as a mutant. The correct stub must pass every check the kit can run, each mutant must fail the check it is named against, and each refusal above must hold. A mutant's failure shows what the kit detects. It doesn't show that a supplier cannot lie.

## Against the demo receiver

```
python3 scripts/receiver-conformance.py init --run-id DEMO-01 --base-url http://127.0.0.1:52773/downstream/api \
    --receiver-identity "demo receiver" --receiver-build "this repository" \
    --credential-scope "downstream-client: Downstream_API only" --attestation "a disposable demo instance" > manifest.json
SHUTTER_CONFORMANCE_USER=downstream-client SHUTTER_CONFORMANCE_PASSWORD=... \
    python3 scripts/receiver-conformance.py run --manifest manifest.json --out report-01 \
    --confirm-origin http://127.0.0.1:52773
```
