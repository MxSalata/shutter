/// How both FHIR items read from a FHIR R4 receiver: the base in front of every path, one GET that follows no redirect
/// into a bounded stream, and what its answer gives a part (the status as it came, the ETag, the Location, the content
/// type and the body as characters). FHIR Receiver reads every part this way and FHIR Execute its own read of the
/// Encounter, so one version read through either item gives the same characters: FHIR Execute compares the digest of
/// what it read with the digest of the body the approval rests on.
Class Shutter.FHIR.Wire [ Abstract ]
{

/// The base of a receiver's fhir block, with no slash at its end; "" when the block gives none.
ClassMethod Base(block As %DynamicObject) As %String
{
    Set base = $SELECT($ISOBJECT(block) && (block.%GetTypeOf("base") = "string"): block.%Get("base"), 1: "")
    While $EXTRACT(base, *) = "/" {
        Set base = $EXTRACT(base, 1, * - 1)
    }
    Quit base
}

/// A part with nothing read.
ClassMethod Blank() As %DynamicObject
{
    Quit {"http_status": 0, "raw_status": 0, "etag": "", "location": "", "content_type": "", "body": "", "error": ""}
}

/// The most bytes of a body read for a limit of <var>maxBody</var> characters: three are the most one character takes,
/// so more bytes than that are more characters than the limit. Never more than 3,600,000.
ClassMethod ByteLimit(maxBody As %Integer) As %Integer
{
    Set limit = 3 * maxBody
    Quit $SELECT(limit > 3600000: 3600000, 1: limit)
}

/// A GET that asks for FHIR JSON and reads its body as bytes into <var>bounded</var>, a stream that stops taking
/// them past <var>limit</var> bytes or <var>seconds</var> seconds (<class>Shutter.FHIR.BoundedStream</class>).
ClassMethod Request(limit As %Integer, seconds As %Numeric, Output bounded As Shutter.FHIR.BoundedStream) As %Net.HttpRequest
{
    Set http = ##class(%Net.HttpRequest).%New()
    Set http.ReadRawMode = 1
    // A redirect is never followed: the credential would go with it to another host, whose answer would be read as
    // the receiver's. A 3xx is carried as it came.
    Set http.FollowRedirect = 0
    Do http.SetHeader("Accept", "application/fhir+json")
    Set bounded = ##class(Shutter.FHIR.BoundedStream).Within(limit, seconds)
    Set http.ResponseStream = bounded
    Quit http
}

/// What an answer gives <var>part</var>: the status as it came (raw_status and http_status), the ETag and Location
/// verbatim, the content type, and the body (<method>Decode</method>). The part is judged afterwards, by
/// <class>Shutter.FHIR.Trust</class>.
ClassMethod Take(part As %DynamicObject, answer As %Net.HttpResponse, maxBody As %Integer)
{
    Set raw = +answer.StatusCode
    Do part.%Set("raw_status", raw, "number")
    Do part.%Set("http_status", raw, "number")
    Do part.%Set("etag", answer.GetHeader("ETag"), "string")
    Do part.%Set("location", answer.GetHeader("Location"), "string")
    Set contentType = answer.GetHeader("Content-Type")
    If contentType = "" Set contentType = answer.ContentType
    Do part.%Set("content_type", contentType, "string")
    Set bytes = ..Bytes(answer, ..ByteLimit(maxBody), .over)
    Do ..Decode(part, bytes, over, contentType, maxBody)
}

/// An answer's body as the bytes that came, up to <var>limit</var>; <var>over</var> says there were more, and then
/// what is returned is only the start.
ClassMethod Bytes(answer As %Net.HttpResponse, limit As %Integer, Output over As %Boolean) As %String
{
    Set bytes = "", over = 0
    If $ISOBJECT(answer.Data) {
        Do answer.Data.Rewind()
        While 'answer.Data.AtEnd {
            Set chunk = answer.Data.Read(32000)
            If ($LENGTH(bytes) + $LENGTH(chunk)) > limit Set over = 1 Quit
            Set bytes = bytes _ chunk
        }
    } ElseIf $LENGTH(answer.Data) > limit {
        Set over = 1
    } Else {
        Set bytes = answer.Data
    }
    Quit bytes
}

/// The body as characters into <var>part</var>: UTF-8 when the content type names it or names no charset. Any other
/// charset, bytes that are not UTF-8 and a body over <var>maxBody</var> characters (or over the bytes read,
/// <var>over</var>) are not trusted, and no body is carried.
ClassMethod Decode(part As %DynamicObject, bytes As %String, over As %Boolean, contentType As %String, maxBody As %Integer)
{
    Set charset = ..Charset(contentType)
    If over {
        Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's body is over " _ maxBody _ " characters")
    } ElseIf (charset '= "") && (charset '= "utf-8") && (charset '= "utf8") {
        Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's charset is not UTF-8")
    } Else {
        Set text = $ZCONVERT(bytes, "I", "UTF8")
        If $ZCONVERT(text, "O", "UTF8") '= bytes {
            Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's body is not UTF-8")
        } ElseIf $LENGTH(text) > maxBody {
            Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's body is over " _ maxBody _ " characters")
        } Else {
            Do part.%Set("body", text, "string")
        }
    }
}

/// The charset a content type names, in lower case without quotes; "" when it names none.
ClassMethod Charset(contentType As %String) As %String
{
    Set charset = ""
    For i = 2:1:$LENGTH(contentType, ";") {
        Set parameter = $ZSTRIP($PIECE(contentType, ";", i), "<>W")
        If $ZCONVERT($PIECE(parameter, "=", 1), "L") = "charset" Set charset = $ZCONVERT($TRANSLATE($ZSTRIP($PIECE(parameter, "=", 2, *), "<>W"), """'"), "L")
    }
    Quit charset
}

}
