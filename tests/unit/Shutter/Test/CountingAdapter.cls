/// A connector adapter that sends nothing and counts: each call is one request that would have reached the wire.
Class Shutter.Test.CountingAdapter Extends EnsLib.HTTP.OutboundAdapter
{

/// What the fake receiver answers: an HTTP status, or 0 for a request nobody answered.
ClassMethod Answer(status As %Integer = 200, json As %String = "{""rehearsal"":true,""would_apply"":true}")
{
    Set ^Shutter.TestWire("answer") = $LISTBUILD(status, json)
}

ClassMethod Clear()
{
    Kill ^Shutter.TestWire
}

ClassMethod Count(verb As %String = "POST") As %Integer
{
    Quit +$GET(^Shutter.TestWire("count", verb))
}

Method SendFormDataArray(Output pHttpResponse As %Net.HttpResponse, pOp As %String, pHttpRequest As %Net.HttpRequest, pFormVarNames As %String, ByRef pData, pURL As %String) As %Status
{
    Set n = $INCREMENT(^Shutter.TestWire("count", $ZCONVERT(pOp, "U")))
    Set answer = $GET(^Shutter.TestWire("answer"), $LISTBUILD(200, "{}"))
    If $LIST(answer, 1) = 0 {
        Set pHttpResponse = ""
        Quit $$$ERROR(5922)
    }
    Set pHttpResponse = ##class(%Net.HttpResponse).%New()
    Set pHttpResponse.StatusCode = $LIST(answer, 1)
    Set stream = ##class(%Stream.GlobalCharacter).%New()
    Do stream.Write($LIST(answer, 2))
    Set pHttpResponse.Data = stream
    Quit $$$OK
}

}
