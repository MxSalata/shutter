/// A message IRIS could not read, sent to the Second Parser (CONTRACTS 6.7, v1.34): the raw HL7 text and, for the trace, the
/// case and the header it came from. The PEX operation answers with the request's own Reply, a Shutter.Msg.ParseReport.
Class Shutter.Msg.ParseRequest Extends Ens.Request
{

Property Raw As %String(MAXLEN = "");

Property CaseId As %String(MAXLEN = 32);

Property HeaderId As %String(MAXLEN = 32);

/// The report for this request, made here so the Java side needs no connection of its own: the parser's JSON and its name.
Method Reply(json As %String, parser As %String) As Shutter.Msg.ParseReport
{
    Set r = ##class(Shutter.Msg.ParseReport).%New()
    Set r.ReportJSON = json, r.Parser = parser
    Quit r
}

Storage Default
{
<Data name="ParseRequestDefaultData">
<Subscript>"ParseRequest"</Subscript>
<Value name="1">
<Value>Raw</Value>
</Value>
<Value name="2">
<Value>CaseId</Value>
</Value>
<Value name="3">
<Value>HeaderId</Value>
</Value>
</Data>
<DefaultData>ParseRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
