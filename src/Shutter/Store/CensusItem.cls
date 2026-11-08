/// One failed delivery in a census run, or a case whose origin is gone (docs/CONTRACTS.md, section 19). Its key is the source
/// namespace, the delivery's header and the target. It holds ids and codes, never message content.
Class Shutter.Store.CensusItem Extends %Persistent
{

Property Run As Shutter.Store.CensusRun [ Required ];

Index RunIdx On Run;

Property SourceNamespace As %String(MAXLEN = 64);

/// The delivery's Ens.MessageHeader id in the source namespace; "" for a case whose origin is gone.
Property DeliveryHeaderId As %String(MAXLEN = 40);

Property Target As %String(MAXLEN = 128);

Index HeaderIdx On (Run, DeliveryHeaderId);

Property SessionId As %String(MAXLEN = 40);

/// The header a case names, for a case whose origin is gone.
Property OriginHeaderId As %String(MAXLEN = 40);

Property TimeCreated As %String(MAXLEN = 30);

/// The header's status when the source was read: error, suspended, aborted, discarded, completed (with the error flag).
Property SourceStatus As %String(MAXLEN = 16);

Property BodyClass As %String(MAXLEN = 128);

/// The HL7 structure's family, ADT or ORU: nothing else is read from the body.
Property Family As %String(MAXLEN = 16);

/// The header this one was resent from, as the engine records it.
Property ResendOf As %String(MAXLEN = 40);

/// The linked cases' public ids, comma-separated.
Property CaseIds As %String(MAXLEN = 2000);

/// exact, ambiguous or none.
Property LinkQuality As %String(MAXLEN = 16);

/// in_scope, excluded or unknown.
Property Eligibility As %String(MAXLEN = 16);

/// Why, as a code (CONTRACTS 19).
Property Explanation As %String(MAXLEN = 64);

/// The row of a run for a delivery's header, or "".
ClassMethod Of(run As Shutter.Store.CensusRun, header As %String) As Shutter.Store.CensusItem
{
    Set id = "", runId = run.%Id()
    &sql(SELECT ID INTO :id FROM Shutter_Store.CensusItem WHERE Run = :runId AND DeliveryHeaderId = :header)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

Storage Default
{
<Data name="CensusItemDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Run</Value>
</Value>
<Value name="3">
<Value>SourceNamespace</Value>
</Value>
<Value name="4">
<Value>DeliveryHeaderId</Value>
</Value>
<Value name="5">
<Value>Target</Value>
</Value>
<Value name="6">
<Value>SessionId</Value>
</Value>
<Value name="7">
<Value>OriginHeaderId</Value>
</Value>
<Value name="8">
<Value>TimeCreated</Value>
</Value>
<Value name="9">
<Value>SourceStatus</Value>
</Value>
<Value name="10">
<Value>BodyClass</Value>
</Value>
<Value name="11">
<Value>Family</Value>
</Value>
<Value name="12">
<Value>ResendOf</Value>
</Value>
<Value name="13">
<Value>CaseIds</Value>
</Value>
<Value name="14">
<Value>LinkQuality</Value>
</Value>
<Value name="15">
<Value>Eligibility</Value>
</Value>
<Value name="16">
<Value>Explanation</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.CensusItemD</DataLocation>
<DefaultData>CensusItemDefaultData</DefaultData>
<IdLocation>^Shutter.Store.CensusItemD</IdLocation>
<IndexLocation>^Shutter.Store.CensusItemI</IndexLocation>
<StreamLocation>^Shutter.Store.CensusItemS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
