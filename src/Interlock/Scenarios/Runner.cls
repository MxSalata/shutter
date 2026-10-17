/// Plays the demo scenarios (docs/CONTRACTS.md, section 4). <method>Run</method> resets the ward, sets the case
/// workflow's mode, then plays a scenario's steps: faults on the ward, HL7 files into the production's inbound
/// folder, waits, and for S7 a wait for the case's state. The production and the app do the rest.
/// <method>Start</method> does the same in a background job and returns at once, for the app. The methods are SQL
/// procedures, so scripts and the app can call them: <code>SELECT Interlock_Scenarios.Runner_Run('S2', 'board')</code>.
Class Interlock.Scenarios.Runner
{

/// Seconds a <code>wait_for_state</code> step waits when it gives no <code>timeout</code>.
Parameter WAITTIMEOUT = 120;

/// The folder that holds scenarios.json and one folder per scenario.
ClassMethod FixturesDir() As %String
{
    Quit ##class(%File).NormalizeDirectory($GET(^Interlock.Config("fixtures"), "/home/irisowner/dev/fixtures"))
}

/// The scenarios as scenarios.json lists them, with each file step's full path added. JSON text.
ClassMethod List() As %String [ SqlProc ]
{
    Set scenarios = ..Load(.error)
    If error '= "" {
        Quit {"error": (error)}.%ToJSON()
    }
    Quit scenarios.%ToJSON()
}

/// scenarios.json, parsed, with each file step's <code>path</code> filled in; <var>error</var> says what went wrong.
ClassMethod Load(Output error As %String) As %DynamicArray
{
    Set error = ""
    Set dir = ..FixturesDir()
    Set path = dir _ "scenarios.json"
    If '##class(%File).Exists(path) {
        Set error = "no scenarios.json in " _ dir
        Quit []
    }
    Set stream = ##class(%Stream.FileCharacter).%New()
    Set stream.TranslateTable = "UTF8"
    Do stream.LinkToFile(path)
    Try {
        Set scenarios = ##class(%DynamicAbstractObject).%FromJSON(stream)
    } Catch ex {
        Set error = "scenarios.json is not valid JSON: " _ ex.DisplayString()
        Set scenarios = []
    }
    Quit:error'="" scenarios
    Set iter = scenarios.%GetIterator()
    While iter.%GetNext(.i, .scenario) {
        Set steps = scenario.steps.%GetIterator()
        While steps.%GetNext(.j, .step) {
            Do:step.%IsDefined("file") step.%Set("path", dir _ scenario.id _ "/" _ step.file)
        }
    }
    Quit scenarios
}

/// Plays <var>scenario</var> (S1 to S10) and returns when its steps are done. <var>mode</var> is the investigation
/// mode, written to <code>^Interlock.Config("mode")</code>: board, single or rules. Whether agents run live or replay
/// is the agent items' production setting, not this. Returns JSON text.
ClassMethod Run(scenario As %String, mode As %String = "board") As %String [ SqlProc ]
{
    Set found = ..Prepare(scenario, mode, .inbound, .error)
    Quit:error'="" {"error": (error)}.%ToJSON()
    // Called over HTTP, a run that waits can outlast the web gateway's 60-second response timeout (S7 waits up to
    // three minutes): ask the gateway to wait for the whole run
    Set duration = ..Duration(found)
    Set:$ISOBJECT($GET(%response))&&(duration > 30) %response.Timeout = duration + 60
    Set started = ..Begin(scenario, mode, .error)
    Quit:error'="" {"error": (error)}.%ToJSON()
    Quit ..Play(found, scenario, mode, started, inbound, 0).%ToJSON()
}

