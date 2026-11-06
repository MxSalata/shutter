/// The alert intake (Shutter.Intake.AlertProcess; CONTRACTS 11, v1.35): which alerts it takes, how it reads the failure
/// from an alert's words, the session's HL7 header, the forward it builds, and the once-per-session marks: pending while
/// the forward is out, seen once Shutter took the message.
Class Shutter.Test.AlertIntake Extends %UnitTest.TestCase
{

/// Headers and sessions this class's tests made, to clear afterwards.
Property Made As %List;

Property Sessions As %List;

Method OnAfterAllTests() As %Status
{
    For i = 1:1:$LISTLENGTH(..Made) {
        Set h = ##class(Ens.MessageHeader).%OpenId($LIST(..Made, i))
        If $ISOBJECT(h) {
            Do ##class(EnsLib.HL7.Message).%DeleteId(h.MessageBodyId)
            Do ##class(Ens.MessageHeader).%DeleteId($LIST(..Made, i))
        }
    }
    For i = 1:1:$LISTLENGTH(..Sessions) {
        Kill ^Shutter.AlertIntake("several", $LIST(..Sessions, i))
    }
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
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "Something broke"), "uncertain_outcome", "words it does not know say nothing about delivery: uncertain")
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "ERROR <Ens>ErrOutConnectFailed: HTTP Connect failed for ward:8080 - Connection refused"), "delivery_failed", "a connection refused is no rejection: nothing was sent")
    Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", "Refused by the receiving service: the message does not validate"), "rejected", "refused by the receiver is a rejection")
    Do $$$AssertEquals($CLASSMETHOD(ap, "HttpStatusIn", "Received non-OK status 503 from remote HTTP server: 'HTTP/1.1 503 Service Unavailable'"), "503", "the HTTP status from the text")
    Do $$$AssertEquals($CLASSMETHOD(ap, "HttpStatusIn", "Received http 422 from the ward system"), "422", "any case")
    Do $$$AssertEquals($CLASSMETHOD(ap, "HttpStatusIn", "'HTTP/1.1 503 Service Unavailable'"), "503", "the status line's form")
    Do $$$AssertEquals($CLASSMETHOD(ap, "HttpStatusIn", "status 2026 is not one"), "", "four digits are not a status")
    Do $$$AssertEquals($CLASSMETHOD(ap, "HttpStatusIn", "Lost TCP connection"), "", "none named")
}

/// Words Classify does not know, and the words that say the receiver may hold the message, are never "not delivered". What it
/// knows keeps its meaning, and a receiver's answer is read before the words for a connection.
Method TestClassifyNeverGuessesNotDelivered()
{
    Set ap = "Shutter.Intake.AlertProcess"
    Set unread = $LISTBUILD("Invalid NHS number", "Patient not known", "Invalid location WARD-9", "Zeitlimit beim Warten auf die Antwort", "Peer closed connection after send",
        "QueueWaitAlert: Message Header Id 12345 has been queued for more than 30 seconds", "ERROR <Ens>ErrOutConnectionLost: Lost HL7 Read connection", "ERROR <Ens>ErrHTTPStatus: Received non-OK status 500 from remote HTTP server", "ERROR <Ens>ErrHTTPStatus: Received non-OK status 502 from remote HTTP server", "")
    For i = 1:1:$LISTLENGTH(unread) {
        Set words = $LIST(unread, i), read = ""
        Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", words, .read), "uncertain_outcome", "uncertain: " _ words)
        Do $$$AssertEquals(read, 1, "and marked as not read: " _ words)
    }
    Set known("ERROR <Ens>ErrOutConnectExpired: TCP Connect timeout") = "delivery_failed"
    Set known("ERROR <Ens>ErrOutConnectFailed: HTTP Connect failed for ward:8080 - Connection refused") = "delivery_failed"
    Set known("ERROR <Ens>ErrHTTPStatus: Received non-OK status 503 from remote HTTP server") = "delivery_failed"
    Set known("ERROR <Ens>ErrTCPTerminatedReadTimeoutExpired") = "uncertain_outcome"
    Set known("Response timeout after 15 seconds") = "uncertain_outcome"
    Set known("AE: database connection refused at the application") = "rejected"
    Set known("Received HTTP 422 from the ward system") = "rejected"
    Set known("connection refused by ward:8080") = "delivery_failed"
    Set words = ""
    For {
        Set words = $ORDER(known(words), 1, kind) Quit:words=""
        Set read = ""
        Do $$$AssertEquals($CLASSMETHOD(ap, "Classify", words, .read), kind, kind _ ": " _ words)
        Do $$$AssertEquals(read, 0, "words it knows: " _ words)
    }
}

