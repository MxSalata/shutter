/// A request for a production review (CONTRACTS 13): sent by the REST API through the Shutter API service to the Case
/// Review item, which sweeps the named production read-only, stores the review and, when asked, has the review agent rank
/// the findings. The target must be one Shutter knows (Shutter.Review.Sweep.Targets): the route checks, and the process
/// checks again, so no caller's string ever becomes a namespace switch.
Class Shutter.Msg.ReviewRequest Extends Ens.Request
{

/// The namespace the production runs in; empty means this one.
Property Namespace As %String(MAXLEN = 64);

/// The production's name; empty means Shutter's own (Shutter.Setup.ProductionName).
Property Production As %String(MAXLEN = 128);

/// Days of event log, messages and cases the review looks back over (7 by default, 1 to 90).
Property WindowDays As %Integer [ InitialExpression = 7 ];

/// Whether the review agent ranks and explains the findings after the sweep.
Property Agent As %Boolean [ InitialExpression = 1 ];

/// The signed-in user who asked for the review.
Property RequestedBy As %String(MAXLEN = 100);

Storage Default
{
<Data name="ReviewRequestDefaultData">
<Subscript>"ReviewRequest"</Subscript>
<Value name="1">
<Value>Namespace</Value>
</Value>
<Value name="2">
<Value>Production</Value>
</Value>
<Value name="3">
<Value>WindowDays</Value>
</Value>
<Value name="4">
<Value>Agent</Value>
</Value>
<Value name="5">
<Value>RequestedBy</Value>
</Value>
</Data>
<DefaultData>ReviewRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
