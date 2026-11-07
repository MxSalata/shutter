/// The gate's one check of the engine's hands, for a write on a case from a stock HL7 TCP operation (a hook in
/// Shutter.Operation.Gate's ordering): a message the engine is still trying, or has delivered, must not also be written by
/// Shutter, and one the receiver may hold needs a person. Scope is read first and an unknown scope blocks, as an unknown
/// prerequisite always does. Read reads, Judge is the table, and Settle does what a block means for the case.
/// Called from the Gate, a production job, which may switch namespace; the REST process can't.
Class Shutter.Util.EngineCheck Extends %RegisteredObject
{

/// The message's custody and words as they read now, and the gate's row for them.
ClassMethod Row(case As Shutter.Store.Case) As %DynamicObject
{
    Quit ..Judge(..Read(case))
}

/// Everything Judge weighs: { "scope", "why", "namespace", "item", "receiver", "ackRoute", "deliveryHeader", "headers": [ {
/// "headerId", "custody", "status", "itemStatus", "completedAt", "why", "attempts" } ], "effectiveAck", "ackReason" }. The
/// delivery header comes first in headers, then its siblings; attempts is read for a settled header, the acknowledgement
/// level only when a header reads delivered. Never throws: a failed read leaves scope or a custody at unreadable.
ClassMethod Read(case As Shutter.Store.Case) As %DynamicObject
{
    Set facts = {"scope": "unreadable", "why": "", "namespace": (case.SourceNamespace), "item": "", "receiver": (case.Receiver), "deliveryHeader": "", "headers": [], "effectiveAck": "", "ackReason": ""}
    Do facts.%Set("ackRoute", ..AckRoute(case), "boolean")
    Try {
        Set ns = case.SourceNamespace
        Set item = ##class(Shutter.Util.EngineScope).ItemOf(ns, case)
        Set facts.item = item
        Set stock = ##class(Shutter.Util.EngineScope).IsStockTcp(ns, item)
        Set facts.scope = stock
        If (stock '= "yes") && (stock '= "base") Quit
        Set delivery = ##class(Shutter.Util.EngineRead).DeliveryHeader(ns, case.OriginHeaderId, item)
        If delivery.answer '= "found" {
            Set facts.scope = "unreadable", facts.why = delivery.why
            Quit
        }
        Set facts.deliveryHeader = delivery.headerId
        Do facts.headers.%Push(..HeaderFacts(ns, item, delivery.headerId))
        Set siblings = ##class(Shutter.Util.EngineRead).Siblings(ns, delivery.headerId)
        If siblings.answer '= "ok" {
            Set facts.scope = "unreadable", facts.why = siblings.why
            Quit
        }
        Set iter = siblings.rows.%GetIterator()
        While iter.%GetNext(.i, .row) {
            Do facts.headers.%Push(..HeaderFacts(ns, item, row.headerId))
        }
        If ..AnyDelivered(facts.headers) {
            Set level = ##class(Shutter.Store.SiteProfile).ReceiverAckLevel(case.Receiver)
            Set facts.effectiveAck = ..AckAt(ns, item, stock, level, .reason), facts.ackReason = reason
        }
    } Catch ex {
        Set facts.scope = "unreadable", facts.why = ex.DisplayString()
    }
    Quit facts
}

/// One header's custody and, once the engine has settled it, its words.
ClassMethod HeaderFacts(ns As %String, item As %String, headerId As %String) As %DynamicObject [ Private ]
{
    Set custody = ##class(Shutter.Util.EngineRead).Custody(ns, item, headerId)
    Set h = {"headerId": (headerId), "custody": (custody.answer), "status": (custody.headerStatus), "itemStatus": (custody.itemStatus), "completedAt": (custody.completedAt), "why": (custody.why), "attempts": ""}
    If custody.answer = "settled" {
        Set rows = ##class(Shutter.Util.EngineRead).LogRows(ns, headerId)
        If rows.answer = "ok" {
            Set h.attempts = ##class(Shutter.Util.EngineWords).Attempts(rows.rows)
        } Else {
            // A log that could not be read says nothing of the attempts: that is an unreadable engine, not unknown words.
            Set h.custody = "unreadable", h.why = rows.why
        }
    }
    Quit h
}

