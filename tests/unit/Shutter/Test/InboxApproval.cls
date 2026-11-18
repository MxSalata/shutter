/// The approval of a case in the Workflow inbox (CONTRACTS 6.4): the task is bound on the server when the rehearsal
/// passes, its form shows the plan it releases, and an approval there names no digest. Approve releases exactly what the
/// task is bound to; once anything bound has moved, the case blocks with nothing approved and nothing sent, read from
/// the request the workflow sent, so a task whose own copy of the binding was changed does not pass. An answer that
/// names a digest (the web application's) is decided by it, as before. Each test drives an instance outside the
/// production (Shutter.Test.InboxWorkflow) over a case it saves and purges.
Class Shutter.Test.InboxApproval Extends %UnitTest.TestCase
{

Parameter THECASE = "C-TEST-INBOX";

Parameter KEY = "PAS^HOSP^MRN-IB1^ENC-IB1^transfer^2026-11-18T09:00:00Z";

Parameter APPROVER = "approver";

Method OnAfterOneTest(testname As %String) As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId %STARTSWITH ?", ..#THECASE)
    While rs.%Next() { Do ##class(Shutter.Store.Case).PurgeCase(rs.%Get("ID")) }
    Quit $$$OK
}

/// A case that awaits approval of a resend at receiver version 1, as the workflow leaves it once the rehearsal passed:
/// the instance, the case, the plan, the rehearsal and the task the workflow sent.
Method Awaiting(Output wf As Shutter.Test.InboxWorkflow, Output case As Shutter.Store.Case, Output plan As Shutter.Store.Plan, Output task As EnsLib.Workflow.TaskRequest)
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = ..#THECASE _ "-" _ $INCREMENT(^||Shutter.Test.InboxApproval), case.OperationKey = ..#KEY _ "-" _ case.CaseId
    Set case.Event = "transfer", case.EncounterId = "ENC-IB1", case.PatientId = "MRN-IB1", case.PatientIdAuthority = "HOSP", case.SourceSystem = "PAS"
    Set case.FailureKind = "delivery_failed", case.Ward = "WARD-B", case.EventTime = "2026-11-18T09:00:00Z", case.State = "rehearsing", case.Mode = "board"
    Set case.Receiver = $PARAMETER("Shutter.Production", "RECEIVER"), case.Headline = "Resend the transfer at version 1"
    Do $$$AssertStatusOK(case.%Save(), "the case")
    Set plan = ##class(Shutter.Store.Plan).%New()
    Do plan.CaseSetObjectId(case.%Id())
    Set plan.Version = 1, plan.Disposition = "resend", plan.ActionType = "resend", plan.OperationKey = case.OperationKey, plan.ExpectedVersion = 1
    Set plan.Digest = ##class(Shutter.Util.Digest).SHA256Hex("inbox approval " _ case.CaseId)
    Do $$$AssertStatusOK(plan.%Save(), "the plan")
    Set wf = ##class(Shutter.Test.InboxWorkflow).%New("Case Workflow")
    Set wf.CaseId = case.CaseId, wf.PlanId = plan.%Id(), wf.Mode = "board"
    Set sent = ##class(Shutter.Msg.WardOperation).%New()
    Set sent.OperationKey = case.OperationKey, sent.ExpectedVersion = 1, sent.DryRun = 1
    Set result = ##class(Shutter.Msg.WardResult).%New()
    Set result.Outcome = "would_apply", result.HttpStatus = 200, result.ResponseJSON = "{""would_apply"":true,""encounter_before"":{""version"":1}}", result.EncounterVersion = 1
    Do $$$AssertStatusOK(wf.OnRehearsal(case, sent, result), "the rehearsal is taken")
    Do $$$AssertEquals(case.State, "awaiting_approval", "the case awaits an approver")
    Set task = wf.Sent("approval")
    Do $$$AssertTrue($ISOBJECT(task) && task.%IsA("EnsLib.Workflow.TaskRequest"), "and the task was sent")
}

