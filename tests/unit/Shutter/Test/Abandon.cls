/// Abandoning a case the workflow left in a working state (Shutter.Store.Case.Abandon, InFlight and MarkOpenAtStart;
/// CONTRACTS 5 and 12). Table-free, as CaseWrites: the test case UT-ABANDON is saved in collecting with its state event,
/// under its own public id outside the case counter, and removed with everything made for it afterwards. Nothing here
/// needs a production. Message headers cannot be made safely in a unit test, so InFlight is tested on a case with no
/// workflow session, where the last state event's age decides; the header rule runs on a production only.
/// MarkOpenAtStart notes every case in a working state on the instance, this one included: on a shared instance the
/// other working cases get the start note too.
Class Shutter.Test.Abandon Extends %UnitTest.TestCase
{

Parameter CASEID = "UT-ABANDON";

Property CaseRowId As %String;

Method OnBeforeAllTests() As %Status
{
    // Rows a run that stopped half-way may have left.
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", ..#CASEID)
    While rs.%Next() { Do ..Purge(rs.%Get("ID")) }
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = ..#CASEID, c.OperationKey = "PAS^HOSP^MRN9004^ENC-9004^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.EncounterId = "ENC-9004", c.PatientId = "MRN9004", c.FailureKind = "delivery_failed"
    Set c.State = "collecting", c.Headline = "The transfer to WARD-B of 2026-10-15 08:20:00 for encounter ENC-9004 was not delivered"
    Set c.OpenedAt = "2026-10-20T10:00:00Z", c.UpdatedAt = c.OpenedAt
    Set sc = c.%Save()
    Quit:$$$ISERR(sc) sc
    Set ..CaseRowId = c.%Id()
    // The workflow's last step: the state event into collecting, written now.
    Quit ##class(Shutter.Store.CaseEvent).Append(c, "state", "detected", "collecting", "Collecting evidence", "system")
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..Purge(..CaseRowId)
    Quit $$$OK
}

/// Deletes the test case's approvals, plans, escalations and events, its counters and the case itself.
ClassMethod Purge(id As %String)
{
    For table = "Shutter_Store.Approval", "Shutter_Store.Plan", "Shutter_Store.Escalation", "Shutter_Store.CaseEvent" {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ table _ " WHERE ""Case"" = ?", id)
    }
    Kill ^Shutter.Counter("event", id), ^Shutter.Counter("plan", id)
    If ##class(Shutter.Store.Case).%ExistsId(id) Do ##class(Shutter.Store.Case).%DeleteId(id)
}

// ---- the abandon ----

