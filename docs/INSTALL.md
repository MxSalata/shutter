# Installing Shutter in a hospital

Shutter is an IRIS Interoperability production that recovers failed HL7 ADT deliveries: a failed message becomes a
case, the evidence is collected, a plan is checked by a deterministic gate and approved by a person or by the site's
policy, and the result is verified at the receiver. This document is for the integration team that installs it beside
the productions a hospital already runs; the README's `docker compose up` is the demo.

## 1. In one page

- **The demo install is not a hospital install.** The image loads the `iris-shutter` module with `demo=1`: demo
  users, the demo bed-management system (`Downstream.*`), the scenario player, a namespace-wide message purge, and
  `Shutter.Production` as the auto-start production.
- **Shape A, recommended: Shutter in its own namespace, the hospital's productions hooked in.** The hospital's
  productions keep running untouched. A forwarder in each watched production hands Shutter a failed message over
  HTTP; Shutter stores its own copy, opens the case and records where the original lives.
- **Shape B: Shutter's items inside a production the hospital already runs**, in that namespace, through
  `Setup.InstallInto`. One production to look at, with Shutter's queues, settings and upgrades beside the hospital's.
- **Both start from a non-demo install** (`-Ddemo=0`): no demo users, no demo receiver, no credential, and no
  namespace-wide purge unless asked for. The feed, records and scenario items (`ADT In`, `ADT to Downstream`,
  `Downstream Out`, `ADT to Records`, `Records Out` and `Scenario Player`) are present but switched off in shape A (the
  installer disables them in `Shutter.Production`), and not added at all in shape B (`InstallInto`).
- **A receiver with no API is escalated, never resent.** Shutter resends only to a receiver whose site profile entry
  describes its API (state, receipt, capabilities and operations paths). A ward system that takes HL7 over TCP and
  keeps no receipts is investigated and escalated; the team corrects it by hand and marks the case handled.

## 2. What an install creates

- **The package.** `iris-shutter` (the repository root, published on IPM) is the whole of Shutter for an InterSystems IRIS AI
  Hub build: the core, the demo receiver's classes, and the live agents with their tools, policies, schemas and knowledge
  bases. Its manifest requires IRIS 2026.3 or later with Interoperability (the organisers' line: the agents need the `%AI`
  package, which the early access builds 2026.3.0AI.154.0 and 2027.1.0AI.109.0 have and 2026.2 has not), so
  `zpm "install iris-shutter"` on either installs everything and an earlier version refuses it.
- **The core alone,** for a plain IRIS for Health Community 2026.2 that replays recorded agent runs, is the module
  `iris-shutter-core` in the repository's `core/` folder: loaded by path (`zpm "load <repository>/core"`), never published;
  the image build loads one or the other by what the base image has (`WITH_AIHUB`). Without the agents the gate, the
  catalogue and the policy path work, and the board replays recordings.
- **What the manifests run.** Both run `Shutter.Setup.InstallStatus(root, demo, production)`, and the full package then
  `Shutter.Setup.InstallAIHubStatus(root)` (the provider configuration, the knowledge bases, the agent mode, the publisher's
  web application). A failed install stops the load.
- **The parameters.** `demo` defaults to 1, and `zpm "load /path/to/module -Ddemo=0"` installs without the demo; `production`
  (empty by default) names a production of the site's own to install Shutter's items into instead (section 4), as in
  `zpm "load /path/to/module -Ddemo=0 -Dproduction=Your.Production"`.
- **A packaged install** (an archive made by `zpm "package"`, the form the registry serves) carries the `knowledge/`,
  `fixtures/` and `www/` folders the install reads; IPM keeps the extracted module in its module root (its ModuleRoot setting,
  by default `<data directory>/ipm/iris-shutter/<version>/`), and `/shutter` serves `www/` from there. It needs IPM 0.10.4 or
  later: 0.10.0 to 0.10.3 delete the extracted module when the install ends, so the install refuses them and says so; a load
  from a folder works on any IPM.
- **On a plain instance** a load goes into the namespace you run it in (`USER` by default), and the demo install makes the
  rest itself: the `RECORDS` and `HOSPITAL` namespaces, the records system's web application and the hospital's production.
  It doesn't build the Second Parser's jar (below), so that item stays disabled and S25 is decided without its second
  opinion. `scripts/stock-install-check.sh` runs this path; CI runs it on 2026.2 with the core.
- **`zpm "uninstall iris-shutter"` removes the classes only.** The productions, the web applications and the two demo
  namespaces stay, so stop the production first, or remove the instance.

`Install` creates, in the current namespace, the folders under `<mgr>/shutter/`, the resources `Shutter_Operate`,
`Shutter_Approve` and `Shutter_Intake`, the roles `Shutter_Operator`, `Shutter_Approver`, `Shutter_WebApp` and
`Shutter_Forwarder`, the Workflow role "Shutter Approvers", the seeds, the web applications `/api/shutter` and
`/shutter`, the daily task "Shutter retention", the default settings, and `Shutter.Production`, started as the
auto-start production. The operator, approver, demo, judge and forwarder roles are granted SQL SELECT on Shutter's schemas
(`Shutter_Store`; all but the forwarder also `Shutter_Index`, `Shutter_Msg`, `Shutter_Bridge` and `Ens_Config`): the API
reads without privilege checks, but a cached query that has to be compiled again in the caller's process is checked
as the caller. Once the demo hospital is installed, the operator and approver roles also read its databases. With `demo=1` it also creates the demo users, the demo receiver's resource, role, user and
`/downstream/api`, the `DownstreamAPI` credential and the feed and demo items.

