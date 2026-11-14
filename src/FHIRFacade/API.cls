/// The test FHIR server's HTTP face: every request under the web application is handed to
/// <class>FHIRFacade.Service</class> and its answer written back as it came, status, headers and body. The content type
/// and charset are set on every answer, so the web gateway's default never shows. No web application is defined here;
/// the one that serves this class asks for a password and nothing else.
/// <p>A caller needs the <code>FHIRFacade_API</code> resource, <code>READ</code> to read and <code>WRITE</code> to
/// write; without it the answer is 403 with an empty <code>text/html</code> body, as IRIS answers a user without the
/// FHIR endpoint's required resource. The demo controls need <code>FHIRFacade_Admin</code> <code>USE</code>, which the
/// client a test uses does not hold: <code>POST /admin/reset</code> (with an optional JSON array of resources to seed),
/// <code>POST /admin/fault</code> (<code>{"modes": [..], "times": 1}</code>, the fault modes of
/// <class>FHIRFacade.Service</class>) and <code>GET /admin/stats</code> (the PUTs counted and the fault still set).</p>
Class FHIRFacade.API Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/fhir+json";

Parameter CHARSET = "UTF-8";

Parameter HandleCorsRequest = 0;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/admin/reset" Method="POST" Call="PostReset"/>
<Route Url="/admin/fault" Method="POST" Call="PostFault"/>
<Route Url="/admin/stats" Method="GET" Call="GetStats"/>
<Route Url="/(.*)" Method="GET" Call="Dispatch"/>
<Route Url="/(.*)" Method="PUT" Call="Dispatch"/>
<Route Url="/(.*)" Method="DELETE" Call="Dispatch"/>
<Route Url="/(.*)" Method="POST" Call="Dispatch"/>
<Route Url="/(.*)" Method="PATCH" Call="Dispatch"/>
</Routes>
}

ClassMethod Dispatch(path As %String) As %Status
{
    Set need = $SELECT(%request.Method = "GET": "READ", 1: "WRITE")
    Quit:'$SYSTEM.Security.Check("FHIRFacade_API", need) ..Forbidden()
    Quit ..Answer(##class(FHIRFacade.Service).Handle(..Request(path)))
}

ClassMethod PostReset() As %Status
{
    Quit:'$SYSTEM.Security.Check("FHIRFacade_Admin", "USE") ..Forbidden()
    Quit ..Answer(##class(FHIRFacade.Service).AdminReset(..Body()))
}

ClassMethod PostFault() As %Status
{
    Quit:'$SYSTEM.Security.Check("FHIRFacade_Admin", "USE") ..Forbidden()
    Quit ..Answer(##class(FHIRFacade.Service).AdminFault(..Body()))
}

ClassMethod GetStats() As %Status
{
    Quit:'$SYSTEM.Security.Check("FHIRFacade_Admin", "USE") ..Forbidden()
    Quit ..Answer(##class(FHIRFacade.Service).AdminStats())
}

/// The request as <class>FHIRFacade.Service</class> takes it.
ClassMethod Request(path As %String) As %DynamicObject [ Private ]
{
    Set headers = {}
    For name = "If-Match", "Prefer", "Accept" {
        Set value = %request.GetCgiEnv("HTTP_" _ $TRANSLATE($ZCONVERT(name, "U"), "-", "_"))
        Do:value'="" headers.%Set(name, value)
    }
    Do:%request.ContentType'="" headers.%Set("Content-Type", %request.ContentType)
    Set application = %request.Application
    Set:$EXTRACT(application, *)="/" application = $EXTRACT(application, 1, *-1)
    Set base = $SELECT(%request.Secure: "https", 1: "http") _ "://" _ %request.GetCgiEnv("HTTP_HOST") _ application
    Quit {"method": (%request.Method), "path": (path), "query": (%request.GetCgiEnv("QUERY_STRING")), "headers": (headers), "body": (..Body()), "base": (base)}
}

/// The body as text: the bytes read as UTF-8 when the gateway passed them through unconverted.
ClassMethod Body() As %String [ Private ]
{
    Quit:'$ISOBJECT(%request.Content) ""
    Do %request.Content.Rewind()
    Set text = ""
    While '%request.Content.AtEnd {
        Set text = text _ %request.Content.Read(32000)
    }
    Quit:%request.Content.%IsA("%Library.CharacterStream")||%request.Content.%IsA("%Stream.Character")||%request.Content.%IsA("%CSP.CharacterStream") text
    Quit $ZCONVERT(text, "I", "UTF8")
}

/// Writes one answer of <class>FHIRFacade.Service</class>.
ClassMethod Answer(answer As %DynamicObject) As %Status [ Private ]
{
    Set %response.Status = answer.status _ " " _ ..Reason(answer.status)
    Set type = "", iter = answer.headers.%GetIterator()
    While iter.%GetNext(.name, .value) {
        If name = "Content-Type" {
            Set type = value
        } Else {
            Do %response.SetHeader(name, value)
        }
    }
    Set %response.ContentType = $ZSTRIP($PIECE(type, ";", 1), "<>W")
    Set charset = $ZSTRIP($PIECE($PIECE(type, "charset=", 2), ";", 1), "<>W")
    Set %response.CharSet = charset
    Write:answer.body'="" answer.body
    Quit $$$OK
}

/// 403 with an empty body, before anything is read or written.
ClassMethod Forbidden() As %Status [ Private ]
{
    Set %response.Status = "403 Forbidden"
    Set %response.ContentType = "text/html"
    Set %response.CharSet = "utf-8"
    Quit $$$OK
}

ClassMethod Reason(status As %Integer) As %String [ Private ]
{
    Quit $CASE(status, 200: "OK", 201: "Created", 204: "No Content", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 410: "Gone", 412: "Precondition Failed", 500: "Internal Server Error", : "Error")
}

}
