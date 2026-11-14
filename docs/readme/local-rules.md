# A trust's own stop rule: a worked example

> **Proposed design, not implemented.** No release of Shutter does this. The trust, its cases and every result below are synthetic and illustrative, not the output of Shutter's code or of a test.

[Back to the README](https://github.com/MxSalata/shutter#at-your-site-investigate-first-enable-recovery-deliberately)

## What exists today

- **The shipped file is the whole catalogue.** `SeedFromFile` in `src/Shutter/Catalogue/Entry.cls` removes every entry not in `knowledge/catalogue/catalogue.json`, so a trust has no supported way to add one.
- **No entry can single out a ward.** Entries name only the fixed conditions (`scripts/build-catalogue.py`; `Conditions` in `src/Shutter/Catalogue/Matcher.cls`), none of them a ward.
- **E19 answers alone.** A death on the message replaces every other match (`Match` in `Matcher.cls`).
- **A closure needs no approval.** A plan that writes nothing and passes the gate is verified and closed (`OnGateProposal` in `src/Shutter/Process/CaseWorkflow.cls`).
- **Approvals bind the catalogue's version.** A write planned under another version is refused at dispatch (`InvalidReason` in `src/Shutter/Store/Approval.cls`).

## The case

The synthetic trust's PAS sends an A02 transfer into WARD-ISO, a side-room isolation ward, to the receiver Downstream Out. The receiver times out and holds no receipt, and nothing later changed the encounter.

Today, read from the entries and not run, this case matches E2, "Not delivered, still current": a resend decided by site policy (`knowledge/catalogue/E2.md`). The shipped site profile asks a person to approve it (`policy` in `knowledge/site/profile.json`); with recovery enabled and the tier set to `automatic`, Site policy mode can resend it with nobody asked (`PolicyPath` in `CaseWorkflow.cls`).

### Why a trust needs this

[Author's note: ...]

## The proposed rule

```yaml
id: L1        # given by Shutter, never reused
kind: stop    # the only kind proposed
title: A failed transfer into the isolation ward
scope:
  receiver: [Downstream Out]
  source_system: [PAS]
  ward: [WARD-ISO]
pattern:
  event: transfer
  delivery: [failed, rejected, uncertain]
why: Infection control places every patient in this ward by hand, so a resend can't know the bed is right.
team: infection-control
instructions: Ring the ward's nurse in charge before anything is entered. Do not resend.
fixtures:
  - case: 1041
    expect: match
  - case: 1057
    expect: no_match
```

The pattern uses today's vocabulary only; every scope fact must hold. No field sets who decides or the outcome: the matcher would write a person and escalate itself. A matching rule would answer alone, as E19 does, showing the shipped entries it displaced.

## A matching fixture and a near miss

Illustrative only: no code computes this today.

| Fixture | The case | Expected | Illustrative result |
| --- | --- | --- | --- |
| Case 1041 | A02 from PAS to Downstream Out into WARD-ISO; the receiver timed out | match | L1 alone: a person decides. Without it: E2, resend |
| Case 1057 | The same, into WARD-B | no_match | L1 stays silent; E2 decides as today |

## Why no automatic resend, and no automatic closure

Here infection control decides who goes into the isolation ward, often by phone, before the PAS catches up. Shutter's evidence is the message, the receiver's state and its receipts; none of them says what infection control decided.

- **A resend** can pass every check the gate makes and still record a placement infection control has since changed.
- **A closure**, as E1 makes by policy when a later transfer was applied (`knowledge/catalogue/E1.md`), ends the case with nobody told, though the bed board showed the patient in the wrong place for a while. A wrong closure is as silent as a wrong write.

So the rule stops and tells a person.

## What the rule can and cannot promise

- **It can restrict automated writes and closures**, nothing more: no field asks for a resend or a closure. Delay is still a harm, and a rule drawn too broadly floods people with escalations.
- **Checked against these fixtures and sampled historical cases.** Shutter would run each fixture's stored evidence, and the last 200 stored cases, through the real matcher with and without the rule, sending nothing; a match and a near miss are required. A second person, not the author, approves the exact version and digest. This is not clinical validation: the trust's safety process decides whether the rule is right.
- **The gate is unchanged; the risk is not low.** Its existing checks would block every write on such a case (`OUTCOME_MISMATCH`, `ENTRY_NOT_NAMED_WRITE`, `PATTERN_NOT_MATCHED` in `src/Shutter/Operation/Gate.cls`), but it judges plans against the matcher's result. This change sits in the matcher and workflow, which decide what reaches the gate.
- **Suspension.** One approver may switch one rule off at once, with a reason, if it floods people. Until a second person approves resuming it, the protection is off and a warning shows.
- **Widening.** If an upgrade no longer knows a condition the rule names, or reads its fixture differently, that part is dropped and the rule flagged for review. It then matches more, never less: that keeps the brake on every case it caught, not the site's overall safety.
- **The activation window.** The version check runs at dispatch (`InvalidReason`), so a resend whose check passed just before activation can still go, as with any catalogue update today. A closure planned earlier would be planned again.
- **Words.** A rule's words can reach a model; an NHS number check catches obvious identifiers, not all patient information.
