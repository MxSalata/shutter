/// Another visit's movement that a read after the snapshot finds and the snapshot did not show (Shutter.Util.FurtherNew), on
/// rows alone: a site that shows such a movement on the plan has its approval given on what the plan showed, so a row the plan
/// did not show is new, and an approval never carries it through.
Class Shutter.Test.FurtherNew Extends %UnitTest.TestCase
{

ClassMethod Item(control As %String, visit As %String, why As %String = "other_visit") As %DynamicObject
{
    Quit {"why": (why), "event": "admit", "message_type": "ADT_A01", "visit_number": (visit), "event_time": "2026-10-15T08:30:00Z", "control_id": (control)}
}

ClassMethod Found(shows As %DynamicArray, stops As %DynamicArray = "") As %DynamicObject
{
    Quit {"identifier": "read", "stops": ($SELECT($ISOBJECT(stops): stops, 1: [])), "shows": (shows), "unread": ""}
}

/// A row of another visit the snapshot did not show is new; one it showed, by control id and visit, is not.
Method TestANewRowIsFoundByControlIdAndVisit()
{
    Set fresh = ..Found([(..Item("M-2", "ENC-2"))])
    Do $$$AssertEquals(##class(Shutter.Util.FurtherNew).Rows(fresh, ..Found([])).%Size(), 1, "a row the snapshot did not show is new")
    Do $$$AssertEquals(##class(Shutter.Util.FurtherNew).Rows(fresh, "").%Size(), 1, "with no snapshot's further messages, every row is new")
    Do $$$AssertEquals(##class(Shutter.Util.FurtherNew).Rows(fresh, ..Found([(..Item("M-2", "ENC-2"))])).%Size(), 0, "a row the snapshot showed is not")
    Do $$$AssertEquals(##class(Shutter.Util.FurtherNew).Rows(fresh, ..Found([(..Item("M-2", "ENC-3"))])).%Size(), 1, "the same control id on another visit is new")
    Do $$$AssertEquals(##class(Shutter.Util.FurtherNew).Rows(fresh, ..Found([(..Item("M-9", "ENC-2"))])).%Size(), 1, "another control id on the same visit is new")
    Set two = ..Found([(..Item("M-2", "ENC-2")), (..Item("M-3", "ENC-4"))])
    Set rows = ##class(Shutter.Util.FurtherNew).Rows(two, ..Found([(..Item("M-2", "ENC-2"))]))
    Do $$$AssertEquals(rows.%Size(), 1, "only the row the snapshot did not show")
    If rows.%Size() Do $$$AssertEquals(rows.%Get(0)."visit_number", "ENC-4", "is the new one")
}

/// Only another visit's movement counts: what shows anyway, such as an out-patient attendance, stops nothing whenever it came.
Method TestOnlyAnotherVisitsMovementCounts()
{
    Set fresh = ..Found([(..Item("M-5", "ENC-5", "shown"))])
    Do $$$AssertEquals(##class(Shutter.Util.FurtherNew).Rows(fresh, ..Found([])).%Size(), 0, "a row shown anyway is not new movement")
    Do $$$AssertEquals(##class(Shutter.Util.FurtherNew).Rows("", ..Found([])).%Size(), 0, "no read, no rows")
    Do $$$AssertEquals(##class(Shutter.Util.FurtherNew).Rows(..Found([], [(..Item("M-6", "ENC-6"))]), ..Found([])).%Size(), 0, "a stop is the gate's FURTHER_MOVEMENT, not a new row here")
}

/// What a person reads: the new visit, the case's own, and how many more.
Method TestDescribeNamesTheNewVisit()
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.PatientId = "MRN1", case.PatientIdAuthority = "HOSP", case.EncounterId = "ENC-1", case.Event = "transfer"
    Do $$$AssertEquals(##class(Shutter.Util.FurtherNew).Describe(case, ..Found([]), ..Found([])), "", "nothing new, nothing to say")
    Set text = ##class(Shutter.Util.FurtherNew).Describe(case, ..Found([(..Item("M-2", "ENC-2")), (..Item("M-3", "ENC-4"))]), ..Found([]))
    Do $$$AssertTrue(text [ "visit ENC-2", "names the new visit: " _ text)
    Do $$$AssertTrue(text [ "visit ENC-1", "and the case's own: " _ text)
    Do $$$AssertTrue(text [ "and 1 more", "and counts the rest: " _ text)
    Do $$$AssertTrue(text [ "after the plan", "and says the plan did not show it: " _ text)
}

}
