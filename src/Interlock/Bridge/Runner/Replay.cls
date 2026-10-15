/// Replays a recorded run: no model call, no key needed. Serves judges without an API key,
/// continuous integration and a dependable demo. The response says Mode = replay so that nothing
/// downstream can mistake it for a live result.
Class Interlock.Bridge.Runner.Replay Extends Interlock.Bridge.Runner
{

Method Run(spec As Interlock.Bridge.RunSpec, ByRef response As Interlock.Bridge.Msg.AgentResponse) As %Status
{
    Set key = spec.ReplayKey()
    Set record = ##class(Interlock.Bridge.Record).Find(key)
    Set response.StartedAt = ##class(Interlock.Util.Time).NowUTC()
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
    Set response.StartedAt = ##class(Interlock.Util.Time).NowUTC()
    Quit sc
}

}
