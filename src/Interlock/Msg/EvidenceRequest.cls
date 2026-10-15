/// Asks the evidence collector for a fresh snapshot of a case.
Class Interlock.Msg.EvidenceRequest Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

/// initial, refresh.
Property Reason As %String(MAXLEN = 32) [ InitialExpression = "initial" ];

Storage Default
{
<Data name="EvidenceRequestDefaultData">
<Subscript>"EvidenceRequest"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>Reason</Value>
</Value>
</Data>
<DefaultData>EvidenceRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
