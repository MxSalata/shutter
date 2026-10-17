/// An incident's timeline.
Class Interlock.Store.IncidentEvent Extends %Persistent
{

Property Incident As Interlock.Store.Incident [ Required ];

Property Seq As %Integer [ Required ];

Index IncidentSeq On (Incident, Seq) [ Unique ];

Property At As %String(MAXLEN = 30);

/// state, note, artifact, release
Property Kind As %String(MAXLEN = 16);

Property Text As %String(MAXLEN = 4000);

Property Actor As %String(MAXLEN = 100);

Storage Default
{
<Data name="IncidentEventDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Incident</Value>
</Value>
<Value name="3">
<Value>Seq</Value>
</Value>
<Value name="4">
<Value>At</Value>
</Value>
<Value name="5">
<Value>Kind</Value>
</Value>
<Value name="6">
<Value>Text</Value>
</Value>
<Value name="7">
<Value>Actor</Value>
</Value>
</Data>
<DataLocation>^Interlock.Store.IncidentEventD</DataLocation>
<DefaultData>IncidentEventDefaultData</DefaultData>
<IdLocation>^Interlock.Store.IncidentEventD</IdLocation>
<IndexLocation>^Interlock.Store.IncidentEventI</IndexLocation>
<StreamLocation>^Interlock.Store.IncidentEventS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
