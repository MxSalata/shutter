# Held-out cases

Twelve failed ADT deliveries at a made-up hospital, written by an author who had not read the catalogue, with reference
outcomes and a scoring rule hashed before any mode ran. This folder plays them through the shipped product and grades
the runs. The cases, the reference outcomes and the rule are published with their hashes in
[docs/readme/fair-test](https://github.com/MxSalata/shutter/tree/main/docs/readme/fair-test); the hashes are also in
`build_fixtures.py`, which refuses to build or grade against anything else. Nothing here is loaded into a module or an
image, and CI doesn't run it.

## The files

| File | What |
|---|---|
| `fixtures/` | One folder per case, each message exactly as the sealed case file prints it, and `scenarios.json` with the case file's recipes in the runner's steps. Built by `build_fixtures.py`; `--check` compares. No outcome is in here. |
| `instance.sh` | A throwaway IRIS with this working copy mounted, installed as CI installs it: the core edition, no key, so agents can only replay. |
| `set_fixtures.sh` | Points `^Shutter.Config("fixtures")` at a folder. The runner needs no other change. |
| `play.py` | One run per case, mode and repetition, in a shuffled order; keeps each run's raw record. |
| `grade.py` | The export with the mode's name removed, the category of each run from that export alone, then the counts, the strict and lenient means and the always-escalate baseline. |
| `test_grade.py` | The grader's rules and the date shift, with no instance. |

## How to run

```
bash tests/fair_test/instance.sh CTR irishealth-community:2027.1.0AI.109.0 PORT
CTR=CTR python3 tests/fair_test/play.py --url http://127.0.0.1:PORT --play-root "$PWD/play" \
    --container-root /home/irisowner/dev/play/ --set-fixtures tests/fair_test/set_fixtures.sh \
    --out runs --modes rules,policy --repeat 3
python3 tests/fair_test/grade.py --raw runs --sealed docs/readme/fair-test --out graded
```

A finished run's file is skipped on a second start, so a broken session carries on where it stopped. The play folder is
replaced on each start, so `play.py` refuses one holding anything it didn't write.

## What the rig changes, and why

- **The dates.** The set is dated 18 November 2026. The product calls an event time more than five minutes after the
  evidence `future`, and the gate blocks every write on it. So before that day the player shifts every date by one fixed
  number of days into a play folder (`--day`, default 5 November, where the clocks and the weekday change nothing the
  cases rest on). The day must be over: played on the day itself, an afternoon event is `future`, and `grade.py` declares
  any run the product stopped that way unscorable, since the stop is about the play date. `grade.py` moves the keys and
  the fixtures' dates in the texts back before it compares them with the sealed ones; a date after `--day` is the run's
  own clock (a receipt's time, say) and stays, so the export shows the times that really happened.
- **The scenario ids.** The scenario id is in what a model is shown, so each case plays under an opaque id.
- **F08's delay.** The case file asks for a commit about 30 s after the send and a read before it. The shipped Case
  Workflow waits 15 s after the connector's 15 s timeout, so the read lands at about 30 s, on the commit. The delay is
  45 s, the rest of the case is as written, and a run that read after the commit is declared unscorable.
- **A 5 s wait before each `fault off`,** as the demo scenarios have, so the file service has read the failing message
  while the fault is on.
- **No hold was added.** The shipped 15 s settle already collects evidence after the steps that matter. F09's run
  records whether the cancel was in the snapshot; one where it wasn't is declared unscorable.
- **Approval.** A plan waiting for approval is approved once the steps are done, as `scenario_check.py --approve` does,
  so that its effect at the receiver is measured. The record says when that happened.
- **The second demo receiver stays on.** The production feeds Records Out as well, so a run can open a case there too.
  Those are kept in the record and not judged. The demo hospital isn't installed.

## What it does not do

- It calls no model. A case Site policy sends to the board has no recording here, so the product falls back to the
  rules path's plain resend; `grade.py` marks those runs and gives the mode's figures with and without them. The board
  and the single investigator need a live key.
- Always-escalate is computed from the rule, not played: the product has no such mode.
- The two reason flags in the rule need two human graders. They are null in the rows.
