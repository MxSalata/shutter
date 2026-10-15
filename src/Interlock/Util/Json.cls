/// Small helpers over %DynamicObject.
Class Interlock.Util.Json Extends %RegisteredObject
{

/// Parse JSON text; an empty string gives an empty object; invalid text gives "" and an error status.
ClassMethod Parse(text As %String, Output sc As %Status) As %DynamicAbstractObject
{
    Set sc = $$$OK
    If $ZSTRIP(text, "<>W") = "" Quit {}
    Try {
        Set obj = ##class(%DynamicAbstractObject).%FromJSON(text)
    } Catch ex {
        Set sc = ex.AsStatus(), obj = ""
    }
    Quit obj
}

/// A string value, or the default when the key is absent or null.
ClassMethod Str(obj As %DynamicObject, key As %String, default As %String = "") As %String
{
    If '$ISOBJECT(obj) Quit default
    Set type = obj.%GetTypeOf(key)
    If (type = "unassigned") || (type = "null") Quit default
    Quit obj.%Get(key)
}

/// A boolean value as 1 or 0, or the default when absent.
ClassMethod Bool(obj As %DynamicObject, key As %String, default As %Boolean = 0) As %Boolean
{
    If '$ISOBJECT(obj) Quit default
    Set type = obj.%GetTypeOf(key)
    If (type = "unassigned") || (type = "null") Quit default
    Set v = obj.%Get(key)
    If type = "string" Quit $CASE($ZCONVERT(v, "L"), "true": 1, "1": 1, "yes": 1, : 0)
    Quit ''v
}

/// The JSON text of a dynamic object, or "" for a non-object.
ClassMethod Text(obj As %DynamicAbstractObject) As %String
{
    If '$ISOBJECT(obj) Quit ""
    Quit obj.%ToJSON()
}

/// A short, single-line preview of JSON text for logs and traces.
ClassMethod Preview(text As %String, max As %Integer = 200) As %String
{
    Set t = $TRANSLATE(text, $CHAR(13, 10, 9), "   ")
    If $LENGTH(t) <= max Quit t
    Quit $EXTRACT(t, 1, max - 1) _ "…"
}

}
