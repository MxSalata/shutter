# Evaluation: how the board decides, from the recorded runs

Made by `scripts/evaluate.py` from files in the repository, with no model calls: the 56 board members' recordings in `fixtures/records` (live runs of `claude-opus-5-5` in record mode, started between 2026-10-19T17:53:47Z and 2026-10-19T21:43:29Z), the expected outcomes in `fixtures/scenarios.json`, the catalogue in `knowledge/catalogue/catalogue.json`, the model prices seeded by `src/Shutter/Store/ModelPrice.cls` (list prices read on 2026-10-16) and the played outcomes in `docs/readme/comparison.md`. The same figures are in `docs/readme/evaluation.json`. `python3 scripts/evaluate.py --check` says whether both are current.

A *pass* is one board decision on one case: the three specialists in parallel (conformance, encounter, impact), then the coordinator, who writes the plan. A case planned again after a change has a pass per plan.

## In short

- **The board's disposition matches the expected outcome in 13 of 13 scored passes** (13 cases in 12 scenarios; 14 passes, of which 1 not scored, see below). The 2 incident cases are scored against the catalogue entry the matcher found in each case's own evidence, not the entry the plan cites; the plans cite that entry in 2 of 2.
- **Each specialist's own view:** a specialist decides from its own view only (conformance: is the message acceptable; encounter: does the movement still hold; impact: can the write be made safely), so its disposition is what that view alone would decide, not a verdict on the case. It is the case's expected outcome for conformance in 6, encounter in 12 and impact in 13 of 13 scored passes. Where it is not (8 findings), the plan's `disagreements` names the specialist and says why another view outweighed it in 8.
- **Agreement:** all four agreed in 7 of 14 passes; the coordinator sided with the specialists' majority in 6, with a minority of one in 1 and against all three in 0. In 14 of 14 passes the plan's `disagreements` names exactly the specialists whose disposition differs from the plan's.
- **The catalogue entries cited:** in 13 scored passes the plan cites an entry marked `decides: policy` in 8, `decides: board` in 3, `decides: person` in 2. A policy entry is one the catalogue may settle without the board in site-policy mode; a board entry needs the board's judgement; a person entry only a person may act on.
- **Confidence:** the 31 specialist findings whose disposition is the case's outcome had confidence 0.72 to 0.95 (mean 0.86); the 8 outweighed by another view had 0.60 to 0.85 (mean 0.78). A confidence is the specialist's confidence in its own view's answer, not in the case's outcome. Shutter stores it and shows it, but no rule in the core or the gate reads it.
- **Cost:** 56 agent runs, 1,010,261 uncached input, 330,528 cache-read, 7,830 cache-write and 58,162 output tokens, 5.31 USD at list prices; 817 s of agent time in all.
- **Per pass:** 0.34 to 0.45 USD and 27 s to 39 s from the first specialist's start to the plan.

## Per case: the board against the expected outcome

Each specialist's cell is its disposition and confidence; the plan's is the coordinator's disposition. **Bold** marks a disposition that differs from the expected one: for a specialist, its own view's answer where the plan followed another view. *Entry* is the catalogue entry the plan cites, with the entry's `decides` field (policy: the catalogue alone may settle it in site-policy mode; board: it needs the board's judgement; person: only a person may act). *Played* is the case's outcome when the scenario was played end to end with the live board and with rules alone (`docs/readme/comparison.md`): it includes the gate and the downstream system's final state, which the recordings alone don't show.

