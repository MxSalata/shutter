/// The case workflow: opens a case from an intake and takes it through evidence, the board, the
/// coordinator, the gate, rehearsal, approval, execution and verification. One instance per case;
/// every step is a message to another production item, so the Visual Trace of a case is its
/// audit trail. The instance keeps only identifiers between steps; the store holds the record.
Class Shutter.Process.CaseWorkflow Extends Ens.BusinessProcess
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

Property WardTarget As %String(MAXLEN = 128) [ InitialExpression = {$PARAMETER("Shutter.Production", "RECEIVER")} ];

Property ApprovalTarget As %String(MAXLEN = 128) [ InitialExpression = "Shutter Approvers" ];

Property VerifyTarget As %String(MAXLEN = 128) [ InitialExpression = "Verifier" ];

/// Seconds an approval stays valid.
Property ApprovalValidSeconds As %Integer [ InitialExpression = 3600 ];

/// Boards convened per minute at most (v1.35): a case that finds the minute's cap reached waits about a minute for a slot
/// instead of convening at once (Shutter.Util.BoardSlots), so a storm of failures costs the cap a minute rather than one paid
/// board per message, and no case is lost. 0 means no cap.
Property BoardsPerMinute As %Integer [ InitialExpression = 6 ];

/// Whether this case is waiting for a board slot, and who asked for the board (OnBoardDefer convenes it then).
/// The board mode a deferred case convenes with when its slot comes (v1.35; the policy path asks for the full board).
Property DeferredMode As %String(MAXLEN = 16);

/// The failure signature this case leads a board for (v1.35, one board per failure signature), until the lead is finished.
Property LeadSignature As %String(MAXLEN = 80);

Property DeferredBy As %String(MAXLEN = 100);

/// How long an approval task may wait for a decision (v1.35): after this many seconds with no answer the task is cancelled
/// and the case escalates, so a plan nobody looked at never waits for ever; 0 waits without limit. 24 hours by default.
Property ApprovalWaitSeconds As %Integer [ InitialExpression = 86400 ];

/// The site's policy for this case when the catalogue settled it: automatic, approval, per_chain or board.
Property Policy As %String(MAXLEN = 16);

/// The catalogue entry and outcome the policy path followed.
Property CatalogueEntry As %String(MAXLEN = 16);

Property CatalogueOutcome As %String(MAXLEN = 32);

/// How long a new case waits before the evidence is collected, so that messages still in flight
/// for the encounter (a later transfer, a retry from the source) are in the snapshot. 0 collects at once.
Property SettleSeconds As %Integer [ InitialExpression = 15 ];

/// Set on an instance started by a case release from an incident (CONTRACTS 7.4).
Property Release As %Boolean [ InitialExpression = 0 ];

Property IncidentId As %String(MAXLEN = 32);

Property ChainSeq As %Integer;

Property ChainPosition As %Integer;

/// The kind of chain this case belongs to (single, ordered, interleaved); single for a case on its own.
Property ChainKind As %String(MAXLEN = 16) [ InitialExpression = "single" ];

/// policy, board or person: who decides a released case, from its chain's classification.
Property ChainDecides As %String(MAXLEN = 16);

/// The receiver version the chain expects at this item's dispatch, or "" when fresh evidence decides.
Property ExpectedVersion As %String(MAXLEN = 20);

/// automatic, incident or path: how a released policy case is authorised.
Property ReleasePolicy As %String(MAXLEN = 16);

Property IncidentApprover As %String(MAXLEN = 100);

Property IncidentApprovalRef As %String(MAXLEN = 50);

Property IncidentPlanDigest As %String(MAXLEN = 80);

/// The catalogue entry and outcome the incident's approval bound for this item (CONTRACTS 7.3): fresh evidence that
/// reads otherwise is not covered by it.
Property IncidentEntry As %String(MAXLEN = 16);

Property IncidentOutcome As %String(MAXLEN = 32);

Property IncidentTarget As %String(MAXLEN = 128) [ InitialExpression = "Incident Workflow" ];

/// Seconds a board round, or the coordinator, may take before the case goes on without the missing answers.
Property BoardTimeoutSeconds As %Integer [ InitialExpression = 600 ];

Property CoordinatorPending As %Boolean [ InitialExpression = 0 ];

/// Evidence refreshes and preflight retries taken at the dispatch stage (A1): bounded, then the case blocks.
Property Refreshes As %Integer [ InitialExpression = 0 ];

/// The investigation round (one per evidence collection); a timeout armed in an earlier round is ignored when it fires.
Property Round As %Integer [ InitialExpression = 0 ];

/// The next evidence collection is a refresh under an approval, not a new investigation.
Property Refreshing As %Boolean [ InitialExpression = 0 ];

Property MaxRefreshes As %Integer [ InitialExpression = 3 ];

/// Set on an instance that reopened a closed case: it runs alone, even when an incident once held the case.
Property Reopened As %Boolean [ InitialExpression = 0 ];

/// The reopening asked for the board whatever the policy says (a judge's "Convene the board", v1.34), and who asked.
Property ForceBoard As %Boolean [ InitialExpression = 0 ];

Property ConvenedBy As %String(MAXLEN = 100);

/// Who reopened the case (v1.39): the person whose share the reopened case's runs count against; "" for a case the feed
/// opened, whose runs are the feed's own ("system").
Property ReopenedBy As %String(MAXLEN = 100);

/// Whether the reopened case's agents may run live (v1.39): false for a reopener without Shutter_LiveAgents, or while the
/// provider refuses the key; then every agent request carries ModeOverride replay, as a question's does (14).
Property LiveAllowed As %Boolean [ InitialExpression = 1 ];

Parameter SETTINGS = "EvidenceTarget:Targets,GateTarget:Targets,WardTarget:Targets,ApprovalTarget:Targets,VerifyTarget:Targets,IncidentTarget:Targets,ApprovalValidSeconds:Approval,ApprovalWaitSeconds:Approval,SettleSeconds:Timing,BoardTimeoutSeconds:Timing,BoardsPerMinute:Timing,MaxRefreshes:Timing";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    If request.%IsA("Shutter.Msg.CaseRelease") Quit ..OnRelease(request, .response)
    If request.%IsA("Shutter.Msg.Reinvestigate") Quit ..OnReinvestigate(request, .response)
    If request.%IsA("Shutter.Msg.LeadReady") Quit ..OnLeadReady(request, .response)
    If request.%IsA("Shutter.Msg.CaseClose") Quit ..OnClose(request, .response)
    If request.%IsA("Shutter.Msg.CaseAbandon") Quit ..OnAbandon(request, .response)
    If 'request.%IsA("Shutter.Msg.CaseIntake") Quit $$$ERROR($$$GeneralError, "Case Workflow expects a case intake, a case release, a reinvestigation, a close or an abandon, got " _ $CLASSNAME(request))
    Set op = ##class(Shutter.Util.Json).Parse(request.OperationJSON, .sc)
    If $$$ISERR(sc) Quit sc
    Set sc = ##class(Shutter.Store.Case).Open(op, request.FailureKind, request.FailureText, request.EnsSessionId, request.SourceHeaderId, request.Mode, .case, .opened, $SELECT(request.Receiver '= "": request.Receiver, 1: ..WardTarget), request.HeldSchema)
    If $$$ISERR(sc) Quit sc
    Set started = ##class(Shutter.Msg.CaseStarted).%New()
    Set started.CaseId = case.CaseId, started.Opened = opened, started.State = case.State
    Set response = started
    If 'opened {
        // The production's own report of a failure the alert intake reported first (v1.38): the alert's words gave the
        // case its failure with no reason code, so the catalogue matched nothing (new_pattern) where the report's
        // ward_unavailable matches an entry. Before the evidence is collected, the report's fields replace the alert's.
        Set taken = ..TakeReport(case, request)
        $$$TRACE("Case " _ case.CaseId _ " already open; the new failure was noted" _ $SELECT(taken: ", and its failure is now the production's own report", 1: ""))
        Quit $$$OK
    }
    Set ..CaseId = case.CaseId, ..Mode = case.Mode
    Set case.WorkflowSessionId = ..%SessionId
    // The receiver is the one the intake names (a case from another production, CONTRACTS 11), else this process's
    // connector; where the original message lives travels with it, so the evidence can say where it is.
    Set case.Receiver = $SELECT(request.Receiver '= "": request.Receiver, 1: ..WardTarget)
    Set case.SourceNamespace = request.SourceNamespace, case.SourceProduction = request.SourceProduction
    Set case.SourceRoute = request.SourceRoute, case.OriginHeaderId = request.OriginHeaderId
    // The connector's answer, structured, so the matcher never parses it out of the failure text.
    Set wr = ##class(Shutter.Util.Json).Parse(request.WardResultJSON, .wsc)
    If $ISOBJECT(wr) {
        Set case.FailureOutcome = ##class(Shutter.Util.Json).Str(wr, "outcome"), case.FailureReasonCode = ##class(Shutter.Util.Json).Str(wr, "reason_code")
        Set status = ##class(Shutter.Util.Json).Str(wr, "http_status")
        If +status > 0 Set case.FailureHttpStatus = +status
        // The receiver's Retry-After (v1.35): the resend's preflight read waits for it.
        Set retryAfter = ##class(Shutter.Util.Json).Str(wr, "retry_after_seconds")
        If +retryAfter > 0 Set case.RetryAfterUntil = ##class(Shutter.Util.Time).FromNow(+retryAfter)
    }
    // A withheld operation was never sent: its reason code (merge, cancel_unsupported) is the feed's, not the connector's.
    If (request.FailureReasonCode '= "") && ($ZSTRIP(request.WardResultJSON, "<>W") = "") Set case.FailureReasonCode = request.FailureReasonCode
    Do case.%Save()
    $$$TRACE("Case " _ case.CaseId _ " opened (" _ case.Mode _ "): " _ case.Headline)
    // The answer goes back now, not when the whole workflow completes: the case intake process (and through it the
    // REST route) waits for the case id, and the feed's instance need not stay open for the investigation. The
    // response set above still stands for a caller that reads it at completion.
    Set rsc = ..Reply(started)
    If $$$ISERR(rsc) $$$TRACE("The early reply was not sent: " _ $SYSTEM.Status.GetErrorText(rsc))
    // Detection (CONTRACTS 7.1): this failure counts towards an incident for the receiver; at the threshold one
    // opens, adopts the burst's cases, and its workflow starts. A detection error never stops the case.
    Set dsc = ##class(Shutter.Store.IncidentDetector).Register(case, case.Receiver, .incident, .openedNow)
    If $$$ISERR(dsc) {
        $$$LOGWARNING("Incident detection failed for " _ case.CaseId _ ": " _ $SYSTEM.Status.GetErrorText(dsc))
    } ElseIf $ISOBJECT(incident) && openedNow {
        Set intake = ##class(Shutter.Msg.IncidentIntake).%New()
        Set intake.IncidentId = incident.IncidentId, intake.CaseId = case.CaseId
        Set dsc = ..SendRequestAsync(..IncidentTarget, intake, 0)
        If $$$ISERR(dsc) $$$LOGWARNING("Could not start the workflow of incident " _ incident.IncidentId _ ": " _ $SYSTEM.Status.GetErrorText(dsc))
    }
    If ..SettleSeconds <= 0 Quit ..StartEvidence(case)
    Do case.Note("note", "Waiting " _ ..SettleSeconds _ " s for the feed to settle before collecting evidence", "system", "")
    Set alarm = ##class(Ens.AlarmRequest).%New()
    Set alarm.Timeout = ..SettleSeconds
    Quit ..SendRequestAsync("Ens.Alarm", alarm, 1, "settle", "Settle period before the investigation")
}

Method StartEvidence(case As Shutter.Store.Case) As %Status
{
    Set ..Round = ..Round + 1
    Set sc = case.Transition("collecting", "Collecting evidence", "system")
    Quit:$$$ISERR(sc) sc
    Set req = ##class(Shutter.Msg.EvidenceRequest).%New()
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
        Set case = ##class(Shutter.Store.Case).ByCaseId(..CaseId)
        If '$ISOBJECT(case) Quit
        If case.IsClosed() {
            // A late agent answer still has a cost: record the run, then ignore it.
            If $ISOBJECT(callresponse) && (($EXTRACT(completionkey, 1, 7) = "member:") || (completionkey = "coordinator")) {
                Set code = $SELECT(completionkey = "coordinator": "coordinator", 1: $EXTRACT(completionkey, 8, *))
                Set m = ##class(Shutter.Store.BoardMember).ByCode(code)
                Do ##class(Shutter.Store.AgentRun).FromResponse(case, case.CurrentSnapshot, $SELECT(completionkey = "coordinator": "coordinator", $ISOBJECT(m): m.Role, 1: ""), code, callresponse, ..HeaderIdOf(..%LastCallRequest), .run)
            }
            $$$TRACE("Case " _ ..CaseId _ " is closed; ignoring " _ completionkey)
            Quit
        }
        // A reopened or released case belongs to its newest instance; an answer that reaches an earlier one is recorded
        // for its cost and changes nothing.
        If (case.WorkflowSessionId '= "") && (case.WorkflowSessionId '= ..%SessionId) {
            If $ISOBJECT(callresponse) && (($EXTRACT(completionkey, 1, 7) = "member:") || (completionkey = "coordinator")) {
                Set code = $SELECT(completionkey = "coordinator": "coordinator", 1: $EXTRACT(completionkey, 8, *))
                Set m = ##class(Shutter.Store.BoardMember).ByCode(code)
                Do ##class(Shutter.Store.AgentRun).FromResponse(case, case.CurrentSnapshot, $SELECT(completionkey = "coordinator": "coordinator", $ISOBJECT(m): m.Role, 1: ""), code, callresponse, ..HeaderIdOf(..%LastCallRequest), .run)
            }
            $$$TRACE("Case " _ ..CaseId _ " is driven by another instance (session " _ case.WorkflowSessionId _ "); ignoring " _ completionkey)
            Quit
        }
        If $PIECE(completionkey, ":", 1, 2) = "board:timeout" {
            If +$PIECE(completionkey, ":", 3) '= +..Round { $$$TRACE("A board timeout from round " _ $PIECE(completionkey, ":", 3) _ " arrived in round " _ ..Round _ "; ignored") Quit }
            Set sc = ..OnBoardTimeout(case) Quit
        }
        If $PIECE(completionkey, ":", 1, 2) = "lead:timeout" {
            If +$PIECE(completionkey, ":", 3) '= +..Round { $$$TRACE("A lead timeout from round " _ $PIECE(completionkey, ":", 3) _ " arrived in round " _ ..Round _ "; ignored") Quit }
            Set sc = ..OnLeadTimeout(case) Quit
        }
        If completionkey = "preflight:retry" { Set sc = ..SendPreflight(case) Quit }
        If completionkey = "refresh:retry" { Set sc = ..StartEvidence(case) Quit }
        If completionkey = "verify:retry" { Set sc = ..SendVerify(case) Quit }
        If $PIECE(completionkey, ":", 1, 2) = "coordinator:timeout" {
            If +$PIECE(completionkey, ":", 3) '= +..Round { $$$TRACE("A coordinator timeout from round " _ $PIECE(completionkey, ":", 3) _ " arrived in round " _ ..Round _ "; ignored") Quit }
            Set sc = ..OnCoordinatorTimeout(case) Quit
        }
        If completionkey = "settle" { Set sc = ..StartEvidence(case) Quit }
        If completionkey = "evidence" { Set sc = ..OnEvidence(case, callresponse) Quit }
        If $EXTRACT(completionkey, 1, 7) = "member:" { Set sc = ..OnMember(case, $EXTRACT(completionkey, 8, *), callresponse) Quit }
        If completionkey = "coordinator" { Set sc = ..OnCoordinator(case, callresponse) Quit }
        If completionkey = "gate:proposal" { Set sc = ..OnGateProposal(case, callresponse) Quit }
        If completionkey = "rehearsal" { Set sc = ..OnRehearsal(case, callrequest, callresponse) Quit }
        If completionkey = "approval" { Set sc = ..OnApproval(case, callresponse) Quit }
        If $PIECE(completionkey, ":", 1, 2) = "approval:timeout" { Set sc = ..OnApprovalTimeout(case, +$PIECE(completionkey, ":", 3)) Quit }
        If $PIECE(completionkey, ":", 1, 2) = "board:defer" { Set sc = ..OnBoardDefer(case, +$PIECE(completionkey, ":", 3)) Quit }
        If completionkey = "preflight" { Set sc = ..OnPreflight(case, callresponse) Quit }
        If completionkey = "gate:dispatch" { Set sc = ..OnGateDispatch(case, callresponse) Quit }
        If completionkey = "execute" { Set sc = ..OnExecute(case, callresponse) Quit }
        If completionkey = "verify" { Set sc = ..OnVerify(case, callresponse) Quit }
        $$$LOGWARNING("Unexpected completion key " _ completionkey)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) {
        Set case = ##class(Shutter.Store.Case).ByCaseId(..CaseId)
        If $ISOBJECT(case) && 'case.IsClosed() {
            // A lead this case holds ends with it, so the cases following it carry on at once instead of waiting out the bound.
            Do ..LeadFinish(case, "failed", "", "the leader's workflow failed: " _ $EXTRACT($SYSTEM.Status.GetErrorText(sc), 1, 400))
            Do case.Transition("failed", "Workflow error at " _ completionkey _ ": " _ $SYSTEM.Status.GetErrorText(sc), "system")
        }
    }
    Quit sc
}