/// Starts <var>scenario</var> and returns at once, for the app's 202 (CONTRACTS 5.2): the same checks and reset as
/// <method>Run</method>, then a background job plays the steps; <method>Status</method> follows it. When no job can
/// start, it plays the steps itself and answers when they are done (<code>"running": false</code>). Refused while
/// another run is playing. Returns JSON text.
ClassMethod Start(scenario As %String, mode As %String = "board") As %String [ SqlProc ]
{
    If ..Running() {
        Quit {"error": "scenario_running", "detail": ("a run of " _ {}.%FromJSON(^Interlock.Scenarios("run")).scenario _ " is still playing")}.%ToJSON()
    }
    Set found = ..Prepare(scenario, mode, .inbound, .error)
    Quit:error'="" {"error": (error)}.%ToJSON()
    Set started = ..Begin(scenario, mode, .error)
    Quit:error'="" {"error": (error)}.%ToJSON()
    Kill ^Interlock.Scenarios("run")
    Set ^Interlock.Scenarios("run") = {"scenario": (scenario), "mode": (mode), "startedAt": (started), "state": "running", "files": [], "timeouts": []}.%ToJSON()
    Job ##class(Interlock.Scenarios.Runner).Background(scenario, mode, started)::10
    If $TEST {
        Set ^Interlock.Scenarios("run", "job") = $ZCHILD
        Quit {"scenario": (scenario), "mode": (mode), "startedAt": (started), "files": [], "running": true}.%ToJSON()
    }
    // No process to spare (the Community licence caps them, and the production holds most): play the steps here,
    // in the caller's process, and answer when they are done. Called over HTTP, the gateway is asked to wait.
    Set duration = ..Duration(found)
    Set:$ISOBJECT($GET(%response))&&(duration > 30) %response.Timeout = duration + 60
    Set ^Interlock.Scenarios("run", "job") = $JOB
    Do ..Background(scenario, mode, started)
    Set run = {}.%FromJSON(^Interlock.Scenarios("run"))
    If run.state '= "done" {
        Quit {"error": (run.error), "files": (run.files)}.%ToJSON()
    }
    Quit {"scenario": (scenario), "mode": (mode), "startedAt": (started), "files": (run.files), "timeouts": (run.timeouts), "running": false}.%ToJSON()
}

/// The background run <method>Start</method> began, or the last one: scenario, mode, startedAt, state (running, done,
/// failed, or interrupted when its job is gone), files, timeouts, the step it is on while running, finishedAt and
/// error. JSON text, <code>null</code> when nothing has run.
ClassMethod Status() As %String [ SqlProc ]
{
    Set text = $GET(^Interlock.Scenarios("run"))
    Quit:text="" "null"
    Set run = {}.%FromJSON(text)
    If run.state = "running" {
        If ..Running() {
            Set run.step = $GET(^Interlock.Scenarios("run", "step"))
        } Else {
            Set run.state = "interrupted"
        }
    }
    Quit run.%ToJSON()
}

/// The job <method>Start</method> runs: plays the steps and records how it went.
ClassMethod Background(scenario As %String, mode As %String, started As %String)
{
    Try {
        Set found = ..Prepare(scenario, mode, .inbound, .error)
        Set result = $SELECT(error = "": ..Play(found, scenario, mode, started, inbound, 1), 1: {"error": (error), "files": []})
    } Catch ex {
        Set result = {"error": (ex.DisplayString()), "files": []}
    }
    Set run = {}.%FromJSON($GET(^Interlock.Scenarios("run"), "{}"))
    Set run.state = $SELECT(result.error '= "": "failed", 1: "done")
    Set run.files = result.files
    Set run.timeouts = $SELECT($ISOBJECT(result.timeouts): result.timeouts, 1: [])
    Set:result.error'="" run.error = result.error
    Set run.finishedAt = ##class(Wards.Service).Now()
    Set ^Interlock.Scenarios("run") = run.%ToJSON()
    Kill ^Interlock.Scenarios("run", "step")
}

/// Whether a background run is playing: its record says running and its job is alive.
ClassMethod Running() As %Boolean
{
    Set text = $GET(^Interlock.Scenarios("run"))
    Quit:text="" 0
    Set run = {}.%FromJSON(text)
    Quit:run.state'="running" 0
    Set job = $GET(^Interlock.Scenarios("run", "job"))
    Quit (job '= "") && ($DATA(^$JOB(job)) > 0)
}

/// The scenario's definition once the checks a run needs pass (the mode, the scenario, the inbound folder setting),
/// with the inbound folder in <var>inbound</var>; otherwise an empty string and the reason in <var>error</var>.
ClassMethod Prepare(scenario As %String, mode As %String, Output inbound As %String, Output error As %String) As %DynamicObject
{
    Set inbound = "", error = ""
    If '$LISTFIND($LISTBUILD("board", "single", "rules", "policy"), mode) {
        Set error = "unknown mode " _ mode _ ": use board, single or rules"
        Quit ""
    }
    Set scenarios = ..Load(.error)
    Quit:error'="" ""
    Set found = ""
    Set iter = scenarios.%GetIterator()
    While iter.%GetNext(.i, .candidate) {
        If candidate.id = scenario {
            Set found = candidate
            Quit
        }
    }
    If '$ISOBJECT(found) {
        Set error = "no scenario " _ scenario
        Quit ""
    }
    Set inbound = $GET(^Interlock.Config("adtIn"))
    If inbound = "" {
        Set error = "the adtIn setting (^Interlock.Config) is not set: run Interlock.Setup first"
        Quit ""
    }
    Set inbound = ##class(%File).NormalizeDirectory(inbound)
    Quit found
}

