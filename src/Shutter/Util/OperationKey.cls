/// The operation key identifies a business operation, not a message (docs/CONTRACTS.md, section 2):
/// <source_system>^<patient_id_authority>^<patient_id>^<encounter_id>^<event>^<event_time>.
/// The same transfer resent under a new message control id has the same key. The trigger table (EventForTrigger)
/// gives the event word of each ADT trigger, and DeliveryOf says what the feed does with the word: deliver it, index
/// it only, treat it as a cancel or as a merge.
Class Shutter.Util.OperationKey Extends %RegisteredObject
{

/// A field of the first segment of a name, wherever the structure puts it: the plain path (PID:3.1) resolves a
/// top-level segment; inside a group (the PATIENT group of ADT_A39, a merge) the segment is found by name and
/// read with the field path (3.1). Returns "" when neither finds it.
ClassMethod Value(message As EnsLib.HL7.Message, segment As %String, path As %String) As %String
{
    Set value = message.GetValueAt(segment _ ":" _ path)
    If value '= "" Quit value
    Set index = ""
    Set seg = message.FindSegment(segment, .index)
    If '$ISOBJECT(seg) Quit ""
    Quit seg.GetValueAt(path)
}

/// Build a key from its parts. The event is one of the words of EventForTrigger; the time is ISO 8601 UTC.
ClassMethod FromParts(sourceSystem As %String, authority As %String, patientId As %String, encounterId As %String, event As %String, eventTime As %String) As %String
{
    Quit sourceSystem _ "^" _ authority _ "^" _ patientId _ "^" _ encounterId _ "^" _ event _ "^" _ eventTime
}

/// The patient identifier and its assigning authority: the PID-3 repetition typed MR (PID-3.5) whichever it is,
/// else the first repetition (D2). Every reader of PID-3 uses this, so one patient gets one identifier. typeCode is
/// the chosen repetition's PID-3.5.
ClassMethod PatientIdentifier(message As EnsLib.HL7.Message, Output authority As %String, Output typeCode As %String) As %String
{
    Set reps = +..Value(message, "PID", "3(*)"), pick = 1
    For r = 1:1:reps { If $ZCONVERT(..Value(message, "PID", "3(" _ r _ ").5"), "U") = "MR" Set pick = r Quit }
    Set authority = ..Value(message, "PID", "3(" _ pick _ ").4.1")
    If authority = "" Set authority = ..Value(message, "PID", "3(" _ pick _ ").4")
    Set typeCode = ..Value(message, "PID", "3(" _ pick _ ").5")
    Quit ..Value(message, "PID", "3(" _ pick _ ").1")
}

/// The downstream operation (as a dynamic object with the contract's field names) for an HL7 ADT message,
/// with its operation key and payload digest filled in. Returns "" with an error status when the trigger is not in
/// the table or a required field is missing.
/// PV1-19 is required for the events that are delivered or cancelled. For the indexed-only events (register,
/// preadmit, person_add, person_update) and a merge, the key's encounter piece is PV1-19 when present, else the
/// literal "-", never empty: the timeline returns nothing for "-" and the evidence skips the encounter reads.
/// An A04 whose PV1-2 is I and whose PV1-3.1 names a bed is an admit, not a register. The ward is carried for admit
/// and transfer only, as before.
/// A merge (A40) also carries prior_patient_id and prior_patient_id_authority (MRG-1, the repetition typed MR, else
/// the first), prior_encounter_id (MRG-5) and merge_groups, the number of MRG segments (one per PATIENT group; the
/// prior fields are the first group's). They sit outside the canonical payload (CONTRACTS 1.6), so the digest is the
/// same eight-key form as before.
ClassMethod FromHL7(message As EnsLib.HL7.Message, Output sc As %Status) As %DynamicObject
{
    Set sc = $$$OK
    Try {
        Set sourceSystem = message.GetValueAt("MSH:3.1")
        Set trigger = message.GetValueAt("MSH:9.2")
        Set controlId = message.GetValueAt("MSH:10")
        Set patientId = ..PatientIdentifier(message, .authority)
        Set encounterId = ..Value(message, "PV1", "19.1")
        Set ward = ..Value(message, "PV1", "3.1")
        Set bed = ..BedOf(..Value(message, "PV1", "3.2"), ..Value(message, "PV1", "3.3"))
        Set eventTime = message.GetValueAt("EVN:6.1")
        If eventTime = "" Set eventTime = message.GetValueAt("EVN:2.1")
        Set event = ..EventForTrigger(trigger)
        If event = "" Set sc = $$$ERROR($$$GeneralError, "Unsupported ADT trigger: " _ trigger) Quit
        // An A04 for an inpatient with a bed is an admission the receiver can take; any other registration is indexed only.
        If (event = "register") && ($ZCONVERT(..Value(message, "PV1", "2"), "U") = "I") && (ward '= "") Set event = "admit"
        Set how = ..DeliveryOf(event)
        Set missing = ""
        If sourceSystem = "" Set missing = "MSH-3 sending application"
        If patientId = "" Set missing = "PID-3 patient identifier"
        If authority = "" Set missing = "PID-3 assigning authority"
        If (encounterId = "") && ((how = "deliver") || (how = "cancel")) Set missing = "PV1-19 visit number"
        If eventTime = "" Set missing = "EVN-6 or EVN-2 event time"
        If missing '= "" Set sc = $$$ERROR($$$GeneralError, "Missing field for the operation key: " _ missing) Quit
        // A registration, a person update or a merge may carry no visit number: the piece is "-", never empty.
        If encounterId = "" Set encounterId = "-"
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
        // The bed (PV1-3's bed component, with its room) travels beside the canonical payload (CONTRACTS 1.24: not in the digest), for an
        // admission or a transfer only; a placement without one is at ward level.
        If ((event = "admit") || (event = "transfer")) && (bed '= "") { Set op."bed" = $EXTRACT(bed, 1, 64) } Else { Do op.%Set("bed", "", "null") }
        Set op."event_time" = isoTime
        Set op."source_system" = sourceSystem
        Set op."source_message_id" = controlId
        Set op."payload_digest" = ##class(Shutter.Util.Digest).WardPayloadDigest(op)
        If event = "merge" Do ..MergeFields(message, op)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) Quit ""
    Quit op
}

/// The prior record of a merge (A40) from the message's MRG segments, added to the operation: prior_patient_id and
/// prior_patient_id_authority (MRG-1, the repetition typed MR by CX.5, else the first), prior_encounter_id (MRG-5),
/// both from the first MRG, and merge_groups, how many MRG segments the message has (one per PATIENT group).
/// The bed of a PL location (PV1-3), named within its ward: the bed component (PV1-3.3), prefixed by the room (PV1-3.2) when
/// one is given, as BAY1-01, since beds are numbered within a bay; "" when the location names no bed (a ward or bay level
/// placement), whatever the room says. At most 64 characters.
ClassMethod BedOf(room As %String, bed As %String) As %String
{
    Set room = $ZSTRIP(room, "<>W"), bed = $ZSTRIP(bed, "<>W")
    If bed = "" Quit ""
    Quit $EXTRACT($SELECT(room = "": bed, 1: room _ "-" _ bed), 1, 64)
}

ClassMethod MergeFields(message As EnsLib.HL7.Message, op As %DynamicObject)
{
    Set index = "", groups = 0
    For {
        Set seg = message.FindSegment("MRG", .index)
        Quit:((index = "") || '$ISOBJECT(seg))
        Set groups = groups + 1
        If groups = 1 {
            Set reps = +seg.GetValueAt("1(*)"), pick = 1
            For r = 1:1:reps { If $ZCONVERT(seg.GetValueAt("1(" _ r _ ").5"), "U") = "MR" Set pick = r Quit }
            Set priorAuthority = seg.GetValueAt("1(" _ pick _ ").4.1")
            If priorAuthority = "" Set priorAuthority = seg.GetValueAt("1(" _ pick _ ").4")
            Set op."prior_patient_id" = seg.GetValueAt("1(" _ pick _ ").1")
            Set op."prior_patient_id_authority" = priorAuthority
            Set op."prior_encounter_id" = seg.GetValueAt("5.1")
        }
    }
    Set op."merge_groups" = groups
}

/// The operation record of a message that does not map: what the message says, with a key of its own
/// (UNMAPPED^<header id>), so the case can hold it. headerId is the message's Ens.MessageHeader id in this namespace:
/// the feed's own (Shutter.Process.ADTToWard) or the intake's stored copy (Shutter.Process.Intake).
ClassMethod Unmapped(request As EnsLib.HL7.Message, headerId As %String) As %DynamicObject
{
    Set op = {}
    Set op."operation_key" = "UNMAPPED^" _ headerId
    Set op."encounter_id" = ..Value(request, "PV1", "19.1")
    Set op."patient_id" = ..PatientIdentifier(request, .authority)
    Set op."patient_id_authority" = authority
    Set trigger = request.GetValueAt("MSH:9.2")
    Set op."event" = $SELECT(trigger = "": "", 1: trigger)
    Set ward = ..Value(request, "PV1", "3.1")
    If ward '= "" { Set op."ward" = ward } Else { Do op.%Set("ward", "", "null") }
    Set bed = ..BedOf(..Value(request, "PV1", "3.2"), ..Value(request, "PV1", "3.3"))
    If bed '= "" { Set op."bed" = $EXTRACT(bed, 1, 64) } Else { Do op.%Set("bed", "", "null") }
    Set raw = request.GetValueAt("EVN:6.1")
    If raw = "" Set raw = request.GetValueAt("EVN:2.1")
    If raw = "" Set raw = request.GetValueAt("MSH:7.1")
    Set when = ##class(Shutter.Util.Time).FromHL7(raw)
    Set op."event_time" = $SELECT(when = "": ##class(Shutter.Util.Time).NowUTC(), 1: when)
    Set op."source_system" = request.GetValueAt("MSH:3.1")
    Set op."source_message_id" = request.GetValueAt("MSH:10")
    Set op."payload_digest" = ""
    Quit op
}

/// The operation of a message whose schema category is not loaded here (v1.34, the hold): read as standard 2.5.1 for the
/// case's identity (Shutter.Util.Schemas.Canonical), else unmapped. sc says whether the canonical reading mapped.
ClassMethod FromCanonical(request As EnsLib.HL7.Message, headerId As %String, Output sc As %Status) As %DynamicObject
{
    Set sc = $$$OK
    Set copy = ##class(Shutter.Util.Schemas).Canonical(request)
    If '$ISOBJECT(copy) Set sc = $$$ERROR($$$GeneralError, "The message has no 2.5.1 structure to read it by") Quit ..Unmapped(request, headerId)
    Set op = ..FromHL7(copy, .sc)
    If $$$ISERR(sc) || '$ISOBJECT($GET(op)) Quit ..Unmapped(copy, headerId)
    Quit op
}

/// The trigger table (CONTRACTS 2): the event word for an ADT trigger, "" for anything else.
/// A01 admit, A02 transfer, A03 discharge, A04 register, A05 preadmit, A06 and A07 update (a change of patient
/// class), A08 update, A11 cancel_admit, A12 cancel_transfer, A13 cancel_discharge, A28 person_add, A31
/// person_update, A40 merge. FromHL7 turns a register with PV1-2 I and a bed into an admit.
ClassMethod EventForTrigger(trigger As %String) As %String
{
    Set trigger = $ZCONVERT(trigger, "U")
    Quit $CASE(trigger, "A01": "admit", "A02": "transfer", "A03": "discharge", "A04": "register", "A05": "preadmit", "A06": "update", "A07": "update", "A08": "update", "A11": "cancel_admit", "A12": "cancel_transfer", "A13": "cancel_discharge", "A28": "person_add", "A31": "person_update", "A40": "merge", : "")
}

/// What the feed does with an event word: "deliver" (admit, transfer, discharge, update go to the receiver),
/// "index" (register, preadmit, person_add, person_update are recorded by the index and not delivered), "cancel"
/// (the three cancel words: delivered only to a receiver whose profile entry says cancels), "merge" (delivered only
/// when the site allows merges and the receiver takes them), "" for a word not in the table.
ClassMethod DeliveryOf(event As %String) As %String
{
    Quit $CASE(event, "admit": "deliver", "transfer": "deliver", "discharge": "deliver", "update": "deliver", "register": "index", "preadmit": "index", "person_add": "index", "person_update": "index", "cancel_admit": "cancel", "cancel_transfer": "cancel", "cancel_discharge": "cancel", "merge": "merge", : "")
}

}
