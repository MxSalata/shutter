/// A recovery case: one failed or uncertain delivery, identified by its operation key, with a
/// lifecycle whose every transition is a CaseEvent. Changes carry an expected version so that two
/// actors cannot both advance the same case.
/// Several jobs hold copies of a case at once (its workflow, the evidence collector, the gate, the incident detector of
/// another case), so no job writes its whole copy back over a newer one: a transition takes the case's lock and refuses
/// a copy older than the stored version; a note writes only its time; the incident and the current snapshot are written
/// field by field (SetIncident, SetSnapshot), and every whole save takes both from the stored case (%OnBeforeSave).
Class Shutter.Store.Case Extends (%Persistent, %JSON.Adaptor)
{

Parameter %JSONIGNOREINVALIDFIELD = 1;

/// Public identifier, C-000001.
Property CaseId As %String(%JSONFIELDNAME = "caseId", MAXLEN = 32) [ Required ];

Index CaseIdIdx On CaseId [ Unique ];

/// The business operation this case is about (docs/CONTRACTS.md, section 2).
Property OperationKey As %String(%JSONFIELDNAME = "operationKey", MAXLEN = 400) [ Required ];

Index OperationKeyIdx On OperationKey;

Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 32, VALUELIST = ",detected,collecting,investigating,grouped,proposed,gated,rehearsing,awaiting_approval,approved,executing,verifying,resolved,blocked,escalated,failed") [ InitialExpression = "detected" ];

Index StateIdx On State;

/// Optimistic concurrency: every transition increments it; a change must name the version it saw.
Property Version As %Integer(%JSONFIELDNAME = "version") [ InitialExpression = 1 ];

/// How the case is investigated: the board, a single investigator, or rules only.
Property Mode As %String(%JSONFIELDNAME = "mode", MAXLEN = 16, VALUELIST = ",board,single,rules,policy") [ InitialExpression = "board" ];

/// delivery_failed, uncertain_outcome and rejected are the connector's answers; unmappable, a message that maps to no
/// operation; withheld, an operation the feed never sent (a merge the site's policy keeps for the PAS team, a cancel
/// the receiver cannot reverse), with the reason in FailureReasonCode (merge, cancel_unsupported).
Property FailureKind As %String(%JSONFIELDNAME = "failureKind", MAXLEN = 32, VALUELIST = ",delivery_failed,uncertain_outcome,rejected,unmappable,withheld,unreadable");

Property FailureText As %String(%JSONFIELDNAME = "failureText", MAXLEN = 2000);

/// The connector's answer as recorded, not parsed from prose: its outcome, reason code and HTTP status (C3).
Property FailureOutcome As %String(%JSONFIELDNAME = "failureOutcome", MAXLEN = 32);

Property FailureReasonCode As %String(%JSONFIELDNAME = "failureReasonCode", MAXLEN = 100);

/// The schema category whose absence holds the message (v1.34, kind unreadable, "prevent failures"): the index's check
/// releases the case once it is loaded where the message was read (SourceNamespace, else here). "" for every other case.
Property HeldSchema As %String(%JSONFIELDNAME = "heldSchema", MAXLEN = 128);

Property FailureHttpStatus As %Integer(%JSONFIELDNAME = "failureHttpStatus");

/// Until when the receiver asked not to retry (its Retry-After on the failed delivery, v1.35): the preflight read of the
/// resend waits for it (CaseWorkflow.SendPreflight, 300 s at most), then it is cleared. "" when it sent none.
Property RetryAfterUntil As %String(%JSONFIELDNAME = "retryAfterUntil", MAXLEN = 30);

Property EncounterId As %String(%JSONFIELDNAME = "encounterId", MAXLEN = 100);

Index EncounterIdx On EncounterId;

Property PatientId As %String(%JSONFIELDNAME = "patientId", MAXLEN = 100);

Property PatientIdAuthority As %String(%JSONFIELDNAME = "patientIdAuthority", MAXLEN = 100);

Property SourceSystem As %String(%JSONFIELDNAME = "sourceSystem", MAXLEN = 100);

Property SourceMessageId As %String(%JSONFIELDNAME = "sourceMessageId", MAXLEN = 200);

/// The event word of the operation key (Shutter.Util.OperationKey.EventForTrigger): admit, transfer, discharge,
/// update, the cancel words, merge, the indexed-only words; the raw trigger for an unmappable case.
Property Event As %String(%JSONFIELDNAME = "event", MAXLEN = 32);

Property Ward As %String(%JSONFIELDNAME = "ward", MAXLEN = 100);

/// The bed within the ward (PV1-3's second component; v1.28), for an admission or a transfer; empty for a ward-level placement.
/// Beside the canonical payload, so it is not in the digest.
Property Bed As %String(%JSONFIELDNAME = "bed", MAXLEN = 64);

/// The case this one waits on (v1.28): the case about the occupant's movement out of the bed this case's write needs, set
/// when the gate blocks with WAITING_FOR_OCCUPANT_CASE and cleared by a reopening; when that case closes, this one is
/// reinvestigated (ReleaseWaiting).
Property WaitsOnCase As %String(%JSONFIELDNAME = "waitsOn", MAXLEN = 32);

Index WaitsIdx On WaitsOnCase;

/// The message this case waits for (v1.29): the MSH-10 control id of a newer message of the encounter that was pending in
/// Shutter when the gate or the connector held the resend (NEWER_MESSAGE_PENDING); cleared by a reopening. Its delivery
/// reopens the case (ReleaseWaitingOnMessage).
Property WaitsOnMessage As %String(%JSONFIELDNAME = "waitsOnMessage", MAXLEN = 200);

Index WaitsMsgIdx On WaitsOnMessage;

/// The header the engine still holds that this case waits on, "namespace:header id", while blocked ENGINE_STILL_TRYING.
Property WaitsOnEngine As %String(%JSONFIELDNAME = "waitsOnEngine", MAXLEN = 200);

Index WaitsEngineIdx On WaitsOnEngine;

/// A person's release of a stop on another visit's movement (POST /cases/{id}/further-release, CONTRACTS 6.5), as JSON:
/// {digest, by, at, reason}. It holds only while a fresh read gives the same digest (Shutter.Util.FurtherMessages.Released).
Property FurtherReleaseJSON As %String(%JSONINCLUDE = "none", MAXLEN = 4000);

/// The case whose board this one follows (v1.35, one board per failure signature) while that board runs; "" otherwise.
Property FollowsCase As %String(%JSONFIELDNAME = "followsCase", MAXLEN = 32);

Index FollowsIdx On FollowsCase;

/// The failure signature this case led or followed a board for (v1.35), for the record.
Property LeadSignature As %String(%JSONFIELDNAME = "leadSignature", MAXLEN = 80);

/// A merge's prior record (A40, CONTRACTS 2): the patient identifier the merge discards (MRG-1) with its assigning
/// authority, the prior visit (MRG-5), and how many MRG segments the message carried (one per PATIENT group); the
/// identifiers are the first group's.
Property PriorPatientId As %String(%JSONFIELDNAME = "priorPatientId", MAXLEN = 100);

