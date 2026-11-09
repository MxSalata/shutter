# Shutter 1.4.0: the design for tier C's last rows and the email wording

Built on branch `tier-c` from 1.3.2 with tier C and its fixes (head c0c94311). Decided on 9 Nov 2026: build all of it for
1.4.0, so that tier C is complete and every pathology rig row passes, and narrow the patient check for orders and results
to newer messages of the same order. `docs/CONTRACTS.md` version 1.53 says the same in contract form (sections 10, 11 and
17.8).

The product rules this design keeps: hospitals first; Shutter never touches an ADT^A40 merge that is not an exact resend
(every send here is the engine's own resend of the stored body); only what is needed goes to a model (nothing here goes to
one); an escalation email carries identifiers and the date of birth, no more (its content is unchanged).

## What 1.4.0 must pass

`tests/e2e/pathology_check.py` is locked: it says what a site wants, and nothing here changes it. The rows that read FAIL
or NOT WIRED on c0c94311, with their exact wording:

| Row | The rig's assertion | Today | Part |
|---|---|---|---|
| O5.c | After one approval only those arrive, once each, and the read-timeout, AE and CA messages hear nothing further for 30 s | FAIL: the patient check holds the five | 1 |
| O6.d | A resend that fails, of a message with an earlier case, is shown as failed with no new case or alert to prompt it, and nothing further goes | NOT WIRED | 2 |
| O8.c | Its refusal closes the item as already delivered, not as a failure | NOT WIRED | 3 |
| O8.d | Unknown receiver: the page offers already handled by hand, and nothing has been sent | NOT WIRED | 4 |
| O8.e | Choosing that sends nothing for 30 s and closes the item as handled by hand | NOT WIRED | 4 |

Part 5, the escalation email page, has no rig row: its proof is unit and component tests, and `tests/e2e/roles_check.py`.

