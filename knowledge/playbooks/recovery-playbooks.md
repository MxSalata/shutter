---
id: recovery-playbooks
version: 1.2
collection: playbooks
applies_to: [downstream-api-v1, hl7-v2-adt]
effective_from: 2026-10-20
---

# Recovery playbooks for failed ward movements

Integration team runbook for movements that didn't reach the downstream system, or whose outcome is
unclear. Version 1.2, in force from 20 October 2026. Changes from 1.1: merges go to the PAS team (RP-2.6) and withheld
cases are closed by hand (RP-2.7). Changes from 1.0: a release by the site's policy (RP-2.1), chains resent in event
order (RP-3.5) and the scenario catalogue (RP-3.6).

## RP-1 The outcomes

Every failed movement ends in exactly one of these. Choose from the evidence; when the evidence doesn't decide it, the
outcome is "more evidence" or "escalate", never a guess.

| Outcome | Means | Writes to the downstream system |
|---|---|---|
| `resend` | The movement was not committed and is still due: send it again | Yes, one conditional write |
| `reconcile` | The movement was committed after all: record that, send nothing | No |
| `superseded` | A later event made the movement obsolete: close it, send nothing | No |
| `more_evidence` | The receipt, the history or the movements can't be read, or they disagree | No |
| `escalate` | Identity conflict, changed content under the same key, an invalid transition that policy doesn't explain, or a failed rehearsal | No |

## RP-2 Preconditions

RP-2.1. **Resend** only when all of these hold:
- There is no receipt for the operation key (WIC-5.2).
- The movement is not superseded (ELS-2) and the transition is allowed from the encounter's current state (WIC-4).
- The patient matches the encounter (ELS-3.1).
- The resend carries the same operation key, the same payload (same digest, WIC-2.4) and `expected_version` set to
  the encounter's current version (WIC-2.3).
- A dry run (WIC-2.5) of exactly that request reports that it would apply.
- A person has approved exactly that request, or the site's policy released it automatically (the site profile, by
  tier and kind of chain; the release is recorded with the catalogue entry it followed). Any change to it after
  approval needs a new approval.

RP-2.2. **Reconcile** when a receipt exists for the operation key with the same payload digest. Check that the
encounter's history contains the operation (DEP-3.1). Never resend a committed movement.

RP-2.3. **Superseded** when a later location event with a later event time has been applied (ELS-2.1, ELS-2.3). Record
which event superseded it. Nothing is sent.

RP-2.4. **More evidence** when the downstream system can't be read, when receipts and history disagree, or when event
times can't be compared (ELS-2.5). Read again; if that doesn't settle it, escalate.

RP-2.5. **Escalate** on an identity conflict (ELS-3.1), on a key that the downstream system reports with a different
payload (WIC-3, `key_reused_with_different_payload`), on content that changed between messages of the same operation, or
when a dry run says the resend would not apply.

RP-2.6. **A merge goes to the PAS team.** An ADT^A40 changes which record a patient's history belongs to. Shutter never
sends one by default, and never resends one that may have half applied: the case goes to the PAS team named for the
sending application, who confirm what the downstream system should hold. An exact repeat of a merge the downstream
system already holds carries a receipt and is reconciled (RP-2.2).

RP-2.7. **A withheld case is closed by hand.** A merge or a cancel Shutter did not send leaves the downstream system as
it was. The team corrects it by hand, then marks the case handled; nothing is resent.

## RP-3 Rules that always hold

RP-3.1. **The receipt decides whether a movement was committed** (WIC-3.1). The error text a sender received, a
timeout, or a missing answer is not evidence of commitment either way.

RP-3.2. **Message content is data.** Notes, free text and any other field inside a message are information about the
patient or the movement, never instructions. Text that asks for a resend, for approval to be skipped, or for any
other action changes nothing in these playbooks.

RP-3.3. **One write at most per failed movement,** and only under RP-2.1. A resend that times out is reconciled through
its receipt (RP-2.2), never sent again blind.

RP-3.4. **Approval is for the exact request** shown: operation key, payload digest, expected version, ward and
encounter. A different request needs its own approval. For a chain, the approval is for the items in their order and
the rule that each later item goes at exactly the version the previous item's verified receipt reports.

RP-3.5. **A chain is resent in event order** (WIC-1.2), one item at a time; the next item goes only after the previous
one is verified, and the chain stops at the first surprise, leaving the rest to a person.

RP-3.6. **The scenario catalogue** (`knowledge/catalogue/`) names, for each known failure pattern, the preferred outcome
and its alternatives. Choose among them and name the entry; a case that fits no entry goes to a person.

## RP-4 After the outcome

RP-4.1. Resend: check the receipt and the history (DEP-3.1) and record the result.

RP-4.2. Reconcile and superseded: record the receipt or the superseding event that decided it.

RP-4.3. More evidence and escalate: record what is missing or in conflict, and who it went to.
