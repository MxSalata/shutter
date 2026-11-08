# When the model fails

A model failure can stop a case or hand it to a person. It can't write. No agent holds a tool that changes anything: besides the evidence reads, an agent's only tools are the five `Submit*` answers ([src/Shutter/Tools](https://github.com/MxSalata/shutter/tree/main/src/Shutter/Tools)), and what they return is a proposal that the gate, the rehearsal and a person act on. A plan made by the board, the single investigator or the rules path is never released by the site's policy: only a catalogue match on the policy path, which calls no model, can be (`CaseWorkflow.PolicyPath`). So when the model fails, nothing is written unless a person approves it.

This page is read from release 1.1.2's code (`rel/v1.1.2` at `ab0118e0`). What was run is under [Measured](#measured).

## The bounds

| Bound | Default | Where | What it does |
| --- | --- | --- | --- |
| One model call | 120 s, and 10 s to connect | `SHUTTER_PROVIDER_TIMEOUT_SECONDS`, held to 10 to 600 (`Shutter.Setup.ProviderTimeoutSeconds`); `AIHub.cls`, `BoundCall` | The HTTP client's request timeout, on the provider the install configures and on one a board item names in `ProviderConfig`, unless that configuration sets its own `http_config`. An agent class left to its own `PROVIDERCONFIG` gets no bound. |
| Turns | 8 a run | the Agent item's `MaxIterations` | The framework's tool-calling loop stops there. A run whose turns ran out after its answer was accepted is `ok`. |
| Tokens | 120,000 a run | the Agent item's `TokenBudget` | Judged after the run: over it, the run is `budget_exceeded` and its answer is kept for inspection, not used. |
| The run's deadline | 120 s a turn, 960 s at 8 turns | the Agent item's `RequestTimeoutSeconds` | Checked by the monitor between model turns. On build 154 the framework calls the monitor only before and after the run (`Shutter.Bridge.Monitor`), so this deadline isn't checked during a run there; the per-call bound and the board's time are what hold. |
| The board | 600 s for the specialists, then 600 s for the coordinator | Case Workflow's `BoardTimeoutSeconds` | When it runs out, the members that haven't answered count as failed and the case goes on with what it has (below). A case following another case's board waits at most 1,260 s (twice that plus 60). |
| The day's spend | `SHUTTER_DAILY_BUDGET_USD` | `Shutter.Util.Budget` | Once reached, a run that would call a model is refused with no call: `budget_exhausted`. |

Shutter doesn't retry a failed run or fall back to another model. The case goes to a person, or to the rules path, whose resend a person approves.

## Each status of a run

Every agent run ends with one status (`Shutter.Bridge.Msg.AgentResponse`), stored on the run with the error text. Only `ok` with an answer that parses is used.

| Status | When |
| --- | --- |
| `ok` | The run's `Submit*` tool accepted an answer. |
| `schema_failed` | The run ended without an accepted answer; the error gives the tool's last refusal, when there was one. |
| `budget_exceeded` | Over the run's token budget. The answer is kept and not used. |
| `timeout` | The run passed its deadline, or the error's text says timeout or timed out. |
| `model_error` | Any other error from the provider or the framework, and an agent that couldn't start. |
| `denied`, `loop_detected` | An error whose text says denied, or loop. |
| `catalogue_mismatch` | The agent's tools aren't exactly the declared ones. No model call is made. |
| `refused` | Record mode while the API mimic is on. No model call. |
| `error` | The agent class or the runner isn't installed, the agent replaced the runner's provider (no model call), or the runner itself failed. |
| `no_record` | Replay, with no recording for this case. |
| `budget_exhausted` | The day's model budget is spent. No call. |
| `provider_auth` | A live run failed with an authentication error in the last 15 minutes. No call. See [what isn't covered](#what-isnt-covered). |

## What the case does

A board member's run that ends in anything but `ok` gives no findings. The rest depends on what the round has once every member has answered or the board's time is up.

| What happened | The case | Written |
| --- | --- | --- |
| Some specialists answered and others failed or ran out of time | The coordinator plans from the findings in hand. The plan names the members who didn't answer, and its approval task says "Not every board member's review stands behind this plan: ... did not answer." | Only after a person approves |
| Every specialist failed, at least one with an error (any status but `no_record`, `budget_exhausted` and `provider_auth`) | `escalated`: "No board member produced usable findings; a person must look". No plan. | Nothing |
| Nobody could answer (every run `no_record`, `budget_exhausted` or `provider_auth`), and the catalogue gives the case to the board or a person | `escalated`, no plan, the entry and the reason in the headline: "Escalated to a person: catalogue E7, and no board member could answer: ..." (since 1.1.0) | Nothing |
| Nobody could answer, and no catalogue entry asks for the board or a person | The rules path: the plain resend at the observed version, which the gate judges and the receiver rehearses, then an approval task | Only after a person approves |
| The coordinator's run fails, or its plan isn't valid JSON | `escalated`: "The coordinator produced no plan: <status>, <error>" | Nothing |
| The coordinator doesn't answer within 600 s | `escalated`: "The coordinator did not answer within 600 s; the findings are on the case for a person" | Nothing |
| An answer comes after the board's time is up, or about an earlier snapshot | Recorded for its cost and not used | Nothing |
| The single investigator fails | As a board whose only member failed: one of the rows above, without a coordinator | As above |
| A case following another case's board, when that board decided nothing or took the rules path | It decides for itself, as a case nobody could answer | As above |
| A question (Ask about this case) | The question fails with the status. A question can't change anything. | Nothing |
| The production review's agent | The review keeps its baseline order. | Nothing |

In Rules only mode no model is asked, so none of this applies.

**On the case page:** the timeline lists every event with its text: each member's "gave no usable findings" with the status and the error, "The board's time is up after 600 s; no answer from ...", and the reason the case was escalated or sent to the rules path. The board section shows such a member's card as "No answer from this agent.", with the run's status beside its model and time, and its error text one click away under the finding. The approval task in the Workflow inbox names the members who didn't answer.

## Measured

- **Every specialist failing, on release 1.1.1** (commit `4e5ab015`), build `2027.1.0AI.109.0`, 8 November 2026: S2 live on OpenAI's `gpt-5.5`. Impact, conformance and encounter each ended `model_error` with no tokens used, since that model refuses the runner's `max_tokens`; the coordinator never ran, and the case escalated with no plan and no write in 23 s ([another-provider.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/another-provider.md)).
- **No recording, on release 1.1.2** (`ab0118e0`), the replay edition, 8 November 2026: S1 with the single investigator. Its run ended `no_record`, the case took the rules path, and the gate blocked the resend (`SUPERSEDED_BY_LATER_EVENT`); nothing was written.
- **The unit test** `Shutter.Test.BoardLead`, `TestNoBoardAnswerGoesToAPerson`: in Board, Site policy and single investigator modes, with every run `budget_exhausted`, `provider_auth` or `no_record`, a case the catalogue gives to the board goes to a person with no plan, naming the entry and why nobody answered.

The other statuses are read in the code, not run: no provider fault was injected.

## What isn't covered

- **The 15-minute breaker on a refused key is set only by a run whose status is `error`** with an authentication error's words (`Shutter.Util.LiveAgents.NoteRun`). The live runner reports a provider's own error as `model_error` (`AIHub.cls`, its `Catch`), so, as read in the code, a key the provider refuses ends each run `model_error` and every live run still calls the provider. Each such case still escalates or takes the rules path, as above. Untested live.
- **The 120 s bound's own error text wasn't measured,** so a call it stops may end `timeout` or `model_error`. Either way the member gives no findings.
- **The provider's error text is kept as the provider wrote it,** up to 2,000 characters on the run, and in the production's event log.
- **The run's deadline isn't checked during a run on build 154** (above).
