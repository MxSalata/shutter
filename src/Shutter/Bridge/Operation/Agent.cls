/// An AI Hub agent as a business operation. Each request is one agent run; the response carries
/// the structured result, the status, the tokens and the time, so the Visual Trace of a production
/// shows what the agent did, what it cost and how long it took. The operation itself does not
/// depend on AI Hub: a runner class does the work, and the replay runner needs no model at all.
///
/// Settings: AgentClass (the declarative agent to run unless the request names one), Runner (the
/// class that runs live and record modes), Mode (live, record or replay), ProviderConfig and Model
/// (overrides of the agent class's parameters), MaxIterations, TokenBudget, RequestTimeoutSeconds (the whole run's
/// deadline, as seconds per turn times the turn limit, checked by the monitor between model calls: AI Hub's
/// agent loop offers no timeout on a single request, so one slow request can run past it).
/// Configure one item per board member for separate lanes in the trace, or one shared item with a
/// larger pool.
Class Shutter.Bridge.Operation.Agent Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

/// The declarative agent class to run, unless the request names one.
Property AgentClass As %String(MAXLEN = 200);

/// The runner for live and record modes (the aihub module's Shutter.Bridge.Runner.AIHub).
Property Runner As %String(MAXLEN = 200) [ InitialExpression = "Shutter.Bridge.Runner.AIHub" ];

/// replay answers from recordings and needs no model; record runs live and stores the recording; auto
/// (the default) is what the instance says: SHUTTER_AGENT_MODE when set, else live when a provider is
/// configured and the live runner is installed, else replay; live while the API mimic (tests/mock) is on.
Property Mode As %String(MAXLEN = 16, VALUELIST = ",auto,live,record,replay") [ InitialExpression = "auto" ];

/// A Config Store configuration name (AI.LLM.<name>) that overrides the agent class's provider, and its model
/// unless Model is set.
Property ProviderConfig As %String(MAXLEN = 100);

/// A model id that overrides the agent class's model.
Property Model As %String(MAXLEN = 100);

/// Model turns allowed per run.
Property MaxIterations As %Integer [ InitialExpression = 8 ];

/// Tokens (prompt plus completion, cumulative over the run) after which the run is stopped.
Property TokenBudget As %Integer [ InitialExpression = 120000 ];

/// Seconds per turn for the run's deadline: the monitor stops the run after this many seconds times the turn limit,
/// checked between model calls. AI Hub's agent loop has no timeout on a single request.
Property RequestTimeoutSeconds As %Integer [ InitialExpression = 120 ];

Parameter SETTINGS = "AgentClass:Agent,Runner:Agent,Mode:Agent,ProviderConfig:Agent,Model:Agent,MaxIterations:Agent,TokenBudget:Agent,RequestTimeoutSeconds:Agent";