/// A working case with no session whose last step is 20 minutes old: nothing is in flight, and the abandon fails it with
/// disposition abandoned, the headline and outcome, a state event by the approver naming the state and the reason, the
/// approval revoked and the draft and queued emails cancelled; a sent one stays as history.
Method TestAbandonsAWorkingCase()
{
    Do ..AgeLastStateEvent(20)
    Do ..Escalation(1, "sent")
    Do ..Escalation(2, "draft")
    Do ..Escalation(3, "queued")
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set approval = ..Approve(c)
    Do $$$AssertEquals(##class(Shutter.Store.Case).InFlight(c, 15, .newestAt, .deferred), 0, "nothing is in flight: no session, and the last step is 20 minutes old")
    Do $$$AssertStatusOK(##class(Shutter.Store.Case).Abandon(c, "the instance died in the restart", "approver", c.Version), "the abandon")
    Do $$$AssertEquals(..Stored("State"), "failed", "the case is failed")
    Do $$$AssertEquals(..Stored("Disposition"), "abandoned", "with disposition abandoned")
    Do $$$AssertEquals(..Stored("Version"), 2, "the version moved")
    Do $$$AssertNotEquals(..Stored("ClosedAt"), "", "and the case is closed")
    Do $$$AssertEquals(..Stored("Headline"), "Abandoned by approver. the instance died in the restart", "the headline names who and why")
    Do $$$AssertTrue(..Stored("Outcome") [ "Abandoned, recorded by approver: the instance died in the restart. The workflow stopped in collecting", "the outcome: " _ ..Stored("Outcome"))
    Set ev = ..LastEvent("state")
    Do $$$AssertEquals(ev.fromState, "collecting", "the state event leaves collecting")
    Do $$$AssertEquals(ev.toState, "failed", "for failed")
    Do $$$AssertEquals(ev.actor, "approver", "its actor is the approver")
    Do $$$AssertTrue(ev.text [ "Abandoned from collecting: the instance died in the restart", "its text names the state and the reason: " _ ev.text)
    Do $$$AssertTrue(ev.text [ "2 pending emails cancelled", "and the emails cancelled: " _ ev.text)
    Do $$$AssertEquals(..Column(1, "State"), "sent", "a sent email stays sent")
    Do $$$AssertEquals(..Column(2, "State"), "cancelled", "the draft is cancelled")
    Do $$$AssertEquals(..Column(3, "State"), "cancelled", "and the queued one")
    Set a = ##class(Shutter.Store.Approval).%OpenId(approval.%Id())
    Do $$$AssertEquals(a.Revoked, 1, "the approval is revoked")
    Do $$$AssertTrue(a.RevokedBy [ "abandoned", "by the abandon: " _ a.RevokedBy)
}

/// A closed case is refused and left as it is: it is marked handled or reopened instead.
Method TestRefusesAClosedCase()
{
    Do ..Exec("UPDATE Shutter_Store.""Case"" SET State = 'escalated', ClosedAt = '2026-10-20T10:30:00Z' WHERE ID = ?")
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set sc = ##class(Shutter.Store.Case).Abandon(c, "no longer wanted", "approver")
    Do $$$AssertStatusNotOK(sc, "a closed case is refused")
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "The case is escalated", "and the error names its state: " _ $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertEquals(..Stored("State"), "escalated", "the state stands")
    Do $$$AssertEquals(..Stored("Version"), 1, "and the version")
    Do $$$AssertEquals(..Stored("Disposition"), "", "no disposition was written")
}

/// An expected version that is not the case's is refused before anything changes: no email is cancelled.
Method TestRefusesAStaleVersion()
{
    Do ..AgeLastStateEvent(20)
    Do ..Escalation(1, "draft")
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set sc = ##class(Shutter.Store.Case).Abandon(c, "stale", "approver", c.Version + 1)
    Do $$$AssertStatusNotOK(sc, "a stale expected version is refused")
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "Stale case version", "and says so: " _ $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertEquals(..Stored("State"), "collecting", "the case is untouched")
    Do $$$AssertEquals(..Stored("Version"), 1, "its version too")
    Do $$$AssertEquals(..Stored("Disposition"), "", "no disposition was written")
    Do $$$AssertEquals(..Column(1, "State"), "draft", "and the draft email is not cancelled")
}

// ---- busy or left behind ----

/// Without a workflow session, the last state event's age decides: a case that moved within the quiet minutes is busy
/// (one in flight, the event's time as newestAt, nothing deferred, no session judged), one older than them is not, and
/// a note written afterwards (the start sweep's, a collector's) never makes it busy again. Message headers are not made
/// here: the header rule (created, queued or deferred, or delivered within the minutes) runs on a production only.
Method TestInFlightWithoutASessionReadsTheLastStateEvent()
{
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set n = ##class(Shutter.Store.Case).InFlight(c, 15, .newestAt, .deferred, .session)
    Do $$$AssertEquals(n, 1, "a case whose last step is fresh is busy")
    Do $$$AssertEquals(session, "", "judged without a session")
    Do $$$AssertEquals(deferred, 0, "nothing deferred")
    Do $$$AssertEquals(newestAt, ..LastEvent("state").at, "newestAt is the state event's time")
    Do ..AgeLastStateEvent(20)
    Set n = ##class(Shutter.Store.Case).InFlight(c, 15, .newestAt, .deferred, .session)
    Do $$$AssertEquals(n, 0, "20 minutes after its last step the case is left behind")
    Do $$$AssertEquals(##class(Shutter.Store.Case).InFlight(c, 30, .newestAt, .deferred), 1, "with 30 quiet minutes it is still busy")
    Do $$$AssertStatusOK(c.Note("error", "A note written after the case stopped", "system"), "a note is written")
    Do $$$AssertEquals(##class(Shutter.Store.Case).InFlight(c, 15, .newestAt, .deferred), 0, "and the case is still left behind: only state events count")
}

/// The default quiet time is 15 minutes, and the lower bound keeps it above the board timeout (600 s).
Method TestAbandonAfterMinutesDefaults()
{
    Set saved = $GET(^Shutter.Config("abandonAfterMinutes"), $CHAR(0))
    Kill ^Shutter.Config("abandonAfterMinutes")
    Do $$$AssertEquals(##class(Shutter.Store.Case).AbandonAfterMinutes(), 15, "15 minutes when unset")
    Set ^Shutter.Config("abandonAfterMinutes") = 5
    Do $$$AssertEquals(##class(Shutter.Store.Case).AbandonAfterMinutes(), 11, "a value at or under the board timeout reads as 11")
    Set ^Shutter.Config("abandonAfterMinutes") = 45
    Do $$$AssertEquals(##class(Shutter.Store.Case).AbandonAfterMinutes(), 45, "a longer value stands")
    If saved = $CHAR(0) { Kill ^Shutter.Config("abandonAfterMinutes") } Else { Set ^Shutter.Config("abandonAfterMinutes") = saved }
}

// ---- the start sweep ----

/// The start sweep notes every case in a working state once, as an error-kind event by the system naming the state and
/// the way out, counts them, and never moves a case; a closed case gets nothing.
Method TestMarkOpenAtStartNotesWorkingCasesOnly()
{
    Set before = ..EventCount(), working = ..WorkingCases()
    Set n = ##class(Shutter.Store.Case).MarkOpenAtStart()
    Do $$$AssertEquals(n, working, "the sweep counts the cases in a working state (" _ n _ ", the test case among them)")
    Do $$$AssertEquals(..EventCount(), before + 1, "one event was written for the test case")
    Set ev = ..LastEvent("error")
    Do $$$AssertEquals(ev.actor, "system", "by the system")
    Do $$$AssertTrue(ev.text [ "The production started at ", "it says the production started: " _ ev.text)
    Do $$$AssertTrue(ev.text [ " while this case was collecting", "while the case was collecting")
    Do $$$AssertTrue(ev.text [ "resumes when the production was stopped cleanly", "that a clean restart resumes the work")
    Do $$$AssertTrue(ev.text [ "an approver can abandon it (POST /cases/" _ ..#CASEID _ "/abandon", "and names the way out")
    Do $$$AssertEquals($EXTRACT(ev.ref, 1, 6), "start:", "its ref is the start time")
    Do $$$AssertEquals(..Stored("State"), "collecting", "the sweep never closes a case")
    Do $$$AssertEquals(..Stored("Version"), 1, "nor moves its version")
    Do ..Exec("UPDATE Shutter_Store.""Case"" SET State = 'failed', ClosedAt = '2026-10-20T10:30:00Z' WHERE ID = ?")
    Set before = ..EventCount()
    Do ##class(Shutter.Store.Case).MarkOpenAtStart()
    Do $$$AssertEquals(..EventCount(), before, "a closed case gets no note")
}

// ---- helpers ----

/// Dates the test case's latest state event a number of minutes back, as a case left behind has it.
Method AgeLastStateEvent(minutes As %Integer)
{
    Set at = ##class(Shutter.Util.Time).FromNow(-(minutes * 60))
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 ID FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? AND Kind = 'state' ORDER BY Seq DESC", ..CaseRowId)
    Do $$$AssertTrue(rs.%Next(), "the case has a state event")
    Set ev = ##class(Shutter.Store.CaseEvent).%OpenId(rs.%Get("ID"))
    Set ev.At = at
    Do $$$AssertStatusOK(ev.%Save(), "the state event is dated " _ minutes _ " minutes back")
}

/// An escalation row of the test case, made directly (no draft: the text is the test's own).
Method Escalation(seq As %Integer, state As %String) As Shutter.Store.Escalation
{
    Set e = ##class(Shutter.Store.Escalation).%New()
    Do e.CaseSetObjectId(..CaseRowId)
    Set e.Seq = seq, e.State = state, e.TeamId = "pas", e.TeamName = "PAS team"
    Set e.ToAddr = "pas@example.nhs.uk", e.Subject = "Shutter " _ ..#CASEID _ ": manual check needed"
    Set e.Body = "Please check the transfer", e.BodyDigest = "d1", e.DraftedBy = "operator", e.DraftedAt = "2026-10-20T10:00:00Z"
    If (state = "sent") || (state = "queued") Set e.SentBy = "operator"
    If state = "sent" Set e.SentAt = "2026-10-20T10:05:00Z", e.Transport = "file"
    Do $$$AssertStatusOK(e.%Save(), "escalation " _ seq _ " (" _ state _ ") is saved")
    Quit e
}

/// A plan and an approval of it, saved as the case's current plan and approval.
Method Approve(c As Shutter.Store.Case) As Shutter.Store.Approval
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(c, "", {"disposition": "resend", "action": {"type": "resend"}}, "rules", .plan), "a plan is saved")
    Do $$$AssertStatusOK(##class(Shutter.Store.Approval).Create(c, plan, "", "unit-test", "", 3, "approver", "approved", "unit test", "", 3600, .approval), "an approval of it is saved")
    Set c.CurrentPlan = plan, c.CurrentApproval = approval
    Do $$$AssertStatusOK(c.%Save(), "the case points at them")
    Quit approval
}

/// The test case's latest event of a kind, or empty fields.
Method LastEvent(kind As %String) As %DynamicObject
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Text, Ref, Actor, FromState, ToState, At FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? AND Kind = ? ORDER BY Seq DESC", ..CaseRowId, kind)
    If 'rs.%Next() Quit {"text": "", "ref": "", "actor": "", "fromState": "", "toState": "", "at": ""}
    Quit {"text": (rs.%Get("Text")), "ref": (rs.%Get("Ref")), "actor": (rs.%Get("Actor")), "fromState": (rs.%Get("FromState")), "toState": (rs.%Get("ToState")), "at": (rs.%Get("At"))}
}

/// How many events the test case has.
Method EventCount() As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", ..CaseRowId)
    Quit $SELECT(rs.%Next(): +rs.%Get("n"), 1: 0)
}

/// How many cases on the instance are in a working state, the test case among them.
Method WorkingCases() As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM Shutter_Store.""Case"" WHERE State NOT IN ('resolved', 'blocked', 'escalated', 'failed')")
    Quit $SELECT(rs.%Next(): +rs.%Get("n"), 1: 0)
}

/// A column of one of the test case's escalations, as stored.
Method Column(seq As %Integer, column As %String) As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT " _ column _ " AS v FROM Shutter_Store.Escalation WHERE ""Case"" = ? AND Seq = ?", ..CaseRowId, seq)
    Quit $SELECT(rs.%Next(): rs.%Get("v"), 1: "")
}

/// A column of the test case, as stored.
Method Stored(column As %String) As %String
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT " _ column _ " AS v FROM Shutter_Store.""Case"" WHERE ID = ?", ..CaseRowId)
    Quit $SELECT(rs.%Next(): rs.%Get("v"), 1: "")
}

Method Exec(sql As %String)
{
    Do ##class(%SQL.Statement).%ExecDirect(, sql, ..CaseRowId)
}

}
