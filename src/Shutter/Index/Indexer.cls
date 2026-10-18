/// Shutter's indexer (CONTRACTS 8.1): a service with no adapter that walks Ens.MessageHeader by id, a few seconds
/// behind the newest header, and gives every HL7 message on the watched routes a row in Shutter.Index.Message. The
/// site's Search Table Class settings stay as they are. A high-water mark in ^Shutter.Index("hwm") says where the
/// walk stands; the first start begins at the oldest header within the back-fill window; Rebuild() walks a range
/// again. The index is a finder, never a second source of truth: every decision still opens the message.
Class Shutter.Index.Indexer Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Property Adapter As Ens.InboundAdapter;

/// The business services whose HL7 messages are indexed (config names, comma-separated). Empty indexes every HL7 message.
Property Routes As %String(MAXLEN = 1000) [ InitialExpression = "ADT In" ];

/// Headers read per pass.
Property BatchSize As %Integer [ InitialExpression = 200 ];

/// Headers younger than this wait for the next pass: an id is taken before its row is written, so the newest few can
/// appear out of order.
Property LagSeconds As %Integer [ InitialExpression = 5 ];

/// On the first start, how far back the walk begins (hours). 0 starts at the newest header.
Property BackfillHours As %Integer [ InitialExpression = 168 ];

Parameter SETTINGS = "Routes:Index,BatchSize:Index,LagSeconds:Index,BackfillHours:Index";

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    Set pOutput = ""
    Set caughtUp = ..Pass(..Routes, ..BatchSize, ..LagSeconds, ..BackfillHours, .indexed, .error)
    If error '= "" $$$LOGWARNING("Index pass: " _ error)
    If indexed > 0 $$$TRACE("Indexed " _ indexed _ " HL7 message(s); high-water mark " _ $GET(^Shutter.Index("hwm")))
    Quit $$$OK
}

/// One pass: the next batch of headers after the high-water mark, on the routes, older than the lag. Returns 1 when
/// the walk has caught up (fewer headers than the batch).
ClassMethod Pass(routes As %String = "", batch As %Integer = 200, lag As %Integer = 5, backfillHours As %Integer = 168, Output indexed As %Integer, Output error As %String) As %Boolean
{
    Set indexed = 0, error = "", caughtUp = 1
    Try {
        Set hwm = $GET(^Shutter.Index("hwm"))
        If hwm = "" {
            Set hwm = 0
            If backfillHours > 0 {
                Set sinceTs = ..Odbc(##class(Shutter.Util.Time).FromNow(-3600 * backfillHours)), first = ""
                &sql(SELECT MIN(ID) INTO :first FROM Ens.MessageHeader WHERE TimeCreated >= :sinceTs)
                If (SQLCODE = 0) && (first '= "") Set hwm = first - 1
            } Else {
                Set last = ""
                &sql(SELECT MAX(ID) INTO :last FROM Ens.MessageHeader)
                If (SQLCODE = 0) && (last '= "") Set hwm = last
            }
            Set ^Shutter.Index("hwm") = hwm, ^Shutter.Index("started_at") = ##class(Shutter.Util.Time).NowUTC()
        }
        Set cutoff = ..Odbc(##class(Shutter.Util.Time).FromNow(-lag))
        Set sql = "SELECT TOP " _ (+batch) _ " ID, MessageBodyId FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'EnsLib.HL7.Message' AND TimeCreated <= ?"
        Set args = 2, args(1) = hwm, args(2) = cutoff
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
        Set n = 0
        While rs.%Next() {
            Set n = n + 1, id = rs.%Get("ID"), bodyId = rs.%Get("MessageBodyId")
            If (bodyId '= "") && '##class(Shutter.Index.Message).Indexed(bodyId) {
                Set body = ##class(EnsLib.HL7.Message).%OpenId(bodyId)
                If $ISOBJECT(body) {
                    Set sc = ##class(Shutter.Index.Message).IndexDoc(body)
                    If $$$ISERR(sc) { Set error = "header " _ id _ ": " _ $SYSTEM.Status.GetErrorText(sc) } Else { Set indexed = indexed + 1 }
                }
            }
            Set hwm = id
        }
        Set ^Shutter.Index("hwm") = hwm, ^Shutter.Index("last_pass_at") = ##class(Shutter.Util.Time).NowUTC()
        If indexed > 0 Set ^Shutter.Index("last_indexed_at") = ^Shutter.Index("last_pass_at"), ^Shutter.Index("total") = $GET(^Shutter.Index("total")) + indexed
        Set caughtUp = (n < batch)
    } Catch ex {
        Set error = ex.DisplayString()
    }
    Quit caughtUp
}

/// Walk a range of header ids again, whatever the high-water mark: the back-fill, or a repair. Returns how many rows
/// it added.
ClassMethod Rebuild(fromId As %Integer, toId As %Integer, routes As %String = "") As %Integer [ SqlProc ]
{
    If '$SYSTEM.Security.Check("Shutter_Operate", "USE") Quit -1
    Set added = 0
    Set sql = "SELECT ID, MessageBodyId FROM Ens.MessageHeader WHERE ID >= ? AND ID <= ? AND MessageBodyClassName = 'EnsLib.HL7.Message'"
    Set args = 2, args(1) = fromId, args(2) = toId, in = ""
    For i = 1:1:$LENGTH(routes, ",") {
        Set r = $ZSTRIP($PIECE(routes, ",", i), "<>W")
        Continue:r=""
        Set in = in _ $SELECT(in = "": "", 1: ", ") _ "?", args = args + 1, args(args) = r
    }
    If in '= "" Set sql = sql _ " AND SourceConfigName IN (" _ in _ ")"
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql _ " ORDER BY ID", args...)
    While rs.%Next() {
        Set bodyId = rs.%Get("MessageBodyId")
        Continue:((bodyId = "") || ##class(Shutter.Index.Message).Indexed(bodyId))
        Set body = ##class(EnsLib.HL7.Message).%OpenId(bodyId)
        Continue:'$ISOBJECT(body)
        If $$$ISOK(##class(Shutter.Index.Message).IndexDoc(body)) Set added = added + 1
    }
    If added > 0 Set ^Shutter.Index("total") = $GET(^Shutter.Index("total")) + added
    Quit added
}

/// Where the walk stands, for the API.
ClassMethod Status() As %DynamicObject
{
    Set o = {}
    Set o.rows = ##class(Shutter.Index.Message).Count()
    Set o."high_water_mark" = $GET(^Shutter.Index("hwm"))
    Set o."started_at" = $GET(^Shutter.Index("started_at")), o."last_pass_at" = $GET(^Shutter.Index("last_pass_at"))
    Set o."last_indexed_at" = $GET(^Shutter.Index("last_indexed_at")), o."indexed_total" = +$GET(^Shutter.Index("total"))
    Set newest = ""
    &sql(SELECT MAX(ID) INTO :newest FROM Ens.MessageHeader)
    Set o."newest_header" = newest
    Quit o
}

/// An ISO UTC timestamp as the ODBC form Ens.MessageHeader.TimeCreated uses.
ClassMethod Odbc(iso As %String) As %String
{
    Quit $TRANSLATE($PIECE(iso, "Z", 1), "T", " ")
}

}