Property PriorPatientIdAuthority As %String(%JSONFIELDNAME = "priorPatientIdAuthority", MAXLEN = 100);

Property PriorEncounterId As %String(%JSONFIELDNAME = "priorEncounterId", MAXLEN = 100);

Property MergeGroups As %Integer(%JSONFIELDNAME = "mergeGroups");

/// The production item the failed delivery went to (the receiver), for incidents (CONTRACTS 7).
Property Receiver As %String(%JSONFIELDNAME = "receiver", MAXLEN = 128);

Property EventTime As %String(%JSONFIELDNAME = "eventTime", MAXLEN = 30);

/// The incident the case belongs to, when many failures to the receiver were grouped (CONTRACTS 7). Written only by
/// SetIncident.
Property Incident As Shutter.Store.Incident(%JSONINCLUDE = "none");

/// The demo scenario that produced the case (S1 to S6), when the scenario runner was running one;
/// recordings of agent runs for a scenario replay on any instance.
Property Scenario As %String(%JSONFIELDNAME = "scenario", MAXLEN = 32);

/// Whether the scenario runner played this case, set when it opens: a live story stamps its cases with a scenario id too, and
/// isn't a recorded run. Rules only's exemption at the gate asks this, and a later story can't change it.
Property ScenarioRecorded As %Boolean(%JSONINCLUDE = "none") [ InitialExpression = 0 ];

Index ScenarioIdx On Scenario;

/// The production session of the failed delivery: the Visual Trace link.
Property EnsSessionId As %String(%JSONFIELDNAME = "ensSessionId", MAXLEN = 20);

/// The Ens.MessageHeader id of the message whose delivery failed.
Property SourceHeaderId As %String(%JSONFIELDNAME = "sourceHeaderId", MAXLEN = 20);

/// Where the original message lives when the case came from another production (CONTRACTS 11): its namespace, the
/// production and the route (the item) that received it there, and its Ens.MessageHeader id in that namespace.
/// SourceHeaderId is then Shutter's own stored copy. Empty for a case the feed in this production opened.
Property SourceNamespace As %String(%JSONFIELDNAME = "sourceNamespace", MAXLEN = 64);

Property SourceProduction As %String(%JSONFIELDNAME = "sourceProduction", MAXLEN = 128);

Property SourceRoute As %String(%JSONFIELDNAME = "sourceRoute", MAXLEN = 128);

Property OriginHeaderId As %String(%JSONFIELDNAME = "originHeaderId", MAXLEN = 40);

/// The production session of the case workflow, once it runs.
Property WorkflowSessionId As %String(%JSONFIELDNAME = "workflowSessionId", MAXLEN = 20);

/// The decided disposition: resend, reconcile, superseded, more_evidence, escalate; handled_by_hand when the team closed the case (CloseByHand); abandoned when an approver gave up a case the workflow left behind (Abandon).
Property Disposition As %String(%JSONFIELDNAME = "disposition", MAXLEN = 32);

/// The catalogue had no entry for this case's pattern (CONTRACTS 6.3): a reviewer may write one.
Property CandidateEntry As %Boolean(%JSONFIELDNAME = "candidateEntry") [ InitialExpression = 0 ];

/// One line for the queue: what happened and what was decided.
Property Headline As %String(%JSONFIELDNAME = "headline", MAXLEN = 500);

/// The document block of a document case (CONTRACTS 11.2, Shutter.Util.DocumentCase): metadata only. Not projected: the API
/// gives it by the reader's right.
Property DocumentJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// The closing summary.
Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 4000);

Property OpenedAt As %String(%JSONFIELDNAME = "openedAt", MAXLEN = 30);

Property UpdatedAt As %String(%JSONFIELDNAME = "updatedAt", MAXLEN = 30);

Index UpdatedIdx On UpdatedAt;

Property ClosedAt As %String(%JSONFIELDNAME = "closedAt", MAXLEN = 30);

/// Written only by SetSnapshot.
Property CurrentSnapshot As Shutter.Store.Snapshot(%JSONFIELDNAME = "currentSnapshotId", %JSONREFERENCE = "ID");

Property CurrentPlan As Shutter.Store.Plan(%JSONFIELDNAME = "currentPlanId", %JSONREFERENCE = "ID");

Property CurrentApproval As Shutter.Store.Approval(%JSONFIELDNAME = "currentApprovalId", %JSONREFERENCE = "ID");

