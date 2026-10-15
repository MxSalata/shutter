/// What an agent run produced, with everything an operator or a judge asks about it: the status,
/// the model, the tokens (cache tokens separately), the iterations, the tool calls, the time, and
/// where the full transcript is. Errors travel here, never as a failed message, so the workflow
/// decides what a failed run means.
Class Interlock.Bridge.Msg.AgentResponse Extends Ens.Response
{

/// ok, schema_failed, budget_exceeded, timeout, model_error, denied, loop_detected, no_record, error.
Property Status As %String(MAXLEN = 32);

Property AgentClass As %String(MAXLEN = 200);

Property ConfigVersion As %String(MAXLEN = 32);

/// live, record or replay.
Property Mode As %String(MAXLEN = 16);

Property Model As %String(MAXLEN = 100);

Property ProviderConfig As %String(MAXLEN = 100);

Property StartedAt As %String(MAXLEN = 30);

Property DurationMs As %Integer;

/// Prompt tokens excluding cache reads and writes.
Property PromptTokens As %Integer;

Property CompletionTokens As %Integer;

Property CacheReadTokens As %Integer;

Property CacheCreationTokens As %Integer;

/// Model turns in the run.
Property Iterations As %Integer;

/// Tool calls in the run; the calls themselves are Interlock.Bridge.ToolCall rows.
Property ToolCalls As %Integer;

/// The persisted agent session, when the runner kept one.
Property SessionId As %String(MAXLEN = 50);

/// The structured result the terminal tool received, validated, as JSON.
Property ResultJSON As %String(MAXLEN = "");

/// The agent's final text, if any.
Property Content As %String(MAXLEN = "");

Property Error As %String(MAXLEN = 2000);

/// The recording this response came from, or was stored as.
Property RecordId As %String(MAXLEN = 20);

/// The response as a dynamic object, for recordings and the API.
Method ToObject() As %DynamicObject
{
    Set o = {}
    Set o.status = ..Status, o."agent_class" = ..AgentClass, o."config_version" = ..ConfigVersion
    Set o.mode = ..Mode, o.model = ..Model, o."provider_config" = ..ProviderConfig
    Set o."started_at" = ..StartedAt, o."duration_ms" = +..DurationMs
    Set o."prompt_tokens" = +..PromptTokens, o."completion_tokens" = +..CompletionTokens
    Set o."cache_read_tokens" = +..CacheReadTokens, o."cache_creation_tokens" = +..CacheCreationTokens
    Set o.iterations = +..Iterations, o."tool_calls" = +..ToolCalls
    Set o."session_id" = ..SessionId
    If ..ResultJSON '= "" { Set o.result = ##class(%DynamicAbstractObject).%FromJSON(..ResultJSON) } Else { Do o.%Set("result", "", "null") }
    Set o.content = ..Content, o.error = ..Error, o."record_id" = ..RecordId
    Quit o
}

/// Fill the response from a dynamic object with the same field names.
Method FromObject(o As %DynamicObject) As %Status
{
    Set ..Status = ##class(Interlock.Util.Json).Str(o, "status")
    Set ..AgentClass = ##class(Interlock.Util.Json).Str(o, "agent_class")
    Set ..ConfigVersion = ##class(Interlock.Util.Json).Str(o, "config_version")
    Set ..Mode = ##class(Interlock.Util.Json).Str(o, "mode")
    Set ..Model = ##class(Interlock.Util.Json).Str(o, "model")
    Set ..ProviderConfig = ##class(Interlock.Util.Json).Str(o, "provider_config")
    Set ..StartedAt = ##class(Interlock.Util.Json).Str(o, "started_at")
    Set ..DurationMs = +##class(Interlock.Util.Json).Str(o, "duration_ms", 0)
    Set ..PromptTokens = +##class(Interlock.Util.Json).Str(o, "prompt_tokens", 0)
    Set ..CompletionTokens = +##class(Interlock.Util.Json).Str(o, "completion_tokens", 0)
    Set ..CacheReadTokens = +##class(Interlock.Util.Json).Str(o, "cache_read_tokens", 0)
    Set ..CacheCreationTokens = +##class(Interlock.Util.Json).Str(o, "cache_creation_tokens", 0)
    Set ..Iterations = +##class(Interlock.Util.Json).Str(o, "iterations", 0)
    Set ..ToolCalls = +##class(Interlock.Util.Json).Str(o, "tool_calls", 0)
    Set ..SessionId = ##class(Interlock.Util.Json).Str(o, "session_id")
    Set result = o.%Get("result")
    Set ..ResultJSON = $SELECT($ISOBJECT(result): result.%ToJSON(), 1: "")
    Set ..Content = ##class(Interlock.Util.Json).Str(o, "content")
    Set ..Error = ##class(Interlock.Util.Json).Str(o, "error")
    Set ..RecordId = ##class(Interlock.Util.Json).Str(o, "record_id")
    Quit $$$OK
}

Storage Default
{
<Data name="AgentResponseDefaultData">
<Subscript>"AgentResponse"</Subscript>
<Value name="1">
<Value>Status</Value>
</Value>
<Value name="2">
<Value>AgentClass</Value>
</Value>
<Value name="3">
<Value>ConfigVersion</Value>
</Value>
<Value name="4">
<Value>Mode</Value>
</Value>
<Value name="5">
<Value>Model</Value>
</Value>
<Value name="6">
<Value>ProviderConfig</Value>
</Value>
<Value name="7">
<Value>StartedAt</Value>
</Value>
<Value name="8">
<Value>DurationMs</Value>
</Value>
<Value name="9">
<Value>PromptTokens</Value>
</Value>
<Value name="10">
<Value>CompletionTokens</Value>
</Value>
<Value name="11">
<Value>CacheReadTokens</Value>
</Value>
<Value name="12">
<Value>CacheCreationTokens</Value>
</Value>
<Value name="13">
<Value>Iterations</Value>
</Value>
<Value name="14">
<Value>ToolCalls</Value>
</Value>
<Value name="15">
<Value>SessionId</Value>
</Value>
<Value name="16">
<Value>ResultJSON</Value>
</Value>
<Value name="17">
<Value>Content</Value>
</Value>
<Value name="18">
<Value>Error</Value>
</Value>
<Value name="19">
<Value>RecordId</Value>
</Value>
</Data>
<DefaultData>AgentResponseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
