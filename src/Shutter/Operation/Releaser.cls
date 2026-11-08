/// The Case Releaser (CONTRACTS 8.1, v1.35): the one host that releases the cases no other host can. Three kinds wait on
/// something outside Shutter's own feed: a case blocked or escalated while a newer message of its encounter was in
/// flight at a watched production (waitsOnMessage; that production's connector knows nothing of Shutter, so nobody
/// tells the case when the message lands), a case held for a schema that was not loaded when its message was read
/// (heldSchema), and a case blocked while the engine was still trying its message (waitsOnEngine). Each sweep counts the
/// candidates first; when there are any it opens a run row (Shutter.Store.ReleaseRun), runs the three checks, which send
/// each release to the Case Workflow as an id-only Shutter.Msg.Reinvestigate from this host (the third can also resolve
/// a case the engine delivered), and ends the row: this host is the one writer that ends a run. A quiet
/// sweep writes no row, only its time. At start every run still open is marked interrupted, since the host starting
/// again means a restart cut it. Until v1.35 the HL7 Index adapter's task ran the two checks beside its walk; now the
/// adapter only reads.
Class Shutter.Operation.Releaser Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Property Adapter As Ens.InboundAdapter;

/// The Case Workflow item that reinvestigates a released case.
Property WorkflowTarget As %String(MAXLEN = 128) [ InitialExpression = "Case Workflow" ];

/// How many run rows are kept (the newest).
Property KeepRuns As %Integer [ InitialExpression = 500 ];

Parameter SETTINGS = "WorkflowTarget:Targets,KeepRuns:Runs";

/// Set when this sweep's third check has read every wait on the engine, so a check that throws before it leaves no count
/// from an earlier sweep.
Property EngineSwept As %Boolean [ InitialExpression = 0, Transient ];

Method OnInit() As %Status
{
    Set n = ##class(Shutter.Store.ReleaseRun).InterruptOpen("the Case Releaser started while this run was open: a restart cut it")
    If n > 0 $$$LOGINFO("Marked " _ n _ " release run(s) left open as interrupted")
    Set ^Shutter.Release("started_at") = ##class(Shutter.Util.Time).NowUTC()
    Quit ##super()
}

/// Each call of the adapter: one sweep.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    // The Doctor's credential checks are kept fresh from here (v1.38): this sweep runs every few seconds as the production's
    // user, which may write the cache; a request with no roles only reads it. Recomputed only when older than ten minutes.
    Do ##class(Shutter.Setup).RefreshCredentialCache()
    Set pOutput = ""
    Quit ..Sweep()
}

/// The cases a sweep would look at: waiting on a message, held for a schema, and waiting on the engine.
ClassMethod Candidates(Output waiting As %Integer, Output held As %Integer, Output engine As %Integer)
{
    Set waiting = 0, held = 0, engine = 0
    &sql(SELECT COUNT(*) INTO :waiting FROM Shutter_Store."Case" WHERE WaitsOnMessage <> '' AND State IN ('blocked', 'escalated'))
    If SQLCODE '= 0 Set waiting = 0
    &sql(SELECT COUNT(*) INTO :held FROM Shutter_Store."Case" WHERE FailureKind = 'unreadable' AND HeldSchema <> '' AND State IN ('blocked', 'escalated'))
    If SQLCODE '= 0 Set held = 0
    &sql(SELECT COUNT(*) INTO :engine FROM Shutter_Store."Case" WHERE WaitsOnEngine <> '' AND State = 'blocked')
    If SQLCODE '= 0 Set engine = 0
}

/// One sweep: the candidates, and when there are any a run row around the three checks. Never an error for the adapter:
/// a check that throws ends the run as failed, with the error on the row (the counts as far as the checks got) and a
/// warning in the event log; since v1.39 the checks throw their errors instead of answering a partial count.
Method Sweep() As %Status
{
    Set ^Shutter.Release("last_sweep_at") = ##class(Shutter.Util.Time).NowUTC()
    If $INCREMENT(^Shutter.Release("sweeps"))
    Do ..Candidates(.waiting, .held, .engine)
    If engine = 0 Set ^Shutter.Release("engine_unreadable") = 0
    If (waiting = 0) && (held = 0) && (engine = 0) Quit $$$OK
    Set sc = ##class(Shutter.Store.ReleaseRun).Begin(.run)
    If $$$ISERR(sc) { $$$LOGWARNING("A release run could not be opened: " _ $SYSTEM.Status.GetErrorText(sc)) Quit $$$OK }
    Set error = "", wc = 0, wr = 0, hc = 0, hr = 0, ..EngineSwept = 0
    Try {
        Do ..Checks(.wc, .wr, .hc, .hr)
    } Catch ex {
        Set error = ex.DisplayString()
    }
    // The third check never finished, so none of this sweep's waits on the engine was read.
    If '..EngineSwept Set ^Shutter.Release("engine_unreadable") = engine
    Set sc = run.End(wc, wr, hc, hr, error)
    If $$$ISERR(sc) $$$LOGWARNING("Release run " _ run.%Id() _ " could not be ended: " _ $SYSTEM.Status.GetErrorText(sc))
    If error '= "" $$$LOGWARNING("Release run " _ run.%Id() _ " failed: " _ error)
    If (wr + hr) > 0 $$$LOGINFO("Release run " _ run.%Id() _ ": " _ wr _ " of " _ wc _ " waiting and " _ hr _ " of " _ hc _ " held case(s) released")
    Set ^Shutter.Release("last_run_id") = run.%Id()
    Do ##class(Shutter.Store.ReleaseRun).Prune(..KeepRuns)
    Quit $$$OK
}

