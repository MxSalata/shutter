/// The Receiver Watch: a read-only poll of the production items the site profile's receivers name in a watch block. Each poll
/// asks the engine what it shows about the item and stores the answer per receiver; it opens no connection, sends nothing and
/// writes nothing in the watched namespace. With no watch block it does nothing at all. It has its own item, so a failure in a
/// watched namespace can't stop the Case Releaser, and a failure here reaches no intake.
///
/// The judging is in pure class methods (AdapterWord, RetryOf, HeadWords, HeadCheck, ReadingOf, DownSince, ShouldOpen, MarkAfter), so a table can
/// test them with no instance. Here it only opens an outage: what moves an open one on is written elsewhere.
Class Shutter.Operation.ReceiverWatch Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Property Adapter As Ens.InboundAdapter;

/// Elapsed time every poll must read down before an outage opens.
Parameter OPENSECONDS = 30;

/// With no poll for this long, the readings before the gap say nothing about the time since.
Parameter GAPSECONDS = 30;

/// The header status the engine calls Error ($$$eMessageStatusError).
Parameter ERRORSTATUS = 8;

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    Set pOutput = ""
    Do ..PollAll(##class(Shutter.Store.SiteProfile).WatchedReceivers())
    Quit $$$OK
}

/// One poll of each entry. One receiver's failure never stops the next.
ClassMethod PollAll(entries As %DynamicArray)
{
    Set iter = entries.%GetIterator()
    While iter.%GetNext(.i, .entry) {
        Try {
            Set sc = ..PollOne(entry)
            If $$$ISERR(sc) $$$LOGWARNING("The watch of " _ entry.%Get("name") _ ": " _ $SYSTEM.Status.GetErrorText(sc))
        } Catch ex {
            $$$LOGWARNING("The watch of " _ entry.%Get("name") _ ": " _ ex.DisplayString())
        }
    }
}

/// Reads one receiver, stores the reading, and opens its outage when a rule says so.
ClassMethod PollOne(entry As %DynamicObject) As %Status
{
    Set receiver = entry.%Get("name"), watch = entry.%Get("watch")
    Set ns = watch.%Get("namespace"), item = watch.%Get("item")
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set row = ##class(Shutter.Store.ReceiverReading).Find(receiver)
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.ReceiverReading).%New(), row.Receiver = receiver
    Do ..ForgetOtherItem(row, ns, item)
    Set outage = ##class(Shutter.Store.Outage).ActiveFor(receiver)
    Set facts = ..Read(ns, item)
    Set facts.lastHead = row.LastHead, facts.open = $ISOBJECT(outage)
    Set reading = ..ReadingOf(facts)
    Do ..Fill(row, ns, item, facts, reading, now)
    Set row.DownSince = ..DownSince(reading, row.DownSince, row.CheckedAt, now)
    Set row.CheckedAt = now, row.LastHead = facts.head
    Set fresh = ..NewNeverOpened(ns, item, facts.retry, row, facts.open, .freshHeader)
    Set sc = row.%Save()
    If $$$ISERR(sc) Quit sc
    If $ISOBJECT(outage) {
        Quit $SELECT(..IsKind(reading): outage.SetKind(reading, "Receiver Watch"), 1: $$$OK)
    }
    Set why = ..ShouldOpen(reading, row.DownSince, now, fresh)
    If why = "" Quit $$$OK
    Set sc = ##class(Shutter.Store.Outage).Open(entry, $SELECT(..IsKind(reading): reading, 1: "cant_tell"), why, "Receiver Watch", .outage, .opened)
    If $$$ISERR(sc) || 'fresh Quit sc
    // Only now is that header spent: a refused open judges it again on the next poll.
    Set row.ErrorHeaderMark = freshHeader
    Quit row.%Save()
}

/// What the row remembers holds only for the item it was read from: when the watch block names another, the mark, the head and
/// the clock start again, so that item's old failures aren't new and another namespace's ids hide nothing.
ClassMethod ForgetOtherItem(row As Shutter.Store.ReceiverReading, ns As %String, item As %String)
{
    If (row.Namespace = ns) && (row.Item = item) Quit
    Set row.ErrorHeaderMark = "", row.DownSince = "", row.LastHead = ""
}

