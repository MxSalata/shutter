# Changelog

Versions follow `major.minor.patch`: a minor release for new features, a patch release for fixes and dependency
updates. The version in both `module.xml` files (the one the package manager publishes) is always the version of the
GitHub tag on the same commit; `scripts/check-versions.py` checks every place the version is written.

## 1.4.6 (14 November 2026)

Each case says what the agents contributed, the online demo shows its pathology work, the first screen leads to a short route, and the site profile can ask Shutter about its key answers.

- **What the agents contributed, on the case.** The decision receipt's first fact says who proposed the plan (the
  coordinator agent, one agent, the rules or the site's policy), read from the plan's own origin and the case's runs, and
  names no agent for a plan no agent's run made. "Why" opens the plan's recorded reason word for word, what it cites as
  links to the Evidence tab, how the specialists stood to it and each agent's finding. On the board, "Cited N evidence
  sections" and "Dissent kept" open from their own lines; in the trial every run reads "Browser recording".
- **Pathology on the online demo.** Two optional paths on the Scenarios page, counted apart from the 36 scenarios. P1
  sends an ORU^R01 result the demo's results system refuses (AE, an unknown test code): its case goes to a person with
  the OBX and the receiver's words, and offers no resend. P2 takes the results system down while three results fail,
  brings it back, and the outage of Lab Results Out offers the three; one approval with the receiver check has the engine
  send each again unchanged. P2 waits while its last outage is open, and no start or reset changes an outage (CONTRACTS
  1.62).
- **The short route from the first screen.** The trial's welcome offers Start with S2, which opens S2's card in Board
  mode with Run focused and presses nothing. The quick tour follows S2, then S3, then S8, with S20 optional. A Run just
  pressed shows as starting at once, so the last run's "Open its case" is never offered for the new run. A replayed case
  on IRIS says "Recorded replay: no new inference", and S8's board case says again that the board sent nothing.
- **Ask Shutter about this, on the site profile.** Beside a receiver's kind and tier and beside enabling recovery, it
  explains that answer with the live Explain agent on IRIS AI Hub, or shows its written explanation where no live answer
  is given; asking changes nothing in the profile. A page answer names the agent and links its run's message.
- **The review on a phone.** The review of a plan shows what releasing it is expected to leave, with its notes, before
  the controls come into view; the binding line names the encounter; and from the confirming press until the answer the
  review can't be closed. The request is unchanged.
- **Hide resolved on Cases.** The switch now leaves out the resolved cases only, since a blocked, an escalated and a
  failed case still need a person. `GET /cases` takes `resolved=0`, in the query itself; `open=1` keeps its 1.4.5
  meaning. The count of cases that need a person says "at most" when more than 100 failed (CONTRACTS 1.60).
- **Figures by cohort.** Every evaluation figure on the sign-in page, Scenarios and Evaluation names its cohort and
  release, the 1.4.3 regression rerun first; the Evaluation page adds F03 as one case under the same gate, with nothing
  written in any run.
- **Budget admission.** A live run is admitted only when the recorded spend, the reservations and this run's estimate
  fit the day's cap and the person's share, checked and reserved in one locked step; the SQL diagnostic `TestRun` goes
  through the same admission and its cost is counted. A share that can't take the next run says so.
- **OpenAI as a second provider, in the installer.** The install reads `OPENAI_API_KEY` and `SHUTTER_PROVIDER` beside
  `ANTHROPIC_API_KEY` and `SHUTTER_MODEL`: the provider named, else the one whose key is set, Anthropic when both are.
  Not yet measured on OpenAI, whose runs have no price, so the budgets do not count them (CONTRACTS 1.61).
- **Pull requests are checked before they merge.** The repository checks, the web application, the browser suite, the
  recordings and the IRIS shards run on every pull request, with no secret and no write.
- **Docs.** Two guides, How Shutter works and How to integrate Shutter at your trust; a worked example of a proposed
  local stop rule, labelled as not implemented; the README leads with what the agents decide, what permits a write,
  what the test found and why it was built, with a two-minute video; screenshots retaken with 1.4.5's names.
- **Tests.** The gate's unit tests pin how a snapshot with no catalogue decision is read, and the tour keeps its Cases
  steps when the Cases switch is used.

## 1.4.5 (13 November 2026)

A case leads with what it proposes and opens its review in one press, the Cases list can hide what is closed, and the
Scenarios page says how each run executes.

- **The plan says its action first.** A waiting case's action button, its copy in the tab bar and "What needs you now"
  open the review of the exact plan from any tab, named for what it does ("Approve the resend"). The review leads with
  the plan's action in plain words, read from the plan's own operation, says what releasing it is expected to leave, and
  keeps the plan digest, the case version and Cancel in view at the confirming press. Opening, switching and cancelling
  send nothing; the confirming press sends the digest and version the review opened on, as before.
- **Hide closed on Cases.** `GET /cases` takes `open=1`, which leaves out resolved, blocked, escalated and failed cases in
  the query itself, so the total and the pages count the same rows. The Cases page's Hide closed switch sends it and
  keeps it in the address. The closed-outcome tiles say when they counted only the 100 newest cases, and the Failed tile
  says "at most" when more failed.
- **An empty Cases list fits the install.** The words come from the trial flag, the health report and the caller's
  rights, never from a name: the trial and a demo offer a scenario, a site says what it watches and points at Health, and
  a site that put Shutter's items in its own production says that a case opens when its HL7 process or a forwarder
  reports a failed delivery. CONTRACTS 1.59 says all of this.
- **The Source message link opens the message.** Every link to the Management Portal's message page names
  `Ens.MessageHeader` before the header's id; the page answered ERROR #5809 without it. The agent runs' `messageLink` in
  `GET /cases/{id}/runs` comes from one class method, and a link from a recording gains the class before it is shown.
- **Scenarios: each run mode in its own card.** Board, Single investigator and Rules only show their approved words
  without a choice or a hover, how a run executes here is said apart from who proposes, and a finished run leads to its
  own case. Home starts a short route on S2's card in Board mode, then S3 and S8, with S20 optional.
- **Provenance in plain words.** The trial's runs say "Browser recording: no new inference", a replay on IRIS says it
  is recorded, and a run is called live only when its own case's runs show a model call. S8's "every check passed" lines
  say that Rules only is exempted there on purpose and that the gate holds the resend on a real case.
- **Site profile.** The questions line up, the folds share one style, and the Orders and results card says what a case
  gets and how the outage resend works.
- **Repository checks on every push.** The credentials scan, the version check, the ASCII check of both module files
  and the dash check of the files and pushed commit messages run in a workflow of their own,
  `.github/workflows/repository-checks.yml`, on every push to main (documentation-only pushes included) and on pull
  requests; CI calls the same workflow and still waits for it.
- **Docs.** The README puts S8 side by side under the opening, one block for judges and Try it after the results, and
  gives each figure its cases, runs and release; it ends with a note on how Shutter was developed. The install guide
  makes enabling recovery its own step after the conformance and stop tests; the safety page, first steps, limits and the
  AI Hub page say which email shadow mode holds and that runs started together can pass a spending cap a little.

## 1.4.4 (11 November 2026)

Anyone on the online demo can play the scenarios now, from their recordings.

- **The public demo's account runs the scenarios, replayed.** Signed in as `demo`, **Run** on Scenarios is on. A run
  started by someone without the live agents plays every agent of its cases from the recordings: no model is called and
  nothing counts against the day's budget or anyone's share, even on an instance whose board answers live. The judges'
  runs stay live, as in 1.4.3, and a reopening or a convened board goes by its own requester's right.
- **A replayed run says so.** The case carries "Replayed: this scenario run was started by a sign-in without the live
  agents..." on its trail from its opening, its agent runs show as recorded replays costing nothing, and the run banner
  says its agents answer from their recordings. `POST /scenarios/{id}/run` and the run record carry `replay`.
- **The single investigator, never recorded, is refused to a replayed run.** Such a run in that mode is 409
  `not_recorded`, before anything is reset; the Scenarios page greys the mode out for the demo's account with "No recording
  to replay", as the trial does.
