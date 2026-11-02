/// One sweep of the Case Releaser (CONTRACTS 8.1, v1.35) that had candidates: when it began and ended, what it checked
/// and what it released, and how it ended (done, failed, or interrupted when the host started again while the row was
/// still open). The Releaser is the one writer that ends a run; a quiet sweep writes no row.
Class Shutter.Store.ReleaseRun Extends (%Persistent, %JSON.Adaptor)
{

Property StartedAt As %String(%JSONFIELDNAME = "startedAt", MAXLEN = 30);

Index StartedIdx On StartedAt;

Property EndedAt As %String(%JSONFIELDNAME = "endedAt", MAXLEN = 30);

Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 16, VALUELIST = ",running,done,failed,interrupted");

Index StateIdx On State;

/// Cases waiting on a message (blocked or escalated with waitsOnMessage) the sweep looked at, and how many it released.
Property WaitingChecked As %Integer(%JSONFIELDNAME = "waitingChecked") [ InitialExpression = 0 ];

Property WaitingReleased As %Integer(%JSONFIELDNAME = "waitingReleased") [ InitialExpression = 0 ];

/// Cases held for a schema the sweep looked at, and how many it released.
Property HeldChecked As %Integer(%JSONFIELDNAME = "heldChecked") [ InitialExpression = 0 ];

Property HeldReleased As %Integer(%JSONFIELDNAME = "heldReleased") [ InitialExpression = 0 ];

Property Error As %String(%JSONFIELDNAME = "error", MAXLEN = 2000);

/// The job that ran the sweep.
Property Job As %String(%JSONFIELDNAME = "job", MAXLEN = 20);

/// Open a run: running, from now.
ClassMethod Begin(Output run As Shutter.Store.ReleaseRun) As %Status
{
    Set run = ..%New()
    Set run.StartedAt = ##class(Shutter.Util.Time).NowUTC(), run.State = "running", run.Job = $JOB
    Quit run.%Save()
}

/// End a run with its counts: done, or failed when an error is given.
Method End(waitingChecked As %Integer, waitingReleased As %Integer, heldChecked As %Integer, heldReleased As %Integer, error As %String = "") As %Status
{
    Set ..WaitingChecked = +waitingChecked, ..WaitingReleased = +waitingReleased
    Set ..HeldChecked = +heldChecked, ..HeldReleased = +heldReleased
    Set ..Error = $EXTRACT(error, 1, 2000)
    Set ..EndedAt = ##class(Shutter.Util.Time).NowUTC(), ..State = $SELECT(error '= "": "failed", 1: "done")
    Quit ..%Save()
}

/// Every run still open is marked interrupted with the reason: the host starting again means a restart cut them.
/// Returns how many.
ClassMethod InterruptOpen(why As %String = "the Case Releaser started while this run was open") As %Integer
{
    Set n = 0
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.ReleaseRun WHERE State = 'running' ORDER BY ID")
        While rs.%Next() {
            Set run = ..%OpenId(rs.%Get("ID"))
            Continue:'$ISOBJECT(run)
            Set run.State = "interrupted", run.EndedAt = ##class(Shutter.Util.Time).NowUTC(), run.Error = $EXTRACT(why, 1, 2000)
            If $$$ISOK(run.%Save()) Set n = n + 1
        }
    } Catch ex {
    }
    Quit n
}

/// Keep the newest rows only. Returns how many were deleted.
ClassMethod Prune(keep As %Integer = 500) As %Integer
{
    Set n = 0
    If keep < 1 Set keep = 1
    Try {
        Set edge = "", k = +keep
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM (SELECT TOP ? ID FROM Shutter_Store.ReleaseRun ORDER BY ID DESC) ORDER BY ID", k)
        If rs.%Next() Set edge = rs.%Get("ID")
        If edge '= "" {
            &sql(DELETE FROM Shutter_Store.ReleaseRun WHERE ID < :edge)
            If SQLCODE = 0 Set n = %ROWCOUNT
        }
    } Catch ex {
    }
    Quit n
}

/// The newest run as JSON, or "" when there is none.
ClassMethod Last() As %DynamicObject
{
    Set id = ""
    &sql(SELECT TOP 1 ID INTO :id FROM Shutter_Store.ReleaseRun ORDER BY ID DESC)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Set run = ..%OpenId(id)
    Quit $SELECT($ISOBJECT(run): run.Projection(), 1: "")
}

/// The newest runs, newest first.
ClassMethod Recent(n As %Integer = 20) As %DynamicArray
{
    Quit ##class(Shutter.Util.Json).Rows("Shutter.Store.ReleaseRun", "SELECT TOP ? ID FROM Shutter_Store.ReleaseRun ORDER BY ID DESC", +n)
}

/// How many runs there are, and how many ended interrupted.
ClassMethod Counts(Output interrupted As %Integer) As %Integer
{
    Set total = 0, interrupted = 0
    &sql(SELECT COUNT(*), SUM(CASE WHEN State = 'interrupted' THEN 1 ELSE 0 END) INTO :total, :interrupted FROM Shutter_Store.ReleaseRun)
    Quit +total
}

/// The row as JSON with its id.
Method Projection() As %DynamicObject
{
    Quit ##class(Shutter.Util.Json).Project($THIS)
}

Storage Default
{
<Data name="ReleaseRunDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>StartedAt</Value>
</Value>
<Value name="3">
<Value>EndedAt</Value>
</Value>
<Value name="4">
<Value>State</Value>
</Value>
<Value name="5">
<Value>WaitingChecked</Value>
</Value>
<Value name="6">
<Value>WaitingReleased</Value>
</Value>
<Value name="7">
<Value>HeldChecked</Value>
</Value>
<Value name="8">
<Value>HeldReleased</Value>
</Value>
<Value name="9">
<Value>Error</Value>
</Value>
<Value name="10">
<Value>Job</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.ReleaseRunD</DataLocation>
<DefaultData>ReleaseRunDefaultData</DefaultData>
<IdLocation>^Shutter.Store.ReleaseRunD</IdLocation>
<IndexLocation>^Shutter.Store.ReleaseRunI</IndexLocation>
<StreamLocation>^Shutter.Store.ReleaseRunS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
