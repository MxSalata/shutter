# Comparison: the board of specialists and rules alone

Played on 19 October 2026 with `tests/e2e/scenario_check.py --approve`, which plays each scenario through the REST
API, approves any plan that waits for approval (as a person who approves whatever is proposed would), and compares the
case's outcome and the receiving system's final state with the scenario's expected outcome (`fixtures/scenarios.json`).

- **Board, live:** the board of specialists with live agents, `claude-opus-5-5`, on the contest's AI Hub build
  (irishealth-community:2026.3.0AI.154.0) in record mode: for each case the three specialists in parallel, then the
  coordinator. 48 agent runs for these eleven cases (S7 was planned twice), 5.04 USD, as the instance's own costs page
  reports; with the board's two passes in S11's incident, the whole recording took 56 runs, 1,170,307 input and 63,188
  output tokens, 6.02 USD. What the agents saw carried tokens for the patient's identifiers, with no demographics and
  no note text (`tests/privacy_check.py`). Each cell gives the case's cost.
- **Board, replay:** the same board replaying those live runs' recordings, as Shutter does without an API key (the
  recordings in `fixtures/records` are these runs, one per board member and case). Played on IRIS for Health Community
  2026.2 in replay mode, with no model calls, as CI does on every push.
- **Rules only:** no agents. It proposes resending the operation unchanged at the observed version, and the gate alone
  decides.

| Scenario | Expected | Board, live | Board, replay | Rules only |
| --- | --- | --- | --- | --- |
| S1 Stale transfer after a later transfer | superseded, no write, ward admitted WARD-C | as expected: resolved, superseded, no write, ward admitted WARD-C (0.41 USD) | as expected: resolved, superseded, no write, ward admitted WARD-C | **differs**: blocked, resend, no write, ward admitted WARD-C (disposition resend, expected superseded) |
| S2 Never-accepted transfer, still current | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B (0.40 USD) | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S3 Lost acknowledgment | reconcile, no write, ward admitted WARD-B | as expected: resolved, reconcile, no write, ward admitted WARD-B (0.40 USD) | as expected: resolved, reconcile, no write, ward admitted WARD-B | **differs**: blocked, resend, no write, ward admitted WARD-B (disposition resend, expected reconcile) |
| S4 Misleading duplicate error, with an injected note | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B (0.46 USD) | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S5 A later unrelated update | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B (0.39 USD) | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S6 Transfer after discharge | superseded, no write, ward discharged | as expected: resolved, superseded, no write, ward discharged None (0.37 USD) | as expected: resolved, superseded, no write, ward discharged None | **differs**: blocked, resend, no write, ward discharged None (disposition resend, expected superseded) |
| S7 Conditions change while the plan awaits approval | superseded, no write, ward admitted WARD-C | as expected: resolved, superseded, no write, ward admitted WARD-C (0.84 USD) | as expected: resolved, superseded, no write, ward admitted WARD-C | **differs**: blocked, resend, no write, ward admitted WARD-C (disposition resend, expected superseded) |
| S8 Event times that can't be compared | escalate, no write, ward admitted WARD-C | as expected: escalated, escalate, no write, ward admitted WARD-C (0.43 USD) | as expected: escalated, escalate, no write, ward admitted WARD-C | **differs**: resolved, resend, one write, ward admitted WARD-B (disposition resend, expected escalate or more_evidence; wrote to the ward; the ward holds admitted WARD-B, expected admitted WARD-C) |
| S9 One patient, two encounters | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B (0.37 USD) | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S10 The ward can't take a conditional write | escalate, no write, ward admitted WARD-A | as expected: escalated, escalate, no write, ward admitted WARD-A (0.45 USD) | as expected: escalated, escalate, no write, ward admitted WARD-A | **differs**: blocked, resend, no write, ward admitted WARD-A (disposition resend, expected escalate or more_evidence) |
| S13 A transfer timed before its admission | escalate, no write, ward admitted WARD-A | as expected: escalated, escalate, no write, ward admitted WARD-A (0.51 USD) | as expected: escalated, escalate, no write, ward admitted WARD-A | **differs**: blocked, resend, no write, ward admitted WARD-A (disposition resend, expected escalate or more_evidence) |

## What it shows

- **The board gets all eleven right, with live agents as in replay.** Rules alone get the four plain resends right
  (S2, S4, S5, S9).
- **Where rules alone are wrong, the gate usually stops them.** In S1, S3, S6, S7, S10 and S13 the resend is blocked by
  a check (a later event, an existing receipt, a discharge, a changed receiver, a receiver that can't take a conditional
  write, an event time before the admission), so nothing wrong reaches the receiver, but the case stops for a person.
- **S8 is the case a gate can't catch.** Two systems moved the same patient at the same time, 09:20. No event is
  later than the other, so every mechanical check passes; rules alone resend, the approval goes through, and the
  write moves the patient to Ward B over the bed manager's placement in Ward C. The board sees that the evidence
  can't decide which movement is current and escalates to a person.
- **S13 is bad data from the PAS.** A transfer timed half an hour before the patient's admission can't be resent or
  ordered: the gate refuses the write (`EVENT_TIME_IMPLAUSIBLE`), and the board, matching catalogue entry E13, escalates
  so the PAS team can check the source.
- **What a live case costs.** Most cases took one board pass, four agent runs, for 0.37 to 0.51 USD. S7 took two
  passes, 0.84 USD: a later transfer arrived while the first plan awaited approval, so the case was planned again and
  closed as superseded.

The replay column is what CI checks on every push: a full install on IRIS for Health Community, then
`scenario_check.py --approve` over S1 to S10 and S13 with these recordings, all expected to match; the image job builds
the contest image's Dockerfile and plays S2 on it.
