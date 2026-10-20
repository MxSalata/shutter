/// A downstream operation as the production sends it to the receiver (docs/CONTRACTS.md, section 1.1):
/// the same message for normal traffic, rehearsals and recovery writes. The purpose says which.
Class Shutter.Msg.WardOperation Extends Ens.Request
{

/// normal (the feed), rehearsal (a dry run from a case), recovery (an approved write from a case),
/// read (a preflight read of the encounter's current state and version; nothing is sent to write).
Property Purpose As %String(MAXLEN = 16, VALUELIST = ",normal,rehearsal,recovery,read") [ InitialExpression = "normal" ];

Property OperationKey As %String(MAXLEN = 400);

Property EncounterId As %String(MAXLEN = 100);

Property PatientId As %String(MAXLEN = 100);

Property PatientIdAuthority As %String(MAXLEN = 100);

/// admit, transfer, discharge, update; cancel_admit, cancel_transfer, cancel_discharge and merge for a receiver whose
/// profile entry says it takes them (CONTRACTS 1.1).
Property Event As %String(MAXLEN = 32);

Property Ward As %String(MAXLEN = 100);

/// ISO 8601 UTC.
Property EventTime As %String(MAXLEN = 30);

Property SourceSystem As %String(MAXLEN = 100);

Property SourceMessageId As %String(MAXLEN = 200);

Property PayloadDigest As %String(MAXLEN = 80);

/// Sent only when set: the receiver version the write is conditional on.
Property ExpectedVersion As %Integer;

Property DryRun As %Boolean [ InitialExpression = 0 ];

/// The case this operation belongs to, for rehearsals and recovery.
Property CaseId As %String(MAXLEN = 32);

/// The Ens.MessageHeader id of the HL7 message this operation came from.
Property SourceHeaderId As %String(MAXLEN = 20);

/// A merge's prior record (CONTRACTS 1.1 and 2): sent only when the event is merge, outside the payload digest (1.6).
Property PriorPatientId As %String(MAXLEN = 100);

Property PriorPatientIdAuthority As %String(MAXLEN = 100);

Property PriorEncounterId As %String(MAXLEN = 100);

/// Build from a downstream operation object (Shutter.Util.OperationKey.FromHL7, or a plan's action).
ClassMethod FromOperation(op As %DynamicObject) As Shutter.Msg.WardOperation
{
    Set m = ..%New()
    Set m.OperationKey = ##class(Shutter.Util.Json).Str(op, "operation_key")
    Set m.EncounterId = ##class(Shutter.Util.Json).Str(op, "encounter_id")
    Set m.PatientId = ##class(Shutter.Util.Json).Str(op, "patient_id")
    Set m.PatientIdAuthority = ##class(Shutter.Util.Json).Str(op, "patient_id_authority")
    Set m.Event = ##class(Shutter.Util.Json).Str(op, "event")
    Set m.Ward = ##class(Shutter.Util.Json).Str(op, "ward")
    Set m.EventTime = ##class(Shutter.Util.Json).Str(op, "event_time")
    Set m.SourceSystem = ##class(Shutter.Util.Json).Str(op, "source_system")
    Set m.SourceMessageId = ##class(Shutter.Util.Json).Str(op, "source_message_id")
    Set m.PayloadDigest = ##class(Shutter.Util.Json).Str(op, "payload_digest")
    If m.PayloadDigest = "" Set m.PayloadDigest = ##class(Shutter.Util.Digest).WardPayloadDigest(m.ToOperation())
    Set m.PriorPatientId = ##class(Shutter.Util.Json).Str(op, "prior_patient_id")
    Set m.PriorPatientIdAuthority = ##class(Shutter.Util.Json).Str(op, "prior_patient_id_authority")
    Set m.PriorEncounterId = ##class(Shutter.Util.Json).Str(op, "prior_encounter_id")
    Set ev = ##class(Shutter.Util.Json).Str(op, "expected_version")
    If ev '= "" Set m.ExpectedVersion = +ev
    Quit m
}

/// The operation as a dynamic object with the contract's field names (without the request-only
/// fields), the shape the digest is computed over.
Method ToOperation() As %DynamicObject
{
    Set op = {}
    Set op."operation_key" = ..OperationKey
    Set op."encounter_id" = ..EncounterId
    Set op."patient_id" = ..PatientId
    Set op."patient_id_authority" = ..PatientIdAuthority
    Set op."event" = ..Event
    If (..Event = "admit") || (..Event = "transfer") { Set op."ward" = ..Ward } Else { Do op.%Set("ward", "", "null") }
    Set op."event_time" = ..EventTime
    Set op."source_system" = ..SourceSystem
    Set op."source_message_id" = ..SourceMessageId
    Quit op
}

/// The JSON body for POST /downstream/api/operations.
Method ToWardJSON() As %DynamicObject
{
    Set body = ..ToOperation()
    Set body."payload_digest" = ..PayloadDigest
    If ..ExpectedVersion '= "" Set body."expected_version" = ..ExpectedVersion
    If ..Event = "merge" Set body."prior_patient_id" = ..PriorPatientId, body."prior_patient_id_authority" = ..PriorPatientIdAuthority, body."prior_encounter_id" = ..PriorEncounterId
    Do body.%Set("dry_run", ..DryRun, "boolean")
    Quit body
}

Storage Default
{
<Data name="WardOperationDefaultData">
<Subscript>"WardOperation"</Subscript>
<Value name="1">
<Value>Purpose</Value>
</Value>
<Value name="2">
<Value>OperationKey</Value>
</Value>
<Value name="3">
<Value>EncounterId</Value>
</Value>
<Value name="4">
<Value>PatientId</Value>
</Value>
<Value name="5">
<Value>PatientIdAuthority</Value>
</Value>
<Value name="6">
<Value>Event</Value>
</Value>
<Value name="7">
<Value>Ward</Value>
</Value>
<Value name="8">
<Value>EventTime</Value>
</Value>
<Value name="9">
<Value>SourceSystem</Value>
</Value>
<Value name="10">
<Value>SourceMessageId</Value>
</Value>
<Value name="11">
<Value>PayloadDigest</Value>
</Value>
<Value name="12">
<Value>ExpectedVersion</Value>
</Value>
<Value name="13">
<Value>DryRun</Value>
</Value>
<Value name="14">
<Value>CaseId</Value>
</Value>
<Value name="15">
<Value>SourceHeaderId</Value>
</Value>
<Value name="16">
<Value>PriorPatientId</Value>
</Value>
<Value name="17">
<Value>PriorPatientIdAuthority</Value>
</Value>
<Value name="18">
<Value>PriorEncounterId</Value>
</Value>
</Data>
<DefaultData>WardOperationDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
