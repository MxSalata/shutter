/// What a case cost (CONTRACTS 5): the sum of what its agent runs spent, read from the AgentRun rows Shutter keeps, as
/// GET /costs counts them case by case. Read only; nothing here calls a model, prices a run again or writes a row.
/// A live or record run spent its CostUSD, Shutter.Store.ModelPrice.Cost of its tokens at the price stored when it ran.
/// A replay reads a recording and calls no model, so it costs 0, whatever its recorded tokens; so does a run the API mimic
/// answered (model mock) and a run that reached no model (no tokens: refused for the budget, or failed before the call).
/// A run that reached a model whose price Shutter did not hold when it ran has no CostUSD: the case's cost is then
/// unpriced, never shown as 0, and what the priced runs spent is still given.
Class Shutter.Util.CaseCost
{

/// The cost of one case, by its row id, as the API names it: {usd, unpriced, runs, modelRuns, replayedRuns, mockRuns,
/// unpricedRuns, models, unpricedModels, questionRuns, questionUsd}. Every run of the case counts, the questions' (CONTRACTS
/// 14.2) included; questionRuns and questionUsd say how much of it was asked after the decision. usd is what the priced runs
/// spent; unpriced is true when any run that reached a model has no price, and unpricedModels names those models.
ClassMethod ForCase(caseRowId As %String) As %DynamicObject
{
    Kill t
    If caseRowId '= "" {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Mode, Model, CostUSD, PromptTokens, CompletionTokens, CacheReadTokens, CacheCreationTokens, QuestionId FROM Shutter_Store.AgentRun WHERE ""Case"" = ? ORDER BY ID", caseRowId)
        While rs.%Next() {
            Do ..Tally(.t, rs.%Get("Mode"), rs.%Get("Model"), rs.%Get("CostUSD"), rs.%Get("PromptTokens") + rs.%Get("CompletionTokens") + rs.%Get("CacheReadTokens") + rs.%Get("CacheCreationTokens"), rs.%Get("QuestionId") '= "")
        }
    }
    Quit ..Object(.t)
}

/// Adds one run to the tally <var>t</var>: t("runs"), t("modelRuns") (a run that reached a real model), t("replayedRuns"),
/// t("mockRuns"), t("unpricedRuns"), t("usd"), t("models", model), t("unpriced", model), t("questionRuns") and
/// t("questionUsd"). <var>tokens</var> is the run's four token counts added up.
ClassMethod Tally(ByRef t, mode As %String, model As %String, costUsd As %String, tokens As %Integer, question As %Boolean = 0)
{
    Set t("runs") = $GET(t("runs")) + 1, usd = 0
    If question Set t("questionRuns") = $GET(t("questionRuns")) + 1
    If mode = "replay" {
        // A replay calls no model: 0, as GET /costs and the day's budget count it.
        Set t("replayedRuns") = $GET(t("replayedRuns")) + 1
        Quit
    }
    If model = "mock" {
        Set t("mockRuns") = $GET(t("mockRuns")) + 1
        Quit
    }
    // A run with no tokens never reached the model, so it spent nothing, priced or not.
    Quit:+tokens<=0
    Set t("modelRuns") = $GET(t("modelRuns")) + 1
    If model '= "" Set t("models", model) = ""
    If costUsd = "" {
        Set t("unpricedRuns") = $GET(t("unpricedRuns")) + 1, t("unpriced", $SELECT(model = "": "(no model named)", 1: model)) = ""
        Quit
    }
    Set usd = +costUsd, t("usd") = $GET(t("usd")) + usd
    If question Set t("questionUsd") = $GET(t("questionUsd")) + usd
}

/// The tally as the API names it.
ClassMethod Object(ByRef t) As %DynamicObject
{
    Set o = {}
    Do o.%Set("usd", +$JUSTIFY($GET(t("usd")), 0, 6), "number")
    Do o.%Set("unpriced", +$GET(t("unpricedRuns")) > 0, "boolean")
    For name = "runs", "modelRuns", "replayedRuns", "mockRuns", "unpricedRuns", "questionRuns" {
        Do o.%Set(name, +$GET(t(name)), "number")
    }
    Do o.%Set("questionUsd", +$JUSTIFY($GET(t("questionUsd")), 0, 6), "number")
    For name = "models", "unpriced" {
        Set list = [], m = ""
        For {
            Set m = $ORDER(t(name, m))
            Quit:m=""
            Do list.%Push(m)
        }
        Do o.%Set($SELECT(name = "models": "models", 1: "unpricedModels"), list)
    }
    Quit o
}

}
