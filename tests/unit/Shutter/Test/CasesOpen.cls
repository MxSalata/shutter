/// GET /cases with open=1 and with resolved=0 (Shutter.API.Dispatch.CasesWhere and Cases; docs/CONTRACTS.md, section
/// 5): open=1 leaves out the closed cases and resolved=0 the resolved ones only, each in the query itself, so the total
/// and every page count the same rows. Each test has one case in every state of the case's State list, saved under a
/// scenario id of its own, so it counts its own cases whatever else the namespace holds, and removes them afterwards.
Class Shutter.Test.CasesOpen Extends %UnitTest.TestCase
{

/// The scenario id this test's cases carry.
Property Tag As %String;

/// The row ids of this test's cases, in the order of the State list.
Property Cases As %List;

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set ..Tag = "UT-OPEN-" _ $RANDOM(1000000), ..Cases = ""
    Set states = ..States(), sc = $$$OK
    For i = 1:1:$LISTLENGTH(states) {
        Set c = ##class(Shutter.Store.Case).%New()
        Set c.CaseId = ..Tag _ "-" _ i, c.OperationKey = "PAS^HOSP^MRN-UT-OPEN^ENC-UT-OPEN-" _ i _ "^transfer^2026-11-13T09:00:00Z"
        Set c.Event = "transfer", c.EncounterId = "ENC-UT-OPEN-" _ i, c.PatientId = "MRN-UT-OPEN", c.FailureKind = "delivery_failed"
        Set c.Scenario = ..Tag, c.State = $LIST(states, i)
        Set sc = c.%Save()
        Quit:$$$ISERR(sc)
        Set ..Cases = ..Cases _ $LISTBUILD(c.%Id())
    }
    Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Set ptr = 0
    While $LISTNEXT(..Cases, ptr, id) { Do ##class(Shutter.Store.Case).%DeleteId(id) }
    Set ..Cases = ""
    Quit $$$OK
}

/// Every state a case can be in, from the State property's own value list (it starts with its delimiter).
ClassMethod States() As %List
{
    Set prop = ##class(%Dictionary.CompiledProperty).%OpenId("Shutter.Store.Case||State")
    Quit $LISTFROMSTRING($EXTRACT(prop.Parameters.GetAt("VALUELIST"), 2, *), ",")
}

/// The states of this test's cases a filter keeps, comma-separated in the order saved; total is what the same filter
/// counts, as the route counts it.
Method Kept(state As %String, open As %String, Output total As %Integer, resolved As %String = "") As %String
{
    Set where = ##class(Shutter.API.Dispatch).CasesWhere(state, ..Tag, open, resolved, .args)
    Set total = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM Shutter_Store.""Case"" WHERE 1=1" _ where, args...)
    If rs.%Next() Set total = rs.%Get("N")
    Set kept = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State FROM Shutter_Store.""Case"" WHERE 1=1" _ where _ " ORDER BY ID", args...)
    While rs.%Next() { Set kept = kept _ $SELECT(kept = "": "", 1: ",") _ rs.%Get("State") }
    Quit kept
}

/// Calls GET /cases as Shutter.API.Dispatch serves it, as this process's user, with the query's names and values, and
/// what the route writes caught in a file. Returns the HTTP status; body is the reply, parsed.
ClassMethod Ask(query As %DynamicObject, Output body As %DynamicObject) As %String
{
    New %request, %response
    Set %request = ##class(%CSP.Request).%New()
    Set %request.CgiEnvs("REQUEST_METHOD") = "GET"
    Set iter = query.%GetIterator()
    While iter.%GetNext(.name, .value) { Set %request.Data(name, 1) = value }
    Set %response = ##class(%CSP.Response).%New()
    Set file = ##class(%File).TempFilename("json"), io = $IO
    Open file:("NWS"):5
    Try {
        Use file
        Do ##class(Shutter.API.Dispatch).Cases()
    } Catch ex {
        Use io
        Set %response.Status = "500 " _ ex.DisplayString()
    }
    Use io
    Close file
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(file)
    Set text = stream.Read(1000000)
    Kill stream
    Do ##class(%File).Delete(file)
    Set body = ##class(Shutter.Util.Json).Parse(text, .sc)
    If '$ISOBJECT(body) Set body = {"text": (text)}
    Quit %response.Status
}

/// open=1 keeps exactly the cases Shutter.Store.Case.IsClosed calls open, whatever states the list has, and counts them.
Method TestOpenLeavesOutEveryClosedState()
{
    Set kept = "," _ ..Kept("", "1", .total) _ ","
    Set states = ..States(), expected = 0
    For i = 1:1:$LISTLENGTH(states) {
        Set state = $LIST(states, i)
        Set c = ##class(Shutter.Store.Case).%OpenId($LIST(..Cases, i))
        Set closed = c.IsClosed(), listed = kept [ ("," _ state _ ",")
        If 'closed Set expected = expected + 1
        Set wanted = $SELECT(closed: 0, 1: 1)
        Do $$$AssertEquals(listed, wanted, "a case that is " _ state _ " is " _ $SELECT(closed: "left out", 1: "kept"))
    }
    Do $$$AssertEquals(total, expected, "the total counts the cases kept, and no other: " _ expected)
    For state = "resolved", "blocked", "escalated", "failed" {
        Set listed = kept [ ("," _ state _ ",")
        Do $$$AssertNotTrue(listed, "a " _ state _ " case is closed")
    }
    Do $$$AssertEquals(total, $LISTLENGTH(states) - 4, "and those four are the only closed states")
}

/// Without open, or with any value but 1, nothing is filtered: the list is what it was before the parameter.
Method TestAnyOtherValueFiltersNothing()
{
    Set all = $LISTLENGTH(..States())
    For open = "", "0", "true", "yes" {
        Do $$$AssertEquals(##class(Shutter.API.Dispatch).CasesWhere("", ..Tag, open, "", .args), " AND Scenario = ?", "open '" _ open _ "' adds nothing to the filter")
        Set kept = ..Kept("", open, .total), listed = $LENGTH(kept, ",")
        Do $$$AssertEquals(total, all, "open '" _ open _ "' counts every case")
        Do $$$AssertEquals(listed, all, "and lists every one")
    }
}

/// open is one more condition beside the state: an open state with it is itself, and a closed one matches nothing.
Method TestOpenWithAState()
{
    Do $$$AssertEquals(..Kept("awaiting_approval", "1", .total), "awaiting_approval", "an open state passes")
    Do $$$AssertEquals(total, 1, "and is counted once")
    Do $$$AssertEquals(..Kept("resolved", "1", .total), "", "a closed state with open=1 lists no case")
    Do $$$AssertEquals(total, 0, "and counts none")
    Do $$$AssertEquals(..Kept("resolved", "", .total), "resolved", "without open the closed state is listed as before")
    Do $$$AssertEquals(total, 1, "and counted")
}

/// Through the route: the total is the open cases' on every page, the pages together hold each open case once, newest
/// first, and a page past the end is empty with the same total. Without open the route counts and lists every case.
Method TestTheRouteCountsAndPagesTheSameRows()
{
    If '$SYSTEM.Security.Check("Shutter_Operate", "USE") {
        Do $$$AssertSkipped("the session's user does not hold Shutter_Operate")
        Quit
    }
    Set tag = ..Tag, all = $LISTLENGTH(..States()), open = all - 4
    Set seen = "", last = "", closedStates = $LISTBUILD("resolved", "blocked", "escalated", "failed")
    For offset = 0:4:12 {
        Set status = ..Ask({"scenario": (tag), "open": "1", "limit": 4, "offset": (offset)}, .body)
        Do $$$AssertEquals(status, "200 OK", "GET /cases?open=1 at offset " _ offset _ ": " _ body.%ToJSON())
        Continue:status'="200 OK"
        Do $$$AssertEquals(body.total, open, "the total is the open cases' at offset " _ offset)
        Set left = open - offset, wanted = $SELECT(left > 4: 4, left > 0: left, 1: 0)
        Do $$$AssertEquals(body.items.%Size(), wanted, "the page at offset " _ offset _ " holds what is left of them")
        Set iter = body.items.%GetIterator()
        While iter.%GetNext(.n, .item) {
            Set closed = $LISTFIND(closedStates, item.state), again = $LISTFIND(seen, item.caseId)
            Do $$$AssertNotTrue(closed, item.caseId _ " is " _ item.state _ ", which is open")
            Do $$$AssertNotTrue(again, item.caseId _ " is on one page only")
            If last '= "" Do $$$AssertTrue(item.id < last, item.caseId _ " comes after a newer case")
            Set seen = seen _ $LISTBUILD(item.caseId), last = item.id
        }
    }
    Set pages = $LISTLENGTH(seen)
    Do $$$AssertEquals(pages, open, "the pages together hold every open case")
    Set status = ..Ask({"scenario": (tag), "limit": 500}, .body)
    Do $$$AssertEquals(status, "200 OK", "GET /cases without open: " _ body.%ToJSON())
    If status = "200 OK" {
        Do $$$AssertEquals(body.total, all, "without open the total is every case's")
        Do $$$AssertEquals(body.items.%Size(), all, "and every case is listed")
    }
}

/// resolved=0 leaves out the resolved cases and no other: a blocked, an escalated and a failed case still need a
/// person, so they stay, with every case still being worked on.
Method TestResolvedLeavesOutOnlyTheResolvedCases()
{
    Set kept = "," _ ..Kept("", "", .total, "0") _ ","
    Set states = ..States(), all = $LISTLENGTH(states)
    For i = 1:1:all {
        Set state = $LIST(states, i), listed = kept [ ("," _ state _ ","), wanted = $SELECT(state = "resolved": 0, 1: 1)
        Do $$$AssertEquals(listed, wanted, "a case that is " _ state _ " is " _ $SELECT(wanted: "kept", 1: "left out"))
    }
    Do $$$AssertEquals(total, all - 1, "the total counts every case but the resolved one: " _ (all - 1))
    For state = "blocked", "escalated", "failed" {
        Set listed = kept [ ("," _ state _ ",")
        Do $$$AssertTrue(listed, "a " _ state _ " case is closed and still listed")
    }
}

/// Without resolved, or with any value but 0, nothing is filtered: 1 does not list the resolved cases alone (state does).
Method TestAnyOtherValueOfResolvedFiltersNothing()
{
    Set all = $LISTLENGTH(..States())
    For resolved = "", "1", "false", "no", "00" {
        Do $$$AssertEquals(##class(Shutter.API.Dispatch).CasesWhere("", ..Tag, "", resolved, .args), " AND Scenario = ?", "resolved '" _ resolved _ "' adds nothing to the filter")
        Set kept = ..Kept("", "", .total, resolved), listed = $LENGTH(kept, ",")
        Do $$$AssertEquals(total, all, "resolved '" _ resolved _ "' counts every case")
        Do $$$AssertEquals(listed, all, "and lists every one")
    }
}

/// resolved is one more condition beside the state and open: any state but resolved with it is itself, resolved with it
/// matches nothing, and with open=1 the open cases are what is left, since open already leaves the resolved ones out.
Method TestResolvedWithAStateAndWithOpen()
{
    For state = "awaiting_approval", "blocked", "escalated", "failed" {
        Do $$$AssertEquals(..Kept(state, "", .total, "0"), state, state _ " passes beside resolved=0")
        Do $$$AssertEquals(total, 1, "and is counted once")
    }
    Do $$$AssertEquals(..Kept("resolved", "", .total, "0"), "", "state resolved with resolved=0 lists no case")
    Do $$$AssertEquals(total, 0, "and counts none")
    Do $$$AssertEquals(..Kept("resolved", "", .total), "resolved", "without it the resolved state is listed as before")
    Do $$$AssertEquals(total, 1, "and counted")
    Set open = ..Kept("", "1", .openTotal), both = ..Kept("", "1", .total, "0")
    Do $$$AssertEquals(both, open, "open=1 with resolved=0 lists the open cases")
    Do $$$AssertEquals(total, openTotal, "and counts them")
}

/// Through the route: with resolved=0 the total is every case's but the resolved one on every page, the pages together
/// hold each of those once, newest first, the closed ones that still need a person among them, and a page past the end
/// is empty with the same total.
Method TestTheRouteCountsAndPagesWithoutTheResolvedCases()
{
    If '$SYSTEM.Security.Check("Shutter_Operate", "USE") {
        Do $$$AssertSkipped("the session's user does not hold Shutter_Operate")
        Quit
    }
    Set tag = ..Tag, all = $LISTLENGTH(..States()), left = all - 1
    Set seen = "", states = "", last = "", pastEnd = left + (4 - (left # 4))
    For offset = 0:4:pastEnd {
        Set status = ..Ask({"scenario": (tag), "resolved": "0", "limit": 4, "offset": (offset)}, .body)
        Do $$$AssertEquals(status, "200 OK", "GET /cases?resolved=0 at offset " _ offset _ ": " _ body.%ToJSON())
        Continue:status'="200 OK"
        Do $$$AssertEquals(body.total, left, "the total leaves out the resolved case at offset " _ offset)
        Set rest = left - offset, wanted = $SELECT(rest > 4: 4, rest > 0: rest, 1: 0)
        Do $$$AssertEquals(body.items.%Size(), wanted, "the page at offset " _ offset _ " holds what is left of them")
        Set iter = body.items.%GetIterator()
        While iter.%GetNext(.n, .item) {
            Set again = $LISTFIND(seen, item.caseId)
            Do $$$AssertNotEquals(item.state, "resolved", item.caseId _ " is " _ item.state)
            Do $$$AssertNotTrue(again, item.caseId _ " is on one page only")
            If last '= "" Do $$$AssertTrue(item.id < last, item.caseId _ " comes after a newer case")
            Set seen = seen _ $LISTBUILD(item.caseId), states = states _ $LISTBUILD(item.state), last = item.id
        }
    }
    Set pages = $LISTLENGTH(seen)
    Do $$$AssertEquals(pages, left, "the pages together hold every case but the resolved one")
    For state = "blocked", "escalated", "failed" {
        Set found = ''$LISTFIND(states, state)
        Do $$$AssertTrue(found, "the " _ state _ " case is on a page")
    }
    Set status = ..Ask({"scenario": (tag), "resolved": "0", "state": "escalated", "limit": 4}, .body)
    Do $$$AssertEquals(status, "200 OK", "GET /cases?resolved=0&state=escalated: " _ body.%ToJSON())
    If status = "200 OK" {
        Do $$$AssertEquals(body.total, 1, "beside a state the total is that state's")
        Do $$$AssertEquals(body.items.%Size(), 1, "and its case is listed")
    }
    Set status = ..Ask({"scenario": (tag), "resolved": "0", "state": "resolved", "limit": 4}, .body)
    Do $$$AssertEquals(status, "200 OK", "GET /cases?resolved=0&state=resolved: " _ body.%ToJSON())
    If status = "200 OK" {
        Do $$$AssertEquals(body.total, 0, "beside the resolved state the total is none")
        Do $$$AssertEquals(body.items.%Size(), 0, "and no case is listed")
    }
}

}
