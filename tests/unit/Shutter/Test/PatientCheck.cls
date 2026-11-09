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

/// The stored profile's text before a test added its receivers, put back after it.
Property ProfileBefore As %String(MAXLEN = "");

/// The orders and results receiver the order rule's tests name: added to the stored profile by OrdersReceiver.
Parameter LAB = "PatientCheck Lab Out";

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
    If ..ProfileBefore '= "" {
        Set row = ##class(Shutter.Store.SiteProfile).Row()
        If $ISOBJECT(row) Set row.Json = ..ProfileBefore Do row.%Save()
        Set ..ProfileBefore = ""
    }
    Do ##class(Shutter.Util.PatientCheck).Pass(0)
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

// ---- v1.53: the order rule (docs/design-1.4.0.md, part 1) ----

/// The order keys as a table: Related, Distinct and OtherOrders on pairs of order groups, pure.
Method TestOrderKeysTable()
{
    Set pc = "Shutter.Util.PatientCheck"
    // placer, filler, parents: each "id^ns" or ""; parents "kind:id^ns,..."; related, distinct.
    Set rows = $LISTBUILD(
        $LISTBUILD("ORD1", "", "", "ORD1", "", "", 1, 0, "the same placer"),
        $LISTBUILD("ORD1^LAB", "", "", "ORD1", "", "", 1, 0, "the same placer, one namespace blank"),
        $LISTBUILD("ORD1^LAB", "", "", "ORD1^PAS", "", "", 0, 1, "the same identifier under two namespaces"),
        $LISTBUILD("ORD1", "", "", "ORD2", "", "", 0, 1, "two placers"),
        $LISTBUILD("ORD1", "FIL1", "", "", "FIL1", "", 1, 0, "the same filler"),
        $LISTBUILD("ORD1", "", "", "", "FIL9", "", 0, 0, "a placer and a filler: nothing to compare"),
        $LISTBUILD("ORD1", "", "", "ORD2", "", "placer:ORD1", 1, 0, "a reflex child: its parent is this placer"),
        $LISTBUILD("ORD2", "", "placer:ORD1", "ORD3", "", "placer:ORD1", 1, 0, "two reflex orders of one parent"),
        $LISTBUILD("ORD1", "", "", "ORD2", "", "filler:ORD1", 0, 1, "a parent filler is not compared with a placer"),
        $LISTBUILD("ORD1", "FIL1", "", "ORD2", "FIL2", "", 0, 1, "both numbers differ"))
    For i = 1:1:$LISTLENGTH(rows) {
        Set r = $LIST(rows, i)
        Set a = ..Group($LIST(r, 1), $LIST(r, 2), $LIST(r, 3)), b = ..Group($LIST(r, 4), $LIST(r, 5), $LIST(r, 6))
        Do $$$AssertEquals($CLASSMETHOD(pc, "Related", a, b) '= "", $LIST(r, 7), $LIST(r, 9) _ ": related")
        Do $$$AssertEquals($CLASSMETHOD(pc, "Related", b, a) '= "", $LIST(r, 7), $LIST(r, 9) _ ": related, the other way")
        Do $$$AssertEquals($CLASSMETHOD(pc, "Distinct", a, b), $LIST(r, 8), $LIST(r, 9) _ ": distinct")
    }
    Set one = [(..Group("ORD1", "", ""))], two = [(..Group("ORD2", "", "")), (..Group("ORD3", "", ""))]
    Do $$$AssertTrue($CLASSMETHOD(pc, "OtherOrders", one, two), "every pair distinct: other orders")
    Do two.%Push(..Group("ORD1", "", ""))
    Do $$$AssertNotTrue($CLASSMETHOD(pc, "OtherOrders", one, two), "one pair related: not other orders")
    Do $$$AssertNotTrue($CLASSMETHOD(pc, "OtherOrders", one, []), "a message with no order group: not other orders")
    // Orders reads ORC and OBR by name: an ORC and its OBR are one group; OBR-29 and ORC-8 are parents; ORC-1 and OBR-25.
    Set msg = ..Message(..Order("ORU^R01", "9990000201^^^NHS^NH", "ORD7^LAB", "FIL7", {"orc1": "RE", "status": "C", "parent": "ORD6&LAB^FIL6"}))
    Set g = ##class(Shutter.Util.PatientCheck).Orders(msg)
    Do $$$AssertEquals(g.%Size(), 1, "one order group")
    Do $$$AssertEquals(g.%Get(0).placer.id _ "/" _ g.%Get(0).placer.ns _ "/" _ g.%Get(0).filler.id, "ORD7/LAB/FIL7", "placer with its namespace, filler")
    Do $$$AssertEquals(g.%Get(0).control _ "/" _ g.%Get(0).status, "RE/C", "ORC-1 and OBR-25")
    Do $$$AssertEquals(g.%Get(0).parents.%Size(), 2, "the parents of OBR-29, placer and filler")
    Do $$$AssertEquals(g.%Get(0).parents.%Get(0).kind _ ":" _ g.%Get(0).parents.%Get(0).id _ "^" _ g.%Get(0).parents.%Get(0).ns, "placer:ORD6^LAB", "the parent placer with its namespace")
}

/// N1: a newer final result on the same order holds the preliminary one, and names the rule.
Method TestSameOrderNewerHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000211^^^NHS^NH", "ORD1", "", {"status": "P"}), 8)
    Do ..Header(..Order("ORU^R01", "9990000211^^^NHS^NH", "ORD1", "", {"status": "F", "control": "C123"}), 9)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold, "held")
    Do $$$AssertEquals(r.scope, "order", "the order rule")
    Do $$$AssertEquals(r.patients.%Get(0).rule, "same_order", "same_order")
    Do $$$AssertTrue(r.why [ "a newer message on the same order (placer ORD1) reached the receiver at ", r.why)
    Do $$$AssertTrue(r.why [ "(control id C123)", r.why)
}

/// A correction or amendment names the order it changes: OBR-25 C and OBX-11 C on the same order hold.
Method TestAmendmentHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000212^^^NHS^NH", "ORD1", "FIL1", {"status": "F"}), 8)
    Do ..Header(..Order("ORU^R01", "9990000212^^^NHS^NH", "ORD1", "FIL1", {"status": "C", "obx11": "C"}), 9)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "same_order"), "an amendment on the same order holds: " _ r.why)
}

