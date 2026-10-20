/// The store for the intake's copy of a failed message: an adapterless operation that takes the EnsLib.HL7.Message
/// the Case Intake process sends it and answers with the message's id. It writes nothing itself: the point is the
/// Ens.MessageHeader the production wrote for the send, which gives the copy a header id in this namespace, so the
/// evidence, the model view and the index read it as they read the feed's own messages.
Class Shutter.Operation.IntakeStore Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnStore(request As EnsLib.HL7.Message, Output response As Ens.StringResponse) As %Status
{
    Set response = ##class(Ens.StringResponse).%New()
    Set response.StringValue = request.%Id()
    $$$TRACE("Stored the intake's copy of " _ request.Name _ " as message " _ request.%Id())
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="EnsLib.HL7.Message">
    <Method>OnStore</Method>
  </MapItem>
</MapItems>
}

}
