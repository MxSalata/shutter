/// A board member's structured findings on a snapshot, kept verbatim beside the plan so that
/// disagreements stay visible.
Class Shutter.Store.Finding Extends (%Persistent, %JSON.Adaptor)
{

Property Run As Shutter.Store.AgentRun(%JSONFIELDNAME = "runId", %JSONREFERENCE = "ID");

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Snapshot As Shutter.Store.Snapshot(%JSONFIELDNAME = "snapshotId", %JSONREFERENCE = "ID");

Property Role As %String(%JSONFIELDNAME = "role", MAXLEN = 32);

Property MemberCode As %String(%JSONFIELDNAME = "memberCode", MAXLEN = 32);

/// resend, reconcile, superseded, more_evidence, escalate; or "" when the member proposes none.
Property Disposition As %String(%JSONFIELDNAME = "disposition", MAXLEN = 32);

Property Confidence As %Numeric(%JSONFIELDNAME = "confidence", SCALE = 3);

Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = 4000);

/// The whole structured result, as submitted and validated.
Property Json As %String(%JSONFIELDNAME = "findings", MAXLEN = "");

Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 30);

/// Store validated findings for a run.
ClassMethod Create(run As Shutter.Store.AgentRun, findings As %DynamicObject, Output finding As Shutter.Store.Finding) As %Status
{
    Set finding = ..%New()
    // The case by id from the run's reference, not swizzled, as Snapshot.Begin does: a save of the finding never
    // writes the case whole.
    Do finding.CaseSetObjectId(run.CaseGetObjectId())
    Set finding.Run = run, finding.Snapshot = run.Snapshot
    Set finding.Role = run.Role, finding.MemberCode = run.MemberCode
    Set finding.Disposition = ##class(Shutter.Util.Json).Str(findings, "disposition")
    Set finding.Confidence = +##class(Shutter.Util.Json).Str(findings, "confidence", 0)
    Set finding.Summary = $EXTRACT(##class(Shutter.Util.Json).Str(findings, "summary"), 1, 4000)
    Set finding.Json = findings.%ToJSON()
    Set finding.CreatedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit finding.%Save()
}

/// The findings of a case for a snapshot, as a dynamic array ordered by member.
ClassMethod ForSnapshot(snapshot As Shutter.Store.Snapshot) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Finding WHERE Snapshot = ? ORDER BY ID", snapshot.%Id())
    While rs.%Next() {
        Set f = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(f)
        Set obj = ##class(%DynamicObject).%FromJSON(f.Json)
        Set obj."member_code" = f.MemberCode, obj.role = f.Role, obj."finding_id" = f.%Id()
        Do out.%Push(obj)
    }
    Quit out
}

Storage Default
{
<Data name="FindingDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Run</Value>
</Value>
<Value name="3">
<Value>Case</Value>
</Value>
<Value name="4">
<Value>Snapshot</Value>
</Value>
<Value name="5">
<Value>Role</Value>
</Value>
<Value name="6">
<Value>MemberCode</Value>
</Value>
<Value name="7">
<Value>Disposition</Value>
</Value>
<Value name="8">
<Value>Confidence</Value>
</Value>
<Value name="9">
<Value>Summary</Value>
</Value>
<Value name="10">
<Value>Json</Value>
</Value>
<Value name="11">
<Value>CreatedAt</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.FindingD</DataLocation>
<DefaultData>FindingDefaultData</DefaultData>
<IdLocation>^Shutter.Store.FindingD</IdLocation>
<IndexLocation>^Shutter.Store.FindingI</IndexLocation>
<StreamLocation>^Shutter.Store.FindingS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
