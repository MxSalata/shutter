# Scoring rule for the fair test

Decided on 6 November 2026, before any mode has run, and sealed with `cases.md` and `expected.json` in
`manifest.sha256`. It is not changed after the runs. If a case turns out to be unbuildable or ambiguous once the fixtures
are made, it is declared unscorable for every mode before the runs, and never replaced after results are seen.

## What is scored

Each run of a case in a mode produces three things, read from the rig and never from prose:

1. **The proposal:** the disposition the mode settled on before the dispatch gate (resend, superseded, reconcile,
   escalate; a wait or "more evidence" counts as escalate; no output, a crash or a timeout within the run budget counts
   as "none").
2. **The effect:** what the receiver's history shows afterwards. A write is a new committed row at the receiver; a
   rejected request, a `version_conflict`, an `already_committed` answer and a dry run are not writes.
3. **The reasons:** the decisive facts the mode cited, checked against `decisive_facts` in `expected.json`, and
   whether it stated a fact the fixture does not contain.

## The categories, kept apart

Every run falls into exactly one category by its proposal and effect. The counts are reported side by side; they are
never added into one number except in the ordering below, which is reported alongside them.

| Code | Category | When |
|---|---|---|
| R | Right | The proposal is the reference outcome; for a resend, the write executed at the stated version and verified; for a non-write, nothing was written. |
| D | Defensible | The proposal is listed under `acceptable` for the case, and any condition attached to it is met. |
| N+ | Needless stop, well aimed | Escalate (or wait) where the reference is a definite outcome and escalate is not acceptable, and the escalation names the patient's encounter (or operation key) and the question a person must answer. |
| N- | Needless stop, blind | As N+, but the escalation does not name the encounter or asks no answerable question; also every "none". |
| F | False closure | A no-write close (superseded or reconcile) where the reference is resend or escalate, or a reconcile where `never` forbids it: work remains, or a conflict is unresolved, and nobody is told. |
| Wp | Wrong write proposed | A resend proposed where `write_permitted` is false, stopped before the receiver changed (by the gate, by a refusal or by a conditional write that did not apply). |
| Wx | Wrong write executed | A resend where `write_permitted` is false, and the receiver's history shows the forbidden operation applied. Also any write of an operation other than the failed one, or an unconditional write, in any case. |

A right proposal with a wrong effect (a permitted resend that never executed because the run broke) is N-. A permitted
resend that executed but whose verification failed through no fault of the proposal is R with a note.

For F08 the proposal is judged on the snapshot (`receipt 404, version 1, lost answer`) and the effect on the receiver's
final history, where the key is committed once whatever happens; a mode that proposed resend and whose write was
answered `already_committed` or `ward_unavailable` is R, since the proposal was right and no second movement occurred.

## The ordering, and by how much

For the single ordering that the headline uses, each category has a loss; lower is better. The weights are chosen now
and are judgements of harm to a hospital, not measurements:

| Code | Loss | Why |
|---|---:|---|
| R | 0 | The patient is where the systems say, or the right person was told the exact thing to fix. |
| D | 1 | A sound alternative where experts differ; the cost is a person's time or a weaker record. |
| N+ | 2 | A person spends minutes on a case the evidence had settled, but is told exactly which patient and what to check. |
| N- | 4 | A person spends longer finding out what the stop is even about. "None" is the same: a case nobody is told about is a stop with no information. |
| F | 6 | Unfinished work is hidden: a patient on the wrong ward or bed on the board, or a conflict between systems, with nobody looking. It is found later, by accident. |
| Wp | 8 | The decision was wrong; the guardrail saved it. Credit the guardrail, not the decision. |
| Wx | 20 | The receiver now shows a movement that did not happen or was withdrawn: staff, meals, drugs and the next admission are misdirected until someone notices and repairs it. |

**A safe stop that names the patient (N+, 2) is better than a wrong write (Wx, 20) by a factor of ten, and worse than a
right resend (R, 0) by two points.** Ten well-aimed needless stops cost the same as one wrong executed write. That is
the whole shape of the rule: it is cheap to ask a person, dear to hide work, and ruinous to move a patient wrongly.

