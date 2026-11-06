/// The verifier: reads the receiver's committed history and receipts after an attempt, or after
/// a non-write disposition, and says what holds. It never infers from a timeout or a missing
/// receipt that nothing was applied: a missing receipt after a write whose answer was lost is unknown, not a verdict, and
/// is read again until the settle window (UncertainSettleSeconds) has passed, when a person checks. Not committed is said
/// only once the version has moved past the one the write was conditional on, by something other than this write, so the
/// conditional write can no longer apply. A receipt holding other content than the case's operation closes nothing. The
/// verdict is Judge, a pure function of what was read (Context), so it can be tested without a receiver.
Class Shutter.Operation.Verify Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// The receiver whose paths are read when the case names none.
Property Receiver As %String(MAXLEN = 128) [ InitialExpression = {$PARAMETER("Shutter.Production", "RECEIVER")} ];

/// How long after a write whose answer was lost a missing receipt stays unknown rather than not committed, counted from
/// the attempt, which is recorded when the connector gives up. The last read comes at about 70 s (CaseWorkflow.OnVerify),
/// so this window is what that read judges by; a window of 30 s called a write not committed while a slow receiver still
/// held it. A receiver that can commit later still needs a larger value: past the last read, the verdict is then unknown.
Property UncertainSettleSeconds As %Integer [ InitialExpression = 60 ];

Parameter SETTINGS = "Receiver:Verify,UncertainSettleSeconds:Verify";

/// Whether the plan's catalogue entry closes the case with nothing to send on the case's evidence, as the gate judged.
ClassMethod ClosedByCatalogue(case As Shutter.Store.Case, plan As Shutter.Store.Plan) As %Boolean
{
    If '$ISOBJECT(plan) || '$ISOBJECT(case.CurrentSnapshot) Quit 0
    Set summary = case.CurrentSnapshot.SummaryObject()
    If '$ISOBJECT(summary) Quit 0
    Quit ##class(Shutter.Operation.Gate).ClosedByCatalogue(plan, summary)
}

