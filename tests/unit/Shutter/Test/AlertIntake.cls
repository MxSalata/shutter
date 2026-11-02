/// The alert intake (Shutter.Intake.AlertProcess; CONTRACTS 11, v1.35): which alerts it takes, how it reads the failure
/// from an alert's words, the session's HL7 header, the forward it builds, and the once-per-session mark.
Class Shutter.Test.AlertIntake Extends %UnitTest.TestCase
{

Method OnAfterAllTests() As %Status
{
    Kill ^Shutter.AlertIntake("seen", 999999991), ^Shutter.AlertIntake("seen", 999999992)
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

}
