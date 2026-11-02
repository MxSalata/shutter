/// The terminal tool of the coordinator and the single investigator: the plan arrives as a typed
/// object, is validated and kept for the runner. One instance per run.
Class Shutter.Tools.SubmitPlan Extends %AI.Tool
{

Property Name As %String [ InitialExpression = "Submit plan" ];

Property Description As %String(MAXLEN = "") [ InitialExpression = "Submit the one plan for the case, once, when it is decided" ];

/// The case this run is for; a submission for another case is refused.
Property CaseId As %String(MAXLEN = 32);

/// What the result may cite (v1.35): the keys of the evidence the run was given, and the keys one level down, comma
/// separated; the runner sets them from the request's context. "" leaves the evidence_refs unchecked.
Property CiteIds As %String(MAXLEN = "");

/// The accepted plan as JSON, or "".
Property Result As %String(MAXLEN = "");

Property Submissions As %Integer [ InitialExpression = 0 ];

Property LastError As %String(MAXLEN = 2000);

/// Submit the one plan for the case, exactly once, when it is decided. The disposition is one of resend, reconcile, superseded, more_evidence or escalate. action.type is resend (the only write Shutter makes: the case's own operation, unchanged, with expected_version set to the receiver's current version), reconcile (the receipt shows it committed; write nothing) or none (for superseded, more_evidence and escalate). preconditions say what must still hold at dispatch; evidence_refs list the snapshot items the plan rests on; disagreements keep every specialist view the plan does not follow, as {member, said, why_kept}. If the submission is refused, fix the fields it names and submit again.
/// caseId: the case identifier the plan is for
/// plan: the plan object
Method SubmitPlan(caseId As %String, plan As Shutter.Schema.Plan) As %DynamicObject
{
    Set json = ##class(Shutter.Schema.Argument).AsJSON(.plan, .err)
    If err '= "" Set ..LastError = err Return {"accepted": false, "error": (err)}
    If (..CaseId '= "") && (caseId '= ..CaseId) Set ..LastError = "wrong case" Return {"accepted": false, "error": ("This run is for case " _ ..CaseId)}
    Set problems = ##class(Shutter.Schema.Plan).Check(json, ..CiteIds)
    If problems.%Size() > 0 Set ..LastError = problems.%ToJSON() Return {"accepted": false, "problems": (problems), "hint": "Correct the fields named and call SubmitPlan again"}
    Set ..Result = json, ..Submissions = ..Submissions + 1, ..LastError = ""
    Return {"accepted": true, "next": "Submitted. Reply with one short sentence and stop; call no other tool."}
}

}
