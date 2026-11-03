/// One board per failure signature (Shutter.Util.Signature and Shutter.Store.BoardLead; CONTRACTS 6.6, v1.35): the
/// signature's parts and normalisation, the lead's window, finish, expiry and the reset stamp, and a leader that fails or
/// is abandoned finishing its lead, so its followers are released. The rows written are deleted at the end. The leader
/// tests drive an instance of the Case Workflow item outside the production, with no case following the lead, so no
/// LeadReady goes to the production; that a follower is told is proved by the scenario runs.
Class Shutter.Test.BoardLead Extends %UnitTest.TestCase
{

Property Sigs As %String [ MultiDimensional ];

Property SavedWindow As %String;

Property SavedReset As %String;

Method OnBeforeAllTests() As %Status
{
    Set ..SavedWindow = $GET(^Shutter.Config("leadWindowSeconds"), $CHAR(0))
    Set ..SavedReset = $GET(^Shutter.Config("resetAt"), $CHAR(0))
    Kill ^Shutter.Config("leadWindowSeconds")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Set sig = ""
    For {
        Set sig = $ORDER(..Sigs(sig)) Quit:sig=""
        &sql(DELETE FROM Shutter_Store.BoardLead WHERE Signature = :sig)
    }
    For caseId = "C-TEST-LEAD-A", "C-TEST-LEAD-B", "C-TEST-LEAD-C", "C-TEST-LEAD-D" { Do ..Purge(caseId) }
    If ..SavedWindow = $CHAR(0) { Kill ^Shutter.Config("leadWindowSeconds") } Else { Set ^Shutter.Config("leadWindowSeconds") = ..SavedWindow }
    If ..SavedReset = $CHAR(0) { Kill ^Shutter.Config("resetAt") } Else { Set ^Shutter.Config("resetAt") = ..SavedReset }
    Quit $$$OK
}

Method Case(receiver As %String, text As %String, scenario As %String = "") As Shutter.Store.Case
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = "C-TEST-LEAD", c.Receiver = receiver, c.FailureKind = "delivery_failed", c.FailureText = text, c.Scenario = scenario
    Quit c
}

Method Summary(answer As %String = "unavailable", entry As %String = "E2") As %DynamicObject
{
    Quit {"catalogue": {"conditions": {"receiver_answer": (answer), "delivery": "failed"}, "entry": (entry), "outcome": "resend"}}
}

