/// The day's model budget (Shutter.Util.Budget; CONTRACTS 9, v1.34): the cap read from a text, the day's window, the
/// exhaustion rule and the refusal's words. The cap global is put back afterwards.
Class Shutter.Test.Budget Extends %UnitTest.TestCase
{

Property SavedCap As %String;

Method OnBeforeAllTests() As %Status
{
    Set ..SavedCap = $GET(^Shutter.Config("dailyBudgetUsd"), "<none>")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    If ..SavedCap = "<none>" { Kill ^Shutter.Config("dailyBudgetUsd") } Else { Set ^Shutter.Config("dailyBudgetUsd") = ..SavedCap }
    Quit $$$OK
}

Method TestConfigure()
{
    Do $$$AssertEquals(##class(Shutter.Util.Budget).Configure(""), 0, "empty: no cap")
    Do $$$AssertEquals(##class(Shutter.Util.Budget).Configure("five"), 0, "words: no cap")
    Do $$$AssertEquals(##class(Shutter.Util.Budget).Configure("-3"), 0, "a negative: no cap")
    Do $$$AssertEquals(##class(Shutter.Util.Budget).Configure(" 2.50 "), 2.5, "2.50 with spaces")
    Do $$$AssertEquals(##class(Shutter.Util.Budget).Cap(), 2.5, "and Cap reads it back")
    Do $$$AssertEquals(##class(Shutter.Util.Budget).Configure("5"), 5, "a whole number")
}

Method TestWindowAndRule()
{
    Do ##class(Shutter.Util.Budget).Configure("0")
    Set s = ##class(Shutter.Util.Budget).Status("2026-11-01T02:30:00Z")
    Do $$$AssertEquals(s.since, "2026-11-01T00:00:00Z", "the day starts at 00:00 UTC")
    Do $$$AssertEquals(s.resetsAt, "2026-11-02T00:00:00Z", "and resets at the next")
    Do $$$AssertEquals(s.dailyUsd, 0, "no cap")
    Do $$$AssertNotTrue(s.exhausted, "no cap is never exhausted, whatever was spent")
    Do $$$AssertTrue(s.spentTodayUsd >= 0, "the spend is a number: " _ s.spentTodayUsd)
    Do $$$AssertEquals(##class(Shutter.Util.Budget).Spent("2999-01-01T00:00:00Z"), 0, "nothing spent in the future")
    Do $$$AssertNotTrue(##class(Shutter.Util.Budget).Exhausted(0, 100), "cap 0: not exhausted")
    Do $$$AssertNotTrue(##class(Shutter.Util.Budget).Exhausted(5, 4.99), "below the cap")
    Do $$$AssertTrue(##class(Shutter.Util.Budget).Exhausted(5, 5), "at the cap")
    Do $$$AssertTrue(##class(Shutter.Util.Budget).Exhausted(5, 7.2), "over it")
    Set s = {"dailyUsd": 5, "spentTodayUsd": 5.12, "since": "2026-11-01T00:00:00Z", "resetsAt": "2026-11-02T00:00:00Z"}
    Set words = ##class(Shutter.Util.Budget).Refusal(s)
    Do $$$AssertTrue((words [ "5 USD") && (words [ "5.12 USD") && (words [ "2026-11-02T00:00:00Z") && (words [ "not sent"), "the refusal names the cap, the spend and the reset: " _ words)
    Do ##class(Shutter.Util.Budget).Configure("0.000001")
    Set s = ##class(Shutter.Util.Budget).Status()
    Do $$$AssertEquals(s.dailyUsd, .000001, "a tiny cap reads back")
    Do $$$AssertEquals(s.exhausted, (s.spentTodayUsd >= .000001), "exhausted follows the day's spend against it")
}

}
