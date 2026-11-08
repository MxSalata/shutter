# A storm of 40, 200 and 1,000 failures

CI plays S11, eight failures to one receiver. This page records what one incident does with many more, measured once, after the v1.0.0 release, with no model call. The tables record a defect and its fix, released in 1.1.2, not a benchmark.

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

## After the fix

**When and what:** 7 November 2026, the code of the fix that release 1.1.2 carries, the same image, harness and shape of storm, one fresh container per size, on a Linux VM with 19 GB of memory, the demo receiver in the same instance on loopback. The harness is `tests/e2e/storm_scale_check.py`, and `tests/e2e/incident_task_check.py` for the task. The 10-failure control also ran on the AI Hub build 109.

| | 10 (control) | 40 | 200 | 1,000 |
| --- | --- | --- | --- | --- |
| Chains formed | 5 | 20 | 100 | 500 |
| Approval task raised, after the last post | 60 s | 59 s | 61 s | 61 s |
| Approved and released | all 10 | all 40 | all 200 | stopped measuring at 50 |
| Approval to the last case decided | 29.5 s | 119.3 s | 600.2 s | not run; about 50 minutes by extrapolation |
| Seconds an item (lowest, median, highest) | 2.5, 3.0, 3.0 | 2.3, 3.0, 3.0 | 2.2, 3.0, 4.0 | 2.5, 3.0, 3.0 |
| Keys committed twice | 0 | 0 | 0 | 0 |
| Writes out of order | 0 | 0 | 0 | 0 |
| Cases whose writes had no gate and rehearsal first | 0 of 10 | 0 of 40 | 0 of 200 | 0 of 1,000 |
| Cases at the end | 10 resolved | 40 resolved | 200 resolved | 51 resolved, 949 waiting their turn |
| `GET /incidents/{id}` at the end | 13.9 KB, 0.00 s | 49.5 KB, 0.01 s | 239 KB, 0.02 s | 971 KB, 0.06 s |

**Again on an AI Hub build.** 8 November 2026, the same harness on `2026.3.0AI.154.0`, the core loaded as CI loads it, one fresh container per size: 40, 200 and 1,000 each held every rule, with one shared task and one approval at every size. Approval to the last case decided took 120.0 s at 40 (2.0, 3.0, 4.0 s an item) and 607.8 s at 200 (2.8, 3.0, 7.0 s, with a second instance running beside it on the VM); at 1,000 the first 50 items took 2.6, 3.0 and 3.0 s, and `GET /incidents/{id}` answered 963 KB in 0.14 s. No key was committed twice, and no case was released without the task's approval.

**The task.** Its message holds what fits: at 24 failures, 1,797 characters, the first 3 of 12 chains and 6 of 24 operations; at 1,000, 1,804 characters, the first 3 of 500 chains, and "Approving binds all 500 chains, listed here or not". The digest in it equals the plan's, and an approval through the engine with that digest released all 12 chains.

**When the task cannot be raised.** With the approval target missing, 8 failures in 4 chains: the incident stayed open, no case failed, one error on its timeline and one Event Log alert named it, an approval answered 409, and a retry that failed again 5 minutes later said nothing new. With the target back, the next retry raised the task; the approval was taken, and all 8 items were released in order and verified, with no key twice.

**The page.** In a browser, for 100 chains waiting for approval: the earlier layout put the Approve button 16,784 px down on a laptop and 28,238 px on a phone. It now lists six chains with the rest behind one button, and the button is 1,098 px and 2,093 px down.

**What this does not show.** The whole release at 1,000, a restart during a release, a receiver that answers slowly, a storm through the board, and a Workflow item that answers each task with an error (that case is unit tests only). One shape of storm, one instance. Nothing at these sizes ran on build 109.
