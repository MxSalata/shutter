/// The operations for an encounter (CONTRACTS 8.2): what the feed sent through Shutter's own typed messages, each
/// with its delivery outcome, and what the exact index knows besides, from HL7 messages on routes whose delivery
/// Shutter does not watch, with outcome unknown. The evidence collector puts the result in the snapshot; the gate
/// and the matcher count only applied outcomes, so an indexed message never supersedes a case by itself: the
/// receiver's own history decides that.
Class Shutter.Index.Timeline
{

/// The timeline for a case: the feed's operations for its encounter since the last reset, then the index's rows the
/// feed did not carry, merged by event time.
ClassMethod ForCase(case As Shutter.Store.Case) As %DynamicArray
{
    Set resetAt = $GET(^Shutter.Config("resetAt"))
    Set since = $SELECT(resetAt = "": "2000-01-01 00:00:00", 1: $TRANSLATE($PIECE(resetAt, "Z", 1), "T", " "))
    Set out = ..Typed(case, since)
    Set extra = ..FromIndex(case, since, out)
    If extra.%Size() = 0 Quit out
    Quit ..Merge(out, extra)
}

/// The feed's operations for the encounter, oldest event first, with the delivery outcome the connector recorded.
ClassMethod Typed(case As Shutter.Store.Case, since As %String) As %DynamicArray
{
    Set out = []
    Set sql = "SELECT w.ID AS WID, w.Event, w.Ward, w.EventTime, w.OperationKey, w.SourceMessageId, h.ID AS HeaderId, h.SessionId, h.TimeCreated "
        _ "FROM Shutter_Msg.WardOperation w JOIN Ens.MessageHeader h ON h.MessageBodyId = CAST(w.ID AS VARCHAR(20)) AND h.MessageBodyClassName = 'Shutter.Msg.WardOperation' "
        _ "WHERE w.EncounterId = ? AND w.Purpose = 'normal' AND h.TimeCreated >= ? ORDER BY w.EventTime, w.ID"
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, case.EncounterId, since)
    While rs.%Next() {
        Set ev = {}
        Set ev."event" = rs.%Get("Event"), ev.ward = rs.%Get("Ward"), ev."event_time" = rs.%Get("EventTime")
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

}