/// A cancellation of the same order, each of the six codes, holds.
Method TestCancelSameOrderHolds()
{
    Do ..OrdersReceiver()
    For code = "CA", "OC", "CR", "DC", "OD", "DR" {
        Set origin = ..Header(..Order("ORM^O01", "9990000213^^^NHS^NH", "ORD" _ code, "", {}), 8)
        Do ..Header(..Order("ORM^O01", "9990000213^^^NHS^NH", "ORD" _ code, "", {"orc1": (code)}), 9)
        Set r = ..Check(origin)
        Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "same_order"), code _ " on the same order holds: " _ r.why)
    }
}

/// Matched by the filler alone: M has a placer and a filler, the newer one only the filler.
Method TestSameOrderByFiller()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000214^^^NHS^NH", "ORD1", "FIL1", {}), 8)
    Do ..Header(..Order("ORU^R01", "9990000214^^^NHS^NH", "", "FIL1", {}), 9)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.why [ "(filler FIL1)"), "the same filler holds: " _ r.why)
}

/// A reflex order: a newer ORM whose OBR-29 names this order as its parent holds it.
Method TestReflexChildHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000215^^^NHS^NH", "ORD1", "", {}), 8)
    Do ..Header(..Order("ORM^O01", "9990000215^^^NHS^NH", "ORD2", "", {"parent": "ORD1", "control": "C124"}), 9)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold, "held")
    Do $$$AssertEquals(r.patients.%Get(0).rule, "linked_order", "linked_order")
    Do $$$AssertTrue(r.why [ "a newer message on an order linked to this one (parent placer ORD1) reached the receiver at ", r.why)
}

/// Two reflex orders of one parent hold each other.
Method TestReflexSiblingHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORM^O01", "9990000216^^^NHS^NH", "ORD2", "", {"parent": "ORD1"}), 8)
    Do ..Header(..Order("ORM^O01", "9990000216^^^NHS^NH", "ORD3", "", {"parent": "ORD1"}), 9)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "linked_order"), "siblings hold: " _ r.why)
}

/// The same order number for another patient (a final result filed under the surviving identifier after a merge) holds.
Method TestSameOrderOtherPatientHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000217^^^NHS^NH", "ORD1", "", {"status": "P"}), 8)
    Do ..Header(..Order("ORU^R01", "9990000299^^^NHS^NH", "ORD1", "", {"status": "F"}), 9)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "same_order"), "another patient's message on the same order holds: " _ r.why)
}

