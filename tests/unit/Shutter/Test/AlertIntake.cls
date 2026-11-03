/// The alert intake (Shutter.Intake.AlertProcess; CONTRACTS 11, v1.35): which alerts it takes, how it reads the failure
/// from an alert's words, the session's HL7 header, the forward it builds, and the once-per-session marks: pending while
/// the forward is out, seen once Shutter took the message.
Class Shutter.Test.AlertIntake Extends %UnitTest.TestCase
{

Method OnAfterAllTests() As %Status
{
    Kill ^Shutter.AlertIntake("seen", 999999991), ^Shutter.AlertIntake("seen", 999999992), ^Shutter.AlertIntake("seen", 999999993)
    Kill ^Shutter.AlertIntake("pending", 999999993), ^Shutter.AlertIntake("pending", 999999994), ^Shutter.AlertIntake("pending", 999999995)
    Quit $$$OK
}

Method TestTakes()
{
    Set ap = "Shutter.Intake.AlertProcess"
    Do $$$AssertTrue($CLASSMETHOD(ap, "Takes", "Downstream Out", ""), "no list takes any item")
    Do $$$AssertTrue($CLASSMETHOD(ap, "Takes", "Downstream Out", "Downstream Out"), "the listed item")
    Do $$$AssertTrue($CLASSMETHOD(ap, "Takes", "Records Out", "Downstream Out, Records Out"), "one of several, spaces allowed")
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "Takes", "PAS to Downstream", "Downstream Out, Records Out"), "an item outside the list is passed on only")
}

Method TestClassify()
{
    Set ap = "Shutter.Intake.AlertProcess"
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "ERROR <Ens>ErrHTTPStatus: Received non-OK status 503 from remote HTTP server: 'HTTP/1.1 503 Service Unavailable'"), "delivery_failed", "a 503 is a failed delivery")
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "ERROR <Ens>ErrOutConnectionLost: Lost TCP connection; no response received"), "uncertain_outcome", "no response is uncertain")
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "Response timeout after 15 seconds"), "uncertain_outcome", "a timeout is uncertain")
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "Application reject: AR MSA-1 received"), "rejected", "a reject is a rejection")
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "Received HTTP 422 from the ward system"), "rejected", "a 4xx is a rejection")
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "Something broke"), "delivery_failed", "anything else is a failed delivery")
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "ERROR <Ens>ErrOutConnectFailed: HTTP Connect failed for ward:8080 - Connection refused"), "delivery_failed", "a connection refused is no rejection: nothing was sent")
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "Refused by the receiving service: the message does not validate"), "rejected", "refused by the receiver is a rejection")
    Do $$$AssertEquals($CLASSMETHOD(ap, "HttpStatusIn", "Received non-OK status 503 from remote HTTP server: 'HTTP/1.1 503 Service Unavailable'"), "503", "the HTTP status from the text")
    Do $$$AssertEquals($CLASSMETHOD(ap, "HttpStatusIn", "Received http 422 from the ward system"), "422", "any case")
    Do $$$AssertEquals($CLASSMETHOD(ap, "HttpStatusIn", "'HTTP/1.1 503 Service Unavailable'"), "503", "the status line's form")
    Do $$$AssertEquals($CLASSMETHOD(ap, "HttpStatusIn", "status 2026 is not one"), "", "four digits are not a status")
    Do $$$AssertEquals($CLASSMETHOD(ap, "HttpStatusIn", "Lost TCP connection"), "", "none named")
}

