/// The terminal tool of the production review's agent: the ranking arrives as a typed object, so the model sees the
/// schema, the tool checks its shape and keeps the accepted JSON for the runner. One instance per run. CaseId holds
/// the review id: the runner sets it from the request's correlation key, as it does for a case.
Class Shutter.Tools.SubmitReview Extends %AI.Tool
{

Property Name As %String [ InitialExpression = "Submit review" ];

Property Description As %String(MAXLEN = "") [ InitialExpression = "Submit the ranking and the explanations for the production review, once, when they are complete" ];

/// The review this run is for; a submission for another review is refused.
Property CaseId As %String(MAXLEN = 32);

/// The accepted review as JSON, or "".
Property Result As %String(MAXLEN = "");

Property Submissions As %Integer [ InitialExpression = 0 ];

Property LastError As %String(MAXLEN = 2000);

/// Submit your ranking of the review's findings, exactly once, when it is complete. ranking names every finding id of the review once, with its rank (1 first; the ranks run 1 to the number of findings without a gap) and an explanation of one or two sentences against the case history, which says "consistent with" and names counts, never "caused"; confidence_note says what limits it. A finding keeps its severity, its confidence, its counts and its values: a lower severity tier is never ranked above a higher one. summary is the review in a few sentences; unknowns lists what could not be judged. If the submission is refused, fix the fields it names and submit again.
/// reviewId: the review identifier the ranking is for, for example PR-000001
/// review: the review object
Method SubmitReview(reviewId As %String, review As Shutter.Schema.Review) As %DynamicObject
{
    Set json = ##class(Shutter.Schema.Argument).AsJSON(.review, .err)
    If err '= "" Set ..LastError = err Return {"accepted": false, "error": (err)}
    If (..CaseId '= "") && (reviewId '= ..CaseId) Set ..LastError = "wrong review" Return {"accepted": false, "error": ("This run is for review " _ ..CaseId)}
    Set problems = ##class(Shutter.Schema.Review).Check(json)
    If problems.%Size() > 0 Set ..LastError = problems.%ToJSON() Return {"accepted": false, "problems": (problems), "hint": "Correct the fields named and call SubmitReview again"}
    Set ..Result = json, ..Submissions = ..Submissions + 1, ..LastError = ""
    Return {"accepted": true, "next": "Submitted. Reply with one short sentence and stop; call no other tool."}
}

}
