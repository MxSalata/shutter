/// Digests over canonical JSON. A digest proves that two parties looked at the same artefact; it
/// says nothing about the artefact being true or complete.
Class Shutter.Util.Digest Extends %RegisteredObject
{

/// "sha256:" followed by the lower-case hex SHA-256 of the UTF-8 encoding of a string.
ClassMethod SHA256Hex(text As %String) As %String
{
    Set bytes = $ZCONVERT(text, "O", "UTF8")
    Set hash = $SYSTEM.Encryption.SHAHash(256, bytes)
    Quit "sha256:" _ $ZCONVERT(##class(%xsd.hexBinary).LogicalToXSD(hash), "L")
}

/// The digest of a dynamic object or array, serialised canonically (section Canonical below).
ClassMethod OfObject(obj As %DynamicAbstractObject) As %String
{
    Quit ..SHA256Hex(..Canonical(obj))
}

/// Canonical JSON: object keys sorted, no whitespace, numbers as JSON numbers, strings escaped as
/// JSON does, booleans and nulls literal. Arrays keep their order.
ClassMethod Canonical(obj As %DynamicAbstractObject) As %String
{
    If obj.%IsA("%Library.DynamicArray") {
        Set out = "", iter = obj.%GetIterator()
        While iter.%GetNext(.i, .value) {
            Set out = out _ $SELECT(out = "": "", 1: ",") _ ..CanonicalValue(obj, i)
        }
        Quit "[" _ out _ "]"
    }
    Kill keys
    Set iter = obj.%GetIterator()
    While iter.%GetNext(.key) { Set keys(key) = "" }
    Set out = "", key = ""
    For {
        Set key = $ORDER(keys(key))
        Quit:(key="")
        Set out = out _ $SELECT(out = "": "", 1: ",") _ ..JSONString(key) _ ":" _ ..CanonicalValue(obj, key)
    }
    Quit "{" _ out _ "}"
}

/// One member of a dynamic object or array, canonically.
ClassMethod CanonicalValue(container As %DynamicAbstractObject, key) As %String [ Private ]
{
    Set type = container.%GetTypeOf(key)
    If type = "object" Quit ..Canonical(container.%Get(key))
    If type = "array" Quit ..Canonical(container.%Get(key))
    If type = "null" Quit "null"
    If type = "unassigned" Quit "null"
    If type = "boolean" Quit $SELECT(container.%Get(key): "true", 1: "false")
    If type = "number" { Set a = [] Do a.%Push(container.%Get(key)) Quit $EXTRACT(a.%ToJSON(), 2, * - 1) }
    Quit ..JSONString(container.%Get(key))
}

/// A string as a JSON literal, with the escaping JSON requires.
ClassMethod JSONString(s As %String) As %String
{
    Set a = []
    Do a.%Push(s)
    Set j = a.%ToJSON()
    Quit $EXTRACT(j, 2, * - 1)
}

/// The canonical payload of a ward operation (docs/CONTRACTS.md, 1.6): exactly these keys, in this
/// order, null for an absent ward. The ward computes the same string on its side.
ClassMethod WardPayloadCanonical(op As %DynamicObject) As %String
{
    Set out = ""
    For key = "operation_key", "encounter_id", "patient_id", "patient_id_authority", "event", "ward", "event_time", "source_system" {
        Set type = op.%GetTypeOf(key)
        Set value = $SELECT((type = "null") || (type = "unassigned") || (op.%Get(key) = ""): "null", 1: ..JSONString(op.%Get(key)))
        Set out = out _ $SELECT(out = "": "", 1: ",") _ ..JSONString(key) _ ":" _ value
    }
    Quit "{" _ out _ "}"
}

/// The digest of a ward operation's canonical payload.
ClassMethod WardPayloadDigest(op As %DynamicObject) As %String
{
    Quit ..SHA256Hex(..WardPayloadCanonical(op))
}

}
