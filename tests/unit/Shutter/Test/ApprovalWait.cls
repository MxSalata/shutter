/// The approval wait (CONTRACTS 6.4, v1.35): the task's text announces the bound, and the Case Workflow's setting defaults to a
/// day. The alarm and the escalation run inside the production (an end-to-end check on core, 2 Nov 2026).
Class Shutter.Test.ApprovalWait Extends %UnitTest.TestCase
{

Method TestTaskAnnouncesTheWait()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-WAIT", case.Headline = "A plan to approve"
    Set plan = ##class(Shutter.Store.Plan).%New()
    Set plan.Version = 1, plan.Disposition = "resend", plan.ActionType = "resend", plan.OperationKey = "PAS^HOSP^X^Y^transfer^2026-11-02T00:00:00Z", plan.ExpectedVersion = 3, plan.Digest = "sha256:0123456789abcdef0123456789abcdef"
    Set task = ##class(Shutter.Process.CaseWorkflow).ApprovalTask(case, plan, 86400)
    Do $$$AssertTrue(task.%Message [ "Unanswered after 24.0 hours, the task is cancelled and the case escalates", "the task says what happens when nobody answers: " _ $EXTRACT(task.%Message, 1, 300))
    Do $$$AssertEquals(##class(Shutter.Process.CaseWorkflow).WaitWords(60) _ "|" _ ##class(Shutter.Process.CaseWorkflow).WaitWords(5400), "1 minutes|1.5 hours", "minutes under an hour, hours above")
    Set task = ##class(Shutter.Process.CaseWorkflow).ApprovalTask(case, plan, 0)
    Do $$$AssertNotTrue(task.%Message [ "Unanswered after", "no bound, no sentence")
    Set def = ##class(%Dictionary.CompiledProperty).%OpenId("Shutter.Process.CaseWorkflow||ApprovalWaitSeconds")
    Do $$$AssertTrue($ISOBJECT(def) && (def.InitialExpression = 86400), "a day by default")
}

}
