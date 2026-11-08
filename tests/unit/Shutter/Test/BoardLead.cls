/// One board per failure signature (Shutter.Util.Signature and Shutter.Store.BoardLead; CONTRACTS 6.6, v1.35): the
/// signature's parts and normalisation, the lead's window, finish, expiry and the reset stamp, and a leader that fails or
/// is abandoned finishing its lead, so its followers are released. The rows written are deleted at the end. The leader
/// tests drive an instance of the Case Workflow item outside the production, with no case following the lead, so no
/// LeadReady goes to the production; that a follower is told is proved by the scenario runs. A case no board can answer:
/// outside Rules only it goes to a person when the catalogue gives it to the board or a person (NoBoard).
Class Shutter.Test.BoardLead Extends %UnitTest.TestCase
{

Property Sigs As %String [ MultiDimensional ];

Property SavedWindow As %String;

Property SavedReset As %String;

Method OnBeforeAllTests() As %Status
{
    Set ..SavedWindow = $GET(^Shutter.Config("leadWindowSeconds"), $CHAR(0))
    Set ..SavedReset = $GET(^Shutter.Config("resetAt"), $CHAR(0))
    Kill ^Shutter.Config("leadWindowSeconds")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Set sig = ""
    For {
        Set sig = $ORDER(..Sigs(sig)) Quit:sig=""
        &sql(DELETE FROM Shutter_Store.BoardLead WHERE Signature = :sig)
    }
    For caseId = "C-TEST-LEAD-A", "C-TEST-LEAD-B", "C-TEST-LEAD-C", "C-TEST-LEAD-D" { Do ..Purge(caseId) }
    If ..SavedWindow = $CHAR(0) { Kill ^Shutter.Config("leadWindowSeconds") } Else { Set ^Shutter.Config("leadWindowSeconds") = ..SavedWindow }
    If ..SavedReset = $CHAR(0) { Kill ^Shutter.Config("resetAt") } Else { Set ^Shutter.Config("resetAt") = ..SavedReset }
    Quit $$$OK
}

Method Case(receiver As %String, text As %String, scenario As %String = "") As Shutter.Store.Case
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "C-TEST-LEAD", c.Receiver = receiver, c.FailureKind = "delivery_failed", c.FailureText = text, c.Scenario = scenario
    Quit c
}

Method Summary(answer As %String = "unavailable", entry As %String = "E2") As %DynamicObject
{
    Quit {"catalogue": {"conditions": {"receiver_answer": (answer), "delivery": "failed"}, "entry": (entry), "outcome": "resend"}}
}

