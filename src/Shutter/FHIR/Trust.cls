/// Whether an HTTP answer is the FHIR receiver's own. A gateway's sign-in page behind a 200, its plain 404 and a body
/// of another kind say nothing about the receiver: the part's trusted status becomes 0, which every reader takes as
/// could not be read, and the part says why. Pure: no global, no clock, and never an error.
Class Shutter.FHIR.Trust [ Abstract ]
{

/// Judges one part as FHIR Receiver made it (http_status as it came, raw_status, etag, location, content_type, body)
/// and sets <code>part.http_status</code> to 0 and <code>part.error</code> when the answer is not the receiver's own.
/// <ul>
/// <li>No answer (status 0): 0.</li>
/// <li>A resource (<var>kind</var> encounter, patient, location, vread): a 200 counts only with the media type
/// application/fhir+json or application/json (without case, parameters ignored) and a JSON object whose resourceType
/// is <var>type</var> and whose id is <var>id</var>. A Location header, when present, must end
/// <code>_history/{vid}</code> with the ETag's version id.</li>
/// <li>search: a 200 Bundle of type searchset. history: a 200 Bundle of type history. metadata: a 200
/// CapabilityStatement.</li>
/// <li>A 404 or 410 of any kind counts only with a FHIR JSON OperationOutcome body.</li>
/// <li>Any other status passes through as it came.</li>
/// </ul>
/// With no <var>type</var> a resource kind takes its own (Encounter, Patient, Location).
ClassMethod Part(kind As %String, part As %DynamicObject, type As %String = "", id As %String = "")
{
    If '..IsObject(part) Quit
    Set status = ..Status(part)
    If status = 0 {
        Do ..Fail(part, $SELECT(..Str(part, "error") '= "": part.error, 1: "no answer"))
        Quit
    }
    If (status '= 200) && (status '= 404) && (status '= 410) Quit
    Set media = ..MediaOK(..Str(part, "content_type"))
    Set body = ..Parsed(..Str(part, "body"))
    If status '= 200 {
        If media && ..IsObject(body) && (..Str(body, "resourceType") = "OperationOutcome") Quit
        Do ..Fail(part, "HTTP " _ status _ " that is not the receiver's answer (as the endpoint answers a missing or refused login)")
        Quit
    }
    If 'media {
        Do ..Fail(part, "HTTP 200 that is not the receiver's answer: the media type is not FHIR JSON")
        Quit
    }
    If '..IsObject(body) {
        Do ..Fail(part, "HTTP 200 that is not the receiver's answer: the body is not a JSON object")
        Quit
    }
    Set found = ..Str(body, "resourceType")
    If kind = "metadata" {
        If found '= "CapabilityStatement" Do ..Fail(part, "HTTP 200 that is not the receiver's answer: the body is not a CapabilityStatement")
        Quit
    }
    If (kind = "search") || (kind = "history") {
        Set want = $SELECT(kind = "search": "searchset", 1: "history")
        If (found '= "Bundle") || (..Str(body, "type") '= want) Do ..Fail(part, "HTTP 200 that is not the receiver's answer: the body is not a Bundle of type " _ want)
        Quit
    }
    If type = "" Set type = $CASE(kind, "encounter": "Encounter", "vread": "Encounter", "patient": "Patient", "location": "Location", : "")
    If type = "" {
        Do ..Fail(part, "HTTP 200 of a kind of read that is not known")
        Quit
    }
    If id = "" {
        Do ..Fail(part, "HTTP 200 for a " _ type _ " read that asked for no id")
        Quit
    }
    If (found '= type) || (..Str(body, "id") '= id) {
        Do ..Fail(part, "HTTP 200 that is not the receiver's answer: the body is not the " _ type _ " asked for")
        Quit
    }
    Set location = ..Str(part, "location")
    If location '= "" {
        Set usable = ##class(Shutter.FHIR.Judge).ETagVid(..Str(part, "etag"), .vid)
        If 'usable || '..LocationNames(location, vid) Do ..Fail(part, "HTTP 200 whose Location header names another version than its ETag")
    }
}

/// The resources of a searchset's matches, in the Bundle's order: only entries whose search.mode is match or absent
/// count, so an included resource or an OperationOutcome entry is no match. An entry with no resource counts, as "".
ClassMethod Matches(bundle As %DynamicObject) As %DynamicArray
{
    Set out = []
    If '..IsObject(bundle) || '..IsArray(bundle.%Get("entry")) Quit out
    Set it = bundle.%Get("entry").%GetIterator()
    While it.%GetNext(.i, .entry) {
        Continue:'..IsObject(entry)
        Set search = entry.%Get("search")
        If ..IsObject(search) && (search.%GetTypeOf("mode") '= "unassigned") && (..Str(search, "mode") '= "match") Continue
        Set resource = entry.%Get("resource")
        Do out.%Push($SELECT(..IsObject(resource): resource, 1: ""))
    }
    Quit out
}

/// A body as a JSON object, or "" when it is not one. Never throws.
ClassMethod Parsed(text As %String) As %DynamicObject
{
    If text = "" Quit ""
    Set obj = ""
    Try { Set obj = ##class(%DynamicAbstractObject).%FromJSON(text) } Catch { Set obj = "" }
    Quit $SELECT(..IsObject(obj): obj, 1: "")
}

/// Whether a content type is FHIR JSON (or plain JSON), compared without case and parameters.
ClassMethod MediaOK(type As %String) As %Boolean
{
    Set t = $ZCONVERT($ZSTRIP($PIECE(type, ";", 1), "<>W"), "L")
    Quit (t = "application/fhir+json") || (t = "application/json")
}

/// Marks a part as not the receiver's own answer: status 0 and the reason.
ClassMethod Fail(part As %DynamicObject, why As %String)
{
    Do part.%Set("http_status", 0, "number")
    Do part.%Set("error", why, "string")
}

/// Whether a Location header names version vid: its text after the last "_history/" is exactly vid.
ClassMethod LocationNames(location As %String, vid As %String) As %Boolean [ Private ]
{
    If (vid = "") || (location '[ "_history/") Quit 0
    Quit $PIECE(location, "_history/", $LENGTH(location, "_history/")) = vid
}

/// The part's status as a whole number, 0 for anything else.
ClassMethod Status(part As %DynamicObject) As %Integer [ Private ]
{
    Set type = part.%GetTypeOf("http_status")
    If (type '= "number") && (type '= "string") Quit 0
    Set value = part.%Get("http_status")
    Quit $SELECT(value ? 1.3N: +value, 1: 0)
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

ClassMethod IsArray(x) As %Boolean [ Private ]
{
    Quit $ISOBJECT(x) && x.%IsA("%DynamicArray")
}

}
