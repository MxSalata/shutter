/// The drafted correction sequence (Shutter.Util.HistoryDraft, CONTRACTS 10): the shape for k later movements, every reason it
/// draws nothing, the text of the cancels and the replays, and that no message text reaches the plan. Decide and Draft run on
/// facts the test gives, so the cases are not saved and no message store is read; the last tests read a saved message, the
/// index and a saved case, and remove them.
Class Shutter.Test.HistoryDraft Extends %UnitTest.TestCase
{

Parameter CASEID = "UT-HISTORYDRAFT";

/// A body for a test: a stored ADT message of this encounter, with its own control id.
ClassMethod Body(control As %String, trigger As %String, ward As %String, prior As %String = "", extra As %String = "", pid As %String = "SYNTH^TEST") As %String
{
    Set cr = $CHAR(13)
    Set text = "MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261019100000||ADT^" _ trigger _ "^ADT_" _ trigger _ "|" _ control _ "|P|2.5.1" _ cr
    Set text = text _ "EVN|" _ trigger _ "|20261019100000||||20261019100000" _ cr
    Set text = text _ "PID|1||MRN-UT1^^^HOSP^MR||" _ pid _ "||19700202|F" _ cr
    Set text = text _ "PV1|1|I|" _ ward _ "^BAY1^01^HOSP|||" _ prior _ "|||||||||||||ENC-UT1|||||||||||||||||||||||||20261019080000" _ cr
    Quit text _ extra
}

ClassMethod Key(event As %String, time As %String) As %String
{
    Quit "PAS^HOSP^MRN-UT1^ENC-UT1^" _ event _ "^" _ time
}

/// The failed transfer to WARD-B at 09:00, with the case's identifiers.
ClassMethod Case() As Shutter.Store.Case
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = ..#CASEID, c.Event = "transfer", c.Ward = "WARD-B", c.EventTime = "2026-10-19T09:00:00Z"
    Set c.OperationKey = ..Key("transfer", c.EventTime), c.EncounterId = "ENC-UT1", c.PatientId = "MRN-UT1", c.PatientIdAuthority = "HOSP"
    Set c.Receiver = "UT Records Receiver", c.SourceMessageId = "MSG-F", c.State = "escalated"
    Quit c
}

/// A snapshot with the given later movements, each [event, ward, time], applied at the receiver and in the feed.
ClassMethod Summary(moves As %DynamicArray) As %DynamicObject
{
    Set history = [{"event": "admit", "ward": "WARD-A", "event_time": "2026-10-19T08:00:00Z", "operation_key": (..Key("admit", "2026-10-19T08:00:00Z")), "applied_at": "2026-10-19T08:00:01Z"}]
    Set timeline = [], li = moves.%GetIterator(), newest = ""
    While li.%GetNext(, .m) {
        If '$ISOBJECT(newest) || (##class(Shutter.Util.HistoryDraft).Gap(newest.%Get(2), m.%Get(2)) > 0) Set newest = m
        Set key = ..Key(m.%Get(0), m.%Get(2))
        Do history.%Push({"event": (m.%Get(0)), "ward": (m.%Get(1)), "event_time": (m.%Get(2)), "operation_key": (key), "applied_at": (m.%Get(2))})
        Set row = {"event": (m.%Get(0)), "ward": (m.%Get(1)), "event_time": (m.%Get(2)), "operation_key": (key), "source": "feed", "outcome": "applied", "sent_at": (m.%Get(2)), "source_message_id": ("MSG-" _ m.%Get(1)), "ens_header_id": ("H-" _ m.%Get(1))}
        Do row.%Set("later", 1, "boolean")
        Do timeline.%Push(row)
    }
    // The receiver's placement follows its newest movement, as a real receiver's does.
    Set gone = $ISOBJECT(newest) && (newest.%Get(0) = "discharge")
    Set state = $SELECT(gone: "discharged", 1: "admitted"), ward = $SELECT(gone: "", $ISOBJECT(newest): newest.%Get(1), 1: "WARD-A")
    Quit {"observed_at": "2026-10-19T12:00:00Z", "receipt_http_status": 404, "ward_state": {"state": (state), "ward": (ward), "version": 3, "history": (history)}, "timeline": (timeline)}
}

/// Facts with cancels taken and everything caught up, and a body for the failed movement and each later one.
ClassMethod Facts(moves As %DynamicArray) As %DynamicObject
{
    Set facts = {"has_entry": true, "cancels": true, "caught_up": true, "merge_case": false, "resend_timestamp": "original", "pending": [], "patient_rows": []}
    Set bodies = {}, c = ..Case()
    Do bodies.%Set(c.OperationKey, {"text": (..Body("MSG-F", "A02", "WARD-B", "WARD-A^BAY1^01^HOSP")), "control_id": "MSG-F", "ens_header_id": "H-F"})
    Set prior = "WARD-B", li = moves.%GetIterator()
    While li.%GetNext(, .m) {
        Set key = ..Key(m.%Get(0), m.%Get(2)), trigger = $SELECT(m.%Get(0) = "discharge": "A03", 1: "A02")
        Do bodies.%Set(key, {"text": (..Body("MSG-" _ m.%Get(1), trigger, m.%Get(1), prior _ "^BAY2^04^HOSP")), "control_id": ("MSG-" _ m.%Get(1)), "ens_header_id": ("H-" _ m.%Get(1))})
        Set prior = m.%Get(1)
    }
    Set facts.bodies = bodies
    Quit facts
}

/// One later transfer to WARD-C, as S22 has it.
ClassMethod One() As %DynamicArray
{
    Quit [["transfer", "WARD-C", "2026-10-19T09:30:00Z"]]
}

ClassMethod Decide(case As Shutter.Store.Case, moves As %DynamicArray, facts As %DynamicObject = "", entry As %String = "E1") As %DynamicObject
{
    If '$ISOBJECT(facts) Set facts = ..Facts(moves)
    Quit ##class(Shutter.Util.HistoryDraft).Decide(case, ..Summary(moves), entry, facts, 1)
}

Method AssertCode(seq As %DynamicObject, code As %String, what As %String)
{
    Do $$$AssertEquals(seq."reason_code", code, what _ ": " _ seq.reason)
    Do $$$AssertNotTrue(seq.drawn, "nothing is drawn")
    Do $$$AssertEquals(seq.steps.%Size(), 0, "no steps")
    Do $$$AssertEquals(seq.count, 0, "no messages")
    Do $$$AssertEquals($EXTRACT(seq.reason, 1, 13), "No sequence: ", "the line says so")
}

// ---- the shape ----

