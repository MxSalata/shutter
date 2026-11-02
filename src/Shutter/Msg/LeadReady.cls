/// The board a case was following has ended (CONTRACTS 6.6, v1.35, one board per failure signature): a fresh instance of
/// the case workflow carries the follower on from its evidence, taking the leader's decision when the lead is done, or
/// the rules path when it failed.
Class Shutter.Msg.LeadReady Extends Ens.Request
{

/// The follower.
Property CaseId As %String(MAXLEN = 32);

/// The case whose board ran.
Property LeaderCaseId As %String(MAXLEN = 32);

Property Signature As %String(MAXLEN = 80);

/// done or failed.
Property Outcome As %String(MAXLEN = 16);

Storage Default
{
<Data name="LeadReadyDefaultData">
<Subscript>"LeadReady"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>LeaderCaseId</Value>
</Value>
<Value name="3">
<Value>Signature</Value>
</Value>
<Value name="4">
<Value>Outcome</Value>
</Value>
</Data>
<DefaultData>LeadReadyDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
