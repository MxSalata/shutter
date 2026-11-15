/// What the tests of the site's own catalogue entries (CONTRACTS 6.8) share: a stored, closed case with evidence the
/// matcher reads as a plain failed transfer, an entry's body, the two-person walk to an active entry, and the way back
/// to an instance that never had one.
Class Shutter.Test.SiteKit
{

Parameter EVENTTIME = "2026-10-19T09:00:00Z";

/// The evidence of a transfer the receiver was unavailable for: admitted, nothing later, no receipt.
ClassMethod Summary(case As Shutter.Store.Case, patch As %DynamicObject = "") As %DynamicObject
{
    Set s = {
        "operation": {"operation_key": (case.OperationKey), "payload_digest": "sha256:ut", "source_system": "PAS"},
        "failure": {"reason_code": "ward_unavailable", "http_status": 503},
        "ward_state_http_status": 200,
        "ward_state": {"patient_id": (case.PatientId), "patient_id_authority": "HOSP", "state": "admitted", "ward": "WARD-A", "version": 3, "epoch": 1, "history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z", "ward": "WARD-A", "operation_key": ("PAS^HOSP^" _ case.PatientId _ "^" _ case.EncounterId _ "^admit^2026-10-18T08:00:00Z")}]},
        "receipt_http_status": 404,
        "validation": {"parsed": true},
        "route": {"capabilities_http_status": 200, "capabilities": {"conditional_writes": true}, "conditional_writes": true, "receipts": true, "history": true, "dry_run": true},
        "timeline": []
    }
    If $ISOBJECT(patch) {
        Set it = patch.%GetIterator()
        While it.%GetNext(.key, .value) { Do s.%Set(key, value) }
    }
    Quit s
}

/// A saved case with a sealed snapshot whose catalogue item is the matcher's own answer now. spec: id, ward (WARD-ISO),
/// event (transfer), state (escalated), mode (policy), failure_kind, summary (a patch of the evidence).
ClassMethod Case(spec As %DynamicObject, Output snapshot As Shutter.Store.Snapshot) As Shutter.Store.Case
{
    Set json = "Shutter.Util.Json"
    Set id = $CLASSMETHOD(json, "Str", spec, "id", "UT-SITE-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.Site))
    Do ..Purge(id)
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = id
    Set case.Event = $CLASSMETHOD(json, "Str", spec, "event", "transfer")
    Set case.FailureKind = $CLASSMETHOD(json, "Str", spec, "failure_kind", "delivery_failed")
    Set case.FailureText = "Delivery unavailable (ward_unavailable), HTTP 503"
    Set case.EncounterId = "ENC-" _ id, case.PatientId = "MRN-" _ id, case.PatientIdAuthority = "HOSP"
    Set case.EventTime = ..#EVENTTIME, case.SourceSystem = "PAS", case.Ward = $CLASSMETHOD(json, "Str", spec, "ward", "WARD-ISO")
    Set case.Receiver = $PARAMETER("Shutter.Production", "RECEIVER")
    Set case.OperationKey = "PAS^HOSP^" _ case.PatientId _ "^" _ case.EncounterId _ "^" _ case.Event _ "^" _ case.EventTime
    Set case.State = $CLASSMETHOD(json, "Str", spec, "state", "escalated"), case.Mode = $CLASSMETHOD(json, "Str", spec, "mode", "policy")
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    $$$ThrowOnError(case.%Save())
    Set snapshot = ..Snapshot(case, $SELECT($ISOBJECT(spec): spec.%Get("summary"), 1: ""))
    Quit case
}

/// A fresh snapshot of the case, matched now, made its current one.
ClassMethod Snapshot(case As Shutter.Store.Case, patch As %DynamicObject = "") As Shutter.Store.Snapshot
{
    Set summary = ..Summary(case, patch)
    Set matcher = "Shutter.Catalogue.Matcher"
    Set summary.catalogue = $CLASSMETHOD(matcher, "Match", $CLASSMETHOD(matcher, "Conditions", case, summary, "single"), $CLASSMETHOD(matcher, "Facts", summary, case), $CLASSMETHOD(matcher, "Scope", case, summary))
    Set snap = ##class(Shutter.Store.Snapshot).Begin(case, 300)
    $$$ThrowOnError(snap.Seal(summary))
    $$$ThrowOnError(case.SetSnapshot(snap))
    Quit snap
}

/// The case and everything stored for it removed.
ClassMethod Purge(caseId As %String)
{
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Quit
    Set id = case.%Id()
    Kill case
    For table = "Shutter_Store.GateDecision", "Shutter_Store.Approval", "Shutter_Store.Rehearsal", "Shutter_Store.Verification", "Shutter_Store.Plan", "Shutter_Store.CaseEvent" {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ table _ " WHERE ""Case"" = ?", id)
    }
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.SnapshotItem WHERE Snapshot IN (SELECT ID FROM Shutter_Store.Snapshot WHERE ""Case"" = ?)", id)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.Snapshot WHERE ""Case"" = ?", id)
    Do ##class(Shutter.Store.Case).%DeleteId(id)
    Kill ^Shutter.Counter("event", id), ^Shutter.Counter("plan", id), ^Shutter.Counter("snapshot", id)
}