Environment variables read when the installer runs. Eleven of them, `SHUTTER_LIVE`, `SHUTTER_LIVE_SCENARIOS`, `SHUTTER_DEMO_PORTAL`,
`SHUTTER_DAILY_BUDGET_USD`, `SHUTTER_JUDGE_BUDGET_USD`, `SHUTTER_DEMO_BUDGET_USD`, `SHUTTER_DEMO_BUDGET_PERIOD`,
`SHUTTER_PROVIDER_TIMEOUT_SECONDS`, `SHUTTER_PUBLIC_DEMO_PASSWORD`, `SHUTTER_TRACE_PASSWORD` and `SHUTTER_JUDGE_PASSWORD`, are also
applied every time `Shutter.Production` starts (`Shutter.Setup.ApplyEnvironment`, from the production's `OnStart`, which reads exactly these), so in the
image they travel as container environment from `.env` through `docker-compose.yml`, need no build argument (a password in a
build argument would sit in the image's history), and a change takes effect on the next `docker compose up`; a variable that is
empty leaves the instance's setting as it is. `SELECT Shutter.Setup_ApplyEnvironment()` applies them by hand, for an instance
whose production is a site's own (shape B). The others are read once, while the image is built: the purge, the message days and
the escalation days as build arguments, and `SHUTTER_DEMO_PASSWORD` as a BuildKit secret (`docker-compose.yml` sources it from
the environment or `.env`; a plain `docker build` passes `--secret id=shutter_demo_password,env=SHUTTER_DEMO_PASSWORD`), so
neither the build log nor the image's history carries it; the build needs BuildKit, the default builder since Docker 23
(`DOCKER_BUILDKIT=1` before that). Unset, the default applies:

| Variable | Meaning |
| --- | --- |
| `SHUTTER_DEMO_PASSWORD` | The demo users' password (default `shutter`); demo only. |
| `SHUTTER_PUBLIC_DEMO_PASSWORD` | When set, the user `demo` exists with the role `Shutter_Demo`: reads, reinvestigates, approves and asks, and can neither run or reset scenarios nor save the site profile, the library or a schema. For a public demo; no default. |
| `SHUTTER_TRACE_PASSWORD` | When set, the user `demo-trace` exists with the role `Shutter_Trace`: the Visual Trace and the messages in the Management Portal, read only. No default. |
| `SHUTTER_JUDGE_PASSWORD` | When set, the user `judge` exists with the role `Shutter_Judge`: the public demo's role plus the live agents (live questions, convening the board), under the model budget and the judge's share. No default. |
| `SHUTTER_JUDGE_BUDGET_USD` | Each user's share of the day's model budget in US dollars (CONTRACTS 9): a user whose live runs today reach it is refused `budget_exhausted`. Empty or 0: no share, the day's cap alone. |
| `SHUTTER_PROVIDER_TIMEOUT_SECONDS` | The bound on one model call (CONTRACTS 6.6): the seconds the provider's HTTP client waits for a reply before the call fails, 10 to 600; default 120. Applied at every start of the production, like the budget. |
| `SHUTTER_DAILY_BUDGET_USD` | A cap in US dollars on what the agents' live runs may spend per day (00:00 to 00:00 UTC; CONTRACTS 9). At the cap, runs are refused with `budget_exhausted`, the board falls back to the rules path and the gate still judges the resend. Empty or 0: no cap. |
| `SHUTTER_DEMO_BUDGET_USD` | The budget the public demo's banner shows (what its owner spends on live runs), a figure in US dollars; it may be enforced outside Shutter while `SHUTTER_DAILY_BUDGET_USD` guards a burst. Unset, the banner shows the cap. Applied at every start of the production. |
| `SHUTTER_DEMO_BUDGET_PERIOD` | The period of that figure, `day` or `hour` (default `day`). Applied at every start of the production. |
| `SHUTTER_LIVE` | `1` turns on the live hospital (CONTRACTS 4.4): the demo hospital plays one of Shutter's scenarios every 7 minutes with fresh patients at present times and real faults, and sends an ordinary message a minute between stories, and the shipped profile's tier 2 single chains wait for an approval, so visitors have a case to approve. Demo only; off by default. `SELECT Hospital.Setup_SetLive(1)` in the HOSPITAL namespace switches it later. |
| `SHUTTER_LIVE_SCENARIOS` | The live hospital's rotation, scenario ids in order (default `S2,S8,S1,S23a,S3,S24,S15`; S11 is left to the storm and to a run on demand). `default` or unset keeps the player's own setting. Applied at every start of the production. |
| `SHUTTER_DEMO_PORTAL` | `1` makes the Management Portal read only at every start of the production (CONTRACTS 12 and 14.5: the portal applications lose their MatchRoles and require `Shutter_Portal`, which only the trace role holds), since that hardening lives in the instance, not the kept data, and a recreated container would come back with the portal open. For a public demo; leave it unset on a local install, where the approver's "In IRIS" links rely on the portal as IRIS made it. |
| `SHUTTER_MESSAGE_PURGE` | `1` creates the daily task "Shutter message purge" (`Ens.Util.Tasks.Purge`, every message type in the namespace). On by default in the demo, off otherwise: only a namespace that holds nothing but Shutter should purge this way. |
| `SHUTTER_MESSAGE_DAYS` | Days the purge keeps (default 90). |
| `SHUTTER_ESCALATION_DAYS` | Days after a case closes before the daily task "Shutter retention" removes the text of its escalation emails (the hospital number, the NHS number and the date of birth) and their `.eml` files; the rows stay with their digest, recipients and who sent them. Default: `SHUTTER_MESSAGE_DAYS` (90); `0` keeps them. An instance upgraded in place runs the default, 90, until the task's `EscalationDays` is changed in the Task Manager. |

The production's name comes from `^Shutter.Config("production")`, which `InstallInto` records (default
`Shutter.Production`); the health report (`GET /api/shutter/health`) and the readiness report (`Shutter.Setup.Doctor`)
read it.

**The Second Parser** (CONTRACTS 6.7) is a Java component: the production item "Second Parser" runs HAPI through PEX to give a
second opinion on a message IRIS cannot read. The Docker image builds it (`pex/build.sh`: the jars from Maven Central with
pinned SHA-256 checks, compiled against the IRIS image's own PEX framework jar and JDK into the manager directory's
`pex/`, outside the data volume; the step never fails the image, it skips with the reason where something is missing). On an instance you
install by hand, run `pex/build.sh` once with Java 11 or later on the machine, then run the install again or enable the item;
without the jar the install leaves the item disabled, the evidence carries no second opinion and the Doctor's `second_parser`
says so. Nothing else depends on it.

## 3. Shape A: Shutter in its own namespace

**3.1 The namespace.** Before the module is loaded nothing of Shutter's is on the instance, so load the one class that makes
a namespace first, from any namespace, and make it there (`$SYSTEM.OBJ.Load("<module>/src/Shutter/Setup.cls", "ck")`, then
`Write ##class(Shutter.Setup).CreateNamespace("SHUTTER")`): its database goes under `<mgr>/shutter/`; a site that wants the
data on storage the trust backs up makes the namespace and its database in the Management Portal instead, with
Interoperability on. `src/Shutter/Installer.cls`, as the image uses it, also makes the demo's namespaces, so it is not for a
site. IPM (`zpm`) is per namespace and a stock image has none: load `vendor/ipm/zpm-0.10.10.xml` in the new namespace with
`$SYSTEM.OBJ.Load`. Load the module with `-Ddemo=0`: `Shutter.Production` starts with its feed, records and scenario items
disabled (the six named in section 1), so it has no feed of its own until the intake route or the site's own items bring it
one. **Load only in the namespace made for Shutter.** A load in a namespace running another production is refused and says
so, since starting `Shutter.Production` there would stop it; name that production (`-Dproduction=...`) for shape B.

**3.2 The hook.** A failure reaches Shutter through `POST /api/shutter/intake`. The caller signs in with HTTP Basic
authentication as a user holding `Shutter_Forwarder` (the resource `Shutter_Intake`), sends the header
`X-Requested-With: Shutter`, and the body:

```json
{"source": {"namespace": "HOSPITAL", "production": "Hospital.Production", "route": "PAS In", "header_id": "123"},
 "receiver": "Downstream Out",
 "failure": {"kind": "delivery_failed", "text": "...", "outcome": "unavailable", "http_status": 503,
             "reason_code": "ward_unavailable"},
 "message": "<the HL7 text, segments separated by carriage returns>",
 "schema_category": "2.5.1"}
```

`kind` is `delivery_failed`, `rejected`, `uncertain_outcome` or `unmappable`; `outcome` is `unavailable`, `error`,
`uncertain`, `rejected` or empty; `schema_category` is optional (2.5.1). The answer is 202
`{"caseId": "C-000012", "state": "...", "opened": true}`, 400 `bad_request` (not a JSON object, no message, an unknown
kind), 401, 403, or 503 `no_service` when the production is not running. Shutter stores its own copy of the HL7
message, so the evidence, the model view and the index work as in the demo, and the case carries `SourceNamespace`,
`SourceProduction`, `SourceRoute` and `OriginHeaderId`.

The forwarder, `Shutter.Intake.Forwarder`, is a business operation for the watched production: its adapter settings
name Shutter's server, port, URL (`/api/shutter/intake`), SSL configuration and the credential of a user holding
`Shutter_Forwarder`. Section 9 adds it, the alert intake and everything they need for you. The hospital's HL7 process calls it on a failed delivery with the failed message's header id, the
receiver's item name, the outcome and the receiver's answer; the class documents the call.

The alert intake needs no change to the hospital's own code. `Shutter.Intake.AlertProcess`, added as the watched
production's `Ens.Alert` item (the name the engine sends its alerts to), receives every alert an item raises and passes
it first to `PassTo`, the site's own alert consumer renamed, so Shutter adds to the production's alerting and never
replaces it. For an alert from one of its `Receivers` whose session holds an HL7 message, it hands that message to the
forwarder (`docs/CONTRACTS.md`, section 11).

**3.3 The index.** Shutter's exact index (the "HL7 Index" item) is per namespace: in SHUTTER it covers the messages
Shutter stores, so a case's timeline shows what the intake brought. An index of a watched production's whole feed,
readable from SHUTTER, is not in this version.

**3.4 The receivers.** Each system Shutter should recover is a receiver entry in the site profile: its name (the
production item that delivers to it), tier, what it takes (cancels, merges) and its API paths. For a system with no API,
such as a plain MLLP receiver, declare its `features` all false and leave `api` out. There is then no read-back, no
receipt lookup and no resend: the gate blocks any write, and the case holds the evidence and the reason nothing was
sent. Nothing goes out by itself: a person reads the case on the Cases page, and its page drafts the email for the team
that owns the system. A receiver you do give an API needs a connector of its name in Shutter's production and the credential
it signs in with (section 9, "Giving a receiver its API"). On a site install a receiver the profile does not name at all
reads as one with no API: nothing is resent to it. `tests/e2e/plain_receiver_check.py` plays this on a stock `EnsLib.HL7.Operation.TCPOperation`,
down and answering AE.

**3.5 Security and operations.** Only holders of `Shutter_Forwarder` can open cases; the web application keeps its
roles. Escalation mail goes through the `Escalation Mail` operation's `SMTPServer` setting; unset, it writes `.eml`
files under `<mgr>/shutter/out/mail`. The daily task "Shutter retention" removes the text of each escalation email
and its `.eml` file `SHUTTER_ESCALATION_DAYS` days after the case closed (section 2); the row stays with its digest,
the recipients and who sent it. A case the workflow left in a working state (after a container killed in the middle of its
work) is noted when the production starts, and an approver abandons it with `POST /cases/{id}/abandon` once nothing of
its workflow has moved for `abandonAfterMinutes` (15 by default; 409 `busy` while something has).

**3.6 The production review.** `POST /api/shutter/production-reviews` (an operator's; CONTRACTS 13) runs on request
only, never at the production's start, in the Doctor or on a timer: one read-only pass over a production's effective
settings, event log errors and failed messages over a window of 1 to 90 days, tied to the cases Shutter opened for it.
It runs in a production job (the Case Review item), so it reads the production, the watched namespace and the message
purge task in `%SYS` as the production's own user, not as the signed-in caller, and it needs nothing configured: the
targets are Shutter's own production and every watched one Shutter knows (`GET /api/shutter/production-reviews/targets`),
each read in its own namespace, as the demo hospital's `Hospital.Production` is read in HOSPITAL. It changes nothing in
a production; a person applies any change in the Management Portal. Marking a finding intended, an accepted risk or a
false positive is an approver's annotation (`POST /api/shutter/production-reviews/{id}/annotations`), bound to the
finding's exact value: it reopens when the value moves, when it expires or when an approver revokes it.

**The worked example: Hospital PAS.** The demo image carries a second, tiny production in its own namespace, the
hospital's side of shape A: an HL7 service (`PAS In`), a delivery (`Downstream Out`) that fails, and the forwarder. Its
failures appear as cases in Shutter's own production in SHUTTER, each recording where the original lives; nothing in
that production is stopped, purged or rerouted.

## 4. Shape B: Shutter's items inside an existing production

Load the module's classes into the production's namespace without the demo installer
(`$SYSTEM.OBJ.LoadDir("/path/to/module/src/", "ck", , 1)`), then
`SELECT Shutter.Setup_InstallInto('Hospital.Production', '/path/to/module/')`. It refuses an empty or unknown
production name, and then:

- records the name in `^Shutter.Config("production")` and runs the namespace-level parts of a non-demo install (no
  demo users, no demo receiver, no credential, no message purge: the trust's own purge rules stand);
- adds Shutter's recovery, index, intake and board items to the production when it has none of that name, each as
  `Shutter.Production` defines it (the agent operations when their class is compiled); never the feed or demo items;
- writes the default settings keyed to that production (the receiver's address goes to Shutter's own items, not the
  trust's), saves the definition and, when the production is running, calls `Ens.Director.UpdateProduction()` so it
  takes the items without a stop; a stopped production is left for the site to start.

It never stops a production and never changes the auto-start production; run again after an upgrade, it adds the
items that are new. The hook is in-production: the hospital's HL7 process sends `Shutter.Msg.CaseIntake` to "Case
Workflow", or the forwarder posts to the same instance's intake route. The `HL7 Index` item's `Routes` names the
trust's HL7 services.

## 5. The steps for the integration team

Shape A:

1. On the integration server, create the SHUTTER namespace with its data database on backed-up storage.
2. On an AI Hub build, `zpm "install iris-shutter"` with `-Ddemo=0`, or `zpm "load <repository> -Ddemo=0"` by path (the provider
   key in the environment); on a plain 2026.2, `zpm "load <repository>/core -Ddemo=0"`. IPM goes in that namespace first (3.1).
   Check `/api/shutter/health`.
3. Map the trust's users to `Shutter_Operator` and `Shutter_Approver`; add the approvers to the Workflow role; create
   the forwarder's user with `Shutter_Forwarder`. An operator escalates a case (the escalation is the sign-off),
   marks it handled once the team has corrected the systems and starts a production review (3.6); an approver also
   approves plans and incident releases, saves the site profile, changes the agent library and marks a review's
   finding intended. A trust that wants only an approver to close a case handled
   by hand answers yes to "Closing a case by hand needs an approver" in the site profile
   (`approvers.close_needs_approver`). Shutter checks the role of whoever closes the case, not that a second person
   does: an approver may escalate and close the same case. An approver who decides in the Management Portal's Workflow
   inbox pastes the plan digest from the task's message (it is **Plan digest** on the case page too) into its `PlanDigest` field (the field starts empty, and an
   approval without it, or with another digest, blocks the case; the recovery is a reinvestigation); the web
   application sends it for them. Whoever approves must hold `Shutter_Approve` and be a member of the Workflow role
   "Shutter Approvers": a holder outside the role is refused (403).
4. Fill in the site profile (the web application's questionnaire): receivers, tiers, what each takes, API paths or
   none, the policy per tier, teams and mailboxes, and the mail domains they must lie in (`mail.allowed_domains`: every
   team mailbox and every address a person types must be one bare address in one of those domains or under one; with
   no domain set no email can go, and a profile that names a team mailbox without one is refused, so replace the
   shipped `example.nhs.uk` with the trust's; a profile saved before this rule that names teams and no domains sends
   nothing until an approver saves the list), the feed's time zone, `merges: forbidden`.
5. Set the `Escalation Mail` operation's SMTP server.
6. Onboard each watched namespace (section 9), which adds the forwarder and the alert intake. If your own process delivers
   and you want it to report failures itself, call the forwarder from it on a failed delivery. With the site profile's "prevent failures" on (section
   7): where a routing engine routes the feed, set its `Validation` (`dm`) and its `BadMessageHandler` to the forwarder
   item, and the forwarder's `HeldReceiver` to the receiver it feeds, so a message the engine cannot read against its
   schema reaches Shutter as a held case instead of sitting in a bad-message queue; where your own process delivers, have
   it check `Shutter.Util.Schemas.Known` on each message's category and send an unknown one to the forwarder as
   `Shutter.Intake.Forwarder.ForwardFor` builds it, as the demo hospital's `Hospital.Process.PASToDownstream` does.
7. Replay a known failure in a test environment: a case opens in SHUTTER, the evidence shows the message and the
   receiver's state, and the escalation draft names the right team.
8. Switch the investigation mode to `policy` for the easy chains once the catalogue's entries are reviewed; watch the
   first weeks on the Settings and costs page and in the Doctor report (`SELECT Shutter.Setup_Doctor()`).

Shape B: section 4 in place of steps 1, 2 and 6; the rest as above.

**To try step 2 on a stock instance first** (Docker, a clone of this repository, nothing of the hospital's): this loads the core on a plain IRIS for Health, in `USER`, with no demo, and ends with the health report saying `"ok":true`.

```sh
docker run -d --name shutter-site -p 127.0.0.1:52773:52773 \
  containers.intersystems.com/intersystems/irishealth-community:2026.2 --check-caps false --ISCAgent false
until docker exec shutter-site iris qlist IRIS 2> /dev/null | grep -q '\^running'; do sleep 5; done; sleep 5
git archive HEAD | docker exec -i -u root shutter-site sh -c \
  'mkdir -p /home/irisowner/pkg && tar -xf - -C /home/irisowner/pkg && chown -R irisowner:irisowner /home/irisowner/pkg'
docker exec -i shutter-site iris session IRIS -U USER << 'EOF'
Do $SYSTEM.OBJ.Load("/home/irisowner/pkg/vendor/ipm/zpm-0.10.10.xml", "ck")
Do ##class(%IPM.Main).Shell("load /home/irisowner/pkg/core -Ddemo=0")
Halt
EOF
curl http://localhost:52773/api/shutter/health
```

The web application is then at http://localhost:52773/shutter/index.html; it has no demo users, so step 3 comes first. `docker rm -f shutter-site` removes it all. `scripts/stock-install-check.sh containers.intersystems.com/intersystems/irishealth-community:2026.2 core --no-demo` does the same and checks that the production runs.

## 6. What stays the same in both shapes

The case, the evidence, the matcher and the catalogue, the gate, approvals and incidents, the escalation by email, the
model view, the REST API and the web application are namespace-local code with settings for the names they need. Only
the scenario player, the demo receiver, the demo users and the store purge (refused on a non-demo instance) know the
demo.

## 7. Using your site's custom schema

A site's feed often carries its own HL7 schema: a local variant of 2.5.1 with Z segments, or a category exported from the
source system's IRIS. Shutter validates each message against the category its route named (the service's
`MessageSchemaCategory` in your production; the message's `DocType` when the hospital's production forwarded it), so that
category has to be loaded in Shutter's namespace too.

- **See what is missing.** `SELECT Shutter.Setup_Doctor()` has an `hl7_schemas` section: `loaded` (the categories this
  namespace holds), `needed` (every `MessageSchemaCategory` your productions' items name, the categories of the newest
  messages in the store, what the services of each watched namespace name that Shutter lacks, and any category a forward
  named that was not loaded, each with where it came from and whether it is known) and `missing`. The same answers
  `GET /api/shutter/settings/schemas`.
- **From a watched namespace on this instance,** the apply of section 9 imports what its services name, and it never
  replaces a schema: a category of that name holding something else here is imported under an alias, and that namespace's
  forwards are read by the alias. By hand: `Do ##class(Shutter.Util.Schemas).ImportFrom("PATHOLOGY", "TRUSTLAB")`.
- **Load it.** Export the schema from the source system's Management Portal (Interoperability, Interoperate, HL7 v2.x,
  HL7 v2.x Schema Structures, Export) or write it, copy the `.xml` onto Shutter's server, and run
  `SELECT Shutter.Setup_ImportSchema('/path/to/schema.xml')` as an approver, or `POST /api/shutter/settings/schemas`
  with `{"path": "/path/to/schema.xml"}`. It is IRIS's own importer (`EnsLib.HL7.SchemaXML`): nothing else changes, except
  that a category of the same name is replaced whole and with no warning, so check the name first.
- **What a case says meanwhile.** A message whose category is not loaded is not called invalid: its evidence says
  `unknown schema` with the category and the fix, and the gate blocks any write with `SCHEMA_UNKNOWN`. Once the schema is
  loaded, reinvestigate the case from its page; the fresh evidence reads the message under that category and the case goes
  on. A forwarded message keeps the category it named, and is read as 2.5.1 only for its identity until then.
- **Prevent failures.** An interface deployed without its schema does not fail loudly: IRIS still reads the message by
  position, so every field can come from the wrong place and the receiver gets a silent stream of wrong data. Answer yes to
  the site profile's last induction question ("Should Shutter hold the feed when a message arrives whose HL7 schema is not
  loaded here, until the schema is imported?", `feed.prevent_failures`) and Shutter holds such a message instead: a case of
  kind `unreadable` opens with the headline "Held: the schema X is not loaded here ...", nothing is delivered, the gate
  blocks it `SCHEMA_UNKNOWN`, and the Doctor's `held_messages` (and the app's Settings page) list the held categories. Import
  the schema as above and set the inbound item's category: within seconds the index's check releases the case, the fresh
  evidence reads the message under its schema, and the resend goes out under your policy and approvals. The setting is off
  by default and in the shipped profile. In the demo, the hospital's `PAS to Downstream` follows it (it checks each message's category
  and hands a held one to the forwarder); in your own productions, step 6 of section 5 says what to set up.