Every other row must still pass, O5.b ("What is offered is exactly the never-opened messages, in order, and at no
reading anything else") and O8.b ("Refusing receiver, holding the message already: one approval sends it exactly once")
above all, since parts 1 and 3 change what is offered and how a refusal ends.

## 1. O5.c: the patient check narrowed for orders and results

### Why O5.c fails

Every rig result has its own MRN, its own placer order (ORC-2 and OBR-2 equal to the control id, with no namespace) and
its own visit, and all of them share one NHS number. The row fails five results while the receiver is down, then sends
three more once it is back: T (a read timeout), R (AE) and C (CA, Completed). `Shutter.Util.PatientCheck` holds a
message when any newer message to the item for any of its PID-3 identifiers is Queued, Delivered or Completed, so C holds
all five ("a newer message for identifier 9997001001 (NHS) reached the receiver"), the second close offers nothing, the
outage goes to `needs_person`, and the approval is refused. The check does what its rule says; the rule is wider than an
order or a result needs.

### Which messages take the narrowed check

A candidate takes the narrowed check when all three hold:

1. its receiver's profile entry has `category` `orders_results`;
2. its MSH-9.1 is ORM, OML, OMG, OMI, ORU or OUL;
3. at least one of its ORC or OBR segments carries an order number (below).

Anything else (ADT, SIU, MDM, an acknowledgement, an order or result with no order number, or a receiver of another
category) keeps today's patient-wide rule, unchanged, with one tightening that applies to both paths: a newer header whose
body can't be read now holds the message (today it is skipped). The narrowed rules add holds for order links, merges and
unreadable reads; the only thing they remove is the patient-wide hold on a newer message proven to be about another order.

### The order keys

`PatientCheck.Orders(msg)` reads every ORC and OBR segment by name (an ORU can carry several order groups, and several
PIDs), and gives for each segment:

- `placer`: ORC-2, else OBR-2 (EI: entity identifier .1, namespace .2);
- `filler`: ORC-3, else OBR-3;
- `parents`: the parent order of ORC-8 and OBR-29 (EIP: its placer as .1 with subcomponents, its filler as .2);
- `control`: ORC-1;
- `status`: OBR-25.

Two numbers are **the same** when their identifiers are equal and their namespaces are equal or either is blank, and
**different** when their identifiers differ, or both namespaces are present and differ. A placer is compared only with a
placer and a filler only with a filler, since they are numbered by different systems; a parent placer is compared with a
placer and a parent filler with a filler.

Two order groups are **related** when any of their numbers or parents is the same (own number to own number, own to parent,
parent to own, parent to parent). They are **proven distinct** when they are not related and they carry a number of the
same kind to compare: both a placer, or both a filler. Two messages are about **other orders** when each has at least one
order group and every pair of groups, one from each, is proven distinct. Placer group numbers (ORC-4) are not keys: the
orders of one requisition are independent, and a result of one may go after a result of another.

`Related`, `Distinct` and `OtherOrders` are pure, with a table test (`PatientCheck:TestOrderKeysTable`).

### The rules, each with an example and its proof

For a candidate M, after the reads of today that stay (M's body read, at least one PID, no PID-3 key with a blank
authority), in this order. The first that holds M gives the words after "held by the patient check: ".

**N1. A newer message on the same order or a linked order holds M, whatever its patient and whatever its status.** The
read is today's: the item's headers newer than M's origin, less this run's own clones (the ledger's `NewHeaderId`), up
to CAP (2,000); it now takes every status, and leaves out only the headers of the set itself (the candidates being placed,
or this run's other rows), whose order the set's header-id order already keeps. A related order group in any of them holds
M. The patient is not compared, so a final result filed under the surviving identifier after a merge still holds the
preliminary one under the retired identifier.

- Example: M is ORU placer ORD1, OBR-25 P (preliminary); a newer ORU placer ORD1, OBR-25 F, reached the receiver. Words:
  "a newer message on the same order (placer ORD1) reached the receiver at 03:13 (control id C123)". Sending M would put
  the preliminary result after the final one. Unit: `PatientCheck:TestSameOrderNewerHolds`.
- A correction or amendment (OBR-25 C, OBX-11 C) or a cancellation (ORC-1 CA, OC, CR, DC, OD or DR) names the order it
  changes, so it is the same order. Units: `PatientCheck:TestAmendmentHolds`, `PatientCheck:TestCancelSameOrderHolds`
  (a table over the six cancellation codes).
- Matched by filler alone: M has placer ORD1 and filler FIL1, the newer one only FIL1. Unit: `PatientCheck:TestSameOrderByFiller`.
- A reflex order: a newer ORM with placer ORD2 and OBR-29 parent ORD1. Words: "a newer message on an order linked to this
  one (parent placer ORD1) reached the receiver at 03:13 (control id C124)". Two reflex orders of one parent hold each
  other too. Units: `PatientCheck:TestReflexChildHolds`, `PatientCheck:TestReflexSiblingHolds`.
- Another patient's message on the same order number: `PatientCheck:TestSameOrderOtherPatientHolds`.
- A newer message on the same order that has not reached the receiver (Error, Suspended or any status but Queued,
  Delivered and Completed) and is not in the set: "a newer message on the same order (placer ORD1), header 812, reads
  Suspended: a person decides the order's messages together". Unit: `PatientCheck:TestSameOrderSetAsideHolds`. One that
  is in the set does not hold M (it goes after M): `PatientCheck:TestSameOrderInTheSetGoes`.
- A newer message whose body can't be read: "the newer message in header 812 could not be read, so it can't be shown to
  be about another order". Unit: `PatientCheck:TestUnreadableNewerHolds` (on both paths).

**N2. A newer message for the same patient that can't be shown to be about other orders holds M.** Today's patient read
(the item's newer headers Queued, Delivered or Completed sharing a PID-3 key), with one exception: a message about other
orders (above) with no replacement code does not hold M. So:

- **Results on other orders go.** M is ORU placer N51 for NHS 9997001001; the newer ORU placer C5 for the same NHS number
  reached the receiver (Completed). They are proven distinct (both have placers, which differ, and no parent links them),
  so M is not held. This is O5.c. Units: `PatientCheck:TestOtherOrderGoes`, and `ResendSet:TestOtherOrdersOffered`, which
  plays the O5 shape in process (five never-opened results, a newer Completed result of another order, an open case on a
  third) and reads all five in `offered`.
- A newer ADT for the patient (an A08 to the same item, say) names no order: held, "a newer message for identifier
  9997001001 (NHS) reached the receiver at 03:13 (control id C125), and it names no order, so it can't be shown to be
  about another order". Unit: `PatientCheck:TestNewerAdtForThePatientHolds`.
- No comparable number: M has only a placer, the newer one only a filler. Held, "... it carries only a filler number
  where this one has only a placer number". Unit: `PatientCheck:TestNoComparableNumberHolds`.
- A replacement (ORC-1 RP, RU, RO, RQ, RR, XO, XR or XX) for the same patient holds M whatever its numbers, since a
  replacement can carry new order numbers and the link to what it replaces may exist only at the receiver: "a newer
  message for identifier 9997001001 (NHS) replaces an order (ORC-1 RP), and a replacement may carry new order numbers".
  Unit: `PatientCheck:TestReplacementHolds`. A cancellation of another order does not hold M, since a cancellation names
  its order: `PatientCheck:TestCancelOtherOrderGoes`.

**N3. A merge or an identity change of the patient holds M.** Two reads, both from M's creation on:

- In the source namespace, every HL7 body newer than M's (`EnsLib_HL7.Message` rows with an ID above M's body id), to
  any item, whose `DocType` names an ADT structure or is blank: MSH-9 is read, and an event of A18, A24, A30, A34, A35,
  A36, A37, A39, A40, A41, A42, A44, A45, A46, A47, A48, A49, A50 or A51 that names any of M's patient keys in PID-3 or
  MRG-1 holds M: "an ADT^A40 at 03:13 (header 900) merges or changes identifier 9997001001 (NHS), after this message was
  created: the receiver may hold the patient under another identifier". The read is made once per set and once per run,
  then only for what arrived since; more than IDENTITYCAP (5,000) such bodies holds every candidate, "more than 5,000 ADT
  messages passed through this namespace since this one, more than Shutter reads for merges", and a failed read holds
  them too.
- Shutter's own cases, any state, any receiver, opened after M was created, whose event is a merge or an identity change
  and whose `patientId` or `priorPatientId` with its authority is one of M's keys: "Shutter's case C-000031 is a merge
  naming identifier 9997001001 (NHS), opened after this message was created".

Units: `PatientCheck:TestMergeHolds` (a table of A40, A34 and A47, with the identifier in MRG-1 and in PID-3),
`PatientCheck:TestMergeOfAnotherPatientGoes`, `PatientCheck:TestMergeCaseHolds`, `PatientCheck:TestIdentityCapHolds`.
A merge that never passes through the watched namespace (the PAS sends it straight to the laboratory system, say) is not
seen: a stated limit, on the card (below).

**N4. Shutter's unresolved case at this receiver holds M unless its message is about other orders.** Today's case read
(every state but `resolved`, the candidate's own cases and the set's left out), with the same exception as N2: the
case's stored copy (its `sourceHeaderId` in Shutter's namespace) is read, and a case whose message is proven about other
orders, with no replacement code, does not hold M. A copy that can't be read holds M. Words: "Shutter still has an
unresolved case on the same order at this receiver: C-000014 (escalated)", or "... for this patient at this receiver,
whose message can't be shown to be about another order: C-000014 (escalated)". In O5 the R and T messages have cases on
other orders, so they no longer hold the five. Units: `PatientCheck:TestOpenCaseOtherOrderGoes`,
`PatientCheck:TestOpenCaseSameOrderHolds`, `PatientCheck:TestOpenCaseUnreadableHolds`.

**N5. What the check can't read holds M**, as today and more: M's body, a PID, a blank authority, the headers past CAP or
a failed read (all today); a newer body (N1), a case's copy (N4), the merge read (N3) (new).

**Fallback.** M with no order number takes today's patient-wide rule with the N1 unreadable-body tightening:
`PatientCheck:TestNoOrderNumberFallsBack` (a newer result of another order for the patient holds it, as today). An ADT
message keeps today's rule exactly: `PatientCheck:TestAdtKeepsThePatientRule` (a newer ORU of another order for the
patient holds an ADT A08). Today's tests (`TestTwoPatients`, `TestRepetitions`, `TestBlankAuthority`,
`TestNewerCompleted`, `TestOwnCloneAndHandResend`, `TestCap`, `TestCasesOpen`, `TestOneOfTwoHeld`, `TestLedgerEmpty`)
stay and pass; where one builds an ORU with an order number, it now names the rule it means.

