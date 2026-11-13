/// The proof that a receiver's FHIR server software answers as the conformance kit measured: one row per receiver,
/// written only by importing the proof document tests/conformance/fhir_conformance.py --proof wrote from a run in which
/// no exchange differed. It is install state: no case owns it and no purge removes it. The four KIT parameters are
/// written by tests/conformance/embed.py from the kit file, and embed.py --check fails when they are not the file's.
Class Shutter.Store.FHIRProof Extends (%Persistent, %JSON.Adaptor)
{

Parameter KITNAME = "fhir-facade-v1.json";

Parameter KITSHA256 = "95d86920df7365ecd5464124de743c46e4fb18467e817a13036a4fe5c74dda0c";

Parameter KITFACADE = 244;

Parameter KITIRIS = 236;

Property Receiver As %String(%JSONFIELDNAME = "receiver", MAXLEN = 128) [ Required ];

Index ReceiverIdx On Receiver [ Unique ];

Property SoftwareName As %String(%JSONFIELDNAME = "softwareName", MAXLEN = 200);

Property SoftwareVersion As %String(%JSONFIELDNAME = "softwareVersion", MAXLEN = 200);

Property FhirVersion As %String(%JSONFIELDNAME = "fhirVersion", MAXLEN = 20);

Property Kit As %String(%JSONFIELDNAME = "kit", MAXLEN = 100);

Property KitDigest As %String(%JSONFIELDNAME = "kitDigest", MAXLEN = 80);

Property Target As %String(%JSONFIELDNAME = "target", MAXLEN = 16);

Property MeasuredBase As %String(%JSONFIELDNAME = "measuredBase", MAXLEN = 500);

Property MeasuredAt As %String(%JSONFIELDNAME = "measuredAt", MAXLEN = 30);

Property Exchanges As %Integer(%JSONFIELDNAME = "exchanges");

Property Differ As %Integer(%JSONFIELDNAME = "differ");

Property IfMatchStaleRefused As %Boolean(%JSONFIELDNAME = "ifMatchStaleRefused");

Property IfMatchUnknownIdRefused As %Boolean(%JSONFIELDNAME = "ifMatchUnknownIdRefused");

Property TagsKept As %Boolean(%JSONFIELDNAME = "tagsKept");

Property MeasurementsJSON As %String(%JSONFIELDNAME = "measurements", MAXLEN = "");

Property ImportedAt As %String(%JSONFIELDNAME = "importedAt", MAXLEN = 30);

Property ImportedBy As %String(%JSONFIELDNAME = "importedBy", MAXLEN = 100);

/// Imports a proof document for a receiver, replacing the receiver's row. Refused unless the document is a whole run of
/// this release's kit in which nothing differed and each of the three measurements passed on its own exchange.
ClassMethod Import(receiver As %String, proofJSON As %String, Output p As Shutter.Store.FHIRProof) As %Status
{
    Set p = ""
    Set why = ..Problem(receiver, proofJSON, .doc)
    If why '= "" Quit $$$ERROR($$$GeneralError, "The FHIR proof is refused: " _ why)
    Set row = ..For(receiver)
    If '$ISOBJECT(row) Set row = ..%New(), row.Receiver = receiver
    Set row.SoftwareName = doc.software.name, row.SoftwareVersion = doc.software.version, row.FhirVersion = doc."fhir_version"
    Set row.Kit = doc.kit, row.KitDigest = doc."kit_sha256", row.Target = doc.target
    Set row.MeasuredBase = doc.base, row.MeasuredAt = doc."measured_at"
    Set row.Exchanges = doc.exchanges, row.Differ = doc.differ
    Set row.IfMatchStaleRefused = 1, row.IfMatchUnknownIdRefused = 1, row.TagsKept = 1
    Set row.MeasurementsJSON = doc.measurements.%ToJSON()
    Set row.ImportedAt = ##class(Shutter.Util.Time).NowUTC(), row.ImportedBy = $EXTRACT($USERNAME, 1, 100)
    Set sc = row.%Save()
    If $$$ISOK(sc) Set p = row
    Quit sc
}

/// Imports the proof document in a file (UTF-8).
ClassMethod ImportFile(receiver As %String, path As %String) As %Status
{
    If (path = "") || '##class(%File).Exists(path) Quit $$$ERROR($$$GeneralError, "The FHIR proof is refused: no file " _ path)
    Set stream = ##class(%Stream.FileCharacter).%New()
    Set stream.TranslateTable = "UTF8"
    Set sc = stream.LinkToFile(path)
    If $$$ISERR(sc) Quit sc
    Set text = ""
    Try {
        While 'stream.AtEnd { Set text = text _ stream.Read(32000) }
    } Catch ex {
        Set sc = $$$ERROR($$$GeneralError, "The FHIR proof is refused: the file is too large to be a proof document")
    }
    If $$$ISERR(sc) Quit sc
    Quit ..Import(receiver, text)
}

/// The receiver's row, or "".
ClassMethod For(receiver As %String) As Shutter.Store.FHIRProof
{
    If receiver = "" Quit ""
    Quit ..ReceiverIdxOpen(receiver)
}

/// True when the software named is the software that was measured: string equality on the name and on the version,
/// and false when either argument or either stored value is empty.
Method Matches(softwareName As %String, softwareVersion As %String) As %Boolean
{
    If (softwareName = "") || (softwareVersion = "") || (..SoftwareName = "") || (..SoftwareVersion = "") Quit 0
    Quit (softwareName = ..SoftwareName) && (softwareVersion = ..SoftwareVersion)
}

/// Why a proof document is refused, or "" with the parsed document.
ClassMethod Problem(receiver As %String, proofJSON As %String, Output doc As %DynamicObject) As %String [ Private ]
{
    Set doc = ""
    If receiver = "" Quit "no receiver is named"
    If (..#KITSHA256 = "") || (+..#KITFACADE = 0) || (+..#KITIRIS = 0) Quit "this build carries no kit digest"
    Try {
        Set doc = ##class(%DynamicAbstractObject).%FromJSON(proofJSON)
    } Catch ex {
        Set doc = ""
    }
    If '..IsObject(doc) Quit "it is not a JSON object"
    If ..Text(doc, "kit") '= ..#KITNAME Quit "kit is not " _ ..#KITNAME
    If ..Text(doc, "kit_sha256") '= ..#KITSHA256 Quit "kit_sha256 is not the digest of this release's kit"
    Set target = ..Text(doc, "target")
    If (target '= "facade") && (target '= "iris") Quit "target is neither facade nor iris"
    Set count = $SELECT(target = "facade": ..#KITFACADE, 1: ..#KITIRIS)
    If (doc.%GetTypeOf("exchanges") '= "number") || (doc.exchanges '= count) Quit "exchanges is not the " _ count _ " of target " _ target
    If (doc.%GetTypeOf("differ") '= "number") || (doc.differ '= 0) Quit "differ is not 0"
    For key = "base", "measured_at", "fhir_version" {
        If ..Text(doc, key) = "" Return key _ " is missing"
    }
    Set software = doc.%Get("software")
    If '..IsObject(software) Quit "software is missing"
    For key = "name", "version" {
        If ..Text(software, key) = "" Return "software." _ key _ " is missing"
    }
    Set measurements = doc.%Get("measurements")
    If '..IsObject(measurements) Quit "measurements is missing"
    Set expected = {"if_match_stale_refused": "m3-update-stale", "if_match_unknown_id_refused": "m5-if-match-unknown-id", "tags_kept": "m8-history-tags"}
    Set iter = measurements.%GetIterator()
    While iter.%GetNext(.key, .m, .type) {
        If 'expected.%IsDefined(key) Return "measurements." _ key _ " is not a measurement of this kit"
    }
    Set iter = expected.%GetIterator()
    While iter.%GetNext(.key, .exchange) {
        Set m = measurements.%Get(key)
        If '..IsObject(m) Return "measurements." _ key _ " is missing"
        If ..Text(m, "exchange") '= exchange Return "measurements." _ key _ " does not name the exchange " _ exchange
        If (m.%GetTypeOf("passed") '= "boolean") || 'm.passed Return "measurements." _ key _ " did not pass"
        Set it2 = m.%GetIterator()
        While it2.%GetNext(.k2, .v2, .t2) {
            If (k2 '= "exchange") && (k2 '= "passed") Return "measurements." _ key _ "." _ k2 _ " is not part of a measurement"
        }
    }
    Quit ""
}

ClassMethod IsObject(value) As %Boolean [ Private ]
{
    Quit $ISOBJECT(value) && value.%IsA("%DynamicObject")
}

/// A member that is a string, or "".
ClassMethod Text(obj As %DynamicObject, key As %String) As %String [ Private ]
{
    If obj.%GetTypeOf(key) '= "string" Quit ""
    Quit obj.%Get(key)
}

Storage Default
{
<Data name="FHIRProofDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Receiver</Value>
</Value>
<Value name="3">
<Value>SoftwareName</Value>
</Value>
<Value name="4">
<Value>SoftwareVersion</Value>
</Value>
<Value name="5">
<Value>FhirVersion</Value>
</Value>
<Value name="6">
<Value>Kit</Value>
</Value>
<Value name="7">
<Value>KitDigest</Value>
</Value>
<Value name="8">
<Value>Target</Value>
</Value>
<Value name="9">
<Value>MeasuredBase</Value>
</Value>
<Value name="10">
<Value>MeasuredAt</Value>
</Value>
<Value name="11">
<Value>Exchanges</Value>
</Value>
<Value name="12">
<Value>Differ</Value>
</Value>
<Value name="13">
<Value>IfMatchStaleRefused</Value>
</Value>
<Value name="14">
<Value>IfMatchUnknownIdRefused</Value>
</Value>
<Value name="15">
<Value>TagsKept</Value>
</Value>
<Value name="16">
<Value>MeasurementsJSON</Value>
</Value>
<Value name="17">
<Value>ImportedAt</Value>
</Value>
<Value name="18">
<Value>ImportedBy</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.FHIRProofD</DataLocation>
<DefaultData>FHIRProofDefaultData</DefaultData>
<IdLocation>^Shutter.Store.FHIRProofD</IdLocation>
<IndexLocation>^Shutter.Store.FHIRProofI</IndexLocation>
<StreamLocation>^Shutter.Store.FHIRProofS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
