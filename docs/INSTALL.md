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
- **Both start from a non-demo install** (`-Ddemo=0`): no demo users, no demo receiver, no credential, no scenario or
  feed items, and no namespace-wide purge unless asked for.
- **A receiver with no API is escalated, never resent.** Shutter resends only to a receiver whose site profile entry
  describes its API (state, receipt, capabilities and operations paths). A ward system that takes HL7 over TCP and
  keeps no receipts is investigated and escalated; the team corrects it by hand and marks the case handled.

## 2. What an install creates

The module `iris-shutter` (the repository root) carries the core, the demo receiver's classes included. Its manifest
runs `Shutter.Setup.InstallStatus(root, demo, production)`; the IPM parameter `demo` defaults to 1, and
`zpm "load /path/to/module -Ddemo=0"` installs without the demo; the parameter `production` (empty by default) names a
production of the site's own to install Shutter's items into instead (section 4), as in
`zpm "load /path/to/module -Ddemo=0 -Dproduction=Your.Production"`. A failed install stops the load. A packaged install (an
archive made by `zpm "package"`, the form the registry serves) carries the `knowledge/`, `fixtures/` and `www/` folders
the install reads; IPM keeps the extracted module in its module root (its ModuleRoot setting, by default
`<data directory>/ipm/iris-shutter/<version>/`), and `/shutter` serves `www/` from there. A packaged install needs IPM
0.10.4 or later: 0.10.0 to 0.10.3 delete the extracted module when the install ends, so the install refuses them and
says so; a load from a folder works on any IPM. The companion module `iris-shutter-aihub` adds the live agents on an AI
Hub build; without it the gate, the catalogue and the policy path work, and the board replays recordings.

`Install` creates, in the current namespace, the folders under `<mgr>/shutter/`, the resources `Shutter_Operate`,
`Shutter_Approve` and `Shutter_Intake`, the roles `Shutter_Operator`, `Shutter_Approver`, `Shutter_WebApp` and
`Shutter_Forwarder`, the Workflow role "Shutter Approvers", the seeds, the web applications `/api/shutter` and
`/shutter`, the daily task "Shutter retention", the default settings, and `Shutter.Production`, started as the
auto-start production. With `demo=1` it also creates the demo users, the demo receiver's resource, role, user and
`/downstream/api`, the `DownstreamAPI` credential and the feed and demo items.

Environment variables read when the installer runs:

| Variable | Meaning |
| --- | --- |
| `SHUTTER_DEMO_PASSWORD` | The demo users' password (default `shutter`); demo only. |
| `SHUTTER_MESSAGE_PURGE` | `1` creates the daily task "Shutter message purge" (`Ens.Util.Tasks.Purge`, every message type in the namespace). On by default in the demo, off otherwise: only a namespace that holds nothing but Shutter should purge this way. |
| `SHUTTER_MESSAGE_DAYS` | Days the purge keeps (default 90). |
| `SHUTTER_ESCALATION_DAYS` | Days after a case closes before the daily task "Shutter retention" removes the text of its escalation emails (the hospital number, the NHS number and the date of birth) and their `.eml` files; the rows stay with their digest, recipients and who sent them. Default: `SHUTTER_MESSAGE_DAYS` (90); `0` keeps them. An instance upgraded in place runs the default, 90, until the task's `EscalationDays` is changed in the Task Manager. |

The production's name comes from `^Shutter.Config("production")`, which `InstallInto` records (default
`Shutter.Production`); the health report (`GET /api/shutter/health`) and the readiness report (`Shutter.Setup.Doctor`)
read it.

## 3. Shape A: Shutter in its own namespace

**3.1 The namespace.** Create it with `Installer.cls` as the image does (two databases, Interoperability on) or with
`SELECT Shutter.Setup_CreateNamespace('SHUTTER')`, its data database on storage the trust backs up. Load the module
with `-Ddemo=0`: `Shutter.Production` starts with no feed items.

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
`Shutter_Forwarder`. The hospital's HL7 process calls it on a failed delivery with the failed message's header id, the
receiver's item name, the outcome and the receiver's answer; the class documents the call.

**3.3 The index.** Shutter's exact index (the "HL7 Index" item) is per namespace: in SHUTTER it covers the messages
Shutter stores, so a case's timeline shows what the intake brought. An index of a watched production's whole feed,
readable from SHUTTER, is not in this version.

**3.4 The receivers.** Each system Shutter should recover is a receiver entry in the site profile: its name (the
production item that delivers to it), tier, what it takes (cancels, merges) and its API paths. Without API paths there
is no receipt lookup and no resend: the gate blocks any write and the case is escalated to the team the profile names.

**3.5 Security and operations.** Only holders of `Shutter_Forwarder` can open cases; the web application keeps its
roles. Escalation mail goes through the `Escalation Mail` operation's `SMTPServer` setting; unset, it writes `.eml`
files under `<mgr>/shutter/out/mail`.

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
2. Load `iris-shutter` with `-Ddemo=0` (and `iris-shutter-aihub` on an AI Hub build, the provider key in the
   environment). Check `/api/shutter/health`.
3. Map the trust's users to `Shutter_Operator` and `Shutter_Approver`; add the approvers to the Workflow role; create
   the forwarder's user with `Shutter_Forwarder`. An operator escalates a case (the escalation is the sign-off) and
   marks it handled once the team has corrected the systems; an approver also approves plans and incident releases,
   saves the site profile and changes the agent library. A trust that wants only an approver to close a case handled
   by hand answers yes to "Closing a case by hand needs an approver" in the site profile
   (`approvers.close_needs_approver`). Shutter checks the role of whoever closes the case, not that a second person
   does: an approver may escalate and close the same case.
4. Fill in the site profile (the web application's questionnaire): receivers, tiers, what each takes, API paths or
   none, the policy per tier, teams and mailboxes, the feed's time zone, `merges: forbidden`.
5. Set the `Escalation Mail` operation's SMTP server.
6. In each watched production, add `Shutter.Intake.Forwarder` with Shutter's address and credential, and call it from
   the process that delivers to each receiver on a failed delivery.
7. Replay a known failure in a test environment: a case opens in SHUTTER, the evidence shows the message and the
   receiver's state, and the escalation draft names the right team.
8. Switch the investigation mode to `policy` for the easy chains once the catalogue's entries are reviewed; watch the
   first weeks on the Costs page and the Doctor report.

Shape B: section 4 in place of steps 1, 2 and 6; the rest as above.

## 6. What stays the same in both shapes

The case, the evidence, the matcher and the catalogue, the gate, approvals and incidents, the escalation by email, the
model view, the REST API and the web application are namespace-local code with settings for the names they need. Only
the scenario player, the demo receiver, the demo users and the store purge (refused on a non-demo instance) know the
demo.
