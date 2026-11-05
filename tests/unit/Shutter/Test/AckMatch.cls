/// An application acknowledgement on its own feed (Shutter.Intake.AckMatch; CONTRACTS 11, v1.43): reading it with no schema, which
/// codes do nothing, finding the message it answers among those sent to the receiver, the forward it gives, once, and what it says
/// when it cannot find one. tests/e2e/onboard_check.py plays it on a real production.
Class Shutter.Test.AckMatch Extends %UnitTest.TestCase
{

Parameter RECEIVER = "UT Ack Out";

Property Headers As %List;

Property Sessions As %List;

Method OnAfterAllTests() As %Status
{
    For i = 1:1:$LISTLENGTH(..Headers) {
        Set h = ##class(Ens.MessageHeader).%OpenId($LIST(..Headers, i))
        If $ISOBJECT(h) {
            Do ##class(EnsLib.HL7.Message).%DeleteId(h.MessageBodyId)
            Do ##class(Ens.MessageHeader).%DeleteId($LIST(..Headers, i))
        }
    }
    For i = 1:1:$LISTLENGTH(..Sessions) {
        Kill ^Shutter.AlertIntake("seen", $LIST(..Sessions, i)), ^Shutter.AlertIntake("pending", $LIST(..Sessions, i))
    }
    Quit $$$OK
}

/// An acknowledgement as a feed brings it, with no document type.
Method Ack(code As %String, control As %String, words As %String = "", err As %String = "") As EnsLib.HL7.Message
{
    Quit ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\&|APP|HOSP|OCS|HOSP|20261105000000||ACK|K1|P|2.5.1" _ $CHAR(13) _ "MSA|" _ code _ "|" _ control _ "|" _ words _ $CHAR(13) _ $SELECT(err '= "": "ERR||||E||||" _ err _ $CHAR(13), 1: ""))
}

/// A saved message and its header: from the source to the target, in the session.
Method Sent(control As %String, source As %String, target As %String, session As %String) As Ens.MessageHeader
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\&|OCS|HOSP|APP|HOSP|20261105000000||ORM^O01|" _ control _ "|P|2.5.1" _ $CHAR(13))
    Do msg.%Save()
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.SessionId = session, h.SourceConfigName = source, h.TargetConfigName = target
    Set h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = msg.%Id()
    Do h.%Save()
    Set ..Headers = ..Headers _ $LISTBUILD(h.%Id()), ..Sessions = ..Sessions _ $LISTBUILD(session)
    Quit h
}

Method TestReadsAnAckWithNoSchema()
{
    Set m = "Shutter.Intake.AckMatch"
    Do $$$AssertTrue($CLASSMETHOD(m, "ReadAck", ..Ack("ae", "C1", "Not known"), .code, .control, .words), "an MSA is found")
    Do $$$AssertEquals(code _ "|" _ control _ "|" _ words, "AE|C1|Not known", "its code in upper case, its control id and its words")
    Do $CLASSMETHOD(m, "ReadAck", ..Ack("AR", "C2", "", "Closed encounter"), .code, .control, .words)
    Do $$$AssertEquals(words, "Closed encounter", "with no MSA-3, the words of ERR-8")
    Set none = ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\&|APP|HOSP|OCS|HOSP|20261105000000||ACK|K1|P|2.5.1" _ $CHAR(13))
    Do $$$AssertNotTrue($CLASSMETHOD(m, "ReadAck", none, .code, .control, .words), "no MSA")
    Do $$$AssertNotTrue($CLASSMETHOD(m, "ReadAck", "", .code, .control, .words), "no message")
}

