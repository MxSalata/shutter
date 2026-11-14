# How to integrate Shutter at your trust

This guide is for an NHS trust's integration team deciding whether and how to run Shutter beside their production; it describes Shutter 1.4.5.

Shutter opens a case for each failed HL7 delivery it can see in IRIS Interoperability. It can recover supported patient movements through a receiver's API; a plain message listener gets a case and a drafted email, never a resend from the case. On that recovery path the catalogue or IRIS AI Hub agents propose a plan, a deterministic gate decides whether anything may be written, a person releases it, and the result is verified in the receiver's receipt and history. In the profile Shutter ships, a person gives that release at every tier; only a tier you set to `automatic` goes without one. Since 1.4.0 an outage has a second path: at a receiver set up for it, one approval has the engine resend the messages its own records show never arrived, completed in the engine and not verified at the receiver.

My background is interoperability with 28 NHS hospitals. Many split their engine by purpose: order comms and the LIMS in a Pathology namespace, the DMS in Documents, the PAS feed in another. This guide puts Shutter beside those namespaces in the order a trust would do it. The commands are in [the install guide](../INSTALL.md), which I link to rather than repeat.

## Contents

- [Is this for you?](#is-this-for-you)
- [1. What Shutter needs, and what it touches](#1-what-shutter-needs-and-what-it-touches)
- [2. Install beside the production, without the demo](#2-install-beside-the-production-without-the-demo)
- [3. Shadow mode first](#3-shadow-mode-first)
- [4. Receivers, their kinds and tiers, and the site profile](#4-receivers-their-kinds-and-tiers-and-the-site-profile)
- [5. Before recovery: the conformance and stop tests](#5-before-recovery-the-conformance-and-stop-tests)
- [6. Enable recovery, as its own step](#6-enable-recovery-as-its-own-step)
- [7. Who approves what, the stop switch and the escalation email](#7-who-approves-what-the-stop-switch-and-the-escalation-email)
- [8. The budget and the model provider](#8-the-budget-and-the-model-provider)
- [9. Going live in stages, and rolling back](#9-going-live-in-stages-and-rolling-back)
- [10. Checklist](#10-checklist)

## Is this for you?

This is for an organisation on IRIS for Health with HL7 productions, an engineer with a terminal, and a clinical safety officer and an information governance lead before anything goes beyond a test instance.

Wait if:

- **You need orders, results or documents recovered from a case.** A case never resends one. The one resend they can get is an outage's, through the engine and under its own approval. It takes any message type that failed while the receiver was down, a document included, and reads no document's status ([section 4](#4-receivers-their-kinds-and-tiers-and-the-site-profile)).
- **You need a supported platform.** The live agents need an AI Hub early access build (2026.3.0AI.154.0 or 2027.1.0AI.109.0). On IRIS for Health Community 2026.2 the core loads without them, and no model is called.
- **You need a vendor.** Shutter is my MIT-licensed contest entry, with no warranty, and no supplier unless you arrange one.
- **Your engine and Shutter can't share an instance.** The onboarding helpers read only their own instance ([INSTALL 9.7](../INSTALL.md#9-onboarding-several-namespaces)).

**Clinical safety.** No regulatory classification has been made for Shutter, no standard has been applied to it, and it has no clinical safety case: in England, DCB0160 and DCB0129 have not been carried out for it. The [pilot pack](../pilot/00-decision-record.md) gives templates and claims no compliance, and [SAFETY.md](../SAFETY.md) lists the hazards with the code behind each (its body describes release 1.0.0).

## 1. What Shutter needs, and what it touches

**It needs:**

- **One namespace of its own,** with its database on storage the trust backs up. This is shape A, the recommended one: your productions keep their processes and routes, and a forwarder in each hands Shutter a failed message over HTTP. Shape B, Shutter's items inside one of your productions, exists ([INSTALL 4](../INSTALL.md#4-shape-b-shutters-items-inside-an-existing-production)); the pilot pack asks for shape A.
- **IRIS for Health with Interoperability:** 2026.3 or later with the `%AI` package for the whole package, or 2026.2 for the core alone.
- **A user who can reach `%SYS` and every namespace involved,** for the install and the onboarding. `%Admin_Manage` alone got Access Denied.
- **IPM in that namespace;** the repository carries `vendor/ipm/zpm-0.10.10.xml`.

First run the report in [INSTALL, "Before you install: will it work here?"](../INSTALL.md#before-you-install-will-it-work-here). It changes nothing but the two classes it loads.

**What it reads and what it may write, and where:**

| Where | Shutter reads | Shutter writes |
| --- | --- | --- |
| Its own namespace | Its own store | Cases, evidence, plans, approvals, the site profile, and a copy of each failed message: whole, except a document at a receiver with a document profile |
| The instance | The message purge task in `%SYS`, for a production review | Its resources, roles and web applications, the task "Shutter retention", two package mappings for each watched namespace, the user `shutter-fwd` |
| Each watched namespace | The production's settings, event log, message headers and the HL7 messages behind them: for a production review, the outage watch, and later messages about the patient before a write or a resend | At onboarding: the items `Shutter Forwarder` and `Ens.Alert` (your own alert item is renamed `Site Alerts` and still gets every alert first), a credential, and `AlertOnError` only if you ask. Afterwards: the forwarder's own messages and the alert intake's markers (`^Shutter.AlertIntake`). With `engine_resend` and an approval: a resend of the stored message, by the engine |
| A receiver with an API in its profile entry | Its state and history, receipts and capabilities | Only with recovery enabled: a dry run, then one conditional write, after the gate and an approval |
| A receiver with no API | Nothing: Shutter never connects to it | Nothing from a case |
| Outside the trust | | Case evidence, its identifiers replaced by tokens, and the questions people type, to the model provider, only when one is configured. Email through your mail server |

Say three things plainly to whoever owns the feed:

- **Onboarding edits the watched production, which then depends on Shutter's database.** With that database dismounted, a failing operation's job terminated with `<PROTECT>`, the site's alert consumer received nothing, and the production would not start. The apply also saves your production's class, so put that change in your source control.
- **Shutter keeps patient data.** Nothing purges its copies of failed messages on a non-demo install unless you set it, and any operator reads every watched namespace's cases ([data flow and retention](../pilot/05-data-flow-and-retention.md)).
- **Shutter hears only what the engine calls a failure.** A message accepted by a transport ACK and then lost downstream raises nothing ([what a watched namespace does not get](../INSTALL.md#10-what-a-watched-namespace-does-not-get)).

## 2. Install beside the production, without the demo

Do this on a test instance first, with a copy of your productions, their operations pointed at closed ports or a test listener, and no real patient data.

The steps: create the `SHUTTER` namespace and load IPM in it ([INSTALL 3.1](../INSTALL.md#3-shape-a-shutter-in-its-own-namespace)); install with `-Ddemo=0`, in that namespace only; check `GET /api/shutter/health` and `SELECT Shutter.Setup_Doctor()`; then make your operators and approvers ([INSTALL 5](../INSTALL.md#5-the-steps-for-the-integration-team), steps 2, 3 and 10).

**`-Ddemo=0` is not optional.** The default installs the demo: demo users with a documented password, the demo receiver, the scenario player and a namespace-wide message purge. With `-Ddemo=0` there are no demo users, no demo receiver and no credential; the feed, records and scenario items are switched off; and any `automatic` in the policy it starts from is turned to `approval`, so every write waits for a person until a profile you save says otherwise. A load in a namespace running another production is refused. The registry's published version can lag the repository: for an exact version, load a clone of that tag by path.

**A non-demo install makes no users.** An operator holds `Shutter_Operator`. An approver holds `Shutter_Approver` and must also be a member of the Workflow role "Shutter Approvers", or an approval answers 403. These are the calls the installer itself uses for the demo's approver, with a user of your own:

```objectscript
Set $NAMESPACE="%SYS"
Set sc=##class(Security.Users).Create("appr1","Shutter_Approver","<password>","An approver","SHUTTER","","",0,1) Write $SYSTEM.Status.GetErrorText(sc),!
Set $NAMESPACE="SHUTTER"
Set sc=##class(EnsLib.Workflow.UserDefinition).CreateUser("appr1","An approver") Write $SYSTEM.Status.GetErrorText(sc),!
Set sc=##class(EnsLib.Workflow.RoleDefinition).AddUserToRole("Shutter Approvers","appr1",1,"Approver") Write $SYSTEM.Status.GetErrorText(sc),!
```

Each line prints nothing when it worked. Then sign in as each role at `/shutter/index.html` and check that the operator can't approve. Leave the provider key out for now ([section 8](#8-the-budget-and-the-model-provider)).

## 3. Shadow mode first

**A new non-demo install starts in shadow mode,** and so does an upgrade whose stored profile doesn't say. Only an explicit `"recovery": {"mode": "enabled"}` in the site profile enables recovery; no environment variable does. Until then a banner on every page reads "Shadow mode.".

| In shadow mode Shutter does | It does not |
| --- | --- |
| Open a case for each failure it hears of, collect the evidence and investigate | Send a rehearsal (a dry run) to a receiver |
| Read a receiver's API, where the profile describes one | Send a recovery write |
| Run the gate and record what it would have proposed | Send a blind-resend preview or an outage's resend |
| Call the model, if a provider is configured | Send an escalation email or a reminder, unless the profile says `"notifications": {"shadow_delivery": "enabled"}`. An outage email, where you have added Outage Mailer, is not held: it names no patient |
| Let a person draft an escalation and close a case by hand | Take an approval: a case's, an incident's or an outage's answers 409 `recovery_shadow` |

The hospital's ordinary feed goes on either way. A case whose plan passed the proposal gate and would have written ends escalated, headed "Shadow observation: nothing sent." At a receiver with no API the gate stops the plan before that, and the case says why. **Shadow mode is not "no data leaves":** with a provider key, case evidence still goes to the model.

### Connect the first namespace

In a sandbox first, not between a live production's alerts and their consumer. From the apply on, the watched production depends on Shutter's database: with it dismounted, the production would not start ([section 1](#1-what-shutter-needs-and-what-it-touches)). Each step is a call in Shutter's namespace; the app's Watched namespaces page, under Settings and costs, runs the same helpers ([INSTALL 9.1 to 9.5](../INSTALL.md#9-onboarding-several-namespaces)).

| Step | Call | What to know |
| --- | --- | --- |
| Read the plan | `SELECT Shutter.Setup_OnboardPlan('PATHOLOGY')` | It changes nothing. Read `actions`, `todo`, `warnings` and each operation's `proves` |
| Apply it | `SELECT Shutter.Setup_OnboardApply('PATHOLOGY', '{"alert_on_error": true}')` | It stops no production. Without `AlertOnError` on a stock HL7 operation, no real failure there opens a case |
| Give the forwarder its sign-in | `Do ##class(Shutter.Setup).OnboardCredential("PATHOLOGY")`, in a terminal | No password passes through a statement |
| Send a test failure | `SELECT Shutter.Setup_OnboardTest('PATHOLOGY')` | It proves the address, the password and the role, not the alert path |

Then fail one real test delivery, and confirm that a case opens for the right message and receiver and that your own alert consumer still received the alert. From then on, read `watched_namespaces` in the Doctor's report: `problems`, `refused_72h`, `operations_unwatched`.

### What observation tells you

- **Each case, read daily.** As shipped, nothing in Shutter tells a person a case needs them (reminders are off until the profile turns them on, and held in shadow mode), so the [daily review](../pilot/08-daily-review.md) is a control. Its first query, every write attempt, must return no rows at this stage.
- **The reports.** The shadow report (`GET /api/shutter/shadow-observations`, or the CSV link on the Settings and costs page) counts the cases that reached Shutter, not all failed deliveries, and authorises nothing. A production review reads the watched production and changes nothing ([INSTALL 3.6](../INSTALL.md#3-shape-a-shutter-in-its-own-namespace)). The failure census is off unless the profile turns it on ([CONTRACTS 19](../CONTRACTS.md#19-the-failure-coverage-census-v150)).
- **Each receiver.** Ask its supplier what a positive ACK means (INSTALL 9.9). And mind `FailureTimeout` -1, the stock TCP operation's default: a case opens on the first failure, the engine delivers when the system returns, and no alert says so. Read the message trace before anyone re-enters an order by hand.

Don't say "would have recovered" from observation: a resend that never went tested nothing at the receiver.

## 4. Receivers, their kinds and tiers, and the site profile

The site profile is the site's written policy: an entry for each receiver, and the site's own answers. Onboarding drafts an entry for each stock HL7 operation: tier 3, no API, every feature false, marked `draft`. Nothing can be resent to a draft. Review each on the Site profile page and remove `draft` when you save.

**The kind** (`category`) says what matters to the system. An entry with none reads as `current_state`, so state it.

| Kind | Examples | What a failed message becomes |
| --- | --- | --- |
| `current_state` | A bed manager, a ward whiteboard, portering | With an API, an ADT case that can end in a resend. A failure a later event has overtaken closes with no write |
| `history_of_record` | A PAS, an electronic patient record, a clinical data warehouse | The same, except that an overtaken failure asks for a correction by hand, with the steps on the case |
| `orders_results` | Order communications, a laboratory system | A case with its findings for a person, and no resend from the case. With a `watch` block and `engine_resend`, an outage's undelivered messages can be resent by the engine after one approval ([INSTALL 11](../INSTALL.md#11-a-receivers-outages-v110)) |

The outage resend is not only for orders and results: an entry of either other kind can say `engine_resend` too, and there it also needs `ack_level` `application`.

**The tier** is how sensitive the receiver is: 1 information, 2 operations, 3 clinical safety. It picks the row of the approval table: the profile's `policy` says, for each tier and each shape of failure (a single failed message, an ordered chain, an interleaved chain), one of `automatic`, `approval`, `per_chain` or `board`. As shipped, every tier asks a person for a single failure and an ordered chain, and sends an interleaved one to the board, whose plan a person then approves. Only a tier you set to `automatic`, with a receiver at that tier given an API, lets a case write with no person. Keep the policy as shipped until your clinical safety officer agrees otherwise.

**An API, or none.** A case resends only to a receiver that offers conditional writes, receipts, a readable history and dry runs, through the four endpoints of [the receiver contract](../readme/receiver-contract.md). For any other receiver leave `api` out and its features false. A receiver you give an API also needs a connector item in Shutter's production and a credential in Shutter's namespace (INSTALL 9.6), and in this version every such receiver must answer on the same host and port.

**What a case's recovery sends** is one mapped ADT operation (an admission, transfer, discharge or update), not the HL7 message: fixed fields and no demographics. So resending a failed A08 puts none of its changes right: the write is an update with no ward, bed or demographics, and only the receiver record's version moves.

**The site's own answers** to settle before the first real case: teams and their mailboxes, with `mail.allowed_domains` set to your domains in place of the shipped `example.nhs.uk` (with none set, no email can go), and the feed's time zone, since it changes every operation key.

### Who sets it, and who approves it

- **The integration engineer prepares it.** Onboarding writes the drafts, and any operator can work through the questionnaire; without the right to change the site only Save is locked ("Only an approver saves here"). The receiver's owner says what its ACKs and receipts mean, and the clinical safety officer agrees the tier table.
- **An approver saves it,** through **Review and save…**, which lists each change and marks any that takes a person's approval away. Saving needs `Shutter_Configure`, which the approver role holds. Each saved version is kept with who saved it, and a save voids every approval not yet dispatched.
- **An approver can change the policy they approve under.** Keeping a tier on `approval` is a setting an approver can undo, not a control over approvers. To keep the two apart, give your approvers a role of your own that holds `Shutter_Approve` and not `Shutter_Configure`, since an install restores Shutter's own roles. That separates the rights. It puts no second signature on a profile change: whoever holds `Shutter_Configure` saves the policy alone. Such an approver can neither save the profile nor clear a stop, which needs both rights, so keep someone who holds both.

## 5. Before recovery: the conformance and stop tests

Both happen in the laboratory: a test instance, the receiver's test endpoint, synthetic patients.

### The receiver conformance kit

`scripts/receiver-conformance.py` is run by an interface engineer and the receiver's supplier against a declared test endpoint ([receiver-conformance.md](../receiver-conformance.md)). It needs Python 3 and nothing else.

- **What it answers:** which parts of the recovery contract this endpoint showed, in 26 checks, of which 25 are required.
- **What it refuses:** anything but `environment: TEST`, a redirect, and any identity it did not declare. A run declares at least 60 synthetic encounters and 40 beds, and deletes nothing.
- **What it is not:** it does not certify a supplier, does not enable recovery and changes nothing in Shutter.
- **Conforming isn't the same as being safe to recover to.** Run it as well as the [receiver acceptance](../pilot/06-receiver-acceptance.md) page: a "no" or "unknown" on a required line there means no recovery to this receiver.

Two settings follow. Set `UncertainSettleSeconds` on the Verifier item (60 by default) above the receiver's worst time to commit. And where the engine's own operation to this receiver is a class of your own, or reaches it through a business process, keep its `FailureTimeout` at 0: only at a stock HL7 TCP operation does Shutter hold its write while the engine is still trying.

### The stop drill

Every person who may call a stop does this with their own sign-in, on the laboratory instance with recovery enabled there:

1. With a case waiting for approval, press **Stop Shutter recovery** on the Settings and costs page, with a reason.
2. See the banner on every page, and that an approval now answers 409 `recovery_stopped`, while the feed goes on.
3. Restart the production: the stop is still set.
4. As an approver, clear it with a reason. Clearing enables nothing and releases nothing: the earlier plan is refused (`plan_predates_control`) until it is rejected and reinvestigated.

The repository plays the same on a throwaway instance, counting requests on the wire (`tests/e2e/shadow_pilot_check.py`, and `tests/e2e/outage_stop_check.py` for an outage's resend). Your drill shows that your people can do it.

## 6. Enable recovery, as its own step

Enabling recovery is not part of the install, and observation does not lead to it by itself. It is a separate signed decision, taken when all of these are true:

- the tests of section 5 are complete for the one receiver in scope, and someone who can stop is on call whenever recovery is on;
- a named person in the receiving team, and a deputy, accept unresolved work: Shutter can stop, but it can't correct a record;
- every tier's policy still asks a person, and `incident.threshold` (5 as shipped) is raised far above your feed's volume, so one decision covers one case;
- approvers are trained to read the evidence, not only the plan.

**How.** An approver answers question 14 on the Site profile page, "May Shutter attempt recovery here, within its gate and the policy above?", by switching **Enable recovery** on, and saves. Through the API it is `"recovery": {"mode": "enabled"}` in the profile you `PUT` to `/api/shutter/site-profile`.

**The switch is site-wide; the scope is the profile.** A case can still write only to a receiver whose entry has an API. So bounded recovery means one receiver given its API, and every other entry left without one. The outage resend has its own scope: with recovery enabled, any watched entry that says `engine_resend` can have an outage's messages resent after an approval, API or none. Leave `engine_resend` out of every entry outside the agreed scope.

**What enabling does not do:**

- **It releases no plan made before it.** Each stop, clear and change of mode raises a floor under the plans, and a plan at or below it is refused (`plan_predates_control`). Reject it and reinvestigate: the case takes fresh evidence and a new plan.
- **It sends no escalation held in shadow mode.** An escalation a person sent in shadow mode reads Not sent, and enabling recovery does not send it; a person can send it again. Reminders differ: if the profile has turned them on, the first reminder run after enabling sends what is due.
- **It resends nothing by itself.** An outage's offered messages still wait for their own approval.

Going back to shadow mode is the same save the other way. An upgrade from a version before shadow mode also comes up in shadow ([INSTALL 8](../INSTALL.md#8-upgrading-in-place)).

## 7. Who approves what, the stop switch and the escalation email

| Who | Holds | May |
| --- | --- | --- |
| Operator | `Shutter_Operator` | Read every case; reinvestigate; draft and send an escalation email; mark a case handled, unless the profile says an approver must; stop Shutter recovery |
| Approver | `Shutter_Approver`, and membership of the Workflow role "Shutter Approvers" | All of that, and: approve or reject a plan, an incident's release and an outage's resend; save the site profile; clear a stop; abandon a stuck case |
| Forwarder (`shutter-fwd`) | `Shutter_Forwarder` | Open a case, for any receiver, and nothing else. Its password does not expire: give it an integration credential's care |
| A site administrator | Interoperability rights of your own | Disable an item or stop a production. Shutter's roles aren't given this |

**An approval** binds one plan at one receiver version, lasts an hour, and is void once the plan, the material evidence, the receiver's version, the site profile, the catalogue or the gate's policy moves. An approver who decides in the Workflow inbox pastes the plan digest into the task's `PlanDigest` field; without it the case blocks.

**A plan nobody decides** waits 24 hours, then its task is cancelled and the case moves to escalated. Nothing tells anyone unless you turn the reminders on, and Shutter has no field for who owns a case, so keep your own list ([roles and handover](../pilot/03-roles-and-handover.md)).

### The stop switch

**Stop Shutter recovery**, on the Settings and costs page, is for any operator or approver, with a reason.

| | |
| --- | --- |
| What it stops | From the moment it commits: every rehearsal, recovery write, blind-resend preview and outage resend that Shutter itself starts. An outage's run halts before its next message |
| What it doesn't | The hospital's feed and the engine's own retries, other people's writes, reads of a receiver, and email. A call admitted before the stop may still complete; it is listed as outstanding |
| How long | Until a person clears it. It outlives a restart and a reinstall, and a recovery call that a restart cut off sets it too |
| Clearing | An approver, with a reason. It enables nothing and releases no earlier plan |

A stop undoes nothing already written. When to call one, and what to do next, is in [stop and withdraw](../pilot/07-stop-and-withdraw.md).

### The escalation email

A blocked, escalated or failed case can be handed to the team that corrects the system by hand. The draft is built from the stored case, never by a model ([CONTRACTS 10](../CONTRACTS.md#10-escalation-by-email-v111)).

- **The patient is identified by the hospital number, the NHS number and the date of birth only:** no name, address or note text. The failure text goes as the receiver or the engine wrote it, so it may echo a name: read it before sending.
- **A person sends it.** Someone presses **Escalate to** the team on the case page, reviews the draft and sends it; the send is bound to the digest of the text they read. Every address must lie in `mail.allowed_domains`.
- **With no mail server it is a file, not an email.** It is written as an `.eml` under `<mgr>/shutter/out/mail` and its line reads "Saved, not delivered": nobody was emailed. Set the `Escalation Mail` operation's SMTP server first.
- **Its text is removed** 90 days after the case closed, by default. An NHS number and a date of birth by email is still a decision for your information governance lead.

## 8. The budget and the model provider

**No key, no model.** An instance never given a key has no provider. A watched production's failures run in Site policy mode by default: the catalogue proposes what it knows and a person approves it, a case it gives to the board or a person escalates with no plan, and a failure it doesn't know takes the rules path, where the gate blocks it (`NEW_PATTERN`). A provider once configured stays until it is removed: read the Doctor's `provider` line.

| Setting | Where | What it does |
| --- | --- | --- |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `SHUTTER_PROVIDER`, `SHUTTER_MODEL` | The environment, at install and at every start of `Shutter.Production` | Configure the provider and the model: Anthropic (`claude-opus-5-5` by default) or OpenAI (`gpt-4.1`), one at a time, and Anthropic when both keys are set. A start writes the provider again when none is configured, or the key or the provider has changed. Only Anthropic is measured ([INSTALL, section 2](../INSTALL.md#2-what-an-install-creates)) |
| `SELECT Shutter.Setup_ConfigureProvider(?, ?)` | SQL, the key bound as a parameter | The same by hand. The key goes into the IRIS wallet and is never printed |
| `SELECT Shutter.Setup_ClearProvider()` | SQL | Removes the provider and the key. Take the key out of the environment too, or the production's next start configures it again |
| `Model`, `ProviderConfig` | An agent item's settings | That item's model, or its provider configuration |
| `SHUTTER_DAILY_BUDGET_USD` | The environment, applied at every start of the production | A cap on a day's live runs, 00:00 to 00:00 UTC. Never set, or 0: no cap. Left empty later, the cap already stored stays. Runs on a model with no price, OpenAI's included, are not counted |
| `SHUTTER_JUDGE_BUDGET_USD` | The same | Each user's share of that day |
| `SHUTTER_PROVIDER_TIMEOUT_SECONDS` | The same | The bound on one model call: 10 to 600 seconds, 120 by default |

**Set the cap when you add a key, or no cap applies.** At the cap a run is refused `budget_exhausted`: a case the catalogue gives to the board or a person goes to a person with no plan, and others take the rules path, where the gate still judges the resend. Runs in flight can finish past it. Operators and approvers both hold `Shutter_LiveAgents`, the right to spend it.

**What a run cost, where it was measured.** On the twelve held-out cases rerun on release 1.4.3 (36 runs each for the board and the single investigator, every agent on `claude-opus-5-5`; a regression rerun, not a new held-out test), a board run cost 0.480 USD against the single investigator's 0.127, about 3.8 times as much by those two figures, and both scored a strict mean loss of 0.167, the single investigator's as settled on that page (0.667 by the unchanged grader; the page gives both). The board is not shown to decide better than one agent: what it adds is three findings from separate views and a record of disagreement for the approver ([the fair test](../readme/fair-test.md), "Release 1.4.3: all 12 cases rerun"). All of it is synthetic.

**What leaves, with a key.** The case's known identifiers become tokens, demographics are dropped, and notes go as flags unless the profile turns free text on ([CONTRACTS 9](../CONTRACTS.md#9-what-leaves-iris-for-a-model-v111)). An identifier that appears only in a receiver's or the engine's free text can still reach the model. So name the provider, its region and its terms in your data protection impact assessment first. Another provider can be set by hand; its runs are unpriced and outside the day's budget ([another-provider.md](../readme/another-provider.md)).

## 9. Going live in stages, and rolling back

Move up one stage at a time, each with a signed [decision record](../pilot/00-decision-record.md). Nothing moves on by itself. The stages are the pilot pack's and cover a case's recovery through a receiver's API. An outage's engine resend is not in them: before any entry says `engine_resend`, agree its own scope, what the receiver's ACK and its duplicate answer mean, what is done about a send that reads unknown, and a stop drill during a run.

| Stage | What is on | Way out |
| --- | --- | --- |
| 0. Scope and authority | Nothing installed | Named owners; clinical safety, information governance and change owners agree a laboratory exercise |
| 1. Disposable laboratory | A test instance, a test receiver, synthetic messages: each role, known failures, the conformance kit, the stop drill, withdrawal | A recorded result for each test, and no unexplained receiver write |
| 2. Connected observation | Shadow mode; the production onboarded; no receiver with an API; no model unless separately approved | You know what reaches Shutter and what doesn't, and no recovery attempt is on record |
| 3. Bounded recovery | Recovery enabled; one receiver with an API; named approvers; one case at a time | Every attempt accounted for, and scope unchanged without a new decision |
| 4. Decide | | Continue under a new decision, return to observation, or withdraw |

**The pilot pack describes release 1.0.0.** What its [stage plan](../pilot/02-stage-plan.md) says a later release may add is in 1.4.5 (shadow mode, the stop switch, the failure census, the conformance kit and the full uninstall), except an acceptance runner: I found none in the tree, so replay known failures by hand. Two of its lines have moved on: a non-demo install no longer writes at tiers 1 and 2 with no person (read `policy` after an upgrade all the same), and a forward is tried again while nobody answers, for 300 seconds as onboarding sets it.

### Rolling back

Smallest first. The first three rows change only Shutter, and the ordinary feed goes on as it was. The last two also update each watched production, without stopping it: test a delivery and an alert there afterwards.

| To undo | Do | It leaves |
| --- | --- | --- |
| Recovery, at once | Stop Shutter recovery | The cases, open as they were. An admitted call may complete |
| Recovery, as a decision | An approver saves the profile with recovery off | Shadow mode. Earlier plans are void |
| One receiver's recovery | An approver takes `api` out of its entry, with its features false, and sets `engine_resend` false where the entry has it | Its cases stop for a person, and approvals not yet dispatched are void. An outage's set there stops being approvable when Shutter next reads it, within about a minute; a resend run already approved is halted by the stop above, not by this |
| One watched namespace | `SELECT Shutter.Setup_OnboardRemove('<NAMESPACE>')`; purge under your own rules; then again with `{"unmap": true, "credential": true}` (INSTALL 9.7) | Shutter's cases and the imported schemas. Send a test alert and check your own consumer receives it |
| Shutter itself | `SELECT Shutter_Util.Uninstall_Plan()`, which changes nothing, then `zpm "uninstall iris-shutter"` ([INSTALL 2](../INSTALL.md#2-what-an-install-creates)) | Nothing of Shutter's, so export what you must keep first. The namespace and its database stay, as do the package manager and the users you made, with Shutter's roles taken off: remove or disable them yourself |

**Rolling back Shutter is not a clinical rollback.** A record already changed needs the receiver's own correction procedure. Don't restore an old database just to undo Shutter's state.

**What has not been tried.** Every receiver behaviour measured is a demo receiver's, a stub's or a made-up listener's, and failover, mirrors and restoring from a backup aren't tested. Your own tests on your own receiver are the evidence that counts.

## 10. Checklist

**Install**

- [ ] Named owners, a decision record for the stage, and a pre-install report with nothing blocked.
- [ ] A test instance first, with a copy of your productions and synthetic data only.
- [ ] Shutter's own namespace, on backed-up storage, installed with `-Ddemo=0`, and no provider key.
- [ ] Operators and approvers made, approvers in the Workflow role, each role tried with a real sign-in.

**Shadow mode**

- [ ] The banner reads "Shadow mode.".
- [ ] Before real patient data reaches Shutter: retention and deletion agreed and set, who may read every watched namespace's cases agreed, and the backup and restore of Shutter's database agreed.
- [ ] The plan read, then applied; the credential stored; the test failure answers a case.
- [ ] A real test failure opens a case and still reaches your own alert consumer.
- [ ] The daily review is running, and its write-attempt query returns no rows.

**The site profile**

- [ ] Every receiver has its kind, tier and team, with `draft` removed, and an API only where it has one.
- [ ] Your own mail domains, a mail server, and the feed's time zone.
- [ ] The policy as shipped, saved by an approver.

**Before recovery**

- [ ] The conformance kit's required checks all pass, and the receiver's owner has signed the acceptance page.
- [ ] The stop drill done by every person on the stop list.
- [ ] A named receiving-team owner and deputy.
- [ ] `UncertainSettleSeconds`, `FailureTimeout` and `incident.threshold` set as sections 5 and 6 say.
- [ ] A separate signed decision for bounded recovery.

**Enabling, and after**

- [ ] An approver saves recovery enabled; plans from before are rejected and reinvestigated.
- [ ] One receiver with an API; a person checks the receiver after each write.
- [ ] If a key goes in: the assessment done first, and the daily budget set.
- [ ] Withdrawal rehearsed.
