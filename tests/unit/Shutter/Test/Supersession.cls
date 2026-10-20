/// The matcher's reading of the later events (docs/CONTRACTS.md, section 6.1), which the gate's ordering check reads
/// too: a later transfer whose delivery also failed supersedes outside a chain, never an admission and never inside an
/// ordered chain, and a later discharge that failed supersedes nothing; a later event whose time lies in the future
/// supersedes nothing and makes the order a person's question when believing it would change the reading. Each test builds a case in memory (never saved) and a snapshot summary by hand.
Class Shutter.Test.Supersession Extends %UnitTest.TestCase
{

/// A failed transfer of ENC-9001 at 08:20.
Method Case(event As %String = "transfer") As Shutter.Store.Case
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "UT-SUPERSESSION", c.Event = event, c.EventTime = "2026-10-15T08:20:00Z", c.EncounterId = "ENC-9001"
    Set c.PatientId = "MRN9001", c.PatientIdAuthority = "HOSP", c.FailureKind = "delivery_failed", c.Ward = "WARD-B"
    Set c.OperationKey = "PAS^HOSP^MRN9001^ENC-9001^" _ event _ "^2026-10-15T08:20:00Z"
    Quit c
}

/// A summary with the case's own failed row, the timeline rows and history entries given, the evidence taken at 09:30.
Method Summary(case As Shutter.Store.Case, timeline As %DynamicArray, history As %DynamicArray) As %DynamicObject
{
    Set own = {"event": (case.Event), "ward": "WARD-B", "event_time": (case.EventTime), "operation_key": (case.OperationKey), "sent_at": "2026-10-15 08:20:01.000", "source": "feed", "later": false, "this_case": true, "outcome": "unavailable"}
    Set rows = [(own)], iter = timeline.%GetIterator()
    While iter.%GetNext(.i, .r) { Do rows.%Push(r) }
    Set first = {"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-15T08:00:00Z", "applied_at": "2026-10-15T08:00:02Z", "operation_key": "PAS^HOSP^MRN9001^ENC-9001^admit^2026-10-15T08:00:00Z"}
    Set all = [(first)], iter = history.%GetIterator()
    While iter.%GetNext(.i, .h) { Do all.%Push(h) }
    Set s = {"message": {"message_time": "2026-10-15T08:20:00Z", "event_recorded": "2026-10-15T08:20:00Z"}, "observed_at": "2026-10-15T09:30:00Z", "ward_state_http_status": 200}
    Set s.timeline = rows
    Set ws = {"encounter_id": "ENC-9001", "patient_id": "MRN9001", "patient_id_authority": "HOSP", "state": "admitted", "ward": "WARD-A", "version": 1}
    Set ws.history = all, s."ward_state" = ws
    Quit s
}

/// A row of the feed's timeline later than the case, with its delivery outcome.
Method Row(event As %String, ward As %String, time As %String, outcome As %String, source As %String = "feed") As %DynamicObject
{
    Set key = "PAS^HOSP^MRN9001^ENC-9001^" _ event _ "^" _ time
    Quit {"event": (event), "ward": (ward), "event_time": (time), "operation_key": (key), "sent_at": ($TRANSLATE($EXTRACT(time, 1, 19), "T", " ") _ ".500"), "source": (source), "later": true, "this_case": false, "outcome": (outcome)}
}

/// The rest of what a resend needs (E2): the receiver was unavailable, no receipt, conditional writes.
Method Resendable(summary As %DynamicObject) As %DynamicObject
{
    Set summary.failure = {"reason_code": "ward_unavailable", "http_status": 503}, summary."receipt_http_status" = 404
    Set summary.route = {"capabilities": {"conditional_writes": true}}
    Quit summary
}

Method Conditions(case As Shutter.Store.Case, summary As %DynamicObject, chain As %String = "single") As %DynamicObject
{
    Quit ##class(Shutter.Catalogue.Matcher).Conditions(case, summary, chain)
}

