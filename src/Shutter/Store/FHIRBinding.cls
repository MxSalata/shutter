/// What one plan's FHIR update is bound to: the read it was built on, the body that was approved, and the versions of
/// everything the checks rested on. Sealed when the proposal gate passes, before the task is sent; tied to the approval
/// when the person approves. One row per plan; a row is never rewritten, only tied once to its approval.
Class Shutter.Store.FHIRBinding Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property PlanId As %String(%JSONFIELDNAME = "planId", MAXLEN = 20) [ Required ];

Index PlanIdx On PlanId [ Unique ];

/// Empty until Bind.
Property ApprovalId As %String(%JSONFIELDNAME = "approvalId", MAXLEN = 20);

Index ApprovalIdx On ApprovalId;

Property SnapshotId As %String(%JSONFIELDNAME = "snapshotId", MAXLEN = 20);

Property Receiver As %String(%JSONFIELDNAME = "receiver", MAXLEN = 128);

/// The Encounter's FHIR logical id.
Property EncounterId As %String(%JSONFIELDNAME = "encounterId", MAXLEN = 64);

/// The read's ETag, verbatim: what If-Match carries.
Property ExpectedEtag As %String(%JSONFIELDNAME = "expectedEtag", MAXLEN = 200);

Property BaseVersionId As %String(%JSONFIELDNAME = "baseVersionId", MAXLEN = 100);

/// {"system", "value"}
Property EncounterIdentifierJSON As %String(%JSONFIELDNAME = "encounterIdentifier", MAXLEN = 500);

/// {"reference", "identifier": {"system", "value"}, "etag"}
Property PatientJSON As %String(%JSONFIELDNAME = "patient", MAXLEN = 1000);

/// [{"reference", "ward", "system", "value", "etag"}]: every map entry, in map order.
Property LocationsJSON As %String(%JSONFIELDNAME = "locations", MAXLEN = "");

/// Location/{id}
Property PriorLocation As %String(%JSONFIELDNAME = "priorLocation", MAXLEN = 100);

/// Location/{id}
Property TargetLocation As %String(%JSONFIELDNAME = "targetLocation", MAXLEN = 100);

/// The case's event time, the string the body was built with.
Property EventTime As %String(%JSONFIELDNAME = "eventTime", MAXLEN = 40);

Property OperationId As %String(%JSONFIELDNAME = "operationId", MAXLEN = 32);

Property MarkerSystem As %String(%JSONFIELDNAME = "markerSystem", MAXLEN = 200);

/// The sealed read the body was built from. Never exported.
Property BaseBody As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// The body to send. Never exported.
Property ApprovedBody As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// Shutter.FHIR.Plan's BodyDigest of the approved body: bare lower-case hex.
Property ApprovedBodyDigest As %String(%JSONFIELDNAME = "approvedBodyDigest", MAXLEN = 80);

Property MappingDigest As %String(%JSONFIELDNAME = "mappingDigest", MAXLEN = 80);

Property ProfileVersion As %Integer(%JSONFIELDNAME = "profileVersion");

Property PolicyVersion As %String(%JSONFIELDNAME = "policyVersion", MAXLEN = 32);

Property SealedAt As %String(%JSONFIELDNAME = "sealedAt", MAXLEN = 30);

