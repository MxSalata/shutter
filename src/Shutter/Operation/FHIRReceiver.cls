/// The reader of a FHIR R4 receiver. It only reads: every request is a GET with Accept: application/fhir+json that
/// follows no redirect, and what came back is carried as parts, each with the status that can be trusted
/// (<class>Shutter.FHIR.Trust</class>).
/// A request names no receiver: the case is opened by its id and the address comes from the fhir block of the case's
/// own receiver in the site profile, so a request can borrow no other entry's settings. The server, port, TLS and
/// credential are this item's adapter settings.
Class Shutter.Operation.FHIRReceiver Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// A body of more characters than this is not trusted, and is not carried.
Property MaxBody As %Integer [ InitialExpression = 1000000 ];

/// When the parts together pass this many characters the answer is one error and no parts, so no string that is too
/// long can reach the event log.
Property MaxTotal As %Integer [ InitialExpression = 1500000 ];

/// One request gives up reading after this many seconds: the parts not yet read say so.
Property Budget As %Numeric [ InitialExpression = 45 ];

/// When this request's reads began ($ZHOROLOG), and the characters of the bodies carried so far.
Property Started As %Numeric [ Internal ];

Property Carried As %Integer [ InitialExpression = 0, Internal ];

Property TooLarge As %Boolean [ InitialExpression = 0, Internal ];

Parameter TOOLARGE = "the receiver's answers are together too large to carry";

Parameter OUTOFTIME = "the request ran out of time";

Parameter IDCHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-";

