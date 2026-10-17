# Comparison: the board of specialists and rules alone

Played on 16 October 2026 with `tests/e2e/scenario_check.py --approve`, which plays each scenario through the REST
API, approves any plan that waits for approval (as a person who approves whatever is proposed would), and compares the
case's outcome and the receiving system's final state with the scenario's expected outcome (`fixtures/scenarios.json`).

- **Board, live:** the board of specialists with live agents, `claude-opus-5-5`, on the contest's AI Hub build
  (irishealth-community:2026.3.0AI.154.0) in record mode: for each case the three specialists in parallel, then the
  coordinator. 44 agent runs in all (S7 was planned twice), 1,005,417 input and 56,829 output tokens: 5.18 USD at
  $4 and $20 per million tokens, as the instance's own costs page reports. Each cell gives the case's cost.
- **Board, replay:** the same board replaying those live runs' recordings, as Shutter does without an API key (the
  recordings in `fixtures/records` are these runs, one per board member and case). Played on the same instance in
  replay mode, with no model calls.
- **Rules only:** no agents. It proposes resending the operation unchanged at the observed version, and the gate alone
  decides.

| Scenario | Expected | Board, live | Board, replay | Rules only |
| --- | --- | --- | --- | --- |
| S1 Stale transfer after a later transfer | superseded, no write, ward admitted WARD-C | as expected: resolved, superseded, no write, ward admitted WARD-C (0.41 USD) | as expected: resolved, superseded, no write, ward admitted WARD-C | **differs**: blocked, resend, no write, ward admitted WARD-C (disposition resend, expected superseded) |
| S2 Never-accepted transfer, still current | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B (0.43 USD) | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S3 Lost acknowledgment | reconcile, no write, ward admitted WARD-B | as expected: resolved, reconcile, no write, ward admitted WARD-B (0.45 USD) | as expected: resolved, reconcile, no write, ward admitted WARD-B | **differs**: blocked, resend, no write, ward admitted WARD-B (disposition resend, expected reconcile) |
| S4 Misleading duplicate error, with an injected note | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B (0.60 USD) | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S5 A later unrelated update | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B (0.49 USD) | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S6 Transfer after discharge | superseded, no write, ward discharged | as expected: resolved, superseded, no write, ward discharged None (0.36 USD) | as expected: resolved, superseded, no write, ward discharged None | **differs**: blocked, resend, no write, ward discharged None (disposition resend, expected superseded) |
| S7 Conditions change while the plan awaits approval | superseded, no write, ward admitted WARD-C | as expected: resolved, superseded, no write, ward admitted WARD-C (0.91 USD) | as expected: resolved, superseded, no write, ward admitted WARD-C | **differs**: blocked, resend, no write, ward admitted WARD-C (disposition resend, expected superseded) |
| S8 Event times that can't be compared | escalate, no write, ward admitted WARD-C | as expected: escalated, escalate, no write, ward admitted WARD-C (0.59 USD) | as expected: escalated, escalate, no write, ward admitted WARD-C | **differs**: resolved, resend, one write, ward admitted WARD-B (disposition resend, expected escalate or more_evidence; wrote to the ward; the ward holds admitted WARD-B, expected admitted WARD-C) |
| S9 One patient, two encounters | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B (0.42 USD) | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S10 The ward can't take a conditional write | escalate, no write, ward admitted WARD-A | as expected: escalated, escalate, no write, ward admitted WARD-A (0.51 USD) | as expected: escalated, escalate, no write, ward admitted WARD-A | **differs**: blocked, resend, no write, ward admitted WARD-A (disposition resend, expected escalate or more_evidence) |

## What it shows

- **The board gets all ten right, with live agents as in replay.** Rules alone get the four plain resends right
  (S2, S4, S5, S9).
- **Where rules alone are wrong, the gate usually stops them.** In S1, S3, S6, S7 and S10 the resend is blocked by a
  check (a later event, an existing receipt, a discharge, a changed receiver, a receiver that can't take a conditional
  write), so nothing wrong reaches the receiver, but the case stops for a person.
- **S8 is the case a gate can't catch.** Two systems moved the same patient at the same time, 09:20. No event is
  later than the other, so every mechanical check passes; rules alone resend, the approval goes through, and the
  write moves the patient to Ward B over the bed manager's placement in Ward C. The board sees that the evidence
  can't decide which movement is current and escalates to a person.
- **What a live case costs.** Most cases took one board pass, four agent runs, for 0.36 to 0.60 USD. S7 took two
  passes, 0.91 USD: a later transfer arrived while the first plan awaited approval, so the case was planned again and
  closed as superseded.

The replay column was reproduced on the contest image itself (irishealth-community:2026.3.0AI.154.0, built from
scratch with this repository's Dockerfile on 16 October 2026, with the live recordings): `scenario_check.py --approve`
over S1 to S10 reported all ten as expected.
