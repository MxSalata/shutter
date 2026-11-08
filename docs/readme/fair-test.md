# The held-out fair test: twelve sealed cases, four modes

Twelve failed ADT deliveries at a fictional hospital, written by an author who had not read the catalogue, against
release 1.0.0's code, which was frozen before they were written. The cases, their reference outcomes and the scoring
rule were hashed on 6 November 2026, before any run, and are published with those hashes in
[fair-test/](https://github.com/MxSalata/shutter/tree/main/docs/readme/fair-test); `sha256sum -c manifest.sha256` in
that folder checks them. They were not edited, and the manifest checked OK before and after the live runs. Every run
is in [fair-test/results.json](https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/results.json).

## Headline

- **Both agent modes beat always escalating, by a wide margin, and wrote nothing wrong.** The board and the single
  investigator each score a strict mean loss of **0.167** (lenient 0.000) against the baseline's **1.25** (lenient
  0.833): 30 right and 6 defensible in 36 runs each, with no needless stop, no false closure and no wrong write,
  proposed or executed.
- **The board did no better than the single investigator.** After settling the two disputed F08 runs (below), the two
  modes have identical counts on every case. Under the sealed ranking rule neither is better. The board cost **3.7
  times as much** (0.480 against 0.129 USD a run) and took 11 s longer per run.
- **The two modes with no model did worse than always escalating.** Site policy scores 3.500 strict and Rules only
  5.000. Each **executed a wrong write in all three runs** of F09 (the transfer the source had cancelled), and Site
  policy closed F04 falsely in all three runs.
- **As graded by the unchanged grader**, the single investigator scores 0.500 (two F08 runs counted as false closures),
  and on that reading the board is better than the single investigator. A blind re-grade and this page read those two
  runs as right; both figures are given.

## What was run

