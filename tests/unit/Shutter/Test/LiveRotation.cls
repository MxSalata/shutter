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

}
