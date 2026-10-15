/// One observation inside a snapshot, with its own digest and provenance.
Class Interlock.Store.SnapshotItem Extends (%Persistent, %JSON.Adaptor)
{

Property Snapshot As Interlock.Store.Snapshot(%JSONFIELDNAME = "snapshotId", %JSONREFERENCE = "ID") [ Required ];

Property Seq As %Integer(%JSONFIELDNAME = "seq") [ Required ];

Index SnapshotSeqIdx On (Snapshot, Seq) [ Unique ];

Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 32, VALUELIST = ",operation,message,validation,ward_state,receipt,later_event,route,error,note");

/// Where it came from: message_store, ward_api, production, validator.
Property Source As %String(%JSONFIELDNAME = "source", MAXLEN = 32);

Property ObservedAt As %String(%JSONFIELDNAME = "observedAt", MAXLEN = 30);

Property Json As %String(%JSONFIELDNAME = "data", MAXLEN = "");

Property Digest As %String(%JSONFIELDNAME = "digest", MAXLEN = 80);

}
