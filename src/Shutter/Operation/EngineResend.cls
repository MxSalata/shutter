/// Tier C's sender: an outage whose set a person approved (state sending) has its messages sent again through the engine,
/// one at a time, in the approved order, from this production job. The approval route only records the approval and the
/// run's rows in the ledger (Shutter.Store.ResendRecord); the REST process never switches to the watched namespace.
///
/// For each message: every rule of the set is read again (the item's state and FailureTimeout, the message's status, its
/// attempts, its copies, the log reaching back, the patient check); the ledger row is written as sending before the call;
/// the stock Ens.MessageHeader.ResendDuplicatedMessage sends the stored body unchanged; the new header is read until it
/// settles, within the item's FailureTimeout and ConnectTimeout and PADSECONDS. Completed: the row is completed and the
/// message's case resolved with what happened. Anything else stops the run, except a refusal the receiver's profile
/// declares as its duplicate answer, which closes that message as already held. A patient the check holds is skipped and
/// the rest go; a copy resent by someone else stops the run. A row found sending (a restart mid-run) goes to a person with
/// nothing more sent. The operation's DefCharEncoding, IPAddress and Port are read before the first send and bound to the
/// approval: a change stops the run.
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

/// The actor the outage's events and the cases' notes name.
Parameter ACTOR = "Engine Resend";

