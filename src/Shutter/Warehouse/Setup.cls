/// Sets up warehouse history (docs/warehouse-history.md) for a site that asks for it. Nothing here runs at Shutter's own
/// install: until an administrator calls Install and Enable there are no tables, no reader and no user, and the case
/// page shows nothing of it. Run from the namespace Shutter is installed in.
Class Shutter.Warehouse.Setup [ Abstract ]
{

Parameter ROLE = "Shutter_WarehouseReader";

Parameter READER = "ShutterWarehouseReader";

Parameter RESOURCE = "Shutter_WarehouseRead";

/// The two tables when missing, the reader's resource, role, user and web application, its SELECT grants and the
/// stored credential. It stays off until Enable. The role reads this namespace's databases and writes nothing: the
/// reader's identity can SELECT on the two tables and is refused everything else. Returns "ok" or the error.
ClassMethod Install(password As %String) As %String
{
    If '$SYSTEM.Security.Check("%Admin_Secure", "USE") Quit "%Admin_Secure is required"
    If $LENGTH(password) < 12 Quit "ERROR: give the reader a password of at least 12 characters"
    Set ns = $NAMESPACE
    Set sc = ..CreateTables()
    If $$$ISOK(sc) Set sc = ..CreateIdentity(ns, password)
    If $$$ISOK(sc) Set sc = ..Grant()
    If $$$ISOK(sc) Set sc = ##class(Ens.Config.Credentials).SetCredential(##class(Shutter.Warehouse.Client).#CREDENTIAL, ..#READER, password, 1)
    If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
    Quit "ok"
}

/// Switch on the panel for a dataset. maxAgeMinutes: rows older than this by the watermark, or of unknown age, are withheld
/// unless showOlder is 1. host and port are this instance's web server as Shutter's own process reaches it.
ClassMethod Enable(dataset As %String, maxAgeMinutes As %Integer = 360, showOlder As %Boolean = 0, host As %String = "localhost", port As %Integer = 52773) As %String
{
    If '$SYSTEM.Security.Check("%Admin_Secure", "USE") Quit "%Admin_Secure is required"
    If (dataset = "") || ($LENGTH(dataset) > 64) Quit "ERROR: name the dataset, 64 characters at most"
    Do ##class(Shutter.Warehouse.Client).Configure(dataset, 1, maxAgeMinutes, showOlder, host, port)
    Quit "ok"
}

/// Switch off the panel. The stored reads stay with their cases, unread by anything but the case page's panel, which is gone.
ClassMethod Disable() As %String
{
    If '$SYSTEM.Security.Check("%Admin_Secure", "USE") Quit "%Admin_Secure is required"
    Set ^Shutter.Config("warehouse", "enabled") = 0
    Quit "ok"
}

/// Take away what Install made, but not the tables: they and their rows are the site's. Returns "ok" or the error.
ClassMethod Remove() As %String
{
    If '$SYSTEM.Security.Check("%Admin_Secure", "USE") Quit "%Admin_Secure is required"
    Set ns = $NAMESPACE
    Kill ^Shutter.Config("warehouse"), ^Shutter.Config("webapp", ##class(Shutter.Warehouse.Client).#READERPATH)
    If ##class(Ens.Config.Credentials).%ExistsId(##class(Shutter.Warehouse.Client).#CREDENTIAL) Do ##class(Ens.Config.Credentials).%DeleteId(##class(Shutter.Warehouse.Client).#CREDENTIAL)
    Set path = ##class(Shutter.Warehouse.Client).#READERPATH
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If ##class(Security.Applications).Exists(path) Do ##class(Security.Applications).Delete(path)
    If ##class(Security.Users).Exists(..#READER) Do ##class(Security.Users).Delete(..#READER)
    If ##class(Security.Roles).Exists(..#ROLE) Do ##class(Security.Roles).Delete(..#ROLE)
    If ##class(Security.Resources).Exists(..#RESOURCE) Do ##class(Security.Resources).Delete(..#RESOURCE)
    Quit "ok"
}

/// Whether Install's user is on this instance.
ClassMethod IdentityExists() As %Boolean
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Quit ''##class(Security.Users).Exists(..#READER)
}

ClassMethod TablesExist() As %Boolean
{
    Quit ##class(%Dictionary.CompiledClass).%ExistsId("ShutterWH.Batch") && ##class(%Dictionary.CompiledClass).%ExistsId("ShutterWH.Movement")
}

/// The tables as docs/warehouse-history.md gives them, when they are not there yet.
ClassMethod CreateTables() As %Status
{
    If ..TablesExist() Quit $$$OK
    Set sc = $$$OK
    For i = 1:1:3 {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, ..Ddl(i))
        If rs.%SQLCODE < 0 Set sc = $$$ERROR($$$GeneralError, "SQLCODE " _ rs.%SQLCODE _ ": " _ rs.%Message) Quit
    }
    Quit sc
}

