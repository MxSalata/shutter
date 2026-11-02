/// Who decides a Workflow task and what the task carries (CONTRACTS 5, 6.4, 7.3): Shutter.Util.Workflow takes the decider
/// from the process's own user, never from an argument, refuses an approval that names no digest and a decider outside
/// the task's Workflow role, and the approval tasks of a case and of an incident start with an empty PlanDigest form
/// value, the digest in the text the approver reads; and an assignment keeps in step with the engine's distribution of
/// the task. Nothing here needs a production or leaves a row: the membership and assignment tests make a Workflow role
/// and user of their own and remove them again, the assignment test removes the tasks it saves, and the task tests
/// build unsaved objects.
Class Shutter.Test.Workflow Extends %UnitTest.TestCase
{

Parameter ROLE = "UT Shutter Approvers";

Parameter USER = "ut-shutter-approver";

/// The decider is the session's user: what $USERNAME says, and nothing an argument could change.
Method TestActorIsTheSessionUser()
{
    Set actor = ##class(Shutter.Util.Workflow).Actor()
    Do $$$AssertEquals(actor, $USERNAME, "the actor is the process's user")
    Do $$$AssertNotEquals(actor, "", "and the tests run as a signed-in user")
}

/// Membership of a Workflow role is the engine's own record, <role>||<user>: a Workflow user outside the role, a name
/// that is no Workflow user, no role or no user are not members.
Method TestMembershipIsTheWorkflowRole()
{
    Set role = ..#ROLE, user = ..#USER
    Do ..RemoveRole()
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.RoleDefinition).CreateRole(role), "a role of the test's own is made")
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.UserDefinition).CreateUser(user, "Shutter unit test approver"), "and a user")
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).IsMember(role, user), 0, "a Workflow user outside the role is not a member")
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(role, user, 1, "Approver"), "the user joins the role")
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).IsMember(role, user), 1, "and is a member")
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).IsMember(role, "nobody"), 0, "a name that is no Workflow user is not")
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).IsMember("", user), 0, "no role, no membership")
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).IsMember(role, ""), 0, "no user, no membership")
    Do ..RemoveRole()
    Set left = ##class(EnsLib.Workflow.RoleMembership).%ExistsId(role _ "||" _ user) || ##class(EnsLib.Workflow.RoleDefinition).%ExistsId(role) || ##class(EnsLib.Workflow.UserDefinition).%ExistsId(user)
    Do $$$AssertEquals(left, 0, "the role, the user and the membership are gone")
}

/// Removes the test's role, user and membership, whichever exist (a run that stopped half-way may have left them).
ClassMethod RemoveRole()
{
    Set role = ..#ROLE, user = ..#USER
    If ##class(EnsLib.Workflow.RoleMembership).%ExistsId(role _ "||" _ user) Do ##class(EnsLib.Workflow.RoleDefinition).RemoveUserFromRole(role, user)
    If ##class(EnsLib.Workflow.RoleDefinition).%ExistsId(role) Do ##class(EnsLib.Workflow.RoleDefinition).%DeleteId(role)
    If ##class(EnsLib.Workflow.UserDefinition).%ExistsId(user) Do ##class(EnsLib.Workflow.UserDefinition).DeleteUser(user)
}

/// An approval names the digest it binds, and is refused before any task is looked for when it names none; a
/// rejection needs none. A process without Shutter_Approve is refused first, whatever it passes.
Method TestApproveNeedsADigest()
{
    Set may = $SYSTEM.Security.Check("Shutter_Approve", "USE")
    Set out = ..Decide("UT-WF-NONE", "Approve", "", "")
    Do $$$AssertEquals(out.code, $SELECT(may: "no_digest", 1: "forbidden"), "an approval with no digest is refused: " _ out.error)
    Set out = ..Decide("UT-WF-NONE", "Approve", $CHAR(0), "")
    Do $$$AssertEquals(out.code, $SELECT(may: "no_digest", 1: "forbidden"), "SQL's empty string is no digest either: " _ out.error)
    Set out = ..Decide("UT-WF-NONE", "Reject", "", "")
    Do $$$AssertEquals(out.code, $SELECT(may: "no_task", 1: "forbidden"), "a rejection needs no digest and goes on to the task: " _ out.error)
}

/// With no open task nothing is assigned or completed, and the Workflow tables are left as they were.
Method TestDecideWithoutATaskChangesNothing()
{
    Set may = $SYSTEM.Security.Check("Shutter_Approve", "USE")
    Do $$$AssertEquals(..TaskCount("UT-WF-NONE"), 0, "the test's case has no tasks")
    Set out = ..Decide("UT-WF-NONE", "Approve", "sha256:0", "")
    Do $$$AssertEquals(out.code, $SELECT(may: "no_task", 1: "forbidden"), "no task, no decision: " _ out.error)
    Do $$$AssertEquals(..TaskCount("UT-WF-NONE"), 0, "and no task row appeared")
}

