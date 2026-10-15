/// An encounter in the synthetic ward system: its state, its current ward and a version that every applied
/// operation increments. The history of what was applied is in <class>Wards.Event</class>.
Class Wards.Encounter Extends %Persistent
{

Property EncounterId As %String(COLLATION = "EXACT", MAXLEN = 64) [ Required ];

Property PatientId As %String(COLLATION = "EXACT", MAXLEN = 64) [ Required ];

Property PatientIdAuthority As %String(COLLATION = "EXACT", MAXLEN = 64) [ Required ];

/// <code>admitted</code> or <code>discharged</code>.
Property State As %String(VALUELIST = ",admitted,discharged") [ Required ];

/// The ward the patient is in. Empty once discharged.
Property Ward As %String(COLLATION = "EXACT", MAXLEN = 64);

Property Version As %Integer [ InitialExpression = 0, Required ];

/// When the last operation was applied, ISO 8601 UTC.
Property UpdatedAt As %String(MAXLEN = 32);

Index EncounterIdIdx On EncounterId [ Unique ];

/// The encounter as the API returns it, with its history oldest first.
Method ToJSON() As %DynamicObject
{
    Set out = {"encounter_id": (..EncounterId), "patient_id": (..PatientId), "patient_id_authority": (..PatientIdAuthority), "state": (..State)}
    If ..Ward = "" { Do out.%Set("ward", "", "null") } Else { Do out.%Set("ward", ..Ward) }
    Do out.%Set("version", ..Version, "number")
    Do out.%Set("updated_at", ..UpdatedAt)
    Set history = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Wards.Event WHERE EncounterId = ? ORDER BY VersionAfter", ..EncounterId)
    While rs.%Next() {
        Set event = ##class(Wards.Event).%OpenId(rs.%Get("ID"))
        Do:$ISOBJECT(event) history.%Push(event.ToJSON())
    }
    Do out.%Set("history", history)
    Quit out
}

}
