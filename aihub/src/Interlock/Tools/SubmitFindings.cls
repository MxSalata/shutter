/// The terminal tool of a specialist: the findings arrive as a typed object, so the model sees the
/// schema, the tool validates them and keeps the accepted JSON for the runner. One instance per run.
Class Interlock.Tools.SubmitFindings Extends %AI.Tool
{

Property Name As %String [ InitialExpression = "Submit findings" ];

Property Description As %String(MAXLEN = "") [ InitialExpression = "Submit the findings for the case, once, when the review is complete" ];

/// The case this run is for; a submission for another case is refused.
Property CaseId As %String(MAXLEN = 32);

/// The accepted findings as JSON, or "".
Property Result As %String(MAXLEN = "");

Property Submissions As %Integer [ InitialExpression = 0 ];

Property LastError As %String(MAXLEN = 2000);

/// Submit your findings for the case, exactly once, when the review is complete. The disposition is one of resend, reconcile, superseded, more_evidence or escalate; confidence is 0 to 1; violations lists the contract clauses the message or the situation breaks (empty when none); unknowns lists what could not be established; evidence_refs lists the snapshot items the findings rest on (message, validation, ward_state, receipt, timeline, route, error). If the submission is refused, fix the fields it names and submit again.
/// caseId: the case identifier the findings are for
/// findings: the findings object
Method SubmitFindings(caseId As %String, findings As Interlock.Schema.Findings) As %DynamicObject
{
    Set json = ##class(Interlock.Tools.SubmitPlan).AsJSON(.findings, .err)
    If err '= "" Set ..LastError = err Return {"accepted": false, "error": (err)}
    If (..CaseId '= "") && (caseId '= ..CaseId) Set ..LastError = "wrong case" Return {"accepted": false, "error": ("This run is for case " _ ..CaseId)}
    Set problems = ##class(Interlock.Schema.Findings).Check(json)
    If problems.%Size() > 0 Set ..LastError = problems.%ToJSON() Return {"accepted": false, "problems": (problems), "hint": "Correct the fields named and call SubmitFindings again"}
    Set ..Result = json, ..Submissions = ..Submissions + 1, ..LastError = ""
    Return {"accepted": true, "next": "Submitted. Reply with one short sentence and stop; call no other tool."}
}

}
