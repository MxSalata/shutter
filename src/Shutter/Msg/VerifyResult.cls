/// What the verifier established: verified, superseded_after, unresolved or failed.
Class Shutter.Msg.VerifyResult Extends Ens.Response
{

Property Outcome As %String(MAXLEN = 32);

Property VerificationId As %String(MAXLEN = 20);

Property Summary As %String(MAXLEN = 2000);

Property DetailJSON As %String(MAXLEN = "");

Property Error As %String(MAXLEN = 2000);

Storage Default
{
<Data name="VerifyResultDefaultData">
<Subscript>"VerifyResult"</Subscript>
<Value name="1">
<Value>Outcome</Value>
</Value>
<Value name="2">
<Value>VerificationId</Value>
</Value>
<Value name="3">
<Value>Summary</Value>
</Value>
<Value name="4">
<Value>DetailJSON</Value>
</Value>
<Value name="5">
<Value>Error</Value>
</Value>
</Data>
<DefaultData>VerifyResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
