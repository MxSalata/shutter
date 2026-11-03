/// The Case Releaser's run rows (Shutter.Store.ReleaseRun; CONTRACTS 8.1, v1.35): begin and end, the interrupt at start,
/// the status, the candidates, the keep count, and a sweep whose check throws. The rows and the case this test writes are
/// deleted at the end.
Class Shutter.Test.Releaser Extends %UnitTest.TestCase
{

Parameter KEY = "PAS^HOSP^MRN-UT10^ENC-UT10^admit^2026-11-01T12:00:00Z";

Property Ids As %String [ MultiDimensional ];

Property CaseRowId As %String;

Method OnAfterAllTests() As %Status
{
    Set id = ""
    For {
        Set id = $ORDER(..Ids(id)) Quit:id=""
        Do ##class(Shutter.Store.ReleaseRun).%DeleteId(id)
    }
    If ..CaseRowId '= "" {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", ..CaseRowId)
        Kill ^Shutter.Counter("event", ..CaseRowId)
        If ##class(Shutter.Store.Case).%ExistsId(..CaseRowId) Do ##class(Shutter.Store.Case).%DeleteId(..CaseRowId)
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

/// A sweep whose check throws ends its run failed, with the error's text on the row, and answers the adapter ok; a sweep
/// whose checks run ends its run done. The sweep needs a candidate to open a run, so a case held for a schema that is not
/// loaded is opened first; the production's own Case Releaser may sweep it too, so the rows are found by this job. The
/// second sweep runs the real checks through the fake host over every candidate of the instance, and the fake host
/// answers a release without queueing it, so it is tried only when this test's case is the instance's one candidate.
Method TestACheckThatThrowsFailsTheRun()
{
    Set op = {"operation_key": (..#KEY), "encounter_id": "ENC-UT10", "patient_id": "MRN-UT10", "patient_id_authority": "HOSP", "event": "admit", "ward": "WARD-A", "bed": null, "event_time": "2026-11-01T12:00:00Z", "source_system": "PAS", "source_message_id": "UT10", "payload_digest": "sha256:ut10"}
    Set sc = ##class(Shutter.Store.Case).Open(op, "unreadable", "Held: the schema MYSITE_2.5.1 is not loaded here", "", "", "policy", .case, .opened, "", "MYSITE_2.5.1")
    Do $$$AssertStatusOK(sc, "a held case opens, the sweep's candidate")
    Set ..CaseRowId = case.%Id()
    Set case.State = "blocked"
    Do $$$AssertStatusOK(case.%Save(), "saved as blocked")
    Do ##class(Shutter.Operation.Releaser).Candidates(.waiting, .held)
    Do $$$AssertTrue(held >= 1, "the sweep has a candidate: " _ held _ " held")
    Set host = ##class(Shutter.Test.FakeReleaser).%New("Case Releaser (unit test)")
    Set host.ThrowInChecks = "the lookup threw (unit test)"
    Set edge = ..LastRunId()
    Do $$$AssertStatusOK(host.Sweep(), "the sweep answers ok to the adapter")
    Set run = ..RunByThisJobAfter(edge)
    Do $$$AssertTrue($ISOBJECT(run), "the sweep wrote a run row")
    Quit:'$ISOBJECT(run)
    Do ..Keep(run)
    Do $$$AssertEquals(run.State, "failed", "the run failed")
    Do $$$AssertTrue(run.Error [ "the lookup threw (unit test)", "with the error's text: " _ run.Error)
    Do $$$AssertNotEquals(run.EndedAt, "", "and an end time")
    Set host.ThrowInChecks = ""
    Do ##class(Shutter.Operation.Releaser).Candidates(.waiting, .held)
    If (waiting '= 0) || (held '= 1) {
        Do $$$LogMessage("the instance has candidates of its own (" _ waiting _ " waiting, " _ held _ " held): the sweep whose checks run is not tried here, since the fake host would release them without a reinvestigation")
        Quit
    }
    Set edge = ..LastRunId()
    Do $$$AssertStatusOK(host.Sweep(), "a sweep whose checks run")
    Set run = ..RunByThisJobAfter(edge)
    Do $$$AssertTrue($ISOBJECT(run), "wrote a run row")
    Quit:'$ISOBJECT(run)
    Do ..Keep(run)
    Do $$$AssertEquals(run.State _ "|" _ run.Error, "done|", "that ended done")
    Do $$$AssertTrue((run.HeldChecked >= 1) && (run.HeldReleased = 0), "it looked at the held case and left it held, since its schema is still missing: " _ run.HeldChecked _ " checked")
    Do $$$AssertEquals(host.Sent.Count(), 0, "and sent nothing")
}

/// The newest run row's id, or 0.
Method LastRunId() As %Integer
{
    Set id = 0
    &sql(SELECT TOP 1 ID INTO :id FROM Shutter_Store.ReleaseRun ORDER BY ID DESC)
    Quit $SELECT(SQLCODE = 0: +id, 1: 0)
}

/// The newest run row this job wrote after the given id, or "".
Method RunByThisJobAfter(edge As %Integer) As Shutter.Store.ReleaseRun
{
    Set id = "", job = $JOB
    &sql(SELECT TOP 1 ID INTO :id FROM Shutter_Store.ReleaseRun WHERE Job = :job AND ID > :edge ORDER BY ID DESC)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ##class(Shutter.Store.ReleaseRun).%OpenId(id)
}

}
