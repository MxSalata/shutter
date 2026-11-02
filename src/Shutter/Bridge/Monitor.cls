Include %occStatus

/// The run monitor. On build 154, %AI.Agent.Run() is one Chat() call whose tool-calling loop runs inside the
/// framework, bounded by the agent's MaxIterations and its own stall detection; the callback gets
/// OnRunStart(session) before it and OnRunComplete(response, session) after it, nothing in between. So the
/// monitor records the run's usage from the final response and the session's statistics, and the runner
/// judges the token budget after the run (a result over budget is reported as budget_exceeded, with the
/// result kept for inspection). The per-iteration methods stay for a build that calls them.
Class Shutter.Bridge.Monitor Extends %RegisteredObject
{

/// Tokens (prompt plus completion, cumulative) after which the run is stopped; 0 for no limit.
Property TokenBudget As %Integer [ InitialExpression = 0 ];

/// $ZHOROLOG after which the run is stopped; 0 for no limit.
Property Deadline As %Float [ InitialExpression = 0 ];

Property Iterations As %Integer [ InitialExpression = 0 ];

Property TotalTokens As %Integer [ InitialExpression = 0 ];

Property PromptTokens As %Integer [ InitialExpression = 0 ];

Property CompletionTokens As %Integer [ InitialExpression = 0 ];

Property CacheReadTokens As %Integer [ InitialExpression = 0 ];

Property CacheCreationTokens As %Integer [ InitialExpression = 0 ];

Property ToolCalls As %Integer [ InitialExpression = 0 ];

/// Why the run was stopped, or "".
Property Stopped As %String(MAXLEN = 32);

/// Called once before the run.
Method OnRunStart(session As %AI.Agent.Session)
{
    Set ..Started = $ZHOROLOG
}

/// Called once after the run, with the final response: the usage of the last model call, and the session's
/// totals.
Method OnRunComplete(response As %AI.LLM.Response, session As %AI.Agent.Session)
{
    Do ..Account(response)
    Try {
        Set stats = session.GetStats()
        If $ISOBJECT(stats) {
            Set ..PromptTokens = ..Value(stats, "total_prompt_tokens")
            Set ..CompletionTokens = ..Value(stats, "total_completion_tokens")
            Set ..TotalTokens = ..PromptTokens + ..CompletionTokens
            Set ..ToolCalls = ..Value(stats, "total_tool_calls")
            Set ..Iterations = ..Value(stats, "total_interactions")
            // The session's cache totals cover every call of the run; Account() saw only the final response.
            Set cr = ..Value(stats, "total_cache_read_tokens"), cc = ..Value(stats, "total_cache_creation_tokens")
            If cr > ..CacheReadTokens Set ..CacheReadTokens = cr
            If cc > ..CacheCreationTokens Set ..CacheCreationTokens = cc
        }
    } Catch {
    }
    Set ..Completed = 1
}

/// $ZHOROLOG when the run started.
Property Started As %Float;

/// Whether OnRunComplete was called.
Property Completed As %Boolean [ InitialExpression = 0 ];

Method OnIterationStart(iteration As %Integer, maxIter As %Integer, session As %AI.Agent.Session)
{
    Set ..Iterations = iteration
}

Method OnIterationComplete(iteration As %Integer, response As %AI.LLM.Response, session As %AI.Agent.Session)
{
    Set ..Iterations = iteration
    Do ..Account(response)
    If (..TokenBudget > 0) && (..TotalTokens > ..TokenBudget) {
        Set ..Stopped = "budget_exceeded"
        $$$ThrowStatus($$$ERROR($$$GeneralError, "budget_exceeded: " _ ..TotalTokens _ " tokens after " _ iteration _ " turns, budget " _ ..TokenBudget))
    }
    If (..Deadline > 0) && ($ZHOROLOG > ..Deadline) {
        Set ..Stopped = "timeout"
        $$$ThrowStatus($$$ERROR($$$GeneralError, "timeout: the run passed its deadline after " _ iteration _ " turns"))
    }
}

/// Adds a response's usage to the totals (cache tokens included, under whichever names the provider uses).
Method Account(response)
{
    Set usage = $SELECT($ISOBJECT(response): response.Usage, 1: "")
    If $ISOBJECT(usage) {
        Set prompt = ..Value(usage, "prompt_tokens,input_tokens,PromptTokens")
        Set completion = ..Value(usage, "completion_tokens,output_tokens,CompletionTokens")
        Set total = ..Value(usage, "total_tokens,TotalTokens")
        If total = 0 Set total = prompt + completion
        Set ..PromptTokens = ..PromptTokens + prompt, ..CompletionTokens = ..CompletionTokens + completion
        Set ..TotalTokens = ..TotalTokens + total
        Set ..CacheReadTokens = ..CacheReadTokens + ..Value(usage, "cache_read_tokens,cache_read_input_tokens,CacheReadTokens")
        Set ..CacheCreationTokens = ..CacheCreationTokens + ..Value(usage, "cache_creation_tokens,cache_creation_input_tokens,CacheCreationTokens")
    }
}

/// The first of several possible keys of a usage object that is set, as a number.
ClassMethod Value(usage As %DynamicObject, keys As %String) As %Integer
{
    For i = 1:1:$LENGTH(keys, ",") {
        Set k = $PIECE(keys, ",", i)
        If usage.%IsDefined(k) {
            Set v = usage.%Get(k)
            If $ISOBJECT(v) Continue
            Return +v
        }
    }
    Return 0
}

}
