/// The deterministic gate's verdict on a plan at one stage: proposal, approval or dispatch. Each
/// check is pass, block or unknown with a reason code; the outcome is the worst of them.
Class Shutter.Store.GateDecision Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Plan As Shutter.Store.Plan(%JSONFIELDNAME = "planId", %JSONREFERENCE = "ID");

Property Stage As %String(%JSONFIELDNAME = "stage", MAXLEN = 16, VALUELIST = ",proposal,approval,dispatch");

Property PolicyVersion As %String(%JSONFIELDNAME = "policyVersion", MAXLEN = 32);

Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 16, VALUELIST = ",pass,block,unknown");

/// [{"check": "ordering", "result": "block", "reason_code": "SUPERSEDED_BY_LATER_EVENT", "detail": "..."}]
Property ChecksJSON As %String(%JSONFIELDNAME = "checks", MAXLEN = "");

Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = 2000);

Property At As %String(%JSONFIELDNAME = "at", MAXLEN = 30);

ClassMethod Create(case As Shutter.Store.Case, plan As Shutter.Store.Plan, stage As %String, policyVersion As %String, outcome As %String, checks As %DynamicArray, summary As %String, Output d As Shutter.Store.GateDecision) As %Status
{
    Set d = ..%New()
    // By id, not the caller's copy, as Snapshot.Begin does: a save of the decision never writes the case whole.
    Do d.CaseSetObjectId(case.%Id())
    Set d.Plan = plan, d.Stage = stage, d.PolicyVersion = policyVersion
    Set d.Outcome = outcome, d.ChecksJSON = checks.%ToJSON(), d.Summary = $EXTRACT(summary, 1, 2000)
    Set d.At = ##class(Shutter.Util.Time).NowUTC()
    Quit d.%Save()
}

Storage Default
{
<Data name="GateDecisionDefaultData">
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
<Value>Stage</Value>
</Value>
<Value name="5">
<Value>PolicyVersion</Value>
</Value>
<Value name="6">
<Value>Outcome</Value>
</Value>
<Value name="7">
<Value>ChecksJSON</Value>
</Value>
<Value name="8">
<Value>Summary</Value>
</Value>
<Value name="9">
<Value>At</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.GateDecisionD</DataLocation>
<DefaultData>GateDecisionDefaultData</DefaultData>
<IdLocation>^Shutter.Store.GateDecisionD</IdLocation>
<IndexLocation>^Shutter.Store.GateDecisionI</IndexLocation>
<StreamLocation>^Shutter.Store.GateDecisionS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
