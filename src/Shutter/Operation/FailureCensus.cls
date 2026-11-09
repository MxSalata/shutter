/// Runs the failure coverage census in a production job, which may read a watched namespace where the REST caller's role need
/// not (docs/CONTRACTS.md, section 19). It takes a registered receiver and a window. An observer: it writes only its own run and
/// rows, and nothing here opens or closes a case or sends a message anywhere.
Class Shutter.Operation.FailureCensus Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnCensus(request As Shutter.Msg.CensusRequest, Output response As Shutter.Msg.CensusAnswer) As %Status
{
    Set response = ##class(Shutter.Msg.CensusAnswer).%New()
    Set sc = ##class(Shutter.Util.FailureCensus).Run(request.Receiver, request.FromUTC, request.ToUTC, request.RequestedBy, .run, .refused)
    If $ISOBJECT($GET(run)) Set response.RunId = run.RunId
    If $GET(refused) '= "" Set response.Error = refused
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc)
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.CensusRequest">
    <Method>OnCensus</Method>
  </MapItem>
</MapItems>
}

}
