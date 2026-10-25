/// One production review (CONTRACTS 13): a read-only pass over one production's effective settings, its event log's
/// errors and its messages' failures over a window, tied to the cases Shutter opened for it, as Shutter.Review.Sweep
/// wrote it; and, when the review agent ran, its ranking of the findings within their severity tiers with the run's
/// model, tokens and cost. The deterministic part stands whole whatever the agent did. Kept: the last 50 per production.
Class Shutter.Store.Review Extends (%Persistent, %JSON.Adaptor)
{

/// PR-nnnnnn
Property ReviewId As %String(%JSONFIELDNAME = "reviewId", MAXLEN = 32) [ Required ];

Index ReviewIdx On ReviewId [ Unique ];

Property Namespace As %String(%JSONFIELDNAME = "namespace", MAXLEN = 64);

Property Production As %String(%JSONFIELDNAME = "production", MAXLEN = 128);

Index TargetIdx On (Namespace, Production);

/// The production's state as the reader saw it (running, stopped, suspended, troubled, another production running, ...).
Property ProductionState As %String(%JSONFIELDNAME = "productionState", MAXLEN = 64);

Property WindowDays As %Integer(%JSONFIELDNAME = "windowDays");

Property WindowFrom As %String(%JSONFIELDNAME = "windowFrom", MAXLEN = 30);

Property WindowTo As %String(%JSONFIELDNAME = "windowTo", MAXLEN = 30);

Property StartedAt As %String(%JSONFIELDNAME = "startedAt", MAXLEN = 30);

Property FinishedAt As %String(%JSONFIELDNAME = "finishedAt", MAXLEN = 30);

/// sweeping (the reader and the checks run), ranking (the agent was asked), done, failed (the sweep itself failed).
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 16, VALUELIST = ",sweeping,ranking,done,failed") [ InitialExpression = "sweeping" ];

Index StateIdx On State;

/// SHA-256 over the sorted configuration findings' code, item, setting and found values (Shutter.Review.Sweep.Fingerprint):
/// no counts, ids or times, so it is the same on every instance that reaches the same configuration.
Property Fingerprint As %String(%JSONFIELDNAME = "fingerprint", MAXLEN = 80);

/// The findings in baseline rank order, as the sweep wrote them: the agent's exact input.
Property FindingsJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

Property SummaryJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// The per-item case aggregates over the window (counts only, never note text or identifiers).
Property CaseAggregatesJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// Whether the namespace could not be read (then the one finding is NAMESPACE_UNREADABLE).
Property Unreadable As %Boolean(%JSONFIELDNAME = "unreadable") [ InitialExpression = 0 ];

Property RequestedBy As %String(%JSONFIELDNAME = "requestedBy", MAXLEN = 100);

/// Why the sweep failed, when it did.
Property Error As %String(%JSONFIELDNAME = "error", MAXLEN = 2000);

// ---- the agent's part ----

/// pending (the sweep runs, or the agent was asked), ok, no_record, skipped (not asked, or nothing to rank),
/// schema_failed (the ranking was refused; the baseline order stands), error.
Property AgentState As %String(%JSONFIELDNAME = "agentState", MAXLEN = 16) [ InitialExpression = "pending" ];

/// live, record or replay, as the bridge reported it; empty until the agent answered.
Property Mode As %String(%JSONFIELDNAME = "mode", MAXLEN = 16);

Property Model As %String(%JSONFIELDNAME = "model", MAXLEN = 100);

Property ProviderConfig As %String(%JSONFIELDNAME = "providerConfig", MAXLEN = 100);

Property PromptTokens As %Integer(%JSONFIELDNAME = "promptTokens");

Property CompletionTokens As %Integer(%JSONFIELDNAME = "completionTokens");

Property CacheReadTokens As %Integer(%JSONFIELDNAME = "cacheReadTokens");

Property CacheCreationTokens As %Integer(%JSONFIELDNAME = "cacheCreationTokens");

/// Estimated cost in US dollars from Shutter.Store.ModelPrice; 0 for a replay or a run the API mimic answered.
Property CostUSD As %Numeric(%JSONFIELDNAME = "costUsd", SCALE = 6);

Property DurationMs As %Integer(%JSONFIELDNAME = "durationMs");

/// The agent's accepted result (ranking, summary, unknowns), as JSON; empty unless AgentState is ok.
Property RankingJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// The persisted agent session, when the runner kept one.
Property SessionId As %String(%JSONFIELDNAME = "sessionId", MAXLEN = 50);

