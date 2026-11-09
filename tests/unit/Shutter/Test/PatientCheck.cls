/// Shutter.Util.PatientCheck and the ledger Shutter.Store.ResendRecord. The headers, bodies, cases and ledger rows are made
/// in this namespace under an item name of the test's own and removed after each test. Every patient is made up (NHS
/// numbers in the 999 range).
Class Shutter.Test.PatientCheck Extends %UnitTest.TestCase
{

Property Item As %String;

Property Headers As %String [ MultiDimensional ];

Property Bodies As %String [ MultiDimensional ];

Property Cases As %String [ MultiDimensional ];

Property Ledger As %String [ MultiDimensional ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set ..Item = "PatientCheck Test Out " _ $JOB _ "-" _ $INCREMENT(^||PatientCheckTest)
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Set id = "" For { Set id = $ORDER(..Headers(id)) Quit:id=""  Do ##class(Ens.MessageHeader).%DeleteId(id) }
    Set id = "" For { Set id = $ORDER(..Bodies(id)) Quit:id=""  Do ##class(EnsLib.HL7.Message).%DeleteId(id) }
    Set id = "" For { Set id = $ORDER(..Cases(id)) Quit:id=""  Do ##class(Shutter.Store.Case).%DeleteId(id) }
    Set id = "" For { Set id = $ORDER(..Ledger(id)) Quit:id=""  Do ##class(Shutter.Store.ResendRecord).%DeleteId(id) }
    Kill ..Headers, ..Bodies, ..Cases, ..Ledger
    Quit $$$OK
}

/// Every PID by name: an ORU with two patient groups gives both.
Method TestTwoPatients()
{
    Set p = ##class(Shutter.Util.PatientCheck).Patients(..Message(..ORU($LISTBUILD("9990000101^^^NHS^NH", "9990000102^^^NHS^NH"))))
    Do $$$AssertEquals(p.%Size(), 2, "two patients")
    Do $$$AssertEquals(p.%Get(1).keys.%Get(0).identifier, "9990000102", "the second patient's identifier")
}

/// Three PID-3 repetitions: each a key, the authority from PID-3.4.1, then PID-3.4.
Method TestRepetitions()
{
    Set p = ##class(Shutter.Util.PatientCheck).Patients(..Message(..ORU($LISTBUILD("MRN1^^^HOSP&1.2.3&ISO^MR~9990000103^^^NHS^NH~LAB7^^^LIMS^PI"))))
    Set keys = p.%Get(0).keys
    Do $$$AssertEquals(keys.%Size(), 3, "three keys")
    Do $$$AssertEquals(keys.%Get(0).authority, "HOSP", "PID-3.4.1 first")
    Do $$$AssertEquals(keys.%Get(1).identifier _ "/" _ keys.%Get(1).authority, "9990000103/NHS", "the second repetition")
    Do $$$AssertNotTrue(p.%Get(0).hold, "every key has an authority")
}

/// A blank authority holds that patient.
Method TestBlankAuthority()
{
    Set p = ##class(Shutter.Util.PatientCheck).Patients(..Message(..ORU($LISTBUILD("9990000104^^^NHS^NH~MRN9"))))
    Do $$$AssertTrue(p.%Get(0).hold, "held")
    Do $$$AssertTrue(p.%Get(0).why [ "no assigning authority", p.%Get(0).why)
}

/// A newer Completed header sharing a key is a hit naming it; an older one, another item's, or another patient's is not.
Method TestNewerCompleted()
{
    Set origin = ..Header(..ORU($LISTBUILD("9990000105^^^NHS^NH")), 8)
    Do ..Header(..ORU($LISTBUILD("9990000199^^^NHS^NH")), 9)
    Set hit = ..Header(..ORU($LISTBUILD("OTHER1^^^LIMS^PI~9990000105^^^NHS^NH"), "CTL-NEWER"), 9)
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, origin, "Results Out")
    Do $$$AssertTrue(r.hold, "held")
    Do $$$AssertEquals(r.patients.%Get(0).newer.header, hit, "the newer header named")
    Do $$$AssertTrue(r.why [ "identifier 9990000105 (NHS)", r.why)
    Do $$$AssertTrue(r.why [ "control id CTL-NEWER", "its control id")
    Set clear = ..Header(..ORU($LISTBUILD("9990000106^^^NHS^NH")), 8)
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, clear, "Results Out")
    Do $$$AssertNotTrue(r.hold, "nothing newer for this patient: " _ r.why)
}

/// This run's own clone (a ledger row names it) is not a hit; a hand resend's clone (no row) is.
Method TestOwnCloneAndHandResend()
{
    Set origin = ..Header(..ORU($LISTBUILD("9990000107^^^NHS^NH")), 8)
    Set clone = ..Header(..ORU($LISTBUILD("9990000107^^^NHS^NH")), 9)
    Set row = ##class(Shutter.Store.ResendRecord).%New()
    Set row.RunId = "RUN-TEST", row.Namespace = $NAMESPACE, row.Item = ..Item, row.OriginHeaderId = origin, row.NewHeaderId = clone, row.State = "completed"
    Do $$$AssertStatusOK(row.%Save(), "a ledger row")
    Set ..Ledger(row.%Id()) = ""
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, origin, "Results Out")
    Do $$$AssertNotTrue(r.hold, "Shutter's own clone is not newer: " _ r.why)
    Set hand = ..Header(..ORU($LISTBUILD("9990000107^^^NHS^NH")), 9)
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, origin, "Results Out")
    Do $$$AssertTrue(r.hold, "a hand resend's clone counts")
    Do $$$AssertEquals(r.patients.%Get(0).newer.header, hand, "and is named")
}

/// More than 2,000 newer headers hold the patient, and the cap is named; and the read's cost over 2,000 is reported.
Method TestCap()
{
    Set origin = ..Header(..ORU($LISTBUILD("9990000108^^^NHS^NH")), 8)
    Set body = ..Body(..ORU($LISTBUILD("9990000198^^^NHS^NH")))
    For i = 1:1:2000 { Do ..Bare(body, 9) }
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, origin, "Results Out")
    Do $$$AssertNotTrue(r.hold, "2,000 newer headers, none this patient's: read whole")
    Do $$$AssertEquals(r."headers_read", 2000, "2,000 read")
    Do $$$LogMessage("the read over 2,000 headers took " _ r."read_ms" _ " ms")
    Do ..Bare(body, 9)
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, origin, "Results Out")
    Do $$$AssertTrue(r.hold, "2,001 hold the patient")
    Do $$$AssertTrue(r.why [ "more than 2000", r.why)
}

/// Two failed messages for one patient with cases open: no self-hit and no hit on each other when both are in the set;
/// a blocked case outside the set holds.
Method TestCasesOpen()
{
    Set a = ..Header(..ORU($LISTBUILD("9990000109^^^NHS^NH")), 8)
    Set b = ..Header(..ORU($LISTBUILD("9990000109^^^NHS^NH")), 8)
    Set ca = ..Case("T-PC-0001", "9990000109", "NHS", "escalated"), cb = ..Case("T-PC-0002", "9990000109", "NHS", "proposed")
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, a, "Results Out", $LISTBUILD("T-PC-0001", "T-PC-0002"))
    Do $$$AssertNotTrue(r.hold, "its own case and the set's other are left out: " _ r.why)
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, b, "Results Out", $LISTBUILD("T-PC-0001", "T-PC-0002"))
    Do $$$AssertNotTrue(r.hold, "nor for the second: " _ r.why)
    Do ..Case("T-PC-0003", "9990000109", "NHS", "blocked")
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, a, "Results Out", $LISTBUILD("T-PC-0001", "T-PC-0002"))
    Do $$$AssertTrue(r.hold, "a blocked case outside the set holds")
    Do $$$AssertTrue(r.why [ "T-PC-0003 (blocked)", r.why)
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, a, "Another Out", $LISTBUILD("T-PC-0001", "T-PC-0002"))
    Do $$$AssertNotTrue(r.hold, "another receiver's case does not")
    Do ..Case("T-PC-0004", "9990000109", "NHS", "resolved")
}

