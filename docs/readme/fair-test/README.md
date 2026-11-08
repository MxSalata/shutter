# Fair test for Shutter, 6 November 2026

A held-out set of twelve cases for Shutter's three ways of deciding a failed ADT delivery (Site policy, the single
investigator, the board), with the reference outcomes and the scoring rule fixed before any mode runs. The author
worked blind to the catalogue and the recorded results, so this is an exam set before the answers were seen.

## The files

| File | What |
|---|---|
| `cases.md` | The twelve cases: situation, HL7 messages, the receiver's state, history and receipt at investigation, the site profile, why each is hard, and a build recipe in the runner's step vocabulary. |
| `expected.json` | Per case: the reference outcome, outcomes also accepted and why, what must never happen, the decisive facts, the receiver after a right answer, the confidence, and whether honest experts differ. |
| `scoring.md` | The rule: seven categories kept apart (right, defensible, needless stop well aimed, needless stop blind, false closure, wrong write proposed, wrong write executed), their losses, strict and lenient views, the always-escalate baseline (1.25 strict on this set), and how the modes are compared. |
| `manifest.sha256` | SHA-256 of the three files above, written once they were finished. They are not to change. |
| `README.md` | This file, written last and outside the manifest. |
| `results.json` | Added with the results, after the runs and outside the manifest: per mode, each run's category and seconds, and each case's cost. |

The sealed hashes:

```
01b89c903cb3d24d7b3d4e9e3a41518ac0ae94dd32580cefa18ea7552e34752d  cases.md
5bc5edfc4b7d5f0cf20cf2cd9743b9f60003a4916f0eeabf68d8c6d93e644a31  expected.json
1a029ad9f047ecd46cb27bbd912e9999cfdd1094ea70880ba18c1fb8c933d858  scoring.md
```

## The set in one paragraph

Twelve made-up situations at a fictional hospital ("Northvale", `NVH`) with one current-state bed-board receiver, on 18
November 2026: six where the right answer is a conditional resend (a demographic update after the failure; an
equal-time two-source conflict under a written precedence; a late discharge of the patient's other spell; a timed-out
delivery with nothing yet visible; a note claiming the team already did it; a bed move within one ward), three
superseded (a hand discharge on the ward before a late transfer; an offset that reverses the clock-digit order; a cancel
six minutes after the failure), one reconcile (a slow receiver committed it and the patient has moved on) and two
escalate (a reused key with a corrected ward; a patient identity the receiver refuses). Half want a write, so a tool
that only stops cannot do well. Five cases accept a second answer because honest experts differ, and the scoring shows
the ranking with and without that allowance.

## What the author read, and did not

Read, as permitted:

- A list of 25 seed ideas: most were dropped, several were reshaped, none was taken as given.
- `docs/readme/scenarios.md` (the demo scenarios in prose).
- `docs/CONTRACTS.md`, sections 1 to 4 (the receiver's API, the operation key and HL7 mapping, the fixture format, the
  scenario runner and its steps), 5.1 (attempts and verification), 6.4 (the site profile's fields) and 9 (what leaves
  IRIS for a model). Section 6's other parts (the condition vocabulary, the entries' front matter, matching, the gate's
  catalogue checks, the board and the catalogue) were deliberately not read.
- `fixtures/`: the two S2 messages, one message each from S8, S13, S21, S23a and S9, the head of `generate.py`, and from
  `scenarios.json` the set of step kinds and expected keys plus the full definitions of S10, S20, S22, S23a and S24, for
  the shape of a `manual`, `capabilities`, two-receiver and keyed-fault scenario.
- `tests/e2e/scenario_check.py`: the docstring and the function outline, for what the check compares.

Not read, as required: `knowledge/catalogue/`, `src/Shutter/Catalogue/`, `docs/readme/comparison.md`,
`docs/readme/evaluation.md`, `docs/readme/evaluation.json`, `docs/readme/s8-what-the-agents-saw.md`,
`fixtures/records/`, and every review note and recorded result.

Two disclosures, so the reader can judge the blindness:

1. `scenarios.md` names four catalogue entry ids in passing (E1, E2, E13, E17) with a phrase each, and gives the
   board-versus-rules counts for the demo scenarios. `CONTRACTS.md` 6.4 names E1's alternative (`correct_history`), E3,
   E14 and E15 in passing. I know from these that entries exist for "overtaken by a later transfer", "not delivered,
   still current", a clock-change time, a bed occupied, a withheld merge, a withheld cancel and a committed merge. I did
   not read any entry's conditions, text or policy, and nothing in the cases is written against an entry.
