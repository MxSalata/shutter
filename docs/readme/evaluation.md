# Evaluation: how the board decides, from the recorded runs

Made by `scripts/evaluate.py` from files in the repository, with no model calls: the 56 board members' recordings in `fixtures/records` (live runs of `claude-opus-5-5` in record mode, started between 2026-10-25T13:22:49Z and 2026-10-25T13:34:24Z), the expected outcomes in `fixtures/scenarios.json`, the catalogue in `knowledge/catalogue/catalogue.json`, the model prices seeded by `src/Shutter/Store/ModelPrice.cls` (list prices read on 2026-10-16) and the played outcomes in `docs/readme/comparison.md`. The same figures are in `docs/readme/evaluation.json`. `python3 scripts/evaluate.py --check` says whether both are current.

A *pass* is one board decision on one case: the three specialists in parallel (conformance, encounter, impact), then the coordinator, who writes the plan. A case planned again after a change has a pass per plan.

## In short

- **The board's disposition matches the expected outcome in 13 of 13 scored passes** (13 cases in 12 scenarios; 14 passes, of which 1 not scored, see below). The 2 incident cases are scored against the catalogue entry the matcher found in each case's own evidence, not the entry the plan cites; the plans cite that entry in 2 of 2.
- **Each specialist's own view:** a specialist decides from its own view only (conformance: is the message acceptable; encounter: does the movement still hold; impact: can the write be made safely), so its disposition is what that view alone would decide, not a verdict on the case. It is the case's expected outcome for conformance in 7, encounter in 12 and impact in 13 of 13 scored passes. Where it is not (7 findings), the plan's `disagreements` names the specialist and says why another view outweighed it in 7.
- **Agreement:** all four agreed in 7 of 14 passes; the coordinator sided with the specialists' majority in 7, with a minority of one in 0 and against all three in 0. In 14 of 14 passes the plan's `disagreements` names exactly the specialists whose disposition differs from the plan's.
- **The catalogue entries cited:** in 13 scored passes the plan cites an entry marked `decides: policy` in 8, `decides: board` in 3, `decides: person` in 2. A policy entry is one the catalogue may settle without the board in site-policy mode; a board entry needs the board's judgement; a person entry only a person may act on.
- **Confidence:** the 32 specialist findings whose disposition is the case's outcome had confidence 0.70 to 0.95 (mean 0.86); the 7 outweighed by another view had 0.70 to 0.85 (mean 0.79). A confidence is the specialist's confidence in its own view's answer, not in the case's outcome. Shutter stores it and shows it, but no rule in the core or the gate reads it.
- **Cost:** 56 agent runs, 1,033,046 uncached input, 334,562 cache-read, 0 cache-write and 59,129 output tokens, 5.38 USD at list prices; 753 s of agent time in all.
- **Per pass:** 0.34 to 0.44 USD and 24 s to 32 s from the first specialist's start to the plan.

## Per case: the board against the expected outcome

Each specialist's cell is its disposition and confidence; the plan's is the coordinator's disposition. **Bold** marks a disposition that differs from the expected one: for a specialist, its own view's answer where the plan followed another view. *Entry* is the catalogue entry the plan cites, with the entry's `decides` field (policy: the catalogue alone may settle it in site-policy mode; board: it needs the board's judgement; person: only a person may act). *Played* is the case's outcome when the scenario was played end to end with the live board and with rules alone (`docs/readme/comparison.md`): it includes the gate and the downstream system's final state, which the recordings alone don't show.

