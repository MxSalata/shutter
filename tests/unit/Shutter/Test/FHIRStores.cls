/// The FHIR stores: one binding per plan and one approval per binding, the one-dispatch fence and its SQL mechanics, the
/// sealed read that answers only to its digest, the purge with the case, and what a proof document must be to be
/// imported.
Class Shutter.Test.FHIRStores Extends %UnitTest.TestCase
{

Parameter RECEIVER = "UT FHIR Ward Out";

Parameter BASEBODY = "{""resourceType"":""Encounter"",""id"":""enc-1"",""meta"":{""versionId"":""1""},""status"":""in-progress""}";

Parameter NEWBODY = "{""resourceType"":""Encounter"",""id"":""enc-1"",""meta"":{""versionId"":""1""},""status"":""in-progress"",""location"":[]}";

Property Made As %String [ MultiDimensional ];

Method OnAfterOneTest() As %Status
{
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ##class(Shutter.Store.Case).PurgeCase(id)
    }
    Kill i%Made
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.FHIRProof WHERE Receiver %STARTSWITH ?", ..#RECEIVER)
    Quit $$$OK
}

/// A saved case with a sealed snapshot as its current one, and that snapshot's sealed read.
Method NewCase(Output snapshot As Shutter.Store.Snapshot) As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-FHIRST-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.FHIRStores)
    Set case.Event = "transfer", case.FailureKind = "delivery_failed", case.FailureText = "made up", case.EncounterId = "V1001"
    Set case.PatientId = "MRN-UT1", case.PatientIdAuthority = "HOSP", case.Receiver = ..#RECEIVER, case.State = "gated", case.Mode = "rules"
    Set case.OperationKey = "PAS^HOSP^MRN-UT1^V1001^transfer^" _ case.CaseId, case.Disposition = "resend"
    Set case.EventTime = "2026-11-14T10:30:00Z"
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Do $$$AssertStatusOK(case.%Save(), "the case is saved")
    Set i%Made(case.%Id()) = ""
    Set snapshot = ##class(Shutter.Store.Snapshot).Begin(case)
    Do $$$AssertStatusOK(snapshot.Seal({"fhir": {"kind": "fhir_r4"}}), "the snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snapshot), "and is the case's current one")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRSealedRead).Keep(case, snapshot.%Id(), ..#BASEBODY), "its Encounter body is kept")
    Quit case
}

Method NewPlan(case As Shutter.Store.Case) As Shutter.Store.Plan
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, case.CurrentSnapshot, {"disposition": "resend", "action": {"type": "resend"}}, "rules", .plan), "a plan is saved")
    Quit plan
}

/// What the proposal builder hands over for a plan, in the shape the design gives it.
Method Prepared(case As Shutter.Store.Case, plan As Shutter.Store.Plan, body As %String = "", etag As %String = "W/""1""") As %DynamicObject
{
    Set:body="" body = ..#NEWBODY
    Set digest = "Shutter.FHIR.Plan"
    Set operation = $EXTRACT($CLASSMETHOD(digest, "BodyDigest", case.CaseId _ "|" _ plan.%Id() _ "|" _ etag), 1, 32)
    Set map = [
        {"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}},
        {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]
    Set prepared = {"view": {"prior_location": "Location/ward-a", "target_location": "Location/ward-b"}, "detail": {},
        "fhir": {"kind": "fhir_r4", "mapping_digest": "sha256:ut-mapping",
            "encounter": {"http_status": 200, "id": "enc-1", "version_id": "1"},
            "patient": {"http_status": 200, "reference": "Patient/demo-p1", "etag": "W/\"4\""},
            "locations": [{"reference": "Location/ward-a", "etag": "W/\"2\""}, {"reference": "Location/ward-b", "etag": "W/\"3\""}]},
        "entry": {"name": (..#RECEIVER), "fhir": {"base": "/fhir-facade/r4", "encounter_identifier": {"system": "urn:ut:visit"},
            "patient_identifier": {"system": "urn:ut:mrn", "hl7_authority": "HOSP"}, "marker": {"system": "urn:shutter:recovery"}}}}
    Set prepared.entry.fhir."location_map" = map
    Set prepared.fhir.encounter.etag = etag, prepared.fhir.encounter."body_digest" = $CLASSMETHOD(digest, "BodyDigest", ..#BASEBODY)
    Set prepared."event_time" = case.EventTime, prepared."operation_id" = operation
    Set prepared.marker = {"system": "urn:shutter:recovery", "code": (operation)}
    Set prepared.body = body, prepared."body_digest" = $CLASSMETHOD(digest, "BodyDigest", body)
    Quit prepared
}

/// A plan of the case with its binding sealed and tied to an approval.
Method Bound(case As Shutter.Store.Case, approvalId As %String, etag As %String = "W/""1""") As Shutter.Store.FHIRBinding
{
    Set plan = ..NewPlan(case)
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan, ..Prepared(case, plan, , etag), .b), "the binding is sealed")
    Do $$$AssertStatusOK(b.Bind(approvalId), "and tied to approval " _ approvalId)
    Quit b
}

/// An approval id no other test or row uses.
Method ApprovalId() As %String
{
    Quit "UT" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.FHIRStores)
}

