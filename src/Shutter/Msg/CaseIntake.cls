/// Opens a case: sent by the feed process when a delivery failed, its outcome is uncertain, the message could not
/// be mapped, or the operation was withheld (a merge the site's policy keeps for the PAS team, a cancel the receiver
/// cannot reverse); and by the case intake process for a failure another production reported (CONTRACTS 11), which
/// names its receiver and where the original message lives.
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

/// The production item the delivery went to (the receiver); empty means the case workflow's own connector.
Property Receiver As %String(MAXLEN = 128);

/// Where the original message lives when the failure came from another production (CONTRACTS 11): its namespace, the
/// production and the route (the item) that received it there, and its Ens.MessageHeader id in that namespace.
/// SourceHeaderId is then Shutter's own stored copy. Empty for the feed's own cases.
Property SourceNamespace As %String(MAXLEN = 64);

Property SourceProduction As %String(MAXLEN = 128);

Property SourceRoute As %String(MAXLEN = 128);

Property OriginHeaderId As %String(MAXLEN = 40);

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
<Value name="8">
<Value>FailureReasonCode</Value>
</Value>
<Value name="9">
<Value>Receiver</Value>
</Value>
<Value name="10">
<Value>SourceNamespace</Value>
</Value>
<Value name="11">
<Value>SourceProduction</Value>
</Value>
<Value name="12">
<Value>SourceRoute</Value>
</Value>
<Value name="13">
<Value>OriginHeaderId</Value>
</Value>
</Data>
<DefaultData>CaseIntakeDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
