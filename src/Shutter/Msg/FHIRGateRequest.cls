/// Asks FHIR Gate to judge a plan at one stage. Answered with Shutter.Msg.GateResult.
Class Shutter.Msg.FHIRGateRequest Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

Property PlanId As %String(MAXLEN = 20);

Property Stage As %String(MAXLEN = 16, VALUELIST = ",proposal,dispatch");

Property ApprovalId As %String(MAXLEN = 20);

Property ChainKind As %String(MAXLEN = 16);

/// The id of the dispatch stage's Shutter.Msg.FHIRReadResult; empty at proposal.
Property ReadId As %String(MAXLEN = 20);

Storage Default
{
<Data name="FHIRGateRequestDefaultData">
<Subscript>"FHIRGateRequest"</Subscript>
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
<Value>ChainKind</Value>
</Value>
<Value name="6">
<Value>ReadId</Value>
</Value>
</Data>
<DefaultData>FHIRGateRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
