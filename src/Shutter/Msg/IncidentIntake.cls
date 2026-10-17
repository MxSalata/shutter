/// Starts an incident's workflow: sent by the case workflow whose case took the receiver's failures to the
/// site's threshold (CONTRACTS 7.1).
Class Shutter.Msg.IncidentIntake Extends Ens.Request
{

Property IncidentId As %String(MAXLEN = 32);

/// The case that opened the incident.
Property CaseId As %String(MAXLEN = 32);

Storage Default
{
<Data name="IncidentIntakeDefaultData">
<Subscript>"IncidentIntake"</Subscript>
<Value name="1">
<Value>IncidentId</Value>
</Value>
<Value name="2">
<Value>CaseId</Value>
</Value>
</Data>
<DefaultData>IncidentIntakeDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
