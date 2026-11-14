/// A runner for the tests that contacts no provider: it counts its calls in ^Shutter.Test.FakeRunner("calls") and answers
/// ok with a fixed model and token counts, so the cost a run records is ModelPrice's figure for them.
Class Shutter.Test.FakeRunner Extends Shutter.Bridge.Runner
{

Parameter MODEL = "claude-haiku-5-5";

Parameter PROMPTTOKENS = 4000;

Parameter COMPLETIONTOKENS = 800;

Method Run(spec As Shutter.Bridge.RunSpec, ByRef response As Shutter.Bridge.Msg.AgentResponse) As %Status
{
    Set calls = $INCREMENT(^Shutter.Test.FakeRunner("calls"))
    Set response.Status = "ok", response.Mode = spec.Mode, response.Model = ..#MODEL
    Set response.PromptTokens = ..#PROMPTTOKENS, response.CompletionTokens = ..#COMPLETIONTOKENS
    Set response.CacheReadTokens = 0, response.CacheCreationTokens = 0, response.Iterations = 1, response.ToolCalls = 0
    Set response.StartedAt = ##class(Shutter.Util.Time).NowUTC(), response.DurationMs = 5
    Set response.ResultJSON = "{""findings"":[]}"
    Quit $$$OK
}

}
