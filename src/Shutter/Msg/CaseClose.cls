/// Closes a case the team handled by hand (T31, 2.6): sent by the REST API to the Case Workflow item, where a fresh
/// instance resolves an escalated, blocked or failed case with disposition handled_by_hand and cancels its open
/// approval task, if any. Reinvestigate stays for a correction the receiver's state can prove.
Class Shutter.Msg.CaseClose Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

/// What the team did, in the person's words; the case event names it.
Property Reason As %String(MAXLEN = 2000);

/// The signed-in user who marked the case handled.
Property Actor As %String(MAXLEN = 100);

/// The case version the caller saw (optional): the close is refused when the case moved on.
Property ExpectedVersion As %Integer;

Storage Default
{
<Data name="CaseCloseDefaultData">
<Subscript>"CaseClose"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>Reason</Value>
</Value>
<Value name="3">
<Value>Actor</Value>
</Value>
</Data>
<DefaultData>CaseCloseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
