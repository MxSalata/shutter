/// A person's decision on an exact plan. It binds the plan digest, the snapshot digest, the gate
/// policy version, the rehearsal and the receiver version it expects, and it expires. Anything
/// that changes those makes it invalid; it can also be revoked.
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

ClassMethod Create(case As Shutter.Store.Case, plan As Shutter.Store.Plan, snapshot As Shutter.Store.Snapshot, policyVersion As %String, rehearsal As Shutter.Store.Rehearsal, expectedVersion As %Integer, approver As %String, decision As %String, comment As %String, workflowTaskId As %String, validSeconds As %Integer, Output a As Shutter.Store.Approval, epoch As %Integer = "") As %Status
{
    Set a = ..%New()
    Set a.Case = case, a.Plan = plan, a.PlanDigest = plan.Digest
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

/// Why the approval cannot authorise a dispatch now, or "" when it can.
Method InvalidReason(plan As Shutter.Store.Plan, snapshot As Shutter.Store.Snapshot, policyVersion As %String, receiverVersion As %Integer, receiverEpoch As %Integer = "") As %String
{
    If ..Decision '= "approved" Quit "not_approved"
    If ..Revoked Quit "revoked"
    If ##class(Shutter.Util.Time).NowUTC() ]] ..ExpiresAt Quit "expired"
    If ..PlanDigest '= plan.Digest Quit "plan_changed"
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
</Data>
<DataLocation>^Shutter.Store.ApprovalD</DataLocation>
<DefaultData>ApprovalDefaultData</DefaultData>
<IdLocation>^Shutter.Store.ApprovalD</IdLocation>
<IndexLocation>^Shutter.Store.ApprovalI</IndexLocation>
<StreamLocation>^Shutter.Store.ApprovalS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
