/// Shutter.Util.ObxFinding: the OBX a receiver's words name, by segment scan, never the first by default. Every test code,
/// patient and value here is made up; the values carry no meaning and are never read.
Class Shutter.Test.ObxFinding Extends %UnitTest.TestCase
{

/// The words a receiver that refuses an unknown code sends, as the rig's fake receiver words them.
Parameter WORDS = "Test code not recognised: ";

/// Two panels: the words name the 4th OBX in one and the 2nd in the other, never the first.
Method TestNamesTheRightObx()
{
    Set f = ##class(Shutter.Util.ObxFinding).Find(..Panel(6, 4, "2.5.1:ORU_R01"), ..#WORDS _ "ZZUNK")
    Do $$$AssertEquals(f.kind, "obx", "a code named in a panel of six")
    Do $$$AssertEquals(f."obx_count", 6, "six OBX scanned")
    Do $$$AssertEquals(f.matches.%Size(), 1, "one OBX named")
    Do $$$AssertEquals(f.matches.%Get(0).position, 4, "the 4th")
    Do $$$AssertEquals(f.matches.%Get(0)."set_id", "4", "set id 4")
    Do $$$AssertEquals(f.matches.%Get(0).code, "ZZUNK", "the code")
    Do $$$AssertEquals(f.sentence, "The receiver's words name the 4th OBX of 6, set id OBX-1 = 4, code 'ZZUNK'.", "in words")
    Set f = ##class(Shutter.Util.ObxFinding).Find(..Panel(3, 2, "2.5.1:ORU_R01"), ..#WORDS _ "ZZUNK")
    Do $$$AssertEquals(f.matches.%Get(0).position _ "/" _ f.matches.%Get(0)."set_id", "2/2", "the 2nd of three")
}

/// On a stock 2.5.1 ORU, OBX(*) with no group path counts 0; the scan by segment name still finds every OBX.
Method TestScanNotGroupPath()
{
    Set msg = ..Panel(5, 5, "2.5.1:ORU_R01")
    Do $$$AssertEquals(msg.GetValueAt("OBX(*)"), 0, "OBX(*) with no group path counts 0 (the trap)")
    Set f = ##class(Shutter.Util.ObxFinding).Find(msg, ..#WORDS _ "ZZUNK")
    Do $$$AssertEquals(f."obx_count", 5, "the scan counts five")
    Do $$$AssertEquals(f.matches.%Get(0).position, 5, "the last of five")
}

/// A message with no DocType (a site's own schema reads flat paths) is scanned the same way.
Method TestNoDocType()
{
    Set f = ##class(Shutter.Util.ObxFinding).Find(..Panel(8, 1, ""), ..#WORDS _ "ZZUNK")
    Do $$$AssertEquals(f.kind, "obx", "found with no DocType")
    Do $$$AssertEquals(f.schema, "", "no structure to check against")
    Do $$$AssertEquals(f.matches.%Get(0).position, 1, "the first, when the first is the one named")
}

/// 80 OBX: every one is scanned, past the evidence's cap of 50.
Method TestEightyObx()
{
    Set f = ##class(Shutter.Util.ObxFinding).Find(..Panel(80, 80, "2.5.1:ORU_R01"), ..#WORDS _ "ZZUNK")
    Do $$$AssertEquals(f."obx_count", 80, "eighty scanned")
    Do $$$AssertEquals(f.matches.%Get(0).position _ "/" _ f.matches.%Get(0)."set_id", "80/80", "the 80th named")
    Do $$$AssertEquals(f.sentence, "The receiver's words name the 80th OBX of 80, set id OBX-1 = 80, code 'ZZUNK'.", "80th in words")
}

/// Words that name no code in the message, and words with nothing in them.
Method TestNoMatch()
{
    Set f = ##class(Shutter.Util.ObxFinding).Find(..Panel(4, 0, "2.5.1:ORU_R01"), ..#WORDS _ "ZZUNK")
    Do $$$AssertEquals(f.kind, "no_match", "no OBX carries the code")
    Do $$$AssertEquals(f.matches.%Size(), 0, "nothing named")
    Do $$$AssertEquals(f.sentence, "No OBX matches the receiver's words: none of the 4 test codes appears in them.", "in words")
    Set f = ##class(Shutter.Util.ObxFinding).Find(..Panel(4, 2, "2.5.1:ORU_R01"), "")
    Do $$$AssertEquals(f.kind, "no_words", "no words")
    Set f = ##class(Shutter.Util.ObxFinding).Find(..Message("MSH|^~\&|FAKESEND|SITE|FAKELIMS|LAB|20261105100000||ADT^A01|C1|P|2.5.1" _ $CHAR(13) _ "PID|1||9990000014^^^NHS^NH", "2.5.1:ADT_A01"), ..#WORDS _ "ZZUNK")
    Do $$$AssertEquals(f.kind, "no_obx", "a message with no OBX")
    Set f = ##class(Shutter.Util.ObxFinding).Find("", "x")
    Do $$$AssertEquals(f.kind, "unreadable", "no message")
}

/// A code is matched as a whole: K is not inside OK, GLU is not inside GLUC, and two named codes are both listed.
Method TestLiteralBoundaries()
{
    Do $$$AssertNotTrue(##class(Shutter.Util.ObxFinding).Names("Result OK", "K"), "K inside OK")
    Do $$$AssertNotTrue(##class(Shutter.Util.ObxFinding).Names("unknown code GLUC", "GLU"), "GLU inside GLUC")
    Do $$$AssertTrue(##class(Shutter.Util.ObxFinding).Names("unknown code GLU.", "GLU"), "GLU before a full stop")
    Do $$$AssertTrue(##class(Shutter.Util.ObxFinding).Names("GLUC GLU", "GLU"), "the second occurrence")
    Do $$$AssertNotTrue(##class(Shutter.Util.ObxFinding).Names("unknown code zzunk", "ZZUNK"), "literal: case and all")
    Set f = ##class(Shutter.Util.ObxFinding).Find(..Panel(5, 2, "2.5.1:ORU_R01", 4), ..#WORDS _ "ZZUNK, ZZUNK2")
    Do $$$AssertEquals(f.matches.%Size(), 2, "both named codes listed")
    Do $$$AssertEquals(f.sentence, "The receiver's words name the 2nd OBX of 5, set id OBX-1 = 2, code 'ZZUNK' and the 4th OBX of 5, set id OBX-1 = 4, code 'ZZUNK2'.", "two in words")
}

/// An OBX before its OBR fits no structure: the finding is Validate("dm")'s words, quoted.
Method TestObxBeforeObr()
{
    Set cr = $CHAR(13)
    Set text = "MSH|^~\&|FAKESEND|SITE|FAKELIMS|LAB|20261105100000||ORU^R01|C2|P|2.5.1" _ cr _ "PID|1||9990000014^^^NHS^NH||Testpatient^Alpha" _ cr _ "ORC|RE|ORD1|FIL1" _ cr _ "OBX|1|ST|ZZUNK^Made-up^MADELAB||10|||||F" _ cr _ "OBR|1|ORD1|FIL1|PANEL1^Made-up panel^MADELAB"
    Set f = ##class(Shutter.Util.ObxFinding).Find(..Message(text, "2.5.1:ORU_R01"), ..#WORDS _ "ZZUNK")
    Do $$$AssertEquals(f.kind, "schema", "does not fit its structure")
    Do $$$AssertTrue(f.schema [ "OBX", "Validate's words quoted: " _ f.schema)
    Do $$$AssertTrue(f.sentence [ "does not fit its structure", "in words")
    Do $$$AssertEquals(f.matches.%Size(), 1, "the OBX is still named beside it")
    Do $$$AssertNotTrue(f.%ToJSON() [ "|10|", "no value is read")
}

/// No result value reaches the finding: the values are distinctive, and none appears in it.
Method TestNoValueRead()
{
    Set f = ##class(Shutter.Util.ObxFinding).Find(..Panel(6, 4, "2.5.1:ORU_R01"), ..#WORDS _ "ZZUNK")
    For v = 10, 20, 30, 40, 50, 60 { Do $$$AssertNotTrue(f.%ToJSON() [ ("VAL" _ v), "value VAL" _ v _ " not in the finding") }
}

/// An ORU of <var>n</var> OBX with set ids 1 to n; OBX <var>unknown</var> carries ZZUNK (0 for none), and OBX
/// <var>second</var> ZZUNK2.
ClassMethod Panel(n As %Integer, unknown As %Integer, docType As %String, second As %Integer = 0) As EnsLib.HL7.Message
{
    Set cr = $CHAR(13)
    Set text = "MSH|^~\&|FAKESEND|NORTHFIELD TEST SITE|FAKELIMS|TESTLAB ONE|20261105100000||ORU^R01|C0364|P|2.5.1" _ cr _ "PID|1||9990000014^^^NHS^NH||Testpatient^Alpha||19800101|U" _ cr _ "ORC|RE|ORD014|FIL014" _ cr _ "OBR|1|ORD014|FIL014|PANEL1^Made-up panel^MADELAB"
    For i = 1:1:n {
        Set code = $SELECT(i = unknown: "ZZUNK", i = second: "ZZUNK2", 1: "TST" _ $JUSTIFY(i, 2))
        Set code = $TRANSLATE(code, " ", "0")
        Set text = text _ cr _ "OBX|" _ i _ "|ST|" _ code _ "^Made-up test^MADELAB||VAL" _ (i * 10) _ "|||||F"
    }
    Quit ..Message(text, docType)
}

ClassMethod Message(text As %String, docType As %String) As EnsLib.HL7.Message
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    Set:docType'="" msg.DocType = docType
    Quit msg
}

}
