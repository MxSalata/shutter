/// The API mimic's endpoint, at /shutter-mock (Shutter.Mock.Setup creates the web application): an OpenAI-compatible
/// chat completions API that answers the live runner's model calls from the recordings or the catalogue
/// (Shutter.Mock.Turns), so AI Hub's own agent loop, tools, policies and session accounting run with no model and no
/// cost. A test fixture: in tests/mock, outside both IPM modules and the image. It answers loopback callers only,
/// and logs one line per call in ^Shutter.MockLog.
Class Shutter.Mock.API Extends %CSP.REST
{

/// No session outlives its request, so a burst of calls holds no licence beyond the calls themselves.
Parameter UseSession As BOOLEAN = 0;

Parameter HandleCorsRequest = 0;

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "utf-8";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
<Route Url="/v1/models" Method="GET" Call="Models"/>
<Route Url="/v1/models/:id" Method="GET" Call="Model"/>
<Route Url="/v1/chat/completions" Method="POST" Call="Chat"/>
<Route Url="/(.*)" Method="GET" Call="Other"/>
<Route Url="/(.*)" Method="POST" Call="Other"/>
</Routes>
}

/// Loopback callers only: the live runner calls the mimic from inside the instance.
ClassMethod OnPreDispatch(pUrl As %String, pMethod As %String, ByRef pContinue As %Boolean) As %Status
{
    Set addr = $GET(%request.CgiEnvs("REMOTE_ADDR"))
    If (addr = "127.0.0.1") || (addr = "::1") || ($EXTRACT(addr, 1, 4) = "127.") || (addr = "::ffff:127.0.0.1") Quit $$$OK
    Set pContinue = 0
    Do ..Log(pUrl, pMethod, 403, {"note": ("not a loopback caller: " _ addr)})
    Quit ..Fail(403, "The API mimic answers callers on this instance only", "forbidden")
}

/// GET /v1/models: the one model the mimic answers as (what AI Hub's TestConfiguration looks for).
ClassMethod Models() As %Status
{
    Set data = []
    Do data.%Push(..ModelObject(..WireModel()))
    Do ..Token(.scheme)
    Do ..Log("/v1/models", "GET", 200, {"scheme": (scheme)})
    Quit ..Json({"object": "list", "data": (data)})
}

ClassMethod Model(id As %String) As %Status
{
    Do ..Log("/v1/models/" _ id, "GET", 200, {})
    Quit ..Json(..ModelObject(id))
}

/// POST /v1/chat/completions: one model turn, as JSON or, when the request asks to stream, as server-sent events.
ClassMethod Chat() As %Status
{
    Set ctx = ##class(Shutter.Mock.Turns).Decode(..Token(.scheme))
    Set text = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set info = {"scheme": (scheme), "size": ($LENGTH(text))}
    Try {
        Set request = ##class(%DynamicObject).%FromJSON(text)
    } Catch ex {
        Set request = ""
    }
    If '$ISOBJECT(request) {
        Do ..Log("/v1/chat/completions", "POST", 400, info, text)
        Quit ..Fail(400, "The body is not a JSON object", "invalid_request")
    }
    Set stream = ##class(Shutter.Util.Json).Bool(request, "stream")
    Set info.stream = stream
    Set out = ##class(Shutter.Mock.Turns).Answer(ctx, request, $LENGTH(text), .log)
    Set iter = log.%GetIterator()
    While iter.%GetNext(.k, .v) { Do info.%Set(k, v) }
    Do ..Log("/v1/chat/completions", "POST", out.status, info, text)
    If out.status '= 200 Quit ..Json(out.body, "400 Bad Request")
    If stream Quit ..Events(out.body)
    Quit ..Json(out.body)
}

/// Any other path: logged, so a wire format the mimic does not serve shows up, and answered 404.
ClassMethod Other(path As %String) As %Status
{
    Set text = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Do ..Log("/" _ path, %request.Method, 404, {"note": "no such route"}, text)
    Quit ..Fail(404, "The API mimic has no route /" _ path, "not_found")
}

