/// An immutable plan for a case: the disposition and, for a write, the exact action. A new version
/// is a new row; approvals bind to the digest, so an edited plan is never approved by accident.
Class Interlock.Store.Plan Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Interlock.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Property Version As %Integer(%JSONFIELDNAME = "version") [ Required ];

Index CaseVersionIdx On (Case, Version) [ Unique ];

Property Snapshot As Interlock.Store.Snapshot(%JSONFIELDNAME = "snapshotId", %JSONREFERENCE = "ID");

/// The digest of the canonical plan JSON (including the version and the snapshot digest).
Property Digest As %String(%JSONFIELDNAME = "digest", MAXLEN = 80);

Index DigestIdx On Digest;

/// resend, reconcile, superseded, more_evidence, escalate.
Property Disposition As %String(%JSONFIELDNAME = "disposition", MAXLEN = 32);

/// What the production would do: none, resend, reconcile.
Property ActionType As %String(%JSONFIELDNAME = "actionType", MAXLEN = 16);

Property OperationKey As %String(%JSONFIELDNAME = "operationKey", MAXLEN = 400);

/// The receiver version the write is conditional on.
Property ExpectedVersion As %Integer(%JSONFIELDNAME = "expectedVersion");

Property PayloadDigest As %String(%JSONFIELDNAME = "payloadDigest", MAXLEN = 80);

Property PreconditionsJSON As %String(%JSONFIELDNAME = "preconditions", MAXLEN = "");

Property EvidenceRefsJSON As %String(%JSONFIELDNAME = "evidenceRefs", MAXLEN = "");

Property DisagreementsJSON As %String(%JSONFIELDNAME = "disagreements", MAXLEN = "");

Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = 4000);

/// The catalogue entry the plan follows (E1, E2, ...), or "".
Property CatalogueEntry As %String(%JSONFIELDNAME = "catalogueEntry", MAXLEN = 16);

/// "preferred" or "alternative:<n>", or "".
Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 32);

Property Why As %String(%JSONFIELDNAME = "why", MAXLEN = 1000);

/// The whole plan as submitted and validated.
Property Json As %String(%JSONFIELDNAME = "plan", MAXLEN = "");

Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 30);

/// run:<id> for an agent, rules for the rules-only mode, user:<name> for an edit.
Property CreatedBy As %String(%JSONFIELDNAME = "createdBy", MAXLEN = 100);

/// Create the next plan version for a case from a validated plan object.
ClassMethod Create(case As Interlock.Store.Case, snapshot As Interlock.Store.Snapshot, plan As %DynamicObject, createdBy As %String, Output p As Interlock.Store.Plan) As %Status
{
    Set p = ..%New()
    Set p.Case = case, p.Snapshot = snapshot
    Set p.Version = $INCREMENT(^Interlock.Counter("plan", case.%Id()))
    Set p.Disposition = ##class(Interlock.Util.Json).Str(plan, "disposition")
    Set action = plan.%Get("action")
    If $ISOBJECT(action) {
        Set p.ActionType = ##class(Interlock.Util.Json).Str(action, "type", "none")
        Set p.OperationKey = ##class(Interlock.Util.Json).Str(action, "operation_key")
        Set ev = ##class(Interlock.Util.Json).Str(action, "expected_version")
        Set p.ExpectedVersion = $SELECT(ev = "": "", 1: +ev)
        Set p.PayloadDigest = ##class(Interlock.Util.Json).Str(action, "payload_digest")
    } Else {
        Set p.ActionType = "none"
    }
    Set p.PreconditionsJSON = ##class(Interlock.Util.Json).Text(plan.%Get("preconditions"))
    Set p.EvidenceRefsJSON = ##class(Interlock.Util.Json).Text(plan.%Get("evidence_refs"))
    Set p.DisagreementsJSON = ##class(Interlock.Util.Json).Text(plan.%Get("disagreements"))
    Set p.Summary = $EXTRACT(##class(Interlock.Util.Json).Str(plan, "summary"), 1, 4000)
    Set p.CatalogueEntry = ##class(Interlock.Util.Json).Str(plan, "catalogue_entry")
    Set p.Outcome = ##class(Interlock.Util.Json).Str(plan, "outcome")
    Set p.Why = $EXTRACT(##class(Interlock.Util.Json).Str(plan, "why"), 1, 1000)
    Set p.CreatedAt = ##class(Interlock.Util.Time).NowUTC()
    Set p.CreatedBy = createdBy
    // The digest covers the plan, its version and the snapshot it was made from.
    Set envelope = {}
    Set envelope.plan = plan
    Set envelope.version = p.Version
    Set envelope."snapshot_digest" = $SELECT($ISOBJECT(snapshot): snapshot.Digest, 1: "")
    Set envelope."case_id" = case.CaseId
    Set p.Json = plan.%ToJSON()
    Set p.Digest = ##class(Interlock.Util.Digest).OfObject(envelope)
    Quit p.%Save()
}

/// The parsed plan.
Method PlanObject() As %DynamicObject
{
    Quit ##class(%DynamicObject).%FromJSON(..Json)
}

/// True when the plan asks the production to write to the receiver.
Method IsWrite() As %Boolean
{
    Quit ..ActionType = "resend"
}

Storage Default
{
<Data name="PlanDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>Version</Value>
</Value>
<Value name="4">
<Value>Snapshot</Value>
</Value>
<Value name="5">
<Value>Digest</Value>
</Value>
<Value name="6">
<Value>Disposition</Value>
</Value>
<Value name="7">
<Value>ActionType</Value>
</Value>
<Value name="8">
<Value>OperationKey</Value>
</Value>
<Value name="9">
<Value>ExpectedVersion</Value>
</Value>
<Value name="10">
<Value>PayloadDigest</Value>
</Value>
<Value name="11">
<Value>PreconditionsJSON</Value>
</Value>
<Value name="12">
<Value>EvidenceRefsJSON</Value>
</Value>
<Value name="13">
<Value>DisagreementsJSON</Value>
</Value>
<Value name="14">
<Value>Summary</Value>
</Value>
<Value name="15">
<Value>Json</Value>
</Value>
<Value name="16">
<Value>CreatedAt</Value>
</Value>
<Value name="17">
<Value>CreatedBy</Value>
</Value>
<Value name="18">
<Value>CatalogueEntry</Value>
</Value>
<Value name="19">
<Value>Outcome</Value>
</Value>
<Value name="20">
<Value>Why</Value>
</Value>
</Data>
<DataLocation>^Interlock.Store.PlanD</DataLocation>
<DefaultData>PlanDefaultData</DefaultData>
<IdLocation>^Interlock.Store.PlanD</IdLocation>
<IndexLocation>^Interlock.Store.PlanI</IndexLocation>
<StreamLocation>^Interlock.Store.PlanS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
