/// What a case cost (Shutter.Util.CaseCost; CONTRACTS 5): the sum of what its agent runs spent, as GET /costs counts them
/// case by case; 0 for a replay, the API mimic and a run that reached no model; unpriced, never 0, when a run that reached a
/// model had no stored price; the questions' runs counted in it and apart. The runs are stored as the Agent item stores
/// them (Shutter.Store.AgentRun FromResponse), so each is priced as a real run is. The test's cases, runs and price are
/// removed afterwards.
Class Shutter.Test.CaseCost Extends %UnitTest.TestCase
{

Parameter MODEL = "ut-cost-model";

Parameter UNPRICED = "ut-cost-unpriced";

Method OnBeforeAllTests() As %Status
{
    Do ..Clean()
    Set price = ##class(Shutter.Store.ModelPrice).%New()
    Set price.Model = ..#MODEL, price.InputPerMTok = 10, price.OutputPerMTok = 20, price.CacheReadPerMTok = 1, price.Source = "unit test"
    Quit price.%Save()
}

Method OnAfterAllTests() As %Status
{
    Do ..Clean()
    Quit $$$OK
}

Method Clean()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId %STARTSWITH 'UT-COST-'")
    While rs.%Next() {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.AgentRun WHERE ""Case"" = ?", rs.%Get("ID"))
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", rs.%Get("ID"))
        Kill ^Shutter.Counter("event", rs.%Get("ID"))
        Do ##class(Shutter.Store.Case).%DeleteId(rs.%Get("ID"))
    }
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.ModelPrice WHERE Model = ? OR Model = ?", ..#MODEL, ..#UNPRICED)
}

Method Case(name As %String) As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-COST-" _ name, case.OperationKey = "PAS^HOSP^MRN-COST^ENC-" _ name _ "^transfer^2026-11-18T09:00:00Z"
    Set case.Event = "transfer", case.EncounterId = "ENC-" _ name, case.PatientId = "MRN-COST", case.FailureKind = "delivery_failed"
    Set case.Mode = "board", case.OpenedAt = "2026-11-18T09:00:00Z", case.UpdatedAt = "2026-11-18T09:00:00Z"
    Do $$$AssertStatusOK(case.%Save(), "the case " _ name)
    Quit case
}

