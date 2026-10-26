/// The deterministic matcher (CONTRACTS 6.1 and 6.3): computes the condition vocabulary from a case's evidence
/// snapshot and finds the catalogue entries whose pattern holds. No model. Runs when the evidence is collected;
/// its result is the snapshot summary's "catalogue" item, which the workflow, the gate and the app read.
/// Since T31 (CONTRACTS v1.14) the vocabulary has "event" (the failed operation's event word, the three cancels folded
/// to cancel), "delivery" takes "withheld" (an operation Shutter never sent: a merge under the site's policy, a cancel
/// the receiver cannot reverse) with "receiver_answer: none", and "later_applied" takes "cancelled" and "merge". Since v1.21
/// "later_delivery" says how the event that gave later_applied its word reached the receiver (applied, or only sent).
Class Shutter.Catalogue.Matcher
{

/// The conditions a snapshot summary shows for a case (every name of 6.1, each with its observed value).
ClassMethod Conditions(case As Shutter.Store.Case, summary As %DynamicObject, chainKind As %String = "single") As %DynamicObject
{
    Set c = {}
    Set json = "Shutter.Util.Json"
    // delivery
    Set c.delivery = $CASE(case.FailureKind, "delivery_failed": "failed", "rejected": "rejected", "uncertain_outcome": "uncertain", : "failed")
    If case.FailureKind = "unmappable" Set c.delivery = "unmappable"
    If case.FailureKind = "withheld" Set c.delivery = "withheld"
    // receiver_answer, from the error item's reason code and status
    Set error = ..Item(summary, "error")
    Set reason = $ZCONVERT($SELECT($ISOBJECT(error): $CLASSMETHOD(json, "Str", error, "reason_code"), 1: ""), "L")
    Set status = $SELECT($ISOBJECT(error): $CLASSMETHOD(json, "Str", error, "http_status"), 1: "")
    Set c."receiver_answer" = $SELECT(reason [ "unavailable": "unavailable", (reason [ "timeout") || (status = 504): "timeout", reason [ "duplicate": "duplicate", reason [ "version": "version_conflict", (reason '= "") || (status = 422) || (status = 409): "refused", status = 503: "unavailable", 1: "none")
    If (c."receiver_answer" = "none") && (c.delivery = "uncertain") Set c."receiver_answer" = "timeout"
    // A withheld operation was never sent, so no receiver answered (T31).
    If c.delivery = "withheld" Set c."receiver_answer" = "none"
    // event (T31): the failed operation's event word; cancel_admit, cancel_transfer and cancel_discharge fold to cancel
    Set c.event = $SELECT($EXTRACT(case.Event, 1, 7) = "cancel_": "cancel", $LISTFIND($LISTBUILD("admit", "transfer", "discharge", "update", "merge"), case.Event): case.Event, 1: "other")
    // receipt
    Set rstatus = $CLASSMETHOD(json, "Str", summary, "receipt_http_status")
    Set c.receipt = $SELECT(rstatus = 200: "present", rstatus = 404: "absent", rstatus = -1: "none", 1: "unreadable")
    // later_applied: the latest later event (applied, or outside a chain a later transfer that failed too), from the
    // timeline and the receiver's history (Later, which the gate's ordering check reads too)
    Set later = ..Later(summary, case, chainKind)
    Set c."later_applied" = ..LaterApplied(summary, case, later)
    // later_delivery (v1.21): whether that event reached the receiver, or was only sent (the undelivered later transfer)
    Set c."later_delivery" = ..LaterDelivery(later, c."later_applied")
    // event_time (T28): the failed event's time against the admission, the message, the recording time and the clock,
    // and the times of the later events it is ordered against
    Set c."event_time" = ..EventTimePlausibility(summary, case, later)
    // encounter_state and the identity
    Set ward = summary.%Get("ward_state"), wstatus = $CLASSMETHOD(json, "Str", summary, "ward_state_http_status")
    Set state = $SELECT((wstatus = 200) && $ISOBJECT(ward): $CLASSMETHOD(json, "Str", ward, "state"), 1: "")
    // A 404 is its own state: the receiver answered, and does not know the encounter (C6).
    Set c."encounter_state" = $SELECT(wstatus = 404: "not_found", state = "": "unknown", 1: state)
    Set op = summary.%Get("operation")
    If wstatus = 200 {
        Set same = ($CLASSMETHOD(json, "Str", ward, "patient_id") = case.PatientId) && ($CLASSMETHOD(json, "Str", ward, "patient_id_authority") = case.PatientIdAuthority)
        Set c."patient_match" = $SELECT(same: "yes", 1: "no")
    } Else {
        Set c."patient_match" = "unknown"
    }
    // transition: the failed event from the receiver's current state
    If wstatus = 200 {
        Set c.transition = $SELECT(case.Event = "admit": "invalid", case.Event = "merge": $SELECT(state '= "": "allowed", 1: "invalid"), case.Event = "cancel_discharge": $SELECT(state = "discharged": "allowed", 1: "invalid"), state = "admitted": "allowed", 1: "invalid")
    } ElseIf (wstatus = 404) && (case.Event = "admit") {
        Set c.transition = "allowed"
    } Else {
        Set c.transition = "unknown"
    }
    // simultaneous_sources: an applied event for the encounter at the same time from another source
    Set c."simultaneous_sources" = ..SimultaneousSource(summary, case)
    // conditional_writes, from the route's capability profile
    Set route = summary.%Get("route")
    Set caps = $SELECT($ISOBJECT(route): route.%Get("capabilities"), 1: "")
    If $ISOBJECT(caps) && (caps.%GetTypeOf("conditional_writes") '= "unassigned") {
        Set c."conditional_writes" = $SELECT($CLASSMETHOD(json, "Bool", caps, "conditional_writes"): "yes", 1: "no")
    } Else {
        Set c."conditional_writes" = "unknown"
    }
    // free_text: notes in the message
    Set msg = summary.%Get("message")
    Set notes = $SELECT($ISOBJECT(msg): msg.%Get("notes"), 1: "")
    Set c."free_text" = $SELECT($ISOBJECT(notes) && (notes.%Size() > 0): "yes", 1: "no")
    Set c.chain = $SELECT(chainKind = "": "single", 1: chainKind)
    // receiver_category (v1.23): what kind of system the case's receiver is, from its site profile entry
    Set c."receiver_category" = ##class(Shutter.Store.SiteProfile).ReceiverCategory(case.Receiver)
    Quit c
}

/// Match the conditions against every catalogue entry (6.3). Returns the result the summary carries.
ClassMethod Match(conditions As %DynamicObject, facts As %DynamicObject = "") As %DynamicObject
{
    Set out = {}
    Set out.conditions = conditions
    Set out.facts = $SELECT($ISOBJECT($GET(facts)): facts, 1: {"other_source": ""})
    Set out."catalogue_version" = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    Set matches = []
    If ##class(Shutter.Catalogue.Entry).Count() = 0 {
        Set out.matches = matches, out.decision = "not_configured"
        Do out.%Set("entry", "", "null"), out.%Set("outcome", "", "null")
        Quit out
    }
    Set entries = ##class(Shutter.Catalogue.Entry).All()
    Set iter = entries.%GetIterator()
    While iter.%GetNext(.i, .e) {
        If ..Holds(e.%Get("pattern"), conditions) {
            Set m = {}
            Set m.id = e.id, m.version = e.version, m.title = e.title, m.decides = e.decides
            If e.%IsDefined("prose") Set m.prose = e.prose
            Set m.preferred = e.%Get("preferred"), m.alternatives = e.%Get("alternatives")
            Do matches.%Push(m)
        }
    }
    Set out.matches = matches
    If matches.%Size() = 0 {
        Set out.decision = "new_pattern"
        Do out.%Set("entry", "", "null"), out.%Set("outcome", "", "null")
    } ElseIf matches.%Size() > 1 {
        Set out.decision = "board"
        Do out.%Set("entry", "", "null"), out.%Set("outcome", "", "null")
    } Else {
        Set m = matches.%Get(0)
        Set decides = ##class(Shutter.Util.Json).Str(m, "decides", "board")
        Set out.decision = $SELECT($LISTFIND($LISTBUILD("policy", "board", "person"), decides): decides, 1: "board")
        Set out.entry = m.id
        Set pref = m.%Get("preferred")
        Set out.outcome = $SELECT($ISOBJECT(pref): ##class(Shutter.Util.Json).Str(pref, "outcome"), 1: ""), out."outcome_ref" = "preferred"
        // A site-policy alternative (v1.25): an alternative whose when names a flag (history_policy, authoritative_source,
        // unconditional_resend) that holds for this case's receiver applies instead of the preferred outcome, as the entry
        // says it should when the site or the receiver chooses so. "always" is a board option, not a policy.
        Set alts = m.%Get("alternatives")
        If $ISOBJECT(alts) {
            Set ai = alts.%GetIterator()
            While ai.%GetNext(.n, .alt) {
                Continue:'$ISOBJECT(alt)
                Set when = $ZSTRIP(##class(Shutter.Util.Json).Str(alt, "when"), "<>W")
                Continue:((when = "") || (when = "always") || (when '[ ":"))
                If ..WhenHolds(when, out.facts) Set out.outcome = ##class(Shutter.Util.Json).Str(alt, "outcome"), out."outcome_ref" = "alternative:" _ (n + 1) Quit
            }
        }
    }
    Quit out
}

/// Whether a pattern holds: every listed condition's observed value is among the allowed ones.
ClassMethod Holds(pattern As %DynamicObject, conditions As %DynamicObject) As %Boolean
{
    If '$ISOBJECT(pattern) Quit 0
    Set iter = pattern.%GetIterator()
    While iter.%GetNext(.name, .allowed) {
        Set observed = ##class(Shutter.Util.Json).Str(conditions, name)
        If $ISOBJECT(allowed) {
            Set ok = 0
            Set it2 = allowed.%GetIterator()
            While it2.%GetNext(.j, .v) { If ("" _ v) = observed Set ok = 1 Quit }
            If 'ok Return 0
        } Else {
            If ("" _ allowed) '= observed Return 0
        }
    }
    Quit 1
}

/// The later events for the encounter (Later: applied ones, and outside a chain a later transfer whose delivery failed
/// or is uncertain as well), by precedence (CONTRACTS 6.1): cancelled (an applied cancel at or after the failed event's
/// time, T31), else merge (an applied merge, T31), else discharge, else transfer, else admit (a later admission, T28),
/// else update, else none. (A later transfer followed by a later update is a transfer.) A cancel counts from the failed
/// event's own time, not strictly after it, because a cancel carries the time of the event it reverses; the case's own
/// operation never counts. Only the events whose time is plausible count.
ClassMethod LaterApplied(summary As %DynamicObject, case As Shutter.Store.Case, later As %DynamicArray = "") As %String [ Private ]
{
    If '$ISOBJECT(later) Set later = ..Later(summary, case)
    // A later admission is its own answer (T28): an encounter admitted again after the failed event is not an update.
    // So are a cancel and a merge (T31); any other word the receiver or the index reports still reads as an update.
    Set seen("cancelled") = 0, seen("merge") = 0, seen("discharge") = 0, seen("transfer") = 0, seen("update") = 0, seen("admit") = 0
    Set iter = later.%GetIterator()
    While iter.%GetNext(.i, .ev) {
        Continue:'ev.plausible
        Set seen(ev.word) = 1
    }
    Quit $SELECT(seen("cancelled"): "cancelled", seen("merge"): "merge", seen("discharge"): "discharge", seen("transfer"): "transfer", seen("admit"): "admit", seen("update"): "update", 1: "none")
}

/// The events for the encounter that bear on the failed operation's order, from the snapshot's timeline and the
/// receiver's history, each as {word, event, ward, event_time, from (timeline or history), delivered, plausible,
/// operation_key, and case_id when a case was opened for that key (v1.21)}. later_applied, the gate's ordering check
/// (Shutter.Operation.Gate) and the verifier's superseded branch (Shutter.Operation.Verify) all read them, so they agree.
/// - An applied (or already committed) event whose time is later than the failed event's; a cancel from the failed
///   event's own time on (T31), never the case's own operation. word is the precedence word (cancelled, merge,
///   discharge, transfer, admit, update).
/// - Outside a chain, also a later transfer the feed sent whose delivery failed or is uncertain as well (delivered 0):
///   it is the PAS's later word on where the patient is, and its own case delivers it, so resending the earlier
///   movement would only take the patient back. An admission is never overtaken, and in an ordered or interleaved chain
///   the incident sends the chain's failures in event order (CONTRACTS 7), so neither counts such an event. A later
///   discharge that failed does not count either: resending the earlier movement does no harm, since the discharge's
///   own case follows it, and no catalogue entry covers a discharge the receiver has not applied (the encounter is
///   still admitted there). A message the index found on another route has no known outcome and counts only once the
///   receiver's history shows it.
/// - plausible is 0 when the event's time lies more than five minutes after the feed sent it, the receiver applied it
///   or the evidence was taken (the rule event_time applies to the failed event's own time): such a time settles no
///   order.
ClassMethod Later(summary As %DynamicObject, case As Shutter.Store.Case, chainKind As %String = "single") As %DynamicArray
{
    Set out = [], json = "Shutter.Util.Json"
    Set observed = $CLASSMETHOD(json, "Str", summary, "observed_at")
    Set failedCount = ((chainKind = "") || (chainKind = "single")) && (case.Event '= "admit")
    Set words = $LISTBUILD("merge", "discharge", "transfer", "admit", "update")
    Set timeline = summary.%Get("timeline")
    If $ISOBJECT(timeline) {
        Set iter = timeline.%GetIterator()
        While iter.%GetNext(.i, .ev) {
            Continue:'$ISOBJECT(ev)
            Set outcome = $CLASSMETHOD(json, "Str", ev, "outcome"), e = $CLASSMETHOD(json, "Str", ev, "event")
            Set t = $CLASSMETHOD(json, "Str", ev, "event_time"), key = $CLASSMETHOD(json, "Str", ev, "operation_key")
            Set delivered = (outcome = "applied") || (outcome = "already_committed")
            If $EXTRACT(e, 1, 7) = "cancel_" {
                Continue:'delivered
                Continue:'..AtOrAfter(t, key, case)
                Set word = "cancelled"
            } Else {
                Continue:'$CLASSMETHOD(json, "Bool", ev, "later")
                If 'delivered {
                    // A failure the connector recorded for a message the feed sent, not one still in flight.
                    Continue:'failedCount
                    Continue:(($CLASSMETHOD(json, "Str", ev, "source") '= "feed") || (outcome = "") || (outcome = "unknown"))
                    Continue:(e '= "transfer")
                    Continue:((key = case.OperationKey) || $CLASSMETHOD(json, "Bool", ev, "this_case"))
                }
                Set word = $SELECT($LISTFIND(words, e): e, 1: "update")
            }
            Set ok = ..PlausibleLater(t, ..AsUTC($CLASSMETHOD(json, "Str", ev, "sent_at")), observed)
            Do out.%Push(..LaterEvent(word, e, $CLASSMETHOD(json, "Str", ev, "ward"), t, "timeline", delivered, ok, key))
        }
    }
    Set ward = summary.%Get("ward_state")
    Set history = $SELECT($ISOBJECT(ward): ward.%Get("history"), 1: "")
    If $ISOBJECT(history) {
        Set iter = history.%GetIterator()
        While iter.%GetNext(.i, .h) {
            Continue:'$ISOBJECT(h)
            Set t = $CLASSMETHOD(json, "Str", h, "event_time"), e = $CLASSMETHOD(json, "Str", h, "event")
            If $EXTRACT(e, 1, 7) = "cancel_" {
                Continue:'..AtOrAfter(t, $CLASSMETHOD(json, "Str", h, "operation_key"), case)
                Set word = "cancelled"
            } Else {
                Continue:'(t ]] case.EventTime)
                Set word = $SELECT($LISTFIND(words, e): e, 1: "update")
            }
            Set ok = ..PlausibleLater(t, ..AsUTC($CLASSMETHOD(json, "Str", h, "applied_at")), observed)
            Do out.%Push(..LaterEvent(word, e, $CLASSMETHOD(json, "Str", h, "ward"), t, "history", 1, ok, $CLASSMETHOD(json, "Str", h, "operation_key")))
        }
    }
    Quit out
}

ClassMethod LaterEvent(word As %String, event As %String, ward As %String, time As %String, from As %String, delivered As %Boolean, plausible As %Boolean, key As %String = "") As %DynamicObject [ Private ]
{
    Set o = {}
    Set o.word = word, o.event = event, o.ward = ward, o."event_time" = time, o.from = from
    Do o.%Set("delivered", ''delivered, "boolean"), o.%Set("plausible", ''plausible, "boolean")
    Set o."operation_key" = key
    Set caseId = ..CaseIdFor(key)
    If caseId '= "" Set o."case_id" = caseId
    Quit o
}

/// The public id of the case opened for an operation key (the latest, whatever its state), or "".
ClassMethod CaseIdFor(key As %String) As %String [ Private ]
{
    If key = "" Quit ""
    Set caseId = ""
    &sql(SELECT TOP 1 CaseId INTO :caseId FROM Shutter_Store."Case" WHERE OperationKey = :key ORDER BY ID DESC)
    If SQLCODE '= 0 Quit ""
    Quit caseId
}

/// The delivery of the event that gave later_applied its word (6.1, v1.21): applied when a plausible later event with
/// that word is in the receiver's history or was applied in the timeline, sent when the only one is a later transfer the
/// feed sent whose delivery failed or is uncertain, none when later_applied is none.
ClassMethod LaterDelivery(later As %DynamicArray, word As %String) As %String [ Private ]
{
    If (word = "none") || '$ISOBJECT(later) Quit "none"
    Set delivery = "none"
    Set iter = later.%GetIterator()
    While iter.%GetNext(.i, .ev) {
        Continue:('ev.plausible || (ev.word '= word))
        If ev.delivered Return "applied"
        Set delivery = "sent"
    }
    Quit delivery
}

/// A later event (Later) described for a person, as the gate's ordering check and the verifier word it: the event (a
/// transfer or a discharge with its ward, "cancel of the event", "merge", "admission") at its time. With withOrigin,
/// where it comes from: "(receiver history)", or for a later transfer the feed sent whose delivery failed or is
/// uncertain, the key it was sent as and the case that recovers it ("its case C-0000NN recovers it", or "its own case
/// recovers it" when none is known).
ClassMethod Describe(ev As %DynamicObject, withOrigin As %Boolean = 1) As %String
{
    Set json = "Shutter.Util.Json"
    Set word = $CLASSMETHOD(json, "Str", ev, "word"), ward = $CLASSMETHOD(json, "Str", ev, "ward")
    Set what = $CASE(word, "cancelled": "cancel of the event", "merge": "merge", "admit": "admission", : word)
    Set text = what _ $SELECT((ward '= "") && ((word = "transfer") || (word = "discharge")): " to " _ ward, 1: "") _ " at " _ $CLASSMETHOD(json, "Str", ev, "event_time")
    If 'withOrigin Quit text
    If $CLASSMETHOD(json, "Str", ev, "from") = "history" Quit text _ " (receiver history)"
    If '$CLASSMETHOD(json, "Bool", ev, "delivered") {
        Set key = $CLASSMETHOD(json, "Str", ev, "operation_key"), caseId = $CLASSMETHOD(json, "Str", ev, "case_id")
        Quit text _ $SELECT(key '= "": ", sent as " _ key, 1: "") _ " (its delivery failed or is uncertain; " _ $SELECT(caseId '= "": "its case " _ caseId _ " recovers it", 1: "its own case recovers it") _ ")"
    }
    Quit text
}

/// Whether a later event's time is plausible: no more than five minutes after the time it was sent or applied (when
/// known) and after the evidence was taken. A time that cannot be read is not; a reference time that cannot be read
/// skips its own check, as an empty one does (v1.21), so one receiver's odd clock form never makes every later event
/// implausible.
ClassMethod PlausibleLater(time As %String, sentOrApplied As %String, observed As %String) As %Boolean [ Private ]
{
    If (time '= "") && '..Readable(time) Quit 0
    Set ok = 1
    If (sentOrApplied '= "") && (time '= "") && (..Behind(sentOrApplied, time) > 300) Set ok = 0
    If (observed '= "") && (time '= "") && (..Behind(observed, time) > 300) Set ok = 0
    Quit ok
}

/// Whether an ISO UTC timestamp can be read.
ClassMethod Readable(ts As %String) As %Boolean [ Private ]
{
    Set ok = 1
    Try {
        If ##class(Shutter.Util.Time).SecondsBetween(ts, ts) '= 0 Set ok = 0
    } Catch ex {
        Set ok = 0
    }
    Quit ok
}

/// Seconds from a reference time to an event's time, or "" when the reference cannot be read.
ClassMethod Behind(reference As %String, time As %String) As %String [ Private ]
{
    Set seconds = ""
    Try {
        Set seconds = ##class(Shutter.Util.Time).SecondsBetween(reference, time)
    } Catch ex {
        Set seconds = ""
    }
    Quit seconds
}

/// A UTC timestamp as the message store or the receiver writes it, in the ISO form with a Z, to the second: from the
/// ISO form with a Z (2026-10-15T09:20:00Z, a fraction allowed) or the ODBC form the message store writes in UTC
/// (2026-10-15 09:20:00.123). "" for any other form (v1.21): a time with an offset (2026-10-15T10:20:00+01:00) or in
/// another shape is never read as UTC, and the check that would use it is skipped.
ClassMethod AsUTC(ts As %String) As %String [ Private ]
{
    If $MATCH(ts, "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z") Quit $EXTRACT(ts, 1, 19) _ "Z"
    If $MATCH(ts, "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?") Quit $EXTRACT(ts, 1, 10) _ "T" _ $EXTRACT(ts, 12, 19) _ "Z"
    Quit ""
}

/// Whether an applied event (its time and its operation key) lies at or after the failed event's time and is not the
/// case's own operation (T31: the rule for a cancel, which carries the time of the event it reverses).
ClassMethod AtOrAfter(time As %String, key As %String, case As Shutter.Store.Case) As %Boolean [ Private ]
{
    If (time = "") || (key = case.OperationKey) Quit 0
    Quit '(case.EventTime ]] time)
}

/// Whether the failed event's time is plausible (T28): before_admission when it precedes the admission the message
/// or the receiver's history names (for anything but an admission); future when it is more than five minutes after
/// the message was sent or the evidence was taken; far_from_recorded when it is more than a day from the time the
/// event was recorded (EVN-2); clock_change when it came without an offset and lies within an hour of a British clock
/// change, where the order of two events is not safe; later_event_future when the failed event's own time is sound but
/// a later event it would be ordered against (Later) lies in the future by the same five-minute rule and believing it
/// would change the reading, so a wrong time could make a genuine failure look overtaken; plausible otherwise.
ClassMethod EventTimePlausibility(summary As %DynamicObject, case As Shutter.Store.Case, later As %DynamicArray = "") As %String
{
    Set json = "Shutter.Util.Json", t = case.EventTime
    Set msg = summary.%Get("message")
    If t = "" Quit "plausible"
    If '$ISOBJECT(msg) Set msg = {}
    Set admit = $CLASSMETHOD(json, "Str", msg, "admit_time"), recorded = $CLASSMETHOD(json, "Str", msg, "event_recorded"), sent = $CLASSMETHOD(json, "Str", msg, "message_time")
    Set firstAdmit = ""
    Set ward = summary.%Get("ward_state")
    Set history = $SELECT($ISOBJECT(ward): ward.%Get("history"), 1: "")
    If $ISOBJECT(history) && (history.%Size() > 0) {
        Set first = history.%Get(0)
        If $ISOBJECT(first) && ($CLASSMETHOD(json, "Str", first, "event") = "admit") Set firstAdmit = $CLASSMETHOD(json, "Str", first, "event_time")
    }
    If case.Event '= "admit" {
        If (admit '= "") && (admit ]] t) Quit "before_admission"
        If (firstAdmit '= "") && (firstAdmit ]] t) Quit "before_admission"
    }
    Set observed = $CLASSMETHOD(json, "Str", summary, "observed_at")
    If (sent '= "") && (t ]] sent) && ($ZABS(##class(Shutter.Util.Time).SecondsBetween(sent, t)) > 300) Quit "future"
    If (observed '= "") && (t ]] observed) && ($ZABS(##class(Shutter.Util.Time).SecondsBetween(observed, t)) > 300) Quit "future"
    If (recorded '= "") && ($ZABS(##class(Shutter.Util.Time).SecondsBetween(recorded, t)) > 86400) Quit "far_from_recorded"
    If msg.%IsDefined("event_time_had_offset") && '$CLASSMETHOD(json, "Bool", msg, "event_time_had_offset") && ($CLASSMETHOD(json, "Str", msg, "feed_time_zone") = "Europe/London") && ##class(Shutter.Util.Time).NearBritishClockChange(t) Quit "clock_change"
    If '$ISOBJECT(later) Set later = ..Later(summary, case)
    Quit ..LaterTimeDoubt(summary, case, later)
}

/// later_event_future or plausible, for the later events' times. A later event whose time is not plausible is a doubt
/// only when believing it would change the reading: when no plausible later transfer, discharge or cancel settles the
/// order already, and the event outranks what the plausible ones give (by later_applied's precedence). An update never
/// is one, since it supersedes nothing. A settled order has one exception (v1.21): a cancel with a doubtful time may
/// have reversed the very transfer or discharge that settles it, so it is a doubt.
ClassMethod LaterTimeDoubt(summary As %DynamicObject, case As Shutter.Store.Case, later As %DynamicArray) As %String [ Private ]
{
    Set settled = ..LaterApplied(summary, case, later)
    Set settledOrder = $LISTFIND($LISTBUILD("cancelled", "discharge", "transfer"), settled) > 0
    Set rank = $LISTBUILD("update", "admit", "transfer", "discharge", "merge", "cancelled")
    Set iter = later.%GetIterator()
    While iter.%GetNext(.i, .ev) {
        Continue:(ev.plausible || (ev.word = "update"))
        If settledOrder {
            If (ev.word = "cancelled") && (settled '= "cancelled") Return "later_event_future"
            Continue
        }
        If $LISTFIND(rank, ev.word) > $LISTFIND(rank, settled) Return "later_event_future"
    }
    Quit "plausible"
}

/// Facts beside the conditions, for the alternatives' "when": other_source (the other source system of a
/// simultaneous event, or "").
ClassMethod Facts(summary As %DynamicObject, case As Shutter.Store.Case) As %DynamicObject
{
    Set f = {}
    Set f."other_source" = ""
    // The receiver's history policy and category (v1.23), so an entry's when reads the case's receiver, not the site
    Set f."history_policy" = ##class(Shutter.Store.SiteProfile).ReceiverHistoryPolicy(case.Receiver)
    Set f."receiver_category" = ##class(Shutter.Store.SiteProfile).ReceiverCategory(case.Receiver)
    Set ward = summary.%Get("ward_state")
    Set history = $SELECT($ISOBJECT(ward): ward.%Get("history"), 1: "")
    If $ISOBJECT(history) {
        Set source = $PIECE(case.OperationKey, "^", 1)
        Set iter = history.%GetIterator()
        While iter.%GetNext(.i, .h) {
            Continue:(##class(Shutter.Util.Json).Str(h, "event_time") '= case.EventTime)
            Set key = ##class(Shutter.Util.Json).Str(h, "operation_key")
            Continue:(key = case.OperationKey)
            If $PIECE(key, "^", 1) '= source Set f."other_source" = $PIECE(key, "^", 1) Quit
        }
    }
    Quit f
}

/// Whether an alternative's "when" holds for this site: "always", or "<flag>: <value>" against the site profile,
/// where the value "other_source" stands for the fact of that name.
ClassMethod WhenHolds(when As %String, facts As %DynamicObject) As %Boolean
{
    Set when = $ZSTRIP(when, "<>W")
    If (when = "") || (when = "always") Quit 1
    Set flag = $ZSTRIP($PIECE(when, ":", 1), "<>W"), value = $ZSTRIP($PIECE(when, ":", 2, *), "<>W")
    If value = "other_source" Set value = $SELECT($ISOBJECT(facts): ##class(Shutter.Util.Json).Str(facts, "other_source"), 1: "")
    If value = "" Quit 0
    // A fact of the flag's name (history_policy, receiver_category, from the case's receiver, v1.23) answers before the
    // site-wide flag, so the catalogue's when reads the receiver the case went to, as the snapshot recorded it.
    If $ISOBJECT(facts) && (facts.%GetTypeOf(flag) = "string") Quit ##class(Shutter.Util.Json).Str(facts, flag) = value
    Quit ##class(Shutter.Store.SiteProfile).Flag(flag) = value
}

/// yes when the receiver applied an event for the encounter at the failed operation's own event time from
/// another source system.
ClassMethod SimultaneousSource(summary As %DynamicObject, case As Shutter.Store.Case) As %String [ Private ]
{
    Set ward = summary.%Get("ward_state")
    Set history = $SELECT($ISOBJECT(ward): ward.%Get("history"), 1: "")
    If '$ISOBJECT(history) Quit "no"
    Set source = $PIECE(case.OperationKey, "^", 1)
    Set iter = history.%GetIterator()
    While iter.%GetNext(.i, .h) {
        Continue:(##class(Shutter.Util.Json).Str(h, "event_time") '= case.EventTime)
        Set key = ##class(Shutter.Util.Json).Str(h, "operation_key")
        Continue:(key = case.OperationKey)
        If $PIECE(key, "^", 1) '= source Return "yes"
    }
    Quit "no"
}

/// The snapshot item of a kind from a summary's items, or "". The summary itself carries the downstream system's
/// state, the receipt and the route; the error is read from the snapshot through the case.
ClassMethod Item(summary As %DynamicObject, kind As %String) As %DynamicObject [ Private ]
{
    Set failure = summary.%Get("failure")
    If (kind = "error") && $ISOBJECT(failure) {
        // The failure carries the receiver's answer when the connector recorded one.
        Set err = failure.%Get("error")
        If $ISOBJECT(err) Quit err
        // The connector's answer as the case recorded it, when the case carries it (C3).
        Set reasonCode = ##class(Shutter.Util.Json).Str(failure, "reason_code"), httpStatus = +##class(Shutter.Util.Json).Str(failure, "http_status")
        If (reasonCode '= "") || (httpStatus > 0) {
            Set o = {}
            Set o."reason_code" = reasonCode, o."http_status" = httpStatus
            If (reasonCode = "") && (##class(Shutter.Util.Json).Str(failure, "outcome") = "uncertain") Set o."reason_code" = "timeout"
            Quit o
        }
        // "Delivery unavailable (ward_unavailable), HTTP 503: …", "Delivery refused (duplicate_message), HTTP 409",
        // "Delivery uncertain, HTTP 504: …": the reason code in parentheses, the status after "HTTP ".
        Set o = {}
        Set text = ##class(Shutter.Util.Json).Str(failure, "text")
        Set o."reason_code" = $SELECT(text [ "(": $PIECE($PIECE(text, "(", 2), ")", 1), 1: "")
        Set o."http_status" = +$PIECE($PIECE(text, "HTTP ", 2), ":", 1)
        If (o."reason_code" = "") && (text [ "uncertain") Set o."reason_code" = "timeout"
        Quit o
    }
    Quit ""
}

/// The conditions and the match for an existing case, for checks over SQL, with the chain kind of the case's stored
/// chain item (Shutter.Store.ChainItem.KindFor: single outside a chain) unless the caller gives one (v1.21).
ClassMethod ForCase(caseId As %String, chainKind As %String = "") As %String [ SqlProc ]
{
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Quit {"error": ("Unknown case " _ caseId)}.%ToJSON()
    If (chainKind = "") || (chainKind = $CHAR(0)) Set chainKind = ##class(Shutter.Store.ChainItem).KindFor(case)
    Set snap = case.CurrentSnapshot
    If '$ISOBJECT(snap) Quit {"error": "The case has no snapshot"}.%ToJSON()
    Set summary = snap.SummaryObject()
    Set result = ..Match(..Conditions(case, summary, chainKind), ..Facts(summary, case))
    Set result."case_id" = caseId, result.scenario = case.Scenario
    Quit result.%ToJSON()
}

}
