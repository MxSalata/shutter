/// Tier C's sender: an outage whose set a person approved (state sending) has its messages sent again through the engine,
/// one at a time, in the approved order, from this production job. The approval route only records the approval and the
/// run's rows in the ledger (Shutter.Store.ResendRecord); the REST process never switches to the watched namespace.
///
/// For each message: every rule of the set is read again (the item's state and FailureTimeout, the message's status, its
/// attempts, its copies, the log reaching back, the patient check); the ledger row is written as sending before the call;
/// the stock Ens.MessageHeader.ResendDuplicatedMessage sends the stored body unchanged; the new header is read until it
/// settles, within the item's FailureTimeout and ConnectTimeout and PADSECONDS. Completed: the row is completed and the
/// message's case resolved with what happened. Anything else stops the run, with an event of kind resend on the message's
/// case, except a refusal the receiver's profile declares as its duplicate answer, which closes that message as already
/// held and resolves its own cases as already delivered. A patient the check holds is skipped and
/// the rest go; a copy resent by someone else stops the run. A row found sending (a restart mid-run) goes to a person with
/// nothing more sent. The operation's DefCharEncoding, IPAddress and Port are read before the first send and bound to the
/// approval: a change stops the run. Last before each send, under the recovery control's lock until the engine has the
/// message, the stop and shadow mode are read (CONTRACTS 18): either halts the run, and the rest are not sent.
///
/// Built on its own branch: the design keeps an automated resend off the release until a proof shows when the engine's
/// records establish every attempt (an age purge, suppressed rows, a restart, a crash, an incomplete read).
Class Shutter.Operation.EngineResend Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

/// How long an approval stands before its first send, in minutes.
Parameter APPROVALMINUTES = 15;

/// Seconds added to FailureTimeout and ConnectTimeout for the wait on a new header.
Parameter PADSECONDS = 10;

/// How many days after its run stopped an unknown resend is still read again for its result.
Parameter LATEDAYS = 7;

/// The actor the outage's events and the cases' notes name.
Parameter ACTOR = "Engine Resend";

/// The settings an approval binds.
Parameter BOUND = "DefCharEncoding,IPAddress,Port";

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    // A resend whose result was unknown when the run stopped is read again first: its new header may have settled since.
    Try {
        Do ..SettleLate()
    } Catch err {
        $$$LOGWARNING("Engine Resend could not read the unknown resends again: " _ err.DisplayString())
    }
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.Outage WHERE State = 'sending' ORDER BY ID")
    While rs.%Next() {
        Set outage = ##class(Shutter.Store.Outage).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(outage)
        Try {
            Do ..Run(outage)
        } Catch err {
            Do ..Stop(outage, "the sender stopped on an error (" _ err.DisplayString() _ "): read the last new header in the Message Viewer")
        }
    }
    Quit $$$OK
}

/// One run, to its end or its first stop.
ClassMethod Run(outage As Shutter.Store.Outage)
{
    Set approval = $SELECT(outage.Approval '= "": {}.%FromJSON(outage.Approval), 1: {})
    Set runId = ##class(Shutter.Util.Json).Str(approval, "id")
    If runId = "" Do ..Stop(outage, "the outage reads sending with no approval on it") Quit
    Set ns = outage.Namespace, item = outage.Item
    // A row left sending: the process stopped between the call and its answer. Nothing more goes.
    &sql(SELECT TOP 1 OriginHeaderId INTO :left FROM Shutter_Store.ResendRecord WHERE RunId = :runId AND State = 'sending')
    If SQLCODE = 0 Do ..Stop(outage, "message header " _ left _ " may have been sent before the sender stopped: read its new header in the Message Viewer; nothing more was sent") Quit
    // The approval stands for APPROVALMINUTES before the first send.
    &sql(SELECT COUNT(*) INTO :started FROM Shutter_Store.ResendRecord WHERE RunId = :runId AND StartedAt IS NOT NULL AND StartedAt <> '')
    Set now = ##class(Shutter.Util.Time).NowUTC()
    If 'started && (##class(Shutter.Util.Json).Str(approval, "goodUntil") '= "") && (##class(Shutter.Util.Time).MillisBetween(approval.goodUntil, now) > 0) {
        Do ..Stop(outage, "the approval expired at " _ approval.goodUntil _ " before the first send: read the set again and approve it again") Quit
    }
    // The settings the approval binds: read before the first send, compared before each.
    Set current = ..Settings(ns, item)
    If 'approval.%IsDefined("settings") {
        Set approval.settings = current
        Set sc = outage.Advance("sending", "", ..#ACTOR, {"Approval": (approval.%ToJSON())})
        If $$$ISERR(sc) Quit
    }
    Set moved = ..Moved(approval.settings, current)
    If moved '= "" Do ..Stop(outage, moved _ " after the approval: the same stored message would go out differently, so nothing more is sent") Quit
    // One pass of the patient check: its merge read is made once for the run, then only for what arrived since.
    Do ##class(Shutter.Util.PatientCheck).Pass(1)
    For {
        Set rowId = ""
        &sql(SELECT TOP 1 ID INTO :rowId FROM Shutter_Store.ResendRecord WHERE RunId = :runId AND State = 'approved' ORDER BY Position)
        If SQLCODE '= 0 Quit
        Set row = ##class(Shutter.Store.ResendRecord).%OpenId(rowId)
        Set verdict = ..One(outage, row, approval)
        If verdict = "stop" Quit
    }
    Do ##class(Shutter.Util.PatientCheck).Pass(0)
    Do outage.%Reload()
    If outage.State = "sending" Do ..Finish(outage, runId)
}

