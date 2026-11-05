---
id: shutter-in-plain-words
version: 1.1
collection: explain
applies_to: [shutter, hl7-v2-adt]
effective_from: 2026-11-03
---

# Shutter in plain words

What Shutter's words mean for a person reading a case: the outcomes, who decides, the gate's checks and the site profile
settings that change what Shutter does. Version 1.1, in force from 3 November 2026. These words explain; they never
decide anything about a case. The case's own evidence, the gate's checks and the what-if facts do.

## SPW-1 What a case is

SPW-1.1. **One failed delivery.** A case is one ADT message (an admission, transfer, discharge, update, merge or
cancellation) that did not reach one receiving system, or whose answer was lost. Shutter collects the evidence once:
the message, the receiver's answer, what the receiver holds now for the encounter, its history, the receipt lookup and
every other movement sent for the encounter.

SPW-1.2. **The board proposes, the gate disposes.** Three specialist agents (conformance, encounter integrity, impact
analysis) read the evidence and a coordinator proposes one plan. A deterministic gate then checks the plan against the
evidence and the site's policy. The agents never write; the only write Shutter can ever make is to send the case's own
message again, unchanged, and only if the receiver still holds the version the evidence read.

SPW-1.3. **Nothing written is the common, safe answer.** Most failed deliveries need no write: the movement already
arrived, or a later one made it obsolete, or the evidence is unclear and a person must look.

## SPW-2 The outcomes

SPW-2.1. **Resend.** The movement never arrived and is still due. Shutter rehearses the write first (a dry run at the
receiver), then sends it once, conditional on the receiver's version, and checks afterwards that it was committed.

SPW-2.2. **Reconcile.** The movement did arrive; only the answer was lost. Shutter records that and sends nothing.

SPW-2.3. **Superseded.** A later movement for the same encounter made this one obsolete: for example the patient was
moved again before the failed transfer could be resent. Sending it now would put the patient back in the wrong place,
so the case closes with nothing sent.

SPW-2.4. **More evidence.** The receipt, the history or the movements could not be read, or they disagree. Shutter
waits or asks a person rather than guess.

SPW-2.5. **Escalate.** A person must decide: an identity conflict, changed content under the same key, a merge, a
cancellation the receiver cannot reverse, a receiving system whose history must be corrected by hand, or anything the
gate will not release. The escalation names the team and, where Shutter knows them, the steps.

## SPW-3 Who decides

SPW-3.1. **The site's written policy, or a person.** The site profile says, per receiver tier and kind of case, whether
an exact resend is released automatically or waits for an approver. An approval binds the exact plan, the evidence and
the policy in force; if any of them changes before the write, the approval is void and the case blocks for a person.

SPW-3.2. **Closing by hand** is a person's decision, recorded with who closed it and why.

## SPW-4 What the site profile settings change

SPW-4.1. **A receiver's category.** `current_state` (a bed manager or a whiteboard: only where the patient is now
matters, so an overtaken movement closes as superseded), `history_of_record` (a patient record: every movement must be
in the history, so an overtaken movement is escalated with the steps that correct the history by hand) and
`orders_results` (not modelled yet: Shutter escalates before any agent runs and never writes).

SPW-4.2. **A receiver's history policy** follows its category unless the site overrides it: `current` closes an overtaken
movement, `correct` asks for the history to be corrected.

SPW-4.3. **The authoritative source.** When two systems report the same movement with different times (the patient
administration system and the bed manager, say), the site may name one as authoritative. Shutter then trusts that
system's account; the what-if facts say what this case would have done under it.

SPW-4.4. **The tier and its approval policy.** Each receiver has a tier; each tier says, for a single case and for a
chain of related cases, whether a resend waits for an approver.

SPW-4.5. **Merges and cancellations.** A patient merge that is not an exact resend is never applied by Shutter; it goes to
the patient administration team. A cancellation the receiver cannot reverse is escalated, not resent.