/// The case's approval task starts with an empty PlanDigest form value and carries the digest in its text, with the
/// instruction to paste it.
Method TestCaseTaskCarriesNoDigestValue()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-WF-1", case.Headline = "Resend the transfer at version 3"
    Set case.OperationKey = "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T09:00:00Z"
    Set plan = ##class(Shutter.Store.Plan).%New()
    Set plan.Version = 1, plan.Disposition = "resend", plan.ActionType = "resend", plan.OperationKey = case.OperationKey
    Set plan.ExpectedVersion = 3, plan.Digest = "sha256:abc"
    Set task = ##class(Shutter.Process.CaseWorkflow).ApprovalTask(case, plan)
    Do $$$AssertEquals(task.%Subject, "Shutter UT-WF-1: approve plan v1 (resend)", "the subject names the case and the plan")
    Do $$$AssertEquals(task.%Actions, "Approve,Reject", "the actions")
    Do $$$AssertEquals(task.%Priority, 2, "the priority")
    Do $$$AssertEquals(task.%FormFields, "PlanDigest,Comment", "the form fields")
    Do $$$AssertEquals(task.%FormValues.GetAt("PlanDigest"), "", "the PlanDigest form value starts empty")
    Do $$$AssertTrue(task.%Message [ "Plan digest: sha256:abc", "the digest is in the text the approver reads")
    Do $$$AssertTrue(task.%Message [ "PlanDigest field", "with the instruction to paste it")
    Do $$$AssertTrue(task.%Message [ "Exact action: resend " _ case.OperationKey _ " at receiver version 3", "and the exact action")
}

/// The incident's approval task, shared or per chain, starts with an empty PlanDigest form value and carries the
/// digest and what the approval binds in its text.
Method TestIncidentTaskCarriesNoDigestValue()
{
    Set receiver = $PARAMETER("Shutter.Production", "RECEIVER")
    Set inc = ##class(Shutter.Store.Incident).%New()
    Set inc.IncidentId = "UT-WF-I1", inc.Receiver = receiver, inc.OpenedAt = "2026-10-19T09:00:00Z", inc.PlanDigest = "sha256:def"
    Set inc.CatalogueVersion = "E1@1,E2@1", inc.ProfileVersion = "3", inc.PolicyVersion = "2026-10-26.1"
    Set lines = $CHAR(10) _ "Chain 1 (ordered, E4,E4): encounter ENC-UT1, patient MRN-UT1, first at receiver version 1"
    Set task = ##class(Shutter.Process.IncidentWorkflow).ApprovalTask(inc, "", 1, 2, lines)
    Do $$$AssertEquals(task.%Subject, "Shutter UT-WF-I1: approve the release of 1 chain(s) to " _ receiver, "the shared task's subject")
    Do $$$AssertEquals(task.%Actions, "Approve,Reject", "the actions")
    Do $$$AssertEquals(task.%Priority, 1, "the priority")
    Do $$$AssertEquals(task.%FormFields, "PlanDigest,Comment", "the form fields")
    Do $$$AssertEquals(task.%FormValues.GetAt("PlanDigest"), "", "the PlanDigest form value starts empty")
    Do $$$AssertTrue(task.%Message [ "Plan digest: sha256:def", "the digest is in the text the approver reads")
    Do $$$AssertTrue(task.%Message [ "PlanDigest field", "with the instruction to paste it")
    Do $$$AssertTrue(task.%Message [ "2 failures to " _ receiver, "the count of failures")
    Do $$$AssertTrue(task.%Message [ lines, "the chains as listed")
    Do $$$AssertTrue(task.%Message [ "catalogue entry and outcome listed for it", "and that each operation goes only as listed")
    Set task = ##class(Shutter.Process.IncidentWorkflow).ApprovalTask(inc, "2", 1, 2, "")
    Do $$$AssertEquals(task.%Subject, "Shutter UT-WF-I1/2: approve the release of 1 chain(s) to " _ receiver, "a chain's own task names the chain")
}

/// A decision that lands while the engine is still distributing the task (CI, 2 Nov 2026): the task is saved, with no
/// worklist row yet. The assignment waits for the engine's row and assigns the task without one when none comes; a row
/// the engine wrote first is used, not written again; and the error of an assignment whose row met the engine's is
/// told from other errors, so that assignment is tried again.
Method TestAssignFollowsTheEnginesDistribution()
{
    Set role = ..#ROLE, user = ..#USER
    Do ..RemoveRole()
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.RoleDefinition).CreateRole(role), "a role of the test's own is made")
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.UserDefinition).CreateUser(user, "Shutter unit test approver"), "and a user")
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(role, user, 1, "Approver"), "in the role")
    Set task = ..SavedTask(role, "UT-WF-2")
    If '$$$AssertTrue($ISOBJECT(task), "a task as the engine saves it before distributing it") Do ..RemoveRole() Quit
    Set id = task.%Id()
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).HasWorklistRow(task, user), 0, "with no worklist row yet")
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).WaitForWorklist(task, user, 0.2), 0, "a wait for the row runs out when the engine never writes it")
    Do $$$AssertStatusOK(##class(Shutter.Util.Workflow).Assign(task, user), "the task is assigned all the same")
    Do $$$AssertEquals(task.%TaskStatus.AssignedTo, user, "to the user")
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).HasWorklistRow(task, user), 1, "with the row AssignTask wrote")
    Do $$$AssertEquals(..WorklistCount(id), 1, "one row")
    Do ..DeleteTask(task)
    Do $$$AssertEquals(..WorklistCount(id), 0, "the test's rows are gone")
    // The engine's row first, its distribution done: the assignment uses it.
    Set task = ..SavedTask(role, "UT-WF-3")
    If '$$$AssertTrue($ISOBJECT(task), "a second task") Do ..RemoveRole() Quit
    Set id = task.%Id()
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.Engine).SendTask(task, user), "the engine distributes the task to the user")
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).WaitForWorklist(task, user, 0.2), 1, "the wait finds the engine's row at once")
    Do $$$AssertStatusOK(##class(Shutter.Util.Workflow).Assign(task, user), "and the assignment uses it")
    Do $$$AssertEquals(..WorklistCount(id), 1, "still one row")
    Do $$$AssertEquals(task.%TaskStatus.AssignedTo, user, "assigned to the user")
    Do ..DeleteTask(task)
    // The error an assignment meets when its row and the engine's collide, and errors that are not that.
    Set dup = $$$ERROR(5805, "EnsLib.Workflow.Worklist", "^EnsLib.W.WorklistD(65,""approver"")", "^EnsLib.W.WorklistD")
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).MeetsEnginesRow(dup), 1, "the worklist's duplicate key is the engine's row: " _ $SYSTEM.Status.GetErrorText(dup))
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).MeetsEnginesRow($$$ERROR(5805, "Shutter.Store.Case", "x", "y")), 0, "another extent's duplicate key is not")
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).MeetsEnginesRow($$$ERROR($$$GeneralError, "EnsLib.Workflow.Worklist")), 0, "nor another error naming the worklist")
    Do $$$AssertEquals(##class(Shutter.Util.Workflow).MeetsEnginesRow($$$OK), 0, "nor success")
    Do ..RemoveRole()
}

