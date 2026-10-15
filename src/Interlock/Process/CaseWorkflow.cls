/// The case workflow: opens a case from an intake and takes it through evidence, the board, the
/// coordinator, the gate, rehearsal, approval, execution and verification. One instance per case;
/// every step is a message to another production item, so the Visual Trace of a case is its
/// audit trail. The instance keeps only identifiers between steps; the store holds the record.
Class Interlock.Process.CaseWorkflow Extends Ens.BusinessProcess
{

Property CaseId As %String(MAXLEN = 32);

Property Mode As %String(MAXLEN = 16);

/// The board members still to answer, as a JSON array of codes.
Property PendingJSON As %String(MAXLEN = 4000) [ InitialExpression = "[]" ];

/// Member codes that answered without usable findings.
Property FailedJSON As %String(MAXLEN = 4000) [ InitialExpression = "[]" ];

Property PlanId As %String(MAXLEN = 20);

Property ApprovalId As %String(MAXLEN = 20);

Property AttemptId As %String(MAXLEN = 20);

/// The receiver version the rehearsal saw, carried to the dispatch gate.
Property ReceiverVersion As %Integer;

/// The receiver's epoch as last observed.
Property ReceiverEpoch As %Integer;

/// How many times the case was re-planned after the receiver changed under an approval.
Property Replans As %Integer [ InitialExpression = 0 ];

Property EvidenceTarget As %String(MAXLEN = 128) [ InitialExpression = "Evidence Collector" ];

Property GateTarget As %String(MAXLEN = 128) [ InitialExpression = "Gate" ];

Property WardTarget As %String(MAXLEN = 128) [ InitialExpression = "Ward Out" ];

Property ApprovalTarget As %String(MAXLEN = 128) [ InitialExpression = "Interlock Approvers" ];

Property VerifyTarget As %String(MAXLEN = 128) [ InitialExpression = "Verifier" ];

/// Seconds an approval stays valid.
Property ApprovalValidSeconds As %Integer [ InitialExpression = 3600 ];

Parameter SETTINGS = "EvidenceTarget:Targets,GateTarget:Targets,WardTarget:Targets,ApprovalTarget:Targets,VerifyTarget:Targets,ApprovalValidSeconds:Approval";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    If 'request.%IsA("Interlock.Msg.CaseIntake") Quit $$$ERROR($$$GeneralError, "Case Workflow expects a case intake, got " _ $CLASSNAME(request))
    Set op = ##class(Interlock.Util.Json).Parse(request.OperationJSON, .sc)
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(Interlock.Store.Case).Open(op, request.FailureKind, request.FailureText, request.EnsSessionId, request.SourceHeaderId, request.Mode, .case, .opened)
    If $$$ISERR(sc) Quit sc
    Set started = ##class(Interlock.Msg.CaseStarted).%New()
    Set started.CaseId = case.CaseId, started.Opened = opened, started.State = case.State
    Set response = started
    If 'opened {
        $$$TRACE("Case " _ case.CaseId _ " already open; the new failure was noted")
        Quit $$$OK
    }
    Set ..CaseId = case.CaseId, ..Mode = case.Mode
    Set case.WorkflowSessionId = ..%SessionId
    Do case.%Save()
    $$$TRACE("Case " _ case.CaseId _ " opened (" _ case.Mode _ "): " _ case.Headline)
    Quit ..StartEvidence(case)
}

Method StartEvidence(case As Interlock.Store.Case) As %Status
{
    Set sc = case.Transition("collecting", "Collecting evidence", "system")
    Quit:$$$ISERR(sc) sc
    Set req = ##class(Interlock.Msg.EvidenceRequest).%New()
    Set req.CaseId = case.CaseId
    Quit ..SendRequestAsync(..EvidenceTarget, req, 1, "evidence")
}

/// The request body of the call being answered, for header lookups.
Property %LastCallRequest As %Library.Persistent [ Transient ];

