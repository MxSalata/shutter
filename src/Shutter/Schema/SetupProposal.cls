/// One answer the Set-up guide agent drafts from a person's words (CONTRACTS 14.7): the field, the receiver, the value
/// and the person's own words it was read from. The core decides whether it is used (Shutter.Util.ProfileSetup.CheckTurn).
Class Shutter.Schema.SetupProposal Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The field, as the request lists it: receivers[].system, receivers[].category or receivers[].tier.
Property Field As %String(%JSONFIELDNAME = "field", MAXLEN = 64) [ Required ];

/// The receiver the request is about, by its name.
Property Receiver As %String(%JSONFIELDNAME = "receiver", MAXLEN = 200) [ Required ];

/// The value: a few words for the description; current_state, history_of_record or orders_results for the kind; 1, 2 or
/// 3 for the tier.
Property To As %String(%JSONFIELDNAME = "to", MAXLEN = 200) [ Required ];

/// The person's own words the value was read from, copied exactly, at most 200 characters.
Property Quote As %String(%JSONFIELDNAME = "quote", MAXLEN = 200) [ Required ];

}