/// One statement of the tables' definition (tests/e2e/warehouse_check.py compares them with the specification).
ClassMethod Ddl(n As %Integer) As %String [ Private ]
{
    If n = 1 Quit "CREATE TABLE ShutterWH.Batch (DatasetId VARCHAR(64) COLLATE %EXACT NOT NULL, BatchId VARCHAR(64) COLLATE %EXACT NOT NULL, BatchSequence BIGINT NOT NULL, DatasetGeneration VARCHAR(64) COLLATE %EXACT NOT NULL, SourceSystem VARCHAR(100) NOT NULL, ReceiverReference VARCHAR(128) NOT NULL, ExtractStartedAtUTC TIMESTAMP NOT NULL, ExtractFinishedAtUTC TIMESTAMP NOT NULL, SourceWatermarkUTC TIMESTAMP, WatermarkKnown BIT NOT NULL, HistoryCompleteFromUTC TIMESTAMP, PublishedAtUTC TIMESTAMP NOT NULL, Ready BIT NOT NULL, PublishedRows BIGINT NOT NULL, SchemaVersion INTEGER NOT NULL, CONSTRAINT BatchPK PRIMARY KEY (DatasetId, BatchId), CONSTRAINT BatchSequenceKey UNIQUE (DatasetId, DatasetGeneration, BatchSequence))"
    If n = 2 Quit "CREATE TABLE ShutterWH.Movement (DatasetId VARCHAR(64) COLLATE %EXACT NOT NULL, BatchId VARCHAR(64) COLLATE %EXACT NOT NULL, SourceEventId VARCHAR(160) COLLATE %EXACT NOT NULL, Revision INTEGER NOT NULL, RecordStatus VARCHAR(16) NOT NULL, PatientAuthority VARCHAR(100) COLLATE %EXACT NOT NULL, PatientId VARCHAR(160) COLLATE %EXACT NOT NULL, EncounterAuthority VARCHAR(100) COLLATE %EXACT, EncounterId VARCHAR(160) COLLATE %EXACT, EventKind VARCHAR(32) NOT NULL, EventTimeUTC TIMESTAMP, TimePrecision VARCHAR(16) NOT NULL, SourceRecordedAtUTC TIMESTAMP, SourceModifiedAtUTC TIMESTAMP, Ward VARCHAR(100), Bed VARCHAR(100), SupersedesEventId VARCHAR(160) COLLATE %EXACT, CONSTRAINT MovementPK PRIMARY KEY (DatasetId, BatchId, SourceEventId), CONSTRAINT MovementBatchFK FOREIGN KEY (DatasetId, BatchId) REFERENCES ShutterWH.Batch (DatasetId, BatchId))"
    Quit "CREATE INDEX MovementPatient ON ShutterWH.Movement (DatasetId, BatchId, PatientAuthority, PatientId)"
}

/// The reader's resource, its role with read on this namespace's databases and nothing to write with, its user, and the
/// web application, which takes a password and requires the resource.
ClassMethod CreateIdentity(ns As %String, password As %String) As %Status [ Private ]
{
    Set db = ##class(Shutter.Setup).DatabaseResource(ns), code = ##class(Shutter.Setup).DatabaseResource(ns, 1)
    Set resources = ..#RESOURCE _ ":U," _ db _ ":R" _ $SELECT((code '= "") && (code '= db): "," _ code _ ":R", 1: "")
    Set path = ##class(Shutter.Warehouse.Client).#READERPATH
    Set ^Shutter.Config("webapp", path) = 1
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set sc = $$$OK
    If '##class(Security.Resources).Exists(..#RESOURCE) {
        Set sc = ##class(Security.Resources).Create(..#RESOURCE, "Shutter: call the warehouse history reader", "")
        Quit:$$$ISERR(sc) sc
    }
    If ##class(Security.Roles).Exists(..#ROLE) {
        Set props("Description") = "Shutter: the warehouse history reader, read only", props("Resources") = resources
        Set sc = ##class(Security.Roles).Modify(..#ROLE, .props)
    } Else {
        Set sc = ##class(Security.Roles).Create(..#ROLE, "Shutter: the warehouse history reader, read only", resources)
    }
    Quit:$$$ISERR(sc) sc
    Kill props
    If ##class(Security.Users).Exists(..#READER) {
        Set props("Roles") = ..#ROLE, props("Password") = password, props("Enabled") = 1, props("ChangePassword") = 0, props("PasswordNeverExpires") = 1
        Set sc = ##class(Security.Users).Modify(..#READER, .props)
    } Else {
        Set sc = ##class(Security.Users).Create(..#READER, ..#ROLE, password, "Shutter warehouse history reader", ns, "", "", 0, 1, "Reads the warehouse history tables only")
    }
    Quit:$$$ISERR(sc) sc
    Kill props
    Set props("NameSpace") = ns
    Set props("Description") = "Shutter: the warehouse history reader"
    Set props("Enabled") = 1
    Set props("AutheEnabled") = 32
    Set props("DispatchClass") = "Shutter.Warehouse.Reader"
    Set props("Resource") = ..#RESOURCE
    Set props("UseCookies") = 0
    If ##class(Security.Applications).Exists(path) Quit ##class(Security.Applications).Modify(path, .props)
    Quit ##class(Security.Applications).Create(path, .props)
}

/// SELECT on the two tables, in this namespace, and no other privilege.
ClassMethod Grant() As %Status [ Private ]
{
    For table = "ShutterWH.Batch", "ShutterWH.Movement" {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "GRANT SELECT ON " _ table _ " TO " _ ..#ROLE)
        If rs.%SQLCODE < 0 Quit
    }
    If rs.%SQLCODE < 0 Quit $$$ERROR($$$GeneralError, "GRANT failed: SQLCODE " _ rs.%SQLCODE _ ": " _ rs.%Message)
    Quit $$$OK
}

}
