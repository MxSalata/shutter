/// The production review (CONTRACTS 13): one instance per review. The REST route sends Shutter.Msg.ReviewRequest through
/// the Shutter API service; here, in a production job (which can read the hospital's namespace and %SYS, as the REST
/// caller cannot), the review row is opened and the early answer goes back with its id, then the sweep runs
/// (Shutter.Review.Sweep.Run: reads only, never a write to the production) and is stored, and, when asked and there are
/// findings, the review agent is sent the findings and the case aggregates through the Agent Board item; its ranking is
/// stored when it answers, and a timer ends the wait. The deterministic review stands whole whatever the agent does.
Class Shutter.Process.Review Extends Ens.BusinessProcess
{

Property ReviewId As %String(MAXLEN = 32);

/// Whether an agent request is out and its answer awaited.
Property AgentPending As %Boolean [ InitialExpression = 0 ];

/// The agent item the request goes to: the one that runs any request naming its agent class.
Property AgentTarget As %String(MAXLEN = 128) [ InitialExpression = "Agent Board" ];

/// Seconds to wait for the agent before the review is done with the baseline order.
Property AgentTimeoutSeconds As %Integer [ InitialExpression = 600 ];

/// The agent's model turns and token budget: a review costs less than a board member's run.
Property MaxIterations As %Integer [ InitialExpression = 3 ];

Property TokenBudget As %Integer [ InitialExpression = 60000 ];

Parameter SETTINGS = "AgentTarget:Targets,AgentTimeoutSeconds:Timing,MaxIterations:Agent,TokenBudget:Agent";

/// The review agent (the aihub module) and its configuration version, as the record key and the request name them.
Parameter AGENTCLASS = "Shutter.Agent.Review";

Parameter CONFIGVERSION = "1";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    If 'request.%IsA("Shutter.Msg.ReviewRequest") Quit $$$ERROR($$$GeneralError, "Case Review expects a review request, got " _ $CLASSNAME(request))
    Set started = ##class(Shutter.Msg.ReviewStarted).%New()
    Set response = started
    Set ns = $SELECT(request.Namespace = "": $NAMESPACE, 1: request.Namespace)
    Set prod = $SELECT(request.Production = "": ##class(Shutter.Setup).ProductionName(), 1: request.Production)
    Set days = +request.WindowDays
    If days < 1 Set days = 7
    If days > 90 Set days = 90
    // Only a production Shutter knows: the route checked; here again, so that no other caller's string becomes a
    // namespace switch.
    Set known = 0
    Try {
        Set known = ##class(Shutter.Review.Sweep).IsTarget(ns, prod)
    } Catch ex {
        Set known = 0
    }
    If 'known {
        Set started.State = "failed", started.Error = prod _ " in " _ ns _ " is not a production Shutter knows (GET /production-reviews/targets lists them)"
        Quit $$$OK
    }
    Set running = ##class(Shutter.Store.Review).Running(ns, prod)
    If $ISOBJECT(running) {
        Set started.ReviewId = running.ReviewId, started.State = running.State
        Set started.Error = "A review of " _ prod _ " in " _ ns _ " is already " _ running.State _ " (" _ running.ReviewId _ ")"
        Quit $$$OK
    }
    Set sc = ##class(Shutter.Store.Review).Create(ns, prod, request.RequestedBy, days, .r)
    If $$$ISERR(sc) || '$ISOBJECT(r) {
        Set started.State = "failed", started.Error = "The review could not be opened: " _ $SYSTEM.Status.GetErrorText(sc)
        Quit $$$OK
    }
    Set ..ReviewId = r.ReviewId
    Set started.ReviewId = r.ReviewId, started.State = r.State
    $$$TRACE("Review " _ r.ReviewId _ " of " _ prod _ " in " _ ns _ " opened over " _ days _ " days by " _ request.RequestedBy)
    // The answer goes back now, not when the instance completes: the REST route waits for the review id, and the sweep
    // takes seconds, the agent longer. The response set above still stands for a caller that reads it at completion.
    Set rsc = ..Reply(started)
    If $$$ISERR(rsc) $$$TRACE("The early reply was not sent: " _ $SYSTEM.Status.GetErrorText(rsc))
    // The sweep: reads only, in this job, which runs as the production's user and can read the other namespace.
    Set result = ""
    Try {
        Set sc = ##class(Shutter.Review.Sweep).Run(ns, prod, days, .result)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) || '$ISOBJECT(result) {
        Set text = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no result")
        $$$LOGWARNING("Review " _ r.ReviewId _ ": the sweep failed: " _ text)
        Do r.Fail("The sweep failed: " _ text)
        Do ##class(Shutter.Store.Review).Trim(ns, prod)
        Quit $$$OK
    }
    Set findings = result.%Get("findings")
    Set n = $SELECT($ISOBJECT(findings): findings.%Size(), 1: 0)
    Set unreadable = ##class(Shutter.Util.Json).Bool(result, "unreadable", 0)
    // Nothing to rank when there is no finding, and nothing worth a model's time when the one finding is that the
    // namespace could not be read.
    Set wantAgent = request.Agent && (n > 0) && 'unreadable
    Set fingerprint = ##class(Shutter.Util.Json).Str(result, "fingerprint")
    Set key = $SELECT(wantAgent: ..RecordKeyFor(ns, prod, fingerprint), 1: "")
    Set sc = r.StoreSweep(result, wantAgent, key)
    If $$$ISERR(sc) {
        $$$LOGWARNING("Review " _ r.ReviewId _ " could not be stored: " _ $SYSTEM.Status.GetErrorText(sc))
        Quit sc
    }
    $$$TRACE("Review " _ r.ReviewId _ ": " _ n _ " finding" _ $SELECT(n = 1: "", 1: "s") _ ", fingerprint " _ $EXTRACT(fingerprint, 1, 19) _ $SELECT(wantAgent: "; the agent ranks them", request.Agent: "; nothing for the agent to rank", 1: "; no agent asked"))
    If 'wantAgent {
        Do ##class(Shutter.Store.Review).Trim(ns, prod)
        Quit $$$OK
    }
    Set req = ..BuildAgentRequest(r, result, ..MaxIterations, ..TokenBudget)
    Set ..AgentPending = 1
    Set sc = ..SendRequestAsync(..AgentTarget, req, 1, "review")
    If $$$ISERR(sc) {
        Set ..AgentPending = 0
        Do r.AgentFailed("The agent request could not be sent to " _ ..AgentTarget _ ": " _ $SYSTEM.Status.GetErrorText(sc))
        Do ##class(Shutter.Store.Review).Trim(ns, prod)
        Quit $$$OK
    }
    Quit ..ArmTimeout()
}