/// A forward on words Classify does not know says so in its reason code, which the matcher reads as no answer at all.
Method TestForwardOnWordsItDoesNotKnow()
{
    Set ap = "Shutter.Intake.AlertProcess"
    Set header = ##class(Ens.MessageHeader).%New()
    Set header.SourceConfigName = "PAS In"
    Set alert = ##class(Ens.AlertRequest).%New()
    Set alert.SourceConfigName = "Downstream Out", alert.AlertText = "QueueWaitAlert: Message Header Id 12345 has been queued for more than 30 seconds", alert.SessionId = 12345
    Set f = $CLASSMETHOD(ap, "ForwardFromAlert", alert, header, "Downstream Out")
    Do $$$AssertEquals(f.FailureKind _ "|" _ f.FailureOutcome _ "|" _ f.FailureReasonCode, "uncertain_outcome|uncertain|alert_unread", "uncertain, and not read")
    Do $$$AssertTrue(f.FailureText [ "QueueWaitAlert", "with the alert's own words")
    Set alert.AlertText = "Response timeout after 15 seconds"
    Set f = $CLASSMETHOD(ap, "ForwardFromAlert", alert, header, "Downstream Out")
    Do $$$AssertEquals(f.FailureReasonCode, "alert", "words it knows keep the reason alert")
}

/// A saved HL7 message and its header, from the source to the target, in the session; the patient and control id are the test's.
Method Sent(control As %String, source As %String, target As %String, session As %String, patient As %String = "MRN-UT-1", ward As %String = "WARD-A") As Ens.MessageHeader
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\&|PAS|HOSP|BED|HOSP|20261105000000||ADT^A02|" _ control _ "|P|2.5.1" _ $CHAR(13) _ "PID|1||" _ patient _ "^^^HOSP^MR" _ $CHAR(13) _ "PV1|1|I|" _ ward _ $CHAR(13))
    Do msg.%Save()
    Quit ..HeaderFor(msg, source, target, session)
}

Method HeaderFor(msg As EnsLib.HL7.Message, source As %String, target As %String, session As %String) As Ens.MessageHeader
{
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.SessionId = session, h.SourceConfigName = source, h.TargetConfigName = target
    Set h.MessageBodyClassName = $CLASSNAME(msg), h.MessageBodyId = msg.%Id()
    Do h.%Save()
    Set ..Made = ..Made _ $LISTBUILD(h.%Id()), ..Sessions = ..Sessions _ $LISTBUILD(session)
    Quit h
}

/// The alerting item's own message beats the session's first (the transform's change stays); with none, the first stands.
Method TestTheMessageTheItemWasSent()
{
    Set ap = "Shutter.Intake.AlertProcess", session = 999998000 + $RANDOM(900)
    Set inbound = ..Sent("UTF1", "UT In", "UT Router", session, , "PAS-CODE")
    Set sent = ..Sent("UTF1", "UT Router", "UT Out", session, , "WARD-C")
    Set h = $CLASSMETHOD(ap, "HL7HeaderOfSession", session, .problem, "UT Out")
    Do $$$AssertEquals($SELECT($ISOBJECT(h): h.%Id(), 1: ""), sent.%Id(), "the header the item was sent: " _ problem)
    Set h = $CLASSMETHOD(ap, "HL7HeaderOfSession", session, .problem)
    Do $$$AssertEquals($SELECT($ISOBJECT(h): h.%Id(), 1: ""), inbound.%Id(), "with no item, the session's first, as before")
    Set h = $CLASSMETHOD(ap, "HL7HeaderOfSession", session, .problem, "UT Other Out")
    Do $$$AssertEquals($SELECT($ISOBJECT(h): h.%Id(), 1: ""), inbound.%Id(), "an item sent no HL7 falls back to the session's first, as a connector taking a ward operation does")
    Do $$$AssertEquals($CLASSMETHOD(ap, "RouteOfSession", session, sent), "UT In", "the route stays the service that received it")
    Do $$$AssertEquals($CLASSMETHOD(ap, "SeveralInSession", session, "UT Out"), "", "one message to the item is not several")
    Do $$$AssertEquals($CLASSMETHOD(ap, "SeveralInSession", session, "UT Other Out"), "", "nor is one patient's message and its transform")
}

