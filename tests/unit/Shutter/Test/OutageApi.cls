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
 {"name": "a retrying receiver, no duplicates declared: the duplicate line says unknown", "category": "orders_results", "reading": {"retry": "unlimited", "failureTimeout": -1, "queue": 5, "headHeaderId": "41"},
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
  "has": {"call": ["Call: Made-up duty desk"]}},
 {"name": "an offered set of results: the older line and the merge limit", "category": "orders_results", "duplicates": {"behaviour": "refuses", "phrase": "ALREADY HELD"}, "over": {"state": "offered", "kind": "cant_tell", "lists": {"queued": [], "offered": [{"headerId": "41", "controlId": "N1", "reason": "older than a result of another order for the same patient that already reached the receiver (control id C5); each files under its own order"}, {"headerId": "42", "controlId": "N2", "reason": ""}], "reached": [], "refused": [], "closed": []}},
  "has": {"first": ["1 of these is older than results of other orders for the same patients that already reached the receiver; each files under its own order.", "The patient check reads merges and identity changes only where they pass through this namespace; one made elsewhere is not seen."]},
  "not": {"do": ["Already handled by hand"]}},
 {"name": "an offered set where duplicates are unknown: check the receiver first", "category": "orders_results", "over": {"state": "offered", "kind": "cant_tell", "lists": {"queued": [], "offered": [{"headerId": "41", "controlId": "N1", "reason": ""}], "reached": [], "refused": [], "closed": []}},
  "has": {"do": ["At this receiver a duplicate is unknown: before approving, check the receiver for each message. For one already entered by hand, choose Already handled by hand; Shutter then sends nothing for it."]},
  "not": {"first": ["of these is older"]}},
 {"name": "closed after the send: the set's lines are gone", "category": "orders_results", "duplicates": {"behaviour": "refuses", "phrase": "ALREADY HELD"}, "over": {"state": "closed", "lists": {"queued": [], "offered": [{"headerId": "41", "controlId": "N1", "reason": "older than a result of another order for the same patient that already reached the receiver (control id C5); each files under its own order"}], "reached": [], "refused": [], "closed": []}},
  "not": {"first": ["of these is older", "The patient check reads merges"]}},
 {"name": "an offered set where duplicates are filed twice", "category": "orders_results", "duplicates": {"behaviour": "files_twice"}, "over": {"state": "offered", "kind": "cant_tell", "lists": {"queued": [], "offered": [{"headerId": "41", "controlId": "N1", "reason": ""}], "reached": [], "refused": [], "closed": []}},
  "has": {"do": ["At this receiver a duplicate is filed twice: before approving, check the receiver for each message."]}},
 {"name": "closed after a clean run: what Shutter did, not the engine's first Errors", "category": "orders_results", "over": {"state": "closed", "drainedAt": "2026-11-08T03:13:20Z", "settled": {"completed": 0, "suspended": 0, "error": 5, "other": 0}, "sentByShutter": 3, "resends": [{"runId": "R1-6", "headerId": "41", "state": "completed"}, {"runId": "R1-6", "headerId": "42", "state": "completed"}, {"runId": "R1-6", "headerId": "43", "state": "completed"}, {"runId": "H1", "headerId": "44", "state": "handled_by_hand"}, {"runId": "H1", "headerId": "45", "state": "handled_by_hand"}]},
  "has": {"first": ["Nothing remains queued. 0 deliveries Completed; Shutter sent 3 again, each new header Completed; 2 handled by hand.", "Recovery attempts initiated by Shutter: 3."]}, "not": {"first": ["ended in Error", "still need"]}},
 {"name": "a run that failed: each message by what happened to it, once", "category": "orders_results", "over": {"state": "needs_person", "drainedAt": "2026-11-08T03:13:20Z", "approval": {"id": "R8-3", "by": "appr1"}, "set": {"status": "not_computed", "reason": "the resend of header 43 ended Suspended"}, "settled": {"completed": 0, "suspended": 0, "error": 5, "other": 0}, "resends": [{"runId": "R8-3", "headerId": "41", "state": "completed"}, {"runId": "R8-3", "headerId": "42", "state": "completed"}, {"runId": "R8-3", "headerId": "43", "state": "failed"}, {"runId": "R8-3", "headerId": "44", "state": "stopped"}, {"runId": "R8-3", "headerId": "45", "state": "stopped"}]},
  "has": {"first": ["Shutter sent 2 again, each new header Completed; 1 failed when Shutter sent it again and still needs action; 2 not sent and still need action.", "A person must act here: the resend of header 43 ended Suspended."], "do": ["The run stopped: read the message that stopped it in the Message Viewer"]}, "not": {"first": ["ended in Error", "Shutter reads the engine again every minute"]}},
 {"name": "drained while the reading shows a queue: never nothing queued", "category": "orders_results", "over": {"state": "closing", "drainedAt": "2026-11-08T03:13:20Z"}, "reading": {"queue": 4},
  "has": {"first": ["4 messages are still queued."]}, "not": {"first": ["Nothing remains queued"]}},
 {"name": "a busy feed with no approval: when the reason was read, and that the poll reads again", "category": "orders_results", "over": {"state": "needs_person", "set": {"status": "not_computed", "reason": "the queue holds 4 messages: nothing is listed while anything is being tried", "computedAt": "2026-11-08T03:18:05Z"}},
  "has": {"first": ["Nothing is listed yet: the queue holds 4 messages: nothing is listed while anything is being tried (read at 03:18 UTC). Shutter reads the engine again every minute and lists the messages once nothing of the window is being tried; Read again does it now."]}, "not": {"first": ["A person must act here"], "do": ["The run stopped"]}}
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
    Do $$$AssertEquals(n, 28, "the table has its rows")
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

