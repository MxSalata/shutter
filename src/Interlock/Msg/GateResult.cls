/// The gate's decision: pass, block or unknown, with every check and its reason code.
Class Interlock.Msg.GateResult Extends Ens.Response
{

Property Outcome As %String(MAXLEN = 16);

Property DecisionId As %String(MAXLEN = 20);

Property PolicyVersion As %String(MAXLEN = 32);

Property ChecksJSON As %String(MAXLEN = "");

Property Summary As %String(MAXLEN = 2000);

Property Error As %String(MAXLEN = 2000);

Storage Default
{
<Data name="GateResultDefaultData">
<Subscript>"GateResult"</Subscript>
<Value name="1">
<Value>Outcome</Value>
</Value>
<Value name="2">
<Value>DecisionId</Value>
</Value>
<Value name="3">
<Value>PolicyVersion</Value>
</Value>
<Value name="4">
<Value>ChecksJSON</Value>
</Value>
<Value name="5">
<Value>Summary</Value>
</Value>
<Value name="6">
<Value>Error</Value>
</Value>
</Data>
<DefaultData>GateResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