Method OnRead(request As Shutter.Msg.FHIRRead, Output response As Shutter.Msg.FHIRReadResult) As %Status
{
    Set response = ##class(Shutter.Msg.FHIRReadResult).%New()
    Try {
        Set parts = ..ReadParts(request, .error)
        If error = "" {
            Set json = parts.%ToJSON()
            If $LENGTH(json) > ..MaxTotal { Set error = ..#TOOLARGE } Else { Set response.PartsJSON = json }
        }
        Set response.Error = error
    } Catch ex {
        // A string that is too long while the parts were put together is the same answer; anything else says what it was.
        Set response.PartsJSON = ""
        Set response.Error = $SELECT(..TooLarge || (ex.Name [ "MAXSTRING"): ..#TOOLARGE, 1: $EXTRACT("the reads failed: " _ ex.DisplayString(), 1, 2000))
    }
    Set ..Retry = 0
    $$$TRACE("FHIR reads for case " _ request.CaseId _ " (" _ request.Purpose _ "): " _ $SELECT(response.Error = "": $LENGTH(response.PartsJSON) _ " characters", 1: response.Error))
    Quit $$$OK
}

/// Every part the purpose asks for, in the order they are read; <var>error</var> is "" or why there are no parts.
Method ReadParts(request As Shutter.Msg.FHIRRead, Output error As %String) As %DynamicObject
{
    Set error = ""
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Set error = "unknown case " _ request.CaseId Quit ""
    Set purpose = request.Purpose
    If (purpose '= "evidence") && (purpose '= "dispatch") && (purpose '= "verify") Set error = "unknown purpose of a FHIR read" Quit ""
    Set block = ##class(Shutter.FHIR.Profile).Block(case.Receiver)
    If '$ISOBJECT(block) Set error = "the case's receiver has no fhir block in the site profile" Quit ""
    Set base = $SELECT(block.%GetTypeOf("base") = "string": block.%Get("base"), 1: "")
    While $EXTRACT(base, *) = "/" {
        Set base = $EXTRACT(base, 1, * - 1)
    }
    // The Location reads: the whole map for evidence, the request's own list otherwise.
    Set refs = []
    If purpose = "evidence" {
        Set map = block.%Get("location_map")
        If $ISOBJECT(map) && map.%IsA("%DynamicArray") {
            Set it = map.%GetIterator()
            While it.%GetNext(.i, .entry) {
                Do refs.%Push($SELECT($ISOBJECT(entry) && (entry.%GetTypeOf("location") = "string"): entry.%Get("location"), 1: ""))
            }
        }
    } ElseIf request.LocationRefsJSON '= "" {
        Set refs = ##class(Shutter.FHIR.Trust).Parsed("{""refs"":" _ request.LocationRefsJSON _ "}")
        Set refs = $SELECT($ISOBJECT(refs): refs.%Get("refs"), 1: "")
        If '$ISOBJECT(refs) || 'refs.%IsA("%DynamicArray") || (refs.%Size() > 25) Set error = "the Location references of the request are not a list of at most 25" Quit ""
    }
    Set ..Started = $ZHOROLOG, ..Carried = 0, ..TooLarge = 0
    Set parts = {}
    Do parts.%Set("observed_at", ##class(Shutter.Util.Time).NowUTC(), "string")
    Do parts.%Set("base", base, "string")

    If purpose '= "verify" {
        Set part = ..Get(base _ "/metadata", "metadata")
        If part."http_status" = 200 Do part.%Set("statement", ..Statement(part.body))
        Set ..Carried = ..Carried - $LENGTH(part.body)
        Do part.%Remove("body")
        Do parts.%Set("metadata", part)
    }

    // The Encounter's logical id: the search's single match for evidence, the request's own otherwise.
    Set id = request.EncounterId, why = ""
    If purpose = "evidence" {
        Set id = ""
        Set visit = case.EncounterId
        Set system = $SELECT($ISOBJECT(block.%Get("encounter_identifier")) && (block.%Get("encounter_identifier").%GetTypeOf("system") = "string"): block.%Get("encounter_identifier").%Get("system"), 1: "")
        If (visit = "") || (visit = "-") || (system = "") {
            Set part = ..Unread("the case has no visit number to search by, or the profile no identifier system")
        } Else {
            Set part = ..Get(base _ "/Encounter?identifier=" _ ..Escape(system) _ "%7C" _ ..Escape(visit), "search")
        }
        Do parts.%Set("search", part)
        If part."http_status" '= 200 {
            Set why = "the search was not read"
        } Else {
            Set matches = ##class(Shutter.FHIR.Trust).Matches(##class(Shutter.FHIR.Trust).Parsed(part.body))
            If matches.%Size() '= 1 {
                Set why = "the search gave " _ matches.%Size() _ " matches"
            } Else {
                Set match = matches.%Get(0)
                If $ISOBJECT(match) && (match.%GetTypeOf("resourceType") = "string") && (match.resourceType = "Encounter") && (match.%GetTypeOf("id") = "string") Set id = match.id
                If id = "" Set why = "the search's match is not an Encounter with an id"
            }
        }
    }
    If (why = "") && '..IsId(id) Set why = "no Encounter id that can be asked for", id = ""
    If why '= "" Set id = ""
    $$$ThrowOnError(..Bound())

    Set encounter = $SELECT(id = "": ..Unread(why), 1: ..Get(base _ "/Encounter/" _ id, "encounter", "Encounter", id))
    Do parts.%Set("encounter", encounter)
    $$$ThrowOnError(..Bound())

    // The Patient: the request's reference when it gives one, else the Encounter's literal subject.
    Set subject = request.PatientRef
    If (subject = "") && (encounter."http_status" = 200) {
        Set body = ##class(Shutter.FHIR.Trust).Parsed(encounter.body)
        Set s = $SELECT($ISOBJECT(body): body.%Get("subject"), 1: "")
        If $ISOBJECT(s) && s.%IsA("%DynamicObject") && (s.%GetTypeOf("reference") = "string") Set subject = s.reference
    }
    If ..IsReference(subject, "Patient") {
        Set part = ..Get(base _ "/" _ subject, "patient", "Patient", $PIECE(subject, "/", 2))
    } Else {
        Set part = ..Unread($SELECT(subject = "": "no Patient reference to ask for", 1: "the Patient reference is not a literal Patient/{id}"))
    }
    Do parts.%Set("patient", part)
    $$$ThrowOnError(..Bound())

    Set locations = []
    Set it = refs.%GetIterator()
    While it.%GetNext(.i, .ref) {
        If (refs.%GetTypeOf(i) = "string") && ..IsReference(ref, "Location") {
            Set part = ..Get(base _ "/" _ ref, "location", "Location", $PIECE(ref, "/", 2))
        } Else {
            Set part = ..Unread("the Location reference is not a literal Location/{id}")
            If refs.%GetTypeOf(i) '= "string" Set ref = ""
        }
        Do part.%Set("reference", ref, "string")
        Do locations.%Push(part)
        $$$ThrowOnError(..Bound())
    }
    Do parts.%Set("locations", locations)

    Do parts.%Set("history", $SELECT(id = "": ..Unread(why), 1: ..Get(base _ "/Encounter/" _ id _ "/_history", "history")))
    $$$ThrowOnError(..Bound())

    If (purpose = "verify") && (request.Vid '= "") {
        If id = "" {
            Set part = ..Unread(why)
        } ElseIf '..IsId(request.Vid) {
            Set part = ..Unread("the version id cannot be asked for")
        } Else {
            Set part = ..Get(base _ "/Encounter/" _ id _ "/_history/" _ request.Vid, "vread", "Encounter", id)
        }
        Do parts.%Set("vread", part)
        $$$ThrowOnError(..Bound())
    }
    Quit parts
}

