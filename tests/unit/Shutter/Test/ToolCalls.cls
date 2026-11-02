/// The tool-call rows a run leaves (Shutter.Bridge.ToolCall; CONTRACTS 6.6): an executed call with its duration, and since
/// v1.35 a call the authorisation policy refused before it ran, with denied true and the reason and no duration, so a
/// prompt that tries to reach past its case is visible on the case page.
Class Shutter.Test.ToolCalls Extends %UnitTest.TestCase
{

Parameter KEY = "test:UT-TOOLCALLS:conformance:1";

Method OnAfterAllTests() As %Status
{
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Bridge.ToolCall WHERE RunKey = ?", ..#KEY)
    Kill ^Shutter.Counter("toolcall", ..#KEY)
    Quit $$$OK
}

Method TestExecutedAndDeniedRows()
{
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Bridge.ToolCall WHERE RunKey = ?", ..#KEY)
    Kill ^Shutter.Counter("toolcall", ..#KEY)
    Do $$$AssertStatusOK(##class(Shutter.Bridge.ToolCall).Append(..#KEY, "GetSnapshot", "{""caseId"":""C-000001""}", 17, 1, "{""ok"":true}"), "an executed call")
    Do $$$AssertStatusOK(##class(Shutter.Bridge.ToolCall).Append(..#KEY, "GetSnapshot", "{""caseId"":""C-000002""}", 0, 0, "", "This run is for case C-000001 only", 1), "a refused call")
    Set rows = ##class(Shutter.Bridge.ToolCall).ForRun(..#KEY)
    Do $$$AssertEquals(rows.%Size(), 2, "two rows, in order")
    Set a = rows.%Get(0), b = rows.%Get(1)
    Do $$$AssertTrue((a.seq = 1) && a.ok && 'a.denied && (a.durationMs = 17), "the executed call: ok, not denied, timed: " _ a.%ToJSON())
    Do $$$AssertTrue((b.seq = 2) && 'b.ok && b.denied && (b.durationMs = 0) && (b.error [ "C-000001 only"), "the refused call: denied, with the reason and no duration: " _ b.%ToJSON())
    Do $$$AssertEquals(##class(Shutter.Bridge.ToolCall).DeniedCount(..#KEY), 1, "one denial counted for the run")
    Do $$$AssertEquals(##class(Shutter.Bridge.ToolCall).DeniedCount("test:UT-TOOLCALLS:none:0"), 0, "none for a run with no rows")
}

}