/// The reset before a run, and the mode and scenario recorded (CONTRACTS 4). Returns the time of the reset.
ClassMethod Begin(scenario As %String, mode As %String, Output error As %String) As %String
{
    Set error = ""
    Set reset = {}.%FromJSON(..Reset())
    If reset.ward.error '= "" {
        Set error = "the ward refused the reset: is the demo flag (^Wards.Config) set?"
        Quit ""
    }
    Set ^Interlock.Config("mode") = mode
    Set ^Interlock.Config("scenario") = scenario
    Quit reset."reset_at"
}

/// Plays the steps of <var>found</var> after <method>Begin</method>. With <var>track</var>, each step is recorded for
/// <method>Status</method> as it starts.
ClassMethod Play(found As %DynamicObject, scenario As %String, mode As %String, started As %String, inbound As %String, track As %Boolean = 0) As %DynamicObject
{
    Set files = [], timeouts = [], error = ""
    Set steps = found.steps.%GetIterator()
    While steps.%GetNext(.j, .step) {
        Set:track ^Interlock.Scenarios("run", "step") = ..Describe(step)
        If step.%IsDefined("fault") {
            Set request = {"mode": (step.fault)}
            Do:step.%IsDefined("operation_key") request.%Set("operation_key", step."operation_key")
            Set answer = ##class(Wards.Service).SetFault(request, .status)
            Set:status'=200 error = "the ward refused the fault step: " _ answer.%ToJSON()
            Quit:error'=""
        } ElseIf step.%IsDefined("file") {
            Set error = ..Drop(step.path, inbound)
            Quit:error'=""
            Do files.%Push(step.file)
            // At least two seconds between files, so the production applies them in order
            Hang 2
        } ElseIf step.%IsDefined("wait") {
            Hang +step.wait
        } ElseIf step.%IsDefined("wait_for_state") {
            Set timeout = $SELECT(step.%IsDefined("timeout"): +step.timeout, 1: ..#WAITTIMEOUT)
            Set reached = ..WaitForState(scenario, step."wait_for_state", timeout, .problem)
            Set:problem'="" error = "the runner could not read the case store: " _ problem
            Quit:error'=""
            Do:'reached timeouts.%Push(step."wait_for_state")
        } ElseIf step.%IsDefined("capabilities") {
            Set answer = ##class(Wards.Service).SetCapabilities(step.capabilities, .status)
            Set:status'=200 error = "the ward refused the capabilities step: " _ answer.%ToJSON()
            Quit:error'=""
        }
    }
    If error '= "" {
        Quit {"error": (error), "files": (files)}
    }
    Quit {"scenario": (scenario), "mode": (mode), "started_at": (started), "files": (files), "timeouts": (timeouts)}
}

