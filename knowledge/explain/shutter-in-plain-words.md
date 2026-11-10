---
id: shutter-in-plain-words
version: 1.5
collection: explain
applies_to: [shutter, hl7-v2-adt]
effective_from: 2026-11-09
---

# Shutter in plain words

What Shutter's words mean for a person reading a case: the outcomes, who decides, the gate's checks and the site profile
settings that change what Shutter does. Version 1.5, in force from 9 November 2026. These words explain; they never
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
`orders_results` (a case gets its findings and goes to a person before any agent runs, and nothing is resent from it; at a
receiver set up for it, an outage's messages that never arrived can be sent again by the engine after one approval).

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

SPW-5.43. **APPROVAL_ORIGIN_NOT_PROVED: An automatic release needs a proved source.** The intake takes what a holder of the forwarder's sign-in posts, so a write with no person needs the source checked. This one could not be, so the automatic release does not cover it. Next: Have a person read the message in its source and approve or reject the plan.

SPW-5.44. **MATCHER_ERROR: The catalogue matcher failed.** The matcher raised an error instead of a result. That is not the same as no matching entry: the pattern may well be known, so the gate blocks rather than treating the case as new. Next: Investigate again. If the error repeats, the integration team checks the catalogue and the matcher.

SPW-5.45. **RECEIPT_NOT_AVAILABLE: The receiver keeps no receipts.** This receiver publishes no receipts, so whether the operation was applied can only be read from its history. A reconcile is right when the history shows the operation; this history does not, so there is nothing to reconcile against. Next: Check the receiver's own records for the operation. If it was applied, a person confirms and the case closes; if it was not, the plan should resend under the capability check, not reconcile.

SPW-5.46. **EVENT_TIME_IMPLAUSIBLE: The event's time, or a later event's, doesn't fit the encounter.** Shutter orders and supersedes movements by their event time. A time before the admission, in the future, far from when the PAS recorded the event, or in the hour of a clock change can't be ordered safely, nor can a later event timed well after it was sent, applied or seen when that event would decide whether this one was overtaken. Such a time is not simply bad data: one more than a day before the PAS recorded it is usually a retrospective entry (paper notes typed in later), one in the future or before the admission usually a clock fault or a mistyped time, and a local time without an offset within an hour of a clock change may be one that night holds twice (or never), so only the source can say when it was. The messages can't tell these apart, so nothing is written and a person decides. Next: Confirm the event's real time, or the later event's, with the source system: for a time far before it was recorded, whether it was entered retrospectively; for one in the future or before the admission, whether a clock or the typed time is wrong; for one within an hour of a clock change, which side of the change it was. Then reinvestigate the case or correct the history.

SPW-5.47. **MERGE_WITHHELD: A merge is never sent by Shutter.** An ADT^A40 merge changes which record a patient's history belongs to. Shutter withholds it under the site's policy, or because the receiver takes no merges, and sends nothing. Next: Hand the merge to the PAS team named for the sending application; mark the case handled when it confirms what it did.

SPW-5.48. **CANCEL_UNSUPPORTED: The receiver cannot reverse the event.** The message cancels an earlier movement, and the receiver's entry says it takes no cancels. Shutter withholds the cancel and sends nothing; a person corrects the receiver. Next: Correct the receiver by hand, then mark the case handled on the case page.

SPW-5.49. **RECEIVER_NOT_MODELLED: An order or result is not resent from its case.** The receiver keeps orders and results (category orders_results). Shutter's catalogue of single-message recoveries covers patient movements, so nothing is resent from the case and no model judges it: the case carries its findings (who holds the message, the receiver's own words and the result they name) and a person handles it in the receiving system. At a receiver set up for it, an outage's messages that never arrived are listed and can be sent again by the engine after one approval. Next: Handle the failure in the receiving system by hand, then mark the case handled on the case page. Nothing is sent.

