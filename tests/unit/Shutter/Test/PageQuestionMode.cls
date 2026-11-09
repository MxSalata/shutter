/// A question about a page follows the Agent Board item's own Mode (Shutter.Util.PageQuestion RunMode and Refuses,
/// Shutter.Bridge.RunSpec, the Replay runner, Shutter.Bridge.Record), with no production and no model: an item that records
/// runs it live and no recording of it is stored, an item that replays refuses it with the words the person reads and never
/// serves a stored answer, and an item that runs live runs it as before. A recording made here is deleted after each test.
Class Shutter.Test.PageQuestionMode Extends %UnitTest.TestCase
{

/// The id of a recording a test stored under the page tier's key, for OnAfterOneTest to delete.
Property MadeRecord As %String;

Method OnAfterOneTest(testname As %String) As %Status
{
    If (..MadeRecord '= "") && ##class(Shutter.Bridge.Record).%ExistsId(..MadeRecord) Do ##class(Shutter.Bridge.Record).%DeleteId(..MadeRecord)
    Set ..MadeRecord = ""
    Quit $$$OK
}

/// The Agent Board item's settings as the run reads them, in the mode given.
ClassMethod Item(mode As %String) As %DynamicObject
{
    Quit {"AgentClass": "Shutter.Agent.Explain", "Runner": "Shutter.Bridge.Runner.AIHub", "Mode": (mode), "ProviderConfig": "", "Model": "", "MaxIterations": 8, "TokenBudget": 120000, "RequestTimeoutSeconds": 120}
}

/// A page question's request, as the Case Question item sends it for an instance that resolves to <var>instanceMode</var>.
ClassMethod Ask(instanceMode As %String) As Shutter.Bridge.Msg.AgentRequest
{
    Quit ##class(Shutter.Util.PageQuestion).Request("P-000077", "scenarios", "What is S2?", {"title": "Scenarios", "scenarios": [{"id": "S2", "label": "S2"}]}, "ut-page-mode", instanceMode)
}

/// An item set to record while the instance runs live: the run is live, the item does not refuse it, and no recording of it
/// can be stored, so the person gets a live answer and nothing of the question reaches the recordings.
Method TestARecordingItemRunsItLiveAndStoresNothing()
{
    For instanceMode = "live", "record", "auto" {
        Set spec = ##class(Shutter.Bridge.RunSpec).FromRequest(..Ask(instanceMode), ..Item("record"))
        Do $$$AssertEquals(spec.Mode, "live", "an item that records runs a page question live (the instance says " _ instanceMode _ ")")
        Do $$$AssertNotTrue(##class(Shutter.Util.PageQuestion).Refuses(spec, .why), "and does not refuse it")
        Do $$$AssertEquals(why, "", "with no refusal words")
    }
    Set key = spec.ReplayKey()
    Set before = $ISOBJECT(##class(Shutter.Bridge.Record).Find(key))
    Set response = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Set response.Status = "ok", response.Model = "a-model", response.ResultJSON = {"answer": "S2 is a transfer recovered."}.%ToJSON()
    Set sc = ##class(Shutter.Bridge.Record).Store(spec, response, "", "", .record)
    Do $$$AssertTrue($$$ISERR(sc), "a page question's run is refused as a recording")
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "never stored as a recording", "with the reason: " _ $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertEquals($ISOBJECT(##class(Shutter.Bridge.Record).Find(key)), before, "and nothing is written under its key")
    If $ISOBJECT($GET(record)) && (record.%Id() '= "") Set ..MadeRecord = record.%Id()
}

/// An item set to replay: the item refuses the page question before any runner, with words that say it is answered live
/// only; and the Replay runner itself never serves the answer stored under the tier's key, even when one is there.
Method TestAReplayingItemNeverServesAStoredAnswer()
{
    Set spec = ##class(Shutter.Bridge.RunSpec).FromRequest(..Ask("live"), ..Item("replay"))
    Do $$$AssertNotEquals(spec.Mode, "live", "an item that replays does not run a page question live")
    Do $$$AssertTrue(##class(Shutter.Util.PageQuestion).Refuses(spec, .why), "the item refuses it")
    Do $$$AssertTrue(why [ "answered live only", "with words the person reads: " _ why)
    Set key = spec.ReplayKey()
    Set stored = ##class(Shutter.Bridge.Record).Find(key)
    If '$ISOBJECT(stored) {
        Set stored = ##class(Shutter.Bridge.Record).%New()
        Set stored.Key = key, stored.AgentClass = spec.AgentClass, stored.ConfigVersion = spec.ConfigVersion
        Set stored.Model = "a-model", stored.ResponseJSON = {"status": "ok", "result": {"answer": "Another person's earlier answer."}}.%ToJSON()
        Do $$$AssertStatusOK(stored.%Save(), "a stored answer under the page tier's key, for the test")
        Set ..MadeRecord = stored.%Id()
    }
    Set response = ##class(Shutter.Bridge.Msg.AgentResponse).%New()
    Do $$$AssertStatusOK(##class(Shutter.Bridge.Runner.Replay).%New().Run(spec, .response), "the Replay runner answers")
    Do $$$AssertEquals(response.Status, "no_model", "with no answer")
    Do $$$AssertEquals(response.ResultJSON, "", "and nothing of the stored answer")
    Do $$$AssertEquals(response.RecordId, "", "from no recording")
    Do $$$AssertTrue(response.Error [ "answered live only", "and the same words: " _ response.Error)
    // A case question replays as before.
    Set other = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Set other.AgentClass = "Shutter.Agent.Explain"
    Set ospec = ##class(Shutter.Bridge.RunSpec).FromRequest(other, ..Item("replay"))
    Do $$$AssertEquals(ospec.Mode, "replay", "a case question on a replaying item still replays")
    Do $$$AssertNotTrue(##class(Shutter.Util.PageQuestion).Refuses(ospec, .why), "and is not refused")
}

/// An item set to live runs a page question live, as before, and the mode words are the route's: live and record admit,
/// replay is no_model.
Method TestALiveItemRunsItAsBefore()
{
    Set spec = ##class(Shutter.Bridge.RunSpec).FromRequest(..Ask("live"), ..Item("live"))
    Do $$$AssertEquals(spec.Mode, "live", "an item that runs live runs a page question live")
    Do $$$AssertNotTrue(##class(Shutter.Util.PageQuestion).Refuses(spec, .why), "and does not refuse it")
    Do $$$AssertEquals(spec.RecordKey, "", "with no record key")
    Do $$$AssertEquals(##class(Shutter.Util.PageQuestion).RunMode("live"), "live", "live runs live")
    Do $$$AssertEquals(##class(Shutter.Util.PageQuestion).RunMode("record"), "live", "record runs live")
    Do $$$AssertEquals(##class(Shutter.Util.PageQuestion).RunMode("replay", .detail), "", "replay does not run")
    Do $$$AssertTrue(detail '= "", "and says why")
    Set ok = {"available": true, "reason": null, "until": null, "detail": ""}
    Do $$$AssertTrue(##class(Shutter.Util.PageQuestion).Admit(1, ok, "record", .status, .code, .d), "the route admits a question for an item that records")
    Do $$$AssertNotTrue(##class(Shutter.Util.PageQuestion).Admit(1, ok, "replay", .status, .code, .d), "and refuses one for an item that replays")
    Do $$$AssertEquals(code, "no_model", "as no_model")
    Do $$$AssertTrue($LISTFIND($LISTBUILD("live", "record", "replay"), ##class(Shutter.Util.PageQuestion).ItemMode("No Such Item")), "an item that is not there reads as the instance's auto")
}

}
