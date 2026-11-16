/// Set up the site's switch for typed answers (model_content.setup_answers, CONTRACTS 14.7) at the agent item: a turn
/// that waited in the Agent Board item's queue while an approver switched typed answers off is refused there, before any
/// runner, so nothing goes to a model. The stored profile is put back afterwards.
Class Shutter.Test.SetupSwitch Extends %UnitTest.TestCase
{

Property SavedJson As %String(MAXLEN = "");

Property SavedSource As %String(MAXLEN = 500);

Property HadRow As %Boolean [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set ..HadRow = $ISOBJECT(row)
    If ..HadRow Set ..SavedJson = row.Json, ..SavedSource = row.Source
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    If ..HadRow {
        Do ##class(Shutter.Store.SiteProfile).Store(..SavedJson, ..SavedSource, "test", "", .v)
    } Else {
        Set row = ##class(Shutter.Store.SiteProfile).Row()
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    }
    Quit $$$OK
}

/// The profile in force with the switch on or off, stored as a person saves it.
Method Switch(on As %Boolean)
{
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Do p.%Remove("version")
    If '$ISOBJECT(p.%Get("model_content")) Set p."model_content" = {}
    Do p."model_content".%Set("setup_answers", ''on, "boolean")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "api", "approver", "", .v), "the switch saved " _ $SELECT(on: "on", 1: "off"))
}

Method TestTheAgentItemRefusesATurnOnceTheSwitchIsOff()
{
    Set spec = ##class(Shutter.Bridge.RunSpec).%New()
    Set spec.AgentClass = "Shutter.Agent.SetupGuide", spec.Mode = "live"
    Do ..Switch(1)
    Do $$$AssertNotTrue(##class(Shutter.Util.PageQuestion).Refuses(spec, .detail), "switched on: a live turn goes on to its runner")
    Do ..Switch(0)
    Do $$$AssertTrue(##class(Shutter.Util.PageQuestion).Refuses(spec, .detail), "switched off while it waited: refused before any runner")
    Do $$$AssertTrue(detail [ "switched off", "saying so: " _ detail)
    // A page question's run is not a set-up turn: the switch is not its rule
    Set page = ##class(Shutter.Bridge.RunSpec).%New()
    Set page.AgentClass = $PARAMETER("Shutter.Util.PageQuestion", "AGENTCLASS"), page.Mode = "live"
    Do $$$AssertNotTrue(##class(Shutter.Util.PageQuestion).Refuses(page, .detail), "a live page question is not refused by it")
}

/// A turn that ended while its run waited in the Agent Board item's queue (its time ran out) is refused there with the
/// switch on: nothing of it goes to a model.
Method TestAnEndedTurnIsNotSent()
{
    Do ..Switch(1)
    Set st = "Shutter.Store.SetupTurn"
    Set draft = ##class(Shutter.Store.SiteProfile).Current()
    Do draft.receivers.%Push({"name": "Bed Board", "features": {"conditional_writes": false, "receipts": false, "history": false, "dry_run": false}})
    Set frame = ##class(Shutter.Util.ProfileSetup).Frame(draft, "Bed Board", .problem)
    Do $$$AssertStatusOK($CLASSMETHOD(st, "Create", $CLASSMETHOD(st, "NewConversation"), "Bed Board", "it is the ward whiteboard", {}, frame, 1, 1, "ut-setup", .t), "a turn")
    Do t.Answering()
    Set spec = ##class(Shutter.Bridge.RunSpec).%New()
    Set spec.AgentClass = "Shutter.Agent.SetupGuide", spec.Mode = "live", spec.CorrelationKey = t.TurnId
    Do $$$AssertNotTrue(##class(Shutter.Util.PageQuestion).Refuses(spec, .why), "a turn being answered runs: " _ why)
    Do t.Fail("failed", "No answer within its time")
    Do $$$AssertTrue(##class(Shutter.Util.PageQuestion).Refuses(spec, .why), "an ended turn's run is refused")
    Do $$$AssertTrue(why [ "The turn ended (failed)", "saying so: " _ why)
    Do $CLASSMETHOD(st, "PurgeTurn", t.%Id())
}

}
