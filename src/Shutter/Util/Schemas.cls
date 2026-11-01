/// HL7 schemas as this namespace holds them (CONTRACTS 12, v1.32): which categories are loaded (the class query
/// EnsLib.HL7.Schema:TypeCategories), which the production's HL7 services and the recent messages name, and the import of a
/// site's own schema through IRIS's own importer (EnsLib.HL7.SchemaXML). A message whose category is not loaded cannot be
/// validated: the evidence says "unknown schema", not "invalid message", and the gate blocks with SCHEMA_UNKNOWN naming the
/// fix (Shutter.Setup.ImportSchema, or POST /settings/schemas), which a person applies and then reinvestigates the case.
Class Shutter.Util.Schemas
{

/// The schema categories loaded in this namespace, standard ones first, each {category, standard, base}.
ClassMethod Categories() As %DynamicArray
{
    Set out = []
    Try {
        Set rs = ##class(%ResultSet).%New("EnsLib.HL7.Schema:TypeCategories")
        If rs.Execute() {
            While rs.Next() {
                Set c = {}
                Set c.category = rs.Get("Category")
                Do c.%Set("standard", ''rs.Get("IsStandard"), "boolean")
                Set c.base = rs.Get("Base")
                Do out.%Push(c)
            }
        }
    } Catch ex {
    }
    Quit out
}

/// Whether a category is loaded here. Cached per process; an import clears the cache.
ClassMethod Known(category As %String) As %Boolean
{
    Set category = $ZSTRIP(category, "<>W")
    If category = "" Quit 0
    If $DATA(^||Shutter.SchemaKnown(category)) Quit ^||Shutter.SchemaKnown(category)
    Set known = 0
    Set list = ..Categories(), li = list.%GetIterator()
    While li.%GetNext(, .c) { If c.category = category Set known = 1 Quit }
    Set ^||Shutter.SchemaKnown(category) = known
    Quit known
}

/// The categories this namespace needs: every MessageSchemaCategory setting of the productions' items (as stored and as
/// the item classes default), and the categories of the newest HL7 messages in the store (the forwarded messages name their
/// source's schema). Each {category, where, known}, missing ones first.
ClassMethod Needed(recent As %Integer = 500) As %DynamicArray
{
    Set json = "Shutter.Util.Json", seen = "", out = []
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT i.Name AS Item, i.Production AS Production, s.SettingValue AS Category FROM Ens_Config.Item i JOIN Ens_Config.Setting s ON s.Item = i.ID WHERE s.Name = 'MessageSchemaCategory' AND s.SettingValue IS NOT NULL AND s.SettingValue <> ''")
        While rs.%Next() {
            Set cat = $ZSTRIP(rs.%Get("Category"), "<>W")
            Continue:(cat = "")
            Do ..Note(.out, .seen, cat, "item " _ rs.%Get("Item") _ " of " _ rs.%Get("Production"))
        }
    } Catch ex {
    }
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ (+recent) _ " DocType FROM EnsLib_HL7.Message WHERE DocType IS NOT NULL AND DocType <> '' ORDER BY ID DESC")
        While rs.%Next() {
            Set cat = $PIECE(rs.%Get("DocType"), ":", 1)
            Continue:(cat = "")
            Do ..Note(.out, .seen, cat, "the newest " _ (+recent) _ " HL7 messages in the store")
        }
    } Catch ex {
    }
    // Missing first, then by name.
    Set sorted = []
    For pass = 0, 1 {
        Set oi = out.%GetIterator()
        While oi.%GetNext(, .o) { If o.known = pass Do sorted.%Push(o) }
    }
    Quit sorted
}

ClassMethod Note(ByRef out As %DynamicArray, ByRef seen As %String, category As %String, where As %String) [ Private ]
{
    If $LISTFIND(seen, category) {
        Set oi = out.%GetIterator()
        While oi.%GetNext(, .o) { If (o.category = category) && (o.where '[ where) Set o.where = o.where _ "; " _ where }
        Quit
    }
    Set seen = seen _ $LISTBUILD(category)
    Set o = {}
    Set o.category = category, o.where = where
    Do o.%Set("known", ..Known(category), "boolean")
    Do out.%Push(o)
}

/// The Doctor's view: {loaded: [...], needed: [...], missing: [category...], fix}.
ClassMethod Report() As %DynamicObject
{
    Set r = {}
    Set r.loaded = ..Categories()
    Set r.needed = ..Needed()
    Set missing = []
    Set ni = r.needed.%GetIterator()
    While ni.%GetNext(, .n) { If 'n.known Do missing.%Push(n.category) }
    Set r.missing = missing
    Set r.fix = $SELECT(missing.%Size() = 0: "", 1: "Import the site's schema XML (exported from the source system's IRIS, or written for it) with SELECT Shutter.Setup_ImportSchema('<path on this server>') or POST /settings/schemas, then reinvestigate the cases that say unknown schema")
    Quit r
}

/// Import a schema XML file through IRIS's own importer (EnsLib.HL7.SchemaXML.Import): a readable .xml file on this server.
/// category is the category the file defined. The known-category cache is cleared on success.
ClassMethod Import(path As %String, Output category As %String) As %Status
{
    Set category = ""
    Set path = $ZSTRIP(path, "<>W")
    If path = "" Quit $$$ERROR($$$GeneralError, "A path to a schema XML file is needed")
    If $ZCONVERT($EXTRACT(path, * - 3, *), "L") '= ".xml" Quit $$$ERROR($$$GeneralError, "The schema file must be an .xml file (an HL7 schema export)")
    If '##class(%File).Exists(path) Quit $$$ERROR($$$GeneralError, "No file " _ path _ " on this server")
    Set sc = ##class(EnsLib.HL7.SchemaXML).Import(path, .category)
    If $$$ISERR(sc) Quit sc
    Kill ^||Shutter.SchemaKnown
    Try { Do ##class(Ens.Util.Log).LogInfo($CLASSNAME(), "Import", "HL7 schema category " _ category _ " imported from " _ path) } Catch {}
    Quit $$$OK
}

}