/// A newer message on the same order that has not reached the receiver and is not in the set holds, and says a person
/// decides; one that is in the set does not (it goes after M).
Method TestSameOrderSetAsideHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000218^^^NHS^NH", "ORD1", "", {}), 8)
    Set aside = ..Header(..Order("ORU^R01", "9990000218^^^NHS^NH", "ORD1", "", {}), 5)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold, "held")
    Do $$$AssertTrue(r.why [ ("header " _ aside _ ", reads Suspended: a person decides the order's messages together"), r.why)
}

Method TestSameOrderInTheSetGoes()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000219^^^NHS^NH", "ORD1", "", {}), 8)
    Set other = ..Header(..Order("ORU^R01", "9990000219^^^NHS^NH", "ORD1", "", {}), 8)
    Set r = ..Check(origin, "", $LISTBUILD(origin, other))
    Do $$$AssertNotTrue(r.hold, "a member of the set on the same order goes after it: " _ r.why)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold, "outside the set it holds")
}

/// A newer body that can't be read holds, on both paths.
Method TestUnreadableNewerHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000220^^^NHS^NH", "ORD1", "", {}), 8)
    Set broken = ..Bare(990000999, 9)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "unreadable"), "the order rule: " _ r.why)
    Do $$$AssertTrue(r.why [ ("the newer message in header " _ broken _ " could not be read, so it can't be shown to be about another order"), r.why)
    Set adt = ..Header(..ORU($LISTBUILD("9990000221^^^NHS^NH")), 8)
    Set broken = ..Bare(990000998, 9)
    Set r = ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, adt, "Results Out")
    Do $$$AssertEquals(r.scope, "patient", "the patient-wide rule at a receiver with no category")
    Do $$$AssertTrue(r.hold && (r.why [ "could not be read"), "the patient-wide rule: " _ r.why)
}

/// O5.c in small: a newer result of another order for the same NHS number reached the receiver, and does not hold.
Method TestOtherOrderGoes()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9997001001^^^NHS^NH", "N51", "", {}), 8)
    Do ..Header(..Order("ORU^R01", "9997001001^^^NHS^NH", "C5", "", {"control": "C5"}), 9)
    Set r = ..Check(origin)
    Do $$$AssertNotTrue(r.hold, "results on other orders go: " _ r.why)
    Do $$$AssertEquals(r.older, "C5", "and the card's line knows it is older than one")
}

/// A newer ADT for the patient to the same item names no order: held.
Method TestNewerAdtForThePatientHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000222^^^NHS^NH", "ORD1", "", {}), 8)
    Do ..Header(..ADT("A08", "9990000222^^^NHS^NH", "", "C125"), 9)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "same_patient"), "held: " _ r.why)
    Do $$$AssertTrue(r.why [ "a newer message for identifier 9990000222 (NHS) reached the receiver at ", r.why)
    Do $$$AssertTrue(r.why [ "(control id C125), and it names no order, so it can't be shown to be about another order", r.why)
}

/// Only a placer here, only a filler there: nothing to compare, held.
Method TestNoComparableNumberHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000223^^^NHS^NH", "ORD1", "", {}), 8)
    Do ..Header(..Order("ORU^R01", "9990000223^^^NHS^NH", "", "FIL9", {}), 9)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.why [ "it carries only a filler number where this one has only a placer number"), r.why)
}

/// A replacement for the same patient holds whatever its numbers; a cancellation of another order does not.
Method TestReplacementHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORM^O01", "9990000224^^^NHS^NH", "ORD1", "", {}), 8)
    Do ..Header(..Order("ORM^O01", "9990000224^^^NHS^NH", "ORD9", "", {"orc1": "RP"}), 9)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "replacement"), r.why)
    Do $$$AssertTrue(r.why [ "a newer message for identifier 9990000224 (NHS) replaces an order (ORC-1 RP), and a replacement may carry new order numbers", r.why)
}

Method TestCancelOtherOrderGoes()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORM^O01", "9990000225^^^NHS^NH", "ORD1", "", {}), 8)
    Do ..Header(..Order("ORM^O01", "9990000225^^^NHS^NH", "ORD9", "", {"orc1": "CA"}), 9)
    Set r = ..Check(origin)
    Do $$$AssertNotTrue(r.hold, "a cancellation names its own order: " _ r.why)
}

