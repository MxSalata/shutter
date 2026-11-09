/// The Doctor and the health route tell the truth about a dead receiver (Shutter.Util.ReceiverHealth; CONTRACTS 12): each state
/// from a reading, the overall answer, the Doctor's keys, a result that made no call and a case with no reading, and what
/// an alert intake disabled or replaced does to a watched namespace (Shutter.Util.Onboard.IntakeProblems).
Class Shutter.Test.ReceiverHealth Extends %UnitTest.TestCase
{

Method TestEachStateFromAReading()
{
    Set c = "Shutter.Util.ReceiverHealth", t = "2026-11-06T14:00:00Z", later = "2026-11-06T14:05:00Z"
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 1, t, 0, "", 0), "no_answer", "nobody answered: no answer")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 1, t, 503, "", 0), "server_error", "a 503 is the receiver failing")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 1, t, 500, "", 0), "server_error", "and a 500")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 1, t, 401, "", 0), "refused", "a 401 is a refused sign-in")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 1, t, 403, "", 0), "refused", "and a 403")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 1, t, 200, "", 0), "answering", "a 200 answered")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 1, t, 404, "", 0), "answering", "a 404 for an unknown encounter came from a live receiver")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 1, t, 409, "", 0), "answering", "and a 409")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 1, t, 200, later, 1), "failing", "a delivery that failed after the newest answer outweighs it")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 1, later, 200, t, 1), "answering", "and one before the newest answer does not")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 1, "", "", "", 0), "not_read", "a receiver with an API nothing has read")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 0, "", "", "", 0), "no_api", "one with no API, nothing failing")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 0, "", "", t, 3), "failing", "one with no API and failures in the last hour")
    Do $$$AssertEquals($CLASSMETHOD(c, "Judge", 0, "", "", t, 0), "no_api", "and failures older than that are history")
}

Method TestTheOverallAnswer()
{
    Set c = "Shutter.Util.ReceiverHealth"
    Do $$$AssertEquals($CLASSMETHOD(c, "Overall", $LISTBUILD("answering", "not_read")), 1, "one answered, none in trouble")
    Do $$$AssertEquals($CLASSMETHOD(c, "Overall", $LISTBUILD("answering", "no_answer")), 0, "one dead is enough")
    For state = "server_error", "refused", "failing" { Do $$$AssertEquals($CLASSMETHOD(c, "Overall", $LISTBUILD(state)), 0, state _ " is trouble") }
    Do $$$AssertEquals($CLASSMETHOD(c, "Overall", $LISTBUILD("not_read", "no_api")), "", "nothing read: not known, never all clear")
    Do $$$AssertEquals($CLASSMETHOD(c, "Overall", ""), "", "no receivers: not known")
}

Method TestAllWellReadsTheNamespaces()
{
    Set c = "Shutter.Util.ReceiverHealth"
    Do $$$AssertEquals($CLASSMETHOD(c, "AllWell", ""), 1, "none watched")
    Do $$$AssertEquals($CLASSMETHOD(c, "AllWell", [{"ok": true}, {"ok": true}]), 1, "all well")
    Do $$$AssertEquals($CLASSMETHOD(c, "AllWell", [{"ok": true}, {"ok": false}]), 0, "one with a problem")
}

