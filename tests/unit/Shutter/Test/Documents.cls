/// Document-aware exceptions in process (CONTRACTS 11.2): what is read of an MDM message and what is not, the reasons from a
/// block's facts, the one question a sender must ask, the settings' defaults and refusals, the email and the model's view. The
/// whole flow, through a real production and a real forwarder, is tests/e2e/documents_check.py.
Class Shutter.Test.Documents Extends %UnitTest.TestCase
{

/// An MDM message's text. Each canary is a value Shutter must never read.
ClassMethod Text(trigger As %String = "T02", doc As %String = "DOC-1^DMS^1.2^ISO", parent As %String = "", conf As %String = "U", avail As %String = "AV", comp As %String = "AU") As %String
{
    Set cr = $CHAR(13)
    Quit "MSH|^~\&|SRC|HOSP|DMS|HOSP|20261105090000||MDM^" _ trigger _ "^MDM_T02|CTL1|P|2.5.1" _ cr _ "EVN|" _ trigger _ "|20261105090000" _ cr _ "PID|1||MRN1^^^HOSP^MR~999000^^^NHS&2.16&ISO^NH||CANARYNAME^X||19800101|F" _ cr _ "PV1|1|O|CLINIC1||||||||||||||||VISIT1" _ cr _ "TXA|1|CANARYTYPE|TX|20261105090000||||||||" _ doc _ "|" _ parent _ "|||CANARYFILE.pdf|" _ comp _ "|" _ conf _ "|" _ avail _ cr _ "OBX|1|TX|DOC^CANARYTITLE||CANARYOBX" _ cr
}

ClassMethod Block(text As %String, chainRows As %DynamicArray = "", complete As %Boolean = 1) As %DynamicObject
{
    Set b = ##class(Shutter.Util.DocumentFacts).FromText(text, .sc)
    Set b.source = {"namespace": "NS", "production": "P", "route": "R", "header_id": "100", "item": "Docs Out"}
    Set b.receiver = "Docs Out"
    Set b.delivery = {"status": "Error", "header_id": "100"}
    Do b.%Set("restricted", ##class(Shutter.Util.DocumentCase).IsRestricted(b.document.confidentiality), "boolean")
    Do b.%Set("source_verified", 1, "boolean")
    Do b.%Set("source_body_available", 1, "boolean")
    Set b.chain = {"read": 10, "item": "Docs Out", "since": "2026-11-05 09:00:00", "limit": 5000, "unreadable": 0, "rows": ($SELECT($ISOBJECT(chainRows): chainRows, 1: []))}
    Do b.chain.%Set("complete", complete, "boolean")
    Do b.chain.%Set("limit_reached", 0, "boolean")
    Do b.chain.%Set("rows_capped", 0, "boolean")
    Do ##class(Shutter.Util.DocumentCase).Conclude(b)
    Quit b
}

ClassMethod Row(header As %String, trigger As %String, doc As %String, parent As %String = "", binding As %String = "same", content As %String = "other") As %DynamicObject
{
    Quit {"header_id": (header), "trigger": (trigger), "control_id": ("C" _ header), "document_id": (doc), "parent_id": (parent), "completion": "AU", "confidentiality": "U", "availability": "AV", "patient_binding": (binding), "patient_keys": [], "time_created": "2026-11-05 09:01:00", "status": "Error", "body_digest": "x", "content_digest": (content)}
}

ClassMethod Codes(b As %DynamicObject) As %String
{
    Set out = "", it = b.reasons.%GetIterator()
    While it.%GetNext(, .r) { Set out = out _ "," _ r.code }
    Quit out _ ","
}

Method TestRecognisesEveryTriggerAndNoOther()
{
    Set f = "Shutter.Util.DocumentFacts"
    For n = 1:1:11 {
        Set t = "T" _ $TRANSLATE($JUSTIFY(n, 2), " ", "0")
        Do $$$AssertTrue($CLASSMETHOD(f, "IsDocumentText", ..Text(t)), t _ " is a document")
    }
    Do $$$AssertTrue('$CLASSMETHOD(f, "IsDocumentText", ..Text("T12")), "T12 is a query")
    Do $$$AssertTrue('$CLASSMETHOD(f, "IsDocumentText", "MSH|^~\&|S|H|D|H|2026||ORU^R01|1|P|2.5.1"), "an ORU is not")
    Do $$$AssertTrue('$CLASSMETHOD(f, "IsDocumentText", "MSH|^~\&|S|H|D|H|2026||ADT^T02|1|P|2.5.1"), "a trigger under another type is not")
}

Method TestReadsTheNamedFieldsWholeAndNoOther()
{
    Set b = ##class(Shutter.Util.DocumentFacts).FromText(..Text("T10", "NEW^DMS^1.2^ISO", "OLD^DMS"), .sc)
    Do $$$AssertStatusOK(sc)
    Do $$$AssertEquals(b.trigger, "T10")
    Do $$$AssertEquals(b.document.id, "NEW^DMS^1.2^ISO", "all of TXA-12")
    Do $$$AssertEquals(b.document.parent, "OLD^DMS", "all of TXA-13")
    Do $$$AssertEquals(b.document.completion, "AU")
    Do $$$AssertEquals(b.document.confidentiality, "U")
    Do $$$AssertEquals(b.document.availability, "AV")
    Do $$$AssertEquals(b.patient.keys.%Size(), 2, "every PID-3 repetition")
    Do $$$AssertEquals(b.patient.keys.%Get(1).authority, "NHS&2.16&ISO", "the whole assigning authority")
    Do $$$AssertEquals(b.encounter, "VISIT1")
    Do $$$AssertTrue('(b.%ToJSON() [ "CANARY"), "no name, type, file name, title or OBX")
}

Method TestAStoredMessageReadsTheSameAsItsText()
{
    Set text = ..Text()
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .isc)
    Do $$$AssertStatusOK(isc)
    Do $$$AssertTrue(##class(Shutter.Util.DocumentFacts).IsDocument(msg))
    Set a = ##class(Shutter.Util.DocumentFacts).FromMessage(msg, .sc, 0)
    Set b = ##class(Shutter.Util.DocumentFacts).FromText(text, .sc2)
    Do $$$AssertEquals(a.document.id, b.document.id)
    Do $$$AssertEquals(a.patient.binding, b.patient.binding)
    Do $$$AssertEquals(a.trigger, b.trigger)
}

Method TestDigestsTellContentFromTheControlId()
{
    Set one = ..Text(), two = $REPLACE(one, "CTL1", "CTL2"), three = $REPLACE(one, "CANARYOBX", "CHANGED")
    Set d = "Shutter.Util.DocumentDigest"
    Set a = $CLASSMETHOD(d, "OfText", one, .ca), b = $CLASSMETHOD(d, "OfText", two, .cb), c = $CLASSMETHOD(d, "OfText", three, .cc)
    Do $$$AssertEquals($LENGTH(a), 64)
    Do $$$AssertNotEquals(a, b, "the body includes MSH")
    Do $$$AssertEquals(ca, cb, "the content does not")
    Do $$$AssertNotEquals(ca, cc, "changed content")
    // The same however it is written in pieces.
    Set s = ##class(Shutter.Util.DocumentDigest).%New()
    For i = 1:7:$LENGTH(one) { Do s.Write($EXTRACT(one, i, i + 6)) }
    Do $$$AssertEquals(s.Finish(.cs), a)
    Do $$$AssertEquals(cs, ca)
}

Method TestAMissingNumberIsSaidAndNothingStandsInForIt()
{
    Set b = ..Block(..Text("T02", ""))
    Do $$$AssertEquals(b.document.id, "")
    Do $$$AssertTrue(..Codes(b) [ ",DOC_ID_MISSING,")
    Do $$$AssertTrue(b.headline [ "no usable document identifier")
    Do $$$AssertTrue('b.chain.complete, "no chain can be established")
    Do $$$AssertEquals(b.document.id, "", "not MSH-10, a name or a hash")
    // A blank number with only an assigning namespace names nothing.
    Do $$$AssertEquals(##class(Shutter.Util.DocumentFacts).EI("^DMS", "^"), "")
    Do $$$AssertEquals(##class(Shutter.Util.DocumentFacts).EI("X^DMS^^", "^"), "X^DMS")
}

Method TestChainReasons()
{
    Set doc = "DOC-1^DMS^1.2^ISO", b0 = ..Block(..Text()), bind = b0.patient.binding
    Set edited = ..Block(..Text(), [(..Row("101", "T08", doc, "", bind))])
    Do $$$AssertTrue(..Codes(edited) [ ",DOC_REPLACED_OR_EDITED,", "a T08")
    Do $$$AssertTrue(..Codes(edited) [ ",DOC_VERSION_CONFLICT,", "the same number, other content")
    Set replaced = ..Block(..Text(), [(..Row("102", "T10", "NEW^DMS", doc, bind))])
    Do $$$AssertTrue(..Codes(replaced) [ ",DOC_REPLACED_OR_EDITED,", "a T10 naming it as parent")
    Set cancelled = ..Block(..Text(), [(..Row("103", "T11", doc, "", bind))])
    Do $$$AssertTrue(..Codes(cancelled) [ ",DOC_CANCELLED,", "a T11")
    Do $$$AssertTrue('($ZCONVERT(cancelled.chain.says.%ToJSON(), "L") [ "deleted"), "T11 is no claim of deletion")
    Set other = ..Block(..Text(), [(..Row("104", "T02", doc, "", "anotherbinding", b0.digests.content))])
    Do $$$AssertTrue(..Codes(other) [ ",DOC_PATIENT_CHANGED,", "one number, two patients")
    Set again = ..Block(..Text(), [(..Row("105", "T02", doc, "", bind, b0.digests.content))])
    Do $$$AssertTrue(again.chain.says.%ToJSON() [ "retransmission", "the same content under another control id")
    Do $$$AssertTrue('(..Codes(again) [ ",DOC_VERSION_CONFLICT,"), "and no conflict")
    Set self = ..Block(..Text(), [(..Row("100", "T02", doc, "", "anotherbinding"))])
    Do $$$AssertTrue('(..Codes(self) [ ",DOC_PATIENT_CHANGED,"), "its own row in the chain finds nothing")
}

Method TestParents()
{
    Set absent = ..Block(..Text("T06", "ADD^DMS", "GONE^DMS"))
    Do $$$AssertTrue(..Codes(absent) [ ",DOC_PARENT_UNPROVEN,")
    Do $$$AssertTrue(absent.chain.says.%ToJSON() [ "not found")
    Set none = ..Block(..Text("T10", "NEW^DMS", ""))
    Do $$$AssertTrue(..Codes(none) [ ",DOC_PARENT_UNPROVEN,", "the standard requires a parent on T10")
    Set present = ..Block(..Text("T06", "ADD^DMS", "OLD^DMS"), [(..Row("90", "T02", "OLD^DMS"))])
    Do $$$AssertTrue(..Codes(present) [ ",DOC_PARENT_UNPROVEN,", "a parent in the store is not a parent at the receiver")
    Do $$$AssertTrue(present.chain.says.%ToJSON() [ "does not show the receiver holds it")
}

Method TestCoverageIsSaid()
{
    Set b = ..Block(..Text(), "", 0)
    Do $$$AssertTrue(..Codes(b) [ ",DOC_CHAIN_INCOMPLETE,")
    Do $$$AssertTrue(b.chain.says.%ToJSON() [ "incomplete")
    Set c = ..Block(..Text())
    Do $$$AssertTrue(c.chain.says.%ToJSON() [ "Older messages and other routes are not covered", "a clean read says what it covered, never no later document")
}

Method TestStatuses()
{
    For conf = "R", "V", "ZZ" { Do $$$AssertTrue(..Block(..Text("T02", "D^X", "", conf)).restricted, conf _ " is restricted") }
    Do $$$AssertTrue('..Block(..Text("T02", "D^X", "", "")).restricted, "an absent TXA-18 is not")
    Do $$$AssertTrue(..Codes(..Block(..Text("T02", "D^X", "", "U", "CA"))) [ ",DOC_CANCELLED,")
    Do $$$AssertTrue(..Codes(..Block(..Text("T02", "D^X", "", "U", "OB"))) [ ",DOC_REPLACED_OR_EDITED,")
    Do $$$AssertTrue(..Codes(..Block(..Text("T02", "D^X", "", "U", "ZZ"))) [ ",DOC_STATUS_UNPROVEN,")
    Do $$$AssertTrue(..Codes(..Block(..Text("T02", "D^X", "", "U", "AV", ""))) [ ",DOC_STATUS_UNPROVEN,", "TXA-17 is required")
    Do $$$AssertTrue(..Codes(..Block(..Text("T02", "D^X", "", "", ""))) [ ",DOC_STATUS_UNPROVEN,")
}

Method TestTheSendersQuestionFailsClosed()
{
    Set e = "Shutter.Util.DocumentEligibility", defaults = ##class(Shutter.Util.DocumentCase).DefaultSettings()
    Set good = ..Block(..Text())
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", good, defaults), "DOC_RECOVERY_OFF", "the defaults answer off")
    Set s = {"enabled": true, "owner_accepts_acknowledged_recovery": true, "recovery": "original_t02", "duplicates": "rejects_exact", "allowed_completion": ["AU"], "allowed_confidentiality": ["U"], "allowed_availability": ["AV"]}
    Set clean = {"engine_settled": true, "evidence_complete": true, "never_opened_every_attempt": true, "patient_history_checked": true, "patient_history_clear": true}
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", good, s), "DOC_DELIVERY_UNCERTAIN", "no delivery evidence: not eligible")
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", good, s, clean), "DOC_T02_ELIGIBLE", "the one way through")
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", ..Block(..Text("T04")), s, clean), "DOC_NOT_ORIGINAL_T02")
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", ..Block(..Text("T02", "")), s, clean), "DOC_ID_MISSING")
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", ..Block(..Text("T02", "D^X", "", "R")), s, clean), "DOC_RESTRICTED")
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", ..Block(..Text(), "", 0), s, clean), "DOC_CHAIN_INCOMPLETE")
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", ..Block(..Text("T02", "D^X", "", "", "AV")), s, clean), "DOC_STATUS_UNPROVEN", "an optional status absent stops a sender")
    Set unknown = {"enabled": true, "owner_accepts_acknowledged_recovery": true, "recovery": "original_t02", "duplicates": "unknown", "allowed_completion": ["AU"], "allowed_confidentiality": ["U"], "allowed_availability": ["AV"]}
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", good, unknown, clean), "DOC_DUPLICATE_UNDECLARED")
    Set c2 = {"engine_settled": false, "evidence_complete": true, "never_opened_every_attempt": true, "patient_history_checked": true, "patient_history_clear": true}
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", good, s, c2), "DOC_ENGINE_OWNS_DELIVERY")
    Set c3 = {"engine_settled": true, "evidence_complete": true, "never_opened_every_attempt": true, "patient_history_checked": false}
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", good, s, c3), "DOC_PATIENT_CHANGED", "merges not checked: stop")
    Set empty = {"enabled": true, "owner_accepts_acknowledged_recovery": true, "recovery": "original_t02", "duplicates": "rejects_exact"}
    Do $$$AssertEquals($CLASSMETHOD(e, "Check", good, empty, clean), "DOC_STATUS_UNPROVEN", "empty allow lists allow nothing")
}

Method TestNoScreenCodeSaysEligible()
{
    Set b = ..Block(..Text())
    Do $$$AssertTrue('(b.%ToJSON() [ "ELIGIBLE"), "the block never holds it")
    Do $$$AssertEquals(##class(Shutter.Util.DocumentEligibility).Words("DOC_T02_ELIGIBLE"), "", "and it has no words")
}

Method TestSettings()
{
    Set c = "Shutter.Util.DocumentCase"
    Set d = $CLASSMETHOD(c, "DefaultSettings")
    Do $$$AssertTrue('d.enabled, "off")
    Do $$$AssertEquals(d.recovery, "none")
    Do $$$AssertEquals(d.duplicates, "unknown")
    Do $$$AssertEquals(d."email_details", "minimal")
    Do $$$AssertEquals(d."ack_level", "connection")
    Do $$$AssertEquals(d."allowed_completion".%Size(), 0)
    Do $$$AssertTrue('$CLASSMETHOD(c, "Enabled", "No such receiver"))
    Do $$$AssertEquals($CLASSMETHOD(c, "SettingsProblem", {"enabled": true}), "")
    Do $$$AssertTrue($CLASSMETHOD(c, "SettingsProblem", {"enabeld": true}) [ "unknown setting", "a misspelt switch cannot pass as off")
    Do $$$AssertTrue($CLASSMETHOD(c, "SettingsProblem", {"enabled": "yes"}) [ "true or false")
    Do $$$AssertTrue($CLASSMETHOD(c, "SettingsProblem", {"recovery": "original_t02"}) [ "resends no document", "no setting can ask for a send yet")
    Do $$$AssertTrue($CLASSMETHOD(c, "SettingsProblem", {"readback": "t12"}) [ "reads no document back")
    Do $$$AssertTrue($CLASSMETHOD(c, "SettingsProblem", {"chain_read_limit": 0}) [ "at least 1")
}

Method TestTheEmailIsMinimal()
{
    Set usual = ##class(Shutter.Store.Case).%New(), usual.CaseId = "UT-DOC", usual.Receiver = "Docs Out", usual.PatientId = "MRN1"
    Set usual.DocumentJSON = ..Block(..Text()).%ToJSON()
    Do $$$AssertStatusOK(##class(Shutter.Util.EscalationDraft).Build(usual, {"name": "Team"}, .subject, .body))
    Do $$$AssertTrue(body [ "Shutter has sent nothing")
    Do $$$AssertTrue(body [ "UT-DOC")
    Do $$$AssertTrue(body [ "Docs Out")
    Do $$$AssertTrue(body [ "Team")
    For word = "MRN1", "DOC-1", "CANARY", "verifies" { Do $$$AssertTrue('((subject _ body) [ word), "no " _ word) }
    Set hidden = ##class(Shutter.Store.Case).%New(), hidden.CaseId = "UT-DOC2", hidden.Receiver = "Docs Out"
    Set hidden.DocumentJSON = ..Block(..Text("T02", "SECRETDOC^X", "", "R")).%ToJSON()
    Do $$$AssertStatusOK(##class(Shutter.Util.EscalationDraft).Build(hidden, "", .subject2, .body2))
    Do $$$AssertTrue(body2 [ "requires an authorised reviewer")
    Do $$$AssertTrue('(body2 [ "SECRETDOC"))
    Do $$$AssertTrue('(body2 [ "DOC_"), "a restricted notice gives no reason codes")
}

Method TestTheOperationCarriesNoIdentifierInItsKey()
{
    Set b = ..Block(..Text("T02", "SECRETDOC^X"))
    Set op = ##class(Shutter.Util.DocumentCase).Operation(b)
    Do $$$AssertTrue($EXTRACT(op."operation_key", 1, 7) = "mdm-v1:")
    Do $$$AssertTrue('(op."operation_key" [ "SECRETDOC"))
    Do $$$AssertEquals(op."patient_id", "MRN1", "the MR repetition")
    Do $$$AssertEquals(op."encounter_id", "-", "no encounter logic")
    Set r = ##class(Shutter.Util.DocumentCase).Operation(..Block(..Text("T02", "SECRETDOC^X", "", "R")))
    Do $$$AssertEquals(r."patient_id", "", "a restricted document's patient stays off the case's columns")
    // One stored delivery: another header is another operation, with the same number and body.
    Set b2 = ..Block(..Text("T02", "SECRETDOC^X")), b2.source."header_id" = "200"
    Do $$$AssertNotEquals(##class(Shutter.Util.DocumentCase).Operation(b2)."operation_key", op."operation_key")
}

Method TestTheEvidencesBlockHoldsNoWords()
{
    Set b = ..Block(..Text("T02", "SECRETDOC^X", "", "R"))
    Set b.refusal = ##class(Shutter.Util.DocumentCase).Refusal("rejected", "rejected", "ack_AE", "", "CANARYDIAG unknown patient")
    Set e = ##class(Shutter.Util.DocumentCase).ForEvidence(b)
    Do $$$AssertEquals(e.refusal."ack_code", "AE")
    Do $$$AssertTrue('(e.%ToJSON() [ "CANARYDIAG"), "no receiver's words")
    Do $$$AssertTrue('(e.%ToJSON() [ "SECRETDOC"), "no restricted identity")
    Do $$$AssertTrue('(e.%ToJSON() [ "MRN1"), "no restricted patient")
}

}
