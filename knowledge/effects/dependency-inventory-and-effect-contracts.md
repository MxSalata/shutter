---
id: dependency-inventory-and-effect-contracts
version: 1.0
collection: effects
applies_to: [downstream-api-v1]
effective_from: 2026-10-01
---

# Ward location: dependency inventory and effect contracts

Integration team register of what depends on the downstream system's record, and what each operation is
expected to change. Version 1.0, in force from 1 October 2026.

## DEP-1 Who consumes the ward location

| Consumer | What it does with the location | How it hears | Observable from the integration engine |
|---|---|---|---|
| Demo bed-management system (the downstream system) | The record of where each patient is: beds, wards, history | It is the receiver | Yes: encounter history and receipts (WIC-5) |
| Bed board (capacity) | Shows which beds are free; plans admissions | Reads the downstream system every minute | No |
| Pharmacy dispensing | Sends medicines to the patient's current ward | Notified by the downstream system on every location change | No |
| Patient transport (porters) | Creates a move task when a transfer is applied | Notified by the downstream system on every applied transfer | No |
| Electronic patient record | Shows the current location to clinicians | Reads the downstream system on demand | No |

DEP-1.1. Only the downstream system's own record can be checked from the integration engine. Effects on the other
consumers follow from the downstream system's record but can't be verified here; any claim about them is an inference
and must say so.

## DEP-2 Effect contracts

| Operation | Intended effect | Allowed from | Expected receipt | Downstream effects | Must never happen |
|---|---|---|---|---|---|
| Admit | The encounter exists, admitted, at the ward | Never seen | One, version 0 to 1 | Bed occupied; pharmacy and the record follow the ward | A second encounter for the same visit number |
| Transfer | The patient's ward changes | Admitted | One, version n to n+1 | Old bed freed, new bed occupied; pharmacy redirects; one porter task | The location moving back to a ward the patient has left; the same transfer applied twice |
| Discharge | The encounter ends; no ward | Admitted | One, version n to n+1 | Bed freed; pharmacy stops; the record shows discharged | Any location change afterwards |
| Update | Demographic details change | Admitted | One, version n to n+1 | None on location | Any location change |

DEP-2.1. **Applying a transfer twice** creates a second porter task and a second pharmacy redirection, even when the
ward is the same; the history shows two events.

DEP-2.2. **Applying a superseded transfer** moves the recorded location backwards (ELS-2.1): the bed board shows the
wrong bed, pharmacy sends medicines to the wrong ward, porters are asked to move a patient who has already moved.

DEP-2.3. **Not applying a transfer that is still due** leaves the patient recorded on the old ward: the same harms in
the other direction, until it is applied.

## DEP-3 Completing an operation

DEP-3.1. An operation is complete when its receipt exists and the encounter's history contains it with the expected
version, and nothing in DEP-2 "must never happen" is visible in the history.

DEP-3.2. A later legitimate event may change the location again after a recovered operation; completion is judged on
the history, not on the location at the time of checking.
