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

/// A 200 saying already committed, with no receipt in its body, on a first delivery, opened no case. A 200 is a
/// delivery only with the receipt the contract promises (or applied true); a gateway's page is the same case.
Method TestATwoHundredWithNoReceiptIsNoDelivery()
{
    For class = "Shutter.Operation.Ward", "Hospital.Operation.DownstreamOut" {
        Do $$$AssertEquals(..Classified(class, 200, {"applied": false, "reason": "already_committed"}), "uncertain", class _ ": already committed, with no receipt")
        Do $$$AssertEquals(..Classified(class, 200, {}), "uncertain", class _ ": a 200 with nothing the contract says, a gateway's page")
        Do $$$AssertEquals(..Classified(class, 200, {"applied": false}), "uncertain", class _ ": not applied, with no receipt")
        Do $$$AssertEquals(..Classified(class, 200, {"applied": false, "reason": "already_committed", "receipt": {"operation_key": (..#KEY)}}), "already_committed", class _ ": with the earlier receipt, as the contract says")
        Do $$$AssertEquals(..Classified(class, 200, {"applied": true}), "applied", class _ ": applied, in its own words")
        Do $$$AssertEquals(..Classified(class, 200, {"rehearsal": true, "would_apply": true}), "would_apply", class _ ": a rehearsal is not touched")
    }
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.HttpStatus = 200
    Do ##class(Shutter.Operation.Ward).Classify(r, $$$OK, {"applied": false, "reason": "already_committed"}, 0)
    Do $$$AssertEquals(r.Outcome, "already_committed", "a site that reads this receiver on status alone keeps what it had")
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.HttpStatus = 200
    Do ##class(Shutter.Operation.Ward).Classify(r, $$$OK, {})
    Do $$$AssertTrue(r.Error [ "no receipt", "a person reads why: " _ r.Error)
}

/// The preflight read has always refused a 404 that is not the contract's; a 200 that is not an encounter too.
Method TestAPreflightReadNeedsAVersion()
{
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.HttpStatus = 200
    Do ##class(Shutter.Operation.Ward).ClassifyRead(r, $$$OK, {}, "/x")
    Do $$$AssertEquals(r.Outcome, "error", "a 200 with no version is not the receiver's encounter")
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.HttpStatus = 200
    Do ##class(Shutter.Operation.Ward).ClassifyRead(r, $$$OK, {"version": 3, "state": "admitted"}, "/x")
    Do $$$AssertEquals(r.Outcome, "read", "with a version it is")
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.HttpStatus = 200
    Do ##class(Shutter.Operation.Ward).ClassifyRead(r, $$$OK, {}, "/x", 0)
    Do $$$AssertEquals(r.Outcome, "read", "a site that reads this receiver on status alone keeps what it had")
}

/// The verifier on a case whose write's answer was lost, reading through the table: what it recorded of the two reads.
Method Verified(receipt As %List, encounter As %List = "", Output response As Shutter.Msg.VerifyResult) As %DynamicObject
{
    Set c = ..SavedCase()
    Set p = ..ResendPlan(c)
    Do $$$AssertStatusOK(##class(Shutter.Store.ExecutionAttempt).Create(c, p, "", "", 0, "uncertain", {}, "", .a), "the attempt")
    Set op = ##class(Shutter.Operation.Verify).%New("Shutter Verify (unit test)")
    Set http = ##class(Shutter.Test.FakeHttp).%New()
    Set http.Answers("/encounters/") = $SELECT(encounter = "": $LISTBUILD(200, ..#ENCOUNTER), 1: encounter)
    Set http.Answers("/receipts/") = receipt
    Set op.Adapter = http
    Set request = ##class(Shutter.Msg.VerifyRequest).%New()
    Set request.CaseId = c.CaseId, request.PlanId = p.%Id(), request.AttemptId = a.%Id()
    Do $$$AssertStatusOK(op.OnVerifyRequest(request, .response), "the verification ran")
    Set detail = ##class(%DynamicObject).%FromJSON(response.DetailJSON)
    Do ..OnAfterOneTest("")
    Quit detail
}

/// A 200 that is not this operation's receipt, and a 404 that is not the receiver's own, are not readings: the
/// verifier says nothing was established, and does not say the receiver holds, or does not hold, a receipt.
Method TestTheVerifierBelievesOnlyTheReceiversOwnAnswers()
{
    Set d = ..Verified($LISTBUILD(200, "<html>Sign in</html>"), , .r)
    Do $$$AssertEquals(d."receipt_http_status", 0, "a sign-in page is no receipt")
    Do $$$AssertEquals(r.Outcome, "unresolved", "nothing is established: " _ r.Summary)
    Do $$$AssertNotTrue(r.Summary [ "A receipt exists", "and nothing says a receipt exists")
    Set d = ..Verified($LISTBUILD(200, "{""operation_key"":""another key""}"), , .r)
    Do $$$AssertEquals(d."receipt_http_status", 0, "another operation's receipt is no receipt for this one")
    Set d = ..Verified($LISTBUILD(404, "<html>Not found</html>"), , .r)
    Do $$$AssertEquals(d."receipt_http_status", 0, "a gateway's 404 is not the receiver saying no receipt")
    Do $$$AssertEquals(r.Outcome, "unresolved", "so nothing is established")
    Do $$$AssertTrue(''d.retry, "and it is read again")
    Set d = ..Verified($LISTBUILD(404, "{""error"":""no_receipt""}"), , .r)
    Do $$$AssertEquals(d."receipt_http_status", 404, "the contract's own 404 is a reading")
    Set d = ..Verified($LISTBUILD(200, "{""operation_key"":""" _ ..#KEY _ """}"), , .r)
    Do $$$AssertEquals(d."receipt_http_status", 200, "this operation's receipt is a reading")
    Set d = ..Verified($LISTBUILD(404, "{""error"":""no_receipt""}"), $LISTBUILD(200, "<html>Sign in</html>"), .r)
    Do $$$AssertEquals(d."encounter_http_status", 0, "a sign-in page is no encounter")
    Set d = ..Verified($LISTBUILD(404, "{""error"":""no_receipt""}"), $LISTBUILD(404, "<html>Not found</html>"), .r)
    Do $$$AssertEquals(d."encounter_http_status", 0, "a gateway's 404 is not the receiver saying it does not know the encounter")
    Set d = ..Verified($LISTBUILD(404, "{""error"":""no_receipt""}"), $LISTBUILD(404, "{""error"":""unknown_encounter""}"), .r)
    Do $$$AssertEquals(d."encounter_http_status", 404, "the contract's own 404 is a reading")
}

/// At the proposal: the snapshot the gate and the matcher read carries the same judgement, so a sign-in page on the
/// receipt read is not E3's receipt present.
Method TestTheEvidenceBelievesOnlyTheReceiversOwnAnswers()
{
    Set c = ..SavedCase(, "collecting")
    Set op = ##class(Shutter.Operation.Evidence).%New("Shutter Evidence (unit test)")
    Set op.SecondParserTarget = ""
    Set http = ##class(Shutter.Test.FakeHttp).%New()
    Set http.Answers("/encounters/") = $LISTBUILD(404, "")
    Set http.Answers("/receipts/") = $LISTBUILD(200, "<html>Sign in</html>")
    Set op.Adapter = http
    Set request = ##class(Shutter.Msg.EvidenceRequest).%New()
    Set request.CaseId = c.CaseId
    Do $$$AssertStatusOK(op.OnEvidenceRequest(request, .response), "the evidence ran")
    Do $$$AssertEquals(response.Error, "", "with no error")
    Set summary = ##class(%DynamicObject).%FromJSON(response.SummaryJSON)
    Do $$$AssertEquals(summary."receipt_http_status", 0, "a sign-in page is no receipt")
    Do $$$AssertEquals(summary."ward_state_http_status", 0, "an empty 404 is not the receiver's answer for an encounter")
    Do $$$AssertTrue(##class(Shutter.Util.Json).Str(summary.%Get("receipt"), "error") [ "HTTP 200", "and the reading says what came back")
    Set conds = ##class(Shutter.Catalogue.Matcher).Conditions(c, summary)
    Do $$$AssertEquals(conds.receipt, "unreadable", "the matcher reads it as unreadable")
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

/// Blocked, escalated and failed start the retention clock the moment they reach a person. Only what is
/// finished goes: resolved, handled by hand or abandoned.
Method TestPurgeTakesOnlyWhatIsFinished()
{
    For state = "escalated", "blocked", "failed", "resolved" { Set ids(state) = ..OldCase(state) }
    Set ids("abandoned") = ..OldCase("failed", "abandoned")
    Set ids("handled") = ..OldCase("resolved", "handled_by_hand")
    Do ##class(Shutter.Store.Case).PurgeClosedBefore("1970-01-02T00:00:00Z")
    For state = "escalated", "blocked", "failed" { Do $$$AssertTrue(##class(Shutter.Store.Case).%ExistsId(ids(state)), "a case " _ state _ " nobody acted on stays") }
    For state = "resolved", "abandoned", "handled" { Do $$$AssertNotTrue(##class(Shutter.Store.Case).%ExistsId(ids(state)), "a case " _ state _ " goes") }
    // A closed incident that still holds a case nobody acted on stays with it.
    Set i = ##class(Shutter.Store.Incident).%New()
    Set i.IncidentId = ..#THECASE _ "-I", i.State = "closed", i.ClosedAt = "1970-01-01T00:00:00Z"
    Do $$$AssertStatusOK(i.%Save(), "a closed incident")
    Set id = ..OldCase("escalated", "", i)
    Set iid = i.%Id()
    Do ##class(Shutter.Store.Case).PurgeClosedBefore("1970-01-02T00:00:00Z")
    Do $$$AssertTrue(##class(Shutter.Store.Case).%ExistsId(id), "its escalated case stays")
    Do $$$AssertTrue(##class(Shutter.Store.Incident).%ExistsId(iid), "and so does the incident")
    Do ##class(Shutter.Store.Case).PurgeCase(id)
    Do ##class(Shutter.Store.Incident).%DeleteId(iid)
}

Method OldCase(state As %String, disposition As %String = "", incident As Shutter.Store.Incident = "") As %String
{
    Set c = ..SavedCase(..#THECASE _ $EXTRACT(state, 1, 3) _ $EXTRACT(disposition, 1, 3) _ $SELECT($ISOBJECT(incident): "I", 1: ""), state)
    Set c.ClosedAt = "1970-01-01T00:00:00Z", c.Disposition = disposition
    Do $$$AssertStatusOK(c.%Save(), "an old case " _ state)
    Set id = c.%Id()
    If $ISOBJECT(incident) Do $$$AssertStatusOK(c.SetIncident(incident), "in the incident")
    Quit id
}

/// No sign of a write by the last read proves nothing. It escalates as unknown, and the approval it spent stays spent.
Method TestNoSignOfAWriteIsUnknownAndTheApprovalIsSpent()
{
    Set c = ..SavedCase()
    Set p = ..ResendPlan(c)
    Set approval = ##class(Shutter.Store.Approval).%New()
    Do approval.CaseSetObjectId(c.%Id())
    Set approval.Plan = p
    Do $$$AssertStatusOK(approval.%Save(), "an approval")
    Do $$$AssertStatusOK(##class(Shutter.Store.ExecutionAttempt).Create(c, p, approval, "", 0, "uncertain", {}, "", .a), "the attempt")
    Set wf = ##class(Shutter.Test.QuietWorkflow).%New("Case Workflow")
    Set wf.CaseId = c.CaseId, wf.PlanId = p.%Id(), wf.ApprovalId = approval.%Id(), wf.AttemptId = a.%Id(), wf.Mode = "policy"
    Set ctx = ##class(Shutter.Test.Verify).Base()
    Set ctx.attempt.at = "2026-10-19T09:08:50Z", ctx."settle_seconds" = 60
    Set result = ##class(Shutter.Msg.VerifyResult).%New()
    Set result.Outcome = ##class(Shutter.Operation.Verify).Judge(ctx, .text, .detail), result.Summary = text, result.DetailJSON = detail.%ToJSON()
    Do $$$AssertStatusOK(wf.OnVerify(c, result), "the verification is taken")
    Do $$$AssertEquals(c.State, "escalated", "a person checks")
    Do $$$AssertEquals(c.Headline, "Escalated: the resend's outcome is unknown", "and the headline claims nothing")
    Set id = c.%Id(), event = ""
    &sql(SELECT TOP 1 Text INTO :event FROM Shutter_Store.CaseEvent WHERE "Case" = :id AND ToState = 'escalated' ORDER BY Seq DESC)
    Do $$$AssertEquals(##class(Shutter.API.Dispatch).ReasonFromEvent(event, "escalated"), "WRITE_OUTCOME_UNKNOWN", "the reason it shows: " _ event)
    Set again = ##class(Shutter.Store.Approval).%OpenId(approval.%Id())
    Do again.%Reload()
    Do $$$AssertTrue(again.Revoked, "the approval authorised one write and it is spent")
}

}
