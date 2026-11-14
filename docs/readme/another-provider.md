# Running the board on another provider, by hand

When this was tested, Shutter's install configured one model provider, Anthropic, from `ANTHROPIC_API_KEY`. It now also takes `OPENAI_API_KEY` ([INSTALL.md](https://github.com/MxSalata/shutter/blob/main/docs/INSTALL.md), section 2) and writes the secret and the settings of steps 1 and 2 below as Shutter's own `AI.LLM.Shutter`; that path has not been measured yet. AI Hub's Config Store holds others, and each board item names the configuration it runs on in its `ProviderConfig` setting, so a site can point the board at another provider by hand, with no change to Shutter's code. This page is the record of doing that once, with OpenAI: the steps as tested, what came out, what differs from Anthropic, and what the install doesn't do for you. It is one afternoon on one instance, not a supported configuration.

**When and what:** 8 November 2026, 15:01 to 15:15 UTC, on IRIS for Health with AI Hub `2027.1.0AI.109.0` (build 109U), with Shutter 1.1.1 at commit `4e5ab015`, the demo install in namespace `SHUTTER`. The provider was OpenAI's API through AI Hub's `openai` provider, model `gpt-4.1`. Nothing in Shutter's code was changed; the settings below were put back afterwards.

## The result

S2 and S8, live on the board, twice each, all four as expected:

| Pass | Scenario | Case | Expected | Board of specialists, on `gpt-4.1` |
| --- | --- | --- | --- | --- |
| 1 | S2 Never-accepted transfer, still current | C-000002 | resend, one write, downstream admitted WARD-B | as expected: resolved, resend, one write, downstream admitted WARD-B |
| 1 | S8 Event times that can't be compared | C-000003 | escalate, no write, downstream admitted WARD-C | as expected: escalated, escalate, no write, downstream admitted WARD-C |
| 2 | S2 | C-000004 | the same | as expected, as in pass 1 |
| 2 | S8 | C-000005 | the same | as expected, as in pass 1 |

Each case was open 23 to 26 s, and the scenario runner took 26 to 30 s for each. Every board member's run ended `ok`, and every one made its `SubmitFindings` or `SubmitPlan` call with typed arguments that were accepted the first time (16 of 16 runs). In both S2 passes the plan was a resend of version 1 under catalogue entry E2, the gate passed the proposal and the dispatch, the rehearsal answered 200 with `wouldApply` true, the one write answered 201 and the case verified. In both S8 passes the plan was escalate under E7 and nothing was written; conformance said resend in both, as it does in the Anthropic recording of S8, since it judges the message alone, and the other three said escalate.

A board question on the same four items (Q-000001, on C-000004) was answered in 4 runs, each `ok` with one tool call: the three members' `SubmitAnswer` and the coordinator's `SubmitBoardAnswer`, each accepted the first time.

**Only on an older model.** The first attempt, on `gpt-5.5`, failed: S2 escalated with no plan and no write in 23 s, because impact, conformance and encounter each ended `model_error` with no tokens used, and the coordinator never ran:

```text
ProviderError: Provider 'openai' error: API error: [unsupported_parameter] Unsupported parameter: 'max_tokens' is not supported with this model. Use 'max_completion_tokens' instead.
```

Shutter's runner always sends `max_tokens` (16000) when it opens the session ([AIHub.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Bridge/Runner/AIHub.cls), line 100 at `4e5ab015`). Direct calls with that limit gave the same error on `gpt-5.5` and `chat-latest`, and worked on `gpt-4.1`. We found no Config Store field in AI Hub's OpenAI provider on build 109 that sends `max_completion_tokens` instead (the name appears in its library only inside a model catalogue), so on build 109 the board runs on OpenAI only with a model that still takes `max_tokens`, such as `gpt-4.1`, and OpenAI's own model page marks `gpt-4.1` as deprecated.

## The steps, as tested

