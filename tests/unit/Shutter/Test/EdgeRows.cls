/// Rows of docs/edge-cases.md proved without a production: what a repeated or corrected message does to the operation key
/// and to the case (<method>Open</method> of <class>Shutter.Store.Case</class>), what structural validation says of a
/// message with a raw line break or a second PID, and that the operation a case writes is built from the case's own
/// fields. tests/e2e/edge_rows_check.py plays the same rows through the production. Cases are removed after each test, and
/// the public case counter is put back.
Class Shutter.Test.EdgeRows Extends %UnitTest.TestCase
{

Parameter KEYBASE = "PAS^HOSP^MRN-UT-EDGE^ENC-UT-EDGE^transfer^";

Property Counter As %String;

Property Opened As %String [ MultiDimensional ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set ..Counter = $GET(^Shutter.Counter("case"))
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE PatientId %STARTSWITH 'MRN-UT-EDGE'")
    While rs.%Next() { Do ##class(Shutter.Store.Case).PurgeCase(rs.%Get("ID")) }
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE PatientId %STARTSWITH 'MRN-UT-EDGE'")
    While rs.%Next() { Do ##class(Shutter.Store.Case).PurgeCase(rs.%Get("ID")) }
    Set ^Shutter.Counter("case") = ..Counter
    Quit $$$OK
}

/// An A02's text. evn2 and evn6 are the message's recorded and event times; extra is raw text after PV1, and pid2 a
/// second PID segment right after the first.
Method A02(control As %String, ward As %String = "WARD-B", evn2 As %String = "20261015092000", evn6 As %String = "20261015092000", patient As %String = "MRN-UT-EDGE", bed As %String = "04", extra As %String = "", pid2 As %String = "") As %String
{
    Set cr = $CHAR(13)
    Set msh = "MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|" _ evn2 _ "||ADT^A02^ADT_A02|" _ control _ "|P|2.5.1"
    Set evn = "EVN|A02|" _ evn2 _ "||||" _ evn6
    Set pid = "PID|1||" _ patient _ "^^^HOSP^MR||SYNTH^EDGE||19800101|F"
    Set pv1 = "PV1|1|I|" _ ward _ "^BAY2^" _ bed _ "^HOSP|||WARD-A^BAY1^01^HOSP|||||||||||||ENC-UT-EDGE"
    Quit msh _ cr _ evn _ cr _ pid _ cr _ $SELECT(pid2 '= "": pid2 _ cr, 1: "") _ pv1 _ cr _ extra
}

Method Parsed(text As %String) As EnsLib.HL7.Message
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    Do $$$AssertStatusOK(sc, "the text parses into segments")
    Do msg.PokeDocType(##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType("2.5.1", msg.Name))
    Quit msg
}

Method Op(text As %String) As %DynamicObject
{
    Set op = ##class(Shutter.Util.OperationKey).FromHL7(..Parsed(text), .sc)
    Do $$$AssertStatusOK(sc, "the message maps to an operation")
    Quit op
}

Method Open(op As %DynamicObject, Output opened As %Boolean) As Shutter.Store.Case
{
    Set sc = ##class(Shutter.Store.Case).Open(op, "delivery_failed", "Delivery unavailable (test)", "", "", "rules", .case, .opened, "Downstream Out")
    Do $$$AssertStatusOK(sc, "the case opens or takes the failure")
    Quit case
}

/// The sender repeats the same move under a new control id: the same event time gives the same key and digest.
Method TestNewControlIdKeepsTheOperation()
{
    Set first = ..Op(..A02("EDGE1")), again = ..Op(..A02("EDGE2"))
    Do $$$AssertEquals(again."operation_key", first."operation_key", "a new control id: the same operation key")
    Do $$$AssertEquals(again."payload_digest", first."payload_digest", "and the same payload digest")
    Set blank = ..Op(..A02(""))
    Do $$$AssertEquals(blank."operation_key", first."operation_key", "a blank control id: the same key too")
}

/// The sender stamps the move again: EVN-6 still decides when it is there, and with none a new EVN-2 is a new key.
Method TestNewRecordedTime()
{
    Set first = ..Op(..A02("EDGE1"))
    Set stamped = ..Op(..A02("EDGE2", , "20261015094000"))
    Do $$$AssertEquals(stamped."operation_key", first."operation_key", "EVN-6 unchanged and a new EVN-2: the same key")
    Set bare = ..Op(..A02("EDGE1", , "20261015092000", ""))
    Set bareAgain = ..Op(..A02("EDGE2", , "20261015094000", ""))
    Do $$$AssertNotEquals(bareAgain."operation_key", bare."operation_key", "no EVN-6 and a new EVN-2: a new key, a later event")
}

/// A repeated control id across patients merges nothing: the key doesn't use it.
Method TestSameControlIdTwoPatients()
{
    Set a = ..Op(..A02("FIXED")), b = ..Op(..A02("FIXED", , , , "MRN-UT-EDGE2"))
    Do $$$AssertNotEquals(b."operation_key", a."operation_key", "a fixed control id on two patients: two keys")
    Set one = ..Open(a, .openedOne), two = ..Open(b, .openedTwo)
    Do $$$AssertTrue(openedOne && openedTwo, "two cases open")
    Do $$$AssertNotEquals(two.CaseId, one.CaseId, "and they are not the same case")
}

/// Same id or a new id, same content: a further failure noted on the one open case.
Method TestSameContentIsNotedOnTheOpenCase()
{
    Set first = ..Open(..Op(..A02("EDGE1")), .opened)
    Do $$$AssertTrue(opened, "the first failure opens a case")
    Set state = first.State
    For control = "EDGE1", "EDGE2", "" {
        Set again = ..Open(..Op(..A02(control)), .opened)
        Do $$$AssertNotTrue(opened, "control id '" _ control _ "': no second case")
        Do $$$AssertEquals(again.CaseId, first.CaseId, "the open case takes it")
        Do $$$AssertEquals(again.State, state, "and its state stands")
    }
}

/// Same key, other content, whichever the id: the plan would write the first content, so the case blocks.
Method TestOtherContentBlocks()
{
    For control = "EDGE1", "EDGE2" {
        Set first = ..Open(..Op(..A02("EDGE1")), .opened)
        Do $$$AssertTrue(opened, "the first failure opens a case")
        Set again = ..Open(..Op(..A02(control, "WARD-C")), .opened)
        Do $$$AssertNotTrue(opened, "no second case")
        Do $$$AssertEquals(again.CaseId, first.CaseId, "the same case")
        Do $$$AssertEquals(again.State, "blocked", "blocked, control id " _ control)
        Set reason = ""
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? ORDER BY ID DESC", again.%Id())
        If rs.%Next() Set reason = rs.%Get("Text")
        Do $$$AssertTrue(reason [ "PAYLOAD_CHANGED", "the case says why: " _ reason)
        Do ##class(Shutter.Store.Case).PurgeCase(again.%Id())
    }
}

/// What the row says isn't covered, held to it: a bed-only correction isn't noticed, and after a block a correction opens
/// a new case with no link to the first.
Method TestStatedLimits()
{
    Set first = ..Open(..Op(..A02("EDGE1")), .opened)
    Set bedOnly = ..Open(..Op(..A02("EDGE2", , , , , "09")), .opened)
    Do $$$AssertNotEquals(bedOnly.State, "blocked", "the digest leaves the bed out, so a bed-only correction doesn't block")
    Do $$$AssertEquals(bedOnly.Bed, first.Bed, "and the first bed stays on the case")
    Do ..Open(..Op(..A02("EDGE3", "WARD-C")), .opened)
    Set after = ..Open(..Op(..A02("EDGE4", "WARD-D")), .opened)
    Do $$$AssertTrue(opened, "once blocked, the next correction opens its own case")
    Do $$$AssertNotEquals(after.CaseId, first.CaseId, "not the first one")
}

/// The operation a case writes doesn't read the message or today's mapping: the source's text can map to another ward, and
/// the case's operation stands, with the digest its plan bound.
Method TestOperationComesFromTheCase()
{
    Set op = ..Op(..A02("EDGE1"))
    Set case = ..Open(op, .opened)
    Set remapped = ..Op(..A02("EDGE1", "WARD-Z"))
    Do $$$AssertNotEquals(remapped."payload_digest", op."payload_digest", "another mapping of the source gives another digest")
    Set written = ##class(Shutter.Test.EvidenceProbe).%New("edge rows").OperationFor(case)
    Do $$$AssertEquals(written.ward, "WARD-B", "the case still writes the ward it opened with")
    Do $$$AssertEquals(written."payload_digest", op."payload_digest", "under the digest it opened with")
    Do $$$AssertEquals(written."operation_key", op."operation_key", "and the same key")
}

/// A control: the message below passes the same validation with its note on one line, so the failures below are the break's
/// and the second PID's own.
Method TestSoundMessageValidates()
{
    Set note = "OBX|1|TX|NOTE^Transfer note^L||Moved to bay 3 after review||||||F" _ $CHAR(13)
    Do $$$AssertStatusOK(..Parsed(..A02("EDGE1", , , , , , note)).Validate("dm"), "a sound A02 with a note validates")
}

/// A raw CR inside a note turns the rest of the line into a false segment: validation refuses it, and nothing rejoins it.
Method TestRawLineBreakInANoteFails()
{
    Set note = "OBX|1|TX|NOTE^Transfer note^L||Moved to bay 3" _ $CHAR(13) _ "after review||||||F" _ $CHAR(13)
    Do $$$AssertStatusNotOK(..Parsed(..A02("EDGE1", , , , , , note)).Validate("dm"), "the false segment fails validation")
}

/// A second PID in a transfer's structure.
Method TestSecondPidFails()
{
    Set pid2 = "PID|1||MRN-UT-OTHER^^^HOSP^MR||SYNTH^OTHER||19810101|M"
    Do $$$AssertStatusNotOK(..Parsed(..A02("EDGE1", , , , , , , pid2)).Validate("dm"), "a second PID fails validation")
}

}
