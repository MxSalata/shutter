/// A scenario run counts against the share of who started it (1.4.3): the runner records the user beside the scenario
/// (^Shutter.Config("scenarioBy"), Shutter.Scenarios.Runner Begin), a case the run opens keeps it (Shutter.Store.Case's
/// ScenarioBy), and the case's agent requests carry it (Shutter.Process.CaseWorkflow Stamp), so a judge's board run spends
/// the judge's share of the day's model budget as a convened board does. A live story's case, which the runner did not play,
/// keeps the feed's own "system". The test puts every value it marks back.
Class Shutter.Test.ScenarioBy Extends %UnitTest.TestCase
{

/// The ^Shutter.Config values the test sets, as they were: $LISTBUILD($DATA, value).
Property Saved As %String(MAXLEN = "") [ MultiDimensional ];

/// The cases the test opened, by row id.
Property Opened As %String(MAXLEN = "");

Method OnBeforeOneTest() As %Status
{
    For key = "scenario", "scenarioRun", "scenarioBy" {
        Set ..Saved(key) = $LISTBUILD($DATA(^Shutter.Config(key)) # 10, $GET(^Shutter.Config(key)))
    }
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    For key = "scenario", "scenarioRun", "scenarioBy" {
        Set saved = $GET(..Saved(key))
        Continue:saved=""
        If $LIST(saved, 1) { Set ^Shutter.Config(key) = $LIST(saved, 2) } Else { Kill ^Shutter.Config(key) }
    }
    For i = 1:1:$LENGTH(..Opened, ",") {
        Set id = $PIECE(..Opened, ",", i)
        Continue:id=""
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
        Kill ^Shutter.Counter("event", id)
        If ##class(Shutter.Store.Case).%ExistsId(id) Do ##class(Shutter.Store.Case).%DeleteId(id)
    }
    Set ..Opened = ""
    Quit $$$OK
}

/// Opens a case for an operation of this test's own, as the feed does.
Method OpenOne(n As %Integer, Output case As Shutter.Store.Case) As %Status
{
    Set enc = "ENC-UTSB" _ n _ "-" _ $JOB, mrn = "MRN-UTSB" _ n
    Set op = {"operation_key": ("PAS^HOSP^" _ mrn _ "^" _ enc _ "^admit^2026-11-10T01:00:0" _ n _ "Z"), "encounter_id": (enc), "patient_id": (mrn), "patient_id_authority": "HOSP", "event": "admit", "ward": "WARD-A", "bed": null, "event_time": ("2026-11-10T01:00:0" _ n _ "Z"), "source_system": "PAS", "source_message_id": ("UTSB" _ n), "payload_digest": ("sha256:utsb" _ n)}
    Set sc = ##class(Shutter.Store.Case).Open(op, "delivery_failed", "Delivery unavailable (test)", "", "", "board", .case, .opened)
    If $$$ISOK(sc) && $ISOBJECT(case) Set ..Opened = ..Opened _ "," _ case.%Id()
    Quit sc
}

/// A case the runner's run opens keeps who started the run; a live story's case, stamped with a scenario but not a recorded
/// run, keeps nobody.
Method TestACaseKeepsWhoStartedTheRun()
{
    Set ^Shutter.Config("scenario") = "S8", ^Shutter.Config("scenarioRun") = "S8", ^Shutter.Config("scenarioBy") = "judge"
    Do $$$AssertStatusOK(..OpenOne(1, .case), "a case while the judge's run of S8 plays")
    Do $$$AssertTrue(case.ScenarioRecorded, "the runner played it")
    Do $$$AssertEquals(case.ScenarioBy, "judge", "and it keeps who started the run")
    Do case.%JSONExportToString(.json)
    Do $$$AssertNotTrue(json [ "judge", "who started the run is not in the case's JSON: " _ $EXTRACT(json, 1, 200))
    // A live story stamps its scenario and ends the recorded run (Hospital.LivePlayer Stamp)
    Set ^Shutter.Config("scenario") = "S8"
    Kill ^Shutter.Config("scenarioRun")
    Do $$$AssertStatusOK(..OpenOne(2, .story), "a case while a live story of S8 plays")
    Do $$$AssertNotTrue(story.ScenarioRecorded, "a live story's case is not a recorded run")
    Do $$$AssertEquals(story.ScenarioBy, "", "and keeps nobody")
}

/// The share's rule: a convener of a forced board first, then a reopener, then who started the scenario run, else the
/// feed's own "system".
Method TestTheRunsCountAgainstWhoStartedTheRun()
{
    Set cls = "Shutter.Process.CaseWorkflow"
    If '##class(%Dictionary.CompiledMethod).%ExistsId(cls _ "||Stamp") {
        Do $$$AssertSkipped("the case workflow is not compiled on this instance")
        Quit
    }
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 0, "", "", 1, "judge")
    Do $$$AssertEquals(req.RequestedBy, "judge", "a case of the judge's scenario run counts against the judge")
    Do $$$AssertEquals(req.ModeOverride, "", "and runs as its mode says")
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 0, "", "operator", 1, "judge")
    Do $$$AssertEquals(req.RequestedBy, "operator", "a reopening counts against the reopener")
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 1, "approver", "", 1, "judge")
    Do $$$AssertEquals(req.RequestedBy, "approver", "a forced board against its convener")
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 0, "", "", 1, "")
    Do $$$AssertEquals(req.RequestedBy, "system", "a case nobody's run opened is the feed's own")
}

/// The runner records who started the run with the scenario and the reset forgets it, read from their source: Begin can't
/// run here without resetting the demo's receivers.
Method TestTheRunnerRecordsAndTheResetForgets()
{
    Set begin = ..Source("Shutter.Scenarios.Runner", "Begin"), reset = ..Source("Shutter.Scenarios.Runner", "Reset")
    Do $$$AssertTrue(begin [ "^Shutter.Config(""scenarioBy"") = requestedBy", "Begin records who started the run")
    Do $$$AssertTrue(reset [ "^Shutter.Config(""scenarioBy"")", "Reset forgets it with the scenario")
    Do $$$AssertTrue(..Source("Shutter.Operation.ScenarioPlayer", "OnRun") [ "request.RequestedBy, ''request.LiveAllowed)", "the Scenario Player passes the user the API sent the run for, and whether that user has the live agents")
}

ClassMethod Source(class As %String, method As %String) As %String
{
    Set def = ##class(%Dictionary.MethodDefinition).%OpenId(class _ "||" _ method)
    If '$ISOBJECT(def) Quit ""
    Do def.Implementation.Rewind()
    Quit def.Implementation.Read(1000000)
}

}
