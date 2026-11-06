/// What may close a case, and what may be believed from a receiver: an answer that shows no receipt is not a delivery, a
/// read that is not the receiver's own answer is no reading, a receipt holding other content closes nothing, a bed or a
/// cancel since the first delivery goes to a person, a write nobody released never resolves, and a case nobody acted on
/// is never purged. Rows of the verifier's and the gate's own tables are in Shutter.Test.Verify and Shutter.Test.Gate.
Class Shutter.Test.Closure Extends %UnitTest.TestCase
{

Parameter KEY = "PAS^HOSP^MRN-CL1^ENC-CL1^transfer^2026-10-19T09:00:00Z";

Parameter THECASE = "C-TEST-CLOSE";

Parameter ENCOUNTER = "{""encounter_id"":""ENC-CL1"",""patient_id"":""MRN-CL1"",""patient_id_authority"":""HOSP"",""state"":""admitted"",""ward"":""WARD-A"",""version"":1,""history"":[]}";

Method OnAfterOneTest(testname As %String) As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId %STARTSWITH ? OR OperationKey = ?", ..#THECASE, ..#KEY)
    While rs.%Next() { Do ##class(Shutter.Store.Case).PurgeCase(rs.%Get("ID")) }
    &sql(DELETE FROM Shutter_Index.Message WHERE VisitNumber = 'ENC-CL1')
    Quit $$$OK
}

/// A saved case of the transfer, conditional on version 1.
Method SavedCase(caseId As %String = {..#THECASE}, state As %String = "verifying") As Shutter.Store.Case
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = caseId, c.OperationKey = $SELECT(caseId = ..#THECASE: ..#KEY, 1: caseId _ "^transfer")
    Set c.Event = "transfer", c.EncounterId = "ENC-CL1", c.PatientId = "MRN-CL1", c.PatientIdAuthority = "HOSP", c.SourceSystem = "PAS"
    Set c.FailureKind = "delivery_failed", c.Ward = "WARD-B", c.EventTime = "2026-10-19T09:00:00Z", c.State = state, c.Mode = "policy", c.Receiver = $PARAMETER("Shutter.Production", "RECEIVER")
    Do $$$AssertStatusOK(c.%Save(), "the case")
    Quit c
}

/// The case's plan: a resend of its own operation.
Method ResendPlan(c As Shutter.Store.Case) As Shutter.Store.Plan
{
    Set p = ##class(Shutter.Store.Plan).%New()
    Do p.CaseSetObjectId(c.%Id())
    Set p.Version = $INCREMENT(^Shutter.Counter("plan", c.%Id())), p.Disposition = "resend", p.ActionType = "resend", p.OperationKey = c.OperationKey, p.ExpectedVersion = 1
    Do $$$AssertStatusOK(p.%Save(), "the plan")
    Quit p
}

/// The answer as the connector classifies it.
ClassMethod Classified(class As %String, status As %Integer, body As %DynamicObject) As %String
{
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.HttpStatus = status
    Do $CLASSMETHOD(class, "Classify", r, $$$OK, body)
    Quit r.Outcome
}

/// A receiver's entry in the site profile may ask for its answers to be read on status alone, as before this check; the
/// default is to check them.
Method TestStrictAnswersIsTheSitesChoice()
{
    Set sp = "Shutter.Store.SiteProfile"
    Do $$$AssertTrue($CLASSMETHOD(sp, "StrictAnswers", "UT Not In The Profile"), "the default is to check a receiver's answers")
    Do $$$AssertTrue($CLASSMETHOD(sp, "StrictAnswers", $PARAMETER("Shutter.Production", "RECEIVER")), "the shipped receiver is checked")
    Set p = $CLASSMETHOD(sp, "Default")
    Do p.receivers.%Get(0).%Set("strict_answers", "yes")
    Do $$$AssertTrue($CLASSMETHOD(sp, "Validate", p) [ "strict_answers", "anything but true or false is refused")
    Do p.receivers.%Get(0).%Set("strict_answers", 0, "boolean")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Validate", p), "", "false is taken")
}

/// A receiver that stamps arrival time. The key carries the time the message was sent with, so a resent older
/// transfer stored at 09:40 does not read as later than a 09:30 transfer, and E1 cannot close that one on its account.
Method TestAStoredArrivalTimeDoesNotOvertake()
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "UT", c.Event = "transfer", c.EventTime = "2026-10-19T09:30:00Z", c.OperationKey = "PAS^HOSP^MRN^ENC^transfer^2026-10-19T09:30:00Z"
    Set resent = {"event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:40:00Z", "applied_at": "2026-10-19T09:40:00Z", "operation_key": "PAS^HOSP^MRN^ENC^transfer^2026-10-19T08:00:00Z"}
    Set summary = {"observed_at": "2026-10-19T10:00:00Z", "timeline": [], "ward_state": {"history": [(resent)]}}
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Later(summary, c, "single").%Size(), 0, "an 08:00 transfer stored at 09:40 is not later than 09:30")
    Set real = {"event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T09:45:00Z", "applied_at": "2026-10-19T09:45:02Z", "operation_key": "PAS^HOSP^MRN^ENC^transfer^2026-10-19T09:45:00Z"}
    Set summary = {"observed_at": "2026-10-19T10:00:00Z", "timeline": [], "ward_state": {"history": [(real)]}}
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Later(summary, c, "single").%Size(), 1, "a later event whose key says so stays later")
    Set manual = {"event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T09:45:00Z", "applied_at": "2026-10-19T09:45:02Z", "operation_key": "manual-7"}
    Set summary = {"observed_at": "2026-10-19T10:00:00Z", "timeline": [], "ward_state": {"history": [(manual)]}}
    Do $$$AssertEquals(##class(Shutter.Catalogue.Matcher).Later(summary, c, "single").%Size(), 1, "a key with no time leaves the stored time")
    Do $$$AssertEquals(##class(Shutter.Operation.Verify).LaterThan({"history": [(resent)]}, "2026-10-19T09:00:00Z"), "", "and the verifier does not call it a later event")
}

/// What the feed makes of an already_committed answer. A corrected bed under a committed key has the same digest; a re-issue
/// after a cancel has the same key and digest. Both are in the receiver's words delivered and
/// neither is in effect, so each goes to a person.
Method TestAlreadyCommittedThatIsNotThisMessage()
{
    Set feed = "Shutter.Process.ADTToWard"
    Set op = {"operation_key": (..#KEY), "encounter_id": "ENC-CL1", "patient_id": "MRN-CL1", "patient_id_authority": "HOSP", "event": "transfer", "ward": "WARD-B", "bed": "B2", "event_time": "2026-10-19T09:00:00Z", "payload_digest": "sha256:ours"}
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.Outcome = "already_committed", r.ReceiptJSON = {"operation_key": (..#KEY), "ward": "WARD-B", "bed": "B1", "payload_digest": "sha256:ours"}.%ToJSON()
    Set why = $CLASSMETHOD(feed, "CommittedNotThis", op, r)
    Do $$$AssertTrue(why [ "bed B1", "the receiver keeps another bed: " _ why)
    Do $$$AssertEquals($CLASSMETHOD(feed, "CommittedNotThis", op, r, 0), "", "a site that reads this receiver on status alone keeps what it had")
    Set r.ReceiptJSON = {"operation_key": (..#KEY), "ward": "WARD-B", "bed": "B2", "payload_digest": "sha256:ours"}.%ToJSON()
    Do $$$AssertEquals($CLASSMETHOD(feed, "CommittedNotThis", op, r), "", "a plain duplicate is a delivery, as before")
    Set m = ##class(Shutter.Index.Message).%New()
    Set m.DocId = "UT-CLOSURE", m.VisitNumber = "ENC-CL1", m.PatientId = "MRN-CL1", m.PatientIdAuthority = "HOSP", m.Event = "cancel_transfer", m.EventTime = "2026-10-19T09:05:00Z", m.MessageType = "ADT^A12", m.TimeCreated = "2026-10-19 09:05:01"
    Do $$$AssertStatusOK(m.%Save(), "a cancel in the index")
    Set why = $CLASSMETHOD(feed, "CommittedNotThis", op, r)
    Do $$$AssertTrue(why [ "cancel", "a re-issue after a cancel: " _ why)
    Do $$$AssertTrue($CLASSMETHOD(feed, "CommittedNotThis", op, r, 0) [ "cancel", "the cancel is the feed's own record, whatever the site reads of the receiver")
    Set m.EventTime = "2026-10-19T08:00:00Z"
    Do $$$AssertStatusOK(m.%Save(), "a cancel before this message")
    Do $$$AssertEquals($CLASSMETHOD(feed, "CommittedNotThis", op, r), "", "a cancel before this event is not one since")
    Set m.EventTime = "2026-10-19T09:05:00Z", m.PatientId = "MRN-OTHER"
    Do $$$AssertStatusOK(m.%Save(), "another patient's cancel on that visit number")
    Do $$$AssertEquals($CLASSMETHOD(feed, "CommittedNotThis", op, r), "", "another patient's cancel is not this one's")
}

/// Both messages failed. Equal digests only added a note, so the recovery would have written the bed the correction
/// replaced.
Method TestACorrectedBedOnAnOpenCaseStopsIt()
{
    Set op = {"operation_key": (..#KEY), "encounter_id": "ENC-CL1", "patient_id": "MRN-CL1", "patient_id_authority": "HOSP", "source_system": "PAS", "event": "transfer", "ward": "WARD-B", "bed": "B1", "event_time": "2026-10-19T09:00:00Z"}
    Set op."payload_digest" = ##class(Shutter.Util.Digest).WardPayloadDigest(op)
    Set receiver = $PARAMETER("Shutter.Production", "RECEIVER")
    Do $$$AssertStatusOK(##class(Shutter.Store.Case).Open(op, "delivery_failed", "first", "", "1", "policy", .c, .opened, receiver), "the first failure")
    Do $$$AssertTrue(opened, "opens a case")
    Do $$$AssertStatusOK(##class(Shutter.Store.Case).Open(op, "delivery_failed", "again", "", "2", "policy", .c, .opened, receiver), "the same message again")
    Do $$$AssertNotTrue(opened, "joins it")
    Do $$$AssertNotEquals(c.State, "blocked", "and is only noted")
    Set op.bed = "B2"
    Do $$$AssertStatusOK(##class(Shutter.Store.Case).Open(op, "delivery_failed", "corrected", "", "3", "policy", .c, .opened, receiver), "the corrected bed")
    Do $$$AssertEquals(c.State, "blocked", "stops the case: its plan would write the first bed")
    Do $$$AssertTrue(c.Headline [ "different content", "and says why: " _ c.Headline)
}

}
