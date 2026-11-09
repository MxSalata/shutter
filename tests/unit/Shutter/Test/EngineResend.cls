/// Tier C: the approval's checks and run, the settings it binds, the declared duplicate, and a run that must not send.
/// The sends themselves are proven on the Pathology rig (O4.d, O5.c, O6, O7, O8).
Class Shutter.Test.EngineResend Extends %UnitTest.TestCase
{

Property Made As %String [ MultiDimensional ];

/// The stored profile's text before a test added its receiver, put back after it.
Property ProfileBefore As %String(MAXLEN = "");

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
    &sql(DELETE FROM Shutter_Store.ResendRecord WHERE RunId %STARTSWITH 'H' AND Item = 'EngineResend Test Out')
    If ..ProfileBefore '= "" {
        Set row = ##class(Shutter.Store.SiteProfile).Row()
        If $ISOBJECT(row) Set row.Json = ..ProfileBefore Do row.%Save()
        Set ..ProfileBefore = ""
    }
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

/// The declared duplicate (v1.53): MSA-1 AE or AR, then ERR-3's code, or MSA-3 equal to the phrase or starting with it at a
/// word's end; never inside other words, in another case, or on an AA.
Method TestDeclared()
{
    Set c = "Shutter.Operation.EngineResend", d = {"behaviour": "refuses", "phrase": "ALREADY HELD"}
    Set rows = $LISTBUILD(
        $LISTBUILD("MSA|AE|T-1|ALREADY HELD", 1, "equal"),
        $LISTBUILD("MSA|AE|T-1|ALREADY HELD, entered by hand", 1, "the phrase then a comma"),
        $LISTBUILD("MSA|AE|T-1|ALREADY HELD by the laboratory", 1, "the phrase then a space"),
        $LISTBUILD("MSA|AR|T-1|  ALREADY HELD  ", 1, "AR, trimmed"),
        $LISTBUILD("MSA|AE|T-1|ALREADY HELDS", 0, "the phrase then a letter"),
        $LISTBUILD("MSA|AE|T-1|ALREADY HELD2", 0, "the phrase then a digit"),
        $LISTBUILD("MSA|AE|T-1|NOT ALREADY HELD", 0, "the phrase inside other words"),
        $LISTBUILD("MSA|AE|T-1|already held", 0, "another case"),
        $LISTBUILD("MSA|AA|T-1|ALREADY HELD", 0, "MSA-1 AA"),
        $LISTBUILD("MSA|CA|T-1|ALREADY HELD", 0, "MSA-1 CA"))
    For i = 1:1:$LISTLENGTH(rows) {
        Set r = $LIST(rows, i)
        Do $$$AssertEquals(''$CLASSMETHOD(c, "Declared", ##class(Shutter.Util.ReplyWords).FromLog($LIST(r, 1)), d), $LIST(r, 2), $LIST(r, 3))
    }
    Set reply = ##class(Shutter.Util.ReplyWords).FromLog("MSA|AE|T-1|ALREADY HELD ERR||OBR^1|205^Duplicate key identifier^HL70357")
    Do $$$AssertTrue($CLASSMETHOD(c, "Declared", reply, {"behaviour": "refuses", "code": "205"}), "the code")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Declared", reply, {"behaviour": "refuses", "code": "207"}), "another code")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Declared", reply, {"behaviour": "refuses", "phrase": "HELD"}), "a phrase that is not its start")
}

