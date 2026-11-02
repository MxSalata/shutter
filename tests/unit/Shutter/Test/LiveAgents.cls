/// Whether the live agents can run (CONTRACTS 12, v1.37): the provider's refusal of the key is told from other errors, a
/// run's outcome sets or clears the flag, the flag keeps live runs off for fifteen minutes with the next 00:00 UTC as
/// "until", and the availability object says so first, before the budget. The flag's globals are put back as they were.
Class Shutter.Test.LiveAgents Extends %UnitTest.TestCase
{

Method TestAuthFailureIsToldFromOtherErrors()
{
    Set la = "Shutter.Util.LiveAgents"
    Do $$$AssertEquals($CLASSMETHOD(la, "IsAuthFailure", "authentication_error: invalid x-api-key"), 1, "the provider's own words")
    Do $$$AssertEquals($CLASSMETHOD(la, "IsAuthFailure", "HTTP 401 Unauthorized"), 1, "a 401")
    Do $$$AssertEquals($CLASSMETHOD(la, "IsAuthFailure", "The API key is deactivated"), 1, "a deactivated key")
    Do $$$AssertEquals($CLASSMETHOD(la, "IsAuthFailure", "deadline passed after 120 s"), 0, "a timeout is not")
    Do $$$AssertEquals($CLASSMETHOD(la, "IsAuthFailure", "HTTP 429 rate limited"), 0, "nor a rate limit")
    Do $$$AssertEquals($CLASSMETHOD(la, "IsAuthFailure", ""), 0, "nor nothing")
}

Method TestRunsSetAndClearTheFlagAndItExpires()
{
    Set la = "Shutter.Util.LiveAgents", time = "Shutter.Util.Time"
    Do ..Keep()
    Kill ^Shutter.Config("provider", "authFailedAt"), ^Shutter.Config("provider", "authFailedText")
    Do $$$AssertEquals($CLASSMETHOD(la, "ProviderDown", .until, .text), 0, "no flag, no refusal")
    Do $CLASSMETHOD(la, "NoteRun", "replay", "error", "authentication_error")
    Do $$$AssertEquals($CLASSMETHOD(la, "ProviderDown"), 0, "a replay's error sets nothing")
    Do $CLASSMETHOD(la, "NoteRun", "live", "error", "deadline passed")
    Do $$$AssertEquals($CLASSMETHOD(la, "ProviderDown"), 0, "nor a live run's other error")
    Do $CLASSMETHOD(la, "NoteRun", "live", "error", "HTTP 401: authentication_error, invalid x-api-key")
    Do $$$AssertEquals($CLASSMETHOD(la, "ProviderDown", .until, .text), 1, "a refused key sets the flag")
    Set now = $CLASSMETHOD(time, "NowUTC")
    Do $$$AssertEquals(until, $CLASSMETHOD(la, "NextMidnightUTC", now), "until is the next 00:00 UTC: " _ until)
    Do $$$AssertTrue(text [ "provider_auth", "and the text names the status: " _ text)
    Set a = $CLASSMETHOD(la, "Availability", "operator")
    Do $$$AssertEquals(a.available, 0, "not available")
    Do $$$AssertEquals(a.reason, "provider_auth", "for the provider's refusal, before the budget")
    Do $$$AssertEquals(a.until, until, "with the same until")
    Do $CLASSMETHOD(la, "NoteRun", "live", "provider_auth", text)
    Do $$$AssertEquals($CLASSMETHOD(la, "ProviderDown"), 1, "a run refused for the flag leaves it")
    Set ^Shutter.Config("provider", "authFailedAt") = $CLASSMETHOD(time, "FromNow", -901)
    Do $$$AssertEquals($CLASSMETHOD(la, "ProviderDown"), 0, "after fifteen minutes the next run may try")
    Set ^Shutter.Config("provider", "authFailedAt") = $CLASSMETHOD(time, "FromNow", -60)
    Do $CLASSMETHOD(la, "NoteRun", "live", "ok", "")
    Do $$$AssertEquals($CLASSMETHOD(la, "ProviderDown"), 0, "an accepted call clears the flag")
    Do $$$AssertEquals($DATA(^Shutter.Config("provider", "authFailedAt")), 0, "and the global is gone")
    Set a = $CLASSMETHOD(la, "Availability", "operator")
    Do $$$AssertNotEquals(a.reason, "provider_auth", "the availability no longer names the provider")
    Do $$$AssertEquals(a.%GetTypeOf("until"), $SELECT(a.available: "null", 1: "string"), "until is null when available, a time when the budget is spent")
    Do ..Restore()
}

ClassMethod Keep()
{
    Set ^||ut.la("at") = $GET(^Shutter.Config("provider", "authFailedAt")), ^||ut.la("text") = $GET(^Shutter.Config("provider", "authFailedText"))
}

ClassMethod Restore()
{
    Kill ^Shutter.Config("provider", "authFailedAt"), ^Shutter.Config("provider", "authFailedText")
    If $GET(^||ut.la("at")) '= "" Set ^Shutter.Config("provider", "authFailedAt") = ^||ut.la("at"), ^Shutter.Config("provider", "authFailedText") = $GET(^||ut.la("text"))
    Kill ^||ut.la
}

}
