/// The terminal tool of a question's answering run, for the Explain agent and each board member: the answer arrives as a
/// typed object, so the model sees the schema, the tool checks its shape and keeps the accepted JSON for the runner. One instance per run.
Class Shutter.Tools.SubmitAnswer Extends %AI.Tool
{

Property Name As %String [ InitialExpression = "Submit answer" ];

Property Description As %String(MAXLEN = "") [ InitialExpression = "Submit your answer to the question about this case, once, when it is complete" ];

/// The case this run is for; a submission for another case is refused.
Property CaseId As %String(MAXLEN = 32);

/// The accepted answer as JSON, or "".
Property Result As %String(MAXLEN = "");

Property Submissions As %Integer [ InitialExpression = 0 ];

Property LastError As %String(MAXLEN = 2000);

/// Submit your answer to the question, exactly once, when it is complete. answer is plain words for a person who is not an interface engineer, at most 1200 characters; cites lists the evidence ids (message, history[2], ...) and fact ids (W1, W2, ...) it rests on; confidence is high, medium or low. If the submission is refused, fix the fields it names and submit again.
/// caseId: the case the question is about, for example C-000012
/// answer: the answer object
Method SubmitAnswer(caseId As %String, answer As Shutter.Schema.Answer) As %DynamicObject
{
    Set json = ##class(Shutter.Schema.Argument).AsJSON(.answer, .err)
    If err '= "" Set ..LastError = err Return {"accepted": false, "error": (err)}
    If (..CaseId '= "") && (caseId '= ..CaseId) Set ..LastError = "wrong case" Return {"accepted": false, "error": ("This run is for case " _ ..CaseId)}
    Set problems = ##class(Shutter.Schema.Answer).Check(json)
    If problems.%Size() > 0 Set ..LastError = problems.%ToJSON() Return {"accepted": false, "problems": (problems), "hint": "Correct the fields named and call SubmitAnswer again"}
    Set ..Result = json, ..Submissions = ..Submissions + 1, ..LastError = ""
    Return {"accepted": true, "next": "Submitted. Reply with one short sentence and stop; call no other tool."}
}

}