ClassMethod Count(table As %String, column As %String, value As %String) As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM Shutter_Store." _ table _ " WHERE " _ column _ " = ?", value)
    Quit $SELECT(rs.%Next(): rs.%Get("n"), 1: -1)
}

/// One column of one fence row, read through SQL so that no open object answers for the stored row.
ClassMethod Stored(id As %String, column As %String) As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT """ _ column _ """ AS v FROM Shutter_Store.FHIRAttempt WHERE ID = ?", id)
    Quit $SELECT(rs.%Next(): rs.%Get("v"), 1: "no row")
}

Method TestOneBindingPerPlan()
{
    Set case = ..NewCase(.snapshot), plan = ..NewPlan(case), prepared = ..Prepared(case, plan)
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan, prepared, .b), "a plan's update is sealed")
    Quit:'$ISOBJECT(b)
    Do $$$AssertEquals(b.PlanId, plan.%Id(), "under its plan")
    Do $$$AssertEquals(b.ApprovalId, "", "tied to no approval yet")
    Do $$$AssertEquals(b.SnapshotId, snapshot.%Id(), "on the case's current snapshot")
    Do $$$AssertEquals(b.Receiver, ..#RECEIVER, "for the case's receiver")
    Do $$$AssertEquals(b.EncounterId _ " " _ b.ExpectedEtag _ " " _ b.BaseVersionId, "enc-1 W/""1"" 1", "with the Encounter's id, ETag and version")
    Do $$$AssertEquals(b.BaseBody, ..#BASEBODY, "the base body is the snapshot's sealed read")
    Do $$$AssertEquals(b.ApprovedBody, ..#NEWBODY, "the approved body is the prepared one")
    Do $$$AssertEquals(b.ApprovedBodyDigest, ##class(Shutter.FHIR.Plan).BodyDigest(..#NEWBODY), "with its digest as bare hex")
    Do $$$AssertEquals(b.EncounterIdentifierJSON, {"system": "urn:ut:visit", "value": "V1001"}.%ToJSON(), "the Encounter's identifier is the mapped system and the case's visit number")
    Do $$$AssertEquals(b.PatientJSON, {"reference": "Patient/demo-p1", "identifier": {"system": "urn:ut:mrn", "value": "MRN-UT1"}, "etag": "W/\"4\""}.%ToJSON(), "the Patient with its identifier and ETag")
    Do $$$AssertEquals(b.LocationsJSON, [{"reference": "Location/ward-a", "ward": "WARD-A", "system": "urn:shutter:ward", "value": "WARD-A", "etag": "W/\"2\""}, {"reference": "Location/ward-b", "ward": "WARD-B", "system": "urn:shutter:ward", "value": "WARD-B", "etag": "W/\"3\""}].%ToJSON(), "every map entry in map order, each with its ETag")
    Do $$$AssertEquals(b.PriorLocation _ " " _ b.TargetLocation, "Location/ward-a Location/ward-b", "the prior and the target location")
    Do $$$AssertEquals(b.EventTime, "2026-11-14T10:30:00Z", "the event time as it was given")
    Do $$$AssertEquals(b.OperationId, prepared."operation_id", "the operation id")
    Do $$$AssertEquals(b.MarkerSystem, "urn:shutter:recovery", "the marker's system")
    Do $$$AssertEquals(b.MappingDigest, "sha256:ut-mapping", "the mapping digest of the evidence")
    Do $$$AssertTrue(b.SealedAt '= "", "and the time it was sealed")

    Set j = b.JudgeBinding()
    Do $$$AssertEquals(j."expected_etag" _ " " _ j."base_version_id" _ " " _ j."encounter_id", "W/""1"" 1 enc-1", "the verifier's view names the version")
    Do $$$AssertEquals(j."encounter_identifier".%ToJSON(), {"system": "urn:ut:visit", "value": "V1001"}.%ToJSON(), "the Encounter's identifier")
    Do $$$AssertEquals(j.patient.%ToJSON(), {"reference": "Patient/demo-p1", "identifier": {"system": "urn:ut:mrn", "value": "MRN-UT1"}}.%ToJSON(), "the Patient without its ETag")
    Do $$$AssertEquals(j.locations.%ToJSON(), [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}].%ToJSON(), "every bound Location with the identifier that was checked")
    Do $$$AssertEquals(j."operation_id" _ " " _ j."marker_system" _ " " _ j."event_time", b.OperationId _ " urn:shutter:recovery 2026-11-14T10:30:00Z", "the marker and the event time")
    Do $$$AssertEquals(j."prior_location" _ " " _ j."target_location", "Location/ward-a Location/ward-b", "the two locations")
    Do $$$AssertEquals(j."server_owned_fields".%ToJSON(), "[]", "and no server-owned fields")

    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan, ..Prepared(case, plan), .again), "the same update sealed again")
    Do $$$AssertEquals(again.%Id(), b.%Id(), "answers the same row")
    Do $$$AssertStatusNotOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan, ..Prepared(case, plan, ..#NEWBODY _ " "), .other), "another body for the same plan is refused")
    Do $$$AssertEquals(other, "", "and gives no binding")
    Do $$$AssertEquals(..Count("FHIRBinding", "PlanId", plan.%Id()), 1, "so the plan has one binding")
    Do $$$AssertEquals(##class(Shutter.Store.FHIRBinding).ForPlan(plan.%Id()).%Id(), b.%Id(), "found by its plan")
    Do $$$AssertEquals(##class(Shutter.Store.FHIRBinding).ForPlan("no-such-plan"), "", "and no other plan has it")

    // A binding rests only on the body the snapshot was sealed on.
    Set plan2 = ..NewPlan(case), bad = ..Prepared(case, plan2)
    Set bad.fhir.encounter."body_digest" = ##class(Shutter.FHIR.Plan).BodyDigest("another body")
    Do $$$AssertStatusNotOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan2, bad, .none), "evidence naming another body's digest is refused")
    Set bad = ..Prepared(case, plan2), bad."body_digest" = ##class(Shutter.FHIR.Plan).BodyDigest("another body")
    Do $$$AssertStatusNotOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan2, bad, .none), "a body that does not have its digest is refused")
    Set bad = ..Prepared(case, plan2), bad.view."target_location" = "Location/ward-z"
    Do $$$AssertStatusNotOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan2, bad, .none), "a target outside the map is refused")
    Set other = ..NewCase()
    Do $$$AssertStatusNotOK(##class(Shutter.Store.FHIRBinding).Seal(other, plan2, ..Prepared(case, plan2), .none), "another case's plan is refused")
    Do $$$AssertEquals(..Count("FHIRBinding", "PlanId", plan2.%Id()), 0, "and none of them left a row")
}