/// What a Completed header can claim at this item, from the site's declaration and the item's reply settings as read now.
/// A class that overrides the reply handling can't be read that way, whatever its settings say.
ClassMethod AckAt(ns As %String, item As %String, stock As %String, level As %String, Output reason As %String) As %String [ Private ]
{
    Set actions = "unknown", getReply = ""
    If stock = "yes" {
        Set read = ##class(Shutter.Util.EngineRead).ItemSetting(ns, item, "ReplyCodeActions", stock)
        If read.source '= "unknown" Set actions = read.value
        Set read = ##class(Shutter.Util.EngineRead).ItemSetting(ns, item, "GetReply", stock)
        If read.source '= "unknown" Set getReply = read.value
    }
    Quit ##class(Shutter.Util.EngineWords).EffectiveAck(level, actions, getReply, .reason)
}

/// Whether the case came from the application-ACK feed: the engine had finished with its message before the case existed.
/// Decided by the route and never by the clock: an alert can open a case after the engine delivered.
ClassMethod AckRoute(case As Shutter.Store.Case) As %Boolean
{
    Quit $EXTRACT(case.FailureReasonCode, 1, 4) = "ack_"
}

ClassMethod AnyDelivered(headers As %DynamicArray) As %Boolean [ Private ]
{
    Set iter = headers.%GetIterator()
    While iter.%GetNext(.i, .h) {
        If h.custody = "delivered" Return 1
    }
    Quit 0
}

