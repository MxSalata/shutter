/// A person's decision on an exact plan. It binds the plan digest, the snapshot digest, the gate
/// policy version, the rehearsal and the receiver version it expects, and it expires. Anything
/// that changes those makes it invalid; it can also be revoked.
Class Interlock.Store.Approval Extends (%Persistent, %JSON.Adaptor)
{

Property Case As Interlock.Store.Case(%JSONFIELDNAME = "caseId", %JSONREFERENCE = "ID") [ Required ];

Index CaseIdx On Case;

Property Plan As Interlock.Store.Plan(%JSONFIELDNAME = "planId", %JSONREFERENCE = "ID") [ Required ];

Property PlanDigest As %String(%JSONFIELDNAME = "planDigest", MAXLEN = 80);

Property SnapshotDigest As %String(%JSONFIELDNAME = "snapshotDigest", MAXLEN = 80);

Property PolicyVersion As %String(%JSONFIELDNAME = "policyVersion", MAXLEN = 32);

Property Rehearsal As Interlock.Store.Rehearsal(%JSONFIELDNAME = "rehearsalId", %JSONREFERENCE = "ID");

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

ClassMethod Create(case As Interlock.Store.Case, plan As Interlock.Store.Plan, snapshot As Interlock.Store.Snapshot, policyVersion As %String, rehearsal As Interlock.Store.Rehearsal, expectedVersion As %Integer, approver As %String, decision As %String, comment As %String, workflowTaskId As %String, validSeconds As %Integer, Output a As Interlock.Store.Approval, epoch As %Integer = "") As %Status
{
    Set a = ..%New()
    Set a.Case = case, a.Plan = plan, a.PlanDigest = plan.Digest
    Set a.SnapshotDigest = $SELECT($ISOBJECT(snapshot): snapshot.Digest, 1: "")
    Set a.PolicyVersion = policyVersion
    If $ISOBJECT(rehearsal) Set a.Rehearsal = rehearsal
    Set a.ExpectedVersion = expectedVersion
    If epoch '= "" Set a.ReceiverEpoch = epoch
    Set a.Approver = approver, a.Decision = decision, a.Comment = $EXTRACT(comment, 1, 2000)
    Set a.DecidedAt = ##class(Interlock.Util.Time).NowUTC()
    Set a.ExpiresAt = ##class(Interlock.Util.Time).FromNow(validSeconds)
    Set a.WorkflowTaskId = workflowTaskId
    Quit a.%Save()
}

/// Why the approval cannot authorise a dispatch now, or "" when it can.
Method InvalidReason(plan As Interlock.Store.Plan, snapshot As Interlock.Store.Snapshot, policyVersion As %String, receiverVersion As %Integer, receiverEpoch As %Integer = "") As %String
{
    If ..Decision '= "approved" Quit "not_approved"
    If ..Revoked Quit "revoked"
    If ##class(Interlock.Util.Time).NowUTC() ]] ..ExpiresAt Quit "expired"
    If ..PlanDigest '= plan.Digest Quit "plan_changed"
    If $ISOBJECT(snapshot) && (..SnapshotDigest '= snapshot.Digest) Quit "snapshot_changed"
    If ..PolicyVersion '= policyVersion Quit "policy_changed"
    If (..ExpectedVersion '= "") && (receiverVersion '= "") && (..ExpectedVersion '= receiverVersion) Quit "receiver_changed"
    If (..ReceiverEpoch '= "") && (receiverEpoch '= "") && (..ReceiverEpoch '= receiverEpoch) Quit "receiver_reset"
    Quit ""
}

Method Revoke(by As %String) As %Status
{
    Set ..Revoked = 1, ..RevokedAt = ##class(Interlock.Util.Time).NowUTC(), ..RevokedBy = by
    Quit ..%Save()
}

}
