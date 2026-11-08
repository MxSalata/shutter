/// The scenario routes on an instance that is not a demo (docs/CONTRACTS.md, the resources table): POST /scenarios/reset
/// abandons every open incident, moves resetAt (the evidence collector then ignores what came before) and empties the
/// inbound folders, and POST /scenarios/{id}/run resets first, so on a site install, where the operator and the approver
/// hold Shutter_Scenarios, both are refused with 403 not_a_demo_instance and nothing changes. Each test calls the route's
/// class method as the web application's request reaches it, with the CSRF header, as this process's user, and puts the
/// instance's demo flag and every value it marks back afterwards.
Class Shutter.Test.ScenarioGuard Extends %UnitTest.TestCase
{

/// The ^Shutter.Config values a reset writes, and the run record, as they were before the test: $LISTBUILD($DATA, value).
Property Saved As %String(MAXLEN = "") [ MultiDimensional ];

Method OnBeforeOneTest() As %Status
{
    For key = "demo", "mode", "resetAt", "scenario", "scenarioRun" {
        Set ..Saved(key) = $LISTBUILD($DATA(^Shutter.Config(key)) # 10, $GET(^Shutter.Config(key)))
    }
    Set ..Saved("run") = $LISTBUILD($DATA(^Shutter.Scenarios("run")) # 10, $GET(^Shutter.Scenarios("run")))
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    For key = "demo", "mode", "resetAt", "scenario", "scenarioRun" {
        Set saved = $GET(..Saved(key))
        Continue:saved=""
        If $LIST(saved, 1) { Set ^Shutter.Config(key) = $LIST(saved, 2) } Else { Kill ^Shutter.Config(key) }
    }
    Set saved = $GET(..Saved("run"))
    If saved '= "" {
        If $LIST(saved, 1) { Set ^Shutter.Scenarios("run") = $LIST(saved, 2) } Else { Kill ^Shutter.Scenarios("run") }
    }
    Quit $$$OK
}

/// Calls a route's class method as Shutter.API.Dispatch serves it: a request with the CSRF header and a JSON body, a
/// fresh response, and what the route writes caught in a file. Returns the HTTP status; body is the reply, parsed.
ClassMethod Call(method As %String, ByRef body As %DynamicObject, args...) As %String
{
    New %request, %response
    Set %request = ##class(%CSP.Request).%New()
    Set %request.CgiEnvs("HTTP_X_REQUESTED_WITH") = "Shutter"
    Set %request.CgiEnvs("REQUEST_METHOD") = "POST"
    Set content = ##class(%Stream.GlobalCharacter).%New()
    Do content.Write($SELECT($ISOBJECT($GET(body)): body.%ToJSON(), 1: "{}"))
    Do content.Rewind()
    Set %request.Content = content
    Set %response = ##class(%CSP.Response).%New()
    Set file = ##class(%File).TempFilename("json"), io = $IO
    Open file:("NWS"):5
    Try {
        Use file
        Do $CLASSMETHOD("Shutter.API.Dispatch", method, args...)
    } Catch ex {
        Use io
        Set %response.Status = "500 " _ ex.DisplayString()
    }
    Use io
    Close file
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(file)
    Set text = stream.Read(1000000)
    Kill stream
    Do ##class(%File).Delete(file)
    Set body = ##class(Shutter.Util.Json).Parse(text, .sc)
    If '$ISOBJECT(body) Set body = {"text": (text)}
    Quit %response.Status
}

/// What a reset or a run would change, read now: the marked ^Shutter.Config values, the run record, the open incidents,
/// the cases and the demo receiver's encounters.
ClassMethod State() As %String
{
    Set incidents = "", cases = "", encounters = ""
    &sql(SELECT COUNT(*) INTO :incidents FROM Shutter_Store.Incident WHERE State <> 'closed')
    &sql(SELECT COUNT(*) INTO :cases FROM Shutter_Store."Case")
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N FROM Downstream.Encounter")
        If rs.%Next() Set encounters = rs.%Get("N")
    } Catch {
        Set encounters = "?"
    }
    Quit "mode=" _ $GET(^Shutter.Config("mode")) _ " resetAt=" _ $GET(^Shutter.Config("resetAt")) _ " scenario=" _ $GET(^Shutter.Config("scenario")) _ " scenarioRun=" _ $GET(^Shutter.Config("scenarioRun")) _ " run=" _ $GET(^Shutter.Scenarios("run")) _ " incidents=" _ incidents _ " cases=" _ cases _ " encounters=" _ encounters
}

/// Marks the values a reset rewrites, so that a reset that ran shows: the mode back to board, resetAt now, the scenario gone.
ClassMethod Mark()
{
    Set ^Shutter.Config("mode") = "policy"
    Set ^Shutter.Config("resetAt") = "2026-01-01T00:00:00Z"
    Set ^Shutter.Config("scenario") = "UT-GUARD", ^Shutter.Config("scenarioRun") = "UT-GUARD"
}

/// On an instance that is not a demo the reset is refused and changes nothing.
Method TestResetRefusedOffTheDemo()
{
    Set ^Shutter.Config("demo") = 0
    Do ..Mark()
    Set before = ..State()
    Set status = ..Call("ScenarioReset", .body)
    Do $$$AssertEquals(status, "403 Forbidden", "POST /scenarios/reset is 403 on demo=0: " _ body.%ToJSON())
    Do $$$AssertEquals(##class(Shutter.Util.Json).Str(body, "error"), "not_a_demo_instance", "with not_a_demo_instance")
    Do $$$AssertEquals(..State(), before, "nothing changed: " _ before)
}

/// On an instance that is not a demo a run is refused before its reset, in every mode, and changes nothing.
Method TestRunRefusedOffTheDemo()
{
    Set ^Shutter.Config("demo") = 0
    Do ..Mark()
    Set before = ..State()
    For mode = "board", "single", "rules", "policy" {
        Set body = {"mode": (mode)}
        Set status = ..Call("ScenarioRun", .body, "S2")
        Do $$$AssertEquals(status, "403 Forbidden", "POST /scenarios/S2/run in " _ mode _ " is 403 on demo=0: " _ body.%ToJSON())
        Do $$$AssertEquals(##class(Shutter.Util.Json).Str(body, "error"), "not_a_demo_instance", "with not_a_demo_instance")
    }
    Do $$$AssertEquals(..State(), before, "nothing changed: " _ before)
}

/// The flag unset counts as not a demo, as GET /status and the store's purge read it.
Method TestUnsetFlagIsNotADemo()
{
    Kill ^Shutter.Config("demo")
    Do ..Mark()
    Set before = ..State()
    Set status = ..Call("ScenarioReset", .body)
    Do $$$AssertEquals(status, "403 Forbidden", "POST /scenarios/reset is 403 with no demo flag: " _ body.%ToJSON())
    Do $$$AssertEquals(..State(), before, "nothing changed")
}

/// On the demo the guard lets the route through (the routes themselves are played end to end by the scenario checks,
/// which reset the instance, so this test does not call them).
Method TestDemoPasses()
{
    Set ^Shutter.Config("demo") = 1
    New %request, %response
    Set %response = ##class(%CSP.Response).%New()
    Set before = %response.Status
    Do $$$AssertEquals(##class(Shutter.API.Dispatch).DemoOnly(), 1, "a demo instance passes")
    Do $$$AssertEquals(%response.Status, before, "and nothing is written")
}

}
