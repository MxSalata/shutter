/// The Workflow engine's tasks for Interlock cases: finding a case's open approval task and
/// completing it on a person's behalf. The REST API calls Decide() after its own checks; the
/// Management Portal's Workflow inbox is the other way to answer a task.
Class Interlock.Util.Workflow Extends %RegisteredObject
{

/// The open (incomplete) approval task for a case, or "".
ClassMethod OpenTaskFor(caseId As %String) As EnsLib.Workflow.TaskResponse
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE ""%Subject"" LIKE ? ORDER BY ID DESC", "Interlock " _ caseId _ ":%")
    While rs.%Next() {
        Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(task)
        If $ISOBJECT(task.%TaskStatus) && task.%TaskStatus.IsComplete Continue
        Return task
    }
    Quit ""
}

/// Every task for a case, newest first, as a dynamic array for the API.
ClassMethod TasksFor(caseId As %String) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE ""%Subject"" LIKE ? ORDER BY ID DESC", "Interlock " _ caseId _ ":%")
    While rs.%Next() {
        Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(task)
        Set t = {}
        Set t."task_id" = task.%Id(), t.subject = task.%Subject, t.actions = task.%Actions
        Set t.action = task.%Action, t."user_name" = task.%UserName, t.role = task.%RoleName
        Set t.priority = task.%Priority
        If $ISOBJECT(task.%TaskStatus) {
            Do t.%Set("complete", ''task.%TaskStatus.IsComplete, "boolean")
            Set t."assigned_to" = task.%TaskStatus.AssignedTo
            Set t."time_created" = task.%TaskStatus.TimeCreated
            Set t."time_completed" = task.%TaskStatus.TimeCompleted
        }
        Set t."plan_digest" = task.%FormValues.GetAt("PlanDigest")
        Do out.%Push(t)
    }
    Quit out
}

/// Complete a case's open approval task with an action (Approve or Reject) as a user. The task is
/// assigned to the user first, so the Workflow engine records who decided. Returns JSON with the
/// task id, or an error.
ClassMethod Decide(caseId As %String, action As %String = "Approve", user As %String = "approver", comment As %String = "") As %String [ SqlProc ]
{
    Set task = ..OpenTaskFor(caseId)
    If '$ISOBJECT(task) Quit "{""error"": ""no open approval task for " _ caseId _ """}"
    Set action = $SELECT($ZCONVERT(action, "L") = "reject": "Reject", 1: "Approve")
    Set sc = ##class(EnsLib.Workflow.Engine).AssignTask(task, user)
    If $$$ISERR(sc) Quit "{""error"": " _ ##class(Interlock.Util.Digest).JSONString($SYSTEM.Status.GetErrorText(sc)) _ "}"
    Do task.%FormValues.SetAt(comment, "Comment")
    Set task.%UserName = user
    Set sc = task.%Save()
    If $$$ISERR(sc) Quit "{""error"": " _ ##class(Interlock.Util.Digest).JSONString($SYSTEM.Status.GetErrorText(sc)) _ "}"
    Set sc = ##class(EnsLib.Workflow.Engine).CompleteTask(task, action)
    If $$$ISERR(sc) Quit "{""error"": " _ ##class(Interlock.Util.Digest).JSONString($SYSTEM.Status.GetErrorText(sc)) _ "}"
    Set r = {}
    Set r."task_id" = task.%Id(), r.action = action, r.user = user, r."case_id" = caseId
    Quit r.%ToJSON()
}

}