SPW-4.6. **A change is a draft.** A setting suggested from a case opens as a draft on the Site profile page. An approver
reviews it and saves it as a new profile version; it applies to later cases only, never to the case it came from.

## SPW-5 The gate's checks, by reason code

Each reason the gate gives for blocking or escalating, with what it means and the next step.

SPW-5.1. **PATIENT_MISMATCH: The patient doesn't match the encounter.** The message names a different patient or assigning authority from the one the downstream system holds for this encounter. An identity conflict is never a movement to apply. Next: Escalate the identity conflict to the integration team. Nothing is sent.

SPW-5.2. **UNKNOWN_ENCOUNTER: The downstream system has never seen this encounter.** The downstream system has no admission for this visit number, so a transfer, discharge or update can't apply. Next: Check whether the admission failed too and recover it first; otherwise escalate.

SPW-5.3. **RECEIVER_UNREADABLE: The downstream system's record couldn't be read.** Without the downstream system's current state and history, supersession and transitions can't be judged, so nothing is eligible. Next: Collect the evidence again. If the downstream system stays unreadable, contact the downstream system team.

SPW-5.4. **PARSE_FAILED: The message couldn't be read or mapped to an operation.** IRIS couldn't read the message against this namespace's schema, or fields the operation needs, such as the visit number, the event time or the patient identifier, are missing or malformed. A second, independent parser says which: a sound message whose site segment isn't defined here, or a malformed one. Next: Read the gate's words. When the second parser reads the message as sound and names a site segment the schema lacks, import the site's schema and set the inbound item's schema category to it (INSTALL.md section 7), then reinvestigate; nothing is resent meanwhile. Otherwise escalate to the integration team with the message.

SPW-5.5. **UNMAPPABLE: The message can't become a downstream operation.** The feed couldn't map the message to an operation: a field the operation needs is missing or malformed, or the profile maps no operation for its event. Shutter opened a case so the failure isn't lost, but nothing can be resent from it. Next: Escalate to the integration team with the message: correct it at the source and send it again.

SPW-5.6. **UNKNOWN_DISPOSITION: The proposal named an outcome the playbooks don't have.** Only the five playbook outcomes can be acted on. Next: Run the investigation again; if it repeats, escalate.

SPW-5.7. **DIFFERENT_OPERATION: The plan is for a different operation.** A recovery may only resend the same business operation, never a different one. Next: Discard the plan and investigate again.

SPW-5.8. **PAYLOAD_CHANGED: The payload differs from the original.** A resend must carry exactly the original movement: changed content isn't a recovery. A further failure for the same operation with different content blocks the open case for the same reason. Next: Escalate: content that changed under the same key needs the integration team (RP-2.5).

SPW-5.9. **SUPERSEDED_BY_LATER_EVENT: A later event made this movement obsolete.** The encounter has a later transfer or discharge with a plausible event time: one the downstream system applied, a later transfer the PAS sent whose delivery failed too, which its own case recovers, or a later cancel, merge or admission the downstream system applied. Resending would move the patient's record backwards. Next: Close the case as superseded, recording the superseding event. Nothing is sent.

SPW-5.10. **SUPERSESSION_UNSUPPORTED: The claimed later event is not in the evidence.** The plan closes the case as superseded, but the snapshot holds no later transfer or discharge for the encounter. A supersession must be shown by the evidence, not asserted. Next: Check the receiver's history for the encounter. If a later event exists, collect evidence again; otherwise the operation may still be due, so re-plan.

SPW-5.11. **INVALID_TRANSITION: The downstream system wouldn't allow this movement now.** For example, a transfer after a discharge: the downstream system refuses it, and resending can't help. Next: Check for supersession, such as a discharge, and close; otherwise escalate.

SPW-5.12. **ALREADY_COMMITTED: The downstream system already committed this movement.** A receipt with the same payload exists, so the movement happened even though the sender saw an error. Next: Reconcile: record the receipt and verify the history. Never resend.