/// A completion as server-sent events: one chunk with the whole message, one with the finish reason and the usage,
/// then [DONE].
ClassMethod Events(body As %DynamicObject) As %Status
{
    Set %response.ContentType = "text/event-stream"
    Set choice = body.choices.%Get(0), msg = choice.message
    Set delta = {"role": "assistant"}
    If msg.%GetTypeOf("content") = "string" Set delta.content = msg.content
    Set calls = msg.%Get("tool_calls")
    If $ISOBJECT(calls) {
        Set out = []
        Set iter = calls.%GetIterator()
        While iter.%GetNext(.j, .c) { Do out.%Push({"index": (j), "id": (c.id), "type": "function", "function": (c.function)}) }
        Set delta."tool_calls" = out
    }
    Set first = {"id": (body.id), "object": "chat.completion.chunk", "created": (body.created), "model": (body.model)}
    Set c1 = {"index": 0, "delta": (delta)}
    Do c1.%Set("finish_reason", "", "null")
    Set first.choices = [(c1)]
    Set last = {"id": (body.id), "object": "chat.completion.chunk", "created": (body.created), "model": (body.model)}
    Set last.choices = [{"index": 0, "delta": {}, "finish_reason": (choice."finish_reason")}]
    Set last.usage = body.usage
    Write "data: ", first.%ToJSON(), $CHAR(10, 10)
    Write "data: ", last.%ToJSON(), $CHAR(10, 10)
    Write "data: [DONE]", $CHAR(10, 10)
    Quit $$$OK
}

/// The bearer token of the call, and its scheme ("bearer", another, or "" when there is no Authorization header).
ClassMethod Token(Output scheme As %String) As %String
{
    Set auth = $ZSTRIP($GET(%request.CgiEnvs("HTTP_AUTHORIZATION")), "<>W")
    Set scheme = $ZCONVERT($PIECE(auth, " "), "L")
    Quit $SELECT(scheme = "bearer": $ZSTRIP($PIECE(auth, " ", 2, *), "<>W"), 1: "")
}

/// The model id the mimic answers as: the one Shutter.Mock.Setup Enable configured.
ClassMethod WireModel() As %String
{
    Quit $GET(^Shutter.Config("aihub", "mockModel"), "mock")
}

ClassMethod ModelObject(id As %String) As %DynamicObject
{
    Quit {"id": (id), "object": "model", "created": 0, "owned_by": "shutter-mock"}
}

/// One line of the call log, ^Shutter.MockLog(n): the time, the path, the status and what the answer was made from.
/// With ^Shutter.Config("aihub","mockDebug") set, the body is kept too, in ^Shutter.MockLog(n,"body").
ClassMethod Log(path As %String, method As %String, status As %Integer, info As %DynamicObject, body As %String = "")
{
    Try {
        Set line = {"at": (##class(Shutter.Util.Time).NowUTC()), "method": (method), "path": (path), "status": (+status)}
        Set iter = info.%GetIterator()
        While iter.%GetNext(.k, .v) { Do line.%Set(k, v) }
        Set n = $INCREMENT(^Shutter.MockLog)
        Set ^Shutter.MockLog(n) = line.%ToJSON()
        If $GET(^Shutter.Config("aihub", "mockDebug")) && (body '= "") Set ^Shutter.MockLog(n, "body") = $EXTRACT(body, 1, 3000000)
    } Catch ex {
    }
}

ClassMethod Json(obj As %DynamicAbstractObject, status As %String = "200 OK") As %Status
{
    Set %response.Status = status
    Set %response.ContentType = "application/json"
    Do obj.%ToJSON()
    Quit $$$OK
}

/// An error in the shape OpenAI's API answers with. The message never says denied, timeout or loop, which the live
/// runner reads as statuses of their own.
ClassMethod Fail(status As %Integer, message As %String, code As %String) As %Status
{
    Set text = $CASE(status, 403: "403 Forbidden", 404: "404 Not Found", : "400 Bad Request")
    Quit ..Json({"error": {"message": ("[mock] " _ message), "type": "invalid_request_error", "code": (code)}}, text)
}

}
