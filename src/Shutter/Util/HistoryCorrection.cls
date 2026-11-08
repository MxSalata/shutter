/// The correcting steps for a receiver that keeps the history of record (CONTRACTS 6.4 and 10, v1.23): when a failed
/// movement was overtaken by a later one the receiver applied, the record is missing a movement, and Shutter does not
/// write it (a resend into an arrival-order receiver would move the patient back), so the case escalates with a
/// checklist its team can follow. Everything here comes from the case and the snapshot summary: the missing movement,
/// the movements the receiver applied after it, the current placement and version, the receipt. Two routes, in this order:
/// the receiver's own records procedure, and the cancel-and-replay sequence Shutter.Util.HistoryDraft draws for a person to
/// send, whose structure joins these facts as sequence when the catalogue entry is passed. A cancel reaches the current
/// movement only, and a resend of the original on its own is unsafe.
Class Shutter.Util.HistoryCorrection
{

/// {receiver, system, category, encounter, missing: {event, ward, event_time, source_message_id, operation_key, after},
///  later: [{event, ward, event_time, operation_key, source_message_id, ens_header_id}], current: {state, ward, version},
///  receipt, steps: [text], sequence?}. sequence comes with the catalogue entry, and holds no message text.
ClassMethod Steps(case As Shutter.Store.Case, summary As %DynamicObject, entry As %String = "") As %DynamicObject
{
    Set json = "Shutter.Util.Json"
    Set out = {}
    Set receiver = $SELECT(case.Receiver '= "": case.Receiver, 1: "the receiver")
    Set out.receiver = receiver
    Set out.system = ##class(Shutter.Store.SiteProfile).ReceiverLabel(receiver)
    Set out.category = ##class(Shutter.Store.SiteProfile).ReceiverCategory(receiver)
    Set out.encounter = case.EncounterId
    Set missing = {}
    Set missing.event = case.Event, missing.ward = case.Ward, missing."event_time" = case.EventTime
    Set missing."source_message_id" = case.SourceMessageId, missing."operation_key" = case.OperationKey
    // The placement before the missing movement: the latest applied movement with a ward before the failed event's time.
    Set before = "", beforeTime = ""
    Set ward = $SELECT($ISOBJECT(summary): summary.%Get("ward_state"), 1: "")
    Set history = $SELECT($ISOBJECT(ward): ward.%Get("history"), 1: "")
    If $ISOBJECT(history) {
        Set hi = history.%GetIterator()
        While hi.%GetNext(, .h) {
            Set t = $CLASSMETHOD(json, "Str", h, "event_time"), w = $CLASSMETHOD(json, "Str", h, "ward")
            Continue:((w = "") || (t = ""))
            Set gap = ##class(Shutter.Util.HistoryDraft).Gap(t, case.EventTime)
            Continue:((gap = "") || (gap <= 0))
            If beforeTime = "" { Set before = w, beforeTime = t } Else {
                Set newer = ##class(Shutter.Util.HistoryDraft).Gap(beforeTime, t)
                If (newer '= "") && (newer > 0) Set before = w, beforeTime = t
            }
        }
    }
    Set missing.after = before
    Set out.missing = missing
    // The movements the receiver applied after it, in time order, as the matcher reads them.
    Set later = [], seen = ""
    Try {
        Set events = ##class(Shutter.Catalogue.Matcher).Later(summary, case, "single")
        Set li = events.%GetIterator()
        While li.%GetNext(, .e) {
            Continue:'$CLASSMETHOD(json, "Bool", e, "delivered", 1)
            // The matcher reads the same movement from the timeline, the history and the index, whose times can differ in form
            // (an offset, fractional seconds) or by the receiver's clock: the same event to the same ward within a minute is
            // one movement.
            Set row = {}
            Set row.event = $CLASSMETHOD(json, "Str", e, "event"), row.ward = $CLASSMETHOD(json, "Str", e, "ward"), row."event_time" = $CLASSMETHOD(json, "Str", e, "event_time")
            Continue:..SameMovement(later, row)
            Set key = $CLASSMETHOD(json, "Str", e, "operation_key"), row."operation_key" = key
            Set feed = ..FeedRow(summary, key)
            Set row."source_message_id" = $CLASSMETHOD(json, "Str", feed, "source_message_id"), row."ens_header_id" = $CLASSMETHOD(json, "Str", feed, "ens_header_id")
            Do later.%Push(row)
        }
    } Catch ex {
    }
    Set out.later = later
    Set current = {}
    Set current.state = $SELECT($ISOBJECT(ward): $CLASSMETHOD(json, "Str", ward, "state"), 1: ""), current.ward = $SELECT($ISOBJECT(ward): $CLASSMETHOD(json, "Str", ward, "ward"), 1: "")
    Set current.version = $SELECT($ISOBJECT(ward): $CLASSMETHOD(json, "Str", ward, "version"), 1: "")
    Set out.current = current
    Set rstatus = $SELECT($ISOBJECT(summary): $CLASSMETHOD(json, "Str", summary, "receipt_http_status"), 1: "")
    Set out.receipt = $SELECT(rstatus = 200: "present", rstatus = 404: "absent", rstatus = -1: "none", rstatus = "": "unknown", 1: "unreadable")
    Set out.steps = ..Checklist(out)
    If entry '= "" Set out.sequence = ##class(Shutter.Util.HistoryDraft).Sequence(case, summary, entry)
    Quit out
}

/// The snapshot's timeline row for an operation key, or "".
ClassMethod FeedRow(summary As %DynamicObject, key As %String) As %DynamicObject [ Private ]
{
    Set timeline = $SELECT($ISOBJECT(summary): summary.%Get("timeline"), 1: "")
    If (key = "") || '$ISOBJECT(timeline) Quit ""
    Set ti = timeline.%GetIterator()
    While ti.%GetNext(, .t) { If $ISOBJECT(t) && (##class(Shutter.Util.Json).Str(t, "operation_key") = key) Return t }
    Quit ""
}

/// The checklist, in order, in plain words; every value comes from the facts above.
/// Whether a movement is already in the list: the same event to the same ward within 60 seconds.
ClassMethod SameMovement(list As %DynamicArray, row As %DynamicObject) As %Boolean
{
    Set li = list.%GetIterator()
    While li.%GetNext(, .k) {
        Continue:((k.event '= row.event) || (k.ward '= row.ward))
        If k."event_time" = row."event_time" Return 1
        Set gap = ""
        Try { Set gap = ##class(Shutter.Util.Time).SecondsBetween(k."event_time", row."event_time") } Catch { Set gap = "" }
        If (gap '= "") && ($ZABS(gap) <= 60) Return 1
    }
    Quit 0
}

ClassMethod Checklist(f As %DynamicObject) As %DynamicArray [ Private ]
{
    Set json = "Shutter.Util.Json"
    Set steps = []
    Set m = f.%Get("missing"), cur = f.%Get("current")
    Set movement = $CLASSMETHOD(json, "Str", m, "event") _ $SELECT($CLASSMETHOD(json, "Str", m, "ward") '= "": " to " _ $CLASSMETHOD(json, "Str", m, "ward"), 1: "") _ " at " _ $CLASSMETHOD(json, "Str", m, "event_time")
    Set placement = $SELECT($CLASSMETHOD(json, "Str", cur, "ward") '= "": $CLASSMETHOD(json, "Str", cur, "ward"), $CLASSMETHOD(json, "Str", cur, "state") '= "": $CLASSMETHOD(json, "Str", cur, "state"), 1: "unknown")
    Do steps.%Push("Hold the case: Shutter has sent nothing more to " _ f.receiver _ " for this message and will not. Do not resend the original message: an arrival-order receiver would move the patient back to " _ $SELECT($CLASSMETHOD(json, "Str", m, "ward") '= "": $CLASSMETHOD(json, "Str", m, "ward"), 1: "the earlier place") _ ".")
    Do steps.%Push("In " _ f.system _ ", open encounter " _ f.encounter _ " and confirm, reading only, that the current placement is " _ placement _ $SELECT($CLASSMETHOD(json, "Str", cur, "version") '= "": " at version " _ $CLASSMETHOD(json, "Str", cur, "version"), 1: "") _ ".")
    Set laterText = "", li = f.%Get("later").%GetIterator()
    While li.%GetNext(, .e) { Set laterText = laterText _ $SELECT(laterText = "": "", 1: ", then ") _ $CLASSMETHOD(json, "Str", e, "event") _ $SELECT($CLASSMETHOD(json, "Str", e, "ward") '= "": " to " _ $CLASSMETHOD(json, "Str", e, "ward"), 1: "") _ " at " _ $CLASSMETHOD(json, "Str", e, "event_time") }
    Do steps.%Push("Confirm that the movement history is missing the " _ movement _ " (source message " _ $CLASSMETHOD(json, "Str", m, "source_message_id") _ ")" _ $SELECT($CLASSMETHOD(json, "Str", m, "after") '= "": ", which belongs after the placement in " _ $CLASSMETHOD(json, "Str", m, "after"), 1: "") _ $SELECT(laterText '= "": " and before the " _ laterText _ " that applied", 1: "") _ ".")
    Do steps.%Push("Have the correction approved by the person the site names for " _ f.receiver _ " before anything is changed; record who approved it.")
    Do steps.%Push("Correct the " _ movement _ " in the record through the receiver's own records procedure, citing source message " _ $CLASSMETHOD(json, "Str", m, "source_message_id") _ ". One write, by one person. If the receiver has no such procedure, the sequence drafted on this case, where one is drawn, is the other route; it needs the receiver to take cancels, and it deletes the later movements before replaying them.")
    Do steps.%Push("Under its own procedure the current placement " _ placement _ " stays as it is: no movement after " _ $CLASSMETHOD(json, "Str", m, "event_time") _ " changes, and the version moves on only by this correction. The drafted sequence does change it, twice per later movement, and says so.")
    Do steps.%Push("Read the history back and check the order of the movements by their times and the current placement; have a second person check it too.")
    Do steps.%Push("Record what was done on the Shutter case (" _ $SELECT(f.receipt = "present": "the receiver already holds a receipt for the failed key; leave it", 1: "the receiver holds no receipt for the failed key, and none is needed") _ ") and close the case by hand: Shutter verifies nothing for a history correction.")
    Quit steps
}

/// One line for a note: what is missing and how many steps there are.
ClassMethod Headline(f As %DynamicObject) As %String
{
    Set json = "Shutter.Util.Json"
    Set m = f.%Get("missing")
    Quit "the " _ $CLASSMETHOD(json, "Str", m, "event") _ $SELECT($CLASSMETHOD(json, "Str", m, "ward") '= "": " to " _ $CLASSMETHOD(json, "Str", m, "ward"), 1: "") _ " at " _ $CLASSMETHOD(json, "Str", m, "event_time") _ " is missing from the history " _ f.receiver _ " keeps; " _ f.%Get("steps").%Size() _ " steps for its team are on the plan"
}

}
