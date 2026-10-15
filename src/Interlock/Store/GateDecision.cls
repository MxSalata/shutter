/// The deterministic gate's verdict on a plan at one stage: proposal, approval or dispatch. Each
/// check is pass, block or unknown with a reason code; the outcome is the worst of them.
Class Interlock.Store.GateDecision Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Interlock.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Plan As Interlock.Store.Plan(%JSONFIELDNAME = "planId", %JSONREFERENCE = "ID");

Property Stage As %String(%JSONFIELDNAME = "stage", MAXLEN = 16, VALUELIST = ",proposal,approval,dispatch");

Property PolicyVersion As %String(%JSONFIELDNAME = "policyVersion", MAXLEN = 32);

Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 16, VALUELIST = ",pass,block,unknown");

/// [{"check": "ordering", "result": "block", "reason_code": "SUPERSEDED_BY_LATER_EVENT", "detail": "..."}]
Property ChecksJSON As %String(%JSONFIELDNAME = "checks", MAXLEN = "");

Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = 2000);

Property At As %String(%JSONFIELDNAME = "at", MAXLEN = 30);

ClassMethod Create(case As Interlock.Store.Case, plan As Interlock.Store.Plan, stage As %String, policyVersion As %String, outcome As %String, checks As %DynamicArray, summary As %String, Output d As Interlock.Store.GateDecision) As %Status
{
    Set d = ..%New()
    Set d.Case = case, d.Plan = plan, d.Stage = stage, d.PolicyVersion = policyVersion
    Set d.Outcome = outcome, d.ChecksJSON = checks.%ToJSON(), d.Summary = $EXTRACT(summary, 1, 2000)
    Set d.At = ##class(Interlock.Util.Time).NowUTC()
    Quit d.%Save()
}

}