Method TestSignature()
{
    Set sig = "Shutter.Util.Signature"
    Do $$$AssertEquals($CLASSMETHOD(sig, "Normalise", "Delivery unavailable (ward_unavailable), HTTP 503: version 7, digest sha256:ab12ff"), "delivery unavailable ward unavailable http # version # digest #", "lower case, numbers and digests as #, punctuation dropped")
    Set a = $CLASSMETHOD(sig, "Of", ..Case("Downstream Out", "Delivery unavailable (ward_unavailable), HTTP 503: The downstream system is unavailable, version 7"), ..Summary())
    Set b = $CLASSMETHOD(sig, "Of", ..Case("Downstream Out", "Delivery unavailable (ward_unavailable), HTTP 503: The downstream system is unavailable, version 12"), ..Summary())
    Do $$$AssertEquals(a, b, "two cases of the same failure share a signature whatever the numbers")
    Do $$$AssertTrue($MATCH(a, "^sha256:[0-9a-f]{64}$"), "a digest")
    Do $$$AssertNotEquals(a, $CLASSMETHOD(sig, "Of", ..Case("Records Out", "Delivery unavailable (ward_unavailable), HTTP 503"), ..Summary()), "another receiver, another signature")
    Do $$$AssertNotEquals(a, $CLASSMETHOD(sig, "Of", ..Case("Downstream Out", "Delivery unavailable (ward_unavailable), HTTP 503"), ..Summary("timeout")), "another answer, another signature")
    Do $$$AssertNotEquals(a, $CLASSMETHOD(sig, "Of", ..Case("Downstream Out", "Delivery unavailable (ward_unavailable), HTTP 503"), ..Summary("unavailable", "E3")), "another entry, another signature")
    Do $$$AssertNotEquals(a, $CLASSMETHOD(sig, "Of", ..Case("Downstream Out", "Delivery unavailable (ward_unavailable), HTTP 503", "S2"), ..Summary()), "a scenario stamp makes its own signature")
    Do $$$AssertEquals($CLASSMETHOD(sig, "Of", "", ..Summary()), "", "no case, no signature")
    Set parts = $CLASSMETHOD(sig, "Parts", ..Case("Downstream Out", "x"), ..Summary())
    Do $$$AssertEquals(parts.receiver _ "|" _ parts."receiver_answer" _ "|" _ parts.entry _ "|" _ parts."policy_version", "Downstream Out|unavailable|E2|" _ ##class(Shutter.Operation.Gate).#POLICYVERSION, "the parts")
}

Method TestLeadWindow()
{
    Set bl = "Shutter.Store.BoardLead"
    Do $$$AssertEquals($CLASSMETHOD(bl, "WindowSeconds"), 600, "ten minutes by default")
    Set ^Shutter.Config("leadWindowSeconds") = 0
    Do $$$AssertEquals($CLASSMETHOD(bl, "WindowSeconds"), 0, "nought switches the coalescing off")
    Set ^Shutter.Config("leadWindowSeconds") = "soon"
    Do $$$AssertEquals($CLASSMETHOD(bl, "WindowSeconds"), 600, "a bad value means the default")
    Set ^Shutter.Config("leadWindowSeconds") = 120
    Do $$$AssertEquals($CLASSMETHOD(bl, "WindowSeconds"), 120, "two minutes when the site says so")
    Kill ^Shutter.Config("leadWindowSeconds"), ^Shutter.Config("resetAt")
    Set sig = "sha256:test-lead-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set ..Sigs(sig) = ""
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "no lead yet")
    Set leader = ..Case("Downstream Out", "x")
    Set leader.CaseId = "C-TEST-LEADER"
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig, leader, {"receiver": "Downstream Out"}, .lead), "a lead begins")
    Do $$$AssertEquals(lead.State _ "|" _ lead.LeaderCaseId, "running|C-TEST-LEADER", "running, led by the first case")
    Do $$$AssertTrue(##class(Shutter.Util.Time).SecondsBetween(##class(Shutter.Util.Time).NowUTC(), lead.ExpiresAt) > 590, "for the window")
    Set cur = $CLASSMETHOD(bl, "Current", sig)
    Do $$$AssertTrue($ISOBJECT(cur) && (cur.%Id() = lead.%Id()), "a case of the signature finds it")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Finish", "C-NOBODY", "done")), "a case that leads nothing finishes nothing")
    Set done = $CLASSMETHOD(bl, "Finish", "C-TEST-LEADER", "done", {"disposition": "resend", "action": {"type": "resend"}}, [{"memberCode": "impact", "disposition": "resend", "confidence": 0.9}])
    Do $$$AssertEquals(done.State, "done", "done with the plan")
    Do $$$AssertEquals(done.Projection().plan.disposition _ "|" _ done.Projection().verdicts.%Get(0).memberCode, "resend|impact", "the plan and the verdicts as objects")
    Do $$$AssertEquals(done.EndedAt '= "", 1, "ended")
    Do $$$AssertEquals($CLASSMETHOD(bl, "Finish", "C-TEST-LEADER", "failed").State, "done", "finished once; a later finish changes nothing")
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "a done lead still attracts followers within the window")
    Do $$$AssertStatusOK(done.Followed(), "a follower counted")
    Do $$$AssertEquals($CLASSMETHOD(bl, "ForLeader", "C-TEST-LEADER").Followers, 1, "one follower")
    // A reset after the lead began: the lead counts for nothing, as the incident detector's window.
    Set ^Shutter.Config("resetAt") = ##class(Shutter.Util.Time).FromNow(5)
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "a lead begun before the last reset is not followed")
    Kill ^Shutter.Config("resetAt")
    // An expired lead.
    Set done.ExpiresAt = ##class(Shutter.Util.Time).FromNow(-1)
    Do $$$AssertStatusOK(done.%Save(), "expired by hand")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "an expired lead is not followed")
    // A failed lead.
    Set sig2 = sig _ "-f"
    Set ..Sigs(sig2) = ""
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig2, leader, "", .lead2), "another lead")
    Set failed = $CLASSMETHOD(bl, "Finish", "C-TEST-LEADER", "failed", "", "", "the coordinator did not answer")
    Do $$$AssertEquals(failed.State _ "|" _ failed.Reason, "failed|the coordinator did not answer", "failed with the reason")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig2)), "a failed lead attracts no followers")
    Do $$$AssertEquals($CLASSMETHOD(bl, "FollowersOf", "C-NOBODY").%Size(), 0, "nobody follows a case that is not there")
    Do $$$AssertEquals($CLASSMETHOD(bl, "VerdictsOf", "").%Size(), 0, "no snapshot, no verdicts")
}

/// A saved case in investigating, under its own public id outside the case counter.
Method SavedCase(caseId As %String) As Shutter.Store.Case
{
    Do ..Purge(caseId)
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = caseId, c.Receiver = "Downstream Out", c.OperationKey = "PAS^HOSP^MRN9004^ENC-9004^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.EncounterId = "ENC-9004", c.PatientId = "MRN9004", c.FailureKind = "delivery_failed", c.FailureText = "x"
    Set c.State = "investigating", c.Headline = "The transfer was not delivered"
    Set c.OpenedAt = ##class(Shutter.Util.Time).NowUTC(), c.UpdatedAt = c.OpenedAt
    Do $$$AssertStatusOK(c.%Save(), "the case " _ caseId _ " is saved")
    Quit c
}

/// Deletes a test case's events and counters and the case itself, whichever exist (a run that stopped half-way may have
/// left them).
ClassMethod Purge(caseId As %String)
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", caseId)
    While rs.%Next() {
        Set id = rs.%Get("ID")
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
        Kill ^Shutter.Counter("event", id), ^Shutter.Counter("plan", id)
        If ##class(Shutter.Store.Case).%ExistsId(id) Do ##class(Shutter.Store.Case).%DeleteId(id)
    }
}

/// A case workflow instance of the production's item, driven here outside the production: it sends nothing while no
/// case follows the lead, so the production never sees a test case.
Method Instance() As Shutter.Process.CaseWorkflow
{
    Set wf = ##class(Shutter.Process.CaseWorkflow).%New("Case Workflow")
    Do $$$AssertTrue($ISOBJECT(wf), "an instance of the Case Workflow item")
    Quit wf
}

