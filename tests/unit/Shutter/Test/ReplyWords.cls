/// Shutter.Util.ReplyWords: a receiver's words read by field, from the engine's log row (the flat text) and from a saved
/// reply. The rows copy the shape the engine wrote on 2026.2 and 2027.1.0AI; every receiver wording is made up.
Class Shutter.Test.ReplyWords Extends %UnitTest.TestCase
{

/// The engine's text before a reply's words, as the measured rows carry it.
Parameter BOILER = "ERROR <Ens>ErrGeneral: Suspending HL7 Message body 812@EnsLib.HL7.Message / 77 because response 913@EnsLib.HL7.Message MSA code 'AE' matched ReplyCodeActions 1-6 : ':?R=RF,:?E=S,:~=S,:?A=C,:*=S,:I?=W', resulting in Action code S : MSH|^~\&|FAKELIMS|TESTLAB ONE|FAKESEND|NORTHFIELD TEST SITE|20261105100001||ACK^O01|A1|P|2.5.1 ";

/// Style a: the words in MSA-3 only.
Method TestStyleA()
{
    Set w = ##class(Shutter.Util.ReplyWords).FromLog(..#BOILER _ "MSA|AE|T-M-K3-AE-a|Patient not found")
    Do $$$AssertEquals(w.source, "log", "from the log row")
    Do $$$AssertEquals(w.msa1 _ "/" _ w.msa2, "AE/T-M-K3-AE-a", "MSA-1 and MSA-2")
    Do $$$AssertEquals(w.msa3, "Patient not found", "MSA-3")
    Do $$$AssertEquals(w.errors.%Size(), 0, "no ERR")
    Do $$$AssertEquals(w.kind, "words", "words")
    Do $$$AssertEquals(w.quote, "MSA-3: Patient not found", "quoted by field")
}

/// Style b: MSA-3 empty, the words in ERR only (an empty MSA-3 leaves "| ERR||").
Method TestStyleB()
{
    Set w = ##class(Shutter.Util.ReplyWords).FromLog(..#BOILER _ "MSA|AE|T-M-K1-AE-b| ERR||OBR^1^4|103^Table value not found^HL70357|E|||Test code FBX not in test catalogue|Unknown test code")
    Do $$$AssertEquals(w.msa3, "", "MSA-3 empty")
    Do $$$AssertEquals(w.errors.%Size(), 1, "one ERR")
    Set e = w.errors.%Get(0)
    Do $$$AssertEquals(e.location, "OBR^1^4", "ERR-2")
    Do $$$AssertEquals(e.code _ "/" _ e."code_text" _ "/" _ e.table, "103/Table value not found/HL70357", "ERR-3")
    Do $$$AssertEquals(e.diagnostic, "Test code FBX not in test catalogue", "ERR-7")
    Do $$$AssertEquals(e."user_message", "Unknown test code", "ERR-8")
    Do $$$AssertEquals(w.kind, "words", "words in ERR")
    Do $$$AssertEquals(w.quote, "ERR-7: Test code FBX not in test catalogue; ERR-8: Unknown test code; code 103 (Table value not found); at OBR^1^4", "quoted by field")
}

/// Style c: both, with an AR; and the type 6 copy's alert suffix left out.
Method TestStyleC()
{
    Set row = ..#BOILER _ "MSA|AR|T-M-K3-AR-c|Patient not found ERR||PID^1^3|204^Unknown key identifier^HL70357|E|||No patient with identifier MRN-FAKE-1|Patient not found (alert request ID=4411)"
    Set w = ##class(Shutter.Util.ReplyWords).FromLog(row)
    Do $$$AssertEquals(w.msa1, "AR", "AR")
    Do $$$AssertEquals(w.msa3, "Patient not found", "MSA-3, not running into ERR")
    Do $$$AssertEquals(w.errors.%Get(0)."user_message", "Patient not found", "ERR-8 without the alert suffix")
    Do $$$AssertNotTrue(w.quote [ "alert request", "the engine's suffix is not the receiver's")
}

/// Style d: the older ERR, a location and a code with no words.
Method TestStyleD()
{
    Set w = ##class(Shutter.Util.ReplyWords).FromLog(..#BOILER _ "MSA|AE|T-M-K3-AE-d| ERR|PID^1^3^101")
    Do $$$AssertEquals(w.errors.%Get(0).location, "PID^1^3", "the location from ERR-1")
    Do $$$AssertEquals(w.errors.%Get(0).code, "101", "the code from ERR-1's fourth component")
    Do $$$AssertEquals(w.kind, "code_only", "a location and a code, no words")
    Do $$$AssertEquals(w.quote, "code 101; at PID^1^3", "quoted as they are")
    Set w = ##class(Shutter.Util.ReplyWords).FromLog(..#BOILER _ "MSA|AE|T-M-K3-AE-d|Patient not found ERR|PID^1^3^101")
    Do $$$AssertEquals(w.kind, "words", "with MSA-3 beside it, words")
    Set w = ##class(Shutter.Util.ReplyWords).FromLog(..#BOILER _ "MSA|AE|T-1")
    Do $$$AssertEquals(w.kind, "no_words", "an MSA with only its code")
}

/// No MSA at all: unknown words, the end of the text quoted, nothing named; and an empty row.
Method TestUnknownWords()
{
    Set w = ##class(Shutter.Util.ReplyWords).FromLog("ERROR <Ens>ErrGeneral: the receiver closed the connection with REJECTED BY GATEWAY")
    Do $$$AssertEquals(w.kind, "unknown", "no MSA")
    Do $$$AssertEquals(w.msa1, "", "nothing named")
    Do $$$AssertTrue(w.quote [ "REJECTED BY GATEWAY", "the text quoted")
    Set w = ##class(Shutter.Util.ReplyWords).FromLog("")
    Do $$$AssertEquals(w.source _ "/" _ w.kind, "none/unknown", "nothing to read")
}

/// A row longer than 160 characters keeps its words; a quote is cut at 300 characters.
Method TestLengths()
{
    Set long = ..#BOILER _ "MSA|AE|T-2|Patient not found"
    Do $$$AssertTrue($LENGTH(long) > 160, "longer than a 160-character consumer keeps")
    Do $$$AssertEquals(##class(Shutter.Util.ReplyWords).FromLog(long).msa3, "Patient not found", "the words are at the end and still read")
    Set w = ##class(Shutter.Util.ReplyWords).FromLog(..#BOILER _ "MSA|AE|T-3|" _ $TRANSLATE($JUSTIFY("", 400), " ", "x"))
    Do $$$AssertEquals($LENGTH(w.quote), 300, "cut at 300")
    Set w = ##class(Shutter.Util.ReplyWords).FromLog($TRANSLATE($JUSTIFY("", 500), " ", "y") _ " no reply here")
    Do $$$AssertEquals($LENGTH(w.quote), 300, "unknown words cut at 300 too")
    Do $$$AssertTrue(w.quote [ "no reply here", "from the end, where the words stand")
}

/// The saved reply's id is read off the row; a reply that can't be opened falls back to the flat read.
Method TestReplyIdAndFallback()
{
    Do $$$AssertEquals(##class(Shutter.Util.ReplyWords).ReplyId(..#BOILER), "913", "because response 913@EnsLib.HL7.Message")
    Set w = ##class(Shutter.Util.ReplyWords).Read(..#BOILER _ "MSA|AE|T-4|Patient not found", "999999999")
    Do $$$AssertEquals(w.source, "log", "an id that does not open: the flat read")
    Do $$$AssertEquals(w.msa3, "Patient not found", "its words")
}

/// A saved reply read by its own segments, two ERR included.
Method TestFromReply()
{
    Set cr = $CHAR(13)
    Set text = "MSH|^~\&|FAKELIMS|TESTLAB ONE|FAKESEND|SITE|20261105100001||ACK^R01|A2|P|2.5.1" _ cr _ "MSA|AE|T-M-K4-AE-c|Patient demographics do not match" _ cr _ "ERR||PID^1^5|207^Application internal error^HL70357|E|||Surname and date of birth do not match the record for the identifier" _ cr _ "ERR||PID^1^7|207^Application internal error^HL70357|W"
    Set reply = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    Set w = ##class(Shutter.Util.ReplyWords).FromReply(reply)
    Do $$$AssertEquals(w.source, "reply", "from the saved reply")
    Do $$$AssertEquals(w.msa3, "Patient demographics do not match", "MSA-3")
    Do $$$AssertEquals(w.errors.%Size(), 2, "both ERR")
    Do $$$AssertEquals(w.errors.%Get(1).location, "PID^1^7", "the second's location")
    Do $$$AssertEquals(w.errors.%Get(0).diagnostic, "Surname and date of birth do not match the record for the identifier", "ERR-7")
}

/// Codes holds no free text: no MSA-3, no ERR-7 or ERR-8, no code text.
Method TestCodesHoldNoText()
{
    Set w = ##class(Shutter.Util.ReplyWords).FromLog(..#BOILER _ "MSA|AR|T-M-K3-AR-c|Patient not found ERR||PID^1^3|204^Unknown key identifier^HL70357|E|||No patient with identifier MRN-FAKE-1|Patient not found")
    Set c = ##class(Shutter.Util.ReplyWords).Codes(w).%ToJSON()
    Do $$$AssertEquals(c, "{""msa1"":""AR"",""msa2"":""T-M-K3-AR-c"",""errors"":[{""code"":""204"",""table"":""HL70357""}]}", "codes only: " _ c)
    For text = "Patient", "MRN-FAKE-1", "Unknown key" { Do $$$AssertNotTrue(c [ text, "no " _ text) }
}

}
