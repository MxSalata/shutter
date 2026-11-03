/// The tool catalogue a run may offer (CONTRACTS 9, v1.38): the expected names for an agent's toolsets, terminal and
/// attached collections, and the comparison with what the framework discovered, which must match exactly.
Class Shutter.Test.Catalogue Extends %UnitTest.TestCase
{

Method TestExpectedNames()
{
    Set c = "Shutter.Bridge.Catalogue"
    Set e = $CLASSMETHOD(c, "Expected", "Shutter.Tools.Evidence", "SubmitFindings", "contracts,effects")
    Do $$$AssertEquals($LISTTOSTRING(e, ","), "GetSnapshot,GetMessage,GetValidation,GetWardState,GetReceipt,GetTimeline,GetRoute,GetFailure,SubmitFindings,search_contracts,search_effects", "a specialist: the eight evidence tools, its terminal and its collections' searches")
    Set e = $CLASSMETHOD(c, "Expected", "", "SubmitReview", "review")
    Do $$$AssertEquals($LISTTOSTRING(e, ","), "SubmitReview,search_review", "the reviewer: no evidence tools, its terminal, its collection")
    Set e = $CLASSMETHOD(c, "Expected", "Shutter.Tools.Evidence", "SubmitPlan", "")
    Do $$$AssertEquals($LISTLENGTH(e), 9, "the coordinator with no library built: the evidence tools and its terminal")
    Set e = $CLASSMETHOD(c, "Expected", "Shutter.Tools.Other", "SubmitThing", "")
    Do $$$AssertEquals($LISTTOSTRING(e, ","), "?Shutter.Tools.Other,?SubmitThing", "an unknown toolset or terminal is expected of nothing, so a check fails")
}

Method TestCheckIsExactWhateverTheOrderOrCase()
{
    Set c = "Shutter.Bridge.Catalogue"
    Set expected = $CLASSMETHOD(c, "Expected", "Shutter.Tools.Evidence", "SubmitFindings", "contracts")
    Set same = $LISTBUILD("search_contracts", "SUBMITFINDINGS", "getsnapshot", "GetMessage", "GetValidation", "GetWardState", "GetReceipt", "GetTimeline", "GetRoute", "GetFailure")
    Do $$$AssertEquals($CLASSMETHOD(c, "Check", expected, same, .problem), 1, "the same names in another order and case match: " _ problem)
    Set fewer = $LISTBUILD("GetSnapshot", "GetMessage", "GetValidation", "GetWardState", "GetReceipt", "GetTimeline", "GetRoute", "GetFailure", "SubmitFindings")
    Do $$$AssertEquals($CLASSMETHOD(c, "Check", expected, fewer, .problem), 0, "a missing tool fails")
    Do $$$AssertEquals(problem, "missing search_contracts", "and is named: " _ problem)
    Set more = same _ $LISTBUILD("SubmitAnswer")
    Do $$$AssertEquals($CLASSMETHOD(c, "Check", expected, more, .problem), 0, "an extra tool fails")
    Do $$$AssertEquals(problem, "not declared SubmitAnswer", "and is named: " _ problem)
    Set both = fewer _ $LISTBUILD("Shell")
    Do $$$AssertEquals($CLASSMETHOD(c, "Check", expected, both, .problem), 0, "both at once fail")
    Do $$$AssertEquals(problem, "missing search_contracts; not declared Shell", "with both named: " _ problem)
    Do $$$AssertEquals($CLASSMETHOD(c, "Check", "", "", .problem), 1, "nothing expected and nothing found match")
    Do $$$AssertEquals($CLASSMETHOD(c, "Check", $LISTBUILD("?Shutter.Tools.Other"), $LISTBUILD("GetSnapshot"), .problem), 0, "an unknown toolset never matches")
}

Method TestNamesOfTheDiscovery()
{
    Set tools = [{"name": "GetSnapshot", "description": "x"}, {"name": "SubmitFindings"}, {"description": "no name"}]
    Do $$$AssertEquals($LISTTOSTRING(##class(Shutter.Bridge.Catalogue).NamesOf(tools), ","), "GetSnapshot,SubmitFindings", "the names of the framework's descriptions, nameless entries skipped")
    Do $$$AssertEquals(##class(Shutter.Bridge.Catalogue).NamesOf(""), "", "no answer, no names")
}

}
