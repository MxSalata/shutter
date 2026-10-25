/// A person's decision on an exact plan. It binds the plan digest, the snapshot digest, the gate
/// policy version, the rehearsal and the receiver version it expects, and it expires. Anything
/// that changes those makes it invalid; it can also be revoked. For an item released under an incident's approval it
/// also binds the incident plan's digest and the catalogue entry and outcome that approval covered for the item.
Class Shutter.Store.Approval Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Shutter.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Plan As Shutter.Store.Plan(%JSONFIELDNAME = "planId", %JSONREFERENCE = "ID") [ Required ];

Property PlanDigest As %String(%JSONFIELDNAME = "planDigest", MAXLEN = 80);

Property SnapshotDigest As %String(%JSONFIELDNAME = "snapshotDigest", MAXLEN = 80);

/// The approved snapshot's material digest: a refreshed snapshot with the same one keeps the approval (A7).
Property MaterialDigest As %String(%JSONFIELDNAME = "materialDigest", MAXLEN = 80);

Property PolicyVersion As %String(%JSONFIELDNAME = "policyVersion", MAXLEN = 32);

/// The site profile's version when the approval was given; a changed profile voids it (A8).
Property SiteProfileVersion As %String(%JSONFIELDNAME = "siteProfileVersion", MAXLEN = 32);

Property Rehearsal As Shutter.Store.Rehearsal(%JSONFIELDNAME = "rehearsalId", %JSONREFERENCE = "ID");

Property ExpectedVersion As %Integer(%JSONFIELDNAME = "expectedVersion");

/// The receiver's epoch at approval: it changes at every reset, so an approval from before a
/// reset cannot authorise a dispatch after it even when the version numbers match.
Property ReceiverEpoch As %Integer(%JSONFIELDNAME = "receiverEpoch");

Property Approver As %String(%JSONFIELDNAME = "approver", MAXLEN = 100);

Property Decision As %String(%JSONFIELDNAME = "decision", MAXLEN = 16, VALUELIST = ",approved,rejected");

Property DecidedAt As %String(%JSONFIELDNAME = "decidedAt", MAXLEN = 30);

Property ExpiresAt As %String(%JSONFIELDNAME = "expiresAt", MAXLEN = 30);

Property Revoked As %Boolean(%JSONFIELDNAME = "revoked") [ InitialExpression = 0 ];

Property RevokedAt As %String(%JSONFIELDNAME = "revokedAt", MAXLEN = 30);

Property RevokedBy As %String(%JSONFIELDNAME = "revokedBy", MAXLEN = 100);

/// The Workflow engine task that carried the decision.
Property WorkflowTaskId As %String(%JSONFIELDNAME = "workflowTaskId", MAXLEN = 50);

Property Comment As %String(%JSONFIELDNAME = "comment", MAXLEN = 2000);

/// Set only for an approval that stands in for an incident's or a chain's (CONTRACTS 7.4): the incident plan's digest
/// the person bound, and the catalogue entry and outcome that plan listed for this item. The dispatch gate refuses the
/// approval when the case's plan or its fresh evidence names another entry or outcome, or the incident's plan moved.
Property IncidentPlanDigest As %String(%JSONFIELDNAME = "incidentPlanDigest", MAXLEN = 80);

Property BoundEntry As %String(%JSONFIELDNAME = "boundEntry", MAXLEN = 16);

Property BoundOutcome As %String(%JSONFIELDNAME = "boundOutcome", MAXLEN = 32);

ClassMethod Create(case As Shutter.Store.Case, plan As Shutter.Store.Plan, snapshot As Shutter.Store.Snapshot, policyVersion As %String, rehearsal As Shutter.Store.Rehearsal, expectedVersion As %Integer, approver As %String, decision As %String, comment As %String, workflowTaskId As %String, validSeconds As %Integer, Output a As Shutter.Store.Approval, epoch As %Integer = "") As %Status
{
    Set a = ..%New()
    // By id, not the caller's copy: a save of the approval never writes the case whole.
    Do a.CaseSetObjectId(case.%Id())
    Set a.Plan = plan, a.PlanDigest = plan.Digest
    Set a.SnapshotDigest = $SELECT($ISOBJECT(snapshot): snapshot.Digest, 1: "")
    Set a.MaterialDigest = $SELECT($ISOBJECT(snapshot): snapshot.MaterialDigest, 1: "")
    Set a.PolicyVersion = policyVersion
    Set a.SiteProfileVersion = ##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0)
    If $ISOBJECT(rehearsal) Set a.Rehearsal = rehearsal
    Set a.ExpectedVersion = expectedVersion
    If epoch '= "" Set a.ReceiverEpoch = epoch
    Set a.Approver = approver, a.Decision = decision, a.Comment = $EXTRACT(comment, 1, 2000)
    Set a.DecidedAt = ##class(Shutter.Util.Time).NowUTC()
    Set a.ExpiresAt = ##class(Shutter.Util.Time).FromNow(validSeconds)
    Set a.WorkflowTaskId = workflowTaskId
    Quit a.%Save()
}

