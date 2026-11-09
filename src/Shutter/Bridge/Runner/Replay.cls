Include Ensemble

/// Replays a recorded run: no model call, no key needed. Serves judges without an API key,
/// continuous integration and a dependable demo. The response says Mode = replay so that nothing
/// downstream can mistake it for a live result.
Class Shutter.Bridge.Runner.Replay Extends Shutter.Bridge.Runner
{

Method Run(spec As Shutter.Bridge.RunSpec, ByRef response As Shutter.Bridge.Msg.AgentResponse) As %Status
{
    Set response.StartedAt = ##class(Shutter.Util.Time).NowUTC()
    If ##class(Shutter.Util.PageQuestion).IsPageRun(spec.AgentClass) {
        // A question about a page is never answered from a recording, whatever is stored under its key.
        Do ..Stamp(spec, response)
        Set response.Mode = "replay", response.Status = "no_model", response.DurationMs = 0
        Do ##class(Shutter.Util.PageQuestion).RunMode("replay", .detail)
        Set response.Error = detail
        Quit $$$OK
    }
    Set key = spec.ReplayKey()
    Set record = ##class(Shutter.Bridge.Record).Find(key)
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
        Set name = $CLASSMETHOD(json, "Str", c, "name"), ms = +$CLASSMETHOD(json, "Str", c, "durationMs", 0)
        Set ok = $CLASSMETHOD(json, "Bool", c, "ok", 1), denied = $CLASSMETHOD(json, "Bool", c, "denied", 0)
        Set sc = ##class(Shutter.Bridge.ToolCall).Append(runKey, name, $GET(args), ms, ok, $CLASSMETHOD(json, "Str", c, "resultPreview"), $CLASSMETHOD(json, "Str", c, "error"), denied, at)
        If $$$ISOK(sc) {
            Set n = n + 1
            // One line per call, as a live run's audit writes (Shutter.Bridge.Policy.Trace), so each call is its own step in
            // the Visual Trace; unlike a live line it carries no argument, result or error text, and a name that isn't a
            // plain tool name is left out.
            $$$TRACE("Tool " _ $SELECT($MATCH(name, "[A-Za-z_][A-Za-z0-9_.]{0,63}"): name, 1: "(not a tool name)") _ " " _ $SELECT(denied: "denied", ok: "ok", 1: "failed") _ ", " _ ms _ " ms (replay)")
        }
    }
    Quit n
}

}
