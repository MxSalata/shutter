# What a receiver needs for Shutter to recover to it

A case resends a failed message only to a receiver that can answer four questions: where is this encounter now, did this exact operation land, can you rehearse it, and will you refuse it if the encounter has moved. A receiver that cannot has its cases investigated and escalated, never resent (the last section). An outage's resend through the engine, at a receiver set up for it, is a separate path that this contract does not govern ([the install guide, section 11](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md#11-a-receivers-outages-v110)).

## The endpoints

The paths are the site profile's (`receivers[].api`, [CONTRACTS 6.4](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#64-the-site-profile-and-the-policy-path)); these are the demo's.

| Endpoint | What it must do |
|---|---|
| `POST /operations` | Apply one movement. With `expected_version`, apply only at that version, else 409 `version_conflict`. With `dry_run: true`, report and keep nothing. The same `operation_key` again returns its receipt, never a second write |
| `GET /encounters/{encounter}` | The encounter now: `version`, and `history` as an array (empty included), each row with its `operation_key`. 404 `unknown_encounter` if never seen |
| `GET /receipts/{key}` | The receipt for that key, with its own `operation_key`, or 404 `no_receipt` if nothing was committed under it |
| `GET /capabilities` | `conditional_writes`, `receipts`, `history` and `dry_run`, all true. Optional: a receiver without it declares the same four in its site profile entry (`features`) |

If any of the four is false, the gate blocks the resend (`CONNECTOR_INCAPABLE`, `HISTORY_UNSUPPORTED`, `DRY_RUN_UNSUPPORTED`).

## Headers

- Request: `Content-Type: application/json`, and HTTP Basic sign-in from the connector's IRIS credential (`DownstreamAPI` in the demo).
- Response: a JSON body (the demo sends `Content-Type: application/json`). On a 503 or 429, `Retry-After` in seconds (1 to 3600) is kept, and the next read waits for it, 300 s at most.
- Answer within 15 seconds. A write with no answer in that time is `uncertain`: the case reads the receipt and the history to learn whether it landed.

## One request and one response each

```http
POST /downstream/api/operations
{"operation_key": "PAS^HOSP^MRN1001^ENC-1001^transfer^2026-10-15T09:20:00Z", "encounter_id": "ENC-1001",
 "patient_id": "MRN1001", "patient_id_authority": "HOSP", "event": "transfer", "ward": "WARD-B",
 "event_time": "2026-10-15T09:20:00Z", "source_system": "PAS", "source_message_id": "MSG00002",
 "expected_version": 1, "payload_digest": "sha256:...", "dry_run": false}

201 {"applied": true, "receipt": {...}, "encounter": {...}}
```

```http
GET /downstream/api/encounters/ENC-1001

200 {"encounter_id": "ENC-1001", "state": "admitted", "ward": "WARD-C", "version": 3,
     "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "operation_key": "..."}, ...]}
```

```http
GET /downstream/api/receipts/{operation_key, URL-encoded}

200 {"operation_key": "...", "encounter_id": "ENC-1001", "event": "transfer", "ward": "WARD-B",
     "version_before": 1, "version_after": 2, "payload_digest": "sha256:...", "status": "committed"}
```

```http
GET /downstream/api/capabilities

200 {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true, "epoch": 7}
```

A dry run answers 200 `{"applied": false, "rehearsal": true, "would_apply": true, "encounter_before": {...}, "encounter_after": {...}}`. Every field and error code is in [CONTRACTS section 1](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#1-the-downstream-systems-api).

## The smallest receiver

In memory, one handler per endpoint, each returning a status and a body. A real receiver adds transitions, patient checks, its own digest, beds and locking.

```python
enc, rcpt = {}, {}  # encounter_id -> encounter; operation_key -> receipt

def capabilities():  # GET /capabilities
    return 200, {"conditional_writes": True, "receipts": True, "history": True, "dry_run": True}

def encounter(eid):  # GET /encounters/{encounter}
    return (200, enc[eid]) if eid in enc else (404, {"error": "unknown_encounter"})

def receipt(key):  # GET /receipts/{key}
    return (200, rcpt[key]) if key in rcpt else (404, {"error": "no_receipt"})

def operation(op):  # POST /operations
    key, eid = op["operation_key"], op["encounter_id"]
    if key in rcpt:  # the same key again: its receipt, never a second write
        if rcpt[key]["payload_digest"] != op["payload_digest"]:
            return 409, {"error": "key_reused_with_different_payload", "operation_key": key}
        return 200, {"applied": False, "reason": "already_committed", "receipt": rcpt[key], "encounter": enc[eid]}
    before = enc.get(eid)
    version = before["version"] if before else 0
    if op.get("expected_version") is not None and op["expected_version"] != version:
        return 409, {"error": "version_conflict", "expected_version": op["expected_version"], "current_version": version}
    step = {"version_after": version + 1, "event": op["event"], "ward": op["ward"], "event_time": op["event_time"], "operation_key": key}
    after = {"encounter_id": eid, "patient_id": op["patient_id"], "state": "discharged" if op["event"] == "discharge" else "admitted",
             "ward": op["ward"], "version": version + 1, "history": (before["history"] if before else []) + [step]}
    if op.get("dry_run"):  # report, keep nothing
        return 200, {"applied": False, "rehearsal": True, "would_apply": True, "encounter_before": before, "encounter_after": after}
    enc[eid] = after  # in a real receiver, these two writes are one transaction
    rcpt[key] = {"operation_key": key, "encounter_id": eid, "event": op["event"], "ward": op["ward"],
                 "payload_digest": op["payload_digest"], "version_before": version, "version_after": version + 1, "status": "committed"}
    return 201, {"applied": True, "receipt": rcpt[key], "encounter": after}
```

**The demo bed manager is the reference:** [`Downstream.API`](https://github.com/MxSalata/shutter/blob/main/src/Downstream/API.cls) is its REST handler and [`Downstream.Service`](https://github.com/MxSalata/shutter/blob/main/src/Downstream/Service.cls) does the work. Its contract tests are [`Downstream.Test.Contract`](https://github.com/MxSalata/shutter/blob/main/tests/unit/Downstream/Test/Contract.cls) and, over HTTP, [`downstream_api_check.py`](https://github.com/MxSalata/shutter/blob/main/tests/e2e/downstream_api_check.py). To connect your receiver, add its paths to the site profile and give it a connector item ([INSTALL section 9](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md#9-onboarding-several-namespaces), "Giving a receiver its API").

## A receiver without it

A plain MLLP receiver, or one whose entry declares its features false, still gets a case:

- the evidence, and the board's diagnosis where the agents can run;
- the reason nothing was sent: `CONNECTOR_INCAPABLE`, and an approval is refused;
- a drafted email to the team that owns the system, which a person checks and sends (**Escalate to**);
- the team corrects the receiver by hand and marks the case handled.

Never a resend from the case: an ACK says a message arrived, not what the receiver now holds. [`plain_receiver_check.py`](https://github.com/MxSalata/shutter/blob/main/tests/e2e/plain_receiver_check.py) plays this on a stock `EnsLib.HL7.Operation.TCPOperation`, down and answering AE, and checks nothing was sent. During an outage, at a receiver whose entry has a `watch` block and `engine_resend`, one approval has the engine resend the stored messages that never arrived; each is completed in the engine, as far as the entry's `ack_level` says, or closed on the receiver's declared duplicate answer, and is not verified at the receiver ([CONTRACTS 17.8](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#178-the-send-v151-to-v154)). [What each kind of receiver gets](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md#what-shutter-does-at-your-site).
