/// A scenario run started without the live agents replays (1.4.4): the public demo's role (Shutter_Demo) runs the scenarios
/// (Shutter_Scenarios) and never resets them or purges the store (no Shutter_ScenarioReset); it holds no Shutter_LiveAgents,
/// so the runner records the run as replay only (^Shutter.Config("scenarioReplay"), Shutter.Scenarios.Runner Begin), a case
/// the run opens keeps it (Shutter.Store.Case's ScenarioReplay) with a line on its trail, and every agent request of that
/// case carries ModeOverride replay (Shutter.Process.CaseWorkflow Stamp), so the Agent item takes the replay runner: no
/// provider call, no budget asked or reserved, cost 0. A judge's run, with the live agents, stays as its mode says, and a
/// reopening or a convened board goes by its own requester's right. The single investigator, never recorded, is refused
/// to a replay-only starter. The test puts every value it marks back.
Class Shutter.Test.ReplayOnly Extends %UnitTest.TestCase
{

/// The ^Shutter.Config values the test sets, as they were: $LISTBUILD($DATA, value).
Property Saved As %String(MAXLEN = "") [ MultiDimensional ];

/// The cases the test opened, by row id.
Property Opened As %String(MAXLEN = "");

Method OnBeforeOneTest() As %Status
{
    For key = "scenario", "scenarioRun", "scenarioBy", "scenarioReplay" {
        Set ..Saved(key) = $LISTBUILD($DATA(^Shutter.Config(key)) # 10, $GET(^Shutter.Config(key)))
    }
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    For key = "scenario", "scenarioRun", "scenarioBy", "scenarioReplay" {
        Set saved = $GET(..Saved(key))
        Continue:saved=""
        If $LIST(saved, 1) { Set ^Shutter.Config(key) = $LIST(saved, 2) } Else { Kill ^Shutter.Config(key) }
    }
    For i = 1:1:$LENGTH(..Opened, ",") {
        Set id = $PIECE(..Opened, ",", i)
        Continue:id=""
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
        Kill ^Shutter.Counter("event", id)
        If ##class(Shutter.Store.Case).%ExistsId(id) Do ##class(Shutter.Store.Case).%DeleteId(id)
    }
    Set ..Opened = ""
    Quit $$$OK
}

/// Opens a case for an operation of this test's own, as the feed does.
Method OpenOne(n As %Integer, Output case As Shutter.Store.Case) As %Status
{
    Set enc = "ENC-UTRO" _ n _ "-" _ $JOB, mrn = "MRN-UTRO" _ n
    Set op = {"operation_key": ("PAS^HOSP^" _ mrn _ "^" _ enc _ "^admit^2026-11-11T01:00:0" _ n _ "Z"), "encounter_id": (enc), "patient_id": (mrn), "patient_id_authority": "HOSP", "event": "admit", "ward": "WARD-A", "bed": null, "event_time": ("2026-11-11T01:00:0" _ n _ "Z"), "source_system": "PAS", "source_message_id": ("UTRO" _ n), "payload_digest": ("sha256:utro" _ n)}
    Set sc = ##class(Shutter.Store.Case).Open(op, "delivery_failed", "Delivery unavailable (test)", "", "", "board", .case, .opened)
    If $$$ISOK(sc) && $ISOBJECT(case) Set ..Opened = ..Opened _ "," _ case.%Id()
    Quit sc
}

/// A role's own resources, as Security.Roles keeps them.
ClassMethod Resources(role As %String) As %String
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If '##class(Security.Roles).Exists(role) Quit "<no role>"
    Do ##class(Security.Roles).Get(role, .p)
    Quit $GET(p("Resources"))
}

ClassMethod Source(class As %String, method As %String) As %String
{
    Set def = ##class(%Dictionary.MethodDefinition).%OpenId(class _ "||" _ method)
    If '$ISOBJECT(def) Quit ""
    Do def.Implementation.Rewind()
    Quit def.Implementation.Read(1000000)
}

/// The demo may run and may not reset or purge: its role holds Shutter_Scenarios and neither Shutter_ScenarioReset nor
/// Shutter_LiveAgents, the run route checks the first and the reset and the purge the second. Where the install made the
/// user demo (SHUTTER_PUBLIC_DEMO_PASSWORD), the user's own permissions say the same.
Method TestTheDemoRunsAndNeverResetsOrPurges()
{
    Do ##class(Shutter.Setup).RefreshSecurity($NAMESPACE)
    Set demo = "," _ ..Resources("Shutter_Demo") _ ","
    Do $$$AssertTrue(demo [ ",Shutter_Scenarios:U,", "the demo role runs the scenarios: " _ demo)
    Do $$$AssertNotTrue(demo [ ",Shutter_ScenarioReset:", "and never resets them or purges the store")
    Do $$$AssertNotTrue(demo [ ",Shutter_LiveAgents:", "and has no live agents, so its runs replay")
    Do $$$AssertTrue(..Source("Shutter.API.Dispatch", "ScenarioRun") [ "Allow(""Shutter_Scenarios"", 1)", "the run route checks Shutter_Scenarios")
    Do $$$AssertTrue(..Source("Shutter.API.Dispatch", "ScenarioReset") [ "Allow(""Shutter_ScenarioReset"", 1)", "the reset route checks Shutter_ScenarioReset")
    Do $$$AssertTrue(..Source("Shutter.Setup", "PurgeStore") [ "Check(""Shutter_ScenarioReset"", ""USE"")", "and so does the purge")
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If '##class(Security.Users).Exists("demo") {
        Do $$$LogMessage("no user demo on this instance (SHUTTER_PUBLIC_DEMO_PASSWORD was not set): the role's definition stands for it")
        Quit
    }
    Do $$$AssertEquals($SYSTEM.Security.CheckUserPermission("demo", "Shutter_Scenarios"), "USE", "the user demo may run")
    Do $$$AssertEquals($SYSTEM.Security.CheckUserPermission("demo", "Shutter_ScenarioReset"), "", "and may not reset or purge")
    Do $$$AssertEquals($SYSTEM.Security.CheckUserPermission("demo", "Shutter_LiveAgents"), "", "nor spend the model budget")
}

/// The runner: Begin works out whether the starter has the live agents (the Scenario Player is sent the API's reading, in
/// the user's own process), records it and refuses an unrecorded mode before the reset; the reset forgets it. Read from
/// their source, since Begin can't run here without resetting the demo's receivers.
Method TestTheRunnerRecordsAReplayOnlyRun()
{
    Set runner = "Shutter.Scenarios.Runner"
    Set begin = ..Source(runner, "Begin")
    Do $$$AssertTrue(begin [ "^Shutter.Config(""scenarioReplay"") = '+liveAllowed", "Begin records a run without the live agents as replay only")
    Do $$$AssertTrue(begin [ "Check(""Shutter_LiveAgents"", ""USE"")", "the caller's own right when nobody passes one")
    Set refusedAt = $FIND(begin, "NotRecorded("), resetAt = $FIND(begin, "..Reset()")
    Do $$$AssertTrue((refusedAt > 0) && (resetAt > refusedAt), "an unrecorded mode is refused before the reset")
    Do $$$AssertTrue(..Source(runner, "Reset") [ "^Shutter.Config(""scenarioReplay"")", "the reset forgets it")
    Do $$$AssertTrue(..Source("Shutter.Operation.ScenarioPlayer", "OnRun") [ "request.LiveAllowed", "the Scenario Player passes the right the API read")
    Set run = ..Source("Shutter.API.Dispatch", "ScenarioRun")
    Do $$$AssertTrue((run [ "Check(""Shutter_LiveAgents"", ""USE"")") && (run [ "msg.LiveAllowed = live"), "the route reads the starter's live agents and sends them with the run")
    // The single investigator was never recorded: a replay-only starter is refused it, in plain words; the judge is not
    Set why = $CLASSMETHOD(runner, "NotRecorded", "single", 0)
    Do $$$AssertTrue(why [ "no recordings", "a replay-only starter is told the single investigator has no recordings: " _ why)
    Do $$$AssertNotTrue((why [ "Shutter_") || (why [ "role"), "without naming a role or a resource")
    For mode = "board", "policy", "rules" { Do $$$AssertEquals($CLASSMETHOD(runner, "NotRecorded", mode, 0), "", mode _ " plays replay only") }
    Do $$$AssertEquals($CLASSMETHOD(runner, "NotRecorded", "single", 1), "", "a starter with the live agents plays the single investigator")
}

/// A case of a replay-only run keeps it, says so on its trail from its opening, and hides it from the API's JSON; a case
/// of a judge's run and a live story's case don't.
Method TestACaseOfAReplayOnlyRunSaysItReplays()
{
    Set ^Shutter.Config("scenario") = "S8", ^Shutter.Config("scenarioRun") = "S8", ^Shutter.Config("scenarioBy") = "demo", ^Shutter.Config("scenarioReplay") = 1
    Do $$$AssertStatusOK(..OpenOne(1, .case), "a case while the demo's run of S8 plays")
    Do $$$AssertTrue(case.ScenarioReplay, "the case keeps that its run replays")
    Do $$$AssertEquals(case.ScenarioBy, "demo", "and who started it")
    Set events = case.Events(), said = 0, it = events.%GetIterator()
    While it.%GetNext(, .e) { If $ISOBJECT(e) && ($EXTRACT(e.text, 1, 9) = "Replayed:") Set said = 1 }
    Do $$$AssertTrue(said, "its trail says it was replayed: " _ $EXTRACT(events.%ToJSON(), 1, 400))
    Do case.%JSONExportToString(.json)
    Do $$$AssertNotTrue(json [ "scenarioReplay", "the flag is not in the case's JSON")
    Set ^Shutter.Config("scenarioBy") = "judge", ^Shutter.Config("scenarioReplay") = 0
    Do $$$AssertStatusOK(..OpenOne(2, .judged), "a case while the judge's run plays")
    Do $$$AssertNotTrue(judged.ScenarioReplay, "a judge's run is not replay only")
    Set events = judged.Events(), said = 0, it = events.%GetIterator()
    While it.%GetNext(, .e) { If $ISOBJECT(e) && ($EXTRACT(e.text, 1, 9) = "Replayed:") Set said = 1 }
    Do $$$AssertNotTrue(said, "and its trail says nothing of a replay")
    Set ^Shutter.Config("scenarioReplay") = 1
    Kill ^Shutter.Config("scenarioRun")
    Do $$$AssertStatusOK(..OpenOne(3, .story), "a case while a live story of S8 plays")
    Do $$$AssertNotTrue(story.ScenarioReplay, "a live story's case is not the runner's, so it is not replay only")
}

/// The rule: every agent request of a replay-only run's case replays and counts against its starter; a judge's run's
/// requests run as their mode says; a reopening or a convened board goes by its requester's own right.
Method TestTheRunsReplayAndAJudgesStayLive()
{
    Set cls = "Shutter.Process.CaseWorkflow"
    If '##class(%Dictionary.CompiledMethod).%ExistsId(cls _ "||Stamp") {
        Do $$$AssertSkipped("the case workflow is not compiled on this instance")
        Quit
    }
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 0, "", "", 1, "demo", 1)
    Do $$$AssertEquals(req.ModeOverride, "replay", "a replay-only run's case replays")
    Do $$$AssertEquals(req.RequestedBy, "demo", "and counts against the demo user, who spends nothing")
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 0, "", "", 1, "judge", 0)
    Do $$$AssertEquals(req.ModeOverride, "", "a judge's run runs as its mode says")
    Do $$$AssertEquals(req.RequestedBy, "judge", "against the judge's share")
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 0, "", "judge", 1, "demo", 1)
    Do $$$AssertEquals(req.ModeOverride _ "|" _ req.RequestedBy, "|judge", "a judge reopening the demo's case goes by the judge's own right")
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 1, "judge", "judge", 1, "demo", 1)
    Do $$$AssertEquals(req.ModeOverride _ "|" _ req.RequestedBy, "|judge", "and so does a board the judge convenes on it")
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do $CLASSMETHOD(cls, "Stamp", req, 0, "", "demo", 0, "demo", 1)
    Do $$$AssertEquals(req.ModeOverride _ "|" _ req.RequestedBy, "replay|demo", "the demo reopening its own case replays still")
}

/// What the Agent item does with such a request, short of the item itself (a business host can't run outside the
/// production): the request's override wins over an item set to run live, so the item takes the replay runner, which
/// asks the budget nothing and calls no provider; a recording answers with mode replay, and the run's row costs nothing.
Method TestAReplayedRequestCallsNoProviderAndSpendsNothing()
{
    Set op = {"AgentClass": "Shutter.Agent.Conformance", "Runner": "Shutter.Bridge.Runner.AIHub", "Mode": "live", "ProviderConfig": "OpenAI", "Model": "gpt-4.1", "MaxIterations": 8, "TokenBudget": 120000, "RequestTimeoutSeconds": 120}
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do ##class(Shutter.Process.CaseWorkflow).Stamp(req, 0, "", "", 1, "demo", 1)
    Set spec = ##class(Shutter.Bridge.RunSpec).FromRequest(req, op)
    Do $$$AssertEquals(spec.Mode, "replay", "an item set to live replays this request")
    Set judgeReq = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Do ##class(Shutter.Process.CaseWorkflow).Stamp(judgeReq, 0, "", "", 1, "judge", 0)
    Do $$$AssertEquals(##class(Shutter.Bridge.RunSpec).FromRequest(judgeReq, op).Mode, "live", "while the judge's request runs live")
    // The item's choice of runner, and that the budget and the provider's state are asked only off replay
    Set item = ..Source("Shutter.Bridge.Operation.Agent", "OnAgentRequest")
    Do $$$AssertTrue(item [ "$SELECT(spec.Mode = ""replay"": ""Shutter.Bridge.Runner.Replay""", "the item takes the replay runner for a replay")
    Do $$$AssertTrue(item [ "(spec.Mode '= ""replay"") && '##class(Shutter.Util.Budget).AllowsFor(", "the budget is asked only off replay")
    Do $$$AssertTrue(item [ "If spec.Mode '= ""replay"" {", "and reserved only off replay")
    // A recording of S8 answers it, as the demo's case would be answered
    Set key = ""
    &sql(SELECT TOP 1 "Key" INTO :key FROM Shutter_Bridge.Record WHERE "Key" %STARTSWITH 'scenario:S8:' AND "Key" [ '|conformance|')
    If (SQLCODE '= 0) || (key = "") {
        Do $$$LogMessage("no recording of S8 on this instance: the replay runner's answer is not checked here")
        Quit
    }
    Set spec.RecordKey = key, spec.AgentClass = "Shutter.Agent.Conformance", spec.MemberCode = "conformance", spec.Model = "", spec.ProviderConfig = ""
    Set response = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set sc = ##class(Shutter.Bridge.Runner.Replay).%New().Run(spec, .response)
    Do $$$AssertStatusOK(sc, "the replay runner answers from " _ key)
    Do $$$AssertEquals(response.Mode, "replay", "and says it replayed")
    Do $$$AssertTrue(response.RecordId '= "", "from the recording")
    Do $$$AssertTrue(..Source("Shutter.Store.AgentRun", "FromResponse") [ "$SELECT(response.Mode = ""replay"": 0", "the row's cost is 0 for a replay")
}

}
