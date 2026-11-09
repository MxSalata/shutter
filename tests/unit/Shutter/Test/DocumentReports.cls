/// Reports carried as attachments (CONTRACTS 11.2): an ORU with an attachment OBX at a receiver with a document profile. What
/// counts as one, what is read of it and what is not, its one chain rule, and the words a person reads. The whole flow, through a
/// real production and a real forwarder, is tests/e2e/documents_check.py.
Class Shutter.Test.DocumentReports Extends %UnitTest.TestCase
{

/// An ORU's text. obx is its OBX lines; each canary is a value Shutter must never read.
ClassMethod Text(obx As %String, control As %String = "CTL1", placer As %String = "ORD-1^LAB", filler As %String = "REP-1^LAB", status As %String = "F", type As %String = "ORU^R01^ORU_R01") As %String
{
    Set cr = $CHAR(13)
    Quit "MSH|^~\&|LAB|HOSP|EPR|HOSP|20261105090000||" _ type _ "|" _ control _ "|P|2.5.1" _ cr _ "PID|1||MRN1^^^HOSP^MR~999000^^^NHS^NH||CANARYNAME^X||19800101|F" _ cr _ "PV1|1|O|CLINIC1||||||||||||||||VISIT1" _ cr _ "ORC|RE|" _ placer _ "|" _ filler _ cr _ ..Obr(placer, filler, status) _ cr _ obx _ cr
}

ClassMethod Obr(placer As %String, filler As %String, status As %String) As %String
{
    Quit "OBR|1|" _ placer _ "|" _ filler _ "|CANARYTEST^Test^L||||||||||||||||||20261105090000|||" _ status
}

ClassMethod Ed() As %String
{
    Quit "OBX|1|ED|REP^CANARYTITLE^L||^application^pdf^Base64^JVBERi0xLjQgQ0FOQVJZ"
}

ClassMethod Block(text As %String, rows As %DynamicArray = "", complete As %Boolean = 1) As %DynamicObject
{
    Set b = ##class(Shutter.Util.DocumentFacts).FromText(text, .sc)
    Set b.source = {"namespace": "NS", "production": "P", "route": "R", "header_id": "100", "item": "Docs Out"}
    Set b.receiver = "Docs Out"
    Set b.delivery = {"status": "Error", "header_id": "100"}
    Do b.%Set("restricted", 0, "boolean")
    Do b.%Set("source_verified", 1, "boolean")
    Do b.%Set("source_body_available", 1, "boolean")
    Set b.chain = {"read": 10, "item": "Docs Out", "since": "2026-11-05 09:00:00", "limit": 5000, "unreadable": 0, "rows": ($SELECT($ISOBJECT(rows): rows, 1: []))}
    Do b.chain.%Set("complete", complete, "boolean")
    Do b.chain.%Set("limit_reached", 0, "boolean")
    Do b.chain.%Set("rows_capped", 0, "boolean")
    Do ##class(Shutter.Util.DocumentCase).Conclude(b)
    Quit b
}

ClassMethod Row(header As %String, status As %String, placer As %String = "ORD-1^LAB", filler As %String = "REP-1^LAB", control As %String = "") As %DynamicObject
{
    Quit {"header_id": (header), "trigger": "R01", "control_id": ($SELECT(control '= "": control, 1: "C" _ header)), "placer": (placer), "filler": (filler), "result_status": (status), "time_created": "2026-11-05 09:01:00", "status": "Error"}
}

ClassMethod Codes(b As %DynamicObject) As %String
{
    Set out = "", it = b.reasons.%GetIterator()
    While it.%GetNext(, .r) { Set out = out _ "," _ r.code }
    Quit out _ ","
}

ClassMethod Says(b As %DynamicObject) As %String
{
    Set out = "", it = b.chain.says.%GetIterator()
    While it.%GetNext(, .s) { Set out = out _ " " _ s }
    Quit out
}

/// The rule: OBX-2 says ED or RP. Anything else is not a report here, a value that looks like base64 included.
Method TestTheRule()
{
    Set f = "Shutter.Util.DocumentFacts", long = $TRANSLATE($JUSTIFY("", 300), " ", "A")
    Do $$$AssertEquals($CLASSMETHOD(f, "Attachment", "ED"), "ED")
    Do $$$AssertEquals($CLASSMETHOD(f, "Attachment", "RP"), "RP")
    Do $$$AssertEquals($CLASSMETHOD(f, "Attachment", "ed"), "ED", "whatever its case")
    Do $$$AssertEquals($CLASSMETHOD(f, "Attachment", "NM"), "")
    Do $$$AssertEquals($CLASSMETHOD(f, "Attachment", "TX"), "")
    Do $$$AssertEquals($CLASSMETHOD(f, "Attachment", ""), "")
    Do $$$AssertTrue('$CLASSMETHOD(f, "IsReportText", ..Text("OBX|1|TX|N^Note||" _ long)), "base64 under TX is text")
    Do $$$AssertTrue('$CLASSMETHOD(f, "IsReportText", ..Text("OBX|1|ST|N^Note||^application^pdf^Base64^" _ long)), "and under ST, in a component")
    Do $$$AssertTrue($CLASSMETHOD(f, "IsReportText", ..Text("OBX|1|TX|N^Note||" _ long _ $CHAR(13) _ ..Ed())), "an ED after it still counts")
}

Method TestTheTextSaysWhichMessagesAreReports()
{
    Set f = "Shutter.Util.DocumentFacts"
    Do $$$AssertTrue($CLASSMETHOD(f, "IsReportText", ..Text(..Ed())), "an ED")
    Do $$$AssertTrue($CLASSMETHOD(f, "IsReportText", ..Text("OBX|1|NM|K^Potassium||5.4" _ $CHAR(13) _ ..Ed())), "an ED after a number")
    Do $$$AssertTrue('$CLASSMETHOD(f, "IsReportText", ..Text("OBX|1|NM|K^Potassium||5.4")), "numbers only")
    Do $$$AssertTrue('$CLASSMETHOD(f, "IsReportText", ..Text("OBX|1|TX|N^Note||Plain words")), "text only")
    Do $$$AssertTrue('$CLASSMETHOD(f, "IsReportText", ..Text("NTE|1||No OBX here")), "no OBX")
    Do $$$AssertTrue('$CLASSMETHOD(f, "IsReportText", ##class(Shutter.Test.Documents).Text()), "an MDM is no report")
    Do $$$AssertTrue('$CLASSMETHOD(f, "IsDocumentText", ..Text(..Ed())), "and a report is no MDM")
}

Method TestReadsTheNamedFieldsAndNoOther()
{
    Set b = ..Block(..Text(..Ed() _ $CHAR(13) _ "OBX|2|TX|N^CANARYTITLE||CANARYOBXTEXT" _ $CHAR(13) _ "NTE|1||CANARYNOTE"))
    Do $$$AssertEquals(b.kind, "report")
    Do $$$AssertEquals(b.trigger, "R01")
    Do $$$AssertEquals(b."message_type", "ORU^R01")
    Do $$$AssertEquals(b.report.placer, "ORD-1^LAB", "OBR-2")
    Do $$$AssertEquals(b.report.filler, "REP-1^LAB", "OBR-3")
    Do $$$AssertEquals(b.report."result_status", "F", "OBR-25")
    Do $$$AssertEquals(b.report.attachment, "ED")
    Do $$$AssertEquals(b.document.id, "REP-1^LAB", "the case's identity is the report's number")
    Do $$$AssertEquals(b.patient.keys.%Size(), 2, "every PID-3 repetition")
    Do $$$AssertEquals(b.patient.keys.%Get(1).id, "999000")
    Do $$$AssertEquals(b.encounter, "VISIT1")
    Do $$$AssertTrue('(b.%ToJSON() [ "CANARY"), "nothing else is read: " _ b.%ToJSON())
    Do $$$AssertTrue('(b.%ToJSON() [ "JVBER"), "and none of the value")
    Do $$$AssertEquals($LENGTH(b.digests.body), 64)
    Set none = ..Block(..Text(..Ed(), "CTL1", "ORD-1^LAB", ""))
    Do $$$AssertEquals(none.document.id, "ORD-1^LAB", "the order's number when it has no report's")
}

/// An ORU's order groups: the identity is the one carrying the first attachment, and the message says it has more.
Method TestSeveralOrdersInOneMessage()
{
    Set cr = $CHAR(13)
    Set text = ..Text("OBX|1|NM|K^Potassium||5.4" _ cr _ ..Obr("ORD-2^LAB", "REP-2^LAB", "P") _ cr _ ..Ed())
    Set b = ..Block(text)
    Do $$$AssertEquals(b.report.placer, "ORD-2^LAB", "the attachment's own OBR")
    Do $$$AssertEquals(b.report."result_status", "P")
    Do $$$AssertEquals(b.report.orders, 2)
    Do $$$AssertTrue(..Says(b) [ "2 orders", "the case says so: " _ ..Says(b))
}

/// What a stored message gives is what its text gives, and the walk leaves the message's value alone.
Method TestAStoredMessageReadsTheSameAsItsText()
{
    Set text = ..Text(..Ed() _ $CHAR(13) _ "OBX|2|TX|N^CANARYTITLE||CANARYOBXTEXT")
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    Do $$$AssertStatusOK(sc)
    Do $$$AssertStatusOK(msg.%Save())
    Do $$$AssertTrue(##class(Shutter.Util.DocumentFacts).IsReportMessage(msg), "an ORU message")
    Do $$$AssertTrue('##class(Shutter.Util.DocumentFacts).IsDocument(msg), "no MDM")
    Set stored = ##class(Shutter.Util.DocumentFacts).FromMessage(msg, .sc1)
    Do $$$AssertStatusOK(sc1)
    Set posted = ##class(Shutter.Util.DocumentFacts).FromText(text, .sc2)
    Do $$$AssertEquals(stored.report.%ToJSON(), posted.report.%ToJSON())
    Do $$$AssertEquals(stored.patient.%ToJSON(), posted.patient.%ToJSON())
    Do $$$AssertEquals(stored.digests.body, posted.digests.body)
    Do $$$AssertEquals(stored.digests.content, posted.digests.content)
    Do $$$AssertTrue('(stored.%ToJSON() [ "CANARY"), stored.%ToJSON())
    Set numeric = ##class(EnsLib.HL7.Message).ImportFromString(..Text("OBX|1|NM|K^Potassium||5.4"), .sc)
    Do $$$AssertStatusOK(numeric.%Save())
    Do $$$AssertEquals(##class(Shutter.Util.DocumentFacts).FromMessage(numeric, .sc3, 0).report.attachment, "", "no attachment")
    Do ##class(EnsLib.HL7.Message).%DeleteId(msg.%Id()), ##class(EnsLib.HL7.Message).%DeleteId(numeric.%Id())
}

/// The one chain rule: a further message for the same order or report under another result status, said plainly.
Method TestTheChainsOneRule()
{
    Set text = ..Text(..Ed(), "CTL1", "ORD-1^LAB", "REP-1^LAB", "P")
    Set own = ..Row("100", "P", , , "CTL1")
    Set b = ..Block(text, [(own), (..Row("101", "F"))])
    Do $$$AssertTrue(..Codes(b) [ ",DOC_RESULT_STATUS_CHANGED,", ..Codes(b))
    Do $$$AssertTrue((..Says(b) [ "header 101") && (..Says(b) [ "Final results (F)") && (..Says(b) [ "Preliminary (P)"), ..Says(b))
    Do $$$AssertEquals(b.chain.findings."status_changes".%Size(), 1)
    Set same = ..Block(text, [(own), (..Row("101", "P"))])
    Do $$$AssertTrue('(..Codes(same) [ "RESULT_STATUS"), "the same status is not the rule: " _ ..Codes(same))
    Set other = ..Block(text, [(own), (..Row("101", "F", "ORD-9^LAB", "REP-9^LAB"))])
    Do $$$AssertTrue('(..Codes(other) [ "RESULT_STATUS"), "another order and report")
    Set order = ..Block(text, [(own), (..Row("101", "F", "ORD-1^LAB", "REP-9^LAB"))])
    Do $$$AssertTrue(..Codes(order) [ "RESULT_STATUS", "the same order, under another report's number")
    Set report = ..Block(text, [(own), (..Row("101", "F", "", "REP-1^LAB"))])
    Do $$$AssertTrue(..Codes(report) [ "RESULT_STATUS", "the same report, no order's number")
    Set blank = ..Block(text, [(own), (..Row("101", "", "ORD-1^LAB", "REP-1^LAB"))])
    Do $$$AssertTrue((..Codes(blank) [ "RESULT_STATUS") && (..Says(blank) [ "no result status"), "a missing status is another status: " _ ..Says(blank))
    Do $$$AssertTrue('(..Says(b) [ "supersede") && '(..Says(b) [ "replace") && '(..Says(b) [ "latest"), "it says what it found and no more")
    // The MDM's rules aren't an ORU's.
    Do $$$AssertTrue('(..Codes(b) [ "VERSION_CONFLICT") && '(..Codes(b) [ "PATIENT_CHANGED") && '(..Codes(b) [ "STATUS_UNPROVEN") && '(..Codes(b) [ "PARENT"), ..Codes(b))
    Set plain = ..Block(text)
    Do $$$AssertTrue(..Says(plain) [ "No message for this order or report", ..Says(plain))
    Do $$$AssertEquals(..Codes(plain), ",", "no reason at all from a clean read")
}

Method TestAMissingNumberIsSaid()
{
    Set b = ..Block(..Text(..Ed(), "CTL1", "", ""))
    Do $$$AssertTrue(..Codes(b) [ "DOC_ID_MISSING", ..Codes(b))
    Do $$$AssertEquals(b.document.id, "", "nothing stands in for it")
    Do $$$AssertTrue(b.headline [ "no usable order or report number", b.headline)
    Do $$$AssertEquals(b.chain.complete, 0)
    Do $$$AssertTrue(..Says(b) [ "cannot establish", ..Says(b))
}

Method TestItsCaseWordsAreAReports()
{
    Set c = "Shutter.Util.DocumentCase"
    Set b = ..Block(..Text(..Ed()))
    Do $$$AssertEquals(b.headline, "Report delivery needs review. Shutter has sent nothing.")
    Do $$$AssertTrue($EXTRACT($CLASSMETHOD(c, "Operation", b)."operation_key", 1, 7) = "oru-v1:")
    Do $$$AssertTrue('($CLASSMETHOD(c, "Operation", b)."operation_key" [ "REP-1"), "no identifier in its key")
    Do $$$AssertEquals($CLASSMETHOD(c, "Operation", b)."patient_id", "MRN1", "the MR repetition")
    Do $$$AssertEquals($PIECE($CLASSMETHOD(c, "FailureWords", b), ":", 1), "This message is ORU, not ADT")
    Set case = ##class(Shutter.Store.Case).%New(), case.CaseId = "UT-REP", case.Receiver = "Docs Out", case.PatientId = "MRN1"
    Set case.DocumentJSON = b.%ToJSON()
    Do $$$AssertStatusOK(##class(Shutter.Util.EscalationDraft).Build(case, {"name": "Team"}, .subject, .body))
    Do $$$AssertTrue(subject [ "report delivery needs review", subject)
    Do $$$AssertTrue(body [ "resends no report", body)
    For word = "MRN1", "REP-1", "ORD-1", "CANARY", "JVBER" { Do $$$AssertTrue('((subject _ body) [ word), "no " _ word) }
    Do $$$AssertTrue(##class(Shutter.Util.DocumentEligibility).Check(b, {"recovery": "original_t02", "enabled": true, "owner_accepts_acknowledged_recovery": true}, {}) = "DOC_NOT_ORIGINAL_T02", "a sender's question stays shut for a report")
    Set e = $CLASSMETHOD(c, "ForEvidence", b)
    Do $$$AssertTrue('(e.%ToJSON() [ "CANARY") && '(e.%ToJSON() [ "JVBER"), "the evidence's block")
}

Method TestTheStructuresSetting()
{
    Set c = "Shutter.Util.DocumentCase"
    Do $$$AssertEquals($CLASSMETHOD(c, "DefaultSettings")."report_structures".%ToJSON(), "[""ORU^R01""]")
    Do $$$AssertEquals($CLASSMETHOD(c, "SettingsProblem", {"report_structures": ["ORU^R01", "ORU^R30"]}), "")
    Do $$$AssertEquals($CLASSMETHOD(c, "SettingsProblem", {"report_structures": []}), "", "none: this receiver's reports take the ordinary path")
    Do $$$AssertTrue($CLASSMETHOD(c, "SettingsProblem", {"report_structures": ["MDM^T02"]}) [ "ORU^", "only ORU")
    Do $$$AssertTrue($CLASSMETHOD(c, "SettingsProblem", {"report_structures": "ORU^R01"}) [ "an array")
    Do $$$AssertTrue($CLASSMETHOD(c, "Counts", ["ORU^R01"], "ORU^R01"))
    Do $$$AssertTrue('$CLASSMETHOD(c, "Counts", ["ORU^R01"], "ORU^R30"))
    Do $$$AssertTrue('$CLASSMETHOD(c, "Counts", [], "ORU^R01"))
}

/// The intake's choice, for each kind of message at a receiver with a profile and one without.
Method TestTheIntakeTakesOnlyAReportAtAProfile()
{
    Set keep = ##class(Shutter.Store.SiteProfile).Current().%ToJSON()
    Try {
        Set p = ##class(%DynamicObject).%FromJSON(keep)
        If '$ISOBJECT(p.%Get("receivers")) Set p.receivers = []
        Set entry = {"name": "UT Reports", "system": "x", "tier": 3, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "features": {"conditional_writes": false, "receipts": false, "history": false, "dry_run": false}, "documents": {"enabled": true}}
        Do p.receivers.%Push(entry)
        Set sc = ##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "test", "report test")
        Do $$$AssertStatusOK(sc)
        Set i = "Shutter.API.DocumentIntake"
        Do $$$AssertTrue($CLASSMETHOD(i, "Takes", {"message": (..Text(..Ed())), "receiver": "UT Reports"}), "an attachment")
        Do $$$AssertTrue('$CLASSMETHOD(i, "Takes", {"message": (..Text("OBX|1|NM|K^Potassium||5.4")), "receiver": "UT Reports"}), "numbers stay as they are")
        Do $$$AssertTrue('$CLASSMETHOD(i, "Takes", {"message": (..Text(..Ed())), "receiver": "No such receiver"}), "no profile stays as it is")
        Do $$$AssertTrue('$CLASSMETHOD(i, "Takes", {"message": (..Text(..Ed(), , , , , "ORU^R30^ORU_R30")), "receiver": "UT Reports"}), "a structure the profile doesn't name")
    } Catch ex {
        Do $$$AssertTrue(0, ex.DisplayString())
    }
    Do ##class(Shutter.Store.SiteProfile).Store(keep, "test", "report test over")
}

/// TXA-19 CA in the standard's own word, and the email's retry sentence only where something can retry.
Method TestWordsFromTheReview()
{
    Do $$$AssertTrue(##class(Shutter.Util.DocumentEligibility).Words("DOC_CANCELLED") [ "says deleted", "table 0273 calls CA Deleted")
    Set b = ##class(Shutter.Test.Documents).Block(##class(Shutter.Test.Documents).Text())
    Set b.refusal = ##class(Shutter.Util.DocumentCase).Refusal("rejected", "rejected", "ack_AE", "", "words")
    Set case = ##class(Shutter.Store.Case).%New(), case.CaseId = "UT-REJ", case.Receiver = "Docs Out", case.DocumentJSON = b.%ToJSON()
    Do $$$AssertStatusOK(##class(Shutter.Util.EscalationDraft).Build(case, {"name": "Team"}, .subject, .body))
    Do $$$AssertTrue('(body [ "retries"), "a rejection isn't retried: " _ body)
    Do $$$AssertTrue(body [ "Message Viewer", "the check stays")
    Do b.%Remove("refusal")
    Set case.DocumentJSON = b.%ToJSON()
    Do $$$AssertStatusOK(##class(Shutter.Util.EscalationDraft).Build(case, {"name": "Team"}, .subject, .body2))
    Do $$$AssertTrue(body2 [ "retries", "a failed connection keeps it")
}

}
