/// One turn of the Set-up guide agent (CONTRACTS 14.7): what it says to the person, the answers it drafts from their
/// words and the question it suggests next. The terminal tool's argument, so the model sees this shape as the tool's
/// JSON Schema; the core checks every part before anything is kept (Shutter.Util.ProfileSetup.CheckTurn).
Class Shutter.Schema.SetupTurn Extends (%RegisteredObject, %JSON.Adaptor)
{

/// What the agent says to the person, in plain words, at most 800 characters.
Property Say As %String(%JSONFIELDNAME = "say", MAXLEN = 800) [ Required ];

/// The answers drafted, at most three; none when the words did not say.
Property Proposals As list Of Shutter.Schema.SetupProposal(%JSONFIELDNAME = "proposals");

/// The next unanswered question, or nothing.
Property Ask As Shutter.Schema.SetupAsk(%JSONFIELDNAME = "ask");

/// Problems with a turn object as JSON text, as an array of messages; empty when its shape is right. What it may draft
/// is the core's to decide (Shutter.Util.ProfileSetup.CheckTurn), with the stored turn beside it.
ClassMethod Check(json As %String) As %DynamicArray
{
    Set problems = []
    Set o = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(o) || $$$ISERR(sc) || 'o.%IsA("%Library.DynamicObject") Do problems.%Push("turn must be a JSON object") Quit problems
    If (o.%GetTypeOf("say") '= "string") || ($ZSTRIP(o.%Get("say"), "<>W") = "") {
        Do problems.%Push("say needs a sentence for the person")
    } ElseIf $LENGTH(o.%Get("say")) > 800 {
        Do problems.%Push("say is longer than 800 characters")
    }
    Set t = o.%GetTypeOf("proposals")
    If (t '= "unassigned") && (t '= "null") {
        If t '= "array" {
            Do problems.%Push("proposals must be an array")
        } ElseIf o.%Get("proposals").%Size() > 3 {
            Do problems.%Push("proposals holds at most three answers")
        }
    }
    Set t = o.%GetTypeOf("ask")
    If (t '= "unassigned") && (t '= "null") && (t '= "object") Do problems.%Push("ask must be {field, receiver} or left out")
    Quit problems
}

}
