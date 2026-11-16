/// A catalogue entry (CONTRACTS 6.2): a known failure pattern with its preferred outcome and alternatives, as the
/// matcher reads it. Seeded from knowledge/catalogue/catalogue.json, which scripts/build-catalogue.py writes from
/// the entries' Markdown front matter.
Class Shutter.Catalogue.Entry Extends (%Persistent, %JSON.Adaptor)
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

ClassMethod ById(id As %String) As Shutter.Catalogue.Entry
{
    // A site's own entry (L<n>, CONTRACTS 6.8) answers here too, as an entry that is never stored in this table: the
    // gate's lookup then words a plan that names a site entry whose pattern does not hold as PATTERN_NOT_MATCHED.
    If ##class(Shutter.Catalogue.SiteEntry).IsSiteId(id) {
        Set site = ##class(Shutter.Catalogue.SiteEntry).ById(id)
        If '$ISOBJECT(site) Quit ""
        Set e = ..%New()
        Set e.EntryId = id, e.Version = site.ActiveVersion, e.Decides = "person", e.Source = "site"
        Quit e
    }
    Quit ..Shipped(id)
}

/// A shipped entry's row, or "".
ClassMethod Shipped(id As %String) As Shutter.Catalogue.Entry [ Private ]
{
    Set rid = ""
    &sql(SELECT ID INTO :rid FROM Shutter_Catalogue.Entry WHERE EntryId = :id)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ..%OpenId(rid)
}

/// How many entries the catalogue has.
ClassMethod Count() As %Integer
{
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Catalogue.Entry)
    Quit +n
}

/// A version string for the whole catalogue: the shipped entries' ids and versions, in order, and, on a site that has
/// ever activated an entry of its own (CONTRACTS 6.8), ";g<n>:" and the active site entries ("...,E9@1;g7:L1@2,L4@1").
/// <n> is a generation that rises at every activation, suspension, resumption and retirement and never comes down, so an
/// approval voided by one change is not made valid again by undoing it. A site that never had one keeps the shipped string.
ClassMethod CatalogueVersion() As %String
{
    Quit ..ShippedVersion() _ ##class(Shutter.Catalogue.SiteEntry).VersionSuffix()
}

/// The shipped entries' ids and versions, in order.
ClassMethod ShippedVersion() As %String
{
    Set parts = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT EntryId, Version FROM Shutter_Catalogue.Entry ORDER BY EntryId")
    While rs.%Next() { Set parts = parts _ $SELECT(parts = "": "", 1: ",") _ rs.%Get("EntryId") _ "@" _ rs.%Get("Version") }
    Quit parts
}

/// Every entry as a dynamic object, in id order.
ClassMethod All() As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Catalogue.Entry ORDER BY EntryId")
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
    Set o.scenarios = ##class(Shutter.Util.Json).Parse($SELECT(..ScenariosJSON = "": "[]", 1: ..ScenariosJSON), .sc)
    Set o.pattern = ##class(Shutter.Util.Json).Parse($SELECT(..PatternJSON = "": "{}", 1: ..PatternJSON), .sc)
    Set o.preferred = ##class(Shutter.Util.Json).Parse($SELECT(..PreferredJSON = "": "{}", 1: ..PreferredJSON), .sc)
    Set o.alternatives = ##class(Shutter.Util.Json).Parse($SELECT(..AlternativesJSON = "": "[]", 1: ..AlternativesJSON), .sc)
    Set o.checks = ##class(Shutter.Util.Json).Parse($SELECT(..ChecksJSON = "": "[]", 1: ..ChecksJSON), .sc)
    Set o.prose = ..Prose
    Quit o
}

