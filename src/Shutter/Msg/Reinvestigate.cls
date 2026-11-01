/// Reopens a closed case (blocked, escalated or failed): a fresh instance of the case workflow collects fresh
/// evidence and plans again; the old plan and approval stay as history (CONTRACTS 1.6, A3).
Class Shutter.Msg.Reinvestigate Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

Property RequestedBy As %String(MAXLEN = 100);

Property Reason As %String(MAXLEN = 2000);

/// Convene the board on the fresh evidence whatever the site policy says (a judge's request, v1.34).
Property ForceBoard As %Boolean [ InitialExpression = 0 ];

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
<Value name="4">
<Value>ForceBoard</Value>
</Value>
</Data>
<DefaultData>ReinvestigateDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