2. `scenarios.md` and `scenarios.json` describe the demo scenarios S1 to S25. I used that to keep the cases away from
   them (different identifiers, wards, day, sources and situations), and `cases.md` says where a case is nearest to one
   (F03 to the lost acknowledgement and the overtaken transfer; F08 to the newer-message hold; F02 and F09 to the
   hand-entered move). A fixture builder who knows all 26 scenarios should check that resemblance once more.

None of the files not to be read was opened, no mode was run while the cases were written, and no file was written
outside this folder.

## What a fixture builder needs that the rig may lack

Found while writing the recipes against `CONTRACTS.md` sections 1 to 4; each is stated in the case it affects.

1. **Hold the first investigation until the scenario's steps are done.** F09 needs the A12 indexed before the A02's case
   is investigated; the live-story variant of F03 needs the later transfer applied first. The runner has `wait` and
   `wait_for_state` but, as far as sections 1 to 4 say, no step that delays the case's own investigation. Either a step
   for it, a quiet period before the first investigation, or a reinvestigate after the steps whose round is the one
   judged. Without it F09 is unscorable for every mode, declared before the runs (`scoring.md`). Every other recipe is
   ordered so that the decisive receiver state exists before the failing delivery, and has no race.
2. **A site profile per case.** F05 sets `authoritative_source: "EPR"`; F10 sets `model_content.free_text: true`. The
   runner has no profile step; the builder needs a `PUT /site-profile` before the run and a restore after, with the
   profile version in the run's record. The author did not read what the product does with `authoritative_source`; the
   builder should check before relying on F05, and if the field is unread by the product, F05 still stands as a case
   where the written policy is present in the profile and the modes are judged on whether they use it.
3. **A case on a 4xx refusal and on a timeout.** F02 and F12 fail with 422 (`invalid_transition`, `patient_mismatch`),
   F04 with 409 (`key_reused_with_different_payload`), F08 with no answer at all (the connector's 15 s timeout against
   `delay_response` 30 s). Confirm the feed opens a case for each of these, not only for 5xx.
4. **The evidence read time, logged.** F08 is judged on a snapshot taken after the timeout and before the delayed commit
   (about 15 s wide). The rig must record when the evidence was read relative to the send, and the case is unscorable
   for a run whose read fell after the commit.
5. **Explicit offsets in EVN and MSH-7.** F06 carries `20261118015000+0100`. Section 3 says an offset is shifted to UTC;
   confirm the parser does it for both fields and that the operation key reads `00:50:00Z`.
6. **The patient's other encounter in the evidence.** F07 needs the collector to show V26-00388's discharge beside
   V26-00512's state, as the index does for a patient's other visits; confirm it is in what the modes see.
7. **`manual` steps with `source_system`** `EPR` and `FLOW` and a chosen `event_time` (F03, F05, F06): section 4.3 says
   these exist. F03 relies on a manual `EPR` operation having the same key and digest as the HL7 message; the digests in
   `cases.md` were computed from section 1.6 and should be checked against the receiver's own.
8. **An export for blind grading.** Per run: the proposal before the gate, the gate's decision, dispatch attempts and
   verification, the receiver's final encounter read, the catalogue entry retrieved, the stated reasons, tokens, time
   and cost, with the mode's name removable. Run order randomised, the receiver reset between runs, three runs per
   model-backed mode.
9. **The shipped release policy, not approval.** Tier 2 single chains release automatically under the seed profile, so
   Site policy writes without a person; the test needs that, on an isolated receiver, so that a wrong write can be
   measured as executed rather than always stopped at an approval task.
10. **Two baselines run beside the modes:** Rules only, and an always-escalate run that names the encounter and the
    failure text, so the 1.25 figure in `scoring.md` is measured and not only computed.

## A note on the seeds

The 25 seed ideas lean to escalate (8 of 25) and rest on receiver semantics the demo receiver does not have (receipt
retention windows, receipts from another epoch alongside a live encounter, a receipt whose encounter differs from its
key, retired-ward registers, alias tables). Those were dropped as testing nothing the product does today. What survived,
reshaped and re-identified: the equal-time conflict under a written precedence (F05, the seeds' 02), the offset reversal
(F06, from 04), the committed-then-moved reconcile (F03, from 06), the same-ward movement (F11, from 07, with a bed to
make it real), the cancellation (F09, from 17), the quiet-close injection (F10, turned from the seeds' 21 and 22 towards
a false closure, which is the harder steer), and the lost answer (F08, from 20, made honest by idempotency). F01, F02,
F04, F07 and F12 are the author's own. The seeds' single-number scoring was not adopted; `scoring.md` keeps the
categories apart and publishes the baseline instead.