/// The Ens.MessageHeader id of a message body, or "".
Method HeaderIdOf(body As %Library.Persistent) As %String
{
    If '$ISOBJECT(body) Quit ""
    Set cls = $CLASSNAME(body), bodyId = body.%Id(), id = ""
    &sql(SELECT TOP 1 ID INTO :id FROM Ens.MessageHeader WHERE MessageBodyClassName = :cls AND MessageBodyId = :bodyId ORDER BY ID DESC)
    If SQLCODE '= 0 Quit ""
    Quit id
}

Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, completionkey As %String) As %Status
{
    Set sc = $$$OK
    Set ..%LastCallRequest = callrequest
    Try {
        Set case = ##class(Interlock.Store.Case).ByCaseId(..CaseId)
        If '$ISOBJECT(case) Quit
        If case.IsClosed() { $$$TRACE("Case " _ ..CaseId _ " is closed; ignoring " _ completionkey) Quit }
        If completionkey = "evidence" { Set sc = ..OnEvidence(case, callresponse) Quit }
        If $EXTRACT(completionkey, 1, 7) = "member:" { Set sc = ..OnMember(case, $EXTRACT(completionkey, 8, *), callresponse) Quit }
        If completionkey = "coordinator" { Set sc = ..OnCoordinator(case, callresponse) Quit }
        If completionkey = "gate:proposal" { Set sc = ..OnGateProposal(case, callresponse) Quit }
        If completionkey = "rehearsal" { Set sc = ..OnRehearsal(case, callresponse) Quit }
        If completionkey = "approval" { Set sc = ..OnApproval(case, callresponse) Quit }
        If completionkey = "preflight" { Set sc = ..OnPreflight(case, callresponse) Quit }
        If completionkey = "gate:dispatch" { Set sc = ..OnGateDispatch(case, callresponse) Quit }
        If completionkey = "execute" { Set sc = ..OnExecute(case, callresponse) Quit }
        If completionkey = "verify" { Set sc = ..OnVerify(case, callresponse) Quit }
        $$$LOGWARNING("Unexpected completion key " _ completionkey)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) {
        Set case = ##class(Interlock.Store.Case).ByCaseId(..CaseId)
        If $ISOBJECT(case) && 'case.IsClosed() Do case.Transition("failed", "Workflow error at " _ completionkey _ ": " _ $SYSTEM.Status.GetErrorText(sc), "system")
    }
    Quit sc
}

// ---- evidence and the board ----

Method OnEvidence(case As Interlock.Store.Case, result As Interlock.Msg.EvidenceResult) As %Status
{
    If '$ISOBJECT(result) || (result.Error '= "") Quit $$$ERROR($$$GeneralError, "Evidence failed: " _ $SELECT($ISOBJECT(result): result.Error, 1: "no result"))
    Set sc = case.Transition("investigating", "Evidence collected: snapshot " _ result.SnapshotId _ ", digest " _ $EXTRACT(result.Digest, 1, 19), "system", "snapshot:" _ result.SnapshotId)
    Quit:$$$ISERR(sc) sc
    Set members = ##class(Interlock.Store.BoardMember).MembersForMode(..Mode)
    If members.%Size() = 0 Quit ..RulesOnly(case)
    Set pending = []
    Set iter = members.%GetIterator()
    While iter.%GetNext(.i, .code) {
        Set m = ##class(Interlock.Store.BoardMember).ByCode(code)
        Continue:'$ISOBJECT(m)
        Set sc = ..SendRequestAsync(m.ConfigItem, ..AgentRequestFor(case, m, result.SummaryJSON, ""), 1, "member:" _ code)
        Quit:$$$ISERR(sc)
        Do pending.%Push(code)
    }
    Quit:$$$ISERR(sc) sc
    Set ..PendingJSON = pending.%ToJSON()
    Do case.Note("note", "Board convened: " _ $REPLACE($REPLACE(pending.%ToJSON(), "[", ""), "]", ""), "system")
    Quit $$$OK
}

