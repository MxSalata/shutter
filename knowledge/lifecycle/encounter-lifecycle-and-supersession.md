---
id: encounter-lifecycle-and-supersession
version: 1.0
collection: lifecycle
applies_to: [ward-api-v1, hl7-v2.5.1-adt]
effective_from: 2026-10-01
---

# Inpatient encounter lifecycle and supersession policy

Integration team policy for patient movements sent to the ward bed management system. Version 1.0, in force from
1 October 2026.

## ELS-1 The lifecycle

ELS-1.1. An inpatient encounter starts with an admission (A01) to a ward. While admitted it may be transferred (A02)
any number of times and its demographic details may be updated (A08). A discharge (A03) ends it. Nothing changes a
discharged encounter's location or state again; a readmission is a new encounter with a new visit number.

ELS-1.2. Location events are admissions, transfers and discharges: they decide where the patient is. Updates are not
location events.

ELS-1.3. The ward system applies operations in arrival order (contract WIC-1.2). The integration engine therefore
decides whether an event may still be applied **before** it is sent, by comparing event times, not arrival times.

## ELS-2 Supersession

ELS-2.1. **A transfer is superseded** when the encounter has an applied location event whose event time is later than
the transfer's event time: a later transfer, or a discharge. A superseded transfer must not be applied, because it
would move the patient's recorded location back to where they no longer are.

ELS-2.2. **An update never supersedes a transfer.** A demographic update changes no location. A transfer that failed
before a later update is still the patient's latest movement, and is still due, provided nothing in ELS-2.1 applies.

ELS-2.3. **A discharge supersedes every location event with an earlier event time**, including transfers that never
reached the ward system. After a discharge, no transfer is applied (contract WIC-4).

ELS-2.4. An admission is never superseded; if it failed, nothing else can apply until it does.

ELS-2.5. **When event times can't be compared** (missing, equal, or not in UTC), supersession is unknown. Don't apply
the event; ask the integration team.

ELS-2.6. Supersession is decided from the encounter's history as the ward system holds it (WIC-5.1) together with the
movements the integration engine has received. The current location alone isn't enough: the history shows what was
applied and when its event happened.

## ELS-3 Identity

ELS-3.1. An encounter is identified by its visit number (PV1-19) together with the patient's identifier and its
assigning authority (PID-3). A message whose patient doesn't match the encounter's is an identity conflict, never a
movement to apply.

ELS-3.2. The same movement can arrive in more than one message (a resend under a new message control id). It is the
same business operation when its operation key is the same (WIC-2.2).

## ELS-4 What a failed movement means

ELS-4.1. A movement that failed to reach the ward system leaves the ward's record behind reality until it is applied
or found to be superseded. Either outcome closes the gap; leaving it open is not an outcome.

ELS-4.2. A movement that may have reached the ward system (no answer, a timeout, or an answer that doesn't match the
ward's record) is unresolved until its receipt is checked (WIC-3.1, WIC-5.2).
