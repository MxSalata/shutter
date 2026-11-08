# Pilot pack: start here

This pack helps a hospital's integration service owner decide whether Shutter may be piloted, how far, and when to stop. You can use it without reading the rest of the repository; your technical lead will need `docs/INSTALL.md` for the commands.

**This pack claims no compliance.** It does not show that Shutter is safe, and it meets no clinical safety, data protection or regulatory standard. It gives you templates and questions. The decisions, and the safety work, are yours.

It describes release 1.0.0. A later release's `CHANGELOG.md` may change a step. Some steps depend on features that may not be in your release: [the stage plan](02-stage-plan.md) says which, and what to do without them.

| File | Use it to |
| --- | --- |
| 00 (this page) | Record each decision |
| [01 Scope and exclusions](01-scope-and-exclusions.md) | Agree what the pilot covers |
| [02 Stage plan](02-stage-plan.md) | See each stage's way in and way out |
| [03 Roles and handover](03-roles-and-handover.md) | Name who owns what |
| [04 Hazard log](04-hazard-log.csv) | Start your own hazard log |
| [05 Data flow and retention](05-data-flow-and-retention.md) | Brief information governance |
| [06 Receiver acceptance](06-receiver-acceptance.md) | Test the receiving system's behaviour |
| [07 Stop and withdraw](07-stop-and-withdraw.md) | Stop, account for work, and remove Shutter |
| [08 Daily review](08-daily-review.md) | Run the pilot day to day |
| [09 Outcome report](09-outcome-report.md) | Report what happened |
| [10 Safety case template](10-safety-case-template.md) | Start your own safety case |

## The decision record

Copy this and fill in one for each stage. **A blank, "TBC" or a team name where a person is asked for means no: that stage does not start.**

```text
Pilot reference:
Stage this decision allows (0, 1, 2, 3 or 4):

Accountable service owner (person):
Clinical safety lead (person):
Integration technical lead (person):
Information governance lead (person):
Receiver owner (person) and supplier contact:
Receiving-team owner of unresolved work (person), and their deputy:
On-call team and hours covered:
Change approval reference:

Shutter version, commit and image digest if any:
IRIS build:
Mode: OBSERVATION / BOUNDED RECOVERY
Start:
Review date:
End date:

Included namespaces, productions, receiver items:
Included message families and triggers:
Excluded messages and patients:
Known unsupported routes:
Permitted external destinations:
Model use: OFF / separately approved (reference):
Email use and identification level:
Retention and deletion dates:

Who may stop (people, at least one for every covered hour):
Date each of them last did the stop drill (07):
Who may clear the stop:
Who may approve a recovery (people):
Success criteria agreed locally, with numbers (09):
What ends the pilot immediately, beyond the stop list in 07:
Residual hazards accepted, with hazard log references:

Signed decisions, with names and dates:
```

You set the success criteria; this pack gives no target percentages. Whatever you set, an unexplained write to the wrong patient, or a write nobody authorised, always stops the pilot ([07](07-stop-and-withdraw.md)).
