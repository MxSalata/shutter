/// The evidence collector: takes an immutable snapshot of what is known about a case from the
/// message store, the ward system and the production, each observation with its source and time.
/// The agents and the gate read the snapshot's summary; nothing reaches them that is not in it.
Class Interlock.Operation.Evidence Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// Seconds a live observation stays fresh.
Property FreshSeconds As %Integer [ InitialExpression = 300 ];

Parameter SETTINGS = "FreshSeconds:Evidence";

Method OnEvidenceRequest(request As Interlock.Msg.EvidenceRequest, Output response As Interlock.Msg.EvidenceResult) As %Status
{
    Set response = ##class(Interlock.Msg.EvidenceResult).%New()
    Set case = ##class(Interlock.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Set response.Error = "Unknown case " _ request.CaseId Quit $$$OK
    Set now = ##class(Interlock.Util.Time).NowUTC()
    Set snap = ##class(Interlock.Store.Snapshot).Begin(case, ..FreshSeconds)
    Set count = 0

    // 1. The operation the case is about, as the production built it.
    Set op = ..OperationOf(case)
    Do snap.AddItem("operation", "production", now, op) Set count = count + 1

    // 2. The failure as the production saw it.
    Set failure = {}
    Set failure.kind = case.FailureKind, failure.text = case.FailureText
    Set failure."ens_session_id" = case.EnsSessionId, failure."source_header_id" = case.SourceHeaderId
    Do snap.AddItem("error", "production", now, failure) Set count = count + 1

    // 3. The message's named fields and its validation, from the message store.
    Set msgInfo = ..MessageFields(case.SourceHeaderId, .validation)
    Do snap.AddItem("message", "message_store", now, msgInfo) Set count = count + 1
    Do snap.AddItem("validation", "validator", now, validation) Set count = count + 1

    // 4. The ward's state and history for the encounter.
    Set wardState = ..WardGet("/wards/api/encounters/" _ ..URLEncode(case.EncounterId), .status)
    Set wardItem = {}
    Set wardItem."http_status" = status
    Set wardItem.body = wardState
    Do snap.AddItem("ward_state", "ward_api", now, wardItem) Set count = count + 1

    // 5. The receipt for the operation key, if any.
    Set receipt = ..WardGet("/wards/api/receipts/" _ ..URLEncode(case.OperationKey), .rstatus)
    Set receiptItem = {}
    Set receiptItem."http_status" = rstatus
    Set receiptItem.body = receipt
    Do snap.AddItem("receipt", "ward_api", now, receiptItem) Set count = count + 1

    // 6. Every operation the feed sent for this encounter in this run, with its delivery outcome.
    Set timeline = ..Timeline(case)
    Set laterCount = 0
    Set iter = timeline.%GetIterator()
    While iter.%GetNext(.i, .ev) {
        If ev."later" {
            Do snap.AddItem("later_event", "message_store", now, ev)
            Set count = count + 1, laterCount = laterCount + 1
        }
    }

    // 7. The route, with the receiver's own capability profile (GET /wards/api/capabilities):
    // the gate's capability check reads this, never an assumption.
    Set caps = ..WardGet("/wards/api/capabilities", .cstatus)
    Set route = {}
    Set route.feed = "ADT In -> ADT to Ward -> Ward Out"
    Set route.connector = "Ward Out"
    Set route.receiver = "the ward system (/wards/api)"
    Set route."capabilities_http_status" = cstatus
    If cstatus = 200 {
        Set route.capabilities = caps
        Do route.%Set("conditional_writes", ##class(Interlock.Util.Json).Bool(caps, "conditional_writes"), "boolean")
        Do route.%Set("receipts", ##class(Interlock.Util.Json).Bool(caps, "receipts"), "boolean")
        Do route.%Set("dry_run", ##class(Interlock.Util.Json).Bool(caps, "dry_run"), "boolean")
        Set route.epoch = ##class(Interlock.Util.Json).Str(caps, "epoch")
    } Else {
        Do route.%Set("capabilities", "", "null")
        Set route.note = "The receiver's capability profile could not be read; nothing is assumed about it"
    }
    Do snap.AddItem("route", "ward_api", now, route) Set count = count + 1

    // The summary the agents and the gate read.
    Set summary = {}
    Set summary."case_id" = case.CaseId
    Set summary.scenario = case.Scenario
    Set summary.operation = op
    Set summary.failure = failure
    Set summary.message = msgInfo
    Set summary.validation = validation
    Set summary."ward_state" = wardState
    Set summary."ward_state_http_status" = status
    Set summary.receipt = receipt
    Set summary."receipt_http_status" = rstatus
    Set summary.timeline = timeline
    Set summary."later_events" = laterCount
    Set summary.route = route
    Set summary.epoch = ##class(Interlock.Util.Json).Str(wardState, "epoch", ##class(Interlock.Util.Json).Str(route, "epoch"))
    Set summary."observed_at" = now
    Set summary."fresh_until" = snap.FreshUntil
    Set sc = snap.Seal(summary)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc) Quit $$$OK
    Set case.CurrentSnapshot = snap
    Do case.Note("artifact", "Snapshot " _ snap.Seq _ " taken: " _ count _ " observations, " _ laterCount _ " later events, digest " _ $EXTRACT(snap.Digest, 1, 19), "system", "snapshot:" _ snap.%Id())
    Set response.SnapshotId = snap.%Id(), response.Digest = snap.Digest, response.SummaryJSON = snap.Summary, response.ItemCount = count
    $$$TRACE("Snapshot " _ snap.%Id() _ " for " _ case.CaseId _ ": ward HTTP " _ status _ ", receipt HTTP " _ rstatus _ ", " _ laterCount _ " later events")
    Quit $$$OK
}

/// The case's operation as the contract's object.
Method OperationOf(case As Interlock.Store.Case) As %DynamicObject [ Private ]
{
    Set op = {}
    Set op."operation_key" = case.OperationKey, op."encounter_id" = case.EncounterId
    Set op."patient_id" = case.PatientId, op."patient_id_authority" = case.PatientIdAuthority
    Set op."event" = case.Event
    If case.Ward '= "" { Set op."ward" = case.Ward } Else { Do op.%Set("ward", "", "null") }
    Set op."event_time" = case.EventTime, op."source_system" = case.SourceSystem, op."source_message_id" = case.SourceMessageId
    Set op."payload_digest" = ##class(Interlock.Util.Digest).WardPayloadDigest(op)
    Quit op
}

/// Named fields of the HL7 message behind a message header, and its parse status.
Method MessageFields(headerId As %String, Output validation As %DynamicObject) As %DynamicObject [ Private ]
{
    Set info = {}, validation = {}
    Do validation.%Set("parsed", 0, "boolean")
    Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
    If '$ISOBJECT(header) Set info.error = "No message header " _ headerId Set validation.error = info.error Quit info
    Set msg = ##class(EnsLib.HL7.Message).%OpenId(header.MessageBodyId)
    If '$ISOBJECT(msg) Set info.error = "No HL7 message body " _ header.MessageBodyId Set validation.error = info.error Quit info
    Try {
        Set info."message_control_id" = msg.GetValueAt("MSH:10")
        Set info."message_type" = msg.GetValueAt("MSH:9.1") _ "^" _ msg.GetValueAt("MSH:9.2")
        Set info."sending_application" = msg.GetValueAt("MSH:3.1")
        Set info."sending_facility" = msg.GetValueAt("MSH:4.1")
        Set info."receiving_application" = msg.GetValueAt("MSH:5.1")
        Set info."message_time" = ##class(Interlock.Util.Time).FromHL7(msg.GetValueAt("MSH:7.1"))
        Set info."hl7_version" = msg.GetValueAt("MSH:12.1")
        Set info."event_recorded" = ##class(Interlock.Util.Time).FromHL7(msg.GetValueAt("EVN:2.1"))
        Set info."event_occurred" = ##class(Interlock.Util.Time).FromHL7(msg.GetValueAt("EVN:6.1"))
        Set info."patient_identifier" = msg.GetValueAt("PID:3(1).1") _ "^^^" _ msg.GetValueAt("PID:3(1).4.1") _ "^" _ msg.GetValueAt("PID:3(1).5")
        Set info."patient_name" = msg.GetValueAt("PID:5(1).1") _ ", " _ msg.GetValueAt("PID:5(1).2")
        Set info."patient_class" = msg.GetValueAt("PV1:2")
        Set info."assigned_location" = msg.GetValueAt("PV1:3.1") _ "^" _ msg.GetValueAt("PV1:3.2") _ "^" _ msg.GetValueAt("PV1:3.3") _ "^" _ msg.GetValueAt("PV1:3.4")
        Set info."visit_number" = msg.GetValueAt("PV1:19.1")
        Set info."admit_time" = ##class(Interlock.Util.Time).FromHL7(msg.GetValueAt("PV1:44.1"))
        Set notes = []
        For i = 1:1:8 {
            Set text = msg.GetValueAt("OBX(" _ i _ "):5")
            Quit:(text="")
            Set note = {}
            Set note."observation_id" = msg.GetValueAt("OBX(" _ i _ "):3.1")
            Set note.text = text
            Do notes.%Push(note)
        }
        Set info.notes = notes
        Set info."segment_count" = msg.SegCount
        Set info."doc_type" = msg.DocType
        // "dm": the document type must be known and the segment structure must match the schema.
        Set sc = msg.Validate("dm")
        Do validation.%Set("parsed", $$$ISOK(sc), "boolean")
        Set validation."doc_type" = msg.DocType
        Set validation."schema_category" = msg.DocTypeCategory
        Set validation.spec = "dm"
        If $$$ISERR(sc) Set validation.error = $SYSTEM.Status.GetErrorText(sc)
        Set validation.note = "Structural validation against the " _ msg.DocTypeCategory _ " schema (document type and segment structure); profile rules are the conformance review's job"
    } Catch ex {
        Set info.error = ex.DisplayString()
        Set validation.error = ex.DisplayString()
    }
    Quit info
}

/// GET a ward path; returns the parsed body (an object) and the HTTP status (0 when no answer).
Method WardGet(path As %String, Output status As %Integer) As %DynamicObject [ Private ]
{
    Set status = 0
    Set body = {}
    Try {
        Set http = ##class(%Net.HttpRequest).%New()
        Set sc = ..Adapter.SendFormDataArray(.resp, "GET", http, "", "", path)
        Set ..Retry = 0
        If $ISOBJECT($GET(resp)) {
            Set status = +resp.StatusCode
            Set text = ""
            If $ISOBJECT(resp.Data) { Do resp.Data.Rewind() While 'resp.Data.AtEnd { Set text = text _ resp.Data.Read(32000) } }
            Set parsed = ##class(Interlock.Util.Json).Parse(text, .psc)
            If $ISOBJECT(parsed) && $$$ISOK(psc) Set body = parsed
        } ElseIf $$$ISERR(sc) {
            Set body.error = $SYSTEM.Status.GetErrorText(sc)
        }
    } Catch ex {
        Set body.error = ex.DisplayString()
    }
    Quit body
}

/// Every normal operation the feed sent for the case's encounter in this run, oldest first, with
/// its delivery outcome and whether it is later than the case's event.
Method Timeline(case As Interlock.Store.Case) As %DynamicArray [ Private ]
{
    Set out = []
    Set resetAt = $GET(^Interlock.Config("resetAt"))
    Set since = $SELECT(resetAt = "": "2000-01-01 00:00:00", 1: $TRANSLATE($PIECE(resetAt, "Z", 1), "T", " "))
    Set sql = "SELECT w.ID AS WID, w.Event, w.Ward, w.EventTime, w.OperationKey, w.SourceMessageId, h.ID AS HeaderId, h.SessionId, h.TimeCreated "
        _ "FROM Interlock_Msg.WardOperation w JOIN Ens.MessageHeader h ON h.MessageBodyId = CAST(w.ID AS VARCHAR(20)) AND h.MessageBodyClassName = 'Interlock.Msg.WardOperation' "
        _ "WHERE w.EncounterId = ? AND w.Purpose = 'normal' AND h.TimeCreated >= ? ORDER BY w.EventTime, w.ID"
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, case.EncounterId, since)
    While rs.%Next() {
        Set ev = {}
        Set ev."event" = rs.%Get("Event"), ev.ward = rs.%Get("Ward"), ev."event_time" = rs.%Get("EventTime")
        Set ev."operation_key" = rs.%Get("OperationKey"), ev."source_message_id" = rs.%Get("SourceMessageId")
        Set ev."ens_header_id" = rs.%Get("HeaderId"), ev."ens_session_id" = rs.%Get("SessionId")
        Set ev."sent_at" = rs.%Get("TimeCreated")
        Do ev.%Set("later", rs.%Get("EventTime") ]] case.EventTime, "boolean")
        Do ev.%Set("this_case", rs.%Get("OperationKey") = case.OperationKey, "boolean")
        Set ev.outcome = "unknown"
        Set rid = ""
        &sql(SELECT TOP 1 MessageBodyId INTO :rid FROM Ens.MessageHeader WHERE CorrespondingMessageId = :headerId AND MessageBodyClassName = 'Interlock.Msg.WardResult')
        Set headerId = rs.%Get("HeaderId")
        &sql(SELECT TOP 1 MessageBodyId INTO :rid FROM Ens.MessageHeader WHERE CorrespondingMessageId = :headerId AND MessageBodyClassName = 'Interlock.Msg.WardResult')
        If (SQLCODE = 0) && (rid '= "") {
            Set r = ##class(Interlock.Msg.WardResult).%OpenId(rid)
            If $ISOBJECT(r) {
                Set ev.outcome = r.Outcome, ev."reason_code" = r.ReasonCode, ev."http_status" = r.HttpStatus
                If r.EncounterVersion '= "" Set ev."version_after" = r.EncounterVersion
            }
        }
        Do out.%Push(ev)
    }
    Quit out
}

Method URLEncode(s As %String) As %String [ Private ]
{
    Quit $ZCONVERT(s, "O", "URL")
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Interlock.Msg.EvidenceRequest">
    <Method>OnEvidenceRequest</Method>
  </MapItem>
</MapItems>
}

}