/// A leader whose workflow errors (a member call answered with an error status) finishes its lead as failed before the
/// case fails, so the signature attracts no new follower, and the cases already following it are told at once and take
/// what a case with no board answer gets (OnLeadReady on a failed lead) instead of waiting out the bound. A case that follows it is told
/// through the production, so the proof that it is told is the scenario runs; here nobody follows, and nobody is told.
/// The stamps are whole seconds. A replayed board begins and ends within one, so the next scenario's reset can carry the
/// same stamp as the lead of the run before it, and that run's case must not take the earlier board's decision.
Method TestALeadInTheSecondOfTheResetIsNotFollowed()
{
    Set bl = "Shutter.Store.BoardLead"
    Kill ^Shutter.Config("leadWindowSeconds"), ^Shutter.Config("resetAt")
    Set sig = "sha256:test-lead-tie-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set ..Sigs(sig) = ""
    Set leader = ..Case("Downstream Out", "x")
    Set leader.CaseId = "C-TEST-LEADER"
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig, leader, {"receiver": "Downstream Out"}, .lead), "a lead begins")
    Set done = $CLASSMETHOD(bl, "Finish", "C-TEST-LEADER", "done", {"disposition": "escalate", "action": {"type": "none"}})
    Do $$$AssertEquals(done.State, "done", "the board has decided")
    Set ^Shutter.Config("resetAt") = ##class(Shutter.Util.Time).FromNow(-5)
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "a lead begun after the last reset is followed")
    Set ^Shutter.Config("resetAt") = lead.StartedAt
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "a lead stamped in the second of the reset is not followed")
    Kill ^Shutter.Config("resetAt")
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "with no reset the lead is followed")
}

Method TestLeaderFailureFinishesTheLead()
{
    Set bl = "Shutter.Store.BoardLead"
    Kill ^Shutter.Config("leadWindowSeconds"), ^Shutter.Config("resetAt")
    Set sig = "sha256:test-lead-fail-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set ..Sigs(sig) = ""
    Set leader = ..SavedCase("C-TEST-LEAD-A")
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig, leader, "", .lead), "the leader's lead begins")
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "a case of the signature would follow it")
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-A", wf.LeadSignature = sig, wf.PendingJSON = ["conformance"].%ToJSON()
    Do $$$AssertStatusOK(wf.OnError("", .response, "", $$$ERROR($$$GeneralError, "the member item is not running"), "member:conformance"), "the error of an awaited member call is handled")
    Set after = $CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-A")
    Do $$$AssertEquals(after.State, "failed", "the lead is finished as failed")
    Do $$$AssertEquals(after.Reason, "the leader's workflow failed: ERROR #5001: the member item is not running", "with the reason")
    Do $$$AssertNotEquals(after.EndedAt, "", "and ended")
    Do $$$AssertEquals(wf.LeadSignature, "", "the instance leads nothing now")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-A").State, "failed", "the case failed with the error")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "a new case of the signature leads itself instead of following the dead lead")
    Do $$$AssertEquals(wf.TellFollowers("C-TEST-LEAD-A", after), 0, "nobody was waiting, so nobody is told")
}