/// Open a case for an operation, or return the open one for the same key. The operation is the
/// downstream operation as built by Shutter.Util.OperationKey.FromHL7.
ClassMethod Open(op As %DynamicObject, failureKind As %String, failureText As %String, ensSessionId As %String, sourceHeaderId As %String, mode As %String, Output case As Shutter.Store.Case, Output opened As %Boolean, receiver As %String = "", heldSchema As %String = "") As %Status
{
    Set sc = $$$OK, opened = 0
    Set key = op."operation_key"
    // One case per failed delivery to one receiver (v1.25): the lookup is by the key and the receiver when it is known.
    Set case = ..FindOpen(key, receiver)
    If $ISOBJECT(case) {
        // An open case from before the last scenario reset belongs to an earlier run: close it.
        Set resetAt = $GET(^Shutter.Config("resetAt"))
        If (resetAt '= "") && (resetAt ]] case.OpenedAt) {
            Do case.Transition("failed", "Abandoned: a new scenario run reset the downstream system after this case was opened", "system")
            Set case = ""
        } Else {
            // The same key with other content (a corrected message resent with the same event time): the open case's plan
            // carries the first content, so it must not go out; a person decides (PAYLOAD_CHANGED).
            Set newDigest = ##class(Shutter.Util.Json).Str(op, "payload_digest"), oldDigest = case.PayloadDigest()
            Set digestDiffers = (newDigest '= "") && (oldDigest '= "") && (newDigest '= oldDigest)
            // The bed sits outside the digest (CONTRACTS 1.6), so a correction of the bed alone shows only here.
            Set newBed = $EXTRACT(##class(Shutter.Util.Json).Str(op, "bed"), 1, 64)
            Set bedDiffers = (op.%GetTypeOf("bed") '= "unassigned") && (newBed '= case.Bed)
            If (digestDiffers || bedDiffers) && 'case.IsClosed() {
                Set case.Headline = "Blocked: a further message for the same operation carries different content"
                Quit case.Transition("blocked", "PAYLOAD_CHANGED: a further failure for the same operation key carries different content (" _ $SELECT(digestDiffers: "payload digest " _ $EXTRACT(newDigest, 1, 19) _ " against " _ $EXTRACT(oldDigest, 1, 19), 1: "bed " _ $SELECT(newBed = "": "none", 1: newBed) _ " against " _ $SELECT(case.Bed = "": "none", 1: case.Bed)) _ "); the plan would write the first content, so nothing is dispatched and a person must decide. " _ failureText, "system", "ens:" _ sourceHeaderId)
            }
            Set sc = case.Note("note", "A further failure for the same operation: " _ failureText, "system", "ens:" _ sourceHeaderId)
            Quit sc
        }
    }
    Set case = ..%New()
    Set case.CaseId = ..NextId()
    Set case.OperationKey = key
    If receiver '= "" Set case.Receiver = receiver
    Set case.FailureKind = failureKind
    Set case.FailureText = $EXTRACT(failureText, 1, 2000)
    Set case.HeldSchema = $EXTRACT(heldSchema, 1, 128)
    Set case.EncounterId = op."encounter_id"
    Set case.PatientId = op."patient_id"
    Set case.PatientIdAuthority = op."patient_id_authority"
    Set case.SourceSystem = op."source_system"
    Set case.SourceMessageId = ##class(Shutter.Util.Json).Str(op, "source_message_id")
    Set case.Event = op."event"
    Set case.Ward = ##class(Shutter.Util.Json).Str(op, "ward")
    Set case.Bed = $EXTRACT(##class(Shutter.Util.Json).Str(op, "bed"), 1, 64)
    Set case.PriorPatientId = ##class(Shutter.Util.Json).Str(op, "prior_patient_id")
    Set case.PriorPatientIdAuthority = ##class(Shutter.Util.Json).Str(op, "prior_patient_id_authority")
    Set case.PriorEncounterId = ##class(Shutter.Util.Json).Str(op, "prior_encounter_id")
    Set groups = ##class(Shutter.Util.Json).Str(op, "merge_groups")
    If groups '= "" Set case.MergeGroups = +groups
    Set case.EventTime = op."event_time"
    Set case.EnsSessionId = ensSessionId
    Set case.SourceHeaderId = sourceHeaderId
    If op.%IsDefined("document_stage") Set case.DocumentJSON = ##class(Shutter.Util.DocumentCase).Unstage(op."document_stage")
    Set case.Mode = $SELECT(mode = "": "board", 1: mode)
    Set case.Scenario = $GET(^Shutter.Config("scenario"))
    Set case.ScenarioRecorded = (case.Scenario '= "") && (case.Scenario = $GET(^Shutter.Config("scenarioRun")))
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    // A held message's headline is the hold itself ("Held: the schema X is not loaded here ..."), as the feed wrote it.
    Set case.Headline = $SELECT((failureKind = "unreadable") && ($EXTRACT(failureText, 1, 5) = "Held:"): $EXTRACT(failureText, 1, 500), 1: ..DescribeFailure(case))
    TSTART
    Set sc = case.%Save()
    If $$$ISOK(sc) Set sc = ##class(Shutter.Store.CaseEvent).Append(case, "state", "", "detected", "Case opened: " _ case.Headline, "system", "ens:" _ sourceHeaderId)
    If $$$ISOK(sc) {
        TCOMMIT
        Set opened = 1
    } Else {
        TROLLBACK
    }
    Quit sc
}

/// Delete the finished cases whose closing is older than a time, with everything that hangs off them (events, snapshots
/// and their items, plans, approvals, rehearsals, gate decisions, attempts, verifications, agent runs and their tool
/// calls, chain items, escalation emails and their .eml files), and the closed incidents older than it with their
/// chains, items, events and the cases they held. Finished means resolved, which covers handled by hand, or abandoned: a
/// blocked, escalated or failed case is waiting for a person, whatever its age, so it stays, and so does an incident that
/// holds one. Cases an open incident still holds stay. Returns how many cases went.
/// Housekeeping only (Shutter.Util.RetentionTask, switched on by a site): the record is the product.
ClassMethod PurgeClosedBefore(cutoff As %String) As %Integer
{
    Set n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.""Case"" WHERE ClosedAt IS NOT NULL AND ClosedAt < ? AND (State = 'resolved' OR (State = 'failed' AND Disposition = 'abandoned')) AND Incident IS NULL", cutoff)
    While rs.%Next() {
        If $$$ISOK(..PurgeCase(rs.%Get("ID"))) Set n = n + 1
    }
    Set ri = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Incident WHERE State = 'closed' AND ClosedAt IS NOT NULL AND ClosedAt < ?", cutoff)
    While ri.%Next() {
        Set iid = ri.%Get("ID"), ok = 1
        // Only its cases whose own closing is older than the cutoff: a case reopened and closed again later stays.
        Set rc = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.""Case"" WHERE Incident = ? AND (State = 'resolved' OR (State = 'failed' AND Disposition = 'abandoned')) AND ClosedAt IS NOT NULL AND ClosedAt < ?", iid, cutoff)
        While rc.%Next() { If $$$ISOK(..PurgeCase(rc.%Get("ID"))) { Set n = n + 1 } Else { Set ok = 0 } }
        Continue:'ok
        Set open = 0
        &sql(SELECT COUNT(*) INTO :open FROM Shutter_Store."Case" WHERE Incident = :iid)
        Continue:(+open > 0)
        TSTART
        Set sc = ..Exec("DELETE FROM Shutter_Store.ChainItem WHERE Chain IN (SELECT ID FROM Shutter_Store.Chain WHERE Incident = ?)", iid)
        If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM Shutter_Store.Chain WHERE Incident = ?", iid)
        If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM Shutter_Store.IncidentEvent WHERE Incident = ?", iid)
        If $$$ISOK(sc) Set sc = ##class(Shutter.Store.Incident).%DeleteId(iid)
        If $$$ISOK(sc) { TCOMMIT  Kill ^Shutter.Counter("incidentEvent", iid) } Else { TROLLBACK }
    }
    Quit n
}

/// One closed case and everything that hangs off it, in one transaction.
ClassMethod PurgeCase(id As %String) As %Status
{
    // The tool calls of the case's runs, and their counters.
    Set keys = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT EnsMessageId FROM Shutter_Store.AgentRun WHERE ""Case"" = ? AND EnsMessageId IS NOT NULL", id)
    While keys.%Next() { Kill ^Shutter.Counter("toolcall", keys.%Get("EnsMessageId")) }
    // The .eml files of the case's escalations, removed once their rows are gone (a rollback leaves both).
    Set files = ""
    Set emails = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Seq, Result FROM Shutter_Store.Escalation WHERE ""Case"" = ? AND Transport = 'file'", id)
    While emails.%Next() { Set files = files _ $LISTBUILD($LISTBUILD(emails.%Get("Seq"), emails.%Get("Result"))) }
    TSTART
    Set sc = ..Exec("DELETE FROM Shutter_Bridge.ToolCall WHERE RunKey IN (SELECT EnsMessageId FROM Shutter_Store.AgentRun WHERE ""Case"" = ? AND EnsMessageId IS NOT NULL)", id)
    For table = "Shutter_Store.WarehouseRead", "Shutter_Store.CaseToken", "Shutter_Store.ChainItem", "Shutter_Store.Verification", "Shutter_Store.ExecutionAttempt", "Shutter_Store.Approval", "Shutter_Store.Rehearsal", "Shutter_Store.GateDecision", "Shutter_Store.Finding", "Shutter_Store.AgentRun", "Shutter_Store.CaseQuestion", "Shutter_Store.Plan", "Shutter_Store.Escalation", "Shutter_Store.CaseReminder" {
        If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM " _ table _ " WHERE ""Case"" = ?", id)
    }
    If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM Shutter_Store.SnapshotItem WHERE Snapshot IN (SELECT ID FROM Shutter_Store.Snapshot WHERE ""Case"" = ?)", id)
    If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM Shutter_Store.Snapshot WHERE ""Case"" = ?", id)
    If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
    If $$$ISOK(sc) Set sc = ..%DeleteId(id)
    If $$$ISOK(sc) { TCOMMIT } Else { TROLLBACK  Quit sc }
    Kill ^Shutter.Counter("event", id), ^Shutter.Counter("plan", id), ^Shutter.Counter("snapshot", id)
    For i = 1:1:$LISTLENGTH(files) { Do ##class(Shutter.Store.Escalation).RemoveFile($LIST($LIST(files, i), 2), $LIST($LIST(files, i), 1)) }
    Quit sc
}

/// One SQL statement with one argument, as a status.
ClassMethod Exec(sql As %String, arg As %String) As %Status [ Private ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, arg)
    If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "SQLCODE " _ rs.%SQLCODE _ ": " _ rs.%Message)
    Quit $$$OK
}

/// The payload digest of the operation this case is about, from the case's own fields (as the evidence computes it).
Method PayloadDigest() As %String
{
    Set op = {}
    Set op."operation_key" = ..OperationKey, op."encounter_id" = ..EncounterId
    Set op."patient_id" = ..PatientId, op."patient_id_authority" = ..PatientIdAuthority
    Set op."event" = ..Event
    If ..Ward '= "" { Set op."ward" = ..Ward } Else { Do op.%Set("ward", "", "null") }
    Set op."event_time" = ..EventTime, op."source_system" = ..SourceSystem, op."source_message_id" = ..SourceMessageId
    Quit ##class(Shutter.Util.Digest).WardPayloadDigest(op)
}

/// The open case for an operation key, if any (closed states are resolved, blocked, escalated, failed); with a receiver
/// (v1.25), the open case of that receiver for the key, since the same message goes to every receiver the production
/// feeds and each failed delivery is a case of its own.
ClassMethod FindOpen(operationKey As %String, receiver As %String = "") As Shutter.Store.Case
{
    Set id = ""
    If receiver = "" {
        &sql(SELECT TOP 1 ID INTO :id FROM Shutter_Store."Case" WHERE OperationKey = :operationKey AND State NOT IN ('resolved','blocked','escalated','failed') ORDER BY ID DESC)
    } Else {
        &sql(SELECT TOP 1 ID INTO :id FROM Shutter_Store."Case" WHERE OperationKey = :operationKey AND Receiver = :receiver AND State NOT IN ('resolved','blocked','escalated','failed') ORDER BY ID DESC)
    }
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// A case by its public id.
ClassMethod ByCaseId(caseId As %String) As Shutter.Store.Case
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Shutter_Store."Case" WHERE CaseId = :caseId)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// Move the case to a new state. The expected version, when given, must match; the version then
/// increments. Appends the CaseEvent in the same transaction. Under the case's lock, a copy whose version is no
/// longer the stored one (another job moved the case after this copy was read) changes nothing.
Method Transition(toState As %String, text As %String = "", actor As %String = "system", ref As %String = "", expectedVersion As %Integer = "") As %Status
{
    If (expectedVersion '= "") && (expectedVersion '= ..Version) {
        Quit $$$ERROR($$$GeneralError, "Stale case version: expected " _ expectedVersion _ ", current " _ ..Version)
    }
    Set sc = ..Lock()
    Quit:$$$ISERR(sc) sc
    Set level = $TLEVEL
    Try {
        Set stored = ..StoredVersion()
        If (stored '= "") && (stored '= ..Version) {
            Set sc = $$$ERROR($$$GeneralError, "Stale case version: this copy of " _ ..CaseId _ " is at version " _ ..Version _ ", the stored case at " _ stored)
        } Else {
            Set from = ..State
            Set ..State = toState
            Set ..Version = ..Version + 1
            Set ..UpdatedAt = ##class(Shutter.Util.Time).NowUTC()
            If $LISTFIND($LISTBUILD("resolved", "blocked", "escalated", "failed"), toState) Set ..ClosedAt = ..UpdatedAt
            TSTART
            Set sc = ..%Save()
            If $$$ISOK(sc) Set sc = ##class(Shutter.Store.CaseEvent).Append($THIS, "state", from, toState, text, actor, ref)
            If $$$ISOK(sc) { TCOMMIT } Else { TROLLBACK }
        }
    } Catch ex {
        If $TLEVEL > level TROLLBACK 1
        Set sc = ex.AsStatus()
    }
    Do ..Unlock()
    // A case that closes releases the cases waiting on it (v1.28): each is reinvestigated on fresh evidence.
    If $$$ISOK(sc) && $LISTFIND($LISTBUILD("resolved", "blocked", "escalated", "failed"), toState) Do ..ReleaseWaiting(toState)
    Quit sc
}

/// The blocked or escalated cases whose WaitsOnCase names this case are reopened through the production (Shutter.Msg.Reinvestigate to
/// the Case Workflow), so each plans afresh on the bed as it is now: the gate passes the resend when the occupant has left,
/// and escalates the case when this one ended without freeing the bed. Returns how many were released; never fails the
/// caller (a production that is not running leaves them blocked, with the wait on the case for a person to see).
Method ReleaseWaiting(toState As %String) As %Integer
{
    Quit ..Reopen("WaitsOnCase", ..CaseId, "case " _ ..CaseId _ " about the bed's occupant closed as " _ toState _ "; the bed is checked again")
}

/// The blocked or escalated cases waiting for a message (WaitsOnMessage, v1.29) are reopened once it has been delivered,
/// whatever the receiver answered: the fresh evidence then shows the later event applied, or its own case, and the gate
/// decides. Returns how many were released.
ClassMethod ReleaseWaitingOnMessage(controlId As %String, outcome As %String = "", host As Ens.Host = "", target As %String = "Case Workflow") As %Integer
{
    If controlId = "" Quit 0
    Quit ..Reopen("WaitsOnMessage", controlId, "message " _ controlId _ " of this encounter was delivered" _ $SELECT(outcome '= "": " (" _ outcome _ ")", 1: "") _ "; the resend is checked again", host, target)
}

/// The cases waiting on this header (WaitsOnEngine), reopened now that the engine has settled it and sent nothing.
ClassMethod ReleaseWaitingOnEngine(headerKey As %String, host As Ens.Host = "", target As %String = "Case Workflow") As %Integer
{
    Quit $SELECT(headerKey = "": 0, 1: ..Reopen("WaitsOnEngine", headerKey, "the engine has finished with header " _ headerKey _ "; the resend is checked again", host, target))
}

/// Release a case held for a schema that is loaded now (v1.34): reopened as a case waiting on a message is, with the reason,
/// and its HeldSchema cleared, so the check releases it once (the gate may block the re-plan for another reason, and the case
/// is then a blocked case like any other, not a held one). The field is cleared with NULL (v1.39): SQL's '' is stored as
/// $CHAR(0), which the opened case, its JSON and the publisher's case tool would then carry as a one-character schema.
ClassMethod ReleaseHeld(caseId As %String, category As %String, where As %String, host As Ens.Host = "", target As %String = "Case Workflow") As %Integer
{
    If caseId = "" Quit 0
    Set n = ..Reopen("CaseId", caseId, "the schema " _ category _ " is loaded in " _ where _ " now, found by the Case Releaser's sweep; the message is read again", host, target)
    If n > 0 {
        &sql(UPDATE Shutter_Store."Case" SET HeldSchema = NULL WHERE CaseId = :caseId)
    }
    Quit n
}

/// Reopen every blocked or escalated case whose field names the value, with an id-only Reinvestigate to the Case Workflow:
/// sent from the given host (the Case Releaser, v1.35), or through the API service when there is none (a caller outside
/// the production, or the Ward operation's release of Shutter's own feed).
ClassMethod Reopen(field As %String, value As %String, reason As %String, host As Ens.Host = "", target As %String = "Case Workflow") As %Integer [ Private ]
{
    Set n = 0
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT CaseId FROM Shutter_Store.""Case"" WHERE " _ field _ " = ? AND State IN ('blocked', 'escalated') ORDER BY ID", value)
        While rs.%Next() {
            Set msg = ##class(Shutter.Msg.Reinvestigate).%New()
            Set msg.CaseId = rs.%Get("CaseId"), msg.RequestedBy = "system", msg.Reason = reason
            If $ISOBJECT(host) {
                Set sc = host.SendRequestAsync($SELECT(target '= "": target, 1: "Case Workflow"), msg)
                If $$$ISOK(sc) Set n = n + 1
                Continue
            }
            Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .service)
            If $$$ISERR(sc) || '$ISOBJECT(service) Quit
            Set service.Target = "Case Workflow", service.Async = 1
            Set sc = service.ProcessInput(msg)
            If $$$ISOK(sc) Set n = n + 1
        }
    } Catch ex {
    }
    Quit n
}

/// The case's lock (^Shutter.CaseLock), taken around the read and write of the stored case by Transition, Note,
/// SetIncident and SetSnapshot, and by the case workflow's Park; ten seconds at most to get it. A case not yet saved
/// needs none. A plain whole save (the case's opening, a release from an incident, a reopening) does not take it, and
/// %OnBeforeSave keeps the incident and the current snapshot as stored, which only SetIncident and SetSnapshot write.
Method Lock() As %Status
{
    Set id = ..%Id()
    If id = "" Quit $$$OK
    LOCK +^Shutter.CaseLock(id):10
    If '$TEST Quit $$$ERROR($$$GeneralError, "Case " _ ..CaseId _ " is locked by another job")
    Quit $$$OK
}

Method Unlock()
{
    Set id = ..%Id()
    If id '= "" LOCK -^Shutter.CaseLock(id)
}

/// The version as stored, or "" for a case not saved yet.
Method StoredVersion() As %String [ Private ]
{
    Set id = ..%Id(), v = ""
    If id = "" Quit ""
    &sql(SELECT Version INTO :v FROM Shutter_Store."Case" WHERE ID = :id)
    If SQLCODE '= 0 Quit ""
    Quit v
}

/// The incident that holds the case as stored (this copy may be older), or "".
Method StoredIncident() As Shutter.Store.Incident
{
    Set id = ..%Id(), iid = ""
    If id = "" Quit ""
    &sql(SELECT Incident INTO :iid FROM Shutter_Store."Case" WHERE ID = :id)
    If (SQLCODE '= 0) || (iid = "") Quit ""
    Quit ##class(Shutter.Store.Incident).%OpenId(iid)
}

/// Make the case a member of an incident, or of none (""), writing that field alone under the case's lock, in the
/// stored case and in this copy. With unlessState, a case whose stored state is that one keeps its membership (a case
/// that parked meanwhile stays); changed says whether the membership was written.
Method SetIncident(incident As Shutter.Store.Incident, unlessState As %String = "", Output changed As %Boolean) As %Status
{
    Set changed = 0, id = ..%Id(), iid = $SELECT($ISOBJECT(incident): incident.%Id(), 1: "")
    If id = "" Quit $$$ERROR($$$GeneralError, "The case is not saved yet")
    Set sc = ..Lock()
    Quit:$$$ISERR(sc) sc
    Set state = ""
    If unlessState '= "" {
        &sql(SELECT State INTO :state FROM Shutter_Store."Case" WHERE ID = :id)
    }
    If (unlessState = "") || (state '= unlessState) {
        &sql(UPDATE Shutter_Store."Case" SET Incident = :iid WHERE ID = :id)
        If SQLCODE < 0 {
            Set sc = $$$ERROR($$$SQLError, SQLCODE, $GET(%msg))
        } Else {
            Do ..IncidentSetObjectId(iid)
            Set changed = 1
        }
    }
    Do ..Unlock()
    Quit sc
}

/// Make a snapshot the case's current one, writing that field alone under the case's lock, in the stored case and in
/// this copy.
Method SetSnapshot(snapshot As Shutter.Store.Snapshot) As %Status
{
    Set id = ..%Id(), sid = $SELECT($ISOBJECT(snapshot): snapshot.%Id(), 1: "")
    If id = "" Quit $$$ERROR($$$GeneralError, "The case is not saved yet")
    Set sc = ..Lock()
    Quit:$$$ISERR(sc) sc
    &sql(UPDATE Shutter_Store."Case" SET CurrentSnapshot = :sid WHERE ID = :id)
    If SQLCODE < 0 {
        Set sc = $$$ERROR($$$SQLError, SQLCODE, $GET(%msg))
    } Else {
        Do ..CurrentSnapshotSetObjectId(sid)
    }
    Do ..Unlock()
    Quit sc
}

/// A whole save keeps the incident and the current snapshot as stored: only SetIncident and SetSnapshot write them, so
/// a copy read before either changed never writes back the older value.
Method %OnBeforeSave(insert As %Boolean) As %Status [ Private, ServerOnly = 1 ]
{
    If insert Quit $$$OK
    Set id = ..%Id(), inc = "", snap = ""
    &sql(SELECT Incident, CurrentSnapshot INTO :inc, :snap FROM Shutter_Store."Case" WHERE ID = :id)
    If SQLCODE '= 0 Quit $$$OK
    If inc '= ..IncidentGetObjectId() Do ..IncidentSetObjectId(inc)
    If snap '= ..CurrentSnapshotGetObjectId() Do ..CurrentSnapshotSetObjectId(snap)
    Quit $$$OK
}

/// Close a case the team handled by hand (T31, 2.6): an escalated, blocked or failed case resolves with disposition
/// handled_by_hand, and its state event names the reason and, when the case was escalated, the latest escalation
/// it followed. Every draft or queued escalation email of the case is cancelled, whatever its seq, and the event says
/// how many (a failed send stays failed, as history). The current approval, if any, is revoked as a reopening revokes
/// it. An open Workflow task is the workflow's to cancel (Shutter.Process.CaseWorkflow.OnClose), since the engine
/// answers the instance that raised it.
ClassMethod CloseByHand(case As Shutter.Store.Case, reason As %String, actor As %String, expectedVersion As %Integer = "") As %Status
{
    If '$ISOBJECT(case) Quit $$$ERROR($$$GeneralError, "No case to close")
    If '$LISTFIND($LISTBUILD("escalated", "blocked", "failed"), case.State) Quit $$$ERROR($$$GeneralError, "The case is " _ case.State _ "; only an escalated, blocked or failed case can be marked handled")
    Set who = $SELECT(actor = "": "a person", 1: actor)
    Set reason = $EXTRACT(reason, 1, 2000)
    // The escalation the team worked from: the latest one, whatever its state.
    Set cid = case.%Id(), seq = "", followed = "", ref = ""
    &sql(SELECT MAX(Seq) INTO :seq FROM Shutter_Store.Escalation WHERE "Case" = :cid)
    If (SQLCODE '= 0) Set seq = ""
    If +seq > 0 {
        Set esc = ##class(Shutter.Store.Escalation).BySeq(case, +seq)
        Set followed = "; after escalation " _ (+seq)
        If $ISOBJECT(esc) Set followed = followed _ $SELECT(esc.TeamName '= "": " to " _ esc.TeamName, 1: "") _ " (" _ esc.ShownState() _ ")"
        Set ref = "escalation:" _ (+seq)
    }
    // An email not yet sent would tell the team to correct a case already handled: every draft or queued one is
    // cancelled, not only the latest (CancelPendingEscalations; an abandon cancels them the same way).
    Set cancelled = ..CancelPendingEscalations(case)
    If cancelled > 0 Set followed = followed _ "; " _ cancelled _ " pending email" _ $SELECT(cancelled = 1: "", 1: "s") _ " cancelled"
    If $ISOBJECT(case.CurrentApproval) && 'case.CurrentApproval.Revoked Do case.CurrentApproval.Revoke(who _ ": the case was handled by hand")
    Set case.Disposition = "handled_by_hand"
    Set case.Headline = "Handled by the team. " _ ##class(Shutter.Util.Json).Clip(reason, 200)
    Set case.Outcome = "Handled by hand, recorded by " _ who _ ": " _ reason
    Quit case.Transition("resolved", "Handled by hand: " _ reason _ followed, who, ref, expectedVersion)
}

/// Cancel every draft or queued escalation email of a case, whatever its seq, so the team is not asked to correct a
/// case already closed (the mail operation skips a queued row cancelled before it reads it; a failed send stays
/// failed, as history). Returns how many were cancelled.
ClassMethod CancelPendingEscalations(case As Shutter.Store.Case) As %Integer
{
    Set cancelled = 0, cid = case.%Id()
    If cid = "" Quit 0
    Set pending = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Escalation WHERE ""Case"" = ? AND State IN ('draft', 'queued') ORDER BY Seq", cid)
    While pending.%Next() {
        Set e = ##class(Shutter.Store.Escalation).%OpenId(pending.%Get("ID"))
        Continue:'$ISOBJECT(e)
        Set e.State = "cancelled"
        If $$$ISOK(e.%Save()) Set cancelled = cancelled + 1
    }
    Quit cancelled
}

/// The quiet minutes after which a working case counts as left behind by its workflow (CONTRACTS 5): the abandon
/// route's busy rule, the start sweep's note and the Doctor read it from ^Shutter.Config("abandonAfterMinutes"), 15
/// when unset. It must exceed the longest wait the workflow arms (the board timeout, 600 s), so a value of 10 or less
/// reads as 11.
ClassMethod AbandonAfterMinutes() As %Integer
{
    Set n = +$GET(^Shutter.Config("abandonAfterMinutes"))
    If n <= 0 Quit 15
    If n < 11 Quit 11
    Quit n
}

/// How many messages of the case's workflow are in flight, which tells a busy case from one left behind (CONTRACTS 5).
/// For the case's workflow session (its incident's for a grouped case, which the incident's instance drives): every
/// Ens.MessageHeader created, queued or deferred, whatever its age (a deferred one is an approval task a person must
/// answer: the case waits, and the plan is rejected instead of the case abandoned), and a delivered one (taken by its
/// target, not yet answered) created within the last <var>minutes</var> (AbandonAfterMinutes when not given). A case
/// with no session yet is judged by its last state event alone: busy while that is younger than the minutes. Never by
/// UpdatedAt, which a note writes (the start sweep's note would make every stranded case look fresh). newestAt is the
/// newest header's time (the state event's for a case with no session) as ISO UTC, deferred 1 when a deferred header
/// exists, session the workflow session judged ("" when the state event decided).
ClassMethod InFlight(case As Shutter.Store.Case, minutes As %Integer = "", Output newestAt As %String, Output deferred As %Boolean, Output session As %String) As %Integer
{
    Set newestAt = "", deferred = 0, session = ""
    If '$ISOBJECT(case) Quit 0
    If (minutes = "") || (+minutes <= 0) Set minutes = ..AbandonAfterMinutes()
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set cutoff = ##class(Shutter.Util.Time).FromNow(-(minutes * 60))
    Set ws = case.WorkflowSessionId
    If case.State = "grouped" {
        Set inc = case.StoredIncident()
        If $ISOBJECT(inc) && (inc.WorkflowSessionId '= "") Set ws = inc.WorkflowSessionId
    }
    If ws = "" {
        // No session yet: the last state event's time stands for the workflow's last step. A time with milliseconds
        // ("...:28.123Z") is read to the second.
        Set id = case.%Id(), at = ""
        If id = "" Quit 0
        &sql(SELECT TOP 1 "At" INTO :at FROM Shutter_Store.CaseEvent WHERE "Case" = :id AND Kind = 'state' ORDER BY Seq DESC)
        If (SQLCODE '= 0) || (at = "") Quit 0
        Set newestAt = at
        Set age = ##class(Shutter.Util.Time).SecondsBetween($PIECE($PIECE(at, "Z", 1), ".", 1) _ "Z", now)
        Quit $SELECT(age < (minutes * 60): 1, 1: 0)
    }
    Set session = ws
    // Header Status is Ens.DataType.MessageStatus: 1 Created, 2 Queued, 3 Delivered, 6 Deferred (4 Discarded, 8 Error
    // and 9 Completed are over). TimeCreated is UTC in the ODBC form, "yyyy-mm-dd hh:mm:ss.fff".
    Set odbcCutoff = $TRANSLATE($PIECE(cutoff, "Z", 1), "T", " ")
    Set n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS n, SUM(CASE WHEN Status = 6 THEN 1 ELSE 0 END) AS deferred FROM Ens.MessageHeader WHERE SessionId = ? AND (Status IN (1, 2, 6) OR (Status = 3 AND TimeCreated >= ?))", ws, odbcCutoff)
    If rs.%Next() {
        Set n = +rs.%Get("n")
        Set deferred = (+rs.%Get("deferred") > 0)
    }
    Set rn = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT MAX(TimeCreated) AS t FROM Ens.MessageHeader WHERE SessionId = ?", ws)
    If rn.%Next() && (rn.%Get("t") '= "") Set newestAt = $TRANSLATE($PIECE(rn.%Get("t"), ".", 1), " ", "T") _ "Z"
    Quit n
}

/// Give up a case the workflow left in a working state (CONTRACTS 5): an approver's record that nothing more happens
/// to it. Refused for a closed case (resolved, blocked, escalated or failed: it is marked handled or reinvestigated
/// instead) and, before anything changes, for an expected version that is not the case's. The current approval, if
/// any, is revoked, every draft or queued escalation email is cancelled as a hand close cancels them, the disposition
/// is abandoned, and the case fails with the reason, the actor and the version check; the state event is the record.
/// Whether the case is busy or left behind is the route's question (InFlight), asked before the request reaches the
/// workflow; an open approval task is the workflow's to cancel (Shutter.Process.CaseWorkflow.OnAbandon). A failed case
/// reopens through a reinvestigation, so a wrong abandon is recoverable.
ClassMethod Abandon(case As Shutter.Store.Case, reason As %String, actor As %String, expectedVersion As %Integer = "") As %Status
{
    If '$ISOBJECT(case) Quit $$$ERROR($$$GeneralError, "No case to abandon")
    If case.IsClosed() Quit $$$ERROR($$$GeneralError, "The case is " _ case.State _ "; a closed case is marked handled (/close) or reopened (/reinvestigate), not abandoned")
    If (expectedVersion '= "") && (expectedVersion '= case.Version) Quit $$$ERROR($$$GeneralError, "Stale case version: expected " _ expectedVersion _ ", current " _ case.Version)
    Set who = $SELECT(actor = "": "a person", 1: actor)
    Set reason = $ZSTRIP($EXTRACT(reason, 1, 2000), "<>W")
    Set from = case.State
    Set cancelled = ..CancelPendingEscalations(case)
    If $ISOBJECT(case.CurrentApproval) && 'case.CurrentApproval.Revoked Do case.CurrentApproval.Revoke(who _ ": the case was abandoned")
    Set case.Disposition = "abandoned"
    Set case.Headline = "Abandoned by " _ who _ ". " _ ##class(Shutter.Util.Json).Clip(reason, 200)
    Set case.Outcome = "Abandoned, recorded by " _ who _ ": " _ reason _ ". The workflow stopped in " _ from _ "; nothing more is sent"
    Set text = "Abandoned from " _ from _ ": " _ reason
    If cancelled > 0 Set text = text _ "; " _ cancelled _ " pending email" _ $SELECT(cancelled = 1: "", 1: "s") _ " cancelled"
    Quit case.Transition("failed", text, who, "", expectedVersion)
}

/// At the production's start, note every case still in a working state (Shutter.Production.OnStart): the production
/// started while the case was <state>; work in flight resumes after a clean stop and start (queued requests keep their
/// place and suspended alarms reload); if the case does not move on within the quiet minutes, an approver can abandon
/// it. Marking only: nothing here closes a case, since a clean restart resumes the work and a failure written here
/// would be wrong. The note is an error-kind event, the audit trail of the restart; the version does not move. Returns
/// how many cases were noted.
ClassMethod MarkOpenAtStart() As %Integer
{
    Set n = 0, now = ##class(Shutter.Util.Time).NowUTC(), minutes = ..AbandonAfterMinutes()
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.""Case"" WHERE State NOT IN ('resolved', 'blocked', 'escalated', 'failed') ORDER BY ID")
    While rs.%Next() {
        Set case = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(case)
        Set text = "The production started at " _ now _ " while this case was " _ case.State _ ". Work in flight resumes when the production was stopped cleanly; if the case does not move on within " _ minutes _ " minutes, an approver can abandon it (POST /cases/" _ case.CaseId _ "/abandon, or ""Abandon the case"" on the case page)"
        If $$$ISOK(case.Note("error", text, "system", "start:" _ now)) Set n = n + 1
    }
    Quit n
}

/// Record something that is not a state change: a note, an artefact, an error. Only the time of the change is written
/// to the stored case, never this copy, so a job holding an older copy (the evidence collector, the gate) writes nothing
/// back over newer changes; the version does not move. A case not saved yet is saved whole.
Method Note(kind As %String, text As %String, actor As %String = "system", ref As %String = "") As %Status
{
    Set now = ##class(Shutter.Util.Time).NowUTC(), id = ..%Id()
    If id = "" {
        Set ..UpdatedAt = now
        TSTART
        Set sc = ..%Save()
        If $$$ISOK(sc) Set sc = ##class(Shutter.Store.CaseEvent).Append($THIS, kind, "", "", text, actor, ref)
        If $$$ISOK(sc) { TCOMMIT } Else { TROLLBACK }
        Quit sc
    }
    Set sc = ..Lock()
    Quit:$$$ISERR(sc) sc
    // A copy that had no unsaved change before the note has none after it: marked changed, it would be written whole
    // by the next save of a record that refers to it (a snapshot, a plan), over whatever moved the case meanwhile.
    Set clean = '..%IsModified()
    Set level = $TLEVEL
    Try {
        TSTART
        &sql(UPDATE Shutter_Store."Case" SET UpdatedAt = :now WHERE ID = :id)
        If SQLCODE < 0 {
            Set sc = $$$ERROR($$$SQLError, SQLCODE, $GET(%msg))
        } Else {
            Set i%UpdatedAt = now
            Set sc = ##class(Shutter.Store.CaseEvent).Append($THIS, kind, "", "", text, actor, ref)
        }
        If $$$ISOK(sc) { TCOMMIT } Else { TROLLBACK }
    } Catch ex {
        If $TLEVEL > level TROLLBACK 1
        Set sc = ex.AsStatus()
    }
    If clean Do ..%SetModified(0)
    Do ..Unlock()
    Quit sc
}

/// True when the case is closed.
Method IsClosed() As %Boolean
{
    Quit ''$LISTFIND($LISTBUILD("resolved", "blocked", "escalated", "failed"), ..State)
}

/// The next public id, C-000001 onwards.
ClassMethod NextId() As %String [ Private ]
{
    Set n = $INCREMENT(^Shutter.Counter("case"))
    Quit "C-" _ $TRANSLATE($JUSTIFY(n, 6), " ", "0")
}

/// A one-line description of the failure for the headline. The four movements keep their wording ("The transfer to
/// WARD-B of 2026-10-15 09:20:00 for encounter ENC-1001 was not delivered"); a cancel reads "The cancellation of the
/// transfer to WARD-B at ...", a merge "The merge of <prior patient id> into <patient id> at ...", and the encounter
/// clause is left out when the key's encounter piece is the literal "-" or empty (no visit number).
ClassMethod DescribeFailure(case As Shutter.Store.Case) As %String
{
    // An order, a result or a document (v1.45): the message may be sound, so the words say what the receiver did.
    If case.NotModelled() {
        Set to = $SELECT(case.Receiver '= "": case.Receiver, 1: "the receiver")
        Set how = $CASE(case.FailureOutcome, "uncertain": "may have reached " _ to _ ", which did not answer", "rejected": "was refused by " _ to, "error": "was not delivered to " _ to, : "failed at " _ to)
        Quit "The " _ case.Event _ " message of " _ $REPLACE($PIECE(case.EventTime, "Z", 1), "T", " ") _ $SELECT((case.EncounterId = "-") || (case.EncounterId = ""): "", 1: " for encounter " _ case.EncounterId) _ " " _ how
    }
    Set what = $CASE(case.Event, "admit": "admission", "transfer": "transfer to " _ case.Ward _ $SELECT(case.Bed '= "": " bed " _ case.Bed, 1: ""), "discharge": "discharge", "update": "update", "merge": $SELECT(case.PriorPatientId '= "": "merge of " _ case.PriorPatientId _ " into " _ case.PatientId, 1: "merge into " _ case.PatientId), "cancel_admit": "cancellation of the admission", "cancel_transfer": "cancellation of the transfer" _ $SELECT(case.Ward '= "": " to " _ case.Ward, 1: ""), "cancel_discharge": "cancellation of the discharge", "register": "registration", "preadmit": "pre-admission", "person_add": "person record", "person_update": "person update", "": "message", : case.Event _ " message")
    Set when = $REPLACE($PIECE(case.EventTime, "Z", 1), "T", " ")
    Set how = $CASE(case.FailureKind, "delivery_failed": "was not delivered", "uncertain_outcome": "has an uncertain outcome", "rejected": "was rejected", "unmappable": "could not be mapped to an operation for the downstream system", "withheld": $SELECT(case.Event = "merge": "was withheld by the site's policy", 1: "was withheld: the receiver cannot reverse it"), "unreadable": "could not be read against an HL7 schema where it arrived", : "failed")
    // A cancel or a merge happens at its time; the movements keep "of".
    Set joiner = $SELECT((case.Event = "merge") || ($EXTRACT(case.Event, 1, 7) = "cancel_"): " at ", 1: " of ")
    Set where = $SELECT((case.EncounterId = "-") || (case.EncounterId = ""): "", 1: " for encounter " _ case.EncounterId)
    Quit "The " _ what _ joiner _ when _ where _ " " _ how
}

/// Whether the case is for a message Shutter does not model: an order, a result or a document (v1.42). Its kind says
/// unmappable because there is no operation to resend; the message itself may be sound, so nothing here may blame it.
Method NotModelled() As %Boolean
{
    Quit ($EXTRACT(..FailureText, 1, 16) = "This message is ") && ($PIECE(..FailureText, ":", 1) [ ", not ADT")
}

/// The case's events, oldest first, as a dynamic array.
Method Events() As %DynamicArray
{
    Set out = []
    Set id = ..%Id()
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? ORDER BY Seq", id)
    While rs.%Next() {
        Set ev = ##class(Shutter.Store.CaseEvent).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(ev)
        Do ev.%JSONExportToString(.json)
        Do out.%Push(##class(%DynamicObject).%FromJSON(json))
    }
    Quit out
}

Storage Default
{
<Data name="CaseDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>CaseId</Value>
</Value>
<Value name="3">
<Value>OperationKey</Value>
</Value>
<Value name="4">
<Value>State</Value>
</Value>
<Value name="5">
<Value>Version</Value>
</Value>
<Value name="6">
<Value>Mode</Value>
</Value>
<Value name="7">
<Value>FailureKind</Value>
</Value>
<Value name="8">
<Value>FailureText</Value>
</Value>
<Value name="9">
<Value>EncounterId</Value>
</Value>
<Value name="10">
<Value>PatientId</Value>
</Value>
<Value name="11">
<Value>PatientIdAuthority</Value>
</Value>
<Value name="12">
<Value>SourceSystem</Value>
</Value>
<Value name="13">
<Value>SourceMessageId</Value>
</Value>
<Value name="14">
<Value>Event</Value>
</Value>
<Value name="15">
<Value>Ward</Value>
</Value>
<Value name="16">
<Value>EventTime</Value>
</Value>
<Value name="17">
<Value>Scenario</Value>
</Value>
<Value name="18">
<Value>EnsSessionId</Value>
</Value>
<Value name="19">
<Value>SourceHeaderId</Value>
</Value>
<Value name="20">
<Value>WorkflowSessionId</Value>
</Value>
<Value name="21">
<Value>Disposition</Value>
</Value>
<Value name="22">
<Value>Headline</Value>
</Value>
<Value name="23">
<Value>Outcome</Value>
</Value>
<Value name="24">
<Value>OpenedAt</Value>
</Value>
<Value name="25">
<Value>UpdatedAt</Value>
</Value>
<Value name="26">
<Value>ClosedAt</Value>
</Value>
<Value name="27">
<Value>CurrentSnapshot</Value>
</Value>
<Value name="28">
<Value>CurrentPlan</Value>
</Value>
<Value name="29">
<Value>CurrentApproval</Value>
</Value>
<Value name="30">
<Value>Receiver</Value>
</Value>
<Value name="31">
<Value>Incident</Value>
</Value>
<Value name="32">
<Value>CandidateEntry</Value>
</Value>
<Value name="33">
<Value>FailureOutcome</Value>
</Value>
<Value name="34">
<Value>FailureReasonCode</Value>
</Value>
<Value name="35">
<Value>FailureHttpStatus</Value>
</Value>
<Value name="36">
<Value>PriorPatientId</Value>
</Value>
<Value name="37">
<Value>PriorPatientIdAuthority</Value>
</Value>
<Value name="38">
<Value>PriorEncounterId</Value>
</Value>
<Value name="39">
<Value>MergeGroups</Value>
</Value>
<Value name="40">
<Value>SourceNamespace</Value>
</Value>
<Value name="41">
<Value>SourceProduction</Value>
</Value>
<Value name="42">
<Value>SourceRoute</Value>
</Value>
<Value name="43">
<Value>OriginHeaderId</Value>
</Value>
<Value name="44">
<Value>Bed</Value>
</Value>
<Value name="45">
<Value>WaitsOnCase</Value>
</Value>
<Value name="46">
<Value>WaitsOnMessage</Value>
</Value>
<Value name="47">
<Value>HeldSchema</Value>
</Value>
<Value name="48">
<Value>RetryAfterUntil</Value>
</Value>
<Value name="49">
<Value>FollowsCase</Value>
</Value>
<Value name="50">
<Value>LeadSignature</Value>
</Value>
<Value name="51">
<Value>ScenarioRecorded</Value>
</Value>
<Value name="52">
<Value>WaitsOnEngine</Value>
</Value>
<Value name="53">
<Value>DocumentJSON</Value>
</Value>
<Value name="54">
<Value>FurtherReleaseJSON</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.CaseD</DataLocation>
<DefaultData>CaseDefaultData</DefaultData>
<IdLocation>^Shutter.Store.CaseD</IdLocation>
<IndexLocation>^Shutter.Store.CaseI</IndexLocation>
<StreamLocation>^Shutter.Store.CaseS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