SPW-5.50. **RECEIVER_NOT_IN_PROFILE: The site profile does not describe the receiver.** The case's receiver has no entry in the site profile, so Shutter does not know its API or what it guarantees: the evidence was read at the default receiver API, and a resend would go to the production's default receiver rather than this one. Shutter resends only to a receiver the profile describes, so nothing is sent. Next: Add the receiver to the site profile (its name, tier, category, API paths and features), then reinvestigate the case. Nothing is sent meanwhile.

SPW-5.51. **PATIENT_LEVEL_WRITE: The operation names no encounter.** Shutter writes only to an encounter whose state and version it can read and compare. A patient-level message names none, so there is nothing to check a write against. Next: A person decides: the message is patient-level (a merge with no visit number).

SPW-5.52. **APPROVAL_ITEM_CHANGED: The incident's approval covered another entry or outcome for this item.** The incident's approval named this operation as one catalogue entry and outcome, and its plan or its fresh evidence now reads another. The release does not cover it, so nothing is sent and the chain stops here. Next: A person reviews the item on its fresh evidence: approve its own plan, or reinvestigate.

SPW-5.53. **APPROVAL_INCIDENT_PLAN_CHANGED: The incident's plan changed after its approval.** The approval the released item stands on named an incident plan digest that is no longer the incident's, or the case no longer belongs to the incident. An approval covers one exact plan (RP-3.4). Next: Review the incident's plan as it is now, and approve it again if it still holds.

SPW-5.54. **DRY_RUN_UNSUPPORTED: The downstream system offers no dry run.** Without a dry run nothing shows that the exact request would apply before it is written, so resending is not offered. Next: Escalate for manual handling. Reconcile and superseded remain possible; a resend is not offered to a receiver that cannot rehearse it.

SPW-5.55. **HISTORY_UNSUPPORTED: The downstream system offers no readable history.** Without a readable history a move made outside this feed would not show, so a resend could overwrite it, and nothing could confirm the write afterwards. Next: Escalate for manual handling. Reconcile and superseded remain possible; a resend is not offered to a receiver whose history can't be read.

SPW-5.56. **HISTORY_UNREADABLE: The downstream system's read holds no history.** The receiver says it keeps a history, but this read of the encounter holds none, so what has moved since is unknown. A missing history isn't the same as nothing later. Next: Ask the downstream system's team why the encounter's read has no history, then investigate again.

SPW-5.57. **DRY_RUN_MISSING: The exact request was never rehearsed.** The approval carries no dry run of this plan, so the write would be blind. Next: Investigate again: the case rehearses the plan before any approval.

SPW-5.58. **DRY_RUN_FAILED: The rehearsal of this plan reported a refusal.** The dry run bound to the approval said the request would not apply; nothing is dispatched on it. Next: Escalate with the rehearsal's reason (RP-2.5).

SPW-5.59. **DRY_RUN_STALE: The rehearsal was checked against another version.** The dry run was checked against a different receiver version, epoch or payload from the write's, so it proves nothing about this write. Next: Collect fresh evidence and investigate again; the case rehearses the new plan.

SPW-5.60. **WRITE_NOT_COMMITTED: The resend was not committed.** The write's answer was lost. Not committed: the receiver holds no receipt for the operation and its history does not show it, and the encounter moved past the version the write was conditional on by something else, so the conditional write can no longer apply. The approval authorised one write and it is spent; a reinvestigation makes a new plan on fresh evidence. Next: Check the receiver's history and receipts for the operation key; reinvestigate the case when the receiver's state is known. Never resend blind.

SPW-5.61. **WRITE_OUTCOME_UNKNOWN: The resend's outcome is unknown.** The write's answer was lost, or the write call itself failed, and nothing since has settled whether the receiver applied it: a lookup failed, the receiver no longer knows the encounter, the budget of reads ran out, or there was no sign of the write by the last read, when a slower receiver can still commit it. Nothing is established either way, so nothing is resent until a person has checked at the receiver. The approval authorised one write and it is spent. Next: Check the receiver's history and receipts for the operation key; reinvestigate the case when the receiver's state is known. Never resend blind.

