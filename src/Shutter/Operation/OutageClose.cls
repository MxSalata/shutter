/// How a receiver's open outage moves on, for the Receiver Watch's poll: from open to draining while the engine delivers the
/// backlog, back to open on a dirty read, to closing when the engine has finished with every header of the window, and from
/// closing to closed or to a person. At the close every header of the window is read and listed by what happened to it, the
/// engine's own alerts for the item sit beside the record, and the cases linked by receiver and time are each judged from
/// their own delivery header: a link is no authority to resolve. It sends nothing and writes nothing in the watched namespace.
///
/// The judging is in pure class methods (Next, Quiet, Disposition, MoreThanOnce, CloseWords, LinkVerdict, AlertKind,
/// PauseOver, Overdue), so a table can test them with no instance. With no set gate in the build, nothing is offered: an
/// Error header of the window goes to a person, and the set stays not computed.
Class Shutter.Operation.OutageClose Extends %RegisteredObject
{

/// The overdue line comes this long after the open.
Parameter OVERDUEMINUTES = 60;

/// Two quiet polls this far apart make the engine's finish with the window: the poll runs every 5 s.
Parameter QUIETMILLIS = 4000;

/// The most headers of the window one close reads; more are counted as not read, and the close goes to a person.
Parameter MAXHEADERS = 1000;

/// The most linked cases one close judges.
Parameter MAXCASES = 200;

/// Who moves the row.
Parameter ACTOR = "Receiver Watch";

/// The set's reason with no set gate in the build.
Parameter NOSETGATE = "no set gate in this build";

/// One poll's step for a receiver's outage that is not closed. reading is the poll's reading, facts what Read gave.
ClassMethod Step(outage As Shutter.Store.Outage, entry As %DynamicObject, facts As %DynamicObject, reading As %String, now As %String) As %Status
{
    Set state = outage.State
    If state = "closed" Quit $$$OK
    If ..Overdue(outage.OpenedAt, outage.OverdueAt, state, now, ..#OVERDUEMINUTES) {
        Set line = "down longer than the site's limit: the lab's downtime procedure applies" _ $SELECT(outage.Runbook '= "": "; next: " _ $EXTRACT(outage.Runbook, 1, 500), 1: "")
        Set sc = outage.Advance(state, line, ..#ACTOR, {"OverdueAt": (now)}, "overdue")
        If $$$ISERR(sc) Quit sc
    }
    Set fields = {}
    If state = "paused" {
        If '..PauseOver(outage.PausedUntil, now) Quit $$$OK
        Set fields.PausedUntil = "", fields.QuietSince = "", fields.DrainStartedAt = "", fields.SetStatus = "not_computed", fields.SetReason = ..SetReasonNow()
        Quit outage.Advance("open", "the pause ended at " _ outage.PausedUntil, ..#ACTOR, fields)
    }
    Do ..NewAlerts(outage, fields)
    // Closing is a step within one poll: a row left there (the close's save refused by a lock, the production stopped between
    // the two saves) is closed again on the next poll. The close reads everything again, so running it twice is safe.
    If state = "closing" {
        Set sc = ..Save(outage, fields)
        If $$$ISERR(sc) Quit sc
        Quit ..Close(outage, entry, facts, now, "")
    }
    // An offered set (the set gate in the build) stands only while the engine has nothing of the window: a message tried
    // again sends the row back to open. Otherwise the poll computes the set again when a person asked (read_again) or a
    // minute has passed, so a member resent by hand meanwhile moves the digest. A person's row is read again only when asked.
    If (state = "offered") || ((state = "needs_person") && (outage.ReadAgainAt '= "")) {
        If (state = "offered") && '..IsQuiet(outage, facts, now) {
            Set fields.QuietSince = "", fields.DrainStartedAt = "", fields.SetStatus = "not_computed", fields.SetReason = "the engine is trying a message of the window again"
            Quit outage.Advance("open", "a message of the window is being tried again: the set is withdrawn and the quiet clock starts again", ..#ACTOR, fields)
        }
        Set since = ##class(Shutter.Util.Time).MillisBetween(outage.SetComputedAt, now)
        If (outage.ReadAgainAt '= "") || (since = "") || (since >= ..#RECOMPUTEMILLIS) {
            Set fields.ReadAgainAt = ""
            Set sc = ..Save(outage, fields)
            If $$$ISERR(sc) Quit sc
            Quit ..Close(outage, entry, facts, now, "")
        }
        Quit ..Save(outage, fields)
    }
    // Only open and draining are the poll's to move otherwise; sending belongs to a later part.
    If (state '= "open") && (state '= "draining") Quit ..Save(outage, fields)
    Set f = {"state": (state), "reading": (reading), "retry": (facts.retry), "stayConnected": (facts.stayConnected), "status": (facts.status), "word": (##class(Shutter.Operation.ReceiverWatch).AdapterWord(facts.adapterState)), "quietSince": (outage.QuietSince), "openedAt": (outage.OpenedAt), "drainStartedAt": (outage.DrainStartedAt), "settleMinutes": (##class(Shutter.Store.SiteProfile).ReceiverMinutes(outage.Receiver, "settle_minutes"))}
    Do f.%Set("quiet", ..IsQuiet(outage, facts, now), "boolean")
    Set next = ..Next(f, now)
    If next.quietSince '= outage.QuietSince Set fields.QuietSince = next.quietSince
    If next.drainStartedAt '= outage.DrainStartedAt Set fields.DrainStartedAt = next.drainStartedAt
    If next.to = state Quit ..Save(outage, fields)
    If next.to = "closing" {
        Set sc = outage.Advance("closing", next.why, ..#ACTOR, fields, , .moved)
        If $$$ISERR(sc) || 'moved Quit sc
        Quit ..Close(outage, entry, facts, now, "")
    }
    If next.to = "needs_person" {
        Set sc = ..Save(outage, fields)
        If $$$ISERR(sc) Quit sc
        Quit ..Close(outage, entry, facts, now, next.why)
    }
    Quit outage.Advance(next.to, next.why, ..#ACTOR, fields)
}

/// Fields alone, when there are any.
ClassMethod Save(outage As Shutter.Store.Outage, fields As %DynamicObject) As %Status [ Private ]
{
    If fields.%Size() = 0 Quit $$$OK
    Quit outage.Advance(outage.State, "", ..#ACTOR, fields)
}

/// Whether an offered set at this receiver can be approved: the build has the sender (Shutter.Operation.EngineResend) and
/// the receiver's site profile entry has engine_resend true.
ClassMethod Approvable(receiver As %String) As %Boolean
{
    Quit:'##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Operation.EngineResend") 0
    Set entry = ##class(Shutter.Store.SiteProfile).Receiver(receiver)
    Quit:'$ISOBJECT(entry) 0
    Quit (entry.%GetTypeOf("engine_resend") = "boolean") && entry.%Get("engine_resend")
}

/// How often the poll computes an offered set again, in milliseconds.
Parameter RECOMPUTEMILLIS = 60000;

/// The set's reason now: with no set gate in the build, that.
ClassMethod SetReasonNow() As %String
{
    Quit $SELECT(##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Util.ResendSet"): "", 1: ..#NOSETGATE)
}

/// The state table, pure. f: state (open or draining), reading, retry, stayConnected, status, word (AdapterWord's), quiet (the
/// engine has nothing of the window: Quiet's answer), quietSince, openedAt, drainStartedAt, settleMinutes. Answers { "to",
/// "why", "quietSince", "drainStartedAt" }. The retry path (an item that retries for ever and stays connected) leaves open
/// only by draining; the no-retry path leaves open on two quiet polls, whatever Status and AdapterState read, because there
/// the engine shows nothing about the listener while nothing is sent. A busy feed goes to a person at settleMinutes.
ClassMethod Next(f As %DynamicObject, now As %String) As %DynamicObject
{
    Set state = f.state
    Set out = {"to": (state), "why": "", "quietSince": (f.quietSince), "drainStartedAt": (f.drainStartedAt)}
    // A poll that could not read the engine judges nothing, and a quiet run it interrupts starts again.
    If (f.reading = "unknown") || (f.reading = "") {
        Set out.quietSince = ""
        Quit out
    }
    // StayConnected unread is the no-retry path, as FailureTimeout unread is: only an item known to retry and stay connected
    // waits for the adapter to read connected.
    Set retryPath = (f.retry = "unlimited") && (f.stayConnected '= "") && (f.stayConnected '= 0) && (f.stayConnected '= "0")
    Set status = $ZCONVERT(f.status, "L"), ok = (status = "ok") || (status = "inactive")
    Set dirty = (f.word '= "connected") || 'ok || (f.reading = "refusing") || (f.reading = "not_answering")
    Set twice = f.quiet && (f.quietSince '= "") && (##class(Shutter.Util.Time).MillisBetween(f.quietSince, now) >= ..#QUIETMILLIS)
    Set out.quietSince = $SELECT('f.quiet: "", f.quietSince = "": now, 1: f.quietSince)
    Set settle = 60000 * $SELECT(+f.settleMinutes > 0: +f.settleMinutes, 1: 10)
    If state = "open" {
        If retryPath {
            If 'dirty Set out.to = "draining", out.why = "connected and Status OK: the engine is delivering the backlog", out.drainStartedAt = now
            Quit out
        }
        If twice Set out.to = "closing", out.why = "queue 0, no head message and no header of the window Queued or Delivered, on two polls" Quit out
        Set since = ##class(Shutter.Util.Time).MillisBetween(f.openedAt, now)
        If (since '= "") && (since >= settle) Set out.to = "needs_person", out.why = "a busy feed: messages keep failing and the queue is never empty" Quit out
        Quit out
    }
    If state = "draining" {
        If dirty {
            Set out.to = "open", out.why = "a dirty read during the drain (" _ $SELECT(f.word '= "connected": "the adapter reads " _ f.word, 'ok: "Status " _ f.status, 1: "the receiver is " _ $TRANSLATE(f.reading, "_", " ")) _ "): the quiet clock starts again"
            Set out.quietSince = "", out.drainStartedAt = ""
            Quit out
        }
        If twice Set out.to = "closing", out.why = "queue 0, no head message and no header of the window Queued or Delivered, on two polls" Quit out
        Set since = ##class(Shutter.Util.Time).MillisBetween(f.drainStartedAt, now)
        If (since '= "") && (since >= settle) Set out.to = "needs_person", out.why = "a busy feed: the backlog has not drained in " _ (settle \ 60000) _ " minute" _ $SELECT(settle = 60000: "", 1: "s") Quit out
    }
    Quit out
}

/// Whether the engine has nothing of the window now: the read worked, the production runs, the item is enabled, the queue is
/// 0, there is no head message and no header of the window reads Queued or Delivered.
ClassMethod IsQuiet(outage As Shutter.Store.Outage, facts As %DynamicObject, now As %String) As %Boolean [ Private ]
{
    If '..Quiet(facts) Quit 0
    Set busy = ..WindowBusy(outage.Namespace, outage.Item, outage.WindowFrom, now)
    Quit busy = 0
}

/// Quiet's part from the poll's own facts, pure: { answer, productionState, enabled, queue, head }.
ClassMethod Quiet(facts As %DynamicObject) As %Boolean
{
    If (facts.answer '= "ok") || (facts.productionState '= "running") || 'facts.enabled Quit 0
    If (facts.queue = "") || (+facts.queue '= 0) Quit 0
    Quit facts.head = ""
}

/// 1 when a header to the item created since from reads Queued or Delivered, 0 when none does, "" when the read failed.
/// Only stock classes while switched.
ClassMethod WindowBusy(ns As %String, item As %String, from As %String, now As %String) As %String [ Private ]
{
    Set queued = ..StatusLogical("Queued"), delivered = ..StatusLogical("Delivered")
    If (queued = "") || (delivered = "") Quit ""
    Set from = ..EngineTime(from), answer = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM Ens.MessageHeader WHERE TargetConfigName = ? AND TimeCreated >= ? AND Status IN (?, ?)", item, from, queued, delivered)
        If rs.%SQLCODE < 0 Quit
        Set answer = rs.%Next()
        If rs.%SQLCODE < 0 Set answer = ""
    } Catch ex {
        Set answer = ""
    }
    Quit answer
}

/// A status word's stored value, from the stock enumeration.
ClassMethod StatusLogical(word As %String) As %String [ Private ]
{
    Try {
        Set value = ##class(Ens.DataType.MessageStatus).DisplayToLogical(word)
    } Catch ex {
        Set value = ""
    }
    Quit value
}

/// An ISO UTC time in the engine's stored form, "yyyy-mm-dd hh:mm:ss.fff".
ClassMethod EngineTime(iso As %String) As %String
{
    Quit $TRANSLATE($PIECE(iso, "Z", 1), "T", " ")
}

/// The close: every header of the window read and listed, the linked cases judged, then closed or to a person. why is the
/// reason when the row goes to a person whatever the headers say (a busy feed), else empty.
ClassMethod Close(outage As Shutter.Store.Outage, entry As %DynamicObject, facts As %DynamicObject, now As %String, why As %String) As %Status
{
    Set fields = {"SetStatus": "not_computed", "SetReason": (..SetReasonNow())}
    If why = "" Set fields.DrainedAt = now, fields.WindowTo = now
    // With the set gate in the build: the set, computed here in the production job, which may read the watched namespace.
    Set set = "", setReason = fields.SetReason
    If setReason = "" {
        Set set = ##class(Shutter.Util.ResendSet).Compute(outage.Namespace, outage.Item, ..EngineTime(outage.WindowFrom), ..EngineTime(now), outage.Receiver)
        Set fields.SetStatus = set.set.status, fields.SetReason = set.set.reason, fields.SetDigest = set.set.digest
        Set fields.SetComputedAt = set.set.computedAt, fields.SetPolicyVersion = set.set.setPolicyVersion
        Set setReason = set.set.reason
    }
    Set computed = $ISOBJECT(set) && (set.set.status = "computed")
    // Approvable only where the build has the sender and the receiver's profile entry says engine_resend.
    Do fields.%Set("Approvable", ..Approvable(outage.Receiver), "boolean")
    Set read = ..WindowHeaders(outage.Namespace, outage.Item, outage.WindowFrom, now)
    Set sorted = ..Sort(read, $SELECT(setReason '= "": setReason, 1: ..#NOSETGATE))
    Set fields.SettledCompleted = sorted.settled.completed, fields.SettledSuspended = sorted.settled.suspended
    Set fields.SettledError = sorted.settled.error, fields.SettledOther = sorted.settled.other
    Set lists = $SELECT(computed: set.lists, 1: sorted.lists)
    Set fields.ListQueued = lists.queued, fields.ListOffered = lists.offered
    Set fields.ListReached = lists.reached, fields.ListRefused = lists.refused
    Set fields.ListClosed = $SELECT($ISOBJECT(lists.%Get("closed")): lists.closed, 1: [])
    Set w = {"closed": (fields.ListClosed.%Size()), "why": (why), "unread": (read.answer '= "ok"), "unreadWhy": (read.why), "truncated": (sorted.truncated), "errors": (sorted.settled.error), "openCases": 0, "completed": (sorted.settled.completed), "suspended": (sorted.settled.suspended), "other": (sorted.settled.other), "queued": (sorted.lists.queued.%Size()), "moreThanOnce": (sorted.moreThanOnce), "drainedAt": ($SELECT(why = "": ..Clock(now), 1: "")), "recoveredAt": ($SELECT((why = "") && (outage.DrainStartedAt '= ""): ..Clock(outage.DrainStartedAt), 1: "")), "offered": ($SELECT(computed: lists.offered.%Size(), 1: 0))}
    // Whether the close goes back to open does not depend on the cases, so that is known before any case is judged.
    Set first = ..CloseWords(w)
    If first.to = "open" {
        // A dirty read at the close: back to open, as during the drain, with nothing of a close kept and no case touched.
        Quit outage.Advance("open", first.outcome, ..#ACTOR, {"QuietSince": "", "DrainStartedAt": ""})
    }
    // Only a close that answers closed or needs_person judges the linked cases.
    Set linked = ..Linked(outage, now)
    Set fields.LinkedCases = linked.linked, fields.OpenCases = linked.open
    Set w.openCases = linked.open.%Size()
    Set words = ..CloseWords(w)
    Set fields.Outcome = words.outcome
    // The same state and the same set: a recompute writes the fields and no event.
    If (words.to = outage.State) && computed && (set.set.digest = outage.SetDigest) Quit outage.Advance(words.to, "", ..#ACTOR, fields)
    Quit outage.Advance(words.to, words.outcome, ..#ACTOR, fields)
}

/// The close's verdict and words, pure. w: why (a busy feed's reason, or empty), unread and unreadWhy (the headers could not be
/// read), truncated, errors, openCases, completed, suspended, other, queued, moreThanOnce (header ids), drainedAt and
/// recoveredAt (clock words, or empty). Answers { "to", "outcome" }: closed only with every header read, none Error and
/// nothing queued; a header queued again at the close is a dirty read (open); otherwise needs_person, with what a person
/// must do.
ClassMethod CloseWords(w As %DynamicObject) As %DynamicObject
{
    // A message closed without a send of its own (already held at the receiver, or handled by hand) stays Error in the
    // engine, and needs nobody now.
    Set closed = +w.%Get("closed"), errors = +w.errors - closed, open = +w.openCases
    Set:errors<0 errors = 0
    Set exceptions = $SELECT(open = 0: "", 1: " " _ open _ " delivery exception" _ $SELECT(open = 1: " still needs", 1: "s still need") _ " review.")
    Set twice = ""
    Set iter = w.moreThanOnce.%GetIterator()
    While iter.%GetNext(.i, .id) {
        Set twice = twice _ " Header " _ id _ " may have reached the receiver more than once."
    }
    If w.unread Quit {"to": "needs_person", "outcome": ("The headers of the window could not be read (" _ $EXTRACT(w.unreadWhy, 1, 200) _ "): a person reads the trace." _ exceptions)}
    If w.truncated Quit {"to": "needs_person", "outcome": ("The window holds more headers than one close reads (" _ ..#MAXHEADERS _ "): a person reads the trace." _ exceptions)}
    Set failed = $SELECT(errors = 0: "", 1: errors _ " message" _ $SELECT(errors = 1: " failed and was", 1: "s failed and were") _ " not offered; a person reads the trace.")
    If w.why '= "" Quit {"to": "needs_person", "outcome": (..Upper(w.why) _ "." _ $SELECT(failed = "": "", 1: " " _ failed) _ exceptions _ twice)}
    If +w.queued Quit {"to": "open", "outcome": (+w.queued _ " of the window queued again at the close: the quiet clock starts again")}
    // With the set gate, the messages that never reached the receiver are listed for a person: the row stays offered while
    // the engine has nothing of the window. Shutter sends nothing itself.
    If +w.offered && errors Quit {"to": "offered", "outcome": (errors _ " message" _ $SELECT(errors = 1: " failed", 1: "s failed") _ "; " _ +w.offered _ " never reached the receiver and " _ $SELECT(+w.offered = 1: "is", 1: "are") _ " listed for a person. Shutter will not send these messages. Review them in the Message Viewer using the site's recovery procedure." _ exceptions _ twice)}
    If errors Quit {"to": "needs_person", "outcome": (failed _ exceptions _ twice)}
    Set words = $SELECT(w.recoveredAt '= "": "The engine's connection recovered at " _ w.recoveredAt _ ". ", 1: "")
    Set words = words _ "Delivery backlog drained" _ $SELECT(w.drainedAt '= "": " at " _ w.drainedAt, 1: "") _ ". Application processing has not been independently checked. Nothing remains queued. "
    Set words = words _ +w.completed _ " deliver" _ $SELECT(+w.completed = 1: "y", 1: "ies") _ " Completed"
    If +w.suspended Set words = words _ "; " _ +w.suspended _ $SELECT(+w.suspended = 1: " was Suspended and still needs", 1: " were Suspended and still need") _ " action"
    If +w.other Set words = words _ "; " _ +w.other _ " set aside in the engine"
    Set words = words _ "." _ twice
    If closed Set words = words _ " Every message of the window was sent or closed: " _ closed _ " closed without a send of " _ $SELECT(closed = 1: "its", 1: "their") _ " own."
    If open Set words = "Transport outage closed." _ exceptions _ " " _ words
    Quit {"to": "closed", "outcome": (words)}
}

ClassMethod Upper(text As %String) As %String [ Private ]
{
    Quit $ZCONVERT($EXTRACT(text), "U") _ $EXTRACT(text, 2, *)
}

/// Every header of the window sorted, pure. read: WindowHeaders' answer, each row with headerId, controlId, timeCreated, status
/// (the word), attempts (for Error), moreThanOnce (for Completed), patient. Answers { "settled": { completed, suspended,
/// error, other }, "lists": { queued, offered, reached, refused }, "moreThanOnce": [ ids ], "truncated" }. Every header is in
/// exactly one place: Completed in the count, the others in a list with the count of what settled.
ClassMethod Sort(read As %DynamicObject, setReason As %String = {..#NOSETGATE}) As %DynamicObject
{
    Set out = {"settled": {"completed": 0, "suspended": 0, "error": 0, "other": 0}, "lists": {"queued": [], "offered": [], "reached": [], "refused": []}, "moreThanOnce": []}
    Do out.%Set("truncated", ''read.truncated, "boolean")
    If read.answer '= "ok" Quit out
    Set iter = read.rows.%GetIterator()
    While iter.%GetNext(.i, .h) {
        Set d = ..Disposition(h.status, h.attempts, setReason)
        If d.count '= "" Do out.settled.%Set(d.count, out.settled.%Get(d.count) + 1)
        If h.moreThanOnce Do out.moreThanOnce.%Push(h.headerId)
        If d.list = "" Continue
        Set row = {"headerId": (h.headerId), "controlId": (h.controlId), "timeCreated": (h.timeCreated), "status": (h.status), "attempts": (h.attempts), "reason": (d.reason), "patient": (h.patient)}
        Do row.%Set("sibling", "", "null")
        Do out.lists.%Get(d.list).%Push(row)
    }
    Quit out
}

/// Where one header goes at the close, pure: { "list", "count", "reason" }. count is the settled count it adds to (empty for
/// one the engine still has). With no set gate nothing is offered: a header that failed before a connection opened is set
/// aside for a person, and one that may have reached the receiver is listed for its screen.
ClassMethod Disposition(status As %String, attempts As %String, setReason As %String = {..#NOSETGATE}) As %DynamicObject
{
    If status = "Completed" Quit {"list": "", "count": "completed", "reason": ""}
    If (status = "Queued") || (status = "Delivered") Quit {"list": "queued", "count": "", "reason": "the engine is still attempting this"}
    If status = "Error" {
        If attempts = "never_opened" Quit {"list": "refused", "count": "error", "reason": ("failed before a connection opened; not offered: " _ setReason _ ", so a person reads the trace")}
        If attempts = "reached_receiver" Quit {"list": "reached", "count": "error", "reason": "reached the receiver, answer unknown: check its screen; Shutter will not resend this, and if you do, use the Message Viewer"}
        Quit {"list": "reached", "count": "error", "reason": "the engine's log does not show whether it reached the receiver: check its screen; Shutter will not resend this"}
    }
    If status = "Suspended" Quit {"list": "refused", "count": "suspended", "reason": "suspended by the engine (a refusal or a stop in its reply actions): see its case"}
    Quit {"list": "refused", "count": "other", "reason": ("set aside in the engine (" _ $SELECT(status = "": "a status the engine's list does not name", 1: status) _ "): a person's decision, never offered and not waited for")}
}

/// Whether a Completed header may have reached the receiver more than once, pure: its retained rows show an attempt that
/// wrote the frame and had no answer (a read timeout, a read's lost connection) before the one that completed. description is
/// the header's own words ("after N retries"), for the record only: the rows alone decide. rows: LogRows' list.
ClassMethod MoreThanOnce(description As %String, rows As %DynamicArray) As %Boolean
{
    If '$ISOBJECT(rows) Quit 0
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set text = row.%Get("text")
        If text [ "ErrTCPTerminatedReadTimeoutExpired" Return 1
        If (text [ "ErrOutConnectionLost") && (text [ "HL7 Read") Return 1
    }
    Quit 0
}

/// The headers to the item created from from to to, read with their words: { "answer": "ok", "rows": [ { "headerId",
/// "controlId", "timeCreated", "status", "description", "attempts", "moreThanOnce", "patient": { "id", "authority" } } ],
/// "truncated" } or { "answer": "unknown", "why" }. Attempts is read for every Error header, the rows for every Completed one.
ClassMethod WindowHeaders(ns As %String, item As %String, from As %String, to As %String) As %DynamicObject
{
    Set out = {"answer": "unknown", "why": ""}
    // The end of the window is a whole second: every header made within that second is the window's.
    Set to = ..EngineTime(to)
    If to '[ "." Set to = to _ ".999"
    If '..ReadWindow(ns, item, ..EngineTime(from), to, .rows, .why) Set out.why = why Quit out
    Set truncated = (rows.%Size() > ..#MAXHEADERS)
    Set list = []
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .h) {
        If i >= ..#MAXHEADERS Quit
        Set h.status = ##class(Shutter.Util.EngineRead).StatusWord(h.status)
        Set h.attempts = ""
        Do h.%Set("moreThanOnce", 0, "boolean")
        If (h.status = "Error") || (h.status = "Completed") {
            Set log = ##class(Shutter.Util.EngineRead).LogRows(ns, h.headerId)
            If h.status = "Error" Set h.attempts = $SELECT(log.answer = "ok": ##class(Shutter.Util.EngineWords).Attempts(log.rows), 1: "unknown")
            If (h.status = "Completed") && (log.answer = "ok") Do h.%Set("moreThanOnce", ..MoreThanOnce(h.description, log.rows), "boolean")
        }
        Do list.%Push(h)
    }
    Set out.answer = "ok", out.rows = list
    Do out.%Set("truncated", truncated, "boolean")
    Quit out
}

/// The window's headers in the item's namespace, with each HL7 body's control id and first patient identifier. 0 with why on
/// a failed read. Only stock classes while switched.
ClassMethod ReadWindow(ns As %String, item As %String, from As %String, to As %String, Output rows As %DynamicArray, Output why As %String) As %Boolean [ Private ]
{
    Set rows = [], why = "", ok = 0, limit = ..#MAXHEADERS + 1
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ limit _ " ID, Status, TimeCreated, Description, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE TargetConfigName = ? AND TimeCreated >= ? AND TimeCreated <= ? ORDER BY ID", item, from, to)
        If rs.%SQLCODE < 0 Set why = "SQLCODE " _ rs.%SQLCODE _ " " _ rs.%Message Quit
        While rs.%Next() {
            Set h = {"headerId": (rs.%Get("ID")), "status": (rs.%Get("Status")), "timeCreated": (rs.%Get("TimeCreated")), "description": (rs.%Get("Description")), "controlId": "", "patient": {"id": "", "authority": ""}}
            If rs.%Get("MessageBodyClassName") = "EnsLib.HL7.Message" {
                Try {
                    Set m = ##class(EnsLib.HL7.Message).%OpenId(rs.%Get("MessageBodyId"))
                    If $ISOBJECT(m) {
                        Set h.controlId = m.GetValueAt("1:10")
                        For s = 1:1:m.SegCount {
                            Set seg = m.GetSegmentAt(s)
                            If '$ISOBJECT(seg) || (seg.Name '= "PID") Continue
                            Set authority = seg.GetValueAt("3(1).4.1")
                            If authority = "" Set authority = seg.GetValueAt("3(1).4")
                            Set h.patient = {"id": (seg.GetValueAt("3(1).1")), "authority": (authority)}
                            Quit
                        }
                    }
                } Catch inner {
                    // A body that won't open leaves its identifiers empty; the header is still listed.
                }
            }
            Do rows.%Push(h)
        }
        If rs.%SQLCODE < 0 Set why = "SQLCODE " _ rs.%SQLCODE _ " " _ rs.%Message Quit
        Set ok = 1
    } Catch ex {
        Set why = ex.DisplayString(), ok = 0
    }
    Quit ok
}

/// The engine's own Alert rows for the item since the row's mark, inside the window, added to the row's alerts by time and
/// kind. The row type comes from the stock enumeration. It reads the engine only: an alert moves no state.
ClassMethod NewAlerts(outage As Shutter.Store.Outage, fields As %DynamicObject) [ Private ]
{
    Try {
        Set type = ##class(Ens.DataType.LogType).DisplayToLogical("Alert")
    } Catch ex {
        Set type = ""
    }
    If type = "" Quit
    If '..ReadAlerts(outage.Namespace, outage.Item, type, +outage.AlertMark, ..EngineTime(outage.WindowFrom), .rows, .mark) Quit
    If mark = +outage.AlertMark Quit
    Set alerts = outage.GetList("Alerts")
    Set iter = rows.%GetIterator()
    While iter.%GetNext(.i, .row) {
        Do alerts.%Push({"at": (row.at), "kind": (..AlertKind(row.text)), "text": ($EXTRACT(row.text, 1, 300))})
    }
    Set fields.Alerts = alerts, fields.AlertMark = mark
}

/// Alert rows above mark logged since from, whose item is this one or whose words name it in quotes (the engine's monitor
/// raises the queue alerts). At most 100 a poll. Only stock classes while switched.
ClassMethod ReadAlerts(ns As %String, item As %String, type As %String, mark As %Integer, from As %String, Output rows As %DynamicArray, Output newMark As %Integer) As %Boolean [ Private ]
{
    Set rows = [], newMark = mark, ok = 0
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 100 ID, TimeLogged, Text, ConfigName FROM Ens_Util.Log WHERE ID > ? AND Type = ? AND TimeLogged >= ? AND (ConfigName = ? OR Text LIKE ?) ORDER BY ID", mark, type, from, item, "%'" _ item _ "'%")
        If rs.%SQLCODE < 0 Quit
        While rs.%Next() {
            Do rows.%Push({"id": (rs.%Get("ID")), "at": (rs.%Get("TimeLogged")), "text": (rs.%Get("Text"))})
            Set newMark = rs.%Get("ID")
        }
        If rs.%SQLCODE < 0 Quit
        Set ok = 1
    } Catch ex {
        Set ok = 0
    }
    Quit ok
}

/// An alert's kind from its words, pure: the engine's own setting name where it leads the words (QueueWaitAlert,
/// QueueCountAlert), InactivityTimeout, AlertOnError for an error raised as an alert, else alert.
ClassMethod AlertKind(text As %String) As %String
{
    If $MATCH(text, "^(Queue\w*Alert|\w+Alert):.*") Quit $PIECE(text, ":", 1)
    If text [ "InactivityTimeout" Quit "InactivityTimeout"
    If $EXTRACT(text, 1, 6) = "ERROR " Quit "AlertOnError"
    Quit "alert"
}

/// The cases linked to the outage by receiver and time, each judged from its own delivery header: { "linked": [ { "caseId",
/// "state", "headerId", "resolved" } ], "open": [ { "caseId", "reason", "owner" } ] }. A case resolved here took the shared
/// sentence; every other one not finished is listed open with why.
ClassMethod Linked(outage As Shutter.Store.Outage, now As %String) As %DynamicObject
{
    Set out = {"linked": [], "open": []}
    Set owner = ..Owner(outage)
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP " _ ..#MAXCASES _ " ID FROM Shutter_Store.""Case"" WHERE Receiver = ? AND OpenedAt >= ? AND OpenedAt <= ? ORDER BY ID", outage.Receiver, $PIECE(outage.WindowFrom, ".", 1) _ $SELECT(outage.WindowFrom [ ".": "Z", 1: ""), now)
    While rs.%Next() {
        Set case = ##class(Shutter.Store.Case).%OpenId(rs.%Get("ID"))
        If '$ISOBJECT(case) Continue
        Set verdict = ..Judge(case, outage)
        Set link = {"caseId": (case.CaseId), "state": (case.State), "headerId": (verdict.headerId)}
        Do link.%Set("resolved", ''verdict.resolved, "boolean")
        Do out.linked.%Push(link)
        If verdict.finished Continue
        Do out.open.%Push({"caseId": (case.CaseId), "reason": (verdict.reason), "owner": (owner)})
    }
    Quit out
}

/// Who owns what the close leaves open: the receiver's approvers, or the profile's escalation line.
ClassMethod Owner(outage As Shutter.Store.Outage) As %String [ Private ]
{
    Set names = ""
    Try {
        Set list = [].%FromJSON(outage.Approvers)
        Set iter = list.%GetIterator()
        While iter.%GetNext(.i, .n) {
            Set names = names _ $SELECT(names = "": "", 1: ", ") _ n
        }
    } Catch ex {
        Set names = ""
    }
    Quit $SELECT(names = "": "unassigned", 1: names)
}

/// One linked case: read, judged by LinkVerdict, and resolved with the shared sentence only when it says so. { "finished",
/// "resolved", "reason", "headerId" }.
ClassMethod Judge(case As Shutter.Store.Case, outage As Shutter.Store.Outage) As %DynamicObject [ Private ]
{
    Set c = {"state": (case.State), "failureKind": (case.FailureKind), "failureReasonCode": (case.FailureReasonCode), "deliveryHeader": "", "deliveryCustody": "", "deliveryStatus": "", "effectiveAck": "", "words": ""}
    Do c.%Set("identity", ..IdentityException(case), "boolean")
    Set first = ..LinkVerdict(c)
    If first.decided Quit ..Verdict(first, "")
    Set facts = ##class(Shutter.Util.EngineCheck).Read(case)
    Set c.deliveryHeader = facts.deliveryHeader
    If (facts.scope '= "yes") && (facts.scope '= "base") {
        Set c.deliveryCustody = "unreadable", c.why = $SELECT(facts.why '= "": facts.why, 1: "the engine's record of it could not be read")
    } ElseIf facts.headers.%Size() {
        Set h = facts.headers.%Get(0)
        Set c.deliveryCustody = h.custody, c.deliveryStatus = h.status
        If h.custody = "delivered" {
            Set c.effectiveAck = facts.effectiveAck
            Set c.words = ##class(Shutter.Util.EngineWords).DeliveredWords(h.headerId, ..LocalTime(h.completedAt), facts.effectiveAck, facts.ackReason)
        }
    }
    Set verdict = ..LinkVerdict(c)
    If verdict.resolve {
        Set case.Outcome = c.words, case.Headline = $EXTRACT(c.words, 1, 500)
        Set sc = case.Transition("resolved", c.words, ..#ACTOR, "outage:" _ outage.%Id())
        If $$$ISERR(sc) Quit ..Verdict({"finished": 0, "resolved": 0, "reason": ("it could not be resolved: " _ $EXTRACT($SYSTEM.Status.GetErrorText(sc), 1, 200))}, c.deliveryHeader)
        Quit ..Verdict({"finished": 1, "resolved": 1, "reason": ""}, c.deliveryHeader)
    }
    // At not_established the sentence goes on the case once, and the case stays for a person.
    If (c.words '= "") && (case.Outcome '= c.words) {
        Set case.Outcome = c.words
        Do case.Note("note", c.words, ..#ACTOR, "outage:" _ outage.%Id())
        Do case.%Save()
    }
    Quit ..Verdict(verdict, c.deliveryHeader)
}

ClassMethod Verdict(v As %DynamicObject, headerId As %String) As %DynamicObject [ Private ]
{
    Quit {"finished": (''v.finished), "resolved": (''v.resolved), "reason": (v.reason), "headerId": (headerId)}
}

/// Whether the case's newest gate decision named an identity conflict.
ClassMethod IdentityException(case As Shutter.Store.Case) As %Boolean [ Private ]
{
    Set found = 0
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ChecksJSON FROM Shutter_Store.GateDecision WHERE ""Case"" = ? ORDER BY ID DESC", case.%Id())
        If rs.%Next() && (rs.%Get("ChecksJSON") [ "PATIENT_MISMATCH") Set found = 1
    } Catch ex {
        Set found = 0
    }
    Quit found
}

/// A linked case's verdict, pure. c: state, failureKind, failureReasonCode, identity, and once read deliveryHeader,
/// deliveryCustody (EngineRead.Custody's answer for its own delivery header), deliveryStatus, effectiveAck, words. Answers {
/// "decided" (known before the engine is read), "finished", "resolve", "resolved", "reason" }. Membership of the outage is no
/// authority: only an engine delivery failure whose own header reads Completed, with an acknowledgement level established, is
/// resolved.
ClassMethod LinkVerdict(c As %DynamicObject) As %DynamicObject
{
    Set state = c.state
    If (state = "resolved") || (state = "failed") Quit {"decided": 1, "finished": 1, "resolve": 0, "resolved": 0, "reason": ""}
    If $LISTFIND($LISTBUILD("awaiting_approval", "approved", "executing", "verifying"), state) Quit ..Open("a person is reviewing it (" _ state _ ")", 1)
    If '$LISTFIND($LISTBUILD("blocked", "escalated"), state) Quit ..Open("the workflow is still working on it (" _ state _ ")", 1)
    If $EXTRACT(c.failureReasonCode, 1, 4) = "ack_" Quit ..Open("an application acknowledgement failure (" _ c.failureReasonCode _ "): a Completed header does not settle it", 1)
    If c.failureKind = "rejected" Quit ..Open("the receiver refused its content: a Completed header does not settle it", 1)
    If (c.failureKind '= "delivery_failed") && (c.failureKind '= "uncertain_outcome") Quit ..Open("its failure is " _ $SELECT(c.failureKind = "": "of no known kind", 1: c.failureKind) _ ", not a failed delivery: a Completed header does not settle it", 1)
    If c.identity Quit ..Open("an identity exception: a Completed header does not settle it", 1)
    If c.%Get("deliveryCustody") = "" Quit {"decided": 0, "finished": 0, "resolve": 0, "resolved": 0, "reason": ""}
    If c.deliveryCustody '= "delivered" Quit ..Open("its own delivery header" _ $SELECT(c.deliveryHeader '= "": " (" _ c.deliveryHeader _ ")", 1: "") _ " reads " _ $SELECT(c.deliveryStatus '= "": c.deliveryStatus, 1: c.deliveryCustody) _ ", not Completed", 0)
    If (c.effectiveAck = "not_established") || (c.effectiveAck = "") Quit ..Open(c.words, 0)
    Quit {"decided": 0, "finished": 1, "resolve": 1, "resolved": 0, "reason": ""}
}

ClassMethod Open(reason As %String, decided As %Boolean) As %DynamicObject [ Private ]
{
    Quit {"decided": (decided), "finished": 0, "resolve": 0, "resolved": 0, "reason": (reason)}
}

/// Whether a pause has run out, pure: until is an ISO UTC time; one that does not read never runs out by itself.
ClassMethod PauseOver(until As %String, now As %String) As %Boolean
{
    Set gap = ##class(Shutter.Util.Time).MillisBetween(until, now)
    Quit (gap '= "") && (gap >= 0)
}

/// Whether the overdue line comes now, pure: once, minutes after the open, on a row not closed.
ClassMethod Overdue(openedAt As %String, overdueAt As %String, state As %String, now As %String, minutes As %Integer) As %Boolean
{
    If (overdueAt '= "") || (state = "closed") Quit 0
    Set gap = ##class(Shutter.Util.Time).MillisBetween(openedAt, now)
    Quit (gap '= "") && (gap >= (minutes * 60000))
}

/// HH:MM:SS of an ISO UTC time in this instance's local time, for a person's words.
ClassMethod Clock(iso As %String) As %String [ Private ]
{
    Set local = ..LocalTime(..EngineTime(iso))
    Quit $EXTRACT(local, 12, 19)
}

/// The engine's UTC time as this instance's local "yyyy-mm-dd hh:mm:ss"; as given if it won't convert.
ClassMethod LocalTime(utc As %String) As %String [ Private ]
{
    If utc = "" Quit ""
    Try {
        Set local = ##class(%UTC).ConvertUTCtoLocal($EXTRACT(utc, 1, 19))
    } Catch ex {
        Set local = utc
    }
    Quit local
}

}
