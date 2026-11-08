/// Warehouse history (docs/warehouse-history.md): the contract's checks on what the reader returned, the fixed queries on
/// the real tables, the stored read, and the proofs that it stays out of every decision. The tables are made here when
/// they are missing and removed afterwards, and rows are only ever those of this test's own dataset.
Class Shutter.Test.Warehouse Extends %UnitTest.TestCase
{

Parameter DATASET = "UT-WH";

Parameter CASEID = "UT-WAREHOUSE";

Parameter NOW = "2026-11-06T12:00:00Z";

Property MadeTables As %Boolean [ InitialExpression = 0 ];

Property CaseRowId As %String;

Method OnBeforeAllTests() As %Status
{
    If '##class(Shutter.Warehouse.Setup).TablesExist() {
        Set sc = ##class(Shutter.Warehouse.Setup).CreateTables()
        Quit:$$$ISERR(sc) sc
        Set ..MadeTables = 1
    }
    Do ..ClearRows()
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Do ..ClearRows()
    If ..MadeTables {
        Do ##class(%SQL.Statement).%ExecDirect(, "DROP TABLE ShutterWH.Movement")
        Do ##class(%SQL.Statement).%ExecDirect(, "DROP TABLE ShutterWH.Batch")
    }
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Do ..ClearRows()
    Do ..RemoveCase()
    Kill ^Shutter.Config("warehouse")
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = ..#CASEID, c.OperationKey = "PAS^HOSP^MRN9050^ENC-9050^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.EncounterId = "ENC-9050", c.PatientId = "MRN9050", c.PatientIdAuthority = "HOSP", c.FailureKind = "delivery_failed"
    Set c.State = "collecting", c.Headline = "A test case"
    Set c.OpenedAt = "2026-10-20T10:00:00Z", c.UpdatedAt = c.OpenedAt
    Set sc = c.%Save()
    Quit:$$$ISERR(sc) sc
    Set ..CaseRowId = c.%Id()
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..RemoveCase()
    Kill ^Shutter.Config("warehouse")
    Quit $$$OK
}

Method RemoveCase()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", ..#CASEID)
    While rs.%Next() { Do ##class(Shutter.Store.Case).PurgeCase(rs.%Get("ID")) }
}

Method ClearRows()
{
    If '##class(Shutter.Warehouse.Setup).TablesExist() Quit
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM ShutterWH.Movement WHERE DatasetId = ?", ..#DATASET)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM ShutterWH.Batch WHERE DatasetId = ?", ..#DATASET)
}

