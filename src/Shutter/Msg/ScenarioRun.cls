/// Asks the scenario player to play a demo scenario: the production's own job feeds the files and sets
/// the ward's faults, so a run never needs a new process and shows in the trace.
Class Shutter.Msg.ScenarioRun Extends Ens.Request
{

/// S1 to S10.
Property Scenario As %String(MAXLEN = 16);

/// board, single or rules: the investigation mode the case workflow reads.
Property Mode As %String(MAXLEN = 16) [ InitialExpression = "board" ];

/// Who asked, for the trace.
Property RequestedBy As %String(MAXLEN = 160);

Storage Default
{
<Data name="ScenarioRunDefaultData">
<Subscript>"ScenarioRun"</Subscript>
<Value name="1">
<Value>Scenario</Value>
</Value>
<Value name="2">
<Value>Mode</Value>
</Value>
<Value name="3">
<Value>RequestedBy</Value>
</Value>
</Data>
<DefaultData>ScenarioRunDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
