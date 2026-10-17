/// The answer to a case intake: which case, and whether it was opened by this intake.
Class Shutter.Msg.CaseStarted Extends Ens.Response
{

Property CaseId As %String(MAXLEN = 32);

Property Opened As %Boolean;

Property State As %String(MAXLEN = 32);

Storage Default
{
<Data name="CaseStartedDefaultData">
<Subscript>"CaseStarted"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>Opened</Value>
</Value>
<Value name="3">
<Value>State</Value>
</Value>
</Data>
<DefaultData>CaseStartedDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
