/// One call of the publisher's tools (CONTRACTS 15, v1.35): who asked which tool about what, at which version of the
/// case, and how long it took. Never the answer: the audit says a case was read, not what was read.
Class Shutter.Store.PublishCall Extends (%Persistent, %JSON.Adaptor)
{

/// When the call was made (the column is CalledAt, since At is a word SQL keeps).
Property CalledAt As %String(%JSONFIELDNAME = "at", MAXLEN = 30);

Index CalledIdx On CalledAt;

/// The IRIS user the gateway authenticated.
Property User As %String(%JSONFIELDNAME = "user", MAXLEN = 100);

Property Tool As %String(%JSONFIELDNAME = "tool", MAXLEN = 64);

/// The case or incident id, a filter ("awaiting_approval@Downstream Out"), or empty.
Property Target As %String(%JSONFIELDNAME = "target", MAXLEN = 200);

/// The case's version when it was read, so a later question "what did they see" has an answer.
Property Version As %String(%JSONFIELDNAME = "version", MAXLEN = 20);

Property DurationMs As %Integer(%JSONFIELDNAME = "durationMs");

ClassMethod Record(tool As %String, target As %String = "", version As %String = "", durationMs As %Integer = "") As %Status
{
    Set c = ..%New()
    Set c.CalledAt = ##class(Shutter.Util.Time).NowUTC(), c.User = $SELECT($USERNAME = "UnknownUser": "", 1: $USERNAME)
    Set c.Tool = $EXTRACT(tool, 1, 64), c.Target = $EXTRACT(target, 1, 200), c.Version = version
    If durationMs '= "" Set c.DurationMs = +durationMs
    Quit c.%Save()
}

/// How many calls since an ISO UTC time.
ClassMethod CountSince(sinceIso As %String) As %Integer
{
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.PublishCall WHERE CalledAt >= :sinceIso)
    Quit +n
}

/// The newest calls, newest first.
ClassMethod Recent(n As %Integer = 50) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP ? ID FROM Shutter_Store.PublishCall ORDER BY ID DESC", +n)
    While rs.%Next() {
        Set c = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Set sc = c.%JSONExportToString(.json)
        Set o = ##class(%DynamicObject).%FromJSON($SELECT($$$ISOK(sc): json, 1: "{}"))
        Set o.id = c.%Id()
        Do out.%Push(o)
    }
    Quit out
}

Storage Default
{
<Data name="PublishCallDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>CalledAt</Value>
</Value>
<Value name="3">
<Value>User</Value>
</Value>
<Value name="4">
<Value>Tool</Value>
</Value>
<Value name="5">
<Value>Target</Value>
</Value>
<Value name="6">
<Value>Version</Value>
</Value>
<Value name="7">
<Value>DurationMs</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.PublishCallD</DataLocation>
<DefaultData>PublishCallDefaultData</DefaultData>
<IdLocation>^Shutter.Store.PublishCallD</IdLocation>
<IndexLocation>^Shutter.Store.PublishCallI</IndexLocation>
<StreamLocation>^Shutter.Store.PublishCallS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
