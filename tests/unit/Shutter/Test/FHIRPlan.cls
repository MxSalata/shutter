/// The FHIR plan builder (Shutter.FHIR.Plan): the one location change built from a sealed Encounter read, every stop
/// it owns, the diff that bounds it, and the digest of the bytes it would send. The fixtures in XData are Encounters
/// as IRIS for Health returned them (enc-1 and enc-rich, read on 2027.1.0AI Build 109U); nothing here talks to a
/// server. The ordering of the move against the event time is the FHIR gate's row, not Build's (TestNoOrderingJudged).
Class Shutter.Test.FHIRPlan Extends %UnitTest.TestCase
{

Parameter EVENTTIME = "2026-11-07T10:15:00Z";

Parameter MARKERSYSTEM = "urn:shutter:recovery";

Parameter CODE = "0123456789abcdef0123456789abcdef";

Parameter OUT = "FHIR_DIFF_OUT_OF_BOUNDS";

Parameter SHAPE = "FHIR_SHAPE_UNSUPPORTED";

/// 1. The measured seed Encounter: the exact outbound text, its digest and the touched paths.
Method TestSeedGolden()
{
    Set seed = ..Text("Seed")
    Do $$$AssertEquals($LENGTH(seed), 455, "the seed is the 455-byte read IRIS returned")
    Set code = ##class(Shutter.FHIR.Plan).Build(seed, ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "the seed builds")
    Do $$$AssertEquals(body, ..Text("Golden"), "the outbound text is exactly the golden one")
    Do $$$AssertEquals(##class(Shutter.FHIR.Plan).BodyDigest(body), "140da1f931937b9c58242747012e2c13d0365eee3bf9e127ad61b0acb3f710f7", "its digest is the SHA-256 of its UTF-8 bytes")
    Do $$$AssertEquals(detail."completed_index", 0, "the open entry 0 is completed")
    Do $$$AssertEquals(detail."appended_index", 1, "the new entry is appended at 1")
    Do $$$AssertEquals(detail."marker_index", 0, "the marker is the first tag")
    Do $$$AssertEquals(detail.paths.%ToJSON(), "[""/location/0/status"",""/location/0/period/end"",""/location/1"",""/meta/tag""]", "exactly the allowed paths")
    Do $$$AssertEquals(##class(Shutter.FHIR.Plan).Diff(seed, body, .paths), "", "the diff of the two is in bounds")
}

/// 2. A rich read: unknown and extension content, other tags, meta.security, profile and source kept byte for byte,
/// key order kept; the open entry is the second one, and a closed one before it is left alone.
Method TestRichContentKept()
{
    Set rich = ..Text("Rich")
    Set view = ..View("Location/ward-b", "Location/ward-c")
    Set code = ##class(Shutter.FHIR.Plan).Build(rich, view, "2026-11-07T10:15:00+01:00", ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "the rich read builds")
    Do $$$AssertEquals(body, ..Text("RichGolden"), "the outbound text is exactly the golden one, non-ASCII text included")
    Do $$$AssertEquals(##class(Shutter.FHIR.Plan).BodyDigest(body), "eee00b75f45bf0146f22ee3c3e010123707b81735c532bb87d3370630dccae5f", "and its digest")
    Do $$$AssertEquals(detail."completed_index", 1, "the second entry was the open one")
    Do $$$AssertEquals(detail."marker_index", 1, "the marker goes after the other tag")
    Do $$$AssertEquals(detail.paths.%ToJSON(), "[""/location/1/status"",""/location/1/period/end"",""/location/2"",""/meta/tag/1""]", "exactly the allowed paths")

    // Primitive extensions (_status), nested extensions and an unknown top-level property, in their places.
    Set e = ..Seed()
    Do e.%Set("_status", {"extension": [{"url": "http://example.org/ext/why", "valueString": "kept"}]})
    Do e.%Set("priority", {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ActPriority", "code": "EM"}]})
    Do e.class.%Set("extension", [{"url": "http://example.org/ext/nested", "valueBoolean": true}])
    Do e.%Set("zzUnknown", {"a": [1, "two", null, false]})
    Set before = e.%ToJSON()
    Set code = ##class(Shutter.FHIR.Plan).Build(before, ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "builds with extensions and unknown content")
    Set fragment(1) = "{""system"":""http://terminology.hl7.org/CodeSystem/v3-ActCode"",""code"":""IMP"",""extension"":[{""url"":""http://example.org/ext/nested"",""valueBoolean"":true}]}"
    Set fragment(2) = """_status"":{""extension"":[{""url"":""http://example.org/ext/why"",""valueString"":""kept""}]}"
    Set fragment(3) = """priority"":{""coding"":[{""system"":""http://terminology.hl7.org/CodeSystem/v3-ActPriority"",""code"":""EM""}]}"
    Set fragment(4) = """zzUnknown"":{""a"":[1,""two"",null,false]}"
    Set last = 0
    For i = 1:1:4 {
        Set fragment = fragment(i), at = $FIND(body, fragment)
        Do $$$AssertTrue(at > last, "kept byte for byte and in order: " _ fragment)
        Set:at>last last = at
    }
}

/// 3. Numbers and times: decimal text, exponents, fractions of a second and offsets survive, or the guard refuses.
Method TestNumbersAndTimes()
{
    Set e = ..Seed()
    Do e.%Set("length", {"value": 0, "unit": "h"})
    Do e.%Set("extension", [{"url": "http://example.org/ext/n", "valueDecimal": 0}, {"url": "http://example.org/ext/q", "valueQuantity": {"value": 0}}])
    Do e.location.%Get(0).period.%Set("start", "2026-11-07T10:00:00.000+00:00")
    Do ..Prepend(e.location, {"location": {"reference": "Location/ward-c"}, "status": "completed", "period": {"start": "2026-11-06T09:00:00+01:00", "end": "2026-11-07T10:00:00.000+00:00"}})
    // The numbers' text as a receiver might send it, put in by text so that nothing normalises it first.
    Set before = $REPLACE($REPLACE($REPLACE(e.%ToJSON(), """value"":0,""unit""", """value"":1.50,""unit"""), """valueDecimal"":0", """valueDecimal"":1.0E2"), """valueQuantity"":{""value"":0}", """valueQuantity"":{""value"":-0.000}")
    Set lossless = (##class(%DynamicAbstractObject).%FromJSON(before).%ToJSON() = before)
    Set view = ..View(), view."location_map" = ..Map("Location/ward-a", "Location/ward-b", "Location/ward-c")
    Set code = ##class(Shutter.FHIR.Plan).Build(before, view, "2026-11-07T11:15:00.123-05:00", ..Marker(), .body, .detail)
    If lossless {
        Do $$$LogMessage("this platform keeps the numbers' text: 1.50, 1.0E2 and -0.000 round-trip")
        Do $$$AssertEquals(code, "", "builds")
        For fragment = """value"":1.50,", """valueDecimal"":1.0E2", """value"":-0.000}", """start"":""2026-11-06T09:00:00+01:00""", """end"":""2026-11-07T10:00:00.000+00:00""", """start"":""2026-11-07T10:00:00.000+00:00"",""end"":""2026-11-07T11:15:00.123-05:00""" {
            Do $$$AssertTrue(body [ fragment, "kept unchanged: " _ fragment)
        }
        Do $$$AssertEquals(detail."completed_index", 1, "the open entry, after a closed one")
    } Else {
        Do $$$LogMessage("this platform normalises a number's text: the round-trip guard refuses")
        Do $$$AssertEquals(code, ..#SHAPE, "refused")
        Do $$$AssertEquals(detail.reason, "body_not_lossless", "by the round-trip guard")
    }
}

/// 4. Non-ASCII text kept and digested as UTF-8; escapes the platform would rewrite are refused by the guard.
Method TestNonAscii()
{
    Set e = ..Seed()
    Do e.subject.%Set("display", "Zo" _ $CHAR(235) _ " " _ $CHAR(55357, 56832))
    Set before = e.%ToJSON()
    Set code = ##class(Shutter.FHIR.Plan).Build(before, ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "builds with a non-ASCII display")
    Do $$$AssertTrue(body [ ("""display"":""Zo" _ $CHAR(235) _ " " _ $CHAR(55357, 56832) _ """"), "the text is kept as characters")
    Do $$$AssertEquals(##class(Shutter.FHIR.Plan).BodyDigest(body), "8e5e2a79d35d175be099bc164ffc89cb4da5c6b41793bf2225cfc9faf58b3738", "the digest is over UTF-8, the emoji as four bytes")

    // Escaped text: kept only if this platform writes it back as it came.
    For escaped = "\u00e9", "a\/b", "\ud83d\ude00" {
        Set before = $REPLACE(..Text("Seed"), """reference"":""Patient/demo-p1""", """reference"":""Patient/demo-p1"",""display"":""" _ escaped _ """")
        Set lossless = (##class(%DynamicAbstractObject).%FromJSON(before).%ToJSON() = before)
        Set code = ##class(Shutter.FHIR.Plan).Build(before, ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
        If lossless {
            Do $$$LogMessage("kept: " _ escaped)
            Do $$$AssertEquals(code, "", "the platform keeps " _ escaped _ ", so it builds")
        } Else {
            Do $$$LogMessage("rewritten by the platform, refused: " _ escaped)
            Do $$$AssertEquals(code, ..#SHAPE, "the platform rewrites " _ escaped _ ": refused")
            Do $$$AssertEquals(detail.reason, "body_not_lossless", "by the round-trip guard")
            Do $$$AssertEquals(body, "", "with no body")
        }
    }

    // Insignificant whitespace outside strings is not a change; inside a string it is kept.
    Set spaced = $REPLACE($REPLACE(..Text("Seed"), ",""status"":", ", " _ $CHAR(10) _ " ""status"" : "), """value"":""V1001""", """value"":""V 1001""")
    Set code = ##class(Shutter.FHIR.Plan).Build(spaced, ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "a pretty-printed read builds")
    Do $$$AssertTrue(body [ """value"":""V 1001""", "the space inside the string is kept")
}

/// 5. A modifierExtension anywhere stops the plan, named by its path.
Method TestModifierExtension()
{
    Set e = ..Seed()
    Do e.%Set("modifierExtension", [{"url": "http://example.org/m", "valueBoolean": true}])
    Do ..Expect(e.%ToJSON(), "FHIR_MODIFIER_EXTENSION", "/modifierExtension", "at the top level")
    Set e = ..Seed()
    Do e.location.%Get(0).%Set("modifierExtension", [{"url": "http://example.org/m", "valueBoolean": true}])
    Do ..Expect(e.%ToJSON(), "FHIR_MODIFIER_EXTENSION", "/location/0/modifierExtension", "in a location entry")
    Set e = ..Seed()
    Do e.%Set("extension", [{"url": "http://example.org/x", "modifierExtension": [{"url": "http://example.org/m", "valueBoolean": true}]}])
    Do ..Expect(e.%ToJSON(), "FHIR_MODIFIER_EXTENSION", "/extension/0/modifierExtension", "inside an extension")
    // implicitRules is a modifier element of every resource: a body under rules Shutter cannot read is not rewritten
    Set e = ..Seed()
    Do e.%Set("implicitRules", "http://example.org/rules")
    Do ..Expect(e.%ToJSON(), "FHIR_MODIFIER_EXTENSION", "/implicitRules", "implicitRules", "implicit_rules")
    // An extension on the open entry's own status would come to describe "completed"
    Set e = ..Seed()
    Do e.location.%Get(0).%Set("_status", {"extension": [{"url": "http://example.org/why-active", "valueString": "bed held"}]})
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/location/0/_status", "an extension on the open entry's status", "status_extension")
}

/// 6. A subsetted representation, with full meta and in the exact shape IRIS returns for _elements=id,location.
Method TestSubsetted()
{
    Set e = ..Seed()
    Do e.meta.%Set("tag", [{"system": "http://terminology.hl7.org/CodeSystem/v3-ObservationValue", "code": "SUBSETTED"}])
    Do ..Expect(e.%ToJSON(), "FHIR_REPRESENTATION_PARTIAL", "/meta/tag/0", "SUBSETTED with versionId present")
    Do ..Expect(..Text("Elements"), "FHIR_REPRESENTATION_PARTIAL", "/meta/tag/0", "the measured _elements body, meta only the tag")
    // Checked before the modifierExtension and status rules, so the reason names the real cause.
    Set e = {}.%FromJSON(..Text("Elements"))
    Do e.%Set("modifierExtension", [])
    Do ..Expect(e.%ToJSON(), "FHIR_REPRESENTATION_PARTIAL", "/meta/tag/0", "SUBSETTED wins over later rules")
    // The code has one meaning whatever system carries it: STU3's URI for the same code system, another system, none.
    For system = "http://hl7.org/fhir/v3/ObservationValue", "urn:example:other" {
        Set e = ..Seed()
        Do e.meta.%Set("tag", [{"system": "urn:example:keep", "code": "x"}, {"system": (system), "code": "SUBSETTED"}])
        Do ..Expect(e.%ToJSON(), "FHIR_REPRESENTATION_PARTIAL", "/meta/tag/1", "SUBSETTED under " _ system)
    }
    Set e = ..Seed()
    Do e.meta.%Set("tag", [{"code": "SUBSETTED"}])
    Do ..Expect(e.%ToJSON(), "FHIR_REPRESENTATION_PARTIAL", "/meta/tag/0", "SUBSETTED with no system")
}

/// 7. A narrative is always a stop.
Method TestNarrative()
{
    Set e = ..Seed()
    Do e.%Set("text", {"status": "generated", "div": ("<div xmlns=""http://www.w3.org/1999/xhtml"">In Ward A</div>")})
    Do ..Expect(e.%ToJSON(), "FHIR_NARRATIVE_PRESENT", "/text", "text present")
}

/// 8. Open entries: exactly one, and every open one a literal reference in the map.
Method TestOpenEntries()
{
    Set e = ..Seed()
    Do e.location.%Push({"location": {"reference": "Location/ward-x"}, "status": "active", "period": {"start": "2026-11-07T09:30:00Z"}})
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/location/1", "an open entry outside the map", "open_entry_unmapped")
    Set e = ..Seed()
    Do e.location.%Push({"location": {"reference": "Location/ward-b"}, "status": "active"})
    Set detail = ..Expect(e.%ToJSON(), ..#SHAPE, "/location", "two mapped open entries", "open_entries")
    Do $$$AssertEquals(detail."open_entries", 2, "counted two")
    Set e = ..Seed()
    Do e.location.%Get(0).%Set("status", "completed")
    Set detail = ..Expect(e.%ToJSON(), ..#SHAPE, "/location", "none open", "open_entries")
    Do $$$AssertEquals(detail."open_entries", 0, "counted none")
    Set e = ..Seed()
    Do e.%Remove("location")
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/location", "no location at all", "open_entries")
    Set e = ..Seed()
    Do e.location.%Get(0).%Set("status", 1)
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/location/0", "an entry whose status is not a string", "location_entry")

    // A pending entry (a planned move, a held place) beside the open one is a stop, with or without an end; so is a
    // status R4 does not define.
    For status = "planned", "reserved" {
        Set e = ..Seed()
        Do e.location.%Push({"location": {"reference": "Location/ward-c"}, "status": (status), "period": {"start": "2026-11-07T11:00:00Z"}})
        Do ..Expect(e.%ToJSON(), ..#SHAPE, "/location/1", "a " _ status _ " entry with no end", "pending_entry")
        Set e = ..Seed()
        Do ..Prepend(e.location, {"location": {"reference": "Location/ward-c"}, "status": (status), "period": {"start": "2026-11-08T09:00:00Z", "end": "2026-11-09T09:00:00Z"}})
        Do ..Expect(e.%ToJSON(), ..#SHAPE, "/location/0", "a " _ status _ " entry with an end", "pending_entry")
    }
    Set e = ..Seed()
    Do e.location.%Push({"location": {"reference": "Location/ward-c"}, "status": "booked"})
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/location/1", "a status R4 does not define", "pending_entry")

    // An active entry with an end is not open: beside the mapped open one, the plan builds.
    Set e = ..Seed()
    Do ..Prepend(e.location, {"location": {"reference": "Location/ward-x"}, "status": "active", "period": {"start": "2026-11-06T09:00:00Z", "end": "2026-11-07T09:00:00Z"}})
    Set code = ##class(Shutter.FHIR.Plan).Build(e.%ToJSON(), ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "an active entry with period.end is closed, whatever its location")
    Do $$$AssertEquals(detail."completed_index", 1, "the open one is completed")

    // No status and no end is open; the completion adds the status and, with no period, the period.
    Set e = ..Seed()
    Do e.location.%Get(0).%Remove("status")
    Do e.location.%Get(0).%Remove("period")
    Set before = e.%ToJSON()
    Set code = ##class(Shutter.FHIR.Plan).Build(before, ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "status absent and no end is open")
    Do $$$AssertTrue(body [ "[{""location"":{""reference"":""Location/ward-a""},""status"":""completed"",""period"":{""end"":""2026-11-07T10:15:00Z""}},", "completed, with a period holding only the end")
    Do $$$AssertEquals(detail.paths.%ToJSON(), "[""/location/0/status"",""/location/0/period"",""/location/1"",""/meta/tag""]", "the period is one path when it was absent")
}

/// 9. The prior location, the target, the map and its beds, and references Build cannot read as literal.
Method TestPriorAndTarget()
{
    Do ..Expect(..Text("Seed"), "FHIR_PRIOR_LOCATION_DIFFERS", "/location/0", "the open entry is not the prior location", "", ..View("Location/ward-c", "Location/ward-b"))
    Do ..Expect(..Text("Seed"), "FHIR_ALREADY_THERE", "/location/0", "the target is the open entry", "", ..View("Location/ward-a", "Location/ward-a"))
    Do ..Expect(..Text("Seed"), "FHIR_LOCATION_UNMAPPED", "/target_location", "the target is not in the map", "", ..View("Location/ward-a", "Location/ward-z"))
    Do ..Expect(..Text("Seed"), "FHIR_LOCATION_UNMAPPED", "/target_location", "an absolute target is not in the map", "", ..View("Location/ward-a", "http://example.org/fhir/Location/ward-b"))
    Set view = ..View()
    Do view."location_map".%Get(1).%Set("bed", "B-1")
    Do ..Expect(..Text("Seed"), "FHIR_BED_MOVE_UNSUPPORTED", "/location_map/1/bed", "a map entry naming a bed", "", view)
    Set view = ..View()
    Do view."location_map".%Get(0).%Remove("bed")
    Set code = ##class(Shutter.FHIR.Plan).Build(..Text("Seed"), view, ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "a map entry with no bed key is ward level")
    Set e = ..Seed()
    Do e.location.%Get(0).%Set("location", {"display": "Ward A"})
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/location/0", "a display-only reference is unmapped", "open_entry_unmapped")
    Set e = ..Seed()
    Do e.location.%Get(0).location.%Set("reference", "http://example.org/fhir/Location/ward-a")
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/location/0", "an absolute reference is unmapped", "open_entry_unmapped")
    Set e = ..Seed()
    Do e.location.%Get(0).location.%Set("reference", "Location/Ward-A")
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/location/0", "references match case-sensitively", "open_entry_unmapped")
}

/// 10. Only an encounter in progress moves.
Method TestStatus()
{
    For status = "planned", "finished", "entered-in-error", "In-Progress" {
        Set e = ..Seed()
        Do e.%Set("status", status)
        Do ..Expect(e.%ToJSON(), "FHIR_STATUS_NOT_IN_PROGRESS", "/status", "status " _ status)
    }
    Set e = ..Seed()
    Do e.%Remove("status")
    Do ..Expect(e.%ToJSON(), "FHIR_STATUS_NOT_IN_PROGRESS", "/status", "no status")
}

/// 11. The marker: where it goes, other tags kept, and a reused code refused.
Method TestMarker()
{
    Set marker = "{""system"":""urn:shutter:recovery"",""code"":""0123456789abcdef0123456789abcdef""}"
    Set e = ..Seed()
    Do e.%Remove("meta")
    Set code = ##class(Shutter.FHIR.Plan).Build(e.%ToJSON(), ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "no meta: builds")
    Set expected = ",""meta"":{""tag"":[" _ marker _ "]}}"
    Do $$$AssertEquals($EXTRACT(body, * - $LENGTH(expected) + 1, *), expected, "meta is appended at the end with only the marker")
    Do $$$AssertEquals(detail.paths.%Get(3), "/meta", "named as /meta")

    Set code = ##class(Shutter.FHIR.Plan).Build(..Text("Seed"), ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertTrue(body [ ("""versionId"":""1"",""tag"":[" _ marker _ "]}"), "meta without tag: tag added after versionId, which stays as read")

    Set e = ..Seed()
    Do e.meta.%Set("tag", [{"system": "urn:example:other", "code": "keep-me"}, {"system": (..#MARKERSYSTEM), "code": "ffffffffffffffffffffffffffffffff"}])
    Set code = ##class(Shutter.FHIR.Plan).Build(e.%ToJSON(), ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "other tags, and another operation's code under the same system: builds")
    Do $$$AssertTrue(body [ ("""tag"":[{""system"":""urn:example:other"",""code"":""keep-me""},{""system"":""urn:shutter:recovery"",""code"":""ffffffffffffffffffffffffffffffff""}," _ marker _ "]"), "both kept, the marker last")
    Do $$$AssertEquals(detail."marker_index", 2, "at index 2")

    Set e = ..Seed()
    Do e.meta.%Set("tag", [{"system": (..#MARKERSYSTEM), "code": (..#CODE)}])
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/meta/tag/0", "the exact marker already there", "marker_present")
    Set e = ..Seed()
    Do e.meta.%Set("tag", [{"system": "URN:SHUTTER:RECOVERY", "code": (..#CODE)}])
    Set code = ##class(Shutter.FHIR.Plan).Build(e.%ToJSON(), ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "the pair matches case-sensitively: another system's tag is data")
    Set e = ..Seed()
    Do e.meta.%Set("tag", {"system": "urn:example:other"})
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/meta/tag", "a tag that is not an array", "meta_tag")
}

/// 12. Bad inputs are refused as a shape, never thrown.
Method TestBadInputs()
{
    Do ..Expect("not json", ..#SHAPE, "", "not JSON", "not_json")
    Do ..Expect("", ..#SHAPE, "", "empty", "not_json")
    Do ..Expect("[1,2]", ..#SHAPE, "", "an array", "not_encounter")
    Set e = ..Seed()
    Do e.%Set("resourceType", "Patient")
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/resourceType", "a Patient", "not_encounter")
    Set e = ..Seed()
    Do e.%Remove("id")
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/id", "no id", "no_id")
    For time = "2026-11-07", "2026-11-07T10:15:00", "2026-11-07T10:15Z", "2026-13-07T10:15:00Z", "2026-11-07 10:15:00Z", "", "2026-11-07T10:15:60Z", "2026-11-07T10:15:00.1234567890Z", "2026-02-30T10:15:00Z", "2026-11-07T24:00:00Z", "2026-11-07T10:15:00+14:30" {
        Set code = ##class(Shutter.FHIR.Plan).Build(..Text("Seed"), ..View(), time, ..Marker(), .body, .detail)
        Do $$$AssertEquals(code, ..#SHAPE, "event time refused: '" _ time _ "'")
        Do $$$AssertEquals(detail.reason, "event_time", "named as the event time")
        Do $$$AssertEquals(body, "", "no body")
    }
    For marker = {"system": (..#MARKERSYSTEM), "code": "0123456789ABCDEF0123456789ABCDEF"}, {"system": (..#MARKERSYSTEM), "code": "0123456789abcdef"}, {"system": "", "code": (..#CODE)}, {"system": (..#MARKERSYSTEM), "code": (..#CODE), "display": "x"}, {"code": (..#CODE)}, "" {
        Set code = ##class(Shutter.FHIR.Plan).Build(..Text("Seed"), ..View(), ..#EVENTTIME, marker, .body, .detail)
        Do $$$AssertEquals(code, ..#SHAPE, "marker refused: " _ $SELECT($ISOBJECT(marker): marker.%ToJSON(), 1: "none"))
        Do $$$AssertEquals(detail.reason, "marker", "named as the marker")
    }
    Set view = ..View()
    Do view.%Remove("location_map")
    Do ..Expect(..Text("Seed"), ..#SHAPE, "/location_map", "a view with no map", "view", view)
    Set view = ..View()
    Do view."location_map".%Get(0).%Set("location", "http://example.org/fhir/Location/ward-a")
    Do ..Expect(..Text("Seed"), ..#SHAPE, "/location_map/0/location", "a map entry that is not a literal reference", "view", view)
    Do ..Expect(..Text("Seed"), ..#SHAPE, "/", "no view", "view", "")
    // An empty prior or target (PV1-6 or PV1-3 absent) is a bad view, not a receiver whose location differs
    Do ..Expect(..Text("Seed"), ..#SHAPE, "/prior_location", "an empty prior location", "view", ..View(""))
    Do ..Expect(..Text("Seed"), ..#SHAPE, "/target_location", "an empty target location", "view", ..View("Location/ward-a", ""))
    Set e = ..Seed()
    Do e.%Set("meta", "x")
    Do ..Expect(e.%ToJSON(), ..#SHAPE, "/meta", "meta that is not an object", "meta")
}

/// 13. Diff on hand-made afters: each touch outside the change is out of bounds and named.
Method TestDiff()
{
    Set seed = ..Text("Seed"), golden = ..Text("Golden")
    Do $$$AssertEquals(##class(Shutter.FHIR.Plan).Diff(seed, golden, .paths), "", "the golden after is in bounds")
    Do $$$AssertEquals(paths.%ToJSON(), "[""/location/0/status"",""/location/0/period/end"",""/location/1"",""/meta/tag""]", "with exactly the allowed paths")

    Do ..OutOfBounds(seed, ..Edit(golden, "subject", {"reference": "Patient/other"}), "/subject/reference", "subject changed")
    Do ..OutOfBounds(seed, ..Edit(golden, "meta.versionId", "2"), "/meta/versionId", "meta.versionId changed")
    Do ..OutOfBounds(seed, ..Edit(golden, "meta.security", [{"system": "http://terminology.hl7.org/CodeSystem/v3-Confidentiality", "code": "R"}]), "/meta/security", "meta.security added")
    Set a = {}.%FromJSON(golden)
    Do a.meta.tag.%Push({"system": (..#MARKERSYSTEM), "code": (..#CODE)})
    Do ..OutOfBounds(seed, a.%ToJSON(), "/meta/tag", "the marker twice")
    Set a = {}.%FromJSON(golden)
    Do a.location.%Push({"location": {"reference": "Location/ward-c"}, "status": "active", "period": {"start": (..#EVENTTIME)}})
    Do ..OutOfBounds(seed, a.%ToJSON(), "/location/2", "a second appended entry")
    Set a = {}.%FromJSON(golden), first = a.location.%Get(0)
    Do a.location.%Remove(0)
    Do a.location.%Push(first)
    Do ..OutOfBounds(seed, a.%ToJSON(), "/location/0/location/reference", "location reordered")
    Set a = {}.%FromJSON(golden)
    Do a.location.%Remove(0)
    Do ..OutOfBounds(seed, a.%ToJSON(), "/location/0/location/reference", "the old entry removed")
    Do ..OutOfBounds(seed, ..Edit(golden, "location.0.status", "cancelled"), "", "the old entry ends as something other than completed")
    Do ..OutOfBounds(seed, ..Edit(golden, "location.1.period", {"start": "2026-11-07T10:16:00Z"}), "", "the new entry does not start at the old one's end")
    Do ..OutOfBounds(seed, ..Edit(golden, "location.1.display", "x"), "", "the new entry carries more than the shape")
    Do ..OutOfBounds(seed, ..Edit(golden, "meta.tag", [{"system": (..#MARKERSYSTEM), "code": "nothex"}]), "", "the tag is not a marker")
    Do ..OutOfBounds(seed, $REPLACE(golden, ",""meta"":{""lastUpdated"":""2026-11-08T02:31:51Z"",""versionId"":""1"",", ",""meta"":{""versionId"":""1"",""lastUpdated"":""2026-11-08T02:31:51Z"","), "", "control: key order alone is not a change", 1)
    Do ..OutOfBounds(seed, seed, "", "no change at all")
    Do ..OutOfBounds(seed, "not json", "", "an after that is not JSON")

    // Extensions removed, and numbers by their text.
    Set e = ..Seed()
    Do e.%Set("extension", [{"url": "http://example.org/ext/a", "valueString": "x"}])
    Set before = e.%ToJSON()
    Set code = ##class(Shutter.FHIR.Plan).Build(before, ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "builds with an extension")
    Set a = {}.%FromJSON(body)
    Do a.%Remove("extension")
    Do ..OutOfBounds(before, a.%ToJSON(), "/extension", "an extension removed")
    Set before = $REPLACE(..Text("Seed"), """id"":""enc-1"",", """id"":""enc-1"",""length"":{""value"":1.50},")
    Set after = $REPLACE(golden, """id"":""enc-1"",", """id"":""enc-1"",""length"":{""value"":1.5},")
    Do ..OutOfBounds(before, after, "/length/value", "1.50 and 1.5 differ by their text")
    Set before = $REPLACE(..Text("Seed"), """id"":""enc-1"",", """id"":""enc-1"",""a/b~c"":""x"",")
    Set after = $REPLACE(golden, """id"":""enc-1"",", """id"":""enc-1"",""a/b~c"":""y"",")
    Do ..OutOfBounds(before, after, "/a~1b~0c", "a key with / and ~ is escaped in the pointer")
    Set after = $REPLACE(golden, """id"":""enc-1"",", """id"":""enc-1"",""a/b~c"":""1"",")
    Set before = $REPLACE(..Text("Seed"), """id"":""enc-1"",", """id"":""enc-1"",""a/b~c"":1,")
    Do ..OutOfBounds(before, after, "/a~1b~0c", "the string 1 is not the number 1")
}

/// 14. Purity: the same inputs give the same text, and nothing passed in is changed.
Method TestPurity()
{
    Set seed = ..Text("Seed"), copy = seed, view = ..View(), viewText = view.%ToJSON(), marker = ..Marker(), markerText = marker.%ToJSON()
    Set code1 = ##class(Shutter.FHIR.Plan).Build(seed, view, ..#EVENTTIME, marker, .body1, .detail1)
    Set code2 = ##class(Shutter.FHIR.Plan).Build(seed, view, ..#EVENTTIME, marker, .body2, .detail2)
    Do $$$AssertEquals(code1 _ "|" _ code2, "|", "both build")
    Do $$$AssertEquals(body1, body2, "the same text twice")
    Do $$$AssertEquals(detail1.%ToJSON(), detail2.%ToJSON(), "the same detail twice")
    Do $$$AssertEquals(seed, copy, "the input text is unchanged")
    Do $$$AssertEquals(view.%ToJSON(), viewText, "the view is unchanged")
    Do $$$AssertEquals(marker.%ToJSON(), markerText, "the marker is unchanged")
    Do $$$AssertEquals(##class(Shutter.FHIR.Plan).BodyDigest(body1), ##class(Shutter.FHIR.Plan).BodyDigest(body2), "the same digest")
    // A refusal leaves the outputs empty even when they held a value before.
    Set body = "stale"
    Set code = ##class(Shutter.FHIR.Plan).Build("not json", view, ..#EVENTTIME, marker, .body, .detail)
    Do $$$AssertEquals(body, "", "a refusal clears the body")
}

/// Build does not judge the move against the event time: an open entry that starts after it still builds, because
/// FHIR_LATER_MOVE_AT_RECEIVER is the gate's row (it needs the time reader). meta.security is the gate's too.
/// This pins a deliberate gap, not a property: the body built here ends the old entry before it starts, and an IRIS
/// FHIR server stores such a period without complaint, so the gate's ordering row is the only stop for it.
Method TestNoOrderingJudged()
{
    Set e = ..Seed()
    Do e.location.%Get(0).period.%Set("start", "2026-11-07T11:00:00Z")
    Do e.meta.%Set("security", [{"system": "http://terminology.hl7.org/CodeSystem/v3-Confidentiality", "code": "R"}])
    Set code = ##class(Shutter.FHIR.Plan).Build(e.%ToJSON(), ..View(), ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", "a later start and a restricted label are not Build's to stop")
}

/// Builds and asserts a refusal: its code, the detail's path and, when given, its reason. Returns the detail.
Method Expect(before As %String, code As %String, path As %String, what As %String, reason As %String = "", view As %DynamicObject = "default") As %DynamicObject
{
    Set:('$ISOBJECT(view))&&(view="default") view = ..View()
    Set got = ##class(Shutter.FHIR.Plan).Build(before, view, ..#EVENTTIME, ..Marker(), .body, .detail)
    Do $$$AssertEquals(got, code, what _ ": " _ code)
    Do $$$AssertEquals(detail.path, path, what _ ": at " _ path)
    Do:reason'="" $$$AssertEquals(detail.reason, reason, what _ ": reason " _ reason)
    Do $$$AssertEquals(body, "", what _ ": no body")
    Quit detail
}

/// Asserts Diff refuses the pair, naming <var>path</var> among the touched paths when it is given; with
/// <var>inBounds</var>, asserts it accepts it instead.
Method OutOfBounds(before As %String, after As %String, path As %String, what As %String, inBounds As %Boolean = 0)
{
    Set code = ##class(Shutter.FHIR.Plan).Diff(before, after, .paths)
    If inBounds {
        Do $$$AssertEquals(code, "", what)
        Quit
    }
    Do $$$AssertEquals(code, ..#OUT, what)
    Quit:path=""
    Set found = 0
    For i = 0:1:paths.%Size() - 1 {
        Set:paths.%Get(i)=path found = 1
    }
    Do $$$AssertTrue(found, what _ ": names " _ path _ " in " _ paths.%ToJSON())
}

/// The text with the value at a dotted path set (array indexes as numbers).
ClassMethod Edit(text As %String, path As %String, value) As %String
{
    Set obj = ##class(%DynamicAbstractObject).%FromJSON(text), at = obj
    For i = 1:1:$LENGTH(path, ".") - 1 {
        Set at = at.%Get($PIECE(path, ".", i))
    }
    Do at.%Set($PIECE(path, ".", *), value)
    Quit obj.%ToJSON()
}

/// Puts the item first in the array (the array is changed in place).
ClassMethod Prepend(array As %DynamicArray, item)
{
    Set rest = []
    For i = 0:1:array.%Size() - 1 { Do rest.%Push(array.%Get(i)) }
    For i = array.%Size() - 1:-1:0 { Do array.%Remove(i) }
    Do array.%Push(item)
    For i = 0:1:rest.%Size() - 1 { Do array.%Push(rest.%Get(i)) }
}

/// The seed read, parsed.
ClassMethod Seed() As %DynamicObject
{
    Quit {}.%FromJSON(..Text("Seed"))
}

/// The view the gate would build: the prior and target locations and a ward-level map.
ClassMethod View(prior As %String = "Location/ward-a", target As %String = "Location/ward-b") As %DynamicObject
{
    Quit {"prior_location": (prior), "target_location": (target), "location_map": (..Map("Location/ward-a", "Location/ward-b", "Location/ward-c"))}
}

/// Map entries at ward level, one per location.
ClassMethod Map(locations... As %String) As %DynamicArray
{
    Set map = []
    For i = 1:1:$GET(locations) {
        Set ward = $ZCONVERT($PIECE(locations(i), "/", 2), "U")
        Do map.%Push({"ward": (ward), "bed": null, "location": (locations(i)), "checked_identifier": (ward)})
    }
    Quit map
}

ClassMethod Marker() As %DynamicObject
{
    Quit {"system": (..#MARKERSYSTEM), "code": (..#CODE)}
}

/// A fixture's text, trimmed of the line breaks around it. In Rich and RichGolden, @E@ and @A@ stand for the two
/// non-ASCII characters IRIS returned (U+00E9 and U+2192), so that this file stays ASCII.
ClassMethod Text(name As %String) As %String
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||" _ name)
    Set text = ""
    Do xdata.Data.Rewind()
    While 'xdata.Data.AtEnd { Set text = text _ xdata.Data.Read(32000) }
    Set text = $ZSTRIP(text, "<>", $CHAR(9, 10, 13, 32))
    Quit $REPLACE($REPLACE(text, "@E@", $CHAR(233)), "@A@", $CHAR(8594))
}

/// enc-1 as IRIS returned it (GET Encounter/enc-1, version 1, 455 bytes).
XData Seed [ MimeType = application/json ]
{
{"resourceType":"Encounter","id":"enc-1","status":"in-progress","identifier":[{"system":"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49","value":"V1001"}],"class":{"system":"http://terminology.hl7.org/CodeSystem/v3-ActCode","code":"IMP"},"subject":{"reference":"Patient/demo-p1"},"location":[{"location":{"reference":"Location/ward-a"},"status":"active","period":{"start":"2026-11-07T09:00:00Z"}}],"meta":{"lastUpdated":"2026-11-08T02:31:51Z","versionId":"1"}}
}

/// The seed moved from ward-a to ward-b at 2026-11-07T10:15:00Z with the test's marker.
XData Golden [ MimeType = application/json ]
{
{"resourceType":"Encounter","id":"enc-1","status":"in-progress","identifier":[{"system":"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49","value":"V1001"}],"class":{"system":"http://terminology.hl7.org/CodeSystem/v3-ActCode","code":"IMP"},"subject":{"reference":"Patient/demo-p1"},"location":[{"location":{"reference":"Location/ward-a"},"status":"completed","period":{"start":"2026-11-07T09:00:00Z","end":"2026-11-07T10:15:00Z"}},{"location":{"reference":"Location/ward-b"},"status":"active","period":{"start":"2026-11-07T10:15:00Z"}}],"meta":{"lastUpdated":"2026-11-08T02:31:51Z","versionId":"1","tag":[{"system":"urn:shutter:recovery","code":"0123456789abcdef0123456789abcdef"}]}}
}

/// enc-rich as IRIS returned it (GET Encounter/enc-rich, version 1).
XData Rich [ MimeType = application/json ]
{
{"resourceType":"Encounter","id":"enc-rich","status":"in-progress","identifier":[{"system":"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49","value":"V1004"}],"class":{"system":"http://terminology.hl7.org/CodeSystem/v3-ActCode","code":"IMP"},"subject":{"reference":"Patient/demo-p1"},"location":[{"location":{"reference":"Location/ward-a","display":"Ward A"},"status":"completed","period":{"start":"2026-11-07T08:00:00+00:00","end":"2026-11-07T09:00:00.000Z"}},{"location":{"reference":"Location/ward-b"},"status":"active","period":{"start":"2026-11-07T09:00:00Z"}}],"meta":{"tag":[{"system":"urn:example:other","code":"keep-me"}],"security":[{"system":"http://terminology.hl7.org/CodeSystem/v3-Confidentiality","code":"N"}],"profile":["http://example.org/StructureDefinition/enc"],"source":"urn:example:src","versionId":"1","lastUpdated":"2026-11-08T02:31:53Z"},"extension":[{"url":"http://example.org/ext/a","valueString":"x"}],"period":{"start":"2026-11-07T08:00:00Z"},"serviceType":{"coding":[{"system":"urn:example:st","code":"GEN"}],"text":"General"},"priority":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ActPriority","code":"R"}]},"reasonCode":[{"text":"reason @E@ @A@ unicode"}],"length":{"value":1.5,"unit":"h"},"hospitalization":{"admitSource":{"text":"GP"}}}
}

/// enc-rich moved from ward-b to ward-c at 2026-11-07T10:15:00+01:00 with the test's marker.
XData RichGolden [ MimeType = application/json ]
{
{"resourceType":"Encounter","id":"enc-rich","status":"in-progress","identifier":[{"system":"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49","value":"V1004"}],"class":{"system":"http://terminology.hl7.org/CodeSystem/v3-ActCode","code":"IMP"},"subject":{"reference":"Patient/demo-p1"},"location":[{"location":{"reference":"Location/ward-a","display":"Ward A"},"status":"completed","period":{"start":"2026-11-07T08:00:00+00:00","end":"2026-11-07T09:00:00.000Z"}},{"location":{"reference":"Location/ward-b"},"status":"completed","period":{"start":"2026-11-07T09:00:00Z","end":"2026-11-07T10:15:00+01:00"}},{"location":{"reference":"Location/ward-c"},"status":"active","period":{"start":"2026-11-07T10:15:00+01:00"}}],"meta":{"tag":[{"system":"urn:example:other","code":"keep-me"},{"system":"urn:shutter:recovery","code":"0123456789abcdef0123456789abcdef"}],"security":[{"system":"http://terminology.hl7.org/CodeSystem/v3-Confidentiality","code":"N"}],"profile":["http://example.org/StructureDefinition/enc"],"source":"urn:example:src","versionId":"1","lastUpdated":"2026-11-08T02:31:53Z"},"extension":[{"url":"http://example.org/ext/a","valueString":"x"}],"period":{"start":"2026-11-07T08:00:00Z"},"serviceType":{"coding":[{"system":"urn:example:st","code":"GEN"}],"text":"General"},"priority":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ActPriority","code":"R"}]},"reasonCode":[{"text":"reason @E@ @A@ unicode"}],"length":{"value":1.5,"unit":"h"},"hospitalization":{"admitSource":{"text":"GP"}}}
}

/// The body IRIS returned for GET Encounter/enc-rich?_elements=id,location: meta is only the SUBSETTED tag.
XData Elements [ MimeType = application/json ]
{
{"resourceType":"Encounter","id":"enc-rich","location":[{"location":{"reference":"Location/ward-a","display":"Ward A"},"status":"completed","period":{"start":"2026-11-07T08:00:00+00:00","end":"2026-11-07T09:00:00.000Z"}},{"location":{"reference":"Location/ward-b"},"status":"active","period":{"start":"2026-11-07T09:00:00Z"}}],"meta":{"tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED","display":"Resource content reduced because _elements search parameter"}]}}
}

}
