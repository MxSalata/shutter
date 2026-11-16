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

/// The case's own message on a header of this namespace, so the resend set's hold can be read for it.
ClassMethod OnHeader(case As Shutter.Store.Case, header As %String)
{
    Set stored = ##class(Shutter.Store.Case).%OpenId(case.%Id())
    Set stored.SourceNamespace = $NAMESPACE, stored.OriginHeaderId = header
    Do stored.%Save()
}

/// R18 for a case whose evidence was collected before an entry was activated: the closures outside the workflow match its
/// stored evidence against the entries in force now, so the entry holds it as it would have held fresh evidence. The
/// engine's delivery leaves it for a person, and the resend set holds its message. Before, both read only the match the
/// old evidence carried.
Method TestAnEntryActivatedAfterTheEvidenceHoldsTheCase()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "state": "gated"})
    Do $$$AssertEquals(case.CurrentSnapshot.SummaryObject().catalogue.entry, "E2", "the evidence was matched with no site entry in force")
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "then an entry for its ward is activated")
    Set stopped = $CLASSMETHOD(site, "StoppedCase", case)
    Do $$$AssertTrue($ISOBJECT(stopped) && (stopped.entry = id), "the entry holds the case: " _ $SELECT($ISOBJECT(stopped): stopped.%ToJSON(), 1: ""))
    Do ..OnHeader(case, "UT-SITE-H1-" _ $JOB)
    Set why = ##class(Shutter.Util.ResendSet).SiteHold($NAMESPACE, "UT-SITE-H1-" _ $JOB)
    Do $$$AssertTrue(why [ ("held by the site's own scenario " _ id), "the resend set holds its message: " _ why)
    Do $$$AssertTrue(why [ "Ring the ward's nurse in charge", "with the site's instructions")
    Set row = ..Delivered()
    Do $$$AssertStatusOK(##class(Shutter.Util.EngineCheck).Settle(case, row, [(row)], "gate:ut"), "settled")
    Set case = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(case.State, "blocked", "the engine's delivery does not close it")
    Do $$$AssertTrue(..Notes(case) [ ("the site's own scenario " _ id _ " asks a person"), "and the note names the entry")
    // A case of another ward, matched the same way before the activation, is not the entry's and settles as before.
    Set other = $CLASSMETHOD(kit, "Case", {"ward": "WARD-C", "state": "gated"})
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(site, "StoppedCase", other)), "a case of another ward is not held")
}

/// The case's record of its entry holds it whatever its current evidence matches (here E2's): the engine's delivery and
/// the resend set read it, as the workflow's own closures do.
Method TestTheRecordHoldsACaseOnAnotherEntrysEvidence()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "state": "gated"})
    Do $$$AssertEquals(case.CurrentSnapshot.SummaryObject().catalogue.entry, "E2", "its current evidence is E2's")
    Do $$$AssertStatusOK(case.MarkSiteEntry(id), "an earlier investigation matched the entry")
    Set stopped = $CLASSMETHOD(site, "StoppedCase", case)
    Do $$$AssertTrue($ISOBJECT(stopped) && (stopped.entry = id), "the record holds it")
    Do $$$AssertTrue($ISOBJECT(stopped) && (stopped.instructions [ "Ring the ward"), "with the version's instructions")
    Do ..OnHeader(case, "UT-SITE-H2-" _ $JOB)
    Do $$$AssertTrue(##class(Shutter.Util.ResendSet).SiteHold($NAMESPACE, "UT-SITE-H2-" _ $JOB) [ id, "the resend set holds its message")
    Set row = ..Delivered()
    Do $$$AssertStatusOK(##class(Shutter.Util.EngineCheck).Settle(case, row, [(row)], "gate:ut"), "settled")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId(case.CaseId).State, "blocked", "the engine's delivery does not close it")
}

/// Evidence matched while the site's entries could not be read answered nothing either way, and so does a store of
/// entries that cannot be read now: either holds the case for a person, never reads as "no entry stopped it".
Method TestAnUnreadableAnswerHoldsTheCase()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "state": "gated"})
    // The kit's snapshot matches again on its way in: the stored evidence is set to the error answer.
    Set snap = case.CurrentSnapshot, summary = snap.SummaryObject()
    Set summary.catalogue = {"decision": "error", "matches": [], "error": "A site entry cannot be read: the row of site entry L9 cannot be opened"}
    Set snap.Summary = summary.%ToJSON()
    Do $$$AssertStatusOK(snap.%Save(), "evidence matched as error")
    Set stopped = $CLASSMETHOD(site, "StoppedCase", case)
    Do $$$AssertTrue($ISOBJECT(stopped) && (stopped.entry = "") && (stopped.unread '= ""), "an error answer holds it: " _ $SELECT($ISOBJECT(stopped): stopped.%ToJSON(), 1: ""))
    Set row = ..Delivered()
    Do $$$AssertStatusOK(##class(Shutter.Util.EngineCheck).Settle(case, row, [(row)], "gate:ut"), "settled")
    Set case = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(case.State, "blocked", "the engine's delivery does not close it")
    Do $$$AssertTrue(case.Headline [ "could not be told", "saying why: " _ case.Headline)
    // Entries in force that cannot be read now hold a case whose own evidence named none.
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Set other = $CLASSMETHOD(kit, "Case", {"ward": "WARD-C", "state": "gated"})
    Set v = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1)
    Set json = v.Json, v.Json = "{""id"": ""L1"", ""pattern"": {"
    Do v.%Save()
    Set stopped = $CLASSMETHOD(site, "StoppedCase", other)
    Do $$$AssertTrue($ISOBJECT(stopped) && (stopped.entry = ""), "entries that cannot be read hold it: " _ $SELECT($ISOBJECT(stopped): stopped.%ToJSON(), 1: ""))
    Set v.Json = json
    Do v.%Save()
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(site, "StoppedCase", other)), "mended, the case of another ward is not held")
}

}