SPW-5.62. **WAITING_FOR_OCCUPANT_CASE: Waiting for the bed's occupant to leave.** The receiver refused this movement because another patient's encounter holds the bed, and that patient's movement out is still being recovered in another case. Resending now would be refused again, so this case waits for that one. Next: Nothing to do yet. The case is checked again when the case about the occupant's movement closes; recover that case first if it needs a person.

SPW-5.63. **OCCUPANT_CASE_FAILED: The bed's occupant is not leaving after all.** The case about the occupant's movement out of the bed ended escalated, failed or abandoned, so the bed will not free itself. A person must decide where each patient is. Next: Escalate to the bed manager with the conflict: the bed, the occupant's encounter, the refused movement. Nothing is sent.

SPW-5.64. **BED_OCCUPIED: Two patients for one bed.** The receiver holds another patient's encounter in the destination bed and nothing says they are leaving, or the occupant could not be read. That is a clash on the ward, not a delivery fault. Next: Escalate to the bed manager with the conflict laid out. Nothing is sent: a resend would be refused again or double-book the bed.

SPW-5.65. **OCCUPANT_MOVED_OUT: The bed's occupant has left.** The patient who held the destination bed has moved out of it at the receiver, so the refused movement can be sent again. The receiver refuses it again if the bed is held after all. Next: None: a pass. The resend goes ahead under the tier's approval policy, conditional on this encounter's version.

SPW-5.66. **NEWER_MESSAGE_PENDING: A newer message for this patient is on its way.** While Shutter was about to resend this movement, a newer message for the same patient arrived from the source system and has not yet reached the receiver. Resending first would be pointless at best, and wrong behind a cancellation or a merge, so the resend waits for the newer message. Next: Nothing to do yet. The case waits for that message; when it is delivered, the case is checked again on fresh evidence, and a newer movement usually means nothing needs resending.

SPW-5.67. **FURTHER_MOVEMENT: Something else has happened to this patient.** After this message failed, a further message arrived for the same patient that Shutter can't weigh by itself: a new admission or ward stay under another visit number, a cancel or discharge the receiver never applied, a later A08 that names another ward or bed, or a change to the record. Someone may be working round bad history, or the site may move beds by A08, which reaches the receiver with no location. Shutter can't weigh it, so it stops and names both. Next: Read what is named here, both visits or the later A08, in the source system and on the receiver's own screen, and put the patient right by hand or close the case. Where it is only another visit's movement, an approver can release this stop on the case page for the rows they read. Nothing is sent, and nothing will be until a person decides.

SPW-5.68. **FURTHER_MOVEMENT_RELEASED: A person released this stop for the rows they read.** An approver read the messages on the patient's other visit, gave a reason, and released this one stop. It holds only for those rows, and it releases nothing else. Next: None: a pass. Every other check still runs, and the write still needs its approval.

SPW-5.69. **NO_FURTHER_MOVEMENT: Nothing else stops this for the patient.** Shutter read this patient's further messages on every visit it can see and none of them stops the resend. A change made by hand at the receiver can't be seen this way. Next: None: a pass. Anything else on file for the patient, such as an out-patient attendance, is on the plan.

SPW-5.70. **PATIENT_UNREADABLE: The patient's identifier could not be read.** With no identifier, Shutter can't tell what else has happened to this patient, so nothing is sent. Next: Find the patient from the message itself and decide by hand.

SPW-5.71. **FURTHER_NOT_READ: Further messages for the patient could not all be read.** There were too many new messages to read at the moment of the write, or the source namespace could not be read, so whether something else has happened to this patient is not known. Nothing is sent. Next: Reinvestigate the case, or check the patient in the Message Viewer and decide by hand. A read that keeps running out of time needs more of it: further_messages.scan_seconds in the site profile.

