/// A reference to one fact of the question's what-if facts (whatif.facts[].id, W1, W2, ...). The agent names a fact;
/// the core stores the fact itself, from its own facts, never from the agent's text.
Class Shutter.Schema.FactRef Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The fact's id, W1, W2, ...
Property Fact As %String(%JSONFIELDNAME = "fact", MAXLEN = 16);

/// For a suggested change: why it fits what the person asked, in a sentence.
Property Why As %String(%JSONFIELDNAME = "why", MAXLEN = 400);

}
