/// The terminal tool of the coordinator in a board question: the synthesis arrives as a typed object, so the model sees
/// the schema; the tool checks its shape, refuses a setting or change that is not one of the question's facts, and keeps
/// the accepted JSON for the runner. One instance per run.
Class Shutter.Tools.SubmitBoardAnswer Extends %AI.Tool
{

Property Name As %String [ InitialExpression = "Submit board answer" ];

Property Description As %String(MAXLEN = "") [ InitialExpression = "Submit the board's answer to the question about this case, once, when it is complete" ];

/// The case this run is for; a submission for another case is refused.
Property CaseId As %String(MAXLEN = 32);

/// The ids of the question's whatif.facts, comma separated; the runner sets them from the request's context.
Property FactIds As %String(MAXLEN = 2000);

/// What may be cited: the case section's evidence ids and the question's fact ids, comma separated; the runner sets them
/// from the request's context. Empty means any (the core checks again).
Property CiteIds As %String(MAXLEN = "");

/// The accepted answer as JSON, or "".
Property Result As %String(MAXLEN = "");

Property Submissions As %Integer [ InitialExpression = 0 ];

Property LastError As %String(MAXLEN = 2000);

/// Submit the board's answer to the question, exactly once, when it is complete. answer is the synthesis in plain words, at most 1200 characters; perspectives gives each specialist's view, disagreements kept; setting, under_alternative and suggested_change, when the question turns on a site profile setting, each name one fact id from whatif.facts and nothing else (suggested_change with why); cites lists the evidence ids and fact ids used; confidence is high, medium or low. If the submission is refused, fix the fields it names and submit again.
/// caseId: the case the question is about, for example C-000012
/// answer: the board's answer object
Method SubmitBoardAnswer(caseId As %String, answer As Shutter.Schema.BoardAnswer) As %DynamicObject
{
    Set json = ##class(Shutter.Schema.Argument).AsJSON(.answer, .err)
    If err '= "" Set ..LastError = err Return {"accepted": false, "error": (err)}
    If (..CaseId '= "") && (caseId '= ..CaseId) Set ..LastError = "wrong case" Return {"accepted": false, "error": ("This run is for case " _ ..CaseId)}
    Set problems = ##class(Shutter.Schema.BoardAnswer).Check(json, ..FactIds, ..CiteIds)
    If problems.%Size() > 0 Set ..LastError = problems.%ToJSON() Return {"accepted": false, "problems": (problems), "hint": "Correct the fields named and call SubmitBoardAnswer again"}
    Set ..Result = json, ..Submissions = ..Submissions + 1, ..LastError = ""
    Return {"accepted": true, "next": "Submitted. Reply with one short sentence and stop; call no other tool."}
}

}
