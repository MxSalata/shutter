/// The Failure Census item's answer: the run's public id, or why there is none.
Class Shutter.Msg.CensusAnswer Extends Ens.Response
{

Property RunId As %String(MAXLEN = 32);

Property Error As %String(MAXLEN = 2000);

Storage Default
{
<Data name="CensusAnswerDefaultData">
<Subscript>"CensusAnswer"</Subscript>
<Value name="1">
<Value>RunId</Value>
</Value>
<Value name="2">
<Value>Error</Value>
</Value>
</Data>
<DefaultData>CensusAnswerDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
