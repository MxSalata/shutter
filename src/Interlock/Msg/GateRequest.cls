/// Asks the gate to evaluate a plan at a stage: proposal, approval or dispatch.
Class Interlock.Msg.GateRequest Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

Property PlanId As %String(MAXLEN = 20);

Property Stage As %String(MAXLEN = 16, VALUELIST = ",proposal,approval,dispatch") [ InitialExpression = "proposal" ];

/// The approval the dispatch relies on, for the authorization check.
Property ApprovalId As %String(MAXLEN = 20);

/// The receiver's version as last observed, for the concurrency check at dispatch.
Property ReceiverVersion As %Integer;

/// The receiver's epoch as last observed (it changes at every reset).
Property ReceiverEpoch As %Integer;

}
