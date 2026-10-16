/// The deterministic matcher (CONTRACTS 6.1 and 6.3): computes the condition vocabulary from a case's evidence
/// snapshot and finds the catalogue entries whose pattern holds. No model. Runs when the evidence is collected;
/// its result is the snapshot summary's "catalogue" item, which the workflow, the gate and the app read.
Class Interlock.Catalogue.Matcher
{

/// The conditions a snapshot summary shows for a case (every name of 6.1, each with its observed value).
ClassMethod Conditions(case As Interlock.Store.Case, summary As %DynamicObject, chainKind As %String = "single") As %DynamicObject
{
    Set c = {}
    Set json = "Interlock.Util.Json"
    // delivery
    Set c.delivery = $CASE(case.FailureKind, "delivery_failed": "failed", "rejected": "rejected", "uncertain_outcome": "uncertain", : "failed")
    // receiver_answer, from the error item's reason code and status
    Set error = ..Item(summary, "error")
    Set reason = $ZCONVERT($SELECT($ISOBJECT(error): $CLASSMETHOD(json, "Str", error, "reason_code"), 1: ""), "L")
    Set status = $SELECT($ISOBJECT(error): $CLASSMETHOD(json, "Str", error, "http_status"), 1: "")
    Set c."receiver_answer" = $SELECT(reason [ "unavailable": "unavailable", (reason [ "timeout") || (status = 504): "timeout", reason [ "duplicate": "duplicate", reason [ "version": "version_conflict", (reason '= "") || (status = 422) || (status = 409): "refused", status = 503: "unavailable", 1: "none")
    If (c."receiver_answer" = "none") && (c.delivery = "uncertain") Set c."receiver_answer" = "timeout"
    // receipt
    Set rstatus = $CLASSMETHOD(json, "Str", summary, "receipt_http_status")
    Set c.receipt = $SELECT(rstatus = 200: "present", rstatus = 404: "absent", 1: "unreadable")
    // later_applied: the latest later applied event, from the timeline and the receiver's history
    Set c."later_applied" = ..LaterApplied(summary, case)
    // encounter_state and the identity
    Set ward = summary.%Get("ward_state"), wstatus = $CLASSMETHOD(json, "Str", summary, "ward_state_http_status")
    Set state = $SELECT((wstatus = 200) && $ISOBJECT(ward): $CLASSMETHOD(json, "Str", ward, "state"), 1: "")
    Set c."encounter_state" = $SELECT(state = "": "unknown", 1: state)
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
ClassMethod Match(conditions As %DynamicObject) As %DynamicObject
{
    Set out = {}
    Set out.conditions = conditions
    Set out."catalogue_version" = ##class(Interlock.Catalogue.Entry).CatalogueVersion()
    Set matches = []
    If ##class(Interlock.Catalogue.Entry).Count() = 0 {
        Set out.matches = matches, out.decision = "not_configured"
        Do out.%Set("entry", "", "null"), out.%Set("outcome", "", "null")
        Quit out
    }
    Set entries = ##class(Interlock.Catalogue.Entry).All()
    Set iter = entries.%GetIterator()
    While iter.%GetNext(.i, .e) {
        If ..Holds(e.%Get("pattern"), conditions) {
            Set m = {}
            Set m.id = e.id, m.version = e.version, m.title = e.title, m.decides = e.decides
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
        Set decides = ##class(Interlock.Util.Json).Str(m, "decides", "board")
        Set out.decision = $SELECT($LISTFIND($LISTBUILD("policy", "board", "person"), decides): decides, 1: "board")
        Set out.entry = m.id
        Set pref = m.%Get("preferred")
        Set out.outcome = $SELECT($ISOBJECT(pref): ##class(Interlock.Util.Json).Str(pref, "outcome"), 1: "")
    }
    Quit out
}

/// Whether a pattern holds: every listed condition's observed value is among the allowed ones.
ClassMethod Holds(pattern As %DynamicObject, conditions As %DynamicObject) As %Boolean
{
    If '$ISOBJECT(pattern) Quit 0
    Set iter = pattern.%GetIterator()
    While iter.%GetNext(.name, .allowed) {
        Set observed = ##class(Interlock.Util.Json).Str(conditions, name)
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

/// The latest applied event for the encounter later than the failed operation: transfer, discharge, update, or none.
ClassMethod LaterApplied(summary As %DynamicObject, case As Interlock.Store.Case) As %String [ Private ]
{
    Set found = "", foundAt = ""
    Set timeline = summary.%Get("timeline")
    If $ISOBJECT(timeline) {
        Set iter = timeline.%GetIterator()
        While iter.%GetNext(.i, .ev) {
            Continue:'##class(Interlock.Util.Json).Bool(ev, "later")
            Set outcome = ##class(Interlock.Util.Json).Str(ev, "outcome")
            Continue:((outcome '= "applied") && (outcome '= "already_committed"))
            Set t = ##class(Interlock.Util.Json).Str(ev, "event_time")
            If (foundAt = "") || (t ]] foundAt) Set found = ##class(Interlock.Util.Json).Str(ev, "event"), foundAt = t
        }
    }
    Set ward = summary.%Get("ward_state")
    Set history = $SELECT($ISOBJECT(ward): ward.%Get("history"), 1: "")
    If $ISOBJECT(history) {
        Set iter = history.%GetIterator()
        While iter.%GetNext(.i, .h) {
            Set t = ##class(Interlock.Util.Json).Str(h, "event_time")
            Continue:'(t ]] case.EventTime)
            If (foundAt = "") || (t ]] foundAt) Set found = ##class(Interlock.Util.Json).Str(h, "event"), foundAt = t
        }
    }
    If found = "" Quit "none"
    Quit $SELECT($LISTFIND($LISTBUILD("transfer", "discharge", "update"), found): found, 1: "update")
}

/// yes when the receiver applied an event for the encounter at the failed operation's own event time from
/// another source system.
ClassMethod SimultaneousSource(summary As %DynamicObject, case As Interlock.Store.Case) As %String [ Private ]
{
    Set ward = summary.%Get("ward_state")
    Set history = $SELECT($ISOBJECT(ward): ward.%Get("history"), 1: "")
    If '$ISOBJECT(history) Quit "no"
    Set source = $PIECE(case.OperationKey, "^", 1)
    Set iter = history.%GetIterator()
    While iter.%GetNext(.i, .h) {
        Continue:(##class(Interlock.Util.Json).Str(h, "event_time") '= case.EventTime)
        Set key = ##class(Interlock.Util.Json).Str(h, "operation_key")
        Continue:(key = case.OperationKey)
        If $PIECE(key, "^", 1) '= source Return "yes"
    }
    Quit "no"
}

/// The snapshot item of a kind from a summary's items, or "". The summary itself carries the ward state, the
/// receipt and the route; the error is read from the snapshot through the case.
ClassMethod Item(summary As %DynamicObject, kind As %String) As %DynamicObject [ Private ]
{
    Set failure = summary.%Get("failure")
    If (kind = "error") && $ISOBJECT(failure) {
        // The failure carries the receiver's answer when the connector recorded one.
        Set err = failure.%Get("error")
        If $ISOBJECT(err) Quit err
        // "Delivery unavailable (ward_unavailable), HTTP 503: …", "Delivery refused (duplicate_message), HTTP 409",
        // "Delivery uncertain, HTTP 504: …": the reason code in parentheses, the status after "HTTP ".
        Set o = {}
        Set text = ##class(Interlock.Util.Json).Str(failure, "text")
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
    Set case = ##class(Interlock.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Quit {"error": ("Unknown case " _ caseId)}.%ToJSON()
    Set snap = case.CurrentSnapshot
    If '$ISOBJECT(snap) Quit {"error": "The case has no snapshot"}.%ToJSON()
    Set summary = snap.SummaryObject()
    Set result = ..Match(..Conditions(case, summary, chainKind))
    Set result."case_id" = caseId, result.scenario = case.Scenario
    Quit result.%ToJSON()
}

}