SPW-5.72. **UPDATE_LOCATION_DIFFERS: The failed A08 carried a different location.** This A08 named another ward or bed than the receiver holds. Shutter sends an A08 as an update, which carries no location, so a resend could be accepted and verified, or the case closed, with the move undone. Shutter can't tell a move from a stale location, so nothing is sent or closed, and it names the patient and both places. Next: Check where the patient is in the source system and on the receiver's own screen, and move them there by hand if the A08 is right. Close the case once they are right. A site that repeats stale locations on full-state A08s can set further_messages.a08_location to show in the site profile.

SPW-5.73. **UPDATE_LOCATION_SHOWN: The failed A08 carried a different location, and the site shows it.** This A08 named another ward or bed than the receiver holds, and the site has said its A08s can repeat stale locations. It goes on the plan and stops nothing. The update the resend sends carries no location, so it moves nobody. Next: None: a pass. The line is on the plan: check the receiver's own screen, since the resend carries no location.

SPW-5.74. **SCHEMA_UNKNOWN: The message's schema is not loaded here.** The message names a schema category that Shutter's namespace does not have, such as a site's own variant of HL7 2.5.1 with extra segments. That is missing evidence, not an invalid message: Shutter cannot validate the message until the schema is imported. Next: Import the site's schema into Shutter's namespace (the Doctor's hl7_schemas check names the category and the command), then reinvestigate the case. Nothing is sent meanwhile.

SPW-5.75. **ENTRY_NOT_NAMED_WRITE: A write that doesn't name the catalogue entry that stops it.** The plan would resend and names no catalogue entry, but an entry that matches this case calls for something other than a resend. Only Rules only mode in a recorded scenario, the baseline, passes this. Next: Read the matched entry and decide by hand, or investigate again so the plan follows the entry.

SPW-5.76. **NO_BOARD_ANSWER: The board has to decide this, and nobody on it could answer.** The scenario catalogue gives this case to the board or to a person, and no board member could answer. Nothing is planned and nothing is sent, because a plain resend would replace that decision with one nobody took. Next: Read the matched catalogue entry and the patient's record, then decide how to recover the message by hand, or investigate again when the agents can run.

SPW-5.77. **RECEIPT_PAYLOAD_DIFFERS: The receiver holds this key with other content.** The receipt shows the operation key is taken, not that this message is what the receiver holds: another movement in the same second, or a corrected message, shares the key, and the bed sits outside the digest. The receiver refused or ignored this message, so closing the case as committed would drop it. Nothing is written. Next: Compare the two at the receiver: this message and what its receipt holds. Correct the patient's location there if this message is the right one, then mark the case handled.

SPW-5.78. **RECEIPT_THEN_CANCELLED: A cancel followed the receipt.** The receiver holds a receipt for this operation, but a cancel was recorded at or after its event, so the receipt does not show it stands. Closing the case as committed could leave the patient where the cancel put them. Nothing is written. Next: Look at the cancel and at what the receiver holds now, and decide whether this movement should stand. A re-issue under the first message's event time cannot reach the receiver through its API: its key is taken. Correct it there if it is due, then mark the case handled.

SPW-5.79. **WRITE_NOT_RELEASED: The receiver wrote during a rehearsal.** The receiver applied a dry run, so the operation is in effect with no approval or policy behind it. It is on the record as an attempt, and the case does not close as a success, whatever the verifier reads. Next: Check the operation at the receiver, correct it there if it should not stand, and mark the case handled. Tell the receiver's team it does not honour dry_run, and take dry_run off its entry in the site profile until it does.

SPW-5.80. **ENGINE_STILL_TRYING: The engine is still trying this message.** The message is Queued or Delivered at a stock HL7 TCP operation, or that operation is retrying, or a copy of it is in hand. The engine will deliver it when the receiver returns, so a resend now would deliver it twice. Nothing is written and the case waits. Next: Wait: the case is judged again when the engine has finished. To act sooner, read the message in the Message Viewer. Reopening the case judges it again at once.

