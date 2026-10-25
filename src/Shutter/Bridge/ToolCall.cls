/// One tool call made by an agent during a run, as the bridge's audit policy recorded it. Keyed by
/// the production message that carried the run, so the case page and the Visual Trace meet here.
Class Shutter.Bridge.ToolCall Extends (%Persistent, %JSON.Adaptor)
{

/// The Ens.MessageHeader id of the agent request, or a test run's own key (test:<case>:<member>:<n>, the live
/// runner's TestRun).
Property RunKey As %String(%JSONFIELDNAME = "runKey", MAXLEN = 80) [ Required ];

Property Seq As %Integer(%JSONFIELDNAME = "seq") [ Required ];

Index RunSeqIdx On (RunKey, Seq) [ Unique ];

Property At As %String(%JSONFIELDNAME = "at", MAXLEN = 30);

Property Name As %String(%JSONFIELDNAME = "name", MAXLEN = 200);

Property ArgumentsJSON As %String(%JSONFIELDNAME = "arguments", MAXLEN = "");

Property DurationMs As %Integer(%JSONFIELDNAME = "durationMs");

Property Ok As %Boolean(%JSONFIELDNAME = "ok");

Property ResultPreview As %String(%JSONFIELDNAME = "resultPreview", MAXLEN = 1000);

Property Error As %String(%JSONFIELDNAME = "error", MAXLEN = 2000);

/// Append a call for a run.
ClassMethod Append(runKey As %String, name As %String, arguments As %String, durationMs As %Integer, ok As %Boolean, resultPreview As %String, error As %String = "") As %Status
{
    Set c = ..%New()
    Set c.RunKey = runKey
    Set c.Seq = $INCREMENT(^Shutter.Counter("toolcall", runKey))
    Set c.At = ##class(Shutter.Util.Time).NowUTCms()
    Set c.Name = name, c.ArgumentsJSON = arguments, c.DurationMs = durationMs, c.Ok = ok
    Set c.ResultPreview = $EXTRACT(resultPreview, 1, 1000), c.Error = $EXTRACT(error, 1, 2000)
    Quit c.%Save()
}

/// The calls of a run, in order, as a dynamic array.
ClassMethod ForRun(runKey As %String) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Bridge.ToolCall WHERE RunKey = ? ORDER BY Seq", runKey)
    While rs.%Next() {
        Set c = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Do c.%JSONExportToString(.json)
        Do out.%Push(##class(%DynamicObject).%FromJSON(json))
    }
    Quit out
}

Storage Default
{
<Data name="ToolCallDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>RunKey</Value>
</Value>
<Value name="3">
<Value>Seq</Value>
</Value>
<Value name="4">
<Value>At</Value>
</Value>
<Value name="5">
<Value>Name</Value>
</Value>
<Value name="6">
<Value>ArgumentsJSON</Value>
</Value>
<Value name="7">
<Value>DurationMs</Value>
</Value>
<Value name="8">
<Value>Ok</Value>
</Value>
<Value name="9">
<Value>ResultPreview</Value>
</Value>
<Value name="10">
<Value>Error</Value>
</Value>
</Data>
<DataLocation>^Shutter.Bridge.ToolCallD</DataLocation>
<DefaultData>ToolCallDefaultData</DefaultData>
<IdLocation>^Shutter.Bridge.ToolCallD</IdLocation>
<IndexLocation>^Shutter.Bridge.ToolCallI</IndexLocation>
<StreamLocation>^Shutter.Bridge.ToolCallS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
