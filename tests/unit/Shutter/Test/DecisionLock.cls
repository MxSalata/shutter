/// Two decisions on one approval task (CONTRACTS 5): both can find the task open, so each takes the task's decision lock
/// and reads the task again before it decides. A decision that meets one under way waits for it and is then told who
/// decided, what and when; one that waits past the lock's wait is refused as busy; and a cancellation (the approval wait
/// running out, a case closed by hand or abandoned) leaves a task decided meanwhile as it was decided. The first
/// decision is played here by the test itself, holding the lock as Decide does while it completes the task, and the
/// second runs in a job of its own, as a second request would. The tests make a Workflow role of their own, with the
/// session's user in it, and remove the role, the membership, any Workflow user they made and the tasks they save.
Class Shutter.Test.DecisionLock Extends %UnitTest.TestCase
{

Parameter ROLE = "UT Shutter Decision Lock";

/// A decision that meets another under way waits for it, then finds the task decided: decided, naming the action, who
/// took it and when, and the task keeps the first decision.
Method TestTheSecondDecisionIsToldWhoDecided()
{
    If '..Ready(.made) Quit
    Set task = ##class(Shutter.Test.Workflow).SavedTask(..#ROLE, "UT-WF-L1")
    If '$$$AssertTrue($ISOBJECT(task), "an open task") Do ..Tidy(made) Quit
    Set id = task.%Id()
    Kill ^Shutter.Test("lock")
    // The first decision holds the lock while it completes the task, as Decide does.
    Lock +^Shutter.TaskDecision(id)
    Job ##class(Shutter.Test.DecisionLock).DecideInJob("UT-WF-L1", "Reject")
    Do ..JobStarted(10)
    Set task.%Action = "Approve", task.%UserName = $USERNAME
    Set task.%TaskStatus.IsComplete = 1, task.%TaskStatus.TimeCompleted = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Do $$$AssertStatusOK(task.%Save(), "the first decision completes the task")
    Lock -^Shutter.TaskDecision(id)
    Set out = ..JobAnswer(20)
    Do $$$AssertEquals(out.code, "decided", "the second decision is refused as decided: " _ out.error)
    Do $$$AssertEquals(out.action, "Approve", "naming the first decision's action")
    Do $$$AssertEquals(out.user, $USERNAME, "and who took it")
    Do $$$AssertTrue(out.completedAt '= "", "and when: " _ out.completedAt)
    Do $$$AssertStatusOK(task.%Reload(), "the task is read again")
    Do $$$AssertEquals(task.%Action, "Approve", "and keeps the first decision")
    Do $$$AssertEquals(task.%TaskStatus.IsComplete, 1, "complete")
    Do ##class(Shutter.Test.Workflow).DeleteTask(task)
    Do ..Tidy(made)
}

/// A decision that waits past the lock's wait is refused as busy, and the task is left open and unassigned.
Method TestADecisionHeldUpIsBusy()
{
    If '..Ready(.made) Quit
    Set task = ##class(Shutter.Test.Workflow).SavedTask(..#ROLE, "UT-WF-L2")
    If '$$$AssertTrue($ISOBJECT(task), "an open task") Do ..Tidy(made) Quit
    Set id = task.%Id()
    Kill ^Shutter.Test("lock")
    Lock +^Shutter.TaskDecision(id)
    Job ##class(Shutter.Test.DecisionLock).DecideInJob("UT-WF-L2", "Reject")
    Set out = ..JobAnswer(20)
    Lock -^Shutter.TaskDecision(id)
    Do $$$AssertEquals(out.code, "busy", "a decision held up past the wait is busy: " _ out.error)
    Do $$$AssertStatusOK(task.%Reload(), "the task is read again")
    Do $$$AssertEquals(+task.%TaskStatus.IsComplete, 0, "and is still open")
    Do $$$AssertEquals(task.%TaskStatus.AssignedTo, "", "and unassigned")
    Do ##class(Shutter.Test.Workflow).DeleteTask(task)
    Do ..Tidy(made)
}

/// A cancellation that meets a decision under way leaves the task as that decision left it: not cancelled, its action
/// and comment unchanged, and the caller told it was decided.
Method TestACancellationLeavesADecidedTask()
{
    If '..Ready(.made) Quit
    Set task = ##class(Shutter.Test.Workflow).SavedTask(..#ROLE, "UT-WF-L3")
    If '$$$AssertTrue($ISOBJECT(task), "an open task") Do ..Tidy(made) Quit
    Set id = task.%Id()
    Kill ^Shutter.Test("lock")
    Lock +^Shutter.TaskDecision(id)
    Job ##class(Shutter.Test.DecisionLock).CancelInJob("UT-WF-L3")
    Do ..JobStarted(10)
    Set task.%Action = "Approve", task.%UserName = $USERNAME
    Do task.%FormValues.SetAt("the first decision", "Comment")
    Set task.%TaskStatus.IsComplete = 1, task.%TaskStatus.TimeCompleted = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Do $$$AssertStatusOK(task.%Save(), "a decision completes the task")
    Lock -^Shutter.TaskDecision(id)
    Set out = ..JobAnswer(20)
    Do $$$AssertEquals(out.decided, 1, "the cancellation says the task was decided: " _ out.%ToJSON())
    Do $$$AssertStatusOK(task.%Reload(), "the task is read again")
    Do $$$AssertEquals(task.%Action, "Approve", "and keeps its decision, not Cancel")
    Do $$$AssertEquals(task.%FormValues.GetAt("Comment"), "the first decision", "and its comment")
    Do ##class(Shutter.Test.Workflow).DeleteTask(task)
    &sql(DELETE FROM Shutter_Store.CaseEvent WHERE "Case"->CaseId = 'UT-WF-L3')
    &sql(DELETE FROM Shutter_Store."Case" WHERE CaseId = 'UT-WF-L3')
    Do ..Tidy(made)
}

/// The tests need Shutter_Approve, which the decision checks first: without it they are skipped. Then the role of the
/// tests' own, with the session's user a Workflow user in it; made is 1 when that Workflow user was made here.
Method Ready(Output made As %Boolean) As %Boolean
{
    Set made = 0
    If '$SYSTEM.Security.Check("Shutter_Approve", "USE") {
        Do $$$AssertSkipped("the session's user does not hold Shutter_Approve")
        Quit 0
    }
    Set role = ..#ROLE, user = $USERNAME
    Do ..Tidy(0)
    If '$$$AssertStatusOK(##class(EnsLib.Workflow.RoleDefinition).CreateRole(role), "a role of the test's own is made") Quit 0
    If '##class(EnsLib.Workflow.UserDefinition).%ExistsId(user) {
        If '$$$AssertStatusOK(##class(EnsLib.Workflow.UserDefinition).CreateUser(user, "Shutter unit test decider"), "the session's user is made a Workflow user") Do ..Tidy(0) Quit 0
        Set made = 1
    }
    If '$$$AssertStatusOK(##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(role, user, 1, "Approver"), "in the role") Do ..Tidy(made) Quit 0
    Quit 1
}