/// A run stored as the Agent item stores it, priced by its row's own formula (AgentRun CostOf).
Method Run(case As Shutter.Store.Case, mode As %String, model As %String, prompt As %Integer, completion As %Integer, cacheRead As %Integer = 0, questionId As %String = "")
{
    Set r = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set r.Status = "ok", r.Mode = mode, r.Model = model, r.AgentClass = "Shutter.Agent.Conformance", r.ConfigVersion = "1"
    Set r.StartedAt = "2026-11-18T09:00:05Z", r.PromptTokens = prompt, r.CompletionTokens = completion, r.CacheReadTokens = cacheRead
    Set r.ResultJSON = "{}"
    Do $$$AssertStatusOK(##class(Shutter.Store.AgentRun).FromResponse(case, "", "member", "conformance", r, "", .run, questionId), "a " _ mode _ " run on " _ model)
}

/// What GET /costs gives the case in byCase: the same rows, summed the same way.
Method CostsByCase(case As Shutter.Store.Case) As %Numeric
{
    Set id = case.%Id(), cost = 0
    &sql(SELECT SUM(CASE WHEN Mode = 'replay' THEN 0 ELSE CostUSD END) INTO :cost FROM Shutter_Store.AgentRun WHERE "Case" = :id)
    Quit +cost
}

Method Names(list As %DynamicArray) As %String
{
    Set out = "", iter = list.%GetIterator()
    While iter.%GetNext(.i, .v) { Set out = out _ $SELECT(out = "": "", 1: ",") _ v }
    Quit out
}

/// A case no agent ran on (rules alone, the site's policy) cost 0, and is not unpriced; nor is an unknown row id.
Method TestNoRunsCostNothing()
{
    Set c = ##class(Shutter.Util.CaseCost).ForCase(..Case("NONE").%Id())
    Do $$$AssertEquals(c.usd _ "|" _ c.runs _ "|" _ c.modelRuns _ "|" _ c.unpricedRuns, "0|0|0|0", "nothing ran: " _ c.%ToJSON())
    Do $$$AssertEquals(c.%GetTypeOf("unpriced"), "boolean", "unpriced is a boolean")
    Do $$$AssertNotTrue(c.unpriced, "and false")
    Do $$$AssertEquals(c.models.%Size() + c.unpricedModels.%Size(), 0, "no model named")
    Do $$$AssertEquals(##class(Shutter.Util.CaseCost).ForCase("").runs, 0, "no row id, no runs")
}

/// A live run (0.015), a record run (0.0025), a replay of a priced recording (0), a mimic run (0) and a question's live
/// run (0.002): the case cost the sum of the three that reached a model, and GET /costs gives the case the same figure.
Method TestTheSumOfItsRuns()
{
    Set case = ..Case("SUM")
    Do ..Run(case, "live", ..#MODEL, 1000, 200, 1000)
    Do ..Run(case, "record", ..#MODEL, 50, 100)
    Do ..Run(case, "replay", ..#MODEL, 90000, 9000)
    Do ..Run(case, "live", "mock", 4000, 400)
    Do ..Run(case, "live", ..#MODEL, 200, 0, 0, "Q-000001")
    Set c = ##class(Shutter.Util.CaseCost).ForCase(case.%Id())
    Do $$$AssertEquals(c.usd, .0195, "0.015 + 0.0025 + 0.002, the replay and the mimic adding nothing: " _ c.%ToJSON())
    Do $$$AssertEquals(c.usd, ..CostsByCase(case), "as GET /costs counts the case")
    Do $$$AssertEquals(c.runs _ "|" _ c.modelRuns _ "|" _ c.replayedRuns _ "|" _ c.mockRuns, "5|3|1|1", "every run counted, by kind")
    Do $$$AssertNotTrue(c.unpriced, "every run that reached a model was priced")
    Do $$$AssertEquals(..Names(c.models), ..#MODEL, "the model that was called, once")
    Do $$$AssertEquals(c.questionRuns _ "|" _ c.questionUsd, "1|.002", "the question's run, inside the total and apart")
}

/// A replay costs 0 whatever its recorded tokens, and never makes a case unpriced, even on a model with no price.
Method TestReplaysCostNothing()
{
    Set case = ..Case("REPLAY")
    Do ..Run(case, "replay", ..#MODEL, 90000, 9000)
    Do ..Run(case, "replay", ..#UNPRICED, 90000, 9000)
    // A replay that found no recording names no model.
    Do ..Run(case, "replay", "", 0, 0)
    Set c = ##class(Shutter.Util.CaseCost).ForCase(case.%Id())
    Do $$$AssertEquals(c.usd _ "|" _ c.replayedRuns _ "|" _ c.modelRuns, "0|3|0", "three replays, 0: " _ c.%ToJSON())
    Do $$$AssertNotTrue(c.unpriced, "and not unpriced")
}

/// A run on a model Shutter held no price for is unpriced: the case says so and names the model, and the priced runs'
/// spend is still given. A run on such a model that reached no model (no tokens) spent nothing and leaves it priced.
Method TestAModelWithNoPriceIsUnpriced()
{
    Set case = ..Case("NOPRICE")
    Do ..Run(case, "live", ..#MODEL, 1000, 200, 1000)
    Do ..Run(case, "live", ..#UNPRICED, 500, 50)
    Set c = ##class(Shutter.Util.CaseCost).ForCase(case.%Id())
    Do $$$AssertTrue(c.unpriced, "unpriced: " _ c.%ToJSON())
    Do $$$AssertEquals(c.unpricedRuns, 1, "one run had no price")
    Do $$$AssertEquals(..Names(c.unpricedModels), ..#UNPRICED, "named")
    Do $$$AssertEquals(c.usd, .015, "the priced run's spend, never the unpriced one's as 0")
    Do $$$AssertEquals(..Names(c.models), ..#MODEL _ "," _ ..#UNPRICED, "both models were called")
    Set none = ..Case("NOTOKENS")
    Do ..Run(none, "live", ..#UNPRICED, 0, 0)
    Set c = ##class(Shutter.Util.CaseCost).ForCase(none.%Id())
    Do $$$AssertNotTrue(c.unpriced, "a run with no tokens reached no model: " _ c.%ToJSON())
    Do $$$AssertEquals(c.usd _ "|" _ c.runs _ "|" _ c.modelRuns, "0|1|0", "it counts as a run, at 0")
}

}
