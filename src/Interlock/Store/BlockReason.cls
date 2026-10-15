/// The catalogue of blocked reasons: for each reason code the gate or the workflow can produce,
/// what is missing, the next permitted action, who owns it and what triggers a re-evaluation. The
/// texts come from knowledge/block-reasons.json; the app renders them beside a blocked case.
Class Interlock.Store.BlockReason Extends (%Persistent, %JSON.Adaptor)
{

Property Code As %String(%JSONFIELDNAME = "code", MAXLEN = 64) [ Required ];

Index CodeIdx On Code [ Unique ];

Property Title As %String(%JSONFIELDNAME = "title", MAXLEN = 200);

Property Prerequisite As %String(%JSONFIELDNAME = "prerequisite", MAXLEN = 1000);

Property NextAction As %String(%JSONFIELDNAME = "nextAction", MAXLEN = 1000);

Property Owner As %String(%JSONFIELDNAME = "owner", MAXLEN = 100);

Property ReevaluateWhen As %String(%JSONFIELDNAME = "reevaluateWhen", MAXLEN = 1000);

Property Text As %String(%JSONFIELDNAME = "text", MAXLEN = 4000);

ClassMethod ByCode(code As %String) As Interlock.Store.BlockReason
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Interlock_Store.BlockReason WHERE Code = :code)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// Load the catalogue from a JSON file: an array of objects with code, title, prerequisite,
/// next_action, owner, reevaluate_when and text. Existing codes are replaced. Returns the count.
ClassMethod SeedFromFile(path As %String, Output count As %Integer) As %Status
{
    Set count = 0
    If '##class(%File).Exists(path) Quit $$$OK
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.Filename = path
    Set json = f.Read($$$MaxStringLength)
    Set arr = ##class(Interlock.Util.Json).Parse(json, .sc)
    Quit:$$$ISERR(sc) sc
    If '$ISOBJECT(arr) Quit $$$OK
    If arr.%IsA("%Library.DynamicObject") && $ISOBJECT(arr.%Get("reasons")) Set arr = arr.%Get("reasons")
    Set iter = arr.%GetIterator()
    While iter.%GetNext(.i, .d) {
        Set code = ##class(Interlock.Util.Json).Str(d, "code")
        Continue:(code="")
        Set r = ..ByCode(code)
        If '$ISOBJECT(r) Set r = ..%New(), r.Code = code
        Set r.Title = ##class(Interlock.Util.Json).Str(d, "title")
        Set r.Prerequisite = ##class(Interlock.Util.Json).Str(d, "prerequisite")
        Set r.NextAction = ##class(Interlock.Util.Json).Str(d, "next_action", ##class(Interlock.Util.Json).Str(d, "nextAction"))
        Set r.Owner = ##class(Interlock.Util.Json).Str(d, "owner")
        Set r.ReevaluateWhen = ##class(Interlock.Util.Json).Str(d, "reevaluate_when", ##class(Interlock.Util.Json).Str(d, "reevaluateWhen"))
        Set r.Text = ##class(Interlock.Util.Json).Str(d, "text")
        Set sc = r.%Save()
        Quit:$$$ISERR(sc)
        Set count = count + 1
    }
    Quit sc
}

}
