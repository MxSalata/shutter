/// An application acknowledgement that arrives on its own feed (docs/INSTALL.md 9.9; CONTRACTS 11, v1.43): some receivers take a
/// message with a commit ACK on the connection and answer AE or AR later, as a message of their own, to a service in the
/// sending namespace. The engine has already completed that message by then, so nothing else in Shutter hears of it. A site's small
/// business process on that feed calls ForwardFor with each message the feed brings and the item that delivered, and sends what it
/// answers to the forwarder: tests/e2e/onboard_site/OnbAck.AckProcess.cls is the worked example, and the service needs
/// IgnoreInboundAck 0 and AckMode Never. A positive code does nothing. A code that names no message it can find is a
/// problem to raise, since that failure has no case. An acknowledgement that never comes is not seen here: nothing waits for one.
Class Shutter.Intake.AckMatch
{

/// How many of the newest messages to the receiver are read when looking for the one an acknowledgement names: IRIS keeps no
/// index on a message's control id, so a feed slower than this many messages gets the problem, and a larger lookback.
Parameter LOOKBACK = 5000;

/// The acknowledgement's MSA-1 in upper case, MSA-2 and its words (MSA-3, else ERR-8), read by position, so it needs no schema. False: there is no MSA.
ClassMethod ReadAck(ack As EnsLib.HL7.Message, Output code As %String, Output control As %String, Output words As %String) As %Boolean
{
    Set (code, control, words) = "", found = 0, err = ""
    If '$ISOBJECT(ack) Quit 0
    For i = 2:1 {
        Set seg = ack.GetSegmentAt(i)
        Quit:'$ISOBJECT(seg)
        Set name = seg.GetValueAt(0)
        If (name = "MSA") && 'found {
            Set found = 1, code = $ZCONVERT($ZSTRIP(seg.GetValueAt(1), "<>W"), "U"), control = $ZSTRIP(seg.GetValueAt(2), "<>W"), words = seg.GetValueAt(3)
        } ElseIf (name = "ERR") && (err = "") {
            Set err = seg.GetValueAt(8)
        }
    }
    If words = "" Set words = err
    Quit found
}

/// The header of the newest message sent to the receiver whose MSH-10 is the control id, or "".
ClassMethod FindSent(control As %String, receiver As %String, lookback As %Integer = "") As Ens.MessageHeader
{
    If (control = "") || (receiver = "") Quit ""
    If +lookback < 1 Set lookback = ..#LOOKBACK
    Set found = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ (+lookback) _ " ID, MessageBodyId, MessageBodyClassName FROM Ens.MessageHeader WHERE TargetConfigName = ? ORDER BY ID DESC", receiver)
    While rs.%Next() {
        Set cls = rs.%Get("MessageBodyClassName"), isHL7 = 0
        Continue:cls=""
        Try { Set isHL7 = $CLASSMETHOD(cls, "%Extends", "EnsLib.HL7.Message") } Catch inner { Set isHL7 = 0 }
        Continue:'isHL7
        Set msg = $CLASSMETHOD(cls, "%OpenId", rs.%Get("MessageBodyId"))
        Continue:'$ISOBJECT(msg)
        If msg.GetValueAt("1:10") = control Set found = ##class(Ens.MessageHeader).%OpenId(rs.%Get("ID")) Quit
    }
    Quit found
}

/// The forward for a negative acknowledgement, as a process on the feed sends it (kind rejected, reason ack_ and the code), or "".
/// AA and CA give "" and no problem. AE, AR, CE and CR look for the message by MSA-2 among those sent to the receiver: the forward
/// names that message, so a transform on the route is not lost, with the session's service as its route. problem says why there is no forward
/// for one that needed it, and is for the site to raise. session is the completion key: pending and seen marks are the alert intake's
/// (Shutter.Intake.AlertProcess), so one message at one receiver reaches Shutter once, by whichever route comes first. Those marks are
/// per session and receiver, so a negative code for another message of a session already handed on gets no case, and the problem names it.
ClassMethod ForwardFor(ack As EnsLib.HL7.Message, receiver As %String, Output problem As %String, Output session As %String, lookback As %Integer = "") As Shutter.Intake.Forward
{
    Set problem = "", session = ""
    If '..ReadAck(ack, .code, .control, .words) Set problem = "A message on the acknowledgement feed has no MSA segment, so it answers nothing" Quit ""
    If (code = "AA") || (code = "CA") Quit ""
    If '$LISTFIND($LISTBUILD("AE", "AR", "CE", "CR"), code) Set problem = "An acknowledgement of " _ control _ " has the code '" _ code _ "', which is neither an accept nor an error" Quit ""
    Set sent = ..FindSent(control, receiver, lookback)
    If '$ISOBJECT(sent) Set problem = "A " _ code _ " names the control id '" _ control _ "', and no message with it is among the last " _ $SELECT(+lookback > 0: +lookback, 1: ..#LOOKBACK) _ " sent to " _ receiver _ ", so Shutter has no case for it: " _ $EXTRACT(words, 1, 200) Quit ""
    Set session = sent.SessionId
    Set ap = "Shutter.Intake.AlertProcess"
    If $CLASSMETHOD(ap, "Seen", session, receiver) || $CLASSMETHOD(ap, "Pending", session, receiver) {
        If '$CLASSMETHOD(ap, "Handed", session, receiver, control) && ($LISTLENGTH($CLASSMETHOD(ap, "SentTo", session, receiver)) > 1) {
            Set problem = "A " _ code _ " names the message " _ control _ " (header " _ sent.%Id() _ ") sent to " _ receiver _ ", and another message of session " _ session _ " was handed to Shutter already, so this one has no case: " _ $EXTRACT(words, 1, 200)
        }
        Quit ""
    }
    Set f = ##class(Shutter.Intake.Forward).%New()
    Set f.HeaderId = sent.%Id()
    Set f.Route = $CLASSMETHOD(ap, "RouteOfSession", session, sent)
    Set f.Receiver = receiver
    Set f.FailureKind = "rejected", f.FailureOutcome = "rejected", f.FailureReasonCode = "ack_" _ code
    Set f.FailureText = $EXTRACT("The receiver's acknowledgement feed answered " _ code _ " to the message " _ control _ " sent to " _ receiver _ " (header " _ sent.%Id() _ "), which the engine had completed" _ $SELECT(words '= "": ": " _ words, 1: ""), 1, 2000)
    Do $CLASSMETHOD(ap, "MarkPending", session, receiver)
    Do $CLASSMETHOD(ap, "MarkHanded", session, receiver, control)
    Quit f
}

}
