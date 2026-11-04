/// The demo's portal page (CONTRACTS 16, v1.41): it escapes what began in a message, says so when there is no board case,
/// links only to what the demo's edge leaves open, and shows nothing it can't read.
Class Shutter.Test.PortalGuide Extends %UnitTest.TestCase
{

Method Facts() As %DynamicObject
{
    Quit {"user": "demo-trace", "namespace": "SHUTTER", "updated": "13:44:30", "shutter": "running", "hospital": "stopped", "messages": 214, "queued": 0, "errors": 3,
        "feature": {"caseId": "C-000034", "session": "641", "members": 4},
        "cases": [{"caseId": "C-000041", "state": "blocked", "story": "<script>alert('x')</script> & more", "session": "650"}, {"caseId": "C-000040", "state": "resolved", "story": "Fine", "session": "not-a-number"}],
        "agents": [{"member": "conformance", "lastAt": "2026-11-04T13:44:30Z"}]}
}

Method TestEscapesWhatBeganInAMessage()
{
    Set h = ##class(Shutter.Portal.Guide).Html(..Facts(), "/csp/healthshare/shutter/")
    Do $$$AssertNotTrue(h [ "<script", "no script reaches the page")
    Do $$$AssertTrue(h [ "&lt;script&gt;", "the headline is shown as text")
    Do $$$AssertNotTrue(h [ "SESSIONID=not-a-number", "a session that isn't a number makes no link")
}

Method TestWhatItSays()
{
    Set guide = "Shutter.Portal.Guide"
    Set h = $CLASSMETHOD(guide, "Html", ..Facts(), "/csp/healthshare/shutter/")
    Do $$$AssertTrue(h [ "C-000034: the escalated S8 case", "the board's case by its number")
    Do $$$AssertTrue(h [ "4 agents, each in its own lane", "with the agents it counted")
    Do $$$AssertTrue(h [ "EnsPortal.VisualTrace.zen?SESSIONID=641", "and its trace")
    Do $$$AssertTrue(h [ ">Stopped<", "a stopped production says so")
    Do $$$AssertTrue(h [ "Agent Conformance", "the agents by name")
    Do $$$AssertEquals($CLASSMETHOD(guide, "Story", "Blocked by the gate: Blocked: no receipt", ""), "Blocked by the gate: no receipt", "a blocked case says so once")
    Do $$$AssertEquals($CLASSMETHOD(guide, "Story", "", "Ward unavailable"), "Ward unavailable", "a case with no headline shows its failure")
    Do $$$AssertTrue(h [ "last 2026-11-04 13:44 UTC", "and when each last ran, with its date, since a kept run can be days old")
    Do $$$AssertNotTrue(h [ "Mock-up", "no mock-up's words")
    Set f = ..Facts()
    Set f.feature = "", f.cases = [], f.agents = []
    Set f.hospital = "", f.errors = ""
    Set h = $CLASSMETHOD(guide, "Html", f, "/csp/healthshare/shutter/")
    Do $$$AssertTrue(h [ "No board case on this instance yet", "no S8 case yet, and it says so")
    Do $$$AssertTrue(h [ "No case on this instance yet", "no cases")
    Do $$$AssertTrue(h [ "No agent has run on this instance yet", "no agents")
    Do $$$AssertNotTrue(h [ "Hospital production", "a state it can't read leaves its tile out")
    Do $$$AssertNotTrue(h [ "Errors logged", "as does a count")
}

/// The edge's allow-list: the portal's three pages in both namespaces, the Visual Trace in Shutter's, and the app.
Method TestLinksOnlyToWhatTheEdgeLeavesOpen()
{
    Set h = ##class(Shutter.Portal.Guide).Html(..Facts(), "/csp/healthshare/shutter/")
    Set m = ##class(%Regex.Matcher).%New("href='([^']*)'", h), n = 0
    While m.Locate() {
        Set href = m.Group(1), n = n + 1
        Set ok = (href = "/shutter/index.html")
        If 'ok Set ok = ##class(%Regex.Matcher).%New("^/csp/healthshare/(shutter|hospital)/EnsPortal\.(ProductionMonitor|MessageViewer|EventLog)\.zen$", href).Locate()
        If 'ok Set ok = ##class(%Regex.Matcher).%New("^/csp/healthshare/shutter/EnsPortal\.VisualTrace\.zen\?SESSIONID=[0-9]+$", href).Locate()
        Do $$$AssertTrue(ok, "open on the demo's edge: " _ href)
    }
    Do $$$AssertTrue(n >= 8, "it has its links: " _ n)
    Do $$$AssertNotTrue(h [ "<form", "no form")
    Do $$$AssertNotTrue(h [ "<script", "no script")
    Do $$$AssertTrue(h [ "http-equiv='refresh'", "a plain refresh")
}

/// Read from this instance, each figure or empty; a namespace that does not exist reads as unknown, not as an error.
Method TestFactsAreReadOrEmpty()
{
    Set guide = "Shutter.Portal.Guide"
    Set f = $CLASSMETHOD(guide, "Facts")
    Do $$$AssertEquals(f.user, $USERNAME, "the caller")
    Do $$$AssertEquals(f.namespace, $NAMESPACE, "the namespace")
    Do $$$AssertTrue(f.cases.%IsA("%DynamicArray") && f.agents.%IsA("%DynamicArray"), "the lists are lists")
    Do $$$AssertEquals($CLASSMETHOD(guide, "ProductionState", "NO_SUCH_NAMESPACE"), "", "a namespace that isn't there")
    Do $$$AssertEquals($CLASSMETHOD(guide, "Count", "SELECT COUNT(*) AS n FROM No_Such.Table"), "", "a count that can't run")
}

}
