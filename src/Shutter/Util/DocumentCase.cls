/// The document block of a case (docs/CONTRACTS.md 11.2): how a failed MDM delivery, or an ORU carrying a report as an attachment,
/// at a receiver with a document profile becomes the ordinary case with its no-recovery path, with no copy of the document. The block in Case.DocumentJSON holds
/// metadata only: the identity, the parent, the patient, the delivery, the receiver's refusal and the chain. It is not
/// projected with the case: View gives it to the API by the reader's right, and a restricted document's identity and a
/// receiver's own words only to a holder of Shutter_Approve. The snapshot, the email, the events and the model's view never
/// get them. Nothing here sends anything, and no agent is convened: there is no operation to send.
Class Shutter.Util.DocumentCase
{

/// The defaults of a receiver's documents setting: off, and every question of recovery unanswered.
ClassMethod DefaultSettings() As %DynamicObject
{
    Set d = {"report_structures": ["ORU^R01"], "recovery": "none", "source_namespaces": [], "supported_versions": [], "ack_level": "connection", "duplicates": "unknown", "allowed_completion": [], "allowed_confidentiality": [], "allowed_availability": [], "missing_status_policy": "stop", "max_recovery_bytes": 0, "approval_minutes": 15, "email_details": "minimal", "readback": "disabled"}
    Do d.%Set("enabled", 0, "boolean")
    Do d.%Set("owner_accepts_acknowledged_recovery", 0, "boolean")
    Do d.%Set("chain_read_limit", ##class(Shutter.Util.DocumentChain).#LIMIT, "number")
    Quit d
}

/// A receiver's settings: its entry over the defaults. A receiver the profile does not name, or names with no documents
/// entry, has the defaults, so its messages take the ordinary path.
ClassMethod Settings(receiver As %String) As %DynamicObject
{
    Set out = ..DefaultSettings()
    Set r = ##class(Shutter.Store.SiteProfile).Receiver(receiver)
    If '$ISOBJECT(r) || (r.%GetTypeOf("documents") '= "object") Quit out
    Set own = r.%Get("documents"), it = own.%GetIterator()
    While it.%GetNext(.k, .v) { Do ..Copy(own, k, out) }
    Quit out
}

/// One key from one object to another, keeping its type.
ClassMethod Copy(from As %DynamicObject, key As %String, to As %DynamicObject) [ Private ]
{
    Set type = from.%GetTypeOf(key)
    If (type = "object") || (type = "array") { Do to.%Set(key, from.%Get(key)) } Else { Do to.%Set(key, from.%Get(key), type) }
}

ClassMethod Enabled(receiver As %String) As %Boolean
{
    Quit ##class(Shutter.Util.Json).Bool(..Settings(receiver), "enabled", 0)
}

/// Whether a list of structures names a message type.
ClassMethod Counts(list As %DynamicArray, type As %String) As %Boolean
{
    If '$ISOBJECT(list) Quit 0
    Set it = list.%GetIterator()
    While it.%GetNext(, .v) { If v = type Return 1 }
    Quit 0
}

/// Whether a receiver's profile takes this type of report.
ClassMethod TakesReport(receiver As %String, type As %String) As %Boolean
{
    Set s = ..Settings(receiver)
    Quit ##class(Shutter.Util.Json).Bool(s, "enabled", 0) && ..Counts(s.%Get("report_structures"), type)
}

/// What a person calls this delivery.
ClassMethod Noun(block As %DynamicObject) As %String
{
    Quit $SELECT($ISOBJECT(block) && (block.kind = "report"): "report", 1: "document")
}

/// What is wrong with a receiver's documents entry, or "": every key named, so a misspelt switch cannot pass as off.
ClassMethod SettingsProblem(d) As %String
{
    If '$ISOBJECT(d) || d.%IsA("%Library.DynamicArray") Quit ": must be an object"
    Set known = ..DefaultSettings(), it = d.%GetIterator()
    While it.%GetNext(.k, .v) {
        If 'known.%IsDefined(k) Return "." _ k _ ": unknown setting"
        If d.%GetTypeOf(k) '= known.%GetTypeOf(k) Return "." _ k _ ": must be " _ $CASE(known.%GetTypeOf(k), "boolean": "true or false", "array": "an array", "number": "a number", : "a string")
    }
    If d.%IsDefined("report_structures") {
        Set it = d.%Get("report_structures").%GetIterator()
        While it.%GetNext(, .v) { If v'?1"ORU^"1.AN Return ".report_structures: each must be an ORU message type, such as ORU^R01" }
    }
    // The sender is another piece of work: until it exists, no setting can ask for it.
    If d.%IsDefined("recovery") && (d.%Get("recovery") '= "none") Quit ".recovery: must be none: this version resends no document"
    If d.%IsDefined("readback") && (d.%Get("readback") '= "disabled") Quit ".readback: must be disabled: this version reads no document back"
    If d.%IsDefined("ack_level") && '$LISTFIND($LISTBUILD("connection", "application"), d.%Get("ack_level")) Quit ".ack_level: must be connection or application"
    If d.%IsDefined("duplicates") && '$LISTFIND($LISTBUILD("unknown", "rejects_exact", "rejects_number", "replaces", "files_again"), d.%Get("duplicates")) Quit ".duplicates: must be unknown, rejects_exact, rejects_number, replaces or files_again"
    If d.%IsDefined("missing_status_policy") && (d.%Get("missing_status_policy") '= "stop") Quit ".missing_status_policy: must be stop"
    If d.%IsDefined("email_details") && '$LISTFIND($LISTBUILD("minimal", "identifiers"), d.%Get("email_details")) Quit ".email_details: must be minimal or identifiers"
    If d.%IsDefined("chain_read_limit") && (+d.%Get("chain_read_limit") < 1) Quit ".chain_read_limit: must be at least 1"
    Quit ""
}

// ---- the operation and the block ----

/// A confidentiality status that gets the restricted presentation: V and R, and a value the standard does not list, since it
/// cannot be read as usual control. An absent TXA-18 (optional in the standard) is not restricted.
ClassMethod IsRestricted(status As %String) As %Boolean
{
    Quit (status '= "") && (status '= "U")
}

/// The operation a case carries. Its key binds one stored delivery (receiver, source, header, identity, parent, trigger,
/// patient and body), a hash and so no identifier, and is no statement about the document's version: a new transmission under
/// a new header is a new case. A restricted document's patient stays out of the case's own columns.
ClassMethod Operation(block As %DynamicObject) As %DynamicObject
{
    Set src = block.source, doc = block.document, json = "Shutter.Util.Json"
    Set report = block.kind = "report"
    Set canon = $LISTTOSTRING($LISTBUILD(block.receiver, src.namespace, src."header_id", doc.id, $SELECT(report: block.report.placer, 1: doc.parent), block.trigger, block.patient.binding, block.digests.body), "|")
    Set op = {}
    Set op."operation_key" = $SELECT(report: "oru-v1:", 1: "mdm-v1:") _ ##class(Shutter.Util.Digest).SHA256Hex(canon)
    Set op."encounter_id" = "-"
    Set restricted = ''block.restricted
    Set op."patient_id" = "", op."patient_id_authority" = ""
    If 'restricted {
        Set pick = 0, keys = block.patient.keys
        For i = 0:1:keys.%Size() - 1 { If $ZCONVERT($CLASSMETHOD(json, "Str", keys.%Get(i), "type"), "U") = "MR" Set pick = i Quit }
        If keys.%Size() > 0 Set op."patient_id" = $CLASSMETHOD(json, "Str", keys.%Get(pick), "id"), op."patient_id_authority" = $PIECE($CLASSMETHOD(json, "Str", keys.%Get(pick), "authority"), "&", 1)
    }
    Set op."event" = block.trigger
    Do op.%Set("ward", "", "null"), op.%Set("bed", "", "null")
    Set when = ##class(Shutter.Util.Time).FromHL7(block."message_time")
    Set op."event_time" = $SELECT(when = "": ##class(Shutter.Util.Time).NowUTC(), 1: when)
    Set op."source_system" = $PIECE(block."sending_application", "^", 1)
    Set op."source_message_id" = block."control_id"
    Set op."payload_digest" = "sha256-chunked:" _ block.digests.body
    Quit op
}

/// The words a document case's failure carries: the ones every message Shutter does not model carries (Case.NotModelled), with
/// nothing the source reported after them, since a receiver's words stay in the block.
ClassMethod FailureWords(block As %DynamicObject = "") As %String
{
    Quit "This message is " _ $SELECT(..Noun(block) = "report": "ORU", 1: "MDM") _ ", not ADT: Shutter resends only ADT, so it sends nothing and a person decides"
}

/// The refusal from what the forward reported: the code by itself, and the receiver's words for whoever may read them.
ClassMethod Refusal(kind As %String, outcome As %String, reason As %String, http As %String, text As %String) As %DynamicObject
{
    Set o = {"kind": (kind), "outcome": (outcome), "reason_code": (reason)}
    If +http > 0 Do o.%Set("http_status", +http, "number")
    Set code = ""
    If $EXTRACT(reason, 1, 4) = "ack_" Set code = $EXTRACT(reason, 5, 6)
    // The engine's own words first ("MSA code 'AE'"), then the code on its own.
    If code = "" {
        Set e = 0, m = ""
        If $LOCATE(text, "MSA code '(AE|AR|CE|CR)'", 1, e, m) { Set code = $EXTRACT(m, 11, 12) } ElseIf $LOCATE(text, "\b(AE|AR|CE|CR)\b", 1, e, m) { Set code = m }
    }
    Set o."ack_code" = code
    Set o.text = $EXTRACT(text, 1, 2000)
    Quit o
}

/// Hand a block to the case being opened, outside the messages' own stored bodies (a restricted identity and a receiver's words
/// must not sit in the message archive). The stage's key travels in the operation.
ClassMethod Stage(block As %DynamicObject) As %String
{
    Set key = ##class(Shutter.Util.Digest).SHA256Hex($JOB _ "|" _ $ZTIMESTAMP _ "|" _ $RANDOM(1000000000))
    Set ^Shutter.DocumentStage(key) = block.%ToJSON()
    Quit key
}

ClassMethod Unstage(key As %String) As %String
{
    If key = "" Quit ""
    Set text = $GET(^Shutter.DocumentStage(key))
    Kill ^Shutter.DocumentStage(key)
    Quit text
}

// ---- the evidence ----

/// The evidence of a document case: the snapshot's items, none of them from a message body. The chain is read now from the
/// source's store when this instance has that namespace, else what the forwarder read stands, with its time.
ClassMethod Collect(case As Shutter.Store.Case, snap As Shutter.Store.Snapshot, response As Shutter.Msg.EvidenceResult) As %Status
{
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set block = ##class(Shutter.Util.Json).Parse(case.DocumentJSON, .psc)
    If '$ISOBJECT(block) Set response.Error = "The document block of " _ case.CaseId _ " cannot be read" Quit $$$OK
    Do ..Refresh(block, case.Receiver)
    Do ..Conclude(block)
    Set json = block.%ToJSON()
    Set sc = ##class(%SQL.Statement).%ExecDirectNoPriv(, "UPDATE Shutter_Store.""Case"" SET DocumentJSON = ? WHERE CaseId = ?", json, case.CaseId)
    Set case.DocumentJSON = json
    // A status that turned restricted since the case opened takes the patient off its columns too.
    If block.restricted && (case.PatientId '= "") {
        Do ##class(%SQL.Statement).%ExecDirectNoPriv(, "UPDATE Shutter_Store.""Case"" SET PatientId = '', PatientIdAuthority = '' WHERE CaseId = ?", case.CaseId)
        Set case.PatientId = "", case.PatientIdAuthority = ""
    }
    Set open = ..ForEvidence(block), op = open.operation
    Do open.%Remove("operation")
    Set failure = {"kind": (case.FailureKind), "text": (case.FailureText), "outcome": (case.FailureOutcome), "reason_code": (case.FailureReasonCode)}
    Set source = {"namespace": (case.SourceNamespace), "production": (case.SourceProduction), "route": (case.SourceRoute), "header_id": (case.OriginHeaderId)}
    Set count = 0
    Do snap.AddItem("operation", "production", now, op) Set count = count + 1
    Do snap.AddItem("error", "production", now, failure) Set count = count + 1
    Do snap.AddItem("source", "production", now, source) Set count = count + 1
    Do snap.AddItem("message", "message_store", now, open) Set count = count + 1
    Set summary = {}
    Set summary."case_id" = case.CaseId, summary.scenario = case.Scenario
    Set summary.operation = op, summary.failure = failure, summary.source = source, summary.document = open
    Set summary.message = {"message_type": ($SELECT(..Noun(block) = "report": "ORU^", 1: "MDM^") _ case.Event), "message_control_id": (case.SourceMessageId), "note": "Metadata only: Shutter holds no copy of this document"}
    Set summary.validation = {"note": "Not validated by Shutter: it holds no copy of this document"}
    Set summary.timeline = [], summary."pending_messages" = []
    Do summary.%Set("later_events", 0, "number")
    Set summary."observed_at" = now, summary."fresh_until" = snap.FreshUntil
    Set sc = snap.Seal(summary)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc) Quit $$$OK
    Set sc = case.SetSnapshot(snap)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc) Quit $$$OK
    Do case.Note("artifact", "Snapshot " _ snap.Seq _ " taken: " _ count _ " observations, document metadata only, digest " _ $EXTRACT(snap.Digest, 1, 19), "system", "snapshot:" _ snap.%Id())
    Set response.SnapshotId = snap.%Id(), response.Digest = snap.Digest, response.SummaryJSON = snap.Summary, response.ItemCount = count
    Quit $$$OK
}

/// Read the source again, where this instance can: its delivery header's status, whether the body is still there, and the chain.
/// A source that can't be read leaves the forwarder's reading standing, with the source unverified.
ClassMethod Refresh(block As %DynamicObject, receiver As %String) [ Private ]
{
    Set src = block.source, ns = src.namespace, item = src.item, headerId = src."header_id"
    Set doc = block.document, limit = +..Settings(receiver).%Get("chain_read_limit")
    If (ns = "") || '##class(%SYS.Namespace).Exists(ns) {
        Do block.%Set("source_verified", 0, "boolean")
        Set note = "The namespace " _ $SELECT(ns = "": "(none)", 1: ns) _ " is not on this instance, so Shutter cannot read its message store"
        If 'block.%IsDefined("chain") || '$ISOBJECT(block.chain) {
            Set block.chain = {"note": (note), "rows": []}
            Do block.chain.%Set("complete", 0, "boolean")
        } Else {
            Set block.chain.note = note _ ": what the forwarder read at " _ block.chain."read_at" _ " stands"
        }
        Quit
    }
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
        If '$ISOBJECT(header) {
            Do block.%Set("source_verified", 0, "boolean")
            Do block.%Set("source_body_available", 0, "boolean")
        } ElseIf (item '= "") && (header.TargetConfigName '= item) {
            // The whole-text path names a header the source chose, not the delivery: where it is, not what was delivered.
            // The session's delivery is what Findings compares other rows with.
            Do block.%Set("source_verified", 0, "boolean")
            Set own = ##class(Shutter.Util.DocumentFacts).DeliveryHeader(header.SessionId, item, .ambiguous)
            If $ISOBJECT(own) {
                Set block.delivery."session_header" = own.%Id()
                Do block.delivery.%Set("ambiguous", ''ambiguous, "boolean")
            }
        } Else {
            Do block.%Set("source_verified", 1, "boolean")
            Set item = header.TargetConfigName, src.item = item
            Do block.%Set("source_body_available", $ISOBJECT(##class(EnsLib.HL7.Message).%OpenId(header.MessageBodyId)), "boolean")
            Set block.delivery.status = ##class(Shutter.Util.DocumentFacts).StatusWords(header), block.delivery."header_id" = headerId
            Set block.delivery."time_created" = header.TimeCreated, block.delivery."time_processed" = header.TimeProcessed
        }
        If item '= "" {
            If block.kind = "report" {
                Set block.chain = ##class(Shutter.Util.DocumentChain).ReadReports(item, block.report.placer, block.report.filler, limit)
            } Else {
                Set block.chain = ##class(Shutter.Util.DocumentChain).Read(item, doc.id, doc.parent, limit)
            }
        } Else {
            Set block.chain = {"note": "The source did not name its item, so the chain was not read", "rows": []}
            Do block.chain.%Set("complete", 0, "boolean")
        }
    } Catch ex {
        Do block.%Set("source_verified", 0, "boolean")
        Set block.chain = {"note": ("The message store of " _ ns _ " could not be read: " _ $EXTRACT(ex.DisplayString(), 1, 200)), "rows": []}
        Do block.chain.%Set("complete", 0, "boolean")
    }
}

/// What the block's facts come to: its reasons, the chain's plain sentences, and whether it is restricted.
ClassMethod Conclude(block As %DynamicObject)
{
    Do ##class(Shutter.Util.DocumentEligibility).Findings(block)
    Set block.reasons = ##class(Shutter.Util.DocumentEligibility).Reasons(block)
    Do block.%Set("sent_nothing", 1, "boolean")
    Do block.%Set("body_stored_in_shutter", 0, "boolean")
    Set block.headline = ..Headline(block)
}

/// The sentence a person reads first.
ClassMethod Headline(block As %DynamicObject) As %String
{
    If block.restricted Quit "Restricted document delivery requires an authorised reviewer. No document content is shown or sent by email."
    If ..Noun(block) = "report" {
        If block.document.id = "" Quit "The message has no usable order or report number. Shutter cannot establish its chain and will not resend it."
        Quit "Report delivery needs review. Shutter has sent nothing."
    }
    If block.document.id = "" Quit "The message has no usable document identifier. Shutter cannot establish its document chain and will not resend it."
    Quit "Document delivery needs review. Shutter has sent nothing."
}

/// The block as the snapshot holds it: no receiver's words, and a restricted document's identity left out.
ClassMethod ForEvidence(block As %DynamicObject) As %DynamicObject
{
    Set o = ##class(%DynamicObject).%FromJSON(block.%ToJSON())
    Set op = ..Operation(block)
    Set o.operation = op
    If o.%IsDefined("refusal") && $ISOBJECT(o.refusal) Do o.refusal.%Remove("text")
    If o.restricted Quit ..Masked(o)
    Quit o
}

/// The same with the identity removed: the case's first screen for anyone without Shutter_Approve.
ClassMethod Masked(o As %DynamicObject) As %DynamicObject
{
    Set op = $SELECT(o.%IsDefined("operation"): o.operation, 1: "")
    Set out = {}
    For k = "trigger", "message_type", "restricted", "reasons", "sent_nothing", "body_stored_in_shutter", "headline", "size", "delivery", "refusal", "source_verified", "source_body_available", "document_restricted_view" {
        If o.%IsDefined(k) Do ..Copy(o, k, out)
    }
    If $ISOBJECT(op) Set out.operation = op
    Do out.%Set("identity_withheld", 1, "boolean")
    Set out.chain = {"says": ["Restricted: the document's chain is for an authorised reviewer."]}
    Do out.chain.%Set("complete", ''o.chain.complete, "boolean")
    Quit out
}

/// The block for the API, by the reader's right: a receiver's words and a restricted document's identity need Shutter_Approve.
ClassMethod View(case As Shutter.Store.Case) As %DynamicObject
{
    Set o = ##class(Shutter.Util.Json).Parse(case.DocumentJSON, .psc)
    If '$ISOBJECT(o) Quit {}
    If $SYSTEM.Security.Check("Shutter_Approve", "USE") Quit o
    If o.%IsDefined("refusal") && $ISOBJECT(o.refusal) {
        Do o.refusal.%Set("text_withheld", o.refusal.text '= "", "boolean")
        Do o.refusal.%Remove("text")
    }
    If o.restricted Quit ..Masked(o)
    Quit o
}

// ---- the plan and the email ----

/// The plan of a document case: a person, and no action.
ClassMethod Plan(case As Shutter.Store.Case) As %DynamicObject
{
    Set block = ##class(Shutter.Util.Json).Parse(case.DocumentJSON, .psc)
    Set plan = {}
    Set plan.disposition = "escalate", plan.action = {"type": "none"}
    Set noun = ..Noun(block)
    Set plan.why = "A " _ noun _ " delivery: Shutter recognises it and resends nothing, so a person handles it"
    Set plan.summary = $ZCONVERT($EXTRACT(noun), "U") _ $EXTRACT(noun, 2, *) _ " delivery: Shutter has sent nothing, and a person decides"
    Set plan.preconditions = [], plan."evidence_refs" = ["document"], plan.disagreements = []
    Quit plan
}

/// The email for a document case: the case's link, the receiver, the reason and the team. Identifiers only under the receiver's
/// own email_details setting, and never for a restricted document, whose email is the minimal notice. No "verifies the
/// correction": there is no read-back of a document, so nothing here can verify one.
ClassMethod Draft(case As Shutter.Store.Case, team As %DynamicObject, Output subject As %String, Output body As %String) As %Status
{
    Set nl = $CHAR(13, 10), json = "Shutter.Util.Json"
    Set block = $CLASSMETHOD(json, "Parse", case.DocumentJSON, .psc)
    If '$ISOBJECT(block) Quit $$$ERROR($$$GeneralError, "The document block cannot be read")
    Set receiver = $SELECT(case.Receiver '= "": case.Receiver, 1: "the receiver")
    Set label = ##class(Shutter.Store.SiteProfile).ReceiverLabel(receiver)
    Set teamName = $SELECT($ISOBJECT(team): $CLASSMETHOD(json, "Str", team, "name"), 1: "")
    Set noun = ..Noun(block), refused = (case.FailureOutcome = "rejected") || ($ISOBJECT(block.%Get("refusal")) && (block.refusal."ack_code" '= ""))
    Set subject = "Shutter " _ case.CaseId _ ": " _ noun _ " delivery needs review, " _ receiver
    Set b = "To " _ $SELECT(teamName '= "": teamName, 1: "the team") _ "," _ nl _ nl
    If block.restricted {
        Set b = b _ "Restricted document delivery requires an authorised reviewer. No document content is shown or sent by email." _ nl _ nl
    } Else {
        Set b = b _ "A " _ noun _ " delivery to " _ label _ " needs review. Shutter has sent nothing for it, and resends no " _ noun _ ". Before anyone re-enters it, check the source's Message Viewer" _ $SELECT(refused: ".", 1: ": an operation that retries delivers it by itself once the receiver is back.") _ nl _ nl
        Set b = b _ "WHY IT NEEDS A PERSON" _ nl
        Set it = block.reasons.%GetIterator(), any = 0
        While it.%GetNext(, .r) { Set b = b _ "  " _ r.words _ " (" _ r.code _ ")" _ nl, any = 1 }
        If 'any Set b = b _ "  The delivery failed: " _ $CASE(case.FailureOutcome, "uncertain": "the receiver may hold it already", "rejected": "the receiver refused it", : "it was not delivered") _ "." _ nl
        Set b = b _ nl
        Set settings = ..Settings(receiver)
        If $CLASSMETHOD(json, "Str", settings, "email_details") = "identifiers" {
            Set b = b _ "IDENTIFIERS (this receiver's setting)" _ nl
            Set b = b _ "  Hospital number: " _ case.PatientId _ $SELECT(case.PatientIdAuthority '= "": " (" _ case.PatientIdAuthority _ ")", 1: "") _ nl
            Set b = b _ "  " _ $SELECT(noun = "report": "Report", 1: "Document") _ ": " _ block.document.id _ nl _ nl
        }
    }
    Set b = b _ "WHEN IT IS HANDLED" _ nl
    Set b = b _ "  Record it on the case and mark the case as handled by the team: Shutter sent nothing for this message, and it cannot check what " _ receiver _ " filed." _ nl _ nl
    Set b = b _ "REFERENCES" _ nl
    Set b = b _ "  Case: " _ case.CaseId _ " (Shutter, /shutter/index.html#/cases/" _ case.CaseId _ ")" _ nl
    Set b = b _ nl _ "This email was drafted by Shutter from its record of the case and reviewed by the person who sent it." _ nl
    Set body = b
    Quit $$$OK
}

}
