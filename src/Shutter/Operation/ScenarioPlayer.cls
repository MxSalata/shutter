/// Plays a demo scenario inside the production: the same checks, reset and steps as
/// Shutter.Scenarios.Runner.Start, in this item's own job instead of a new process (the Community
/// licence caps those), and visible in the trace with the cases it causes. One run at a time
/// (PoolSize 1); a run that reaches the queue while another plays waits its turn, and the API refuses
/// a second run while one is queued or playing.
Class Shutter.Operation.ScenarioPlayer Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnRun(request As Shutter.Msg.ScenarioRun, Output response As Shutter.Msg.ScenarioRunResult) As %Status
{
    Set response = ##class(Shutter.Msg.ScenarioRunResult).%New()
    Set response.Scenario = request.Scenario, response.Mode = request.Mode
    Set runner = "Shutter.Scenarios.Runner"
    If '##class(%Dictionary.CompiledClass).%ExistsId(runner) {
        Set response.State = "refused", response.Error = "The scenario runner is not installed"
        Quit $$$OK
    }
    If $CLASSMETHOD(runner, "Running") {
        Set response.State = "refused", response.Error = "Another run is still playing"
        $$$LOGWARNING("Scenario " _ request.Scenario _ " refused: another run is still playing")
        Quit $$$OK
    }
    Set error = ""
    Set found = $CLASSMETHOD(runner, "Prepare", request.Scenario, request.Mode, .inbound, .error)
    // Whether who asked may run the agents live travels with the run (1.4.4): this job runs as the production, which may.
    If error = "" Set started = $CLASSMETHOD(runner, "Begin", request.Scenario, request.Mode, .error, request.RequestedBy, ''request.LiveAllowed)
    If error '= "" {
        Set response.State = "refused", response.Error = error
        Set run = {"scenario": (request.Scenario), "mode": (request.Mode), "state": "failed", "error": (error), "files": [], "timeouts": []}
        Set ^Shutter.Scenarios("run") = run.%ToJSON()
        Kill ^Shutter.Scenarios("run", "job")
        Set response.RunJSON = run.%ToJSON()
        $$$LOGWARNING("Scenario " _ request.Scenario _ " refused: " _ error)
        Quit $$$OK
    }
    Set run = {"scenario": (request.Scenario), "mode": (request.Mode), "startedAt": (started), "state": "running", "files": [], "timeouts": [], "player": (..%ConfigName)}
    Do run.%Set("replay", 'request.LiveAllowed, "boolean")
    Set ^Shutter.Scenarios("run") = run.%ToJSON()
    Set ^Shutter.Scenarios("run", "job") = $JOB
    $$$TRACE("Playing scenario " _ request.Scenario _ " (" _ request.Mode _ ") from " _ started)
    // Plays the steps and records how it went (state done or failed, files, timeouts, finishedAt, error).
    Do $CLASSMETHOD(runner, "Background", request.Scenario, request.Mode, started)
    Set run = {}.%FromJSON($GET(^Shutter.Scenarios("run"), "{}"))
    Set response.State = ##class(Shutter.Util.Json).Str(run, "state")
    Set response.StartedAt = started
    Set response.FinishedAt = ##class(Shutter.Util.Json).Str(run, "finishedAt")
    Set response.Error = ##class(Shutter.Util.Json).Str(run, "error")
    Set response.RunJSON = run.%ToJSON()
    If response.State = "failed" $$$LOGWARNING("Scenario " _ request.Scenario _ " failed: " _ response.Error)
    $$$TRACE("Scenario " _ request.Scenario _ " " _ response.State _ $SELECT(response.FinishedAt '= "": " at " _ response.FinishedAt, 1: ""))
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.ScenarioRun">
    <Method>OnRun</Method>
  </MapItem>
</MapItems>
}

}
