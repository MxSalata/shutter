/// Every version of the site profile ever stored, with who stored it and from where (CONTRACTS 6.4): the record of
/// the questionnaire's answers over time, case-independent.
Class Shutter.Store.SiteProfileVersion Extends (%Persistent, %JSON.Adaptor)
{

Property Version As %Integer(%JSONFIELDNAME = "version") [ Required ];

Index VersionIdx On Version [ Unique ];

Property Json As %String(%JSONFIELDNAME = "profile", MAXLEN = "");

/// seed, api, install.
Property Source As %String(%JSONFIELDNAME = "source", MAXLEN = 32);

Property UpdatedAt As %String(%JSONFIELDNAME = "updatedAt", MAXLEN = 30);

Property UpdatedBy As %String(%JSONFIELDNAME = "updatedBy", MAXLEN = 100);

/// The versions, newest first, as objects (the profile itself included).
ClassMethod History(limit As %Integer = 50) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ (+limit) _ " ID FROM Shutter_Store.SiteProfileVersion ORDER BY Version DESC")
    While rs.%Next() {
        Set v = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(v)
        Set o = {}
        Set o.version = v.Version, o.source = v.Source, o.updatedAt = v.UpdatedAt, o.updatedBy = v.UpdatedBy
        Set p = ##class(Shutter.Util.Json).Parse(v.Json, .sc)
        If $ISOBJECT(p) Set o.profile = p
        Do out.%Push(o)
    }
    Quit out
}

Storage Default
{
<Data name="SiteProfileVersionDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Version</Value>
</Value>
<Value name="3">
<Value>Json</Value>
</Value>
<Value name="4">
<Value>Source</Value>
</Value>
<Value name="5">
<Value>UpdatedAt</Value>
</Value>
<Value name="6">
<Value>UpdatedBy</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.SiteProfileD188D</DataLocation>
<DefaultData>SiteProfileVersionDefaultData</DefaultData>
<IdLocation>^Shutter.Store.SiteProfileD188D</IdLocation>
<IndexLocation>^Shutter.Store.SiteProfileD188I</IndexLocation>
<StreamLocation>^Shutter.Store.SiteProfileD188S</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
