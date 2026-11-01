/// One run of a board member (an agent) on a snapshot, as the bridge reported it: status, model,
/// tokens, cost, time, and where the full transcript and the tool calls are.
Class Shutter.Store.AgentRun Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Snapshot As Shutter.Store.Snapshot(%JSONFIELDNAME = "snapshotId", %JSONREFERENCE = "ID");

/// specialist, coordinator or generalist.
Property Role As %String(%JSONFIELDNAME = "role", MAXLEN = 32);

/// The library member that ran, for example conformance.
Property MemberCode As %String(%JSONFIELDNAME = "memberCode", MAXLEN = 32);

Property AgentClass As %String(%JSONFIELDNAME = "agentClass", MAXLEN = 200);

Property ConfigVersion As %String(%JSONFIELDNAME = "configVersion", MAXLEN = 32);

/// live, record, replay or rules.
Property Mode As %String(%JSONFIELDNAME = "mode", MAXLEN = 16);

Property Model As %String(%JSONFIELDNAME = "model", MAXLEN = 100);

Property ProviderConfig As %String(%JSONFIELDNAME = "providerConfig", MAXLEN = 100);

/// ok, schema_failed, budget_exceeded, timeout, model_error, denied, loop_detected, no_record, refused, error.
Property Status As %String(%JSONFIELDNAME = "status", MAXLEN = 32);

Property StartedAt As %String(%JSONFIELDNAME = "startedAt", MAXLEN = 30);

Property DurationMs As %Integer(%JSONFIELDNAME = "durationMs");

Property PromptTokens As %Integer(%JSONFIELDNAME = "promptTokens");

Property CompletionTokens As %Integer(%JSONFIELDNAME = "completionTokens");

Property CacheReadTokens As %Integer(%JSONFIELDNAME = "cacheReadTokens");

Property CacheCreationTokens As %Integer(%JSONFIELDNAME = "cacheCreationTokens");

Property Iterations As %Integer(%JSONFIELDNAME = "iterations");

Property ToolCallCount As %Integer(%JSONFIELDNAME = "toolCallCount");

/// The persisted conversation (the agent session id in the aihub module), when there is one.
Property SessionId As %String(%JSONFIELDNAME = "sessionId", MAXLEN = 50);

/// The production message that carried the request: the Visual Trace link for this run.
Property EnsMessageId As %String(%JSONFIELDNAME = "ensMessageId", MAXLEN = 20);

/// The structured result the agent submitted (findings or a plan), as JSON.
Property ResultJSON As %String(%JSONFIELDNAME = "result", MAXLEN = "");

/// The agent's final text, if any.
Property Content As %String(%JSONFIELDNAME = "content", MAXLEN = "");

Property Error As %String(%JSONFIELDNAME = "error", MAXLEN = 2000);

/// Estimated cost in US dollars from Shutter.Store.ModelPrice.
Property CostUSD As %Numeric(%JSONFIELDNAME = "costUsd", SCALE = 6);

/// The question this run answered (Shutter.Store.CaseQuestion, CONTRACTS 14.2), or empty for an investigation's run.
Property QuestionId As %String(%JSONFIELDNAME = "questionId", MAXLEN = 32);

/// Who asked for the run (v1.34): a question's asker, a judge who convened the board; "system" for the feed's own.
Property RequestedBy As %String(%JSONFIELDNAME = "requestedBy", MAXLEN = 100);

Index QuestionIdx On QuestionId;