/// The whole route on this instance's store: a made-up receiver, a dead reading in its evidence and then an answer.
Method TestAReadingOnTheStore()
{
    Set c = "Shutter.Util.ReceiverHealth", name = "ReceiverHealthTest Out"
    Set one = $CLASSMETHOD(c, "Receiver", name, 1)
    Do $$$AssertEquals(one.state, "not_read", "nothing has read it: " _ one.%ToJSON())
    Do $$$AssertEquals(one.%GetTypeOf("http_status"), "null", "with no status")
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "C-RH" _ $JOB, case.Receiver = name, case.State = "blocked", case.OpenedAt = "2026-11-06T10:00:00Z", case.EncounterId = "RH", case.OperationKey = "RH" _ $JOB
    Set sc = case.%Save()
    Do $$$AssertStatusOK(sc, "a case for it")
    Quit:$$$ISERR(sc)
    Set snap = ##class(Shutter.Store.Snapshot).%New()
    Set snap.Case = case, snap.Seq = 1, snap.TakenAt = "2026-11-06T10:00:00Z"
    Do $$$AssertStatusOK(snap.%Save(), "its snapshot")
    Try {
        Do $$$AssertStatusOK(..Item(snap, 1, "2026-11-06T10:00:01Z", {"http_status": 0, "body": {"error": "ERROR #6059: Unable to open TCP/IP socket"}}), "a read nobody answered")
        Set one = $CLASSMETHOD(c, "Receiver", name, 1)
        Do $$$AssertEquals(one.state, "no_answer", "reads as no answer: " _ one.%ToJSON())
        Do $$$AssertEquals(one.from, "evidence", "from the evidence")
        Do $$$AssertEquals(one."http_status", 0, "status 0")
        Do $$$AssertTrue(one.error [ "6059", "with the error")
        Do $$$AssertEquals(one.at, "2026-11-06T10:00:01Z", "and its time")
        Do $$$AssertEquals(one."last_answer_at", "", "and no answer on record")
        Set snap2 = ##class(Shutter.Store.Snapshot).%New()
        Set snap2.Case = case, snap2.Seq = 2, snap2.TakenAt = "2026-11-06T10:05:00Z"
        Do $$$AssertStatusOK(snap2.%Save(), "a later snapshot")
        Do $$$AssertStatusOK(..Item(snap2, 1, "2026-11-06T10:05:01Z", {"http_status": 200, "body": {"state": "secret-bed"}}), "a read that was answered")
        Set one = $CLASSMETHOD(c, "Receiver", name, 1)
        Do $$$AssertEquals(one.state, "answering", "the newest reading wins: " _ one.%ToJSON())
        Do $$$AssertEquals(one."last_answer_at", "2026-11-06T10:05:01Z", "and it is the last answer")
        Do $$$AssertTrue(one.%ToJSON() '[ "secret-bed", "the receiver's body goes no further")
        Set case.FailureKind = "delivery_failed", case.OpenedAt = "2026-11-06T10:06:00Z"
        Do $$$AssertStatusOK(case.%Save(), "a delivery fails after it")
        Set one = $CLASSMETHOD(c, "Receiver", name, 1)
        Do $$$AssertEquals(one.state, "failing", "failing since its last answer: " _ one.%ToJSON())
    } Catch ex {
        Do $$$AssertTrue(0, "threw: " _ ex.DisplayString())
    }
    Set id = case.%Id()
    &sql(DELETE FROM Shutter_Store.SnapshotItem WHERE Snapshot IN (SELECT ID FROM Shutter_Store.Snapshot WHERE "Case" = :id))
    &sql(DELETE FROM Shutter_Store.Snapshot WHERE "Case" = :id)
    Do ##class(Shutter.Store.Case).%DeleteId(id)
}

Method Item(snap As Shutter.Store.Snapshot, seq As %Integer, at As %String, data As %DynamicObject) As %Status [ Private ]
{
    Set item = ##class(Shutter.Store.SnapshotItem).%New()
    Set item.Snapshot = snap, item.Seq = seq, item.Kind = "ward_state", item.Source = "ward_api", item.ObservedAt = at, item.Json = data.%ToJSON()
    Quit item.%Save()
}

/// The Doctor carries the keys, and the health route's ok stays the production's.
Method TestTheDoctorCarriesThem()
{
    Set r = ##class(%DynamicObject).%FromJSON(##class(Shutter.Setup).Doctor())
    Do $$$AssertTrue(r.%IsDefined("receivers") && r.receivers.%IsA("%DynamicArray"), "the receivers")
    Do $$$AssertTrue(r.%IsDefined("receivers_ok"), "whether they answer")
    Do $$$AssertTrue($LISTFIND($LISTBUILD("boolean", "null"), r.%GetTypeOf("receivers_ok")) > 0, "true, false or null: " _ r.%GetTypeOf("receivers_ok"))
    Do $$$AssertEquals(r."receivers_state", "read", "the reading itself worked")
    Do $$$AssertEquals(r.%GetTypeOf("watched_ok"), "boolean", "and whether the watched namespaces are well")
    Set it = r.receivers.%GetIterator()
    While it.%GetNext(, .one) { Do $$$AssertTrue(one.%IsDefined("state") && one.%IsDefined("at") && one.%IsDefined("has_api"), "each says how it stands: " _ one.name) }
}

/// EC-126 in the watched namespaces' report: the intake disabled, replaced or gone, and the forwarder disabled.
Method TestAnIntakeThatCannotHear()
{
    Set c = "Shutter.Util.Onboard"
    Set f = {"item": "Shutter Forwarder", "enabled": true}, off = {"item": "Shutter Forwarder", "enabled": false}
    Set a = {"item": "Ens.Alert", "class": "Shutter.Intake.AlertProcess", "is_shutter": true, "enabled": true}
    Set p = $CLASSMETHOD(c, "IntakeProblems", 1, "P", f, a)
    Do $$$AssertEquals(p.%Size(), 0, "wired and enabled: no problem: " _ p.%ToJSON())
    Set a.enabled = 0
    Set p = $CLASSMETHOD(c, "IntakeProblems", 1, "P", f, a)
    Do $$$AssertTrue((p.%Size() = 1) && (p.%Get(0) [ "disabled"), "a disabled intake is a problem: " _ p.%ToJSON())
    Set mine = {"item": "Ens.Alert", "class": "Site.AlertRouter", "is_shutter": false, "enabled": true}
    Set p = $CLASSMETHOD(c, "IntakeProblems", 1, "P", f, mine)
    Do $$$AssertTrue((p.%Size() = 1) && (p.%Get(0) [ "Site.AlertRouter"), "a replaced intake is one, by the class it found: " _ p.%ToJSON())
    Set p = $CLASSMETHOD(c, "IntakeProblems", 1, "P", f, "")
    Do $$$AssertTrue((p.%Size() = 1) && (p.%Get(0) [ "No alert intake"), "and a missing one: " _ p.%ToJSON())
    Set a.enabled = 1
    Set p = $CLASSMETHOD(c, "IntakeProblems", 1, "P", off, a)
    Do $$$AssertTrue((p.%Size() = 1) && (p.%Get(0) [ "forwarder"), "a disabled forwarder too: " _ p.%ToJSON())
    // A namespace a case names but nobody onboarded has its own way of reporting: no intake is no fault of its.
    Set p = $CLASSMETHOD(c, "IntakeProblems", 0, "P", f, "")
    Do $$$AssertEquals(p.%Size(), 0, "not onboarded, no intake: nothing to say")
    Set p = $CLASSMETHOD(c, "IntakeProblems", 0, "P", "", mine)
    Do $$$AssertEquals(p.%Size(), 0, "not onboarded, the site's own consumer: nothing to say")
    Set a.enabled = 0
    Set p = $CLASSMETHOD(c, "IntakeProblems", 0, "P", f, a)
    Do $$$AssertEquals(p.%Size(), 1, "but Shutter's intake disabled is a problem wherever it is")
}

}
