/// The failsafe at the point of the resend (CONTRACTS 6.5, v1.29; the requirement of 26 Oct 2026): before Shutter
/// writes a case's operation again, the messages of the same encounter that reached Shutter after the case's own and are not
/// yet delivered to the case's receiver are listed, from the feed's deliveries (a ward message queued for the receiver with
/// no answer yet; for a case forwarded from a watched production, that production's deliveries too, v1.34) and the exact
/// index (a message received and not yet routed, or on a route Shutter does not watch). A
/// resend with one pending is refused by the connector and blocked by the gate (NEWER_MESSAGE_PENDING), and the case waits
/// for that message's delivery, after which it is planned again on fresh evidence: the later message may supersede the
/// resend, and nothing is written out of order. Classify is pure, so a test runs it without a message store.
Class Shutter.Util.ResendGuard
{

/// The messages of the case's encounter pending ahead of a resend: [{event, event_time, operation_key, control_id,
/// ens_header_id, sent_at, receiver, where}], oldest first; [] when none, or when the case names no encounter.
ClassMethod Pending(case As Shutter.Store.Case) As %DynamicArray
{
    If (case.EncounterId = "") || (case.EncounterId = "-") Quit []
    Set receiver = case.Receiver
    // A case forwarded from a watched production (CONTRACTS 11) names its namespace: the newer message of the encounter may
    // be queued or in flight there, so that production's deliveries count too (v1.34).
    Set deliveries = ##class(Shutter.Index.Timeline).Deliveries(case.EncounterId, receiver, case.SourceNamespace)
    Set indexed = []
    Try { Set indexed = ##class(Shutter.Index.Message).ForVisit(case.EncounterId) } Catch { Set indexed = [] }
    Quit ..Classify(deliveries, indexed, case.OperationKey, ..SinceOf(case), receiver)
}

/// The cases waiting for a message (WaitsOnMessage, CONTRACTS 6.5 and 11, v1.34) whose message has since been delivered,
/// released: the Ward item releases a case as it delivers, but that misses two cases, which the HL7 Index item's adapter
/// catches here every few seconds. A case forwarded from a watched production waits for a delivery that production's
/// connector makes, and it knows nothing of Shutter. And a case whose plan took time (the board's minute) may start waiting
/// after the delivery already happened: the gate judged the snapshot's pending messages, the Ward's release found no case
/// waiting yet, and nothing would ever release it (S24 on the board, 1 Nov 2026). A case is released when no pending
/// message of its encounter carries the awaited control id any more; the note says the delivery's outcome and where it was
/// read. Returns how many were released, and checked how many waiting cases it looked at; nothing here throws. Called by
/// the Case Releaser (Shutter.Operation.Releaser, v1.35), which passes itself as host so each release goes from that host
/// to the Case Workflow; without a host the release goes through the Shutter API service.
ClassMethod ReleaseDeliveredWaits(host As Ens.Host = "", target As %String = "Case Workflow", Output checked As %Integer) As %Integer
{
    Set n = 0, checked = 0, json = "Shutter.Util.Json"
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.""Case"" WHERE WaitsOnMessage <> '' AND State IN ('blocked', 'escalated')")
        While rs.%Next() {
            Set case = ##class(Shutter.Store.Case).%OpenId(rs.%Get("ID"))
            Continue:'$ISOBJECT(case)
            Set checked = checked + 1
            Set control = case.WaitsOnMessage, still = 0, outcome = "", where = ""
            Set pending = ..Pending(case), pi = pending.%GetIterator()
            While pi.%GetNext(, .p) { If $CLASSMETHOD(json, "Str", p, "control_id") = control Set still = 1 }
            Continue:still
            Set rows = ##class(Shutter.Index.Timeline).Deliveries(case.EncounterId, case.Receiver, case.SourceNamespace), ri = rows.%GetIterator()
            While ri.%GetNext(, .r) {
                Continue:($CLASSMETHOD(json, "Str", r, "source_message_id") '= control)
                Set outcome = $CLASSMETHOD(json, "Str", r, "outcome"), where = $CLASSMETHOD(json, "Str", r, "namespace")
            }
            Set n = n + ##class(Shutter.Store.Case).ReleaseWaitingOnMessage(control, $SELECT(outcome '= "": outcome, 1: "delivered") _ $SELECT(where '= "": " in " _ where, 1: "") _ ", found by the Case Releaser's sweep", host, target)
        }
    } Catch ex {
    }
    Quit n
}

/// The former name of ReleaseDeliveredWaits, kept for a caller compiled against it.
ClassMethod ReleaseForwardedWaits() As %Integer
{
    Quit ..ReleaseDeliveredWaits("", "Case Workflow", .checked)
}

/// When the case's own message reached Shutter: its source header's TimeCreated, else the case's opening time in the
/// header's form (yyyy-mm-dd hh:mm:ss), so that a message received later compares later as a string.
ClassMethod SinceOf(case As Shutter.Store.Case) As %String
{
    Set t = ""
    If case.SourceHeaderId '= "" {
        Set hid = case.SourceHeaderId
        &sql(SELECT TimeCreated INTO :t FROM Ens.MessageHeader WHERE ID = :hid)
        If SQLCODE '= 0 Set t = ""
    }
    If t '= "" Quit t
    Quit $TRANSLATE($PIECE(case.OpenedAt, "Z", 1), "T", " ")
}

/// The pending messages among the feed's deliveries (rows of Shutter.Index.Timeline.Deliveries) and the index's rows
/// (Shutter.Index.Message.ToObject): received after since (sent_at, the header's TimeCreated, compared as text), not the
/// case's own operation, and not delivered (a delivery with no answer recorded; an index row with no delivery to the
/// receiver). A delivery that was answered, applied or not, is not pending: it is history the gate reads elsewhere.
ClassMethod Classify(deliveries As %DynamicArray, indexed As %DynamicArray, caseKey As %String, since As %String, receiver As %String = "") As %DynamicArray
{
    Set json = "Shutter.Util.Json", out = [], seenKeys = "", seenControls = ""
    If $ISOBJECT(deliveries) {
        Set di = deliveries.%GetIterator()
        While di.%GetNext(, .d) {
            Continue:'$ISOBJECT(d)
            Set key = $CLASSMETHOD(json, "Str", d, "operation_key"), control = $CLASSMETHOD(json, "Str", d, "source_message_id")
            If key '= "" Set seenKeys = seenKeys _ $LISTBUILD(key)
            If control '= "" Set seenControls = seenControls _ $LISTBUILD(control)
            Continue:(key = caseKey)
            Set outcome = $CLASSMETHOD(json, "Str", d, "outcome", "unknown")
            Continue:((outcome '= "") && (outcome '= "unknown"))
            Set sent = $CLASSMETHOD(json, "Str", d, "sent_at")
            Continue:((since '= "") && '(sent ]] since))
            Do out.%Push(..Row(d, control, sent, $SELECT(receiver '= "": receiver, 1: $CLASSMETHOD(json, "Str", d, "receiver")), "queued for the receiver, no answer yet"))
        }
    }
    If $ISOBJECT(indexed) {
        Set ii = indexed.%GetIterator()
        While ii.%GetNext(, .r) {
            Continue:'$ISOBJECT(r)
            Set key = $CLASSMETHOD(json, "Str", r, "operation_key"), control = $CLASSMETHOD(json, "Str", r, "control_id")
            Continue:(key = caseKey)
            Continue:((key '= "") && $LISTFIND(seenKeys, key))
            Continue:((control '= "") && $LISTFIND(seenControls, control))
            Set sent = $CLASSMETHOD(json, "Str", r, "sent_at")
            Continue:((since '= "") && '(sent ]] since))
            Do out.%Push(..Row(r, control, sent, receiver, "received, not yet delivered to the receiver"))
        }
    }
    Quit out
}

ClassMethod Row(src As %DynamicObject, control As %String, sent As %String, receiver As %String, where As %String) As %DynamicObject [ Private ]
{
    Set json = "Shutter.Util.Json", o = {}
    Set o.event = $CLASSMETHOD(json, "Str", src, "event"), o."event_time" = $CLASSMETHOD(json, "Str", src, "event_time")
    Set o."operation_key" = $CLASSMETHOD(json, "Str", src, "operation_key"), o."control_id" = control
    Set o."ens_header_id" = $CLASSMETHOD(json, "Str", src, "ens_header_id"), o."sent_at" = sent
    Set o.receiver = receiver, o.where = where
    Quit o
}

/// One line for a check's detail or a case note: the first pending message, and how many more.
ClassMethod Describe(pending As %DynamicArray) As %String
{
    If '$ISOBJECT(pending) || (pending.%Size() = 0) Quit ""
    Set json = "Shutter.Util.Json", p = pending.%Get(0)
    Set text = "a " _ $CLASSMETHOD(json, "Str", p, "event", "message") _ " of this encounter received at " _ $CLASSMETHOD(json, "Str", p, "sent_at") _ " (control id " _ $CLASSMETHOD(json, "Str", p, "control_id") _ ") is " _ $CLASSMETHOD(json, "Str", p, "where")
    If pending.%Size() > 1 Set text = text _ ", and " _ (pending.%Size() - 1) _ " more"
    Quit text
}

}
