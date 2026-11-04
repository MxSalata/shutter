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
    Set task = ..WaitForTask(caseId, ..#TASKWAIT)
    If '$ISOBJECT(task) Quit ..ErrorJSON("no_task", "no open approval task for " _ caseId)
    If '..IsMember(task.%RoleName, user) Quit ..ErrorJSON("not_in_role", user _ " is not a member of the Workflow role " _ task.%RoleName)
    Set assigned = $SELECT($ISOBJECT(task.%TaskStatus): task.%TaskStatus.AssignedTo, 1: "")
    If (assigned '= "") && (assigned '= user) Quit ..ErrorJSON("assigned_to_other", "the task is assigned to " _ assigned)
    Set sc = ..Assign(task, user)
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

/// How long Decide waits for a task on its way, in seconds.
Parameter TASKWAIT = 5;

/// The case's open task, waiting briefly for one that isn't there yet. The workflow sets a case to awaiting approval and
/// then sends its task, so a decision can arrive before the Workflow operation has saved it: the API's approver polls the
/// case and answers as soon as it awaits approval (CI, 4 Nov 2026, on a run with no change to this code: "no open approval
/// task"). A task already there costs no wait, and a case with no task coming still gets no_task, later.
ClassMethod WaitForTask(caseId As %String, seconds As %Numeric = 5) As EnsLib.Workflow.TaskResponse
{
    Set until = $ZHOROLOG + seconds
    While 1 {
        Set task = ..OpenTaskFor(caseId)
        If $ISOBJECT(task) Return task
        If $ZHOROLOG > until Return ""
        Hang 0.05
    }
    Quit ""
}

/// How long Assign waits for the engine's distribution to reach the user, in seconds.
Parameter DISTRIBUTIONWAIT = 2;

/// Assigns the task to the user through the engine, in step with the engine's own distribution of it. The engine saves
/// a new task and then writes a worklist row per member of its role, and AssignTask writes the user's row itself when
/// it finds none. A decision can land in that gap: the API's approver polls the case and answers as soon as it awaits
/// approval, which the workflow sets just before it sends the task (CI, 2 Nov 2026, once in some hundreds of runs:
/// "ID key not unique for extent 'EnsLib.Workflow.Worklist'" from AssignTask, whose row met the engine's). So this
/// waits, briefly, for the engine to reach the user's row, and when its own save still meets the engine's, assigns
/// once more: the row is there by then, and the engine uses it. A task the engine never reaches (no row after the wait)
/// is assigned as before.
ClassMethod Assign(task As EnsLib.Workflow.TaskResponse, user As %String) As %Status
{
    Do ..WaitForWorklist(task, user, ..#DISTRIBUTIONWAIT)
    Set sc = ##class(EnsLib.Workflow.Engine).AssignTask(task, user)
    If $$$ISERR(sc) && ..MeetsEnginesRow(sc) {
        Hang 0.05
        Set sc = ##class(EnsLib.Workflow.Engine).AssignTask(task, user)
    }
    Quit sc
}

/// Whether the engine's worklist row for the task and user exists: the engine's own record, whose id is <task>||<user>.
ClassMethod HasWorklistRow(task As EnsLib.Workflow.TaskResponse, user As %String) As %Boolean
{
    If '$ISOBJECT(task) || (task.%Id() = "") || (user = "") Quit 0
    Quit ''##class(EnsLib.Workflow.Worklist).%ExistsId(task.%Id() _ "||" _ user)
}

/// Waits up to <var>seconds</var> for the engine's worklist row for the task and user, looking every 50 ms: 1 when it
/// exists, 0 when the wait ran out.
ClassMethod WaitForWorklist(task As EnsLib.Workflow.TaskResponse, user As %String, seconds As %Numeric = 2) As %Boolean
{
    Set until = $ZHOROLOG + seconds
    While 1 {
        If ..HasWorklistRow(task, user) Return 1
        If $ZHOROLOG > until Return 0
        Hang 0.05
    }
    Quit 0
}

/// Whether an assignment failed because its worklist row met the engine's: error 5805, the ID key not unique, on the
/// worklist's extent.
ClassMethod MeetsEnginesRow(sc As %Status) As %Boolean
{
    If $$$ISOK(sc) Quit 0
    If '$LISTFIND($LISTFROMSTRING($SYSTEM.Status.GetErrorCodes(sc), ","), "5805") Quit 0
    Quit $SYSTEM.Status.GetErrorText(sc) [ "EnsLib.Workflow.Worklist"
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
