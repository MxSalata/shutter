/// A site's subclass of the stock HL7 TCP operation that adds a setting of its own and touches nothing about delivery
/// (Shutter.Test.EngineScope).
Class Shutter.Test.ScopeTcpPlain Extends EnsLib.HL7.Operation.TCPOperation
{

Property SiteNote As %String(MAXLEN = 64);

Parameter SETTINGS = "SiteNote:Additional";

}