Method TestOneLaterMovement()
{
    Set seq = ..Decide(..Case(), ..One())
    Do $$$AssertTrue(seq.drawn, "drawn: " _ seq.reason)
    Do $$$AssertEquals(seq.k, 1, "k = 1")
    Do $$$AssertEquals(seq.count, 3, "three messages")
    Do $$$AssertEquals(seq.steps.%Get(0).trigger, "A12", "a cancel first")
    Do $$$AssertEquals(seq.steps.%Get(1).trigger, "A02", "then the failed movement")
    Do $$$AssertEquals(seq.steps.%Get(1).ward, "WARD-B", "which is WARD-B")
    Do $$$AssertEquals(seq.steps.%Get(2).ward, "WARD-C", "then the later one")
    Do $$$AssertEquals(seq.steps.%Get(0).after."by_receiver", "WARD-A", "the cancel leaves this receiver at A")
    Do $$$AssertEquals(seq.steps.%Get(0).after."by_source", "WARD-B", "and the source at B")
    Do $$$AssertEquals(seq.steps.%Get(1).after."by_receiver", "WARD-B", "then B")
    Do $$$AssertEquals(seq.steps.%Get(2).after."by_receiver", "WARD-C", "then C")
    Do $$$AssertEquals(seq.end.history.%ToJSON(), "[""WARD-A"",""WARD-B"",""WARD-C""]", "the history at the end")
    Do $$$AssertEquals(seq."receiver_version", "3", "the version the draft was drawn at")
}

