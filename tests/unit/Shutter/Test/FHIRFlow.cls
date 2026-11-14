/// The flow of a case whose receiver is a FHIR R4 receiver (Shutter.FHIR.Flow) and the lines of the case workflow that
/// hand such a case to it, on an instance of the workflow outside the production (Shutter.Test.QuietFHIRWorkflow): every
/// send is kept, none is made. The answers of the gate, the reader, FHIR Out and the verifier are made up here, each
/// with the rows a real one leaves in the store (a gate decision, a fence row), so the tests say what the flow does
/// with an answer, not what the items answer.
///
/// For each test the class puts a FHIR receiver of its own into the stored site profile with recovery enabled, clears
/// the recovery stop, and points Shutter at a scratch production that holds the four FHIR items and never runs
/// (^Shutter.Config("production")); all of it goes back as it was, and every case made is purged.
Class Shutter.Test.FHIRFlow Extends %UnitTest.TestCase
{

Parameter RECEIVER = "UT FHIR Flow Out";

Parameter PRODUCTION = "ShutterTest.FhirFlow";

Parameter APPROVER = "ut.approver";

Property Made As %String [ MultiDimensional ];

/// The read results the flow saved for the gate, to delete.
Property Reads As %String [ MultiDimensional ];

Property SavedProfile As %String(MAXLEN = "");

Property ProfileChanged As %Boolean [ InitialExpression = 0 ];

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

Property SavedControl As %String(MAXLEN = "");

Property HadProduction As %Boolean [ InitialExpression = 0 ];

Property SavedProduction As %String(MAXLEN = "");

/// Counters of every workflow instance a test let go of (Next): what the workflow's own path was asked for.
Property MainCalls As %Integer [ InitialExpression = 0 ];

Property KeysSoFar As %String(MAXLEN = "");

Property ClassesSoFar As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
    Do ##class(Shutter.Util.RecoveryControl).Ensure()
    Set c = ##class(Shutter.Util.RecoveryControl).Control()
    Set ..SavedControl = $LISTBUILD(c.StopLatched, c.StoppedAt, c.StoppedBy, c.StopReason)
    Set c.StopLatched = 0, c.StoppedAt = "", c.StoppedBy = "", c.StopReason = ""
    Do c.%Save()
    Set ..HadProduction = $DATA(^Shutter.Config("production"), was) # 2, ..SavedProduction = $GET(was)
    Set sc = ..MakeProduction()
    Quit:$$$ISERR(sc) sc
    Set ^Shutter.Config("production") = ..#PRODUCTION
    Set ..MainCalls = 0, ..KeysSoFar = "", ..ClassesSoFar = ""
    Do ..ChangeProfile()
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    If ..HadProduction { Set ^Shutter.Config("production") = ..SavedProduction } Else { Kill ^Shutter.Config("production") }
    Do ..RemoveProduction()
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ##class(Shutter.Store.Case).PurgeCase(id)
    }
    Kill i%Made
    Set id = ""
    For {
        Set id = $ORDER(i%Reads(id))
        Quit:id=""
        Do ##class(Shutter.Msg.FHIRReadResult).%DeleteId(id)
    }
    Kill i%Reads
    Set c = ##class(Shutter.Util.RecoveryControl).Control()
    Set c.StopLatched = $LIST(..SavedControl, 1), c.StoppedAt = $LIST(..SavedControl, 2), c.StoppedBy = $LIST(..SavedControl, 3), c.StopReason = $LIST(..SavedControl, 4)
    Do c.%Save()
    Do ..RestoreProfile()
    Quit $$$OK
}

// ---- the tests ----

/// Nothing Shutter ships is a FHIR receiver: not the default profile, not the seed. So no case of an install that was
/// not given one takes any line of the FHIR flow.
Method TestShippedProfilesAreNotFHIR()
{
    Set list = ##class(Shutter.Store.SiteProfile).Default().receivers, n = 0
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .r) { Set n = n + 1 Do $$$AssertNotTrue(r.%IsDefined("fhir"), "the default profile's receiver " _ r.name _ " has no fhir block") }
    Do $$$AssertTrue(n > 0, "the default profile has receivers (" _ n _ ")")
    Set path = $PIECE($GET(^UnitTestRoot), "tests/unit/", 1) _ "knowledge/site/profile.json"
    If ($GET(^UnitTestRoot) = "") || '##class(%File).Exists(path) {
        Do $$$LogMessage("knowledge/site/profile.json is not on the mounted path; the seed was not checked")
    } Else {
        Set stream = ##class(%Stream.FileCharacter).%New()
        Do stream.LinkToFile(path)
        Set stream.TranslateTable = "UTF8"
        Set seed = {}.%FromJSON(stream), n = 0
        Set iter = $SELECT($ISOBJECT(seed.%Get("receivers")): seed.%Get("receivers"), 1: []).%GetIterator()
        While iter.%GetNext(.i, .r) { Set n = n + 1 Do $$$AssertNotTrue(r.%IsDefined("fhir"), "the seed's receiver " _ r.name _ " has no fhir block") }
        Do $$$AssertTrue(n > 0, "the seed has receivers (" _ n _ ")")
    }
    // The workflow's own question, for a case of the shipped receiver, one that names none, and this class's.
    Set wf = ##class(Shutter.Test.QuietFHIRWorkflow).%New("Case Workflow")
    Do $$$AssertNotTrue(wf.IsFHIR(..NewCase("rules", 0)), "a case of the shipped receiver is not a FHIR case")
    Set none = ..NewCase("rules", 0)
    Set none.Receiver = ""
    Do $$$AssertNotTrue(wf.IsFHIR(none), "nor is a case that names no receiver, which is the workflow's own connector")
    Do $$$AssertTrue(wf.IsFHIR(..NewCase("rules")), "a case of a receiver with a fhir block is")
}

/// A FHIR case's plan goes to the FHIR gate, through the one funnel, and the workflow's own gate is never asked. Rules
/// only proposes the one update with no expected version; another mode with no entry that says resend asks a person.
Method TestAFhirPlanGoesToTheFhirGate()
{
    Do ..Planned("rules", .wf, .case)
    Do $$$AssertEquals(wf.Last(), "FHIR Gate|Shutter.Msg.FHIRGateRequest|fhir:gate:proposal", "the plan is sent to the FHIR gate")
    Do $$$AssertEquals(wf.MainGates _ " " _ +$GET(wf.Sent), "0 1", "and nowhere else: the workflow's own gate is not asked")
    Set req = wf.LastRequest(), plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
    Do $$$AssertEquals(req.CaseId _ "|" _ req.PlanId _ "|" _ req.Stage _ "|" _ req.ReadId _ "|" _ req.ApprovalId, case.CaseId _ "|" _ plan.%Id() _ "|proposal||", "for this case's plan, at the proposal")
    Do $$$AssertEquals(plan.Disposition _ "|" _ plan.ActionType _ "|" _ plan.OperationKey _ "|[" _ plan.ExpectedVersion _ "]|" _ plan.CreatedBy, "resend|resend|" _ case.OperationKey _ "|[]|rules", "a resend plan of the case's operation, with no expected version, made by the rules")
    Do $$$AssertEquals(plan.PayloadDigest, "sha256:ut", "with the message's digest")
    Do $$$AssertEquals(plan.Summary, "One update of the Encounter's location with If-Match on the version read, after this case's own approval. The HL7 message is not sent again.", "its summary")
    Do $$$AssertEquals(case.State, "proposed", "the case is proposed")
    Do $$$AssertEquals(case.Headline, "Update the Encounter's location once, WARD-A to WARD-B, after this case's own approval. No dry run exists for this receiver. The HL7 message is not sent again.", "under the flow's headline")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(case.CaseId).Headline, case.Headline, "which is saved")

    // Site policy mode with nothing that settles the case: a person, with the reason in the plan's own summary.
    For decision = "person", "new_pattern", "" {
        Do ..Planned("policy", .wf, .case, $SELECT(decision = "": "", 1: {"decision": (decision), "entry": "E19", "matches": []}))
        Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
        Do $$$AssertEquals(plan.Disposition _ "|" _ plan.ActionType _ "|" _ plan.CreatedBy _ "|" _ plan.IsWrite(), "escalate|none|fhir|0", "catalogue [" _ decision _ "]: a plan that asks for a person and writes nothing")
        Do $$$AssertEquals($EXTRACT(plan.Summary, * - 24, *), " (FHIR_PLAN_NEEDS_PERSON)", "whose summary ends with its reason: " _ plan.Summary)
        Do $$$AssertEquals(wf.Last() _ " " _ wf.MainGates, "FHIR Gate|Shutter.Msg.FHIRGateRequest|fhir:gate:proposal 0", "it goes to the FHIR gate too")
        Do $$$AssertTrue(case.Headline [ "Escalated to a person", "under the workflow's own headline for such a plan: " _ case.Headline)
    }
}

/// From the evidence to the close no ward operation is built or sent, nothing of the workflow's own path is asked,
/// and the case is never rehearsing.
Method TestNoWardOperationIsBuilt()
{
    Do ..ToTheEnd(0, .wf, .case)
    Do $$$AssertEquals(case.State, "resolved", "the case went the whole way")
    Do $$$AssertEquals(wf.WardOperations, 0, "no ward operation was built")
    Do $$$AssertEquals(wf.MainGates + wf.MainVerifies + wf.MainPreflights + wf.Boards, 0, "the workflow's own gate, verifier, preflight read and board were not asked")
    Do $$$AssertEquals(wf.Classes(), "Shutter.Msg.FHIRGateRequest EnsLib.Workflow.TaskRequest Ens.AlarmRequest Shutter.Msg.FHIRRead Shutter.Msg.FHIRWrite Shutter.Msg.VerifyRequest", "what was sent")
    Do $$$AssertEquals(..States(case), "investigating proposed gated awaiting_approval approved executing verifying resolved", "the states the case went through, with no rehearsing")
    Set id = case.%Id(), n = ""
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.Rehearsal WHERE "Case" = :id)
    Do $$$AssertEquals(n, 0, "and no rehearsal is on record")
}

