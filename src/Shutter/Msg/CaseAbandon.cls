/// Abandons a case the workflow left in a working state (CONTRACTS 5): sent by the REST API to the Case Workflow
/// item, where a fresh instance fails the case with disposition abandoned (Shutter.Store.Case.Abandon) and cancels its
/// open approval task, if any. The route has checked that nothing of the case's workflow is in flight; a closed case is
/// marked handled (CaseClose) or reopened (Reinvestigate) instead.
Class Shutter.Msg.CaseAbandon Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

/// Why the case is given up, in the approver's words; the case event names it.
Property Reason As %String(MAXLEN = 2000);

/// The signed-in approver who abandoned the case.
Property Actor As %String(MAXLEN = 100);

/// The case version the caller saw (optional): the abandon is refused when the case moved on.
Property ExpectedVersion As %Integer;

Storage Default
{
<Data name="CaseAbandonDefaultData">
<Subscript>"CaseAbandon"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>Reason</Value>
</Value>
<Value name="3">
<Value>Actor</Value>
</Value>
<Value name="4">
<Value>ExpectedVersion</Value>
</Value>
</Data>
<DefaultData>CaseAbandonDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
