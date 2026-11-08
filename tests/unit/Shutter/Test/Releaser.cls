/// The Case Releaser's run rows (Shutter.Store.ReleaseRun; CONTRACTS 8.1, v1.35): begin and end, the interrupt at start,
/// the status, the candidates, the keep count, a sweep whose check throws, and the third pass, which judges the cases waiting on
/// the engine. The rows and the cases this test writes are deleted at the end.
Class Shutter.Test.Releaser Extends %UnitTest.TestCase
{

Parameter KEY = "PAS^HOSP^MRN-UT10^ENC-UT10^admit^2026-11-01T12:00:00Z";

Property Ids As %String [ MultiDimensional ];

Property CaseRowId As %String;

Property Made As %String [ MultiDimensional ];

Method OnAfterOneTest() As %Status
{
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ##class(Shutter.Store.Case).PurgeCase(id)
    }
    Kill i%Made
    Quit $$$OK
}

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
    // The production's own Case Releaser may open a run of its own at any moment, so the rows are compared by order, not
    // by being this test's.
    Set last = $CLASSMETHOD(rr, "Last")
    Do $$$AssertTrue(last.id >= failed.%Id(), "the last run is the newest row: " _ last.id _ " against " _ failed.%Id())
    If last.id = failed.%Id() Do $$$AssertEquals(last.state, "failed", "projected with its state")
    Do $$$AssertEquals(failed.Projection().state, "failed", "a run projects its state")
    Set recent = $CLASSMETHOD(rr, "Recent", 2)
    Do $$$AssertEquals(recent.%Size(), 2, "two recent rows asked for")
    Do $$$AssertTrue(recent.%Get(0).id > recent.%Get(1).id, "newest first: " _ recent.%Get(0).id _ " then " _ recent.%Get(1).id)
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

/// A case waiting on the engine, at a namespace no sweep can read, so the production's own Case Releaser leaves it alone.
Method WaitingCase(kind As %String = "delivery_failed", reasonCode As %String = "") As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-RELEASE-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.Releaser)
    Set case.Event = "transfer", case.FailureKind = kind, case.FailureReasonCode = reasonCode, case.FailureText = "made up", case.EncounterId = "ENC-UT2"
    Set case.PatientId = "MRN-UT2", case.PatientIdAuthority = "HOSP", case.Receiver = "UT Out", case.State = "blocked", case.Mode = "rules"
    Set case.OperationKey = "PAS^HOSP^MRN-UT2^ENC-UT2^transfer^" _ case.CaseId, case.Disposition = "resend"
    Set case.SourceNamespace = "UTNONE", case.OriginHeaderId = "16", case.WaitsOnEngine = "UTNONE:17"
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Do $$$AssertStatusOK(case.%Save(), "the case is saved")
    Set i%Made(case.%Id()) = ""
    Quit case
}

/// The gate's own row for a header in this state, as EngineWaitFacts takes it from EngineCheck.Row.
Method GateRow(custody As %String, ack As %String = "connection", reason As %String = "") As %DynamicObject
{
    Set facts = {"scope": "yes", "why": "", "namespace": "UTNONE", "item": "UT Out", "receiver": "UT Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": (custody), "status": "Completed", "itemStatus": "OK", "completedAt": "2026-11-07 03:12:01.123", "why": "", "attempts": ""}], "effectiveAck": (ack), "ackReason": (reason)}
    Quit ##class(Shutter.Util.EngineCheck).Judge(facts)
}

Method Delivered(ack As %String = "connection", reason As %String = "", checks As %DynamicArray = "") As %DynamicObject
{
    Quit {"answer": "delivered", "why": "", "row": (..GateRow("delivered", ack, reason)), "checks": ($SELECT($ISOBJECT(checks): checks, 1: []))}
}

Method Host() As Shutter.Test.FakeReleaser
{
    Quit ##class(Shutter.Test.FakeReleaser).%New("Case Releaser (unit test)")
}

