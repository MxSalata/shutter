/// The plan builder and the verifier's decision, tested against each other (Shutter.FHIR.Plan, Shutter.FHIR.Judge): what
/// Build writes is what Judge verifies, and both read a time, a number and a Location's identifier the same way. Each
/// class has its own table (Shutter.Test.FHIRPlan, Shutter.Test.FHIRJudge); these tests are the seam between the two.
/// The read is FHIRPlan's measured seed (Encounter enc-1, version "1", WARD-A active), the receiver's answer is the built
/// body committed as version "2", and the walk is a clean one. Nothing is saved and nothing is read.
Class Shutter.Test.FHIRPlanJudge Extends %UnitTest.TestCase
{

Parameter EVENTTIME = "2026-11-07T10:15:00Z";

/// Build on the seed, committed as it was built and read back, is verified as the current version.
Method TestBuildsOutputIsJudgedVerified()
{
    Set seed = ..Seed()
    Set code = ##class(Shutter.FHIR.Plan).Build(seed, ..View(), ..#EVENTTIME, ..Marker(), .body, .built)
    Do $$$AssertEquals(code, "", "the seed builds")
    Set outcome = ##class(Shutter.FHIR.Judge).Judge(..Context(seed, body), .text, .detail)
    Do $$$AssertEquals(outcome _ " " _ detail.reason, "verified committed_current", "what Build wrote is what Judge verifies (" _ text _ " " _ detail.%ToJSON() _ ")")
    Do $$$AssertEquals(detail."committed_version", "2", "in the version the receiver committed")
    Do $$$AssertEquals(detail."base_version", "1", "from the version that was read")
    Do $$$AssertEquals(detail.path, "", "with no path that differs")
}

/// A second 60 is refused by Build, and it is a time the Judge does not read either.
Method TestBuildRefusesASecondSixty()
{
    Do ..Refused("2026-11-07T10:15:60Z", "a second 60")
    Do ..Refused("2026-12-31T23:59:60Z", "a leap second at the end of a year")
}

/// A fraction of more than nine digits is refused; nine digits build and are read.
Method TestBuildRefusesATenDigitFraction()
{
    Do ..Refused("2026-11-07T10:15:00.1234567890Z", "a ten-digit fraction")
    Do ..Refused("2026-11-07T10:15:00.Z", "a fraction with no digit")
    Do ..Accepted("2026-11-07T10:15:00.123456789Z", "a nine-digit fraction")
    Do ..Accepted("2026-11-07T10:15:00.5+01:00", "one digit and an offset")
}

/// A date that does not exist is refused, whatever its offset; the last day of February is not.
Method TestBuildRefusesTheThirtiethOfFebruary()
{
    Do ..Refused("2026-02-30T10:15:00Z", "30 February")
    Do ..Refused("2026-02-29T10:15:00+01:00", "29 February in a year that has none")
    Do ..Refused("2026-11-31T10:15:00Z", "31 November")
    Do ..Refused("2026-11-07T10:15:00+14:30", "an offset beyond 14:00")
    Do ..Refused("2026-11-07T24:00:00Z", "hour 24")
    Do ..Accepted("2028-02-29T10:15:00Z", "29 February in a leap year")
    Do ..Accepted("2026-02-28T23:59:59-05:00", "the last second of February")
    Do ..Accepted("2026-11-07T10:15:00+14:00", "the offset 14:00")
}

/// A number is compared by its JSON text, as Build's own diff compares it: a committed 1.50 where 1.5 was approved is a
/// field that differs, never the approved body.
Method TestNumbersCompareByJsonText()
{
    Set seed = $REPLACE(..Seed(), """subject"":", """length"":{""value"":1.5,""unit"":""h""},""subject"":")
    Set code = ##class(Shutter.FHIR.Plan).Build(seed, ..View(), ..#EVENTTIME, ..Marker(), .body, .built)
    Do $$$AssertEquals(code, "", "a read with a decimal builds")
    Do $$$AssertTrue(body [ """value"":1.5,", "and keeps it as it was read")
    Set outcome = ##class(Shutter.FHIR.Judge).Judge(..Context(seed, body), .text, .detail)
    Do $$$AssertEquals(outcome _ " " _ detail.reason, "verified committed_current", "committed as approved, it verifies (" _ text _ ")")
    Set committed = $REPLACE(body, """value"":1.5,", """value"":1.50,")
    Do $$$AssertNotTrue(committed = body, "the committed text differs in one number's text")
    If ##class(%DynamicAbstractObject).%FromJSON("{""v"":1.50}").%ToJSON() '= "{""v"":1.50}" {
        Do $$$LogMessage("this platform normalises a number's text, so 1.50 cannot be told from 1.5 once parsed")
        Quit
    }
    Set outcome = ##class(Shutter.FHIR.Judge).Judge(..Context(seed, body, committed), .text, .detail)
    Do $$$AssertEquals(outcome _ " " _ detail.reason, "unknown field_differs", "1.50 against 1.5 (" _ text _ ")")
    Do $$$AssertEquals(detail.path, "/length/value", "named by its path")
    Do $$$AssertEquals(##class(Shutter.FHIR.Plan).Diff(body, committed, .paths), "FHIR_DIFF_OUT_OF_BOUNDS", "and Build's own diff sees the same difference")
    Do $$$AssertEquals(paths.%ToJSON(), "[""/length/value""]", "at the same path")
}

/// A bound Location checked by {system, value} is the exact pair: the value under another system is not the mapped
/// Location, and the committed update needs review.
Method TestALocationUnderAnotherSystemNeedsReview()
{
    Set seed = ..Seed()
    Set code = ##class(Shutter.FHIR.Plan).Build(seed, ..View(), ..#EVENTTIME, ..Marker(), .body, .built)
    Do $$$AssertEquals(code, "", "the seed builds")
    Set ctx = ..Context(seed, body)
    Set ctx.binding.locations = [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-A"}},
        {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}]
    Set outcome = ##class(Shutter.FHIR.Judge).Judge(ctx, .text, .detail)
    Do $$$AssertEquals(outcome _ " " _ detail.reason, "verified committed_current", "the pair as mapped verifies (" _ text _ " " _ detail.%ToJSON() _ ")")
    Set other = ##class(Shutter.Test.FHIRJudge).LocationBody("b")
    Set other.identifier = [{"system": "urn:another:ward", "value": "WARD-B"}]
    Set ctx.locations.%Get(1).body = other.%ToJSON()
    Set outcome = ##class(Shutter.FHIR.Judge).Judge(ctx, .text, .detail)
    Do $$$AssertEquals(outcome _ " " _ detail.reason, "committed_review location_changed", "the value under another system (" _ text _ ")")
    Do $$$AssertEquals(detail."committed_version", "2", "the update itself is committed")
    Do $$$AssertTrue(detail.note [ "Location/ward-b", "and the note names the Location: " _ detail.note)
    // The other case: the same value, the system as mapped, in another letter case.
    Set other.identifier = [{"system": "urn:shutter:demo:ward", "value": "ward-b"}]
    Set ctx.locations.%Get(1).body = other.%ToJSON()
    Set outcome = ##class(Shutter.FHIR.Judge).Judge(ctx, .text, .detail)
    Do $$$AssertEquals(outcome _ " " _ detail.reason, "committed_review location_changed", "the value is case-sensitive (" _ text _ ")")
}

/// Build refuses a time as the event time, and the Judge's reader refuses it too.
Method Refused(time As %String, what As %String)
{
    Set code = ##class(Shutter.FHIR.Plan).Build(..Seed(), ..View(), time, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "FHIR_SHAPE_UNSUPPORTED", what _ " is refused: " _ time)
    Do $$$AssertEquals(detail.reason, "event_time", what _ ": named as the event time")
    Do $$$AssertEquals(body, "", what _ ": no body")
    Do $$$AssertNotTrue(##class(Shutter.FHIR.Judge).Instant(time, .seconds), what _ ": the Judge does not read it either")
}

/// Build accepts a time, and the body it writes with it is judged verified: no time Build takes is one the Judge cannot read.
Method Accepted(time As %String, what As %String)
{
    Set seed = ..Seed()
    Set code = ##class(Shutter.FHIR.Plan).Build(seed, ..View(), time, ..Marker(), .body, .detail)
    Do $$$AssertEquals(code, "", what _ " builds: " _ time)
    Do $$$AssertTrue(##class(Shutter.FHIR.Judge).Instant(time, .seconds), what _ ": the Judge reads it")
    Set ctx = ..Context(seed, body)
    Set ctx.binding."event_time" = time
    Set outcome = ##class(Shutter.FHIR.Judge).Judge(ctx, .text, .jd)
    Do $$$AssertEquals(outcome _ " " _ jd.reason, "verified committed_current", what _ ": judged verified (" _ text _ " " _ jd.%ToJSON() _ ")")
}

/// The seed read, as text.
ClassMethod Seed() As %String
{
    Quit ##class(Shutter.Test.FHIRPlan).Text("Seed")
}

ClassMethod View() As %DynamicObject
{
    Quit ##class(Shutter.Test.FHIRPlan).View()
}

ClassMethod Marker() As %DynamicObject
{
    Quit ##class(Shutter.Test.FHIRPlan).Marker()
}

/// The context of a clean walk after the approved body was sent: the receiver answered 200 with W/"2", and the vread,
/// the history (newest first) and the current read all show version "2". <var>committed</var> is the text the receiver
/// committed when it is not the approved body itself. Every body is put in as text, so nothing normalises it.
ClassMethod Context(seed As %String, body As %String, committed As %String = "") As %DynamicObject
{
    Set judge = "Shutter.Test.FHIRJudge", marker = ..Marker()
    Set v = $REPLACE($SELECT(committed = "": body, 1: committed), """versionId"":""1""", """versionId"":""2""")
    Set put = ",""request"":{""method"":""PUT"",""url"":""Encounter/enc-1""}}"
    Set bundle = "{""resourceType"":""Bundle"",""type"":""history"",""entry"":[{""resource"":" _ v _ put _ ",{""resource"":" _ seed _ put _ "]}"
    Set media = "application/fhir+json; charset=UTF-8"
    Set ctx = {"binding": {"expected_etag": "W/\"1\"", "base_version_id": "1", "operation_id": (marker.code), "marker_system": (marker.system),
            "encounter_id": "enc-1", "encounter_identifier": {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49", "value": "V1001"},
            "patient": {"reference": "Patient/demo-p1", "identifier": {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.48", "value": "MRN-Ab77"}},
            "prior_location": "Location/ward-a", "target_location": "Location/ward-b",
            "locations": [{"reference": "Location/ward-a", "checked_identifier": "WARD-A"}, {"reference": "Location/ward-b", "checked_identifier": "WARD-B"}],
            "event_time": (..#EVENTTIME), "server_owned_fields": []},
        "base_body": (seed), "expected_body": (body),
        "attempt": {"outcome": "applied", "http_status": 200, "response_etag": "W/\"2\"", "response_location": "http://ward.example/fhir/r4/Encounter/enc-1/_history/2", "seconds_since": 0},
        "settle_final_seconds": 70,
        "vread": {"http_status": 200, "etag": "W/\"2\"", "content_type": (media), "body": (v)},
        "history": {"http_status": 200, "content_type": (media), "body": (bundle)},
        "current": {"http_status": 200, "etag": "W/\"2\"", "content_type": (media), "body": (v)},
        "patient": {"http_status": 200, "body": ($CLASSMETHOD(judge, "PatientBody").%ToJSON())},
        "locations": []}
    For ward = "a", "b" {
        Do ctx.locations.%Push({"reference": ("Location/ward-" _ ward), "http_status": 200, "body": ($CLASSMETHOD(judge, "LocationBody", ward).%ToJSON())})
    }
    Quit ctx
}

}
