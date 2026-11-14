/// What became of the update: its outcome, whether anything was sent, and the receiver's answer.
Class Shutter.Msg.FHIRWriteResult Extends Ens.Response
{

/// applied, version_conflict, refused, uncertain or error.
Property Outcome As %String(MAXLEN = 32);

/// 0 when there was no answer.
Property HttpStatus As %Integer;

/// True once the request left, whatever came back.
Property Sent As %Boolean;

Property ResponseEtag As %String(MAXLEN = 200);

Property ResponseLocation As %String(MAXLEN = 500);

Property ReasonCode As %String(MAXLEN = 64);

Property Diagnostics As %String(MAXLEN = 400);

Property Error As %String(MAXLEN = 2000);

Storage Default
{
<Data name="FHIRWriteResultDefaultData">
<Subscript>"FHIRWriteResult"</Subscript>
<Value name="1">
<Value>Outcome</Value>
</Value>
<Value name="2">
<Value>HttpStatus</Value>
</Value>
<Value name="3">
<Value>Sent</Value>
</Value>
<Value name="4">
<Value>ResponseEtag</Value>
</Value>
<Value name="5">
<Value>ResponseLocation</Value>
</Value>
<Value name="6">
<Value>ReasonCode</Value>
</Value>
<Value name="7">
<Value>Diagnostics</Value>
</Value>
<Value name="8">
<Value>Error</Value>
</Value>
</Data>
<DefaultData>FHIRWriteResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
