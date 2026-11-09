/// The REST route's request to the Failure Census item: a registered receiver and a window, never a namespace or SQL text.
Class Shutter.Msg.CensusRequest Extends Ens.Request
{

Property Receiver As %String(MAXLEN = 128);

/// ISO UTC.
Property FromUTC As %String(MAXLEN = 30);

Property ToUTC As %String(MAXLEN = 30);

Property RequestedBy As %String(MAXLEN = 160);

Storage Default
{
<Data name="CensusRequestDefaultData">
<Subscript>"CensusRequest"</Subscript>
<Value name="1">
<Value>Receiver</Value>
</Value>
<Value name="2">
<Value>FromUTC</Value>
</Value>
<Value name="3">
<Value>ToUTC</Value>
</Value>
<Value name="4">
<Value>RequestedBy</Value>
</Value>
</Data>
<DefaultData>CensusRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
