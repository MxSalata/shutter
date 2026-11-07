/// One read of warehouse history for a case (docs/warehouse-history.md): what the batch was, how old it was, and the
/// reduced rows. A supplement for a person to read, kept apart from the case's evidence: it is no snapshot item and no
/// event, and nothing that decides a case reads it. Rows are never changed; a new read is a new row, and the page shows the
/// newest. The rows are personal data, so they go when the case goes (Shutter.Store.Case, PurgeCase).
Class Shutter.Store.WarehouseRead Extends %Persistent
{

Property Case As Shutter.Store.Case [ Required ];

Index CaseIdx On Case;

Property ReadAt As %String(MAXLEN = 30);

Property ReadBy As %String(MAXLEN = 160);

/// ok, no_rows, no_batch, no_identity, withheld, invalid, unavailable.
Property Status As %String(MAXLEN = 16);

/// Why, for invalid and unavailable (row_count_mismatch, identity_mismatch, unreachable ...).
Property Category As %String(MAXLEN = 32);

Property Dataset As %String(MAXLEN = 64);

Index DatasetIdx On Dataset;

Property Generation As %String(MAXLEN = 64);

Property BatchId As %String(MAXLEN = 64);

Property Sequence As %BigInt;

Property SourceSystem As %String(MAXLEN = 100);

Property ReceiverReference As %String(MAXLEN = 128);

Property SourceWatermark As %String(MAXLEN = 30);

Property WatermarkKnown As %Boolean;

Property HistoryCompleteFrom As %String(MAXLEN = 30);

Property PublishedAt As %String(MAXLEN = 30);

Property AgeMinutes As %Integer;

/// within, older or unknown.
Property Freshness As %String(MAXLEN = 16);

Property RowCount As %Integer;

Property Truncated As %Boolean;

Property GenerationChanged As %Boolean;

Property QueryVersion As %String(MAXLEN = 16);

Property ResultDigest As %String(MAXLEN = 80);

/// The reduced rows as JSON: 200 at most, none unless Status is ok.
Property RowsJson As %String(MAXLEN = "");

ClassMethod Record(case As Shutter.Store.Case, a As %DynamicObject, dataset As %String, user As %String, now As %String, Output read As Shutter.Store.WarehouseRead) As %Status
{
    Set read = ..%New()
    Do read.CaseSetObjectId(case.%Id())
    Set read.ReadAt = now, read.ReadBy = user, read.Dataset = dataset
    Set read.Status = a.%Get("status"), read.Category = a.%Get("category"), read.Freshness = a.%Get("freshness")
    Set read.Generation = a.%Get("generation"), read.BatchId = a.%Get("batch"), read.Sequence = a.%Get("sequence")
    Set read.SourceSystem = a.%Get("source_system"), read.ReceiverReference = a.%Get("receiver_reference")
    Set read.SourceWatermark = a.%Get("source_watermark"), read.WatermarkKnown = ''a.%Get("watermark_known")
    Set read.HistoryCompleteFrom = a.%Get("history_complete_from"), read.PublishedAt = a.%Get("published_at")
    Set read.AgeMinutes = a.%Get("age_minutes"), read.RowCount = +a.%Get("row_count")
    Set read.Truncated = ''a.%Get("truncated"), read.GenerationChanged = ''a.%Get("generation_changed")
    Set read.QueryVersion = a.%Get("query_version"), read.ResultDigest = a.%Get("result_digest")
    Set rows = a.%Get("rows")
    Set read.RowsJson = $SELECT($ISOBJECT(rows): rows.%ToJSON(), 1: "[]")
    Quit read.%Save()
}

/// The newest read of a case, or "".
ClassMethod Latest(case As Shutter.Store.Case) As Shutter.Store.WarehouseRead
{
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM Shutter_Store.WarehouseRead WHERE ""Case"" = ? ORDER BY ID DESC", case.%Id())
    If 'rs.%Next() Quit ""
    Quit ..%OpenId(rs.%Get("ID"))
}

/// {generation, sequence} of the dataset's last read that named a batch which passed, or "": what the next one compares with.
ClassMethod LastSeen(dataset As %String) As %DynamicObject
{
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 Generation, Sequence FROM Shutter_Store.WarehouseRead WHERE Dataset = ? AND Generation IS NOT NULL AND Status IN ('ok', 'no_rows', 'withheld') ORDER BY ID DESC", dataset)
    If 'rs.%Next() Quit ""
    Quit {"generation": (rs.%Get("Generation")), "sequence": (+rs.%Get("Sequence"))}
}

/// The read as the API gives it.
Method View() As %DynamicObject
{
    Set o = {"readAt": (..ReadAt), "readBy": (..ReadBy), "status": (..Status), "category": (..Category), "dataset": (..Dataset), "generation": (..Generation), "batch": (..BatchId), "sourceSystem": (..SourceSystem), "receiverReference": (..ReceiverReference), "sourceWatermark": (..SourceWatermark), "historyCompleteFrom": (..HistoryCompleteFrom), "publishedAt": (..PublishedAt), "freshness": (..Freshness), "queryVersion": (..QueryVersion), "resultDigest": (..ResultDigest)}
    If ..Sequence = "" { Do o.%Set("sequence", "", "null") } Else { Do o.%Set("sequence", +..Sequence, "number") }
    If ..AgeMinutes = "" { Do o.%Set("ageMinutes", "", "null") } Else { Do o.%Set("ageMinutes", +..AgeMinutes, "number") }
    Do o.%Set("rowCount", +..RowCount, "number"), o.%Set("watermarkKnown", ''..WatermarkKnown, "boolean"), o.%Set("truncated", ''..Truncated, "boolean"), o.%Set("generationChanged", ''..GenerationChanged, "boolean")
    Set o.rows = ##class(%DynamicArray).%FromJSON($SELECT(..RowsJson = "": "[]", 1: ..RowsJson))
    Quit o
}

Storage Default
{
<Data name="WarehouseReadDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Case</Value>
</Value>
<Value name="3">
<Value>ReadAt</Value>
</Value>
<Value name="4">
<Value>ReadBy</Value>
</Value>
<Value name="5">
<Value>Status</Value>
</Value>
<Value name="6">
<Value>Category</Value>
</Value>
<Value name="7">
<Value>Dataset</Value>
</Value>
<Value name="8">
<Value>Generation</Value>
</Value>
<Value name="9">
<Value>BatchId</Value>
</Value>
<Value name="10">
<Value>Sequence</Value>
</Value>
<Value name="11">
<Value>SourceSystem</Value>
</Value>
<Value name="12">
<Value>ReceiverReference</Value>
</Value>
<Value name="13">
<Value>SourceWatermark</Value>
</Value>
<Value name="14">
<Value>WatermarkKnown</Value>
</Value>
<Value name="15">
<Value>HistoryCompleteFrom</Value>
</Value>
<Value name="16">
<Value>PublishedAt</Value>
</Value>
<Value name="17">
<Value>AgeMinutes</Value>
</Value>
<Value name="18">
<Value>Freshness</Value>
</Value>
<Value name="19">
<Value>RowCount</Value>
</Value>
<Value name="20">
<Value>Truncated</Value>
</Value>
<Value name="21">
<Value>GenerationChanged</Value>
</Value>
<Value name="22">
<Value>QueryVersion</Value>
</Value>
<Value name="23">
<Value>ResultDigest</Value>
</Value>
<Value name="24">
<Value>RowsJson</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.WarehouseReadD</DataLocation>
<DefaultData>WarehouseReadDefaultData</DefaultData>
<IdLocation>^Shutter.Store.WarehouseReadD</IdLocation>
<IndexLocation>^Shutter.Store.WarehouseReadI</IndexLocation>
<StreamLocation>^Shutter.Store.WarehouseReadS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
