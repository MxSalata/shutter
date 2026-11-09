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
    Do $$$AssertTrue(##class(Shutter.Util.CaseFindings).CustodyWords("never_opened", "engine") [ "The engine holds it; it is still trying this message", "the engine holds it")
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
    Set findings = {"custody": {"words": "The engine holds it; it is still trying this message: do not resend it and do not re-enter it by hand."}, "reply": (reply), "obx": (obx), "character": (character)}
    Set lines = ##class(Shutter.Util.CaseFindings).DraftLines(findings)
    Do $$$AssertTrue(lines [ "The engine holds it", "the custody")
    Do $$$AssertTrue(lines [ "The receiver answered AE, error code 204 (HL70357); its words are on the case page.", "the codes only")
    Do $$$AssertTrue(lines [ "set id OBX-1 = 4", "the OBX")
    Do $$$AssertTrue(lines [ "PID-5 holds e with a grave accent, U+00E8; the operation sends E8.", "the character")
    For text = "Testpatient", "1980", "MRN-FAKE-1", "Patient not found", "Unknown key identifier" { Do $$$AssertNotTrue(lines [ text, "no free text: " _ text) }
    Do $$$AssertEquals(##class(Shutter.Util.CaseFindings).DraftLines(""), "", "no findings, no lines")
}

/// CONTRACTS 10: the real finders on a result whose OBX-5 holds a value, units, a comment and an accented character; the
/// draft's lines name the segment, field and code, and carry none of the result's content.
Method TestDraftCarriesNoResultContent()
{
    Set cr = $CHAR(13), eg = $CHAR(232)
    Set text = "MSH|^~&|FAKESEND|SITE|FAKELIMS|LAB|20261105100000||ORU^R01|C77|P|2.5.1" _ cr _ "PID|1||9990000177^^^NHS^NH||Testpatient^Alpha||19800101|U" _ cr _ "OBR|1|ORD77|FIL77|PANEL1^Made-up panel^MADELAB" _ cr _ "OBX|1|ST|TST01^Made-up test 01^MADELAB||RESULT-SECRET-41|mmol/L|1-5|H|||F" _ cr _ "OBX|2|ST|ZZUNK^Made-up test NK^MADELAB||VALUE-SECRET-77 caf" _ eg _ "|g/L|||||F" _ cr _ "NTE|1||COMMENT-SECRET-55"
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    Set msg.DocType = "2.5.1:ORU_R01"
    Set reply = ##class(Shutter.Util.ReplyWords).FromLog("MSA|AE|C77|Test code ZZUNK not recognised for VALUE-SECRET-77")
    Set findings = {"custody": {"words": (##class(Shutter.Util.CaseFindings).CustodyWords("reached_receiver", "settled"))}, "reply": (reply)}
    Set findings.obx = ##class(Shutter.Util.ObxFinding).Find(msg, ##class(Shutter.Util.CaseFindings).WordsToMatch(reply))
    Set findings.character = ##class(Shutter.Util.CharacterFinding).Of(msg, "latin1")
    Set lines = ##class(Shutter.Util.CaseFindings).DraftLines(findings)
    Do $$$AssertTrue(lines [ "set id OBX-1 = 2, code 'ZZUNK'", "the OBX named by set id and code: " _ lines)
    Do $$$AssertTrue(lines [ "OBX-5 holds e with a grave accent, U+00E8", "the field and the character")
    For secret = "VALUE-SECRET-77", "RESULT-SECRET-41", "COMMENT-SECRET-55", "mmol/L", "g/L", "caf", "Testpatient", "not recognised" {
        Do $$$AssertNotTrue(lines [ secret, "no result content in the draft: " _ secret)
    }
}

/// A structure finding says so without quoting the validator's words.
Method TestSchemaLine()
{
    Set lines = ##class(Shutter.Util.CaseFindings).DraftLines({"custody": {}, "reply": {"msa1": "", "errors": []}, "obx": {"kind": "schema", "sentence": "x"}, "character": {}})
    Do $$$AssertTrue(lines [ "does not fit its structure", lines)
}

}
