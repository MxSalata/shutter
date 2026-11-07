# Outcome report

Agree the criteria before the stage starts, and write them in the [decision record](00-decision-record.md). This pack sets no target percentages. Give counts with their denominators, not percentages alone.

## Observation

Count by case opened in the period, not by message or by repeated investigation.

```text
Period, Shutter version, namespaces, receivers:

1.  Cases opened:
2.  Failures the engine showed, or census result, and how counted:
3.  Failures with no case, and why:
4.  Cases with a person's independent review:
5.  Proposed: resend / reconcile / superseded / escalate / other:
6.  Gate: passed / blocked / unknown:
7.  Cases blocked only because the receiver has no API:
8.  Reviewer agreed with the proposal:      of reviewed
9.  Unsafe resend proposals:                of reviewed resend proposals
10. Wrongly did nothing:                    of reviewed no-action proposals
11. Cautious stops a person thought needless: of reviewed
12. Cases still needing a person:
13. Reviewer minutes, and how many cases were timed:
14. Model spend:
15. Write attempts (must be 0), and emails sent:
```

Where practical, the reviewer decides what should happen from the source and receiver evidence **before** seeing Shutter's answer.

Observation with no receiver API can't test a resend: the gate blocks it for lack of evidence. A case in that mode shows what reached Shutter, and what it would ask about, and no more.

## Bounded recovery

```text
16. Write attempts:
17. Attempts that met the criteria you set for checking at the receiver:
18. Attempts with an uncertain outcome, and how each ended:
19. Checked at the receiver by a person (ward, bed, patient), not only "verified":
20. Wrong writes, with their correction:
21. Stops called, why, and how long until recovery was halted:
22. Cases handed over, and how long until accepted:
23. Time from failure to correct record, against the ordinary route, and how measured:
```

## What you may say

- "During the period, Shutter received N cases. Of M independently reviewed, reviewers agreed with its proposed result in K."
- "Of P authorised attempts, Q met our criteria at the receiver." Only after stage 3.

Don't say "would have recovered R cases" from observation: a resend that never went tested nothing at the receiver. Don't call N "all failures" unless you have counted failures another way, and say how. Name what wasn't tested, and don't carry a result to another receiver.

## Decision

```text
Criteria met, and not met:
Hazards that changed:
Decision: continue under a new record / return to observation / withdraw
Signed, with names and dates:
```
