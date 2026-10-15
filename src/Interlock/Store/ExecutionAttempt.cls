/// One dispatch of an approved plan to the receiver: the conditional write with the stable
/// operation key, and what came back.
Class Interlock.Store.ExecutionAttempt Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Interlock.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Plan As Interlock.Store.Plan(%JSONFIELDNAME = "planId", %JSONREFERENCE = "ID");

Property Approval As Interlock.Store.Approval(%JSONFIELDNAME = "approvalId", %JSONREFERENCE = "ID");

Property At As %String(%JSONFIELDNAME = "at", MAXLEN = 30);

Property OperationKey As %String(%JSONFIELDNAME = "operationKey", MAXLEN = 400);

Property ExpectedVersion As %Integer(%JSONFIELDNAME = "expectedVersion");

Property HttpStatus As %Integer(%JSONFIELDNAME = "httpStatus");

/// applied, already_committed, version_conflict, refused, uncertain, error.
Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 32);

Property ReceiptJSON As %String(%JSONFIELDNAME = "receipt", MAXLEN = "");

Property ResponseJSON As %String(%JSONFIELDNAME = "response", MAXLEN = "");

Property Error As %String(%JSONFIELDNAME = "error", MAXLEN = 2000);

ClassMethod Create(case As Interlock.Store.Case, plan As Interlock.Store.Plan, approval As Interlock.Store.Approval, httpStatus As %Integer, outcome As %String, response As %DynamicObject, error As %String, Output e As Interlock.Store.ExecutionAttempt) As %Status
{
    Set e = ..%New()
    Set e.Case = case, e.Plan = plan
    If $ISOBJECT(approval) Set e.Approval = approval
    Set e.At = ##class(Interlock.Util.Time).NowUTC()
    Set e.OperationKey = plan.OperationKey, e.ExpectedVersion = plan.ExpectedVersion
    Set e.HttpStatus = httpStatus, e.Outcome = outcome, e.Error = $EXTRACT(error, 1, 2000)
    Set e.ResponseJSON = ##class(Interlock.Util.Json).Text(response)
    If $ISOBJECT(response) && $ISOBJECT(response.%Get("receipt")) Set e.ReceiptJSON = response.%Get("receipt").%ToJSON()
    Quit e.%Save()
}

}
