# Picking up where Shutter stopped

What happens to cases, approvals and runs when a person leaves the page, the connection drops, the production restarts,
Shutter is upgraded or the instance fails over, and how a person carries on without doing anything twice. Each line names
the contract section or the source it rests on. What is not covered yet is at the end.

Underneath all of it: Shutter's records live in IRIS, not in the browser. A page that is closed, reloaded or cut off reads
them again, and nothing a person decided waits in the page.

## You left the page, or came back to it

| What | Where it is kept | How you pick up |
| --- | --- | --- |
| The Cases list's filters | In the address (`web/src/lib/listParams.ts`) | Back from a case returns to the same filtered list. |
| The case's tab, the story step a link opened, the S8 comparison, the Ask panel | In the address: `?tab=`, `?open=`, `?show=compare`, `?ask=1` | A link or a reload opens the same place. |
| Work the case is doing (collecting, investigating, a gate, a dispatch, a verification) | The case's workflow, in the production, not in the page | The case page reads the case, its events and its parts again while the case is open. |
| A question to the agents about a case | A server record (`Shutter.Store.CaseQuestion`), which reads "The agent is answering…" until it ends | Come back to the case: the answer is there when it has come. One left pending or answering for 15 minutes (`STALEAFTERSECONDS`, a restart in the middle of it) is marked failed by the next read, so the panel never waits for ever: ask again. |
| A review opened but not confirmed | Nothing: opening, switching and cancelling a review send nothing | Open the review again. It reads the case as it is then. |

## No answer came back

Every change a person makes carries an `Idempotency-Key`. The same key with the same body is answered from the first reply
for a day, and the same key with another body is refused; the key is scoped to the user, the method and the route
([CONTRACTS 5](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#5-the-rest-api-for-the-app),
`Shutter.Store.Idempotency`). A decision on a case's plan is also bound to the plan's digest and the case's version, and a
decision on a case already decided is refused with who decided first.

- **A decision on a case whose answer never came** (the connection dropped, or a gateway's page came back in the API's
  place): the review says it can't tell whether the decision was recorded and keeps the comment as sent, and pressing the
  same button again sends the same decision under the same key. If the first was recorded, the server answers with that
  record or refuses this press naming who decided; nothing is decided twice. If the page reads the case moved meanwhile,
  the review stops and says the change may be that decision: the Audit trail says who decided. It never says nothing was
  decided.
- **The approval of an outage's resend** whose answer never came says it can't tell whether it was recorded, and points to
  the card, which is read again. Its confirming button stays off until the dialog is opened again, and "Already handled by
  hand" does the same. Only an offered set can be approved, so a second approval of a set already approved is refused ([CONTRACTS 17.8](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#178-the-send-v151-to-v154)).
- **A recovery write whose answer was lost** is recorded as `uncertain`, never as sent or not sent, and the verification
  reads the receiver's receipt and history to settle it
  ([CONTRACTS 5.1](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#51-attempts-and-verification-v121)).

## The production restarted

A clean stop and start, a container restarted, or a crash. Read from the source and the contract; a restart has not been
played for this page.

- **Every open case is noted and none is closed.** At each start of `Shutter.Production`, every case not in a closed state
  gets one event by `system` (ref `start:<time>`): "The production started at <UTC> while this case was <state>". Work in
  flight resumes when the production was stopped cleanly: queued requests keep their place and suspended alarms reload
  ([CONTRACTS 12](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#12-the-install-v115), the start sweep).
  The case page says so under the progress strip until the case moves on, with when the production started and what to do
  now, and the Audit trail names the event "Production started".
- **A working case that does not move on** within the quiet minutes (`abandonAfterMinutes`, 15 by default and never fewer
  than 11) can be abandoned by an approver: "Still working" on the case's Summary tab, or `POST /cases/{id}/abandon`. The
  case fails with disposition `abandoned`, nothing more is sent, and a reinvestigation reopens it, so a wrong abandon is
  recoverable. A case whose workflow still has a message in flight is refused as `busy`, with when to try again
  ([CONTRACTS 5](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#5-the-rest-api-for-the-app),
  "Abandoning a case the workflow left behind").
- **A case waiting for approval** waits on its approval task, a deferred message, which a clean stop keeps as it keeps
  queued requests: decide on the plan as before. Abandoning is never offered there; the server answers `busy` with
  `deferred: true`, and the way out is rejecting the plan.
- **A recovery write cut off by the restart** leaves its dispatch permit `admitted` with no lock. It becomes `uncertain`,
  never "not sent", and that latches the recovery stop: Shutter starts no recovery write until an approver clears it in
  Settings, and the message, if it comes round again, is refused rather than retried
  ([CONTRACTS 18](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#18-shadow-mode-and-the-recovery-stop-v150)).
- **An outage resend under way** stops: a row found `sending` stops the run with nothing more sent, and a message whose
  life crosses a production start is refused from the set, so a person sends it
  ([CONTRACTS 17.8](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#178-the-send-v151-to-v154), check 6).
- **The index host's release runs** still open are marked `interrupted`
  ([CONTRACTS 8.1](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#81-the-index-and-the-indexer)).
- **In a site's own production** filled by `InstallInto` (shape B), the start sweep does not run: no note and no notice on
  the case. Abandoning works there as anywhere ([CONTRACTS 12](https://github.com/MxSalata/shutter/blob/main/docs/CONTRACTS.md#12-the-install-v115)).

## Shutter was upgraded

- **The data stays.** `docker compose down` and `up`, and a rebuilt image over the same volume, keep every case, approval,
  review and profile change; proven on 1 November 2026
  ([INSTALL 8](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md#8-upgrading-in-place)). The production's
  next start notes the open cases as above.
- **An approval given before an upgrade that changes the gate's policy version** is refused at dispatch with
  `APPROVAL_POLICY_CHANGED` (or `APPROVAL_CATALOGUE_CHANGED` for a plan matched against the old catalogue): nothing is
  sent, and the case comes back to a person to investigate again and approve the new plan. Each release's notes in
  [INSTALL 8](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md#8-upgrading-in-place) say when this applies.

## Failover, mirrors, restore and test copies

Not tested. A restored engine, a mirror failover in the middle of a run, or a test copy refreshed from live are not
guarded: there is no instance identity and no monotonic reference
([INSTALL](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md), "Restore, mirror, test copy";
[SAFETY](https://github.com/MxSalata/shutter/blob/main/docs/SAFETY.md), "Restart, failover, restore"). The production
needs Shutter's database once it is applied, so before a failover, a restore or a move, take the namespace off or plan for
it. A site tests what its own failover does.

## Not covered yet

- The same "no answer came back" words on the incident's decision, Close, Abandon, Reinvestigate, Convene and the
  escalation sends, which show the error as it came; and keeping the outage approval's key across a lost answer.
- "Abandon" in the web for a case waiting for approval whose approval task an unclean stop lost (the API allows it).
- A list of the cases noted at the last start.
- Search of the Cases list's full history (it filters the newest 100 today), on request.
