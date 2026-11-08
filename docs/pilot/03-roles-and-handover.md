# Roles and handover

Each row needs a person's name, not a team. One person may hold several rows, but the receiving-team owner must be in the team that can correct the record.

| Work | Accountable | Name |
| --- | --- | --- |
| Decision to pilot, and scope | Integration service owner | |
| Installation, configuration and what reaches Shutter | Integration technical lead | |
| What the receiver's state, receipts and ACKs mean | Receiver owner, with the supplier's confirmation | |
| Patient-level corrective action | Receiving clinical or application team | |
| Approving a recovery | Named approver | |
| Accepting unresolved work | Named receiving-team owner | |
| Clinical hazard assessment and residual-risk advice | Clinical safety officer | |
| Model use, email and retention | Information governance or data protection lead | |
| Calling a stop | Anyone on the stop list; service owner accountable | |
| Clearing a stop and restarting a stage | Change or recovery owner | |
| Supplier and manufacturer duties | Named explicitly, not assumed to fall to the hospital | |

## What each right takes in IRIS

Check this in the laboratory with real sign-ins. Without a stop switch, **Shutter's roles aren't built to do the whole stop.**

| Task | Needs |
| --- | --- |
| Read cases, close one by hand, send a drafted email | `Shutter_Operator` |
| Approve or reject, save the site profile, abandon a stuck case | `Shutter_Approver`, and membership of the Workflow role "Shutter Approvers" to approve |
| Disable a connector or stop the production | A site administrator's right in Interoperability. Shutter's roles aren't given it |

So your stop list needs a person, or a pair on call together, holding both the second and third rows. An approver can also change the policy they approve under, and each saved version keeps who saved it. For a two-person rule, give approvers a role of your own without `Shutter_Configure`, and read the profile's history at each review. Set `approvers.close_needs_approver` to true if only an approver should close a case by hand.

## Handover

Shutter has no field for who owns a case, and **nobody is told when a case needs someone** unless your release has reminders for cases left open and the site has turned them on (off by default, and no mail goes in shadow mode). A reminder doesn't show anyone read it or took the case on. After 24 hours undecided, a waiting plan's case moves to `escalated`, with no mail or alert of its own. So keep your own list, and use this for each unresolved case:

```text
Case id:
State, and why it stopped:
Was a write attempted? Outcome:
What the receiver holds now, and who checked it:
What the patient's record needs:
Owner (person), and when they accepted it:
Closed by, how, and when:
```

A case that a person corrects outside Shutter is then marked handled, with the reason, on its page.

If nobody can accept a case, recovery stops ([07](07-stop-and-withdraw.md)). During a period with no owner, don't approve anything.