/// Seals the binding of a plan from what Shutter.FHIR.Proposal's Prepare built on the case's current snapshot. The base
/// body is the snapshot's sealed read, taken by the digest the evidence names, so a binding rests on no other body. A
/// second seal of the same plan answers the first row when it is the same update, and an error otherwise.
ClassMethod Seal(case As Shutter.Store.Case, plan As Shutter.Store.Plan, prepared As %DynamicObject, Output b As Shutter.Store.FHIRBinding) As %Status
{
    Set b = ""
    If '$ISOBJECT(case) || (case.%Id() = "") Quit ..Refuse("the case is not saved")
    If '$ISOBJECT(plan) || (plan.%Id() = "") Quit ..Refuse("the plan is not saved")
    If plan.CaseGetObjectId() '= case.%Id() Quit ..Refuse("the plan is another case's")
    If '..IsObject(prepared) Quit ..Refuse("nothing was prepared")
    Set fhir = prepared.%Get("fhir"), view = prepared.%Get("view"), marker = prepared.%Get("marker"), entry = prepared.%Get("entry")
    If '..IsObject(fhir) || '..IsObject(view) || '..IsObject(marker) || '..IsObject(entry) Quit ..Refuse("what was prepared is incomplete")
    // The receiver's entry carries its settings under fhir; the block itself is accepted too.
    Set block = entry.%Get("fhir")
    If '..IsObject(block) Set block = entry
    Set enc = fhir.%Get("encounter"), pat = fhir.%Get("patient"), map = block.%Get("location_map")
    If '..IsObject(enc) || '..IsObject(pat) Quit ..Refuse("the evidence names no Encounter or no Patient")
    If '$ISOBJECT(map) || 'map.%IsA("%DynamicArray") || (map.%Size() = 0) Quit ..Refuse("the receiver has no location map")
    Set snapshotId = case.CurrentSnapshotGetObjectId()
    If snapshotId = "" Quit ..Refuse("the case has no snapshot")

    Set row = ..%New()
    Do row.CaseSetObjectId(case.%Id())
    Set row.PlanId = plan.%Id(), row.SnapshotId = snapshotId, row.Receiver = case.Receiver
    Set row.EncounterId = ..Text(enc, "id"), row.ExpectedEtag = ..Text(enc, "etag"), row.BaseVersionId = ..Text(enc, "version_id")
    Set row.PriorLocation = ..Text(view, "prior_location"), row.TargetLocation = ..Text(view, "target_location")
    Set row.EventTime = ..Text(prepared, "event_time"), row.OperationId = ..Text(prepared, "operation_id")
    Set row.MarkerSystem = ..Text(marker, "system")
    Set row.ApprovedBody = ..Text(prepared, "body"), row.ApprovedBodyDigest = ..Text(prepared, "body_digest")
    For key = "EncounterId", "ExpectedEtag", "BaseVersionId", "PriorLocation", "TargetLocation", "EventTime", "OperationId", "MarkerSystem", "ApprovedBody" {
        If $PROPERTY(row, key) = "" Return ..Refuse("what was prepared has no " _ key)
    }
    If '$MATCH(row.OperationId, "[0-9a-f]{32}") Quit ..Refuse("the operation id is not 32 lower-case hex")
    If ##class(Shutter.FHIR.Plan).BodyDigest(row.ApprovedBody) '= row.ApprovedBodyDigest Quit ..Refuse("the body does not have the digest it was prepared with")
    Set row.BaseBody = ##class(Shutter.Store.FHIRSealedRead).BodyFor(snapshotId, ..Text(enc, "body_digest"))
    If row.BaseBody = "" Quit ..Refuse("the snapshot has no sealed read with the digest its evidence names")

    Set encounterSystem = ..Text(block.%Get("encounter_identifier"), "system"), patientSystem = ..Text(block.%Get("patient_identifier"), "system")
    If (encounterSystem = "") || (case.EncounterId = "") Quit ..Refuse("the Encounter's identifier is incomplete")
    If (patientSystem = "") || (case.PatientId = "") || (..Text(pat, "reference") = "") Quit ..Refuse("the Patient's reference or identifier is incomplete")
    Set row.EncounterIdentifierJSON = {"system": (encounterSystem), "value": (case.EncounterId)}.%ToJSON()
    Set row.PatientJSON = {"reference": (..Text(pat, "reference")), "identifier": {"system": (patientSystem), "value": (case.PatientId)}, "etag": (..Text(pat, "etag"))}.%ToJSON()

    // Every map entry, in map order, with the ETag its read gave.
    Set read = fhir.%Get("locations"), locations = [], hasPrior = 0, hasTarget = 0
    Set iter = map.%GetIterator()
    While iter.%GetNext(.i, .m) {
        If '..IsObject(m) Return ..Refuse("the location map has an entry that is not an object")
        Set reference = ..Text(m, "location"), identifier = m.%Get("identifier")
        If (reference = "") || (..Text(identifier, "system") = "") || (..Text(identifier, "value") = "") Return ..Refuse("the location map has an incomplete entry")
        Set etag = ""
        If $ISOBJECT(read) && read.%IsA("%DynamicArray") {
            Set it2 = read.%GetIterator()
            While it2.%GetNext(.j, .l) { If ..IsObject(l) && (..Text(l, "reference") = reference) Set etag = ..Text(l, "etag") }
        }
        Do locations.%Push({"reference": (reference), "ward": (..Text(m, "ward")), "system": (..Text(identifier, "system")), "value": (..Text(identifier, "value")), "etag": (etag)})
        Set:reference=row.PriorLocation hasPrior = 1
        Set:reference=row.TargetLocation hasTarget = 1
    }
    If 'hasPrior || 'hasTarget Quit ..Refuse("the location map leaves out the prior or the target location")
    Set row.LocationsJSON = locations.%ToJSON()

    Set row.MappingDigest = ..Text(fhir, "mapping_digest")
    If row.MappingDigest = "" Set row.MappingDigest = ##class(Shutter.Util.Digest).OfObject(block)
    Set row.ProfileVersion = +##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0)
    Set row.PolicyVersion = ..PolicyVersion()
    Set row.SealedAt = ##class(Shutter.Util.Time).NowUTC()

    Set existing = ..ForPlan(row.PlanId)
    If '$ISOBJECT(existing) {
        Set sc = row.%Save()
        If $$$ISOK(sc) { Set b = row  Quit $$$OK }
        // Another job sealed the plan between the look and the save: that row is the plan's binding.
        Set existing = ..ForPlan(row.PlanId)
        If '$ISOBJECT(existing) Quit sc
    }
    If (existing.ApprovedBodyDigest '= row.ApprovedBodyDigest) || (existing.ExpectedEtag '= row.ExpectedEtag) || (existing.CaseGetObjectId() '= case.%Id()) Quit ..Refuse("the plan already has a binding to another update")
    Set b = existing
    Quit $$$OK
}

