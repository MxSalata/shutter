/// The terminal tool of a turn of Set up the site (CONTRACTS 14.7): the Set-up guide agent's turn arrives as a typed
/// object, so the model sees the schema; the tool checks its shape, then the core's own checks against the stored turn
/// (Shutter.Util.ProfileSetup.CheckStored: the fields the agent may draft, their values, the person's quoted words, the
/// effects check and the validator on a copy), and keeps the accepted JSON for the runner. A refusal names the field, so
/// the agent can correct it within its turns. It writes nothing: no profile, no draft. One instance per run.
Class Shutter.Tools.SubmitSetupTurn Extends %AI.Tool
{

Property Name As %String [ InitialExpression = "Submit setup turn" ];

Property Description As %String(MAXLEN = "") [ InitialExpression = "Submit what you read from the person's words about the receiver, once, when it is complete" ];

/// The turn this run is for (ST-nnnnnn); a submission for another is refused.
Property CaseId As %String(MAXLEN = 32);

/// The accepted turn as JSON, or "".
Property Result As %String(MAXLEN = "");

Property Submissions As %Integer [ InitialExpression = 0 ];

Property LastError As %String(MAXLEN = 2000);

/// Submit your turn, exactly once, when it is complete. say is what you tell the person in plain words, at most 800 characters; proposals lists at most three drafted answers, each {field, receiver, to, quote}, only for fields the request marks as yours, with quote copied exactly from what the person typed; ask names the next unanswered question as {field, receiver}, or is left out. If the submission is refused, correct the field it names and call it again; when the words do not say, draft nothing and ask.
/// caseId: the turn's id as the request gives it, for example ST-000012
/// turn: the turn object
Method SubmitSetupTurn(caseId As %String, turn As Shutter.Schema.SetupTurn) As %DynamicObject
{
    Set json = ##class(Shutter.Schema.Argument).AsJSON(.turn, .err)
    If err '= "" Set ..LastError = err Return {"accepted": false, "error": (err)}
    If (..CaseId '= "") && (caseId '= ..CaseId) Set ..LastError = "wrong turn" Return {"accepted": false, "error": ("This run is for turn " _ ..CaseId)}
    Set problems = ##class(Shutter.Schema.SetupTurn).Check(json)
    If problems.%Size() > 0 Set ..LastError = problems.%ToJSON() Return {"accepted": false, "problems": (problems), "hint": "Correct the fields named and call SubmitSetupTurn again"}
    Set o = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '##class(Shutter.Util.ProfileSetup).CheckStored(..CaseId, o, .problem, .accepted) {
        Set ..LastError = problem
        Return {"accepted": false, "problems": [(problem)], "hint": "Correct what is named and call SubmitSetupTurn again. A field marked person is never yours to draft: leave it out and ask about it instead."}
    }
    Set ..Result = accepted.%ToJSON(), ..Submissions = ..Submissions + 1, ..LastError = ""
    Return {"accepted": true, "next": "Submitted. Reply with one short sentence and stop; call no other tool."}
}

}
