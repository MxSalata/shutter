/// The scenario runner's reset and the live hospital (CONTRACTS 4 and 4.4): the reset clears the live feed's bed map in the
/// hospital's namespace unless a story is playing, and a story cut off mid-play leaves no fault on the receiver, since
/// the player records the receivers it faulted and the next job's OnInit turns them off. The hospital's globals and the
/// receiver's fault are put back as they were. Both tests need the hospital namespace recorded in this one.
Class Shutter.Test.ResetLive Extends %UnitTest.TestCase
{

Property Hospital As %String;

Property Saved As %String [ MultiDimensional ];

Property SavedFault As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
    Set ..Hospital = $GET(^Shutter.Config("hospitalNamespace"))
    Set h = ..Hospital
    If h '= "" {
        For node = "adm", "bed", "turn", "playing", "faulted", "storm" { Merge ..Saved(node) = ^|h|Hospital.Live(node) }
    }
    Merge ..SavedFault = ^Downstream.Config("fault")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Set h = ..Hospital
    If h '= "" {
        For node = "adm", "bed", "turn", "playing", "faulted", "storm" { Kill ^|h|Hospital.Live(node) Merge ^|h|Hospital.Live(node) = ..Saved(node) }
    }
    Kill ^Downstream.Config("fault")
    Merge ^Downstream.Config("fault") = ..SavedFault
    Quit $$$OK
}

Method SetPatient()
{
    Set h = ..Hospital
    Set ^|h|Hospital.Live("adm", "MRN500001") = $LISTBUILD("ENC-500001", "WARD-A", "LIVE1", "01", "20261103100000")
    Set ^|h|Hospital.Live("bed", "WARD-A", "LIVE1", "01") = "MRN500001"
    Set ^|h|Hospital.Live("turn") = 5
}

