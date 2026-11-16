/// The moment of activation (CONTRACTS 6.8, R17): work planned before a site entry was activated never completes under
/// the old catalogue version. A person's approved write, a policy release, an incident's item and a follower's write
/// are void at dispatch (the approval's check of the catalogue's version, which the generation keeps void when the
/// change is undone); a closure, which has no approval to void, is planned again on fresh evidence, at the proposal gate
/// and before the verification closes it. On the fresh evidence the site entry answers alone and the case goes to a
/// person, in an incident's release and before a case can follow another's board too. Driven in process, outside the
/// production: what the receiver's history shows is the end-to-end check's (tests/e2e/site_entry_check.py).
Class Shutter.Test.SiteEntryRace Extends %UnitTest.TestCase
{

Method OnBeforeOneTest() As %Status
{
    Do ##class(Shutter.Test.SiteKit).PurgeAll()
    Kill ^||Shutter.Test.SiteWorkflow
    Quit ##class(Shutter.Test.SiteKit).Reset()
}

Method OnAfterAllTests() As %Status
{
    Do ##class(Shutter.Test.SiteKit).PurgeAll()
    Quit ##class(Shutter.Test.SiteKit).Reset()
}

/// A resend plan on the case's current snapshot, as a board or the policy path makes one.
Method Resend(case As Shutter.Store.Case, by As %String) As Shutter.Store.Plan
{
    Set plan = {"disposition": "resend", "action": {"type": "resend", "operation_key": (case.OperationKey), "expected_version": 3, "payload_digest": "sha256:ut"}, "summary": "Resend the transfer", "catalogue_entry": "E2", "outcome": "preferred"}
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, case.CurrentSnapshot, plan, by, .p), "a resend plan by " _ by)
    Quit p
}

Method Approval(case As Shutter.Store.Case, plan As Shutter.Store.Plan, approver As %String) As Shutter.Store.Approval
{
    Set sc = ##class(Shutter.Store.Approval).Create(case, plan, case.CurrentSnapshot, $PARAMETER("Shutter.Operation.Gate", "POLICYVERSION"), "", plan.ExpectedVersion, approver, "approved", "unit test", "", 3600, .approval)
    Do $$$AssertStatusOK(sc, "an approval by " _ approver)
    Quit approval
}

Method Why(approval As Shutter.Store.Approval, plan As Shutter.Store.Plan, case As Shutter.Store.Case) As %String
{
    Quit approval.InvalidReason(plan, case.CurrentSnapshot, $PARAMETER("Shutter.Operation.Gate", "POLICYVERSION"), 3)
}

