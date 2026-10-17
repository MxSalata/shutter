/// What the receiver answered to a ward operation, classified. The connector never turns an
/// outcome into a failed message: outcomes are data for the feed process and the case workflow.
Class Shutter.Msg.WardResult Extends Ens.Response
{

Property HttpStatus As %Integer;

/// applied, already_committed, would_apply, would_not_apply, version_conflict, refused,
/// unavailable, uncertain, error.
Property Outcome As %String(MAXLEN = 32);

/// The receiver's error code or the rehearsal's reason: duplicate_message, invalid_transition, ...
Property ReasonCode As %String(MAXLEN = 64);

Property ResponseJSON As %String(MAXLEN = "");

Property ReceiptJSON As %String(MAXLEN = "");

/// The encounter's version as the receiver reported it: after an applied write, the version it
/// checked against for a dry run (encounter_before), the current one for a read.
Property EncounterVersion As %Integer;

/// For a dry run that would apply, the version the write would leave.
Property VersionAfter As %Integer;

/// The receiver's epoch, when the response carried it.
Property Epoch As %Integer;

Property Error As %String(MAXLEN = 2000);

Property DurationMs As %Integer;

/// True for the outcomes that mean the business operation is in effect at the receiver.
Method IsInEffect() As %Boolean
{
    Quit (..Outcome = "applied") || (..Outcome = "already_committed")
}

/// The parsed response, or an empty object.
Method ResponseObject() As %DynamicObject
{
    If ..ResponseJSON = "" Quit {}
    Try { Set o = ##class(%DynamicObject).%FromJSON(..ResponseJSON) } Catch { Set o = {} }
    Quit o
}

Storage Default
{
<Data name="WardResultDefaultData">
<Subscript>"WardResult"</Subscript>
<Value name="1">
<Value>HttpStatus</Value>
</Value>
<Value name="2">
<Value>Outcome</Value>
</Value>
<Value name="3">
<Value>ReasonCode</Value>
</Value>
<Value name="4">
<Value>ResponseJSON</Value>
</Value>
<Value name="5">
<Value>ReceiptJSON</Value>
</Value>
<Value name="6">
<Value>EncounterVersion</Value>
</Value>
<Value name="7">
<Value>VersionAfter</Value>
</Value>
<Value name="8">
<Value>Epoch</Value>
</Value>
<Value name="9">
<Value>Error</Value>
</Value>
<Value name="10">
<Value>DurationMs</Value>
</Value>
</Data>
<DefaultData>WardResultDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
