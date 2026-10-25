/// One dispatch of an approved plan to the receiver: the conditional write with the stable
/// operation key, and what came back.
Class Shutter.Store.ExecutionAttempt Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Plan As Shutter.Store.Plan(%JSONFIELDNAME = "planId", %JSONREFERENCE = "ID");

Property Approval As Shutter.Store.Approval(%JSONFIELDNAME = "approvalId", %JSONREFERENCE = "ID");

Property At As %String(%JSONFIELDNAME = "at", MAXLEN = 30);

Property OperationKey As %String(%JSONFIELDNAME = "operationKey", MAXLEN = 400);

Property ExpectedVersion As %Integer(%JSONFIELDNAME = "expectedVersion");

Property HttpStatus As %Integer(%JSONFIELDNAME = "httpStatus");

/// applied, already_committed, version_conflict, refused, uncertain, error.
Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 32);

Property ReceiptJSON As %String(%JSONFIELDNAME = "receipt", MAXLEN = "");

Property ResponseJSON As %String(%JSONFIELDNAME = "response", MAXLEN = "");

Property Error As %String(%JSONFIELDNAME = "error", MAXLEN = 2000);

/// The dry run the write stood on (v1.21): the approval's bound rehearsal, or the rehearsal itself when the receiver
/// applied it instead of rolling it back.
Property Rehearsal As Shutter.Store.Rehearsal(%JSONFIELDNAME = "rehearsalId", %JSONREFERENCE = "ID");

ClassMethod Create(case As Shutter.Store.Case, plan As Shutter.Store.Plan, approval As Shutter.Store.Approval, rehearsal As Shutter.Store.Rehearsal = "", httpStatus As %Integer, outcome As %String, response As %DynamicObject, error As %String, Output e As Shutter.Store.ExecutionAttempt) As %Status
{
    Set e = ..%New()
    // By id, not the caller's copy (as Snapshot.Begin does): a save of the attempt never writes the case copy whole.
    Do e.CaseSetObjectId(case.%Id())
    Set e.Plan = plan
    If $ISOBJECT(approval) Set e.Approval = approval
    If $ISOBJECT(rehearsal) Set e.Rehearsal = rehearsal
    Set e.At = ##class(Shutter.Util.Time).NowUTC()
    Set e.OperationKey = plan.OperationKey, e.ExpectedVersion = plan.ExpectedVersion
    Set e.HttpStatus = httpStatus, e.Outcome = outcome, e.Error = $EXTRACT(error, 1, 2000)
    Set e.ResponseJSON = ##class(Shutter.Util.Json).Text(response)
    If $ISOBJECT(response) && $ISOBJECT(response.%Get("receipt")) Set e.ReceiptJSON = response.%Get("receipt").%ToJSON()
    Quit e.%Save()
}

Storage Default
{
<Data name="ExecutionAttemptDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>Plan</Value>
</Value>
<Value name="4">
<Value>Approval</Value>
</Value>
<Value name="5">
<Value>At</Value>
</Value>
<Value name="6">
<Value>OperationKey</Value>
</Value>
<Value name="7">
<Value>ExpectedVersion</Value>
</Value>
<Value name="8">
<Value>HttpStatus</Value>
</Value>
<Value name="9">
<Value>Outcome</Value>
</Value>
<Value name="10">
<Value>ReceiptJSON</Value>
</Value>
<Value name="11">
<Value>ResponseJSON</Value>
</Value>
<Value name="12">
<Value>Error</Value>
</Value>
<Value name="13">
<Value>Rehearsal</Value>
</Value>
</Data>
<DataLocation>^Shutter7581.ExecutionAt8F65D</DataLocation>
<DefaultData>ExecutionAttemptDefaultData</DefaultData>
<IdLocation>^Shutter7581.ExecutionAt8F65D</IdLocation>
<IndexLocation>^Shutter7581.ExecutionAt8F65I</IndexLocation>
<StreamLocation>^Shutter7581.ExecutionAt8F65S</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