SPW-5.13. **NO_RECEIPT: No receipt for this operation.** Reconciling needs proof that the downstream system committed the movement; there is none. Next: Investigate again: the movement wasn't committed, so reconciling doesn't apply.

SPW-5.14. **RECEIPT_UNREADABLE: The receipt lookup didn't answer.** No answer isn't the same as no receipt. Until the lookup answers, nothing may be resent (RP-3.1). Next: Collect the evidence again later. The outcome stays unknown until the lookup answers.

SPW-5.15. **NO_APPROVAL: Nobody has approved this plan yet.** A resend needs a person's approval of the exact request. Next: Send the plan to an approver.

SPW-5.16. **APPROVAL_REVOKED: The approval was revoked.** The approver withdrew the approval before dispatch. Next: Review the plan again and ask for a new approval if it still holds.

SPW-5.17. **APPROVAL_EXPIRED: The approval expired.** Approvals are time-limited, because the downstream system's state can change. Next: Collect fresh evidence and ask for a new approval.

SPW-5.18. **APPROVAL_PLAN_CHANGED: The plan changed after approval.** An approval covers one exact plan; any change needs a new one (RP-3.4). Next: Ask for approval of the new plan.

SPW-5.19. **APPROVAL_SNAPSHOT_CHANGED: The evidence changed after approval.** New evidence arrived after the approval, so the approver hasn't seen what the plan now rests on. Next: Review the new evidence, and approve again if the plan still holds.

SPW-5.20. **APPROVAL_POLICY_CHANGED: The policy changed after approval.** The rules the approval relied on have a new version. Next: Run the checks again under the new policy, and approve again.

SPW-5.21. **APPROVAL_CATALOGUE_CHANGED: The catalogue changed after approval.** An entry of the scenario catalogue has a new version since the approval, so the match the plan rests on may no longer hold. Next: Investigate again under the current catalogue, and approve again if the plan still holds.

SPW-5.22. **APPROVAL_SITE_PROFILE_CHANGED: The site profile changed after approval.** The site's profile (its policies, its tiers or its receiver description) has a new version since the approval, so who decides and what is allowed may have changed. Next: Review the plan under the new profile, and approve again if it still applies.

SPW-5.23. **APPROVAL_RECEIVER_CHANGED: The downstream system's state changed after approval.** Something was applied to the encounter after the approval, or the downstream system was reset, so the approved request may no longer be right. Next: Collect fresh evidence: a later event may have superseded the movement.

SPW-5.24. **APPROVAL_RECEIVER_RESET: The downstream system was reset after approval.** The downstream system's epoch changed after the approval, so the version the approver saw belongs to records that no longer exist (WIC-1.4). Next: Collect fresh evidence: after a reset the downstream system's records start again, and versions from before it don't compare.

SPW-5.25. **APPROVAL_NOT_APPROVED: The approval record isn't an approval.** The record the dispatch found holds another decision, so it authorises nothing. Next: Ask an approver to decide on the current plan.

SPW-5.26. **NO_EXPECTED_VERSION: The resend has no expected version.** A resend must be conditional, so that the downstream system refuses it if anything changed in between. Next: Rebuild the plan from fresh evidence.

SPW-5.27. **RECEIVER_CHANGED: The downstream system's state changed before dispatch.** The check before dispatch found a newer version, so the conditional write would be refused anyway. Next: Collect fresh evidence and investigate again.

SPW-5.28. **STALE_EVIDENCE: The evidence is too old.** Observations of the current state age quickly; decisions use a fresh read. Next: Collect the evidence again.

SPW-5.29. **CONNECTOR_INCAPABLE: The downstream system can't take a conditional write now.** Without conditional writes, nothing makes sure the resend lands on the state the approver saw, so resending isn't offered. Next: Escalate for manual handling, or wait until the capability is back. Reconcile and superseded remain possible.

