# Contest 49 entry (working title)

The development repository for our entry to the InterSystems Programming Contest "AI Agents in Interoperability
Workflows" (Open Exchange contest 49). Private while the entry is built.

- Contest page: https://openexchange.intersystems.com/contest/49
- Announcement: https://community.intersystems.com/post/intersystems-programming-contest-ai-agents-interoperability-workflows
- Task: an InterSystems IRIS Interoperability workflow that uses an IRIS AI Hub agent to handle a decision-making task.
- Dates: development from 26 October 2026, submissions until 8 November, voting 9 to 15 November (Eastern time).

## Run it

Interlock runs on InterSystems IRIS for Health Community with AI Hub, build `2026.3.0AI.154.0`. The image comes from
InterSystems' early-access programme, so it is loaded from the file InterSystems provides and tagged with the name this
repository's `Dockerfile` expects; the rest is `docker compose up`.

```sh
docker image load -i <the irishealth-community 2026.3.0AI.154.0 image file>
docker tag <the loaded image> irishealth-community:2026.3.0AI.154.0
docker compose up -d
```

The first `up` builds the image: it creates the `INTERLOCK` namespace, installs the InterSystems Package Manager and
loads the `iris-interlock` module (the production, the case store, the gate, the synthetic ward system, the web
application and the recorded agent runs), then starts the production. Allow a few minutes.

Then open:

- the web application: http://localhost:52773/interlock/index.html (the bare `/interlock/` answers 404);
  sign in as `operator` or `approver`, password `interlock`;
- the REST API's health report: http://localhost:52773/api/interlock/health;
- the Management Portal: http://localhost:52773/csp/sys/UtilHome.csp, `_SYSTEM` / `SYS` (namespace `INTERLOCK`,
  production `Interlock.Production`, and the Visual Trace of every case).

To watch a case unfold, run a scenario from the web application's Scenarios page (S1 to S10): each one feeds synthetic
ADT messages into the production, makes one delivery fail in a particular way, and opens a case. Out of the box the
agents replay recorded runs, so the demo needs no API key. For live agents, put an `ANTHROPIC_API_KEY` in a `.env` file
(copy `.env.example`) before `docker compose up`; the `aihub` module reads it.

The same `Dockerfile` builds the replay edition on any IRIS for Health Community 2026.2 or later:
`INTERLOCK_IMAGE=intersystemsdc/irishealth-community:latest docker compose up -d --build`. Other settings in
`.env.example`: the published ports and the demo users' password.

Status: planning. The idea, the stack and the layout of this repository come next.