Method TestBindOnce()
{
    Set case = ..NewCase(), plan = ..NewPlan(case)
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan, ..Prepared(case, plan), .b), "the binding is sealed")
    Set first = ..ApprovalId(), second = ..ApprovalId()
    Do $$$AssertStatusNotOK(b.Bind(""), "no approval is no tie")
    Do $$$AssertStatusOK(b.Bind(first), "the first approval takes the binding")
    Do $$$AssertEquals(b.ApprovalId, first, "and the object shows it")
    Do $$$AssertEquals(..Count("FHIRBinding", "ApprovalId", first), 1, "as the stored row does")
    Do $$$AssertStatusOK(b.Bind(first), "the same approval again is accepted")
    Do $$$AssertStatusNotOK(b.Bind(second), "another approval is refused")
    Do $$$AssertEquals(b.ApprovalId, first, "and the binding stays with the first")
    Do $$$AssertEquals(..Count("FHIRBinding", "ApprovalId", second), 0, "in the stored row too")
}

Method TestOpenTwiceGivesOneRow()
{
    Set case = ..NewCase(), plan = ..NewPlan(case), approval = ..ApprovalId()
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan, ..Prepared(case, plan), .b), "the binding is sealed")
    Do $$$AssertStatusNotOK(##class(Shutter.Store.FHIRAttempt).Open(case, b, .a, .created), "a binding tied to no approval opens no fence row")
    Do $$$AssertStatusOK(b.Bind(approval), "tied to its approval")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, b, .a, .created), "the fence row opens")
    Do $$$AssertEquals(created, 1, "as a new row")
    Do $$$AssertEquals(a.State, "unsent", "unsent")
    Do $$$AssertEquals(a.ApprovalId _ " " _ a.PlanId _ " " _ a.BindingId, approval _ " " _ plan.%Id() _ " " _ b.%Id(), "naming the approval, the plan and the binding")
    Do $$$AssertEquals(a.ExpectedEtag _ " " _ a.BodyDigest _ " " _ a.OperationId, b.ExpectedEtag _ " " _ b.ApprovedBodyDigest _ " " _ b.OperationId, "with the binding's ETag, digest and operation id")
    Do $$$AssertTrue(a.CreatedAt '= "", "and when it was made")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, b, .again, .created), "opening it again")
    Do $$$AssertEquals(created, 0, "makes nothing")
    Do $$$AssertEquals(again.%Id(), a.%Id(), "and answers the same row")
    Do $$$AssertEquals(..Count("FHIRAttempt", "ApprovalId", approval), 1, "so the approval has one fence row")
    Do $$$AssertEquals(##class(Shutter.Store.FHIRAttempt).ForApproval(approval).%Id(), a.%Id(), "found by its approval")
    Do $$$AssertEquals(##class(Shutter.Store.FHIRAttempt).ForApproval("no-such-approval"), "", "and by no other")
    Set other = ..NewCase()
    Do $$$AssertStatusNotOK(##class(Shutter.Store.FHIRAttempt).Open(other, b, .none, .created), "another case opens no fence row on this binding")
}

Method TestMarkSentOnceThenFalse()
{
    Set case = ..NewCase(), b = ..Bound(case, ..ApprovalId())
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, b, .a, .created), "the fence row opens")
    Set waits = $SYSTEM.Process.SynchCommit()
    Do $$$AssertTrue(a.MarkSent(), "the first mark changes the row")
    Do $$$AssertEquals(a.State, "sent", "the object shows sent")
    Set sentAt = a.SentAt
    Do $$$AssertTrue(sentAt '= "", "with the time")
    Do $$$AssertEquals(..Stored(a.%Id(), "State"), "sent", "as the stored row does")
    Do $$$AssertNotTrue(a.MarkSent(), "the second mark answers false")
    Do $$$AssertEquals($SYSTEM.Process.SynchCommit(), waits, "and whether this job's other commits wait for the journal is as it was")
    Do $$$AssertEquals(..Stored(a.%Id(), "State") _ " " _ ..Stored(a.%Id(), "SentAt"), "sent " _ sentAt, "and leaves the row as it was")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, b, .again, .created), "opening the spent row")
    Do $$$AssertEquals(created _ " " _ again.State, "0 sent", "answers it as sent, not as new")
    Do $$$AssertNotTrue(again.MarkSent(), "and it cannot be marked again")
}