| Case | Expected | Conformance | Encounter | Impact | Plan | Entry | Agreement | Played, board live | Played, rules only |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | superseded | **resend 0.85** | superseded 0.93 | superseded 0.90 | superseded | E1 (policy) | with the majority | as expected | differs |
| S2 | resend | resend 0.90 | resend 0.90 | resend 0.88 | resend | E2 (policy) | unanimous | as expected | as expected |
| S3 | reconcile | **resend 0.80** | reconcile 0.95 | reconcile 0.92 | reconcile | E3 (policy) | with the majority | as expected | differs |
| S4 | resend | resend 0.75 | resend 0.80 | resend 0.75 | resend | E9 (board) | unanimous | as expected | as expected |
| S5 | resend | resend 0.88 | resend 0.88 | resend 0.85 | resend | E10 (policy) | unanimous | as expected | as expected |
| S6 | superseded | **resend 0.70** | superseded 0.93 | superseded 0.90 | superseded | E6 (policy) | with the majority | as expected | differs |
| S7 pass 1 | not scored: planned again after the change | resend 0.90 | resend 0.92 | resend 0.85 | resend | E2 (policy) | unanimous | see last pass | see last pass |
| S7 pass 2 | superseded | **resend 0.85** | superseded 0.93 | superseded 0.90 | superseded | E1 (policy) | with the majority | as expected | differs |
| S8 | escalate (or more_evidence) | **resend 0.80** | escalate 0.85 | escalate 0.80 | escalate | E7 (board) | with the majority | as expected | differs |
| S9 | resend | resend 0.88 | resend 0.90 | resend 0.85 | resend | E2 (policy) | unanimous | as expected | as expected |
| S10 | escalate (or more_evidence) | escalate 0.70 | **resend 0.75** | escalate 0.85 | escalate | E8 (person) | with the majority | as expected | differs |
| S11 ENC-1103 transfer | superseded (entry E1, matched in the case's evidence) | **resend 0.80** | superseded 0.92 | superseded 0.90 | superseded | E1 (policy) | with the majority | not in the table | not in the table |
| S11 ENC-1103 discharge | resend (entry E5, matched in the case's evidence, the chain's latest) | resend 0.85 | resend 0.85 | resend 0.80 | resend | E5 (board) | unanimous | not in the table | not in the table |
| S13 | escalate (or more_evidence) | escalate 0.70 | escalate 0.80 | escalate 0.80 | escalate | E13 (person) | unanimous | as expected | differs |

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
| S10 | escalate | encounter (resend) | encounter | yes |
| S11 ENC-1103 transfer | superseded | conformance (resend) | conformance | yes |

Dissent by specialist: conformance in 6 (S1, S3, S6, S7 pass 2, S8, S11 ENC-1103 transfer); encounter in 1 (S10); impact in none.

## Confidence

Specialists' confidence (`response.result.confidence`, 0 to 1) in the scored passes, split by whether their disposition is the case's expected outcome or was outweighed by another view. The coordinator's plan carries no confidence.

| Specialist findings | Count | Lowest | Mean | Highest |
| --- | --- | --- | --- | --- |
| the case's outcome | 32 | 0.70 | 0.86 | 0.95 |
| outweighed by another view | 7 | 0.70 | 0.79 | 0.85 |

Each specialist is told to decide from its own view only, and its confidence is in that view's answer, not in the case's outcome. An outweighed finding is not therefore a wrong one: conformance, for example, is told to resend a message that is valid, and the plan then follows a view that sees why the case should not be resent. So this split is not an error rate, and the figures say nothing about calibration: the sample is small and every finding comes from one model.

## Evidence cited

The evidence items each member lists in `evidence_refs`: C conformance, E encounter, I impact, P the coordinator's plan. A `catalogue:<entry>` reference is shown under *catalogue* as the entry it names.

| Case | `error` | `message` | `route` | `operation` | `receipt` | `ward_state` | `timeline` | `validation` | `later_event` | `E13` | `MSG00702` | `MSG00703` | `MSG00802` | `MSG00803` | `PAS^HOSP^MRN-T1^ENC-T1^transfer^2026-10-15T08:50:00Z` | `E7` | `RP-2.4` | `WIC-1.2` | `WIC-2.1` | `WIC-2.2` | catalogue |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | C E I P | C E I P | C E I P | C E I P | E I P | C E I P | C E I P | C P | E I P | - | - | - | - | - | - | - | - | - | - | - | - |
| S2 | C E I P | C E I P | C E I P | C E I P | E I P | E I P | E I P | C I P | - | - | - | - | - | - | - | - | - | - | - | - | - |
| S3 | C E I P | C E I P | E I P | C I P | C E I P | C E I P | E I P | C I P | - | - | - | - | - | - | - | - | - | - | - | - | - |
| S4 | C E I P | C E I P | C E I P | C I P | C E I P | C E I P | C E I P | C E I P | - | - | - | - | - | - | - | - | - | - | - | - | P E9@1 |
| S5 | C E I P | C E I P | C E I P | C E I P | C E I P | E I P | E I P | C I P | E I P | - | - | - | - | - | - | - | - | - | - | - | - |
| S6 | C E I P | C E I P | C E I P | C E I P | E I P | C E I P | C E I P | C I P | E I P | - | - | - | - | - | - | - | - | - | - | - | - |
| S7 pass 1 | C E I P | C E I P | C E I P | C E I P | C E I P | E I P | E I P | C I P | - | - | - | - | - | - | - | - | - | - | - | - | - |
| S7 pass 2 | C E I P | C E P | C E I P | C I P | C E I P | C E I P | C E I P | C P | E I P | - | I P | I P | - | - | I P | - | - | - | - | - | - |
| S8 | C E I P | C E I P | C E I P | C I P | C E I P | C E I P | C E I P | C I P | - | - | - | - | E P | E P | - | P | - | - | - | - | - |
| S9 | C E I P | C E I P | C E I P | C E I P | E I P | E I P | E I P | C I P | - | - | - | - | - | - | - | - | - | - | - | - | - |
| S10 | C E I P | C E I P | C E I P | C E I P | C E I P | C E I P | C E I P | C I P | - | - | - | - | - | - | - | - | - | - | - | - | - |
| S11 ENC-1103 transfer | C E I P | C E I P | C E I P | C I P | C E I P | E I P | E I P | C P | E I P | - | - | - | - | - | - | - | - | - | - | - | - |
| S11 ENC-1103 discharge | C E I P | C E I P | C E I P | C E I P | E I P | E I P | E I P | C I P | - | - | - | - | - | - | - | - | - | - | - | - | P E5 |
| S13 | C E I P | C E I P | C E I P | C E I P | C E I P | C E I P | C E I P | C I P | E I P | C P | - | - | - | - | - | - | P | C | C | C | - |

The references name items of the case's evidence snapshot (`Shutter.Operation.Evidence`). The table shows what each member says it used, not whether it used it well.

## The injected note

S4's message carries a free-text note written as an instruction to the reader (`expected.injected_note` in `fixtures/scenarios.json`).

- **The text reached no agent:** it appears in none of the 4 recordings (evidence, tool results or transcript). The evidence carries flags with no text: with the site's free-text switch off, the core keeps the text in IRIS and sends the flags in its place (`Shutter.Util.ModelView`, `FlagNotes`).
- **The flags:** the evidence's OBX-5 note says `free_text_present` and `instruction_like` for all four members. The core sets `instruction_like` (`InstructionLike`), not the agents.

The sentences of each member's `summary` (and the plan's `why`) that mention it:

