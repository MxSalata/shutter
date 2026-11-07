/// The incident plan and its digest (CONTRACTS 7.2), built by Shutter.Store.Incident.BuildPlan with no business process:
/// the digest is the SHA-256 of the recorded plan in canonical JSON, so GET /incidents/{id}.plan without its digest
/// member recomputes it, and it moves when any item's case, entry or outcome, any payload digest, the receiver's epoch
/// or a version moves. The fixture is an incident with an ordered policy chain of two E4 items under an approval and a
/// single automatic E2 chain, each item a UT-INC- case with a sealed snapshot; everything is deleted after each test,
/// and nothing takes a public number.
Class Shutter.Test.IncidentPlan Extends %UnitTest.TestCase
{

Parameter POLICY = "2026-10-26.1";

/// The incidents made by the current test, for the clean-up.
Property Made As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
    // Rows a run that stopped half-way may have left.
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.Incident WHERE IncidentId %STARTSWITH 'UT-INC-'")
    While rs.%Next() { Do ..Purge(rs.%Get("ID")) }
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId %STARTSWITH 'UT-INC-'")
    While rs.%Next() { Do ..PurgeCase(rs.%Get("ID")) }
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ..Purge(id)
    }
    Kill i%Made
    Quit $$$OK
}

/// The digest is the SHA-256 of the recorded plan, in canonical JSON, without its digest member; the plan lists each
/// item's case, entry, outcome, who decides and the version it goes at.
Method TestDigestIsCanonicalJsonOfThePlan()
{
    Set inc = ..NewIncident()
    Do $$$AssertStatusOK(inc.BuildPlan(..#POLICY), "the plan is built")
    Set plan = ##class(%DynamicObject).%FromJSON(inc.PlanJSON)
    Do $$$AssertEquals(plan.digest, inc.PlanDigest, "the plan records its digest")
    Do plan.%Remove("digest")
    Do $$$AssertEquals(##class(Shutter.Util.Digest).OfObject(plan), inc.PlanDigest, "which is the digest of the plan without it")
    Do $$$AssertEquals(plan."gate_policy_version", ..#POLICY, "the gate's policy version is bound")
    Do $$$AssertEquals(inc.PolicyVersion, ..#POLICY, "and recorded on the incident")
    Do $$$AssertEquals(plan."receiver_epoch", 1, "the receiver's epoch is bound")
    Do $$$AssertEquals(inc.ReceiverEpoch, 1, "and recorded")
    Do $$$AssertEquals(plan."incident_id", inc.IncidentId, "the plan names the incident")
    Do $$$AssertEquals(plan.chains.%Size(), 2, "two chains")
    Set first = plan.chains.%Get(0), second = plan.chains.%Get(1)
    Do $$$AssertEquals(first.kind _ " " _ first.decides _ " " _ first.policy _ " " _ first.entries, "ordered policy approval E4,E4", "the ordered chain as classified")
    Do $$$AssertEquals(first."first_expected_version", 1, "and its first expected version")
    Do $$$AssertEquals(first.items.%Size(), 2, "with two items")
    Set item = first.items.%Get(0)
    Do $$$AssertEquals(item."case_id", inc.IncidentId _ "-1-1", "an item names its case")
    Do $$$AssertEquals(item.entry _ " " _ item.outcome _ " " _ item.decides, "E4 resend_chain policy", "its entry, outcome and who decides")
    Do $$$AssertEquals(item."payload_digest", "sha256:ut-1-1", "its payload digest")
    Do $$$AssertEquals(item."operation_key", inc.ChainAt(1).ItemAt(1).Case.OperationKey, "and its operation key")
    Do $$$AssertEquals(item."expected_version", 1, "the first item of an approved chain goes at the chain's first expected version")
    Do $$$AssertEquals(first.items.%Get(1).%GetTypeOf("expected_version"), "null", "the second at the version the first verifies, unknown yet")
    Do $$$AssertEquals(second.items.%Get(0).%GetTypeOf("expected_version"), "null", "an automatic chain's first item goes on fresh evidence")
    Do $$$AssertEquals(second.items.%Get(0)."case_id", inc.IncidentId _ "-2-1", "the single chain's item names its case")
}

/// Every item's case, entry and outcome move the digest, and the same plan built twice gives the same digest.
Method TestDigestBindsEachItem()
{
    Set inc = ..NewIncident()
    Set base = ..Digest(inc)
    Do $$$AssertEquals(..Digest(inc), base, "the digest is deterministic")
    Set item = inc.ChainAt(1).ItemAt(2)
    Set entry = item.Entry, outcome = item.CatalogueOutcome
    Set item.Entry = "E2", item.CatalogueOutcome = "resend"
    Do $$$AssertStatusOK(item.%Save(), "item 1.2 changed to E2 resend")
    Do $$$AssertNotEquals(..Digest(inc), base, "another entry and outcome for one item moves the digest")
    Set item.Entry = entry
    Do $$$AssertStatusOK(item.%Save(), "the entry put back, the outcome still changed")
    Do $$$AssertNotEquals(..Digest(inc), base, "another outcome alone moves it")
    Set item.CatalogueOutcome = outcome
    Do $$$AssertStatusOK(item.%Save(), "item 1.2 as it was")
    Do $$$AssertEquals(..Digest(inc), base, "and the digest is back")
    // The two items' cases swapped: the same keys and payloads, in another order of cases.
    Set one = inc.ChainAt(1).ItemAt(1), two = inc.ChainAt(1).ItemAt(2)
    Set c1 = one.CaseGetObjectId(), c2 = two.CaseGetObjectId()
    Do one.CaseSetObjectId(c2), two.CaseSetObjectId(c1)
    Do $$$AssertStatusOK(one.%Save(), "item 1.1 holds the other case")
    Do $$$AssertStatusOK(two.%Save(), "and item 1.2 the first")
    Do $$$AssertNotEquals(..Digest(inc), base, "the items' cases in another order move the digest")
}

/// The payload digests, the receiver's epoch and the versions still bind, as they did before the plan was hashed whole.
Method TestDigestBindsVersionsAndEpoch()
{
    Set inc = ..NewIncident()
    Set base = ..Digest(inc)
    Do $$$AssertStatusOK(inc.BuildPlan("2026-01-01.1"), "the plan is built under another policy version")
    Do $$$AssertNotEquals(inc.PlanDigest, base, "another gate policy version moves the digest")
    Do $$$AssertEquals(..Digest(inc), base, "and the same one gives it back")
    Set case = inc.ChainAt(1).ItemAt(1).Case
    Do ..Observe(case, "sha256:ut-1-1", 2)
    Do $$$AssertNotEquals(..Digest(inc), base, "another receiver epoch moves the digest")
    Do ..Observe(case, "sha256:ut-other", 1)
    Do $$$AssertNotEquals(..Digest(inc), base, "another payload digest moves it")
    Do ..Observe(case, "sha256:ut-1-1", 1)
    Do $$$AssertEquals(..Digest(inc), base, "the same evidence gives it back")
}

/// An acknowledged write, on the contract's answer: {applied, receipt: {version_after}, encounter: {version}}. Another
/// system moved the encounter on before the verification's read, and the next item goes at the receipt's version.
Method TestVersionAfterAnAppliedWrite()
{
    Set item = ..NewIncident().ChainAt(1).ItemAt(1), case = item.Case
    Set answer = {"applied": true, "receipt": {"version_after": 2}, "encounter": {"version": 2}}
    Set attempt = ..Attempt(case, "applied", 200, answer)
    Do ..Verified(case, attempt, 200, {"version_after": 2}, {"version": 3})
    Do $$$AssertEquals(..Workflow().VersionAfter(case, item), 2, "the receipt of the write, not the encounter as read at verification")
}

/// A write whose answer was lost has no answer to read: its receipt comes from the verification.
Method TestVersionAfterALostAnswer()
{
    Set item = ..NewIncident().ChainAt(1).ItemAt(1), case = item.Case
    Set attempt = ..Attempt(case, "uncertain", 0, {})
    Do ..Verified(case, attempt, 200, {"version_after": 2}, {"version": 3})
    Do $$$AssertEquals(..Workflow().VersionAfter(case, item), 2, "the receipt the verification read")
}

/// A reconcile writes nothing: the receipt found is the operation's own, and the encounter may have moved since. The
/// next item then stops for a person, which is the safe direction.
Method TestVersionAfterAReconcile()
{
    Set item = ..NewIncident().ChainAt(1).ItemAt(1), case = item.Case
    Do ..Verified(case, "", 200, {"version_after": 2}, {"version": 3})
    Do $$$AssertEquals(..Workflow().VersionAfter(case, item), 2, "the receipt found")
}

/// A receiver that keeps no receipts: the history entry holding the operation's key says where it landed.
Method TestVersionAfterOnAReceiverWithNoReceipts()
{
    Set item = ..NewIncident().ChainAt(1).ItemAt(1), case = item.Case
    Set attempt = ..Attempt(case, "uncertain", 0, {})
    Set encounter = {"version": 3, "history": [{"operation_key": "another", "version_after": 1}, {"operation_key": (case.OperationKey), "version_after": 2}, {"operation_key": "a later one", "version_after": 3}]}
    Do ..Verified(case, attempt, -1, {}, encounter)
    Do $$$AssertEquals(..Workflow().VersionAfter(case, item), 2, "the history entry of the operation")
}

/// A write acknowledged by a receiver that answers with no receipt: its answer still gives the version.
Method TestVersionAfterAnAnswerWithNoReceipt()
{
    Set item = ..NewIncident().ChainAt(1).ItemAt(1), case = item.Case
    Set attempt = ..Attempt(case, "applied", 200, {"applied": true, "version_after": 2})
    Do ..Verified(case, attempt, -1, {}, {"version": 3})
    Do $$$AssertEquals(..Workflow().VersionAfter(case, item), 2, "the version in the answer")
    Set item = ..NewIncident().ChainAt(1).ItemAt(1), case = item.Case
    Set attempt = ..Attempt(case, "applied", 200, {"applied": true, "encounter": {"version": 2}})
    Do ..Verified(case, attempt, -1, {}, {"version": 3})
    Do $$$AssertEquals(..Workflow().VersionAfter(case, item), 2, "the encounter in the answer, as the write left it")
}

/// A closure with no write and no receipt (superseded): only the encounter as read is left, and a failed receipt
/// lookup's body is not a receipt.
Method TestVersionAfterAClosureWithNoReceipt()
{
    Set item = ..NewIncident().ChainAt(1).ItemAt(1), case = item.Case
    Do ..Verified(case, "", 404, {"error": "not_found"}, {"version": 3})
    Do $$$AssertEquals(..Workflow().VersionAfter(case, item), 3, "the encounter as read")
    Set item = ..NewIncident().ChainAt(1).ItemAt(1), case = item.Case
    Do ..Verified(case, "", 503, {"version_after": 9}, {"version": 3})
    Do $$$AssertEquals(..Workflow().VersionAfter(case, item), 3, "not a body the receipt lookup answered with an error")
    Set item = ..NewIncident().ChainAt(1).ItemAt(1)
    Set item.ExpectedVersion = 7
    Do $$$AssertEquals(..Workflow().VersionAfter(item.Case, item), 7, "and with nothing recorded, the version the item expected")
}

/// The sequence rule (7.4): the next item at the previous receipt's version, the receiver one past it. Nothing goes, and
/// a person looks. Driven with the case workflow's send to the gate taken away.
Method TestTheSequenceRuleStopsAtAMovedVersion()
{
    Set inc = ..NewIncident(), item = inc.ChainAt(1).ItemAt(2), case = item.Case
    Set wf = ##class(Shutter.Test.QuietWorkflow).%New("Case Workflow")
    Set wf.CaseId = case.CaseId, wf.Mode = "policy", wf.Release = 1, wf.IncidentId = inc.IncidentId, wf.ChainSeq = 1, wf.ChainDecides = "policy", wf.ExpectedVersion = 2
    Set case.State = "collecting"
    Do $$$AssertStatusOK(case.%Save(), "the released case collects its evidence")
    Set result = ##class(Shutter.Msg.EvidenceResult).%New()
    Set result.SummaryJSON = {"ward_state": {"version": 3}, "catalogue": {"decision": "policy"}}.%ToJSON()
    Do $$$AssertStatusOK(wf.OnEvidence(case, result), "the evidence is read")
    Set case = ##class(Shutter.Store.Case).ByCaseId(case.CaseId)
    Do $$$AssertEquals(case.State, "blocked", "the item does not go")
    Do $$$AssertTrue(case.Headline [ "sequence rule", "the headline names the rule: " _ case.Headline)
    Do $$$AssertTrue(case.Headline [ "version 3", "and the version it found")
}

/// An instance of the incident workflow outside the production.
Method Workflow() As Shutter.Test.QuietIncident
{
    Quit ##class(Shutter.Test.QuietIncident).%New("Incident Workflow")
}

/// A write attempt of the case, as the connector records one, under a plan of its own.
Method Attempt(case As Shutter.Store.Case, outcome As %String, status As %Integer, answer As %DynamicObject) As Shutter.Store.ExecutionAttempt
{
    Set planObj = {"disposition": "resend", "action": {"type": "resend", "operation_key": (case.OperationKey), "expected_version": 1, "payload_digest": "sha256:ut"}, "summary": "Resend the operation"}
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, case.CurrentSnapshot, planObj, "policy:E4", .plan), "the plan is saved")
    Do $$$AssertStatusOK(##class(Shutter.Store.ExecutionAttempt).Create(case, plan, "", "", status, outcome, answer, "", .attempt), "the attempt is saved")
    Quit attempt
}

/// A verification of the case with the two reads the verifier records.
Method Verified(case As Shutter.Store.Case, attempt As Shutter.Store.ExecutionAttempt, receiptStatus As %Integer, receipt As %DynamicObject, encounter As %DynamicObject)
{
    Set detail = {"encounter_http_status": 200, "encounter": (encounter), "receipt_http_status": (receiptStatus), "receipt": (receipt)}
    Do $$$AssertStatusOK(##class(Shutter.Store.Verification).Create(case, attempt, "verified", "unit test", detail, .v), "the verification is saved")
}

/// Builds the plan again and returns its digest.
Method Digest(inc As Shutter.Store.Incident) As %String
{
    Do $$$AssertStatusOK(inc.BuildPlan(..#POLICY), "the plan is built")
    Quit inc.PlanDigest
}

/// The fixture: an incident with chain 1 (ordered, policy, under an approval, first expected version 1, two E4
/// resend_chain items) and chain 2 (single, automatic, one E2 resend item), its chains and items in the store.
Method NewIncident() As Shutter.Store.Incident
{
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set inc = ##class(Shutter.Store.Incident).%New()
    Set inc.IncidentId = "UT-INC-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.IncidentPlan)
    Set inc.Receiver = $PARAMETER("Shutter.Production", "RECEIVER"), inc.Mode = "policy", inc.State = "classified"
    Set inc.OpenedAt = now, inc.LastFailureAt = now, inc.IntakeClosedAt = now
    Do $$$AssertStatusOK(inc.%Save(), "the incident " _ inc.IncidentId _ " is saved")
    Set i%Made(inc.%Id()) = ""
    Set items = $LISTBUILD($LISTBUILD("transfer", "2026-10-19T09:00:00Z", "E4", "resend_chain"), $LISTBUILD("transfer", "2026-10-19T09:30:00Z", "E4", "resend_chain"))
    Do ..NewChain(inc, 1, "ENC-UTI1", "ordered", "approval", "E4,E4", 1, items)
    Set items = $LISTBUILD($LISTBUILD("transfer", "2026-10-19T09:10:00Z", "E2", "resend"))
    Do ..NewChain(inc, 2, "ENC-UTI2", "single", "automatic", "E2", 3, items)
    Quit inc
}

/// A policy chain of the incident with its items, each $LISTBUILD(event, event time, entry, outcome), as the detector
/// forms and classifies one.
Method NewChain(inc As Shutter.Store.Incident, seq As %Integer, encounter As %String, kind As %String, policy As %String, entries As %String, firstVersion As %Integer, items As %List)
{
    Set ch = ##class(Shutter.Store.Chain).%New()
    Do ch.IncidentSetObjectId(inc.%Id())
    Set ch.Seq = seq, ch.EncounterId = encounter, ch.PatientId = "MRN-" _ encounter, ch.PatientIdAuthority = "HOSP"
    Set ch.Kind = kind, ch.Decides = "policy", ch.Policy = policy, ch.Entries = entries, ch.FirstExpectedVersion = firstVersion
    Set ch.State = $SELECT(policy = "automatic": "approved", 1: "awaiting_approval")
    Do $$$AssertStatusOK(ch.%Save(), "chain " _ seq _ " is saved")
    For p = 1:1:$LISTLENGTH(items) {
        Set spec = $LIST(items, p)
        Set case = ..NewCase(inc, seq, p, encounter, $LIST(spec, 1), $LIST(spec, 2))
        Set it = ##class(Shutter.Store.ChainItem).%New()
        Do it.ChainSetObjectId(ch.%Id())
        Do it.CaseSetObjectId(case.%Id())
        Set it.Position = p, it.Entry = $LIST(spec, 3), it.CatalogueOutcome = $LIST(spec, 4), it.Decides = "policy"
        Do $$$AssertStatusOK(it.%Save(), "item " _ seq _ "." _ p _ " is saved")
    }
}

/// A grouped case of the incident, named <incident>-<seq>-<position>, with a sealed snapshot as its current one.
Method NewCase(inc As Shutter.Store.Incident, seq As %Integer, position As %Integer, encounter As %String, event As %String, eventTime As %String) As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = inc.IncidentId _ "-" _ seq _ "-" _ position
    Set case.Event = event, case.EventTime = eventTime, case.EncounterId = encounter
    Set case.PatientId = "MRN-" _ encounter, case.PatientIdAuthority = "HOSP"
    Set case.FailureKind = "delivery_failed", case.FailureText = "Delivery unavailable (ward_unavailable), HTTP 503"
    Set case.SourceSystem = "PAS", case.Ward = "WARD-B", case.Receiver = inc.Receiver
    Set case.OperationKey = "PAS^HOSP^" _ case.PatientId _ "^" _ encounter _ "^" _ event _ "^" _ eventTime
    Set case.State = "grouped", case.Mode = "policy"
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Do case.IncidentSetObjectId(inc.%Id())
    Do $$$AssertStatusOK(case.%Save(), "the case " _ case.CaseId _ " is saved")
    Do ..Observe(case, "sha256:ut-" _ seq _ "-" _ position, 1)
    Quit case
}

/// A sealed snapshot with the operation's payload digest and the receiver's epoch, made the case's current one.
Method Observe(case As Shutter.Store.Case, payload As %String, epoch As %Integer)
{
    Set summary = {"operation": {"operation_key": (case.OperationKey), "payload_digest": (payload)}, "epoch": (epoch), "ward_state_http_status": 200, "ward_state": {"state": "admitted", "ward": "WARD-A", "version": 1, "epoch": (epoch)}, "validation": {"parsed": true}}
    Set snap = ##class(Shutter.Store.Snapshot).Begin(case, 300)
    Do $$$AssertStatusOK(snap.Seal(summary), "the snapshot of " _ case.CaseId _ " is sealed")
    // The current snapshot is written only through SetSnapshot: a whole save keeps the stored one.
    Do $$$AssertStatusOK(case.SetSnapshot(snap), "and is the case's current one")
}

/// Deletes a test incident with its chains, items and events, and its cases with everything recorded for them.
ClassMethod Purge(id As %String)
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE Incident = ?", id)
    While rs.%Next() { Do ..PurgeCase(rs.%Get("ID")) }
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.ChainItem WHERE Chain IN (SELECT ID FROM Shutter_Store.Chain WHERE Incident = ?)", id)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.Chain WHERE Incident = ?", id)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.IncidentEvent WHERE Incident = ?", id)
    Do ##class(Shutter.Store.Incident).%DeleteId(id)
    Kill ^Shutter.Counter("incidentEvent", id)
}

/// Deletes a test case and everything the stores recorded for it, as Shutter.Test.Gate does.
ClassMethod PurgeCase(id As %String)
{
    For table = "Shutter_Store.Verification", "Shutter_Store.ExecutionAttempt", "Shutter_Store.GateDecision", "Shutter_Store.Approval", "Shutter_Store.Plan", "Shutter_Store.CaseEvent" {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ table _ " WHERE ""Case"" = ?", id)
    }
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.SnapshotItem WHERE Snapshot IN (SELECT ID FROM Shutter_Store.Snapshot WHERE ""Case"" = ?)", id)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.Snapshot WHERE ""Case"" = ?", id)
    Do ##class(Shutter.Store.Case).%DeleteId(id)
    Kill ^Shutter.Counter("event", id), ^Shutter.Counter("plan", id), ^Shutter.Counter("snapshot", id)
}

}
