# The rig for a receiver's outage

What every check of a laboratory or ADT receiver's outage runs on, so that none writes its own. It holds no assertion about the product. `tests/e2e/pathology_check.py` and its `pathology_site` are the independent oracle and don't use this.

Every name here is made up, and every receiver is a fake on the loopback address of a test instance. Nothing here calls a model or needs an API key.

| File | What it is |
| --- | --- |
| `rig.py` | The library: `Rig` starts the instance, installs Shutter and the site, runs the listeners, signs REST sessions out and proves a stop and start. Also a small command line. |
| `listener.py` | The fake receiver, run inside the container. Its first lines say what each mode does. |
| `probe.py`, `mllp_send.py` | One connect and at most one frame, for checking a listener; and sending bytes unchanged into a service's port. |
| `site/` | The two productions, their rule, the function the rule calls and the alert consumer. |
| `test_rig.py` | The rig's own rules with no instance and no Docker. |
| `check_rig.py` | Whether the rig stands, on a real instance. |

## The two namespaces

| Namespace | Production | Goes in at | Item, and the port it dials | Behaviour |
| --- | --- | --- | --- | --- |
| `RIGROUTED` | `V11Rig.Routed` | `ROUTED_IN` 7601, through `Routed Router` | `LIMS Out`, `LIMS` 7701 | `FailureTimeout` -1 |
| | | | `Second Out`, `SECOND` 7702 | 0: every message also goes here |
| | | | `Aside Out`, `ASIDE` 7703 | 0: where the rule sends what its function answers 1 for |
| `RIGPLAIN` | `V11Rig.Plain` | `RETRY_IN` 7611 | `Retry Out`, `RETRY` 7711 | -1 |
| | | `NORETRY_IN` 7612 | `NoRetry Out`, `NORETRY` 7712 | 0 |
| | | `BOUNDED_IN` 7613 | `Bounded Out`, `BOUNDED` 7713 | 25 s |
| | | `ONESHOT_IN` 7614 | `OneShot Out`, `ONESHOT` 7714 | 0, `StayConnected` 0 |

The routed production's rule (`V11Rig.Rule`) calls `V11Rig.RuleFn.RigHold(Document, "LIMS Out")`, a function set's method that answers 1 when `^V11Rig.Hold(item, first PID-3.1)` is set and counts its calls in `^V11Rig.Calls`. To try another function, compile your own function set and rule with `put_file` and `load_classes`, and point the router at it with `set_item(ns, production, "Routed Router", BusinessRuleName=...)`.

No receiver is declared in a profile here: the profile's form belongs to the slice that uses it.

## The listener's modes

`listener_up(port, spec)` starts one, `listener_spec(port, spec)` changes what it answers from the next frame on, `listener_down(port)` stops it.

| `spec` | What the listener does |
| --- | --- |
| no listener | Down: the port refuses the connect |
| `{"mode": "up"}` | Answers AA |
| `{"mode": "answer", "code": "AE", "words": "...", "err": ["ERR|..."]}` | That code and words, with `by_control` per message and `nonascii` for a frame with a byte above 0x7F |
| `{"mode": "take_and_die"}` | Reads the frame, closes with no answer and exits; `after` N answers the first N-1 |
| `{"mode": "hang"}` | Accepts, reads and never answers |
| `{"mode": "noaccept"}` | Listens and never accepts (read at the start) |
| `{"mode": "log_hex"}` | Answers AA and logs each frame's bytes; `"hex": true` does that in any mode |

`delay` slows each answer. `heard(port)` gives the control ids in order, `frames(port)` each frame's record (`copy`, `bytes`, `sha1`, `high`, `answer`, `hex`), and `events(port)` the connections too. `listening(port)` reads `/proc/net/tcp`, so asking opens no connection at the receiver.

## Rules it keeps for you

- **A stop and start proves itself.** `restart_production(ns, production, watch)` asks until the output says both happened, compares the watched host's job number, and raises `RestartNotProven` if it's the same. A long-lived operation keeps its old code until this has happened. For Shutter's production, watch `Gate`.
- **A licence refusal is never an empty answer.** `session` waits it out (exit 133 or `<LICENSE LIMIT EXCEEDED>`, up to 5 minutes), then raises `RigBroken`.
- **A read that can't answer raises.** `session`, and every reading built on it, raises `RigBroken` on a missing container or namespace, any other non-zero exit and an uncaught ObjectScript error on any line. So do `events`, `heard` and `listening`. An empty answer is a real one: no rows, or a port with no log.
- **`set_item` does it or says so.** The engine's own list (`item_settings`) gives each setting its target, Host or Adapter. An item or setting it doesn't have raises, so do a failed save or update, and the engine must then read the new value.
- **REST sessions sign out.** `with rig.api() as a:` signs out on leaving, whatever happened. A session left open can hold a licence unit, and a later terminal session may then be refused.
- **Name your container and port.** `Rig` refuses an empty name, and `start()` removes only a container of that name.

## Running it

```
python3 tests/e2e/v11_rig/test_rig.py
python3 tests/e2e/v11_rig/check_rig.py --ctr NAME --port PORT --image IMAGE [--module core] [--keep] [--reuse]
python3 tests/e2e/v11_rig/rig.py restart --ctr NAME --ns SHUTTER --production Shutter.Production --watch Gate
```

The check's exit status is 0 when all is well, 1 when a check failed and 3 when the rig broke. The whole package goes with module `.` on 2027.1, and `--module core` on 2026.2.
