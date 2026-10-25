/// The API mimic's core side (docs/CONTRACTS.md, section 4), with no AI Hub and no HTTP: the switch
/// ^Shutter.Config("aihub","mock") counts on a demo instance only; an item set to auto resolves to live under it only
/// through the live runner, else to what the instance says; a response labelled model mock is refused as a recording, at
/// the store and at the imports; a run the mimic answered costs 0; and record mode is refused while the switch is set,
/// the recorded mode left as it was. Each test sets the switch, the demo flag and the recorded mode and puts them back
/// as they were; the rows a test writes (a case, its runs, a price, recordings under ut:mimic:) are removed after it.
Class Shutter.Test.Mimic Extends %UnitTest.TestCase
{

Parameter SWITCH = "AI.LLM.ShutterMock";

/// The settings as they were before the test: whether each node had a value, and the value.
Property Saved As %String [ MultiDimensional ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Kill i%Saved
    Do ..Save("mock"), ..Save("mockModel"), ..Save("mode"), ..Save("demo")
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..Restore("mock"), ..Restore("mockModel"), ..Restore("mode"), ..Restore("demo")
    Do ..Purge()
    Quit $$$OK
}

/// The global node of a setting: the demo flag at the root of ^Shutter.Config, the rest under "aihub".
ClassMethod Node(name As %String) As %String
{
    If name = "demo" Quit $NAME(^Shutter.Config("demo"))
    Quit $NAME(^Shutter.Config("aihub", name))
}

Method Save(name As %String)
{
    Set ref = ..Node(name)
    Set i%Saved(name) = $DATA(@ref), i%Saved(name, "value") = $GET(@ref)
}

/// The node's value as it was, or no value (its descendants, if any, untouched).
Method Restore(name As %String)
{
    Set ref = ..Node(name)
    If i%Saved(name) # 2 { Set @ref = i%Saved(name, "value") } Else { ZKill @ref }
}

/// The rows a test may have left: the recordings under the test's keys, the test case with its runs, the test's price.
Method Purge()
{
    &sql(DELETE FROM Shutter_Bridge.Record WHERE "Key" %STARTSWITH 'ut:mimic:')
    Set case = ##class(Shutter.Store.Case).ByCaseId("UT-MIMIC")
    If $ISOBJECT(case) {
        Set id = case.%Id()
        &sql(DELETE FROM Shutter_Store.AgentRun WHERE "Case" = :id)
        Do ##class(Shutter.Store.Case).%DeleteId(id)
    }
    &sql(DELETE FROM Shutter_Store.ModelPrice WHERE Model = 'ut-mimic-model')
}

/// The switch counts on a demo instance only: MockConfig answers it there and "" on a site, whatever the global holds.
Method TestSwitchCountsOnADemoOnly()
{
    Set ^Shutter.Config("aihub", "mock") = ..#SWITCH
    Set ^Shutter.Config("demo") = 1
    Do $$$AssertEquals(##class(Shutter.Setup).MockConfig(), ..#SWITCH, "on a demo the switch is the mimic's configuration")
    Set ^Shutter.Config("demo") = 0
    Do $$$AssertEquals(##class(Shutter.Setup).MockConfig(), "", "on a site the switch is ignored")
    Set ^Shutter.Config("demo") = 1
    Kill ^Shutter.Config("aihub", "mock")
    Do $$$AssertEquals(##class(Shutter.Setup).MockConfig(), "", "and with the switch gone there is none")
}

/// An item's explicit mode stands. Under the switch, auto is live only through the live runner (the aihub module);
/// where the runner is absent (this instance, when core alone is loaded) and on a site it is what the instance says.
Method TestResolveMode()
{
    Set ^Shutter.Config("demo") = 1
    Set ^Shutter.Config("aihub", "mode") = "replay"
    Set ^Shutter.Config("aihub", "mock") = ..#SWITCH
    Set runner = ##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Bridge.Runner.AIHub")
    Set underSwitch = $SELECT(runner: "live", 1: "replay")
    Do $$$AssertEquals(##class(Shutter.Bridge.Operation.Agent).ResolveMode("record", ..#SWITCH), "record", "an explicit mode stands under the switch")
    Do $$$AssertEquals(##class(Shutter.Bridge.Operation.Agent).ResolveMode("Replay", ..#SWITCH), "replay", "whatever its case")
    Do $$$AssertEquals(##class(Shutter.Bridge.Operation.Agent).ResolveMode("auto", ..#SWITCH), underSwitch, "auto under the switch: live through the live runner, else the instance's mode (runner present: " _ runner _ ")")
    Do $$$AssertEquals(##class(Shutter.Bridge.Operation.Agent).ResolveMode("", ..#SWITCH), underSwitch, "an empty setting is auto")
    Do $$$AssertEquals(##class(Shutter.Bridge.Operation.Agent).ResolveMode("auto"), underSwitch, "the switch read by ResolveMode itself says the same")
    Do $$$AssertEquals(##class(Shutter.Bridge.Operation.Agent).ResolveMode("auto", ""), "replay", "with no switch, the instance's mode")
    Set ^Shutter.Config("demo") = 0
    Do $$$AssertEquals(##class(Shutter.Bridge.Operation.Agent).ResolveMode("auto", ..#SWITCH), "replay", "on a site the switch is ignored, whatever the caller read")
    Do $$$AssertEquals(##class(Shutter.Bridge.Operation.Agent).ResolveMode("auto"), "replay", "and ResolveMode reads none")
    Set ^Shutter.Config("demo") = 1
    Kill ^Shutter.Config("aihub", "mock")
    Set ^Shutter.Config("aihub", "mode") = "live"
    Do $$$AssertEquals(##class(Shutter.Bridge.Operation.Agent).ResolveMode("auto"), "live", "the instance's recorded mode, live")
}

/// A response the mimic answered (model mock) is refused as a recording: nothing is written under the key. A model's
/// response under the same key is stored.
Method TestStoreRefusesAMockRun()
{
    Set spec = ##class(Shutter.Bridge.RunSpec).%New()
    Set spec.AgentClass = "Shutter.Agent.Conformance", spec.MemberCode = "conformance", spec.Mode = "record"
    Set spec.RecordKey = "ut:mimic:store", spec.CorrelationKey = "UT-MIMIC"
    Set response = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set response.Model = "mock", response.ProviderConfig = "ShutterMock", response.Status = "ok", response.Mode = "record"
    Set sc = ##class(Shutter.Bridge.Record).Store(spec, response, "", "[]", .record)
    Do $$$AssertStatusNotOK(sc, "the store refuses a response labelled mock")
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "API mimic", "and says why: " _ $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertNotTrue($ISOBJECT($GET(record)), "no record comes back")
    Do $$$AssertNotTrue($ISOBJECT(##class(Shutter.Bridge.Record).Find("ut:mimic:store")), "and nothing is stored under the key")
    Set response.Model = "ut-mimic-model", response.ProviderConfig = "Shutter"
    Set sc = ##class(Shutter.Bridge.Record).Store(spec, response, "", "[]", .record)
    Do $$$AssertStatusOK(sc, "a model's response is stored")
    Do $$$AssertTrue($ISOBJECT($GET(record)) && (record.Model = "ut-mimic-model"), "and comes back with its model")
    Do $$$AssertNotTrue(##class(Shutter.Bridge.Record).IsMock(record), "which is not the mimic's")
}

/// The imports refuse a recording labelled mock, by its model or by the response it holds, and import a model's.
Method TestImportRefusesAMockRecording()
{
    Set out = ##class(Shutter.Bridge.Record).ImportJSON("{""key"": ""ut:mimic:import"", ""model"": ""mock"", ""memberCode"": ""conformance"", ""response"": {""status"": ""ok"", ""model"": ""mock""}}")
    Do $$$AssertEquals($EXTRACT(out, 1, 6), "ERROR:", "a recording labelled mock is refused: " _ out)
    Do $$$AssertNotTrue($ISOBJECT(##class(Shutter.Bridge.Record).Find("ut:mimic:import")), "and not stored")
    Set out = ##class(Shutter.Bridge.Record).ImportJSON("{""key"": ""ut:mimic:import"", ""model"": ""ut-mimic-model"", ""response"": {""status"": ""ok"", ""model"": ""ut-mimic-model"", ""provider_config"": ""ShutterMock""}}")
    Do $$$AssertEquals($EXTRACT(out, 1, 6), "ERROR:", "so is one whose response names the mimic's configuration: " _ out)
    Do $$$AssertNotTrue($ISOBJECT(##class(Shutter.Bridge.Record).Find("ut:mimic:import")), "and not stored either")
    Set out = ##class(Shutter.Bridge.Record).ImportJSON("{""key"": ""ut:mimic:import"", ""model"": ""ut-mimic-model"", ""response"": {""status"": ""ok"", ""model"": ""ut-mimic-model""}}")
    Do $$$AssertEquals(out, "ut:mimic:import", "a model's recording is imported")
    Set record = ##class(Shutter.Bridge.Record).Find("ut:mimic:import")
    Do $$$AssertTrue($ISOBJECT(record), "and found under its key")
}

/// A run the mimic answered costs nothing whatever its tokens, as a replay does; a model's run is priced.
Method TestAMockRunCostsNothing()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-MIMIC", case.OperationKey = "PAS^HOSP^MRN9003^ENC-9003^transfer^2026-10-19T09:00:00Z"
    Set case.Event = "transfer", case.EncounterId = "ENC-9003", case.PatientId = "MRN9003", case.FailureKind = "delivery_failed"
    Do $$$AssertStatusOK(case.%Save(), "the test case")
    Set price = ##class(Shutter.Store.ModelPrice).%New()
    Set price.Model = "ut-mimic-model", price.InputPerMTok = 10, price.OutputPerMTok = 20, price.CacheReadPerMTok = 1, price.Source = "unit test"
    Do $$$AssertStatusOK(price.%Save(), "a price for the test's model")
    Set response = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set response.Status = "ok", response.Mode = "live", response.Model = "mock", response.ProviderConfig = "ShutterMock"
    Set response.PromptTokens = 10000, response.CompletionTokens = 2000, response.StartedAt = "2026-10-19T09:00:00Z"
    Set sc = ##class(Shutter.Store.AgentRun).FromResponse(case, "", "specialist", "conformance", response, "ut:mimic", .run)
    Do $$$AssertStatusOK(sc, "the mock run is recorded")
    Do $$$AssertEquals(run.Model, "mock", "labelled mock")
    Do $$$AssertEquals(+run.CostUSD, 0, "and costs 0")
    Set response.Model = "ut-mimic-model", response.ProviderConfig = "Shutter"
    Set sc = ##class(Shutter.Store.AgentRun).FromResponse(case, "", "specialist", "conformance", response, "ut:mimic", .priced)
    Do $$$AssertStatusOK(sc, "the model's run is recorded")
    Do $$$AssertEquals(+priced.CostUSD, 0.14, "and priced: 10,000 in at 10 and 2,000 out at 20 per million")
    Set response.Mode = "replay"
    Set sc = ##class(Shutter.Store.AgentRun).FromResponse(case, "", "specialist", "conformance", response, "ut:mimic", .replayed)
    Do $$$AssertStatusOK(sc, "the replay is recorded")
    Do $$$AssertEquals(+replayed.CostUSD, 0, "and a replay costs 0 too")
}

/// Record mode is refused while the switch is set, the recorded mode left as it was; with the switch gone, or on a
/// site, where the switch does not count, it is recorded.
Method TestRecordRefusedUnderTheSwitch()
{
    Set ^Shutter.Config("demo") = 1
    Set ^Shutter.Config("aihub", "mode") = "replay"
    Set ^Shutter.Config("aihub", "mock") = ..#SWITCH
    Do $$$AssertEquals(##class(Shutter.Setup).RecordAgentMode("record"), "refused: the API mimic is on", "record is refused")
    Do $$$AssertEquals($GET(^Shutter.Config("aihub", "mode")), "replay", "and the mode is left as it was")
    Do $$$AssertEquals(##class(Shutter.Setup).RecordAgentMode("live"), "live", "live is recorded under the switch")
    Do $$$AssertEquals($GET(^Shutter.Config("aihub", "mode")), "live", "and stands")
    Kill ^Shutter.Config("aihub", "mock")
    Do $$$AssertEquals(##class(Shutter.Setup).RecordAgentMode("record"), "record", "with the switch gone, record is recorded")
    Do $$$AssertEquals($GET(^Shutter.Config("aihub", "mode")), "record", "and stands")
    Set ^Shutter.Config("aihub", "mock") = ..#SWITCH, ^Shutter.Config("demo") = 0
    Do $$$AssertEquals(##class(Shutter.Setup).RecordAgentMode("record"), "record", "a site ignores the switch")
}

}
