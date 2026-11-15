/// The question the Set-up guide agent suggests comes next (CONTRACTS 14.7): a field of the checklist that is not answered
/// yet, of the receiver the request is about. The page takes it only when it is an unanswered question of its checklist.
Class Shutter.Schema.SetupAsk Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The field, as the request lists it, for example receivers[].tier.
Property Field As %String(%JSONFIELDNAME = "field", MAXLEN = 64) [ Required ];

/// The receiver the request is about, by its name.
Property Receiver As %String(%JSONFIELDNAME = "receiver", MAXLEN = 200) [ Required ];

}
