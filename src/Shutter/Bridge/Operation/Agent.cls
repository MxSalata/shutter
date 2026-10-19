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
/// configured and the live runner is installed, else replay.
Property Mode As %String(MAXLEN = 16, VALUELIST = ",auto,live,record,replay") [ InitialExpression = "auto" ];

/// A Config Store configuration name (AI.LLM.<name>) that overrides the agent class's provider.
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
ClassMethod ResolveMode(mode As %String) As %String
{
    Set mode = $ZCONVERT(mode, "L")
    If (mode '= "") && (mode '= "auto") Quit mode
    Set m = $ZCONVERT($GET(^Shutter.Config("aihub", "mode")), "L")
    If $LISTFIND($LISTBUILD("live", "record", "replay"), m) Quit m
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Bridge.Runner.AIHub") Quit "replay"
    Quit $SELECT(##class(Shutter.Setup).ProviderConfigured(): "live", 1: "replay")
}

Method OnAgentRequest(request As Shutter.Bridge.Msg.AgentRequest, Output response As Shutter.Bridge.Msg.AgentResponse) As %Status
{
    Set response = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set spec = ##class(Shutter.Bridge.RunSpec).FromRequest(request, $THIS)
    Set spec.EnsMessageId = ..%RequestHeader.%Id()
    Set spec.EnsSessionId = ..%SessionId
    Set runnerClass = $SELECT(spec.Mode = "replay": "Shutter.Bridge.Runner.Replay", 1: spec.RunnerClass)
    $$$TRACE("Agent run: " _ spec.AgentClass _ " (" _ spec.MemberCode _ ") in " _ spec.Mode _ " mode for " _ spec.CorrelationKey _ " via " _ runnerClass)
    Set start = $ZHOROLOG
    If (runnerClass = "") || '##class(%Dictionary.CompiledClass).%ExistsId(runnerClass) {
        Set response.Status = "error"
        Set response.Error = "Runner class not available: " _ runnerClass _ ". Install the aihub module for live runs, or set the Mode to replay."
    } Else {
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
    }
    Do ##class(Shutter.Bridge.Runner).Stamp(spec, response)
    If response.Mode = "" Set response.Mode = spec.Mode
    If response.StartedAt = "" Set response.StartedAt = ##class(Shutter.Util.Time).NowUTC()
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
