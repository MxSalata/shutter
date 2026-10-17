/// A catalogue entry (CONTRACTS 6.2): a known failure pattern with its preferred outcome and alternatives, as the
/// matcher reads it. Seeded from knowledge/catalogue/catalogue.json, which scripts/build-catalogue.py writes from
/// the entries' Markdown front matter.
Class Interlock.Catalogue.Entry Extends (%Persistent, %JSON.Adaptor)
{

/// E1, E2, ...
Property EntryId As %String(%JSONFIELDNAME = "id", MAXLEN = 16) [ Required ];

Index EntryIdx On EntryId [ Unique ];

Property Version As %Integer(%JSONFIELDNAME = "version") [ InitialExpression = 1 ];

Property Title As %String(%JSONFIELDNAME = "title", MAXLEN = 200);

/// The scenarios the entry covers, as a JSON array.
Property ScenariosJSON As %String(%JSONFIELDNAME = "scenarios", MAXLEN = 400);

/// The pattern: a JSON object of condition to a value or an array of values (CONTRACTS 6.1).
Property PatternJSON As %String(%JSONFIELDNAME = "pattern", MAXLEN = "");

/// policy, board or person.
Property Decides As %String(%JSONFIELDNAME = "decides", MAXLEN = 16);

/// {outcome, why}
Property PreferredJSON As %String(%JSONFIELDNAME = "preferred", MAXLEN = "");

/// [{outcome, why, when}]
Property AlternativesJSON As %String(%JSONFIELDNAME = "alternatives", MAXLEN = "");

Property ChecksJSON As %String(%JSONFIELDNAME = "checks", MAXLEN = 400);

/// The prose for the board, from the Markdown after the front matter.
Property Prose As %String(%JSONFIELDNAME = "prose", MAXLEN = "");

Property Source As %String(%JSONFIELDNAME = "source", MAXLEN = 300);

ClassMethod ById(id As %String) As Interlock.Catalogue.Entry
{
    Set rid = ""
    &sql(SELECT ID INTO :rid FROM Interlock_Catalogue.Entry WHERE EntryId = :id)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ..%OpenId(rid)
}

/// How many entries the catalogue has.
ClassMethod Count() As %Integer
{
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Interlock_Catalogue.Entry)
    Quit +n
}

/// A version string for the whole catalogue: the entries' ids and versions, in order.
ClassMethod CatalogueVersion() As %String
{
    Set parts = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT EntryId, Version FROM Interlock_Catalogue.Entry ORDER BY EntryId")
    While rs.%Next() { Set parts = parts _ $SELECT(parts = "": "", 1: ",") _ rs.%Get("EntryId") _ "@" _ rs.%Get("Version") }
    Quit parts
}

/// Every entry as a dynamic object, in id order.
ClassMethod All() As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Catalogue.Entry ORDER BY EntryId")
    While rs.%Next() {
        Set e = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(e)
        Do out.%Push(e.ToObject())
    }
    Quit out
}

/// The entry with its JSON fields parsed.
Method ToObject() As %DynamicObject
{
    Set o = {}
    Set o.id = ..EntryId, o.version = ..Version, o.title = ..Title, o.decides = ..Decides
    Set o.scenarios = ##class(Interlock.Util.Json).Parse($SELECT(..ScenariosJSON = "": "[]", 1: ..ScenariosJSON), .sc)
    Set o.pattern = ##class(Interlock.Util.Json).Parse($SELECT(..PatternJSON = "": "{}", 1: ..PatternJSON), .sc)
    Set o.preferred = ##class(Interlock.Util.Json).Parse($SELECT(..PreferredJSON = "": "{}", 1: ..PreferredJSON), .sc)
    Set o.alternatives = ##class(Interlock.Util.Json).Parse($SELECT(..AlternativesJSON = "": "[]", 1: ..AlternativesJSON), .sc)
    Set o.checks = ##class(Interlock.Util.Json).Parse($SELECT(..ChecksJSON = "": "[]", 1: ..ChecksJSON), .sc)
    Quit o
}