/// A called item answered with an error status instead of a response: the case fails with the reason, and the
/// instance ends cleanly instead of stranding the case in a working state.
Method OnError(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, pErrorStatus As %Status, pCompletionKey As %String) As %Status
{
    Try {
        Set case = ##class(Shutter.Store.Case).ByCaseId(..CaseId)
        If $ISOBJECT(case) && 'case.IsClosed() && ((case.WorkflowSessionId = "") || (case.WorkflowSessionId = ..%SessionId)) {
            Set text = $EXTRACT($SYSTEM.Status.GetErrorText(pErrorStatus), 1, 400)
            // A board member or the coordinator the case no longer waits for (an earlier round, or a late call).
            Set awaited = 1
            If $EXTRACT(pCompletionKey, 1, 7) = "member:" {
                Set awaited = 0, code = $EXTRACT(pCompletionKey, 8, *)
                Set pending = ##class(%DynamicArray).%FromJSON(..PendingJSON), iter = pending.%GetIterator()
                While iter.%GetNext(.i, .c) { If c = code Set awaited = 1 }
            } ElseIf pCompletionKey = "coordinator" {
                Set awaited = ..CoordinatorPending
            }
            If 'awaited {
                Do case.Note("error", "The call " _ pCompletionKey _ " failed after the case had moved on: " _ text, "system")
                Quit
            }
            If pCompletionKey = "execute" {
                // The write may or may not have been applied: that is for a person to establish, not a failure.
                Set case.Headline = "Escalated: the write's call failed and its outcome is unknown"
                Do case.Transition("escalated", "Error from the write call: " _ text _ ". Whether the receiver applied the operation is unknown; a person must check", "system")
                Quit
            }
            // A lead this case holds ends with it, so the cases following it carry on at once instead of waiting out the bound.
            Do ..LeadFinish(case, "failed", "", "the leader's workflow failed: " _ text)
            Set case.Headline = "Failed: " _ text
            Do case.Transition("failed", "Error from the call " _ pCompletionKey _ ": " _ text, "system")
        }
    } Catch {
    }
    Quit $$$OK
}

// ---- evidence and the board ----

Method OnEvidence(case As Shutter.Store.Case, result As Shutter.Msg.EvidenceResult) As %Status
{
    If '$ISOBJECT(result) || (result.Error '= "") Quit $$$ERROR($$$GeneralError, "Evidence failed: " _ $SELECT($ISOBJECT(result): result.Error, 1: "no result"))
    Set sc = case.Transition("investigating", "Evidence collected: snapshot " _ result.SnapshotId _ ", digest " _ $EXTRACT(result.Digest, 1, 19), "system", "snapshot:" _ result.SnapshotId)
    Quit:$$$ISERR(sc) sc
    Set summary = ##class(Shutter.Util.Json).Parse(result.SummaryJSON, .psc)
    Set cat = $SELECT($ISOBJECT(summary): summary.%Get("catalogue"), 1: "")
    Set decision = $SELECT($ISOBJECT(cat): ##class(Shutter.Util.Json).Str(cat, "decision"), 1: "")
    // A refresh under an approval (A1): the approval stands when nothing material changed, and the dispatch goes on
    // from the preflight read; otherwise the approval is void and the case is planned again on the fresh evidence.
    If ..Refreshing {
        Set snap = case.CurrentSnapshot
        // A refresh whose own lookups failed decides nothing: it waits and collects again, up to the limit.
        If '..Complete(summary, case) {
            If ..Refreshes < ..MaxRefreshes {
                Set ..Refreshes = ..Refreshes + 1
                Set wait = 10 * (2 ** (..Refreshes - 1))
                Do case.Note("note", "The refreshed evidence still has a lookup that failed; collecting again in " _ wait _ " s (" _ ..Refreshes _ " of " _ ..MaxRefreshes _ ")", "system", "snapshot:" _ $SELECT($ISOBJECT(snap): snap.%Id(), 1: ""))
                Set alarm = ##class(Ens.AlarmRequest).%New()
                Set alarm.Timeout = wait
                Quit ..SendRequestAsync("Ens.Alarm", alarm, 1, "refresh:retry")
            }
            Set ..Refreshing = 0
            Set case.Headline = "Blocked at dispatch: the receiver or its receipts could not be read"
            Quit case.Transition("blocked", "The evidence could not be completed in " _ ..MaxRefreshes _ " refreshes (the receiver or its receipts could not be read); nothing was dispatched, and a person must look", "system")
        }
        Set ..Refreshing = 0
        Set approval = ##class(Shutter.Store.Approval).%OpenId(..ApprovalId)
        If $ISOBJECT(approval) && $ISOBJECT(snap) && (approval.MaterialDigest '= "") && (approval.MaterialDigest = snap.MaterialDigest) {
            Set sc = case.Transition("approved", "Evidence refreshed (" _ ..Refreshes _ " of " _ ..MaxRefreshes _ "): nothing material changed, so the approval of " _ approval.Approver _ " stands; dispatching again", "system", "snapshot:" _ snap.%Id())
            Quit:$$$ISERR(sc) sc
            Quit ..SendPreflight(case)
        }
        If $ISOBJECT(approval) Do approval.Revoke("system: the evidence changed materially on refresh")
        Set ..PlanId = "", ..ApprovalId = "", ..ReceiverVersion = "", ..ReceiverEpoch = "", ..AttemptId = ""
        Do case.Note("note", "Evidence refreshed (" _ ..Refreshes _ " of " _ ..MaxRefreshes _ "): the evidence changed materially, so the approval is void and the case is planned again", "system", "snapshot:" _ $SELECT($ISOBJECT(snap): snap.%Id(), 1: ""))
    }
    // A case an incident holds parks here, its evidence and match in the store: the incident decides when it is
    // released (CONTRACTS 7.1).
    If '..Release && '..Reopened && $ISOBJECT(case.Incident) {
        Set sc = ..Park(case, .parked)
        If parked || $$$ISERR(sc) Quit sc
    }
    // Every investigation starts clean: a policy from an earlier round never carries over to a plan the board makes.
    Set ..Policy = "", ..CatalogueEntry = "", ..CatalogueOutcome = ""
    // A withheld operation (T31) has one answer in every mode: nothing is sent and a person decides. The gate blocks
    // every plan on it, so a board run would only cost: a burst of merges or cancels would buy one run per message.
    If case.FailureKind = "withheld" {
        If $ISOBJECT(cat) && (cat.%GetTypeOf("matches") = "array") && (cat.%Get("matches").%Size() = 1) Quit ..PersonByCatalogue(case, cat)
        Quit ..WithheldToPerson(case)
    }
    // A receiver of category orders_results (v1.23) keeps orders and results, which the ADT catalogue does not model:
    // the case goes to a person at once, in every mode, and no model runs for it.
    If ##class(Shutter.Store.SiteProfile).ReceiverCategory($SELECT(case.Receiver '= "": case.Receiver, 1: ..WardTarget)) = "orders_results" Quit ..NotModelledToPerson(case)
    If ..Release {
        // The sequence rule (7.4): the item goes at the version the chain expects, or not at all.
        If ..ExpectedVersion '= "" {
            Set ward = $SELECT($ISOBJECT(summary): summary.%Get("ward_state"), 1: "")
            Set version = $SELECT($ISOBJECT(ward): +##class(Shutter.Util.Json).Str(ward, "version", 0), 1: 0)
            If version '= +..ExpectedVersion {
                Set case.Headline = "Blocked by the sequence rule: the receiver is at version " _ version _ ", chain " _ ..ChainSeq _ " expected " _ ..ExpectedVersion
                Quit case.Transition("blocked", "Sequence rule: the receiver is at version " _ version _ " but chain " _ ..ChainSeq _ " of incident " _ ..IncidentId _ " expected " _ ..ExpectedVersion _ " (the version the previous item verified). Something else wrote in between; nothing was dispatched, and a person must look", "system", "incident:" _ ..IncidentId)
            }
            Do case.Note("note", "Sequence rule: the receiver is at version " _ version _ ", as chain " _ ..ChainSeq _ " expected", "system")
        }
        // The chain's classification decides the path (7.2), not the case's own match.
        If ..ChainDecides = "policy" {
            If decision = "policy" Quit ..PolicyPath(case, summary, cat)
            Do case.Note("note", "Catalogue on fresh evidence: " _ $SELECT(decision = "": "no result", 1: decision) _ " (the chain was classified policy); the board decides this item", "system")
        } ElseIf ..ChainDecides = "person" {
            If $ISOBJECT(cat) && (cat.%GetTypeOf("matches") = "array") && (cat.%Get("matches").%Size() > 0) Quit ..PersonByCatalogue(case, cat)
            Quit case.Transition("escalated", "Chain " _ ..ChainSeq _ " of incident " _ ..IncidentId _ " asks for a person", "system", "incident:" _ ..IncidentId)
        } Else {
            Do case.Note("note", "Released on the chain's own path (" _ ..ChainDecides _ " decides)", "system")
        }
    } ElseIf ..Mode = "policy" {
        // In policy mode the catalogue's match settles the easy cases (CONTRACTS 6.3); the rest go to the board. A judge's
        // forced board (v1.34; v1.39) comes before the person path: the catalogue's "person" is the decision the board
        // was asked to take again on fresh evidence, so the case convenes it instead of escalating again.
        If decision = "policy" Quit ..PolicyPath(case, summary, cat)
        If (decision = "person") && '..ForceBoard Quit ..PersonByCatalogue(case, cat)
        Do case.Note("note", "Catalogue: " _ $SELECT(decision = "": "no result", 1: decision) _ "; the board decides" _ $SELECT(..ForceBoard && (decision = "person"): " (convened by " _ ..ConvenedBy _ " on the catalogue's person decision)", 1: ""), "system")
    }
    // One board per failure signature (v1.35): a case whose signature has a board running, or decided within the window,
    // follows it instead of convening its own; the first case of a signature leads.
    Set lead = ..LeadFor(case, summary, .signature)
    If $ISOBJECT(lead) Quit ..Follow(case, lead, signature)
    Set sc = ..ConveneBoard(case, result.SummaryJSON, $SELECT(..ForceBoard: ..ConvenedBy, 1: ""), "", .convened)
    Quit:($$$ISERR(sc) || 'convened) sc
    Quit ..AfterConvene(case, result.SummaryJSON)
}

// ---- one board per failure signature (v1.35) ----

/// The lead a case follows for its failure signature, or "" when it convenes its own board, and then leads the signature
/// itself while coalescing is on and a board would convene. A forced board (a judge's request) and an incident's release
/// never follow.
Method LeadFor(case As Shutter.Store.Case, summary As %DynamicObject, Output signature As %String) As Shutter.Store.BoardLead
{
    Set signature = ""
    If ..ForceBoard || ..Release || '$ISOBJECT(summary) Quit ""
    If ##class(Shutter.Store.BoardLead).WindowSeconds() <= 0 Quit ""
    Set mode = $SELECT(..Mode = "policy": "board", 1: ..Mode)
    If ##class(Shutter.Store.BoardMember).MembersForMode(mode).%Size() = 0 Quit ""
    Set signature = ##class(Shutter.Util.Signature).Of(case, summary)
    If signature = "" Quit ""
    Set lead = ##class(Shutter.Store.BoardLead).Current(signature)
    If $ISOBJECT(lead) && (lead.LeaderCaseId '= case.CaseId) Quit lead
    If '$ISOBJECT(lead) {
        Set sc = ##class(Shutter.Store.BoardLead).Begin(signature, case, ##class(Shutter.Util.Signature).Parts(case, summary), .mine)
        If $$$ISOK(sc) Set ..LeadSignature = signature, case.LeadSignature = signature
    }
    Quit ""
}

/// A case of a signature whose board runs or ran on another case: it takes that decision now when the lead is done, or
/// waits for it (FollowsCase), with a bound of twice the board's timeout.
Method Follow(case As Shutter.Store.Case, lead As Shutter.Store.BoardLead, signature As %String) As %Status
{
    Set case.LeadSignature = signature
    If lead.State = "done" Quit ..TakeDiagnosis(case, lead)
    Set case.FollowsCase = lead.LeaderCaseId
    Set sc = case.%Save()
    Do case.Note("note", "Board not convened: the same failure signature has a board running on case " _ lead.LeaderCaseId _ " (since " _ lead.StartedAt _ "); this case follows it and will take its decision, keeping its own gate, rehearsal and approval", "system", "lead:" _ lead.%Id())
    Set alarm = ##class(Ens.AlarmRequest).%New()
    Set alarm.Timeout = (2 * ..BoardTimeoutSeconds) + 60
    Quit ..SendRequestAsync("Ens.Alarm", alarm, 1, "lead:timeout:" _ ..Round, "Waiting for the leader's board")
}

/// The board a follower waited for has ended (Shutter.Msg.LeadReady): a fresh instance carries the follower on from its
/// evidence, as a reinvestigation does; the instance that waited ignores its alarm, since the case is driven here now.
Method OnLeadReady(request As Shutter.Msg.LeadReady, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Quit $$$ERROR($$$GeneralError, "No case " _ request.CaseId _ " to carry on")
    If (case.State '= "investigating") || (case.FollowsCase '= request.LeaderCaseId) {
        $$$TRACE("Case " _ case.CaseId _ " is " _ case.State _ " and follows " _ $SELECT(case.FollowsCase = "": "nobody", 1: case.FollowsCase) _ "; the lead of " _ request.LeaderCaseId _ " changes nothing")
        Quit $$$OK
    }
    Set ..CaseId = case.CaseId, ..Mode = case.Mode
    Set case.WorkflowSessionId = ..%SessionId
    Do case.%Save()
    Set lead = ##class(Shutter.Store.BoardLead).ForLeader(request.LeaderCaseId)
    If '$ISOBJECT(lead) || (lead.State '= "done") Quit ..LeadFailedFallback(case, lead)
    Quit ..TakeDiagnosis(case, lead)
}

