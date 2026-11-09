/// A receiver the onboarding drafted (Shutter.Util.Onboard.DraftReceivers): until a person fills in its entry, its system
/// text is a placeholder and it has no API. A person reads it by its item and namespace (SiteProfile.DisplayName), in the
/// escalation email and the case page alike, and the reason a case on it stops says it was declared with no API, with
/// filling in the entry as the next action, under the code RECEIVER_UNREADABLE. The site profile row is changed for each
/// test and put back after it; the case is saved as UT-DRAFTRECEIVER and removed after each test.
Class Shutter.Test.DraftReceiver Extends %UnitTest.TestCase
{

Parameter CASEID = "UT-DRAFTRECEIVER";

Parameter RECEIVER = "UT Draft Out";

Parameter NS = "UTLABS";

Property CaseRowId As %String;

Property HadProfileRow As %Boolean;

Property SavedProfile As %String(MAXLEN = "");

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", ..#CASEID)
    While rs.%Next() { Do ..Purge(rs.%Get("ID")) }
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set ..HadProfileRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: "")
    // The entry exactly as the onboarding drafts it, beside one a person has named.
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    If '$ISOBJECT(p.%Get("receivers")) Set p.receivers = []
    Do p.receivers.%Push({"name": (..#RECEIVER), "system": (..#RECEIVER _ " in " _ ..#NS _ ##class(Shutter.Store.SiteProfile).#DRAFTSYSTEM), "tier": 3, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "features": {"conditional_writes": false, "receipts": false, "history": false, "dry_run": false}, "draft": true, "namespace": (..#NS), "item": (..#RECEIVER)})
    Do p.receivers.%Push({"name": "UT Named Out", "system": "Trust LIMS", "tier": 3, "features": {"conditional_writes": false, "receipts": false, "history": false, "dry_run": false}})
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Version = version
    Set row.Json = p.%ToJSON()
    Set sc = row.%Save()
    Quit:$$$ISERR(sc) sc
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = ..#CASEID, c.OperationKey = "LAB^HOSP^T900001^-^result^2026-11-08T18:12:31Z"
    Set c.Event = "result", c.EncounterId = "-", c.PatientId = "T900001", c.FailureKind = "delivery_failed", c.Receiver = ..#RECEIVER
    Set c.FailureText = "This message is ORU, not ADT: Shutter resends only ADT, so nothing is planned"
    Set c.State = "escalated", c.ClosedAt = "1970-01-01T00:00:00Z"
    Set sc = c.%Save()
    Set ..CaseRowId = c.%Id()
    Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..Purge(..CaseRowId)
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..HadProfileRow {
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    } ElseIf $ISOBJECT(row) {
        Set row.Json = ..SavedProfile
        Do row.%Save()
    }
    Quit $$$OK
}

ClassMethod Purge(id As %String)
{
    Quit:id=""
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.Escalation WHERE ""Case"" = ?", id)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
    Kill ^Shutter.Counter("event", id)
    If ##class(Shutter.Store.Case).%ExistsId(id) Do ##class(Shutter.Store.Case).%DeleteId(id)
}

/// A named system reads as written; a draft reads as its item and namespace, never the placeholder.
Method TestDisplayName()
{
    Set sp = "Shutter.Store.SiteProfile", note = $PARAMETER(sp, "DRAFTSYSTEM")
    Do $$$AssertEquals($CLASSMETHOD(sp, "DisplayName", {"name": "LIMS Out", "system": "Trust LIMS"}), "Trust LIMS", "a named system is unchanged")
    Do $$$AssertEquals($CLASSMETHOD(sp, "DisplayName", {"name": "LIMS Out", "system": ("LIMS Out in LABS" _ note), "draft": true, "item": "LIMS Out", "namespace": "LABS"}), "LIMS Out in LABS", "a draft gives its item and namespace")
    Do $$$AssertEquals($CLASSMETHOD(sp, "DisplayName", {"name": "LIMS Out", "system": "", "draft": true, "item": "LIMS Out"}), "LIMS Out", "a draft with no namespace gives its item")
    Do $$$AssertEquals($CLASSMETHOD(sp, "DisplayName", {"name": "LIMS Out", "system": ("LIMS Out in LABS" _ note), "draft": true}), "LIMS Out in LABS", "a draft with no item drops the placeholder from its system")
    Do $$$AssertEquals($CLASSMETHOD(sp, "DisplayName", {"name": "LIMS Out", "system": "Trust LIMS", "draft": true, "item": "LIMS Out", "namespace": "LABS"}), "Trust LIMS", "a draft a person has named keeps that name")
    Do $$$AssertEquals($CLASSMETHOD(sp, "DisplayName", {"name": "LIMS Out"}), "LIMS Out", "no system gives the name")
    Do $$$AssertEquals($CLASSMETHOD(sp, "DisplayName", "", "LIMS Out"), "LIMS Out", "and no entry the name asked for")
    Do $$$AssertEquals($CLASSMETHOD(sp, "ReceiverLabel", ..#RECEIVER), ..#RECEIVER _ " in " _ ..#NS, "the label of the drafted receiver")
    Do $$$AssertEquals($CLASSMETHOD(sp, "ReceiverLabel", "UT Named Out"), "Trust LIMS", "and of the named one")
}

/// The email's first line names the item and namespace, with no placeholder in the sentence.
Method TestEscalationFirstLine()
{
    Set c = ##class(Shutter.Store.Case).ByCaseId(..#CASEID)
    Do $$$AssertTrue(c.NotModelled(), "a result Shutter does not model")
    Do $$$AssertStatusOK(##class(Shutter.Util.EscalationDraft).Build(c, {"name": "Pathology IT"}, .subject, .body), "a draft for the drafted receiver")
    Set first = $PIECE($PIECE(body, $CHAR(13, 10), 3), $CHAR(13, 10), 1)
    Do $$$AssertEquals($EXTRACT(first, 1, $LENGTH("A message to " _ ..#RECEIVER _ " in " _ ..#NS _ " failed.")), "A message to " _ ..#RECEIVER _ " in " _ ..#NS _ " failed.", "the first line: " _ first)
    Do $$$AssertNotTrue(body [ "a person fills this in", "no placeholder anywhere in the body")
}

/// RECEIVER_UNREADABLE on a drafted receiver says it was declared with no API, and filling in its entry comes next; on any
/// other receiver the catalogue's words stand, and the gate's detail with them.
Method TestReasonForADraft()
{
    Set br = "Shutter.Store.BlockReason"
    Set plain = $CLASSMETHOD(br, "ByCode", "RECEIVER_UNREADABLE")
    Do $$$AssertTrue($ISOBJECT(plain), "the catalogue holds RECEIVER_UNREADABLE")
    Quit:'$ISOBJECT(plain)
    Set r = $CLASSMETHOD(br, "ForReceiver", "RECEIVER_UNREADABLE", ..#RECEIVER)
    Do $$$AssertEquals(r.Code, "RECEIVER_UNREADABLE", "the code is kept")
    Do $$$AssertTrue(r.Text [ "declared with no API", "the text says the receiver was declared with no API: " _ r.Text)
    Do $$$AssertTrue(r.Text [ (..#RECEIVER _ " in " _ ..#NS), "and names it by its item and namespace")
    Do $$$AssertTrue(r.NextAction [ "Fill in the receiver's entry", "the next action is to fill in its entry: " _ r.NextAction)
    Do $$$AssertNotTrue(r.NextAction [ "downstream system team", "not to contact the downstream system team")
    Set n = $CLASSMETHOD(br, "ForReceiver", "RECEIVER_UNREADABLE", "UT Named Out")
    Do $$$AssertEquals(n.NextAction, plain.NextAction, "another receiver keeps the catalogue's next action")
    Do $$$AssertEquals(##class(Shutter.Store.BlockReason).ByCode("RECEIVER_UNREADABLE").NextAction, plain.NextAction, "the stored row is unchanged")
    Set c = ##class(Shutter.Store.Case).ByCaseId(..#CASEID)
    Set detail = ##class(Shutter.Operation.Gate).Unreadable(c, "The receiver's state could not be read")
    Do $$$AssertTrue(detail [ "declared with no API", "the gate's detail for the draft: " _ detail)
    Do $$$AssertTrue(detail [ "a person fills in its details", "says a person fills in its details")
    Set c.Receiver = "UT Named Out"
    Do $$$AssertEquals(##class(Shutter.Operation.Gate).Unreadable(c, "The receiver's state could not be read"), "The receiver's state could not be read", "and for another receiver the words given")
}

}
