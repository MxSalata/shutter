/// One observation inside a snapshot, with its own digest and provenance.
Class Shutter.Store.SnapshotItem Extends (%Persistent, %JSON.Adaptor)
{

Property Snapshot As Shutter.Store.Snapshot(%JSONFIELDNAME = "snapshotId", %JSONREFERENCE = "ID") [ Required ];

Property Seq As %Integer(%JSONFIELDNAME = "seq") [ Required ];

Index SnapshotSeqIdx On (Snapshot, Seq) [ Unique ];

Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 32, VALUELIST = ",operation,message,validation,ward_state,receipt,later_event,route,error,note,source,bed_conflict,pending_messages");

/// Where it came from: message_store, ward_api, production, validator.
Property Source As %String(%JSONFIELDNAME = "source", MAXLEN = 32);

Property ObservedAt As %String(%JSONFIELDNAME = "observedAt", MAXLEN = 30);

Property Json As %String(%JSONFIELDNAME = "data", MAXLEN = "");

Property Digest As %String(%JSONFIELDNAME = "digest", MAXLEN = 80);

Storage Default
{
<Data name="SnapshotItemDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Snapshot</Value>
</Value>
<Value name="3">
<Value>Seq</Value>
</Value>
<Value name="4">
<Value>Kind</Value>
</Value>
<Value name="5">
<Value>Source</Value>
</Value>
<Value name="6">
<Value>ObservedAt</Value>
</Value>
<Value name="7">
<Value>Json</Value>
</Value>
<Value name="8">
<Value>Digest</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.SnapshotItemD</DataLocation>
<DefaultData>SnapshotItemDefaultData</DefaultData>
<IdLocation>^Shutter.Store.SnapshotItemD</IdLocation>
<IndexLocation>^Shutter.Store.SnapshotItemI</IndexLocation>
<StreamLocation>^Shutter.Store.SnapshotItemS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