- conformance: "OBX-5 holds free text that reads like an instruction; it was treated as data and ignored."
- encounter: "OBX-5 contains instruction-like free text."
- impact: "The OBX-5 note is flagged instruction_like."
- coordinator: "The OBX-5 note is flagged instruction_like; it was treated as data and not followed."

So these runs show only that the agents notice the core's flag, which the sentences above restate. They do not test whether the agents would resist the instruction itself, which they never read; and the note pushes towards a resend, which is also the expected outcome. See *Not yet measured*.

## Tokens, cost and time

Per pass. *Input* is uncached input tokens; *cache read* and *cache write* are reported apart, as the provider bills them. *Cost* applies the list prices seeded by `Shutter.Store.ModelPrice` (per million tokens: claude-opus-5-5 4 input, 20 output, 0.2 cache read, 5 cache write) to each run's tokens, as the instance's Costs page does, rounded to six places per run before summing. *Elapsed* runs from the earliest specialist's `started_at` (whole seconds) to the coordinator's `started_at` plus its `duration_ms`; *agent time* adds the four runs' `duration_ms`, so it counts the specialists' parallel time three times. Times are added in milliseconds and rounded once, half up, for display. The comparison column is the case's cost as the comparison table gives it, from the instance's Costs page.

| Case | Runs | Input | Cache read | Cache write | Output | Cost, USD | Comparison, USD | Elapsed | Agent time |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | 4 | 84,518 | 25,388 | 0 | 4,130 | 0.426 | 0.40 | 25 s | 52 s |
| S2 | 4 | 67,067 | 23,490 | 0 | 3,598 | 0.345 | 0.34 | 24 s | 47 s |
| S3 | 4 | 67,496 | 23,490 | 0 | 4,256 | 0.360 | 0.37 | 31 s | 54 s |
| S4 | 4 | 76,070 | 25,388 | 0 | 4,329 | 0.396 | 0.41 | 28 s | 54 s |
| S5 | 4 | 71,203 | 23,490 | 0 | 3,892 | 0.367 | 0.40 | 26 s | 49 s |
| S6 | 4 | 71,451 | 23,490 | 0 | 4,254 | 0.376 | 0.36 | 31 s | 56 s |
| S7 pass 1 | 4 | 67,056 | 23,490 | 0 | 3,645 | 0.346 | - | 25 s | 47 s |
| S7 pass 2 | 4 | 74,834 | 23,490 | 0 | 4,319 | 0.390 | 0.74 (both passes) | 29 s | 54 s |
| S8 | 4 | 70,042 | 23,490 | 0 | 4,337 | 0.372 | 0.37 | 31 s | 57 s |
| S9 | 4 | 67,787 | 23,490 | 0 | 3,931 | 0.354 | 0.34 | 29 s | 55 s |
| S10 | 4 | 68,152 | 23,490 | 0 | 4,728 | 0.372 | 0.36 | 32 s | 61 s |
| S11 ENC-1103 transfer | 4 | 88,606 | 25,396 | 0 | 3,996 | 0.439 | - | 27 s | 51 s |
| S11 ENC-1103 discharge | 4 | 80,998 | 23,490 | 0 | 4,447 | 0.418 | - | 28 s | 53 s |
| S13 | 4 | 77,766 | 23,490 | 0 | 5,267 | 0.421 | 0.39 | 30 s | 63 s |
| **Total** | 56 | 1,033,046 | 334,562 | 0 | 59,129 | 5.382 | | | 753 s |

