/// The board's slots per minute (Shutter.Util.BoardSlots; CONTRACTS 6.6, v1.35): the count, the cap, the deferral rule and the
/// dropping of earlier minutes.
Class Shutter.Test.BoardSlots Extends %UnitTest.TestCase
{

Property Saved As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
    Merge ..Saved = ^Shutter.Board("convened")
    Kill ^Shutter.Board("convened")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Kill ^Shutter.Board("convened")
    Merge ^Shutter.Board("convened") = ..Saved
    Quit $$$OK
}

Method TestSlots()
{
    Set slots = "Shutter.Util.BoardSlots"
    Do $$$AssertEquals($CLASSMETHOD(slots, "MinuteKey", "2026-11-02T01:07:33Z"), "202611020107", "the minute's key from a UTC time")
    Do $$$AssertTrue($MATCH($CLASSMETHOD(slots, "MinuteKey"), "^20[0-9]{10}$"), "now is twelve digits")
    Set m = "202611020107"
    Do $$$AssertEquals($CLASSMETHOD(slots, "Count", m), 0, "nothing convened yet")
    Do $$$AssertNotTrue($CLASSMETHOD(slots, "Full", 2, m), "two allowed, none taken")
    Do $$$AssertNotTrue($CLASSMETHOD(slots, "Full", 0, m), "no cap, never full")
    Do $$$AssertEquals($CLASSMETHOD(slots, "Take", m), 1, "one taken")
    Do $$$AssertEquals($CLASSMETHOD(slots, "Take", m), 2, "two taken")
    Do $$$AssertTrue($CLASSMETHOD(slots, "Full", 2, m), "full at the cap")
    Do $$$AssertNotTrue($CLASSMETHOD(slots, "Full", 3, m), "not at a higher cap")
    // The next minute starts at nought, and old minutes are dropped as new ones are taken.
    Set ^Shutter.Board("convened", "202611020100") = 9
    Do $$$AssertEquals($CLASSMETHOD(slots, "Take", "202611020108"), 1, "a fresh minute")
    Do $$$AssertEquals($DATA(^Shutter.Board("convened", "202611020100")), 0, "a minute eight back is dropped")
    Do $$$AssertEquals($DATA(^Shutter.Board("convened", "202611020107")), 0, "and the last minute too: only the current minute counts")
    Do $$$AssertEquals($CLASSMETHOD(slots, "Count", "202611020108"), 1, "the new minute holds its one")
}

}
