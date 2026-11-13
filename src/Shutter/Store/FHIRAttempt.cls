/// The one-dispatch fence of a FHIR update, and nothing else: one row per approval, unsent until the moment before the
/// request leaves, sent from then on. A sent row is never sent again, whatever the answer was. After Open, every change
/// is one SQL UPDATE followed by a reload, because an object save after a SQL update would write the old state back.
Class Shutter.Store.FHIRAttempt Extends (%Persistent, %JSON.Adaptor)
{

Property ApprovalId As %String(%JSONFIELDNAME = "approvalId", MAXLEN = 20) [ Required ];

Index ApprovalIdx On ApprovalId [ Unique ];

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property PlanId As %String(%JSONFIELDNAME = "planId", MAXLEN = 20);

Property BindingId As %String(%JSONFIELDNAME = "bindingId", MAXLEN = 20);

/// The Shutter.Store.ExecutionAttempt row written for this fence row; one at most.
Property ExecutionAttemptId As %String(%JSONFIELDNAME = "executionAttemptId", MAXLEN = 20);

Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 8, VALUELIST = ",unsent,sent");

/// The ETag the update is conditional on, verbatim.
Property ExpectedEtag As %String(%JSONFIELDNAME = "expectedEtag", MAXLEN = 200);

Property BodyDigest As %String(%JSONFIELDNAME = "bodyDigest", MAXLEN = 80);

Property OperationId As %String(%JSONFIELDNAME = "operationId", MAXLEN = 32);

Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 30);

Property SentAt As %String(%JSONFIELDNAME = "sentAt", MAXLEN = 30);

Property AnsweredAt As %String(%JSONFIELDNAME = "answeredAt", MAXLEN = 30);

Property HttpStatus As %Integer(%JSONFIELDNAME = "httpStatus");

/// applied, version_conflict, refused, uncertain or error; empty while no answer is recorded.
Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 32);

Property ResponseEtag As %String(%JSONFIELDNAME = "responseEtag", MAXLEN = 200);

Property ResponseLocation As %String(%JSONFIELDNAME = "responseLocation", MAXLEN = 500);

Property Diagnostics As %String(%JSONFIELDNAME = "diagnostics", MAXLEN = 400);

/// The fence row of the binding's approval: inserted unsent, or the existing row with <var>created</var> = 0.
ClassMethod Open(case As Shutter.Store.Case, binding As Shutter.Store.FHIRBinding, Output a As Shutter.Store.FHIRAttempt, Output created As %Boolean) As %Status
{
    Set a = "", created = 0
    If '$ISOBJECT(case) || (case.%Id() = "") Quit $$$ERROR($$$GeneralError, "The fence needs a saved case")
    If '$ISOBJECT(binding) || (binding.%Id() = "") Quit $$$ERROR($$$GeneralError, "The fence needs a sealed binding")
    If binding.CaseGetObjectId() '= case.%Id() Quit $$$ERROR($$$GeneralError, "The binding is another case's")
    If binding.ApprovalId = "" Quit $$$ERROR($$$GeneralError, "The binding is tied to no approval")
    Set a = ..ForApproval(binding.ApprovalId)
    If '$ISOBJECT(a) {
        Set a = ..%New()
        Do a.CaseSetObjectId(case.%Id())
        Set a.ApprovalId = binding.ApprovalId, a.PlanId = binding.PlanId, a.BindingId = binding.%Id(), a.State = "unsent"
        Set a.ExpectedEtag = binding.ExpectedEtag, a.BodyDigest = binding.ApprovedBodyDigest, a.OperationId = binding.OperationId
        Set a.CreatedAt = ##class(Shutter.Util.Time).NowUTC()
        Set sc = a.%Save()
        If $$$ISOK(sc) { Set created = 1  Quit $$$OK }
        // Another job inserted the approval's row between the look and the save: that row is the fence.
        Set a = ..ForApproval(binding.ApprovalId)
        If '$ISOBJECT(a) Quit sc
    }
    If a.BindingId '= binding.%Id() {
        Set a = ""
        Quit $$$ERROR($$$GeneralError, "The approval's fence row belongs to another binding")
    }
    Quit $$$OK
}

/// Unsent to sent, once. True only when this call changed the row; a row already sent answers false.
Method MarkSent() As %Boolean
{
    Set id = ..%Id()
    If id = "" Quit 0
    Set changed = 0
    TSTART
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "UPDATE Shutter_Store.FHIRAttempt SET State = 'sent', SentAt = ? WHERE ID = ? AND State = 'unsent'", ##class(Shutter.Util.Time).NowUTC(), id)
        Set changed = (rs.%SQLCODE = 0) && (rs.%ROWCOUNT = 1)
    } Catch ex {
        Set changed = 0
    }
    If changed { TCOMMIT } Else { TROLLBACK 1 }
    Do ..%Reload()
    Quit changed
}

