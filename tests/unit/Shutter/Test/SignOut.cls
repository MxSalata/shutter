/// Signing out of the web application ends the IRIS session (1.1.2), and the public demo's API sessions are short: each
/// signed-in session holds a licence connection until it ends, and the Community licence refuses every new login once the
/// instance holds 8 (the demo of 8 Nov 2026: the portal page answered 503 after the 8th sign-in).
Class Shutter.Test.SignOut Extends %UnitTest.TestCase
{

/// DELETE /session logs the session out and ends it at the end of the request, so its licence connection is freed then,
/// not at the application's timeout; the answer is still {"signedOut": true}.
Method TestLogoutEndsTheSession()
{
    New %session, %response
    Set %session = ##class(Shutter.Test.FakeSession).%New()
    Set %response = ##class(%CSP.Response).%New()
    Set io = $IO, null = "/dev/null"
    Open null:"W":2
    Set opened = $TEST
    If opened Use null
    Set sc = ##class(Shutter.API.Dispatch).Logout()
    If opened Use io Close null
    Do $$$AssertStatusOK(sc, "the sign-out answers")
    Do $$$AssertEquals(%session.LoggedOut, 1, "the session is logged out")
    Do $$$AssertEquals(%session.EndSession, 1, "and ends with the request, freeing its licence connection")
    Do $$$AssertEquals(%response.Status, "200 OK", "200")
    Do $$$AssertEquals(%response.ContentType, "application/json", "with JSON")
}

/// The demo's session timeout outlasts the slowest poll of an open tab (30 s, the live hospital's banner) at least twice
/// over, so a visible tab is never signed out, and is at most a third of IRIS's 900 s, so a closed tab's session ends soon.
Method TestDemoTimeoutBounds()
{
    Set t = ##class(Shutter.Setup).#DEMOAPISESSIONSECONDS
    Do $$$AssertTrue(t >= 60, "at least twice the 30 s poll: " _ t)
    Do $$$AssertTrue(t <= 300, "and at most a third of IRIS's 900 s: " _ t)
}

}
