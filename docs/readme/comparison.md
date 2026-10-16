# Comparison: the board of specialists and rules alone (draft)

Played on a development instance on 16 October 2026 with `tests/e2e/scenario_check.py --approve --modes board,rules
S1 S2 S3`, which plays each scenario through the REST API, approves a plan that waits for approval, and compares the
case's outcome and the ward's final state with the scenario's expected outcome (`fixtures/scenarios.json`).

**The board's answers here are replays of recorded runs, written by hand as fixtures, not live model output.** The
same comparison with live agents comes with the AI Hub build. Rules only uses no agents: it proposes resending the
operation unchanged at the observed version, and the gate alone decides.

| Scenario | Expected | Board of specialists | Rules only |
| --- | --- | --- | --- |
| S1 Stale transfer after a later transfer | superseded, no write, ward admitted WARD-C | as expected: resolved, superseded, no write, ward admitted WARD-C | **differs**: blocked, resend, no write, ward admitted WARD-C (disposition resend, expected superseded) |
| S2 Never-accepted transfer, still current | resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B | as expected: resolved, resend, one write, ward admitted WARD-B |
| S3 Lost acknowledgment | reconcile, no write, ward admitted WARD-B | as expected: resolved, reconcile, no write, ward admitted WARD-B | **differs**: blocked, resend, no write, ward admitted WARD-B (disposition resend, expected reconcile) |

What it shows: in both cases where rules alone are wrong (S1, a stale transfer; S3, a lost acknowledgement), the gate
blocks the resend, so nothing wrong reaches the ward; the case stops for a person. The board resolves both, with the
evidence for its answer, and in S2, where resending is right, both agree.
