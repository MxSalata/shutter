/// The occupied bed (CONTRACTS 6.1 and 9, v1.28): from the receiver's refusal, the occupant's encounter as read now and the
/// feed's deliveries for that encounter, who holds the bed and whether they are leaving. Pure functions of what was read, so a
/// test runs them without a receiver; the evidence collector reads and calls Build. The occupant is named by their encounter
/// id only, which the model view replaces by a token; no demographic of theirs is read or kept.
Class Shutter.Util.BedConflict
{

/// {refused, ward, bed, since, occupant: {encounter_id, version, read_http_status, state?, ward?, bed?} | null,
/// occupant_movement: {event, ward, bed, event_time, operation_key, delivery, outcome?, case_id?} | null, status, note}.
/// status: occupant_left (the occupant's encounter is discharged or placed elsewhere now; the movement is the history's),
/// occupant_leaving (a transfer or discharge of the occupant after since was sent and not applied: failed, uncertain or still
/// pending, in another case when one was opened for it), occupant_staying (the occupant still holds the bed and no movement
/// out is known), unknown (the refusal named no occupant, or the occupant could not be read).
ClassMethod Build(refusal As %DynamicObject, caseWard As %String, caseBed As %String, occupantRead As %DynamicObject, readStatus As %Integer, deliveries As %DynamicArray) As %DynamicObject
{
    Set json = "Shutter.Util.Json"
    Set out = {}
    Do out.%Set("refused", 1, "boolean")
    Set ward = $SELECT($ISOBJECT(refusal): $CLASSMETHOD(json, "Str", refusal, "ward"), 1: "")
    Set bed = $SELECT($ISOBJECT(refusal): $CLASSMETHOD(json, "Str", refusal, "bed"), 1: "")
    Set out.ward = $SELECT(ward '= "": ward, 1: caseWard), out.bed = $SELECT(bed '= "": bed, 1: caseBed)
    Set occ = $SELECT($ISOBJECT(refusal): refusal.%Get("occupant"), 1: "")
    Set occId = $SELECT($ISOBJECT(occ): $CLASSMETHOD(json, "Str", occ, "encounter_id"), 1: "")
    Set out.since = $SELECT($ISOBJECT(occ): $CLASSMETHOD(json, "Str", occ, "since"), 1: "")
    Do out.%Set("occupant_movement", "", "null")
    If occId = "" {
        Do out.%Set("occupant", "", "null")
        Set out.status = "unknown", out.note = "The refusal named no occupant, so nothing is known about who holds the bed"
        Quit out
    }
    Set o = {}
    Set o."encounter_id" = occId
    Set v = $CLASSMETHOD(json, "Str", occ, "version")
    If v '= "" Do o.%Set("version", +v, "number")
    Do o.%Set("read_http_status", +readStatus, "number")
    Set out.occupant = o
    If (+readStatus '= 200) || '$ISOBJECT(occupantRead) {
        Set out.status = "unknown", out.note = "The occupant's encounter could not be read (HTTP " _ +readStatus _ "), so whether they are leaving is not known"
        Quit out
    }
    Set o.state = $CLASSMETHOD(json, "Str", occupantRead, "state"), o.ward = $CLASSMETHOD(json, "Str", occupantRead, "ward"), o.bed = $CLASSMETHOD(json, "Str", occupantRead, "bed")
    Set rv = $CLASSMETHOD(json, "Str", occupantRead, "version")
    If rv '= "" Do o.%Set("version", +rv, "number")
    // Left: discharged, or no longer in the refused bed (another ward, another bed, or a ward-level placement now).
    Set gone = (o.state = "discharged") || ((out.ward '= "") && (o.ward '= out.ward)) || ((out.bed '= "") && (o.bed '= out.bed))
    If gone {
        Set mv = ..LastApplied(occupantRead, out.since)
        If $ISOBJECT(mv) Set out."occupant_movement" = mv
        Set out.status = "occupant_left"
        Set out.note = "The occupant's encounter is " _ $SELECT(o.state = "discharged": "discharged", 1: "placed in " _ o.ward _ $SELECT(o.bed '= "": " bed " _ o.bed, 1: "")) _ " now, so the bed is free of them"
        Quit out
    }
    // Leaving: a transfer or discharge of the occupant sent after since and not applied.
    Set mv = ..UnappliedMovement(deliveries, out.since)
    If $ISOBJECT(mv) {
        Set out."occupant_movement" = mv
        Set out.status = "occupant_leaving"
        Set out.note = "The occupant's " _ mv.event _ $SELECT(mv.ward '= "": " to " _ mv.ward, 1: "") _ " was sent and " _ $CASE(mv.delivery, "pending": "has no answer yet", "uncertain": "its outcome is uncertain", : "was not applied (" _ $CLASSMETHOD(json, "Str", mv, "outcome", mv.delivery) _ ")") _ $SELECT(mv.%IsDefined("case_id"): "; case " _ mv."case_id" _ " is about it", 1: "")
        Quit out
    }
    Set out.status = "occupant_staying"
    Set out.note = "The occupant's encounter still holds the bed and no movement out of it is known"
    Quit out
}

/// The newest transfer or discharge in the occupant's history after since, as the movement that freed the bed; "" when the
/// history shows none (then the state alone says they left).
ClassMethod LastApplied(occupantRead As %DynamicObject, since As %String) As %DynamicObject
{
    Set json = "Shutter.Util.Json"
    Set history = occupantRead.%Get("history")
    If '$ISOBJECT(history) || 'history.%IsA("%Library.DynamicArray") Quit ""
    Set best = ""
    Set hi = history.%GetIterator()
    While hi.%GetNext(, .h) {
        Continue:'$ISOBJECT(h)
        Set e = $CLASSMETHOD(json, "Str", h, "event")
        Continue:((e '= "transfer") && (e '= "discharge"))
        Set t = $CLASSMETHOD(json, "Str", h, "event_time")
        Continue:((since '= "") && '(t ]] since))
        Set best = h
    }
    If '$ISOBJECT(best) Quit ""
    Set mv = {}
    Set mv.event = $CLASSMETHOD(json, "Str", best, "event"), mv.ward = $CLASSMETHOD(json, "Str", best, "ward"), mv.bed = $CLASSMETHOD(json, "Str", best, "bed")
    Set mv."event_time" = $CLASSMETHOD(json, "Str", best, "event_time"), mv."operation_key" = $CLASSMETHOD(json, "Str", best, "operation_key")
    Set mv.delivery = "applied"
    Quit mv
}

/// The first transfer or discharge of the occupant after since whose delivery was not applied: failed (refused, unavailable,
/// an error), uncertain, or pending (no answer recorded yet). The row's outcome word is kept beside the normalised delivery.
ClassMethod UnappliedMovement(deliveries As %DynamicArray, since As %String) As %DynamicObject
{
    Set json = "Shutter.Util.Json"
    If '$ISOBJECT(deliveries) || 'deliveries.%IsA("%Library.DynamicArray") Quit ""
    Set di = deliveries.%GetIterator()
    While di.%GetNext(, .row) {
        Continue:'$ISOBJECT(row)
        Set e = $CLASSMETHOD(json, "Str", row, "event")
        Continue:((e '= "transfer") && (e '= "discharge"))
        Set t = $CLASSMETHOD(json, "Str", row, "event_time")
        Continue:((since '= "") && '(t ]] since))
        Set outcome = $CLASSMETHOD(json, "Str", row, "outcome")
        Continue:((outcome = "applied") || (outcome = "already_committed"))
        Set mv = {}
        Set mv.event = e, mv.ward = $CLASSMETHOD(json, "Str", row, "ward"), mv.bed = $CLASSMETHOD(json, "Str", row, "bed")
        Set mv."event_time" = t, mv."operation_key" = $CLASSMETHOD(json, "Str", row, "operation_key")
        Set mv.delivery = $SELECT((outcome = "") || (outcome = "unknown"): "pending", outcome = "uncertain": "uncertain", 1: "failed")
        Set mv.outcome = $SELECT(outcome = "": "unknown", 1: outcome)
        Set caseId = $CLASSMETHOD(json, "Str", row, "case_id")
        If caseId '= "" Set mv."case_id" = caseId
        Return mv
    }
    Quit ""
}

}
