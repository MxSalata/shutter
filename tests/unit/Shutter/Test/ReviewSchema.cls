/// The production review's result shape (Shutter.Schema.Review.Check) and its terminal tool (Shutter.Tools.SubmitReview):
/// a ranking that names every finding once with the ranks 1 to n and an explanation each is accepted; a repeated id, a
/// rank outside 1 to n or given twice, a missing or overlong explanation and a ranking that is not an array are refused
/// by name; the tool refuses another review id and keeps the accepted JSON. Both classes belong to the aihub module
/// (they extend %JSON.Adaptor and %AI.Tool there), so each test runs only where its class is compiled and passes
/// trivially, saying so, on an instance with the core alone. Nothing is written.
Class Shutter.Test.ReviewSchema Extends %UnitTest.TestCase
{

/// Whether the aihub class is compiled on this instance; when it is not, the test says so and passes.
Method Present(class As %String) As %Boolean
{
    If ##class(%Dictionary.CompiledClass).%ExistsId(class) Quit 1
    Do $$$AssertTrue(1, class _ " is not compiled on this instance (the aihub module is not loaded): nothing to check here")
    Quit 0
}

/// The problems the schema finds with a review object, through the class name, since the class is the aihub module's.
Method Problems(review As %DynamicObject) As %DynamicArray
{
    Quit $CLASSMETHOD("Shutter.Schema.Review", "Check", review.%ToJSON())
}

/// A ranking of three findings in another order than F1, F2, F3, with the optional fields filled.
Method GoodReview() As %DynamicObject
{
    Quit {
        "ranking": [
            {"finding_id": "F2", "rank": 1, "code": "RETRY_FOREVER", "item": "Downstream Out", "setting": "FailureTimeout", "explanation": "FailureTimeout -1 on Downstream Out is consistent with the 3 unique cases of the window, all with failure kind unavailable.", "confidence_note": "No mechanism was traced."},
            {"finding_id": "F1", "rank": 2, "code": "NO_ALERT_CONSUMER", "item": "", "setting": "", "explanation": "No alert consumer exists, so the alerts the items would raise reach the event log only."},
            {"finding_id": "F3", "rank": 3, "code": "PURGE_LONG", "item": "", "setting": "NumberOfDaysToKeep", "explanation": "The purge task keeps 30 days, within the site's retention; no cases bear on it.", "confidence_note": "Latent."}
        ],
        "summary": "Two findings are consistent with the window's cases; the purge finding is latent.",
        "unknowns": ["Whether an external monitor reads the event log."]
    }
}

/// The ranking's entry <var>i</var> (0-based) of a review, the same object the review holds.
Method Entry(review As %DynamicObject, i As %Integer) As %DynamicObject
{
    Quit review.ranking.%Get(i)
}

/// <var>n</var> characters of <var>c</var>.
Method Repeat(c As %String, n As %Integer) As %String
{
    Quit $TRANSLATE($JUSTIFY("", n), " ", c)
}

Method TestGoodRankingIsAccepted()
{
    If '..Present("Shutter.Schema.Review") Quit
    Set problems = ..Problems(..GoodReview())
    Do $$$AssertEquals(problems.%Size(), 0, "a ranking of every finding once, ranks 1 to 3, an explanation each, is accepted: " _ problems.%ToJSON())
    Set minimal = {"ranking": [{"finding_id": "F1", "rank": 1, "code": "PURGE_MISSING", "item": "", "setting": "", "explanation": "One finding, ranked first."}]}
    Do $$$AssertEquals(..Problems(minimal).%Size(), 0, "one finding with no summary and no unknowns is accepted too")
    // Since v1.22 an entry names the finding's code (item and setting may be empty): a ranking is matched by them on replay.
    Set nocode = {"ranking": [{"finding_id": "F1", "rank": 1, "explanation": "No code."}]}
    Do $$$AssertTrue(..Problems(nocode).%ToJSON() [ "code", "an entry without the finding's code is refused: " _ ..Problems(nocode).%ToJSON())
}

Method TestRepeatedIdAndRanksOutOfRangeAreRefused()
{
    If '..Present("Shutter.Schema.Review") Quit
    Set review = ..GoodReview(), e = ..Entry(review, 2)
    Set e."finding_id" = "F2"
    Set problems = ..Problems(review)
    Do $$$AssertTrue(problems.%ToJSON() [ "F2 is ranked more than once", "a finding id ranked twice is named: " _ problems.%ToJSON())
    Set review = ..GoodReview(), e = ..Entry(review, 2)
    Set e.rank = 5
    Set problems = ..Problems(review)
    Do $$$AssertTrue(problems.%ToJSON() [ "integer from 1 to 3", "a rank beyond the number of findings is refused: " _ problems.%ToJSON())
    Set review = ..GoodReview(), e = ..Entry(review, 2)
    Set e.rank = 1
    Set problems = ..Problems(review)
    Do $$$AssertTrue(problems.%ToJSON() [ "rank 1 is given twice", "a rank given twice is refused, which is what a gap looks like with n entries: " _ problems.%ToJSON())
    Set review = ..GoodReview(), e = ..Entry(review, 0)
    Set e.rank = 0
    Do $$$AssertTrue(..Problems(review).%ToJSON() [ "integer from 1 to 3", "rank 0 is refused")
    Set review = ..GoodReview(), e = ..Entry(review, 0)
    Set e.rank = 1.5
    Do $$$AssertTrue(..Problems(review).%ToJSON() [ "integer from 1 to 3", "a fraction is refused")
}

Method TestExplanationsAreRequiredAndBounded()
{
    If '..Present("Shutter.Schema.Review") Quit
    Set review = ..GoodReview(), e = ..Entry(review, 1)
    Do e.%Remove("explanation")
    Set problems = ..Problems(review)
    Do $$$AssertTrue(problems.%ToJSON() [ "needs an explanation for F1", "a missing explanation is named with its finding: " _ problems.%ToJSON())
    Set review = ..GoodReview(), e = ..Entry(review, 1)
    Set e.explanation = "   "
    Do $$$AssertTrue(..Problems(review).%ToJSON() [ "needs an explanation for F1", "blank text is no explanation")
    Set review = ..GoodReview(), e = ..Entry(review, 0)
    Set e.explanation = ..Repeat("x", 601)
    Do $$$AssertTrue(..Problems(review).%ToJSON() [ "explanation of F2 is longer than 600", "an explanation over 600 characters is refused")
    Set review = ..GoodReview(), e = ..Entry(review, 0)
    Set e."confidence_note" = ..Repeat("y", 301)
    Do $$$AssertTrue(..Problems(review).%ToJSON() [ "confidence_note of F2 is longer than 300", "a confidence note over 300 characters is refused")
    Set review = ..GoodReview()
    Set review.summary = ..Repeat("z", 601)
    Do $$$AssertTrue(..Problems(review).%ToJSON() [ "summary is longer than 600", "a summary over 600 characters is refused")
}

Method TestShapeIsAnObjectWithARanking()
{
    If '..Present("Shutter.Schema.Review") Quit
    Set problems = $CLASSMETHOD("Shutter.Schema.Review", "Check", "not json")
    Do $$$AssertTrue(problems.%ToJSON() [ "must be a JSON object", "text that is not JSON is refused")
    Set problems = ..Problems({"summary": "no ranking"})
    Do $$$AssertTrue(problems.%ToJSON() [ "ranking must be an array", "a review without a ranking is refused")
    Set problems = ..Problems({"ranking": []})
    Do $$$AssertTrue(problems.%ToJSON() [ "must list every finding", "an empty ranking is refused")
    Set problems = ..Problems({"ranking": ["F1"]})
    Do $$$AssertTrue(problems.%ToJSON() [ "ranking[0] must be an object", "a bare id is refused")
    Set review = ..GoodReview()
    Set review.unknowns = "one string"
    Do $$$AssertTrue(..Problems(review).%ToJSON() [ "unknowns must be an array", "unknowns as a string is refused")
}

/// The tool keeps the accepted JSON and counts the submission; another review id and a bad shape are refused and leave
/// the result as it was.
Method TestSubmitReviewKeepsTheAcceptedJSONAndRefusesAnotherReview()
{
    If '..Present("Shutter.Tools.SubmitReview") Quit
    Set tool = $CLASSMETHOD("Shutter.Tools.SubmitReview", "%New")
    Set tool.CaseId = "PR-000001"
    Set out = tool.SubmitReview("PR-000002", ..GoodReview().%ToJSON())
    Do $$$AssertNotTrue(out.accepted, "a submission for another review is refused")
    Do $$$AssertTrue(out.error [ "PR-000001", "and the refusal names the run's review")
    Do $$$AssertEquals(tool.Result, "", "nothing is kept")
    Do $$$AssertEquals(tool.Submissions, 0, "and nothing is counted")
    Set out = tool.SubmitReview("PR-000001", {"ranking": []}.%ToJSON())
    Do $$$AssertNotTrue(out.accepted, "a review of the wrong shape is refused")
    Set problems = out.problems
    Do $$$AssertTrue($ISOBJECT(problems), "with the problems named")
    If $ISOBJECT(problems) Do $$$AssertTrue(problems.%Size() > 0, "at least one")
    Do $$$AssertTrue(tool.LastError '= "", "and the last error says so")
    Set out = tool.SubmitReview("PR-000001", ..GoodReview().%ToJSON())
    Do $$$AssertTrue(out.accepted, "the good review is accepted: " _ out.%ToJSON())
    Do $$$AssertTrue(out.next [ "one short sentence", "and the model is told to stop")
    Do $$$AssertEquals(tool.Submissions, 1, "one submission is counted")
    Do $$$AssertEquals(tool.LastError, "", "the last error is cleared")
    Set kept = ##class(Shutter.Util.Json).Parse(tool.Result, .sc)
    Do $$$AssertStatusOK(sc, "the result is JSON")
    Do $$$AssertEquals(kept.ranking.%Size(), 3, "and it is the ranking submitted")
}

}