Method TestForwardFromAlert()
{
    Set ap = "Shutter.Intake.AlertProcess"
    // A real HL7 header of this namespace, when the instance has one (the feed's or an intake's); the forward names it.
    Set hid = ""
    &sql(SELECT TOP 1 ID INTO :hid FROM Ens.MessageHeader WHERE MessageBodyClassName = 'EnsLib.HL7.Message' ORDER BY ID DESC)
    If (SQLCODE '= 0) || (hid = "") {
        Do $$$AssertTrue(1, "no HL7 message header on this instance yet: the forward's fields are checked with an unsaved header")
        Set header = ##class(Ens.MessageHeader).%New()
        Set header.SourceConfigName = "PAS In"
    } Else {
        Set header = ##class(Ens.MessageHeader).%OpenId(hid)
        Set found = $CLASSMETHOD(ap, "HL7HeaderOfSession", header.SessionId, .problem)
        Do $$$AssertTrue($ISOBJECT(found), "the session's HL7 header is found: " _ problem)
        If $ISOBJECT(found) Do $$$AssertEquals(found.SessionId, header.SessionId, "in the same session")
        If $ISOBJECT(found) Do $$$AssertTrue($CLASSMETHOD(found.MessageBodyClassName, "%Extends", "EnsLib.HL7.Message"), "with an HL7 body")
    }
    Set none = $CLASSMETHOD(ap, "HL7HeaderOfSession", "", .problem)
    Do $$$AssertNotTrue($ISOBJECT(none), "no session, no header")
    Do $$$AssertEquals(problem, "no session", "and the problem says so")
    Set none = $CLASSMETHOD(ap, "HL7HeaderOfSession", 999999999, .problem)
    Do $$$AssertNotTrue($ISOBJECT(none), "an unknown session, no header")
    Do $$$AssertEquals(problem, "no HL7 message in session 999999999", "and the problem says so")
    Set alert = ##class(Ens.AlertRequest).%New()
    Set alert.SourceConfigName = "Downstream Out", alert.AlertText = "ERROR <Ens>ErrHTTPStatus: Received non-OK status 503 from remote HTTP server", alert.SessionId = 12345
    Set alert.AlertTime = $ZDATETIMEH("2026-11-02 01:50:00", 3)
    Set f = $CLASSMETHOD(ap, "ForwardFromAlert", alert, header, "Downstream Out")
    Do $$$AssertEquals(f.HeaderId, header.%Id(), "the header's id")
    Do $$$AssertEquals(f.Route, header.SourceConfigName, "the header's service as the route")
    Do $$$AssertEquals(f.Receiver, "Downstream Out", "the alerting item as the receiver")
    Do $$$AssertEquals(f.FailureKind _ "|" _ f.FailureOutcome _ "|" _ f.FailureHttpStatus _ "|" _ f.FailureReasonCode, "delivery_failed|error|503|alert", "the failure from the words")
    Do $$$AssertEquals($EXTRACT(f.FailureText, 1, 53), "Alert from Downstream Out at 2026-11-02 01:50:00 UTC:", "the text names the item and the time")
    Do $$$AssertTrue(f.FailureText [ "Received non-OK status 503", "and carries the alert's words")
    // The engine's own AlertTime is a UTC timestamp string, which once read as a $HOROLOG day (1846-07-19).
    Set alert.AlertTime = "2026-11-02 19:39:34.123"
    Set f = $CLASSMETHOD(ap, "ForwardFromAlert", alert, header, "Downstream Out")
    Do $$$AssertEquals($EXTRACT(f.FailureText, 1, 53), "Alert from Downstream Out at 2026-11-02 19:39:34 UTC:", "a timestamp string reads as itself, to the second")
    Set alert.AlertText = "Response timeout after 15 seconds", alert.AlertTime = ""
    Set f = $CLASSMETHOD(ap, "ForwardFromAlert", alert, header, "Downstream Out")
    Do $$$AssertEquals(f.FailureKind _ "|" _ f.FailureOutcome _ "|" _ f.FailureHttpStatus, "uncertain_outcome|uncertain|", "a timeout: uncertain, no status")
    Do $$$AssertEquals($EXTRACT(f.FailureText, 1, 27), "Alert from Downstream Out: ", "no time, no 'at'")
}

Method TestSeenOnce()
{
    Set ap = "Shutter.Intake.AlertProcess"
    Kill ^Shutter.AlertIntake("seen", 999999991), ^Shutter.AlertIntake("seen", 999999992)
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "Seen", 999999991), "not seen yet")
    Do $CLASSMETHOD(ap, "MarkSeen", 999999991, "Downstream Out")
    Do $$$AssertTrue($CLASSMETHOD(ap, "Seen", 999999991), "seen once marked")
    Do $$$AssertEquals($LISTGET(^Shutter.AlertIntake("seen", 999999991), 1), "Downstream Out", "with the item")
    // An entry older than a day is dropped by the next mark.
    Set ^Shutter.AlertIntake("seen", 999999990) = $LISTBUILD("old", 0)
    Do $CLASSMETHOD(ap, "MarkSeen", 999999992, "Downstream Out")
    Do $$$AssertEquals($DATA(^Shutter.AlertIntake("seen", 999999990)), 0, "the old entry is gone")
    Do $$$AssertTrue($CLASSMETHOD(ap, "Seen", 999999991) && $CLASSMETHOD(ap, "Seen", 999999992), "the fresh ones stay")
}