/// One GET, as a part: the status as it came and as it can be trusted, the ETag and Location verbatim, the content
/// type, and the body as characters. The body is read as bytes and decoded here: UTF-8 when the content type names it
/// or names no charset; any other charset, bytes that are not UTF-8 and a body over the limit are not trusted.
Method Get(path As %String, kind As %String, type As %String = "", id As %String = "") As %DynamicObject
{
    Set left = ..Budget - ($ZHOROLOG - ..Started)
    If left <= 0 Quit ..Unread(..#OUTOFTIME)
    Set part = ..Blank()
    Set http = ##class(%Net.HttpRequest).%New()
    Set http.ReadRawMode = 1
    // A redirect is never followed: the credential would go with it to another host, whose answer would be read as
    // the receiver's. A 3xx is carried as it came.
    Set http.FollowRedirect = 0
    Do http.SetHeader("Accept", "application/fhir+json")
    // The adapter waits no longer for this answer than the request has left.
    Set wait = ..Adapter.ResponseTimeout
    If (wait < 0) || (wait > left) Set ..Adapter.ResponseTimeout = $SELECT(left < 1: 1, 1: left \ 1)
    Set sc = $$$OK
    Try {
        Set sc = ..Adapter.SendFormDataArray(.answer, "GET", http, "", "", path)
    } Catch ex {
        Set sc = ex.AsStatus(), answer = ""
    }
    Set ..Adapter.ResponseTimeout = wait
    Set ..Retry = 0
    If '$ISOBJECT($GET(answer)) {
        Do part.%Set("error", $EXTRACT("no answer" _ $SELECT($$$ISERR(sc): ": " _ $SYSTEM.Status.GetErrorText(sc), 1: ""), 1, 400), "string")
        Quit part
    }
    Set raw = +answer.StatusCode
    Do part.%Set("raw_status", raw, "number")
    Do part.%Set("http_status", raw, "number")
    Do part.%Set("etag", answer.GetHeader("ETag"), "string")
    Do part.%Set("location", answer.GetHeader("Location"), "string")
    Set contentType = answer.GetHeader("Content-Type")
    If contentType = "" Set contentType = answer.ContentType
    Do part.%Set("content_type", contentType, "string")
    // Three bytes are the most one character takes, so more bytes than that are more characters than the limit.
    Set limit = 3 * ..MaxBody
    If limit > 3600000 Set limit = 3600000
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
    Set charset = ..Charset(contentType)
    If over {
        Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's body is over " _ ..MaxBody _ " characters")
    } ElseIf (charset '= "") && (charset '= "utf-8") && (charset '= "utf8") {
        Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's charset is not UTF-8")
    } Else {
        Set text = $ZCONVERT(bytes, "I", "UTF8")
        If $ZCONVERT(text, "O", "UTF8") '= bytes {
            Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's body is not UTF-8")
        } ElseIf $LENGTH(text) > ..MaxBody {
            Do ##class(Shutter.FHIR.Trust).Fail(part, "the answer's body is over " _ ..MaxBody _ " characters")
        } Else {
            Do part.%Set("body", text, "string")
        }
    }
    Do ##class(Shutter.FHIR.Trust).Part(kind, part, type, id)
    Set ..Carried = ..Carried + $LENGTH(part.body)
    Quit part
}

