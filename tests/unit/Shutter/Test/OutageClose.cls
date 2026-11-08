/// How an open outage moves on and closes, by table with no instance state where the judging is pure, and on the store for a
/// close from the poll: the state table, the quiet clock, every header in one place, the close's words, a linked case judged
/// from its own delivery header, the alerts' kinds, the pause's end and the overdue line.
Class Shutter.Test.OutageClose Extends %UnitTest.TestCase
{

Parameter RECEIVER = "Unit Close Receiver";

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
    &sql(DELETE FROM Shutter_Store.CaseEvent WHERE "Case" IN (SELECT ID FROM Shutter_Store."Case" WHERE Receiver = :name))
    &sql(DELETE FROM Shutter_Store."Case" WHERE Receiver = :name)
}

Method Close() As %String [ Private ]
{
    Quit "Shutter.Operation.OutageClose"
}

Method Entry() As %DynamicObject [ Private ]
{
    Quit {"name": (..#RECEIVER), "watch": {"namespace": ($NAMESPACE), "item": "Unit Close Out"}, "runbook": "start the listener", "call": "the on-call", "approvers": ["a person"]}
}

/// A poll's facts for Next: connected and OK, quiet or not, on the path asked.
Method Facts(state As %String, retry As %String, quiet As %Boolean, quietSince As %String = "", word As %String = "connected", status As %String = "OK", reading As %String = "healthy") As %DynamicObject [ Private ]
{
    Set f = {"state": (state), "reading": (reading), "retry": (retry), "stayConnected": "-1", "status": (status), "word": (word), "quietSince": (quietSince), "openedAt": "2026-11-08T01:00:00Z", "drainStartedAt": "", "settleMinutes": 10}
    Do f.%Set("quiet", quiet, "boolean")
    Quit f
}

/// The retry path leaves open only by draining, and an active delivery at the head doesn't stop it: the facts carry no head.
Method TestRetryPathDrains()
{
    Set c = ..Close(), now = "2026-11-08T01:05:00Z"
    Set n = $CLASSMETHOD(c, "Next", ..Facts("open", "unlimited", 0), now)
    Do $$$AssertEquals(n.to, "draining", "connected and OK, a backlog still queued: draining")
    Do $$$AssertEquals(n.drainStartedAt, now, "the drain's clock starts")
    Set n = $CLASSMETHOD(c, "Next", ..Facts("open", "unlimited", 1, "2026-11-08T01:04:00Z", "disconnected", "Retry", "down"), now)
    Do $$$AssertEquals(n.to, "open", "quiet but down: the retry path never closes from open")
    For reading = "refusing", "not_answering" {
        Set n = $CLASSMETHOD(c, "Next", ..Facts("open", "unlimited", 0, "", "connected", "OK", reading), now)
        Do $$$AssertEquals(n.to, "open", "connected and OK while " _ reading _ ": not draining")
    }
    Set n = $CLASSMETHOD(c, "Next", ..Facts("open", "unlimited", 0, "", "connected", "Error"), now)
    Do $$$AssertEquals(n.to, "open", "Status Error: not draining")
    Set f = ..Facts("open", "unlimited", 0), f.stayConnected = 0
    Set n = $CLASSMETHOD(c, "Next", f, now)
    Do $$$AssertEquals(n.to, "open", "StayConnected 0 is the no-retry path: never draining")
    Set f = ..Facts("open", "unlimited", 0), f.stayConnected = ""
    Set n = $CLASSMETHOD(c, "Next", f, now)
    Do $$$AssertEquals(n.to, "open", "StayConnected unread is the no-retry path: never draining")
    Set f = ..Facts("open", "unlimited", 1, "2026-11-08T01:04:55Z", "disconnected", "Retry", "cant_tell"), f.stayConnected = ""
    Set n = $CLASSMETHOD(c, "Next", f, now)
    Do $$$AssertEquals(n.to, "closing", "and it leaves open on two quiet polls, whatever the adapter reads")
    Set f = ..Facts("open", "unlimited", 0), f.stayConnected = ""
    Set n = $CLASSMETHOD(c, "Next", f, "2026-11-08T01:10:00Z")
    Do $$$AssertEquals(n.to, "needs_person", "with the busy feed's clock")
}

/// Two quiet polls at least 4 s apart close the drain; one, or two too close, don't.
Method TestTwoQuietPollsClose()
{
    Set c = ..Close(), now = "2026-11-08T01:05:10Z"
    Set n = $CLASSMETHOD(c, "Next", ..Facts("draining", "unlimited", 1), now)
    Do $$$AssertEquals(n.to, "draining", "the first quiet poll")
    Do $$$AssertEquals(n.quietSince, now, "starts the quiet clock")
    Set n = $CLASSMETHOD(c, "Next", ..Facts("draining", "unlimited", 1, "2026-11-08T01:05:08Z"), now)
    Do $$$AssertEquals(n.to, "draining", "two quiet polls 2 s apart are not enough")
    Set n = $CLASSMETHOD(c, "Next", ..Facts("draining", "unlimited", 1, "2026-11-08T01:05:05Z"), now)
    Do $$$AssertEquals(n.to, "closing", "two quiet polls 5 s apart")
    Set n = $CLASSMETHOD(c, "Next", ..Facts("draining", "unlimited", 0, "2026-11-08T01:05:05Z"), now)
    Do $$$AssertEquals(n.to, "draining", "the queue moved again")
    Do $$$AssertEquals(n.quietSince, "", "and the quiet clock starts again")
}

/// A dirty read during the drain goes back to open with both clocks reset.
Method TestDirtyDrainReopens()
{
    Set c = ..Close(), now = "2026-11-08T01:06:00Z"
    For row = "disconnected:Retry:down", "connected:Retry:cant_tell", "connected:Error:cant_tell", "connected:OK:refusing", "connected:OK:not_answering", "mixed:OK:cant_tell" {
        Set f = ..Facts("draining", "unlimited", 1, "2026-11-08T01:05:00Z", $PIECE(row, ":", 1), $PIECE(row, ":", 2), $PIECE(row, ":", 3))
        Set f.drainStartedAt = "2026-11-08T01:04:00Z"
        Set n = $CLASSMETHOD(c, "Next", f, now)
        Do $$$AssertEquals(n.to, "open", "dirty: " _ row)
        Do $$$AssertEquals(n.quietSince, "", "quiet clock reset: " _ row)
        Do $$$AssertEquals(n.drainStartedAt, "", "drain clock reset: " _ row)
    }
}

/// The no-retry path closes on two quiet polls whatever Status and AdapterState read, and a busy feed goes to a person.
Method TestNoRetryPath()
{
    Set c = ..Close(), now = "2026-11-08T01:05:10Z"
    For retry = "none", "bounded", "unknown" {
        Set n = $CLASSMETHOD(c, "Next", ..Facts("open", retry, 1, "2026-11-08T01:05:05Z", "disconnected", "Error", "cant_tell"), now)
        Do $$$AssertEquals(n.to, "closing", retry _ ": quiet twice, disconnected and Error")
        Set n = $CLASSMETHOD(c, "Next", ..Facts("open", retry, 0, "", "connected", "OK", "cant_tell"), now)
        Do $$$AssertEquals(n.to, "open", retry _ ": never draining")
    }
    Set n = $CLASSMETHOD(c, "Next", ..Facts("open", "none", 0), "2026-11-08T01:09:59Z")
    Do $$$AssertEquals(n.to, "open", "a busy feed before settle_minutes")
    Set n = $CLASSMETHOD(c, "Next", ..Facts("open", "none", 0), "2026-11-08T01:10:00Z")
    Do $$$AssertEquals(n.to, "needs_person", "a busy feed at settle_minutes")
    Do $$$AssertTrue(n.why [ "busy feed", "says so")
    Set n = $CLASSMETHOD(c, "Next", ..Facts("open", "unlimited", 0, "", "disconnected", "Retry", "down"), "2026-11-08T02:00:00Z")
    Do $$$AssertEquals(n.to, "open", "the retry path stays open while down, however long")
    Set f = ..Facts("draining", "unlimited", 0), f.drainStartedAt = "2026-11-08T01:00:00Z", f.settleMinutes = 1
    Set n = $CLASSMETHOD(c, "Next", f, "2026-11-08T01:00:59Z")
    Do $$$AssertEquals(n.to, "draining", "draining before settle_minutes")
    Set n = $CLASSMETHOD(c, "Next", f, "2026-11-08T01:01:00Z")
    Do $$$AssertEquals(n.to, "needs_person", "draining at settle_minutes")
}

/// A poll that could not read the engine judges nothing.
Method TestUnknownJudgesNothing()
{
    Set c = ..Close()
    For state = "open", "draining" {
        Set n = $CLASSMETHOD(c, "Next", ..Facts(state, "none", 1, "2026-11-08T01:00:00Z", "connected", "OK", "unknown"), "2026-11-08T03:00:00Z")
        Do $$$AssertEquals(n.to, state, state _ " stays")
        Do $$$AssertEquals(n.quietSince, "", "and the quiet run starts again")
    }
}

Method TestQuiet()
{
    Set c = ..Close()
    Set f = {"answer": "ok", "productionState": "running", "enabled": 1, "queue": 0, "head": ""}
    Do $$$AssertTrue($CLASSMETHOD(c, "Quiet", f), "queue 0, no head")
    Set f.head = 41
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Quiet", f), "a head message")
    Set f.head = "", f.queue = 1
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Quiet", f), "something queued")
    Set f.queue = ""
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Quiet", f), "a queue not read")
    Set f.queue = 0, f.enabled = 0
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Quiet", f), "the item disabled")
    Set f.enabled = 1, f.productionState = "not running"
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Quiet", f), "the production stopped")
    Set f.productionState = "running", f.answer = "unknown"
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Quiet", f), "a failed read")
}

/// Where each header goes: Completed counted, and every other status in one list with its reason.
Method TestDisposition()
{
    Set c = ..Close()
    For row = "Completed::-:completed", "Queued::queued:-", "Delivered::queued:-", "Error:never_opened:refused:error", "Error:reached_receiver:reached:error", "Error:unknown:reached:error", "Error:no_rows:reached:error", "Suspended::refused:suspended", "Aborted::refused:other", "Discarded::refused:other", "Deferred::refused:other", "Created::refused:other", ":unknown:refused:other" {
        Set d = $CLASSMETHOD(c, "Disposition", $PIECE(row, ":", 1), $PIECE(row, ":", 2))
        Do $$$AssertEquals($SELECT(d.list = "": "-", 1: d.list), $PIECE(row, ":", 3), "list " _ row)
        Do $$$AssertEquals($SELECT(d.count = "": "-", 1: d.count), $PIECE(row, ":", 4), "count " _ row)
    }
    Do $$$AssertTrue($CLASSMETHOD(c, "Disposition", "Aborted", "").reason [ "Aborted", "a person's act is named with its status word")
    Do $$$AssertTrue($CLASSMETHOD(c, "Disposition", "Error", "never_opened").reason [ "no set gate in this build", "nothing offered without a set gate")
    Do $$$AssertTrue($CLASSMETHOD(c, "Disposition", "Error", "reached_receiver").reason [ "check its screen", "the receiver's screen")
}

/// Every header of the window is in exactly one place.
Method TestSortPlacesEveryHeaderOnce()
{
    Set c = ..Close()
    Set rows = []
    Set statuses = $LISTBUILD("Completed", "Completed", "Suspended", "Aborted", "Error", "Error", "Queued")
    Set attempts = $LISTBUILD("", "", "", "", "never_opened", "reached_receiver", "")
    For i = 1:1:$LISTLENGTH(statuses) {
        Set h = {"headerId": (100 + i), "controlId": ("C" _ i), "timeCreated": "2026-11-08 01:00:00.000", "status": ($LIST(statuses, i)), "attempts": ($LIST(attempts, i)), "patient": {"id": "", "authority": ""}}
        Do h.%Set("moreThanOnce", (i = 2), "boolean")
        Do rows.%Push(h)
    }
    Set s = $CLASSMETHOD(c, "Sort", {"answer": "ok", "rows": (rows)})
    Do $$$AssertEquals(s.settled.%ToJSON(), "{""completed"":2,""suspended"":1,""error"":2,""other"":1}", "the settled counts")
    Do $$$AssertEquals(s.lists.queued.%Size(), 1, "one still queued")
    Do $$$AssertEquals(s.lists.offered.%Size(), 0, "nothing offered")
    Do $$$AssertEquals(s.lists.reached.%Size(), 1, "one may be at the receiver")
    Do $$$AssertEquals(s.lists.refused.%Size(), 3, "the Suspended, the Aborted and the never-opened Error")
    Do $$$AssertEquals(s.lists.refused.%Get(1).status, "Aborted", "the Aborted header listed with its word")
    Do $$$AssertEquals(s.moreThanOnce.%ToJSON(), "[102]", "the Completed header that may have gone twice")
    Set total = s.settled.completed + s.lists.queued.%Size() + s.lists.reached.%Size() + s.lists.refused.%Size()
    Do $$$AssertEquals(total, rows.%Size(), "every header once")
    Set s = $CLASSMETHOD(c, "Sort", {"answer": "unknown", "why": "no"})
    Do $$$AssertEquals(s.lists.refused.%Size(), 0, "an unread window lists nothing")
}

Method Words(errors As %Integer = 0, open As %Integer = 0, why As %String = "") As %DynamicObject [ Private ]
{
    Set w = {"why": (why), "unreadWhy": "", "errors": (errors), "openCases": (open), "completed": 6, "suspended": 0, "other": 0, "queued": 0, "moreThanOnce": [], "drainedAt": "03:13:00", "recoveredAt": "03:12:01"}
    Do w.%Set("unread", 0, "boolean"), w.%Set("truncated", 0, "boolean")
    Quit w
}

/// The close's verdict: closed only with no Error header and nothing queued; an Error header never closes unread by a person.
Method TestCloseWords()
{
    Set c = ..Close()
    Set r = $CLASSMETHOD(c, "CloseWords", ..Words())
    Do $$$AssertEquals(r.to, "closed", "only Completed: closed")
    Do $$$AssertTrue(r.outcome [ "The engine's connection recovered at 03:12:01. Delivery backlog drained at 03:13:00.", "the return words")
    Do $$$AssertTrue(r.outcome [ "6 deliveries Completed", "the count")
    Do $$$AssertNotTrue(r.outcome [ "Verified", "never verified")
    Set r = $CLASSMETHOD(c, "CloseWords", ..Words(5))
    Do $$$AssertEquals(r.to, "needs_person", "Error headers: a person")
    Do $$$AssertEquals(r.outcome, "5 messages failed and were not offered; a person reads the trace.", "the words")
    Set r = $CLASSMETHOD(c, "CloseWords", ..Words(1))
    Do $$$AssertEquals(r.outcome, "1 message failed and was not offered; a person reads the trace.", "one")
    Set r = $CLASSMETHOD(c, "CloseWords", ..Words(0, 2))
    Do $$$AssertEquals(r.to, "closed", "open cases don't hold the transport outage open")
    Do $$$AssertEquals($EXTRACT(r.outcome, 1, 65), "Transport outage closed. 2 delivery exceptions still need review.", "never green over open work")
    Set r = $CLASSMETHOD(c, "CloseWords", ..Words(0, 1))
    Do $$$AssertTrue(r.outcome [ "1 delivery exception still needs review.", "one exception")
    Set w = ..Words(), w.suspended = 1, w.completed = 5
    Do w.moreThanOnce.%Push(41)
    Set r = $CLASSMETHOD(c, "CloseWords", w)
    Do $$$AssertEquals(r.to, "closed", "an AE in the drain closes as settled")
    Do $$$AssertTrue(r.outcome [ "1 was Suspended and still needs action", "and says so")
    Do $$$AssertTrue(r.outcome [ "Header 41 may have reached the receiver more than once.", "the header that may have gone twice")
    Set w = ..Words(), w.queued = 1
    Do $$$AssertEquals($CLASSMETHOD(c, "CloseWords", w).to, "open", "queued again at the close: a dirty read")
    Set w = ..Words(3, 0, "a busy feed: messages keep failing and the queue is never empty"), w.queued = 2
    Set r = $CLASSMETHOD(c, "CloseWords", w)
    Do $$$AssertEquals(r.to, "needs_person", "a busy feed goes to a person, queue or no queue")
    Do $$$AssertTrue(r.outcome [ "A busy feed" && (r.outcome [ "3 messages failed and were not offered"), r.outcome)
    Set w = ..Words(), w.unread = 1, w.unreadWhy = "no such namespace"
    Do $$$AssertEquals($CLASSMETHOD(c, "CloseWords", w).to, "needs_person", "headers not read: never closed")
    Set w = ..Words(), w.truncated = 1
    Do $$$AssertEquals($CLASSMETHOD(c, "CloseWords", w).to, "needs_person", "headers not all read: never closed")
}

Method Link(state As %String, kind As %String, code As %String = "", custody As %String = "", ack As %String = "") As %DynamicObject [ Private ]
{
    Set c = {"state": (state), "failureKind": (kind), "failureReasonCode": (code), "deliveryHeader": "77", "deliveryCustody": (custody), "deliveryStatus": "", "effectiveAck": (ack), "words": "the shared sentence"}
    Do c.%Set("identity", 0, "boolean")
    Quit c
}

/// Membership is no authority: only an engine delivery failure whose own header reads Completed, at an established level.
Method TestLinkVerdict()
{
    Set c = ..Close()
    Set v = $CLASSMETHOD(c, "LinkVerdict", ..Link("blocked", "delivery_failed", "", "delivered", "connection"))
    Do $$$AssertTrue(v.resolve, "a QueueWaitAlert case whose header completed")
    Set v = $CLASSMETHOD(c, "LinkVerdict", ..Link("escalated", "uncertain_outcome", "", "delivered", "application"))
    Do $$$AssertTrue(v.resolve, "an uncertain outcome, escalated, completed")
    Set v = $CLASSMETHOD(c, "LinkVerdict", ..Link("blocked", "delivery_failed", "ack_AE", "delivered", "connection"))
    Do $$$AssertNotTrue(v.resolve, "an application ACK failure stays")
    Do $$$AssertTrue(v.decided && (v.reason [ "ack_AE"), "known before the engine is read")
    Set v = $CLASSMETHOD(c, "LinkVerdict", ..Link("blocked", "rejected", "", "delivered", "connection"))
    Do $$$AssertNotTrue(v.resolve, "a content refusal stays")
    Set v = $CLASSMETHOD(c, "LinkVerdict", ..Link("blocked", "unmappable", "", "delivered", "connection"))
    Do $$$AssertNotTrue(v.resolve, "an unmappable message stays")
    Set l = ..Link("blocked", "delivery_failed", "", "delivered", "connection"), l.identity = 1
    Do $$$AssertNotTrue($CLASSMETHOD(c, "LinkVerdict", l).resolve, "an identity exception stays")
    For state = "awaiting_approval", "approved", "executing", "verifying" {
        Set v = $CLASSMETHOD(c, "LinkVerdict", ..Link(state, "delivery_failed", "", "delivered", "connection"))
        Do $$$AssertNotTrue(v.resolve, state _ ": under a person's review")
        Do $$$AssertNotTrue(v.finished, state _ " is listed open")
    }
    For state = "detected", "investigating", "gated" {
        Do $$$AssertNotTrue($CLASSMETHOD(c, "LinkVerdict", ..Link(state, "delivery_failed", "", "delivered", "connection")).resolve, state _ ": the workflow's")
    }
    Set v = $CLASSMETHOD(c, "LinkVerdict", ..Link("blocked", "delivery_failed", "", "delivered", "not_established"))
    Do $$$AssertNotTrue(v.resolve, "GetReply off: not established")
    Do $$$AssertEquals(v.reason, "the shared sentence", "and the sentence goes with it")
    For custody = "settled", "engine", "unreadable" {
        Set v = $CLASSMETHOD(c, "LinkVerdict", ..Link("blocked", "delivery_failed", "", custody, ""))
        Do $$$AssertNotTrue(v.resolve, "its own header reads " _ custody _ ": linked by time, not resolved")
        Do $$$AssertTrue(v.reason [ "77", "names its own header")
    }
    Set v = $CLASSMETHOD(c, "LinkVerdict", ..Link("blocked", "delivery_failed"))
    Do $$$AssertNotTrue(v.decided, "not decided before the engine is read")
    For state = "resolved", "failed" {
        Set v = $CLASSMETHOD(c, "LinkVerdict", ..Link(state, "delivery_failed"))
        Do $$$AssertTrue(v.finished && 'v.resolve, state _ ": finished, nothing to do")
    }
}

Method TestAlertKind()
{
    Set c = ..Close()
    Do $$$AssertEquals($CLASSMETHOD(c, "AlertKind", "QueueWaitAlert: Message Header Id '37' queued for config item 'Unit Out' with priority 'Async' has been queued for more than 30 seconds"), "QueueWaitAlert", "queue wait")
    Do $$$AssertEquals($CLASSMETHOD(c, "AlertKind", "QueueCountAlert: Queue count of '3' exceeded for host 'Unit Out'"), "QueueCountAlert", "queue count")
    Do $$$AssertEquals($CLASSMETHOD(c, "AlertKind", "ERROR <Ens>ErrOutConnectExpired: TCP Connect timeout period (5) expired for 127.0.0.1:7712"), "AlertOnError", "an error raised as an alert")
    Do $$$AssertEquals($CLASSMETHOD(c, "AlertKind", "InactivityTimeout of 60 seconds exceeded for 'Unit Out'"), "InactivityTimeout", "inactivity")
    Do $$$AssertEquals($CLASSMETHOD(c, "AlertKind", "something else"), "alert", "anything else")
}

Method TestMoreThanOnce()
{
    Set c = ..Close()
    Set timeout = {"text": "ERROR <Ens>ErrTCPTerminatedReadTimeoutExpired: TCP Read timeout (30) expired waiting for terminator SegTerminator", "messageId": "41"}
    Set lost = {"text": "ERROR <Ens>ErrOutConnectionLost: TCP Write/Read lost connection during HL7 Read", "messageId": "41"}
    Set connect = {"text": "ERROR <Ens>ErrOutConnectExpired: TCP Connect timeout period (5) expired for 127.0.0.1:7711", "messageId": "41"}
    Do $$$AssertTrue($CLASSMETHOD(c, "MoreThanOnce", "Completed after 2 retries", [(timeout)]), "a read timeout before the completion")
    Do $$$AssertTrue($CLASSMETHOD(c, "MoreThanOnce", "", [(connect), (lost)]), "a lost read, whatever the description")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "MoreThanOnce", "Completed after 3 retries", [(connect), (connect)]), "only failed connects: it went once")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "MoreThanOnce", "", []), "no rows")
}

Method TestPauseOverAndOverdue()
{
    Set c = ..Close()
    Do $$$AssertTrue($CLASSMETHOD(c, "PauseOver", "2026-11-08T06:00:00Z", "2026-11-08T06:00:00Z"), "at the date")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "PauseOver", "2026-11-08T06:00:00Z", "2026-11-08T05:59:59Z"), "before it")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "PauseOver", "not a date", "2026-11-08T05:59:59Z"), "a date that doesn't read never ends by itself")
    Do $$$AssertTrue($CLASSMETHOD(c, "Overdue", "2026-11-08T01:00:00Z", "", "open", "2026-11-08T02:00:00Z", 60), "at 60 minutes")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Overdue", "2026-11-08T01:00:00Z", "", "open", "2026-11-08T01:59:59Z", 60), "before")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Overdue", "2026-11-08T01:00:00Z", "2026-11-08T02:00:00Z", "open", "2026-11-08T03:00:00Z", 60), "once")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Overdue", "2026-11-08T01:00:00Z", "", "closed", "2026-11-08T03:00:00Z", 60), "never on a closed row")
}

/// The poll's change on the store: the state and version move with an event, fields land, a stale copy gives up quietly, and
/// closed lets a new outage open.
Method TestAdvance()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "down", "a test", "unit", .o), "opened")
    Set id = o.%Id()
    Do $$$AssertStatusOK(o.Advance("draining", "the engine is delivering", "unit", {"DrainStartedAt": "2026-11-08T01:00:00Z"}, , .moved), "draining")
    Do $$$AssertTrue(moved, "it moved")
    Do $$$AssertEquals(o.Version, 2, "the version with the state")
    Do $$$AssertStatusOK(o.Advance("draining", "", "unit", {"QuietSince": "2026-11-08T01:00:05Z"}, , .moved), "a field alone")
    Do $$$AssertEquals(o.Version, 2, "no state, no version")
    &sql(UPDATE Shutter_Store.Outage SET State = 'open', Version = 3 WHERE ID = :id)
    Do $$$AssertStatusOK(o.Advance("closing", "quiet", "unit", , , .moved), "a stale copy gives up quietly")
    Do $$$AssertNotTrue(moved, "and doesn't move")
    Do $$$AssertEquals(o.State, "open", "the copy reads the store")
    Do $$$AssertStatusOK(o.Advance("closing", "quiet", "unit", , , .moved), "closing")
    Do $$$AssertStatusOK(o.Advance("closed", "drained", "unit", {"Outcome": "Delivery backlog drained.", "ListRefused": [{"headerId": 9}], "LinkedCases": [{"caseId": "C-1"}]}, , .moved), "closed from closing")
    Set j = o.ToJSON()
    Do $$$AssertEquals(j.state, "closed", "closed")
    Do $$$AssertEquals(j.outcome, "Delivery backlog drained.", "outcome")
    Do $$$AssertEquals(j.lists.refused.%Get(0).headerId, 9, "a list")
    Do $$$AssertEquals(j.linkedCases.%Get(0).caseId, "C-1", "the linked cases")
    Do $$$AssertTrue(j.closedAt '= "", "the time")
    Do $$$AssertNotTrue($ISOBJECT(##class(Shutter.Store.Outage).ActiveFor(..#RECEIVER)), "no longer active")
    Set kinds = ""
    Set events = ##class(Shutter.Store.OutageEvent).Of(id), iter = events.%GetIterator()
    While iter.%GetNext(.i, .e) { Set kinds = kinds _ $SELECT(kinds = "": "", 1: ",") _ e.kind }
    Do $$$AssertEquals(kinds, "opened,draining,closing,closed", "closed only from closing")
    Do $$$AssertStatusOK(o.Advance("open", "again", "unit", , , .moved), "a closed row never changes")
    Do $$$AssertNotTrue(moved, "nothing moved")
}

/// Down on purpose until a date: the poll brings it back to open at the date, with the set no longer withheld.
Method TestPausedByDate()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "down", "a test", "unit", .o), "opened")
    Do $$$AssertStatusOK(o.Pause("2030-01-01T00:00:00Z", "a person"), "paused")
    Do $$$AssertStatusOK(##class(Shutter.Operation.OutageClose).Step(o, ..Entry(), {}, "down", "2026-11-08T01:00:00Z"), "a poll before the date")
    Do $$$AssertEquals(o.State, "paused", "still paused")
    Do $$$AssertStatusOK(##class(Shutter.Operation.OutageClose).Step(o, ..Entry(), {}, "down", "2030-01-01T00:00:01Z"), "a poll after it")
    Set j = o.ToJSON()
    Do $$$AssertEquals(j.state, "open", "open again")
    Do $$$AssertEquals(j.set.status, "not_computed", "the set no longer withheld")
    Do $$$AssertEquals(j.%GetTypeOf("pausedUntil"), "null", "the date cleared")
}

/// A no-retry outage closes from the poll on the store: two quiet polls, every header of the window read (none here), the
/// linked cases judged, and an exception left open with its owner.
Method TestNoRetryClosesWithOpenCases()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "cant_tell", "a test", "unit", .o), "opened")
    Do ..AddCase("rejected", "", "escalated")
    Do ..AddCase("delivery_failed", "ack_AE", "blocked")
    Do ..AddCase("delivery_failed", "", "awaiting_approval")
    Set facts = {"answer": "ok", "productionState": "running", "enabled": 1, "queue": 0, "head": "", "retry": "none", "stayConnected": "-1", "status": "Error", "adapterState": "1 job disconnected"}
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Do $$$AssertStatusOK(##class(Shutter.Operation.OutageClose).Step(o, ..Entry(), facts, "cant_tell", now), "the first quiet poll")
    Do $$$AssertEquals(o.State, "open", "one quiet poll is not enough")
    Do $$$AssertTrue(o.QuietSince '= "", "the quiet clock started")
    Do $$$AssertStatusOK(##class(Shutter.Operation.OutageClose).Step(o, ..Entry(), facts, "cant_tell", ##class(Shutter.Util.Time).PlusMillis(now, 5000)), "the second, 5 s on")
    Set j = o.ToJSON()
    Do $$$AssertEquals(j.state, "closed", "closed, whatever Status and AdapterState read")
    Do $$$AssertEquals(j.set.status, "not_computed", "set.status")
    Do $$$AssertEquals(j.set.reason, "no set gate in this build", "set.reason")
    Do $$$AssertEquals(j.openCases.%Size(), 3, "three exceptions still open")
    Do $$$AssertEquals(j.linkedCases.%Size(), 3, "three linked")
    Do $$$AssertEquals(j.openCases.%Get(0).owner, "a person", "with their owner")
    Do $$$AssertEquals($EXTRACT(j.outcome, 1, 65), "Transport outage closed. 3 delivery exceptions still need review.", j.outcome)
    Set kinds = ""
    Set events = ##class(Shutter.Store.OutageEvent).Of(o.%Id()), iter = events.%GetIterator()
    While iter.%GetNext(.i, .e) { Set kinds = kinds _ $SELECT(kinds = "": "", 1: ",") _ e.kind }
    Do $$$AssertEquals(kinds, "opened,closing,closed", "through closing")
    Set name = ..#RECEIVER
    &sql(SELECT COUNT(*) INTO :resolved FROM Shutter_Store."Case" WHERE Receiver = :name AND State = 'resolved')
    Do $$$AssertEquals(resolved, 0, "none resolved by membership")
}

/// A row left in closing (the close's save never came) is closed again by the next poll, which reads everything again.
Method TestRowLeftInClosingClosesOnTheNextPoll()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "cant_tell", "a test", "unit", .o), "opened")
    Do $$$AssertStatusOK(o.Advance("closing", "queue 0 on two polls", "unit", , , .moved), "closing, and the close never ran")
    Do ..AddCase("rejected", "", "escalated")
    Set facts = {"answer": "ok", "productionState": "running", "enabled": 1, "queue": 0, "head": "", "retry": "none", "stayConnected": "-1", "status": "Error", "adapterState": "1 job disconnected"}
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Do $$$AssertStatusOK(##class(Shutter.Operation.OutageClose).Step(o, ..Entry(), facts, "cant_tell", now), "the next poll")
    Set j = o.ToJSON()
    Do $$$AssertEquals(j.state, "closed", "closed from closing by the next poll")
    Do $$$AssertEquals(j.openCases.%Size(), 1, "the case judged")
    Do $$$AssertEquals(j.set.reason, "no set gate in this build", "set.reason")
    Set kinds = ""
    Set events = ##class(Shutter.Store.OutageEvent).Of(o.%Id()), iter = events.%GetIterator()
    While iter.%GetNext(.i, .e) { Set kinds = kinds _ $SELECT(kinds = "": "", 1: ",") _ e.kind }
    Do $$$AssertEquals(kinds, "opened,closing,closed", "one closing, then closed")
}

/// A header queued again at the close sends the row back to open before any linked case is judged.
Method TestQueuedAtTheCloseJudgesNoCase()
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Outage).Open(..Entry(), "cant_tell", "a test", "unit", .o), "opened")
    Do $$$AssertStatusOK(o.Advance("closing", "queue 0 on two polls", "unit", , , .moved), "closing")
    Do ..AddCase("rejected", "", "escalated")
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.SourceConfigName = "Unit Close In", h.TargetConfigName = "Unit Close Out", h.Status = ##class(Ens.DataType.MessageStatus).DisplayToLogical("Queued")
    Set h.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Do $$$AssertStatusOK(h.%Save(), "a header queued at the item")
    Set sc = ##class(Shutter.Operation.OutageClose).Close(o, ..Entry(), {}, ##class(Shutter.Util.Time).NowUTC(), "")
    Do ##class(Ens.MessageHeader).%DeleteId(h.%Id())
    Do $$$AssertStatusOK(sc, "the close")
    Set j = o.ToJSON()
    Do $$$AssertEquals(j.state, "open", "back to open: " _ j.state _ " " _ j.outcome)
    Do $$$AssertEquals(j.linkedCases.%Size(), 0, "no case judged")
    Do $$$AssertEquals(j.openCases.%Size(), 0, "and none listed")
}

Method AddCase(kind As %String, code As %String, state As %String) [ Private ]
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "C-U" _ $INCREMENT(^||UnitCloseCase), c.OperationKey = "unit-close-" _ c.CaseId, c.Receiver = ..#RECEIVER
    Set c.FailureKind = kind, c.FailureReasonCode = code, c.State = state, c.SourceNamespace = $NAMESPACE
    Set c.OpenedAt = ##class(Shutter.Util.Time).NowUTC(), c.UpdatedAt = c.OpenedAt
    Do $$$AssertStatusOK(c.%Save(), "a case " _ kind _ " " _ code)
}

}
