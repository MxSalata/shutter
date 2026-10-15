/// The deterministic gate. It checks what can be checked mechanically about a plan against the
/// snapshot: identity, conformance, intent, ordering, state transition, effect completeness,
/// authorization, concurrency, evidence freshness and connector capability. Each check is pass,
/// block or unknown with a reason code; an unknown prerequisite blocks a write as surely as a
/// block does. The board may explain these results; it cannot override them.
Class Interlock.Operation.Gate Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

/// Bumped whenever a check changes; recorded on every decision and bound by approvals.
Parameter POLICYVERSION = "2026-10-15.1";

Method OnGateRequest(request As Interlock.Msg.GateRequest, Output response As Interlock.Msg.GateResult) As %Status
{
    Set response = ##class(Interlock.Msg.GateResult).%New()
    Set response.PolicyVersion = ..#POLICYVERSION
    Set case = ##class(Interlock.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Set response.Error = "Unknown case " _ request.CaseId, response.Outcome = "unknown" Quit $$$OK
    Set plan = ##class(Interlock.Store.Plan).%OpenId(request.PlanId)
    If '$ISOBJECT(plan) Set response.Error = "Unknown plan " _ request.PlanId, response.Outcome = "unknown" Quit $$$OK
    Set snapshot = case.CurrentSnapshot
    If '$ISOBJECT(snapshot) Set response.Error = "The case has no snapshot", response.Outcome = "unknown" Quit $$$OK
    Set summary = snapshot.SummaryObject()
    Set checks = []
    Set isWrite = plan.IsWrite()
    Set ward = summary.%Get("ward_state")
    Set wardStatus = +##class(Interlock.Util.Json).Str(summary, "ward_state_http_status", 0)
    Set receipt = summary.%Get("receipt")
    Set receiptStatus = +##class(Interlock.Util.Json).Str(summary, "receipt_http_status", 0)
    Set validation = summary.%Get("validation")

    // Identity: the receiver's encounter belongs to the case's patient.
    If wardStatus = 200 {
        Set same = (##class(Interlock.Util.Json).Str(ward, "patient_id") = case.PatientId) && (##class(Interlock.Util.Json).Str(ward, "patient_id_authority") = case.PatientIdAuthority)
        Do ..Check(checks, "identity", $SELECT(same: "pass", 1: "block"), $SELECT(same: "IDENTITY_MATCHES", 1: "PATIENT_MISMATCH"), $SELECT(same: "The receiver's encounter " _ case.EncounterId _ " belongs to " _ case.PatientId _ " (" _ case.PatientIdAuthority _ ")", 1: "The receiver's encounter belongs to another patient"))
    } ElseIf (wardStatus = 404) && (case.Event = "admit") {
        Do ..Check(checks, "identity", "pass", "NEW_ENCOUNTER", "The receiver has no encounter yet, as an admission expects")
    } ElseIf wardStatus = 404 {
        Do ..Check(checks, "identity", "block", "UNKNOWN_ENCOUNTER", "The receiver does not know encounter " _ case.EncounterId)
    } Else {
        Do ..Check(checks, "identity", "unknown", "RECEIVER_UNREADABLE", "The receiver's state could not be read (HTTP " _ wardStatus _ ")")
    }

    // Conformance: the message parsed against its schema.
    Set parsed = ##class(Interlock.Util.Json).Bool(validation, "parsed")
    Do ..Check(checks, "conformance", $SELECT(parsed: "pass", 1: "block"), $SELECT(parsed: "PARSED", 1: "PARSE_FAILED"), $SELECT(parsed: "The message parses against its schema", 1: "The message does not parse: " _ ##class(Interlock.Util.Json).Str(validation, "error")))

    // Intent: the plan is well-formed and, for a write, is exactly the case's operation.
    Set okDisp = $LISTFIND($LISTBUILD("resend", "reconcile", "superseded", "more_evidence", "escalate"), plan.Disposition) > 0
    If 'okDisp {
        Do ..Check(checks, "intent", "block", "UNKNOWN_DISPOSITION", "Disposition '" _ plan.Disposition _ "' is not one the gate knows")
    } ElseIf isWrite {
        Set exact = (plan.OperationKey = case.OperationKey)
        Set op = summary.%Get("operation")
        Set digestOk = (plan.PayloadDigest = "") || (plan.PayloadDigest = ##class(Interlock.Util.Json).Str(op, "payload_digest"))
        Do ..Check(checks, "intent", $SELECT(exact && digestOk: "pass", 1: "block"), $SELECT(exact && digestOk: "EXACT_OPERATION", 'exact: "DIFFERENT_OPERATION", 1: "PAYLOAD_CHANGED"), $SELECT(exact && digestOk: "The plan resends the case's own operation, unchanged", 1: "The plan's action is not the case's operation unchanged"))
    } Else {
        Do ..Check(checks, "intent", "pass", "NO_WRITE", "The plan writes nothing to the receiver")
    }

    // Ordering: for a write, no later transfer or discharge was applied for this encounter.
    If isWrite {
        Set superseding = ..Superseding(summary, case)
        If superseding = "" {
            Do ..Check(checks, "ordering", "pass", "NO_LATER_EVENT", "No later transfer or discharge was applied for this encounter")
        } Else {
            Do ..Check(checks, "ordering", "block", "SUPERSEDED_BY_LATER_EVENT", "A later event was applied: " _ superseding)
        }
    } Else {
        Do ..Check(checks, "ordering", "pass", "NOT_APPLICABLE", "No write proposed")
    }

    // State transition: allowed from the receiver's current state.
    If isWrite {
        If wardStatus = 200 {
            Set state = ##class(Interlock.Util.Json).Str(ward, "state")
            Set allowed = $CASE(case.Event, "admit": 0, "transfer": state = "admitted", "update": state = "admitted", "discharge": state = "admitted", : 0)
            Do ..Check(checks, "state_transition", $SELECT(allowed: "pass", 1: "block"), $SELECT(allowed: "TRANSITION_ALLOWED", 1: "INVALID_TRANSITION"), "Receiver state '" _ state _ "', event '" _ case.Event _ "'")
        } ElseIf (wardStatus = 404) && (case.Event = "admit") {
            Do ..Check(checks, "state_transition", "pass", "TRANSITION_ALLOWED", "An admission of an unknown encounter")
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
    } Else {
        Do ..Check(checks, "effect", "unknown", "RECEIPT_UNREADABLE", "The receipt lookup failed (HTTP " _ receiptStatus _ ")")
    }

    // Authorization: at approval and dispatch, a valid approval for exactly this plan.
    If request.Stage = "proposal" {
        Do ..Check(checks, "authorization", "pass", "NOT_YET_REQUIRED", "Authorization is checked at approval and dispatch")
    } Else {
        Set approval = ##class(Interlock.Store.Approval).%OpenId(request.ApprovalId)
        If '$ISOBJECT(approval) {
            Do ..Check(checks, "authorization", "block", "NO_APPROVAL", "No approval for this plan")
        } Else {
            Set why = approval.InvalidReason(plan, snapshot, ..#POLICYVERSION, request.ReceiverVersion)
            Do ..Check(checks, "authorization", $SELECT(why = "": "pass", 1: "block"), $SELECT(why = "": "APPROVAL_VALID", 1: "APPROVAL_" _ $ZCONVERT(why, "U")), $SELECT(why = "": "Approved by " _ approval.Approver _ " for plan digest " _ $EXTRACT(approval.PlanDigest, 1, 19), 1: "The approval no longer authorises this dispatch: " _ why))
        }
    }

    // Concurrency: a write names the receiver version it expects, and that is the version seen.
    If isWrite {
        If plan.ExpectedVersion = "" {
            Do ..Check(checks, "concurrency", "block", "NO_EXPECTED_VERSION", "The plan names no receiver version to condition the write on")
        } ElseIf wardStatus = 200 {
            Set seen = +##class(Interlock.Util.Json).Str(ward, "version", -1)
            Set current = $SELECT(request.ReceiverVersion '= "": request.ReceiverVersion, 1: seen)
            Do ..Check(checks, "concurrency", $SELECT(current = plan.ExpectedVersion: "pass", 1: "block"), $SELECT(current = plan.ExpectedVersion: "VERSION_MATCHES", 1: "RECEIVER_CHANGED"), "Expected version " _ plan.ExpectedVersion _ ", observed " _ current)
        } ElseIf (wardStatus = 404) && (case.Event = "admit") {
            Do ..Check(checks, "concurrency", $SELECT(plan.ExpectedVersion = 0: "pass", 1: "block"), $SELECT(plan.ExpectedVersion = 0: "VERSION_MATCHES", 1: "RECEIVER_CHANGED"), "An admission expects version 0")
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
    Set capable = ##class(Interlock.Util.Json).Bool(route, "conditional_writes") && ##class(Interlock.Util.Json).Bool(route, "receipts")
    Do ..Check(checks, "capability", $SELECT(capable || 'isWrite: "pass", 1: "block"), $SELECT(capable || 'isWrite: "CONNECTOR_CAPABLE", 1: "CONNECTOR_INCAPABLE"), "The connector supports conditional writes and receipts")

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
    Set sc = ##class(Interlock.Store.GateDecision).Create(case, plan, request.Stage, ..#POLICYVERSION, outcome, checks, text, .decision)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc)
    Set response.Outcome = outcome, response.ChecksJSON = checks.%ToJSON(), response.Summary = text
    If $ISOBJECT($GET(decision)) Set response.DecisionId = decision.%Id()
    Do case.Note("artifact", "Gate (" _ request.Stage _ "): " _ text, "system", "gate:" _ response.DecisionId)
    $$$TRACE("Gate " _ request.Stage _ " for " _ case.CaseId _ " plan v" _ plan.Version _ ": " _ outcome)
    Quit $$$OK
}

/// A later applied transfer or discharge for the encounter, described, or "".
Method Superseding(summary As %DynamicObject, case As Interlock.Store.Case) As %String [ Private ]
{
    Set found = ""
    Set timeline = summary.%Get("timeline")
    If $ISOBJECT(timeline) {
        Set iter = timeline.%GetIterator()
        While iter.%GetNext(.i, .ev) {
            If '##class(Interlock.Util.Json).Bool(ev, "later") Continue
            Set outcome = ##class(Interlock.Util.Json).Str(ev, "outcome")
            If (outcome '= "applied") && (outcome '= "already_committed") Continue
            Set event = ##class(Interlock.Util.Json).Str(ev, "event")
            If (event = "transfer") || (event = "discharge") {
                Set found = event _ $SELECT(##class(Interlock.Util.Json).Str(ev, "ward") '= "": " to " _ ev.ward, 1: "") _ " at " _ ##class(Interlock.Util.Json).Str(ev, "event_time")
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
                Set t = ##class(Interlock.Util.Json).Str(h, "event_time")
                If '(t ]] case.EventTime) Continue
                Set event = ##class(Interlock.Util.Json).Str(h, "event")
                If (event = "transfer") || (event = "discharge") Set found = event _ $SELECT(##class(Interlock.Util.Json).Str(h, "ward") '= "": " to " _ h.ward, 1: "") _ " at " _ t _ " (receiver history)"
            }
        }
    }
    Quit found
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
  <MapItem MessageType="Interlock.Msg.GateRequest">
    <Method>OnGateRequest</Method>
  </MapItem>
</MapItems>
}

}