Method Again(case As Shutter.Store.Case) As Shutter.Store.Case
{
    // The same object while the test holds it, so read again: a release clears the marker by SQL.
    Set again = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do again.%Reload()
    Quit again
}

Method TestCompletedResolvesWithTheSharedSentence()
{
    Set case = ..WaitingCase(), host = ..Host()
    Set releaser = "Shutter.Operation.Releaser"
    Do $$$AssertEquals($CLASSMETHOD(releaser, "ActOnEngineWait", case, ..Delivered(), host), "resolved", "resolved")
    Set after = ..Again(case)
    Do $$$AssertEquals(after.State, "resolved", "the case reads resolved")
    Do $$$AssertEquals(after.Outcome, ##class(Shutter.Util.EngineWords).DeliveredWords("17", "2026-11-07 03:12:01", "connection"), "Outcome is the shared sentence, which the gate's resolve writes too")
    Do $$$AssertEquals(after.Disposition, "resend", "the plan's disposition is unchanged")
    Do $$$AssertEquals(after.WaitsOnEngine, "", "the marker is cleared")
    Do $$$AssertEquals(host.Sent.Count(), 0, "and nothing is planned again")
    Do after.%JSONExportToString(.json)
    Do $$$AssertTrue(json '[ "Verified", "no Verified on the case")
}

Method TestDeclaredApplicationCarriesTheDeclaredWords()
{
    Set case = ..WaitingCase()
    Do $$$AssertEquals(##class(Shutter.Operation.Releaser).ActOnEngineWait(case, ..Delivered("application"), ..Host()), "resolved", "resolved")
    Do $$$AssertTrue(..Again(case).Outcome [ "accepted by the receiver's application (its ACK), as declared in the site profile", "the declared words: " _ ..Again(case).Outcome)
}

Method TestErrorReopensAndClears()
{
    Set case = ..WaitingCase(), host = ..Host()
    Do $$$AssertEquals(##class(Shutter.Operation.Releaser).ActOnEngineWait(case, {"answer": "settled", "why": ""}, host), "released", "released")
    Do $$$AssertEquals(host.Sent.Count(), 1, "one reinvestigation")
    Do $$$AssertTrue(host.Sent.GetAt(1) [ case.CaseId, "for this case: " _ host.Sent.GetAt(1))
    Set after = ..Again(case)
    Do $$$AssertEquals(after.WaitsOnEngine, "", "the marker is cleared, so the next sweep doesn't send it again")
    Do $$$AssertNotEquals(after.State, "resolved", "and it isn't resolved")
}

Method TestStillDeliveredIsLeft()
{
    Set case = ..WaitingCase(), host = ..Host(), marker = case.WaitsOnEngine
    Do $$$AssertEquals(##class(Shutter.Operation.Releaser).ActOnEngineWait(case, {"answer": "engine", "why": ""}, host), "left", "left")
    Set after = ..Again(case)
    Do $$$AssertEquals(after.State _ "|" _ after.WaitsOnEngine, "blocked|" _ marker, "still blocked, still waiting")
    Do $$$AssertEquals(host.Sent.Count(), 0, "nothing sent")
    // The marked header is Completed and another copy is still in the engine's hands: the gate's row says so, and it waits.
    Set facts = ..Delivered(), facts.row = ..GateRow("engine")
    Do $$$AssertEquals(##class(Shutter.Operation.Releaser).ActOnEngineWait(case, facts, host), "left", "a copy still with the engine waits too")
    Do $$$AssertEquals(..Again(case).State, "blocked", "still blocked")
}

Method TestAckCaseIsNotResolved()
{
    Set case = ..WaitingCase("delivery_failed", "ack_AE"), host = ..Host()
    Do $$$AssertEquals(##class(Shutter.Operation.Releaser).ActOnEngineWait(case, ..Delivered(), host), "released", "released, not resolved")
    Set after = ..Again(case)
    Do $$$AssertNotEquals(after.State, "resolved", "not resolved")
    Do $$$AssertEquals(after.WaitsOnEngine, "", "the marker is cleared")
    Do $$$AssertEquals(after.Outcome, "", "and no delivered words on it")
    Do $$$AssertEquals(host.Sent.Count(), 1, "planned again")
}

Method TestNotEstablishedIsNotResolved()
{
    Set case = ..WaitingCase(), host = ..Host()
    Do $$$AssertEquals(##class(Shutter.Operation.Releaser).ActOnEngineWait(case, ..Delivered("not_established", ":?E=C"), host), "stopped", "stopped")
    Set after = ..Again(case)
    Do $$$AssertEquals(after.State, "blocked", "blocked for a person")
    Do $$$AssertEquals(after.WaitsOnEngine, "", "the marker is cleared")
    Do $$$AssertTrue(after.Outcome [ "Receiver acceptance has not been established.", "the words: " _ after.Outcome)
    Do $$$AssertTrue(after.Headline [ "Stopped for a person", "the headline: " _ after.Headline)
    Do $$$AssertEquals(host.Sent.Count(), 0, "nothing planned again: the gate would say the same")
}

/// As at the gate: a Completed header doesn't settle a refusal or an identity conflict.
Method TestWhatCompletedCantClose()
{
    Set case = ..WaitingCase("rejected")
    Do $$$AssertEquals(##class(Shutter.Operation.Releaser).ActOnEngineWait(case, ..Delivered(), ..Host()), "stopped", "a refusal stays with a person")
    Do $$$AssertEquals(..Again(case).State, "blocked", "blocked")
    Set case = ..WaitingCase()
    Set checks = [{"check": "identity", "result": "block", "reason_code": "PATIENT_MISMATCH", "detail": "made up"}]
    Do $$$AssertEquals(##class(Shutter.Operation.Releaser).ActOnEngineWait(case, ..Delivered(, , checks), ..Host()), "stopped", "an identity conflict too")
    Do $$$AssertEquals(..Again(case).State, "blocked", "blocked")
}

/// The whole pass, reading for real: nothing can be read at a namespace that doesn't exist, so the case is left and counted,
/// and the count is in the object the Doctor prints as release_sweep.
Method TestUnreadableIsLeftAndCounted()
{
    Set case = ..WaitingCase(), host = ..Host(), marker = case.WaitsOnEngine
    Do ##class(Shutter.Operation.Releaser).Candidates(.waiting, .held, .engine)
    Do $$$AssertTrue(engine >= 1, "the sweep counts it as a candidate: " _ engine)
    Do ##class(Shutter.Operation.Releaser).ReleaseEngineWaits(host, "Case Workflow", .checked, .unreadable)
    Do $$$AssertTrue(checked >= 1, "looked at: " _ checked)
    Do $$$AssertTrue(unreadable >= 1, "unreadable: " _ unreadable)
    Set status = ##class(Shutter.Operation.Releaser).Status()
    Do $$$AssertTrue(status."engine_unreadable" >= 1, "Status counts it: " _ status.%ToJSON())
    Do $$$AssertTrue(status.candidates.engine >= 1, "and the candidates")
    Set after = ..Again(case)
    Do $$$AssertEquals(after.State _ "|" _ after.WaitsOnEngine, "blocked|" _ marker, "left as it was")
    Do $$$AssertEquals(host.Sent.Count(), 0, "with nothing sent")
    // Other unreadable waits on the instance count too, so the count is read again without this one: exactly one fewer.
    Set after.State = "failed"
    Do $$$AssertStatusOK(after.%Save(), "taken out of the sweep")
    Do ##class(Shutter.Operation.Releaser).ReleaseEngineWaits(host, "Case Workflow", .checked2, .unreadable2)
    Do $$$AssertEquals(unreadable - unreadable2, 1, "this case is exactly one of the count: " _ unreadable _ " then " _ unreadable2)
    Do $$$AssertEquals(checked - checked2, 1, "and one of those looked at")
}

/// A sweep whose checks throw before the third has read the waits on the engine counts every one of them as unread, rather
/// than keeping an earlier sweep's count.
Method TestAThrownSweepCountsItsWaitsUnread()
{
    Set case = ..WaitingCase()
    Set ^Shutter.Release("engine_unreadable") = 0
    Set host = ..Host(), host.ThrowInChecks = "the lookup threw (unit test)"
    Set edge = ..LastRunId()
    Do $$$AssertStatusOK(host.Sweep(), "the sweep answers ok to the adapter")
    Set run = ..RunByThisJobAfter(edge)
    Do $$$AssertTrue($ISOBJECT(run), "it wrote a run row, since the case is a candidate")
    If $ISOBJECT(run) Do ..Keep(run)
    Do $$$AssertTrue(+$GET(^Shutter.Release("engine_unreadable")) >= 1, "the unread wait is counted: " _ $GET(^Shutter.Release("engine_unreadable")))
    Do $$$AssertEquals(..Again(case).State, "blocked", "and the case is left")
}

/// A release reopens every blocked case waiting on the header, and never an escalated one: that is a person's, and its
/// marker is dropped so no later sweep reopens it either.
Method TestAnEscalatedSiblingIsNotReopened()
{
    Set case = ..WaitingCase(), sibling = ..WaitingCase(), person = ..WaitingCase(), host = ..Host()
    Set person.State = "escalated"
    Do $$$AssertStatusOK(person.%Save(), "one escalated by a person")
    Do $$$AssertEquals(##class(Shutter.Operation.Releaser).ActOnEngineWait(case, {"answer": "settled", "why": ""}, host), "released", "released")
    Set sent = " "
    For i = 1:1:host.Sent.Count() Set sent = sent _ $PIECE(host.Sent.GetAt(i), "|", 2) _ " "
    Do $$$AssertEquals(host.Sent.Count(), 2, "two reinvestigations: " _ sent)
    Do $$$AssertTrue((sent [ (" " _ case.CaseId _ " ")) && (sent [ (" " _ sibling.CaseId _ " ")), "the case and its blocked sibling: " _ sent)
    Do $$$AssertTrue(sent '[ (" " _ person.CaseId _ " "), "not the escalated one")
    Set after = ..Again(person)
    Do $$$AssertEquals(after.State _ "|" _ after.WaitsOnEngine, "escalated|", "which stays escalated, with no marker")
    Do $$$AssertEquals(..Again(sibling).WaitsOnEngine, "", "the sibling's marker is cleared")
}

Method TestAMarkerNamingNoHeaderIsUnreadable()
{
    Set case = ..WaitingCase()
    Set case.WaitsOnEngine = "UTNONE"
    Set facts = ##class(Shutter.Operation.Releaser).EngineWaitFacts(case)
    Do $$$AssertEquals(facts.answer, "unreadable", facts.%ToJSON())
    Set case.WaitsOnEngine = "UTNONE:17"
    Do $$$AssertEquals(##class(Shutter.Operation.Releaser).EngineWaitFacts(case).answer, "unreadable", "and a namespace that doesn't exist")
}

Method TestBlockingChecksAreTheLatestDecisions()
{
    Set case = ..WaitingCase()
    Do $$$AssertTrue(##class(Shutter.Operation.Releaser).BlockingChecks(case, .checks), "no decision reads as no rows")
    Do $$$AssertEquals(checks.%Size(), 0, "none")
    Set rows = [{"check": "identity", "result": "block", "reason_code": "PATIENT_MISMATCH", "detail": "made up"}]
    Do $$$AssertStatusOK(##class(Shutter.Store.GateDecision).Create(case, "", "proposal", "t", "block", rows, "made up", .d), "a decision")
    Do $$$AssertStatusOK(##class(Shutter.Store.GateDecision).Create(case, "", "proposal", "t", "pass", [], "made up", .d2), "a later one that passed")
    Do $$$AssertTrue(##class(Shutter.Operation.Releaser).BlockingChecks(case, .checks), "reads")
    Do $$$AssertEquals(checks.%Get(0)."reason_code", "PATIENT_MISMATCH", "the rows of the one that blocked")
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