/// Writes planned before an activation: a person's approval, the policy's automatic one, a follower's, and an item
/// released under its incident's approval. Each stands until the activation and is void after it, and stays void when
/// the entry is suspended and when it is resumed.
Method TestWritesPlannedBeforeAnActivationAreVoid()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set before = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    // Four cases in flight, none in the entry's ward: the entry does not even match them.
    For who = "user:ut", "policy", "lead:C-OTHER", "incident" {
        Set c(who) = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "state": "approved"})
        Set p(who) = ..Resend(c(who), $CASE(who, "user:ut": "run:1", "policy": "policy:E2", "incident": "policy:E2", : who))
        Do $$$AssertEquals(p(who).CatalogueVersion, before, who _ ": the plan records the catalogue's version")
        Set a(who) = ..Approval(c(who), p(who), $SELECT(who = "lead:C-OTHER": "user:ut", who = "incident": "user:ut", 1: who))
    }
    // The incident's item: its approval is bound to the incident's plan, which recorded the versions of its moment.
    Set inc = ##class(Shutter.Store.Incident).%New()
    Set inc.IncidentId = "UT-SITE-I-" _ $JOB, inc.Receiver = c("incident").Receiver, inc.State = "releasing", inc.Mode = "policy"
    Set inc.PlanDigest = "sha256:ut-incident", inc.CatalogueVersion = before
    Set inc.ProfileVersion = ##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0), inc.PolicyVersion = $PARAMETER("Shutter.Operation.Gate", "POLICYVERSION")
    Set inc.OpenedAt = ##class(Shutter.Util.Time).NowUTC()
    Do $$$AssertStatusOK(inc.%Save(), "an incident")
    Do $$$AssertStatusOK(c("incident").SetIncident(inc), "holds the fourth case")
    Do $$$AssertStatusOK(a("incident").BindIncident("sha256:ut-incident", "E2", "resend"), "whose approval is the incident's")
    For who = "user:ut", "policy", "lead:C-OTHER", "incident" { Do $$$AssertEquals(..Why(a(who), p(who), c(who)), "", who _ ": the approval stands before the activation") }
    // The activation.
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "a site entry is activated")
    For who = "user:ut", "policy", "lead:C-OTHER", "incident" { Do $$$AssertEquals(..Why(a(who), p(who), c(who)), "catalogue_changed", who _ ": void after the activation") }
    // The gate at dispatch says so with the code it has.
    Set req = ##class(Shutter.Msg.GateRequest).%New()
    Set req.CaseId = c("user:ut").CaseId, req.PlanId = p("user:ut").%Id(), req.Stage = "dispatch", req.Receiver = c("user:ut").Receiver, req.ChainKind = "single", req.ApprovalId = a("user:ut").%Id(), req.ReceiverVersion = 3
    Set gate = ##class(Shutter.Operation.Gate).%New("Shutter Gate (unit test)")
    Do $$$AssertStatusOK(gate.OnGateRequest(req, .resp), "the dispatch gate runs")
    Do $$$AssertEquals(resp.Outcome, "block", "and blocks")
    Do $$$AssertTrue(resp.Summary [ "APPROVAL_CATALOGUE_CHANGED", "with APPROVAL_CATALOGUE_CHANGED: " _ resp.Summary)
    // Undoing the change does not make the approvals valid again: the generation.
    Do $$$AssertEquals($CLASSMETHOD(site, "Suspend", id, "unit test", "ut-approver", "api", .entry, .detail), "", "the entry is suspended")
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntry).ActiveCount(), 0, "no site entry is active")
    For who = "user:ut", "policy", "lead:C-OTHER", "incident" { Do $$$AssertEquals(..Why(a(who), p(who), c(who)), "catalogue_changed", who _ ": still void with the entry suspended") }
    Do $$$AssertEquals($CLASSMETHOD(kit, "Approve", id, "resume"), "", "and resumed")
    For who = "user:ut", "policy", "lead:C-OTHER", "incident" { Do $$$AssertEquals(..Why(a(who), p(who), c(who)), "catalogue_changed", who _ ": still void with it resumed") }
    // A plan made now stands.
    Set fresh = ..Resend(c("user:ut"), "run:2")
    Do $$$AssertEquals(..Why(..Approval(c("user:ut"), fresh, "user:ut"), fresh, c("user:ut")), "catalogue_changed", "a plan made now on the old evidence records the old version, and is void too")
    Do $CLASSMETHOD(kit, "Snapshot", c("user:ut"))
    Set fresh = ..Resend(c("user:ut"), "run:3")
    Do $$$AssertEquals(..Why(..Approval(c("user:ut"), fresh, "user:ut"), fresh, c("user:ut")), "", "a plan made on fresh evidence under the new version stands")
    Do $$$AssertStatusOK(c("incident").SetIncident(""), "the fourth case leaves the incident")
    Set incId = inc.%Id()
    Kill inc
    Do ##class(Shutter.Store.Incident).%DeleteId(incId)
}