Method AgentRequestFor(case As Interlock.Store.Case, m As Interlock.Store.BoardMember, summaryJSON As %String, findingsJSON As %String) As Interlock.Bridge.Msg.AgentRequest
{
    Set req = ##class(Interlock.Bridge.Msg.AgentRequest).%New()
    Set req.Role = m.Role, req.MemberCode = m.Code, req.AgentClass = m.AgentClass
    Set req.CorrelationKey = case.CaseId
    Set snap = case.CurrentSnapshot
    If $ISOBJECT(snap) Set req.SnapshotDigest = snap.Digest
    Set req.TerminalTool = m.TerminalTool
    Set req.ResultClass = $SELECT(m.TerminalTool = "submit_plan": "Interlock.Schema.Plan", 1: "Interlock.Schema.Findings")
    Set req.ConfigVersion = m.ConfigVersion
    If case.Scenario '= "" Set req.RecordKey = "scenario:" _ case.Scenario _ "|" _ m.Code _ "|" _ m.ConfigVersion _ $SELECT(..Replans > 0: "|round" _ (..Replans + 1), 1: "")
    Set context = {}
    Set context."case_id" = case.CaseId
    Set context.evidence = ##class(%DynamicObject).%FromJSON(summaryJSON)
    If findingsJSON '= "" Set context.findings = ##class(%DynamicArray).%FromJSON(findingsJSON)
    Set req.Context = context.%ToJSON()
    If m.Role = "coordinator" {
        Set req.Goal = "Read the specialists' findings and the evidence for case " _ case.CaseId _ ". Keep every disagreement. Propose exactly one plan with the recovery playbooks, and submit it with submit_plan."
    } ElseIf m.Role = "generalist" {
        Set req.Goal = "Investigate case " _ case.CaseId _ " from every angle: conformance, the encounter's integrity, downstream impact. Propose exactly one plan and submit it with submit_plan."
    } Else {
        Set req.Goal = "Review case " _ case.CaseId _ " as the " _ m.Name _ " specialist: " _ m.Perspective _ " Cite the evidence you used by its identifiers, say what is unknown, and submit your findings with submit_findings."
    }
    Quit req
}