/// One message of the run: "go" (sent, closed or skipped: the run goes on) or "stop" (the outage has gone to a person).
ClassMethod One(outage As Shutter.Store.Outage, row As Shutter.Store.ResendRecord, approval As %DynamicObject) As %String
{
    Set ns = outage.Namespace, item = outage.Item
    // The item first: nothing goes while the engine is trying anything, or into an operation that retries for ever.
    Set isStock = ##class(Shutter.Util.EngineScope).IsStockTcp(ns, item)
    Set gate = ##class(Shutter.Util.ResendSet).ItemGate(##class(Shutter.Util.EngineRead).ItemState(ns, item), ##class(Shutter.Util.EngineRead).ItemSetting(ns, item, "FailureTimeout", isStock))
    If gate '= "" Do ..Stop(outage, gate) Quit "stop"
    Set moved = ..Moved(approval.settings, ..Settings(ns, item))
    If moved '= "" Do ..Stop(outage, moved _ " after the approval: the same stored message would go out differently, so nothing more is sent") Quit "stop"
    // The message: every rule of the set read again, this run's own unsent rows aside.
    Set check = ..Recheck(ns, item, row.OriginHeaderId, outage.Receiver, ..RunCases(row.RunId), ..RunHeaders(row.RunId))
    If check.verdict = "skip" {
        Set row.State = "stopped", row.Words = $EXTRACT("not sent: " _ check.why, 1, 1000), row.EndedAt = ##class(Shutter.Util.Time).NowUTC()
        Do row.%Save()
        Quit "go"
    }
    If check.verdict = "stop" Do ..Stop(outage, check.why) Quit "stop"
    Set headerId = check.headerId
    Set body = ##class(Shutter.Util.MessageCopy).Of(ns, headerId)
    Set digest = $SELECT($ISOBJECT(body): ..Hex($SYSTEM.Encryption.SHAHash(256, $ZCONVERT(body.OutputToString(), "O", "UTF8"))), 1: "")
    Set newId = ..Send(outage, row, approval, headerId, digest, .sc, .halted)
    If halted Quit "stop"
    If $$$ISERR(sc) || (newId = "") {
        Set row.State = "failed", row.Words = $EXTRACT("the engine refused the resend: " _ $SYSTEM.Status.GetErrorText(sc), 1, 1000), row.EndedAt = ##class(Shutter.Util.Time).NowUTC()
        Do row.%Save()
        Do ..Stop(outage, "the engine refused to resend header " _ headerId _ ": nothing more was sent")
        Quit "stop"
    }
    Set row.NewHeaderId = newId, row.SameBody = 1
    Do row.%Save()
    // The new header to its end, within the item's own timeouts.
    Set wait = ..WaitSeconds(ns, item, isStock)
    Set status = ..Settle(ns, newId, wait)
    Quit ..Outcome(outage, row, approval, headerId, newId, status, wait)
}