/// The settings an approval binds.
Parameter BOUND = "DefCharEncoding,IPAddress,Port";

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
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
    For {
        Set rowId = ""
        &sql(SELECT TOP 1 ID INTO :rowId FROM Shutter_Store.ResendRecord WHERE RunId = :runId AND State = 'approved' ORDER BY Position)
        If SQLCODE '= 0 Quit
        Set row = ##class(Shutter.Store.ResendRecord).%OpenId(rowId)
        Set verdict = ..One(outage, row, approval)
        If verdict = "stop" Quit
    }
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
    Set check = ..Recheck(ns, item, row.OriginHeaderId, outage.Receiver, ..RunCases(row.RunId))
    If check.verdict = "skip" {
        Set row.State = "stopped", row.Words = $EXTRACT("not sent: " _ check.why, 1, 1000), row.EndedAt = ##class(Shutter.Util.Time).NowUTC()
        Do row.%Save()
        Quit "go"
    }
    If check.verdict = "stop" Do ..Stop(outage, check.why) Quit "stop"
    // The intent first, then the call: EnQueue commits a transaction of its own, so the two cannot be one.
    Set headerId = check.headerId
    Set body = ##class(Shutter.Util.MessageCopy).Of(ns, headerId)
    Set row.OriginHeaderId = headerId, row.State = "sending", row.StartedAt = ##class(Shutter.Util.Time).NowUTC()
    Set row.DigestBefore = $SELECT($ISOBJECT(body): ..Hex($SYSTEM.Encryption.SHAHash(256, $ZCONVERT(body.OutputToString(), "O", "UTF8"))), 1: "")
    Set row.DefCharEncoding = approval.settings.DefCharEncoding, row.IPAddress = approval.settings.IPAddress, row.Port = approval.settings.Port
    $$$ThrowOnError(row.%Save())
    Set newId = ..Enqueue(ns, headerId, .sc)
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
    Set at = ##class(Shutter.Util.Time).NowUTC()
    If status = "Completed" {
        Set row.State = "completed", row.EndedAt = at
        Set row.Words = "Resent by Shutter at " _ ..Clock(at) _ " under approval " _ approval.id _ " by " _ approval.by _ "; new header " _ newId _ " Completed."
        Do row.%Save()
        Do outage.%Reload()
        Do outage.Advance("sending", "", ..#ACTOR, {"SentByShutter": (outage.SentByShutter + 1)})
        Do ..Resolve(ns, headerId, row.Words, outage)
        Quit "go"
    }
    If (status = "Error") || (status = "Suspended") {
        If ..Duplicate(ns, newId, outage.Receiver) {
            Set row.State = "closed_as_present", row.EndedAt = at
            Set row.Words = "The receiver reports it already holds this; the engine never delivered it by this route, and a hand entry would explain it. Shutter has not compared the stored result or amendment."
            Do row.%Save()
            Quit "go"
        }
        Set row.State = "failed", row.EndedAt = at, row.Words = "new header " _ newId _ " ended " _ status
        Do row.%Save()
        Do ..Stop(outage, "the resend of header " _ headerId _ " (new header " _ newId _ ") ended " _ status _ ": the rest were not sent")
        Quit "stop"
    }
    Set row.State = "unknown", row.EndedAt = at, row.Words = "new header " _ newId _ " had not settled in " _ wait _ " s (" _ $SELECT(status '= "": status, 1: "unread") _ ")"
    Do row.%Save()
    Do ..Stop(outage, "new header " _ newId _ " had not settled in " _ wait _ " s: read it in the Message Viewer; nothing more was sent")
    Quit "stop"
}

/// The set's rules for one message again: {"verdict": "go", "headerId"} (the header to send: the origin, or Shutter's
/// never-opened clone in its place), {"verdict": "skip", "why"} (the patient check holds it) or {"verdict": "stop", "why"}.
ClassMethod Recheck(ns As %String, item As %String, headerId As %String, receiver As %String, exclude As %List) As %DynamicObject
{
    Set h = ..Header(ns, headerId)
    If '$ISOBJECT(h) Quit {"verdict": "stop", "why": ("header " _ headerId _ " could not be read")}
    Set row = ##class(Shutter.Util.ResendSet).Row(ns, h)
    Set place = ##class(Shutter.Util.ResendSet).Place(ns, h, row)
    If place = "candidate" {
        Set check = ##class(Shutter.Util.PatientCheck).Check(ns, item, row.headerId, receiver, exclude)
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
/// code in an ERR-3 or the exact MSA-3 phrase. Matched by field, never as a substring of the whole reply.
ClassMethod Duplicate(ns As %String, newId As %String, receiver As %String) As %Boolean
{
    Set entry = ##class(Shutter.Store.SiteProfile).Receiver(receiver)
    Quit:'$ISOBJECT(entry) 0
    Set d = entry.%Get("duplicates")
    Quit:'$ISOBJECT(d) 0
    Quit:d.%Get("behaviour")'="refuses" 0
    Set rows = ##class(Shutter.Util.EngineRead).LogRows(ns, newId), text = ""
    If rows.answer = "ok" {
        Set iter = rows.rows.%GetIterator()
        While iter.%GetNext(, .r) { Set:r.text["MSA|" text = r.text }
    }
    Quit ..Declared(##class(Shutter.Util.ReplyWords).Read(text), d)
}

/// The match itself, pure: the reply's words against the declaration {"code", "phrase"}.
ClassMethod Declared(reply As %DynamicObject, d As %DynamicObject) As %Boolean
{
    Set code = d.%Get("code"), phrase = d.%Get("phrase")
    If (phrase '= "") && (reply.msa3 = phrase) Quit 1
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

/// The message's case, resolved with what was sent, when it has one that is not resolved yet.
ClassMethod Resolve(ns As %String, headerId As %String, words As %String, outage As Shutter.Store.Outage)
{
    Set rows = ##class(Shutter.Util.ResendSet).CaseRows(ns, headerId)
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

/// The run stops: every row not yet sent reads stopped, and the outage goes to a person with the reason.
ClassMethod Stop(outage As Shutter.Store.Outage, why As %String)
{
    Set approval = $SELECT(outage.Approval '= "": {}.%FromJSON(outage.Approval), 1: {})
    Set runId = ##class(Shutter.Util.Json).Str(approval, "id")
    If runId '= "" {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.ResendRecord WHERE RunId = ? AND State = 'approved'", runId)
        While rs.%Next() {
            Set row = ##class(Shutter.Store.ResendRecord).%OpenId(rs.%Get("ID"))
            Continue:'$ISOBJECT(row)
            Set row.State = "stopped", row.Words = "not sent: the run stopped", row.EndedAt = ##class(Shutter.Util.Time).NowUTC()
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
