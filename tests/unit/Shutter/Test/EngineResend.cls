/// Tier C: the approval's checks and run, the settings it binds, the declared duplicate, and a run that must not send.
/// The sends themselves are proven on the Pathology rig (O4.d, O5.c, O6, O7, O8).
Class Shutter.Test.EngineResend Extends %UnitTest.TestCase
{

Property Made As %String [ MultiDimensional ];

Method OnAfterOneTest(testname As %String) As %Status
{
    // The run's rows first, while their outage still exists to find them by: deleted after it, they stayed, and the patient
    // check's empty-ledger test read them.
    &sql(DELETE FROM Shutter_Store.ResendRecord WHERE RunId %STARTSWITH 'R' AND OutageId IN (SELECT ID FROM Shutter_Store.Outage WHERE Receiver = 'EngineResend Test'))
    Set class = ""
    For {
        Set class = $ORDER(..Made(class)) Quit:class=""
        Set id = "" For { Set id = $ORDER(..Made(class, id)) Quit:id=""  Do $CLASSMETHOD(class, "%DeleteId", id) }
    }
    Kill ..Made
    Quit $$$OK
}

/// A setting that moved, or reads unknown, stops a run; the same settings pass.
Method TestMoved()
{
    Set c = "Shutter.Operation.EngineResend", a = {"DefCharEncoding": "latin1", "IPAddress": "10.0.0.5", "Port": "7202"}
    Do $$$AssertEquals($CLASSMETHOD(c, "Moved", a, {}.%FromJSON(a.%ToJSON())), "", "the same")
    Do $$$AssertEquals($CLASSMETHOD(c, "Moved", a, {"DefCharEncoding": "latin1", "IPAddress": "10.0.0.5", "Port": "7203"}), "the operation's Port changed from 7202 to 7203", "a port")
    Do $$$AssertTrue($CLASSMETHOD(c, "Moved", a, {"DefCharEncoding": "unknown", "IPAddress": "10.0.0.5", "Port": "7202"}) [ "DefCharEncoding", "unknown moves")
}

/// The declared duplicate: ERR-3's code or the exact MSA-3 phrase, never a substring.
Method TestDeclared()
{
    Set c = "Shutter.Operation.EngineResend"
    Set reply = ##class(Shutter.Util.ReplyWords).FromLog("MSA|AE|T-1|ALREADY HELD ERR||OBR^1|205^Duplicate key identifier^HL70357")
    Do $$$AssertTrue($CLASSMETHOD(c, "Declared", reply, {"behaviour": "refuses", "code": "205"}), "the code")
    Do $$$AssertTrue($CLASSMETHOD(c, "Declared", reply, {"behaviour": "refuses", "phrase": "ALREADY HELD"}), "the phrase")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Declared", reply, {"behaviour": "refuses", "phrase": "ALREADY"}), "not a substring")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Declared", reply, {"behaviour": "refuses", "code": "207"}), "another code")
}