### Where the code goes

- `Shutter.Util.PatientCheck`: `Orders`, `Related`, `Distinct`, `OtherOrders`, `Identities(ns, fromBodyId)`, and
  `Check(ns, item, originHeaderId, receiver, exclude, members)`, `members` a `$LIST` of the set's header ids. `Check`'s
  answer gains `scope` (`order` or `patient`) and, per patient, `rule` (`same_order`, `linked_order`, `same_patient`,
  `replacement`, `identity`, `open_case`, `unreadable` or `cap`). The class comment's merge paragraph is replaced by
  the limit below.
- `Shutter.Util.ResendSet.Lists` passes the candidates' header ids as `members`; `SETPOLICYVERSION` moves to the build
  day's next value (2026-11-09.3 if built that day), which voids an approval not yet sent, as the digest binds it.
- `Shutter.Operation.EngineResend.Recheck` passes the run's origin header ids as `members`, beside `RunCases`.

### The card

The set's words gain, when it offers a result older than a result of another order for the same patient that already
reached the receiver: "N of these are older than results of other orders for the same patients that already reached the
receiver; each files under its own order." The limit line replaces "Merges are not read": "The patient check reads merges
and identity changes only where they pass through this namespace; one made elsewhere is not seen."
`OutageApi:TestWordsTable` gains both.