SPW-5.30. **CAPABILITIES_UNREADABLE: The downstream system's capability profile couldn't be read.** Without the profile it is unknown whether the downstream system still honours conditional writes and receipts, so no write is dispatched (WIC-7.2). Next: Collect the evidence again later. Nothing is assumed about the downstream system's guarantees meanwhile.

SPW-5.31. **REHEARSAL_WOULD_NOT_APPLY: The rehearsal says the resend wouldn't apply.** The downstream system's dry run of the exact request reported a refusal. Next: Escalate with the rehearsal's reason (RP-2.5).

SPW-5.32. **REJECTED_BY_APPROVER: The approver rejected the plan.** A person declined the request. Next: Read the approver's reason, then investigate again or escalate.

SPW-5.33. **DISPATCH_REFUSED: The downstream system refused the resend.** The conditional write was refused, so nothing changed. Next: Read the downstream system's answer: for a version conflict, collect fresh evidence; for anything else, escalate.

SPW-5.34. **ESCALATED: Handed to a person.** The investigation asked for a person: the evidence doesn't settle what should happen, or nothing Shutter may do would settle it. Next: Read the findings and the gate's notes, then decide how to recover the message by hand.

SPW-5.35. **BLOCKED: Stopped before any write.** The case stopped without a gate check to name the reason; its timeline says why. Next: Read the case's last events for the reason, then investigate again or escalate.

SPW-5.36. **ENTRY_UNKNOWN: The plan names an unknown scenario.** The plan cites a catalogue entry the catalogue doesn't have, so the gate can't check its pattern or its outcomes. Next: Investigate again so the plan names an entry from the current catalogue, or escalate.

SPW-5.37. **PATTERN_NOT_MATCHED: The case doesn't fit the scenario the plan names.** The entry the plan names doesn't match the evidence snapshot: at least one of its conditions has another value here. Next: Read the observed conditions on the case; investigate again or escalate.

SPW-5.38. **OUTCOME_NOT_ALLOWED: This site doesn't allow the chosen outcome.** The plan chose an alternative outcome whose condition doesn't hold for this site, for example history correction where the site keeps what is current. Next: Choose the entry's preferred outcome, or ask the integration team to change the site profile.

SPW-5.39. **OUTCOME_MISMATCH: The plan doesn't do what its catalogue outcome says.** The plan names a catalogue outcome but proposes another disposition, for example a resend where the outcome calls for no write. Next: Investigate again so the plan's disposition follows the entry's outcome, or escalate.

SPW-5.40. **NEW_PATTERN: No known scenario fits.** No entry in the scenario catalogue matches this case's evidence. The board analysed it, but a new pattern is settled by a person, and may become a new entry. Next: Read the board's analysis and resolve the case by hand; flag it as a candidate catalogue entry.

SPW-5.41. **POLICY_REQUIRES_APPROVAL: This site's policy needs an approval.** An automatic release was attempted where the site profile requires a person's approval for this tier and kind of chain. Next: Approve or reject the plan in its Workflow task.

SPW-5.42. **APPROVAL_PLAN_ORIGIN: The policy's approval needs a plan from the policy path.** An approval by site policy stands only for a plan the policy path produced for its catalogue entry. This plan came from elsewhere, so the automatic release does not cover it. Next: Investigate again so the plan comes from the policy path for its entry, or have a person approve it.

SPW-5.43. **MATCHER_ERROR: The catalogue matcher failed.** The matcher raised an error instead of a result. That is not the same as no matching entry: the pattern may well be known, so the gate blocks rather than treating the case as new. Next: Investigate again. If the error repeats, the integration team checks the catalogue and the matcher.

SPW-5.44. **RECEIPT_NOT_AVAILABLE: The receiver keeps no receipts.** This receiver publishes no receipts, so whether the operation was applied can only be read from its history. A reconcile is right when the history shows the operation; this history does not, so there is nothing to reconcile against. Next: Check the receiver's own records for the operation. If it was applied, a person confirms and the case closes; if it was not, the plan should resend under the capability check, not reconcile.

