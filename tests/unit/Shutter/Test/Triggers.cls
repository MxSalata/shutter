/// The feed's mapping of HL7 ADT messages (docs/CONTRACTS.md, section 2): the trigger table, what is delivered, the
/// encounter piece, a merge's prior record. Each test parses a hand-made 2.5.1 message through
/// <class>Shutter.Test.Feed</class> and reads the operation <class>Shutter.Util.OperationKey</class> builds, with no
/// production, no receiver and no case.
Class Shutter.Test.Triggers Extends %UnitTest.TestCase
{

Method Message(trigger As %String, structure As %String, segments As %String) As %String
{
    Set msh = "MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261019100000||ADT^" _ trigger _ "^" _ structure _ "|UT" _ trigger _ "|P|2.5.1"
    Set evn = "EVN|" _ trigger _ "|20261019100000||||20261019100000"
    Quit msh _ "<CR>" _ evn _ "<CR>" _ segments
}

Method Op(text As %String) As %DynamicObject
{
    Quit ##class(Shutter.Util.Json).Parse(##class(Shutter.Test.Feed).Map(text), .sc)
}

Parameter PID = "PID|1||MRN9001^^^HOSP^MR||SYNTH^UT||19800101|F";

Method PV1(class As %String, ward As %String, visit As %String) As %String
{
    // PV1-2 the class, PV1-3 the location, PV1-19 the visit number (sixteen separators after the location), PV1-44 the admit time.
    Quit "PV1|1|" _ class _ "|" _ $SELECT(ward = "": "", 1: ward _ "^BAY1^01^HOSP") _ "||||||||||||||||" _ visit _ "|||||||||||||||||||||||||20261019100000"
}

Method TestTriggerTable()
{
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A01"), "admit", "A01 admit")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A02"), "transfer", "A02 transfer")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A03"), "discharge", "A03 discharge")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A04"), "register", "A04 register")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A05"), "preadmit", "A05 preadmit")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A06"), "update", "A06 update")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A07"), "update", "A07 update")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A08"), "update", "A08 update")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A11"), "cancel_admit", "A11")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A12"), "cancel_transfer", "A12")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A13"), "cancel_discharge", "A13")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A28"), "person_add", "A28")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A31"), "person_update", "A31")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("a40"), "merge", "A40 merge, any case")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).EventForTrigger("A17"), "", "A17 does not map")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).DeliveryOf("update"), "deliver", "update is delivered")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).DeliveryOf("preadmit"), "index", "preadmit is indexed")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).DeliveryOf("cancel_transfer"), "cancel", "a cancel")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).DeliveryOf("merge"), "merge", "a merge")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).DeliveryOf("A17"), "", "an unmapped word")
}

