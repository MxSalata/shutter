/// The live hospital's rotation (CONTRACTS 4.4, v1.38): S11 is out of the shipped list, and the build's
/// SHUTTER_LIVE_SCENARIOS is read into the hospital's namespace, normalised, and cleared by "default" or by no valid id.
/// The hospital's global is put back as it was.
Class Shutter.Test.LiveRotation Extends %UnitTest.TestCase
{

Method TestTheShippedRotationLeavesS11Out()
{
    Set list = $PARAMETER("Hospital.LivePlayer", "DEFAULTSCENARIOS")
    Do $$$AssertEquals(list, "S2,S8,S1,S23a,S3,S24,S15", "the rotation as shipped")
    Do $$$AssertEquals($LISTFIND($LISTFROMSTRING(list, ","), "S11"), 0, "S11 is out of it")
    Do $$$AssertNotEquals($LISTFIND($LISTFROMSTRING(list, ","), "S8"), 0, "S8, the one board, stays")
}

Method TestTheBuildsListIsNormalisedAndCleared()
{
    Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
    If hospital = "" {
        Do $$$AssertEquals(##class(Shutter.Setup).ConfigureLiveScenarios("S2,S8"), "no hospital", "no hospital namespace on this instance: nothing to write")
        Quit
    }
    Set had = $DATA(^|hospital|Hospital.Config("liveScenarios")), keep = $GET(^|hospital|Hospital.Config("liveScenarios"))
    Do $$$AssertEquals(##class(Shutter.Setup).ConfigureLiveScenarios(" s2, S8 ,S23a,,bogus,S11xx,S24"), "S2,S8,S23a,S24", "ids trimmed, the S in upper case, the rest dropped")
    Do $$$AssertEquals($GET(^|hospital|Hospital.Config("liveScenarios")), "S2,S8,S23a,S24", "and written for the player")
    Do $$$AssertEquals(##class(Shutter.Setup).ConfigureLiveScenarios("default"), "default", "default clears it")
    Do $$$AssertEquals($DATA(^|hospital|Hospital.Config("liveScenarios")), 0, "and the global is gone")
    Do ##class(Shutter.Setup).ConfigureLiveScenarios("S8")
    Do $$$AssertEquals(##class(Shutter.Setup).ConfigureLiveScenarios("nothing, at all"), "default", "no valid id clears it too")
    Do $$$AssertEquals($DATA(^|hospital|Hospital.Config("liveScenarios")), 0, "gone again")
    Kill ^|hospital|Hospital.Config("liveScenarios")
    If had Set ^|hospital|Hospital.Config("liveScenarios") = keep
}

/// The live hospital's guard: a namespace with no API service registered is not listening, and asking never throws.
/// A live story stamps its cases with a scenario id, as the scenario runner does, but it isn't the runner: only a case that opens
/// under the runner's own run records it, for the gate's exemption in Rules only, and a later story leaves that case as it was.
Method TestALiveStoryIsNotARecordedRun()
{
    Set scenario = $GET(^Shutter.Config("scenario")), run = $GET(^Shutter.Config("scenarioRun"))
    Set ^Shutter.Config("scenario") = "S8", ^Shutter.Config("scenarioRun") = "S8"
    Set played = ..OpenCase("played")
    Do $$$AssertEquals(played.Scenario, "S8", "a case under the runner's run carries the scenario")
    Do $$$AssertEquals(played.ScenarioRecorded, 1, "and records that the runner played it")
    Set player = ##class(Hospital.LivePlayer).%New("Live PAS")
    Set player.ShutterNamespace = $NAMESPACE
    Do player.Stamp("S8")
    Set story = ..OpenCase("story")
    Do $$$AssertEquals(story.Scenario, "S8", "a live story's case still carries the id")
    Do $$$AssertEquals(story.ScenarioRecorded, 0, "and doesn't record a run, though it is the same scenario")
    Do played.%Reload()
    Do $$$AssertEquals(played.ScenarioRecorded, 1, "the runner's case keeps what it recorded")
    Set ^Shutter.Config("scenarioRun") = "S8", ^Shutter.Config("scenario") = ""
    Do player.Stamp("")
    Do $$$AssertEquals($GET(^Shutter.Config("scenarioRun")), "S8", "a blank stamp doesn't end a run")
    Set none = ..OpenCase("none")
    Do $$$AssertEquals(none.ScenarioRecorded, 0, "and a case with no stamp records nothing")
    Do ##class(Shutter.Store.Case).%DeleteId(played.%Id()), ##class(Shutter.Store.Case).%DeleteId(story.%Id()), ##class(Shutter.Store.Case).%DeleteId(none.%Id())
    Set ^Shutter.Config("scenario") = scenario, ^Shutter.Config("scenarioRun") = run
}

Method OpenCase(name As %String) As Shutter.Store.Case
{
    Set visit = "ENC-UT-LIVE-" _ name
    Set op = {"operation_key": ("PAS^HOSP^MRN-UT-LIVE^" _ visit _ "^transfer^2026-10-19T09:00:00Z"), "encounter_id": (visit), "patient_id": "MRN-UT-LIVE", "patient_id_authority": "HOSP", "source_system": "PAS", "event": "transfer", "event_time": "2026-10-19T09:00:00Z", "ward": "WARD-B", "payload_digest": "sha256:ut"}
    Do $$$AssertStatusOK(##class(Shutter.Store.Case).Open(op, "delivery_failed", "unit test", "", "", "rules", .case, .opened), name _ ": the case opens")
    Quit case
}

Method TestShutterListening()
{
    Do $$$AssertNotTrue(##class(Hospital.LivePlayer).ShutterListening("SHUTTERNOSUCHNS"), "no such namespace")
    Do $$$AssertNotTrue(##class(Hospital.LivePlayer).ShutterListening("%SYS"), "a namespace with no production")
    // The yes matters as much: a guard that always says no would silence the demo's hospital with nothing else failing.
    Do ##class(Ens.Director).GetProductionStatus(.production, .state)
    If ($GET(production) = "Shutter.Production") && ($GET(state) = 1) {
        Do $$$AssertTrue(##class(Hospital.LivePlayer).ShutterListening($NAMESPACE), "Shutter's production is running here")
    }
}

}
