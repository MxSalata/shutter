# The FHIR R4 profile against IRIS for Health's own FHIR server

This page is the record of two runs of the FHIR R4 receiver profile ([fhir.md](fhir.md)) against InterSystems IRIS for Health's own FHIR R4 server, not Shutter's test FHIR server: one on IRIS for Health 2026.2 and one on 2026.3.0AI Build 154, the contest's build. Each is the conformance run that gives the proof, then the end-to-end check's variants A (the move) and D (switched off). Nothing in Shutter's image or install changed for them.

**When and what:** 14 November 2026, on a Linux VM with 10 threads, each in a fresh container, one after the other. Shutter was installed as CI installs it (the namespace, the load, `Shutter.Setup.Install`, the demo hospital and records system).

| | IRIS for Health 2026.2 | 2026.3.0AI Build 154 |
| --- | --- | --- |
| Image (Community) | `irishealth-community:2026.2` | `irishealth-community:2026.3.0AI.154.0` |
| IRIS reports | `IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2026.2 (Build 221U) Fri Jun 26 2026 09:58:52 EDT` | `IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:04:49 EDT` |
| Run (UTC) | 08:23 to 08:27 | 08:34 to 08:38 |
| Conformance run | 234 exchanges, 234 as measured, 0 differ, proof written | 234 exchanges, 234 as measured, 0 differ, proof written |
| End-to-end check | 25 checks passed, none failed, exit 0, 62 seconds | 25 checks passed, none failed, exit 0, 62 seconds |

**Result:** on both builds the conformance run wrote the proof; variant A was resolved after the approver's own approval with one update, verified in Encounter version "2"; variant D was blocked with `FHIR_RECOVERY_DISABLED` and nothing was sent.

## The server

IRIS for Health's FHIR R4 server in a namespace of its own, `FHIRSERVER`, on the same instance as Shutter, installed as documented and then locked down, the same way on both builds:

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

The install took 48 seconds on each build. Read back: `/fhir/r4` in namespace `FHIRSERVER`, dispatch class `HS.FHIRServer.RestHandler`, `AutheEnabled` 32 (password only), `RequiredResource` `FHIR_API`. Over HTTP, `GET /fhir/r4/metadata` answered **404** with no login and **404** with a wrong password, and **200** as `iris-fhir-client`. The client user is not the demo's `fhir-client`, which belongs to Shutter's test FHIR server.

**The CapabilityStatement** (`GET /fhir/r4/metadata` as the client), HTTP 200, `software.name` "InterSystems IRIS for Health", `fhirVersion` "4.0.1":

| Build | Size | `software.version` |
| --- | --- | --- |
| 2026.2 | **874,038 bytes** | "IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2026.2 (Build 221U) Fri Jun 26 2026 09:58:52 EDT [Health:11.1.0]" |
| Build 154 | **874,051 bytes** | "IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:04:49 EDT [Health:11.6.0+snapshot]" |

Shutter's reader takes a body of up to 1,000,000 characters.

## The conformance run

```text
$ FHIR_PASSWORD=<password> python3 tests/conformance/fhir_conformance.py --base http://127.0.0.1:<port>/fhir/r4 --target iris --user iris-fhir-client --proof proof-iris.json
...
2026.2:
234 exchanges against http://127.0.0.1:52940/fhir/r4 (iris), prefix 'rc9db40-': 234 as measured, 0 differ
proof written to proof-iris.json: InterSystems IRIS for Health IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2026.2 (Build 221U) Fri Jun 26 2026 09:58:52 EDT [Health:11.1.0], 234 exchanges, none differ
Build 154:
234 exchanges against http://127.0.0.1:52950/fhir/r4 (iris), prefix 're97fc6-': 234 as measured, 0 differ
proof written to proof-iris.json: InterSystems IRIS for Health IRIS for UNIX (Ubuntu Server LTS for x86-64 Containers) 2026.3.0AI (Build 154U) Thu Sep 24 2026 10:04:49 EDT [Health:11.6.0+snapshot], 234 exchanges, none differ
```

