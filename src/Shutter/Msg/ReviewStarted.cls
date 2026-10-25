/// The early answer to a review request: which review was opened and its state (sweeping), sent back before the sweep
/// runs, as the case workflow answers an intake with CaseStarted. Error says why no review was opened (not a production
/// Shutter knows, or one of the same production still sweeping or ranking, whose id and state are then given).
Class Shutter.Msg.ReviewStarted Extends Ens.Response
{

Property ReviewId As %String(MAXLEN = 32);

/// sweeping, ranking, done or failed.
Property State As %String(MAXLEN = 32);

Property Error As %String(MAXLEN = 2000);

Storage Default
{
<Data name="ReviewStartedDefaultData">
<Subscript>"ReviewStarted"</Subscript>
<Value name="1">
<Value>ReviewId</Value>
</Value>
<Value name="2">
<Value>State</Value>
</Value>
<Value name="3">
<Value>Error</Value>
</Value>
</Data>
<DefaultData>ReviewStartedDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