- **Shape B.** When Shutter's items live in your own production, the HL7 service is yours and its category is already
  loaded there; the check still matters for messages forwarded from other namespaces.

## 8. Upgrading in place

The image keeps Shutter's code; the `shutter-mgr` volume keeps the data: the data databases of the SHUTTER, HOSPITAL and
RECORDS namespaces under `db/`, and the HL7 folders. So `docker compose down` and `up` keep every case, approval, review,
profile change and recording, and a rebuilt image (a newer Shutter) starts against the same data. Proven on 1 November 2026:
a 26 October build played two scenarios and a review, the container was removed and started again (the cases stayed), then
the image was rebuilt at that day's main over the same volume (the cases, their plans, approvals and the review stayed, the
new catalogue entries, recordings, gate policy and the Second Parser were there, and new scenarios played).

After a rebuild, run the install once inside the new container, which re-reads the production's definition and the seeds
into the kept data and is safe to repeat:

```sh
printf '%s\n' 'Set r = ##class(Shutter.Setup).Install("/home/irisowner/dev/", 1) Write !,"RESULT: ",r,!' 'Halt' \
  | docker compose exec -T shutter iris session IRIS -U SHUTTER
printf '%s\n' 'Set r = ##class(Hospital.Setup).Install("SHUTTER") Write !,"RESULT: ",r,!' 'Halt' \
  | docker compose exec -T shutter iris session IRIS -U HOSPITAL
```