Method TestLaterAppliedTransferStillSupersedes()
{
    Set c = ..Case()
    Set s = ..Summary(c, [(..Row("transfer", "WARD-C", "2026-10-15T09:00:00Z", "applied"))], [])
    Set k = ..Conditions(c, s)
    Do $$$AssertEquals(k."later_applied", "transfer", "an applied later transfer")
    Do $$$AssertEquals(k."event_time", "plausible", "its time is sound")
}

Method TestLaterFailedTransferSupersedesOutsideAChain()
{
    Set c = ..Case()
    Set s = ..Summary(c, [(..Row("transfer", "WARD-C", "2026-10-15T09:00:00Z", "unavailable"))], [])
    Do $$$AssertEquals(..Conditions(c, s)."later_applied", "transfer", "a later transfer whose delivery failed too makes the earlier one stale")
    Set later = ##class(Shutter.Catalogue.Matcher).Later(s, c, "single")
    Do $$$AssertEquals(later.%Size(), 1, "one later event")
    Do $$$AssertNotTrue(later.%Get(0).delivered, "marked as not delivered, for the gate's wording")
    Do $$$AssertEquals(..Conditions(c, s, "ordered")."later_applied", "none", "in an ordered chain the incident sends both in order")
    Do $$$AssertEquals(..Conditions(c, s, "interleaved")."later_applied", "none", "nor in an interleaved chain")
}

Method TestLaterUncertainTransferCounts()
{
    Set c = ..Case()
    Set s = ..Summary(c, [(..Row("transfer", "WARD-C", "2026-10-15T09:00:00Z", "uncertain"))], [])
    Do $$$AssertEquals(..Conditions(c, s)."later_applied", "transfer", "a later transfer whose outcome is uncertain: applied or not, it is the later word")
}

Method TestLaterFailedDischargeLeavesTheResend()
{
    Set c = ..Case()
    Set s = ..Resendable(..Summary(c, [(..Row("discharge", "", "2026-10-15T10:00:00Z", "unavailable"))], []))
    Set s."observed_at" = "2026-10-15T10:30:00Z"
    Set k = ..Conditions(c, s)
    Do $$$AssertEquals(k."later_applied", "none", "a later discharge the receiver has not applied supersedes nothing")
    Do $$$AssertEquals(k."event_time", "plausible", "and raises no doubt")
    Set m = ##class(Shutter.Catalogue.Matcher).Match(k)
    Do $$$AssertEquals(m.decision _ " " _ m.entry, "policy E2", "the transfer is resent by policy, and the discharge's own case follows it")
}

Method TestAdmissionIsNeverOvertakenByAFailure()
{
    Set c = ..Case("admit")
    Set s = ..Summary(c, [(..Row("transfer", "WARD-C", "2026-10-15T09:00:00Z", "unavailable"))], [])
    Set s."ward_state" = {"error": "not found"}, s."ward_state_http_status" = 404
    Do $$$AssertEquals(..Conditions(c, s)."later_applied", "none", "a failed admission stays due whatever failed after it")
}

Method TestOnlyRecordedFailuresCount()
{
    Set c = ..Case()
    Set s = ..Summary(c, [(..Row("transfer", "WARD-C", "2026-10-15T09:00:00Z", "unknown")), (..Row("transfer", "WARD-D", "2026-10-15T09:10:00Z", "unknown", "index")), (..Row("update", "", "2026-10-15T09:20:00Z", "unavailable"))], [])
    Do $$$AssertEquals(..Conditions(c, s)."later_applied", "none", "a message still in flight, an indexed one and a failed update supersede nothing")
}

