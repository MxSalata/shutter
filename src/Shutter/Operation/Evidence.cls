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

/// The item asked for an independent parser's report on a message IRIS could not read (the Second Parser, a PEX business
/// operation running HAPI in Java); empty never asks.
Property SecondParserTarget As %String(MAXLEN = 128) [ InitialExpression = "Second Parser" ];

Parameter SETTINGS = "FreshSeconds:Evidence,Receiver:Evidence,SecondParserTarget:Evidence";

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

    // 2b. Where the original message lives when the case came from another production (CONTRACTS 11): the namespace,
    // the production, the route that received it and its header id there. Operational names, no patient data.
    Set source = ""
    If case.SourceNamespace '= "" {
        Set source = {}
        Set source.namespace = case.SourceNamespace, source.production = case.SourceProduction
        Set source.route = case.SourceRoute, source."header_id" = case.OriginHeaderId
        Do snap.AddItem("source", "production", now, source) Set count = count + 1
    }

    // 3. The message's named fields and its validation, from the message store.
    Set msgInfo = ..MessageFields(case.SourceHeaderId, .validation)
    // Said once, on the first collection; the facts stay in every snapshot's message section.
    If (+##class(Shutter.Util.Json).Str(msgInfo, "times_without_offset") > 0) && '$ISOBJECT(case.CurrentSnapshot) {
        Set zone = ##class(Shutter.Util.Json).Str(msgInfo, "feed_time_zone")
        // A zone Shutter does not know is read as UTC: the note says so rather than name a zone that was not applied.
        Set read = $SELECT(##class(Shutter.Util.Time).KnownZone(zone): zone _ " (the site profile's feed time zone)", 1: "UTC (the feed time zone, " _ zone _ ", is not one Shutter knows)")
        Do case.Note("note", "The message's times carry no offset; they are read as " _ read _ $SELECT(+##class(Shutter.Util.Json).Str(msgInfo, "times_with_offset") > 0: ", while others in the same message carry one", 1: ""), "system")
    }
    Do snap.AddItem("message", "message_store", now, msgInfo) Set count = count + 1
    // A message IRIS could not read (no parse, or a schema this namespace lacks) gets a second opinion from an independent
    // parser, the Second Parser item (CONTRACTS 6.7, v1.34), when the production has one; without it the evidence says so.
    If (..SecondParserTarget '= "") && '##class(Shutter.Util.Json).Bool(validation, "parsed") Set validation."second_parser" = ..SecondOpinion(case.SourceHeaderId)
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

    // 4b. A refusal for an occupied bed (v1.28): who holds the bed and whether they are leaving, from the refusal the
    // connector recorded, the occupant's encounter read now and the feed's deliveries for it (Shutter.Util.BedConflict). The
    // occupant is named by their encounter id only, a token for the model; no demographic of theirs is read.
    Set conflict = ""
    If (case.FailureReasonCode = "bed_occupied") && 'noEncounter {
        Set refusal = ##class(Shutter.Index.Timeline).LastRefusal(case)
        Set occ = $SELECT($ISOBJECT(refusal): refusal.%Get("occupant"), 1: "")
        Set occId = $SELECT($ISOBJECT(occ): ##class(Shutter.Util.Json).Str(occ, "encounter_id"), 1: "")
        Set occRead = {}, ostatus = 0, deliveries = []
        If (occId '= "") && (occId '= case.EncounterId) {
            Set opath = ##class(Shutter.Store.SiteProfile).ReceiverPath(receiver, "state", occId)
            If opath '= "" Set occRead = ..WardGet(opath, .ostatus)
            Set deliveries = ##class(Shutter.Index.Timeline).Deliveries(occId, receiver, case.SourceNamespace)
        }
        Set conflict = ##class(Shutter.Util.BedConflict).Build(refusal, case.Ward, case.Bed, occRead, ostatus, deliveries)
        Do snap.AddItem("bed_conflict", "ward_api", now, conflict) Set count = count + 1
    }

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

    // 6b. The messages of the encounter pending ahead of a resend (v1.29, the failsafe): received after the case's own
    // and not yet delivered to the receiver, from the feed's deliveries and the exact index (Shutter.Util.ResendGuard). The
    // gate blocks a write while one is pending, and the connector checks again at the moment of the write.
    Set pending = $SELECT(noEncounter: [], 1: ##class(Shutter.Util.ResendGuard).Pending(case))
    Set pendingItem = {}
    Set pendingItem.items = pending
    Do pendingItem.%Set("count", pending.%Size(), "number")
    Do snap.AddItem("pending_messages", "message_store", now, pendingItem) Set count = count + 1

    // 6c. Further messages for the patient, on any visit (Shutter.Util.FurtherMessages): the gate stops a write on them, and
    // the plan shows the ones that don't stop it.
    Set further = ##class(Shutter.Util.FurtherMessages).Find(case)
    Do snap.AddItem("further_messages", "message_store", now, further) Set count = count + 1

    // 7. The route, with the receiver's own capability profile (its capabilities endpoint): the gate's capability
    // check reads this, never an assumption. A receiver without such an endpoint is described by the site profile's
    // declared features, and the route says so.
    Set route = ..Route(receiver)
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
    If $ISOBJECT(conflict) Set summary."bed_conflict" = conflict
    Set summary.timeline = timeline
    Set summary."later_events" = laterCount
    Set summary."pending_messages" = pending
    Set summary."further_messages" = further
    Set summary.route = route
    If $ISOBJECT(source) Set summary.source = source
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
    // Precedents (6.4, v1.35): what approvers decided before on these conditions at this receiver, and whether it held.
    // For the person and the app: the model view's allowlist leaves it out, and the material digest never includes it.
    Try {
        Set pcat = summary.%Get("catalogue")
        Set summary.precedents = ##class(Shutter.Store.Precedent).Summary(case.Receiver, $SELECT($ISOBJECT(pcat): pcat.%Get("conditions"), 1: ""))
    } Catch ex {
        Set summary.precedents = {"error": (ex.DisplayString())}
    }
    Set summary."fresh_until" = snap.FreshUntil
    Set sc = snap.Seal(summary)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc) Quit $$$OK
    // The snapshot field alone: this copy of the case was read before the lookups, and the case may have joined an
    // incident meanwhile.
    Set sc = case.SetSnapshot(snap)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc) Quit $$$OK
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
    // The bed travels beside the canonical payload (v1.28): the recovery write and the rehearsal carry it, the digest does not.
    If case.Bed '= "" { Set op."bed" = case.Bed } Else { Do op.%Set("bed", "", "null") }
    Set op."event_time" = case.EventTime, op."source_system" = case.SourceSystem, op."source_message_id" = case.SourceMessageId
    Set op."payload_digest" = ##class(Shutter.Util.Digest).WardPayloadDigest(op)
    // A merge (ADT^A40): the prior patient and visit the merge discards, as the case carries them. The payload
    // digest's eight keys (CONTRACTS 1.6) are unchanged by them.
    If case.PriorPatientId '= "" Set op."prior_patient_id" = case.PriorPatientId, op."prior_patient_id_authority" = case.PriorPatientIdAuthority
    If case.PriorEncounterId '= "" Set op."prior_encounter_id" = case.PriorEncounterId
    Quit op
}

/// The Second Parser's report on the HL7 message behind a header (CONTRACTS 6.1): the item's report object with the item's
/// name added, or {available: false, item, reason} when the item is off, missing, slow or failing; nothing here throws.
Method SecondOpinion(headerId As %String) As %DynamicObject
{
    Set out = {}
    Do out.%Set("available", 0, "boolean")
    Set out.item = ..SecondParserTarget
    Try {
        Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
        Set msg = $SELECT($ISOBJECT(header): ##class(EnsLib.HL7.Message).%OpenId(header.MessageBodyId), 1: "")
        If '$ISOBJECT(msg) Set out.reason = "no HL7 message behind header " _ headerId Quit
        Set raw = msg.OutputToString(, , .osc)
        If $$$ISERR(osc) || (raw = "") Set raw = msg.RawContent
        If raw = "" Set out.reason = "the message has no text to parse" Quit
        If '##class(Shutter.Util.SecondParser).Available() Set out.reason = "the parser's jar is not installed (pex/build.sh), so the item is off" Quit
        Set req = ##class(Shutter.Msg.ParseRequest).%New()
        Set req.Raw = raw, req.HeaderId = headerId
        Set sc = ..SendRequestSync(..SecondParserTarget, req, .resp, 20)
        If $$$ISERR(sc) Set out.reason = $EXTRACT($SYSTEM.Status.GetErrorText(sc), 1, 300) Quit
        If '$ISOBJECT(resp) Set out.reason = "no answer within 20 s" Quit
        Set out = resp.Report()
        Do out.%Set("available", 1, "boolean")
        Set out.item = ..SecondParserTarget
    } Catch ex {
        Set out = {}
        Do out.%Set("available", 0, "boolean")
        Set out.item = ..SecondParserTarget, out.reason = $EXTRACT(ex.DisplayString(), 1, 300)
    }
    Quit out
}

/// Named fields of the HL7 message behind a message header, and its parse status.
/// The item that received the message behind a header (its SourceConfigName), "" when the header is not there.
Method SourceItemOf(headerId As %String) As %String [ Private ]
{
    Set h = $SELECT(headerId = "": "", 1: ##class(Ens.MessageHeader).%OpenId(headerId))
    Quit $SELECT($ISOBJECT(h): h.SourceConfigName, 1: "")
}

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
        // A message its route could not type (its category was not loaded when it arrived; v1.34, the hold) is typed here
        // for the check once the category is known, in memory only: the stored copy stays as it arrived.
        Set heldCategory = ##class(Shutter.Util.Schemas).CategoryOf(msg, ..SourceItemOf(headerId))
        If (msg.DocType = "") && ##class(Shutter.Util.Schemas).Known(heldCategory) {
            Set heldType = ##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType(heldCategory, msg.Name, .hsc)
            If $$$ISOK(hsc) && (heldType '= "") Do msg.PokeDocType(heldType)
        }
        // A forward that named a category not loaded when it came (v1.42) is read by that category from then on: once the
        // schema is loaded a copy from its text is typed under it (the stored copy's segment map is 2.5.1's, and it stays as it
        // arrived), in memory only; until then the verdict below is "unknown schema".
        Set namedCategory = ##class(Shutter.Util.Schemas).NamedCategory(msg)
        If (namedCategory '= "") && ##class(Shutter.Util.Schemas).Known(namedCategory) {
            Set namedType = ##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType(namedCategory, msg.Name, .nsc)
            Set namedCopy = $SELECT($$$ISOK(nsc) && (namedType '= ""): ##class(EnsLib.HL7.Message).ImportFromString(msg.OutputToString(), .csc), 1: "")
            If $ISOBJECT(namedCopy) {
                Do namedCopy.PokeDocType(namedType)
                Set msg = namedCopy
            }
        }
        // "dm": the document type must be known and the segment structure must match the schema.
        Set sc = msg.Validate("dm")
        Do validation.%Set("parsed", $$$ISOK(sc), "boolean")
        Set validation."doc_type" = msg.DocType
        Set validation."schema_category" = $SELECT(namedCategory '= "": namedCategory, msg.DocTypeCategory '= "": msg.DocTypeCategory, 1: heldCategory)
        Set validation.spec = "dm"
        If $$$ISERR(sc) Set validation.error = $SYSTEM.Status.GetErrorText(sc)
        // A category this namespace does not hold (v1.32: a forwarded message named its source's own schema) cannot be
        // validated at all: the verdict is "unknown schema" with the fix, never "invalid message".
        Set schemaKnown = ##class(Shutter.Util.Schemas).Known(validation."schema_category")
        Do validation.%Set("schema_known", schemaKnown, "boolean")
        If 'schemaKnown {
            Do validation.%Set("parsed", 0, "boolean")
            Set validation.error = "unknown schema: the category " _ $SELECT(validation."schema_category" = "": "(none)", 1: validation."schema_category") _ " is not loaded in this namespace, so the message could not be validated"
            Set validation."schema_fix" = "Import the schema with Write ##class(Shutter.Util.Schemas).ImportFrom(""<source namespace>"",""<category>""), or from a file with SELECT Shutter.Setup_ImportSchema('<path>') (it replaces a same-named category whole) or POST /settings/schemas, then reinvestigate the case"
        }
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

/// The route item (CONTRACTS 6.4): the receiver's own capability profile, read from its capabilities endpoint, or
/// the features its entry in the site profile declares when it has no such endpoint. An entry without an endpoint that
/// declares no features vouches for nothing: the route then records the capabilities as unread (status 0), so the gate
/// answers unknown (CAPABILITIES_UNREADABLE) rather than pass on the defaults. The declared features stay on the route
/// as the record of what the site believes.
Method Route(receiver As %String) As %DynamicObject
{
    Set capsPath = ##class(Shutter.Store.SiteProfile).ReceiverPath(receiver, "capabilities")
    Set declared = ##class(Shutter.Store.SiteProfile).ReceiverFeatures(receiver)
    Set entry = ##class(Shutter.Store.SiteProfile).Receiver(receiver)
    Set undeclared = (capsPath = "") && '($ISOBJECT(entry) && $ISOBJECT(entry.%Get("features")))
    If undeclared {
        Set caps = {}, cstatus = 0
    } ElseIf capsPath = "" {
        Set caps = declared, cstatus = 200
    } Else {
        Set caps = ..WardGet(capsPath, .cstatus)
    }
    Set route = {}
    Set route.feed = "ADT In -> ADT to Downstream -> " _ receiver
    Set route.connector = receiver
    Set route.receiver = ##class(Shutter.Store.SiteProfile).ReceiverLabel(receiver)
    Set route.tier = ##class(Shutter.Store.SiteProfile).TierOf(receiver)
    // The receiver's category and the history policy it derives (v1.23), as the snapshot saw them
    Set route.category = ##class(Shutter.Store.SiteProfile).ReceiverCategory(receiver)
    Set route."history_policy" = ##class(Shutter.Store.SiteProfile).ReceiverHistoryPolicy(receiver)
    Set route."capabilities_source" = $SELECT(undeclared: "not declared by the site profile", capsPath = "": "declared by the site profile", 1: "read from " _ capsPath)
    Set route.declared = declared
    Set route."capabilities_http_status" = cstatus
    If cstatus = 200 {
        Set route.capabilities = caps
        Do route.%Set("conditional_writes", ##class(Shutter.Util.Json).Bool(caps, "conditional_writes"), "boolean")
        Do route.%Set("receipts", ##class(Shutter.Util.Json).Bool(caps, "receipts"), "boolean")
        Do route.%Set("dry_run", ##class(Shutter.Util.Json).Bool(caps, "dry_run"), "boolean")
        Set route.epoch = ##class(Shutter.Util.Json).Str(caps, "epoch")
    } ElseIf undeclared {
        Do route.%Set("capabilities", "", "null")
        Set route.note = "The receiver has no capabilities endpoint and its entry in the site profile declares no features; nothing is assumed about it"
    } Else {
        Do route.%Set("capabilities", "", "null")
        Set route.note = "The receiver's capability profile could not be read; nothing is assumed about it"
    }
    Quit route
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
