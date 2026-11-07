# Stop and withdraw

Keep this page where the on-call person can reach it. **A stop halts Shutter's recovery only.** The hospital engine's own delivery and retries, and other people's writes to the receiver, carry on. Stopping undoes nothing already written.

## When to stop

Any of these pauses recovery at once. Anyone on the stop list may call it, without asking first.

- A write outside the declared scope.
- A write without its required authorisation.
- A write to the wrong patient or the wrong receiver, or evidence of one.
- An attempted write nobody can account for.
- Evidence that a dry run changed the receiver.
- A restore or configuration change, at the source or the receiver, that voids the acceptance evidence.
- A material privacy incident.
- Nobody available to own manual exceptions.

**An unexplained wrong-patient write, or a write nobody authorised, ends the pilot** until a new signed decision says otherwise.

Many cautious stops may be a reason to end a pilot for lack of value. They are never a reason to relax a control during it.

## How to stop

If your release has a switch to stop recovery (`CHANGELOG.md`), use it, follow the words beside it, and go to step 5.

Otherwise, at release 1.0.0 there is no such switch. These steps were tried on IRIS for Health 2026.2 against Shutter's demo receiver, so rehearse them on yours.

1. **Note the time,** and tell the approvers to stop approving.
2. **Disable each receiver's connector** in Shutter's production: the item named after the receiver. In the Management Portal, Interoperability, Configure, Production, select the item, untick Enabled, Apply. Or in a terminal, in Shutter's namespace:

   ```
   Do ##class(Ens.Director).EnableConfigItem("<connector item>", 0, 1)
   ```

   The terminal form is the one that was tried.

   Dry runs, pre-write reads and writes all go through this item, so they wait in its queue. The Evidence Collector and the Verifier are separate items and keep running, as does intake, so new failures still open cases.
3. **Void approvals.** An approver saves the site profile with a small change, such as a word in `approvers.escalation`. Any save voids every approval that hasn't yet passed its final gate.
4. **If you can't disable the item,** stop `Shutter.Production` instead, and save the profile first if you can. This is worse: read-back stops too, work resumes when it starts again, and any failure forwarded while it's down is refused and never opens a case, so watch your ordinary alerts.
5. **List what's open** with the queries in [08](08-daily-review.md). Do not resend an uncertain operation; read the receiver.
6. **Tell the owner of the ordinary feed.** Its retries may still deliver.
7. **Give each unresolved case to a named person** ([03](03-roles-and-handover.md)).

## How to clear a stop

Only the person named for this in the [decision record](00-decision-record.md), with the reason written down. **Enabling the connector sends what's waiting in its queue:** in testing, an approved write held for three minutes went to the receiver within 30 seconds of enabling. Waiting dry runs and reads go out too.

1. Find out why the stop happened, and whether the scope or hazard log must change.
2. Save the site profile again just before enabling, so no approval from before survives. In testing, the held case then blocked at the gate with `APPROVAL_SITE_PROFILE_CHANGED` and nothing was written.
3. Look for cases reading `executing`. Their write has passed the final gate, so a save doesn't void it, and if it's still queued, enabling sends it. Read the receiver and decide first. Removing a queued message by hand wasn't tested, so try it in your laboratory.
4. Enable the items, and watch the first case through.

## Withdrawing

Work through these in order. Your technical lead has the full commands in `docs/INSTALL.md`, section 9.7.

1. Stop as above, and close or hand over every open case.
2. Keep the ordinary feed's delivery and alerting as they were throughout.
3. Take each watched namespace off. It removes the two items, gives your item the name `Ens.Alert` back, and the production is updated, not stopped:

   ```sql
   SELECT Shutter.Setup_OnboardRemove('<NAMESPACE>')
   ```

   **Do this before dismounting Shutter's database:** once onboarded, a production needs it, and with it dismounted a failing operation's job ended with an error, alerts stopped reaching your consumer, and the production wouldn't start.
4. **Send a test alert** and check your original consumer receives it.
5. Purge that namespace's messages under your own rules, **then** run the removal again with `{"unmap": true, "credential": true}` as a second argument. Unmapping first leaves message bodies behind for good. Without `credential`, the sign-in stays, with a password that doesn't expire, so disable it by hand.
6. Revoke Shutter's other credentials and outside destinations.
7. Keep the agreed evidence, and apply your [deletion dates](05-data-flow-and-retention.md). If your release lists a full uninstall, use that. Otherwise stop `Shutter.Production` and remove the namespace or the instance: `zpm "uninstall iris-shutter"` at 1.0.0 removes classes only, leaving productions, web applications and data.

## Rolling back software

- Do not restore an old database just to undo Shutter's state.
- An earlier image doesn't undo what was written at the receiver.
- Do not resume old queues or approvals after a rollback without reconciling them first.
- Try the previous image against a copy of the kept data, in the laboratory, first.

**A record already changed needs the receiver's own correction procedure.** Rolling back Shutter is not a clinical rollback.
