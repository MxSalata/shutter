/// The proposal builder for a FHIR R4 receiver: from a case, its plan's digest, the evidence's fhir view, the Encounter
/// as it was read and the receiver's entry of the site profile to everything the one update needs: the plan builder's
/// view, the event time, the operation id, the marker, the exact body and its digest.
///
/// Pure: class methods only, no storage, no globals, no network and no clock, and it never throws. The same inputs give
/// the same body, so the gate at the proposal, the seal of the binding and the gate at the dispatch can each build the
/// update again and compare what they got.
Class Shutter.FHIR.Proposal [ Abstract ]
{

/// Prepares the update. Returns "" with <var>prepared</var> =
/// {"view", "event_time", "operation_id", "marker", "body", "body_digest", "detail", "fhir", "entry"}, or a FHIR_* reason
/// code with <var>prepared</var> = {"reason", "path"} (and "detail" when the plan builder gave the refusal) and no body.
/// <ul>
/// <li><var>case</var>: the case; its Bed, EventTime and CaseId are read.</li>
/// <li><var>planDigest</var>: the digest of the plan the update belongs to; one of the three parts of the operation id.</li>
/// <li><var>fhir</var>: the evidence's fhir view (summary.fhir): its message's prior_ward and target_ward and its
/// encounter's etag are read.</li>
/// <li><var>encounterBody</var>: the Encounter as it was read, as characters.</li>
/// <li><var>entry</var>: the receiver's whole entry of the site profile; the fhir block itself is accepted too.</li>
/// </ul>
/// The steps, the first refusal winning: a message that names a bed (FHIR_BED_MOVE_UNSUPPORTED, path PV1-3); a prior
/// ward (PV1-6) or a target ward (PV1-3) the map does not hold (FHIR_LOCATION_UNMAPPED); then whatever
/// Shutter.FHIR.Plan.Build refuses, with its own reason and path.
ClassMethod Prepare(case As Shutter.Store.Case, planDigest As %String, fhir As %DynamicObject, encounterBody As %String, entry As %DynamicObject, Output prepared As %DynamicObject) As %String
{
    Set prepared = {}
    Try {
        Set code = ..Steps(case, planDigest, fhir, encounterBody, entry, .prepared)
    } Catch err {
        Set code = "FHIR_SHAPE_UNSUPPORTED", prepared = {"reason": "error", "path": "", "error": (err.DisplayString())}
    }
    Quit code
}

/// Prepare's steps in order.
ClassMethod Steps(case As Shutter.Store.Case, planDigest As %String, fhir As %DynamicObject, encounterBody As %String, entry As %DynamicObject, Output prepared As %DynamicObject) As %String [ Private ]
{
    Set prepared = {}
    Quit:'$ISOBJECT(case) ..Refuse("FHIR_SHAPE_UNSUPPORTED", "no_case", "", .prepared)

    // An Encounter's version does not reserve a bed, so a message that names one is never written as a ward move.
    Quit:case.Bed'="" ..Refuse("FHIR_BED_MOVE_UNSUPPORTED", "bed", "PV1-3", .prepared)

    // The inputs: the evidence's view and the receiver's settings.
    Set message = $SELECT(..IsObject(fhir): fhir.%Get("message"), 1: "")
    Set encounter = $SELECT(..IsObject(fhir): fhir.%Get("encounter"), 1: "")
    If ('..IsObject(message)) || ('..IsObject(encounter)) Quit ..Refuse("FHIR_SHAPE_UNSUPPORTED", "no_fhir_view", "", .prepared)
    Set block = $SELECT(..IsObject(entry): entry.%Get("fhir"), 1: "")
    Set:'..IsObject(block) block = entry
    If ('..IsObject(block)) || (block.%GetTypeOf("location_map") '= "array") {
        Quit ..Refuse("FHIR_SHAPE_UNSUPPORTED", "no_fhir_entry", "", .prepared)
    }
    Set system = $SELECT(..IsObject(block.%Get("marker")): ..Text(block.%Get("marker"), "system"), 1: "")
    Quit:system="" ..Refuse("FHIR_SHAPE_UNSUPPORTED", "no_marker_system", "", .prepared)

    // The wards of the message, each to its Location in the map.
    Set prior = ##class(Shutter.FHIR.Profile).LocationOf(block, ..Text(message, "prior_ward"))
    Quit:'$ISOBJECT(prior) ..Refuse("FHIR_LOCATION_UNMAPPED", "prior", "PV1-6", .prepared)
    Set target = ##class(Shutter.FHIR.Profile).LocationOf(block, ..Text(message, "target_ward"))
    Quit:'$ISOBJECT(target) ..Refuse("FHIR_LOCATION_UNMAPPED", "target", "PV1-3", .prepared)

    // The plan builder's view: the two Locations and the map at ward level, in the map's order.
    Set map = [], it = block.%Get("location_map").%GetIterator()
    While it.%GetNext(.j, .e) {
        Continue:'..IsObject(e)
        Do map.%Push({"ward": (..Text(e, "ward")), "location": (..Text(e, "location"))})
    }
    Set view = {"prior_location": (..Text(prior, "location")), "target_location": (..Text(target, "location")), "location_map": (map)}

    // The operation id names this case, this plan and the version the update is conditional on, and nothing else.
    Set eventTime = case.EventTime
    Set operationId = $EXTRACT(##class(Shutter.FHIR.Plan).BodyDigest(case.CaseId _ "|" _ planDigest _ "|" _ ..Text(encounter, "etag")), 1, 32)
    Set marker = {"system": (system), "code": (operationId)}

    Set code = ##class(Shutter.FHIR.Plan).Build(encounterBody, view, eventTime, marker, .body, .detail)
    If code '= "" {
        Set prepared = {"reason": (..Text(detail, "reason")), "path": (..Text(detail, "path")), "detail": (detail)}
        Quit code
    }
    Set prepared = {"view": (view), "event_time": (eventTime), "operation_id": (operationId), "marker": (marker)}
    Set prepared.body = body, prepared."body_digest" = ##class(Shutter.FHIR.Plan).BodyDigest(body)
    Set prepared.detail = detail, prepared.fhir = fhir, prepared.entry = entry
    Quit ""
}

/// A refusal of this class's own: the code, with why and where.
ClassMethod Refuse(code As %String, reason As %String, path As %String, Output prepared As %DynamicObject) As %String [ Private ]
{
    Set prepared = {"reason": (reason), "path": (path)}
    Quit code
}

/// True for a JSON object (not an array, not a string).
ClassMethod IsObject(value) As %Boolean [ Private ]
{
    Quit $ISOBJECT(value) && value.%IsA("%Library.DynamicObject")
}

/// The string under a key, "" when the key is absent or holds anything but a string.
ClassMethod Text(obj As %DynamicObject, key As %String) As %String [ Private ]
{
    If '..IsObject(obj) Quit ""
    Quit $SELECT(obj.%GetTypeOf(key) = "string": obj.%Get(key), 1: "")
}

}