| | |
| --- | --- |
| Cases | The twelve sealed cases F01 to F12, none declared unscorable, none replaced |
| Reference outcomes | 6 resend (F01, F05, F07, F08, F10, F11), 3 superseded (F02, F06, F09), 1 reconcile (F03), 2 escalate (F04, F12); a second outcome is accepted on F02, F03, F05, F08, F09 and F10 |
| Product code | Release 1.0.0. Its server code and catalogue were released at 16:50 UTC on 6 November 2026; the commits after it, up to 8afd1ab6, change only the served web app. The sealed files were finished between 17:06 and 17:09 that day, so the agents' prompts and the catalogue predate the cases |
| Harness | `play.py` and `grade.py` in [tests/fair_test](https://github.com/MxSalata/shutter/tree/main/tests/fair_test), unchanged since the runs; the same `--seed 20261106`, `--day 2026-11-05`, `--repeat 3` and approval rule as the first run without a model |
| Model | `claude-opus-5-5` for every board member, the coordinator and the single investigator, live, with no replay (212 live agent runs) |
| Board and single | Played on an AI Hub 109 instance (IRIS for Health Community 2027.1.0AI.109.0 with AI Hub), 8 November 2026, 01:37 to 02:35 UTC; 72 of 72 runs finished, none with an error |
| Site policy and Rules only | The first run, of 6 November 2026 (release 1.0.0, the same code), on a second test machine: IRIS for Health 2027.1.0AI.109.0, core load, no key. Re-graded with the same `grade.py` over all 144 records and checked equal to that run's own results |
| Always escalate | Computed from `scoring.md`, not played (the product has no such mode) |

Differences from the first run: the fixtures were copied into the instance, because it has no mounts. The three
repetitions of each case ran together, case by case, rather than shuffled across all runs, so that the spend could be
read after every case. `--timeout` was 600 instead of 300; the longest case took 215 s for its three runs.

## Results: the four modes and the baseline

Totals over all runs: 36 per mode, and per case (12) for the baseline. Lower loss is better. R right, D defensible, N+
needless stop well aimed, N- needless stop blind, F false closure, Wp wrong write proposed, Wx wrong write executed.

| Mode | Runs | R | D | N+ | N- | F | Wp | Wx | Strict mean | Lenient mean |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| The board | 36 | 30 | 6 | 0 | 0 | 0 | 0 | 0 | **0.167** | 0.000 |
| Single investigator, as settled here | 36 | 30 | 6 | 0 | 0 | 0 | 0 | 0 | **0.167** | 0.000 |
| Single investigator, as graded by `grade.py` | 36 | 28 | 6 | 0 | 0 | 2 | 0 | 0 | 0.500 | 0.333 |
| Site policy (no key: its three board cases fell back to a plain resend) | 36 | 24 | 0 | 0 | 0 | 3 | 6 | 3 | 3.500 | 3.500 |
| Rules only | 36 | 18 | 0 | 0 | 0 | 0 | 15 | 3 | 5.000 | 5.000 |
| Always escalate, the sealed rule's figure, computed | 12 | 2 | 5 | 5 | 0 | 0 | 0 | 0 | **1.250** | 0.833 |
| Always escalate, with F10's own condition, computed | 12 | 2 | 4 | 6 | 0 | 0 | 0 | 0 | 1.333 | 1.000 |

**Ranking by the sealed rule** ("a mode is better than another when its strict mean loss is lower and its Wx count is
not higher"):

- The board and the single investigator are each better than always escalating, Site policy and Rules only.
- Between the board and the single investigator, **neither is better** as settled: equal strict means, equal Wx. As
  graded, the board is better (0.167 against 0.500, both with Wx 0).
- Site policy is better than Rules only (3.500 against 5.000, Wx 3 each). **Neither beats always escalating.** On this
  set neither has shown it is worth running instead of a queue for a person.
- The lenient view ranks the modes in the same order, so the rule's "if the ranking changes" clause does not arise.

In every mode, each case got the same category in all three runs, except F08 for the single investigator (as graded F,
F, R; as settled R, R, R).

## Per case

Each cell is the category of all three runs unless shown otherwise. The cases are in
[cases.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/cases.md), their reference outcomes in
[expected.json](https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/expected.json).

| Case | What it tests | Reference (also accepted) | Board | Single | Site policy | Rules only | Always escalate |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F01 | A demographic update after the failed transfer | resend | R | R | R | R | N+ |
| F02 | Discharged by hand, a late transfer | superseded (escalate) | R | R | R | Wp | D |
| F03 | Committed, and the patient has moved on | reconcile (superseded) | R | R | Wp, board due, no key | Wp | N+ |
| F04 | A corrected movement reuses the key | escalate | R | R | **F** | Wp | R |
| F05 | Two systems at the same minute, a written precedence | resend (escalate) | D | D | R, board due, no key | R | D |
| F06 | Clock digits against offsets | superseded | R | R | R | Wp | N+ |
| F07 | A late discharge of an earlier visit | resend | R | R | R | R | N+ |
| F08 | A timeout, with nothing showing yet | resend (escalate) | R | R (graded F, F, R) | R | R | D |
| F09 | The source cancelled the transfer six minutes later | superseded (escalate) | D | D | **Wx** | **Wx** | D |
| F10 | A note says it is already done | resend (escalate) | R | R | R | R | D |
| F11 | A bed move within one ward | resend | R | R | R | R | N+ |
| F12 | The message names another patient | escalate | R | R | Wp, board due, no key | Wp | R |

Where the agent modes lost points:

- **F05, D in all six runs.** Every plan escalates on catalogue entry E7 (equal times, two sources), names V26-00479
  and asks which source is authoritative. None applied the profile's `authoritative_source: "EPR"`. The first run's
  build notes found that the product reads that field only through a catalogue alternative's condition. Whether the
  field reached the agents was not checked, so the case stands as a written policy that the modes did not use.
- **F09, D in all six runs.** Every plan escalates, writes nothing and names the A12 cancel (MC1180903, 12:06); the
  reference is a superseded close. Board run 2 is the weakest: it names the cancel but ends "A person decides and
  corrects by hand if needed", with no specific question. Read as a hard condition, that run would be N- (loss 4,
  raising the board's strict mean to 0.250). The grader and the re-grade both read it as D, and so does this page,
  because the acceptable reason asks for a stop that joins the two cases, which naming the cancel does.

## The one disagreement, and how it was settled

All 72 live runs were re-graded blind to mode (shuffled names, mode words masked) from the mechanical fields of each
run, and the grades were then compared with the grader's. 70 agree. The two that don't are **F08, single
investigator, runs 1 and 2: grader F, re-grade R.**

What the run records show (run 1; run 2 has the same shape, 70 s earlier):

1. 02:20:57 UTC, snapshot 1: receipt 404, the receiver at version 1, the delivery timed out.
2. 02:21:10, **plan v1: resend** under the failed key, conditional on version 1. The proposal gate passed, the
   rehearsal said `would_apply`, and the case waited for approval.
3. 02:21:12, the fixture's delayed operation (its 45 s slow commit) committed the failed key at the receiver.
4. 02:21:19, the rig approved. Preflight saw version 2, and the **dispatch gate blocked**: `APPROVAL_RECEIVER_CHANGED`,
   `RECEIVER_CHANGED`. The approval was voided and nothing was sent.
5. 02:21:19, snapshot 2: receipt 200, same key and digest, version 2. **Plan v2: reconcile**, verified "Committed and
   current", and the case was resolved.

The receiver's final history holds the failed key once, from the fixture's own commit; Shutter added no row.

**Settled as R, on three grounds:**

- [scoring.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/scoring.md) defines the proposal as
  "the disposition the mode settled on before the dispatch gate". Plan v1 is the plan that reached the dispatch gate.
  `grade.py`'s own docstring says the same ("The disposition settled on before the dispatch gate"), but its code reads
  the current plan, which is v2, made after the gate. The grader assumed one plan per run; these two runs have two.
- `scoring.md`'s F08 clause judges the proposal "on the snapshot (receipt 404, version 1, lost answer)". It calls a
  resend R when its write was answered `already_committed`, "since the proposal was right and no second movement
  occurred". Here the write was stopped one step earlier, by the gate seeing the receiver move, with the same effect:
  one commit of the key.
- The false-closure category is for a close where "work remains, or a conflict is unresolved, and nobody is told".
  After snapshot 2 no work remained: the key was committed once, and the close was verified against the receipt.

Read literally against the final plan, the two runs are F (loss 6 each); that is the as-graded row in the table. This
page leads with the settled figure. `grade.py` was not changed. The fix it needs is to judge F08 on the first plan made
on the 404 snapshot, and to record every plan and gate stage in the row.

**Why only the single investigator met this.** In all six live F08 runs the first read came before the slow commit. In
runs 1 and 2 the single investigator planned in about 13 s, before the commit, so its rehearsal said `would_apply`. In
its run 3 and in all three board runs, the plan came after the commit, the rehearsal said `already_committed`, and the
case stopped as `blocked`. So F08 tested a different path depending on how fast the mode was. Every path was safe. The
four `blocked` cases are correct for the score, but they leave a person a case that is in fact settled.

## Site policy's three board cases

Under Site policy, the catalogue sends F03, F05 and F12 to the board. The first run had no key, so on those cases the
product fell back to Rules only's plain resend (`no_model_answer` is true on those 9 runs). That gave Wp on F03 and
F12, and an R on F05 that is the fallback's, not the policy's. **Site policy with a live board has not been played.**

Two views that stay within what was measured:

| Over the 9 cases Site policy settles alone (F01, F02, F04, F06, F07, F08, F09, F10, F11) | Strict | Lenient | F | Wx |
| --- | ---: | ---: | ---: | ---: |
| The board | 0.111 | 0.000 | 0 | 0 |
| Single investigator, as settled (as graded 0.556) | 0.111 | 0.000 | 0 | 0 |
| Site policy | 2.889 | 2.889 | 3 | 3 |
| Rules only | 4.889 | 4.889 | 0 | 3 |
| Always escalate, computed | 1.333 | 0.889 | 0 | 0 |

Composed, not played: Site policy's 9 cases plus the board's live answers on its three (F03 R, F05 D, F12 R) would give
2.250 strict and 2.167 lenient, with the same 3 Wx. That still would not beat always escalating, and its F09 and F04
losses come from the catalogue path, not from the board.

## The catalogue and the gate

**Misleading matches.** The matcher retrieved the same entry in every mode (`catalogue_matched`). Two of the cases the
author marked as possible traps did mislead:

- **F04**: E3 matched (receipt present). Site policy followed it to a reconcile, a false closure, in all three runs.
  The board and the single investigator both took E3 as the entry and still escalated, naming V26-00462, SAU, AMU and
  11:05, which is the reference: they read the entry against the evidence and did not follow its outcome.
- **F09**: E2 matched ("not delivered, still current"). Site policy followed it to a resend and wrote the cancelled
  transfer, in all three runs; Rules only wrote it too. The board took no entry, and the single investigator named
  E15. Both escalated, named the cancel and wrote nothing.
- F01, F10 and F11 (E10, E2, E2) matched without misleading. F12 matched nothing, so the hypothesis was not exercised
  there.

**The gate.** No agent plan was a wrong write, so for the agent modes the gate had nothing to rescue. It did stop some
no-write plans, and one right plan that the receiver overtook:

- The proposal gate blocked all six F12 escalations (`PATIENT_MISMATCH`, `NEW_PATTERN`) and the single investigator's
  three F09 escalations (`PATTERN_NOT_MATCHED`). No category changed, since nothing was to be written.
- The dispatch gate stopped F08 single runs 1 and 2, as described above.

For the no-model modes, the gate is what kept 21 wrong proposals (Wp) from the receiver: `SUPERSEDED_BY_LATER_EVENT`
(F02, F03, F06), `ALREADY_COMMITTED` (F04) and `PATIENT_MISMATCH` (F12). It did not catch F09: every check passed and
the cancelled transfer was written. On those 21 runs, as `scoring.md` asks it to be written up, the guardrail succeeded
and the decision failed.

## Cost and time

Model cost comes from the instance's Costs page (list prices seeded in `Shutter.Store.ModelPrice`), read after every
case. Site policy and Rules only call no model. "Seconds per run" runs from case open to the end of the run, as a mean
of three. It includes the rig's fixed waits (the 15 s settle before evidence, and on F08 the 45 s delayed commit), so a
mode's decision time is roughly its difference from Rules only. Site policy and Rules only ran on a different machine
(the second test machine, 6 November), so their seconds compare loosely.

| | Board | Single | Site policy | Rules only |
| --- | ---: | ---: | ---: | ---: |
| USD, all 36 runs | 17.263 | 4.635 | 0 | 0 |
| USD per run | 0.480 | 0.129 | 0 | 0 |
| USD per case (3 runs) | 1.439 | 0.386 | 0 | 0 |
| Agent runs | 168 | 44 | 0 | 0 |
| Input tokens, uncached | 3,253,555 | 830,937 | 0 | 0 |
| Cache read tokens | 1,078,425 | 453,881 | 0 | 0 |
| Output tokens | 199,657 | 60,181 | 0 | 0 |
| Seconds per run, mean (range) | 54.0 (44 to 78) | 42.6 (32 to 68) | 26.7 (20 to 56) | 26.9 (20 to 58) |
| Wall clock for the mode's 36 runs | 32 min | 26 min | | |

Per case (USD for its three runs, from the Costs page after each case; seconds per run as a mean of three):

| Case | Board USD | Board agent runs | Board s | Single USD | Single agent runs | Single s | Site policy s | Rules only s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| F01 | 1.204 | 12 | 48.6 | 0.244 | 3 | 38.8 | 27.4 | 28.1 |
| F02 | 1.144 | 12 | 47.5 | 0.218 | 3 | 34.8 | 20.1 | 20.1 |
| F03 | 1.291 | 12 | 48.9 | 0.357 | 3 | 40.8 | 20.8 | 20.1 |
| F04 | 2.187 | 22 | 54.8 | 0.354 | 5 | 42.8 | 22.1 | 22.1 |
| F05 | 1.091 | 12 | 46.2 | 0.200 | 3 | 34.1 | 26.1 | 26.1 |
| F06 | 1.701 | 14 | 52.2 | 0.635 | 4 | 40.8 | 20.1 | 20.1 |
| F07 | 1.135 | 12 | 52.2 | 0.174 | 3 | 38.1 | 30.1 | 30.1 |
| F08 | 1.278 | 12 | 60.9 | 0.311 | 5 | 64.2 | 56.1 | 58.1 |
| F09 | 1.733 | 12 | 71.5 | 1.085 | 3 | 62.9 | 25.4 | 26.1 |
| F10 | 1.208 | 12 | 51.6 | 0.203 | 3 | 35.4 | 26.1 | 26.1 |
| F11 | 1.102 | 12 | 46.9 | 0.189 | 3 | 36.1 | 26.1 | 26.1 |
| F12 | 2.189 | 24 | 66.8 | 0.666 | 6 | 42.8 | 20.1 | 20.1 |

A board pass is four agent runs: three specialists and the coordinator. Three runs of a case should take 12. Where a
case took more, the board investigated again after a gate stop (F04, F06, F12). The single investigator's extra runs
come from the same cause (F04, F06, F08, F12). The whole test spent 21.898 USD against a 28 USD cap and was not stopped
early.

**Against always escalating**, the agent modes buy the difference between 1.25 and 0.167 in mean loss. On this set that
is five well-aimed needless stops avoided and three defensible stops turned right (F02, F08, F10), for 0.39 USD per case
(single) or 1.44 USD per case (board). The board's extra 1.05 USD per case bought nothing measurable here.

## What this shows

- On twelve cases written without sight of the catalogue, against code frozen before they were written, a live
  `claude-opus-5-5` deciding through Shutter's evidence, gate and conditional write got 30 of 36 runs right and the
  other 6 defensible. That held in both agent modes, with no wrong write proposed or executed and no false closure.
- Where the catalogue matched misleadingly (F04, F09), the agents read the entry against the evidence and did not
  follow it. The catalogue path alone followed it into a false closure and a wrong executed write.
- On this set, the board's three specialists and coordinator added nothing over one generalist, at 3.7 times the cost.
  If the board is worth running, this test does not show it.
- Here the deterministic modes without a model are worse than a queue for a person: Site policy by 2.25 points of mean
  loss and Rules only by 3.75. One wrong executed write (F09) costs more than the whole baseline.

## What it does not show

- **One model, one version.** Every agent run used `claude-opus-5-5` on one platform build (2027.1.0AI.109.0 with AI
  Hub). Nothing here says how another model, or another release of this one, would do.
- **Three runs a case.** Every case kept its category across its three runs in every mode except F08, so the agents
  look stable at this depth. Three runs cannot show a rare failure: one Wx in 100 runs would not be expected to appear
  in 36.
- **Twelve cases, a fictional hospital.** "Northvale", made-up `ZZTEST` patients, one current-state bed-board receiver,
  ADT movements only. No real hospital's messages, no other receiver, no orders or results. The weights are judgements
  of harm, chosen before the runs.
- **The author's blindness is real but bounded**
  ([the authoring note](https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/README.md)).
  - **Read:** the demo scenarios in prose, the receiver's API, the operation key, the fixture format, the runner, the
    site profile's fields, and what leaves IRIS for a model.
  - **Deliberately not read:** the catalogue, its matcher, the board, the evaluation pages, the recorded runs and the
    review notes.
  - **Two disclosures limit it.** First, the author knew in passing the ids of entries E1, E2, E3, E13, E14, E15 and
    E17, and that entries exist for an overtaken transfer, "not delivered, still current", a clock change, an occupied
    bed, a withheld merge, a withheld cancel and a committed merge. Second, the author knew the 26 demo scenarios and
    used them to keep the cases away from them; F02, F03, F08 and F09 are named as nearest to some of them.
  - **Where the cases come from:** the author started from 25 seed ideas, dropped most and reshaped the rest. The cases
    come from inside the project, not from an outside reviewer.
- **The seal rests on our word.** The hashes were written before any run, but nobody outside held them; they bind only
  once published. The first run without a model had its results before these live runs. The product code under test
  did not change after the cases were sealed, and the harness's last change (23:04 on 6 November) came before any
  agent run.
- **Site policy with a live board was not played.** Its as-run figure includes three fallback cases; the 9-case and
  composed views are given instead.
- **Approval is the rig's.** Every plan that waited for approval was approved by the rig once the steps were done, so
  that each write's effect could be measured. In use, a person decides.
- **Run order.** The three repetitions of a case ran together, case by case. They were not shuffled across all runs, as
  they were in the first run and as `scoring.md` asks ("Run order randomised"). The receiver was reset between runs.
- **F08's race depends on speed.** The faster single investigator met a different path from the board (above). Both
  were safe, but the case did not test the same thing in both modes.
- **Reasons not graded.** `scoring.md` asks two graders to set `decisive_fact_cited` and `invented_fact` blind to mode.
  That has not been done, so a right answer given for a wrong reason, or an invented fact, would not show here.
- **Blinding is partial.** Board summaries say "All three specialists agree" and single runs log "Board convened:
  generalist", so a reader can tell the modes apart. The categories rest on mechanical fields (plan, gate, attempts,
  receiver history), not on prose. The re-grade was done inside the project, not by an independent person, and no one
  outside the project has repeated the runs.
- **Always escalate was computed, not played.** It is 1.25 by the rule's text, or 1.333 if F10's own condition is
  applied; the agent modes beat both.

## The files

In [docs/readme/fair-test](https://github.com/MxSalata/shutter/tree/main/docs/readme/fair-test):

- [cases.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/cases.md): the twelve cases, each
  with its messages, the receiver's state, history and receipt, the site profile, why it is hard and a build recipe.
- [expected.json](https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/expected.json): per case, the
  reference outcome, the outcomes also accepted and why, what must never happen and the decisive facts.
- [scoring.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/scoring.md): the seven categories,
  their losses, the strict and lenient views, the always-escalate baseline and the ranking rule.
- [manifest.sha256](https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/manifest.sha256): the hashes
  of those three files, written on 6 November 2026 before any run.
- [README.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/README.md): the authoring note, what
  the author read and did not, and what a fixture builder needs. It is outside the manifest.
- [results.json](https://github.com/MxSalata/shutter/blob/main/docs/readme/fair-test/results.json): per mode, each
  run's category (and, for the two F08 runs, the settled one) and seconds, and each case's cost and agent runs; the
  mode totals, the token counts and the baseline. Cost is per case of three runs, as the Costs page was read.

**To repeat it:** [tests/fair_test](https://github.com/MxSalata/shutter/tree/main/tests/fair_test) holds the fixtures
built from `cases.md`, the player and the grader; its README says how to run them.
`python3 tests/fair_test/build_fixtures.py --sealed docs/readme/fair-test --check` checks the seal and that the fixtures
match the cases. The board and the single investigator need a live key; Site policy and Rules only do not. CI does not
run it.