Each prints the installer's progress (the production's start writes to the terminal too) and then, on a line of its own,
`RESULT: ok`; anything else after `RESULT:` is the error text, and the install stopped there. The `Write` is what shows the
result: `Install` returns `ok` or the error as a string, so a bare `iris session IRIS -U SHUTTER "##class(Shutter.Setup).Install(...)"`
runs it and shows nothing of the outcome. (Or `SELECT Shutter.Setup_Install('/home/irisowner/dev/', 1)` in SHUTTER and
`SELECT Hospital.Setup_Install('SHUTTER')` in HOSPITAL from any SQL tool, each answering `ok`; the second is for the demo
hospital, a demo install only; a site install uses `demo` 0 and its own root.) The install recompiles each production's
class in its namespace, so items that are new in the image reach the kept production definition, then updates the running production, seeds what is new and leaves what is there. Then
`SELECT Shutter.Setup_Doctor()`: `missing_items` and `disabled_items` must be empty, and the rest says what the instance
has. Images built before 1 November 2026 kept the SHUTTER data database at the install directory, outside the volume (the
installer's `DATADIR` was a name `%Installer` reserves); on such an instance the cases live in the container and go with it,
so take what you need from it before replacing it, or copy `/usr/irissys/IRIS.DAT` out, create the database under
`mgr/shutter/db/SHUTTERDATA` and mount it there.

## 9. Onboarding several namespaces

A trust's integration engine is often several namespaces: order communications and the LIMS in one, documents in another,
the PAS feed in a third. Shutter sits in its own namespace (shape A) and each of those is onboarded on its own, in minutes,
with its production running throughout. `tests/e2e/onboard_check.py` plays this whole section on a stock instance, on five
namespaces with stock classes.

**What you get per namespace.** A failed delivery in that namespace opens a case in Shutter, with where it came from. What
happens next depends on the receiver: ADT to a receiver whose API you describe can be recovered; **every other message type
(ORM, ORU, OML, MDM and the rest) and every receiver with no API escalates with its evidence, and nothing is resent.** A
Pathology or Documents namespace gets a durable case and a drafted email per failure, not a recovery (section 10).

**Each step is an SQL call or a terminal line, in Shutter's namespace, as a user holding `%Admin_Manage`** (`_SYSTEM`, or a
terminal session on the server). Options are one JSON object. Answers are JSON.

