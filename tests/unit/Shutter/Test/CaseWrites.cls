/// Writes to a case from several jobs (Shutter.Store.Case): a copy read before another job changed the case never
/// writes back over the change. Within one process IRIS hands out one copy per case, so the other job is played
/// by SQL updates of the stored row, as SetIncident and a transition elsewhere make them. The test case is saved under
/// its own public id, outside the case counter, and removed afterwards.
Class Shutter.Test.CaseWrites Extends %UnitTest.TestCase
{

Property CaseRowId As %String;

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "UT-CASEWRITES", c.OperationKey = "PAS^HOSP^MRN9002^ENC-9002^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.EncounterId = "ENC-9002", c.PatientId = "MRN9002", c.FailureKind = "delivery_failed"
    Set sc = c.%Save()
    Set ..CaseRowId = c.%Id()
    Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Set id = ..CaseRowId
    &sql(DELETE FROM Shutter_Store.CaseEvent WHERE "Case" = :id)
    Kill ^Shutter.Counter("event", id)
    Quit ##class(Shutter.Store.Case).%DeleteId(id)
}

Method Stored(column As %String) As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT " _ column _ " AS v FROM Shutter_Store.""Case"" WHERE ID = ?", ..CaseRowId)
    Quit $SELECT(rs.%Next(): rs.%Get("v"), 1: "")
}

Method Exec(sql As %String)
{
    Do ##class(%SQL.Statement).%ExecDirect(, sql, ..CaseRowId)
}

Method TestNoteKeepsAMembershipMadeElsewhere()
{
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    // Another job's incident detector makes the case a member after this copy was read.
    Do ..Exec("UPDATE Shutter_Store.""Case"" SET Incident = 424242 WHERE ID = ?")
    Do $$$AssertStatusOK(c.Note("note", "A note from a job holding the older copy"), "the note")
    Do $$$AssertEquals(..Stored("Incident"), 424242, "the membership survives the note")
    Do $$$AssertEquals(..Stored("Version"), 1, "a note never moves the version (the approve route compares it)")
}

Method TestNoteLeavesTheCopyUnchanged()
{
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Do $$$AssertStatusOK(c.Note("note", "A note from the evidence collector"), "the note")
    Do $$$AssertNotTrue(c.%IsModified(), "the copy is not marked changed by the note")
    // Another job moves the case on, then a snapshot made from the older copy is saved: it never writes the copy.
    Do ..Exec("UPDATE Shutter_Store.""Case"" SET State = 'blocked', Version = 2 WHERE ID = ?")
    Set snap = ##class(Shutter.Store.Snapshot).Begin(c, 300)
    Do $$$AssertStatusOK(snap.Seal({}), "the snapshot is sealed")
    Do $$$AssertEquals(..Stored("State"), "blocked", "the other job's state stands")
    Do $$$AssertEquals(..Stored("Version"), 2, "and its version")
    Set id = ..CaseRowId, sid = snap.%Id()
    &sql(DELETE FROM Shutter_Store.SnapshotItem WHERE Snapshot = :sid)
    Do ##class(Shutter.Store.Snapshot).%DeleteId(sid)
    Kill ^Shutter.Counter("snapshot", id)
}

Method TestTransitionKeepsAMembershipMadeElsewhere()
{
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Do ..Exec("UPDATE Shutter_Store.""Case"" SET Incident = 424242, CurrentSnapshot = 535353 WHERE ID = ?")
    Do $$$AssertStatusOK(c.Transition("collecting", "Collecting evidence"), "the transition")
    Do $$$AssertEquals(..Stored("Incident"), 424242, "the membership survives the whole save")
    Do $$$AssertEquals(..Stored("CurrentSnapshot"), 535353, "so does the current snapshot")
    Do $$$AssertEquals(c.IncidentGetObjectId(), 424242, "and the copy now shows it")
    Do $$$AssertEquals(..Stored("State"), "collecting", "the state moved")
    Do $$$AssertEquals(..Stored("Version"), 2, "with the version")
}

Method TestStaleTransitionChangesNothing()
{
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    // Another job moved the case after this copy was read.
    Do ..Exec("UPDATE Shutter_Store.""Case"" SET State = 'blocked', Version = 2 WHERE ID = ?")
    Set sc = c.Transition("investigating", "From the older copy")
    Do $$$AssertStatusNotOK(sc, "a copy older than the stored version is refused")
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Stale case version", "and says why")
    Do $$$AssertEquals(..Stored("State"), "blocked", "the other job's state stands")
    Do $$$AssertEquals(..Stored("Version"), 2, "and its version")
}

Method TestLeavingKeepsAParkedCase()
{
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Do ..Exec("UPDATE Shutter_Store.""Case"" SET Incident = 424242, State = 'grouped' WHERE ID = ?")
    Do $$$AssertStatusOK(c.SetIncident("", "grouped", .left), "the incident lets go")
    Do $$$AssertNotTrue(left, "a case that parked meanwhile stays")
    Do $$$AssertEquals(..Stored("Incident"), 424242, "its membership is kept")
    Do ..Exec("UPDATE Shutter_Store.""Case"" SET State = 'investigating' WHERE ID = ?")
    Do $$$AssertStatusOK(c.SetIncident("", "grouped", .left), "again, not parked")
    Do $$$AssertTrue(left, "a case not parked leaves")
    Do $$$AssertEquals(..Stored("Incident"), "", "its membership is gone")
}

}
