# The API mimic

A test fixture for the live agent path. It answers the live runner's model calls without a model, so AI Hub's own
agent loop, the evidence tools, the knowledge search, the scope and trace policies, the saved sessions and the
Visual Trace all run, at no cost. Only the model's answers are mimicked.

It needs an AI Hub build (the `%AI` package) with the aihub module loaded. The classes here are in neither IPM module,
and `.dockerignore` keeps this folder out of the image: load them by hand, on a test instance.

| Class | What it does |
| --- | --- |
| `Shutter.Mock.API` | The web application `/shutter-mock`: an OpenAI-compatible API (`GET /v1/models`, `POST /v1/chat/completions`, as JSON or server-sent events) that answers loopback callers only and logs one line per call in `^Shutter.MockLog` |
| `Shutter.Mock.Turns` | The answers, JSON in and JSON out with no HTTP: the member's recording replayed turn by turn, or a deterministic answer from the catalogue |
| `Shutter.Mock.Setup` | The switch, the checks and the call log, as SQL procedures |

## Switching it on and off

Load the classes and switch the mimic on:

```
python3 scripts/iris-load.py --url http://localhost:52773 --ns SHUTTER tests/mock
python3 scripts/iris-sql.py --url http://localhost:52773 --ns SHUTTER "SELECT Shutter_Mock.Setup_Enable() AS s"
python3 scripts/iris-sql.py --url http://localhost:52773 --ns SHUTTER "SELECT Shutter_Mock.Setup_SelfTest() AS s"
```

`Enable()` creates the web application `/shutter-mock`, with a role for the namespace's databases, the Config Store
configuration `AI.LLM.ShutterMock` (provider `openai`, `base_url` the web application at the address the production
reaches the downstream system on, a placeholder key) and the switch `^Shutter.Config("aihub","mock")`. It is refused
while the agent mode is `record`, and it needs UnknownUser enabled. The agent mode the instance records is left as it
is: while the switch is set, every agent item set to `auto` runs live through the mimic.

`SelfTest()` is the proof to run before any agent does, and it calls nothing but the mimic. It checks that:

- every board item resolves to live through the live runner, and the spec the operation builds for it carries the
  mimic's configuration;
- the provider the runner makes is the mimic's, and an agent keeps it through `%Init`, so `AI.LLM.Shutter` is never
  read;
- that provider lists the models, passes the Config Store's test of the configuration, and gets "pong" back for a ping
  that the call log shows arriving with the run's token;
- a response labelled `mock` is refused as a recording.

Switch it off with `SELECT Shutter_Mock.Setup_Disable() AS s` (`Disable(1)` clears the call log too). The switch goes
first, then the options, the configuration, the web application and the role. The switch is read once per run, when its
mode is resolved, and the runner follows that reading: a run resolved while the mimic was on still goes to the mimic,
and fails if the mimic is gone by then, but never reaches the instance's own provider.

## What it answers

The runner passes the run's context as the API key: the replay key, the case, the member, the terminal tool and the
production message. The mimic checks them against the request (the case in the evidence tag, the member's heading in
the instructions, the terminal tool among the tools) and answers 400 when they differ.

- **Replay.** When the member's recording exists and its case's material facts are this case's, the recording is
  replayed turn by turn. The material facts are the scenario, the event, the catalogue's entry, outcome, matches and
  conditions, the receiver's version and state, the receipt, conditional writes and the specialists' dispositions.
  The tool calls are the recording's own, for this case. A call to a tool this run does not offer is dropped.
- **The catalogue.** Otherwise, and for every run with `mockReplay` set to 0, the answer is deterministic. The first
  turn calls the member's read tools and one knowledge search, and the second calls the terminal tool. The disposition
  is the one the policy path takes for the catalogue entry the evidence matched: the single match, else the entry whose
  scenarios name the case's.
- **Refusals.** A terminal call refused beyond the recording's own is answered once with the catalogue's call; the next
  refusal ends the run with the problems as its text.

Every text the mimic writes starts with `[mock]`. Each run is labelled model `mock` and provider configuration
`ShutterMock`, costs 0, and is never recorded: record mode is refused while the mimic is on.

Options, through `SELECT Shutter_Mock.Setup_Option('<name>', '<value>')` (an empty value removes one):

- `mockReplay` 0: every run is answered from the catalogue;
- `mockStrict` 1: a replayed run ends at the first tool that failed;
- `mockDebug` 1: each request's body is kept in the call log.

`Shutter_Mock.Setup_Log(<from line>, <bodies>)` reads the call log: the run, the member, the turn, the source
(`replay:<key>` or `fallback:<entry>`), any divergence from the recording, and the drift, which counts the tool results
that differ from the recording's beyond volatile fields. `Shutter_Mock.Setup_Offline()` replays every recording through
`Shutter.Mock.Turns` with no HTTP, and checks that a copy with the receiver's version raised by one goes to the
catalogue. `Shutter_Mock.Setup_Licences()` lists who holds the instance's licence units.

## What it proves, and what it doesn't

It proves the plumbing of the live path on a real AI Hub build:

- the agent classes start and keep the runner's provider;
- the tools are offered, called, authorised by the scope policy and audited into the trace and the ToolCall rows;
- the terminal tools validate and accept the results;
- the sessions are saved;
- the runner fills the response, and the case workflow, the gate, the approvals and the writes act on what the board
  submitted, as for a live board.

It proves nothing about judgement. Replayed answers are the recorded model's, and the catalogue's answers are the
policy path's, so neither tells how a model would decide a case. Token figures are estimates (four characters a token,
no cache), and durations are the mimic's, not a model's. The wire format is the `openai` provider's, not the
`anthropic` provider's that the agents use with a key.

On build 154 the `openai` provider sends `POST {base_url}/chat/completions` with `model`, `messages`, `tools` (each
`{type: "function", function: {name, description, parameters}}`) and `max_tokens`, with no `stream`, and the key as
`Authorization: Bearer`. It fetches `GET /models` once and keeps the answer. A request from inside the instance holds no
licence unit after it ends.
