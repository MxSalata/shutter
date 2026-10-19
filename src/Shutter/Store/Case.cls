/// A recovery case: one failed or uncertain delivery, identified by its operation key, with a
/// lifecycle whose every transition is a CaseEvent. Changes carry an expected version so that two
/// actors cannot both advance the same case.
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
Property FailureKind As %String(%JSONFIELDNAME = "failureKind", MAXLEN = 32, VALUELIST = ",delivery_failed,uncertain_outcome,rejected,unmappable,withheld");

Property FailureText As %String(%JSONFIELDNAME = "failureText", MAXLEN = 2000);

/// The connector's answer as recorded, not parsed from prose: its outcome, reason code and HTTP status (C3).
Property FailureOutcome As %String(%JSONFIELDNAME = "failureOutcome", MAXLEN = 32);

Property FailureReasonCode As %String(%JSONFIELDNAME = "failureReasonCode", MAXLEN = 100);

Property FailureHttpStatus As %Integer(%JSONFIELDNAME = "failureHttpStatus");

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

/// The incident the case belongs to, when many failures to the receiver were grouped (CONTRACTS 7).
Property Incident As Shutter.Store.Incident(%JSONINCLUDE = "none");

/// The demo scenario that produced the case (S1 to S6), when the scenario runner was running one;
/// recordings of agent runs for a scenario replay on any instance.
Property Scenario As %String(%JSONFIELDNAME = "scenario", MAXLEN = 32);

Index ScenarioIdx On Scenario;

/// The production session of the failed delivery: the Visual Trace link.
Property EnsSessionId As %String(%JSONFIELDNAME = "ensSessionId", MAXLEN = 20);

/// The Ens.MessageHeader id of the message whose delivery failed.
Property SourceHeaderId As %String(%JSONFIELDNAME = "sourceHeaderId", MAXLEN = 20);

/// The production session of the case workflow, once it runs.
Property WorkflowSessionId As %String(%JSONFIELDNAME = "workflowSessionId", MAXLEN = 20);

/// The decided disposition: resend, reconcile, superseded, more_evidence, escalate; handled_by_hand when the team closed the case (CloseByHand).
Property Disposition As %String(%JSONFIELDNAME = "disposition", MAXLEN = 32);

/// The catalogue had no entry for this case's pattern (CONTRACTS 6.3): a reviewer may write one.
Property CandidateEntry As %Boolean(%JSONFIELDNAME = "candidateEntry") [ InitialExpression = 0 ];

/// One line for the queue: what happened and what was decided.
Property Headline As %String(%JSONFIELDNAME = "headline", MAXLEN = 500);

/// The closing summary.
Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 4000);

Property OpenedAt As %String(%JSONFIELDNAME = "openedAt", MAXLEN = 30);

Property UpdatedAt As %String(%JSONFIELDNAME = "updatedAt", MAXLEN = 30);

Index UpdatedIdx On UpdatedAt;

Property ClosedAt As %String(%JSONFIELDNAME = "closedAt", MAXLEN = 30);

Property CurrentSnapshot As Shutter.Store.Snapshot(%JSONFIELDNAME = "currentSnapshotId", %JSONREFERENCE = "ID");

Property CurrentPlan As Shutter.Store.Plan(%JSONFIELDNAME = "currentPlanId", %JSONREFERENCE = "ID");

Property CurrentApproval As Shutter.Store.Approval(%JSONFIELDNAME = "currentApprovalId", %JSONREFERENCE = "ID");

/// Open a case for an operation, or return the open one for the same key. The operation is the
/// downstream operation as built by Shutter.Util.OperationKey.FromHL7.
ClassMethod Open(op As %DynamicObject, failureKind As %String, failureText As %String, ensSessionId As %String, sourceHeaderId As %String, mode As %String, Output case As Shutter.Store.Case, Output opened As %Boolean) As %Status
{
    Set sc = $$$OK, opened = 0
    Set key = op."operation_key"
    Set case = ..FindOpen(key)
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
            If (newDigest '= "") && (oldDigest '= "") && (newDigest '= oldDigest) && 'case.IsClosed() {
                Set case.Headline = "Blocked: a further message for the same operation carries different content"
                Quit case.Transition("blocked", "PAYLOAD_CHANGED: a further failure for the same operation key carries different content (payload digest " _ $EXTRACT(newDigest, 1, 19) _ " against " _ $EXTRACT(oldDigest, 1, 19) _ "); the plan would write the first content, so nothing is dispatched and a person must decide. " _ failureText, "system", "ens:" _ sourceHeaderId)
            }
            Set sc = case.Note("note", "A further failure for the same operation: " _ failureText, "system", "ens:" _ sourceHeaderId)
            Quit sc
        }
    }
    Set case = ..%New()
    Set case.CaseId = ..NextId()
    Set case.OperationKey = key
    Set case.FailureKind = failureKind
    Set case.FailureText = $EXTRACT(failureText, 1, 2000)
    Set case.EncounterId = op."encounter_id"
    Set case.PatientId = op."patient_id"
    Set case.PatientIdAuthority = op."patient_id_authority"
    Set case.SourceSystem = op."source_system"
    Set case.SourceMessageId = ##class(Shutter.Util.Json).Str(op, "source_message_id")
    Set case.Event = op."event"
    Set case.Ward = ##class(Shutter.Util.Json).Str(op, "ward")
    Set case.PriorPatientId = ##class(Shutter.Util.Json).Str(op, "prior_patient_id")
    Set case.PriorPatientIdAuthority = ##class(Shutter.Util.Json).Str(op, "prior_patient_id_authority")
    Set case.PriorEncounterId = ##class(Shutter.Util.Json).Str(op, "prior_encounter_id")
    Set groups = ##class(Shutter.Util.Json).Str(op, "merge_groups")
    If groups '= "" Set case.MergeGroups = +groups
    Set case.EventTime = op."event_time"
    Set case.EnsSessionId = ensSessionId
    Set case.SourceHeaderId = sourceHeaderId
    Set case.Mode = $SELECT(mode = "": "board", 1: mode)
    Set case.Scenario = $GET(^Shutter.Config("scenario"))
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Set case.Headline = ..DescribeFailure(case)
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