Method TestSignature()
{
    Set sig = "Shutter.Util.Signature"
    Do $$$AssertEquals($CLASSMETHOD(sig, "Normalise", "Delivery unavailable (ward_unavailable), HTTP 503: version 7, digest sha256:ab12ff"), "delivery unavailable ward unavailable http # version # digest #", "lower case, numbers and digests as #, punctuation dropped")
    Set a = $CLASSMETHOD(sig, "Of", ..Case("Downstream Out", "Delivery unavailable (ward_unavailable), HTTP 503: The downstream system is unavailable, version 7"), ..Summary())
    Set b = $CLASSMETHOD(sig, "Of", ..Case("Downstream Out", "Delivery unavailable (ward_unavailable), HTTP 503: The downstream system is unavailable, version 12"), ..Summary())
    Do $$$AssertEquals(a, b, "two cases of the same failure share a signature whatever the numbers")
    Do $$$AssertTrue($MATCH(a, "^sha256:[0-9a-f]{64}$"), "a digest")
    Do $$$AssertNotEquals(a, $CLASSMETHOD(sig, "Of", ..Case("Records Out", "Delivery unavailable (ward_unavailable), HTTP 503"), ..Summary()), "another receiver, another signature")
    Do $$$AssertNotEquals(a, $CLASSMETHOD(sig, "Of", ..Case("Downstream Out", "Delivery unavailable (ward_unavailable), HTTP 503"), ..Summary("timeout")), "another answer, another signature")
    Do $$$AssertNotEquals(a, $CLASSMETHOD(sig, "Of", ..Case("Downstream Out", "Delivery unavailable (ward_unavailable), HTTP 503"), ..Summary("unavailable", "E3")), "another entry, another signature")
    Do $$$AssertNotEquals(a, $CLASSMETHOD(sig, "Of", ..Case("Downstream Out", "Delivery unavailable (ward_unavailable), HTTP 503", "S2"), ..Summary()), "a scenario stamp makes its own signature")
    Do $$$AssertEquals($CLASSMETHOD(sig, "Of", "", ..Summary()), "", "no case, no signature")
    Set parts = $CLASSMETHOD(sig, "Parts", ..Case("Downstream Out", "x"), ..Summary())
    Do $$$AssertEquals(parts.receiver _ "|" _ parts."receiver_answer" _ "|" _ parts.entry _ "|" _ parts."policy_version", "Downstream Out|unavailable|E2|" _ ##class(Shutter.Operation.Gate).#POLICYVERSION, "the parts")
}

Method TestLeadWindow()
{
    Set bl = "Shutter.Store.BoardLead"
    Do $$$AssertEquals($CLASSMETHOD(bl, "WindowSeconds"), 600, "ten minutes by default")
    Set ^Shutter.Config("leadWindowSeconds") = 0
    Do $$$AssertEquals($CLASSMETHOD(bl, "WindowSeconds"), 0, "nought switches the coalescing off")
    Set ^Shutter.Config("leadWindowSeconds") = "soon"
    Do $$$AssertEquals($CLASSMETHOD(bl, "WindowSeconds"), 600, "a bad value means the default")
    Set ^Shutter.Config("leadWindowSeconds") = 120
    Do $$$AssertEquals($CLASSMETHOD(bl, "WindowSeconds"), 120, "two minutes when the site says so")
    Kill ^Shutter.Config("leadWindowSeconds"), ^Shutter.Config("resetAt")
    Set sig = "sha256:test-lead-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set ..Sigs(sig) = ""
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "no lead yet")
    Set leader = ..Case("Downstream Out", "x")
    Set leader.CaseId = "C-TEST-LEADER"
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig, leader, {"receiver": "Downstream Out"}, .lead), "a lead begins")
    Do $$$AssertEquals(lead.State _ "|" _ lead.LeaderCaseId, "running|C-TEST-LEADER", "running, led by the first case")
    Do $$$AssertTrue(##class(Shutter.Util.Time).SecondsBetween(##class(Shutter.Util.Time).NowUTC(), lead.ExpiresAt) > 590, "for the window")
    Set cur = $CLASSMETHOD(bl, "Current", sig)
    Do $$$AssertTrue($ISOBJECT(cur) && (cur.%Id() = lead.%Id()), "a case of the signature finds it")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Finish", "C-NOBODY", "done")), "a case that leads nothing finishes nothing")
    Set done = $CLASSMETHOD(bl, "Finish", "C-TEST-LEADER", "done", {"disposition": "resend", "action": {"type": "resend"}}, [{"memberCode": "impact", "disposition": "resend", "confidence": 0.9}])
    Do $$$AssertEquals(done.State, "done", "done with the plan")
    Do $$$AssertEquals(done.Projection().plan.disposition _ "|" _ done.Projection().verdicts.%Get(0).memberCode, "resend|impact", "the plan and the verdicts as objects")
    Do $$$AssertEquals(done.EndedAt '= "", 1, "ended")
    Do $$$AssertEquals($CLASSMETHOD(bl, "Finish", "C-TEST-LEADER", "failed").State, "done", "finished once; a later finish changes nothing")
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "a done lead still attracts followers within the window")
    Do $$$AssertStatusOK(done.Followed(), "a follower counted")
    Do $$$AssertEquals($CLASSMETHOD(bl, "ForLeader", "C-TEST-LEADER").Followers, 1, "one follower")
    // A reset after the lead began: the lead counts for nothing, as the incident detector's window.
    Set ^Shutter.Config("resetAt") = ##class(Shutter.Util.Time).FromNow(5)
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "a lead begun before the last reset is not followed")
    Kill ^Shutter.Config("resetAt")
    // An expired lead.
    Set done.ExpiresAt = ##class(Shutter.Util.Time).FromNow(-1)
    Do $$$AssertStatusOK(done.%Save(), "expired by hand")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "an expired lead is not followed")
    // A failed lead.
    Set sig2 = sig _ "-f"
    Set ..Sigs(sig2) = ""
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig2, leader, "", .lead2), "another lead")
    Set failed = $CLASSMETHOD(bl, "Finish", "C-TEST-LEADER", "failed", "", "", "the coordinator did not answer")
    Do $$$AssertEquals(failed.State _ "|" _ failed.Reason, "failed|the coordinator did not answer", "failed with the reason")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig2)), "a failed lead attracts no followers")
    Do $$$AssertEquals($CLASSMETHOD(bl, "FollowersOf", "C-NOBODY").%Size(), 0, "nobody follows a case that is not there")
    Do $$$AssertEquals($CLASSMETHOD(bl, "VerdictsOf", "").%Size(), 0, "no snapshot, no verdicts")
}

/// A saved case in investigating, under its own public id outside the case counter.
Method SavedCase(caseId As %String) As Shutter.Store.Case
{
    Do ..Purge(caseId)
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = caseId, c.Receiver = "Downstream Out", c.OperationKey = "PAS^HOSP^MRN9004^ENC-9004^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.EncounterId = "ENC-9004", c.PatientId = "MRN9004", c.FailureKind = "delivery_failed", c.FailureText = "x"
    Set c.State = "investigating", c.Headline = "The transfer was not delivered"
    Set c.OpenedAt = ##class(Shutter.Util.Time).NowUTC(), c.UpdatedAt = c.OpenedAt
    Do $$$AssertStatusOK(c.%Save(), "the case " _ caseId _ " is saved")
    Quit c
}

