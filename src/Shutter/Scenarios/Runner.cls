/// Plays the demo scenarios (docs/CONTRACTS.md, section 4). <method>Run</method> resets the downstream system, sets
/// the case workflow's mode, then plays a scenario's steps: faults on the downstream system, HL7 files into the
/// production's inbound folder, waits, for S7 and S20 a wait for the case's state, and for S20 a change a person makes
/// in the downstream system by hand. The production and the app do the rest.
/// <method>Start</method> does the same in a background job and returns at once, for the app. The methods are SQL
/// procedures, so scripts and the app can call them: <code>SELECT Shutter_Scenarios.Runner_Run('S2', 'board')</code>.
/// All three play on a demo instance only (<method>NotDemo</method>), whoever calls them.
Class Shutter.Scenarios.Runner
{

/// Seconds a <code>wait_for_state</code> step waits when it gives no <code>timeout</code>.
Parameter WAITTIMEOUT = 120;

/// The source system of an operation a <code>manual</code> step enters: a person on the ward, in the downstream
/// system's own screens rather than through the feed.
Parameter MANUALSOURCE = "WARD";

/// The scenarios play on a demo instance only (^Shutter.Config("demo"), the flag GET /status reports): a run resets the
/// receivers first and a reset abandons every open incident, empties the inbound and archive folders and moves resetAt.
/// The REST routes refuse a site install first (Shutter.API.Dispatch, DemoOnly); this refuses a caller that reaches
/// <method>Run</method>, <method>Start</method> or <method>Reset</method> another way, over SQL or from the terminal,
/// with the same words. Returns the refusal as JSON text, or an empty string on a demo instance.
ClassMethod NotDemo() As %String
{
    Quit:$GET(^Shutter.Config("demo")) ""
    Quit {"error": "not_a_demo_instance", "detail": "Scenarios run and reset on a demo instance only: this instance is a site install, where a reset would abandon its open incidents"}.%ToJSON()
}

/// The folder that holds scenarios.json and one folder per scenario.
ClassMethod FixturesDir() As %String
{
    Quit ##class(%File).NormalizeDirectory($GET(^Shutter.Config("fixtures"), "/home/irisowner/dev/fixtures"))
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
/// mode, written to <code>^Shutter.Config("mode")</code>: board, single or rules. Whether agents run live or replay
/// is the agent items' production setting, not this. Returns JSON text.
ClassMethod Run(scenario As %String, mode As %String = "board") As %String [ SqlProc ]
{
    Set refused = ..NotDemo()
    Quit:refused'="" refused
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
    Set refused = ..NotDemo()
    Quit:refused'="" refused
    If ..Running() {
        Quit {"error": "scenario_running", "detail": ("a run of " _ {}.%FromJSON(^Shutter.Scenarios("run")).scenario _ " is still playing")}.%ToJSON()
    }
    Set found = ..Prepare(scenario, mode, .inbound, .error)
    Quit:error'="" {"error": (error)}.%ToJSON()
    Set started = ..Begin(scenario, mode, .error)
    Quit:error'="" {"error": (error)}.%ToJSON()
    Kill ^Shutter.Scenarios("run")
    Set record = {"scenario": (scenario), "mode": (mode), "startedAt": (started), "state": "running", "files": [], "timeouts": []}
    Do record.%Set("replay", ..ReplayOnly(), "boolean")
    Set ^Shutter.Scenarios("run") = record.%ToJSON()
    Job ##class(Shutter.Scenarios.Runner).Background(scenario, mode, started)::10
    If $TEST {
        Set ^Shutter.Scenarios("run", "job") = $ZCHILD
        Set out = {"scenario": (scenario), "mode": (mode), "startedAt": (started), "files": [], "running": true}
        Do out.%Set("replay", ..ReplayOnly(), "boolean")
        Quit out.%ToJSON()
    }
    // No process to spare (the Community licence caps them, and the production holds most): play the steps here,
    // in the caller's process, and answer when they are done. Called over HTTP, the gateway is asked to wait.
    Set duration = ..Duration(found)
    Set:$ISOBJECT($GET(%response))&&(duration > 30) %response.Timeout = duration + 60
    Set ^Shutter.Scenarios("run", "job") = $JOB
    Do ..Background(scenario, mode, started)
    Set run = {}.%FromJSON(^Shutter.Scenarios("run"))
    If run.state '= "done" {
        Quit {"error": (run.error), "files": (run.files)}.%ToJSON()
    }
    Set out = {"scenario": (scenario), "mode": (mode), "startedAt": (started), "files": (run.files), "timeouts": (run.timeouts), "running": false}
    Do out.%Set("replay", ..ReplayOnly(), "boolean")
    Quit out.%ToJSON()
}

/// The background run <method>Start</method> began, or the last one: scenario, mode, startedAt, state (running, done,
/// failed, or interrupted when its job is gone), files, timeouts, the step it is on while running, finishedAt and
/// error. JSON text, <code>null</code> when nothing has run.
ClassMethod Status() As %String [ SqlProc ]
{
    Set text = $GET(^Shutter.Scenarios("run"))
    Quit:text="" "null"
    Set run = {}.%FromJSON(text)
    If run.state = "running" {
        If ..Running() {
            Set run.step = $GET(^Shutter.Scenarios("run", "step"))
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
    Set run = {}.%FromJSON($GET(^Shutter.Scenarios("run"), "{}"))
    Set run.state = $SELECT(result.error '= "": "failed", 1: "done")
    Set run.files = result.files
    Set run.timeouts = $SELECT($ISOBJECT(result.timeouts): result.timeouts, 1: [])
    Set:result.error'="" run.error = result.error
    Set run.finishedAt = ##class(Downstream.Service).Now()
    Set ^Shutter.Scenarios("run") = run.%ToJSON()
    Kill ^Shutter.Scenarios("run", "step")
}

/// Whether a background run is playing: its record says running and its job is alive.
ClassMethod Running() As %Boolean
{
    Set text = $GET(^Shutter.Scenarios("run"))
    Quit:text="" 0
    Set run = {}.%FromJSON(text)
    Quit:run.state'="running" 0
    Set job = $GET(^Shutter.Scenarios("run", "job"))
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
    Set inbound = $GET(^Shutter.Config("adtIn"))
    If inbound = "" {
        Set error = "the adtIn setting (^Shutter.Config) is not set: run Shutter.Setup first"
        Quit ""
    }
    Set inbound = ##class(%File).NormalizeDirectory(inbound)
    Quit found
}

/// The reset before a run, and the mode and scenario recorded (CONTRACTS 4), with who started the run: the cases it opens
/// carry that user (Shutter.Store.Case's ScenarioBy), so their live agent runs count against that user's share of the day's
/// model budget, as a convened board does (1.4.3). <var>requestedBy</var> is the user the Scenario Player was sent the run
/// by; empty, the caller itself. <var>liveAllowed</var> is whether that user holds Shutter_LiveAgents, as the API read it
/// in the user's own process; empty, the caller's own right. Without it (the public demo's role, 1.4.4) the run is replay
/// only: ^Shutter.Config("scenarioReplay") says so, the cases it opens keep it (Case's ScenarioReplay), and every agent of
/// theirs answers from its recording (Shutter.Process.CaseWorkflow Stamp), with no model call and nothing spent; a mode
/// with no recording is refused before the reset (<method>NotRecorded</method>). Returns the time of the reset.
ClassMethod Begin(scenario As %String, mode As %String, Output error As %String, requestedBy As %String = "", liveAllowed As %String = "") As %String
{
    Set error = ""
    If liveAllowed = "" Set liveAllowed = $SYSTEM.Security.Check("Shutter_LiveAgents", "USE")
    Set error = ..NotRecorded(mode, liveAllowed)
    Quit:error'="" ""
    Set reset = {}.%FromJSON(..Reset())
    If reset.ward.error '= "" {
        Set error = "the downstream system refused the reset: is the demo flag (^Downstream.Config) set?"
        Quit ""
    }
    Set ^Shutter.Config("mode") = mode
    Set ^Shutter.Config("scenario") = scenario, ^Shutter.Config("scenarioRun") = scenario
    If requestedBy = "" Set requestedBy = $SELECT($USERNAME = "UnknownUser": "", 1: $USERNAME)
    Set ^Shutter.Config("scenarioBy") = requestedBy
    Set ^Shutter.Config("scenarioReplay") = '+liveAllowed
    Quit reset."reset_at"
}

/// Why a run in <var>mode</var> can't be played replay only, or "": the single investigator was never recorded, so a
/// starter without the live agents would have nothing to replay (1.4.4). The trial leaves that mode out for the same reason.
ClassMethod NotRecorded(mode As %String, liveAllowed As %Boolean) As %String
{
    Quit:+liveAllowed ""
    Quit:mode'="single" ""
    Quit "The single investigator has no recordings, and a run from this sign-in replays the recorded agents only: choose Board, Site policy or Rules only"
}

/// Whether the run playing now, or the last one, is replay only (1.4.4): who started it holds no Shutter_LiveAgents.
ClassMethod ReplayOnly() As %Boolean
{
    Quit +$GET(^Shutter.Config("scenarioReplay"))
}

/// Plays the steps of <var>found</var> after <method>Begin</method>. With <var>track</var>, each step is recorded for
/// <method>Status</method> as it starts.
ClassMethod Play(found As %DynamicObject, scenario As %String, mode As %String, started As %String, inbound As %String, track As %Boolean = 0) As %DynamicObject
{
    Set files = [], timeouts = [], error = ""
    Set steps = found.steps.%GetIterator()
    While steps.%GetNext(.j, .step) {
        Set:track ^Shutter.Scenarios("run", "step") = ..Describe(step)
        If step.%IsDefined("fault") {
            Set request = {"mode": (step.fault)}
            Do:step.%IsDefined("operation_key") request.%Set("operation_key", step."operation_key")
            Do:step.%IsDefined("seconds") request.%Set("seconds", step.seconds)
            // The receivers the fault applies to (v1.25): the step's list, else the bed manager alone, so the scenarios
            // written before keep their meaning. Each demo receiver is reached in its own namespace.
            Set targets = $SELECT(step.%IsDefined("receivers") && $ISOBJECT(step.receivers): step.receivers, 1: [($PARAMETER("Shutter.Production", "RECEIVER"))])
            Set ri = targets.%GetIterator()
            While ri.%GetNext(, .name) {
                Set answer = ..InReceiver(name, "SetFault", request, .status)
                Set:status'=200 error = "the receiver " _ name _ " refused the fault step: " _ $SELECT($ISOBJECT(answer): answer.%ToJSON(), 1: "HTTP " _ status)
                Quit:error'=""
            }
            Quit:error'=""
        } ElseIf step.%IsDefined("file") {
            // A step naming an item plays through that demo route instead of the inbound folder (S14, S26)
            If step.%IsDefined("item") {
                Set error = ##class(Shutter.Scenarios.Route).Play(step.item, step.path)
                Quit:error'=""
                Do files.%Push(step.file)
                Hang 2
                Continue
            }
            // A step with the route "hospital" drops the file into the demo hospital's own inbound folder (T33), so
            // the failure happens in the hospital's production and reaches Shutter through its forwarder.
            Set target = inbound
            If step.%IsDefined("route") && (step.route = "hospital") {
                Set target = $GET(^Shutter.Config("hospitalIn"))
                If target = "" {
                    Set error = "the step's route is the demo hospital, which is not installed (^Shutter.Config(""hospitalIn"") is not set)"
                    Quit
                }
                Set target = ##class(%File).NormalizeDirectory(target)
            }
            Set error = ..Drop(step.path, target)
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
            Set answer = ##class(Downstream.Service).SetCapabilities(step.capabilities, .status)
            Set:status'=200 error = "the downstream system refused the capabilities step: " _ answer.%ToJSON()
            Quit:error'=""
        } ElseIf step.%IsDefined("prevent_failures") {
            Do ##class(Shutter.Scenarios.SiteSchema).PreventFailures(step."prevent_failures")
        } ElseIf step.%IsDefined("schema_forget") {
            Do ##class(Shutter.Scenarios.SiteSchema).Forget(step."schema_forget")
        } ElseIf step.%IsDefined("schema_import") {
            Set error = ##class(Shutter.Scenarios.SiteSchema).Import(..FixturesDir() _ step."schema_import")
            Quit:error'=""
        } ElseIf step.%IsDefined("manual") {
            Set answer = ..Manual(step.manual, .status)
            Set:status'=201 error = "the downstream system refused the manual step: " _ $SELECT($ISOBJECT(answer): answer.%ToJSON(), 1: "HTTP " _ status)
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
    Quit:step.%IsDefined("file") "delivering " _ step.file _ $SELECT(step.%IsDefined("route") && (step.route = "hospital"): " to the demo hospital", step.%IsDefined("item"): " through " _ step.item, 1: "")
    Quit:step.%IsDefined("prevent_failures") "turning prevent failures " _ $SELECT(step."prevent_failures": "on", 1: "off") _ " for this run"
    Quit:step.%IsDefined("schema_forget") "removing the schema " _ step."schema_forget"
    Quit:step.%IsDefined("schema_import") "importing the schema " _ step."schema_import"
    Quit:step.%IsDefined("fault") "setting the fault to " _ step.fault _ $SELECT(step.%IsDefined("receivers") && $ISOBJECT(step.receivers): " on " _ $REPLACE($REPLACE($REPLACE(step.receivers.%ToJSON(), "[", ""), "]", ""), """", ""), 1: " on the downstream system")
    Quit:step.%IsDefined("wait") "waiting " _ step.wait _ " s"
    Quit:step.%IsDefined("wait_for_state") "waiting for the case to reach " _ $REPLACE(step."wait_for_state", "|", " or ")
    Quit:step.%IsDefined("capabilities") "changing the downstream system's capabilities"
    If step.%IsDefined("manual") {
        Set entry = step.manual
        Quit:'$ISOBJECT(entry) "a manual step with nothing to enter"
        Quit "entering a " _ entry.event _ " of " _ entry."encounter_id" _ $SELECT(entry.ward '= "": " to " _ entry.ward, 1: "") _ " in the downstream system by hand"
    }
    Quit "a step the runner doesn't know"
}

/// A <code>manual</code> step (CONTRACTS 4.3): an operation a person on the ward enters in the downstream system
/// itself while the feed's own delivery is still a case, as S20's nurse moves the patient. It goes to
/// <class>Downstream.Service</class> in process with its own source (<parameter>MANUALSOURCE</parameter> unless the
/// step names one) and its own operation key, and no expected version, as a person's entry has none; the downstream
/// system applies it like any operation, so its version moves and its history records the key. The patient is the
/// encounter's own unless the step names one, and the event time is the step's or now. Returns the downstream
/// system's answer, with its HTTP status in <var>status</var>: 201 when it applied.
ClassMethod Manual(entry As %DynamicObject, Output status As %Integer) As %DynamicObject
{
    If '$ISOBJECT(entry) {
        Set status = 422
        Quit {"error": "invalid_request", "detail": "a manual step is an object with encounter_id, event and, for an admission or a transfer, ward"}
    }
    Set encounterId = entry."encounter_id", event = entry.event
    Set patient = entry."patient_id", authority = entry."patient_id_authority"
    Set held = ##class(Downstream.Encounter).EncounterIdIdxOpen(encounterId)
    If $ISOBJECT(held) {
        Set:patient="" patient = held.PatientId
        Set:authority="" authority = held.PatientIdAuthority
    }
    Set source = $SELECT(entry."source_system" '= "": entry."source_system", 1: ..#MANUALSOURCE)
    Set time = $SELECT(entry."event_time" '= "": entry."event_time", 1: ##class(Downstream.Service).Now())
    Set request = {"encounter_id": (encounterId), "patient_id": (patient), "patient_id_authority": (authority), "event": (event), "event_time": (time), "source_system": (source)}
    Set request."operation_key" = ##class(Shutter.Util.OperationKey).FromParts(source, authority, patient, encounterId, event, time)
    Do:entry.ward'="" request.%Set("ward", entry.ward)
    Quit ##class(Downstream.Service).Apply(request, .status)
}

/// Waits until the newest case of <var>scenario</var> reaches <var>state</var> (CONTRACTS 4.1). Returns 1 when it
/// did, 0 when <var>timeout</var> seconds passed; <var>problem</var> says why the case store couldn't be read.
ClassMethod WaitForState(scenario As %String, state As %String, timeout As %Integer = {..#WAITTIMEOUT}, Output problem As %String) As %Boolean
{
    Set problem = ""
    Set deadline = $ZHOROLOG + timeout
    While $ZHOROLOG < deadline {
        // Without privilege checks: the caller may be the app's user, which has no SQL privileges on the store
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 State FROM Shutter_Store.""Case"" WHERE Scenario = ? ORDER BY ID DESC", scenario)
        If rs.%SQLCODE < 0 {
            Set problem = rs.%Message
            Return 0
        }
        If rs.%Next(), ..StateIs(rs.%Get("State"), state) {
            Return 1
        }
        Hang 1
    }
    Quit 0
}

/// Whether a case's state is the one a wait names, or one of several separated by "|" (S26: awaiting_approval|resolved).
ClassMethod StateIs(state As %String, wanted As %String) As %Boolean
{
    Quit (state '= "") && (("|" _ wanted _ "|") [ ("|" _ state _ "|"))
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

/// The downstream system reset, the live hospital's bed map cleared (unless a story is playing), the inbound and archive
/// folders (Shutter's and the demo hospital's) emptied of
/// fixtures, the mode back to board, the
/// running scenario and any run record that isn't playing cleared, and <code>^Shutter.Config("resetAt")</code> set to
/// the time of the reset: the evidence collector ignores message-store events older than it, since encounter ids are
/// fixed per scenario. An incident still open is abandoned, since the downstream system it would release into has just
/// been reset; its open cases fail with the reason. JSON text.
ClassMethod Reset() As %String [ SqlProc ]
{
    Set refused = ..NotDemo()
    Quit:refused'="" refused
    Set resetAt = ##class(Downstream.Service).Now()
    Set ward = ##class(Downstream.Service).Reset(.status)
    // Every other demo receiver the profile lists, in its own namespace (v1.25): the records system beside the bed manager.
    Set receivers = {}, names = ##class(Shutter.Store.SiteProfile).ReceiverNames(), ni = names.%GetIterator()
    While ni.%GetNext(, .name) {
        Continue:##class(Shutter.Store.SiteProfile).ReceiverNamespace(name)=$NAMESPACE
        Set answer = ..InReceiver(name, "Reset", "", .rstatus)
        Do receivers.%Set(name, $SELECT($ISOBJECT(answer): answer, 1: {"error": ("HTTP " _ rstatus)}))
    }
    Set live = ..ResetLive()
    Set emptied = []
    For setting = "adtIn", "adtArchive", "hospitalIn", "hospitalArchive" {
        Set dir = $GET(^Shutter.Config(setting))
        Continue:dir=""
        Set dir = ##class(%File).NormalizeDirectory(dir)
        Do emptied.%Push(dir)
        Set rs = ##class(%File).FileSetFunc(dir, "*.hl7;*.part", , 0)
        While rs.%Next() {
            Do:rs.%Get("Type")="F" ##class(%File).Delete(rs.%Get("Name"))
        }
    }
    Set ^Shutter.Config("mode") = "board"
    Kill ^Shutter.Config("scenario"), ^Shutter.Config("scenarioRun"), ^Shutter.Config("scenarioBy"), ^Shutter.Config("scenarioReplay")
    // S26 turns the hold on for its own run: a run cut off must not leave it on, so the profile's word stands again.
    Do ##class(Shutter.Scenarios.SiteSchema).PreventFailures(0)
    Set ^Shutter.Config("resetAt") = resetAt
    Set abandoned = ##class(Shutter.Store.Incident).AbandonOpen("scenario reset")
    Do ##class(Shutter.Util.RecoveryControl).DemoReset($USERNAME)
    // A run record left queued or finished goes with the reset (a queued run whose player stopped would otherwise
    // refuse every later run); one that is playing stays, since that run's own reset comes through here
    Kill:'..Running() ^Shutter.Scenarios("run")
    Quit {"ward": (ward), "receivers": (receivers), "live": (live), "emptied": (emptied), "mode": "board", "reset_at": (resetAt), "abandoned_incidents": (abandoned)}.%ToJSON()
}

/// A playing mark older than this, in seconds, was left by a job that died: no story takes this long.
Parameter PLAYINGSTALESECONDS = 1800;

/// The live hospital's bed map goes with the reset (CONTRACTS 4.4): the receiver has just forgotten every encounter, so
/// each patient the ordinary feed still knew (Shutter.Util.LiveFeed.Ordinary, ^Hospital.Live("adm") and ("bed") in the
/// hospital's namespace) would from now on fail its transfer, update or discharge as unknown_encounter and open a spurious
/// case; with the map empty the feed admits fresh patients, and the turn counter starts again. Not while a story is
/// playing (^Hospital.Live("playing"), set by Hospital.LivePlayer.Play, which reads its own patients without $GET): the
/// map stays. Returns "cleared", "playing", "none" (no hospital namespace recorded in
/// ^Shutter.Config("hospitalNamespace")) or "not cleared" (the map could not be touched: a role without write access to
/// the hospital's data, say). Never an error: the receiver has already been reset by now, and the rest of the reset must
/// still happen.
ClassMethod ResetLive() As %String
{
    Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
    If hospital = "" Quit "none"
    Set result = "cleared"
    Try {
        Set playing = $GET(^|hospital|Hospital.Live("playing"))
        If $LISTVALID(playing), playing '= "", (##class(Shutter.Util.Time).EpochSeconds() - +$LISTGET(playing, 2)) < ..#PLAYINGSTALESECONDS {
            Set result = "playing"
        } Else {
            Kill ^|hospital|Hospital.Live("adm"), ^|hospital|Hospital.Live("bed"), ^|hospital|Hospital.Live("turn")
        }
    } Catch ex {
        Set result = "not cleared"
    }
    Quit result
}

/// A call on the demo receiver package in the namespace a receiver runs in (its profile entry's demo.namespace, else this
/// one): SetFault with a request, or Reset. The namespace is restored on return.
ClassMethod InReceiver(name As %String, method As %String, request As %DynamicObject = "", Output status As %Integer) As %DynamicObject
{
    Set status = 0, answer = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ##class(Shutter.Store.SiteProfile).ReceiverNamespace(name)
        If method = "Reset" {
            Set answer = ##class(Downstream.Service).Reset(.status)
        } Else {
            Set answer = ##class(Downstream.Service).SetFault(request, .status)
        }
    } Catch ex {
        Set status = 500, answer = {"error": ($ZCONVERT(ex.DisplayString(), "O", "JSON"))}
    }
    Quit answer
}

}