Method TestResetClearsTheBedMap()
{
    Set h = ..Hospital
    If h = "" {
        Do $$$AssertEquals(##class(Shutter.Scenarios.Runner).ResetLive(), "none", "no hospital namespace on this instance: nothing to clear")
        Quit
    }
    Set runner = "Shutter.Scenarios.Runner", time = "Shutter.Util.Time"
    Kill ^|h|Hospital.Live("playing")
    Do ..SetPatient()
    Do $$$AssertEquals($CLASSMETHOD(runner, "ResetLive"), "cleared", "no story playing: cleared")
    Do $$$AssertEquals($DATA(^|h|Hospital.Live("adm")) + $DATA(^|h|Hospital.Live("bed")) + $DATA(^|h|Hospital.Live("turn")), 0, "the patients, the beds and the turn are gone")
    // A story playing keeps its patients: the player reads them for its next message.
    Do ..SetPatient()
    Set ^|h|Hospital.Live("playing") = $LISTBUILD("S2", $CLASSMETHOD(time, "EpochSeconds"))
    Do $$$AssertEquals($CLASSMETHOD(runner, "ResetLive"), "playing", "a story playing: left alone")
    Do $$$AssertEquals($DATA(^|h|Hospital.Live("adm", "MRN500001")), 1, "the patient stays")
    Do $$$AssertEquals($DATA(^|h|Hospital.Live("bed", "WARD-A", "LIVE1", "01")), 1, "and the bed")
    Do $$$AssertEquals($GET(^|h|Hospital.Live("turn")), 5, "and the turn")
    // A mark older than any story was left by a job that died.
    Set ^|h|Hospital.Live("playing") = $LISTBUILD("S2", $CLASSMETHOD(time, "EpochSeconds") - $PARAMETER(runner, "PLAYINGSTALESECONDS") - 1)
    Do $$$AssertEquals($CLASSMETHOD(runner, "ResetLive"), "cleared", "a stale mark does not count")
    Do $$$AssertEquals($DATA(^|h|Hospital.Live("adm")), 0, "cleared")
    // The whole reset reports it.
    Kill ^|h|Hospital.Live("playing")
    Do ..SetPatient()
    Set answer = ##class(%DynamicObject).%FromJSON($CLASSMETHOD(runner, "Reset"))
    Do $$$AssertEquals(answer.live, "cleared", "Reset says so")
    Do $$$AssertEquals($DATA(^|h|Hospital.Live("adm")) + $DATA(^|h|Hospital.Live("bed")), 0, "and the map is gone")
}

/// A hospital the caller can't touch costs the bed map only: Reset goes on to the folders, the mode and resetAt (before
/// v1.42 it stopped with a 500, the receiver already reset). A namespace that doesn't exist fails as a protected one does.
Method TestAMapItCannotTouchLeavesTheResetWhole()
{
    Set saved = $GET(^Shutter.Config("hospitalNamespace")), before = $GET(^Shutter.Config("resetAt"))
    Set ^Shutter.Config("hospitalNamespace") = "SHUTTERNOSUCHNS"
    Set live = "", answer = ""
    Try {
        Set live = ##class(Shutter.Scenarios.Runner).ResetLive()
        Set answer = ##class(%DynamicObject).%FromJSON(##class(Shutter.Scenarios.Runner).Reset())
    } Catch ex {
        Do $$$AssertTrue(0, "Reset threw: " _ ex.DisplayString())
    }
    If saved = "" { Kill ^Shutter.Config("hospitalNamespace") } Else { Set ^Shutter.Config("hospitalNamespace") = saved }
    Do $$$AssertEquals(live, "not cleared", "ResetLive says so and does not throw")
    If $ISOBJECT(answer) {
        Do $$$AssertEquals(answer.live, "not cleared", "Reset's answer says so")
        Do $$$AssertEquals(answer."reset_at", ^Shutter.Config("resetAt"), "and resetAt was still set")
        Do $$$AssertEquals(answer.mode, "board", "and the mode went back")
    }
}

Method TestAStoryCutOffLeavesNoFault()
{
    Set h = ..Hospital
    If h = "" {
        Do $$$AssertEquals(##class(Hospital.LivePlayer).ClearFaultsLeft($NAMESPACE), "", "no hospital namespace on this instance: nothing recorded")
        Quit
    }
    Set shutter = $NAMESPACE, service = "Downstream.Service", player = "Hospital.LivePlayer"
    Kill ^|h|Hospital.Live("storm")
    // The story faulted the receiver and its job died before the end of Play.
    Do $CLASSMETHOD(service, "SetFault", {"mode": "fail_before_accept"}, .status)
    Do $$$AssertEquals(status, 200, "the fault is on")
    Set ^|h|Hospital.Live("faulted", "Downstream Out") = 1
    Set ^|h|Hospital.Live("playing") = $LISTBUILD("S2", ##class(Shutter.Util.Time).EpochSeconds())
    Do ..InHospital(.cleared, .sc)
    Do $$$AssertStatusOK(sc, "the player's OnInit ran in the hospital's namespace")
    Do $$$AssertEquals($CLASSMETHOD(service, "GetFault", .status).mode, "off", "the next job turned the fault off")
    Do $$$AssertEquals($DATA(^|h|Hospital.Live("faulted")) + $DATA(^|h|Hospital.Live("playing")), 0, "and forgot the story")
    // The storm's outage is not a story's: it stays until StormWatch ends it.
    Do $CLASSMETHOD(service, "SetFault", {"mode": "fail_before_accept"}, .status)
    Set ^|h|Hospital.Live("faulted", "Downstream Out") = 1
    Set ^|h|Hospital.Live("storm") = {"stormId": "ST-000001", "state": "waiting_receiver"}.%ToJSON()
    Do ..InHospital(.cleared, .sc)
    Do $$$AssertEquals($CLASSMETHOD(service, "GetFault", .status).mode, "fail_before_accept", "a storm waiting for its receiver keeps the fault")
    Do $$$AssertEquals($DATA(^|h|Hospital.Live("faulted", "Downstream Out")), 1, "and the record, for later")
    Set ^|h|Hospital.Live("storm") = {"stormId": "ST-000001", "state": "done"}.%ToJSON()
    Do ..InHospital(.cleared, .sc)
    Do $$$AssertEquals($CLASSMETHOD(service, "GetFault", .status).mode, "off", "the storm done: cleared")
    Do $$$AssertEquals(cleared, "Downstream Out", "the method names the receiver")
    Do $CLASSMETHOD(service, "SetFault", {"mode": "off"}, .status)
}

/// The next job's OnInit, in the hospital's namespace: the service as the production creates it when it runs there, else
/// the class on its own; <var>cleared</var> is what ClearFaultsLeft answered on the way.
Method InHospital(Output cleared As %String, Output sc As %Status)
{
    Set cleared = "", sc = $$$OK, h = ..Hospital, shutter = $NAMESPACE
    Try {
        New $NAMESPACE
        Set $NAMESPACE = h
        Set before = $GET(^Hospital.Live("faulted", "Downstream Out"))
        Set sc = ##class(Ens.Director).CreateBusinessService("Live PAS", .svc)
        If $$$ISERR(sc) || '$ISOBJECT($GET(svc)) {
            Set svc = ##class(Hospital.LivePlayer).%New("Live PAS")
            Set sc = $SELECT($ISOBJECT(svc): $$$OK, 1: $$$ERROR($$$GeneralError, "the player could not be created: " _ $SYSTEM.Status.GetErrorText(%objlasterror)))
        }
        Quit:$$$ISERR(sc)
        Set svc.ShutterNamespace = shutter
        Set sc = svc.OnInit()
        Set cleared = $SELECT(before && '$DATA(^Hospital.Live("faulted", "Downstream Out")): "Downstream Out", 1: "")
    } Catch ex {
        Set sc = ex.AsStatus()
    }
}

}
