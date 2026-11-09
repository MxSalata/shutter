/// The Receiver Watch's judging, by table with no instance state, and the outage store's contract: every field of the routes'
/// JSON on a fresh row, one row per receiver, and a stale copy or a closed row changing nothing.
Class Shutter.Test.ReceiverWatch Extends %UnitTest.TestCase
{

Parameter RECEIVER = "Unit Watch Receiver";

Method OnBeforeOneTest() As %Status
{
    Do ..Clean()
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    Do ..Clean()
    Quit $$$OK
}

Method Clean()
{
    // The names are exact, so the upper-case twin that TestNamesAreExact makes is a row of its own.
    For name = ..#RECEIVER, $ZCONVERT(..#RECEIVER, "U") {
        &sql(DELETE FROM Shutter_Store.OutageEvent WHERE OutageId IN (SELECT ID FROM Shutter_Store.Outage WHERE Receiver = :name))
        &sql(DELETE FROM Shutter_Store.Outage WHERE Receiver = :name)
        &sql(DELETE FROM Shutter_Store.ReceiverReading WHERE Receiver = :name)
    }
}

Method Watch() As %String [ Private ]
{
    Quit "Shutter.Operation.ReceiverWatch"
}

Method TestAdapterWord()
{
    Set w = ..Watch()
    For row = "1 job connected:connected", "1 job disconnected:disconnected", "2 jobs connected:connected", "2 jobs connected, 1 job disconnected:mixed", "disabled:other", "unscheduled:other", "not connecting:other", "n/a:other", ":other", "1 job listening:other", "disconnected:other" {
        Do $$$AssertEquals($CLASSMETHOD(w, "AdapterWord", $PIECE(row, ":", 1)), $PIECE(row, ":", 2), "AdapterWord " _ row)
    }
}

Method TestRetryOf()
{
    Set w = ..Watch()
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryOf", "item", -1), "unlimited", "-1")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryOf", "class_default", -1), "unlimited", "-1 from the class")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryOf", "item", 0), "none", "0")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryOf", "item", 25), "bounded", "25")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryOf", "unknown", ""), "unknown", "a failed read")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryOf", "unknown", -1), "unknown", "a value with an unknown source")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryOf", "item", "x"), "unknown", "not a number")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryOf", "item", -2), "unknown", "no such behaviour")
}

Method TestHeadWords()
{
    Set w = ..Watch()
    Set ar = "ERROR <Ens>ErrGeneral: Retrying HL7 Message body 7@EnsLib.HL7.Message / 9 because response 8 MSA code 'AR' matched ReplyCodeActions"
    Set timeout = "ERROR <Ens>ErrTCPTerminatedReadTimeoutExpired: TCP Read timeout (30) expired waiting for terminator SegTerminator"
    Do $$$AssertEquals($CLASSMETHOD(w, "HeadWords", {"answer": "ok", "rows": [{"text": (ar)}]}), "refusing", "an AR retry")
    Do $$$AssertEquals($CLASSMETHOD(w, "HeadWords", {"answer": "ok", "rows": [{"text": (timeout)}]}), "not_answering", "a read timeout")
    Do $$$AssertEquals($CLASSMETHOD(w, "HeadWords", {"answer": "ok", "rows": [{"text": (timeout)}, {"text": (ar)}]}), "refusing", "the newest row decides")
    Do $$$AssertEquals($CLASSMETHOD(w, "HeadWords", {"answer": "ok", "rows": []}), "", "no rows")
    Do $$$AssertEquals($CLASSMETHOD(w, "HeadWords", {"answer": "unknown", "why": "x"}), "", "a failed read")
    Do $$$AssertEquals($CLASSMETHOD(w, "HeadWords", {"answer": "ok", "rows": [{"text": "ERROR <Ens>ErrOutConnectExpired: TCP Connect timeout period (5) expired for 127.0.0.1:7711"}]}), "", "a failed connect")
    Set far = "ERROR <Ens>ErrGeneral: Something else entirely, long enough to pass the start of the row by far, then the words Retrying HL7 Message MSA code 'AR'"
    Do $$$AssertEquals($CLASSMETHOD(w, "HeadWords", {"answer": "ok", "rows": [{"text": (far)}]}), "", "a receiver's own words later in a row")
}