SPW-5.45. **EVENT_TIME_IMPLAUSIBLE: The event's time, or a later event's, doesn't fit the encounter.** Shutter orders and supersedes movements by their event time. A time before the admission, in the future, far from when the PAS recorded the event, or in the hour of a clock change can't be ordered safely, nor can a later event timed well after it was sent, applied or seen when that event would decide whether this one was overtaken. Such a time is not simply bad data: one more than a day before the PAS recorded it is usually a retrospective entry (paper notes typed in later), one in the future or before the admission usually a clock fault or a mistyped time, and a local time without an offset within an hour of a clock change may be one that night holds twice (or never), so only the source can say when it was. The messages can't tell these apart, so nothing is written and a person decides. Next: Confirm the event's real time, or the later event's, with the source system: for a time far before it was recorded, whether it was entered retrospectively; for one in the future or before the admission, whether a clock or the typed time is wrong; for one within an hour of a clock change, which side of the change it was. Then reinvestigate the case or correct the history.

SPW-5.46. **MERGE_WITHHELD: A merge is never sent by Shutter.** An ADT^A40 merge changes which record a patient's history belongs to. Shutter withholds it under the site's policy, or because the receiver takes no merges, and sends nothing. Next: Hand the merge to the PAS team named for the sending application; mark the case handled when it confirms what it did.

SPW-5.47. **CANCEL_UNSUPPORTED: The receiver cannot reverse the event.** The message cancels an earlier movement, and the receiver's entry says it takes no cancels. Shutter withholds the cancel and sends nothing; a person corrects the receiver. Next: Correct the receiver by hand, then mark the case handled on the case page.

SPW-5.48. **RECEIVER_NOT_MODELLED: The receiver's category is not modelled yet.** The receiver keeps orders and results (category orders_results), which Shutter's catalogue does not model yet. Shutter sends it nothing and does not judge the failure; a person handles it in the receiving system. Next: Handle the failure in the receiving system by hand, then mark the case handled on the case page. Nothing is sent.

SPW-5.49. **RECEIVER_NOT_IN_PROFILE: The site profile does not describe the receiver.** The case's receiver has no entry in the site profile, so Shutter does not know its API or what it guarantees: the evidence was read at the default receiver API, and a resend would go to the production's default receiver rather than this one. Shutter resends only to a receiver the profile describes, so nothing is sent. Next: Add the receiver to the site profile (its name, tier, category, API paths and features), then reinvestigate the case. Nothing is sent meanwhile.

SPW-5.50. **PATIENT_LEVEL_WRITE: The operation names no encounter.** Shutter writes only to an encounter whose state and version it can read and compare. A patient-level message names none, so there is nothing to check a write against. Next: A person decides: the message is patient-level (a merge with no visit number).

SPW-5.51. **APPROVAL_ITEM_CHANGED: The incident's approval covered another entry or outcome for this item.** The incident's approval named this operation as one catalogue entry and outcome, and its plan or its fresh evidence now reads another. The release does not cover it, so nothing is sent and the chain stops here. Next: A person reviews the item on its fresh evidence: approve its own plan, or reinvestigate.

SPW-5.52. **APPROVAL_INCIDENT_PLAN_CHANGED: The incident's plan changed after its approval.** The approval the released item stands on named an incident plan digest that is no longer the incident's, or the case no longer belongs to the incident. An approval covers one exact plan (RP-3.4). Next: Review the incident's plan as it is now, and approve it again if it still holds.

SPW-5.53. **DRY_RUN_UNSUPPORTED: The downstream system offers no dry run.** Without a dry run nothing shows that the exact request would apply before it is written, so resending is not offered. Next: Escalate for manual handling. Reconcile and superseded remain possible; a resend is not offered to a receiver that cannot rehearse it.

SPW-5.54. **DRY_RUN_MISSING: The exact request was never rehearsed.** The approval carries no dry run of this plan, so the write would be blind. Next: Investigate again: the case rehearses the plan before any approval.

