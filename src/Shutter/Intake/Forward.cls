/// What a watched production hands Shutter when one of its deliveries failed (docs/CONTRACTS.md, section 11): the
/// failed HL7 message's header id in the sending namespace, the item that delivered, and the failure as the sender's
/// connector reported it. Shutter.Intake.Forwarder turns it into the intake request; the message text itself is read
/// from the header, never copied here.
Class Shutter.Intake.Forward Extends Ens.Request
{

/// The Ens.MessageHeader id of the failed HL7 message, in the namespace the forwarder runs in.
Property HeaderId As %String(MAXLEN = 20);

/// The production item that delivered to the receiver: the receiver's name in Shutter's site profile.
Property Receiver As %String(MAXLEN = 128);

/// delivery_failed, rejected, uncertain_outcome or unmappable.
Property FailureKind As %String(MAXLEN = 32);

Property FailureText As %String(MAXLEN = 2000);

/// The connector's outcome: unavailable, error, uncertain, rejected, or empty when there was none.
Property FailureOutcome As %String(MAXLEN = 32);

/// The HTTP status the receiver answered, when it answered.
Property FailureHttpStatus As %Integer;

/// The receiver's error code (invalid_transition, duplicate_message, ...), when it gave one.
Property FailureReasonCode As %String(MAXLEN = 100);

/// The service that received the message. Empty: the forwarder reads the header's SourceConfigName.
Property Route As %String(MAXLEN = 128);

Storage Default
{
<Data name="ForwardDefaultData">
<Subscript>"Forward"</Subscript>
<Value name="1">
<Value>HeaderId</Value>
</Value>
<Value name="2">
<Value>Receiver</Value>
</Value>
<Value name="3">
<Value>FailureKind</Value>
</Value>
<Value name="4">
<Value>FailureText</Value>
</Value>
<Value name="5">
<Value>FailureOutcome</Value>
</Value>
<Value name="6">
<Value>FailureHttpStatus</Value>
</Value>
<Value name="7">
<Value>FailureReasonCode</Value>
</Value>
<Value name="8">
<Value>Route</Value>
</Value>
</Data>
<DefaultData>ForwardDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
