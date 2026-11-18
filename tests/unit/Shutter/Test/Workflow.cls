/// Who decides a Workflow task and what the task carries (CONTRACTS 5, 6.4, 7.3): Shutter.Util.Workflow takes the decider
/// from the process's own user, never from an argument, refuses an approval that names no digest and a decider outside
/// the task's Workflow role, and the approval tasks of a case and of an incident are bound on the server to what they
/// approve, with an empty PlanDigest form value for the API's decider and the digest in the text the approver reads; and
/// an assignment keeps in step with the engine's distribution of the task. Nothing here needs a production or leaves a row: the membership and assignment tests make a Workflow role
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

/// The workflow sets a case to awaiting approval and then sends its task, so a decision can arrive first. The wait finds a
/// task saved during it, runs out when none comes, and costs nothing when the task is already there.
Method TestDecisionWaitsForATaskOnItsWay()
{
    Set role = ..#ROLE
    Do ..RemoveRole()
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.RoleDefinition).CreateRole(role), "a role of the test's own is made")
    Set start = $ZHOROLOG
    Do $$$AssertTrue('$ISOBJECT(##class(Shutter.Util.Workflow).WaitForTask("UT-WF-4", 0.2)), "no task comes, so the wait finds none")
    Do $$$AssertTrue(($ZHOROLOG - start) >= 0.2, "having waited")
    Job ##class(Shutter.Test.Workflow).SaveTaskLater(role, "UT-WF-5", 0.3)
    Set task = ##class(Shutter.Util.Workflow).WaitForTask("UT-WF-5", 10)
    If $$$AssertTrue($ISOBJECT(task), "a task saved during the wait is found") Do ..DeleteTask(task)
    Set task = ..SavedTask(role, "UT-WF-6")
    If '$$$AssertTrue($ISOBJECT(task), "a task already there") Do ..RemoveRole() Quit
    Set start = $ZHOROLOG
    Set found = ##class(Shutter.Util.Workflow).WaitForTask("UT-WF-6", 10)
    Do $$$AssertEquals($SELECT($ISOBJECT(found): found.%Id(), 1: ""), task.%Id(), "is found")
    Do $$$AssertTrue(($ZHOROLOG - start) < 5, "without waiting the wait out")
    Do ..DeleteTask(task)
    Do ..RemoveRole()
}

/// Two decisions on one case are taken one at a time, so the second finds no open task: when the case's newest task is
/// complete and bound to the digest the second names, the second is told the decision that stands (decided, with the
/// action, who took it and when); a task bound to another digest, a decision with no digest and a case with no task
/// still get no_task.
Method TestASecondDecisionIsToldTheOneThatStands()
{
    Set role = ..#ROLE
    Do ..RemoveRole()
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.RoleDefinition).CreateRole(role), "a role of the test's own is made")
    Set task = ..SavedTask(role, "UT-WF-7")
    If '$$$AssertTrue($ISOBJECT(task), "a task") Do ..RemoveRole() Quit
    Do task.%FormValues.SetAt("sha256:7", "PlanDigest")
    Set task.%Action = "Reject", task.%UserName = $USERNAME
    Set task.%TaskStatus.IsComplete = 1, task.%TaskStatus.TimeCompleted = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Do $$$AssertStatusOK(task.%Save(), "the first decision completes the task")
    Set out = ##class(Shutter.Util.Json).Parse(##class(Shutter.Util.Workflow).NoOpenTask("UT-WF-7", "sha256:7"), .sc)
    Do $$$AssertEquals(out.code, "decided", "the second decision is told the first stands: " _ out.error)
    Do $$$AssertEquals(out.action, "Reject", "naming its action")
    Do $$$AssertEquals(out.user, $USERNAME, "who took it")
    Do $$$AssertTrue(out.completedAt '= "", "and when")
    Set out = ##class(Shutter.Util.Json).Parse(##class(Shutter.Util.Workflow).NoOpenTask("UT-WF-7", "sha256:other"), .sc)
    Do $$$AssertEquals(out.code, "no_task", "a task bound to another digest is not this decision's")
    Set out = ##class(Shutter.Util.Json).Parse(##class(Shutter.Util.Workflow).NoOpenTask("UT-WF-7", ""), .sc)
    Do $$$AssertEquals(out.code, "no_task", "nor one that names no digest")
    Set out = ##class(Shutter.Util.Json).Parse(##class(Shutter.Util.Workflow).NoOpenTask("UT-WF-NONE", "sha256:7"), .sc)
    Do $$$AssertEquals(out.code, "no_task", "and a case with no task has none")
    Do ..DeleteTask(task)
    Do ..RemoveRole()
}

