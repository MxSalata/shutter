/// The receiver outages as the routes give them (docs/CONTRACTS.md, section 17): the list with the always-on readings, one
/// outage with the card's words, and a person's acts. The words are composed here, on every read, from the stored row, the
/// receiver's last reading, the profile's entry and what this build holds, so they follow the build and never promise a send
/// the build lacks. Nothing here reads a watched namespace: the REST process can't switch to one, and the stored reading is
/// what the Receiver Watch's production job saw.
Class Shutter.API.Outages
{

/// The card's critical line, given as an action at every orders and results receiver.
Parameter CRITICAL = "Shutter does not assess clinical urgency. If delayed reporting may require clinical action, contact the laboratory using the site's critical-results and downtime procedure. Do not re-enter or amend a result solely from this page.";

/// What a card says where nothing can be approved.
Parameter NOSEND = "Shutter will not send these messages. Review them in the Message Viewer using the site's recovery procedure.";

/// The patient check's stated limit, on the card wherever a set of orders or results is listed.
Parameter MERGELIMIT = "The patient check reads merges and identity changes only where they pass through this namespace; one made elsewhere is not seen.";

/// What the approval answers at a receiver whose duplicates are not refused, without the approver's word.
Parameter RECEIVERCHECK = "At this receiver a duplicate is unknown: check the receiver for these messages first, and say so with the approval.";

/// The reason a row gives when the build has no set gate.
Parameter NOSETGATE = "no set gate in this build";

/// The largest body an act may carry, in characters, checked before it is parsed.
Parameter MAXBODY = 8192;

/// After this long open, the card says the site's limit has passed.
Parameter OVERDUEMINUTES = 60;

/// The classes whose presence decides what this build can do: the set gate, the send, the hold and the mail.
Parameter SETGATECLASS = "Shutter.Util.ResendSet";

Parameter SENDCLASS = "Shutter.Operation.EngineResend";

Parameter HOLDCLASS = "Shutter.Store.HoldEntry";

Parameter MAILCLASS = "Shutter.Operation.OutageMail";

/// What this build holds, as the words need it: { "setGate", "send" }.
ClassMethod Build() As %DynamicObject
{
    Set o = {}
    Do o.%Set("setGate", ..Has(..#SETGATECLASS), "boolean")
    Do o.%Set("send", ..Has(..#SENDCLASS), "boolean")
    Quit o
}

ClassMethod Has(class As %String) As %Boolean
{
    Quit ##class(%Dictionary.CompiledClass).%ExistsId(class)
}

/// GET /outages: the rows, newest first, open (not closed) or all, and one reading per watched receiver.
ClassMethod List(state As %String = "open") As %DynamicObject
{
    Set where = $SELECT(state = "all": "", 1: " WHERE State <> 'closed'")
    Set items = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Outage" _ where _ " ORDER BY ID DESC")
    While rs.%Next() {
        Set row = ##class(Shutter.Store.Outage).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(row)
        Do items.%Push(..One(row))
    }
    Quit {"items": (items), "receivers": (##class(Shutter.Store.ReceiverReading).All())}
}

/// One outage as the routes give it: the store's JSON, with the card's words and the acts composed for this build and the
/// receiver's profile entry.
ClassMethod One(row As Shutter.Store.Outage, now As %String = "") As %DynamicObject
{
    Set o = row.ToJSON()
    Set entry = ##class(Shutter.Store.SiteProfile).Receiver(row.Receiver)
    Do ..ComposeActs(o, entry)
    Set recovered = ..RecoveredAt(row.%Id())
    Set o.words = ..Words(o, entry, ..Build(), now, recovered)
    Quit o
}

/// Whether "already handled by hand" is offered at this receiver: its duplicates.behaviour is unknown or files_twice, or
/// it declares none. Where a receiver refuses duplicates its own answer closes a message it holds.
ClassMethod ByHand(entry As %DynamicObject) As %Boolean
{
    Set d = $SELECT($ISOBJECT(entry): entry.%Get("duplicates"), 1: "")
    Quit $SELECT($ISOBJECT(d): ..S(d, "behaviour"), 1: "") '= "refuses"
}

/// The acts composed on read, as the words are (v1.53): while the row is offered at a receiver where ByHand holds, each Row
/// of lists.offered carries acts ["handled_by_hand"] and the outage's acts gain it; every other Row carries [].
ClassMethod ComposeActs(o As %DynamicObject, entry As %DynamicObject)
{
    Set byHand = (..S(o, "state") = "offered") && ..ByHand(entry)
    Set lists = o.%Get("lists")
    If $ISOBJECT(lists) {
        Set li = lists.%GetIterator()
        While li.%GetNext(.name, .list) {
            Continue:'$ISOBJECT(list)
            Set ri = list.%GetIterator()
            While ri.%GetNext(, .r) {
                Continue:'$ISOBJECT(r)
                Set r.acts = $SELECT(byHand && (name = "offered"): ["handled_by_hand"], 1: [])
                For key = "closure", "closedBy", "closedAt" { Do:'r.%IsDefined(key) r.%Set(key, "", "null") }
            }
        }
    }
    If byHand && $ISOBJECT(o.%Get("acts")) Do o.acts.%Push("handled_by_hand")
}

/// When the engine's connection came back, from the outage's own events: the first move to draining, or "".
ClassMethod RecoveredAt(id As %String) As %String
{
    If id = "" Quit ""
    Set at = ""
    Set events = ##class(Shutter.Store.OutageEvent).Of(id)
    Set iter = events.%GetIterator()
    While iter.%GetNext(.i, .e) {
        If (e.kind = "draining") || ((e.kind = "state") && (e.detail [ "draining")) Set at = e.at Quit
    }
    Quit at
}

/// The card's words { first, do, call, critical }, from the outage's JSON o, the receiver's profile entry, the build (Build())
/// and, for a test, the time now and when the connection recovered. Pure: it reads nothing else.
ClassMethod Words(o As %DynamicObject, entry As %DynamicObject = "", build As %DynamicObject = "", now As %String = "", recovered As %String = "") As %DynamicObject
{
    If now = "" Set now = ##class(Shutter.Util.Time).NowUTC()
    If '$ISOBJECT(build) Set build = {"setGate": false, "send": false}
    Set reading = o.%Get("readings")
    If '$ISOBJECT(reading) Set reading = {}
    Set state = ..S(o, "state"), kind = ..S(o, "kind"), retry = ..S(reading, "retry")
    If retry = "" Set retry = "unknown"
    Set approvable = (o.%GetTypeOf("approvable") = "boolean") && o.approvable
    Set queue = ..S(reading, "queue"), head = ..S(reading, "headHeaderId")
    Set category = $SELECT($ISOBJECT(entry): ..S(entry, "category"), 1: "")

    // first: what is happening, then what the engine and Shutter do about it.
    If state = "closed" {
        Set first = ..ClosedWords(o, retry, recovered)
    } ElseIf $LISTFIND($LISTBUILD("draining", "closing", "offered", "sending"), state) || (..S(o, "drainedAt") '= "") {
        Set first = ..ReturnWords(o, state, retry, recovered, queue)
    } Else {
        Set first = ..KindWords(o, kind, reading, retry, approvable, build, queue, head, now)
    }
    If (state = "needs_person") && (..SetReason(o) '= "") && (..SetReason(o) '= ..#NOSETGATE) Set first = first _ " A person must act here: " _ ..SetReason(o) _ "."
    If state = "needs_person" {
        Set halted = ..HaltLine(o)
        If halted '= "" Set first = halted _ " " _ first
    }
    If (..S(reading, "replyCodeActions") '= "") && (reading.%GetTypeOf("replyCodeActionsStock") = "boolean") && 'reading.replyCodeActionsStock {
        Set first = first _ " This operation's reply actions are the site's own: what an AE, AR or timeout does here follows this string: " _ reading.replyCodeActions _ "."
    }
    If (category = "orders_results") && (state = "offered") && $ISOBJECT(o.%Get("lists")) && (o.lists.offered.%Size() > 0) {
        Set older = 0
        Set oi = o.lists.offered.%GetIterator()
        While oi.%GetNext(, .r) { Set:..S(r, "reason")[##class(Shutter.Util.ResendSet).#OLDER older = older + 1 }
        If older Set first = first _ " " _ older _ " of these " _ $SELECT(older = 1: "is", 1: "are") _ " older than results of other orders for the same patients that already reached the receiver; each files under its own order."
        Set first = first _ " " _ ..#MERGELIMIT
    }
    Set first = first _ " " _ ..RecoveryLine(o, state, retry, queue, head)

    // do: the site's runbook line, or what a person decides; swapped while down on purpose.
    Set runbook = $SELECT($ISOBJECT(entry): ..S(entry, "runbook"), 1: ..S(o, "runbook"))
    If runbook = "" Set runbook = ..S(o, "runbook")
    If state = "paused" {
        Set do = "Down on purpose until " _ ..S(o, "pausedUntil") _ ": Shutter offers nothing for this receiver until then, and the engine goes on doing what its settings say."
    } ElseIf state = "closed" {
        Set do = $SELECT(o.openCases.%Size() > 0: "Do: review the delivery exceptions listed below with their owners.", 1: "Do: nothing more for this outage.")
    } ElseIf kind = "refusing" {
        Set do = "Do: a person decides in the Message Viewer; Shutter does not suspend or discard." _ $SELECT(runbook '= "": " The site's line: " _ ..Stop(runbook), 1: "")
    } Else {
        Set do = "Do: " _ $SELECT(runbook '= "": ..Stop(runbook), 1: "the site has not written what to do for this receiver.")
    }
    If (state = "offered") && (o.lists.offered.%Size() > 0) && ..ByHand(entry) {
        Set behaviour = $SELECT($ISOBJECT(entry) && $ISOBJECT(entry.%Get("duplicates")): ..S(entry.duplicates, "behaviour"), 1: "")
        Set do = do _ " At this receiver a duplicate is " _ $SELECT(behaviour = "files_twice": "filed twice", 1: "unknown") _ ": before approving, check the receiver for each message. For one already entered by hand, choose Already handled by hand; Shutter then sends nothing for it."
    }
    If (state '= "closed") && (state '= "paused") {
        If $LISTFIND($LISTBUILD("unlimited", "bounded"), retry) Set do = do _ " " _ ..DuplicateLine(entry)
        If ..Overdue(o, now) Set do = do _ " Down longer than the site's limit: the lab's downtime procedure applies."
    }

    // call: the site's line, and who may approve.
    Set call = $SELECT($ISOBJECT(entry): ..S(entry, "call"), 1: "")
    If call = "" Set call = ..S(o, "call")
    Set call = "Call: " _ $SELECT(call '= "": ..Stop(call), 1: "the site has not named who to call for this receiver.")
    Set names = ""
    If $ISOBJECT(o.%Get("approvers")) {
        Set ai = o.approvers.%GetIterator()
        While ai.%GetNext(.i, .n) { Set names = names _ $SELECT(names = "": "", 1: ", ") _ n }
    }
    Set call = call _ " " _ $SELECT(names '= "": "Who may approve here: " _ names _ ".", 1: "No approver is named for this receiver.") _ " An operator can do nothing here, which is safe."

    Set words = {"first": (first), "do": (do), "call": (call)}
    If category = "orders_results" {
        Set words.critical = ..#CRITICAL
    } Else {
        Do words.%Set("critical", "", "null")
    }
    Quit words
}

/// Where the recovery control halted the latest run (CONTRACTS 18), what it came to and how it goes on, from o.resends; ""
/// when nothing halted it.
ClassMethod HaltLine(o As %DynamicObject) As %String
{
    Set rows = o.%Get("resends")
    Quit:'$ISOBJECT(rows) ""
    Set run = ""
    Set iter = rows.%GetIterator()
    While iter.%GetNext(, .r) { Set:$EXTRACT(..S(r, "runId"))="R" run = ..S(r, "runId") }
    Quit:run="" ""
    Set code = "", total = 0, sent = 0, halted = 0
    Set iter = rows.%GetIterator()
    While iter.%GetNext(, .r) {
        Continue:..S(r, "runId")'=run
        Set total = total + 1
        Set:..S(r, "closure")="sent" sent = sent + 1
        If ..S(r, "halt") '= "" Set halted = halted + 1 Set:code="" code = ..S(r, "halt")
    }
    Quit:'halted ""
    Set why = $CASE(code, "recovery_stopped": "Shutter recovery was stopped", "recovery_shadow": "the site is in shadow mode, with recovery off", : "the recovery control could not be read")
    Set after = $CASE(code, "recovery_stopped": "once an approver has cleared the stop in Settings", "recovery_shadow": "once the site enables recovery in its site profile", : "")
    Set text = "The resend halted because " _ why _ ": " _ sent _ " of " _ total _ " message" _ $SELECT(total = 1: " was", 1: "s were") _ " sent and " _ halted _ " not sent."
    Quit text _ " The rest go only by a new approval" _ $SELECT(after '= "": " " _ after, 1: "") _ ": read the set again, then approve it."
}

/// The first line while the outage is open, by the kind the engine shows.
ClassMethod KindWords(o As %DynamicObject, kind As %String, reading As %DynamicObject, retry As %String, approvable As %Boolean, build As %DynamicObject, queue As %String, head As %String, now As %String) As %String
{
    Set failed = ..Failed(o)
    If kind = "refusing" {
        Quit "The receiver is up, and nothing is getting through: it refused " _ $SELECT(head '= "": "message header " _ head, 1: "the message at the head of the queue") _ ", and the engine is trying it again." _ ..Queued(queue) _ " Shutter resends nothing."
    }
    If kind = "not_answering" {
        Quit "The listener accepts connections and is not answering. " _ $SELECT(head '= "": "Message header " _ head, 1: "The message at the head of the queue") _ " has been written to it at least once and may already be held there." _ ..Queued(queue) _ " Shutter resends nothing."
    }
    If kind = "down" {
        Set since = ..Clock(..S(o, "openedAt"))
        Set text = "The listener has been unreachable" _ $SELECT(since '= "": " since " _ since _ " (" _ ..Minutes(..S(o, "openedAt"), now) _ " min)", 1: "") _ "." _ ..Queued(queue)
        Quit text _ " " _ ..RetryWords(reading, retry, approvable, build, failed, 0)
    }
    // cant_tell, or a row whose kind is not set yet.
    Set text = "Whether the listener is back cannot be read from the engine at this receiver: it will show on the next send."
    Set listed = o.lists.offered.%Size()
    If listed > 0 Set text = text _ " The engine's retained log shows no connection opened for " _ listed _ " message" _ $SELECT(listed = 1: "", 1: "s") _ " (listed below)."
    Quit text _ ..Queued(queue) _ " " _ ..RetryWords(reading, retry, approvable, build, failed, 1)
}

/// What the engine does with what has failed or is queued, from the setting as read, then by tier where it doesn't retry.
ClassMethod RetryWords(reading As %DynamicObject, retry As %String, approvable As %Boolean, build As %DynamicObject, failed As %String, cantTell As %Boolean) As %String
{
    Set timeout = ..S(reading, "failureTimeout")
    Set source = ""
    If $ISOBJECT(reading.%Get("settingSources")) Set source = ..S(reading.settingSources, "FailureTimeout")
    Set where = $SELECT(source = "class_default": "the stock operation's default", 1: "read off the item")
    If retry = "unlimited" {
        Quit "At this operation the engine retries without limit (FailureTimeout -1, " _ where _ "): it goes on attempting them, in order, when the listener is back; a refusal, a stopped production or a changed setting can still stop one."
    }
    If retry = "none" {
        Set text = "The engine does not retry here (FailureTimeout 0, " _ where _ "): "
    } ElseIf retry = "bounded" {
        Set text = "The engine retries here for at most " _ timeout _ " s, then gives up (FailureTimeout " _ timeout _ ", " _ where _ "): "
    } Else {
        Set text = "Whether this operation retries could not be read: treat them as not going by themselves until a person checks the item. "
    }
    If retry '= "unknown" Set text = text _ $SELECT(failed '= "": failed _ " message" _ $SELECT(failed = 1: " has", 1: "s have") _ " failed and will not go by themselves.", 1: "messages that fail here will not go by themselves.") _ " "
    If approvable {
        If cantTell Quit text _ "Shutter checks each again before it goes and stops at the first that fails."
        Quit text _ "Shutter lists them for one approval as soon as the engine shows them settled; whether the listener is back cannot be read from the engine here, so the first send tells, and Shutter stops at the first that fails."
    }
    Set text = text _ ..#NOSEND
    If '((build.%GetTypeOf("setGate") = "boolean") && build.setGate) {
        Set text = text _ " " _ $SELECT(failed '= "": failed _ " message" _ $SELECT(failed = 1: "", 1: "s") _ " failed and " _ $SELECT(failed = 1: "was", 1: "were") _ " not offered", 1: "The messages that failed were not offered") _ "; a person reads the trace."
    }
    Quit text
}

/// The words once the engine has the connection back: recovered, drained, and how the messages settled.
ClassMethod ReturnWords(o As %DynamicObject, state As %String, retry As %String, recovered As %String, queue As %String) As %String
{
    Set text = ""
    // Only where the adapter read connected: on the no-retry path nothing shows the listener's state.
    If (retry = "unlimited") && (..Clock(recovered) '= "") Set text = "The engine's connection recovered at " _ ..Clock(recovered) _ "."
    Set drained = ..Clock(..S(o, "drainedAt"))
    If drained '= "" {
        Set text = text _ $SELECT(text = "": "", 1: " ") _ "Delivery backlog drained at " _ drained _ "."
    } ElseIf state = "draining" {
        Set text = text _ $SELECT(text = "": "", 1: " ") _ "The engine is delivering the backlog." _ ..Queued(queue)
    }
    Set text = text _ $SELECT(text = "": "", 1: " ") _ "Application processing has not been independently checked."
    If (drained '= "") || (state '= "draining") Set text = text _ " " _ ..Settled(o)
    Quit text
}

/// The words of a closed outage: never green over open work.
ClassMethod ClosedWords(o As %DynamicObject, retry As %String, recovered As %String) As %String
{
    Set n = o.openCases.%Size()
    Set text = "Transport outage closed." _ $SELECT(n > 0: " " _ n _ " delivery exception" _ $SELECT(n = 1: " still needs", 1: "s still need") _ " review.", 1: "")
    If (retry = "unlimited") && (..Clock(recovered) '= "") Set text = text _ " The engine's connection recovered at " _ ..Clock(recovered) _ "."
    If ..Clock(..S(o, "drainedAt")) '= "" Set text = text _ " Delivery backlog drained at " _ ..Clock(..S(o, "drainedAt")) _ ". Application processing has not been independently checked. " _ ..Settled(o)
    Quit text
}

/// "Nothing remains queued. N deliveries Completed; M was Suspended and still needs action."
ClassMethod Settled(o As %DynamicObject) As %String
{
    Set s = o.%Get("settled")
    If '$ISOBJECT(s) Quit "Nothing remains queued."
    Set c = +s.completed, u = +s.suspended, e = +s.error
    Set text = "Nothing remains queued. " _ c _ " deliver" _ $SELECT(c = 1: "y", 1: "ies") _ " Completed"
    If u > 0 Set text = text _ "; " _ u _ $SELECT(u = 1: " was", 1: " were") _ " Suspended and still need" _ $SELECT(u = 1: "s", 1: "") _ " action"
    If e > 0 Set text = text _ "; " _ e _ " ended in Error and still need" _ $SELECT(e = 1: "s", 1: "") _ " action"
    Quit text _ "."
}

/// "Recovery attempts initiated by Shutter: 0.", and while anything is queued or being tried, that the engine may be at it.
ClassMethod RecoveryLine(o As %DynamicObject, state As %String, retry As %String, queue As %String, head As %String) As %String
{
    Set text = "Recovery attempts initiated by Shutter: " _ (+o.%Get("sentByShutter")) _ "."
    Set trying = (+queue > 0) || (head '= "")
    If trying Set text = text _ " The integration engine may still be delivering or retrying."
    Quit text _ " Nothing is sent to the receiver to check this."
}

/// The duplicate line, from the profile's duplicates: what a duplicate does at this receiver, refused with its words, filed twice or unknown.
ClassMethod DuplicateLine(entry As %DynamicObject) As %String
{
    Set d = $SELECT($ISOBJECT(entry): entry.%Get("duplicates"), 1: "")
    Set behaviour = $SELECT($ISOBJECT(d): ..S(d, "behaviour"), 1: "")
    Set text = "Entering one by hand first is your downtime procedure's call; at this receiver a duplicate is "
    If behaviour = "refuses" {
        Set said = ..S(d, "phrase")
        If said = "" Set said = ..S(d, "code")
        Quit text _ "refused, with its words """ _ said _ """."
    }
    If behaviour = "files_twice" Quit text _ "filed twice."
    Quit text _ "unknown."
}

/// The number of failed messages the row knows of, or "" when it knows none yet.
ClassMethod Failed(o As %DynamicObject) As %String
{
    Set n = 0
    If $ISOBJECT(o.%Get("settled")) Set n = +o.settled.error + o.settled.suspended
    If (n = 0) && $ISOBJECT(o.%Get("lists")) Set n = o.lists.offered.%Size() + o.lists.reached.%Size() + o.lists.refused.%Size()
    Quit $SELECT(n > 0: n, 1: "")
}

/// The site's line as written, with a full stop after it when it ends in none, so the next sentence reads apart from it.
ClassMethod Stop(text As %String) As %String
{
    Set text = $ZSTRIP(text, ">W")
    If (text = "") || (".!?" [ $EXTRACT(text, *)) Quit text
    Quit text _ "."
}

ClassMethod Queued(queue As %String) As %String
{
    If (queue = "") || (+queue = 0) Quit ""
    Quit " " _ (+queue) _ " message" _ $SELECT(+queue = 1: " is", 1: "s are") _ " queued."
}

/// Whether an open outage has passed the site's limit.
ClassMethod Overdue(o As %DynamicObject, now As %String) As %Boolean
{
    Set state = ..S(o, "state")
    If '$LISTFIND($LISTBUILD("open", "needs_person"), state) Quit 0
    Set at = ..S(o, "overdueAt")
    If at '= "" Quit ##class(Shutter.Util.Time).MillisBetween(at, now) >= 0
    Set millis = ##class(Shutter.Util.Time).MillisBetween(..S(o, "openedAt"), now)
    Quit (millis '= "") && (millis >= (..#OVERDUEMINUTES * 60000))
}

ClassMethod Minutes(from As %String, now As %String) As %Integer
{
    Set millis = ##class(Shutter.Util.Time).MillisBetween(from, now)
    Quit $SELECT(millis = "": 0, 1: millis \ 60000)
}

/// The first HH:MM in a time as given, or "".
ClassMethod Clock(time As %String) As %String
{
    Set clock = ""
    Set found = $LOCATE(time, "(?<!\d)\d\d:\d\d", 1, , clock)
    Quit clock
}

ClassMethod SetReason(o As %DynamicObject) As %String
{
    Set set = o.%Get("set")
    Quit $SELECT($ISOBJECT(set): ..S(set, "reason"), 1: "")
}

/// A string member, "" when absent or null.
ClassMethod S(obj As %DynamicObject, key As %String) As %String
{
    If '$ISOBJECT(obj) Quit ""
    If obj.%GetTypeOf(key) = "null" Quit ""
    If obj.%GetTypeOf(key) = "unassigned" Quit ""
    Quit obj.%Get(key)
}

/// A person's one approval of an offered set (tier C): answers the HTTP status, and in reply the outage as the routes give
/// it or the error. by is the signed-in user. The approval names the set's digest and the row's version, carries a note,
/// stands APPROVALMINUTES before the first send, and copies the set into the ledger as the run's rows (Shutter.Store.ResendRecord,
/// state approved), one run per outage; Engine Resend sends them. A replayed Idempotency-Key answers the first reply. While
/// Shutter recovery is stopped or the site is in shadow mode it is refused (409 recovery_stopped or recovery_shadow) and
/// records nothing.
ClassMethod Approve(row As Shutter.Store.Outage, body As %DynamicObject, by As %String, Output reply As %DynamicObject) As %String
{
    Set reply = ""
    If row.State '= "offered" Set reply = {"error": "wrong_state", "detail": ("Outage " _ row.%Id() _ " reads " _ row.State _ ": only an offered set can be approved")} Quit "409 Conflict"
    If 'row.Approvable Set reply = {"error": "not_approvable", "detail": "This receiver's profile entry does not say engine_resend, or this build has no sender: Shutter will not send these messages"} Quit "409 Conflict"
    If row.SetStatus '= "computed" Set reply = {"error": "wrong_state", "detail": ("The set is " _ row.SetStatus _ ": read it again")} Quit "409 Conflict"
    Set digest = ..S(body, "digest"), note = $ZSTRIP(..S(body, "note"), "<>W")
    If digest = "" Set reply = {"error": "bad_request", "detail": "An approval names the set's digest"} Quit "400 Bad Request"
    If note = "" Set reply = {"error": "bad_request", "detail": "An approval needs a note: what was checked, and with whom"} Quit "400 Bad Request"
    If $LENGTH(note) > 1000 Set reply = {"error": "bad_request", "detail": "note is longer than 1000 characters"} Quit "400 Bad Request"
    If body.%IsDefined("version") && (+body.%Get("version") '= +row.Version) Set reply = {"error": "version_changed", "detail": "The outage has moved on: read it again", "currentVersion": (+row.Version)} Quit "409 Conflict"
    If digest '= row.SetDigest Set reply = {"error": "set_changed", "detail": "The set has changed since it was read: read it again and approve what it lists now", "currentDigest": (row.SetDigest)} Quit "409 Conflict"
    // Shadow mode and the recovery stop (CONTRACTS 18): asked once the row, its version and its digest hold, so a refused
    // approval puts nothing on the record and the set stays offered.
    Set refusal = ##class(Shutter.Util.RecoveryControl).OutageApprovalRefusal(.code)
    If code '= "" Set reply = {"error": (code), "detail": (refusal)} Quit "409 Conflict"
    // Ask first (v1.53): only where a receiver refuses duplicates is a resend safe with no check.
    If ..ByHand(##class(Shutter.Store.SiteProfile).Receiver(row.Receiver)) && '((body.%GetTypeOf("receiverChecked") = "boolean") && body.receiverChecked) Set reply = {"error": "receiver_check_needed", "detail": (..#RECEIVERCHECK)} Quit "409 Conflict"
    Set offered = row.GetList("ListOffered")
    If offered.%Size() = 0 Set reply = {"error": "wrong_state", "detail": "The set lists nothing to send"} Quit "409 Conflict"
    Set now = ##class(Shutter.Util.Time).NowUTC(), runId = "R" _ row.%Id() _ "-" _ (+row.Version)
    Set approval = {"id": (runId), "by": (by), "givenAt": (now), "goodUntil": (##class(Shutter.Util.Time).PlusMillis(now, ..#APPROVALMINUTES * 60000)), "digest": (digest), "note": (note)}
    // The run's rows first, in the set's order: if the move below is refused, they are taken away again.
    Set made = "", sc = $$$OK
    Set iter = offered.%GetIterator()
    While iter.%GetNext(.i, .r) {
        Set rec = ##class(Shutter.Store.ResendRecord).%New()
        Set rec.RunId = runId, rec.Position = i + 1, rec.OutageId = row.%Id(), rec.Namespace = row.Namespace, rec.Item = row.Item
        Set rec.OriginHeaderId = r.headerId, rec.ControlId = ..S(r, "controlId"), rec.State = "approved", rec.SetDigest = digest, rec.ApprovalId = runId, rec.ApprovedBy = by
        Set cases = ##class(Shutter.Util.ResendSet).CasesOf(row.Namespace, [(r)])
        Set:cases'="" rec.CaseId = $LIST(cases, 1)
        Set sc = rec.%Save()
        If $$$ISERR(sc) Quit
        Set made = made _ $LISTBUILD(rec.%Id())
    }
    If $$$ISOK(sc) Set sc = row.Advance("sending", "approved by " _ by _ ": " _ offered.%Size() _ " message" _ $SELECT(offered.%Size() = 1: "", 1: "s") _ " to send in order. " _ note, by, {"Approval": (approval.%ToJSON())}, "approved", .moved)
    If $$$ISERR(sc) || 'moved {
        For j = 1:1:$LISTLENGTH(made) { Do ##class(Shutter.Store.ResendRecord).%DeleteId($LIST(made, j)) }
        Set reply = {"error": "version_changed", "detail": ("The outage moved on while it was approved: read it again" _ $SELECT($$$ISERR(sc): " (" _ $SYSTEM.Status.GetErrorText(sc) _ ")", 1: ""))}
        Quit "409 Conflict"
    }
    Set reply = ..One(row)
    Quit "200 OK"
}

/// How long an approval stands before its first send, in minutes.
Parameter APPROVALMINUTES = 15;

/// "Already handled by hand" (v1.53, CONTRACTS 17.8): a person says one offered message was entered at the receiver by hand,
/// so Shutter sends nothing for it. The header must be a Row of lists.offered whose acts list the act, and the note says what
/// was checked. A ledger row handled_by_hand is written first; then, under the row's lock and version, the Row moves from
/// offered to closed, the digest is computed over what stays offered, the version moves on, an event names the person and
/// the control id and the row is marked to read again; if that move is refused the ledger row is taken away again. Then the
/// message's own cases are closed by hand with the same words. Nothing is sent.
ClassMethod HandledByHand(row As Shutter.Store.Outage, body As %DynamicObject, by As %String, Output reply As %DynamicObject) As %String
{
    Set reply = ""
    Set headerId = ..S(body, "headerId"), note = $ZSTRIP(..S(body, "note"), "<>W")
    Set o = ..One(row), offered = o.lists.offered, found = "", keep = []
    Set iter = offered.%GetIterator()
    While iter.%GetNext(, .r) {
        If (headerId '= "") && (..S(r, "headerId") = headerId) { Set found = r } Else { Do keep.%Push(r) }
    }
    If '$ISOBJECT(found) Set reply = {"error": "bad_request", "detail": ("headerId must be a message the set offers: " _ $SELECT(headerId '= "": "header " _ headerId _ " is not offered", 1: "none was given"))} Quit "400 Bad Request"
    Set listed = 0
    Set ai = found.acts.%GetIterator()
    While ai.%GetNext(, .a) { Set:a="handled_by_hand" listed = 1 }
    If 'listed Set reply = {"error": "bad_request", "detail": ("Header " _ headerId _ " does not list handled_by_hand: this receiver refuses duplicates, and its own answer closes a message it holds")} Quit "400 Bad Request"
    If note = "" Set reply = {"error": "bad_request", "detail": "A note is needed: what was checked at the receiver, and with whom"} Quit "400 Bad Request"
    If $LENGTH(note) > 1000 Set reply = {"error": "bad_request", "detail": "note is longer than 1000 characters"} Quit "400 Bad Request"
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set words = $EXTRACT("Handled by hand, recorded by " _ by _ " at " _ ..Clock(now) _ ": " _ note _ ". Shutter sent nothing for it.", 1, 1000)
    Set rec = ##class(Shutter.Store.ResendRecord).%New()
    Set rec.RunId = "H" _ row.%Id(), rec.Position = 0, rec.OutageId = row.%Id(), rec.Namespace = row.Namespace, rec.Item = row.Item
    Set rec.OriginHeaderId = headerId, rec.ControlId = ..S(found, "controlId"), rec.State = "handled_by_hand", rec.RecordedBy = by
    Set rec.EndedAt = now, rec.Words = words
    Set cases = ##class(Shutter.Util.ResendSet).CasesOf(row.Namespace, [(found)])
    Set:cases'="" rec.CaseId = $LIST(cases, 1)
    Set sc = rec.%Save()
    If $$$ISERR(sc) Set reply = {"error": "wrong_state", "detail": ("The record could not be written: " _ $SYSTEM.Status.GetErrorText(sc))} Quit "409 Conflict"
    Set closedRow = {}.%FromJSON(found.%ToJSON())
    Set closedRow.reason = words, closedRow.closure = "handled_by_hand", closedRow.closedBy = by, closedRow.closedAt = now, closedRow.acts = []
    Set closed = row.GetList("ListClosed")
    Do closed.%Push(closedRow)
    // The stored lists carry no acts: they are composed on read.
    Set stored = []
    Set ki = keep.%GetIterator()
    While ki.%GetNext(, .k) {
        Set copy = {}.%FromJSON(k.%ToJSON())
        Do copy.%Remove("acts")
        Do stored.%Push(copy)
    }
    Do closedRow.%Remove("acts")
    Set fields = {"ListOffered": (stored), "ListClosed": (closed), "SetDigest": (##class(Shutter.Util.ResendSet).Digest(stored)), "Version": (row.Version + 1), "ReadAgainAt": (now)}
    Set sc = row.Advance(row.State, "handled by hand: " _ $SELECT(found.controlId '= "": "control id " _ found.controlId _ ", ", 1: "") _ "header " _ headerId _ ", recorded by " _ by _ ": " _ note, by, fields, "handled_by_hand", .moved)
    If $$$ISERR(sc) || 'moved {
        Do ##class(Shutter.Store.ResendRecord).%DeleteId(rec.%Id())
        Set reply = {"error": "version_changed", "detail": "The outage moved on while it was read: read it again", "currentVersion": (+row.Version)}
        Quit "409 Conflict"
    }
    Do ..CloseCasesByHand(row.Namespace, headerId, words, by)
    Set reply = ..One(row)
    Quit "200 OK"
}

/// The message's own cases (its origin's, by ResendSet.CaseRows) closed by hand with words, as POST /cases/{id}/close does:
/// through the Case Workflow item when the production runs, so an open approval task is cancelled; else directly.
ClassMethod CloseCasesByHand(ns As %String, headerId As %String, words As %String, by As %String)
{
    Set rows = ##class(Shutter.Util.ResendSet).CaseRows(ns, headerId)
    Set iter = rows.%GetIterator()
    While iter.%GetNext(, .one) {
        Continue:one.state="resolved"
        Set service = ""
        Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .service)
        If $$$ISOK(sc) && $ISOBJECT(service) {
            Set msg = ##class(Shutter.Msg.CaseClose).%New()
            Set msg.CaseId = one.caseId, msg.Reason = words, msg.Actor = by
            Set service.Target = "Case Workflow", service.Async = 1
            Set sc = service.ProcessInput(msg)
            Continue:$$$ISOK(sc)
        }
        Set case = ##class(Shutter.Store.Case).%OpenId(one.id)
        Continue:'$ISOBJECT(case)
        Set sc = ##class(Shutter.Store.Case).CloseByHand(case, words, by)
        If $$$ISERR(sc) Do case.Note("note", words _ " (the case stays " _ case.State _ ": " _ $SYSTEM.Status.GetErrorText(sc) _ ")", by)
    }
}

/// A person's act on an outage: pause until a time, or close with a reason. Answers the HTTP status, and in reply the outage
/// as the routes give it or the error object. by is the signed-in user, never a name from the body.
/// acts, when given, stands in for the row's own list (a later build's row may list an act this method doesn't handle).
ClassMethod Act(row As Shutter.Store.Outage, body As %DynamicObject, by As %String, Output reply As %DynamicObject, acts As %DynamicArray = "") As %String
{
    Set reply = ""
    Set act = ..S(body, "act")
    If (act = "handled_by_hand") && (row.State '= "offered") && (row.State '= "closed") Set reply = {"error": "wrong_state", "detail": ("Outage " _ row.%Id() _ " reads " _ row.State _ ": a message is closed by hand only while the set is offered")} Quit "409 Conflict"
    If '$ISOBJECT(acts) Set acts = ..One(row).acts
    Set allowed = ""
    Set ai = acts.%GetIterator()
    While ai.%GetNext(.i, .a) { Set allowed = allowed _ $SELECT(allowed = "": "", 1: ", ") _ a }
    If row.State = "closed" Set reply = {"error": "wrong_state", "detail": ("Outage " _ row.%Id() _ " is closed")} Quit "409 Conflict"
    If (act = "") || '$LISTFIND($LISTFROMSTRING($REPLACE(allowed, ", ", ",")), act) {
        Set reply = {"error": "bad_request", "detail": ("act must be one of " _ allowed)}
        Quit "400 Bad Request"
    }
    If body.%IsDefined("version") && (+body.%Get("version") '= +row.Version) {
        Set reply = {"error": "version_changed", "detail": "The outage has moved on: read it again", "currentVersion": (+row.Version)}
        Quit "409 Conflict"
    }
    If act = "pause" {
        Set until = ..S(body, "until")
        If '$MATCH(until, "\d{4}-\d\d-\d\dT\d\d:\d\d(:\d\d(\.\d+)?)?Z") Set reply = {"error": "bad_request", "detail": "until must be a UTC time such as 2026-11-08T06:00:00Z"} Quit "400 Bad Request"
        Set ahead = ##class(Shutter.Util.Time).MillisBetween(##class(Shutter.Util.Time).NowUTC(), until)
        If (ahead = "") || (ahead <= 0) Set reply = {"error": "bad_request", "detail": "until must be in the future"} Quit "400 Bad Request"
        Set sc = row.Pause(until, by)
    } ElseIf act = "close" {
        Set reason = ..S(body, "reason")
        If $ZSTRIP(reason, "<>W") = "" Set reply = {"error": "bad_request", "detail": "A close needs a reason"} Quit "400 Bad Request"
        If $LENGTH(reason) > 1000 Set reply = {"error": "bad_request", "detail": "reason is longer than 1000 characters"} Quit "400 Bad Request"
        Set sc = row.Close(reason, by)
    } ElseIf act = "handled_by_hand" {
        Quit ..HandledByHand(row, body, by, .reply)
    } ElseIf act = "read_again" {
        // The REST process never switches to the watched namespace: the row is marked, and the next poll of Receiver Watch
        // (every 5 s), a production job, computes the set again there.
        Set sc = row.ReadAgain(by)
    } Else {
        Set reply = {"error": "bad_request", "detail": ("The act " _ act _ " is not handled in this build")}
        Quit "400 Bad Request"
    }
    If $$$ISERR(sc) {
        Set reply = {"error": "wrong_state", "detail": ($SYSTEM.Status.GetErrorText(sc))}
        Quit "409 Conflict"
    }
    Set reply = ..One(row)
    Quit "200 OK"
}

}