/// Every case the kit made in this process removed.
ClassMethod PurgeAll()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT CaseId FROM Shutter_Store.""Case"" WHERE CaseId %STARTSWITH 'UT-SITE-'")
    While rs.%Next() { Do ..Purge(rs.%Get("CaseId")) }
}

/// The site entries, their generation and the two-person lift gone, and the installed vocabulary in force again: the
/// instance as one that never had a site entry.
ClassMethod Reset() As %Status
{
    Set sc = ##class(Shutter.Catalogue.SiteEntry).RemoveAll()
    Kill ^Shutter.Catalogue.Vocabulary
    Do ##class(Shutter.Catalogue.Vocabulary).Current()
    Quit sc
}

/// A body: a failed transfer into WARD-ISO goes to a person, proved on a matching case and a near miss.
ClassMethod Body(matchCase As %String = "", nearCase As %String = "") As %DynamicObject
{
    Set b = {
        "title": "A failed transfer into the isolation ward",
        "priority": 10,
        "scope": {"ward": ["WARD-ISO"], "source_system": ["PAS"]},
        "pattern": {"event": "transfer", "delivery": ["failed", "rejected", "uncertain"]},
        "why": "Infection control places every patient in this ward by hand, so a resend cannot know the bed is right.",
        "instructions": "Ring the ward's nurse in charge before anything is entered. Do not resend.",
        "fixtures": []
    }
    If matchCase '= "" Do b.fixtures.%Push({"case": (matchCase), "expect": "match"})
    If nearCase '= "" Do b.fixtures.%Push({"case": (nearCase), "expect": "no_match"})
    Quit b
}

/// A draft made, proved, proposed by one person and approved by another. Returns "" and the id, or the step that
/// refused with its code and words.
ClassMethod Activate(body As %DynamicObject, Output id As %String, author As %String = "ut-author", approver As %String = "ut-approver") As %String
{
    Set site = "Shutter.Catalogue.SiteEntry", id = ""
    Set code = $CLASSMETHOD(site, "Create", body, author, "api", .entry, .problems, .warnings)
    If code '= "" Quit "create: " _ code _ " " _ problems.%ToJSON()
    Set id = entry.EntryId
    Quit ..Approve(id, "activate", author, approver)
}

/// An action proved, proposed by one person and approved by another.
ClassMethod Approve(id As %String, action As %String, author As %String = "ut-author", approver As %String = "ut-approver") As %String
{
    Set site = "Shutter.Catalogue.SiteEntry"
    Set code = $CLASSMETHOD(site, "Prove", id, action, author, "api", .result, .detail)
    If code '= "" Quit "proof: " _ code _ " " _ detail
    If 'result.passed Quit "proof: did not pass " _ result.%ToJSON()
    Set code = $CLASSMETHOD(site, "Propose", id, action, author, "api", .entry, .detail)
    If code '= "" Quit "propose: " _ code _ " " _ detail
    Set body = {"action": (action), "version": (entry.ProposalVersion), "digest": (entry.ProposalDigest), "decision": "approve", "reason": "unit test"}
    Set code = $CLASSMETHOD(site, "Decide", id, body, approver, "api", .entry, .detail, .extra)
    If code '= "" Quit "approve: " _ code _ " " _ detail
    Quit ""
}

/// The site entries' lock held in a process of its own until ^Shutter.Test.SiteLock says release (a minute at most), as
/// a long approval would hold it: run with JOB by the test of a recheck that cannot take the lock.
ClassMethod HoldTheLock()
{
    LOCK +^Shutter.Catalogue.Site("lock"):5
    If '$TEST Set ^Shutter.Test.SiteLock = "not held" Quit
    Set ^Shutter.Test.SiteLock = "held"
    For i = 1:1:600 { Quit:($GET(^Shutter.Test.SiteLock) = "release")  Hang 0.1 }
    LOCK -^Shutter.Catalogue.Site("lock")
    Set ^Shutter.Test.SiteLock = "done"
}

/// A matching case and a near miss, stored and closed, and an entry active for them. Returns the entry's id.
ClassMethod ActiveEntry(Output match As Shutter.Store.Case, Output near As Shutter.Store.Case, Output problem As %String) As %String
{
    Set match = ..Case({"ward": "WARD-ISO"}), near = ..Case({"ward": "WARD-B"})
    Set problem = ..Activate(..Body(match.CaseId, near.CaseId), .id)
    Quit id
}

}
