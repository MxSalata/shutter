/// FHIR Verifier's walk (Shutter.Operation.FHIRVerify): what it reads, the context it hands to the Judge, and how the
/// six outcomes are stored. Each test makes a case whose one update was really sent to the test FHIR server in process
/// (<class>Shutter.Test.FakeFhir</class>): the read is sealed, the body is built by the proposal builder, the binding
/// and the fence are the stores' own, and the PUT goes out with If-Match as FHIR Out sends it. The verifier is
/// <class>Shutter.Test.QuietFHIRVerify</class>, whose reads go through a FHIR Receiver with that same server as its
/// adapter, so every request of a walk is in the adapter's log. A test that stores a profile puts the row back as it
/// was, and every case it saved is purged.
Class Shutter.Test.FHIRVerify Extends %UnitTest.TestCase
{

Parameter SERVICE = "FHIRFacade.Service";

Parameter RECEIVER = "UT FHIR Verify Out";

Parameter BASE = "/ut-fhir/r4";

Parameter SYS = "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49";

/// The reads of a walk over two bound Locations with no version to read by id, as the adapter logs them.
Parameter WALK = "Encounter/enc-1 | Patient/demo-p1 | Location/ward-a | Location/ward-b | Encounter/enc-1/_history";

Property Made As %String [ MultiDimensional ];

Property SavedProfile As %String(MAXLEN = "");

Property ProfileChanged As %Boolean [ InitialExpression = 0 ];

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

Method OnAfterOneTest(testname As %String) As %Status
{
    If ..Loaded() Do $CLASSMETHOD(..#SERVICE, "Reset")
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ##class(Shutter.Store.Case).PurgeCase(id)
    }
    Kill i%Made
    Do ..RestoreProfile()
    Quit $$$OK
}

/// An update that was applied is verified in the version the receiver named, read by id, and the record of it is the
/// verification, the case's note and the answer.
Method TestAppliedThenVerified()
{
    Quit:'..Sent(.s)
    Do $$$AssertEquals(s("outcome") _ " " _ s("status") _ " " _ s("fence").ResponseEtag, "applied 200 W/""2""", "the update was applied as version 2")
    Set op = ..Verifier(.http)
    Set response = ..Walk(op, .s, .detail)
    Do ..Is(response, detail, "verified", "verified", "committed_current", "", "applied and read back")
    Do $$$AssertEquals(detail."committed_version" _ " " _ detail."current_version" _ " " _ detail."base_version", "2 2 1", "committed as version 2, which is current, from version 1")
    Do $$$AssertEquals(detail.kind _ " " _ detail.disposition, "fhir resend", "the detail says what kind of verification it is")
    Do $$$AssertEquals(detail.retry, 0, "no other read is asked for")
    Do $$$AssertEquals(response.Summary, "Verified in Encounter version ""2"": the approved location update is present, carrying Shutter's marker; no other field changed from version ""1"", the version the write was conditional on.", "the Judge's sentence, unchanged")
    Do $$$AssertEquals(response.Error, "", "no error")
    // The reads: one request to the reader, the version last, nothing but GETs
    Do $$$AssertEquals(..Log(http), ..#WALK _ " | Encounter/enc-1/_history/2", "the walk's requests")
    Do $$$AssertEquals(..NotReads(http), "", "every request is a GET with no body and no If-Match")
    Do $$$AssertEquals(op.Calls, 1, "one read request")
    Set read = op.LastRead
    Do $$$AssertEquals(read.CaseId _ " " _ read.Purpose _ " " _ read.EncounterId _ " " _ read.PatientRef _ " " _ read.Vid, s("case").CaseId _ " verify enc-1 Patient/demo-p1 2", "what the request asked for")
    Do $$$AssertEquals(read.LocationRefsJSON, "[""Location/ward-a"",""Location/ward-b""]", "every bound Location")
    // The stored verification
    Set v = ##class(Shutter.Store.Verification).%OpenId(response.VerificationId)
    If '$ISOBJECT(v) Do $$$AssertTrue(0, "the verification is stored") Quit
    Do $$$AssertEquals(v.Outcome _ " | " _ v.Summary, "verified | " _ response.Summary, "its word and its sentence")
    Do $$$AssertEquals(v.CaseGetObjectId() _ " " _ v.AttemptGetObjectId(), s("case").%Id() _ " " _ s("attempt").%Id(), "on the case and the attempt")
    Do $$$AssertEquals(..J(v.DetailJSON).%ToJSON(), detail.%ToJSON(), "its detail is the answer's")
    // The case's note
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Kind, Text, Ref, Actor FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? ORDER BY Seq DESC", s("case").%Id())
    If 'rs.%Next() Do $$$AssertTrue(0, "the case has an event") Quit
    Do $$$AssertEquals(rs.%Get("Kind") _ " | " _ rs.%Get("Text"), "artifact | Verification: verified. " _ response.Summary, "the note")
    Do $$$AssertEquals(rs.%Get("Ref") _ " " _ rs.%Get("Actor"), "verification:" _ v.%Id() _ " system", "names the verification")
}

/// The receiver committed the update and its answer was lost: there is no version to read by id, and the history
/// alone verifies it.
Method TestCommitDropResponseIsVerifiedFromTheHistory()
{
    Quit:'..Sent(.s, "commit_drop_response")
    Do $$$AssertEquals(s("outcome") _ " " _ s("status") _ " [" _ s("fence").ResponseEtag _ "]", "uncertain 500 []", "the answer was a 500 with no ETag")
    Set op = ..Verifier(.http)
    Set response = ..Walk(op, .s, .detail)
    Do ..Is(response, detail, "verified", "verified", "committed_current", "", "committed with a lost answer")
    Do $$$AssertEquals(detail."committed_version", "2", "in the version the history shows")
    Do $$$AssertEquals(op.LastRead.Vid, "", "no version was asked for")
    Do $$$AssertEquals(..Log(http), ..#WALK, "and none was read by id")
    Do $$$AssertEquals(##class(Shutter.Store.Verification).%OpenId(response.VerificationId).Outcome, "verified", "stored as verified")
}

/// A server that ignored If-Match while another writer got in between: the marked version does not follow the base,
/// so another version was overwritten. Failed, never verified.
Method TestIgnoreIfMatchWithASecondWriterFails()
{
    Quit:'..Sent(.s, "ignore_if_match,second_writer_between_read_and_write")
    Do $$$AssertEquals(s("outcome") _ " " _ s("status") _ " " _ s("fence").ResponseEtag, "applied 200 W/""3""", "the receiver said applied, as version 3")
    Set op = ..Verifier(.http)
    Set response = ..Walk(op, .s, .detail)
    Do ..Is(response, detail, "failed", "failed", "introducing_predecessor_not_base", "FHIR_WRITE_CONTRADICTED", "a lost update")
    Do $$$AssertEquals(detail."committed_version" _ " " _ detail."base_version" _ " " _ detail."head_version", "3 1 3", "version 3 carries the marker, two after the base")
    Do $$$AssertTrue(response.Summary [ "The receiver's record contradicts the update", "the sentence says so: " _ response.Summary)
    Do $$$AssertEquals(##class(Shutter.Store.Verification).%OpenId(response.VerificationId).Outcome, "failed", "stored as failed")
}

/// Another writer alone: the update was refused with a 412 and the history's head is the other writer's version.
/// Inside the settle window that is unknown; after it, no committed version was found.
Method TestASecondWriterAloneLeavesAnotherHead()
{
    Quit:'..Sent(.s, "second_writer_between_read_and_write")
    Do $$$AssertEquals(s("outcome") _ " " _ s("status"), "version_conflict 412", "the receiver refused the update")
    Set op = ..Verifier(.http)
    Set response = ..Walk(op, .s, .detail)
    Do ..Is(response, detail, "unresolved", "unknown", "settling", "", "inside the settle window")
    Do $$$AssertEquals(detail.retry, 1, "another read is asked for")
    Do $$$AssertEquals(detail."head_version" _ " " _ detail."base_version" _ " [" _ detail."committed_version" _ "]", "2 1 []", "the head is the other writer's version 2")
    Do $$$AssertEquals(..Log(http), ..#WALK, "no version read by id")
    Do ..Age(.s, 100)
    Set response = ..Walk(..Verifier(), .s, .detail)
    Do ..Is(response, detail, "not_committed", "not_found", "no_committed_version", "FHIR_WRITE_NOT_FOUND", "after the settle window")
    Do $$$AssertEquals(detail.retry, 0, "final")
    Do $$$AssertTrue(response.Summary [ "from version ""2"" back to the base ""1""", "the sentence names the history read: " _ response.Summary)
    Do $$$AssertEquals(##class(Shutter.Store.Verification).%OpenId(response.VerificationId).Outcome, "not_committed", "stored as not committed")
}

/// A walk that skipped the read of a bound Location never verifies, however good the rest is.
Method TestASkippedLocationReadIsContextInvalid()
{
    Quit:'..Sent(.s)
    Set op = ..Verifier(.http)
    Set op.Skip = "Location/ward-b"
    Set response = ..Walk(op, .s, .detail)
    Do ..Is(response, detail, "unresolved", "unknown", "context_invalid", "FHIR_WRITE_OUTCOME_UNKNOWN", "one Location read short")
    Do $$$AssertEquals(detail.note, "the bound location Location/ward-b has 0 reads, not one", "and why")
    Do $$$AssertEquals(detail.retry, 0, "no other read is asked for")
    Do $$$AssertEquals(##class(Shutter.Store.Verification).%OpenId(response.VerificationId).Outcome, "unresolved", "stored as unresolved")
    // The same case with every read made is verified: the skipped read alone decided
    Set response = ..Walk(..Verifier(), .s, .detail)
    Do ..Is(response, detail, "verified", "verified", "committed_current", "", "with every read made")
}

/// Every bound Location is read exactly once, the ones that are neither the prior nor the target too.
Method TestEachBoundLocationIsReadOnce()
{
    Quit:'..Sent(.s, "", 0, "a,b,c")
    Set op = ..Verifier(.http)
    Set response = ..Walk(op, .s, .detail)
    Do ..Is(response, detail, "verified", "verified", "committed_current", "", "three bound Locations")
    Do $$$AssertEquals(op.LastRead.LocationRefsJSON, "[""Location/ward-a"",""Location/ward-b"",""Location/ward-c""]", "the request names every bound Location")
    Do $$$AssertEquals(..Log(http), "Encounter/enc-1 | Patient/demo-p1 | Location/ward-a | Location/ward-b | Location/ward-c | Encounter/enc-1/_history | Encounter/enc-1/_history/2", "the request log")
    For ward = "a", "b", "c" {
        Do $$$AssertEquals($LENGTH(" | " _ ..Log(http) _ " | ", " | Location/ward-" _ ward _ " | ") - 1, 1, "Location/ward-" _ ward _ " is read once")
    }
    Do $$$AssertEquals(http.Requests, 7, "seven requests in all")
    Do $$$AssertEquals(..NotReads(http), "", "every one a GET with no body and no If-Match")
    Do $$$AssertEquals(op.Calls, 1, "in one read request")
}

/// A read that fails is never a verdict: every part has status 0, the Judge answers unknown history_unavailable, and
/// another read is asked for while the settle window is open.
Method TestAFailedReadIsARetry()
{
    Quit:'..Sent(.s)
    // The call to the reader fails
    Set op = ..Verifier(.http)
    Set op.Fail = "the reader did not answer in time"
    Set response = ..Walk(op, .s, .detail)
    Do ..Is(response, detail, "unresolved", "unknown", "history_unavailable", "", "the read call failed")
    Do $$$AssertEquals(detail.retry, 1, "the read call failed: a retry")
    Do $$$AssertEquals(+$GET(http.Requests), 0, "and nothing was asked of the receiver")
    // The reader answers with an error and no parts
    Set op = ..Verifier(.http)
    Set op.Reader.MaxTotal = 10
    Set response = ..Walk(op, .s, .detail)
    Do ..Is(response, detail, "unresolved", "unknown", "history_unavailable", "", "the reader answered with an error")
    Do $$$AssertEquals(detail.retry, 1, "the reader answered with an error: a retry")
    // The receiver answers nothing at all
    Set op = ..Verifier(.http)
    For i = 1:1:$LENGTH(..#WALK, " | ") {
        Set http.Canned("GET", $PIECE(..#WALK, " | ", i)) = $LISTBUILD(0)
    }
    Set http.Canned("GET", "Encounter/enc-1/_history/2") = $LISTBUILD(0)
    Set response = ..Walk(op, .s, .detail)
    Do ..Is(response, detail, "unresolved", "unknown", "history_unavailable", "", "the receiver answered nothing")
    Do $$$AssertEquals(detail.retry, 1, "the receiver answered nothing: a retry")
    Do $$$AssertEquals(http.Requests, 6, "each read was tried once")
    // After the settle window the same failure is final
    Do ..Age(.s, 100)
    Set op = ..Verifier()
    Set op.Fail = "the reader did not answer in time"
    Set response = ..Walk(op, .s, .detail)
    Do ..Is(response, detail, "unresolved", "unknown", "history_unavailable", "FHIR_WRITE_OUTCOME_UNKNOWN", "after the settle window")
    Do $$$AssertEquals(detail.retry, 0, "after the settle window: final")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM Shutter_Store.Verification WHERE ""Case"" = ? AND Outcome = 'unresolved'", s("case").%Id())
    Do $$$AssertEquals($SELECT(rs.%Next(): rs.%Get("n"), 1: -1), 4, "each walk stored its verification")
}

/// The further walks' schedule and the settle window are held together in the verifier's class: the waits add up to
/// the window, so the last walk of the schedule is made at or after it, and a walk made at the window is final.
Method TestTheScheduleReachesTheSettleWindow()
{
    Set cls = "Shutter.Operation.FHIRVerify", window = $PARAMETER(cls, "SETTLEFINALSECONDS")
    Set total = 0, waits = ""
    For n = 1:1:20 {
        Set wait = $CLASSMETHOD(cls, "RetryWait", n, .of)
        Quit:wait=""
        Set total = total + wait, waits = waits _ " " _ wait
    }
    Do $$$AssertEquals(waits _ " | " _ of, " 10 20 40 | 3", "three further walks, after 10, 20 and 40 seconds")
    Do $$$AssertEquals($CLASSMETHOD(cls, "RetryWait", 0) _ "|" _ $CLASSMETHOD(cls, "RetryWait", of + 1), "|", "and none before the first or after the last")
    Do $$$AssertTrue(total >= window, "the schedule reaches the settle window (" _ total _ " s of waits, a window of " _ window _ " s)")
    Quit:'..Sent(.s)
    // Before the window a failed read asks for another walk
    Do ..Age(.s, window - 15)
    Set op = ..Verifier()
    Set op.Fail = "the reader did not answer in time"
    Set response = ..Walk(op, .s, .detail)
    Do $$$AssertEquals(detail.reason _ " " _ detail.retry, "history_unavailable 1", "a walk made before the window asks for another")
    // The walk the schedule ends with is made its waits after the first, which is itself after the update: at the window
    Do ..Age(.s, total)
    Set op = ..Verifier()
    Set op.Fail = "the reader did not answer in time"
    Set response = ..Walk(op, .s, .detail)
    Do $$$AssertEquals(detail.reason _ " " _ detail.retry, "history_unavailable 0", "a walk made where the schedule ends is final")
}

/// The six outcomes of the Judge, row by row: the word stored and the case's code.
Method TestTheMappingTable()
{
    Set rows = $LISTBUILD(
        $LISTBUILD("verified", 0, "verified", ""),
        $LISTBUILD("verified_continued", 0, "verified", ""),
        $LISTBUILD("committed_review", 0, "unresolved", "FHIR_COMMITTED_NEEDS_REVIEW"),
        $LISTBUILD("not_found", 0, "not_committed", "FHIR_WRITE_NOT_FOUND"),
        $LISTBUILD("unknown", 1, "unresolved", ""),
        $LISTBUILD("unknown", 0, "unresolved", "FHIR_WRITE_OUTCOME_UNKNOWN"),
        $LISTBUILD("failed", 0, "failed", "FHIR_WRITE_CONTRADICTED"))
    Set seen = ""
    For i = 1:1:$LISTLENGTH(rows) {
        Set row = $LIST(rows, i), judged = $LIST(row, 1), retry = $LIST(row, 2)
        Set word = ##class(Shutter.Operation.FHIRVerify).Mapped(judged, retry, .code)
        Do $$$AssertEquals(word _ " [" _ code _ "]", $LIST(row, 3) _ " [" _ $LIST(row, 4) _ "]", judged _ $SELECT(retry: ", another read asked for", 1: ""))
        Do $$$AssertTrue($LISTFIND($LISTBUILD("verified", "not_committed", "unresolved", "failed"), word) > 0, judged _ ": one of the four words a verification is stored under")
        Set:'$LISTFIND(seen, judged) seen = seen _ $LISTBUILD(judged)
    }
    Do $$$AssertEquals($LISTTOSTRING(seen), $PARAMETER("Shutter.FHIR.Judge", "OUTCOMES"), "the rows are the Judge's six outcomes, each of them")
    Set word = ##class(Shutter.Operation.FHIRVerify).Mapped("no such word", 1, .code)
    Do $$$AssertEquals(word _ " [" _ code _ "]", "unresolved [FHIR_WRITE_OUTCOME_UNKNOWN]", "a word the Judge does not have is the unknown that is final")

    // The two rows no other test walks: a later change that follows the update, and a record that needs review
    Quit:'..Sent(.s)
    Set w = ..Current(.etag)
    Set w.status = "finished"
    Set entry = w.location.%Get(1)
    Set entry.status = "completed", entry.period.end = "2026-11-14T12:00:00Z"
    Do $$$AssertEquals(..Put("Encounter/enc-1", w, etag), 200, "another writer finishes the Encounter as version 3")
    Set response = ..Walk(..Verifier(), .s, .detail)
    Do ..Is(response, detail, "verified", "verified_continued", "committed_continued", "", "a later change followed")
    Do $$$AssertEquals(detail."committed_version" _ " " _ detail."current_version", "2 3", "the update is version 2, the current record version 3")

    Quit:'..Sent(.s)
    Do $$$AssertEquals(..Put("Patient/demo-p1", {"resourceType": "Patient", "id": "demo-p1", "identifier": [{"system": "urn:shutter:demo:mrn", "value": "MRN-UT1"}], "active": false}), 200, "the Patient is made inactive")
    Set response = ..Walk(..Verifier(), .s, .detail)
    Do ..Is(response, detail, "unresolved", "committed_review", "patient_changed", "FHIR_COMMITTED_NEEDS_REVIEW", "the update is there, the record needs review")
    Do $$$AssertEquals(detail."committed_version", "2", "the committed version is named")
}

/// The Judge's own codes are the words of the other receivers. A FHIR verification stores the FHIR code in their place.
Method TestTheStoredCaseCodeIsTheFhirCode()
{
    Do ##class(Shutter.FHIR.Judge).Judge({}, .text, .own)
    Do $$$AssertEquals(own."case_code", "WRITE_OUTCOME_UNKNOWN", "the Judge's own code for an unknown")
    // An update with no answer at all, which never reached the receiver
    Quit:'..Sent(.s, "", 1)
    Do $$$AssertEquals(s("outcome") _ " " _ s("status"), "uncertain 0", "no answer")
    Set response = ..Walk(..Verifier(), .s, .detail)
    Do ..Is(response, detail, "unresolved", "unknown", "head_is_base", "", "inside the settle window")
    Do $$$AssertEquals(..StoredCode(response), "", "no code is stored while another read is asked for")
    Do ..Age(.s, 100)
    Set response = ..Walk(..Verifier(), .s, .detail)
    Do ..Is(response, detail, "unresolved", "unknown", "head_is_base", "FHIR_WRITE_OUTCOME_UNKNOWN", "after the settle window")
    Do $$$AssertEquals(..StoredCode(response), "FHIR_WRITE_OUTCOME_UNKNOWN", "the stored code of an unknown")
    Do $$$AssertNotTrue(..StoredText(response) [ """WRITE_OUTCOME_UNKNOWN""", "the other receivers' word is nowhere in the stored row")
    Do $$$AssertNotTrue(response.DetailJSON [ """WRITE_OUTCOME_UNKNOWN""", "nor in the answer")
    // An update that was refused, with another writer's version as the head
    Quit:'..Sent(.s, "second_writer_between_read_and_write")
    Do ..Age(.s, 100)
    Set response = ..Walk(..Verifier(), .s, .detail)
    Do ..Is(response, detail, "not_committed", "not_found", "no_committed_version", "FHIR_WRITE_NOT_FOUND", "no version found")
    Do $$$AssertEquals(..StoredCode(response), "FHIR_WRITE_NOT_FOUND", "the stored code of a version not found")
    Do $$$AssertNotTrue((..StoredText(response) _ response.DetailJSON) [ "WRITE_NOT_COMMITTED", "the other receivers' word is nowhere")
}

/// The other receivers' verifications carry a verdict, which the workflow and the page read. A FHIR verification has
/// no such key, whatever its outcome.
Method TestNoVerdictKey()
{
    Quit:'..Sent(.s)
    Set response = ..Walk(..Verifier(), .s, .detail)
    Do ..Is(response, detail, "verified", "verified", "committed_current", "", "a verified walk")
    Do $$$AssertEquals(..Keys(detail), "reason,committed_version,current_version,base_version,head_version,path,case_code,retry,kind,judge_outcome,disposition", "the keys of its detail")
    Do $$$AssertNotTrue(..J(..StoredText(response)).%IsDefined("verdict"), "verified: no verdict key in the stored row")
    Set op = ..Verifier()
    Set op.Fail = "the reader did not answer in time"
    Set response = ..Walk(op, .s, .detail)
    Do $$$AssertNotTrue(detail.%IsDefined("verdict") || ..J(..StoredText(response)).%IsDefined("verdict"), "unknown: no verdict key")
    Quit:'..Sent(.s, "ignore_if_match,second_writer_between_read_and_write")
    Set response = ..Walk(..Verifier(), .s, .detail)
    Do $$$AssertEquals(response.Outcome, "failed", "a failed walk")
    Do $$$AssertNotTrue(detail.%IsDefined("verdict") || ..J(..StoredText(response)).%IsDefined("verdict"), "failed: no verdict key")
    Do $$$AssertNotTrue((response.DetailJSON _ ..StoredText(response)) [ """verdict""", "nor the word as a key anywhere")
}

/// What was sealed and what was sent are part of the context: without the plan's binding or the attempt nothing is
/// verified, though the update is there to be read.
Method TestAMissingBindingOrAttemptNeverVerifies()
{
    Quit:'..Sent(.s)
    // A plan with no binding: nothing is known to read
    Set op = ..Verifier(.http)
    Set response = ..Walk(op, .s, .detail, "", s("attempt").%Id())
    Do ..Is(response, detail, "unresolved", "unknown", "context_invalid", "FHIR_WRITE_OUTCOME_UNKNOWN", "no binding")
    Do $$$AssertEquals(detail.note, "no binding", "and why")
    Do $$$AssertEquals(op.Calls _ " " _ +$GET(http.Requests), "0 0", "nothing was read")
    // No attempt row
    Set response = ..Walk(..Verifier(), .s, .detail, s("plan").%Id(), "")
    Do ..Is(response, detail, "unresolved", "unknown", "context_invalid", "FHIR_WRITE_OUTCOME_UNKNOWN", "no attempt")
    Do $$$AssertEquals(detail.note, "the attempt's outcome is not one the connector records", "and why")
    // Another case's attempt and another case's plan are not this case's
    Set other = ..NewCase()
    Do $$$AssertStatusOK(##class(Shutter.Store.ExecutionAttempt).Create(other, "", "", "", 200, "applied", {"kind": "fhir"}, "", .foreign), "another case's attempt")
    Set response = ..Walk(..Verifier(), .s, .detail, s("plan").%Id(), foreign.%Id())
    Do ..Is(response, detail, "unresolved", "unknown", "context_invalid", "FHIR_WRITE_OUTCOME_UNKNOWN", "another case's attempt")
    Set request = ##class(Shutter.Msg.VerifyRequest).%New()
    Set request.CaseId = other.CaseId, request.PlanId = s("plan").%Id(), request.AttemptId = foreign.%Id()
    Set op = ..Verifier(.http)
    Do $$$AssertStatusOK(op.OnVerifyRequest(request, .response), "the verifier answers")
    Do $$$AssertEquals(response.Outcome _ " " _ ..J(response.DetailJSON).note _ " " _ +$GET(http.Requests), "unresolved no binding 0", "another case's plan gives no binding, and no read")
}

/// A request for a case that is not there is answered, not thrown: unknown, final, with nothing stored.
Method TestAnUnknownCaseIsAnswered()
{
    Set request = ##class(Shutter.Msg.VerifyRequest).%New()
    Set request.CaseId = "UT-FHIRVF-NO-SUCH-CASE", request.PlanId = "1", request.AttemptId = "1"
    Set op = ..Verifier(.http)
    Do $$$AssertStatusOK(op.OnVerifyRequest(request, .response), "the verifier answers")
    Set detail = ..J(response.DetailJSON)
    Do ..Is(response, detail, "unresolved", "unknown", "context_invalid", "FHIR_WRITE_OUTCOME_UNKNOWN", "an unknown case")
    Do $$$AssertEquals(response.Error _ " [" _ response.VerificationId _ "]", "Unknown case UT-FHIRVF-NO-SUCH-CASE []", "with the error and no verification")
    Do $$$AssertEquals(detail.kind _ " " _ detail.retry _ " " _ op.Calls, "fhir 0 0", "final, and nothing was read")
}

// ---- helpers ----

Method Loaded() As %Boolean
{
    Quit ##class(%Dictionary.CompiledClass).%ExistsId(..#SERVICE)
}

/// A case whose one update was sent, in <var>s</var>: "case", "plan", "binding", "fence", "attempt", and the "status"
/// and "outcome" of the write. The test FHIR server is emptied and seeded, the Encounter is read and sealed, the body
/// is the proposal builder's, and the PUT goes out with If-Match on the version read. <var>faults</var> is set on
/// the server for that PUT; <var>lost</var> sends it nowhere (no answer, nothing written). False, with the test
/// skipped, on an instance without the test FHIR server.
Method Sent(Output s, faults As %String = "", lost As %Boolean = 0, wards As %String = "a,b") As %Boolean
{
    Kill s
    If '..Loaded() {
        Do $$$AssertSkipped("FHIRFacade is not loaded on this instance")
        Quit 0
    }
    Do $CLASSMETHOD(..#SERVICE, "Reset")
    Do ..Seed(wards)
    Do ..ChangeEntry(wards)
    // The read the evidence sealed
    Set http = ..Http()
    Do http.SendFormDataArray(.answer, "GET", ..Ask(), "", "", ..#BASE _ "/Encounter/enc-1")
    Set etag = answer.GetHeader("ETag"), body = $ZCONVERT(answer.Data.Read(1000000), "I", "UTF8")
    Do $$$AssertEquals(etag, "W/""1""", "the Encounter is read at version 1")
    Set case = ..NewCase()
    Set snapshot = ##class(Shutter.Store.Snapshot).Begin(case)
    Do $$$AssertStatusOK(snapshot.Seal({"fhir": {"kind": "fhir_r4"}}), "the snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snapshot), "and is the case's current one")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRSealedRead).Keep(case, snapshot.%Id(), body), "its Encounter body is kept")
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, case.CurrentSnapshot, {"disposition": "resend", "action": {"type": "resend"}}, "rules", .plan), "a plan is saved")
    // The body, the binding and the fence
    Set fhir = {"kind": "fhir_r4", "message": {"prior_ward": "WARD-A", "target_ward": "WARD-B"}, "encounter": {"http_status": 200, "id": "enc-1", "version_id": "1"}, "patient": {"http_status": 200, "reference": "Patient/demo-p1", "etag": "W/\"1\""}, "locations": []}
    Set fhir.encounter.etag = etag, fhir.encounter."body_digest" = ##class(Shutter.FHIR.Plan).BodyDigest(body)
    Set entry = {"name": (..#RECEIVER), "fhir": (##class(Shutter.FHIR.Profile).Block(..#RECEIVER))}
    Set code = ##class(Shutter.FHIR.Proposal).Prepare(case, plan.%Id(), fhir, body, entry, .prepared)
    Do $$$AssertEquals(code, "", "the update is prepared" _ $SELECT(code = "": "", 1: ": " _ prepared.%ToJSON()))
    Quit:code'="" 0
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan, prepared, .binding), "the binding is sealed")
    Do $$$AssertStatusOK(binding.Bind("UTV" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.FHIRVerify)), "and tied to an approval")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, binding, .fence, .created), "the fence row is opened")
    Do $$$AssertTrue(fence.MarkSent(), "and marked sent")
    // The one update
    If faults '= "" Do $CLASSMETHOD(..#SERVICE, "SetFault", faults, 1)
    Set out = ..Http()
    If lost Set out.Canned("PUT", "Encounter/enc-1") = $LISTBUILD(0)
    Set sc = out.SendFormDataArray(.answer, "PUT", ..Ask(binding.ExpectedEtag, binding.ApprovedBody), "", "", ..#BASE _ "/Encounter/enc-1")
    Set status = 0, retag = "", location = ""
    If $ISOBJECT($GET(answer)) Set status = +answer.StatusCode, retag = answer.GetHeader("ETag"), location = answer.GetHeader("Location")
    Set outcome = $SELECT(status = 200: "applied", status = 412: "version_conflict", 1: "uncertain")
    Do $$$AssertStatusOK(fence.Answer(status, outcome, retag, location, ""), "the answer is recorded on the fence")
    Set receipt = {"kind": "fhir", "encounter": "Encounter/enc-1", "expected_etag": (binding.ExpectedEtag), "response_etag": (retag), "response_location": (location), "body_digest": (binding.ApprovedBodyDigest), "operation_id": (binding.OperationId), "marker_system": (binding.MarkerSystem)}
    Do $$$AssertStatusOK(##class(Shutter.Store.ExecutionAttempt).Create(case, plan, "", "", status, outcome, {"kind": "fhir", "sent": true, "reason_code": "", "diagnostics": "", "receipt": (receipt)}, "", .attempt), "the attempt is recorded")
    Do $$$AssertStatusOK(fence.SetExecutionAttempt(attempt.%Id()), "and named on the fence")
    Set s("case") = case, s("plan") = plan, s("binding") = binding, s("fence") = fence, s("attempt") = attempt
    Set s("status") = status, s("outcome") = outcome
    Quit 1
}

/// The verifier, its reads going to the test FHIR server through a FHIR Receiver; <var>http</var> is that reader's
/// adapter, whose log is the walk's requests.
Method Verifier(Output http As Shutter.Test.FakeFhir) As Shutter.Test.QuietFHIRVerify
{
    Set op = ##class(Shutter.Test.QuietFHIRVerify).%New("FHIR Verifier (unit test)")
    Set reader = ##class(Shutter.Operation.FHIRReceiver).%New("FHIR Receiver (unit test)")
    Set http = ..Http()
    Set reader.Adapter = http
    Set op.Reader = reader
    Quit op
}

/// One walk: the answer and its detail. The plan and the attempt are the scenario's unless others are given.
Method Walk(op As Shutter.Test.QuietFHIRVerify, ByRef s, Output detail As %DynamicObject, planId As %String, attemptId As %String) As Shutter.Msg.VerifyResult
{
    Set request = ##class(Shutter.Msg.VerifyRequest).%New()
    Set request.CaseId = s("case").CaseId
    Set request.PlanId = $SELECT($DATA(planId): planId, 1: s("plan").%Id())
    Set request.AttemptId = $SELECT($DATA(attemptId): attemptId, 1: s("attempt").%Id())
    Do $$$AssertStatusOK(op.OnVerifyRequest(request, .response), "the verifier answers")
    Set detail = ..J(response.DetailJSON)
    Quit response
}

/// What a walk said: the word stored, the Judge's word, its reason and the case's code.
Method Is(response As Shutter.Msg.VerifyResult, detail As %DynamicObject, word As %String, judged As %String, reason As %String, code As %String, what As %String)
{
    Do $$$AssertEquals(response.Outcome _ " " _ detail."judge_outcome" _ " " _ detail.reason _ " [" _ detail."case_code" _ "]", word _ " " _ judged _ " " _ reason _ " [" _ code _ "]", what _ " (" _ response.Summary _ " " _ response.DetailJSON _ ")")
}

/// The fence's send, moved <var>seconds</var> into the past in the stored row: the walk then reads as that long after
/// the update. The test still holds the row open as it was, so this also shows that the walk reads the stored row.
Method Age(ByRef s, seconds As %Integer)
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "UPDATE Shutter_Store.FHIRAttempt SET SentAt = ? WHERE ID = ?", ##class(Shutter.Util.Time).FromNow(-seconds), s("fence").%Id())
    Do $$$AssertEquals(rs.%SQLCODE _ " " _ rs.%ROWCOUNT, "0 1", "the update is now " _ seconds _ " seconds old")
}

/// The stored verification's detail, as text, and its case code.
ClassMethod StoredText(response As Shutter.Msg.VerifyResult) As %String
{
    Set v = ##class(Shutter.Store.Verification).%OpenId(response.VerificationId)
    Quit $SELECT($ISOBJECT(v): v.DetailJSON, 1: "{}")
}

ClassMethod StoredCode(response As Shutter.Msg.VerifyResult) As %String
{
    Set detail = ..J(..StoredText(response))
    Quit $SELECT(detail.%GetTypeOf("case_code") = "string": detail."case_code", 1: "no case_code")
}

/// An adapter that is the test FHIR server.
Method Http() As Shutter.Test.FakeFhir
{
    Set http = ##class(Shutter.Test.FakeFhir).%New()
    Set http.Base = ..#BASE
    Quit http
}

/// A request as a client sends it: a read, or with a body an update, with If-Match when one is given.
ClassMethod Ask(ifMatch As %String = "", body As %String = "") As %Net.HttpRequest
{
    Set http = ##class(%Net.HttpRequest).%New()
    Do http.SetHeader("Accept", "application/fhir+json")
    If ifMatch '= "" Do http.SetHeader("If-Match", ifMatch)
    If body '= "" {
        Set http.ContentType = "application/fhir+json"
        Do http.EntityBody.Write($ZCONVERT(body, "O", "UTF8"))
    }
    Quit http
}

/// The Encounter as the server holds it now, with its ETag.
Method Current(Output etag As %String) As %DynamicObject
{
    Set http = ..Http()
    Do http.SendFormDataArray(.answer, "GET", ..Ask(), "", "", ..#BASE _ "/Encounter/enc-1")
    Set etag = answer.GetHeader("ETag")
    Quit ..J($ZCONVERT(answer.Data.Read(1000000), "I", "UTF8"))
}

/// Another writer's PUT of a resource; the status it was answered with.
Method Put(path As %String, resource As %DynamicObject, ifMatch As %String = "") As %Integer
{
    Set http = ..Http()
    Do http.SendFormDataArray(.answer, "PUT", ..Ask(ifMatch, resource.%ToJSON()), "", "", ..#BASE _ "/" _ path)
    Quit $SELECT($ISOBJECT($GET(answer)): +answer.StatusCode, 1: 0)
}

/// The paths of the requests the adapter saw, in order.
ClassMethod Log(http As Shutter.Test.FakeFhir) As %String
{
    Set out = ""
    For i = 1:1:+$GET(http.Requests) {
        Set out = out _ $SELECT(i > 1: " | ", 1: "") _ $LIST(http.Requests(i), 2)
    }
    Quit out
}

/// The requests the adapter saw that are not a GET with no body and no If-Match; "" when there is none.
ClassMethod NotReads(http As Shutter.Test.FakeFhir) As %String
{
    Set others = ""
    For i = 1:1:+$GET(http.Requests) {
        Set verb = $LIST(http.Requests(i), 1)
        Set:(verb'="GET")||($LIST(http.Requests(i), 3)'="")||($LIST(http.Requests(i), 4)'="") others = others _ verb _ " " _ $LIST(http.Requests(i), 2) _ "; "
    }
    Quit others
}

ClassMethod J(text As %String) As %DynamicObject
{
    Quit ##class(%DynamicAbstractObject).%FromJSON(text)
}

/// The keys of an object, in its order.
ClassMethod Keys(obj As %DynamicObject) As %String
{
    Set out = "", it = obj.%GetIterator()
    While it.%GetNext(.key) { Set out = out _ $SELECT(out = "": "", 1: ",") _ key }
    Quit out
}

/// The wards (a comma list of letters), a patient and enc-1 at Ward A for visit V1001.
Method Seed(wards As %String)
{
    Set seed = []
    For i = 1:1:$LENGTH(wards, ",") {
        Set ward = $PIECE(wards, ",", i)
        Do seed.%Push({"resourceType": "Location", "id": ("ward-" _ ward), "identifier": [{"system": "urn:shutter:ward", "value": ("WARD-" _ $ZCONVERT(ward, "U"))}], "status": "active", "name": ("Ward " _ $ZCONVERT(ward, "U"))})
    }
    Do seed.%Push({"resourceType": "Patient", "id": "demo-p1", "identifier": [{"system": "urn:shutter:demo:mrn", "value": "MRN-UT1"}], "active": true})
    Do seed.%Push({"resourceType": "Encounter", "id": "enc-1", "status": "in-progress", "identifier": [{"system": (..#SYS), "value": "V1001"}], "class": {"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IMP"}, "subject": {"reference": "Patient/demo-p1"}, "location": [{"location": {"reference": "Location/ward-a"}, "status": "active", "period": {"start": "2026-11-07T09:00:00Z"}}]})
    Set out = $CLASSMETHOD(..#SERVICE, "Seed", seed)
    Do $$$AssertEquals(out.%Get(out.%Size() - 1).status, 201, "the seed is written")
}

/// A saved case of this class's receiver: a transfer for visit V1001, its update sent and waiting to be verified.
Method NewCase() As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-FHIRVF-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.FHIRVerify)
    Set case.Event = "transfer", case.FailureKind = "delivery_failed", case.FailureText = "made up", case.EncounterId = "V1001"
    Set case.PatientId = "MRN-UT1", case.PatientIdAuthority = "HOSP", case.Receiver = ..#RECEIVER, case.State = "verifying", case.Mode = "rules"
    Set case.OperationKey = "PAS^HOSP^MRN-UT1^V1001^transfer^" _ case.CaseId, case.Disposition = "resend"
    Set case.EventTime = "2026-11-14T10:30:00Z"
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Do $$$AssertStatusOK(case.%Save(), "the case is saved")
    Set i%Made(case.%Id()) = ""
    Quit case
}

/// Puts this class's receiver into the stored profile (kept once per test, to be put back), its map holding the
/// wards given.
Method ChangeEntry(wards As %String)
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..ProfileChanged {
        Set ..HadProfileRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: ""), ..ProfileChanged = 1
    }
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    Set map = []
    For i = 1:1:$LENGTH(wards, ",") {
        Set ward = $PIECE(wards, ",", i), code = "WARD-" _ $ZCONVERT(ward, "U")
        Do map.%Push({"ward": (code), "location": ("Location/ward-" _ ward), "identifier": {"system": "urn:shutter:ward", "value": (code)}})
    }
    Set entry = {"name": (..#RECEIVER), "system": "the ward system (FHIR R4)", "category": "current_state", "tier": 3, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "fhir": {"base": (..#BASE), "recovery_enabled": true, "encounter_identifier": {"system": (..#SYS)}, "patient_identifier": {"system": "urn:shutter:demo:mrn", "hl7_authority": "HOSP"}, "marker": {"system": "urn:shutter:recovery"}, "location_map": (map)}}
    // Every other entry stays as it is; an earlier copy of this one is replaced
    Set kept = [], list = p.%Get("receivers")
    If $ISOBJECT(list) {
        Set it = list.%GetIterator()
        While it.%GetNext(.i, .r) { Do:'($ISOBJECT(r)&&(r.%Get("name")=..#RECEIVER)) kept.%Push(r) }
    }
    Do kept.%Push(entry)
    Do p.%Set("receivers", kept)
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Name = "current", row.Version = version
    Set row.Json = p.%ToJSON()
    Do $$$AssertStatusOK(row.%Save(), "the site profile holds the test's receiver")
}

Method RestoreProfile()
{
    Quit:'..ProfileChanged
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..HadProfileRow {
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    } ElseIf $ISOBJECT(row) {
        Set row.Json = ..SavedProfile
        Do row.%Save()
    }
    Set ..ProfileChanged = 0
}

}
