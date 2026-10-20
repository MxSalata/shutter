# Changelog

Versions follow `major.minor.patch`: a minor release for new features, a patch release for fixes and dependency
updates. The version in both `module.xml` files (the one the package manager publishes) is always the version of the
GitHub tag on the same commit; `scripts/check-versions.py` checks every place the version is written.

## Unreleased

What the first release holds: Shutter, supervised recovery of failed deliveries in an InterSystems IRIS
Interoperability production, with a board of IRIS AI Hub agents.

- **A failed delivery is a case, not a retry.** When a delivery from an HL7 ADT feed fails, Shutter opens a case,
  gathers the evidence (the message, the receiver's state, receipt and history) and decides what should happen:
  resend it, reconcile it because it already arrived, leave it because a later event superseded it, or escalate it.
- **A board of AI Hub agents** (the `iris-shutter-aihub` module): three specialists review a case in parallel and a
  coordinator proposes one plan, each agent a business operation in `Shutter.Production`, with their tools, schemas
  and knowledge bases. Without an API key or the AI Hub build, the agents replay recorded runs.
- **A deterministic gate** checks every plan (identity, conformance, intent, ordering, state transition, effect,
  authorization, concurrency, evidence freshness, the receiver's capabilities and the catalogue); an unknown blocks
  a write as surely as a failed check.
- **A person approves the exact action**, bound to the plan's digest, the evidence, the gate's policy and the
  receiver's version, or the site's policy does for the cases the scenario catalogue knows. Shutter then makes one
  conditional write and verifies it in the receiver's own history.
- **Incidents:** many failures to one receiver become chains per encounter, released in order under one approval,
  stopping at the first surprise.
- **The site profile:** the induction questions that decide what goes without a person, who approves what, the teams
  an escalation goes to, the feed's time zone and whether note text may reach the model, with every version kept.
- **Only what is needed reaches the model:** identifiers become per-case tokens, names, dates of birth and addresses
  are dropped, and CI fails when anything personal from the fixtures reaches a recording.
- **Merges** are withheld by default (the site profile can allow them for a receiver that takes them), and **cancels**
  the receiver cannot take are withheld; both are escalated, with an email drafted for the team the site profile names.
- **The web application:** scenarios, cases, incidents, the board's findings, the gate, approvals, verification, the
  site profile, the library, and costs and tokens per agent run; served by IRIS, and as an online demo of recorded
  runs.
- **Scenarios** S1 to S20 (S14 aside) that play each kind of failure end to end on the demo downstream system, a
  demo hospital production in its own namespace that Shutter watches (S19), and a nurse's move entered by hand in the
  downstream system while a resend waits for approval: the approval is bound to the receiver's version, so the resend
  never writes over her entry (S20).
- **Install:** the `iris-shutter` and `iris-shutter-aihub` IPM modules, a Dockerfile and `docker compose up`, and a
  site install into an existing production.

## 1.0.0

To be dated at release: the entries above move here when 1.0.0 is tagged and released on Open Exchange.