Method TestFutureLaterEventSupersedesNothing()
{
    Set c = ..Case()
    // Applied at 09:00, but timed the next day: the time lies in the future of both the receiver's write and the evidence.
    Set h = {"version_after": 2, "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-16T09:00:00Z", "applied_at": "2026-10-15T09:00:02Z", "operation_key": "PAS^HOSP^MRN9001^ENC-9001^transfer^2026-10-16T09:00:00Z"}
    Set s = ..Summary(c, [], [(h)])
    Set k = ..Conditions(c, s)
    Do $$$AssertEquals(k."later_applied", "none", "the future-timed transfer does not close the genuine failure")
    Do $$$AssertEquals(k."event_time", "later_event_future", "the order is a person's question")
    Set later = ##class(Shutter.Catalogue.Matcher).Later(s, c, "single")
    Do $$$AssertNotTrue(later.%Get(0).plausible, "flagged for the gate")
}

Method TestFutureUpdateRaisesNoDoubt()
{
    Set c = ..Case()
    // An A08 applied at 09:10 but timed the next day: an update supersedes nothing, so its time decides nothing.
    Set u = ..Row("update", "", "2026-10-16T09:10:00Z", "applied")
    Set u."sent_at" = "2026-10-15 09:10:00.000"
    Set s = ..Resendable(..Summary(c, [(u)], []))
    Set k = ..Conditions(c, s)
    Do $$$AssertEquals(k."later_applied", "none", "the future-timed update does not count")
    Do $$$AssertEquals(k."event_time", "plausible", "nor does it make the order a person's question")
    Set m = ##class(Shutter.Catalogue.Matcher).Match(k)
    Do $$$AssertEquals(m.decision _ " " _ m.entry, "policy E2", "so the resend stands")
    // A sound later transfer settles the order, whatever the update's time.
    Do s.timeline.%Push(..Row("transfer", "WARD-C", "2026-10-15T09:00:00Z", "applied"))
    Set k = ..Conditions(c, s)
    Do $$$AssertEquals(k."later_applied", "transfer", "the plausible transfer supersedes")
    Do $$$AssertEquals(k."event_time", "plausible", "and the future update does not block the closure")
}

Method TestSoundTransferSettlesTheOrder()
{
    Set c = ..Case()
    // A plausible applied transfer at 09:00, and a discharge applied at 09:20 but timed the next day.
    Set h = {"version_after": 3, "event": "discharge", "ward": "", "event_time": "2026-10-16T09:20:00Z", "applied_at": "2026-10-15T09:20:02Z", "operation_key": "PAS^HOSP^MRN9001^ENC-9001^discharge^2026-10-16T09:20:00Z"}
    Set s = ..Summary(c, [(..Row("transfer", "WARD-C", "2026-10-15T09:00:00Z", "applied"))], [(h)])
    Set k = ..Conditions(c, s)
    Do $$$AssertEquals(k."later_applied", "transfer", "the sound transfer supersedes")
    Do $$$AssertEquals(k."event_time", "plausible", "so the discharge's doubtful time changes nothing")
}

Method TestFeedRowTimedAfterItWasSent()
{
    Set c = ..Case()
    Set r = ..Row("transfer", "WARD-C", "2026-10-15T09:20:00Z", "applied")
    // Sent at 09:00 with an event time twenty minutes on.
    Set r."sent_at" = "2026-10-15 09:00:00.000"
    Set s = ..Summary(c, [(r)], [])
    Set k = ..Conditions(c, s)
    Do $$$AssertEquals(k."later_applied", "none", "a row timed after it was sent supersedes nothing")
    Do $$$AssertEquals(k."event_time", "later_event_future", "and asks for a person")
}

Method TestOwnTimeChecksComeFirst()
{
    Set c = ..Case()
    Set c.EventTime = "2026-10-15T07:50:00Z"
    Set h = {"version_after": 2, "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-16T09:00:00Z", "applied_at": "2026-10-15T09:00:02Z", "operation_key": "k"}
    Set s = ..Summary(c, [], [(h)])
    Do $$$AssertEquals(..Conditions(c, s)."event_time", "before_admission", "the failed event's own doubt is named first")
}

}
