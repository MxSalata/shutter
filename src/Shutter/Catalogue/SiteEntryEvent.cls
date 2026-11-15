/// What was done to a site's own entry (CONTRACTS 6.8), who did it, when and from where: created, edited, proved,
/// proposed, approved, rejected, activated, suspended, resumed, retired, rechecked, and the two events of the site as a
/// whole (two_person_lifted, two_person_restored), whose EntryId is empty. Rows are only ever added.
Class Shutter.Catalogue.SiteEntryEvent Extends (%Persistent, %JSON.Adaptor)
{

Property EntryId As %String(%JSONFIELDNAME = "id", MAXLEN = 16);

Index EntryIdx On EntryId;

Property Version As %Integer(%JSONFIELDNAME = "version");

Property Kind As %String(%JSONFIELDNAME = "kind", MAXLEN = 32) [ Required ];

Property Actor As %String(%JSONFIELDNAME = "actor", MAXLEN = 160);

Property At As %String(%JSONFIELDNAME = "at", MAXLEN = 30);

/// api, upgrade, profile or terminal.
Property Source As %String(%JSONFIELDNAME = "source", MAXLEN = 16);

Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = 2000);

/// What the event points at: a proof, a digest.
Property Ref As %String(%JSONFIELDNAME = "ref", MAXLEN = 120);

ClassMethod Record(entryId As %String, version As %String, kind As %String, actor As %String, source As %String, text As %String = "", ref As %String = "") As %Status
{
    Set e = ..%New()
    Set e.EntryId = entryId, e.Kind = kind, e.Actor = $EXTRACT(actor, 1, 160), e.Source = source
    If version '= "" Set e.Version = +version
    Set e.At = ##class(Shutter.Util.Time).NowUTC(), e.Text = $EXTRACT(text, 1, 2000), e.Ref = $EXTRACT(ref, 1, 120)
    Quit e.%Save()
}

/// An entry's events, newest first.
ClassMethod For(entryId As %String, limit As %Integer = 200) As %DynamicArray
{
    Quit ##class(Shutter.Util.Json).Rows($CLASSNAME(), "SELECT TOP " _ (+limit) _ " ID FROM Shutter_Catalogue.SiteEntryEvent WHERE EntryId = ? ORDER BY ID DESC", entryId)
}

Storage Default
{
<Data name="SiteEntryEventDefaultData">
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
<Value>Kind</Value>
</Value>
<Value name="5">
<Value>Actor</Value>
</Value>
<Value name="6">
<Value>At</Value>
</Value>
<Value name="7">
<Value>Source</Value>
</Value>
<Value name="8">
<Value>Text</Value>
</Value>
<Value name="9">
<Value>Ref</Value>
</Value>
</Data>
<DataLocation>^Shutter.Cat5ADA.SiteEntryEventD</DataLocation>
<DefaultData>SiteEntryEventDefaultData</DefaultData>
<IdLocation>^Shutter.Cat5ADA.SiteEntryEventD</IdLocation>
<IndexLocation>^Shutter.Cat5ADA.SiteEntryEventI</IndexLocation>
<StreamLocation>^Shutter.Cat5ADA.SiteEntryEventS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
