/// One message of an approved set to send again through the engine. Declared here, with no sender in this release, so
/// that the later tier's sender and its ADT route compile against the same message.
Class Shutter.Msg.EngineResendRequest Extends Ens.Request
{

/// The header to send again: the origin, or Shutter's own never-opened clone standing in its place.
Property OriginHeaderId As %String(MAXLEN = 40);

/// The namespace of the production that holds it.
Property Namespace As %String(MAXLEN = 64);

/// The approval that covers the set.
Property ApprovalId As %String(MAXLEN = 64);

/// The case of the origin message, when it has one.
Property CaseId As %String(MAXLEN = 32);

Storage Default
{
<Data name="EngineResendRequestDefaultData">
<Subscript>"EngineResendRequest"</Subscript>
<Value name="1">
<Value>OriginHeaderId</Value>
</Value>
<Value name="2">
<Value>Namespace</Value>
</Value>
<Value name="3">
<Value>ApprovalId</Value>
</Value>
<Value name="4">
<Value>CaseId</Value>
</Value>
</Data>
<DefaultData>EngineResendRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
