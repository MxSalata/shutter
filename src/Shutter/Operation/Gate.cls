/// The deterministic gate. It checks what can be checked mechanically about a plan against the
/// snapshot: identity, conformance, intent, ordering, state transition, effect completeness,
/// authorization, concurrency, evidence freshness and connector capability. Each check is pass,
/// block or unknown with a reason code; an unknown prerequisite blocks a write as surely as a
/// block does. The board may explain these results; it cannot override them.
Class Shutter.Operation.Gate Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

/// Bumped whenever a check changes; recorded on every decision and bound by approvals.
Parameter POLICYVERSION = "2026-10-19.3";

Method OnGateRequest(request As Shutter.Msg.GateRequest, Output response As Shutter.Msg.GateResult) As %Status
{
    Set response = ##class(Shutter.Msg.GateResult).%New()
    Set response.PolicyVersion = ..#POLICYVERSION
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Set response.Error = "Unknown case " _ request.CaseId, response.Outcome = "unknown" Quit $$$OK
    Set plan = ##class(Shutter.Store.Plan).%OpenId(request.PlanId)
    If '$ISOBJECT(plan) Set response.Error = "Unknown plan " _ request.PlanId, response.Outcome = "unknown" Quit $$$OK
    Set snapshot = case.CurrentSnapshot
    If '$ISOBJECT(snapshot) Set response.Error = "The case has no snapshot", response.Outcome = "unknown" Quit $$$OK
    Set summary = snapshot.SummaryObject()
    Set checks = []
    Set isWrite = plan.IsWrite()
    Set ward = summary.%Get("ward_state")
    Set wardStatus = +##class(Shutter.Util.Json).Str(summary, "ward_state_http_status", 0)
    Set receipt = summary.%Get("receipt")
    Set receiptStatus = +##class(Shutter.Util.Json).Str(summary, "receipt_http_status", 0)
    Set validation = summary.%Get("validation")

    // Identity: the receiver's encounter belongs to the case's patient.
    If wardStatus = 200 {
        Set same = (##class(Shutter.Util.Json).Str(ward, "patient_id") = case.PatientId) && (##class(Shutter.Util.Json).Str(ward, "patient_id_authority") = case.PatientIdAuthority)
        Do ..Check(checks, "identity", $SELECT(same: "pass", 1: "block"), $SELECT(same: "IDENTITY_MATCHES", 1: "PATIENT_MISMATCH"), $SELECT(same: "The receiver's encounter " _ case.EncounterId _ " belongs to " _ case.PatientId _ " (" _ case.PatientIdAuthority _ ")", 1: "The receiver's encounter belongs to another patient"))
    } ElseIf case.EncounterId = "-" {
        Do ..Check(checks, "identity", "pass", "NO_ENCOUNTER", "The message names no encounter (a patient-level message): there is no receiver record to compare")
    } ElseIf (wardStatus = 404) && (case.Event = "admit") {
        Do ..Check(checks, "identity", "pass", "NEW_ENCOUNTER", "The receiver has no encounter yet, as an admission expects")
    } ElseIf wardStatus = 404 {
        Do ..Check(checks, "identity", "block", "UNKNOWN_ENCOUNTER", "The receiver does not know encounter " _ case.EncounterId)
    } Else {
        Do ..Check(checks, "identity", "unknown", "RECEIVER_UNREADABLE", "The receiver's state could not be read (HTTP " _ wardStatus _ ")")
    }

    // Conformance: the message parsed against its schema.
    Set parsed = ##class(Shutter.Util.Json).Bool(validation, "parsed")
    // A message Shutter could not map to an operation has nothing to resend: the conformance check blocks it.
    If case.FailureKind = "unmappable" Do ..Check(checks, "conformance", "block", "UNMAPPABLE", "The message could not be mapped to an operation for the downstream system: " _ $EXTRACT(case.FailureText, 1, 300))
    Do ..Check(checks, "conformance", $SELECT(parsed: "pass", 1: "block"), $SELECT(parsed: "PARSED", 1: "PARSE_FAILED"), $SELECT(parsed: "The message parses against its schema", 1: "The message does not parse: " _ ##class(Shutter.Util.Json).Str(validation, "error")))

    // Intent: the plan is well-formed and, for a write, is exactly the case's operation.
    // A withheld operation (T31) was never sent and never will be by Shutter: a merge goes to the PAS team, and a cancel
    // the receiver cannot reverse is corrected by hand. The check is appended whatever the plan, as UNMAPPABLE is.
    If case.FailureKind = "withheld" Do ..Check(checks, "intent", "block", $SELECT(case.Event = "merge": "MERGE_WITHHELD", 1: "CANCEL_UNSUPPORTED"), $SELECT(case.Event = "merge": "Withheld by the site's policy: a merge goes to the PAS team", 1: "Withheld: the receiver cannot reverse the " _ ..Reversed(case.Event)))
    Set okDisp = $LISTFIND($LISTBUILD("resend", "reconcile", "superseded", "more_evidence", "escalate"), plan.Disposition) > 0
    If 'okDisp {
        Do ..Check(checks, "intent", "block", "UNKNOWN_DISPOSITION", "Disposition '" _ plan.Disposition _ "' is not one the gate knows")
    } ElseIf isWrite {
        // The same two rules guard every write (T31), whatever the case's kind and whoever made the plan: a merge goes
        // only when the site allows merges and the receiver's entry takes them, a cancel only to a receiver whose entry
        // reverses. A withheld case carries the block already (above), so it is not repeated here.
        If (case.FailureKind '= "withheld") && (case.Event = "merge") {
            Set siteAllows = ##class(Shutter.Store.SiteProfile).MergesAllowed(), receiverTakes = ##class(Shutter.Store.SiteProfile).ReceiverFlag(case.Receiver, "merges")
            If '(siteAllows && receiverTakes) Do ..Check(checks, "intent", "block", "MERGE_WITHHELD", "A merge is not sent through Shutter: " _ $SELECT('siteAllows: "the site's policy forbids merges (merges: forbidden)", 1: "the receiver's entry does not take merges") _ "; the PAS team decides it")
        } ElseIf (case.FailureKind '= "withheld") && ($EXTRACT(case.Event, 1, 7) = "cancel_") {
            If '##class(Shutter.Store.SiteProfile).ReceiverFlag(case.Receiver, "cancels") Do ..Check(checks, "intent", "block", "CANCEL_UNSUPPORTED", "The receiver's entry says it cannot reverse a " _ ..Reversed(case.Event) _ " (cancels: false)")
        }
        Set exact = (plan.OperationKey = case.OperationKey)
        Set op = summary.%Get("operation")
        Set digestOk = (plan.PayloadDigest = "") || (plan.PayloadDigest = ##class(Shutter.Util.Json).Str(op, "payload_digest"))
        Do ..Check(checks, "intent", $SELECT(exact && digestOk: "pass", 1: "block"), $SELECT(exact && digestOk: "EXACT_OPERATION", 'exact: "DIFFERENT_OPERATION", 1: "PAYLOAD_CHANGED"), $SELECT(exact && digestOk: "The plan resends the case's own operation, unchanged", 1: "The plan's action is not the case's operation unchanged"))
    } Else {
        Do ..Check(checks, "intent", "pass", "NO_WRITE", "The plan writes nothing to the receiver")
    }

    // Ordering: for a write, the event's time is plausible (T28) and no later transfer or discharge was applied for
    // this encounter.
    Set cat = summary.%Get("catalogue"), conds = $SELECT($ISOBJECT(cat): cat.%Get("conditions"), 1: "")
    Set eventTime = $SELECT($ISOBJECT(conds): ##class(Shutter.Util.Json).Str(conds, "event_time"), 1: "")
    Set timeDoubt = (eventTime '= "") && (eventTime '= "plausible")
    If isWrite {
        Set superseding = ..Superseding(summary, case)
        If timeDoubt {
            Do ..Check(checks, "ordering", "block", "EVENT_TIME_IMPLAUSIBLE", "The event's time is not plausible (" _ eventTime _ "): " _ $CASE(eventTime, "before_admission": "it precedes the admission", "future": "it lies in the future", "far_from_recorded": "it is more than a day from when the event was recorded", "clock_change": "it lies within an hour of a clock change and came without an offset", : eventTime) _ "; a person decides")
        } ElseIf superseding = "" {
            Do ..Check(checks, "ordering", "pass", "NO_LATER_EVENT", "No later transfer or discharge was applied for this encounter")
        } Else {
            Do ..Check(checks, "ordering", "block", "SUPERSEDED_BY_LATER_EVENT", "A later event was applied: " _ superseding)
        }
    } ElseIf plan.Disposition = "superseded" {
        Set superseding = ..Superseding(summary, case)
        If timeDoubt {
            // An ordering made with a doubtful time closes nothing on its own: a person decides.
            Do ..Check(checks, "ordering", "block", "EVENT_TIME_IMPLAUSIBLE", "The event's time is not plausible (" _ eventTime _ "), so what came before or after it is not settled; a person decides")
        } ElseIf superseding '= "" {
            Do ..Check(checks, "ordering", "pass", "SUPERSEDED_BY_LATER_EVENT", "The evidence shows the later event: " _ superseding)
        } ElseIf ..ClosedByCatalogue(plan, summary) {
            Do ..Check(checks, "ordering", "pass", "CLOSED_BY_CATALOGUE", "Catalogue entry " _ plan.CatalogueEntry _ " closes the case with nothing to send, and its pattern holds on this evidence")
        } Else {
            Do ..Check(checks, "ordering", "block", "SUPERSESSION_UNSUPPORTED", "The plan calls the operation superseded, but the evidence shows no later transfer or discharge for this encounter")
        }
    } Else {
        Do ..Check(checks, "ordering", "pass", "NOT_APPLICABLE", "No write proposed")
    }

    // State transition: allowed from the receiver's current state.
    If isWrite {
        If wardStatus = 200 {
            Set state = ##class(Shutter.Util.Json).Str(ward, "state")
            Set allowed = $CASE(case.Event, "admit": 0, "transfer": state = "admitted", "update": state = "admitted", "discharge": state = "admitted", "merge": state '= "", "cancel_admit": state = "admitted", "cancel_transfer": state = "admitted", "cancel_discharge": state = "discharged", : 0)
            Do ..Check(checks, "state_transition", $SELECT(allowed: "pass", 1: "block"), $SELECT(allowed: "TRANSITION_ALLOWED", 1: "INVALID_TRANSITION"), "Receiver state '" _ state _ "', event '" _ case.Event _ "'")
        } ElseIf (wardStatus = 404) && (case.Event = "admit") {
            Do ..Check(checks, "state_transition", "pass", "TRANSITION_ALLOWED", "An admission of an unknown encounter")
        } ElseIf case.EncounterId = "-" {
            Do ..Check(checks, "state_transition", "block", "PATIENT_LEVEL_WRITE", "The operation names no encounter whose state could be checked (a patient-level message); a person decides")
        } Else {
            Do ..Check(checks, "state_transition", "unknown", "RECEIVER_UNREADABLE", "The receiver's state could not be read")
        }
    } Else {
        Do ..Check(checks, "state_transition", "pass", "NOT_APPLICABLE", "No write proposed")
    }

    // Effect completeness: a receipt means the operation is already in effect.
    If receiptStatus = 200 {
        If plan.Disposition = "reconcile" {
            Do ..Check(checks, "effect", "pass", "RECEIPT_FOUND", "The receiver holds a receipt for this operation; reconciling is right")
        } ElseIf isWrite {
            Do ..Check(checks, "effect", "block", "ALREADY_COMMITTED", "The receiver already committed this operation; a resend would be a duplicate")
        } Else {
            Do ..Check(checks, "effect", "pass", "RECEIPT_FOUND", "A receipt exists")
        }
    } ElseIf receiptStatus = 404 {
        If plan.Disposition = "reconcile" {
            Do ..Check(checks, "effect", "block", "NO_RECEIPT", "Nothing to reconcile: the receiver has no receipt for this operation")
        } Else {
            Do ..Check(checks, "effect", "pass", "NO_RECEIPT", "The receiver has no receipt for this operation")
        }
    } ElseIf receiptStatus = -1 {
        // The receiver keeps no receipts (no receipt path in its description): its history alone shows what it applied,
        // and the capability check governs writes.
        If plan.Disposition = "reconcile" {
            Set inHistory = (wardStatus = 200) && ##class(Shutter.Operation.Verify).InHistory(ward, case.OperationKey)
            Do ..Check(checks, "effect", $SELECT(inHistory: "pass", 1: "block"), "RECEIPT_NOT_AVAILABLE", $SELECT(inHistory: "The receiver keeps no receipts, but its history shows the operation as applied; reconciling is right", 1: "The receiver keeps no receipts and its history does not show the operation: nothing to reconcile against"))
        } Else {
            Do ..Check(checks, "effect", "pass", "RECEIPT_NOT_AVAILABLE", "The receiver has no receipt endpoint; its capabilities decide whether a write may go")
        }
    } Else {
        Do ..Check(checks, "effect", "unknown", "RECEIPT_UNREADABLE", "The receipt lookup failed (HTTP " _ receiptStatus _ ")")
    }

    // Authorization: at approval and dispatch, a valid approval for exactly this plan.
    If request.Stage = "proposal" {
        Do ..Check(checks, "authorization", "pass", "NOT_YET_REQUIRED", "Authorization is checked at approval and dispatch")
    } Else {
        Set approval = ##class(Shutter.Store.Approval).%OpenId(request.ApprovalId)
        If '$ISOBJECT(approval) {
            Do ..Check(checks, "authorization", "block", "NO_APPROVAL", "No approval for this plan")
        } Else {
            Set why = approval.InvalidReason(plan, snapshot, ..#POLICYVERSION, request.ReceiverVersion, request.ReceiverEpoch)
            // An automatic release must be what the site's policy allows for this receiver's tier (6.5).
            If (why = "") && (approval.Approver = "policy") {
                Set tier = ##class(Shutter.Store.SiteProfile).TierOf(request.Receiver)
                Set policy = ##class(Shutter.Store.SiteProfile).Policy(tier, $SELECT(request.ChainKind = "": "single", 1: request.ChainKind))
                If policy '= "automatic" Set why = "policy_requires_approval"
                // The plan must have come from the policy path for the entry it names: a board's plan never goes by policy.
                If (why = "") && ((plan.CatalogueEntry = "") || (plan.CreatedBy '= ("policy:" _ plan.CatalogueEntry))) Set why = "plan_origin"
            }
            Do ..Check(checks, "authorization", $SELECT(why = "": "pass", 1: "block"), $SELECT(why = "": "APPROVAL_VALID", why = "policy_requires_approval": "POLICY_REQUIRES_APPROVAL", 1: "APPROVAL_" _ $ZCONVERT(why, "U")), $SELECT(why = "": "Approved by " _ approval.Approver _ " for plan digest " _ $EXTRACT(approval.PlanDigest, 1, 19), 1: "The approval no longer authorises this dispatch: " _ why))
        }
    }

    // Concurrency: a write names the receiver version it expects, and that is the version seen.
    If isWrite {
        If plan.ExpectedVersion = "" {
            Do ..Check(checks, "concurrency", "block", "NO_EXPECTED_VERSION", "The plan names no receiver version to condition the write on")
        } ElseIf wardStatus = 200 {
            Set seen = +##class(Shutter.Util.Json).Str(ward, "version", -1)
            Set current = $SELECT(request.ReceiverVersion '= "": request.ReceiverVersion, 1: seen)
            Do ..Check(checks, "concurrency", $SELECT(current = plan.ExpectedVersion: "pass", 1: "block"), $SELECT(current = plan.ExpectedVersion: "VERSION_MATCHES", 1: "RECEIVER_CHANGED"), "Expected version " _ plan.ExpectedVersion _ ", observed " _ current)
        } ElseIf (wardStatus = 404) && (case.Event = "admit") {
            Do ..Check(checks, "concurrency", $SELECT(plan.ExpectedVersion = 0: "pass", 1: "block"), $SELECT(plan.ExpectedVersion = 0: "VERSION_MATCHES", 1: "RECEIVER_CHANGED"), "An admission expects version 0")
        } ElseIf case.EncounterId = "-" {
            Do ..Check(checks, "concurrency", "block", "PATIENT_LEVEL_WRITE", "The operation names no encounter version to condition the write on (a patient-level message); a person decides")
        } Else {
            Do ..Check(checks, "concurrency", "unknown", "RECEIVER_UNREADABLE", "The receiver's version could not be read")
        }
    } Else {
        Do ..Check(checks, "concurrency", "pass", "NOT_APPLICABLE", "No write proposed")
    }

    // Evidence: the snapshot's live observations are fresh.
    Set fresh = snapshot.IsFresh()
    Do ..Check(checks, "evidence", $SELECT(fresh: "pass", 1: "unknown"), $SELECT(fresh: "FRESH", 1: "STALE_EVIDENCE"), $SELECT(fresh: "Observed at " _ snapshot.TakenAt _ ", fresh until " _ snapshot.FreshUntil, 1: "The snapshot's observations expired at " _ snapshot.FreshUntil))

    // Capability: the connector enforces what the plan needs.
    Set route = summary.%Get("route")
    If 'isWrite {
        Do ..Check(checks, "capability", "pass", "NOT_APPLICABLE", "No write proposed")
    } ElseIf ##class(Shutter.Util.Json).Str(route, "capabilities_http_status") '= 200 {
        Do ..Check(checks, "capability", "unknown", "CAPABILITIES_UNREADABLE", "The receiver's capability profile could not be read, so its guarantees are unknown")
    } Else {
        Set capable = ##class(Shutter.Util.Json).Bool(route, "conditional_writes") && ##class(Shutter.Util.Json).Bool(route, "receipts")
        Do ..Check(checks, "capability", $SELECT(capable: "pass", 1: "block"), $SELECT(capable: "CONNECTOR_CAPABLE", 1: "CONNECTOR_INCAPABLE"), $SELECT(capable: "The receiver guarantees conditional writes and receipts", 1: "The receiver reports no conditional writes: a resend cannot be made safe, so only investigation and reconciliation are open"))
    }

    // Catalogue (CONTRACTS 6.5): the plan's entry and outcome against the matcher's result in the evidence.
    Set cat = summary.%Get("catalogue")
    Set decision = $SELECT($ISOBJECT(cat): ##class(Shutter.Util.Json).Str(cat, "decision"), 1: "")
    If (decision = "") || (decision = "not_configured") {
        Do ..Check(checks, "catalogue", "pass", "NOT_CONFIGURED", "No catalogue is installed, or the matcher gave no result")
    } ElseIf decision = "error" {
        Do ..Check(checks, "catalogue", "unknown", "MATCHER_ERROR", "The matcher failed on this evidence: " _ $EXTRACT(##class(Shutter.Util.Json).Str(cat, "error"), 1, 200))
    } ElseIf decision = "new_pattern" {
        Do ..Check(checks, "catalogue", "block", "NEW_PATTERN", "No catalogue entry matches this evidence: a candidate entry for a reviewer")
    } ElseIf plan.CatalogueEntry = "" {
        Do ..Check(checks, "catalogue", "pass", "ENTRY_NOT_NAMED", "The plan names no catalogue entry; the evidence matched " _ $SELECT(##class(Shutter.Util.Json).Str(cat, "entry") '= "": ##class(Shutter.Util.Json).Str(cat, "entry"), 1: "several entries"))
    } Else {
        Set matched = "", mi = cat.%Get("matches").%GetIterator()
        While mi.%GetNext(.i, .m) { If ##class(Shutter.Util.Json).Str(m, "id") = plan.CatalogueEntry Set matched = m Quit }
        If '$ISOBJECT(matched) {
            Set exists = $ISOBJECT(##class(Shutter.Catalogue.Entry).ById(plan.CatalogueEntry))
            Do ..Check(checks, "catalogue", "block", $SELECT(exists: "PATTERN_NOT_MATCHED", 1: "ENTRY_UNKNOWN"), $SELECT(exists: "The plan follows " _ plan.CatalogueEntry _ ", but its pattern does not hold on this evidence", 1: "The plan names " _ plan.CatalogueEntry _ ", which is not in the catalogue"))
        } ElseIf $EXTRACT(plan.Outcome, 1, 12) = "alternative:" {
            Set n = +$PIECE(plan.Outcome, ":", 2), alts = matched.%Get("alternatives")
            Set alt = $SELECT($ISOBJECT(alts) && (n >= 1) && (n <= alts.%Size()): alts.%Get(n - 1), 1: "")
            Set when = $SELECT($ISOBJECT(alt): ##class(Shutter.Util.Json).Str(alt, "when", "always"), 1: "")
            Set allowed = $ISOBJECT(alt) && ##class(Shutter.Catalogue.Matcher).WhenHolds(when, cat.%Get("facts"))
            Do ..Check(checks, "catalogue", $SELECT(allowed: "pass", 1: "block"), $SELECT(allowed: "OUTCOME_ALLOWED", 1: "OUTCOME_NOT_ALLOWED"), $SELECT(allowed: "Entry " _ plan.CatalogueEntry _ " matches and the site allows alternative " _ n, 1: "Entry " _ plan.CatalogueEntry _ "'s alternative " _ n _ " is not allowed for this site (" _ when _ ")"))
            If allowed Do ..OutcomeConsistency(checks, plan, ##class(Shutter.Util.Json).Str(alt, "outcome"))
        } Else {
            Do ..Check(checks, "catalogue", "pass", "ENTRY_MATCHED", "Entry " _ plan.CatalogueEntry _ " matches the evidence; the preferred outcome")
            Do ..OutcomeConsistency(checks, plan, ##class(Shutter.Util.Json).Str(matched.%Get("preferred"), "outcome"))
        }
    }

    // The outcome is the worst check.
    Set outcome = "pass"
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) {
        If c.result = "block" Set outcome = "block"
        If (c.result = "unknown") && (outcome '= "block") Set outcome = "unknown"
    }
    Set blocks = ""
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) { If c.result '= "pass" Set blocks = blocks _ $SELECT(blocks = "": "", 1: ", ") _ c.check _ " " _ c."reason_code" }
    Set text = $CASE(outcome, "pass": "Every check passed", "block": "Blocked: " _ blocks, : "Unknown: " _ blocks) _ " (policy " _ ..#POLICYVERSION _ ", stage " _ request.Stage _ ")"
    Set sc = ##class(Shutter.Store.GateDecision).Create(case, plan, request.Stage, ..#POLICYVERSION, outcome, checks, text, .decision)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc)
    Set response.Outcome = outcome, response.ChecksJSON = checks.%ToJSON(), response.Summary = text
    If $ISOBJECT($GET(decision)) Set response.DecisionId = decision.%Id()
    Do case.Note("artifact", "Gate (" _ request.Stage _ "): " _ text, "system", "gate:" _ response.DecisionId)
    $$$TRACE("Gate " _ request.Stage _ " for " _ case.CaseId _ " plan v" _ plan.Version _ ": " _ outcome)
    Quit $$$OK
}

/// Whether the plan follows a matched catalogue entry whose chosen outcome is "none": the entry closes the case with
/// nothing to send, so a superseded plan needs no later event in the message store (a discharge before the failed
/// transfer, a duplicate, another source named authoritative).
ClassMethod ClosedByCatalogue(plan As Shutter.Store.Plan, summary As %DynamicObject) As %Boolean
{
    If plan.CatalogueEntry = "" Quit 0
    Set cat = summary.%Get("catalogue")
    If '$ISOBJECT(cat) || '$ISOBJECT(cat.%Get("matches")) Quit 0
    Set matched = "", mi = cat.%Get("matches").%GetIterator()
    While mi.%GetNext(.i, .m) { If ##class(Shutter.Util.Json).Str(m, "id") = plan.CatalogueEntry Set matched = m Quit }
    If '$ISOBJECT(matched) Quit 0
    If $EXTRACT(plan.Outcome, 1, 12) = "alternative:" {
        Set n = +$PIECE(plan.Outcome, ":", 2), alts = matched.%Get("alternatives")
        Set alt = $SELECT($ISOBJECT(alts) && (n >= 1) && (n <= alts.%Size()): alts.%Get(n - 1), 1: "")
        If '$ISOBJECT(alt) Quit 0
        If '##class(Shutter.Catalogue.Matcher).WhenHolds(##class(Shutter.Util.Json).Str(alt, "when", "always"), cat.%Get("facts")) Quit 0
        Quit ##class(Shutter.Util.Json).Str(alt, "outcome") = "none"
    }
    Quit ##class(Shutter.Util.Json).Str(matched.%Get("preferred"), "outcome") = "none"
}

/// The disposition a catalogue outcome allows (CONTRACTS 6.3): a plan that follows an entry's outcome must act
/// accordingly, or it is blocked with OUTCOME_MISMATCH (C4).
ClassMethod DispositionFor(outcome As %String) As %String
{
    Quit $CASE(outcome, "resend": "resend", "resend_chain": "resend", "resend_latest": "resend", "reconcile": "reconcile", "none": "superseded", "escalate": "escalate", "resend_unconditional": "escalate", "correct_history": "escalate", : "")
}

Method OutcomeConsistency(checks As %DynamicArray, plan As Shutter.Store.Plan, outcome As %String) [ Private ]
{
    Set allowed = ..DispositionFor(outcome)
    If (allowed = "") || (plan.Disposition = allowed) Quit
    If (allowed = "escalate") && (plan.Disposition = "more_evidence") Quit
    Do ..Check(checks, "catalogue", "block", "OUTCOME_MISMATCH", "The outcome " _ outcome _ " calls for " _ allowed _ ", but the plan's disposition is " _ plan.Disposition)
}

/// A later applied transfer or discharge for the encounter, described, or "".
Method Superseding(summary As %DynamicObject, case As Shutter.Store.Case) As %String [ Private ]
{
    Set found = ""
    Set timeline = summary.%Get("timeline")
    If $ISOBJECT(timeline) {
        Set iter = timeline.%GetIterator()
        While iter.%GetNext(.i, .ev) {
            If '##class(Shutter.Util.Json).Bool(ev, "later") Continue
            Set outcome = ##class(Shutter.Util.Json).Str(ev, "outcome")
            If (outcome '= "applied") && (outcome '= "already_committed") Continue
            Set event = ##class(Shutter.Util.Json).Str(ev, "event")
            If (event = "transfer") || (event = "discharge") {
                Set found = event _ $SELECT(##class(Shutter.Util.Json).Str(ev, "ward") '= "": " to " _ ev.ward, 1: "") _ " at " _ ##class(Shutter.Util.Json).Str(ev, "event_time")
            }
        }
    }
    // The receiver's own history is authoritative when the message store is silent.
    If found = "" {
        Set ward = summary.%Get("ward_state")
        Set history = $SELECT($ISOBJECT(ward): ward.%Get("history"), 1: "")
        If $ISOBJECT(history) {
            Set iter = history.%GetIterator()
            While iter.%GetNext(.i, .h) {
                Set t = ##class(Shutter.Util.Json).Str(h, "event_time")
                If '(t ]] case.EventTime) Continue
                Set event = ##class(Shutter.Util.Json).Str(h, "event")
                If (event = "transfer") || (event = "discharge") Set found = event _ $SELECT(##class(Shutter.Util.Json).Str(h, "ward") '= "": " to " _ h.ward, 1: "") _ " at " _ t _ " (receiver history)"
            }
        }
    }
    Quit found
}

/// The event a cancel reverses, as a word for a person: cancel_admit is "admission", cancel_transfer "transfer",
/// cancel_discharge "discharge"; any other event word is given back as it is.
ClassMethod Reversed(event As %String) As %String
{
    Set base = $SELECT($EXTRACT(event, 1, 7) = "cancel_": $EXTRACT(event, 8, *), 1: event)
    Quit $CASE(base, "admit": "admission", "": "event", : base)
}

Method Check(checks As %DynamicArray, name As %String, result As %String, code As %String, detail As %String) [ Private ]
{
    Set c = {}
    Set c.check = name, c.result = result, c."reason_code" = code, c.detail = detail
    Do checks.%Push(c)
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.GateRequest">
    <Method>OnGateRequest</Method>
  </MapItem>
</MapItems>
}

}