Run these in the namespace Shutter is installed in, as a user who may write the wallet and the Config Store (the test used `_SYSTEM`). The test passed the key as a parameter of a temporary SQL procedure over the instance's HTTP API, so that it never appeared on a screen or in a file; the calls inside it are the ones below. In a terminal, which the test didn't use, read the key into `key` without echo (`Use $PRINCIPAL:(:"+S")` before the `Read`, `Use $PRINCIPAL:(:"-S")` after it) and `Kill key` when done.

**1. The wallet secret.** The same resource and collection Shutter's own setup uses, and a secret of its own, so Shutter's `Shutter.Anthropic` is left alone (the test instance had none, and no `Shutter` collection or `Shutter_Secrets` resource either, so this created both):

```objectscript
Do ##class(Shutter.Setup).EnsureSecretResource()
Do ##class(Shutter.Setup).RebuildDescriptorRegistry()
If '##class(%Wallet.Collection).Exists("Shutter") Do ##class(%Wallet.Collection).Create("Shutter", {"UseResource": "Shutter_Secrets", "EditResource": "Shutter_Secrets"})
Set sc = ##class(%Wallet.KeyValue).Create("Shutter.OpenAI", {"Usage": "CUSTOM", "Secret": {"key": (key)}})
```

`RebuildDescriptorRegistry` is there because a fresh AI Hub instance refuses any `AI.LLM` configuration with #26414 "No descriptor found for AI.LLM" until its descriptor registry is rebuilt ([building-on-ai-hub.md](https://github.com/MxSalata/shutter/blob/main/docs/readme/building-on-ai-hub.md)).

**2. The provider configuration**, with the secret named by reference, never the key:

```objectscript
Set sc = ##class(%ConfigStore.Configuration).Create("AI", "LLM", "", "OpenAI", {"model_provider": "openai", "model": "gpt-4.1", "api_key": "secret://Shutter.OpenAI#key"})
```

To change the model, the test deleted `AI.LLM.OpenAI` and created it again (first with `gpt-5.5`, then `gpt-4.1`). Read back with `GetDetails`, `AI.LLM.OpenAI` was:

```json
{"model_provider":"openai","model":"gpt-4.1","api_key":"secret://Shutter.OpenAI#key"}
```

**3. The items' settings.** On Agent Conformance, Agent Encounter, Agent Impact and Agent Coordinator in `Shutter.Production` (Interoperability, Configure, Production, each item's Settings), set `ProviderConfig` to `OpenAI`. A name of fewer than three parts is looked up under `AI.LLM`, so `OpenAI` means `AI.LLM.OpenAI`. `Model` was left empty, so the configuration's model was used; an item's `Model` setting, when set, wins over it. Agent Board, which runs the single investigator, library members and explain questions, was not changed and not tested.

**4. Restart the items.** Save the production and update it (Apply in the portal, or `##class(Ens.Director).UpdateProduction()`), so the four items start again with their new settings. Each logs a line on start naming its mode, its provider configuration and its model ([Agent.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Bridge/Operation/Agent.cls), `OnInit`). The mode in that line is the one at start; the test set live mode after the restart, which works because the mode is resolved again for each run ([RunSpec.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Bridge/RunSpec.cls), `FromRequest`).

**5. Live mode.** An item set to `auto` resolves to live only when Shutter's own provider is configured (Agent.cls, `ResolveMode`), so with only `AI.LLM.OpenAI` the items stay in replay. The test set the instance's agent mode:

```sql
SELECT Shutter.Setup_RecordAgentMode('live')
```

That applies to every agent item set to `auto`, Agent Board included, which has no provider here; its start-up warning says every live run will then fail (Agent.cls, `OnInit`). An item's own `Mode` setting comes before the instance's, so `Mode` set to `live` on the four items alone would leave Agent Board in replay; that was not tried. A mode set this way survives a restart, unless the container's `SHUTTER_AGENT_MODE` names another one, which the production records at each start.

**Check before a case.** `GET /api/shutter/settings` then said `agentMode` live, and each of the four items `effectiveMode` live with `answeredBy` `AI.LLM.OpenAI`.

