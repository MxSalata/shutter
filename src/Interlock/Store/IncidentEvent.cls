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

}
