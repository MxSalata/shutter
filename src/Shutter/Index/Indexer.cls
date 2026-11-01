/// Shutter's indexer (CONTRACTS 8.1): the service behind the production item "HL7 Index". Its adapter, Shutter.Index.Adapter
/// (v1.31), walks Ens.MessageHeader a few seconds behind the newest header and hands it each batch of HL7 headers on the
/// watched routes; the service gives every message a row in Shutter.Index.Message. The site's Search Table Class settings
/// stay as they are. A high-water mark in ^Shutter.Index("hwm") says where the walk stands (the adapter keeps it); Rebuild()
/// walks a range again. The index is a finder, never a second source of truth: every decision still opens the message.
Class Shutter.Index.Indexer Extends Ens.BusinessService
{

Parameter ADAPTER = "Shutter.Index.Adapter";

Property Adapter As Shutter.Index.Adapter;

/// A batch from the adapter: every header's message is indexed, a failure is recorded against the header for Rebuild and
/// the walk goes on. The batch is always taken (the adapter then moves the mark), so one bad message never stalls the index.
Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    Set pOutput = ""
    If '$ISOBJECT(pInput) || 'pInput.%IsA("Shutter.Index.Batch") Quit $$$ERROR($$$GeneralError, "The indexer expects a Shutter.Index.Batch, got " _ $SELECT($ISOBJECT(pInput): $CLASSNAME(pInput), 1: "nothing"))
    Set indexed = 0, failed = 0, last = ""
    For i = 1:1:pInput.Count {
        Set sc = ..IndexHeader($LIST(pInput.Ids, i), $LIST(pInput.BodyIds, i), .added)
        If $$$ISERR(sc) { Set failed = failed + 1, last = $EXTRACT($SYSTEM.Status.GetErrorText(sc), 1, 200) } ElseIf added { Set indexed = indexed + 1 }
    }
    If indexed > 0 Set ^Shutter.Index("last_indexed_at") = ##class(Shutter.Util.Time).NowUTC(), ^Shutter.Index("total") = $GET(^Shutter.Index("total")) + indexed
    If failed > 0 $$$LOGWARNING(failed _ " header(s) of the batch after " _ pInput.AfterId _ " could not be indexed, the last: " _ last)
    If indexed > 0 $$$TRACE("Indexed " _ indexed _ " HL7 message(s) of " _ pInput.Count _ " header(s), up to header " _ pInput.LastId)
    Quit $$$OK
}

/// One header's message into the index: added says whether a row was made (none for a message already indexed or a
/// header without a body). A failure is recorded in ^Shutter.Index("failed", id) for Rebuild, and cleared when it succeeds.
ClassMethod IndexHeader(id As %Integer, bodyId As %String, Output added As %Boolean) As %Status
{
    Set added = 0
    If (bodyId = "") || ##class(Shutter.Index.Message).Indexed(bodyId) Quit $$$OK
    Set body = ##class(EnsLib.HL7.Message).%OpenId(bodyId)
    If '$ISOBJECT(body) Quit $$$OK
    Set sc = ##class(Shutter.Index.Message).IndexDoc(body)
    If $$$ISERR(sc) {
        Set ^Shutter.Index("failed", id) = $EXTRACT($SYSTEM.Status.GetErrorText(sc), 1, 500)
        Quit sc
    }
    Set added = 1
    Kill ^Shutter.Index("failed", id)
    Quit $$$OK
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
        If $$$ISOK(..IndexHeader(rs.%Get("ID"), rs.%Get("MessageBodyId"), .one)) && one Set added = added + 1
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
    // Behind: the HL7 headers above the mark on the watched routes that are older than the lag, as the walk sees them.
    Set behind = 0
    If (newest '= "") && ($GET(^Shutter.Index("hwm")) '= "") {
        Set hwm = ^Shutter.Index("hwm"), routes = $GET(^Shutter.Index("routes")), lag = +$GET(^Shutter.Index("lag"))
        Set sql = "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID > ? AND MessageBodyClassName = 'EnsLib.HL7.Message' AND TimeCreated <= ?"
        Set args = 2, args(1) = hwm, args(2) = ..Odbc(##class(Shutter.Util.Time).FromNow(-lag)), in = ""
        For i = 1:1:$LENGTH(routes, ",") {
            Set r = $ZSTRIP($PIECE(routes, ",", i), "<>W")
            Continue:r=""
            Set in = in _ $SELECT(in = "": "", 1: ", ") _ "?", args = args + 1, args(args) = r
        }
        If in '= "" Set sql = sql _ " AND SourceConfigName IN (" _ in _ ")"
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, args...)
        If rs.%Next() Set behind = rs.%GetData(1)
    }
    Set o."hl7_headers_behind" = +behind
    Do o.%Set("caught_up", +behind = 0, "boolean")
    Set o."failed_headers" = 0
    Set k = "" For { Set k = $ORDER(^Shutter.Index("failed", k)) Quit:k=""  Set o."failed_headers" = o."failed_headers" + 1 }
    Set o.adapter = "Shutter.Index.Adapter"
    Quit o
}

/// An ISO UTC timestamp as the ODBC form Ens.MessageHeader.TimeCreated uses.
ClassMethod Odbc(iso As %String) As %String
{
    Quit $TRANSLATE($PIECE(iso, "Z", 1), "T", " ")
}

}