/// The key the agent's run is recorded and replayed under: the configuration findings' fingerprint, so the key is the
/// same on every instance that reaches the same configuration and does not move with counts or times.
ClassMethod RecordKeyFor(namespace As %String, production As %String, fingerprint As %String) As %String
{
    Quit "review:" _ namespace _ ":" _ production _ "|review|" _ ..#CONFIGVERSION _ "|" _ fingerprint
}

/// The agent's request for a review: the findings as the sweep wrote them, less what is not for the model (the error
/// example text, which may quote an HL7 segment; the annotation id; the rank and explanation it is to fill), and the
/// per-item case aggregates (counts and case ids only: the sweep never reads note text, operation-key pieces or failure
/// text, so no patient or encounter identifier reaches the context by construction). A class method, so a test can
/// build the same request outside the production.
ClassMethod BuildAgentRequest(review As Shutter.Store.Review, result As %DynamicObject, maxIterations As %Integer = 3, tokenBudget As %Integer = 60000) As Shutter.Bridge.Msg.AgentRequest
{
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Set req.Role = "review", req.MemberCode = "review", req.AgentClass = ..#AGENTCLASS
    Set req.TerminalTool = "SubmitReview", req.ResultClass = "Shutter.Schema.Review"
    Set req.ConfigVersion = ..#CONFIGVERSION
    Set req.CorrelationKey = review.ReviewId
    Set fingerprint = ##class(Shutter.Util.Json).Str(result, "fingerprint")
    Set req.SnapshotDigest = $EXTRACT(fingerprint, 1, 80)
    Set req.RecordKey = ..RecordKeyFor(review.Namespace, review.Production, fingerprint)
    Set req.TokenBudget = tokenBudget, req.MaxIterations = maxIterations
    Set req.Goal = "Rank the findings of this production review within their severity tiers and explain each in one or two sentences against the case history; call SubmitReview once with the review id."
    Set context = {}
    Set context."review_id" = review.ReviewId
    Set context.namespace = review.Namespace, context.production = review.Production
    Set context."production_state" = ##class(Shutter.Util.Json).Str(result, "productionState")
    Set w = result.%Get("window")
    If '$ISOBJECT(w) Set w = {}
    Set context.window = w
    Set summary = result.%Get("summary")
    If '$ISOBJECT(summary) Set summary = {}
    Set context.summary = summary
    Set findings = []
    Set source = result.%Get("findings")
    If $ISOBJECT(source) {
        Set iter = source.%GetIterator()
        While iter.%GetNext(.i, .f) {
            Continue:'$ISOBJECT(f)
            Set copy = ##class(%DynamicObject).%FromJSON(f.%ToJSON())
            Do copy.%Remove("annotationId"), copy.%Remove("rank"), copy.%Remove("explanation")
            Set ev = copy.%Get("evidence")
            If $ISOBJECT(ev) Do ev.%Remove("example")
            Do findings.%Push(copy)
        }
    }
    Set context.findings = findings
    Set agg = result.%Get("caseAggregates")
    If '$ISOBJECT(agg) Set agg = {}
    Set context.cases = agg
    Set req.Context = context.%ToJSON()
    Quit req
}