**Undo, as tested.** Remove the four items' `ProviderConfig`, save and update the production, `SELECT Shutter.Setup_RecordAgentMode('auto')`, then delete `AI.LLM.OpenAI` with `%ConfigStore.Configuration`'s `Delete` and `Shutter.OpenAI` with `%Wallet.KeyValue`'s `Delete`. The test also deleted the `Shutter` collection and the `Shutter_Secrets` resource, because it had created them; where Shutter's own provider is configured, leave them, since `Shutter.Anthropic` uses them. After the undo, `/settings` said `agentMode` auto and every item replay. The cases C-000001 to C-000005, the question and AI Hub's agent sessions stayed on the instance as history.

## What differs from Anthropic

- **Model choice.** `gpt-5.5` and `chat-latest`, the two current OpenAI models tried, refuse the runner's `max_tokens`, as above; `gpt-4.1` takes it. On Anthropic the same parameter is the one the API expects.
- **The Costs page reads 0 USD.** `Shutter.Store.ModelPrice` holds only Anthropic's list prices ([ModelPrice.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Store/ModelPrice.cls), `Seed`), so a run on another model has no price: `ModelPrice.Cost` returns none, and the case page showed each run's cost as null. After the test, `/costs` counted 23 live runs and 0 USD spent: 20 on `gpt-4.1` (222,747 prompt, 4,809 completion and 108,416 cache-read tokens) and the 3 failed `gpt-5.5` runs with no tokens. The tokens show; the money doesn't.
- **The day's budget doesn't hold.** `SHUTTER_DAILY_BUDGET_USD` counts the day's `CostUSD` ([Budget.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Util/Budget.cls)), which stays at 0, so it never stops runs on an unpriced model; only the reservation for each run in flight counts against it (the mean cost of the last twenty priced live runs, else 0.50 USD, `Budget.Estimate`). This is read from the code; the test set no budget. Keep a hard limit at the provider.
- **A price row added by hand would over-count.** `ModelPrice.Cost` takes prompt tokens and cache reads as separate counts, but the runner stores the prompt tokens as AI Hub reports them (`FillStats` takes `total_prompt_tokens` as it is, though a comment in `Cost` says the bridge takes the cache reads out), and OpenAI's count includes the cached ones: two identical calls straight through the provider each reported 5,214 prompt tokens, the second with 4,992 of them read from cache. At `gpt-4.1`'s list prices (input 2.00, cached input 0.50 and output 8.00 USD per million tokens, from OpenAI's model page on the day) the four scenario runs cost 0.2586 USD by OpenAI's own counting (0.0545 to 0.0900 a scenario); the same tokens through `ModelPrice.Cost` would read 1.3 to 2.0 times that.
- **Caching happened by itself.** The two probe calls above asked for no caching, and the second still read 4,992 tokens from cache. On the board, where the runner asks AI Hub for caching as it does for Anthropic, cache reads showed in 15 of the 16 board runs, and were 49% of the prompt tokens of the 20 recorded runs; no cache writes were reported.
- **Repairs.** A submission naming evidence the agent wasn't given is refused with the keys it was given, and the agent submits again. In 20 runs that never happened on its own. Forced once, in a conformance run on C-000004's evidence made straight through the runner (outside the board, so not among the 20), by telling it to cite a key that doesn't exist, the first `SubmitFindings` got `accepted: false` ("evidence_refs names evidence that was not given: patient_notes; cite the keys of the evidence you received ...") and the second, without it, was accepted; the run ended `ok` after 4 turns and 7 tool calls.
- **Health doesn't see it.** The Health page's `provider`, `wallet_secret` and `provider_config` describe Shutter's own `AI.LLM.Shutter` and `Shutter.Anthropic` only, so they say nothing of `AI.LLM.OpenAI`: after the runs, `provider` was still empty and `wallet_secret` and `provider_config` null, as before. Its `last_live_run` named the model, `gpt-4.1`, but not the configuration. The Settings page's `answeredBy` is the place that names the provider in use.

## What Shutter's install doesn't do for you

At commit `4e5ab015` it configured Anthropic only, and these were the places that assumed it. With `OPENAI_API_KEY` the install now does the first four for OpenAI, and the Health page's check and `ClearProvider` follow the provider it configured; the price list, the budget and `max_tokens` are as they were.

- The install and the container read one key, `ANTHROPIC_API_KEY` (`.env.example` line 11, `docker-compose.yml` line 40); whatever key is set there is written as Anthropic's, since `ConfigureProvider` doesn't check which provider it is for.
- `Shutter.Setup.ConfigureProvider` ([Setup.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Setup.cls), line 2354) writes the secret `Shutter.Anthropic` and `AI.LLM.Shutter` with `model_provider` anthropic; nothing writes another provider's configuration, so steps 1 and 2 are by hand.
- The production's start ([Production.cls](https://github.com/MxSalata/shutter/blob/main/src/Shutter/Production.cls), line 35) configures the provider again from `ANTHROPIC_API_KEY` when it changed or went missing; it leaves `AI.LLM.OpenAI` and the items' `ProviderConfig` alone.
- `auto` means live only when `AI.LLM.Shutter` is configured (`Setup.ProviderConfigured`, line 2601), so another provider needs step 5.
- The price list is Anthropic's, and the budget is counted from it, as above.
- The Health page's provider checks name `Shutter.Anthropic` (`Setup.WalletSecretState`, line 2475).
- `Shutter.Setup_ClearProvider()` (line 2619) removes only `AI.LLM.Shutter` and `Shutter.Anthropic`; the undo above is by hand.
- The runner's `max_tokens` (`AIHub.cls`, line 100) limits the choice of OpenAI model.

## Measured, per run

All on `gpt-4.1`, provider configuration `OpenAI`, every member's status `ok` and no submission refused. Tokens are prompt / completion / cache read, as OpenAI reported them; then the model's turns and tool calls.

| Pass | Case | Member | Tokens | Turns | Tool calls |
| --- | --- | --- | --- | --- | --- |
| 1, S2 | C-000002 | Encounter | 6,817 / 157 / 3,328 | 2 | 1 |
| 1, S2 | C-000002 | Impact | 11,492 / 239 / 4,096 | 3 | 2 |
| 1, S2 | C-000002 | Conformance | 13,877 / 271 / 8,576 | 3 | 6 |
| 1, S2 | C-000002 | Coordinator | 8,132 / 254 / 4,096 | 2 | 1 |
| 1, S8 | C-000003 | Encounter | 7,380 / 195 / 3,584 | 2 | 1 |
| 1, S8 | C-000003 | Conformance | 12,751 / 217 / 8,064 | 3 | 2 |
| 1, S8 | C-000003 | Impact | 12,564 / 213 / 7,936 | 3 | 2 |
| 1, S8 | C-000003 | Coordinator | 8,800 / 326 / 4,480 | 2 | 1 |
| 2, S2 | C-000004 | Encounter | 6,809 / 153 / 3,328 | 2 | 1 |
| 2, S2 | C-000004 | Conformance | 11,953 / 187 / 7,424 | 3 | 2 |
| 2, S2 | C-000004 | Impact | 17,973 / 340 / 12,544 | 4 | 6 |
| 2, S2 | C-000004 | Coordinator | 8,151 / 268 / 4,096 | 2 | 1 |
| 2, S8 | C-000005 | Impact | 12,464 / 222 / 3,584 | 3 | 2 |
| 2, S8 | C-000005 | Encounter | 12,190 / 219 / 3,456 | 3 | 2 |
| 2, S8 | C-000005 | Conformance | 19,069 / 314 / 8,192 | 4 | 6 |
| 2, S8 | C-000005 | Coordinator | 8,725 / 238 / 0 | 2 | 1 |

Both S2 cases were approved by the scenario runner's `--approve`, as in the other receipts. The tool arguments were stored as JSON text, the same shape as the `claude-opus-5-5` recordings of S2 and S8 on the same instance.
