# Receiver acceptance

Stage 3 needs this for the one receiver in scope. Every proof Shutter's project has run was against its demo receiver or a stub, so **none of it tells you what your receiver does.** Only your receiver's specification, its supplier and your own tests can.

Test against a non-production copy, with synthetic patients. If your release has a receiver conformance kit, run it as well as this list, not instead of it.

An answer of "no" or "unknown" on a required line means no recovery to this receiver. Stay in observation.

| # | Required: is this true of your receiver? | Answer | Evidence and who gave it |
| --- | --- | --- | --- |
| 1 | It has a readable current state, receipts, a capabilities answer and an operations address | | |
| 2 | A write with an out-of-date expected version is refused and changes nothing | | |
| 3 | A dry run changes nothing, including its onward feeds and audit. Check by reading the record before and after | | |
| 4 | The same operation key sent twice makes one change, and its receipt stays the same | | |
| 5 | Its receipt and history are complete when read: not a part, a cached copy or a delayed copy | | |
| 6 | An error is an error: a gateway or sign-in page can't answer in its place with a 200 | | |
| 7 | A write through its API has the same effect as a delivered message, including its own onward feeds and audit | | |
| 8 | Its worst time to commit is known, and `UncertainSettleSeconds` on the Verifier is set above it (a case is judged about 70 s after the attempt as shipped) | | |
| 9 | It has a way to correct a wrong write, and the receiving team can use it | | |

These should also be answered and written down, since they change what a case means:

| # | Question | Answer |
| --- | --- | --- |
| 10 | What does its positive ACK mean: received, or accepted by the application? Ask the supplier. A commit ACK and an application ACK read alike on stock settings | |
| 11 | Is its category `current_state` or `history_of_record`? State it, with its `tier`, on the profile entry. An entry with no category reads as current state | |
| 12 | Can anyone else write to this record meanwhile? A hand entry can change what a resend should do | |
| 13 | Does it refuse an occupied bed with the code `bed_occupied`? Shutter looks for a conflict only after that refusal. If not, accept that hazard by name | |

Also confirm:

- [ ] `FailureTimeout` 0 on the engine's operation to this receiver. With -1, the stock default, the engine delivers the same message when the listener returns, on top of Shutter's resend.
- [ ] The receiver owner has signed this page.
- [ ] A restore, version upgrade or configuration change at the receiver voids this page: stop, and test again.