/// The table, from what Read found: the gate's row, with what Settle needs under "engine". In order: scope; a header the
/// engine holds; an unread one; a delivered one, by route; then the words of what has settled.
ClassMethod Judge(facts As %DynamicObject) As %DynamicObject
{
    If facts.scope = "no" Quit ..Answer("pass", "ENGINE_NOT_IN_SCOPE", "The target is not a stock HL7 TCP operation; the engine's hands are not read here")
    If facts.scope = "unreadable" Quit ..Unreadable($SELECT(facts.why '= "": facts.why, 1: "the item or its class could not be read"))
    Set (engine, unread, delivered, held) = ""
    Set iter = facts.headers.%GetIterator()
    While iter.%GetNext(.i, .h) {
        If (h.custody = "engine") && (engine = "") Set engine = h
        If (h.custody '= "engine") && (h.custody '= "delivered") && (h.custody '= "settled") && (unread = "") Set unread = h
        If (h.custody = "delivered") && (delivered = "") Set delivered = h
        If (h.custody = "settled") && (h.attempts '= "never_opened") && (held = "") Set held = h
    }
    If $ISOBJECT(engine) {
        Set row = ..Answer("block", "ENGINE_STILL_TRYING", "The engine is still trying this message at the receiver (status " _ engine.status _ ", operation " _ engine.itemStatus _ "): a resend now would deliver it twice. The case waits; it is judged again when the engine has finished.")
        Set row.engine = {"marker": (facts.namespace _ ":" _ engine.headerId)}
        Quit row
    }
    If $ISOBJECT(unread) Quit ..Unreadable(unread.why)
    If facts.headers.%Size() = 0 Quit ..Unreadable("no delivery header")
    Set clock = ""
    If $ISOBJECT(delivered) Set clock = ..LocalTime(delivered.completedAt)
    If $ISOBJECT(delivered) && 'facts.ackRoute {
        Set words = ##class(Shutter.Util.EngineWords).DeliveredWords(delivered.headerId, clock, facts.effectiveAck, facts.ackReason)
        Set open = (facts.effectiveAck = "not_established")
        Set row = ..Answer("block", "ENGINE_DELIVERED", $SELECT(open: words, 1: "The engine delivered this message itself" _ $SELECT(clock '= "": " at " _ $EXTRACT(clock, 12, 16), 1: "") _ " (header " _ delivered.headerId _ "): nothing to resend."))
        Set row.engine = {"words": (words)}
        Do row.engine.%Set("established", 'open, "boolean")
        Quit row
    }
    If $ISOBJECT(held) Quit ..Answer("block", "RECEIVER_MAY_HOLD_IT", "The receiver may hold this message: its first attempt reached the receiver (the connection was lost after the frame was written, a read timed out, or the log does not say), and the operation then gave up. A resend could file it twice. A person checks the receiver's own screen first.")
    If $ISOBJECT(delivered) Quit ..Answer("pass", "ENGINE_SETTLED", "The engine had finished with this message (Completed" _ $SELECT(clock '= "": " at " _ $EXTRACT(clock, 12, 16), 1: "") _ ") before the case opened: the receiver's acknowledgement feed raised it")
    Quit ..Answer("pass", "ENGINE_SETTLED", "The engine has finished with this message, and every attempt in its retained log failed before a connection opened")
}

/// What the gate's two engine blocks mean for the case: true when this row is one of them, with the case moved. Still trying:
/// blocked, waiting on the engine. Delivered: resolved with the engine's words and the plan's disposition kept, or blocked for
/// a person when those words can't establish acceptance or the case is one a Completed header doesn't settle.
ClassMethod Settle(case As Shutter.Store.Case, row As %DynamicObject, checks As %DynamicArray, ref As %String) As %Status
{
    Set code = ##class(Shutter.Util.Json).Str(row, "reason_code")
    Set detail = ##class(Shutter.Util.Json).Str(row, "detail")
    Set engine = row.%Get("engine")
    If code = "ENGINE_STILL_TRYING" {
        Set case.WaitsOnEngine = ##class(Shutter.Util.Json).Str(engine, "marker")
        Set case.Headline = "Waiting for the engine: it is still trying this message at " _ case.Receiver
        Quit case.Transition("blocked", detail, "gate", ref)
    }
    Set words = ##class(Shutter.Util.Json).Str(engine, "words")
    Set case.Outcome = words
    If ##class(Shutter.Util.Json).Bool(engine, "established") && ..Resolvable(case, checks) {
        Set case.Headline = words
        Quit case.Transition("resolved", words, "gate", ref)
    }
    Set case.Headline = "Stopped for a person: " _ ##class(Shutter.Util.Json).Clip(words, 200)
    Quit case.Transition("blocked", words, "gate", ref)
}

/// Whether a Completed header can close this case: only a delivery the engine was failing to make, and no identity conflict.
/// A receiver's refusal or a message that maps to nothing isn't settled by the transport finishing.
ClassMethod Resolvable(case As Shutter.Store.Case, checks As %DynamicArray) As %Boolean
{
    If (case.FailureKind '= "delivery_failed") && (case.FailureKind '= "uncertain_outcome") Quit 0
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) {
        If ##class(Shutter.Util.Json).Str(c, "reason_code") = "PATIENT_MISMATCH" Return 0
    }
    Quit 1
}

ClassMethod Unreadable(why As %String) As %DynamicObject [ Private ]
{
    Quit ..Answer("unknown", "ENGINE_UNREADABLE", "The engine's record of this message could not be read (" _ ##class(Shutter.Util.Json).Clip(why, 200) _ "), so whether it is still trying it is not known. Nothing is sent")
}

ClassMethod Answer(result As %String, code As %String, detail As %String) As %DynamicObject [ Private ]
{
    Set c = {}
    Set c.check = "ordering", c.result = result, c."reason_code" = code, c.detail = detail
    Quit c
}

/// The engine's UTC time as this instance's local "yyyy-mm-dd hh:mm:ss", the form a person's words want; as given if it won't
/// convert, or "" for none.
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