/// An ORU with two patients, one held: the whole message is held, and says why.
Method TestOneOfTwoHeld()
{
    Set origin = ..Header(..ORU($LISTBUILD("9990000110^^^NHS^NH", "9990000111^^^NHS^NH")), 8)
    Do ..Case("T-PC-0005", "9990000111", "NHS", "blocked")
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, origin, "Results Out")
    Do $$$AssertTrue(r.hold, "the whole message waits")
    Do $$$AssertNotTrue(r.patients.%Get(0).hold, "the first patient is clear")
    Do $$$AssertTrue(r.patients.%Get(1).hold, "the second is held")
    Do $$$AssertTrue(r.why [ "1 of the message's 2 patients held", r.why)
}

/// The ledger compiles, and reads empty with no writer.
Method TestLedgerEmpty()
{
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.ResendRecord WHERE RunId <> 'RUN-TEST')
    Do $$$AssertEquals(SQLCODE _ "/" _ n, "0/0", "no rows")
    Do $$$AssertNotTrue(##class(Shutter.Store.ResendRecord).IsOwnClone($NAMESPACE, "1"), "nothing is a clone of Shutter's")
}

/// An ORU with one PID per patient group, PID-3 as given.
ClassMethod ORU(pids As %List, control As %String = "") As %String
{
    Set cr = $CHAR(13)
    Set:control="" control = "C" _ $INCREMENT(^||PatientCheckTest)
    Set text = "MSH|^~\&|FAKESEND|NORTHFIELD TEST SITE|FAKELIMS|TESTLAB ONE|20261105100000||ORU^R01|" _ control _ "|P|2.5.1"
    For i = 1:1:$LISTLENGTH(pids) {
        Set text = text _ cr _ "PID|1||" _ $LIST(pids, i) _ "||Testpatient^Alpha||19800101|U" _ cr _ "OBR|1|ORD" _ i _ "|FIL" _ i _ "|PANEL1" _ cr _ "OBX|1|ST|TST01||VAL10|||||F"
    }
    Quit text
}