/// The production message that carried the agent request: the Visual Trace link for the run.
Property EnsMessageId As %String(%JSONFIELDNAME = "ensMessageId", MAXLEN = 20);

/// The key the agent's run is recorded and replayed under: review:<namespace>:<production>|review|<version>|<fingerprint>.
Property RecordKey As %String(%JSONFIELDNAME = "recordKey", MAXLEN = 300);

/// What went wrong on the agent's side (the bridge's status and error, the refused ranking's problem, a timeout).
Property AgentError As %String(%JSONFIELDNAME = "agentError", MAXLEN = 2000);

/// A review still sweeping or ranking after this many seconds was left behind (a restart in the middle of it, an
/// answer that never came): it no longer counts as running, and the next review of the production fails it.
Parameter STALEAFTERSECONDS = 1200;

/// Open a review of a production: a PR- id from the counter, state sweeping, the window as asked. A review of the same
/// production left behind (STALEAFTERSECONDS) is failed first, so it never blocks this one.
ClassMethod Create(namespace As %String, production As %String, requestedBy As %String, windowDays As %Integer, Output r As Shutter.Store.Review) As %Status
{
    Set r = ""
    If (namespace = "") || (production = "") Quit $$$ERROR($$$GeneralError, "A review needs a namespace and a production")
    Do ..CloseStale(namespace, production)
    Set days = +windowDays
    If days < 1 Set days = 7
    If days > 90 Set days = 90
    Set r = ..%New()
    Set r.ReviewId = "PR-" _ $TRANSLATE($JUSTIFY($INCREMENT(^Shutter.Counter("review")), 6), " ", "0")
    Set r.Namespace = namespace, r.Production = production, r.RequestedBy = requestedBy
    Set r.WindowDays = days, r.State = "sweeping", r.AgentState = "pending"
    Set r.StartedAt = ##class(Shutter.Util.Time).NowUTC()
    // Provisional: the sweep's own window replaces these in StoreSweep.
    Set r.WindowTo = r.StartedAt, r.WindowFrom = ##class(Shutter.Util.Time).FromNow(-(days * 86400))
    Quit r.%Save()
}

