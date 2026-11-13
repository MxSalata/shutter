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