/// One fact set per row: the base is a connected, quiet, retrying item.
Method Facts(changes As %DynamicObject) As %DynamicObject [ Private ]
{
    Set f = {"answer": "ok", "productionState": "running", "enabled": 1, "status": "OK", "adapterState": "1 job connected", "queue": 0, "head": "", "active": "", "lastHead": "", "headWords": "", "retry": "unlimited", "stayConnected": -1, "open": 0}
    Set iter = changes.%GetIterator()
    While iter.%GetNext(.k, .v) { Do f.%Set(k, v) }
    Quit f
}

Method TestReadingOf()
{
    Set rows = []
    Do rows.%Push(["healthy", {}, "connected, OK, quiet"])
    Do rows.%Push(["healthy", {"status": "Inactive"}, "Inactive on a quiet feed"])
    Do rows.%Push(["slow", {"queue": 3}, "connected, OK, queue above 0: no outage"])
    Do rows.%Push(["down", {"status": "Retry", "adapterState": "1 job disconnected", "queue": 5, "head": "41"}, "retrying, disconnected"])
    Do rows.%Push(["down", {"status": "Error", "adapterState": "1 job disconnected"}, "retrying item gone on a quiet feed"])
    Do rows.%Push(["cant_tell", {"adapterState": "1 job disconnected"}, "disconnected with Status OK fits nothing else"])
    Do rows.%Push(["refusing", {"status": "Retry", "head": "41", "lastHead": "41", "headWords": "refusing"}, "AR loop on one head"])
    Do rows.%Push(["refusing", {"status": "OK", "head": "41", "lastHead": "41", "headWords": "refusing"}, "whatever Status reads"])
    Do rows.%Push(["not_answering", {"status": "Error", "head": "41", "lastHead": "41", "headWords": "not_answering"}, "hung, one head"])
    Do rows.%Push(["cant_tell", {"status": "Retry", "head": "42", "lastHead": "41", "headWords": "refusing"}, "the head moved under Retry: not two polls of one, and not delivering"])
    Do rows.%Push(["cant_tell", {"status": "Error", "retry": "none", "head": "42", "lastHead": "41", "headWords": "refusing"}, "the head moved under Error at a no-retry item: not slow"])
    Do rows.%Push(["slow", {"status": "OK", "queue": 2, "head": "42", "lastHead": "41"}, "the head moved under OK with a queue: delivering"])
    Do rows.%Push(["cant_tell", {"status": "Retry", "head": "41", "lastHead": "41"}, "one head, connected, words it can't place"])
    Do rows.%Push(["cant_tell", {"status": "Retry", "queue": 2}, "the head unknown"])
    Do rows.%Push(["healthy", {"status": "Error", "retry": "none"}, "one AR at FailureTimeout 0, then silence"])
    Do rows.%Push(["healthy", {"retry": "none"}, "a quiet no-retry item, connected and OK"])
    Do rows.%Push(["healthy", {"retry": "bounded"}, "a quiet bounded item, connected and OK"])
    Do rows.%Push(["cant_tell", {"retry": "none", "open": 1}, "a quiet no-retry item with an outage open"])
    Do rows.%Push(["cant_tell", {"retry": "none", "status": "Error", "adapterState": "1 job disconnected"}, "a quiet no-retry item not connected"])
    Do rows.%Push(["cant_tell", {"retry": "unknown", "status": "Error", "adapterState": "1 job disconnected"}, "a setting unknown takes the no-retry path"])
    Do rows.%Push(["down", {"retry": "none", "status": "Error", "adapterState": "1 job disconnected", "queue": 3, "head": "41"}, "a no-retry item with messages going"])
    Do rows.%Push(["cant_tell", {"stayConnected": 0, "status": "Error", "adapterState": "1 job disconnected", "queue": 2, "head": "41"}, "StayConnected 0 reads disconnected up or down"])
    Do rows.%Push(["unknown", {"answer": "unknown"}, "a failed read"])
    Do rows.%Push(["unknown", {"productionState": "not running"}, "the source production stopped"])
    Do rows.%Push(["unknown", {"enabled": 0, "status": "Disabled", "adapterState": "disabled"}, "the item disabled"])
    Do rows.%Push(["cant_tell", {"adapterState": "2 jobs connected, 1 job disconnected", "status": "Error"}, "some jobs of each"])
    Set w = ..Watch()
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .row) {
        Do $$$AssertEquals($CLASSMETHOD(w, "ReadingOf", ..Facts(row.%Get(1))), row.%Get(0), row.%Get(2))
    }
}

