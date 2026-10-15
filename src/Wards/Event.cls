/// One applied operation in an encounter's history. Rows are only ever inserted: the history is immutable.
Class Wards.Event Extends %Persistent
{

Property EncounterId As %String(COLLATION = "EXACT", MAXLEN = 64) [ Required ];

/// The encounter's version once this operation was applied.
Property VersionAfter As %Integer [ Required ];

Property Event As %String(VALUELIST = ",admit,transfer,discharge,update") [ Required ];

Property Ward As %String(COLLATION = "EXACT", MAXLEN = 64);

/// The source event's time, ISO 8601 UTC. Stored, never used for ordering.
Property EventTime As %String(MAXLEN = 32) [ Required ];

/// When the ward applied it, ISO 8601 UTC.
Property AppliedAt As %String(MAXLEN = 32) [ Required ];

Property OperationKey As %String(COLLATION = "EXACT", MAXLEN = 255) [ Required ];

Index EncounterVersionIdx On (EncounterId, VersionAfter) [ Unique ];

Method %OnBeforeSave(insert As %Boolean) As %Status [ Private, ServerOnly = 1 ]
{
    Quit:'insert $$$ERROR($$$GeneralError, "Ward events are immutable")
    Quit $$$OK
}

Method ToJSON() As %DynamicObject
{
    Set out = {"version_after": (..VersionAfter), "event": (..Event)}
    If ..Ward = "" { Do out.%Set("ward", "", "null") } Else { Do out.%Set("ward", ..Ward) }
    Do out.%Set("event_time", ..EventTime)
    Do out.%Set("applied_at", ..AppliedAt)
    Do out.%Set("operation_key", ..OperationKey)
    Quit out
}

Storage Default
{
<Data name="EventDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>EncounterId</Value>
</Value>
<Value name="3">
<Value>VersionAfter</Value>
</Value>
<Value name="4">
<Value>Event</Value>
</Value>
<Value name="5">
<Value>Ward</Value>
</Value>
<Value name="6">
<Value>EventTime</Value>
</Value>
<Value name="7">
<Value>AppliedAt</Value>
</Value>
<Value name="8">
<Value>OperationKey</Value>
</Value>
</Data>
<DataLocation>^Wards.EventD</DataLocation>
<DefaultData>EventDefaultData</DefaultData>
<IdLocation>^Wards.EventD</IdLocation>
<IndexLocation>^Wards.EventI</IndexLocation>
<StreamLocation>^Wards.EventS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
