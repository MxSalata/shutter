/// Asks the gate to evaluate a plan at a stage: proposal, approval or dispatch.
Class Interlock.Msg.GateRequest Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

Property PlanId As %String(MAXLEN = 20);

Property Stage As %String(MAXLEN = 16, VALUELIST = ",proposal,approval,dispatch") [ InitialExpression = "proposal" ];

/// The approval the dispatch relies on, for the authorization check.
Property ApprovalId As %String(MAXLEN = 20);

/// The receiver's version as last observed, for the concurrency check at dispatch.
Property ReceiverVersion As %Integer;

/// The receiver's epoch as last observed (it changes at every reset).
/// The production item the write goes to, for the site profile's tier.
Property Receiver As %String(MAXLEN = 128);

Property ReceiverEpoch As %Integer;

Storage Default
{
<Data name="GateRequestDefaultData">
<Subscript>"GateRequest"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>PlanId</Value>
</Value>
<Value name="3">
<Value>Stage</Value>
</Value>
<Value name="4">
<Value>ApprovalId</Value>
</Value>
<Value name="5">
<Value>ReceiverVersion</Value>
</Value>
<Value name="6">
<Value>ReceiverEpoch</Value>
</Value>
<Value name="7">
<Value>Receiver</Value>
</Value>
</Data>
<DefaultData>GateRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
