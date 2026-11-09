/// The fixed-query reader of warehouse history (docs/warehouse-history.md). It runs in a web application of its own,
/// authenticated as a dedicated user who may SELECT on the two tables and do nothing else, and only reads: the three
/// statements below are all it can run, each through %SQL.Statement so that the identity's SQL privileges are checked.
/// No table name, SQL fragment or condition comes from the request.
Class Shutter.Warehouse.Reader Extends %CSP.REST
{

Parameter HandleCorsRequest = 0;

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "utf-8";

Parameter UseSession = 0;

/// The version of the statements below, kept with each read.
Parameter QUERYVERSION = "1";

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/history" Method="GET" Call="History"/>
</Routes>
}

ClassMethod History() As %Status
{
    Set %response.ContentType = "application/json"
    Set dataset = $GET(%request.Data("dataset", 1)), authority = $GET(%request.Data("authority", 1)), patient = $GET(%request.Data("patient", 1))
    If (dataset = "") || (authority = "") || (patient = "") || ($LENGTH(dataset) > 64) || ($LENGTH(authority) > 100) || ($LENGTH(patient) > 160) {
        Set %response.Status = "400 Bad Request"
        Write "{""error"":""bad_request""}"
        Quit $$$OK
    }
    Try {
        Do ..Read(dataset, authority, patient).%ToJSON()
    } Catch ex {
        Set %response.Status = "500 Internal Server Error"
        Write "{""error"":""read_failed""}"
    }
    Quit $$$OK
}

/// {query_version, manifest (null when no batch is ready), present_rows, rows}: the newest ready batch's manifest, how
/// many rows that batch holds, and up to 201 of this patient's rows from that batch alone.
ClassMethod Read(dataset As %String, authority As %String, patient As %String) As %DynamicObject
{
    Set out = {"query_version": (..#QUERYVERSION), "manifest": null, "present_rows": 0, "rows": []}
    Set rs = ..Run("SELECT TOP 1 DatasetId, BatchId, BatchSequence, DatasetGeneration, SourceSystem, ReceiverReference, SourceWatermarkUTC, WatermarkKnown, HistoryCompleteFromUTC, PublishedAtUTC, PublishedRows, SchemaVersion FROM ShutterWH.Batch WHERE DatasetId = ? AND Ready = 1 ORDER BY PublishedAtUTC DESC, BatchSequence DESC", dataset)
    If 'rs.%Next() Quit out
    Set m = {}
    Do ..Put(m, "dataset_id", rs.%Get("DatasetId")), ..Put(m, "batch_id", rs.%Get("BatchId")), ..Put(m, "dataset_generation", rs.%Get("DatasetGeneration"))
    Do ..Put(m, "source_system", rs.%Get("SourceSystem")), ..Put(m, "receiver_reference", rs.%Get("ReceiverReference"))
    Do ..Put(m, "source_watermark_utc", rs.%Get("SourceWatermarkUTC")), ..Put(m, "history_complete_from_utc", rs.%Get("HistoryCompleteFromUTC")), ..Put(m, "published_at_utc", rs.%Get("PublishedAtUTC"))
    Do m.%Set("batch_sequence", +rs.%Get("BatchSequence"), "number"), m.%Set("watermark_known", +rs.%Get("WatermarkKnown"), "number")
    Do m.%Set("published_rows", +rs.%Get("PublishedRows"), "number"), m.%Set("schema_version", +rs.%Get("SchemaVersion"), "number")
    Set out.manifest = m
    Set batch = rs.%Get("BatchId")

    Set rs = ..Run("SELECT COUNT(*) AS PresentRows FROM ShutterWH.Movement WHERE DatasetId = ? AND BatchId = ?", dataset, batch)
    Do rs.%Next()
    Do out.%Set("present_rows", +rs.%Get("PresentRows"), "number")

    Set rs = ..Run("SELECT TOP 201 SourceEventId, Revision, RecordStatus, PatientAuthority, PatientId, EncounterAuthority, EncounterId, EventKind, EventTimeUTC, TimePrecision, SourceRecordedAtUTC, SourceModifiedAtUTC, Ward, Bed, SupersedesEventId FROM ShutterWH.Movement WHERE DatasetId = ? AND BatchId = ? AND PatientAuthority = ? AND PatientId = ? ORDER BY EventTimeUTC DESC, SourceRecordedAtUTC DESC, SourceEventId DESC", dataset, batch, authority, patient)
    Set rows = []
    While rs.%Next() {
        Set r = {}
        Do ..Put(r, "source_event_id", rs.%Get("SourceEventId")), r.%Set("revision", +rs.%Get("Revision"), "number"), ..Put(r, "record_status", rs.%Get("RecordStatus"))
        Do ..Put(r, "patient_authority", rs.%Get("PatientAuthority")), ..Put(r, "patient_id", rs.%Get("PatientId"))
        Do ..Put(r, "encounter_authority", rs.%Get("EncounterAuthority")), ..Put(r, "encounter_id", rs.%Get("EncounterId")), ..Put(r, "event_kind", rs.%Get("EventKind"))
        Do ..Put(r, "event_time_utc", rs.%Get("EventTimeUTC")), ..Put(r, "time_precision", rs.%Get("TimePrecision"))
        Do ..Put(r, "source_recorded_at_utc", rs.%Get("SourceRecordedAtUTC")), ..Put(r, "source_modified_at_utc", rs.%Get("SourceModifiedAtUTC"))
        Do ..Put(r, "ward", rs.%Get("Ward")), ..Put(r, "bed", rs.%Get("Bed")), ..Put(r, "supersedes_event_id", rs.%Get("SupersedesEventId"))
        Do rows.%Push(r)
    }
    Set out.rows = rows
    Quit out
}

/// Prepare and run one statement in ODBC mode, so a time reads as text; a refusal is thrown, not swallowed.
ClassMethod Run(sql As %String, args...) As %SQL.StatementResult [ Private ]
{
    Set statement = ##class(%SQL.Statement).%New()
    Set statement.%SelectMode = 1
    $$$ThrowOnError(statement.%Prepare(sql))
    Set rs = statement.%Execute(args...)
    If rs.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(rs.%SQLCODE, rs.%Message)
    Quit rs
}

ClassMethod Put(o As %DynamicObject, key As %String, value As %String) [ Private ]
{
    If value = "" { Do o.%Set(key, "", "null") } Else { Do o.%Set(key, value, "string") }
}

}