/// A forward Shutter refused leaves the session forwardable: only an answer without Error marks it seen.
Method TestRefusedForwardIsNotSeen()
{
    Set ap = "Shutter.Intake.AlertProcess"
    Kill ^Shutter.AlertIntake("seen", 999999993), ^Shutter.AlertIntake("pending", 999999993)
    Do $CLASSMETHOD(ap, "MarkPending", 999999993, "Downstream Out")
    Do $$$AssertTrue($CLASSMETHOD(ap, "Pending", 999999993), "pending while the forward is out")
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "Seen", 999999993), "but not seen before Shutter answers")
    Set refused = ##class(Shutter.Intake.Forwarded).%New()
    Set refused.Error = "No answer from Shutter at /api/shutter/intake: HTTP 503"
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "ForwardAnswered", 999999993, refused), "a refusal: Shutter did not take the message")
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "Seen", 999999993), "a refused forward does not mark the session seen")
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "Pending", 999999993), "and the pending mark is gone, so the next alert forwards again")
    // The forwarder failed the forward outright (OnError): the same.
    Do $CLASSMETHOD(ap, "MarkPending", 999999993, "Downstream Out")
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "ForwardAnswered", 999999993, ""), "no answer at all: not taken")
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "Seen", 999999993) || $CLASSMETHOD(ap, "Pending", 999999993), "neither seen nor pending")
    // Shutter took the message: seen, with the item the pending mark recorded.
    Do $CLASSMETHOD(ap, "MarkPending", 999999993, "Downstream Out")
    Set taken = ##class(Shutter.Intake.Forwarded).%New()
    Set taken.CaseId = "CASE-1", taken.State = "sealed"
    Do $$$AssertTrue($CLASSMETHOD(ap, "ForwardAnswered", 999999993, taken), "an answer without Error: taken")
    Do $$$AssertTrue($CLASSMETHOD(ap, "Seen", 999999993), "the session is seen once Shutter took the message")
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "Pending", 999999993), "and no longer pending")
    Do $$$AssertEquals($LISTGET(^Shutter.AlertIntake("seen", 999999993), 1), "Downstream Out", "with the item")
}

/// A pending mark no answer clears lapses after ten minutes, and the next mark drops it.
Method TestPendingLapses()
{
    Set ap = "Shutter.Intake.AlertProcess"
    Kill ^Shutter.AlertIntake("pending", 999999994), ^Shutter.AlertIntake("pending", 999999995)
    Set now = ##class(Shutter.Util.Time).EpochSeconds()
    Set ^Shutter.AlertIntake("pending", 999999994) = $LISTBUILD("Downstream Out", now - 601)
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "Pending", 999999994), "a mark older than ten minutes no longer holds the session")
    Set ^Shutter.AlertIntake("pending", 999999994) = $LISTBUILD("Downstream Out", now - 599)
    Do $$$AssertTrue($CLASSMETHOD(ap, "Pending", 999999994), "a younger one does")
    Set ^Shutter.AlertIntake("pending", 999999994) = $LISTBUILD("Downstream Out", now - 601)
    // The next mark drops the lapsed entries from the lowest session id up to the first young one, so a real session's
    // mark (a forward out at this moment) would stop the walk before this test's ids: the drop is checked only when
    // the test's entry comes first.
    Set first = $ORDER(^Shutter.AlertIntake("pending", ""))
    Do $CLASSMETHOD(ap, "MarkPending", 999999995, "Downstream Out")
    If first = 999999994 {
        Do $$$AssertEquals($DATA(^Shutter.AlertIntake("pending", 999999994)), 0, "the lapsed entry is dropped by the next mark")
    } Else {
        Do $$$LogMessage("a session's own pending mark (" _ first _ ") comes before the test's: the drop is not checked here")
    }
    Do $$$AssertTrue($CLASSMETHOD(ap, "Pending", 999999995), "the fresh one stays")
}

}