/// The send of one message, the recovery control last (CONTRACTS 18): under the control's lock until the engine has the
/// message, so a stop commits either before this check, and this message and the rest are not sent (halted 1, the run
/// halted), or after the hand-over. Otherwise the ledger row is written sending, then the stock resend: the new header's id,
/// or "" with sc.
ClassMethod Send(outage As Shutter.Store.Outage, row As Shutter.Store.ResendRecord, approval As %DynamicObject, headerId As %String, digest As %String, Output sc As %Status, Output halted As %Boolean) As %String
{
    Set sc = $$$OK, halted = 0, newId = ""
    If '##class(Shutter.Util.RecoveryControl).HoldForResend(.code, .text) {
        Do ..Halt(outage, row, code, text)
        Set halted = 1
        Quit ""
    }
    Try {
        // The intent first, then the call: EnQueue commits a transaction of its own, so the two cannot be one.
        Set row.OriginHeaderId = headerId, row.State = "sending", row.StartedAt = ##class(Shutter.Util.Time).NowUTC(), row.DigestBefore = digest
        Set row.DefCharEncoding = approval.settings.DefCharEncoding, row.IPAddress = approval.settings.IPAddress, row.Port = approval.settings.Port
        $$$ThrowOnError(row.%Save())
        Set newId = ..Enqueue(outage.Namespace, headerId, .sc)
    } Catch err {
        Do ##class(Shutter.Util.RecoveryControl).ResendHandedOver()
        Throw err
    }
    Do ##class(Shutter.Util.RecoveryControl).ResendHandedOver()
    Quit newId
}

