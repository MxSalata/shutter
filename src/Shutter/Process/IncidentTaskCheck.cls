/// Whether an incident's approval task can be made, and whether one was (CONTRACTS 7.3). The Workflow item defers its
/// reply before it makes the task, so an error inside it (its role not defined, for one) never answers the call: the
/// incident would wait on a task that does not exist. Before the call, RoleMissing names a role the item would not
/// find; after it, Lost tells whether the item took the request and made no task.
Class Shutter.Process.IncidentTaskCheck
{

/// An error when the approval target is a Workflow item whose role (the item's own name) is not defined; $$$OK
/// otherwise, and for a target that is not a Workflow item.
ClassMethod RoleMissing(target As %String) As %Status
{
    Set class = $GET(^Ens.Runtime("ConfigItem", target, "ClassName"))
    If (class '= "") && '$CLASSMETHOD(class, "%Extends", "EnsLib.Workflow.Operation") Quit $$$OK
    If ##class(EnsLib.Workflow.RoleDefinition).%ExistsId(target) Quit $$$OK
    Quit $$$ERROR($$$GeneralError, "the Workflow role " _ target _ " is not defined, so the Workflow item would make no task")
}

/// What became of a task request sent to the Workflow item: "" when its task exists, or the request cannot be found;
/// "wait" while the item has not finished with it (created, queued, being delivered, suspended); otherwise the reason
/// there is no task: the item finished with the request at least 10 seconds ago (deferred, completed, errored,
/// discarded or aborted) and no task names it. A task already answered still counts as made.
ClassMethod Lost(requestId As %String, subjectPrefix As %String) As %String
{
    Quit:requestId="" ""
    If ..TaskFor(requestId, subjectPrefix) Quit ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, Status, DATEDIFF('s', COALESCE(TimeProcessed, TimeCreated), GETUTCDATE()) AS Age FROM Ens.MessageHeader WHERE MessageBodyClassName = 'EnsLib.Workflow.TaskRequest' AND MessageBodyId = ? ORDER BY ID", requestId)
    Quit:'rs.%Next() ""
    Set header = rs.%Get("ID"), status = rs.%Get("Status"), age = rs.%Get("Age")
    // 1 created, 2 queued, 3 delivered, 5 suspended: the item has not finished with it, and a task may still come.
    If $LISTFIND($LISTBUILD(1, 2, 3, 5), status) Quit "wait"
    If age < 10 Quit "wait"
    // A task made in between counts.
    If ..TaskFor(requestId, subjectPrefix) Quit ""
    Quit "the Workflow item took the request (message " _ header _ ", status " _ ..StatusName(status) _ ") and made no task; its Event Log has the error"
}

/// Whether a Workflow task, open or answered, was made from this request, among the tasks whose subject starts so.
ClassMethod TaskFor(requestId As %String, subjectPrefix As %String) As %Boolean
{
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE ""%Subject"" %STARTSWITH ? ORDER BY ID DESC", subjectPrefix)
    While rs.%Next() {
        Set task = ##class(EnsLib.Workflow.TaskResponse).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(task)
        If $ISOBJECT(task.%TaskStatus) && (task.%TaskStatus.RequestGetObjectId() = requestId) Return 1
    }
    Quit 0
}

ClassMethod StatusName(status As %Integer) As %String
{
    Quit $CASE(status, 4: "discarded", 6: "deferred", 7: "aborted", 8: "error", 9: "completed", : status)
}

/// The subject every task for the incident's shared approval (seq "") or for one chain starts with, as ApprovalTask
/// writes it.
ClassMethod SubjectPrefix(incidentId As %String, seq As %String) As %String
{
    Quit "Shutter " _ incidentId _ $SELECT(seq '= "": "/" _ seq, 1: "") _ ":"
}

}
