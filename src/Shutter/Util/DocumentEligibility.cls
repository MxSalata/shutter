/// The document reason table (docs/CONTRACTS.md 11.2): deterministic, from the block's facts, with no catalogue entry and no
/// model. Findings reads the chain into plain sentences; Reasons gives what a person reads; Check is the one mandatory question a
/// sender must ask, immediately before every send, and it fails closed: with no delivery evidence, or with recovery off (the only
/// setting this version accepts), it never answers eligible. Its positive answer is a code for the sender and appears on no
/// screen, email or API answer.
Class Shutter.Util.DocumentEligibility
{

/// Words for each code a person may read. The codes a sender alone meets have none and are never shown.
ClassMethod Words(code As %String) As %String
{
    Quit $CASE(code,
        "DOC_ID_MISSING": "The message has no usable document identifier",
        "DOC_RESTRICTED": "The document's confidentiality status is restricted, or one Shutter cannot read as usual control",
        "DOC_CHAIN_INCOMPLETE": "Chain coverage is incomplete, so this cannot say no other message exists for this document",
        "DOC_CANCELLED": "A cancellation names this document, or its availability status says cancelled",
        "DOC_REPLACED_OR_EDITED": "A later edit or replacement exists for this document, or its availability status says obsolete",
        "DOC_VERSION_CONFLICT": "The same document number or control id appears with different content",
        "DOC_PARENT_UNPROVEN": "This message depends on a parent document, and nothing here shows the receiver holds it",
        "DOC_PATIENT_CHANGED": "This document number appears with different patient identifiers",
        "DOC_STATUS_UNPROVEN": "A document status is missing or is not one the standard lists",
        "DOC_ENGINE_OWNS_DELIVERY": "The engine still owns this delivery, and may deliver it by itself",
        "DOC_DELIVERY_UNCERTAIN": "The receiver may hold this document already",
        "DOC_BODY_UNAVAILABLE": "The source no longer holds this message, or its source could not be checked",
        : "")
}

ClassMethod Reason(code As %String) As %DynamicObject [ Private ]
{
    Quit {"code": (code), "words": (..Words(code))}
}

/// The chain's findings and its sentences, onto the block.
ClassMethod Findings(block As %DynamicObject)
{
    Set doc = block.document, self = doc.id, parent = doc.parent, myHeader = block.source."header_id"
    If '$ISOBJECT(block.%Get("chain")) {
        Set block.chain = {"rows": []}
        Do block.chain.%Set("complete", 0, "boolean")
    }
    Set chain = block.chain, says = [], f = {"edited": [], "replaced": [], "cancelled": [], "addenda": [], "status_changes": []}
    Do f.%Set("version_conflict", 0, "boolean"), f.%Set("patient_conflict", 0, "boolean"), f.%Set("parent_seen", 0, "boolean")
    Set parentStatus = "", rows = chain.%Get("rows"), myControl = block."control_id", myDigest = block.digests.body, myContent = block.digests.content, myBinding = block.patient.binding
    Set anyRestricted = ##class(Shutter.Util.DocumentCase).IsRestricted(doc.confidentiality)
    If $ISOBJECT(rows) {
        Set it = rows.%GetIterator()
        While it.%GetNext(, .r) {
            Set hid = r."header_id"
            If ##class(Shutter.Util.DocumentCase).IsRestricted(r.confidentiality) Set anyRestricted = 1
            Continue:(hid = myHeader)
            Set t = r.trigger, what = t _ " at header " _ hid _ ", " _ r.status
            If (self '= "") && (r."document_id" = self) {
                If $CASE(t, "T07": 1, "T08": 1, : 0) Do f.edited.%Push(what), says.%Push("An edit (" _ what _ ") exists for this document.")
                If t = "T11" Do f.cancelled.%Push(what), says.%Push("A cancellation (" _ what _ ") names this document. It says the document should be withdrawn, not that every copy is gone.")
                If $CASE(t, "T03": 1, "T04": 1, : 0) Do f."status_changes".%Push(what), says.%Push("A status change (" _ what _ ") exists for this document.")
                If r.availability = "CA" Do f.cancelled.%Push(what)
                If r.availability = "OB" Do f.replaced.%Push(what)
                If (t = "T01") || (t = "T02") {
                    If (r."content_digest" '= "") && (r."content_digest" = myContent) && (r."control_id" '= myControl) {
                        Do says.%Push("The same content is at header " _ hid _ " under another control id: a possible retransmission, or a copy, and each delivery keeps its own case.")
                    } ElseIf (r."content_digest" '= myContent) && (r."content_digest" '= "") {
                        Do f.%Set("version_conflict", 1, "boolean"), says.%Push("Another " _ t _ " carries this document number with different content (" _ what _ ").")
                    }
                } ElseIf $CASE(t, "T08": 1, "T04": 1, : 0) {
                    Do f.%Set("version_conflict", 1, "boolean")
                }
                If (r."patient_binding" '= myBinding) Do f.%Set("patient_conflict", 1, "boolean"), says.%Push("This document number is on other patient identifiers at header " _ hid _ ".")
            }
            If (self '= "") && (r."parent_id" = self) {
                If $CASE(t, "T09": 1, "T10": 1, : 0) Do f.replaced.%Push(what), says.%Push("A replacement (" _ what _ ") names this document as its parent, with its own number. It does not show the receiver has made this one obsolete.")
                If $CASE(t, "T05": 1, "T06": 1, : 0) Do f.addenda.%Push(what), says.%Push("An addendum (" _ what _ ") names this document as its parent.")
            }
            If (parent '= "") && (r."document_id" = parent) && (parentStatus = "") {
                Do f.%Set("parent_seen", 1, "boolean")
                Set parentStatus = r.status
            }
            If (myControl '= "") && (r."control_id" = myControl) && (r."content_digest" '= myContent) && (r."content_digest" '= "") Do f.%Set("version_conflict", 1, "boolean"), says.%Push("The control id " _ myControl _ " is on different content at header " _ hid _ ".")
        }
    }
    Do block.%Set("restricted", anyRestricted, "boolean")
    Set t = block.trigger
    If $CASE(t, "T05": 1, "T06": 1, "T09": 1, "T10": 1, : 0) {
        Set f."needs_parent" = 1
        If parent = "" {
            Do says.%Push("This " _ t _ " names no parent document, though the standard requires one.")
        } ElseIf f."parent_seen" {
            Do says.%Push("Its parent is in the message store (" _ parentStatus _ "). That does not show the receiver holds it.")
        } Else {
            Do says.%Push("Its parent " _ parent _ " was not found among the messages read.")
        }
    } ElseIf parent '= "" {
        Do says.%Push("It names a parent: " _ parent _ $SELECT(f."parent_seen": ", in the message store (" _ parentStatus _ ").", 1: ", not found among the messages read."))
    }
    If self = "" {
        Do chain.%Set("complete", 0, "boolean")
        Do says.%Push("With no document identifier, Shutter cannot establish a chain.")
    } ElseIf chain.complete {
        If says.%Size() = 0 Do says.%Push("No other message for this document among the " _ chain.read _ " messages to " _ chain.item _ " read back to " _ $EXTRACT(chain.since, 1, 16) _ ". Older messages and other routes are not covered.")
        If says.%Size() > 0 Do says.%Set(says.%Size(), "Read: " _ chain.read _ " messages to " _ chain.item _ " back to " _ $EXTRACT(chain.since, 1, 16) _ ".")
    } Else {
        Set why = $SELECT(chain.%IsDefined("note"): chain.note, 1: "")
        If +chain.%Get("unreadable") > 0 Set why = why _ $SELECT(why = "": "", 1: "; ") _ chain.unreadable _ " message(s) could not be read"
        If chain."limit_reached" Set why = why _ $SELECT(why = "": "", 1: "; ") _ "the limit of " _ chain.limit _ " messages was reached"
        If chain."rows_capped" Set why = why _ $SELECT(why = "": "", 1: "; ") _ "more linked messages than a chain holds"
        Do says.%Push("Chain coverage is incomplete" _ $SELECT(why = "": ".", 1: ": " _ why _ "."))
    }
    Set chain.says = says, chain.findings = f
}

/// What a person reads: the codes that hold now, most serious first. The sender's own codes are not here.
ClassMethod Reasons(block As %DynamicObject) As %DynamicArray
{
    Set out = [], doc = block.document, f = block.chain.findings, delivery = block.%Get("delivery")
    If doc.id = "" Do out.%Push(..Reason("DOC_ID_MISSING"))
    If block.restricted Do out.%Push(..Reason("DOC_RESTRICTED"))
    If (doc.id '= "") && 'block.chain.complete Do out.%Push(..Reason("DOC_CHAIN_INCOMPLETE"))
    If (f.cancelled.%Size() > 0) || (doc.availability = "CA") || (block.trigger = "T11") Do out.%Push(..Reason("DOC_CANCELLED"))
    If (f.edited.%Size() > 0) || (f.replaced.%Size() > 0) || (doc.availability = "OB") Do out.%Push(..Reason("DOC_REPLACED_OR_EDITED"))
    If f."version_conflict" Do out.%Push(..Reason("DOC_VERSION_CONFLICT"))
    If f.%IsDefined("needs_parent") Do out.%Push(..Reason("DOC_PARENT_UNPROVEN"))
    If f."patient_conflict" Do out.%Push(..Reason("DOC_PATIENT_CHANGED"))
    If ..StatusUnproven(doc, 0) Do out.%Push(..Reason("DOC_STATUS_UNPROVEN"))
    If $ISOBJECT(delivery) && $CASE(delivery.status, "Created": 1, "Queued": 1, "Delivered": 1, "Deferred": 1, : 0) Do out.%Push(..Reason("DOC_ENGINE_OWNS_DELIVERY"))
    // Several bodies to one receiver in one session: which one failed is not known.
    If ($ISOBJECT(block.%Get("refusal")) && (block.refusal.kind = "uncertain_outcome")) || ($ISOBJECT(delivery) && delivery.ambiguous) Do out.%Push(..Reason("DOC_DELIVERY_UNCERTAIN"))
    If block.%IsDefined("source_body_available") && 'block."source_body_available" Do out.%Push(..Reason("DOC_BODY_UNAVAILABLE"))
    Quit out
}

/// Whether a status is outside the standard's tables, or missing: TXA-17 is required, TXA-18 and TXA-19 optional, so an absent
/// one counts for a sender (strict) and, for a person, only when it is the required one or both optional ones are gone.
ClassMethod StatusUnproven(doc As %DynamicObject, strict As %Boolean) As %Boolean [ Private ]
{
    Set c = doc.completion, s = doc.confidentiality, a = doc.availability
    If c = "" Quit 1
    If '$LISTFIND($LISTBUILD("DI", "DO", "IP", "IN", "PA", "AU", "LA"), c) Quit 1
    If (a '= "") && '$LISTFIND($LISTBUILD("AV", "CA", "OB", "UN"), a) Quit 1
    If strict Quit (s = "") || (a = "")
    Quit (s = "") && (a = "")
}

/// The mandatory question before a send of one original T02 (for the later sender, at every send): a reason code, and only with
/// every check passing the one code that lets it go on. block is the case's, freshly concluded; settings the receiver's;
/// delivery what the sender's own engine reader found: {engine_settled, never_opened_every_attempt, evidence_complete,
/// patient_history_checked, patient_history_clear}. No delivery object: not eligible.
ClassMethod Check(block As %DynamicObject, settings As %DynamicObject, delivery As %DynamicObject = "") As %String
{
    Set json = "Shutter.Util.Json", doc = block.document
    If '$ISOBJECT(block) || '$ISOBJECT(doc) Quit "DOC_ID_MISSING"
    If $CLASSMETHOD(json, "Str", settings, "recovery") '= "original_t02" Quit "DOC_RECOVERY_OFF"
    If '$CLASSMETHOD(json, "Bool", settings, "enabled", 0) || '$CLASSMETHOD(json, "Bool", settings, "owner_accepts_acknowledged_recovery", 0) Quit "DOC_RECOVERY_OFF"
    If block.trigger '= "T02" Quit "DOC_NOT_ORIGINAL_T02"
    If doc.id = "" Quit "DOC_ID_MISSING"
    If block.restricted Quit "DOC_RESTRICTED"
    If '$ISOBJECT(block.%Get("chain")) || 'block.chain.complete Quit "DOC_CHAIN_INCOMPLETE"
    Set f = block.chain.findings
    If (f.cancelled.%Size() > 0) || (doc.availability = "CA") Quit "DOC_CANCELLED"
    If (f.edited.%Size() > 0) || (f.replaced.%Size() > 0) || (f."status_changes".%Size() > 0) || (f.addenda.%Size() > 0) || (doc.availability = "OB") Quit "DOC_REPLACED_OR_EDITED"
    If f."version_conflict" Quit "DOC_VERSION_CONFLICT"
    If doc.parent '= "" Quit "DOC_PARENT_UNPROVEN"
    If f."patient_conflict" Quit "DOC_PATIENT_CHANGED"
    If ..StatusUnproven(doc, 1) Quit "DOC_STATUS_UNPROVEN"
    If '..Allowed(settings, "allowed_completion", doc.completion) || '..Allowed(settings, "allowed_confidentiality", doc.confidentiality) || '..Allowed(settings, "allowed_availability", doc.availability) Quit "DOC_STATUS_UNPROVEN"
    If block.%IsDefined("source_body_available") && 'block."source_body_available" Quit "DOC_BODY_UNAVAILABLE"
    If 'block."source_verified" Quit "DOC_BODY_UNAVAILABLE"
    If $CLASSMETHOD(json, "Str", settings, "duplicates") = "unknown" Quit "DOC_DUPLICATE_UNDECLARED"
    If '$ISOBJECT(delivery) || (block.%GetTypeOf("delivery") = "object" && block.delivery.ambiguous) Quit "DOC_DELIVERY_UNCERTAIN"
    If '$CLASSMETHOD(json, "Bool", delivery, "engine_settled", 0) Quit "DOC_ENGINE_OWNS_DELIVERY"
    If '$CLASSMETHOD(json, "Bool", delivery, "evidence_complete", 0) || '$CLASSMETHOD(json, "Bool", delivery, "never_opened_every_attempt", 0) Quit "DOC_DELIVERY_UNCERTAIN"
    If '$CLASSMETHOD(json, "Bool", delivery, "patient_history_checked", 0) || '$CLASSMETHOD(json, "Bool", delivery, "patient_history_clear", 0) Quit "DOC_PATIENT_CHANGED"
    Quit ..Eligible()
}

/// Whether a value is on a receiver's list of allowed values: an empty list allows nothing.
ClassMethod Allowed(settings As %DynamicObject, key As %String, value As %String) As %Boolean [ Private ]
{
    Set list = settings.%Get(key)
    If '$ISOBJECT(list) Quit 0
    Set it = list.%GetIterator()
    While it.%GetNext(, .v) { If v = value Return 1 }
    Quit 0
}

/// The one code that lets a sender go on. A code for a program: no screen, email or API answer shows it.
ClassMethod Eligible() As %String [ Private ]
{
    Quit "DOC_T02_ELIGIBLE"
}

}