/// Record a run from the bridge's response. A run that answered a question names it (questionId).
ClassMethod FromResponse(case As Shutter.Store.Case, snapshot As Shutter.Store.Snapshot, role As %String, memberCode As %String, response As Shutter.Bridge.Msg.AgentResponse, ensMessageId As %String, Output run As Shutter.Store.AgentRun, questionId As %String = "") As %Status
{
    Set run = ..%New()
    Set run.QuestionId = questionId
    // By id, not the caller's copy, as Snapshot.Begin does: a save of the run never writes the case whole.
    Do run.CaseSetObjectId(case.%Id())
    Set run.Snapshot = snapshot, run.Role = role, run.MemberCode = memberCode
    Set run.AgentClass = response.AgentClass, run.ConfigVersion = response.ConfigVersion
    Set run.Mode = response.Mode, run.Model = response.Model, run.ProviderConfig = response.ProviderConfig
    Set run.Status = response.Status, run.StartedAt = response.StartedAt, run.DurationMs = response.DurationMs
    Set run.PromptTokens = response.PromptTokens, run.CompletionTokens = response.CompletionTokens
    Set run.CacheReadTokens = response.CacheReadTokens, run.CacheCreationTokens = response.CacheCreationTokens
    Set run.Iterations = response.Iterations, run.ToolCallCount = response.ToolCalls
    Set run.SessionId = response.SessionId, run.EnsMessageId = ensMessageId
    Set run.RequestedBy = response.RequestedBy
    // The run is read by people inside IRIS: the case's tokens become the identifiers again (T27).
    Set run.ResultJSON = ##class(Shutter.Util.ModelView).Restore(case, response.ResultJSON)
    Set run.Content = ##class(Shutter.Util.ModelView).Restore(case, response.Content)
    Set run.Error = ##class(Shutter.Util.ModelView).Restore(case, response.Error)
    // A replayed run spends nothing: its tokens are the recording's, kept for the record, and cost 0. Nor does a run
    // the API mimic answered (model mock): its tokens are estimates and no model was called.
    Set run.CostUSD = $SELECT(response.Mode = "replay": 0, response.Model = "mock": 0, 1: ##class(Shutter.Store.ModelPrice).Cost(response.Model, response.PromptTokens, response.CompletionTokens, response.CacheReadTokens, response.CacheCreationTokens))
    Quit run.%Save()
}

Storage Default
{
<Data name="AgentRunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>Snapshot</Value>
</Value>
<Value name="4">
<Value>Role</Value>
</Value>
<Value name="5">
<Value>MemberCode</Value>
</Value>
<Value name="6">
<Value>AgentClass</Value>
</Value>
<Value name="7">
<Value>ConfigVersion</Value>
</Value>
<Value name="8">
<Value>Mode</Value>
</Value>
<Value name="9">
<Value>Model</Value>
</Value>
<Value name="10">
<Value>ProviderConfig</Value>
</Value>
<Value name="11">
<Value>Status</Value>
</Value>
<Value name="12">
<Value>StartedAt</Value>
</Value>
<Value name="13">
<Value>DurationMs</Value>
</Value>
<Value name="14">
<Value>PromptTokens</Value>
</Value>
<Value name="15">
<Value>CompletionTokens</Value>
</Value>
<Value name="16">
<Value>CacheReadTokens</Value>
</Value>
<Value name="17">
<Value>CacheCreationTokens</Value>
</Value>
<Value name="18">
<Value>Iterations</Value>
</Value>
<Value name="19">
<Value>ToolCallCount</Value>
</Value>
<Value name="20">
<Value>SessionId</Value>
</Value>
<Value name="21">
<Value>EnsMessageId</Value>
</Value>
<Value name="22">
<Value>ResultJSON</Value>
</Value>
<Value name="23">
<Value>Content</Value>
</Value>
<Value name="24">
<Value>Error</Value>
</Value>
<Value name="25">
<Value>CostUSD</Value>
</Value>
<Value name="26">
<Value>QuestionId</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.AgentRunD</DataLocation>
<DefaultData>AgentRunDefaultData</DefaultData>
<IdLocation>^Shutter.Store.AgentRunD</IdLocation>
<IndexLocation>^Shutter.Store.AgentRunI</IndexLocation>
<StreamLocation>^Shutter.Store.AgentRunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