/// A closure not yet verified, planned before an activation: it has no approval to void, so the workflow checks it. At
/// the proposal gate and again when the verification answers, the case is sent back for fresh evidence and is not closed.
Method TestAClosurePlannedBeforeAnActivationIsPlannedAgain()
{
    Set kit = "Shutter.Test.SiteKit"
    Set closure = {"disposition": "superseded", "action": {"type": "none"}, "summary": "A later transfer moved the encounter on"}
    Set pass = ##class(Shutter.Msg.GateResult).%New()
    Set pass.Outcome = "pass", pass.Summary = "Every check passed", pass.ChecksJSON = "[]"
    // One at the gate, one already verifying.
    Set atGate = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "state": "investigating"})
    Set wf1 = ##class(Shutter.Test.SiteWorkflow).%New("Case Workflow")
    Set wf1.CaseId = atGate.CaseId, wf1.Mode = "policy"
    Do $$$AssertStatusOK(wf1.AdoptPlan(atGate, closure, "policy:E1"), "a closure is planned")
    Set verifying = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "state": "investigating"})
    Set wf2 = ##class(Shutter.Test.SiteWorkflow).%New("Case Workflow")
    Set wf2.CaseId = verifying.CaseId, wf2.Mode = "policy"
    Do $$$AssertStatusOK(wf2.AdoptPlan(verifying, closure, "policy:E1"), "another closure is planned")
    Do $$$AssertStatusOK(wf2.OnGateProposal(verifying, pass), "and passes the gate")
    Do $$$AssertEquals(verifying.State, "verifying", "it is being verified")
    // A third closes as it always did: no activation falls in its way.
    Set plain = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "state": "investigating"})
    Set wf3 = ##class(Shutter.Test.SiteWorkflow).%New("Case Workflow")
    Set wf3.CaseId = plain.CaseId, wf3.Mode = "policy"
    Do $$$AssertStatusOK(wf3.AdoptPlan(plain, closure, "policy:E1"), "a third closure is planned")
    Do $$$AssertStatusOK(wf3.OnGateProposal(plain, pass), "and passes the gate")
    Set verified = ##class(Shutter.Msg.VerifyResult).%New()
    Set verified.Outcome = "verified", verified.Summary = "Superseded by a later transfer", verified.DetailJSON = "{}"
    Do $$$AssertStatusOK(wf3.OnVerify(plain, verified), "and is verified")
    Do $$$AssertEquals(plain.State, "resolved", "with no activation, a closure closes as before")
    Do $$$AssertEquals(+$GET(^||Shutter.Test.SiteWorkflow("evidence")), 0, "and no evidence is asked for again")
    // The activation.
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "a site entry is activated")
    Do $$$AssertStatusOK(wf1.OnGateProposal(atGate, pass), "the first closure's gate answers")
    Do $$$AssertEquals(atGate.State, "collecting", "the case is sent back for fresh evidence")
    Do $$$AssertEquals(wf1.PlanId, "", "its plan is dropped")
    Do $$$AssertStatusOK(wf2.OnVerify(verifying, verified), "the second closure's verification answers")
    Do $$$AssertEquals(verifying.State, "collecting", "that case is sent back too, not resolved")
    Do $$$AssertEquals(verifying.Outcome, "", "and carries no outcome")
    Do $$$AssertEquals(+$GET(^||Shutter.Test.SiteWorkflow("evidence")), 2, "evidence was asked for twice")
    Set text = "", cid = atGate.%Id()
    &sql(SELECT TOP 1 Text INTO :text FROM Shutter_Store.CaseEvent WHERE "Case" = :cid AND Text LIKE '%catalogue changed%' ORDER BY Seq DESC)
    Do $$$AssertTrue(text [ "never completed", "the trail says why: " _ text)
    // Bounded: a catalogue that keeps changing does not loop a case for ever.
    Set wf1.Refreshes = wf1.MaxRefreshes
    Do $CLASSMETHOD(kit, "Snapshot", atGate)
    Do $$$AssertStatusOK(wf1.AdoptPlan(atGate, closure, "policy:E1"), "planned again")
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntry).Suspend(id, "unit test", "ut-approver", "api", .entry, .detail), "", "and the catalogue changes once more")
    Do $$$AssertStatusOK(wf1.OnGateProposal(atGate, pass), "the gate answers")
    Do $$$AssertEquals(atGate.State, "blocked", "at the limit a person looks")
}

