/// A site's subclass of the stock HL7 TCP operation that decides for itself what a reply means (Shutter.Test.EngineScope).
Class Shutter.Test.ScopeTcpReply Extends EnsLib.HL7.Operation.TCPOperation
{

Method OnGetReplyAction(pRequest As EnsLib.HL7.Message, Output pResponse As EnsLib.HL7.Message, ByRef pSC As %Status) As %String
{
    Quit "C"
}

}
