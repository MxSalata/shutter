/// Asks FHIR Out for the one update a binding holds, under one approval and one dispatch decision.
Class Shutter.Msg.FHIRWrite Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

Property PlanId As %String(MAXLEN = 20);

Property ApprovalId As %String(MAXLEN = 20);

Property BindingId As %String(MAXLEN = 20);

/// The dispatch stage's Shutter.Store.GateDecision.
Property DecisionId As %String(MAXLEN = 20);

Storage Default
{
<Data name="FHIRWriteDefaultData">
<Subscript>"FHIRWrite"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>PlanId</Value>
</Value>
<Value name="3">
<Value>ApprovalId</Value>
</Value>
<Value name="4">
<Value>BindingId</Value>
</Value>
<Value name="5">
<Value>DecisionId</Value>
</Value>
</Data>
<DefaultData>FHIRWriteDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