/// A tier the site's policy releases by itself still asks a person: the catalogue's entry settles what is proposed,
/// never who releases it.
Method TestAnAutomaticTierStillAsksAPerson()
{
    Do ..ChangeProfile({"1": {"single": "automatic", "ordered": "automatic", "interleaved": "automatic"}, "2": {"single": "automatic", "ordered": "automatic", "interleaved": "automatic"}, "3": {"single": "automatic", "ordered": "automatic", "interleaved": "automatic"}})
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(##class(Shutter.Store.SiteProfile).TierOf(..#RECEIVER), "single"), "automatic", "the site's policy releases this receiver's tier by itself")
    Do ..Planned("policy", .wf, .case, ..Resend())
    Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
    Do $$$AssertEquals(wf.Policy _ "|" _ wf.CatalogueEntry _ "|" _ wf.CatalogueOutcome, "approval|E2|preferred", "the flow's policy is an approval, whatever the table says")
    Do $$$AssertEquals(plan.Disposition _ "|" _ plan.CreatedBy _ "|" _ plan.CatalogueEntry _ "|" _ plan.Outcome _ "|" _ plan.Why _ "|[" _ plan.ExpectedVersion _ "]", "resend|policy:E2|E2|preferred|the transfer never reached the receiver|[]", "the plan follows the entry, with no expected version")
    Do ..Step(wf, "fhir:gate:proposal", ..Gate(case, wf, "proposal"))
    Do $$$AssertEquals(case.State, "awaiting_approval", "a pass at the proposal waits for a person")
    Do $$$AssertEquals(wf.Keys(), "fhir:gate:proposal fhir:approval approval:timeout:1", "a task and its bounded wait were sent")
    Do $$$AssertEquals(..Count("Approval", case) _ " " _ ..Count("ExecutionAttempt", case), "0 0", "no approval was made for anyone and nothing was sent")
}

/// A release under an incident's approval or at an expected version releases nothing for a FHIR case: the release is
/// taken down to the case's own path, and the flow asks a person.
Method TestAReleaseUnderAnIncidentReleasesNothing()
{
    For fhir = 1, 0 {
        Set case = ..NewCase("policy", fhir)
        Do $$$AssertStatusOK(case.Transition("grouped", "held by an incident"), "the case is grouped")
        Set wf = ..Workflow(case)
        Set release = ##class(Shutter.Msg.CaseRelease).%New()
        Set release.CaseId = case.CaseId, release.IncidentId = "INC-UT-FLOW", release.ChainSeq = 1, release.Position = 1, release.ChainKind = "single", release.Decides = "policy"
        Set release.ExpectedVersion = "7", release.ReleasePolicy = "incident", release.Approver = "ut.incident", release.ApprovalRef = "1", release.PlanDigest = "sha256:incident", release.Entry = "E2", release.Outcome = "resend"
        Do $$$AssertStatusOK(wf.OnRelease(release, .started), "the release is taken")
        Do $$$AssertEquals(wf.Evidence, 1, "evidence is collected afresh")
        If 'fhir {
            Do $$$AssertEquals(wf.ReleasePolicy _ "|" _ wf.ExpectedVersion, "incident|7", "another receiver's case keeps the incident's approval and the expected version")
            Continue
        }
        Do $$$AssertEquals(wf.ReleasePolicy _ "|" _ wf.ExpectedVersion, "path|", "a FHIR case is released on its own path, at no expected version")
        Do $$$AssertStatusOK(wf.OnEvidence(case, ..Evidence(case, ..Resend())), "the evidence is taken")
        Do $$$AssertEquals(wf.Policy _ " " _ wf.Last(), "approval FHIR Gate|Shutter.Msg.FHIRGateRequest|fhir:gate:proposal", "the plan goes to the FHIR gate for a person's approval")
        Do ..Step(wf, "fhir:gate:proposal", ..Gate(case, wf, "proposal"))
        Do $$$AssertEquals(case.State, "awaiting_approval", "and waits for one")
        Do $$$AssertEquals(..Count("Approval", case) _ " " _ ..Count("ExecutionAttempt", case) _ " " _ wf.WardOperations, "0 0 0", "no approval was given under the incident's and nothing was sent")
    }
}

