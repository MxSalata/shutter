/// Shutter.Util.CaseFindings: which cases get findings, the custody in words, the text the OBX finding matches, and the
/// draft's lines, which carry no free text of the receiver's. Every wording here is made up.
Class Shutter.Test.EvidenceFindings Extends %UnitTest.TestCase
{

/// Orders and results get findings; ADT, SIU and MDM do not, so their evidence is unchanged.
Method TestApplies()
{
    For type = "ORU^R01", "ORM^O01", "OML^O21", "OUL^R22" { Do $$$AssertTrue(##class(Shutter.Util.CaseFindings).Applies({"message_type": (type)}), type) }
    For type = "ADT^A02", "SIU^S12", "MDM^T02", "", "O" { Do $$$AssertNotTrue(##class(Shutter.Util.CaseFindings).Applies({"message_type": (type)}), "not " _ type) }
    Do $$$AssertNotTrue(##class(Shutter.Util.CaseFindings).Applies(""), "no message")
}

/// The custody in words: the engine holding the message outranks the log.
Method TestCustodyWords()
{
    Do $$$AssertTrue(##class(Shutter.Util.CaseFindings).CustodyWords("never_opened", "engine") [ "The engine holds this message and is still trying it", "the engine holds it")
    Do $$$AssertTrue(##class(Shutter.Util.CaseFindings).CustodyWords("reached_receiver", "settled") [ "The receiver took this message on at least one attempt", "reached the receiver")
    Do $$$AssertTrue(##class(Shutter.Util.CaseFindings).CustodyWords("never_opened", "settled") [ "The log may not keep every attempt", "never opened, with its limit")
    Do $$$AssertTrue(##class(Shutter.Util.CaseFindings).CustodyWords("unknown", "unreadable") [ "does not show", "unknown")
}

/// The OBX finding matches codes in MSA-3 and each ERR's words, or the unknown words.
Method TestWordsToMatch()
{
    Set reply = ##class(Shutter.Util.ReplyWords).FromLog("MSA|AE|T-1| ERR||OBR^1^4|103^Table value not found^HL70357|E|||Test code FBX not in test catalogue|Unknown test code")
    Do $$$AssertTrue(##class(Shutter.Util.CaseFindings).WordsToMatch(reply) [ "FBX", "ERR-7's code reached")
    Set reply = ##class(Shutter.Util.ReplyWords).FromLog("REJECTED ZZUNK")
    Do $$$AssertTrue(##class(Shutter.Util.CaseFindings).WordsToMatch(reply) [ "ZZUNK", "unknown words used as they are")
}

/// The draft's lines: the custody, the reply's codes, the OBX and the character, and never the receiver's own words.
Method TestDraftLinesHoldNoFreeText()
{
    Set reply = ##class(Shutter.Util.ReplyWords).FromLog("MSA|AE|T-2|No patient Testpatient Alpha born 1980 ERR||PID^1^3|204^Unknown key identifier^HL70357|E|||No patient with identifier MRN-FAKE-1|Patient not found")
    Set obx = {"kind": "obx", "sentence": "The receiver's words name the 4th OBX of 6, set id OBX-1 = 4, code 'ZZUNK'."}
    Set character = {"kind": "characters", "fields": [{"field": "PID-5", "character": "e with a grave accent, U+00E8", "wire": "E8"}]}
    Set findings = {"custody": {"words": "The engine holds this message and is still trying it: do not resend it and do not re-enter it by hand."}, "reply": (reply), "obx": (obx), "character": (character)}
    Set lines = ##class(Shutter.Util.CaseFindings).DraftLines(findings)
    Do $$$AssertTrue(lines [ "The engine holds this message", "the custody")
    Do $$$AssertTrue(lines [ "The receiver answered AE, error code 204 (HL70357); its words are on the case page.", "the codes only")
    Do $$$AssertTrue(lines [ "set id OBX-1 = 4", "the OBX")
    Do $$$AssertTrue(lines [ "PID-5 holds e with a grave accent, U+00E8; the operation sends E8.", "the character")
    For text = "Testpatient", "1980", "MRN-FAKE-1", "Patient not found", "Unknown key identifier" { Do $$$AssertNotTrue(lines [ text, "no free text: " _ text) }
    Do $$$AssertEquals(##class(Shutter.Util.CaseFindings).DraftLines(""), "", "no findings, no lines")
}

/// A structure finding says so without quoting the validator's words.
Method TestSchemaLine()
{
    Set lines = ##class(Shutter.Util.CaseFindings).DraftLines({"custody": {}, "reply": {"msa1": "", "errors": []}, "obx": {"kind": "schema", "sentence": "x"}, "character": {}})
    Do $$$AssertTrue(lines [ "does not fit its structure", lines)
}

}