/// The bound on a follower's wait: the lead's decision if it is there by now, else the rules path.
Method OnLeadTimeout(case As Shutter.Store.Case) As %Status
{
    If (case.State '= "investigating") || (case.FollowsCase = "") { $$$TRACE("The lead wait ended; the case is " _ case.State _ ", so nothing is due") Quit $$$OK }
    Set lead = ##class(Shutter.Store.BoardLead).ForLeader(case.FollowsCase)
    If $ISOBJECT(lead) && (lead.State = "done") Quit ..TakeDiagnosis(case, lead)
    Quit ..LeadFailedFallback(case, lead)
}

/// The board this case followed ended without a decision, or never ended: the rules path proposes the plain resend and
/// the gate judges it, as when no board member can answer.
Method LeadFailedFallback(case As Shutter.Store.Case, lead As Shutter.Store.BoardLead) As %Status
{
    Set leader = case.FollowsCase
    Set case.FollowsCase = ""
    Set why = $SELECT('$ISOBJECT(lead): "no lead was recorded for it", lead.State = "running": "its board has not finished within the wait", lead.Reason '= "": lead.Reason, 1: "it ended without a plan")
    Do case.Note("note", "The board this case followed (case " _ leader _ ") decided nothing: " _ why _ "; the rules path proposes the plain resend and the gate judges it", "system")
    Quit ..RulesOnly(case)
}

/// The leader's decision applied to this case's own evidence: the disposition and action type, the catalogue entry and
/// outcome when this case's own match shows the entry, and the members' verdicts, never a word of the leader's text (which
/// carries the leader's patient); the operation key, the receiver version and the payload digest are this case's own.
/// The plan then goes to the gate, the rehearsal and the approval as any plan does.
Method TakeDiagnosis(case As Shutter.Store.Case, lead As Shutter.Store.BoardLead) As %Status
{
    Set json = "Shutter.Util.Json"
    Set case.FollowsCase = ""
    Set leaderPlan = $CLASSMETHOD(json, "Parse", lead.PlanJSON, .psc)
    If '$ISOBJECT(leaderPlan) Quit ..LeadFailedFallback(case, lead)
    Set snap = case.CurrentSnapshot
    Set summary = $SELECT($ISOBJECT(snap): snap.SummaryObject(), 1: {})
    Set ward = summary.%Get("ward_state")
    Set version = $SELECT($ISOBJECT(ward): $CLASSMETHOD(json, "Str", ward, "version", 0), 1: 0)
    Set disposition = $CLASSMETHOD(json, "Str", leaderPlan, "disposition", "resend")
    Set leaderAction = leaderPlan.%Get("action")
    Set actionType = $SELECT($ISOBJECT(leaderAction): $CLASSMETHOD(json, "Str", leaderAction, "type", disposition), 1: $SELECT(disposition = "escalate": "none", 1: disposition))
    Set plan = {}
    Set plan.disposition = disposition
    Set action = {"type": (actionType)}
    If actionType '= "none" {
        Set action."operation_key" = case.OperationKey, action."expected_version" = +version
        Set action."payload_digest" = $CLASSMETHOD(json, "Str", summary.%Get("operation"), "payload_digest")
    }
    Set plan.action = action
    // The entry only when this case's own match shows it: the matcher ran on this case's evidence.
    Set entry = $CLASSMETHOD(json, "Str", leaderPlan, "catalogue_entry"), outcome = $CLASSMETHOD(json, "Str", leaderPlan, "outcome")
    Set cat = summary.%Get("catalogue"), own = 0
    If (entry '= "") && $ISOBJECT(cat) && $ISOBJECT(cat.%Get("matches")) {
        Set mi = cat.%Get("matches").%GetIterator()
        While mi.%GetNext(, .m) { If $CLASSMETHOD(json, "Str", m, "id") = entry Set own = 1 }
    }
    If own Set plan."catalogue_entry" = entry, plan.outcome = outcome
    Set verdicts = $CLASSMETHOD(json, "Parse", lead.VerdictsJSON, .vsc), words = ""
    If $ISOBJECT(verdicts) {
        Set vi = verdicts.%GetIterator()
        While vi.%GetNext(, .v) {
            Set words = words _ $SELECT(words = "": "", 1: ", ") _ $CLASSMETHOD(json, "Str", v, "memberCode") _ " " _ $CLASSMETHOD(json, "Str", v, "disposition") _ $SELECT($CLASSMETHOD(json, "Str", v, "confidence") '= "": " (" _ $CLASSMETHOD(json, "Str", v, "confidence") _ ")", 1: "")
        }
    }
    Set window = ##class(Shutter.Store.BoardLead).WindowSeconds()
    Set plan.summary = "Follows the board of case " _ lead.LeaderCaseId _ " (the same failure signature within " _ window _ " s): " _ disposition _ $SELECT(actionType '= "none": " the operation unchanged at receiver version " _ version _ " unless the gate objects", 1: ", a person decides")
    Set plan.why = "The board convened for case " _ lead.LeaderCaseId _ " decided " _ disposition _ $SELECT(words '= "": "; its members: " _ words, 1: "") _ ". This case shares the receiver, the failure, the receiver's answer, the error and the catalogue match, so the decision is taken without another board; this case's own evidence, gate, rehearsal and approval still apply"
    Set plan.preconditions = [], plan."evidence_refs" = [], plan.disagreements = []
    Do lead.Followed()
    Do case.Note("note", "Board not convened: the decision of case " _ lead.LeaderCaseId _ "'s board is taken (" _ disposition _ "); " _ lead.Followers _ " case(s) have followed that board", "system", "lead:" _ lead.%Id())
    Quit ..AdoptPlan(case, plan, "lead:" _ lead.LeaderCaseId)
}

/// The leader's board ended, with a plan or without: the lead is finished for its signature and every follower still
/// waiting is told (Shutter.Msg.LeadReady to this item), so each carries on at once.
Method LeadFinish(case As Shutter.Store.Case, state As %String, plan As %DynamicObject = "", reason As %String = "")
{
    Quit:(..LeadSignature = "")
    Set lead = ##class(Shutter.Store.BoardLead).Finish(case.CaseId, state, plan, ##class(Shutter.Store.BoardLead).VerdictsOf(case.CurrentSnapshot), reason)
    Set ..LeadSignature = ""
    Quit:'$ISOBJECT(lead)
    Set n = ..TellFollowers(case.CaseId, lead)
    If n > 0 Do case.Note("note", "This case's board led its failure signature: " _ n _ " waiting case(s) told that it " _ $SELECT(lead.State = "done": "decided", 1: "decided nothing"), "system", "lead:" _ lead.%Id())
}

/// Every case still waiting on a leader's lead is told that it ended (Shutter.Msg.LeadReady to this item), so each
/// carries on at once: with the leader's decision when the lead is done, on the rules path when it failed. The followers
/// are found by the leader's case id, so a fresh instance that never knew the lead (an abandon, a close by hand) can tell
/// them too. Returns how many were told.
Method TellFollowers(leaderCaseId As %String, lead As Shutter.Store.BoardLead) As %Integer
{
    Set followers = ##class(Shutter.Store.BoardLead).FollowersOf(leaderCaseId), n = 0
    Set it = followers.%GetIterator()
    While it.%GetNext(, .fid) {
        Set msg = ##class(Shutter.Msg.LeadReady).%New()
        Set msg.CaseId = fid, msg.LeaderCaseId = leaderCaseId, msg.Signature = lead.Signature, msg.Outcome = lead.State
        Set sc = ..SendRequestAsync(..%ConfigName, msg, 0, "lead:" _ fid)
        If $$$ISOK(sc) Set n = n + 1
    }
    Quit n
}

/// A case closed by a person while it led a board (abandoned, or handled by hand): the lead is finished as failed with
/// the reason and the cases following it are told (TellFollowers), so none waits out the bound for a board that will
/// never end. A lead already ended, or none, changes nothing.
Method LeadLeftBehind(case As Shutter.Store.Case, reason As %String)
{
    Set lead = ##class(Shutter.Store.BoardLead).ForLeader(case.CaseId)
    Quit:'$ISOBJECT(lead)
    Quit:(lead.State '= "running")
    Set lead = ##class(Shutter.Store.BoardLead).Finish(case.CaseId, "failed", "", ##class(Shutter.Store.BoardLead).VerdictsOf(case.CurrentSnapshot), reason)
    Quit:'$ISOBJECT(lead)
    Set n = ..TellFollowers(case.CaseId, lead)
    If n > 0 Do case.Note("note", "This case led its failure signature's board when it was closed: " _ n _ " waiting case(s) told that it decided nothing", "system", "lead:" _ lead.%Id())
}

/// The board convened on the evidence (6.6): a request to every member of the mode's board, the pending list kept for the
/// answers, one slot of the minute taken. Under the per-minute cap (v1.35, BoardsPerMinute; 0 for none) a case that finds
/// the minute full waits for a slot instead: a note says so, an alarm keyed by the round brings it back (OnBoardDefer), and
/// convened is 0 (DeferredBy and DeferredMode say who asked and with which members). With no member to convene the rules
/// path takes over (RulesOnly), convened 0 too. The slot is taken only once every member's request is built.
Method ConveneBoard(case As Shutter.Store.Case, summaryJSON As %String, byWhom As %String = "", mode As %String = "", Output convened As %Boolean) As %Status
{
    Set convened = 0, sc = $$$OK
    // The members: the case's mode by default (policy convenes the full board); the policy path asks for "board" whatever
    // the case's mode, as it did before the cap.
    If mode = "" Set mode = $SELECT(..Mode = "policy": "board", 1: ..Mode)
    Set members = ##class(Shutter.Store.BoardMember).MembersForMode(mode)
    If members.%Size() = 0 Quit ..RulesOnly(case)
    // Every request first: the model view may refuse, and no slot is spent on a board that never convenes.
    Set n = 0
    Set iter = members.%GetIterator()
    While iter.%GetNext(.i, .code) {
        Set m = ##class(Shutter.Store.BoardMember).ByCode(code)
        Continue:'$ISOBJECT(m)
        Set req = ..AgentRequestFor(case, m, summaryJSON, "", .sc)
        If '$ISOBJECT(req) Set refused = sc Quit
        Set n = n + 1, reqs(n) = req, items(n) = m.ConfigItem, codes(n) = code
    }
    If $DATA(refused) Quit ..ModelViewFailed(case, refused)
    If n = 0 Quit ..RulesOnly(case)
    // The minute's slot, taken atomically (TryTake): a case that finds the minute full waits for the next one instead.
    If '##class(Shutter.Util.BoardSlots).TryTake(..BoardsPerMinute, .count) {
        Set wait = 60 + $RANDOM(30)
        Set ..DeferredBy = byWhom, ..DeferredMode = mode
        Do case.Note("note", "The board is busy: " _ count _ " convened this minute, the cap is " _ ..BoardsPerMinute _ " a minute; this case waits " _ wait _ " s for a slot", "system")
        Set alarm = ##class(Ens.AlarmRequest).%New()
        Set alarm.Timeout = wait
        Quit ..SendRequestAsync("Ens.Alarm", alarm, 1, "board:defer:" _ ..Round, "Waiting for a board slot")
    }
    Set pending = []
    For k = 1:1:n {
        Set sc = ..SendRequestAsync(items(k), reqs(k), 1, "member:" _ codes(k))
        Quit:$$$ISERR(sc)
        Do pending.%Push(codes(k))
    }
    Quit:$$$ISERR(sc) sc
    Set ..PendingJSON = pending.%ToJSON(), convened = 1
    Do case.Note("note", "Board convened" _ $SELECT(byWhom '= "": " by " _ byWhom, 1: "") _ ": " _ $REPLACE($REPLACE(pending.%ToJSON(), "[", ""), "]", ""), $SELECT(..ForceBoard && (..ConvenedBy '= ""): ..ConvenedBy, 1: "system"))
    Quit $$$OK
}

/// After the board is convened: the audit of free text that left IRIS, and the board's timeout armed.
Method AfterConvene(case As Shutter.Store.Case, summaryJSON As %String) As %Status
{
    // The audit trail says when free text left IRIS under the site's switch (T27).
    If ##class(Shutter.Store.SiteProfile).ModelFreeText() {
        Set sm = ##class(Shutter.Util.Json).Parse(summaryJSON, .psc), notesN = 0
        If $ISOBJECT(sm) && $ISOBJECT(sm.%Get("message")) && $ISOBJECT(sm.%Get("message").%Get("notes")) Set notesN = sm.%Get("message").%Get("notes").%Size()
        If notesN > 0 Do case.Note("note", "The free text of " _ notesN _ " note(s) is sent to the board, as the site profile (version " _ ##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0) _ ") allows", "system")
    }
    Quit ..ArmTimeout("board:timeout")
}

/// A board slot came round for a deferred case (v1.35): convene now on the snapshot's summary, unless the case has moved on
/// or the round has changed; a case with no summary to convene on goes to a person.
Method OnBoardDefer(case As Shutter.Store.Case, round As %Integer) As %Status
{
    If round '= ..Round { $$$TRACE("A board slot from round " _ round _ "; the case is in round " _ ..Round) Quit $$$OK }
    If case.State '= "investigating" { $$$TRACE("A board slot came; the case is " _ case.State _ ", so nothing is due") Quit $$$OK }
    Set summaryJSON = $SELECT($ISOBJECT(case.CurrentSnapshot): case.CurrentSnapshot.Summary, 1: "")
    If summaryJSON = "" {
        Do ..LeadFinish(case, "failed", "", "the leader had no evidence summary to convene the board on")
        Quit case.Transition("escalated", "A board slot came, but the case has no evidence summary to convene the board on; a person must look", "system")
    }
    Set sc = ..ConveneBoard(case, summaryJSON, ..DeferredBy, ..DeferredMode, .convened)
    Quit:($$$ISERR(sc) || 'convened) sc
    Quit ..AfterConvene(case, summaryJSON)
}

/// The request the case workflow sends a board member, built from the case, its current snapshot's summary,
/// the specialists' findings (for the coordinator) and the re-plan round. A class method, so a test can
/// build the same request outside the production. "" when the model view cannot be built (sc says why): then nothing
/// of the case leaves IRIS.
ClassMethod BuildAgentRequest(case As Shutter.Store.Case, m As Shutter.Store.BoardMember, summaryJSON As %String, findingsJSON As %String, replans As %Integer = 0, Output sc As %Status) As Shutter.Bridge.Msg.AgentRequest
{
    Set sc = $$$OK
    Set req = ##class(Shutter.Bridge.Msg.AgentRequest).%New()
    Set req.Role = m.Role, req.MemberCode = m.Code, req.AgentClass = m.AgentClass
    Set req.CorrelationKey = case.CaseId
    Set snap = case.CurrentSnapshot
    If $ISOBJECT(snap) Set req.SnapshotDigest = snap.Digest
    Set req.TerminalTool = m.TerminalTool
    Set req.ResultClass = $SELECT($ZCONVERT(m.TerminalTool, "L") [ "plan": "Shutter.Schema.Plan", 1: "Shutter.Schema.Findings")
    Set req.ConfigVersion = m.ConfigVersion
    // The key names the case within its scenario (several cases can share one); the replay runner also looks up
    // the older form without the encounter and event. A case at a receiver other than the production's default names it
    // too (v1.34): two receivers' cases of one movement (S22) record and replay apart, and the earlier recordings, all at
    // the default receiver, keep their keys.
    If case.Scenario '= "" Set req.RecordKey = "scenario:" _ case.Scenario _ ":" _ case.EncounterId _ ":" _ case.Event _ $SELECT((case.Receiver '= "") && (case.Receiver '= $PARAMETER("Shutter.Production", "RECEIVER")): ":" _ case.Receiver, 1: "") _ "|" _ m.Code _ "|" _ m.ConfigVersion _ $SELECT(replans > 0: "|round" _ (replans + 1), 1: "")
    // Only what is needed leaves IRIS (T27): the evidence and the findings pass through the model view, which drops
    // the demographics and the free text and replaces the case's identifiers by its tokens.
    Set context = {}
    Set context."case_id" = case.CaseId
    Set evidence = ##class(%DynamicObject).%FromJSON(summaryJSON)
    // The map of the case's identifiers is made here, once per case and in one job, in a canonical order.
    Set sc = ##class(Shutter.Util.ModelView).Learn(case, evidence)
    If $$$ISERR(sc) Quit ""
    // Reduce fails closed with an object of the one key error, which the evidence never has at its top and the
    // findings array never is: then no request, and the status carries its text (ModelViewFailed escalates the case).
    Set reduced = ##class(Shutter.Util.ModelView).Reduce(case, evidence)
    If reduced.%IsA("%Library.DynamicObject") && (reduced.%Size() = 1) && reduced.%IsDefined("error") && 'evidence.%IsDefined("error") {
        Set sc = $$$ERROR($$$GeneralError, reduced.%Get("error"))
        Quit ""
    }
    Set context.evidence = reduced
    If findingsJSON '= "" {
        Set reduced = ##class(Shutter.Util.ModelView).Reduce(case, ##class(%DynamicArray).%FromJSON(findingsJSON))
        If reduced.%IsA("%Library.DynamicObject") {
            Set sc = $$$ERROR($$$GeneralError, ##class(Shutter.Util.Json).Str(reduced, "error", "The findings could not be reduced to the model's view"))
            Quit ""
        }
        Set context.findings = reduced
    }
    Set req.Context = context.%ToJSON()
    If m.Role = "coordinator" {
        Set req.Goal = "Read the specialists' findings and the evidence for case " _ case.CaseId _ ". Keep every disagreement. Propose exactly one plan with the recovery playbooks, and submit it with SubmitPlan."
    } ElseIf m.Role = "generalist" {
        Set req.Goal = "Investigate case " _ case.CaseId _ " from every angle: conformance, the encounter's integrity, downstream impact. Propose exactly one plan and submit it with SubmitPlan."
    } Else {
        Set req.Goal = "Review case " _ case.CaseId _ " as the " _ m.Name _ " specialist: " _ m.Perspective _ " Name the evidence keys you used in evidence_refs, say what is unknown, and submit your findings with SubmitFindings."
    }
    Quit req
}

Method AgentRequestFor(case As Shutter.Store.Case, m As Shutter.Store.BoardMember, summaryJSON As %String, findingsJSON As %String, Output sc As %Status) As Shutter.Bridge.Msg.AgentRequest
{
    Set req = ..BuildAgentRequest(case, m, summaryJSON, findingsJSON, ..Replans, .sc)
    If $ISOBJECT(req) Do ..StampRequester(req)
    Quit req
}

/// Who asked, for the budget's share (v1.34, v1.39): a judge who convened the board, else the person who reopened the
/// case, else the feed itself ("system", no share); and whether the run may go live: a reopener without the live agents
/// gets recordings only (ModeOverride replay), as a question's runs do (14).
Method StampRequester(req As Shutter.Bridge.Msg.AgentRequest)
{
    Do ..Stamp(req, ..ForceBoard, ..ConvenedBy, ..ReopenedBy, ..LiveAllowed)
}

/// The rule itself, a class method so a test can apply it without a running process.
ClassMethod Stamp(req As Shutter.Bridge.Msg.AgentRequest, forceBoard As %Boolean = 0, convenedBy As %String = "", reopenedBy As %String = "", liveAllowed As %Boolean = 1)
{
    Set req.RequestedBy = $SELECT(forceBoard && (convenedBy '= ""): convenedBy, reopenedBy '= "": reopenedBy, 1: "system")
    If 'liveAllowed Set req.ModeOverride = "replay"
}

/// The model view of the case could not be built (Shutter.Util.ModelView.Learn): nothing was sent to a model, and a
/// person looks.
Method ModelViewFailed(case As Shutter.Store.Case, sc As %Status) As %Status
{
    Do ..LeadFinish(case, "failed", "", "the model view refused the evidence")
    Quit case.Transition("escalated", "The model's view of the case could not be built (" _ $EXTRACT($SYSTEM.Status.GetErrorText(sc), 1, 400) _ "), so nothing was sent to a model; a person must look", "system")
}

Method OnMember(case As Shutter.Store.Case, code As %String, result As Shutter.Bridge.Msg.AgentResponse) As %Status
{
    Set m = ##class(Shutter.Store.BoardMember).ByCode(code)
    Set sc = ##class(Shutter.Store.AgentRun).FromResponse(case, case.CurrentSnapshot, $SELECT($ISOBJECT(m): m.Role, 1: ""), code, result, ..HeaderIdOf(..%LastCallRequest), .run)
    Quit:$$$ISERR(sc) sc
    // An answer after the board's time was up is recorded for its cost and changes nothing: no finding, no plan.
    Set pending = ##class(%DynamicArray).%FromJSON(..PendingJSON), was = 0
    Set iter = pending.%GetIterator()
    While iter.%GetNext(.i, .c) { If c = code Set was = 1 }
    If 'was {
        Do case.Note("note", $SELECT($ISOBJECT(m): m.Name, 1: code) _ " answered after the board's time was up; the answer is recorded and not used", "system", "run:" _ run.%Id())
        Quit $$$OK
    }
    // An answer about an earlier snapshot (the member timed out in the round before and was asked again) is late too.
    If ..StaleAnswer(case) {
        Do case.Note("note", $SELECT($ISOBJECT(m): m.Name, 1: code) _ " answered about an earlier snapshot; the answer is recorded and not used", "system", "run:" _ run.%Id())
        Quit $$$OK
    }
    Set usable = (result.Status = "ok") && (result.ResultJSON '= "")
    Set findings = ""
    If usable {
        // The model spoke in the case's tokens; what is stored and shown carries the identifiers again (T27).
        Set restored = ##class(Shutter.Util.ModelView).Restore(case, result.ResultJSON)
        Set left = ##class(Shutter.Util.ModelView).Unresolved(restored)
        If left '= "" Do case.Note("error", $SELECT($ISOBJECT(m): m.Name, 1: code) _ " names tokens the case has no value for (" _ left _ "); they stay as written", "system", "run:" _ run.%Id())
        Set findings = ##class(Shutter.Util.Json).Parse(restored, .psc)
        If '$ISOBJECT(findings) || $$$ISERR(psc) Set usable = 0
    }
    If usable {
        If $ISOBJECT(m) && (m.Role = "generalist") {
            // The single investigator proposes the plan itself.
            Set ..PendingJSON = "[]"
            Quit ..AdoptPlan(case, findings, "run:" _ run.%Id())
        }
        Set sc = ##class(Shutter.Store.Finding).Create(run, findings, .finding)
        Quit:$$$ISERR(sc) sc
        Do case.Note("artifact", $SELECT($ISOBJECT(m): m.Name, 1: code) _ ": " _ ##class(Shutter.Util.Json).Str(findings, "disposition") _ " (" _ $EXTRACT(##class(Shutter.Util.Json).Str(findings, "summary"), 1, 300) _ ")", "agent:" _ code, "finding:" _ finding.%Id())
    } Else {
        Set failed = ##class(%DynamicArray).%FromJSON(..FailedJSON)
        Do failed.%Push(code)
        Set ..FailedJSON = failed.%ToJSON()
        Do case.Note("error", $SELECT($ISOBJECT(m): m.Name, 1: code) _ " gave no usable findings: " _ result.Status _ $SELECT(result.Error '= "": ", " _ result.Error, 1: ""), "agent:" _ code, "run:" _ run.%Id())
    }
    // Remove from the pending list.
    Set rest = []
    Set iter = pending.%GetIterator()
    While iter.%GetNext(.i, .c) { If c '= code Do rest.%Push(c) }
    Set ..PendingJSON = rest.%ToJSON()
    If rest.%Size() > 0 Quit $$$OK
    Quit ..AfterBoard(case)
}

/// Everyone answered, or the board's time is up: the coordinator takes the findings in hand, or the case is
/// escalated when there are none.
Method AfterBoard(case As Shutter.Store.Case) As %Status
{
    Set all = ##class(Shutter.Store.Finding).ForSnapshot(case.CurrentSnapshot)
    If all.%Size() = 0 {
        // In replay mode a case outside the fixtures has no recording for anyone: the rules path plans the plain
        // resend and the gate judges it, instead of an escalation that says only "no findings" (B10).
        If ..AllNoRecord(case) {
            Do case.Note("note", ..UnansweredNote(case), "system")
            Quit ..RulesOnly(case)
        }
        Do ..LeadFinish(case, "failed", "", "no board member produced usable findings")
        Quit case.Transition("escalated", "No board member produced usable findings; a person must look", "system")
    }
    Set coordinator = ##class(Shutter.Store.BoardMember).Coordinator()
    If '$ISOBJECT(coordinator) {
        Do ..LeadFinish(case, "failed", "", "no coordinator is enabled")
        Quit case.Transition("escalated", "No coordinator is enabled; the findings are on the case for a person", "system")
    }
    Set snap = case.CurrentSnapshot
    Set req = ..AgentRequestFor(case, coordinator, snap.Summary, all.%ToJSON(), .sc)
    If '$ISOBJECT(req) Quit ..ModelViewFailed(case, sc)
    Set sc = ..SendRequestAsync(coordinator.ConfigItem, req, 1, "coordinator")
    Quit:$$$ISERR(sc) sc
    Set ..CoordinatorPending = 1
    Quit ..ArmTimeout("coordinator:timeout")
}

/// A case the alert intake opened (CONTRACTS 11: FailureReasonCode "alert", the failure read from the alert's words) takes
/// the production's own report of the same failure when that arrives second and the case is still detected or
/// collecting (v1.38): the kind, text, outcome, reason code, HTTP status and Retry-After the connector answered, and the
/// headline from them. After the evidence is collected the case keeps what its snapshot was built on. Returns 1 when the
/// fields were taken.
ClassMethod TakeReport(case As Shutter.Store.Case, request As Shutter.Msg.CaseIntake) As %Boolean
{
    If '$ISOBJECT(case) || (case.FailureReasonCode '= "alert") Quit 0
    If '$LISTFIND($LISTBUILD("detected", "collecting"), case.State) Quit 0
    Set wr = ##class(Shutter.Util.Json).Parse(request.WardResultJSON, .wsc)
    If '$ISOBJECT(wr) Quit 0
    Set reason = ##class(Shutter.Util.Json).Str(wr, "reason_code")
    If (reason = "") || (reason = "alert") Quit 0
    Set case.FailureKind = request.FailureKind, case.FailureText = $EXTRACT(request.FailureText, 1, 2000)
    Set case.FailureOutcome = ##class(Shutter.Util.Json).Str(wr, "outcome"), case.FailureReasonCode = reason
    Set status = ##class(Shutter.Util.Json).Str(wr, "http_status")
    If +status > 0 Set case.FailureHttpStatus = +status
    Set retryAfter = ##class(Shutter.Util.Json).Str(wr, "retry_after_seconds")
    If +retryAfter > 0 Set case.RetryAfterUntil = ##class(Shutter.Util.Time).FromNow(+retryAfter)
    Set case.Headline = ##class(Shutter.Store.Case).DescribeFailure(case)
    Do case.Note("note", "The production's own report of the failure replaces the alert's words: " _ reason _ $SELECT(+status > 0: ", HTTP " _ +status, 1: "") _ " (" _ request.FailureKind _ ")", "system", "ens:" _ request.SourceHeaderId)
    Set sc = case.%Save()
    Quit $$$ISOK(sc)
}

/// Whether every agent run of the current snapshot ended with no recording (replay mode outside the fixtures).
Method AllNoRecord(case As Shutter.Store.Case) As %Boolean
{
    Set cid = case.%Id(), sid = $SELECT($ISOBJECT(case.CurrentSnapshot): case.CurrentSnapshot.%Id(), 1: ""), n = 0, other = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.AgentRun WHERE "Case" = :cid AND Snapshot = :sid)
    &sql(SELECT COUNT(*) INTO :other FROM Shutter_Store.AgentRun WHERE "Case" = :cid AND Snapshot = :sid AND Status <> 'no_record' AND Status <> 'budget_exhausted' AND Status <> 'provider_auth')
    Quit (+n > 0) && (+other = 0)
}

/// Why nobody on the board answered this snapshot: the day's model budget is spent (Shutter.Util.Budget, v1.34), or replay
/// mode has no recording for the case (it answers the fixtures only). Either way the rules path proposes the plain resend.
Method UnansweredNote(case As Shutter.Store.Case) As %String
{
    Set cid = case.%Id(), sid = $SELECT($ISOBJECT(case.CurrentSnapshot): case.CurrentSnapshot.%Id(), 1: ""), n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.AgentRun WHERE "Case" = :cid AND Snapshot = :sid AND Status = 'budget_exhausted')
    If +n > 0 Quit "No board member could run: the day's model budget is spent (budget_exhausted); the rules path proposes the plain resend and the gate judges it"
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.AgentRun WHERE "Case" = :cid AND Snapshot = :sid AND Status = 'provider_auth')
    If +n > 0 Quit "No board member could run: the model provider refuses the key (provider_auth); the rules path proposes the plain resend and the gate judges it"
    Quit "No board member has a recording for this case (replay mode answers the fixtures only); the rules path proposes the plain resend and the gate judges it"
}

/// Whether the call being answered was made about a snapshot other than the case's current one.
Method StaleAnswer(case As Shutter.Store.Case) As %Boolean
{
    Set req = ..%LastCallRequest
    If '$ISOBJECT(req) || 'req.%IsA("Shutter.Bridge.Msg.AgentRequest") Quit 0
    Set digest = $PROPERTY(req, "SnapshotDigest")
    If (digest = "") || '$ISOBJECT(case.CurrentSnapshot) Quit 0
    Quit digest '= case.CurrentSnapshot.Digest
}

/// A timer on a board round or on the coordinator: a member that never answers must not hang the case.
Method ArmTimeout(key As %String) As %Status
{
    If ..BoardTimeoutSeconds <= 0 Quit $$$OK
    Set alarm = ##class(Ens.AlarmRequest).%New()
    Set alarm.Timeout = ..BoardTimeoutSeconds
    Quit ..SendRequestAsync("Ens.Alarm", alarm, 1, key _ ":" _ ..Round)
}

Method OnBoardTimeout(case As Shutter.Store.Case) As %Status
{
    Set pending = ##class(%DynamicArray).%FromJSON(..PendingJSON)
    If pending.%Size() = 0 Quit $$$OK
    Set failed = ##class(%DynamicArray).%FromJSON(..FailedJSON)
    Set iter = pending.%GetIterator()
    While iter.%GetNext(.i, .code) { Do failed.%Push(code) }
    Set ..FailedJSON = failed.%ToJSON(), ..PendingJSON = "[]"
    Do case.Note("error", "The board's time is up after " _ ..BoardTimeoutSeconds _ " s; no answer from " _ $REPLACE($REPLACE(pending.%ToJSON(), "[", ""), "]", "") _ ". The findings in hand go on", "system")
    Quit ..AfterBoard(case)
}

Method OnCoordinatorTimeout(case As Shutter.Store.Case) As %Status
{
    If '..CoordinatorPending Quit $$$OK
    Set ..CoordinatorPending = 0
    Do ..LeadFinish(case, "failed", "", "the coordinator did not answer")
    Quit case.Transition("escalated", "The coordinator did not answer within " _ ..BoardTimeoutSeconds _ " s; the findings are on the case for a person", "system")
}

Method OnCoordinator(case As Shutter.Store.Case, result As Shutter.Bridge.Msg.AgentResponse) As %Status
{
    Set sc = ##class(Shutter.Store.AgentRun).FromResponse(case, case.CurrentSnapshot, "coordinator", "coordinator", result, ..HeaderIdOf(..%LastCallRequest), .run)
    Quit:$$$ISERR(sc) sc
    // A plan about an earlier snapshot (the coordinator of the round before) is recorded and changes nothing.
    If ..StaleAnswer(case) {
        Do case.Note("note", "The coordinator answered about an earlier snapshot; the answer is recorded and not used", "system", "run:" _ run.%Id())
        Quit $$$OK
    }
    Set ..CoordinatorPending = 0
    If (result.Status '= "ok") || (result.ResultJSON = "") {
        Do ..LeadFinish(case, "failed", "", "the coordinator produced no plan (" _ result.Status _ ")")
        Quit case.Transition("escalated", "The coordinator produced no plan: " _ result.Status _ $SELECT(result.Error '= "": ", " _ result.Error, 1: ""), "system", "run:" _ run.%Id())
    }
    Set restored = ##class(Shutter.Util.ModelView).Restore(case, result.ResultJSON)
    Set left = ##class(Shutter.Util.ModelView).Unresolved(restored)
    If left '= "" Do case.Note("error", "The coordinator names tokens the case has no value for (" _ left _ "); they stay as written", "system", "run:" _ run.%Id())
    Set plan = ##class(Shutter.Util.Json).Parse(restored, .psc)
    If '$ISOBJECT(plan) || $$$ISERR(psc) {
        Do ..LeadFinish(case, "failed", "", "the coordinator's plan is not valid JSON")
        Quit case.Transition("escalated", "The coordinator's plan is not valid JSON", "system", "run:" _ run.%Id())
    }
    Do ..AttachCorrectionSteps(case, plan)
    Quit ..AdoptPlan(case, plan, "run:" _ run.%Id())
}

/// The board's plan at a receiver that keeps the history of record (CONTRACTS 6.4, v1.23; here since v1.34): when the
/// catalogue outcome the coordinator chose is correct_history, the correcting steps join the plan as the site-policy path
/// puts them, so the escalation draft has its correcting section whichever path planned. The outcome is read from the
/// snapshot's catalogue match the plan names (preferred, or the alternative the plan's outcome points at); a plan that
/// already carries steps, or names no entry, is left alone. Deterministic, so a replay carries the same steps.
Method AttachCorrectionSteps(case As Shutter.Store.Case, plan As %DynamicObject)
{
    Try {
        Quit:(##class(Shutter.Util.Json).Str(plan, "disposition") '= "escalate")
        Quit:plan.%IsDefined("correction_steps")
        Set entry = ##class(Shutter.Util.Json).Str(plan, "catalogue_entry"), ref = ##class(Shutter.Util.Json).Str(plan, "outcome", "preferred")
        Quit:(entry = "")
        Set summary = $SELECT($ISOBJECT(case.CurrentSnapshot): case.CurrentSnapshot.SummaryObject(), 1: "")
        Quit:'$ISOBJECT(summary)
        Set cat = summary.%Get("catalogue"), matches = $SELECT($ISOBJECT(cat): cat.%Get("matches"), 1: "")
        Quit:'$ISOBJECT(matches)
        Set chosen = "", mi = matches.%GetIterator()
        While mi.%GetNext(, .m) {
            Continue:(##class(Shutter.Util.Json).Str(m, "id") '= entry)
            Set chosen = m.%Get("preferred")
            If $EXTRACT(ref, 1, 12) = "alternative:" {
                Set alts = m.%Get("alternatives"), n = +$PIECE(ref, ":", 2)
                If $ISOBJECT(alts) && (n >= 1) && (n <= alts.%Size()) Set chosen = alts.%Get(n - 1)
            }
        }
        Quit:'$ISOBJECT(chosen)
        Quit:(##class(Shutter.Util.Json).Str(chosen, "outcome") '= "correct_history")
        Set steps = ##class(Shutter.Util.HistoryCorrection).Steps(case, summary)
        Set plan."correction_steps" = steps
        Do case.Note("artifact", "Correcting the history: " _ ##class(Shutter.Util.HistoryCorrection).Headline(steps), "system")
    } Catch ex {
        Do case.Note("error", "The correcting steps could not be attached to the board's plan: " _ ex.DisplayString(), "system")
    }
}

/// Rules-only mode: the plan is a resend of the case's own operation at the observed version,
/// and the gate alone decides.
/// The policy path: one catalogue entry matched and decides by policy. The plan follows the entry's preferred
/// outcome; the site profile's policy for the receiver's tier and the chain kind says whether it is released
/// automatically (no Workflow task; still gated, rehearsed and verified) or after an approval. A policy of board
/// sends the case to the board after all.
Method PolicyPath(case As Shutter.Store.Case, summary As %DynamicObject, cat As %DynamicObject) As %Status
{
    Set json = "Shutter.Util.Json"
    Set entry = $CLASSMETHOD(json, "Str", cat, "entry"), outcome = $CLASSMETHOD(json, "Str", cat, "outcome")
    // An item released under the incident's approval was approved as one entry and outcome (7.3, 7.4): fresh evidence
    // that reads otherwise is not covered, so nothing is planned under that approval and the chain stops here. The
    // dispatch gate checks the same binding on the approval record (Shutter.Store.Approval.InvalidReason).
    If ..Release && (..ReleasePolicy = "incident") && ((entry '= ..IncidentEntry) || (outcome '= ..IncidentOutcome)) {
        Set case.Headline = "Not covered by the incident's approval: fresh evidence matches " _ entry _ " " _ outcome _ ", the approval bound " _ ..IncidentEntry _ " " _ ..IncidentOutcome
        Quit case.Transition("blocked", "Not covered by the approval of incident " _ ..IncidentId _ ": chain " _ ..ChainSeq _ " item " _ ..ChainPosition _ " was approved as " _ ..IncidentEntry _ " (" _ ..IncidentOutcome _ "), but its fresh evidence matches " _ entry _ " (" _ outcome _ "); nothing was dispatched, and a person must look", "system", "incident:" _ ..IncidentId)
    }
    Set tier = ##class(Shutter.Store.SiteProfile).TierOf($SELECT(case.Receiver '= "": case.Receiver, 1: ..WardTarget))
    Set kind = $SELECT(..Release: ..ChainKind, 1: $CLASSMETHOD(json, "Str", cat.%Get("conditions"), "chain", "single"))
    Set ..Policy = ##class(Shutter.Store.SiteProfile).Policy(tier, kind)
    // A released item is authorised by its incident (7.3): by site policy, or under the incident's approval.
    If ..Release Set ..Policy = $SELECT(..ReleasePolicy = "incident": "incident", ..ReleasePolicy = "automatic": "automatic", 1: ..Policy)
    // The outcome the matcher settled on: the preferred one, or a site-policy alternative whose when holds for the case's
    // receiver (CONTRACTS 6.3, v1.25); the plan names it as the board would.
    Set ref = $CLASSMETHOD(json, "Str", cat, "outcome_ref", "preferred")
    Set ..CatalogueEntry = entry, ..CatalogueOutcome = ref
    Set m = cat.%Get("matches").%Get(0)
    Set chosen = m.%Get("preferred")
    If $EXTRACT(ref, 1, 12) = "alternative:" {
        Set alts = m.%Get("alternatives"), n = +$PIECE(ref, ":", 2)
        If $ISOBJECT(alts) && (n >= 1) && (n <= alts.%Size()) Set chosen = alts.%Get(n - 1)
    }
    Set title = $CLASSMETHOD(json, "Str", m, "title"), why = $CLASSMETHOD(json, "Str", chosen, "why")
    Set profile = ##class(Shutter.Store.SiteProfile).Current()
    Do case.Note("note", "Catalogue " _ entry _ " (" _ title _ ") matched alone: " _ outcome _ ". Site policy for tier " _ tier _ ", " _ kind _ ": " _ ..Policy _ " (profile v" _ $CLASSMETHOD(json, "Str", profile, "version", 0) _ ")", "system")
    If (..Policy = "board") || ..ForceBoard {
        // A forced board's plan is a board's plan (v1.39): a person approves it, and the site policy the entry would have
        // had (automatic on this tier, say) does not release it, which the dispatch gate would then block as plan_origin;
        // the entry and outcome stay for the notes.
        If ..ForceBoard Set ..Policy = ""
        Set sc = ..ConveneBoard(case, summary.%ToJSON(), $SELECT(..ForceBoard: ..ConvenedBy, 1: "site policy"), "board", .convened)
        Quit:($$$ISERR(sc) || 'convened) sc
        Quit ..AfterConvene(case, summary.%ToJSON())
    }
    Set ward = summary.%Get("ward_state")
    Set version = $SELECT($ISOBJECT(ward): $CLASSMETHOD(json, "Str", ward, "version", 0), 1: 0)
    Set plan = {}
    Set plan."catalogue_entry" = entry, plan.outcome = ref, plan.why = why
    Set plan."evidence_refs" = ["catalogue", "ward_state", "receipt", "timeline", "route"], plan.disagreements = []
    Set action = {}
    If (outcome = "resend") || (outcome = "resend_chain") || (outcome = "resend_latest") {
        Set plan.disposition = "resend"
        Set action.type = "resend", action."operation_key" = case.OperationKey, action."expected_version" = +version
        Set action."payload_digest" = $CLASSMETHOD(json, "Str", summary.%Get("operation"), "payload_digest")
        Set plan.preconditions = [("The receiver's version is still " _ version _ " at dispatch"), "No later event for the encounter before dispatch"]
        Set plan.summary = "Catalogue " _ entry _ ", " _ title _ ": resend the operation unchanged at receiver version " _ version _ ", by site policy (" _ ..Policy _ ")"
    } ElseIf outcome = "resend_after_occupant" {
        // The destination bed is held by a patient who is leaving (v1.28): a resend that waits for their movement's case,
        // which the gate holds with WAITING_FOR_OCCUPANT_CASE until that case closes.
        Set occCase = $CLASSMETHOD(json, "Str", cat.%Get("facts"), "occupant_case")
        Set plan.disposition = "resend"
        Set action.type = "resend", action."operation_key" = case.OperationKey, action."expected_version" = +version
        Set action."payload_digest" = $CLASSMETHOD(json, "Str", summary.%Get("operation"), "payload_digest")
        If occCase '= "" Set plan."waits_on" = occCase
        Set plan.preconditions = [("The receiver's version is still " _ version _ " at dispatch"), "No later event for the encounter before dispatch", ("The bed's occupant has left" _ $SELECT(occCase '= "": ": case " _ occCase _ " about their movement has resolved", 1: ""))]
        Set plan.summary = "Catalogue " _ entry _ ", " _ title _ ": resend the operation unchanged once the bed's occupant has left" _ $SELECT(occCase '= "": " (case " _ occCase _ ")", 1: "") _ ", at receiver version " _ version _ ", by site policy (" _ ..Policy _ ")"
    } ElseIf outcome = "reconcile" {
        Set plan.disposition = "reconcile"
        Set action.type = "reconcile", action."operation_key" = case.OperationKey
        Set plan.preconditions = [], plan.summary = "Catalogue " _ entry _ ", " _ title _ ": the receiver holds a receipt; reconcile, nothing is sent"
    } ElseIf outcome = "none" {
        Set plan.disposition = "superseded"
        Set action.type = "none"
        Set plan.preconditions = [], plan.summary = "Catalogue " _ entry _ ", " _ title _ ": nothing is sent"
    } ElseIf outcome = "correct_history" {
        // The receiver keeps the history of record (v1.23): the overtaken movement is not left out, and Shutter does not
        // write it (a resend would move the patient back), so the case escalates with the correcting steps on its plan.
        Set plan.disposition = "escalate"
        Set action.type = "none"
        Set steps = ##class(Shutter.Util.HistoryCorrection).Steps(case, summary)
        Set plan."correction_steps" = steps
        Set plan.preconditions = [], plan.summary = "Catalogue " _ entry _ ", " _ title _ ": the receiver keeps the history of record, so the missing movement is corrected by its team; the steps are on the plan"
        Do case.Note("artifact", "Correcting the history: " _ ##class(Shutter.Util.HistoryCorrection).Headline(steps), "system")
    } Else {
        Set plan.disposition = "escalate"
        Set action.type = "none"
        Set plan.preconditions = [], plan.summary = "Catalogue " _ entry _ ", " _ title _ ": " _ outcome _ " needs a person"
    }
    Set plan.action = action
    Quit ..AdoptPlan(case, plan, "policy:" _ entry)
}

/// The receiver's category is orders_results (v1.23): an escalate plan naming the reason, through the gate (which blocks
/// any write to such a receiver with RECEIVER_NOT_MODELLED), to escalated; no board and no investigator.
/// A gate that did not pass because the destination bed is held (v1.28): with WAITING_FOR_OCCUPANT_CASE the case blocks
/// waiting on the occupant's case (WaitsOnCase, released by Shutter.Store.Case when that case closes); with
/// OCCUPANT_CASE_FAILED it escalates at once, since the bed will not free itself. waited says whether either applied.
Method BedWaitOutcome(case As Shutter.Store.Case, result As Shutter.Msg.GateResult, Output waited As %Boolean) As %Status
{
    Set waited = 0
    Set code = ""
    Set checks = ##class(Shutter.Util.Json).Parse(result.ChecksJSON, .psc)
    If $ISOBJECT(checks) && checks.%IsA("%Library.DynamicArray") {
        Set ci = checks.%GetIterator()
        While ci.%GetNext(, .c) {
            Continue:'$ISOBJECT(c)
            Set rc = ##class(Shutter.Util.Json).Str(c, "reason_code")
            If (rc = "WAITING_FOR_OCCUPANT_CASE") || (rc = "OCCUPANT_CASE_FAILED") || (rc = "NEWER_MESSAGE_PENDING") Set code = rc Quit
        }
    }
    If code = "" Quit $$$OK
    Set waited = 1
    Set other = "", where = ""
    Set snap = case.CurrentSnapshot
    If $ISOBJECT(snap) {
        Set bc = snap.SummaryObject().%Get("bed_conflict")
        If $ISOBJECT(bc) {
            Set mv = bc.%Get("occupant_movement")
            If $ISOBJECT(mv) Set other = ##class(Shutter.Util.Json).Str(mv, "case_id")
            Set where = ##class(Shutter.Util.Json).Str(bc, "ward") _ $SELECT(##class(Shutter.Util.Json).Str(bc, "bed") '= "": " bed " _ ##class(Shutter.Util.Json).Str(bc, "bed"), 1: "")
        }
    }
    If code = "NEWER_MESSAGE_PENDING" {
        // The resend waits for a newer message of the encounter that is pending in Shutter (v1.29); its delivery reopens the case.
        Set pendingMsgs = $SELECT($ISOBJECT(snap): snap.SummaryObject().%Get("pending_messages"), 1: "")
        Set control = $SELECT($ISOBJECT(pendingMsgs) && (pendingMsgs.%Size() > 0): ##class(Shutter.Util.Json).Str(pendingMsgs.%Get(0), "control_id"), 1: "")
        Set case.WaitsOnMessage = control
        Set case.Headline = "Waiting for a newer message of the encounter to be delivered" _ $SELECT(control '= "": " (" _ control _ ")", 1: "")
        Quit case.Transition("blocked", "A newer message of this encounter is pending in Shutter" _ $SELECT($ISOBJECT(pendingMsgs) && (pendingMsgs.%Size() > 0): ": " _ ##class(Shutter.Util.ResendGuard).Describe(pendingMsgs), 1: "") _ ". Nothing was dispatched; the case is checked again on fresh evidence once it has been delivered", "gate", "gate:" _ result.DecisionId)
    }
    If code = "WAITING_FOR_OCCUPANT_CASE" {
        Set case.WaitsOnCase = other
        Set case.Headline = "Waiting for the occupant of " _ where _ " to leave" _ $SELECT(other '= "": " (case " _ other _ ")", 1: "")
        Quit case.Transition("blocked", "The destination bed " _ where _ " is held by a patient who is leaving: " _ $SELECT(other '= "": "case " _ other _ " is about their movement, and this case is checked again when it closes", 1: "their movement's delivery has no answer yet; reinvestigate once it has") _ ". Nothing was dispatched", "gate", "gate:" _ result.DecisionId)
    }
    // The wait stays on the escalated case too, so that the awaited case closing later (resolved by hand, say) releases it.
    Set case.WaitsOnCase = other
    Set case.Headline = "The occupant of " _ where _ " did not leave: a person decides"
    Quit case.Transition("escalated", "The destination bed " _ where _ " is still held" _ $SELECT(other '= "": ", and case " _ other _ " about the occupant's movement ended without freeing it", 1: "") _ "; a person decides, with the bed manager. Nothing was dispatched", "gate", "gate:" _ result.DecisionId)
}

Method NotModelledToPerson(case As Shutter.Store.Case) As %Status
{
    Set ..Policy = "person", ..CatalogueEntry = "", ..CatalogueOutcome = ""
    Do case.Note("note", "The receiver's category is orders_results: order communications and results are not modelled yet, so a person handles the failure", "system")
    Set plan = {}
    Set plan.disposition = "escalate", plan.action = {"type": "none"}
    Set plan.why = "Not modelled yet: the receiver keeps orders and results, which Shutter's ADT catalogue does not cover"
    Set plan.summary = "Receiver category orders_results: not modelled yet, a person handles the failure"
    Set plan.preconditions = [], plan."evidence_refs" = ["route"], plan.disagreements = []
    Quit ..AdoptPlan(case, plan, "policy:not_modelled")
}

/// The connector a case's reads, rehearsals and writes go to (v1.25): the case's receiver when the site profile names it
/// as a receiver (a connector of this production, by the profile's rule), else this item's WardTarget setting.
Method WardTargetFor(case As Shutter.Store.Case) As %String
{
    If (case.Receiver '= "") && $ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver(case.Receiver)) Quit case.Receiver
    Quit ..WardTarget
}

/// One entry matched and it decides by a person: an escalate plan naming it, through the gate, to escalated.
Method PersonByCatalogue(case As Shutter.Store.Case, cat As %DynamicObject) As %Status
{
    Set json = "Shutter.Util.Json"
    Set entry = $CLASSMETHOD(json, "Str", cat, "entry")
    Set m = cat.%Get("matches").%Get(0)
    Set title = $CLASSMETHOD(json, "Str", m, "title"), why = $CLASSMETHOD(json, "Str", m.%Get("preferred"), "why")
    Set ..CatalogueEntry = entry, ..CatalogueOutcome = "preferred", ..Policy = "person"
    Do case.Note("note", "Catalogue " _ entry _ " (" _ title _ ") matched alone and asks for a person", "system")
    Set plan = {}
    Set plan.disposition = "escalate", plan.action = {"type": "none"}
    Set plan."catalogue_entry" = entry, plan.outcome = "preferred", plan.why = why
    Set plan.summary = "Catalogue " _ entry _ ", " _ title _ ": " _ why
    Set plan.preconditions = [], plan."evidence_refs" = ["catalogue"], plan.disagreements = []
    Quit ..AdoptPlan(case, plan, "policy:" _ entry)
}

Method RulesOnly(case As Shutter.Store.Case) As %Status
{
    Set snap = case.CurrentSnapshot
    Set summary = snap.SummaryObject()
    Set ward = summary.%Get("ward_state")
    Set version = $SELECT($ISOBJECT(ward): ##class(Shutter.Util.Json).Str(ward, "version", 0), 1: 0)
    Set plan = {}
    Set plan.disposition = "resend"
    Set plan.summary = "Rules only: resend the operation unchanged at receiver version " _ version _ " unless the gate objects"
    Set action = {}
    Set action.type = "resend", action."operation_key" = case.OperationKey, action."expected_version" = +version
    Set action."payload_digest" = ##class(Shutter.Util.Json).Str(summary.%Get("operation"), "payload_digest")
    Set plan.action = action
    Set plan.preconditions = [], plan."evidence_refs" = [], plan.disagreements = []
    Do case.Note("note", "Rules-only mode: no agents consulted", "system")
    Quit ..AdoptPlan(case, plan, "rules")
}

/// Store the plan as the case's current plan and send it to the gate.
Method AdoptPlan(case As Shutter.Store.Case, plan As %DynamicObject, createdBy As %String) As %Status
{
    Set sc = ##class(Shutter.Store.Plan).Create(case, case.CurrentSnapshot, plan, createdBy, .p)
    Quit:$$$ISERR(sc) sc
    // A case that leads its failure signature (v1.35) has decided: its followers take the plan.
    Do ..LeadFinish(case, "done", plan)
    Set ..PlanId = p.%Id()
    Set case.CurrentPlan = p
    Set case.Disposition = p.Disposition
    Set case.Headline = ..HeadlineFor(case, p)
    Set sc = case.Transition("proposed", "Plan v" _ p.Version _ " (" _ p.Disposition _ "): " _ p.Summary, createdBy, "plan:" _ p.%Id())
    Quit:$$$ISERR(sc) sc
    // A case its incident adopted while the board sat parks here: the plan is on the case, the release re-plans.
    If '..Release && '..Reopened && $ISOBJECT(case.Incident) {
        Set sc = ..Park(case, .parked)
        If parked || $$$ISERR(sc) Quit sc
    }
    Quit ..SendGate(case, "proposal", "gate:proposal")
}

/// The case's headline: what the plan does, then the start of its summary, cut at a word (the whole summary is on the
/// plan).
Method HeadlineFor(case As Shutter.Store.Case, p As Shutter.Store.Plan) As %String
{
    Set what = $CASE(case.Event, "transfer": "transfer to " _ case.Ward, "admit": "admission", "discharge": "discharge", : case.Event)
    Set summary = ##class(Shutter.Util.Json).Clip(p.Summary, 200)
    Quit $CASE(p.Disposition,
        "superseded": "Valid message. Do not resend: a later event moved the encounter on. " _ summary,
        "resend": "Resend the " _ what _ " unchanged, after rehearsal and approval. " _ summary,
        "reconcile": "Already applied at the receiver: reconcile, do not resend. " _ summary,
        "escalate": "Escalated to a person. " _ summary,
        "more_evidence": "More evidence needed. " _ summary,
        : p.Disposition _ ": " _ summary)
}

Method SendGate(case As Shutter.Store.Case, stage As %String, key As %String) As %Status
{
    Set req = ##class(Shutter.Msg.GateRequest).%New()
    Set req.CaseId = case.CaseId, req.PlanId = ..PlanId, req.Stage = stage, req.Receiver = $SELECT(case.Receiver '= "": case.Receiver, 1: ..WardTarget)
    Set req.ApprovalId = ..ApprovalId, req.ChainKind = ..ChainKind
    If ..ReceiverVersion '= "" Set req.ReceiverVersion = ..ReceiverVersion
    If ..ReceiverEpoch '= "" Set req.ReceiverEpoch = ..ReceiverEpoch
    Quit ..SendRequestAsync(..GateTarget, req, 1, key)
}

// ---- the gate, rehearsal, approval, execution, verification ----

Method OnGateProposal(case As Shutter.Store.Case, result As Shutter.Msg.GateResult) As %Status
{
    Set plan = ##class(Shutter.Store.Plan).%OpenId(..PlanId)
    Set sc = case.Transition("gated", "Gate at proposal: " _ result.Outcome _ ". " _ result.Summary, "gate", "gate:" _ result.DecisionId)
    Quit:$$$ISERR(sc) sc
    // A plan that asks for a person is escalated whatever the gate found; the gate's result stays on the case.
    If (plan.Disposition = "escalate") || (plan.Disposition = "more_evidence") {
        Quit case.Transition("escalated", "The plan asks for a person: " _ plan.Summary _ $SELECT(result.Outcome '= "pass": " (the gate noted: " _ result.Summary _ ")", 1: ""), "system", "plan:" _ plan.%Id())
    }
    If result.Outcome '= "pass" {
        // An unknown pattern alone is no reason to block (CONTRACTS 6.3): a plan that writes nothing closes as usual,
        // flagged as a candidate entry; a plan that writes is escalated to a person with the flag.
        If ..OnlyNewPattern(result) {
            Set case.CandidateEntry = 1
            Do case.Note("note", "The catalogue has no entry for this pattern; the case is flagged as a candidate entry for a reviewer", "gate", "gate:" _ result.DecisionId)
            If 'plan.IsWrite() {
                Set sc = case.Transition("verifying", "No write; verifying the receiver's state (new pattern, candidate entry)", "system")
                Quit:$$$ISERR(sc) sc
                Quit ..SendVerify(case)
            }
            Set case.Headline = "New pattern, a person decides: " _ ##class(Shutter.Util.Json).Clip(plan.Summary, 200)
            Quit case.Transition("escalated", "The catalogue has no entry for this pattern and the plan writes; a person decides (candidate entry)", "gate", "gate:" _ result.DecisionId)
        }
        // A lookup that failed at the proposal is not a verdict either: the evidence is collected again and the case is
        // planned afresh, up to the limit.
        If ..OnlyRefreshable(result) && (..Refreshes < ..MaxRefreshes) {
            Set ..Refreshes = ..Refreshes + 1, ..Refreshing = 0
            Set ..PlanId = "", ..PendingJSON = "[]"
            Set wait = 10 * (2 ** (..Refreshes - 1))
            Do case.Note("note", "The proposal gate could not decide (" _ result.Summary _ "); collecting the evidence again in " _ wait _ " s and planning afresh (" _ ..Refreshes _ " of " _ ..MaxRefreshes _ ")", "gate", "gate:" _ result.DecisionId)
            Set alarm = ##class(Ens.AlarmRequest).%New()
            Set alarm.Timeout = wait
            Quit ..SendRequestAsync("Ens.Alarm", alarm, 1, "refresh:retry")
        }
        Set sc = ..BedWaitOutcome(case, result, .waited)
        If waited Quit sc
        Set case.Headline = "Blocked by the gate: " _ result.Summary
        Quit case.Transition("blocked", "The gate did not pass the plan; a person must decide", "gate", "gate:" _ result.DecisionId)
    }
    If plan.IsWrite() {
        Set sc = case.Transition("rehearsing", "Rehearsing the exact action as a dry run", "system")
        Quit:$$$ISERR(sc) sc
        Quit ..SendRequestAsync(..WardTargetFor(case), ..WardOperationFor(case, plan, 1), 1, "rehearsal")
    }
    // superseded or reconcile: nothing is written; verify what the receiver holds and close.
    Set sc = case.Transition("verifying", "No write; verifying the receiver's state", "system")
    Quit:$$$ISERR(sc) sc
    Quit ..SendVerify(case)
}

/// Whether the evidence's lookups all answered: the receiver's state (200, or 404 for an admission), the receipt (200,
/// 404, or -1 for a receiver that keeps none) and the capabilities (200, or declared by the profile).
Method Complete(summary As %DynamicObject, case As Shutter.Store.Case) As %Boolean
{
    If '$ISOBJECT(summary) Quit 0
    Set json = "Shutter.Util.Json"
    Set ws = $CLASSMETHOD(json, "Str", summary, "ward_state_http_status"), rs = $CLASSMETHOD(json, "Str", summary, "receipt_http_status")
    Set route = summary.%Get("route")
    Set cs = $SELECT($ISOBJECT(route): $CLASSMETHOD(json, "Str", route, "capabilities_http_status"), 1: 200)
    If case.EncounterId = "-" Quit (cs = 200)
    If (ws '= 200) && '((ws = 404) && (case.Event = "admit")) Quit 0
    If (rs '= 200) && (rs '= 404) && (rs '= -1) Quit 0
    If cs '= 200 Quit 0
    Quit 1
}

/// Whether every check that did not pass is an unknown a fresh collection can answer: stale evidence, a receipt or
/// capabilities lookup that failed, a receiver that could not be read.
Method OnlyRefreshable(result As Shutter.Msg.GateResult) As %Boolean
{
    Set checks = ##class(Shutter.Util.Json).Parse(result.ChecksJSON, .psc)
    If '$ISOBJECT(checks) || (checks.%Size() = 0) Quit 0
    Set found = 0
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) {
        Continue:(##class(Shutter.Util.Json).Str(c, "result") = "pass")
        If ##class(Shutter.Util.Json).Str(c, "result") '= "unknown" Return 0
        If '$LISTFIND($LISTBUILD("STALE_EVIDENCE", "RECEIPT_UNREADABLE", "CAPABILITIES_UNREADABLE", "RECEIVER_UNREADABLE"), ##class(Shutter.Util.Json).Str(c, "reason_code")) Return 0
        Set found = 1
    }
    Quit found
}

/// Whether the only checks that did not pass are the catalogue's NEW_PATTERN.
Method OnlyNewPattern(result As Shutter.Msg.GateResult) As %Boolean
{
    Set checks = ##class(Shutter.Util.Json).Parse(result.ChecksJSON, .psc)
    If '$ISOBJECT(checks) || (checks.%Size() = 0) Quit 0
    Set found = 0
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) {
        Continue:(##class(Shutter.Util.Json).Str(c, "result") = "pass")
        If ##class(Shutter.Util.Json).Str(c, "reason_code") '= "NEW_PATTERN" Return 0
        Set found = 1
    }
    Quit found
}

Method WardOperationFor(case As Shutter.Store.Case, plan As Shutter.Store.Plan, dryRun As %Boolean) As Shutter.Msg.WardOperation
{
    Set snap = case.CurrentSnapshot
    Set op = snap.SummaryObject().%Get("operation")
    Set w = ##class(Shutter.Msg.WardOperation).FromOperation(op)
    Set w.Purpose = $SELECT(dryRun: "rehearsal", 1: "recovery")
    Set w.DryRun = dryRun
    Set w.ExpectedVersion = plan.ExpectedVersion
    Set w.CaseId = case.CaseId
    Set w.SourceHeaderId = case.SourceHeaderId
    Quit w
}

/// The receiver's answer to the dry run <var>sent</var>: the rehearsal is recorded with what was sent (the dispatch gate
/// checks the write against it), and the case goes on to its release or blocks.
Method OnRehearsal(case As Shutter.Store.Case, sent As Shutter.Msg.WardOperation, result As Shutter.Msg.WardResult) As %Status
{
    Set plan = ##class(Shutter.Store.Plan).%OpenId(..PlanId)
    Set sc = ##class(Shutter.Store.Rehearsal).Create(case, plan, sent, result.HttpStatus, result.ResponseObject(), .r)
    Quit:$$$ISERR(sc) sc
    // A dry run that would apply validated the expected version: that is the receiver's version now.
    If result.Outcome = "would_apply" Set ..ReceiverVersion = $SELECT(result.EncounterVersion '= "": result.EncounterVersion, 1: plan.ExpectedVersion)
    If result.Epoch '= "" Set ..ReceiverEpoch = result.Epoch
    // A receiver that applied the dry run does not honour dry_run (v1.21): the operation is in effect, so it is recorded as
    // an execution, an alert is raised and the effect is verified; it is never reported as rolled back.
    If result.IsInEffect() {
        $$$LOGALERT("Receiver " _ ..WardTargetFor(case) _ " applied a dry run of " _ sent.OperationKey _ " for " _ case.CaseId _ " (HTTP " _ result.HttpStatus _ "): it does not honour dry_run")
        Set sc = ##class(Shutter.Store.ExecutionAttempt).Create(case, plan, "", r, result.HttpStatus, result.Outcome, result.ResponseObject(), "written by the receiver during a rehearsal", .attempt)
        Quit:$$$ISERR(sc) sc
        Set ..AttemptId = attempt.%Id()
        Do case.Note("execution", "The receiver applied the rehearsal (HTTP " _ result.HttpStatus _ "): it does not honour dry_run and the operation is in effect", "system", "attempt:" _ attempt.%Id())
        Set sc = case.Transition("verifying", "The receiver applied the dry run instead of rolling it back; verifying the effect", "system", "attempt:" _ attempt.%Id())
        Quit:$$$ISERR(sc) sc
        Quit ..SendVerify(case)
    }
    Set rolledBack = (result.Outcome = "would_apply") || (result.Outcome = "would_not_apply")
    Do case.Note("artifact", "Rehearsal: " _ result.Outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "") _ $SELECT(rolledBack: ", rolled back by the receiver", 1: ""), "system", "rehearsal:" _ r.%Id())
    If result.Outcome '= "would_apply" {
        Set case.Headline = "Rehearsal failed: " _ result.Outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "")
        Quit case.Transition("blocked", "The rehearsal shows the action would not apply: " _ result.Outcome _ $SELECT(result.Error '= "": ", " _ result.Error, 1: ""), "system", "rehearsal:" _ r.%Id())
    }
    If ..Policy = "automatic" Quit ..ReleaseByPolicy(case, plan, r)
    If ..Policy = "incident" Quit ..ReleaseByIncident(case, plan, r)
    Set sc = case.Transition("awaiting_approval", "Rehearsal passed; asking an approver for the exact plan", "system", "rehearsal:" _ r.%Id())
    Quit:$$$ISERR(sc) sc
    Set sc = ..SendRequestAsync(..ApprovalTarget, ..ApprovalTask(case, plan, ..ApprovalWaitSeconds), 1, "approval")
    Quit:$$$ISERR(sc) sc
    // The wait is bounded (v1.35): an alarm keyed by the round, so one from an earlier plan is ignored.
    If ..ApprovalWaitSeconds > 0 {
        Set alarm = ##class(Ens.AlarmRequest).%New()
        Set alarm.Timeout = ..ApprovalWaitSeconds
        Set sc = ..SendRequestAsync("Ens.Alarm", alarm, 1, "approval:timeout:" _ ..Round, "The approval wait")
    }
    Quit sc
}

/// The approval task got no answer within the wait (v1.35): if the case still waits for this round's plan, the task is
/// cancelled and the case escalates, so a person sees it as work left undone rather than a request nobody noticed; a
/// decision taken meanwhile, or a later round, leaves the alarm with nothing to do.
Method OnApprovalTimeout(case As Shutter.Store.Case, round As %Integer) As %Status
{
    If round '= ..Round { $$$TRACE("An approval wait from round " _ round _ " ended; the case is in round " _ ..Round) Quit $$$OK }
    If case.State '= "awaiting_approval" { $$$TRACE("The approval wait ended; the case is " _ case.State _ ", so nothing is due") Quit $$$OK }
    Set wait = ..WaitWords(..ApprovalWaitSeconds)
    Do ..CancelOpenTask(case, "", "no decision within " _ wait)
    Set case.Headline = "No approval within " _ wait _ "; a person must decide"
    Quit case.Transition("escalated", "The approval task got no answer within " _ wait _ "; it is cancelled, and the plan waits for a reinvestigation or a hand close", "system")
}

/// A wait in words: whole minutes under an hour, else hours to one decimal.
ClassMethod WaitWords(seconds As %Integer) As %String
{
    If seconds < 3600 Quit (seconds \ 60) _ " minutes"
    Quit $FNUMBER(seconds / 3600, "", 1) _ " hours"
}

/// The approval task for a case's plan (CONTRACTS 6.4). Its PlanDigest form value starts empty: the decider supplies
/// the digest (the API from the body it checked, an approver in the Workflow inbox by pasting it from this message),
/// and OnApproval blocks the case when the answer carries none, or another one.
ClassMethod ApprovalTask(case As Shutter.Store.Case, plan As Shutter.Store.Plan, waitSeconds As %Integer = 0) As EnsLib.Workflow.TaskRequest
{
    Set task = ##class(EnsLib.Workflow.TaskRequest).%New()
    Set task.%Actions = "Approve,Reject"
    Set task.%Subject = "Shutter " _ case.CaseId _ ": approve plan v" _ plan.Version _ " (" _ plan.Disposition _ ")"
    Set task.%Message = case.Headline _ $CHAR(10) _ "Exact action: " _ plan.ActionType _ " " _ plan.OperationKey _ " at receiver version " _ plan.ExpectedVersion _ $CHAR(10) _ "Plan digest: " _ plan.Digest _ $CHAR(10) _ "Snapshot digest: " _ $SELECT($ISOBJECT(case.CurrentSnapshot): case.CurrentSnapshot.Digest, 1: "") _ $CHAR(10) _ "Rehearsal: would apply (rolled back)."
    Set task.%Message = task.%Message _ $CHAR(10) _ "To approve from the Workflow inbox, paste the plan digest above into the PlanDigest field: an approval with no digest, or another one, binds nothing and blocks the case."
    // What approvers decided before on these conditions at this receiver (6.4, v1.35); a lookup that fails leaves the line out.
    Try {
        Set words = ##class(Shutter.Store.Precedent).Words(##class(Shutter.Store.Precedent).SummaryFor(case))
        If words '= "" Set task.%Message = task.%Message _ $CHAR(10) _ words
    } Catch ex {}
    If waitSeconds > 0 Set task.%Message = task.%Message _ $CHAR(10) _ "Unanswered after " _ ..WaitWords(waitSeconds) _ ", the task is cancelled and the case escalates to a person."
    Set task.%Priority = 2
    Set task.%FormFields = "PlanDigest,Comment"
    Quit task
}

/// A person's decision as a precedent (CONTRACTS 6.4, v1.35): an approval once its resend is verified at the receiver, a
/// rejection at once; an automatic release writes none. Never an error for the case: a precedent that fails to write is
/// a warning in the event log, and the case goes on.
Method RecordPrecedent(case As Shutter.Store.Case, plan As Shutter.Store.Plan, approval As Shutter.Store.Approval, decision As %String)
{
    Try {
        Set sc = ##class(Shutter.Store.Precedent).Record(case, plan, approval, decision, .p)
        If $$$ISERR(sc) {
            $$$LOGWARNING("The precedent of " _ case.CaseId _ " was not recorded: " _ $SYSTEM.Status.GetErrorText(sc))
        } ElseIf $ISOBJECT(p) {
            Do case.Note("note", "Precedent recorded: " _ decision _ " by " _ approval.Approver _ " on these conditions at " _ case.Receiver, "system", "precedent:" _ p.%Id())
        }
    } Catch ex {
        $$$LOGWARNING("The precedent of " _ case.CaseId _ " was not recorded: " _ ex.DisplayString())
    }
}

/// The automatic release (CONTRACTS 6.4): no Workflow task; an approval by "policy" binds the same things a
/// person's does, then the preflight read and the dispatch gate as for any approval.
Method ReleaseByPolicy(case As Shutter.Store.Case, plan As Shutter.Store.Plan, rehearsal As Shutter.Store.Rehearsal) As %Status
{
    Set profile = ##class(Shutter.Store.SiteProfile).Current()
    Set tier = ##class(Shutter.Store.SiteProfile).TierOf($SELECT(case.Receiver '= "": case.Receiver, 1: ..WardTarget))
    Set comment = "Automatic by site policy v" _ ##class(Shutter.Util.Json).Str(profile, "version", 0) _ ": tier " _ tier _ ", " _ ..ChainKind _ " chain; catalogue " _ ..CatalogueEntry _ " " _ ..CatalogueOutcome
    Set sc = ##class(Shutter.Store.Approval).Create(case, plan, case.CurrentSnapshot, ##class(Shutter.Operation.Gate).#POLICYVERSION, rehearsal, plan.ExpectedVersion, "policy", "approved", comment, "", ..ApprovalValidSeconds, .a, ..ReceiverEpoch)
    Quit:$$$ISERR(sc) sc
    Set ..ApprovalId = a.%Id()
    Set case.CurrentApproval = a
    Set sc = case.Transition("approved", "Released by site policy, no approval asked: " _ comment _ "; plan digest " _ $EXTRACT(plan.Digest, 1, 19), "policy", "approval:" _ a.%Id())
    Quit:$$$ISERR(sc) sc
    Quit ..SendPreflight(case)
}

/// The case stops here, its evidence and match in the store, until its incident releases it (CONTRACTS 7.1);
/// this instance ends. The membership is read again under the case's lock, which the incident takes too when it lets a
/// case go (Shutter.Store.IncidentDetector.Leave): a case let go meanwhile does not park (parked is 0) and goes on alone.
Method Park(case As Shutter.Store.Case, Output parked As %Boolean) As %Status
{
    Set parked = 0
    Set sc = case.Lock()
    Quit:$$$ISERR(sc) sc
    Set inc = case.StoredIncident()
    If '$ISOBJECT(inc) {
        Do case.IncidentSetObjectId("")
        Do case.Unlock()
        Quit $$$OK
    }
    Set parked = 1, ..PendingJSON = "[]"
    Set sc = case.Transition("grouped", "Held by incident " _ inc.IncidentId _ ": the incident groups the receiver's failures into chains per encounter and decides the order of release", "system", "incident:" _ inc.IncidentId)
    Do case.Unlock()
    Quit sc
}

/// A case its incident releases (CONTRACTS 7.4): a fresh instance, fresh evidence with no settle period, then the
/// chain's path. The incident's approval, when the site's policy asked for one, stands in for a person's.
Method OnRelease(request As Shutter.Msg.CaseRelease, Output response As %Library.Persistent) As %Status
{
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Quit $$$ERROR($$$GeneralError, "No case " _ request.CaseId _ " to release")
    Set started = ##class(Shutter.Msg.CaseStarted).%New()
    Set started.CaseId = case.CaseId, started.Opened = 0, started.State = case.State
    Set response = started
    If case.State '= "grouped" {
        $$$LOGWARNING("Case " _ case.CaseId _ " is " _ case.State _ ", not grouped; the release from incident " _ request.IncidentId _ " is ignored")
        Quit $$$OK
    }
    Set ..CaseId = case.CaseId, ..Mode = case.Mode, ..Release = 1
    Set ..IncidentId = request.IncidentId, ..ChainSeq = request.ChainSeq, ..ChainPosition = request.Position
    Set ..ChainKind = $SELECT(request.ChainKind = "": "single", 1: request.ChainKind), ..ChainDecides = request.Decides
    Set ..ExpectedVersion = request.ExpectedVersion, ..ReleasePolicy = request.ReleasePolicy
    Set ..IncidentApprover = request.Approver, ..IncidentApprovalRef = request.ApprovalRef, ..IncidentPlanDigest = request.PlanDigest
    Set ..IncidentEntry = request.Entry, ..IncidentOutcome = request.Outcome
    Set case.WorkflowSessionId = ..%SessionId
    Do case.%Save()
    Set how = $CASE(..ReleasePolicy, "automatic": "automatic by site policy", "incident": "under the incident's approval by " _ ..IncidentApprover, : "on its own path")
    Do case.Note("note", "Released by incident " _ ..IncidentId _ ": chain " _ ..ChainSeq _ " item " _ ..ChainPosition _ " (" _ ..ChainKind _ ", " _ ..ChainDecides _ " decides, " _ how _ ")" _ $SELECT(..ExpectedVersion '= "": "; expected receiver version " _ ..ExpectedVersion, 1: "; fresh evidence decides"), "system", "incident:" _ ..IncidentId)
    $$$TRACE("Case " _ case.CaseId _ " released by incident " _ ..IncidentId)
    Quit ..StartEvidence(case)
}

/// A closed case reopened by a person: fresh evidence, a new plan version, the old plan and approval kept as
/// history. A case an incident once held runs alone from here.
Method OnReinvestigate(request As Shutter.Msg.Reinvestigate, Output response As %Library.Persistent) As %Status
{
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Quit $$$ERROR($$$GeneralError, "No case " _ request.CaseId _ " to reopen")
    Set started = ##class(Shutter.Msg.CaseStarted).%New()
    Set started.CaseId = case.CaseId, started.Opened = 0, started.State = case.State
    Set response = started
    If 'case.IsClosed() || (case.State = "resolved") {
        $$$LOGWARNING("Case " _ case.CaseId _ " is " _ case.State _ "; only a blocked, escalated or failed case can be reopened")
        Quit $$$OK
    }
    Set ..CaseId = case.CaseId, ..Mode = case.Mode, ..Reopened = 1
    Set ..ForceBoard = request.ForceBoard, ..ConvenedBy = $SELECT(request.ForceBoard: request.RequestedBy, 1: "")
    Set ..ReopenedBy = request.RequestedBy, ..LiveAllowed = request.LiveAllowed
    Set case.WorkflowSessionId = ..%SessionId, case.ClosedAt = ""
    // A wait on another case ends with the reopening; the fresh gate sets it again if the bed is still held (v1.28).
    Set case.WaitsOnCase = "", case.WaitsOnMessage = ""
    If $ISOBJECT(case.CurrentApproval) && 'case.CurrentApproval.Revoked Do case.CurrentApproval.Revoke(request.RequestedBy _ ": the case was reopened")
    Do case.%Save()
    Set who = $SELECT(request.RequestedBy = "": "a person", 1: request.RequestedBy)
    Do case.Note("note", "Reopened by " _ who _ $SELECT(request.Reason '= "": ": " _ request.Reason, 1: "") _ ". Fresh evidence; the earlier plan and approval stay as history", who)
    $$$TRACE("Case " _ case.CaseId _ " reopened by " _ who)
    Quit ..StartEvidence(case)
}

/// A closed case the team handled by hand (T31, 2.6): a fresh instance resolves it with disposition handled_by_hand
/// (Shutter.Store.Case.CloseByHand), cancels its open approval task, if any, and ends, as an instance ends after a
/// verification. The case keeps the workflow session of its investigation, so its trace link still shows the work
/// that led to the escalation.
Method OnClose(request As Shutter.Msg.CaseClose, Output response As %Library.Persistent) As %Status
{
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Quit $$$ERROR($$$GeneralError, "No case " _ request.CaseId _ " to close")
    Set started = ##class(Shutter.Msg.CaseStarted).%New()
    Set started.CaseId = case.CaseId, started.Opened = 0, started.State = case.State
    Set response = started
    If '$LISTFIND($LISTBUILD("escalated", "blocked", "failed"), case.State) {
        $$$LOGWARNING("Case " _ case.CaseId _ " is " _ case.State _ "; only an escalated, blocked or failed case can be marked handled")
        Quit $$$OK
    }
    Set ..CaseId = case.CaseId, ..Mode = case.Mode
    Set who = $SELECT(request.Actor = "": "a person", 1: request.Actor)
    Set sc = ##class(Shutter.Store.Case).CloseByHand(case, request.Reason, who, request.ExpectedVersion)
    Quit:$$$ISERR(sc) sc
    Set started.State = case.State
    $$$TRACE("Case " _ case.CaseId _ " handled by hand, closed by " _ who)
    Do ..LeadLeftBehind(case, "the leader was handled by hand")
    Quit ..CancelOpenTask(case, request.Actor, "the case was handled by hand")
}

/// A working case an approver gave up (CONTRACTS 5): a fresh instance fails it with disposition abandoned
/// (Shutter.Store.Case.Abandon), cancels its open approval task, if any, and ends. The case keeps the workflow session
/// of the instance that stopped, so its trace link still shows where it stopped; that instance, if it ever answers,
/// finds the case closed and ignores the answer (OnResponse). The route refused the request while anything of that
/// session was in flight; the transition's version check guards the moment in between, and a refused abandon leaves the
/// case as it was.
Method OnAbandon(request As Shutter.Msg.CaseAbandon, Output response As %Library.Persistent) As %Status
{
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Quit $$$ERROR($$$GeneralError, "No case " _ request.CaseId _ " to abandon")
    Set started = ##class(Shutter.Msg.CaseStarted).%New()
    Set started.CaseId = case.CaseId, started.Opened = 0, started.State = case.State
    Set response = started
    If case.IsClosed() {
        $$$LOGWARNING("Case " _ case.CaseId _ " is " _ case.State _ "; a closed case is marked handled or reopened, not abandoned")
        Quit $$$OK
    }
    Set ..CaseId = case.CaseId, ..Mode = case.Mode
    Set who = $SELECT(request.Actor = "": "a person", 1: request.Actor)
    Set sc = ##class(Shutter.Store.Case).Abandon(case, request.Reason, who, request.ExpectedVersion)
    Quit:$$$ISERR(sc) sc
    Set started.State = case.State
    $$$TRACE("Case " _ case.CaseId _ " abandoned by " _ who)
    Do ..LeadLeftBehind(case, "the leader was abandoned")
    Quit ..CancelOpenTask(case, request.Actor, "the case was abandoned")
}

/// An approval task still open for a case just closed (it was closed by hand or abandoned while it waited for an
/// approver) is completed as cancelled, so it leaves the inbox and the instance waiting on it ends: that instance finds
/// the case closed and ignores the answer (OnResponse). The case is closed first, so the answer can never reach an open
/// case. The engine records the actor as the person who closed it when the Workflow role lets it; the task's comment
/// and the case's approval event say why ("Cancelled: <why>"). Nothing here fails the caller: a refusal is logged and
/// noted on the case.
Method CancelOpenTask(case As Shutter.Store.Case, actor As %String, why As %String) As %Status
{
    Set task = ##class(Shutter.Util.Workflow).OpenTaskFor(case.CaseId)
    If '$ISOBJECT(task) Quit $$$OK
    Set who = $SELECT(actor = "": "a person", 1: actor)
    Set taskId = task.%Id()
    If actor '= "" {
        // The engine records who closed it; a refusal (the user is outside the Workflow role) changes nothing below.
        Set asc = ##class(EnsLib.Workflow.Engine).AssignTask(task, actor)
        If $$$ISERR(asc) { $$$TRACE("Approval task " _ taskId _ " was not assigned to " _ actor _ ": " _ $SYSTEM.Status.GetErrorText(asc)) }
        Set task.%UserName = actor
    }
    Do task.%FormValues.SetAt("Cancelled: " _ why, "Comment")
    If '$LISTFIND($LISTFROMSTRING(task.%Actions, ","), "Cancel") Set task.%Actions = task.%Actions _ $SELECT(task.%Actions = "": "", 1: ",") _ "Cancel"
    Do task.%Save()
    Set tsc = ##class(EnsLib.Workflow.Engine).CompleteTask(task, "Cancel")
    If $$$ISERR(tsc) {
        $$$LOGWARNING("The approval task " _ taskId _ " of case " _ case.CaseId _ " could not be cancelled: " _ $SYSTEM.Status.GetErrorText(tsc))
        Do case.Note("error", "The approval task " _ taskId _ " could not be cancelled: " _ $EXTRACT($SYSTEM.Status.GetErrorText(tsc), 1, 400), "system", "task:" _ taskId)
    } Else {
        Do case.Note("approval", "Approval task " _ taskId _ " cancelled: " _ why, who, "task:" _ taskId)
    }
    Quit $$$OK
}

/// A withheld case with no single catalogue entry (E14 and E15 not installed, or several matched): an escalate plan
/// naming the feed's reason, through the gate, which appends MERGE_WITHHELD or CANCEL_UNSUPPORTED; the board never runs.
Method WithheldToPerson(case As Shutter.Store.Case) As %Status
{
    Set ..Policy = "person"
    Do case.Note("note", "Withheld operation: no board; a person decides (" _ case.FailureText _ ")", "system")
    Set plan = {}
    Set plan.disposition = "escalate", plan.action = {"type": "none"}
    Set plan.why = case.FailureText
    Set plan.summary = case.FailureText
    Set plan.preconditions = [], plan."evidence_refs" = ["failure"], plan.disagreements = []
    Quit ..AdoptPlan(case, plan, "withheld")
}

/// A released item authorised by the incident's approval (CONTRACTS 7.3): an approval record naming the approver,
/// the task, the incident plan digest they bound and the entry and outcome that plan listed for the item, then the
/// preflight read and the dispatch gate as for any approval.
Method ReleaseByIncident(case As Shutter.Store.Case, plan As Shutter.Store.Plan, rehearsal As Shutter.Store.Rehearsal) As %Status
{
    Set comment = "Under the approval of incident " _ ..IncidentId _ " by " _ ..IncidentApprover _ " (task " _ ..IncidentApprovalRef _ ", incident plan digest " _ $EXTRACT(..IncidentPlanDigest, 1, 19) _ "): chain " _ ..ChainSeq _ " item " _ ..ChainPosition _ ", " _ ..ChainKind _ "; approved as " _ ..IncidentEntry _ " " _ ..IncidentOutcome _ ", catalogue " _ ..CatalogueEntry _ " " _ ..CatalogueOutcome _ $SELECT(..ExpectedVersion '= "": "; expected version " _ ..ExpectedVersion, 1: "")
    Set sc = ##class(Shutter.Store.Approval).Create(case, plan, case.CurrentSnapshot, ##class(Shutter.Operation.Gate).#POLICYVERSION, rehearsal, plan.ExpectedVersion, ..IncidentApprover, "approved", comment, ..IncidentApprovalRef, ..ApprovalValidSeconds, .a, ..ReceiverEpoch)
    Quit:$$$ISERR(sc) sc
    Set sc = a.BindIncident(..IncidentPlanDigest, ..IncidentEntry, ..IncidentOutcome)
    Quit:$$$ISERR(sc) sc
    Set ..ApprovalId = a.%Id()
    Set case.CurrentApproval = a
    Set sc = case.Transition("approved", "Released under incident " _ ..IncidentId _ "'s approval by " _ ..IncidentApprover _ ": " _ comment _ "; plan digest " _ $EXTRACT(plan.Digest, 1, 19), ..IncidentApprover, "approval:" _ a.%Id())
    Quit:$$$ISERR(sc) sc
    Quit ..SendPreflight(case)
}

Method OnApproval(case As Shutter.Store.Case, result As EnsLib.Workflow.TaskResponse) As %Status
{
    Set plan = ##class(Shutter.Store.Plan).%OpenId(..PlanId)
    Set action = $ZCONVERT(result.%Action, "L")
    Set user = result.%UserName
    Set comment = result.%FormValues.GetAt("Comment")
    Set digest = result.%FormValues.GetAt("PlanDigest")
    Set taskId = result.%Id()
    // The latest rehearsal of this plan: the approval binds it, and the dispatch gate's rehearsal check requires the bound
    // one to be of the plan it releases (none bound blocks DRY_RUN_MISSING).
    Set rehearsal = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM Shutter_Store.Rehearsal WHERE Plan = ? ORDER BY ID DESC", ..PlanId)
    If rs.%Next() Set rehearsal = ##class(Shutter.Store.Rehearsal).%OpenId(rs.%Get("ID"))
    If action '= "approve" {
        Set sc = ##class(Shutter.Store.Approval).Create(case, plan, case.CurrentSnapshot, ##class(Shutter.Operation.Gate).#POLICYVERSION, rehearsal, plan.ExpectedVersion, user, "rejected", comment, taskId, ..ApprovalValidSeconds, .a)
        Quit:$$$ISERR(sc) sc
        Do ..RecordPrecedent(case, plan, a, "rejected")
        Set case.Headline = "Rejected by " _ user _ ": " _ case.Headline
        Quit case.Transition("blocked", "Rejected by " _ user _ $SELECT(comment '= "": ": " _ comment, 1: ""), user, "approval:" _ a.%Id())
    }
    If digest = "" {
        Quit case.Transition("blocked", "The approval carried no plan digest, so it binds nothing; nothing was dispatched", user)
    }
    If digest '= plan.Digest {
        Quit case.Transition("blocked", "The approval named another plan digest (" _ $EXTRACT(digest, 1, 19) _ "); nothing was dispatched", user)
    }
    Set sc = ##class(Shutter.Store.Approval).Create(case, plan, case.CurrentSnapshot, ##class(Shutter.Operation.Gate).#POLICYVERSION, rehearsal, plan.ExpectedVersion, user, "approved", comment, taskId, ..ApprovalValidSeconds, .a, ..ReceiverEpoch)
    Quit:$$$ISERR(sc) sc
    Set ..ApprovalId = a.%Id()
    Set case.CurrentApproval = a
    Set sc = case.Transition("approved", "Approved by " _ user _ " for plan digest " _ $EXTRACT(plan.Digest, 1, 19) _ $SELECT(comment '= "": ": " _ comment, 1: ""), user, "approval:" _ a.%Id())
    Quit:$$$ISERR(sc) sc
    // Preflight: read the receiver's current version before the dispatch gate decides.
    Quit ..SendPreflight(case)
}

/// The wait before a preflight read is tried again: the backoff, or the receiver's Retry-After when it asked for longer, at
/// most MAXRETRYAFTER.
ClassMethod RetryAfterWait(retryAfter As %String, backoff As %Integer) As %Integer
{
    If (retryAfter = "") || (+retryAfter <= 0) Quit backoff
    Set asked = $SELECT(+retryAfter > ..#MAXRETRYAFTER: ..#MAXRETRYAFTER, 1: +retryAfter)
    Quit $SELECT(asked > backoff: asked, 1: backoff)
}

/// Seconds the preflight read waits for the receiver's Retry-After: what is left of it, at most MAXRETRYAFTER; 0 when the
/// case carries none or it has passed. now is an ISO UTC time, the clock when empty.
ClassMethod PreflightWaitSeconds(case As Shutter.Store.Case, now As %String = "") As %Integer
{
    If '$ISOBJECT(case) || (case.RetryAfterUntil = "") Quit 0
    If now = "" Set now = ##class(Shutter.Util.Time).NowUTC()
    Set left = ##class(Shutter.Util.Time).SecondsBetween(now, case.RetryAfterUntil)
    If left <= 0 Quit 0
    Quit $SELECT(left > ..#MAXRETRYAFTER: ..#MAXRETRYAFTER, 1: left)
}

/// The longest the preflight read waits for a receiver's Retry-After, in seconds.
Parameter MAXRETRYAFTER = 300;

/// The preflight read of the receiver before the dispatch gate.
Method SendPreflight(case As Shutter.Store.Case) As %Status
{
    // The receiver's Retry-After (v1.35; CONTRACTS 6.5): the first read after an unavailable answer waits as the receiver
    // asked, 300 s at most; the wait is spent once.
    Set wait = ..PreflightWaitSeconds(case)
    If case.RetryAfterUntil '= "" {
        // Spent once, whether or not anything is left of it.
        Set until = case.RetryAfterUntil
        Set case.RetryAfterUntil = ""
        If wait > 0 Do case.Note("note", "The receiver asked for a pause before a retry (Retry-After, until " _ until _ "); the preflight read waits " _ wait _ " s", "system")
        Set sc = case.%Save()
        If wait > 0 {
            Set alarm = ##class(Ens.AlarmRequest).%New()
            Set alarm.Timeout = wait
            Quit ..SendRequestAsync("Ens.Alarm", alarm, 1, "preflight:retry")
        }
    }
    Set read = ##class(Shutter.Msg.WardOperation).%New()
    Set read.Purpose = "read", read.EncounterId = case.EncounterId, read.OperationKey = case.OperationKey, read.CaseId = case.CaseId
    Quit ..SendRequestAsync(..WardTargetFor(case), read, 1, "preflight")
}

Method OnPreflight(case As Shutter.Store.Case, result As Shutter.Msg.WardResult) As %Status
{
    If result.Outcome = "unknown_encounter" {
        If result.Epoch '= "" Set ..ReceiverEpoch = result.Epoch
        If case.Event = "admit" {
            Set ..ReceiverVersion = 0
            Do case.Note("note", "Preflight: the receiver has no encounter yet, as the admission expects (version 0)", "system")
            Quit ..SendGate(case, "dispatch", "gate:dispatch")
        }
        // A definite answer, not a failed read: the receiver has no such encounter, so nothing may be written to it. The
        // gate judges the stored snapshot, not this read, so the case blocks here, for a person.
        Set case.Headline = "Blocked at dispatch: the receiver does not know encounter " _ case.EncounterId
        Quit case.Transition("blocked", "The preflight read found no encounter " _ case.EncounterId _ " at the receiver (UNKNOWN_ENCOUNTER); nothing was dispatched, and a person must decide", "system")
    }
    If result.Outcome '= "read" {
        // A receiver that cannot be read right now is asked again, with a growing wait (A1); then the case blocks.
        If ..Refreshes < ..MaxRefreshes {
            Set ..Refreshes = ..Refreshes + 1
            Set backoff = 10 * (2 ** (..Refreshes - 1))
            // The receiver's Retry-After on the read, when it sent one (v1.35): the longer of it and the backoff.
            Set wait = ..RetryAfterWait(result.RetryAfterSeconds, backoff)
            Do case.Note("note", "The preflight read failed (" _ result.Outcome _ $SELECT(result.Error '= "": ", " _ result.Error, 1: "") _ "); reading again in " _ wait _ " s" _ $SELECT(wait > backoff: " as the receiver asked (Retry-After)", 1: "") _ " (" _ ..Refreshes _ " of " _ ..MaxRefreshes _ ")", "system")
            Set alarm = ##class(Ens.AlarmRequest).%New()
            Set alarm.Timeout = wait
            Quit ..SendRequestAsync("Ens.Alarm", alarm, 1, "preflight:retry")
        }
        Set case.Headline = "Blocked at dispatch: the receiver could not be read (" _ result.Outcome _ ")"
        Quit case.Transition("blocked", "The preflight read of the receiver failed " _ (..MaxRefreshes + 1) _ " times: " _ result.Outcome _ $SELECT(result.Error '= "": ", " _ result.Error, 1: "") _ ". Nothing was dispatched", "system")
    }
    Set ..ReceiverVersion = result.EncounterVersion
    If result.Epoch '= "" Set ..ReceiverEpoch = result.Epoch
    Do case.Note("note", "Preflight: the receiver holds the encounter at version " _ result.EncounterVersion _ " (" _ result.ReasonCode _ ")" _ $SELECT(result.Epoch '= "": ", epoch " _ result.Epoch, 1: ""), "system")
    Quit ..SendGate(case, "dispatch", "gate:dispatch")
}

Method OnGateDispatch(case As Shutter.Store.Case, result As Shutter.Msg.GateResult) As %Status
{
    If result.Outcome '= "pass" {
        // The receiver changed after the approval: the approval is void, and the case is planned
        // again once, on fresh evidence. Anything else blocks for a person.
        Set changed = (result.Summary [ "RECEIVER_CHANGED") || (result.Summary [ "RECEIVER_RESET")
        If changed && (..Replans < 1) {
            Set ..Replans = ..Replans + 1
            Set approval = ##class(Shutter.Store.Approval).%OpenId(..ApprovalId)
            If $ISOBJECT(approval) Do approval.Revoke("system: the receiver changed before dispatch")
            Set ..PlanId = "", ..ApprovalId = "", ..ReceiverVersion = "", ..ReceiverEpoch = "", ..AttemptId = ""
            Set ..Policy = "", ..CatalogueEntry = "", ..CatalogueOutcome = ""
            Do case.Note("note", "The receiver changed after the approval (" _ result.Summary _ "). The approval is void and the case is planned again on fresh evidence", "gate", "gate:" _ result.DecisionId)
            Quit ..StartEvidence(case)
        }
        // Stale evidence or a failed lookup is not a verdict (A1): the evidence is collected again, and the approval
        // stands if nothing material changed. Bounded, then the case blocks.
        If ..OnlyRefreshable(result) && (..Refreshes < ..MaxRefreshes) {
            Set ..Refreshes = ..Refreshes + 1, ..Refreshing = 1
            Do case.Note("note", "The dispatch gate could not decide (" _ result.Summary _ "); refreshing the evidence (" _ ..Refreshes _ " of " _ ..MaxRefreshes _ ") and checking again; the approval stands if nothing material changed", "gate", "gate:" _ result.DecisionId)
            Quit ..StartEvidence(case)
        }
        Set sc = ..BedWaitOutcome(case, result, .waited)
        If waited Quit sc
        Set case.Headline = "Blocked at dispatch: " _ result.Summary
        Quit case.Transition("blocked", "The gate did not pass the dispatch: " _ result.Summary, "gate", "gate:" _ result.DecisionId)
    }
    Set plan = ##class(Shutter.Store.Plan).%OpenId(..PlanId)
    // The dispatch is cleared: the retry budget starts afresh for what follows.
    Set ..Refreshes = 0
    Set sc = case.Transition("executing", "Dispatching the conditional write (expected version " _ plan.ExpectedVersion _ ")", "system", "gate:" _ result.DecisionId)
    Quit:$$$ISERR(sc) sc
    Quit ..SendRequestAsync(..WardTargetFor(case), ..WardOperationFor(case, plan, 0), 1, "execute")
}

Method OnExecute(case As Shutter.Store.Case, result As Shutter.Msg.WardResult) As %Status
{
    Set plan = ##class(Shutter.Store.Plan).%OpenId(..PlanId)
    Set approval = ##class(Shutter.Store.Approval).%OpenId(..ApprovalId)
    Set outcome = $CASE(result.Outcome, "applied": "applied", "already_committed": "already_committed", "version_conflict": "version_conflict", "uncertain": "uncertain", "unavailable": "error", "error": "error", : "refused")
    Set sc = ##class(Shutter.Store.ExecutionAttempt).Create(case, plan, approval, $SELECT($ISOBJECT(approval): approval.Rehearsal, 1: ""), result.HttpStatus, outcome, result.ResponseObject(), result.Error, .attempt)
    Quit:$$$ISERR(sc) sc
    Set ..AttemptId = attempt.%Id()
    Do case.Note("execution", "Dispatch: " _ outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "") _ ", HTTP " _ result.HttpStatus, "system", "attempt:" _ attempt.%Id())
    If (outcome = "applied") || (outcome = "already_committed") || (outcome = "uncertain") {
        Set sc = case.Transition("verifying", $SELECT(outcome = "uncertain": "The receiver did not answer; reconciling by operation key, reading again until a receipt, the history or the settle window settles it", 1: "The receiver acknowledged; verifying the effect"), "system", "attempt:" _ attempt.%Id())
        Quit:$$$ISERR(sc) sc
        Quit ..SendVerify(case)
    }
    // A version conflict means the receiver moved between the preflight read and the write (A9): the approval is void,
    // and the case is planned once more on fresh evidence, which shows what moved it (an update never supersedes a
    // transfer, so the plan comes back at the new version, for approval again). Anything else blocks for a person.
    If (outcome = "version_conflict") && (..Replans < 1) {
        Set ..Replans = ..Replans + 1
        If $ISOBJECT(approval) Do approval.Revoke("system: the receiver's version moved before the write")
        Set ..PlanId = "", ..ApprovalId = "", ..ReceiverVersion = "", ..ReceiverEpoch = "", ..AttemptId = ""
        Set ..Policy = "", ..CatalogueEntry = "", ..CatalogueOutcome = ""
        Do case.Note("note", "The write was refused: the receiver's version moved between the preflight read and the write (" _ $SELECT(result.ReasonCode '= "": result.ReasonCode, 1: outcome) _ "). The approval is void and the case is planned again on fresh evidence", "system", "attempt:" _ attempt.%Id())
        Quit ..StartEvidence(case)
    }
    Set case.Headline = "Dispatch refused: " _ outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "")
    If result.ReasonCode = "newer_message_pending" {
        // The connector's last-line check (v1.29): the resend waits for the pending message's delivery.
        Set pending = ##class(Shutter.Util.ResendGuard).Pending(case)
        Set control = $SELECT($ISOBJECT(pending) && (pending.%Size() > 0): ##class(Shutter.Util.Json).Str(pending.%Get(0), "control_id"), 1: "")
        Set case.WaitsOnMessage = control
        Set case.Headline = "Waiting for a newer message of the encounter to be delivered" _ $SELECT(control '= "": " (" _ control _ ")", 1: "")
        Quit case.Transition("blocked", "The connector held the resend: " _ $SELECT(result.Error '= "": result.Error, 1: "a newer message of this encounter is pending in Shutter") _ ". Nothing was sent; the case is checked again on fresh evidence once that message has been delivered", "system", "attempt:" _ attempt.%Id())
    }
    Quit case.Transition("blocked", "The conditional write was refused: " _ outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "") _ ". The plan is void; a person must decide", "system", "attempt:" _ attempt.%Id())
}

Method SendVerify(case As Shutter.Store.Case) As %Status
{
    Set req = ##class(Shutter.Msg.VerifyRequest).%New()
    Set req.CaseId = case.CaseId, req.PlanId = ..PlanId, req.AttemptId = ..AttemptId
    Quit ..SendRequestAsync(..VerifyTarget, req, 1, "verify")
}

Method OnVerify(case As Shutter.Store.Case, result As Shutter.Msg.VerifyResult) As %Status
{
    Set json = "Shutter.Util.Json"
    Set detail = $CLASSMETHOD(json, "Parse", result.DetailJSON, .dsc)
    If result.Outcome = "verified" {
        Set case.Outcome = result.Summary
        // A closure on a later transfer the feed sent whose delivery failed or is uncertain is written on that transfer's
        // case too (CONTRACTS 6.1): the person handling it sees what was dropped on its account.
        If $ISOBJECT(detail) Do ..NoteSupersededBy(case, detail.%Get("superseded_by"))
        // An approval that held: a precedent for the next approver of these conditions (6.4).
        Do ..RecordPrecedent(case, ##class(Shutter.Store.Plan).%OpenId(..PlanId), ##class(Shutter.Store.Approval).%OpenId(..ApprovalId), "approved")
        Quit case.Transition("resolved", "Verified: " _ result.Summary, "system", "verification:" _ result.VerificationId)
    }
    // A verification that established nothing yet is asked again with a growing wait, up to the limit (reads at about 0,
    // 10, 30 and 70 s after the attempt). The verifier says whether another read could settle it (detail.retry: a lookup
    // failed, or no receipt yet inside the settle window after a write whose answer was lost); a verification written
    // before it said so is read again when a lookup failed.
    Set retry = 0, unreadable = 0, es = "", rs = ""
    If $ISOBJECT(detail) {
        Set es = $CLASSMETHOD(json, "Str", detail, "encounter_http_status"), rs = $CLASSMETHOD(json, "Str", detail, "receipt_http_status")
        Set unreadable = ((es '= 200) && (es '= 404)) || ((rs '= 200) && (rs '= 404) && (rs '= -1))
        Set retry = $SELECT(detail.%IsDefined("retry"): $CLASSMETHOD(json, "Bool", detail, "retry"), 1: unreadable)
    }
    If retry && (..Refreshes < ..MaxRefreshes) {
        Set ..Refreshes = ..Refreshes + 1
        Set wait = 10 * (2 ** (..Refreshes - 1))
        Set why = $SELECT(unreadable: "could not read the receiver (encounter HTTP " _ es _ ", receipt HTTP " _ rs _ ")", 1: "established nothing yet (" _ result.Summary _ ")")
        Do case.Note("note", "The verification " _ why _ "; verifying again in " _ wait _ " s (" _ ..Refreshes _ " of " _ ..MaxRefreshes _ ")", "system", "verification:" _ result.VerificationId)
        Set alarm = ##class(Ens.AlarmRequest).%New()
        Set alarm.Timeout = wait
        Quit ..SendRequestAsync("Ens.Alarm", alarm, 1, "verify:retry")
    }
    Set case.Outcome = result.Summary
    // A write whose answer was lost and that was not committed (CONTRACTS 5.1): the approval authorised one write and it
    // is spent, so nothing is resent from here; a person reinvestigates, which plans again on fresh evidence.
    If result.Outcome = "not_committed" {
        Set approval = ##class(Shutter.Store.Approval).%OpenId(..ApprovalId)
        If $ISOBJECT(approval) Do approval.Revoke("system: the write was not committed")
        Set case.Headline = "Escalated: the resend was not committed"
        Quit case.Transition("escalated", "Not verified (not_committed): " _ result.Summary _ ". The approval is revoked, and nothing is resent without a person: a reinvestigation plans again on fresh evidence", "system", "verification:" _ result.VerificationId)
    }
    // A write whose outcome the reads could not settle: unknown is the verdict, and a person checks at the receiver.
    If (result.Outcome = "unresolved") && $ISOBJECT(detail) && ($CLASSMETHOD(json, "Str", detail, "disposition") = "resend") && ($CLASSMETHOD(json, "Str", detail, "verdict") = "unknown") && $ISOBJECT(detail.%Get("attempt")) {
        Set case.Headline = "Escalated: the resend's outcome is unknown"
        Quit case.Transition("escalated", "Not verified (unknown): " _ result.Summary _ ". Whether the receiver applied the resend is unknown; a person must check at the receiver before anything is resent", "system", "verification:" _ result.VerificationId)
    }
    Quit case.Transition("escalated", "Not verified (" _ result.Outcome _ "): " _ result.Summary, "system", "verification:" _ result.VerificationId)
}

/// Writes on the later transfer's case that this case was closed as superseded on its account, when the verifier's
/// support (detail.superseded_by) was a later transfer the feed sent whose delivery failed or is uncertain and whose
/// case is known (CONTRACTS 6.1). Never on this case, and never an error for the closure.
Method NoteSupersededBy(case As Shutter.Store.Case, by As %DynamicObject)
{
    If '$ISOBJECT(by) Quit
    Set otherId = ##class(Shutter.Util.Json).Str(by, "case_id")
    If (otherId = "") || (otherId = case.CaseId) Quit
    Set other = ##class(Shutter.Store.Case).ByCaseId(otherId)
    If '$ISOBJECT(other) Quit
    Set sc = other.Note("note", "Case " _ case.CaseId _ " was closed as superseded on this case's account: its " _ case.Event _ $SELECT(case.Ward '= "": " to " _ case.Ward, 1: "") _ " at " _ case.EventTime _ " is not resent, because this case's later movement supersedes it; this case recovers the patient's location", "system", "case:" _ case.CaseId)
    If $$$ISERR(sc) $$$LOGWARNING("Could not note the supersession on " _ otherId _ ": " _ $SYSTEM.Status.GetErrorText(sc))
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
<Value name="17">
<Value>Policy</Value>
</Value>
<Value name="18">
<Value>CatalogueEntry</Value>
</Value>
<Value name="19">
<Value>CatalogueOutcome</Value>
</Value>
<Value name="20">
<Value>SettleSeconds</Value>
</Value>
<Value name="21">
<Value>Release</Value>
</Value>
<Value name="22">
<Value>IncidentId</Value>
</Value>
<Value name="23">
<Value>ChainSeq</Value>
</Value>
<Value name="24">
<Value>ChainPosition</Value>
</Value>
<Value name="25">
<Value>ChainKind</Value>
</Value>
<Value name="26">
<Value>ChainDecides</Value>
</Value>
<Value name="27">
<Value>ExpectedVersion</Value>
</Value>
<Value name="28">
<Value>ReleasePolicy</Value>
</Value>
<Value name="29">
<Value>IncidentApprover</Value>
</Value>
<Value name="30">
<Value>IncidentApprovalRef</Value>
</Value>
<Value name="31">
<Value>IncidentPlanDigest</Value>
</Value>
<Value name="32">
<Value>IncidentTarget</Value>
</Value>
<Value name="33">
<Value>BoardTimeoutSeconds</Value>
</Value>
<Value name="34">
<Value>CoordinatorPending</Value>
</Value>
<Value name="35">
<Value>Reopened</Value>
</Value>
<Value name="36">
<Value>Refreshes</Value>
</Value>
<Value name="37">
<Value>Refreshing</Value>
</Value>
<Value name="38">
<Value>MaxRefreshes</Value>
</Value>
<Value name="39">
<Value>Round</Value>
</Value>
<Value name="40">
<Value>IncidentEntry</Value>
</Value>
<Value name="41">
<Value>IncidentOutcome</Value>
</Value>
<Value name="42">
<Value>ForceBoard</Value>
</Value>
<Value name="43">
<Value>ConvenedBy</Value>
</Value>
<Value name="48">
<Value>ReopenedBy</Value>
</Value>
<Value name="49">
<Value>LiveAllowed</Value>
</Value>
<Value name="44">
<Value>BoardsPerMinute</Value>
</Value>
<Value name="45">
<Value>DeferredMode</Value>
</Value>
<Value name="46">
<Value>DeferredBy</Value>
</Value>
<Value name="47">
<Value>LeadSignature</Value>
</Value>
</Data>
<DefaultData>CaseWorkflowDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
