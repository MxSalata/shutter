/// The operations for an encounter (CONTRACTS 8.2): what the feed sent through Shutter's own typed messages, each
/// with its delivery outcome, and what the exact index knows besides, from HL7 messages on routes whose delivery
/// Shutter does not watch, with outcome unknown. The evidence collector puts the result in the snapshot; the gate
/// and the matcher count applied outcomes and, outside a chain, a later transfer of the feed's own whose failure the
/// connector recorded (Shutter.Catalogue.Matcher.Later), so an indexed message never supersedes a case by itself: the
/// receiver's own history decides that.
Class Shutter.Index.Timeline
{

/// The timeline for a case: the feed's operations for its encounter since the last reset, then the index's rows the
/// feed did not carry, merged by event time.
ClassMethod ForCase(case As Shutter.Store.Case) As %DynamicArray
{
    If ..NoEncounter(case.EncounterId) { Set out = [] Quit out }
    Set resetAt = $GET(^Shutter.Config("resetAt"))
    Set since = $SELECT(resetAt = "": "2000-01-01 00:00:00", 1: $TRANSLATE($PIECE(resetAt, "Z", 1), "T", " "))
    Set out = ..Typed(case, since)
    // A case forwarded from a watched production (CONTRACTS 11) names its namespace: the encounter's story there, that
    // production's own deliveries, joins the timeline, each row marked with the namespace (v1.34). Before, such a case saw
    // only what had been forwarded, its own failure, and nothing before or after it.
    If (case.SourceNamespace '= "") && (case.SourceNamespace '= $NAMESPACE) {
        Set there = ..TypedIn(case.SourceNamespace, case, since)
        If there.%Size() > 0 Set out = ..Merge(out, there)
    }
    Set extra = ..FromIndex(case, since, out)
    If extra.%Size() = 0 Quit out
    Quit ..Merge(out, extra)
}

/// Typed in another namespace, which must hold Shutter's message classes (a watched production's does): its rows, each with
/// namespace set; [] when it cannot be read.
ClassMethod TypedIn(namespace As %String, case As Shutter.Store.Case, since As %String) As %DynamicArray
{
    Set rows = []
    Try {
        New $NAMESPACE
        Set $NAMESPACE = namespace
        Set rows = ..Typed(case, since)
        Set ri = rows.%GetIterator()
        While ri.%GetNext(, .ev) { Set ev.namespace = namespace }
    } Catch ex {
        Set rows = []
    }
    Quit rows
}

/// The feed's operations for the encounter, oldest event first, with the delivery outcome the connector recorded.
ClassMethod Typed(case As Shutter.Store.Case, since As %String) As %DynamicArray
{
    Set out = []
    If ..NoEncounter(case.EncounterId) Quit out
    // One row per feed message for the case's receiver (v1.28): with two receivers each message is delivered twice, and the
    // other receiver's delivery is another case's story. A case without a receiver (older rows) sees every delivery.
    Set sql = "SELECT w.ID AS WID, w.Event, w.Ward, w.EventTime, w.OperationKey, w.SourceMessageId, h.ID AS HeaderId, h.SessionId, h.TimeCreated, h.TargetConfigName AS Receiver "
        _ "FROM Shutter_Msg.WardOperation w JOIN Ens.MessageHeader h ON h.MessageBodyId = CAST(w.ID AS VARCHAR(20)) AND h.MessageBodyClassName = 'Shutter.Msg.WardOperation' "
        _ "WHERE w.EncounterId = ? AND w.Purpose = 'normal' AND h.TimeCreated >= ? AND (? = '' OR h.TargetConfigName = ?) ORDER BY w.EventTime, w.ID"
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, case.EncounterId, since, case.Receiver, case.Receiver)
    While rs.%Next() {
        Set ev = {}
        Set ev."event" = rs.%Get("Event"), ev.ward = rs.%Get("Ward"), ev."event_time" = rs.%Get("EventTime")
        Set ev.receiver = rs.%Get("Receiver")
        Set ev."operation_key" = rs.%Get("OperationKey"), ev."source_message_id" = rs.%Get("SourceMessageId")
        Set ev."ens_header_id" = rs.%Get("HeaderId"), ev."ens_session_id" = rs.%Get("SessionId")
        Set ev."sent_at" = rs.%Get("TimeCreated"), ev.source = "feed"
        Do ev.%Set("later", rs.%Get("EventTime") ]] case.EventTime, "boolean")
        Do ev.%Set("this_case", rs.%Get("OperationKey") = case.OperationKey, "boolean")
        Set ev.outcome = "unknown"
        Set rid = ""
        Set headerId = rs.%Get("HeaderId")
        &sql(SELECT TOP 1 MessageBodyId INTO :rid FROM Ens.MessageHeader WHERE CorrespondingMessageId = :headerId AND MessageBodyClassName = 'Shutter.Msg.WardResult')
        If (SQLCODE = 0) && (rid '= "") {
            Set r = ##class(Shutter.Msg.WardResult).%OpenId(rid)
            If $ISOBJECT(r) {
                Set ev.outcome = r.Outcome, ev."reason_code" = r.ReasonCode, ev."http_status" = r.HttpStatus
                If r.EncounterVersion '= "" Set ev."version_after" = r.EncounterVersion
            }
        }
        Do out.%Push(ev)
    }
    Quit out
}

