/// The operation key identifies a business operation, not a message (docs/CONTRACTS.md, section 2):
/// <source_system>^<patient_id_authority>^<patient_id>^<encounter_id>^<event>^<event_time>.
/// The same transfer resent under a new message control id has the same key.
Class Shutter.Util.OperationKey Extends %RegisteredObject
{

/// Build a key from its parts. The event is one of admit, transfer, discharge, update; the time
/// is ISO 8601 UTC.
ClassMethod FromParts(sourceSystem As %String, authority As %String, patientId As %String, encounterId As %String, event As %String, eventTime As %String) As %String
{
    Quit sourceSystem _ "^" _ authority _ "^" _ patientId _ "^" _ encounterId _ "^" _ event _ "^" _ eventTime
}

/// The ward operation (as a dynamic object with the contract's field names) for an HL7 ADT message,
/// with its operation key and payload digest filled in. Returns "" with an error status when a
/// required field is missing.
ClassMethod FromHL7(message As EnsLib.HL7.Message, Output sc As %Status) As %DynamicObject
{
    Set sc = $$$OK
    Try {
        Set sourceSystem = message.GetValueAt("MSH:3.1")
        Set trigger = message.GetValueAt("MSH:9.2")
        Set controlId = message.GetValueAt("MSH:10")
        // The medical record number (PID-3.5 = MR) whichever repetition carries it, else the first repetition (D2).
        Set reps = +message.GetValueAt("PID:3(*)"), pick = 1
        For r = 1:1:reps { If $ZCONVERT(message.GetValueAt("PID:3(" _ r _ ").5"), "U") = "MR" Set pick = r Quit }
        Set patientId = message.GetValueAt("PID:3(" _ pick _ ").1")
        Set authority = message.GetValueAt("PID:3(" _ pick _ ").4.1")
        If authority = "" Set authority = message.GetValueAt("PID:3(" _ pick _ ").4")
        Set encounterId = message.GetValueAt("PV1:19.1")
        Set ward = message.GetValueAt("PV1:3.1")
        Set eventTime = message.GetValueAt("EVN:6.1")
        If eventTime = "" Set eventTime = message.GetValueAt("EVN:2.1")
        Set event = ..EventForTrigger(trigger)
        If event = "" Set sc = $$$ERROR($$$GeneralError, "Unsupported ADT trigger: " _ trigger) Quit
        Set missing = ""
        If sourceSystem = "" Set missing = "MSH-3 sending application"
        If patientId = "" Set missing = "PID-3 patient identifier"
        If authority = "" Set missing = "PID-3 assigning authority"
        If encounterId = "" Set missing = "PV1-19 visit number"
        If eventTime = "" Set missing = "EVN-6 or EVN-2 event time"
        If missing '= "" Set sc = $$$ERROR($$$GeneralError, "Missing field for the operation key: " _ missing) Quit
        Set isoTime = ##class(Shutter.Util.Time).FromHL7(eventTime)
        Set op = {}
        Set op."operation_key" = ..FromParts(sourceSystem, authority, patientId, encounterId, event, isoTime)
        Set op."encounter_id" = encounterId
        Set op."patient_id" = patientId
        Set op."patient_id_authority" = authority
        Set op."event" = event
        If (event = "admit") || (event = "transfer") {
            Set op."ward" = ward
        } Else {
            Do op.%Set("ward", "", "null")
        }
        Set op."event_time" = isoTime
        Set op."source_system" = sourceSystem
        Set op."source_message_id" = controlId
        Set op."payload_digest" = ##class(Shutter.Util.Digest).WardPayloadDigest(op)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) Quit ""
    Quit op
}

/// admit, transfer, discharge or update for an ADT trigger event; "" for anything else.
ClassMethod EventForTrigger(trigger As %String) As %String
{
    Set trigger = $ZCONVERT(trigger, "U")
    Quit $CASE(trigger, "A01": "admit", "A02": "transfer", "A03": "discharge", "A08": "update", : "")
}

}