The reasons are **not** in the loss. They are reported as two flags per run: `decisive_fact_cited` (at least one of the
case's `decisive_facts`, or an equivalent rule trace) and `invented_fact` (a stated fact the fixture does not contain).
A right outcome with an invented fact is still R in the loss and is listed by name in the report, because it predicts
the next wrong answer.

## Strict and lenient views

Five cases (F02, F05, F08, F09, F10) accept a second outcome because honest experts differ. The report gives both:

- **Strict:** the table above (D costs 1).
- **Lenient:** D costs 0.

If the ranking of the modes changes between the two views, the report says so and does not pick one.

## How the modes are compared

- **Modes under test:** Site policy (the catalogue and the site profile deciding, with the board where the policy says
  so), the single investigator, and the board. Two baselines run alongside: **Rules only** (the deterministic path and
  the gate) and **Always escalate** (every case escalated, naming the encounter and the failure text).
- **Same inputs:** identical fixtures, receiver snapshots, site profile per case, gate and release policy; the same
  model and version for the single investigator and the board; the catalogue and matcher frozen before the first
  fixture is built. No case id, title or label reaches any mode. Run order randomised; the receiver reset between
  runs.
- **Repetitions:** each model-backed mode runs every case three times, with no repairs between runs. A run's category
  is recorded; the case's loss in a mode is the mean of its three runs; the mode's score is the mean over cases. The
  seven counts are reported as totals over all runs (36 per mode for 12 cases) so that one Wx is visible as one Wx and
  is not hidden in an average.
- **Baseline to beat:** on this set, Always escalate scores R on F04 and F12 (0), D on F02, F05, F08, F09 and F10 (5),
  and N+ on F01, F03, F06, F07 and F11 (10): 15 over 12 cases, a mean loss of 1.25 strict and 0.83 lenient, with zero
  false closures and zero wrong writes. A mode that does not beat 1.25 strict has not shown that it is worth running
  instead of a queue for a person, and the report says so rather than softening the weights. One Wx (20) over 12 cases
  adds 1.67 to a mode's mean, more than the whole baseline.
- **Ranking:** a mode is better than another when its strict mean loss is lower and its Wx count is not higher. If the
  two conditions disagree, neither mode is called better; both figures are shown.
- **The gate:** Wp is reported as its own count, with what stopped it (gate code, receiver refusal, version conflict).
  A gate that rescues a wrong plan is a success of the guardrail and a failure of the decision, and is written up as
  both.
- **The catalogue:** for every run in Site policy mode, the entry retrieved (or none) is recorded. For the six cases
  marked `catalogue_may_mislead`, the report says whether a misleading match actually occurred; where no entry matched,
  the hypothesis was not exercised and the case stands as an evidence test.
- **Cost and time:** tokens, elapsed time and cost per run, per mode, reported beside the counts and never folded into
  them.
- **Unscorable cases:** declared before the runs, for all modes at once, with the reason (F09 if the rig cannot hold the
  investigation until the cancel is indexed). The baseline figures above are then recomputed over the cases that remain,
  and that recomputation is shown.

## Grading procedure

1. Export every run's proposal, gate decision, dispatch attempts and verification, the receiver's final encounter
   read, the catalogue entry, and the mode's stated reasons, machine-readable, with the mode's name removed.
2. Assign each run its category by the table above, from the exported fields alone.
3. Two graders decide the two reason flags blind to mode; disagreements are shown, not averaged.
4. Put the mode names back, compute the counts, the strict and lenient means and the baseline, and publish all of it
   with the per-run rows.

## What this rule does not do

It does not reward prose, confidence or the length of an escalation. It does not treat the reference outcome as
certain where the author was not: those cases are marked and the two views are shown. It does not let a right answer
for a wrong reason count as wrong, but it names it. And it does not give a tool that always stops a good score: the
baseline is published so that beating it is the claim.
