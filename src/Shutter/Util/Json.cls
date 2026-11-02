/// Small helpers over %DynamicObject.
Class Shutter.Util.Json Extends %RegisteredObject
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

/// The raw JSON projection of a persistent object, for diagnosis through SQL: the text, or the
/// export's error.
ClassMethod Export(class As %String, id As %String) As %String [ SqlProc ]
{
    Set obj = $CLASSMETHOD(class, "%OpenId", id)
    If '$ISOBJECT(obj) Quit "no object " _ class _ " " _ id
    Set sc = obj.%JSONExportToString(.json)
    If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
    Quit json
}

/// A short, single-line preview of JSON text for logs and traces.
ClassMethod Preview(text As %String, max As %Integer = 200) As %String
{
    Set t = $TRANSLATE(text, $CHAR(13, 10, 9), "   ")
    If $LENGTH(t) <= max Quit t
    Quit $EXTRACT(t, 1, max - 1) _ "…"
}

/// <var>text</var> cut to at most <var>max</var> characters at a word boundary, with an ellipsis when it was cut, and no
/// punctuation left hanging before it (a full stop included, so the ellipsis never follows one). A single word longer
/// than half the room is cut where it falls.
ClassMethod Clip(text As %String, max As %Integer = 200) As %String
{
    If $LENGTH(text) <= max Quit text
    Set t = $EXTRACT(text, 1, max - 1)
    // The last space within the room, if the words before it fill at least half of it.
    For i = max:-1:max \ 2 { If $EXTRACT(text, i) = " " Set t = $EXTRACT(text, 1, i - 1) Quit }
    Quit $ZSTRIP(t, ">", " .,;:(-") _ "…"
}

/// <var>json</var> with <code>null</code> inserted wherever a value is missing (<code>:,</code>, <code>:}</code>
/// or <code>:]</code> outside string literals), as %JSON.Adaptor writes a numeric property with no value.
/// Text inside strings is left alone.
/// A persistent object's JSON projection as a dynamic object, with its id; an export that fails is reported as
/// {id, error} rather than thrown. The one projection the API and the store classes share (v1.35).
ClassMethod Project(obj As %JSON.Adaptor) As %DynamicObject
{
    If '$ISOBJECT(obj) Quit ""
    Set sc = obj.%JSONExportToString(.json)
    If $$$ISERR(sc) || ($GET(json) = "") {
        Set o = {}
        Set o.id = obj.%Id()
        Set o.error = "projection failed: " _ $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "empty")
        Quit o
    }
    Set o = ""
    Try {
        Set o = ##class(%DynamicObject).%FromJSON(json)
    } Catch {
        // A numeric property with no value (added after the row was saved) exports as an empty value,
        // which is not JSON: null takes its place, outside string literals only.
        Try {
            Set o = ##class(%DynamicObject).%FromJSON(..NullEmptyValues(json))
        } Catch ex {
            Set o = {}
            Set o.error = "projection failed: " _ ex.DisplayString()
        }
    }
    Set o.id = obj.%Id()
    Quit o
}

/// Rows of an SQL query (its first column the ID) as projected objects of a class.
ClassMethod Rows(class As %String, sql As %String, args...) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, args...)
    While rs.%Next() {
        Set obj = $CLASSMETHOD(class, "%OpenId", rs.%Get("ID"))
        Continue:'$ISOBJECT(obj)
        Do out.%Push(..Project(obj))
    }
    Quit out
}

ClassMethod NullEmptyValues(json As %String) As %String [ SqlProc ]
{
    Set out = "", start = 1, inString = 0, escaped = 0
    For i = 1:1:$LENGTH(json) {
        Set c = $EXTRACT(json, i)
        If inString {
            If escaped { Set escaped = 0 } ElseIf c = "\" { Set escaped = 1 } ElseIf c = """" { Set inString = 0 }
            Continue
        }
        If c = """" { Set inString = 1 Continue }
        If c = ":" {
            Set next = $EXTRACT(json, i + 1)
            If (next = ",") || (next = "}") || (next = "]") Set out = out _ $EXTRACT(json, start, i) _ "null", start = i + 1
        }
    }
    Quit out _ $EXTRACT(json, start, *)
}

}
