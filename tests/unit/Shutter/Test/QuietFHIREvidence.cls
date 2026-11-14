/// The evidence collector with its send to FHIR Receiver replaced by a call, for tests that drive it outside the
/// production: the reads go straight to <property>Reader</property>'s OnRead, an instance of the real operation whose
/// adapter the test chose (Shutter.Test.FakeFhir). It is never added to a production.
Class Shutter.Test.QuietFHIREvidence Extends Shutter.Operation.Evidence
{

/// The operation that makes the reads.
Property Reader As Shutter.Operation.FHIRReceiver;

/// When not empty the call fails with this text, as a send to an item that is not there does.
Property Fails As %String(MAXLEN = "");

/// How many times the collector asked for the reads.
Property Calls As %Integer [ InitialExpression = 0 ];

Method FHIRReadParts(read As Shutter.Msg.FHIRRead, Output result As Shutter.Msg.FHIRReadResult) As %Status
{
    Set ..Calls = ..Calls + 1
    If ..Fails '= "" Quit $$$ERROR($$$GeneralError, ..Fails)
    Quit ..Reader.OnRead(read, .result)
}

}
