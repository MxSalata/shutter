/// A question about a page of the web app (CONTRACTS 14.6): sent by the REST API through the Shutter API service to the
/// Case Question item, which opens the question row, answers at once with its id (Shutter.Msg.QuestionStarted) and asks
/// the Explain agent in the tier page through the Agent Board item. The question and the summary of the screen are data
/// about what the person sees and wants to know; no tool the agent holds writes anything. Only a caller who may spend the
/// model budget sends one (the route answers 403 to everyone else).
Class Shutter.Msg.PageQuestionRequest Extends Ens.Request
{

/// The page's name as the web app sends it.
Property Page As %String(MAXLEN = 40);

/// The question as asked, 1 to 500 characters.
Property Text As %String(MAXLEN = 500);

/// The summary of the screen, already held to its shape by Shutter.Util.PageQuestion.CleanContext, as JSON.
Property ContextJSON As %String(MAXLEN = "");

/// The signed-in user who asked.
Property AskedBy As %String(MAXLEN = 100);

Storage Default
{
<Data name="PageQuestionRequestDefaultData">
<Subscript>"PageQuestionRequest"</Subscript>
<Value name="1">
<Value>Page</Value>
</Value>
<Value name="2">
<Value>Text</Value>
</Value>
<Value name="3">
<Value>ContextJSON</Value>
</Value>
<Value name="4">
<Value>AskedBy</Value>
</Value>
</Data>
<DefaultData>PageQuestionRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