/// Saves a task after a moment, as the Workflow operation does once the workflow has sent it.
ClassMethod SaveTaskLater(role As %String, caseId As %String, seconds As %Numeric)
{
    Hang seconds
    Do ..SavedTask(role, caseId)
}

/// The case's approval task is bound on the server when it is made (Shutter.Process.TaskBinding): its form takes only a
/// comment, its PlanDigest form value starts empty for the API's decider alone, and its text carries the digest and says
/// nothing needs pasting.
Method TestCaseTaskIsBound()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-WF-1", case.Headline = "Resend the transfer at version 3"
    Set case.OperationKey = "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T09:00:00Z"
    Set plan = ##class(Shutter.Store.Plan).%New()
    Set plan.Version = 1, plan.Disposition = "resend", plan.ActionType = "resend", plan.OperationKey = case.OperationKey
    Set plan.ExpectedVersion = 3, plan.Digest = "sha256:abc"
    Set task = ##class(Shutter.Process.CaseWorkflow).ApprovalTask(case, plan, 0, "R-7", 4, 2)
    Do $$$AssertEquals(task.%Subject, "Shutter UT-WF-1: approve plan v1 (resend)", "the subject names the case and the plan")
    Do $$$AssertEquals(task.%Actions, "Approve,Reject", "the actions")
    Do $$$AssertEquals(task.%Priority, 2, "the priority")
    Do $$$AssertEquals(task.%FormFields, "Comment", "the inbox's form takes only a comment")
    Do $$$AssertEquals(task.%FormTemplate, "Shutter.Process.ApprovalForm.cls", "drawn by Shutter's own form page")
    Do $$$AssertEquals(task.%FormValues.GetAt("PlanDigest"), "", "the PlanDigest form value starts empty: only the API's decider writes one")
    Set v = task.%FormValues
    Do $$$AssertEquals(v.GetAt("Shutter.Kind") _ "|" _ v.GetAt("Shutter.Case") _ "|" _ v.GetAt("Shutter.CaseVersion") _ "|" _ v.GetAt("Shutter.PlanVersion") _ "|" _ v.GetAt("Shutter.PlanDigest") _ "|" _ v.GetAt("Shutter.Rehearsal") _ "|" _ v.GetAt("Shutter.ReceiverVersion") _ "|" _ v.GetAt("Shutter.ReceiverEpoch") _ "|" _ v.GetAt("Shutter.Policy"), "case|UT-WF-1|1|1|sha256:abc|R-7|4|2|" _ ##class(Shutter.Operation.Gate).#POLICYVERSION, "bound to the case, the plan, the rehearsal, the receiver and the gate's policy")
    Do $$$AssertEquals(v.GetAt("Shutter.SiteProfile") _ "|" _ v.GetAt("Shutter.Catalogue"), ##class(Shutter.Process.TaskBinding).ProfileVersion() _ "|" _ ##class(Shutter.Process.TaskBinding).CatalogueDigest(), "and to the site profile and the catalogue")
    Do $$$AssertTrue(task.%Message [ "Plan digest: sha256:abc", "the digest is in the text the approver reads")
    Do $$$AssertNotTrue(task.%Message [ "PlanDigest field", "nothing asks for a paste")
    Do $$$AssertTrue(task.%Message [ "needs nothing pasted: this task is bound to this plan, case version 1, this evidence and rehearsal, and receiver version 4", "the text says what the task is bound to")
    Do $$$AssertTrue(task.%Message [ "Exact action: resend " _ case.OperationKey _ " at receiver version 3", "and the exact action")
    Set task = ##class(Shutter.Process.CaseWorkflow).ApprovalTask(case, plan)
    Do $$$AssertEquals(task.%FormValues.GetAt("Shutter.ReceiverVersion"), 3, "with no rehearsed version, the plan's expected version is bound")
}

/// What moved since a case's task was made, said in words, from the request the workflow sent; nothing when the binding
/// holds, and a refreshed snapshot keeps it when nothing material changed (A7). A request that is not a bound task is not
/// bound.
Method TestCaseBindingIsChecked()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-WF-3", case.Headline = "Resend", case.OperationKey = "PAS^HOSP^MRN-UT3^ENC-UT3^transfer^2026-10-19T09:00:00Z"
    Set snap = ##class(Shutter.Store.Snapshot).%New()
    Set snap.Digest = "sha256:snap1", snap.MaterialDigest = "sha256:mat1"
    Set case.CurrentSnapshot = snap
    Set plan = ##class(Shutter.Store.Plan).%New()
    Set plan.Version = 2, plan.Disposition = "resend", plan.ActionType = "resend", plan.OperationKey = case.OperationKey, plan.ExpectedVersion = 3, plan.Digest = "sha256:abc"
    Set policy = ##class(Shutter.Operation.Gate).#POLICYVERSION
    Set task = ##class(Shutter.Process.CaseWorkflow).ApprovalTask(case, plan, 0, "R-7", 3, 2)
    Set binding = "Shutter.Process.TaskBinding"
    Do $$$AssertTrue($CLASSMETHOD(binding, "IsBound", task), "the task is bound")
    Do $$$AssertEquals($CLASSMETHOD(binding, "BoundDigest", task), "sha256:abc", "to the plan's digest")
    Do $$$AssertEquals($CLASSMETHOD(binding, "CaseMoved", task, case, plan, "R-7", 3, 2, policy), "", "nothing moved")
    Set case.Version = 2
    Do $$$AssertEquals($CLASSMETHOD(binding, "CaseMoved", task, case, plan, "R-7", 3, 2, policy), "the case moved: version 1 when the task was made, 2 now", "the case moved")
    Set case.Version = 1, plan.Digest = "sha256:def"
    Do $$$AssertTrue($CLASSMETHOD(binding, "CaseMoved", task, case, plan, "R-7", 3, 2, policy) [ "the plan moved: the task was made for plan v2 (sha256:abc)", "the plan moved")
    Set plan.Digest = "sha256:abc", snap.Digest = "sha256:snap2"
    Do $$$AssertEquals($CLASSMETHOD(binding, "CaseMoved", task, case, plan, "R-7", 3, 2, policy), "", "a refreshed snapshot with the same material keeps the binding")
    Set snap.MaterialDigest = "sha256:mat2"
    Do $$$AssertEquals($CLASSMETHOD(binding, "CaseMoved", task, case, plan, "R-7", 3, 2, policy), "the evidence moved: snapshot sha256:snap1 when the task was made, sha256:snap2 now", "a material change moves the evidence")
    Set snap.Digest = "sha256:snap1", snap.MaterialDigest = "sha256:mat1"
    Do $$$AssertEquals($CLASSMETHOD(binding, "CaseMoved", task, case, plan, "R-8", 3, 2, policy), "the rehearsal moved: R-7 when the task was made, R-8 now", "another rehearsal")
    Do $$$AssertEquals($CLASSMETHOD(binding, "CaseMoved", task, case, plan, "R-7", 4, 2, policy), "the receiver version moved: 3 when the task was made, 4 now", "another receiver version")
    Do $$$AssertEquals($CLASSMETHOD(binding, "CaseMoved", task, case, plan, "R-7", 3, 5, policy), "the receiver's epoch moved: 2 when the task was made, 5 now", "another epoch")
    Do $$$AssertEquals($CLASSMETHOD(binding, "CaseMoved", task, case, plan, "R-7", 3, 2, "2000-01-01.1"), "the gate's policy moved: " _ policy _ " when the task was made, 2000-01-01.1 now", "another gate policy")
    Set other = ##class(Shutter.Store.Case).%New()
    Set other.CaseId = "UT-WF-4", other.CurrentSnapshot = snap
    Do $$$AssertEquals($CLASSMETHOD(binding, "CaseMoved", task, other, plan, "R-7", 3, 2, policy), "the task is for case UT-WF-3", "a task for another case")
    Set old = ##class(EnsLib.Workflow.TaskRequest).%New()
    Set old.%FormFields = "PlanDigest,Comment"
    Do $$$AssertNotTrue($CLASSMETHOD(binding, "IsBound", old), "a task made before tasks were bound is not")
    Do $$$AssertNotTrue($CLASSMETHOD(binding, "IsBound", ""), "nor is no request")
    Do $$$AssertNotTrue($CLASSMETHOD(binding, "IsBound", ##class(Shutter.Msg.WardOperation).%New()), "nor another kind of request")
    Do $$$AssertEquals($CLASSMETHOD(binding, "CaseMoved", "", case, plan, "R-7", 3, 2, policy), "the task is not bound", "and an unbound request never holds")
}

/// A line the approver should read that could not be worked out is said to be missing, not left out: the digest doesn't change,
/// so nothing else on the page would show it.
Method TestCaseTaskSaysWhatItCouldNotRead()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-WF-2", case.Headline = "Resend the transfer at version 3", case.OperationKey = "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T09:00:00Z"
    Set plan = ##class(Shutter.Store.Plan).%New()
    Set plan.Version = 1, plan.Disposition = "resend", plan.ActionType = "resend", plan.OperationKey = case.OperationKey, plan.ExpectedVersion = 3, plan.Digest = "sha256:abc"
    Do $$$AssertNotTrue(##class(Shutter.Process.CaseWorkflow).ApprovalTask(case, plan).%Message [ "could not be read", "a clean read says nothing")
    Set snap = ##class(Shutter.Store.Snapshot).%New()
    Set snap.Summary = "{not json"
    Set case.CurrentSnapshot = snap
    Set message = ##class(Shutter.Process.CaseWorkflow).ApprovalTask(case, plan).%Message
    Do $$$AssertTrue(message [ "further messages for this patient could not be read", "the task says what it could not read: " _ message)
    Do $$$AssertTrue(message [ "before deciding", "and what to do about it")
}

/// The incident's approval task, shared or per chain, is bound on the server to the incident, the chain and the plan
/// digest; its form takes only a comment, its PlanDigest form value starts empty, and its text carries the digest and what
/// the approval binds. The binding moves with another incident, another chain or another plan.
Method TestIncidentTaskIsBound()
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
    Do $$$AssertEquals(task.%FormFields _ "|" _ task.%FormTemplate, "Comment|Shutter.Process.ApprovalForm.cls", "the form takes only a comment, drawn by Shutter's own page")
    Do $$$AssertEquals(task.%FormValues.GetAt("PlanDigest"), "", "the PlanDigest form value starts empty")
    Set v = task.%FormValues
    Do $$$AssertEquals(v.GetAt("Shutter.Kind") _ "|" _ v.GetAt("Shutter.Incident") _ "|" _ v.GetAt("Shutter.Chain") _ "|" _ v.GetAt("Shutter.PlanDigest"), "incident|UT-WF-I1||sha256:def", "bound to the incident, the chains under one approval and the plan")
    Do $$$AssertTrue(task.%Message [ "Plan digest: sha256:def", "the digest is in the text the approver reads")
    Do $$$AssertNotTrue(task.%Message [ "PlanDigest field", "nothing asks for a paste")
    Do $$$AssertTrue(task.%Message [ "needs nothing pasted", "the text says so")
    Do $$$AssertTrue(task.%Message [ "2 failures to " _ receiver, "the count of failures")
    Do $$$AssertTrue(task.%Message [ lines, "the chains as listed")
    Do $$$AssertTrue(task.%Message [ "catalogue entry and outcome listed for it", "and that each operation goes only as listed")
    Set binding = "Shutter.Process.TaskBinding"
    Do $$$AssertEquals($CLASSMETHOD(binding, "IncidentMoved", task, inc, ""), "", "nothing moved")
    Do $$$AssertEquals($CLASSMETHOD(binding, "IncidentMoved", task, inc, "2"), "the task is for the chains under one approval", "an answer for a chain")
    Set inc.PlanDigest = "sha256:fed"
    Do $$$AssertEquals($CLASSMETHOD(binding, "IncidentMoved", task, inc, ""), "the plan moved: the task was made for sha256:def, the incident's plan is sha256:fed", "the plan moved")
    Set inc.PlanDigest = "sha256:def"
    Set task = ##class(Shutter.Process.IncidentWorkflow).ApprovalTask(inc, "2", 1, 2, "")
    Do $$$AssertEquals(task.%Subject, "Shutter UT-WF-I1/2: approve the release of 1 chain(s) to " _ receiver, "a chain's own task names the chain")
    Do $$$AssertEquals(task.%FormValues.GetAt("Shutter.Chain"), "2", "and binds it")
    Set html = ##class(Shutter.Process.ApprovalForm).FormHTML(task)
    Do $$$AssertTrue(html [ "<th scope=""row"">Incident</th><td>UT-WF-I1, chain 2</td>", "the form names the incident and the chain: " _ $EXTRACT(html, 1, 400))
    Do $$$AssertTrue(html [ "value=""sha256:def""", "and shows the digest")
    Do $$$AssertEquals($LENGTH(html, "name=""") - 1, 1, "with one named field")
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

/// A reopened case's agent requests carry the person who reopened it, for the budget's share, and run from recordings
/// only when that person may not spend the model budget (v1.39); a judge's forced board keeps the convener; the feed's
/// own case runs as "system" and live as its mode says. The rule is CaseWorkflow.Stamp, which the process applies with
/// its own state.
Method TestReopenedRunsCarryTheReopener()
{
    Set cls = "Shutter.Process.CaseWorkflow"
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req)
    Do $$$AssertEquals(req.RequestedBy, "system", "the feed's own case runs as system")
    Do $$$AssertEquals(req.ModeOverride, "", "and in the mode the item resolves")
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 0, "", "demo", 0)
    Do $$$AssertEquals(req.RequestedBy, "demo", "a reopened case's runs name the reopener")
    Do $$$AssertEquals(req.ModeOverride, "replay", "and replay when the reopener may not spend")
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 0, "", "operator", 1)
    Do $$$AssertEquals(req.RequestedBy, "operator", "an operator's reopening counts against the operator")
    Do $$$AssertEquals(req.ModeOverride, "", "and runs as the mode says")
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 1, "judge", "judge", 1)
    Do $$$AssertEquals(req.RequestedBy, "judge", "a forced board keeps its convener")
}

}
