/// An HTTP adapter that answers from a table, for tests that drive a connector, the verifier or the evidence collector with
/// no receiver: <code>Set http.Answers("/receipts/") = $LISTBUILD(200, "...")</code>, the first path piece found in the
/// address answering. Anything else is a 404 with an empty body.
Class Shutter.Test.FakeHttp Extends EnsLib.HTTP.OutboundAdapter
{

Property Answers As %String [ MultiDimensional ];

Method SendFormDataArray(Output pHttpResponse As %Net.HttpResponse, pOp As %String, pHttpRequest As %Net.HttpRequest, pFormVarNames As %String = "", ByRef pData, pURL As %String = "") As %Status
{
    Set pHttpResponse = ##class(%Net.HttpResponse).%New()
    Set pHttpResponse.StatusCode = 404
    Set body = ""
    Set piece = ""
    For {
        Set piece = $ORDER(..Answers(piece))
        Quit:piece=""
        If pURL [ piece {
            Set pHttpResponse.StatusCode = $LIST(..Answers(piece), 1)
            Set body = $LIST(..Answers(piece), 2)
            Quit
        }
    }
    Set stream = ##class(%Stream.GlobalCharacter).%New()
    Do stream.Write(body)
    Do stream.Rewind()
    Set pHttpResponse.Data = stream
    Quit $$$OK
}

}
