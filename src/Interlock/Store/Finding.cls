/// A board member's structured findings on a snapshot, kept verbatim beside the plan so that
/// disagreements stay visible.
Class Interlock.Store.Finding Extends (%Persistent, %JSON.Adaptor)
{

Property Run As Interlock.Store.AgentRun(%JSONFIELDNAME = "runId", %JSONREFERENCE = "ID");

Property Case As Interlock.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Snapshot As Interlock.Store.Snapshot(%JSONFIELDNAME = "snapshotId", %JSONREFERENCE = "ID");

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
ClassMethod Create(run As Interlock.Store.AgentRun, findings As %DynamicObject, Output finding As Interlock.Store.Finding) As %Status
{
    Set finding = ..%New()
    Set finding.Run = run, finding.Case = run.Case, finding.Snapshot = run.Snapshot
    Set finding.Role = run.Role, finding.MemberCode = run.MemberCode
    Set finding.Disposition = ##class(Interlock.Util.Json).Str(findings, "disposition")
    Set finding.Confidence = +##class(Interlock.Util.Json).Str(findings, "confidence", 0)
    Set finding.Summary = $EXTRACT(##class(Interlock.Util.Json).Str(findings, "summary"), 1, 4000)
    Set finding.Json = findings.%ToJSON()
    Set finding.CreatedAt = ##class(Interlock.Util.Time).NowUTC()
    Quit finding.%Save()
}

/// The findings of a case for a snapshot, as a dynamic array ordered by member.
ClassMethod ForSnapshot(snapshot As Interlock.Store.Snapshot) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Interlock_Store.Finding WHERE Snapshot = ? ORDER BY ID", snapshot.%Id())
    While rs.%Next() {
        Set f = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(f)
        Set obj = ##class(%DynamicObject).%FromJSON(f.Json)
        Set obj."member_code" = f.MemberCode, obj.role = f.Role, obj."finding_id" = f.%Id()
        Do out.%Push(obj)
    }
    Quit out
}

}
