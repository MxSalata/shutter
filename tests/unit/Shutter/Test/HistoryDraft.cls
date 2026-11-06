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
    Set timeline = [], li = moves.%GetIterator()
    While li.%GetNext(, .m) {
        Set key = ..Key(m.%Get(0), m.%Get(2))
        Do history.%Push({"event": (m.%Get(0)), "ward": (m.%Get(1)), "event_time": (m.%Get(2)), "operation_key": (key), "applied_at": (m.%Get(2))})
        Set row = {"event": (m.%Get(0)), "ward": (m.%Get(1)), "event_time": (m.%Get(2)), "operation_key": (key), "source": "feed", "outcome": "applied", "sent_at": (m.%Get(2)), "source_message_id": ("MSG-" _ m.%Get(1)), "ens_header_id": ("H-" _ m.%Get(1))}
        Do row.%Set("later", 1, "boolean")
        Do timeline.%Push(row)
    }
    Quit {"observed_at": "2026-10-19T12:00:00Z", "receipt_http_status": 404, "ward_state": {"state": "admitted", "ward": "WARD-C", "version": 3, "history": (history)}, "timeline": (timeline)}
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

/// A site's case: a new admission on a new visit number for the same patient.
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

Method TestFeedNotIndexed()
{
    Set c = ..Case(), c.SourceNamespace = "UTOTHERNS"
    Do ..AssertCode(..Decide(c, ..One()), "feed_not_indexed", "a forwarded case")
    Set facts = ..Facts(..One())
    Do facts.%Set("caught_up", 0, "boolean")
    Do ..AssertCode(..Decide(..Case(), ..One(), facts), "feed_not_indexed", "an index behind")
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
    Do $$$AssertEquals(draft."cannot_know".%Size(), 10, "ten things it can't know")
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
    Set patient = "MRN-UT-FORPATIENT", msg = ##class(EnsLib.HL7.Message).ImportFromString(..Body("MSG-UT-G", "A02", "WARD-B", "WARD-A"), .sc)
    Do $$$AssertStatusOK(sc, "a message imports")
    Set sc = msg.%Save()
    Do $$$AssertStatusOK(sc, "and saves")
    Set c = ..Case(), c.PatientId = patient, c.OperationKey = "UT-GATHER-KEY"
    Set ids = ""
    Set docId = msg.%Id()
    For row = $LISTBUILD(docId, "HOSP", "ENC-UT1", "UT-GATHER-KEY"), $LISTBUILD(docId + 1000000, "", "ENC-UT2", "UT-GATHER-NOAUTH"), $LISTBUILD(docId + 1000001, "OTHER", "ENC-UT3", "UT-GATHER-OTHER") {
        Set r = ##class(Shutter.Index.Message).%New()
        Set r.DocId = $LIST(row, 1), r.PatientId = patient, r.PatientIdAuthority = $LIST(row, 2), r.VisitNumber = $LIST(row, 3), r.OperationKey = $LIST(row, 4), r.ControlId = "MSG-UT-G", r.Event = "transfer", r.EventTime = "2026-10-19T09:00:00Z", r.TimeCreated = "2026-11-06 00:00:00"
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
    Do $$$AssertTrue(body.text [ "MSG-UT-G", "with its stored text")
    Do $$$AssertEquals(##class(Shutter.Util.HistoryDraft).StoredText(docId + 1000000), "", "a message that is gone reads empty")
    For i = 1:1:$LISTLENGTH(ids) { Do ##class(Shutter.Index.Message).%DeleteId($LIST(ids, i)) }
    Do ##class(EnsLib.HL7.Message).%DeleteId(docId)
}

}
