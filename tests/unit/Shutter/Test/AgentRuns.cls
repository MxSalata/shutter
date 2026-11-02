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
