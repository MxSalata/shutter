/// The alert intake (docs/CONTRACTS.md, section 11, v1.35): the Ens.Alert item of a watched production, for a site whose
/// delivering process does nothing on a failure beyond the error IRIS logs. Added as the item named "Ens.Alert" (the name
/// the engine sends alerts to), it receives every Ens.AlertRequest an item raises (AlertOnError, a queue alert, an
/// inactivity alert). Every alert is first passed on to PassTo, the site's own alert consumer renamed, so Shutter never
/// silences a site's alerting. Then, for an alert from one of the Receivers (the connector items; empty takes any item)
/// whose session holds an HL7 message, it finds that message (the session's first header with an EnsLib.HL7.Message
/// body: the receiving service's), builds a Shutter.Intake.Forward for it with the failure read from the alert's words,
/// and sends it to the forwarder, once per session. The feed never waits: both sends are asynchronous. An alert whose
/// session has no HL7 message, or from an item outside Receivers, is passed on only.
/// The demo hospital's production carries this item with Receivers "Downstream Out"; its own process already forwards
/// its failures (Hospital.Process.PASToDownstream), so that process stays out of Receivers and a failure reaches Shutter
/// once.
Class Shutter.Intake.AlertProcess Extends Ens.BusinessProcess
{

/// The Shutter.Intake.Forwarder item that hands the message to Shutter.
Property ForwarderTarget As %String(MAXLEN = 128) [ InitialExpression = "Shutter Forwarder" ];

/// The site's own alert consumer (an alert operation, an email), renamed so that this item can take the Ens.Alert name;
/// every alert is passed on to it, before anything else. Empty: alerts end here.
Property PassTo As %String(MAXLEN = 128);

/// The items whose alerts hand a failed delivery to Shutter (comma-separated config names; the connectors). Empty: any item.
Property Receivers As %String(MAXLEN = 1000);

Parameter SETTINGS = "ForwarderTarget:Shutter:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},PassTo:Shutter:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},Receivers:Shutter";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    If '$ISOBJECT(request) || 'request.%IsA("Ens.AlertRequest") {
        $$$TRACE("Not an alert (" _ $SELECT($ISOBJECT(request): $CLASSNAME(request), 1: "nothing") _ "): ignored")
        Quit $$$OK
    }
    // The site's own consumer first: Shutter adds to a production's alerting, never replaces it.
    If ..PassTo '= "" {
        Set sc = ..SendRequestAsync(..PassTo, request, 0, "pass")
        If $$$ISERR(sc) $$$LOGWARNING("The alert could not be passed on to " _ ..PassTo _ ": " _ $SYSTEM.Status.GetErrorText(sc))
    }
    If '..Takes(request.SourceConfigName, ..Receivers) {
        $$$TRACE("Alert from " _ request.SourceConfigName _ ": not a receiver in " _ $SELECT(..Receivers = "": "(any)", 1: ..Receivers) _ ", passed on only")
        Quit $$$OK
    }
    If request.SessionId = "" {
        $$$TRACE("Alert from " _ request.SourceConfigName _ " carries no session: nothing to hand to Shutter")
        Quit $$$OK
    }
    If ..Seen(request.SessionId) {
        $$$TRACE("Alert from " _ request.SourceConfigName _ " for session " _ request.SessionId _ ": its message was handed to Shutter already")
        Quit $$$OK
    }
    Set header = ..HL7HeaderOfSession(request.SessionId, .problem)
    If '$ISOBJECT(header) {
        $$$TRACE("Alert from " _ request.SourceConfigName _ " for session " _ request.SessionId _ ": " _ problem _ "; passed on only")
        Quit $$$OK
    }
    Set forward = ..ForwardFromAlert(request, header, request.SourceConfigName)
    Set sc = ..SendRequestAsync(..ForwarderTarget, forward, 1, "forward")
    If $$$ISERR(sc) {
        $$$LOGWARNING("The alert's message (header " _ header.%Id() _ ") could not be handed to " _ ..ForwarderTarget _ ": " _ $SYSTEM.Status.GetErrorText(sc))
        Quit $$$OK
    }
    Do ..MarkSeen(request.SessionId, request.SourceConfigName)
    $$$TRACE("Alert from " _ request.SourceConfigName _ ": message header " _ header.%Id() _ " (" _ header.SourceConfigName _ ") handed to " _ ..ForwarderTarget _ " as " _ forward.FailureKind)
    Quit $$$OK
}

/// The forwarder's answer: a refusal is a warning here, as the sending process has it; the alert itself was passed on already.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, completionkey As %String) As %Status
{
    If (completionkey = "forward") && $ISOBJECT(callresponse) && callresponse.%IsA("Shutter.Intake.Forwarded") {
        If callresponse.Error '= "" {
            $$$LOGWARNING("Shutter did not take the alert's message: " _ callresponse.Error)
        } Else {
            $$$TRACE("Shutter opened or found case " _ callresponse.CaseId _ " (" _ callresponse.State _ ")")
        }
    }
    Quit $$$OK
}

/// Whether an alert from the item is one to hand to Shutter: receivers empty takes any; else the item must be listed.
ClassMethod Takes(source As %String, receivers As %String) As %Boolean
{
    If $ZSTRIP(receivers, "<>W") = "" Quit 1
    Set listed = 0
    For i = 1:1:$LENGTH(receivers, ",") {
        If $ZSTRIP($PIECE(receivers, ",", i), "<>W") = source Set listed = 1 Quit
    }
    Quit listed
}