Method TestAnswerKeepsTheFenceSent()
{
    Set case = ..NewCase(), approval = ..ApprovalId(), b = ..Bound(case, approval)
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, b, .a, .created), "the fence row opens")
    Do $$$AssertTrue(a.MarkSent(), "it is marked sent")
    Set id = a.%Id(), sentAt = a.SentAt
    Do $$$AssertStatusOK(a.Answer(200, "applied", "W/""2""", "http://ut/fhir/r4/Encounter/enc-1/_history/2", "none"), "the answer is recorded")
    Do $$$AssertStatusOK(a.SetExecutionAttempt("77"), "and the attempt row is named")
    Do $$$AssertEquals(a.State _ " " _ a.Outcome _ " " _ a.HttpStatus, "sent applied 200", "the object shows the answer on a sent row")
    Kill a, again
    Set a = ##class(Shutter.Store.FHIRAttempt).%OpenId(id)
    Do $$$AssertEquals(a.State, "sent", "opened again by id, the row is sent")
    Do $$$AssertEquals(a.SentAt, sentAt, "with the time it was sent kept")
    Do $$$AssertEquals(a.Outcome _ " " _ a.HttpStatus _ " " _ a.ResponseEtag, "applied 200 W/""2""", "the outcome, status and ETag")
    Do $$$AssertEquals(a.ResponseLocation, "http://ut/fhir/r4/Encounter/enc-1/_history/2", "the Location")
    Do $$$AssertEquals(a.Diagnostics _ " " _ a.ExecutionAttemptId, "none 77", "the diagnostics and the attempt row")
    Do $$$AssertTrue(a.AnsweredAt '= "", "and when it was answered")
    Do $$$AssertEquals(..Stored(id, "State") _ " " _ ..Stored(id, "SentAt"), "sent " _ sentAt, "as the stored row says")
    Do $$$AssertNotTrue(a.MarkSent(), "an answered row is not marked sent again")
    // What does not fit its column is never cut into another value.
    Do $$$AssertStatusOK(a.Answer(200, "applied", $TRANSLATE($JUSTIFY("", 201), " ", "e"), $TRANSLATE($JUSTIFY("", 501), " ", "l"), $TRANSLATE($JUSTIFY("", 450), " ", "d")), "an answer too long for its columns is still recorded")
    Do $$$AssertEquals(a.ResponseEtag _ "|" _ a.ResponseLocation _ "|" _ $LENGTH(a.Diagnostics), "||400", "with no ETag, no Location and the diagnostics cut")
}

