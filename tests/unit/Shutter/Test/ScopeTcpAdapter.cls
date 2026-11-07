/// A site's subclass of the stock HL7 TCP operation on another adapter, which does the sending and holds GetReply's
/// default (Shutter.Test.EngineScope).
Class Shutter.Test.ScopeTcpAdapter Extends EnsLib.HL7.Operation.TCPOperation
{

Parameter ADAPTER = "EnsLib.TCP.OutboundAdapter";

}