/// N3: an A40, an A34 and an A47 after M, naming the patient in MRG-1 or in PID-3, to any item, hold.
Method TestMergeHolds()
{
    Do ..OrdersReceiver()
    For event = "A40", "A34", "A47" {
        For where = "MRG", "PID" {
            Set origin = ..Header(..Order("ORU^R01", "9990000226^^^NHS^NH", "ORD" _ event _ where, "", {}), 8)
            Set pid = $SELECT(where = "PID": "9990000226^^^NHS^NH", 1: "9990000280^^^NHS^NH")
            Set mrg = $SELECT(where = "MRG": "9990000226^^^NHS^NH", 1: "9990000281^^^NHS^NH")
            Set merge = ..AdtBody(..ADT(event, pid, mrg), $SELECT(event = "A40": "2.5.1:ADT_A39", 1: ""))
            Set r = ..Check(origin)
            Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "identity"), event _ " in " _ where _ ": " _ r.why)
            Do $$$AssertTrue(r.why [ ("an ADT^" _ event _ " at ") && (r.why [ "merges or changes identifier 9990000226 (NHS), after this message was created: the receiver may hold the patient under another identifier"), r.why)
            Do ##class(EnsLib.HL7.Message).%DeleteId(merge)
            Kill ..Bodies(merge)
        }
    }
}

Method TestMergeOfAnotherPatientGoes()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000227^^^NHS^NH", "ORD1", "", {}), 8)
    Do ..AdtBody(..ADT("A40", "9990000282^^^NHS^NH", "9990000283^^^NHS^NH"), "2.5.1:ADT_A39")
    Set r = ..Check(origin)
    Do $$$AssertNotTrue(r.hold, "a merge of another patient: " _ r.why)
}

/// One of Shutter's own cases on a merge naming the patient, opened after M was created, holds.
Method TestMergeCaseHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000228^^^NHS^NH", "ORD1", "", {}), 8)
    Set c = ..Case("T-PC-0031", "9990000284", "NHS", "escalated")
    Set case = ##class(Shutter.Store.Case).%OpenId(c)
    Set case.Event = "merge", case.PriorPatientId = "9990000228", case.PriorPatientIdAuthority = "NHS", case.Receiver = "Bed Manager Out", case.OpenedAt = "2999-01-01T00:00:00Z"
    Do case.%Save()
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "identity"), r.why)
    Do $$$AssertTrue(r.why [ "Shutter's case T-PC-0031 is a merge naming identifier 9990000228 (NHS), opened after this message was created", r.why)
    Set case.OpenedAt = "2000-01-01T00:00:00Z"
    Do case.%Save()
    Do $$$AssertNotTrue(..Check(origin).hold, "one opened before it does not")
}

/// More than 5,000 ADT bodies since M holds every candidate; the read keeps what it read inside a pass.
Method TestIdentityCapHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000229^^^NHS^NH", "ORD1", "", {}), 8)
    Set text = ..ADT("A08", "9990000285^^^NHS^NH", "", "CAP")
    Set t0 = $ZHOROLOG
    For i = 1:1:5001 {
        Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
        Do msg.%Save()
        Set ..Bodies(msg.%Id()) = ""
    }
    Set r = ..Check(origin)
    Do $$$LogMessage("the merge read over 5,001 ADT bodies took " _ r."read_ms" _ " ms (written in " _ $NUMBER($ZHOROLOG - t0, 1) _ " s)")
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "cap"), r.why)
    Do $$$AssertTrue(r.why [ "more than 5000 ADT messages passed through this namespace since this one, more than Shutter reads for merges", r.why)
}

/// N4: an unresolved case at the receiver whose stored copy is on another order does not hold; one on the same order does;
/// one whose copy can't be read does.
Method TestOpenCaseOtherOrderGoes()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000230^^^NHS^NH", "ORD1", "", {}), 8)
    Do ..CaseOn("T-PC-0041", "9990000230", ..Order("ORU^R01", "9990000230^^^NHS^NH", "ORD2", "", {}))
    Set r = ..Check(origin)
    Do $$$AssertNotTrue(r.hold, "a case on another order: " _ r.why)
}

Method TestOpenCaseSameOrderHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000231^^^NHS^NH", "ORD1", "", {}), 8)
    Do ..CaseOn("T-PC-0042", "9990000231", ..Order("ORU^R01", "9990000231^^^NHS^NH", "ORD1", "", {}))
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "open_case"), r.why)
    Do $$$AssertTrue(r.why [ "Shutter still has an unresolved case on the same order at this receiver: T-PC-0042 (escalated)", r.why)
}

