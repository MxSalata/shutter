/// FHIR Out's write (Shutter.Operation.FHIRExecute): at most one version-aware update for one approval. The operation
/// runs in process with the test FHIR server as its adapter (Shutter.Test.FakeFhir), so every request it makes is in
/// that adapter's log, and a canned answer stands for what a gateway or a failing receiver would say. Each test puts
/// back the profile and the control row as it found them, purges the cases it saved and removes the permits it made.
Class Shutter.Test.FHIRExecute Extends %UnitTest.TestCase
{

Parameter SERVICE = "FHIRFacade.Service";

Parameter RECEIVER = "UT FHIR Execute Out";

Parameter BASE = "/ut-fhir-out/r4";

Parameter SYS = "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49";

Parameter VISIT = "UTFX9001";

Parameter FHIRJSON = "application/fhir+json; charset=UTF-8";

/// The one address the operation asks for, as the adapter logs it.
Parameter ENC = "Encounter/enc-1";

Parameter OUTCOME = "{""resourceType"":""OperationOutcome"",""issue"":[{""severity"":""error"",""code"":""invalid"",""diagnostics"":""the receiver's own words""}]}";

Property Made As %String [ MultiDimensional ];

Property SavedProfile As %String(MAXLEN = "");

Property ProfileChanged As %Boolean [ InitialExpression = 0 ];

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

/// The control row's stop, and the newest permit, before the test.
Property SavedControl As %String(MAXLEN = "");

Property PermitsFrom As %Integer;

/// For TestTheStepsInTheirOrder, where the test itself is the operation's adapter: the adapter that answers, the
/// approval whose fence row is watched, and what was stored at the moment of each request.
Property Inner As Shutter.Test.FakeFhir;

Property Watched As %String;

Property Moments As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
    If ..Loaded() Do $CLASSMETHOD(..#SERVICE, "Reset")
    Do ##class(Shutter.Util.RecoveryControl).Ensure()
    Set c = ##class(Shutter.Util.RecoveryControl).Control()
    Set ..SavedControl = $LISTBUILD(c.StopLatched, c.StoppedAt, c.StoppedBy, c.StopReason)
    Set c.StopLatched = 0, c.StoppedAt = "", c.StoppedBy = "", c.StopReason = ""
    Do c.%Save()
    Set last = ""
    &sql(SELECT MAX(ID) INTO :last FROM Shutter_Store.DispatchPermit)
    Set ..PermitsFrom = +$GET(last)
    Quit $$$OK
}

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
    Set from = ..PermitsFrom
    &sql(DELETE FROM Shutter_Store.DispatchPermit WHERE ID > :from)
    Set c = ##class(Shutter.Util.RecoveryControl).Control()
    Set c.StopLatched = $LIST(..SavedControl, 1), c.StoppedAt = $LIST(..SavedControl, 2), c.StoppedBy = $LIST(..SavedControl, 3), c.StopReason = $LIST(..SavedControl, 4)
    Do c.%Save()
    Do ..RestoreProfile()
    Quit $$$OK
}

