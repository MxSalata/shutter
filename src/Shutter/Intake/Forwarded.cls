/// What Shutter answered a forwarded failure: the case it opened or updated, or why it took nothing. Error is empty
/// when Shutter answered 202; otherwise it holds the HTTP status and body, or the connection error. The forwarder
/// never fails the message over it; the sending process reads Error and decides.
Class Shutter.Intake.Forwarded Extends Ens.Response
{

Property CaseId As %String(MAXLEN = 32);

Property State As %String(MAXLEN = 32);

/// True when the intake opened a new case; false when it joined an open one.
Property Opened As %Boolean [ InitialExpression = 0 ];

Property Error As %String(MAXLEN = 4000);

Storage Default
{
<Data name="ForwardedDefaultData">
<Subscript>"Forwarded"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>State</Value>
</Value>
<Value name="3">
<Value>Opened</Value>
</Value>
<Value name="4">
<Value>Error</Value>
</Value>
</Data>
<DefaultData>ForwardedDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