/// A clock, not a count: a poll's time decides, and a gap with no poll starts it again.
Method TestTheClock()
{
    Set w = ..Watch()
    Set t0 = "2026-11-07T03:00:00Z"
    Do $$$AssertEquals($CLASSMETHOD(w, "DownSince", "down", "", "", t0), t0, "the first poll starts it")
    Do $$$AssertEquals($CLASSMETHOD(w, "DownSince", "down", t0, t0, "2026-11-07T03:00:05Z"), t0, "kept")
    Do $$$AssertEquals($CLASSMETHOD(w, "DownSince", "healthy", t0, t0, "2026-11-07T03:00:05Z"), "", "ended by any other reading")
    Do $$$AssertEquals($CLASSMETHOD(w, "DownSince", "down", t0, t0, "2026-11-07T03:05:00Z"), "2026-11-07T03:05:00Z", "a gap with no poll starts it again")
    Do $$$AssertEquals($CLASSMETHOD(w, "ShouldOpen", "down", t0, "2026-11-07T03:00:29Z", 0), "", "29 s: not yet")
    Do $$$AssertTrue($CLASSMETHOD(w, "ShouldOpen", "down", t0, "2026-11-07T03:00:30Z", 0) '= "", "30 s, however many polls")
    Do $$$AssertEquals($CLASSMETHOD(w, "ShouldOpen", "healthy", "", "2026-11-07T03:00:30Z", 0), "", "not on healthy")
    Do $$$AssertEquals($CLASSMETHOD(w, "ShouldOpen", "slow", "", "2026-11-07T03:00:30Z", 0), "", "never on a queue's depth")
    Do $$$AssertEquals($CLASSMETHOD(w, "ShouldOpen", "cant_tell", "", "2026-11-07T03:00:30Z", 0), "", "not on can't tell")
    Do $$$AssertEquals($CLASSMETHOD(w, "ShouldOpen", "unknown", "", "2026-11-07T03:00:30Z", 0), "", "not on a failed read")
    Do $$$AssertTrue($CLASSMETHOD(w, "ShouldOpen", "refusing", "", t0, 0) '= "", "at once on refusing")
    Do $$$AssertTrue($CLASSMETHOD(w, "ShouldOpen", "not_answering", "", t0, 0) '= "", "at once on not answering")
    Do $$$AssertTrue($CLASSMETHOD(w, "ShouldOpen", "cant_tell", "", t0, 1) '= "", "at once on a new never-opened header")
}

Method Entry() As %DynamicObject [ Private ]
{
    Quit {"name": (..#RECEIVER), "watch": {"namespace": "USER", "item": "Unit Out"}, "runbook": "start the listener", "call": "the on-call", "approvers": ["a person"]}
}

/// Every field the routes' JSON names, on a fresh row, with what the design says it holds before anything fills it.
Method TestFreshRowAnswersEveryField()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "down", "a test", "unit", .o, .opened), "opened")
    Do $$$AssertTrue(opened, "a new row")
    Set j = o.ToJSON()
    For key = "id", "receiver", "namespace", "item", "state", "kind", "openedAt", "drainedAt", "closedAt", "runbook", "call", "approvers", "pausedUntil", "overdueAt", "readings", "window", "settled", "alerts", "lists", "openCases", "version", "set", "approvable", "approval", "sentByShutter", "acts", "words" {
        Do $$$AssertTrue(j.%IsDefined(key), "the field " _ key)
    }
    Do $$$AssertEquals(j.state, "open", "state")
    Do $$$AssertEquals(j.kind, "down", "kind")
    Do $$$AssertEquals(j.runbook, "start the listener", "runbook")
    Do $$$AssertEquals(j.call, "the on-call", "call")
    Do $$$AssertEquals(j.approvers.%Get(0), "a person", "approvers")
    Do $$$AssertEquals(j.set.status, "not_computed", "set.status")
    For key = "digest", "computedAt", "setPolicyVersion", "status", "reason" {
        Do $$$AssertTrue(j.set.%IsDefined(key), "set." _ key)
    }
    For key = "digest", "computedAt", "setPolicyVersion" {
        Do $$$AssertEquals(j.set.%GetTypeOf(key), "null", "set." _ key _ " null")
    }
    For key = "queued", "offered", "reached", "refused" {
        Do $$$AssertEquals(j.lists.%Get(key).%Size(), 0, "lists." _ key _ " empty")
    }
    For key = "completed", "suspended", "error", "other" {
        Do $$$AssertEquals(j.settled.%Get(key), 0, "settled." _ key)
    }
    For key = "first", "do", "call", "critical" {
        Do $$$AssertEquals(j.words.%GetTypeOf(key), "null", "words." _ key _ " null")
    }
    For key = "drainedAt", "closedAt", "pausedUntil", "overdueAt", "approval" {
        Do $$$AssertEquals(j.%GetTypeOf(key), "null", key _ " null")
    }
    Do $$$AssertEquals(j.alerts.%Size(), 0, "alerts")
    Do $$$AssertEquals(j.openCases.%Size(), 0, "openCases")
    Do $$$AssertEquals(j.%GetTypeOf("approvable"), "boolean", "approvable a boolean")
    Do $$$AssertEquals(j.approvable, 0, "approvable false")
    Do $$$AssertEquals(j.sentByShutter, 0, "nothing sent")
    // The set gate is in the build: read_again is listed beside pause and close.
    Do $$$AssertEquals(j.acts.%ToJSON(), "[""pause"",""read_again"",""close""]", "acts")
    Do $$$AssertTrue(j.window.%IsDefined("from") && j.window.%IsDefined("to"), "window")
    Do $$$AssertEquals(j.window.%GetTypeOf("to"), "null", "window.to null")
    Do $$$AssertEquals(j.readings.reading, "unknown", "no reading yet reads unknown")
}

/// The profile sets no length on these lines, so a long one still opens the outage, and reads back whole.
Method TestLongLinesStillOpen()
{
    Set long = "", names = []
    For i = 1:1:2100 Set long = long _ "x"
    For i = 1:1:150 Do names.%Push("a person with quite a long name " _ i)
    Set entry = ..Entry(), entry.runbook = long, entry.call = long, entry.approvers = names
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(entry, "down", "a test", "unit", .o, .opened), "opened")
    Do $$$AssertTrue(opened, "a new row")
    Set j = ##class(Shutter.Store.Outage).%OpenId(o.%Id()).ToJSON()
    Do $$$AssertEquals($LENGTH(j.runbook), 2100, "the whole runbook")
    Do $$$AssertEquals($LENGTH(j.call), 2100, "the whole call line")
    Do $$$AssertEquals(j.approvers.%Size(), 150, "every approver")
    Do $$$AssertTrue($LENGTH(names.%ToJSON()) > 2000, "the approvers were over the old length")
    Set row = ##class(Shutter.Store.ReceiverReading).%New()
    Set row.Receiver = ..#RECEIVER, row.Reading = "healthy", row.ReplyCodeActions = long
    Do $$$AssertStatusOK(row.%Save(), "a long reply code string still saves the reading")
}

/// What a row remembers belongs to the item it was read from.
Method TestAnotherItemForgetsTheMark()
{
    Set w = "Shutter.Operation.ReceiverWatch"
    For block = "NS2:Unit Out:0", "NS1:Other Out:0", "NS1:Unit Out:1" {
        Set row = ##class(Shutter.Store.ReceiverReading).%New()
        Set row.Namespace = "NS1", row.Item = "Unit Out", row.ErrorHeaderMark = 39, row.DownSince = "2026-11-07T03:00:00Z", row.LastHead = 41
        Do $CLASSMETHOD(w, "ForgetOtherItem", row, $PIECE(block, ":", 1), $PIECE(block, ":", 2))
        Set kept = $PIECE(block, ":", 3)
        Do $$$AssertEquals(row.ErrorHeaderMark, $SELECT(kept: 39, 1: ""), "the mark, " _ block)
        Do $$$AssertEquals(row.DownSince, $SELECT(kept: "2026-11-07T03:00:00Z", 1: ""), "the clock, " _ block)
        Do $$$AssertEquals(row.LastHead, $SELECT(kept: 41, 1: ""), "the head, " _ block)
    }
    // Through a real poll, with the same namespace that can't be read: an unread block leaves the mark alone, another clears it.
    Set entry = {"name": (..#RECEIVER), "watch": {"namespace": "NOSUCHNS", "item": "Unit Out"}}
    Set row = ##class(Shutter.Store.ReceiverReading).%New()
    Set row.Receiver = ..#RECEIVER, row.Namespace = "NOSUCHNS", row.Item = "Unit Out", row.ErrorHeaderMark = 39
    Do $$$AssertStatusOK(row.%Save(), "a row at this block")
    Do $$$AssertStatusOK($CLASSMETHOD(w, "PollOne", entry), "polled")
    Do $$$AssertEquals(##class(Shutter.Store.ReceiverReading).Find(..#RECEIVER).ErrorHeaderMark, 39, "the same block keeps the mark")
    Do entry.watch.%Set("item", "Unit Out Two")
    Do $$$AssertStatusOK($CLASSMETHOD(w, "PollOne", entry), "polled")
    Set row = ##class(Shutter.Store.ReceiverReading).Find(..#RECEIVER)
    Do row.%Reload()
    Do $$$AssertEquals(row.ErrorHeaderMark, "", "another item clears it")
    Do $$$AssertEquals(row.Item, "Unit Out Two", "and the row names the new item")
}

Method TestOneRowPerReceiver()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "down", "a test", "unit", .a, .opened), "first")
    Do $$$AssertTrue(opened, "opened")
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "refusing", "a test", "unit", .b, .opened), "second")
    Do $$$AssertTrue('opened, "not opened again")
    Do $$$AssertEquals(a.%Id(), b.%Id(), "the same row")
    Set again = ##class(Shutter.Store.Outage).%New()
    Set again.Receiver = ..#RECEIVER, again.ActiveReceiver = ..#RECEIVER
    Do $$$AssertTrue($$$ISERR(again.%Save()), "the store itself refuses a second row")
}

/// A list written says so in its status, and reads back whole after a save and a fresh open.
Method TestPutListSaysItWrote()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "down", "a test", "unit", .o), "opened")
    Set sc = o.PutList("ListOffered", [{"headerId": "5", "controlId": "C1"}])
    Do $$$AssertStatusOK(sc, "the write says it worked")
    Do $$$AssertStatusOK(o.PutList("Alerts", [{"at": "t", "kind": "k", "text": "x"}]), "and again")
    Do $$$AssertStatusOK(o.%Save(), "saved")
    Set id = o.%Id()
    Kill o
    Set o = ##class(Shutter.Store.Outage).%OpenId(id, 0)
    Set j = o.ToJSON()
    Do $$$AssertEquals(j.lists.offered.%Size(), 1, "the list read back")
    Do $$$AssertEquals(j.lists.offered.%Get(0).controlId, "C1", "as written")
    Do $$$AssertEquals(j.alerts.%Get(0).kind, "k", "the alerts too")
    Do $$$AssertEquals(j.lists.queued.%Size(), 0, "a list not written stays empty")
    Do $$$AssertStatusOK(o.PutList("ListOffered", []), "replaced by an empty one")
    Do $$$AssertEquals(o.ToJSON().lists.offered.%Size(), 0, "and it reads empty")
}

