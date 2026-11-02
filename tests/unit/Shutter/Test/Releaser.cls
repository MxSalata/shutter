/// The Case Releaser's run rows (Shutter.Store.ReleaseRun; CONTRACTS 8.1, v1.35): begin and end, the interrupt at start,
/// the status, the candidates, and the keep count. The rows this test writes are deleted at the end.
Class Shutter.Test.Releaser Extends %UnitTest.TestCase
{

Property Ids As %String [ MultiDimensional ];

Method OnAfterAllTests() As %Status
{
    Set id = ""
    For {
        Set id = $ORDER(..Ids(id)) Quit:id=""
        Do ##class(Shutter.Store.ReleaseRun).%DeleteId(id)
    }
    Quit $$$OK
}

Method Keep(run As Shutter.Store.ReleaseRun)
{
    Set ..Ids(run.%Id()) = ""
}

Method TestBeginAndEnd()
{
    Set rr = "Shutter.Store.ReleaseRun"
    Do $$$AssertStatusOK($CLASSMETHOD(rr, "Begin", .run), "a run opens")
    Do ..Keep(run)
    Do $$$AssertEquals(run.State, "running", "running")
    Do $$$AssertEquals(run.Job, $JOB, "by this job")
    Do $$$AssertEquals($EXTRACT(run.StartedAt, 1, 10), $EXTRACT(##class(Shutter.Util.Time).NowUTC(), 1, 10), "dated now")
    Do $$$AssertStatusOK(run.End(3, 1, 2, 0), "ended")
    Set again = $CLASSMETHOD(rr, "%OpenId", run.%Id())
    Do $$$AssertEquals(again.State _ "|" _ again.WaitingChecked _ "|" _ again.WaitingReleased _ "|" _ again.HeldChecked _ "|" _ again.HeldReleased, "done|3|1|2|0", "done, with the counts")
    Do $$$AssertNotEquals(again.EndedAt, "", "and an end time")
    Do $$$AssertStatusOK($CLASSMETHOD(rr, "Begin", .failed), "a second run")
    Do ..Keep(failed)
    Do $$$AssertStatusOK(failed.End(1, 0, 0, 0, "the lookup threw"), "ended with an error")
    Do $$$AssertEquals(failed.State _ "|" _ failed.Error, "failed|the lookup threw", "failed, with the error")
    Set last = $CLASSMETHOD(rr, "Last")
    Do $$$AssertEquals(last.id, failed.%Id(), "the last run is the newest row")
    Do $$$AssertEquals(last.state, "failed", "projected with its state")
    Set recent = $CLASSMETHOD(rr, "Recent", 2)
    Do $$$AssertEquals(recent.%Size(), 2, "two recent rows asked for")
    Do $$$AssertEquals(recent.%Get(0).id _ "," _ recent.%Get(1).id, failed.%Id() _ "," _ run.%Id(), "newest first")
}

Method TestInterruptAtStart()
{
    Set rr = "Shutter.Store.ReleaseRun"
    Do $$$AssertStatusOK($CLASSMETHOD(rr, "Begin", .a), "one open run")
    Do ..Keep(a)
    Do $$$AssertStatusOK($CLASSMETHOD(rr, "Begin", .b), "another")
    Do ..Keep(b)
    Do $$$AssertStatusOK($CLASSMETHOD(rr, "Begin", .c), "and one that ends")
    Do ..Keep(c)
    Do $$$AssertStatusOK(c.End(0, 0, 0, 0), "ended")
    Set n = $CLASSMETHOD(rr, "InterruptOpen", "the test restarted")
    Do $$$AssertTrue(n >= 2, "the two open runs are interrupted (" _ n _ ")")
    Set a2 = $CLASSMETHOD(rr, "%OpenId", a.%Id()), b2 = $CLASSMETHOD(rr, "%OpenId", b.%Id()), c2 = $CLASSMETHOD(rr, "%OpenId", c.%Id())
    Do $$$AssertEquals(a2.State _ "|" _ b2.State _ "|" _ c2.State, "interrupted|interrupted|done", "open ones interrupted, the ended one untouched")
    Do $$$AssertEquals(a2.Error, "the test restarted", "with the reason")
    Do $$$AssertNotEquals(a2.EndedAt, "", "and an end time")
    Do $$$AssertEquals($CLASSMETHOD(rr, "InterruptOpen", "again"), 0, "nothing open any more")
    Set total = $CLASSMETHOD(rr, "Counts", .interrupted)
    Do $$$AssertTrue((total >= 3) && (interrupted >= 2), "the counts see them: " _ total _ " runs, " _ interrupted _ " interrupted")
}

Method TestStatusAndCandidates()
{
    Do ##class(Shutter.Operation.Releaser).Candidates(.waiting, .held)
    Do $$$AssertTrue((waiting ? 1.N) && (held ? 1.N), "the candidates are counts: " _ waiting _ " waiting, " _ held _ " held")
    Set s = ##class(Shutter.Operation.Releaser).Status()
    Do $$$AssertEquals(s.host, "Case Releaser", "named")
    For k = "started_at", "last_sweep_at", "sweeps", "last_run", "runs", "interrupted_runs", "candidates" {
        Do $$$AssertTrue(s.%IsDefined(k), "status has " _ k)
    }
    Do $$$AssertEquals(s.candidates.waiting _ "|" _ s.candidates.held, waiting _ "|" _ held, "with the same candidates")
    Do $$$AssertTrue((s.%GetTypeOf("last_run") = "object") || (s.%GetTypeOf("last_run") = "null"), "the last run is a row or null")
    Do $$$AssertEquals(##class(Shutter.Store.ReleaseRun).Prune(1000000), 0, "keeping a million rows deletes nothing")
}

}
