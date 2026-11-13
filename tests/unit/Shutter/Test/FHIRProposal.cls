/// The proposal builder for a FHIR receiver (Shutter.FHIR.Proposal) and the reason codes the FHIR path can give. The
/// builder is pure, so its tests save nothing: the case is an unsaved object, the read is the plan builder's measured
/// seed (Shutter.Test.FHIRPlan: Encounter enc-1, version "1", WARD-A active) and the entry is the demo's shape. The last
/// test reads the reason store as an install seeded it from knowledge/block-reasons.json.
Class Shutter.Test.FHIRProposal Extends %UnitTest.TestCase
{

Parameter EVENTTIME = "2026-11-07T10:15:00Z";

Parameter PLANDIGEST = "sha256:1f0e2d3c4b5a69788796a5b4c3d2e1f00112233445566778899aabbccddeeff0";

/// Two calls with the same inputs give the same body, digest, operation id and marker; and the body is the plan
/// builder's own for the view, the event time and the marker that came back.
Method TestTheSameInputsGiveTheSameBody()
{
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(..Case(), ..#PLANDIGEST, ..Fhir(), ..Seed(), ..Entry(), .first)
    Do $$$AssertEquals(code, "", "the seed prepares (" _ first.%ToJSON() _ ")")
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(..Case(), ..#PLANDIGEST, ..Fhir(), ..Seed(), ..Entry(), .second)
    Do $$$AssertEquals(code, "", "and prepares again")
    Do $$$AssertTrue(first.body '= "", "with a body")
    Do $$$AssertEquals(second.body, first.body, "the same body")
    Do $$$AssertEquals(second."body_digest", first."body_digest", "the same digest")
    Do $$$AssertEquals(second."operation_id", first."operation_id", "the same operation id")
    Do $$$AssertEquals(second.marker.%ToJSON(), first.marker.%ToJSON(), "the same marker")
    Do $$$AssertEquals(first."body_digest", ##class(Shutter.FHIR.Plan).BodyDigest(first.body), "the digest is the body's")

    Do $$$AssertEquals(first.view."prior_location", "Location/ward-a", "the prior ward's Location")
    Do $$$AssertEquals(first.view."target_location", "Location/ward-b", "the target ward's Location")
    Do $$$AssertEquals(first.view."location_map".%ToJSON(), "[{""ward"":""WARD-A"",""location"":""Location/ward-a""},{""ward"":""WARD-B"",""location"":""Location/ward-b""}]", "the map at ward level, in its order")
    Do $$$AssertEquals(first."event_time", ..#EVENTTIME, "the case's event time")
    Do $$$AssertEquals(first.marker.system, "urn:shutter:recovery", "the entry's marker system")
    Do $$$AssertEquals(first.marker.code, first."operation_id", "the marker's code is the operation id")
    Do $$$AssertEquals(first.fhir.encounter.etag, "W/""1""", "the fhir view comes back")
    Do $$$AssertEquals(first.entry.name, "FHIR Ward Out", "the entry comes back")
    Do $$$AssertEquals(first.detail."appended_index", 1, "with the plan builder's detail")

    Set code = ##class(Shutter.FHIR.Plan).Build(..Seed(), first.view, first."event_time", first.marker, .body, .detail)
    Do $$$AssertEquals(code, "", "the plan builder builds from what came back")
    Do $$$AssertEquals(first.body, body, "and gives the prepared body")
    Do $$$AssertTrue(first.body [ ("""code"":""" _ first."operation_id" _ """"), "which carries the operation id as its marker")

    // The fhir block alone is read as the entry is.
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(..Case(), ..#PLANDIGEST, ..Fhir(), ..Seed(), ..Entry().fhir, .third)
    Do $$$AssertEquals(code _ " " _ third.body, " " _ first.body, "the block alone gives the same body")
}

/// A message that names a bed stops before anything is built: the code, the field, and no body.
Method TestABedStopsTheMove()
{
    Set case = ..Case()
    Set case.Bed = "B-12"
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(case, ..#PLANDIGEST, ..Fhir(), ..Seed(), ..Entry(), .prepared)
    Do $$$AssertEquals(code, "FHIR_BED_MOVE_UNSUPPORTED", "a bed is refused")
    Do $$$AssertEquals(prepared.path, "PV1-3", "at PV1-3")
    Do $$$AssertEquals(prepared.reason, "bed", "for the bed")
    Do $$$AssertEquals(prepared.%GetTypeOf("body"), "unassigned", "and no body")
    Do $$$AssertEquals(prepared.%GetTypeOf("operation_id"), "unassigned", "and no operation id")

    // The bed comes first: before a ward the map does not hold and before a body that is no Encounter.
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(case, ..#PLANDIGEST, ..Fhir("WARD-A", "WARD-Z"), "not json", ..Entry(), .prepared)
    Do $$$AssertEquals(code, "FHIR_BED_MOVE_UNSUPPORTED", "a bed is refused first")
}

/// The operation id is 32 lower-case hex characters, the start of the digest of the case, the plan and the version,
/// and it changes with each of the three.
Method TestTheOperationIdIs32Hex()
{
    Set case = ..Case()
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(case, ..#PLANDIGEST, ..Fhir(), ..Seed(), ..Entry(), .prepared)
    Do $$$AssertEquals(code, "", "the seed prepares")
    Set id = prepared."operation_id"
    Do $$$AssertTrue($MATCH(id, "^[0-9a-f]{32}$"), "32 lower-case hex characters: " _ id)
    Set want = $EXTRACT(##class(Shutter.FHIR.Plan).BodyDigest(case.CaseId _ "|" _ ..#PLANDIGEST _ "|W/""1"""), 1, 32)
    Do $$$AssertEquals(id, want, "the first 32 of the digest of case, plan and ETag")

    Set other = ..Case()
    Set other.CaseId = "UT-FHIRPROP-2"
    Do ##class(Shutter.FHIR.Proposal).Prepare(other, ..#PLANDIGEST, ..Fhir(), ..Seed(), ..Entry(), .p2)
    Do $$$AssertNotEquals(p2."operation_id", id, "another case, another id")
    Do ##class(Shutter.FHIR.Proposal).Prepare(case, "sha256:another", ..Fhir(), ..Seed(), ..Entry(), .p3)
    Do $$$AssertNotEquals(p3."operation_id", id, "another plan, another id")
    Set fhir = ..Fhir()
    Set fhir.encounter.etag = "W/""2"""
    Do ##class(Shutter.FHIR.Proposal).Prepare(case, ..#PLANDIGEST, fhir, ..Seed(), ..Entry(), .p4)
    Do $$$AssertNotEquals(p4."operation_id", id, "another version, another id")
    Do $$$AssertTrue($MATCH(p4."operation_id", "^[0-9a-f]{32}$"), "still 32 lower-case hex characters")
}

/// A ward the map does not hold gives FHIR_LOCATION_UNMAPPED, naming the field of the message, and no body.
Method TestAnUnmappedWardGivesItsCode()
{
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(..Case(), ..#PLANDIGEST, ..Fhir("WARD-A", "WARD-Z"), ..Seed(), ..Entry(), .prepared)
    Do $$$AssertEquals(code, "FHIR_LOCATION_UNMAPPED", "an unmapped target ward")
    Do $$$AssertEquals(prepared.reason _ " " _ prepared.path, "target PV1-3", "named as the target, PV1-3")
    Do $$$AssertEquals(prepared.%GetTypeOf("body"), "unassigned", "and no body")

    Set code = ##class(Shutter.FHIR.Proposal).Prepare(..Case(), ..#PLANDIGEST, ..Fhir("WARD-Z", "WARD-B"), ..Seed(), ..Entry(), .prepared)
    Do $$$AssertEquals(code, "FHIR_LOCATION_UNMAPPED", "an unmapped prior ward")
    Do $$$AssertEquals(prepared.reason _ " " _ prepared.path, "prior PV1-6", "named as the prior, PV1-6")

    Set code = ##class(Shutter.FHIR.Proposal).Prepare(..Case(), ..#PLANDIGEST, ..Fhir("", "WARD-B"), ..Seed(), ..Entry(), .prepared)
    Do $$$AssertEquals(code, "FHIR_LOCATION_UNMAPPED", "a message with no prior ward")
    Do $$$AssertEquals(prepared.path, "PV1-6", "named at PV1-6")
}

/// What the plan builder refuses comes through with its code, its reason and its path, and no body.
Method TestBuildsRefusalComesThrough()
{
    Set seed = $REPLACE(..Seed(), """status"":""in-progress""", """status"":""finished""")
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(..Case(), ..#PLANDIGEST, ..Fhir(), seed, ..Entry(), .prepared)
    Do $$$AssertEquals(code, "FHIR_STATUS_NOT_IN_PROGRESS", "a finished Encounter")
    Do $$$AssertEquals(prepared.reason _ " " _ prepared.path, "status /status", "with the builder's reason and path")
    Do $$$AssertEquals(prepared.%GetTypeOf("body"), "unassigned", "and no body")
    Do $$$AssertEquals(prepared.detail.path, "/status", "the builder's detail is kept")

    Set code = ##class(Shutter.FHIR.Proposal).Prepare(..Case(), ..#PLANDIGEST, ..Fhir(), "not json", ..Entry(), .prepared)
    Do $$$AssertEquals(code _ " " _ prepared.reason, "FHIR_SHAPE_UNSUPPORTED not_json", "a body that is not JSON")

    // The patient is on WARD-A and the message says they came from WARD-B: the open entry is not the prior Location.
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(..Case(), ..#PLANDIGEST, ..Fhir("WARD-B", "WARD-A"), ..Seed(), ..Entry(), .prepared)
    Do $$$AssertTrue($EXTRACT(code, 1, 5) = "FHIR_", "a move from another ward than the open one is refused: " _ code)
    Do $$$AssertEquals(prepared.%GetTypeOf("body"), "unassigned", "and no body")

    Set case = ..Case()
    Set case.EventTime = "2026-11-07 10:15:00"
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(case, ..#PLANDIGEST, ..Fhir(), ..Seed(), ..Entry(), .prepared)
    Do $$$AssertEquals(code _ " " _ prepared.reason, "FHIR_SHAPE_UNSUPPORTED event_time", "an event time with no offset")

    // Inputs that are not there are a refusal, never an error.
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(..Case(), ..#PLANDIGEST, "", ..Seed(), ..Entry(), .prepared)
    Do $$$AssertEquals(code _ " " _ prepared.reason, "FHIR_SHAPE_UNSUPPORTED no_fhir_view", "no fhir view")
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(..Case(), ..#PLANDIGEST, ..Fhir(), ..Seed(), {"name": "FHIR Ward Out"}, .prepared)
    Do $$$AssertEquals(code _ " " _ prepared.reason, "FHIR_SHAPE_UNSUPPORTED no_fhir_entry", "an entry with no fhir block")
    Set code = ##class(Shutter.FHIR.Proposal).Prepare("", ..#PLANDIGEST, ..Fhir(), ..Seed(), ..Entry(), .prepared)
    Do $$$AssertEquals(code _ " " _ prepared.reason, "FHIR_SHAPE_UNSUPPORTED no_case", "no case")
}

/// Every reason code of the FHIR path is in the reason store after an install, with its words.
Method TestEveryCodeOf211IsInTheStore()
{
    Set codes = ##class(%DynamicArray).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Codes").Data)
    Do $$$AssertEquals(codes.%Size(), 53, "the list holds every code")
    Set missing = "", bare = ""
    For i = 0:1:codes.%Size() - 1 {
        Set code = codes.%Get(i), r = ##class(Shutter.Store.BlockReason).ByCode(code)
        If '$ISOBJECT(r) {
            Set missing = missing _ " " _ code
            Continue
        }
        If (r.Title = "") || (r.Text = "") || (r.Prerequisite = "") || (r.NextAction = "") || (r.Owner = "") || (r.ReevaluateWhen = "") Set bare = bare _ " " _ code
    }
    Do $$$AssertEquals(missing, "", "every code is in the store")
    Do $$$AssertEquals(bare, "", "each with its title, prerequisite, next action, owner, re-evaluation and text")
    Set r = ##class(Shutter.Store.BlockReason).ByCode("FHIR_VERSIONING_UNPROVEN")
    If $ISOBJECT(r) Do $$$AssertTrue(r.NextAction [ "tests/conformance/fhir_conformance.py", "the unproven server's next action names the conformance run")
}

/// An unsaved transfer case with no bed.
ClassMethod Case() As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-FHIRPROP-1", case.Event = "transfer", case.FailureKind = "delivery_failed"
    Set case.EncounterId = "V1001", case.PatientId = "MRN-UT1", case.PatientIdAuthority = "HOSP"
    Set case.Receiver = "FHIR Ward Out", case.Ward = "WARD-B", case.EventTime = ..#EVENTTIME
    Quit case
}

/// The part of the evidence's fhir view the builder reads.
ClassMethod Fhir(prior As %String = "WARD-A", target As %String = "WARD-B") As %DynamicObject
{
    Set fhir = {"kind": "fhir_r4", "base": "/fhir-facade/r4",
        "message": {"prior_ward": (prior), "target_ward": (target), "event_time": (..#EVENTTIME)},
        "encounter": {"http_status": 200, "id": "enc-1", "version_id": "1", "etag_usable": true, "status": "in-progress"}}
    Set fhir.encounter.etag = "W/""1"""
    Quit fhir
}

/// The receiver's entry of the site profile, as the demo has it.
ClassMethod Entry() As %DynamicObject
{
    Quit {"name": "FHIR Ward Out", "category": "current_state",
        "fhir": {"base": "/fhir-facade/r4", "recovery_enabled": true,
            "encounter_identifier": {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49"},
            "patient_identifier": {"system": "urn:shutter:demo:mrn", "hl7_authority": "HOSP"},
            "marker": {"system": "urn:shutter:recovery"},
            "location_map": [
                {"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}},
                {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}
}

/// The Encounter as it was read: the plan builder's measured seed.
ClassMethod Seed() As %String
{
    Quit ##class(Shutter.Test.FHIRPlan).Text("Seed")
}

/// Every reason code the FHIR path can give, in the knowledge file's order.
XData Codes [ MimeType = application/json ]
{
["FHIR_NO_DRY_RUN_SUBSTITUTED", "FHIR_ITEMS_MISSING", "FHIR_ITEM_ERROR",
"FHIR_PLAN_NEEDS_PERSON", "FHIR_RECEIVER_UNREADABLE", "FHIR_ENCOUNTER_NOT_FOUND",
"FHIR_ENCOUNTER_AMBIGUOUS", "FHIR_IDENTIFIER_UNMAPPED", "FHIR_SUBJECT_UNRESOLVED",
"FHIR_PATIENT_MISMATCH", "FHIR_PATIENT_LINKED", "FHIR_EVENT_UNSUPPORTED",
"FHIR_FAILURE_KIND_UNSUPPORTED", "FHIR_RECOVERY_DISABLED", "FHIR_REPRESENTATION_PARTIAL",
"FHIR_MODIFIER_EXTENSION", "FHIR_NARRATIVE_PRESENT", "FHIR_RESTRICTED",
"FHIR_NO_ETAG", "FHIR_STATUS_NOT_IN_PROGRESS", "FHIR_ALREADY_THERE",
"FHIR_LATER_MOVE_AT_RECEIVER", "FHIR_PRIOR_LOCATION_DIFFERS", "FHIR_TIME_UNREADABLE",
"FHIR_LOCATION_UNMAPPED", "FHIR_LOCATION_UNREADABLE", "FHIR_LOCATION_MISMATCH",
"FHIR_SHAPE_UNSUPPORTED", "FHIR_BED_MOVE_UNSUPPORTED", "FHIR_DIFF_OUT_OF_BOUNDS",
"FHIR_BODY_CHANGED", "FHIR_NO_BINDING", "FHIR_RECEIVER_CHANGED",
"FHIR_PATIENT_CHANGED", "FHIR_LOCATION_CHANGED", "FHIR_EARLIER_WRITE_UNRESOLVED",
"FHIR_CAPABILITIES_UNREADABLE", "FHIR_NO_HISTORY", "FHIR_VERSIONING_UNPROVEN",
"FHIR_HISTORY_UNAVAILABLE", "FHIR_HISTORY_HEAD_DIFFERS", "FHIR_ALREADY_WRITTEN",
"FHIR_APPROVAL_NOT_PERSONAL", "FHIR_ENGINE_NOT_IN_SCOPE", "FHIR_ENGINE_SUBCLASS_UNPROVEN",
"FHIR_ENGINE_DELIVERED", "FHIR_ENGINE_HOLDS_SUSPENDED", "FHIR_WRITE_REFUSED",
"FHIR_WRITE_CONFLICT", "FHIR_WRITE_OUTCOME_UNKNOWN", "FHIR_WRITE_NOT_FOUND",
"FHIR_COMMITTED_NEEDS_REVIEW", "FHIR_WRITE_CONTRADICTED"]
}

}
