/// One specialist's view inside the board's answer to a question: an element of Shutter.Schema.BoardAnswer.
Class Shutter.Schema.Perspective Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The member's code: conformance, encounter or impact.
Property Member As %String(%JSONFIELDNAME = "member", MAXLEN = 32);

/// What that member's answer says, in a sentence or two, at most 400 characters; a disagreement is kept, not smoothed.
Property View As %String(%JSONFIELDNAME = "view", MAXLEN = 400);

}
