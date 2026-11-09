/// The answer to a case intake: which case, and whether it was opened by this intake.
Class Shutter.Msg.CaseStarted Extends Ens.Response
{

Property CaseId As %String(MAXLEN = 32);

Property Opened As %Boolean;

Property State As %String(MAXLEN = 32);

/// The intake was Shutter's own resend (v1.53): no case was opened; CaseId is the message's earlier case, or empty.
Property OwnResend As %Boolean;

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
<Value name="4">
<Value>OwnResend</Value>
</Value>
</Data>
<DefaultData>CaseStartedDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
