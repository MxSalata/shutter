/// The set gate, as a list for a person: of the messages to one operation item in an outage's window, which the engine
/// shows never reached the receiver and so could be sent again, and why each other one is not. It certifies nothing a send
/// would need: Shutter will not send these messages, and the words say so.
///
/// The item first (rules 2 and 7): the production running, the item enabled, its queue at 0, its Status not Retry and no
/// head message, so nothing is computed while anything is being tried; and its FailureTimeout read now neither -1 nor
/// unknown, since a resend into an operation that retries for ever reads Delivered for ever on an AR. A failed condition
/// gives set.status not_computed with set.reason naming it, never an empty list.
///
/// Then each origin header to the item created in the window, in header id order (the engine's own arrival order), into
/// one of four lists: queued (the engine, or a copy of it, is still trying: wait), offered (status Error; every retained
/// log row a connection that never opened; the log reaching back past it; no copy resent by hand; no resend of Shutter's
/// but a never-opened clone, which then stands in the origin's place; and the patient check passed), reached (the receiver
/// took it on an attempt: a reply, a lost read, a read timeout) or refused (anything else, with its reason, Suspended and
/// the other set-aside statuses included).
Class Shutter.Util.ResendSet [ Abstract ]
{

/// The version of these rules, which the set's digest and an approval bind.
Parameter SETPOLICYVERSION = "2026-11-09.1";

/// The words every surface shows with the set.
Parameter NOTSENT = "Shutter will not send these messages. Review them in the Message Viewer using the site's recovery procedure.";

Parameter NOTCURRENT = "Shutter has not checked whether this order or result is still current.";

/// The set for <var>item</var> in <var>ns</var> over the window <var>from</var> to <var>to</var> (the engine's
/// TimeCreated form, UTC), for the receiver name <var>receiver</var> Shutter's cases carry.
/// {"set": {"digest", "computedAt", "setPolicyVersion", "status", "reason"}, "lists": {"queued", "offered", "reached",
/// "refused"}, "words": {"first", "critical"}}.
ClassMethod Compute(ns As %String, item As %String, from As %String, to As %String, receiver As %String) As %DynamicObject
{
    Set state = ##class(Shutter.Util.EngineRead).ItemState(ns, item)
    Set isStock = ##class(Shutter.Util.EngineScope).IsStockTcp(ns, item)
    Set ft = ##class(Shutter.Util.EngineRead).ItemSetting(ns, item, "FailureTimeout", isStock)
    Set reason = ..ItemGate(state, ft)
    If reason '= "" Quit ..NotComputed(reason)
    Quit ..Lists(ns, item, from, to, receiver)
}

/// Rules 2 and 7 on what was read of the item: "" when the set may be computed, else the reason it is not.
ClassMethod ItemGate(state As %DynamicObject, ft As %DynamicObject) As %String
{
    Quit:'$ISOBJECT(state) "the item's state could not be read"
    Quit:state.answer'="ok" "the item's state could not be read: " _ state.why
    Quit:state.productionState'="running" "the production is not running"
    Quit:'state.enabled "the item is disabled"
    Quit:+state.queue>0 "the queue holds " _ (+state.queue) _ " message" _ $SELECT(+state.queue = 1: "", 1: "s") _ ": nothing is listed while anything is being tried"
    Quit:state.status="Retry" "the item is retrying a message: nothing is listed while anything is being tried"
    Quit:state.headHeaderId'="" "the engine is trying header " _ state.headHeaderId _ ": nothing is listed while anything is being tried"
    Quit:'$ISOBJECT(ft) "FailureTimeout could not be read, and unknown is treated as -1"
    Quit:ft.source="unknown" "FailureTimeout could not be read (" _ ft.why _ "), and unknown is treated as -1"
    Quit:(+ft.value=-1)&&(ft.value'="") "FailureTimeout is -1: the engine retries without limit, so a message sent again could read Delivered for ever"
    Quit ""
}

/// The four lists, the item's conditions already met.
ClassMethod Lists(ns As %String, item As %String, from As %String, to As %String, receiver As %String) As %DynamicObject
{
    Set out = ..Empty()
    Set out.set.status = "computed"
    Set headers = ..Origins(ns, item, from, to, .why)
    If why '= "" Quit ..NotComputed(why)
    // Rules 1, 3 to 6 per header; the patient check after, on the candidates together, since the set's own cases are
    // left out of it.
    Set candidates = []
    Set iter = headers.%GetIterator()
    While iter.%GetNext(, .h) {
        Set row = ..Row(ns, h)
        Set list = ..Place(ns, h, row)
        Continue:list=""
        If list = "candidate" { Do candidates.%Push(row) } Else { Do out.lists.%Get(list).%Push(row) }
    }
    Set exclude = ..CasesOf(ns, candidates)
    Set iter = candidates.%GetIterator()
    While iter.%GetNext(, .row) {
        Set check = ##class(Shutter.Util.PatientCheck).Check(ns, item, row.headerId, receiver, exclude)
        If check.hold {
            Set row.reason = "held by the patient check: " _ check.why
            Do out.lists.refused.%Push(row)
        } Else {
            Do out.lists.offered.%Push(row)
        }
    }
    Set out.set.digest = ..Digest(out.lists.offered)
    Quit out
}

/// Where one origin header goes: "queued", "reached", "refused", "candidate" or "" (Completed: none) (rules 1 and 3 to 6 passed). The row's
/// reason, sibling and headerId (a never-opened clone of Shutter's stands in for the origin) are set here.
ClassMethod Place(ns As %String, h As %DynamicObject, row As %DynamicObject) As %String
{
    Set word = row.status
    If (word = "Queued") || (word = "Delivered") {
        Set row.reason = "the engine still has it: wait"
        Quit "queued"
    }
    // A Completed header got through: it is in none of the lists, only in the outage's settled counts.
    Quit:word="Completed" ""
    If word '= "Error" {
        Set row.reason = $SELECT(word '= "": word, 1: "no status") _ ": set aside, not a delivery that failed"
        Quit "refused"
    }
    // Rules 5 and 6: copies of it in its session.
    Set sib = ##class(Shutter.Util.EngineRead).Siblings(ns, row.headerId)
    If sib.answer '= "ok" {
        Set row.reason = "its copies could not be read: " _ sib.why
        Quit "refused"
    }
    Set candidate = row.headerId, note = ""
    Set iter = sib.rows.%GetIterator()
    While iter.%GetNext(, .s) {
        Set at = ..Clock(s.at)
        Set row.sibling = {"headerId": (s.headerId), "status": (s.status), "at": (s.at)}
        If ##class(Shutter.Store.ResendRecord).IsOwnClone(ns, s.headerId) {
            If (s.status = "Error") && (..AttemptsOf(ns, s.headerId) = "never_opened") {
                Set candidate = s.headerId, note = "Shutter tried at " _ at _ "; the connection never opened"
                Continue
            }
            Set row.reason = "Shutter resent it at " _ at _ " and that copy reads " _ s.status
            Return "refused"
        }
        If (s.status = "Queued") || (s.status = "Delivered") {
            Set row.reason = "a copy resent by hand at " _ at _ " is being tried: wait"
            Return "queued"
        }
        Set row.reason = "resent by hand at " _ at _ $SELECT(s.status '= "Completed": " and that copy reads " _ s.status, 1: "")
        Return "refused"
    }
    // Rule 3: every retained row a connection that never opened.
    Set attempts = ..AttemptsOf(ns, candidate)
    Set row.attempts = attempts
    If attempts = "reached_receiver" {
        Set row.reason = "the receiver took it on an attempt (a reply, a lost read or a read timeout): do not send it again before checking the receiver"
        Quit "reached"
    }
    If attempts '= "never_opened" {
        Set row.reason = $CASE(attempts, "no_rows": "the engine's log keeps no attempt for it", : "the engine's log does not show what its attempts did")
        Quit "refused"
    }
    // Rule 4: the log reaches back past it, so no age purge took its history.
    Set back = ##class(Shutter.Util.EngineRead).LogReachesBack(ns, candidate)
    If back.answer '= "yes" {
        Set row.reason = "the engine's log does not reach back to it, so its attempts may have been purged"
        Quit "refused"
    }
    If candidate '= row.headerId Set row.headerId = candidate, row.reason = note
    Quit "candidate"
}