/// A manifest as the reader returns it, watermark an hour before NOW.
ClassMethod Manifest() As %DynamicObject
{
    Set m = {"dataset_id": (..#DATASET), "batch_id": "B1", "batch_sequence": 5, "dataset_generation": "G1", "source_system": "PAS", "receiver_reference": "the bed manager", "source_watermark_utc": "2026-11-06 11:00:00", "history_complete_from_utc": "2020-01-01 00:00:00", "published_at_utc": "2026-11-06 11:30:00", "published_rows": 1, "schema_version": 1}
    Do m.%Set("watermark_known", 1, "number")
    Quit m
}

ClassMethod Row(id As %String = "E1") As %DynamicObject
{
    Quit {"source_event_id": (id), "revision": 1, "record_status": "active", "patient_authority": "HOSP", "patient_id": "MRN9050", "encounter_authority": null, "encounter_id": "ENC-1", "event_kind": "transfer", "event_time_utc": "2026-11-01 10:00:00", "time_precision": "second", "source_recorded_at_utc": null, "source_modified_at_utc": null, "ward": "WARD-B", "bed": null, "supersedes_event_id": null}
}

ClassMethod Payload(rows As %DynamicArray = "") As %DynamicObject
{
    If '$ISOBJECT(rows) Set rows = [(..Row())]
    Set m = ..Manifest(), m."published_rows" = 1
    Quit {"query_version": "1", "manifest": (m), "present_rows": 1, "rows": (rows)}
}

ClassMethod Assess(payload As %DynamicObject, last As %DynamicObject = "", maxAge As %Integer = 360, showOlder As %Boolean = 0) As %DynamicObject
{
    Quit ##class(Shutter.Warehouse.Contract).Assess(payload, ..#DATASET, "HOSP", "MRN9050", ..#NOW, maxAge, showOlder, last)
}

// ---- the contract ----

Method TestAGoodReadShowsItsRowsWithTheirProvenance()
{
    Set a = ..Assess(..Payload())
    Do $$$AssertEquals(a.status, "ok")
    Do $$$AssertEquals(a.freshness, "within")
    Do $$$AssertEquals(a."age_minutes", 60)
    Do $$$AssertEquals(a."source_watermark", "2026-11-06T11:00:00Z", "the watermark is a UTC time")
    Do $$$AssertEquals(a.rows.%Size(), 1)
    Do $$$AssertEquals(a.rows.%Get(0).ward, "WARD-B")
    Do $$$AssertEquals(a.rows.%Get(0)."event_time", "2026-11-01T10:00:00Z")
    Do $$$AssertNotTrue(a.rows.%Get(0).%IsDefined("patient_id"), "a kept row does not repeat the patient")
    Do $$$AssertTrue($EXTRACT(a."result_digest", 1, 7) = "sha256:" || (a."result_digest" '= ""), "the result has a digest")
}

Method TestNoBatchIsSaidAndNoRowsIsNotAbsence()
{
    Set a = ..Assess({"query_version": "1", "manifest": null, "present_rows": 0, "rows": []})
    Do $$$AssertEquals(a.status, "no_batch")
    Set a = ..Assess(..Payload([]))
    Do $$$AssertEquals(a.status, "no_rows", "an empty answer from a batch is only that")
    Do $$$AssertEquals(a.rows.%Size(), 0)
}

/// A fresh publication of old data: PublishedAt is minutes ago and the watermark is days old. Age counts from the watermark.
Method TestAFreshPublicationOfOldDataIsOld()
{
    Set p = ..Payload()
    Set p.manifest."source_watermark_utc" = "2026-11-01 11:00:00"
    Set a = ..Assess(p)
    Do $$$AssertEquals(a.status, "withheld")
    Do $$$AssertEquals(a.freshness, "older")
    Do $$$AssertEquals(a.rows.%Size(), 0, "not shown unless the site chose to")
    Set a = ..Assess(p, "", 360, 1)
    Do $$$AssertEquals(a.status, "ok", "shown when the site chose to, and marked")
    Do $$$AssertEquals(a.freshness, "older")
    Do $$$AssertEquals(a.rows.%Size(), 1)
}

Method TestAnUnknownWatermarkHasAnUnknownAge()
{
    Set p = ..Payload()
    Set p.manifest."watermark_known" = 0
    Do p.manifest.%Set("source_watermark_utc", "", "null")
    Set a = ..Assess(p)
    Do $$$AssertEquals(a.status, "withheld")
    Do $$$AssertEquals(a.freshness, "unknown")
    Do $$$AssertEquals(a."age_minutes", "")
    // Claimed known and given no time, or a time still to come: the manifest cannot be believed
    Set p = ..Payload()
    Do p.manifest.%Set("source_watermark_utc", "", "null")
    Do $$$AssertEquals(..Assess(p).category, "watermark_inconsistent")
    Set p = ..Payload()
    Set p.manifest."source_watermark_utc" = "2026-11-07 12:00:00"
    Do $$$AssertEquals(..Assess(p).category, "watermark_in_future")
}

/// A batch marked ready before its rows were all there.
Method TestAHalfPublishedBatchIsRefused()
{
    Set p = ..Payload()
    Set p.manifest."published_rows" = 40
    Set a = ..Assess(p)
    Do $$$AssertEquals(a.status, "invalid")
    Do $$$AssertEquals(a.category, "row_count_mismatch")
    Do $$$AssertEquals(a.rows.%Size(), 0)
}

Method TestARowOfAnotherPatientRefusesTheWholeRead()
{
    For pair = "OTHER|MRN9050", "HOSP|mrn9050", "HOSP|0MRN9050" {
        Set row = ..Row()
        Set row."patient_authority" = $PIECE(pair, "|", 1), row."patient_id" = $PIECE(pair, "|", 2)
        Set a = ..Assess(..Payload([(row)]))
        Do $$$AssertEquals(a.status, "invalid", pair)
        Do $$$AssertEquals(a.category, "identity_mismatch", pair)
        Do $$$AssertEquals(a.rows.%Size(), 0, "nothing of it is kept: " _ pair)
    }
}

Method TestABadRowOrManifestIsRefused()
{
    Set row = ..Row(), row."record_status" = "maybe"
    Do $$$AssertEquals(..Assess(..Payload([(row)])).category, "row_invalid")
    Set row = ..Row(), row."event_kind" = "teleport"
    Do $$$AssertEquals(..Assess(..Payload([(row)])).category, "row_invalid")
    Set p = ..Payload(), p.manifest."schema_version" = 2
    Do $$$AssertEquals(..Assess(p).category, "schema_version")
    Set p = ..Payload(), p.manifest."dataset_id" = "ANOTHER"
    Do $$$AssertEquals(..Assess(p).category, "wrong_dataset")
}

Method TestCancelledAndRetractedRowsStayVisible()
{
    Set c = ..Row("E1"), c."record_status" = "cancelled"
    Set r = ..Row("E2"), r."record_status" = "retracted"
    Set p = ..Payload([(c), (r)]), p.manifest."published_rows" = 2, p."present_rows" = 2
    Set a = ..Assess(p)
    Do $$$AssertEquals(a.status, "ok")
    Do $$$AssertEquals(a.rows.%Get(0)."record_status", "cancelled")
    Do $$$AssertEquals(a.rows.%Get(1)."record_status", "retracted")
}

Method TestRow201MeansCutShort()
{
    Set rows = []
    For i = 1:1:201 { Do rows.%Push(..Row("E" _ i)) }
    Set p = ..Payload(rows), p.manifest."published_rows" = 201, p."present_rows" = 201
    Set a = ..Assess(p)
    Do $$$AssertEquals(a.status, "ok")
    Do $$$AssertEquals(a.rows.%Size(), 200)
    Do $$$AssertTrue(a.truncated, "row 201 sets truncated")
    Do rows.%Remove(200)
    Do $$$AssertNotTrue(..Assess(p).truncated, "exactly 200 is not cut short")
}

Method TestARestoredExportIsMarked()
{
    Set a = ..Assess(..Payload(), {"generation": "G0", "sequence": 90})
    Do $$$AssertEquals(a.status, "ok", "a new generation may start its sequence again")
    Do $$$AssertTrue(a."generation_changed", "and is marked")
    Set a = ..Assess(..Payload(), {"generation": "G1", "sequence": 6})
    Do $$$AssertEquals(a.status, "invalid", "the same generation going backwards is an export restored")
    Do $$$AssertEquals(a.category, "sequence_regressed")
    Do $$$AssertEquals(a.rows.%Size(), 0)
    Set a = ..Assess(..Payload(), {"generation": "G1", "sequence": 5})
    Do $$$AssertEquals(a.status, "ok", "the same batch again is fine")
    Do $$$AssertNotTrue(a."generation_changed")
}

// ---- the fixed queries, on the real tables ----

Method Publish(batch As %String, sequence As %Integer, generation As %String = "G1", ready As %Boolean = 1, published As %String = "2026-11-06 11:30:00", rows As %Integer = 0) As %Status
{
    Set sql = "INSERT INTO ShutterWH.Batch (DatasetId,BatchId,BatchSequence,DatasetGeneration,SourceSystem,ReceiverReference,ExtractStartedAtUTC,ExtractFinishedAtUTC,SourceWatermarkUTC,WatermarkKnown,HistoryCompleteFromUTC,PublishedAtUTC,Ready,PublishedRows,SchemaVersion) VALUES (?,?,?,?,'PAS','the bed manager','2026-11-06 11:00:00','2026-11-06 11:10:00','2026-11-06 11:00:00',1,'2020-01-01 00:00:00',?,?,?,1)"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, ..#DATASET, batch, sequence, generation, published, ready, rows)
    Do $$$AssertTrue(rs.%SQLCODE = 0, "batch " _ batch _ ": " _ rs.%SQLCODE _ " " _ rs.%Message)
    Quit $$$OK
}

Method Move(batch As %String, event As %String, authority As %String = "HOSP", patient As %String = "MRN9050", time As %String = "2026-11-01 10:00:00") As %Status
{
    Set sql = "INSERT INTO ShutterWH.Movement (DatasetId,BatchId,SourceEventId,Revision,RecordStatus,PatientAuthority,PatientId,EventKind,EventTimeUTC,TimePrecision,Ward) VALUES (?,?,?,1,'active',?,?,'transfer',?,'second','WARD-B')"
    Set rs = ##class(%SQL.Statement).%ExecDirect(, sql, ..#DATASET, batch, event, authority, patient, time)
    Do $$$AssertTrue(rs.%SQLCODE = 0, "row " _ event _ ": " _ rs.%SQLCODE _ " " _ rs.%Message)
    Quit $$$OK
}

Method TestAnUnreadyBatchIsNeverRead()
{
    Do ..Publish("B1", 1, "G1", 1, "2026-11-06 09:00:00", 1)
    Do ..Move("B1", "E1")
    Do ..Publish("B2", 2, "G1", 0, "2026-11-06 11:00:00", 1)
    Do ..Move("B2", "E2")
    Set out = ##class(Shutter.Warehouse.Reader).Read(..#DATASET, "HOSP", "MRN9050")
    Do $$$AssertEquals(out.manifest."batch_id", "B1")
    Do $$$AssertEquals(out.rows.%Size(), 1)
    Do $$$AssertEquals(out.rows.%Get(0)."source_event_id", "E1")
    Do $$$AssertEquals(out."present_rows", 1)
}

/// A rebuilt export starts its sequence again and still becomes the batch read.
Method TestANewGenerationIsReadThoughItsSequenceStartsAgain()
{
    Do ..Publish("OLD", 90, "G1", 1, "2026-11-01 09:00:00")
    Do ..Publish("NEW", 1, "G2", 1, "2026-11-06 09:00:00")
    Set out = ##class(Shutter.Warehouse.Reader).Read(..#DATASET, "HOSP", "MRN9050")
    Do $$$AssertEquals(out.manifest."batch_id", "NEW")
}

Method TestRowsMatchExactly()
{
    Do ..Publish("B1", 1, "G1", 1, , 5)
    Do ..Move("B1", "E1", "HOSP", "MRN9050")
    Do ..Move("B1", "E2", "OTHER", "MRN9050")
    Do ..Move("B1", "E3", "HOSP", "mrn9050")
    Do ..Move("B1", "E4", "HOSP", "0MRN9050")
    Do ..Move("B1", "E5", "hosp", "MRN9050")
    Set out = ##class(Shutter.Warehouse.Reader).Read(..#DATASET, "HOSP", "MRN9050")
    Do $$$AssertEquals(out.rows.%Size(), 1, "the same id under another authority, another case or a leading zero is another patient")
    Do $$$AssertEquals(out.rows.%Get(0)."source_event_id", "E1")
    Do $$$AssertEquals(out."present_rows", 5)
    Set out = ##class(Shutter.Warehouse.Reader).Read(..#DATASET, "HOSP", "0MRN9050")
    Do $$$AssertEquals(out.rows.%Get(0)."source_event_id", "E4")
}

Method TestUnknownTimesStayUnknownAndSortLast()
{
    Do ..Publish("B1", 1, "G1", 1, , 2)
    Do ..Move("B1", "NOTIME", , , "")
    Do ..Move("B1", "TIMED")
    Set out = ##class(Shutter.Warehouse.Reader).Read(..#DATASET, "HOSP", "MRN9050")
    Do $$$AssertEquals(out.rows.%Get(0)."source_event_id", "TIMED")
    Do $$$AssertEquals(out.rows.%Get(1)."source_event_id", "NOTIME")
    Do $$$AssertEquals(out.rows.%Get(1).%GetTypeOf("event_time_utc"), "null")
}

Method TestTheQueryReturnsRow201()
{
    Do ..Publish("B1", 1, "G1", 1, , 201)
    For i = 1:1:201 { Do ..Move("B1", "E" _ i) }
    Set out = ##class(Shutter.Warehouse.Reader).Read(..#DATASET, "HOSP", "MRN9050")
    Do $$$AssertEquals(out.rows.%Size(), 201, "the row that shows the list is cut short")
    Set a = ##class(Shutter.Warehouse.Contract).Assess(out, ..#DATASET, "HOSP", "MRN9050", ..#NOW, 360, 0, "")
    Do $$$AssertEquals(a.rows.%Size(), 200)
    Do $$$AssertTrue(a.truncated)
}

// ---- the boundary: what the reader's identity can do ----

/// The real role, user and web application, and a background job signed in as that user (a terminal is refused once it
/// has changed identity, and a job keeps this process's own). Every write must fail, as must any table but the two.
Method TestTheReaderIdentityCanOnlySelect()
{
    Set password = "Ut-" _ $SYSTEM.Encryption.Base64Encode($SYSTEM.Encryption.GenCryptRand(12))
    Set free = '##class(Shutter.Warehouse.Setup).IdentityExists()
    If 'free Do $$$AssertSkipped("the reader is already set up on this instance") Quit
    Do $$$AssertEquals(##class(Shutter.Warehouse.Setup).Install(password), "ok")
    Do ..Publish("B1", 1, "G1", 1, , 1)
    Do ..Move("B1", "E1")
    Kill ^CacheTemp.ShutterWarehouseProof
    Job ##class(Shutter.Test.Warehouse).AsReader(password)
    For i = 1:1:200 { Quit:$DATA(^CacheTemp.ShutterWarehouseProof("done"))  Hang 0.05 }
    Do $$$AssertEquals($GET(^CacheTemp.ShutterWarehouseProof("done")), 1, "the job finished")
    Do $$$AssertEquals($GET(^CacheTemp.ShutterWarehouseProof("user")), ##class(Shutter.Warehouse.Setup).#READER, "as the reader")
    Do $$$AssertEquals($GET(^CacheTemp.ShutterWarehouseProof("read")), "B1|1|E1", "it reads through the fixed queries")
    For statement = "insert", "update", "delete", "drop", "create", "store", "dictionary" {
        Do $$$AssertEquals($GET(^CacheTemp.ShutterWarehouseProof(statement)), -99, statement _ " is refused: " _ $GET(^CacheTemp.ShutterWarehouseProof(statement, "message")))
    }
    // Skipping the privilege check is no way round: the role has nothing to write to the database with
    Do $$$AssertEquals($GET(^CacheTemp.ShutterWarehouseProof("nopriv")), "PROTECT", "a write that skips the SQL check meets the database's own")
    Do $$$AssertEquals($GET(^CacheTemp.ShutterWarehouseProof("global")), "PROTECT", "and so does a global")
    Kill ^CacheTemp.ShutterWarehouseProof
    // Nothing moved
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM ShutterWH.Batch WHERE DatasetId = ? AND Ready = 1", ..#DATASET)
    Do rs.%Next()
    Do $$$AssertEquals(rs.%Get("n"), 1, "the batch is as it was")
    Do $$$AssertEquals(##class(Shutter.Warehouse.Setup).Remove(), "ok")
    Do $$$AssertNotTrue(##class(Shutter.Warehouse.Setup).IdentityExists(), "Remove leaves no user")
    Do $$$AssertTrue(##class(Shutter.Warehouse.Setup).TablesExist(), "and leaves the tables")
}

/// The background job of TestTheReaderIdentityCanOnlySelect, signed in as the reader. ^CacheTemp is in IRISTEMP, the one
/// place it may write.
ClassMethod AsReader(password As %String)
{
    Set key = "^CacheTemp.ShutterWarehouseProof"
    Try {
        If '$SYSTEM.Security.Login(##class(Shutter.Warehouse.Setup).#READER, password) Set @key@("user") = "not signed in" Quit
        Set @key@("user") = $USERNAME
        Set out = ##class(Shutter.Warehouse.Reader).Read(..#DATASET, "HOSP", "MRN9050")
        Set @key@("read") = out.manifest."batch_id" _ "|" _ out."present_rows" _ "|" _ out.rows.%Get(0)."source_event_id"
        Set statements("insert") = "INSERT INTO ShutterWH.Movement (DatasetId,BatchId,SourceEventId,Revision,RecordStatus,PatientAuthority,PatientId,EventKind,TimePrecision) VALUES ('" _ ..#DATASET _ "','B1','X',1,'active','A','B','other','unknown')"
        Set statements("update") = "UPDATE ShutterWH.Batch SET Ready = 0"
        Set statements("delete") = "DELETE FROM ShutterWH.Movement"
        Set statements("drop") = "DROP TABLE ShutterWH.Movement"
        Set statements("create") = "CREATE TABLE ShutterWH.Another (A INT)"
        Set statements("store") = "SELECT TOP 1 PatientId FROM Shutter_Store.""Case"""
        Set statements("dictionary") = "SELECT TOP 1 Name FROM %Dictionary.ClassDefinition"
        Set name = ""
        For {
            Set name = $ORDER(statements(name))
            Quit:name=""
            Set rs = ##class(%SQL.Statement).%ExecDirect(, statements(name))
            Set @key@(name) = rs.%SQLCODE, @key@(name, "message") = $EXTRACT(rs.%Message, 1, 100)
        }
        Try {
            Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "UPDATE ShutterWH.Batch SET Ready = 0")
            Set @key@("nopriv") = $SELECT(rs.%Message [ "PROTECT": "PROTECT", 1: rs.%SQLCODE)
        } Catch ex {
            Set @key@("nopriv") = $SELECT(ex.DisplayString() [ "PROTECT": "PROTECT", 1: ex.DisplayString())
        }
        Try {
            Set ^ShutterWarehouseProbe = 1
            Set @key@("global") = "written"
        } Catch ex {
            Set @key@("global") = $SELECT(ex.Name [ "PROTECT": "PROTECT", 1: ex.Name)
        }
    } Catch ex {
        Set @key@("error") = ex.DisplayString()
    }
    Set @key@("done") = 1
}

// ---- the stored read ----

Method TestAReadIsStoredWithItsProvenanceAndGoesWithTheCase()
{
    Set case = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set a = ..Assess(..Payload())
    Set sc = ##class(Shutter.Store.WarehouseRead).Record(case, a, ..#DATASET, "a.reader", ..#NOW, .read)
    Do $$$AssertStatusOK(sc)
    Set view = ##class(Shutter.Store.WarehouseRead).Latest(case).View()
    Do $$$AssertEquals(view.status, "ok")
    Do $$$AssertEquals(view.batch, "B1")
    Do $$$AssertEquals(view.sequence, 5)
    Do $$$AssertEquals(view.readBy, "a.reader")
    Do $$$AssertEquals(view.rows.%Size(), 1)
    Do $$$AssertEquals(view.queryVersion, "1")
    // The next read of the dataset compares with this one
    Set last = ##class(Shutter.Store.WarehouseRead).LastSeen(..#DATASET)
    Do $$$AssertEquals(last.generation, "G1")
    Do $$$AssertEquals(last.sequence, 5)
    // No trace on the case's own record
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", ..CaseRowId)
    Do rs.%Next()
    Do $$$AssertEquals(rs.%Get("n"), 0, "no event on the timeline")
    Do $$$AssertStatusOK(##class(Shutter.Store.Case).PurgeCase(..CaseRowId))
    Set ..CaseRowId = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM Shutter_Store.WarehouseRead WHERE Dataset = ?", ..#DATASET)
    Do rs.%Next()
    Do $$$AssertEquals(rs.%Get("n"), 0, "the patient's rows go when the case goes")
}

/// A case with no authority or no patient id is not looked up: no id is guessed, and nothing is called.
Method TestACaseWithoutAnIdentityIsNotLookedUp()
{
    Do ##class(Shutter.Warehouse.Client).Configure(..#DATASET, 1, 360, 0, "localhost", 1)
    Set case = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set case.PatientIdAuthority = ""
    Do $$$AssertStatusOK(case.%Save())
    Set read = ##class(Shutter.Warehouse.Client).ReadForCase(case, "a.reader")
    Do $$$AssertEquals(read.View().status, "no_identity")
}

/// Nothing listening: the supplement is unavailable and says so.
Method TestAnUnavailableReaderIsOnlyThat()
{
    Do ##class(Shutter.Warehouse.Client).Configure(..#DATASET, 1, 360, 0, "localhost", 1)
    Set case = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set read = ##class(Shutter.Warehouse.Client).ReadForCase(case, "a.reader")
    Set view = read.View()
    Do $$$AssertEquals(view.status, "unavailable")
    Do $$$AssertEquals(view.rows.%Size(), 0)
}

// ---- it stays out of every decision ----

Method TestOffByDefault()
{
    Do $$$AssertNotTrue(##class(Shutter.Warehouse.Client).Enabled(), "nothing configured is off")
    Set profile = ##class(Shutter.Store.SiteProfile).Default()
    Do $$$AssertNotTrue(profile.%IsDefined("warehouse_history"), "the site profile does not carry it")
}

/// The site profile's version is part of what an approval rests on, so a setting kept there would revoke every waiting
/// approval when it changed. Switching this on keeps the version and so the approval; the second half is the control:
/// a change that does move the version does revoke it, so the comparison can tell the two apart.
Method TestEnablingChangesNoApprovalAndAControlDoes()
{
    Set before = ##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0)
    Set approval = ##class(Shutter.Store.Approval).%New()
    Set approval.Decision = "approved", approval.ExpiresAt = "2099-01-01T00:00:00Z", approval.PlanDigest = "d", approval.PolicyVersion = "p", approval.SiteProfileVersion = before
    Set plan = ##class(Shutter.Store.Plan).%New()
    Set plan.Digest = "d"
    Do $$$AssertEquals(approval.InvalidReason(plan, "", "p", ""), "", "valid before")
    Do ##class(Shutter.Warehouse.Client).Configure(..#DATASET, 1, 360, 0, "localhost", 1)
    Do $$$AssertTrue(##class(Shutter.Warehouse.Client).Enabled())
    Do $$$AssertEquals(##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0), before, "the profile's version did not move")
    Do $$$AssertEquals(approval.InvalidReason(plan, "", "p", ""), "", "valid after")
    Set approval.SiteProfileVersion = "not " _ before
    Do $$$AssertEquals(approval.InvalidReason(plan, "", "p", ""), "site_profile_changed", "the control: a moved version revokes")
}

/// The classes that decide name nothing of this feature, and neither do those that feed them.
Method TestTheDecidingClassesNeverNameIt()
{
    For cls = "Shutter.Operation.Gate", "Shutter.Operation.Verify", "Shutter.Operation.Evidence", "Shutter.Catalogue.Matcher", "Shutter.Catalogue.Entry", "Shutter.Process.CaseWorkflow", "Shutter.Process.Question", "Shutter.Process.IncidentWorkflow", "Shutter.Index.Timeline", "Shutter.Store.Approval", "Shutter.Store.Plan", "Shutter.Store.Snapshot", "Shutter.Store.CaseEvent", "Shutter.Tools.Evidence", "Shutter.Util.WhatIf", "Shutter.Publish.Tools" {
        // Tools.Evidence and Publish.Tools are only in the whole package, not in the core
        If '##class(%Dictionary.CompiledClass).%ExistsId(cls) Continue
        Do ..NamesNothing(cls)
    }
    Do $$$AssertNotTrue(##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Operation.WarehouseHistory"), "no production item")
}

Method NamesNothing(cls As %String)
{
    Kill lines
    Set sc = ##class(%Compiler.UDL.TextServices).GetTextAsArray($NAMESPACE, cls, .lines)
    Do $$$AssertStatusOK(sc, cls _ " read")
    Set hit = ""
    For i = 1:1:+$GET(lines(0)) {
        Set line = $ZCONVERT($GET(lines(i)), "L")
        If (line [ "shutter.warehouse") || (line [ "warehouseread") || (line [ "shutterwh") Set hit = i Quit
    }
    Do $$$AssertEquals(hit, "", cls _ " names nothing of warehouse history")
}

}
