/// The one action a plan may carry. The only write Shutter ever makes is to resend the case's own
/// operation unchanged, conditional on the receiver's version.
Class Shutter.Schema.PlanAction Extends (%RegisteredObject, %JSON.Adaptor)
{

/// resend (the only write), reconcile (record the receipt, write nothing) or none (superseded, more_evidence, escalate).
Property Type As %String(%JSONFIELDNAME = "type", MAXLEN = 16) [ Required ];

/// The case's own operation key, for resend and reconcile.
Property OperationKey As %String(%JSONFIELDNAME = "operation_key", MAXLEN = 400);

/// For resend: the receiver's current version of the encounter, which the write is conditional on.
Property ExpectedVersion As %Integer(%JSONFIELDNAME = "expected_version");

}
