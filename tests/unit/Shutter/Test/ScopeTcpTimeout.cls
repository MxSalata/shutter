/// A site's subclass of the stock HL7 TCP operation with another FailureTimeout default (Shutter.Test.EngineScope).
Class Shutter.Test.ScopeTcpTimeout Extends EnsLib.HL7.Operation.TCPOperation
{

Property FailureTimeout As %Numeric(MINVAL = -1) [ InitialExpression = 0 ];

}
