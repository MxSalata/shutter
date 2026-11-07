# Daily review

Nothing in Shutter tells a person that a case needs them, so this review is a control. Name who does it, and who covers. Time it, and report the time ([09](09-outcome-report.md)).

Run these in the Management Portal's SQL page, in Shutter's namespace.

**Every write attempt.** In stage 2 this must return no rows. In stage 3 every row needs a named person as `Approver`, a case you recognise and a known result. An `Approver` of `policy` means the write went with no person: stop ([07](07-stop-and-withdraw.md)).

```sql
SELECT "Case"->CaseId AS CaseId, "At" AS AttemptAt, Outcome, HttpStatus, OperationKey, Approval->Approver AS Approver
FROM Shutter_Store.ExecutionAttempt ORDER BY ID DESC
```

**Cases still moving.**

```sql
SELECT CaseId, State, Receiver FROM Shutter_Store."Case"
WHERE State NOT IN ('resolved', 'blocked', 'escalated', 'failed')
```

**Cases closed without a resolution,** waiting for a person until marked handled:

```sql
SELECT CaseId, State, Disposition, Receiver FROM Shutter_Store."Case"
WHERE State IN ('blocked', 'escalated', 'failed')
```

**The health report:**

```sql
SELECT Shutter.Setup_Doctor()
```

## Each day

```text
Date, and reviewer:

Write attempts since yesterday:
  Any without a named approver, outside scope, or to the wrong receiver? (stop: 07)
  Any uncertain? Who is reading the receiver?
Cases awaiting approval, and how long each has waited:
  A plan left undecided moves to escalated after 24 hours, and tells nobody.
Blocked, escalated or failed cases:
  Each has a named owner? (03) If a case can't get one: stop.
Drafted emails: read before sending; identifiers as agreed?
Doctor: production_state, watched_namespaces (refused_72h, operations_unwatched, problems):
  A refused forward is a failure with no case. Find it in the Message Viewer.
Coverage: failures the engine shows against cases Shutter opened (below). Difference, and why:
Anything changed at the source or receiver? (06)
Site profile history: saved by whom, and was it agreed?
Minutes spent:
```

## Coverage

If your release has a census of failures against cases, use it, and read its "incomplete" and "ambiguous" counts as unknown, not as covered.

Otherwise count by hand: in the watched namespace's Message Viewer, filter on each receiver item and on status Error and Suspended, and compare with the cases opened in that period. This finds only what the engine itself failed. A message the engine completed and then lost appears on neither side, so **your count of cases is the number that reached Shutter, not the number of failed deliveries.**

## Each week

- Read a sample of closed cases, and the ones marked handled, against the receiver.
- Check that the on-call list and stop list are still true.
- Update the [hazard log](04-hazard-log.csv) with what you've learned.
