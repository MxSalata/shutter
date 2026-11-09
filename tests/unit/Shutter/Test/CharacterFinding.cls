/// Shutter.Util.CharacterFinding against U4's tables (measured on 2026.2 and 2027.1.0AI): the stored code points, the
/// wire bytes per setting and MSH-18, the "?" in an identity field, and the words. Every name and value is made up.
Class Shutter.Test.CharacterFinding Extends %UnitTest.TestCase
{

/// U4's wire table, one assertion per cell: stored 232 or 195 168, MSH-18 empty, UTF-8 or 8859/1, and the four settings.
Method TestWireTable()
{
    Set eg = $CHAR(232), mangled = $CHAR(195, 168)
    // stored | MSH-18 | default latin1 | UTF-8 | !UTF-8 | !latin1
    Set rows = $LISTBUILD(
        $LISTBUILD(eg, "", "E8", "C3 A8", "C3 A8", "E8"),
        $LISTBUILD(eg, "UNICODE UTF-8", "C3 A8", "C3 A8", "C3 A8", "E8"),
        $LISTBUILD(eg, "8859/1", "E8", "E8", "C3 A8", "E8"),
        $LISTBUILD(mangled, "", "C3 A8", "C3 83 C2 A8", "C3 83 C2 A8", "C3 A8"),
        $LISTBUILD(mangled, "UTF-8", "C3 83 C2 A8", "C3 83 C2 A8", "C3 83 C2 A8", "C3 A8"),
        $LISTBUILD(mangled, "8859/1", "C3 A8", "C3 A8", "C3 83 C2 A8", "C3 A8"))
    Set settings = $LISTBUILD("latin1", "UTF-8", "!UTF-8", "!latin1")
    For r = 1:1:$LISTLENGTH(rows) {
        Set row = $LIST(rows, r)
        For s = 1:1:4 {
            Set got = ##class(Shutter.Util.CharacterFinding).Wire($LIST(row, 1), $LIST(settings, s), $LIST(row, 2))
            Do $$$AssertEquals(got, $LIST(row, 2 + s), "row " _ r _ " (MSH-18 '" _ $LIST(row, 2) _ "'), " _ $LIST(settings, s) _ ": " _ got)
        }
    }
}

/// A setting or MSH-18 that was not measured gets no bytes; a setting that could not be read says so.
Method TestNotKnown()
{
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Wire($CHAR(232), "UTF-16", ""), "not known for this setting", "a fifth setting")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Wire($CHAR(232), "NOSUCH", ""), "not known for this setting", "an unknown name")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Wire($CHAR(232), "latin1", "8859/15"), "not known for this setting", "an MSH-18 not measured")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Wire($CHAR(232), "!latin1", "8859/15"), "E8", "a ! setting wins over any MSH-18")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Wire($CHAR(8364), "latin1", ""), "not known for this setting", "a character Latin-1 has no byte for")
    Do $$$AssertTrue(##class(Shutter.Util.CharacterFinding).Wire($CHAR(232), "", "") [ "could not be read", "the setting unread")
}