/// Two different messages to one item in a session: the alert names neither, so no case is built on a guess, and the words name both.
Method TestSeveralMessagesToOneItemOpenNoCase()
{
    Set ap = "Shutter.Intake.AlertProcess", session = 999998000 + $RANDOM(900)
    Set inbound = ..Sent("UTG0", "UT In", "UT Router", session, "MRN-UT-1")
    Set first = ..Sent("UTG1", "UT Router", "UT Out", session, "MRN-UT-1")
    Set second = ..Sent("UTG2", "UT Router", "UT Out", session, "MRN-UT-2")
    Set words = $CLASSMETHOD(ap, "SeveralInSession", session, "UT Out")
    Do $$$AssertTrue((words [ "2 different") && (words [ "UT Out") && (words [ "UTG1") && (words [ "UTG2") && (words [ first.%Id()) && (words [ second.%Id()), "the words name the session's messages: " _ words)
    Do $$$AssertNotTrue(words [ "MRN-UT", "by control id and header, with no patient identifier in an alert: " _ words)
    Set h = $CLASSMETHOD(ap, "HL7HeaderOfSession", session, .problem, "UT Out")
    Do $$$AssertNotTrue($ISOBJECT(h), "no header is picked")
    Do $$$AssertTrue(problem '= "", "and the problem says why")
    // The same body sent twice is one message.
    Set again = ##class(EnsLib.HL7.Message).%OpenId(first.MessageBodyId)
    Set session2 = session + 1000
    Do ..HeaderFor(again, "UT Router", "UT Out", session2), ..HeaderFor(again, "UT Router", "UT Out", session2)
    Do $$$AssertEquals($CLASSMETHOD(ap, "SeveralInSession", session2, "UT Out"), "", "one body sent twice is one message")
    // Said once per session and item, kept a day with the other marks.
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "SaidSeveral", session, "UT Out"), "not said yet")
    Do $CLASSMETHOD(ap, "MarkSaidSeveral", session, "UT Out")
    Do $$$AssertTrue($CLASSMETHOD(ap, "SaidSeveral", session, "UT Out"), "said")
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "SaidSeveral", session, "UT Other Out"), "not for another item")
}

/// An item that took no HL7, in a session whose HL7 messages name two patients: the session's first could be the wrong patient.
Method TestAnotherPatientStopsTheFallback()
{
    Set ap = "Shutter.Intake.AlertProcess", session = 999998000 + $RANDOM(900)
    Do ..Sent("UTP1", "UT In", "UT Router", session, "MRN-UT-1"), ..Sent("UTP2", "UT In", "UT Router", session, "MRN-UT-2")
    Set words = $CLASSMETHOD(ap, "SeveralInSession", session, "UT Out")
    Do $$$AssertTrue((words [ "UTP1") && (words [ "UTP2"), "two patients in the session are said: " _ words)
    Do $$$AssertNotTrue(words [ "MRN-UT", "with no patient identifier in an alert: " _ words)
    Set h = $CLASSMETHOD(ap, "HL7HeaderOfSession", session, .problem, "UT Out")
    Do $$$AssertNotTrue($ISOBJECT(h), "and no header is picked")
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
    Do $$$AssertTrue($CLASSMETHOD(ap, "Seen", 999999991, "Downstream Out"), "at that item")
    // A message routed to two receivers: the second one's failure is its own forward.
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "Seen", 999999991, "Records Out"), "not at another item")
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
    Do $$$AssertTrue($CLASSMETHOD(ap, "Seen", 999999993, "Downstream Out"), "with the item")
}

/// A pending mark no answer clears lapses after ten minutes, and the next mark drops it.
Method TestPendingLapses()
{
    Set ap = "Shutter.Intake.AlertProcess"
    Kill ^Shutter.AlertIntake("pending", 999999994), ^Shutter.AlertIntake("pending", 999999995)
    Set now = ##class(Shutter.Util.Time).EpochSeconds()
    Set ^Shutter.AlertIntake("pending", 999999994, "Downstream Out") = now - 601
    Do $$$AssertNotTrue($CLASSMETHOD(ap, "Pending", 999999994), "a mark older than ten minutes no longer holds the session")
    Set ^Shutter.AlertIntake("pending", 999999994, "Downstream Out") = now - 599
    Do $$$AssertTrue($CLASSMETHOD(ap, "Pending", 999999994), "a younger one does")
    Set ^Shutter.AlertIntake("pending", 999999994, "Downstream Out") = now - 601
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