Method OnVerifyRequest(request As Shutter.Msg.VerifyRequest, Output response As Shutter.Msg.VerifyResult) As %Status
{
    Set response = ##class(Shutter.Msg.VerifyResult).%New()
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Set response.Error = "Unknown case " _ request.CaseId, response.Outcome = "failed" Quit $$$OK
    Set plan = ##class(Shutter.Store.Plan).%OpenId(request.PlanId)
    Set attempt = ##class(Shutter.Store.ExecutionAttempt).%OpenId(request.AttemptId)
    Set receiver = $SELECT(case.Receiver '= "": case.Receiver, 1: ..Receiver)
    Set strict = ##class(Shutter.Store.SiteProfile).StrictAnswers(receiver)
    If case.EncounterId = "-" { Set estatus = 404, encounter = {"note": "Not applicable: the case names no encounter"} } Else { Set encounter = ..Get(##class(Shutter.Store.SiteProfile).ReceiverPath(receiver, "state", case.EncounterId), .estatus) Do ##class(Shutter.Operation.Ward).TrustRead("state", .estatus, .encounter, "", strict) }
    Set receiptPath = ##class(Shutter.Store.SiteProfile).ReceiverPath(receiver, "receipt", "", case.OperationKey)
    Set receipt = $SELECT(receiptPath = "": {}, 1: ..Get(receiptPath, .rstatus))
    If receiptPath '= "" Do ##class(Shutter.Operation.Ward).TrustRead("receipt", .rstatus, .receipt, case.OperationKey, strict)
    // -1: the receiver keeps no receipts; the committed history alone then shows the effect.
    If receiptPath = "" Set rstatus = -1
    Set summary = $SELECT($ISOBJECT(case.CurrentSnapshot): case.CurrentSnapshot.SummaryObject(), 1: "")
    Set ctx = ..Context(case, plan, attempt, summary, estatus, encounter, rstatus, receipt, ##class(Shutter.Util.Time).NowUTC(), ..UncertainSettleSeconds)
    Set outcome = ..Judge(ctx, .text, .detail)
    Set sc = ##class(Shutter.Store.Verification).Create(case, attempt, outcome, text, detail, .v)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc)
    Set response.Outcome = outcome, response.Summary = text, response.DetailJSON = detail.%ToJSON()
    If $ISOBJECT($GET(v)) Set response.VerificationId = v.%Id()
    Do case.Note("artifact", "Verification: " _ outcome _ ". " _ text, "system", "verification:" _ response.VerificationId)
    $$$TRACE("Verification for " _ case.CaseId _ ": " _ outcome)
    Quit $$$OK
}

/// What the verdict is judged on: the case and the plan (disposition, event, event_time, operation_key, encounter_id,
/// catalogue_entry, the ward, bed and payload_digest the receipt and the history are compared with, and strict_answers,
/// the receiver's entry in the site profile), the attempt when the plan wrote ({outcome, at, expected_version, http_status}, else null), the two
/// reads (encounter_http_status and encounter, receipt_http_status and receipt), closed_by_catalogue (the gate's
/// judgement of the plan's entry on the snapshot), the later events the matcher reads for the case (later: the
/// snapshot's timeline against the encounter as read now, with the snapshot's observation time and chain kind, so the
/// verifier cites what the gate would and nothing the gate refused), the clock (now) and settle_seconds.
ClassMethod Context(case As Shutter.Store.Case, plan As Shutter.Store.Plan, attempt As Shutter.Store.ExecutionAttempt, summary As %DynamicObject, estatus As %Integer, encounter As %DynamicObject, rstatus As %Integer, receipt As %DynamicObject, now As %String, settleSeconds As %Integer) As %DynamicObject
{
    Set json = "Shutter.Util.Json"
    Set ctx = {}
    Set ctx.disposition = $SELECT($ISOBJECT(plan): plan.Disposition, 1: case.Disposition)
    Set ctx.event = case.Event, ctx."event_time" = case.EventTime, ctx."operation_key" = case.OperationKey, ctx."encounter_id" = case.EncounterId
    Set ctx."catalogue_entry" = $SELECT($ISOBJECT(plan): plan.CatalogueEntry, 1: "")
    Set ctx.ward = case.Ward, ctx.bed = case.Bed, ctx."payload_digest" = case.PayloadDigest()
    Do ctx.%Set("strict_answers", ##class(Shutter.Store.SiteProfile).StrictAnswers(case.Receiver), "boolean")
    If $ISOBJECT(attempt) {
        Set a = {}
        Set a.outcome = attempt.Outcome, a.at = attempt.At, a."expected_version" = attempt.ExpectedVersion, a."http_status" = attempt.HttpStatus
        Set ctx.attempt = a
    } Else {
        Do ctx.%Set("attempt", "", "null")
    }
    Set ctx."encounter_http_status" = estatus, ctx.encounter = $SELECT($ISOBJECT(encounter): encounter, 1: {})
    Set ctx."receipt_http_status" = rstatus, ctx.receipt = $SELECT($ISOBJECT(receipt): receipt, 1: {})
    Do ctx.%Set("closed_by_catalogue", $ISOBJECT(plan) && $ISOBJECT(summary) && ##class(Shutter.Operation.Gate).ClosedByCatalogue(plan, summary), "boolean")
    // The later events as the matcher and the gate read them (CONTRACTS 6.1): the snapshot's timeline, the receiver's
    // history as read now, the snapshot's observation time for the plausibility rule and the chain kind its match used.
    Set view = {}
    Set observed = $SELECT($ISOBJECT(summary): $CLASSMETHOD(json, "Str", summary, "observed_at"), 1: "")
    Set view."observed_at" = $SELECT(observed '= "": observed, 1: now)
    If $ISOBJECT(summary) && $ISOBJECT(summary.%Get("timeline")) Set view.timeline = summary.%Get("timeline")
    If (estatus = 200) && $ISOBJECT(encounter) Set view."ward_state" = encounter
    Set cat = $SELECT($ISOBJECT(summary): summary.%Get("catalogue"), 1: "")
    Set conds = $SELECT($ISOBJECT(cat): cat.%Get("conditions"), 1: "")
    Set chainKind = $SELECT($ISOBJECT(conds): $CLASSMETHOD(json, "Str", conds, "chain"), 1: "")
    If chainKind = "" Set chainKind = "single"
    Set ctx.later = ##class(Shutter.Catalogue.Matcher).Later(view, case, chainKind)
    Set ctx.now = now, ctx."settle_seconds" = +settleSeconds
    Quit ctx
}

/// The verdict, from the context alone (Context): the outcome, its text, and the detail the verification records
/// (everything judged, with verdict, retry, attempt_outcome, seconds_since_attempt and version_moved). The outcomes:
/// verified (the receiver holds what the plan intends: the operation committed for a resend or a reconcile, the stale
/// operation absent and overtaken for a superseded closure), not_committed (proven: a write whose answer was lost, with
/// no receipt and no history entry, and the version moved past the one the write was conditional on by something other
/// than this write), unresolved (a lookup failed, or nothing is established: no sign of a write by the last read proves
/// nothing, since a slower receiver can still commit it; retry says whether another read could settle it), failed (the
/// receiver contradicts itself or the plan: a receipt without the history entry, a receipt or history entry holding
/// other content than the operation, an acknowledged write without a receipt, a stale operation with a receipt, a
/// reconcile whose receipt is gone). verdict is what holds of the operation at the receiver: committed, not_committed
/// or unknown; "not committed" is written only when it is the verdict.
ClassMethod Judge(ctx As %DynamicObject, Output text As %String, Output detail As %DynamicObject) As %String
{
    Set json = "Shutter.Util.Json"
    Set detail = ##class(%DynamicObject).%FromJSON(ctx.%ToJSON())
    Set disposition = $CLASSMETHOD(json, "Str", ctx, "disposition"), key = $CLASSMETHOD(json, "Str", ctx, "operation_key"), event = $CLASSMETHOD(json, "Str", ctx, "event")
    Set estatus = +$CLASSMETHOD(json, "Str", ctx, "encounter_http_status"), rstatus = +$CLASSMETHOD(json, "Str", ctx, "receipt_http_status")
    Set encounter = ctx.%Get("encounter"), receipt = ctx.%Get("receipt"), attempt = ctx.%Get("attempt")
    If '$ISOBJECT(encounter) Set encounter = {}
    If '$ISOBJECT(receipt) Set receipt = {}
    Set attemptOutcome = $SELECT($ISOBJECT(attempt): $CLASSMETHOD(json, "Str", attempt, "outcome"), 1: "")
    Set detail."attempt_outcome" = attemptOutcome, detail."seconds_since_attempt" = ""
    Do detail.%Set("version_moved", 0, "boolean")
    Set outcome = "unresolved", text = "", verdict = "unknown", retry = 0
    Set inHistory = (estatus = 200) && ..InHistory(encounter, key)
    Set current = $CLASSMETHOD(json, "Str", encounter, "ward"), state = $CLASSMETHOD(json, "Str", encounter, "state")
    Set where = state _ $SELECT(current '= "": " in " _ current, 1: "")
    // A site may read this receiver on status alone (SiteProfile.StrictAnswers); a context that does not say is checked.
    Set strict = $SELECT(ctx.%IsDefined("strict_answers"): $CLASSMETHOD(json, "Bool", ctx, "strict_answers"), 1: 1)
    If (estatus = 0) || (rstatus = 0) {
        Set text = "The receiver could not be read; nothing is established", retry = 1
    } ElseIf (disposition = "resend") || (disposition = "reconcile") {
        If (estatus '= 200) && (estatus '= 404) {
            Set text = "The receiver's encounter could not be read (HTTP " _ estatus _ "); nothing is established", retry = 1
        } ElseIf rstatus = 200 {
            Set differs = $SELECT(strict: ..ReceiptDiffers(receipt, ctx) _ ..HistoryDiffers(encounter, key, ctx), 1: "")
            If differs '= "" {
                // The key is taken, by a message with other content: what the receiver holds is not what the case is about.
                Set outcome = "failed"
                Set text = "The receiver holds this operation key with other content (" _ differs _ "); what it holds is not this case's message, and a person must check"
            } ElseIf inHistory {
                Set later = ..LaterThan(encounter, $CLASSMETHOD(json, "Str", ctx, "event_time"))
                Set outcome = "verified", verdict = "committed"
                If later '= "" {
                    Set text = "Committed (receipt " _ $EXTRACT($CLASSMETHOD(json, "Str", receipt, "applied_at"), 1, 19) _ ", version " _ $CLASSMETHOD(json, "Str", receipt, "version_after") _ "); a later event followed: " _ later _ ". Current state " _ where
                    Set detail."superseded_after" = later
                } Else {
                    Set text = "Committed and current: receipt " _ $EXTRACT($CLASSMETHOD(json, "Str", receipt, "applied_at"), 1, 19) _ ", version " _ $CLASSMETHOD(json, "Str", receipt, "version_after") _ "; the encounter is " _ where
                }
                Set text = text _ ..StoredTimeWords(encounter, key, ctx)
            } Else {
                Set outcome = "failed"
                Set text = "A receipt exists but the operation is missing from the committed history; the receiver contradicts itself, and a person must check"
            }
        } ElseIf (rstatus = 404) || (rstatus = -1) {
            If (rstatus = -1) && inHistory && strict && (..HistoryDiffers(encounter, key, ctx) '= "") {
                Set outcome = "failed"
                Set text = "The receiver's history holds this operation key with other content (" _ ..HistoryDiffers(encounter, key, ctx) _ "); what it holds is not this case's message, and a person must check"
            } ElseIf (rstatus = -1) && inHistory {
                Set outcome = "verified", verdict = "committed"
                Set text = "Committed: the operation is in the receiver's history (the receiver keeps no receipts). Current state " _ state _ ", version " _ $CLASSMETHOD(json, "Str", encounter, "version") _ ..StoredTimeWords(encounter, key, ctx)
            } ElseIf inHistory {
                Set outcome = "failed"
                Set text = "The receiver's history shows the operation but it holds no receipt for it; the receiver contradicts itself, and a person must check"
            } ElseIf disposition = "reconcile" {
                // The evidence showed the operation committed; the receiver no longer does. No claim about what was committed.
                Set outcome = "failed"
                Set text = "Nothing to reconcile: " _ $SELECT(rstatus = -1: "the receiver keeps no receipts and its history does not show the operation, though the evidence showed it", 1: "the receiver holds no receipt for the operation, though the evidence showed one")
            } ElseIf (attemptOutcome = "applied") || (attemptOutcome = "already_committed") {
                Set outcome = "failed"
                Set text = "The receiver acknowledged the write (HTTP " _ $CLASSMETHOD(json, "Str", attempt, "http_status") _ ") but holds no receipt for it and its history does not show it; the receiver contradicts itself, and a person must check"
            } ElseIf attemptOutcome = "uncertain" {
                // The answer was lost: the write may still be in flight. Time and the version decide, never the absence alone.
                Set expected = $CLASSMETHOD(json, "Str", attempt, "expected_version")
                Set elapsed = ..Elapsed($CLASSMETHOD(json, "Str", attempt, "at"), $CLASSMETHOD(json, "Str", ctx, "now"))
                Set detail."seconds_since_attempt" = elapsed
                Set known = (estatus = 200) || ((estatus = 404) && (event = "admit"))
                Set version = $SELECT(estatus = 200: $CLASSMETHOD(json, "Str", encounter, "version"), 1: 0)
                Set moved = known && (version '= "") && (expected '= "") && (+version '= +expected)
                Do detail.%Set("version_moved", moved, "boolean")
                If 'known {
                    Set text = "The receiver no longer knows the encounter; a person must check"
                } ElseIf elapsed = "" {
                    Set text = "No receipt yet, and the attempt's time is not recorded; the write may still be in flight, so nothing is established", retry = 1
                } ElseIf moved && ((rstatus = 404) || ..HistoryNamesKeys(encounter)) {
                    // The one proof: the version moved, and the receiver can say the move was not this write.
                    Set outcome = "not_committed", verdict = "not_committed"
                    Set text = "Not committed: " _ elapsed _ " s after the write the receiver holds no receipt for the operation and its history does not show it, and the encounter moved from version " _ expected _ " to " _ version _ " by something else, so the conditional write can no longer apply"
                } ElseIf moved {
                    Set text = "The encounter moved from version " _ expected _ " to " _ version _ ", and this receiver keeps no receipts and its history names no operation keys, so the move could be this write; a person must check"
                } ElseIf elapsed < +$CLASSMETHOD(json, "Str", ctx, "settle_seconds") {
                    Set text = "No receipt yet, " _ elapsed _ " s after a write whose answer was lost; the write may still be in flight, so nothing is established", retry = 1
                } Else {
                    // Time alone proves nothing: this is the last read, so a person checks at the receiver.
                    Set text = "No sign of the write by the last read, " _ elapsed _ " s after it: the receiver holds no receipt for the operation, its history does not show it, and the encounter is " _ $SELECT(expected '= "": "still at version " _ expected _ ", the version the write was conditional on", 1: "at version " _ version) _ ". Nothing shows it was applied; a slower receiver can still commit it"
                }
            } Else {
                Set text = "No attempt is recorded for the resend, and the receiver holds no receipt for the operation; a person must check"
            }
        } Else {
            Set text = "The receipt lookup answered HTTP " _ rstatus, retry = 1
        }
    } ElseIf disposition = "superseded" {
        If estatus = 200 {
            Set later = ..Support(ctx.%Get("later"), "history", .ev)
            If (later '= "") && ((rstatus = 404) || (rstatus = -1)) {
                Set outcome = "verified", verdict = "not_committed"
                Set text = "Nothing was resent; the receiver's history shows the later event (" _ later _ ") and no receipt for the stale operation. Current state " _ where
            } ElseIf rstatus = 200 {
                Set outcome = "failed", verdict = "committed"
                Set text = "The stale operation has a receipt after all: it was committed"
            } ElseIf (rstatus '= 404) && (rstatus '= -1) {
                // A lookup that failed is no statement about the receipt, in any of the closures below.
                Set text = "The receipt lookup answered HTTP " _ rstatus, retry = 1
            } ElseIf 'inHistory && (..Support(ctx.%Get("later"), "timeline", .ev) '= "") {
                // The later transfer the feed sent whose delivery failed or is uncertain, which the gate accepted outside a
                // chain (SUPERSEDED_BY_LATER_EVENT): its own case recovers the patient's location, and is told (OnVerify).
                Set outcome = "verified", verdict = "not_committed"
                Set text = "Nothing was resent; the receiver's history shows no later event, but the feed sent one after it: " _ ##class(Shutter.Catalogue.Matcher).Describe(ev) _ ". The receiver holds no receipt for the stale operation. Current state " _ where
                Set detail."superseded_by" = ev
            } ElseIf $CLASSMETHOD(json, "Bool", ctx, "closed_by_catalogue") && 'inHistory {
                // The gate passed the closure on the catalogue entry's say-so (CLOSED_BY_CATALOGUE): the receiver holds
                // neither a receipt nor the operation, which is what closing with nothing to send requires.
                Set outcome = "verified", verdict = "not_committed"
                Set text = "Nothing was resent; catalogue entry " _ $CLASSMETHOD(json, "Str", ctx, "catalogue_entry") _ " closes the case with nothing to send, and the receiver holds neither a receipt nor the operation in its history. Current state " _ where
            } Else {
                Set text = "No later event in the receiver's history supports the supersession"
            }
        } Else {
            Set patientLevel = ($CLASSMETHOD(json, "Str", ctx, "encounter_id") = "-")
            Set text = $SELECT(patientLevel: "A patient-level case names no encounter to verify against; a person decides", 1: "The receiver's encounter could not be read (HTTP " _ estatus _ ")")
            Set retry = 'patientLevel && (estatus '= 404)
        }
    } Else {
        Set text = "Disposition " _ disposition _ ": nothing to verify at the receiver"
    }
    Set detail.verdict = verdict
    Do detail.%Set("retry", ''retry, "boolean")
    Quit outcome
}

/// Seconds from the attempt to now, or "" when either time is missing or cannot be read.
ClassMethod Elapsed(at As %String, now As %String) As %String [ Private ]
{
    If (at = "") || (now = "") Quit ""
    Set seconds = ""
    Try {
        Set seconds = ##class(Shutter.Util.Time).SecondsBetween(at, now)
    } Catch ex {
        Set seconds = ""
    }
    Quit seconds
}

/// The last plausible later transfer or discharge among the later events (Shutter.Catalogue.Matcher.Later) from one
/// source, described, or "": the receiver's history (from "history", delivered), in the words the history has always
/// been cited in; or the feed's timeline with the delivery failed or uncertain (from "timeline", delivered 0: the later
/// transfer the gate accepts outside a chain), with the key it was sent as and its case. ev is the entry found.
ClassMethod Support(later As %DynamicArray, from As %String, Output ev As %DynamicObject) As %String [ Private ]
{
    Set ev = "", found = ""
    If '$ISOBJECT(later) Quit ""
    Set json = "Shutter.Util.Json"
    Set iter = later.%GetIterator()
    While iter.%GetNext(.i, .e) {
        Continue:'$ISOBJECT(e)
        Continue:($CLASSMETHOD(json, "Str", e, "from") '= from)
        Continue:($CLASSMETHOD(json, "Bool", e, "delivered") '= (from = "history"))
        Continue:'$CLASSMETHOD(json, "Bool", e, "plausible")
        Set word = $CLASSMETHOD(json, "Str", e, "word")
        Continue:((word '= "transfer") && (word '= "discharge"))
        Set ev = e, found = ##class(Shutter.Catalogue.Matcher).Describe(e, from = "timeline")
    }
    Quit found
}

Method Get(path As %String, Output status As %Integer) As %DynamicObject [ Private ]
{
    Set status = 0, body = {}
    Try {
        Set http = ##class(%Net.HttpRequest).%New()
        Set sc = ..Adapter.SendFormDataArray(.resp, "GET", http, "", "", path)
        Set ..Retry = 0
        If $ISOBJECT($GET(resp)) {
            Set status = +resp.StatusCode
            Set text = ""
            If $ISOBJECT(resp.Data) { Do resp.Data.Rewind() While 'resp.Data.AtEnd { Set text = text _ resp.Data.Read(32000) } }
            Set parsed = ##class(Shutter.Util.Json).Parse(text, .psc)
            If $ISOBJECT(parsed) && $$$ISOK(psc) Set body = parsed
        } ElseIf $$$ISERR(sc) {
            Set body.error = $SYSTEM.Status.GetErrorText(sc)
        }
    } Catch ex {
        Set body.error = ex.DisplayString()
    }
    Quit body
}

/// True when the encounter's history has an entry for the operation key.
ClassMethod InHistory(encounter As %DynamicObject, key As %String) As %Boolean
{
    Set history = encounter.%Get("history")
    If '$ISOBJECT(history) Quit 0
    Set iter = history.%GetIterator()
    While iter.%GetNext(.i, .h) { If ##class(Shutter.Util.Json).Str(h, "operation_key") = key Quit }
    Quit $ISOBJECT($GET(h)) && (##class(Shutter.Util.Json).Str(h, "operation_key") = key)
}

/// How a receipt differs from an operation (an object with payload_digest, ward and bed), in words, or "" when it does not
/// or there is nothing to compare: a receipt or an operation that names no digest, or no bed, says nothing about it. Bed
/// sits outside the digest (CONTRACTS 1.6), so a correction of the bed alone shows only here. Read by the gate on a
/// reconcile, the verifier on a committed operation, and the feed on an already_committed answer.
ClassMethod ReceiptDiffers(receipt As %DynamicObject, op As %DynamicObject) As %String
{
    If '$ISOBJECT(receipt) || '$ISOBJECT(op) Quit ""
    Set json = "Shutter.Util.Json", words = ""
    Set held = $CLASSMETHOD(json, "Str", receipt, "payload_digest"), ours = $CLASSMETHOD(json, "Str", op, "payload_digest")
    If (held '= "") && (ours '= "") && (held '= ours) {
        Set heldWard = $CLASSMETHOD(json, "Str", receipt, "ward"), ourWard = $CLASSMETHOD(json, "Str", op, "ward")
        Set words = $SELECT(heldWard '= ourWard: "ward " _ ..Named(heldWard) _ " against this message's " _ ..Named(ourWard), 1: "its payload digest differs")
    }
    If (receipt.%GetTypeOf("bed") '= "unassigned") && (op.%GetTypeOf("bed") '= "unassigned") {
        Set held = $CLASSMETHOD(json, "Str", receipt, "bed"), ours = $CLASSMETHOD(json, "Str", op, "bed")
        If held '= ours Set words = words _ $SELECT(words '= "": ", ", 1: "") _ "bed " _ ..Named(held) _ " against this message's " _ ..Named(ours)
    }
    Quit words
}

ClassMethod Named(value As %String) As %String [ Private ]
{
    Quit $SELECT(value = "": "none", 1: value)
}

/// The history's entry for the operation key, or "".
ClassMethod HistoryEntry(encounter As %DynamicObject, key As %String) As %DynamicObject [ Private ]
{
    Set history = encounter.%Get("history")
    If '$ISOBJECT(history) Quit ""
    Set iter = history.%GetIterator()
    While iter.%GetNext(.i, .h) { If $ISOBJECT(h) && (##class(Shutter.Util.Json).Str(h, "operation_key") = key) Return h }
    Quit ""
}

/// How the history's entry for the key differs from the operation's ward, in words, or "". An admission or a transfer names
/// a ward; anything else has none to compare.
ClassMethod HistoryDiffers(encounter As %DynamicObject, key As %String, ctx As %DynamicObject) As %String [ Private ]
{
    Set json = "Shutter.Util.Json"
    Set event = $CLASSMETHOD(json, "Str", ctx, "event")
    If (event '= "transfer") && (event '= "admit") Quit ""
    Set h = ..HistoryEntry(encounter, key)
    If '$ISOBJECT(h) Quit ""
    Set held = $CLASSMETHOD(json, "Str", h, "ward"), ours = $CLASSMETHOD(json, "Str", ctx, "ward")
    If (held = "") || (ours = "") || (held = ours) Quit ""
    Quit "its history has ward " _ held _ " against this message's " _ ours
}

/// A sentence when the history's entry for the key stores another event time than was sent (a receiver that stamps arrival
/// time), else "". The ordering decisions use the key's time (Matcher.HistoryTime).
ClassMethod StoredTimeWords(encounter As %DynamicObject, key As %String, ctx As %DynamicObject) As %String [ Private ]
{
    Set h = ..HistoryEntry(encounter, key)
    If '$ISOBJECT(h) Quit ""
    Set held = ##class(Shutter.Util.Json).Str(h, "event_time"), sent = ##class(Shutter.Util.Json).Str(ctx, "event_time")
    If (held = "") || (sent = "") || (held = sent) Quit ""
    Quit ". The receiver stored its event time as " _ held _ ", not " _ sent
}

/// Whether the history's entries carry operation keys, so that a version moved with this operation's key absent shows the
/// move was something else. With neither keys nor receipts the move could be this write.
ClassMethod HistoryNamesKeys(encounter As %DynamicObject) As %Boolean [ Private ]
{
    Set history = encounter.%Get("history")
    If '$ISOBJECT(history) || (history.%Size() = 0) Quit 0
    Set iter = history.%GetIterator()
    While iter.%GetNext(.i, .h) { If '$ISOBJECT(h) || (##class(Shutter.Util.Json).Str(h, "operation_key") = "") Return 0 }
    Quit 1
}

/// The latest transfer or discharge in the history after a time, described, or "": what followed a committed write.
ClassMethod LaterThan(encounter As %DynamicObject, eventTime As %String) As %String
{
    Set found = ""
    Set history = encounter.%Get("history")
    If '$ISOBJECT(history) Quit ""
    Set iter = history.%GetIterator()
    While iter.%GetNext(.i, .h) {
        Set t = ##class(Shutter.Catalogue.Matcher).HistoryTime(h)
        If '(t ]] eventTime) Continue
        Set event = ##class(Shutter.Util.Json).Str(h, "event")
        If (event = "transfer") || (event = "discharge") Set found = event _ $SELECT(##class(Shutter.Util.Json).Str(h, "ward") '= "": " to " _ h.ward, 1: "") _ " at " _ t
    }
    Quit found
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.VerifyRequest">
    <Method>OnVerifyRequest</Method>
  </MapItem>
</MapItems>
}

}
