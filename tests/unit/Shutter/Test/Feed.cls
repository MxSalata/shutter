/// Development helpers for the feed, called through SQL on a test instance (loaded by hand or by CI from tests/unit; never
/// part of the product's install or image; Drop and Mode need the %Development resource):
/// Map parses an HL7 text and returns the downstream operation Shutter builds from it, so the trigger table and the
/// key can be checked without the production; Drop writes an HL7 text into the production's inbound folder, so a
/// message can be fed by hand from a script. Segments in the text are separated by the marker <CR>.
Class Shutter.Test.Feed
{

/// The operation JSON for an HL7 text (segments separated by <CR>), or {"error": "..."} when it does not map.
/// docType names the parsed structure (default: resolved from the message type in the 2.5.1 category).
ClassMethod Map(text As %String, docType As %String = "") As %String [ SqlProc ]
{
    Set msg = ..Parse(text, docType, .sc)
    If $$$ISERR(sc) Quit {"error": ($SYSTEM.Status.GetErrorText(sc))}.%ToJSON()
    Set op = ##class(Shutter.Util.OperationKey).FromHL7(msg, .sc)
    If $$$ISERR(sc) Quit {"error": ($SYSTEM.Status.GetErrorText(sc))}.%ToJSON()
    Quit op.%ToJSON()
}

/// The parsed message's DocType, Name and segment count, to check how a text is resolved.
ClassMethod Describe(text As %String, docType As %String = "") As %String [ SqlProc ]
{
    Set msg = ..Parse(text, docType, .sc)
    If $$$ISERR(sc) Quit {"error": ($SYSTEM.Status.GetErrorText(sc))}.%ToJSON()
    Quit {"doc_type": (msg.DocType), "name": (msg.Name), "segments": (msg.SegCount)}.%ToJSON()
}

/// Writes the text as <name> into the inbound folder (^Shutter.Config("adtIn")), through a .part file that is
/// renamed, as the scenario runner does. Returns the path written, or an error text.
ClassMethod Drop(name As %String, text As %String) As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("%Development", "USE") Quit "error: a development helper; %Development is required"
    If '$MATCH(name, "^[A-Za-z0-9_.-]+\.hl7$") Quit "error: the name must be a plain .hl7 file name"
    Set dir = $GET(^Shutter.Config("adtIn"))
    If dir = "" Quit "error: the adtIn setting is not set"
    Set target = ##class(%File).NormalizeDirectory(dir) _ name, partial = target _ ".part"
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.Filename = partial
    Do f.Write(..Text(text))
    Set sc = f.%Save()
    If $$$ISERR(sc) Quit "error: " _ $SYSTEM.Status.GetErrorText(sc)
    If '##class(%File).Rename(partial, target, .code) Quit "error: rename failed with code " _ code
    Quit target
}

/// Sets the investigation mode for the cases the feed opens next (board, single, rules or policy), as a scenario run
/// does, and returns it.
ClassMethod Mode(mode As %String) As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("%Development", "USE") Quit "error: a development helper; %Development is required"
    Set mode = $ZCONVERT($ZSTRIP(mode, "<>W"), "L")
    If '$LISTFIND($LISTBUILD("board", "single", "rules", "policy"), mode) Quit "error: unknown mode " _ mode
    Set ^Shutter.Config("mode") = mode
    Quit mode
}

ClassMethod Text(text As %String) As %String [ Private ]
{
    Set text = $REPLACE(text, "<CR>", $CHAR(13))
    Set text = $REPLACE(text, $CHAR(10), $CHAR(13))
    Quit text
}

ClassMethod Parse(text As %String, docType As %String, Output sc As %Status) As EnsLib.HL7.Message [ Private ]
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(..Text(text), .sc)
    If $$$ISERR(sc) Quit ""
    If (docType = "") || (docType = $CHAR(0)) Set docType = ##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType("2.5.1", msg.Name, .sc)
    If $$$ISERR(sc) Quit ""
    If docType '= "" Do msg.PokeDocType(docType)
    Quit msg
}

}
