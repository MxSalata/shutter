/// What FHIR Receiver read: every part asked for, each with its trusted status, or one error and no parts. The body
/// of a Patient or a Location part holds only the fields the checks read; the Encounter, its history and a version
/// read by id are whole.
Class Shutter.Msg.FHIRReadResult Extends Ens.Response
{

/// {"observed_at", "base", "metadata", "search", "encounter", "patient", "locations": [..], "history", "vread"}; a part
/// not asked for is absent.
Property PartsJSON As %String(MAXLEN = "");

Property Error As %String(MAXLEN = 2000);

Storage Default
{
<Data name="FHIRReadResultDefaultData">
<Subscript>"FHIRReadResult"</Subscript>
<Value name="1">
<Value>PartsJSON</Value>
</Value>
<Value name="2">
<Value>Error</Value>
</Value>
</Data>
<DefaultData>FHIRReadResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