Method TestOpenCaseUnreadableHolds()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000232^^^NHS^NH", "ORD1", "", {}), 8)
    Set c = ..Case("T-PC-0043", "9990000232", "NHS", "escalated")
    Set case = ##class(Shutter.Store.Case).%OpenId(c)
    Set case.Receiver = ..#LAB, case.SourceHeaderId = 990000997
    Do case.%Save()
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "unreadable"), r.why)
}

/// An order or result with no order number takes the patient-wide rule: a newer result of another order holds it.
Method TestNoOrderNumberFallsBack()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000233^^^NHS^NH", "", "", {}), 8)
    Do ..Header(..Order("ORU^R01", "9990000233^^^NHS^NH", "ORD5", "", {}), 9)
    Set r = ..Check(origin)
    Do $$$AssertEquals(r.scope, "patient", "the patient-wide rule")
    Do $$$AssertTrue(r.hold, "held, as before 1.4.0: " _ r.why)
}

/// An ADT keeps today's rule exactly: a newer ORU of another order for the patient holds an A08.
Method TestAdtKeepsThePatientRule()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..ADT("A08", "9990000234^^^NHS^NH", ""), 8)
    Do ..Header(..Order("ORU^R01", "9990000234^^^NHS^NH", "ORD5", "", {}), 9)
    Set r = ..Check(origin)
    Do $$$AssertEquals(r.scope, "patient", "the patient-wide rule")
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "same_patient"), r.why)
}

/// Inside a pass (a set's computation, an Engine Resend run) each newer body is read once and kept by header id; outside
/// one, every check reads it again.
Method TestPassKeepsWhatItRead()
{
    Do ..OrdersReceiver()
    Set origin = ..Header(..Order("ORU^R01", "9990000235^^^NHS^NH", "ORD1", "", {}), 8)
    Set newer = ..Header(..Order("ORU^R01", "9990000235^^^NHS^NH", "ORD2", "", {}), 9)
    Do ##class(Shutter.Util.PatientCheck).Pass(1)
    Do $$$AssertNotTrue(..Check(origin).hold, "another order: not held")
    Set body = ##class(Ens.MessageHeader).%OpenId(newer).MessageBodyId
    Do ##class(EnsLib.HL7.Message).%DeleteId(body)
    Kill ..Bodies(body)
    Do $$$AssertNotTrue(..Check(origin).hold, "inside the pass the body is not read again")
    Do ##class(Shutter.Util.PatientCheck).Pass(0)
    Set r = ..Check(origin)
    Do $$$AssertTrue(r.hold && (r.patients.%Get(0).rule = "unreadable"), "outside it the body is read again, and can't be: " _ r.why)
}

/// The check at the orders and results receiver.
Method Check(origin As %String, exclude As %List = "", members As %List = "") As %DynamicObject
{
    Quit ##class(Shutter.Util.PatientCheck).Check($NAMESPACE, ..Item, origin, ..#LAB, exclude, members)
}

