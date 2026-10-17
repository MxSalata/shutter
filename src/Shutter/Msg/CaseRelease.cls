/// Releases a case an incident holds (CONTRACTS 7.4): the incident workflow sends it to the case workflow, which
/// starts a fresh instance for the case: fresh evidence, then the chain's path (policy, board or person), with the
/// incident's approval standing in for a person's when the site's policy asked for one.
Class Shutter.Msg.CaseRelease Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

Property IncidentId As %String(MAXLEN = 32);

Property ChainSeq As %Integer;

Property Position As %Integer;

/// single, ordered, interleaved.
Property ChainKind As %String(MAXLEN = 16);

/// policy, board or person: who decides this case, from the chain's classification.
Property Decides As %String(MAXLEN = 16);

/// The receiver version the chain expects at this item's dispatch (the previous item's verified version, or
/// the chain's first expected version when a person approved the chain); empty when fresh evidence decides.
Property ExpectedVersion As %String(MAXLEN = 20);

/// automatic (released by site policy, no task), incident (released under the incident's approval), or path
/// (the case's own path raises its own approval).
Property ReleasePolicy As %String(MAXLEN = 16);

/// The user who approved the incident or the chain, for the approval record.
Property Approver As %String(MAXLEN = 100);

/// The Workflow task that carried the approval.
Property ApprovalRef As %String(MAXLEN = 50);

/// The incident plan's digest the approval bound.
Property PlanDigest As %String(MAXLEN = 80);

Storage Default
{
<Data name="CaseReleaseDefaultData">
<Subscript>"CaseRelease"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>IncidentId</Value>
</Value>
<Value name="3">
<Value>ChainSeq</Value>
</Value>
<Value name="4">
<Value>Position</Value>
</Value>
<Value name="5">
<Value>ChainKind</Value>
</Value>
<Value name="6">
<Value>Decides</Value>
</Value>
<Value name="7">
<Value>ExpectedVersion</Value>
</Value>
<Value name="8">
<Value>ReleasePolicy</Value>
</Value>
<Value name="9">
<Value>Approver</Value>
</Value>
<Value name="10">
<Value>ApprovalRef</Value>
</Value>
<Value name="11">
<Value>PlanDigest</Value>
</Value>
</Data>
<DefaultData>CaseReleaseDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
