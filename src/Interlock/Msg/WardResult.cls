/// What the receiver answered to a ward operation, classified. The connector never turns an
/// outcome into a failed message: outcomes are data for the feed process and the case workflow.
Class Interlock.Msg.WardResult Extends Ens.Response
{

Property HttpStatus As %Integer;

/// applied, already_committed, would_apply, would_not_apply, version_conflict, refused,
/// unavailable, uncertain, error.
Property Outcome As %String(MAXLEN = 32);

/// The receiver's error code or the rehearsal's reason: duplicate_message, invalid_transition, ...
Property ReasonCode As %String(MAXLEN = 64);

Property ResponseJSON As %String(MAXLEN = "");

Property ReceiptJSON As %String(MAXLEN = "");

/// The encounter's version after the call, when the response carried it.
Property EncounterVersion As %Integer;

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

}