/// The approval: every check before anything is written, then the run's rows in order and the row sending.
Method TestApprove()
{
    Set api = "Shutter.API.Outages", o = ..Offered()
    Do $$$AssertEquals($CLASSMETHOD(api, "Approve", o, {"digest": "d1"}, "appr1", .reply), "400 Bad Request", "a note is required")
    Do $$$AssertEquals($CLASSMETHOD(api, "Approve", o, {"digest": "other", "note": "checked"}, "appr1", .reply), "409 Conflict", "another digest")
    Do $$$AssertEquals(reply.error, "set_changed", "set_changed")
    Do $$$AssertEquals($CLASSMETHOD(api, "Approve", o, {"digest": "d1", "note": "checked", "version": 99}, "appr1", .reply), "409 Conflict", "a stale version")
    Do o.Advance("offered", "", "unit", {"Approvable": 0})
    Do $$$AssertEquals($CLASSMETHOD(api, "Approve", o, {"digest": "d1", "note": "checked"}, "appr1", .reply), "409 Conflict", "not approvable")
    Do $$$AssertEquals(reply.error, "not_approvable", "not_approvable")
    Do o.Advance("offered", "", "unit", {"Approvable": 1})
    Do $$$AssertEquals($CLASSMETHOD(api, "Approve", o, {"digest": "d1", "note": "checked with the lab", "version": (o.Version)}, "appr1", .reply), "200 OK", "approved")
    Do $$$AssertEquals(reply.state, "sending", "the row reads sending")
    Do $$$AssertEquals(reply.approval.by _ "/" _ reply.approval.digest, "appr1/d1", "the approval names its person and digest")
    Do $$$AssertTrue(reply.approval.goodUntil ] reply.approval.givenAt, "two clocks")
    Set run = reply.approval.id, order = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT OriginHeaderId, State FROM Shutter_Store.ResendRecord WHERE RunId = ? ORDER BY Position", run)
    While rs.%Next() { Set order = order _ rs.%Get("OriginHeaderId") _ ":" _ rs.%Get("State") _ "," }
    Do $$$AssertEquals(order, "41:approved,44:approved,", "the run's rows in the set's order")
    Do $$$AssertEquals($CLASSMETHOD(api, "Approve", o, {"digest": "d1", "note": "again"}, "appr1", .reply), "409 Conflict", "one run at a time")
}

/// A run with a row left sending (a restart mid-call) sends nothing more and goes to a person; so does an approval that
/// expired before its first send.
Method TestRunThatMustNotSend()
{
    Set o = ..Offered()
    Do $$$AssertEquals(##class(Shutter.API.Outages).Approve(o, {"digest": "d1", "note": "checked"}, "appr1", .reply), "200 OK", "approved")
    Set run = reply.approval.id
    &sql(UPDATE Shutter_Store.ResendRecord SET State = 'sending' WHERE RunId = :run AND Position = 1)
    Do ##class(Shutter.Operation.EngineResend).Run(o)
    Do o.%Reload()
    Do $$$AssertEquals(o.State, "needs_person", "to a person")
    Do $$$AssertTrue(o.ToJSON().outcome [ "may have been sent" || (##class(Shutter.Store.OutageEvent).Of(o.%Id()).%ToJSON() [ "may have been sent"), "says what may have gone")
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.ResendRecord WHERE RunId = :run AND State = 'approved')
    Do $$$AssertEquals(n, 0, "nothing left to send")
    Set o = ..Offered()
    Do $$$AssertEquals(##class(Shutter.API.Outages).Approve(o, {"digest": "d1", "note": "checked"}, "appr1", .reply), "200 OK", "approved")
    Set a = {}.%FromJSON(o.Approval), a.goodUntil = "2020-01-01T00:00:00Z"
    Do o.Advance("sending", "", "unit", {"Approval": (a.%ToJSON())})
    Do ##class(Shutter.Operation.EngineResend).Run(o)
    Do o.%Reload()
    Do $$$AssertEquals(o.State, "needs_person", "an expired approval sends nothing")
    Do $$$AssertTrue(##class(Shutter.Store.OutageEvent).Of(o.%Id()).%ToJSON() [ "expired", "and says so")
}

/// An offered outage with a set of two, digest d1, approvable.
Method Offered() As Shutter.Store.Outage
{
    Do ##class(Shutter.Store.Outage).Open({"name": "EngineResend Test", "watch": {"namespace": ($NAMESPACE), "item": "EngineResend Test Out"}}, "cant_tell", "a test", "unit", .o)
    Set ..Made("Shutter.Store.Outage", o.%Id()) = ""
    Do o.Advance("offered", "listed", "unit", {"SetStatus": "computed", "SetDigest": "d1", "Approvable": 1, "ListOffered": [{"headerId": "41", "controlId": "CA"}, {"headerId": "44", "controlId": "CF"}]})
    Quit o
}

}
