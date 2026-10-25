Include Ensemble

/// Writes one Shutter.Bridge.ToolCall row per tool call, keyed by the production message that
/// carries the run, and a trace line, so the Visual Trace's log shows what the agent asked for.
Class Shutter.Bridge.Policy.Trace Extends %AI.Policy.Audit
{

/// The Ens.MessageHeader id of the agent request, or a test run's own key (test:<case>:<member>:<n>, the runner's
/// TestRun).
Property RunKey As %String(MAXLEN = 80);

Property Calls As %Integer [ InitialExpression = 0 ];

Method %LogExecution(call As %DynamicObject, metadata As %DynamicObject, result As %DynamicObject, duration As %Integer, status As %Status) As %Status
{
    Try {
        Set name = ##class(Shutter.Bridge.Policy.Scope).ToolName(call)
        Set args = $SELECT($ISOBJECT(call): call.%Get("arguments"), 1: "")
        If $ISOBJECT(args) Set args = args.%ToJSON()
        Set text = $SELECT($ISOBJECT(result): result.%ToJSON(), 1: $GET(result))
        Set ok = $$$ISOK(status)
        Set error = $SELECT(ok: "", 1: $SYSTEM.Status.GetErrorText(status))
        Set ..Calls = ..Calls + 1
        Do ##class(Shutter.Bridge.ToolCall).Append(..RunKey, name, $EXTRACT(args, 1, 30000), +duration, ok, $EXTRACT(text, 1, 500), error)
        $$$TRACE("Tool " _ name _ "(" _ ##class(Shutter.Util.Json).Preview(args, 120) _ ") " _ $SELECT(ok: "ok", 1: "failed: " _ error) _ ", " _ (+duration) _ " ms, " _ $LENGTH(text) _ " chars")
    } Catch ex {
        $$$LOGWARNING("The tool-call audit failed: " _ ex.DisplayString())
    }
    Return $$$OK
}

}
