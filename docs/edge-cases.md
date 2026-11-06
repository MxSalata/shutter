# What can go wrong when you resend

A resend in a hospital can do harm with every check passed. This page lists ways it can go wrong and what Shutter does about each. **Seen in practice** marks the ones the author has met at hospitals. **Handled**: a test shows the outcome. **Stops and flags**: nothing is written and the case says why, so a person decides. Stopping is a right answer here, because the alternative is a guess written to a patient's record. **Says so**: Shutter tells you and takes no action.

Everything is played against the demo receiver or a stub listener; what a real receiver does is for its interface specification to say. "In CI" means IRIS for Health Community 2026.2, with the board's agents replaying recorded live runs; the gates, the rules and the receiver run for real.

| What goes wrong | What Shutter does | Proof | Not covered |
| --- | --- | --- | --- |
| A transfer never reached the receiver | **Handled.** One conditional write once released, checked against receipt and history | S2 in CI | Verified compares the operation's key, not its ward or bed |
| The receiver took it, but its answer was lost | **Handled.** Reads the receipt, finds it, resends nothing | S3 in CI | A receipt under the same key with different content reads as the same |
| *Seen in practice.* The receiver changes while a resend waits for approval | **Handled.** That approval is void, nothing is written on it, the case is planned afresh | S7, S20 in CI, [boundary](../tests/e2e/boundary_check.py) | A change that doesn't move the version; a fix made before the case; a hand entry recorded as an update, or timed before the failed event: the new plan can propose the resend again |
| *Seen in practice.* A later move overtook the failed one, but history is owed | **Handled.** Per receiver: closed, or correction steps for a person | S22 in CI | Wards aren't compared. A failed update or discharge followed by a later transfer closes the same way today. A receiver with no declared category counts as current state |
| A transfer timed in the hour the clocks go back | **Stops and flags.** The case goes to a person | S21 in CI | Europe/London only. In an outage, one such item sends its whole chain to a person (read, not played) |
| *Seen in practice.* Refused as "duplicate", but nothing filed | **Handled.** That refusal closes nothing; receipt and history decide | S4 in CI, [Verify](../tests/unit/Shutter/Test/Verify.cls) | A receipt written before filing. A 200 saying already committed, on a first delivery, counts as delivered and opens no case. A receiver that still says duplicate to the resend hasn't been played |
| A newer message on its way | **Stops and flags.** Held at gate and connector, named | S24 in CI | The same visit only; the wait has no limit |
| A merge, perhaps undone since | **Stops and flags.** Never sent automatically | S15 in CI | Later activity and the merge's age aren't shown |
| AE at a plain MLLP receiver. *Seen in practice:* a listener allowing one connection | **Stops and flags.** Case with evidence, no resend, no MLLP connection of Shutter's own | [plain receiver](../tests/e2e/plain_receiver_check.py) in CI | Needs AlertOnError; every one costs a person. The test counts messages, not connections; the connection claim rests on reading the code |
| Two patients in one message | **Stops and flags.** Not mapped, nothing sent | [trigger](../tests/unit/Shutter/Test/Triggers.cls), [gate](../tests/unit/Shutter/Test/Gate.cls) | The A17 test checks the trigger, not a message with two patients. The case names the first patient only |
| Any result or order, where a resend could put a preliminary over a final | **Stops and flags.** Results are never resent | [gate](../tests/unit/Shutter/Test/Gate.cls), [onboarding](../tests/e2e/onboard_check.py), by hand | Over 2 MB: an alert, no case |
| Completed means less than it reads | **Says so.** Onboarding states what it proves, per TCP operation | [onboarding](../tests/e2e/onboard_check.py), by hand; [Verify](../tests/unit/Shutter/Test/Verify.cls) | Batch ACKs; other adapters get a general line |
| Two approvers, an old tab, a double click | **Handled.** In the web app a stale approval is refused, and one approval makes one write; in the inbox a wrong digest blocks the case | [boundary](../tests/e2e/boundary_check.py), [inbox](../tests/e2e/inbox_check.py) in CI | Played in sequence, not at the same instant. An inbox rejection names no digest. The later person's decision isn't recorded |
| The write landed, but the answer says conflict, as a proxy might | **Handled.** One write. The case finds the receipt and closes, and resends nothing. In rules-only mode it stops and flags instead | [edge rows](../tests/e2e/edge_rows_check.py) | Played with a fault in the demo receiver. The case's first note still says the write was refused |
| A write to one of two receivers | **Handled.** The other receiver's version doesn't move, and its plan still waits for its own approval | [edge rows](../tests/e2e/edge_rows_check.py) | Two receivers, approved one after the other |
| A move recorded hours late: after the discharge, or after a later move applied | **Handled.** Per receiver: closed with nothing sent, or correction steps for a person | [edge rows](../tests/e2e/edge_rows_check.py) | After a discharge, this rests on the receiver refusing the move. Times are taken as stated |
| Someone resends by hand while an incident waits | **Stops and flags.** That chain stops at the sequence rule and nothing more goes to it; the other chains carry on | [edge rows](../tests/e2e/edge_rows_check.py) | A hand resend under the same key, which moves the version |
| The sender repeats a failed move, under a new control id or a blank one | **Handled.** The key and the digest come from the event, not the control id: the open case takes the repeat, and no second case opens | [edge unit tests](../tests/unit/Shutter/Test/EdgeRows.cls) | A sender with no EVN-6 that restamps EVN-2 makes a new key, read as a later move |
| A repeat of the move lands while the resend waits for approval | **Stops and flags.** The approval is void, nothing more is written, and the case says already committed, or overtaken by a later move | [edge rows](../tests/e2e/edge_rows_check.py) | Played in rules-only mode, so a person closes it |
| The same operation comes again with other content while the plan waits | **Stops and flags.** The case blocks and says the content changed; nothing is written | [edge rows](../tests/e2e/edge_rows_check.py), [edge unit tests](../tests/unit/Shutter/Test/EdgeRows.cls) | A bed-only change isn't noticed (the digest leaves the bed out). The headline gives the reason; the reason code only says handed to a person. The next correction opens its own case with no link to the first |
| The message's text would now map to another ward | **Handled.** The operation a case writes is built from the case's own fields and the digest its plan bound, not re-read from the message | [edge unit tests](../tests/unit/Shutter/Test/EdgeRows.cls) | A mapping change before the case opened |
| A note with a raw line break, or a second PID | **Stops and flags.** Validation refuses the message, the case blocks, and nothing is written | [edge rows](../tests/e2e/edge_rows_check.py), [edge unit tests](../tests/unit/Shutter/Test/EdgeRows.cls) | These two shapes only |

## What it doesn't do yet

- It compares one visit at a time, not a patient's other visits or merged records.
- It doesn't read death or restriction fields.
- It sends an operation, not the message, so a failed A08 isn't recovered.
- Verified means this operation was in the receipt and history when read. Ward and bed aren't compared, and closed cases aren't read again.
- It takes times as stated: two sources a second apart aren't simultaneous, and a slow clock isn't noticed.
- It trusts the receiver's API: an ignored condition, a gateway's page or a partial history isn't detected.
- On the alert route it reads the alert's words and the session's first HL7 message, and doesn't see a hand resend.
- When no agent can answer, cases take the rules path; a person still approves.
- Failover, mirrors and restores are untested, and there is no switch to stop all writes.

**Check it yourself:** the [scenarios](readme/scenarios.md) name their modes; run them with `tests/e2e/scenario_check.py --url "$IRIS_URL" --approve S4 S7 S15`, and the approval attacks with `tests/e2e/boundary_check.py --url "$IRIS_URL"`.
