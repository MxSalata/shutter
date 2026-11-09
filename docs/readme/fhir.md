# FHIR R4: in development

Shutter recovers failed HL7 v2 deliveries. A receiver that is a FHIR R4 server is **in development**: some of its parts are
in the release and tested, and no case uses them yet. Shutter does not recover a write to a FHIR server today, and the
README claims no FHIR support.

## What is in the release

Three parts, each tested on its own, compiled by the install and CI, and called by nothing in the case workflow:

- **The plan builder** (`Shutter.FHIR.Plan`). From an Encounter as a FHIR R4 server returned it, it builds the one body
  Shutter would send for a ward move: the open location entry completed at the event time, one new active entry at the
  target ward, and Shutter's marker tag. It refuses every shape it cannot change exactly (a pending or subsetted entry, a
  modifier extension, `implicitRules`, a narrative, an extension on the open entry's status, an empty prior or target
  location) and never throws. `Diff` says whether two bodies differ only where that change may touch them.
- **The verifier's decision** (`Shutter.FHIR.Judge`). Given everything read after a write, it decides with no clock or
  network which of six outcomes holds: verified, verified and continued, committed but for review, unknown, failed, or not
  found. 147 table rows, and a meta-test that no adversarial row ever verifies.
- **A test FHIR server** (`FHIRFacade`), held to the answers IRIS for Health's own FHIR server gave when measured: read,
  vread, history, identifier search, `PUT` with and without `If-Match`, `DELETE`, `metadata`. Its conformance file of 236
  exchanges matched IRIS's own server with 0 differences. No web application serves it yet.

Their unit tests pass on IRIS for Health 2026.2 and on the contest's AI Hub build 2026.3.0AI.154.0.

## What was measured about IRIS for Health's FHIR server

On 2026.2, 2026.3.0AI.154 and 2027.1.0AI.109, identically: a stale or unknown ETag in `If-Match` answers 412 and writes
nothing; the ETag is `W/"versionId"`; a good write answers 200 with an empty body; each `PUT` replaces `meta.tag`; the
smallest role that can write is `FHIR_API:RW`.

## What is left before a FHIR receiver works

The receiver's strict reader and its projection into the case's evidence, a FHIR gate and the approval's binding to the
ETag and the exact body, a FHIR branch of the case workflow beside the ADT one, the write and the verifier's full walk,
the install and a demo, end-to-end scenarios, the case page's panel, and an attack round on the whole. The first use
would be narrow: one ward move on an existing in-progress Encounter, sent as one person-approved `PUT` with the ETag the
server returned in `If-Match`.