/// The mode a setting means: itself, or for auto what the instance says (^Shutter.Config("aihub","mode")
/// from SHUTTER_AGENT_MODE), else live when a provider is configured and the live runner exists, else replay.
/// While the API mimic is on (<var>mock</var>, Shutter.Setup MockConfig unless the caller read it), auto means live:
/// the live runner sends the run to the mimic, and switching the mimic off brings back what the instance says. The
/// mimic counts on a demo instance only (^Shutter.Config("demo")): a site ignores a stray switch, as MockConfig does.
/// At the item's start (v1.35): one event-log line saying what this item will do, so an operator sees the effective mode
/// (auto resolved to live or replay), the runner, the provider configuration and the mimic's switch without a run; and a
/// warning when live is asked for with no provider configured, since every live run would then fail.
Method OnInit() As %Status
{
    Try {
        Set mock = ##class(Shutter.Setup).MockConfig()
        Set mode = ..ResolveMode(..Mode, mock)
        Set runnerThere = (..Runner = "") || ##class(%Dictionary.CompiledClass).%ExistsId(..Runner)
        // A key typed into ProviderConfig or Model reads "hidden" here, as everywhere else (Shutter.Util.Secret).
        Set provider = $SELECT(mock '= "": "the API mimic (" _ mock _ ")", ..ProviderConfig '= "": ##class(Shutter.Util.Secret).Clean(..ProviderConfig), ##class(Shutter.Setup).ProviderConfigured(): ##class(Shutter.Util.Secret).Clean($GET(^Shutter.Config("aihub", "provider"))), 1: "none configured")
        $$$LOGINFO(..%ConfigName _ " starts in " _ mode _ " mode" _ $SELECT($ZCONVERT(..Mode, "L") = "auto": " (auto)", 1: "") _ "; runner " _ ..Runner _ $SELECT(runnerThere: "", 1: " (not installed)") _ "; provider " _ provider _ "; model " _ $SELECT(..Model '= "": ##class(Shutter.Util.Secret).CleanModel(..Model), 1: "the configuration's") _ "; one call bounded at " _ ##class(Shutter.Setup).ProviderTimeoutSeconds() _ " s")
        If (mode = "live") && (mock = "") && (..ProviderConfig = "") && '##class(Shutter.Setup).ProviderConfigured() $$$LOGWARNING(..%ConfigName _ ": live mode with no provider configured; every live run will fail until ANTHROPIC_API_KEY or a provider configuration is set (SELECT Shutter.Setup_ConfigureProvider)")
        If (mode '= "replay") && 'runnerThere $$$LOGWARNING(..%ConfigName _ ": the runner " _ ..Runner _ " is not installed (the aihub module); live and record runs will fail, replay still works")
    } Catch ex {
        $$$LOGWARNING(..%ConfigName _ ": the start-up note failed: " _ ex.DisplayString())
    }
    Quit $$$OK
}

ClassMethod ResolveMode(mode As %String, mock As %String = {##class(Shutter.Setup).MockConfig()}) As %String
{
    Set mode = $ZCONVERT(mode, "L")
    If (mode '= "") && (mode '= "auto") Quit mode
    If (mock '= "") && $GET(^Shutter.Config("demo")) && ##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Bridge.Runner.AIHub") Quit "live"
    Set m = $ZCONVERT($GET(^Shutter.Config("aihub", "mode")), "L")
    If $LISTFIND($LISTBUILD("live", "record", "replay"), m) Quit m
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Bridge.Runner.AIHub") Quit "replay"
    Quit $SELECT(##class(Shutter.Setup).ProviderConfigured(): "live", 1: "replay")
}

Method OnAgentRequest(request As Shutter.Bridge.Msg.AgentRequest, Output response As Shutter.Bridge.Msg.AgentResponse) As %Status
{
    Set response = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set spec = ##class(Shutter.Bridge.RunSpec).FromRequest(request, $THIS)
    // A key typed into the item's ProviderConfig or Model: "hidden" in the spec, so no runner, line or row gets it.
    Set keyed = ##class(Shutter.Util.Secret).MaskSpec(spec)
    Set spec.EnsMessageId = ..%RequestHeader.%Id()
    Set spec.EnsSessionId = ..%SessionId
    Set runnerClass = $SELECT(spec.Mode = "replay": "Shutter.Bridge.Runner.Replay", 1: spec.RunnerClass)
    $$$TRACE("Agent run: " _ spec.AgentClass _ " (" _ spec.MemberCode _ ") in " _ spec.Mode _ " mode for " _ spec.CorrelationKey _ " via " _ runnerClass)
    Set start = $ZHOROLOG
    // The day's model budget (Shutter.Util.Budget, v1.34): a run that would call a model is refused once the day's spend
    // has reached the cap; a replay calls no model and is never refused.
    Set response.RequestedBy = request.RequestedBy
    // The provider refusing the key (Shutter.Util.LiveAgents, v1.37): while a live run failed with an authentication error
    // in the last fifteen minutes, a run that would call a model is refused here with no call, as the budget refuses one.
    // A run that would call a model with such a setting is refused before anything is looked up with it.
    If (spec.Mode '= "replay") && (keyed '= "") {
        Set response.Status = "error"
        Set response.Error = ##class(Shutter.Util.Secret).Refusal(keyed)
    } ElseIf (spec.Mode '= "replay") && ##class(Shutter.Util.LiveAgents).ProviderDown(.downUntil, .downText) {
        Set response.Status = "provider_auth"
        Set response.Error = downText
    } ElseIf (spec.Mode '= "replay") && '##class(Shutter.Util.Budget).AllowsFor(request.RequestedBy, .budget) {
        Set response.Status = "budget_exhausted"
        Set response.Error = ##class(Shutter.Util.Budget).Refusal(budget)
    } ElseIf (runnerClass = "") || '##class(%Dictionary.CompiledClass).%ExistsId(runnerClass) {
        Set response.Status = "error"
        Set response.Error = "Runner class not available: " _ runnerClass _ ". Install the aihub module for live runs, or set the Mode to replay."
    } Else {
        // Reserve, then settle (Shutter.Util.Budget, v1.35): the run counts against the cap while it is in flight.
        Set reserveKey = ""
        If spec.Mode '= "replay" {
            Set reserveKey = spec.CorrelationKey _ "|" _ spec.MemberCode _ "|" _ $JOB _ "|" _ $ZHOROLOG
            Set reserved = ##class(Shutter.Util.Budget).Reserve(reserveKey, request.RequestedBy)
            $$$TRACE("Reserved " _ ##class(Shutter.Util.Budget).Dollars(reserved) _ " of the day's budget for this run")
        }
        Try {
            Set runner = $CLASSMETHOD(runnerClass, "%New")
            Set sc = runner.Run(spec, .response)
            If $$$ISERR(sc) {
                Set response.Status = "error"
                Set response.Error = $SYSTEM.Status.GetErrorText(sc)
            }
        } Catch ex {
            Set response.Status = "error"
            Set response.Error = ex.DisplayString()
        }
        If reserveKey '= "" Do ##class(Shutter.Util.Budget).Settle(reserveKey)
    }
    Do ##class(Shutter.Util.Secret).MaskResponse(response, $LISTBUILD(..ProviderConfig), ..Model)
    Do ##class(Shutter.Util.LiveAgents).NoteRun(spec.Mode, response.Status, response.Error)
    Do ##class(Shutter.Bridge.Runner).Stamp(spec, response)
    If response.Mode = "" Set response.Mode = spec.Mode
    If response.StartedAt = "" Set response.StartedAt = ##class(Shutter.Util.Time).NowUTC()
    If response.StartedAtMs = "" Set response.StartedAtMs = ##class(Shutter.Util.Time).NowUTCms()
    If response.DurationMs = "" Set response.DurationMs = (($ZHOROLOG - start) * 1000) \ 1
    If response.Status = "" Set response.Status = "ok"
    $$$TRACE("Agent run done: " _ response.Status _ ", model " _ response.Model _ ", tokens " _ (+response.PromptTokens) _ " in / " _ (+response.CompletionTokens) _ " out (cache read " _ (+response.CacheReadTokens) _ "), " _ (+response.Iterations) _ " turns, " _ (+response.ToolCalls) _ " tool calls, " _ (+response.DurationMs) _ " ms")
    If response.Error '= "" $$$LOGWARNING("Agent run " _ response.Status _ ": " _ response.Error)
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Bridge.Msg.AgentRequest">
    <Method>OnAgentRequest</Method>
  </MapItem>
</MapItems>
}

}