/// A verification that answers for a case whose plan can no longer be read, with no write on record: whether the plan
/// wrote nothing, and so whether the closure rules hold, cannot be told, so the case goes to a person and is not closed.
/// Before, the closure rules were passed over and the case resolved.
Method TestAVerificationWithNoPlanToReadDoesNotClose()
{
    Set kit = "Shutter.Test.SiteKit"
    Set closure = {"disposition": "superseded", "action": {"type": "none"}, "summary": "A later transfer moved the encounter on"}
    Set pass = ##class(Shutter.Msg.GateResult).%New()
    Set pass.Outcome = "pass", pass.Summary = "Every check passed", pass.ChecksJSON = "[]"
    Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "state": "investigating"})
    Set wf = ##class(Shutter.Test.SiteWorkflow).%New("Case Workflow")
    Set wf.CaseId = case.CaseId, wf.Mode = "policy"
    Do $$$AssertStatusOK(wf.AdoptPlan(case, closure, "policy:E1"), "a closure is planned")
    Do $$$AssertStatusOK(wf.OnGateProposal(case, pass), "and passes the gate")
    Do $$$AssertEquals(case.State, "verifying", "it is being verified")
    // The plan the workflow names is no longer there to read.
    Set wf.PlanId = "999999999"
    Set verified = ##class(Shutter.Msg.VerifyResult).%New()
    Set verified.Outcome = "verified", verified.Summary = "Superseded by a later transfer", verified.DetailJSON = "{}"
    Do $$$AssertStatusOK(wf.OnVerify(case, verified), "the verification answers")
    Do $$$AssertEquals(case.State, "escalated", "a person decides, the case is not closed")
    Do $$$AssertEquals(case.Outcome, "", "and it carries no outcome")
    Do $$$AssertTrue(case.Headline [ "cannot be read", "the headline says why: " _ case.Headline)
}

