/// Asks the evidence collector for a fresh snapshot of a case.
Class Interlock.Msg.EvidenceRequest Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

/// initial, refresh.
Property Reason As %String(MAXLEN = 32) [ InitialExpression = "initial" ];

}