/// A member who did not answer is recorded on the plan the others' findings made and named in the approval task, so the
/// approver sees a thinner review.
Method TestAbsentMembersAreOnThePlanAndTheTask()
{
    Set c = ..SavedCase("C-TEST-LEAD-P")
    Set snap = ##class(Shutter.Store.Snapshot).Begin(c)
    Do $$$AssertStatusOK(snap.%Save(), "a snapshot")
    Do $$$AssertStatusOK(c.SetSnapshot(snap), "the case's current one")
    Set wf = ##class(Shutter.Test.QuietWorkflow).%New("Case Workflow")
    Set wf.CaseId = "C-TEST-LEAD-P", wf.FailedJSON = ["encounter"].%ToJSON()
    Do $$$AssertStatusOK(wf.AdoptPlan(c, {"disposition": "resend", "action": {"type": "resend", "operation_key": (c.OperationKey), "expected_version": 3}, "summary": "Resend the transfer"}, "run:1"), "the coordinator's plan is adopted")
    Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
    Set absent = plan.PlanObject().%Get("absent_members")
    Do $$$AssertTrue($ISOBJECT(absent) && (absent.%Size() = 1), "the plan records who was absent")
    If $ISOBJECT(absent) && (absent.%Size() = 1) Do $$$AssertTrue(absent.%Get(0) '= "", "by name: " _ absent.%Get(0))
    Set task = ##class(Shutter.Process.CaseWorkflow).ApprovalTask(c, plan)
    Do $$$AssertTrue(task.%Message [ "did not answer", "the task says a member did not answer: " _ task.%Message)
    If $ISOBJECT(absent) && (absent.%Size() = 1) Do $$$AssertTrue(task.%Message [ absent.%Get(0), "and names them")
    // A full board: nothing is added.
    Set wf.FailedJSON = "[]"
    Do $$$AssertStatusOK(wf.AdoptPlan(c, {"disposition": "resend", "action": {"type": "resend", "operation_key": (c.OperationKey), "expected_version": 3}, "summary": "Resend the transfer"}, "run:2"), "a full board's plan")
    Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
    Do $$$AssertNotTrue(plan.PlanObject().%IsDefined("absent_members"), "records nobody")
    Do $$$AssertNotTrue(##class(Shutter.Process.CaseWorkflow).ApprovalTask(c, plan).%Message [ "did not answer", "and the task says nothing")
    Do ..Purge("C-TEST-LEAD-P")
}

/// A plan that writes nothing from a board with a member missing goes to a person and doesn't close: a closure rests on the
/// whole review. A full board's closes as before, and a partial board's write goes on, since a person approves that anyway.
Method TestAPartialBoardsNoWritePlanGoesToAPerson()
{
    Set c = ..SavedCase("C-TEST-LEAD-Q")
    Set snap = ##class(Shutter.Store.Snapshot).Begin(c)
    Do $$$AssertStatusOK(snap.%Save(), "a snapshot")
    Do $$$AssertStatusOK(c.SetSnapshot(snap), "the case's current one")
    Set wf = ##class(Shutter.Test.QuietWorkflow).%New("Case Workflow")
    Set wf.CaseId = "C-TEST-LEAD-Q", wf.FailedJSON = ["encounter"].%ToJSON()
    Do $$$AssertStatusOK(wf.AdoptPlan(c, {"disposition": "superseded", "action": {"type": "none"}, "summary": "A later transfer moved the encounter on"}, "run:1"), "the partial board's plan")
    Set result = ##class(Shutter.Msg.GateResult).%New()
    Set result.Outcome = "pass", result.Summary = "Every check passed", result.ChecksJSON = "[]"
    Do $$$AssertStatusOK(wf.OnGateProposal(c, result), "the gate passed it")
    Set after = ##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-Q")
    Do $$$AssertEquals(after.State, "escalated", "a person decides, and it doesn't close")
    Do $$$AssertTrue(after.Headline [ "did not answer", "the case says why: " _ after.Headline)
    Do ..Purge("C-TEST-LEAD-Q")
    // A reconcile is a plan that writes nothing too.
    Set c = ..SavedCase("C-TEST-LEAD-Q")
    Set snap = ##class(Shutter.Store.Snapshot).Begin(c)
    Do $$$AssertStatusOK(snap.%Save(), "a snapshot")
    Do $$$AssertStatusOK(c.SetSnapshot(snap), "the case's current one")
    Set wf.PlanId = ""
    Do $$$AssertStatusOK(wf.AdoptPlan(c, {"disposition": "reconcile", "action": {"type": "reconcile", "operation_key": (c.OperationKey)}, "summary": "A receipt exists"}, "run:2"), "a partial board's reconcile")
    Do $$$AssertStatusOK(wf.OnGateProposal(c, result), "the gate passed it")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-Q").State, "escalated", "a person decides that too")
    Do ..Purge("C-TEST-LEAD-Q")
    // A full board's closure goes on to the verifier.
    Set c = ..SavedCase("C-TEST-LEAD-Q")
    Set snap = ##class(Shutter.Store.Snapshot).Begin(c)
    Do $$$AssertStatusOK(snap.%Save(), "a snapshot")
    Do $$$AssertStatusOK(c.SetSnapshot(snap), "the case's current one")
    Set wf.FailedJSON = "[]"
    Do $$$AssertStatusOK(wf.AdoptPlan(c, {"disposition": "superseded", "action": {"type": "none"}, "summary": "A later transfer moved the encounter on"}, "run:3"), "a full board's plan")
    Do $$$AssertStatusOK(wf.OnGateProposal(c, result), "the gate passed it")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-Q").State, "verifying", "it goes on to close")
    Do ..Purge("C-TEST-LEAD-Q")
}

/// A follower takes its leader's decision, and the missing member with it: it is the same thinner review.
Method TestAFollowerOfAPartialBoardCarriesWhoWasMissing()
{
    Set lead = ##class(Shutter.Store.BoardLead).%New()
    Set lead.LeaderCaseId = "C-TEST-LEAD-O", lead.DecidedBy = "run:1"
    Set lead.PlanJSON = {"disposition": "superseded", "action": {"type": "none"}, "absent_members": ["Encounter reviewer"], "summary": "A later transfer"}.%ToJSON()
    Set c = ..NoAnswerCase("C-TEST-LEAD-F2", "board", ..E2())
    Set wf = ..QuietInstance()
    Set wf.CaseId = "C-TEST-LEAD-F2", wf.Mode = "board"
    Do $$$AssertStatusOK(wf.TakeDiagnosis(c, lead), "the follower takes the decision")
    Set plan = ##class(Shutter.Store.Plan).%OpenId(wf.PlanId)
    Set absent = plan.PlanObject().%Get("absent_members")
    Do $$$AssertTrue($ISOBJECT(absent) && (absent.%Size() = 1), "the follower's plan says who was missing")
    Do ##class(Shutter.Store.Case).PurgeCase(c.%Id())
}

/// A lost admission released by an incident's automatic policy is asked of a person (the gate would refuse it otherwise), and
/// one released under the approval a person gave the incident's plan goes on under that approval.
Method TestAReleasedLostAdmissionAsksAPerson()
{
    Set c = ..NoAnswerCase("C-TEST-LEAD-A", "policy", ..E2())
    Set c.Event = "admit"
    Do $$$AssertStatusOK(c.%Save(), "an admission")
    Set summary = {"ward_state_http_status": 404, "operation": {"payload_digest": "sha256:ut"}}
    Set wf = ..QuietInstance()
    Set wf.CaseId = "C-TEST-LEAD-A", wf.Mode = "policy", wf.Release = 1, wf.ReleasePolicy = "automatic", wf.ChainKind = "single"
    Do $$$AssertStatusOK(wf.PolicyPath(c, summary, ..E2()), "the chain's automatic release")
    Do $$$AssertEquals(wf.Policy, "approval", "a person approves")
    Do ##class(Shutter.Store.Case).PurgeCase(c.%Id())
    Set c = ..NoAnswerCase("C-TEST-LEAD-A", "policy", ..E2())
    Set c.Event = "admit"
    Do $$$AssertStatusOK(c.%Save(), "an admission")
    Set wf = ..QuietInstance()
    Set wf.CaseId = "C-TEST-LEAD-A", wf.Mode = "policy", wf.Release = 1, wf.ReleasePolicy = "incident", wf.ChainKind = "single", wf.IncidentEntry = "E2", wf.IncidentOutcome = "resend"
    Do $$$AssertStatusOK(wf.PolicyPath(c, summary, ..E2()), "under the incident's approval")
    Do $$$AssertEquals(wf.Policy, "incident", "that approval stands")
    Do ##class(Shutter.Store.Case).PurgeCase(c.%Id())
}

/// A case reopened by someone without the live agents, whose board has no recording: it stays with a person and says why,
/// and no plan is made, since the plain resend would replace the board's stop with a plan nobody on the board looked at.
Method TestReopenedWithNoLiveAgentsAndNoRecording()
{
    Set c = ..SavedCase("C-TEST-LEAD-R")
    Set snap = ##class(Shutter.Store.Snapshot).Begin(c)
    Do $$$AssertStatusOK(snap.%Save(), "a snapshot")
    Do $$$AssertStatusOK(c.SetSnapshot(snap), "the case's current one")
    For member = "conformance", "encounter" {
        Set run = ##class(Shutter.Store.AgentRun).%New()
        Do run.CaseSetObjectId(c.%Id())
        Set run.Snapshot = snap, run.Status = "no_record"
        Do $$$AssertStatusOK(run.%Save(), member _ " has no recording")
    }
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-R", wf.Reopened = 1, wf.LiveAllowed = 0
    Do $$$AssertStatusOK(wf.AfterBoard(c), "the board's end is handled")
    Set after = ##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-R")
    Do $$$AssertEquals(after.State, "escalated", "it stays with a person")
    Do $$$AssertTrue(after.Headline [ "without the live agents", "the headline says why: " _ after.Headline)
    Set id = after.%Id(), n = 1, text = ""
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.Plan WHERE "Case" = :id)
    Do $$$AssertEquals(+n, 0, "no plan is made")
    &sql(SELECT TOP 1 Text INTO :text FROM Shutter_Store.CaseEvent WHERE "Case" = :id AND ToState = 'escalated' ORDER BY Seq DESC)
    Do $$$AssertTrue(text [ "no board member has a recording", "the audit trail says why: " _ text)
    Do $$$AssertEquals(##class(Shutter.API.Dispatch).ReasonFromEvent(text, "escalated"), "ESCALATED", "the reason it shows")
    Do ##class(Shutter.Store.Case).PurgeCase(id)
}

/// A leader an approver abandons: the fresh instance that abandons it never knew the lead, so it finds the lead by the
/// case id, finishes it as failed and tells the followers; a lead already ended, or a case that leads nothing, is left
/// as it is.
Method TestAbandonedLeaderFinishesTheLead()
{
    Set bl = "Shutter.Store.BoardLead"
    Kill ^Shutter.Config("leadWindowSeconds"), ^Shutter.Config("resetAt")
    Set sig = "sha256:test-lead-abandon-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set ..Sigs(sig) = ""
    Set leader = ..SavedCase("C-TEST-LEAD-C")
    Set other = ..SavedCase("C-TEST-LEAD-D")
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig, leader, "", .lead), "the leader's lead begins")
    Set wf = ..Instance()
    Set request = ##class(Shutter.Msg.CaseAbandon).%New()
    Set request.CaseId = "C-TEST-LEAD-C", request.Actor = "approver", request.Reason = "the instance died in the restart"
    Do $$$AssertStatusOK(wf.OnAbandon(request, .response), "the abandon")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-C").State, "failed", "the case is failed")
    Set after = $CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-C")
    Do $$$AssertEquals(after.State _ "|" _ after.Reason, "failed|the leader was abandoned", "the lead is finished as failed with the reason")
    Do $$$AssertNotEquals(after.EndedAt, "", "and ended")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "the signature attracts no follower now")
    Do wf.LeadLeftBehind(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-C"), "again")
    Do $$$AssertEquals($CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-C").Reason, "the leader was abandoned", "a lead already ended keeps its first reason")
    Do wf.LeadLeftBehind(other, "nothing led")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-D")), "a case that leads nothing finishes nothing")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-D").State, "investigating", "and is left as it was")
}

/// An instance whose send to the gate does nothing, for a path that plans: what is asserted is the plan it stored.
Method QuietInstance() As Shutter.Process.CaseWorkflow
{
    Set wf = ##class(Shutter.Test.QuietWorkflow).%New("Case Workflow")
    Do $$$AssertTrue($ISOBJECT(wf), "an instance of the Case Workflow item")
    Quit wf
}

/// A saved case in the given mode with a sealed snapshot of the summary, and a run per status on that snapshot, as the
/// members of a board nobody could answer leave them.
Method NoAnswerCase(caseId As %String, mode As %String, catalogue As %DynamicObject, statuses As %List = "") As Shutter.Store.Case
{
    Set c = ..SavedCase(caseId)
    Set c.Mode = mode
    Do $$$AssertStatusOK(c.%Save(), "the case's mode")
    Set snap = ##class(Shutter.Store.Snapshot).Begin(c)
    Set summary = {"ward_state": {"version": 3}, "operation": {"payload_digest": "sha256:ut"}}
    Set summary.catalogue = catalogue
    Do $$$AssertStatusOK(snap.Seal(summary), "the snapshot is sealed")
    Do $$$AssertStatusOK(c.SetSnapshot(snap), "the case's current one")
    For i = 1:1:$LISTLENGTH(statuses) {
        Set run = ##class(Shutter.Store.AgentRun).%New()
        Do run.CaseSetObjectId(c.%Id())
        Set run.Snapshot = snap, run.Status = $LIST(statuses, i)
        Do $$$AssertStatusOK(run.%Save(), "a member's run answered " _ run.Status)
    }
    Quit c
}

/// The catalogue's result for two sources at the same time, the entry whose outcome is to stop.
ClassMethod E7() As %DynamicObject
{
    Quit {"decision": "board", "entry": "E7", "outcome": "escalate", "matches": [{"id": "E7", "title": "Two sources at the same time", "decides": "board", "preferred": {"outcome": "escalate", "why": "Neither is later, so a resend would overwrite the other system's placement."}}]}
}

/// The catalogue's result for an entry the board decides whose preferred outcome is a resend.
ClassMethod E9() As %DynamicObject
{
    Quit {"decision": "board", "entry": "E9", "outcome": "resend", "matches": [{"id": "E9", "title": "The receiver's answer contradicts its records", "decides": "board", "preferred": {"outcome": "resend", "why": "The movement was never committed."}}]}
}

/// The catalogue's result for an entry that decides by policy.
ClassMethod E2() As %DynamicObject
{
    Quit {"decision": "policy", "entry": "E2", "outcome": "resend", "matches": [{"id": "E2", "title": "Not delivered, still current", "decides": "policy", "preferred": {"outcome": "resend", "why": "It is still due."}}]}
}

/// The catalogue's result for a death on the message.
ClassMethod E19() As %DynamicObject
{
    Quit {"decision": "person", "entry": "E19", "outcome": "escalate", "conditions": {"death_recorded": "yes"}, "matches": [{"id": "E19", "title": "A death on the message", "decides": "person", "preferred": {"outcome": "escalate", "why": "The message records a death."}}]}
}

/// The case stopped for a person: escalated, nothing planned, and the event and the reason name why.
Method AssertStopped(caseId As %String, what As %String, words As %String)
{
    Set after = ##class(Shutter.Store.Case).ByCaseId(caseId)
    Do $$$AssertEquals(after.State, "escalated", what _ ": it goes to a person")
    Set id = after.%Id(), n = 1, text = ""
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.Plan WHERE "Case" = :id)
    Do $$$AssertEquals(+n, 0, what _ ": no plan is made")
    Do $$$AssertEquals(after.Disposition, "escalate", what _ ": the case reads as escalated")
    &sql(SELECT TOP 1 Text INTO :text FROM Shutter_Store.CaseEvent WHERE "Case" = :id AND ToState = 'escalated' ORDER BY Seq DESC)
    Do $$$AssertTrue(text [ words, what _ ": the audit trail says " _ words _ ": " _ text)
    Do $$$AssertEquals(##class(Shutter.API.Dispatch).ReasonFromEvent(text, "escalated"), "NO_BOARD_ANSWER", what _ ": the reason it shows")
    Do $$$AssertTrue(##class(Shutter.API.Dispatch).StoppedAfterTheGate(text), what _ ": an earlier round's gate block is not the reason")
    Do $$$AssertTrue(after.Headline [ "no board member could answer", what _ ": the headline: " _ after.Headline)
    Do ##class(Shutter.Store.Case).PurgeCase(id)
}

/// A case the catalogue gives to the board, and every member refused or with no recording: in Site policy and in Board
/// mode, with each of the three statuses, it goes to a person with no plan, naming the entry and why nobody answered.
Method TestNoBoardAnswerGoesToAPerson()
{
    For mode = "board", "policy", "single" {
        For status = "budget_exhausted", "provider_auth", "no_record" {
            Set c = ..NoAnswerCase("C-TEST-LEAD-N", mode, ..E7(), $LISTBUILD(status, status, status))
            Set wf = ..Instance()
            Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = mode
            Do wf.AfterBoard(c)
            Do ..AssertStopped("C-TEST-LEAD-N", mode _ ", " _ status, "E7")
        }
    }
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", ..E7(), $LISTBUILD("budget_exhausted"))
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board"
    Do wf.AfterBoard(c)
    Do ..AssertStopped("C-TEST-LEAD-N", "the budget is named", "budget")
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", ..E7(), $LISTBUILD("provider_auth"))
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board"
    Do wf.AfterBoard(c)
    Do ..AssertStopped("C-TEST-LEAD-N", "the provider is named", "refuses the key")
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", ..E7(), $LISTBUILD("no_record"))
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board"
    Do wf.AfterBoard(c)
    Do ..AssertStopped("C-TEST-LEAD-N", "the missing recording is named", "recording")
}

/// Every case the catalogue gives to the board stops, not only an entry whose outcome is to stop: an entry preferring a
/// resend, several matches at once, and a person's entry the board was asked to take again.
Method TestEveryBoardDecisionStops()
{
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "policy", ..E9(), $LISTBUILD("budget_exhausted"))
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "policy"
    Do wf.AfterBoard(c)
    Do ..AssertStopped("C-TEST-LEAD-N", "one entry preferring a resend", "E9")
    Set several = {"decision": "board", "matches": [{"id": "E2", "title": "One", "preferred": {"outcome": "resend"}}, {"id": "E7", "title": "Two", "preferred": {"outcome": "escalate"}}]}
    Do several.%Set("entry", "", "null"), several.%Set("outcome", "", "null")
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", several, $LISTBUILD("no_record"))
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board"
    Do wf.AfterBoard(c)
    Do ..AssertStopped("C-TEST-LEAD-N", "several matches", "E2, E7")
    Set person = {"decision": "person", "entry": "E8", "outcome": "escalate", "matches": [{"id": "E8", "title": "A person decides", "decides": "person", "preferred": {"outcome": "escalate"}}]}
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", person, $LISTBUILD("provider_auth"))
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board"
    Do wf.AfterBoard(c)
    Do ..AssertStopped("C-TEST-LEAD-N", "an entry a person decides", "E8")
}

/// A leader that stops so finishes its lead as failed with the reason: the signature attracts no follower, and no plan
/// is there for one to take.
Method TestALeaderThatStopsFailsItsLead()
{
    Set bl = "Shutter.Store.BoardLead"
    Kill ^Shutter.Config("leadWindowSeconds"), ^Shutter.Config("resetAt")
    Set sig = "sha256:test-lead-noanswer-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set ..Sigs(sig) = ""
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", ..E7(), $LISTBUILD("budget_exhausted"))
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig, c, "", .lead), "the lead begins")
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board", wf.LeadSignature = sig
    Do wf.AfterBoard(c)
    Set after = $CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-N")
    Do $$$AssertEquals(after.State, "failed", "the lead is failed")
    Do $$$AssertEquals(after.PlanJSON, "", "with no plan for a follower")
    Do $$$AssertTrue(after.Reason [ "no board member could answer", "with the reason: " _ after.Reason)
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "and no case follows it")
    Do ##class(Shutter.Store.Case).PurgeCase(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-N").%Id())
}

/// A follower whose leader decided nothing (told of the failed lead, or the bound on its wait run out, or no lead at
/// all) goes to a person on a case the catalogue gives to the board, naming the case it followed.
Method TestFollowerOfAFailedLeadGoesToAPerson()
{
    Set bl = "Shutter.Store.BoardLead"
    Kill ^Shutter.Config("leadWindowSeconds"), ^Shutter.Config("resetAt")
    Set sig = "sha256:test-lead-follow-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set ..Sigs(sig) = ""
    Set leader = ..SavedCase("C-TEST-LEAD-A")
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig, leader, "", .lead), "the leader's lead begins")
    // The bound on the wait runs out while the board still runs.
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", ..E7())
    Set c.FollowsCase = "C-TEST-LEAD-A"
    Do $$$AssertStatusOK(c.%Save(), "it follows the leader")
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board"
    Do wf.OnLeadTimeout(c)
    Do ..AssertStopped("C-TEST-LEAD-N", "the wait ran out", "C-TEST-LEAD-A")
    // Told that the lead failed.
    Do $CLASSMETHOD(bl, "Finish", "C-TEST-LEAD-A", "failed", "", "", "no board member produced usable findings")
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "policy", ..E7())
    Set c.FollowsCase = "C-TEST-LEAD-A"
    Do $$$AssertStatusOK(c.%Save(), "it follows the leader")
    Set msg = ##class(Shutter.Msg.LeadReady).%New()
    Set msg.CaseId = "C-TEST-LEAD-N", msg.LeaderCaseId = "C-TEST-LEAD-A"
    Set wf = ..Instance()
    Do wf.OnLeadReady(msg, .response)
    Do ..AssertStopped("C-TEST-LEAD-N", "told of the failed lead", "no board member produced usable findings")
    // A lead nobody recorded.
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", ..E9())
    Set c.FollowsCase = "C-TEST-NOBODY"
    Do $$$AssertStatusOK(c.%Save(), "it follows a case that led nothing")
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board"
    Do wf.OnLeadTimeout(c)
    Do ..AssertStopped("C-TEST-LEAD-N", "no lead recorded", "no lead was recorded")
}

/// A board with no member to convene is no board either: a case the catalogue gives to the board stops in Board mode.
Method TestNoMemberToConveneGoesToAPerson()
{
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", ..E7())
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board"
    Do wf.ConveneBoard(c, c.CurrentSnapshot.Summary, "", "rules", .convened)
    Do $$$AssertEquals(+$GET(convened), 0, "nothing was convened")
    Do ..AssertStopped("C-TEST-LEAD-N", "no member", "E7")
}

/// Explicit Rules only is the demonstration and does not change: the same case in that mode gets the plain resend with
/// no entry named.
Method TestRulesOnlyStillProposesTheResend()
{
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "rules", ..E7())
    Set wf = ..QuietInstance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "rules"
    Do $$$AssertStatusOK(wf.ConveneBoard(c, c.CurrentSnapshot.Summary, "", "", .convened), "the rules path plans")
    Set after = ##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-N")
    Set id = after.%Id(), disposition = "", entry = "x", by = ""
    &sql(SELECT TOP 1 Disposition, CatalogueEntry, CreatedBy INTO :disposition, :entry, :by FROM Shutter_Store.Plan WHERE "Case" = :id ORDER BY ID DESC)
    Do $$$AssertEquals(disposition, "resend", "the plain resend")
    Do $$$AssertEquals(entry, "", "naming no entry")
    Do $$$AssertEquals(by, "rules", "from the rules")
    Do ##class(Shutter.Store.Case).PurgeCase(id)
}

