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

/// The runner itself refuses on an instance that is not a demo, so a caller that reaches it over SQL or from the terminal,
/// not through the routes, changes nothing either: Run, Start and Reset answer not_a_demo_instance with the routes' words,
/// an open incident stays open and a fixture in the inbound folder stays where it is.
Method TestRunnerRefusesOffTheDemo()
{
    Set runner = "Shutter.Scenarios.Runner"
    Set words = "Scenarios run and reset on a demo instance only: this instance is a site install, where a reset would abandon its open incidents"
    Kill ^Shutter.Config("demo")
    Do ..Mark()
    // An open incident a reset would abandon, and a file a reset would delete
    Set sc = ##class(Shutter.Store.Incident).Open("UT-GUARD-RECEIVER", "board", .incident)
    Do $$$AssertStatusOK(sc, "an open incident to keep")
    Set hadIn = $DATA(^Shutter.Config("adtIn")) # 10, savedIn = $GET(^Shutter.Config("adtIn"))
    Set dir = savedIn
    If dir = "" {
        Set dir = ##class(%File).NormalizeDirectory(##class(%File).TempFilename("dir"))
        Do ##class(%File).CreateDirectoryChain(dir)
        Set ^Shutter.Config("adtIn") = dir
    }
    Set file = ##class(%File).NormalizeDirectory(dir) _ "ut-guard-runner.hl7"
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(file)
    Do stream.Write("MSH|^~\&|UT|GUARD")
    Do stream.%Save()
    Kill stream
    Set before = ..State()
    Set answers("Run") = $CLASSMETHOD(runner, "Run", "S2", "board")
    Set answers("Start") = $CLASSMETHOD(runner, "Start", "S2", "board")
    Set answers("Reset") = $CLASSMETHOD(runner, "Reset")
    Set answers("Reset over SQL") = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Shutter_Scenarios.Runner_Reset() AS A")
    If rs.%Next() Set answers("Reset over SQL") = rs.%Get("A")
    Set name = ""
    For {
        Set name = $ORDER(answers(name))
        Quit:name=""
        Set answer = ##class(Shutter.Util.Json).Parse(answers(name), .psc)
        Do $$$AssertTrue($ISOBJECT(answer), name _ " answers JSON: " _ answers(name))
        Continue:'$ISOBJECT(answer)
        Do $$$AssertEquals(answer.error, "not_a_demo_instance", name _ " is refused with not_a_demo_instance")
        Do $$$AssertEquals(answer.detail, words, name _ " says what the routes say")
    }
    Do $$$AssertEquals(..State(), before, "nothing changed: " _ before)
    Set kept = ##class(Shutter.Store.Incident).%OpenId(incident.%Id())
    Do $$$AssertEquals($SELECT($ISOBJECT(kept): kept.State, 1: "gone"), "open", "the incident is still open")
    Do $$$AssertTrue(##class(%File).Exists(file), "the inbound file is still there")
    // Put back what the test made
    Do ##class(%File).Delete(file)
    If savedIn = "" {
        Do ##class(%File).RemoveDirectory(dir)
        If hadIn { Set ^Shutter.Config("adtIn") = savedIn } Else { Kill ^Shutter.Config("adtIn") }
    }
    Set id = incident.%Id()
    Kill incident, kept
    &sql(DELETE FROM Shutter_Store.IncidentEvent WHERE Incident = :id)
    Do ##class(Shutter.Store.Incident).%DeleteId(id)
}

/// On the demo the runner's own check lets every call through: Run, Start and Reset behave as before (the reset is called
/// for real by Shutter.Test.ResetLive, the runs by the scenario checks).
Method TestRunnerOnTheDemo()
{
    Set ^Shutter.Config("demo") = 1
    Do $$$AssertEquals(##class(Shutter.Scenarios.Runner).NotDemo(), "", "a demo instance passes")
}

}