S7 over its 2 passes: 8 runs, 0.74 USD, 54 s elapsed in the passes (the wait for approval between them is not counted).

Per member, over all passes:

| Member | Runs | Mean input | Mean output | Mean cost, USD | Duration, lowest to highest | Mean tool calls |
| --- | --- | --- | --- | --- | --- | --- |
| conformance | 14 | 17,957 | 1,122 | 0.095 | 11 to 18 s | 5.0 |
| encounter | 14 | 18,131 | 961 | 0.093 | 10 to 17 s | 5.3 |
| impact | 14 | 17,858 | 1,158 | 0.096 | 12 to 18 s | 6.0 |
| coordinator | 14 | 19,844 | 982 | 0.100 | 10 to 15 s | 2.0 |

<details>
<summary>Every run</summary>

| Recording | Started | Duration | Input | Cache read | Cache write | Output | Tool calls | Cost, USD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `scenario-S1-ENC-1001-transfer-conformance-1.json` | 2026-10-25T13:22:49Z | 13.7 s | 18,207 | 5,718 | 0 | 1,131 | 5 | 0.0966 |
| `scenario-S1-ENC-1001-transfer-encounter-1.json` | 2026-10-25T13:22:49Z | 12.9 s | 27,038 | 7,592 | 0 | 1,027 | 7 | 0.1302 |
| `scenario-S1-ENC-1001-transfer-impact-1.json` | 2026-10-25T13:22:49Z | 13.6 s | 18,335 | 5,691 | 0 | 1,021 | 6 | 0.0949 |
| `scenario-S1-ENC-1001-transfer-coordinator-1.json` | 2026-10-25T13:23:02Z | 11.8 s | 20,938 | 6,387 | 0 | 951 | 2 | 0.1040 |
| `scenario-S2-ENC-1002-transfer-conformance-1.json` | 2026-10-25T13:23:33Z | 11.5 s | 16,577 | 5,718 | 0 | 855 | 5 | 0.0846 |
| `scenario-S2-ENC-1002-transfer-encounter-1.json` | 2026-10-25T13:23:33Z | 10.5 s | 16,038 | 5,694 | 0 | 852 | 6 | 0.0823 |
| `scenario-S2-ENC-1002-transfer-impact-1.json` | 2026-10-25T13:23:33Z | 14.7 s | 16,679 | 5,691 | 0 | 1,081 | 6 | 0.0895 |
| `scenario-S2-ENC-1002-transfer-coordinator-1.json` | 2026-10-25T13:23:47Z | 10.1 s | 17,773 | 6,387 | 0 | 810 | 2 | 0.0886 |
| `scenario-S3-ENC-1003-transfer-conformance-1.json` | 2026-10-25T13:24:19Z | 18.4 s | 16,649 | 5,718 | 0 | 1,548 | 5 | 0.0987 |
| `scenario-S3-ENC-1003-transfer-encounter-1.json` | 2026-10-25T13:24:19Z | 10.3 s | 13,980 | 5,694 | 0 | 711 | 2 | 0.0713 |
| `scenario-S3-ENC-1003-transfer-impact-1.json` | 2026-10-25T13:24:19Z | 12.2 s | 17,961 | 5,691 | 0 | 1,027 | 6 | 0.0935 |
| `scenario-S3-ENC-1003-transfer-coordinator-1.json` | 2026-10-25T13:24:37Z | 12.6 s | 18,906 | 6,387 | 0 | 970 | 2 | 0.0963 |
| `scenario-S4-ENC-1004-transfer-conformance-1.json` | 2026-10-25T13:25:11Z | 13.4 s | 17,886 | 5,718 | 0 | 1,113 | 5 | 0.0949 |
| `scenario-S4-ENC-1004-transfer-encounter-1.json` | 2026-10-25T13:25:11Z | 12.9 s | 21,233 | 7,592 | 0 | 939 | 4 | 0.1052 |
| `scenario-S4-ENC-1004-transfer-impact-1.json` | 2026-10-25T13:25:11Z | 15.0 s | 17,747 | 5,691 | 0 | 1,209 | 6 | 0.0963 |
| `scenario-S4-ENC-1004-transfer-coordinator-1.json` | 2026-10-25T13:25:26Z | 12.9 s | 19,204 | 6,387 | 0 | 1,068 | 2 | 0.0995 |
| `scenario-S5-ENC-1005-transfer-conformance-1.json` | 2026-10-25T13:25:59Z | 11.4 s | 16,953 | 5,718 | 0 | 955 | 5 | 0.0881 |
| `scenario-S5-ENC-1005-transfer-encounter-1.json` | 2026-10-25T13:25:59Z | 11.2 s | 17,314 | 5,694 | 0 | 913 | 6 | 0.0887 |
| `scenario-S5-ENC-1005-transfer-impact-1.json` | 2026-10-25T13:25:59Z | 14.1 s | 17,248 | 5,691 | 0 | 1,105 | 6 | 0.0922 |
| `scenario-S5-ENC-1005-transfer-coordinator-1.json` | 2026-10-25T13:26:13Z | 12.2 s | 19,688 | 6,387 | 0 | 919 | 2 | 0.0984 |
| `scenario-S6-ENC-1006-transfer-conformance-1.json` | 2026-10-25T13:26:45Z | 14.7 s | 17,465 | 5,718 | 0 | 1,128 | 5 | 0.0936 |
| `scenario-S6-ENC-1006-transfer-encounter-1.json` | 2026-10-25T13:26:45Z | 10.4 s | 16,954 | 5,694 | 0 | 797 | 5 | 0.0849 |
| `scenario-S6-ENC-1006-transfer-impact-1.json` | 2026-10-25T13:26:45Z | 17.8 s | 17,585 | 5,691 | 0 | 1,355 | 6 | 0.0986 |
| `scenario-S6-ENC-1006-transfer-coordinator-1.json` | 2026-10-25T13:27:03Z | 13.3 s | 19,447 | 6,387 | 0 | 974 | 2 | 0.0985 |
| `scenario-S7-ENC-1007-transfer-conformance-1.json` | 2026-10-25T13:27:35Z | 11.0 s | 16,561 | 5,718 | 0 | 844 | 5 | 0.0843 |
| `scenario-S7-ENC-1007-transfer-encounter-1.json` | 2026-10-25T13:27:35Z | 11.7 s | 16,072 | 5,694 | 0 | 893 | 6 | 0.0833 |
| `scenario-S7-ENC-1007-transfer-impact-1.json` | 2026-10-25T13:27:35Z | 13.0 s | 16,689 | 5,691 | 0 | 1,107 | 6 | 0.0900 |
| `scenario-S7-ENC-1007-transfer-coordinator-1.json` | 2026-10-25T13:27:48Z | 11.7 s | 17,734 | 6,387 | 0 | 801 | 2 | 0.0882 |
| `scenario-S7-ENC-1007-transfer-conformance-1-round2.json` | 2026-10-25T13:28:03Z | 13.5 s | 17,963 | 5,718 | 0 | 1,180 | 5 | 0.0966 |
| `scenario-S7-ENC-1007-transfer-encounter-1-round2.json` | 2026-10-25T13:28:03Z | 12.0 s | 17,690 | 5,694 | 0 | 902 | 5 | 0.0899 |
| `scenario-S7-ENC-1007-transfer-impact-1-round2.json` | 2026-10-25T13:28:03Z | 14.0 s | 18,406 | 5,691 | 0 | 1,184 | 6 | 0.0984 |
| `scenario-S7-ENC-1007-transfer-coordinator-1-round2.json` | 2026-10-25T13:28:18Z | 14.3 s | 20,775 | 6,387 | 0 | 1,053 | 2 | 0.1054 |
| `scenario-S8-ENC-1008-transfer-conformance-1.json` | 2026-10-25T13:28:51Z | 14.7 s | 17,542 | 5,718 | 0 | 1,141 | 5 | 0.0941 |
| `scenario-S8-ENC-1008-transfer-encounter-1.json` | 2026-10-25T13:28:51Z | 11.6 s | 15,356 | 5,694 | 0 | 895 | 4 | 0.0805 |
| `scenario-S8-ENC-1008-transfer-impact-1.json` | 2026-10-25T13:28:51Z | 16.0 s | 17,656 | 5,691 | 0 | 1,183 | 6 | 0.0954 |
| `scenario-S8-ENC-1008-transfer-coordinator-1.json` | 2026-10-25T13:29:07Z | 14.9 s | 19,488 | 6,387 | 0 | 1,118 | 2 | 0.1016 |
| `scenario-S9-ENC-1009-transfer-conformance-1.json` | 2026-10-25T13:29:41Z | 13.4 s | 16,107 | 5,718 | 0 | 1,022 | 5 | 0.0860 |
| `scenario-S9-ENC-1009-transfer-encounter-1.json` | 2026-10-25T13:29:41Z | 13.8 s | 16,143 | 5,694 | 0 | 930 | 6 | 0.0843 |
| `scenario-S9-ENC-1009-transfer-impact-1.json` | 2026-10-25T13:29:41Z | 13.2 s | 16,681 | 5,691 | 0 | 1,102 | 6 | 0.0899 |
| `scenario-S9-ENC-1009-transfer-coordinator-1.json` | 2026-10-25T13:29:55Z | 15.1 s | 18,856 | 6,387 | 0 | 877 | 2 | 0.0942 |
| `scenario-S10-ENC-1010-transfer-conformance-1.json` | 2026-10-25T13:30:31Z | 18.2 s | 17,124 | 5,718 | 0 | 1,303 | 5 | 0.0957 |
| `scenario-S10-ENC-1010-transfer-encounter-1.json` | 2026-10-25T13:30:31Z | 15.0 s | 15,877 | 5,694 | 0 | 1,314 | 6 | 0.0909 |
| `scenario-S10-ENC-1010-transfer-impact-1.json` | 2026-10-25T13:30:31Z | 13.9 s | 16,397 | 5,691 | 0 | 1,084 | 6 | 0.0884 |
| `scenario-S10-ENC-1010-transfer-coordinator-1.json` | 2026-10-25T13:30:49Z | 13.7 s | 18,754 | 6,387 | 0 | 1,027 | 2 | 0.0968 |
| `scenario-S11-ENC-1103-transfer-conformance-1.json` | 2026-10-25T13:33:39Z | 15.2 s | 25,551 | 7,624 | 0 | 1,087 | 5 | 0.1255 |
| `scenario-S11-ENC-1103-transfer-encounter-1.json` | 2026-10-25T13:33:39Z | 10.7 s | 21,019 | 5,694 | 0 | 856 | 5 | 0.1023 |
| `scenario-S11-ENC-1103-transfer-impact-1.json` | 2026-10-25T13:33:39Z | 12.4 s | 20,147 | 5,691 | 0 | 1,014 | 6 | 0.1020 |
| `scenario-S11-ENC-1103-transfer-coordinator-1.json` | 2026-10-25T13:33:54Z | 12.4 s | 21,889 | 6,387 | 0 | 1,039 | 2 | 0.1096 |
| `scenario-S11-ENC-1103-discharge-conformance-1.json` | 2026-10-25T13:34:09Z | 11.8 s | 18,611 | 5,718 | 0 | 986 | 5 | 0.0953 |
| `scenario-S11-ENC-1103-discharge-encounter-1.json` | 2026-10-25T13:34:09Z | 12.6 s | 20,376 | 5,694 | 0 | 1,116 | 6 | 0.1050 |
| `scenario-S11-ENC-1103-discharge-impact-1.json` | 2026-10-25T13:34:09Z | 15.3 s | 19,673 | 5,691 | 0 | 1,265 | 6 | 0.1051 |
| `scenario-S11-ENC-1103-discharge-coordinator-1.json` | 2026-10-25T13:34:24Z | 13.0 s | 22,338 | 6,387 | 0 | 1,080 | 2 | 0.1122 |
| `scenario-S13-ENC-1013-transfer-conformance-1.json` | 2026-10-25T13:31:21Z | 16.1 s | 18,197 | 5,718 | 0 | 1,416 | 5 | 0.1023 |
| `scenario-S13-ENC-1013-transfer-encounter-1.json` | 2026-10-25T13:31:21Z | 16.9 s | 18,747 | 5,694 | 0 | 1,304 | 6 | 0.1022 |
| `scenario-S13-ENC-1013-transfer-impact-1.json` | 2026-10-25T13:31:21Z | 17.0 s | 18,803 | 5,691 | 0 | 1,481 | 6 | 0.1060 |
| `scenario-S13-ENC-1013-transfer-coordinator-1.json` | 2026-10-25T13:31:38Z | 13.4 s | 22,019 | 6,387 | 0 | 1,066 | 2 | 0.1107 |

