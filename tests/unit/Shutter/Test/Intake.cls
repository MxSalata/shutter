/// Case Intake's first step (v1.53, CONTRACTS 11): Shutter's own resend opens no case. A forward naming a clone one of
/// Shutter's runs made, or an origin with a ledger row that has started, is answered as taken, with the message's earlier
/// case when it has one, and the engine's words go on that case, or on the outage as an alert line. The headers are ids
/// of a made-up namespace; the ledger rows, cases and outages are made here and removed after each test.
Class Shutter.Test.Intake Extends %UnitTest.TestCase
{

Parameter NS = "INTAKETEST";

Property Made As %String [ MultiDimensional ];

Method OnAfterOneTest(testname As %String) As %Status
{
    Set class = ""
    For {
        Set class = $ORDER(..Made(class)) Quit:class=""
        Set id = "" For { Set id = $ORDER(..Made(class, id)) Quit:id=""  Do $CLASSMETHOD(class, "%DeleteId", id) }
    }
    Kill ..Made
    Quit $$$OK
}

/// A forward naming Shutter's clone, and one naming an origin with a started row: no case, an event on the earlier case;
/// with no case, an alert line on the outage; a header no run touched goes on to the intake as before.
Method TestOwnCloneOpensNoCase()
{
    Set intake = "Shutter.Process.Intake"
    Do ##class(Shutter.Store.Outage).Open({"name": ("Intake Test " _ $JOB), "watch": {"namespace": (..#NS), "item": "Intake Test Out"}}, "cant_tell", "a test", "unit", .o)
    Set ..Made("Shutter.Store.Outage", o.%Id()) = ""
    Set run = ..Row(o.%Id(), 990000501, 990000601, "C-INTAKE-T1")
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "C-INTAKE-T1", c.OperationKey = "LAB^NHS^999000^^result^2026-11-09T08:00:00Z", c.Receiver = "Intake Test", c.FailureKind = "delivery_failed", c.State = "escalated", c.OpenedAt = "2026-11-09T08:00:00Z", c.SourceNamespace = ..#NS, c.OriginHeaderId = 990000501
    Do $$$AssertStatusOK(c.%Save(), "the message's earlier case")
    Set ..Made("Shutter.Store.Case", c.%Id()) = ""
    Set before = ..Count()
    // The engine's alert on the clone.
    Set answer = $CLASSMETHOD(intake, "OwnResend", ..Request(990000601, "Alert from Intake Test Out: ERROR <Ens>ErrGeneral: response AE"))
    Do $$$AssertTrue($ISOBJECT(answer), "answered")
    Do $$$AssertEquals(answer.CaseId _ "/" _ answer.Opened _ "/" _ answer.OwnResend _ "/" _ answer.State, "C-INTAKE-T1/0/1/escalated", "the earlier case, nothing opened")
    Do $$$AssertEquals(..Count(), before, "no case opened")
    Set events = c.Events().%ToJSON()
    Do $$$AssertTrue(events [ """kind"":""resend""" && (events [ "the engine alerted on Shutter's resend of this message (header 990000601): Alert from Intake Test Out"), events)
    Do c.%Reload()
    Do $$$AssertEquals(c.State, "escalated", "the case's state as it was")
    // The origin, with a row that has started.
    Set answer = $CLASSMETHOD(intake, "OwnResend", ..Request(990000501, "Alert from Intake Test Out: ERROR"))
    Do $$$AssertTrue($ISOBJECT(answer) && (answer.CaseId = "C-INTAKE-T1"), "the origin with a started row is answered the same")
    // No case: the outage's alert line.
    Do ..Row(o.%Id(), 990000502, 990000602, "")
    Set answer = $CLASSMETHOD(intake, "OwnResend", ..Request(990000602, "Alert from Intake Test Out: ERROR"))
    Do $$$AssertTrue($ISOBJECT(answer) && (answer.CaseId = "") && answer.OwnResend, "no case, still taken")
    Do o.%Reload()
    Set alerts = o.GetList("Alerts").%ToJSON()
    Do $$$AssertTrue(alerts [ """kind"":""resend""" && (alerts [ "the engine alerted on Shutter's resend"), "an alert line on the outage: " _ alerts)
    // A header no run touched, and an origin whose row has not started.
    Do $$$AssertEquals($CLASSMETHOD(intake, "OwnResend", ..Request(990000599, "x")), "", "any other header goes on to the intake")
    Set r = ..Row(o.%Id(), 990000503, "", "")
    Set row = ##class(Shutter.Store.ResendRecord).%OpenId(r)
    Set row.StartedAt = "", row.State = "approved"
    Do row.%Save()
    Do $$$AssertEquals($CLASSMETHOD(intake, "OwnResend", ..Request(990000503, "x")), "", "an origin approved and not started goes on to the intake")
}

/// A ledger row of a run on the outage: origin, the clone it made, the case.
Method Row(outageId As %String, origin As %String, clone As %String, caseId As %String) As %String
{
    Set r = ##class(Shutter.Store.ResendRecord).%New()
    Set r.RunId = "R" _ outageId _ "-1", r.Position = 1, r.OutageId = outageId, r.Namespace = ..#NS, r.Item = "Intake Test Out", r.OriginHeaderId = origin, r.NewHeaderId = clone, r.CaseId = caseId
    Set r.State = "failed", r.StartedAt = "2026-11-09T03:20:00Z", r.EndedAt = "2026-11-09T03:20:30Z"
    Do $$$AssertStatusOK(r.%Save(), "a ledger row")
    Set ..Made("Shutter.Store.ResendRecord", r.%Id()) = ""
    Quit r.%Id()
}

Method Request(header As %String, text As %String) As Shutter.Msg.ExternalIntake
{
    Set q = ##class(Shutter.Msg.ExternalIntake).%New()
    Set q.SourceNamespace = ..#NS, q.OriginHeaderId = header, q.FailureKind = "delivery_failed", q.FailureText = text, q.Receiver = "Intake Test"
    Quit q
}

ClassMethod Count() As %Integer
{
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store."Case")
    Quit +n
}

}
