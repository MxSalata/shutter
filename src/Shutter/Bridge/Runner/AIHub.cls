Include Ensemble

/// The live runner: runs a declarative AI Hub agent for one request and fills the response. It
/// creates the agent, sets the case, initialises it from its class parameters (provider from the
/// Config Store, model, evidence tools), adds the terminal tool as an instance it keeps, attaches
/// the knowledge collection, the scope and the trace policies, runs the agent with a monitor that
/// enforces the token budget, and reads the result the terminal tool accepted. Failures are
/// reported in the response's Status, never retried here. When the run was resolved under the API mimic
/// (the spec's MockConfig), the provider is the mimic's, set before %Init so the class's own
/// configuration is never read; the run is labelled model mock and is never recorded. That %Init leaves a
/// provider set before it alone is what the mock's SelfTest proves on build 154, not something the
/// framework documents, so every run checks it after %Init and ends with status error, before any model
/// call, when the agent came out with another provider.
Class Shutter.Bridge.Runner.AIHub Extends Shutter.Bridge.Runner
{

Method Run(spec As Shutter.Bridge.RunSpec, ByRef response As Shutter.Bridge.Msg.AgentResponse) As %Status
{
    Set start = $ZHOROLOG
    Set response.StartedAt = ##class(Shutter.Util.Time).NowUTC(), response.StartedAtMs = ##class(Shutter.Util.Time).NowUTCms()
    Set response.Mode = $SELECT(spec.Mode = "": "live", 1: spec.Mode)
    Set agent = "", session = "", monitor = "", submit = "", trace = "", scope = ""
    Set turns = $SELECT(+spec.MaxIterations > 0: +spec.MaxIterations, 1: 8)
    // The terminal tool by its name: a board answer's (before an answer's, which it contains), an answer's, a review's,
    // a plan's, else a specialist's findings.
    Set lowerTerminal = $ZCONVERT(spec.TerminalTool, "L")
    Set terminal = $SELECT(lowerTerminal [ "boardanswer": "SubmitBoardAnswer", lowerTerminal [ "answer": "SubmitAnswer", lowerTerminal [ "review": "SubmitReview", lowerTerminal [ "plan": "SubmitPlan", 1: "SubmitFindings")
    // A question's run is keyed by its question id; its agent, tools and scope work on the question's case.
    Set caseKey = ..CaseKeyOf(spec, .question)
    // The mimic as the run was resolved, not as the switch is now, so such a run never reaches another provider.
    Set mock = spec.MockConfig
    Try {
        If (spec.AgentClass = "") || '##class(%Dictionary.CompiledClass).%ExistsId(spec.AgentClass) {
            Set response.Status = "error", response.Error = "Agent class not available: " _ spec.AgentClass
        } ElseIf (mock '= "") && (response.Mode = "record") {
            // Nothing the mimic answers may become a recording.
            Set response.Status = "refused", response.Error = "Record mode is refused while the API mimic is on"
        } Else {
            // The provider goes in before %Init, which then leaves the class's PROVIDERCONFIG unread: the mimic's
            // while it is on, else the item's ProviderConfig when set. One that cannot be made fails the run.
            Set provider = "", model = ""
            If mock '= "" {
                Set provider = ..MockProvider(mock, spec, terminal, .model)
            } ElseIf spec.ProviderConfig '= "" {
                Set provider = ..ProviderFrom(spec.ProviderConfig, .model)
            } ElseIf ##class(Shutter.Setup).ProviderConfigured() {
                // Shutter's own configuration (ConfigureProvider, v1.35): built here rather than by the agent class from its
                // PROVIDERCONFIG parameter, so the bound on one call (BoundCall) applies to the default path too.
                Set provider = ..ProviderFrom($GET(^Shutter.Config("aihub", "provider")), .model)
            }
            Set agent = $CLASSMETHOD(spec.AgentClass, "%New")
            If agent.%IsA("Shutter.Agent.Base") {
                Set agent.CaseId = caseKey
                // A question (CONTRACTS 14.3): the agent swaps its investigation for the question's rules and answers
                // through the request's terminal tool.
                If $ISOBJECT(question) Set agent.QuestionTier = question.Tier, agent.Terminal = terminal
            }
            If $ISOBJECT(provider) Set agent.Provider = provider
            Set sc = agent.%Init({"caseId": (caseKey), "role": (spec.Role), "member": (spec.MemberCode)})
            If $$$ISERR(sc) {
                Set response.Status = "model_error", response.Error = "The agent could not start: " _ $SYSTEM.Status.GetErrorText(sc)
            } ElseIf $ISOBJECT(provider) && (agent.Provider '= provider) {
                // The provider set before %Init must still be the agent's: a mimic run that reached the class's own
                // configuration (and the instance's key) would be labelled mock at cost 0, so the run ends here instead.
                Set response.Status = "error", response.Error = "The agent replaced the runner's provider"
            } Else {
                // The model: the mimic's; else the item's Model, then its configuration's, then the class's.
                If mock '= "" {
                    Set agent.Model = model
                } ElseIf spec.Model '= "" {
                    Set agent.Model = spec.Model
                } ElseIf model '= "" {
                    Set agent.Model = model
                }
                Set agent.MaxIterations = turns
                // The terminal tool: an instance this runner keeps, so the accepted result is read from it.
                Set submit = $CLASSMETHOD("Shutter.Tools." _ terminal, "%New")
                Set submit.CaseId = caseKey
                If terminal = "SubmitBoardAnswer" Set submit.FactIds = ..FactIdsOf(spec.Context)
                If (terminal = "SubmitAnswer") || (terminal = "SubmitBoardAnswer") Set submit.CiteIds = ..CiteIdsOf(spec.Context)
                // Findings and plans may cite only the evidence they were given (v1.35).
                If (terminal = "SubmitFindings") || (terminal = "SubmitPlan") Set submit.CiteIds = ..EvidenceIdsOf(spec.Context)
                Do agent.ToolManager.AddTool(submit)
                // The member's knowledge collection as search tools, when the library is built.
                Do ..AttachKnowledge(agent, spec, .attached)
                // Policies: the run is held to its case; every tool call is audited into the trace.
                Set scope = ##class(Shutter.Bridge.Policy.Scope).%New()
                Set scope.CaseId = caseKey
                Do agent.ToolManager.SetAuthPolicy(scope)
                Set trace = ##class(Shutter.Bridge.Policy.Trace).%New()
                Set trace.RunKey = spec.EnsMessageId
                Do agent.ToolManager.SetAuditPolicy(trace)
                // The tool catalogue is pinned (Shutter.Bridge.Catalogue, v1.38): what the framework discovered must be exactly
                // the evidence tools, the terminal and the attached collections' search tools, or no model call is made.
                If '..CataloguePinned(agent, terminal, $GET(attached), .catalogueProblem) {
                    Set response.Status = "catalogue_mismatch", response.Error = "The agent's tools are not the declared ones: " _ catalogueProblem
                    Quit
                }
                // The session, with prompt caching on, and the monitor.
                Set config = {"max_tokens": 16000, "cache": {"enabled": true, "cache_system_prompt": true, "cache_tool_definitions": true}}
                Set session = agent.CreateSession(config)
                Set monitor = ##class(Shutter.Bridge.Monitor).%New()
                Set monitor.TokenBudget = +spec.TokenBudget
                If +spec.RequestTimeoutSeconds > 0 Set monitor.Deadline = $ZHOROLOG + (spec.RequestTimeoutSeconds * turns)
                // The tag carries a code of this run, so text inside the evidence cannot close it (B9).
                Set nonce = $ZHEX($RANDOM(1048576)) _ $ZHEX($RANDOM(1048576))
                Set prompt = spec.Goal _ $CHAR(10, 10) _ "<evidence-" _ nonce _ " case=""" _ caseKey _ """>" _ $CHAR(10) _ spec.Context _ $CHAR(10) _ "</evidence-" _ nonce _ ">"
                $$$TRACE("Running " _ spec.AgentClass _ " for " _ spec.CorrelationKey _ ": up to " _ turns _ " turns, budget " _ (+spec.TokenBudget) _ " tokens")
                // Run(session, goal, callback) on build 154; the turn limit is the MaxIterations property.
                Set final = agent.Run(session, prompt, monitor)
                If $ISOBJECT(final) && '$ISOBJECT(final.Content) Set response.Content = $EXTRACT(final.Content, 1, 20000)
                If submit.Result '= "" {
                    Set response.ResultJSON = submit.Result, response.Status = "ok"
                    // The budget is judged after the run: the framework's loop cannot be stopped from outside.
                    If (+spec.TokenBudget > 0) && (monitor.TotalTokens > +spec.TokenBudget) {
                        Set response.Status = "budget_exceeded"
                        Set response.Error = "The run used " _ monitor.TotalTokens _ " tokens, over its budget of " _ (+spec.TokenBudget) _ "; its result is kept for inspection but not used"
                    }
                } Else {
                    Set response.Status = "schema_failed"
                    Set response.Error = "The agent finished without an accepted " _ terminal _ $SELECT(submit.LastError '= "": ": " _ submit.LastError, 1: "")
                }
            }
        }
    } Catch ex {
        Set text = ex.DisplayString()
        Set response.Error = $EXTRACT(text, 1, 2000)
        Set lower = $ZCONVERT(text, "L")
        Set response.Status = $SELECT($ISOBJECT(monitor) && (monitor.Stopped '= ""): monitor.Stopped, lower [ "budget_exceeded": "budget_exceeded", lower [ "timeout": "timeout", lower [ "timed out": "timeout", lower [ "denied": "denied", lower [ "loop": "loop_detected", 1: "model_error")
        If $ISOBJECT(submit) && (submit.Result '= "") {
            Set response.ResultJSON = submit.Result
            // The terminal tool accepted a result and only the closing sentence was missing when the turns ran out: the
            // run did its work, so it is ok, with the stop noted in the error field for the record.
            If lower [ "maxiterations" Set response.Status = "ok", response.Error = "The turns ran out after the result was accepted: " _ $EXTRACT(response.Error, 1, 300)
        }
    }
    Do ..FillStats(response, agent, session, monitor, trace)
    // No model answered a run of the mimic's: it is labelled so, costs nothing and is never recorded.
    If mock '= "" Set response.Model = "mock", response.ProviderConfig = $PIECE(mock, ".", *)
    Set response.DurationMs = (($ZHOROLOG - start) * 1000) \ 1
    If (mock = "") && (response.Mode = "record") && (response.Status = "ok") Do ..Record(spec, response, session)
    Quit $$$OK
}

/// A provider made from a Config Store configuration, resolved as the agent class's @{config:...} is: a name of
/// fewer than three parts is under AI.LLM (Shutter is AI.LLM.Shutter), and secrets are resolved. Returns the
/// configuration's model too. Build 154's %AI.Provider has Create(name, settings) and no CreateFromConfig. Throws
/// when the configuration cannot be read or the provider made.
ClassMethod ProviderFrom(name As %String, Output model As %String) As %AI.Provider
{
    Set model = ""
    Set fqn = $SELECT($LENGTH(name, ".") < 3: "AI.LLM." _ name, 1: name)
    $$$ThrowOnError(##class(%ConfigStore.Configuration).GetDetails(fqn, .details, 0, 1))
    Set model = details.%Get("model")
    Do ..BoundCall(details)
    Quit ##class(%AI.Provider).Create(details.%Get("model_provider"), details)
}

/// A bound on one model call (v1.35): the provider's HTTP client gets a request timeout (Shutter.Setup.ProviderTimeoutSeconds,
/// 120 s unless configured) and a connect timeout of 10 s, unless the configuration sets http_config itself. Without it a
/// hung provider holds a board member until the board's 600 s timeout, since the run's deadline is only checked between
/// the model's turns (Shutter.Bridge.Monitor).
ClassMethod BoundCall(details As %DynamicObject)
{
    If '$ISOBJECT(details) || details.%IsDefined("http_config") Quit
    Set http = {}
    Set http."request_timeout_secs" = ##class(Shutter.Setup).ProviderTimeoutSeconds(), http."connect_timeout_secs" = 10
    Set details."http_config" = http
}

/// The case a run works on: the correlation key, or for a question's run (keyed by its question id, CONTRACTS 14.2) the
/// question's case, with the question in <var>question</var> ("" otherwise).
ClassMethod CaseKeyOf(spec As Shutter.Bridge.RunSpec, Output question As %RegisteredObject) As %String
{
    Set question = ""
    Set key = spec.CorrelationKey
    If ($EXTRACT(key, 1, 2) '= "Q-") || '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Store.CaseQuestion") Quit key
    Set question = $CLASSMETHOD("Shutter.Store.CaseQuestion", "ByQuestionId", key)
    If '$ISOBJECT(question) || '$ISOBJECT(question.Case) Set question = "" Quit key
    Quit question.Case.CaseId
}

/// What a question's answer may cite, comma separated: the keys of the context's case section and the keys one level
/// down in it (where the evidence may sit), and the fact ids, as Shutter.Store.CaseQuestion.CiteKnown accepts them.
ClassMethod CiteIdsOf(context As %String) As %String
{
    Set ids = ..FactIdsOf(context)
    Set o = ##class(Shutter.Util.Json).Parse(context, .sc)
    If '$ISOBJECT(o) || (o.%GetTypeOf("case") '= "object") Quit ids
    Set it = o.case.%GetIterator()
    While it.%GetNext(.k, .v) {
        Set ids = ids _ $SELECT(ids = "": "", 1: ",") _ k
        If $ISOBJECT(v) && v.%IsA("%Library.DynamicObject") {
            Set it2 = v.%GetIterator()
            While it2.%GetNext(.k2) { Set ids = ids _ "," _ k2 }
        }
    }
    Quit ids
}

/// What findings and plans may cite (v1.35): the keys of the board context's evidence object and the keys one level down in
/// it (where the error, the ward state's fields and the like sit), plus "findings" for the coordinator, comma separated.
/// The names the prompts used before v1.39 for two of the keys, "error" for the failure and "later_event" for the timeline,
/// stay citable while the evidence has the key they stand for: the recordings and the evaluation table carry them.
ClassMethod EvidenceIdsOf(context As %String) As %String
{
    Set ids = ""
    Set o = ##class(Shutter.Util.Json).Parse(context, .sc)
    If '$ISOBJECT(o) Quit ""
    Set ev = o.%Get("evidence")
    If $ISOBJECT(ev) && ev.%IsA("%Library.DynamicObject") {
        Set it = ev.%GetIterator()
        While it.%GetNext(.k, .v) {
            Set ids = ids _ $SELECT(ids = "": "", 1: ",") _ k
            If $ISOBJECT(v) && v.%IsA("%Library.DynamicObject") {
                Set it2 = v.%GetIterator()
                While it2.%GetNext(.k2) { If '$FIND("," _ ids _ ",", "," _ k2 _ ",") Set ids = ids _ "," _ k2 }
            }
        }
        If ev.%IsDefined("failure") && '$FIND("," _ ids _ ",", ",error,") Set ids = ids _ ",error"
        If ev.%IsDefined("timeline") && '$FIND("," _ ids _ ",", ",later_event,") Set ids = ids _ ",later_event"
    }
    If o.%IsDefined("findings") Set ids = ids _ $SELECT(ids = "": "", 1: ",") _ "findings"
    Quit ids
}

/// The ids of a question context's whatif.facts, comma separated: the only facts a board answer may name.
ClassMethod FactIdsOf(context As %String) As %String
{
    Set ids = ""
    Set o = ##class(Shutter.Util.Json).Parse(context, .sc)
    If '$ISOBJECT(o) || '$ISOBJECT(o.whatif) || (o.whatif.%GetTypeOf("facts") '= "array") Quit ""
    Set it = o.whatif.facts.%GetIterator()
    While it.%GetNext(, .f) {
        Set id = $SELECT($ISOBJECT(f): ##class(Shutter.Util.Json).Str(f, "id"), 1: "")
        If (id '= "") && '$ISOBJECT(id) Set ids = ids _ $SELECT(ids = "": "", 1: ",") _ id
    }
    Quit ids
}

/// The API mimic's provider for one run: its configuration's openai provider, base_url and model, with the run's
/// context as the API key (MockToken), so the mimic knows the recording, case, member and terminal tool the run is
/// for. No secret is read: the configuration's own key is a placeholder, and it is replaced.
ClassMethod MockProvider(config As %String, spec As Shutter.Bridge.RunSpec, terminal As %String, Output model As %String) As %AI.Provider
{
    Set model = ""
    Set fqn = $SELECT($LENGTH(config, ".") < 3: "AI.LLM." _ config, 1: config)
    $$$ThrowOnError(##class(%ConfigStore.Configuration).GetDetails(fqn, .details, 0, 0))
    If (details.%Get("model_provider") '= "openai") || (details.%Get("base_url") = "") {
        $$$ThrowStatus($$$ERROR($$$GeneralError, "The API mimic's configuration " _ fqn _ " must name the openai provider and a base_url"))
    }
    Set model = details.%Get("model")
    Set details."api_key" = ..MockToken(spec, terminal)
    Do ..BoundCall(details)
    Quit ##class(%AI.Provider).Create("openai", details)
}

/// The run's context for the API mimic, carried as its API key: smk1. and the JSON in unpadded base64url, with the
/// replay key, the case, the member, the terminal tool and the production message.
ClassMethod MockToken(spec As Shutter.Bridge.RunSpec, terminal As %String) As %String
{
    Set ctx = {"k": (spec.ReplayKey()), "c": (spec.CorrelationKey), "m": (spec.MemberCode), "t": (terminal), "r": (spec.EnsMessageId)}
    Quit "smk1." _ $TRANSLATE($SYSTEM.Encryption.Base64Encode($ZCONVERT(ctx.%ToJSON(), "O", "UTF8"), 1), "+/=", "-_")
}

/// Tokens, turns, tool calls, the model and the saved session.
Method FillStats(response As Shutter.Bridge.Msg.AgentResponse, agent, session, monitor, trace) [ Private ]
{
    If $ISOBJECT(agent) {
        Try { Set response.Model = agent.Model } Catch { }
    }
    If $ISOBJECT(session) {
        Try {
            Set stats = session.GetStats()
            If $ISOBJECT(stats) {
                Set response.PromptTokens = +stats."total_prompt_tokens"
                Set response.CompletionTokens = +stats."total_completion_tokens"
                Set response.ToolCalls = +stats."total_tool_calls"
                // AI Hub's own timing counters and reasoning tokens (v1.35), when the build returns them.
                If stats.%IsDefined("total_llm_duration_ms") Set response.LlmMs = +stats."total_llm_duration_ms"
                If stats.%IsDefined("total_tool_duration_ms") Set response.ToolMs = +stats."total_tool_duration_ms"
                If stats.%IsDefined("total_reasoning_tokens") Set response.ReasoningTokens = +stats."total_reasoning_tokens"
            }
        } Catch { }
        Try {
            Set sc = session.%Save()
            If $$$ISOK(sc) Set response.SessionId = session.%Id()
        } Catch { }
    }
    If $ISOBJECT(monitor) {
        Set response.Iterations = $SELECT(monitor.Iterations > 0: monitor.Iterations, 1: "")
        If +response.PromptTokens = 0 Set response.PromptTokens = monitor.PromptTokens
        If +response.CompletionTokens = 0 Set response.CompletionTokens = monitor.CompletionTokens
        Set response.CacheReadTokens = monitor.CacheReadTokens
        Set response.CacheCreationTokens = monitor.CacheCreationTokens
        If (+response.ToolCalls = 0) && (monitor.ToolCalls > 0) Set response.ToolCalls = monitor.ToolCalls
    }
    If $ISOBJECT(trace) && (+response.ToolCalls = 0) Set response.ToolCalls = trace.Calls
}

/// The member's knowledge collection, as search tools, when the library is present and built: the board member row's
/// collection; for an agent with no row (the production review's), the agent class's KNOWLEDGE parameter; else every
/// collection.
/// The tool catalogue against the declared one (Shutter.Bridge.Catalogue, v1.38): the agent class's TOOLSETS, the run's
/// terminal tool and the knowledge collections attached; problem says what differs.
ClassMethod CataloguePinned(agent, terminal As %String, attached As %String, Output problem As %String) As %Boolean
{
    Set problem = ""
    Set toolsets = $SELECT(##class(%Dictionary.CompiledParameter).%ExistsId($CLASSNAME(agent) _ "||TOOLSETS"): $PARAMETER(agent, "TOOLSETS"), 1: "")
    Set expected = ##class(Shutter.Bridge.Catalogue).Expected(toolsets, terminal, attached)
    Set discovered = ##class(Shutter.Bridge.Catalogue).NamesOf(agent.ToolManager.%Discover())
    Quit ##class(Shutter.Bridge.Catalogue).Check(expected, discovered, .problem)
}

/// The pin as the runner applies it, for the proof over SQL on an AI Hub build: the agent built as Run builds it (its
/// toolsets, the terminal, the collection's search tools), plus an extra tool when one is named, and the verdict with
/// the names: {expected, discovered, ok, problem}.
ClassMethod CataloguePin(agentClass As %String = "Shutter.Agent.Conformance", terminal As %String = "SubmitFindings", collection As %String = "", extra As %String = "") As %String [ SqlProc ]
{
    Try {
        // SQL passes its empty string as $CHAR(0).
        If terminal = $CHAR(0) Set terminal = ""
        If collection = $CHAR(0) Set collection = ""
        If extra = $CHAR(0) Set extra = ""
        Set agent = $CLASSMETHOD(agentClass, "%New")
        Set toolsets = $SELECT(##class(%Dictionary.CompiledParameter).%ExistsId(agentClass _ "||TOOLSETS"): $PARAMETER(agentClass, "TOOLSETS"), 1: "")
        For i = 1:1:$LENGTH(toolsets, ",") { Set ts = $ZSTRIP($PIECE(toolsets, ",", i), "<>W") If ts '= "" Do agent.UseToolSet(ts) }
        If terminal '= "" Do agent.ToolManager.AddTool($CLASSMETHOD("Shutter.Tools." _ terminal, "%New"))
        Set attached = ""
        If collection '= "" Set n = ##class(Shutter.Knowledge.Library).Attach(agent, collection, .problems, .attached)
        If extra '= "" Do agent.ToolManager.AddTool($CLASSMETHOD("Shutter.Tools." _ extra, "%New"))
        Set expected = ##class(Shutter.Bridge.Catalogue).Expected(toolsets, terminal, attached)
        Set discovered = ##class(Shutter.Bridge.Catalogue).NamesOf(agent.ToolManager.%Discover())
        Set ok = ##class(Shutter.Bridge.Catalogue).Check(expected, discovered, .problem)
        Set out = {}
        Set out.expected = $LISTTOSTRING(expected, ","), out.discovered = $LISTTOSTRING(discovered, ",")
        Do out.%Set("ok", ok, "boolean")
        Set out.problem = problem, out.attached = attached
        If $GET(problems) '= "" Set out."knowledge_problems" = problems
        Return out.%ToJSON()
    } Catch ex {
        Return {"error": (ex.DisplayString())}.%ToJSON()
    }
}

Method AttachKnowledge(agent, spec As Shutter.Bridge.RunSpec, Output attached As %String) [ Private ]
{
    Set attached = ""
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Knowledge.Library") Quit
    Set collection = ""
    Set member = ##class(Shutter.Store.BoardMember).ByCode(spec.MemberCode)
    If $ISOBJECT(member) && (member.KnowledgeCollection '= "") Set collection = member.KnowledgeCollection
    If (collection = "") && ##class(%Dictionary.CompiledParameter).%ExistsId($CLASSNAME(agent) _ "||KNOWLEDGE") Set collection = $PARAMETER(agent, "KNOWLEDGE")
    If collection = "" Set collection = "all"
    Set n = $CLASSMETHOD("Shutter.Knowledge.Library", "Attach", agent, collection, .problems, .attached)
    If $GET(problems) '= "" $$$LOGWARNING("Knowledge for " _ spec.MemberCode _ ": " _ problems)
    $$$TRACE("Knowledge collections attached for " _ spec.MemberCode _ ": " _ n _ " (" _ collection _ ")")
}

/// Record mode: store the run, its transcript and its tool calls as a recording for replays.
Method Record(spec As Shutter.Bridge.RunSpec, response As Shutter.Bridge.Msg.AgentResponse, session) [ Private ]
{
    Try {
        Set transcript = ""
        If $ISOBJECT(session) Set transcript = session.Export()
        If $ISOBJECT(transcript) Set transcript = transcript.%ToJSON()
        Set toolCalls = ##class(Shutter.Bridge.ToolCall).ForRun(spec.EnsMessageId).%ToJSON()
        Set sc = ##class(Shutter.Bridge.Record).Store(spec, response, transcript, toolCalls, .record)
        If $$$ISOK(sc) && $ISOBJECT($GET(record)) Set response.RecordId = record.%Id()
        If $$$ISERR(sc) $$$LOGWARNING("The recording could not be stored: " _ $SYSTEM.Status.GetErrorText(sc))
    } Catch ex {
        $$$LOGWARNING("The recording could not be stored: " _ ex.DisplayString())
    }
}

/// The tools an agent class exposes, as the model sees them: the evidence tools plus the terminal
/// tool, with their JSON Schemas. Needs no provider. For checks over SQL.
ClassMethod DescribeTools(agentClass As %String = "Shutter.Agent.Conformance", terminal As %String = "SubmitFindings", collection As %String = "") As %String [ SqlProc ]
{
    Try {
        Set agent = $CLASSMETHOD(agentClass, "%New")
        Do agent.UseToolSet("Shutter.Tools.Evidence")
        Set submit = $CLASSMETHOD("Shutter.Tools." _ terminal, "%New")
        Do agent.ToolManager.AddTool(submit)
        Set problems = ""
        If collection '= "" Set n = ##class(Shutter.Knowledge.Library).Attach(agent, collection, .problems)
        Set tools = agent.ToolManager.%Discover()
        If collection '= "" Return {"tools": (tools), "knowledge_attached": ($GET(n)), "knowledge_problems": (problems)}.%ToJSON()
        If $ISOBJECT(tools) Return tools.%ToJSON()
        Return "" _ tools
    } Catch ex {
        Return {"error": (ex.DisplayString())}.%ToJSON()
    }
}

/// Whether an agent class starts: the provider configuration resolves and the model is set. Prints
/// no secret. For checks over SQL.
ClassMethod Probe(agentClass As %String = "Shutter.Agent.Conformance") As %String [ SqlProc ]
{
    Set out = {}
    Try {
        Set agent = $CLASSMETHOD(agentClass, "%New")
        Set agent.CaseId = "C-000000"
        Set sc = agent.%Init({"caseId": "C-000000", "role": "specialist", "member": "probe"})
        Do out.%Set("init", $$$ISOK(sc), "boolean")
        If $$$ISERR(sc) Set out.error = $SYSTEM.Status.GetErrorText(sc)
        Set out.model = agent.Model
        Set out.provider = $SELECT($ISOBJECT(agent.Provider): agent.Provider.Name, 1: "")
        Set out."system_prompt_chars" = $LENGTH(agent.SystemPrompt)
        Set tools = agent.ToolManager.%Discover()
        Set names = []
        If $ISOBJECT(tools) {
            Set iter = tools.%GetIterator()
            While iter.%GetNext(.i, .t) { Do names.%Push(##class(Shutter.Util.Json).Str(t, "name")) }
        }
        Set out.tools = names
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out.%ToJSON()
}

/// Run one board member live for an existing case, outside the production: builds the request the
/// case workflow would build (the snapshot summary, and the specialists' findings for the coordinator),
/// runs this runner in <var>mode</var> (live or record; any other word is refused, so a replay never runs
/// live by mistake) and returns the response as JSON. For checks over SQL once a provider is configured.
/// The tool calls are keyed test:<case>:<member>:<n>, one key per run (run_key in the answer; a member's
/// runs are found with LIKE 'test:<case>:<member>:%'), so two runs of one member never share a list; mock
/// says whether the API mimic answered. No AgentRun row is written: a test run is not the case's.
ClassMethod TestRun(caseId As %String, memberCode As %String = "conformance", mode As %String = "live", tokenBudget As %Integer = 60000) As %String [ SqlProc ]
{
    // A live run costs money: only a caller who may operate Shutter gets one.
    If '$SYSTEM.Security.Check("Shutter_Operate", "USE") Quit {"error": "TestRun needs the Shutter_Operate resource"}.%ToJSON()
    If '$LISTFIND($LISTBUILD("live", "record"), $ZCONVERT(mode, "L")) Quit {"error": "mode must be live or record"}.%ToJSON()
    Try {
        Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
        If '$ISOBJECT(case) Return {"error": ("Unknown case " _ caseId)}.%ToJSON()
        Set member = ##class(Shutter.Store.BoardMember).ByCode(memberCode)
        If '$ISOBJECT(member) Return {"error": ("Unknown board member " _ memberCode)}.%ToJSON()
        Set snap = case.CurrentSnapshot
        If '$ISOBJECT(snap) Return {"error": "The case has no evidence snapshot"}.%ToJSON()
        Set findings = ""
        If member.Role '= "specialist" Set findings = ##class(Shutter.Store.Finding).ForSnapshot(snap).%ToJSON()
        Set request = ##class(Shutter.Process.CaseWorkflow).BuildAgentRequest(case, member, snap.Summary, findings, 0, .bsc)
        If '$ISOBJECT(request) Return {"error": ("The model's view of the case could not be built: " _ $SYSTEM.Status.GetErrorText(bsc))}.%ToJSON()
        // The operation's defaults, by hand: a business host cannot be instantiated outside the production.
        Set spec = ##class(Shutter.Bridge.RunSpec).%New()
        Set spec.AgentClass = $SELECT(request.AgentClass '= "": request.AgentClass, 1: member.AgentClass)
        Set spec.Role = request.Role, spec.MemberCode = request.MemberCode
        Set spec.Goal = request.Goal, spec.Context = request.Context
        Set spec.CorrelationKey = request.CorrelationKey, spec.SnapshotDigest = request.SnapshotDigest
        Set spec.ResultClass = request.ResultClass, spec.TerminalTool = request.TerminalTool
        Set spec.ConfigVersion = request.ConfigVersion
        Set spec.Mode = $ZCONVERT(mode, "L"), spec.RunnerClass = $CLASSNAME(), spec.MockConfig = ##class(Shutter.Setup).MockConfig()
        Set spec.MaxIterations = 8, spec.TokenBudget = tokenBudget, spec.RequestTimeoutSeconds = 120
        // One key per run: a second run of the same member must not append to the first one's tool calls.
        Set n = $INCREMENT(^Shutter.Counter("testrun"))
        Set spec.RecordKey = "", spec.EnsMessageId = "test:" _ caseId _ ":" _ memberCode _ ":" _ n, spec.EnsSessionId = ""
        Set response = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
        Set runner = ..%New()
        Set sc = runner.Run(spec, .response)
        Do ##class(Shutter.Bridge.Runner).Stamp(spec, response)
        Set out = response.ToObject()
        If $$$ISERR(sc) Set out."run_error" = $SYSTEM.Status.GetErrorText(sc)
        Set out."tool_calls_detail" = ##class(Shutter.Bridge.ToolCall).ForRun(spec.EnsMessageId)
        Set out."run_key" = spec.EnsMessageId
        Do out.%Set("mock", spec.MockConfig '= "", "boolean")
        Return out.%ToJSON()
    } Catch ex {
        Return {"error": (ex.DisplayString())}.%ToJSON()
    }
}

/// A saved session's statistics and its last message, as the framework reports them. For checks over SQL.
ClassMethod SessionStats(id As %String) As %String [ SqlProc ]
{
    Try {
        Set session = ##class(%AI.Agent.Session).%OpenId(id, , .sc)
        If '$ISOBJECT(session) Return {"error": ($SYSTEM.Status.GetErrorText(sc))}.%ToJSON()
        // A saved session answers only once attached to an agent.
        Set agent = ##class(Shutter.Agent.Conformance).%New()
        Set sc = agent.%InitWithSession(session)
        If $$$ISERR(sc) Return {"error": ($SYSTEM.Status.GetErrorText(sc))}.%ToJSON()
        Set out = {}
        Set out.stats = session.GetStats()
        Set messages = session.GetContext()
        Set out."message_count" = $SELECT($ISOBJECT(messages): messages.%Size(), 1: 0)
        Set roles = []
        If $ISOBJECT(messages) {
            Set iter = messages.%GetIterator()
            While iter.%GetNext(.i, .m) {
                Set content = m.%Get("content")
                Do roles.%Push(##class(Shutter.Util.Json).Str(m, "role") _ ":" _ $LENGTH($SELECT($ISOBJECT(content): content.%ToJSON(), 1: content)))
            }
        }
        Set out.roles = roles
        Return out.%ToJSON()
    } Catch ex {
        Return {"error": (ex.DisplayString())}.%ToJSON()
    }
}

}
