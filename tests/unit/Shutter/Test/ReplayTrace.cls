/// A replay writes one trace line per recorded tool call, so the Visual Trace shows each call as its own step: the tool,
/// whether it ran, was refused or failed, its milliseconds and the word replay, and nothing of the call's arguments,
/// its result or its error text.
Class Shutter.Test.ReplayTrace Extends %UnitTest.TestCase
{

Method TestOneLinePerRecordedCall()
{
    Set key = "test-replaytrace-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set calls = [{"at": "2026-10-25T13:22:53.467Z", "name": "GetRoute", "arguments": {"caseId": "C-UT9", "patient": "MRN-UT9"}, "durationMs": 120, "ok": true, "resultPreview": "{\"name\":\"DOE^JANE\"}"}, {"at": "2026-10-25T13:22:54.000Z", "name": "GetMessage", "arguments": "{\"caseId\":\"C-UT10\"}", "durationMs": 0, "ok": false, "denied": true, "error": "case C-UT10 is not this run's case"}, {"at": "2026-10-25T13:22:55.000Z", "name": "GetReceipt", "arguments": {"dob": "1970-01-01"}, "durationMs": 45, "ok": false, "error": "no receipt for ENC-UT9"}]
    &sql(SELECT MAX(ID) INTO :before FROM Ens_Util.Log)
    Set before = +$GET(before)
    Do $$$AssertEquals(##class(Shutter.Bridge.Runner.Replay).ReplayToolCalls(key, calls.%ToJSON(), ""), 3, "three calls written")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Text %STARTSWITH 'Tool ' ORDER BY ID", before)
    Set lines = ""
    While rs.%Next() { Set lines = lines _ $SELECT(lines = "": "", 1: "|") _ rs.Text }
    Do $$$AssertEquals(lines, "Tool GetRoute ok, 120 ms (replay)|Tool GetMessage denied, 0 ms (replay)|Tool GetReceipt failed, 45 ms (replay)", "one line per call, in order: " _ lines)
    For word = "C-UT9", "MRN-UT9", "C-UT10", "DOE", "1970", "ENC-UT9", "receipt for", "not this run" {
        Do $$$AssertTrue(lines '[ word, "no argument, result or error text in the lines: " _ word)
    }
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM Ens_Util.Log WHERE ID > ? AND Text %STARTSWITH 'Recorded tool calls'", before)
    Do rs.%Next()
    Do $$$AssertEquals(rs.n, 0, "no summary line for the run beside them")
    &sql(DELETE FROM Shutter_Bridge.ToolCall WHERE RunKey = :key)
    Kill ^Shutter.Counter("toolcall", key)
}

/// A tool name is the catalogue's, but it comes from a recording file: one that isn't a plain name is not written into
/// the line at all.
Method TestNameIsOnlyAName()
{
    Set key = "test-replaytrace-name-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set calls = [{"name": "search_effects (MRN-UT11)", "durationMs": 7, "ok": true}]
    &sql(SELECT MAX(ID) INTO :before FROM Ens_Util.Log)
    Set before = +$GET(before)
    Do $$$AssertEquals(##class(Shutter.Bridge.Runner.Replay).ReplayToolCalls(key, calls.%ToJSON(), ""), 1, "one call written")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Ens_Util.Log WHERE ID > ? AND Text %STARTSWITH 'Tool ' ORDER BY ID", before)
    Do $$$AssertTrue(rs.%Next(), "a line for the call")
    Do $$$AssertEquals(rs.Text, "Tool (not a tool name) ok, 7 ms (replay)", "the odd name is left out: " _ rs.Text)
    &sql(DELETE FROM Shutter_Bridge.ToolCall WHERE RunKey = :key)
    Kill ^Shutter.Counter("toolcall", key)
}

}
