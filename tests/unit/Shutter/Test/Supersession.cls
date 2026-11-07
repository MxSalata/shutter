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

/// A row of the store for a timeline test: the feed's operation on the encounter, its header to the receiver, and the
/// connector's answer. The ids go in rows, for the clean-up.
Method StoreRow(patient As %String, authority As %String, event As %String, time As %String, outcome As %String, ByRef rows)
{
    Set op = ##class(Shutter.Msg.WardOperation).%New()
    Set op.EncounterId = "ENC-UT-SHARED", op.PatientId = patient, op.PatientIdAuthority = authority, op.Event = event, op.Ward = "WARD-X"
    Set op.EventTime = time, op.OperationKey = "PAS^" _ authority _ "^" _ patient _ "^ENC-UT-SHARED^" _ event _ "^" _ time
    Do $$$AssertStatusOK(op.%Save(), "the operation")
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.MessageBodyClassName = "Shutter.Msg.WardOperation", h.MessageBodyId = op.%Id(), h.TargetConfigName = "UT Receiver"
    Set h.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Do $$$AssertStatusOK(h.%Save(), "its header")
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.Outcome = outcome
    Do $$$AssertStatusOK(r.%Save(), "the connector's answer")
    Set a = ##class(Ens.MessageHeader).%New()
    Set a.MessageBodyClassName = "Shutter.Msg.WardResult", a.MessageBodyId = r.%Id(), a.CorrespondingMessageId = h.%Id(), a.TimeCreated = h.TimeCreated
    Do $$$AssertStatusOK(a.%Save(), "the answer's header")
    Set rows($I(rows)) = $LISTBUILD(op.%Id(), h.%Id(), r.%Id(), a.%Id())
}