/// Seed (replace) the catalogue from catalogue.json: an array of entries in the front matter's shape, each with
/// "prose". Entries missing from the file are removed, so the file is the whole catalogue.
ClassMethod SeedFromFile(path As %String, Output count As %Integer) As %Status
{
    Set count = 0
    If '##class(%File).Exists(path) Quit $$$OK
    Set text = ##class(Interlock.Knowledge.Text).ReadFile(path)
    Set list = ##class(Interlock.Util.Json).Parse(text, .sc)
    If '$ISOBJECT(list) || $$$ISERR(sc) Quit $$$ERROR($$$GeneralError, "catalogue.json is not JSON: " _ $SYSTEM.Status.GetErrorText(sc))
    Set keep = ""
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .d) {
        Set id = ##class(Interlock.Util.Json).Str(d, "id")
        Continue:id=""
        Set e = ..ById(id)
        If '$ISOBJECT(e) Set e = ..%New(), e.EntryId = id
        Set e.Version = +##class(Interlock.Util.Json).Str(d, "version", 1)
        Set e.Title = ##class(Interlock.Util.Json).Str(d, "title"), e.Decides = ##class(Interlock.Util.Json).Str(d, "decides", "board")
        Set e.ScenariosJSON = ##class(Interlock.Util.Json).Text(d.%Get("scenarios"))
        Set e.PatternJSON = ##class(Interlock.Util.Json).Text(d.%Get("pattern"))
        Set e.PreferredJSON = ##class(Interlock.Util.Json).Text(d.%Get("preferred"))
        Set e.AlternativesJSON = ##class(Interlock.Util.Json).Text(d.%Get("alternatives"))
        Set e.ChecksJSON = ##class(Interlock.Util.Json).Text(d.%Get("checks"))
        Set e.Prose = ##class(Interlock.Util.Json).Str(d, "prose"), e.Source = path
        Set sc = e.%Save()
        Quit:$$$ISERR(sc)
        Set count = count + 1, keep = keep _ $LISTBUILD(id)
    }
    Quit:$$$ISERR(sc) sc
    // Entries no longer in the file go.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, EntryId FROM Interlock_Catalogue.Entry")
    While rs.%Next() { If '$LISTFIND(keep, rs.%Get("EntryId")) Do ..%DeleteId(rs.%Get("ID")) }
    Quit sc
}

/// Seed (replace) the catalogue from JSON text, for tests and tools. Returns the count or the error.
ClassMethod SeedFromJSON(json As %String) As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("Interlock_Approve", "USE") Quit "Interlock_Approve is required to replace the catalogue"
    Set path = ##class(%File).NormalizeDirectory($SYSTEM.Util.ManagerDirectory() _ "interlock") _ "catalogue-seed.json"
    Set stream = ##class(%Stream.FileCharacter).%New()
    Set stream.TranslateTable = "UTF8"
    Set sc = stream.LinkToFile(path)
    If $$$ISOK(sc) Set sc = stream.Write(json)
    If $$$ISOK(sc) Set sc = stream.%Save()
    If $$$ISERR(sc) Quit "error: " _ $SYSTEM.Status.GetErrorText(sc)
    Set sc = ..SeedFromFile(path, .count)
    Quit $SELECT($$$ISOK(sc): "seeded " _ count _ " entries", 1: "error: " _ $SYSTEM.Status.GetErrorText(sc))
}

Storage Default
{
<Data name="EntryDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>EntryId</Value>
</Value>
<Value name="3">
<Value>Version</Value>
</Value>
<Value name="4">
<Value>Title</Value>
</Value>
<Value name="5">
<Value>ScenariosJSON</Value>
</Value>
<Value name="6">
<Value>PatternJSON</Value>
</Value>
<Value name="7">
<Value>Decides</Value>
</Value>
<Value name="8">
<Value>PreferredJSON</Value>
</Value>
<Value name="9">
<Value>AlternativesJSON</Value>
</Value>
<Value name="10">
<Value>ChecksJSON</Value>
</Value>
<Value name="11">
<Value>Prose</Value>
</Value>
<Value name="12">
<Value>Source</Value>
</Value>
</Data>
<DataLocation>^Interlock.Catalogue.EntryD</DataLocation>
<DefaultData>EntryDefaultData</DefaultData>
<IdLocation>^Interlock.Catalogue.EntryD</IdLocation>
<IndexLocation>^Interlock.Catalogue.EntryI</IndexLocation>
<StreamLocation>^Interlock.Catalogue.EntryS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