/// Bind an approval given under an incident's to what that approval covered for this item (7.4): the incident plan's
/// digest, and the item's catalogue entry and outcome as the plan listed them.
Method BindIncident(digest As %String, entry As %String, outcome As %String) As %Status
{
    Set ..IncidentPlanDigest = digest, ..BoundEntry = entry, ..BoundOutcome = outcome
    Quit ..%Save()
}

/// Why the approval cannot authorise a dispatch now, or "" when it can.
Method InvalidReason(plan As Shutter.Store.Plan, snapshot As Shutter.Store.Snapshot, policyVersion As %String, receiverVersion As %Integer, receiverEpoch As %Integer = "") As %String
{
    If ..Decision '= "approved" Quit "not_approved"
    If ..Revoked Quit "revoked"
    If ##class(Shutter.Util.Time).NowUTC() ]] ..ExpiresAt Quit "expired"
    If ..PlanDigest '= plan.Digest Quit "plan_changed"
    // An approval given under an incident's covers one entry and outcome for the item, and that incident's plan (7.4).
    If ..IncidentPlanDigest '= "" {
        Set inc = $SELECT($ISOBJECT(..Case): ..Case.Incident, 1: "")
        If '$ISOBJECT(inc) || (inc.PlanDigest '= ..IncidentPlanDigest) Quit "incident_plan_changed"
        If plan.CatalogueEntry '= ..BoundEntry Quit "item_changed"
        Set cat = $SELECT($ISOBJECT(snapshot): snapshot.SummaryObject().%Get("catalogue"), 1: "")
        If '$ISOBJECT(cat) || (##class(Shutter.Util.Json).Str(cat, "entry") '= ..BoundEntry) || (##class(Shutter.Util.Json).Str(cat, "outcome") '= ..BoundOutcome) Quit "item_changed"
    }
    // A refreshed snapshot keeps the approval when nothing material changed (A7).
    If $ISOBJECT(snapshot) && (..SnapshotDigest '= snapshot.Digest) && ((..MaterialDigest = "") || (..MaterialDigest '= snapshot.MaterialDigest)) Quit "snapshot_changed"
    If ..PolicyVersion '= policyVersion Quit "policy_changed"
    // The catalogue and the site profile the decision rested on must still be the current ones (A8).
    If (plan.CatalogueVersion '= "") && (plan.CatalogueVersion '= ##class(Shutter.Catalogue.Entry).CatalogueVersion()) Quit "catalogue_changed"
    If (..SiteProfileVersion '= "") && (..SiteProfileVersion '= ##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0)) Quit "site_profile_changed"
    If (..ExpectedVersion '= "") && (receiverVersion '= "") && (..ExpectedVersion '= receiverVersion) Quit "receiver_changed"
    If (..ReceiverEpoch '= "") && (receiverEpoch '= "") && (..ReceiverEpoch '= receiverEpoch) Quit "receiver_reset"
    Quit ""
}

Method Revoke(by As %String) As %Status
{
    Set ..Revoked = 1, ..RevokedAt = ##class(Shutter.Util.Time).NowUTC(), ..RevokedBy = by
    Quit ..%Save()
}

Storage Default
{
<Data name="ApprovalDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>Plan</Value>
</Value>
<Value name="4">
<Value>PlanDigest</Value>
</Value>
<Value name="5">
<Value>SnapshotDigest</Value>
</Value>
<Value name="6">
<Value>PolicyVersion</Value>
</Value>
<Value name="7">
<Value>Rehearsal</Value>
</Value>
<Value name="8">
<Value>ExpectedVersion</Value>
</Value>
<Value name="9">
<Value>ReceiverEpoch</Value>
</Value>
<Value name="10">
<Value>Approver</Value>
</Value>
<Value name="11">
<Value>Decision</Value>
</Value>
<Value name="12">
<Value>DecidedAt</Value>
</Value>
<Value name="13">
<Value>ExpiresAt</Value>
</Value>
<Value name="14">
<Value>Revoked</Value>
</Value>
<Value name="15">
<Value>RevokedAt</Value>
</Value>
<Value name="16">
<Value>RevokedBy</Value>
</Value>
<Value name="17">
<Value>WorkflowTaskId</Value>
</Value>
<Value name="18">
<Value>Comment</Value>
</Value>
<Value name="19">
<Value>SiteProfileVersion</Value>
</Value>
<Value name="20">
<Value>MaterialDigest</Value>
</Value>
<Value name="21">
<Value>IncidentPlanDigest</Value>
</Value>
<Value name="22">
<Value>BoundEntry</Value>
</Value>
<Value name="23">
<Value>BoundOutcome</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.ApprovalD</DataLocation>
<DefaultData>ApprovalDefaultData</DefaultData>
<IdLocation>^Shutter.Store.ApprovalD</IdLocation>
<IndexLocation>^Shutter.Store.ApprovalI</IndexLocation>
<StreamLocation>^Shutter.Store.ApprovalS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