/// Two patients share a visit number (a visit number reissued, or two authorities' numbering): the other's later transfer,
/// refused or failed, is no word on this patient's place. It isn't in the case's timeline, so it can't close the case, and
/// the index's rows for the visit keep to the patient too. A row of the case's own patient still counts.
Method TestAnotherPatientOnTheVisitClosesNothing()
{
    Set c = ..Case()
    Set c.EncounterId = "ENC-UT-SHARED", c.PatientId = "MRN-P2", c.PatientIdAuthority = "HOSP", c.Receiver = "UT Receiver"
    Set c.OperationKey = "PAS^HOSP^MRN-P2^ENC-UT-SHARED^transfer^2026-10-15T08:20:00Z"
    Kill rows
    Do ..StoreRow("MRN-P2", "HOSP", "transfer", "2026-10-15T08:20:00Z", "unavailable", .rows)
    Do ..StoreRow("MRN-P1", "HOSP", "transfer", "2026-10-15T09:00:00Z", "refused", .rows)
    Do ..StoreRow("MRN-P2", "OTHER", "transfer", "2026-10-15T09:05:00Z", "applied", .rows)
    Set ix = ##class(Shutter.Index.Message).%New()
    Set ix.DocId = "999000001", ix.VisitNumber = "ENC-UT-SHARED", ix.PatientId = "MRN-P1", ix.PatientIdAuthority = "HOSP", ix.Event = "transfer", ix.EventTime = "2026-10-15T09:10:00Z", ix.ControlId = "UT-SHARED-1"
    Do $$$AssertStatusOK(ix.%Save(), "an index row of the other patient")
    Set iy = ##class(Shutter.Index.Message).%New()
    Set iy.DocId = "999000002", iy.VisitNumber = "ENC-UT-SHARED", iy.PatientId = "MRN-P2", iy.PatientIdAuthority = "HOSP", iy.Event = "update", iy.EventTime = "2026-10-15T09:15:00Z", iy.ControlId = "UT-SHARED-2"
    Do $$$AssertStatusOK(iy.%Save(), "an index row of this patient")
    Try {
        Set timeline = ##class(Shutter.Index.Timeline).ForCase(c)
        Set found = "", iter = timeline.%GetIterator()
        While iter.%GetNext(.i, .ev) { Set found = found _ $SELECT(found = "": "", 1: ",") _ $PIECE(ev."event_time", "T", 2) }
        Do $$$AssertEquals(found, "08:20:00Z,09:15:00Z", "only this patient's rows, from the feed and the index: " _ found)
        Set s = ..Summary(c, [], [])
        Set s.timeline = timeline
        Do $$$AssertEquals(..Conditions(c, s)."later_applied", "none", "the other patient's transfer doesn't overtake this one")
        // The same case once its own patient has moved on.
        Do ..StoreRow("MRN-P2", "HOSP", "transfer", "2026-10-15T09:20:00Z", "applied", .rows)
        Set s.timeline = ##class(Shutter.Index.Timeline).ForCase(c)
        Do $$$AssertEquals(..Conditions(c, s)."later_applied", "transfer", "this patient's own later transfer does")
        // The failsafe at the point of the resend still reads the whole visit: another patient's message in flight holds a write.
        Do $$$AssertEquals(##class(Shutter.Index.Message).ForVisit("ENC-UT-SHARED").%Size(), 2, "ForVisit with no patient: every row of the visit")
    } Catch ex {
        Do $$$AssertTrue(0, "no error: " _ ex.DisplayString())
    }
    Do ##class(Shutter.Index.Message).%DeleteId(ix.%Id())
    Do ##class(Shutter.Index.Message).%DeleteId(iy.%Id())
    For n = 1:1:rows {
        Do ##class(Shutter.Msg.WardOperation).%DeleteId($LIST(rows(n), 1))
        Do ##class(Ens.MessageHeader).%DeleteId($LIST(rows(n), 2))
        Do ##class(Shutter.Msg.WardResult).%DeleteId($LIST(rows(n), 3))
        Do ##class(Ens.MessageHeader).%DeleteId($LIST(rows(n), 4))
    }
}

Method TestLaterAppliedTransferStillSupersedes()
{
    Set c = ..Case()
    Set s = ..Summary(c, [(..Row("transfer", "WARD-C", "2026-10-15T09:00:00Z", "applied"))], [])
    Set k = ..Conditions(c, s)
    Do $$$AssertEquals(k."later_applied", "transfer", "an applied later transfer")
    Do $$$AssertEquals(k."later_delivery", "applied", "which reached the receiver")
    Do $$$AssertEquals(k."event_time", "plausible", "its time is sound")
}

Method TestLaterFailedTransferSupersedesOutsideAChain()
{
    Set c = ..Case()
    Set s = ..Summary(c, [(..Row("transfer", "WARD-C", "2026-10-15T09:00:00Z", "unavailable"))], [])
    Do $$$AssertEquals(..Conditions(c, s)."later_applied", "transfer", "a later transfer whose delivery failed too makes the earlier one stale")
    Do $$$AssertEquals(..Conditions(c, s)."later_delivery", "sent", "the later word reached the receiver only as a message the feed sent")
    Set later = ##class(Shutter.Catalogue.Matcher).Later(s, c, "single")
    Do $$$AssertEquals(later.%Size(), 1, "one later event")
    Do $$$AssertNotTrue(later.%Get(0).delivered, "marked as not delivered, for the gate's wording")
    Do $$$AssertEquals(later.%Get(0)."operation_key", "PAS^HOSP^MRN9001^ENC-9001^transfer^2026-10-15T09:00:00Z", "named by the key it was sent as")
    Do $$$AssertNotTrue(later.%Get(0).%IsDefined("case_id"), "no case is known for it here")
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
    Set m = ##class(Shutter.Catalogue.Matcher).Match(k)
    Do $$$AssertEquals(m.decision _ " " _ m.entry, "person E13", "the catalogue sends the doubtful order to a person, with no board")
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
    Set m = ##class(Shutter.Catalogue.Matcher).Match(k)
    Do $$$AssertEquals(m.decision _ " " _ m.entry, "person E13", "the catalogue sends the doubtful order to a person, with no board")
}

/// Describe: the words the gate's ordering check and the verifier use for a later event (CONTRACTS 6.1).
Method TestDescribe()
{
    Set c = ..Case()
    Set s = ..Summary(c, [(..Row("transfer", "WARD-C", "2026-10-15T09:00:00Z", "unavailable"))], [])
    Set later = ##class(Shutter.Catalogue.Matcher).Later(s, c, "single")
    Set ev = later.%Get(0)
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Describe(ev), "transfer to WARD-C at 2026-10-15T09:00:00Z, sent as PAS^HOSP^MRN9001^ENC-9001^transfer^2026-10-15T09:00:00Z (its delivery failed or is uncertain; its own case recovers it)", "an undelivered later transfer, with the key it was sent as")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Describe(ev, 0), "transfer to WARD-C at 2026-10-15T09:00:00Z", "the bare description")
    Set ev."case_id" = "C-000042"
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Describe(ev), "transfer to WARD-C at 2026-10-15T09:00:00Z, sent as PAS^HOSP^MRN9001^ENC-9001^transfer^2026-10-15T09:00:00Z (its delivery failed or is uncertain; its case C-000042 recovers it)", "its case, when one is known")
    Set h = {"word": "discharge", "event": "discharge", "ward": "", "event_time": "2026-10-15T10:00:00Z", "from": "history", "delivered": true, "plausible": true}
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Describe(h), "discharge at 2026-10-15T10:00:00Z (receiver history)", "a discharge from the receiver's history")
    Set h.word = "cancelled", h.event = "cancel_transfer", h.ward = "WARD-B"
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Describe(h), "cancel of the event at 2026-10-15T10:00:00Z (receiver history)", "a cancel, with no ward")
    Set h.word = "merge", h.event = "merge"
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Describe(h, 0), "merge at 2026-10-15T10:00:00Z", "a merge")
    Set h.word = "admit", h.event = "admit", h.ward = "WARD-A"
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Describe(h, 0), "admission at 2026-10-15T10:00:00Z", "an admission")
    Set t = {"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-15T09:00:00Z", "from": "timeline", "delivered": true, "plausible": true}
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Describe(t), "transfer to WARD-C at 2026-10-15T09:00:00Z", "an applied feed transfer carries no origin")
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