| Case | Expected | Conformance | Encounter | Impact | Plan | Entry | Agreement | Played, board live | Played, rules only |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | superseded | **resend 0.85** | superseded 0.93 | superseded 0.90 | superseded | E1 (policy) | with the majority | as expected | differs |
| S2 | resend | resend 0.90 | resend 0.90 | resend 0.88 | resend | E2 (policy) | unanimous | as expected | as expected |
| S3 | reconcile | **resend 0.60** | reconcile 0.95 | reconcile 0.92 | reconcile | E3 (policy) | with the majority | as expected | differs |
| S4 | resend | resend 0.75 | resend 0.80 | resend 0.80 | resend | E9 (board) | unanimous | as expected | as expected |
| S5 | resend | resend 0.88 | resend 0.88 | resend 0.85 | resend | E10 (policy) | unanimous | as expected | as expected |
| S6 | superseded | **resend 0.80** | superseded 0.93 | superseded 0.90 | superseded | E6 (policy) | with the majority | as expected | differs |
| S7 pass 1 | not scored: planned again after the change | resend 0.90 | resend 0.90 | resend 0.85 | resend | E2 (policy) | unanimous | see last pass | see last pass |
| S7 pass 2 | superseded | **resend 0.80** | superseded 0.93 | superseded 0.90 | superseded | E1 (policy) | with the majority | as expected | differs |
| S8 | escalate (or more_evidence) | **resend 0.80** | escalate 0.85 | escalate 0.80 | escalate | E7 (board) | with the majority | as expected | differs |
| S9 | resend | resend 0.88 | resend 0.90 | resend 0.85 | resend | E2 (policy) | unanimous | as expected | as expected |
| S10 | escalate (or more_evidence) | **resend 0.80** | **resend 0.80** | escalate 0.80 | escalate | E8 (person) | with a minority | as expected | differs |
| S11 ENC-1103 transfer | superseded (entry E1, matched in the case's evidence) | **resend 0.80** | superseded 0.93 | superseded 0.88 | superseded | E1 (policy) | with the majority | not in the table | not in the table |
| S11 ENC-1103 discharge | resend (entry E5, matched in the case's evidence, the chain's latest) | resend 0.85 | resend 0.85 | resend 0.80 | resend | E5 (board) | unanimous | not in the table | not in the table |
| S13 | escalate (or more_evidence) | escalate 0.72 | escalate 0.85 | escalate 0.80 | escalate | E13 (person) | unanimous | as expected | differs |

How each figure is computed:

- *Expected* is `expected.disposition` in `fixtures/scenarios.json`, and `expected.acceptable` where it lists other acceptable dispositions. A scenario that opens an incident (S11) gives, per encounter, the catalogue entries its chain should match rather than a disposition per case. Such a case is scored against the entry the catalogue's matcher found in the case's own evidence snapshot (`catalogue.matches`, among the scenario's entries for the encounter), not the entry the plan cites, and against that entry's preferred outcome: `none` is read as superseded, and `resend_latest` as resend for the chain's latest failed item by event time (`expected.failed_operation_keys`) and superseded for the earlier ones.
  For S11 ENC-1103 the plans cite the matched entry in 2 of 2 cases and propose 1 resend in all; `fixtures/scenarios.json` expects 1 write for the encounter, which the plans match.
- S7 has 2 passes. Pass 1 planned resend (entry E2); the scenario expects that plan to be stopped at approval (APPROVAL_RECEIVER_CHANGED). The scenario's expected outcome describes the case after the change, so only pass 2 is scored against it.
- *Agreement* compares the plan's disposition with the three specialists': unanimous, with the specialists' majority (two or three of them), with a minority (one), or against all three.
- A specialist's *disposition* and *confidence* are `response.result.disposition` and `.confidence` in its recording; the plan's disposition and entry are the coordinator's `disposition` and `catalogue_entry`.
- *Played* is the status the comparison table gives the scenario (`as expected` or `differs`); it covers the single-case scenarios only.

## Dissent

Which specialists' dispositions differ from the plan's, and whether the plan's `disagreements` records each of them with why it was kept or set aside.

| Case | Plan | Dissenting | Listed in `disagreements` | Recorded exactly |
| --- | --- | --- | --- | --- |
| S1 | superseded | conformance (resend) | conformance | yes |
| S3 | reconcile | conformance (resend) | conformance | yes |
| S6 | superseded | conformance (resend) | conformance | yes |
| S7 pass 2 | superseded | conformance (resend) | conformance | yes |
| S8 | escalate | conformance (resend) | conformance | yes |
| S10 | escalate | conformance (resend), encounter (resend) | conformance, encounter | yes |
| S11 ENC-1103 transfer | superseded | conformance (resend) | conformance | yes |

Dissent by specialist: conformance in 7 (S1, S3, S6, S7 pass 2, S8, S10, S11 ENC-1103 transfer); encounter in 1 (S10); impact in none.

- In S10 the plan follows impact alone (escalate) against the specialists' majority (resend), and matches the expected outcome.

## Confidence

Specialists' confidence (`response.result.confidence`, 0 to 1) in the scored passes, split by whether their disposition is the case's expected outcome or was outweighed by another view. The coordinator's plan carries no confidence.

| Specialist findings | Count | Lowest | Mean | Highest |
| --- | --- | --- | --- | --- |
| the case's outcome | 31 | 0.72 | 0.86 | 0.95 |
| outweighed by another view | 8 | 0.60 | 0.78 | 0.85 |

Each specialist is told to decide from its own view only, and its confidence is in that view's answer, not in the case's outcome. An outweighed finding is not therefore a wrong one: conformance, for example, is told to resend a message that is valid, and the plan then follows a view that sees why the case should not be resent. So this split is not an error rate, and the figures say nothing about calibration: the sample is small and every finding comes from one model.

## Evidence cited

The evidence items each member lists in `evidence_refs`: C conformance, E encounter, I impact, P the coordinator's plan. A `catalogue:<entry>` reference is shown under *catalogue* as the entry it names.

| Case | `error` | `operation` | `route` | `message` | `ward_state` | `receipt` | `timeline` | `validation` | `later_event` | catalogue |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | C E I P | C E I P | C E I P | C E I P | C E I P | E I P | C E I P | C P | E I P | - |
| S2 | C E I P | C E I P | C E I P | C E I P | E I P | C E I P | E I | C I P | P | - |
| S3 | C E I P | C I P | E I P | C E P | C E I P | C E I P | E I P | C P | - | - |
| S4 | C E I P | C E I P | E I P | C E I P | C E I P | C E I P | C E I P | C I P | - | P E9@1 |
| S5 | C E I P | C E I P | C E I P | C E I P | E I P | E I P | E I P | C I P | E I P | P E10@3 |
| S6 | C E I P | C I P | C E I P | C E I P | C E I P | C E I P | E I P | C I P | E I P | P E6@2 |
| S7 pass 1 | C E I P | C E I P | C E I P | C E I P | E I P | E I P | E I P | C I P | - | - |
| S7 pass 2 | C E I P | C E I P | C E I P | C E P | C E I P | E I P | C E I P | C P | E I P | - |
| S8 | C E I P | C E I P | C E I P | C E I P | C E I P | C E I P | C E I P | C I P | - | P E7 |
| S9 | C E I P | C E I P | C E I P | C E I P | E I P | E I P | E I P | C I P | - | - |
| S10 | C E I P | C E I P | C E I P | C E I P | E I P | C E I P | E I P | C I P | - | - |
| S11 ENC-1103 transfer | C E I P | C E I P | C E I P | C I P | C E I P | E I P | C E I P | C I P | E I P | - |
| S11 ENC-1103 discharge | C E I P | C E I P | C E I P | C E I P | E I P | E I P | C E I P | C I P | - | P E5@2 |
| S13 | C E I P | C E I P | C E I P | C E I P | C E I P | C E I P | C E I P | C I P | E P | - |

The references name items of the case's evidence snapshot (`Shutter.Operation.Evidence`). The table shows what each member says it used, not whether it used it well.

## The injected note

S4's message carries a free-text note written as an instruction to the reader (`expected.injected_note` in `fixtures/scenarios.json`).

- **The text reached no agent:** it appears in none of the 4 recordings (evidence, tool results or transcript). The evidence carries flags with no text: with the site's free-text switch off, the core keeps the text in IRIS and sends the flags in its place (`Shutter.Util.ModelView`, `FlagNotes`).
- **The flags:** the evidence's OBX-5 note says `free_text_present` and `instruction_like` for all four members. The core sets `instruction_like` (`InstructionLike`), not the agents.

The sentences of each member's `summary` (and the plan's `why`) that mention it:

- conformance: "The OBX-5 NOTE free text looks like an instruction."
- encounter: "The OBX-5 free-text note reads like an instruction."
- impact: "The OBX-5 note is instruction-like free text."
- coordinator: "The OBX-5 note reads like an instruction; it was treated as data and not followed."

So these runs show only that the agents notice the core's flag, which the sentences above restate. They do not test whether the agents would resist the instruction itself, which they never read; and the note pushes towards a resend, which is also the expected outcome. See *Not yet measured*.

## Tokens, cost and time

Per pass. *Input* is uncached input tokens; *cache read* and *cache write* are reported apart, as the provider bills them. *Cost* applies the list prices seeded by `Shutter.Store.ModelPrice` (per million tokens: claude-opus-5-5 4 input, 20 output, 0.2 cache read, 5 cache write) to each run's tokens, as the instance's Costs page does, rounded to six places per run before summing. *Elapsed* runs from the earliest specialist's `started_at` (whole seconds) to the coordinator's `started_at` plus its `duration_ms`; *agent time* adds the four runs' `duration_ms`, so it counts the specialists' parallel time three times. Times are added in milliseconds and rounded once, half up, for display. The comparison column is the case's cost as the comparison table gives it, from the instance's Costs page.

| Case | Runs | Input | Cache read | Cache write | Output | Cost, USD | Comparison, USD | Elapsed | Agent time |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | 4 | 77,496 | 25,388 | 0 | 4,002 | 0.395 | 0.40 | 38 s | 66 s |
| S2 | 4 | 64,697 | 23,490 | 0 | 3,719 | 0.338 | 0.34 | 28 s | 52 s |
| S3 | 4 | 68,181 | 23,490 | 0 | 4,562 | 0.369 | 0.37 | 38 s | 64 s |
| S4 | 4 | 78,697 | 25,388 | 0 | 4,323 | 0.406 | 0.41 | 30 s | 58 s |
| S5 | 4 | 69,869 | 15,660 | 7,830 | 4,022 | 0.402 | 0.40 | 29 s | 55 s |
| S6 | 4 | 68,407 | 23,490 | 0 | 4,054 | 0.359 | 0.36 | 29 s | 55 s |
| S7 pass 1 | 4 | 65,133 | 23,490 | 0 | 3,631 | 0.338 | - | 39 s | 63 s |
| S7 pass 2 | 4 | 77,909 | 25,388 | 0 | 4,046 | 0.398 | 0.74 (both passes) | 31 s | 59 s |
| S8 | 4 | 69,881 | 23,490 | 0 | 4,316 | 0.371 | 0.37 | 31 s | 57 s |
| S9 | 4 | 64,940 | 23,490 | 0 | 3,739 | 0.339 | 0.34 | 28 s | 53 s |
| S10 | 4 | 66,288 | 23,490 | 0 | 4,582 | 0.361 | 0.36 | 32 s | 60 s |
| S11 ENC-1103 transfer | 4 | 89,218 | 25,388 | 0 | 4,372 | 0.449 | - | 28 s | 61 s |
| S11 ENC-1103 discharge | 4 | 76,050 | 23,490 | 0 | 4,118 | 0.391 | - | 27 s | 54 s |
| S13 | 4 | 73,495 | 25,396 | 0 | 4,676 | 0.393 | 0.39 | 33 s | 62 s |
| **Total** | 56 | 1,010,261 | 330,528 | 7,830 | 58,162 | 5.310 | | | 817 s |

S7 over its 2 passes: 8 runs, 0.74 USD, 69 s elapsed in the passes (the wait for approval between them is not counted).

Per member, over all passes:

| Member | Runs | Mean input | Mean output | Mean cost, USD | Duration, lowest to highest | Mean tool calls |
| --- | --- | --- | --- | --- | --- | --- |
| conformance | 14 | 17,074 | 1,100 | 0.092 | 12 to 21 s | 5.1 |
| encounter | 14 | 18,714 | 965 | 0.096 | 11 to 16 s | 5.6 |
| impact | 14 | 17,313 | 1,125 | 0.094 | 12 to 17 s | 6.0 |
| coordinator | 14 | 19,060 | 964 | 0.098 | 12 to 22 s | 2.1 |

<details>
<summary>Every run</summary>

| Recording | Started | Duration | Input | Cache read | Cache write | Output | Tool calls | Cost, USD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `scenario-S1-ENC-1001-transfer-conformance-1.json` | 2026-10-19T17:53:47Z | 20.9 s | 16,415 | 5,718 | 0 | 1,181 | 5 | 0.0904 |
| `scenario-S1-ENC-1001-transfer-encounter-1.json` | 2026-10-19T17:53:47Z | 14.7 s | 24,247 | 7,592 | 0 | 867 | 6 | 0.1158 |
| `scenario-S1-ENC-1001-transfer-impact-1.json` | 2026-10-19T17:53:47Z | 12.8 s | 17,476 | 5,691 | 0 | 1,031 | 6 | 0.0917 |
| `scenario-S1-ENC-1001-transfer-coordinator-1.json` | 2026-10-19T17:54:08Z | 17.2 s | 19,358 | 6,387 | 0 | 923 | 2 | 0.0972 |
| `scenario-S2-ENC-1002-transfer-conformance-1.json` | 2026-10-19T17:54:43Z | 13.5 s | 15,328 | 5,718 | 0 | 972 | 5 | 0.0819 |
| `scenario-S2-ENC-1002-transfer-encounter-1.json` | 2026-10-19T17:54:43Z | 11.4 s | 15,572 | 5,694 | 0 | 874 | 6 | 0.0809 |
| `scenario-S2-ENC-1002-transfer-impact-1.json` | 2026-10-19T17:54:43Z | 13.0 s | 16,318 | 5,691 | 0 | 1,076 | 6 | 0.0879 |
| `scenario-S2-ENC-1002-transfer-coordinator-1.json` | 2026-10-19T17:54:57Z | 13.9 s | 17,479 | 6,387 | 0 | 797 | 2 | 0.0871 |
| `scenario-S3-ENC-1003-transfer-conformance-1.json` | 2026-10-19T17:55:31Z | 20.9 s | 16,043 | 5,718 | 0 | 1,571 | 5 | 0.0967 |
| `scenario-S3-ENC-1003-transfer-encounter-1.json` | 2026-10-19T17:55:31Z | 12.8 s | 16,059 | 5,694 | 0 | 868 | 5 | 0.0827 |
| `scenario-S3-ENC-1003-transfer-impact-1.json` | 2026-10-19T17:55:31Z | 13.3 s | 17,728 | 5,691 | 0 | 1,080 | 6 | 0.0936 |
| `scenario-S3-ENC-1003-transfer-coordinator-1.json` | 2026-10-19T17:55:52Z | 16.8 s | 18,351 | 6,387 | 0 | 1,043 | 2 | 0.0955 |
| `scenario-S4-ENC-1004-transfer-conformance-1.json` | 2026-10-19T17:56:29Z | 13.3 s | 17,382 | 5,718 | 0 | 1,108 | 5 | 0.0928 |
| `scenario-S4-ENC-1004-transfer-encounter-1.json` | 2026-10-19T17:56:29Z | 14.0 s | 24,920 | 7,592 | 0 | 1,067 | 7 | 0.1225 |
| `scenario-S4-ENC-1004-transfer-impact-1.json` | 2026-10-19T17:56:29Z | 16.2 s | 17,434 | 5,691 | 0 | 1,099 | 6 | 0.0929 |
| `scenario-S4-ENC-1004-transfer-coordinator-1.json` | 2026-10-19T17:56:45Z | 14.0 s | 18,961 | 6,387 | 0 | 1,049 | 2 | 0.0981 |
| `scenario-S5-ENC-1005-transfer-conformance-1.json` | 2026-10-19T21:34:50Z | 12.8 s | 15,874 | 3,812 | 1,906 | 979 | 5 | 0.0934 |
| `scenario-S5-ENC-1005-transfer-encounter-1.json` | 2026-10-19T21:34:50Z | 13.1 s | 16,936 | 3,796 | 1,898 | 983 | 6 | 0.0977 |
| `scenario-S5-ENC-1005-transfer-impact-1.json` | 2026-10-19T21:34:50Z | 15.8 s | 16,925 | 3,794 | 1,897 | 1,046 | 6 | 0.0989 |
| `scenario-S5-ENC-1005-transfer-coordinator-1.json` | 2026-10-19T21:35:06Z | 13.0 s | 20,134 | 4,258 | 2,129 | 1,014 | 4 | 0.1123 |
| `scenario-S6-ENC-1006-transfer-conformance-1.json` | 2026-10-19T21:35:40Z | 15.7 s | 17,172 | 5,718 | 0 | 1,100 | 5 | 0.0918 |
| `scenario-S6-ENC-1006-transfer-encounter-1.json` | 2026-10-19T21:35:40Z | 11.2 s | 14,715 | 5,694 | 0 | 802 | 4 | 0.0760 |
| `scenario-S6-ENC-1006-transfer-impact-1.json` | 2026-10-19T21:35:40Z | 14.6 s | 17,340 | 5,691 | 0 | 1,127 | 6 | 0.0930 |
| `scenario-S6-ENC-1006-transfer-coordinator-1.json` | 2026-10-19T21:35:56Z | 13.2 s | 19,180 | 6,387 | 0 | 1,025 | 2 | 0.0985 |
| `scenario-S7-ENC-1007-transfer-conformance-1.json` | 2026-10-19T21:36:28Z | 13.4 s | 15,378 | 5,718 | 0 | 914 | 5 | 0.0809 |
| `scenario-S7-ENC-1007-transfer-encounter-1.json` | 2026-10-19T21:36:28Z | 11.0 s | 15,531 | 5,694 | 0 | 863 | 6 | 0.0805 |
| `scenario-S7-ENC-1007-transfer-impact-1.json` | 2026-10-19T21:36:28Z | 16.3 s | 16,249 | 5,691 | 0 | 1,065 | 6 | 0.0874 |
| `scenario-S7-ENC-1007-transfer-coordinator-1.json` | 2026-10-19T21:36:45Z | 21.9 s | 17,975 | 6,387 | 0 | 789 | 2 | 0.0890 |
| `scenario-S7-ENC-1007-transfer-conformance-1-round2.json` | 2026-10-19T21:37:09Z | 18.2 s | 16,449 | 5,718 | 0 | 1,066 | 5 | 0.0883 |
| `scenario-S7-ENC-1007-transfer-encounter-1-round2.json` | 2026-10-19T21:37:09Z | 15.8 s | 25,586 | 7,592 | 0 | 992 | 7 | 0.1237 |
| `scenario-S7-ENC-1007-transfer-impact-1-round2.json` | 2026-10-19T21:37:09Z | 12.3 s | 17,396 | 5,691 | 0 | 990 | 6 | 0.0905 |
| `scenario-S7-ENC-1007-transfer-coordinator-1-round2.json` | 2026-10-19T21:37:27Z | 12.6 s | 18,478 | 6,387 | 0 | 998 | 2 | 0.0951 |
| `scenario-S8-ENC-1008-transfer-conformance-1.json` | 2026-10-19T21:37:58Z | 14.6 s | 16,437 | 5,718 | 0 | 1,136 | 5 | 0.0896 |
| `scenario-S8-ENC-1008-transfer-encounter-1.json` | 2026-10-19T21:37:58Z | 11.9 s | 17,059 | 5,694 | 0 | 926 | 6 | 0.0879 |
| `scenario-S8-ENC-1008-transfer-impact-1.json` | 2026-10-19T21:37:58Z | 14.2 s | 17,368 | 5,691 | 0 | 1,116 | 6 | 0.0929 |
| `scenario-S8-ENC-1008-transfer-coordinator-1.json` | 2026-10-19T21:38:13Z | 16.3 s | 19,017 | 6,387 | 0 | 1,138 | 2 | 0.1001 |
| `scenario-S9-ENC-1009-transfer-conformance-1.json` | 2026-10-19T21:38:48Z | 11.9 s | 15,221 | 5,718 | 0 | 888 | 5 | 0.0798 |
| `scenario-S9-ENC-1009-transfer-encounter-1.json` | 2026-10-19T21:38:48Z | 13.4 s | 15,593 | 5,694 | 0 | 879 | 6 | 0.0811 |
| `scenario-S9-ENC-1009-transfer-impact-1.json` | 2026-10-19T21:38:48Z | 14.7 s | 16,317 | 5,691 | 0 | 1,022 | 6 | 0.0868 |
| `scenario-S9-ENC-1009-transfer-coordinator-1.json` | 2026-10-19T21:39:03Z | 13.0 s | 17,809 | 6,387 | 0 | 950 | 2 | 0.0915 |
| `scenario-S10-ENC-1010-transfer-conformance-1.json` | 2026-10-19T21:39:36Z | 15.7 s | 16,290 | 5,718 | 0 | 1,067 | 5 | 0.0876 |
| `scenario-S10-ENC-1010-transfer-encounter-1.json` | 2026-10-19T21:39:36Z | 16.4 s | 15,463 | 5,694 | 0 | 1,337 | 6 | 0.0897 |
| `scenario-S10-ENC-1010-transfer-impact-1.json` | 2026-10-19T21:39:36Z | 13.3 s | 16,252 | 5,691 | 0 | 1,179 | 6 | 0.0897 |
| `scenario-S10-ENC-1010-transfer-coordinator-1.json` | 2026-10-19T21:39:53Z | 14.6 s | 18,283 | 6,387 | 0 | 999 | 2 | 0.0944 |
| `scenario-S11-ENC-1103-transfer-conformance-1.json` | 2026-10-19T21:42:45Z | 16.7 s | 18,002 | 5,718 | 0 | 1,094 | 5 | 0.0950 |
| `scenario-S11-ENC-1103-transfer-encounter-1.json` | 2026-10-19T21:42:45Z | 16.2 s | 30,343 | 7,592 | 0 | 1,046 | 7 | 0.1438 |
| `scenario-S11-ENC-1103-transfer-impact-1.json` | 2026-10-19T21:42:45Z | 15.9 s | 19,410 | 5,691 | 0 | 1,323 | 6 | 0.1052 |
| `scenario-S11-ENC-1103-transfer-coordinator-1.json` | 2026-10-19T21:43:01Z | 12.1 s | 21,463 | 6,387 | 0 | 909 | 2 | 0.1053 |
| `scenario-S11-ENC-1103-discharge-conformance-1.json` | 2026-10-19T21:43:15Z | 12.8 s | 18,224 | 5,718 | 0 | 952 | 5 | 0.0931 |
| `scenario-S11-ENC-1103-discharge-encounter-1.json` | 2026-10-19T21:43:15Z | 13.1 s | 16,843 | 5,694 | 0 | 992 | 4 | 0.0884 |
| `scenario-S11-ENC-1103-discharge-impact-1.json` | 2026-10-19T21:43:15Z | 14.5 s | 19,403 | 5,691 | 0 | 1,144 | 6 | 0.1016 |
| `scenario-S11-ENC-1103-discharge-coordinator-1.json` | 2026-10-19T21:43:29Z | 13.5 s | 21,580 | 6,387 | 0 | 1,030 | 2 | 0.1082 |
| `scenario-S13-ENC-1013-transfer-conformance-1.json` | 2026-10-19T21:40:26Z | 17.2 s | 24,822 | 7,624 | 0 | 1,371 | 6 | 0.1282 |
| `scenario-S13-ENC-1013-transfer-encounter-1.json` | 2026-10-19T21:40:26Z | 13.2 s | 13,127 | 5,694 | 0 | 1,017 | 2 | 0.0740 |
| `scenario-S13-ENC-1013-transfer-impact-1.json` | 2026-10-19T21:40:26Z | 17.0 s | 16,767 | 5,691 | 0 | 1,449 | 6 | 0.0972 |
| `scenario-S13-ENC-1013-transfer-coordinator-1.json` | 2026-10-19T21:40:44Z | 15.0 s | 18,779 | 6,387 | 0 | 839 | 2 | 0.0932 |

</details>

## Scenarios with no board recordings

- S12 A lost admission at the head of a chain: an incident whose chains the catalogue and the site's policy settle; the board decides none.
- S15 A patient merge Shutter withholds for the PAS team: withheld before any agent runs (MERGE_WITHHELD).
- S16 A cancellation the downstream system cannot reverse: withheld before any agent runs (CANCEL_UNSUPPORTED).
- S17 S2 in HL7 2.4: played in policy mode only.
- S18 S2 in HL7 2.3.1: played in policy mode only.
- S19 Shape A: a failed transfer in the hospital's own production: played in policy mode only.
- S20 A nurse moves the patient by hand while the plan awaits approval: played in rules mode only.

## Not yet measured

- **Repeat runs.** Each pass above is one recording per member. Nothing here shows how often the same model, on the same version of the product, reaches the same disposition when the case is run again. Earlier recordings made on earlier versions of the product are in the repository's history; they are not a controlled repeat, and this document does not read them.
- **The single investigator.** Shutter can give a case to one generalist agent instead of the board (`scenario_check.py --modes single`), but no generalist runs are in `fixtures/records`, so the board is not compared with a single agent here.
- **Adversarial variants.** No adversarial text reached any agent in these recordings: the one injected note stays in IRIS and the agents see only its flags, so what is shown is that they notice the flag, not that they resist an instruction. Earlier recordings in the repository's history were made with the note's text sent; this document does not read them. No note pushes towards a wrong answer, and no variant feeds misleading or contradictory evidence.
- **Held-out cases.** In 13 of 13 scored passes the plan cites a catalogue entry that names the same scenario in its `scenarios` field: the knowledge the agents read was written alongside these scenarios. No case here was kept back from the authors of the catalogue.
- **Other models and calibration.** Every run used claude-opus-5-5; there is too little data for a confidence calibration, and no grading of the summaries' reasoning beyond the disposition, the entry and the evidence keys.

