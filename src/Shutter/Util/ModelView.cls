/// What a model may see of a case (T27, the owner's rule of 19 Oct): the evidence and every tool result pass through
/// Reduce before they leave IRIS, and the model's findings, plan and text pass through Restore before they are stored.
/// Reduce rebuilds the object from allowlists chosen by each node's shape (the summary, the operation, the message,
/// the validation, a receiver's body, a history entry, a receipt, the failure, a timeline row, the route) and a denylist
/// of demographic keys everywhere else; replaces each OBX or NTE note by a flag (unless the site profile allows the
/// text); and replaces every identifier of the case (MRN, NHS number, other patient identifiers, encounter ids, visit
/// numbers, the name parts and the date of birth) by the case's token for it (Shutter.Store.CaseToken) inside every
/// string value, wherever the value stands: a field, an operation key, a history entry, a timeline row, an error echo.
/// The map is built once per case by Learn, in the business process, in a canonical order; Reduce only reads it. The
/// view fails closed: when Learn cannot read the message or store a token it returns an error and the workflow sends
/// nothing, and Reduce refuses a case whose own identifiers have no tokens. Values of three characters or more are
/// matched whatever their case ("SMITH", "Smith"); a two-letter name part only as written, so a short word of the
/// summary's own text ("no", "to") is never taken for a name. The stored snapshot is untouched: the gate, the matcher, the verifier and the app read it inside
/// IRIS. The regular expressions are ICU's ($LOCATE, $MATCH).
Class Shutter.Util.ModelView Extends %RegisteredObject
{

/// Keys that never leave IRIS, wherever they occur.
Parameter DENYLIST = ",patient_name,name,given_name,family_name,date_of_birth,dob,birth_date,birth_time,sex,gender,address,phone,telephone,email,next_of_kin,mother_maiden_name,maiden_name,religion,ethnicity,ethnic_group,marital_status,nationality,ssn,national_id,language,headline,";

Parameter SUMMARYKEEP = ",case_id,scenario,operation,failure,message,validation,ward_state,ward_state_http_status,receipt,receipt_http_status,bed_conflict,pending_messages,timeline,later_events,route,source,epoch,observed_at,incident,catalogue,fresh_until,snapshot_id,snapshot_digest,taken_at,";

/// What the source of a case from another production keeps (CONTRACTS 11): the namespace, the production, the route
/// and the header id there, operational names with no patient data.
Parameter SOURCEKEEP = ",namespace,production,route,header_id,";

Parameter OPERATIONKEEP = ",operation_key,encounter_id,patient_id,patient_id_authority,event,ward,bed,event_time,source_system,source_message_id,payload_digest,prior_patient_id,prior_patient_id_authority,prior_encounter_id,";

Parameter MESSAGEKEEP = ",message_control_id,message_type,sending_application,sending_facility,receiving_application,message_time,hl7_version,message_version,event_recorded,event_occurred,patient_identifier,patient_class,assigned_location,visit_number,admit_time,prior_patient_identifier,prior_visit_number,merge_groups,prior_identifiers,notes,segment_count,doc_type,error,";

Parameter VALIDATIONKEEP = ",parsed,doc_type,schema_category,spec,error,note,message_version,route_category,route_standard,version_agrees,version_note,";

/// What a receiver's body keeps.
Parameter WARDKEEP = ",encounter_id,patient_id,patient_id_authority,state,ward,bed,location,version,epoch,history,error,status,http_status,read_http_status,";

/// What the occupied-bed section keeps (v1.28): the bed, since when, the occupant's encounter (a token) and their movement.
Parameter BEDCONFLICTKEEP = ",refused,ward,bed,since,occupant,occupant_movement,status,note,";

/// What the occupant's movement keeps: operational fields and the case about it.
Parameter MOVEMENTKEEP = ",event,ward,bed,event_time,operation_key,delivery,outcome,case_id,";

/// What a message pending ahead of a resend keeps (v1.29): operational fields, no content.
Parameter PENDINGKEEP = ",event,event_time,operation_key,control_id,ens_header_id,sent_at,receiver,where,";

/// What a history entry keeps (Downstream.Event.ToJSON: event, ward, event_time, applied_at, version_after, operation_key).
Parameter HISTORYKEEP = ",event,ward,bed,location,event_time,applied_at,version,version_before,version_after,operation_key,source_system,";

/// What a receipt keeps (Downstream.Receipt.ToJSON): all of it is operational.
Parameter RECEIPTKEEP = ",operation_key,encounter_id,event,ward,bed,event_time,applied_at,version_before,version_after,payload_digest,source_message_id,status,epoch,error,";

/// What the failure and the receiver's error keep.
Parameter FAILUREKEEP = ",kind,outcome,reason_code,http_status,status,text,error,message,ens_session_id,source_header_id,instruction_like,";

Parameter TIMELINEKEEP = ",event,ward,bed,event_time,operation_key,source_message_id,ens_header_id,ens_session_id,sent_at,source,later,this_case,outcome,reason_code,http_status,version_after,route,receiver,message_type,";

Parameter ROUTEKEEP = ",feed,connector,receiver,tier,category,history_policy,capabilities_source,declared,capabilities_http_status,capabilities,conditional_writes,receipts,dry_run,epoch,note,";

/// Keys whose string values are identifiers of the case, and the token kind each gives.
Parameter IDKEYS = ",patient_id:PID,encounter_id:ENC,encounter:ENC,visit_number:VISIT,visit:VISIT,nhs_number:NHS,mrn:MRN,prior_patient_id:PID,prior_encounter_id:ENC,prior_visit_number:VISIT,prior_patient_identifier:PID,";

/// Strings that come from outside and are kept: capped, and flagged when they read like an instruction.
Parameter OUTSIDEKEYS = ",text,error,message,detail,";

/// The token syntax, for the way back.
Parameter TOKENRE = "(MRN|NHS|PID|ENC|VISIT|NAME|DOB)-T[0-9]+";

// ---- what leaves ----

/// The model-facing copy of an object of the case. The original is not touched; the map is read, never extended.
ClassMethod Reduce(case As Shutter.Store.Case, obj As %DynamicAbstractObject) As %DynamicAbstractObject
{
    If '$ISOBJECT(obj) Quit obj
    Set copy = ##class(%DynamicAbstractObject).%FromJSON(obj.%ToJSON())
    Set freeText = ##class(Shutter.Store.SiteProfile).ModelFreeText()
    Kill map, byValue
    Set list = ##class(Shutter.Store.CaseToken).Map(case)
    For i = 1:1:$LISTLENGTH(list) { Set e = $LIST(list, i), map(i) = e, byValue($LIST(e, 2)) = $LIST(e, 1) }
    Set map = $LISTLENGTH(list)
    // Fail closed: a case whose own patient or encounter has no token was never learnt, or not completely.
    For value = case.PatientId, case.EncounterId {
        If ##class(Shutter.Store.CaseToken).Accepts("", value) && '$DATA(byValue(value)) Return {"error": ("The identifiers of case " _ case.CaseId _ " have no tokens yet, so nothing of it is shown to a model")}
    }
    Quit ..Walk(copy, "", freeText, .map, .byValue)
}

/// Reduce, on JSON text.
ClassMethod ReduceJSON(case As Shutter.Store.Case, json As %String) As %String
{
    Set obj = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(obj) || $$$ISERR(sc) Quit ..Tokenise(case, json)
    Quit ..Reduce(case, obj).%ToJSON()
}

/// What the model would see of a case's current evidence, as JSON: for the app, a test and the terminal. Learns the
/// case's identifiers as the business process does, in the same canonical order, and like it shows nothing when
/// learning fails.
ClassMethod Preview(caseId As %String) As %String [ SqlProc ]
{
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Quit {"error": ("Unknown case " _ caseId)}.%ToJSON()
    If '$ISOBJECT(case.CurrentSnapshot) Quit {"error": "The case has no evidence snapshot yet"}.%ToJSON()
    Set summary = case.CurrentSnapshot.SummaryObject()
    If '$ISOBJECT(summary) Quit {"error": "The snapshot has no summary"}.%ToJSON()
    Set sc = ..Learn(case, summary)
    If $$$ISERR(sc) Quit {"error": ("The model's view of the case could not be built: " _ $SYSTEM.Status.GetErrorText(sc))}.%ToJSON()
    Quit ..Reduce(case, summary).%ToJSON()
}

/// The rebuild: allowlists by shape, the denylist everywhere, notes flagged, identifiers replaced in string values and
/// in numbers equal to an identifier, outside strings capped and flagged.
ClassMethod Walk(node As %DynamicAbstractObject, parentKey As %String, freeText As %Boolean, ByRef map, ByRef byValue) As %DynamicAbstractObject [ Private ]
{
    If '$ISOBJECT(node) Quit node
    If node.%IsA("%DynamicArray") {
        Set out = [], iter = node.%GetIterator()
        While iter.%GetNext(.i, .v) {
            Set type = node.%GetTypeOf(i)
            If (type = "object") || (type = "array") { Do out.%Push(..Walk(v, parentKey, freeText, .map, .byValue)) }
            ElseIf type = "string" { Do out.%Push(..TokeniseWith(v, .map)) }
            ElseIf type = "number" { If $DATA(byValue(v)) { Do out.%Push(byValue(v)) } Else { Do out.%Push(v, "number") } }
            Else { Do out.%Push(v, type) }
        }
        Quit out
    }
    Set keep = ..KeepFor(node, parentKey)
    Set out = {}, iter = node.%GetIterator()
    While iter.%GetNext(.key, .v) {
        Set lkey = $ZCONVERT(key, "L"), type = node.%GetTypeOf(key)
        Continue:(..#DENYLIST [ ("," _ lkey _ ","))
        Continue:((keep '= "") && '(keep [ ("," _ lkey _ ",")))
        If (lkey = "notes") && (type = "array") {
            Do out.%Set(key, ..FlagNotes(v, freeText, .map))
            Continue
        }
        If (type = "object") || (type = "array") {
            Do out.%Set(key, ..Walk(v, lkey, freeText, .map, .byValue))
        } ElseIf type = "string" {
            Set s = ..TokeniseWith(v, .map)
            If ..#OUTSIDEKEYS [ ("," _ lkey _ ",") {
                Set s = $EXTRACT(s, 1, 1000)
                If ..InstructionLike(s) Do out.%Set("instruction_like", 1, "boolean")
            }
            Do out.%Set(key, s)
        } ElseIf type = "number" {
            If $DATA(byValue(v)) { Do out.%Set(key, byValue(v)) } Else { Do out.%Set(key, v, "number") }
        } Else {
            Do out.%Set(key, v, type)
        }
    }
    Quit out
}

/// The allowlist a node takes, by its shape (and its parent's key for history entries); "" for the denylist alone.
ClassMethod KeepFor(node As %DynamicObject, parentKey As %String) As %String [ Private ]
{
    If parentKey = "history" Quit ..#HISTORYKEEP
    If node.%IsDefined("ward_state_http_status") || (node.%IsDefined("operation") && node.%IsDefined("failure")) Quit ..#SUMMARYKEEP
    If node.%IsDefined("message_control_id") || node.%IsDefined("message_type") && node.%IsDefined("sending_application") Quit ..#MESSAGEKEEP
    If node.%IsDefined("parsed") && node.%IsDefined("spec") Quit ..#VALIDATIONKEEP
    If node.%IsDefined("applied_at") && node.%IsDefined("payload_digest") Quit ..#RECEIPTKEEP
    If node.%IsDefined("operation_key") && node.%IsDefined("payload_digest") Quit ..#OPERATIONKEEP
    If node.%IsDefined("operation_key") && (node.%IsDefined("sent_at") || node.%IsDefined("this_case")) Quit ..#TIMELINEKEEP
    If node.%IsDefined("refused") && node.%IsDefined("occupant_movement") Quit ..#BEDCONFLICTKEEP
    If node.%IsDefined("where") && node.%IsDefined("control_id") Quit ..#PENDINGKEEP
    If node.%IsDefined("delivery") && node.%IsDefined("event_time") && 'node.%IsDefined("sent_at") Quit ..#MOVEMENTKEEP
    If node.%IsDefined("state") || node.%IsDefined("history") Quit ..#WARDKEEP
    If node.%IsDefined("kind") && (node.%IsDefined("text") || node.%IsDefined("outcome")) && 'node.%IsDefined("data") && 'node.%IsDefined("item") && 'node.%IsDefined("items") Quit ..#FAILUREKEEP
    If node.%IsDefined("connector") && node.%IsDefined("capabilities_source") Quit ..#ROUTEKEEP
    If node.%IsDefined("namespace") && node.%IsDefined("header_id") Quit ..#SOURCEKEEP
    Quit ""
}

/// OBX and NTE notes as flags: that free text is there, and whether it reads like an instruction. With the site's
/// switch on, the text itself (identifiers, names and the birth date replaced by tokens, 500 characters at most),
/// never a binary or reference value (OBX-2 ED, RP).
ClassMethod FlagNotes(notes As %DynamicArray, freeText As %Boolean, ByRef map) As %DynamicArray [ Private ]
{
    Set out = [], iter = notes.%GetIterator()
    While iter.%GetNext(.i, .note) {
        Set flag = {}, text = "", vtype = ""
        If $ISOBJECT(note) {
            For k = "segment", "position", "observation_id", "value_type" { If note.%IsDefined(k) Do flag.%Set(k, note.%Get(k), note.%GetTypeOf(k)) }
            Set text = ##class(Shutter.Util.Json).Str(note, "text"), vtype = $ZCONVERT(##class(Shutter.Util.Json).Str(note, "value_type"), "U")
        } Else {
            Set text = note
        }
        Do flag.%Set("free_text_present", text '= "", "boolean")
        Do flag.%Set("instruction_like", ..InstructionLike(text), "boolean")
        If freeText && (text '= "") && (vtype '= "ED") && (vtype '= "RP") {
            Set flag.text = $EXTRACT(..TokeniseWith(text, .map), 1, 500)
        } Else {
            Set flag.note = $SELECT((vtype = "ED") || (vtype = "RP"): "A binary or reference value; it is never sent", 1: "The text stays in IRIS; it is not sent")
        }
        Do out.%Push(flag)
    }
    Quit out
}

/// Whether a text that came from outside reads like an instruction to a reader rather than data (a flag, not a
/// verdict): directives, role and markup markers, the run's own tool names.
ClassMethod InstructionLike(text As %String) As %Boolean
{
    If text = "" Quit 0
    Set t = " " _ $ZCONVERT($TRANSLATE(text, $CHAR(10, 13, 9), "   "), "L") _ " "
    For w = "ignore ", "disregard", "override", "instruction", "prompt", "assistant", "you must", "you should", "resend", "approve", "forget", "pretend", "system:", "human:", "act as", "important:", "urgent", "immediately", "note to", "<evidence", "```", "submitfindings", "submitplan", "getsnapshot", "getmessage", "ai " {
        If t [ w Quit
    }
    Quit t [ w
}

// ---- the map ----

/// The case's identifiers, each given its token, in a canonical order: the case's own patient and encounter first
/// (always T1 of their kinds), then everything else found in the message (every PID-3 repetition, the name parts, the
/// date of birth) and in the object (patient_id, encounter_id, visit_number, nhs_number values, the pieces of every
/// operation key) sorted by kind and value, so the same evidence gives the same tokens in every run. Run once per case
/// by the business process (and by Preview); Reduce never learns. An error when the message could not be read or a
/// value that takes a token could not be given one: the caller then sends nothing to a model.
ClassMethod Learn(case As Shutter.Store.Case, obj As %DynamicAbstractObject) As %Status
{
    Kill cand
    Set patientKind = ..LearnMessage(case, .cand, .sc)
    Quit:$$$ISERR(sc) sc
    If case.PatientId '= "" Set sc = ..Assign(case, patientKind, case.PatientId)
    If $$$ISOK(sc) && (case.EncounterId '= "") Set sc = ..Assign(case, "ENC", case.EncounterId)
    Quit:$$$ISERR(sc) sc
    Do ..Collect(obj, .cand, case, 0)
    Set kind = ""
    For {
        Set kind = $ORDER(cand(kind)) Quit:kind=""
        Set value = ""
        For {
            Set value = $ORDER(cand(kind, value)) Quit:value=""
            Set sc = ..Assign(case, kind, value)
            Quit:$$$ISERR(sc)
        }
        Quit:$$$ISERR(sc)
    }
    Quit sc
}

/// A value's token, made on first sight; an error when the value takes a token and none could be stored.
ClassMethod Assign(case As Shutter.Store.Case, kind As %String, value As %String) As %Status [ Private ]
{
    If ##class(Shutter.Store.CaseToken).Assign(case, kind, value) '= "" Quit $$$OK
    If '##class(Shutter.Store.CaseToken).Accepts(kind, value) Quit $$$OK
    Quit $$$ERROR($$$GeneralError, "No token could be stored for a " _ kind _ " value of case " _ case.CaseId)
}

/// The message's identifiers (every PID-3 repetition, typed by PID-3.5), the name parts (PID-5) and the date of birth
/// (PID-7, as written and as ISO), and for a merge the prior patient's identifiers (MRG-1, every repetition, typed by
/// CX.5), visit number (MRG-5) and name parts (MRG-7) from every MRG segment, as candidates; returns the kind of the
/// case's own patient identifier. A name part counts from two letters (a single initial is left: as a token it would
/// replace every standalone letter of a text). sc is an error when the case names a message that cannot be read, or
/// reading it failed: its names would then reach a model unreplaced.
ClassMethod LearnMessage(case As Shutter.Store.Case, ByRef cand, Output sc As %Status) As %String [ Private ]
{
    Set kind = "MRN", sc = $$$OK
    Try {
        Set header = $SELECT(case.SourceHeaderId '= "": ##class(Ens.MessageHeader).%OpenId(case.SourceHeaderId), 1: "")
        If (case.SourceHeaderId '= "") && '$ISOBJECT(header) Set sc = $$$ERROR($$$GeneralError, "The message header " _ case.SourceHeaderId _ " of case " _ case.CaseId _ " cannot be read")
        If $ISOBJECT(header) {
            Set msg = ##class(EnsLib.HL7.Message).%OpenId(header.MessageBodyId)
            If '$ISOBJECT(msg) Set sc = $$$ERROR($$$GeneralError, "The HL7 message of case " _ case.CaseId _ " cannot be read")
            If $ISOBJECT(msg) {
                Set reps = +##class(Shutter.Util.OperationKey).Value(msg, "PID", "3(*)")
                For r = 1:1:reps {
                    Set id = ##class(Shutter.Util.OperationKey).Value(msg, "PID", "3(" _ r _ ").1"), type = $ZCONVERT(##class(Shutter.Util.OperationKey).Value(msg, "PID", "3(" _ r _ ").5"), "U")
                    Continue:id=""
                    Set k = $CASE(type, "MR": "MRN", "NH": "NHS", "NHS": "NHS", "NI": "NHS", : "PID")
                    If id = case.PatientId { Set kind = k } Else { Set cand(k, id) = "" }
                }
                Set names = +##class(Shutter.Util.OperationKey).Value(msg, "PID", "5(*)")
                For r = 1:1:names {
                    For c = 1, 2, 3 {
                        Set part = $ZSTRIP(##class(Shutter.Util.OperationKey).Value(msg, "PID", "5(" _ r _ ")." _ c), "<>W")
                        If $LENGTH(part) >= 2 Set cand("NAME", part) = ""
                    }
                }
                Set dob = $ZSTRIP(##class(Shutter.Util.OperationKey).Value(msg, "PID", "7.1"), "<>W")
                If $LENGTH(dob) >= 8 {
                    Set cand("DOB", $EXTRACT(dob, 1, 8)) = ""
                    Set cand("DOB", $EXTRACT(dob, 1, 4) _ "-" _ $EXTRACT(dob, 5, 6) _ "-" _ $EXTRACT(dob, 7, 8)) = ""
                    If $LENGTH(dob) > 8 Set cand("DOB", dob) = ""
                }
                // A merge (ADT^A40): every MRG segment, one per PATIENT group (a bare "MRG" path reads the first only),
                // so every prior identifier, the prior visit number and the prior name parts become tokens too.
                Set index = ""
                For {
                    Set mrg = msg.FindSegment("MRG", .index)
                    Quit:'$ISOBJECT(mrg)
                    Set reps = +mrg.GetValueAt("1(*)")
                    For r = 1:1:reps {
                        Set id = mrg.GetValueAt("1(" _ r _ ").1"), type = $ZCONVERT(mrg.GetValueAt("1(" _ r _ ").5"), "U")
                        If (id '= "") && (id '= case.PatientId) Set cand($CASE(type, "MR": "MRN", "NH": "NHS", "NHS": "NHS", "NI": "NHS", : "PID"), id) = ""
                    }
                    Set visit = $ZSTRIP(mrg.GetValueAt("5.1"), "<>W")
                    If (visit '= "") && (visit '= case.EncounterId) Set cand("VISIT", visit) = ""
                    Set names = +mrg.GetValueAt("7(*)")
                    For r = 1:1:names {
                        For c = 1, 2, 3 {
                            Set part = $ZSTRIP(mrg.GetValueAt("7(" _ r _ ")." _ c), "<>W")
                            If $LENGTH(part) >= 2 Set cand("NAME", part) = ""
                        }
                    }
                }
            }
        }
    } Catch ex {
        Set sc = $$$ERROR($$$GeneralError, "The message of case " _ case.CaseId _ " could not be read for its identifiers: " _ ex.DisplayString())
    }
    Quit kind
}

/// Candidates from an object: the values of identifier keys, the first piece of a composite patient identifier (the
/// case's, or a merge's prior one), and the patient and encounter pieces of every operation key
/// (source^authority^patient^encounter^event^time).
ClassMethod Collect(node As %DynamicAbstractObject, ByRef cand, case As Shutter.Store.Case, depth As %Integer) [ Private ]
{
    If '$ISOBJECT(node) || (depth > 12) Quit
    Set isArray = node.%IsA("%DynamicArray")
    Set iter = node.%GetIterator()
    While iter.%GetNext(.key, .value) {
        Set type = node.%GetTypeOf(key)
        If (type = "object") || (type = "array") { Do ..Collect(value, .cand, case, depth + 1) Continue }
        Continue:isArray
        Continue:(type'="string")&&(type'="number")
        Set lkey = $ZCONVERT(key, "L")
        If (lkey = "operation_key") && ($LENGTH(value, "^") >= 4) {
            Set pid = $PIECE(value, "^", 3), enc = $PIECE(value, "^", 4)
            If ($LENGTH(pid) >= 3) && (pid '= case.PatientId) Set cand("PID", pid) = ""
            If ($LENGTH(enc) >= 3) && (enc '= case.EncounterId) Set cand("ENC", enc) = ""
            Continue
        }
        If (lkey = "patient_identifier") || (lkey = "prior_patient_identifier") {
            Set pid = $PIECE(value, "^", 1)
            If ($LENGTH(pid) >= 3) && (pid '= case.PatientId) Set cand("PID", pid) = ""
            Continue
        }
        Set kind = $PIECE($PIECE(..#IDKEYS, "," _ lkey _ ":", 2), ",", 1)
        Continue:kind=""
        Continue:$LENGTH(value)<3
        Continue:(value=case.PatientId)||(value=case.EncounterId)
        Set cand(kind, value) = ""
    }
}

// ---- the replacement ----

/// Every identifier of the case replaced by its token in a text (the map read for this call).
ClassMethod Tokenise(case As Shutter.Store.Case, text As %String) As %String
{
    Kill map
    Set list = ##class(Shutter.Store.CaseToken).Map(case)
    For i = 1:1:$LISTLENGTH(list) { Set map(i) = $LIST(list, i) }
    Set map = $LISTLENGTH(list)
    Quit ..TokeniseWith(text, .map)
}

ClassMethod TokeniseWith(text As %String, ByRef map) As %String [ Private ]
{
    If text = "" Quit text
    // Whatever the case from three characters; a two-letter name part only as written.
    For i = 1:1:+$GET(map) { Set text = ..ReplaceBounded(text, $LIST(map(i), 2), $LIST(map(i), 1), $LENGTH($LIST(map(i), 2)) > 2) }
    Quit text
}

/// Every token of the case replaced by its value: what the model said, as people and the gate must read it. Tokens
/// hold no character JSON escapes, so the model's JSON can be restored as text.
ClassMethod Restore(case As Shutter.Store.Case, text As %String) As %String
{
    If (text = "") || '$ISOBJECT(case) Quit text
    Set list = ##class(Shutter.Store.CaseToken).Map(case)
    For i = 1:1:$LISTLENGTH(list) {
        Set e = $LIST(list, i)
        Set text = ..ReplaceBounded(text, $LIST(e, 1), $LIST(e, 2))
    }
    Quit text
}

/// The tokens left in a text after Restore (ones the case has no value for), as a comma list; "" when none.
ClassMethod Unresolved(text As %String) As %String
{
    Set out = "", pos = 1, pattern = "(?<![A-Za-z0-9_-])" _ ..#TOKENRE _ "(?![A-Za-z0-9_-])"
    For {
        Set at = $LOCATE(text, pattern, pos, after, found)
        Quit:at=0
        If '$LISTFIND($LISTFROMSTRING(out, ","), found) Set out = out _ $SELECT(out = "": "", 1: ",") _ found
        Set pos = after
    }
    Quit out
}

/// Replace a value by another wherever it stands as a whole identifier (not inside a longer run of letters, digits,
/// hyphens or underscores), whatever its case when caseless is set (the way out: a name written "SMITH" in the message
/// and "Smith" in an error echo). The value is quoted for the regular expression piece by piece, so a \E inside it is
/// safe.
ClassMethod ReplaceBounded(text As %String, value As %String, by As %String, caseless As %Boolean = 0) As %String
{
    If value = "" Quit text
    If caseless { Quit:'($ZCONVERT(text, "U") [ $ZCONVERT(value, "U")) text } Else { Quit:'(text [ value) text }
    Set quoted = ""
    For p = 1:1:$LENGTH(value, "\E") { Set quoted = quoted _ $SELECT(p > 1: "\\E", 1: "") _ "\Q" _ $PIECE(value, "\E", p) _ "\E" }
    Set pattern = $SELECT(caseless: "(?i)", 1: "") _ "(?<![A-Za-z0-9_-])" _ quoted _ "(?![A-Za-z0-9_-])"
    Set out = "", pos = 1
    For {
        Set at = $LOCATE(text, pattern, pos, after)
        Quit:at=0
        Set out = out _ $EXTRACT(text, pos, at - 1) _ by, pos = after
    }
    Quit out _ $EXTRACT(text, pos, *)
}

}