- **Reset stays locked.** The demo's account still can't reset the shared demo or purge its store, and the greyed-out
  Reset says why without naming a role the user menu shows. The hourly reset cleans up after visitors' runs.
- **On an upgrade,** the install gives the role `Shutter_Demo` the resource `Shutter_Scenarios`, and nothing else. The
  trial's online demo role runs scenarios too. CONTRACTS 1.58 says all of this.

## 1.4.3 (10 November 2026)

The judges play the scenarios on the online demo, and the words for orders and results say what 1.4.x does.

- **The judges' account runs the scenarios, live.** A judge signed in to the online demo can press **Run** on Scenarios,
  S8 with the real agents included, one run at a time, under the demo's caps and the judge's own share of the day's model
  budget: a run's cases now carry who started it, so their live agent runs count against that person's share, as a
  convened board does. The public demo's own account still only looks.
- **Running and resetting are two rights.** Reset clears the shared demo for everyone signed in, so it has a resource of
  its own, `Shutter_ScenarioReset`, which the operator and the approver hold and the judges' role does not; it also guards
  the store's purge. `Shutter_Scenarios` now guards running only. An install or an upgrade creates the new resource and
  gives it to the operator and the approver, so an upgraded instance keeps their Reset; the uninstall removes it. `GET
  /me` says `can.reset`, and the Settings page's access table has a row for it.
- **Reasons that ask for no role the menu shows.** The user menu shows the demo's viewer and a judge the operator and
  approver badges, yet greyed-out Run and Reset told them they needed the operator or approver role. The reasons now say
  what the sign-in lacks: a judge reads "This sign-in runs scenarios but does not reset the shared demo, which would clear
  it for everyone signed in"; a sign-in with neither badge is still told the role.
- **Orders and results, in true words.** The site profile no longer calls an orders and results receiver "Not modelled
  yet" or says every failure goes to a person and the gate blocks any write to it. Since 1.3.0 and 1.4.0 an order or result
  case gets its findings and goes to a person, with no resend from the case, and at a receiver set up for it an outage's
  messages that never arrived are listed and can be resent after one approval through Engine Resend. The receiver cards,
  the release table, the category choice, the gate's reason `RECEIVER_NOT_MODELLED` (its words; the code is unchanged),
  the explain collection, the install guide's outage section and the README's limits say so.
- **The run modes say what each one is.** The line above the modes says the mode decides who proposes the plan and that
  the same gate checks it in every mode. Board names its four AI Hub agents and the three angles its specialists read the
  sealed evidence from; Site policy says failures the catalogue recognises are settled by the site's written policy with
  no model; Single investigator says it is live only; Rules only is the baseline, a plain Resend, and says where S8 lifts
  one gate check on purpose.
- **Scenario titles and summaries that put the decision first.** Eighteen scenarios' titles or summaries were reworded
  so their first sentence says what the case is about: S3 explains reconciling, S8 names two transfers at the same
  recorded time and its Rules only exemption, S9 and S27 tell an outpatient visit from a second admission, S11 gives the
  incident's scale, and S17 to S19, S25 and S26 have titles that read on their own. The cards on Scenarios and the
  guided path follow: the headline says Shutter resends a failed HL7 delivery only when its checks pass, an unresolved
  gate check blocks a write, S23a's card says the other case frees the bed rather than that this one waits, S15's says
  what the gate prevents, S8's Board card leads with the evidence problem, the S8 Rules only step says it is a
  demonstration, and the guided path names the modes Board and Rules only. Ids, steps and expected outcomes are
  unchanged, and the trial's recorded scenarios carry the same words, S9's without the other visit on the plan, which
  its recording does not show.