/// A refresh of the evidence under a standing approval voids a FHIR case's approval, even when nothing material
/// changed, and the case is planned again; another receiver's approval stands as before.
Method TestARefreshUnderAnApprovalRevokesIt()
{
    Do ..Approved(.wf, .case)
    Set approvalId = wf.ApprovalId, planId = wf.PlanId
    Set wf.Refreshing = 1
    Set evidence = ..Evidence(case)
    Do $$$AssertEquals(##class(Shutter.Store.Approval).%OpenId(approvalId).MaterialDigest, case.CurrentSnapshot.MaterialDigest, "the fresh evidence is materially the approved one")
    Do $$$AssertNotEquals(case.CurrentSnapshot.MaterialDigest, "", "and has a material digest")
    Do $$$AssertStatusOK(wf.OnEvidence(case, evidence), "the refreshed evidence is taken")
    Do $$$AssertEquals(##class(Shutter.Store.Approval).%OpenId(approvalId).Revoked, 1, "the approval is void")
    Do $$$AssertEquals(wf.MainPreflights, 0, "nothing is dispatched under it")
    Do $$$AssertTrue((wf.PlanId '= "") && (wf.PlanId '= planId) && (wf.ApprovalId = "") && (wf.FHIRBindingId = ""), "the case is planned again, with no approval and no binding carried (" _ wf.PlanId _ ", " _ wf.ApprovalId _ ", " _ wf.FHIRBindingId _ ")")
    Do $$$AssertEquals(case.State _ " " _ wf.Last(), "proposed FHIR Gate|Shutter.Msg.FHIRGateRequest|fhir:gate:proposal", "and the new plan goes to the FHIR gate")

    // Another receiver, the same refresh: the approval stands and the dispatch goes on.
    Set adt = ..NewCase("rules", 0)
    Set snap = ..AdtSnapshot(adt)
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(adt, snap, {"disposition": "resend", "summary": "resend", "action": {"type": "resend", "operation_key": (adt.OperationKey), "expected_version": 3}}, "rules", .plan), "its plan")
    Do $$$AssertStatusOK(##class(Shutter.Store.Approval).Create(adt, plan, snap, "ut-policy", "", 3, ..#APPROVER, "approved", "", "", 900, .approval), "its approval")
    Set wf = ..Workflow(adt)
    Set wf.PlanId = plan.%Id(), wf.ApprovalId = approval.%Id(), wf.Refreshing = 1
    Set evidence = ##class(Shutter.Msg.EvidenceResult).%New()
    Set evidence.SnapshotId = snap.%Id(), evidence.Digest = snap.Digest, evidence.SummaryJSON = snap.Summary
    Do $$$AssertStatusOK(wf.OnEvidence(adt, evidence), "the refreshed evidence of the other receiver's case is taken")
    Do $$$AssertEquals(approval.Revoked _ " " _ wf.MainPreflights _ " " _ adt.State, "0 1 approved", "its approval stands and the dispatch goes on")
}

/// Every handler works from the store and the identifiers alone: between any two steps the workflow instance is
/// thrown away and a new one given only the identifiers the stored one keeps, as after a restart.
Method TestEachHandlerOnAFreshInstance()
{
    Do ..ToTheEnd(1, .wf, .case)
    Do $$$AssertEquals(case.State, "resolved", "the case resolved, each step on an instance of its own")
    Do $$$AssertEquals(..KeysSoFar, "fhir:gate:proposal fhir:approval approval:timeout:1 fhir:preflight fhir:gate:dispatch fhir:execute fhir:verify", "every step sent what follows it")
    Do $$$AssertEquals(..MainCalls, 0, "and none asked the workflow's own path for anything")
    Do $$$AssertEquals(..Count("ExecutionAttempt", case) _ " " _ ..Count("Approval", case), "1 1", "one approval and one attempt are on record")
}

/// The call to FHIR Out failed with the fence row sent: the update may have landed, so the attempt is uncertain and
/// the verifier reads what the receiver holds. Never a failure, and never "not applied".
Method TestAnExecuteErrorWithASentFenceVerifies()
{
    Do ..Executing(.wf, .case)
    Set fence = ..Fence(wf, case, 1)
    Do ..Fail(wf, "fhir:execute", "the job of FHIR Out ended")
    Do $$$AssertEquals(case.State, "verifying", "the case is verifying")
    Do $$$AssertEquals(wf.Last(), "FHIR Verifier|Shutter.Msg.VerifyRequest|fhir:verify", "the verifier is asked")
    Set attempt = ##class(Shutter.Store.ExecutionAttempt).%OpenId(wf.AttemptId)
    Do $$$AssertEquals(attempt.Outcome _ "|" _ +attempt.HttpStatus _ "|" _ attempt.ApprovalGetObjectId(), "uncertain|0|" _ wf.ApprovalId, "the attempt is uncertain, with no HTTP answer, under the approval")
    Do $$$AssertEquals(wf.LastRequest().AttemptId _ "|" _ wf.LastRequest().PlanId, attempt.%Id() _ "|" _ wf.PlanId, "and it is the attempt the verifier is given")
    Do fence.%Reload()
    Do $$$AssertEquals(fence.ExecutionAttemptId, attempt.%Id(), "the fence row names it")
    Do $$$AssertEquals(##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId).Revoked, 0, "the approval is not revoked while the outcome is being read")
    Do $$$AssertNotTrue(..AllEvents(case) [ "not applied", "nothing says not applied")
}

/// The call to FHIR Out failed with nothing sent (no fence row, or one still unsent): the case blocks, the approval is
/// void, and the attempt says error.
Method TestAnExecuteErrorUnsentBlocksAndRevokes()
{
    For row = 0, 1 {
        Do ..Executing(.wf, .case)
        If row Do ..Fence(wf, case, 0)
        Set sends = +$GET(wf.Sent)
        Do ..Fail(wf, "fhir:execute", "FHIR Out is not there")
        Do $$$AssertEquals(case.State _ "|" _ case.Headline, "blocked|Blocked: the update was not applied", $SELECT(row: "an unsent fence row", 1: "no fence row") _ ": the case blocks")
        Do $$$AssertEquals(##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId).Revoked, 1, "the approval is void")
        Set attempt = ##class(Shutter.Store.ExecutionAttempt).%OpenId(wf.AttemptId)
        Do $$$AssertEquals(attempt.Outcome _ "|" _ +attempt.HttpStatus, "error|0", "the attempt says error")
        Do $$$AssertEquals(##class(Shutter.Util.Json).Parse(attempt.ResponseJSON).sent, 0, "with nothing sent")
        Do $$$AssertEquals(+$GET(wf.Sent), sends, "nothing more is asked of anyone")
        Do $$$AssertEquals(..Code(case), "FHIR_WRITE_REFUSED", "the reason: " _ ..Event(case, "blocked"))
    }
}

/// A second request on a spent fence is answered uncertain by FHIR Out: the case verifies, and the fence row keeps
/// the one attempt it has.
Method TestASpentFenceAnswerGoesToVerifying()
{
    Do ..Executing(.wf, .case)
    Do ..Fence(wf, case, 1)
    Set answer = ..Wrote("uncertain", 0, 1, "fhir_already_sent")
    Set answer.Error = "This approval's update was already sent and no answer is recorded, so it may have been applied. Nothing was sent again"
    Do ..Step(wf, "fhir:execute", answer)
    Do $$$AssertEquals(case.State _ " " _ wf.Last(), "verifying FHIR Verifier|Shutter.Msg.VerifyRequest|fhir:verify", "an uncertain answer is verified")
    Set first = wf.AttemptId
    Do $$$AssertEquals(##class(Shutter.Store.ExecutionAttempt).%OpenId(first).Outcome, "uncertain", "its attempt is uncertain")
    // The same answer once more, as a redelivery brings it: that row is the attempt.
    Do ..Step(wf, "fhir:execute", ..Wrote("uncertain", 0, 1, "fhir_already_sent"))
    Do $$$AssertEquals(wf.AttemptId _ " " _ ..Count("ExecutionAttempt", case), first _ " 1", "a fence row that names an attempt gets no second one")
    Do $$$AssertEquals(##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId).Revoked, 0, "and the approval is not revoked before the outcome is read")
}

/// An error from the verifier after the update was sent ends the case as an outcome nobody knows, with the approval
/// void: never as a failed workflow with the approval standing. Before anything is sent an item's error blocks the
/// case; an error of the approval task is the workflow's own to handle.
Method TestAVerifierErrorAfterASentWriteIsUnknown()
{
    Do ..Verifying(.wf, .case)
    Do ..Fail(wf, "fhir:verify", "the verifier could not be reached")
    Do $$$AssertEquals(case.State _ "|" _ case.Headline, "escalated|Escalated: the update's outcome is unknown", "the case goes to a person")
    Do $$$AssertEquals(..Event(case, "escalated"), "A FHIR item failed after the update was sent: ERROR #5001: the verifier could not be reached. Whether the receiver applied it is unknown; a person checks at the receiver (FHIR_WRITE_OUTCOME_UNKNOWN)", "in these words")
    Do $$$AssertEquals(##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId).Revoked, 1, "the approval is void")
    Do $$$AssertEquals(..Code(case), "FHIR_WRITE_OUTCOME_UNKNOWN", "the reason")

    // A handler that fails after the update was sent ends the same way, and the workflow sees no error.
    Do ..Verifying(.wf, .case)
    Set wf.FailSend = "no production"
    Do ..Step(wf, "fhir:verify:retry")
    Do $$$AssertEquals(case.State _ "|" _ ..Code(case), "escalated|FHIR_WRITE_OUTCOME_UNKNOWN", "a step that fails after the update was sent: unknown, for a person")
    Do $$$AssertEquals(##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId).Revoked, 1, "with the approval void")

    // A handler that fails before anything was sent: the error is the workflow's, and the approval is void.
    Do ..Approved(.wf, .case)
    Set wf.FailSend = "no production", read = ..Read(), response = ""
    Do $$$AssertStatusNotOK(wf.OnResponse("", .response, "", read, "fhir:preflight"), "a step that fails before the update was sent is an error of the workflow")
    If read.%Id() '= "" Set i%Reads(read.%Id()) = ""
    Do $$$AssertEquals(case.State _ " " _ ##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId).Revoked, "failed 1", "the case fails as the workflow fails it, and its approval is void")
    Do $$$AssertTrue(..Event(case, "failed") [ "Workflow error at fhir:preflight", "in the workflow's own words: " _ ..Event(case, "failed"))

    // Before anything was sent: the gate at the dispatch answers with an error status.
    Do ..Approved(.wf, .case)
    Do ..Fail(wf, "fhir:gate:dispatch", "the FHIR gate is not there")
    Do $$$AssertEquals(case.State _ "|" _ case.Headline, "blocked|Blocked: a FHIR item failed", "an item's error before the write blocks the case")
    Do $$$AssertEquals(..Event(case, "blocked"), "A FHIR item answered with an error before anything was sent: ERROR #5001: the FHIR gate is not there (FHIR_ITEM_ERROR)", "in these words")
    Do $$$AssertEquals(##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId).Revoked _ " " _ ..Code(case), "1 FHIR_ITEM_ERROR", "the approval is void, and the reason is the item's error")

    // The gate that answers what it could not decide, with no decision: the same stop.
    Do ..Planned("rules", .wf, .case)
    Set undecided = ##class(Shutter.Msg.GateResult).%New()
    Set undecided.Outcome = "unknown", undecided.Error = "Unknown plan 0"
    Do ..Step(wf, "fhir:gate:proposal", undecided)
    Do $$$AssertEquals(case.State _ "|" _ ..Code(case), "blocked|FHIR_ITEM_ERROR", "a gate answer with an error and no decision is an item's error")

    // The approval task is the workflow's own.
    Do ..Awaiting(.wf, .case)
    Do ..Fail(wf, "fhir:approval", "the Workflow engine refused the task")
    Do $$$AssertEquals(case.State, "failed", "an error of the approval task fails the case, as it does for every receiver")
    Do $$$AssertTrue(..Event(case, "failed") [ "Error from the call fhir:approval", "in the workflow's own words: " _ ..Event(case, "failed"))
}

/// What a person reads before approving says what will be done and never promises a rehearsal: not the headline, not
/// the task, not any event of the case.
Method TestHeadlineAndTaskNeverSayRehearsal()
{
    Do ..Awaiting(.wf, .case)
    Set task = wf.Requests.GetAt(2)
    Do $$$AssertEquals($CLASSNAME(task) _ "|" _ $LIST(wf.Sent(2), 1) _ "|" _ $LIST(wf.Sent(2), 3), "EnsLib.Workflow.TaskRequest|" _ wf.ApprovalTarget _ "|fhir:approval", "the task goes to the approvers")
    Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
    Do $$$AssertEquals(task.%Subject, "Shutter " _ case.CaseId _ ": approve plan v" _ plan.Version _ " (resend)", "under the subject every approval task has")
    Do $$$AssertEquals(task.%Actions _ "|" _ task.%FormFields, "Approve,Reject|PlanDigest,Comment", "with its actions and form")
    Set text = task.%Message, lf = $CHAR(10)
    For words = case.Headline, task.%Subject, text, ..AllEvents(case) {
        Do $$$AssertNotTrue($ZCONVERT(words, "L") [ "rehears", "no rehearsal is spoken of: " _ $EXTRACT(words, 1, 120))
        Do $$$AssertNotTrue(words [ "Resend the", "nor a resend of the message: " _ $EXTRACT(words, 1, 120))
    }
    Do $$$AssertEquals($PIECE(text, lf, 1), case.Headline, "the task begins with the headline")
    Do $$$AssertEquals($PIECE(text, lf, 2), "Exact action: one update of Encounter enc-1, location WARD-A to WARD-B, sent with If-Match on the version read at " _ case.CurrentSnapshot.TakenAt _ " (ETag W/""1""). This server software refused a changed version when it was measured.", "then the exact action")
    Do $$$AssertEquals($PIECE(text, lf, 3) _ lf _ $PIECE(text, lf, 4), "Plan digest: " _ plan.Digest _ lf _ "Snapshot digest: " _ case.CurrentSnapshot.Digest, "the two digests")
    Do $$$AssertEquals($PIECE(text, lf, 5), "No dry run exists for this receiver.", "that nothing was rehearsed")
    Do $$$AssertEquals($PIECE(text, lf, 6), "After this update, do not resend the original HL7 message from the engine.", "and what not to do afterwards")
    Do $$$AssertTrue(text [ "paste the plan digest above into the PlanDigest field", "how to approve from the inbox")
    Do $$$AssertTrue(text [ ("Unanswered after " _ wf.WaitWords(wf.ApprovalWaitSeconds)), "and how long the task waits")
    Do $$$AssertEquals(..Event(case, "awaiting_approval"), "No dry run exists for this receiver; asking an approver for the exact plan", "the case says why it waits")
    Do $$$AssertEquals(wf.Requests.GetAt(3).Timeout _ "|" _ $LIST(wf.Sent(3), 1) _ "|" _ $LIST(wf.Sent(3), 3), wf.ApprovalWaitSeconds _ "|Ens.Alarm|approval:timeout:" _ wf.Round, "the wait is bounded by the workflow's own alarm")
    Set binding = ##class(Shutter.Store.FHIRBinding).%OpenId(wf.FHIRBindingId)
    Do $$$AssertEquals(binding.PlanId _ "|" _ binding.ApprovalId _ "|" _ binding.EncounterId _ "|" _ binding.ExpectedEtag, plan.%Id() _ "||enc-1|W/""1""", "the update was sealed before the task was sent, tied to no approval yet")
}

/// Every stop of the flow names its own reason: the code its event text ends with, or the gate's failing row for the
/// two stops the gate explains. An earlier round's failing row is never the reason of a later stop.
Method TestEveryStopNamesItsCode()
{
    // 1. The items are missing.
    Set ^Shutter.Config("production") = "ShutterTest.NoSuchFhirFlow"
    Set case = ..NewCase("rules"), wf = ..Workflow(case)
    Do $$$AssertStatusOK(wf.OnEvidence(case, ..Evidence(case)), "stop 1: the evidence is taken")
    Do ..Stopped(case, 1, "blocked", "Blocked: the FHIR items are missing or disagree", "The production cannot reach this FHIR receiver: No production ShutterTest.NoSuchFhirFlow. Nothing was read or sent (FHIR_ITEMS_MISSING)", "FHIR_ITEMS_MISSING")
    Do $$$AssertEquals(+$GET(wf.Sent), 0, "stop 1: nothing was sent to anyone")
    Set ^Shutter.Config("production") = ..#PRODUCTION

    // 2. A plan that asks for a person, with what the gate noted.
    Do ..Planned("policy", .wf, .case, {"decision": "person", "entry": "E19", "matches": []})
    Set summary = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId).Summary
    Set noted = ..Gate(case, wf, "proposal", "unknown", [(..Row("ordering", "unknown", "FHIR_ENGINE_NOT_IN_SCOPE"))])
    Do ..Step(wf, "fhir:gate:proposal", noted)
    Do ..Stopped(case, 2, "escalated", "", "The plan asks for a person: " _ summary _ " (the gate noted: " _ noted.Summary _ ")", "FHIR_PLAN_NEEDS_PERSON")

    // 3. The proposal gate did not pass: its failing row is the reason.
    Do ..Planned("rules", .wf, .case)
    Set blocked = ..Gate(case, wf, "proposal", "block", [(..Row("identity", "pass", "FHIR_IDENTITY_MATCHES")), (..Row("state_transition", "block", "FHIR_STATUS_NOT_IN_PROGRESS"))])
    Do ..Step(wf, "fhir:gate:proposal", blocked)
    Do ..Stopped(case, 3, "blocked", "Blocked by the FHIR gate: " _ blocked.Summary, "The FHIR gate did not pass the plan; a person must decide", "FHIR_STATUS_NOT_IN_PROGRESS")

    // 4. A pass on a plan that writes nothing and asks for nobody.
    Set case = ..NewCase("rules"), wf = ..Workflow(case)
    Do ..Evidence(case)
    Do $$$AssertStatusOK(wf.AdoptPlan(case, {"disposition": "superseded", "summary": "A later event moved the encounter on", "action": {"type": "none"}}, "rules"), "stop 4: a plan that writes nothing is adopted")
    Do ..Step(wf, "fhir:gate:proposal", ..Gate(case, wf, "proposal"))
    Do ..Stopped(case, 4, "escalated", "Escalated: over FHIR nothing closes by itself", "Over FHIR Shutter closes no case without a person or a verified update; a person decides (FHIR_PLAN_NEEDS_PERSON)", "FHIR_PLAN_NEEDS_PERSON")
    Do $$$AssertEquals(wf.MainVerifies, 0, "stop 4: the workflow's own verifier is not asked")

    // 5. The stop: the control's own words, and the reason the workflow gives them for every receiver.
    Do ..Planned("rules", .wf, .case)
    Set c = ##class(Shutter.Util.RecoveryControl).Control()
    Set c.StopLatched = 1, c.StoppedAt = ##class(Shutter.Util.Time).NowUTC(), c.StoppedBy = ..#APPROVER, c.StopReason = "unit test"
    Do $$$AssertStatusOK(c.%Save(), "stop 5: recovery is stopped")
    Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId), passed = ..Gate(case, wf, "proposal")
    Set words = ##class(Shutter.Store.ShadowObservation).Words(plan, passed)
    Do ..Step(wf, "fhir:gate:proposal", passed)
    Do $$$AssertTrue(words [ "Nothing sent: Shutter recovery was stopped", "stop 5: the control refuses (" _ words _ ")")
    Do ..Stopped(case, 5, "escalated", words, words, ##class(Shutter.API.Dispatch).ReasonFromEvent(words, "escalated"))
    Do $$$AssertEquals(+$GET(wf.Sent) _ " " _ wf.FHIRBindingId, "1 ", "stop 5: no task is sent and nothing is sealed")
    Set c.StopLatched = 0, c.StoppedAt = "", c.StoppedBy = "", c.StopReason = ""
    Do $$$AssertStatusOK(c.%Save(), "the stop is gone")

    // 6. The update could not be sealed: a message that names a bed, then evidence that names no Patient.
    Set case = ..NewCase("rules")
    Set case.Bed = "12"
    Do $$$AssertStatusOK(case.%Save(), "stop 6: the message names a bed")
    Set wf = ..Workflow(case)
    Do $$$AssertStatusOK(wf.OnEvidence(case, ..Evidence(case)), "stop 6: the evidence is taken")
    Do ..Step(wf, "fhir:gate:proposal", ..Gate(case, wf, "proposal"))
    Do ..Stopped(case, 6, "blocked", "Blocked: the update could not be sealed for approval", "The update could not be sealed for approval: the update could not be built (bed, PV1-3) (FHIR_BED_MOVE_UNSUPPORTED)", "FHIR_BED_MOVE_UNSUPPORTED")
    Do $$$AssertEquals(+$GET(wf.Sent) _ " " _ wf.FHIRBindingId, "1 ", "stop 6: no task is sent and nothing is sealed")
    Set case = ..NewCase("rules"), wf = ..Workflow(case)
    Do $$$AssertStatusOK(wf.OnEvidence(case, ..Evidence(case, "", "patient")), "stop 6: evidence with no Patient reference is taken")
    Do ..Step(wf, "fhir:gate:proposal", ..Gate(case, wf, "proposal"))
    Do $$$AssertEquals(case.State _ "|" _ ..Code(case), "blocked|FHIR_NO_BINDING", "stop 6: a seal that fails names FHIR_NO_BINDING: " _ ..Event(case, "blocked"))

    // 7. The read before the write failed, after its retries.
    Do ..Approved(.wf, .case)
    Set waits = ""
    For try = 1:1:4 {
        Set unread = ##class(Shutter.Msg.FHIRReadResult).%New()
        If try # 2 { Set unread.Error = "FHIR Receiver could not connect" } Else { Set unread.PartsJSON = {"observed_at": "2026-11-07T10:20:00Z", "encounter": {"http_status": 0, "error": "not read: no answer"}}.%ToJSON() }
        Do ..Step(wf, "fhir:preflight", unread)
        If try < 4 {
            Do $$$AssertEquals(case.State _ " " _ wf.Last(), "approved Ens.Alarm|Ens.AlarmRequest|fhir:preflight:retry", "stop 7: try " _ try _ " is made again")
            Set waits = waits _ " " _ wf.LastRequest().Timeout
            Do ..Step(wf, "fhir:preflight:retry")
            Do $$$AssertEquals(wf.Last(), "FHIR Receiver|Shutter.Msg.FHIRRead|fhir:preflight", "stop 7: the alarm asks for the read again")
        }
    }
    Do $$$AssertEquals(waits, " 10 20 40", "stop 7: after 10, 20 and 40 seconds")
    Do ..Stopped(case, 7, "blocked", "Blocked at dispatch: the receiver could not be read", "The receiver could not be read just before the write, in 4 tries. The approval is void and nothing was sent (FHIR_RECEIVER_UNREADABLE)", "FHIR_RECEIVER_UNREADABLE", wf)

    // 8. The dispatch gate did not pass: its failing row is the reason, not the proposal's unknown before it.
    Do ..Planned("rules", .wf, .case)
    Do ..Step(wf, "fhir:gate:proposal", ..Gate(case, wf, "proposal", "unknown", [(..Row("evidence", "unknown", "STALE_EVIDENCE"))]))
    Do $$$AssertEquals(case.State _ " " _ wf.Last() _ " " _ wf.LastRequest().Timeout _ " [" _ wf.PlanId _ "]", "gated Ens.Alarm|Ens.AlarmRequest|refresh:retry 10 []", "stop 8: an unknown a fresh read can answer collects the evidence again, with the plan dropped")
    Do $$$AssertStatusOK(wf.OnEvidence(case, ..Evidence(case)), "stop 8: the fresh evidence is taken")
    Do ..Step(wf, "fhir:gate:proposal", ..Gate(case, wf, "proposal"))
    Do ..Step(wf, "fhir:approval", ..Approve(wf))
    Do ..ReadStep(wf)
    Do ..Step(wf, "fhir:gate:dispatch", ..Gate(case, wf, "dispatch", "unknown", [(..Row("evidence", "unknown", "STALE_EVIDENCE"))]))
    Do $$$AssertEquals(case.State _ " " _ wf.Last() _ " " _ wf.LastRequest().Timeout _ " " _ ##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId).Revoked, "approved Ens.Alarm|Ens.AlarmRequest|fhir:preflight:retry 10 0", "stop 8: an unknown a fresh read can answer at the dispatch reads the receiver again, under the approval")
    Do ..Step(wf, "fhir:preflight:retry")
    Do ..ReadStep(wf)
    Set blocked = ..Gate(case, wf, "dispatch", "block", [(..Row("concurrency", "block", "FHIR_VERSION_CHANGED"))])
    Do ..Step(wf, "fhir:gate:dispatch", blocked)
    Do ..Stopped(case, 8, "blocked", "Blocked at dispatch: " _ blocked.Summary, "The FHIR gate did not pass the plan at dispatch. The approval is void; a reinvestigation reads fresh evidence and asks again", "FHIR_VERSION_CHANGED", wf)

    // 9 and 10. The write was refused: an earlier round's failing row is not the reason.
    For outcome = "version_conflict", "refused", "error" {
        Do ..Planned("rules", .wf, .case)
        Do ..Step(wf, "fhir:gate:proposal", ..Gate(case, wf, "proposal", "unknown", [(..Row("evidence", "unknown", "STALE_EVIDENCE"))]))
        Do $$$AssertStatusOK(wf.OnEvidence(case, ..Evidence(case)), "the fresh evidence is taken")
        Do ..Step(wf, "fhir:gate:proposal", ..Gate(case, wf, "proposal"))
        Do ..Step(wf, "fhir:approval", ..Approve(wf))
        Do ..ReadStep(wf)
        Do ..Step(wf, "fhir:gate:dispatch", ..Gate(case, wf, "dispatch"))
        If outcome = "version_conflict" {
            Do ..Fence(wf, case, 1, 412, "version_conflict")
            Do ..Step(wf, "fhir:execute", ..Wrote("version_conflict", 412, 1))
            Do ..Stopped(case, 9, "blocked", "Blocked: the Encounter changed before the update", "The receiver refused the update: the Encounter changed after it was read (HTTP 412). The approval is void and nothing is sent again without fresh evidence and a new approval (FHIR_WRITE_CONFLICT)", "FHIR_WRITE_CONFLICT", wf)
        } ElseIf outcome = "refused" {
            Do ..Step(wf, "fhir:execute", ..Wrote("refused", 0, 0, "fhir_dispatch_stale"))
            Do ..Stopped(case, 10, "blocked", "Blocked: the update was not applied", "The update was not applied: fhir_dispatch_stale, no HTTP answer (FHIR_WRITE_REFUSED)", "FHIR_WRITE_REFUSED", wf)
        } Else {
            // A plain refusal of the receiver's has no reason code of its own: the outcome stands in its place.
            Do ..Fence(wf, case, 1, 400, "error")
            Do ..Step(wf, "fhir:execute", ..Wrote("error", 400, 1))
            Do ..Stopped(case, 10, "blocked", "Blocked: the update was not applied", "The update was not applied: error, HTTP 400 (FHIR_WRITE_REFUSED)", "FHIR_WRITE_REFUSED", wf)
        }
        Set attempt = ##class(Shutter.Store.ExecutionAttempt).%OpenId(wf.AttemptId)
        Do $$$AssertEquals(attempt.Outcome _ " " _ ..Count("ExecutionAttempt", case), outcome _ " 1", outcome _ ": one attempt row says so")
        Do $$$AssertEquals(wf.MainVerifies + wf.Evidence, 0, outcome _ ": nothing is verified and nothing planned again by itself")
    }
    // 11 is TestTheSixOutcomes, 12 and 13 are TestAVerifierErrorAfterASentWriteIsUnknown.
}

/// The six outcomes of the verifier's walk, and the settle schedule: a walk that asks for another read is made again
/// after 10, 20 and 40 seconds, and is final after that.
Method TestTheSixOutcomes()
{
    Set by = "system: "
    // judged, the stored word, retry, the state, the headline, the code, why the approval is void ("" when it stands)
    Set rows = $LISTBUILD(
        $LISTBUILD("verified", "verified", 0, "resolved", "", "", ""),
        $LISTBUILD("verified_continued", "verified", 0, "resolved", "", "", ""),
        $LISTBUILD("committed_review", "unresolved", 0, "escalated", "Escalated: the update is present, the current record needs review", "FHIR_COMMITTED_NEEDS_REVIEW", ""),
        $LISTBUILD("unknown", "unresolved", 0, "escalated", "Escalated: the update's outcome is unknown", "FHIR_WRITE_OUTCOME_UNKNOWN", "the update's outcome is unknown, and its one write is spent"),
        $LISTBUILD("not_found", "not_committed", 0, "escalated", "Escalated: the update is not in the history read", "FHIR_WRITE_NOT_FOUND", "the update is not in the history read, and its one write is spent"),
        $LISTBUILD("failed", "failed", 0, "escalated", "Escalated: the receiver's record contradicts the update", "FHIR_WRITE_CONTRADICTED", "the receiver's record contradicts the update"))
    For i = 1:1:$LISTLENGTH(rows) {
        Set $LISTBUILD(judged, word, retry, state, headline, code, void) = $LIST(rows, i)
        Do ..Verifying(.wf, .case)
        Set before = case.Headline, sentence = "The Judge's sentence for " _ judged _ "."
        Do ..Step(wf, "fhir:verify", ..Verified(word, judged, retry, sentence))
        Do $$$AssertEquals(case.State _ "|" _ case.Outcome, state _ "|" _ sentence, judged _ ": the case is " _ state _ ", its outcome the verifier's sentence")
        Do $$$AssertEquals(..Event(case, state), sentence _ $SELECT(code = "": "", 1: " (" _ code _ ")"), judged _ ": the event is the sentence" _ $SELECT(code = "": " as it is", 1: " and the code"))
        Do $$$AssertEquals(case.Headline, $SELECT(headline = "": before, 1: headline), judged _ ": the headline")
        Set approval = ##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId)
        Do $$$AssertEquals(approval.Revoked _ "|" _ approval.RevokedBy, $SELECT(void = "": "0|", 1: "1|" _ by _ void), judged _ ": the approval " _ $SELECT(void = "": "stands", 1: "is void"))
        If code '= "" Do $$$AssertEquals(..Code(case), code, judged _ ": the reason")
        Do $$$AssertEquals(wf.Keys(), "", judged _ ": nothing follows by itself")
    }

    // The settle schedule: three more walks, then the unknown is final.
    Do ..Verifying(.wf, .case)
    Set waits = ""
    For walk = 1:1:4 {
        Do ..Step(wf, "fhir:verify", ..Verified("unresolved", "unknown", 1, "The history could not be read yet."))
        Quit:walk=4
        Do $$$AssertEquals(case.State _ " " _ wf.Last(), "verifying Ens.Alarm|Ens.AlarmRequest|fhir:verify:retry", "walk " _ walk _ " asks for another")
        Set waits = waits _ " " _ wf.LastRequest().Timeout
        Do ..Step(wf, "fhir:verify:retry")
        Do $$$AssertEquals(wf.Last() _ " " _ wf.LastRequest().AttemptId, "FHIR Verifier|Shutter.Msg.VerifyRequest|fhir:verify " _ wf.AttemptId, "and the alarm asks the verifier again, for the same attempt")
    }
    Do $$$AssertEquals(waits _ " | " _ wf.Refreshes, " 10 20 40 | 3", "after 10, 20 and 40 seconds")
    Do $$$AssertEquals(case.State _ "|" _ case.Headline _ "|" _ ..Code(case), "escalated|Escalated: the update's outcome is unknown|FHIR_WRITE_OUTCOME_UNKNOWN", "a walk that still asks for another read after the last is the unknown that is final")
    Do $$$AssertEquals(##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId).RevokedBy, "system: the update's outcome is unknown, and its one write is spent", "with the approval void")

    // An answer that says verified without the verifier's own word behind it resolves nothing.
    Do ..Verifying(.wf, .case)
    Set odd = ##class(Shutter.Msg.VerifyResult).%New()
    Set odd.Outcome = "verified", odd.Summary = "Committed and current", odd.DetailJSON = "{}"
    Do ..Step(wf, "fhir:verify", odd)
    Do $$$AssertEquals(case.State _ "|" _ ..Code(case), "escalated|FHIR_WRITE_OUTCOME_UNKNOWN", "an answer of another verifier's shape is no verification of a FHIR update")
}

/// The case's reason is the code a stop of the flow closes its own text with, never a code quoted inside other
/// words: an approver's comment that names one, on any case, is still a rejection, and an earlier round's failing
/// The FHIR items found missing after the approval, when the read before the write has been made: the stop voids the
/// approval with its reason, as every stop at the dispatch does, and does not say that nothing was read.
Method TestItemsMissingAtTheDispatchVoidTheApproval()
{
    Do ..Approved(.wf, .case)
    Set wf = ..Carry(wf)
    Set ^Shutter.Config("production") = "ShutterTest.NoSuchFhirFlow"
    Do ..Step(wf, "fhir:preflight", ..Read())
    Set ^Shutter.Config("production") = ..#PRODUCTION
    Do ..Stopped(case, 1, "blocked", "Blocked: the FHIR items are missing or disagree", "The production cannot reach this FHIR receiver: No production ShutterTest.NoSuchFhirFlow. The approval is void and nothing was sent (FHIR_ITEMS_MISSING)", "FHIR_ITEMS_MISSING", wf)
    Do $$$AssertEquals(##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId).RevokedBy, "system: the FHIR items are missing or disagree", "the approval says why it is void")
    Do $$$AssertTrue(..AllEvents(case) [ "The read before the write was made", "the read before the write was made")
    Do $$$AssertTrue(..AllEvents(case) '[ "Nothing was read", "and no event says that nothing was read")
    Do $$$AssertEquals(wf.Keys(), "", "nothing follows by itself: no gate request, no update")
}

/// The verification's further walks follow their own schedule, whatever Case Workflow's MaxRefreshes is: the same
/// three, after 10, 20 and 40 seconds, and then the walk that still asks for another read is final.
Method TestTheVerifyWalksKeepTheirOwnSchedule()
{
    For max = 1, 2, 3, 5 {
        Do ..Verifying(.wf, .case)
        Set wf.MaxRefreshes = max
        Set waits = "", walks = 0
        For walk = 1:1:8 {
            Do ..Step(wf, "fhir:verify", ..Verified("unresolved", "unknown", 1, "The history could not be read yet."))
            Set walks = walks + 1
            Quit:case.State'="verifying"
            Set waits = waits _ " " _ wf.LastRequest().Timeout
            Do ..Step(wf, "fhir:verify:retry")
        }
        Do $$$AssertEquals(walks _ " |" _ waits, "4 | 10 20 40", "MaxRefreshes " _ max _ ": four walks, the further ones after 10, 20 and 40 seconds")
        Do $$$AssertEquals(case.State _ "|" _ ..Code(case), "escalated|FHIR_WRITE_OUTCOME_UNKNOWN", "MaxRefreshes " _ max _ ": then the unknown is final")
        Do $$$AssertTrue(..AllEvents(case) [ "verifying again in 40 s (3 of 3)", "MaxRefreshes " _ max _ ": the case counts the walks of the verification's own schedule")
    }
}

/// row of the gate stays the reason where it was.
Method TestAQuotedCodeIsNotTheReason()
{
    Set d = "Shutter.API.Dispatch"
    Set rows = 0
    Set rows($INCREMENT(rows)) = $LISTBUILD("Rejected by ut.approver: not like (FHIR_ALREADY_THERE) last week", "blocked", "REJECTED_BY_APPROVER", 0)
    Set rows($INCREMENT(rows)) = $LISTBUILD("Rejected by ut.approver: as it was last week (FHIR_ALREADY_THERE)", "blocked", "REJECTED_BY_APPROVER", 0)
    Set rows($INCREMENT(rows)) = $LISTBUILD("The gate did not pass the dispatch: we saw (FHIR_ALREADY_THERE) once, and the record moved on", "blocked", "BLOCKED", 0)
    Set rows($INCREMENT(rows)) = $LISTBUILD("The receiver refused the update: the Encounter changed after it was read (HTTP 412). The approval is void and nothing is sent again without fresh evidence and a new approval (FHIR_WRITE_CONFLICT)", "blocked", "FHIR_WRITE_CONFLICT", 1)
    Set rows($INCREMENT(rows)) = $LISTBUILD("The plan asks for a person: Over FHIR an update is proposed only where the catalogue's one matching entry says resend; here no catalogue entry matches this evidence, so a person decides (FHIR_PLAN_NEEDS_PERSON) (the gate noted: Blocked: identity FHIR_PATIENT_MISMATCH (policy fhir-1, stage proposal))", "escalated", "FHIR_PLAN_NEEDS_PERSON", 1)
    Set rows($INCREMENT(rows)) = $LISTBUILD("The update could not be sealed for approval: the update could not be built (bed, PV1-3) (FHIR_BED_MOVE_UNSUPPORTED)", "blocked", "FHIR_BED_MOVE_UNSUPPORTED", 1)
    For i = 1:1:rows {
        Set text = $LIST(rows(i), 1)
        Do $$$AssertEquals($CLASSMETHOD(d, "ReasonFromEvent", text, $LIST(rows(i), 2)), $LIST(rows(i), 3), "the reason of: " _ $EXTRACT(text, 1, 70))
        Do $$$AssertEquals(''$CLASSMETHOD(d, "StoppedAfterTheGate", text), $LIST(rows(i), 4), "whether it stopped after the gate: " _ $EXTRACT(text, 1, 70))
    }
}

/// A convened board sends no agent request for a FHIR case, in any mode: the case is planned as every FHIR case is,
/// and says so.
Method TestAConvenedBoardSendsNoAgentRequest()
{
    For mode = "board", "policy", "rules" {
        For forced = 1, 0 {
            Set case = ..NewCase(mode), wf = ..Workflow(case)
            Set wf.ForceBoard = forced, wf.ConvenedBy = $SELECT(forced: "ut.judge", 1: "")
            Do $$$AssertStatusOK(wf.OnEvidence(case, ..Evidence(case, ..Resend())), mode _ ", board asked for " _ forced _ ": the evidence is taken")
            Do $$$AssertEquals(wf.Boards _ " " _ wf.Classes() _ " " _ wf.MainGates, "0 Shutter.Msg.FHIRGateRequest 0", mode _ ": no board is convened and the only request is the FHIR gate's")
            Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
            Do $$$AssertEquals(plan.CreatedBy, $SELECT(mode = "rules": "rules", 1: "policy:E2"), mode _ ": the plan is the rules' or the entry's, never a board's")
            Do $$$AssertEquals(..AllEvents(case) [ "A board was asked for. No board plans or reviews a FHIR plan, so the case is planned as every FHIR case is", forced, mode _ ": the case " _ $SELECT(forced: "says", 1: "does not say") _ " that a board was asked for")
            Set id = case.%Id(), runs = ""
            &sql(SELECT COUNT(*) INTO :runs FROM Shutter_Store.AgentRun WHERE "Case" = :id)
            Do $$$AssertEquals(runs, 0, mode _ ": no agent ran")
        }
    }
}

/// A rejection, an approval wait that ran out, an abandon and a reopening are the workflow's own, in its own words.
Method TestRejectionTimeoutAbandonReopen()
{
    // A rejection.
    Do ..Awaiting(.wf, .case)
    Set headline = case.Headline
    Do ..Step(wf, "fhir:approval", ..Approve(wf, "Reject", "not today"))
    Do $$$AssertEquals(case.State _ "|" _ case.Headline, "blocked|Rejected by " _ ..#APPROVER _ ": " _ headline, "a rejection blocks the case")
    Do $$$AssertEquals(..Event(case, "blocked"), "Rejected by " _ ..#APPROVER _ ": not today", "in the workflow's words")
    Set id = case.%Id(), decision = "", version = ""
    &sql(SELECT TOP 1 Decision, PolicyVersion INTO :decision, :version FROM Shutter_Store.Approval WHERE "Case" = :id ORDER BY ID DESC)
    Do $$$AssertEquals(decision _ "|" _ version, "rejected|" _ ##class(Shutter.FHIR.Profile).#POLICYVERSION, "the rejection is on record under the FHIR gate's policy version")
    Do $$$AssertEquals(wf.Keys() _ " [" _ wf.ApprovalId _ "]", "fhir:gate:proposal fhir:approval approval:timeout:1 []", "nothing is read or sent after it")
    Do $$$AssertEquals(##class(Shutter.API.Dispatch).ReasonFromEvent(..Event(case, "blocked"), "blocked"), "REJECTED_BY_APPROVER", "the reason it shows")

    // A reopening of that case: fresh evidence, a new plan, nothing of the earlier one carried.
    Set again = ..Workflow(case)
    Set reopen = ##class(Shutter.Msg.Reinvestigate).%New()
    Set reopen.CaseId = case.CaseId, reopen.RequestedBy = ..#APPROVER, reopen.Reason = "look again"
    Do $$$AssertStatusOK(again.OnReinvestigate(reopen, .started), "the case is reopened")
    Do $$$AssertEquals(again.Evidence _ " " _ again.Reopened _ " " _ case.State, "1 1 collecting", "evidence is collected afresh")
    Do $$$AssertStatusOK(again.OnEvidence(case, ..Evidence(case)), "the fresh evidence is taken")
    Do $$$AssertEquals(##class(Shutter.Store.Plan).%OpenId(again.PlanId).Version _ " " _ again.Last() _ " [" _ again.FHIRBindingId _ "]", "2 FHIR Gate|Shutter.Msg.FHIRGateRequest|fhir:gate:proposal []", "a second plan goes to the FHIR gate")
    Do ..Step(again, "fhir:gate:proposal", ..Gate(case, again, "proposal"))
    Do $$$AssertEquals(case.State _ " " _ ##class(Shutter.Store.FHIRBinding).%OpenId(again.FHIRBindingId).PlanId, "awaiting_approval " _ again.PlanId, "and is sealed and asked for again, under a binding of its own")

    // An approval wait that ran out.
    Do ..Awaiting(.wf, .case)
    Do ..Step(wf, "approval:timeout:" _ wf.Round)
    Do $$$AssertEquals(case.State _ "|" _ case.Headline, "escalated|No approval within " _ wf.WaitWords(wf.ApprovalWaitSeconds) _ "; a person must decide", "the wait's own alarm escalates the case")
    Do ..Step(wf, "approval:timeout:" _ (wf.Round + 1))
    Do $$$AssertEquals(case.State, "escalated", "an alarm of another round changes nothing")

    // An abandon while the case waits.
    Do ..Awaiting(.wf, .case)
    Set other = ##class(Shutter.Test.QuietFHIRWorkflow).%New("Case Workflow")
    Set abandon = ##class(Shutter.Msg.CaseAbandon).%New()
    Set abandon.CaseId = case.CaseId, abandon.Reason = "handled on the ward", abandon.Actor = ..#APPROVER
    Do $$$AssertStatusOK(other.OnAbandon(abandon, .started), "the case is abandoned")
    Do $$$AssertEquals(case.State _ "|" _ case.Disposition, "failed|abandoned", "it fails as abandoned")
    // The cancelled task's answer reaches the first instance and finds the case closed.
    Do ..Step(wf, "fhir:approval", ..Approve(wf, "Cancel"))
    Do $$$AssertEquals(case.State _ " " _ ..Count("Approval", case), "failed 0", "an answer that comes after is ignored")
}

/// A case stopped in the middle of its write (abandoned, here) has a sent fence row and no attempt. The next plan of
/// the case writes the attempt row, once: uncertain when no answer is on record, the recorded answer when one is.
Method TestAnAbandonedSentWriteGetsItsAttemptRow()
{
    For answered = 0, 1 {
        Do ..Executing(.wf, .case)
        Set fence = $SELECT(answered: ..Fence(wf, case, 1, 200, "applied", "W/""2"""), 1: ..Fence(wf, case, 1))
        Do $$$AssertStatusOK(##class(Shutter.Store.Case).Abandon(case, "the engine was restarted", ..#APPROVER), "the case is abandoned in the middle of its write")
        Do $$$AssertEquals(..Count("ExecutionAttempt", case), 0, "no attempt is on record")
        Set again = ..Workflow(case)
        Set reopen = ##class(Shutter.Msg.Reinvestigate).%New()
        Set reopen.CaseId = case.CaseId, reopen.RequestedBy = ..#APPROVER
        Do $$$AssertStatusOK(again.OnReinvestigate(reopen, .started), "the case is reopened")
        Do $$$AssertStatusOK(again.OnEvidence(case, ..Evidence(case)), "and planned again")
        Do fence.%Reload()
        Set attempt = ##class(Shutter.Store.ExecutionAttempt).%OpenId(fence.ExecutionAttemptId)
        Do $$$AssertTrue($ISOBJECT(attempt), "the sent update has its attempt row")
        Do $$$AssertEquals(attempt.Outcome _ "|" _ +attempt.HttpStatus _ "|" _ attempt.ApprovalGetObjectId() _ "|" _ attempt.PlanGetObjectId(), $SELECT(answered: "applied|200|", 1: "uncertain|0|") _ fence.ApprovalId _ "|" _ fence.PlanId, $SELECT(answered: "with the answer on record", 1: "uncertain, with no HTTP answer") _ ", under the approval and the plan it was sent for")
        Set receipt = ##class(Shutter.Util.Json).Parse(attempt.ReceiptJSON)
        Do $$$AssertEquals(receipt.kind _ "|" _ receipt.encounter _ "|" _ receipt."expected_etag" _ "|" _ receipt."response_etag" _ "|" _ receipt."operation_id", "fhir|Encounter/enc-1|W/""1""|" _ $SELECT(answered: "W/""2""", 1: "") _ "|" _ fence.OperationId, "and a FHIR receipt")
        Do $$$AssertEquals(##class(Shutter.Util.Json).Parse(attempt.ResponseJSON).sent, 1, "that says it was sent")
        Do $$$AssertStatusOK(again.OnEvidence(case, ..Evidence(case)), "planned once more")
        Do $$$AssertEquals(..Count("ExecutionAttempt", case), 1, "the row is written once")
        Do $$$AssertEquals(again.AttemptId, "", "and is not the new plan's attempt")
    }
}

/// A case of another receiver is untouched: its plan goes to the workflow's own gate, under the workflow's own
/// headline, and the flow sends nothing.
Method TestAnAdtCaseStillCallsMainsGate()
{
    Set case = ..NewCase("rules", 0), snap = ..AdtSnapshot(case)
    Set wf = ..Workflow(case)
    Set evidence = ##class(Shutter.Msg.EvidenceResult).%New()
    Set evidence.SnapshotId = snap.%Id(), evidence.Digest = snap.Digest, evidence.SummaryJSON = snap.Summary
    Do $$$AssertStatusOK(wf.OnEvidence(case, evidence), "the evidence is taken")
    Do $$$AssertEquals(wf.Boards _ " " _ wf.PlanId _ " " _ +$GET(wf.Sent), "1  0", "the case goes on to the workflow's own path (the board's step, which plans a Rules only case), and the flow plans and sends nothing")
    Do $$$AssertStatusOK(wf.RulesOnly(case), "the rules plan it, as that step does in Rules only")
    Do $$$AssertEquals(wf.MainGates _ " " _ +$GET(wf.Sent), "1 0", "the plan goes to the workflow's own gate, and the flow sends nothing")
    Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
    Do $$$AssertEquals(plan.CreatedBy _ "|" _ plan.ExpectedVersion _ "|" _ case.State, "rules|3|proposed", "with the rules' plan at the receiver's version")
    Do $$$AssertTrue(case.Headline [ "Resend the transfer to WARD-B unchanged, after rehearsal and approval", "under the workflow's own headline: " _ case.Headline)
    Do $$$AssertEquals(wf.FHIRBindingId, "", "and no binding")
    // An answer under one of the flow's keys never arrives for such a case; the workflow's own keys are as they were.
    Set refused = ##class(Shutter.Msg.GateResult).%New()
    Set refused.Outcome = "block", refused.Summary = "Blocked: ordering LATER_EVENT_APPLIED", refused.ChecksJSON = "[]"
    Do ..Step(wf, "gate:proposal", refused)
    Do $$$AssertEquals(case.State _ "|" _ case.Headline, "blocked|Blocked by the gate: Blocked: ordering LATER_EVENT_APPLIED", "the workflow's own handler takes its own key")
}

// ---- the path, step by step ----

/// A new FHIR case with its evidence taken: planned, the plan at the FHIR gate. <var>catalogue</var>, when given, is
/// the evidence's catalogue match.
Method Planned(mode As %String, Output wf As Shutter.Test.QuietFHIRWorkflow, Output case As Shutter.Store.Case, catalogue As %DynamicObject = "")
{
    Set case = ..NewCase(mode), wf = ..Workflow(case)
    Do $$$AssertStatusOK(wf.OnEvidence(case, ..Evidence(case, catalogue)), "the evidence is taken")
    Do $$$AssertEquals(case.State _ " " _ wf.Keys(), "proposed fhir:gate:proposal", "the case is planned and its plan sent to the FHIR gate")
}

/// Planned, and the proposal gate passed: the update sealed, the task sent, the case waiting for an approver.
Method Awaiting(Output wf As Shutter.Test.QuietFHIRWorkflow, Output case As Shutter.Store.Case)
{
    Do ..Planned("rules", .wf, .case)
    Do ..Step(wf, "fhir:gate:proposal", ..Gate(case, wf, "proposal"))
    Do $$$AssertEquals(case.State _ " " _ wf.Keys(), "awaiting_approval fhir:gate:proposal fhir:approval approval:timeout:1", "the case waits for an approver")
}

/// Awaiting, and approved: the binding tied to the approval, the read before the write asked for.
Method Approved(Output wf As Shutter.Test.QuietFHIRWorkflow, Output case As Shutter.Store.Case)
{
    Do ..Awaiting(.wf, .case)
    Do ..Step(wf, "fhir:approval", ..Approve(wf))
    Do $$$AssertEquals(case.State _ " " _ wf.Last(), "approved FHIR Receiver|Shutter.Msg.FHIRRead|fhir:preflight", "the case is approved and the read before the write asked for")
    Set approval = ##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId), binding = ##class(Shutter.Store.FHIRBinding).%OpenId(wf.FHIRBindingId)
    Do $$$AssertEquals(approval.Decision _ "|" _ approval.Approver _ "|" _ approval.PolicyVersion _ "|[" _ approval.ExpectedVersion _ "]|" _ approval.RehearsalGetObjectId(), "approved|" _ ..#APPROVER _ "|" _ ##class(Shutter.FHIR.Profile).#POLICYVERSION _ "|[]|", "the approval is the person's, under the FHIR gate's policy version, with no expected version and no rehearsal")
    Do $$$AssertEquals(binding.ApprovalId _ "|" _ case.CurrentApprovalGetObjectId(), approval.%Id() _ "|" _ approval.%Id(), "the binding is tied to it, and it is the case's current approval")
    Set read = wf.LastRequest()
    Do $$$AssertEquals(read.CaseId _ "|" _ read.Purpose _ "|" _ read.EncounterId _ "|" _ read.PatientRef _ "|" _ read.LocationRefsJSON _ "|" _ read.Vid, case.CaseId _ "|dispatch|enc-1|Patient/demo-p1|[""Location/ward-a"",""Location/ward-b""]|", "the read names the Encounter, its Patient and every bound Location")
}

/// Approved, the read made and the dispatch gate passed: the one update asked of FHIR Out.
Method Executing(Output wf As Shutter.Test.QuietFHIRWorkflow, Output case As Shutter.Store.Case)
{
    Do ..Approved(.wf, .case)
    Do ..ReadStep(wf)
    Set gate = wf.LastRequest()
    Do $$$AssertEquals(wf.Last() _ "|" _ gate.Stage _ "|" _ gate.ApprovalId _ "|" _ (gate.ReadId '= ""), "FHIR Gate|Shutter.Msg.FHIRGateRequest|fhir:gate:dispatch|dispatch|" _ wf.ApprovalId _ "|1", "the read goes to the FHIR gate at the dispatch, with the approval")
    Set passed = ..Gate(case, wf, "dispatch")
    Do ..Step(wf, "fhir:gate:dispatch", passed)
    Set write = wf.LastRequest()
    Do $$$AssertEquals(case.State _ " " _ wf.Last(), "executing FHIR Out|Shutter.Msg.FHIRWrite|fhir:execute", "the update is asked of FHIR Out")
    Do $$$AssertEquals(write.CaseId _ "|" _ write.PlanId _ "|" _ write.ApprovalId _ "|" _ write.BindingId _ "|" _ write.DecisionId, case.CaseId _ "|" _ wf.PlanId _ "|" _ wf.ApprovalId _ "|" _ wf.FHIRBindingId _ "|" _ passed.DecisionId, "under the plan, the approval, the binding and the dispatch decision")
    Do $$$AssertEquals(..Event(case, "executing") _ " " _ wf.Refreshes, "Sending one update with If-Match W/""1"" 0", "the case says what is sent")
}

/// Executing, and the update applied: the fence row sent and answered, the attempt written, the verifier asked.
Method Verifying(Output wf As Shutter.Test.QuietFHIRWorkflow, Output case As Shutter.Store.Case)
{
    Do ..Executing(.wf, .case)
    Set fence = ..Fence(wf, case, 1, 200, "applied", "W/""2""", "/ut/Encounter/enc-1/_history/2")
    Do ..Step(wf, "fhir:execute", ..Wrote("applied", 200, 1, "", "W/""2""", "/ut/Encounter/enc-1/_history/2"))
    Do $$$AssertEquals(case.State _ " " _ wf.Last(), "verifying FHIR Verifier|Shutter.Msg.VerifyRequest|fhir:verify", "the update is verified")
    Do fence.%Reload()
    Set attempt = ##class(Shutter.Store.ExecutionAttempt).%OpenId(wf.AttemptId)
    Do $$$AssertEquals(fence.ExecutionAttemptId _ "|" _ attempt.Outcome _ "|" _ attempt.HttpStatus _ "|[" _ attempt.ExpectedVersion _ "]|" _ attempt.RehearsalGetObjectId(), attempt.%Id() _ "|applied|200|[]|", "its attempt row is the fence row's, with no expected version and no rehearsal")
    Set response = ##class(Shutter.Util.Json).Parse(attempt.ResponseJSON), receipt = ##class(Shutter.Util.Json).Parse(attempt.ReceiptJSON)
    Set binding = ##class(Shutter.Store.FHIRBinding).%OpenId(wf.FHIRBindingId)
    Do $$$AssertEquals(response.kind _ "|" _ response.sent _ "|" _ response."reason_code" _ "|" _ response.receipt.%ToJSON(), "fhir|1||" _ receipt.%ToJSON(), "the response is a FHIR one, sent, with the receipt")
    Do $$$AssertEquals(receipt.%ToJSON(), {"kind": "fhir", "encounter": "Encounter/enc-1", "expected_etag": "W/\"1\"", "response_etag": "W/\"2\"", "response_location": "/ut/Encounter/enc-1/_history/2", "body_digest": (binding.ApprovedBodyDigest), "operation_id": (binding.OperationId), "marker_system": "urn:shutter:recovery"}.%ToJSON(), "the receipt names the update")
    Do $$$AssertTrue(..AllEvents(case) [ "FHIR update: applied, HTTP 200", "and the case notes it")
    // What was sent before goes out of the way: a test counts from here.
    Set wf = ..Carry(wf)
}

/// The whole path of a case that is approved, applied and verified. With <var>fresh</var> every step runs on a new
/// workflow instance that was given only the identifiers.
Method ToTheEnd(fresh As %Boolean, Output wf As Shutter.Test.QuietFHIRWorkflow, Output case As Shutter.Store.Case)
{
    Set case = ..NewCase("rules"), wf = ..Workflow(case)
    Do $$$AssertStatusOK(wf.OnEvidence(case, ..Evidence(case)), "the evidence is taken")
    If fresh Set wf = ..Next(wf)
    Do ..Step(wf, "fhir:gate:proposal", ..Gate(case, wf, "proposal"))
    If fresh Set wf = ..Next(wf)
    Do ..Step(wf, "fhir:approval", ..Approve(wf))
    If fresh Set wf = ..Next(wf)
    Do ..ReadStep(wf)
    If fresh Set wf = ..Next(wf)
    Do ..Step(wf, "fhir:gate:dispatch", ..Gate(case, wf, "dispatch"))
    If fresh Set wf = ..Next(wf)
    Do ..Fence(wf, case, 1, 200, "applied", "W/""2""")
    Do ..Step(wf, "fhir:execute", ..Wrote("applied", 200, 1, "", "W/""2"""))
    If fresh Set wf = ..Next(wf)
    Do ..Step(wf, "fhir:verify", ..Verified("verified", "verified", 0, "The update is in the Encounter's history and the record shows it."))
    If fresh Set wf = ..Next(wf)
    Do $$$AssertEquals(..Event(case, "resolved") _ "|" _ case.Outcome, "The update is in the Encounter's history and the record shows it.|The update is in the Encounter's history and the record shows it.", "the case resolves with the verifier's sentence as it is")
}

/// Lets go of a workflow instance, keeping what it sent and what it asked the workflow's own path for, and returns
/// a new one that knows only the identifiers the stored instance keeps.
Method Next(wf As Shutter.Test.QuietFHIRWorkflow) As Shutter.Test.QuietFHIRWorkflow
{
    Set ..KeysSoFar = ..KeysSoFar _ $SELECT((..KeysSoFar = "") || (wf.Keys() = ""): "", 1: " ") _ wf.Keys()
    Set ..ClassesSoFar = ..ClassesSoFar _ " " _ wf.Classes()
    Set ..MainCalls = ..MainCalls + wf.MainGates + wf.MainVerifies + wf.MainPreflights + wf.WardOperations + wf.Boards + wf.Evidence
    Quit ..Carry(wf)
}

/// A new workflow instance with the identifiers of another, and nothing else of it.
ClassMethod Carry(wf As Shutter.Test.QuietFHIRWorkflow) As Shutter.Test.QuietFHIRWorkflow
{
    Set new = ##class(Shutter.Test.QuietFHIRWorkflow).%New("Case Workflow")
    For name = "CaseId", "Mode", "PlanId", "ApprovalId", "AttemptId", "FHIRBindingId", "Round", "Refreshes", "Policy", "CatalogueEntry", "CatalogueOutcome" {
        Set $PROPERTY(new, name) = $PROPERTY(wf, name)
    }
    Quit new
}

// ---- answers ----

/// One answer through the workflow's own OnResponse, under that key.
Method Step(wf As Shutter.Test.QuietFHIRWorkflow, key As %String, answer As %Library.RegisteredObject = "")
{
    Set response = ""
    Do $$$AssertStatusOK(wf.OnResponse("", .response, "", answer, key), "the answer at " _ key _ " is taken")
}

/// The read before the write, made and answered now; what the flow saved of it for the gate is deleted after the test.
Method ReadStep(wf As Shutter.Test.QuietFHIRWorkflow)
{
    Do ..Step(wf, "fhir:preflight", ..Read())
    Set gate = wf.LastRequest()
    If $ISOBJECT(gate) && gate.%IsA("Shutter.Msg.FHIRGateRequest") && (gate.ReadId '= "") Set i%Reads(gate.ReadId) = ""
}

/// An error status through the workflow's own OnError, under that key.
Method Fail(wf As Shutter.Test.QuietFHIRWorkflow, key As %String, text As %String)
{
    Set response = ""
    Do $$$AssertStatusOK(wf.OnError("", .response, "", $$$ERROR($$$GeneralError, text), key), "the error at " _ key _ " is taken")
}

/// A decision of the FHIR gate as the gate stores and answers it: pass by default, or the outcome with those rows.
Method Gate(case As Shutter.Store.Case, wf As Shutter.Test.QuietFHIRWorkflow, stage As %String, outcome As %String = "pass", checks As %DynamicArray = "") As Shutter.Msg.GateResult
{
    Set policy = ##class(Shutter.FHIR.Profile).#POLICYVERSION
    If '$ISOBJECT(checks) Set checks = []
    Set blocks = "", iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) { If c.result '= "pass" Set blocks = blocks _ $SELECT(blocks = "": "", 1: ", ") _ c.check _ " " _ c."reason_code" }
    Set text = $CASE(outcome, "pass": "Every check passed", "block": "Blocked: " _ blocks, : "Unknown: " _ blocks) _ " (policy " _ policy _ ", stage " _ stage _ ")"
    Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
    Do $$$AssertStatusOK(##class(Shutter.Store.GateDecision).Create(case, plan, stage, policy, outcome, checks, text, .decision), "the gate's decision is stored")
    Set result = ##class(Shutter.Msg.GateResult).%New()
    Set result.Outcome = outcome, result.DecisionId = decision.%Id(), result.PolicyVersion = policy, result.ChecksJSON = checks.%ToJSON(), result.Summary = text
    Quit result
}

/// One row of a gate decision.
ClassMethod Row(check As %String, result As %String, code As %String) As %DynamicObject
{
    Quit {"check": (check), "result": (result), "reason_code": (code), "detail": "made up"}
}

/// The approver's answer to the task: an approval of the workflow's plan by its digest, or another action.
Method Approve(wf As Shutter.Test.QuietFHIRWorkflow, action As %String = "Approve", comment As %String = "") As EnsLib.Workflow.TaskResponse
{
    Set answer = ##class(EnsLib.Workflow.TaskResponse).%New()
    Set answer.%Action = action, answer.%UserName = ..#APPROVER
    Do answer.%FormValues.SetAt($SELECT(action = "Approve": ##class(Shutter.Store.Plan).%OpenId(wf.PlanId).Digest, 1: ""), "PlanDigest")
    Do answer.%FormValues.SetAt(comment, "Comment")
    Quit answer
}

/// The read before the write as FHIR Receiver answers it, made now.
ClassMethod Read() As Shutter.Msg.FHIRReadResult
{
    Set read = ##class(Shutter.Msg.FHIRReadResult).%New()
    Set read.PartsJSON = ##class(Shutter.Test.FHIRGate).Parts(##class(Shutter.Util.Time).NowUTC()).%ToJSON()
    Quit read
}

/// An answer of FHIR Out.
ClassMethod Wrote(outcome As %String, status As %Integer, sent As %Boolean, reason As %String = "", etag As %String = "", location As %String = "") As Shutter.Msg.FHIRWriteResult
{
    Set answer = ##class(Shutter.Msg.FHIRWriteResult).%New()
    Set answer.Outcome = outcome, answer.HttpStatus = status, answer.Sent = sent, answer.ReasonCode = reason
    Set answer.ResponseEtag = etag, answer.ResponseLocation = location
    Quit answer
}

/// An answer of FHIR Verifier: the stored word, the Judge's own, whether another read is asked for, and the sentence.
ClassMethod Verified(word As %String, judged As %String, retry As %Boolean, sentence As %String) As Shutter.Msg.VerifyResult
{
    Set detail = {"kind": "fhir", "judge_outcome": (judged), "disposition": "resend", "case_code": ""}
    Do detail.%Set("retry", ''retry, "boolean")
    Set answer = ##class(Shutter.Msg.VerifyResult).%New()
    Set answer.Outcome = word, answer.Summary = sentence, answer.DetailJSON = detail.%ToJSON()
    Quit answer
}

/// The fence row of the workflow's approval as FHIR Out leaves it: opened; with <var>sent</var> marked as sent; with
/// a status, answered so.
Method Fence(wf As Shutter.Test.QuietFHIRWorkflow, case As Shutter.Store.Case, sent As %Boolean, status As %Integer = "", outcome As %String = "", etag As %String = "", location As %String = "") As Shutter.Store.FHIRAttempt
{
    Set binding = ##class(Shutter.Store.FHIRBinding).%OpenId(wf.FHIRBindingId)
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, binding, .fence, .created), "the fence row is opened")
    If sent Do $$$AssertTrue(fence.MarkSent(), "and marked as sent")
    If status '= "" Do $$$AssertStatusOK(fence.Answer(status, outcome, etag, location, ""), "and answered " _ outcome)
    Quit fence
}

// ---- what the store says ----

/// The stop a case is at: its state, its headline ("" leaves it unasked), the text of its closing event, the reason
/// the case's reason route answers and, with a workflow, that its approval is void.
Method Stopped(case As Shutter.Store.Case, stop As %Integer, state As %String, headline As %String, text As %String, code As %String, wf As Shutter.Test.QuietFHIRWorkflow = "")
{
    Do $$$AssertEquals(case.State, state, "stop " _ stop _ ": the case is " _ state)
    If headline '= "" Do $$$AssertEquals(case.Headline, headline, "stop " _ stop _ ": the headline")
    Do $$$AssertEquals(..Event(case, state), text, "stop " _ stop _ ": the event")
    Do $$$AssertEquals(..Code(case), code, "stop " _ stop _ ": the reason is " _ code)
    If $ISOBJECT(wf) Do $$$AssertEquals(##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId).Revoked, 1, "stop " _ stop _ ": the approval is void")
}

/// The reason the case's reason route answers (GET /cases/{id}/blocked-reason), or the reply when it gave none.
ClassMethod Code(case As Shutter.Store.Case) As %String
{
    Set body = ""
    Set status = ##class(Shutter.Test.ScenarioGuard).Call("CaseBlockedReason", .body, case.CaseId)
    If '$ISOBJECT(body) || (body.code = "") Quit status _ " " _ $SELECT($ISOBJECT(body): body.%ToJSON(), 1: "")
    Quit body.code
}

/// The text of the newest event that took the case to that state.
ClassMethod Event(case As Shutter.Store.Case, state As %String) As %String
{
    Set id = case.%Id(), text = ""
    &sql(SELECT TOP 1 Text INTO :text FROM Shutter_Store.CaseEvent WHERE "Case" = :id AND ToState = :state ORDER BY Seq DESC)
    Quit text
}

/// Every event text of the case, in order, one per line.
ClassMethod AllEvents(case As Shutter.Store.Case) As %String
{
    Set out = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? ORDER BY Seq", case.%Id())
    While rs.%Next() { Set out = out _ rs.%Get("Text") _ $CHAR(10) }
    Quit out
}

/// The states the case went through, in order.
ClassMethod States(case As Shutter.Store.Case) As %String
{
    Set out = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ToState FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? AND Kind = 'state' ORDER BY Seq", case.%Id())
    While rs.%Next() { Set out = out _ $SELECT(out = "": "", 1: " ") _ rs.%Get("ToState") }
    Quit out
}

/// How many rows of a store the case has.
ClassMethod Count(store As %String, case As Shutter.Store.Case) As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Shutter_Store." _ store _ " WHERE ""Case"" = ?", case.%Id())
    Quit $SELECT(rs.%Next(): +rs.%GetData(1), 1: -1)
}

// ---- the fixture ----

/// A workflow instance for the case, in its first round.
ClassMethod Workflow(case As Shutter.Store.Case) As Shutter.Test.QuietFHIRWorkflow
{
    Set wf = ##class(Shutter.Test.QuietFHIRWorkflow).%New("Case Workflow")
    Set wf.CaseId = case.CaseId, wf.Mode = case.Mode, wf.Round = 1
    Quit wf
}

/// A saved case of a ward move whose delivery failed: of this class's FHIR receiver, or of the shipped receiver.
Method NewCase(mode As %String, fhir As %Boolean = 1) As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-FHIRFLOW-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.FHIRFlow)
    Set case.Event = "transfer", case.FailureKind = "delivery_failed", case.FailureText = "Delivery unavailable (ward_unavailable), HTTP 503"
    Set case.EncounterId = "V1001", case.PatientId = "MRN-UT1", case.PatientIdAuthority = "HOSP", case.EventTime = "2026-11-07T10:15:00Z"
    Set case.SourceSystem = "PAS", case.Ward = "WARD-B"
    Set case.Receiver = $SELECT(fhir: ..#RECEIVER, 1: $PARAMETER("Shutter.Production", "RECEIVER"))
    Set case.OperationKey = "PAS^HOSP^" _ case.PatientId _ "^" _ case.EncounterId _ "^transfer^" _ case.EventTime _ "^" _ case.CaseId
    Set case.State = "collecting", case.Mode = mode
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Do $$$AssertStatusOK(case.%Save(), "the case " _ case.CaseId _ " is saved")
    Set i%Made(case.%Id()) = ""
    Quit case
}

/// Fresh evidence of the case, as the collector leaves it: a sealed snapshot of a ward move that can be written
/// (Shutter.Test.FHIRGate's view), made the case's current one, with its sealed read. <var>catalogue</var> is the
/// catalogue match to put in it; <var>without</var> names a part of the FHIR evidence to empty ("patient": the
/// Patient's reference). Returns the collector's answer.
Method Evidence(case As Shutter.Store.Case, catalogue As %DynamicObject = "", without As %String = "") As Shutter.Msg.EvidenceResult
{
    Set view = ##class(Shutter.Test.FHIRGate).Fill(##class(Shutter.Test.FHIRGate).BaseView(), case.OperationKey)
    If $ISOBJECT(catalogue) Set view.catalogue = catalogue
    If without = "patient" Set view.fhir.patient.reference = ""
    Set snap = ##class(Shutter.Store.Snapshot).Begin(case, 300)
    Do $$$AssertStatusOK(snap.Seal(view), "the snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snap), "and is the case's current one")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRSealedRead).Keep(case, snap.%Id(), ##class(Shutter.Test.FHIRGate).Seed()), "its Encounter body is kept")
    Set result = ##class(Shutter.Msg.EvidenceResult).%New()
    Set result.SnapshotId = snap.%Id(), result.Digest = snap.Digest, result.SummaryJSON = view.%ToJSON()
    Quit result
}

/// The catalogue's answer when one entry matches alone and says resend.
ClassMethod Resend() As %DynamicObject
{
    Quit {"decision": "policy", "entry": "E2", "outcome": "resend", "outcome_ref": "preferred", "conditions": {"chain": "single"}, "facts": {},
        "matches": [{"id": "E2", "title": "A transfer that never reached the receiver", "preferred": {"outcome": "resend", "why": "the transfer never reached the receiver"}}]}
}

/// A sealed snapshot of another receiver's case, read whole at version 3, made the case's current one.
Method AdtSnapshot(case As Shutter.Store.Case) As Shutter.Store.Snapshot
{
    Set snap = ##class(Shutter.Store.Snapshot).Begin(case, 300)
    Set view = {"operation": {"operation_key": (case.OperationKey), "payload_digest": "sha256:ut"}, "ward_state_http_status": 200, "ward_state": {"version": 3, "state": "admitted", "ward": "WARD-A"}, "receipt_http_status": 404, "receipt": {"error": "no_receipt"}}
    Do $$$AssertStatusOK(snap.Seal(view), "the other receiver's snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snap), "and is its case's current one")
    Quit snap
}

/// Puts this class's receiver into the stored profile (once per test) with recovery enabled; <var>policy</var>, when
/// given, replaces the profile's release policy.
Method ChangeProfile(policy As %DynamicObject = "")
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..ProfileChanged {
        Set ..HadProfileRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: ""), ..ProfileChanged = 1
    }
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    Do p.%Set("recovery", {"mode": "enabled"})
    If $ISOBJECT(policy) Do p.%Set("policy", policy)
    Set entry = ##class(Shutter.Test.FHIRGate).Entry()
    Set entry.name = ..#RECEIVER
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
    Set ..ProfileChanged = 0, ..SavedProfile = ""
}

/// A scratch production that holds the four FHIR items, each on its class and enabled, and never runs: only its
/// definition is read.
Method MakeProduction() As %Status
{
    Do ..RemoveProduction()
    Set p = ##class(Ens.Config.Production).%New()
    Set p.Name = ..#PRODUCTION
    Set names = $PARAMETER("Shutter.FHIR.Profile", "ITEMS")
    For n = 1:1:$LENGTH(names, ",") {
        Set i = ##class(Ens.Config.Item).%New()
        Set i.Name = $PIECE(names, ",", n), i.ClassName = ##class(Shutter.FHIR.Install).ItemClass(i.Name), i.PoolSize = 1, i.Enabled = 1, i.Production = p
        Do p.Items.Insert(i)
    }
    Quit p.%Save()
}

Method RemoveProduction()
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    If $ISOBJECT(p) {
        For i = p.Items.Count():-1:1 {
            Set id = p.Items.GetAt(i).%Id()
            Do p.Items.RemoveAt(i)
            Do:id'="" ##class(Ens.Config.Item).%DeleteId(id)
        }
        Kill p
        Do ##class(Ens.Config.Production).%DeleteId(..#PRODUCTION)
    }
}

}