**Before you start, for each receiver: know what a green message means there.** A completed message does not always mean the
message was processed. **A message accepted by a transport ACK and then lost downstream raises nothing in Shutter today.** Section 9.9 says
which level you get, what was measured on a stock operation, the settings, and how to bring in acknowledgements that arrive on a feed of
their own.

**9.1 Read the plan: this changes nothing.**

```sql
SELECT Shutter.Setup_OnboardPlan('PATHOLOGY')
```

It answers the running production; its HL7 services, routers and operations; each schema category the services name, whether
that namespace and Shutter have it and what would be done; what is wired already; and:

- `actions`: exactly what the apply would do, one line each, in the order it would do them;
- `todo`: what only a person can do;
- `warnings`: what you should look at first (two items named `Ens.Alert`, a category not even loaded in that namespace);
- per item in `operations`: `get_reply`, `reply_code_actions`, `alert_on_error`, and `proves`, one plain line on what a completed
  message proves there (9.9).

Options, for this call and the apply alike: `production` (when several exist and none runs), `shutter_host` and `shutter_port`
(the forwarder's target: 127.0.0.1 and this instance's web server port by default; on a licensed instance give the Web
Gateway's), `ssl_config`, `credential` (default `ShutterIntake`), `receivers` (a comma-separated list of items in place of
the namespace's stock HL7 operations, for a site whose connector is its own class; `other_operations` in the plan lists those)
and `alert_on_error` (below).

**9.2 Apply it.**

```sql
SELECT Shutter.Setup_OnboardApply('PATHOLOGY')
SELECT Shutter.Setup_OnboardApply('DOCUMENTS', '{"alert_on_error": true}')
```

It does what the plan listed and nothing else, answers `changed`, and run again answers "Nothing to do". It never stops a
production: a running one is updated, and only the items it changes restart. In order:

1. Maps `Shutter.Intake` and `Shutter.Util` into that namespace from Shutter's code database, unless the classes already
   resolve there.
2. Imports each custom category the services name into Shutter's namespace, by IRIS's own export and import. The same schema
   already there needs nothing. **A different one of the same name is imported as `<NAMESPACE>_<CATEGORY>`**, since IRIS's
   importer would replace the other namespace's whole; that namespace's forwards are then read by the alias.
3. Adds the item `Shutter Forwarder`, naming the credential and never holding a password.
4. Renames the site's own `Ens.Alert`, if it has one, to `Site Alerts`, and adds `Shutter.Intake.AlertProcess` as `Ens.Alert`
   with `PassTo` set to it, so every alert still reaches it first, and `Receivers` set to the HL7 operations. Two items named
   `Ens.Alert` compile and start, and the engine silently uses one: the plan warns, and adds none until you have renamed one.
5. Turns `AlertOnError` on for those operations **only if you passed `alert_on_error`**: it is your item's setting, and the
   alert intake hears nothing from an operation with it off. `todo` names the ones affected.
6. Drafts a site profile entry for each operation: tier 3, no API, every feature false, marked `draft`, in one new version of
   the profile. **Nothing can be resent to a draft**: the gate blocks any write and the case escalates. An entry that already
   exists is never touched.

**The same name in two namespaces.** Shutter's site profile has one list of receivers, and a case is matched on its operation
and its receiver, so two namespaces' `Results Out` under one name would pool their cases and incidents. When a name is taken,
the apply sets the forwarder's `ReceiverPrefix` to the namespace, so DOCUMENTS' item is reported and listed as
`DOCUMENTS Results Out`. The item in your production keeps its name. To see it, read `reported_as` in the plan.

**9.3 Give the forwarder its sign-in.** In a terminal, in Shutter's namespace:

```
Do ##class(Shutter.Setup).OnboardCredential("PATHOLOGY")
```

It asks for the password with the echo off, creates the user `shutter-fwd` with only the role `Shutter_Forwarder` and a password that does not expire (a lapsed one would turn
every forward into a refused one) when that user does not exist, stores the credential `ShutterIntake` in that namespace, and prints no password. For a user that exists
it first checks that the password signs in, and stores nothing if not, so one forwarder user can serve every namespace. It is
not an SQL procedure, so no password passes through a statement. In a script, pass the user and password as the second and
third arguments.

**9.4 Send a test failure.**

```sql
SELECT Shutter.Setup_OnboardTest('PATHOLOGY')
```

It posts a made-up ORU, with no patient, using that namespace's forwarder settings and its stored credential, and answers the
case id. The case says `ONBOARDING TEST` and its receiver is `Onboarding test`, which no profile names. An ORU has no recovery,
so it escalates with no model called and nothing sent. Mark it handled. A failed test says what to check:

| Answer | Meaning |
| --- | --- |
| `http_status` 404 | The sign-in was refused: IRIS answers a refused password this way on a REST application, not with 401. Check the credential and the user's password. |
| 403 | The user signed in and lacks `Shutter_Forwarder`. |
| 503 | `Shutter.Production` is not running. |
| empty, with an error | No answer: check `HTTPServer` and `HTTPPort` on `Shutter Forwarder`. |

The test proves the address, the password and the role. It does not prove the alert path: for that, fail a real delivery in a
test environment (section 5, step 7).

**9.5 Check it.** `SELECT Shutter.Setup_Doctor()` has `watched_namespaces`, one entry per namespace onboarded or named by a
case: `production`, `production_state`, `forwarder`, `alert_intake`, `pass_to`, `classes`, `credential`, `last_forward`,
`last_forward_error`, `refused_72h`, `last_refused`, `last_case`, `schemas_missing`, `operations_unwatched`, `removed`, `problems`
in words and `ok`. `last_forward_error` is the last forward only, and the next good one clears it; `refused_72h` counts every refused
forward over three days, so a daily read still sees a lost failure. `operations_unwatched` lists HL7 operations added since the last
apply, whose failures reach the site's consumer and open no case: run the plan and the apply again. A namespace taken off reads
`removed` and has no problems. `credentials` tries each namespace's stored
sign-in. `hl7_schemas.missing` includes what a watched namespace's services name.

The web application is at `/shutter/index.html`; `/shutter` and `/shutter/` answer 404.

**9.6 Fill in the receivers.** In the app's site profile (an approver's), review each draft: its system, category
(`current_state`, `history_of_record` or `orders_results`), tier and team, and remove `draft` when you save. Use the name the
draft has: in a second namespace every item is reported with its prefix (`DOCUMENTS DMS Out`), including those that clash with
nothing, so a team's `receivers` must say that. Through the API, `GET /api/shutter/site-profile`, change its `profile`, and
`PUT` the whole of it back with the header `X-Requested-With: Shutter`; a part alone answers 400. A receiver with no API stays declared as it is, and its failures escalate to its team.

