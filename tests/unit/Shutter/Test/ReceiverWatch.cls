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
    Set name = ..#RECEIVER
    &sql(DELETE FROM Shutter_Store.OutageEvent WHERE OutageId IN (SELECT ID FROM Shutter_Store.Outage WHERE Receiver = :name))
    &sql(DELETE FROM Shutter_Store.Outage WHERE Receiver = :name)
    &sql(DELETE FROM Shutter_Store.ReceiverReading WHERE Receiver = :name)
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
    Do rows.%Push(["slow", {"status": "Retry", "head": "42", "lastHead": "41", "headWords": "refusing"}, "the head moved: not two polls of one"])
    Do rows.%Push(["cant_tell", {"status": "Retry", "head": "41", "lastHead": "41"}, "one head, connected, words it can't place"])
    Do rows.%Push(["cant_tell", {"status": "Retry", "queue": 2}, "the head unknown"])
    Do rows.%Push(["healthy", {"status": "Error", "retry": "none"}, "E-02: one AR at FailureTimeout 0, then silence"])
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
    Do $$$AssertEquals(j.acts.%ToJSON(), "[""pause"",""close""]", "acts")
    Do $$$AssertTrue(j.window.%IsDefined("from") && j.window.%IsDefined("to"), "window")
    Do $$$AssertEquals(j.window.%GetTypeOf("to"), "null", "window.to null")
    Do $$$AssertEquals(j.readings.reading, "unknown", "no reading yet reads unknown")
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

/// No watch block: nothing read, nothing stored, nothing opened, nothing logged.
Method TestNoWatchBlockDoesNothing()
{
    &sql(SELECT COUNT(*) INTO :readings FROM Shutter_Store.ReceiverReading)
    &sql(SELECT COUNT(*) INTO :outages FROM Shutter_Store.Outage)
    Do ##class(Shutter.Operation.ReceiverWatch).PollAll([])
    &sql(SELECT COUNT(*) INTO :after FROM Shutter_Store.ReceiverReading)
    Do $$$AssertEquals(after, readings, "no reading stored")
    &sql(SELECT COUNT(*) INTO :after FROM Shutter_Store.Outage)
    Do $$$AssertEquals(after, outages, "no outage opened")
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
}

}