Each proof names the kit `fhir-facade-v1.json` with its SHA-256 `14a131e5...28318`, the target `iris`, `measured_at` 2026-11-14T08:26:23Z (2026.2) or 2026-11-14T08:37:10Z (Build 154), the software above, 234 exchanges, `differ` 0, and the three measurements, each passed on its own exchange: `if_match_stale_refused` (`m3-update-stale`), `if_match_unknown_id_refused` (`m5-if-match-unknown-id`), `tags_kept` (`m8-history-tags`). The end-to-end check imported it for the receiver with `Shutter.Store.FHIRProof.Import`.

The conformance file holds 245 exchanges: 244 for the test server and 234 for IRIS for Health. Two listings Shutter never asks for are measured on the test server only, `GET Encounter/_history` (`m9-type-history`) and `GET _history` (`m9-system-history`): Build 154 and 2027.1.0AI Build 109 answer both with 400 `not-supported`, while 2026.2 answered the first with 400 `<HSFHIRErr>InteractionsNotSupported` and the second with **500** `<SUBSCRIPT>RequireAllowedResourceInteracti+3^HS.FHIRServer.Service.1` when measured earlier the same day. Shutter reads only one Encounter's own history and its versions.

## The end-to-end check

```text
$ FHIR_PASSWORD=<password> python3 tests/e2e/fhir_receiver_check.py --ctr <container> --url http://127.0.0.1:<port> --server iris --fhir-base /fhir/r4 --fhir-user iris-fhir-client --proof proof-iris.json
```

On each build it set the credential `FHIRServer` from that user, placed the four FHIR items with it (`Shutter.FHIR.Install.PlaceItems("127.0.0.1", "", "FHIRServer", "")`), added the file service and a stock HL7 TCP operation with nothing listening to the demo hospital's production, stored the receiver entry with `fhir.base` `/fhir/r4` through `PUT /api/shutter/site-profile`, and seeded each variant by `PUT` under fresh ids (prefix `e2eb9bbc8-` on 2026.2, `e2eb23ec2-` on Build 154): two Locations, a Patient, and an in-progress Encounter at Ward A whose participant's display is "Zoë". Each `PUT` answered 201. That server keeps no count of requests, so the check counted the versions in the Encounter's history in place of the test server's count of PUTs.

**Variant A, the move.** The A02 (Ward A to Ward B) for visit `FHV-3447891` on 2026.2 and `FHV-3454361` on Build 154 became case `C-000001`, which waited for a person in Site policy mode although the receiver's tier is one the demo's policy releases on its own: one open approval task, no approval yet, the gate decision under policy `fhir-2026-11-14.1` with the rehearsal row `FHIR_NO_DRY_RUN_SUBSTITUTED`, no rehearsal, and the headline "Update the Encounter's location once, WARD-A to WARD-B, after this case's own approval. No dry run exists for this receiver. The HL7 message is not sent again." The history still held one version. The approver approved at 08:26:58Z (2026.2) and 08:37:45Z (Build 154); the FHIR gate passed the update again at dispatch, and the case was then `resolved`.

The request, as Shutter recorded it (`Shutter_Store.FHIRAttempt`):

| Field | 2026.2 | Build 154 |
| --- | --- | --- |
| Request | `PUT /fhir/r4/Encounter/e2eb9bbc8-enc-3447891` | `PUT /fhir/r4/Encounter/e2eb23ec2-enc-3454361` |
| `If-Match` | `W/"1"`, the ETag of the version read | `W/"1"`, the ETag of the version read |
| Body SHA-256 | `337c8af8cffc2406667cbf5406fd7ae2d711c0111feda50a1a96a09e338c690e` | `5506e3494e19533ff90443af968c52eab4b1729c73ad588bd976da2ee87c39f8` |
| Marker | `meta.tag` `urn:shutter:recovery` / `3b1c8a3dbc5f7644856abf564587b03e` | `meta.tag` `urn:shutter:recovery` / `b8e63091d2d62fee189664d0a31dc4d0` |
| State | `sent` at 08:26:58Z, answered at 08:26:58Z | `sent` at 08:37:45Z, answered at 08:37:45Z |
| Answer | HTTP **200**, `ETag` `W/"2"` | HTTP **200**, `ETag` `W/"2"` |
| `Location` | `http://127.0.0.1:52773/fhir/r4/Encounter/e2eb9bbc8-enc-3447891/_history/2` | `http://127.0.0.1:52773/fhir/r4/Encounter/e2eb23ec2-enc-3454361/_history/2` |