/// Delete the closed cases whose closing is older than a time, with everything that hangs off them (events, snapshots
/// and their items, plans, approvals, rehearsals, gate decisions, attempts, verifications, agent runs and their tool
/// calls, chain items), and the closed incidents older than it with their chains, items, events and the cases they
/// held. Cases an open incident still holds stay. Returns how many cases went. Housekeeping only
/// (Shutter.Util.RetentionTask, switched on by a site): the record is the product.
ClassMethod PurgeClosedBefore(cutoff As %String) As %Integer
{
    Set n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.""Case"" WHERE ClosedAt IS NOT NULL AND ClosedAt < ? AND State IN ('resolved', 'blocked', 'escalated', 'failed') AND Incident IS NULL", cutoff)
    While rs.%Next() {
        If $$$ISOK(..PurgeCase(rs.%Get("ID"))) Set n = n + 1
    }
    Set ri = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Incident WHERE State = 'closed' AND ClosedAt IS NOT NULL AND ClosedAt < ?", cutoff)
    While ri.%Next() {
        Set iid = ri.%Get("ID"), ok = 1
        // Only its cases whose own closing is older than the cutoff: a case reopened and closed again later stays.
        Set rc = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.""Case"" WHERE Incident = ? AND State IN ('resolved', 'blocked', 'escalated', 'failed') AND ClosedAt IS NOT NULL AND ClosedAt < ?", iid, cutoff)
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
ClassMethod PurgeCase(id As %String) As %Status [ Private ]
{
    // The tool calls of the case's runs, and their counters.
    Set keys = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT EnsMessageId FROM Shutter_Store.AgentRun WHERE ""Case"" = ? AND EnsMessageId IS NOT NULL", id)
    While keys.%Next() { Kill ^Shutter.Counter("toolcall", keys.%Get("EnsMessageId")) }
    TSTART
    Set sc = ..Exec("DELETE FROM Shutter_Bridge.ToolCall WHERE RunKey IN (SELECT EnsMessageId FROM Shutter_Store.AgentRun WHERE ""Case"" = ? AND EnsMessageId IS NOT NULL)", id)
    For table = "Shutter_Store.CaseToken", "Shutter_Store.ChainItem", "Shutter_Store.Verification", "Shutter_Store.ExecutionAttempt", "Shutter_Store.Approval", "Shutter_Store.Rehearsal", "Shutter_Store.GateDecision", "Shutter_Store.Finding", "Shutter_Store.AgentRun", "Shutter_Store.Plan" {
        If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM " _ table _ " WHERE ""Case"" = ?", id)
    }
    If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM Shutter_Store.SnapshotItem WHERE Snapshot IN (SELECT ID FROM Shutter_Store.Snapshot WHERE ""Case"" = ?)", id)
    If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM Shutter_Store.Snapshot WHERE ""Case"" = ?", id)
    If $$$ISOK(sc) Set sc = ..Exec("DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
    If $$$ISOK(sc) Set sc = ..%DeleteId(id)
    If $$$ISOK(sc) { TCOMMIT } Else { TROLLBACK  Quit sc }
    Kill ^Shutter.Counter("event", id), ^Shutter.Counter("plan", id), ^Shutter.Counter("snapshot", id)
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

/// The open case for an operation key, if any (closed states are resolved, blocked, escalated, failed).
ClassMethod FindOpen(operationKey As %String) As Shutter.Store.Case
{
    Set id = ""
    &sql(SELECT TOP 1 ID INTO :id FROM Shutter_Store."Case" WHERE OperationKey = :operationKey AND State NOT IN ('resolved','blocked','escalated','failed') ORDER BY ID DESC)
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
/// increments. Appends the CaseEvent in the same transaction.
Method Transition(toState As %String, text As %String = "", actor As %String = "system", ref As %String = "", expectedVersion As %Integer = "") As %Status
{
    If (expectedVersion '= "") && (expectedVersion '= ..Version) {
        Quit $$$ERROR($$$GeneralError, "Stale case version: expected " _ expectedVersion _ ", current " _ ..Version)
    }
    Set from = ..State
    Set ..State = toState
    Set ..Version = ..Version + 1
    Set ..UpdatedAt = ##class(Shutter.Util.Time).NowUTC()
    If $LISTFIND($LISTBUILD("resolved", "blocked", "escalated", "failed"), toState) Set ..ClosedAt = ..UpdatedAt
    TSTART
    Set sc = ..%Save()
    If $$$ISOK(sc) Set sc = ##class(Shutter.Store.CaseEvent).Append($THIS, "state", from, toState, text, actor, ref)
    If $$$ISOK(sc) { TCOMMIT } Else { TROLLBACK }
    Quit sc
}

/// Close a case the team handled by hand (T31, 2.6): an escalated, blocked or failed case resolves with disposition
/// handled_by_hand, and its state event names the reason and, when the case was escalated, the latest escalation
/// it followed. The current approval, if any, is revoked as a reopening revokes it. An open Workflow task is the
/// workflow's to cancel (Shutter.Process.CaseWorkflow.OnClose), since the engine answers the instance that raised it.
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
        If $ISOBJECT(esc) Set followed = followed _ $SELECT(esc.TeamName '= "": " to " _ esc.TeamName, 1: "") _ " (" _ esc.State _ ")"
        // An email not yet sent would tell the team to correct a case already handled: it is cancelled.
        If $ISOBJECT(esc) && ((esc.State = "draft") || (esc.State = "queued")) { Set esc.State = "cancelled" Set esc.UpdatedAt = ##class(Shutter.Util.Time).NowUTC() Do esc.%Save() Set followed = followed _ ", cancelled" }
        Set ref = "escalation:" _ (+seq)
    }
    If $ISOBJECT(case.CurrentApproval) && 'case.CurrentApproval.Revoked Do case.CurrentApproval.Revoke(who _ ": the case was handled by hand")
    Set case.Disposition = "handled_by_hand"
    Set case.Headline = "Handled by the team. " _ $EXTRACT(reason, 1, 200)
    Set case.Outcome = "Handled by hand, recorded by " _ who _ ": " _ reason
    Quit case.Transition("resolved", "Handled by hand: " _ reason _ followed, who, ref, expectedVersion)
}

/// Record something that is not a state change: a note, an artefact, an error.
Method Note(kind As %String, text As %String, actor As %String = "system", ref As %String = "") As %Status
{
    Set ..UpdatedAt = ##class(Shutter.Util.Time).NowUTC()
    TSTART
    Set sc = ..%Save()
    If $$$ISOK(sc) Set sc = ##class(Shutter.Store.CaseEvent).Append($THIS, kind, "", "", text, actor, ref)
    If $$$ISOK(sc) { TCOMMIT } Else { TROLLBACK }
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
/// clause is left out when the key's encounter piece is the literal "-" (no visit number).
ClassMethod DescribeFailure(case As Shutter.Store.Case) As %String [ Private ]
{
    Set what = $CASE(case.Event, "admit": "admission", "transfer": "transfer to " _ case.Ward, "discharge": "discharge", "update": "update", "merge": $SELECT(case.PriorPatientId '= "": "merge of " _ case.PriorPatientId _ " into " _ case.PatientId, 1: "merge into " _ case.PatientId), "cancel_admit": "cancellation of the admission", "cancel_transfer": "cancellation of the transfer" _ $SELECT(case.Ward '= "": " to " _ case.Ward, 1: ""), "cancel_discharge": "cancellation of the discharge", "register": "registration", "preadmit": "pre-admission", "person_add": "person record", "person_update": "person update", "": "message", : case.Event _ " message")
    Set when = $REPLACE($PIECE(case.EventTime, "Z", 1), "T", " ")
    Set how = $CASE(case.FailureKind, "delivery_failed": "was not delivered", "uncertain_outcome": "has an uncertain outcome", "rejected": "was rejected", "unmappable": "could not be mapped to an operation for the downstream system", "withheld": $SELECT(case.Event = "merge": "was withheld by the site's policy", 1: "was withheld: the receiver cannot reverse it"), : "failed")
    // A cancel or a merge happens at its time; the movements keep "of".
    Set joiner = $SELECT((case.Event = "merge") || ($EXTRACT(case.Event, 1, 7) = "cancel_"): " at ", 1: " of ")
    Set where = $SELECT(case.EncounterId = "-": "", 1: " for encounter " _ case.EncounterId)
    Quit "The " _ what _ joiner _ when _ where _ " " _ how
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
</Data>
<DataLocation>^Shutter.Store.CaseD</DataLocation>
<DefaultData>CaseDefaultData</DefaultData>
<IdLocation>^Shutter.Store.CaseD</IdLocation>
<IndexLocation>^Shutter.Store.CaseI</IndexLocation>
<StreamLocation>^Shutter.Store.CaseS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
