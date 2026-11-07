/// The escalation email's closing and visit lines (Shutter.Util.EscalationDraft.Build) by the receiver: an ADT case at a
/// receiver with an API keeps its words; an order, a result or an ADT case at a receiver with no API does not promise to
/// verify anything; an order with no PV1 says no visit number was supplied. Each test saves its own case, removed after
/// it, and the stored site profile is put back as it was.
Class Shutter.Test.DraftClosing Extends %UnitTest.TestCase
{

Parameter CASEID = "UT-DRAFTCLOSING";

/// The closing as an ADT case at a receiver with an API has it.
Parameter WITHAPI = "  Reply to this email with what was changed, or record it on the case, then mark the case as handled by the team on the case page. Reinvestigate is for when the message is still due: Shutter collects fresh evidence and may plan another resend, which this site's policy may release with no person.";

/// The closing at a receiver Shutter can't read.
Parameter NOAPI = "  Reply to this email with what was changed, or record it on the case, then mark the case as handled by the team: Shutter can't read this receiver, so it can't verify the correction.";

Parameter ORDERTEXT = "This message is ORU, not ADT: Shutter resends only ADT, so it sends nothing and a person decides.";

Property CaseRowId As %String;

Property SavedProfile As %String;

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Do ..Purge()
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set ..HadProfileRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: "")
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    Do p.receivers.%Push({"name": "UT Lab Out", "tier": 2, "category": "orders_results", "system": "a made-up laboratory system"})
    Do p.receivers.%Push({"name": "UT Lab Api", "tier": 2, "category": "orders_results", "system": "a made-up laboratory system", "api": {"base": "http://127.0.0.1:1/x"}})
    Do p.receivers.%Push({"name": "UT Beds Plain", "tier": 2, "category": "current_state", "system": "a made-up bed system", "features": {"conditional_writes": false, "receipts": false, "history": false, "dry_run": false}})
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Version = version
    Set row.Json = p.%ToJSON()
    Quit row.%Save()
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..Purge()
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..HadProfileRow {
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    } ElseIf $ISOBJECT(row) {
        Set row.Json = ..SavedProfile
        Do row.%Save()
    }
    Quit $$$OK
}

Method Purge()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", ..#CASEID)
    While rs.%Next() {
        Set id = rs.%Get("ID")
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
        Kill ^Shutter.Counter("event", id)
        Do ##class(Shutter.Store.Case).%DeleteId(id)
    }
}

/// The draft of a saved case at a receiver, with or without an encounter, an order's words or an ADT case's.
Method Draft(receiver As %String, encounter As %String, failureText As %String = "") As %String
{
    Do ..Purge()
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = ..#CASEID, c.OperationKey = "PAS^HOSP^MRN9101^" _ encounter _ "^transfer^2026-11-07T03:00:00Z"
    Set c.Event = "transfer", c.EncounterId = encounter, c.PatientId = "MRN9101", c.FailureKind = "delivery_failed"
    Set c.Receiver = receiver, c.FailureText = failureText, c.State = "escalated"
    Do $$$AssertStatusOK(c.%Save(), "the case is saved")
    Set subject = "", body = ""
    Do $$$AssertStatusOK(##class(Shutter.Util.EscalationDraft).Build(c, {"name": "the team"}, .subject, .body), "the email is drafted")
    Quit body
}

/// The lines under a heading of the draft, up to the blank line.
ClassMethod Under(body As %String, heading As %String) As %String
{
    Quit $PIECE($PIECE(body, heading _ $CHAR(13, 10), 2), $CHAR(13, 10, 13, 10), 1)
}

Method TestAdtAtAReceiverWithAnApiKeepsItsWords()
{
    Set receiver = $PARAMETER("Shutter.Production", "RECEIVER")
    Set body = ..Draft(receiver, "ENC-9101")
    Do $$$AssertEquals(..Under(body, "WHEN IT IS CORRECTED"), ..#WITHAPI, "the closing")
    Do $$$AssertTrue(body [ ("  Encounter (visit number): ENC-9101" _ $CHAR(13, 10)), "the visit line")
    Do $$$AssertNotTrue(body [ "can't read this receiver", "and no other closing")
}

Method TestAdtPatientLevelKeepsItsWords()
{
    Set receiver = $PARAMETER("Shutter.Production", "RECEIVER")
    Set body = ..Draft(receiver, "-")
    Do $$$AssertTrue(body [ "none (a patient-level message)", "the visit line")
    Do $$$AssertTrue(body [ "the message names no encounter (a patient-level message)", "what the receiver holds")
    Do $$$AssertTrue(..Under(body, "WHEN IT IS CORRECTED") [ "it cannot verify a merge or a cancellation against", "the closing")
    Do $$$AssertNotTrue(body [ "No visit number was supplied", "and no words of an order's")
}

Method TestOrdersResultsCaseDoesNotPromise()
{
    For receiver = "UT Lab Out", "UT Lab Api" {
        Set body = ..Draft(receiver, "ENC-9101", ..#ORDERTEXT)
        Do $$$AssertEquals(..Under(body, "WHEN IT IS CORRECTED"), ..#NOAPI, "the closing at " _ receiver)
        Do $$$AssertNotTrue(body [ "Reinvestigate", "and no way on through a resend")
    }
    // The category alone says so, whatever the case's text
    Set body = ..Draft("UT Lab Api", "ENC-9101")
    Do $$$AssertEquals(..Under(body, "WHEN IT IS CORRECTED"), ..#NOAPI, "the closing at the category")
}

Method TestMllpAdtWithAnEncounterDoesNotPromise()
{
    Set body = ..Draft("UT Beds Plain", "ENC-9101")
    Do $$$AssertEquals(..Under(body, "WHEN IT IS CORRECTED"), ..#NOAPI, "the closing")
    Do $$$AssertTrue(body [ ("  Encounter (visit number): ENC-9101" _ $CHAR(13, 10)), "the visit line keeps the encounter")
}

Method TestAnOrderWithNoVisitNumberSaysSo()
{
    For encounter = "-", "" {
        Set body = ..Draft("UT Lab Out", encounter, ..#ORDERTEXT)
        Do $$$AssertTrue(body [ "Encounter (visit number): No visit number was supplied.", "the visit line: " _ encounter)
        Do $$$AssertTrue(..Under(body, "WHAT UT LAB OUT HOLDS") [ "No visit number was supplied", "what the receiver holds")
        Do $$$AssertNotTrue(body [ "patient-level", "no patient-level message")
        Do $$$AssertEquals(..Under(body, "WHEN IT IS CORRECTED"), ..#NOAPI, "the closing")
        Do $$$AssertNotTrue(body [ "merge or a cancellation", "an order is no merge")
    }
}

}
