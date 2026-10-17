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

Property FailureKind As %String(%JSONFIELDNAME = "failureKind", MAXLEN = 32, VALUELIST = ",delivery_failed,uncertain_outcome,rejected");

Property FailureText As %String(%JSONFIELDNAME = "failureText", MAXLEN = 2000);

Property EncounterId As %String(%JSONFIELDNAME = "encounterId", MAXLEN = 100);

Index EncounterIdx On EncounterId;

Property PatientId As %String(%JSONFIELDNAME = "patientId", MAXLEN = 100);

Property PatientIdAuthority As %String(%JSONFIELDNAME = "patientIdAuthority", MAXLEN = 100);

Property SourceSystem As %String(%JSONFIELDNAME = "sourceSystem", MAXLEN = 100);

Property SourceMessageId As %String(%JSONFIELDNAME = "sourceMessageId", MAXLEN = 200);

Property Event As %String(%JSONFIELDNAME = "event", MAXLEN = 16);

Property Ward As %String(%JSONFIELDNAME = "ward", MAXLEN = 100);

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

/// The decided disposition: resend, reconcile, superseded, more_evidence, escalate.
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
/// ward operation as built by Shutter.Util.OperationKey.FromHL7.
ClassMethod Open(op As %DynamicObject, failureKind As %String, failureText As %String, ensSessionId As %String, sourceHeaderId As %String, mode As %String, Output case As Shutter.Store.Case, Output opened As %Boolean) As %Status
{
    Set sc = $$$OK, opened = 0
    Set key = op."operation_key"
    Set case = ..FindOpen(key)
    If $ISOBJECT(case) {
        // An open case from before the last scenario reset belongs to an earlier run: close it.
        Set resetAt = $GET(^Shutter.Config("resetAt"))
        If (resetAt '= "") && (resetAt ]] case.OpenedAt) {
            Do case.Transition("failed", "Abandoned: a new scenario run reset the ward after this case was opened", "system")
            Set case = ""
        } Else {
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

/// A one-line description of the failure for the headline.
ClassMethod DescribeFailure(case As Shutter.Store.Case) As %String [ Private ]
{
    Set what = $CASE(case.Event, "admit": "admission", "transfer": "transfer to " _ case.Ward, "discharge": "discharge", "update": "update", : case.Event)
    Set when = $REPLACE($PIECE(case.EventTime, "Z", 1), "T", " ")
    Set how = $CASE(case.FailureKind, "delivery_failed": "was not delivered", "uncertain_outcome": "has an uncertain outcome", "rejected": "was rejected", : "failed")
    Quit "The " _ what _ " of " _ when _ " for encounter " _ case.EncounterId _ " " _ how
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
</Data>
<DataLocation>^Shutter.Store.CaseD</DataLocation>
<DefaultData>CaseDefaultData</DefaultData>
<IdLocation>^Shutter.Store.CaseD</IdLocation>
<IndexLocation>^Shutter.Store.CaseI</IndexLocation>
<StreamLocation>^Shutter.Store.CaseS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