/// The failed delivery's HL7 message: the session's first header whose body is an EnsLib.HL7.Message (the receiving
/// service's). problem says why there is none.
ClassMethod HL7HeaderOfSession(sessionId As %String, Output problem As %String) As Ens.MessageHeader
{
    Set problem = ""
    If sessionId = "" Set problem = "no session" Quit ""
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, MessageBodyClassName FROM Ens.MessageHeader WHERE SessionId = ? ORDER BY ID", sessionId)
        While rs.%Next() {
            Set cls = rs.%Get("MessageBodyClassName")
            Continue:cls=""
            Set isHL7 = 0
            Try { Set isHL7 = $CLASSMETHOD(cls, "%Extends", "EnsLib.HL7.Message") } Catch inner { Set isHL7 = 0 }
            If isHL7 Quit
        }
        If '$GET(isHL7) Set problem = "no HL7 message in session " _ sessionId Quit
        Set header = ##class(Ens.MessageHeader).%OpenId(rs.%Get("ID"))
        If '$ISOBJECT(header) Set problem = "header " _ rs.%Get("ID") _ " could not be opened" Quit
        Quit
    } Catch ex {
        Set problem = ex.DisplayString(), header = ""
    }
    Quit $GET(header)
}

/// The failure as the alert's words tell it: a timeout or no answer is an uncertain outcome, a refusal or a NACK a
/// rejection, anything else a failed delivery.
ClassMethod Classify(text As %String) As %String
{
    Set t = $ZCONVERT(text, "L")
    If (t [ "timeout") || (t [ "timed out") || (t [ "no response") || (t [ "did not answer") || (t [ "did not respond") || (t [ "uncertain") Quit "uncertain_outcome"
    If (t [ "reject") || (t [ "refused") || (t [ "nack") || $MATCH(t, ".*\b(ae|ar)\b.*") Quit "rejected"
    If $EXTRACT(..HttpStatusIn(text), 1) = "4" Quit "rejected"
    Quit "delivery_failed"
}

/// The HTTP status the alert's text names ("HTTP 503", "status 503", "HTTP/1.1 503"), else "".
ClassMethod HttpStatusIn(text As %String) As %String
{
    Set e = 0, m = ""
    Set p = $LOCATE(text, "(?i)(?:HTTP(?:/[0-9.]+)?|status)[ :]+([1-5][0-9][0-9])\b", 1, e, m)
    If 'p Quit ""
    Quit $EXTRACT(m, $LENGTH(m) - 2, $LENGTH(m))
}

/// The forward for an alert's message: the header, its service as the route, the alerting item as the receiver, and the
/// failure from the alert's words, with reason code "alert".
ClassMethod ForwardFromAlert(alert As Ens.AlertRequest, header As Ens.MessageHeader, receiver As %String) As Shutter.Intake.Forward
{
    Set f = ##class(Shutter.Intake.Forward).%New()
    Set f.HeaderId = header.%Id()
    Set f.Route = header.SourceConfigName
    Set f.Receiver = receiver
    Set f.FailureKind = ..Classify(alert.AlertText)
    Set f.FailureOutcome = $CASE(f.FailureKind, "uncertain_outcome": "uncertain", "rejected": "rejected", : "error")
    Set status = ..HttpStatusIn(alert.AlertText)
    If status '= "" Set f.FailureHttpStatus = +status
    Set f.FailureReasonCode = "alert"
    Set when = ""
    Try { Set when = $SELECT(alert.AlertTime '= "": $ZDATETIME(alert.AlertTime, 3, 1), 1: "") } Catch ex { Set when = "" }
    Set f.FailureText = $EXTRACT("Alert from " _ alert.SourceConfigName _ $SELECT(when '= "": " at " _ when _ " UTC", 1: "") _ ": " _ alert.AlertText, 1, 2000)
    Quit f
}

/// Whether the session's message was handed to Shutter already (once per session, kept a day).
ClassMethod Seen(sessionId As %String) As %Boolean
{
    Quit $DATA(^Shutter.AlertIntake("seen", sessionId)) > 0
}

ClassMethod MarkSeen(sessionId As %String, source As %String)
{
    Set now = $PIECE($HOROLOG, ",", 1) * 86400 + $PIECE($HOROLOG, ",", 2)
    Set ^Shutter.AlertIntake("seen", sessionId) = $LISTBUILD(source, now)
    // Sessions are numbered upwards, so the oldest entries come first: drop what is older than a day.
    Set k = ""
    For {
        Set k = $ORDER(^Shutter.AlertIntake("seen", k)) Quit:k=""
        If (now - $LISTGET(^Shutter.AlertIntake("seen", k), 2, 0)) < 86400 Quit
        Kill ^Shutter.AlertIntake("seen", k)
    }
}

Storage Default
{
<Data name="AlertProcessDefaultData">
<Subscript>"AlertProcess"</Subscript>
<Value name="1">
<Value>ForwarderTarget</Value>
</Value>
<Value name="2">
<Value>PassTo</Value>
</Value>
<Value name="3">
<Value>Receivers</Value>
</Value>
</Data>
<DefaultData>AlertProcessDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