/// The origin headers to the item created in the window, oldest first: not a copy (Resent 0 or empty, no "Resent "
/// description), each {"id", "status", "timeCreated", "bodyId"}. why is set when the read failed.
ClassMethod Origins(ns As %String, item As %String, from As %String, to As %String, Output why As %String) As %DynamicArray
{
    Set why = "", list = []
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, Status, TimeCreated, MessageBodyId FROM Ens.MessageHeader WHERE TargetConfigName = ? AND TimeCreated >= ? AND TimeCreated <= ? AND (Resent IS NULL OR Resent = 0) AND (Description IS NULL OR NOT (Description %STARTSWITH 'Resent ')) ORDER BY ID", item, from, to)
        If rs.%SQLCODE < 0 {
            Set why = "the engine's headers could not be read (" _ rs.%Message _ ")"
        } Else {
            While rs.%Next() { Do list.%Push({"id": (rs.%Get("ID")), "status": (rs.%Get("Status")), "timeCreated": (rs.%Get("TimeCreated")), "bodyId": (rs.%Get("MessageBodyId"))}) }
        }
    } Catch err {
        Set why = "the engine's headers could not be read (" _ err.DisplayString() _ ")"
    }
    Quit list
}

/// A Row: {"headerId", "controlId", "timeCreated", "status", "attempts", "reason", "patient": {"id", "authority"},
/// "sibling"}.
ClassMethod Row(ns As %String, h As %DynamicObject) As %DynamicObject
{
    Set row = {"headerId": (h.id), "controlId": "", "timeCreated": (h.timeCreated), "status": (##class(Shutter.Util.EngineRead).StatusWord(h.status)), "attempts": "", "reason": "", "patient": {"id": "", "authority": ""}, "sibling": null}
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set msg = ##class(EnsLib.HL7.Message).%OpenId(h.bodyId)
        If $ISOBJECT(msg) {
            Set row.controlId = msg.GetValueAt("MSH:10")
            Set p = ##class(Shutter.Util.PatientCheck).Patients(msg)
            If p.%Size() && p.%Get(0).keys.%Size() Set row.patient = {"id": (p.%Get(0).keys.%Get(0).identifier), "authority": (p.%Get(0).keys.%Get(0).authority)}
        }
    } Catch {
    }
    Quit row
}

/// Rule 3's answer for one header: EngineWords.Attempts on its log rows, "unknown" when they could not be read.
ClassMethod AttemptsOf(ns As %String, headerId As %String) As %String
{
    Set rows = ##class(Shutter.Util.EngineRead).LogRows(ns, headerId)
    Quit $SELECT(rows.answer = "ok": ##class(Shutter.Util.EngineWords).Attempts(rows.rows), 1: "unknown")
}

/// The case ids of the candidates' messages: Shutter's cases on those headers in ns, which the patient check leaves out.
ClassMethod CasesOf(ns As %String, rows As %DynamicArray) As %List
{
    Set ids = ""
    Set iter = rows.%GetIterator()
    While iter.%GetNext(, .row) {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT CaseId FROM Shutter_Store.""Case"" WHERE (OriginHeaderId = ? OR SourceHeaderId = ?) AND (SourceNamespace = ? OR SourceNamespace IS NULL OR SourceNamespace = '')", row.headerId, row.headerId, ns)
        Continue:rs.%SQLCODE<0
        While rs.%Next() { Set:'$LISTFIND(ids, rs.%Get("CaseId")) ids = ids _ $LISTBUILD(rs.%Get("CaseId")) }
    }
    Quit ids
}

/// SHA-256, hex, of the rules' version and the offered header ids in order.
ClassMethod Digest(offered As %DynamicArray) As %String
{
    Set text = ..#SETPOLICYVERSION
    Set iter = offered.%GetIterator()
    While iter.%GetNext(, .row) { Set text = text _ "|" _ row.headerId }
    Set hash = $SYSTEM.Encryption.SHAHash(256, $ZCONVERT(text, "O", "UTF8")), hex = ""
    For i = 1:1:$LENGTH(hash) { Set hex = hex _ $ZCONVERT($TRANSLATE($JUSTIFY($ZHEX($ASCII(hash, i)), 2), " ", "0"), "L") }
    Quit hex
}

ClassMethod Empty() As %DynamicObject
{
    Quit {"set": {"digest": "", "computedAt": (##class(Shutter.Util.Time).NowUTC()), "setPolicyVersion": (..#SETPOLICYVERSION), "status": "", "reason": ""}, "lists": {"queued": [], "offered": [], "reached": [], "refused": []}, "words": {"first": (..#NOTSENT), "critical": (..#NOTCURRENT)}}
}

ClassMethod NotComputed(reason As %String) As %DynamicObject
{
    Set out = ..Empty()
    Set out.set.status = "not_computed", out.set.reason = reason
    Quit out
}

/// HH:MM of an engine time ("2026-11-09 03:12:01.123"), or the time as given.
ClassMethod Clock(time As %String) As %String [ Private ]
{
    Set t = $PIECE($TRANSLATE(time, "T", " "), " ", 2)
    Quit $SELECT(t '= "": $EXTRACT(t, 1, 5), 1: time)
}

}