/// The index's rows for the encounter that the feed's list does not already carry (by operation key, else by
/// header id): messages on routes whose delivery Shutter does not watch. Their outcome is unknown here.
ClassMethod FromIndex(case As Shutter.Store.Case, since As %String, typed As %DynamicArray) As %DynamicArray
{
    Set out = []
    If ..NoEncounter(case.EncounterId) Quit out
    Try {
        Set iter = typed.%GetIterator()
        While iter.%GetNext(.i, .ev) {
            Set k = ##class(Shutter.Util.Json).Str(ev, "operation_key")
            If k '= "" Set keys(k) = 1
            Set h = ##class(Shutter.Util.Json).Str(ev, "ens_header_id")
            If h '= "" Set headers(h) = 1
            Set m = ##class(Shutter.Util.Json).Str(ev, "source_message_id")
            If m '= "" Set controls(m) = 1
        }
        Set rows = ##class(Shutter.Index.Message).ForVisit(case.EncounterId, since)
        Set iter = rows.%GetIterator()
        While iter.%GetNext(.i, .row) {
            Set k = ##class(Shutter.Util.Json).Str(row, "operation_key")
            Continue:((k '= "") && $DATA(keys(k)))
            Continue:(k = case.OperationKey)
            // The case's own message, mapped or not, is not a second event.
            Continue:((case.SourceHeaderId '= "") && (##class(Shutter.Util.Json).Str(row, "ens_header_id") = case.SourceHeaderId))
            Set c = ##class(Shutter.Util.Json).Str(row, "control_id")
            Continue:((c '= "") && $DATA(controls(c)))
            Set ev = {}
            Set ev."event" = ##class(Shutter.Util.Json).Str(row, "event"), ev.ward = ##class(Shutter.Util.Json).Str(row, "location")
            Set ev."event_time" = ##class(Shutter.Util.Json).Str(row, "event_time"), ev."operation_key" = k
            Set ev."source_message_id" = c, ev."ens_header_id" = ##class(Shutter.Util.Json).Str(row, "ens_header_id")
            Set ev."sent_at" = ##class(Shutter.Util.Json).Str(row, "sent_at"), ev.source = "index"
            Set ev.route = ##class(Shutter.Util.Json).Str(row, "route"), ev."message_type" = ##class(Shutter.Util.Json).Str(row, "message_type")
            Do ev.%Set("later", ev."event_time" ]] case.EventTime, "boolean")
            Do ev.%Set("this_case", 0, "boolean")
            Set ev.outcome = "unknown"
            Set ev.note = "Seen by the exact index on a route whose delivery Shutter does not watch; its outcome is not known from the message store, so it supersedes nothing by itself"
            Do out.%Push(ev)
        }
    } Catch ex {
        // The index is a finder; without it the feed's timeline stands.
    }
    Quit out
}

/// Whether an encounter id names nothing to look up: empty, or the "-" piece of a patient-level message (a merge or
/// a person update without a visit number). An empty id would join every indexed message without a visit number, so
/// every entry point answers an empty timeline for both without a query.
ClassMethod NoEncounter(encounterId As %String) As %Boolean
{
    Quit (encounterId = "") || (encounterId = "-")
}

/// Two timelines merged by event time (the feed's first at equal times).
ClassMethod Merge(a As %DynamicArray, b As %DynamicArray) As %DynamicArray
{
    Set n = 0
    For src = 1, 2 {
        Set list = $SELECT(src = 1: a, 1: b)
        Set iter = list.%GetIterator()
        While iter.%GetNext(.i, .ev) {
            Set n = n + 1
            Set t = ##class(Shutter.Util.Json).Str(ev, "event_time")
            Set order($SELECT(t = "": " ", 1: t), src, n) = ev
        }
    }
    Set out = [], t = ""
    For {
        Set t = $ORDER(order(t))
        Quit:t=""
        Set s = ""
        For {
            Set s = $ORDER(order(t, s))
            Quit:s=""
            Set k = ""
            For {
                Set k = $ORDER(order(t, s, k), 1, ev)
                Quit:k=""
                Do out.%Push(ev)
            }
        }
    }
    Quit out
}

/// The feed's deliveries for an encounter to a receiver (v1.28), oldest event first, with the outcome the connector recorded
/// and the case opened for each key, when one was: what the evidence reads about a bed's occupant. Rows:
/// {event, ward, bed, event_time, operation_key, source_message_id, ens_header_id, sent_at, receiver, outcome (unknown
/// when no answer is recorded), reason_code?, http_status?, version_after?, case_id?}. An empty receiver sees every delivery.
ClassMethod Deliveries(encounterId As %String, receiver As %String = "", sourceNamespace As %String = "") As %DynamicArray
{
    Set out = []
    If ..NoEncounter(encounterId) Quit out
    Set resetAt = $GET(^Shutter.Config("resetAt"))
    Set since = $SELECT(resetAt = "": "2000-01-01 00:00:00", 1: $TRANSLATE($PIECE(resetAt, "Z", 1), "T", " "))
    Set rows = ..DeliveryRows(encounterId, receiver, since)
    // A watched production's deliveries live in its own namespace (CONTRACTS 11): a case forwarded from it names the
    // namespace, and the occupant's movements there count too (v1.34).
    If (sourceNamespace '= "") && (sourceNamespace '= $NAMESPACE) {
        Set more = ..DeliveryRowsIn(sourceNamespace, encounterId, receiver, since)
        Set mi = more.%GetIterator()
        While mi.%GetNext(, .ev) { Set ev.namespace = sourceNamespace Do rows.%Push(ev) }
    }
    // In event order, then by when they were sent; the case each opened here, by its operation key.
    Set ri = rows.%GetIterator(), n = 0
    While ri.%GetNext(, .ev) {
        Set n = n + 1, sorted(ev."event_time", ev."sent_at", n) = ev
    }
    Set t = "" For { Set t = $ORDER(sorted(t)) Quit:t=""  Set a = "" For { Set a = $ORDER(sorted(t, a)) Quit:a=""  Set i = "" For { Set i = $ORDER(sorted(t, a, i), 1, ev) Quit:i=""
        Set caseId = "", key = ev."operation_key"
        &sql(SELECT TOP 1 CaseId INTO :caseId FROM Shutter_Store."Case" WHERE OperationKey = :key AND (Receiver = :receiver OR :receiver = '') ORDER BY ID DESC)
        If (SQLCODE = 0) && (caseId '= "") Set ev."case_id" = caseId
        Do out.%Push(ev)
    } } }
    Quit out
}

/// DeliveryRows in another namespace, which must hold Shutter's message classes (a watched production's does); [] when it
/// cannot be read.
ClassMethod DeliveryRowsIn(namespace As %String, encounterId As %String, receiver As %String, since As %String) As %DynamicArray
{
    Set rows = []
    Try {
        New $NAMESPACE
        Set $NAMESPACE = namespace
        Set rows = ..DeliveryRows(encounterId, receiver, since)
    } Catch ex {
        Set rows = []
    }
    Quit rows
}

/// The normal ward operations sent for an encounter in this namespace since a time, with each one's result: {event, ward,
/// bed, event_time, operation_key, source_message_id, ens_header_id, sent_at, receiver, outcome, reason_code?, http_status?,
/// version_after?}, in event order.
ClassMethod DeliveryRows(encounterId As %String, receiver As %String, since As %String) As %DynamicArray
{
    Set out = []
    Set sql = "SELECT w.ID AS WID, w.Event, w.Ward, w.Bed, w.EventTime, w.OperationKey, w.SourceMessageId, h.ID AS HeaderId, h.TimeCreated, h.TargetConfigName AS Receiver "
        _ "FROM Shutter_Msg.WardOperation w JOIN Ens.MessageHeader h ON h.MessageBodyId = CAST(w.ID AS VARCHAR(20)) AND h.MessageBodyClassName = 'Shutter.Msg.WardOperation' "
        _ "WHERE w.EncounterId = ? AND w.Purpose = 'normal' AND h.TimeCreated >= ? AND (? = '' OR h.TargetConfigName = ?) ORDER BY w.EventTime, w.ID"
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, encounterId, since, receiver, receiver)
    While rs.%Next() {
        Set ev = {}
        Set ev."event" = rs.%Get("Event"), ev.ward = rs.%Get("Ward"), ev.bed = rs.%Get("Bed"), ev."event_time" = rs.%Get("EventTime")
        Set ev."operation_key" = rs.%Get("OperationKey"), ev."source_message_id" = rs.%Get("SourceMessageId")
        Set ev."ens_header_id" = rs.%Get("HeaderId"), ev."sent_at" = rs.%Get("TimeCreated"), ev.receiver = rs.%Get("Receiver")
        Set ev.outcome = "unknown"
        Set r = ..ResultFor(rs.%Get("HeaderId"))
        If $ISOBJECT(r) {
            Set ev.outcome = r.Outcome, ev."reason_code" = r.ReasonCode, ev."http_status" = r.HttpStatus
            If r.EncounterVersion '= "" Set ev."version_after" = r.EncounterVersion
        }
        Do out.%Push(ev)
    }
    Quit out
}

/// The connector's answer to a ward operation's header, or "".
ClassMethod ResultFor(headerId As %String) As Shutter.Msg.WardResult
{
    Set rid = ""
    &sql(SELECT TOP 1 MessageBodyId INTO :rid FROM Ens.MessageHeader WHERE CorrespondingMessageId = :headerId AND MessageBodyClassName = 'Shutter.Msg.WardResult')
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ##class(Shutter.Msg.WardResult).%OpenId(rid)
}

/// The body of the receiver's answer to the newest delivery of the case's operation to its receiver (v1.28: the 409
/// bed_occupied refusal with its occupant), as the connector recorded it; "" when none is recorded or it is not JSON.
ClassMethod LastRefusal(case As Shutter.Store.Case) As %DynamicObject
{
    Set body = ..LastRefusalHere(case.OperationKey, case.Receiver)
    // A case forwarded from another production (CONTRACTS 11): the connector that met the refusal ran in that production's
    // namespace, so its recorded response is there (v1.34).
    If '$ISOBJECT(body) && (case.SourceNamespace '= "") && (case.SourceNamespace '= $NAMESPACE) Set body = ..LastRefusalIn(case.SourceNamespace, case.OperationKey, case.Receiver)
    Quit body
}

/// LastRefusalHere in another namespace, which must hold Shutter's message classes (a watched production's does).
ClassMethod LastRefusalIn(namespace As %String, key As %String, receiver As %String) As %DynamicObject
{
    Set body = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = namespace
        Set body = ..LastRefusalHere(key, receiver)
    } Catch ex {
        Set body = ""
    }
    Quit body
}

/// The refusal recorded in this namespace for an operation key, as LastRefusal reads it.
ClassMethod LastRefusalHere(key As %String, receiver As %String) As %DynamicObject
{
    Set sql = "SELECT TOP 1 h.ID AS HeaderId FROM Shutter_Msg.WardOperation w JOIN Ens.MessageHeader h ON h.MessageBodyId = CAST(w.ID AS VARCHAR(20)) AND h.MessageBodyClassName = 'Shutter.Msg.WardOperation' "
        _ "WHERE w.OperationKey = ? AND w.Purpose = 'normal' AND (? = '' OR h.TargetConfigName = ?) ORDER BY w.ID DESC"
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, key, receiver, receiver)
    If 'rs.%Next() Quit ""
    Set r = ..ResultFor(rs.%Get("HeaderId"))
    If '$ISOBJECT(r) || (r.ResponseJSON = "") Quit ""
    Set body = ##class(Shutter.Util.Json).Parse(r.ResponseJSON, .sc)
    If '$ISOBJECT(body) || $$$ISERR(sc) || 'body.%IsA("%Library.DynamicObject") Quit ""
    Quit body
}

}