/// Stops the reads when the bodies carried so far are together too large.
Method Bound() As %Status
{
    If ..Carried <= ..MaxTotal Quit $$$OK
    Set ..TooLarge = 1
    Quit $$$ERROR($$$GeneralError, ..#TOOLARGE)
}

/// What the page and the gate need of a CapabilityStatement, and nothing else of it: the software, the FHIR version
/// and, from the rest entry of mode server, what it says of the Encounter type.
ClassMethod Statement(body As %String) As %DynamicObject
{
    Set out = {"software": {"name": "", "version": ""}, "fhir_version": "", "versioning": "", "interactions": [], "read_history": false, "update_create": false}
    Set cs = ##class(Shutter.FHIR.Trust).Parsed(body)
    If '$ISOBJECT(cs) Quit out
    Set software = cs.%Get("software")
    If ..IsObject(software) {
        Do out.software.%Set("name", ..Str(software, "name"), "string")
        Do out.software.%Set("version", ..Str(software, "version"), "string")
    }
    Do out.%Set("fhir_version", ..Str(cs, "fhirVersion"), "string")
    Set rest = cs.%Get("rest"), encounter = ""
    If $ISOBJECT(rest) && rest.%IsA("%DynamicArray") {
        Set it = rest.%GetIterator()
        While it.%GetNext(.i, .r) {
            Continue:'..IsObject(r)||(..Str(r, "mode")'="server")
            Set resources = r.%Get("resource")
            If $ISOBJECT(resources) && resources.%IsA("%DynamicArray") {
                Set rit = resources.%GetIterator()
                While rit.%GetNext(.j, .res) {
                    If ..IsObject(res) && (..Str(res, "type") = "Encounter") Set encounter = res Quit
                }
            }
            Quit
        }
    }
    If '$ISOBJECT(encounter) Quit out
    Do out.%Set("versioning", ..Str(encounter, "versioning"), "string")
    Set list = encounter.%Get("interaction")
    If $ISOBJECT(list) && list.%IsA("%DynamicArray") {
        Set it = list.%GetIterator()
        While it.%GetNext(.i, .entry) {
            If ..IsObject(entry) && (..Str(entry, "code") '= "") Do out.interactions.%Push(entry.code, "string")
        }
    }
    If encounter.%GetTypeOf("readHistory") = "boolean" Do out.%Set("read_history", ''encounter.%Get("readHistory"), "boolean")
    If encounter.%GetTypeOf("updateCreate") = "boolean" Do out.%Set("update_create", ''encounter.%Get("updateCreate"), "boolean")
    Quit out
}

/// A part with nothing read.
ClassMethod Blank() As %DynamicObject [ Private ]
{
    Quit {"http_status": 0, "raw_status": 0, "etag": "", "location": "", "content_type": "", "body": "", "error": ""}
}

/// A part that was asked for and not read, with the reason.
ClassMethod Unread(why As %String) As %DynamicObject [ Private ]
{
    Set part = ..Blank()
    Do part.%Set("error", "not read: " _ why, "string")
    Quit part
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

/// Whether a text is a FHIR id: 1 to 64 of A-Z, a-z, 0-9, "." and "-".
ClassMethod IsId(id As %String) As %Boolean
{
    Quit (id '= "") && ($LENGTH(id) <= 64) && ($TRANSLATE(id, ..#IDCHARS) = "")
}

/// Whether a reference is literal: {type}/{id} and nothing else.
ClassMethod IsReference(reference As %String, type As %String) As %Boolean
{
    Quit ($LENGTH(reference, "/") = 2) && ($PIECE(reference, "/", 1) = type) && ..IsId($PIECE(reference, "/", 2))
}

/// A value of a query, URL-encoded from its UTF-8 bytes.
ClassMethod Escape(value As %String) As %String
{
    Quit $ZCONVERT($ZCONVERT(value, "O", "UTF8"), "O", "URL")
}

ClassMethod Str(obj As %DynamicObject, key As %String) As %String [ Private ]
{
    If '..IsObject(obj) || (obj.%GetTypeOf(key) '= "string") Quit ""
    Quit obj.%Get(key)
}

ClassMethod IsObject(x) As %Boolean [ Private ]
{
    Quit $ISOBJECT(x) && x.%IsA("%DynamicObject")
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.FHIRRead">
    <Method>OnRead</Method>
  </MapItem>
</MapItems>
}

}
