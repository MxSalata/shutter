/// Plays the demo scenarios (docs/CONTRACTS.md, section 4). <method>Run</method> resets the ward, sets the case
/// workflow's mode, then plays a scenario's steps: faults on the ward, HL7 files into the production's inbound
/// folder, waits. It doesn't wait for the case; the production and the app do the rest. The methods are SQL
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

/// Plays <var>scenario</var> (S1 to S10). <var>mode</var> is the investigation mode, written to
/// <code>^Interlock.Config("mode")</code>: board, single or rules. Whether agents run live or replay is the agent
/// items' production setting, not this. Returns JSON text.
ClassMethod Run(scenario As %String, mode As %String = "board") As %String [ SqlProc ]
{
    If '$LISTFIND($LISTBUILD("board", "single", "rules"), mode) {
        Quit {"error": ("unknown mode " _ mode _ ": use board, single or rules")}.%ToJSON()
    }
    Set scenarios = ..Load(.error)
    If error '= "" {
        Quit {"error": (error)}.%ToJSON()
    }
    Set found = ""
    Set iter = scenarios.%GetIterator()
    While iter.%GetNext(.i, .candidate) {
        If candidate.id = scenario {
            Set found = candidate
            Quit
        }
    }
    If '$ISOBJECT(found) {
        Quit {"error": ("no scenario " _ scenario)}.%ToJSON()
    }
    Set inbound = $GET(^Interlock.Config("adtIn"))
    If inbound = "" {
        Quit {"error": "the adtIn setting (^Interlock.Config) is not set: run Interlock.Setup first"}.%ToJSON()
    }
    Set inbound = ##class(%File).NormalizeDirectory(inbound)
    // Called over HTTP, a run that waits can outlast the web gateway's 60-second response timeout (S7 waits up to
    // three minutes): ask the gateway to wait for the whole run
    Set duration = ..Duration(found)
    Set:$ISOBJECT($GET(%response))&&(duration > 30) %response.Timeout = duration + 60
    Set reset = {}.%FromJSON(..Reset())
    If reset.ward.error '= "" {
        Quit {"error": "the ward refused the reset: is the demo flag (^Wards.Config) set?"}.%ToJSON()
    }
    Set started = reset."reset_at"
    Set ^Interlock.Config("mode") = mode
    Set ^Interlock.Config("scenario") = scenario
    Set files = [], timeouts = [], error = ""
    Set steps = found.steps.%GetIterator()
    While steps.%GetNext(.j, .step) {
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
        Quit {"error": (error), "files": (files)}.%ToJSON()
    }
    Quit {"scenario": (scenario), "mode": (mode), "started_at": (started), "files": (files), "timeouts": (timeouts)}.%ToJSON()
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
/// cleared, and <code>^Interlock.Config("resetAt")</code> set to the time of the reset: the evidence collector ignores
/// message-store events older than it, since encounter ids are fixed per scenario. JSON text.
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
    Quit {"ward": (ward), "emptied": (emptied), "mode": "board", "reset_at": (resetAt)}.%ToJSON()
}

}
