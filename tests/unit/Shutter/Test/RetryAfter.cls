/// Retry-After as a minimum wait (CONTRACTS 6.5, v1.35): the header's value as seconds, and the preflight read's wait.
Class Shutter.Test.RetryAfter Extends %UnitTest.TestCase
{

Method TestHeaderValue()
{
    Set w = "Shutter.Operation.Ward"
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryAfterOf", "20"), 20, "delta seconds")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryAfterOf", " 120 "), 120, "spaces around")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryAfterOf", "0"), "", "nought means no wait")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryAfterOf", "5000"), 3600, "an hour at most")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryAfterOf", "Sun, 06 Nov 1994 08:49:37 GMT"), "", "the date form is ignored")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryAfterOf", ""), "", "none")
    Do $$$AssertEquals($CLASSMETHOD(w, "RetryAfterOf", "soon"), "", "words are ignored")
}

Method TestPreflightWait()
{
    Set wf = "Shutter.Process.CaseWorkflow", time = "Shutter.Util.Time"
    Set case = ##class(Shutter.Store.Case).%New()
    Do $$$AssertEquals($CLASSMETHOD(wf, "PreflightWaitSeconds", case), 0, "no Retry-After, no wait")
    Set now = "2026-11-02T02:40:00Z"
    Set case.RetryAfterUntil = "2026-11-02T02:40:15Z"
    Do $$$AssertEquals($CLASSMETHOD(wf, "PreflightWaitSeconds", case, now), 15, "what is left of it")
    Set case.RetryAfterUntil = "2026-11-02T02:39:50Z"
    Do $$$AssertEquals($CLASSMETHOD(wf, "PreflightWaitSeconds", case, now), 0, "past: no wait")
    Set case.RetryAfterUntil = "2026-11-02T03:00:00Z"
    Do $$$AssertEquals($CLASSMETHOD(wf, "PreflightWaitSeconds", case, now), 300, "five minutes at most")
    Set case.RetryAfterUntil = $CLASSMETHOD(time, "FromNow", 40)
    Set wait = $CLASSMETHOD(wf, "PreflightWaitSeconds", case)
    Do $$$AssertTrue((wait >= 38) && (wait <= 40), "against the clock: " _ wait)
    Do $$$AssertEquals($CLASSMETHOD(wf, "PreflightWaitSeconds", ""), 0, "no case, no wait")
}

}