/// Deletes a test case's events and counters and the case itself, whichever exist (a run that stopped half-way may have
/// left them).
ClassMethod Purge(caseId As %String)
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", caseId)
    While rs.%Next() {
        Set id = rs.%Get("ID")
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
        Kill ^Shutter.Counter("event", id), ^Shutter.Counter("plan", id)
        If ##class(Shutter.Store.Case).%ExistsId(id) Do ##class(Shutter.Store.Case).%DeleteId(id)
    }
}

/// A case workflow instance of the production's item, driven here outside the production: it sends nothing while no
/// case follows the lead, so the production never sees a test case.
Method Instance() As Shutter.Process.CaseWorkflow
{
    Set wf = ##class(Shutter.Process.CaseWorkflow).%New("Case Workflow")
    Do $$$AssertTrue($ISOBJECT(wf), "an instance of the Case Workflow item")
    Quit wf
}

/// A leader whose workflow errors (a member call answered with an error status) finishes its lead as failed before the
/// case fails, so the signature attracts no new follower, and the cases already following it are told at once and take
/// the rules path (OnLeadReady on a failed lead) instead of waiting out the bound. A case that follows it is told
/// through the production, so the proof that it is told is the scenario runs; here nobody follows, and nobody is told.
Method TestLeaderFailureFinishesTheLead()
{
    Set bl = "Shutter.Store.BoardLead"
    Kill ^Shutter.Config("leadWindowSeconds"), ^Shutter.Config("resetAt")
    Set sig = "sha256:test-lead-fail-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set ..Sigs(sig) = ""
    Set leader = ..SavedCase("C-TEST-LEAD-A")
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig, leader, "", .lead), "the leader's lead begins")
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "a case of the signature would follow it")
    Set wf = ..Instance()
    Set wf.CaseId = "C-TEST-LEAD-A", wf.LeadSignature = sig, wf.PendingJSON = ["conformance"].%ToJSON()
    Do $$$AssertStatusOK(wf.OnError("", .response, "", $$$ERROR($$$GeneralError, "the member item is not running"), "member:conformance"), "the error of an awaited member call is handled")
    Set after = $CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-A")
    Do $$$AssertEquals(after.State, "failed", "the lead is finished as failed")
    Do $$$AssertEquals(after.Reason, "the leader's workflow failed: ERROR #5001: the member item is not running", "with the reason")
    Do $$$AssertNotEquals(after.EndedAt, "", "and ended")
    Do $$$AssertEquals(wf.LeadSignature, "", "the instance leads nothing now")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-A").State, "failed", "the case failed with the error")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "a new case of the signature leads itself instead of following the dead lead")
    Do $$$AssertEquals(wf.TellFollowers("C-TEST-LEAD-A", after), 0, "nobody was waiting, so nobody is told")
}

/// A leader an approver abandons: the fresh instance that abandons it never knew the lead, so it finds the lead by the
/// case id, finishes it as failed and tells the followers; a lead already ended, or a case that leads nothing, is left
/// as it is.
Method TestAbandonedLeaderFinishesTheLead()
{
    Set bl = "Shutter.Store.BoardLead"
    Kill ^Shutter.Config("leadWindowSeconds"), ^Shutter.Config("resetAt")
    Set sig = "sha256:test-lead-abandon-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set ..Sigs(sig) = ""
    Set leader = ..SavedCase("C-TEST-LEAD-C")
    Set other = ..SavedCase("C-TEST-LEAD-D")
    Do $$$AssertStatusOK($CLASSMETHOD(bl, "Begin", sig, leader, "", .lead), "the leader's lead begins")
    Set wf = ..Instance()
    Set request = ##class(Shutter.Msg.CaseAbandon).%New()
    Set request.CaseId = "C-TEST-LEAD-C", request.Actor = "approver", request.Reason = "the instance died in the restart"
    Do $$$AssertStatusOK(wf.OnAbandon(request, .response), "the abandon")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-C").State, "failed", "the case is failed")
    Set after = $CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-C")
    Do $$$AssertEquals(after.State _ "|" _ after.Reason, "failed|the leader was abandoned", "the lead is finished as failed with the reason")
    Do $$$AssertNotEquals(after.EndedAt, "", "and ended")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "Current", sig)), "the signature attracts no follower now")
    Do wf.LeadLeftBehind(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-C"), "again")
    Do $$$AssertEquals($CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-C").Reason, "the leader was abandoned", "a lead already ended keeps its first reason")
    Do wf.LeadLeftBehind(other, "nothing led")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(bl, "ForLeader", "C-TEST-LEAD-D")), "a case that leads nothing finishes nothing")
    Do $$$AssertEquals(##class(Shutter.Store.Case).ByCaseId("C-TEST-LEAD-D").State, "investigating", "and is left as it was")
}

}