/// Two receivers whose names differ only in case are two receivers, as the profile's check says: two outages, two readings.
Method TestNamesAreExact()
{
    Set twin = ..Entry(), twin.name = $ZCONVERT(..#RECEIVER, "U")
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "down", "a test", "unit", .a, .opened), "first")
    Do $$$AssertTrue(opened, "opened")
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(twin, "down", "a test", "unit", .b, .opened), "the twin")
    Do $$$AssertTrue(opened, "the twin opens its own row")
    Do $$$AssertNotEquals(a.%Id(), b.%Id(), "two rows")
    Do $$$AssertEquals(b.Receiver, twin.name, "named as written")
    For name = ..#RECEIVER, twin.name {
        Set row = ##class(Shutter.Store.ReceiverReading).%New()
        Set row.Receiver = name, row.Reading = "healthy", row.CheckedAt = "2026-11-07T03:00:00Z"
        Do $$$AssertStatusOK(row.%Save(), "a reading for " _ name)
    }
    Do $$$AssertEquals(##class(Shutter.Store.ReceiverReading).Find(twin.name).Receiver, twin.name, "Find gives the twin its own row")
    Do $$$AssertEquals(##class(Shutter.Store.ReceiverReading).Find(..#RECEIVER).Receiver, ..#RECEIVER, "and the first its own")
    Do $$$AssertTrue(##class(Shutter.Store.ReceiverReading).Find("unit watch receiver") = "", "a third casing finds nothing")
}

Method TestPauseAndClose()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "down", "a test", "unit", .o), "opened")
    Do $$$AssertTrue($$$ISERR(o.Pause("", "a person")), "a pause needs its end")
    Do $$$AssertTrue($$$ISERR(o.Close("", "a person")), "a close needs its reason")
    Do $$$AssertStatusOK(o.Pause("2026-11-08T06:00:00Z", "a person"), "paused")
    Do $$$AssertEquals(o.ToJSON().state, "paused", "state")
    Do $$$AssertEquals(o.ToJSON().pausedUntil, "2026-11-08T06:00:00Z", "until")
    Do $$$AssertEquals(o.ToJSON().set.status, "withheld", "the set withheld")
    Do $$$AssertEquals(o.ToJSON().set.reason, "down on purpose", "and why")
    Do $$$AssertEquals(o.ToJSON().version, 2, "the version moved")
    // One process shares one copy of a row, so a copy read before the pause is made by setting back its version.
    Set o.Version = 1
    Do $$$AssertTrue($$$ISERR(o.Close("too late", "a person")), "a stale copy changes nothing")
    Do $$$AssertEquals(o.State, "paused", "the copy reads the store again, still paused")
    Do $$$AssertEquals(o.Version, 2, "and its version")
    Do $$$AssertStatusOK(o.Close("the listener is back", "a person"), "closed")
    Do $$$AssertEquals(o.ToJSON().state, "closed", "state")
    Do $$$AssertEquals(o.ToJSON().acts.%Size(), 0, "no act on a closed row")
    Do $$$AssertTrue($ISOBJECT(##class(Shutter.Store.Outage).ActiveFor(..#RECEIVER)) = 0, "no longer active")
    Do $$$AssertTrue($$$ISERR(o.Close("again", "a person")), "a closed row never changes")
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "down", "a test", "unit", .next, .opened), "a new outage after the close")
    Do $$$AssertTrue(opened && (next.%Id() '= o.%Id()), "a new row")
    Do $$$AssertEquals(##class(Shutter.Store.OutageEvent).Of(o.%Id()).%Size(), 3, "opened, paused, closed")
}

/// The stored reading's own rules: a stale row reads unknown with its last stamp, and JSON nulls where nothing was read.
Method TestStoredReading()
{
    Set row = ##class(Shutter.Store.ReceiverReading).%New()
    Set row.Receiver = ..#RECEIVER, row.Reading = "healthy", row.Retry = "unlimited", row.CheckedAt = "2026-11-07T03:00:00Z", row.ReplyCodeActions = ":?A=C", row.ReplyCodeActionsStock = 0
    Set row.SettingSources = "{""FailureTimeout"":""item""}", row.UnknownFields = "[""GetReply""]"
    Do $$$AssertStatusOK(row.%Save(), "saved")
    Set j = row.ToJSON("2026-11-07T03:00:30Z")
    Do $$$AssertEquals(j.reading, "healthy", "fresh")
    Do $$$AssertEquals(j.replyCodeActions, ":?A=C", "the string")
    Do $$$AssertEquals(j.replyCodeActionsStock, 0, "marked as changed")
    Do $$$AssertEquals(j.settingSources.FailureTimeout, "item", "its source")
    Do $$$AssertEquals(j.unknownFields.%Get(0), "GetReply", "what was not read")
    Do $$$AssertEquals(j.%GetTypeOf("queue"), "null", "a value not read is null")
    Set j = row.ToJSON("2026-11-07T03:01:01Z")
    Do $$$AssertEquals(j.reading, "unknown", "over 60 s reads unknown")
    Do $$$AssertEquals(j.checkedAt, "2026-11-07T03:00:00Z", "with its last stamp")
    Do $$$AssertEquals(##class(Shutter.Store.ReceiverReading).Last("No Such Receiver").reading, "unknown", "no row reads unknown")
}

/// A profile with no watch block: nothing stored and nothing opened, where the same poll of a profile with one stores a reading.
Method TestNoWatchBlockDoesNothing()
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Set savedJson = $SELECT($ISOBJECT(row): row.Json, 1: p.%ToJSON()), savedSource = $SELECT($ISOBJECT(row): row.Source, 1: "unit")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "unit", "test", "", .v), "a profile with no watch block")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).WatchedReceivers().%Size(), 0, "nothing to watch")
    &sql(SELECT COUNT(*) INTO :readings FROM Shutter_Store.ReceiverReading)
    &sql(SELECT COUNT(*) INTO :outages FROM Shutter_Store.Outage)
    Do ##class(Shutter.Operation.ReceiverWatch).PollAll(##class(Shutter.Store.SiteProfile).WatchedReceivers())
    &sql(SELECT COUNT(*) INTO :after FROM Shutter_Store.ReceiverReading)
    Do $$$AssertEquals(after, readings, "no reading stored")
    &sql(SELECT COUNT(*) INTO :after FROM Shutter_Store.Outage)
    Do $$$AssertEquals(after, outages, "no outage opened")
    Do p.receivers.%Push({"name": (..#RECEIVER), "system": "Made-up LIMS", "category": "orders_results", "tier": 3, "watch": {"namespace": "NOSUCHNS", "item": "Unit Out"}})
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "unit", "test", "", .v), "the same profile with one")
    Do ##class(Shutter.Operation.ReceiverWatch).PollAll(##class(Shutter.Store.SiteProfile).WatchedReceivers())
    &sql(SELECT COUNT(*) INTO :after FROM Shutter_Store.ReceiverReading)
    Do $$$AssertEquals(after, readings + 1, "the poll does store a reading when there is one to watch")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(savedJson, savedSource, "test", "", .v), "the profile put back")
}