/// The Ens.MessageHeader id of a message body, or "".
Method HeaderIdOf(body As %Library.Persistent) As %String
{
    If '$ISOBJECT(body) Quit ""
    Set cls = $CLASSNAME(body), bodyId = body.%Id(), id = ""
    &sql(SELECT TOP 1 ID INTO :id FROM Ens.MessageHeader WHERE MessageBodyClassName = :cls AND MessageBodyId = :bodyId ORDER BY ID DESC)
    If SQLCODE '= 0 Quit ""
    Quit id
}

Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, completionkey As %String) As %Status
{
    Set sc = $$$OK
    Try {
        Set r = ##class(Shutter.Store.Review).ByReviewId(..ReviewId)
        If '$ISOBJECT(r) { $$$LOGWARNING("No review " _ ..ReviewId _ " for the answer " _ completionkey) Quit }
        If completionkey = "review" { Set sc = ..OnAgent(r, callrequest, callresponse) Quit }
        If completionkey = "review:timeout" { Set sc = ..OnTimeout(r) Quit }
        $$$LOGWARNING("Unexpected completion key " _ completionkey)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) {
        Set r = ##class(Shutter.Store.Review).ByReviewId(..ReviewId)
        If $ISOBJECT(r) && (r.State = "ranking") Do r.AgentFailed("Error at " _ completionkey _ ": " _ $EXTRACT($SYSTEM.Status.GetErrorText(sc), 1, 1500))
    }
    Quit sc
}