SPW-5.55. **DRY_RUN_FAILED: The rehearsal of this plan reported a refusal.** The dry run bound to the approval said the request would not apply; nothing is dispatched on it. Next: Escalate with the rehearsal's reason (RP-2.5).

SPW-5.56. **DRY_RUN_STALE: The rehearsal was checked against another version.** The dry run was checked against a different receiver version, epoch or payload from the write's, so it proves nothing about this write. Next: Collect fresh evidence and investigate again; the case rehearses the new plan.

SPW-5.57. **WRITE_NOT_COMMITTED: The resend was not committed.** The write's answer was lost. Not committed: by the last read, after the settle window, the receiver holds no receipt for the operation and its history does not show it, and the encounter is still at the version the write was conditional on (or moved past it by something else, so the conditional write can no longer apply). Nothing shows it was applied; a slower receiver can still commit it, unless the version has moved. The approval authorised one write and it is spent; a reinvestigation makes a new plan on fresh evidence. Next: Check the receiver's history and receipts for the operation key; reinvestigate the case when the receiver's state is known. Never resend blind.

SPW-5.58. **WRITE_OUTCOME_UNKNOWN: The resend's outcome is unknown.** The write's answer was lost, and the reads that followed could not settle whether the receiver applied it: a lookup failed, the receiver no longer knows the encounter, or the budget of reads ran out. Nothing is established either way, so nothing is resent until a person has checked at the receiver. Next: Check the receiver's history and receipts for the operation key; reinvestigate the case when the receiver's state is known. Never resend blind.

SPW-5.59. **WAITING_FOR_OCCUPANT_CASE: Waiting for the bed's occupant to leave.** The receiver refused this movement because another patient's encounter holds the bed, and that patient's movement out is still being recovered in another case. Resending now would be refused again, so this case waits for that one. Next: Nothing to do yet. The case is checked again when the case about the occupant's movement closes; recover that case first if it needs a person.

SPW-5.60. **OCCUPANT_CASE_FAILED: The bed's occupant is not leaving after all.** The case about the occupant's movement out of the bed ended escalated, failed or abandoned, so the bed will not free itself. A person must decide where each patient is. Next: Escalate to the bed manager with the conflict: the bed, the occupant's encounter, the refused movement. Nothing is sent.

SPW-5.61. **BED_OCCUPIED: Two patients for one bed.** The receiver holds another patient's encounter in the destination bed and nothing says they are leaving, or the occupant could not be read. That is a clash on the ward, not a delivery fault. Next: Escalate to the bed manager with the conflict laid out. Nothing is sent: a resend would be refused again or double-book the bed.

SPW-5.62. **OCCUPANT_MOVED_OUT: The bed's occupant has left.** The patient who held the destination bed has moved out of it at the receiver, so the refused movement can be sent again. The receiver refuses it again if the bed is held after all. Next: None: a pass. The resend goes ahead under the tier's approval policy, conditional on this encounter's version.

SPW-5.63. **NEWER_MESSAGE_PENDING: A newer message for this patient is on its way.** While Shutter was about to resend this movement, a newer message for the same patient arrived from the source system and has not yet reached the receiver. Resending first would be pointless at best, and wrong behind a cancellation or a merge, so the resend waits for the newer message. Next: Nothing to do yet. The case waits for that message; when it is delivered, the case is checked again on fresh evidence, and a newer movement usually means nothing needs resending.

SPW-5.64. **SCHEMA_UNKNOWN: The message's schema is not loaded here.** The message names a schema category that Shutter's namespace does not have, such as a site's own variant of HL7 2.5.1 with extra segments. That is missing evidence, not an invalid message: Shutter cannot validate the message until the schema is imported. Next: Import the site's schema into Shutter's namespace (the Doctor's hl7_schemas check names the category and the command), then reinvestigate the case. Nothing is sent meanwhile.
