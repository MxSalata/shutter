# Stage plan

Move up one stage at a time, each with a signed [decision record](00-decision-record.md). Nothing moves on by itself, and finishing a stage does not make Shutter a production service.

## Features that may not be in your release

These came after 1.0.0, so not every release has each of them. Look for them in `CHANGELOG.md`. **Every stage works without them**, using the right-hand column.

| Feature | Used in | Without it |
| --- | --- | --- |
| Shadow mode: cases are investigated and no recovery is attempted | Stage 2 | Give receivers no API, as below. Cases can't see the receiver's state, so you learn less |
| A switch to stop recovery | Stages 1 to 3 | Disable the connector items ([07](07-stop-and-withdraw.md)) |
| A census of failures against cases | Stage 2 | Count failures by hand ([08](08-daily-review.md)) |
| A receiver conformance kit | Stages 1 and 3 | Test by hand with the supplier ([06](06-receiver-acceptance.md)) |
| A site's own acceptance runner | Stage 1 | Replay known failures by hand and record each result |
| A full uninstall | Withdrawal | Remove the namespace or the instance ([07](07-stop-and-withdraw.md)) |

**Observation without shadow mode.** Leave every receiver as an entry with no `api` and all `features` false, which is how onboarding drafts them. The gate then blocks any write, and no request goes to that receiver. Do not add API paths during this stage.

## Stages

| Stage | Way in | What you do | Way out |
| --- | --- | --- | --- |
| **0. Scope and authority** | A named service owner and receiver owner; intended use written down | Agree [scope](01-scope-and-exclusions.md), [owners](03-roles-and-handover.md), data destinations and who may stop | Clinical safety, information governance and change owners agree a laboratory exercise may go ahead |
| **1. Disposable laboratory** | An isolated test receiver; synthetic messages only; a way to rebuild it all | Install with `-Ddemo=0`. Test each role. Replay known failures. Do the stop drill and clear it ([07](07-stop-and-withdraw.md)). Restart the production. Practise withdrawal | No unexplained receiver writes; a recorded result for each test; failures and untested areas accepted or taken out of scope |
| **2. Connected observation** | Change approval to hook in the production; no receiver can be written to; model off unless separately approved | Run the onboarding plan, read it, then apply it. For an agreed period, review every case daily ([08](08-daily-review.md)). Send no drafted emails unless agreed | You understand what reaches Shutter and what doesn't; a reviewer has judged the cases; the workload is manageable; **no recovery attempt is on record** |
| **3. Bounded recovery** | The checks below, all met | One receiver and the agreed triggers; named approvers; one case at a time; reconcile daily | Every attempt accounted for; disagreements and uncertain outcomes handled; scope unchanged without a new decision |
| **4. Decide** | The period ended, or a stop was called | Compare what happened with your [criteria](09-outcome-report.md) | Continue under a new decision, return to observation, or [withdraw](07-stop-and-withdraw.md) |

Onboarding changes the watched production: it adds two items and renames your `Ens.Alert` item, and the production then needs Shutter's database to be mounted. It is reversed by [the withdrawal steps](07-stop-and-withdraw.md).

## The way into stage 3

All of these, with evidence in the decision record. **If any is missing, stay at stage 2 or go to stage 4.**

- [ ] **A named receiving-team owner and deputy** who accept unresolved work and patient-level correction. Shutter can stop, but it can't correct a record. With no owner, nobody picks up what a stop or a failed recovery leaves behind, so **recovery does not start, whatever else is ready.**
- [ ] A separate signed decision. Approval of stage 2 does not carry over.
- [ ] [Receiver acceptance](06-receiver-acceptance.md) complete, with no open "no" or "unknown" on a required line.
- [ ] Remaining hazards accepted by name in [your log](04-hazard-log.csv).
- [ ] A person on every write. As shipped, tiers 1 and 2 write with no person. Set `single` and `ordered` to `approval` on all three tiers of the site profile's `policy`, then show in the laboratory that a case stops at `awaiting_approval`.
- [ ] One case at a time. Above the profile's `incident.threshold` (5 as shipped), one decision can cover many cases. Raise it far above your feed's volume, and test that in the laboratory.
- [ ] `FailureTimeout` 0 on the engine's own operation to this receiver, so it doesn't deliver what Shutter has resent.
- [ ] Staff trained: approvers read the evidence, not only the plan. A plan can be wrong, and "verified" means only that the receiver's receipt and history held the operation's key.
- [ ] Every person who may stop has done the [stop drill](07-stop-and-withdraw.md), and someone is on call whenever recovery is on.
