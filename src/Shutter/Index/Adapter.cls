/// Shutter's own inbound adapter (CONTRACTS 8.1, v1.31): where the plain Ens.InboundAdapter only ticks, this one reads. On
/// each task it walks Ens.MessageHeader by id from the index's high-water mark, on the watched routes and only headers older
/// than the lag (an id is taken before its row is written, so the newest few can appear out of order), and hands the
/// indexer (Shutter.Index.Indexer) each batch as a Shutter.Index.Batch through ProcessInput; once the service has taken a
/// batch the mark moves to its last id. Several batches per task while the walk is behind (a back-fill, a burst), bounded so
/// the service stays responsive. The first start begins at the oldest header within the back-fill window, or at the newest
/// header when none is that recent. The site's Search Table Class settings stay as they are; the index is a finder, never a
/// second source of truth.
Class Shutter.Index.Adapter Extends Ens.InboundAdapter
{

/// The business services whose HL7 messages are indexed (config names, comma-separated). Empty indexes every HL7 message.
Property Routes As %String(MAXLEN = 1000) [ InitialExpression = "ADT In" ];

/// Headers read per batch.
Property BatchSize As %Integer [ InitialExpression = 200 ];

/// Headers younger than this wait for the next task.
Property LagSeconds As %Integer [ InitialExpression = 5 ];

/// On the first start, how far back the walk begins (hours). 0 starts at the newest header.
Property BackfillHours As %Integer [ InitialExpression = 168 ];

/// Batches per task at most, while the walk is behind.
Property MaxBatchesPerTask As %Integer [ InitialExpression = 20 ];

Parameter SETTINGS = "Routes:Index,BatchSize:Index,LagSeconds:Index,BackfillHours:Index,MaxBatchesPerTask:Index";

/// Each task: the next batches after the mark, each handed to the service; the mark moves when the service has taken one.
Method OnTask() As %Status
{
    // Only the walk: the releases of waiting and held cases that ran here in v1.34 are the Case Releaser's (v1.35,
    // Shutter.Operation.Releaser), one host for each job.
    Set total = 0, batches = 0
    Do ..EnsureMark()
    Set ^Shutter.Index("routes") = ..Routes, ^Shutter.Index("lag") = ..LagSeconds
    For {
        Set batch = ..NextBatch($GET(^Shutter.Index("hwm"), 0), ..Routes, ..BatchSize, ..LagSeconds, .error)
        If error '= "" { $$$LOGWARNING("Index walk: " _ error) Quit }
        Set ^Shutter.Index("last_pass_at") = ##class(Shutter.Util.Time).NowUTC()
        Quit:(batch.Count = 0)
        Set sc = ..BusinessHost.ProcessInput(batch, .out)
        If $$$ISERR(sc) { $$$LOGWARNING("The indexer did not take a batch of " _ batch.Count _ " header(s) after " _ batch.AfterId _ ": " _ $SYSTEM.Status.GetErrorText(sc)) Quit }
        Do ..Advance(batch.LastId)
        Set total = total + batch.Count, batches = batches + 1
        Quit:(batch.Count < ..BatchSize)
        Quit:(batches >= ..MaxBatchesPerTask)
    }
    If total > 0 $$$TRACE("Walked " _ total _ " header(s) in " _ batches _ " batch(es); high-water mark " _ $GET(^Shutter.Index("hwm")))
    Quit $$$OK
}

/// The first start: the mark begins at the oldest header within the back-fill window, or at the newest header when none
/// is that recent (and when BackfillHours is 0), so an old, quiet store is never walked from header 1.
Method EnsureMark()
{
    Quit:($GET(^Shutter.Index("hwm")) '= "")
    Set sinceTs = ""
    If ..BackfillHours > 0 Set sinceTs = ..Odbc(##class(Shutter.Util.Time).FromNow(-3600 * ..BackfillHours))
    Set ^Shutter.Index("hwm") = ..FirstMark(sinceTs), ^Shutter.Index("started_at") = ##class(Shutter.Util.Time).NowUTC()
}

/// Where a first walk starts: one below the oldest header created at or after sinceTs (the ODBC form), else the newest
/// header's id (no window, or no header that recent), and 0 for an empty table. A read, nothing written, so a test can
/// call it with any window.
ClassMethod FirstMark(sinceTs As %String = "") As %Integer
{
    If sinceTs '= "" {
        Set first = ""
        &sql(SELECT MIN(ID) INTO :first FROM Ens.MessageHeader WHERE TimeCreated >= :sinceTs)
        If (SQLCODE = 0) && (first '= "") Quit first - 1
    }
    Set last = ""
    &sql(SELECT MAX(ID) INTO :last FROM Ens.MessageHeader)
    If (SQLCODE = 0) && (last '= "") Quit +last
    Quit 0
}

/// The next batch of HL7 headers after a mark, on the routes, older than the lag: a read, nothing written, so a test can
/// call it on a live table. The walk is bounded by id, not by time: it stops short of the first header younger than the lag,
/// so a header with a lower id that is still being written is never leapt over. error is set when the query fails.
ClassMethod NextBatch(afterId As %Integer, routes As %String = "", batch As %Integer = 200, lag As %Integer = 5, Output error As %String) As Shutter.Index.Batch
{
    Set error = ""
    Set out = ##class(Shutter.Index.Batch).%New(), out.AfterId = +afterId, out.LastId = +afterId, out.Routes = routes
    Try {
        Set cutoff = ..Odbc(##class(Shutter.Util.Time).FromNow(-lag))
        Set boundary = "", hwm = +afterId
        &sql(SELECT MIN(ID) INTO :boundary FROM Ens.MessageHeader WHERE ID > :hwm AND TimeCreated > :cutoff)
        If (SQLCODE '= 0) Set boundary = ""
        Set sql = "SELECT TOP " _ (+batch) _ " ID, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'EnsLib.HL7.Message'"
        Set args = 1, args(1) = hwm
        If boundary '= "" Set sql = sql _ " AND ID < ?", args = 2, args(2) = boundary
        Set in = ""
        For i = 1:1:$LENGTH(routes, ",") {
            Set r = $ZSTRIP($PIECE(routes, ",", i), "<>W")
            Continue:r=""
            Set in = in _ $SELECT(in = "": "", 1: ", ") _ "?", args = args + 1, args(args) = r
        }
        If in '= "" Set sql = sql _ " AND SourceConfigName IN (" _ in _ ")"
        Set sql = sql _ " ORDER BY ID"
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, args...)
        If rs.%SQLCODE < 0 Set error = "SQLCODE " _ rs.%SQLCODE _ ": " _ rs.%Message Quit
        While rs.%Next() { Do out.Add(rs.%Get("ID"), rs.%Get("MessageBodyId")) }
    } Catch ex {
        Set error = ex.DisplayString()
    }
    Quit out
}

/// The mark moves forward only.
ClassMethod Advance(lastId As %Integer)
{
    If +lastId > +$GET(^Shutter.Index("hwm")) Set ^Shutter.Index("hwm") = +lastId
}

/// An ISO UTC timestamp as the ODBC form Ens.MessageHeader.TimeCreated uses.
ClassMethod Odbc(iso As %String) As %String
{
    Quit $TRANSLATE($PIECE(iso, "Z", 1), "T", " ")
}

}