/// The approved update reaches the receiver once, and the answer, the fence row and the permit all say applied.
Method TestApplied()
{
    Quit:'..Ready()
    Set request = ..Fixture(.case, .binding)
    Set op = ..Op(.http)
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response), "applied|200|1|", "the update is applied")
    Do $$$AssertEquals(response.ResponseEtag, "W/""2""", "the answer's ETag names the new version")
    Do $$$AssertEquals($PIECE(response.ResponseLocation, "/r4/", 2), "Encounter/enc-1/_history/2", "and its Location that version")
    Do $$$AssertEquals(response.Error, "", "an applied update carries no error")
    Do $$$AssertEquals(..Log(http), "GET " _ ..#ENC _ " | PUT " _ ..#ENC, "its own read, then one PUT, and nothing else")
    // The fence row: sent, with the answer
    Set fence = ##class(Shutter.Store.FHIRAttempt).ForApproval(request.ApprovalId)
    Do $$$AssertEquals(fence.State _ "|" _ fence.Outcome _ "|" _ fence.HttpStatus _ "|" _ fence.ResponseEtag, "sent|applied|200|W/""2""", "the fence row holds the answer")
    Do $$$AssertTrue((fence.SentAt '= "") && (fence.AnsweredAt '= ""), "with the time it was sent and answered")
    Do $$$AssertEquals(fence.BindingId _ "|" _ fence.PlanId _ "|" _ fence.ExpectedEtag, binding.%Id() _ "|" _ binding.PlanId _ "|W/""1""", "and names the binding, the plan and the ETag")
    // The receiver: version 2, the patient on Ward B, the marker on that version
    Set now = ..J(..ServerRead(.etag))
    Do $$$AssertEquals(etag _ " " _ now.meta.versionId, "W/""2"" 2", "the receiver is at version 2")
    Do $$$AssertEquals(now.location.%Get(1).location.reference _ " " _ now.location.%Get(0).period.end, "Location/ward-b 2026-11-14T10:30:00Z", "the new ward is open and the old one closed")
    Do $$$AssertEquals(now.meta.tag.%Get(0).code, binding.OperationId, "and the version carries the update's marker")
    // The permit: one, answered
    Set permits = ..Permits()
    Do $$$AssertEquals(permits.%Size(), 1, "one permit was taken")
    Set p = ##class(Shutter.Store.DispatchPermit).%OpenId(permits.%Get(0).id)
    Do $$$AssertEquals(p.State _ "|" _ p.Outcome _ "|" _ p.HttpStatus _ "|" _ p.ActionKind, "answered|applied|200|recovery", "and it is finished as applied")
    Do $$$AssertEquals(p.CaseId _ "|" _ p.Receiver _ "|" _ p.OperationKey _ "|" _ p.BodyDigest, case.CaseId _ "|" _ ..#RECEIVER _ "|" _ case.OperationKey _ "|sha256:" _ binding.ApprovedBodyDigest, "it names the case, the receiver, the plan's key and the body's digest")
    Do ..NoneAdmitted()
}

/// Every line of the classifier, through the operation where the adapter can give the answer and by the method
/// itself where it cannot.
Method TestTheClassifierTable()
{
    Quit:'..Ready()
    Set encounter = "{""resourceType"":""Encounter"",""id"":""enc-1"",""meta"":{""versionId"":""2""}}"
    // canned PUT answer (status, content type, ETag, Location, body), then outcome|status|sent|reason
    Set rows = 0
    Set rows($INCREMENT(rows)) = $LISTBUILD("412 with an OperationOutcome", $LISTBUILD(412, ..#FHIRJSON, "", "", ..#OUTCOME), "version_conflict|412|1|")
    Set rows($INCREMENT(rows)) = $LISTBUILD("409", $LISTBUILD(409, "text/plain", "", "", "Conflict"), "version_conflict|409|1|")
    Set rows($INCREMENT(rows)) = $LISTBUILD("405 with an OperationOutcome", $LISTBUILD(405, ..#FHIRJSON, "", "", ..#OUTCOME), "refused|405|1|invalid_if_match")
    Set rows($INCREMENT(rows)) = $LISTBUILD("a 422 OperationOutcome", $LISTBUILD(422, ..#FHIRJSON, "", "", ..#OUTCOME), "refused|422|1|")
    Set rows($INCREMENT(rows)) = $LISTBUILD("a plain 404", $LISTBUILD(404, "text/html", "", "", "Not Found"), "uncertain|404|1|credentials_or_proxy")
    Set rows($INCREMENT(rows)) = $LISTBUILD("a 404 OperationOutcome", $LISTBUILD(404, ..#FHIRJSON, "", "", ..#OUTCOME), "refused|404|1|")
    Set rows($INCREMENT(rows)) = $LISTBUILD("a page behind a 200", $LISTBUILD(200, "text/html; charset=utf-8", "", "", "<html><body>Sign in</body></html>"), "uncertain|200|1|")
    Set rows($INCREMENT(rows)) = $LISTBUILD("a 200 with an ETag and no body", $LISTBUILD(200, "text/html", "W/""2""", "", ""), "applied|200|1|")
    Set rows($INCREMENT(rows)) = $LISTBUILD("a 201 with an ETag", $LISTBUILD(201, ..#FHIRJSON, "W/""1""", "", ""), "applied|201|1|update_created")
    Set rows($INCREMENT(rows)) = $LISTBUILD("a 201 without an ETag", $LISTBUILD(201, ..#FHIRJSON, "", "", ""), "uncertain|201|1|update_created")
    Set rows($INCREMENT(rows)) = $LISTBUILD("204", $LISTBUILD(204, "", "W/""2""", "", ""), "uncertain|204|1|")
    Set rows($INCREMENT(rows)) = $LISTBUILD("302", $LISTBUILD(302, "text/html", "", "https://sso.example/login", ""), "uncertain|302|1|")
    Set rows($INCREMENT(rows)) = $LISTBUILD("401", $LISTBUILD(401, "text/plain", "", "", "Unauthorized"), "refused|401|1|credentials")
    Set rows($INCREMENT(rows)) = $LISTBUILD("500", $LISTBUILD(500, ..#FHIRJSON, "", "", ..#OUTCOME), "uncertain|500|1|")
    Set rows($INCREMENT(rows)) = $LISTBUILD("a connection that never opened", $LISTBUILD(0), "error|0|0|")
    For i = 1:1:rows {
        Set what = $LIST(rows(i), 1), want = $LIST(rows(i), 3)
        Do $CLASSMETHOD(..#SERVICE, "Reset")
        Do ..Seed(0)
        Set request = ..Fixture()
        Set op = ..Op(.http)
        Set http.Canned("PUT", ..#ENC) = $LIST(rows(i), 2)
        Set response = ..Run(op, request)
        Do $$$AssertEquals(..Answer(response), want, what)
        Do $$$AssertEquals(..Verbs(http), "GET PUT", what _ ": one read and one PUT, never a second")
        Set fence = ##class(Shutter.Store.FHIRAttempt).ForApproval(request.ApprovalId)
        Do $$$AssertEquals(fence.State _ "|" _ fence.Outcome _ "|" _ fence.HttpStatus, "sent|" _ $PIECE(want, "|", 1, 2), what _ ": the fence row is sent and holds the answer")
        Set p = ..Permits().%Get(0)
        Do $$$AssertEquals(p.state, $SELECT($PIECE(want, "|", 1) = "uncertain": "uncertain", 1: "answered"), what _ ": the permit is finished")
    }
    Do $$$AssertEquals(response.Diagnostics [ "6059", 1, "a connection that never opened is known by its status code (" _ response.Diagnostics _ ")")
    // The receiver's words come with a refusal
    Do $$$AssertEquals(..Classified($$$OK, 422, "", "", ..#FHIRJSON, ..#OUTCOME, .diagnostics), "refused|", "a 422 OperationOutcome")
    Do $$$AssertEquals(diagnostics, "the receiver's own words", "carries the first issue's diagnostics")
    Do ..Classified($$$OK, 422, "", "", ..#FHIRJSON, $REPLACE(..#OUTCOME, "the receiver's own words", $TRANSLATE($JUSTIFY("", 400), " ", "x")), .diagnostics)
    Do $$$AssertEquals($LENGTH(diagnostics), 300, "cut to 300 characters")

    // The lines the adapter cannot give, by the method
    Set timeout = $SYSTEM.Status.Error(5001, "the response timed out")
    Set table = 0
    Set table($INCREMENT(table)) = $LISTBUILD("no answer", timeout, 0, "", "", "", "", "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("no answer and no error", $$$OK, 0, "", "", "", "", "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("a refused connection, by its words", $SYSTEM.Status.Error(5001, "Connection refused"), 0, "", "", "", "", "error|")
    Set table($INCREMENT(table)) = $LISTBUILD("200 with this Encounter at the ETag's version", $$$OK, 200, "W/""2""", "/b/Encounter/enc-1/_history/2", ..#FHIRJSON, encounter, "applied|")
    Set table($INCREMENT(table)) = $LISTBUILD("200 with the Encounter at another version", $$$OK, 200, "W/""3""", "", ..#FHIRJSON, encounter, "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("200 with another Encounter", $$$OK, 200, "W/""2""", "", ..#FHIRJSON, $REPLACE(encounter, "enc-1", "enc-2"), "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("200 with an OperationOutcome", $$$OK, 200, "W/""2""", "", ..#FHIRJSON, ..#OUTCOME, "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("200 whose Location names another version", $$$OK, 200, "W/""2""", "/b/Encounter/enc-1/_history/3", "", "", "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("200 with a strong ETag", $$$OK, 200, """2""", "", "", "", "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("200 with no ETag", $$$OK, 200, "", "", ..#FHIRJSON, encounter, "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("202", $$$OK, 202, "W/""2""", "", "", "", "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("304", $$$OK, 304, "W/""1""", "", "", "", "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("405 with a page", $$$OK, 405, "", "", "text/html", "<html></html>", "refused|")
    Set table($INCREMENT(table)) = $LISTBUILD("400 with an OperationOutcome", $$$OK, 400, "", "", ..#FHIRJSON, ..#OUTCOME, "refused|")
    Set table($INCREMENT(table)) = $LISTBUILD("400 with a page", $$$OK, 400, "", "", "text/html", "Bad Request", "refused|")
    Set table($INCREMENT(table)) = $LISTBUILD("410 with an OperationOutcome", $$$OK, 410, "", "", ..#FHIRJSON, ..#OUTCOME, "refused|")
    Set table($INCREMENT(table)) = $LISTBUILD("404 with an OperationOutcome under another media type", $$$OK, 404, "", "", "text/html", ..#OUTCOME, "uncertain|credentials_or_proxy")
    Set table($INCREMENT(table)) = $LISTBUILD("403", $$$OK, 403, "", "", ..#FHIRJSON, ..#OUTCOME, "refused|credentials")
    Set table($INCREMENT(table)) = $LISTBUILD("428", $$$OK, 428, "", "", "", "", "refused|")
    Set table($INCREMENT(table)) = $LISTBUILD("503", $$$OK, 503, "", "", "", "", "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("100", $$$OK, 100, "", "", "", "", "uncertain|")
    Set table($INCREMENT(table)) = $LISTBUILD("999", $$$OK, 999, "", "", "", "", "uncertain|")
    For i = 1:1:table {
        Set r = table(i)
        Do $$$AssertEquals(..Classified($LIST(r, 2), $LIST(r, 3), $LIST(r, 4), $LIST(r, 5), $LIST(r, 6), $LIST(r, 7)), $LIST(r, 8), $LIST(r, 1))
    }
    Do ..NoneAdmitted()
}

/// Every PUT carries If-Match with the binding's ETag byte for byte and the body with the approved digest.
Method TestIfMatchAndTheBodysDigestOnEveryPut()
{
    Quit:'..Ready()
    Set puts = 0
    For canned = "", $LISTBUILD(412, ..#FHIRJSON, "", "", ..#OUTCOME), $LISTBUILD(500, "text/plain", "", "", "boom"), $LISTBUILD(0) {
        Do $CLASSMETHOD(..#SERVICE, "Reset")
        Do ..Seed(0)
        Set request = ..Fixture(.case, .binding)
        Set op = ..Op(.http)
        Set:canned'="" http.Canned("PUT", ..#ENC) = canned
        Do ..Run(op, request)
        For i = 1:1:+$GET(http.Requests) {
            Set sent = http.Requests(i)
            Continue:$LIST(sent, 1)'="PUT"
            Set puts = puts + 1
            Do $$$AssertEquals($LIST(sent, 2) _ " " _ $LIST(sent, 3), ..#ENC _ " " _ binding.ExpectedEtag, "PUT " _ puts _ ": the Encounter's own address, If-Match on the ETag that was read")
            Do $$$AssertEquals(##class(Shutter.FHIR.Plan).BodyDigest($LIST(sent, 4)), binding.ApprovedBodyDigest, "PUT " _ puts _ ": the body has the approved digest")
            Do $$$AssertEquals($LIST(sent, 4), binding.ApprovedBody, "PUT " _ puts _ ": and is the approved body")
        }
    }
    Do $$$AssertEquals(puts, 4, "four updates, one PUT each")
    // The request as the adapter is handed it
    Set http = ##class(Shutter.Operation.FHIRExecute).Request(binding)
    Do $$$AssertEquals(http.GetHeader("If-Match") _ "|" _ http.GetHeader("Accept") _ "|" _ http.GetHeader("Prefer") _ "|" _ http.ContentType, "W/""1""|application/fhir+json|return=minimal|application/fhir+json", "its headers")
    Do $$$AssertEquals(http.ReadRawMode _ " " _ http.WriteRawMode, "1 1", "read and written raw")
    // An ETag is sent as it was read, whatever it holds
    Set binding.ExpectedEtag = "W/""a b;c=d, e"""
    Do $$$AssertEquals(##class(Shutter.Operation.FHIRExecute).Request(binding).GetHeader("If-Match"), "W/""a b;c=d, e""", "an ETag goes byte for byte")
    Do binding.%Reload()
    Do ..NoneAdmitted()
}

/// A fence row that is sent and has no answer: a second request sends nothing and is answered uncertain, never
/// refused, whatever has lapsed since.
Method TestASecondRequestSendsNothingAndAnswersUncertain()
{
    Quit:'..Ready()
    Set request = ..Fixture(.case, .binding, .approval, .decision)
    // A job that marked the row sent and was lost before any answer
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, binding, .fence, .created), "the fence row is opened")
    Do $$$AssertTrue(fence.MarkSent(), "and marked sent")
    Set op = ..Op(.http)
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response), "uncertain|0|1|fhir_already_sent", "the second request is answered as a write that may have landed")
    Do $$$AssertEquals(+$GET(http.Requests), 0, "and sends nothing, not even a read")
    Do $$$AssertEquals(..Permits().%Size(), 0, "it takes no permit")
    // The decision is stale, the approval revoked and the plan no longer current: still not "refused"
    Set decision.At = ##class(Shutter.Util.Time).FromNow(-600)
    Do $$$AssertStatusOK(decision.%Save(), "the decision is made old")
    Do $$$AssertStatusOK(approval.Revoke("unit test"), "the approval is revoked")
    Do ..NewCurrentPlan(case)
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response), "uncertain|0|1|fhir_already_sent", "after everything lapsed the answer is the same")
    Do $$$AssertEquals(+$GET(http.Requests), 0, "and nothing is sent")
    Do ..ServerRead(.etag)
    Do $$$AssertEquals(etag, "W/""1""", "the receiver is as it was")
    Do ..NoneAdmitted()
}

/// A fence row that is sent and answered gives its recorded outcome, status, ETag and Location again.
Method TestAnAnsweredFenceAnswersItsRecordAgain()
{
    Quit:'..Ready()
    Set request = ..Fixture()
    Set op = ..Op(.http)
    Set first = ..Run(op, request)
    Do $$$AssertEquals(..Answer(first), "applied|200|1|", "the first request is applied")
    Set op = ..Op(.http)
    Set second = ..Run(op, request)
    Do $$$AssertEquals(..Answer(second), "applied|200|1|fhir_already_sent", "the second gets the record")
    Do $$$AssertEquals(second.ResponseEtag _ " " _ second.ResponseLocation, first.ResponseEtag _ " " _ first.ResponseLocation, "with the ETag and the Location that were recorded")
    Do $$$AssertEquals(+$GET(http.Requests), 0, "and sends nothing")
    Do ..ServerRead(.etag)
    Do $$$AssertEquals(etag, "W/""2""", "the receiver was written once")
    Do $$$AssertEquals(..Permits().%Size(), 1, "one permit in all")
    // A recorded conflict, an uncertain answer and a connection that never opened are given again as they were
    For row = $LISTBUILD($LISTBUILD(412, ..#FHIRJSON, "", "", ..#OUTCOME), "version_conflict|412|1|"), $LISTBUILD($LISTBUILD(502, "text/html", "", "", "Bad Gateway"), "uncertain|502|1|"), $LISTBUILD($LISTBUILD(0), "error|0|0|") {
        Do $CLASSMETHOD(..#SERVICE, "Reset")
        Do ..Seed(0)
        Set request = ..Fixture()
        Set op = ..Op(.http)
        Set http.Canned("PUT", ..#ENC) = $LIST(row, 1)
        Set first = ..Run(op, request)
        Do $$$AssertEquals(..Answer(first), $LIST(row, 2), "first: " _ $LIST(row, 2))
        Set op = ..Op(.http)
        Set second = ..Run(op, request)
        Do $$$AssertEquals(..Answer(second), $LIST(row, 2) _ "fhir_already_sent", "again: " _ $LIST(row, 2))
        Do $$$AssertEquals(second.Diagnostics, first.Diagnostics, "with the diagnostics that were recorded")
        Do $$$AssertEquals(+$GET(http.Requests), 0, "and nothing is sent")
    }
    Do ..NoneAdmitted()
}

/// Step one: what the request names is opened again, and each thing that no longer holds refuses with no request,
/// no fence row and no permit.
Method TestStepOneRefusals()
{
    Quit:'..Ready()
    // An expired approval
    Set request = ..Fixture(.case, .binding, .approval)
    Set approval.ExpiresAt = ##class(Shutter.Util.Time).FromNow(-5)
    Do $$$AssertStatusOK(approval.%Save(), "the approval is made to expire")
    Do ..Refused(request, "fhir_approval_void", "an expired approval")
    // A revoked approval
    Set request = ..Fixture(.case, .binding, .approval)
    Do $$$AssertStatusOK(approval.Revoke("unit test"), "the approval is revoked")
    Do ..Refused(request, "fhir_approval_void", "a revoked approval")
    // A policy approver
    Set request = ..Fixture(.case, .binding, .approval)
    Set approval.Approver = "policy"
    Do $$$AssertStatusOK(approval.%Save(), "the approver is the policy")
    Do ..Refused(request, "fhir_approval_not_personal", "a policy approver")
    // An incident approval
    Set request = ..Fixture(.case, .binding, .approval)
    Do $$$AssertStatusOK(approval.BindIncident("sha256:ut-incident-plan", "E01", "resend"), "the approval is an incident's")
    Do ..Refused(request, "fhir_approval_not_personal", "an incident approval")
    // Another case's approval
    Set request = ..Fixture(.case, .binding)
    Set other = ..Fixture(.otherCase, .otherBinding, .otherApproval)
    Set approvalId = request.ApprovalId
    Set request.ApprovalId = other.ApprovalId
    Do ..Refused(request, "fhir_binding_missing", "another case's approval", approvalId)
    // Another case's binding
    Set request.ApprovalId = approvalId, request.BindingId = other.BindingId
    Do ..Refused(request, "fhir_binding_missing", "another case's binding")
    // No binding, no case
    Set request.BindingId = ""
    Do ..Refused(request, "fhir_binding_missing", "no binding")
    Set request.BindingId = binding.%Id(), request.CaseId = "UT-NO-SUCH-CASE"
    Do ..Refused(request, "fhir_binding_missing", "a case that does not exist")
    // A plan that is no longer current
    Set request = ..Fixture(.case, .binding)
    Do ..NewCurrentPlan(case)
    Do ..Refused(request, "fhir_binding_missing", "a plan that is no longer current")
    // A stale dispatch decision, and one that is just young enough
    Set request = ..Fixture(.case, .binding, .approval, .decision)
    Set decision.At = ##class(Shutter.Util.Time).FromNow(-125)
    Do $$$AssertStatusOK(decision.%Save(), "the decision is made 125 seconds old")
    Do ..Refused(request, "fhir_dispatch_stale", "a stale dispatch decision")
    // A missing decision, a decision that blocked, the proposal's decision, another case's decision
    Set request = ..Fixture(.case, .binding, .approval, .decision)
    Set decisionId = request.DecisionId
    Set request.DecisionId = ""
    Do ..Refused(request, "fhir_dispatch_stale", "no dispatch decision")
    Set request.DecisionId = "999999999"
    Do ..Refused(request, "fhir_dispatch_stale", "a decision that does not exist")
    Set request.DecisionId = other.DecisionId
    Do ..Refused(request, "fhir_dispatch_stale", "another case's decision")
    Set request.DecisionId = decisionId, decision.Outcome = "block"
    Do $$$AssertStatusOK(decision.%Save(), "the decision is a block")
    Do ..Refused(request, "fhir_dispatch_stale", "a decision that blocked")
    Set decision.Outcome = "pass", decision.Stage = "proposal"
    Do $$$AssertStatusOK(decision.%Save(), "the decision is the proposal's")
    Do ..Refused(request, "fhir_dispatch_stale", "the proposal stage's decision")
    // A changed body
    Set request = ..Fixture(.case, .binding)
    Set binding.ApprovedBody = $REPLACE(binding.ApprovedBody, "Location/ward-b", "Location/ward-a")
    Do $$$AssertStatusOK(binding.%Save(), "the stored body is changed")
    Do ..Refused(request, "fhir_body_changed", "a changed body")
    // Recovery turned off in the receiver's entry, and a receiver that is no FHIR receiver
    Set request = ..Fixture()
    Do ..ChangeEntry({"recovery_enabled": false})
    Do ..Refused(request, "fhir_recovery_disabled", "fhir.recovery_enabled false")
    Do ..ChangeEntry("")
    Set request = ..Fixture(.case)
    Set case.Receiver = "Ward Out"
    Do $$$AssertStatusOK(case.%Save(), "the case is another receiver's")
    Do ..Refused(request, "fhir_recovery_disabled", "a receiver with no fhir block")
    Do $$$AssertEquals(..Permits().%Size(), 0, "no refusal took a permit")
    Do ..ServerRead(.etag)
    Do $$$AssertEquals(etag, "W/""1""", "the receiver is as it was")
}

/// Step five: this item's own read must give the ETag and the body the approval rests on, or nothing is sent.
Method TestItsOwnReadRefusesAnotherVersionOrBody()
{
    Quit:'..Ready()
    Set body = ..ServerRead(.etag, .type)
    Set rows = 0
    Set rows($INCREMENT(rows)) = $LISTBUILD("another version", $LISTBUILD(200, type, "W/""2""", "", body))
    Set rows($INCREMENT(rows)) = $LISTBUILD("another body under the same ETag", $LISTBUILD(200, type, etag, "", $REPLACE(body, "in-progress", "finished")))
    Set rows($INCREMENT(rows)) = $LISTBUILD("no ETag", $LISTBUILD(200, type, "", "", body))
    Set rows($INCREMENT(rows)) = $LISTBUILD("a page behind a 200", $LISTBUILD(200, "text/html", etag, "", "<html><body>Sign in</body></html>"))
    Set rows($INCREMENT(rows)) = $LISTBUILD("another Encounter", $LISTBUILD(200, type, etag, "", $REPLACE(body, """enc-1""", """enc-2""")))
    Set rows($INCREMENT(rows)) = $LISTBUILD("a plain 404", $LISTBUILD(404, "text/html", "", "", "Not Found"))
    Set rows($INCREMENT(rows)) = $LISTBUILD("the receiver's own 404", $LISTBUILD(404, ..#FHIRJSON, "", "", ..#OUTCOME))
    Set rows($INCREMENT(rows)) = $LISTBUILD("a 503", $LISTBUILD(503, "text/plain", "", "", "busy"))
    Set rows($INCREMENT(rows)) = $LISTBUILD("no answer", $LISTBUILD(0))
    For i = 1:1:rows {
        Set what = $LIST(rows(i), 1)
        Set request = ..Fixture()
        Set op = ..Op(.http)
        Set http.Canned("GET", ..#ENC) = $LIST(rows(i), 2)
        Set response = ..Run(op, request)
        Do $$$AssertEquals(..Answer(response), "refused|0|0|fhir_endpoint_differs", what)
        Do $$$AssertEquals(..Verbs(http), "GET", what _ ": one read and no PUT")
        Do $$$AssertEquals(##class(Shutter.Store.FHIRAttempt).ForApproval(request.ApprovalId).State, "unsent", what _ ": the fence row stays unsent")
    }
    // The receiver itself moved on after the approval
    Set request = ..Fixture()
    Do ..ServerWrite($REPLACE(body, "in-progress", "onleave"), etag)
    Set op = ..Op(.http)
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response), "refused|0|0|fhir_endpoint_differs", "a receiver that moved on")
    Do $$$AssertTrue(response.Error [ "ETag W/""2""", "the answer names the version it found (" _ response.Error _ ")")
    Do $$$AssertEquals(..Verbs(http), "GET", "one read and no PUT")
    Do $$$AssertEquals(..Permits().%Size() _ " " _ ..Permits("answered").%Size(), (rows + 1) _ " " _ (rows + 1), "each refusal finished its permit as answered")
    Do ..NoneAdmitted()
}

/// Shadow mode and the stop refuse at the admission: nothing is read or sent, and the fence row stays unsent.
Method TestShadowAndTheStopSendNothing()
{
    Quit:'..Ready()
    Set request = ..Fixture()
    Do ..ChangeEntry("", "shadow")
    Set op = ..Op(.http)
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response), "refused|0|0|recovery_shadow", "shadow mode refuses")
    Do $$$AssertTrue(response.Error [ "Shadow mode", "in the control's own words (" _ response.Error _ ")")
    Do $$$AssertEquals(+$GET(http.Requests), 0, "and nothing is read or sent")
    Do $$$AssertEquals(##class(Shutter.Store.FHIRAttempt).ForApproval(request.ApprovalId).State, "unsent", "the fence row is there, unsent")
    // The profile with no recovery section at all is shadow too
    Do ..ChangeEntry("", "")
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response) _ " " _ +$GET(http.Requests), "refused|0|0|recovery_shadow 0", "no recovery mode in the profile is shadow")
    // The stop
    Do ..ChangeEntry("", "enabled")
    Set c = ##class(Shutter.Util.RecoveryControl).Control()
    Set c.StopLatched = 1, c.StoppedAt = ##class(Shutter.Util.Time).NowUTC(), c.StoppedBy = "ut.approver", c.StopReason = "unit test"
    Do $$$AssertStatusOK(c.%Save(), "recovery is stopped")
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response), "refused|0|0|recovery_stopped", "the stop refuses")
    Do $$$AssertEquals(+$GET(http.Requests), 0, "and nothing is read or sent")
    Do $$$AssertEquals(..Permits().%Size(), 0, "neither refusal took a permit")
    // With the stop gone the same request goes: the refusals spent nothing
    Set c.StopLatched = 0, c.StoppedAt = "", c.StoppedBy = "", c.StopReason = ""
    Do $$$AssertStatusOK(c.%Save(), "the stop is gone")
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response) _ " " _ ..Verbs(http), "applied|200|1| GET PUT", "the same request is then applied")
    Do ..NoneAdmitted()
}

/// Every way out after the admission finishes the permit, and lets go of its lock.
Method TestEveryExitLeavesThePermitFinished()
{
    Quit:'..Ready()
    Set body = ..ServerRead(.etag, .type)
    // what, canned GET, canned PUT, the answer, the permit's state|outcome|status
    Set rows = 0
    Set rows($INCREMENT(rows)) = $LISTBUILD("its own read differs", $LISTBUILD(200, type, "W/""9""", "", body), "", "refused|0|0|fhir_endpoint_differs", "answered|refused|0")
    Set rows($INCREMENT(rows)) = $LISTBUILD("its own read gets no answer", $LISTBUILD(0), "", "refused|0|0|fhir_endpoint_differs", "answered|refused|0")
    Set rows($INCREMENT(rows)) = $LISTBUILD("a conflict", "", $LISTBUILD(412, ..#FHIRJSON, "", "", ..#OUTCOME), "version_conflict|412|1|", "answered|version_conflict|412")
    Set rows($INCREMENT(rows)) = $LISTBUILD("a refusal", "", $LISTBUILD(422, ..#FHIRJSON, "", "", ..#OUTCOME), "refused|422|1|", "answered|refused|422")
    Set rows($INCREMENT(rows)) = $LISTBUILD("an answer nobody named", "", $LISTBUILD(500, "text/plain", "", "", "boom"), "uncertain|500|1|", "uncertain|uncertain|500")
    Set rows($INCREMENT(rows)) = $LISTBUILD("a connection that never opened", "", $LISTBUILD(0), "error|0|0|", "answered|error|0")
    Set rows($INCREMENT(rows)) = $LISTBUILD("applied", "", "", "applied|200|1|", "answered|applied|200")
    For i = 1:1:rows {
        Set what = $LIST(rows(i), 1)
        Set request = ..Fixture()
        Set op = ..Op(.http)
        Set:$LIST(rows(i), 2)'="" http.Canned("GET", ..#ENC) = $LIST(rows(i), 2)
        Set:$LIST(rows(i), 3)'="" http.Canned("PUT", ..#ENC) = $LIST(rows(i), 3)
        Set response = ..Run(op, request)
        Do $$$AssertEquals(..Answer(response), $LIST(rows(i), 4), what)
        Set permits = ..Permits()
        Do $$$AssertEquals(permits.%Size(), i, what _ ": one permit more")
        Set p = ##class(Shutter.Store.DispatchPermit).%OpenId(permits.%Get(0).id)
        Do $$$AssertEquals(p.State _ "|" _ p.Outcome _ "|" _ p.HttpStatus, $LIST(rows(i), 5), what _ ": the permit is finished")
        Do $$$AssertTrue(p.EndedAt '= "", what _ ": with the time it ended")
        Do $$$AssertEquals($DATA(^||Shutter.RecoveryPermit(p.Token)), 0, what _ ": and this job holds its mark no longer")
        Do ..NoneAdmitted()
    }
    // An adapter that fails outright: the read gets no answer, and the permit is still finished
    Set request = ..Fixture()
    Set op = ..Op(.http)
    Set op.Adapter = ""
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response), "refused|0|0|fhir_endpoint_differs", "an adapter that fails")
    Do $$$AssertEquals(..Permits().%Size() _ " " _ ..Permits("admitted").%Size(), (rows + 1) _ " 0", "and its permit is finished too")
}

/// A body with characters above ASCII leaves as its UTF-8 bytes, encoded once.
Method TestABodyAboveAsciiGoesAsUtf8Once()
{
    Quit:'..Ready()
    Set name = "Zo" _ $CHAR(235) _ " " _ $CHAR(321) _ "uk " _ $CHAR(26481)
    // The Encounter at the receiver carries the name, so this item's own read has to decode it as the approval did
    Do $CLASSMETHOD(..#SERVICE, "Reset")
    Do ..Seed(0, name)
    Set request = ..Fixture(.case, .binding, , , "transferred with " _ name)
    Do $$$AssertTrue((binding.BaseBody [ name) && (binding.ApprovedBody [ ("transferred with " _ name)), "the read and the approved body both carry the name")
    // The request as the adapter is handed it: the body's UTF-8 bytes, once
    Set http = ##class(Shutter.Operation.FHIRExecute).Request(binding)
    Do http.EntityBody.Rewind()
    Set bytes = ""
    While 'http.EntityBody.AtEnd {
        Set bytes = bytes _ http.EntityBody.Read(32000)
    }
    Do $$$AssertEquals($ZISWIDE(bytes), 0, "the entity body is bytes")
    Do $$$AssertTrue(bytes = $ZCONVERT(binding.ApprovedBody, "O", "UTF8"), "the UTF-8 bytes of the approved body")
    Do $$$AssertTrue($ZCONVERT(bytes, "I", "UTF8") = binding.ApprovedBody, "which read back once are the approved body")
    Do $$$AssertEquals($LENGTH(bytes) - $LENGTH(binding.ApprovedBody), 2 * (1 + 1 + 2), "two characters of two bytes and one of three, twice in the body")
    Do $$$AssertEquals(http.WriteRawMode, 1, "and they are written raw, so nothing translates them again")
    // Through the operation
    Set op = ..Op(.fake)
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response), "applied|200|1|", "the update is applied")
    Set sent = fake.Requests(2)
    Do $$$AssertTrue($LIST(sent, 4) = binding.ApprovedBody, "the receiver was handed the approved body, character for character")
    Do $$$AssertEquals(##class(Shutter.FHIR.Plan).BodyDigest($LIST(sent, 4)), binding.ApprovedBodyDigest, "with the approved digest")
    Set now = ..J(..ServerRead(.etag))
    Do $$$AssertTrue((etag = "W/""2""") && (now.reasonCode.%Get(0).text = name) && (now.reasonCode.%Get(1).text = ("transferred with " _ name)), "and holds it as it was written")
    Do ..NoneAdmitted()
}

/// The order is the promise: the fence row and the admission are there before this item's own read, the row is
/// still unsent at that read, and it is sent before the PUT leaves.
Method TestTheStepsInTheirOrder()
{
    Quit:'..Ready()
    Set request = ..Fixture()
    Set op = ..Op(.http)
    Set ..Inner = http, ..Watched = request.ApprovalId, ..Moments = ""
    // The test is the adapter: it notes what is stored, then lets the test FHIR server answer
    Set op.Adapter = $THIS
    Set response = ..Run(op, request)
    Set op.Adapter = http, ..Inner = ""
    Do $$$AssertEquals(..Answer(response), "applied|200|1|", "the update is applied")
    Do $$$AssertEquals(..Moments, "GET: fence unsent, permits admitted 1 | PUT: fence sent, permits admitted 1", "what was stored at each request")
    Do $$$AssertEquals(..Permits().%Size() _ " " _ ..Permits("answered").%Size(), "1 1", "and afterwards the one permit is finished")
    Do ..NoneAdmitted()
}

/// The connector's last line for further messages for the patient, read at the moment of the write: a message that
/// reached the engine after the plan refuses the update with nothing sent.
Method TestTheConnectorsLastLineSendsNothing()
{
    Quit:'..Ready()
    Do ..ChangeEntry("", "enabled", "stop")
    Set request = ..Fixture(.case)
    Set row = ##class(Shutter.Index.Message).%New()
    Set row.DocId = "UT-FHIRX-FURTHER", row.PatientId = "MRN-UTFX1", row.PatientIdAuthority = "HOSP", row.VisitNumber = "ENC-UTFX-NEW", row.Event = "admit", row.MessageType = "ADT_A01"
    Set row.ControlId = "UT-FHIRX-NEW", row.EventTime = "2026-11-14T11:00:00Z", row.TimeCreated = "2099-01-01 00:00:00"
    Do $$$AssertStatusOK(row.%Save(), "a later message for the patient is in the index")
    Try {
        Set op = ..Op(.http)
        Set response = ..Run(op, request)
        Do $$$AssertEquals(..Answer(response) _ " " _ +$GET(http.Requests), "refused|0|0|further_movement 0", "the update is refused and nothing is read or sent")
        Do $$$AssertTrue(response.Error [ "ENC-UTFX-NEW", "the answer names the other visit (" _ response.Error _ ")")
        Do $$$AssertTrue('$ISOBJECT(##class(Shutter.Store.FHIRAttempt).ForApproval(request.ApprovalId)), "no fence row is made")
    } Catch ex {
        Do $$$AssertTrue(0, "no error: " _ ex.DisplayString())
    }
    Do ##class(Shutter.Index.Message).%DeleteId(row.%Id())
    // With the message gone the same request goes
    Set op = ..Op(.http)
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response) _ " " _ ..Verbs(http), "applied|200|1| GET PUT", "without it the same request is applied")
    Do ..NoneAdmitted()
}

// ---- helpers ----

/// The test as the operation's adapter (TestTheStepsInTheirOrder): notes the watched approval's fence row and the
/// permits still admitted at the moment of the request, then hands the request to the adapter that answers.
Method SendFormDataArray(Output pHttpResponse As %Net.HttpResponse, pOp As %String, pHttpRequest As %Net.HttpRequest, pFormVarNames As %String = "", ByRef pData, pURL As %String = "") As %Status
{
    Set state = "none"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State FROM Shutter_Store.FHIRAttempt WHERE ApprovalId = ?", ..Watched)
    If rs.%Next() Set state = rs.%Get("State")
    Set ..Moments = ..Moments _ $SELECT(..Moments = "": "", 1: " | ") _ pOp _ ": fence " _ state _ ", permits admitted " _ ..Permits("admitted").%Size()
    Quit ..Inner.SendFormDataArray(.pHttpResponse, pOp, pHttpRequest, pFormVarNames, .pData, pURL)
}

Method Loaded() As %Boolean
{
    Quit ##class(%Dictionary.CompiledClass).%ExistsId(..#SERVICE)
}

/// Whether the test can run: the test FHIR server is loaded. Seeds it and puts this class's receiver in the profile,
/// with recovery enabled.
Method Ready() As %Boolean
{
    If '..Loaded() {
        Do $$$AssertSkipped("FHIRFacade is not loaded on this instance")
        Quit 0
    }
    Do ..Seed()
    Do ..ChangeEntry("")
    Quit 1
}

/// Two wards, a patient and enc-1 at Ward A for this class's visit; with <var>name</var> the Encounter carries it.
Method Seed(assert As %Boolean = 1, name As %String = "")
{
    Set seed = []
    Do seed.%Push({"resourceType": "Location", "id": "ward-a", "identifier": [{"system": "urn:shutter:ward", "value": "WARD-A"}], "status": "active", "name": "Ward A"})
    Do seed.%Push({"resourceType": "Location", "id": "ward-b", "identifier": [{"system": "urn:shutter:ward", "value": "WARD-B"}], "status": "active", "name": "Ward B"})
    Do seed.%Push({"resourceType": "Patient", "id": "demo-p1", "identifier": [{"system": "urn:shutter:demo:mrn", "value": "MRN-UTFX1"}], "active": true})
    Set enc = {"resourceType": "Encounter", "id": "enc-1", "status": "in-progress", "identifier": [{"system": (..#SYS), "value": (..#VISIT)}], "class": {"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IMP"}, "subject": {"reference": "Patient/demo-p1"}, "location": [{"location": {"reference": "Location/ward-a"}, "status": "active", "period": {"start": "2026-11-14T08:30:00Z"}}]}
    If name '= "" Set enc.reasonCode = [{"text": (name)}]
    Do seed.%Push(enc)
    Set out = $CLASSMETHOD(..#SERVICE, "Seed", seed)
    If assert Do $$$AssertEquals(out.%Get(3).status, 201, "the seed is written")
}

/// The operation with the test FHIR server as its adapter.
Method Op(Output http As Shutter.Test.FakeFhir) As Shutter.Operation.FHIRExecute
{
    Set op = ##class(Shutter.Operation.FHIRExecute).%New("FHIR Out (unit test)")
    Set http = ##class(Shutter.Test.FakeFhir).%New()
    Set http.Base = ..#BASE
    Set op.Adapter = http
    Quit op
}

/// One request through the operation, which always answers.
Method Run(op As Shutter.Operation.FHIRExecute, request As Shutter.Msg.FHIRWrite) As Shutter.Msg.FHIRWriteResult
{
    Set response = ""
    Do $$$AssertStatusOK(op.OnWrite(request, .response), "the request is answered, never with an error status")
    Do $$$AssertStatusOK(response.%ValidateObject(), "and the answer can be saved")
    Quit response
}

/// A request that is refused before anything: no request to the receiver, no fence row, nothing sent.
Method Refused(request As Shutter.Msg.FHIRWrite, code As %String, what As %String, approvalId As %String = "")
{
    Set op = ..Op(.http)
    Set response = ..Run(op, request)
    Do $$$AssertEquals(..Answer(response) _ " " _ +$GET(http.Requests), "refused|0|0|" _ code _ " 0", what _ " (" _ response.Error _ ")")
    Set fence = ##class(Shutter.Store.FHIRAttempt).ForApproval($SELECT(approvalId '= "": approvalId, 1: request.ApprovalId))
    Do $$$AssertTrue('$ISOBJECT(fence), what _ ": no fence row is made")
}

/// outcome|status|sent|reason of an answer.
ClassMethod Answer(response As Shutter.Msg.FHIRWriteResult) As %String
{
    Quit response.Outcome _ "|" _ response.HttpStatus _ "|" _ response.Sent _ "|" _ response.ReasonCode
}

/// outcome|reason of the classifier for one answer about enc-1.
ClassMethod Classified(sc As %Status, status As %Integer, etag As %String, location As %String, type As %String, body As %String, Output diagnostics As %String) As %String
{
    Set outcome = ##class(Shutter.Operation.FHIRExecute).Classify(sc, status, etag, location, type, body, "enc-1", .reason, .diagnostics)
    Quit outcome _ "|" _ reason
}

/// The verbs of the requests the adapter saw, in order.
ClassMethod Verbs(http As Shutter.Test.FakeFhir) As %String
{
    Set out = ""
    For i = 1:1:+$GET(http.Requests) {
        Set out = out _ $SELECT(i > 1: " ", 1: "") _ $LIST(http.Requests(i), 1)
    }
    Quit out
}

/// The verbs and addresses of the requests the adapter saw, in order.
ClassMethod Log(http As Shutter.Test.FakeFhir) As %String
{
    Set out = ""
    For i = 1:1:+$GET(http.Requests) {
        Set out = out _ $SELECT(i > 1: " | ", 1: "") _ $LIST(http.Requests(i), 1) _ " " _ $LIST(http.Requests(i), 2)
    }
    Quit out
}

/// The permits made since the test began, newest first; with <var>state</var> only those in it.
Method Permits(state As %String = "") As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, State FROM Shutter_Store.DispatchPermit WHERE ID > ? ORDER BY ID DESC", ..PermitsFrom)
    While rs.%Next() {
        Continue:(state'="")&&(rs.%Get("State")'=state)
        Do out.%Push({"id": (rs.%Get("ID")), "state": (rs.%Get("State"))})
    }
    Quit out
}

/// No permit of this test is left admitted: one would latch the stop for the whole deployment.
Method NoneAdmitted()
{
    Do $$$AssertEquals(..Permits("admitted").%Size(), 0, "no permit is left admitted")
}

/// The Encounter at the test FHIR server, read as the operation reads it: its body as characters, its ETag and its
/// content type.
Method ServerRead(Output etag As %String, Output type As %String) As %String
{
    Set http = ##class(Shutter.Test.FakeFhir).%New()
    Set http.Base = ..#BASE
    Set request = ##class(%Net.HttpRequest).%New()
    Do request.SetHeader("Accept", "application/fhir+json")
    Do http.SendFormDataArray(.answer, "GET", request, "", "", ..#BASE _ "/" _ ..#ENC)
    Set etag = answer.GetHeader("ETag"), type = answer.GetHeader("Content-Type")
    Do answer.Data.Rewind()
    Set bytes = ""
    While 'answer.Data.AtEnd {
        Set bytes = bytes _ answer.Data.Read(32000)
    }
    Quit $ZCONVERT(bytes, "I", "UTF8")
}

/// Another writer's update of the Encounter at the test FHIR server.
Method ServerWrite(body As %String, etag As %String)
{
    Set http = ##class(Shutter.Test.FakeFhir).%New()
    Set http.Base = ..#BASE
    Set request = ##class(%Net.HttpRequest).%New()
    Set request.ContentType = "application/fhir+json"
    Do request.SetHeader("If-Match", etag)
    Do request.EntityBody.Write($ZCONVERT(body, "O", "UTF8"))
    Do http.SendFormDataArray(.answer, "PUT", request, "", "", ..#BASE _ "/" _ ..#ENC)
    Do $$$AssertEquals(answer.StatusCode, 200, "another writer changed the Encounter")
}

/// Everything a write rests on, as the flow leaves it at the moment it asks FHIR Out: a case of this class's
/// receiver with a sealed snapshot and its sealed read, a current resend plan, the binding sealed on the receiver's
/// Encounter as it stands and tied to a person's approval, and a passing dispatch decision made now. The approved
/// body closes Ward A at the event time, opens Ward B and carries the marker; <var>reason</var> adds a reason text.
/// Returns the request.
Method Fixture(Output case As Shutter.Store.Case, Output binding As Shutter.Store.FHIRBinding, Output approval As Shutter.Store.Approval, Output decision As Shutter.Store.GateDecision, reason As %String = "") As Shutter.Msg.FHIRWrite
{
    Set policy = ##class(Shutter.FHIR.Profile).#POLICYVERSION
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-FHIRX-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.FHIRExecute)
    Set case.Event = "transfer", case.FailureKind = "delivery_failed", case.FailureText = "made up", case.EncounterId = ..#VISIT
    Set case.PatientId = "MRN-UTFX1", case.PatientIdAuthority = "HOSP", case.Receiver = ..#RECEIVER, case.State = "executing", case.Mode = "rules"
    Set case.OperationKey = "PAS^HOSP^MRN-UTFX1^" _ ..#VISIT _ "^transfer^" _ case.CaseId, case.Disposition = "resend"
    Set case.EventTime = "2026-11-14T10:30:00Z", case.Ward = "WARD-B"
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Do $$$AssertStatusOK(case.%Save(), "the case is saved")
    Set i%Made(case.%Id()) = ""

    // The evidence: the Encounter as the receiver has it now
    Set base = ..ServerRead(.etag)
    Do ##class(Shutter.FHIR.Judge).ETagVid(etag, .vid)
    Set snapshot = ##class(Shutter.Store.Snapshot).Begin(case)
    Do $$$AssertStatusOK(snapshot.Seal({"fhir": {"kind": "fhir_r4"}}), "the snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snapshot), "and is the case's current one")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRSealedRead).Keep(case, snapshot.%Id(), base), "its Encounter body is kept")

    Set action = {"type": "resend", "operation_key": (case.OperationKey)}
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, snapshot, {"disposition": "resend", "summary": "One update of the Encounter's location", "action": (action)}, "rules", .plan), "a plan is saved")
    Set case.CurrentPlan = plan
    Do $$$AssertStatusOK(case.%Save(), "and is the case's current one")

    // The approved body
    Set operation = $EXTRACT(##class(Shutter.FHIR.Plan).BodyDigest(case.CaseId _ "|" _ plan.%Id() _ "|" _ etag), 1, 32)
    Set enc = ..J(base)
    Do enc.location.%Get(0).period.%Set("end", case.EventTime)
    Do enc.location.%Get(0).%Set("status", "completed")
    Do enc.location.%Push({"location": {"reference": "Location/ward-b"}, "status": "active", "period": {"start": (case.EventTime)}})
    If '$ISOBJECT(enc.meta) Set enc.meta = {}
    Set enc.meta.tag = [{"system": "urn:shutter:recovery", "code": (operation)}]
    If reason '= "" {
        If '$ISOBJECT(enc.reasonCode) Set enc.reasonCode = []
        Do enc.reasonCode.%Push({"text": (reason)})
    }
    Set body = enc.%ToJSON()

    Set prepared = {"view": {"prior_location": "Location/ward-a", "target_location": "Location/ward-b"}, "detail": {},
        "fhir": {"kind": "fhir_r4", "mapping_digest": "sha256:ut-mapping",
            "encounter": {"http_status": 200, "id": "enc-1"},
            "patient": {"http_status": 200, "reference": "Patient/demo-p1", "etag": "W/\"1\""},
            "locations": [{"reference": "Location/ward-a", "etag": "W/\"1\""}, {"reference": "Location/ward-b", "etag": "W/\"1\""}]}}
    Set prepared.entry = ##class(Shutter.Store.SiteProfile).Receiver(..#RECEIVER)
    Set prepared.fhir.encounter.etag = etag, prepared.fhir.encounter."version_id" = vid
    Set prepared.fhir.encounter."body_digest" = ##class(Shutter.FHIR.Plan).BodyDigest(base)
    Set prepared."event_time" = case.EventTime, prepared."operation_id" = operation
    Set prepared.marker = {"system": "urn:shutter:recovery", "code": (operation)}
    Set prepared.body = body, prepared."body_digest" = ##class(Shutter.FHIR.Plan).BodyDigest(body)
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan, prepared, .binding), "the binding is sealed")

    Do $$$AssertStatusOK(##class(Shutter.Store.Approval).Create(case, plan, snapshot, policy, "", "", "ut.approver", "approved", "", "", 900, .approval), "a person approved the plan")
    Do $$$AssertStatusOK(binding.Bind(approval.%Id()), "and the binding is tied to that approval")
    Do $$$AssertStatusOK(##class(Shutter.Store.GateDecision).Create(case, plan, "dispatch", policy, "pass", [], "made up", .decision), "the dispatch gate passed")

    Set request = ##class(Shutter.Msg.FHIRWrite).%New()
    Set request.CaseId = case.CaseId, request.PlanId = plan.%Id(), request.ApprovalId = approval.%Id()
    Set request.BindingId = binding.%Id(), request.DecisionId = decision.%Id()
    Quit request
}

/// A newer plan of the case, made its current one.
Method NewCurrentPlan(case As Shutter.Store.Case)
{
    Set action = {"type": "resend", "operation_key": (case.OperationKey)}
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, case.CurrentSnapshot, {"disposition": "resend", "summary": "a later plan", "action": (action)}, "rules", .plan), "a later plan is saved")
    Set case.CurrentPlan = plan
    Do $$$AssertStatusOK(case.%Save(), "and is the case's current one")
}

/// A body as its JSON object.
ClassMethod J(text As %String) As %DynamicObject
{
    Quit ##class(%DynamicAbstractObject).%FromJSON(text)
}

/// Puts this class's receiver into the stored profile (once per test), with <var>patch</var> set over its fhir
/// block and the profile's recovery mode as given ("" takes the recovery section away). <var>further</var> sets what
/// another visit's in-patient movement does to a write (stop or show).
Method ChangeEntry(patch As %DynamicObject, mode As %String = "enabled", further As %String = "")
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..ProfileChanged {
        Set ..HadProfileRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: ""), ..ProfileChanged = 1
    }
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    If mode = "" { Do p.%Remove("recovery") } Else { Do p.%Set("recovery", {"mode": (mode)}) }
    If further '= "" Do p.%Set("further_messages", {"in_patient_movement": (further)})
    Set entry = {"name": (..#RECEIVER), "system": "the ward system (FHIR R4)", "category": "current_state", "tier": 3, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "fhir": {"base": (..#BASE), "recovery_enabled": true, "encounter_identifier": {"system": (..#SYS)}, "patient_identifier": {"system": "urn:shutter:demo:mrn", "hl7_authority": "HOSP"}, "marker": {"system": "urn:shutter:recovery"}, "location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}
    If $ISOBJECT(patch) {
        Set it = patch.%GetIterator()
        While it.%GetNext(.key, .value) {
            If patch.%GetTypeOf(key) = "boolean" { Do entry.fhir.%Set(key, value, "boolean") } Else { Do entry.fhir.%Set(key, value) }
        }
    }
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
