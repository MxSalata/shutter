/// A scenario run's label on the cases of the messages it played (CONTRACTS 4, v1.71): the runner records each message it
/// plays by its control id (Shutter.Scenarios.Runner MarkSent), and Shutter.Store.Case Open takes the scenario, the recorded
/// run, who started it and the replay mark from there, so a case that opens after the live hospital's player has rewritten
/// the stamp still carries its run's label. S35's case reaches Shutter through the demo hospital's alert and forwarder, and
/// could open after the ordinary feed's blank stamp. A step played after a story has started still records the run's whole
/// tag, kept by Begin (KeepTag). A message the run did not play keeps the stamp, and a reset forgets the run's messages.
/// The runner's settings and the cases made here go back as they were.
Class Shutter.Test.ScenarioSent Extends %UnitTest.TestCase
{

Parameter RUNNER = "Shutter.Scenarios.Runner";

/// The settings a run's tag writes, as they were before each test.
Property Saved As %String [ MultiDimensional ];

/// The cases and files made by a test, removed after it.
Property Made As %String [ MultiDimensional ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Kill ..Saved, ..Made
    For key = "scenario", "scenarioRun", "scenarioBy", "scenarioReplay", "scenarioTag", "resetAt", "mode" {
        Set:$DATA(^Shutter.Config(key))#2 ..Saved(key) = ^Shutter.Config(key)
    }
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Set id = ""
    For {
        Set id = $ORDER(..Made("case", id)) Quit:id=""
        Do ##class(Shutter.Store.Case).%DeleteId(id)
    }
    Set control = ""
    For {
        Set control = $ORDER(..Made("control", control)) Quit:control=""
        Kill ^Shutter.Config("scenarioSent", control)
    }
    Set path = ""
    For {
        Set path = $ORDER(..Made("file", path)) Quit:path=""
        Do ##class(%File).Delete(path)
    }
    For key = "scenario", "scenarioRun", "scenarioBy", "scenarioReplay", "scenarioTag", "resetAt", "mode" {
        If $DATA(..Saved(key)) { Set ^Shutter.Config(key) = ..Saved(key) } Else { Kill ^Shutter.Config(key) }
    }
    Quit $$$OK
}

/// The run's tag as Begin writes it, through the runner's own methods: the stamp and the recorded run (Tag; none for a
/// pathology path), who started it and whether it replays, and the whole tag kept (KeepTag).
/// <method>TestBeginKeepsTheWholeTag</method> holds Begin to the same call.
Method Tag(scenario As %String, by As %String, replay As %Boolean, pathology As %Boolean = 0)
{
    Do $CLASSMETHOD(..#RUNNER, "Tag", scenario, pathology)
    Set ^Shutter.Config("scenarioBy") = by, ^Shutter.Config("scenarioReplay") = replay
    Do $CLASSMETHOD(..#RUNNER, "KeepTag", scenario, 'pathology, by, replay)
}

/// A method's source, as the class defines it.
ClassMethod Source(class As %String, method As %String) As %String
{
    Set def = ##class(%Dictionary.MethodDefinition).%OpenId(class _ "||" _ method)
    If '$ISOBJECT(def) Quit ""
    Do def.Implementation.Rewind()
    Quit def.Implementation.Read(1000000)
}

/// A one-message HL7 file with the control id given, as a fixture is, recorded for removal.
Method WriteMessage(control As %String) As %String
{
    Set path = ##class(%File).TempFilename("hl7")
    Set file = ##class(%Stream.FileCharacter).%New()
    Do file.LinkToFile(path)
    Do file.Write("MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015092000||ADT^A02^ADT_A02|" _ control _ "|P|2.5.1" _ $CHAR(13) _ "EVN|A02|20261015092000||||20261015092000" _ $CHAR(13))
    Do $$$AssertStatusOK(file.%Save(), "the message file is written")
    Set ..Made("file", path) = "", ..Made("control", control) = ""
    Quit path
}

/// A case for the message with the control id given, opened as the case workflow opens one.
Method OpenCase(control As %String) As Shutter.Store.Case
{
    Set visit = "ENC-UT-SENT-" _ control
    Set op = {"operation_key": ("PAS^HOSP^MRN-UT-SENT^" _ visit _ "^transfer^2026-10-15T08:20:00Z"), "encounter_id": (visit), "patient_id": "MRN-UT-SENT", "patient_id_authority": "HOSP", "source_system": "PAS", "event": "transfer", "event_time": "2026-10-15T08:20:00Z", "ward": "WARD-B", "source_message_id": (control)}
    Set case = ""
    Do $$$AssertStatusOK(##class(Shutter.Store.Case).Open(op, "delivery_failed", "unit test", "", "", "policy", .case, .opened), control _ ": the case opens")
    If $ISOBJECT(case) Set ..Made("case", case.%Id()) = ""
    Quit case
}

/// The demo's S35 path: the run tags S35 for a replay-only starter and plays its message; a minute later the live hospital's
/// ordinary feed blanks the stamp and a story sets its own; only then does the case open, as the alert and the forwarder
/// brought it. It carries S35, the recorded run, the starter and the replay mark. Before 1.5.2 it took the story's id (or
/// none), was not a recorded run, and its agents would not have replayed.
Method TestALateCaseKeepsItsRunsLabel()
{
    Set control = "UT-SENT-" _ $JOB _ "-1"
    Set path = ..WriteMessage(control)
    Do ..Tag("S35", "ut-sent-user", 1)
    Do $CLASSMETHOD(..#RUNNER, "MarkSent", path, "S35")
    Set player = ##class(Hospital.LivePlayer).%New("Live PAS")
    Set player.ShutterNamespace = $NAMESPACE
    Do player.Stamp("")
    Do player.Stamp("S2")
    Do $$$AssertEquals($GET(^Shutter.Config("scenario")), "S2", "the stamp is the live story's by the time the case opens")
    Set case = ..OpenCase(control)
    Quit:'$ISOBJECT(case)
    Do $$$AssertEquals(case.Scenario, "S35", "the case carries its run's scenario")
    Do $$$AssertEquals(case.ScenarioRecorded, 1, "and records that the runner played it")
    Do $$$AssertEquals(case.ScenarioBy, "ut-sent-user", "and who started the run")
    Do $$$AssertEquals(case.ScenarioReplay, 1, "and that the run replays")
    // A message the run did not play opens under the stamp, as before: the live story's
    Set other = ..OpenCase("UT-SENT-" _ $JOB _ "-other")
    Quit:'$ISOBJECT(other)
    Do $$$AssertEquals(other.Scenario, "S2", "a message the run did not play takes the stamp")
    Do $$$AssertEquals(other.ScenarioRecorded, 0, "and a live story's case is no recorded run")
}

/// A file step played after a live story has started: the story's stamp killed ^Shutter.Config("scenarioRun") and the
/// ordinary feed blanked the stamp before the runner recorded the message (S11's file steps go out over 37 s, and a story
/// starts every 7 minutes, at once on a fresh start). The record is still the run's whole tag, from what Begin kept, so the
/// case is S35's recorded run, for its starter, replaying. Read from scenarioRun when the step plays, as before, it was no
/// recorded run, and so had no starter and no replay mark: a replay-only starter's case would have run its agents live.
Method TestALaterStepKeepsTheRunsTag()
{
    Set control = "UT-SENT-" _ $JOB _ "-5"
    Set path = ..WriteMessage(control)
    Do ..Tag("S35", "ut-sent-user", 1)
    Set player = ##class(Hospital.LivePlayer).%New("Live PAS")
    Set player.ShutterNamespace = $NAMESPACE
    Do player.Stamp("S2")
    Do player.Stamp("")
    Do $$$AssertEquals($DATA(^Shutter.Config("scenarioRun")), 0, "the story's stamp has killed the recorded run")
    Do $CLASSMETHOD(..#RUNNER, "MarkSent", path, "S35")
    Set case = ..OpenCase(control)
    Quit:'$ISOBJECT(case)
    Do $$$AssertEquals(case.Scenario, "S35", "the case carries its run's scenario")
    Do $$$AssertEquals(case.ScenarioRecorded, 1, "and is still the runner's recorded run")
    Do $$$AssertEquals(case.ScenarioBy, "ut-sent-user", "for who started it")
    Do $$$AssertEquals(case.ScenarioReplay, 1, "and replays its agents")
}

/// Begin keeps the whole tag from its own values (the scenario, a recorded run unless it is a pathology path, who started
/// it and the replay mark), not read back from the globals the player rewrites, and the reset forgets it. Read from the
/// source, since Begin can't run here without resetting the demo's receivers.
Method TestBeginKeepsTheWholeTag()
{
    Do $$$AssertTrue(..Source(..#RUNNER, "Begin") [ "..KeepTag(scenario, '$ISOBJECT(pathology), requestedBy, '+liveAllowed)", "Begin keeps the run's whole tag")
    Do $$$AssertTrue(..Source(..#RUNNER, "Reset") [ "^Shutter.Config(""scenarioTag"")", "and the reset forgets it")
    // A pathology path's kept tag is no recorded run, and no scenario keeps none
    Do $CLASSMETHOD(..#RUNNER, "KeepTag", "P1", 0, "", 0)
    Do $$$AssertEquals($LISTGET(^Shutter.Config("scenarioTag"), 2), 0, "a pathology path is no recorded run")
    Do $CLASSMETHOD(..#RUNNER, "KeepTag", "", 1, "", 0)
    Do $$$AssertEquals($LISTGET(^Shutter.Config("scenarioTag"), 2), 0, "nor is no scenario")
}

/// Played without a kept tag (a test calling Play by itself), the record is worked out from the scenario: a scenario is a
/// recorded run even once the player has killed scenarioRun, and nothing is recorded for no scenario.
Method TestWithoutAKeptTag()
{
    Set control = "UT-SENT-" _ $JOB _ "-6"
    Set path = ..WriteMessage(control)
    Kill ^Shutter.Config("scenarioTag"), ^Shutter.Config("scenarioRun")
    Set ^Shutter.Config("scenarioBy") = "", ^Shutter.Config("scenarioReplay") = 0
    Do $CLASSMETHOD(..#RUNNER, "MarkSent", path, "")
    Do $$$AssertEquals($DATA(^Shutter.Config("scenarioSent", control)), 0, "no scenario, no record")
    Do $CLASSMETHOD(..#RUNNER, "MarkSent", path, "UT-SENT-SCENARIO")
    Set sent = $GET(^Shutter.Config("scenarioSent", control))
    Do $$$AssertEquals($LISTGET(sent, 1), "UT-SENT-SCENARIO", "the scenario")
    Do $$$AssertEquals($LISTGET(sent, 2), 1, "a recorded run, though scenarioRun is gone")
}

/// A pathology path's tag sets the stamp and no recorded run: a message it plays is labelled, never recorded.
Method TestAPathologyTagLabelsAndRecordsNothing()
{
    Set control = "UT-SENT-" _ $JOB _ "-2"
    Set path = ..WriteMessage(control)
    Do ..Tag("P1", "", 0, 1)
    Do $CLASSMETHOD(..#RUNNER, "MarkSent", path, "P1")
    Set ^Shutter.Config("scenario") = ""
    Set case = ..OpenCase(control)
    Quit:'$ISOBJECT(case)
    Do $$$AssertEquals(case.Scenario, "P1", "labelled with the path")
    Do $$$AssertEquals(case.ScenarioRecorded, 0, "and no recorded run")
    Do $$$AssertEquals(case.ScenarioBy, "", "so nobody's share")
}

/// The control id comes from MSH-10; a file that is missing or holds no MSH segment gives none, and records nothing.
Method TestControlId()
{
    Set control = "UT-SENT-" _ $JOB _ "-3"
    Set path = ..WriteMessage(control)
    Do $$$AssertEquals($CLASSMETHOD(..#RUNNER, "ControlId", path), control, "MSH-10 of the file")
    Do $$$AssertEquals($CLASSMETHOD(..#RUNNER, "ControlId", path _ ".none"), "", "no file, no id")
    Set bare = ##class(%File).TempFilename("hl7")
    Set file = ##class(%Stream.FileCharacter).%New()
    Do file.LinkToFile(bare)
    Do file.Write("EVN|A02|20261015092000" _ $CHAR(13))
    Do file.%Save()
    Set ..Made("file", bare) = ""
    Do $$$AssertEquals($CLASSMETHOD(..#RUNNER, "ControlId", bare), "", "no MSH segment, no id")
    Do ..Tag("S35", "", 0)
    Set before = 0, k = ""
    For { Set k = $ORDER(^Shutter.Config("scenarioSent", k)) Quit:k=""  Set before = before + 1 }
    Do $CLASSMETHOD(..#RUNNER, "MarkSent", bare, "S35")
    Set after = 0, k = ""
    For { Set k = $ORDER(^Shutter.Config("scenarioSent", k)) Quit:k=""  Set after = after + 1 }
    Do $$$AssertEquals(after, before, "and nothing is recorded for it")
}

/// The next run's reset forgets the last run's messages, so a later case of the same message takes the next run's label.
/// This calls the real Reset, as Shutter.Test.ResetLive does, on a demo instance only; the mode and resetAt go back.
Method TestTheResetForgetsTheRunsMessages()
{
    If '$GET(^Shutter.Config("demo")) {
        Do $$$AssertEquals($CLASSMETHOD(..#RUNNER, "NotDemo") '= "", 1, "not a demo instance: no reset to call")
        Quit
    }
    Set control = "UT-SENT-" _ $JOB _ "-4"
    Set path = ..WriteMessage(control)
    Do ..Tag("S35", "", 0)
    Do $CLASSMETHOD(..#RUNNER, "MarkSent", path, "S35")
    Do $$$AssertNotEquals($GET(^Shutter.Config("scenarioSent", control)), "", "the run's message is recorded")
    Try {
        Do $CLASSMETHOD(..#RUNNER, "Reset")
    } Catch ex {
        Do $$$AssertTrue(0, "Reset threw: " _ ex.DisplayString())
    }
    Do $$$AssertEquals($DATA(^Shutter.Config("scenarioSent")), 0, "and gone after the reset")
}

}
