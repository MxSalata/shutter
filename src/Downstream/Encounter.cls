/// An encounter in the downstream system: its state, its current ward and bed and a version that every applied
/// operation increments. The history of what was applied is in <class>Downstream.Event</class>.
Class Downstream.Encounter Extends %Persistent
{

Property EncounterId As %String(COLLATION = "EXACT", MAXLEN = 64) [ Required ];

Property PatientId As %String(COLLATION = "EXACT", MAXLEN = 64) [ Required ];

Property PatientIdAuthority As %String(COLLATION = "EXACT", MAXLEN = 64) [ Required ];

/// <code>admitted</code> or <code>discharged</code>.
Property State As %String(VALUELIST = ",admitted,discharged") [ Required ];

/// The ward the patient is in. Empty once discharged.
Property Ward As %String(COLLATION = "EXACT", MAXLEN = 64);

/// The bed within the ward (PV1-3's bed component). Empty for a ward-level placement and once discharged.
Property Bed As %String(COLLATION = "EXACT", MAXLEN = 64);

Property Version As %Integer [ InitialExpression = 0, Required ];

/// When the last operation was applied, ISO 8601 UTC.
Property UpdatedAt As %String(MAXLEN = 32);

Index EncounterIdIdx On EncounterId [ Unique ];

/// Who holds a bed: <method>Downstream.Service.Occupant</method> reads it.
Index WardBedIdx On (Ward, Bed);

/// The encounter as the API returns it, with its history oldest first.
Method ToJSON() As %DynamicObject
{
    Set out = {"encounter_id": (..EncounterId), "patient_id": (..PatientId), "patient_id_authority": (..PatientIdAuthority), "state": (..State)}
    If ..Ward = "" { Do out.%Set("ward", "", "null") } Else { Do out.%Set("ward", ..Ward) }
    If ..Bed = "" { Do out.%Set("bed", "", "null") } Else { Do out.%Set("bed", ..Bed) }
    Do out.%Set("version", ..Version, "number")
    Do out.%Set("updated_at", ..UpdatedAt)
    Do out.%Set("epoch", ##class(Downstream.Service).Epoch(), "number")
    // Every applied operation added one version, so the history is versions 1 to Version. Read through the unique
    // index rather than SQL: the API's users have the Downstream_API role and no SQL privileges.
    Set history = []
    For version = 1:1:..Version {
        Set event = ##class(Downstream.Event).EncounterVersionIdxOpen(..EncounterId, version)
        Do:$ISOBJECT(event) history.%Push(event.ToJSON())
    }
    Do out.%Set("history", history)
    Quit out
}

Storage Default
{
<Data name="EncounterDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>EncounterId</Value>
</Value>
<Value name="3">
<Value>PatientId</Value>
</Value>
<Value name="4">
<Value>PatientIdAuthority</Value>
</Value>
<Value name="5">
<Value>State</Value>
</Value>
<Value name="6">
<Value>Ward</Value>
</Value>
<Value name="7">
<Value>Version</Value>
</Value>
<Value name="8">
<Value>UpdatedAt</Value>
</Value>
<Value name="9">
<Value>Bed</Value>
</Value>
</Data>
<DataLocation>^Downstream.EncounterD</DataLocation>
<DefaultData>EncounterDefaultData</DefaultData>
<IdLocation>^Downstream.EncounterD</IdLocation>
<IndexLocation>^Downstream.EncounterI</IndexLocation>
<StreamLocation>^Downstream.EncounterS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