**Giving a receiver its API.** Only a receiver with state, receipt, capabilities and operations paths can be recovered. Add
them in the profile, then, since Shutter writes through a connector item of that receiver's name in its own production:

```sql
SELECT Shutter.Setup_OnboardReceiverItem('Bed Mgmt Out', 'beds.example-trust.nhs.uk', '443', 'DownstreamAPI', 'MySSLConfig')
```

The Doctor's `receivers_without_item` lists any receiver that needs this; a case for one otherwise fails with "not registered to
run". The item is recorded, so a load or an upgrade puts it back. Set the credential in Shutter's namespace
(`Do ##class(Ens.Config.Credentials).SetCredential("DownstreamAPI", "<user>", "<password>", 1)`), which on a site install does
not exist until you do. **One limit stands:** Evidence Collector and Verifier call one server, so every receiver with an API must
answer on the same host and port in this version; the call warns when a second one differs.

**9.7 Take a namespace off.**

```sql
SELECT Shutter.Setup_OnboardRemove('PATHOLOGY')
SELECT Shutter.Setup_OnboardRemove('PATHOLOGY', '{"unmap": true, "credential": true}')
```

It removes what the apply added: the two items, and the site's item gets the name `Ens.Alert` back, `AlertOnError` goes back,
and the drafts still marked `draft` leave the profile. The production is updated, not stopped. It answers `removed` and `kept`.
Kept: Shutter's cases and the imported schemas; an entry a person edited; the credential and the user, unless `credential`; and
the mappings while that namespace still holds messages of Shutter's classes, since its own purge must open them. Purge first, then
run it again with `unmap`. `unmap` does not refuse if you have not: it takes the mappings anyway and says how many messages were
left. Those messages' bodies then stay for good: with 12 left, the purge answered no error, removed every header, and left 12 rows in
`^Ens.MessageBodyD` whose class no longer resolves.

