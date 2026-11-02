/// The storm (CONTRACTS 4.4, v1.35): the route's refusal rule (Shutter.Setup.StormRefusal), the cooldown setting, and the
/// live player's plan (Hospital.LivePlayer.StormPlan). The plan takes beds in the live feed's globals of this namespace,
/// which are saved and put back.
Class Shutter.Test.Storm Extends %UnitTest.TestCase
{

Property Saved As %String [ MultiDimensional ];

Property SavedCooldown As %String;

Method OnBeforeAllTests() As %Status
{
    Merge ..Saved = ^Hospital.Live
    Set ..SavedCooldown = $GET(^Shutter.Config("stormCooldownMinutes"), $CHAR(0))
    Kill ^Shutter.Config("stormCooldownMinutes")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Kill ^Hospital.Live
    Merge ^Hospital.Live = ..Saved
    If ..SavedCooldown = $CHAR(0) { Kill ^Shutter.Config("stormCooldownMinutes") } Else { Set ^Shutter.Config("stormCooldownMinutes") = ..SavedCooldown }
    Quit $$$OK
}

Method TestRefusal()
{
    Set setup = "Shutter.Setup", time = "Shutter.Util.Time"
    Set r = $CLASSMETHOD(setup, "StormRefusal", 0, "", 10)
    Do $$$AssertEquals(r.error _ "|" _ r.status, "live_off|409 Conflict", "the live hospital off")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(setup, "StormRefusal", 1, "", 10)), "live on and no storm ever: allowed")
    Set playing = {"stormId": "ST-000003", "state": "sending", "startedAt": ($CLASSMETHOD(time, "FromNow", -30)), "endsAt": ($CLASSMETHOD(time, "FromNow", 570))}
    Set r = $CLASSMETHOD(setup, "StormRefusal", 1, playing.%ToJSON(), 10)
    Do $$$AssertEquals(r.error _ "|" _ r.stormId _ "|" _ r.state, "storm_in_progress|ST-000003|sending", "a storm playing")
    Do $$$AssertEquals(r.endsAt, playing.endsAt, "with its end")
    Set playing.state = "releasing"
    Do $$$AssertEquals($CLASSMETHOD(setup, "StormRefusal", 1, playing.%ToJSON(), 10).error, "storm_in_progress", "releasing is still playing")
    // A storm still marked as playing after its span is over was cut off: it blocks nothing beyond the cooldown.
    Set cut = {"stormId": "ST-000002", "state": "waiting_receiver", "startedAt": ($CLASSMETHOD(time, "FromNow", -1300)), "endsAt": ($CLASSMETHOD(time, "FromNow", -700))}
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(setup, "StormRefusal", 1, cut.%ToJSON(), 10)), "a stale storm does not block")
    Set done = {"stormId": "ST-000003", "state": "done", "startedAt": ($CLASSMETHOD(time, "FromNow", -120))}
    Set r = $CLASSMETHOD(setup, "StormRefusal", 1, done.%ToJSON(), 10)
    Do $$$AssertEquals(r.error, "cooldown", "done two minutes ago: the cooldown")
    Do $$$AssertTrue((r.retryAfterSeconds > 470) && (r.retryAfterSeconds <= 480), "about eight minutes left: " _ r.retryAfterSeconds)
    Do $$$AssertEquals($EXTRACT(r.until, 1, 13), $EXTRACT($CLASSMETHOD(time, "FromNow", r.retryAfterSeconds), 1, 13), "until, the same hour")
    Set done.startedAt = $CLASSMETHOD(time, "FromNow", -1200)
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(setup, "StormRefusal", 1, done.%ToJSON(), 10)), "done twenty minutes ago: allowed")
    Set done.state = "failed", done.startedAt = $CLASSMETHOD(time, "FromNow", -120)
    Do $$$AssertEquals($CLASSMETHOD(setup, "StormRefusal", 1, done.%ToJSON(), 10).error, "cooldown", "a failed storm counts for the cooldown")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(setup, "StormRefusal", 1, done.%ToJSON(), 0)), "no cooldown, allowed at once")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(setup, "StormRefusal", 1, "not json", 10)), "an unreadable record refuses nothing")
}