/// A step in words, for <method>Status</method>.
ClassMethod Describe(step As %DynamicObject) As %String
{
    Quit:step.%IsDefined("file") "delivering " _ step.file
    Quit:step.%IsDefined("fault") "setting the ward's fault to " _ step.fault
    Quit:step.%IsDefined("wait") "waiting " _ step.wait _ " s"
    Quit:step.%IsDefined("wait_for_state") "waiting for the case to reach " _ step."wait_for_state"
    Quit:step.%IsDefined("capabilities") "changing the ward's capabilities"
    Quit "a step the runner doesn't know"
}

/// Waits until the newest case of <var>scenario</var> reaches <var>state</var> (CONTRACTS 4.1). Returns 1 when it
/// did, 0 when <var>timeout</var> seconds passed; <var>problem</var> says why the case store couldn't be read.
ClassMethod WaitForState(scenario As %String, state As %String, timeout As %Integer = {..#WAITTIMEOUT}, Output problem As %String) As %Boolean
{
    Set problem = ""
    Set deadline = $ZHOROLOG + timeout
    While $ZHOROLOG < deadline {
        // Without privilege checks: the caller may be the app's user, which has no SQL privileges on the store
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 State FROM Interlock_Store.""Case"" WHERE Scenario = ? ORDER BY ID DESC", scenario)
        If rs.%SQLCODE < 0 {
            Set problem = rs.%Message
            Return 0
        }
        If rs.%Next(), rs.%Get("State") = state {
            Return 1
        }
        Hang 1
    }
    Quit 0
}

/// The longest <var>scenario</var>'s steps can take, in seconds: two a file, its waits and each state's timeout.
ClassMethod Duration(scenario As %DynamicObject) As %Integer
{
    Set total = 0
    Set steps = scenario.steps.%GetIterator()
    While steps.%GetNext(.j, .step) {
        If step.%IsDefined("file") {
            Set total = total + 2
        } ElseIf step.%IsDefined("wait") {
            Set total = total + step.wait
        } ElseIf step.%IsDefined("wait_for_state") {
            Set total = total + $SELECT(step.%IsDefined("timeout"): +step.timeout, 1: ..#WAITTIMEOUT)
        }
    }
    Quit total
}

/// Copies a fixture into the inbound folder under a temporary name, then renames it, so the file service never reads
/// half a file. Returns an empty string, or what went wrong.
ClassMethod Drop(source As %String, inbound As %String) As %String
{
    Set target = inbound _ ##class(%File).GetFilename(source)
    Set partial = target _ ".part"
    If '##class(%File).CopyFile(source, partial, 1, .code) {
        Quit "could not copy " _ source _ " (" _ code _ ")"
    }
    If '##class(%File).Rename(partial, target, .code) {
        Quit "could not rename " _ partial _ " (" _ code _ ")"
    }
    Quit ""
}

/// The ward reset, the inbound and archive folders emptied of fixtures, the mode back to board, the running scenario
/// and any run record that isn't playing cleared, and <code>^Interlock.Config("resetAt")</code> set to the time of the
/// reset: the evidence collector ignores message-store events older than it, since encounter ids are fixed per
/// scenario. JSON text.
ClassMethod Reset() As %String [ SqlProc ]
{
    Set resetAt = ##class(Wards.Service).Now()
    Set ward = ##class(Wards.Service).Reset(.status)
    Set emptied = []
    For setting = "adtIn", "adtArchive" {
        Set dir = $GET(^Interlock.Config(setting))
        Continue:dir=""
        Set dir = ##class(%File).NormalizeDirectory(dir)
        Do emptied.%Push(dir)
        Set rs = ##class(%File).FileSetFunc(dir, "*.hl7;*.part", , 0)
        While rs.%Next() {
            Do:rs.%Get("Type")="F" ##class(%File).Delete(rs.%Get("Name"))
        }
    }
    Set ^Interlock.Config("mode") = "board"
    Kill ^Interlock.Config("scenario")
    Set ^Interlock.Config("resetAt") = resetAt
    // A run record left queued or finished goes with the reset (a queued run whose player stopped would otherwise
    // refuse every later run); one that is playing stays, since that run's own reset comes through here
    Kill:'..Running() ^Interlock.Scenarios("run")
    Quit {"ward": (ward), "emptied": (emptied), "mode": "board", "reset_at": (resetAt)}.%ToJSON()
}

}