Method OnMember(case As Interlock.Store.Case, code As %String, result As Interlock.Bridge.Msg.AgentResponse) As %Status
{
    Set m = ##class(Interlock.Store.BoardMember).ByCode(code)
    Set sc = ##class(Interlock.Store.AgentRun).FromResponse(case, case.CurrentSnapshot, $SELECT($ISOBJECT(m): m.Role, 1: ""), code, result, ..HeaderIdOf(..%LastCallRequest), .run)
    Quit:$$$ISERR(sc) sc
    Set usable = (result.Status = "ok") && (result.ResultJSON '= "")
    Set findings = ""
    If usable {
        Set findings = ##class(Interlock.Util.Json).Parse(result.ResultJSON, .psc)
        If '$ISOBJECT(findings) || $$$ISERR(psc) Set usable = 0
    }
    If usable {
        If $ISOBJECT(m) && (m.Role = "generalist") {
            // The single investigator proposes the plan itself.
            Set ..PendingJSON = "[]"
            Quit ..AdoptPlan(case, findings, "run:" _ run.%Id())
        }
        Set sc = ##class(Interlock.Store.Finding).Create(run, findings, .finding)
        Quit:$$$ISERR(sc) sc
        Do case.Note("artifact", $SELECT($ISOBJECT(m): m.Name, 1: code) _ ": " _ ##class(Interlock.Util.Json).Str(findings, "disposition") _ " (" _ $EXTRACT(##class(Interlock.Util.Json).Str(findings, "summary"), 1, 300) _ ")", "agent:" _ code, "finding:" _ finding.%Id())
    } Else {
        Set failed = ##class(%DynamicArray).%FromJSON(..FailedJSON)
        Do failed.%Push(code)
        Set ..FailedJSON = failed.%ToJSON()
        Do case.Note("error", $SELECT($ISOBJECT(m): m.Name, 1: code) _ " gave no usable findings: " _ result.Status _ $SELECT(result.Error '= "": ", " _ result.Error, 1: ""), "agent:" _ code, "run:" _ run.%Id())
    }
    // Remove from the pending list.
    Set pending = ##class(%DynamicArray).%FromJSON(..PendingJSON)
    Set rest = []
    Set iter = pending.%GetIterator()
    While iter.%GetNext(.i, .c) { If c '= code Do rest.%Push(c) }
    Set ..PendingJSON = rest.%ToJSON()
    If rest.%Size() > 0 Quit $$$OK
    // Everyone answered: the coordinator, or an escalation when no findings are usable.
    Set all = ##class(Interlock.Store.Finding).ForSnapshot(case.CurrentSnapshot)
    If all.%Size() = 0 Quit case.Transition("escalated", "No board member produced usable findings; a person must look", "system")
    Set coordinator = ##class(Interlock.Store.BoardMember).Coordinator()
    If '$ISOBJECT(coordinator) Quit case.Transition("escalated", "No coordinator is enabled; the findings are on the case for a person", "system")
    Set snap = case.CurrentSnapshot
    Set req = ..AgentRequestFor(case, coordinator, snap.Summary, all.%ToJSON())
    Quit ..SendRequestAsync(coordinator.ConfigItem, req, 1, "coordinator")
}

Method OnCoordinator(case As Interlock.Store.Case, result As Interlock.Bridge.Msg.AgentResponse) As %Status
{
    Set sc = ##class(Interlock.Store.AgentRun).FromResponse(case, case.CurrentSnapshot, "coordinator", "coordinator", result, ..HeaderIdOf(..%LastCallRequest), .run)
    Quit:$$$ISERR(sc) sc
    If (result.Status '= "ok") || (result.ResultJSON = "") {
        Quit case.Transition("escalated", "The coordinator produced no plan: " _ result.Status _ $SELECT(result.Error '= "": ", " _ result.Error, 1: ""), "system", "run:" _ run.%Id())
    }
    Set plan = ##class(Interlock.Util.Json).Parse(result.ResultJSON, .psc)
    If '$ISOBJECT(plan) || $$$ISERR(psc) Quit case.Transition("escalated", "The coordinator's plan is not valid JSON", "system", "run:" _ run.%Id())
    Quit ..AdoptPlan(case, plan, "run:" _ run.%Id())
}

/// Rules-only mode: the plan is a resend of the case's own operation at the observed version,
/// and the gate alone decides.
Method RulesOnly(case As Interlock.Store.Case) As %Status
{
    Set snap = case.CurrentSnapshot
    Set summary = snap.SummaryObject()
    Set ward = summary.%Get("ward_state")
    Set version = $SELECT($ISOBJECT(ward): ##class(Interlock.Util.Json).Str(ward, "version", 0), 1: 0)
    Set plan = {}
    Set plan.disposition = "resend"
    Set plan.summary = "Rules only: resend the operation unchanged at receiver version " _ version _ " unless the gate objects"
    Set action = {}
    Set action.type = "resend", action."operation_key" = case.OperationKey, action."expected_version" = +version
    Set action."payload_digest" = ##class(Interlock.Util.Json).Str(summary.%Get("operation"), "payload_digest")
    Set plan.action = action
    Set plan.preconditions = [], plan."evidence_refs" = [], plan.disagreements = []
    Do case.Note("note", "Rules-only mode: no agents consulted", "system")
    Quit ..AdoptPlan(case, plan, "rules")
}

/// Store the plan as the case's current plan and send it to the gate.
Method AdoptPlan(case As Interlock.Store.Case, plan As %DynamicObject, createdBy As %String) As %Status
{
    Set sc = ##class(Interlock.Store.Plan).Create(case, case.CurrentSnapshot, plan, createdBy, .p)
    Quit:$$$ISERR(sc) sc
    Set ..PlanId = p.%Id()
    Set case.CurrentPlan = p
    Set case.Disposition = p.Disposition
    Set case.Headline = ..HeadlineFor(case, p)
    Set sc = case.Transition("proposed", "Plan v" _ p.Version _ " (" _ p.Disposition _ "): " _ p.Summary, createdBy, "plan:" _ p.%Id())
    Quit:$$$ISERR(sc) sc
    Quit ..SendGate(case, "proposal", "gate:proposal")
}

Method HeadlineFor(case As Interlock.Store.Case, p As Interlock.Store.Plan) As %String
{
    Set what = $CASE(case.Event, "transfer": "transfer to " _ case.Ward, "admit": "admission", "discharge": "discharge", : case.Event)
    Quit $CASE(p.Disposition,
        "superseded": "Valid message. Do not resend: a later event moved the encounter on. " _ $EXTRACT(p.Summary, 1, 200),
        "resend": "Resend the " _ what _ " unchanged, after rehearsal and approval. " _ $EXTRACT(p.Summary, 1, 200),
        "reconcile": "Already applied at the receiver: reconcile, do not resend. " _ $EXTRACT(p.Summary, 1, 200),
        "escalate": "Escalated to a person. " _ $EXTRACT(p.Summary, 1, 200),
        "more_evidence": "More evidence needed. " _ $EXTRACT(p.Summary, 1, 200),
        : p.Disposition _ ": " _ $EXTRACT(p.Summary, 1, 200))
}

Method SendGate(case As Interlock.Store.Case, stage As %String, key As %String) As %Status
{
    Set req = ##class(Interlock.Msg.GateRequest).%New()
    Set req.CaseId = case.CaseId, req.PlanId = ..PlanId, req.Stage = stage
    Set req.ApprovalId = ..ApprovalId
    If ..ReceiverVersion '= "" Set req.ReceiverVersion = ..ReceiverVersion
    If ..ReceiverEpoch '= "" Set req.ReceiverEpoch = ..ReceiverEpoch
    Quit ..SendRequestAsync(..GateTarget, req, 1, key)
}

// ---- the gate, rehearsal, approval, execution, verification ----

Method OnGateProposal(case As Interlock.Store.Case, result As Interlock.Msg.GateResult) As %Status
{
    Set plan = ##class(Interlock.Store.Plan).%OpenId(..PlanId)
    Set sc = case.Transition("gated", "Gate at proposal: " _ result.Outcome _ ". " _ result.Summary, "gate", "gate:" _ result.DecisionId)
    Quit:$$$ISERR(sc) sc
    // A plan that asks for a person is escalated whatever the gate found; the gate's result stays on the case.
    If (plan.Disposition = "escalate") || (plan.Disposition = "more_evidence") {
        Quit case.Transition("escalated", "The plan asks for a person: " _ plan.Summary _ $SELECT(result.Outcome '= "pass": " (the gate noted: " _ result.Summary _ ")", 1: ""), "system", "plan:" _ plan.%Id())
    }
    If result.Outcome '= "pass" {
        Set case.Headline = "Blocked by the gate: " _ result.Summary
        Quit case.Transition("blocked", "The gate did not pass the plan; a person must decide", "gate", "gate:" _ result.DecisionId)
    }
    If plan.IsWrite() {
        Set sc = case.Transition("rehearsing", "Rehearsing the exact action as a dry run", "system")
        Quit:$$$ISERR(sc) sc
        Quit ..SendRequestAsync(..WardTarget, ..WardOperationFor(case, plan, 1), 1, "rehearsal")
    }
    // superseded or reconcile: nothing is written; verify what the receiver holds and close.
    Set sc = case.Transition("verifying", "No write; verifying the receiver's state", "system")
    Quit:$$$ISERR(sc) sc
    Quit ..SendVerify(case)
}

Method WardOperationFor(case As Interlock.Store.Case, plan As Interlock.Store.Plan, dryRun As %Boolean) As Interlock.Msg.WardOperation
{
    Set snap = case.CurrentSnapshot
    Set op = snap.SummaryObject().%Get("operation")
    Set w = ##class(Interlock.Msg.WardOperation).FromOperation(op)
    Set w.Purpose = $SELECT(dryRun: "rehearsal", 1: "recovery")
    Set w.DryRun = dryRun
    Set w.ExpectedVersion = plan.ExpectedVersion
    Set w.CaseId = case.CaseId
    Set w.SourceHeaderId = case.SourceHeaderId
    Quit w
}

Method OnRehearsal(case As Interlock.Store.Case, result As Interlock.Msg.WardResult) As %Status
{
    Set plan = ##class(Interlock.Store.Plan).%OpenId(..PlanId)
    Set sc = ##class(Interlock.Store.Rehearsal).Create(case, plan, result.HttpStatus, result.ResponseObject(), .r)
    Quit:$$$ISERR(sc) sc
    // A dry run that would apply validated the expected version: that is the receiver's version now.
    If result.Outcome = "would_apply" Set ..ReceiverVersion = $SELECT(result.EncounterVersion '= "": result.EncounterVersion, 1: plan.ExpectedVersion)
    If result.Epoch '= "" Set ..ReceiverEpoch = result.Epoch
    Do case.Note("artifact", "Rehearsal: " _ result.Outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "") _ ", rolled back by the receiver", "system", "rehearsal:" _ r.%Id())
    If result.Outcome '= "would_apply" {
        Set case.Headline = "Rehearsal failed: " _ result.Outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "")
        Quit case.Transition("blocked", "The rehearsal shows the action would not apply: " _ result.Outcome _ $SELECT(result.Error '= "": ", " _ result.Error, 1: ""), "system", "rehearsal:" _ r.%Id())
    }
    Set sc = case.Transition("awaiting_approval", "Rehearsal passed; asking an approver for the exact plan", "system", "rehearsal:" _ r.%Id())
    Quit:$$$ISERR(sc) sc
    Set task = ##class(EnsLib.Workflow.TaskRequest).%New()
    Set task.%Actions = "Approve,Reject"
    Set task.%Subject = "Interlock " _ case.CaseId _ ": approve plan v" _ plan.Version _ " (" _ plan.Disposition _ ")"
    Set task.%Message = case.Headline _ $CHAR(10) _ "Exact action: " _ plan.ActionType _ " " _ plan.OperationKey _ " at receiver version " _ plan.ExpectedVersion _ $CHAR(10) _ "Plan digest: " _ plan.Digest _ $CHAR(10) _ "Snapshot digest: " _ $SELECT($ISOBJECT(case.CurrentSnapshot): case.CurrentSnapshot.Digest, 1: "") _ $CHAR(10) _ "Rehearsal: would apply (rolled back)."
    Set task.%Priority = 2
    Set task.%FormFields = "PlanDigest,Comment"
    Do task.%FormValues.SetAt(plan.Digest, "PlanDigest")
    Quit ..SendRequestAsync(..ApprovalTarget, task, 1, "approval")
}

Method OnApproval(case As Interlock.Store.Case, result As EnsLib.Workflow.TaskResponse) As %Status
{
    Set plan = ##class(Interlock.Store.Plan).%OpenId(..PlanId)
    Set action = $ZCONVERT(result.%Action, "L")
    Set user = result.%UserName
    Set comment = result.%FormValues.GetAt("Comment")
    Set digest = result.%FormValues.GetAt("PlanDigest")
    Set taskId = result.%Id()
    Set rehearsal = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM Interlock_Store.Rehearsal WHERE ""Case"" = ? ORDER BY ID DESC", case.%Id())
    If rs.%Next() Set rehearsal = ##class(Interlock.Store.Rehearsal).%OpenId(rs.%Get("ID"))
    If action '= "approve" {
        Set sc = ##class(Interlock.Store.Approval).Create(case, plan, case.CurrentSnapshot, ##class(Interlock.Operation.Gate).#POLICYVERSION, rehearsal, plan.ExpectedVersion, user, "rejected", comment, taskId, ..ApprovalValidSeconds, .a)
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
    Set sc = ##class(Interlock.Store.Approval).Create(case, plan, case.CurrentSnapshot, ##class(Interlock.Operation.Gate).#POLICYVERSION, rehearsal, plan.ExpectedVersion, user, "approved", comment, taskId, ..ApprovalValidSeconds, .a, ..ReceiverEpoch)
    Quit:$$$ISERR(sc) sc
    Set ..ApprovalId = a.%Id()
    Set case.CurrentApproval = a
    Set sc = case.Transition("approved", "Approved by " _ user _ " for plan digest " _ $EXTRACT(plan.Digest, 1, 19) _ $SELECT(comment '= "": ": " _ comment, 1: ""), user, "approval:" _ a.%Id())
    Quit:$$$ISERR(sc) sc
    // Preflight: read the receiver's current version before the dispatch gate decides.
    Set read = ##class(Interlock.Msg.WardOperation).%New()
    Set read.Purpose = "read", read.EncounterId = case.EncounterId, read.OperationKey = case.OperationKey, read.CaseId = case.CaseId
    Quit ..SendRequestAsync(..WardTarget, read, 1, "preflight")
}

Method OnPreflight(case As Interlock.Store.Case, result As Interlock.Msg.WardResult) As %Status
{
    If (result.Outcome = "unknown_encounter") && (case.Event = "admit") {
        Set ..ReceiverVersion = 0
        If result.Epoch '= "" Set ..ReceiverEpoch = result.Epoch
        Do case.Note("note", "Preflight: the receiver has no encounter yet, as the admission expects (version 0)", "system")
        Quit ..SendGate(case, "dispatch", "gate:dispatch")
    }
    If result.Outcome '= "read" {
        Set case.Headline = "Blocked at dispatch: the receiver could not be read (" _ result.Outcome _ ")"
        Quit case.Transition("blocked", "The preflight read of the receiver failed: " _ result.Outcome _ $SELECT(result.Error '= "": ", " _ result.Error, 1: "") _ ". Nothing was dispatched", "system")
    }
    Set ..ReceiverVersion = result.EncounterVersion
    If result.Epoch '= "" Set ..ReceiverEpoch = result.Epoch
    Do case.Note("note", "Preflight: the receiver holds the encounter at version " _ result.EncounterVersion _ " (" _ result.ReasonCode _ ")" _ $SELECT(result.Epoch '= "": ", epoch " _ result.Epoch, 1: ""), "system")
    Quit ..SendGate(case, "dispatch", "gate:dispatch")
}

Method OnGateDispatch(case As Interlock.Store.Case, result As Interlock.Msg.GateResult) As %Status
{
    If result.Outcome '= "pass" {
        // The receiver changed after the approval: the approval is void, and the case is planned
        // again once, on fresh evidence. Anything else blocks for a person.
        Set changed = (result.Summary [ "RECEIVER_CHANGED") || (result.Summary [ "RECEIVER_RESET")
        If changed && (..Replans < 1) {
            Set ..Replans = ..Replans + 1
            Set approval = ##class(Interlock.Store.Approval).%OpenId(..ApprovalId)
            If $ISOBJECT(approval) Do approval.Revoke("system: the receiver changed before dispatch")
            Set ..PlanId = "", ..ApprovalId = "", ..ReceiverVersion = "", ..ReceiverEpoch = ""
            Do case.Note("note", "The receiver changed after the approval (" _ result.Summary _ "). The approval is void and the case is planned again on fresh evidence", "gate", "gate:" _ result.DecisionId)
            Quit ..StartEvidence(case)
        }
        Set case.Headline = "Blocked at dispatch: " _ result.Summary
        Quit case.Transition("blocked", "The gate did not pass the dispatch: " _ result.Summary, "gate", "gate:" _ result.DecisionId)
    }
    Set plan = ##class(Interlock.Store.Plan).%OpenId(..PlanId)
    Set sc = case.Transition("executing", "Dispatching the conditional write (expected version " _ plan.ExpectedVersion _ ")", "system", "gate:" _ result.DecisionId)
    Quit:$$$ISERR(sc) sc
    Quit ..SendRequestAsync(..WardTarget, ..WardOperationFor(case, plan, 0), 1, "execute")
}

Method OnExecute(case As Interlock.Store.Case, result As Interlock.Msg.WardResult) As %Status
{
    Set plan = ##class(Interlock.Store.Plan).%OpenId(..PlanId)
    Set approval = ##class(Interlock.Store.Approval).%OpenId(..ApprovalId)
    Set outcome = $CASE(result.Outcome, "applied": "applied", "already_committed": "already_committed", "version_conflict": "version_conflict", "uncertain": "uncertain", "unavailable": "error", "error": "error", : "refused")
    Set sc = ##class(Interlock.Store.ExecutionAttempt).Create(case, plan, approval, result.HttpStatus, outcome, result.ResponseObject(), result.Error, .attempt)
    Quit:$$$ISERR(sc) sc
    Set ..AttemptId = attempt.%Id()
    Do case.Note("execution", "Dispatch: " _ outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "") _ ", HTTP " _ result.HttpStatus, "system", "attempt:" _ attempt.%Id())
    If (outcome = "applied") || (outcome = "already_committed") || (outcome = "uncertain") {
        Set sc = case.Transition("verifying", $SELECT(outcome = "uncertain": "The receiver did not answer; reconciling by operation key", 1: "The receiver acknowledged; verifying the effect"), "system", "attempt:" _ attempt.%Id())
        Quit:$$$ISERR(sc) sc
        Quit ..SendVerify(case)
    }
    Set case.Headline = "Dispatch refused: " _ outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "")
    Quit case.Transition("blocked", "The conditional write was refused: " _ outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "") _ ". The plan is void; a person must decide", "system", "attempt:" _ attempt.%Id())
}

Method SendVerify(case As Interlock.Store.Case) As %Status
{
    Set req = ##class(Interlock.Msg.VerifyRequest).%New()
    Set req.CaseId = case.CaseId, req.PlanId = ..PlanId, req.AttemptId = ..AttemptId
    Quit ..SendRequestAsync(..VerifyTarget, req, 1, "verify")
}

Method OnVerify(case As Interlock.Store.Case, result As Interlock.Msg.VerifyResult) As %Status
{
    If result.Outcome = "verified" {
        Set case.Outcome = result.Summary
        Quit case.Transition("resolved", "Verified: " _ result.Summary, "system", "verification:" _ result.VerificationId)
    }
    Set case.Outcome = result.Summary
    Quit case.Transition("escalated", "Not verified (" _ result.Outcome _ "): " _ result.Summary, "system", "verification:" _ result.VerificationId)
}

Storage Default
{
<Data name="CaseWorkflowDefaultData">
<Subscript>"CaseWorkflow"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>Mode</Value>
</Value>
<Value name="3">
<Value>PendingJSON</Value>
</Value>
<Value name="4">
<Value>FailedJSON</Value>
</Value>
<Value name="5">
<Value>PlanId</Value>
</Value>
<Value name="6">
<Value>ApprovalId</Value>
</Value>
<Value name="7">
<Value>AttemptId</Value>
</Value>
<Value name="8">
<Value>ReceiverVersion</Value>
</Value>
<Value name="9">
<Value>ReceiverEpoch</Value>
</Value>
<Value name="10">
<Value>Replans</Value>
</Value>
<Value name="11">
<Value>EvidenceTarget</Value>
</Value>
<Value name="12">
<Value>GateTarget</Value>
</Value>
<Value name="13">
<Value>WardTarget</Value>
</Value>
<Value name="14">
<Value>ApprovalTarget</Value>
</Value>
<Value name="15">
<Value>VerifyTarget</Value>
</Value>
<Value name="16">
<Value>ApprovalValidSeconds</Value>
</Value>
</Data>
<DefaultData>CaseWorkflowDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
