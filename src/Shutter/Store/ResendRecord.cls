/// The ledger of Shutter's own resends of a receiver's failed messages through the engine: one row per message of an
/// approved set, written by the sender before and after each call. This release has the table and its readers and no
/// writer: the sender is a later tier's. PatientCheck reads NewHeaderId so that a run never counts its own clones as newer
/// messages; a hand resend's clone has no row, and counts.
Class Shutter.Store.ResendRecord Extends %Persistent
{

/// The approved set this row belongs to: the outage's run, one approval.
Property RunId As %String(MAXLEN = 64) [ Required ];

Index RunIdx On RunId;

/// The message's place in the approved order, from 1.
Property Position As %Integer;

/// The outage the set came from.
Property OutageId As %String(MAXLEN = 32);

/// The namespace of the production that holds the messages.
Property Namespace As %String(MAXLEN = 64) [ Required ];

/// The operation item the messages go to.
Property Item As %String(MAXLEN = 128) [ Required ];

/// The header resent: the origin, or Shutter's own earlier clone standing in its place.
Property OriginHeaderId As %String(MAXLEN = 40) [ Required ];

/// The header the engine made for the resend, once the call returned it.
Property NewHeaderId As %String(MAXLEN = 40);

Index NewHeaderIdx On (Namespace, NewHeaderId);

/// The case of the message, when it has one.
Property CaseId As %String(MAXLEN = 32);

/// sending (before the call), completed, failed (the new header did not end Completed), closed_as_present (the receiver
/// already held it, so it was not sent), handled_by_hand (a person resent or re-entered it), stopped (not sent: the run
/// stopped before it) or unknown (a restart mid-call).
Property State As %String(MAXLEN = 24, VALUELIST = ",sending,completed,failed,closed_as_present,handled_by_hand,stopped,unknown") [ InitialExpression = "sending" ];

/// SHA-256 of the stored body before the call, hex.
Property DigestBefore As %String(MAXLEN = 64);

/// Whether the new header's body is the stored body unchanged.
Property SameBody As %Boolean;

/// The digest of the approved set, which the approval names.
Property SetDigest As %String(MAXLEN = 64);

/// The approval and the person who gave it.
Property ApprovalId As %String(MAXLEN = 64);

Property ApprovedBy As %String(MAXLEN = 128);

/// The operation's settings as read before the first send, which the approval binds: a change stops the run.
Property DefCharEncoding As %String(MAXLEN = 64);

Property IPAddress As %String(MAXLEN = 256);

Property Port As %String(MAXLEN = 16);

/// UTC, ISO 8601.
Property StartedAt As %String(MAXLEN = 30);

Property EndedAt As %String(MAXLEN = 30);

/// What happened, in words, for the case and the outage.
Property Words As %String(MAXLEN = 1000);

/// Whether <var>headerId</var> in <var>ns</var> is a clone one of Shutter's runs made.
ClassMethod IsOwnClone(ns As %String, headerId As %String) As %Boolean
{
    Quit:headerId="" 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.ResendRecord WHERE Namespace = :ns AND NewHeaderId = :headerId)
    Quit (SQLCODE = 0) && (n > 0)
}

Storage Default
{
<Data name="ResendRecordDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>RunId</Value>
</Value>
<Value name="3">
<Value>Position</Value>
</Value>
<Value name="4">
<Value>OutageId</Value>
</Value>
<Value name="5">
<Value>Namespace</Value>
</Value>
<Value name="6">
<Value>Item</Value>
</Value>
<Value name="7">
<Value>OriginHeaderId</Value>
</Value>
<Value name="8">
<Value>NewHeaderId</Value>
</Value>
<Value name="9">
<Value>CaseId</Value>
</Value>
<Value name="10">
<Value>State</Value>
</Value>
<Value name="11">
<Value>DigestBefore</Value>
</Value>
<Value name="12">
<Value>SameBody</Value>
</Value>
<Value name="13">
<Value>SetDigest</Value>
</Value>
<Value name="14">
<Value>ApprovalId</Value>
</Value>
<Value name="15">
<Value>ApprovedBy</Value>
</Value>
<Value name="16">
<Value>DefCharEncoding</Value>
</Value>
<Value name="17">
<Value>IPAddress</Value>
</Value>
<Value name="18">
<Value>Port</Value>
</Value>
<Value name="19">
<Value>StartedAt</Value>
</Value>
<Value name="20">
<Value>EndedAt</Value>
</Value>
<Value name="21">
<Value>Words</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.ResendRecordD</DataLocation>
<DefaultData>ResendRecordDefaultData</DefaultData>
<IdLocation>^Shutter.Store.ResendRecordD</IdLocation>
<IndexLocation>^Shutter.Store.ResendRecordI</IndexLocation>
<StreamLocation>^Shutter.Store.ResendRecordS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
