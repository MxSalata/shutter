/// Asks the verifier to establish what holds at the receiver after an attempt, or after a
/// non-write disposition.
Class Interlock.Msg.VerifyRequest Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

Property PlanId As %String(MAXLEN = 20);

Property AttemptId As %String(MAXLEN = 20);

Storage Default
{
<Data name="VerifyRequestDefaultData">
<Subscript>"VerifyRequest"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>PlanId</Value>
</Value>
<Value name="3">
<Value>AttemptId</Value>
</Value>
</Data>
<DefaultData>VerifyRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