/// Where the mark goes: past what was read, short of what could not be, and short of the first never-opened header.
Method TestMarkAfter()
{
    Set w = ..Watch(), ids = $LISTBUILD(11, 12, 13)
    Do $$$AssertEquals($CLASSMETHOD(w, "MarkAfter", 10, ids, $LISTBUILD("reached_receiver", "unknown", "no_rows"), .h), 13, "all read: past them all")
    Do $$$AssertEquals(h, "", "and none new")
    Do $$$AssertEquals($CLASSMETHOD(w, "MarkAfter", 10, ids, $LISTBUILD("reached_receiver", "", "reached_receiver"), .h), 11, "stops short of a header not read")
    Do $$$AssertEquals(h, "", "with none new")
    Do $$$AssertEquals($CLASSMETHOD(w, "MarkAfter", 10, ids, $LISTBUILD("reached_receiver", "never_opened", "never_opened"), .h), 11, "stops short of the first never-opened")
    Do $$$AssertEquals(h, 12, "which is the one named")
    Do $$$AssertEquals($CLASSMETHOD(w, "MarkAfter", 10, ids, $LISTBUILD("", "reached_receiver", "never_opened"), .h), 10, "an unread header holds the mark")
    Do $$$AssertEquals(h, 13, "and those after it are still judged")
    Do $$$AssertEquals($CLASSMETHOD(w, "MarkAfter", 10, "", "", .h), 10, "nothing new: it stays")
}

