/// The run record (Shutter.Store.AgentRun; CONTRACTS 6.6, 9) copies what the agent response carries, since v1.35 the
/// millisecond start and AI Hub's own counters (time in the model's calls, time in the tools, reasoning tokens), for the case
/// page's timeline and the DPI-I-689 queries.
Class Shutter.Test.AgentRuns Extends %UnitTest.TestCase
{

Parameter KEY = "PAS^HOSP^MRN-UT8^ENC-UT8^admit^2026-11-02T01:00:00Z";

Property CaseRowId As %String;

Method OnAfterAllTests() As %Status
{
    If ..CaseRowId '= "" {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.AgentRun WHERE ""Case"" = ?", ..CaseRowId)
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", ..CaseRowId)
        Kill ^Shutter.Counter("event", ..CaseRowId)
        If ##class(Shutter.Store.Case).%ExistsId(..CaseRowId) Do ##class(Shutter.Store.Case).%DeleteId(..CaseRowId)
    }
    Quit $$$OK
}

/// The millisecond counters survive the response's JSON (a recording), the time helpers move times by milliseconds, and a
/// replay writes the recorded tool calls for the run at their recorded pace, once.
Method TestReplayKeepsThePace()
{
    Set time = "Shutter.Util.Time"
    Do $$$AssertEquals($CLASSMETHOD(time, "MillisBetween", "2026-11-02T01:00:00.250Z", "2026-11-02T01:00:02.750Z"), 2500, "two and a half seconds")
    Do $$$AssertEquals($CLASSMETHOD(time, "MillisBetween", "2026-11-02T01:00:00Z", "2026-11-02T01:00:01.5Z"), 1500, "a time without a fraction, and a fraction of one digit")
    Do $$$AssertEquals($CLASSMETHOD(time, "MillisBetween", "", "2026-11-02T01:00:01Z"), "", "no time, no answer")
    Do $$$AssertEquals($CLASSMETHOD(time, "PlusMillis", "2026-11-02T01:00:59.900Z", 1350), "2026-11-02T01:01:01.250Z", "moved past the minute")
    Do $$$AssertEquals($CLASSMETHOD(time, "PlusMillis", "2026-11-02T00:00:00.100Z", -200), "2026-11-01T23:59:59.900Z", "moved back past midnight")
    Set r = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set r.Status = "ok", r.StartedAt = "2026-11-02T01:00:00Z", r.StartedAtMs = "2026-11-02T01:00:00.123Z", r.LlmMs = 4200, r.ToolMs = 310, r.ReasoningTokens = 77
    Set back = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Do $$$AssertStatusOK(back.FromObject(r.ToObject()), "the response round-trips through its JSON")
    Do $$$AssertEquals(back.StartedAtMs _ "|" _ back.LlmMs _ "|" _ back.ToolMs _ "|" _ back.ReasoningTokens, "2026-11-02T01:00:00.123Z|4200|310|77", "with the millisecond counters")
    // The replayed calls: a run key of this test, the recorded times moved by the shift, written once.
    Set key = "test-replay-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set calls = [{"at": "2026-10-25T13:22:53.467Z", "name": "GetRoute", "arguments": {"caseId": "C-1"}, "durationMs": 120, "ok": true, "resultPreview": "{}"}, {"at": "2026-10-25T13:22:55.000Z", "name": "GetFailure", "arguments": "{}", "durationMs": 80, "ok": true, "resultPreview": "{}"}]
    Set shift = $CLASSMETHOD(time, "MillisBetween", "2026-10-25T13:22:53.467Z", "2026-11-02T01:00:00.000Z")
    Do $$$AssertEquals(##class(Shutter.Bridge.Runner.Replay).ReplayToolCalls(key, calls.%ToJSON(), shift), 2, "two calls written")
    Set rows = ##class(Shutter.Bridge.ToolCall).ForRun(key)
    Do $$$AssertEquals(rows.%Size(), 2, "two rows for the run")
    Do $$$AssertEquals(rows.%Get(0).at _ "|" _ rows.%Get(0).name _ "|" _ rows.%Get(0).durationMs, "2026-11-02T01:00:00.000Z|GetRoute|120", "the first at the shifted start")
    Do $$$AssertEquals(rows.%Get(1).at, "2026-11-02T01:00:01.533Z", "the second 1.533 s later, as recorded")
    Do $$$AssertEquals(##class(Shutter.Bridge.Runner.Replay).ReplayToolCalls(key, calls.%ToJSON(), shift), 0, "a run with rows already is left alone")
    Do $$$AssertEquals(##class(Shutter.Bridge.Runner.Replay).ReplayToolCalls(key _ "-x", "", shift), 0, "no calls recorded, nothing written")
    &sql(DELETE FROM Shutter_Bridge.ToolCall WHERE RunKey = :key)
    Kill ^Shutter.Counter("toolcall", key)
}

Method TestRunKeepsTheCounters()
{
    Set op = {"operation_key": (..#KEY), "encounter_id": "ENC-UT8", "patient_id": "MRN-UT8", "patient_id_authority": "HOSP", "event": "admit", "ward": "WARD-A", "bed": null, "event_time": "2026-11-02T01:00:00Z", "source_system": "PAS", "source_message_id": "UT8", "payload_digest": "sha256:ut8"}
    Set sc = ##class(Shutter.Store.Case).Open(op, "delivery_failed", "Delivery unavailable (test)", "", "", "policy", .case, .opened)
    Do $$$AssertStatusOK(sc, "a case for the run")
    Set ..CaseRowId = case.%Id()
    Set r = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set r.Status = "ok", r.Mode = "replay", r.Model = "claude-opus-5-5", r.AgentClass = "Shutter.Agent.Conformance", r.ConfigVersion = "1"
    Set r.StartedAt = "2026-11-02T01:00:05Z", r.StartedAtMs = "2026-11-02T01:00:05.123Z", r.DurationMs = 13670
    Set r.PromptTokens = 1200, r.CompletionTokens = 80, r.ToolCalls = 2
    Set r.LlmMs = 13600, r.ToolMs = 17, r.ReasoningTokens = 300
    Set r.ResultJSON = "{}"
    Set sc = ##class(Shutter.Store.AgentRun).FromResponse(case, "", "member", "conformance", r, "", .run)
    Do $$$AssertStatusOK(sc, "the run is stored")
    Do $$$AssertEquals(run.StartedAtMs _ "|" _ run.LlmMs _ "|" _ run.ToolMs _ "|" _ run.ReasoningTokens, "2026-11-02T01:00:05.123Z|13600|17|300", "the millisecond start and the three counters are kept")
    Do run.%JSONExportToString(.json)
    Set o = ##class(%DynamicObject).%FromJSON(json)
    Do $$$AssertTrue((o.startedAtMs = r.StartedAtMs) && (o.llmMs = 13600) && (o.toolMs = 17) && (o.reasoningTokens = 300), "and named for the API: " _ json)
    // A response without them (a replay, an older build) leaves them empty, never zero.
    Set r2 = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set r2.Status = "ok", r2.Mode = "replay", r2.StartedAt = "2026-11-02T01:00:06Z", r2.ResultJSON = "{}"
    Set sc = ##class(Shutter.Store.AgentRun).FromResponse(case, "", "member", "encounter", r2, "", .run2)
    Do $$$AssertStatusOK(sc, "a second run")
    Do $$$AssertTrue((run2.LlmMs = "") && (run2.ToolMs = "") && (run2.ReasoningTokens = ""), "counters the session did not give stay empty")
    Do $$$AssertTrue($MATCH(##class(Shutter.Util.Time).NowUTCms(), "^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"), "the millisecond clock has the ISO form")
}

}
