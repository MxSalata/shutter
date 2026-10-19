/// Opens a case: sent by the feed process when a delivery failed, its outcome is uncertain, the message could not
/// be mapped, or the operation was withheld (a merge the site's policy keeps for the PAS team, a cancel the receiver
/// cannot reverse).
Class Shutter.Msg.CaseIntake Extends Ens.Request
{

/// The downstream operation as a JSON object (the contract's fields).
Property OperationJSON As %String(MAXLEN = "");

/// delivery_failed, uncertain_outcome, rejected, unmappable, withheld.
Property FailureKind As %String(MAXLEN = 32);

Property FailureText As %String(MAXLEN = 2000);

/// The feed's own reason code for a case with no connector answer: merge (a merge withheld by the site's policy) or
/// cancel_unsupported (a cancel the receiver cannot reverse). The connector's reason code travels in WardResultJSON.
Property FailureReasonCode As %String(MAXLEN = 100);

/// The Ens.MessageHeader id of the HL7 message whose delivery failed.
Property SourceHeaderId As %String(MAXLEN = 20);

/// The production session of the failed delivery.
Property EnsSessionId As %String(MAXLEN = 20);

/// The connector's result, as JSON, for the evidence.
Property WardResultJSON As %String(MAXLEN = "");

/// The investigation mode requested (board, single, rules); empty takes the configured default.
Property Mode As %String(MAXLEN = 16);

Storage Default
{
<Data name="CaseIntakeDefaultData">
<Subscript>"CaseIntake"</Subscript>
<Value name="1">
<Value>OperationJSON</Value>
</Value>
<Value name="2">
<Value>FailureKind</Value>
</Value>
<Value name="3">
<Value>FailureText</Value>
</Value>
<Value name="4">
<Value>SourceHeaderId</Value>
</Value>
<Value name="5">
<Value>EnsSessionId</Value>
</Value>
<Value name="6">
<Value>WardResultJSON</Value>
</Value>
<Value name="7">
<Value>Mode</Value>
</Value>
</Data>
<DefaultData>CaseIntakeDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
