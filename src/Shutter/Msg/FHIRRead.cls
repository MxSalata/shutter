/// Asks FHIR Receiver for the reads one purpose needs. It names no receiver: the item opens the case and takes the
/// receiver from it, so a request can borrow no other entry's settings.
Class Shutter.Msg.FHIRRead Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

Property Purpose As %String(MAXLEN = 16, VALUELIST = ",evidence,dispatch,verify");

/// The Encounter's FHIR logical id; empty for evidence, which finds it by search.
Property EncounterId As %String(MAXLEN = 64);

Property PatientRef As %String(MAXLEN = 100);

/// ["Location/ward-a", ...]: the Location reads of a dispatch or verify request.
Property LocationRefsJSON As %String(MAXLEN = "");

/// The version id to read by id (verify only); empty for none.
Property Vid As %String(MAXLEN = 100);

Storage Default
{
<Data name="FHIRReadDefaultData">
<Subscript>"FHIRRead"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>Purpose</Value>
</Value>
<Value name="3">
<Value>EncounterId</Value>
</Value>
<Value name="4">
<Value>PatientRef</Value>
</Value>
<Value name="5">
<Value>LocationRefsJSON</Value>
</Value>
<Value name="6">
<Value>Vid</Value>
</Value>
</Data>
<DefaultData>FHIRReadDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