Method TestTwoLaterMovements()
{
    Set moves = [["transfer", "WARD-C", "2026-10-19T09:30:00Z"], ["transfer", "WARD-D", "2026-10-19T10:00:00Z"]]
    Set seq = ..Decide(..Case(), moves)
    Do $$$AssertTrue(seq.drawn, "drawn: " _ seq.reason)
    Do $$$AssertEquals(seq.count, 5, "five messages")
    Do $$$AssertEquals(seq.steps.%Get(0).cancels.ward, "WARD-D", "the newest is cancelled first")
    Do $$$AssertEquals(seq.steps.%Get(1).cancels.ward, "WARD-C", "then the one before")
    Do $$$AssertEquals(seq.steps.%Get(2).ward, "WARD-B", "the failed movement")
    Do $$$AssertEquals(seq.steps.%Get(3).ward, "WARD-C", "the later ones oldest first")
    Do $$$AssertEquals(seq.steps.%Get(4).ward, "WARD-D", "the last")
    Do $$$AssertEquals(seq.steps.%Get(0).after."by_receiver", "WARD-C", "after the first cancel, C")
    Do $$$AssertEquals(seq.steps.%Get(1).after."by_receiver", "WARD-A", "after the second, A")
    Set draft = ##class(Shutter.Util.HistoryDraft).Draft(..Case(), ..Summary(moves), "E1", ..Facts(moves))
    Do $$$AssertTrue(draft.header.%Get(6) [ "wrong place 4 times", "four in-between states: " _ draft.header.%Get(6))
    Do $$$AssertTrue(draft.header.%Get(6) [ "after message 4", "the fourth is listed")
    Do $$$AssertNotTrue(draft.header.%Get(6) [ "after message 5", "the last message is not in between")
}

Method TestThreeLaterMovements()
{
    Set moves = [["transfer", "WARD-C", "2026-10-19T09:30:00Z"], ["transfer", "WARD-D", "2026-10-19T10:00:00Z"], ["transfer", "WARD-E", "2026-10-19T10:30:00Z"]]
    Set seq = ..Decide(..Case(), moves)
    Do $$$AssertEquals(seq.count, 7, "seven messages: " _ seq.reason)
}

Method TestDischargeAfterIt()
{
    Set moves = [["discharge", "WARD-B", "2026-10-19T09:30:00Z"]]
    Set seq = ..Decide(..Case(), moves, "", "E6")
    Do $$$AssertTrue(seq.drawn, "drawn: " _ seq.reason)
    Do $$$AssertEquals(seq.steps.%Get(0).trigger, "A13", "a discharge is cancelled by A13")
    Do $$$AssertEquals(seq.steps.%Get(1).trigger, "A02", "then the transfer")
    Do $$$AssertEquals(seq.steps.%Get(2).trigger, "A03", "then the discharge")
    Do $$$AssertEquals(seq.end.ward, "discharged", "the patient ends discharged")
    Set a13 = ##class(Shutter.Util.HistoryDraft).CancelText("A13", ..Body("MSG-D", "A03", "WARD-B", "WARD-A^BAY1^01^HOSP"))
    Do $$$AssertEquals($PIECE(##class(Shutter.Util.HistoryDraft).Field(a13, "PV1", 3), "^", 1), "WARD-B", "PV1-3 is the discharge's own")
    Do $$$AssertEquals(##class(Shutter.Util.HistoryDraft).Field(a13, "PV1", 6), "", "PV1-6 is empty")
    Do $$$AssertEquals(##class(Shutter.Util.HistoryDraft).Field(a13, "PV1", 45), "", "PV1-45 is empty")
    Do $$$AssertEquals(##class(Shutter.Util.HistoryDraft).Field(a13, "MSH", 9), "ADT^A13^ADT_A01", "2.5.1 gives an A13 ADT_A01's structure")
}

Method TestTwoRowsOfOneKeyAreOneMovement()
{
    // Summary gives every later movement a timeline row and a history row under one key.
    Set seq = ..Decide(..Case(), ..One())
    Do $$$AssertEquals(seq.k, 1, "one movement")
}

/// Two movements with the same event and ward, 30 seconds apart, are two, which is what the steps' checklist would merge.
Method TestAlikeMovementsAreNotMerged()
{
    Set moves = [["transfer", "WARD-C", "2026-10-19T09:30:00Z"], ["transfer", "WARD-C", "2026-10-19T09:30:30Z"]]
    Set seq = ..Decide(..Case(), moves)
    Do $$$AssertEquals(seq.k, 2, "both in the feed and the history: two movements: " _ seq.reason)
    Set summary = ..Summary(moves)
    Do summary.timeline.%Remove(1)
    Set seq = ##class(Shutter.Util.HistoryDraft).Decide(..Case(), summary, "E1", ..Facts(moves), 1)
    Do ..AssertCode(seq, "history_mismatch", "in the history only")
}

// ---- the reasons ----

Method TestCancelsFalse()
{
    Set facts = ..Facts(..One()), facts.cancels = 0
    Do facts.%Set("cancels", 0, "boolean")
    Set seq = ..Decide(..Case(), ..One(), facts)
    Do ..AssertCode(seq, "cancels_false", "cancels false")
    Do $$$AssertTrue(seq.reason [ "cancels: false", "names the flag")
    Set steps = ##class(Shutter.Util.HistoryCorrection).Steps(..Case(), ..Summary(..One()), "E1")
    Do $$$AssertEquals(steps.steps.%Size(), 8, "the eight steps stay")
    Do $$$AssertNotTrue(steps.sequence.drawn, "and on a receiver the profile doesn't name nothing is drawn")
    Do $$$AssertTrue(steps.sequence.reason [ "no entry" , "saying so: " _ steps.sequence.reason)
}

Method TestNoProfileEntry()
{
    Set facts = ..Facts(..One())
    Do facts.%Set("has_entry", 0, "boolean")
    Set seq = ..Decide(..Case(), ..One(), facts)
    Do ..AssertCode(seq, "cancels_false", "no entry")
    Do $$$AssertTrue(seq.reason [ "no entry", "with its own wording")
    Do $$$AssertEquals(seq.%GetTypeOf("cancels_flag"), "null", "the flag has no answer")
}

Method TestOtherEntries()
{
    Set seq = ..Decide(..Case(), ..One(), "", "E5")
    Do ..AssertCode(seq, "not_e1_e6", "E5")
    Do $$$AssertTrue(seq.reason [ "E5", "names E5")
    Do ..AssertCode(..Decide(..Case(), ..One(), "", "E2"), "not_e1_e6", "another entry")
    Set c = ..Case(), c.Event = "admit"
    Do ..AssertCode(..Decide(c, ..One()), "not_e1_e6", "a failed admission")
}

Method TestLaterAdmission()
{
    Do ..AssertCode(..Decide(..Case(), [["admit", "WARD-C", "2026-10-19T09:30:00Z"]]), "later_not_movement", "a later admit")
}

Method TestLaterUndelivered()
{
    Set summary = ..Summary(..One()), row = summary.timeline.%Get(0)
    Set row.outcome = "failed"
    Do summary."ward_state".history.%Remove(1)
    Set seq = ##class(Shutter.Util.HistoryDraft).Decide(..Case(), summary, "E1", ..Facts(..One()), 1)
    Do ..AssertCode(seq, "later_undelivered", "a later transfer that failed")
}

Method TestHistoryRowTheFeedDidNotSend()
{
    Set summary = ..Summary(..One())
    Do summary.timeline.%Remove(0)
    Set seq = ##class(Shutter.Util.HistoryDraft).Decide(..Case(), summary, "E1", ..Facts(..One()), 1)
    Do ..AssertCode(seq, "history_mismatch", "a history row with no feed row")
}

/// The receiver's own placement disagrees with its history, as after a change by hand: the first cancel would miss.
Method TestPlacementDisagreesWithHistory()
{
    Set moves = [["transfer", "WARD-C", "2026-10-19T09:30:00Z"], ["transfer", "WARD-D", "2026-10-19T10:00:00Z"]]
    Set summary = ..Summary(moves), summary."ward_state".ward = "WARD-C"
    Set seq = ##class(Shutter.Util.HistoryDraft).Decide(..Case(), summary, "E1", ..Facts(moves), 1)
    Do ..AssertCode(seq, "history_mismatch", "placed at C, history ends at D")
    Do $$$AssertTrue((seq.reason [ "(WARD-C)") && (seq.reason [ "(WARD-D)"), "the line names both")
    Set summary = ..Summary(moves), summary."ward_state".state = "discharged", summary."ward_state".ward = ""
    Do ..AssertCode(##class(Shutter.Util.HistoryDraft).Decide(..Case(), summary, "E1", ..Facts(moves), 1), "history_mismatch", "discharged, history ends in a transfer")
    Set moves = [["discharge", "WARD-B", "2026-10-19T09:30:00Z"]]
    Set summary = ..Summary(moves), summary."ward_state".state = "admitted", summary."ward_state".ward = "WARD-B"
    Do ..AssertCode(##class(Shutter.Util.HistoryDraft).Decide(..Case(), summary, "E6", ..Facts(moves), 1), "history_mismatch", "still placed, history ends in a discharge")
    Set summary = ..Summary(moves), held = summary."ward_state"
    Do held.%Remove("state"), held.%Remove("ward")
    Do ..AssertCode(##class(Shutter.Util.HistoryDraft).Decide(..Case(), summary, "E6", ..Facts(moves), 1), "history_mismatch", "no placement given")
}

Method TestPending()
{
    Set facts = ..Facts(..One())
    Do facts.pending.%Push({"event": "transfer", "event_time": "2026-10-19T11:00:00Z", "ens_header_id": "H-9"})
    Set seq = ..Decide(..Case(), ..One(), facts)
    Do ..AssertCode(seq, "pending_message", "pending")
    Do $$$AssertTrue(seq.reason [ "H-9", "names the header")
}

/// A row for the patient's facts.
ClassMethod Row(visit As %String, event As %String, time As %String, sent As %String, key As %String = "") As %DynamicObject
{
    Quit {"visit_number": (visit), "event": (event), "event_time": (time), "sent_at": (sent), "operation_key": (key), "control_id": ("CTL-" _ event), "ens_header_id": "H-77"}
}

/// A new admission on a new visit number for the same patient.
Method TestNewAdmissionOnAnotherVisit()
{
    Set facts = ..Facts(..One())
    Do facts."patient_rows".%Push(..Row("ENC-UT2", "admit", "2026-10-19T09:40:00Z", "2026-10-19 09:40:01"))
    Set seq = ..Decide(..Case(), ..One(), facts)
    Do ..AssertCode(seq, "further_message", "another visit")
    Do $$$AssertTrue(seq.reason [ "ENC-UT2", "the line names the encounter: " _ seq.reason)
    Do $$$AssertTrue(seq.reason [ "H-77", "and the header")
    Set forPlan = ##class(Shutter.Util.HistoryDraft).Decide(..Case(), ..Summary(..One()), "E1", facts, 0)
    Do $$$AssertEquals(forPlan."reason_code", "further_message", "the plan's reason too")
    Do $$$AssertNotTrue(forPlan.reason [ "ENC-UT2", "but with no identifier the model view couldn't tokenise")
}

/// An earlier stay of the same patient is not a further message: it came before the failed one in both times.
Method TestEarlierStayDoesNotStopIt()
{
    Set facts = ..Facts(..One())
    Do facts."patient_rows".%Push(..Row("ENC-OLD", "discharge", "2026-09-01T09:00:00Z", "2026-09-01 09:00:01"))
    Do facts."patient_rows".%Push(..Row("ENC-UT1", "transfer", "2026-10-19T09:00:00Z", "2026-10-19 09:00:01", ..Case().OperationKey))
    Set seq = ..Decide(..Case(), ..One(), facts)
    Do $$$AssertTrue(seq.drawn, "drawn: " _ seq.reason)
    Do facts."patient_rows".%Push(..Row("ENC-OLD", "update", "2026-09-02T09:00:00Z", "2026-10-19 09:05:00"))
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "further_message", "but one received after the failed message is")
}

Method TestReceivedAfterTheSnapshot()
{
    Set facts = ..Facts(..One())
    Do facts."patient_rows".%Push(..Row("ENC-UT1", "update", "2026-10-19T09:10:00Z", "2026-10-19 12:30:00"))
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "further_message", "received after the snapshot")
}

Method TestUpdateInsideTheSpan()
{
    Set facts = ..Facts(..One())
    Do facts."patient_rows".%Push(..Row("ENC-UT1", "update", "2026-10-19T09:10:00Z", "2026-10-19 09:10:01", ..Key("update", "2026-10-19T09:10:00Z")))
    Set seq = ..Decide(..Case(), ..One(), facts)
    Do $$$AssertTrue(seq.drawn, "drawn: " _ seq.reason)
    Do $$$AssertEquals(seq."left_alone".%Size(), 1, "one row left alone")
    Do $$$AssertEquals(seq."left_alone".%Get(0)."event_time", "2026-10-19T09:10:00Z", "at its time")
}

Method TestDischargeAfterTheSpan()
{
    Set facts = ..Facts(..One())
    Do facts."patient_rows".%Push(..Row("ENC-UT1", "discharge", "2026-10-19T10:00:00Z", "2026-10-19 10:00:01"))
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "further_message", "an unexpected discharge")
}

Method TestUpdateAfterTheSpan()
{
    Set facts = ..Facts(..One())
    Do facts."patient_rows".%Push(..Row("ENC-UT1", "update", "2026-10-19T10:00:00Z", "2026-10-19 10:00:01"))
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "further_message", "an update after the span is further")
}

Method TestSecondMessageUnderAKey()
{
    Set facts = ..Facts(..One()), key = ..Key("transfer", "2026-10-19T09:30:00Z")
    Do facts."patient_rows".%Push({"visit_number": "ENC-UT1", "event": "transfer", "event_time": "2026-10-19T09:30:00Z", "sent_at": "2026-10-19 09:30:01", "operation_key": (key), "control_id": "ONE"})
    Do facts."patient_rows".%Push({"visit_number": "ENC-UT1", "event": "transfer", "event_time": "2026-10-19T09:30:00Z", "sent_at": "2026-10-19 09:31:01", "operation_key": (key), "control_id": "TWO"})
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "further_message", "two control ids under one key")
}

Method TestUnreadableRowTime()
{
    Set facts = ..Facts(..One())
    Do facts."patient_rows".%Push(..Row("ENC-UT9", "transfer", "", "2026-10-19 08:00:00"))
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "further_message", "a row with no time can't be ruled out")
}

Method TestIdentifierUnreadable()
{
    For prop = "PatientId", "PatientIdAuthority", "EncounterId" {
        Set c = ..Case(), $PROPERTY(c, prop) = ""
        Do ..AssertCode(..Decide(c, ..One()), "identifier_unreadable", prop _ " empty")
    }
    Set c = ..Case(), c.EncounterId = "-"
    Do ..AssertCode(..Decide(c, ..One()), "identifier_unreadable", "encounter -")
}

Method TestMerge()
{
    Set c = ..Case(), c.PriorPatientId = "MRN-OLD"
    Do ..AssertCode(..Decide(c, ..One()), "merge_seen", "a prior identifier")
    Set facts = ..Facts(..One())
    Do facts."patient_rows".%Push(..Row("ENC-UT1", "merge", "2026-09-01T09:00:00Z", "2026-09-01 09:00:01"))
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "merge_seen", "a merge row, at any time")
    Set facts = ..Facts(..One())
    Do facts.%Set("merge_case", 1, "boolean")
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "merge_seen", "a merge case with this patient as its prior")
}

/// A forwarded case stays as it is on every read, so it says no. An index behind passes in seconds, so it says not yet.
Method TestFeedNotIndexed()
{
    Set c = ..Case(), c.SourceNamespace = "UTOTHERNS"
    Do ..AssertCode(..Decide(c, ..One()), "forwarded_case", "a forwarded case")
    Set facts = ..Facts(..One())
    Do facts.%Set("caught_up", 0, "boolean")
    Set seq = ..Decide(..Case(), ..One(), facts)
    Do $$$AssertEquals(seq."reason_code", "feed_not_indexed", "an index behind: " _ seq.reason)
    Do $$$AssertNotTrue(seq.drawn, "nothing is drawn")
    Do $$$AssertEquals(seq.steps.%Size(), 0, "no steps")
    Do $$$AssertEquals($EXTRACT(seq.reason, 1, 17), "No sequence yet: ", "the line says not yet")
    Do $$$AssertTrue(seq.reason [ "Every read checks again", "and that a read checks again")
    Do facts.%Set("caught_up", 1, "boolean")
    Do $$$AssertTrue(..Decide(..Case(), ..One(), facts).drawn, "and once caught up it draws")
}

Method TestReceipt()
{
    Set summary = ..Summary(..One()), summary."receipt_http_status" = 200
    Do ..AssertCode(##class(Shutter.Util.HistoryDraft).Decide(..Case(), summary, "E1", ..Facts(..One()), 1), "receipt_present", "a receipt")
}

Method TestImplausibleTime()
{
    Set moves = [["transfer", "WARD-C", "2026-10-19T14:00:00Z"]]
    Do ..AssertCode(..Decide(..Case(), moves), "time_in_doubt", "a time after the snapshot")
}

Method TestTwoMovementsInOneSecond()
{
    Set moves = [["transfer", "WARD-C", "2026-10-19T09:30:00Z"], ["transfer", "WARD-D", "2026-10-19T09:30:00.5Z"]]
    Do ..AssertCode(..Decide(..Case(), moves), "time_in_doubt", "no order to draw")
}

Method TestEmptyPriorLocation()
{
    Set facts = ..Facts(..One()), key = ..Key("transfer", "2026-10-19T09:30:00Z")
    Do facts.bodies.%Set(key, {"text": (..Body("MSG-C", "A02", "WARD-C")), "control_id": "MSG-C", "ens_header_id": "H-C"})
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "pv1_6_empty", "no PV1-6 on the cancelled message")
}

Method TestZbe()
{
    Set facts = ..Facts(..One()), key = ..Key("transfer", "2026-10-19T09:30:00Z")
    Do facts.bodies.%Set(key, {"text": (..Body("MSG-C", "A02", "WARD-C", "WARD-B", "ZBE|1|20261019" _ $CHAR(13))), "control_id": "MSG-C", "ens_header_id": "H-C"})
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "zbe_present", "a ZBE segment")
}

Method TestBodyUnreadable()
{
    Set facts = ..Facts(..One()), key = ..Key("transfer", "2026-10-19T09:30:00Z")
    Do facts.bodies.%Remove(key)
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "body_unreadable", "a later message gone")
    Set facts = ..Facts(..One())
    Do facts.bodies.%Remove(..Case().OperationKey)
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "body_unreadable", "the failed message gone")
}

Method TestNoLaterMovement()
{
    Do ..AssertCode(..Decide(..Case(), []), "k_zero", "nothing later")
}

/// The order comes from seconds, whichever form the times came in: as text "+01:00" and fractions would sort otherwise.
Method TestTimesInOtherForms()
{
    // 10:15+01:00 is 09:15Z, and 09:40:00.250Z comes after it.
    Do $$$AssertEquals(##class(Shutter.Util.HistoryDraft).Norm("2026-10-19T10:15:00+01:00"), "2026-10-19T09:15:00Z", "an offset is shifted")
    Do $$$AssertEquals(##class(Shutter.Util.HistoryDraft).Gap("2026-10-19T10:15:00+01:00", "2026-10-19T09:40:00.250Z"), 1500, "seconds between the forms")
    Do $$$AssertEquals(##class(Shutter.Util.HistoryDraft).Norm("no time"), "", "text is no time")
    Set moves = [["transfer", "WARD-D", "2026-10-19T09:40:00.250Z"], ["transfer", "WARD-C", "2026-10-19T09:30:00.900Z"]]
    Set seq = ..Decide(..Case(), moves)
    Do $$$AssertTrue(seq.drawn, "fractional seconds: drawn: " _ seq.reason)
    Do $$$AssertEquals(seq.steps.%Get(0).cancels.ward, "WARD-D", "the later by seconds is cancelled first, whichever row came first")
    Do $$$AssertEquals(seq.steps.%Get(1).cancels.ward, "WARD-C", "then the earlier")
    // The matcher settles no order on a receiver's time with an offset, and that is a doubt here too, never a guess.
    Do ..AssertCode(..Decide(..Case(), [["transfer", "WARD-C", "2026-10-19T10:15:00+01:00"]]), "time_in_doubt", "an offset the matcher can't read")
}

// ---- the text ----

Method TestWithheldAboveAscii()
{
    Set moves = ..One(), facts = ..Facts(moves), failedKey = ..Case().OperationKey
    Do facts.bodies.%Set(failedKey, {"text": (..Body("MSG-F", "A02", "WARD-B", "WARD-A^BAY1^01^HOSP", "", "SYNTH^REN" _ $CHAR(232))), "control_id": "MSG-F", "ens_header_id": "H-F"})
    Set seq = ..Decide(..Case(), moves, facts)
    Do $$$AssertTrue(seq.drawn, "still drawn: " _ seq.reason)
    Do $$$AssertTrue(seq.steps.%Get(1)."non_ascii", "the replay is flagged")
    Do $$$AssertNotTrue(seq.steps.%Get(2)."non_ascii", "the other is not")
    Set draft = ##class(Shutter.Util.HistoryDraft).Draft(..Case(), ..Summary(moves), "E1", facts)
    Set row = draft.messages.%Get(1)
    Do $$$AssertEquals(row.%GetTypeOf("text"), "null", "its text is withheld")
    Do $$$AssertTrue(row.withheld [ "Don't paste this message", "and says why")
    Do $$$AssertTrue(draft.messages.%Get(2).text '= "", "another message's text is there")
    Do $$$AssertEquals(draft.messages.%Get(2).withheld, "", "with no warning")
    Do $$$AssertTrue(row.withheld [ "MSG-F", "naming the message that is in the store")
    Do $$$AssertNotTrue(draft.messages.%Get(0)."text" = "", "the cancel, which copies nothing above ASCII, keeps its text")
    Do $$$AssertEquals(draft.messages.%Get(0).withheld, "", "and has no warning")
}

/// A cancel isn't in the message store, so a character above ASCII in what it copies draws nothing, on either trigger.
Method TestCancelAboveAscii()
{
    Set moves = ..One(), facts = ..Facts(moves), key = ..Key("transfer", "2026-10-19T09:30:00Z")
    Do facts.bodies.%Set(key, {"text": (..Body("MSG-C", "A02", "WARD-C", "WARD-B^BAY2^04^HOSP", "", "SYNTH^REN" _ $CHAR(232))), "control_id": "MSG-C", "ens_header_id": "H-C"})
    Set seq = ..Decide(..Case(), moves, facts)
    Do ..AssertCode(seq, "cancel_non_ascii", "a transfer's PID")
    Do $$$AssertNotTrue(seq.reason [ "MSG-C", "the line for the plan names no message")
    Set draft = ##class(Shutter.Util.HistoryDraft).Draft(..Case(), ..Summary(moves), "E1", facts)
    Do $$$AssertNotTrue(draft.drawn, "the read stops too")
    Do $$$AssertEquals(draft.messages.%Size(), 0, "with no text")
    Set moves = [["discharge", "WARD-B", "2026-10-19T09:30:00Z"]], facts = ..Facts(moves), key = ..Key("discharge", "2026-10-19T09:30:00Z")
    Do facts.bodies.%Set(key, {"text": (..Body("MSG-D", "A03", "WARD-B", "", "", "SYNTH^REN" _ $CHAR(232))), "control_id": "MSG-D", "ens_header_id": "H-D"})
    Do ..AssertCode(..Decide(..Case(), moves, facts, "E6"), "cancel_non_ascii", "a discharge's PID")
    // Above ASCII only outside what a cancel copies: the cancel is exact, and the replay of that message is withheld.
    Set moves = ..One(), facts = ..Facts(moves), key = ..Key("transfer", "2026-10-19T09:30:00Z")
    Do facts.bodies.%Set(key, {"text": (..Body("MSG-C", "A02", "WARD-C", "WARD-B^BAY2^04^HOSP", "NTE|1||CAF" _ $CHAR(233) _ $CHAR(13))), "control_id": "MSG-C", "ens_header_id": "H-C"})
    Set seq = ..Decide(..Case(), moves, facts)
    Do $$$AssertTrue(seq.drawn, "a note above ASCII doesn't stop it: " _ seq.reason)
    Do $$$AssertNotTrue(seq.steps.%Get(0)."non_ascii", "the cancel isn't flagged")
    Do $$$AssertTrue(seq.steps.%Get(2)."non_ascii", "the replay is")
}

/// With the placeholders filled, an A12 parses and validates as HL7 2.5.1 in stock IRIS, and so does an A13.
Method TestCancelsParse()
{
    For pair = $LISTBUILD("A12", "ADT_A12"), $LISTBUILD("A13", "ADT_A01") {
        Set trigger = $LIST(pair, 1)
        Set text = ##class(Shutter.Util.HistoryDraft).CancelText(trigger, ..Body("MSG-C", "A02", "WARD-C", "WARD-B^BAY2^04^HOSP"))
        Set filled = ..Fill(text)
        Set msg = ##class(EnsLib.HL7.Message).ImportFromString(filled, .sc)
        Do $$$AssertStatusOK(sc, trigger _ " imports")
        Set sc = msg.PokeDocType("2.5.1:" _ $LIST(pair, 2))
        Do $$$AssertStatusOK(sc, trigger _ " takes its structure")
        Set sc = msg.Validate("dm")
        Do $$$AssertStatusOK(sc, trigger _ " validates: " _ $SYSTEM.Status.GetErrorText(sc))
    }
}

ClassMethod Fill(text As %String) As %String
{
    Set out = text
    For pair = $LISTBUILD("[SENDER: time sent]", "20261019120000"), $LISTBUILD("[SENDER: new control id]", "MSG-NEW"), $LISTBUILD("[SENDER: time recorded]", "20261019120000"), $LISTBUILD("[SITE: event time for a cancel]", "20261019120000") {
        Set out = $REPLACE(out, $LIST(pair, 1), $LIST(pair, 2))
    }
    Quit out
}

/// The A12 by the table: the location before the move in PV1-3, the cancelled destination in PV1-6, PID copied, every
/// value a person must supply a placeholder.
Method TestCancelFields()
{
    Set source = ..Body("MSG-C", "A02", "WARD-C", "WARD-B^BAY2^04^HOSP")
    Set a12 = ##class(Shutter.Util.HistoryDraft).CancelText("A12", source), d = "Shutter.Util.HistoryDraft"
    Do $$$AssertEquals($CLASSMETHOD(d, "Field", a12, "PV1", 3), "WARD-B^BAY2^04^HOSP", "PV1-3 is the location before the move")
    Do $$$AssertEquals($PIECE($CLASSMETHOD(d, "Field", a12, "PV1", 6), "^", 1), "WARD-C", "PV1-6 is the cancelled destination")
    Do $$$AssertEquals($CLASSMETHOD(d, "Field", a12, "PV1", 19), "ENC-UT1", "PV1-19 copied")
    Do $$$AssertEquals($CLASSMETHOD(d, "Field", a12, "PV1", 44), "20261019080000", "PV1-44 copied")
    Do $$$AssertEquals($CLASSMETHOD(d, "Field", a12, "MSH", 3), "PAS", "MSH-3 copied")
    Do $$$AssertEquals($CLASSMETHOD(d, "Field", a12, "MSH", 7), "[SENDER: time sent]", "MSH-7 is a placeholder")
    Do $$$AssertEquals($CLASSMETHOD(d, "Field", a12, "MSH", 9), "ADT^A12^ADT_A12", "MSH-9")
    Do $$$AssertEquals($CLASSMETHOD(d, "Field", a12, "MSH", 10), "[SENDER: new control id]", "MSH-10 is a placeholder")
    Do $$$AssertEquals($CLASSMETHOD(d, "Field", a12, "EVN", 6), "[SITE: event time for a cancel]", "EVN-6 is a placeholder")
    Do $$$AssertTrue(a12 [ "PID|1||MRN-UT1^^^HOSP^MR||SYNTH^TEST||19700202|F", "PID copied whole")
}

Method TestReplayIsTheStoredText()
{
    Set moves = ..One(), facts = ..Facts(moves)
    Set draft = ##class(Shutter.Util.HistoryDraft).Draft(..Case(), ..Summary(moves), "E1", facts)
    Set stored = facts.bodies.%Get(..Case().OperationKey).text, row = draft.messages.%Get(1)
    Do $$$AssertEquals(row.text, stored, "the replay is the stored text, byte for byte")
    Do $$$AssertEquals(row."body_digest", ##class(Shutter.Util.Digest).SHA256Hex(stored), "its digest is of that text")
    Do $$$AssertTrue(row.label [ "Replay, unchanged", "and it says so")
    Do $$$AssertTrue(row.label [ "20261019100000", "with the source's own time")
    Do $$$AssertEquals(draft.header.%Size(), 9, "nine header lines")
    Do $$$AssertEquals(draft."cannot_know".%Size(), 11, "eleven things it can't know")
    Do $$$AssertTrue(draft.digest [ "sha256:", "a digest of what was read")
    Do $$$AssertTrue(draft.messages.%Get(0).label [ "Shutter's table", "a cancel says it is not a source message")
}

/// The structure holds no message text, for the plan goes to a model.
Method TestThePlanHoldsNoText()
{
    Set moves = ..One(), seq = ..Decide(..Case(), moves)
    Set steps = ##class(Shutter.Util.HistoryCorrection).Steps(..Case(), ..Summary(moves), "E1")
    For json = seq.%ToJSON(), steps.%ToJSON() {
        Do $$$AssertNotTrue(json [ "MSH|", "no MSH")
        Do $$$AssertNotTrue(json [ "PID|", "no PID")
        Do $$$AssertNotTrue(json [ "PV1|", "no PV1")
        Do $$$AssertNotTrue(json [ "SYNTH", "no name")
        Do $$$AssertNotTrue(json [ "19700202", "no date of birth")
    }
    Do $$$AssertTrue(seq.%IsDefined("drawn") && seq.%IsDefined("k") && seq.%IsDefined("count"), "the structure is there")
    Do $$$AssertEquals(steps.steps.%Size(), 8, "eight steps beside it")
    Do $$$AssertTrue(steps.steps.%Get(4) [ "own records procedure", "the receiver's own procedure first")
    Do $$$AssertNotTrue(steps.steps.%Get(4) [ "IHE", "no IHE update is offered")
}

Method TestEmailLine()
{
    Set line = ##class(Shutter.Util.HistoryDraft).EmailLine({"sequence": (..Decide(..Case(), ..One()))})
    Do $$$AssertTrue(line [ "sequence of 3 messages", "drawn: " _ line)
    Do $$$AssertTrue(line [ "this email carries none of it", "and carries none of it")
    Set facts = ..Facts(..One())
    Do facts.%Set("cancels", 0, "boolean")
    Set line = ##class(Shutter.Util.HistoryDraft).EmailLine({"sequence": (..Decide(..Case(), ..One(), facts))})
    Do $$$AssertTrue($EXTRACT(line, 1, 34) = "No message sequence was drafted: t", "not drawn: " _ line)
    Do $$$AssertNotTrue(line [ "No sequence:", "with no doubled opening")
    Do $$$AssertEquals(##class(Shutter.Util.HistoryDraft).EmailLine({}), "", "a plan from before the sequence adds nothing")
    Set facts = ..Facts(..One())
    Do facts.%Set("caught_up", 0, "boolean")
    Set line = ##class(Shutter.Util.HistoryDraft).EmailLine({"sequence": (..Decide(..Case(), ..One(), facts))})
    Do $$$AssertTrue($EXTRACT(line, 1, 42) = "No message sequence has been drafted yet: ", "not yet: " _ line)
    Do $$$AssertTrue(line [ "checks again on every read", "says a read checks again")
    Do $$$AssertTrue(line [ "this email carries none of it", "and carries none of it")
    Do $$$AssertNotTrue(line [ "was drafted", "and doesn't say no")
    Set c = ..Case(), c.SourceNamespace = "UTOTHERNS"
    Set line = ##class(Shutter.Util.HistoryDraft).EmailLine({"sequence": (..Decide(c, ..One()))})
    Do $$$AssertTrue($EXTRACT(line, 1, 33) = "No message sequence was drafted: ", "a forwarded case says no: " _ line)
}

/// What the draft says it can't see: a message under an identifier the failed message doesn't hold.
Method TestCannotKnowAnotherIdentifier()
{
    Set moves = ..One(), out = ##class(Shutter.Util.HistoryDraft).Draft(..Case(), ..Summary(moves), "E1", ..Facts(moves))
    Do $$$AssertTrue(out.drawn, "drawn: " _ out.reason)
    Do $$$AssertEquals(out."cannot_know".%Size(), 11, "every line")
    Set found = "", ci = out."cannot_know".%GetIterator()
    While ci.%GetNext(, .row) { Set:(row.what = "A message under another identifier") found = row }
    Do $$$AssertTrue($ISOBJECT(found), "the line is there")
    Do $$$AssertTrue($ISOBJECT(found) && (found.why [ "doesn't hold can't be matched"), "says it can't be matched")
    Do $$$AssertTrue($ISOBJECT(found) && (found.why [ "a different patient must not match"), "and why there is no match on a name")
}

/// Every identifier in a PID-3, each with its authority, whatever the repetition's type; none empty.
Method TestIdentifiers()
{
    Set draft = "Shutter.Util.HistoryDraft"
    Set one = $CLASSMETHOD(draft, "Identifiers", ..WithPid("MRN-1^^^HOSP^MR"))
    Do $$$AssertEquals(one.%Size(), 1, "one repetition")
    Do $$$AssertEquals(one.%Get(0).id, "MRN-1", "its number")
    Do $$$AssertEquals(one.%Get(0).authority, "HOSP", "its authority")
    Set two = $CLASSMETHOD(draft, "Identifiers", ..WithPid("MRN-1^^^HOSP^MR~999^^^NHS&2.16&ISO^NH~^^^EMPTY^XX~888^^^^PI"))
    Do $$$AssertEquals(two.%Size(), 3, "an empty repetition isn't one")
    Do $$$AssertEquals(two.%Get(1).id, "999", "the second number")
    Do $$$AssertEquals(two.%Get(1).authority, "NHS", "the authority's first part, as the operation key reads it")
    Do $$$AssertEquals(two.%Get(2).authority, "", "no authority stays empty")
    Do $$$AssertEquals($CLASSMETHOD(draft, "Identifiers", "").%Size(), 0, "no message, no identifiers")
    Set other = $CLASSMETHOD(draft, "Identifiers", "MSH#*!\&#PAS"_$CHAR(13)_"PID#1##MRN-1***HOSP*MR!999***NHS*NH"_$CHAR(13))
    Do $$$AssertEquals(other.%Size(), 2, "the message's own separators")
    Do $$$AssertEquals(other.%Get(1).id, "999", "the second number by them")
}

/// A body with the given PID-3.
ClassMethod WithPid(pid3 As %String) As %String
{
    Quit $REPLACE(..Body("MSG-UT-P", "A02", "WARD-B", "WARD-A"), "MRN-UT1^^^HOSP^MR", pid3)
}

// ---- the store ----

/// Reading a drawn draft leaves one event naming who, how many and the digest, and no message text; a new message for the
/// patient turns the same draft to not drawn, with no event.
Method TestReadRecordsTheRead()
{
    Do ..Clean()
    Set c = ..Case()
    Set sc = c.%Save()
    Do $$$AssertStatusOK(sc, "the case saves")
    Set moves = ..One(), facts = ..Facts(moves)
    Set out = ##class(Shutter.Util.HistoryDraft).Read(c, "ut-approver", ..Summary(moves), "E1", facts)
    Do $$$AssertTrue(out.drawn, "drawn: " _ out.reason)
    Set text = ..Events(c)
    Do $$$AssertEquals($LENGTH(text, "Correction draft read by") - 1, 1, "one event: " _ text)
    Do $$$AssertTrue(text [ "ut-approver", "naming the user")
    Do $$$AssertTrue(text [ "3 messages", "the count")
    Do $$$AssertTrue(text [ out.digest, "and the digest")
    Do $$$AssertNotTrue(text [ "MSH|", "and no message text")
    Do $$$AssertNotTrue(text [ "SYNTH", "and no name")
    Do facts."patient_rows".%Push(..Row("ENC-UT2", "admit", "2026-10-19T09:40:00Z", "2026-10-19 09:40:01"))
    Set out = ##class(Shutter.Util.HistoryDraft).Read(c, "ut-approver", ..Summary(moves), "E1", facts)
    Do $$$AssertNotTrue(out.drawn, "the redraw stops")
    Do $$$AssertEquals(out."reason_code", "further_message", "and says why")
    Do $$$AssertEquals(out.messages.%Size(), 0, "with no text")
    Do $$$AssertEquals($LENGTH(..Events(c), "Correction draft read by") - 1, 1, "and no new event")
    Do ..Clean()
}

ClassMethod Events(c As Shutter.Store.Case) As %String
{
    Set text = "", id = c.%Id()
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? ORDER BY ID", id)
    While rs.%Next() { Set text = text _ rs.%Get("Text") _ $CHAR(10) }
    Quit text
}

ClassMethod Clean()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", ..#CASEID)
    While rs.%Next() {
        Set id = rs.%Get("ID")
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
        Kill ^Shutter.Counter("event", id)
        Do ##class(Shutter.Store.Case).%DeleteId(id)
    }
}

/// The patient-level query respects the authority, and Gather reads a stored message's text through the index.
Method TestForPatientAndGather()
{
    // Rows a run that stopped half-way may have left.
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Index.Message WHERE PatientId = ?", "MRN-UT-FORPATIENT")
    Set patient = "MRN-UT-FORPATIENT", msg = ##class(EnsLib.HL7.Message).ImportFromString(..Body("MSG-UT-G", "A02", "WARD-B", "WARD-A"), .sc)
    Do $$$AssertStatusOK(sc, "a message imports")
    Set sc = msg.%Save()
    Do $$$AssertStatusOK(sc, "and saves")
    Set c = ..Case(), c.PatientId = patient, c.OperationKey = "UT-GATHER-KEY"
    Set ids = ""
    Set docId = msg.%Id()
    For row = $LISTBUILD(docId, "HOSP", "ENC-UT1", "UT-GATHER-KEY"), $LISTBUILD(docId + 1000000, "", "ENC-UT2", "UT-GATHER-NOAUTH"), $LISTBUILD(docId + 1000001, "OTHER", "ENC-UT3", "UT-GATHER-OTHER") {
        Set r = ##class(Shutter.Index.Message).%New()
        Set r.DocId = $LIST(row, 1), r.PatientId = patient, r.PatientIdAuthority = $LIST(row, 2), r.VisitNumber = $LIST(row, 3), r.OperationKey = $LIST(row, 4), r.ControlId = "MSG-UT-G", r.Event = "transfer", r.EventTime = "2026-10-19T09:00:00Z", r.TimeCreated = $TRANSLATE($PIECE(##class(Shutter.Util.Time).NowUTC(), "Z", 1), "T", " ")
        Set sc = r.%Save()
        Do $$$AssertStatusOK(sc, "an index row saves")
        Set ids = ids _ $LISTBUILD(r.%Id())
    }
    Set rows = ##class(Shutter.Index.Message).ForPatient(patient, "HOSP")
    Do $$$AssertEquals(rows.%Size(), 2, "its own authority and a row with none, not another authority's")
    Do $$$AssertEquals(##class(Shutter.Index.Message).ForPatient("", "HOSP").%Size(), 0, "an empty identifier has no rows")
    Set facts = ##class(Shutter.Util.HistoryDraft).Gather(c)
    Set body = facts.bodies.%Get("UT-GATHER-KEY")
    Do $$$AssertTrue($ISOBJECT(body), "the case's message is gathered")
    Do $$$AssertTrue($ISOBJECT(body) && (body.text [ "MSG-UT-G"), "with its stored text")
    Do $$$AssertEquals(##class(Shutter.Util.HistoryDraft).StoredText(docId + 1000000), "", "a message that is gone reads empty")
    For i = 1:1:$LISTLENGTH(ids) { Do ##class(Shutter.Index.Message).%DeleteId($LIST(ids, i)) }
    Do ##class(EnsLib.HL7.Message).%DeleteId(docId)
}

/// The failed message holds a hospital number and an NHS number, so a message under either is this patient's. Another
/// number, or the same number under another authority, is not. A merge naming either as its prior side touches this patient.
Method TestGatherAsksEveryIdentifier()
{
    Do ..Clean()
    Set mrn = "MRN-UT-EVERY", nhs = "NHS-UT-EVERY", other = "NHS-UT-OTHER"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Index.Message WHERE PatientId IN (?, ?, ?)", mrn, nhs, other)
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(..WithPid(mrn _ "^^^HOSP^MR~" _ nhs _ "^^^NHS^NH"), .sc)
    Do $$$AssertStatusOK(sc, "a message imports")
    Set sc = msg.%Save()
    Do $$$AssertStatusOK(sc, "and saves")
    Set docId = msg.%Id(), moves = ..One(), c = ..Case()
    Set c.PatientId = mrn, c.OperationKey = "UT-EVERY-FAILED"
    Set ids = "", now = $TRANSLATE($PIECE(##class(Shutter.Util.Time).NowUTC(), "Z", 1), "T", " ")
    Set rows = $LISTBUILD($LISTBUILD(docId, mrn, "HOSP", "ENC-UT1", "UT-EVERY-FAILED", "transfer"), $LISTBUILD(docId + 2000001, nhs, "NHS", "ENC-UT9", "UT-EVERY-NHS", "admit"), $LISTBUILD(docId + 2000002, other, "NHS", "ENC-UT8", "UT-EVERY-OTHER", "admit"), $LISTBUILD(docId + 2000003, nhs, "ELSEWHERE", "ENC-UT7", "UT-EVERY-ELSEWHERE", "admit"))
    For i = 1:1:$LISTLENGTH(rows) {
        Set row = $LIST(rows, i), r = ##class(Shutter.Index.Message).%New()
        Set r.DocId = $LIST(row, 1), r.PatientId = $LIST(row, 2), r.PatientIdAuthority = $LIST(row, 3), r.VisitNumber = $LIST(row, 4), r.OperationKey = $LIST(row, 5), r.Event = $LIST(row, 6), r.ControlId = "CTL-" _ i, r.EventTime = "2026-10-19T09:40:00Z", r.TimeCreated = now
        Set sc = r.%Save()
        Do $$$AssertStatusOK(sc, "an index row saves")
        Set ids = ids _ $LISTBUILD(r.%Id())
    }
    Set facts = ##class(Shutter.Util.HistoryDraft).Gather(c), seen = "", ri = facts."patient_rows".%GetIterator()
    While ri.%GetNext(, .row) { Set seen = seen _ row."operation_key" _ " " }
    Do $$$AssertTrue(seen [ "UT-EVERY-FAILED", "its own number: " _ seen)
    Do $$$AssertTrue(seen [ "UT-EVERY-NHS", "the NHS number the failed message holds")
    Do $$$AssertNotTrue(seen [ "UT-EVERY-OTHER", "not another number")
    Do $$$AssertNotTrue(seen [ "UT-EVERY-ELSEWHERE", "and not that number under another authority")
    Do $$$AssertNotTrue(facts."merge_case", "no merge yet")
    // The decision on those rows: the NHS row is a further message.
    Set given = ..Facts(moves), given."patient_rows" = facts."patient_rows"
    Set seq = ##class(Shutter.Util.HistoryDraft).Decide(c, ..Summary(moves), "E1", given, 1)
    Do ..AssertCode(seq, "further_message", "the message under the NHS number stops it")
    Do $$$AssertTrue(seq.reason [ "ENC-UT9", "and is named: " _ seq.reason)
    Set merge = ..Case(), merge.PatientId = "MRN-UT-SURVIVOR", merge.PriorPatientId = nhs
    Set sc = merge.%Save()
    Do $$$AssertStatusOK(sc, "a merge case saves")
    Do $$$AssertTrue(##class(Shutter.Util.HistoryDraft).Gather(c)."merge_case", "a merge naming the NHS number touches this patient")
    Do ..Clean()
    Set rowsBack = ##class(Shutter.Index.Message).ForPatient(nhs, "")
    Do $$$AssertEquals(rowsBack.%Size(), 2, "a repetition with no authority can't be told apart, so it asks for every authority")
    For i = 1:1:$LISTLENGTH(ids) { Do ##class(Shutter.Index.Message).%DeleteId($LIST(ids, i)) }
    Do ##class(EnsLib.HL7.Message).%DeleteId(docId)
}

}
