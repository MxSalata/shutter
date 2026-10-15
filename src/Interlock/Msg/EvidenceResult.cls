/// The snapshot the evidence collector took: its id, its digest and the summary the agents and the
/// gate read.
Class Interlock.Msg.EvidenceResult Extends Ens.Response
{

Property SnapshotId As %String(MAXLEN = 20);

Property Digest As %String(MAXLEN = 80);

Property SummaryJSON As %String(MAXLEN = "");

Property ItemCount As %Integer;

Property Error As %String(MAXLEN = 2000);

Storage Default
{
<Data name="EvidenceResultDefaultData">
<Subscript>"EvidenceResult"</Subscript>
<Value name="1">
<Value>SnapshotId</Value>
</Value>
<Value name="2">
<Value>Digest</Value>
</Value>
<Value name="3">
<Value>SummaryJSON</Value>
</Value>
<Value name="4">
<Value>ItemCount</Value>
</Value>
<Value name="5">
<Value>Error</Value>
</Value>
</Data>
<DefaultData>EvidenceResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
