/// The steps of a case whose receiver is a FHIR R4 receiver, between the evidence and the close: the plan, the FHIR
/// gate at the proposal, the seal of the one update, a person's approval of this case alone, the read just before the
/// write, the FHIR gate at the dispatch, the one version-aware update, and the walk that verifies it.
///
/// Class methods only; <var>p</var> is the case's workflow instance (Shutter.Process.CaseWorkflow), which keeps the
/// identifiers between steps, and every send goes through its FHIRSend. No step waits and none makes an HTTP call:
/// each sends one request to a production item and ends, and the answer comes back to OnResponse under a key that
/// begins "fhir:". A step therefore works from the store and the identifiers alone, on any instance of the workflow.
///
/// What is never done for such a case: no dry run (the receiver has none, and the case never reads "rehearsing"), no
/// release by a policy or under an incident's approval, no board, and no second update under one approval. Where the
/// one update may have left, the fence row of the approval (Shutter.Store.FHIRAttempt) decides what an error means:
/// sent is an outcome nobody knows, never "not applied".
///
/// A stop that no failing row of the gate explains ends its event text with its reason code in brackets, which is
/// where the case's reason is read from (Shutter.API.Dispatch, ReasonFromEvent).
Class Shutter.FHIR.Flow [ Abstract ]
{

/// The production items, by name.
Parameter GATE = "FHIR Gate";

Parameter READER = "FHIR Receiver";

Parameter OUT = "FHIR Out";

Parameter VERIFIER = "FHIR Verifier";

/// The unknowns of the gate that a fresh read can answer.
Parameter REFRESHABLE = "STALE_EVIDENCE,FHIR_RECEIVER_UNREADABLE,FHIR_CAPABILITIES_UNREADABLE,FHIR_HISTORY_UNAVAILABLE,FHIR_LOCATION_UNREADABLE,ENGINE_UNREADABLE";

/// The summary of every plan that writes.
Parameter WRITESUMMARY = "One update of the Encounter's location with If-Match on the version read, after this case's own approval. The HL7 message is not sent again.";

// ---- the plan ----

/// Plans a FHIR case on its fresh evidence. Rules only proposes the update whatever the catalogue matched (the gate's
/// rows stop it); every other mode follows the catalogue's one entry when it says resend, and asks a person otherwise.
/// No board plans or reviews a FHIR plan, a convened one included, and no plan carries an expected version.
ClassMethod Plan(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, summary As %DynamicObject, cat As %DynamicObject) As %Status
{
    Set json = "Shutter.Util.Json"
    Do ..Backfill(case)
    // A fresh plan: nothing of an earlier one is carried.
    Set p.FHIRBindingId = ""
    If p.ForceBoard Do case.Note("note", "A board was asked for. No board plans or reviews a FHIR plan, so the case is planned as every FHIR case is", "system")
    Set operation = $SELECT($ISOBJECT(summary): summary.%Get("operation"), 1: "")
    Set action = {"type": "resend", "operation_key": (case.OperationKey), "payload_digest": ($CLASSMETHOD(json, "Str", operation, "payload_digest"))}
    If p.Mode = "rules" {
        Set plan = {"disposition": "resend", "summary": (..#WRITESUMMARY), "action": (action), "preconditions": [], "evidence_refs": [], "disagreements": []}
        Do case.Note("note", "Rules-only mode: no agents consulted", "system")
        Quit p.AdoptPlan(case, plan, "rules")
    }
    Set decision = $SELECT($ISOBJECT(cat): $CLASSMETHOD(json, "Str", cat, "decision"), 1: "")
    Set outcome = $SELECT($ISOBJECT(cat): $CLASSMETHOD(json, "Str", cat, "outcome"), 1: "")
    Set entry = $SELECT($ISOBJECT(cat): $CLASSMETHOD(json, "Str", cat, "entry"), 1: "")
    If (decision = "policy") && (outcome = "resend") && (entry '= "") {
        // The outcome the matcher settled on, named as the policy path names it (CaseWorkflow, PolicyPath).
        Set ref = $CLASSMETHOD(json, "Str", cat, "outcome_ref", "preferred")
        Set matches = cat.%Get("matches")
        Set m = $SELECT($ISOBJECT(matches) && (matches.%Size() > 0): matches.%Get(0), 1: "")
        Set chosen = $SELECT($ISOBJECT(m): m.%Get("preferred"), 1: "")
        If $ISOBJECT(m) && ($EXTRACT(ref, 1, 12) = "alternative:") {
            Set alts = m.%Get("alternatives"), n = +$PIECE(ref, ":", 2)
            If $ISOBJECT(alts) && (n >= 1) && (n <= alts.%Size()) Set chosen = alts.%Get(n - 1)
        }
        // The entry settles what is proposed, never who releases it: a person approves this case's update.
        Set p.Policy = "approval", p.CatalogueEntry = entry, p.CatalogueOutcome = ref
        Set plan = {"disposition": "resend", "summary": (..#WRITESUMMARY), "action": (action), "preconditions": [], "evidence_refs": ["catalogue", "ward_state", "receipt", "timeline", "route"], "disagreements": []}
        Set plan."catalogue_entry" = entry, plan.outcome = ref, plan.why = $CLASSMETHOD(json, "Str", chosen, "why")
        Do case.Note("note", "Catalogue " _ entry _ " (" _ $CLASSMETHOD(json, "Str", m, "title") _ ") matched alone: " _ outcome _ ". Over FHIR a person approves this case's own update, whatever the site's policy releases elsewhere", "system")
        Quit p.AdoptPlan(case, plan, "policy:" _ entry)
    }
    Set found = $CASE(decision, "": "the catalogue gave no result", "policy": "the catalogue's entry " _ entry _ " says " _ outcome _ ", not a resend", "person": "the catalogue asks for a person", "new_pattern": "no catalogue entry matches this evidence", : "the catalogue answered " _ decision)
    Set plan = {"disposition": "escalate", "action": {"type": "none"}, "preconditions": [], "evidence_refs": ["catalogue"], "disagreements": []}
    Set plan.summary = "Over FHIR an update is proposed only where the catalogue's one matching entry says resend; here " _ found _ ", so a person decides (FHIR_PLAN_NEEDS_PERSON)"
    Quit p.AdoptPlan(case, plan, "fhir")
}

/// A sent fence row of the case that names no attempt (a case abandoned or stopped in the middle of its write) gets
/// its attempt row: with the answer the row recorded when it has one, and as uncertain when it has none, so every
/// surface counts it as an update that may have landed. Never an error for the caller.
ClassMethod Backfill(case As Shutter.Store.Case) As %Integer
{
    Set made = 0
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.FHIRAttempt WHERE ""Case"" = ? AND State = 'sent' AND ExecutionAttemptId IS NULL ORDER BY ID", case.%Id())
        Set ids = ""
        While rs.%Next() { Set ids = ids _ $LISTBUILD(rs.%Get("ID")) }
        For i = 1:1:$LISTLENGTH(ids) {
            Set fence = ##class(Shutter.Store.FHIRAttempt).%OpenId($LIST(ids, i))
            Continue:'$ISOBJECT(fence)
            Do fence.%Reload()
            Continue:(fence.State'="sent")||(fence.ExecutionAttemptId'="")
            Set answered = (fence.AnsweredAt '= "") && (fence.Outcome '= "")
            Set outcome = $SELECT(answered: fence.Outcome, 1: "uncertain"), status = $SELECT(answered: +fence.HttpStatus, 1: 0)
            Set plan = $SELECT(fence.PlanId = "": "", 1: ##class(Shutter.Store.Plan).%OpenId(fence.PlanId))
            Set approval = ##class(Shutter.Store.Approval).%OpenId(fence.ApprovalId)
            Set binding = $SELECT(fence.BindingId = "": "", 1: ##class(Shutter.Store.FHIRBinding).%OpenId(fence.BindingId))
            Set why = "Recorded afterwards: the update was sent at " _ fence.SentAt _ " and the case stopped before its attempt was written" _ $SELECT(answered: "", 1: "; no answer is on record, so it may have been applied")
            Set response = ..AttemptResponse(binding, fence, 1, "", fence.Diagnostics)
            Set sc = ##class(Shutter.Store.ExecutionAttempt).Create(case, plan, approval, "", status, outcome, response, why, .attempt)
            If $$$ISERR(sc) Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "Backfill", "No attempt row for the sent update of " _ case.CaseId _ ": " _ $SYSTEM.Status.GetErrorText(sc)) Continue
            Do fence.SetExecutionAttempt(attempt.%Id())
            Do case.Note("execution", "FHIR update: " _ outcome _ ", " _ ..HttpWords(status) _ ". It was sent at " _ fence.SentAt _ " under an earlier approval and had no attempt on record; it is recorded now", "system", "attempt:" _ attempt.%Id())
            Set made = made + 1
        }
    } Catch ex {
        Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "Backfill", "The sent updates of " _ case.CaseId _ " could not be checked for their attempt rows: " _ ex.DisplayString())
    }
    Quit made
}

// ---- the gate ----

/// Sends the plan to the FHIR gate at one stage. With the FHIR items missing or disagreeing the case blocks here. At
/// the proposal a plan that writes gets its headline first: the workflow's own would promise a rehearsal.
ClassMethod SendGate(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, stage As %String, readId As %String = "") As %Status
{
    Set problem = ##class(Shutter.FHIR.Install).Problem()
    If problem '= "" {
        Quit ..Stop(p, case, "blocked", "Blocked: the FHIR items are missing or disagree", "The production cannot reach this FHIR receiver: " _ ..Plain(problem) _ ". Nothing was read or sent (FHIR_ITEMS_MISSING)")
    }
    Set plan = $SELECT(p.PlanId = "": "", 1: ##class(Shutter.Store.Plan).%OpenId(p.PlanId))
    If (stage = "proposal") && $ISOBJECT(plan) && plan.IsWrite() {
        Set case.Headline = ..WriteHeadline(case)
        Set sc = case.%Save()
        Quit:$$$ISERR(sc) sc
    }
    Set req = ##class(Shutter.Msg.FHIRGateRequest).%New()
    Set req.CaseId = case.CaseId, req.PlanId = p.PlanId, req.Stage = stage, req.ApprovalId = p.ApprovalId, req.ChainKind = p.ChainKind
    Set req.ReadId = readId
    Quit p.FHIRSend(..#GATE, req, "fhir:gate:" _ stage)
}

/// The headline of a case whose plan writes: what will be done, once, and what will not.
ClassMethod WriteHeadline(case As Shutter.Store.Case) As %String
{
    Do ..Wards(case, .prior, .target)
    Quit "Update the Encounter's location once, " _ prior _ " to " _ target _ ", after this case's own approval. No dry run exists for this receiver. The HL7 message is not sent again."
}

/// The two wards of the message, from the snapshot's FHIR evidence; words in their place when it names none.
ClassMethod Wards(case As Shutter.Store.Case, Output prior As %String, Output target As %String)
{
    Set prior = "", target = ""
    Try {
        Set summary = $SELECT($ISOBJECT(case.CurrentSnapshot): case.CurrentSnapshot.SummaryObject(), 1: "")
        Set fhir = $SELECT($ISOBJECT(summary): summary.%Get("fhir"), 1: "")
        Set message = $SELECT($ISOBJECT(fhir): fhir.%Get("message"), 1: "")
        Set prior = ##class(Shutter.Util.Json).Str(message, "prior_ward"), target = ##class(Shutter.Util.Json).Str(message, "target_ward")
    } Catch ex {
        Set prior = "", target = ""
    }
    If target = "" Set target = case.Ward
    If prior = "" Set prior = "the ward the message names as left"
    If target = "" Set target = "the ward the message names"
}

/// Dispatches the answer of a call the flow made, by its key. A handler that fails after the update was sent ends
/// the case as an outcome nobody knows, never as a workflow failure with the approval standing; one that fails before
/// leaves the error to the caller, with the approval revoked.
ClassMethod OnResponse(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, key As %String, callrequest As %Library.Persistent, callresponse As %Library.Persistent) As %Status
{
    Set sc = $$$OK
    Try {
        Set sc = $CASE(key,
            "fhir:gate:proposal": ..OnGateProposal(p, case, callresponse),
            "fhir:approval": ..OnApproval(p, case, callresponse),
            "fhir:preflight": ..OnPreflight(p, case, callresponse),
            "fhir:preflight:retry": ..SendPreflight(p, case),
            "fhir:gate:dispatch": ..OnGateDispatch(p, case, callresponse),
            "fhir:execute": ..OnExecute(p, case, callresponse),
            "fhir:verify": ..OnVerify(p, case, callresponse),
            "fhir:verify:retry": ..SendVerify(p, case),
            : ..Unexpected(key))
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISOK(sc) Quit sc
    Set text = $EXTRACT($SYSTEM.Status.GetErrorText(sc), 1, 400)
    If ..Sent(p) {
        Set stopped = ..ItemFailed(p, case, "the workflow failed at " _ key _ ": " _ text)
        Quit $SELECT($$$ISOK(stopped): $$$OK, 1: sc)
    }
    Do ..Revoke(p, "the workflow failed at " _ key _ " before anything was sent")
    Quit sc
}

/// A key the flow does not have.
ClassMethod Unexpected(key As %String) As %Status
{
    Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "OnResponse", "Unexpected completion key " _ key)
    Quit $$$OK
}

/// An item the flow called answered with an error status. 1 when the error was handled here, 0 to leave it to the
/// workflow's own branch (the approval task, or a stop that could not be written).
ClassMethod OnError(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, key As %String, text As %String) As %Boolean
{
    If key = "fhir:approval" Quit 0
    Set sc = $$$OK
    Try {
        If key = "fhir:execute" {
            Set sc = ..OnExecuteError(p, case, text)
        } Else {
            Set sc = ..ItemFailed(p, case, text)
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "OnError", "The error at " _ key _ " of " _ case.CaseId _ " could not be recorded as a stop: " _ $SYSTEM.Status.GetErrorText(sc))
    Quit $$$ISOK(sc)
}

/// The answer of the FHIR gate at the proposal.
ClassMethod OnGateProposal(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, result As Shutter.Msg.GateResult) As %Status
{
    If '$ISOBJECT(result) Quit ..ItemFailed(p, case, "the FHIR gate gave no answer")
    // The gate answers what it could not decide as an error with no decision: an item's failure, not a verdict.
    If (result.Error '= "") && (result.DecisionId = "") Quit ..ItemFailed(p, case, result.Error)
    Set plan = ##class(Shutter.Store.Plan).%OpenId(p.PlanId)
    If '$ISOBJECT(plan) Quit $$$ERROR($$$GeneralError, "The FHIR gate answered for plan " _ p.PlanId _ ", which is not there")
    Set sc = case.Transition("gated", "FHIR gate at proposal: " _ result.Outcome _ ". " _ result.Summary, "gate", "gate:" _ result.DecisionId)
    Quit:$$$ISERR(sc) sc
    Do ##class(Shutter.Store.ShadowObservation).Capture(case, plan, result)
    // A plan that asks for a person is escalated whatever the gate found; the gate's result stays on the case.
    If (plan.Disposition = "escalate") || (plan.Disposition = "more_evidence") {
        Quit case.Transition("escalated", "The plan asks for a person: " _ plan.Summary _ $SELECT(result.Outcome '= "pass": " (the gate noted: " _ result.Summary _ ")", 1: ""), "system", "plan:" _ plan.%Id())
    }
    If result.Outcome '= "pass" {
        // A read that failed is not a verdict: the evidence is collected again and the case planned afresh, up to the limit.
        If ..OnlyRefreshable(result) && (p.Refreshes < p.MaxRefreshes) {
            Set p.Refreshes = p.Refreshes + 1, p.Refreshing = 0
            Set p.PlanId = "", p.PendingJSON = "[]", p.FHIRBindingId = ""
            Set wait = 10 * (2 ** (p.Refreshes - 1))
            Do case.Note("note", "The FHIR gate could not decide at the proposal (" _ result.Summary _ "); collecting the evidence again in " _ wait _ " s and planning afresh (" _ p.Refreshes _ " of " _ p.MaxRefreshes _ ")", "gate", "gate:" _ result.DecisionId)
            Quit ..Alarm(p, wait, "refresh:retry")
        }
        Set case.Headline = "Blocked by the FHIR gate: " _ result.Summary
        Quit case.Transition("blocked", "The FHIR gate did not pass the plan; a person must decide", "gate", "gate:" _ result.DecisionId)
    }
    If 'plan.IsWrite() {
        Quit ..Stop(p, case, "escalated", "Escalated: over FHIR nothing closes by itself", "Over FHIR Shutter closes no case without a person or a verified update; a person decides (FHIR_PLAN_NEEDS_PERSON)", "plan:" _ plan.%Id())
    }
    // Shadow mode or the stop: nothing is asked of an approver, since nothing may be sent.
    Set refusal = ##class(Shutter.Store.ShadowObservation).Words(plan, result)
    If refusal '= "" Quit ..Stop(p, case, "escalated", refusal, refusal, "plan:" _ plan.%Id())
    Set code = ..SealBinding(p, case, plan, .binding, .reason)
    If code '= "" {
        Quit ..Stop(p, case, "blocked", "Blocked: the update could not be sealed for approval", "The update could not be sealed for approval: " _ ..Plain(reason) _ " (" _ code _ ")", "plan:" _ plan.%Id())
    }
    Set sc = case.Transition("awaiting_approval", "No dry run exists for this receiver; asking an approver for the exact plan", "system", "plan:" _ plan.%Id())
    Quit:$$$ISERR(sc) sc
    Set sc = p.FHIRSend(p.ApprovalTarget, ..ApprovalTask(case, plan, binding, p.ApprovalWaitSeconds), "fhir:approval")
    Quit:$$$ISERR(sc) sc
    // The wait is bounded: an alarm keyed by the round, under the workflow's own key, so its own handler takes it.
    If p.ApprovalWaitSeconds > 0 Set sc = ..Alarm(p, p.ApprovalWaitSeconds, "approval:timeout:" _ p.Round, "The approval wait")
    Quit sc
}

/// Whether every check that did not pass is an unknown a fresh read can answer.
ClassMethod OnlyRefreshable(result As Shutter.Msg.GateResult) As %Boolean
{
    Set checks = ##class(Shutter.Util.Json).Parse(result.ChecksJSON, .psc)
    If '$ISOBJECT(checks) || (checks.%Size() = 0) Quit 0
    Set found = 0, codes = $LISTFROMSTRING(..#REFRESHABLE)
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) {
        Continue:(##class(Shutter.Util.Json).Str(c, "result") = "pass")
        If ##class(Shutter.Util.Json).Str(c, "result") '= "unknown" Return 0
        If '$LISTFIND(codes, ##class(Shutter.Util.Json).Str(c, "reason_code")) Return 0
        Set found = 1
    }
    Quit found
}

/// Seals what the plan's one update is bound to, from the case's current snapshot, and keeps the binding's id on the
/// workflow. Returns "" with the binding, or a reason code with <var>reason</var> saying why in words.
ClassMethod SealBinding(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, plan As Shutter.Store.Plan, Output binding As Shutter.Store.FHIRBinding, Output reason As %String) As %String
{
    Set binding = "", reason = "", code = ""
    Try {
        Set snapshot = case.CurrentSnapshot
        Set summary = $SELECT($ISOBJECT(snapshot): snapshot.SummaryObject(), 1: "")
        Set fhir = $SELECT($ISOBJECT(summary): summary.%Get("fhir"), 1: "")
        Set body = ##class(Shutter.FHIR.Reader).SealedBody(snapshot)
        Set entry = ##class(Shutter.Store.SiteProfile).Receiver(case.Receiver)
        Set code = ##class(Shutter.FHIR.Proposal).Prepare(case, plan.Digest, fhir, body, entry, .prepared)
        If code '= "" {
            Set why = ##class(Shutter.Util.Json).Str(prepared, "reason"), path = ##class(Shutter.Util.Json).Str(prepared, "path")
            Set reason = "the update could not be built" _ $SELECT(why '= "": " (" _ why _ $SELECT(path '= "": ", " _ path, 1: "") _ ")", 1: "")
            Quit
        }
        Set sc = ##class(Shutter.Store.FHIRBinding).Seal(case, plan, prepared, .binding)
        If $$$ISERR(sc) || '$ISOBJECT(binding) {
            Set code = "FHIR_NO_BINDING", binding = ""
            Set reason = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no binding was stored")
            Quit
        }
        Set p.FHIRBindingId = binding.%Id()
    } Catch ex {
        Set code = "FHIR_NO_BINDING", binding = "", reason = ex.DisplayString()
    }
    Quit code
}

// ---- the approval ----

/// The approval task of a FHIR case's plan. Its subject and its form are the workflow's own, so the timeout, the
/// cancel, the close and the abandon find it as they find any; its words say what will be sent, that nothing was
/// rehearsed, and that the HL7 message stays where it is.
ClassMethod ApprovalTask(case As Shutter.Store.Case, plan As Shutter.Store.Plan, binding As Shutter.Store.FHIRBinding, waitSeconds As %Integer = 0) As EnsLib.Workflow.TaskRequest
{
    Set lf = $CHAR(10), workflow = "Shutter.Process.CaseWorkflow"
    Set task = ##class(EnsLib.Workflow.TaskRequest).%New()
    Set task.%Actions = "Approve,Reject"
    Set task.%Subject = "Shutter " _ case.CaseId _ ": approve plan v" _ plan.Version _ " (" _ plan.Disposition _ ")"
    Do ..Wards(case, .prior, .target)
    Set snapshot = case.CurrentSnapshot
    Set message = case.Headline
    Set message = message _ lf _ "Exact action: one update of Encounter " _ binding.EncounterId _ ", location " _ prior _ " to " _ target _ ", sent with If-Match on the version read at " _ $SELECT($ISOBJECT(snapshot): snapshot.TakenAt, 1: "") _ " (ETag " _ binding.ExpectedEtag _ "). This server software refused a changed version when it was measured."
    Set message = message _ lf _ "Plan digest: " _ plan.Digest _ lf _ "Snapshot digest: " _ $SELECT($ISOBJECT(snapshot): snapshot.Digest, 1: "")
    Set message = message _ lf _ "No dry run exists for this receiver."
    Set message = message _ lf _ "After this update, do not resend the original HL7 message from the engine."
    Set message = message _ lf _ "To approve from the Workflow inbox, paste the plan digest above into the PlanDigest field: an approval with no digest, or another one, binds nothing and blocks the case."
    // What the approver should look at first (Shutter.Util.FurtherMessages): the plan's lines for this patient.
    Try {
        Set lines = ##class(Shutter.Util.FurtherMessages).PlanLines(case, $SELECT($ISOBJECT(snapshot): snapshot.SummaryObject(), 1: ""))
        Set li = lines.%GetIterator()
        While li.%GetNext(, .line) { Set message = message _ lf _ line }
    } Catch ex {
        Set message = message _ lf _ $CLASSMETHOD(workflow, "NotRead", case, "further messages for this patient", ex)
    }
    Try {
        Set unproved = ##class(Shutter.Operation.Origin).Problem(case)
        If unproved '= "" Set message = message _ lf _ "Source not verified: " _ unproved _ "."
    } Catch ex {
        Set message = message _ lf _ $CLASSMETHOD(workflow, "NotRead", case, "whether this case's source is proved", ex)
    }
    If waitSeconds > 0 Set message = message _ lf _ "Unanswered after " _ $CLASSMETHOD(workflow, "WaitWords", waitSeconds) _ ", the task is cancelled and the case escalates to a person."
    Set task.%Message = message
    Set task.%Priority = 2
    Set task.%FormFields = "PlanDigest,Comment"
    Quit task
}

/// The approver's answer. As the workflow's own (a rejection, an answer with no digest or another one), with no
/// rehearsal to bind, no expected version, the FHIR gate's policy version and no precedent; an approval is tied to the
/// sealed binding, and the read before the write is asked for.
ClassMethod OnApproval(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, result As EnsLib.Workflow.TaskResponse) As %Status
{
    Set policy = ##class(Shutter.FHIR.Profile).#POLICYVERSION
    Set plan = ##class(Shutter.Store.Plan).%OpenId(p.PlanId)
    If '$ISOBJECT(plan) Quit $$$ERROR($$$GeneralError, "The approval answered for plan " _ p.PlanId _ ", which is not there")
    Set action = $ZCONVERT(result.%Action, "L")
    Set user = result.%UserName
    Set comment = result.%FormValues.GetAt("Comment")
    Set digest = result.%FormValues.GetAt("PlanDigest")
    Set taskId = result.%Id()
    If action '= "approve" {
        Set sc = ##class(Shutter.Store.Approval).Create(case, plan, case.CurrentSnapshot, policy, "", "", user, "rejected", comment, taskId, p.ApprovalValidSeconds, .a)
        Quit:$$$ISERR(sc) sc
        Set case.Headline = "Rejected by " _ user _ ": " _ case.Headline
        Quit case.Transition("blocked", "Rejected by " _ user _ $SELECT(comment '= "": ": " _ comment, 1: ""), user, "approval:" _ a.%Id())
    }
    If digest = "" {
        Quit case.Transition("blocked", "The approval carried no plan digest, so it binds nothing; nothing was dispatched", user)
    }
    If digest '= plan.Digest {
        Quit case.Transition("blocked", "The approval named another plan digest (" _ $EXTRACT(digest, 1, 19) _ "); nothing was dispatched", user)
    }
    Set sc = ##class(Shutter.Store.Approval).Create(case, plan, case.CurrentSnapshot, policy, "", "", user, "approved", comment, taskId, p.ApprovalValidSeconds, .a)
    Quit:$$$ISERR(sc) sc
    Set p.ApprovalId = a.%Id()
    Set case.CurrentApproval = a
    Set sc = case.Transition("approved", "Approved by " _ user _ " for plan digest " _ $EXTRACT(plan.Digest, 1, 19) _ $SELECT(comment '= "": ": " _ comment, 1: ""), user, "approval:" _ a.%Id())
    Quit:$$$ISERR(sc) sc
    Set binding = ..Binding(p)
    Set sc = $SELECT($ISOBJECT(binding): binding.Bind(a.%Id()), 1: $$$ERROR($$$GeneralError, "the plan has no sealed binding"))
    If $$$ISERR(sc) {
        Quit ..Stop(p, case, "blocked", "Blocked: the update could not be sealed for approval", "The update could not be sealed for approval: " _ ..Plain($SYSTEM.Status.GetErrorText(sc)) _ " (FHIR_NO_BINDING)", "approval:" _ a.%Id(), "the approval could not be tied to the sealed update")
    }
    // The retries of the read before the write start afresh.
    Set p.Refreshes = 0
    Quit ..SendPreflight(p, case)
}

/// The plan's binding: the one the workflow names, or the plan's own.
ClassMethod Binding(p As Shutter.Process.CaseWorkflow) As Shutter.Store.FHIRBinding
{
    Set binding = $SELECT(p.FHIRBindingId = "": "", 1: ##class(Shutter.Store.FHIRBinding).%OpenId(p.FHIRBindingId))
    If '$ISOBJECT(binding) Set binding = ##class(Shutter.Store.FHIRBinding).ForPlan(p.PlanId)
    If $ISOBJECT(binding) && (binding.PlanId '= p.PlanId) Set binding = ""
    Quit binding
}

// ---- the read before the write, and the gate at the dispatch ----

/// Asks FHIR Receiver for the read just before the write: the Encounter, its Patient and every bound Location.
ClassMethod SendPreflight(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case) As %Status
{
    Set binding = ..Binding(p)
    If '$ISOBJECT(binding) {
        Quit ..Stop(p, case, "blocked", "Blocked: the update could not be sealed for approval", "The update could not be sealed for approval: the plan's sealed update is not there (FHIR_NO_BINDING)", "", "the sealed update is missing")
    }
    Set patient = ##class(Shutter.Util.Json).Parse(binding.PatientJSON, .psc), bound = ##class(Shutter.Util.Json).Parse(binding.LocationsJSON, .lsc)
    Set refs = []
    If $ISOBJECT(bound) {
        Set iter = bound.%GetIterator()
        While iter.%GetNext(.i, .l) { Do refs.%Push(##class(Shutter.Util.Json).Str(l, "reference")) }
    }
    Set read = ##class(Shutter.Msg.FHIRRead).%New()
    Set read.CaseId = case.CaseId, read.Purpose = "dispatch", read.EncounterId = binding.EncounterId
    Set read.PatientRef = ##class(Shutter.Util.Json).Str(patient, "reference"), read.LocationRefsJSON = refs.%ToJSON()
    Quit p.FHIRSend(..#READER, read, "fhir:preflight")
}

/// The read just before the write. One that failed is asked again with a growing wait, then the case blocks and the
/// approval is void; one that was made goes to the gate at the dispatch.
ClassMethod OnPreflight(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, result As Shutter.Msg.FHIRReadResult) As %Status
{
    Set why = ""
    If '$ISOBJECT(result) {
        Set why = "no answer"
    } ElseIf result.Error '= "" {
        Set why = result.Error
    } Else {
        Set parts = ##class(Shutter.Util.Json).Parse(result.PartsJSON, .psc)
        Set encounter = $SELECT($ISOBJECT(parts): parts.%Get("encounter"), 1: "")
        If '$ISOBJECT(encounter) || (+##class(Shutter.Util.Json).Str(encounter, "http_status") = 0) Set why = "the Encounter could not be read" _ $SELECT($ISOBJECT(encounter) && (##class(Shutter.Util.Json).Str(encounter, "error") '= ""): " (" _ ##class(Shutter.Util.Json).Str(encounter, "error") _ ")", 1: "")
    }
    If why '= "" {
        If p.Refreshes < p.MaxRefreshes {
            Set p.Refreshes = p.Refreshes + 1
            Set wait = 10 * (2 ** (p.Refreshes - 1))
            Do case.Note("note", "The read before the write failed (" _ $EXTRACT(why, 1, 400) _ "); reading again in " _ wait _ " s (" _ p.Refreshes _ " of " _ p.MaxRefreshes _ ")", "system")
            Quit ..Alarm(p, wait, "fhir:preflight:retry")
        }
        Quit ..Stop(p, case, "blocked", "Blocked at dispatch: the receiver could not be read", "The receiver could not be read just before the write, in " _ (p.MaxRefreshes + 1) _ " tries. The approval is void and nothing was sent (FHIR_RECEIVER_UNREADABLE)", "", "the receiver could not be read before the write")
    }
    // The gate reads this result by its id.
    If result.%Id() = "" {
        Set sc = result.%Save()
        Quit:$$$ISERR(sc) sc
    }
    Do case.Note("note", "The read before the write was made (Encounter HTTP " _ ##class(Shutter.Util.Json).Str(encounter, "http_status") _ "); the FHIR gate decides on it", "system")
    Quit ..SendGate(p, case, "dispatch", result.%Id())
}

/// The answer of the FHIR gate at the dispatch. A pass sends the one update; an unknown a fresh read can answer
/// reads again; anything else blocks the case and voids the approval.
ClassMethod OnGateDispatch(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, result As Shutter.Msg.GateResult) As %Status
{
    If '$ISOBJECT(result) Quit ..ItemFailed(p, case, "the FHIR gate gave no answer")
    If (result.Error '= "") && (result.DecisionId = "") Quit ..ItemFailed(p, case, result.Error)
    If result.Outcome '= "pass" {
        If ..OnlyRefreshable(result) && (p.Refreshes < p.MaxRefreshes) {
            Set p.Refreshes = p.Refreshes + 1
            Set wait = 10 * (2 ** (p.Refreshes - 1))
            Do case.Note("note", "The FHIR gate could not decide at the dispatch (" _ result.Summary _ "); reading the receiver again in " _ wait _ " s (" _ p.Refreshes _ " of " _ p.MaxRefreshes _ ")", "gate", "gate:" _ result.DecisionId)
            Quit ..Alarm(p, wait, "fhir:preflight:retry")
        }
        Do ..Revoke(p, "the FHIR gate did not pass the plan at dispatch")
        Set case.Headline = "Blocked at dispatch: " _ result.Summary
        Quit case.Transition("blocked", "The FHIR gate did not pass the plan at dispatch. The approval is void; a reinvestigation reads fresh evidence and asks again", "gate", "gate:" _ result.DecisionId)
    }
    Set binding = ..Binding(p)
    If '$ISOBJECT(binding) {
        Quit ..Stop(p, case, "blocked", "Blocked: the update could not be sealed for approval", "The update could not be sealed for approval: the plan's sealed update is not there (FHIR_NO_BINDING)", "gate:" _ result.DecisionId, "the sealed update is missing")
    }
    // The dispatch is cleared: the retry budget starts afresh for the verification.
    Set p.Refreshes = 0
    Set sc = case.Transition("executing", "Sending one update with If-Match " _ binding.ExpectedEtag, "system", "gate:" _ result.DecisionId)
    Quit:$$$ISERR(sc) sc
    Set write = ##class(Shutter.Msg.FHIRWrite).%New()
    Set write.CaseId = case.CaseId, write.PlanId = p.PlanId, write.ApprovalId = p.ApprovalId, write.BindingId = binding.%Id(), write.DecisionId = result.DecisionId
    Quit p.FHIRSend(..#OUT, write, "fhir:execute")
}

// ---- the write ----

/// What became of the update. Its attempt row is written once per fence row; applied or uncertain is verified, a
/// version conflict or a refusal blocks the case and voids the approval.
ClassMethod OnExecute(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, result As Shutter.Msg.FHIRWriteResult) As %Status
{
    If '$ISOBJECT(result) Quit ..OnExecuteError(p, case, "FHIR Out gave no answer")
    Set sent = ..Sent(p)
    // A word FHIR Out does not have decides nothing by itself: the fence row does.
    Set outcome = $SELECT($LISTFIND($LISTBUILD("applied", "version_conflict", "refused", "uncertain", "error"), result.Outcome): result.Outcome, sent: "uncertain", 1: "error")
    Set status = +result.HttpStatus
    Set sc = ..Attempt(p, case, outcome, status, ''result.Sent, result.ReasonCode, result.Diagnostics, result.ResponseEtag, result.ResponseLocation, result.Error, .attempt)
    Quit:$$$ISERR(sc) sc
    Set ref = "attempt:" _ attempt.%Id()
    Do case.Note("execution", "FHIR update: " _ outcome _ ", " _ ..HttpWords(status) _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: ""), "system", ref)
    If (outcome = "applied") || (outcome = "uncertain") {
        Set sc = case.Transition("verifying", $SELECT(outcome = "applied": "The receiver answered the update; verifying it in the Encounter's history", 1: "Whether the receiver applied the update is not known; reading the Encounter and its history until that settles"), "system", ref)
        Quit:$$$ISERR(sc) sc
        Quit ..SendVerify(p, case)
    }
    If outcome = "version_conflict" {
        Quit ..Stop(p, case, "blocked", "Blocked: the Encounter changed before the update", "The receiver refused the update: the Encounter changed after it was read (" _ ..HttpWords(status) _ "). The approval is void and nothing is sent again without fresh evidence and a new approval (FHIR_WRITE_CONFLICT)", ref, "the Encounter changed before the update")
    }
    Set reason = $SELECT(result.ReasonCode '= "": result.ReasonCode, 1: outcome)
    Quit ..Stop(p, case, "blocked", "Blocked: the update was not applied", "The update was not applied: " _ ..Plain(reason) _ ", " _ ..HttpWords(status) _ " (FHIR_WRITE_REFUSED)", ref, "the update was not applied")
}

/// The call to FHIR Out failed. With the fence row sent the update may have landed: an uncertain attempt, and the
/// verifier reads what the receiver holds. Otherwise nothing left: an error attempt, and the case blocks.
ClassMethod OnExecuteError(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, text As %String) As %Status
{
    If ..Sent(p) {
        Set sc = ..Attempt(p, case, "uncertain", 0, 1, "fhir_item_error", "", "", "", text, .attempt)
        Quit:$$$ISERR(sc) sc
        Set ref = "attempt:" _ attempt.%Id()
        Do case.Note("execution", "FHIR update: uncertain, " _ ..HttpWords(0) _ ". The call to FHIR Out failed after the update was sent: " _ $EXTRACT(text, 1, 400), "system", ref)
        Set sc = case.Transition("verifying", "The call to FHIR Out failed after the update was sent. Whether the receiver applied it is not known; reading the Encounter and its history until that settles", "system", ref)
        Quit:$$$ISERR(sc) sc
        Quit ..SendVerify(p, case)
    }
    Set sc = ..Attempt(p, case, "error", 0, 0, "fhir_item_error", "", "", "", text, .attempt)
    Quit:$$$ISERR(sc) sc
    Set ref = "attempt:" _ attempt.%Id()
    Do case.Note("execution", "FHIR update: error, " _ ..HttpWords(0) _ ". The call to FHIR Out failed before anything was sent: " _ $EXTRACT(text, 1, 400), "system", ref)
    Quit ..Stop(p, case, "blocked", "Blocked: the update was not applied", "The update was not applied: fhir_item_error, " _ ..HttpWords(0) _ " (FHIR_WRITE_REFUSED)", ref, "the update was not applied")
}

/// The attempt row of the update, once per fence row: a fence row that names an attempt already has it, and that row
/// is the attempt. Sets the workflow's AttemptId, and the fence row's when there is one.
ClassMethod Attempt(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, outcome As %String, status As %Integer, sent As %Boolean, reasonCode As %String, diagnostics As %String, etag As %String, location As %String, error As %String, Output attempt As Shutter.Store.ExecutionAttempt) As %Status
{
    Set attempt = ""
    Set fence = ..Fence(p)
    If $ISOBJECT(fence) && (fence.ExecutionAttemptId '= "") {
        Set attempt = ##class(Shutter.Store.ExecutionAttempt).%OpenId(fence.ExecutionAttemptId)
        If $ISOBJECT(attempt) Set p.AttemptId = attempt.%Id() Quit $$$OK
    }
    Set plan = $SELECT(p.PlanId = "": "", 1: ##class(Shutter.Store.Plan).%OpenId(p.PlanId))
    Set approval = $SELECT(p.ApprovalId = "": "", 1: ##class(Shutter.Store.Approval).%OpenId(p.ApprovalId))
    Set response = ..AttemptResponse(..Binding(p), fence, sent, reasonCode, diagnostics, etag, location)
    Set sc = ##class(Shutter.Store.ExecutionAttempt).Create(case, plan, approval, "", status, outcome, response, error, .attempt)
    Quit:$$$ISERR(sc) sc
    Set p.AttemptId = attempt.%Id()
    If $ISOBJECT(fence) Set sc = fence.SetExecutionAttempt(attempt.%Id())
    Quit sc
}

/// The response an attempt row of a FHIR case keeps, with its receipt. The answer's ETag and Location are the
/// arguments', or the fence row's when none is given.
ClassMethod AttemptResponse(binding As Shutter.Store.FHIRBinding, fence As Shutter.Store.FHIRAttempt, sent As %Boolean, reasonCode As %String = "", diagnostics As %String = "", etag As %String = "", location As %String = "") As %DynamicObject
{
    If $ISOBJECT(fence) {
        If etag = "" Set etag = fence.ResponseEtag
        If location = "" Set location = fence.ResponseLocation
    }
    Set receipt = {"kind": "fhir"}
    Do receipt.%Set("encounter", $SELECT($ISOBJECT(binding): "Encounter/" _ binding.EncounterId, 1: ""), "string")
    Do receipt.%Set("expected_etag", $SELECT($ISOBJECT(binding): binding.ExpectedEtag, $ISOBJECT(fence): fence.ExpectedEtag, 1: ""), "string")
    Do receipt.%Set("response_etag", etag, "string")
    Do receipt.%Set("response_location", location, "string")
    Do receipt.%Set("body_digest", $SELECT($ISOBJECT(binding): binding.ApprovedBodyDigest, $ISOBJECT(fence): fence.BodyDigest, 1: ""), "string")
    Do receipt.%Set("operation_id", $SELECT($ISOBJECT(binding): binding.OperationId, $ISOBJECT(fence): fence.OperationId, 1: ""), "string")
    Do receipt.%Set("marker_system", $SELECT($ISOBJECT(binding): binding.MarkerSystem, 1: ""), "string")
    Set response = {"kind": "fhir"}
    Do response.%Set("sent", ''sent, "boolean")
    Do response.%Set("reason_code", reasonCode, "string")
    Do response.%Set("diagnostics", diagnostics, "string")
    Set response.receipt = receipt
    Quit response
}

// ---- the verification ----

/// Asks FHIR Verifier for the walk.
ClassMethod SendVerify(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case) As %Status
{
    Set req = ##class(Shutter.Msg.VerifyRequest).%New()
    Set req.CaseId = case.CaseId, req.PlanId = p.PlanId, req.AttemptId = p.AttemptId
    Quit p.FHIRSend(..#VERIFIER, req, "fhir:verify")
}

/// What the walk established. Verified resolves the case with the verifier's sentence as it is. A walk that asks for
/// another read is made again after 10, 20 and 40 seconds; then, and for every other outcome, the case goes to a
/// person with the verifier's sentence and the outcome's reason code.
ClassMethod OnVerify(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, result As Shutter.Msg.VerifyResult) As %Status
{
    If '$ISOBJECT(result) Quit ..ItemFailed(p, case, "the verifier gave no answer")
    Set json = "Shutter.Util.Json"
    Set detail = $CLASSMETHOD(json, "Parse", result.DetailJSON, .dsc)
    Set judged = $SELECT($ISOBJECT(detail): $CLASSMETHOD(json, "Str", detail, "judge_outcome"), 1: "")
    Set retry = $ISOBJECT(detail) && (detail.%GetTypeOf("retry") = "boolean") && detail.retry
    Set ref = "verification:" _ result.VerificationId
    If (result.Outcome = "verified") && ((judged = "verified") || (judged = "verified_continued")) {
        Set case.Outcome = result.Summary
        Quit case.Transition("resolved", result.Summary, "system", ref)
    }
    If retry && (p.Refreshes < p.MaxRefreshes) {
        Set p.Refreshes = p.Refreshes + 1
        Set wait = 10 * (2 ** (p.Refreshes - 1))
        Do case.Note("note", "The verification established nothing yet (" _ result.Summary _ "); verifying again in " _ wait _ " s (" _ p.Refreshes _ " of " _ p.MaxRefreshes _ ")", "system", ref)
        Quit ..Alarm(p, wait, "fhir:verify:retry")
    }
    Set case.Outcome = result.Summary
    Set text = ..Plain(result.Summary)
    If (result.Outcome = "unresolved") && (judged = "committed_review") {
        // The update is in the history; what the record shows now needs a person. Nothing is revoked or resent.
        Quit ..Stop(p, case, "escalated", "Escalated: the update is present, the current record needs review", text _ " (FHIR_COMMITTED_NEEDS_REVIEW)", ref)
    }
    If (result.Outcome = "not_committed") && (judged = "not_found") {
        Quit ..Stop(p, case, "escalated", "Escalated: the update is not in the history read", text _ " (FHIR_WRITE_NOT_FOUND)", ref, "the update is not in the history read, and its one write is spent")
    }
    If (result.Outcome = "failed") && (judged = "failed") {
        Quit ..Stop(p, case, "escalated", "Escalated: the receiver's record contradicts the update", text _ " (FHIR_WRITE_CONTRADICTED)", ref, "the receiver's record contradicts the update")
    }
    // Unknown after the last read, and any answer that is none of the verifier's: nobody knows what became of the update.
    Quit ..Stop(p, case, "escalated", "Escalated: the update's outcome is unknown", text _ " (FHIR_WRITE_OUTCOME_UNKNOWN)", ref, "the update's outcome is unknown, and its one write is spent")
}

// ---- stops, the fence, and small things ----

/// An error from a FHIR item, or inside the flow. The fence row decides what it means: with the update sent nobody
/// knows its outcome and a person checks at the receiver; before that nothing was sent. Either way the approval is void.
ClassMethod ItemFailed(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, text As %String) As %Status
{
    Set text = ..Plain($EXTRACT(text, 1, 400))
    If ..Sent(p) {
        // The sent update has its attempt row, whatever stopped the case before it was written.
        Do ..Backfill(case)
        Set fence = ..Fence(p)
        If $ISOBJECT(fence) && (fence.ExecutionAttemptId '= "") Set p.AttemptId = fence.ExecutionAttemptId
        Quit ..Stop(p, case, "escalated", "Escalated: the update's outcome is unknown", "A FHIR item failed after the update was sent: " _ text _ ". Whether the receiver applied it is unknown; a person checks at the receiver (FHIR_WRITE_OUTCOME_UNKNOWN)", $SELECT(p.AttemptId '= "": "attempt:" _ p.AttemptId, 1: ""), "a FHIR item failed after the update was sent, and its one write is spent")
    }
    Quit ..Stop(p, case, "blocked", "Blocked: a FHIR item failed", "A FHIR item answered with an error before anything was sent: " _ text _ " (FHIR_ITEM_ERROR)", "", "a FHIR item failed before anything was sent")
}

/// One stop of the flow: the approval revoked when <var>revoke</var> says why, the headline, and the closing event.
ClassMethod Stop(p As Shutter.Process.CaseWorkflow, case As Shutter.Store.Case, state As %String, headline As %String, text As %String, ref As %String = "", revoke As %String = "") As %Status
{
    If revoke '= "" Do ..Revoke(p, revoke)
    Set case.Headline = headline
    Quit case.Transition(state, text, "system", ref)
}

/// Revokes the approval the workflow holds, when there is one that still stands.
ClassMethod Revoke(p As Shutter.Process.CaseWorkflow, why As %String)
{
    Quit:p.ApprovalId=""
    Set approval = ##class(Shutter.Store.Approval).%OpenId(p.ApprovalId)
    If $ISOBJECT(approval) && 'approval.Revoked Do approval.Revoke("system: " _ why)
}

/// The fence row of the workflow's approval, read from the store (it is written by SQL), or "".
ClassMethod Fence(p As Shutter.Process.CaseWorkflow) As Shutter.Store.FHIRAttempt
{
    If p.ApprovalId = "" Quit ""
    Set fence = ##class(Shutter.Store.FHIRAttempt).ForApproval(p.ApprovalId)
    If $ISOBJECT(fence) Do fence.%Reload()
    Quit fence
}

/// Whether the update of the workflow's approval has left: its fence row says sent.
ClassMethod Sent(p As Shutter.Process.CaseWorkflow) As %Boolean
{
    Set fence = ..Fence(p)
    Quit $ISOBJECT(fence) && (fence.State = "sent")
}

/// An alarm back to the workflow after that many seconds, under that key.
ClassMethod Alarm(p As Shutter.Process.CaseWorkflow, seconds As %Integer, key As %String, description As %String = "") As %Status
{
    Set alarm = ##class(Ens.AlarmRequest).%New()
    Set alarm.Timeout = seconds
    Quit p.FHIRSend("Ens.Alarm", alarm, key, description)
}

/// An HTTP status in words: no answer is said, never written as a status of 0.
ClassMethod HttpWords(status As %Integer) As %String
{
    Quit $SELECT(+status > 0: "HTTP " _ +status, 1: "no HTTP answer")
}

/// Words taken into an event's text from somewhere else (an error, a diagnostic): they never carry what reads as a
/// reason code of the flow's own, since the case's reason is read from the code the text closes with.
ClassMethod Plain(text As %String) As %String
{
    Quit $REPLACE(text, "(FHIR_", "(fhir_")
}

}
