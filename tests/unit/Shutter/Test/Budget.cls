/// The day's model budget (Shutter.Util.Budget; CONTRACTS 9, v1.34): the cap read from a text, the day's window, the
/// exhaustion rule and the refusal's words. The cap global is put back afterwards.
Class Shutter.Test.Budget Extends %UnitTest.TestCase
{

Property SavedCap As %String;

Property SavedShare As %String;

Property SavedReserve As %String;

Property SavedReservations As %String [ MultiDimensional ];

/// The bound on one model call (v1.35): 120 s by default, held to 10 to 600, set and cleared by ConfigureProviderTimeout,
/// applied from the environment at a start and shown by the Doctor.
Method TestProviderTimeoutSetting()
{
    Set saved = $GET(^Shutter.Config("providerTimeoutSeconds"), "<none>")
    Try {
        Kill ^Shutter.Config("providerTimeoutSeconds")
        Do $$$AssertEquals(##class(Shutter.Setup).ProviderTimeoutSeconds(), 120, "120 s unless configured")
        Do $$$AssertEquals(##class(Shutter.Setup).ConfigureProviderTimeout("45"), 45, "set to 45")
        Do $$$AssertEquals(##class(Shutter.Setup).ProviderTimeoutSeconds(), 45, "and read back")
        Do $$$AssertEquals(##class(Shutter.Setup).ConfigureProviderTimeout("3"), 10, "never under 10")
        Do $$$AssertEquals(##class(Shutter.Setup).ConfigureProviderTimeout("9999"), 600, "never over the board's 600")
        Do $$$AssertEquals(##class(Shutter.Setup).ConfigureProviderTimeout(""), 120, "empty puts the default back")
        Set applied = ##class(Shutter.Setup).ApplyRuntime("", "", "", "", "", "", 0, "90")
        Do $$$AssertEquals(applied.providerTimeoutSeconds, 90, "the environment sets it at a start: " _ applied.%ToJSON())
        Do $$$AssertTrue(##class(Shutter.Setup).Doctor() [ """provider_timeout_seconds"":90", "and the Doctor shows it")
    } Catch ex {
        Do $$$AssertTrue(0, "error: " _ ex.DisplayString())
    }
    If saved = "<none>" { Kill ^Shutter.Config("providerTimeoutSeconds") } Else { Set ^Shutter.Config("providerTimeoutSeconds") = saved }
}

Method OnBeforeAllTests() As %Status
{
    Set ..SavedCap = $GET(^Shutter.Config("dailyBudgetUsd"), "<none>")
    Set ..SavedShare = $GET(^Shutter.Config("judgeBudgetUsd"), "<none>")
    Set ..SavedReserve = $GET(^Shutter.Config("budgetReserveUsd"), "<none>")
    Merge ..SavedReservations = ^Shutter.Budget("reserve")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    If ..SavedCap = "<none>" { Kill ^Shutter.Config("dailyBudgetUsd") } Else { Set ^Shutter.Config("dailyBudgetUsd") = ..SavedCap }
    If ..SavedShare = "<none>" { Kill ^Shutter.Config("judgeBudgetUsd") } Else { Set ^Shutter.Config("judgeBudgetUsd") = ..SavedShare }
    If ..SavedReserve = "<none>" { Kill ^Shutter.Config("budgetReserveUsd") } Else { Set ^Shutter.Config("budgetReserveUsd") = ..SavedReserve }
    Kill ^Shutter.Budget("reserve")
    Merge ^Shutter.Budget("reserve") = ..SavedReservations
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
    Do $$$AssertTrue((words [ "5.00 USD") && (words [ "5.12 USD") && (words [ "2026-11-02T00:00:00Z") && (words [ "not sent"), "the refusal names the cap, the spend and the reset in dollars and cents: " _ words)
    Do $$$AssertEquals(##class(Shutter.Util.Budget).Dollars(.01), "0.01 USD", "a leading zero")
    Do $$$AssertEquals(##class(Shutter.Util.Budget).Dollars(9.005124), "9.01 USD", "two decimals, rounded")
    // The per-user share (v1.34): read from a text, counted per asker, exhausted on its own.
    Do $$$AssertEquals(##class(Shutter.Util.Budget).ConfigureShare(""), 0, "no share by default")
    Do $$$AssertEquals(##class(Shutter.Util.Budget).ConfigureShare("1.25"), 1.25, "a share of 1.25")
    Do $$$AssertEquals(##class(Shutter.Util.Budget).Share(), 1.25, "read back")
    Do $$$AssertEquals(##class(Shutter.Util.Budget).SpentBy("judge", "2999-01-01T00:00:00Z"), 0, "nothing spent by a user in the future")
    Do $$$AssertEquals(##class(Shutter.Util.Budget).SpentBy("", "2026-11-01T00:00:00Z"), 0, "nobody spends nothing")
    Set f = ##class(Shutter.Util.Budget).StatusFor("judge", "2026-11-01T02:30:00Z")
    Do $$$AssertTrue(f.%IsDefined("spentByMeUsd") && f.%IsDefined("shareExhausted") && (f.perUserUsd = 1.25), "the user's status carries their spend and share: " _ f.%ToJSON())
    Do $$$AssertTrue(##class(Shutter.Util.Budget).AllowsFor("system", .st), "the feed's own runs have no share")
    Set share = {"dailyUsd": 5, "spentTodayUsd": 2, "perUserUsd": 1, "spentByMeUsd": 1.1, "shareExhausted": true, "since": "2026-11-01T00:00:00Z", "resetsAt": "2026-11-02T00:00:00Z"}
    Set words = ##class(Shutter.Util.Budget).Refusal(share)
    Do $$$AssertTrue((words [ "Your share") && (words [ "1.00 USD") && (words [ "1.10 USD"), "a spent share is named as the user's: " _ words)
    // The environment applied at a start (Setup.ApplyRuntime, v1.34): a value sets, an empty one leaves the setting alone.
    Set applied = ##class(Shutter.Setup).ApplyRuntime("2.5", "0.75", "", "", "", "")
    Do $$$AssertTrue((+applied.dailyBudgetUsd = 2.5) && (+applied.judgeBudgetUsd = 0.75), "both set from the environment: " _ applied.%ToJSON())
    Do $$$AssertTrue((+##class(Shutter.Util.Budget).Cap() = 2.5) && (+##class(Shutter.Util.Budget).Share() = 0.75), "and stored")
    Set applied = ##class(Shutter.Setup).ApplyRuntime("", "", "", "", "", "")
    Do $$$AssertTrue('applied.%IsDefined("dailyBudgetUsd") && 'applied.%IsDefined("errors") && (##class(Shutter.Util.Budget).Cap() = 2.5), "an empty environment changes nothing: " _ applied.%ToJSON())
    Do ##class(Shutter.Util.Budget).ConfigureShare("0")
    Do ##class(Shutter.Util.Budget).Configure("0.000001")
    Set s = ##class(Shutter.Util.Budget).Status()
    Do $$$AssertEquals(s.dailyUsd, .000001, "a tiny cap reads back")
    Do $$$AssertEquals(s.exhausted, (s.spentTodayUsd >= .000001), "exhausted follows the day's spend against it")
}

/// Reserve, then settle (v1.35): a run in flight counts against the cap before its row exists.
Method TestReserveThenSettle()
{
    Set b = "Shutter.Util.Budget"
    Kill ^Shutter.Budget("reserve")
    Set ^Shutter.Config("budgetReserveUsd") = 0.40
    Do $$$AssertEquals($CLASSMETHOD(b, "Estimate"), 0.4, "the site's figure is the estimate")
    Kill ^Shutter.Config("budgetReserveUsd")
    Do $$$AssertTrue($CLASSMETHOD(b, "Estimate") >= 0.01, "without it, the mean of the last runs or the default: " _ $CLASSMETHOD(b, "Estimate"))
    Set ^Shutter.Config("budgetReserveUsd") = "0.40"
    Do $CLASSMETHOD(b, "ConfigureShare", "0")
    // The cap sits one dollar above whatever the day has spent so far, so the arithmetic below holds on any instance.
    Set spent = $CLASSMETHOD(b, "Status").spentTodayUsd
    Do $CLASSMETHOD(b, "Configure", $FNUMBER(spent + 1, "", 2))
    Set s = $CLASSMETHOD(b, "Status")
    Do $$$AssertEquals(s.reservedUsd _ "|" _ s.inFlight, "0|0", "nothing in flight")
    Do $$$AssertNotTrue(s.exhausted, "a dollar left")
    Do $$$AssertEquals($CLASSMETHOD(b, "Reserve", "test-run-a", "approver"), 0.4, "a run reserves the estimate")
    Do $CLASSMETHOD(b, "Reserve", "test-run-b", "operator")
    Set s = $CLASSMETHOD(b, "Status")
    Do $$$AssertTrue((+s.reservedUsd = 0.8) && (s.inFlight = 2), "two runs in flight, 0.80 reserved: " _ s.reservedUsd _ "|" _ s.inFlight)
    Do $$$AssertNotTrue(s.exhausted, "0.80 of the dollar reserved: still allowed")
    Do $CLASSMETHOD(b, "Reserve", "test-run-c", "approver")
    Set s = $CLASSMETHOD(b, "Status")
    Do $$$AssertTrue((+s.reservedUsd = 1.2) && (s.inFlight = 3), "three in flight: " _ s.reservedUsd _ "|" _ s.inFlight)
    Do $$$AssertTrue(s.exhausted, "spend plus reservations reach the cap: the next run is refused")
    Do $$$AssertNotTrue($CLASSMETHOD(b, "Allows", .st), "Allows says no")
    Do $$$AssertTrue($CLASSMETHOD(b, "Refusal", st) [ "with 3 run(s) in flight, 1.20 USD reserved", "and the refusal names the runs in flight: " _ $CLASSMETHOD(b, "Refusal", st))
    // A user's share counts that user's reservations.
    Do $CLASSMETHOD(b, "ConfigureShare", "0.50")
    Set sf = $CLASSMETHOD(b, "StatusFor", "approver")
    Do $$$AssertTrue(+sf.reservedByMeUsd = 0.8, "two of the three are the approver's: " _ sf.reservedByMeUsd)
    Do $$$AssertTrue(sf.shareExhausted, "whose share of 0.50 is spoken for")
    Set sf = $CLASSMETHOD(b, "StatusFor", "operator")
    Do $$$AssertTrue(+sf.reservedByMeUsd = 0.4, "one is the operator's: " _ sf.reservedByMeUsd)
    Do $CLASSMETHOD(b, "ConfigureShare", "0")
    // Settling frees the reservations; a stale one is dropped by itself.
    Do $CLASSMETHOD(b, "Settle", "test-run-a"), $CLASSMETHOD(b, "Settle", "test-run-b"), $CLASSMETHOD(b, "Settle", "test-run-c")
    Set s = $CLASSMETHOD(b, "Status")
    Do $$$AssertEquals(s.reservedUsd _ "|" _ s.inFlight, "0|0", "all settled")
    Do $$$AssertNotTrue(s.exhausted, "allowed again")
    Set ^Shutter.Budget("reserve", "test-run-stale") = $LISTBUILD(0.4, 0, "approver")
    Do $$$AssertEquals($CLASSMETHOD(b, "Reserved", "", .n) _ "|" _ n, "0|0", "a reservation from a job that died is dropped")
    Do $$$AssertEquals($DATA(^Shutter.Budget("reserve", "test-run-stale")), 0, "and removed")
    Kill ^Shutter.Budget("reserve")
}

}
