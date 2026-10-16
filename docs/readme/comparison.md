# Comparison: the board of specialists and rules alone

Played on a development instance on 16 October 2026 with `tests/e2e/scenario_check.py --approve --modes board,rules
S1 S2 S3 S4 S5 S6 S7 S8 S9 S10`. The check plays each scenario through the REST API, approves any plan that waits for
approval (as a person who approves whatever is proposed would), and compares the case's outcome and the receiving
system's final state with the scenario's expected outcome (`fixtures/scenarios.json`).

**The board's answers here are replays of recorded runs, written by hand as fixtures, not live model output.** The
same comparison with live agents comes with the AI Hub build. Rules only uses no agents: it proposes resending the
operation unchanged at the observed version, and the gate alone decides.

| Scenario | Expected | Board of specialists | Rules only |
| --- | --- | --- | --- |
| S1 Stale transfer after a later transfer | superseded, no write, ward admitted WARD-C | as expected: resolved, superseded, no write, ward admitted WARD-C | **differs**: blocked, resend, no write, ward admitted WARD-C (disposition resend, expected superseded) |
| S2 Never-accepted transfer, still current | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S3 Lost acknowledgment | reconcile, no write, ward admitted WARD-B | as expected: resolved, reconcile, no write, ward admitted WARD-B | **differs**: blocked, resend, no write, ward admitted WARD-B (disposition resend, expected reconcile) |
| S4 Misleading duplicate error, with an injected note | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S5 A later unrelated update | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S6 Transfer after discharge | superseded, no write, ward discharged | as expected: resolved, superseded, no write, ward discharged None | **differs**: blocked, resend, no write, ward discharged None (disposition resend, expected superseded) |
| S7 Conditions change while the plan awaits approval | superseded, no write, ward admitted WARD-C | as expected: resolved, superseded, no write, ward admitted WARD-C | **differs**: blocked, resend, no write, ward admitted WARD-C (disposition resend, expected superseded) |
| S8 Event times that can't be compared | escalate, no write, ward admitted WARD-C | as expected: escalated, escalate, no write, ward admitted WARD-C | **differs**: resolved, resend, one write, ward admitted WARD-B (disposition resend, expected escalate or more_evidence; wrote to the ward; the ward holds admitted WARD-B, expected admitted WARD-C) |
| S9 One patient, two encounters | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S10 The ward can't take a conditional write | escalate, no write, ward admitted WARD-A | as expected: escalated, escalate, no write, ward admitted WARD-A | **differs**: blocked, resend, no write, ward admitted WARD-A (disposition resend, expected escalate or more_evidence) |

## What it shows

- **The board gets all ten right.** Rules alone get the four plain resends right (S2, S4, S5, S9).
- **Where rules alone are wrong, the gate usually stops them.** In S1, S3, S6, S7 and S10 the resend is blocked by a
  check (a later event, an existing receipt, a discharge, a changed receiver, a receiver that can't take a conditional
  write), so nothing wrong reaches the receiver, but the case stops for a person.
- **S8 is the case a gate can't catch.** Two systems moved the same patient at the same time, 09:20. No event is
  later than the other, so every mechanical check passes; rules alone resend, the approval goes through, and the
  write moves the patient to Ward B over the bed manager's placement in Ward C. The board sees that the evidence
  can't decide which movement is current and escalates to a person.