/// A task as the engine saves it before distributing it: its request and role, unassigned, no worklist row; "" when
/// the save fails.
ClassMethod SavedTask(role As %String, caseId As %String) As EnsLib.Workflow.TaskResponse
{
    Set req = ##class(EnsLib.Workflow.TaskRequest).%New()
    Set req.%Subject = "Shutter " _ caseId _ ": approve plan v1 (resend)", req.%Actions = "Approve,Reject"
    Set task = ##class(EnsLib.Workflow.TaskResponse).%New()
    Set task.%Subject = req.%Subject, task.%Actions = req.%Actions, task.%RoleName = role
    Set task.%TaskStatus.Role = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(role)
    Set task.%TaskStatus.Request = req
    Set task.%TaskStatus.AssignedTo = ""
    Set sc = task.%Save()
    Quit $SELECT($$$ISOK(sc): task, 1: "")
}

/// Removes a test's task, its request and its worklist rows.
ClassMethod DeleteTask(task As EnsLib.Workflow.TaskResponse)
{
    Set id = task.%Id(), reqId = task.%TaskStatus.RequestGetObjectId()
    &sql(DELETE FROM EnsLib_Workflow.Worklist WHERE Task = :id)
    Do ##class(EnsLib.Workflow.TaskResponse).%DeleteId(id)
    If reqId '= "" Do ##class(EnsLib.Workflow.TaskRequest).%DeleteId(reqId)
}

/// How many worklist rows a task has.
ClassMethod WorklistCount(taskId As %String) As %Integer
{
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM EnsLib_Workflow.Worklist WHERE Task = :taskId)
    Quit +n
}

/// Decide's JSON answer as an object.
ClassMethod Decide(caseId As %String, action As %String, digest As %String, comment As %String) As %DynamicObject
{
    Set out = ##class(Shutter.Util.Json).Parse(##class(Shutter.Util.Workflow).Decide(caseId, action, digest, comment), .sc)
    Quit $SELECT($ISOBJECT(out): out, 1: {"code": "unparsed", "error": "the answer was not JSON"})
}

/// How many Workflow tasks name a case.
ClassMethod TaskCount(caseId As %String) As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM EnsLib_Workflow.TaskResponse WHERE ""%Subject"" LIKE ?", "Shutter " _ caseId _ ":%")
    Do rs.%Next()
    Quit +rs.%Get("N")
}

}
