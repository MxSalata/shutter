/// A stand-in for the Incident Workflow for the unit tests: made with %New outside the production, it keeps what it is
/// asked to send instead of queueing it. A Workflow task is checked as the engine's save checks it, so a task that does
/// not fit is refused with the engine's own error, and Refuse makes every task fail with that text. Not a test case: the
/// runner leaves it alone.
Class Shutter.Test.FakeIncidentWorkflow Extends Shutter.Process.IncidentWorkflow
{

/// What was sent, one entry per request: "target|completion key".
Property Sent As list Of %String(MAXLEN = 400);

/// The alerts raised, by their text.
Property Alerts As list Of %String(MAXLEN = 4000);

/// When set, a Workflow task is refused with this text.
Property Refuse As %String(MAXLEN = 200);

/// The last task accepted.
Property LastTask As EnsLib.Workflow.TaskRequest(XMLPROJECTION = "none") [ Transient ];

Method SendRequestAsync(pTargetDispatchName As %String, pRequest As %Library.Persistent, pResponseRequired As %Boolean = 1, pCompletionKey As %String = "", pDescription As %String = "") As %Status
{
    If pRequest.%IsA("EnsLib.Workflow.TaskRequest") {
        If ..Refuse '= "" Quit $$$ERROR($$$GeneralError, ..Refuse)
        Set sc = pRequest.%ValidateObject()
        Quit:$$$ISERR(sc) sc
        Set ..LastTask = pRequest
    }
    Do ..Sent.Insert(pTargetDispatchName _ "|" _ pCompletionKey)
    Quit $$$OK
}

Method SendAlert(pAlertRequest As Ens.AlertRequest) As %Status
{
    Do ..Alerts.Insert(pAlertRequest.AlertText)
    Quit $$$OK
}

}