/// The agent item answered with an error status instead of a response: the review is done with the baseline order and
/// the reason, and the instance ends cleanly.
Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
    Try {
        If (pCompletionKey = "review") && ..AgentPending {
            Set ..AgentPending = 0
            Set r = ##class(Shutter.Store.Review).ByReviewId(..ReviewId)
            If $ISOBJECT(r) Do r.AgentFailed("Error from the agent call: " _ $EXTRACT($SYSTEM.Status.GetErrorText(pErrorStatus), 1, 1500))
        }
    } Catch {
    }
    Quit $$$OK
}

/// The agent's answer: an accepted ranking (every finding once, ranks 1 to n, no finding above a higher severity tier:
/// Shutter.Store.Review.RankingProblem) is stored with the run's cost; a refused one leaves the baseline order and is
/// recorded as schema_failed with the problem; any other status is recorded as the bridge reported it.
Method OnAgent(r As Shutter.Store.Review, callrequest As %Library.Persistent, callresponse As %Library.Persistent) As %Status
{
    If '..AgentPending {
        $$$TRACE("The agent answered review " _ r.ReviewId _ " after its time was up; the answer is not used")
        Quit $$$OK
    }
    Set ..AgentPending = 0
    Set ranking = "", problem = ""
    If '$ISOBJECT(callresponse) || 'callresponse.%IsA("Shutter.Bridge.Msg.AgentResponse") {
        Set sc = r.AgentFailed("The agent item answered with " _ $SELECT($ISOBJECT(callresponse): $CLASSNAME(callresponse), 1: "nothing"))
    } Else {
        If (callresponse.Status = "ok") && (callresponse.ResultJSON '= "") {
            Set parsed = ##class(Shutter.Util.Json).Parse(callresponse.ResultJSON, .psc)
            If '$ISOBJECT(parsed) || $$$ISERR(psc) {
                Set problem = "The agent's result is not valid JSON"
            } Else {
                Set problem = ##class(Shutter.Store.Review).RankingProblem(r.Findings(), parsed)
                If problem = "" Set ranking = parsed
            }
        }
        Set sc = r.StoreAgent(callresponse, ranking, problem, ..HeaderIdOf(callrequest))
        $$$TRACE("Review " _ r.ReviewId _ ": the agent's part is " _ r.AgentState _ $SELECT(r.AgentError '= "": " (" _ r.AgentError _ ")", 1: "") _ $SELECT(callresponse.Mode '= "": ", mode " _ callresponse.Mode, 1: ""))
    }
    Do ##class(Shutter.Store.Review).Trim(r.Namespace, r.Production)
    Quit sc
}

/// The agent's time is up: the review is done with the baseline order.
Method OnTimeout(r As Shutter.Store.Review) As %Status
{
    If '..AgentPending Quit $$$OK
    Set ..AgentPending = 0
    Set sc = r.AgentFailed("The agent did not answer within " _ ..AgentTimeoutSeconds _ " s; the baseline order stands")
    Do ##class(Shutter.Store.Review).Trim(r.Namespace, r.Production)
    Quit sc
}

/// A timer on the agent: a run that never answers must not leave the review ranking for ever.
Method ArmTimeout() As %Status
{
    If ..AgentTimeoutSeconds <= 0 Quit $$$OK
    Set alarm = ##class(Ens.AlarmRequest).%New()
    Set alarm.Timeout = ..AgentTimeoutSeconds
    Quit ..SendRequestAsync("Ens.Alarm", alarm, 1, "review:timeout", "The review agent's time")
}

Storage Default
{
<Data name="ReviewDefaultData">
<Subscript>"Review"</Subscript>
<Value name="1">
<Value>ReviewId</Value>
</Value>
<Value name="2">
<Value>AgentPending</Value>
</Value>
<Value name="3">
<Value>AgentTarget</Value>
</Value>
<Value name="4">
<Value>AgentTimeoutSeconds</Value>
</Value>
<Value name="5">
<Value>MaxIterations</Value>
</Value>
<Value name="6">
<Value>TokenBudget</Value>
</Value>
</Data>
<DefaultData>ReviewDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
