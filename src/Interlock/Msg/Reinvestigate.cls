/// Reopens a closed case (blocked, escalated or failed): a fresh instance of the case workflow collects fresh
/// evidence and plans again; the old plan and approval stay as history (CONTRACTS 1.6, A3).
Class Interlock.Msg.Reinvestigate Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

Property RequestedBy As %String(MAXLEN = 100);

Property Reason As %String(MAXLEN = 2000);

Storage Default
{
<Data name="ReinvestigateDefaultData">
<Subscript>"Reinvestigate"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>RequestedBy</Value>
</Value>
<Value name="3">
<Value>Reason</Value>
</Value>
</Data>
<DefaultData>ReinvestigateDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
