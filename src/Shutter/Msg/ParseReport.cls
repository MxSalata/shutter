/// The Second Parser's answer (CONTRACTS 6.7, v1.34): an independent parser's report on a message IRIS could not read, as
/// JSON ({parser, declared_version, version_known, read_as, message_type, control_id, parsed, valid, structure, errors,
/// segments, segments_declared, notes}), and the parser's name.
Class Shutter.Msg.ParseReport Extends Ens.Response
{

Property ReportJSON As %String(MAXLEN = "");

Property Parser As %String(MAXLEN = 200);

/// The report as an object; {parsed: false, errors: [{code: "UNREADABLE", message}]} when the JSON cannot be read.
Method Report() As %DynamicObject
{
    Set o = ""
    Try { Set o = ##class(%DynamicObject).%FromJSON(..ReportJSON) } Catch ex { Set o = "" }
    If '$ISOBJECT(o) {
        Set o = {"parsed": false, "valid": false, "errors": [{"code": "UNREADABLE", "message": "The parser's report could not be read"}]}
        Set o.parser = ..Parser
    }
    Quit o
}

Storage Default
{
<Data name="ParseReportDefaultData">
<Subscript>"ParseReport"</Subscript>
<Value name="1">
<Value>ReportJSON</Value>
</Value>
<Value name="2">
<Value>Parser</Value>
</Value>
</Data>
<DefaultData>ParseReportDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
