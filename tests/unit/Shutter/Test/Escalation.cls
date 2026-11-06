/// The escalation store (Shutter.Store.Escalation, CONTRACTS 10) against a saved case: the hand close cancels every
/// draft or queued email, the edit and the queue check the subject and the addresses, the retention of the email's text
/// (PurgeTextBefore, RemoveFile, the case purge) and the .eml writer's headers (Shutter.Operation.EscalationMail, in
/// process with no production). The case is saved under its own id, UT-ESCALATION, outside the case counter, closed in
/// 1970 so that a 1970 cutoff reaches only it on a shared instance, and removed with its escalations, events and files
/// after each test.
Class Shutter.Test.Escalation Extends %UnitTest.TestCase
{

Parameter CASEID = "UT-ESCALATION";

/// A case id no row has, for the orphan test.
Parameter ORPHANCASE = 987654321;

Property CaseRowId As %String;

/// The files the test wrote, for the clean-up.
Property Files As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
    // Rows a run that stopped half-way may have left.
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", ..#CASEID)
    While rs.%Next() { Do ..Purge(rs.%Get("ID")) }
    Do ..Purge(..#ORPHANCASE)
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = ..#CASEID, c.OperationKey = "PAS^HOSP^MRN9003^ENC-9003^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.EncounterId = "ENC-9003", c.PatientId = "MRN9003", c.FailureKind = "delivery_failed"
    Set c.State = "escalated", c.ClosedAt = "1970-01-01T00:00:00Z"
    Set sc = c.%Save()
    Set ..CaseRowId = c.%Id()
    Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..Purge(..CaseRowId)
    Do ..Purge(..#ORPHANCASE)
    Set path = ""
    For {
        Set path = $ORDER(i%Files(path))
        Quit:path=""
        If ##class(%File).Exists(path) Do ##class(%File).Delete(path)
    }
    Kill i%Files
    Quit $$$OK
}

/// Deletes a case's escalations and events, its counter and the case itself (already gone after a purge test).
ClassMethod Purge(id As %String)
{
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.Escalation WHERE ""Case"" = ?", id)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
    Kill ^Shutter.Counter("event", id)
    If ##class(Shutter.Store.Case).%ExistsId(id) Do ##class(Shutter.Store.Case).%DeleteId(id)
}

// ---- the hand close ----

Method TestCloseCancelsEveryPendingEmail()
{
    Do ..Escalation(1, "draft")
    Do ..Escalation(2, "failed")
    Do ..Escalation(3, "queued")
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Do $$$AssertStatusOK(##class(Shutter.Store.Case).CloseByHand(c, "corrected by the team", "operator"), "the close")
    Do $$$AssertEquals(..Column(1, "State"), "cancelled", "the earlier draft is cancelled too")
    Do $$$AssertEquals(..Column(2, "State"), "failed", "a failed send stays failed, as history")
    Do $$$AssertEquals(..Column(3, "State"), "cancelled", "the queued latest is cancelled")
    Do $$$AssertEquals(..Stored("State"), "resolved", "the case is resolved")
    Do $$$AssertEquals(..Stored("Disposition"), "handled_by_hand", "handled by hand")
    Set ev = ..LastEvent("state")
    Do $$$AssertEquals(ev.ref, "escalation:3", "the state event refers to the latest escalation")
    Do $$$AssertTrue(ev.text [ "; after escalation 3 to PAS team (queued); 2 pending emails cancelled", "and says how many emails were cancelled: " _ ev.text)
}

Method TestCloseNamesTheLatestWhateverItsState()
{
    Do ..Escalation(1, "sent")
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Do $$$AssertStatusOK(##class(Shutter.Store.Case).CloseByHand(c, "corrected by the team", "operator"), "the close")
    Do $$$AssertEquals(..Column(1, "State"), "sent", "a sent email is left as it is")
    Set ev = ..LastEvent("state")
    Do $$$AssertEquals($EXTRACT(ev.text, * - 5, *), "(sent)", "the state event names it with its state and nothing cancelled: " _ ev.text)
}

// ---- the subject and the addresses ----

/// The rules with the field named, against a given list of domains (the instance's profile may name none).
Method TestProblemNamesTheField()
{
    Set domains = $LISTBUILD("nhs.net")
    Set problem = ##class(Shutter.Store.Escalation).Problem("ok", "a@nhs.net@evil.com", "", .field, domains)
    Do $$$AssertEquals(field, "to", "a second @ in to names the field: " _ problem)
    Set problem = ##class(Shutter.Store.Escalation).Problem("x" _ $CHAR(13), "a@nhs.net", "", .field, domains)
    Do $$$AssertEquals(field, "subject", "a control character names the subject: " _ problem)
    Set problem = ##class(Shutter.Store.Escalation).Problem("ok", "a@nhs.net", "b@evil.com", .field, domains)
    Do $$$AssertEquals(field, "cc", "an outside cc names the field: " _ problem)
    Set problem = ##class(Shutter.Store.Escalation).Problem("ok", "a@nhs.net", "", .field, "")
    Do $$$AssertEquals(field, "to", "an empty list refuses the recipient: " _ problem)
    Do $$$AssertEquals(##class(Shutter.Store.Escalation).Problem("ok", "a@nhs.net, b@trust.nhs.net", "", .field, domains), "", "a plain email passes")
    Do $$$AssertEquals(field, "", "with no field named")
}

/// Edit and Queue refuse what the rules refuse, naming the field, whatever the stored profile's domains.
Method TestEditAndQueueCheckTheText()
{
    Set e = ..Escalation(1, "draft")
    Set sc = e.Edit("x" _ $CHAR(10) _ "Bcc: e@evil.com", "body", "pas@example.nhs.uk", "", "operator")
    Do $$$AssertStatusNotOK(sc, "an edit with a line break in the subject is refused")
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "subject: must not contain line breaks", "naming the field: " _ $SYSTEM.Status.GetErrorText(sc))
    Set sc = e.Edit("ok", "body", "a@example.nhs.uk@evil.com", "", "operator")
    Do $$$AssertStatusNotOK(sc, "an edit with two @ in to is refused")
    Do $$$AssertTrue(($SYSTEM.Status.GetErrorText(sc) [ "to: a@example.nhs.uk@evil.com: ") && ($SYSTEM.Status.GetErrorText(sc) [ "must be one address with one @"), "naming the field, the address and why: " _ $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertEquals(..Column(1, "Subject"), "Shutter " _ ..#CASEID _ ": manual check needed", "the stored text is unchanged")
    // A row changed outside the API is refused at the queue.
    Set e.ToAddr = "Team <pas@example.nhs.uk>"
    Do $$$AssertStatusOK(e.%Save(), "the row is changed directly")
    Set sc = e.Queue("d1", "operator")
    Do $$$AssertStatusNotOK(sc, "a queue with a display name in to is refused")
    Do $$$AssertTrue(($SYSTEM.Status.GetErrorText(sc) [ "to: Team <pas@example.nhs.uk>: ") && ($SYSTEM.Status.GetErrorText(sc) [ "must be a bare address"), "naming the field, the address and why: " _ $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertEquals(..Column(1, "State"), "draft", "and the row stays a draft")
}

// ---- the retention of the email's text ----

Method TestPurgeTextClearsBodyAndRemovesFile()
{
    Set path = ..WriteEml(1)
    Do ..Escalation(1, "sent", "file", path)
    Do $$$AssertEquals(##class(Shutter.Store.Escalation).PurgeTextBefore("1970-01-02T00:00:00Z", 90), 1, "one escalation is purged")
    Do $$$AssertEquals(..Column(1, "Body"), "", "the body is gone")
    Do $$$AssertNotEquals(..Column(1, "PurgedAt"), "", "purgedAt is set")
    Do $$$AssertEquals(..Column(1, "BodyDigest"), "d1", "the digest stays")
    Do $$$AssertEquals(..Column(1, "ToAddr"), "pas@example.nhs.uk", "the recipient stays")
    Do $$$AssertEquals(..Column(1, "SentBy"), "operator", "who sent it stays")
    Do $$$AssertEquals(..Column(1, "State"), "sent", "the state stays")
    Do $$$AssertEquals(..Column(1, "Result"), path, "the file's path stays on record")
    Do $$$AssertNotTrue(##class(%File).Exists(path), "the .eml is removed")
    Set ev = ..LastEvent("escalation")
    Do $$$AssertEquals(ev.ref, "escalation:1", "a timeline line refers to the escalation")
    Do $$$AssertTrue(ev.text [ "text was removed 90 days after the case closed", "and says the text went: " _ ev.text)
    Do $$$AssertEquals(##class(Shutter.Store.Escalation).PurgeTextBefore("1970-01-02T00:00:00Z", 90), 0, "a second pass purges nothing")
    Do $$$AssertEquals(..Count("Shutter_Store.CaseEvent", "Kind = 'escalation'"), 1, "and writes no second line")
    Set o = ##class(Shutter.Store.Escalation).BySeq(##class(Shutter.Store.Case).%OpenId(..CaseRowId), 1).ToObject()
    Do $$$AssertEquals(o.%GetTypeOf("body"), "string", "the API shows the body as a string")
    Do $$$AssertEquals(o.body, "", "an empty one")
    Do $$$AssertTrue(o.%IsDefined("purgedAt") && (o.purgedAt '= ""), "with purgedAt")
}

Method TestPurgedEscalationRefusesEditAndSend()
{
    Set e = ..Escalation(1, "failed")
    Set o = e.ToObject()
    Do $$$AssertNotTrue(o.%IsDefined("purgedAt"), "before the purge there is no purgedAt")
    Do $$$AssertEquals(##class(Shutter.Store.Escalation).PurgeTextBefore("1970-01-02T00:00:00Z", 90), 1, "the failed escalation is purged")
    Set e = ##class(Shutter.Store.Escalation).BySeq(##class(Shutter.Store.Case).%OpenId(..CaseRowId), 1)
    Set sc = e.Edit("s", "b", "pas@example.nhs.uk", "", "operator")
    Do $$$AssertStatusNotOK(sc, "an edit is refused")
    Set why = $SYSTEM.Status.GetErrorText(sc)
    Do $$$AssertTrue((why [ "retention task") && ($ZCONVERT(why, "L") '[ "digest"), "saying the retention task removed the text: " _ why)
    Set sc = e.Queue("d1", "operator")
    Do $$$AssertStatusNotOK(sc, "a send is refused")
    Set why = $SYSTEM.Status.GetErrorText(sc)
    Do $$$AssertTrue((why [ "retention task") && ($ZCONVERT(why, "L") '[ "digest"), "for the same reason, so the route answers wrong_state: " _ why)
    Do $$$AssertEquals(..Column(1, "State"), "failed", "the state is unchanged")
}

Method TestPurgeTextSkipsQueuedOpenAndRecentCases()
{
    Do ..Escalation(1, "queued")
    Do ..Escalation(2, "sent")
    // A case reopened since (its ClosedAt stays) keeps its texts.
    Do ..Exec("UPDATE Shutter_Store.""Case"" SET State = 'collecting' WHERE ID = ?")
    Do $$$AssertEquals(##class(Shutter.Store.Escalation).PurgeTextBefore("1970-01-02T00:00:00Z", 90), 0, "an open case keeps its texts")
    // A case closed after the cutoff keeps them too.
    Do ..Exec("UPDATE Shutter_Store.""Case"" SET State = 'escalated', ClosedAt = '2026-10-20T10:00:00Z' WHERE ID = ?")
    Do $$$AssertEquals(##class(Shutter.Store.Escalation).PurgeTextBefore("1970-01-02T00:00:00Z", 90), 0, "a case closed after the cutoff keeps its texts")
    Do ..Exec("UPDATE Shutter_Store.""Case"" SET ClosedAt = '1970-01-01T00:00:00Z' WHERE ID = ?")
    Do $$$AssertEquals(##class(Shutter.Store.Escalation).PurgeTextBefore("1970-01-02T00:00:00Z", 90), 1, "a case closed before it loses the sent text only")
    Do $$$AssertNotEquals(..Column(1, "Body"), "", "the queued email keeps its text for the mail operation")
    Do $$$AssertEquals(..Column(1, "PurgedAt"), "", "and is not marked purged")
    Do $$$AssertEquals(..Column(2, "Body"), "", "the sent one loses its text")
}

Method TestRemoveFileTakesOnlyEscalationFiles()
{
    Set path = ..WriteEml(1)
    Do $$$AssertNotTrue(##class(Shutter.Store.Escalation).RemoveFile(path, 2), "another escalation's number is refused")
    Do $$$AssertTrue(##class(%File).Exists(path), "and the file stays")
    Set other = ##class(%File).NormalizeFilename("UT-ESCALATION-notes.txt", ##class(%File).NormalizeDirectory(##class(%SYS.System).TempDirectory()))
    Set f = ##class(%Stream.FileCharacter).%New()
    Do f.LinkToFile(other)
    Do f.WriteLine("not an email")
    Do $$$AssertStatusOK(f.%Save(), "another file is written")
    Set i%Files(other) = ""
    Do $$$AssertNotTrue(##class(Shutter.Store.Escalation).RemoveFile(other, 1), "a file not named as an escalation is refused")
    Do $$$AssertTrue(##class(%File).Exists(other), "and stays")
    Do $$$AssertNotTrue(##class(Shutter.Store.Escalation).RemoveFile("", 1), "an empty path is refused")
    Do $$$AssertTrue(##class(Shutter.Store.Escalation).RemoveFile(path, 1), "the escalation's own file is removed")
    Do $$$AssertNotTrue(##class(%File).Exists(path), "and is gone")
    Do $$$AssertTrue(##class(Shutter.Store.Escalation).RemoveFile(path, 1), "a file already gone counts as removed")
}

Method TestPurgeCaseTakesEscalationsAndFiles()
{
    // Only what is finished is purged (Shutter.Test.Closure): this one was handled.
    Set c = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set c.State = "resolved"
    Do $$$AssertStatusOK(c.%Save(), "the case is finished")
    Set path = ..WriteEml(1)
    Do ..Escalation(1, "sent", "file", path)
    Do $$$AssertEquals(##class(Shutter.Store.Case).PurgeClosedBefore("1970-01-02T00:00:00Z"), 1, "the case closed in 1970 is purged")
    Do $$$AssertNotTrue(##class(Shutter.Store.Case).%ExistsId(..CaseRowId), "the case is gone")
    Do $$$AssertEquals(..Count("Shutter_Store.Escalation", """Case"" = " _ ..CaseRowId), 0, "its escalations with it, no orphan left")
    Do $$$AssertNotTrue(##class(%File).Exists(path), "and the .eml file")
}

Method TestPurgeTextBeforeRemovesOrphans()
{
    // An escalation whose case was purged before escalations were part of the case purge.
    Set path = ..WriteEml(1, "UT-ORPHAN")
    Set e = ##class(Shutter.Store.Escalation).%New()
    Do e.CaseSetObjectId(..#ORPHANCASE)
    Set e.Seq = 1, e.State = "sent", e.ToAddr = "pas@example.nhs.uk", e.Subject = "orphan", e.Body = "text", e.BodyDigest = "d1"
    Set e.Transport = "file", e.Result = path
    Do $$$AssertStatusOK(e.%Save(), "the orphan row is saved")
    Set id = e.%Id()
    Do $$$AssertEquals(##class(Shutter.Store.Escalation).PurgeTextBefore("1970-01-02T00:00:00Z", 90), 1, "the pass counts the orphan")
    Do $$$AssertNotTrue(##class(Shutter.Store.Escalation).%ExistsId(id), "the orphan row is gone")
    Do $$$AssertNotTrue(##class(%File).Exists(path), "and its file")
}

/// The task's defaults: an instance upgraded in place, whose task has no EscalationDays setting, runs 90.
Method TestRetentionTaskDefaults()
{
    Set task = ##class(Shutter.Util.RetentionTask).%New()
    Do $$$AssertEquals(task.EscalationDays, 90, "the escalation texts go after 90 days by default")
    Do $$$AssertEquals(task.RetentionDays, 30, "the case retention stays 30")
    Do $$$AssertNotTrue(task.PurgeClosedCases, "and the case purge off")
}

// ---- the .eml writer ----

/// Every header of the .eml is one logical line: a line break in the subject becomes spaces, a long recipient list is
/// folded at a comma or a space with a leading space on the continuation (RFC 5322 2.2.3), and no header exceeds 78
/// characters when it can be folded.
Method TestWriteFileKeepsEachHeaderOnOneLine()
{
    Set to = "team-one@example.nhs.uk, team-two@example.nhs.uk, team-three@example.nhs.uk, team-four@example.nhs.uk"
    Set subject = "Shutter " _ ..#CASEID _ ": manual check needed" _ $CHAR(13, 10) _ "Bcc: evil@example.nhs.uk"
    Set e = ..Escalation(1, "queued")
    Set e.ToAddr = to, e.Subject = subject
    Do $$$AssertStatusOK(e.%Save(), "the escalation carries the long list and the broken subject")
    Set op = ##class(Shutter.Operation.EscalationMail).%New("Escalation Mail (unit test)")
    Set op.OutputFolder = ##class(%File).NormalizeDirectory(##class(%SYS.System).TempDirectory())
    Set path = op.WriteFile(e)
    Set i%Files(path) = ""
    Do $$$AssertTrue(##class(%File).Exists(path), "the .eml is written: " _ path)
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.LineTerminator = $CHAR(13, 10)
    Do f.LinkToFile(path)
    Set headers = "", raw = "", longest = 0
    While 'f.AtEnd {
        Set line = $ZSTRIP(f.ReadLine(), ">C")
        Quit:line=""
        Set raw = raw _ $LISTBUILD(line)
        If $LENGTH(line) > longest Set longest = $LENGTH(line)
        If ($EXTRACT(line, 1) = " ") && ($LISTLENGTH(headers) > 0) {
            Set last = $LISTLENGTH(headers)
            Set $LIST(headers, last) = $LIST(headers, last) _ line
        } Else {
            Set headers = headers _ $LISTBUILD(line)
        }
    }
    Set body = f.Read()
    Do $$$AssertTrue(longest <= 78, "no header line is longer than 78 characters: " _ longest)
    Set bcc = 0
    For i = 1:1:$LISTLENGTH(raw) { If $EXTRACT($LIST(raw, i), 1, 4) = "Bcc:" Set bcc = bcc + 1 }
    Do $$$AssertEquals(bcc, 0, "no Bcc header was injected")
    Do $$$AssertEquals(..HeaderOf(headers, "To"), "To: " _ to, "the recipients unfold to the list as stored")
    Do $$$AssertEquals(..HeaderOf(headers, "Subject"), "Subject: Shutter " _ ..#CASEID _ ": manual check needed  Bcc: evil@example.nhs.uk", "the subject is one line with the break as spaces")
    Do $$$AssertTrue(..HeaderOf(headers, "From") '= "", "a From header is written")
    Do $$$AssertEquals($EXTRACT(body, 1, 7), "PATIENT", "the body follows the blank line")
}

// ---- helpers ----

/// An escalation row of the test case, made directly (no draft: the text is the test's own).
Method Escalation(seq As %Integer, state As %String, transport As %String = "", result As %String = "") As Shutter.Store.Escalation
{
    Set e = ##class(Shutter.Store.Escalation).%New()
    Do e.CaseSetObjectId(..CaseRowId)
    Set e.Seq = seq, e.State = state, e.TeamId = "pas", e.TeamName = "PAS team"
    Set e.ToAddr = "pas@example.nhs.uk", e.Subject = "Shutter " _ ..#CASEID _ ": manual check needed"
    Set e.Body = "PATIENT" _ $CHAR(13, 10) _ "  NHS number: 943 476 5919" _ $CHAR(13, 10) _ "  Date of birth: 1968-10-02" _ $CHAR(13, 10)
    Set e.BodyDigest = "d1", e.DraftedBy = "operator", e.DraftedAt = "2026-10-20T10:00:00Z"
    If (state = "sent") || (state = "failed") || (state = "queued") Set e.SentBy = "operator"
    If state = "sent" Set e.SentAt = "2026-10-20T10:05:00Z"
    Set e.Transport = transport, e.Result = result
    Do $$$AssertStatusOK(e.%Save(), "escalation " _ seq _ " (" _ state _ ") is saved")
    Quit e
}

/// An .eml file in the instance's temp folder, named as the mail operation names them; its path.
Method WriteEml(seq As %Integer, caseId As %String = "") As %String
{
    If caseId = "" Set caseId = ..#CASEID
    Set path = ##class(%File).NormalizeFilename(caseId _ "-escalation-" _ seq _ ".eml", ##class(%File).NormalizeDirectory(##class(%SYS.System).TempDirectory()))
    Set f = ##class(%Stream.FileCharacter).%New()
    Do f.LinkToFile(path)
    Do f.WriteLine("Subject: test")
    Do $$$AssertStatusOK(f.%Save(), "the .eml " _ path _ " is written")
    Set i%Files(path) = ""
    Quit path
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

/// How many rows of a table match a condition, for the test case.
Method Count(table As %String, where As %String) As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS n FROM " _ table _ " WHERE ""Case"" = ? AND " _ where, ..CaseRowId)
    Quit $SELECT(rs.%Next(): +rs.%Get("n"), 1: 0)
}

/// The newest event of a kind on the test case: {text, ref}.
Method LastEvent(kind As %String) As %DynamicObject
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Text, Ref FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? AND Kind = ? ORDER BY Seq DESC", ..CaseRowId, kind)
    If 'rs.%Next() Quit {"text": "", "ref": ""}
    Quit {"text": (rs.%Get("Text")), "ref": (rs.%Get("Ref"))}
}

/// The unfolded header of a name from the list the .eml test read, or "".
ClassMethod HeaderOf(headers As %List, name As %String) As %String
{
    For i = 1:1:$LISTLENGTH(headers) { If $EXTRACT($LIST(headers, i), 1, $LENGTH(name) + 1) = (name _ ":") Return $LIST(headers, i) }
    Quit ""
}

}
