Include %occStatus

/// The run monitor: counts turns, tokens and tool calls as the agent runs, and stops the run when
/// the token budget or the deadline is passed. Passed to %AI.Agent.Run() as its callback.
Class Interlock.Bridge.Monitor Extends %RegisteredObject
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

Method OnIterationStart(iteration As %Integer, maxIter As %Integer, session As %AI.Agent.Session)
{
    Set ..Iterations = iteration
}

Method OnIterationComplete(iteration As %Integer, response As %AI.LLM.Response, session As %AI.Agent.Session)
{
    Set ..Iterations = iteration
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
    Try {
        If $ISOBJECT(response) && response.HasToolCalls() Set ..ToolCalls = ..ToolCalls + response.ToolCalls.%Size()
    } Catch {
    }
    If (..TokenBudget > 0) && (..TotalTokens > ..TokenBudget) {
        Set ..Stopped = "budget_exceeded"
        $$$ThrowStatus($$$ERROR($$$GeneralError, "budget_exceeded: " _ ..TotalTokens _ " tokens after " _ iteration _ " turns, budget " _ ..TokenBudget))
    }
    If (..Deadline > 0) && ($ZHOROLOG > ..Deadline) {
        Set ..Stopped = "timeout"
        $$$ThrowStatus($$$ERROR($$$GeneralError, "timeout: the run passed its deadline after " _ iteration _ " turns"))
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