/// Records the receiver's answer on a sent row. On an unsent row it changes nothing and answers OK. The state is not
/// touched: a sent row stays sent. Diagnostics are cut to their length; an ETag or a Location longer than its column
/// is recorded as empty, because a cut one would read as another version.
Method Answer(httpStatus As %Integer, outcome As %String, etag As %String, location As %String, diagnostics As %String) As %Status
{
    Set id = ..%Id()
    If id = "" Quit $$$ERROR($$$GeneralError, "The fence row is not saved")
    // Diagnostics is a reserved word in SQL, so the column is named in quotes.
    Set etag = $SELECT($LENGTH(etag) > 200: "", 1: etag), location = $SELECT($LENGTH(location) > 500: "", 1: location)
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "UPDATE Shutter_Store.FHIRAttempt SET HttpStatus = ?, Outcome = ?, ResponseEtag = ?, ResponseLocation = ?, ""Diagnostics"" = ?, AnsweredAt = ? WHERE ID = ? AND State = 'sent'", +httpStatus, $EXTRACT(outcome, 1, 32), etag, location, $EXTRACT(diagnostics, 1, 400), ##class(Shutter.Util.Time).NowUTC(), id)
    Do ..%Reload()
    If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "SQLCODE " _ rs.%SQLCODE _ ": " _ rs.%Message)
    Quit $$$OK
}

/// Names the ExecutionAttempt row written for this fence row.
Method SetExecutionAttempt(id As %String) As %Status
{
    Set own = ..%Id()
    If own = "" Quit $$$ERROR($$$GeneralError, "The fence row is not saved")
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "UPDATE Shutter_Store.FHIRAttempt SET ExecutionAttemptId = ? WHERE ID = ?", id, own)
    Do ..%Reload()
    If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "SQLCODE " _ rs.%SQLCODE _ ": " _ rs.%Message)
    Quit $$$OK
}

/// The fence row of an approval, or "".
ClassMethod ForApproval(approvalId As %String) As Shutter.Store.FHIRAttempt
{
    If approvalId = "" Quit ""
    Quit ..ApprovalIdxOpen(approvalId)
}

/// The OperationId of every sent row of the case, oldest first.
ClassMethod SentOperationIds(case As Shutter.Store.Case) As %DynamicArray
{
    Set out = []
    If '$ISOBJECT(case) || (case.%Id() = "") Quit out
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT OperationId FROM Shutter_Store.FHIRAttempt WHERE ""Case"" = ? AND State = 'sent' ORDER BY ID", case.%Id())
    While rs.%Next() { If rs.%Get("OperationId") '= "" Do out.%Push(rs.%Get("OperationId")) }
    Quit out
}

/// True when a sent row of the case was conditional on this same ETag and its outcome is empty, uncertain or applied:
/// a write that may yet land on this version. The ETags are compared as strings, exactly.
ClassMethod UnresolvedAt(case As Shutter.Store.Case, etag As %String) As %Boolean
{
    If '$ISOBJECT(case) || (case.%Id() = "") || (etag = "") Quit 0
    Set found = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ExpectedEtag, Outcome FROM Shutter_Store.FHIRAttempt WHERE ""Case"" = ? AND State = 'sent'", case.%Id())
    While rs.%Next() {
        Continue:rs.%Get("ExpectedEtag")'=etag
        Set outcome = rs.%Get("Outcome")
        If (outcome = "") || (outcome = "uncertain") || (outcome = "applied") Set found = 1
    }
    Quit found
}

Storage Default
{
<Data name="FHIRAttemptDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>ApprovalId</Value>
</Value>
<Value name="3">
<Value>Case</Value>
</Value>
<Value name="4">
<Value>PlanId</Value>
</Value>
<Value name="5">
<Value>BindingId</Value>
</Value>
<Value name="6">
<Value>ExecutionAttemptId</Value>
</Value>
<Value name="7">
<Value>State</Value>
</Value>
<Value name="8">
<Value>ExpectedEtag</Value>
</Value>
<Value name="9">
<Value>BodyDigest</Value>
</Value>
<Value name="10">
<Value>OperationId</Value>
</Value>
<Value name="11">
<Value>CreatedAt</Value>
</Value>
<Value name="12">
<Value>SentAt</Value>
</Value>
<Value name="13">
<Value>AnsweredAt</Value>
</Value>
<Value name="14">
<Value>HttpStatus</Value>
</Value>
<Value name="15">
<Value>Outcome</Value>
</Value>
<Value name="16">
<Value>ResponseEtag</Value>
</Value>
<Value name="17">
<Value>ResponseLocation</Value>
</Value>
<Value name="18">
<Value>Diagnostics</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.FHIRAttemptD</DataLocation>
<DefaultData>FHIRAttemptDefaultData</DefaultData>
<IdLocation>^Shutter.Store.FHIRAttemptD</IdLocation>
<IndexLocation>^Shutter.Store.FHIRAttemptI</IndexLocation>
<StreamLocation>^Shutter.Store.FHIRAttemptS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
