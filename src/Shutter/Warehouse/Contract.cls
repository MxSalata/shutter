/// Warehouse history's checks on what the reader returned (docs/warehouse-history.md): whether this answer can be shown,
/// how old it is, and what is kept of it. No database and no network, so every refusal can be tested on its own. The
/// result is for a person to read and for nothing else: nothing that decides a case reads it.
Class Shutter.Warehouse.Contract [ Abstract ]
{

/// The most rows kept of a read. The query asks for one more, to tell a list that was cut short.
Parameter MAXROWS = 200;

/// The answer as a dynamic object:
/// {status, category, freshness, age_minutes, source_watermark, watermark_known, history_complete_from, published_at,
/// dataset, generation, batch, sequence, source_system, receiver_reference, row_count, truncated, generation_changed,
/// query_version, result_digest, rows}.
/// status: ok, no_rows, no_batch, withheld (too old or of unknown age, and the site chose not to show that), invalid
/// (category says why). Rows are kept only for ok. `last` is {generation, sequence} from the last read of this dataset.
ClassMethod Assess(payload As %DynamicObject, dataset As %String, authority As %String, patient As %String, now As %String, maxAgeMinutes As %Integer = 360, showOlder As %Boolean = 0, last As %DynamicObject = "") As %DynamicObject
{
    Set out = {"status": "invalid", "category": "", "freshness": "unknown", "age_minutes": "", "rows": [], "row_count": 0}
    Do out.%Set("truncated", 0, "boolean"), out.%Set("generation_changed", 0, "boolean"), out.%Set("watermark_known", 0, "boolean")
    Set out."query_version" = ..Text(payload, "query_version")
    Set m = payload.%Get("manifest")
    If '$ISOBJECT(m) Set out.status = "no_batch" Quit out

    Set out.dataset = ..Text(m, "dataset_id"), out.batch = ..Text(m, "batch_id"), out.generation = ..Text(m, "dataset_generation")
    Set out.sequence = ..Text(m, "batch_sequence")
    Set out."source_system" = ..Text(m, "source_system"), out."receiver_reference" = ..Text(m, "receiver_reference")
    Set out."source_watermark" = ..Iso(..Text(m, "source_watermark_utc"))
    Set out."history_complete_from" = ..Iso(..Text(m, "history_complete_from_utc"))
    Set out."published_at" = ..Iso(..Text(m, "published_at_utc"))
    Set known = (+..Text(m, "watermark_known") = 1)
    Do out.%Set("watermark_known", known, "boolean")

    If out.dataset '= dataset Quit ..Refuse(out, "wrong_dataset")
    If +..Text(m, "schema_version") '= 1 Quit ..Refuse(out, "schema_version")
    If (out.batch = "") || (out.generation = "") || (out.sequence = "") Quit ..Refuse(out, "manifest_incomplete")
    If known && (out."source_watermark" = "") Quit ..Refuse(out, "watermark_inconsistent")
    If 'known Set out."source_watermark" = ""
    If +..Text(payload, "present_rows") '= +..Text(m, "published_rows") Quit ..Refuse(out, "row_count_mismatch")

    // The same generation going backwards is an export restored: a new generation may start again, and is marked.
    If $ISOBJECT(last) && (..Text(last, "generation") '= "") {
        If ..Text(last, "generation") '= out.generation {
            Do out.%Set("generation_changed", 1, "boolean")
        } ElseIf +out.sequence < +..Text(last, "sequence") {
            Quit ..Refuse(out, "sequence_regressed")
        }
    }

    Set rows = payload.%Get("rows")
    If '$ISOBJECT(rows) Set rows = []
    Set kept = [], problem = "", iter = rows.%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set problem = ..RowProblem(row, authority, patient)
        Quit:problem'=""
        If kept.%Size() < ..#MAXROWS Do kept.%Push(..Reduced(row))
    }
    If problem '= "" Quit ..Refuse(out, problem)
    Do out.%Set("truncated", rows.%Size() > ..#MAXROWS, "boolean")
    Set out."row_count" = kept.%Size()

    If known {
        Set seconds = ##class(Shutter.Util.Time).SecondsBetween(out."source_watermark", now)
        If seconds = "" Quit ..Refuse(out, "watermark_inconsistent")
        // A small allowance for two clocks; beyond it a watermark still to come cannot be right.
        If seconds < -300 Quit ..Refuse(out, "watermark_in_future")
        Set out."age_minutes" = $SELECT(seconds < 0: 0, 1: seconds \ 60)
        Set out.freshness = $SELECT(out."age_minutes" > maxAgeMinutes: "older", 1: "within")
    }
    Set out."result_digest" = ##class(Shutter.Util.Digest).OfObject(kept)
    If (out.freshness '= "within") && 'showOlder {
        Set out.status = "withheld"
        Quit out
    }
    Set out.rows = kept
    Set out.status = $SELECT(kept.%Size() = 0: "no_rows", 1: "ok")
    Quit out
}

ClassMethod Refuse(out As %DynamicObject, category As %String) As %DynamicObject [ Private ]
{
    Set out.status = "invalid", out.category = category, out.rows = [], out."row_count" = 0
    Do out.%Set("truncated", 0, "boolean")
    Quit out
}

/// Why this row cannot be shown, or "". Compares exactly here, whatever the table's collation did.
ClassMethod RowProblem(row As %DynamicObject, authority As %String, patient As %String) As %String
{
    If '$ISOBJECT(row) Quit "row_invalid"
    If (..Text(row, "patient_authority") '= authority) || (..Text(row, "patient_id") '= patient) Quit "identity_mismatch"
    If ..Text(row, "source_event_id") = "" Quit "row_invalid"
    If '$LISTFIND($LISTBUILD("active", "cancelled", "retracted"), ..Text(row, "record_status")) Quit "row_invalid"
    If '$LISTFIND($LISTBUILD("admit", "transfer", "discharge", "update", "cancel", "other"), ..Text(row, "event_kind")) Quit "row_invalid"
    If '$LISTFIND($LISTBUILD("second", "minute", "date", "unknown"), ..Text(row, "time_precision")) Quit "row_invalid"
    Quit ""
}

/// What is kept of a row: never the patient again, since the read belongs to the case.
ClassMethod Reduced(row As %DynamicObject) As %DynamicObject [ Private ]
{
    Set r = {}
    For key = "source_event_id", "revision", "record_status", "encounter_authority", "encounter_id", "event_kind", "time_precision", "ward", "bed", "supersedes_event_id" {
        Do ..Copy(r, key, ..Text(row, key))
    }
    Do ..Copy(r, "event_time", ..Iso(..Text(row, "event_time_utc")))
    Do ..Copy(r, "source_recorded_at", ..Iso(..Text(row, "source_recorded_at_utc")))
    Do ..Copy(r, "source_modified_at", ..Iso(..Text(row, "source_modified_at_utc")))
    Quit r
}

ClassMethod Copy(r As %DynamicObject, key As %String, value As %String) [ Private ]
{
    If value = "" { Do r.%Set(key, "", "null") } Else { Do r.%Set(key, value) }
}

/// A key's value as text; "" for absent or null.
ClassMethod Text(o As %DynamicObject, key As %String) As %String [ Private ]
{
    If '$ISOBJECT(o) || 'o.%IsDefined(key) Quit ""
    If o.%GetTypeOf(key) = "null" Quit ""
    Quit o.%Get(key)
}

/// "2026-11-06 10:00:00" (a table's UTC time) as "2026-11-06T10:00:00Z"; "" when it is not one.
ClassMethod Iso(odbc As %String) As %String
{
    If odbc = "" Quit ""
    Set text = $EXTRACT(odbc, 1, 19)
    If text '? 4N1"-"2N1"-"2N1" "2N1":"2N1":"2N Quit ""
    Quit $TRANSLATE(text, " ", "T") _ "Z"
}

}