Method TestTransferKey()
{
    Set op = ..Op(..Message("A02", "ADT_A02", ..#PID _ "<CR>" _ ..PV1("I", "WARD-B", "ENC-9001")))
    Do $$$AssertEquals(op.event, "transfer", "the event")
    Do $$$AssertEquals(op."operation_key", "PAS^HOSP^MRN9001^ENC-9001^transfer^2026-10-19T09:00:00Z", "the key, the time read in Europe/London")
    Do $$$AssertEquals(op.ward, "WARD-B", "the ward")
}

Method TestRegistrationIsIndexedUnlessInpatientWithBed()
{
    Set op = ..Op(..Message("A04", "ADT_A01", ..#PID _ "<CR>" _ ..PV1("O", "", "ENC-9002")))
    Do $$$AssertEquals(op.event, "register", "an outpatient registration without a bed")
    Do $$$AssertEquals(op."encounter_id", "ENC-9002", "its visit is kept")
    Set op = ..Op(..Message("A04", "ADT_A01", ..#PID _ "<CR>" _ ..PV1("I", "WARD-C", "ENC-9003")))
    Do $$$AssertEquals(op.event, "admit", "an inpatient registered with a bed is an admission")
    Do $$$AssertEquals(op.ward, "WARD-C", "with its ward")
}

Method TestPersonEventsNeedNoVisit()
{
    Set op = ..Op(..Message("A28", "ADT_A05", "PID|1||MRN9004^^^HOSP^MR||SYNTH^NEW||19900202|M<CR>PV1|1|N"))
    Do $$$AssertEquals(op.event, "person_add", "a person add")
    Do $$$AssertEquals(op."encounter_id", "-", "the encounter piece is the hyphen")
    Do $$$AssertEquals($PIECE(op."operation_key", "^", 4), "-", "in the key too")
    Set op = ..Op(..Message("A31", "ADT_A05", ..#PID _ "<CR>" _ ..PV1("I", "WARD-B", "ENC-9001")))
    Do $$$AssertEquals(op.event, "person_update", "a person update is never an encounter update")
}

Method TestDeliveredEventsNeedAVisit()
{
    Set op = ..Op(..Message("A02", "ADT_A02", ..#PID _ "<CR>" _ ..PV1("I", "WARD-B", "")))
    Do $$$AssertTrue(op.%IsDefined("error"), "a transfer without PV1-19 does not map")
    Do $$$AssertTrue(op.error [ "PV1-19", "and says which field: " _ op.error)
}

Method TestCancelIsItsOwnOperation()
{
    Set op = ..Op(..Message("A12", "ADT_A12", ..#PID _ "<CR>" _ ..PV1("I", "WARD-A", "ENC-9001")))
    Do $$$AssertEquals(op.event, "cancel_transfer", "the cancel word")
    Do $$$AssertEquals($PIECE(op."operation_key", "^", 5), "cancel_transfer", "is the key's fifth piece")
    Do $$$AssertEquals(op.%GetTypeOf("ward"), "null", "a cancel carries no ward")
}

Method TestMergeCarriesThePriorRecord()
{
    Set mrg = "MRG|MRN9000^^^HOSP^MR||||ENC-9000||OLD^NAME"
    Set op = ..Op(..Message("A40", "ADT_A39", ..#PID _ "<CR>" _ mrg _ "<CR>" _ ..PV1("I", "WARD-B", "ENC-9001")))
    Do $$$AssertEquals(op.event, "merge", "the event")
    Do $$$AssertEquals(op."patient_id", "MRN9001", "the surviving patient, read inside the PATIENT group")
    Do $$$AssertEquals(op."encounter_id", "ENC-9001", "the visit named")
    Do $$$AssertEquals(op."prior_patient_id", "MRN9000", "the prior patient")
    Do $$$AssertEquals(op."prior_patient_id_authority", "HOSP", "its authority")
    Do $$$AssertEquals(op."prior_encounter_id", "ENC-9000", "the prior visit")
    Do $$$AssertEquals(op."merge_groups", 1, "one group")
    Do $$$AssertTrue(op.%IsDefined("payload_digest") && (op."payload_digest" '= ""), "the digest is computed")
}

Method TestMergeWithoutVisitAndWithTwoGroups()
{
    Set g1 = ..#PID _ "<CR>" _ "MRG|NHS9000^^^NHS^NH~MRN9000^^^HOSP^MR||||ENC-9000"
    Set g2 = "PID|1||MRN9010^^^HOSP^MR||SYNTH^TWO||19700707|M<CR>MRG|MRN9009^^^HOSP^MR||||ENC-9009"
    Set op = ..Op(..Message("A40", "ADT_A39", g1 _ "<CR>" _ g2))
    Do $$$AssertEquals(op.event, "merge", "the event")
    Do $$$AssertEquals(op."encounter_id", "-", "no visit: the hyphen")
    Do $$$AssertEquals(op."prior_patient_id", "MRN9000", "the MR-typed repetition of the first group's MRG-1")
    Do $$$AssertEquals(op."merge_groups", 2, "two groups counted")
}

/// An event time that makes no date or time is not an empty time: every other row would read as later than it, and the
/// case would close as overtaken. The message doesn't map, and the error says the time couldn't be read.
Method TestUnreadableEventTimeDoesNotMap()
{
    Set msh = "MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261019100000||ADT^A02^ADT_A02|UTA02|P|2.5.1"
    For time = "202610", "20261345120000", "20260230120000", "soon" {
        Set op = ..Op(msh _ "<CR>EVN|A02|" _ time _ "||||" _ time _ "<CR>" _ ..#PID _ "<CR>" _ ..PV1("I", "WARD-A", "ENC-9001"))
        Do $$$AssertTrue(op.%IsDefined("error"), time _ " does not map")
        Do $$$AssertTrue(op.error [ "unreadable", time _ ": the error says so: " _ op.error)
    }
    Set op = ..Op(msh _ "<CR>EVN|A02|20261019100000||||20261019100000<CR>" _ ..#PID _ "<CR>" _ ..PV1("I", "WARD-A", "ENC-9001"))
    Do $$$AssertNotTrue(op.%IsDefined("error"), "a time that reads still maps")
}

Method TestUnmappedTriggerSaysSo()
{
    Set op = ..Op(..Message("A17", "ADT_A17", ..#PID _ "<CR>" _ ..PV1("I", "WARD-A", "ENC-9001")))
    Do $$$AssertTrue(op.%IsDefined("error"), "A17 does not map")
    Do $$$AssertTrue(op.error [ "A17", "the error names the trigger: " _ op.error)
}

}
