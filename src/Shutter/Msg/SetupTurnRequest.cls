/// One turn of Set up the site (CONTRACTS 14.7): sent by the REST API through the Shutter API service to the Case Question
/// item, which opens the turn's row, answers at once with its id (Shutter.Msg.QuestionStarted) and asks the Set-up guide
/// agent in the tier setup through the Agent Board item. The text is what a person typed about a receiver; the view is
/// what the agent is shown of the draft and the frame the part of the draft its checks read
/// (Shutter.Util.ProfileSetup.View and Frame): the whole draft is never sent on. No tool the agent holds writes anything.
/// Only a caller who may spend the model budget sends one, on a site that switched typed answers on.
Class Shutter.Msg.SetupTurnRequest Extends Ens.Request
{

/// SC-nnnnnn: the conversation, made by the route for a first turn.
Property Conversation As %String(MAXLEN = 32);

/// The receiver the turn is about, by the name it has in the draft.
Property Receiver As %String(MAXLEN = 200);

/// What the person typed, 1 to 500 characters.
Property Text As %String(MAXLEN = 500);

Property ViewJSON As %String(MAXLEN = "");

Property FrameJSON As %String(MAXLEN = "");

Property BaseVersion As %Integer;

Property DraftRevision As %Integer;

/// The signed-in user who asked.
Property AskedBy As %String(MAXLEN = 100);

Storage Default
{
<Data name="SetupTurnRequestDefaultData">
<Subscript>"SetupTurnRequest"</Subscript>
<Value name="1">
<Value>Conversation</Value>
</Value>
<Value name="2">
<Value>Receiver</Value>
</Value>
<Value name="3">
<Value>Text</Value>
</Value>
<Value name="4">
<Value>ViewJSON</Value>
</Value>
<Value name="5">
<Value>FrameJSON</Value>
</Value>
<Value name="6">
<Value>BaseVersion</Value>
</Value>
<Value name="7">
<Value>DraftRevision</Value>
</Value>
<Value name="8">
<Value>AskedBy</Value>
</Value>
</Data>
<DefaultData>SetupTurnRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