/// O8.c in process: the receiver's refusal of what it holds closes the row as already delivered, resolves the message's own
/// case with disposition already_delivered and the receiver's words, and the run goes on.
Method TestAlreadyHeldClosesTheCase()
{
    Do ..Receiver()
    Set origin = ..Origin("DA"), other = ..Origin("DB")
    Set c = ..CaseOf(origin, "ER-T-0001"), keep = ..CaseOf(other, "ER-T-0002")
    Set o = ..Offered(origin, other)
    Do $$$AssertEquals(##class(Shutter.API.Outages).Approve(o, {"digest": "d1", "note": "checked"}, "appr1", .reply), "200 OK", "approved")
    Set row = ..RunRow(reply.approval.id, 1)
    Set newId = ..Clone(origin, 5, "MSA|AE|DA|ALREADY HELD, entered by hand")
    Set row.State = "sending", row.NewHeaderId = newId, row.StartedAt = ##class(Shutter.Util.Time).NowUTC()
    Do row.%Save()
    Do $$$AssertEquals(##class(Shutter.Operation.EngineResend).Outcome(o, row, reply.approval, origin, newId, "Suspended", 30), "go", "the run goes on")
    Do row.%Reload()
    Do $$$AssertEquals(row.State, "closed_as_present", "the row closed as present")
    Do $$$AssertTrue(row.Words [ "(MSA-3: ALREADY HELD, entered by hand)", row.Words)
    Set case = ##class(Shutter.Store.Case).%OpenId(c)
    Do $$$AssertEquals(case.State _ "/" _ case.Disposition, "resolved/already_delivered", "the message's own case")
    Do $$$AssertTrue(case.Outcome [ "Already delivered: the receiver reported it already holds this message" && (case.Outcome [ "Shutter has not compared the stored result or amendment"), case.Outcome)
    Do $$$AssertEquals(##class(Shutter.Store.Case).%OpenId(keep).State, "escalated", "never another message's case")
    Set resends = ##class(Shutter.API.Outages).One(o).resends
    Do $$$AssertEquals(resends.%Get(0).closure _ "/" _ resends.%Get(0).controlId, "already_delivered/DA", "resends: " _ resends.%ToJSON())
}

/// O6.d in process: a resend that fails is shown failed, the rest stopped, the outage needs a person, and the message's
/// earlier case gains an event of kind resend with its state left as it is; resends on the outage and on the case.
Method TestFailedResendShown()
{
    Do ..Receiver()
    Set origin = ..Origin("FA"), other = ..Origin("FB")
    Set c = ..CaseOf(origin, "ER-T-0003")
    Set o = ..Offered(origin, other)
    Do $$$AssertEquals(##class(Shutter.API.Outages).Approve(o, {"digest": "d1", "note": "checked"}, "appr1", .reply), "200 OK", "approved")
    Set row = ..RunRow(reply.approval.id, 1)
    Set newId = ..Clone(origin, 5, "MSA|AE|FA|Refused by the application")
    Set row.State = "sending", row.NewHeaderId = newId, row.StartedAt = ##class(Shutter.Util.Time).NowUTC()
    Do row.%Save()
    Do $$$AssertEquals(##class(Shutter.Operation.EngineResend).Outcome(o, row, reply.approval, origin, newId, "Suspended", 30), "stop", "the run stops")
    Do row.%Reload()
    Do $$$AssertEquals(row.State, "failed", "the row failed")
    Do $$$AssertEquals(..RunRow(reply.approval.id, 2).State, "stopped", "the rest stopped")
    Do o.%Reload()
    Do $$$AssertEquals(o.State, "needs_person", "the outage waits for a person")
    Set case = ##class(Shutter.Store.Case).%OpenId(c)
    Do $$$AssertEquals(case.State, "escalated", "the case's state is left as it is")
    Set events = case.Events().%ToJSON()
    Do $$$AssertTrue(events [ """kind"":""resend""", "an event of kind resend: " _ events)
    Do $$$AssertTrue(events [ "Shutter's resend of this message failed at " && (events [ ("new header " _ newId _ " ended Suspended (the receiver answered AE: Refused by the application). Nothing more was sent; the outage waits for a person.")), events)
    Set resends = ##class(Shutter.API.Outages).One(o).resends
    Do $$$AssertEquals(resends.%Size(), 2, "both rows on the outage")
    Do $$$AssertEquals(resends.%Get(0).state _ "/" _ resends.%Get(0).closure _ "/" _ resends.%Get(0).newHeaderId, "failed/failed/" _ newId, resends.%ToJSON())
    Do $$$AssertEquals(resends.%Get(1).state, "stopped", "the second stopped")
    Do $$$AssertEquals(resends.%Get(1).%GetTypeOf("closure"), "null", "closure null while stopped")
    Set onCase = ##class(Shutter.Store.ResendRecord).OfHeader($NAMESPACE, origin)
    Do $$$AssertEquals(onCase.%Size() _ "/" _ onCase.%Get(0).state, "1/failed", "the case's resends: the rows on its origin")
}

/// An approval, then the choice "already handled by hand" for one of its messages: the recheck stops on it and nothing is
/// sent.
Method TestHandledByHandNotSent()
{
    Do ..Receiver()
    Set origin = ..Origin("HA"), other = ..Origin("HB")
    Set o = ..Offered(origin, other)
    Do $$$AssertEquals(##class(Shutter.API.Outages).Approve(o, {"digest": "d1", "note": "checked"}, "appr1", .reply), "200 OK", "approved")
    Set h = ##class(Shutter.Store.ResendRecord).%New()
    Set h.RunId = "H" _ o.%Id(), h.OutageId = o.%Id(), h.Namespace = $NAMESPACE, h.Item = ..#ITEM, h.OriginHeaderId = origin, h.State = "handled_by_hand", h.RecordedBy = "appr2", h.EndedAt = ##class(Shutter.Util.Time).NowUTC()
    Do $$$AssertStatusOK(h.%Save(), "the hand closure")
    Set check = ##class(Shutter.Operation.EngineResend).Recheck($NAMESPACE, ..#ITEM, origin, ..#RECEIVER, "", $LISTBUILD(origin, other))
    Do $$$AssertEquals(check.verdict, "stop", "the recheck stops on it")
    Do $$$AssertTrue(check.why [ ("header " _ origin _ " no longer qualifies: handled by hand, recorded by appr2"), check.why)
    Do $$$AssertEquals(..RunRow(reply.approval.id, 1).NewHeaderId, "", "nothing was sent")
}

/// The test receiver in the stored profile, refusing duplicates with the phrase ALREADY HELD (put back after the test).
Method Receiver()
{
    Set sp = "Shutter.Store.SiteProfile"
    Set row = $CLASSMETHOD(sp, "Row")
    If '$ISOBJECT(row) {
        Do $CLASSMETHOD(sp, "Store", $CLASSMETHOD(sp, "Default").%ToJSON(), "test", "test", "", .v)
        Set row = $CLASSMETHOD(sp, "Row")
    }
    Set:..ProfileBefore="" ..ProfileBefore = row.Json
    Set p = {}.%FromJSON(row.Json)
    If '$ISOBJECT(p.receivers) Set p.receivers = []
    Do p.receivers.%Push({"name": (..#RECEIVER), "category": "orders_results", "duplicates": {"behaviour": "refuses", "phrase": "ALREADY HELD"}})
    Set row.Json = p.%ToJSON()
    Do $$$AssertStatusOK(row.%Save(), "the receiver is in the stored profile")
}

/// A failed origin header to the test item, its own session, with a never-opened log row.
Method Origin(control As %String) As %String
{
    Set cr = $CHAR(13)
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\&|FAKESEND|SITE|FAKELIMS|LAB|20261105100000||ORU^R01|" _ control _ "|P|2.5.1" _ cr _ "PID|1||999000" _ $INCREMENT(^||EngineResendTest) _ "^^^NHS^NH||Testpatient^Alpha" _ cr _ "ORC|RE|" _ control _ cr _ "OBR|1|" _ control _ "||PANEL1" _ cr _ "OBX|1|ST|TST01||VAL10|||||F", .sc)
    Set msg.DocType = "2.5.1:ORU_R01"
    Do msg.%Save()
    Set ..Made("EnsLib.HL7.Message", msg.%Id()) = ""
    Set id = ..Hdr(msg.%Id(), 8, "")
    Do ..Log(id, "ERROR <Ens>ErrOutConnectExpired: TCP Connect timeout period (5) expired for 127.0.0.1:7202")
    Quit id
}

/// Shutter's clone of an origin in its session, status as given, with the receiver's reply logged.
Method Clone(origin As %String, status As %Integer, reply As %String) As %String
{
    Set o = ##class(Ens.MessageHeader).%OpenId(origin)
    Set id = ..Hdr(o.MessageBodyId, status, o.SessionId)
    Do ..Log(id, "ERROR <Ens>ErrGeneral: response " _ reply)
    Quit id
}

Method Hdr(bodyId As %String, status As %Integer, session As %String) As %String
{
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.TargetConfigName = ..#ITEM, h.SourceConfigName = "EngineResend Test In", h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = bodyId
    Set h.Status = status, h.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3), h.Type = 1
    Do h.%Save()
    Set:session="" session = h.%Id()
    Set h.SessionId = session
    Do h.%Save()
    Set ..Made("Ens.MessageHeader", h.%Id()) = ""
    Quit h.%Id()
}

Method Log(headerId As %String, words As %String)
{
    Set h = ##class(Ens.MessageHeader).%OpenId(headerId)
    Set row = ##class(Ens.Util.Log).%New()
    Set row.Type = 2, row.Text = words, row.SessionId = h.SessionId, row.MessageId = headerId, row.ConfigName = ..#ITEM, row.TimeLogged = $ZDATETIME($ZTIMESTAMP, 3, 1, 3), row.SourceClass = "EnsLib.HL7.Operation.TCPOperation", row.SourceMethod = "OnMessage"
    Do row.%Save()
    Set ..Made("Ens.Util.Log", row.%Id()) = ""
}

/// An escalated case on the origin header of this namespace.
Method CaseOf(origin As %String, caseId As %String) As %String
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = caseId, c.OperationKey = "LAB^NHS^999000^^result^2026-11-09T08:00:00Z", c.Receiver = ..#RECEIVER
    Set c.FailureKind = "delivery_failed", c.State = "escalated", c.OpenedAt = "2026-11-09T08:00:00Z"
    Set c.SourceNamespace = $NAMESPACE, c.OriginHeaderId = origin
    Do c.%Save()
    Set ..Made("Shutter.Store.Case", c.%Id()) = ""
    Quit c.%Id()
}

/// The run's row at a position.
ClassMethod RunRow(runId As %String, position As %Integer) As Shutter.Store.ResendRecord
{
    &sql(SELECT ID INTO :id FROM Shutter_Store.ResendRecord WHERE RunId = :runId AND Position = :position)
    Quit $SELECT(SQLCODE = 0: ##class(Shutter.Store.ResendRecord).%OpenId(id), 1: "")
}

/// The approval: every check before anything is written, then the run's rows in order and the row sending.
Method TestApprove()
{
    Do ..Receiver()
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
    Do ..Receiver()
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

/// An offered outage with a set of two (headers 41 and 44, or the two given), digest d1, approvable.
Method Offered(a As %String = "41", b As %String = "44") As Shutter.Store.Outage
{
    Do ##class(Shutter.Store.Outage).Open({"name": (..#RECEIVER), "watch": {"namespace": ($NAMESPACE), "item": (..#ITEM)}}, "cant_tell", "a test", "unit", .o)
    Set ..Made("Shutter.Store.Outage", o.%Id()) = ""
    Set ca = $SELECT(a = "41": "CA", 1: ..ControlOf(a)), cb = $SELECT(b = "44": "CF", 1: ..ControlOf(b))
    Do o.Advance("offered", "listed", "unit", {"SetStatus": "computed", "SetDigest": "d1", "Approvable": 1, "ListOffered": [{"headerId": (a), "controlId": (ca)}, {"headerId": (b), "controlId": (cb)}]})
    Quit o
}

ClassMethod ControlOf(headerId As %String) As %String
{
    Set msg = ##class(Shutter.Util.MessageCopy).Of($NAMESPACE, headerId)
    Quit $SELECT($ISOBJECT(msg): msg.GetValueAt("MSH:10"), 1: "")
}

Parameter RECEIVER = "EngineResend Test";

Parameter ITEM = "EngineResend Test Out";

}
