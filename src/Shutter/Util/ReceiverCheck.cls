/// What to check at the receiver on a stopped case (CONTRACTS 5.2): a read-only card built from the case's own fields, a
/// short allowlist of the snapshot's and the site profile's, and a few named fields of the stored message. It calls no
/// model and no receiver, and writes nothing. Nothing is serialised from the snapshot, so no document or note can come
/// through: OBX, NTE and names are never read. The case's FailureText and the bed conflict are left out too, since a
/// refusal can name the patient in the bed. Words come from the Words block, one version for the server and the demo.
Class Shutter.Util.ReceiverCheck
{

/// The card's words (version 1). web/src/mocks/receiver-check-words.json is a copy for the demo, and a test holds them equal.
XData Words [ MimeType = application/json ]
{
{
  "version": "1",
  "missing": "Not available from this message",
  "no_encounter": "No encounter supplied",
  "evidence": {
    "no_api": "Shutter cannot read this receiving system. These checks come from the failed message and Shutter's records, and don't show what the receiver holds now.",
    "unreadable": "Shutter could not read this encounter at the receiver. These checks come from the failed message and Shutter's records, and don't show what the receiver holds now.",
    "documents": "Shutter cannot read this receiver's documents or reports. These checks come from the failed message and Shutter's records, and don't show what the receiver holds now.",
    "read": "The receiver evidence below was read at {at}. It may have changed since then."
  },
  "queue": "Before correcting anything: check whether the original message is still queued, retrying or awaiting an application acknowledgement. It may still arrive.",
  "report": "Put what you find in the reason when you mark the case handled. That stays a person's report: it isn't verified and doesn't authorise a resend.",
  "asked_note": "A later valid change may mean that this is no longer the correct current state.",
  "several_items": "This message contains more than one report or document item. Check the original message and each item; this card does not establish that all were filed.",
  "other_message": "This card has no specific check for this message type. Check the original in the source's Message Viewer.",
  "later_known": "A later message for this encounter is on Shutter's record.",
  "time_doubtful": "Whether the event time is true: an event in this encounter's order can't have happened then.",
  "bed_occupied": "The receiver reported the requested bed as occupied.",
  "refused": "The receiver refused this message.",
  "document_asked": "File this document against the patient and episode named here.",
  "result_asked": "File this report against the patient and order named here.",
  "attempted": "The send got no answer.",
  "variants": {
    "manual_compare": {
      "where": "The encounter's details, then its movement history.",
      "compare": ["Patient number and authority", "Visit number", "State", "Ward", "Bed", "Effective time"],
      "meanings": {
        "present": ["It shows what the message asked", "A person's observation that fits. It doesn't show that this message caused it."],
        "absent": ["Nothing of this movement", "Unresolved: it may be missing, or may still arrive. Correct it only by the site's agreed procedure; this alone doesn't authorise a resend."],
        "different": ["A different or later placement", "Read the movement history in time order before correcting anything."],
        "cannot_tell": ["No encounter, several, or conflicting identity", "Stop and resolve the identity first."]
      },
      "unknown": ["Whether the original can still arrive.", "Without a movement history, a current placement doesn't show what became of this message."]
    },
    "later_movement": {
      "note": "This movement belongs at its own time, not necessarily as the current placement. Never move the patient back to make this message true.",
      "where": "The current placement and the movement history, including the later movement.",
      "compare": ["Patient number and authority", "Visit number", "Ward", "Bed", "Effective time", "The later movement"],
      "meanings": {
        "present": ["This movement is in the history at its time", "It fits this message arriving or being entered another way. It doesn't show which."],
        "absent": ["This movement is missing from the history", "At a current-state receiver, a correct later placement may be enough for manual handling. At a history-of-record receiver the gap can still need correcting."],
        "different": ["The placement differs from both", "Read the history in time order before correcting anything."],
        "cannot_tell": ["No history you can see", "The current placement may be known while this message's fate stays unknown."]
      },
      "unknown": ["Whether the original can still arrive."]
    },
    "already_applied": {
      "note": "The receiver's own receipt or history names this operation.",
      "where": "The encounter and the recorded event at the receiver.",
      "compare": ["Patient number and authority", "Visit number", "Ward", "Bed", "Event time"],
      "meanings": {
        "present": ["The screen matches", "A person's observation that supports the receiver's record. Keep the two apart."],
        "absent": ["The event isn't on the screen", "Investigate: the screen and the record disagree. This doesn't authorise a resend."],
        "different": ["The screen contradicts it", "Investigate. Don't discard the receipt, and this doesn't authorise a resend."],
        "cannot_tell": ["You can't tell", "Keep the case stopped and escalate."]
      },
      "unknown": ["Whether anything changed at the receiver after that read."]
    },
    "refusal": {
      "note": "This card shows no other patient's details: see the receiver's own screens.",
      "where": "Placement details and the site's bed or occupancy view.",
      "compare": ["Requested ward", "Requested bed", "What the occupancy view shows now"],
      "meanings": {
        "present": ["The patient is in the requested place", "A person's observation that fits. It doesn't show that this message caused it."],
        "absent": ["The place is now free", "That alone doesn't authorise the old move: check that it still applies."],
        "different": ["It is still occupied", "Unresolved. Follow the site's bed procedure."],
        "cannot_tell": ["You can't tell", "Keep the case stopped and escalate."]
      },
      "unknown": ["Why the receiver refused, beyond what it said.", "Whether the move still applies."]
    },
    "identity_or_time": {
      "note": "Only the fields Shutter could read reliably are shown as read.",
      "where": "The source's registration or message, then a patient and episode search at the receiver.",
      "compare": ["Patient number and authority", "Visit number", "Event time at the source"],
      "meanings": {
        "present": ["One clear match", "Compare it with the message, then resolve the mapping or the time at the source."],
        "absent": ["No match", "Don't create an encounter. Resolve the identity or the mapping first."],
        "different": ["Several, or conflicting", "Don't guess which record was meant. Resolve the identity first."],
        "cannot_tell": ["The time can't be settled", "Ask the source which time is right before correcting anything."]
      },
      "unknown": ["Which record or time the message meant."]
    },
    "uncertain": {
      "where": "The queue or message trace, the receiver's event history, and any receipt or application audit you can see.",
      "compare": ["Patient number and authority", "Visit number", "Ward", "Bed", "Effective time", "When it was sent"],
      "meanings": {
        "present": ["The screen shows it", "This doesn't show the attempt has finished, or that this attempt made it."],
        "absent": ["The screen doesn't show it", "This doesn't show that it can't arrive later."],
        "different": ["Something different", "Read the history in time order before correcting anything."],
        "cannot_tell": ["You can't tell", "Keep the case stopped and escalate."]
      },
      "unknown": ["Whether the attempt was applied, or still can be."]
    },
    "history_correction": {
      "note": "Two things, kept apart: this missing movement at its own time, and the later placement, which stays.",
      "where": "The movement history, and the receiver's approved route for correcting history.",
      "compare": ["Patient number and authority", "Visit number", "This movement's ward, bed and time", "The later movement"],
      "meanings": {
        "present": ["This movement is in the history", "Nothing is missing on this screen. Report what you saw."],
        "absent": ["It is missing", "Correct the history by the receiver's own route, keeping the current placement."],
        "different": ["The history differs", "Read it in time order before correcting anything."],
        "cannot_tell": ["You can't see the history", "Ask the receiver's team. This card doesn't know their procedure."]
      },
      "unknown": ["The receiver's correction procedure.", "Whether the original can still arrive."]
    },
    "document": {
      "where": "The document list, and the rejected or unfiled queue if the site uses one.",
      "compare": ["Patient number and authority", "Encounter", "Document number", "Type", "Document time", "Status", "Whether it opens"],
      "meanings": {
        "present": ["Filed against the right record, and it opens", "A person's report that it was handled. A matching title alone is weak."],
        "absent": ["Missing", "Unresolved. Don't re-enter it while the original may still arrive."],
        "different": ["Unreadable, duplicated or on another record", "Unresolved: that isn't a successful filing."],
        "cannot_tell": ["You can't tell", "Open the original in the source's Message Viewer, and escalate."]
      },
      "unknown": ["Whether this document reached the receiver.", "Whether the original can still arrive."]
    },
    "result": {
      "where": "The patient's report list, and the rejected or unfiled queue if the site uses one.",
      "compare": ["Patient number and authority", "Encounter", "Order or report number", "Test", "Observation time", "Status", "Whether it opens"],
      "meanings": {
        "present": ["Filed against the right record, and it opens", "A person's report that it was handled. A matching test name alone is weak."],
        "absent": ["Missing", "Unresolved. Don't re-enter it while the original may still arrive."],
        "different": ["Unreadable, duplicated or on another record", "Unresolved: that isn't a successful filing."],
        "cannot_tell": ["You can't tell", "Open the original in the source's Message Viewer, and escalate."]
      },
      "unknown": ["Whether this report reached the receiver.", "Whether the original can still arrive."]
    },
    "withheld": {
      "note": "Shutter never sends this by itself.",
      "where": "The site's identity or cancellation procedure.",
      "compare": ["Patient number and authority", "Visit number", "What was requested"],
      "meanings": {
        "present": ["Already done by hand", "A person owns the decision. This card neither approves it nor proves its effect."],
        "absent": ["Not done", "A person decides whether to apply it, in the systems concerned."],
        "different": ["Something else was done", "Check the records concerned, and escalate."],
        "cannot_tell": ["You can't tell", "Keep the case stopped and escalate."]
      },
      "unknown": ["The effect of this operation at the receiver."]
    },
    "other_message": {
      "where": "The source's Message Viewer, then the receiver.",
      "compare": ["Patient number and authority", "Message type", "Control id"],
      "meanings": {
        "present": ["You find it at the receiver", "A person's report. It doesn't show that this message caused it."],
        "absent": ["You don't", "Unresolved. Don't re-enter it while the original may still arrive."],
        "different": ["Something different", "Check the original before correcting anything."],
        "cannot_tell": ["You can't tell", "Keep the case stopped and escalate."]
      },
      "unknown": ["What this message did at the receiver."]
    }
  }
}
}

/// The card's versioned words: their text (with its digest in the card) as one object.
ClassMethod Words(Output text As %String) As %DynamicObject
{
    Set x = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Words", 0)
    Set text = ""
    Do x.Data.Rewind()
    While 'x.Data.AtEnd { Set text = text _ x.Data.Read(32000) }
    Quit ##class(%DynamicObject).%FromJSON(text)
}

/// The card for a stopped case: an allowlist, field by field. It has no verified, safe-to-resend or action field.
ClassMethod ForCase(case As Shutter.Store.Case) As %DynamicObject
{
    Set words = ..Words(.text)
    Set snap = case.CurrentSnapshot
    Set summary = $SELECT($ISOBJECT(snap): snap.SummaryObject(), 1: "")
    If '$ISOBJECT(summary) Set summary = {}
    Set meta = ..MessageFacts(case)
    Set later = ..LaterMovement(case, summary)
    Set variant = ..Variant(case, summary)
    Set profile = ##class(Shutter.Store.SiteProfile).Current()
    Set vw = words.variants.%Get(variant)

    Set out = {}
    Set out.caseId = case.CaseId
    Do out.%Set("caseVersion", +case.Version, "number")
    Set out.snapshotId = $SELECT($ISOBJECT(snap): "" _ snap.%Id(), 1: "")
    Do out.%Set("profileVersion", +##class(Shutter.Util.Json).Str(profile, "version", 0), "number")
    Set out.guideVersion = words.version
    Set out.guideDigest = ##class(Shutter.Util.Digest).SHA256Hex(text)
    Set out.variant = variant
    Do ..Evidence(case, summary, variant, words, out)
    Set out.identity = ..Identity(case, summary, meta, words)
    Set out.messageRequest = ..Request(case, summary, variant, meta, words)
    If (variant = "later_movement") || (variant = "history_correction") {
        Set out.laterMovement = later
    } Else {
        Do out.%Set("laterMovement", "", "null")
    }
    Set out.queueWarning = words.queue
    Set check = {"id": (variant), "where": (vw.where), "compare": (vw.compare)}
    Set meanings = [], it = $LISTBUILD("present", "absent", "different", "cannot_tell")
    For i = 1:1:$LISTLENGTH(it) {
        Set answer = $LIST(it, i), m = vw.meanings.%Get(answer)
        Do meanings.%Push({"answer": (answer), "label": (m.%Get(0)), "text": (m.%Get(1))})
    }
    Set check.meanings = meanings
    Set out.checks = []
    Do out.checks.%Push(check)
    Set runbook = ..RunbookIn(profile, case.Receiver)
    If runbook '= "" { Set out.siteRunbook = runbook } Else { Do out.%Set("siteRunbook", "", "null") }
    Set unknown = [], ui = vw.unknown.%GetIterator()
    If (variant = "identity_or_time") && ..TimeDoubtful(case, summary) Do unknown.%Push(words."time_doubtful")
    While ui.%GetNext(, .u) { Do unknown.%Push(u) }
    Set out.unknown = unknown
    Set limits = []
    If +meta.items > 1 Do limits.%Push(words."several_items")
    If variant = "other_message" Do limits.%Push(words."other_message")
    Set out.limitations = limits
    Set out.report = words.report
    Quit out
}

/// Which card a stopped case gets. These read the case; they decide nothing, and no gate reads them.
ClassMethod Variant(case As Shutter.Store.Case, summary As %DynamicObject) As %String
{
    If case.FailureKind = "withheld" Quit "withheld"
    // The two everyone sees, an MDM^T02 and an ORU^R01. Other messages get the general words only.
    If case.Event = "T02" Quit "document"
    If case.Event = "R01" Quit "result"
    If case.NotModelled() Quit "other_message"
    If ##class(Shutter.Util.EscalationDraft).LatestAttemptOutcome(case) = "uncertain" Quit "uncertain"
    Set reason = ..ReasonCode(case)
    If ..HasReceipt(case, summary) || (reason = "ALREADY_COMMITTED") Quit "already_applied"
    If case.FailureKind = "uncertain_outcome" Quit "uncertain"
    If reason = "WRITE_OUTCOME_UNKNOWN" Quit "uncertain"
    Set cat = summary.%Get("catalogue")
    Set entry = $SELECT($ISOBJECT(cat): ##class(Shutter.Util.Json).Str(cat, "entry"), 1: "")
    If $LISTFIND($LISTBUILD("unmappable", "unreadable"), case.FailureKind) || $LISTFIND($LISTBUILD("E11", "E12", "E13", "E18"), entry) || $LISTFIND($LISTBUILD("PARSE_FAILED", "SCHEMA_UNKNOWN", "UNMAPPABLE", "UNKNOWN_ENCOUNTER", "NO_ENCOUNTER", "PATIENT_MISMATCH", "EVENT_TIME_IMPLAUSIBLE"), reason) Quit "identity_or_time"
    If (case.FailureKind = "rejected") || $ISOBJECT(summary.%Get("bed_conflict")) || $LISTFIND($LISTBUILD("BED_OCCUPIED", "OCCUPANT_CASE_FAILED", "WAITING_FOR_OCCUPANT_CASE"), reason) Quit "refusal"
    Set plan = $SELECT($ISOBJECT(case.CurrentPlan): case.CurrentPlan.PlanObject(), 1: "")
    If $ISOBJECT(plan) && $ISOBJECT(plan.%Get("correction_steps")) Quit "history_correction"
    If $ISOBJECT(..LaterMovement(case, summary)) Quit "later_movement"
    Quit "manual_compare"
}

ClassMethod ReasonCode(case As Shutter.Store.Case) As %String [ Private ]
{
    Set reason = ##class(Shutter.Util.EscalationDraft).Reason(case, .failing)
    Quit $SELECT($ISOBJECT(reason): reason.Code, 1: "")
}

/// A receipt the receiver gave for this operation, never a matching location.
ClassMethod HasReceipt(case As Shutter.Store.Case, summary As %DynamicObject) As %Boolean [ Private ]
{
    Set receipt = summary.%Get("receipt")
    If '$ISOBJECT(receipt) || (+summary.%Get("receipt_http_status") '= 200) Quit 0
    Quit ##class(Shutter.Util.Json).Str(receipt, "operation_key") = case.OperationKey
}

ClassMethod TimeDoubtful(case As Shutter.Store.Case, summary As %DynamicObject) As %Boolean [ Private ]
{
    Set cat = summary.%Get("catalogue")
    If $ISOBJECT(cat) && (##class(Shutter.Util.Json).Str(cat, "entry") = "E13") Quit 1
    Quit ..ReasonCode(case) = "EVENT_TIME_IMPLAUSIBLE"
}

/// Sets receiverEvidence, evidenceNote and receiverRead: only this encounter's own state, and only when it was read.
ClassMethod Evidence(case As Shutter.Store.Case, summary As %DynamicObject, variant As %String, words As %DynamicObject, out As %DynamicObject) [ Private ]
{
    Set json = "Shutter.Util.Json"
    Set state = summary.%Get("ward_state")
    Set read = $ISOBJECT(state) && (+summary.%Get("ward_state_http_status") = 200) && ($CLASSMETHOD(json, "Str", state, "state") '= "") && ($CLASSMETHOD(json, "Str", state, "encounter_id") = case.EncounterId)
    If (variant = "document") || (variant = "result") || (variant = "other_message") {
        Set out.receiverEvidence = "unavailable", out.evidenceNote = words.evidence.documents
        Do out.%Set("receiverRead", "", "null")
        Quit
    }
    If read {
        Set at = ..When($CLASSMETHOD(json, "Str", summary, "observed_at"))
        Set out.receiverEvidence = "read", out.evidenceNote = $REPLACE(words.evidence.read, "{at}", at)
        Set out.receiverRead = {"at": (at), "state": ($CLASSMETHOD(json, "Str", state, "state")), "ward": ($CLASSMETHOD(json, "Str", state, "ward")), "bed": ($CLASSMETHOD(json, "Str", state, "bed"))}
        Quit
    }
    Set out.receiverEvidence = "unavailable"
    Set out.evidenceNote = $SELECT(##class(Shutter.Store.SiteProfile).ReceiverPath(case.Receiver, "state") = "": words.evidence."no_api", 1: words.evidence.unreadable)
    Do out.%Set("receiverRead", "", "null")
}

ClassMethod Identity(case As Shutter.Store.Case, summary As %DynamicObject, meta As %DynamicObject, words As %DynamicObject) As %DynamicObject [ Private ]
{
    Set missing = words.missing
    Set o = {}
    Set o.patientId = ..Or(case.PatientId, missing), o.authority = ..Or(case.PatientIdAuthority, missing)
    Set o.encounterId = $SELECT((case.EncounterId = "") || (case.EncounterId = "-"): words."no_encounter", 1: case.EncounterId)
    Set o.receiver = ..Or(case.Receiver, missing), o.sourceSystem = ..Or(case.SourceSystem, missing)
    Set o.messageType = ..Or(meta.messageType, missing), o.controlId = ..Or(case.SourceMessageId, missing)
    // A message with no EVN has no event time of its own: the case's is its message time (OperationKey.Unmapped).
    Set o.timeLabel = $SELECT(case.NotModelled() || $LISTFIND($LISTBUILD("T02", "R01"), case.Event): "Message time", 1: "Event time")
    Set o.time = ..Or(..When(case.EventTime), missing)
    Set o.messageRef = ..Or(case.SourceHeaderId, missing)
    Set o.sourceRoute = ..Or(case.SourceRoute, missing)
    Set o.collectedAt = ..Or(..When(##class(Shutter.Util.Json).Str(summary, "observed_at")), missing)
    Quit o
}

/// "What this message asked the receiver to record", from the message's fields, each marked where it came from.
ClassMethod Request(case As Shutter.Store.Case, summary As %DynamicObject, variant As %String, meta As %DynamicObject, words As %DynamicObject) As %DynamicObject [ Private ]
{
    Set o = {}, fields = []
    Set o.kind = case.Event
    Set o.note = ""
    If $LISTFIND($LISTBUILD("document", "result"), variant) {
        Set o.summary = $SELECT(variant = "document": words."document_asked", 1: words."result_asked")
        Do ..Facts(meta.fields, fields, words)
        Set o.fields = fields
        Quit o
    }
    If variant = "other_message" {
        Set o.summary = "A " _ ..Or(meta.messageType, "message") _ " to the receiver."
        Set o.fields = fields
        Quit o
    }
    Set o.summary = ##class(Shutter.Util.EscalationDraft).EventLine(case.Event, case.Ward, case.EventTime, case) _ "."
    If variant = "refusal" Set o.summary = o.summary _ " " _ $SELECT((case.FailureReasonCode = "bed_occupied") || $ISOBJECT(summary.%Get("bed_conflict")): words."bed_occupied", 1: words.refused)
    If variant = "uncertain" Set o.summary = o.summary _ " " _ words.attempted
    Set timeSource = $SELECT((variant = "identity_or_time") && ..TimeDoubtful(case, summary): "doubtful", 1: "message")
    Set unsure = (case.FailureKind = "unmappable") || (case.FailureKind = "unreadable") || (..ReasonCode(case) = "PARSE_FAILED")
    Set source = $SELECT(unsure: "doubtful", 1: "message")
    If $LISTFIND($LISTBUILD("admit", "transfer", "update", "cancel_transfer", "cancel_admit"), case.Event) {
        Do ..Row(fields, "Ward", case.Ward, source, words)
        Do ..Row(fields, "Bed", case.Bed, source, words)
    }
    Do ..Row(fields, "Effective time", ..When(case.EventTime), $SELECT(unsure: "doubtful", 1: timeSource), words)
    Set o.fields = fields
    Set vw = words.variants.%Get(variant)
    Set note = ##class(Shutter.Util.Json).Str(vw, "note")
    Set o.note = $SELECT(note '= "": note, variant = "withheld": "", 1: words."asked_note")
    Quit o
}

ClassMethod Facts(rows As %DynamicArray, fields As %DynamicArray, words As %DynamicObject) [ Private ]
{
    Set it = rows.%GetIterator()
    While it.%GetNext(, .r) { Do ..Row(fields, r.label, r.value, "message", words) }
}

ClassMethod Row(fields As %DynamicArray, label As %String, value As %String, source As %String, words As %DynamicObject) [ Private ]
{
    If value = "" { Do fields.%Push({"label": (label), "value": (words.missing), "source": "unavailable"}) Quit }
    Do fields.%Push({"label": (label), "value": (value), "source": (source)})
}

/// The stored message's type, and for a T02 or an ORU^R01 its few named fields: TXA and OBR only, never OBX or NTE. Empty
/// when no copy is held. items counts the reports or documents the message carries. A document case reads its block instead,
/// by the reader's right: the block is what a document profile lets a person see, and the header may be another namespace's.
ClassMethod MessageFacts(case As Shutter.Store.Case) As %DynamicObject
{
    Set out = {"messageType": "", "items": 0}
    Set out.fields = []
    If case.Event = "T02" {
        Set rows = $LISTBUILD("Document number", "Document type", "Document time", "Status")
    } ElseIf case.Event = "R01" {
        Set rows = $LISTBUILD("Order or report number", "Test", "Observation time", "Status")
    } Else {
        Set rows = ""
    }
    Set values = ""
    If case.DocumentJSON '= "" {
        Do ..BlockFacts(case, .rows, .values, out)
        For i = 1:1:$LISTLENGTH(rows) { Do out.fields.%Push({"label": ($LIST(rows, i)), "value": ($LISTGET(values, i))}) }
        Quit out
    }
    Try {
        Set header = $SELECT(case.SourceHeaderId = "": "", 1: ##class(Ens.MessageHeader).%OpenId(case.SourceHeaderId))
        Quit:'$ISOBJECT(header)
        Set msg = ##class(EnsLib.HL7.Message).%OpenId(header.MessageBodyId)
        Quit:'$ISOBJECT(msg)
        // By segment too: a stored copy no schema typed answers nothing to the named path.
        Set type = ..Narrow(##class(Shutter.Util.OperationKey).Value(msg, "MSH", "9.1")), trigger = ..Narrow(##class(Shutter.Util.OperationKey).Value(msg, "MSH", "9.2"))
        If type '= "" Set out.messageType = type _ $SELECT(trigger '= "": "^" _ trigger, 1: "")
        Set zone = ##class(Shutter.Store.SiteProfile).FeedTimeZone()
        If case.Event = "T02" {
            Set i = "", n = 0, seg = msg.FindSegment("TXA", .i), first = seg
            While $ISOBJECT(seg) { Set n = n + 1, seg = msg.FindSegment("TXA", .i) }
            Do out.%Set("items", n, "number")
            If $ISOBJECT(first) Set values = $LISTBUILD(..Narrow(first.GetValueAt("12.1")), ..Narrow(first.GetValueAt("2.1")), ..When(##class(Shutter.Util.Time).FromHL7(first.GetValueAt("4.1"), zone)), ..Narrow(first.GetValueAt("17.1")))
        } ElseIf case.Event = "R01" {
            Set i = "", n = 0, seg = msg.FindSegment("OBR", .i), first = seg
            While $ISOBJECT(seg) { Set n = n + 1, seg = msg.FindSegment("OBR", .i) }
            Do out.%Set("items", n, "number")
            Set j = "", orc = msg.FindSegment("ORC", .j)
            Set number = "", which = ""
            If $ISOBJECT(first) {
                Set number = ..Narrow(first.GetValueAt("3.1")), which = "OBR-3, filler"
                If number = "" Set number = ..Narrow(first.GetValueAt("2.1")), which = "OBR-2, placer"
            }
            If (number = "") && $ISOBJECT(orc) {
                Set number = ..Narrow(orc.GetValueAt("3.1")), which = "ORC-3, filler"
                If number = "" Set number = ..Narrow(orc.GetValueAt("2.1")), which = "ORC-2, placer"
            }
            If number '= "" Set $LIST(rows, 1) = "Order or report number (" _ which _ ")"
            If $ISOBJECT(first) {
                Set values = $LISTBUILD(number, ..Narrow(first.GetValueAt("4.1")), ..When(##class(Shutter.Util.Time).FromHL7(first.GetValueAt("7.1"), zone)), ..Narrow(first.GetValueAt("25.1")))
            } Else {
                Set values = $LISTBUILD(number, "", "", "")
            }
        }
    } Catch {
    }
    If out.messageType = "" Set out.messageType = ..TypeOf(case)
    For i = 1:1:$LISTLENGTH(rows) { Do out.fields.%Push({"label": ($LIST(rows, i)), "value": ($LISTGET(values, i))}) }
    Quit out
}

/// The numbers and the status a document case's block holds. It keeps no type, title or time of the document, so those rows
/// stay unavailable, and a restricted document's block shows a person without the right none of this.
ClassMethod BlockFacts(case As Shutter.Store.Case, ByRef rows As %List, Output values As %List, out As %DynamicObject) [ Private ]
{
    Set values = "", json = "Shutter.Util.Json"
    Set block = ##class(Shutter.Util.DocumentCase).View(case)
    Set out.messageType = ..Narrow($CLASSMETHOD(json, "Str", block, "message_type"))
    If out.messageType = "" Set out.messageType = ..TypeOf(case)
    Set doc = block.%Get("document"), report = block.%Get("report")
    If case.Event = "T02" {
        If '$ISOBJECT(doc) Quit
        Do out.%Set("items", 1, "number")
        Set values = $LISTBUILD(..Narrow($CLASSMETHOD(json, "Str", doc, "id")), "", "", ..Narrow($CLASSMETHOD(json, "Str", doc, "completion")))
    } ElseIf (case.Event = "R01") && $ISOBJECT(report) {
        Do out.%Set("items", +$CLASSMETHOD(json, "Str", report, "orders"), "number")
        Set filler = ..Narrow($CLASSMETHOD(json, "Str", report, "filler")), placer = ..Narrow($CLASSMETHOD(json, "Str", report, "placer"))
        If (filler '= "") || (placer '= "") Set $LIST(rows, 1) = "Order or report number (" _ $SELECT(filler '= "": "OBR-3, filler", 1: "OBR-2, placer") _ ")"
        Set values = $LISTBUILD($SELECT(filler '= "": filler, 1: placer), "", "", ..Narrow($CLASSMETHOD(json, "Str", report, "result_status")))
    }
}

ClassMethod TypeOf(case As Shutter.Store.Case) As %String [ Private ]
{
    Quit $SELECT(case.Event = "T02": "MDM^T02", case.Event = "R01": "ORU^R01", 1: "")
}

/// One short coded value: no control characters, and nothing long enough to be a payload.
ClassMethod Narrow(value As %String) As %String [ Private ]
{
    Set v = $ZSTRIP(value, "*C")
    Quit $SELECT($LENGTH(v) > 64: "", 1: v)
}

/// The later movement known for this encounter: from the receiver's history as read, else Shutter's record of messages.
ClassMethod LaterMovement(case As Shutter.Store.Case, summary As %DynamicObject) As %DynamicObject
{
    Set json = "Shutter.Util.Json", found = "", source = ""
    Set state = summary.%Get("ward_state")
    Set history = $SELECT($ISOBJECT(state): state.%Get("history"), 1: "")
    If $ISOBJECT(history) {
        Set it = history.%GetIterator()
        While it.%GetNext(, .h) { If $ISOBJECT(h) && ..After(case, h) Set found = h, source = "the receiver's history" }
    }
    If '$ISOBJECT(found) {
        Set timeline = summary.%Get("timeline")
        If $ISOBJECT(timeline) {
            Set it = timeline.%GetIterator()
            While it.%GetNext(, .h) {
                If $ISOBJECT(h) && ($CLASSMETHOD(json, "Str", h, "outcome") = "applied") && ..After(case, h) Set found = h, source = "Shutter's record of messages"
            }
        }
    }
    If $ISOBJECT(found) {
        Set bed = $CLASSMETHOD(json, "Str", found, "bed")
        Set line = ##class(Shutter.Util.EscalationDraft).EventLine($CLASSMETHOD(json, "Str", found, "event"), $CLASSMETHOD(json, "Str", found, "ward"), $CLASSMETHOD(json, "Str", found, "event_time"))
        Quit {"summary": (line _ $SELECT(bed '= "": ", bed " _ bed, 1: "") _ "."), "source": (source)}
    }
    If +summary.%Get("later_events") > 0 Quit {"summary": (..Words().%Get("later_known")), "source": "Shutter's record of messages"}
    Quit ""
}

/// Another operation at this movement's time or after it. The same time counts: two sources can report one moment.
ClassMethod After(case As Shutter.Store.Case, h As %DynamicObject) As %Boolean [ Private ]
{
    Set key = ##class(Shutter.Util.Json).Str(h, "operation_key"), t = ##class(Shutter.Util.Json).Str(h, "event_time")
    If (key = "") || (key = case.OperationKey) || (t = "") Quit 0
    Quit (t = case.EventTime) || (t ]] case.EventTime)
}

/// "2026-10-15 08:20:00 UTC" from Shutter's ISO 8601 UTC, or "".
ClassMethod When(iso As %String) As %String [ Private ]
{
    If iso = "" Quit ""
    Quit $TRANSLATE($EXTRACT(iso, 1, 19), "T", " ") _ " UTC"
}

ClassMethod Or(value As %String, otherwise As %String) As %String [ Private ]
{
    Quit $SELECT(value '= "": value, 1: otherwise)
}

/// The site's runbook line for a receiver, in the current profile, or "".
ClassMethod RunbookOf(receiver As %String) As %String
{
    Quit ..RunbookIn(##class(Shutter.Store.SiteProfile).Current(), receiver)
}

/// A line that fails the rule, stored before it or by hand, is not shown.
ClassMethod RunbookIn(profile As %DynamicObject, receiver As %String) As %String
{
    Set list = profile.%Get("receivers")
    If '$ISOBJECT(list) Quit ""
    Set it = list.%GetIterator()
    While it.%GetNext(, .r) {
        Continue:'$ISOBJECT(r)
        Continue:(##class(Shutter.Util.Json).Str(r, "name") '= receiver)
        Set mc = r.%Get("manual_check")
        If '$ISOBJECT(mc) || (..ManualCheckProblem(mc) '= "") Return ""
        Return mc.%Get("runbook")
    }
    Quit ""
}

/// What is wrong with a receiver's manual_check, or "": one optional line of plain text, a place to look, read by a person
/// and never as a command, a mapping or a capability. web/src/features/site-profile/profile.ts holds the same rule.
ClassMethod ManualCheckProblem(mc) As %String
{
    If '$ISOBJECT(mc) || mc.%IsA("%DynamicArray") Quit "must be an object"
    Set it = mc.%GetIterator()
    While it.%GetNext(.k) { If k '= "runbook" Return k _ ": unknown field" }
    If 'mc.%IsDefined("runbook") Quit ""
    If mc.%GetTypeOf("runbook") '= "string" Quit "runbook: must be text"
    Set v = mc.%Get("runbook")
    If $ZSTRIP(v, "<>W") = "" Quit "runbook: must not be blank"
    If $LENGTH(v) > 300 Quit "runbook: at most 300 characters"
    If $LOCATE(v, "[\x00-\x1F\x7F]") Quit "runbook: one line, with no control characters"
    If v [ "<" Quit "runbook: plain text only, no HTML"
    If $LOCATE(v, "(?i)(://|\bwww\.|\bmailto:|\bjavascript:)") Quit "runbook: no links"
    If $LOCATE(v, "(?i)\b(password|passwd|pwd|secret|token|api[ _-]?key)\s*[:=]") Quit "runbook: no credentials"
    If $LOCATE(v, "\d{6}") Quit "runbook: no patient examples or identifiers"
    Quit ""
}

}