/// Seed (replace) the catalogue from catalogue.json: an array of entries in the front matter's shape, each with
/// "prose". Entries missing from the file are removed, so the file is the whole catalogue.
ClassMethod SeedFromFile(path As %String, Output count As %Integer) As %Status
{
    Set count = 0
    If '##class(%File).Exists(path) Quit $$$OK
    Set text = ##class(Shutter.Knowledge.Text).ReadFile(path)
    Set list = ##class(Shutter.Util.Json).Parse(text, .sc)
    If '$ISOBJECT(list) || $$$ISERR(sc) Quit $$$ERROR($$$GeneralError, "catalogue.json is not JSON: " _ $SYSTEM.Status.GetErrorText(sc))
    Set keep = ""
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .d) {
        Set id = ##class(Shutter.Util.Json).Str(d, "id")
        Continue:id=""
        // A shipped entry is E<n>. Any other id is refused: L<n> is a site's own entry, which lives in its own tables
        // and can only ever send a case to a person (CONTRACTS 6.8).
        If '$MATCH(id, "E[1-9][0-9]*") Set sc = $$$ERROR($$$GeneralError, "catalogue.json names the entry " _ id _ ": a shipped entry's id is E<n>") Quit
        Set e = ..Shipped(id)
        If '$ISOBJECT(e) Set e = ..%New(), e.EntryId = id
        Set e.Version = +##class(Shutter.Util.Json).Str(d, "version", 1)
        Set e.Title = ##class(Shutter.Util.Json).Str(d, "title"), e.Decides = ##class(Shutter.Util.Json).Str(d, "decides", "board")
        Set e.ScenariosJSON = ##class(Shutter.Util.Json).Text(d.%Get("scenarios"))
        Set e.PatternJSON = ##class(Shutter.Util.Json).Text(d.%Get("pattern"))
        Set e.PreferredJSON = ##class(Shutter.Util.Json).Text(d.%Get("preferred"))
        Set e.AlternativesJSON = ##class(Shutter.Util.Json).Text(d.%Get("alternatives"))
        Set e.ChecksJSON = ##class(Shutter.Util.Json).Text(d.%Get("checks"))
        Set e.Prose = ##class(Shutter.Util.Json).Str(d, "prose"), e.Source = path
        Set sc = e.%Save()
        Quit:$$$ISERR(sc)
        Set count = count + 1, keep = keep _ $LISTBUILD(id)
    }
    Quit:$$$ISERR(sc) sc
    // Entries no longer in the file go.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, EntryId FROM Shutter_Catalogue.Entry")
    While rs.%Next() { If '$LISTFIND(keep, rs.%Get("EntryId")) Do ..%DeleteId(rs.%Get("ID")) }
    // The vocabulary that came with the file, and the site's own entries checked against it and against this release's
    // matcher before any case is matched (CONTRACTS 6.8, R14). The seed never touches their tables. A recheck that fails
    // is tried again at the first match, so it never stops an install.
    // A vocabulary file that is there and is not the vocabulary leaves the old one in force: the entries are then not
    // checked against it, the release is not recorded as checked, and the first match tries again (reading the file).
    Set lsc = ##class(Shutter.Catalogue.Vocabulary).Load(##class(%File).GetDirectory(path) _ "vocabulary.json")
    If $$$ISERR(lsc) {
        Try { Do ##class(%SYS.System).WriteToConsoleLog("Shutter: the catalogue's vocabulary could not be loaded: " _ $SYSTEM.Status.GetErrorText(lsc), 0, 1) } Catch ex { }
        Try { Kill ^Shutter.Catalogue.Site("checked") } Catch ex { }
        Quit sc
    }
    Try { Do ##class(Shutter.Catalogue.SiteEntry).Recheck("upgrade", 0) } Catch ex { Kill ^Shutter.Catalogue.Site("checked") }
    Quit sc
}

/// Seed (replace) the catalogue from JSON text, for tests and tools, on a demo instance only. Returns the count or the error.
ClassMethod SeedFromJSON(json As %String) As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("Shutter_Approve", "USE") Quit "Shutter_Approve is required to replace the catalogue"
    // Replacing the whole catalogue from any JSON, with no validation, version record or audit, is a demo's and a
    // test's tool: a site's catalogue is the shipped file and its own approved entries (CONTRACTS 6.8).
    If '$GET(^Shutter.Config("demo")) Quit "error: not a demo instance: a site's catalogue is the shipped file and its own approved entries"
    Set path = ##class(%File).NormalizeDirectory($SYSTEM.Util.ManagerDirectory() _ "shutter") _ "catalogue-seed.json"
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
<DataLocation>^Shutter.Catalogue.EntryD</DataLocation>
<DefaultData>EntryDefaultData</DefaultData>
<IdLocation>^Shutter.Catalogue.EntryD</IdLocation>
<IndexLocation>^Shutter.Catalogue.EntryI</IndexLocation>
<StreamLocation>^Shutter.Catalogue.EntryS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