/// Every field holding the character is named, by segment, field, component and position, with the stored codes.
Method TestNamesEveryField()
{
    Set f = ##class(Shutter.Util.CharacterFinding).Of(..Result($CHAR(232), ""), "latin1")
    Do $$$AssertEquals(f.kind, "characters", "characters found")
    Set names = ""
    Set iter = f.fields.%GetIterator()
    While iter.%GetNext(, .one) { Set names = names _ $SELECT(names = "": "", 1: ",") _ one.field }
    Do $$$AssertEquals(names, "PID-5,ORC-12,OBX-5,NTE-3", "PID-5, ORC-12, OBX-5 and NTE-3 named")
    Set pid = f.fields.%Get(0)
    Do $$$AssertEquals(pid.component _ "/" _ pid.position, "1/5", "PID-5's first component, position 5 (Testèpatient)")
    Do $$$AssertEquals(pid.codes.%ToJSON(), "[232]", "stored as 232")
    Do $$$AssertEquals(pid.character, "e with a grave accent, U+00E8", "in words")
    Do $$$AssertEquals(pid.wire, "E8", "the default sends E8")
    Do $$$AssertEquals(f.msh18, "", "MSH-18 empty")
    Do $$$AssertNotTrue(f.%ToJSON() [ "Testpatient", "no value around the character")
    Do $$$AssertNotTrue(f.%ToJSON() [ "VAL", "no result value")
}

/// UTF-8 bytes stored as two characters are said to be so.
Method TestStoredAsTwo()
{
    Set f = ##class(Shutter.Util.CharacterFinding).Of(..Result($CHAR(195, 168), ""), "latin1")
    Set pid = f.fields.%Get(0)
    Do $$$AssertEquals(pid.codes.%ToJSON(), "[195,168]", "stored as 195 168")
    Do $$$AssertEquals(pid.character, "stored as 2 characters (195 168), the UTF-8 bytes of e with a grave accent, U+00E8", "in words")
    Do $$$AssertEquals(pid.wire, "C3 A8", "the default sends them back as C3 A8")
    // An operation set to UTF-8 with MSH-18 empty double-encodes them (U4's row 195 168, empty). A message whose MSH-18 says
    // UTF-8 is decoded on import, so it would not store 195 168 at all.
    Set f = ##class(Shutter.Util.CharacterFinding).Of(..Result($CHAR(195, 168), ""), "UTF-8")
    Do $$$AssertEquals(f.fields.%Get(0).wire, "C3 83 C2 A8", "UTF-8 double-encodes them")
}

/// A "?" in PID-3 is a question; in NTE-3 it is not raised.
Method TestQuestionMark()
{
    Set cr = $CHAR(13)
    Set text = "MSH|^~\&|FAKESEND|SITE|FAKELIMS|LAB|20261105100000||ORU^R01|C9|P|2.5.1" _ cr _ "PID|1||99900?0014^^^NHS^NH||Testpatient^Alpha" _ cr _ "OBR|1|ORD1|FIL1|PANEL1" _ cr _ "OBX|1|ST|TST01||VAL10|||||F" _ cr _ "NTE|1||Is this right?"
    Set f = ##class(Shutter.Util.CharacterFinding).Of(##class(EnsLib.HL7.Message).ImportFromString(text, .sc), "latin1")
    Do $$$AssertEquals(f.kind, "question", "only a question")
    Do $$$AssertEquals(f.questions.%Size(), 1, "one: PID-3, not NTE-3")
    Do $$$AssertEquals(f.questions.%Get(0).field _ "/" _ f.questions.%Get(0).position, "PID-3/6", "PID-3 at position 6")
    Do $$$AssertTrue(f.questions.%Get(0).words [ "may be a lost character", "worded as a question")
}

/// The count in words, and "not compared with what got through" when the delivered read failed.
Method TestCountWords()
{
    Set f = ##class(Shutter.Util.CharacterFinding).Of(..Result($CHAR(232), ""), "latin1")
    Do f.count.%Set("PID-5", {"failures": 4, "of_failures": 6, "delivered": 11, "of_delivered": 300})
    Set s = ##class(Shutter.Util.CharacterFinding).Sentence(f)
    Do $$$AssertTrue(s [ "4 of the last 6 failures to this receiver in 7 days carry a character above ASCII in PID-5; 11 of the last 300 delivered do.", s)
    Do f.count.%Set("PID-5", {"failures": 4, "of_failures": 6, "delivered": "", "of_delivered": "", "why_delivered": "SQL"})
    Set s = ##class(Shutter.Util.CharacterFinding).Sentence(f)
    Do $$$AssertTrue(s [ "not compared with what got through", s)
    Do $$$AssertTrue(s [ "Stored MSH-18: empty; the operation's DefCharEncoding: latin1.", "the settings beside it")
}

/// The shared count: a character stored as its UTF-8 bytes is the same character as one stored as itself, and the count of
/// failures holding it leads the sentence, before the counts per field.
Method TestSharedCharacter()
{
    Set one = ##class(Shutter.Util.CharacterFinding).Of(..Result($CHAR(232), ""), "latin1")
    Set two = ##class(Shutter.Util.CharacterFinding).Of(..Result($CHAR(195, 168), ""), "latin1")
    Set other = ##class(Shutter.Util.CharacterFinding).Of(..Result($CHAR(233), ""), "latin1")
    Do $$$AssertEquals($LISTTOSTRING(##class(Shutter.Util.CharacterFinding).Characters(one.fields)), "232", "e grave once, though four fields hold it")
    Do $$$AssertEquals($LISTTOSTRING(##class(Shutter.Util.CharacterFinding).Characters(two.fields)), "232", "its UTF-8 bytes are the same character")
    Do $$$AssertEquals($LISTTOSTRING(##class(Shutter.Util.CharacterFinding).Characters(other.fields)), "233", "e acute is another")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Characters([]), "", "no fields, no characters")
    Set odd = [{"codes": [200, 201, 202]}]
    Do $$$AssertEquals($LISTTOSTRING(##class(Shutter.Util.CharacterFinding).Characters(odd)), "200+201+202", "a run that is no one character, by its codes")
    Do one.count.%Set("PID-5", {"failures": 4, "of_failures": 7, "delivered": 0, "of_delivered": 2})
    Set one.shared = {"failures": 7, "of_failures": 7, "characters": "e with a grave accent, U+00E8"}
    Set s = ##class(Shutter.Util.CharacterFinding).Sentence(one)
    Do $$$AssertEquals($PIECE(s, ".", 1), "7 of the last 7 failures to this receiver in 7 days hold e with a grave accent, U+00E8, in any field", s)
    Do $$$AssertTrue(s [ "4 of the last 7 failures to this receiver in 7 days carry a character above ASCII in PID-5", "the field's count stays")
    Set one.shared = {"failures": "", "of_failures": "", "characters": "e with a grave accent, U+00E8", "why": "SQL"}
    Do $$$AssertTrue(##class(Shutter.Util.CharacterFinding).Sentence(one) [ "Its failures could not be compared for e with a grave accent", "an unread count says so")
}

/// The words for characters: Latin-1 letters by name, others by code point.
Method TestNames()
{
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Name(233), "e with an acute accent, U+00E9", "e acute")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Name(199), "C with a cedilla, U+00C7", "C cedilla")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Name(241), "n with a tilde, U+00F1", "n tilde")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Name(252), "u with a diaeresis, U+00FC", "u diaeresis")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Name(216), "O with a stroke, U+00D8", "O stroke")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Name(223), "sharp s, U+00DF", "sharp s")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Name(215), "U+00D7", "the multiplication sign by code point")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Name(8364), "U+20AC", "the euro sign by code point")
}

/// No characters and no question: none; no message: unreadable.
Method TestNone()
{
    Set f = ##class(Shutter.Util.CharacterFinding).Of(..Result("e", ""), "latin1")
    Do $$$AssertEquals(f.kind, "none", "plain ASCII")
    Do $$$AssertEquals(##class(Shutter.Util.CharacterFinding).Of("", "latin1").kind, "unreadable", "no message")
}

/// An ORU with <var>ch</var> in PID-5, ORC-12, OBX-5 and NTE-3, as the oracle's corpus files carry it.
ClassMethod Result(ch As %String, msh18 As %String) As EnsLib.HL7.Message
{
    Set cr = $CHAR(13)
    Set text = "MSH|^~\&|FAKESEND|NORTHFIELD TEST SITE|FAKELIMS|TESTLAB ONE|20261105100000||ORU^R01|C0401|P|2.5.1|||AL|NE||" _ msh18 _ cr _ "PID|1||9990000014^^^NHS^NH||Test" _ ch _ "patient^Alpha||19800101|U" _ cr _ "ORC|RE|ORD1|FIL1|||||||||Doct" _ ch _ "ur^Made" _ cr _ "OBR|1|ORD1|FIL1|PANEL1^Made-up panel^MADELAB" _ cr _ "OBX|1|ST|TST01^Made-up test 01^MADELAB||VAL" _ ch _ "10|||||F" _ cr _ "NTE|1||A not" _ ch _ " here"
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    Set msg.DocType = "2.5.1:ORU_R01"
    Quit msg
}

}