/// Adds the orders and results receiver to the stored profile for this test (put back after it).
Method OrdersReceiver()
{
    Set sp = "Shutter.Store.SiteProfile"
    Set row = $CLASSMETHOD(sp, "Row")
    If '$ISOBJECT(row) {
        Do $CLASSMETHOD(sp, "Store", $CLASSMETHOD(sp, "Default").%ToJSON(), "test", "test", "", .v)
        Set row = $CLASSMETHOD(sp, "Row")
    }
    Set:..ProfileBefore="" ..ProfileBefore = row.Json
    Set p = {}.%FromJSON(row.Json)
    If '$ISOBJECT(p.receivers) Set p.receivers = []
    Do p.receivers.%Push({"name": (..#LAB), "category": "orders_results", "duplicates": {"behaviour": "refuses", "phrase": "ALREADY HELD"}})
    Set row.Json = p.%ToJSON()
    Do $$$AssertStatusOK(row.%Save(), "the receiver is in the stored profile")
}

/// An order or result: MSH-9 type, one PID, an ORC (unless opts.noOrc) and an OBR with placer and filler, an OBX.
/// opts: orc1 (ORC-1, default NW or RE), status (OBR-25, default F), parent (an EIP for OBR-29), obx11, control.
ClassMethod Order(type As %String, pid As %String, placer As %String, filler As %String, opts As %DynamicObject) As %String
{
    Set cr = $CHAR(13), control = opts.%Get("control")
    Set:control="" control = "C" _ $INCREMENT(^||PatientCheckTest)
    Set text = "MSH|^~\&|FAKESEND|NORTHFIELD TEST SITE|FAKELIMS|TESTLAB ONE|20261105100000||" _ type _ "|" _ control _ "|P|2.5.1"
    Set text = text _ cr _ "PID|1||" _ pid _ "||Testpatient^Alpha||19800101|U"
    Set orc1 = opts.%Get("orc1")
    Set:orc1="" orc1 = $SELECT($PIECE(type, "^") = "ORU": "RE", 1: "NW")
    If 'opts.%Get("noOrc") Set text = text _ cr _ "ORC|" _ orc1 _ "|" _ placer _ "|" _ filler
    Set obr = "OBR|1|" _ placer _ "|" _ filler _ "|PANEL1"
    Set status = opts.%Get("status")
    Set:status="" status = "F"
    Set $PIECE(obr, "|", 26) = status
    Set:opts.%Get("parent")'="" $PIECE(obr, "|", 30) = opts.%Get("parent")
    Set obx = "OBX|1|ST|TST01||VAL10"
    Set $PIECE(obx, "|", 12) = $SELECT(opts.%Get("obx11") '= "": opts.%Get("obx11"), 1: "F")
    Quit text _ cr _ obr _ cr _ obx
}

/// An ADT of the event, with PID-3 pid and, for a merge, MRG-1 mrg.
ClassMethod ADT(event As %String, pid As %String, mrg As %String, control As %String = "") As %String
{
    Set cr = $CHAR(13)
    Set:control="" control = "A" _ $INCREMENT(^||PatientCheckTest)
    Set text = "MSH|^~\&|FAKEPAS|NORTHFIELD TEST SITE|FAKELIMS|TESTLAB ONE|20261105100000||ADT^" _ event _ "|" _ control _ "|P|2.5.1"
    Set text = text _ cr _ "EVN|" _ event _ "|20261105100000" _ cr _ "PID|1||" _ pid _ "||Testpatient^Alpha||19800101|U"
    Set:mrg'="" text = text _ cr _ "MRG|" _ mrg
    Quit text _ cr _ "PV1|1|I"
}

/// A saved ADT body with the DocType given (an ADT structure, or blank: the merge read takes both).
Method AdtBody(text As %String, docType As %String) As %String
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    Set msg.DocType = docType
    Do msg.%Save()
    Set ..Bodies(msg.%Id()) = ""
    Quit msg.%Id()
}

/// An order group for the table: placer and filler as "id^ns", parents as "kind:id^ns,...".
ClassMethod Group(placer As %String, filler As %String, parents As %String) As %DynamicObject
{
    Set g = {"placer": null, "filler": null, "parents": [], "control": "", "status": ""}
    Do:placer'="" g.%Set("placer", {"id": ($PIECE(placer, "^")), "ns": ($PIECE(placer, "^", 2))})
    Do:filler'="" g.%Set("filler", {"id": ($PIECE(filler, "^")), "ns": ($PIECE(filler, "^", 2))})
    For i = 1:1:$LENGTH(parents, ",") {
        Set one = $PIECE(parents, ",", i)
        Continue:one=""
        Do g.parents.%Push({"kind": ($PIECE(one, ":")), "id": ($PIECE($PIECE(one, ":", 2), "^")), "ns": ($PIECE($PIECE(one, ":", 2), "^", 2))})
    }
    Quit g
}

/// An unresolved case at the orders and results receiver whose stored copy (a header in this namespace) is text.
Method CaseOn(caseId As %String, patientId As %String, text As %String) As %String
{
    Set copy = ..Bare(..Body(text), 9)
    // The copy is Shutter's: it is no newer message to the item.
    Set h = ##class(Ens.MessageHeader).%OpenId(copy)
    Set h.TargetConfigName = "PatientCheck Case Intake Store"
    Do h.%Save()
    Set c = ..Case(caseId, patientId, "NHS", "escalated")
    Set case = ##class(Shutter.Store.Case).%OpenId(c)
    Set case.Receiver = ..#LAB, case.SourceHeaderId = copy
    Do case.%Save()
    Quit c
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
