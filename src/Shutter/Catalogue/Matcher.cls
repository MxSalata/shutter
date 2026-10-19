/// The deterministic matcher (CONTRACTS 6.1 and 6.3): computes the condition vocabulary from a case's evidence
/// snapshot and finds the catalogue entries whose pattern holds. No model. Runs when the evidence is collected;
/// its result is the snapshot summary's "catalogue" item, which the workflow, the gate and the app read.
/// Since T31 (CONTRACTS v1.14) the vocabulary has "event" (the failed operation's event word, the three cancels folded
/// to cancel), "delivery" takes "withheld" (an operation Shutter never sent: a merge under the site's policy, a cancel
/// the receiver cannot reverse) with "receiver_answer: none", and "later_applied" takes "cancelled" and "merge".
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
    Set c.event = $SELECT($EXTRACT(case.Event, 1, 7) = "cancel_": "cancel", $LISTFIND($LISTBUILD("admit", "transfer", "discharge", "update", "merge", "register"), case.Event): case.Event, 1: "other")
    // receipt
    Set rstatus = $CLASSMETHOD(json, "Str", summary, "receipt_http_status")
    Set c.receipt = $SELECT(rstatus = 200: "present", rstatus = 404: "absent", rstatus = -1: "none", 1: "unreadable")
    // later_applied: the latest later applied event, from the timeline and the receiver's history
    Set c."later_applied" = ..LaterApplied(summary, case)
    // event_time (T28): the failed event's time against the admission, the message, the recording time and the clock
    Set c."event_time" = ..EventTimePlausibility(summary, case)
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
        Set c.transition = $SELECT(case.Event = "admit": "invalid", state = "admitted": "allowed", 1: "invalid")
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
        Set out.outcome = $SELECT($ISOBJECT(pref): ##class(Shutter.Util.Json).Str(pref, "outcome"), 1: "")
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

/// The applied events for the encounter later than the failed operation, by precedence (CONTRACTS 6.1): cancelled
/// (an applied cancel at or after the failed event's time, T31), else merge (an applied merge, T31), else discharge,
/// else transfer, else admit (a later admission, T28), else update, else none. (A later transfer followed by a later
/// update is a transfer.) A cancel counts from the failed event's own time, not strictly after it, because a cancel
/// carries the time of the event it reverses; the case's own operation never counts.
ClassMethod LaterApplied(summary As %DynamicObject, case As Shutter.Store.Case) As %String [ Private ]
{
    // A later admission is its own answer (T28): an encounter admitted again after the failed event is not an update.
    // So are a cancel and a merge (T31); any other word the receiver or the index reports still reads as an update.
    Set seen("cancelled") = 0, seen("merge") = 0, seen("discharge") = 0, seen("transfer") = 0, seen("update") = 0, seen("admit") = 0
    Set timeline = summary.%Get("timeline")
    If $ISOBJECT(timeline) {
        Set iter = timeline.%GetIterator()
        While iter.%GetNext(.i, .ev) {
            Set outcome = ##class(Shutter.Util.Json).Str(ev, "outcome")
            Continue:((outcome '= "applied") && (outcome '= "already_committed"))
            Set e = ##class(Shutter.Util.Json).Str(ev, "event")
            If $EXTRACT(e, 1, 7) = "cancel_" {
                If ..AtOrAfter(##class(Shutter.Util.Json).Str(ev, "event_time"), ##class(Shutter.Util.Json).Str(ev, "operation_key"), case) Set seen("cancelled") = 1
                Continue
            }
            Continue:'##class(Shutter.Util.Json).Bool(ev, "later")
            Set seen($SELECT($DATA(seen(e)): e, 1: "update")) = 1
        }
    }
    Set ward = summary.%Get("ward_state")
    Set history = $SELECT($ISOBJECT(ward): ward.%Get("history"), 1: "")
    If $ISOBJECT(history) {
        Set iter = history.%GetIterator()
        While iter.%GetNext(.i, .h) {
            Set t = ##class(Shutter.Util.Json).Str(h, "event_time")
            Set e = ##class(Shutter.Util.Json).Str(h, "event")
            If $EXTRACT(e, 1, 7) = "cancel_" {
                If ..AtOrAfter(t, ##class(Shutter.Util.Json).Str(h, "operation_key"), case) Set seen("cancelled") = 1
                Continue
            }
            Continue:'(t ]] case.EventTime)
            Set seen($SELECT($DATA(seen(e)): e, 1: "update")) = 1
        }
    }
    Quit $SELECT(seen("cancelled"): "cancelled", seen("merge"): "merge", seen("discharge"): "discharge", seen("transfer"): "transfer", seen("admit"): "admit", seen("update"): "update", 1: "none")
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
/// change, where the order of two events is not safe; plausible otherwise.
ClassMethod EventTimePlausibility(summary As %DynamicObject, case As Shutter.Store.Case) As %String
{
    Set json = "Shutter.Util.Json", t = case.EventTime
    Set msg = summary.%Get("message")
    If (t = "") || '$ISOBJECT(msg) Quit "plausible"
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
    Quit "plausible"
}

/// Facts beside the conditions, for the alternatives' "when": other_source (the other source system of a
/// simultaneous event, or "").
ClassMethod Facts(summary As %DynamicObject, case As Shutter.Store.Case) As %DynamicObject
{
    Set f = {}
    Set f."other_source" = ""
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

/// The conditions and the match for an existing case, for checks over SQL.
ClassMethod ForCase(caseId As %String, chainKind As %String = "single") As %String [ SqlProc ]
{
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Quit {"error": ("Unknown case " _ caseId)}.%ToJSON()
    Set snap = case.CurrentSnapshot
    If '$ISOBJECT(snap) Quit {"error": "The case has no snapshot"}.%ToJSON()
    Set summary = snap.SummaryObject()
    Set result = ..Match(..Conditions(case, summary, chainKind), ..Facts(summary, case))
    Set result."case_id" = caseId, result.scenario = case.Scenario
    Quit result.%ToJSON()
}

}