/// Store the sweep's result (Shutter.Review.Sweep.Run): the production's state, the window, the fingerprint, the findings,
/// the summary and the case aggregates. With agent 1 and findings to rank in a namespace that could be read, the review
/// goes on to ranking under recordKey (the agent's part is pending); otherwise it is done now, the agent skipped.
Method StoreSweep(result As %DynamicObject, agent As %Boolean = 0, recordKey As %String = "") As %Status
{
    If '$ISOBJECT(result) Quit ..Fail("The sweep returned no result")
    Set ..ProductionState = $EXTRACT(##class(Shutter.Util.Json).Str(result, "productionState"), 1, 64)
    Set w = result.%Get("window")
    If $ISOBJECT(w) {
        Set days = +##class(Shutter.Util.Json).Str(w, "days", ..WindowDays)
        If days > 0 Set ..WindowDays = days
        Set from = ##class(Shutter.Util.Json).Str(w, "from"), to = ##class(Shutter.Util.Json).Str(w, "to")
        If from '= "" Set ..WindowFrom = from
        If to '= "" Set ..WindowTo = to
    }
    Set ..Fingerprint = $EXTRACT(##class(Shutter.Util.Json).Str(result, "fingerprint"), 1, 80)
    Set findings = result.%Get("findings")
    Set ..FindingsJSON = $SELECT($ISOBJECT(findings): findings.%ToJSON(), 1: "[]")
    Set summary = result.%Get("summary")
    Set ..SummaryJSON = $SELECT($ISOBJECT(summary): summary.%ToJSON(), 1: "{}")
    Set agg = result.%Get("caseAggregates")
    Set ..CaseAggregatesJSON = $SELECT($ISOBJECT(agg): agg.%ToJSON(), 1: "{}")
    Set ..Unreadable = ##class(Shutter.Util.Json).Bool(result, "unreadable", 0)
    Set n = $SELECT($ISOBJECT(findings): findings.%Size(), 1: 0)
    If agent && (n > 0) && '..Unreadable {
        Set ..State = "ranking", ..AgentState = "pending", ..RecordKey = recordKey, ..FinishedAt = ""
    } Else {
        Set ..State = "done", ..AgentState = "skipped", ..FinishedAt = ##class(Shutter.Util.Time).NowUTC()
    }
    Quit ..%Save()
}

/// The sweep itself failed: the review is failed with the reason, the agent skipped.
Method Fail(error As %String) As %Status
{
    Set ..State = "failed", ..Error = $EXTRACT(error, 1, 2000)
    Set ..AgentState = "skipped", ..FinishedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit ..%Save()
}

/// Store the agent's answer (Shutter.Bridge.Msg.AgentResponse). ranking is the agent's result once the process validated
/// it (RankingProblem), else ""; problem is why it was refused (then the agent's part is schema_failed and the baseline
/// order stands); ensMessageId the production message that carried the request. The review is done either way.
Method StoreAgent(response As Shutter.Bridge.Msg.AgentResponse, ranking As %DynamicObject = "", problem As %String = "", ensMessageId As %String = "") As %Status
{
    If $ISOBJECT(response) {
        Set ..Mode = response.Mode, ..Model = response.Model, ..ProviderConfig = response.ProviderConfig
        Set ..PromptTokens = +response.PromptTokens, ..CompletionTokens = +response.CompletionTokens
        Set ..CacheReadTokens = +response.CacheReadTokens, ..CacheCreationTokens = +response.CacheCreationTokens
        Set ..DurationMs = +response.DurationMs, ..SessionId = response.SessionId
        // A replayed run spends nothing, nor does one the API mimic answered (model mock): their tokens are kept for the record.
        Set ..CostUSD = $SELECT(response.Mode = "replay": 0, response.Model = "mock": 0, 1: ##class(Shutter.Store.ModelPrice).Cost(response.Model, response.PromptTokens, response.CompletionTokens, response.CacheReadTokens, response.CacheCreationTokens))
        If (response.Status = "ok") && '$ISOBJECT(ranking) && (problem = "") Set problem = "The agent answered without a ranking"
    } ElseIf problem = "" {
        Set problem = "No response from the agent"
    }
    If ensMessageId '= "" Set ..EnsMessageId = ensMessageId
    If $ISOBJECT(ranking) {
        Set ..AgentState = "ok", ..RankingJSON = ranking.%ToJSON(), ..AgentError = ""
    } ElseIf problem '= "" {
        Set ..AgentState = $SELECT($ISOBJECT(response) && (response.Status = "ok"): "schema_failed", 1: "error"), ..AgentError = $EXTRACT(problem, 1, 2000)
    } ElseIf response.Status = "no_record" {
        Set ..AgentState = "no_record", ..AgentError = $EXTRACT(response.Error, 1, 2000)
    } Else {
        Set ..AgentState = "error", ..AgentError = $EXTRACT(response.Status _ $SELECT(response.Error '= "": ": " _ response.Error, 1: ""), 1, 2000)
    }
    Set ..State = "done", ..FinishedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit ..%Save()
}

/// The agent's part failed without an answer (the call failed, or the time was up): the review is done with the baseline order.
Method AgentFailed(error As %String) As %Status
{
    Set ..AgentState = "error", ..AgentError = $EXTRACT(error, 1, 2000)
    Set ..State = "done", ..FinishedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit ..%Save()
}

/// The findings as stored, a dynamic array (empty before the sweep stored them).
Method Findings() As %DynamicArray
{
    Set out = ##class(Shutter.Util.Json).Parse(..FindingsJSON, .sc)
    If '$ISOBJECT(out) || 'out.%IsA("%Library.DynamicArray") Quit []
    Quit out
}

/// The stored finding with this id (F1, F2, ...), or "".
Method Finding(findingId As %String) As %DynamicObject
{
    Set found = ""
    Set iter = ..Findings().%GetIterator()
    While iter.%GetNext(.i, .f) {
        Continue:'$ISOBJECT(f)
        If ##class(Shutter.Util.Json).Str(f, "id") = findingId Set found = f Quit
    }
    Quit found
}

/// The severity tier of a finding: 1 high, 2 medium, 3 low, 4 info; 5 for anything else.
ClassMethod TierOf(severity As %String) As %Integer
{
    Quit $CASE($ZCONVERT(severity, "L"), "high": 1, "medium": 2, "low": 3, "info": 4, : 5)
}

/// Matches a ranking to this review's findings and gives back the ranking as stored (v1.22). A ranking entry carries the
/// finding's code, item and setting beside its finding_id (Shutter.Schema.ReviewRank), so a recording made on another
/// instance is matched by (code, item, setting), in rank order, each current finding at most once; an entry without them
/// is matched by finding_id. Entries with no current finding are dropped, current findings with no entry stay unexplained,
/// and the matched entries keep their recorded order, re-ranked 1 to m. problem names what refuses the whole ranking: a
/// shape that is not a ranking, a finding ranked twice, a tier order that goes up again, or no entry matching at all.
/// Returns 1 when the matched ranking can be stored.
ClassMethod MatchRanking(findings As %DynamicArray, ranking As %DynamicObject, Output matched As %DynamicObject, Output problem As %String) As %Boolean
{
    Set matched = "", problem = ""
    If '$ISOBJECT(ranking) || 'ranking.%IsA("%Library.DynamicObject") Set problem = "The ranking is not a JSON object" Quit 0
    Set list = ranking.%Get("ranking")
    If '$ISOBJECT(list) || 'list.%IsA("%Library.DynamicArray") Set problem = "ranking must be an array of {finding_id, rank, explanation}" Quit 0
    Set json = "Shutter.Util.Json"
    // The current findings: by id, and by (code, item, setting) in baseline order.
    Set n = 0
    If $ISOBJECT(findings) {
        Set iter = findings.%GetIterator()
        While iter.%GetNext(.i, .f) {
            Set id = $CLASSMETHOD(json, "Str", f, "id")
            Continue:id=""
            Set n = n + 1
            Set tier(id) = ..TierOf($CLASSMETHOD(json, "Str", f, "severity")), sev(id) = $CLASSMETHOD(json, "Str", f, "severity")
            Set key = $CLASSMETHOD(json, "Str", f, "code") _ "|" _ $CLASSMETHOD(json, "Str", f, "item") _ "|" _ $CLASSMETHOD(json, "Str", f, "setting")
            Set byKey(key, n) = id
        }
    }
    // The entries in rank order.
    Set liter = list.%GetIterator()
    While liter.%GetNext(.i, .e) {
        If '$ISOBJECT(e) || 'e.%IsA("%Library.DynamicObject") Set problem = "Entry " _ (i + 1) _ " of the ranking is not an object" Quit
        Set eid = $CLASSMETHOD(json, "Str", e, "finding_id")
        If eid = "" Set problem = "Entry " _ (i + 1) _ " of the ranking names no finding_id" Quit
        If $DATA(seenEntry(eid)) Set problem = "The ranking names " _ eid _ " twice" Quit
        Set seenEntry(eid) = 1
        Set rank = $CLASSMETHOD(json, "Str", e, "rank")
        If (rank = "") || (rank '= +rank) || (+rank '= (+rank \ 1)) || (+rank < 1) Set problem = "The rank of " _ eid _ " must be a whole number from 1, not '" _ rank _ "'" Quit
        Set order(+rank, i) = i
    }
    If problem '= "" Quit 0
    Set out = [], dropped = 0, lastTier = "", lastId = ""
    Set rank = ""
    For {
        Set rank = $ORDER(order(rank))
        Quit:rank=""
        Set pos = ""
        For {
            Set pos = $ORDER(order(rank, pos))
            Quit:pos=""
            Set e = list.%Get(pos)
            Set code = $CLASSMETHOD(json, "Str", e, "code"), id = ""
            If code '= "" {
                Set key = code _ "|" _ $CLASSMETHOD(json, "Str", e, "item") _ "|" _ $CLASSMETHOD(json, "Str", e, "setting")
                Set k = $ORDER(byKey(key, ""))
                If k '= "" Set id = byKey(key, k) Kill byKey(key, k)
            } Else {
                Set eid = $CLASSMETHOD(json, "Str", e, "finding_id")
                If $DATA(tier(eid)) && '$DATA(used(eid)) Set id = eid
            }
            If (id = "") || $DATA(used(id)) Set dropped = dropped + 1 Continue
            Set used(id) = 1
            If (lastTier '= "") && (tier(id) < lastTier) Set problem = id _ " (" _ sev(id) _ ") is ranked below " _ lastId _ " (" _ sev(lastId) _ "): a finding never ranks above one of a higher severity tier" Quit
            Set lastTier = tier(id), lastId = id
            Set m = {}
            Set m."finding_id" = id, m.rank = out.%Size() + 1
            Set m.explanation = $CLASSMETHOD(json, "Str", e, "explanation"), m."confidence_note" = $CLASSMETHOD(json, "Str", e, "confidence_note")
            Set m.code = $CLASSMETHOD(json, "Str", e, "code"), m.item = $CLASSMETHOD(json, "Str", e, "item"), m.setting = $CLASSMETHOD(json, "Str", e, "setting")
            Do out.%Push(m)
        }
        Quit:problem'=""
    }
    If problem '= "" Quit 0
    If out.%Size() = 0 Set problem = "No entry of the ranking matches a finding of this review (by code, item and setting)" Quit 0
    Set matched = {}
    Set matched.ranking = out
    Set matched.dropped = dropped, matched.unexplained = n - out.%Size(), matched."recorded_entries" = list.%Size()
    Set matched.summary = $CLASSMETHOD(json, "Str", ranking, "summary")
    Set matched.unknowns = $SELECT($ISOBJECT(ranking.%Get("unknowns")): ranking.%Get("unknowns"), 1: [])
    Quit 1
}

/// What is wrong with an agent's ranking of these findings, or "" when it stands: the result must be an object whose
/// ranking lists every finding id exactly once with ranks 1 to n and no gaps, and no finding of a lower severity tier
/// may be ranked above one of a higher tier (the agent reorders within tiers only). Pure, so a test can call it.
ClassMethod RankingProblem(findings As %DynamicArray, ranking As %DynamicObject) As %String
{
    If '$ISOBJECT(ranking) || 'ranking.%IsA("%Library.DynamicObject") Quit "The ranking is not a JSON object"
    Set list = ranking.%Get("ranking")
    If '$ISOBJECT(list) || 'list.%IsA("%Library.DynamicArray") Quit "ranking must be an array of {finding_id, rank, explanation}"
    Set n = 0
    If $ISOBJECT(findings) {
        Set iter = findings.%GetIterator()
        While iter.%GetNext(.i, .f) {
            Set id = ##class(Shutter.Util.Json).Str(f, "id")
            Continue:id=""
            Set n = n + 1, tier(id) = ..TierOf(##class(Shutter.Util.Json).Str(f, "severity")), sev(id) = ##class(Shutter.Util.Json).Str(f, "severity")
        }
    }
    If list.%Size() '= n Quit "The ranking has " _ list.%Size() _ " entries for " _ n _ " findings"
    Set problem = ""
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .e) {
        If '$ISOBJECT(e) || 'e.%IsA("%Library.DynamicObject") Set problem = "Entry " _ (i + 1) _ " of the ranking is not an object" Quit
        Set id = ##class(Shutter.Util.Json).Str(e, "finding_id")
        If id = "" Set problem = "Entry " _ (i + 1) _ " of the ranking names no finding_id" Quit
        If '$DATA(tier(id)) Set problem = "The ranking names " _ id _ ", which is not a finding of this review" Quit
        If $DATA(seen(id)) Set problem = "The ranking names " _ id _ " twice" Quit
        Set seen(id) = 1
        Set rank = ##class(Shutter.Util.Json).Str(e, "rank")
        If (rank = "") || (rank '= +rank) || (+rank '= (+rank \ 1)) || (+rank < 1) || (+rank > n) Set problem = "The rank of " _ id _ " must be a whole number from 1 to " _ n _ ", not '" _ rank _ "'" Quit
        If $DATA(at(+rank)) Set problem = "Rank " _ +rank _ " is given twice (" _ at(+rank) _ " and " _ id _ ")" Quit
        Set at(+rank) = id
    }
    If problem '= "" Quit problem
    // Every id once, n ranks, each in 1..n and distinct: the ranks are 1..n without gaps. Now the tiers must not go up again.
    For rank = 2:1:n {
        Set above = at(rank - 1), below = at(rank)
        If tier(below) < tier(above) Set problem = below _ " (" _ sev(below) _ ") is ranked below " _ above _ " (" _ sev(above) _ "): a finding never ranks above one of a higher severity tier" Quit
    }
    Quit problem
}

/// The review as the API shows it (CONTRACTS 13). full (the default) is GET /production-reviews/{id}: the window, the
/// fingerprint, the findings in baseline order with their annotation status as it stands now (an annotation that
/// expired or was revoked reopens the finding) and the agent's rank and explanation when it answered, the case
/// aggregates and the agent's part. full 0 is the list's item: identity, times, states and the summary.
Method ToObject(full As %Boolean = 1) As %DynamicObject
{
    Set o = {}
    Set o.reviewId = ..ReviewId, o.namespace = ..Namespace, o.production = ..Production
    Set o.productionState = ..ProductionState
    Set o.startedAt = ..StartedAt
    If ..FinishedAt '= "" { Set o.finishedAt = ..FinishedAt } Else { Do o.%Set("finishedAt", "", "null") }
    Set o.state = ..State, o.agentState = ..AgentState
    Set summary = ##class(Shutter.Util.Json).Parse(..SummaryJSON, .ssc)
    If '$ISOBJECT(summary) || 'summary.%IsA("%Library.DynamicObject") Set summary = {}
    If 'full {
        Set o.summary = summary
        Set o.requestedBy = ..RequestedBy
        Quit o
    }
    Set o.requestedBy = ..RequestedBy, o.error = ..Error
    Set w = {}
    Set w.days = +..WindowDays, w.from = ..WindowFrom, w.to = ..WindowTo
    Set o.window = w
    Set o.fingerprint = ..Fingerprint
    Do o.%Set("unreadable", $SELECT(..Unreadable: 1, 1: 0), "boolean")
    Set findings = ..Findings()
    // The annotations as they stand now: each finding starts new and takes the status of a matching unexpired, unrevoked
    // annotation (Shutter.Review.Sweep.ApplyAnnotations); a failure there leaves every finding new.
    Set iter = findings.%GetIterator()
    While iter.%GetNext(.i, .f) {
        Continue:'$ISOBJECT(f)
        Set f.status = "new", f.annotationId = ""
    }
    If findings.%Size() > 0 {
        Try {
            Do ##class(Shutter.Review.Sweep).ApplyAnnotations(findings, ..Namespace, ..Production)
        } Catch ex {
        }
    }
    // The agent's rank and explanation (v1.22): the stored ranking's entries name current findings (MatchRanking). Every
    // finding gets a rank: within each severity tier the explained findings first, in the agent's order, then the
    // unexplained ones in baseline order; the ranks run 1 to n over the tiers in order.
    Set ranking = ""
    If (..AgentState = "ok") && (..RankingJSON '= "") Set ranking = ##class(Shutter.Util.Json).Parse(..RankingJSON, .rsc)
    If $ISOBJECT(ranking) && ranking.%IsA("%Library.DynamicObject") {
        Set list = ranking.%Get("ranking")
        If $ISOBJECT(list) && list.%IsA("%Library.DynamicArray") {
            Set liter = list.%GetIterator()
            While liter.%GetNext(.i, .e) {
                Continue:'$ISOBJECT(e)
                Set id = ##class(Shutter.Util.Json).Str(e, "finding_id")
                Continue:id=""
                Set rankOf(id) = +##class(Shutter.Util.Json).Str(e, "rank", 0), explanationOf(id) = ##class(Shutter.Util.Json).Str(e, "explanation")
            }
        }
    }
    Set intended = 0, explained = $DATA(rankOf) > 0
    Set iter = findings.%GetIterator()
    While iter.%GetNext(.i, .f) {
        Continue:'$ISOBJECT(f)
        Set id = ##class(Shutter.Util.Json).Str(f, "id")
        Set t = ..TierOf(##class(Shutter.Util.Json).Str(f, "severity"))
        If $DATA(rankOf(id)) && (rankOf(id) > 0) {
            Set f.explanation = explanationOf(id), slot(t, 0, rankOf(id)) = id
        } Else {
            Set f.explanation = "", slot(t, 1, i) = id
        }
        Do f.%Set("rank", "", "null")
        Set byId(id) = f
        If ##class(Shutter.Util.Json).Str(f, "status", "new") '= "new" Set intended = intended + 1
    }
    If explained {
        Set next = 0, t = ""
        For {
            Set t = $ORDER(slot(t))
            Quit:t=""
            For group = 0, 1 {
                Set k = ""
                For {
                    Set k = $ORDER(slot(t, group, k), 1, id)
                    Quit:k=""
                    Set next = next + 1
                    Set byId(id).rank = next
                }
            }
        }
    }
    Set summary.intended = intended
    Set o.summary = summary
    Set o.findings = findings
    Set agg = ##class(Shutter.Util.Json).Parse(..CaseAggregatesJSON, .asc)
    If '$ISOBJECT(agg) Set agg = {}
    Set o.caseAggregates = agg
    Set a = {}
    Set a.state = ..AgentState
    If ..Mode '= "" {
        Set a.mode = ..Mode, a.model = ..Model, a.providerConfig = ..ProviderConfig
        Set a.costUsd = +..CostUSD, a.promptTokens = +..PromptTokens, a.completionTokens = +..CompletionTokens
        Set a.cacheReadTokens = +..CacheReadTokens, a.cacheCreationTokens = +..CacheCreationTokens
        Set a.durationMs = +..DurationMs
    } Else {
        For key = "mode", "model", "providerConfig", "costUsd", "promptTokens", "completionTokens", "cacheReadTokens", "cacheCreationTokens", "durationMs" Do a.%Set(key, "", "null")
    }
    If ..RecordKey '= "" { Set a.recordKey = ..RecordKey } Else { Do a.%Set("recordKey", "", "null") }
    If ..EnsMessageId '= "" { Set a.ensMessageId = ..EnsMessageId } Else { Do a.%Set("ensMessageId", "", "null") }
    Set a.error = ..AgentError
    // How much of the agent's ranking reached these findings (v1.22): null until it answered.
    For key = "explained", "unexplained", "dropped", "recordedEntries" Do a.%Set(key, "", "null")
    If $ISOBJECT(ranking) && ranking.%IsA("%Library.DynamicObject") {
        Set list = ranking.%Get("ranking")
        Set a.explained = $SELECT($ISOBJECT(list): list.%Size(), 1: 0)
        Set a.unexplained = +##class(Shutter.Util.Json).Str(ranking, "unexplained", 0), a.dropped = +##class(Shutter.Util.Json).Str(ranking, "dropped", 0)
        Set a.recordedEntries = +##class(Shutter.Util.Json).Str(ranking, "recorded_entries", $SELECT($ISOBJECT(list): list.%Size(), 1: 0))
    }
    Set a.summary = $SELECT($ISOBJECT(ranking): ##class(Shutter.Util.Json).Str(ranking, "summary"), 1: "")
    Set unknowns = $SELECT($ISOBJECT(ranking): ranking.%Get("unknowns"), 1: "")
    If '$ISOBJECT(unknowns) || 'unknowns.%IsA("%Library.DynamicArray") Set unknowns = []
    Set a.unknowns = unknowns
    Set o.agent = a
    Quit o
}

ClassMethod ByReviewId(id As %String) As Shutter.Store.Review
{
    Set rid = ""
    &sql(SELECT ID INTO :rid FROM Shutter_Store.Review WHERE ReviewId = :id)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ..%OpenId(rid)
}

/// The newest reviews, newest first, as list items (ToObject 0); an empty namespace or production filters nothing.
/// sc carries an SQL error (the list is then empty), so a reader never takes a failed query for an empty table.
ClassMethod List(namespace As %String = "", production As %String = "", limit As %Integer = 50, Output sc As %Status) As %DynamicArray
{
    Set sc = $$$OK, out = []
    Set limit = +limit
    If limit < 1 Set limit = 50
    If limit > 500 Set limit = 500
    Set where = "", args = 0
    If namespace '= "" Set where = where _ " AND Namespace = ?", args = args + 1, args(args) = namespace
    If production '= "" Set where = where _ " AND Production = ?", args = args + 1, args(args) = production
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ limit _ " ID FROM Shutter_Store.Review WHERE 1=1" _ where _ " ORDER BY ID DESC", args...)
    If rs.%SQLCODE < 0 Set sc = ..SqlError(rs) Quit out
    While rs.%Next() {
        Set r = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(r)
        Do out.%Push(r.ToObject(0))
    }
    Quit out
}

/// How many reviews there are for the filter List takes; sc carries an SQL error (the count is then 0).
ClassMethod Count(namespace As %String = "", production As %String = "", Output sc As %Status) As %Integer
{
    Set sc = $$$OK, where = "", args = 0
    If namespace '= "" Set where = where _ " AND Namespace = ?", args = args + 1, args(args) = namespace
    If production '= "" Set where = where _ " AND Production = ?", args = args + 1, args(args) = production
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N FROM Shutter_Store.Review WHERE 1=1" _ where, args...)
    If rs.%SQLCODE < 0 Set sc = ..SqlError(rs) Quit 0
    Quit $SELECT(rs.%Next(): +rs.%Get("N"), 1: 0)
}

/// A failed query as a status: the SQLCODE and the message, so the caller can say what the store could not read.
ClassMethod SqlError(rs As %SQL.StatementResult) As %Status [ Private ]
{
    Quit $$$ERROR($$$GeneralError, "Shutter_Store.Review query failed: SQLCODE " _ rs.%SQLCODE _ ": " _ rs.%Message)
}

/// The review of a production still sweeping or ranking (and started within STALEAFTERSECONDS), or "".
ClassMethod Running(namespace As %String, production As %String, Output sc As %Status) As Shutter.Store.Review
{
    Set sc = $$$OK, since = ##class(Shutter.Util.Time).FromNow(-..#STALEAFTERSECONDS)
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM Shutter_Store.Review WHERE Namespace = ? AND Production = ? AND State IN ('sweeping', 'ranking') AND StartedAt >= ? ORDER BY ID DESC", namespace, production, since)
    If rs.%SQLCODE < 0 Set sc = ..SqlError(rs) Quit ""
    If 'rs.%Next() Quit ""
    Quit ..%OpenId(rs.%Get("ID"))
}

/// Fail the reviews of a production left sweeping or ranking for longer than STALEAFTERSECONDS. Returns how many.
ClassMethod CloseStale(namespace As %String, production As %String, Output sc As %Status) As %Integer
{
    Set sc = $$$OK, n = 0, since = ##class(Shutter.Util.Time).FromNow(-..#STALEAFTERSECONDS)
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Review WHERE Namespace = ? AND Production = ? AND State IN ('sweeping', 'ranking') AND StartedAt < ?", namespace, production, since)
    If rs.%SQLCODE < 0 Set sc = ..SqlError(rs) Quit 0
    While rs.%Next() { Set n = n + 1, ids(n) = rs.%Get("ID") }
    For i = 1:1:n {
        Set r = ..%OpenId(ids(i))
        Continue:'$ISOBJECT(r)
        Do r.Fail("The review did not finish within " _ (..#STALEAFTERSECONDS \ 60) _ " minutes (a restart in the middle of it, or an answer that never came); recorded as failed when the next review started")
    }
    Quit n
}

/// Keep the newest reviews of a production and delete the rest. Returns how many were deleted.
ClassMethod Trim(namespace As %String, production As %String, keep As %Integer = 50, Output sc As %Status) As %Integer
{
    Set sc = $$$OK, n = 0, seen = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Review WHERE Namespace = ? AND Production = ? ORDER BY ID DESC", namespace, production)
    If rs.%SQLCODE < 0 Set sc = ..SqlError(rs) Quit 0
    While rs.%Next() {
        Set seen = seen + 1
        Continue:seen<=keep
        Set n = n + 1, ids(n) = rs.%Get("ID")
    }
    Set deleted = 0
    For i = 1:1:n {
        If $$$ISOK(..%DeleteId(ids(i))) Set deleted = deleted + 1
    }
    Quit deleted
}

Storage Default
{
<Data name="ReviewDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>ReviewId</Value>
</Value>
<Value name="3">
<Value>Namespace</Value>
</Value>
<Value name="4">
<Value>Production</Value>
</Value>
<Value name="5">
<Value>ProductionState</Value>
</Value>
<Value name="6">
<Value>WindowDays</Value>
</Value>
<Value name="7">
<Value>WindowFrom</Value>
</Value>
<Value name="8">
<Value>WindowTo</Value>
</Value>
<Value name="9">
<Value>StartedAt</Value>
</Value>
<Value name="10">
<Value>FinishedAt</Value>
</Value>
<Value name="11">
<Value>State</Value>
</Value>
<Value name="12">
<Value>Fingerprint</Value>
</Value>
<Value name="13">
<Value>FindingsJSON</Value>
</Value>
<Value name="14">
<Value>SummaryJSON</Value>
</Value>
<Value name="15">
<Value>CaseAggregatesJSON</Value>
</Value>
<Value name="16">
<Value>Unreadable</Value>
</Value>
<Value name="17">
<Value>RequestedBy</Value>
</Value>
<Value name="18">
<Value>Error</Value>
</Value>
<Value name="19">
<Value>AgentState</Value>
</Value>
<Value name="20">
<Value>Mode</Value>
</Value>
<Value name="21">
<Value>Model</Value>
</Value>
<Value name="22">
<Value>ProviderConfig</Value>
</Value>
<Value name="23">
<Value>PromptTokens</Value>
</Value>
<Value name="24">
<Value>CompletionTokens</Value>
</Value>
<Value name="25">
<Value>CacheReadTokens</Value>
</Value>
<Value name="26">
<Value>CacheCreationTokens</Value>
</Value>
<Value name="27">
<Value>CostUSD</Value>
</Value>
<Value name="28">
<Value>DurationMs</Value>
</Value>
<Value name="29">
<Value>RankingJSON</Value>
</Value>
<Value name="30">
<Value>SessionId</Value>
</Value>
<Value name="31">
<Value>EnsMessageId</Value>
</Value>
<Value name="32">
<Value>RecordKey</Value>
</Value>
<Value name="33">
<Value>AgentError</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.ReviewD</DataLocation>
<DefaultData>ReviewDefaultData</DefaultData>
<IdLocation>^Shutter.Store.ReviewD</IdLocation>
<IndexLocation>^Shutter.Store.ReviewI</IndexLocation>
<StreamLocation>^Shutter.Store.ReviewS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