/// On fresh evidence a site entry answers alone, wherever the workflow would otherwise have gone: in Site policy and
/// Board mode, in an incident's release on a policy chain, and before the case can follow another's board. A person's
/// convened board still convenes. Rules only stays the baseline. And a closure on such a case never happens without a
/// person (R18).
Method TestTheSiteEntryAnswersInEveryMode()
{
    Set kit = "Shutter.Test.SiteKit"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "a site entry is active")
    For how = "policy", "board", "single", "release", "rules" {
        Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "state": "collecting", "mode": ($SELECT(how = "release": "policy", 1: how))}, .snap)
        Set wf = ##class(Shutter.Test.SiteWorkflow).%New("Case Workflow")
        Set wf.CaseId = case.CaseId, wf.Mode = case.Mode
        If how = "release" Set wf.Release = 1, wf.ChainDecides = "policy", wf.ChainKind = "ordered", wf.IncidentId = "I-UT", wf.ReleasePolicy = "automatic"
        Set result = ##class(Shutter.Msg.EvidenceResult).%New()
        Set result.SnapshotId = snap.%Id(), result.Digest = snap.Digest, result.SummaryJSON = snap.SummaryObject().%ToJSON()
        If how = "rules" {
            // Rules only convenes nobody and proposes the plain resend: the case records the entry all the same, and the
            // real gate blocks the resend (ENTRY_NOT_NAMED_WRITE), so it waits for a person.
            Do $$$AssertStatusOK(wf.OnEvidence(case, result), "rules: the evidence is taken")
            Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(case.CaseId).SiteEntry, id, "rules: the case records the entry, in Rules only too")
            Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
            Do $$$AssertTrue($ISOBJECT(plan), "rules: the plain resend is planned")
            Continue:'$ISOBJECT(plan)
            Do $$$AssertEquals(plan.CreatedBy, "rules", "rules: by the rules path, not the site entry's person path")
            Set req = ##class(Shutter.Msg.GateRequest).%New()
            Set req.CaseId = case.CaseId, req.PlanId = plan.%Id(), req.Stage = "proposal", req.Receiver = case.Receiver, req.ChainKind = "single"
            Set gate = ##class(Shutter.Operation.Gate).%New("Shutter Gate (unit test)")
            Do $$$AssertStatusOK(gate.OnGateRequest(req, .resp), "rules: the gate ran")
            Do $$$AssertTrue(resp.Summary [ "ENTRY_NOT_NAMED_WRITE", "rules: the gate blocks the resend: " _ resp.Summary)
            Do $$$AssertNotEquals(resp.Outcome, "pass", "rules: and it does not pass")
            Set rulesCase = case
            Continue
        }
        Do $$$AssertStatusOK(wf.OnEvidence(case, result), how _ ": the evidence is taken")
        Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
        Do $$$AssertTrue($ISOBJECT(plan), how _ ": a plan is adopted at once, with no board")
        Continue:'$ISOBJECT(plan)
        Do $$$AssertEquals(plan.Disposition, "escalate", how _ ": it asks for a person")
        Do $$$AssertEquals(plan.CatalogueEntry, id, how _ ": naming the site entry")
        Do $$$AssertEquals(plan.CreatedBy, "policy:" _ id, how _ ": made by the catalogue")
        Do $$$AssertNotTrue(plan.IsWrite(), how _ ": it writes nothing")
        Set pass = ##class(Shutter.Msg.GateResult).%New()
        Set pass.Outcome = "pass", pass.Summary = "Every check passed", pass.ChecksJSON = "[]"
        Do $$$AssertStatusOK(wf.OnGateProposal(case, pass), how _ ": the gate answers")
        Do $$$AssertEquals(case.State, "escalated", how _ ": the case is escalated")
        Set note = "", cid = case.%Id()
        &sql(SELECT TOP 1 Text INTO :note FROM Shutter_Store.CaseEvent WHERE "Case" = :cid AND Text LIKE '%own scenario%' ORDER BY Seq)
        Do $$$AssertTrue(note [ "Without it: E2", how _ ": the trail names what it displaced: " _ note)
        Do $$$AssertTrue(note [ "Ring the ward", how _ ": and the site's instructions")
    }
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntry).CasesSent(id), 4, "four cases were sent to a person by the entry")
    // The Rules only case, reopened on evidence that no longer meets the entry: a closure planned then still needs a person.
    If $ISOBJECT($GET(rulesCase)) {
        Set stored = ##class(Shutter.Store.Case).%OpenId(rulesCase.%Id())
        Set stored.Ward = "WARD-B", stored.State = "investigating"
        Do $$$AssertStatusOK(stored.%Save(), "rules: the case reads another ward now")
        Do $CLASSMETHOD(kit, "Snapshot", stored)
        Set wf = ##class(Shutter.Test.SiteWorkflow).%New("Case Workflow")
        Set wf.CaseId = stored.CaseId, wf.Mode = "rules"
        Do $$$AssertStatusOK(wf.AdoptPlan(stored, {"disposition": "superseded", "action": {"type": "none"}, "summary": "A later transfer moved the encounter on"}, "run:9"), "rules: a closure on the fresh evidence")
        Set pass = ##class(Shutter.Msg.GateResult).%New()
        Set pass.Outcome = "pass", pass.Summary = "Every check passed", pass.ChecksJSON = "[]"
        Do $$$AssertStatusOK(wf.OnGateProposal(stored, pass), "rules: the gate passes it")
        Do $$$AssertEquals(stored.State, "escalated", "rules: the case goes to a person, not to the verifier")
    }
    // A board a person convened on such a case plans to close it, naming no entry: the gate passes that (ENTRY_NOT_NAMED),
    // and the workflow sends the case to a person with the board's reasoning (R18).
    Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "state": "investigating", "mode": "board"}, .snap)
    Set wf = ##class(Shutter.Test.SiteWorkflow).%New("Case Workflow")
    Set wf.CaseId = case.CaseId, wf.Mode = "board", wf.ForceBoard = 1, wf.ConvenedBy = "ut-approver"
    Do $$$AssertStatusOK(wf.AdoptPlan(case, {"disposition": "superseded", "action": {"type": "none"}, "summary": "The board thinks a later transfer moved the encounter on"}, "run:9"), "a convened board plans a closure")
    Set pass = ##class(Shutter.Msg.GateResult).%New()
    Set pass.Outcome = "pass", pass.Summary = "Every check passed", pass.ChecksJSON = "[]"
    Do $$$AssertStatusOK(wf.OnGateProposal(case, pass), "the gate passes it")
    Do $$$AssertEquals(case.State, "escalated", "the case goes to a person, not to the verifier")
    Do $$$AssertTrue(case.Headline [ id, "the headline names the site entry: " _ case.Headline)
    Set text = "", cid = case.%Id()
    &sql(SELECT TOP 1 Text INTO :text FROM Shutter_Store.CaseEvent WHERE "Case" = :cid AND ToState = 'escalated' ORDER BY Seq DESC)
    Do $$$AssertTrue(text [ "never closed without a person", "and the trail says why: " _ text)
    Do $$$AssertTrue(text [ "The board thinks", "with the board's reasoning")
    // The same plan on the near miss, which the entry does not match, closes as it always did.
    Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "state": "investigating", "mode": "board"}, .snap)
    Set wf = ##class(Shutter.Test.SiteWorkflow).%New("Case Workflow")
    Set wf.CaseId = case.CaseId, wf.Mode = "board"
    Do $$$AssertStatusOK(wf.AdoptPlan(case, {"disposition": "superseded", "action": {"type": "none"}, "summary": "A later transfer moved the encounter on"}, "run:9"), "the same plan on the near miss")
    Do $$$AssertStatusOK(wf.OnGateProposal(case, pass), "the gate passes it")
    Do $$$AssertEquals(case.State, "verifying", "goes on to close")
}

