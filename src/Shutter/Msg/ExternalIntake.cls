/// A failed delivery reported by another production (CONTRACTS 11, the REST route POST /api/shutter/intake): the HL7
/// message as text, where it came from (the namespace, the production, the route that received it and the header id
/// it has there), the receiver it was for and how the delivery failed. Shutter stores its own copy of the message and
/// opens the case through Shutter.Process.Intake; the answer is the case workflow's CaseStarted.
Class Shutter.Msg.ExternalIntake Extends Ens.Request
{

/// The namespace the failed message lives in.
Property SourceNamespace As %String(MAXLEN = 64);

/// The production that received it there.
Property SourceProduction As %String(MAXLEN = 128);

/// The production item that received it (the route), for example the HL7 service.
Property SourceRoute As %String(MAXLEN = 128);

/// The message's Ens.MessageHeader id in the source namespace.
Property OriginHeaderId As %String(MAXLEN = 40);

/// The production item the delivery went to: the receiver's name, as the site profile knows it.
Property Receiver As %String(MAXLEN = 128);

/// delivery_failed, rejected, uncertain_outcome or unmappable: the source's own judgement of the failure.
Property FailureKind As %String(MAXLEN = 32);

Property FailureText As %String(MAXLEN = 2000);

/// The receiver's answer as the source saw it: unavailable, error, uncertain, rejected, or empty when it gave none.
Property FailureOutcome As %String(MAXLEN = 32);

Property FailureHttpStatus As %Integer;

Property FailureReasonCode As %String(MAXLEN = 100);

/// The HL7 message, segments separated by carriage returns.
Property MessageText As %String(MAXLEN = "");

/// The HL7 schema category the message is parsed under; 2.5.1 when empty.
Property SchemaCategory As %String(MAXLEN = 32);

/// The investigation mode requested (board, single, rules, policy); empty takes the configured default.
Property Mode As %String(MAXLEN = 16);

}
