/// The Encounter body a snapshot's FHIR evidence rests on. It is kept here and never in the snapshot, so that no case
/// bundle, model view or page carries it. One row per snapshot, read back only by a caller that names its digest.
Class Shutter.Store.FHIRSealedRead Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property SnapshotId As %String(%JSONFIELDNAME = "snapshotId", MAXLEN = 20) [ Required ];

Index SnapshotIdx On SnapshotId [ Unique ];

/// The body as the receiver sent it, decoded to characters. Never exported.
Property EncounterBody As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// Shutter.FHIR.Plan's BodyDigest of the body: bare lower-case hex.
Property BodyDigest As %String(%JSONFIELDNAME = "bodyDigest", MAXLEN = 80);

/// Keeps the body a snapshot was sealed on. A second call for the same snapshot is accepted only with the same body.
ClassMethod Keep(case As Shutter.Store.Case, snapshotId As %String, body As %String) As %Status
{
    If '$ISOBJECT(case) || (case.%Id() = "") Quit $$$ERROR($$$GeneralError, "The sealed read needs a saved case")
    If snapshotId = "" Quit $$$ERROR($$$GeneralError, "The sealed read needs a snapshot")
    If body = "" Quit $$$ERROR($$$GeneralError, "The sealed read needs a body")
    Set digest = ##class(Shutter.FHIR.Plan).BodyDigest(body)
    Set r = ..SnapshotIdxOpen(snapshotId)
    If $ISOBJECT(r) {
        If (r.BodyDigest = digest) && (r.CaseGetObjectId() = case.%Id()) Quit $$$OK
        Quit $$$ERROR($$$GeneralError, "Snapshot " _ snapshotId _ " already has another sealed read")
    }
    Set r = ..%New()
    // By id, not the caller's copy, as Snapshot.Begin does: a save here never writes the case whole.
    Do r.CaseSetObjectId(case.%Id())
    Set r.SnapshotId = snapshotId, r.EncounterBody = body, r.BodyDigest = digest
    Quit r.%Save()
}

/// The body kept for a snapshot, or "" when there is no row, when its digest is not <var>digest</var>, or when the body
/// no longer has the digest the row was kept under.
ClassMethod BodyFor(snapshotId As %String, digest As %String) As %String
{
    If (snapshotId = "") || (digest = "") Quit ""
    Set r = ..SnapshotIdxOpen(snapshotId)
    If '$ISOBJECT(r) Quit ""
    If r.BodyDigest '= digest Quit ""
    If ##class(Shutter.FHIR.Plan).BodyDigest(r.EncounterBody) '= digest Quit ""
    Quit r.EncounterBody
}

Storage Default
{
<Data name="FHIRSealedReadDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>SnapshotId</Value>
</Value>
<Value name="4">
<Value>EncounterBody</Value>
</Value>
<Value name="5">
<Value>BodyDigest</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.FHIRSealedReadD</DataLocation>
<DefaultData>FHIRSealedReadDefaultData</DefaultData>
<IdLocation>^Shutter.Store.FHIRSealedReadD</IdLocation>
<IndexLocation>^Shutter.Store.FHIRSealedReadI</IndexLocation>
<StreamLocation>^Shutter.Store.FHIRSealedReadS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
