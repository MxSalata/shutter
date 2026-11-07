/// What a connector makes of a request nobody answered (CONTRACTS 1.3, v1.42). The adapter's response object has no status
/// then and the connectors store +StatusCode, so "no answer" arrives as 0: a test on an empty status would pass and prove
/// nothing, which is how a timed-out write came to read as refused, with the receiver applying it.
Class Shutter.Test.NoAnswer Extends %UnitTest.TestCase
{

/// The status the adapter gives for a request that timed out, and for a socket that never opened.
ClassMethod TimedOut() As %Status
{
    Quit $$$ERROR(5922)
}

ClassMethod NeverOpened() As %Status
{
    Quit $$$ERROR(6059, "ward", 80)
}

/// A result carrying this status, classified by the given class's Classify.
ClassMethod Classified(class As %String, httpStatus As %String, sc As %Status) As Shutter.Msg.WardResult
{
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.HttpStatus = httpStatus
    Do $CLASSMETHOD(class, "Classify", r, sc, {})
    Quit r
}

Method TestAWriteNobodyAnswered()
{
    For class = "Shutter.Operation.Ward", "Hospital.Operation.DownstreamOut" {
        For status = 0, "" {
            Set r = ..Classified(class, status, ..TimedOut())
            Do $$$AssertEquals(r.Outcome, "uncertain", class _ ", status [" _ status _ "]: a timed-out write may have been applied")
            Do $$$AssertTrue(r.Error [ "5922", class _ ": the adapter's words are kept, with no HTTP 0 in them: " _ r.Error)
            Do $$$AssertNotTrue(r.Error [ "HTTP 0", class _ ": no HTTP 0")
            Do $$$AssertTrue(r.Error [ "did not answer; the operation may have been applied", class _ ": a person is told what it means: " _ r.Error)
            Set r = ..Classified(class, status, $$$OK)
            Do $$$AssertEquals(r.Outcome, "uncertain", class _ ", status [" _ status _ "]: no answer and no error is still unknown")
        }
    }
}

Method TestASocketThatNeverOpened()
{
    For class = "Shutter.Operation.Ward", "Hospital.Operation.DownstreamOut" {
        Do $$$AssertEquals(..Classified(class, 0, ..NeverOpened()).Outcome, "unavailable", class _ ": 6059 sent nothing")
        Set refused = $$$ERROR($$$GeneralError, "HTTP Connect failed for ward:8080 - Connection refused")
        Do $$$AssertEquals(..Classified(class, 0, refused).Outcome, "unavailable", class _ ": the wording is the fallback")
        Do $$$AssertNotTrue(..Classified(class, 0, refused).Error [ "may have been applied", class _ ": nothing was sent, so nothing may have been applied")
    }
}

/// A rehearsal's failure says what it shows: the receiver's refusal of the dry run shows the action would not apply, and
/// no answer, or the connector's own refusal with nothing sent, shows nothing.
Method TestARehearsalThatFailed()
{
    Set w = "Shutter.Process.CaseWorkflow", wouldNot = "would not apply", nothing = "shows nothing"
    Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", "would_not_apply", 200) [ wouldNot, "the receiver said would not apply")
    Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", "refused", 422) [ wouldNot, "a 422 to the dry run is its answer")
    Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", "refused", 409) [ wouldNot, "a 409 to the dry run is its answer")
    Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", "version_conflict", 409) [ wouldNot, "so is a version conflict")
    Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", "refused", "") [ nothing, "the connector refused: nothing was sent")
    For outcome = "uncertain", "unavailable", "error" {
        Do $$$AssertTrue($CLASSMETHOD(w, "RehearsalFailureWords", outcome, 0) [ nothing, outcome _ ", no answer: shows nothing")
    }
}

/// The words on the audit trail and in the forwarder's log, for a request nobody answered and for one that was answered.
Method TestTheWordsForNoAnswer()
{
    Set w = "Shutter.Process.CaseWorkflow", f = "Shutter.Intake.Forwarder"
    Do $$$AssertEquals($CLASSMETHOD(w, "UnreadableWords", 0, 0), "encounter no answer, receipt no answer", "neither lookup answered")
    Do $$$AssertEquals($CLASSMETHOD(w, "UnreadableWords", "", 503), "encounter no answer, receipt HTTP 503", "no status is no answer")
    Do $$$AssertEquals($CLASSMETHOD(w, "UnreadableWords", 200, 500), "encounter HTTP 200, receipt HTTP 500", "an answer keeps its status")
    Do $$$AssertEquals($CLASSMETHOD(w, "UnreadableWords", 0, -1), "encounter no answer, receipt not kept by this receiver", "a receiver with no receipts")
    For status = 0, "" {
        Set words = $CLASSMETHOD(f, "RefusalWords", status, ..TimedOut(), "", "/intake")
        Do $$$AssertTrue(words [ "No answer from Shutter at /intake", "status [" _ status _ "]: " _ words)
        Do $$$AssertTrue(words [ "5922", "and the adapter's reason is kept")
        Do $$$AssertNotTrue(words [ "HTTP 0", "with no HTTP 0")
    }
    Do $$$AssertEquals($CLASSMETHOD(f, "RefusalWords", 503, $$$OK, "{}", "/intake"), "HTTP 503 from Shutter: {}", "an answer is quoted")
    Do $$$AssertEquals($CLASSMETHOD(f, "RefusalWords", 500, $$$OK, "", "/intake"), "HTTP 500 from Shutter: empty body", "even an empty one")
}

/// A 202 that names no case took nothing: the real intake always names one, so this is a proxy or a wrong path answering.
Method TestA202WithNoCaseIsARefusal()
{
    Set f = "Shutter.Intake.Forwarder"
    For body = "", "<html>Welcome</html>", "{}", "[]", "{""state"":""sealed""}", "{""caseId"":""""}", "{""caseId"":null}", "not json" {
        Do $$$AssertEquals($CLASSMETHOD(f, "CaseIdIn", body), "", "no case in: " _ body)
    }
    Do $$$AssertEquals($CLASSMETHOD(f, "CaseIdIn", "{""caseId"":""C-000123"",""state"":""sealed"",""opened"":true}"), "C-000123", "a case")
    Set words = $CLASSMETHOD(f, "NoCaseWords", "/intake", "<html>")
    Do $$$AssertTrue((words [ "202") && (words [ "/intake") && (words [ "no case id"), "the words say so: " _ words)
}

/// What the forwarder keeps in its own queue and tries again: no answer, and the answers of a Shutter or a gateway that is down. A
/// refusal is final: an answer about the request itself does not change by asking again.
Method TestWhichAnswersAreTriedAgain()
{
    Set f = "Shutter.Intake.Forwarder"
    For status = "", 0, 502, 503, 504 {
        Do $$$AssertTrue($CLASSMETHOD(f, "TryAgain", status), "[" _ status _ "] is tried again")
    }
    For status = 202, 400, 401, 403, 404, 413, 500 {
        Do $$$AssertNotTrue($CLASSMETHOD(f, "TryAgain", status), "[" _ status _ "] is not")
    }
}

/// An answer keeps its meaning: nothing above reaches a request that got one.
Method TestAnAnswerIsNotNoAnswer()
{
    For class = "Shutter.Operation.Ward", "Hospital.Operation.DownstreamOut" {
        Do $$$AssertEquals(..Classified(class, 504, $$$OK).Outcome, "uncertain", class _ ": 504, the lost acknowledgment of S3")
        Do $$$AssertEquals(..Classified(class, 503, $$$OK).Outcome, "unavailable", class _ ": 503")
        Do $$$AssertEquals(..Classified(class, 500, $$$OK).Outcome, "uncertain", class _ ": 500")
        Do $$$AssertEquals(..Classified(class, 201, $$$OK).Outcome, "applied", class _ ": 201")
        Do $$$AssertEquals(..Classified(class, 403, $$$OK).Outcome, "error", class _ ": 403")
    }
}

/// A preflight read that got no answer changes nothing at the receiver, so it is unavailable however it failed.
Method TestAReadNobodyAnswered()
{
    Set w = "Shutter.Operation.Ward"
    For status = 0, "" {
        For sc = ..TimedOut(), ..NeverOpened() {
            Set r = ##class(Shutter.Msg.WardResult).%New()
            Set r.HttpStatus = status
            Do $CLASSMETHOD(w, "ClassifyRead", r, sc, {}, "/state")
            Do $$$AssertEquals(r.Outcome, "unavailable", "status [" _ status _ "]: " _ r.Error)
            Do $$$AssertTrue(r.Error '= "", "and says why")
        }
    }
    Set r = ##class(Shutter.Msg.WardResult).%New()
    Set r.HttpStatus = 200
    Do $CLASSMETHOD(w, "ClassifyRead", r, $$$OK, {"version": 3, "state": "admitted"}, "/state")
    Do $$$AssertEquals(r.Outcome _ "|" _ r.EncounterVersion, "read|3", "an answer is read")
}

/// A saved case with a snapshot and a resend plan, under its own public id outside the case counter.
Method SavedCase(caseId As %String, encounter As %String, Output plan As Shutter.Store.Plan) As Shutter.Store.Case
{
    Do ..Drop(caseId)
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = caseId, c.Receiver = "Downstream Out", c.OperationKey = "PAS^HOSP^MRN9005^ENC-9005^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.Ward = "WARD-B", c.EventTime = "2026-10-15T08:20:00Z", c.EncounterId = encounter, c.PatientId = "MRN9005"
    Set c.FailureKind = "delivery_failed", c.FailureText = "x", c.State = "executing", c.Headline = "The transfer was not delivered"
    Set c.OpenedAt = ##class(Shutter.Util.Time).NowUTC(), c.UpdatedAt = c.OpenedAt
    Do $$$AssertStatusOK(c.%Save(), "the case " _ caseId _ " is saved")
    Set snap = ##class(Shutter.Store.Snapshot).Begin(c)
    Do $$$AssertStatusOK(snap.%Save(), "its snapshot")
    Set action = {"type": "resend", "operation_key": (c.OperationKey), "expected_version": 1}
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(c, snap, {"disposition": "resend", "summary": "resend", "action": (action)}, "rules", .plan), "its plan")
    Quit c
}

ClassMethod Drop(caseId As %String)
{
    Set c = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If $ISOBJECT(c) Do ##class(Shutter.Store.Case).PurgeCase(c.%Id())
}

/// A write call that answered with an error status never reaches OnExecute. Whether the receiver applied it is unknown, so the
/// attempt is recorded as uncertain: without it the case read 0 writes, and "sent nothing", with the receiver perhaps holding it.
/// The email says so, and says no answer rather than HTTP 0.
Method TestAWriteCallThatErrored()
{
    Set id = "C-TEST-NOANSWER-A"
    Set c = ..SavedCase(id, "ENC-9005", .plan)
    Set wf = ##class(Shutter.Process.CaseWorkflow).%New("Case Workflow")
    Set wf.CaseId = id, wf.PlanId = plan.%Id()
    Do $$$AssertStatusOK(wf.OnError("", .response, "", $$$ERROR($$$GeneralError, "the item is not running"), "execute"), "the error is handled")
    Set after = ##class(Shutter.Store.Case).ByCaseId(id)
    Do $$$AssertEquals(after.State, "escalated", "a person decides")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Outcome, HttpStatus, Error FROM Shutter_Store.ExecutionAttempt WHERE ""Case"" = ?", after.%Id()), n = 0
    While rs.%Next() { Set n = n + 1, outcome = rs.%Get("Outcome"), status = rs.%Get("HttpStatus"), error = rs.%Get("Error") }
    Do $$$AssertEquals(n, 1, "one attempt is recorded")
    Do $$$AssertEquals($GET(outcome) _ "|" _ $GET(status), "uncertain|0", "as a write that may have landed")
    Do $$$AssertTrue($GET(error) [ "the item is not running", "with the error's words")
    Do $$$AssertEquals(##class(Shutter.Util.EscalationDraft).LatestAttemptOutcome(after), "uncertain", "the latest attempt")
    Do $$$AssertStatusOK(##class(Shutter.Util.EscalationDraft).Build(after, {"name": "the team"}, .subject, .body), "the email is drafted")
    Do $$$AssertTrue(body [ "got no answer", "the email says the answer was lost")
    Do $$$AssertTrue(body [ "it can still land while the receiver stays at the version below", "and that it can still land")
    Do $$$AssertEquals(##class(Shutter.Util.EscalationDraft).Reason(after, .failing).Code, "WRITE_OUTCOME_UNKNOWN", "and its reason says the same as the case's")
    Do $$$AssertTrue(body [ "Before anyone corrects this by hand", "and to check first")
    Do $$$AssertTrue(body [ ": uncertain (no answer)", "the write reads no answer")
    Do $$$AssertNotTrue(body [ "HTTP 0", "with no HTTP 0")
    Do $$$AssertNotTrue(body [ "Nothing: Shutter sent no write", "and never that nothing was sent")
    Do ..Drop(id)
}

/// A write the receiver answered keeps the old opening and its status, and a message with no encounter says so in the email.
Method TestTheEmailOfOtherCases()
{
    Set id = "C-TEST-NOANSWER-B"
    Set c = ..SavedCase(id, "", .plan)
    Do $$$AssertEquals(##class(Shutter.Util.EscalationDraft).LatestAttemptOutcome(c), "", "no attempt yet")
    Do $$$AssertStatusOK(##class(Shutter.Store.ExecutionAttempt).Create(c, plan, "", "", 201, "applied", "", "", .a), "an acknowledged write")
    Do $$$AssertStatusOK(##class(Shutter.Util.EscalationDraft).Build(c, {"name": "the team"}, .subject, .body), "the email is drafted")
    Do $$$AssertTrue(body [ "correct them by hand", "the old opening")
    Do $$$AssertTrue(body [ ": applied (HTTP 201)", "the status stays")
    Do $$$AssertTrue(subject [ "(no encounter)", "no encounter in the subject: " _ subject)
    Do $$$AssertNotTrue(subject [ ", encounter ", "and no empty one")
    Do $$$AssertTrue(body [ "none (a patient-level message)", "nor in the body")
    Do $$$AssertEquals(##class(Shutter.Util.EscalationDraft).StatusWords(""), "no answer", "no status")
    Do $$$AssertEquals(##class(Shutter.Util.EscalationDraft).StatusWords(503), "HTTP 503", "a status")
    Do ..Drop(id)
}

/// The reason a stopped case shows, from the event that stopped it: a rehearsal nobody answered is no refusal, and what stopped
/// a case after the gate passed it is not hidden by an earlier round's failing decision.
Method TestTheReasonForAStoppedCase()
{
    Set d = "Shutter.API.Dispatch"
    Set none = $CLASSMETHOD("Shutter.Process.CaseWorkflow", "RehearsalFailureWords", "unavailable", 0) _ "unavailable"
    Set would = $CLASSMETHOD("Shutter.Process.CaseWorkflow", "RehearsalFailureWords", "would_not_apply", 200) _ "would_not_apply"
    Do $$$AssertEquals($CLASSMETHOD(d, "ReasonFromEvent", none, "blocked"), "BLOCKED", "no usable answer shows nothing: " _ none)
    Do $$$AssertEquals($CLASSMETHOD(d, "ReasonFromEvent", would, "blocked"), "REHEARSAL_WOULD_NOT_APPLY", "a refused dry run still reads so: " _ would)
    Do $$$AssertEquals($CLASSMETHOD(d, "ReasonFromEvent", "Not verified (not_committed): Not committed: by the last read", "escalated"), "WRITE_NOT_COMMITTED", "not committed")
    Do $$$AssertEquals($CLASSMETHOD(d, "ReasonFromEvent", "Not verified (unknown): x; a person must check", "escalated"), "WRITE_OUTCOME_UNKNOWN", "unknown")
    Do $$$AssertEquals($CLASSMETHOD(d, "ReasonFromEvent", "Rejected by approver", "blocked"), "REJECTED_BY_APPROVER", "a rejection")
    Do $$$AssertEquals($CLASSMETHOD(d, "ReasonFromEvent", "The conditional write was refused: refused", "blocked"), "DISPATCH_REFUSED", "a refused write")
    Do $$$AssertEquals($CLASSMETHOD(d, "ReasonFromEvent", "A person must look", "escalated"), "ESCALATED", "a person")
    Do $$$AssertEquals($CLASSMETHOD(d, "ReasonFromEvent", "", "blocked"), "BLOCKED", "no words")
    Do $$$AssertEquals($CLASSMETHOD(d, "ReasonFromEvent", "Error from the write call: refused. Whether the receiver applied the operation is unknown; a person must check", "escalated"), "WRITE_OUTCOME_UNKNOWN", "a write call that errored, even with refused in its words")
    Do $$$AssertTrue($CLASSMETHOD(d, "StoppedAfterTheGate", "Error from the write call: x"), "and that names the reason too")
    For text = "Not verified (not_committed): Not committed: x", "Not verified (unknown): x", none {
        Do $$$AssertTrue($CLASSMETHOD(d, "StoppedAfterTheGate", text), "the event names the reason: " _ text)
    }
    For text = "The gate did not pass the plan; a person must decide", "The gate did not pass the dispatch: x", would, "" {
        Do $$$AssertNotTrue($CLASSMETHOD(d, "StoppedAfterTheGate", text), "the gate's decision names the reason: " _ text)
    }
}

}