Method TestHeadCheck()
{
    Set w = ..Watch()
    Do $$$AssertEquals($CLASSMETHOD(w, "HeadCheck", 41, 41), "", "they agree")
    Do $$$AssertEquals($CLASSMETHOD(w, "HeadCheck", 41, ""), "", "an empty active message is unknown, not a disagreement")
    Do $$$AssertEquals($CLASSMETHOD(w, "HeadCheck", "", 41), "", "no head to check")
    Do $$$AssertTrue($CLASSMETHOD(w, "HeadCheck", 41, 42) [ "42", "a disagreement is named")
}

/// Run in a job of its own, by TestAPollNeverUndoesAClose.
ClassMethod CloseFromAnotherJob(id As %String)
{
    Do ##class(Shutter.Store.Outage).%OpenId(id).Close("a person closes it", "a person")
}

/// A poll holding a copy read before a person's close, the close made by a second job: the close stands.
Method TestAPollNeverUndoesAClose()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "down", "a test", "unit", .o), "opened")
    Set id = o.%Id()
    Job ##class(Shutter.Test.ReceiverWatch).CloseFromAnotherJob(id)::10
    Do $$$AssertTrue($TEST, "the second job started")
    For i = 1:1:40 {
        &sql(SELECT State INTO :state FROM Shutter_Store.Outage WHERE ID = :id)
        If state = "closed" Quit
        Hang 0.25
    }
    Do $$$AssertEquals(state, "closed", "the second job closed it")
    Do $$$AssertEquals(o.State, "open", "this copy still reads open")
    Do $$$AssertStatusOK(o.SetKind("refusing", "unit"), "the poll gives up quietly")
    &sql(SELECT State, Version, Kind, ActiveReceiver INTO :state, :version, :kind, :active FROM Shutter_Store.Outage WHERE ID = :id)
    Do $$$AssertEquals(state, "closed", "still closed")
    Do $$$AssertEquals(version, 2, "the version the close gave it")
    Do $$$AssertEquals(kind, "down", "the kind left alone")
    Do $$$AssertEquals(active, "", "no longer active")
    Do $$$AssertEquals(o.State, "closed", "the copy now reads the store")
    Do $$$AssertEquals(##class(Shutter.Store.OutageEvent).Of(id).%Size(), 2, "opened and closed, no kind event")
}