Method TestAPositiveCodeDoesNothing()
{
    Set m = "Shutter.Intake.AckMatch"
    For code = "AA", "CA", "aa" {
        Set f = $CLASSMETHOD(m, "ForwardFor", ..Ack(code, "UTNONE"), ..#RECEIVER, .problem, .session)
        Do $$$AssertNotTrue($ISOBJECT(f), code _ " gives no forward")
        Do $$$AssertEquals(problem, "", code _ " and no problem, though no such message was sent")
    }
}

Method TestWhatItCannotFindIsSaid()
{
    Set m = "Shutter.Intake.AckMatch"
    Set f = $CLASSMETHOD(m, "ForwardFor", ..Ack("AE", "UTNONE", "Not known"), ..#RECEIVER, .problem, .session)
    Do $$$AssertNotTrue($ISOBJECT(f), "no message, no forward")
    Do $$$AssertTrue((problem [ "UTNONE") && (problem [ ..#RECEIVER) && (problem [ "Not known"), "and the problem names the control id, the receiver and the words: " _ problem)
    Set f = $CLASSMETHOD(m, "ForwardFor", ..Ack("ZZ", "UTNONE"), ..#RECEIVER, .problem, .session)
    Do $$$AssertNotTrue($ISOBJECT(f), "an unknown code, no forward")
    Do $$$AssertTrue(problem [ "ZZ", "and it says the code: " _ problem)
    Set none = ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\&|APP|HOSP|OCS|HOSP|20261105000000||ADT^A01|K1|P|2.5.1" _ $CHAR(13))
    Set f = $CLASSMETHOD(m, "ForwardFor", none, ..#RECEIVER, .problem, .session)
    Do $$$AssertNotTrue($ISOBJECT(f), "a message with no MSA, no forward")
    Do $$$AssertTrue(problem [ "no MSA", "and it says so: " _ problem)
}

/// The forward names the session's first HL7 message, once; the receiver's other messages are not it.
Method TestFindsTheMessageAndForwardsOnce()
{
    Set m = "Shutter.Intake.AckMatch", ap = "Shutter.Intake.AlertProcess"
    Set session = 999999000 + $RANDOM(900), control = "UTACK" _ session
    Set inbound = ..Sent(control, "UT In", "UT Router", session)
    Set sent = ..Sent(control, "UT Router", ..#RECEIVER, session)
    Set other = ..Sent(control _ "X", "UT Router", ..#RECEIVER, session + 1)
    Set found = $CLASSMETHOD(m, "FindSent", control, ..#RECEIVER)
    Do $$$AssertEquals($SELECT($ISOBJECT(found): found.%Id(), 1: ""), sent.%Id(), "the header to the receiver with that control id")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(m, "FindSent", control, "UT Other Out")), "not a message to another item")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(m, "FindSent", control, ..#RECEIVER, 1)), "nor one beyond the lookback")
    Set f = $CLASSMETHOD(m, "ForwardFor", ..Ack("AE", control, "Patient not known"), ..#RECEIVER, .problem, .key)
    Do $$$AssertTrue($ISOBJECT(f), "an AE gives a forward: " _ problem)
    If '$ISOBJECT(f) Quit
    Do $$$AssertEquals(key, session, "its completion key is the session")
    Do $$$AssertEquals(f.HeaderId, inbound.%Id(), "it names the session's first HL7 message")
    Do $$$AssertEquals(f.Route, "UT In", "and that message's service")
    Do $$$AssertEquals(f.Receiver, ..#RECEIVER, "the item that delivered")
    Do $$$AssertEquals(f.FailureKind _ "|" _ f.FailureOutcome _ "|" _ f.FailureReasonCode, "rejected|rejected|ack_AE", "a rejection, by that code")
    Do $$$AssertTrue((f.FailureText [ "AE") && (f.FailureText [ control) && (f.FailureText [ "Patient not known"), "the text has the code, the control id and the words: " _ f.FailureText)
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(m, "ForwardFor", ..Ack("AE", control), ..#RECEIVER, .problem)), "while it is out, a second AE gives no forward")
    Do $$$AssertEquals(problem, "", "and no problem")
    Set refused = ##class(Shutter.Intake.Forwarded).%New(), refused.Error = "HTTP 503"
    Do $CLASSMETHOD(ap, "ForwardAnswered", key, refused, ..#RECEIVER)
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(m, "ForwardFor", ..Ack("AE", control), ..#RECEIVER, .problem)), "a refusal leaves it open for the next one")
    Set taken = ##class(Shutter.Intake.Forwarded).%New()
    Do $CLASSMETHOD(ap, "ForwardAnswered", key, taken, ..#RECEIVER)
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(m, "ForwardFor", ..Ack("AR", control), ..#RECEIVER, .problem)), "once Shutter took it, no other code forwards it again")
    Do $$$AssertTrue($CLASSMETHOD(ap, "Seen", session, ..#RECEIVER), "and the alert intake reads it as seen too")
}

}
