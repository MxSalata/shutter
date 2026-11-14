# The FHIR R4 profile against IRIS for Health's own FHIR server

This page is the record of one run of the FHIR R4 receiver profile ([fhir.md](fhir.md)) against InterSystems IRIS for Health's own FHIR R4 server, not Shutter's test FHIR server: the conformance run that gives the proof, then the end-to-end check's variants A (the move) and D (switched off). Nothing in Shutter's image or install changed for it.

**When and what:** 14 November 2026, 05:46 to 05:51 UTC, commit `668205d`, on a Linux VM with 12 threads, in a fresh container of `irishealth-community:2026.3.0AI.154.0` (Community), the contest's build. IRIS reports `IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:04:49 EDT`. Shutter was installed as CI installs it (the namespace, the load, `Shutter.Setup.Install`, the demo hospital and records system).

**Result:** the conformance run gave 236 exchanges, 236 as measured, 0 differ, and wrote the proof; variant A was resolved after the approver's own approval with one update, verified in Encounter version "2"; variant D was blocked with `FHIR_RECOVERY_DISABLED` and nothing was sent. The same run on IRIS for Health 2026.2 did not pass the conformance run (below), so this page proves the profile on build 154 only.

## The server

IRIS for Health's FHIR R4 server in a namespace of its own, `FHIRSERVER`, on the same instance as Shutter, installed as documented and then locked down:

```text
zn "HSLIB"
set sc=##class(HS.Util.Installer.Foundation).Install("FHIRSERVER")
zn "FHIRSERVER"
set sc=##class(HS.FHIRServer.Installer).InstallNamespace()
do ##class(HS.FHIRServer.Installer).InstallInstance("/fhir/r4","HS.FHIRServer.Storage.JsonAdvSQL.InteractionsStrategy",$lb("hl7.fhir.r4.core@4.0.1"))
zn "%SYS"
set sc=##class(Security.Resources).Create("FHIR_API","FHIR R4 endpoint /fhir/r4","")
set sc=##class(Security.Roles).Create("FHIR_Client","FHIR read and write","FHIR_API:RW")
set sc=##class(Security.Users).Create("iris-fhir-client","FHIR_Client","<password>","Client of IRIS for Health's own FHIR server","","","",0,1)
set sc=##class(Security.Applications).Get("/fhir/r4",.p) set p("AutheEnabled")=32 set sc=##class(Security.Applications).Modify("/fhir/r4",.p)
zn "FHIRSERVER"
set strategy=##class(HS.FHIRServer.API.InteractionsStrategy).GetStrategyForEndpoint("/fhir/r4")
set cfg=strategy.GetServiceConfigData() set cfg.RequiredResource="FHIR_API" do strategy.SaveServiceConfigData(cfg)
```

The install took 48 seconds. Read back: `/fhir/r4` in namespace `FHIRSERVER`, dispatch class `HS.FHIRServer.RestHandler`, `AutheEnabled` 32 (password only), `RequiredResource` `FHIR_API`. Over HTTP, `GET /fhir/r4/metadata` answered **404** with no login and **404** with a wrong password, and **200** as `iris-fhir-client`. The client user is not the demo's `fhir-client`, which belongs to Shutter's test FHIR server.

**The CapabilityStatement** (`GET /fhir/r4/metadata` as the client): HTTP 200, **874,051 bytes**, `software.name` "InterSystems IRIS for Health", `software.version` "IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:04:49 EDT [Health:11.6.0+snapshot]", `fhirVersion` "4.0.1". Shutter's reader takes a body of up to 1,000,000 characters.

## The conformance run

```text
$ FHIR_PASSWORD=<password> python3 tests/conformance/fhir_conformance.py --base http://127.0.0.1:52930/fhir/r4 --target iris --user iris-fhir-client --proof proof-iris.json
...
236 exchanges against http://127.0.0.1:52930/fhir/r4 (iris), prefix 'r3bfa04-': 236 as measured, 0 differ
proof written to proof-iris.json: InterSystems IRIS for Health IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:04:49 EDT [Health:11.6.0+snapshot], 236 exchanges, none differ
```

The proof names the kit `fhir-facade-v1.json` with its SHA-256 `95d86920...dda0c`, the target `iris`, `measured_at` 2026-11-14T05:49:27Z, the software above, 236 exchanges, `differ` 0, and the three measurements, each passed on its own exchange: `if_match_stale_refused` (`m3-update-stale`), `if_match_unknown_id_refused` (`m5-if-match-unknown-id`), `tags_kept` (`m8-history-tags`). The end-to-end check imported it for the receiver with `Shutter.Store.FHIRProof.Import`.

## The end-to-end check

```text
$ FHIR_PASSWORD=<password> python3 tests/e2e/fhir_receiver_check.py --ctr <container> --url http://127.0.0.1:52930 --server iris --fhir-base /fhir/r4 --fhir-user iris-fhir-client --proof proof-iris.json
```

It set the credential `FHIRServer` from that user, placed the four FHIR items with it (`Shutter.FHIR.Install.PlaceItems("127.0.0.1", "", "FHIRServer", "")`), added the file service and a stock HL7 TCP operation with nothing listening to the demo hospital's production, stored the receiver entry with `fhir.base` `/fhir/r4` through `PUT /api/shutter/site-profile`, and seeded each variant by `PUT` under fresh ids (prefix `e2e7d8783-`): two Locations, a Patient, and an in-progress Encounter at Ward A whose participant's display is "Zoë". Each `PUT` answered 201. That server keeps no count of requests, so the check counted the versions in the Encounter's history in place of the test server's count of PUTs. 24 checks passed, none failed, exit 0, 62 seconds.