/// resends on the outage (v1.53): every ledger row of the outage in order, in the route's shape, with its closure.
Method TestResendsField()
{
    Do $$$AssertStatusOK(..NewOutage(.row), "an outage opened")
    Set id = row.%Id()
    Do $$$AssertEquals(##class(Shutter.API.Outages).One(row).resends.%ToJSON(), "[]", "none yet, and the field is there")
    For pos = 1:1:3 {
        Set r = ##class(Shutter.Store.ResendRecord).%New()
        Set r.RunId = "R" _ id _ "-1", r.Position = pos, r.OutageId = id, r.Namespace = "USER", r.Item = "Unit Api Out", r.OriginHeaderId = 70 + pos, r.ControlId = "CT" _ pos
        Set r.State = $CASE(pos, 1: "completed", 2: "failed", : "stopped"), r.ApprovedBy = "appr1", r.StartedAt = "2026-11-09T03:20:00Z", r.EndedAt = $SELECT(pos < 3: "2026-11-09T03:20:05Z", 1: ""), r.NewHeaderId = $SELECT(pos < 3: 90 + pos, 1: "")
        Do $$$AssertStatusOK(r.%Save(), "row " _ pos)
    }
    Set h = ##class(Shutter.Store.ResendRecord).%New()
    Set h.RunId = "H" _ id, h.OutageId = id, h.Namespace = "USER", h.Item = "Unit Api Out", h.OriginHeaderId = 79, h.ControlId = "CT9", h.State = "handled_by_hand", h.RecordedBy = "appr2", h.EndedAt = "2026-11-09T03:30:00Z", h.Words = "Handled by hand"
    Do $$$AssertStatusOK(h.%Save(), "a hand closure")
    Set resends = ##class(Shutter.API.Outages).One(row).resends
    Do $$$AssertEquals(resends.%Size(), 4, "four rows")
    Set closures = ""
    For i = 0:1:3 { Set closures = closures _ resends.%Get(i).controlId _ ":" _ resends.%Get(i).%Get("closure") _ "," }
    Do $$$AssertEquals(closures, "CT1:sent,CT2:failed,CT3:,CT9:handled_by_hand,", "in order, each closure, null while stopped")
    Do $$$AssertEquals(resends.%Get(2).%GetTypeOf("closure"), "null", "null, not empty")
    Do $$$AssertEquals(resends.%Get(0).by _ "/" _ resends.%Get(3).by, "appr1/appr2", "by: the approver, or who recorded the hand closure")
    Do $$$AssertEquals(resends.%Get(0).at _ "/" _ resends.%Get(2).at, "2026-11-09T03:20:05Z/2026-11-09T03:20:00Z", "at: the row's end, or its start")
    For key = "runId", "position", "headerId", "controlId", "newHeaderId", "state", "closure", "words", "by", "at", "caseId" { Do $$$AssertTrue(resends.%Get(0).%IsDefined(key), "a resend has " _ key) }
    &sql(DELETE FROM Shutter_Store.ResendRecord WHERE OutageId = :id)
}

/// Already handled by hand (v1.53): offered only where duplicates are unknown, filed twice or not declared; the refusals;
/// the ledger row with who and when; the Row moved to closed and the digest; the message's own case closed by hand.
Method TestHandledByHandAct()
{
    Set api = "Shutter.API.Outages"
    For behaviour = "unknown", "files_twice", "", "refuses" {
        Set o = {"state": "offered", "acts": ["pause", "read_again", "close"], "lists": {"queued": [], "offered": [{"headerId": "71"}], "reached": [{"headerId": "72"}], "refused": [], "closed": []}}
        Set entry = $SELECT(behaviour = "": {}, 1: {"duplicates": {"behaviour": (behaviour)}})
        Do $CLASSMETHOD(api, "ComposeActs", o, entry)
        Set want = (behaviour '= "refuses")
        Do $$$AssertEquals(o.lists.offered.%Get(0).acts.%ToJSON(), $SELECT(want: "[""handled_by_hand""]", 1: "[]"), "an offered row at " _ $SELECT(behaviour = "": "none declared", 1: behaviour))
        Do $$$AssertEquals(o.lists.reached.%Get(0).acts.%ToJSON(), "[]", "a reached row never")
        Do $$$AssertEquals(o.acts.%ToJSON() [ "handled_by_hand", want, "the outage's acts at " _ behaviour)
    }
    Do $$$AssertStatusOK(..NewOutage(.row), "an outage opened")
    Set id = row.%Id()
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "OA-T-" _ id, c.OperationKey = "LAB^NHS^999000^^result^2026-11-09T08:00:00Z", c.Receiver = row.Receiver, c.FailureKind = "delivery_failed", c.State = "escalated", c.OpenedAt = "2026-11-09T08:00:00Z", c.SourceNamespace = "USER", c.OriginHeaderId = 71
    Do $$$AssertStatusOK(c.%Save(), "the message's case")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "handled_by_hand", "headerId": "71", "note": "entered by hand"}, "appr2", .reply), "409 Conflict", "not offered yet: wrong_state")
    Do $$$AssertEquals(reply.error, "wrong_state", "wrong_state")
    Set offered = [{"headerId": "71", "controlId": "CT1", "reason": ""}, {"headerId": "72", "controlId": "CT2", "reason": ""}]
    Do row.Advance("offered", "listed", "unit", {"SetStatus": "computed", "SetDigest": (##class(Shutter.Util.ResendSet).Digest(offered)), "ListOffered": (offered)})
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "handled_by_hand", "headerId": "73", "note": "entered by hand"}, "appr2", .reply), "400 Bad Request", "a header not offered")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "handled_by_hand", "headerId": "71", "note": " "}, "appr2", .reply), "400 Bad Request", "no note")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "handled_by_hand", "headerId": "71", "note": ($TRANSLATE($JUSTIFY("", 1001), " ", "x"))}, "appr2", .reply), "400 Bad Request", "a note over 1,000 characters")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "handled_by_hand", "headerId": "71", "note": "entered by hand", "version": 99}, "appr2", .reply), "409 Conflict", "a stale version")
    Do $$$AssertEquals(reply.error, "version_changed", "version_changed")
    Set version = row.Version
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "handled_by_hand", "headerId": "71", "note": "entered in the lab system by the duty desk", "version": (version)}, "appr2", .reply), "200 OK", "the choice")
    Do $$$AssertEquals(reply.version, version + 1, "the version moves on")
    Do $$$AssertEquals(reply.lists.offered.%Size() _ "/" _ reply.lists.offered.%Get(0).headerId, "1/72", "the Row left offered")
    Do $$$AssertEquals(reply.lists.closed.%Size(), 1, "and is in closed")
    Set closed = reply.lists.closed.%Get(0)
    Do $$$AssertEquals(closed.closure _ "/" _ closed.closedBy, "handled_by_hand/appr2", "with its closure and who")
    Do $$$AssertTrue(closed.closedAt '= "", "and when")
    Do $$$AssertEquals(reply.set.digest, ##class(Shutter.Util.ResendSet).Digest([{"headerId": "72"}]), "the digest over what stays offered")
    Do $$$AssertTrue(##class(Shutter.Store.Outage).%OpenId(id, 0).ReadAgainAt '= "", "marked to read again")
    Set resends = reply.resends
    Do $$$AssertEquals(resends.%Size(), 1, "one ledger row")
    Do $$$AssertEquals(resends.%Get(0).state _ "/" _ resends.%Get(0).closure _ "/" _ resends.%Get(0).by _ "/" _ resends.%Get(0).controlId _ "/" _ resends.%Get(0).runId, "handled_by_hand/handled_by_hand/appr2/CT1/H" _ id, resends.%ToJSON())
    Do $$$AssertTrue(resends.%Get(0).words [ "Handled by hand, recorded by appr2 at " && (resends.%Get(0).words [ ": entered in the lab system by the duty desk. Shutter sent nothing for it."), resends.%Get(0).words)
    Set kinds = "", iter = ##class(Shutter.Store.OutageEvent).Of(id).%GetIterator()
    While iter.%GetNext(, .e) { Set:e.kind="handled_by_hand" kinds = kinds _ e.detail }
    Do $$$AssertTrue((kinds [ "control id CT1") && (kinds [ "appr2"), "an event names the person and the control id: " _ kinds)
    // The case closes by hand through the Case Workflow, a production job: give it a moment.
    For i = 1:1:40 { Do c.%Reload() Quit:c.State="resolved"  Hang 0.25 }
    Do $$$AssertEquals(c.State _ "/" _ c.Disposition, "resolved/handled_by_hand", "the message's case closed by hand")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "handled_by_hand", "headerId": "71", "note": "again"}, "appr2", .reply), "400 Bad Request", "no longer offered")
    &sql(DELETE FROM Shutter_Store.ResendRecord WHERE OutageId = :id)
    Do ##class(Shutter.Store.Case).%DeleteId(c.%Id())
}

/// Ask first (v1.53): where duplicates are not refused the approval needs receiverChecked, else 409
/// receiver_check_needed; where they are refused it does not.
Method TestApproveNeedsReceiverCheck()
{
    Set api = "Shutter.API.Outages"
    Do $$$AssertStatusOK(..NewOutage(.row), "an outage opened")
    Set offered = [{"headerId": "71", "controlId": "CT1"}]
    Do row.Advance("offered", "listed", "unit", {"SetStatus": "computed", "SetDigest": "d1", "Approvable": 1, "ListOffered": (offered)})
    Do $$$AssertEquals($CLASSMETHOD(api, "Approve", row, {"digest": "d1", "note": "checked"}, "appr1", .reply), "409 Conflict", "no receiver check")
    Do $$$AssertEquals(reply.error, "receiver_check_needed", "receiver_check_needed")
    Do $$$AssertEquals(reply.detail, "At this receiver a duplicate is unknown: check the receiver for these messages first, and say so with the approval.", "its words")
    Do $$$AssertEquals($CLASSMETHOD(api, "Approve", row, {"digest": "d1", "note": "checked", "receiverChecked": "yes"}, "appr1", .reply), "409 Conflict", "only true says it")
    Do $$$AssertEquals($CLASSMETHOD(api, "Approve", row, {"digest": "d1", "note": "checked at the receiver", "receiverChecked": true}, "appr1", .reply), "200 OK", "with the receiver checked")
    Set id = row.%Id()
    &sql(SELECT ControlId INTO :ctl FROM Shutter_Store.ResendRecord WHERE OutageId = :id AND Position = 1)
    Do $$$AssertEquals(ctl, "CT1", "the run's row keeps the control id")
    &sql(DELETE FROM Shutter_Store.ResendRecord WHERE OutageId = :id)
}

/// The acts: what is refused, a pause that withholds the set and swaps the Do line, a close with a reason, nothing after it.
Method TestActs()
{
    Set api = "Shutter.API.Outages"
    Do $$$AssertStatusOK(..NewOutage(.row), "an outage opened")
    Quit:'$ISOBJECT(row)
    Set json = $CLASSMETHOD(api, "One", row)
    // The set gate is in the build (Shutter.Util.ResendSet): read_again is listed beside pause and close.
    Do $$$AssertEquals(json.acts.%ToJSON(), "[""pause"",""read_again"",""close""]", "acts list pause, read_again and close")
    Do $$$AssertEquals(json.%GetTypeOf("approvable"), "boolean", "approvable is a boolean")
    Do $$$AssertTrue('json.approvable, "approvable is false")
    Do $$$AssertEquals(json.set.status, "not_computed", "set.status not_computed")
    Do $$$AssertEquals(json.set.reason, "", "set.reason empty: the set is computed when the outage closes")
    For key = "id", "receiver", "namespace", "item", "state", "kind", "openedAt", "drainedAt", "closedAt", "runbook", "call", "approvers", "pausedUntil", "overdueAt", "readings", "window", "settled", "alerts", "lists", "openCases", "version", "set", "approvable", "approval", "sentByShutter", "acts", "words" {
        Do $$$AssertTrue(json.%IsDefined(key), "the outage has " _ key)
    }
    For key = "first", "do", "call", "critical" { Do $$$AssertTrue(json.words.%IsDefined(key), "words has " _ key) }
    Do $$$AssertTrue(json.words.call [ "01632 960998", "the call line as the site wrote it")
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "send"}, "unit", .reply), "400 Bad Request", "an act the row doesn't list is refused")
    Set before = row.State _ "/" _ row.Version
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "send", "reason": "a later act"}, "unit", .reply, ["pause", "close", "send"]), "400 Bad Request", "an act the row lists but this build doesn't handle is refused")
    Do $$$AssertTrue($ISOBJECT(reply) && (reply.error = "bad_request"), "with bad_request")
    Set still = ##class(Shutter.Store.Outage).%OpenId(row.%Id(), 0)
    Do $$$AssertEquals(still.State _ "/" _ still.Version, before, "and the state is as it was")
    // read_again marks the row for the next poll, with an event naming who asked; the REST process computes nothing.
    Do $$$AssertEquals($CLASSMETHOD(api, "Act", row, {"act": "read_again"}, "unit", .reply), "200 OK", "read_again")
    Set marked = ##class(Shutter.Store.Outage).%OpenId(row.%Id(), 0)
    Do $$$AssertTrue(marked.ReadAgainAt '= "", "the row marked for the next poll")
    Do $$$AssertEquals(marked.State, row.State, "and its state unchanged")
    Set kinds = "", events = ##class(Shutter.Store.OutageEvent).Of(row.%Id()), iter = events.%GetIterator()
    While iter.%GetNext(.i, .e) { Set kinds = kinds _ "," _ e.kind }
    Do $$$AssertTrue(kinds [ ",read_again", "an event: " _ kinds)
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

/// The card's open cases are read again on every read (they were written at the close): a case resolved since leaves the
/// list, so does one whose message the ledger holds, and what stays carries its reason in plain words as it reads now. A
/// case that can't be read stays as written. sentByShutter counts every message Shutter sent again, whatever came of it.
Method TestOpenCasesNow()
{
    Do $$$AssertStatusOK(..NewOutage(.row), "an outage opened")
    Set id = row.%Id(), ids = ""
    For i = 1:1:3 {
        Set c = ##class(Shutter.Store.Case).%New()
        Set c.CaseId = "OA-OC-" _ id _ "-" _ i, c.OperationKey = "LAB^NHS^99900" _ i _ "^^result^2026-11-09T08:00:00Z", c.Receiver = row.Receiver
        Set c.FailureKind = "unmappable", c.State = $CASE(i, 1: "resolved", : "escalated"), c.OpenedAt = "2026-11-09T08:00:00Z", c.SourceNamespace = "USER", c.OriginHeaderId = 80 + i
        Do $$$AssertStatusOK(c.%Save(), "case " _ i)
        Set ids = ids _ $LISTBUILD(c.%Id())
    }
    Set stored = [{"caseId": ("OA-OC-" _ id _ "-1"), "reason": "its failure is unmappable, not a failed delivery: a Completed header does not settle it", "owner": "unit approver"}, {"caseId": ("OA-OC-" _ id _ "-2"), "reason": "old words", "owner": "unit approver"}, {"caseId": ("OA-OC-" _ id _ "-3"), "reason": "old words", "owner": "unit approver"}, {"caseId": "OA-OC-NONE", "reason": "as written", "owner": "unit approver"}]
    Do $$$AssertStatusOK(row.Advance("closed", "closed by the test", "unit", {"OpenCases": (stored)}), "closed with four open cases written")
    // The message of case 2 was sent again by Shutter: the ledger holds it.
    Set r = ##class(Shutter.Store.ResendRecord).%New()
    Set r.RunId = "R" _ id _ "-1", r.Position = 1, r.OutageId = id, r.Namespace = "USER", r.Item = "Unit Api Out", r.OriginHeaderId = 82, r.State = "completed", r.StartedAt = "2026-11-09T09:00:00Z", r.EndedAt = "2026-11-09T09:00:02Z"
    Do $$$AssertStatusOK(r.%Save(), "a ledger row")
    Set f = ##class(Shutter.Store.ResendRecord).%New()
    Set f.RunId = "R" _ id _ "-1", f.Position = 2, f.OutageId = id, f.Namespace = "USER", f.Item = "Unit Api Out", f.OriginHeaderId = 90, f.State = "failed", f.StartedAt = "2026-11-09T09:00:03Z"
    Do $$$AssertStatusOK(f.%Save(), "a failed row")
    Set j = ##class(Shutter.API.Outages).One(##class(Shutter.Store.Outage).%OpenId(id))
    Set listed = ""
    For k = 0:1:j.openCases.%Size() - 1 { Set listed = listed _ j.openCases.%Get(k).caseId _ "," }
    Do $$$AssertEquals(listed, "OA-OC-" _ id _ "-3,OA-OC-NONE,", "the resolved case and the one the ledger holds leave the list")
    Do $$$AssertEquals(j.openCases.%Get(0).reason, "Shutter has no resend of its own for this one message: a person decides on its case", "in plain words, as it reads now")
    Do $$$AssertEquals(j.openCases.%Get(0).owner, "unit approver", "with its owner")
    Do $$$AssertEquals(j.openCases.%Get(1).reason, "as written", "a case that can't be read stays as written")
    Do $$$AssertTrue(j.words.first [ "2 delivery exceptions still need review.", "the words count what stays: " _ j.words.first)
    Do $$$AssertEquals(j.sentByShutter, 2, "two messages sent again, one of them failed")
    &sql(DELETE FROM Shutter_Store.ResendRecord WHERE OutageId = :id)
    Set ptr = 0
    While $LISTNEXT(ids, ptr, cid) { Do ##class(Shutter.Store.Case).%DeleteId(cid) }
}

/// A row that is sending lists no act: a pause or a close would not stop the send, so the route refuses them.
Method TestNoActsWhileSending()
{
    Do $$$AssertStatusOK(..NewOutage(.row), "an outage opened")
    Do $$$AssertStatusOK(row.Advance("sending", "approved by the test", "unit"), "sending")
    Set j = ##class(Shutter.API.Outages).One(row)
    Do $$$AssertEquals(j.acts.%ToJSON(), "[]", "no acts while sending")
    Do $$$AssertEquals(##class(Shutter.API.Outages).Act(row, {"act": "close", "reason": "mid-run"}, "unit", .reply), "400 Bad Request", "a close is refused")
    Do $$$AssertEquals(##class(Shutter.Store.Outage).%OpenId(row.%Id(), 0).State, "sending", "and the row still sends")
}

/// The ledger by message: the last row on each header decides it, and attempts counts every message sent again.
Method TestTally()
{
    Set o = {"resends": [{"headerId": "41", "state": "failed"}, {"headerId": "41", "state": "completed"}, {"headerId": "42", "state": "closed_as_present"}, {"headerId": "43", "state": "unknown"}, {"headerId": "44", "state": "stopped"}, {"headerId": "45", "state": "handled_by_hand"}, {"headerId": "46", "state": "approved"}], "lists": {"closed": [{"headerId": "45", "closure": "handled_by_hand"}, {"headerId": "47", "closure": "already_delivered"}]}}
    Set t = ##class(Shutter.API.Outages).Tally(o)
    Do $$$AssertEquals(t.%ToJSON(), "{""sent"":1,""held"":2,""byHand"":1,""failed"":1,""notSent"":1,""attempts"":3,""counted"":6}", t.%ToJSON())
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

/// The reset list names the three outage stores and the ledger (v1.53: the purge resets the case counters, so a ledger row
/// left behind would name a new case of the same id, which the patient check would then leave out).
Method TestResetList()
{
    Set m = ##class(%Dictionary.MethodDefinition).%OpenId("Shutter.Setup||PurgeStore")
    Do $$$AssertTrue($ISOBJECT(m), "PurgeStore reads")
    Quit:'$ISOBJECT(m)
    Do m.Implementation.Rewind()
    Set code = m.Implementation.Read(1000000)
    For cls = "Shutter.Store.OutageEvent", "Shutter.Store.Outage", "Shutter.Store.ReceiverReading", "Shutter.Store.ResendRecord" {
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