/// Removes the role and its membership, and the Workflow user when the test made it.
Method Tidy(made As %Boolean)
{
    Set role = ..#ROLE, user = $USERNAME
    If ##class(EnsLib.Workflow.RoleMembership).%ExistsId(role _ "||" _ user) Do ##class(EnsLib.Workflow.RoleDefinition).RemoveUserFromRole(role, user)
    If ##class(EnsLib.Workflow.RoleDefinition).%ExistsId(role) Do ##class(EnsLib.Workflow.RoleDefinition).%DeleteId(role)
    If made && ##class(EnsLib.Workflow.UserDefinition).%ExistsId(user) Do ##class(EnsLib.Workflow.UserDefinition).DeleteUser(user)
    Kill ^Shutter.Test("lock")
}

/// Waits for the job to start, then a moment more, so it has found the task open before the first decision completes it.
Method JobStarted(seconds As %Numeric)
{
    Set until = $ZHOROLOG + seconds
    While '$DATA(^Shutter.Test("lock", "started")) && ($ZHOROLOG < until) { Hang 0.05 }
    Hang 0.5
}

/// The job's answer as an object, waiting for it up to the seconds given.
Method JobAnswer(seconds As %Numeric) As %DynamicObject
{
    Set until = $ZHOROLOG + seconds
    While '($DATA(^Shutter.Test("lock")) # 2) && ($ZHOROLOG < until) { Hang 0.1 }
    Set out = ##class(Shutter.Util.Json).Parse($GET(^Shutter.Test("lock")), .sc)
    Quit $SELECT($ISOBJECT(out): out, 1: {"code": "none", "error": ("no answer from the job: " _ $GET(^Shutter.Test("lock")))})
}

/// A second decision, as a second request makes it, its answer kept for the test.
ClassMethod DecideInJob(caseId As %String, action As %String)
{
    Set ^Shutter.Test("lock", "started") = 1
    Try {
        Set ^Shutter.Test("lock") = ##class(Shutter.Util.Workflow).Decide(caseId, action, "", "the second decision")
    } Catch ex {
        Set ^Shutter.Test("lock") = {"code": "error", "error": (ex.DisplayString())}.%ToJSON()
    }
}

/// A cancellation of the case's open task, as the case workflow makes one when its approval wait runs out.
ClassMethod CancelInJob(caseId As %String)
{
    Set ^Shutter.Test("lock", "started") = 1
    Try {
        Set case = ##class(Shutter.Store.Case).%New()
        Set case.CaseId = caseId
        Set wf = ##class(Shutter.Process.CaseWorkflow).%New()
        Set decided = 0
        Set sc = wf.CancelOpenTask(case, "system", "a unit test's wait", .decided)
        Set ^Shutter.Test("lock") = {"decided": (+decided), "ok": ($SYSTEM.Status.IsOK(sc))}.%ToJSON()
    } Catch ex {
        Set ^Shutter.Test("lock") = {"code": "error", "error": (ex.DisplayString())}.%ToJSON()
    }
}

}