/// What the engine shows about the item, as one object: ItemState's fields, and the settings through the shared read with
/// IsStockTcp's answer. settings holds each setting's { "source", "value", "why" }.
ClassMethod Read(ns As %String, item As %String) As %DynamicObject
{
    Set state = ##class(Shutter.Util.EngineRead).ItemState(ns, item)
    Set facts = {"answer": (state.answer), "why": (state.why), "productionState": (state.productionState), "enabled": (state.enabled), "status": (state.status), "adapterState": (state.adapterState), "queue": (state.queue), "head": (state.headHeaderId), "active": (state.activeMessage), "headWords": ""}
    Set isStock = ##class(Shutter.Util.EngineScope).IsStockTcp(ns, item)
    Set facts.isStock = isStock
    Set settings = {}
    For setting = "FailureTimeout", "DefCharEncoding", "ReplyCodeActions", "GetReply", "StayConnected" {
        Do settings.%Set(setting, ##class(Shutter.Util.EngineRead).ItemSetting(ns, item, setting, isStock))
    }
    Set facts.settings = settings
    Set timeout = settings.%Get("FailureTimeout")
    Set facts.retry = ..RetryOf(timeout.source, timeout.value)
    Set stay = settings.%Get("StayConnected")
    Set facts.stayConnected = $SELECT(stay.source = "unknown": "", 1: stay.value)
    If facts.head '= "" Set facts.headWords = ..HeadWords(##class(Shutter.Util.EngineRead).LogRows(ns, facts.head))
    Quit facts
}

/// Copies what was read onto the stored row.
ClassMethod Fill(row As Shutter.Store.ReceiverReading, ns As %String, item As %String, facts As %DynamicObject, reading As %String, now As %String) [ Private ]
{
    Set check = ..HeadCheck(facts.head, facts.active)
    Set row.Namespace = ns, row.Item = item, row.Reading = reading, row.Why = $EXTRACT($SELECT(facts.why '= "": facts.why, 1: check), 1, 1000)
    Set row.Status = facts.status, row.AdapterState = facts.adapterState, row.Queue = facts.queue
    Set row.HeadHeaderId = facts.head, row.ActiveMessage = facts.active, row.Retry = facts.retry, row.StayConnected = facts.stayConnected
    Set settings = facts.settings
    Set sources = {}, unknown = []
    For setting = "FailureTimeout", "DefCharEncoding", "ReplyCodeActions", "GetReply", "StayConnected" {
        Set read = settings.%Get(setting)
        Do sources.%Set(setting, read.source)
        If read.source = "unknown" Do unknown.%Push(setting)
    }
    Set row.FailureTimeout = ..Known(settings, "FailureTimeout"), row.DefCharEncoding = ..Known(settings, "DefCharEncoding")
    Set row.ReplyCodeActions = ..Known(settings, "ReplyCodeActions"), row.GetReply = ..Known(settings, "GetReply")
    Set row.ReplyCodeActionsStock = $SELECT(row.ReplyCodeActions = "": "", 1: row.ReplyCodeActions = ##class(Shutter.Util.EngineRead).#STOCKREPLYCODEACTIONS)
    If facts.answer '= "ok" {
        For field = "status", "adapterState", "queue", "headHeaderId" Do unknown.%Push(field)
    }
    If (facts.answer = "ok") && (facts.active = "") && ((+facts.queue > 0) || (facts.head '= "")) Do unknown.%Push("activeMessage")
    If check '= "" Do unknown.%Push("activeMessage")
    Set row.SettingSources = sources.%ToJSON(), row.UnknownFields = unknown.%ToJSON()
}

/// A setting's value, empty when its read was unknown.
ClassMethod Known(settings As %DynamicObject, setting As %String) As %String [ Private ]
{
    Set read = settings.%Get(setting)
    Quit $SELECT(read.source = "unknown": "", 1: read.value)
}

/// Whether an Error header to the item new since this row's mark reads never_opened on every retained attempt, at an item that
/// finishes with messages by itself: header is the first such. A mark never set takes the highest Error header there is and
/// judges nothing, since a header from before the watch began is not new; a read that fails leaves it unset. With an outage
/// open or an item that retries for ever nothing can open from these, so the mark goes to the highest too.
ClassMethod NewNeverOpened(ns As %String, item As %String, retry As %String, row As Shutter.Store.ReceiverReading, open As %Boolean, Output header As %String) As %Boolean [ Private ]
{
    Set header = ""
    If (row.ErrorHeaderMark = "") || open || (retry = "unlimited") {
        If ..HighestErrorHeader(ns, item, +row.ErrorHeaderMark, .highest) Set row.ErrorHeaderMark = highest
        Quit 0
    }
    If '..ErrorHeaders(ns, item, +row.ErrorHeaderMark, .ids) Quit 0
    Set words = ""
    For i = 1:1:$LISTLENGTH(ids) {
        Set rows = ##class(Shutter.Util.EngineRead).LogRows(ns, $LIST(ids, i))
        Set words = words _ $LISTBUILD($SELECT(rows.answer = "ok": ##class(Shutter.Util.EngineWords).Attempts(rows.rows), 1: ""))
    }
    Set row.ErrorHeaderMark = ..MarkAfter(row.ErrorHeaderMark, ids, words, .header)
    Quit header '= ""
}

/// Where the mark goes after judging ids, oldest first, with words their Attempts answers ("" where the rows could not be
/// read). It moves only past headers read, and stops short of an unread one and of the first never_opened, which is header:
/// PollOne moves it past that one once the outage is open. Headers after an unread one are still judged.
ClassMethod MarkAfter(mark As %String, ids As %List, words As %List, Output header As %String) As %String
{
    Set header = "", moving = 1
    For i = 1:1:$LISTLENGTH(ids) {
        Set word = $LIST(words, i)
        If word = "never_opened" Set header = $LIST(ids, i) Quit
        If word = "" Set moving = 0
        If moving Set mark = $LIST(ids, i)
    }
    Quit mark
}

/// The oldest Error headers to the item above the mark, a list of at most 50. 0 on a failed read. Only stock classes while
/// switched.
ClassMethod ErrorHeaders(ns As %String, item As %String, mark As %Integer, Output ids As %List) As %Boolean [ Private ]
{
    Set ids = "", ok = 0
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 50 ID FROM Ens.MessageHeader WHERE TargetConfigName = ? AND Status = ? AND ID > ? ORDER BY ID", item, ..#ERRORSTATUS, mark)
        If rs.%SQLCODE < 0 Quit
        While rs.%Next() {
            Set ids = ids _ $LISTBUILD(rs.%Get("ID"))
        }
        If rs.%SQLCODE < 0 Quit
        Set ok = 1
    } Catch ex {
        Set ok = 0
    }
    Quit ok
}

/// The highest Error header to the item above the mark, or the mark itself as a number when there is none. 0 on a failed read.
/// Only stock classes while switched.
ClassMethod HighestErrorHeader(ns As %String, item As %String, mark As %Integer, Output highest As %Integer) As %Boolean [ Private ]
{
    Set highest = +mark, ok = 0
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT MAX(ID) AS Highest FROM Ens.MessageHeader WHERE TargetConfigName = ? AND Status = ? AND ID > ?", item, ..#ERRORSTATUS, +mark)
        If rs.%SQLCODE < 0 Quit
        If rs.%Next() && (rs.%Get("Highest") '= "") Set highest = +rs.%Get("Highest")
        If rs.%SQLCODE < 0 Quit
        Set ok = 1
    } Catch ex {
        Set ok = 0
    }
    Quit ok
}

/// AdapterState as one word, from a job count and a word, never a substring: connected, disconnected, mixed (some jobs of each),
/// or other (listening, unscheduled, disabled, not connecting, n/a, empty).
ClassMethod AdapterWord(text As %String) As %String
{
    Set connected = 0, disconnected = 0
    For i = 1:1:$LENGTH(text, ",") {
        Set part = $ZSTRIP($PIECE(text, ",", i), "<>W")
        If '$MATCH(part, "\d+ jobs? (connected|disconnected)") Return "other"
        If $PIECE(part, " ", 3) = "connected" { Set connected = connected + $PIECE(part, " ", 1) } Else { Set disconnected = disconnected + $PIECE(part, " ", 1) }
    }
    If text = "" Quit "other"
    If connected && disconnected Quit "mixed"
    If connected Quit "connected"
    If disconnected Quit "disconnected"
    Quit "other"
}

/// The item's retry behaviour: unlimited (FailureTimeout -1), bounded (above 0), none (0), or unknown when the read was unknown.
ClassMethod RetryOf(source As %String, value As %String) As %String
{
    If (source = "unknown") || (source = "") Quit "unknown"
    If '$MATCH(value, "-?\d+") Quit "unknown"
    If value = -1 Quit "unlimited"
    If value = 0 Quit "none"
    If value > 0 Quit "bounded"
    Quit "unknown"
}

/// What the head message's newest rows say: refusing, not_answering or empty. The words are matched where the engine writes
/// them, at the start of a row, since a receiver's own words follow later in the same text. Takes EngineRead.LogRows' answer.
ClassMethod HeadWords(rows As %DynamicObject) As %String
{
    If '$ISOBJECT(rows) || (rows.answer '= "ok") Quit ""
    Set list = rows.rows
    For i = list.%Size() - 1:-1:0 {
        Set text = list.%Get(i).%Get("text"), start = $EXTRACT(text, 1, 80)
        If (start [ "Retrying HL7 Message") && (text [ "MSA code '") Return "refusing"
        If start [ "ErrTCPTerminatedReadTimeoutExpired" Return "not_answering"
    }
    Quit ""
}

/// The job list's active message as a check on the head: words when both were read and they differ, else empty. It changes no
/// reading, since either can move between the two reads, and with PoolSize above 1 a job may hold another message.
ClassMethod HeadCheck(head As %String, active As %String) As %String
{
    If (head = "") || (active = "") || (head = active) Quit ""
    Quit "the job list shows message " _ active _ " active and the head is " _ head
}

/// One of the seven readings. facts: answer, productionState, enabled, status, adapterState, queue, head, active, lastHead,
/// headWords, retry, stayConnected, open.
ClassMethod ReadingOf(facts As %DynamicObject) As %String
{
    If (facts.answer '= "ok") || (facts.productionState '= "running") || 'facts.enabled Quit "unknown"
    Set word = ..AdapterWord(facts.adapterState), status = $ZCONVERT(facts.status, "L")
    Set held = (+facts.queue > 0) || (facts.head '= "") || (facts.active '= "")
    // A no-retry item that is quiet: nothing shows whether the listener is there, unless it reads connected with no outage open.
    If (facts.retry '= "unlimited") && 'held && (facts.open || (word '= "connected")) Quit "cant_tell"
    If word = "connected" {
        If (facts.head '= "") && (facts.head = facts.lastHead) && (facts.headWords '= "") Quit facts.headWords
        If (status = "ok") || (status = "inactive") Quit $SELECT(+facts.queue > 0: "slow", 1: "healthy")
        // Error is sticky after one refusal on a quiet feed: with nothing held, the last message failed and no more than that.
        If 'held Quit "healthy"
        Quit "cant_tell"
    }
    If word = "disconnected" {
        If facts.stayConnected = 0 Quit "cant_tell"
        If (status = "error") || (status = "retry") Quit "down"
    }
    Quit "cant_tell"
}

/// Whether a reading names a kind of outage.
ClassMethod IsKind(reading As %String) As %Boolean
{
    Quit (reading = "down") || (reading = "refusing") || (reading = "not_answering") || (reading = "cant_tell")
}

/// When the unbroken run of down readings began: kept while every poll reads down, and started again after a gap with no poll.
ClassMethod DownSince(reading As %String, since As %String, lastChecked As %String, now As %String) As %String
{
    If reading '= "down" Quit ""
    If (since = "") || (lastChecked = "") Quit now
    Set gap = ##class(Shutter.Util.Time).MillisBetween(lastChecked, now)
    If (gap = "") || (gap > (..#GAPSECONDS * 1000)) Quit now
    Quit since
}

/// Why an outage opens now, or empty. fresh: a new Error header at an item that finishes with messages by itself reads
/// never_opened. Not on a queue's depth, a sticky Error or one poll.
ClassMethod ShouldOpen(reading As %String, since As %String, now As %String, fresh As %Boolean) As %String
{
    If fresh Quit "a new header failed and no connection opened"
    If reading = "refusing" Quit "the receiver refuses the message at the head"
    If reading = "not_answering" Quit "the listener is not answering the message at the head"
    If reading '= "down" Quit ""
    If since = "" Quit ""
    If ##class(Shutter.Util.Time).MillisBetween(since, now) < (..#OPENSECONDS * 1000) Quit ""
    Quit "every poll across " _ ..#OPENSECONDS _ " s read down"
}

}
