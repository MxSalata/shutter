/// The case workflow: opens a case from an intake and takes it through evidence, the board, the
/// coordinator, the gate, rehearsal, approval, execution and verification. One instance per case;
/// every step is a message, so the Visual Trace of a case is its audit trail.
///
/// This version does the intake: it opens or updates the case and answers. The steps follow.
Class Interlock.Process.CaseWorkflow Extends Ens.BusinessProcess
{

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    If 'request.%IsA("Interlock.Msg.CaseIntake") Quit $$$ERROR($$$GeneralError, "Case Workflow expects a case intake, got " _ $CLASSNAME(request))
    Set op = ##class(Interlock.Util.Json).Parse(request.OperationJSON, .sc)
    If $$$ISERR(sc) Quit sc
    Set existing = ##class(Interlock.Store.Case).FindOpen(op."operation_key")
    Set sc = ##class(Interlock.Store.Case).Open(op, request.FailureKind, request.FailureText, request.EnsSessionId, request.SourceHeaderId, request.Mode, .case)
    If $$$ISERR(sc) Quit sc
    Set opened = '$ISOBJECT(existing)
    Set started = ##class(Interlock.Msg.CaseStarted).%New()
    Set started.CaseId = case.CaseId, started.Opened = opened, started.State = case.State
    Set response = started
    If opened {
        Set case.WorkflowSessionId = ..%SessionId
        Do case.%Save()
        $$$TRACE("Case " _ case.CaseId _ " opened: " _ case.Headline)
    } Else {
        $$$TRACE("Case " _ case.CaseId _ " already open; the new failure was noted")
    }
    Quit $$$OK
}

Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, completionkey As %String) As %Status
{
    Quit $$$OK
}

}