/// The task as the Workflow engine makes it from the request, answered in the inbox: the request's form values copied, the
/// action and the approver, and Comment, the one field the inbox's form sends.
ClassMethod InboxAnswer(task As EnsLib.Workflow.TaskRequest, action As %String = "Approve", comment As %String = "") As EnsLib.Workflow.TaskResponse
{
    Set answer = ##class(EnsLib.Workflow.TaskResponse).%New()
    Set key = ""
    For { Set value = task.%FormValues.GetNext(.key) Quit:key=""  Do answer.%FormValues.SetAt(value, key) }
    Set answer.%Action = action, answer.%UserName = ..#APPROVER
    Do answer.%FormValues.SetAt(comment, "Comment")
    Quit answer
}

Method Answer(wf As Shutter.Test.InboxWorkflow, sent As %Library.Persistent, answer As EnsLib.Workflow.TaskResponse)
{
    Set response = ""
    Do $$$AssertStatusOK(wf.OnResponse("", .response, sent, answer, "approval"), "the answer is taken")
}

/// The case's last state event's text, and how many approvals it has with this decision.
ClassMethod LastText(case As Shutter.Store.Case) As %String
{
    Set id = case.%Id(), text = ""
    &sql(SELECT TOP 1 Text INTO :text FROM Shutter_Store.CaseEvent WHERE "Case" = :id AND ToState IS NOT NULL ORDER BY Seq DESC)
    Quit text
}

ClassMethod Approvals(case As Shutter.Store.Case, decision As %String = "approved") As %Integer
{
    Set id = case.%Id(), n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.Approval WHERE "Case" = :id AND Decision = :decision)
    Quit +n
}

