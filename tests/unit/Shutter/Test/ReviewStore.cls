/// The production review's store (Shutter.Store.Review and Shutter.Store.ReviewAnnotation; CONTRACTS 13), with no
/// production and no sweep: the reviews are of a production that does not exist (UT.Review.Production in the namespace
/// UTREVIEW), their findings are fabricated in the sweep's shape, and every row made here is deleted after each test. The
/// review counter is put back when nothing else moved it meanwhile, so the tests take no public review number. The
/// annotation tests go through the sweep's own ApplyAnnotations and ValueFingerprint (Shutter.Review.Sweep), so a second
/// review's matching finding is seen to carry the status the way a real review would.
Class Shutter.Test.ReviewStore Extends %UnitTest.TestCase
{

Parameter NS = "UTREVIEW";

Parameter PROD = "UT.Review.Production";

Parameter FINGERPRINT = "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8";

/// The counter's value before the test, and how many reviews the test opened.
Property CounterBefore As %String;

Property Made As %Integer [ InitialExpression = 0 ];

Method OnBeforeAllTests() As %Status
{
    // Rows a run that stopped half-way may have left.
    Do ..PurgeAll()
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set ..CounterBefore = $GET(^Shutter.Counter("review")), ..Made = 0
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..PurgeAll()
    // The counter goes back when only this test moved it.
    If $GET(^Shutter.Counter("review")) = (+..CounterBefore + ..Made) {
        If ..CounterBefore = "" { Kill ^Shutter.Counter("review") } Else { Set ^Shutter.Counter("review") = ..CounterBefore }
    }
    Quit $$$OK
}

ClassMethod PurgeAll()
{
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.ReviewAnnotation WHERE Production = ?", ..#PROD)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.Review WHERE Production = ?", ..#PROD)
}

/// A ranking is matched to the findings by code, item and setting (v1.22): a recording whose numbers differ still explains
/// the findings that are here; what matches nothing is dropped; what has no entry stays unexplained; the tiers hold.
Method TestMatchRanking()
{
    Set findings = [{"id": "F1", "code": "PURGE_MISSING", "item": "", "setting": "", "severity": "high"}, {"id": "F2", "code": "ERRORS_GROUPED", "item": "ADT to Downstream", "setting": "", "severity": "medium"}, {"id": "F3", "code": "ALERTING_OFF", "item": "", "setting": "AlertOnError", "severity": "medium"}, {"id": "F4", "code": "QUEUE_ALERTS_OFF", "item": "", "setting": "QueueCountAlert", "severity": "low"}]
    // Recorded on another instance: other numbers, an item that is not here, and no entry for the queue alerts.
    Set recorded = {"summary": "s", "unknowns": ["u"], "ranking": [{"finding_id": "F7", "rank": 1, "explanation": "purge", "code": "PURGE_MISSING", "item": "", "setting": ""}, {"finding_id": "F2", "rank": 2, "explanation": "gone", "code": "ERRORS_GROUPED", "item": "ADT to Ward", "setting": ""}, {"finding_id": "F3", "rank": 3, "explanation": "alerting", "code": "ALERTING_OFF", "item": "", "setting": "AlertOnError"}, {"finding_id": "F5", "rank": 4, "explanation": "errors", "code": "ERRORS_GROUPED", "item": "ADT to Downstream", "setting": ""}]}
    Set ok = ##class(Shutter.Store.Review).MatchRanking(findings, recorded, .matched, .problem)
    Do $$$AssertTrue(ok, "a ranking with matches is accepted: " _ problem)
    Do $$$AssertEquals(matched.ranking.%Size(), 3, "three entries matched a finding")
    Do $$$AssertEquals(matched.dropped, 1, "the entry for an item that is not here is dropped")
    Do $$$AssertEquals(matched.unexplained, 1, "the finding with no entry stays unexplained")
    Do $$$AssertEquals(matched."recorded_entries", 4, "the recording had four entries")
    Do $$$AssertEquals(matched.ranking.%Get(0)."finding_id" _ " " _ matched.ranking.%Get(1)."finding_id" _ " " _ matched.ranking.%Get(2)."finding_id", "F1 F3 F2", "matched by code, item and setting, in the recorded order, with the current ids")
    Do $$$AssertEquals(matched.ranking.%Get(2).rank, 3, "re-ranked 1 to m")
    Do $$$AssertEquals(matched.ranking.%Get(2).explanation, "errors", "each keeps its explanation")
    Do $$$AssertEquals(matched.summary, "s", "and the summary")
    // A ranking whose order puts a lower tier above a higher one is refused whole.
    Set bad = {"ranking": [{"finding_id": "a", "rank": 1, "explanation": "x", "code": "QUEUE_ALERTS_OFF", "item": "", "setting": "QueueCountAlert"}, {"finding_id": "b", "rank": 2, "explanation": "y", "code": "PURGE_MISSING", "item": "", "setting": ""}]}
    Do $$$AssertNotTrue(##class(Shutter.Store.Review).MatchRanking(findings, bad, .m2, .p2), "a low above a high is refused")
    Do $$$AssertTrue(p2 [ "higher severity tier", "naming the tier rule: " _ p2)
    // Nothing matching is refused too.
    Set none = {"ranking": [{"finding_id": "z", "rank": 1, "explanation": "x", "code": "NOTHING", "item": "", "setting": ""}]}
    Do $$$AssertNotTrue(##class(Shutter.Store.Review).MatchRanking(findings, none, .m3, .p3), "no match at all is refused")
    // An entry without code, item and setting is matched by its finding id, as before v1.22.
    Set legacy = {"ranking": [{"finding_id": "F2", "rank": 1, "explanation": "by id"}]}
    Do $$$AssertTrue(##class(Shutter.Store.Review).MatchRanking(findings, legacy, .m4, .p4), "a legacy entry matches by id: " _ p4)
    Do $$$AssertEquals(m4.ranking.%Get(0)."finding_id", "F2", "the id it named")
    Do $$$AssertEquals(m4.unexplained, 3, "the other three stay unexplained")
}

/// A review of the test production, opened as the process opens one.
Method NewReview(Output r As Shutter.Store.Review, days As %Integer = 7, requestedBy As %String = "operator") As %Status
{
    Set sc = ##class(Shutter.Store.Review).Create(..#NS, ..#PROD, requestedBy, days, .r)
    If $$$ISOK(sc) Set ..Made = ..Made + 1
    Quit sc
}

/// One finding in the sweep's shape.
ClassMethod Finding(id As %String, code As %String, severity As %String, item As %String, setting As %String, found As %String) As %DynamicObject
{
    Set f = {}
    Set f.id = id, f.code = code, f.severity = severity, f.confidence = "confirmed"
    Set f.item = item, f.itemClass = $SELECT(item = "": "", 1: "Shutter.Operation.Ward"), f.setting = setting, f.found = found
    Set f.source = $SELECT(setting = "": "observed", 1: "item"), f.suggested = "", f.why = "why " _ code, f.action = "action for " _ code
    Set f.cases = {"count": 0, "unique": 0, "latest": []}
    Set f.evidence = {"count": 0, "latestHeaderId": "", "latestAt": "", "example": "an example that never reaches the model"}
    Set f.status = "new", f.annotationId = ""
    Do f.%Set("rank", "", "null")
    Set f.explanation = ""
    Quit f
}

/// A sweep result with four findings in baseline order: one high, two medium, one low.
ClassMethod Result() As %DynamicObject
{
    Set result = {}
    Set result.namespace = ..#NS, result.production = ..#PROD, result.productionState = "running"
    Set result.window = {"days": 7, "from": "2026-10-18T09:00:00Z", "to": "2026-10-25T09:00:00Z"}
    Set result.fingerprint = ..#FINGERPRINT
    Set result.summary = {"bySeverity": {"high": 1, "medium": 2, "low": 1, "info": 0}, "findings": 4, "intended": 0, "items": 5, "errorsInWindow": 2, "messageErrorsInWindow": 1}
    Set result.findings = []
    Do result.findings.%Push(..Finding("F1", "RETRY_FOREVER", "high", "Downstream Out", "FailureTimeout", "-1"))
    Do result.findings.%Push(..Finding("F2", "NO_ALERT_CONSUMER", "medium", "", "", "no Ens.Alert item"))
    Do result.findings.%Push(..Finding("F3", "GIVES_UP_EARLY", "medium", "Escalation Mail", "FailureTimeout", "5"))
    Do result.findings.%Push(..Finding("F4", "ARCHIVE_IO_ON", "low", "ADT In", "ArchiveIO", "1"))
    Set result.caseAggregates = {"Downstream Out": {"count": 3, "unique": 2, "latest": ["C-000001", "C-000002"]}, "_total": {"count": 3, "unique": 2}}
    Set result.readAt = "2026-10-25T09:00:01Z"
    Do result.%Set("unreadable", 0, "boolean")
    Quit result
}

/// A ranking that stands: F1 first, the two medium findings swapped, F4 last.
ClassMethod GoodRanking() As %DynamicObject
{
    Quit {"ranking": [{"finding_id": "F1", "rank": 1, "explanation": "Retries for ever; consistent with 2 cases in the window"}, {"finding_id": "F3", "rank": 2, "explanation": "Fails before a second try"}, {"finding_id": "F2", "rank": 3, "explanation": "Alerts have nowhere to go"}, {"finding_id": "F4", "rank": 4, "explanation": "Raw I/O is kept"}], "summary": "One high finding leads; the two medium findings are close", "unknowns": ["whether the ward team agreed to the retry policy"]}
}

// ---- the review ----

/// A review opens with a PR- id of six digits, sweeping, the agent's part pending, the window as asked (clamped to 1 to 90
/// days), and is the running review of its production; its list item carries the states and a null finishedAt.
Method TestCreateAndIdForm()
{
    Do $$$AssertStatusOK(..NewReview(.r), "a review opens")
    Do $$$AssertTrue($MATCH(r.ReviewId, "^PR-[0-9]{6}$"), "the id is PR- and six digits: " _ r.ReviewId)
    Do $$$AssertEquals(r.State, "sweeping", "it starts sweeping")
    Do $$$AssertEquals(r.AgentState, "pending", "with the agent's part pending")
    Do $$$AssertEquals(r.WindowDays, 7, "over 7 days")
    Do $$$AssertEquals(r.RequestedBy, "operator", "by who asked")
    Do $$$AssertNotEquals(r.StartedAt, "", "and a start time")
    Do $$$AssertEquals(r.Namespace, ..#NS, "of the namespace")
    Do $$$AssertEquals(r.Production, ..#PROD, "and the production")
    Set again = ##class(Shutter.Store.Review).ByReviewId(r.ReviewId)
    Do $$$AssertTrue($ISOBJECT(again) && (again.%Id() = r.%Id()), "ByReviewId finds it")
    Set running = ##class(Shutter.Store.Review).Running(..#NS, ..#PROD)
    Do $$$AssertTrue($ISOBJECT(running) && (running.ReviewId = r.ReviewId), "it is the running review of the production")
    Do $$$AssertEquals(##class(Shutter.Store.Review).Running(..#NS, "Another.Production"), "", "another production has none")
    Set item = r.ToObject(0)
    Do $$$AssertEquals(item.reviewId, r.ReviewId, "the list item names the review")
    Do $$$AssertEquals(item.state, "sweeping", "its state")
    Do $$$AssertEquals(item.agentState, "pending", "the agent's")
    Do $$$AssertEquals(item.%GetTypeOf("finishedAt"), "null", "finishedAt is null while it runs")
    Do $$$AssertEquals(item.%GetTypeOf("summary"), "object", "and the summary is an object")
    Do $$$AssertEquals(item.%GetTypeOf("findings"), "unassigned", "the list item carries no findings")
    Do $$$AssertStatusOK(..NewReview(.wide, 400), "a wide window opens")
    Do $$$AssertEquals(wide.WindowDays, 90, "clamped to 90 days")
    Do $$$AssertStatusOK(..NewReview(.none, 0), "no window opens")
    Do $$$AssertEquals(none.WindowDays, 7, "as 7 days")
    Do $$$AssertStatusNotOK(##class(Shutter.Store.Review).Create("", ..#PROD, "operator", 7, .bad), "no namespace, no review")
}

/// StoreSweep keeps the sweep's result and the GET shape follows: the window, the fingerprint, the findings in baseline
/// order with rank null and no explanation, the summary, the case aggregates and a skipped agent. With the agent asked
/// the review goes on to ranking under the record key; an unreadable namespace or no result does not.
Method TestStoreSweepAndToObject()
{
    Do $$$AssertStatusOK(..NewReview(.r), "a review opens")
    Set result = ..Result()
    Do $$$AssertStatusOK(r.StoreSweep(result), "the sweep is stored")
    Do $$$AssertEquals(r.State, "done", "the review is done")
    Do $$$AssertEquals(r.AgentState, "skipped", "no agent was asked")
    Do $$$AssertNotEquals(r.FinishedAt, "", "and it is finished")
    Do $$$AssertEquals(r.Fingerprint, ..#FINGERPRINT, "the fingerprint is the sweep's")
    Do $$$AssertEquals(r.WindowFrom, "2026-10-18T09:00:00Z", "the window's start is the sweep's")
    Do $$$AssertEquals(r.WindowTo, "2026-10-25T09:00:00Z", "and its end")
    Do $$$AssertEquals(r.ProductionState, "running", "the production's state")
    Do $$$AssertEquals(##class(Shutter.Store.Review).Running(..#NS, ..#PROD), "", "a done review is not running")
    Set o = r.ToObject()
    Do $$$AssertEquals(o.reviewId, r.ReviewId, "the GET names the review")
    Do $$$AssertEquals(o.namespace, ..#NS, "the namespace")
    Do $$$AssertEquals(o.production, ..#PROD, "the production")
    Do $$$AssertEquals(o.productionState, "running", "its state")
    Do $$$AssertEquals(o.state, "done", "the review's state")
    Do $$$AssertEquals(o.window.days, 7, "the window's days")
    Do $$$AssertEquals(o.window.from, "2026-10-18T09:00:00Z", "from")
    Do $$$AssertEquals(o.window.to, "2026-10-25T09:00:00Z", "to")
    Do $$$AssertEquals(o.fingerprint, ..#FINGERPRINT, "the fingerprint")
    Do $$$AssertNotEquals(o.finishedAt, "", "finishedAt")
    Do $$$AssertEquals(o.%GetTypeOf("unreadable"), "boolean", "unreadable is a boolean")
    Do $$$AssertEquals(o.summary.bySeverity.high, 1, "the summary's high count")
    Do $$$AssertEquals(o.summary.bySeverity.medium, 2, "medium")
    Do $$$AssertEquals(o.summary.findings, 4, "findings")
    Do $$$AssertEquals(o.summary.intended, 0, "none intended")
    Do $$$AssertEquals(o.summary.errorsInWindow, 2, "the errors in the window")
    Do $$$AssertEquals(o.findings.%Size(), 4, "four findings")
    Set f1 = o.findings.%Get(0)
    Do $$$AssertEquals(f1.id, "F1", "in baseline order: F1 first")
    Do $$$AssertEquals(f1.code, "RETRY_FOREVER", "with its code")
    Do $$$AssertEquals(f1.severity, "high", "severity")
    Do $$$AssertEquals(f1.item, "Downstream Out", "item")
    Do $$$AssertEquals(f1.setting, "FailureTimeout", "setting")
    Do $$$AssertEquals(f1.found, "-1", "found")
    Do $$$AssertEquals(f1.%GetTypeOf("rank"), "null", "rank is null before the agent")
    Do $$$AssertEquals(f1.explanation, "", "and there is no explanation")
    Do $$$AssertEquals(f1.status, "new", "the finding is new")
    Do $$$AssertEquals(f1.annotationId, "", "with no annotation")
    Do $$$AssertEquals(f1.evidence.example, "an example that never reaches the model", "the GET keeps the error example for the operator")
    Do $$$AssertEquals(o.findings.%Get(3).id, "F4", "F4 last")
    Do $$$AssertEquals(o.caseAggregates."_total".count, 3, "the case aggregates")
    Do $$$AssertEquals(o.agent.state, "skipped", "the agent's part is skipped")
    Do $$$AssertEquals(o.agent.%GetTypeOf("mode"), "null", "with no mode")
    Do $$$AssertEquals(o.agent.%GetTypeOf("costUsd"), "null", "no cost")
    Do $$$AssertEquals(o.agent.%GetTypeOf("recordKey"), "null", "no record key")
    Do $$$AssertEquals(o.agent.error, "", "and no error")
    Do $$$AssertEquals(o.agent.summary, "", "no summary")
    Do $$$AssertEquals(o.requestedBy, "operator", "who asked")
    Do $$$AssertEquals(o.error, "", "and no error on the review")
    // The agent asked: the review goes on to ranking under the record key.
    Do $$$AssertStatusOK(..NewReview(.r2), "a second review opens")
    Set key = "review:" _ ..#NS _ ":" _ ..#PROD _ "|review|1|" _ ..#FINGERPRINT
    Do $$$AssertStatusOK(r2.StoreSweep(..Result(), 1, key), "the sweep is stored with the agent asked")
    Do $$$AssertEquals(r2.State, "ranking", "the review is ranking")
    Do $$$AssertEquals(r2.AgentState, "pending", "the agent's part is pending")
    Do $$$AssertEquals(r2.RecordKey, key, "under the record key")
    Do $$$AssertEquals(r2.FinishedAt, "", "and not finished")
    Set o2 = r2.ToObject()
    Do $$$AssertEquals(o2.%GetTypeOf("finishedAt"), "null", "finishedAt is null while ranking")
    Do $$$AssertEquals(o2.agent.recordKey, key, "the GET shows the record key")
    Do $$$AssertEquals(o2.agent.state, "pending", "and the pending agent")
    Set running = ##class(Shutter.Store.Review).Running(..#NS, ..#PROD)
    Do $$$AssertTrue($ISOBJECT(running) && (running.ReviewId = r2.ReviewId), "a ranking review is the running one")
    // An unreadable namespace: nothing for the agent, even when asked.
    Do $$$AssertStatusOK(..NewReview(.r3), "a third review opens")
    Set u = ..Result()
    Do u.%Set("unreadable", 1, "boolean")
    Do $$$AssertStatusOK(r3.StoreSweep(u, 1, key), "the unreadable sweep is stored")
    Do $$$AssertEquals(r3.State, "done", "the review is done")
    Do $$$AssertEquals(r3.AgentState, "skipped", "and the agent skipped")
    Do $$$AssertEquals(r3.Unreadable, 1, "unreadable is kept")
    // No result at all: failed.
    Do $$$AssertStatusOK(..NewReview(.r4), "a fourth review opens")
    Do r4.StoreSweep("")
    Do $$$AssertEquals(r4.State, "failed", "no result fails the review")
    Do $$$AssertTrue(r4.Error [ "no result", "and says so: " _ r4.Error)
    Do $$$AssertStatusOK(..NewReview(.r5), "a fifth review opens")
    Do $$$AssertStatusOK(r5.Fail("The sweep failed: <PROTECT>"), "Fail")
    Do $$$AssertEquals(r5.State, "failed", "the review is failed")
    Do $$$AssertEquals(r5.AgentState, "skipped", "the agent skipped")
    Do $$$AssertNotEquals(r5.FinishedAt, "", "and finished")
    Do $$$AssertEquals(r5.ToObject().error, "The sweep failed: <PROTECT>", "the GET carries the error")
}

/// The ranking's validation (RankingProblem, the process's rule): every finding id once, ranks 1 to n without gaps, and
/// no finding ranked above one of a higher severity tier; a swap within a tier stands.
Method TestRankingProblem()
{
    Set findings = ..Result().findings
    Do $$$AssertEquals(##class(Shutter.Store.Review).RankingProblem(findings, ..GoodRanking()), "", "a ranking that swaps the two medium findings stands")
    Set same = {"ranking": [{"finding_id": "F1", "rank": "1"}, {"finding_id": "F2", "rank": 2}, {"finding_id": "F3", "rank": 3}, {"finding_id": "F4", "rank": 4}]}
    Do $$$AssertEquals(##class(Shutter.Store.Review).RankingProblem(findings, same), "", "the baseline order stands, a rank given as a string included")
    Set missing = {"ranking": [{"finding_id": "F1", "rank": 1}, {"finding_id": "F2", "rank": 2}, {"finding_id": "F3", "rank": 3}]}
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem(findings, missing) [ "3 entries for 4 findings", "a missing finding: " _ ##class(Shutter.Store.Review).RankingProblem(findings, missing))
    Set twice = {"ranking": [{"finding_id": "F1", "rank": 1}, {"finding_id": "F1", "rank": 2}, {"finding_id": "F3", "rank": 3}, {"finding_id": "F4", "rank": 4}]}
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem(findings, twice) [ "F1 twice", "a finding twice: " _ ##class(Shutter.Store.Review).RankingProblem(findings, twice))
    Set unknown = {"ranking": [{"finding_id": "F1", "rank": 1}, {"finding_id": "F9", "rank": 2}, {"finding_id": "F3", "rank": 3}, {"finding_id": "F4", "rank": 4}]}
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem(findings, unknown) [ "F9, which is not a finding", "an unknown finding: " _ ##class(Shutter.Store.Review).RankingProblem(findings, unknown))
    Set gap = {"ranking": [{"finding_id": "F1", "rank": 1}, {"finding_id": "F2", "rank": 2}, {"finding_id": "F3", "rank": 3}, {"finding_id": "F4", "rank": 5}]}
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem(findings, gap) [ "from 1 to 4", "a rank beyond n: " _ ##class(Shutter.Store.Review).RankingProblem(findings, gap))
    Set dup = {"ranking": [{"finding_id": "F1", "rank": 1}, {"finding_id": "F2", "rank": 1}, {"finding_id": "F3", "rank": 3}, {"finding_id": "F4", "rank": 4}]}
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem(findings, dup) [ "Rank 1 is given twice", "a rank twice: " _ ##class(Shutter.Store.Review).RankingProblem(findings, dup))
    Set fraction = {"ranking": [{"finding_id": "F1", "rank": 1.5}, {"finding_id": "F2", "rank": 2}, {"finding_id": "F3", "rank": 3}, {"finding_id": "F4", "rank": 4}]}
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem(findings, fraction) [ "whole number", "a fraction: " _ ##class(Shutter.Store.Review).RankingProblem(findings, fraction))
    Set tier = {"ranking": [{"finding_id": "F4", "rank": 1}, {"finding_id": "F1", "rank": 2}, {"finding_id": "F2", "rank": 3}, {"finding_id": "F3", "rank": 4}]}
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem(findings, tier) [ "F1 (high) is ranked below F4 (low)", "a low finding above a high one: " _ ##class(Shutter.Store.Review).RankingProblem(findings, tier))
    Set under = {"ranking": [{"finding_id": "F1", "rank": 1}, {"finding_id": "F2", "rank": 2}, {"finding_id": "F4", "rank": 3}, {"finding_id": "F3", "rank": 4}]}
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem(findings, under) [ "F3 (medium) is ranked below F4 (low)", "a medium finding below a low one: " _ ##class(Shutter.Store.Review).RankingProblem(findings, under))
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem(findings, []) [ "not a JSON object", "an array is no ranking")
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem(findings, {}) [ "must be an array", "an object without ranking")
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem(findings, {"ranking": [1, 2, 3, 4]}) [ "not an object", "entries that are no objects")
    Do $$$AssertTrue(##class(Shutter.Store.Review).RankingProblem([], {"ranking": [{"finding_id": "F1", "rank": 1}]}) [ "1 entries for 0 findings", "a ranking of nothing")
}

/// StoreAgent keeps the run and merges an accepted ranking into the GET (rank and explanation by id, the order stays the
/// baseline's); a refused ranking is schema_failed with the problem and the baseline stands; no_record, another status,
/// a missing ranking and a timeout are recorded as such. A replay costs nothing; a live run is priced.
Method TestStoreAgent()
{
    Do $$$AssertStatusOK(..NewReview(.r), "a review opens")
    Do $$$AssertStatusOK(r.StoreSweep(..Result(), 1, "key"), "the sweep is stored with the agent asked")
    Set resp = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set resp.Status = "ok", resp.Mode = "replay", resp.Model = "claude-opus-5-5", resp.ProviderConfig = "Shutter"
    Set resp.PromptTokens = 1000, resp.CompletionTokens = 200, resp.CacheReadTokens = 50, resp.DurationMs = 1500, resp.SessionId = "s-1"
    Set ranking = ..GoodRanking()
    Set resp.ResultJSON = ranking.%ToJSON()
    Do $$$AssertStatusOK(r.StoreAgent(resp, ranking, "", "4242"), "the answer is stored")
    Do $$$AssertEquals(r.AgentState, "ok", "the agent's part is ok")
    Do $$$AssertEquals(r.State, "done", "the review is done")
    Do $$$AssertNotEquals(r.FinishedAt, "", "and finished")
    Do $$$AssertEquals(r.Mode, "replay", "the mode is kept")
    Do $$$AssertEquals(r.Model, "claude-opus-5-5", "the model")
    Do $$$AssertEquals(r.PromptTokens, 1000, "the tokens")
    Do $$$AssertEquals(+r.CostUSD, 0, "a replay costs nothing")
    Do $$$AssertEquals(r.EnsMessageId, "4242", "the trace link")
    Do $$$AssertEquals(r.SessionId, "s-1", "the session")
    Do $$$AssertNotEquals(r.RankingJSON, "", "and the ranking is kept")
    Set o = r.ToObject()
    Do $$$AssertEquals(o.findings.%Get(0).id, "F1", "the order stays the baseline's: F1")
    Do $$$AssertEquals(o.findings.%Get(0).rank, 1, "ranked 1")
    Do $$$AssertEquals(o.findings.%Get(0).explanation, "Retries for ever; consistent with 2 cases in the window", "with its explanation")
    Do $$$AssertEquals(o.findings.%Get(1).id, "F2", "F2 second in the list")
    Do $$$AssertEquals(o.findings.%Get(1).rank, 3, "ranked 3 by the agent")
    Do $$$AssertEquals(o.findings.%Get(2).id, "F3", "F3 third")
    Do $$$AssertEquals(o.findings.%Get(2).rank, 2, "ranked 2")
    Do $$$AssertEquals(o.findings.%Get(3).rank, 4, "F4 ranked 4")
    Do $$$AssertEquals(o.agent.state, "ok", "the GET's agent is ok")
    Do $$$AssertEquals(o.agent.mode, "replay", "mode")
    Do $$$AssertEquals(o.agent.model, "claude-opus-5-5", "model")
    Do $$$AssertEquals(o.agent.costUsd, 0, "cost")
    Do $$$AssertEquals(o.agent.promptTokens, 1000, "prompt tokens")
    Do $$$AssertEquals(o.agent.completionTokens, 200, "completion tokens")
    Do $$$AssertEquals(o.agent.durationMs, 1500, "duration")
    Do $$$AssertEquals(o.agent.recordKey, "key", "record key")
    Do $$$AssertEquals(o.agent.ensMessageId, "4242", "the trace link")
    Do $$$AssertEquals(o.agent.summary, "One high finding leads; the two medium findings are close", "the agent's summary")
    Do $$$AssertEquals(o.agent.unknowns.%Size(), 1, "and its unknowns")
    Do $$$AssertEquals(o.agent.error, "", "no error")
    // A live run is priced as the board's runs are.
    Do $$$AssertStatusOK(..NewReview(.live), "a review for a live run")
    Do $$$AssertStatusOK(live.StoreSweep(..Result(), 1, "key"), "its sweep")
    Set lresp = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set lresp.Status = "ok", lresp.Mode = "live", lresp.Model = "claude-opus-5-5", lresp.PromptTokens = 1000000, lresp.CompletionTokens = 0
    Set lresp.ResultJSON = ranking.%ToJSON()
    Do $$$AssertStatusOK(live.StoreAgent(lresp, ..GoodRanking()), "the live answer is stored")
    Do $$$AssertEquals(+live.CostUSD, +##class(Shutter.Store.ModelPrice).Cost("claude-opus-5-5", 1000000, 0, 0, 0), "priced from the model's price row")
    // A refused ranking: schema_failed, the baseline stands.
    Do $$$AssertStatusOK(..NewReview(.r2), "a review for a refused ranking")
    Do $$$AssertStatusOK(r2.StoreSweep(..Result(), 1, "key"), "its sweep")
    Do $$$AssertStatusOK(r2.StoreAgent(resp, "", "The ranking names F9, which is not a finding of this review"), "the refusal is stored")
    Do $$$AssertEquals(r2.AgentState, "schema_failed", "schema_failed")
    Do $$$AssertTrue(r2.AgentError [ "F9", "with the problem: " _ r2.AgentError)
    Do $$$AssertEquals(r2.RankingJSON, "", "and no ranking kept")
    Do $$$AssertEquals(r2.State, "done", "the review is done")
    Set o2 = r2.ToObject()
    Do $$$AssertEquals(o2.findings.%Get(0).%GetTypeOf("rank"), "null", "the findings carry no rank")
    Do $$$AssertEquals(o2.agent.state, "schema_failed", "the GET says schema_failed")
    Do $$$AssertTrue(o2.agent.error [ "F9", "and why")
    Do $$$AssertEquals(o2.agent.mode, "replay", "the run's mode is still shown")
    // ok with nothing to rank is a refusal too.
    Do $$$AssertStatusOK(..NewReview(.r3), "a review for an empty answer")
    Do $$$AssertStatusOK(r3.StoreSweep(..Result(), 1, "key"), "its sweep")
    Do $$$AssertStatusOK(r3.StoreAgent(resp, "", ""), "stored")
    Do $$$AssertEquals(r3.AgentState, "schema_failed", "ok without a ranking is schema_failed")
    Do $$$AssertTrue(r3.AgentError [ "without a ranking", "and says so: " _ r3.AgentError)
    // no_record
    Do $$$AssertStatusOK(..NewReview(.r4), "a review for no recording")
    Do $$$AssertStatusOK(r4.StoreSweep(..Result(), 1, "key"), "its sweep")
    Set nresp = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set nresp.Status = "no_record", nresp.Mode = "replay", nresp.Error = "No recording for key"
    Do $$$AssertStatusOK(r4.StoreAgent(nresp, "", ""), "stored")
    Do $$$AssertEquals(r4.AgentState, "no_record", "no_record")
    Do $$$AssertEquals(r4.AgentError, "No recording for key", "with the bridge's error")
    Do $$$AssertEquals(r4.State, "done", "and the review is done")
    // another status
    Do $$$AssertStatusOK(..NewReview(.r5), "a review for a timeout status")
    Do $$$AssertStatusOK(r5.StoreSweep(..Result(), 1, "key"), "its sweep")
    Set tresp = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set tresp.Status = "timeout", tresp.Mode = "live", tresp.Model = "claude-opus-5-5", tresp.Error = "deadline passed"
    Do $$$AssertStatusOK(r5.StoreAgent(tresp, "", ""), "stored")
    Do $$$AssertEquals(r5.AgentState, "error", "error")
    Do $$$AssertEquals(r5.AgentError, "timeout: deadline passed", "with the status and the error")
    // the process's own failure (no answer in time)
    Do $$$AssertStatusOK(..NewReview(.r6), "a review for no answer")
    Do $$$AssertStatusOK(r6.StoreSweep(..Result(), 1, "key"), "its sweep")
    Do $$$AssertStatusOK(r6.AgentFailed("The agent did not answer within 600 s; the baseline order stands"), "AgentFailed")
    Do $$$AssertEquals(r6.AgentState, "error", "error")
    Do $$$AssertEquals(r6.State, "done", "the review is done")
    Do $$$AssertNotEquals(r6.FinishedAt, "", "and finished")
    Do $$$AssertEquals(r6.ToObject().agent.%GetTypeOf("mode"), "null", "with no run to show")
}

// ---- annotations ----

/// An annotation binds a finding's code, item, setting and effective value; StatusFor answers it for that binding only,
/// not after it expired or was revoked, not for another value; a later review's matching finding carries the status
/// through the sweep's ApplyAnnotations, and a changed value reopens it.
Method TestAnnotations()
{
    Do $$$AssertStatusOK(..NewReview(.r), "a review opens")
    Do $$$AssertStatusOK(r.StoreSweep(..Result()), "its sweep is stored")
    Do $$$AssertStatusNotOK(##class(Shutter.Store.ReviewAnnotation).Create(r, "F1", "whatever", "reason", "owner", "", "approver", .bad), "a status outside the three is refused")
    Do $$$AssertEquals(bad, "", "and nothing is made")
    Set sc = ##class(Shutter.Store.ReviewAnnotation).Create(r, "F9", "intended", "reason", "owner", "", "approver", .bad)
    Do $$$AssertStatusNotOK(sc, "an unknown finding is refused")
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "No finding F9", "and named: " _ $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertStatusOK(##class(Shutter.Store.ReviewAnnotation).Create(r, "F1", "intended", "Retries for ever by agreement with the ward team", "ward team", "", "approver", .a), "F1 is annotated as intended")
    Do $$$AssertEquals(a.Code, "RETRY_FOREVER", "bound to the code")
    Do $$$AssertEquals(a.Item, "Downstream Out", "the item")
    Do $$$AssertEquals(a.Setting, "FailureTimeout", "the setting")
    Set fp = ##class(Shutter.Review.Sweep).ValueFingerprint("RETRY_FOREVER", "Downstream Out", "FailureTimeout", "-1")
    Do $$$AssertEquals(a.ValueFingerprint, fp, "and the value's fingerprint")
    Do $$$AssertEquals(a.Status, "intended", "the status")
    Do $$$AssertEquals(a.Namespace, ..#NS, "the namespace")
    Do $$$AssertEquals(a.Production, ..#PROD, "the production")
    Do $$$AssertEquals(a.ReviewId, r.ReviewId, "the review it was made on")
    Do $$$AssertEquals(a.FindingId, "F1", "and the finding")
    Do $$$AssertEquals(a.CreatedBy, "approver", "who made it")
    Do $$$AssertNotEquals(a.CreatedAt, "", "when")
    Set o = a.ToObject()
    Do $$$AssertEquals(o.annotationId, a.%Id(), "the API's annotationId is the row id")
    Do $$$AssertEquals(o.code, "RETRY_FOREVER", "code")
    Do $$$AssertEquals(o.item, "Downstream Out", "item")
    Do $$$AssertEquals(o.setting, "FailureTimeout", "setting")
    Do $$$AssertEquals(o.valueFingerprint, fp, "valueFingerprint")
    Do $$$AssertEquals(o.status, "intended", "status")
    Do $$$AssertEquals(o.reason, "Retries for ever by agreement with the ward team", "reason")
    Do $$$AssertEquals(o.owner, "ward team", "owner")
    Do $$$AssertEquals(o.%GetTypeOf("expiresAt"), "null", "expiresAt is null when it does not expire")
    Do $$$AssertNotEquals(o.createdAt, "", "createdAt")
    // StatusFor: the binding, and nothing else.
    Set status = ##class(Shutter.Store.ReviewAnnotation).StatusFor("RETRY_FOREVER", ..#NS, ..#PROD, "Downstream Out", "FailureTimeout", fp, .aid)
    Do $$$AssertEquals(status, "intended", "the binding matches")
    Do $$$AssertEquals(aid, a.%Id(), "and names the annotation")
    Set other = ##class(Shutter.Review.Sweep).ValueFingerprint("RETRY_FOREVER", "Downstream Out", "FailureTimeout", "15")
    Do $$$AssertEquals(##class(Shutter.Store.ReviewAnnotation).StatusFor("RETRY_FOREVER", ..#NS, ..#PROD, "Downstream Out", "FailureTimeout", other, .aid), "", "another value does not")
    Do $$$AssertEquals(aid, "", "and names none")
    Do $$$AssertEquals(##class(Shutter.Store.ReviewAnnotation).StatusFor("RETRY_FOREVER", ..#NS, "Another.Production", "Downstream Out", "FailureTimeout", fp, .aid), "", "another production does not")
    Do $$$AssertEquals(##class(Shutter.Store.ReviewAnnotation).StatusFor("RETRY_FOREVER", ..#NS, ..#PROD, "Escalation Mail", "FailureTimeout", fp, .aid), "", "another item does not")
    Do $$$AssertEquals(##class(Shutter.Store.ReviewAnnotation).StatusFor("GIVES_UP_EARLY", ..#NS, ..#PROD, "Downstream Out", "FailureTimeout", fp, .aid), "", "another code does not")
    // A finding about the production itself: empty item and setting.
    Do $$$AssertStatusOK(##class(Shutter.Store.ReviewAnnotation).Create(r, "F2", "accepted_risk", "Alerts go to the site's own monitoring", "", "", "approver", .b), "F2 is an accepted risk")
    Set fp2 = ##class(Shutter.Review.Sweep).ValueFingerprint("NO_ALERT_CONSUMER", "", "", "no Ens.Alert item")
    Do $$$AssertEquals(##class(Shutter.Store.ReviewAnnotation).StatusFor("NO_ALERT_CONSUMER", ..#NS, ..#PROD, "", "", fp2, .bid), "accepted_risk", "a production-level binding matches with an empty item and setting")
    Do $$$AssertEquals(bid, b.%Id(), "and names its annotation")
    // Expired, and not yet expired.
    Do $$$AssertStatusOK(##class(Shutter.Store.ReviewAnnotation).Create(r, "F4", "false_positive", "ArchiveIO is off on the live item", "", "2020-01-01T00:00:00Z", "approver", .c), "F4 is annotated with an expiry in the past")
    Set fp4 = ##class(Shutter.Review.Sweep).ValueFingerprint("ARCHIVE_IO_ON", "ADT In", "ArchiveIO", "1")
    Do $$$AssertEquals(##class(Shutter.Store.ReviewAnnotation).StatusFor("ARCHIVE_IO_ON", ..#NS, ..#PROD, "ADT In", "ArchiveIO", fp4, .cid), "", "an expired annotation gives nothing")
    Do $$$AssertStatusOK(##class(Shutter.Store.ReviewAnnotation).Create(r, "F4", "false_positive", "ArchiveIO is off on the live item", "", "2999-01-01T00:00:00Z", "approver", .c2), "and one with an expiry to come")
    Do $$$AssertEquals(##class(Shutter.Store.ReviewAnnotation).StatusFor("ARCHIVE_IO_ON", ..#NS, ..#PROD, "ADT In", "ArchiveIO", fp4, .cid), "false_positive", "which gives its status")
    Do $$$AssertEquals(cid, c2.%Id(), "the unexpired one")
    Do $$$AssertEquals(c2.ToObject().expiresAt, "2999-01-01T00:00:00Z", "and the API shows the expiry")
    // Revoked.
    Do $$$AssertStatusOK(a.Revoke("approver"), "F1's annotation is revoked")
    Do $$$AssertEquals(a.Revoked, 1, "it says so")
    Do $$$AssertEquals(a.RevokedBy, "approver", "by whom")
    Do $$$AssertNotEquals(a.RevokedAt, "", "and when")
    Do $$$AssertEquals(##class(Shutter.Store.ReviewAnnotation).StatusFor("RETRY_FOREVER", ..#NS, ..#PROD, "Downstream Out", "FailureTimeout", fp, .aid), "", "a revoked annotation gives nothing")
    Do $$$AssertTrue($ISOBJECT(##class(Shutter.Store.ReviewAnnotation).ById(a.%Id())), "but the row is kept for the record")
    Do $$$AssertEquals(##class(Shutter.Store.ReviewAnnotation).ById("no-such-id"), "", "ById of a word is nothing")
    Do $$$AssertEquals(##class(Shutter.Store.ReviewAnnotation).ById(999999999), "", "and of an id that is not there")
    // A second review's matching findings carry the statuses, through the sweep's ApplyAnnotations.
    Do $$$AssertStatusOK(##class(Shutter.Store.ReviewAnnotation).Create(r, "F1", "intended", "Agreed again", "ward team", "", "approver", .a2), "F1 is annotated once more")
    Do $$$AssertStatusOK(..NewReview(.r2), "a second review opens")
    Do $$$AssertStatusOK(r2.StoreSweep(..Result()), "with the same findings")
    Set o2 = r2.ToObject()
    Do $$$AssertEquals(o2.findings.%Get(0).status, "intended", "its F1 is intended")
    Do $$$AssertEquals(o2.findings.%Get(0).annotationId, a2.%Id(), "by the new annotation")
    Do $$$AssertEquals(o2.findings.%Get(1).status, "accepted_risk", "its F2 an accepted risk")
    Do $$$AssertEquals(o2.findings.%Get(1).annotationId, b.%Id(), "by its annotation")
    Do $$$AssertEquals(o2.findings.%Get(2).status, "new", "its F3 new")
    Do $$$AssertEquals(o2.findings.%Get(3).status, "false_positive", "its F4 a false positive")
    Do $$$AssertEquals(o2.summary.intended, 3, "and the summary counts three")
    // The first review reads the same now: the status is live, not stored with the review.
    Do $$$AssertEquals(r.ToObject().findings.%Get(0).status, "intended", "the first review's F1 reads intended too")
    // A changed value reopens the finding.
    Set changed = ..Result()
    Set changed.findings.%Get(0).found = "30"
    Do $$$AssertStatusOK(..NewReview(.r3), "a third review opens")
    Do $$$AssertStatusOK(r3.StoreSweep(changed), "with F1 at another value")
    Set o3 = r3.ToObject()
    Do $$$AssertEquals(o3.findings.%Get(0).status, "new", "its F1 is new again")
    Do $$$AssertEquals(o3.findings.%Get(0).annotationId, "", "with no annotation")
    Do $$$AssertEquals(o3.summary.intended, 2, "and two are still intended")
}

/// Running names the newest review still sweeping or ranking, and nothing once they are done; Trim keeps the newest
/// reviews of a production; a review left sweeping for too long is failed when the next one opens.
Method TestRunningAndTrim()
{
    For i = 1:1:5 {
        Set sc = ..NewReview(.one)
        Set r(i) = one
        Do $$$AssertStatusOK(sc, "review " _ i _ " opens")
    }
    Set running = ##class(Shutter.Store.Review).Running(..#NS, ..#PROD)
    Do $$$AssertTrue($ISOBJECT(running) && (running.ReviewId = r(5).ReviewId), "the newest sweeping review is the running one")
    For i = 1:1:5 {
        Do $$$AssertStatusOK(r(i).StoreSweep(..Result()), "review " _ i _ " is done")
    }
    Do $$$AssertEquals(##class(Shutter.Store.Review).Running(..#NS, ..#PROD), "", "none is running once all are done")
    Do $$$AssertEquals(##class(Shutter.Store.Review).Count(..#NS, ..#PROD), 5, "five reviews")
    Set list = ##class(Shutter.Store.Review).List(..#NS, ..#PROD, 2)
    Do $$$AssertEquals(list.%Size(), 2, "the list takes its limit")
    Do $$$AssertEquals(list.%Get(0).reviewId, r(5).ReviewId, "newest first")
    Do $$$AssertEquals(list.%Get(1).reviewId, r(4).ReviewId, "then the one before")
    Do $$$AssertEquals(##class(Shutter.Store.Review).Trim(..#NS, ..#PROD, 3), 2, "Trim to 3 deletes 2")
    Do $$$AssertEquals(##class(Shutter.Store.Review).Count(..#NS, ..#PROD), 3, "three are left")
    Do $$$AssertEquals(##class(Shutter.Store.Review).ByReviewId(r(1).ReviewId), "", "the oldest is gone")
    Do $$$AssertEquals(##class(Shutter.Store.Review).ByReviewId(r(2).ReviewId), "", "and the next")
    Do $$$AssertTrue($ISOBJECT(##class(Shutter.Store.Review).ByReviewId(r(5).ReviewId)), "the newest stays")
    Do $$$AssertEquals(##class(Shutter.Store.Review).Trim(..#NS, ..#PROD, 3), 0, "and a second Trim deletes nothing")
    // A review left sweeping: no longer running, and failed by the next one that opens.
    Do $$$AssertStatusOK(..NewReview(.stale), "a review opens")
    Set stale.StartedAt = "2026-01-01T00:00:00Z"
    Do $$$AssertStatusOK(stale.%Save(), "and is made old")
    Do $$$AssertEquals(##class(Shutter.Store.Review).Running(..#NS, ..#PROD), "", "an old sweeping review is not running")
    Do $$$AssertStatusOK(..NewReview(.next), "the next review opens")
    Set stale = ##class(Shutter.Store.Review).ByReviewId(stale.ReviewId)
    Do $$$AssertEquals(stale.State, "failed", "and the old one is failed")
    Do $$$AssertTrue(stale.Error [ "did not finish within 20 minutes", "with the reason: " _ stale.Error)
    Set running = ##class(Shutter.Store.Review).Running(..#NS, ..#PROD)
    Do $$$AssertTrue($ISOBJECT(running) && (running.ReviewId = next.ReviewId), "the new one is the running review")
}

}
