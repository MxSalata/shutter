/// The demo's PurgeStore (Shutter.Setup; CONTRACTS 12): the precedents and the board leads go with the cases they name,
/// since the case counter starts again at C-000001 and a new case would otherwise read a purged case's history, and the
/// reset stamp is set. The purge empties every case table of the instance, so the purge itself is tried only when the
/// case store is empty (as it is in CI, where the suite runs before any scenario); on a demo that has been played the
/// test is reported as skipped rather than taking its cases, and on an instance that is not a demo, or without
/// Shutter_ScenarioReset (1.4.3; Shutter_Scenarios before), only the refusal is checked.
Class Shutter.Test.Purge Extends %UnitTest.TestCase
{

Property SavedWindow As %String;

Property SavedReset As %String;

Method OnBeforeAllTests() As %Status
{
    Set ..SavedWindow = $GET(^Shutter.Config("leadWindowSeconds"), $CHAR(0))
    Set ..SavedReset = $GET(^Shutter.Config("resetAt"), $CHAR(0))
    Kill ^Shutter.Config("leadWindowSeconds")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    If ..SavedWindow = $CHAR(0) { Kill ^Shutter.Config("leadWindowSeconds") } Else { Set ^Shutter.Config("leadWindowSeconds") = ..SavedWindow }
    If ..SavedReset = $CHAR(0) { Kill ^Shutter.Config("resetAt") } Else { Set ^Shutter.Config("resetAt") = ..SavedReset }
    Quit $$$OK
}

Method Conditions() As %DynamicObject
{
    Quit {"delivery": "failed", "receiver_answer": "unavailable", "event": "transfer", "receipt": "absent", "encounter_state": "admitted", "chain": "single"}
}

Method TestPurgeTakesThePrecedentsAndTheLeads()
{
    Set setup = "Shutter.Setup", pre = "Shutter.Store.Precedent", leads = "Shutter.Store.BoardLead"
    If '$GET(^Shutter.Config("demo")) || '$SYSTEM.Security.Check("Shutter_ScenarioReset", "USE") {
        Set answer = $CLASSMETHOD(setup, "PurgeStore")
        Do $$$AssertNotTrue(answer ? 1.N, "not a demo instance with Shutter_ScenarioReset: the purge is refused and nothing is tried: " _ answer)
        Do $$$LogMessage("not a demo instance with Shutter_ScenarioReset: the purge itself was not tried here")
        Quit
    }
    Set cases = 0
    &sql(SELECT COUNT(*) INTO :cases FROM Shutter_Store."Case")
    If cases > 0 {
        Do $$$AssertSkipped("the case store holds " _ cases _ " case(s) that are not this test's: the purge is not tried here, since it would take them")
        Quit
    }
    Set receiver = "test-purge-" _ $JOB, signature = "sig:test-purge-" _ $JOB
    Set policy = ##class(Shutter.Operation.Gate).#POLICYVERSION
    Set profile = ##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0)
    // A precedent and a lead for a case whose id the next case after the purge takes again.
    Set caseId = "C-000001"
    Set sc = $CLASSMETHOD(pre, "RecordValues", caseId, receiver, ..Conditions(), "E03", "resend", "resend", "sha256:purge", "approver", "approved", policy, profile, .p)
    Do $$$AssertStatusOK(sc, "a precedent names the case")
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = caseId, case.Receiver = receiver
    Set sc = $CLASSMETHOD(leads, "Begin", signature, case, "", .lead)
    Do $$$AssertStatusOK(sc, "a lead names the case")
    Set s = $CLASSMETHOD(pre, "Summary", receiver, ..Conditions())
    Do $$$AssertEquals(s.approved _ "|" _ s.lastCaseId, "1|" _ caseId, "before the purge the precedent is read")
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(leads, "Current", signature)), "and the lead is followed")
    Set answer = $CLASSMETHOD(setup, "PurgeStore")
    Do $$$AssertTrue((answer ? 1.N) && (answer >= 25), "the purge counts the tables it emptied, the precedents and the leads among them: " _ answer)
    Set s = $CLASSMETHOD(pre, "Summary", receiver, ..Conditions())
    Do $$$AssertEquals(s.approved _ "|" _ s.rejected _ "|" _ s.lastCaseId, "0|0|", "after it the precedent is gone, so the next C-000001 reads no history")
    Do $$$AssertEquals($CLASSMETHOD(leads, "Current", signature), "", "and the lead is gone")
    Set precedents = 0, boardLeads = 0
    &sql(SELECT COUNT(*) INTO :precedents FROM Shutter_Store.Precedent)
    &sql(SELECT COUNT(*) INTO :boardLeads FROM Shutter_Store.BoardLead)
    Do $$$AssertEquals(precedents _ "|" _ boardLeads, "0|0", "both tables are empty")
    Do $$$AssertEquals($DATA(^Shutter.Counter("case")), 0, "the case counter is reset: the next case is C-000001")
    Set resetAt = $GET(^Shutter.Config("resetAt"))
    Do $$$AssertTrue($MATCH(resetAt, "^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$"), "the reset stamp is set, ISO UTC: " _ resetAt)
    Do $$$AssertTrue($EXTRACT(resetAt, 1, 10) = $EXTRACT(##class(Shutter.Util.Time).NowUTC(), 1, 10), "dated now")
    // The stamps are whole seconds, and a lead in the reset's own second counts as before it (BoardLead.Current).
    If ##class(Shutter.Util.Time).NowUTC() = resetAt {
        Set sc = $CLASSMETHOD(leads, "Begin", signature, case, "", .same)
        Do $$$AssertStatusOK(sc, "a lead begun in the purge's own second")
        Do $$$AssertEquals($CLASSMETHOD(leads, "Current", signature), "", "counts as before it, so it is not followed")
        &sql(DELETE FROM Shutter_Store.BoardLead WHERE Signature = :signature)
    }
    For i = 1:1:30 { Quit:(##class(Shutter.Util.Time).NowUTC() ]] resetAt)  Hang 0.1 }
    Set sc = $CLASSMETHOD(leads, "Begin", signature, case, "", .again)
    Do $$$AssertStatusOK(sc, "a lead begun after the purge's second")
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(leads, "Current", signature)), "is followed: the stamp ignores only what came before it or in its own second")
    &sql(DELETE FROM Shutter_Store.BoardLead WHERE Signature = :signature)
}

}
