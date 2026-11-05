/// The rig's worked example of an application acknowledgement feed (docs/INSTALL.md 9.9): a site copies this class, names the
/// item that delivered, and points its feed's service here. A negative code becomes a case in Shutter through the forwarder; a
/// positive code does nothing; a negative code that names no message it can find raises an alert, since that failure has no case.
Class OnbAck.AckProcess Extends Ens.BusinessProcess
{

/// The item that delivered the messages this feed answers.
Property Receiver As %String(MAXLEN = 128);

Property ForwarderTarget As %String(MAXLEN = 128) [ InitialExpression = "Shutter Forwarder" ];

Parameter SETTINGS = "Receiver:Basic,ForwarderTarget:Basic";

Method OnRequest(request As EnsLib.HL7.Message, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    Set forward = ##class(Shutter.Intake.AckMatch).ForwardFor(request, ..Receiver, .problem, .session)
    If $ISOBJECT(forward) Quit ..SendRequestAsync(..ForwarderTarget, forward, 1, session)
    If problem '= "" {
        $$$LOGWARNING(problem)
        Do ..SendAlert(##class(Ens.AlertRequest).%New($LISTBUILD(..%ConfigName, problem)))
    }
    Quit $$$OK
}

/// The forwarder's answer: seen once Shutter took it; a refusal leaves it open, and the forwarder has raised its alert.
Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, completionkey As %String) As %Status
{
    Do ##class(Shutter.Intake.AlertProcess).ForwardAnswered(completionkey, callresponse, ..Receiver)
    Quit $$$OK
}

Storage Default
{
<Data name="AckProcessDefaultData">
<Subscript>"AckProcess"</Subscript>
<Value name="1">
<Value>Receiver</Value>
</Value>
<Value name="2">
<Value>ForwarderTarget</Value>
</Value>
</Data>
<DefaultData>AckProcessDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