/// The binding of a plan, or "".
ClassMethod ForPlan(planId As %String) As Shutter.Store.FHIRBinding
{
    If planId = "" Quit ""
    Quit ..PlanIdxOpen(planId)
}

/// Ties the binding to the approval a person gave. Once; the same approval again is accepted, another is an error.
Method Bind(approvalId As %String) As %Status
{
    Set id = ..%Id()
    If id = "" Quit $$$ERROR($$$GeneralError, "The binding is not saved")
    If approvalId = "" Quit $$$ERROR($$$GeneralError, "The binding needs an approval to be tied to")
    // One statement, so that two approvals arriving together cannot both take the row.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "UPDATE Shutter_Store.FHIRBinding SET ApprovalId = ? WHERE ID = ? AND (ApprovalId IS NULL OR ApprovalId = ?)", approvalId, id, approvalId)
    Do ..%Reload()
    If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "SQLCODE " _ rs.%SQLCODE _ ": " _ rs.%Message)
    If ..ApprovalId '= approvalId Quit $$$ERROR($$$GeneralError, "The binding is already tied to approval " _ ..ApprovalId)
    Quit $$$OK
}

/// The binding as Shutter.FHIR.Judge reads it.
Method JudgeBinding() As %DynamicObject
{
    Set patient = ..Parsed(..PatientJSON, 0), bound = ..Parsed(..LocationsJSON, 1), locations = []
    Set iter = bound.%GetIterator()
    While iter.%GetNext(.i, .l) {
        Do locations.%Push({"reference": (l.reference), "checked_identifier": {"system": (l.system), "value": (l.value)}})
    }
    Set identifier = patient.%Get("identifier")
    Set out = {"expected_etag": (..ExpectedEtag), "base_version_id": (..BaseVersionId), "operation_id": (..OperationId), "marker_system": (..MarkerSystem), "encounter_id": (..EncounterId)}
    Set out."encounter_identifier" = ..Parsed(..EncounterIdentifierJSON, 0)
    Set out.patient = {"reference": (patient.reference), "identifier": ($SELECT($ISOBJECT(identifier): identifier, 1: {}))}
    Set out."prior_location" = ..PriorLocation, out."target_location" = ..TargetLocation
    Set out.locations = locations
    Set out."event_time" = ..EventTime, out."server_owned_fields" = []
    Quit out
}