/// A case the catalogue settles by policy keeps the rules path when no member can answer, in Board mode: the gate judges
/// the plain resend and a person approves it.
Method TestPolicyDecisionKeepsTheRulesPath()
{
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", ..E2(), $LISTBUILD("no_record", "no_record"))
    Set wf = ..QuietInstance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board"
    Do wf.AfterBoard(c)
    Set after = ##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-N")
    Set id = after.%Id(), disposition = "", by = ""
    &sql(SELECT TOP 1 Disposition, CreatedBy INTO :disposition, :by FROM Shutter_Store.Plan WHERE "Case" = :id ORDER BY ID DESC)
    Do $$$AssertEquals(disposition, "resend", "the plain resend")
    Do $$$AssertEquals(by, "rules", "from the rules")
    Do ##class(Shutter.Store.Case).PurgeCase(id)
}

/// A death on the message goes to a person in Site policy mode and in Board mode too, with no board asked: an escalate plan
/// naming the entry. Rules only is the baseline and stays as it is.
Method TestADeathOnTheMessageAsksAPersonInEveryModeButRules()
{
    For mode = "board", "policy", "rules" {
        Set c = ..NoAnswerCase("C-TEST-LEAD-N", mode, ..E19())
        Set wf = ..QuietInstance()
        Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = mode
        Set result = ##class(Shutter.Msg.EvidenceResult).%New()
        Set result.SnapshotId = c.CurrentSnapshot.%Id(), result.Digest = "sha256:ut", result.SummaryJSON = c.CurrentSnapshot.Summary
        Do $$$AssertStatusOK(wf.OnEvidence(c, result), mode _ ": the workflow plans")
        Set after = ##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-N")
        Set id = after.%Id(), disposition = "", entry = "x", by = ""
        &sql(SELECT TOP 1 Disposition, CatalogueEntry, CreatedBy INTO :disposition, :entry, :by FROM Shutter_Store.Plan WHERE "Case" = :id ORDER BY ID DESC)
        If mode = "rules" {
            Do $$$AssertEquals(disposition, "resend", "Rules only: the plain resend, as before")
            Do $$$AssertEquals(by, "rules", "Rules only: from the rules")
        } Else {
            Do $$$AssertEquals(disposition, "escalate", mode _ ": to a person")
            Do $$$AssertEquals(entry, "E19", mode _ ": naming the entry")
            Do $$$AssertEquals(by, "policy:E19", mode _ ": from the catalogue, with no board")
        }
        Do ##class(Shutter.Store.Case).PurgeCase(id)
    }
}

