/// What one send through the engine did. Declared here, with no sender in this release.
Class Shutter.Msg.EngineResendResult Extends Ens.Response
{

/// The header the engine made for the send.
Property NewHeaderId As %String(MAXLEN = 40);

/// The new header's status when its read ended: Completed, or what stopped the run.
Property Status As %String(MAXLEN = 32);

/// What happened, in words.
Property Words As %String(MAXLEN = 1000);

Storage Default
{
<Data name="EngineResendResultDefaultData">
<Subscript>"EngineResendResult"</Subscript>
<Value name="1">
<Value>NewHeaderId</Value>
</Value>
<Value name="2">
<Value>Status</Value>
</Value>
<Value name="3">
<Value>Words</Value>
</Value>
</Data>
<DefaultData>EngineResendResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