SPW-5.81. **ENGINE_DELIVERED: The engine delivered this message itself.** The source production's engine marked this message Completed at the receiver, on a route where that means the failure the case opened on has passed. A resend would deliver it twice, so nothing is written. The case is resolved in the engine's words, or left for a person where the operation's reply settings or the case's kind mean Completed doesn't settle it. Next: Nothing to resend. Read the case's outcome: where the acknowledgement can't be established, check the receiver's own screen and record what was found.

SPW-5.82. **ENGINE_UNREADABLE: The engine's record of this message could not be read.** The operation, the header the delivery went on or its event log could not be read, or the header's status isn't one the check knows, so whether the engine is still trying this message is not known. Unknown is not nothing pending: nothing is written. Next: Collect the evidence again. If it stays unreadable, check that the source production runs and the case's message is there, then decide by hand.

SPW-5.83. **ENGINE_SETTLED: The engine has finished with this message.** Every retained log row for the message shows a connection that never opened, or the case came from the acknowledgement feed, which raises a case only after the engine has delivered. The retained log can't prove nothing was lost from it. Next: None: a pass.

SPW-5.84. **ENGINE_NOT_IN_SCOPE: The target is not a stock HL7 TCP operation.** This check reads the engine's hands only at a stock HL7 TCP operation, so at this target the engine's own delivery isn't looked at. Next: None: a pass. Where a receiver is reached through a site's own class, the engine's hands are not read, so keep FailureTimeout 0 at such a receiver if it also has an API.

SPW-5.85. **RECEIVER_MAY_HOLD_IT: The receiver may hold this message.** The first attempt reached the receiver (the connection was lost after the frame was written, a read timed out, or the log does not say), and the operation then gave up. A resend could file it twice. Nothing is written, and neither Shutter's API route nor its engine route resends this. Next: Check the receiver's own screen for this message first, then decide by hand and mark the case handled. If it must go again, a person resends it in the Message Viewer.

SPW-5.86. **HOLD_EXPIRED: A hold on this patient's messages ran out.** Messages held behind this case were released unreviewed when the hold reached its limit, in the order they arrived. They may have reached the receiver before this case's message, so a later resend could put the record backwards. Next: Read the released messages named in the case's notes against the receiver's own screen, and review this patient by hand. The plan is stale: investigate again before anything is sent.

SPW-5.87. **ENGINE_ROUTE: An engine resend's conditions.** Every condition for resending this message through the engine holds. It goes byte for byte through the stock resend, and the declared acknowledgement says what its Completed means. Next: None: a pass. A person still approves the resend.

SPW-5.88. **ENGINE_ROUTE_ABSENT: The engine resend is not in this build.** This receiver is declared for a resend through the engine, but the item that makes it is absent or disabled here, so Shutter sends nothing. Next: A person resends in the Message Viewer.

SPW-5.89. **ENGINE_ROUTE_REFUSED: An engine resend's condition failed.** A resend through the engine goes only when every condition holds, and the one named here does not, so nothing is sent. Next: Read the failed condition named here. Correct the declaration or the operation if it is wrong, or recover the message by hand.

SPW-5.90. **ENGINE_ROUTE_NO_API: No API at this receiver.** There is no API at this receiver: the never-opened rule before the send and the declared acknowledgement after it take the place of the version, the receipt and the dry run. Next: None: a pass. A person still approves the resend.

SPW-5.91. **FURTHER_MOVEMENT_NEW: Another visit moved after the plan was made.** This site lets a movement on another visit through, shown on the plan, so the approver sees it. A new admission or ward stay for the same patient under another visit number reached the engine after the plan was made, so the plan did not show it and an approval of that plan does not cover it. Nothing is sent on that approval. Next: Nothing to do yet. Shutter reads the evidence again and makes the plan afresh with the new visit shown, and an approval given before is void, so the approver reads the new visit and decides again. A case that stays blocked with this reason could not complete its refresh: read the new visit the check names and decide.
