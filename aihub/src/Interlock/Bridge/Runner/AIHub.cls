Include Ensemble

/// The live runner: runs a declarative AI Hub agent for one request and fills the response. It
/// creates the agent, sets the case, initialises it from its class parameters (provider from the
/// Config Store, model, evidence tools), adds the terminal tool as an instance it keeps, attaches
/// the knowledge collection, the scope and the trace policies, runs the agent with a monitor that
/// enforces the token budget, and reads the result the terminal tool accepted. Failures are
/// reported in the response's Status, never retried here.
Class Interlock.Bridge.Runner.AIHub Extends Interlock.Bridge.Runner
{

Method Run(spec As Interlock.Bridge.RunSpec, ByRef response As Interlock.Bridge.Msg.AgentResponse) As %Status
{
    Set start = $ZHOROLOG
    Set response.StartedAt = ##class(Interlock.Util.Time).NowUTC()
    Set response.Mode = $SELECT(spec.Mode = "": "live", 1: spec.Mode)
    Set agent = "", session = "", monitor = "", submit = "", trace = "", scope = ""
    Set turns = $SELECT(+spec.MaxIterations > 0: +spec.MaxIterations, 1: 8)
    Set terminal = $SELECT($ZCONVERT(spec.TerminalTool, "L") [ "plan": "SubmitPlan", 1: "SubmitFindings")
    Try {
        If (spec.AgentClass = "") || '##class(%Dictionary.CompiledClass).%ExistsId(spec.AgentClass) {
            Set response.Status = "error", response.Error = "Agent class not available: " _ spec.AgentClass
        } Else {
            Set agent = $CLASSMETHOD(spec.AgentClass, "%New")
            If agent.%IsA("Interlock.Agent.Base") Set agent.CaseId = spec.CorrelationKey
            Set sc = agent.%Init({"caseId": (spec.CorrelationKey), "role": (spec.Role), "member": (spec.MemberCode)})
            If $$$ISERR(sc) {
                Set response.Status = "model_error", response.Error = "The agent could not start: " _ $SYSTEM.Status.GetErrorText(sc)
            } Else {
                If spec.ProviderConfig '= "" Set agent.Provider = ##class(%AI.Provider).CreateFromConfig(spec.ProviderConfig)
                If spec.Model '= "" Set agent.Model = spec.Model
                Set agent.MaxIterations = turns
                // The terminal tool: an instance this runner keeps, so the accepted result is read from it.
                Set submit = $CLASSMETHOD("Interlock.Tools." _ terminal, "%New")
                Set submit.CaseId = spec.CorrelationKey
                Do agent.ToolManager.AddTool(submit)
                // The member's knowledge collection as search tools, when the library is built.
                Do ..AttachKnowledge(agent, spec)
                // Policies: the run is held to its case; every tool call is audited into the trace.
                Set scope = ##class(Interlock.Bridge.Policy.Scope).%New()
                Set scope.CaseId = spec.CorrelationKey
                Do agent.ToolManager.SetAuthPolicy(scope)
                Set trace = ##class(Interlock.Bridge.Policy.Trace).%New()
                Set trace.RunKey = spec.EnsMessageId
                Do agent.ToolManager.SetAuditPolicy(trace)
                // The session, with prompt caching on, and the monitor.
                Set config = {"max_tokens": 4096, "cache": {"enabled": true, "cache_system_prompt": true, "cache_tool_definitions": true}}
                Set session = agent.CreateSession(config)
                Set monitor = ##class(Interlock.Bridge.Monitor).%New()
                Set monitor.TokenBudget = +spec.TokenBudget
                If +spec.RequestTimeoutSeconds > 0 Set monitor.Deadline = $ZHOROLOG + (spec.RequestTimeoutSeconds * turns)
                Set prompt = spec.Goal _ $CHAR(10, 10) _ "<evidence case=""" _ spec.CorrelationKey _ """>" _ $CHAR(10) _ spec.Context _ $CHAR(10) _ "</evidence>"
                $$$TRACE("Running " _ spec.AgentClass _ " for " _ spec.CorrelationKey _ ": up to " _ turns _ " turns, budget " _ (+spec.TokenBudget) _ " tokens")
                Set final = agent.Run(session, prompt, turns, monitor)
                If $ISOBJECT(final) Set response.Content = $EXTRACT(final.Content, 1, 20000)
                If submit.Result '= "" {
                    Set response.ResultJSON = submit.Result, response.Status = "ok"
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
        If $ISOBJECT(submit) && (submit.Result '= "") Set response.ResultJSON = submit.Result
    }
    Do ..FillStats(response, agent, session, monitor, trace)
    Set response.DurationMs = (($ZHOROLOG - start) * 1000) \ 1
    If (response.Mode = "record") && (response.Status = "ok") Do ..Record(spec, response, session)
    Quit $$$OK
}

/// Tokens, turns, tool calls, the model and the saved session.
Method FillStats(response As Interlock.Bridge.Msg.AgentResponse, agent, session, monitor, trace) [ Private ]
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
            }
        } Catch { }
        Try {
            Set sc = session.%Save()
            If $$$ISOK(sc) Set response.SessionId = session.%Id()
        } Catch { }
    }
    If $ISOBJECT(monitor) {
        Set response.Iterations = monitor.Iterations
        If +response.PromptTokens = 0 Set response.PromptTokens = monitor.PromptTokens
        If +response.CompletionTokens = 0 Set response.CompletionTokens = monitor.CompletionTokens
        Set response.CacheReadTokens = monitor.CacheReadTokens
        Set response.CacheCreationTokens = monitor.CacheCreationTokens
        If (+response.ToolCalls = 0) && (monitor.ToolCalls > 0) Set response.ToolCalls = monitor.ToolCalls
    }
    If $ISOBJECT(trace) && (+response.ToolCalls = 0) Set response.ToolCalls = trace.Calls
}

/// The member's knowledge collection, as search tools, when the library is present and built.
Method AttachKnowledge(agent, spec As Interlock.Bridge.RunSpec) [ Private ]
{
    If '##class(%Dictionary.CompiledClass).%ExistsId("Interlock.Knowledge.Library") Quit
    Set collection = "all"
    Set member = ##class(Interlock.Store.BoardMember).ByCode(spec.MemberCode)
    If $ISOBJECT(member) && (member.KnowledgeCollection '= "") Set collection = member.KnowledgeCollection
    Set n = $CLASSMETHOD("Interlock.Knowledge.Library", "Attach", agent, collection, .problems)
    If $GET(problems) '= "" $$$LOGWARNING("Knowledge for " _ spec.MemberCode _ ": " _ problems)
    $$$TRACE("Knowledge collections attached for " _ spec.MemberCode _ ": " _ n _ " (" _ collection _ ")")
}

/// Record mode: store the run, its transcript and its tool calls as a recording for replays.
Method Record(spec As Interlock.Bridge.RunSpec, response As Interlock.Bridge.Msg.AgentResponse, session) [ Private ]
{
    Try {
        Set transcript = ""
        If $ISOBJECT(session) Set transcript = session.Export()
        If $ISOBJECT(transcript) Set transcript = transcript.%ToJSON()
        Set toolCalls = ##class(Interlock.Bridge.ToolCall).ForRun(spec.EnsMessageId).%ToJSON()
        Set sc = ##class(Interlock.Bridge.Record).Store(spec, response, transcript, toolCalls, .record)
        If $$$ISOK(sc) && $ISOBJECT($GET(record)) Set response.RecordId = record.%Id()
        If $$$ISERR(sc) $$$LOGWARNING("The recording could not be stored: " _ $SYSTEM.Status.GetErrorText(sc))
    } Catch ex {
        $$$LOGWARNING("The recording could not be stored: " _ ex.DisplayString())
    }
}

/// The tools an agent class exposes, as the model sees them: the evidence tools plus the terminal
/// tool, with their JSON Schemas. Needs no provider. For checks over SQL.
ClassMethod DescribeTools(agentClass As %String = "Interlock.Agent.Conformance", terminal As %String = "SubmitFindings", collection As %String = "") As %String [ SqlProc ]
{
    Try {
        Set agent = $CLASSMETHOD(agentClass, "%New")
        Do agent.UseToolSet("Interlock.Tools.Evidence")
        Set submit = $CLASSMETHOD("Interlock.Tools." _ terminal, "%New")
        Do agent.ToolManager.AddTool(submit)
        Set problems = ""
        If collection '= "" Set n = ##class(Interlock.Knowledge.Library).Attach(agent, collection, .problems)
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
ClassMethod Probe(agentClass As %String = "Interlock.Agent.Conformance") As %String [ SqlProc ]
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
            While iter.%GetNext(.i, .t) { Do names.%Push(##class(Interlock.Util.Json).Str(t, "name")) }
        }
        Set out.tools = names
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out.%ToJSON()
}

/// Run one board member live for an existing case, outside the production: builds the request the
/// case workflow would build (the snapshot summary, and the specialists' findings for the coordinator),
/// runs this runner in <var>mode</var> (live or record) and returns the response as JSON. For checks
/// over SQL once a provider is configured; the tool calls are keyed "test:<case>:<member>".
ClassMethod TestRun(caseId As %String, memberCode As %String = "conformance", mode As %String = "live", tokenBudget As %Integer = 60000) As %String [ SqlProc ]
{
    Try {
        Set case = ##class(Interlock.Store.Case).ByCaseId(caseId)
        If '$ISOBJECT(case) Return {"error": ("Unknown case " _ caseId)}.%ToJSON()
        Set member = ##class(Interlock.Store.BoardMember).ByCode(memberCode)
        If '$ISOBJECT(member) Return {"error": ("Unknown board member " _ memberCode)}.%ToJSON()
        Set snap = case.CurrentSnapshot
        If '$ISOBJECT(snap) Return {"error": "The case has no evidence snapshot"}.%ToJSON()
        Set findings = ""
        If member.Role '= "specialist" Set findings = ##class(Interlock.Store.Finding).ForSnapshot(snap).%ToJSON()
        Set request = ##class(Interlock.Process.CaseWorkflow).BuildAgentRequest(case, member, snap.Summary, findings, 0)
        Set op = ##class(Interlock.Bridge.Operation.Agent).%New()
        Set spec = ##class(Interlock.Bridge.RunSpec).FromRequest(request, op)
        Set spec.Mode = mode, spec.TokenBudget = tokenBudget, spec.RecordKey = ""
        Set spec.EnsMessageId = "test:" _ caseId _ ":" _ memberCode, spec.EnsSessionId = ""
        Set response = ##class(Interlock.Bridge.Msg.AgentResponse).%New()
        Set runner = ..%New()
        Set sc = runner.Run(spec, .response)
        Do ##class(Interlock.Bridge.Runner).Stamp(spec, response)
        Set out = response.ToObject()
        If $$$ISERR(sc) Set out."run_error" = $SYSTEM.Status.GetErrorText(sc)
        Set out."tool_calls_detail" = ##class(Interlock.Bridge.ToolCall).ForRun(spec.EnsMessageId)
        Return out.%ToJSON()
    } Catch ex {
        Return {"error": (ex.DisplayString())}.%ToJSON()
    }
}

}