ClassMethod Message(text As %String) As EnsLib.HL7.Message
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    Set msg.DocType = "2.5.1:ORU_R01"
    Quit msg
}

/// A saved body.
Method Body(text As %String) As %String
{
    Set msg = ..Message(text)
    Do msg.%Save()
    Set ..Bodies(msg.%Id()) = ""
    Quit msg.%Id()
}

/// A header to the test's item with a body of <var>text</var> and the engine status code <var>status</var> (8 Error,
/// 9 Completed).
Method Header(text As %String, status As %Integer) As %String
{
    Quit ..Bare(..Body(text), status)
}

Method Bare(bodyId As %String, status As %Integer) As %String
{
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.TargetConfigName = ..Item, h.SourceConfigName = "PatientCheck Test In", h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = bodyId
    Set h.Status = status, h.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3), h.Type = 1
    Do h.%Save()
    Set ..Headers(h.%Id()) = ""
    Quit h.%Id()
}

Method Case(caseId As %String, patientId As %String, authority As %String, state As %String) As %String
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = caseId, c.OperationKey = "LAB^" _ authority _ "^" _ patientId _ "^^result^2026-11-05T10:00:00Z"
    Set c.PatientId = patientId, c.PatientIdAuthority = authority, c.Receiver = "Results Out"
    Set c.FailureKind = "delivery_failed", c.State = state, c.OpenedAt = "2026-11-05T10:00:00Z"
    Do c.%Save()
    Set ..Cases(c.%Id()) = ""
    Quit c.%Id()
}

}