/// The plan's words a follower gets, its createdBy after them.
Method FollowerPlanOf(lead As Shutter.Store.BoardLead, catalogue As %DynamicObject) As %String
{
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", catalogue)
    Set wf = ..QuietInstance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board"
    Do $$$AssertStatusOK(wf.TakeDiagnosis(c, lead), "the follower plans")
    Set id = ##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-N").%Id(), why = "", by = "", summary = ""
    &sql(SELECT TOP 1 Why, Summary, CreatedBy INTO :why, :summary, :by FROM Shutter_Store.Plan WHERE "Case" = :id ORDER BY ID DESC)
    Do ##class(Shutter.Store.Case).PurgeCase(id)
    Quit why _ " | " _ summary _ " | " _ by
}

/// A lead whose plan came from the rules because nobody on the board could answer: a follower is never told that a board
/// decided. It takes the rules path itself on its own evidence when its own match allows that, and stops when it does
/// not. A lead a board really decided still says so.
Method TestFollowerOfARulesLeadHearsNoBoard()
{
    Set bl = "Shutter.Store.BoardLead"
    Kill ^Shutter.Config("leadWindowSeconds"), ^Shutter.Config("resetAt")
    Set sig = "sha256:test-lead-rules-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set ..Sigs(sig) = ""
    Set leader = ..NoAnswerCase("C-TEST-LEAD-A", "board", ..E2(), $LISTBUILD("no_record"))
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig, leader, "", .lead), "the lead begins")
    Set wf = ..QuietInstance()
    Set wf.CaseId = "C-TEST-LEAD-A", wf.Mode = "board", wf.LeadSignature = sig
    Do wf.AfterBoard(leader)
    Set lead = $CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-A")
    Do $$$AssertEquals(lead.State, "done", "the leader's rules plan finishes the lead")
    Set words = ..FollowerPlanOf(lead, ..E2())
    Do $$$AssertNotTrue(words [ "board", "no word of a board in the follower's plan: " _ words)
    Do $$$AssertTrue($PIECE(words, " | ", 3) = "rules", "the plan says it came from the rules: " _ words)
    // Its own match goes to the board: it stops rather than taking a resend nobody decided.
    Set c = ..NoAnswerCase("C-TEST-LEAD-N", "board", ..E7())
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-N", wf.Mode = "board"
    Do wf.TakeDiagnosis(c, $CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-A"))
    Do ..AssertStopped("C-TEST-LEAD-N", "a rules lead and a board entry", "C-TEST-LEAD-A")
    // A board's plan: the follower is told so.
    Set sig2 = sig _ "-b"
    Set ..Sigs(sig2) = ""
    Set leader2 = ..NoAnswerCase("C-TEST-LEAD-B", "board", ..E2())
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig2, leader2, "", .lead2), "the board's lead begins")
    Set wf = ..QuietInstance()
    Set wf.CaseId = "C-TEST-LEAD-B", wf.Mode = "board", wf.LeadSignature = sig2
    Set plan = {"disposition": "resend", "action": {"type": "resend", "operation_key": "k", "expected_version": 3}, "summary": "s", "why": "w"}
    Do $$$AssertStatusOK(wf.AdoptPlan(leader2, plan, "run:1"), "the board's plan is adopted")
    Set words = ..FollowerPlanOf($CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-B"), ..E2())
    Do $$$AssertTrue(words [ "The board convened for case C-TEST-LEAD-B decided resend", "the follower is told of the board: " _ words)
    Do ##class(Shutter.Store.Case).PurgeCase(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-A").%Id())
    Do ##class(Shutter.Store.Case).PurgeCase(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-B").%Id())
}

}
