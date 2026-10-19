/// The evidence collector: takes an immutable snapshot of what is known about a case from the
/// message store, the downstream system and the production, each observation with its source and time.
/// The agents and the gate read the snapshot's summary; nothing reaches them that is not in it.
Class Shutter.Operation.Evidence Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// Seconds a live observation stays fresh.
Property FreshSeconds As %Integer [ InitialExpression = 300 ];

/// The receiver whose paths are read when the case names none (the production item that delivers to it).
Property Receiver As %String(MAXLEN = 128) [ InitialExpression = {$PARAMETER("Shutter.Production", "RECEIVER")} ];

Parameter SETTINGS = "FreshSeconds:Evidence,Receiver:Evidence";

Method OnEvidenceRequest(request As Shutter.Msg.EvidenceRequest, Output response As Shutter.Msg.EvidenceResult) As %Status
{
    Set response = ##class(Shutter.Msg.EvidenceResult).%New()
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Set response.Error = "Unknown case " _ request.CaseId Quit $$$OK
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set snap = ##class(Shutter.Store.Snapshot).Begin(case, ..FreshSeconds)
    Set count = 0

    // 1. The operation the case is about, as the production built it.
    Set op = ..OperationOf(case)
    Do snap.AddItem("operation", "production", now, op) Set count = count + 1

    // 2. The failure as the production saw it.
    Set failure = {}
    Set failure.kind = case.FailureKind, failure.text = case.FailureText
    If case.FailureOutcome '= "" Set failure.outcome = case.FailureOutcome
    If case.FailureReasonCode '= "" Set failure."reason_code" = case.FailureReasonCode
    If case.FailureHttpStatus '= "" Do failure.%Set("http_status", case.FailureHttpStatus, "number")
    Set failure."ens_session_id" = case.EnsSessionId, failure."source_header_id" = case.SourceHeaderId
    Do snap.AddItem("error", "production", now, failure) Set count = count + 1

    // 3. The message's named fields and its validation, from the message store.
    Set msgInfo = ..MessageFields(case.SourceHeaderId, .validation)
    // Said once, on the first collection; the facts stay in every snapshot's message section.
    If (+##class(Shutter.Util.Json).Str(msgInfo, "times_without_offset") > 0) && '$ISOBJECT(case.CurrentSnapshot) {
        Do case.Note("note", "The message's times carry no offset; they are read as " _ ##class(Shutter.Util.Json).Str(msgInfo, "feed_time_zone") _ " (the site profile's feed time zone)" _ $SELECT(+##class(Shutter.Util.Json).Str(msgInfo, "times_with_offset") > 0: ", while others in the same message carry one", 1: ""), "system")
    }
    Do snap.AddItem("message", "message_store", now, msgInfo) Set count = count + 1
    Do snap.AddItem("validation", "validator", now, validation) Set count = count + 1

    // 4. The downstream system's state and history for the encounter.
    // The receiver's paths come from its description in the site profile (CONTRACTS 6.4), never from code.
    Set receiver = $SELECT(case.Receiver '= "": case.Receiver, 1: ..Receiver)
    // A case whose encounter piece is "-" (a patient-level message with no visit number: a merge, a person update)
    // names no encounter to read: the state and the receipt are not applicable, recorded with the statuses the
    // matcher reads as encounter_state unknown (no answer, 0) and receipt none (-1), and the timeline is empty.
    Set noEncounter = (case.EncounterId = "-")
    If noEncounter {
        Set status = 0, wardState = {"note": "Not applicable: the case names no encounter (the message carries no visit number)"}
    } Else {
        Set statePath = ##class(Shutter.Store.SiteProfile).ReceiverPath(receiver, "state", case.EncounterId)
        If statePath = "" { Set status = 0, wardState = {"error": "no state endpoint in the receiver's description"} } Else { Set wardState = ..WardGet(statePath, .status) }
    }
    Set wardItem = {}
    Set wardItem."http_status" = status
    Set wardItem.body = wardState
    If noEncounter Do wardItem.%Set("not_applicable", 1, "boolean")
    Do snap.AddItem("ward_state", "ward_api", now, wardItem) Set count = count + 1

    // 5. The receipt for the operation key, if any.
    If noEncounter {
        Set rstatus = -1, receipt = {"note": "Not applicable: the case names no encounter"}
    } Else {
        Set receiptPath = ##class(Shutter.Store.SiteProfile).ReceiverPath(receiver, "receipt", "", case.OperationKey)
        Set receipt = $SELECT(receiptPath = "": {}, 1: ..WardGet(receiptPath, .rstatus))
        // -1: the receiver keeps no receipts (no receipt path in its description), as against 0 for no answer.
        If receiptPath = "" Set rstatus = -1
    }
    Set receiptItem = {}
    Set receiptItem."http_status" = rstatus
    Set receiptItem.body = receipt
    If noEncounter Do receiptItem.%Set("not_applicable", 1, "boolean")
    Do snap.AddItem("receipt", "ward_api", now, receiptItem) Set count = count + 1

    // 6. Every operation the feed sent for this encounter in this run, with its delivery outcome.
    If noEncounter { Set timeline = [] } Else { Set timeline = ..Timeline(case) }
    Set laterCount = 0
    Set iter = timeline.%GetIterator()
    While iter.%GetNext(.i, .ev) {
        If ev."later" {
            Do snap.AddItem("later_event", "message_store", now, ev)
            Set count = count + 1, laterCount = laterCount + 1
        }
    }

    // 7. The route, with the receiver's own capability profile (its capabilities endpoint): the gate's capability
    // check reads this, never an assumption. A receiver without such an endpoint is described by the site profile's
    // declared features, and the route says so.
    Set capsPath = ##class(Shutter.Store.SiteProfile).ReceiverPath(receiver, "capabilities")
    Set declared = ##class(Shutter.Store.SiteProfile).ReceiverFeatures(receiver)
    If capsPath = "" {
        Set caps = declared, cstatus = 200
    } Else {
        Set caps = ..WardGet(capsPath, .cstatus)
    }
    Set route = {}
    Set route.feed = "ADT In -> ADT to Downstream -> " _ receiver
    Set route.connector = receiver
    Set route.receiver = ##class(Shutter.Store.SiteProfile).ReceiverLabel(receiver)
    Set route.tier = ##class(Shutter.Store.SiteProfile).TierOf(receiver)
    Set route."capabilities_source" = $SELECT(capsPath = "": "declared by the site profile", 1: "read from " _ capsPath)
    Set route.declared = declared
    Set route."capabilities_http_status" = cstatus
    If cstatus = 200 {
        Set route.capabilities = caps
        Do route.%Set("conditional_writes", ##class(Shutter.Util.Json).Bool(caps, "conditional_writes"), "boolean")
        Do route.%Set("receipts", ##class(Shutter.Util.Json).Bool(caps, "receipts"), "boolean")
        Do route.%Set("dry_run", ##class(Shutter.Util.Json).Bool(caps, "dry_run"), "boolean")
        Set route.epoch = ##class(Shutter.Util.Json).Str(caps, "epoch")
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
    Set summary.epoch = ##class(Shutter.Util.Json).Str(wardState, "epoch", ##class(Shutter.Util.Json).Str(route, "epoch"))
    Set summary."observed_at" = now
    // The incident this case belongs to, when one holds it (CONTRACTS 7): the board and the matcher see the chain.
    Set summary.incident = ##class(Shutter.Store.ChainItem).IncidentContext(case)
    Set chainKind = ##class(Shutter.Store.ChainItem).KindFor(case)
    // The catalogue: the condition vocabulary this snapshot shows, and the entries whose pattern holds (CONTRACTS 6).
    Try {
        Set summary.catalogue = ##class(Shutter.Catalogue.Matcher).Match(##class(Shutter.Catalogue.Matcher).Conditions(case, summary, chainKind), ##class(Shutter.Catalogue.Matcher).Facts(summary, case))
    } Catch ex {
        Set summary.catalogue = {"decision": "error", "error": (ex.DisplayString())}
    }
    Set summary."fresh_until" = snap.FreshUntil
    Set sc = snap.Seal(summary)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc) Quit $$$OK
    Set case.CurrentSnapshot = snap
    Do case.Note("artifact", "Snapshot " _ snap.Seq _ " taken: " _ count _ " observations, " _ laterCount _ " later events, digest " _ $EXTRACT(snap.Digest, 1, 19), "system", "snapshot:" _ snap.%Id())
    Set response.SnapshotId = snap.%Id(), response.Digest = snap.Digest, response.SummaryJSON = snap.Summary, response.ItemCount = count
    $$$TRACE("Snapshot " _ snap.%Id() _ " for " _ case.CaseId _ ": downstream HTTP " _ status _ ", receipt HTTP " _ rstatus _ ", " _ laterCount _ " later events")
    Quit $$$OK
}

/// The case's operation as the contract's object.
Method OperationOf(case As Shutter.Store.Case) As %DynamicObject [ Private ]
{
    Set op = {}
    Set op."operation_key" = case.OperationKey, op."encounter_id" = case.EncounterId
    Set op."patient_id" = case.PatientId, op."patient_id_authority" = case.PatientIdAuthority
    Set op."event" = case.Event
    If case.Ward '= "" { Set op."ward" = case.Ward } Else { Do op.%Set("ward", "", "null") }
    Set op."event_time" = case.EventTime, op."source_system" = case.SourceSystem, op."source_message_id" = case.SourceMessageId
    Set op."payload_digest" = ##class(Shutter.Util.Digest).WardPayloadDigest(op)
    // A merge (ADT^A40): the prior patient and visit the merge discards, as the case carries them. The payload
    // digest's eight keys (CONTRACTS 1.6) are unchanged by them.
    If case.PriorPatientId '= "" Set op."prior_patient_id" = case.PriorPatientId, op."prior_patient_id_authority" = case.PriorPatientIdAuthority
    If case.PriorEncounterId '= "" Set op."prior_encounter_id" = case.PriorEncounterId
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
        Set zone = ##class(Shutter.Store.SiteProfile).FeedTimeZone(), withOffset = 0, without = 0
        Set info."message_time" = ##class(Shutter.Util.Time).FromHL7(msg.GetValueAt("MSH:7.1"), zone, .had)
        If msg.GetValueAt("MSH:7.1") '= "" { If had { Set withOffset = withOffset + 1 } Else { Set without = without + 1 } }
        // MSH-12.1 under both names: hl7_version, as before, and message_version, the version note's name for it.
        Set version = msg.GetValueAt("MSH:12.1")
        Set info."hl7_version" = version, info."message_version" = version
        Set info."event_recorded" = ##class(Shutter.Util.Time).FromHL7(msg.GetValueAt("EVN:2.1"), zone, .had)
        If msg.GetValueAt("EVN:2.1") '= "" { If had { Set withOffset = withOffset + 1 } Else { Set without = without + 1 } }
        Set recordedHad = had
        Set info."event_occurred" = ##class(Shutter.Util.Time).FromHL7(msg.GetValueAt("EVN:6.1"), zone, .had)
        If msg.GetValueAt("EVN:6.1") '= "" { If had { Set withOffset = withOffset + 1 } Else { Set without = without + 1 } }
        // The field the operation key's time came from (EVN-6, else EVN-2): whether it carried an offset.
        Do info.%Set("event_time_had_offset", $SELECT(msg.GetValueAt("EVN:6.1") '= "": had, 1: recordedHad), "boolean")
        Set pid = ##class(Shutter.Util.OperationKey).PatientIdentifier(msg, .pidAuthority, .pidType)
        Set info."patient_identifier" = pid _ "^^^" _ pidAuthority _ "^" _ pidType
        Set info."patient_name" = ##class(Shutter.Util.OperationKey).Value(msg, "PID", "5(1).1") _ ", " _ ##class(Shutter.Util.OperationKey).Value(msg, "PID", "5(1).2")
        Set info."patient_class" = ##class(Shutter.Util.OperationKey).Value(msg, "PV1", "2")
        Set info."assigned_location" = ##class(Shutter.Util.OperationKey).Value(msg, "PV1", "3.1") _ "^" _ ##class(Shutter.Util.OperationKey).Value(msg, "PV1", "3.2") _ "^" _ ##class(Shutter.Util.OperationKey).Value(msg, "PV1", "3.3") _ "^" _ ##class(Shutter.Util.OperationKey).Value(msg, "PV1", "3.4")
        Set info."visit_number" = ##class(Shutter.Util.OperationKey).Value(msg, "PV1", "19.1")
        Set info."admit_time" = ##class(Shutter.Util.Time).FromHL7(##class(Shutter.Util.OperationKey).Value(msg, "PV1", "44.1"), zone, .had)
        If ##class(Shutter.Util.OperationKey).Value(msg, "PV1", "44.1") '= "" { If had { Set withOffset = withOffset + 1 } Else { Set without = without + 1 } }
        // A merge (ADT^A40, or any message carrying MRG): what the merge discards, from every MRG segment. The first
        // group's prior identifier and visit number stand at the top; prior_identifiers lists every group's, and
        // merge_groups counts them. A bare "MRG" path would read the first group only, so the segments are walked.
        Set trigger = msg.GetValueAt("MSH:9.2"), groups = 0, priors = [], lastPid = ""
        For i = 1:1:msg.SegCount {
            Set seg = msg.GetSegmentAt(i)
            Continue:'$ISOBJECT(seg)
            If seg.Name = "PID" Set lastPid = ..CXIdentifier(seg, 3)
            Continue:(seg.Name '= "MRG")
            Set groups = groups + 1
            Set prior = {}
            Do prior.%Set("group", groups, "number")
            // Each PATIENT group of ADT_A39 is one merge: the PID before the MRG is the surviving record, the MRG what it discards.
            Set prior."patient_identifier" = ..CXIdentifier(seg, 1), prior."visit_number" = seg.GetValueAt("5.1"), prior."into" = lastPid
            If groups = 1 Set info."prior_patient_identifier" = prior."patient_identifier", info."prior_visit_number" = prior."visit_number"
            Do priors.%Push(prior)
        }
        If (trigger = "A40") || (groups > 0) {
            If groups = 0 Set info."prior_patient_identifier" = "", info."prior_visit_number" = ""
            Do info.%Set("merge_groups", groups, "number")
            Set info."prior_identifiers" = priors
        }
        // How the times were read (T28): a timestamp without an offset is read in the feed's time zone.
        Set info."times_without_offset" = without, info."times_with_offset" = withOffset, info."feed_time_zone" = zone
        // Every OBX and NTE segment, wherever it sits (a group of an SIU message included), up to 50: the text stays in
        // the snapshot; what a model sees of it is a flag (Shutter.Util.ModelView).
        Set notes = []
        For i = 1:1:msg.SegCount {
            Quit:notes.%Size()>=50
            Set seg = msg.GetSegmentAt(i)
            Continue:'$ISOBJECT(seg)
            Set name = seg.Name
            Continue:(name'="OBX")&&(name'="NTE")
            Set note = {}
            Set note.segment = name, note.position = i
            If name = "OBX" {
                Set note."observation_id" = seg.GetValueAt("3.1"), note."value_type" = seg.GetValueAt("2")
                Set note.text = seg.GetValueAt("5")
            } Else {
                Set note.text = seg.GetValueAt("3")
            }
            Continue:(note.text="")&&(name="NTE")
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
        // The version note: the route's category is the site's choice, and IRIS never picks it from MSH-12, so a
        // message whose own version is not the category's standard is noted, never failed.
        Set category = msg.DocTypeCategory, standard = ..StandardCategory(category)
        Set validation."message_version" = version
        Set validation."route_category" = category
        Set validation."route_standard" = standard
        Set agrees = (version '= "") && (version = standard)
        Do validation.%Set("version_agrees", agrees, "boolean")
        If 'agrees Set validation."version_note" = $SELECT(version '= "": "The message says HL7 " _ version, 1: "The message names no HL7 version (MSH-12)") _ "; the route parses it as " _ $SELECT(standard '= "": standard, 1: category)
    } Catch ex {
        Set info.error = ex.DisplayString()
        Set validation.error = ex.DisplayString()
    }
    Quit info
}

/// A CX identifier field of a segment (PID-3, MRG-1) as "<id>^^^<authority>^<type>": the repetition typed MR (CX.5), else the first, as the
/// patient identifier is read from PID-3; "" when the field is empty.
Method CXIdentifier(seg As EnsLib.HL7.Segment, field As %Integer) As %String [ Private ]
{
    Set reps = +seg.GetValueAt(field _ "(*)"), pick = 1
    For r = 1:1:reps { If $ZCONVERT(seg.GetValueAt(field _ "(" _ r _ ").5"), "U") = "MR" Set pick = r Quit }
    Set id = seg.GetValueAt(field _ "(" _ pick _ ").1")
    If id = "" Quit ""
    Set authority = seg.GetValueAt(field _ "(" _ pick _ ").4.1")
    If authority = "" Set authority = seg.GetValueAt(field _ "(" _ pick _ ").4")
    Quit id _ "^^^" _ authority _ "^" _ seg.GetValueAt(field _ "(" _ pick _ ").5")
}

/// The standard category a schema category descends from: the category itself when it is standard, else its Base
/// walked up through the class query EnsLib.HL7.Schema:TypeCategories (Category, IsStandard, Base), read once per
/// call; "" when the instance does not know the category.
Method StandardCategory(category As %String) As %String [ Private ]
{
    If category = "" Quit ""
    Set out = ""
    Try {
        Kill base, standard
        Set rs = ##class(%ResultSet).%New("EnsLib.HL7.Schema:TypeCategories")
        If $ISOBJECT(rs) {
            Set sc = rs.Execute()
            If $$$ISOK(sc) {
                While rs.Next() {
                    Set cat = rs.Get("Category")
                    If cat '= "" Set base(cat) = rs.Get("Base"), standard(cat) = +rs.Get("IsStandard")
                }
            }
        }
        Set cat = category
        For i = 1:1:20 {
            Quit:'$DATA(standard(cat))
            If standard(cat) Set out = cat Quit
            Set cat = base(cat)
            Quit:cat=""
        }
    } Catch ex {
        Set out = ""
    }
    Quit out
}

/// GET a path on the downstream system; returns the parsed body (an object) and the HTTP status (0 when no answer).
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
            Set parsed = ##class(Shutter.Util.Json).Parse(text, .psc)
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
/// The operations sent for the encounter in this run, from the feed's typed messages and the exact index
/// (Shutter.Index.Timeline, CONTRACTS 8.2).
Method Timeline(case As Shutter.Store.Case) As %DynamicArray [ Private ]
{
    Quit ##class(Shutter.Index.Timeline).ForCase(case)
}

Method URLEncode(s As %String) As %String [ Private ]
{
    Quit $ZCONVERT(s, "O", "URL")
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.EvidenceRequest">
    <Method>OnEvidenceRequest</Method>
  </MapItem>
</MapItems>
}

}
