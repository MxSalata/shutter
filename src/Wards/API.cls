/// The synthetic ward system's REST API at <code>/wards/api</code> (docs/CONTRACTS.md, section 1). The web
/// application requires password authentication and the <code>Wards_API</code> resource; this class only
/// translates between HTTP and <class>Wards.Service</class>.
Class Wards.API Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "utf-8";

Parameter HandleCorsRequest = 0;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/operations" Method="POST" Call="PostOperation"/>
<Route Url="/encounters/:id" Method="GET" Call="GetEncounter"/>
<Route Url="/receipts/:key" Method="GET" Call="GetReceipt"/>
<Route Url="/faults" Method="POST" Call="PostFault"/>
<Route Url="/faults" Method="GET" Call="GetFault"/>
<Route Url="/reset" Method="POST" Call="PostReset"/>
<Route Url="/capabilities" Method="GET" Call="GetCapabilities"/>
<Route Url="/capabilities" Method="POST" Call="PostCapabilities"/>
</Routes>
}

ClassMethod PostOperation() As %Status
{
    Set request = ..Body(.problem)
    If problem '= "" {
        Quit ..Reply(422, {"error": "invalid_request", "detail": (problem)})
    }
    Set body = ##class(Wards.Service).Apply(request, .status)
    Quit ..Reply(status, body)
}

ClassMethod GetEncounter(id As %String) As %Status
{
    Set body = ##class(Wards.Service).GetEncounter(..Decode(id), .status)
    Quit ..Reply(status, body)
}

ClassMethod GetReceipt(key As %String) As %Status
{
    Set body = ##class(Wards.Service).GetReceipt(..Decode(key), .status)
    Quit ..Reply(status, body)
}

ClassMethod PostFault() As %Status
{
    Set request = ..Body(.problem)
    If problem '= "" {
        Quit ..Reply(422, {"error": "invalid_request", "detail": (problem)})
    }
    Set body = ##class(Wards.Service).SetFault(request, .status)
    Quit ..Reply(status, body)
}

ClassMethod GetFault() As %Status
{
    Set body = ##class(Wards.Service).GetFault(.status)
    Quit ..Reply(status, body)
}

ClassMethod PostReset() As %Status
{
    Set body = ##class(Wards.Service).Reset(.status)
    Quit ..Reply(status, body)
}

ClassMethod GetCapabilities() As %Status
{
    Set body = ##class(Wards.Service).GetCapabilities(.status)
    Quit ..Reply(status, body)
}

ClassMethod PostCapabilities() As %Status
{
    Set request = ..Body(.problem)
    If problem '= "" {
        Quit ..Reply(422, {"error": "invalid_request", "detail": (problem)})
    }
    Set body = ##class(Wards.Service).SetCapabilities(request, .status)
    Quit ..Reply(status, body)
}

/// The request body as a JSON object, or an empty object and the reason in <var>problem</var>.
ClassMethod Body(Output problem As %String) As %DynamicObject [ Private ]
{
    Set problem = "", request = {}
    Try {
        Set parsed = {}.%FromJSON(%request.Content)
        If $ISOBJECT(parsed), parsed.%IsA("%Library.DynamicObject") {
            Set request = parsed
        } Else {
            Set problem = "the body must be a JSON object"
        }
    } Catch {
        Set problem = "the body is not valid JSON"
    }
    Quit request
}

/// A path argument, decoded if it still carries URL escapes (an operation key contains ^ and :).
ClassMethod Decode(value As %String) As %String [ Private ]
{
    Quit:value'["%" value
    Quit $ZCONVERT(value, "I", "URL")
}

ClassMethod Reply(code As %Integer, body) As %Status [ Private ]
{
    Set %response.Status = code _ " " _ $CASE(code, 200: "OK", 201: "Created", 403: "Forbidden", 404: "Not Found", 409: "Conflict", 422: "Unprocessable Entity", 500: "Internal Server Error", 503: "Service Unavailable", 504: "Gateway Timeout", : "Error")
    Write:$ISOBJECT(body) body.%ToJSON()
    Quit $$$OK
}

}
