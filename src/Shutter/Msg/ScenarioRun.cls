/// Asks the scenario player to play a demo scenario: the production's own job feeds the files and sets
/// the downstream system's faults, so a run never needs a new process and shows in the trace.
Class Shutter.Msg.ScenarioRun Extends Ens.Request
{

/// S1 to S10.
Property Scenario As %String(MAXLEN = 16);

/// board, single or rules: the investigation mode the case workflow reads.
Property Mode As %String(MAXLEN = 16) [ InitialExpression = "board" ];

/// Who asked, for the trace.
Property RequestedBy As %String(MAXLEN = 160);

/// Whether the run's agents may run live (1.4.4): false when who asked holds no Shutter_LiveAgents (the public demo's
/// role), and then every agent of the cases the run opens replays its recording, with no model call.
Property LiveAllowed As %Boolean [ InitialExpression = 1 ];

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
<Value name="4">
<Value>LiveAllowed</Value>
</Value>
</Data>
<DefaultData>ScenarioRunDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