/// What one send came to, once its new header settled (status the word, or "" when it had not in wait seconds): the row,
/// the message's cases and the outage moved on. "go" or "stop", as One answers.
ClassMethod Outcome(outage As Shutter.Store.Outage, row As Shutter.Store.ResendRecord, approval As %DynamicObject, headerId As %String, newId As %String, status As %String, wait As %Integer) As %String
{
    Set ns = outage.Namespace
    Set at = ##class(Shutter.Util.Time).NowUTC()
    If status = "Completed" {
        Set row.State = "completed", row.EndedAt = at
        Set row.Words = "Resent by Shutter at " _ ..Clock(at) _ " under approval " _ approval.id _ " by " _ approval.by _ "; new header " _ newId _ " Completed."
        Do row.%Save()
        Do outage.%Reload()
        Do outage.Advance("sending", "", ..#ACTOR, {"SentByShutter": (outage.SentByShutter + 1)})
        Do ..Resolve(ns, headerId, row.Words, outage, row)
        Quit "go"
    }
    If (status = "Error") || (status = "Suspended") {
        If ..Duplicate(ns, newId, outage.Receiver, .said) {
            Set row.State = "closed_as_present", row.EndedAt = at
            Set row.Words = "Already delivered: the receiver reported it already holds this message (MSA-3: " _ said _ "); the engine never delivered it by this route, and a hand entry would explain it. Shutter has not compared the stored result or amendment."
            Do row.%Save()
            Do ..AlreadyDelivered(ns, row, outage)
            Quit "go"
        }
        Set replied = ..ReplyText(ns, newId)
        Set row.State = "failed", row.EndedAt = at, row.Words = $EXTRACT("new header " _ newId _ " ended " _ status _ $SELECT(replied '= "": " (" _ replied _ ")", 1: ""), 1, 1000)
        Do row.%Save()
        Do ..FailedOnCase(ns, row, "Shutter's resend of this message failed at " _ ..Clock(at) _ ": new header " _ newId _ " ended " _ status _ $SELECT(replied '= "": " (" _ replied _ ")", 1: "") _ ". Nothing more was sent; the outage waits for a person.")
        Do ..Stop(outage, "the resend of header " _ headerId _ " (new header " _ newId _ ") ended " _ status _ ": the rest were not sent")
        Quit "stop"
    }
    Set row.State = "unknown", row.EndedAt = at, row.Words = "new header " _ newId _ " had not settled in " _ wait _ " s (" _ $SELECT(status '= "": status, 1: "unread") _ ")"
    Do row.%Save()
    Do ..Stop(outage, "new header " _ newId _ " had not settled in " _ wait _ " s: read it in the Message Viewer; nothing more was sent")
    Quit "stop"
}

/// The rows whose result was unknown when their run stopped (the new header had not settled within the wait): each new
/// header is read again, and once the engine shows it settled the row ends as the send would have ended it in time, by
/// the same rules (CONTRACTS 17.8): Completed is a send that completed and resolves the message's case; the receiver's
/// declared duplicate answer closes it as already held; any other end is a failed resend with an event on its case.
/// The run itself stays stopped, nothing is sent again, and the outage's state is left as it is, with an event saying
/// what was read. A header still Queued or Delivered, or one that can't be read, stays unknown. Only rows ended in the
/// last LATEDAYS days are read.
ClassMethod SettleLate() As %Integer
{
    Set n = 0, since = ##class(Shutter.Util.Time).FromNow(-..#LATEDAYS * 86400)
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.ResendRecord WHERE State = 'unknown' AND NewHeaderId IS NOT NULL AND NewHeaderId <> '' AND (EndedAt IS NULL OR EndedAt = '' OR EndedAt >= ?) ORDER BY ID", since)
    While rs.%Next() {
        Set row = ##class(Shutter.Store.ResendRecord).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(row)
        Set h = ..Header(row.Namespace, row.NewHeaderId)
        Continue:'$ISOBJECT(h)
        Set word = ##class(Shutter.Util.EngineRead).StatusWord(h.status)
        Continue:(word="")||(word="Queued")||(word="Delivered")||(word="Created")
        Set outage = ##class(Shutter.Store.Outage).%OpenId(row.OutageId)
        Continue:'$ISOBJECT(outage)
        Do ..Late(outage, row, word)
        Set n = n + 1
    }
    Quit n
}

/// One unknown row whose new header now reads status: the row, the message's cases and an event on the outage.
ClassMethod Late(outage As Shutter.Store.Outage, row As Shutter.Store.ResendRecord, status As %String)
{
    Set ns = row.Namespace, newId = row.NewHeaderId, at = ##class(Shutter.Util.Time).NowUTC()
    Set sent = $SELECT(row.StartedAt '= "": ..Clock(row.StartedAt), 1: "")
    Set late = ", read at " _ ..Clock(at) _ " after the send's wait had run out"
    If status = "Completed" {
        Set row.State = "completed", row.EndedAt = at
        Set row.Words = "Resent by Shutter" _ $SELECT(sent '= "": " at " _ sent, 1: "") _ " under approval " _ row.ApprovalId _ $SELECT(row.ApprovedBy '= "": " by " _ row.ApprovedBy, 1: "") _ "; new header " _ newId _ " Completed" _ late _ "."
        Do row.%Save()
        Do ..Resolve(ns, row.OriginHeaderId, row.Words, outage, row)
    } ElseIf ((status = "Error") || (status = "Suspended")) && ..Duplicate(ns, newId, outage.Receiver, .said) {
        Set row.State = "closed_as_present", row.EndedAt = at
        Set row.Words = "Already delivered: the receiver reported it already holds this message (MSA-3: " _ said _ "); the engine never delivered it by this route, and a hand entry would explain it. Shutter has not compared the stored result or amendment."
        Do row.%Save()
        Do ..AlreadyDelivered(ns, row, outage)
    } Else {
        Set replied = ..ReplyText(ns, newId)
        Set row.State = "failed", row.EndedAt = at, row.Words = $EXTRACT("new header " _ newId _ " ended " _ status _ $SELECT(replied '= "": " (" _ replied _ ")", 1: "") _ late, 1, 1000)
        Do row.%Save()
        Do ..FailedOnCase(ns, row, "Shutter's resend of this message failed: new header " _ newId _ " ended " _ status _ $SELECT(replied '= "": " (" _ replied _ ")", 1: "") _ late _ ". Nothing more was sent for it; a person reads the trace.")
    }
    Do ##class(Shutter.Store.OutageEvent).Add(outage.%Id(), "resend_settled", $EXTRACT("Header " _ row.OriginHeaderId _ ": its resend's result was unknown, and new header " _ newId _ " now reads " _ status _ ". " _ row.Words, 1, 2000), ..#ACTOR)
}

/// The set's rules for one message again: {"verdict": "go", "headerId"} (the header to send: the origin, or Shutter's
/// never-opened clone in its place), {"verdict": "skip", "why"} (the patient check holds it) or {"verdict": "stop", "why"}.
/// members are the run's origin header ids, which the order rule leaves out of its newer read.
ClassMethod Recheck(ns As %String, item As %String, headerId As %String, receiver As %String, exclude As %List, members As %List = "") As %DynamicObject
{
    Set h = ..Header(ns, headerId)
    If '$ISOBJECT(h) Quit {"verdict": "stop", "why": ("header " _ headerId _ " could not be read")}
    Set row = ##class(Shutter.Util.ResendSet).Row(ns, h)
    Set place = ##class(Shutter.Util.ResendSet).Place(ns, h, row)
    // Closed without a send of its own since the approval (already handled by hand, or held already): nothing goes.
    If place = "closed" Quit {"verdict": "stop", "why": ("header " _ headerId _ " no longer qualifies: " _ $SELECT(row.closure = "handled_by_hand": "handled by hand, recorded by " _ row.closedBy _ $SELECT(row.closedAt '= "": " at " _ ..Clock(row.closedAt), 1: ""), 1: "the receiver reported it already holds it"))}
    If place = "candidate" {
        Set check = ##class(Shutter.Util.PatientCheck).Check(ns, item, row.headerId, receiver, exclude, members)
        If check.hold Quit {"verdict": "skip", "why": (check.why)}
        Quit {"verdict": "go", "headerId": (row.headerId)}
    }
    If ($ISOBJECT(row.sibling) || (row.reason [ "by hand")) Quit {"verdict": "stop", "why": ("someone else is resending: header " _ headerId _ ", " _ row.reason)}
    Quit {"verdict": "stop", "why": ("header " _ headerId _ " no longer qualifies: " _ $SELECT(row.reason '= "": row.reason, 1: "its status is " _ row.status))}
}

/// The run's own cases, which the patient check leaves out: the case each row of the run names, and every case on each
/// row's origin header in its namespace (a message can have more than one).
ClassMethod RunCases(runId As %String) As %List
{
    Set ids = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT CaseId, Namespace, OriginHeaderId FROM Shutter_Store.ResendRecord WHERE RunId = ?", runId)
    While rs.%Next() {
        Set id = rs.%Get("CaseId")
        Set:(id'="")&&'$LISTFIND(ids, id) ids = ids _ $LISTBUILD(id)
        Set cases = ##class(Shutter.Util.ResendSet).CaseRows(rs.%Get("Namespace"), rs.%Get("OriginHeaderId"))
        Set iter = cases.%GetIterator()
        While iter.%GetNext(, .one) { Set:'$LISTFIND(ids, one.caseId) ids = ids _ $LISTBUILD(one.caseId) }
    }
    Quit ids
}

/// The run's origin header ids, in position order.
ClassMethod RunHeaders(runId As %String) As %List
{
    Set ids = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT OriginHeaderId FROM Shutter_Store.ResendRecord WHERE RunId = ? ORDER BY Position", runId)
    While rs.%Next() { Set ids = ids _ $LISTBUILD(rs.%Get("OriginHeaderId")) }
    Quit ids
}

/// The bound settings as read now: {"DefCharEncoding", "IPAddress", "Port"}, each the resolved value or "unknown".
ClassMethod Settings(ns As %String, item As %String) As %DynamicObject
{
    Set isStock = ##class(Shutter.Util.EngineScope).IsStockTcp(ns, item)
    Set out = {}
    For i = 1:1:$LENGTH(..#BOUND, ",") {
        Set name = $PIECE(..#BOUND, ",", i)
        Set s = ##class(Shutter.Util.EngineRead).ItemSetting(ns, item, name, isStock)
        Do out.%Set(name, $SELECT(s.source = "unknown": "unknown", 1: s.value))
    }
    Quit out
}

/// "" when the settings are as bound, else what moved ("the operation's Port changed from 7202 to 7203"). A setting read
/// as unknown now moves too: what can't be read can't be shown unchanged.
ClassMethod Moved(bound As %DynamicObject, now As %DynamicObject) As %String
{
    Quit:'$ISOBJECT(bound) "the settings bound at the approval could not be read"
    For i = 1:1:$LENGTH(..#BOUND, ",") {
        Set name = $PIECE(..#BOUND, ",", i)
        Set was = bound.%Get(name), is = now.%Get(name)
        If (was '= is) || (is = "unknown") Return "the operation's " _ name _ " changed from " _ $SELECT(was '= "": was, 1: "empty") _ " to " _ $SELECT(is '= "": is, 1: "empty")
    }
    Quit ""
}

/// Whether the new header's refusal is the receiver's declared duplicate answer: duplicates.behaviour refuses, with the
/// code in an ERR-3 or the MSA-3 phrase (Declared). Matched by field, never as a substring of the whole reply. said is the
/// receiver's MSA-3, or its ERR-3 code.
ClassMethod Duplicate(ns As %String, newId As %String, receiver As %String, Output said As %String) As %Boolean
{
    Set said = ""
    Set entry = ##class(Shutter.Store.SiteProfile).Receiver(receiver)
    Quit:'$ISOBJECT(entry) 0
    Set d = entry.%Get("duplicates")
    Quit:'$ISOBJECT(d) 0
    Quit:d.%Get("behaviour")'="refuses" 0
    Set reply = ##class(Shutter.Util.ReplyWords).Read(..ReplyLog(ns, newId))
    Set said = $SELECT(reply.msa3 '= "": reply.msa3, 1: "code " _ d.%Get("code"))
    Quit ..Declared(reply, d)
}

/// The log row of the new header that carries the receiver's MSA, or "".
ClassMethod ReplyLog(ns As %String, newId As %String) As %String [ Private ]
{
    Set rows = ##class(Shutter.Util.EngineRead).LogRows(ns, newId), text = ""
    If rows.answer = "ok" {
        Set iter = rows.rows.%GetIterator()
        While iter.%GetNext(, .r) { Set:r.text["MSA|" text = r.text }
    }
    Quit text
}

/// The receiver's words for a new header that did not end Completed, for the case's event: "the receiver answered AE:
/// Refused by the application", or "".
ClassMethod ReplyText(ns As %String, newId As %String) As %String [ Private ]
{
    Set reply = ##class(Shutter.Util.ReplyWords).Read(..ReplyLog(ns, newId))
    Quit:reply.msa1="" ""
    Quit $EXTRACT("the receiver answered " _ reply.msa1 _ $SELECT(reply.msa3 '= "": ": " _ reply.msa3, 1: ""), 1, 300)
}

/// The match itself, pure: the reply's words against the declaration {"code", "phrase"}. MSA-1 must be AE or AR; then
/// an ERR-3 equal to the code, or MSA-3 (trimmed) equal to the phrase, or starting with it where the next character is
/// neither a letter nor a digit ("ALREADY HELD, entered by hand"). Case is kept.
ClassMethod Declared(reply As %DynamicObject, d As %DynamicObject) As %Boolean
{
    Set code = d.%Get("code"), phrase = d.%Get("phrase")
    Set ack = $ZCONVERT($ZSTRIP(reply.msa1, "<>W"), "U")
    Quit:(ack'="AE")&&(ack'="AR") 0
    Set said = $ZSTRIP(reply.msa3, "<>W")
    If phrase '= "" {
        If said = phrase Quit 1
        If ($EXTRACT(said, 1, $LENGTH(phrase)) = phrase) && '$MATCH($EXTRACT(said, $LENGTH(phrase) + 1), "[\p{L}\p{N}]") Quit 1
    }
    Quit:code="" 0
    Set iter = reply.errors.%GetIterator()
    While iter.%GetNext(, .e) { Return:e.code=code 1 }
    Quit 0
}

/// The stock resend, in the watched namespace: the stored body, the same target. The new header's id, or "" with sc.
ClassMethod Enqueue(ns As %String, headerId As %String, Output sc As %Status) As %String
{
    Set here = $NAMESPACE, newId = "", sc = $$$OK
    Try {
        Set $NAMESPACE = ns
        Set sc = ##class(Ens.MessageHeader).ResendDuplicatedMessage(headerId, .newId)
    } Catch err {
        Set sc = err.AsStatus()
    }
    Set $NAMESPACE = here
    Quit newId
}

/// The new header's status word once it leaves Queued and Delivered, or what it reads when wait seconds run out.
ClassMethod Settle(ns As %String, headerId As %String, wait As %Integer) As %String
{
    Set deadline = $ZHOROLOG + wait, word = ""
    For {
        Set h = ..Header(ns, headerId)
        Set word = $SELECT($ISOBJECT(h): ##class(Shutter.Util.EngineRead).StatusWord(h.status), 1: "")
        Quit:(word'="")&&(word'="Queued")&&(word'="Delivered")&&(word'="Created")
        If $ZHOROLOG > deadline Set word = "" Quit
        Hang 1
    }
    Quit word
}

/// How long a new header may take: the item's FailureTimeout and ConnectTimeout, and PADSECONDS.
ClassMethod WaitSeconds(ns As %String, item As %String, isStock As %String) As %Integer
{
    Set ft = ##class(Shutter.Util.EngineRead).ItemSetting(ns, item, "FailureTimeout", isStock)
    Set ct = ##class(Shutter.Util.EngineRead).ItemSetting(ns, item, "ConnectTimeout", isStock)
    Quit $SELECT(+ft.value > 0: +ft.value, 1: 0) + $SELECT(+ct.value > 0: +ct.value, 1: 5) + ..#PADSECONDS
}

/// One header of ns by SQL: {"id", "status", "timeCreated", "bodyId"}, or "".
ClassMethod Header(ns As %String, headerId As %String) As %DynamicObject
{
    Set here = $NAMESPACE, out = ""
    Try {
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Status, TimeCreated, MessageBodyId FROM Ens.MessageHeader WHERE ID = ?", headerId)
        If rs.%Next() Set out = {"id": (rs.%Get("ID")), "status": (rs.%Get("Status")), "timeCreated": (rs.%Get("TimeCreated")), "bodyId": (rs.%Get("MessageBodyId"))}
    } Catch {
        Set out = ""
    }
    Set $NAMESPACE = here
    Quit out
}

/// The receiver reported it already holds the message: the message's own cases (its origin's, by CaseRows; never a case
/// linked by receiver and time) are resolved with disposition already_delivered and the row's words.
ClassMethod AlreadyDelivered(ns As %String, row As Shutter.Store.ResendRecord, outage As Shutter.Store.Outage)
{
    Set rows = ..OwnCases(ns, row)
    Set iter = rows.%GetIterator()
    While iter.%GetNext(, .one) {
        Continue:one.state="resolved"
        Set case = ##class(Shutter.Store.Case).%OpenId(one.id)
        Continue:'$ISOBJECT(case)
        Set case.Disposition = "already_delivered", case.Outcome = row.Words, case.Headline = $EXTRACT(row.Words, 1, 500)
        Do case.Transition("resolved", row.Words, ..#ACTOR, "outage:" _ outage.%Id())
    }
}

/// A failed resend: an event of kind resend on the message's own cases, their state left as it is.
ClassMethod FailedOnCase(ns As %String, row As Shutter.Store.ResendRecord, words As %String)
{
    Set rows = ..OwnCases(ns, row)
    Set iter = rows.%GetIterator()
    While iter.%GetNext(, .one) {
        Set case = ##class(Shutter.Store.Case).%OpenId(one.id)
        Continue:'$ISOBJECT(case)
        Do case.Note("resend", words, ..#ACTOR, "resend:" _ row.RunId _ ":" _ row.Position)
    }
}

/// The cases of a row's message: on the header it sent and, when that was Shutter's clone standing in, on its origin.
ClassMethod OwnCases(ns As %String, row As Shutter.Store.ResendRecord) As %DynamicArray
{
    Set out = ##class(Shutter.Util.ResendSet).CaseRows(ns, row.OriginHeaderId), seen = ""
    Set iter = out.%GetIterator()
    While iter.%GetNext(, .one) { Set seen = seen _ $LISTBUILD(one.id) }
    // A clone of an earlier run sent in the origin's place: the origin's cases are the message's.
    Set origin = "", sent = row.OriginHeaderId
    &sql(SELECT TOP 1 OriginHeaderId INTO :origin FROM Shutter_Store.ResendRecord WHERE Namespace = :ns AND NewHeaderId = :sent)
    If (SQLCODE = 0) && (origin '= "") {
        Set more = ##class(Shutter.Util.ResendSet).CaseRows(ns, origin)
        Set iter = more.%GetIterator()
        While iter.%GetNext(, .one) { Continue:$LISTFIND(seen, one.id)  Set seen = seen _ $LISTBUILD(one.id) Do out.%Push(one) }
    }
    If row.CaseId '= "" {
        Set c = ##class(Shutter.Store.Case).ByCaseId(row.CaseId)
        If $ISOBJECT(c) && '$LISTFIND(seen, c.%Id()) Do out.%Push({"id": (c.%Id()), "caseId": (c.CaseId), "state": (c.State)})
    }
    Quit out
}

/// The message's case, resolved with what was sent, when it has one that is not resolved yet.
ClassMethod Resolve(ns As %String, headerId As %String, words As %String, outage As Shutter.Store.Outage, row As Shutter.Store.ResendRecord = "")
{
    Set rows = $SELECT($ISOBJECT(row): ..OwnCases(ns, row), 1: ##class(Shutter.Util.ResendSet).CaseRows(ns, headerId))
    Set iter = rows.%GetIterator()
    While iter.%GetNext(, .one) {
        Continue:one.state="resolved"
        Set case = ##class(Shutter.Store.Case).%OpenId(one.id)
        Continue:'$ISOBJECT(case)
        Set case.Outcome = words, case.Headline = $EXTRACT(words, 1, 500)
        Do case.Transition("resolved", words, ..#ACTOR, "outage:" _ outage.%Id())
    }
}

/// The run's end with nothing stopped: closed when every message went or was already held, else to a person with those
/// a patient check held.
ClassMethod Finish(outage As Shutter.Store.Outage, runId As %String)
{
    Set sent = 0, held = 0, skipped = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State, OriginHeaderId, Words FROM Shutter_Store.ResendRecord WHERE RunId = ? ORDER BY Position", runId)
    While rs.%Next() {
        Set s = rs.%Get("State")
        If s = "completed" { Set sent = sent + 1 } ElseIf s = "closed_as_present" { Set held = held + 1 } Else { Set skipped = skipped _ $LISTBUILD("header " _ rs.%Get("OriginHeaderId") _ ", " _ rs.%Get("Words")) }
    }
    Set words = sent _ " message" _ $SELECT(sent = 1: "", 1: "s") _ " resent by Shutter in order, each new header Completed" _ $SELECT(held: "; " _ held _ " the receiver reported it already held", 1: "") _ "."
    If skipped = "" Do outage.Advance("closed", words, ..#ACTOR) Quit
    Do outage.Advance("needs_person", words _ " Not sent: " _ $LISTTOSTRING(skipped, "; ") _ ".", ..#ACTOR)
}

/// The recovery control refused the next message (CONTRACTS 18: a stop, shadow mode, or a control that is busy or can't be
/// read). That message and every row not yet sent read stopped, with the words and halt the control's code, and the outage
/// goes to a person. Nothing more goes on this approval: once the stop is cleared or recovery enabled, a person reads the set
/// again and approves it again.
ClassMethod Halt(outage As Shutter.Store.Outage, row As Shutter.Store.ResendRecord, code As %String, text As %String)
{
    Set runId = row.RunId, sent = 0, left = 0
    &sql(SELECT COUNT(*) INTO :sent FROM Shutter_Store.ResendRecord WHERE RunId = :runId AND State = 'completed')
    &sql(SELECT COUNT(*) INTO :left FROM Shutter_Store.ResendRecord WHERE RunId = :runId AND State = 'approved')
    If code = "recovery_stopped" {
        Set cause = text, after = "once an approver has cleared the stop in Settings, read the set again and approve it again"
    } ElseIf code = "recovery_shadow" {
        Set cause = "The site is in shadow mode, with recovery off", after = "once the site enables recovery in its site profile, read the set again and approve it again"
    } Else {
        Set cause = $SELECT(text '= "": text, 1: "The recovery control refused it"), after = "read the set again and approve it again"
    }
    Set rowWords = "not sent: " _ $SELECT(code = "recovery_stopped": cause, 1: $ZCONVERT($EXTRACT(cause), "L") _ $EXTRACT(cause, 2, *)) _ ", so the run halted before this message"
    Set why = cause _ ", so the resend halted before header " _ row.OriginHeaderId _ ": " _ (+sent) _ " sent before it, " _ (+left) _ " not sent. Nothing more goes on this approval: " _ after _ "."
    Do ..Stop(outage, why, rowWords, code)
}

/// The run stops: every row not yet sent reads stopped (with rowWords, and halt when the recovery control stopped it), and the
/// outage goes to a person with the reason.
ClassMethod Stop(outage As Shutter.Store.Outage, why As %String, rowWords As %String = "not sent: the run stopped", halt As %String = "")
{
    Set approval = $SELECT(outage.Approval '= "": {}.%FromJSON(outage.Approval), 1: {})
    Set runId = ##class(Shutter.Util.Json).Str(approval, "id")
    If runId '= "" {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.ResendRecord WHERE RunId = ? AND State = 'approved'", runId)
        While rs.%Next() {
            Set row = ##class(Shutter.Store.ResendRecord).%OpenId(rs.%Get("ID"))
            Continue:'$ISOBJECT(row)
            Set row.State = "stopped", row.Words = $EXTRACT(rowWords, 1, 1000), row.Halt = halt, row.EndedAt = ##class(Shutter.Util.Time).NowUTC()
            Do row.%Save()
        }
    }
    Do outage.%Reload()
    Do outage.Advance("needs_person", $EXTRACT(why, 1, 1000), ..#ACTOR)
}

ClassMethod Hex(bytes As %String) As %String [ Private ]
{
    Set hex = ""
    For i = 1:1:$LENGTH(bytes) { Set hex = hex _ $ZCONVERT($TRANSLATE($JUSTIFY($ZHEX($ASCII(bytes, i)), 2), " ", "0"), "L") }
    Quit hex
}

ClassMethod Clock(iso As %String) As %String [ Private ]
{
    Quit $EXTRACT($PIECE(iso, "T", 2), 1, 5)
}

}