/// The task the rehearsal raises is bound to the case, the plan, the evidence, the rehearsal and the receiver, takes only a
/// comment, and its form shows the plan it releases, read-only.
Method TestTheTaskIsBoundAndShowsThePlan()
{
    Do ..Awaiting(.wf, .case, .plan, .task)
    Set r = ##class(Shutter.Store.Rehearsal).%OpenId(task.%FormValues.GetAt("Shutter.Rehearsal"))
    Do $$$AssertTrue($ISOBJECT(r) && (r.PlanGetObjectId() = plan.%Id()), "the task binds this plan's rehearsal")
    Do $$$AssertEquals(task.%FormFields _ "|" _ task.%FormTemplate _ "|" _ task.%FormValues.GetAt("PlanDigest"), "Comment|Shutter.Process.ApprovalForm.cls|", "Comment its one field, drawn by Shutter's own form, no digest to fill")
    Set v = task.%FormValues
    Do $$$AssertEquals(v.GetAt("Shutter.Case") _ "|" _ v.GetAt("Shutter.CaseVersion") _ "|" _ v.GetAt("Shutter.Plan") _ "|" _ v.GetAt("Shutter.PlanDigest") _ "|" _ v.GetAt("Shutter.ReceiverVersion"), case.CaseId _ "|" _ case.Version _ "|" _ plan.%Id() _ "|" _ plan.Digest _ "|1", "bound to the case's version now, the plan and the receiver version the rehearsal validated")
    Set html = ##class(Shutter.Process.ApprovalForm).FormHTML(..InboxAnswer(task))
    Do $$$AssertTrue(html [ ("<th scope=""row"">Exact action</th><td>resend " _ ##class(Shutter.Process.ApprovalForm).Esc(plan.OperationKey) _ " at receiver version 1</td>"), "the form shows the exact action: " _ $EXTRACT(html, 1, 600))
    Do $$$AssertTrue(html [ ("readonly aria-label=""Plan digest"" style=""" _ ##class(Shutter.Process.ApprovalForm).#BOXSTYLE _ """ value=""" _ plan.Digest _ """"), "and the plan's digest, read-only")
    Do $$$AssertTrue(html [ ("Rehearsal " _ r.%Id() _ ": would apply (rolled back)"), "and the rehearsal")
    Do $$$AssertEquals($LENGTH(html, "name=""") - 1, 1, "one named field")
    Do $$$AssertTrue(html [ "name=""Comment""", "and it is Comment")
    Do $$$AssertTrue(html [ ("/shutter/index.html#/cases/" _ case.CaseId), "with a link to the case")
    Do $$$AssertNotTrue(task.%Message [ "PlanDigest field", "the task asks for no paste")
    Do $$$AssertTrue(task.%Message [ "needs nothing pasted", "and says it needs none")
}

/// Approve with nothing pasted releases exactly the bound plan: one approval, of this plan and its rehearsal, and the read
/// before the write asked for.
Method TestApproveWithNothingPastedReleasesTheBoundPlan()
{
    Do ..Awaiting(.wf, .case, .plan, .task)
    Do ..Answer(wf, task, ..InboxAnswer(task, "Approve", "looked at it"))
    Set case = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(case.State, "approved", "the case is approved: " _ ..LastText(case))
    Set a = ##class(Shutter.Store.Approval).%OpenId(wf.ApprovalId)
    Do $$$AssertTrue($ISOBJECT(a), "an approval is recorded")
    Quit:'$ISOBJECT(a)
    Do $$$AssertEquals(a.PlanDigest _ "|" _ a.Approver _ "|" _ a.RehearsalGetObjectId(), plan.Digest _ "|" _ ..#APPROVER _ "|" _ task.%FormValues.GetAt("Shutter.Rehearsal"), "of the bound plan and rehearsal, by the approver")
    Do $$$AssertTrue(..LastText(case) [ "in the Workflow inbox, as its task was bound", "the trail says how: " _ ..LastText(case))
    Do $$$AssertTrue($ISOBJECT(wf.Sent("preflight")), "and the read before the write is asked for")
}

/// The case moved after its task was made, and the task's own copy of the binding was set to the case's new version: the
/// approval blocks the case, nothing is approved and nothing sent. Only the request the workflow sent still holds the
/// version the task was made for, so this passes only when the workflow checks that request, not the answer.
Method TestAMovedCaseBlocksWhateverTheAnswerSays()
{
    Do ..Awaiting(.wf, .case, .plan, .task)
    Set was = case.Version
    Do $$$AssertStatusOK(case.Transition(case.State, "Another job moves the case under its open task", "test"), "the case moves")
    Set answer = ..InboxAnswer(task)
    Do answer.%FormValues.SetAt(case.Version, "Shutter.CaseVersion")
    Do ..Answer(wf, task, answer)
    Set case = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(case.State, "blocked", "the case blocks")
    Do $$$AssertTrue(..LastText(case) [ ("the case moved: version " _ was _ " when the task was made, " _ (was + 1) _ " now"), "and says what moved: " _ ..LastText(case))
    Do $$$AssertEquals(..Approvals(case), 0, "nothing is approved")
    Do $$$AssertNotTrue($ISOBJECT(wf.Sent("preflight")), "nothing is sent")
}

/// A newer rehearsal of the plan than the one the task binds: the approval blocks, naming both.
Method TestANewerRehearsalBlocks()
{
    Do ..Awaiting(.wf, .case, .plan, .task)
    Set sent = ##class(Shutter.Msg.WardOperation).%New()
    Set sent.OperationKey = case.OperationKey, sent.ExpectedVersion = 1, sent.DryRun = 1
    Do $$$AssertStatusOK(##class(Shutter.Store.Rehearsal).Create(case, plan, sent, 200, {"would_apply": true, "encounter_before": {"version": 1}}, .newer), "another rehearsal of the plan")
    Do ..Answer(wf, task, ..InboxAnswer(task))
    Set case = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(case.State, "blocked", "the case blocks")
    Do $$$AssertTrue(..LastText(case) [ ("the rehearsal moved: " _ task.%FormValues.GetAt("Shutter.Rehearsal") _ " when the task was made, " _ newer.%Id() _ " now"), "naming both: " _ ..LastText(case))
    Do $$$AssertEquals(..Approvals(case), 0, "nothing is approved")
}

/// What GET /cases/{id} shows as a task's planDigest (Shutter.Util.Workflow.DecidedDigest): for an inbox approval that
/// stood, the digest its task was bound to; for one that was void because the case moved under its task, none, since it
/// bound nothing. The answers are saved tasks, as the engine's are, so the approval records name them.
Method TestTheDigestShownIsOnlyAnApprovalThatStood()
{
    Set role = ..#ROLE
    If ##class(EnsLib.Workflow.RoleDefinition).%ExistsId(role) Do ##class(EnsLib.Workflow.RoleDefinition).%DeleteId(role)
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.RoleDefinition).CreateRole(role), "a role of the test's own is made")
    Do ..Awaiting(.wf, .case, .plan, .task)
    Set answer = ..SavedAnswer(task, .sc)
    If $$$AssertStatusOK(sc, "the approval is a saved task") {
        Do ..Answer(wf, task, answer)
        Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(case.CaseId).State, "approved", "the approval stood: " _ ..LastText(case))
        Set id = answer.%Id(), n = 0
        &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.Approval WHERE WorkflowTaskId = :id AND Decision = 'approved')
        Do $$$AssertEquals(+n, 1, "it is recorded under the task " _ id)
        Do $$$AssertEquals(##class(Shutter.Util.Workflow).DecidedDigest(answer), plan.Digest, "so the task shows the digest it was bound to")
        Do ##class(Shutter.Test.Workflow).DeleteTask(answer)
    }
    Do ..Awaiting(.wf, .case, .plan, .task)
    Do $$$AssertStatusOK(case.Transition(case.State, "Another job moves the case under its open task", "test"), "the case moves")
    Set answer = ..SavedAnswer(task, .sc)
    If $$$AssertStatusOK(sc, "the second approval is a saved task") {
        Do ..Answer(wf, task, answer)
        Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(case.CaseId).State, "blocked", "the approval was void: " _ ..LastText(case))
        Do $$$AssertEquals(##class(Shutter.Util.Workflow).DecidedDigest(answer), "", "so the task shows no digest: it bound nothing")
        Do ##class(Shutter.Test.Workflow).DeleteTask(answer)
    }
    Do ##class(EnsLib.Workflow.RoleDefinition).%DeleteId(role)
}

Parameter ROLE = "UT Shutter Inbox Approvers";

/// An inbox answer saved and completed, as the engine leaves a task approved in the inbox, with the request it answers
/// (Shutter.Test.Workflow.DeleteTask removes both); <var>sc</var> says whether it could be saved.
ClassMethod SavedAnswer(task As EnsLib.Workflow.TaskRequest, Output sc As %Status) As EnsLib.Workflow.TaskResponse
{
    Set answer = ..InboxAnswer(task)
    Set answer.%Subject = task.%Subject, answer.%Actions = task.%Actions, answer.%RoleName = ..#ROLE
    Set answer.%TaskStatus.Role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(..#ROLE)
    Set answer.%TaskStatus.Request = task
    Set answer.%TaskStatus.AssignedTo = ..#APPROVER
    Set answer.%TaskStatus.IsComplete = 1, answer.%TaskStatus.TimeCompleted = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Set sc = answer.%Save()
    Quit answer
}

/// An inbox approval with no bound request (a task made before tasks were bound) names no digest and binds nothing, as
/// before; and an answer that names the plan's digest, as the web application's does, is decided by it, as before.
Method TestUnboundAndNamedAnswersAreDecidedAsBefore()
{
    Do ..Awaiting(.wf, .case, .plan, .task)
    Do ..Answer(wf, "", ..InboxAnswer(task))
    Set case = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(case.State, "blocked", "no bound request and no digest: the case blocks")
    Do $$$AssertTrue(..LastText(case) [ "carried no plan digest", "binding nothing: " _ ..LastText(case))
    Do ..Awaiting(.wf, .case, .plan, .task)
    Set answer = ..InboxAnswer(task)
    Do answer.%FormValues.SetAt(plan.Digest, "PlanDigest")
    Do ..Answer(wf, "", answer)
    Set case = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(case.State, "approved", "a named digest that is the plan's approves: " _ ..LastText(case))
    Do $$$AssertNotTrue(..LastText(case) [ "Workflow inbox", "and is not told as an inbox approval")
}

}