/// R18 after a reopening: the case records the site entry that matched its evidence, so a closure planned on fresh
/// evidence that no longer matches the entry still goes to a person. Before, the hold read the plan's own snapshot only.
Method TestAReopenedCaseIsStillTheEntrys()
{
    Set kit = "Shutter.Test.SiteKit"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "a site entry is active")
    Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "state": "collecting", "mode": "policy"}, .snap)
    Set wf = ##class(Shutter.Test.SiteWorkflow).%New("Case Workflow")
    Set wf.CaseId = case.CaseId, wf.Mode = case.Mode
    Set result = ##class(Shutter.Msg.EvidenceResult).%New()
    Set result.SnapshotId = snap.%Id(), result.Digest = snap.Digest, result.SummaryJSON = snap.SummaryObject().%ToJSON()
    Do $$$AssertStatusOK(wf.OnEvidence(case, result), "the evidence is taken")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(case.CaseId).SiteEntry, id, "the case records the entry that matched it")
    Set pass = ##class(Shutter.Msg.GateResult).%New()
    Set pass.Outcome = "pass", pass.Summary = "Every check passed", pass.ChecksJSON = "[]"
    Do $$$AssertStatusOK(wf.OnGateProposal(case, pass), "the gate answers")
    Do $$$AssertEquals(case.State, "escalated", "the case is escalated")
    // The system reopens it, and the fresh evidence no longer matches the entry.
    Set stored = ##class(Shutter.Store.Case).%OpenId(case.%Id())
    Set stored.Ward = "WARD-B"
    Do $$$AssertStatusOK(stored.%Save(), "the case's ward now reads otherwise")
    Do $$$AssertEquals(stored.SiteEntry, id, "a whole save keeps what the case recorded")
    Set fresh = $CLASSMETHOD(kit, "Snapshot", stored)
    Do $$$AssertNotEquals(fresh.SummaryObject().catalogue.entry, id, "the fresh evidence is not the entry's")
    Do $$$AssertStatusOK(stored.Transition("investigating", "Reopened by the system", "system"), "reopened")
    Set wf2 = ##class(Shutter.Test.SiteWorkflow).%New("Case Workflow")
    Set wf2.CaseId = stored.CaseId, wf2.Mode = "policy"
    Do $$$AssertStatusOK(wf2.AdoptPlan(stored, {"disposition": "superseded", "action": {"type": "none"}, "summary": "A later transfer moved the encounter on"}, "run:9"), "a plan to close it on the fresh evidence")
    Do $$$AssertStatusOK(wf2.OnGateProposal(stored, pass), "the gate passes it")
    Do $$$AssertEquals(stored.State, "escalated", "the case goes to a person, not to the verifier")
    Do $$$AssertTrue(stored.Headline [ id, "naming the entry: " _ stored.Headline)
    // The engine's own delivery does not close it either, whatever its current evidence says.
    Set row = {"check": "ordering", "result": "block", "reason_code": "ENGINE_DELIVERED", "detail": "delivered", "engine": {"words": "The engine delivered this message (header 77)"}}
    Do row.engine.%Set("established", 1, "boolean")
    Do $$$AssertStatusOK(##class(Shutter.Util.EngineCheck).Settle(stored, row, [(row)], "gate:ut"), "the engine's delivery read")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(stored.CaseId).State, "blocked", "is left for a person")
}

/// A change takes the stored row as it is under the lock, never a copy the process already had open: here the stored row
/// is changed behind a copy, as another process's commit changes it. Before, the copy's old state was checked and saved
/// over the stored one, undoing a suspension or a recheck's widening.
Method TestAStaleCopyIsNeverSaved()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set body = $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId)
    Set held = $CLASSMETHOD(site, "ById", id), revision = held.Revision
    &sql(UPDATE Shutter_Catalogue.SiteEntry SET State = 'suspended', Revision = Revision + 1 WHERE EntryId = :id)
    Do $$$AssertEquals(SQLCODE, 0, "the stored row is suspended behind the copy")
    Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, body, revision, "ut-author", "api", .e, .problems, .warnings, .detail), "stale_version", "a change on the copy's revision is refused")
    Set state = ""
    &sql(SELECT State INTO :state FROM Shutter_Catalogue.SiteEntry WHERE EntryId = :id)
    Do $$$AssertEquals(state, "suspended", "and the stored state stands")
    // A widening, which changes no revision, saved behind the copy: the change goes on and keeps it.
    Set wide = "{""delivery"":[""failed"",""rejected"",""uncertain""]}", revision = revision + 1
    &sql(UPDATE Shutter_Catalogue.SiteEntry SET State = 'active', EffectiveJSON = :wide, NeedsReview = 1 WHERE EntryId = :id)
    Set body.title = "A changed title"
    Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, body, revision, "ut-author", "api", .e, .problems, .warnings, .detail), "", "a change on the current revision: " _ detail)
    Set stored = "", flag = ""
    &sql(SELECT State, EffectiveJSON, NeedsReview INTO :state, :stored, :flag FROM Shutter_Catalogue.SiteEntry WHERE EntryId = :id)
    Do $$$AssertEquals(state, "active", "the state as stored")
    Do $$$AssertEquals(stored, wide, "the widening survives the change")
    Do $$$AssertEquals(+flag, 1, "and so does its flag")
}

