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
Property MaxIterations As %Integer [ InitialExpression = 4 ];

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
    Set req = ..BuildAgentRequest(r, result, ..MaxIterations, ..TokenBudget, request.RequestedBy)
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
/// text; an error group's signature, the one piece of log text in a finding, goes as ModelSignature shows it, and every
/// item key and value of the aggregates, which a feed or a connector can fill with free text, as ModelKey and ModelValue
/// show them). Who asked (v1.39) is the run's requester, for the budget's share; nobody named means the feed's own
/// ("system", no share). A class method, so a test can build the same request outside the production.
ClassMethod BuildAgentRequest(review As Shutter.Store.Review, result As %DynamicObject, maxIterations As %Integer = 3, tokenBudget As %Integer = 60000, requestedBy As %String = "") As Shutter.Bridge.Msg.AgentRequest
{
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Set req.RequestedBy = $SELECT(requestedBy '= "": requestedBy, 1: "system")
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
    // The names the agent may read as they are in the aggregates' keys: the production's items, and the items the
    // findings are about (an item since removed from the production still logs under its name).
    Kill known
    Set names = result.%Get("itemNames")
    If $ISOBJECT(names) {
        Set iter = names.%GetIterator()
        While iter.%GetNext(.i, .name) { Set:name'="" known(name) = "" }
    }
    If $ISOBJECT(source) {
        Set iter = source.%GetIterator()
        While iter.%GetNext(.i, .f) {
            If $ISOBJECT(f) && (##class(Shutter.Util.Json).Str(f, "item") '= "") Set known(f.item) = ""
        }
    }
    If $ISOBJECT(source) {
        Set iter = source.%GetIterator()
        While iter.%GetNext(.i, .f) {
            Continue:'$ISOBJECT(f)
            Set copy = ##class(%DynamicObject).%FromJSON(f.%ToJSON())
            Do copy.%Remove("annotationId"), copy.%Remove("rank"), copy.%Remove("explanation")
            Set ev = copy.%Get("evidence")
            If $ISOBJECT(ev) Do ev.%Remove("example")
            // An error group's signature is the event log's own text before its first colon, which an application can
            // fill with a patient's name: the model sees an IRIS error code as it is and any other signature as a digest,
            // in found and in the words that quote it. The stored finding keeps the text for the operator's GET.
            If (copy.code = "ERRORS_GROUPED") && (copy.found '= "") {
                Set signature = copy.found, shown = ..ModelSignature(signature)
                Set copy.found = shown
                For key = "why", "suggested", "action" {
                    Do copy.%Set(key, ..WithheldWords(copy, key, signature, shown))
                }
            }
            Do findings.%Push(copy)
        }
    }
    Set context.findings = findings
    Set agg = result.%Get("caseAggregates")
    If '$ISOBJECT(agg) Set agg = {}
    Set context.cases = ..ModelAggregates(agg, .known)
    Set req.Context = context.%ToJSON()
    Quit req
}

/// A finding's words with its error signature withheld: the check's own text filled again with the signature as the model
/// sees it, so a signature that is also a word of that text or of an item's name ("error", "Feed") stands in for itself
/// alone. A sentence the sweep added after the check's text (the production's own errors, an item since removed) is
/// fixed wording and is kept as it is. Words that don't start with the check's text as filled (a finding stored under
/// another version of the rules) fall back to replacing the signature wherever it is, which may also change other words
/// but never lets the signature through.
ClassMethod WithheldWords(finding As %DynamicObject, key As %String, signature As %String, shown As %String) As %String
{
    Set json = "Shutter.Util.Json", checks = "Shutter.Review.Checks"
    Set words = $CLASSMETHOD(json, "Str", finding, key)
    Set template = $CLASSMETHOD(json, "Str", $CLASSMETHOD(checks, "Rule", $CLASSMETHOD(json, "Str", finding, "code")), key)
    Set ev = finding.%Get("evidence")
    Set values = {}
    Set values.item = $CLASSMETHOD(json, "Str", finding, "item")
    Set values.setting = $CLASSMETHOD(json, "Str", finding, "setting")
    Set values.count = $SELECT($ISOBJECT(ev): +ev.%Get("count"), 1: 0)
    Set values.found = signature
    Set asStored = $CLASSMETHOD(checks, "Fill", template, values)
    If (template '= "") && (asStored '= "") && ($EXTRACT(words, 1, $LENGTH(asStored)) = asStored) {
        Set added = $EXTRACT(words, $LENGTH(asStored) + 1, *)
        Set values.found = shown
        Quit $CLASSMETHOD(checks, "Fill", template, values) _ added
    }
    Quit $REPLACE(words, signature, shown)
}

/// An error signature as the review's agent sees it: an IRIS error code (ERROR #5001, ERROR <Ens>ErrBPTerminated) as it
/// is, since the system writes those and they carry nothing of a message; any other text, which an application wrote
/// and may have filled with a name or a number, as "[withheld text h]", h the first 12 hex digits of its SHA-256, the
/// same on every review, so one signature still reads as one. "" stays "".
ClassMethod ModelSignature(signature As %String) As %String
{
    If signature = "" Quit ""
    If signature ? 1"ERROR #"1.N Quit signature
    If signature ? 1"ERROR <"1.(1A,1N,1"%",1".")1">"1.(1A,1N) Quit signature
    Quit ..Withheld(signature)
}

/// A text the review's agent is not to read: "[withheld text h]", h the first 12 hex digits of its SHA-256, the same on
/// every review, so one text still reads as one.
ClassMethod Withheld(text As %String) As %String
{
    Quit "[withheld text " _ $EXTRACT($PIECE(##class(Shutter.Util.Digest).SHA256Hex(text), ":", 2), 1, 12) _ "]"
}

/// The case aggregates as the review's agent sees them. Their keys come from the cases' own fields: the item (Receiver or
/// SourceRoute), and the values by failure kind, outcome, reason code and state, which POST /intake and a connector's
/// reason_code can fill with any text, a patient's name included, as free text or as one word that looks like a code.
/// Each item key goes as ModelKey shows it and each value as ModelValue does; the counts and the case ids go as they are,
/// and two keys withheld into one (never in practice) add their counts.
ClassMethod ModelAggregates(agg As %DynamicObject, ByRef known) As %DynamicObject
{
    Set out = {}
    Set iter = agg.%GetIterator()
    While iter.%GetNext(.name, .a) {
        // The sweep's own keys, the production's totals and its error when the store could not be read, stay as they are.
        Set shown = $SELECT((name = "_total") || (name = "_error"): name, 1: ..ModelKey(name, .known))
        Do out.%Set(shown, $SELECT($ISOBJECT(a): ##class(%DynamicAbstractObject).%FromJSON(a.%ToJSON()), 1: a))
    }
    // The values within each aggregate, the production's totals included, each read against its own dimension's words.
    Do ..ModelWords(.words)
    Set iter = out.%GetIterator()
    While iter.%GetNext(.name, .a) {
        Continue:'$ISOBJECT(a)
        For dim = "byFailureKind", "byOutcome", "byReasonCode", "byState" {
            Set by = a.%Get(dim)
            Continue:'$ISOBJECT(by)
            Set reduced = {}
            Set it2 = by.%GetIterator()
            While it2.%GetNext(.v, .n) {
                Set k = ..ModelValue(dim, v, .words)
                If reduced.%IsDefined(k) && (by.%GetTypeOf(v) = "number") {
                    Do reduced.%Set(k, reduced.%Get(k) + n)
                } Else {
                    Do reduced.%Set(k, n)
                }
            }
            Do a.%Set(dim, reduced)
        }
    }
    Quit out
}

/// An item key of the case aggregates as the review's agent sees it: a name in known (the production's items and the
/// items the findings are about) as it is; "(none)", the sweep's word for an empty value, as it is; any other text
/// withheld (Withheld), whatever its shape, since a receiver or a route posted to the intake can be one word.
ClassMethod ModelKey(key As %String, ByRef known) As %String
{
    If key = "" Quit ""
    If key = "(none)" Quit key
    If $DATA(known(key)) Quit key
    Quit ..Withheld(key)
}

/// The outcomes a case can hold that the agent may read: the connector's classes of an answer (Shutter.Msg.WardResult),
/// the intake's (CONTRACTS 11) and the code an acknowledgement answers.
Parameter MODELOUTCOMES = "applied,already_committed,would_apply,would_not_apply,version_conflict,refused,unavailable,uncertain,error,rejected,read,unknown_encounter,AA,AE,AR,CA,CE,CR";

/// The reason codes a case can hold that the agent may read: Shutter's own (an alert, a held or unreadable message, a
/// withheld merge or cancel, the onboarding test, the connector's preflight), the downstream contract's error codes, and
/// the words the catalogue reads a receiver's answer by.
Parameter MODELREASONS = "alert,alert_unread,schema_unknown,invalid_message,merge,cancel_unsupported,onboarding_test,dry_run_unsupported,newer_message_pending,further_movement,committed_not_this_message,ward_unavailable,duplicate_message,version_conflict,invalid_transition,unknown_encounter,bed_occupied,patient_mismatch,no_receipt,unsupported_precondition,payload_digest_mismatch,key_reused_with_different_payload,invalid_request,internal_error,unavailable,timeout,duplicate,refused";

/// The words each dimension of the aggregates may show as they are: words(dim, word). The failure kinds and the states
/// are the case's own lists (Shutter.Store.Case, VALUELIST); the outcomes and reason codes are MODELOUTCOMES and
/// MODELREASONS.
ClassMethod ModelWords(ByRef words)
{
    Kill words
    For dim = "byFailureKind", "byState" {
        Set prop = ##class(%Dictionary.CompiledProperty).%OpenId("Shutter.Store.Case||" _ $SELECT(dim = "byState": "State", 1: "FailureKind"))
        Set list = $SELECT($ISOBJECT(prop): prop.Parameters.GetAt("VALUELIST"), 1: "")
        // A VALUELIST names its delimiter in its first mark.
        For i = 2:1:$LENGTH(list, $EXTRACT(list)) {
            Set w = $PIECE(list, $EXTRACT(list), i)
            Set:w'="" words(dim, w) = ""
        }
    }
    For dim = "byOutcome", "byReasonCode" {
        Set list = $SELECT(dim = "byOutcome": ..#MODELOUTCOMES, 1: ..#MODELREASONS)
        For i = 1:1:$LENGTH(list, ",") { Set words(dim, $PIECE(list, ",", i)) = "" }
    }
}

/// A value of one dimension of the case aggregates (byFailureKind, byOutcome, byReasonCode, byState) as the review's
/// agent sees it: a word of that dimension's list (ModelWords) as it is; for an outcome or a reason code also an HTTP
/// status (HTTP_503) and, for a reason code, an acknowledgement's code (ack_AR), in those fixed shapes; "(none)" as it
/// is; any other value withheld (Withheld), a word that looks like a code included. words is ModelWords's, built here
/// when not given.
ClassMethod ModelValue(dim As %String, value As %String, ByRef words) As %String
{
    If value = "" Quit ""
    If value = "(none)" Quit value
    If '$DATA(words) Do ..ModelWords(.words)
    If $DATA(words(dim, value)) Quit value
    If ((dim = "byOutcome") || (dim = "byReasonCode")) && (value ? 1"HTTP_"3N) Quit value
    If (dim = "byReasonCode") && (value ? 1"ack_"1(1"AE",1"AR",1"CE",1"CR")) Quit value
    Quit ..Withheld(value)
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
                // The ranking is matched to this review's findings by code, item and setting (v1.22), so a recording made
                // on another instance's findings still explains the ones that are here.
                If ##class(Shutter.Store.Review).MatchRanking(r.Findings(), parsed, .matched, .problem) Set ranking = matched
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
