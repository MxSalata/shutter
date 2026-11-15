/// The closures that run outside the case workflow, on a case one of the site's own entries matched (CONTRACTS 6.8, R18):
/// the engine's delivery read by the gate or the releaser, and the outage close. Neither resolves such a case: what the
/// engine did is noted on it, and the case stays for the person with the site's instructions. A case no site entry
/// matched is settled as before.
Class Shutter.Test.SiteClosures Extends %UnitTest.TestCase
{

Method OnBeforeOneTest() As %Status
{
    Do ##class(Shutter.Test.SiteKit).PurgeAll()
    Quit ##class(Shutter.Test.SiteKit).Reset()
}

Method OnAfterAllTests() As %Status
{
    Do ##class(Shutter.Test.SiteKit).PurgeAll()
    Quit ##class(Shutter.Test.SiteKit).Reset()
}

/// The gate's ENGINE_DELIVERED row, with the acknowledgement established.
ClassMethod Delivered() As %DynamicObject
{
    Set row = {"check": "ordering", "result": "block", "reason_code": "ENGINE_DELIVERED", "detail": "The engine delivered this message itself (header 77): nothing to resend.", "engine": {"words": "The engine delivered this message (header 77) and the receiver acknowledged it"}}
    Do row.engine.%Set("established", 1, "boolean")
    Quit row
}

/// The case's notes, newest first, as one text.
ClassMethod Notes(case As Shutter.Store.Case) As %String
{
    Set out = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? AND Kind = 'note' ORDER BY ID DESC", case.%Id())
    While rs.%Next() { Set out = out _ rs.%Get("Text") _ " | " }
    Quit out
}

Method TestTheEngineDeliveryDoesNotCloseASiteEntrysCase()
{
    Set kit = "Shutter.Test.SiteKit"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "state": "gated"})
    Do $$$AssertEquals(case.CurrentSnapshot.SummaryObject().catalogue.entry, id, "the case is the site entry's")
    Set row = ..Delivered()
    Do $$$AssertStatusOK(##class(Shutter.Util.EngineCheck).Settle(case, row, [(row)], "gate:ut"), "settled")
    Set case = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(case.State, "blocked", "the case is not resolved: it waits for a person")
    Do $$$AssertTrue(case.Headline [ id, "the headline names the entry: " _ case.Headline)
    Set notes = ..Notes(case)
    Do $$$AssertTrue(notes [ "The engine delivered this message", "the delivery is noted on the case: " _ notes)
    Do $$$AssertTrue(notes [ ("the site's own scenario " _ id _ " asks a person"), "with the entry")
    Do $$$AssertTrue(notes [ "Ring the ward's nurse in charge", "and its instructions")
    // A case no site entry matched is settled by the engine's delivery, as before.
    Set other = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "state": "gated"})
    Do $$$AssertNotEquals(other.CurrentSnapshot.SummaryObject().catalogue.entry, id, "a case the entry does not match")
    Do $$$AssertStatusOK(##class(Shutter.Util.EngineCheck).Settle(other, row, [(row)], "gate:ut"), "settled")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(other.CaseId).State, "resolved", "is resolved")
}

/// The outage close's verdict: a delivered, acknowledged message whose case a site entry stopped is not resolved.
Method TestTheOutageCloseLeavesASiteEntrysCase()
{
    Set c = {"state": "escalated", "failureKind": "delivery_failed", "failureReasonCode": "", "deliveryHeader": "77", "deliveryCustody": "delivered", "deliveryStatus": "", "effectiveAck": "connection", "words": "the shared sentence"}
    Do c.%Set("identity", 0, "boolean")
    Do $$$AssertTrue(##class(Shutter.Operation.OutageClose).LinkVerdict(c).resolve, "without a site entry it is resolved")
    Set c.site = "L3"
    Set v = ##class(Shutter.Operation.OutageClose).LinkVerdict(c)
    Do $$$AssertNotTrue(v.resolve, "with one it is not")
    Do $$$AssertNotTrue(v.finished, "it stays open on the card")
    Do $$$AssertTrue(v.site, "marked as the site entry's")
    Do $$$AssertTrue(v.reason [ "L3", "naming the entry: " _ v.reason)
    // Before the engine is read, the site entry decides nothing new: a case the workflow still works on stays the
    // workflow's.
    Set c.state = "investigating", c.deliveryCustody = ""
    Do $$$AssertNotTrue(##class(Shutter.Operation.OutageClose).LinkVerdict(c).resolve, "an investigating case is not resolved either")
}

}