Method TestAnswerOnAnUnsentRowChangesNothing()
{
    Set case = ..NewCase(), b = ..Bound(case, ..ApprovalId())
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, b, .a, .created), "the fence row opens")
    Do $$$AssertStatusOK(a.Answer(200, "applied", "W/""2""", "somewhere", "none"), "an answer on an unsent row is no error")
    Do $$$AssertEquals(a.State _ "|" _ a.Outcome _ "|" _ a.HttpStatus _ "|" _ a.ResponseEtag _ "|" _ a.AnsweredAt, "unsent||||", "and the object is as it was")
    For column = "Outcome", "HttpStatus", "ResponseEtag", "ResponseLocation", "Diagnostics", "AnsweredAt", "SentAt" {
        Do $$$AssertEquals(..Stored(a.%Id(), column), "", "the stored row has no " _ column)
    }
    Do $$$AssertEquals(..Stored(a.%Id(), "State"), "unsent", "and is unsent")
    Do $$$AssertTrue(a.MarkSent(), "so it can still be sent once")
}

Method TestSentOperationIds()
{
    Set case = ..NewCase(), other = ..NewCase()
    Set b1 = ..Bound(case, ..ApprovalId(), "W/""1"""), b2 = ..Bound(case, ..ApprovalId(), "W/""2"""), b3 = ..Bound(case, ..ApprovalId(), "W/""3""")
    For b = b1, b2, b3 {
        Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, b, .a, .created), "a fence row opens")
        If b '= b2 Do $$$AssertTrue(a.MarkSent(), "and is sent")
    }
    Do $$$AssertEquals(##class(Shutter.Store.FHIRAttempt).SentOperationIds(case).%ToJSON(), [(b1.OperationId), (b3.OperationId)].%ToJSON(), "the sent rows' operation ids, oldest first, without the unsent one")
    Do $$$AssertEquals(##class(Shutter.Store.FHIRAttempt).SentOperationIds(other).%ToJSON(), "[]", "another case has none")
}

Method TestUnresolvedAt()
{
    Set class = "Shutter.Store.FHIRAttempt", case = ..NewCase(), other = ..NewCase(), etag = "W/""1"""
    Set b = ..Bound(case, ..ApprovalId(), etag)
    Do $$$AssertStatusOK($CLASSMETHOD(class, "Open", case, b, .a, .created), "the fence row opens")
    Do $$$AssertNotTrue($CLASSMETHOD(class, "UnresolvedAt", case, etag), "an unsent row leaves nothing unresolved")
    Do $$$AssertTrue(a.MarkSent(), "it is sent")
    Do $$$AssertTrue($CLASSMETHOD(class, "UnresolvedAt", case, etag), "a sent row with no answer is unresolved at its version")
    Do $$$AssertNotTrue($CLASSMETHOD(class, "UnresolvedAt", case, "W/""2"""), "not at another version")
    Do $$$AssertNotTrue($CLASSMETHOD(class, "UnresolvedAt", case, "w/""1"""), "nor at an ETag that differs in case")
    Do $$$AssertNotTrue($CLASSMETHOD(class, "UnresolvedAt", case, ""), "nor with no ETag to compare")
    Do $$$AssertNotTrue($CLASSMETHOD(class, "UnresolvedAt", other, etag), "nor for another case")
    For outcome = "uncertain", "applied" {
        Do $$$AssertStatusOK(a.Answer(0, outcome, "", "", ""), "answered " _ outcome)
        Do $$$AssertTrue($CLASSMETHOD(class, "UnresolvedAt", case, etag), outcome _ " may yet land on this version")
    }
    For outcome = "version_conflict", "refused", "error" {
        Do $$$AssertStatusOK(a.Answer(412, outcome, "", "", ""), "answered " _ outcome)
        Do $$$AssertNotTrue($CLASSMETHOD(class, "UnresolvedAt", case, etag), outcome _ " is resolved")
    }
}

Method TestSealedReadChecksItsDigest()
{
    Set class = "Shutter.Store.FHIRSealedRead", case = ..NewCase(.snapshot), sid = snapshot.%Id()
    Set digest = ##class(Shutter.FHIR.Plan).BodyDigest(..#BASEBODY)
    Do $$$AssertEquals($CLASSMETHOD(class, "BodyFor", sid, digest), ..#BASEBODY, "the body answers to its digest")
    Do $$$AssertEquals($CLASSMETHOD(class, "BodyFor", sid, ##class(Shutter.FHIR.Plan).BodyDigest("another")), "", "not to another digest")
    Do $$$AssertEquals($CLASSMETHOD(class, "BodyFor", sid, ""), "", "not to none")
    Do $$$AssertEquals($CLASSMETHOD(class, "BodyFor", "no-such-snapshot", digest), "", "and a snapshot without a row has none")
    Do $$$AssertStatusOK($CLASSMETHOD(class, "Keep", case, sid, ..#BASEBODY), "keeping the same body again is accepted")
    Do $$$AssertStatusNotOK($CLASSMETHOD(class, "Keep", case, sid, ..#BASEBODY _ " "), "another body for the snapshot is refused")
    Do $$$AssertStatusNotOK($CLASSMETHOD(class, "Keep", case, sid, ""), "as is no body")
    Do $$$AssertEquals(..Count("FHIRSealedRead", "SnapshotId", sid), 1, "so the snapshot has one row")
    // A body with a character above ASCII comes back as it was kept.
    Set case2 = ..NewCase(.snap2), snap3 = ##class(Shutter.Store.Snapshot).Begin(case2)
    Do $$$AssertStatusOK(snap3.Seal({}), "another snapshot")
    Set body = "{""resourceType"":""Encounter"",""id"":""enc-2"",""x"":""Zo" _ $CHAR(235) _ " " _ $CHAR(8364) _ """}"
    Do $$$AssertStatusOK($CLASSMETHOD(class, "Keep", case2, snap3.%Id(), body), "a body with characters above ASCII is kept")
    Do $$$AssertEquals($CLASSMETHOD(class, "BodyFor", snap3.%Id(), ##class(Shutter.FHIR.Plan).BodyDigest(body)), body, "and comes back character for character")
    // A row whose body was changed behind its digest answers nothing.
    Do ##class(%SQL.Statement).%ExecDirect(, "UPDATE Shutter_Store.FHIRSealedRead SET EncounterBody = ? WHERE SnapshotId = ?", ..#BASEBODY _ " ", sid)
    Do $$$AssertEquals($CLASSMETHOD(class, "BodyFor", sid, digest), "", "a body that no longer has its digest is not given")
}

Method TestPurgeWithTheCase()
{
    Set case = ..NewCase(), id = case.%Id(), kept = ..NewCase(), approval = ..ApprovalId()
    Set b = ..Bound(case, approval), b2 = ..Bound(kept, ..ApprovalId())
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, b, .a, .created), "the case has a fence row")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(kept, b2, .a2, .created), "as has another case")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRProof).Import(..#RECEIVER, ..Proof().%ToJSON()), "and the receiver has a proof")
    For table = "FHIRBinding", "FHIRAttempt", "FHIRSealedRead" {
        Do $$$AssertEquals(..Count(table, """Case""", id), 1, "before the purge the case has a row in " _ table)
    }
    Do $$$AssertStatusOK(##class(Shutter.Store.Case).PurgeCase(id), "the case is purged")
    Kill i%Made(id)
    For table = "FHIRBinding", "FHIRAttempt", "FHIRSealedRead" {
        Do $$$AssertEquals(..Count(table, """Case""", id), 0, "after it the case has none in " _ table)
        Do $$$AssertEquals(..Count(table, """Case""", kept.%Id()), 1, "and the other case keeps its row in " _ table)
    }
    Do $$$AssertEquals(##class(Shutter.Store.FHIRBinding).ForPlan(b.PlanId), "", "the plan's binding is gone")
    Do $$$AssertEquals(##class(Shutter.Store.FHIRAttempt).ForApproval(approval), "", "as is the approval's fence row")
    Do $$$AssertTrue($ISOBJECT(##class(Shutter.Store.FHIRProof).For(..#RECEIVER)), "the proof is install state and stays")
}

/// A proof document Import accepts, as fhir_conformance.py --proof writes it.
ClassMethod Proof() As %DynamicObject
{
    Set proof = "Shutter.Store.FHIRProof"
    Quit {"kit": ($PARAMETER(proof, "KITNAME")), "kit_sha256": ($PARAMETER(proof, "KITSHA256")), "target": "facade",
        "base": "http://127.0.0.1:52773/fhir-facade/r4", "measured_at": "2026-11-14T10:00:00Z",
        "software": {"name": "Shutter test FHIR server", "version": "facade-v1"}, "fhir_version": "4.0.1",
        "exchanges": (+$PARAMETER(proof, "KITFACADE")), "differ": 0,
        "measurements": {"if_match_stale_refused": {"exchange": "m3-update-stale", "passed": true},
            "if_match_unknown_id_refused": {"exchange": "m5-if-match-unknown-id", "passed": true},
            "tags_kept": {"exchange": "m8-history-tags", "passed": true}}}
}

/// Imports a changed document over an accepted one and asserts that it is refused and the accepted row stands.
Method Refused(doc, what As %String)
{
    Set receiver = ..#RECEIVER _ " refusals"
    If '$ISOBJECT(##class(Shutter.Store.FHIRProof).For(receiver)) {
        Do $$$AssertStatusOK(##class(Shutter.Store.FHIRProof).Import(receiver, ..Proof().%ToJSON()), "an accepted proof to stand")
    }
    Set before = ##class(Shutter.Store.FHIRProof).For(receiver), version = before.SoftwareVersion
    Set sc = ##class(Shutter.Store.FHIRProof).Import(receiver, $SELECT($ISOBJECT(doc): doc.%ToJSON(), 1: doc), .p)
    Do $$$AssertStatusNotOK(sc, what _ " is refused: " _ $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertEquals(p, "", what _ " gives no row")
    Do $$$AssertEquals(##class(Shutter.Store.FHIRProof).For(receiver).SoftwareVersion, version, what _ " leaves the accepted row")
}

Method TestImportRefusesEachMissingPiece()
{
    Set class = "Shutter.Store.FHIRProof", receiver = ..#RECEIVER _ " whole"
    Do $$$AssertEquals($LENGTH($PARAMETER(class, "KITSHA256")), 64, "the build carries the kit's digest")
    Do $$$AssertStatusOK($CLASSMETHOD(class, "Import", receiver, ..Proof().%ToJSON(), .p), "a whole proof is imported")
    Quit:'$ISOBJECT(p)
    Do $$$AssertEquals(p.Receiver _ "|" _ p.SoftwareName _ "|" _ p.SoftwareVersion _ "|" _ p.FhirVersion, receiver _ "|Shutter test FHIR server|facade-v1|4.0.1", "the receiver and the software")
    Do $$$AssertEquals(p.Kit _ "|" _ p.KitDigest _ "|" _ p.Target _ "|" _ p.Exchanges _ "|" _ p.Differ, $PARAMETER(class, "KITNAME") _ "|" _ $PARAMETER(class, "KITSHA256") _ "|facade|" _ $PARAMETER(class, "KITFACADE") _ "|0", "the kit, its digest, the target and the counts")
    Do $$$AssertEquals(p.MeasuredBase _ "|" _ p.MeasuredAt, "http://127.0.0.1:52773/fhir-facade/r4|2026-11-14T10:00:00Z", "where and when it was measured")
    Do $$$AssertEquals(p.IfMatchStaleRefused _ p.IfMatchUnknownIdRefused _ p.TagsKept, "111", "the three measurements")
    Do $$$AssertEquals(p.MeasurementsJSON, ..Proof().measurements.%ToJSON(), "as the document gave them")
    Do $$$AssertTrue((p.ImportedAt '= "") && (p.ImportedBy '= ""), "and when and by whom it was imported")
    Do $$$AssertStatusOK($CLASSMETHOD(class, "Import", receiver, ..Proof().%ToJSON(), .again), "importing again")
    Do $$$AssertEquals(again.%Id(), p.%Id(), "replaces the receiver's row")
    Do $$$AssertEquals(..Count("FHIRProof", "Receiver", receiver), 1, "so there is one")

    For key = "kit", "kit_sha256", "target", "base", "measured_at", "software", "fhir_version", "exchanges", "differ", "measurements" {
        Set doc = ..Proof()
        Do doc.%Remove(key)
        Do ..Refused(doc, "a proof without " _ key)
    }
    For key = "name", "version" {
        Set doc = ..Proof()
        Do doc.software.%Remove(key)
        Do ..Refused(doc, "a proof without software." _ key)
        Set doc = ..Proof()
        Do doc.software.%Set(key, "")
        Do ..Refused(doc, "a proof with an empty software." _ key)
    }
    For key = "if_match_stale_refused", "if_match_unknown_id_refused", "tags_kept" {
        Set doc = ..Proof()
        Do doc.measurements.%Remove(key)
        Do ..Refused(doc, "a proof without the measurement " _ key)
        For part = "exchange", "passed" {
            Set doc = ..Proof()
            Do doc.measurements.%Get(key).%Remove(part)
            Do ..Refused(doc, "a proof whose " _ key _ " has no " _ part)
        }
    }
    Do ..Refused("", "an empty document")
    Do ..Refused("not JSON", "text that is not JSON")
    Do ..Refused("[]", "an array")
    Do $$$AssertStatusNotOK($CLASSMETHOD(class, "Import", "", ..Proof().%ToJSON(), .none), "a proof for no receiver is refused")

    // From a file.
    Set path = ##class(%File).TempFilename("json"), file = ##class(%Stream.FileCharacter).%New()
    Set file.TranslateTable = "UTF8"
    Do file.LinkToFile(path), file.Write(..Proof().%ToJSON()), file.%Save()
    Kill file
    Do $$$AssertStatusOK($CLASSMETHOD(class, "ImportFile", receiver _ " file", path), "the document is imported from a file")
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(class, "For", receiver _ " file")), "and the receiver has its row")
    Do ##class(%File).Delete(path)
    Do $$$AssertStatusNotOK($CLASSMETHOD(class, "ImportFile", receiver _ " none", path), "a file that is not there is refused")
    Do $$$AssertEquals($CLASSMETHOD(class, "For", receiver _ " none"), "", "and leaves no row")
}

Method TestImportRefusesAnotherKitDigestCountOrExchange()
{
    Set class = "Shutter.Store.FHIRProof"
    Set doc = ..Proof(), doc.kit = "fhir-facade-v2.json"
    Do ..Refused(doc, "another kit")
    Set doc = ..Proof(), doc."kit_sha256" = $TRANSLATE(doc."kit_sha256", "0123456789abcdef", "123456789abcdef0")
    Do ..Refused(doc, "another digest")
    Set doc = ..Proof(), doc."kit_sha256" = $ZCONVERT(doc."kit_sha256", "U")
    Do ..Refused(doc, "the digest in upper case")
    Set doc = ..Proof(), doc.exchanges = doc.exchanges - 1
    Do ..Refused(doc, "one exchange fewer")
    Set doc = ..Proof(), doc.exchanges = doc.exchanges + 1
    Do ..Refused(doc, "one exchange more")
    Set doc = ..Proof(), doc.exchanges = "" _ doc.exchanges
    Do ..Refused(doc, "the count as a string")
    Set doc = ..Proof(), doc.target = "iris"
    Do ..Refused(doc, "the facade's count under the target iris")
    Set doc = ..Proof(), doc.target = "hapi"
    Do ..Refused(doc, "another target")
    For key = "if_match_stale_refused", "if_match_unknown_id_refused", "tags_kept" {
        Set doc = ..Proof(), doc.measurements.%Get(key).exchange = "m2-capability"
        Do ..Refused(doc, key _ " resting on another exchange")
    }
    Set doc = ..Proof(), doc.measurements.extra = {"exchange": "m2-capability", "passed": true}
    Do ..Refused(doc, "a fourth measurement")
    Set doc = ..Proof(), doc.measurements."tags_kept".note = "x"
    Do ..Refused(doc, "a measurement with another member")

    Set doc = ..Proof(), doc.target = "iris", doc.exchanges = +$PARAMETER(class, "KITIRIS")
    Do $$$AssertStatusOK($CLASSMETHOD(class, "Import", ..#RECEIVER _ " iris", doc.%ToJSON(), .p), "the target iris with its own count is imported")
    Do $$$AssertEquals(p.Target _ " " _ p.Exchanges, "iris " _ $PARAMETER(class, "KITIRIS"), "as measured")
}

Method TestImportRefusesADifferingRun()
{
    Set doc = ..Proof(), doc.differ = 1
    Do ..Refused(doc, "a run in which one exchange differed")
    Set doc = ..Proof(), doc.differ = "0"
    Do ..Refused(doc, "a differ that is not a number")
    For key = "if_match_stale_refused", "if_match_unknown_id_refused", "tags_kept" {
        Set doc = ..Proof()
        Do doc.measurements.%Get(key).%Set("passed", 0, "boolean")
        Do ..Refused(doc, "a run whose " _ key _ " did not pass")
        Set doc = ..Proof(), doc.measurements.%Get(key).passed = "true"
        Do ..Refused(doc, "a " _ key _ " that passed only as a string")
    }
}

Method TestMatchesNeedsNameAndVersion()
{
    Set class = "Shutter.Store.FHIRProof", receiver = ..#RECEIVER _ " matches"
    Do $$$AssertStatusOK($CLASSMETHOD(class, "Import", receiver, ..Proof().%ToJSON(), .p), "a proof is imported")
    Quit:'$ISOBJECT(p)
    Do $$$AssertTrue(p.Matches("Shutter test FHIR server", "facade-v1"), "the measured name and version match")
    Do $$$AssertNotTrue(p.Matches("Shutter test FHIR server", "facade-v2"), "another version does not")
    Do $$$AssertNotTrue(p.Matches("Another FHIR server", "facade-v1"), "another name does not")
    Do $$$AssertNotTrue(p.Matches("shutter test fhir server", "facade-v1"), "a name that differs in case does not")
    Do $$$AssertNotTrue(p.Matches("Shutter test FHIR server", "facade-v1 "), "nor a version with a space after it")
    Do $$$AssertNotTrue(p.Matches("", "facade-v1"), "no name does not")
    Do $$$AssertNotTrue(p.Matches("Shutter test FHIR server", ""), "no version does not")
    Do $$$AssertNotTrue(p.Matches("", ""), "nor neither")
    Set p.SoftwareVersion = ""
    Do $$$AssertNotTrue(p.Matches("Shutter test FHIR server", ""), "a row with no stored version matches nothing")
    Set p.SoftwareVersion = "facade-v1", p.SoftwareName = ""
    Do $$$AssertNotTrue(p.Matches("", "facade-v1"), "nor does a row with no stored name")
    Do $$$AssertEquals($CLASSMETHOD(class, "For", ""), "", "no receiver has no proof")
    Do $$$AssertEquals($CLASSMETHOD(class, "For", receiver _ " other"), "", "nor has a receiver without a row")
}

}
