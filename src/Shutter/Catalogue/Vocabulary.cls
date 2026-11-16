/// The condition vocabulary (CONTRACTS 6.1) as the core holds it for a site's own entries (6.8): the conditions and
/// their values, the scope facts a site entry may name and the conditions it may not. It is read from
/// knowledge/catalogue/vocabulary.json, which scripts/build-catalogue.py writes and checks the shipped entries against,
/// so the validator of the shipped catalogue and the validator of a site's entries read one file. The copy in force is
/// kept in ^Shutter.Catalogue.Vocabulary, taken whenever the catalogue is seeded.
Class Shutter.Catalogue.Vocabulary
{

/// Take the vocabulary from a file. Returns an error when the file is there and is not the vocabulary; a missing file
/// leaves the copy in force as it is.
ClassMethod Load(path As %String) As %Status
{
    If (path = "") || '##class(%File).Exists(path) Quit $$$OK
    Set text = ##class(Shutter.Knowledge.Text).ReadFile(path)
    Set v = ##class(Shutter.Util.Json).Parse(text, .sc)
    If '$ISOBJECT(v) || $$$ISERR(sc) Quit $$$ERROR($$$GeneralError, "vocabulary.json is not JSON")
    Set problem = ..Problem(v)
    If problem '= "" Quit $$$ERROR($$$GeneralError, "vocabulary.json is not the vocabulary: " _ problem)
    Do ..Use(v)
    Quit $$$OK
}

/// What keeps an object from being the vocabulary, or "".
ClassMethod Problem(v As %DynamicObject) As %String
{
    If '$ISOBJECT(v) || 'v.%IsA("%Library.DynamicObject") Quit "not an object"
    Set conditions = v.%Get("conditions")
    If '$ISOBJECT(conditions) || 'conditions.%IsA("%Library.DynamicObject") || (conditions.%Size() = 0) Quit "it lists no conditions"
    Set it = conditions.%GetIterator()
    While it.%GetNext(.name, .values) {
        If '$ISOBJECT(values) || 'values.%IsA("%Library.DynamicArray") || (values.%Size() = 0) Return "the condition " _ name _ " lists no values"
    }
    Quit ""
}

/// Put a vocabulary in force (the seed, and the tests of an upgrade that knows fewer conditions).
/// Another vocabulary than the one in force is something the site's entries are checked against again before the next
/// case is matched on them (Shutter.Catalogue.SiteEntry.InputsChanged).
ClassMethod Use(v As %DynamicObject)
{
    Set json = v.%ToJSON(), changed = ($GET(^Shutter.Catalogue.Vocabulary("json")) '= json)
    Kill ^Shutter.Catalogue.Vocabulary
    Set ^Shutter.Catalogue.Vocabulary("json") = json
    Set ^Shutter.Catalogue.Vocabulary("at") = ##class(Shutter.Util.Time).NowUTC()
    If changed Do ##class(Shutter.Catalogue.SiteEntry).InputsChanged()
}

/// The vocabulary in force, or "" when none was ever taken and the installed root holds no file.
ClassMethod Current() As %DynamicObject
{
    Set json = $GET(^Shutter.Catalogue.Vocabulary("json"))
    If json = "" {
        Set root = $GET(^Shutter.Config("root"))
        // A caller that only reads cannot keep the copy: it reads the file itself this once.
        Set path = $SELECT(root '= "": ##class(%File).NormalizeDirectory(root) _ "knowledge/catalogue/vocabulary.json", 1: "")
        Try { Do ..Load(path) } Catch ex { }
        Set json = $GET(^Shutter.Catalogue.Vocabulary("json"))
        If (json = "") && (path '= "") && ##class(%File).Exists(path) Set json = ##class(Shutter.Knowledge.Text).ReadFile(path)
    }
    If json = "" Quit ""
    Quit ##class(Shutter.Util.Json).Parse(json, .sc)
}

/// The values a condition takes, or "" for a condition the vocabulary does not know.
ClassMethod ValuesOf(v As %DynamicObject, condition As %String) As %DynamicArray
{
    If '$ISOBJECT(v) Quit ""
    Set conditions = v.%Get("conditions")
    If '$ISOBJECT(conditions) || (conditions.%GetTypeOf(condition) '= "array") Quit ""
    Quit conditions.%Get(condition)
}

/// Whether a value is one of a list's.
ClassMethod In(list As %DynamicArray, value As %String) As %Boolean
{
    If '$ISOBJECT(list) Quit 0
    Set it = list.%GetIterator()
    While it.%GetNext(, .v) { If ("" _ v) = ("" _ value) Return 1 }
    Quit 0
}

/// A list of the site section (kinds, scope, reserved_conditions), with the built-in answer when the file names none.
ClassMethod SiteList(v As %DynamicObject, name As %String) As %DynamicArray
{
    Set site = $SELECT($ISOBJECT(v): v.%Get("site"), 1: "")
    If $ISOBJECT(site) && (site.%GetTypeOf(name) = "array") Quit site.%Get(name)
    Quit $CASE(name, "kinds": ["stop"], "scope": ["receiver", "source_system", "ward", "reason_code"], "reserved_conditions": ["death_recorded"], : [])
}

}
