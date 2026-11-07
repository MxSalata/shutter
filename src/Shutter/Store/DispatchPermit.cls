/// One recovery call to a receiver, admitted before it is sent (a rehearsal, a recovery write or a blind-resend preview).
/// It is saved and committed before the POST, so a call a restart cut off is still on record: nothing here ever reads as
/// "not sent". The ordinary feed takes no permit.
Class Shutter.Store.DispatchPermit Extends %Persistent
{

/// What the sender holds a lock on for as long as the call runs (Shutter.Util.RecoveryControl.Reconcile).
Property Token As %Integer;

Property ActionKind As %String(MAXLEN = 16);

Property CaseId As %String(MAXLEN = 32);

Property PlanId As %String(MAXLEN = 20);

Property OperationKey As %String(MAXLEN = 400);

Property Receiver As %String(MAXLEN = 128);

/// The SHA-256 of the whole body sent, so fields outside the receiver's payload digest, such as the bed, count.
Property BodyDigest As %String(MAXLEN = 80);

Property Generation As %Integer;

Property AdmittedAt As %String(MAXLEN = 30);

Property EndedAt As %String(MAXLEN = 30);

/// admitted: the call may be running. answered: the connector read an outcome. uncertain: the call got no answer that
/// settles it, and it may have been applied.
Property State As %String(MAXLEN = 16, VALUELIST = ",admitted,answered,uncertain") [ InitialExpression = "admitted" ];

/// The connector's outcome, once it has one.
Property Outcome As %String(MAXLEN = 32);

Property HttpStatus As %String(MAXLEN = 8);

/// The job that sends it.
Property Job As %String(MAXLEN = 20);

/// A restart or a lost job left it unanswered. It stops recovery until a person has seen it.
Property Orphaned As %Boolean [ InitialExpression = 0 ];

/// Who saw it, clearing the stop. That says nothing about whether the receiver applied it: the state stays uncertain.
Property ReviewedBy As %String(MAXLEN = 160);

Property ReviewedAt As %String(MAXLEN = 30);

Index StateIdx On State;

Index CaseIdx On CaseId;

}
