/// Precedents (Shutter.Store.Precedent; CONTRACTS 6.4, v1.35): the signature, the record, the summary's counts and window,
/// retirement, and the words the approval task quotes. The rows are written for a receiver named after this run and
/// deleted at the end.
Class Shutter.Test.Precedents Extends %UnitTest.TestCase
{

Property Receiver As %String;

Property SavedDays As %String;

Method OnBeforeAllTests() As %Status
{
    Set ..Receiver = "test-precedents-" _ $JOB _ "-" _ ($PIECE($ZTIMESTAMP, ",", 2) \ 1)
    Set ..SavedDays = $GET(^Shutter.Config("precedentDays"), $CHAR(0))
    Kill ^Shutter.Config("precedentDays")
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Set r = ..Receiver
    &sql(DELETE FROM Shutter_Store.Precedent WHERE Receiver = :r)
    If ..SavedDays = $CHAR(0) { Kill ^Shutter.Config("precedentDays") } Else { Set ^Shutter.Config("precedentDays") = ..SavedDays }
    Quit $$$OK
}

Method Conditions(answer As %String = "unavailable") As %DynamicObject
{
    Quit {"delivery": "failed", "receiver_answer": (answer), "event": "transfer", "receipt": "absent", "encounter_state": "admitted", "chain": "single"}
}

Method TestSignature()
{
    Set pre = "Shutter.Store.Precedent"
    Set a = ..Conditions()
    Set b = {"chain": "single", "encounter_state": "admitted", "receipt": "absent", "event": "transfer", "receiver_answer": "unavailable", "delivery": "failed"}
    Do $$$AssertEquals($CLASSMETHOD(pre, "SignatureOf", a), $CLASSMETHOD(pre, "SignatureOf", b), "key order does not change the signature")
    Do $$$AssertTrue($MATCH($CLASSMETHOD(pre, "SignatureOf", a), "^sha256:[0-9a-f]{64}$"), "a SHA-256 in hex, as every digest")
    Do $$$AssertNotEquals($CLASSMETHOD(pre, "SignatureOf", a), $CLASSMETHOD(pre, "SignatureOf", ..Conditions("timeout")), "one value changed, another signature")
    Do $$$AssertEquals($CLASSMETHOD(pre, "SignatureOf", ""), "", "no conditions, no signature")
}

Method TestRecordAndSummary()
{
    Set pre = "Shutter.Store.Precedent", r = ..Receiver
    Set policy = ##class(Shutter.Operation.Gate).#POLICYVERSION
    Set profile = ##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0)
    Set s = $CLASSMETHOD(pre, "Summary", r, ..Conditions())
    Do $$$AssertEquals(s.approved _ "/" _ s.rejected, "0/0", "nothing recorded yet")
    Do $$$AssertEquals(s.windowDays, 180, "the default window")
    Do $$$AssertEquals($CLASSMETHOD(pre, "Words", s), "Precedents: none; these conditions at this receiver have not reached an approver in the last 180 days.", "the words for none")
    Set sc = $CLASSMETHOD(pre, "RecordValues", "C-TEST-1", r, ..Conditions(), "E03", "resend", "resend", "sha256:one", "approver", "approved", policy, profile, .p1)
    Do $$$AssertStatusOK(sc, "an approved precedent is written")
    Do $$$AssertEquals(p1.Signature, $CLASSMETHOD(pre, "SignatureOf", ..Conditions()), "with the conditions' signature")
    Do $$$AssertTrue(p1.Active, "active")
    Set sc = $CLASSMETHOD(pre, "RecordValues", "C-TEST-2", r, ..Conditions(), "E03", "resend", "resend", "sha256:two", "approver2", "approved", policy, profile, .p2)
    Do $$$AssertStatusOK(sc, "a second approval")
    Set sc = $CLASSMETHOD(pre, "RecordValues", "C-TEST-3", r, ..Conditions(), "E03", "resend", "resend", "sha256:three", "approver", "rejected", policy, profile, .p3)
    Do $$$AssertStatusOK(sc, "a rejection")
    Set sc = $CLASSMETHOD(pre, "RecordValues", "C-TEST-4", r, ..Conditions(), "E03", "resend", "resend", "sha256:four", "approver", "maybe", policy, profile, .p4)
    Do $$$AssertStatusNotOK(sc, "a decision is approved or rejected")
    Set sc = $CLASSMETHOD(pre, "RecordValues", "C-TEST-5", r, "", "E03", "resend", "resend", "sha256:five", "approver", "approved", policy, profile, .p5)
    Do $$$AssertStatusNotOK(sc, "no conditions, no precedent")
    Set s = $CLASSMETHOD(pre, "Summary", r, ..Conditions())
    Do $$$AssertEquals(s.approved _ "/" _ s.rejected, "2/1", "two approved, one rejected")
    Do $$$AssertEquals(s.lastDecision _ "|" _ s.lastApprover _ "|" _ s.lastCaseId, "rejected|approver|C-TEST-3", "the last decision is the newest row")
    Do $$$AssertTrue(s.samePolicy, "taken under the policy and profile in force")
    Do $$$AssertEquals($EXTRACT(s.lastAt, 1, 10), $EXTRACT(##class(Shutter.Util.Time).NowUTC(), 1, 10), "dated now")
    Set words = $CLASSMETHOD(pre, "Words", s)
    Do $$$AssertTrue(words [ "approved and verified 2 times, rejected 1 time in the last 180 days; last rejected by approver on ", "the words carry the counts and the last decision: " _ words)
    Do $$$AssertTrue(words [ "(case C-TEST-3).", "and the case")
    Do $$$AssertNotTrue(words [ "earlier policy", "nothing about the policy when it is the same")
    Set other = $CLASSMETHOD(pre, "Summary", r, ..Conditions("timeout"))
    Do $$$AssertEquals(other.approved _ "/" _ other.rejected, "0/0", "other conditions, no precedent")
    Set elsewhere = $CLASSMETHOD(pre, "Summary", r _ "-other", ..Conditions())
    Do $$$AssertEquals(elsewhere.approved _ "/" _ elsewhere.rejected, "0/0", "another receiver, no precedent")
    // An earlier policy or profile shows in samePolicy and in the words.
    Set sc = $CLASSMETHOD(pre, "RecordValues", "C-TEST-6", r, ..Conditions("duplicate"), "E03", "resend", "resend", "sha256:six", "approver", "approved", "2020-01-01.1", profile, .p6)
    Set s = $CLASSMETHOD(pre, "Summary", r, ..Conditions("duplicate"))
    Do $$$AssertNotTrue(s.samePolicy, "an earlier policy version")
    Do $$$AssertTrue($CLASSMETHOD(pre, "Words", s) [ ", under an earlier policy or site profile.", "said in the words")
}

Method TestWindowAndRetire()
{
    Set pre = "Shutter.Store.Precedent", r = ..Receiver
    Set c = ..Conditions("rejected")
    Set sc = $CLASSMETHOD(pre, "RecordValues", "C-TEST-7", r, c, "E03", "resend", "resend", "sha256:seven", "approver", "approved", "", "", .old)
    Do $$$AssertStatusOK(sc, "written")
    Set old.CreatedAt = ##class(Shutter.Util.Time).FromNow(-200 * 86400)
    Do $$$AssertStatusOK(old.%Save(), "dated 200 days back")
    Do $$$AssertEquals($CLASSMETHOD(pre, "Summary", r, c).approved, 0, "outside the 180-day window it counts for nothing")
    Set ^Shutter.Config("precedentDays") = 365
    Do $$$AssertEquals($CLASSMETHOD(pre, "Days"), 365, "the window from the configuration")
    Do $$$AssertEquals($CLASSMETHOD(pre, "Summary", r, c).approved, 1, "inside a year it counts")
    Set ^Shutter.Config("precedentDays") = "abc"
    Do $$$AssertEquals($CLASSMETHOD(pre, "Days"), 180, "a bad value means the default")
    Set ^Shutter.Config("precedentDays") = 5000
    Do $$$AssertEquals($CLASSMETHOD(pre, "Days"), 180, "and so does one over ten years")
    Set ^Shutter.Config("precedentDays") = 365
    Set why = $CLASSMETHOD(pre, "Retire", old.%Id(), "approver", "the receiver changed its API", .p)
    Do $$$AssertEquals(why, "", "retired")
    Do $$$AssertNotTrue(p.Active, "inactive")
    Do $$$AssertEquals(p.RetiredBy _ "|" _ p.RetiredReason, "approver|the receiver changed its API", "by whom and why")
    Do $$$AssertEquals($CLASSMETHOD(pre, "Summary", r, c).approved, 0, "a retired precedent counts for nothing")
    Do $$$AssertEquals($CLASSMETHOD(pre, "Retire", old.%Id(), "approver", "", .p), "already_retired", "retired once")
    Do $$$AssertEquals($CLASSMETHOD(pre, "Retire", 999999999, "approver", "", .p), "not_found", "no such precedent")
    Set proj = old.Projection()
    Do $$$AssertEquals(proj.%GetTypeOf("conditions"), "object", "the projection carries the conditions as an object")
    Do $$$AssertEquals(proj.conditions."receiver_answer", "rejected", "with their values")
    Do $$$AssertEquals(proj.id, old.%Id(), "and the id")
    Kill ^Shutter.Config("precedentDays")
}

/// The precedent is signed with the snapshot the plan was made from, not a later one the approver never saw.
Method TestRecordUsesThePlanSnapshot()
{
    Set pre = "Shutter.Store.Precedent"
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "C-TEST-9", case.Receiver = ..Receiver
    Set seen = ##class(Shutter.Store.Snapshot).%New(), later = ##class(Shutter.Store.Snapshot).%New()
    Set seen.Summary = {"catalogue": {"conditions": (..Conditions("unavailable")), "entry": "E2", "outcome": "resend"}}.%ToJSON()
    Set later.Summary = {"catalogue": {"conditions": (..Conditions("timeout")), "entry": "E3", "outcome": "wait"}}.%ToJSON()
    Set case.CurrentSnapshot = later
    Set plan = ##class(Shutter.Store.Plan).%New()
    Set plan.Snapshot = seen, plan.Digest = "sha256:plan-nine", plan.Disposition = "resend"
    Set approval = ##class(Shutter.Store.Approval).%New()
    Set approval.Approver = "approver", approval.PolicyVersion = "p", approval.SiteProfileVersion = "1"
    Do $$$AssertStatusOK($CLASSMETHOD(pre, "Record", case, plan, approval, "approved", .p), "recorded")
    Do $$$AssertTrue($ISOBJECT(p), "a row")
    Do $$$AssertEquals(p.Signature, $CLASSMETHOD(pre, "SignatureOf", ..Conditions("unavailable")), "signed with the plan's snapshot")
    Do $$$AssertNotEquals(p.Signature, $CLASSMETHOD(pre, "SignatureOf", ..Conditions("timeout")), "not with the later one")
    Do $$$AssertEquals(p.CatalogueEntry _ "|" _ p.CatalogueOutcome, "E2|resend", "and its entry and outcome")
    Set plan.Snapshot = ""
    Do $$$AssertStatusOK($CLASSMETHOD(pre, "Record", case, plan, approval, "rejected", .q), "a plan with no snapshot falls back to the case's")
    Do $$$AssertEquals(q.Signature, $CLASSMETHOD(pre, "SignatureOf", ..Conditions("timeout")), "the current snapshot then")
}

Method TestRecordGuards()
{
    Set pre = "Shutter.Store.Precedent"
    Set case = ##class(Shutter.Store.Case).%New(), plan = ##class(Shutter.Store.Plan).%New(), approval = ##class(Shutter.Store.Approval).%New()
    Set case.CaseId = "C-TEST-8", case.Receiver = ..Receiver
    Set approval.Approver = "policy"
    Do $$$AssertStatusOK($CLASSMETHOD(pre, "Record", case, plan, approval, "approved", .p), "an automatic release is no error")
    Do $$$AssertNotTrue($ISOBJECT(p), "and writes nothing")
    Set approval.Approver = "approver"
    Do $$$AssertStatusOK($CLASSMETHOD(pre, "Record", case, plan, approval, "approved", .p), "a case with no snapshot is no error")
    Do $$$AssertNotTrue($ISOBJECT(p), "and writes nothing either")
    Do $$$AssertStatusOK($CLASSMETHOD(pre, "Record", "", plan, approval, "approved", .p), "no case, nothing")
    Do $$$AssertEquals($CLASSMETHOD(pre, "Summary", ..Receiver, "").approved, 0, "a summary with no conditions is empty")
    Do $$$AssertEquals($CLASSMETHOD(pre, "Words", ""), "", "and has no words")
}

}