/// A state moved under the copy: nothing changes. On a row that hasn't moved, only Kind does, and fields written elsewhere stay.
Method TestSetKindSetsOnlyKind()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "down", "a test", "unit", .o), "opened")
    Set id = o.%Id()
    &sql(UPDATE Shutter_Store.Outage SET SettledError = 7 WHERE ID = :id)
    Do $$$AssertStatusOK(o.SetKind("refusing", "unit"), "a change of kind")
    &sql(SELECT Kind, Version, SettledError INTO :kind, :version, :settled FROM Shutter_Store.Outage WHERE ID = :id)
    Do $$$AssertEquals(kind, "refusing", "the kind changed")
    Do $$$AssertEquals(version, 1, "no state moved")
    Do $$$AssertEquals(settled, 7, "what another writer saved stands")
    &sql(UPDATE Shutter_Store.Outage SET State = 'paused', Version = 2 WHERE ID = :id)
    Do $$$AssertStatusOK(o.SetKind("not_answering", "unit"), "a stale copy gives up quietly")
    &sql(SELECT State, Kind INTO :state, :kind FROM Shutter_Store.Outage WHERE ID = :id)
    Do $$$AssertEquals(state, "paused", "the pause stands")
    Do $$$AssertEquals(kind, "refusing", "the kind unchanged")
    Do $$$AssertEquals(o.Version, 2, "the copy reads the store")
}

/// A poll of a namespace that isn't there stores unknown, never healthy, and opens nothing.
Method TestFailedReadStoresUnknown()
{
    Set entry = {"name": (..#RECEIVER), "watch": {"namespace": "NOSUCHNS", "item": "Unit Out"}}
    Do $$$AssertStatusOK(##class(Shutter.Operation.ReceiverWatch).PollOne(entry), "polled")
    Set j = ##class(Shutter.Store.ReceiverReading).Last(..#RECEIVER)
    Do $$$AssertEquals(j.reading, "unknown", "unknown")
    Do $$$AssertEquals(j.retry, "unknown", "retry unknown")
    Do $$$AssertTrue(j.unknownFields.%Size() > 0, "says what was not read")
    Do $$$AssertEquals(j.settingSources.FailureTimeout, "unknown", "the setting's source")
    Do $$$AssertTrue('$ISOBJECT(##class(Shutter.Store.Outage).ActiveFor(..#RECEIVER)), "nothing opened")
    Do $$$AssertEquals(##class(Shutter.Store.ReceiverReading).Find(..#RECEIVER).ErrorHeaderMark, "", "a failed first read leaves the mark unset")
}

}