/// The three checks of a run, in order, each sending its releases from this host: the delivered waits
/// (Shutter.Util.ResendGuard), the held cases (Shutter.Util.Schemas), then the waits on the engine, which count with the
/// waiting cases on the run's row. The counts are written as the checks go, so a check that throws leaves them as far as it
/// got, and Sweep records the error on the run.
Method Checks(Output waitingChecked As %Integer, Output waitingReleased As %Integer, Output heldChecked As %Integer, Output heldReleased As %Integer)
{
    Set waitingReleased = ##class(Shutter.Util.ResendGuard).ReleaseDeliveredWaits($THIS, ..WorkflowTarget, .waitingChecked)
    Set heldReleased = ##class(Shutter.Util.Schemas).ReleaseHeld($THIS, ..WorkflowTarget, .heldChecked)
    Set released = ..ReleaseEngineWaits($THIS, ..WorkflowTarget, .engineChecked)
    Set ..EngineSwept = 1
    Set waitingChecked = waitingChecked + engineChecked, waitingReleased = waitingReleased + released
}

/// The third check: every case blocked while the engine was still trying its message, judged on the marked header as it
/// reads now. Returns how many left the wait, resolved or sent to be planned again. How many could not be read is kept for
/// Status, for this sweep alone. One case that throws counts as unreadable and doesn't stop the others.
ClassMethod ReleaseEngineWaits(host As Ens.Host = "", target As %String = "Case Workflow", Output checked As %Integer, Output unreadable As %Integer) As %Integer
{
    Set n = 0, checked = 0, unreadable = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.""Case"" WHERE WaitsOnEngine <> '' AND State = 'blocked' ORDER BY ID")
    While rs.%Next() {
        Set case = ##class(Shutter.Store.Case).%OpenId(rs.%Get("ID"))
        // Released with an earlier case on the same header, or moved on since the list was read.
        Continue:'$ISOBJECT(case)
        Continue:(case.WaitsOnEngine = "")||(case.State '= "blocked")
        Set checked = checked + 1
        Try {
            Set did = ..ActOnEngineWait(case, ..EngineWaitFacts(case), host, target)
        } Catch ex {
            Set did = "unreadable"
            $$$LOGWARNING("Case " _ case.CaseId _ ": its wait on the engine could not be judged: " _ ex.DisplayString())
        }
        If did = "unreadable" Set unreadable = unreadable + 1
        If (did = "resolved") || (did = "stopped") || (did = "released") Set n = n + 1
    }
    Set ^Shutter.Release("engine_unreadable") = unreadable
    Quit n
}

/// What the engine shows for the marked header: { "answer": "engine|delivered|settled|unreadable", "why", "row", "checks" }.
/// For a delivered header on a case Completed can speak for, row is the gate's own judgement of the case as it reads now, whose
/// words hold the receiver's declared level against the item's reply settings, so a case reads one way whichever writer
/// resolved it, and checks are the gate's rows from when it blocked the case.
ClassMethod EngineWaitFacts(case As Shutter.Store.Case) As %DynamicObject
{
    Set facts = {"answer": "unreadable", "why": "", "row": null, "checks": null}
    Set ns = $PIECE(case.WaitsOnEngine, ":", 1), header = $PIECE(case.WaitsOnEngine, ":", 2, *)
    If (ns = "") || (header '? 1.N) {
        Set facts.why = "the marker names no header: " _ case.WaitsOnEngine
        Quit facts
    }
    Set item = ##class(Shutter.Util.EngineScope).ItemOf(ns, case)
    Set custody = ##class(Shutter.Util.EngineRead).Custody(ns, item, header)
    Set facts.answer = custody.answer, facts.why = custody.why
    If (custody.answer '= "delivered") || ##class(Shutter.Util.EngineCheck).AckRoute(case) Quit facts
    Set facts.row = ##class(Shutter.Util.EngineCheck).Row(case)
    Set read = ..BlockingChecks(case, .checks)
    If 'read {
        Set facts.answer = "unreadable", facts.why = "the gate's rows on this case could not be read"
        Quit facts
    }
    Set facts.checks = checks
    Quit facts
}

/// The rows of the gate's latest decision that didn't pass on this case. False when they can't be read.
ClassMethod BlockingChecks(case As Shutter.Store.Case, Output checks As %DynamicArray) As %Boolean
{
    Set checks = "", caseRow = case.%Id(), did = ""
    &sql(SELECT TOP 1 ID INTO :did FROM Shutter_Store.GateDecision WHERE "Case" = :caseRow AND Outcome <> 'pass' ORDER BY ID DESC)
    If SQLCODE = 100 {
        Set checks = []
        Quit 1
    }
    If SQLCODE '= 0 Quit 0
    Set decision = ##class(Shutter.Store.GateDecision).%OpenId(did)
    If '$ISOBJECT(decision) Quit 0
    Set checks = ##class(Shutter.Util.Json).Parse(decision.ChecksJSON, .psc)
    Quit $ISOBJECT(checks) && checks.%IsA("%Library.DynamicArray")
}

/// What the read means for the case, and what was done: left (the engine still has it, or a copy of it), unreadable (left too,
/// and counted), resolved (the engine delivered it, in EngineCheck.Settle's words), stopped (Completed can't speak for this
/// case, so it stays blocked for a person, with the words), or released (marker cleared and planned again). An application-ACK
/// case marked by a sibling's wait is released, never resolved: a Completed header says nothing of the application's refusal.
ClassMethod ActOnEngineWait(case As Shutter.Store.Case, facts As %DynamicObject, host As Ens.Host = "", target As %String = "Case Workflow") As %String
{
    If facts.answer = "engine" Quit "left"
    If facts.answer = "unreadable" Quit "unreadable"
    If (facts.answer = "settled") || ##class(Shutter.Util.EngineCheck).AckRoute(case) Quit ..ReleaseEngineWait(case, host, target)
    Set row = facts.row
    Set code = $SELECT($ISOBJECT(row): ##class(Shutter.Util.Json).Str(row, "reason_code"), 1: "")
    If code = "ENGINE_STILL_TRYING" Quit "left"
    If (code = "") || (code = "ENGINE_UNREADABLE") Quit "unreadable"
    If code '= "ENGINE_DELIVERED" Quit ..ReleaseEngineWait(case, host, target)
    Set case.WaitsOnEngine = ""
    Set sc = ##class(Shutter.Util.EngineCheck).Settle(case, row, facts.checks, "release:" _ case.CaseId)
    If $$$ISERR(sc) {
        // A stale copy changes nothing: the next sweep reads the case again.
        $$$LOGWARNING("Case " _ case.CaseId _ ": the engine's delivery could not be recorded: " _ $SYSTEM.Status.GetErrorText(sc))
        Quit "left"
    }
    Quit $SELECT(case.State = "resolved": "resolved", 1: "stopped")
}

/// Plans the case again on fresh evidence, where the gate's own checks apply, with every other blocked case waiting on the
/// same header, and clears their marker with NULL as ReleaseHeld does its field, so this sweep's release is the only one.
/// An escalated case is a person's: its marker is dropped first, so the release never reopens it, and the case stays as
/// they left it. When a send fails the markers stay, so the next sweep tries the case that didn't go (a case that did go
/// has its marker cleared by its reopening).
ClassMethod ReleaseEngineWait(case As Shutter.Store.Case, host As Ens.Host, target As %String) As %String
{
    Set key = case.WaitsOnEngine, expected = 0
    &sql(UPDATE Shutter_Store."Case" SET WaitsOnEngine = NULL WHERE WaitsOnEngine = :key AND State = 'escalated')
    &sql(SELECT COUNT(*) INTO :expected FROM Shutter_Store."Case" WHERE WaitsOnEngine = :key AND State = 'blocked')
    If SQLCODE '= 0 Set expected = 0
    Set n = ##class(Shutter.Store.Case).ReleaseWaitingOnEngine(key, host, target)
    If n = 0 Quit "left"
    If n < expected {
        $$$LOGWARNING("Header " _ key _ ": " _ n _ " of " _ expected _ " case(s) waiting on it were sent to be planned again; the rest are tried on the next sweep")
        Quit "released"
    }
    &sql(UPDATE Shutter_Store."Case" SET WaitsOnEngine = NULL WHERE WaitsOnEngine = :key AND State = 'blocked')
    Quit "released"
}

/// The releaser's state, for GET /index and the Doctor: when it started and last swept, how many sweeps, the last run
/// with candidates (null when none yet), the run counts, the candidates, and how many waits on the engine the last sweep could
/// not read: each is left blocked until the engine's record reads again or a person reopens it.
ClassMethod Status() As %DynamicObject
{
    Set o = {}
    Set o.host = "Case Releaser"
    Set o."started_at" = $GET(^Shutter.Release("started_at")), o."last_sweep_at" = $GET(^Shutter.Release("last_sweep_at"))
    Set o.sweeps = +$GET(^Shutter.Release("sweeps"))
    Set last = ##class(Shutter.Store.ReleaseRun).Last()
    If $ISOBJECT(last) { Set o."last_run" = last } Else { Do o.%Set("last_run", "", "null") }
    Set o.runs = ##class(Shutter.Store.ReleaseRun).Counts(.interrupted), o."interrupted_runs" = +interrupted
    Do ..Candidates(.waiting, .held, .engine)
    Set o.candidates = {"waiting": (waiting), "held": (held), "engine": (engine)}
    Set o."engine_unreadable" = +$GET(^Shutter.Release("engine_unreadable"))
    Quit o
}

}