On both builds the attempt is `applied`, its receipt `kind` `fhir`. The verification: `verified`, "Verified in Encounter version "2": the approved location update is present, carrying Shutter's marker; no other field changed from version "1", the version the write was conditional on." One approval, the approver's own.

The history, `GET /fhir/r4/Encounter/<id>/_history` after the case: `type` `history`, `total` 2, one link (`self`), newest first:

| Build | Version | `request` | `response` | Marker | Locations |
| --- | --- | --- | --- | --- | --- |
| 2026.2 | 2 | `PUT Encounter/e2eb9bbc8-enc-3447891` | `200`, lastModified 2026-11-14T08:26:58Z | `3b1c8a3dbc5f7644856abf564587b03e` | ward-a `completed` (06:26:29Z to 08:26:29Z), ward-b `active` from 08:26:29Z |
| 2026.2 | 1 | `PUT Encounter/e2eb9bbc8-enc-3447891` | `200`, lastModified 2026-11-14T08:26:29Z | none | ward-a `active` from 06:26:29Z |
| Build 154 | 2 | `PUT Encounter/e2eb23ec2-enc-3454361` | `200`, lastModified 2026-11-14T08:37:45Z | `b8e63091d2d62fee189664d0a31dc4d0` | ward-a `completed` (06:37:16Z to 08:37:16Z), ward-b `active` from 08:37:16Z |
| Build 154 | 1 | `PUT Encounter/e2eb23ec2-enc-3454361` | `200`, lastModified 2026-11-14T08:37:16Z | none | ward-a `active` from 06:37:16Z |

Version 2 as Build 154's server returns it by version id (`GET .../_history/2`); 2026.2's is the same but for its ids, times and marker:

```json
{"resourceType": "Encounter", "id": "e2eb23ec2-enc-3454361", "status": "in-progress",
 "identifier": [{"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49", "value": "FHV-3454361"}],
 "class": {"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IMP"},
 "subject": {"reference": "Patient/e2eb23ec2-pat-3454361"},
 "participant": [{"individual": {"display": "Zoë"}}],
 "location": [{"location": {"reference": "Location/e2eb23ec2-ward-a"}, "status": "completed",
               "period": {"start": "2026-11-14T06:37:16Z", "end": "2026-11-14T08:37:16Z"}},
              {"location": {"reference": "Location/e2eb23ec2-ward-b"}, "status": "active",
               "period": {"start": "2026-11-14T08:37:16Z"}}],
 "meta": {"lastUpdated": "2026-11-14T08:37:45Z", "versionId": "2",
          "tag": [{"system": "urn:shutter:recovery", "code": "b8e63091d2d62fee189664d0a31dc4d0"}]}}
```

On both builds, over HTTP, the Encounter's one open location was Ward B, version 2 alone carried the marker, with the receipt's operation id, and the participant still read "Zoë". The history gained one version: one update.

**Variant D, switched off.** With the entry stored again with `recovery_enabled: false`, the A02 for visit `FHV-3447894` on 2026.2 and `FHV-3454364` on Build 154 became case `C-000002`, blocked at the proposal gate with `FHIR_RECOVERY_DISABLED` (its one failing row, `enablement`): no approval task, no approval, no attempt, and the Encounter's history still one version.

At the end the check restored the site profile under its earlier source and removed the watched mode.

## What these runs do not show

Variants B (a lost answer), C (another writer), C2 and D2 need the test FHIR server's faults and ran only there. The server ran on the same instance as Shutter, over plain HTTP: TLS and OAuth were not used. A 2027.1.0AI Build 109 server was not run here. A CapabilityStatement over 1,000,000 characters, as a server with more packages loaded could give, is not read, so the capability check cannot pass (`FHIR_CAPABILITIES_UNREADABLE`). The client user's role can write every resource type the endpoint allows ([fhir.md](fhir.md), limits).