**On another instance.** A watched namespace on a separate instance cannot take a mapping, and these calls read only their own
instance. Load `src/Shutter/Intake/` (Forward, Forwarded, Forwarder, AlertProcess, AckMatch) and `src/Shutter/Util/Json.cls`, `Schemas.cls` and
`Time.cls` there, add the items by hand with `HTTPServer` naming Shutter's host, and create the user on Shutter's instance. A
partial load compiles and starts, and fails only on the first forward. Not supported yet: a production review of another instance,
and releasing a held case from it (`KnownIn` reads only this instance).

**9.8 Rarer things you may see.**

| What you see | What it means | What to do |
| --- | --- | --- |
| `ZPM "version"` then `<SYNTAX>` | No IPM in this namespace | Load `vendor/ipm/zpm-0.10.10.xml` there |
| `<CLASS DOES NOT EXIST>getProductionItems+51^Ens.Director.1 *Shutter.Intake.AlertProcess` | Items added by hand with no mapping | Use the apply |
| Event log: `HTTP 413 from Shutter ... too_large` | Over 2 MB. No case | No way round it yet |
| `ErrNoCredentials ... 'DownstreamAPI'`, gate `RECEIVER_UNREADABLE` | A site install has no such credential | `SetCredential`, then reinvestigate |
| Page says "Round 2: the receiver changed after the approval" with no approval given | Wrong words after a reinvestigation | Ignore them |
| "Source message" link: `ERROR #5809` | The link's URL form is wrong, and it opens Shutter's copy | Add `HeaderClass=Ens.MessageHeader&` to the URL |
| `Second Parser ... ClassNotFoundException` | As far as I can tell, its jar is not built | `pex/build.sh`, or leave it. Nothing else depends on it |
| `ErrInNoConnectionPort`, or `#6030 'From' property` from `Site Alerts` | Stock service noise, or your own mail settings | Not Shutter's |

**9.9 What a green message proves here.** Shutter hears of a delivery that failed as the engine sees it. A message the engine completed is
not a failure, whatever happened after. For each receiver, find out which of these you have, and put it in the receiver's notes:

| Level | What a completed message means | Where it shows |
| --- | --- | --- |
| None | It was written to the connection | `get_reply` false |
| Transport or commit | The receiver's listener or its integration engine took it. Its application may still refuse it, or the engine may fail it further on | `MSA` `CA`, or `AA` from an engine that answers on receipt |
| Application | The application itself accepted it | `AA` from the application, on the connection or on a feed of its own |
| Read-back | Someone read it back from the receiver | Not an ACK: a receiver with an API, whose history Shutter reads after a write |

The settings cannot tell the second level from the third: **ask the receiver's supplier what its positive ACK means**, and whether a later failure comes
back, and where. An integration engine in front of an application commonly accepts for it. A stock IRIS TCP service does so too: with its defaults
(`AckMode` Immed, `UseAckCommitCodes` on) it answered `CA` in every run here, even to messages whose delivery then failed.

Settings to read: on the operation, `GetReply` (the TCP adapter's, default on), `ReplyCodeActions` (empty means the engine's default
`:?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C`), `AlertOnError`, and `SaveReplies` to keep the replies. On a service, `AckMode`, `UseAckCommitCodes` and
`IgnoreInboundAck`. The plan gives the first three per operation, each as the value that applies, and `proves`. A class of your own with its own
`OnGetReplyAction` decides for itself, which the plan does not read. The production review reports `REPLY_CODES_LENIENT` (a negative code treated as
sent) and `REPLY_CODES_SUSPEND_UNWATCHED` (a negative code suspends and nothing alerts).

**What was measured.** `tests/e2e/onboard_check.py` sends one message to three stock TCP operations and a listener that answers by the message's
control id, with `AlertOnError` on, `FailureTimeout` 0 and `ResponseTimeout` 3. The status is the message header's, on 2027.1 build 109 and on 2026.2:

| The listener | Stock codes | `GetReply` off | `:AA=C,:CA=S,...` |
| --- | --- | --- | --- |
| AA | Completed | Completed | Completed |
| CA | **Completed** | Completed | Suspended, alert |
| AE or CE | Suspended, alert | **Completed** | Suspended, alert |
| AR or CR | Error after the retry, alert | **Completed** | Error after the retry, alert |
| A reply with no MSA | Suspended, alert | **Completed** | Suspended, alert |
| No reply | Error, alert | **Completed** | Error, alert |
| Closes with no reply | Error, alert | **Completed** | Error, alert |
| CA, then AE on the same connection | **Completed** | Completed | Suspended, alert |

- **`?A` means what it says: AA and CA read alike.** On the stock codes a commit ACK completes a message exactly as an application ACK does.
- **An AE that follows a CA on one connection is lost.** The operation reads the first reply only, and before the next send it throws away the second
  with one warning in the event log ("Discarding data found in buffer before HL7 send"). The message stays Completed and nothing alerts.
- **`GetReply` off awaits nothing.** Every code reads as complete. It is worse than that after a dropped connection: when the listener closed the
  connection, the next message read Completed and **never reached the listener**, and only the one after that failed on the write.
- **Setting `:CA=S` does not make the engine wait for an application ACK.** It suspends every message a receiver answers with CA, and each raises an alert
  and, once onboarded, opens a case. Use it only with a receiver that answers AA from its application on the connection.
- **What opens a case.** Only what does not complete and raises an alert. An AE on the connection was suspended and its alert opened a case. Every
  bold cell in the table raises nothing.

**An application ACK on a feed of its own.** Some receivers answer the connection at once and send their AA, AE or AR later, as a message of their own, to a
service in your namespace. The engine has completed the message by then, and stock IRIS does not relate one to the other. To bring the negative ones in,
`tests/e2e/onboard_site/` has a worked example you can copy (`OnbAck.Production.cls`, `OnbAck.AckProcess.cls`):

