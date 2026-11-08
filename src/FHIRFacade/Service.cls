/// The test FHIR server: a FHIR R4 server for Encounter, Patient and Location that answers, by default, as IRIS for
/// Health's own FHIR server was measured to answer (2026.2 Build 221U, 2026.3.0AI Build 154U and 2027.1.0AI Build 109U,
/// on the JsonAdvSQL strategy), so a test run against it says something about IRIS. <class>FHIRFacade.API</class> is its
/// HTTP face; tests call <method>Handle</method> in process.
/// <p>What it does, as measured on IRIS: read, vread, instance history, search by identifier, PUT with and without
/// <code>If-Match</code>, DELETE and the CapabilityStatement. The ETag is always <code>W/"</code> + versionId +
/// <code>"</code>; a malformed <code>If-Match</code> is 405 and a stale one 412, with nothing written; a PUT makes a new
/// version even when nothing changed, overwrites the client's <code>meta.versionId</code> and <code>meta.lastUpdated</code>
/// silently, and stores <code>meta.tag</code> exactly as sent (no carry-over); a body is held to IRIS's structural
/// checks (<class>FHIRFacade.Structure</class>) and an id in the URL to its form; a good write answers an empty
/// <code>text/html</code> 200 unless <code>Prefer: return=representation</code>; history is newest first, whole, with no
/// ETags and no paging; references are not checked, <code>modifierExtension</code> is stored, <code>text</code> is never
/// made.</p>
/// <p>What it does not do, and says so with a 400 (<class>FHIRFacade.Outcome</class>, NotImplemented): create by POST,
/// PATCH, transactions and batches, conditional interactions, <code>$</code> operations, other resource types, XML and
/// <code>_format</code>, search parameters but <code>identifier</code>, profile validation. Login failures belong to the
/// web application (IRIS answers a failed login with a plain-text 404), TLS to the web server. Fault modes are added
/// separately; with none set, this class is the plain server.</p>
Class FHIRFacade.Service
{

Parameter FHIRJSON = "application/fhir+json; charset=UTF-8";

Parameter HTML = "text/html; charset=utf-8";

/// The resource types this server keeps, each compared as a whole name.
Parameter TYPES = "Encounter,Location,Patient";

/// The ids IRIS takes in a URL.
Parameter ID = "[A-Za-z0-9\-\.]{1,64}";

/// The tag IRIS puts on a body reduced by <code>_elements</code>.
Parameter SUBSETTEDSYSTEM = "http://terminology.hl7.org/CodeSystem/v3-ObservationValue";

/// One request, answered. <var>request</var> is <code>{"method", "path" (after the base, such as
/// "Encounter/enc-1/_history", decoded once, as the web gateway hands it over), "query" (the raw query string),
/// "headers" {"If-Match", "Prefer", ...}, "body" (a string), "base" (the absolute base URL, for links)}</code>. The
/// answer is <code>{"status", "headers" {"ETag", "Location", "Last-Modified", "Content-Type"}, "body" (a string,
/// possibly empty)}</code>.
ClassMethod Handle(request As %DynamicObject) As %DynamicObject
{
    Try {
        Set answer = ..Route(request)
    } Catch ex {
        Set answer = ..Fhir(500, ##class(FHIRFacade.Outcome).Failure(ex.DisplayString()))
    }
    Quit answer
}

/// Every resource and version gone, version ids from "1" again, as IRIS's <code>HS.FHIRServer.Installer.Reset</code>
/// leaves its store: a PUT with an ETag from before gets 412 with the current version ''.
ClassMethod Reset()
{
    Do ##class(FHIRFacade.Store).Reset()
}

/// Writes each resource by its id with a PUT and no <code>If-Match</code>; returns <code>[{"type", "id", "status"}]</code>.
ClassMethod Seed(resources As %DynamicArray) As %DynamicArray
{
    Set out = []
    Set iter = resources.%GetIterator()
    While iter.%GetNext(, .resource) {
        Set type = "", id = ""
        If $ISOBJECT(resource) Set type = resource.resourceType, id = resource.id
        Set answer = ..Handle({"method": "PUT", "path": (type _ "/" _ id), "query": "", "headers": {}, "body": ($SELECT($ISOBJECT(resource): resource.%ToJSON(), 1: "")), "base": ""})
        Do out.%Push({"type": (type), "id": (id), "status": (answer.status)})
    }
    Quit out
}

/// Fixes the clock at <var>instant</var> (<code>YYYY-MM-DDThh:mm:ssZ</code>), or frees it with "".
ClassMethod SetClock(instant As %String)
{
    Do ##class(FHIRFacade.Store).SetClock(instant)
}

/// The demo control <code>POST /admin/reset</code>: a reset, then the seed when <var>body</var> is a JSON array of
/// resources. A body that is neither empty nor an array changes nothing and is refused.
ClassMethod AdminReset(body As %String) As %DynamicObject
{
    Set seed = ""
    If $ZSTRIP(body, "<>W") '= "" {
        Try {
            Set seed = [].%FromJSON(body)
        } Catch {
            Set seed = ""
        }
        If '$ISOBJECT(seed) || 'seed.%IsA("%Library.DynamicArray") {
            Quit {"status": 400, "headers": {"Content-Type": "application/json; charset=utf-8"}, "body": ({"error": "the body must be empty or a JSON array of resources"}.%ToJSON())}
        }
    }
    Do ..Reset()
    Set seeded = $SELECT($ISOBJECT(seed): ..Seed(seed), 1: [])
    Quit {"status": 200, "headers": {"Content-Type": "application/json; charset=utf-8"}, "body": ({"reset": true, "seeded": (seeded)}.%ToJSON())}
}

ClassMethod Route(request As %DynamicObject) As %DynamicObject [ Private ]
{
    Set method = $ZCONVERT(request.method, "U"), path = request.path, query = request.query, base = request.base
    Set headers = $SELECT($ISOBJECT(request.headers): request.headers, 1: {})
    While $EXTRACT(path) = "/" {
        Set path = $EXTRACT(path, 2, *)
    }
    While (path '= "") && ($EXTRACT(path, *) = "/") {
        Set path = $EXTRACT(path, 1, *-1)
    }
    Set n = $SELECT(path = "": 0, 1: $LENGTH(path, "/"))
    // The path is not decoded again: IRIS takes a%2541 as the id a%41.
    For i = 1:1:4 {
        Set p(i) = $PIECE(path, "/", i)
    }
    // An empty segment (Encounter//_history) is IRIS's empty 404, before anything is looked up.
    Quit:path["//" ..Empty(404, {})
    Set params = ..Params(query)
    If n = 0 Quit ..NotImplemented("A request to the base (a transaction, a batch or a system search)")
    If (n = 1) && (p(1) = "metadata") {
        Quit:method="GET" ..Metadata(base)
        Quit ..NotImplemented(method _ " metadata")
    }
    If p(1) = "_history" {
        Quit:(n=1)&&(method="GET") ..Fhir(400, ##class(FHIRFacade.Outcome).SystemHistory())
        Quit ..NotImplemented("The request " _ method _ " " _ path)
    }
    Quit:$EXTRACT(p(1))="$" ..NotImplemented("The operation '" _ p(1) _ "'")
    If '$LISTFIND($LISTFROMSTRING(..#TYPES), p(1)) {
        // A name that is not a single type name (Encounter,Location) is IRIS's empty 404.
        Quit:p(1)'?1A.AN ..Empty(404, {})
        Quit ..NotImplemented("The resource type '" _ p(1) _ "'")
    }
    Set type = p(1)
    If n = 1 {
        Quit:method="GET" ..Search(type, params, query, base)
        Quit:method="POST" ..NotImplemented("Create by POST")
        Quit ..NotImplemented("A conditional " _ method)
    }
    If p(2) = "_history" {
        Quit:(n=2)&&(method="GET") ..Fhir(400, ##class(FHIRFacade.Outcome).TypeHistory(type))
        Quit ..NotImplemented("The request " _ method _ " " _ path)
    }
    Quit:$EXTRACT(p(2))="$" ..NotImplemented("The operation '" _ p(2) _ "'")
    Set id = p(2)
    Quit:'$MATCH(id, ..#ID) ..Fhir(400, ##class(FHIRFacade.Outcome).InvalidId(id))
    If n = 2 {
        Quit:method="GET" ..Read(type, id, params, base)
        Quit:method="PUT" ..Update(type, id, headers, request.body, base)
        Quit:method="DELETE" ..Delete(type, id)
        Quit ..NotImplemented(method _ " on a resource")
    }
    If (n = 3) && (p(3) = "_history") {
        Quit:method="GET" ..History(type, id, params, query, base)
        Quit ..NotImplemented(method _ " on a history")
    }
    If (n = 3) && ($EXTRACT(p(3)) = "$") {
        Set operation = $EXTRACT(p(3), 2, *)
        If (operation = "meta") || (operation = "meta-add") || (operation = "meta-delete") {
            Quit ..Fhir(400, ##class(FHIRFacade.Outcome).OperationNotSupported(operation))
        }
        Quit ..NotImplemented("The operation '" _ p(3) _ "'")
    }
    If (n = 4) && (p(3) = "_history") {
        Quit:method="GET" ..VRead(type, id, p(4), params, base)
        Quit ..NotImplemented(method _ " on a version")
    }
    Quit ..NotImplemented("The request " _ method _ " " _ path)
}

/// GET {type}/{id}: the current version, or 404, or 410 when its latest version is a delete.
ClassMethod Read(type As %String, id As %String, params As %DynamicArray, base As %String) As %DynamicObject [ Private ]
{
    Set refused = ..ReadParams(params, .elements)
    Quit:$ISOBJECT(refused) refused
    If '##class(FHIRFacade.Store).Current(type, id, .vid, .deleted) Quit ..Fhir(404, ##class(FHIRFacade.Outcome).NotFound(type, id))
    Quit:deleted ..Fhir(410, ##class(FHIRFacade.Outcome).Deleted(type, id))
    Quit ..Served(type, id, vid, elements, base)
}

/// GET {type}/{id}/_history/{vid}: that version, the same text every time; 410 for a delete's own version.
ClassMethod VRead(type As %String, id As %String, vid As %String, params As %DynamicArray, base As %String) As %DynamicObject [ Private ]
{
    Set refused = ..ReadParams(params, .elements)
    Quit:$ISOBJECT(refused) refused
    If '##class(FHIRFacade.Store).Version(type, id, vid, .method) Quit ..Fhir(404, ##class(FHIRFacade.Outcome).VersionNotFound(type, id, vid))
    Quit:method="DELETE" ..Fhir(410, ##class(FHIRFacade.Outcome).Deleted(type, id, vid))
    Quit ..Served(type, id, vid, elements, base)
}

/// A read's parameters: <code>_elements</code> (kept in <var>elements</var>) and <code>_summary=data</code> are
/// answered; every other <code>_summary</code> is IRIS's 400 for <code>true</code>; other parameters are not implemented.
ClassMethod ReadParams(params As %DynamicArray, Output elements As %String) As %DynamicObject [ Private ]
{
    Set elements = "", refused = ""
    Set iter = params.%GetIterator()
    While iter.%GetNext(, .pair) {
        Set name = pair.%Get(0), value = pair.%Get(1)
        If name = "_elements" {
            Set elements = $ZSTRIP(value, "*W")
        } ElseIf name = "_summary" {
            If value '= "data" Set refused = ..Fhir(400, ##class(FHIRFacade.Outcome).InvalidSummary(value))
        } Else {
            Set refused = ..NotImplemented("The parameter '" _ name _ "' on a read")
        }
        Quit:$ISOBJECT(refused)
    }
    Quit refused
}

ClassMethod Served(type As %String, id As %String, vid As %String, elements As %String, base As %String) As %DynamicObject [ Private ]
{
    Do ##class(FHIRFacade.Store).Version(type, id, vid, , .lastModified, .text)
    Set:elements'="" text = ..Subset(text, elements)
    Quit ..Fhir(200, text, ..VersionHeaders(type, id, vid, lastModified, base))
}

/// The body IRIS gives for <code>_elements</code>: resourceType, id and the named elements in their stored order, and a
/// <code>meta</code> that holds only the SUBSETTED tag (versionId, lastUpdated and the stored tags gone).
ClassMethod Subset(text As %String, elements As %String) As %String [ Private ]
{
    Set source = {}.%FromJSON(text), out = {}, wanted = "," _ elements _ ","
    Set iter = source.%GetIterator()
    While iter.%GetNext(.key) {
        Continue:key="meta"
        If (key = "resourceType") || (key = "id") || (wanted [ ("," _ key _ ",")) {
            Do ..Copy(source, key, out)
        }
    }
    Do out.%Set("meta", {"tag": [{"system": (..#SUBSETTEDSYSTEM), "code": "SUBSETTED", "display": "Resource content reduced because _elements search parameter"}]})
    Quit out.%ToJSON()
}

/// Copies one member, keeping its JSON type.
ClassMethod Copy(source As %DynamicObject, key As %String, target As %DynamicObject) [ Private ]
{
    Set kind = source.%GetTypeOf(key)
    If (kind = "boolean") || (kind = "null") || (kind = "number") {
        Do target.%Set(key, source.%Get(key), kind)
    } Else {
        Do target.%Set(key, source.%Get(key))
    }
}

/// GET {type}/{id}/_history: every version and delete, newest first, in one Bundle. A positive <code>_count</code> is
/// ignored, as IRIS ignores it (no paging, no <code>next</code>); 0 or a non-number is 400. <code>_since</code> keeps the
/// entries modified at or after it; <code>page</code> and <code>_page</code> are ignored, as on IRIS.
ClassMethod History(type As %String, id As %String, params As %DynamicArray, query As %String, base As %String) As %DynamicObject [ Private ]
{
    Set since = "", refused = ""
    Set iter = params.%GetIterator()
    While iter.%GetNext(, .pair) {
        Set name = pair.%Get(0), value = pair.%Get(1)
        If name = "_count" {
            If '..PositiveCount(value) Set refused = ..Fhir(400, ##class(FHIRFacade.Outcome).InvalidCount(value))
        } ElseIf name = "_since" {
            Set since = value
        } ElseIf (name '= "page") && (name '= "_page") {
            Set refused = ..NotImplemented("The parameter '" _ name _ "' on a history")
        }
        Quit:$ISOBJECT(refused)
    }
    Quit:$ISOBJECT(refused) refused
    If '##class(FHIRFacade.Store).Current(type, id) Quit ..Fhir(404, ##class(FHIRFacade.Outcome).NotFound(type, id))
    Set entries = []
    For n = ##class(FHIRFacade.Store).Count(type, id):-1:1 {
        Do ##class(FHIRFacade.Store).Nth(type, id, n, , .method, .lastModified, .text)
        Continue:(since'="")&&(since]]lastModified)
        Set entry = {}
        Do:method'="DELETE" entry.%Set("resource", {}.%FromJSON(text))
        Do entry.%Set("request", {"method": (method), "url": (type _ "/" _ id)})
        Do entry.%Set("response", {"status": "200", "lastModified": (lastModified)})
        Do entries.%Push(entry)
    }
    Set bundle = {"resourceType": "Bundle", "id": (..NewId()), "type": "history", "timestamp": (..Now()), "total": (entries.%Size()), "link": [{"relation": "self", "url": (..Self(base, type _ "/" _ id _ "/_history", query))}], "entry": (entries)}
    Quit ..Fhir(200, bundle.%ToJSON())
}

/// GET {type}?identifier=system|value: a searchset of the current versions that match, in the order they were first
/// written. The value is matched without regard to case and the system with it, with no prefix match; a bare value
/// matches any system, <code>|value</code> only identifiers with no system, <code>system|</code> every value. Pages of
/// <code>_count</code> (100 by default) with <code>first</code>, <code>next</code> and <code>last</code> links that carry
/// <code>page</code> and <code>queryId</code>, served from the kept result.
ClassMethod Search(type As %String, params As %DynamicArray, query As %String, base As %String) As %DynamicObject [ Private ]
{
    Set tokens = [], count = "", page = "", qid = "", refused = ""
    Set iter = params.%GetIterator()
    While iter.%GetNext(, .pair) {
        Set name = pair.%Get(0), value = pair.%Get(1)
        If name = "identifier" {
            Do tokens.%Push(value)
        } ElseIf $PIECE(name, ":", 1) = "identifier" {
            Set refused = ..Fhir(400, ##class(FHIRFacade.Outcome).UnsupportedModifier($PIECE(name, ":", 2, *), "identifier"))
        } ElseIf name = "_count" {
            If ..PositiveCount(value) {
                Set count = +value
            } Else {
                Set refused = ..Fhir(400, ##class(FHIRFacade.Outcome).InvalidCount(value))
            }
        } ElseIf name = "page" {
            Set page = value
        } ElseIf name = "queryId" {
            Set qid = value
        } Else {
            Set refused = ..NotImplemented("The search parameter '" _ name _ "'")
        }
        Quit:$ISOBJECT(refused)
    }
    Quit:$ISOBJECT(refused) refused
    If qid '= "" {
        If '##class(FHIRFacade.Store).Query(qid, .kept, .size, .ids) || (kept '= type) Quit ..Fhir(404, ##class(FHIRFacade.Outcome).UnknownQuery(qid))
        Set:page="" page = 1
        Quit:'..PositiveCount(page) ..Fhir(400, ##class(FHIRFacade.Outcome).Issue("warning", "value", "<FacadeErr>InvalidParameterValue", "The value '" _ page _ "' is invalid for the 'page' parameter"))
        Set page = +page
    } Else {
        Set size = $SELECT(count '= "": count, 1: 100), page = 1, ids = []
        Set all = ##class(FHIRFacade.Store).Ids(type)
        Set walk = all.%GetIterator()
        While walk.%GetNext(, .id) {
            Continue:'##class(FHIRFacade.Store).Current(type, id, .vid, .deleted)
            Continue:deleted
            Do ##class(FHIRFacade.Store).Version(type, id, vid, , , .text)
            Set resource = {}.%FromJSON(text), ok = 1
            Set each = tokens.%GetIterator()
            While each.%GetNext(, .token) {
                If '..Matches(resource, token) Set ok = 0 Quit
            }
            Do:ok ids.%Push(id)
        }
        Set:ids.%Size()>size qid = ##class(FHIRFacade.Store).SaveQuery(type, ids, size, query)
    }
    Set total = ids.%Size(), last = (total + size - 1) \ size
    Set:last<1 last = 1
    Set entries = []
    For i = (page - 1) * size:1:(page * size) - 1 {
        Quit:i>=total
        Set id = ids.%Get(i)
        Continue:'##class(FHIRFacade.Store).Current(type, id, .vid, .deleted)
        Continue:deleted
        Do ##class(FHIRFacade.Store).Version(type, id, vid, , , .text)
        Do entries.%Push({"fullUrl": (base _ "/" _ type _ "/" _ id), "resource": ({}.%FromJSON(text)), "search": {"mode": "match"}})
    }
    Set links = []
    If qid '= "" {
        Set paged = base _ "/" _ type _ "?page="
        Do links.%Push({"relation": "first", "url": (paged _ "1&queryId=" _ qid)})
        Do links.%Push({"relation": "self", "url": (..Self(base, type, query))})
        Do:page>1 links.%Push({"relation": "previous", "url": (paged _ (page - 1) _ "&queryId=" _ qid)})
        Do:page<last links.%Push({"relation": "next", "url": (paged _ (page + 1) _ "&queryId=" _ qid)})
        Do links.%Push({"relation": "last", "url": (paged _ last _ "&queryId=" _ qid)})
    } Else {
        Do links.%Push({"relation": "self", "url": (..Self(base, type, query))})
    }
    Set bundle = {"resourceType": "Bundle", "id": (..NewId()), "type": "searchset", "timestamp": (..Now()), "total": (total), "link": (links)}
    Do:entries.%Size()>0 bundle.%Set("entry", entries)
    Quit ..Fhir(200, bundle.%ToJSON())
}

/// Whether one <code>identifier</code> token matches the resource (see <method>Search</method>).
ClassMethod Matches(resource As %DynamicObject, token As %String) As %Boolean [ Private ]
{
    Set list = resource.%Get("identifier")
    Quit:'$ISOBJECT(list) 0
    Quit:'list.%IsA("%Library.DynamicArray") 0
    Set barred = (token [ "|"), system = $PIECE(token, "|", 1), value = $PIECE(token, "|", 2, *)
    Set:'barred value = token, system = ""
    Set iter = list.%GetIterator()
    While iter.%GetNext(, .identifier) {
        Continue:'$ISOBJECT(identifier)
        Continue:'identifier.%IsA("%Library.DynamicObject")
        If barred {
            If system = "" {
                Continue:identifier.%IsDefined("system")
            } Else {
                Continue:(identifier.%Get("system")_"")'=system
            }
            Continue:(value'="")&&($ZCONVERT(identifier.%Get("value"), "U")'=$ZCONVERT(value, "U"))
        } Else {
            Continue:$ZCONVERT(identifier.%Get("value"), "U")'=$ZCONVERT(value, "U")
        }
        Return 1
    }
    Quit 0
}

/// PUT {type}/{id}. Checks in this order: a malformed <code>If-Match</code> is 405; a body this server cannot store is
/// 400, and so is one that fails IRIS's structural checks (<class>FHIRFacade.Structure</class>: every problem listed
/// in one OperationOutcome); an <code>id</code> missing or not the URL's is 400; an <code>If-Match</code> whose
/// version is not the current one ('' for an id never written, the delete's version for a deleted one) is 412. Nothing
/// is written by a refusal. Otherwise a new version: 200 for an id written before (deleted ones included), 201 for a new
/// one, which only a PUT without <code>If-Match</code> can make.
ClassMethod Update(type As %String, id As %String, headers As %DynamicObject, body As %String, base As %String) As %DynamicObject [ Private ]
{
    // HTTP drops the spaces around a header's value; IRIS accepted W/"2" with a trailing space.
    Set ifMatch = $ZSTRIP(..Header(headers, "If-Match"), "<>W"), prefer = $ZCONVERT(..Header(headers, "Prefer"), "L")
    Set asked = ""
    If ifMatch '= "" {
        Set asked = ..EtagVersion(ifMatch)
        Quit:asked="" ..Fhir(405, ##class(FHIRFacade.Outcome).InvalidIfMatch(ifMatch))
    }
    Set resource = ""
    Try {
        Set resource = {}.%FromJSON(body)
    } Catch {
        Set resource = ""
    }
    If '$ISOBJECT(resource) || 'resource.%IsA("%Library.DynamicObject") Quit ..Fhir(400, ##class(FHIRFacade.Outcome).Unreadable("The body is not a JSON object"))
    If resource.%Get("resourceType") '= type Quit ..Fhir(400, ##class(FHIRFacade.Outcome).Unreadable("The body's resourceType is not '" _ type _ "'"))
    Set problem = ##class(FHIRFacade.Structure).Check(type, resource)
    Quit:problem'="" ..Fhir(400, problem)
    If (resource.%GetTypeOf("id") '= "string") || (resource.%Get("id") '= id) Quit ..Fhir(400, ##class(FHIRFacade.Outcome).InvalidUpdateId())
    Quit:'##class(FHIRFacade.Store).Lock(type, id) ..Fhir(500, ##class(FHIRFacade.Outcome).Failure("The resource is locked by another request"))
    Try {
        Set exists = ##class(FHIRFacade.Store).Current(type, id, .current)
        If (ifMatch '= "") && (asked '= current) {
            Set answer = ..Fhir(412, ##class(FHIRFacade.Outcome).IfMatchViolation(asked, current))
        } Else {
            Set vid = ##class(FHIRFacade.Store).NextVid(type, id), now = ..Now()
            Do ..Stamp(resource, vid, now)
            Set text = resource.%ToJSON()
            Do ##class(FHIRFacade.Store).Append(type, id, vid, "PUT", text, now)
            Set status = $SELECT(exists: 200, 1: 201), out = ..VersionHeaders(type, id, vid, now, base)
            If prefer [ "return=representation" {
                Set answer = ..Fhir(status, text, out)
            } Else {
                Set answer = ..Empty(status, out)
            }
        }
    } Catch ex {
        Set answer = ..Fhir(500, ##class(FHIRFacade.Outcome).Failure(ex.DisplayString()))
    }
    Do ##class(FHIRFacade.Store).Unlock(type, id)
    Quit answer
}

/// DELETE {type}/{id}: 204 with the delete's own ETag (a delete takes a version id), no body; the resource then reads
/// as 410 until a PUT brings it back as an update (200). An id never written is 404, one already deleted 410 (neither
/// measured on IRIS).
ClassMethod Delete(type As %String, id As %String) As %DynamicObject [ Private ]
{
    Quit:'##class(FHIRFacade.Store).Lock(type, id) ..Fhir(500, ##class(FHIRFacade.Outcome).Failure("The resource is locked by another request"))
    Try {
        If '##class(FHIRFacade.Store).Current(type, id, , .deleted) {
            Set answer = ..Fhir(404, ##class(FHIRFacade.Outcome).NotFound(type, id))
        } ElseIf deleted {
            Set answer = ..Fhir(410, ##class(FHIRFacade.Outcome).Deleted(type, id))
        } Else {
            Set vid = ##class(FHIRFacade.Store).NextVid(type, id)
            Do ##class(FHIRFacade.Store).Append(type, id, vid, "DELETE", "", ..Now())
            Set answer = {"status": 204, "headers": {"ETag": (..Etag(vid))}, "body": ""}
        }
    } Catch ex {
        Set answer = ..Fhir(500, ##class(FHIRFacade.Outcome).Failure(ex.DisplayString()))
    }
    Do ##class(FHIRFacade.Store).Unlock(type, id)
    Quit answer
}

/// Overwrites <code>meta.lastUpdated</code> and <code>meta.versionId</code> where they stand, or adds them at the end
/// of <code>meta</code>; a body with no <code>meta</code> gets one at its end. Nothing else in <code>meta</code> changes:
/// its tags are stored exactly as sent.
ClassMethod Stamp(resource As %DynamicObject, vid As %String, now As %String) [ Private ]
{
    If 'resource.%IsDefined("meta") {
        Do resource.%Set("meta", {"lastUpdated": (now), "versionId": (vid)})
        Quit
    }
    Set meta = resource.%Get("meta")
    Do meta.%Set("lastUpdated", now, "string")
    Do meta.%Set("versionId", vid, "string")
}

/// GET metadata: a CapabilityStatement whose Encounter, Patient and Location entries carry the fields the gate's
/// capability row reads, as IRIS states them. The software is named as this server, never as an IRIS build, so no
/// proof can be recorded from it as if it were IRIS.
ClassMethod Metadata(base As %String) As %DynamicObject [ Private ]
{
    Set resources = []
    For type = "Encounter", "Location", "Patient" {
        Set interactions = []
        For code = "read", "vread", "create", "update", "patch", "delete", "history-instance", "search-type" {
            Do interactions.%Push({"code": (code)})
        }
        Do resources.%Push({"type": (type), "profile": ("http://hl7.org/fhir/StructureDefinition/" _ type _ "|4.0.1"), "versioning": "versioned-update", "readHistory": true, "updateCreate": true, "conditionalUpdate": true, "interaction": (interactions), "searchParam": [{"name": "identifier", "definition": ("http://hl7.org/fhir/SearchParameter/" _ type _ "-identifier|4.0.1"), "type": "token"}]})
    }
    Set statement = {"resourceType": "CapabilityStatement", "id": (..NewId()), "url": (base _ "/metadata"), "version": "1", "name": "Shutter test FHIR server", "status": "active", "experimental": true, "date": ($EXTRACT(..Now(), 1, 10)), "publisher": "Shutter", "kind": "instance", "software": {"name": "Shutter test FHIR server", "version": "facade-v1"}, "implementation": {"description": "Shutter test FHIR server", "url": (base)}, "fhirVersion": "4.0.1", "format": ["json"], "rest": [{"mode": "server", "resource": (resources)}]}
    Quit ..Fhir(200, statement.%ToJSON())
}

/// The version id an ETag carries: only <code>W/"</code>, one or more characters other than <code>"</code>, and
/// <code>"</code>, as IRIS demands; "" for any other form (<code>"2"</code>, <code>2</code>, <code>W/2</code>,
/// <code>w/"2"</code>, <code>*</code>).
ClassMethod EtagVersion(etag As %String) As %String
{
    Quit:$EXTRACT(etag, 1, 3)'="W/""" ""
    Quit:$LENGTH(etag)<5 ""
    Quit:$EXTRACT(etag, *)'="""" ""
    Set vid = $EXTRACT(etag, 4, *-1)
    Quit:vid["""" ""
    Quit vid
}

ClassMethod Etag(vid As %String) As %String [ Private ]
{
    Quit "W/""" _ vid _ """"
}

ClassMethod VersionHeaders(type As %String, id As %String, vid As %String, lastModified As %String, base As %String) As %DynamicObject [ Private ]
{
    Quit {"ETag": (..Etag(vid)), "Location": (base _ "/" _ type _ "/" _ id _ "/_history/" _ vid), "Last-Modified": (..HttpDate(lastModified))}
}

ClassMethod Fhir(status As %Integer, body As %String, headers As %DynamicObject = "") As %DynamicObject [ Private ]
{
    Set:'$ISOBJECT(headers) headers = {}
    Do headers.%Set("Content-Type", ..#FHIRJSON)
    Quit {"status": (status), "headers": (headers), "body": (body)}
}

/// The answer of a good write without a representation: an empty body labelled <code>text/html</code>, as IRIS sends it.
ClassMethod Empty(status As %Integer, headers As %DynamicObject) As %DynamicObject [ Private ]
{
    Do headers.%Set("Content-Type", ..#HTML)
    Quit {"status": (status), "headers": (headers), "body": ""}
}

ClassMethod NotImplemented(what As %String) As %DynamicObject [ Private ]
{
    Quit ..Fhir(400, ##class(FHIRFacade.Outcome).NotImplemented(what))
}

/// A header's value whatever the case of its name, or "".
ClassMethod Header(headers As %DynamicObject, name As %String) As %String [ Private ]
{
    Set want = $ZCONVERT(name, "L")
    Set iter = headers.%GetIterator()
    While iter.%GetNext(.key, .value) {
        Return:$ZCONVERT(key, "L")=want value
    }
    Quit ""
}

/// The query string as <code>[[name, value], ...]</code>, in order, each part URL-decoded.
ClassMethod Params(query As %String) As %DynamicArray [ Private ]
{
    Set out = []
    For i = 1:1:$LENGTH(query, "&") {
        Set pair = $PIECE(query, "&", i)
        Continue:pair=""
        Do out.%Push([(..Unescape($PIECE(pair, "=", 1))), (..Unescape($PIECE(pair, "=", 2, *)))])
    }
    Quit out
}

ClassMethod Unescape(text As %String) As %String [ Private ]
{
    Quit:text'["%" text
    Quit $ZCONVERT($ZCONVERT(text, "I", "URL"), "I", "UTF8")
}

ClassMethod PositiveCount(value As %String) As %Boolean [ Private ]
{
    Quit (value?1.N) && (+value > 0)
}

ClassMethod Self(base As %String, path As %String, query As %String) As %String [ Private ]
{
    Quit base _ "/" _ path _ $SELECT(query = "": "", 1: "?" _ query)
}

ClassMethod NewId() As %String [ Private ]
{
    Quit $ZCONVERT($SYSTEM.Util.CreateGUID(), "L")
}

/// The time now, <code>YYYY-MM-DDThh:mm:ssZ</code> in UTC at one-second precision, or the fixed clock.
ClassMethod Now() As %String
{
    Set clock = ##class(FHIRFacade.Store).Clock()
    Quit:clock'="" clock
    Set now = $ZTIMESTAMP
    Quit $ZDATE(+now, 3) _ "T" _ $ZTIME($PIECE(now, ",", 2) \ 1, 1) _ "Z"
}

/// An instant as an HTTP date (RFC 1123), as IRIS's <code>Last-Modified</code>: "Sun, 08 Nov 2026 02:31:53 GMT".
ClassMethod HttpDate(instant As %String) As %String
{
    Set day = $ZDATEH($EXTRACT(instant, 1, 10), 3), time = $ZTIMEH($EXTRACT(instant, 12, 19), 1)
    Quit $ZDATE(day, 11) _ ", " _ $ZDATE(day, 2) _ " " _ $ZTIME(time, 1) _ " GMT"
}

}