/// The FHIR gate's policy version, read where every FHIR item reads it; "" on an instance without that class.
ClassMethod PolicyVersion() As %String [ Private ]
{
    Set v = ""
    Try {
        Set v = $PARAMETER("Shutter.FHIR.Profile", "POLICYVERSION")
    } Catch ex {
        Set v = ""
    }
    Quit v
}

ClassMethod Refuse(why As %String) As %Status [ Private ]
{
    Quit $$$ERROR($$$GeneralError, "The update cannot be sealed: " _ why)
}

ClassMethod IsObject(value) As %Boolean [ Private ]
{
    Quit $ISOBJECT(value) && value.%IsA("%DynamicObject")
}

/// A member that is a string, or "".
ClassMethod Text(obj, key As %String) As %String [ Private ]
{
    If '..IsObject(obj) || (obj.%GetTypeOf(key) '= "string") Quit ""
    Quit obj.%Get(key)
}

/// Stored JSON as an object or an array; an empty one when the text is not that.
ClassMethod Parsed(text As %String, array As %Boolean) As %DynamicAbstractObject [ Private ]
{
    Set empty = $SELECT(array: [], 1: {}), out = ""
    Try {
        Set out = ##class(%DynamicAbstractObject).%FromJSON(text)
    } Catch ex {
        Set out = ""
    }
    If '$ISOBJECT(out) || 'out.%IsA($SELECT(array: "%DynamicArray", 1: "%DynamicObject")) Quit empty
    Quit out
}

Storage Default
{
<Data name="FHIRBindingDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>PlanId</Value>
</Value>
<Value name="4">
<Value>ApprovalId</Value>
</Value>
<Value name="5">
<Value>SnapshotId</Value>
</Value>
<Value name="6">
<Value>Receiver</Value>
</Value>
<Value name="7">
<Value>EncounterId</Value>
</Value>
<Value name="8">
<Value>ExpectedEtag</Value>
</Value>
<Value name="9">
<Value>BaseVersionId</Value>
</Value>
<Value name="10">
<Value>EncounterIdentifierJSON</Value>
</Value>
<Value name="11">
<Value>PatientJSON</Value>
</Value>
<Value name="12">
<Value>LocationsJSON</Value>
</Value>
<Value name="13">
<Value>PriorLocation</Value>
</Value>
<Value name="14">
<Value>TargetLocation</Value>
</Value>
<Value name="15">
<Value>EventTime</Value>
</Value>
<Value name="16">
<Value>OperationId</Value>
</Value>
<Value name="17">
<Value>MarkerSystem</Value>
</Value>
<Value name="18">
<Value>BaseBody</Value>
</Value>
<Value name="19">
<Value>ApprovedBody</Value>
</Value>
<Value name="20">
<Value>ApprovedBodyDigest</Value>
</Value>
<Value name="21">
<Value>MappingDigest</Value>
</Value>
<Value name="22">
<Value>ProfileVersion</Value>
</Value>
<Value name="23">
<Value>PolicyVersion</Value>
</Value>
<Value name="24">
<Value>SealedAt</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.FHIRBindingD</DataLocation>
<DefaultData>FHIRBindingDefaultData</DefaultData>
<IdLocation>^Shutter.Store.FHIRBindingD</IdLocation>
<IndexLocation>^Shutter.Store.FHIRBindingI</IndexLocation>
<StreamLocation>^Shutter.Store.FHIRBindingS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
