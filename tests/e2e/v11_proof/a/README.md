# Tier A's proof rows

Measurements a tier A build can show on the rig (`tests/e2e/v11_rig`), each ending in a stated PASS or STOP and the decision the reading settles. A STOP is an answer, not a broken check: the words that rest on that point change. Every receiver is a fake on the loopback address of a test instance, and nothing here calls a model.

| Row | What it measures |
| --- | --- |
| 9 | A 30 s blip at a no-retry receiver: the outage opens within 10 s of the first never-opened header |
| 2 | That receiver idle once its listener is back: Status, AdapterState and the watch's reading for 2 minutes, and whether the idle operation dials |
| 3 | One refusal at `FailureTimeout` 0, then silence: Status for 2 minutes, and nothing opens |
| 4 | Through a refusal loop and a read-timeout loop at -1: which of Status, the oldest Delivered header and `Ens.Job:Enumerate`'s ActiveMessage names the head |
| 12 | A header Completed after retries: whether its earlier `Ens_Util.Log` rows survive |
| 13 | A message for the patient arriving between a check and an `EnQueue`: which reaches the receiver first, over 20 tries, and how wide the window is with nothing in it |
| 15 | An operation's inactivity alert while its outage is open: the `AlertProcess` line it stops at, whether it has a session, whether a case opens or the outage moves; then a listener down and up three times over 5 minutes at a retrying item with `QueueWaitAlert` and a no-retry item with `AlertOnError` |

```
python3 tests/e2e/v11_proof/a/test_proof_a.py
python3 tests/e2e/v11_proof/a/proof_a.py --ctr NAME --port PORT --image IMAGE [--module core] [--keep] [--reuse] [--only 9,3,4,12,13,15]
```

Exit status: 0 every row passed, 1 a row stopped, 3 the rig broke. The whole package goes with module `.` on 2027.1, and `--module core` on 2026.2.