### Cost

One pass over the item's newer headers per candidate, as today (CAP 2,000, the body of each read once and its patients
and orders kept for the pass), plus the merge read once per set. The time of a set of 50 candidates with 2,000 newer
headers and 5,000 ADT bodies is measured on build 154 before release and written in INSTALL beside the patient check.

## 2. O6.d: a failed resend is shown, and nothing more goes

### What happens today

Engine Resend reads the new header itself until it settles (`Settle`), and never waits for an alert. A new header ending
Error or Suspended without the receiver's declared duplicate answer writes the ledger row `failed`, marks every row not
sent `stopped`, and moves the outage to `needs_person` ("the resend of header N (new header M) ended Suspended: the rest
were not sent"). So nothing further goes already. What's missing: no route shows the ledger, the message's earlier case
says nothing of it, and only the one-day "seen" mark of the alert intake keeps the engine's alert on the new header from
opening a second case for the same message.

### The design

- **The outage shows each resend.** `GET /outages/:id` (and each item of `GET /outages`) gains `resends`: every ledger
  row of the outage in position order, `{ "runId", "position", "headerId", "controlId", "newHeaderId", "state",
  "closure", "words", "by", "at", "caseId" }`. `headerId` is the header sent (the origin, or Shutter's never-opened clone in
  its place), `by` the approver (or for a hand closure the person who recorded it), `at` the row's end, or its start while
  sending. `closure` is `sent` (completed), `already_delivered` (closed_as_present), `handled_by_hand`, `failed`,
  `unknown`, or null while approved, sending or stopped.
- **The earlier case shows it.** `GET /cases/:id` gains `resends`: the ledger rows on the case's origin header, in the same
  shape. A failed one writes a case event of kind `resend`: "Shutter's resend of this message failed at 03:20: new header
  9001 ended Suspended (the receiver answered AE: Refused by the application). Nothing more was sent; the outage waits for
  a person." The case's state is left as it is (an order or result case stands escalated with the team).
- **No new case.** `Shutter.Process.Intake` (Shutter's namespace) gains a first step: a forward whose header in its source
  namespace is Shutter's own clone (`ResendRecord.IsOwnClone`), or is an origin with a ledger row that has started, opens
  no case. It is answered as taken, so the alert intake marks the session seen; the words go on the ledger row's case as
  the event above ("the engine alerted on Shutter's resend: ..."), or, with no case, on the outage as an alert line. The
  site's own alert consumer still gets the engine's alert, as every alert is passed on first (11): Shutter never silences
  a site's alerting.
- **Nothing further, now or later.** The rows not sent stay `stopped`; the outage waits in `needs_person` until a person
  reads it again. Read again, the failed message is placed `refused` ("Shutter resent it at 03:20 and that copy reads
  Suspended"), so it is never offered again; the others are offered again only for a new approval.

The rig's `adapter.resend_failed` reads `resends`: true when a row for the control id reads `state` `failed`. The rig's
own check is that the receiver heard only the first message.

Units: `EngineResend:TestFailedResendShown` (a stub engine answer: the row failed, the rest stopped, the outage
`needs_person`, the case's event, `resends` on both routes), `Intake:TestOwnCloneOpensNoCase` (a forward naming a ledger
clone, and one naming an origin with a started row: no case, an event on the earlier case),
`ResendSet:TestFailedCloneNotOfferedAgain`, `OutageApi:TestResendsField`.

## 3. O8.c: a receiver's refusal of what it holds closes the item as already delivered

### Why it doesn't today

`EngineResend.Declared` matches the receiver's MSA-3 to the profile's `duplicates.phrase` exactly. The rig declares
"ALREADY HELD" and its receiver answers "MSA|AE|...|ALREADY HELD, entered by hand", as a real one does ("already in" with
its own words after them). So the row ends `failed` and the run stops, though O8.b passes, since the message went once.
And no route shows a ledger row's closure.

### The design

- **The match, by field.** The phrase matches when MSA-1 is AE or AR, and MSA-3 (trimmed) equals the phrase, or starts
  with it and the next character is neither a letter nor a digit. Case is kept; nothing is matched across the reply. The
  code (ERR-3) match is unchanged. `refers_to` is printed on the card, as before.
- **The item closes.** The ledger row is `closed_as_present` (as today), with its words; its `closure` reads
  `already_delivered` in `resends`; the run goes on. The message's own cases (its origin's, by `CaseRows`) are resolved
  with disposition `already_delivered`: "Already delivered: the receiver reported it already holds this message (MSA-3:
  ALREADY HELD, entered by hand); the engine never delivered it by this route, and a hand entry would explain it. Shutter
  has not compared the stored result or amendment." Only that message's cases: never every case linked by receiver and
  time. The outage's close words keep "N the receiver reported it already held".
- **The set's fifth list.** `lists` gains `closed`: messages of the window closed without a send of their own, each a Row
  with `closure` and `closedBy` and `closedAt`. `ResendSet.Place` reads the ledger first: an origin with a
  `closed_as_present` or `handled_by_hand` row goes to `closed`, before its copies are read (the refused clone would
  otherwise read "Shutter resent it ... and that copy reads Suspended"). The digest stays over `offered` alone.
- **The page** reads "Already delivered" in the case's outcome line (`outcome.ts`) and on the outage's resend list.

The rig's `adapter.closure` reads `resends`: `already_delivered` or `handled_by_hand` as written, `sent`, `failed` or
`unknown` as "other", and None when the control id has no row or its row's `closure` is null.

Units: `EngineResend:TestDeclared` gains the table (equal, the phrase then a comma, the phrase then a space, the phrase
then a letter, the phrase inside other words, another case, MSA-1 AA), `EngineResend:TestAlreadyHeldClosesTheCase`,
`ResendSet:TestClosedList`.

## 4. O8.d and O8.e: "already handled by hand" at a receiver whose duplicates are unknown

### The offer

At a receiver whose profile's `duplicates.behaviour` is `unknown` or `files_twice`, or that declares none, every row of
`lists.offered` carries `acts: ["handled_by_hand"]`, and the outage's `acts` gains `handled_by_hand` while it is
`offered`. At `refuses` the rows carry `acts: []`: the receiver's answer closes a held one by itself. The row's `acts` are
composed on read from the profile, as `words` are. Nothing is sent by the offer: only an approval sends.

The card's `do` line at such a receiver reads: "At this receiver a duplicate is unknown (or: filed twice): before
approving, check the receiver for each message. For one already entered by hand, choose Already handled by hand; Shutter
then sends nothing for it."

**Ask first.** At those receivers `POST /outages/:id/approvals` also needs `"receiverChecked": true` (the approver says
the receiver was checked for these messages), else 409 `receiver_check_needed`: "At this receiver a duplicate is unknown:
check the receiver for these messages first, and say so with the approval." Only where a receiver refuses duplicates is a
resend safe with no check.

### The choice

`POST /outages/:id/acts` with `{ "act": "handled_by_hand", "headerId": "<a row of lists.offered>", "note": "...",
"version": n }` (`Shutter_Approve`, the CSRF header, an `Idempotency-Key`; no new route):

- 400 `bad_request` for a header that is not in `lists.offered`, a row whose `acts` lack it, or a note empty or over 1,000
  characters; 409 `wrong_state` unless the outage is `offered`; 409 `version_changed` on a stale version.
- Under the row's lock and version: a ledger row `handled_by_hand` (`RunId` "H" and the outage id, `OriginHeaderId`,
  `ControlId`, `RecordedBy` the signed-in user, `EndedAt` now, `Words` "Handled by hand, recorded by <user> at 03:20:
  <note>. Shutter sent nothing for it."); the Row moves from `offered` to `closed` with `closure` `handled_by_hand`,
  `closedBy` and `closedAt`; the digest is recomputed over what stays offered; the version moves on; an event
  `handled_by_hand` names the person and the control id; the row is marked to read again, so the next poll computes the
  set in the watched namespace, where the ledger row places the message in `closed`.
- The message's own cases are closed by hand (`Case.CloseByHand`, disposition `handled_by_hand`) with the same words.
- With nothing left offered and nothing else needing a person, the poll closes the outage ("every message of the window
  was sent or closed"); otherwise it stays `offered` with the others, or goes to `needs_person`.
- A send can't follow: `Place` refuses an origin with a `handled_by_hand` row, so an approval given before the choice
  stops at Engine Resend's recheck of that message ("header N no longer qualifies: handled by hand, recorded by ...").

The rig: `adapter.offers_handled_by_hand` is true when the open outage's `lists.offered` row for the control id lists
`handled_by_hand` in its `acts`; `adapter.choose_handled_by_hand` posts the act with that row's `headerId`, the outage's
`version` and a note, through one `rig.person_decides`; `adapter.closure` then reads `handled_by_hand` from `resends`.

The page (`web/src/features/incidents/outage/OutageSection.tsx`): the approval (note, and the receiver check where it is
needed), each offered row's "Already handled by hand" with a note, the `closed` list, and the `resends` list with each
closure, every control shown only when the row lists its act and the person holds `Shutter_Approve`.

Units: `OutageApi:TestHandledByHandAct` (offered only at unknown, files_twice and none; the refusals; the ledger row with
who and when; the Row moved and the digest; the case closed by hand), `OutageApi:TestApproveNeedsReceiverCheck`,
`ResendSet:TestHandledByHandPlacesClosed`, `EngineResend:TestHandledByHandNotSent` (an approval, then the choice: the
recheck stops on that message, nothing is sent), and component tests in `OutageSection.test.tsx`.

## 5. The escalation email: saved is not delivered

### Today

With no mail server set, `Escalation Mail` writes an `.eml` file and calls `MarkSent("file", path)`: the state reads
`sent`, `sentAt` is set, the case note says "Escalation 1 delivered (file): <path>", and the page shows a Sent badge. Nobody
was emailed. `docs/SAFETY.md` already says so as a limit.

### The design

- **A state of its own.** `Shutter.Store.Escalation.State` gains `saved` (a value list change, no storage slot), and a
  property `SavedAt` (`savedAt`), its storage slot appended. `MarkSaved(path)` sets `saved`, `Transport` `file`, `Result`
  the path and `SavedAt`; `sentAt` stays empty. The case note: "Escalation 1 saved as an email file, not delivered: <path>.
  No mail server is set, so nobody was emailed." A row stored before 1.4.0 with `transport` `file` and `state` `sent`
  reads `saved` everywhere, with `savedAt` from its `sentAt`, through the one serialiser (`ToObject`) and the SQL readers
  below, so nothing is migrated.
- **Through the mail server, sent.** `MarkSent("smtp", ...)` is unchanged in state; its note reads "Escalation 1 sent
  through the mail server: <the server's words>", in place of "delivered (smtp)", since the server's acceptance is not a
  delivery to a person (its words already say so).
- **The person's act is a queue.** The send's note reads "Escalation 1 queued by <user> for <to>; digest of the text
  queued <bodyDigest>" (it said "sent by" before the transport was known).
- **A saved email can go again.** `Queue` takes a `saved` escalation as it takes a draft or a failed one, so once a mail
  server is set the same text can be sent; it stays `saved` until then.
- **The close by hand** still follows an escalation that was sent or saved: the close is a person's statement that the
  team corrected the systems, and a saved file may have been passed on by hand. Its words name the state, "(saved)".

### Every place that shows "Sent" for an email, and what it shows in 1.4.0

| Place | Shows today | 1.4.0, saved as a file | 1.4.0, through the mail server |
|---|---|---|---|
| `Store/Escalation.cls` `MarkSent`, called from `Operation/EscalationMail.cls` for a file | state `sent`, `sentAt` | state `saved`, `savedAt` (`MarkSaved`) | state `sent`, `sentAt` |
| `Store/Escalation.cls` `MarkSent`, the case note | "Escalation 1 delivered (file): <path>" | "Escalation 1 saved as an email file, not delivered: <path>. No mail server is set, so nobody was emailed." | "Escalation 1 sent through the mail server: ..." |
| `Store/Escalation.cls` `Queue`, the case note | "Escalation 1 sent by <user> to <to>; digest of the text sent <d>" | "Escalation 1 queued by <user> for <to>; digest of the text queued <d>" | the same |
| `Store/Case.cls` `CloseByHand`, the close words | "after escalation 1 to <team> (sent)" | "(saved)" | "(sent)" |
| `Util/ShadowReport.cls`, `notification_deliveries` | counts `state = 'sent'`, a file included | not counted | counted |
| `GET /cases/{id}/escalations` and the case bundle (`ToObject`) | `state` `sent`, `sentAt` | `state` `saved`, `savedAt` | `sent`, `sentAt` |
| `EscalationPanel.tsx`, the badge (`humanize(state)`, `IconSend`, tone info) | "Sent" | "Saved, not delivered" (a file icon, tone attention) | "Sent" |
| `EscalationPanel.tsx`, the line under it | "Sent by <user>" and the time | "Queued by <user>; saved as an email file" and `savedAt` | "Sent by <user>" and `sentAt` |
| `EscalationPanel.tsx`, the transport line | "Written as an email file: no mail server is configured" / "Sent by email" | "Saved as an email file, not delivered: no mail server is set, so nobody was emailed. Pass the file on, or set the mail server and send it again." | "Sent through the mail server, which accepted it; that does not show anyone has read it" |
| `EscalationPanel.tsx`, the digest line | "Digest of the text sent" (queued and sent) | "Digest of the text saved" | "Digest of the text sent" (queued: "Digest of the text queued") |
| `EscalationPanel.tsx`, the purged line | "digest of the text sent" | "digest of the text saved" | "digest of the text sent" |
| `EscalationPanel.tsx`, the section's words for a closed case | "The emails sent before the team corrected ..." | "The emails sent or saved before the team corrected ..." | the same |
| `EscalationPanel.tsx`, the toast after Send | live "Escalation 1 sent"; trial "Marked as sent in the trial" | live "Escalation 1 queued", with "Its line shows whether the mail server took it or it was saved as an email file."; trial "Saved in the trial, not delivered" | the same |
| `EscalationPanel.tsx`, the dialog's first line | live "This emails the <team>."; trial "Sending marks it as sent in the trial." | live "This emails the <team> through the site's mail server. With no mail server set, it is saved as an email file and nobody is emailed."; trial "Sending saves it as an email file in the trial, as on an instance with no mail server." | the same |
| `outcome.ts` `handoff`, the case's Escalation line | "Sent to <team>" / "Queued to <team>" | "Saved as an email file for <team>, not delivered" | "Sent to <team>" |
| `caseAction.ts` `closableByHand` and the close button's comment | "once an escalation is sent" (`state === 'sent'`) | sent or saved | the same |
| `web/src/mocks/handlers.ts` (the trial and component tests) | `state: 'sent'`, `transport: 'file'`, "delivered (file)" | `state: 'saved'`, `savedAt`, the notes above | |
| `web/src/api/types.ts` `Escalation` | `state` without `saved` | `saved` and `savedAt` | |
| `docs/api/openapi.json`, the escalation schema | `sent` | `saved` and `savedAt` added | |
| `docs/CONTRACTS.md` 10, the states and the note | `sent` "when the operation delivered it" | as above | |
| `docs/SAFETY.md`, "Nobody looks at it" | "its state reads `sent` and the case note says delivered (file)" | "its state reads `saved` and the case note says not delivered" | |
| `docs/readme/running.md`, Escalation by email | "otherwise writes an `.eml` file" | adds "and shows it as saved, not delivered" | |

Not changed, and why: the outage email with no mail server already says "the email was written to <path>" in the event
log only, and nothing shows it as sent (its throttle global `^Shutter.OutageMail("sent", receiver)` is never shown); the
reminder digest never writes a file (it fails); `sentBy` keeps its name in the API, as the person who pressed Send.

Tests: `Escalation:TestSavedIsNotSent` (`MarkSaved`: state, `savedAt`, empty `sentAt`, the note), `Escalation:TestOldFileRowReadsSaved`,
`Escalation:TestQueueNoteSaysQueued`, `Mail` tests for both transports, `ShadowReport:TestSavedIsNoDelivery`;
`EscalationPanel.test.tsx` (a saved row shows "Saved, not delivered" and no "Sent" anywhere in its item; an SMTP row
shows Sent), `outcome.test.ts` (`handoff`), `caseAction.test.ts` (closable after saved), `handlers.test.ts`;
`tests/e2e/roles_check.py` waits for `saved` with `savedAt` on CI (no mail server) and reads " queued by " and "digest of
the text queued" on the timeline.

## Storage

Every class here keeps its committed Storage block, with new slots appended at the end (`scripts/iris-pull-storage.py`):

| Class | New property | Slot |
|---|---|---|
| `Shutter.Store.Escalation` | `SavedAt` | 22 |
| `Shutter.Store.ResendRecord` | `ControlId`, `RecordedBy` | 22, 23 |
| `Shutter.Store.Outage` | `ListClosed` (a stream, as the other lists) | 50 |

`Escalation.State` gains `saved` and `Case.Disposition` gains `already_delivered` (no value list), with no slot. The
demo's `PurgeStore` also empties `Shutter.Store.ResendRecord`: the purge resets the case counters, so a row's `CaseId` left behind would name a new case of the same id, which the patient check would then leave out.

## Build order and proof

1. Part 5 (independent; web and server).
2. Part 1, then the unit suites on build 154 and on 2026.2 (the core module, as CI).
3. Parts 3 and 4 (the ledger read in `Place`, `lists.closed`, `resends`, the act), then part 2 (the intake step, the
   case's `resends` and event).
4. The adapter's four functions filled in by someone who did not build the features, from this design's field names
   only; the rig's own guard checks the adapter keeps its rule.
5. The whole rig on build 154 with no `--only` (O12.c played as before), `attempt_history_check.py`, both unit suites,
   vitest in `web/`, and `check-text.py`, `check-openapi.py`, `check-versions.py` and `check-records.py`. Every row ok is
   the bar.

## Limits that stay

- A merge or identity change that never passes through the watched namespace is not seen (on the card).
- An order linked only in the receiver's own records (a replacement with new numbers is held for the same patient, but a
  link through another patient's record is not read).
- The receiver's "already held" is its word: Shutter has not compared the stored result or amendment, and the case says so.
- What the attempt-history proof leaves unproven (INSTALL): a failed log insert, rows deleted by hand, a restore or
  failover, an operation class that is not the stock one.
