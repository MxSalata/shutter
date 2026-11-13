/// The projection of what FHIR Receiver read into the evidence of a case: the fhir view (identifiers, statuses,
/// references and version ids, never a name and never a body), the ward state in the shape every reader of an
/// encounter's state already takes, the receipt, and the route's capability fields.
///
/// Project, Material and RouteInto are pure: no storage, no globals, no network and no clock, and they never throw.
/// PriorWard reads the case's HL7 message and SealedBody the sealed read of a snapshot; neither writes.
Class Shutter.FHIR.Reader [ Abstract ]
{

Parameter KIND = "fhir_r4";

Parameter NORECEIPT = "No version in the history read carries the marker of a write this case sent";

Parameter NOSTATEMENT = "The server's CapabilityStatement could not be read; nothing is assumed about it";

Parameter CAPSOURCE = "read from the server's CapabilityStatement";

/// Projects the parts of one read (Shutter.Msg.FHIRReadResult's PartsJSON, as an object) for a case.
/// <ul>
/// <li><var>entry</var>: the receiver's whole entry of the site profile; the fhir block itself is accepted too.</li>
/// <li><var>priorWard</var>: PV1-6.1 of the case's message (PriorWard).</li>
/// <li><var>sentIds</var>: the operation ids of the writes this case sent (FHIRAttempt.SentOperationIds).</li>
/// <li><var>sealed</var>: the snapshot's summary.fhir, given by the gate at dispatch, where the read makes no search:
/// when the parts hold no search, the search of the view is copied from it and the Encounter part's status alone
/// decides the ward state's status. A part that is present always wins.</li>
/// </ul>
/// Returns {"fhir", "ward_state", "ward_state_http_status", "receipt", "receipt_http_status", "route",
/// "encounter_body"}. A part that is absent reads as not read (status 0); an object with only "error" stands for a
/// read that failed whole, and its text is the reason every part gives.
ClassMethod Project(parts As %DynamicObject, entry As %DynamicObject, case As Shutter.Store.Case, priorWard As %String, sentIds As %DynamicArray, sealed As %DynamicObject = "") As %DynamicObject
{
    Try {
        Set view = ..Build(parts, entry, case, priorWard, sentIds, sealed)
    } Catch ex {
        // Nothing of a read that could not be projected is believed: every status is 0 and the reason is said.
        Set failed = {}
        Do failed.%Set("error", $EXTRACT("the reads could not be projected: " _ ex.DisplayString(), 1, 400), "string")
        Try {
            Set view = ..Build(failed, "", case, priorWard, "", "")
        } Catch ex2 {
            Set view = {"fhir": {"kind": "fhir_r4"}, "ward_state": {"error": "the reads could not be projected", "kind": "fhir"}, "ward_state_http_status": 0, "receipt": {"error": "the reads could not be projected", "kind": "fhir"}, "receipt_http_status": 0, "route": {"kind": "fhir_r4", "capabilities_http_status": 0}, "encounter_body": ""}
        }
    }
    Quit view
}

/// Project's steps.
ClassMethod Build(parts As %DynamicObject, entry As %DynamicObject, case As Shutter.Store.Case, priorWard As %String, sentIds As %DynamicArray, sealed As %DynamicObject) As %DynamicObject [ Private ]
{
    Set block = $SELECT(..IsObject(entry) && ..IsObject(entry.%Get("fhir")): entry.%Get("fhir"), ..IsObject(entry): entry, 1: {})
    If '..IsObject(parts) Set parts = {}
    // The reason of a read that failed whole, given by every part that is not there.
    Set whole = ..Str(parts, "error")
    Set visit = $SELECT($ISOBJECT(case): case.EncounterId, 1: "")
    Set patientId = $SELECT($ISOBJECT(case): case.PatientId, 1: "")

    Set fhir = {}
    Do fhir.%Set("kind", ..#KIND, "string")
    Do fhir.%Set("base", $SELECT(..Str(parts, "base") '= "": ..Str(parts, "base"), 1: ..Str(block, "base")), "string")
    Do fhir.%Set("mapping_digest", ##class(Shutter.FHIR.Profile).MappingDigest(block), "string")
    Set message = {}
    Do message.%Set("prior_ward", priorWard, "string")
    Do message.%Set("target_ward", $SELECT($ISOBJECT(case): case.Ward, 1: ""), "string")
    Do message.%Set("event_time", $SELECT($ISOBJECT(case): case.EventTime, 1: ""), "string")
    Set fhir.message = message

    // The CapabilityStatement: the reader's own extract with the status it can be trusted with.
    Set part = ..PartOf(parts, "metadata", whole)
    Set capStatus = ..Status(part)
    If (capStatus = 200) && '..IsObject(part.%Get("statement")) Set capStatus = 0
    Set capability = ..Capability($SELECT(capStatus = 200: part.%Get("statement"), 1: ""), capStatus)
    Set fhir.capability = capability

    // The search: from the parts, else from the sealed view (the dispatch read makes none).
    Set search = {"http_status": 0, "matches": 0, "next": false}
    Set searchWhy = "", searchRead = 0, searchSealed = 0
    If parts.%GetTypeOf("search") = "object" {
        Set part = parts.%Get("search"), searchRead = 1
        Do search.%Set("http_status", ..Status(part), "number")
        If ..Status(part) = 200 {
            Set bundle = ##class(Shutter.FHIR.Trust).Parsed(..Str(part, "body"))
            Do search.%Set("matches", ##class(Shutter.FHIR.Trust).Matches(bundle).%Size(), "number")
            Do search.%Set("next", ..HasNext(bundle), "boolean")
        } Else {
            Set searchWhy = ..Why(part, "the search for the visit number")
        }
    } ElseIf ..IsObject(sealed) && ..IsObject(sealed.%Get("search")) {
        Set from = sealed.%Get("search"), searchSealed = 1
        Do search.%Set("http_status", ..Number(from, "http_status"), "number")
        Do search.%Set("matches", ..Number(from, "matches"), "number")
        Do search.%Set("next", ..Flag(from, "next"), "boolean")
    } Else {
        Set searchWhy = $SELECT(whole '= "": whole, 1: "the search for the visit number was not read")
    }
    Set fhir.search = search

    // The Encounter.
    Set part = ..PartOf(parts, "encounter", whole)
    Set encStatus = ..Status(part), encBody = "", encText = ""
    If encStatus = 200 {
        Set encText = ..Str(part, "body")
        Set encBody = ##class(Shutter.FHIR.Trust).Parsed(encText)
        If '..IsObject(encBody) Set encStatus = 0, encText = ""
    }
    Set encWhy = $SELECT(encStatus = 200: "", 1: ..Why(part, "the Encounter"))
    Set encounter = {}
    Do encounter.%Set("http_status", encStatus, "number")
    Set fhirId = ..Str(encBody, "id"), etag = $SELECT(encStatus = 200: ..Str(part, "etag"), 1: "")
    Set meta = $SELECT(..IsObject(encBody): encBody.%Get("meta"), 1: "")
    // Whether the representation is a subset is read before the version id.
    Set subsetted = ..HasTagCode(meta, "SUBSETTED")
    Set versionId = ..VersionId(encBody)
    Set usable = ##class(Shutter.FHIR.Judge).ETagVid(etag, .vid) && (vid '= "") && (vid = versionId)
    Set subjectObj = $SELECT(..IsObject(encBody): encBody.%Get("subject"), 1: "")
    Set subject = ..Str(subjectObj, "reference")
    Do encounter.%Set("id", fhirId, "string")
    Do encounter.%Set("etag", etag, "string")
    Do encounter.%Set("version_id", versionId, "string")
    Do encounter.%Set("etag_usable", usable, "boolean")
    Do encounter.%Set("status", ..Str(encBody, "status"), "string")
    Do encounter.%Set("subject", subject, "string")
    Set encSystem = ..Str(block.%Get("encounter_identifier"), "system")
    Do encounter.%Set("identifier_ok", ..IsObject(encBody) && (visit '= "-") && ..HoldsIdentifier(encBody.%Get("identifier"), encSystem, visit), "boolean")
    Do encounter.%Set("subsetted", subsetted, "boolean")
    // A modifier element of either kind: a modifierExtension anywhere, or implicitRules.
    Do encounter.%Set("modifier_extension", ..IsObject(encBody) && (..HasKey(encBody, "modifierExtension") || (encBody.%GetTypeOf("implicitRules") '= "unassigned")), "boolean")
    Do encounter.%Set("narrative", ..IsObject(encBody) && (encBody.%GetTypeOf("text") '= "unassigned"), "boolean")
    Do encounter.%Set("security", ..IsObject(meta) && (meta.%GetTypeOf("security") '= "unassigned"), "boolean")
    Do encounter.%Set("body_digest", $SELECT(encStatus = 200: ##class(Shutter.FHIR.Plan).BodyDigest(encText), 1: ""), "string")
    Set entries = [], open = 0, openWard = ""
    Set list = $SELECT(..IsObject(encBody): encBody.%Get("location"), 1: "")
    If ..IsArray(list) {
        Set it = list.%GetIterator()
        While it.%GetNext(.i, .e) {
            Set row = ..LocationEntry(e, block, .isOpen)
            Do entries.%Push(row)
            If isOpen Set open = open + 1, openWard = row.ward
        }
    }
    Set encounter.locations = entries
    Set fhir.encounter = encounter

    // The Patient.
    Set part = ..PartOf(parts, "patient", whole)
    Set patStatus = ..Status(part), patBody = ""
    If patStatus = 200 {
        Set patBody = ##class(Shutter.FHIR.Trust).Parsed(..Str(part, "body"))
        If '..IsObject(patBody) Set patStatus = 0
    }
    Set patSystem = ..Str(block.%Get("patient_identifier"), "system")
    Set patOk = ..IsObject(patBody) && ..HoldsIdentifier(patBody.%Get("identifier"), patSystem, patientId)
    Set patient = {}
    Do patient.%Set("http_status", patStatus, "number")
    Do patient.%Set("reference", $SELECT(patStatus = 200: "Patient/" _ ..Str(patBody, "id"), ..IsReference(subject, "Patient"): subject, 1: ""), "string")
    Do patient.%Set("etag", $SELECT(patStatus = 200: ..Str(part, "etag"), 1: ""), "string")
    Do patient.%Set("identifier_ok", patOk, "boolean")
    Set linked = 0, active = 0
    If ..IsObject(patBody) {
        Set links = patBody.%Get("link")
        Set linked = (patBody.%GetTypeOf("link") '= "unassigned") && ('..IsArray(links) || (links.%Size() > 0))
        // A Patient that does not say is in use, as FHIR reads it; a flag that is not true or false is not believed.
        Set active = $CASE(patBody.%GetTypeOf("active"), "unassigned": 1, "boolean": ''patBody.%Get("active"), : 0)
    }
    Do patient.%Set("link", linked, "boolean")
    Do patient.%Set("active", active, "boolean")
    Set fhir.patient = patient

    // The Locations: one for each part read, in the order they were asked for (the map's order for evidence). With
    // no such parts at all, every ward of the map stands as not read.
    Set locations = []
    Set list = parts.%Get("locations")
    If ..IsArray(list) {
        Set it = list.%GetIterator()
        While it.%GetNext(.i, .lp) {
            Do locations.%Push(..LocationRead(lp, block))
        }
    } ElseIf block.%GetTypeOf("location_map") = "array" {
        Set it = block.%Get("location_map").%GetIterator()
        While it.%GetNext(.i, .e) {
            Set unread = {}
            Do unread.%Set("http_status", 0, "number")
            Do unread.%Set("reference", ..Str(e, "location"), "string")
            Do locations.%Push(..LocationRead(unread, block))
        }
    }
    Set fhir.locations = locations

    // The history: its head, and the version that carries the marker of a write this case sent.
    Set part = ..PartOf(parts, "history", whole)
    Set histStatus = ..Status(part), histWhy = "", next = 0, count = 0, head = "", marked = ""
    If histStatus = 200 {
        Set bundle = ##class(Shutter.FHIR.Trust).Parsed(..Str(part, "body"))
        Set next = ..HasNext(bundle)
        Set list = $SELECT(..IsObject(bundle): bundle.%Get("entry"), 1: "")
        Set markerSystem = ..Str(block.%Get("marker"), "system"), unreadable = 0
        If ..IsArray(list) {
            Set count = list.%Size()
            Set it = list.%GetIterator()
            While it.%GetNext(.i, .e) {
                Set resource = $SELECT(..IsObject(e): e.%Get("resource"), 1: "")
                Set v = ..VersionId(resource)
                If i = 0 Set head = v
                Continue:'..CarriesMarker(resource, markerSystem, sentIds)
                If v = "" { Set unreadable = 1 } ElseIf marked = "" { Set marked = v }
            }
        }
        // A version that carries the marker and no version id: the history cannot say which version was written.
        If unreadable && (marked = "") Set histStatus = 0, histWhy = "a version in the history carries the marker of a write this case sent and no version id", next = 0, count = 0, head = ""
    } Else {
        Set histWhy = ..Why(part, "the history")
    }
    Set history = {}
    Do history.%Set("http_status", histStatus, "number")
    Do history.%Set("next", next, "boolean")
    Do history.%Set("entries", count, "number")
    Do history.%Set("head_version_id", head, "string")
    Do history.%Set("sent_marker_version", marked, "string")
    Set fhir.history = history

    // The ward state: the Encounter's status when the search gave exactly one match (or, with the sealed view's
    // search, by itself); 404 when a trusted search gave none; else nothing is known.
    Set stateWhy = ""
    If searchSealed {
        Set stateStatus = encStatus, stateWhy = encWhy
    } ElseIf 'searchRead || (search."http_status" '= 200) {
        Set stateStatus = 0, stateWhy = searchWhy
    } ElseIf search.matches = 1 {
        Set stateStatus = encStatus, stateWhy = encWhy
    } ElseIf search.matches = 0 {
        Set stateStatus = 404, stateWhy = "no Encounter at the receiver carries the visit number"
    } Else {
        Set stateStatus = 0, stateWhy = "the search gave " _ search.matches _ " Encounters for the visit number"
    }
    If stateStatus = 200 {
        Set wardState = {}
        Do wardState.%Set("encounter_id", visit, "string")
        Do wardState.%Set("fhir_id", fhirId, "string")
        // The case's own patient when the Patient read carries it under the mapped system and the case's authority is
        // the mapped one; else what the receiver holds under that system, with no authority, so no reader takes it as a match.
        Set authority = ..Str(block.%Get("patient_identifier"), "hl7_authority")
        If patOk && (authority '= "") && $ISOBJECT(case) && (case.PatientIdAuthority = authority) {
            Do wardState.%Set("patient_id", patientId, "string")
            Do wardState.%Set("patient_id_authority", authority, "string")
        } Else {
            Do wardState.%Set("patient_id", $SELECT(..IsObject(patBody): ..FirstValue(patBody.%Get("identifier"), patSystem), 1: ""), "string")
            Do wardState.%Set("patient_id_authority", "", "string")
        }
        Set status = ..Str(encBody, "status")
        Do wardState.%Set("state", $CASE(status, "in-progress": "admitted", "finished": "discharged", : status), "string")
        Do wardState.%Set("ward", $SELECT(open = 1: openWard, 1: ""), "string")
        Do wardState.%Set("version", versionId, "string")
        Do wardState.%Set("epoch", "", "string")
        Set wardState.history = ..History(entries, fhirId)
    } Else {
        Set wardState = {}
        Do wardState.%Set("error", $SELECT(stateWhy '= "": stateWhy, 1: "the Encounter was not read"), "string")
        Do wardState.%Set("kind", "fhir", "string")
    }

    // The receipt: present when a version carries the marker; absent only when the history was read whole.
    Set receipt = {}
    If (histStatus = 200) && (marked '= "") {
        Set receiptStatus = 200
        Do receipt.%Set("kind", "fhir", "string")
        Do receipt.%Set("operation_key", $SELECT($ISOBJECT(case): case.OperationKey, 1: ""), "string")
        Do receipt.%Set("version_after", marked, "string")
    } ElseIf (histStatus = 200) && 'next {
        Set receiptStatus = 404
        Do receipt.%Set("error", "no_receipt", "string")
        Do receipt.%Set("kind", "fhir", "string")
        Do receipt.%Set("note", ..#NORECEIPT, "string")
    } Else {
        Set receiptStatus = 0
        Do receipt.%Set("error", $SELECT(histStatus = 200: "the history has more pages than the one read, so it cannot say that no write of this case is in it", histWhy '= "": histWhy, 1: "the history was not read"), "string")
        Do receipt.%Set("kind", "fhir", "string")
    }

    // The route's fields: what the statement says, never what the profile declares.
    Set route = {}
    Do route.%Set("kind", ..#KIND, "string")
    Do route.%Set("capabilities_source", ..#CAPSOURCE, "string")
    Do route.%Set("capabilities_http_status", capStatus, "number")
    Set route.declared = {"conditional_writes": false, "receipts": false, "history": false, "dry_run": false}
    If capStatus = 200 {
        Set conditional = (capability.versioning = "versioned-update")
        Set readable = ..Holds(capability.interactions, "vread") && ..Holds(capability.interactions, "history-instance") && ..Flag(capability, "read_history")
        Set caps = {}
        Do caps.%Set("conditional_writes", conditional, "boolean")
        Do caps.%Set("receipts", 0, "boolean")
        Do caps.%Set("history", readable, "boolean")
        Do caps.%Set("dry_run", 0, "boolean")
        Set route.capabilities = caps
        Do route.%Set("conditional_writes", conditional, "boolean")
        Do route.%Set("receipts", 0, "boolean")
        Do route.%Set("history", readable, "boolean")
        Do route.%Set("dry_run", 0, "boolean")
    } Else {
        Do route.%Set("capabilities", "", "null")
    }
    Do route.%Set("epoch", "", "string")

    Set view = {}
    Set view.fhir = fhir
    Set view."ward_state" = wardState
    Do view.%Set("ward_state_http_status", stateStatus, "number")
    Set view.receipt = receipt
    Do view.%Set("receipt_http_status", receiptStatus, "number")
    Set view.route = route
    Do view.%Set("encounter_body", encText, "string")
    Quit view
}

/// The material view of summary.fhir: what a decision rests on, with no times and no statuses of the reads, so the
/// same evidence read twice gives the same digest and a changed version gives another.
ClassMethod Material(fhir As %DynamicObject) As %DynamicObject
{
    Set m = {}
    If '..IsObject(fhir) Quit m
    Set encounter = fhir.%Get("encounter"), patient = fhir.%Get("patient"), history = fhir.%Get("history"), capability = fhir.%Get("capability")
    Do m.%Set("encounter_etag", ..Str(encounter, "etag"), "string")
    Do m.%Set("body_digest", ..Str(encounter, "body_digest"), "string")
    Do m.%Set("patient_etag", ..Str(patient, "etag"), "string")
    Set etags = [], list = fhir.%Get("locations")
    If ..IsArray(list) {
        Set it = list.%GetIterator()
        While it.%GetNext(.i, .l) {
            Do etags.%Push(..Str(l, "etag"), "string")
        }
    }
    Set m."location_etags" = etags
    Do m.%Set("mapping_digest", ..Str(fhir, "mapping_digest"), "string")
    Do m.%Set("history_head", ..Str(history, "head_version_id"), "string")
    Set software = $SELECT(..IsObject(capability): capability.%Get("software"), 1: "")
    Set c = {}
    Do c.%Set("versioning", ..Str(capability, "versioning"), "string")
    Do c.%Set("read_history", ..Flag(capability, "read_history"), "boolean")
    Do c.%Set("update_create", ..Flag(capability, "update_create"), "boolean")
    Do c.%Set("software_name", ..Str(software, "name"), "string")
    Do c.%Set("software_version", ..Str(software, "version"), "string")
    Set m.capability = c
    Quit m
}

/// The item a snapshot keeps of the Encounter read: its digest, its ETag and its version id, and nothing else. The
/// body never enters a snapshot.
ClassMethod Item(fhir As %DynamicObject) As %DynamicObject
{
    Set encounter = $SELECT(..IsObject(fhir): fhir.%Get("encounter"), 1: "")
    Set item = {}
    Do item.%Set("body_digest", ..Str(encounter, "body_digest"), "string")
    Do item.%Set("etag", ..Str(encounter, "etag"), "string")
    Do item.%Set("version_id", ..Str(encounter, "version_id"), "string")
    Quit item
}

/// PV1-6.1 of the HL7 message behind the case's source header (the ward the patient was moved from), or "".
ClassMethod PriorWard(case As Shutter.Store.Case) As %String
{
    If '$ISOBJECT(case) || (case.SourceHeaderId = "") Quit ""
    Set ward = ""
    Try {
        Set header = ##class(Ens.MessageHeader).%OpenId(case.SourceHeaderId)
        Set msg = $SELECT($ISOBJECT(header): ##class(EnsLib.HL7.Message).%OpenId(header.MessageBodyId), 1: "")
        If $ISOBJECT(msg) Set ward = ##class(Shutter.Util.OperationKey).Value(msg, "PV1", "6.1")
    } Catch ex {
        Set ward = ""
    }
    Quit ward
}

/// The Encounter body a snapshot's FHIR evidence rests on: the sealed read kept beside the snapshot, given only when
/// it still has the digest the snapshot's summary names. "" for a snapshot with no FHIR evidence.
ClassMethod SealedBody(snapshot As Shutter.Store.Snapshot) As %String
{
    If '$ISOBJECT(snapshot) || (snapshot.%Id() = "") Quit ""
    Set digest = ""
    Try {
        Set summary = snapshot.SummaryObject()
        Set fhir = $SELECT(..IsObject(summary): summary.%Get("fhir"), 1: "")
        Set digest = ..Str($SELECT(..IsObject(fhir): fhir.%Get("encounter"), 1: ""), "body_digest")
    } Catch ex {
        Set digest = ""
    }
    If digest = "" Quit ""
    Quit ##class(Shutter.Store.FHIRSealedRead).BodyFor(snapshot.%Id(), digest)
}

/// Lays the projection's route fields over the route the Evidence Collector built, and takes away the note it wrote
/// for an entry with no capabilities endpoint and no declared features: this receiver's capability is read from its
/// CapabilityStatement. When that statement was not read the route says so, and carries no capability flag.
ClassMethod RouteInto(route As %DynamicObject, fields As %DynamicObject)
{
    If '..IsObject(route) || '..IsObject(fields) Quit
    Set it = fields.%GetIterator()
    While it.%GetNext(.key, .value) {
        Set type = fields.%GetTypeOf(key)
        If (type = "object") || (type = "array") {
            Do route.%Set(key, value)
        } ElseIf type = "null" {
            Do route.%Set(key, "", "null")
        } Else {
            Do route.%Set(key, value, type)
        }
    }
    Do route.%Remove("note")
    If ..Number(fields, "capabilities_http_status") '= 200 {
        For flag = "conditional_writes", "receipts", "history", "dry_run" {
            If fields.%GetTypeOf(flag) = "unassigned" Do route.%Remove(flag)
        }
        Do route.%Set("note", ..#NOSTATEMENT, "string")
    }
}

// ---- the pieces ----

/// The statement as the view carries it: every key there, empty when the statement was not read.
ClassMethod Capability(statement As %DynamicObject, status As %Integer) As %DynamicObject [ Private ]
{
    Set software = $SELECT(..IsObject(statement): statement.%Get("software"), 1: "")
    Set c = {}
    Do c.%Set("http_status", status, "number")
    Set s = {}
    Do s.%Set("name", ..Str(software, "name"), "string")
    Do s.%Set("version", ..Str(software, "version"), "string")
    Set c.software = s
    Do c.%Set("fhir_version", ..Str(statement, "fhir_version"), "string")
    Do c.%Set("versioning", ..Str(statement, "versioning"), "string")
    Set interactions = [], list = $SELECT(..IsObject(statement): statement.%Get("interactions"), 1: "")
    If ..IsArray(list) {
        Set it = list.%GetIterator()
        While it.%GetNext(.i, .code) {
            If list.%GetTypeOf(i) = "string" Do interactions.%Push(code, "string")
        }
    }
    Set c.interactions = interactions
    Do c.%Set("read_history", ..Flag(statement, "read_history"), "boolean")
    Do c.%Set("update_create", ..Flag(statement, "update_create"), "boolean")
    Quit c
}

/// One location entry of the Encounter as the view lists it; <var>isOpen</var> says whether it is open (status
/// active or absent, and no period.end), as the plan builder reads an entry.
ClassMethod LocationEntry(e, block As %DynamicObject, Output isOpen As %Boolean) As %DynamicObject [ Private ]
{
    Set isOpen = 0
    Set reference = "", status = "", start = "", end = "", hasEnd = 0, readable = ..IsObject(e)
    If readable {
        Set reference = ..Str(e.%Get("location"), "reference")
        Set status = ..Str(e, "status")
        Set period = e.%Get("period")
        If ..IsObject(period) {
            Set start = ..Str(period, "start"), end = ..Str(period, "end")
            Set hasEnd = (period.%GetTypeOf("end") '= "unassigned")
        }
        Set isOpen = 'hasEnd && ((e.%GetTypeOf("status") = "unassigned") || (status = "active"))
    }
    Set row = {}
    Do row.%Set("reference", reference, "string")
    Do row.%Set("ward", ##class(Shutter.FHIR.Profile).WardOf(block, reference), "string")
    Do row.%Set("status", status, "string")
    Do row.%Set("start", start, "string")
    Do row.%Set("start_utc", ##class(Shutter.Util.Time).FromFHIR(start), "string")
    Do row.%Set("end", end, "string")
    Quit row
}

/// One Location read as the view lists it: the reference asked for, its ward in the map, the trusted status, the
/// ETag, the status word and whether it carries exactly the map entry's identifier.
ClassMethod LocationRead(part As %DynamicObject, block As %DynamicObject) As %DynamicObject [ Private ]
{
    Set reference = ..Str(part, "reference"), status = ..Status(part), body = ""
    If status = 200 {
        Set body = ##class(Shutter.FHIR.Trust).Parsed(..Str(part, "body"))
        If '..IsObject(body) Set status = 0
    }
    Set ward = ##class(Shutter.FHIR.Profile).WardOf(block, reference)
    Set mapped = ##class(Shutter.FHIR.Profile).LocationOf(block, ward)
    Set want = $SELECT(..IsObject(mapped): mapped.%Get("identifier"), 1: "")
    Set row = {}
    Do row.%Set("reference", reference, "string")
    Do row.%Set("ward", ward, "string")
    Do row.%Set("http_status", status, "number")
    Do row.%Set("etag", $SELECT(status = 200: ..Str(part, "etag"), 1: ""), "string")
    Do row.%Set("status", ..Str(body, "status"), "string")
    Do row.%Set("identifier_ok", ..IsObject(body) && ..HoldsIdentifier(body.%Get("identifier"), ..Str(want, "system"), ..Str(want, "value")), "boolean")
    Quit row
}

/// The ward state's history: one transfer for each entry at a mapped Location whose start can be read, in the order
/// of their starts (entries with the same start keep the body's order). The key is
/// fhir^{Encounter id}/{Location id}^{start}: its first piece is "fhir", never the case's source system, and its last
/// the time, as the matcher reads a key. The two ids share one piece, because a key of four pieces or more is read
/// as source^authority^patient^encounter (Shutter.Util.ModelView), and a Location's id is no patient's.
ClassMethod History(entries As %DynamicArray, fhirId As %String) As %DynamicArray [ Private ]
{
    Set it = entries.%GetIterator()
    While it.%GetNext(.i, .e) {
        Continue:(e.ward="")||(e."start_utc"="")
        Set sorted(e."start_utc", i) = e
    }
    Set out = [], t = ""
    For {
        Set t = $ORDER(sorted(t))
        Quit:t=""
        Set i = ""
        For {
            Set i = $ORDER(sorted(t, i), 1, e)
            Quit:i=""
            Set row = {}
            Do row.%Set("event", "transfer", "string")
            Do row.%Set("event_time", t, "string")
            Do row.%Set("ward", e.ward, "string")
            Do row.%Set("operation_key", "fhir^" _ fhirId _ "/" _ $PIECE(e.reference, "/", 2) _ "^" _ t, "string")
            Do row.%Set("applied_at", t, "string")
            Do row.%Set("version", "", "string")
            Do out.%Push(row)
        }
    }
    Quit out
}

/// A part of the read, or one that stands for a part that is not there: status 0 with the reason.
ClassMethod PartOf(parts As %DynamicObject, name As %String, whole As %String) As %DynamicObject [ Private ]
{
    If parts.%GetTypeOf(name) = "object" Quit parts.%Get(name)
    Set part = {}
    Do part.%Set("http_status", 0, "number")
    Do part.%Set("error", $SELECT(whole '= "": whole, 1: "not read"), "string")
    Quit part
}

/// Why a part is not a 200: what the part says, else its status.
ClassMethod Why(part As %DynamicObject, what As %String) As %String [ Private ]
{
    Set error = ..Str(part, "error"), status = ..Status(part)
    If error '= "" Quit $EXTRACT(what _ ": " _ error, 1, 400)
    Quit $SELECT(status = 0: what _ " was not read", 1: what _ " answered HTTP " _ status)
}

/// A part's trusted status as a whole number, 0 for anything else.
ClassMethod Status(part As %DynamicObject) As %Integer [ Private ]
{
    Quit ..Number(part, "http_status")
}

/// A whole number of 1 to 9 digits under a key, 0 for anything else.
ClassMethod Number(obj As %DynamicObject, key As %String) As %Integer [ Private ]
{
    If '..IsObject(obj) Quit 0
    Set type = obj.%GetTypeOf(key)
    If (type '= "number") && (type '= "string") Quit 0
    Set value = obj.%Get(key)
    Quit $SELECT(value ? 1.9N: +value, 1: 0)
}

/// True only for a JSON true under a key.
ClassMethod Flag(obj As %DynamicObject, key As %String) As %Boolean [ Private ]
{
    If '..IsObject(obj) || (obj.%GetTypeOf(key) '= "boolean") Quit 0
    Quit ''obj.%Get(key)
}

/// Whether a Bundle has a link of relation next: more pages than the one read.
ClassMethod HasNext(bundle As %DynamicObject) As %Boolean [ Private ]
{
    Set links = $SELECT(..IsObject(bundle): bundle.%Get("link"), 1: "")
    If '..IsArray(links) Quit 0
    Set found = 0, it = links.%GetIterator()
    While it.%GetNext(.i, .l) {
        If ..IsObject(l) && (..Str(l, "relation") = "next") Set found = 1
    }
    Quit found
}

/// Whether an identifier[] holds exactly the system and value (case-sensitive) and no other value under that system.
ClassMethod HoldsIdentifier(ids, system As %String, value As %String) As %Boolean [ Private ]
{
    If '..IsArray(ids) || (system = "") || (value = "") Quit 0
    Set found = 0, other = 0, it = ids.%GetIterator()
    While it.%GetNext(.i, .id) {
        Continue:'..IsObject(id)
        Continue:(..Str(id, "system") '= system)
        If ..Str(id, "value") = value { Set found = 1 } Else { Set other = 1 }
    }
    Quit found && 'other
}

/// The first value an identifier[] holds under a system, or "".
ClassMethod FirstValue(ids, system As %String) As %String [ Private ]
{
    If '..IsArray(ids) || (system = "") Quit ""
    Set value = "", it = ids.%GetIterator()
    While it.%GetNext(.i, .id) {
        If ..IsObject(id) && (..Str(id, "system") = system) && (..Str(id, "value") '= "") Set value = id.value Quit
    }
    Quit value
}

/// Whether a meta object has a tag of that code, under any system.
ClassMethod HasTagCode(meta, code As %String) As %Boolean [ Private ]
{
    Set tags = $SELECT(..IsObject(meta): meta.%Get("tag"), 1: "")
    If '..IsArray(tags) Quit 0
    Set found = 0, it = tags.%GetIterator()
    While it.%GetNext(.i, .t) {
        If ..IsObject(t) && (..Str(t, "code") = code) Set found = 1
    }
    Quit found
}

/// Whether a version of the history carries the marker of a write this case sent: a meta.tag of the marker system
/// whose code is one of the operation ids, both compared as strings, case-sensitive.
ClassMethod CarriesMarker(resource, system As %String, sentIds As %DynamicArray) As %Boolean [ Private ]
{
    If '..IsObject(resource) || (system = "") || '..IsArray(sentIds) || (sentIds.%Size() = 0) Quit 0
    Set meta = resource.%Get("meta")
    Set tags = $SELECT(..IsObject(meta): meta.%Get("tag"), 1: "")
    If '..IsArray(tags) Quit 0
    Set found = 0, it = tags.%GetIterator()
    While it.%GetNext(.i, .t) {
        Continue:'..IsObject(t)
        Continue:(..Str(t, "system") '= system)||(..Str(t, "code") = "")
        If ..Holds(sentIds, t.code) Set found = 1
    }
    Quit found
}

/// Whether a list holds that string.
ClassMethod Holds(list, text As %String) As %Boolean [ Private ]
{
    If '..IsArray(list) Quit 0
    Set found = 0, it = list.%GetIterator()
    While it.%GetNext(.i, .value) {
        If (list.%GetTypeOf(i) = "string") && (value = text) Set found = 1
    }
    Quit found
}

/// Whether a key is anywhere in a JSON value, at any depth.
ClassMethod HasKey(node, key As %String) As %Boolean [ Private ]
{
    If '$ISOBJECT(node) Quit 0
    If ..IsObject(node) && (node.%GetTypeOf(key) '= "unassigned") Quit 1
    Set found = 0, it = node.%GetIterator()
    While it.%GetNext(.k, .value) {
        If $ISOBJECT(value) && ..HasKey(value, key) Set found = 1 Quit
    }
    Quit found
}

/// A resource's meta.versionId when it is a non-empty string, else "".
ClassMethod VersionId(resource) As %String [ Private ]
{
    Set meta = $SELECT(..IsObject(resource): resource.%Get("meta"), 1: "")
    Quit ..Str(meta, "versionId")
}

/// Whether a reference is literal: {type}/{id} with a FHIR id, and nothing else.
ClassMethod IsReference(reference As %String, type As %String) As %Boolean [ Private ]
{
    Quit $MATCH(reference, type _ "/[A-Za-z0-9.\-]{1,64}")
}

/// The string under a key, "" when the key is absent or holds anything but a string.
ClassMethod Str(obj, key As %String) As %String [ Private ]
{
    If '..IsObject(obj) || (obj.%GetTypeOf(key) '= "string") Quit ""
    Quit obj.%Get(key)
}

ClassMethod IsObject(x) As %Boolean [ Private ]
{
    Quit $ISOBJECT(x) && x.%IsA("%Library.DynamicObject")
}

ClassMethod IsArray(x) As %Boolean [ Private ]
{
    Quit $ISOBJECT(x) && x.%IsA("%Library.DynamicArray")
}

}
