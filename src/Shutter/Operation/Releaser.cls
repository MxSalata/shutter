/// The Case Releaser (CONTRACTS 8.1, v1.35): the one host that releases the cases no other host can. Two kinds wait on
/// something outside Shutter's own feed: a case blocked or escalated while a newer message of its encounter was in
/// flight at a watched production (waitsOnMessage; that production's connector knows nothing of Shutter, so nobody
/// tells the case when the message lands), and a case held for a schema that was not loaded when its message was read
/// (heldSchema). Each sweep counts the candidates first; when there are any it opens a run row
/// (Shutter.Store.ReleaseRun), runs the two checks, which send each release to the Case Workflow as an id-only
/// Shutter.Msg.Reinvestigate from this host, and ends the row: this host is the one writer that ends a run. A quiet
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

/// The cases a sweep would look at: waiting on a message, and held for a schema.
ClassMethod Candidates(Output waiting As %Integer, Output held As %Integer)
{
    Set waiting = 0, held = 0
    &sql(SELECT COUNT(*) INTO :waiting FROM Shutter_Store."Case" WHERE WaitsOnMessage <> '' AND State IN ('blocked', 'escalated'))
    If SQLCODE '= 0 Set waiting = 0
    &sql(SELECT COUNT(*) INTO :held FROM Shutter_Store."Case" WHERE FailureKind = 'unreadable' AND HeldSchema <> '' AND State IN ('blocked', 'escalated'))
    If SQLCODE '= 0 Set held = 0
}

/// One sweep: the candidates, and when there are any a run row around the two checks. Never an error for the adapter:
/// a check that fails ends the run as failed, with the error on the row and a warning in the event log.
Method Sweep() As %Status
{
    Set ^Shutter.Release("last_sweep_at") = ##class(Shutter.Util.Time).NowUTC()
    If $INCREMENT(^Shutter.Release("sweeps"))
    Do ..Candidates(.waiting, .held)
    If (waiting = 0) && (held = 0) Quit $$$OK
    Set sc = ##class(Shutter.Store.ReleaseRun).Begin(.run)
    If $$$ISERR(sc) { $$$LOGWARNING("A release run could not be opened: " _ $SYSTEM.Status.GetErrorText(sc)) Quit $$$OK }
    Set error = "", wc = 0, wr = 0, hc = 0, hr = 0
    Try {
        Set wr = ##class(Shutter.Util.ResendGuard).ReleaseDeliveredWaits($THIS, ..WorkflowTarget, .wc)
        Set hr = ##class(Shutter.Util.Schemas).ReleaseHeld($THIS, ..WorkflowTarget, .hc)
    } Catch ex {
        Set error = ex.DisplayString()
    }
    Set sc = run.End(wc, wr, hc, hr, error)
    If $$$ISERR(sc) $$$LOGWARNING("Release run " _ run.%Id() _ " could not be ended: " _ $SYSTEM.Status.GetErrorText(sc))
    If error '= "" $$$LOGWARNING("Release run " _ run.%Id() _ " failed: " _ error)
    If (wr + hr) > 0 $$$LOGINFO("Release run " _ run.%Id() _ ": " _ wr _ " of " _ wc _ " waiting and " _ hr _ " of " _ hc _ " held case(s) released")
    Set ^Shutter.Release("last_run_id") = run.%Id()
    Do ##class(Shutter.Store.ReleaseRun).Prune(..KeepRuns)
    Quit $$$OK
}

/// The releaser's state, for GET /index and the Doctor: when it started and last swept, how many sweeps, the last run
/// with candidates (null when none yet), and the run counts.
ClassMethod Status() As %DynamicObject
{
    Set o = {}
    Set o.host = "Case Releaser"
    Set o."started_at" = $GET(^Shutter.Release("started_at")), o."last_sweep_at" = $GET(^Shutter.Release("last_sweep_at"))
    Set o.sweeps = +$GET(^Shutter.Release("sweeps"))
    Set last = ##class(Shutter.Store.ReleaseRun).Last()
    If $ISOBJECT(last) { Set o."last_run" = last } Else { Do o.%Set("last_run", "", "null") }
    Set o.runs = ##class(Shutter.Store.ReleaseRun).Counts(.interrupted), o."interrupted_runs" = +interrupted
    Do ..Candidates(.waiting, .held)
    Set o.candidates = {"waiting": (waiting), "held": (held)}
    Quit o
}

}