**Variant A, the move.** The A02 for visit `FHV-3353741` (Ward A to Ward B) became case `C-000001`, which waited for a person in Site policy mode although the receiver's tier is one the demo's policy releases on its own: one open approval task, no approval yet, the gate decision under policy `fhir-2026-11-14.1` with the rehearsal row `FHIR_NO_DRY_RUN_SUBSTITUTED`, no rehearsal, and the headline "Update the Encounter's location once, WARD-A to WARD-B, after this case's own approval. No dry run exists for this receiver. The HL7 message is not sent again." The history still held one version. The approver approved at 05:50:02Z; the case was then `resolved`.

The request, as Shutter recorded it (`Shutter_Store.FHIRAttempt`):

| Field | Value |
| --- | --- |
| Request | `PUT /fhir/r4/Encounter/e2e7d8783-enc-3353741` |
| `If-Match` | `W/"1"`, the ETag of the version read |
| Body SHA-256 | `3e63f25d0d5cb3cf58cb09cdab63b6f90990503f6cde1e31d95eeb2b3a853dc2` |
| Marker | `meta.tag` `urn:shutter:recovery` / `e1279f39154c63933a7d83c6071bc57d` |
| State | `sent` at 05:50:03Z, answered at 05:50:03Z |

The answer: HTTP **200**, `ETag` `W/"2"`, `Location` `http://127.0.0.1:52773/fhir/r4/Encounter/e2e7d8783-enc-3353741/_history/2`. The attempt is `applied`, its receipt `kind` `fhir`. The verification: `verified`, "Verified in Encounter version "2": the approved location update is present, carrying Shutter's marker; no other field changed from version "1", the version the write was conditional on." One approval, the approver's own.

The history, `GET /fhir/r4/Encounter/e2e7d8783-enc-3353741/_history` after the case: `type` `history`, `total` 2, one link (`self`), newest first:

| Version | `request` | `response` | Marker | Locations |
| --- | --- | --- | --- | --- |
| 2 | `PUT Encounter/e2e7d8783-enc-3353741` | `200`, lastModified 2026-11-14T05:50:03Z | `e1279f39154c63933a7d83c6071bc57d` | ward-a `completed` (03:49:34Z to 05:49:34Z), ward-b `active` from 05:49:34Z |
| 1 | `PUT Encounter/e2e7d8783-enc-3353741` | `200`, lastModified 2026-11-14T05:49:34Z | none | ward-a `active` from 03:49:34Z |

Version 2 as the server returns it by version id (`GET .../_history/2`):

```json
{"resourceType": "Encounter", "id": "e2e7d8783-enc-3353741", "status": "in-progress",
 "identifier": [{"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49", "value": "FHV-3353741"}],
 "class": {"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IMP"},
 "subject": {"reference": "Patient/e2e7d8783-pat-3353741"},
 "participant": [{"individual": {"display": "Zoë"}}],
 "location": [{"location": {"reference": "Location/e2e7d8783-ward-a"}, "status": "completed",
               "period": {"start": "2026-11-14T03:49:34Z", "end": "2026-11-14T05:49:34Z"}},
              {"location": {"reference": "Location/e2e7d8783-ward-b"}, "status": "active",
               "period": {"start": "2026-11-14T05:49:34Z"}}],
 "meta": {"lastUpdated": "2026-11-14T05:50:03Z", "versionId": "2",
          "tag": [{"system": "urn:shutter:recovery", "code": "e1279f39154c63933a7d83c6071bc57d"}]}}
```

Over HTTP the Encounter's one open location was Ward B, version 2 alone carried the marker, with the receipt's operation id, and the participant still read "Zoë". The history gained one version: one update.

**Variant D, switched off.** With the entry stored again with `recovery_enabled: false`, the A02 for visit `FHV-3353744` became case `C-000002`, blocked at the proposal gate with `FHIR_RECOVERY_DISABLED` (its one failing row, `enablement`): no approval task, no approval, no attempt, and the Encounter's history still one version.

At the end the check restored the site profile under its earlier source and removed the watched mode.

## The same run on IRIS for Health 2026.2

On a fresh container of `irishealth-community:2026.2` (`2026.2 (Build 221U) Fri Jun 26 2026`), with the server installed and locked down the same way (no login 404, wrong password 404, the client 200; the CapabilityStatement 874,038 bytes), the conformance run gave **236 exchanges, 234 as measured, 2 differ**, and wrote no proof:

- `m9-type-history` (`GET Encounter/_history`): 400 with `<HSFHIRErr>InteractionsNotSupported`, "Neither Interaction 'history' or 'history-type' is supported for resource type 'Encounter'.", where the file holds 154's and 109's `<HSFHIRErr>InteractionNotSupported`.
- `m9-system-history` (`GET _history`): **500**, `<SUBSCRIPT>RequireAllowedResourceInteracti+3^HS.FHIRServer.Service.1`, where the file holds 154's and 109's 400 `not-supported`.

Shutter sends neither request: it reads only one Encounter's own history. But the capability check accepts only a run with no differing exchange, so a 2026.2 server cannot be given a proof in this release. Without one, the end-to-end check played variant 0 in place of A: the case was blocked with `FHIR_VERSIONING_UNPROVEN`, the `capability` row its only failing row, so every other read of that server (the search, the Encounter, the Patient, both Locations, the history) was taken as the receiver's own answer; variant D was blocked with `FHIR_RECOVERY_DISABLED` (and the same `capability` row). Nothing was sent.

## What this run does not show

Variants B (a lost answer), C (another writer), C2 and D2 need the test FHIR server's faults and ran only there. The server ran on the same instance as Shutter, over plain HTTP: TLS and OAuth were not used. A 2027.1.0AI Build 109 server was not run here. The client user's role can write every resource type the endpoint allows ([fhir.md](fhir.md), limits).