/// A whole save of a copy read before the case recorded its site entry keeps the record (Case.%OnBeforeSave).
Method TestAnOlderCopyOfTheCaseKeepsTheRecord()
{
    Set kit = "Shutter.Test.SiteKit"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "state": "escalated"})
    Set copy = ##class(Shutter.Store.Case).%OpenId(case.%Id()), cid = case.%Id()
    Do $$$AssertEquals(copy.SiteEntry, "", "a copy with no record")
    &sql(UPDATE Shutter_Store."Case" SET SiteEntry = :id WHERE ID = :cid)
    Set copy.Headline = "Saved by an older copy"
    Do $$$AssertStatusOK(copy.%Save(), "the older copy is saved whole")
    Set stored = ""
    &sql(SELECT SiteEntry INTO :stored FROM Shutter_Store."Case" WHERE ID = :cid)
    Do $$$AssertEquals(stored, id, "the record stays")
}

/// A case one of the site's own entries stopped once is never written and closed with no person: on fresh evidence that
/// matches a shipped policy entry, an item an incident released by policy or under its approval stops, and the site's
/// own automatic release would ask a person. Before, the write was released by policy with nothing naming the entry.
Method TestAMarkedCaseIsNotReleasedWithoutAPerson()
{
    Set kit = "Shutter.Test.SiteKit"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    For policy = "automatic", "incident" {
        Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "state": "investigating", "mode": "policy"}, .snap)
        Set summary = snap.SummaryObject(), cat = summary.catalogue
        Do $$$AssertEquals(cat.decision, "policy", policy _ ": the fresh evidence is a shipped policy entry's (" _ cat.entry _ ")")
        Do $$$AssertStatusOK(case.MarkSiteEntry(id), policy _ ": an earlier investigation matched the site entry")
        Set wf = ##class(Shutter.Test.SiteWorkflow).%New("Case Workflow")
        Set wf.CaseId = case.CaseId, wf.Mode = "policy", wf.Release = 1, wf.ReleasePolicy = policy, wf.ChainDecides = "policy", wf.ChainKind = "single", wf.IncidentId = "I-UT", wf.ChainSeq = 1, wf.ChainPosition = 1
        Set wf.IncidentEntry = cat.entry, wf.IncidentOutcome = cat.outcome
        Do $$$AssertStatusOK(wf.PolicyPath(case, summary, cat), policy _ ": the policy path")
        Do $$$AssertEquals(case.State, "blocked", policy _ ": the item stops for a person")
        Do $$$AssertTrue(case.Headline [ id, policy _ ": naming the entry: " _ case.Headline)
        Do $$$AssertEquals(wf.PlanId, "", policy _ ": and nothing is planned")
    }
}

}