- **Settings editors that work, with a Save that is locked.** On the site profile, the agents' library and a review's
  annotations, an account without the right to change the site (the online demo's, a judge's, a site's operator) now
  presses every button, opens every menu and changes every answer, and the changes build up on the page and in the review
  dialog as an approver's do. Only Save is locked: it shows a lock, stays reachable from the keyboard and says why, "The
  online demo's settings are locked: nothing is saved." on the online demo and "Only an approver saves here" on a site.
  The server refuses such a save as before.
- **The tour's arrow points at its section without touching it.** The arrow under the tour's card crossed the section's
  highlight on some steps (the second and fourth of the trial's tour on a desktop): the card now keeps the arrow's reach,
  its nudge and a gap clear above the section's ring, measured on the page, at every width.
- **The scenario diagrams hold still across the modes.** The expected end's box was as wide as its caption, so it moved
  between Board ("after gate checks and approval") and Site policy ("after gate checks and release"). It now fits the
  longest label of the four modes, with the caption centred under it, so switching the mode changes only the words.
- **A test fix:** the stock-install check and the CI steps read the install log without a pipe into `grep -q`, which failed on a long log with a broken pipe although the install had succeeded.
- **The same words everywhere.** Home and the sign-in page lead with "Shutter resends a failed HL7 delivery only when its checks pass", as the trial does; S31 and S32 name S27's story by its new title; the start-here card says the gate blocks any plan that would send a merge; first-steps.md describes the run modes in the page's words; and Shutter in IRIS stays under Configure in the navigation in both views.
- **Tested:** the unit suites on build 154 (1,083 passed, none failed) and 2026.2 (1,074 passed, none failed), with new
  tests that the judge runs and doesn't reset or purge, that the operator and the approver do both, and that an upgrade
  over 1.4.2's roles keeps their Reset; `tests/e2e/roles_check.py` on both with the judge's and the demo's passwords set
  (CI's routes check now sets them), the judge playing S8 on the board in replay with its runs counted against the judge
  and refused the reset; the web suite and the browser specs for Scenarios, the judges' path, Site profile and Settings,
  with axe. CONTRACTS 1.57 describes the split. For the new words, the web suite again, the browser specs for Scenarios,
  the trial and the judges' path, with axe, and `fixtures/generate.py` writing the committed `scenarios.json` byte for
  byte.

## 1.4.2 (10 November 2026)

A fix for the public demo's sign-in page. No new features.

- **The sign-in page says the live hospital is on when it is.** On the public demo a visitor who was not signed in got
  "live" switched off from the health route while the live hospital was running, because that visitor may read
  Shutter's own database but not the hospital's, so the sign-in page showed only its short line. The hospital's player,
  the live switch and the hospital's install now keep a copy of the two values the page needs, whether the live
  hospital is on and how often it fails, in Shutter's own database, and the health route reads that copy when it can't
  read the hospital. Nothing else of the player is shown. A copy that has not been renewed for three of the player's
  periods counts as unknown, so a player that has stopped is never shown as live; with no copy at all, the route says
  nothing about the live hospital, as on a site install.

## 1.4.1 (10 November 2026)

Fixes for what the hands-on recheck of 1.4.0 found left over. No new features.

- **A resend whose result was unknown settles once the engine shows how it ended.** When a receiver answered after the
  send's wait, the message read unknown for good: the closed outage card kept leading with "A resend's result is
  unknown", counted it as failed, listed it as needing a person beside the same card's "Do: nothing more", and its case
  stayed escalated. Engine Resend now reads such a message's new header again, for up to 7 days, and ends it by the
  send's own rules once it settles: Completed resolves the message's case with what was sent, the receiver's declared
  duplicate answer closes it as already held, and any other end is a failed resend with a note on its case. Nothing is
  sent again, and the outage keeps its state, with an event saying what was read.
- **The outage card follows each message's latest state.** Its list shows each message once, as it stands now, with the
  rows a later run replaced folded beneath; its counts count each message once (a message an earlier run left unsent and
  a later run sent counts as sent); a result not known yet is counted as such, not as failed; a failed or unknown resend
  from an earlier run is said after the card's own words, in words true for that run; and a closed card says what still
  needs a person instead of "nothing more" while one does.
- **No approval button before the recovery control is read.** For about a second after Incidents loaded under the stop
  or in shadow mode, the card offered "Approve the resend..." until the control arrived. It now says it is reading the
  control, then shows the approval or the notice; a control that can't be read holds the approval, as the server does.
- **A shadow-mode escalation reads Not sent.** Its line's badge read Failed while the dialog and the toast promised Not
  sent; it now reads Not sent, and it can still be sent again.
- **Words for orders, results and documents that are true in 1.4.0.** The intake's "Shutter resends only ADT" is
  replaced: such a message is not resent from its case, and where its receiver is set up for the outage resend an
  approver can have the engine send it again. Cases stored before read the new words in the email, the evidence and the
  case page; nothing stored is rewritten.
- **The findings on an order or result case have their structure.** One line per finding, with one line per field that
  names every place the character stands once, instead of one paragraph that repeated a field for every place; the
  escalation email names each field once.
- **The outage pause field's example is in the future**: the next 06:00 UTC at least an hour ahead, not a fixed date
  that had passed.

## 1.4.0 (9 November 2026)

Pathology, tier C: after one approval, Shutter resends an outage's messages that never reached the receiver, one at a
time, in order, through the engine itself. Also in this release: the order and result findings working end to end
(1.3.0's known issue), an escalation email that reads saved when no mail server delivered it, and a compact list of the
approval safeguards.

- **One approval resends an outage's offered messages.** An approver approves the offered set on the Incidents page
  (`POST /outages/:id/approvals`: the set's digest, the outage's version and a note); at a receiver whose handling of
  duplicates isn't declared, they also confirm they checked the receiver for each message. **Engine Resend**, a
  production item with one job, resends one message at a time with every rule read again first, writes the ledger
  before each send, and stops at the first message that doesn't complete. A failed resend shows as failed on the card,
  opens no new case and stops the rest.
- **Shadow mode and Stop Shutter recovery hold the outage resend too.** While recovery is stopped, or the site is in
  shadow mode, the approval is refused (409 `recovery_stopped` or `recovery_shadow`) and nothing is recorded, and the
  card says why in place of the button. Engine Resend reads the stop and the mode last before every message, under the
  control's lock until the engine has it: either halts the run, its unsent messages read "Not sent" with the reason, and
  the rest go only by a new approval once the stop is cleared or recovery enabled. Already handled by hand sends nothing
  and stays allowed (`tests/e2e/outage_stop_check.py` counts it at a real receiver).
- **Closing what the receiver already has.** A refusal that says the receiver already holds the message closes it as
  already delivered. At a receiver of unknown duplicate handling, an approver can close a message as already handled by
  hand, with a note: nothing is sent, and who and when go on the record.
- **The patient check, narrowed for orders and results.** A result on another order no longer holds the set. A
  message still holds for a newer message on the same or a linked order (an amendment, a cancellation, a reflex order),
  a newer message for the patient that can't be shown to be about other orders, any merge or identity change of the
  patient, an unresolved case on the same order, or anything Shutter can't read. Patient movements keep the
  patient-wide rule, and a newer message Shutter can't read now holds them too.
- **The engine's attempt history.** Measured on build 154: a forced stop or a crash mid-read leaves no log row, and
  the engine then puts the message back looking as if it was never sent. The set now refuses a message whose life
  crosses a production start or a message the engine put back, so such a message is never resent
  (`tests/e2e/attempt_history_check.py` proves the five cases).
- **The order and result findings reach the case** (fixing 1.3.0's known issue): the snapshot store refused the
  findings item; the receiver's own words are read from the engine's log row; the count of failures sharing a
  character covers every field; a message's cases are found by its namespace and header.
- **A queue alert on a message the engine still holds opens no case.**
- **Email with no mail server reads "Saved, not delivered".** An escalation written as an `.eml` file is marked saved,
  with a "Send it again" once a mail server is set; only a mail the mail server accepted reads Sent. Escalations stored
  before 1.4.0 as sent through the file read as saved.
- **The outage card and the case page say what happened.** After a run, a closed outage lists only the cases that
  still need a person, in plain words; its counts follow Shutter's own sends (sent, already held, handled by hand,
  failed, not sent); a card that is sending offers no Pause or Close and no longer lists its messages as still to
  review; a hand closure is listed once; the engine's raw alert lines are folded; a person's outage reached while
  messages were still queued is read again every minute, and says when its reason was read. A case resolved by the
  outage resend shows the resend, its approval and the new header on its own page. An order or result case names its
  own route, asks no demo receiver address, gives its own next step, and is called a result or an order, with no ward or
  bed. In shadow mode the escalation dialog says before the send that no email goes and no file is saved, and the
  escalate button names the team the draft is for. A hospital's own install no longer offers the demo hospital's trial
  on its sign-in page.
- **The Evaluation page's approval safeguards** are a compact list: one line per check with its required outcome, and
  the detail behind a disclosure, on a phone about half the height of the old table.
- **The live demo.** The banner's budget line shows only to the judges' account; the sign-in page says it is live on a
  real IRIS for Health instance with AI Hub, with the build, when the instance says its live hospital is on (the
  anonymous health answer now carries `live` with only `enabled` and `every_minutes`); Shutter in IRIS shows the
  current mark.
- **F03 and F07 played live on release 1.3.2**, three runs each in Rules only, single investigator and board under
  the same gate: both close right in all 12 agent runs, and Rules only grades as on 1.0.0
  (`docs/readme/fair-test.md`, "Release 1.3.2: F03 and F07 live").
- **Tested:** all 56 rows of the pathology rig on build 154; the unit suites on build 154 (1,066 passed) and 2026.2
  (1,057 passed), none failed; the web suite (2,023 tests) and the browser suite; a new check that the outage resend
  sends nothing under the stop or in shadow mode (`tests/e2e/outage_stop_check.py`); and a hands-on test on build 154
  before the release. CONTRACTS 1.54 describes the send.

## 1.3.2 (9 November 2026)

A patch for the phone layout and two tests.

- **The live banner on a phone.** The notes under the banner's bar now use the width kept for the close button, which
  sits only in the band's top corner, so the budget line stays on one line at 360 px.
- **Tests.** The trial transport test knows the one route the recorded trial answers `not_in_trial` on purpose
  (receiver outages), and the live budget test audits the Convene dialog with no motion, as the accessibility suite
  does. The case page's retry to reveal a section stops once the page is gone, so a test's torn-down document no longer
  raises an error after the last test passes.
- **README.** The "Why I built it" paragraph says production exposes conditions test environments cannot fully reproduce.

## 1.3.0 (9 November 2026)

Pathology, tier B: for an outage at a receiver of orders and results, Shutter now lists the messages that never reached
it, for a person. Shutter still sends none of them. The FHIR
R4 receiver is in development: some of its parts are in the release and tested, and no case uses them yet.

- **The resend set on an outage.** When an outage closes, Shutter works out, in the production's own job, which failed
  messages of its window were queued, offered, reached the receiver or were refused, each with its reason, and checks
  every patient on them: every PID-3 identifier, the receiver's newer messages for the same patient, and Shutter's open
  cases for that patient. An outage with messages that never reached the receiver reads **offered**: "N messages failed;
  M never reached the receiver and are listed for a person. Shutter will not send these messages." The set is computed
  again each minute and on **Read again**, a message the engine tries again sends the outage back to open, and nothing
  changed writes no event. An outage with errors and nothing offered stays with a person.
- **Known issue: what Shutter found on an order or result case.** The parts that read who holds the message, the
  receiver's own words (MSA and each ERR), the OBX those words name and where a character above plain ASCII stands are in
  the release and pass their unit tests, but on the pathology test rig these findings did not reach the case end to end
  (the characters' fields, the count of shared failures and the OBX named). The fix comes in 1.4.0. The outage lists,
  their patient checks and the outage email passed on the rig. The escalation draft never takes a result's value, units
  or comment.
- **The outage email.** Outage Mailer, an item a site adds and switches on per receiver, sends one email per outage
  state the receiver's entry names, at most one every 10 minutes, naming the receiver, the counts and the page, never a
  patient.
- **Outages on the Incidents page.** The receivers' outages sit above the incidents: one line per watched receiver, loud
  when its watcher is stale, and a card per outage with its own words, the engine's alerts, the lists, and only the
  actions it allows, for an approver.
- **A message of a watched namespace is copied whole.** A message read in a hospital's namespace and used after
  switching back loaded its segments from Shutter's own message of the same id, so the patient check could hold the
  wrong patient. It is now copied whole while switched (found on the pathology test rig).
- **FHIR R4, in development.** The plan builder, the verifier's decision and a test FHIR server held to IRIS for
  Health's own FHIR server's answers are in the release, compiled and tested; nothing in the case workflow calls them,
  and Shutter does not recover a write to a FHIR server ([fhir.md](docs/readme/fhir.md)).
- **CONTRACTS 1.51** describes the set, Read again and the findings.

## 1.2.1 (9 November 2026)

Fixes found by the checks run on 1.2.0 on IRIS 2026.2 and AI Hub build 154, and stored maps for six tables so a later
upgrade keeps their rows in place.

- **Two decisions at once.** When two people decide the same approval at the same moment, the second is now told the
  decision that stands (the action, who took it and when) once the first has completed the task, instead of a "no task"
  answer.
- **A cancel waiting for an approval's lock.** A cancel that finds the approval task's decision lock taken is tried again
  only by a workflow the running production hosts. One made outside it notes on the case that the task stays open and
  logs a warning, instead of an alarm that IRIS refused and the Event Log kept as a runtime error.
- **Stored maps for six tables.** `OutageEvent`, `ReceiverReading`, `RecoveryControl`, `RecoveryControlEvent`,
  `ShadowObservation` and `DispatchPermit` now keep the storage map 1.2.0 compiled for them in their sources, so a
  property added later takes a new slot at the end and an upgrade reads every existing row as before.
- **The cases list is read once per visit.** Home and the live hospital banner no longer ask for the cases list again
  each time they show; a decision on a held case marks the lists out of date, so Home's link to a held plan is read again.
- **Tests.** The roles test reads the cases list's queries from where this build holds them, and the tour's scroll test
  starts the engineers' tour from its own address.

## 1.2.0 (9 November 2026)

What 1.2.0 holds: **Ask Shutter**, a panel that answers questions about the page on screen; a **live hospital banner**
you can close, which comes back for an open incident; **clearer screens** for an integration engineer and a tired
clinician (the case page's key facts first, more in the Technical view, a colour and icon per disposition, an API page,
an access comparison, the scenario diagrams' expected end); the fix for the null bed that held a settled case for a
person; an incident of any size under one approval; a supported **uninstall and upgrade**; another visit's movement
shown on the plan on a new install, while an upgrade keeps a site's stop; for a site getting ready to pilot,
**shadow mode** and a **stop switch**, a **failure census**, document exceptions, warehouse history, a guide to what to
check at the receiver, a case bundle, the **receiver conformance kit** and the **pilot pack**; and fixes found in three
rounds of review.

- **A receipt whose bed is null says nothing about the bed.** The receipt check read a JSON null bed as a different bed
  (`RECEIPT_PAYLOAD_DIFFERS`), so a person got a case the receipt had settled (held-out case F03). Beds are now compared
  only when both the receipt and the operation state one; a null, missing or empty bed reads as not stated, and a stated
  different bed still stops the close. A unit test covers each. With this check loaded over 1.1.1's code, the board's
  reconcile closed F03 in all three held-out runs, with nothing written (8 Nov 2026, AI Hub build 109).
- **Per-call trace lines in a replay.** A replayed run writes one trace line per recorded tool call, as a live run does,
  with the tool, ok, denied or failed, the milliseconds and the word replay, and no argument, result or error text, so
  each call is a step of its own in the Visual Trace. The tracing walk-through shows the steps and the page size that
  keeps a pass on one page.
- **Uninstall and upgrade.** `zpm "uninstall iris-shutter"` takes off everything the install and the onboarding added, in
  every namespace, and stops no production of the site's: a site production Shutter went into is updated in place and its
  own alert item gets its name back. `SELECT Shutter_Util.Uninstall_Plan()` says what would go. The uninstall refuses,
  changing nothing, while a production it did not wire still names a Shutter class, or while a hospital's namespace holds a
  class of the site's in the `Hospital` or `Downstream` package. A `zpm "load"` of a newer tree over an installed release
  is an upgrade that keeps the production, its cases and the site profile; restart `Shutter.Production` afterwards. Two
  checks, `tests/e2e/uninstall_check.py` and `tests/e2e/upgrade_check.py`, prove both on build 154, the upgrade over
  1.0.0 and 1.1.1.
- **An incident is one approval at any size.** The shared approval task's Workflow message holds 2,000 characters, and
  1.1.1 abandoned an incident above about four chains, with every case `failed`. The task now lists the first chains that
  fit, says how many it leaves out and points to the incident page; the digest is whole and one approval binds every
  chain. An error raising the task leaves the incident waiting for a person and tries again every 5 minutes. The incident
  page lists six chains with the rest behind one button. A storm check proves it at 40, 200 and 1,000 failures
  (`docs/readme/storm-at-scale.md`).
- **Another visit's movement shows on the plan by default.** `further_messages.in_patient_movement` is `show` in the
  shipped profile and when a profile doesn't say: an in-patient movement on another visit goes on the plan beside the
  resend instead of stopping it, while a cancel, merge or discharge on the case's own visit, or a change to the record,
  still stops it. A site that wants the stop sets `stop`. A fresh demo install keeps the stop, labelled in its profile,
  the live hospital's included, so S27, S31 and S32 stop as before. An upgrade never relaxes the check by itself: a site install
  over 1.1.1 or earlier writes `stop` into a stored profile that doesn't name the setting, so a running site keeps
  1.1.1's stop until a person saves `show`; a new install gets `show` (`docs/INSTALL.md`, section 8). A write that shows such a movement is never released by policy: at a tier whose policy is `automatic` it waits
  for a person, and an incident's chain that shows one leaves the shared approval for its case's own path. A
  movement that arrives after the approval is compared with the approved plan at dispatch, and a new one holds the write
  (`FURTHER_MOVEMENT_NEW`) until the plan is read again and approved again.
- **Further messages in an onboarded namespace read the feed's zone.** The read of a patient's further messages runs in the
  watched namespace, which maps only Shutter's intake and utility classes, so a message time with no UTC offset looked up
  the feed's zone in a class that namespace can't reach, the read failed and the write stopped for a person
  (`FURTHER_NOT_READ`), with nothing written. The read now carries the zone from Shutter's namespace (`Shutter.Util.Time`,
  `Shutter.Util.FurtherMessages`), and a unit test reads a time in a namespace with no zone of its own. On build 154 the onboarding check
  passed 238 of 238 and the 26 scenarios played as expected with the fix.
- **Another provider, by hand.** `docs/readme/another-provider.md`: the board run on OpenAI's `gpt-4.1` through AI Hub on
  build 109, S2 and S8 as expected twice, with the steps as tested and their undo, runs unpriced and outside the day's
  budget, and the places the install assumes Anthropic. Current OpenAI models refuse the `max_tokens` the runner sends.
- **AI Hub notes and issues.** `docs/readme/building-on-ai-hub.md` adds skills, `response_format`, knowledge base search and
  `CreateFromConfig`, each measured on builds 154 and 109 against a local stub with no model call, and links the issues
  filed on 8 November 2026: #22 (a tool argument's schema), #23 (the Config Store descriptor), #24 (`max_tokens`), and a
  comment on #4 for 109. `docs/readme/mcp.md` is a transcript of the publisher from an MCP client: the tools listed,
  `GetCase` with its audit row, and the refusal without `Shutter_Publish`.
- **The README, restructured.** A first screen under 750 words with the judges' path, one sign-in table and the measured
  figures, every term defined; six limits inline and the rest in `docs/readme/limits.md` as a table of effect, workaround
  and status; the fuller rows in `docs/edge-cases.md`; a pilot in the order it works in `first-steps.md`; and the
  held-out cases on release 1.1.1 in `fair-test.md`.
- **The trial's judges' path.** The S8 card plays in the chosen mode and says so, `?trial=judge` opens Scenarios in Rules
  only on the S8 card with no welcome, and the Rules only note says S8 is exempted on purpose and that the gate holds the
  resend on a real case. The Evaluation page puts the held-out fair test above the board's own score, with always
  escalating, both single investigator figures and release 1.1.1's board; **Explore on my own** keeps the welcome away
  for the visit, and the boundary table's scroll area takes the focus where it scrolls sideways.
- **The README review fixes.** The trial route has its own line, the first screen is shorter, only the identifiers
  Shutter knows for the case are said to become tokens, and `SELECT Shutter.Setup_ClearProvider()`, which an install
  keeps, is the way to send nothing out; the pilot maps the trust's users to the two roles first.
- **The production review's agent never reads a patient's words.** An error group's signature goes to it as an IRIS
  error code or a digest, never the logged text, and a case aggregate's key goes as it is only when Shutter knows the
  word (an item of the production, a failure kind or state, an outcome or reason code Shutter writes, an acknowledgement
  code or an HTTP status); anything else, a surname or a postcode included, goes as its digest with its count. The
  stored review keeps every word, and the record key and `SnapshotDigest` don't move. The scenario routes
  (`POST /scenarios/reset` and `/scenarios/{id}/run`) answer 403 `not_a_demo_instance` and change nothing off the demo,
  and an end-to-end check plays two patients no fixture holds in Board mode with no key: nothing is written.
- **The MCP page.** The forwarder's `tool_not_found` is credited to the MCP Inspector's own tool-list check, with the
  sidecar's `isError` answer to a `tools/call` sent anyway.
- **Docs truth for 1.2.0.** The README's first screen gives the trial first, then the online demo, then
  `./install.sh --replay`, and a Measured box with each figure's release; `docs/readme/model-fails.md` maps each agent
  run status to what the case does, with the real bounds; the safety and limits pages say what 1.2.0 does as shipped;
  the F03 null-bed runs are published with the fair test; contracts v1.48, and v1.50 with the pilot features below. `docs/INSTALL.md` shows `InstallInto` with a
  site's own production name.
- **The health page.** Each group lists its checks first and its facts apart under **Details**.
- **The API page.** `docs/api/openapi.json` describes every route (an OpenAPI 3.1 file that CI checks against the
  dispatcher), and the Technical view gains an API page listing each route with its parameters, its role and an example.
- **Ask Shutter: a chat about what is on the screen.** A button in the header opens a panel on every page, beside the page
  from 1200 px and as a drawer below it (the whole screen on a phone), open or closed remembered per tab. On a case page it
  is Ask about this case, through the same read-only case questions as before; the "Ask about this case" button opens it
  and asks the case's first suggested question. On every other page it asks about the page through one new read-only
  route, `POST /api/shutter/page-questions`: the web app sends the page's name and a short summary of what is in view (ids
  and labels only), and the Explain agent answers in a new question tier, `page`, with its knowledge search and
  `SubmitAnswer` alone, the summary as data inside the prompt, a small budget and few turns, under `Shutter_LiveAgents` and
  the day's budget as a live case question is; nothing is recorded. Without `Shutter_LiveAgents` the route answers 403 and
  the panel shows the page's written guide; the trial answers a few suggested questions per page with sample answers,
  labelled so. CONTRACTS 14.6.
- **The live hospital banner.** A two-part bar with a timeline from the last failure to the next; it closes for the
  session, a **Live hospital** button reopens it, and an open incident brings it back with a link to the incident.
- **Clearer screens.** The case page puts the key facts first with a smaller case id and click-to-define terms; the
  Technical view shows the HL7 message type, the receiver, the source system and message id, and the HTTP status and
  reason code; each disposition has its own colour and icon; the production review's summary is one compact bar;
  Settings compares what your account can do with the demo viewer, the operator and the approver; the scenario
  diagrams name their expected end and stay readable on a phone; and keyboard focus stays where you expect it.
- **A receiver declared with no API** is named by its item and namespace in the email, the case page and the history,
  and its stop says it was declared with no API and that a person fills in its entry in the site profile.
- **Shadow mode and the recovery stop.** A new install with no demo, and an upgrade whose site profile doesn't say,
  starts in shadow: Shutter investigates and records what it would propose, and sends no rehearsal, recovery write or
  blind-resend preview, until the profile's `recovery.mode` says `enabled`; `GET /shadow-observations` and its CSV report
  the period's cases. **Stop Shutter recovery** on the Settings page (`Shutter_StopRecovery`, which operators and
  approvers hold) refuses every recovery call at the connector from the moment it commits; clearing it takes an
  approver, enables nothing and leaves every earlier plan void. The demo seeds `enabled`, so it behaves as before.
  CONTRACTS 18.
- **The failure coverage census.** Off unless the site turns it on: of a watched receiver's failed deliveries in a
  window, which have a traceable Shutter case, with a CSV that says what the read is worth; it reads only and copies no
  message content. CONTRACTS 19.
- **What to check at the receiver.** A blocked, escalated or failed case lists what a person should look at on the
  receiver's own screen, built from the case's own fields with no model call and no receiver call.
- **Document exceptions.** A failed MDM, or an ORU carrying a report, at a receiver with a document profile becomes a
  case that resends nothing, convenes no agent and keeps no copy of the message; the Settings screen for watched
  namespaces shows where the forwarder and the profile disagree (`documents_mismatch`).
- **Warehouse history.** A receiver with no API can publish its earlier movements in two tables, shown to a person
  beside the case and never used to write (`docs/warehouse-history.md`).
- **The receiver conformance kit.** `scripts/receiver-conformance.py`, run by a site and the receiver's supplier against
  a test endpoint, reports which parts of the recovery contract it showed; it enables nothing (`docs/receiver-conformance.md`).
- **The pilot pack.** `docs/pilot/`: a decision record, scope, stage plan, roles, hazard log, data flow, receiver
  acceptance, stop and withdraw, daily review, outcome report and a safety case template, for a hospital deciding
  whether and how far to pilot. It claims no compliance.
- **The case bundle.** One JSON file of a case for audit or a support handoff, redacted for an operator, or unredacted
  for an approver who types a reason; neither moves a closed case's receipt.
- **A person releases another visit's stop.** An approver who has read the other visit's messages releases that one
  stop with a reason (`FURTHER_MOVEMENT_RELEASED`); every other check still runs. `further_messages.a08_location`,
  `stop` or `show`, decides a later A08 that names another ward or bed (S33, S34).
- **A non-demo install starts with no automatic release.** The seed's demo receivers become one draft to fill in, and
  every `automatic` in its policy reads `approval`. A reminder mail for cases left open is a site profile setting,
  `reminders`, off when absent and held in shadow mode. The drafted correction sequence for a history-of-record receiver
  stops at every further message for the patient. The Doctor lists what each receiver last answered, and a
  report reads an instance before an install.
- **An incident's approval is void when the catalogue, the site profile or the gate policy moved** since it was given
  (`APPROVAL_CATALOGUE_CHANGED`, `APPROVAL_SITE_PROFILE_CHANGED`, `APPROVAL_POLICY_CHANGED`). Gate policy version
  2026-11-07.1, so an approval given under 2026-11-06.1 and not yet dispatched is void at dispatch. A lost admission is
  never released by policy inside an incident either.
- **Four more scenarios:** S14, a later movement only the index has seen; S26, a schema not loaded here; S33 and S34, an
  A08 that moves the patient's bed; 36 in all, S1 to S34 with S23 in three parts.
- **Fixes found in review before the release.**
  - The decision lock is given back when cancelling an approval task fails, and a refused second decision names the
    decision that stands.
  - An incident's approval task is checked for the role before it is raised and after, and an incident whose task can't
    be raised goes back to awaiting approval once its other chains are done, so it stays listed.
  - The task text counts a chain as shown only when all of it fits.
  - Another visit's movement is never released by policy, leaves an incident's shared approval, and a new one after the
    approval holds the write at dispatch.
  - The uninstall also takes the messages, process rows, queues, saved engine state and Workflow index entries that
    Shutter's items left, and nothing of the site's; it stops at the first failed step with Shutter's configuration
    kept, and refuses when a namespace can't be read.
  - The installer refuses a production in the demo's `Hospital`, `Downstream` or `Shutter` packages.
  - In a site's own production the uninstall takes only messages from sessions that hold one of Shutter's, skips
    namespaces nobody can enter, and selects processes by class; the upgrade keeps the stop even when an older profile
    fails today's checks; an approval counts as decided only when it was; a policy release that meets a new movement is
    planned again.
  - Ask Shutter follows the Agent Board item's own Mode and is never recorded or replayed; a page answer may cite a
    listed id with a path, as its tool accepts; its questions are cleared at sign-out, measured as the server measures
    them, and purged on the cases' retention days, and the uninstall takes them.
  - The cases list could come back empty on IRIS 2026.2: the API roles now hold SQL SELECT on `Ens.MessageHeader`,
    the one table outside Shutter's schemas the list reads as its caller, and the uninstall revokes it.
  - A timed-out approval's task is cancelled only under the decision lock; until then the case keeps waiting, and it
    escalates only after the cancel.
  - The scenario runner plays on a demo instance only, over SQL and the terminal as over REST.
  - A key shown anywhere (agent start lines, refusals, settings, stored runs) is masked by one rule, and a model id
    written as a name and a version is shown as it is, not masked.
  - The production review withholds an error signature without blanking the same word elsewhere in its text, and the
    judges' address is set once.
- **The public demo's IRIS page no longer stays locked.** Signing out of the web app ends its IRIS session, and the
  public demo's API sessions end after 120 seconds without a request, so eight sign-ins no longer hold every Community
  licence connection; `docs/readme/troubleshooting.md` says what can still lock the Shutter in IRIS page, and for how long.
- **An incident's page names an approval task that could not be raised,** the shared one or a chain's own, with a banner
  for each until its task is there, and a chain with no first receiver version says none is on record.
- **The tracing walk-through shows the Visual Trace of S2 and S3** in replay on the board, a member's tool calls as
  steps, and S3's receipt read with no write after the gate.
- **Sonnet 5.5's cache reads are priced at its list price,** 0.20 USD per million tokens (0.10 before); an upgrade updates
  the stored price unless a person edited it, and the costs already recorded stay as they were.

## 1.1.1 (8 November 2026)

A fix found by the live board on build 109 at 1.1.0 (`docs/readme/receipt-109.md`, "The board live on build 109, release 1.1.0"):

- The route item an agent reads kept only its history and epoch, because the model view that reduces every item before it leaves IRIS read a route that says whether the receiver offers history as a receiver's body. The specialists then could not see that the receiver takes conditional writes and dry runs, and the live board held every resend for more evidence. The view now reads a route as a route, keeps its capability profile and the history field, and a unit test holds it there. Replay was not affected: a recording answers in the model's place.
- The README's testing figures name the 1.1.0 run; the install notes say which build a plain install takes when both are loaded, how to choose, and how to change the port; the first step says which case id a fresh install shows.
- The Shutter in IRIS page lists the production's agents, the model each runs when live and where it comes from, its mode, turns, budget and last run, and the other operations with the settings that hold no secret. It no longer reloads itself every 30 seconds, which took a screen reader back to the top: a Refresh link beside the time reloads it.

## 1.1.0 (8 November 2026)

What 1.1.0 holds: Shutter watches configured HL7 TCP operations without contacting their receivers. It groups outages,
shows whether the engine is retrying or messages have settled, preserves unresolved exceptions, and shows the site's next
action and contact. It sends no orders or results. At supported stock TCP routes, it also prevents Shutter's ADT API
recovery from competing with the engine's delivery. And the shipped site profile now asks a person before every resend.

- **A person approves at every tier by default.** The shipped site profile's policy is approval for single and ordered
  chains at tiers 1 to 3, and the board for interleaved ones; a site that wants a tier released by its policy says so in its
  own profile. A demo install keeps the earlier table (tiers 1 and 2 released by policy for single chains, tier 1 for ordered
  ones) as the demo's own setting, marked in the profile's source and labelled on the Site profile page; the online demo
  also asks a person at tier 2 for single chains. A profile a person saved is never changed.
- **A receiver's outage is one incident.** A receiver whose site profile entry has a `watch` block is read by the new item
  `Receiver Watch` every 5 seconds: the production's state, the operation's status, adapter state, queue, head message and
  settings, in the watched namespace, with no connection to the receiver and nothing written there. One outage opens per
  receiver, drains, closes when every header of its window has settled, or goes to a person, with the engine's own alerts
  beside the record and the cases of the outage listed with it. A linked case is resolved only from its own delivery header.
  The routes `GET /outages`, `GET /outages/{id}` and `POST /outages/{id}/acts` (pause and close) carry the outage's words:
  what the engine is doing, the site's runbook and call lines, who may approve, and at an orders and results receiver the
  critical-results sentence. The Doctor's `outages` reads each watched item's settings and names what a profile declares that
  the build does not act on (`docs/INSTALL.md` section 11).
- **The site profile takes a receiver's outage keys:** `watch`, `runbook`, `call`, `approvers`, `ack_level`, `duplicates` and
  the minutes, checked in the same words by the server and the page; `engine_resend`, `hold` and `mail` validate and do
  nothing in this release.
- **No write while the engine still has the message.** At a stock HL7 TCP operation, a write waits while the engine is
  still trying its message (`ENGINE_STILL_TRYING`), resolves when the engine delivered it (`ENGINE_DELIVERED`), and is blocked
  for a person when the receiver may already hold it (`RECEIVER_MAY_HOLD_IT`) or the engine's record can't be read
  (`ENGINE_UNREADABLE`). The Case Releaser judges each waiting case again every few seconds. This closes a double delivery
  measured on 1.0.0: an approved API write, then the engine's own delivery when the listener returned.
- **No claim of verification without a receipt.** A case with no receipt says the receiver was not checked, with the words
  its declared acknowledgement level allows, and the escalation email promises no check of a receiver Shutter can't read.
- **Further messages for the patient.** Before a write Shutter reads the patient on every visit it can see: a further
  in-patient movement on another visit stops the write and names both visits, a lost admission waits for a person, and the
  read walks every header since the case's own, for as long as the profile's `further_messages.scan_seconds` allows.
- **An automatic release needs the case's source proved:** the named namespace must hold the named header with the text
  received, sent to that receiver; otherwise a person approves (`feed.prove_origin`).
- **What reaches Shutter.** An alert or a negative acknowledgement carries the message the failing item was sent; a session
  with several messages to one item opens no case on a guess and says so; alert words Shutter does not know read as an
  uncertain outcome, never as not delivered; a forward nobody answered waits in the forwarder's queue and is tried again for
  its `FailureTimeout` (300 seconds as onboarding now sets it).
- **What the receiver must honestly offer.** A resend needs a readable history; a read counts only when it is the receiver's
  own answer, a 200 is a delivery only with its receipt, and a receipt closes a case only when it holds the message's own
  content (`strict_answers`). A write a receiver made during a rehearsal goes on the record and stops the case.
- **The verifier and the purge.** No sign of a write by the last read is unknown, not "not committed"; the case purge takes
  only finished cases.
- **Incidents.** An approval under an incident binds the plan's receiver epoch; the next item of a chain goes at the version
  in the previous item's receipt; a chain waiting on a bed held in a later chain of the same incident stops; the intake of an
  incident closes at a maximum time while the receiver keeps refusing.
- **The catalogue.** E19, new, sends a case with a death on the message to a person; E1 closes a failed transfer only; E7
  takes a movement from another source within `feed.source_skew_seconds`; E13 is revised. A case the catalogue gives to the
  board or a person goes to a person when no board member can answer. Policy version 2026-11-06.1.
- **The approval dialogs** name the case, the patient with authority, the event time and the bed, and hold the plan they
  opened on.
- **Upgrading:** run the install once and restart the production. Approvals given before the upgrade and not yet dispatched
  are refused (the policy and catalogue versions moved), precedents recorded before it are not found under the new policy
  version, and saving the profile voids approvals not yet dispatched (`docs/INSTALL.md` section 8).
- **Not in this release:** a list of messages to send again, a resend of orders or results, named findings, an agent's
  summary of an outage, a profile assistant, the outage email and the hold on a patient's ADT traffic. The limits are
  `docs/INSTALL.md` section 11.7.

## 1.0.0 (6 November 2026)

What the first release holds: Shutter, supervised recovery of failed deliveries in an InterSystems IRIS
Interoperability production, with a board of IRIS AI Hub agents.

- **A failed delivery is a case, not a retry.** When a delivery from an HL7 ADT feed fails, Shutter opens a case,
  gathers the evidence (the message, the receiver's state, receipt and history) and decides what should happen:
  resend it, reconcile it because it already arrived, leave it because a later event superseded it, or escalate it.
- **A board of AI Hub agents** (in the `iris-shutter` package; the core module `iris-shutter-core` replays their
  recordings): three specialists review a case in parallel and a coordinator proposes one plan, each agent a business
  operation in `Shutter.Production`, with their tools, schemas and knowledge bases on IRIS Vector Search
  (`%AI.RAG.VectorStore.IRIS`). Without an API key or the AI Hub build, the agents replay recorded runs.
- **A deterministic gate** checks every plan (identity, conformance, intent, ordering, state transition, effect,
  authorization, rehearsal, concurrency, evidence freshness, the receiver's capabilities and the catalogue); an unknown blocks
  a write as surely as a failed check.
- **A person approves the exact action**, bound to the plan's digest, the evidence, the gate's policy and the
  receiver's version, or the site's policy does for the cases the scenario catalogue knows. Shutter then makes one
  conditional write and verifies it in the receiver's own history.
- **Who decided.** The approver of record for a case's or an incident's approval is the signed-in user, never a name
  in the request: the route assigns the Workflow task to that user, writes the digest the body named into the task and
  completes it, and answers who was recorded. An approver outside the Workflow role `Shutter Approvers` is refused
  (403), as is an approval with no digest and a task another approver holds. The approval tasks no longer pre-fill
  the plan digest: an approver who decides in the Management Portal's Workflow inbox pastes it from the task's text,
  so an approval from the inbox binds the digest as the API's does. The same step from SQL,
  `Shutter.Util.Workflow.Decide`, takes the digest instead of a user name.
- **A write stands on its own dry run.** The gate's rehearsal check releases a write only when the approval's bound
  rehearsal is of the same plan, reported it would apply, and was checked against the version, epoch and payload the
  write carries (`DRY_RUN_MISSING`, `DRY_RUN_FAILED`, `DRY_RUN_STALE`); a receiver whose capability profile offers no
  dry run gets no resend (`DRY_RUN_UNSUPPORTED`), and the connector sends it no dry run. A receiver that applies a dry
  run is recorded as an execution, alerted and verified, never reported as rolled back, and the blind-resend preview
  refuses such a receiver and reports what it was checked against. Policy version 2026-10-25.1: an approval given
  before it and not yet dispatched is void at dispatch.
- **No verdict from silence.** A write whose answer was lost is read again (10, 20, 40 s); the verifier says not
  committed only after its settle window (30 s by default) with the receiver's version unchanged, or once the version
  moved past the one the write was conditional on, and the case then escalates with the approval revoked
  (`WRITE_NOT_COMMITTED`; `WRITE_OUTCOME_UNKNOWN` when the reads could not settle it). An acknowledged write without a
  receipt is a contradiction, not "not committed", and nothing is ever resent from a verification. The matcher, the
  gate and the verifier agree on what supersedes: a later applied cancel, merge or admission blocks a resend, a later
  transfer the feed sent whose delivery failed is named by its key and case on both cases, and the condition
  `later_delivery` says whether the superseding event reached the receiver.
- **Incidents:** many failures to one receiver become chains per encounter, released in order under one approval,
  stopping at the first surprise.
- **The incident's approval binds each item.** The incident plan's digest is the SHA-256 of the whole recorded plan
  in canonical JSON, so every item's case, catalogue entry, outcome, who decides and the version it goes at are
  bound, and the digest is recomputable from `GET /incidents/{id}`. A released item whose fresh evidence reads another
  entry or outcome than the approval covered blocks before it is planned ("Not covered by the incident's approval")
  and its chain stops; the case's approval records the incident plan's digest and the bound entry and outcome
  (`incidentPlanDigest`, `boundEntry`, `boundOutcome`), and the dispatch gate refuses it with
  `APPROVAL_ITEM_CHANGED` or `APPROVAL_INCIDENT_PLAN_CHANGED` when they no longer hold.
- **The site profile:** the induction questions that decide what goes without a person, who approves what, the teams
  an escalation goes to, the feed's time zone and whether note text may reach the model, with every version kept.
- **Only what is needed reaches the model:** identifiers become per-case tokens, names, dates of birth and addresses
  are dropped, and CI fails when anything personal from the fixtures reaches a recording. When the reduced view of a
  case cannot be made, no request is built: the case is escalated with the reason and nothing reaches a model.
- **Merges** are withheld by default (the site profile can allow them for a receiver that takes them), and **cancels**
  the receiver cannot take are withheld; both are escalated, with an email drafted for the team the site profile names.
- **Escalation emails** go only to bare addresses inside the site profile's `mail.allowed_domains` (with none set no
  email can go), with no line break in the subject or an address, checked when the profile is saved, at the edit, at
  the send and by the mail operation before it writes; a hand close cancels every pending email and nothing is sent
  about a case that is closed or reopened; and the text of each email (the one copy of the NHS number and the date of
  birth outside the message store) and its `.eml` file are removed 90 days after the case closed
  (`SHUTTER_ESCALATION_DAYS`; `0` keeps them; on by default, an upgraded instance included), the row staying with its
  digest and recipients.
- **The web application:** scenarios, cases, incidents, the board's findings, the gate, approvals, verification, the
  site profile, the library, and costs and tokens per agent run; served by IRIS, and as an online demo of recorded
  runs.
- **Scenarios** S1 to S25 (S14 aside; S23 in three parts; 26 in all) that play each kind of failure end to end on the
  demo downstream system, a demo hospital production in its own namespace that Shutter watches (S19), a nurse's move entered by hand in the
  downstream system while a resend waits for approval: the approval is bound to the receiver's version, so the resend
  never writes over her entry (S20), and a transfer timed in the hour that happens twice when British clocks go back,
  which nothing writes (S21). Their messages carry what a real PAS feed sends: an NHS number beside the hospital
  number in PID-3, the prior location of a transfer and the location on an update or a discharge.
- **One transfer, two receivers** (S22): the same feed goes to the bed manager and to a demo patient records system
  (the `RECORDS` namespace behind `/records/api`, the items `ADT to Records` and `Records Out`, category
  `history_of_record`). A case is one failed delivery to one receiver, so the bed manager's case closes superseded with
  no write and the records system's escalates with the steps that correct its history.
- **The occupied bed** (S23a to S23c): for a `409 bed_occupied` refusal the evidence reads who holds the bed and whether
  they are leaving, and the gate answers `OCCUPANT_MOVED_OUT`, `WAITING_FOR_OCCUPANT_CASE`, `OCCUPANT_CASE_FAILED` or
  `BED_OCCUPIED`, a case waiting on the occupant's own case. **A newer message on its way** (S24): the gate holds a resend
  with `NEWER_MESSAGE_PENDING` while a later message for the encounter is still undelivered, and the connector checks
  again at the moment of the write. **A site's own segment** (S25): a message IRIS cannot read against the loaded schema
  is never resent (`PARSE_FAILED`, with the Second Parser's verdict). The gate's policy version in this release is
  `2026-11-01.1`; an approval given under an earlier version and not yet dispatched is void at dispatch
  (`APPROVAL_POLICY_CHANGED`).
- **The Second Parser:** a Java business operation through PEX (`Shutter.Operation.SecondParser`, HAPI 2.6.0, built by
  `pex/build.sh`) that the Evidence Collector asks when IRIS cannot read a message; it says whether the message is well
  formed and of a schema this namespace lacks, or malformed and where, and the gate's `SCHEMA_UNKNOWN` and `PARSE_FAILED`
  words carry its verdict. Without the jar the item is disabled and the Doctor's `second_parser` says so.
- **Custom HL7 schemas, and prevent failures:** the Doctor's `hl7_schemas` (loaded, needed, missing),
  `Shutter.Setup.ImportSchema` and `GET` and `POST /settings/schemas`; a message whose category is not loaded is
  `unknown schema`, blocked `SCHEMA_UNKNOWN` until the schema is there. With the site profile's `feed.prevent_failures`
  such a message is held as a case of kind `unreadable` instead of delivered, and the index's check releases it once the
  schema is imported (catalogue entry E18).
- **Onboarding a hospital's namespaces:** a plan that changes nothing (`Shutter.Setup_OnboardPlan`), an apply that does what it
  listed and never stops a production, a marked test failure per namespace, the Doctor's `watched_namespaces`, and a removal;
  an item or a schema category named alike in two namespaces stays apart, and a namespace keeps its receiver names when another
  comes on after it; the forwarder's user goes with the last namespace's removal, never before (`docs/INSTALL.md`, section 9). A forward naming a
  category not loaded here is reported as such and repaired once it is loaded, and a load in a namespace running another
  production is refused.
  A message routed to two receivers opens a case for each that fails. The plan warns of retry-forever whether the item sets it or
  inherits it, a refused forward also raises an alert to the site's consumer, and the Doctor counts refused forwards over 72 hours and
  lists HL7 operations added since the last apply.
  The plan says, per HL7 operation, what a completed message proves there, as measured against a listener: on the stock codes CA reads as
  AA. A negative application acknowledgement on a feed of its own can open a case, through a small process a site copies and
  `Shutter.Intake.AckMatch`. A message taken by a transport ACK and then lost downstream raises nothing.
- **The index walk is an adapter of Shutter's own** (`Shutter.Index.Adapter`, handing batches of message headers to
  the HL7 Index item), and **any IANA time zone** for the feed through Embedded Python's `zoneinfo`
  (`Shutter.Util.Time.PyOffset`), beside the native rules for UTC, Europe/London and fixed offsets.
- **Ask about this case:** a deterministic what-if card (`GET /cases/{id}/whatif`) and questions to the Explain agent or
  to the board (`/cases/{id}/questions`), answered from recorded conversations without a key; the agents cannot write.
- **A storm is survivable:** the alert intake (`Shutter.Intake.AlertProcess`, a watched production's `Ens.Alert` item,
  hands a failed delivery to Shutter from the alert alone); one board per failure signature (the first case leads, the
  rest take its decision through their own evidence, gate, rehearsal and approval); boards per minute capped
  (`BoardsPerMinute`); a bounded approval wait (`ApprovalWaitSeconds`); a bound on one model call
  (`SHUTTER_PROVIDER_TIMEOUT_SECONDS`); a receiver's `Retry-After` kept as a minimum wait before a resend; and the Case
  Releaser item, which releases waiting and held cases in a sweep of its own.
- **Precedents:** what approvers decided before on the same conditions at the same receiver, and whether it held,
  counted in the approval task's text and answered by `GET /cases/{id}/precedents`.
- **The tool catalogue is pinned** when a run starts (`Shutter.Bridge.Catalogue`): what the framework discovered must be
  exactly the agent's evidence tools, its terminal tool and its collections' search tools, or the run ends
  `catalogue_mismatch` before any model call. Findings and plans may cite only the evidence they were given, and
  invisible characters are stripped from everything a model wrote.
- **The live hospital and the storm:** with `SHUTTER_LIVE=1` the demo hospital's Live PAS item plays one of Shutter's
  scenarios every 7 minutes with fresh patients at present times and real faults, and writes an ordinary message a
  minute between stories; `POST /live/storm` ("Break the feed") fails eight movements for four fresh patients with the
  receiver down for a minute, so an incident can be watched on demand.
- **The public demo's users and the model budget:** `demo` (reads, reinvestigates, approves and asks; never spends),
  `demo-trace` (the Visual Trace and the messages in the Management Portal, read only) and `judge` (the demo's role plus
  the live agents), each made only when its password is set. `SHUTTER_DAILY_BUDGET_USD` caps what the live runs spend
  per day, with an estimate reserved for each run in flight, and `SHUTTER_JUDGE_BUDGET_USD` gives each user a share; at
  the cap a run is refused `budget_exhausted` and the board takes the rules path. `GET /settings` says whether the live
  agents can run (`live.agents`). The demo's Management Portal is read only: its applications require `Shutter_Portal`,
  which `Shutter_Trace` alone holds.
- **The publisher:** Shutter's cases, incidents, evidence, plans, events, precedents and health as read-only MCP tools
  (`Shutter.Publish.Tools`) through IRIS's own MCP gateway at `/mcp/shutter`, on the AI Hub build; identifiers
  tokenised, an audit row per call, nothing written.
- **A case the workflow left behind can be abandoned.** The production's start notes every case still in a working state (an error-kind event saying when it started and the way out), and an approver abandons a case whose workflow has had nothing in flight for 15 minutes (`POST /cases/{id}/abandon`; 409 `busy` while it has, with what is in flight): the case fails with disposition `abandoned`, its approval is revoked, its pending escalation emails and open approval task are cancelled, and it can be reinvestigated. The Doctor and `GET /health` report `working_cases` and `abandon_after_minutes`.
- **A production review, on request.** `POST /api/shutter/production-reviews` runs one read-only pass over a production
  Shutter knows (its own, or a watched one such as the demo hospital's) through the new Case Review item:
  `Shutter.Util.ProductionReader` reads the production in its own namespace as plain data, and `Shutter.Review.Sweep`
  runs 23 checks (`Shutter.Review.Checks`) over the items' effective settings, resolved through the item, the default
  settings and the class default, the event log's errors grouped by signature, the suspended, aborted and errored
  messages, the queues, the rule log and the message purge task, over a window of 1 to 90 days, each finding tied to the
  cases Shutter opened for that item. The review is stored (`PR-000001`, the last 50 per production) with the findings in
  a deterministic order (severity tier, unique cases, recency) and a fingerprint of the configuration findings. One AI
  Hub agent, `Shutter.Agent.Review`, asked through the Agent Board item with a smaller budget than a board member's (3
  turns, 60,000 tokens), ranks the findings within their severity tiers and explains each in one or two sentences
  against the case history, seeing item names, setting values, counts and case ids only, never message content or a
  patient identifier; it has no evidence tools and one knowledge collection, the production review rules
  (`knowledge/review/production-review-rules.md`: what each check means, why it matters, the safer value and when it is
  intended), and it calls one typed tool, `SubmitReview`, whose schema refuses a ranking that repeats a finding or
  leaves a gap in the ranks. The agent never changes a severity, a count or a value, and a ranking that misses one of
  the review's findings or puts a lower tier above a higher one is refused: the deterministic order stands, as it does
  when the agent fails, has no recording to replay or is skipped. An approver marks a finding intended, an accepted risk or a false positive; the annotation binds the
  finding's exact effective value and reopens when the value changes, it expires or it is revoked. Nothing writes to
  the production. `GET /costs` lists the reviews' agent runs apart.
- **The case record is written only by its own transitions:** the plan, the gate decision, the agent run, the case
  token, the finding and the approval refer to their case by id, so saving one never writes the case whole, and the
  cases list reads each case's plan origin with the case ids in one query.
- **The boundary, tried over HTTP:** `tests/e2e/boundary_check.py` approves with another plan digest, a stale case
  version and as an operator, sends one approval twice with its Idempotency-Key and then reuses the key, approves S20
  after the nurse's move and lets rules alone resend S3, and checks each is refused with nothing written; CI runs it
  after the roles check, and the Evaluation page lists the attempts from `docs/readme/boundary.json`, which the script
  writes.
- **Install:** the `iris-shutter` IPM package (the whole of Shutter for an AI Hub build, IRIS 2026.3 or later) and the
  `iris-shutter-core` module (loaded by path on IRIS for Health 2026.2, where the board replays its recordings),
  `install.sh`, a Dockerfile and `docker compose up` (the image decides its edition itself, `WITH_AIHUB=auto`, and the
  demo users' password reaches the build as a BuildKit secret), and a site install into an existing production. The
  data databases live on the `shutter-mgr` volume, so a rebuilt image upgrades in place (`docs/INSTALL.md`, section 8),
  and `Shutter.Setup.Doctor` reports what an install or an upgrade left (`missing_items`, `disabled_items`, `edition`,
  `second_parser`, `credentials_ok`).
