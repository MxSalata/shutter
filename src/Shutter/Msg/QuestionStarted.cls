/// The early answer to a question request: which question was opened, its conversation and turn and its state, sent back
/// before the agents run, as the review item answers with ReviewStarted. Error says why none was opened.
Class Shutter.Msg.QuestionStarted Extends Ens.Response
{

Property QuestionId As %String(MAXLEN = 32);

Property Conversation As %String(MAXLEN = 64);

Property Turn As %Integer;

/// pending, answering, answered, schema_failed or failed.
Property State As %String(MAXLEN = 16);

Property Error As %String(MAXLEN = 2000);

Storage Default
{
<Data name="QuestionStartedDefaultData">
<Subscript>"QuestionStarted"</Subscript>
<Value name="1">
<Value>QuestionId</Value>
</Value>
<Value name="2">
<Value>Conversation</Value>
</Value>
<Value name="3">
<Value>Turn</Value>
</Value>
<Value name="4">
<Value>State</Value>
</Value>
<Value name="5">
<Value>Error</Value>
</Value>
</Data>
<DefaultData>QuestionStartedDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
