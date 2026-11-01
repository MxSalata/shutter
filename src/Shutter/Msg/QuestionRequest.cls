/// A question about a case (CONTRACTS 14.2): sent by the REST API through the Shutter API service to the Case Question
/// item, which opens the question row, answers at once with its id, and asks the Explain agent (tier explain) or the
/// board's members and coordinator (tier board) through the Agent Board item. The question's text is data about what the
/// user wants to know; no tool the agents hold writes anything.
Class Shutter.Msg.QuestionRequest Extends Ens.Request
{

Property CaseId As %String(MAXLEN = 32);

/// explain or board.
Property Tier As %String(MAXLEN = 16);

/// suggested (a turn of knowledge/questions/<S>.json, recorded and replayable) or free (live only).
Property Source As %String(MAXLEN = 16) [ InitialExpression = "free" ];

/// The question as asked, 1 to 2000 characters.
Property Text As %String(MAXLEN = 2000);

/// The conversation the turn belongs to: the file's id for a suggested turn, the one the caller continues, or empty
/// for a new one.
Property Conversation As %String(MAXLEN = 64);

/// The file's turn for a suggested question; 0 for the next turn of the conversation.
Property Turn As %Integer [ InitialExpression = 0 ];

/// The signed-in user who asked.
Property AskedBy As %String(MAXLEN = 100);

/// Whether the asker may spend the model budget (Shutter_LiveAgents, v1.34): without it the agents answer from recordings
/// only.
Property LiveAllowed As %Boolean [ InitialExpression = 1 ];

Storage Default
{
<Data name="QuestionRequestDefaultData">
<Subscript>"QuestionRequest"</Subscript>
<Value name="1">
<Value>CaseId</Value>
</Value>
<Value name="2">
<Value>Tier</Value>
</Value>
<Value name="3">
<Value>Source</Value>
</Value>
<Value name="4">
<Value>Text</Value>
</Value>
<Value name="5">
<Value>Conversation</Value>
</Value>
<Value name="6">
<Value>Turn</Value>
</Value>
<Value name="7">
<Value>AskedBy</Value>
</Value>
<Value name="8">
<Value>LiveAllowed</Value>
</Value>
</Data>
<DefaultData>QuestionRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
