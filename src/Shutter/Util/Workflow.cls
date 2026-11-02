/// The Workflow engine's tasks for Shutter cases and incidents: finding a case's open approval task and completing
/// it on the signed-in user's behalf. The REST API calls Decide() after its own checks, and a script or the terminal
/// calls it through SQL; the Management Portal's Workflow inbox is the other way to answer a task, and there the
/// approver pastes the plan digest from the task's text into its PlanDigest field.
Class Shutter.Util.Workflow Extends %RegisteredObject
{

/// The open (incomplete) approval task for a case, or "".
ClassMethod OpenTaskFor(caseId As %String) As EnsLib.Workflow.TaskResponse
{
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE ""%Subject"" LIKE ? ORDER BY ID DESC", "Shutter " _ caseId _ ":%")
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
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE ""%Subject"" LIKE ? ORDER BY ID DESC", "Shutter " _ caseId _ ":%")
    While rs.%Next() {
        Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(task)
        Set t = {}
        Set t.taskId = task.%Id(), t.subject = task.%Subject, t.actions = task.%Actions
        Set t.action = task.%Action, t.userName = task.%UserName, t.role = task.%RoleName
        Set t.priority = task.%Priority
        If $ISOBJECT(task.%TaskStatus) {
            Do t.%Set("complete", ''task.%TaskStatus.IsComplete, "boolean")
            Set t.assignedTo = task.%TaskStatus.AssignedTo
            Do ..SetTime(t, "timeCreated", task.%TaskStatus.TimeCreated)
            Do ..SetTime(t, "timeCompleted", task.%TaskStatus.TimeCompleted)
        }
        // Empty while the task is open: the decider supplies the digest (Decide, or the inbox approver).
        Set t.planDigest = task.%FormValues.GetAt("PlanDigest")
        Do out.%Push(t)
    }
    Quit out
}

/// Complete a case's or an incident's open approval task with an action (Approve or Reject) as the signed-in user:
/// the process's own $USERNAME (the REST session's user, a SQL session's, the terminal's), never a name passed in. The
/// decider holds Shutter_Approve and is a member of the task's Workflow role, and a task another approver has
/// accepted stays theirs. The task is assigned to the user first, so the Workflow engine records who decided, and the
/// digest the caller binds is written into the task's PlanDigest form value, which the case or incident workflow
/// checks against the plan (CONTRACTS 6.4, 7.3): an approval with no digest is refused here. Returns JSON with the
/// task id, the action, the user and the case id, or an error with its code (unauthenticated, forbidden, no_digest,
/// no_task, not_in_role, assigned_to_other, engine).
ClassMethod Decide(caseId As %String, action As %String = "Approve", digest As %String = "", comment As %String = "") As %String [ SqlProc ]
{
    // SQL passes its empty string as $CHAR(0).
    If digest = $CHAR(0) Set digest = ""
    If comment = $CHAR(0) Set comment = ""
    Set user = ..Actor()
    If user = "" Quit ..ErrorJSON("unauthenticated", "no signed-in user to decide as")
    If '$SYSTEM.Security.Check("Shutter_Approve", "USE") Quit ..ErrorJSON("forbidden", "Shutter_Approve is required to decide a task")
    Set action = $SELECT($ZCONVERT(action, "L") = "reject": "Reject", 1: "Approve")
    If (action = "Approve") && (digest = "") Quit ..ErrorJSON("no_digest", "an approval names the plan digest it binds")
    Set task = ..OpenTaskFor(caseId)
    If '$ISOBJECT(task) Quit ..ErrorJSON("no_task", "no open approval task for " _ caseId)
    If '..IsMember(task.%RoleName, user) Quit ..ErrorJSON("not_in_role", user _ " is not a member of the Workflow role " _ task.%RoleName)
    Set assigned = $SELECT($ISOBJECT(task.%TaskStatus): task.%TaskStatus.AssignedTo, 1: "")
    If (assigned '= "") && (assigned '= user) Quit ..ErrorJSON("assigned_to_other", "the task is assigned to " _ assigned)
    Set sc = ##class(EnsLib.Workflow.Engine).AssignTask(task, user)
    If $$$ISERR(sc) Quit ..ErrorJSON("engine", $SYSTEM.Status.GetErrorText(sc))
    Do task.%FormValues.SetAt(digest, "PlanDigest")
    Do task.%FormValues.SetAt(comment, "Comment")
    Set sc = task.%Save()
    If $$$ISERR(sc) Quit ..ErrorJSON("engine", $SYSTEM.Status.GetErrorText(sc))
    Set sc = ##class(EnsLib.Workflow.Engine).CompleteTask(task, action)
    If $$$ISERR(sc) Quit ..ErrorJSON("engine", $SYSTEM.Status.GetErrorText(sc))
    Set r = {}
    Set r."task_id" = task.%Id(), r.action = action, r.user = user, r."case_id" = caseId
    Quit r.%ToJSON()
}

/// The user the process runs as (the REST session's, a SQL session's, the terminal's), or "" when there is none.
ClassMethod Actor() As %String
{
    Quit $SELECT($USERNAME = "UnknownUser": "", 1: $USERNAME)
}

/// Whether a user is a member of a Workflow role: the engine's membership record, whose id is <role>||<user>.
ClassMethod IsMember(role As %String, user As %String) As %Boolean
{
    If (role = "") || (user = "") Quit 0
    If '##class(EnsLib.Workflow.RoleMembership).%ExistsId(role _ "||" _ user) Quit 0
    // A Workflow user marked inactive is no approver, whatever the membership row says (v1.35).
    Set u = ##class(EnsLib.Workflow.UserDefinition).%OpenId(user)
    Quit $SELECT($ISOBJECT(u): ''u.IsActive, 1: 1)
}

/// An error as JSON with its code, for the API's status mapping and for a SQL caller.
ClassMethod ErrorJSON(code As %String, text As %String) As %String
{
    Set e = {}
    Set e.error = text, e.code = code
    Quit e.%ToJSON()
}

/// Sets <var>key</var> on <var>obj</var> to a Workflow timestamp (UTC, "yyyy-mm-dd hh:mm:ss.fff") as ISO 8601,
/// or null when empty.
ClassMethod SetTime(obj As %DynamicObject, key As %String, ts As %String)
{
    If ts = "" Do obj.%Set(key, "", "null") Quit
    Do obj.%Set(key, $TRANSLATE(ts, " ", "T") _ "Z")
}

}