1. **The service for the feed:** a stock HL7 service with **`IgnoreInboundAck` off** and `AckMode` `Never`. Measured: with the stock `IgnoreInboundAck` on,
   an AE on that service was dropped, no header reached its target, and no case opened.
2. **A small process as its target,** naming in `Receiver` the item that delivered. On each message it calls
   `##class(Shutter.Intake.AckMatch).ForwardFor(request, ..Receiver, .problem, .session)`. An answer goes to `Shutter Forwarder` with `SendRequestAsync`; a
   `problem` goes to your alerts; and `OnResponse` tells `AlertProcess.ForwardAnswered`. It is about twenty lines. `AckMatch` comes with the mapping the apply
   makes, so apply first.
3. **Test it:** send a message, and send its AE to the feed.

Measured, on a namespace onboarded as above, with a listener answering CA and an ORM sent through it:

| On the feed | Result |
| --- | --- |
| Nothing at all | The message reads Completed. No case |
| AA or CA | The process takes it and does nothing |
| AE | A case on the receiver, with the service as its route, `originHeaderId` the header of the message the AE answered, and the text "The receiver's acknowledgement feed answered AE to the message ... sent to ...", with the receiver's words. An ORM escalates, as section 10 says |
| AR for an ADT | A case of kind `rejected`, reason `ack_AR`. A draft receiver blocks any write |
| The same AE again, or one for a message an AE on the connection already reported | No second case |
| AR naming a control id not found | No case, and an alert to your consumer naming the control id |

Limits of this route: it matches MSA-2 to the MSH-10 of what the operation sent, among the last 5000 messages to that item, newest first (`lookback`; IRIS has no index on it, so a
larger one costs a read of each), so a receiver that answers with another id gets the alert above. A DTL on the route is fine for the match, and the case still holds
what the service received (section 10). Only ACKs on an HL7 service were tried, and only on stock TCP services.

**Not there: waiting for an ACK that never comes.** Nothing times out a message whose application ACK has not arrived. This is planned, not built.

## 10. What a watched namespace does not get

Say these plainly to whoever owns the feed.

- **A message accepted by a transport ACK and then lost downstream raises nothing in Shutter today.** The engine completed it, so no alert comes and no case
  opens. The same goes for an operation with `GetReply` off, and for an application ACK that never arrives. A negative ACK on a feed of its own opens a case only with the process in 9.9.
- **Non-ADT messages have no recovery.** Orders, results and documents open a case and escalate; a person corrects them. They do
  not group: 5 failed results are 5 cases, and an outage is one case per message, not an incident.
- **An MLLP operation retrying forever (`FailureTimeout` -1, the stock TCP operation's default, which the plan now warns of whether
  the item sets it or inherits it).** The alert opens a case on the first failure, even in a short outage, and the engine goes on
  retrying. When the system returns the messages go through, and the case still reads escalated with a draft asking a team to correct
  them by hand, and shows no later messages. Read the message trace before anyone re-enters an order by hand.
- **A forward is never retried.** While `Shutter.Production` is stopped, or on a wrong password, a failure that reaches the forwarder
  is a warning in that namespace's event log, an alert to the site's own consumer, and `refused_72h` in the Doctor, and no case.
  Restoring the service does not bring it back.
- **A hard dependency on Shutter's database.** After the apply the production needs it. With that database dismounted, a failing
  operation's job terminated with `<PROTECT>`, the site's alert consumer received nothing, and the production would not start until it
  was mounted again. Before a failover, a restore or moving it, take the namespace off or plan for it.
- **A message sent to two receivers** gives one forward per receiver that fails, each quoting the session's first HL7 message, the
  service's: with a DTL on the route, the case holds what the service received, not what the operation sent.
- **Nothing over 2 MB, and nothing that is not HL7.** The intake answers 413 or 400, so a large MDM with its document inline, or a FHIR
  body, is a warning in the event log and no case. A smaller MDM's document is kept whole in the case's snapshot: a governance
  question for the trust.
- **The prevent-failures route (section 7) through a stock routing engine** can name the wrong reason: the engine holds the message, but
  the case reads as a schema failure of the standard the message itself names, because the header's source is the router. Use
  it through a process that checks the category, as the demo hospital's does, or test it first with your feed.
- **Same-instance only:** the links on a case open Shutter's copy of the message, not the source namespace's; `originHeaderId` on the
  case gives its header id there.
- **The cross-namespace timeline** reads Shutter's own connector table only: on a site's stock production it finds no earlier or later
  messages.

## The publisher: Shutter's read-only tools for an MCP client

On the AI Hub build the install makes the web application `/mcp/shutter`: IRIS's own MCP gateway (`%AI.MCP.Service`)
serving `Shutter.Publish.Tools`, read-only (cases, incidents, evidence, plans, events, precedents, health), with the
patients' identifiers replaced by tokens and an audit row per call (`docs/CONTRACTS.md`, section 15). The core edition
has no gateway; the Doctor's `publish.available` says which build this is.

- **Who may read:** a user who holds the resource `Shutter_Publish`: operators and approvers do (`Shutter_Operator`
  carries it), the forwarder and the public demo's visitors do not. The application asks for a password.
- **From an MCP client** (a desktop assistant, an IDE, your own agent): run the sidecar the image ships with an HTTP or
  SSE transport and point the client at it; the client sends its own HTTP Basic credentials (or a bearer), which the
  sidecar passes through to Shutter, so each person reads as themselves. Inside the container, with a small TOML:

  ```
  cat > /tmp/shutter-mcp.toml <<'EOT'
  [[iris]]
  name = "default"

  [iris.server]
  host = "127.0.0.1"
  port = 1972
  username = "operator"
  password = "shutter"

  [[iris.endpoints]]
  path = "/mcp/shutter"
  EOT
  iris-mcp-server -c /tmp/shutter-mcp.toml --transport http://127.0.0.1:8765 run --iris-host 127.0.0.1 --iris-port 1972 --iris-endpoint /mcp/shutter
  ```

  The client's MCP address is then `http://127.0.0.1:8765/mcp`; the tools appear as `mcp_shutter_ListCases`,
  `mcp_shutter_GetCase` and so on. The `[iris.server]` user is the sidecar's own connection to the superserver; the
  reader's identity comes from the client. A stdio transport carries no client credentials and is refused by the
  publisher; the server's `--help` lists the transports and the TOML keys.
- **From a script:** the gateway answers only the sidecar (a direct call gets 502 `GATEWAY_REQUIRED`), so a script talks to
  the sidecar's HTTP transport with the MCP protocol and HTTP Basic.
- **Nothing here writes.** Approvals, reinvestigations and closures stay in the app and its API, under their own
  resources and the `X-Requested-With` header.