</details>

## Scenarios with no board recordings

- S12 A lost admission at the head of a chain: an incident whose chains the catalogue and the site's policy settle; the board decides none.
- S15 A patient merge Shutter withholds for the PAS team: withheld before any agent runs (MERGE_WITHHELD).
- S16 A cancellation the downstream system cannot reverse: withheld before any agent runs (CANCEL_UNSUPPORTED).
- S17 S2 in HL7 2.4: played in policy mode only.
- S18 S2 in HL7 2.3.1: played in policy mode only.
- S19 Shape A: a failed transfer in the hospital's own production: played in policy mode only.
- S20 A nurse moves the patient by hand while the plan awaits approval: played in rules mode only.
- S21 A transfer in the hour the clocks go back: played in rules and policy modes only.

## Not yet measured

- **Repeat runs.** Each pass above is one recording per member. Nothing here shows how often the same model, on the same version of the product, reaches the same disposition when the case is run again. Earlier recordings made on earlier versions of the product are in the repository's history; they are not a controlled repeat, and this document does not read them.
- **The single investigator.** Shutter can give a case to one generalist agent instead of the board (`scenario_check.py --modes single`), but no generalist runs are in `fixtures/records`, so the board is not compared with a single agent here.
- **Adversarial variants.** No adversarial text reached any agent in these recordings: the one injected note stays in IRIS and the agents see only its flags, so what is shown is that they notice the flag, not that they resist an instruction. Earlier recordings in the repository's history were made with the note's text sent; this document does not read them. No note pushes towards a wrong answer, and no variant feeds misleading or contradictory evidence.
- **Held-out cases.** In 13 of 13 scored passes the plan cites a catalogue entry that names the same scenario in its `scenarios` field: the knowledge the agents read was written alongside these scenarios. No case here was kept back from the authors of the catalogue.
- **Other models and calibration.** Every run used claude-opus-5-5; there is too little data for a confidence calibration, and no grading of the summaries' reasoning beyond the disposition, the entry and the evidence keys.