Method TestCooldownSetting()
{
    Set setup = "Shutter.Setup"
    Do $$$AssertEquals($CLASSMETHOD(setup, "StormCooldownMinutes"), 10, "ten minutes by default")
    Set ^Shutter.Config("stormCooldownMinutes") = 0
    Do $$$AssertEquals($CLASSMETHOD(setup, "StormCooldownMinutes"), 0, "none when the site says so")
    Set ^Shutter.Config("stormCooldownMinutes") = 30
    Do $$$AssertEquals($CLASSMETHOD(setup, "StormCooldownMinutes"), 30, "half an hour")
    Set ^Shutter.Config("stormCooldownMinutes") = "soon"
    Do $$$AssertEquals($CLASSMETHOD(setup, "StormCooldownMinutes"), 10, "a bad value means the default")
    Set ^Shutter.Config("stormCooldownMinutes") = 2000
    Do $$$AssertEquals($CLASSMETHOD(setup, "StormCooldownMinutes"), 10, "and so does more than a day")
    Kill ^Shutter.Config("stormCooldownMinutes")
}

Method TestPlan()
{
    Kill ^Hospital.Live("bed"), ^Hospital.Live("adm")
    Set plan = ##class(Hospital.LivePlayer).StormPlan(7, "Europe/London")
    Do $$$AssertEquals(plan.patients.%Size(), 4, "four patients")
    Do $$$AssertEquals(plan.movements.%Size(), 8, "eight movements")
    Set controls = "", events = "", encs = ""
    Set mi = plan.movements.%GetIterator()
    While mi.%GetNext(.i, .m) {
        Set controls = controls _ $SELECT(controls = "": "", 1: ",") _ m.control, events = events _ $EXTRACT(m.event, 1)
        Set encs(m.encounterId) = $GET(encs(m.encounterId)) + 1
    }
    Do $$$AssertEquals(controls, "STORM7-01,STORM7-02,STORM7-03,STORM7-04,STORM7-05,STORM7-06,STORM7-07,STORM7-08", "the control ids")
    Do $$$AssertEquals(events, "aaaatttt", "admissions first, then the transfers")
    Set distinct = 0, e = "" For { Set e = $ORDER(encs(e)) Quit:e=""  Set distinct = distinct + 1 }
    Do $$$AssertEquals(distinct, 4, "two movements per encounter")
    Set pi = plan.patients.%GetIterator()
    While pi.%GetNext(.i, .p) {
        Do $$$AssertNotEquals(p.ward, p.toWard, "patient " _ p.mrn _ " moves to another ward (" _ p.ward _ " to " _ p.toWard _ ")")
        Do $$$AssertEquals(p.movements, 2, "two movements")
        Do $$$AssertTrue($DATA(^Hospital.Live("adm", p.mrn)) && ($LIST(^Hospital.Live("adm", p.mrn), 2) = p.toWard), "the ordinary feed knows the patient in the new ward")
    }
    Set transfer = plan.movements.%Get(4)
    Do $$$AssertEquals($PIECE(transfer.prior, "^", 1), plan.patients.%Get(0).ward, "the first transfer leaves the first admission's ward")
    Do $$$AssertEquals(transfer.ward, plan.patients.%Get(0).toWard, "for its new ward")
    // The text of a movement, as the player writes it at send time.
    Set p = ##class(Shutter.Util.LiveFeed).PatientNamed(transfer.mrn)
    Set text = ##class(Shutter.Util.LiveFeed).Adt("A02", transfer.control, "20261102020000", p, transfer.encounterId, transfer.ward, transfer.room, transfer.bed, transfer.prior, "20261102015900")
    Do $$$AssertTrue(text [ ("ADT^A02^ADT_A02|" _ transfer.control _ "|"), "an A02 with the control id")
    Do $$$AssertTrue(text [ ("PV1|1|I|" _ transfer.ward _ "^" _ transfer.room _ "^" _ transfer.bed _ "^HOSP|||" _ transfer.prior), "to the new bed from the old")
}

}
