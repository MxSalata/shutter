/// How a scenario run went: the run record the runner keeps (CONTRACTS 4), as JSON.
Class Shutter.Msg.ScenarioRunResult Extends Ens.Response
{

Property Scenario As %String(MAXLEN = 16);

Property Mode As %String(MAXLEN = 16);

/// done, failed, or refused (another run was playing, or the checks before a run failed).
Property State As %String(MAXLEN = 16);

Property StartedAt As %String(MAXLEN = 30);

Property FinishedAt As %String(MAXLEN = 30);

Property Error As %String(MAXLEN = 2000);

/// The run record: scenario, mode, startedAt, state, files, timeouts, finishedAt, error.
Property RunJSON As %String(MAXLEN = "");

Storage Default
{
<Data name="ScenarioRunResultDefaultData">
<Subscript>"ScenarioRunResult"</Subscript>
<Value name="1">
<Value>Scenario</Value>
</Value>
<Value name="2">
<Value>Mode</Value>
</Value>
<Value name="3">
<Value>State</Value>
</Value>
<Value name="4">
<Value>StartedAt</Value>
</Value>
<Value name="5">
<Value>FinishedAt</Value>
</Value>
<Value name="6">
<Value>Error</Value>
</Value>
<Value name="7">
<Value>RunJSON</Value>
</Value>
</Data>
<DefaultData>ScenarioRunResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
