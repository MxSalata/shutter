# A storm of 40, 200 and 1,000 failures

CI plays S11, eight failures to one receiver. This page records what one incident does with many more, measured once, after the v1.0.0 release, with no model call. It is a record of a defect, not a benchmark.

**When and what:** 6 November 2026, 23:08 to 23:36 UTC, the code of v1.0.0 (`8afd1ab`), on the public image `irishealth-community:2026.2` (the core, no AI Hub), one fresh container per size on a Linux VM with 22 GB of memory, the demo receiver in the same instance on loopback. The site's default mode for a watched production, `policy`, so no agent ran (0 runs before and after at every size). Each size posted failures of one shape to `POST /api/shutter/intake` one at a time, each `delivery_failed` to `Downstream Out`: per patient an admission and a transfer, fresh identifiers, so a chain of two under tier 2's `approval` policy. The run was judged from outside the code under test: the receiver's own receipt and encounter tables, the REST API as a signed-in user, the Event Log and `docker`. The harness was a test on the intake route.

| | 8 (control) | 10 (control) | 40 | 200 | 1,000 |
| --- | --- | --- | --- | --- | --- |
| Incidents opened | 1 | 1 | 1 | 1 | 1 |
| Cases left at the readiness limit | 0 | 0 | 0 | 0 | 0 |
| Intake closed, from the first post | 60 s | 60 s | 60 s | 61 s | 69 s (the last post at 10 s) |
| Evidence backlog at intake close | 0 | 0 | 0 | 0 | 0 (1,000 cases collected in about 31 s) |
| Chains formed | 4 | 5 | 20 | 100 | 500 (2 s after intake closed) |
| Approval task raised | yes, 60 s after the last post | no | no | no | no |
| What happened next | approved; 8 items released and verified in 23.6 s, 3.0 s an item (2.6 to 3.0) | abandoned | abandoned | abandoned | abandoned |
| Cases at the end | 8 resolved | 10 failed | 40 failed | 200 failed | 1,000 failed |
| Writes at the receiver | 8, each after its gate and rehearsal, in order, no key twice | 0 | 0 | 0 | 0 |
| `GET /incidents/{id}` at the end | 11.5 KB in 0.00 s | 15.5 KB, 0.07 s | 57.5 KB, 0.07 s | 281 KB, 0.08 s | 1.40 MB, 0.14 s |
| Database growth | 0 | 0 | 0 | 0 | 20 MB |
| Instance memory | 2.2 GB | 2.2 GB | 2.2 GB | 2.2 GB | 2.1 GB |

**The defect.** At 10 failures and above the incident closed itself in the same second the chains were formed: "Abandoned: a workflow error at quiet: ERROR #7201: Datatype value '...' length longer than MAXLEN allowed of 2000". The shared approval task writes every chain and item into its Workflow message, `EnsLib.Workflow.TaskRequest.%Message`, which holds 2,000 characters on this image and on the AI Hub builds 109 and 154. With these identifiers four chains of two fit (about 1,835 characters) and five do not (about 2,060). No task is raised, every chain is `stopped`, every case closes `failed` with the incident's name, nothing reaches the receiver. The incident's events name the error.

**What this does not show.** No release above eight items was measured, so the per-item time at scale, the verification and ordering rules under load, and the readiness limit against a receiver that answers slowly (here it answered on loopback in milliseconds) are all untested. One shape of storm, one instance, no restart, no board (a storm with no API key takes the rules path and never reaches the board; a board storm was not run). The times are from a receiver sharing the instance, and are conservative for a site with its own.
