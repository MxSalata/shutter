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

/// Whether a category is loaded here. Cached per process behind an epoch (^Shutter.Config("schemaEpoch")) that an import
/// moves, so the production's long-lived jobs see a schema imported by another process (v1.34).
ClassMethod Known(category As %String) As %Boolean
{
    Set category = $ZSTRIP(category, "<>W")
    If category = "" Quit 0
    Set epoch = $GET(^Shutter.Config("schemaEpoch"), 0)
    If $GET(^||Shutter.SchemaKnown) '= epoch { Kill ^||Shutter.SchemaKnown  Set ^||Shutter.SchemaKnown = epoch }
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
    // The productions' items whose definition sets MessageSchemaCategory. Item settings are a list inside Ens.Config.Item
    // (no table of their own), so they are read through the objects, as the production review does.
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Ens_Config.Production")
        While rs.%Next() {
            Set prod = ##class(Ens.Config.Production).%OpenId(rs.%Get("Name"), 0)
            Continue:'$ISOBJECT(prod)
            For i = 1:1:prod.Items.Count() {
                Set item = prod.Items.GetAt(i)
                For j = 1:1:item.Settings.Count() {
                    Set setting = item.Settings.GetAt(j)
                    Continue:(setting.Name '= "MessageSchemaCategory")
                    Set cat = $ZSTRIP(setting.Value, "<>W")
                    Continue:(cat = "")
                    Do ..Note(.out, .seen, cat, "item " _ item.Name _ " of " _ prod.Name)
                }
            }
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
    // The watched namespaces' services (v1.42): what a forward will name, read in each namespace, by the name Shutter holds
    // it under. A category a forward named and this namespace lacked (the intake's note) stands until it is loaded.
    Try {
        Set watched = ##class(Shutter.Util.Onboard).Watched(), wi = watched.%GetIterator()
        While wi.%GetNext(, .w) {
            Set mi = w."schemas_missing".%GetIterator()
            While mi.%GetNext(, .cat) { Do ..Note(.out, .seen, cat, "a service of " _ w.production _ " in " _ w.namespace) }
        }
        Set cat = ""
        For {
            Set cat = $ORDER(^Shutter.Config("schemaNamed", cat), 1, from) Quit:cat=""
            Do ..Note(.out, .seen, cat, "a message forwarded from " _ from)
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
    Set r.fix = $SELECT(missing.%Size() = 0: "", 1: "Import the category from its namespace with Write ##class(Shutter.Util.Schemas).ImportFrom(""<namespace>"",""<category>""), or the site's schema XML with SELECT Shutter.Setup_ImportSchema('<path on this server>') (it replaces a same-named category whole) or POST /settings/schemas, then reinvestigate the cases that say unknown schema")
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
    Do ..Changed()
    Kill ^Shutter.Config("schemaNamed", category)
    Try { Do ##class(Ens.Util.Log).LogInfo($CLASSNAME(), "Import", "HL7 schema category " _ category _ " imported from " _ path) } Catch {}
    Quit $$$OK
}

/// The loaded categories changed (an import, here or seen by the release check): every process's cache is stale.
ClassMethod Changed()
{
    If $INCREMENT(^Shutter.Config("schemaEpoch"))
    Kill ^||Shutter.SchemaKnown
}

/// The name a source namespace's category has here: the alias it was imported under when that name held something else
/// (v1.42), else its own.
ClassMethod LocalName(namespace As %String, category As %String) As %String
{
    Set alias = ..Alias(namespace, category)
    Quit $SELECT(alias '= "": alias, 1: category)
}

/// The alias of a source namespace's category, or "".
ClassMethod Alias(namespace As %String, category As %String) As %String
{
    If (namespace = "") || (category = "") Quit ""
    Quit $GET(^Shutter.Config("schemaAlias", namespace, category))
}

/// A digest of a category's definition as a namespace holds it, by IRIS's own export; "" when it cannot be exported. Two
/// namespaces' categories with one digest are one schema.
ClassMethod Fingerprint(namespace As %String, category As %String) As %String
{
    Set digest = "", file = ##class(%File).TempFilename("xml")
    New $NAMESPACE
    Try {
        If namespace '= "" Set $NAMESPACE = namespace
        Set sc = ##class(EnsLib.HL7.SchemaXML).Export(category, file)
        If $$$ISOK(sc) {
            Set stream = ##class(%Stream.FileCharacter).%New()
            Do stream.LinkToFile(file)
            Set digest = $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.SHA1HashStream(stream))
            Kill stream
        }
    } Catch ex {
        Set digest = ""
    }
    Do ##class(%File).Delete(file)
    Quit digest
}

/// What a source namespace's custom category needs here (v1.42): none (the same schema is loaded under the name it has
/// here), import (the name is free), or import_as with the alias to import it under, since IRIS's importer replaces a
/// category of that name whole and with no warning, and the schema loaded there serves another namespace.
ClassMethod ImportNeeded(namespace As %String, category As %String, Output as As %String) As %String
{
    Set as = ..Alias(namespace, category)
    If as '= "" Quit $SELECT(..Known(as): "none", 1: "import_as")
    If '..Known(category) Set as = category Quit "import"
    If ..Fingerprint(namespace, category) = ..Fingerprint("", category) Quit "none"
    Set as = $TRANSLATE(namespace, "%") _ "_" _ category
    Quit "import_as"
}

/// IRIS's export of a category, run in the namespace that holds it; the caller stays where it is.
ClassMethod ExportFrom(namespace As %String, category As %String, file As %String) As %Status
{
    New $NAMESPACE
    Try {
        Set $NAMESPACE = namespace
        Set sc = ##class(EnsLib.HL7.SchemaXML).Export(category, file)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Imports a source namespace's category here, under the name as (empty: its own), by IRIS's own export and import; an
/// alias is recorded, so the intake reads that namespace's forwards under it. The source namespace is not changed.
ClassMethod ImportFrom(namespace As %String, category As %String, as As %String = "") As %Status
{
    If $SYSTEM.Security.Check("%Admin_Manage", "USE") = 0 Quit $$$ERROR($$$GeneralError, "Importing a schema from another namespace needs %Admin_Manage")
    Set file = ##class(%File).TempFilename("xml")
    Set sc = ..ExportFrom(namespace, category, file)
    If $$$ISERR(sc) Do ##class(%File).Delete(file) Quit sc
    If (as = "") || (as = category) {
        Set sc = ##class(EnsLib.HL7.SchemaXML).Import(file, .got)
    } Else {
        Set sc = ##class(EnsLib.HL7.SchemaXML).Import(file, .got, as)
        If $$$ISOK(sc) Set ^Shutter.Config("schemaAlias", namespace, category) = as
    }
    Do ##class(%File).Delete(file)
    If $$$ISERR(sc) Quit sc
    Kill ^Shutter.Config("schemaNamed", category)
    Do ..Changed()
    Try { Do ##class(Ens.Util.Log).LogInfo($CLASSNAME(), "ImportFrom", "HL7 schema category " _ category _ " imported from " _ namespace _ " as " _ $SELECT(as = "": category, 1: as)) } Catch {}
    Quit $$$OK
}

/// Whether a category is loaded in another namespace (a watched production's, for a message held there): read there each
/// time, not cached. An empty namespace, or this one, reads here.
ClassMethod KnownIn(namespace As %String, category As %String) As %Boolean
{
    Set category = $ZSTRIP(category, "<>W")
    If category = "" Quit 0
    If (namespace = "") || (namespace = $NAMESPACE) Quit ..Known(category)
    Set known = 0
    Try {
        New $NAMESPACE
        Set $NAMESPACE = namespace
        Set rs = ##class(%ResultSet).%New("EnsLib.HL7.Schema:TypeCategories")
        If rs.Execute() { While rs.Next() { If rs.Get("Category") = category Set known = 1 Quit } }
    } Catch ex {
        Set known = 0
    }
    Quit known
}

/// The key in a stored message's UserValues for the category its forward named and this namespace lacked (v1.42); the
/// message goes when it is purged, and so does this.
Parameter NAMEDKEY = "ShutterNamedCategory";

Parameter NAMEDFROM = "ShutterNamedFrom";

/// Notes on a forwarded message's stored copy the category its forward named when this namespace lacks it (under the name
/// it has here); answers whether it did. The copy itself stays typed as the intake's fallback typed it.
ClassMethod NamedUnloaded(message As EnsLib.HL7.Message, category As %String, namespace As %String = "") As %Boolean
{
    Set category = $ZSTRIP(category, "<>W")
    If category = "" Quit 0
    If ..Known(..LocalName(namespace, category)) Quit 0
    Do message.UserValues.SetAt(category, ..#NAMEDKEY)
    Do message.UserValues.SetAt(namespace, ..#NAMEDFROM)
    Quit 1
}

/// The category a stored message's forward named and that was not loaded when it came, under the name it has here, or "".
ClassMethod NamedCategory(message As EnsLib.HL7.Message) As %String
{
    Set category = message.UserValues.GetAt(..#NAMEDKEY)
    If category = "" Quit ""
    Quit ..LocalName(message.UserValues.GetAt(..#NAMEDFROM), category)
}

/// The schema category a message is read under: its document type's category when the route set one; else the
/// MessageSchemaCategory of the item that received it (sourceItem, the header's SourceConfigName), since an item whose category
/// is not loaded leaves the message untyped; else what the message itself says in MSH-12, read by position (a message with
/// no type has no segment names to read by).
ClassMethod CategoryOf(message As EnsLib.HL7.Message, sourceItem As %String = "") As %String
{
    Set category = ""
    Try {
        Set category = message.DocTypeCategory
        If (category = "") && (sourceItem '= "") {
            Set category = ##class(Ens.Director).GetItemSettingValue(sourceItem, "Host", "MessageSchemaCategory", .sc)
            If $$$ISERR(sc) Set category = ""
        }
        If category = "" Set category = $PIECE(message.GetValueAt("1:12"), "^", 1)
    } Catch ex {
    }
    Quit $ZSTRIP(category, "<>W")
}

/// The message read as standard 2.5.1, for a held case's identity (v1.34): a copy from its text with the 2.5.1 document
/// type of its message structure, or "" when 2.5.1 has none. The standard segments read the same in a site's variant of
/// 2.5.1; the copy is never saved, and nothing is delivered from it.
ClassMethod Canonical(message As EnsLib.HL7.Message) As EnsLib.HL7.Message
{
    Set copy = ""
    Try {
        Set text = message.OutputToString(, , .sc)
        Quit:$$$ISERR(sc)
        Set copy = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
        If $$$ISERR(sc) || '$ISOBJECT($GET(copy)) Set copy = "" Quit
        Set docType = ##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType("2.5.1", copy.Name, .dsc)
        If $$$ISERR(dsc) || (docType = "") Set copy = "" Quit
        Do copy.PokeDocType(docType)
    } Catch ex {
        Set copy = ""
    }
    Quit copy
}

/// The held messages (v1.34, "prevent failures"): the open cases of kind unreadable still waiting for their schema (HeldSchema
/// set; a release clears it), by the category and the namespace it must be loaded in. {count, categories: [{category,
/// namespace, count, oldest}]}, oldest first; the Doctor (held_messages) and GET /settings (heldMessages) carry it.
ClassMethod Held() As %DynamicObject
{
    Set out = {}, cats = [], total = 0
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT %EXACT(HeldSchema) AS Category, %EXACT(SourceNamespace) AS Namespace, COUNT(*) AS N, MIN(OpenedAt) AS Oldest FROM Shutter_Store.""Case"" WHERE FailureKind = 'unreadable' AND HeldSchema <> '' AND State NOT IN ('resolved', 'failed') GROUP BY %EXACT(HeldSchema), %EXACT(SourceNamespace) ORDER BY Oldest")
        While rs.%Next() {
            Set c = {}
            Set c.category = rs.%Get("Category"), c.namespace = $SELECT(rs.%Get("Namespace") = "": $NAMESPACE, 1: rs.%Get("Namespace"))
            Set c.count = +rs.%Get("N"), c.oldest = rs.%Get("Oldest")
            Do cats.%Push(c)
            Set total = total + rs.%Get("N")
        }
    } Catch ex {
    }
    Set out.count = total, out.categories = cats
    Quit out
}

/// Release the held cases whose schema has been loaded since (v1.34): each blocked or escalated case of kind unreadable
/// whose category is now known where the message was read is reinvestigated, as a case waiting on a message is
/// (Shutter.Store.Case.ReleaseHeld), and the fresh evidence reads the message under its schema. Called by the Case
/// Releaser's sweep every few seconds (Shutter.Operation.Releaser, v1.35; the index's task before), which passes itself
/// as host so each release goes from that host to the Case Workflow; the categories are read afresh while anything is
/// held. Returns how many were released, and checked how many held cases it looked at so far. An error in the check is
/// thrown to the caller once the counts are written (v1.39; until then it was swallowed and the check answered a partial
/// count as if it were whole), so the Case Releaser's run row records it; a namespace that cannot be read is not an
/// error (KnownIn answers that it knows nothing), nor is a release the Case Workflow does not take.
ClassMethod ReleaseHeld(host As Ens.Host = "", target As %String = "Case Workflow", Output checked As %Integer) As %Integer
{
    Set n = 0, checked = 0, first = 1
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT CaseId, HeldSchema, SourceNamespace FROM Shutter_Store.""Case"" WHERE FailureKind = 'unreadable' AND HeldSchema <> '' AND State IN ('blocked', 'escalated') ORDER BY ID")
    While rs.%Next() {
        If first Kill ^||Shutter.SchemaKnown  Set first = 0
        Set checked = checked + 1
        Set category = rs.%Get("HeldSchema"), ns = rs.%Get("SourceNamespace")
        Continue:'..KnownIn(ns, category)
        // Loaded since the case was held: every job's cache of the categories is stale.
        Do ..Changed()
        Set n = n + ##class(Shutter.Store.Case).ReleaseHeld(rs.%Get("CaseId"), category, $SELECT(ns = "": $NAMESPACE, 1: ns), host, target)
    }
    Quit n
}

}
