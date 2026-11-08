/// The outage routes' words and acts, the Doctor's outage lines and the install's item (Shutter.API.Outages, Shutter.Setup,
/// docs/CONTRACTS.md section 17). The words are a table: each row builds an outage's JSON and says what its words must and must
/// not hold. Every receiver here is made up.
Class Shutter.Test.OutageApi Extends %UnitTest.TestCase
{

/// The rows this test made, removed after each test.
Property Made As %String(MAXLEN = "");

Method OnAfterOneTest() As %Status
{
    Set ptr = 0
    While $LISTNEXT(..Made, ptr, id) {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.OutageEvent WHERE OutageId = ?", id)
        Do ##class(Shutter.Store.Outage).%DeleteId(id)
    }
    Set ..Made = ""
    Quit $$$OK
}

/// An outage's JSON as the store gives it, with a reading; fields given in over replace the defaults.
ClassMethod Fixture(over As %DynamicObject = "", reading As %DynamicObject = "") As %DynamicObject
{
    Set o = {"id": "1", "receiver": "Unit Lab Out", "state": "open", "kind": "down", "openedAt": "2026-11-08T02:41:00Z", "drainedAt": null, "runbook": "Restart the made-up listener", "call": "Made-up duty desk, 01632 960999", "approvers": ["the lab's on-call"], "pausedUntil": null, "overdueAt": null, "settled": {"completed": 0, "suspended": 0, "error": 0, "other": 0}, "alerts": [], "lists": {"queued": [], "offered": [], "reached": [], "refused": []}, "openCases": [], "version": 1, "set": {"status": "not_computed", "reason": "no set gate in this build"}, "approvable": false, "approval": null, "sentByShutter": 0}
    Set r = {"receiver": "Unit Lab Out", "reading": "down", "retry": "none", "failureTimeout": 0, "queue": 0, "headHeaderId": null, "replyCodeActions": ":?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W,:T?=C", "replyCodeActionsStock": true, "settingSources": {"FailureTimeout": "item"}}
    If $ISOBJECT(reading) {
        Set it = reading.%GetIterator()
        While it.%GetNext(.k, .v) { Do r.%Set(k, v, $CASE(reading.%GetTypeOf(k), "null": "null", "boolean": "boolean", "number": "number", : "")) }
    }
    Set o.readings = r
    If $ISOBJECT(over) {
        Set it = over.%GetIterator()
        While it.%GetNext(.k, .v) { Do o.%Set(k, v, $CASE(over.%GetTypeOf(k), "null": "null", "boolean": "boolean", "number": "number", : "")) }
    }
    Quit o
}

XData Rows [ MimeType = application/json ]
{
[
 {"name": "a no-retry receiver, nothing approvable, no set gate", "category": "orders_results",
  "has": {"first": ["Shutter will not send these messages. Review them in the Message Viewer using the site's recovery procedure.", "The engine does not retry here (FailureTimeout 0, read off the item)", "were not offered; a person reads the trace", "Recovery attempts initiated by Shutter: 0.", "The listener has been unreachable since 02:41"], "do": ["Do: Restart the made-up listener"], "call": ["Call: Made-up duty desk, 01632 960999", "Who may approve here: the lab's on-call", "An operator can do nothing here, which is safe."], "critical": ["Shutter does not assess clinical urgency. If delayed reporting may require clinical action, contact the laboratory using the site's critical-results and downtime procedure. Do not re-enter or amend a result solely from this page."]},
  "not": {"first": ["for one approval", "may still be delivering"], "do": ["duplicate is"]}},
 {"name": "the same with a set gate in the build: no line about what was not offered", "category": "orders_results", "build": {"setGate": true, "send": false},
  "has": {"first": ["Shutter will not send these messages."]}, "not": {"first": ["not offered", "for one approval"]}},
 {"name": "approvable: the one approval, never the refusal", "category": "orders_results", "over": {"approvable": true}, "build": {"setGate": true, "send": true},
  "has": {"first": ["Shutter lists them for one approval"]}, "not": {"first": ["Shutter will not send these messages"]}},
 {"name": "failed messages counted when the row knows them", "category": "orders_results", "over": {"settled": {"completed": 0, "suspended": 0, "error": 3, "other": 0}},
  "has": {"first": ["3 messages have failed and will not go by themselves.", "3 messages failed and were not offered"]}},
 {"name": "bounded retries: not called no retry", "category": "orders_results", "reading": {"retry": "bounded", "failureTimeout": 25},
  "has": {"first": ["The engine retries here for at most 25 s, then gives up"], "do": ["duplicate is unknown."]}, "not": {"first": ["does not retry"]}},
 {"name": "the setting unreadable: no promise", "category": "orders_results", "reading": {"retry": "unknown", "failureTimeout": null, "settingSources": {"FailureTimeout": "unknown"}},
  "has": {"first": ["Whether this operation retries could not be read: treat them as not going by themselves until a person checks the item."]}, "not": {"first": ["retries without limit", "does not retry"]}},
 {"name": "a retrying receiver, no duplicates declared: Q8's line says unknown", "category": "orders_results", "reading": {"retry": "unlimited", "failureTimeout": -1, "queue": 5, "headHeaderId": "41"},
  "has": {"first": ["At this operation the engine retries without limit (FailureTimeout -1, read off the item)", "5 messages are queued.", "The integration engine may still be delivering or retrying."], "do": ["Entering one by hand first is your downtime procedure's call; at this receiver a duplicate is unknown."]},
  "not": {"first": ["Shutter will not send", "not offered"]}},
 {"name": "a retrying receiver that refuses duplicates, with its words", "category": "orders_results", "reading": {"retry": "unlimited", "failureTimeout": -1, "settingSources": {"FailureTimeout": "class_default"}}, "duplicates": {"behaviour": "refuses", "phrase": "ALREADY HELD"},
  "has": {"first": ["FailureTimeout -1, the stock operation's default"], "do": ["a duplicate is refused, with its words \"ALREADY HELD\"."]}},
 {"name": "a retrying receiver that files duplicates twice", "category": "orders_results", "reading": {"retry": "unlimited", "failureTimeout": -1}, "duplicates": {"behaviour": "files_twice"},
  "has": {"do": ["a duplicate is filed twice."]}},
 {"name": "refusing: a person decides, nothing suspended", "category": "orders_results", "over": {"kind": "refusing"}, "reading": {"retry": "unlimited", "failureTimeout": -1, "queue": 4, "headHeaderId": "1041"},
  "has": {"first": ["The receiver is up, and nothing is getting through: it refused message header 1041", "Shutter resends nothing."], "do": ["Do: a person decides in the Message Viewer; Shutter does not suspend or discard."]}},
 {"name": "not answering: may already be held", "category": "orders_results", "over": {"kind": "not_answering"}, "reading": {"retry": "unlimited", "failureTimeout": -1, "headHeaderId": "1041"},
  "has": {"first": ["The listener accepts connections and is not answering. Message header 1041 has been written to it at least once and may already be held there."]}},
 {"name": "can't tell at a no-retry receiver", "category": "orders_results", "over": {"kind": "cant_tell"},
  "has": {"first": ["Whether the listener is back cannot be read from the engine at this receiver: it will show on the next send.", "Shutter will not send these messages."]}, "not": {"first": ["Shutter checks each again"]}},
 {"name": "paused: the Do line swapped", "category": "orders_results", "over": {"state": "paused", "pausedUntil": "2026-11-08T06:00:00Z", "set": {"status": "withheld", "reason": "down on purpose"}},
  "has": {"do": ["Down on purpose until 2026-11-08T06:00:00Z"]}, "not": {"do": ["Do: Restart"]}},
 {"name": "drained: recovered, drained, settled, not checked", "category": "orders_results", "over": {"state": "closing", "drainedAt": "2026-11-08T03:13:20Z", "settled": {"completed": 36, "suspended": 1, "error": 0, "other": 0}}, "reading": {"retry": "unlimited", "failureTimeout": -1, "reading": "healthy"}, "recovered": "2026-11-08T03:12:01Z",
  "has": {"first": ["The engine's connection recovered at 03:12. Delivery backlog drained at 03:13. Application processing has not been independently checked.", "Nothing remains queued. 36 deliveries Completed; 1 was Suspended and still needs action."]}, "not": {"first": ["may still be delivering"]}},
 {"name": "no-retry closing: no claim about the listener", "category": "orders_results", "over": {"state": "closing", "drainedAt": "2026-11-08T03:13:20Z"}, "recovered": "2026-11-08T03:12:01Z",
  "has": {"first": ["Delivery backlog drained at 03:13."]}, "not": {"first": ["connection recovered"]}},
 {"name": "closed with open work: never green", "category": "orders_results", "over": {"state": "closed", "openCases": [{"caseId": "C-1", "reason": "r", "owner": "o"}, {"caseId": "C-2", "reason": "r", "owner": "o"}]},
  "has": {"first": ["Transport outage closed. 2 delivery exceptions still need review."]}},
 {"name": "reply actions that are the site's own", "category": "orders_results", "reading": {"replyCodeActions": ":?E=C", "replyCodeActionsStock": false},
  "has": {"first": ["This operation's reply actions are the site's own: what an AE, AR or timeout does here follows this string: :?E=C."]}},
 {"name": "the stock reply actions say nothing", "category": "orders_results",
  "not": {"first": ["the site's own"]}},
 {"name": "open over an hour: the site's limit", "category": "orders_results", "over": {"openedAt": "2026-11-08T01:00:00Z"},
  "has": {"do": ["Down longer than the site's limit"]}},
 {"name": "an ADT receiver: no laboratory line", "category": "current_state", "critical": null,
  "has": {"call": ["Call: Made-up duty desk"]}}
]
}

/// Every row of the words table.
Method TestWordsTable()
{
    Set rows = [].%FromJSON(##class(%Dictionary.CompiledXData).%OpenId(..%ClassName(1) _ "||Rows").Data)
    Set n = 0
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set n = n + 1
        Set o = ..Fixture(row.%Get("over"), row.%Get("reading"))
        Set entry = {"name": "Unit Lab Out", "category": (row.category), "runbook": "Restart the made-up listener", "call": "Made-up duty desk, 01632 960999"}
        If $ISOBJECT(row.%Get("duplicates")) Set entry.duplicates = row.duplicates
        Set build = $SELECT($ISOBJECT(row.%Get("build")): row.build, 1: {"setGate": false, "send": false})
        Set words = ##class(Shutter.API.Outages).Words(o, entry, build, "2026-11-08T03:20:00Z", row.%Get("recovered"))
        For key = "first", "do", "call" { Do $$$AssertTrue(words.%GetTypeOf(key) = "string", row.name _ ": " _ key _ " is a string") }
        If row.%IsDefined("critical") Do $$$AssertEquals(words.%GetTypeOf("critical"), "null", row.name _ ": no critical line")
        For part = "has", "not" {
            Set want = row.%Get(part)
            Continue:'$ISOBJECT(want)
            Set ki = want.%GetIterator()
            While ki.%GetNext(.key, .list) {
                Set text = words.%Get(key)
                Set li = list.%GetIterator()
                While li.%GetNext(.j, .phrase) {
                    If part = "has" {
                        Do $$$AssertTrue(text [ phrase, row.name _ ": " _ key _ " holds '" _ phrase _ "' (it reads: " _ text _ ")")
                    } Else {
                        Do $$$AssertTrue('(text [ phrase), row.name _ ": " _ key _ " never holds '" _ phrase _ "' (it reads: " _ text _ ")")
                    }
                }
            }
        }
    }
    Do $$$AssertEquals(n, 20, "the table has its rows")
}

/// No word on a card names a supplier, a value or "Verified".
Method TestWordsClaimNoVerification()
{
    For kind = "down", "refusing", "not_answering", "cant_tell" {
        For retry = "unlimited", "bounded", "none", "unknown" {
            Set o = ..Fixture({"kind": (kind)}, {"retry": (retry)})
            Set words = ##class(Shutter.API.Outages).Words(o, {"category": "orders_results"}, {"setGate": false, "send": false})
            Set all = words.first _ words.do _ words.call _ words.critical
            Do $$$AssertTrue('(all [ "erified"), kind _ "/" _ retry _ ": no verification is claimed")
            Do $$$AssertTrue('(all [ "for one approval"), kind _ "/" _ retry _ ": nothing approvable is offered")
        }
    }
}

/// A row made through the store, removed after the test.
Method NewOutage(Output row As Shutter.Store.Outage) As %Status
{
    Set entry = {"name": ("Unit Api Receiver " _ $JOB _ " " _ $ZHOROLOG), "category": "orders_results", "watch": {"namespace": "USER", "item": "Unit Api Out"}, "runbook": "Restart it", "call": "01632 960998", "approvers": ["unit approver"]}
    Set sc = ##class(Shutter.Store.Outage).Open(entry, "down", "the test", "the test", .row, .opened)
    If $ISOBJECT(row) && (row.%Id() '= "") Set ..Made = ..Made _ $LISTBUILD(row.%Id())
    Quit sc
}

/// The acts: what is refused, a pause that withholds the set and swaps the Do line, a close with a reason, nothing after it.
Method TestActs()
{
    Set api = "Shutter.API.Outages"
    Do $$$AssertStatusOK(..NewOutage(.row), "an outage opened")
    Quit:'$ISOBJECT(row)
    Set json = $CLASSMETHOD(api, "One", row)
    Do $$$AssertEquals(json.acts.%ToJSON(), "[""pause"",""close""]", "acts list pause and close")
    Do $$$AssertEquals(json.%GetTypeOf("approvable"), "boolean", "approvable is a boolean")
    Do $$$AssertTrue('json.approvable, "approvable is false")
    Do $$$AssertEquals(json.set.status, "not_computed", "set.status not_computed")
    Do $$$AssertEquals(json.set.reason, "no set gate in this build", "set.reason names the missing gate")
    For key = "id", "receiver", "namespace", "item", "state", "kind", "openedAt", "drainedAt", "closedAt", "runbook", "call", "approvers", "pausedUntil", "overdueAt", "readings", "window", "settled", "alerts", "lists", "openCases", "version", "set", "approvable", "approval", "sentByShutter", "acts", "words" {
        Do $$$AssertTrue(json.%IsDefined(key), "the outage has " _ key)
    }
    For key = "first", "do", "call", "critical" { Do $$$AssertTrue(json.words.%IsDefined(key), "words has " _ key) }
    Do $$$AssertTrue(json.words.call [ "01632 960998", "the call line as the site wrote it")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "read_again"}, "unit", .reply), "400 Bad Request", "an act the row doesn't list is refused")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "pause"}, "unit", .reply), "400 Bad Request", "a pause needs until")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "pause", "until": "2020-01-01T00:00:00Z"}, "unit", .reply), "400 Bad Request", "a pause in the past is refused")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "pause", "until": "tomorrow"}, "unit", .reply), "400 Bad Request", "a pause needs a UTC time")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "close", "version": 99}, "unit", .reply), "409 Conflict", "a stale version is refused")
    Set until = ##class(Shutter.Util.Time).PlusMillis(##class(Shutter.Util.Time).NowUTC(), 3600000)
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "pause", "until": (until)}, "unit", .reply), "200 OK", "a pause until a future time")
    Do $$$AssertEquals(reply.state, "paused", "the row reads paused")
    Do $$$AssertEquals(reply.set.status, "withheld", "the set is withheld")
    Do $$$AssertEquals(reply.set.reason, "down on purpose", "with the reason")
    Do $$$AssertTrue($EXTRACT(reply.words.do, 1, 26) = "Down on purpose until " _ $EXTRACT(until, 1, 4), "the Do line is swapped: " _ reply.words.do)
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "close"}, "unit", .reply), "400 Bad Request", "a close needs a reason")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "close", "reason": "   "}, "unit", .reply), "400 Bad Request", "a blank reason is no reason")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "close", "reason": "the listener is back"}, "unit", .reply), "200 OK", "a close with a reason")
    Do $$$AssertEquals(reply.state, "closed", "the row reads closed")
    Do $$$AssertEquals(reply.acts.%Size(), 0, "a closed row lists no acts")
    Set again = ##class(Shutter.Store.Outage).%OpenId(row.%Id())
    Do $$$AssertEquals(again.ClosedBy, "unit", "the person who closed it is the caller")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", again, {"act": "pause", "until": (until)}, "unit", .reply), "409 Conflict", "nothing moves a closed row")
}

