/// Replays a recorded run: no model call, no key needed. Serves judges without an API key,
/// continuous integration and a dependable demo. The response says Mode = replay so that nothing
/// downstream can mistake it for a live result.
Class Shutter.Bridge.Runner.Replay Extends Shutter.Bridge.Runner
{

Method Run(spec As Shutter.Bridge.RunSpec, ByRef response As Shutter.Bridge.Msg.AgentResponse) As %Status
{
    Set key = spec.ReplayKey()
    Set record = ##class(Shutter.Bridge.Record).Find(key)
    Set response.StartedAt = ##class(Shutter.Util.Time).NowUTC()
    If '$ISOBJECT(record) {
        Do ..Stamp(spec, response)
        Set response.Mode = "replay"
        Set response.Status = "no_record"
        Set response.Error = "No recording for " _ key
        Set response.DurationMs = 0
        Quit $$$OK
    }
    Set sc = record.ApplyTo(response)
    Do ..Stamp(spec, response)
    Set response.Mode = "replay"
    Set response.RecordId = record.%Id()
    // The recording's pace (v1.35): the run starts now, and its recorded tool calls are written for this run with their
    // times moved by the same amount, so the timeline a replay draws is the live run's; a recording with no start keeps
    // the calls at now.
    Set nowMs = ##class(Shutter.Util.Time).NowUTCms()
    Set recordedStart = $SELECT(response.StartedAtMs '= "": response.StartedAtMs, 1: response.StartedAt)
    Set shift = $SELECT(recordedStart '= "": ##class(Shutter.Util.Time).MillisBetween(recordedStart, nowMs), 1: "")
    Set response.StartedAt = ##class(Shutter.Util.Time).NowUTC(), response.StartedAtMs = nowMs
    If spec.EnsMessageId '= "" Do ..ReplayToolCalls(spec.EnsMessageId, record.ToolCallsJSON, shift)
    Quit sc
}

/// The recorded tool calls as this run's rows (Shutter.Bridge.ToolCall), each at its recorded time moved by shift
/// milliseconds ("" leaves them at now), once: a run that has rows already is left alone. Returns how many were written.
ClassMethod ReplayToolCalls(runKey As %String, toolCallsJSON As %String, shift As %String = "") As %Integer
{
    Set n = 0
    If (runKey = "") || ($ZSTRIP(toolCallsJSON, "<>W") = "") Quit 0
    If ##class(Shutter.Bridge.ToolCall).HasRows(runKey) Quit 0
    Set calls = ##class(Shutter.Util.Json).Parse(toolCallsJSON, .psc)
    If '$ISOBJECT(calls) || 'calls.%IsA("%DynamicArray") Quit 0
    Set json = "Shutter.Util.Json", it = calls.%GetIterator()
    While it.%GetNext(, .c) {
        Continue:'$ISOBJECT(c)
        Set at = $CLASSMETHOD(json, "Str", c, "at")
        If (at '= "") && (shift '= "") Set at = ##class(Shutter.Util.Time).PlusMillis(at, shift)
        Set args = c.%Get("arguments")
        If $ISOBJECT(args) Set args = args.%ToJSON()
        Set sc = ##class(Shutter.Bridge.ToolCall).Append(runKey, $CLASSMETHOD(json, "Str", c, "name"), $GET(args), +$CLASSMETHOD(json, "Str", c, "durationMs", 0), $CLASSMETHOD(json, "Bool", c, "ok", 1), $CLASSMETHOD(json, "Str", c, "resultPreview"), $CLASSMETHOD(json, "Str", c, "error"), $CLASSMETHOD(json, "Bool", c, "denied", 0), at)
        If $$$ISOK(sc) Set n = n + 1
    }
    Quit n
}

}
