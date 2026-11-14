/// An HTTP adapter that is the test FHIR server (<class>FHIRFacade.Service</class>) in process, for tests that drive
/// the FHIR operations with no web server: a request is handed to the server and its answer comes back as the real
/// adapter gives one.
/// <ul>
/// <li><property>Base</property>: what every address begins with (the entry's <code>fhir.base</code>). It is taken off
/// the address and given to the server as its base, so the links and Location headers in answers begin with it.</li>
/// <li><property>Requests</property>: <code>Requests(n) = $LISTBUILD(verb, path, ifMatch, body)</code> for the n-th
/// request, <code>Requests</code> itself the count. The path is the address after the base with no leading "/" and
/// with its query ("Encounter/enc-1/_history", "Encounter?identifier=a%7Cb"); the body is the entity body as
/// characters.</li>
/// <li><property>Follow</property>: <code>Follow(n)</code> is what the n-th request said of redirects (its
/// <code>FollowRedirect</code>): 0 for never, "" when it left that to the connection, which follows one for a
/// GET.</li>
/// <li><property>Handed</property>: <code>Handed(n)</code> is how many bytes of the n-th answer's body its stream
/// took. The body goes into the request's own response stream when it has one, as the connection writes it, and a
/// stream that refuses ends the answer there with an error status, as a read that fails does.
/// <code>Bound(n)</code> is that stream's limit in bytes, "" when the request brought no bounded stream.</li>
/// <li><property>Slow</property>: <code>Slow(verb, path)</code> seconds pass before that answer's body arrives.</li>
/// <li><property>Canned</property>: <code>Canned(verb, path) = $LISTBUILD(status, contentType, etag, location,
/// body)</code> answers that request instead of the server, every time: a page behind a 200, a plain 404, and with
/// status 0 no answer at all.</li>
/// </ul>
/// As the real adapter does, an answer that is not 2xx comes with its response and an error status
/// (<code>ErrHTTPStatus</code>), and no answer with an error status and no response. The body of a response is its
/// UTF-8 bytes, as a request with <code>ReadRawMode</code> set reads it.
Class Shutter.Test.FakeFhir Extends EnsLib.HTTP.OutboundAdapter
{

Property Base As %String(MAXLEN = "");

Property Requests As %String [ MultiDimensional ];

Property Follow As %String [ MultiDimensional ];

Property Canned As %String [ MultiDimensional ];

Property Handed As %String [ MultiDimensional ];

Property Bound As %String [ MultiDimensional ];

Property Slow As %String [ MultiDimensional ];

Method SendFormDataArray(Output pHttpResponse As %Net.HttpResponse, pOp As %String, pHttpRequest As %Net.HttpRequest, pFormVarNames As %String = "", ByRef pData, pURL As %String = "") As %Status
{
    Set pHttpResponse = $$$NULLOREF
    Set verb = $ZCONVERT(pOp, "U")
    Set path = pURL
    If (..Base '= "") && ($EXTRACT(path, 1, $LENGTH(..Base)) = ..Base) Set path = $EXTRACT(path, $LENGTH(..Base) + 1, *)
    While $EXTRACT(path) = "/" {
        Set path = $EXTRACT(path, 2, *)
    }
    Set headers = {}, body = "", type = ""
    If $ISOBJECT($GET(pHttpRequest)) {
        For name = "If-Match", "Accept", "Prefer" {
            Set value = pHttpRequest.GetHeader(name)
            Do:value'="" headers.%Set(name, value)
        }
        Set type = pHttpRequest.ContentType
        If $ISOBJECT(pHttpRequest.EntityBody) {
            Do pHttpRequest.EntityBody.Rewind()
            While 'pHttpRequest.EntityBody.AtEnd {
                Set body = body _ pHttpRequest.EntityBody.Read(32000)
            }
            Do pHttpRequest.EntityBody.Rewind()
        }
    }
    // A body handed over as data with no form variable name is the entity body too, as the real adapter takes it.
    If (pFormVarNames = "") && ($DATA(pData(1)) # 2) {
        If $ISOBJECT(pData(1)) {
            Do pData(1).Rewind()
            While 'pData(1).AtEnd {
                Set body = body _ pData(1).Read(32000)
            }
        } Else {
            Set body = body _ pData(1)
        }
    }
    Do:type'="" headers.%Set("Content-Type", type)
    Set body = ..Characters(body)
    Set ..Requests($INCREMENT(..Requests)) = $LISTBUILD(verb, path, headers.%Get("If-Match"), body)
    Set ..Follow(..Requests) = $SELECT($ISOBJECT($GET(pHttpRequest)): pHttpRequest.FollowRedirect, 1: "")
    If $DATA(..Canned(verb, path), canned) # 2 {
        Set status = +$LISTGET(canned, 1)
        If status = 0 Quit $$$ERROR($$$HttpRequestConnect, "the test FHIR server (no answer)")
        Set answer = {"status": (status), "headers": {}, "body": ($LISTGET(canned, 5))}
        Do:$LISTGET(canned, 2)'="" answer.headers.%Set("Content-Type", $LISTGET(canned, 2))
        Do:$LISTGET(canned, 3)'="" answer.headers.%Set("ETag", $LISTGET(canned, 3))
        Do:$LISTGET(canned, 4)'="" answer.headers.%Set("Location", $LISTGET(canned, 4))
    } Else {
        Set answer = ##class(FHIRFacade.Service).Handle({"method": (verb), "path": ($PIECE(path, "?", 1)), "query": ($PIECE(path, "?", 2, *)), "headers": (headers), "body": (body), "base": (..Base)})
    }
    Set pHttpResponse = ##class(%Net.HttpResponse).%New()
    Set pHttpResponse.StatusCode = answer.status
    Set pHttpResponse.ReasonPhrase = ..Reason(answer.status)
    Set pHttpResponse.StatusLine = "HTTP/1.1 " _ answer.status _ " " _ pHttpResponse.ReasonPhrase
    Set iter = answer.headers.%GetIterator()
    While iter.%GetNext(.name, .value) {
        Set pHttpResponse.Headers($ZCONVERT(name, "U")) = value
        Set:$ZCONVERT(name, "U")="CONTENT-TYPE" pHttpResponse.ContentType = value
    }
    Set stream = ##class(%Stream.GlobalBinary).%New(), n = ..Requests
    Set ..Bound(n) = ""
    If $ISOBJECT($GET(pHttpRequest)) && $ISOBJECT(pHttpRequest.ResponseStream) {
        Set stream = pHttpRequest.ResponseStream
        If stream.%IsA("Shutter.FHIR.BoundedStream") Set ..Bound(n) = stream.Limit
    }
    Set bytes = $ZCONVERT(answer.body, "O", "UTF8"), ..Handed(n) = 0, refused = ""
    If +$GET(..Slow(verb, path)) > 0 Hang ..Slow(verb, path)
    Try {
        For i = 1:4000:$LENGTH(bytes) {
            Set chunk = $EXTRACT(bytes, i, i + 3999)
            $$$ThrowOnError(stream.Write(chunk))
            Set ..Handed(n) = ..Handed(n) + $LENGTH(chunk)
        }
    } Catch ex {
        Set refused = ex.DisplayString()
    }
    Do stream.Rewind()
    Set pHttpResponse.Data = stream
    If refused '= "" Quit $$$ERROR($$$ObjectScriptError, refused)
    If answer.status '?1"2"2N Quit $$$ERROR($$$EnsErrHTTPStatus, pHttpResponse.StatusCode, pHttpResponse.StatusLine)
    Quit $$$OK
}

/// A request's body as characters: read as UTF-8 when it is UTF-8 bytes (what a sender with
/// <code>WriteRawMode</code> writes), and as it stands when it already holds characters.
ClassMethod Characters(body As %String) As %String
{
    Quit:body="" ""
    Quit:$ZISWIDE(body) body
    Set text = $ZCONVERT(body, "I", "UTF8")
    Quit $SELECT($ZCONVERT(text, "O", "UTF8") = body: text, 1: body)
}

ClassMethod Reason(status As %Integer) As %String [ Private ]
{
    Quit $CASE(status, 200: "OK", 201: "Created", 204: "No Content", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 410: "Gone", 412: "Precondition Failed", 500: "Internal Server Error", 503: "Service Unavailable", : "Error")
}

}