/// The list route: an open row is listed under open and all, a closed one under all only, with the receivers' readings.
Method TestList()
{
    Do $$$AssertStatusOK(..NewOutage(.row), "an outage opened")
    Quit:'$ISOBJECT(row)
    Set id = row.%Id()
    Do $$$AssertTrue(..Listed(##class(Shutter.API.Outages).List("open"), id), "listed under open")
    Do $$$AssertStatusOK(row.Close("the test", "unit"), "closed")
    Set list = ##class(Shutter.API.Outages).List("open")
    Do $$$AssertTrue('..Listed(list, id), "not listed under open once closed")
    Do $$$AssertTrue(..Listed(##class(Shutter.API.Outages).List("all"), id), "still listed under all")
    Do $$$AssertTrue($ISOBJECT(list.receivers) && list.receivers.%IsA("%DynamicArray"), "receivers is a list")
    Do $$$AssertEquals(list.receivers.%Size(), ##class(Shutter.Store.SiteProfile).WatchedReceivers().%Size(), "one reading per watched receiver")
}

ClassMethod Listed(list As %DynamicObject, id As %String) As %Boolean
{
    Set iter = list.items.%GetIterator()
    While iter.%GetNext(.i, .o) { If o.id = id Return 1 }
    Quit 0
}

/// The forwarded prefixes, and nothing else, go to their classes.
Method TestForwardClass()
{
    Set d = "Shutter.API.Dispatch"
    Do $$$AssertEquals($CLASSMETHOD(d, "ForwardClass", "/summaries/x"), "Shutter.API.Summaries", "/summaries/x")
    Do $$$AssertEquals($CLASSMETHOD(d, "ForwardClass", "/summaries"), "Shutter.API.Summaries", "/summaries")
    Do $$$AssertEquals($CLASSMETHOD(d, "ForwardClass", "/assist/x"), "Shutter.API.Assist", "/assist/x")
    Do $$$AssertEquals($CLASSMETHOD(d, "ForwardClass", "/assistant"), "", "/assistant is not /assist")
    Do $$$AssertEquals($CLASSMETHOD(d, "ForwardClass", "/outages"), "", "/outages is a route of its own")
    Do $$$AssertEquals($CLASSMETHOD(d, "ForwardClass", "/cases/C-1"), "", "/cases is not forwarded")
}

/// The closure's sentence: an ADT receiver's byte for byte as before, and an orders and results receiver's claims nothing.
Method TestClosureLimit()
{
    Set d = "Shutter.API.Dispatch"
    Do $$$AssertEquals($CLASSMETHOD(d, "ClosureLimit", "Bed Mgmt", "current_state"), "Consumers beyond the downstream system are outside the production's view and are not verified", "ADT: unchanged")
    Do $$$AssertEquals($CLASSMETHOD(d, "ClosureLimit", "PAS", "history_of_record"), "Consumers beyond the downstream system are outside the production's view and are not verified", "history of record: unchanged")
    Set lab = $CLASSMETHOD(d, "ClosureLimit", "LIMS Out", "orders_results")
    Do $$$AssertTrue(lab [ "Shutter can't read this receiver", "orders and results: " _ lab)
    Do $$$AssertTrue('(lab [ "downstream system"), "orders and results: no downstream system")
}

/// Receiver Watch is one of the items a site's production gets, and Shutter's production defines it.
Method TestInstallItems()
{
    Set items = ##class(Shutter.Setup).#INSTALLITEMS
    Do $$$AssertTrue($LISTFIND($LISTFROMSTRING(items), "Receiver Watch"), "INSTALLITEMS names Receiver Watch")
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId("Shutter.Production||ProductionDefinition")
    Do $$$AssertTrue($ISOBJECT(xdata), "Shutter.Production's definition reads")
    Quit:'$ISOBJECT(xdata)
    Set text = xdata.Data.Read(1000000)
    Do $$$AssertTrue(text [ "Name=""Receiver Watch""", "Shutter.Production defines the item it copies")
}

/// The reset list names the three outage stores.
Method TestResetList()
{
    Set m = ##class(%Dictionary.MethodDefinition).%OpenId("Shutter.Setup||PurgeStore")
    Do $$$AssertTrue($ISOBJECT(m), "PurgeStore reads")
    Quit:'$ISOBJECT(m)
    Do m.Implementation.Rewind()
    Set code = m.Implementation.Read(1000000)
    For cls = "Shutter.Store.OutageEvent", "Shutter.Store.Outage", "Shutter.Store.ReceiverReading" {
        Do $$$AssertTrue(code [ ("""" _ cls _ """"), "the reset empties " _ cls)
    }
}

/// The Doctor's outage lines on this build: the set gate's version and the hold's line blank when their classes are absent,
/// one line per watched receiver, and the policy version beside the set's.
Method TestDoctorLines()
{
    Set d = {}.%FromJSON(##class(Shutter.Setup).Doctor())
    Do $$$AssertTrue($ISOBJECT(d.%Get("outages")), "the Doctor has an outages section")
    Quit:'$ISOBJECT(d.%Get("outages"))
    Set o = d.outages
    Do $$$AssertTrue('o.%IsDefined("error"), "it read without an error: " _ o.%Get("error"))
    Do $$$AssertEquals(o."policy_version", $PARAMETER("Shutter.Operation.Gate", "POLICYVERSION"), "the gate's policy version")
    If ##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Util.ResendSet") {
        Do $$$AssertEquals(o."set_policy_version", $PARAMETER("Shutter.Util.ResendSet", "SETPOLICYVERSION"), "the set gate's version")
    } Else {
        Do $$$AssertEquals(o."set_policy_version", "", "no set gate: blank")
    }
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Store.HoldEntry") Do $$$AssertEquals(o.hold, "", "no hold: blank")
    Do $$$AssertEquals(o.receivers.%Size(), ##class(Shutter.Store.SiteProfile).WatchedReceivers().%Size(), "one line per watched receiver")
    For key = "open", "by_state", "approvers_missing", "routers_validating", "alert_on_error_off", "declared_not_in_build" { Do $$$AssertTrue(o.%IsDefined(key), "the section has " _ key) }
}

/// A block a profile declares that this build has nothing behind says so.
Method TestDeclaredNotInBuild()
{
    Set list = [{"name": "A", "engine_resend": true, "hold": {"minutes": 5}}, {"name": "B", "engine_resend": false, "mail": {"to": ["x@example.org"], "on": ["open"]}}, {"name": "C"}]
    Set out = ##class(Shutter.Setup).DeclaredNotInBuild(list)
    Set seen = ""
    Set iter = out.%GetIterator()
    While iter.%GetNext(.i, .line) {
        Set seen = seen _ $LISTBUILD(line.receiver _ "|" _ line.block)
        Set class = $CASE(line.block, "engine_resend": "Shutter.Operation.EngineResend", "hold": "Shutter.Store.HoldEntry", : "Shutter.Operation.OutageMail")
        Set want = $SELECT(##class(%Dictionary.CompiledClass).%ExistsId(class): "declared; in this build", 1: "declared; not in this build")
        Do $$$AssertEquals(line.state, want, line.receiver _ " " _ line.block)
    }
    Do $$$AssertEquals($LISTTOSTRING(seen), "A|engine_resend,A|hold,B|mail", "engine_resend false and an entry with none say nothing")
}

}
