/// The deterministic gate (Shutter.Operation.Gate), check by check: every row of the table in XData Rows builds a case,
/// an evidence snapshot, a plan and, when the row has "approval", an approval, runs the gate's OnGateRequest in process
/// with no production running it, and asserts the checks the row names (check, result, reason code). The rows start
/// from a resend that passes every check and change only what the row is about: "case", "summary" and "plan" are merged
/// into the defaults ("{key}" stands for the case's operation key, null removes a field), "approval" makes an approval
/// for the plan (the request is then at dispatch, otherwise at proposal) bound to a rehearsal of it that "rehearsal"
/// changes (NewRehearsal), "request" sets the gate request's fields (its "stage" names another stage), "profile" changes
/// the site profile for the row only, "incident" makes an incident with that plan digest and puts the case in it (an
/// approval may then carry "incident_plan_digest", "bound_entry" and "bound_outcome", what an incident's approval covered
/// for the item), "contains" lists [check, reason code, text] triples the check's detail must contain. The cases
/// are named UT-GATE-..., never take a public case number, and are deleted with everything the gate recorded for them
/// after each test, as the incidents are; the site profile is put back as it was.
Class Shutter.Test.Gate Extends %UnitTest.TestCase
{

Parameter EVENTTIME = "2026-10-19T09:00:00Z";

/// The case rows made by the current test, for the clean-up.
Property Made As %String [ MultiDimensional ];

/// The incident rows made by the current test.
Property MadeIncidents As %String [ MultiDimensional ];

/// The stored site profile's text before a row changed it, and whether there was a stored row at all.
Property SavedProfile As %String;

Property ProfileChanged As %Boolean [ InitialExpression = 0 ];

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

Method OnBeforeAllTests() As %Status
{
    // Rows a run that stopped half-way may have left.
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId %STARTSWITH 'UT-GATE-'")
    While rs.%Next() { Do ..Purge(rs.%Get("ID")) }
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.Incident WHERE IncidentId %STARTSWITH 'UT-GATE-I-'")
    While rs.%Next() { Do ..PurgeIncident(rs.%Get("ID")) }
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    Do ..RestoreProfile()
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ..Purge(id)
    }
    Kill i%Made
    Set id = ""
    For {
        Set id = $ORDER(i%MadeIncidents(id))
        Quit:id=""
        Do ..PurgeIncident(id)
    }
    Kill i%MadeIncidents
    Quit $$$OK
}

Method TestAPlanThatPassesEveryCheck()
{
    Do ..RunRows("pass")
}

Method TestIdentity()
{
    Do ..RunRows("identity")
}

Method TestConformance()
{
    Do ..RunRows("conformance")
}

Method TestIntent()
{
    Do ..RunRows("intent")
}

Method TestOrdering()
{
    Do ..RunRows("ordering")
}

Method TestStateTransition()
{
    Do ..RunRows("state_transition")
}

Method TestEffect()
{
    Do ..RunRows("effect")
}

Method TestAuthorization()
{
    Do ..RunRows("authorization")
}

Method TestConcurrency()
{
    Do ..RunRows("concurrency")
}

Method TestEvidence()
{
    Do ..RunRows("evidence")
}

Method TestCapability()
{
    Do ..RunRows("capability")
}

/// A receiver with declared features and no api, such as a plain MLLP system, has no paths: nothing is read in its place, the
/// declared capabilities stand and the gate blocks a resend. An entry with both keeps its paths.
Method TestReceiverWithNoApi()
{
    Set sp = "Shutter.Store.SiteProfile"
    Set recs = ##class(Shutter.Store.SiteProfile).Current().%Get("receivers")
    Do recs.%Push({"name": "UT Plain", "system": "a plain MLLP system", "tier": 2, "features": {"conditional_writes": false, "receipts": false, "history": false, "dry_run": false}})
    Do ..ChangeProfile({"receivers": (recs)})
    For kind = "state", "receipt", "capabilities", "operations" {
        Do $$$AssertEquals($CLASSMETHOD(sp, "ReceiverPath", "UT Plain", kind, "ENC-UT", "KEY-UT"), "", "no " _ kind _ " path")
    }
    Do $$$AssertEquals($CLASSMETHOD(sp, "ReceiverLabel", "UT Plain"), "a plain MLLP system", "its label names no API")
    Set demo = $PARAMETER("Shutter.Production", "RECEIVER")
    Do $$$AssertTrue($CLASSMETHOD(sp, "ReceiverPath", demo, "state", "ENC-UT") [ "/encounters/ENC-UT", "an entry with an api keeps its paths")
    Do $$$AssertEquals($CLASSMETHOD(sp, "ReceiverPath", "UT Not In The Profile", "state", "ENC-UT"), $CLASSMETHOD(sp, "ReceiverPath", demo, "state", "ENC-UT"), "and a name the profile does not hold still reads the defaults, which the gate refuses by name")
    Set route = ##class(Shutter.Operation.Evidence).%New("Shutter Evidence (unit test)").Route("UT Plain")
    Do $$$AssertEquals(route."capabilities_source", "declared by the site profile", "the capabilities are the declared ones")
    Do $$$AssertNotTrue(route."conditional_writes", "with conditional writes false")
    Set run = ..Run({"name": "a receiver with no api", "summary": {"route": (route)}})
    Do $$$AssertEquals(..Found(run.checks, "capability", "CONNECTOR_INCAPABLE"), "block", "the gate blocks a resend (" _ ..Codes(run.checks, "capability") _ ")")
}

/// A receiver entry with no capabilities endpoint that declares no features vouches for nothing: the route the evidence
/// collector builds records its capabilities as unread, and the gate answers unknown, never CONNECTOR_CAPABLE on the
/// defaults. An entry that declares its features still passes, and every receiver the stored profile names declares them.
Method TestCapabilityUndeclared()
{
    Set recs = ##class(Shutter.Store.SiteProfile).Current().%Get("receivers")
    Set n = 0, iter = recs.%GetIterator()
    While iter.%GetNext(.i, .r) {
        Set n = n + 1
        Do $$$AssertTrue($ISOBJECT(r.%Get("features")), r.name _ " declares its features")
    }
    Do $$$AssertTrue(n > 0, "the profile names receivers")
    Set api = {"base": "/wardb/api", "state": "/encounters/{encounter}", "receipt": "", "capabilities": "", "operations": "/operations"}
    Do recs.%Push({"name": "UT Ward B", "tier": 2, "api": (api)})
    Do recs.%Push({"name": "UT Ward C", "tier": 2, "api": (api), "features": {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}})
    Do ..ChangeProfile({"receivers": (recs)})
    Set evidence = ##class(Shutter.Operation.Evidence).%New("Shutter Evidence (unit test)")
    // No endpoint, no features: unread, and the gate holds.
    Set route = evidence.Route("UT Ward B")
    Do $$$AssertEquals(route."capabilities_http_status", 0, "an entry with no endpoint and no features: the capabilities are unread")
    Do $$$AssertEquals(route."capabilities_source", "not declared by the site profile", "and the route says so")
    Do $$$AssertNotTrue(route.%IsDefined("conditional_writes"), "no flag is assumed")
    Do $$$AssertEquals(route.%GetTypeOf("capabilities"), "null", "the capabilities are null")
    Do $$$AssertTrue(route.note [ "declares no features", "the note says why: " _ route.note)
    Set run = ..Run({"name": "an undeclared receiver", "summary": {"route": (route)}})
    Do $$$AssertEquals(..Found(run.checks, "capability", "CAPABILITIES_UNREADABLE"), "unknown", "the gate answers unknown (" _ ..Codes(run.checks, "capability") _ ")")
    Do $$$AssertEquals(run.response.Outcome, "unknown", "and the plan is not released")
    Do ..OnAfterOneTest()
    // No endpoint, declared features: the declaration stands.
    Do ..ChangeProfile({"receivers": (recs)})
    Set route = evidence.Route("UT Ward C")
    Do $$$AssertEquals(route."capabilities_http_status", 200, "an entry that declares its features reads as 200")
    Do $$$AssertEquals(route."capabilities_source", "declared by the site profile", "from the profile")
    Do $$$AssertTrue(route."conditional_writes" && route.receipts && route."dry_run", "with the declared flags")
    Set run = ..Run({"name": "a declared receiver", "summary": {"route": (route)}})
    Do $$$AssertEquals(..Found(run.checks, "capability", "CONNECTOR_CAPABLE"), "pass", "the gate passes it (" _ ..Codes(run.checks, "capability") _ ")")
}

/// What a receiver offers on history reaches the route: the capabilities endpoint's word, else the entry's own declaration,
/// which is how a site whose endpoint does not mention history says it has one. Nothing said by either is no history.
Method TestHistoryOnTheRoute()
{
    Set e = "Shutter.Operation.Evidence", yes = {"features": {"history": true}}, no = {"features": {"history": false}}
    Do $$$AssertEquals($CLASSMETHOD(e, "HistoryOffered", {"history": true}, ""), 1, "the endpoint says yes")
    Do $$$AssertEquals($CLASSMETHOD(e, "HistoryOffered", {"history": false}, yes), 0, "the endpoint's no outranks the entry")
    Do $$$AssertEquals($CLASSMETHOD(e, "HistoryOffered", {}, yes), 1, "the endpoint is silent and the entry declares it")
    Do $$$AssertEquals($CLASSMETHOD(e, "HistoryOffered", {}, no), 0, "the endpoint is silent and the entry declares none")
    Do $$$AssertEquals($CLASSMETHOD(e, "HistoryOffered", {}, {}), 0, "neither says")
    Do $$$AssertEquals($CLASSMETHOD(e, "HistoryOffered", {}, ""), 0, "and no entry at all")
    Set recs = ##class(Shutter.Store.SiteProfile).Current().%Get("receivers")
    Set api = {"base": "/wardb/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}", "capabilities": "", "operations": "/operations"}
    Do recs.%Push({"name": "UT No History", "tier": 2, "api": (api), "features": {"conditional_writes": true, "receipts": true, "history": false, "dry_run": true}})
    Do recs.%Push({"name": "UT History", "tier": 2, "api": (api), "features": {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}})
    Do ..ChangeProfile({"receivers": (recs)})
    Set evidence = ##class(Shutter.Operation.Evidence).%New("Shutter Evidence (unit test)")
    Set route = evidence.Route("UT History")
    Do $$$AssertEquals(route.%GetTypeOf("history"), "boolean", "the route carries history")
    Do $$$AssertTrue(route.history, "as declared")
    Set route = evidence.Route("UT No History")
    Do $$$AssertEquals(route.%GetTypeOf("history"), "boolean", "the route says so when there is none")
    Do $$$AssertNotTrue(route.history, "as declared")
    Set run = ..Run({"name": "a receiver that declares no history, through the route", "summary": {"route": (route)}})
    Do $$$AssertEquals(..Found(run.checks, "capability", "HISTORY_UNSUPPORTED"), "block", "the gate blocks the resend (" _ ..Codes(run.checks, "capability") _ ")")
    Do $$$AssertEquals(run.response.Outcome, "block", "and the plan is not released")
}

Method TestCatalogue()
{
    Do ..RunRows("catalogue")
}

Method TestRehearsal()
{
    Do ..RunRows("rehearsal")
}

/// The gate answers unknown, with the reason, when the case, its snapshot or the plan cannot be found.
Method TestMissingInputs()
{
    Set gate = ##class(Shutter.Operation.Gate).%New("Shutter Gate (unit test)")
    Set req = ##class(Shutter.Msg.GateRequest).%New()
    Set req.CaseId = "UT-GATE-NONE", req.PlanId = "0"
    Do gate.OnGateRequest(req, .resp)
    Do $$$AssertEquals(resp.Outcome, "unknown", "an unknown case is unknown")
    Do $$$AssertTrue(resp.Error [ "Unknown case", "and says so: " _ resp.Error)
    Set case = ..NewCase({})
    Set req.CaseId = case.CaseId
    Do gate.OnGateRequest(req, .resp)
    Do $$$AssertEquals(resp.Outcome, "unknown", "an unknown plan is unknown")
    Do $$$AssertTrue(resp.Error [ "Unknown plan", "and says so: " _ resp.Error)
    Set sc = ##class(Shutter.Store.Plan).Create(case, "", {"disposition": "escalate"}, "rules", .plan)
    Do $$$AssertStatusOK(sc, "a plan without a snapshot is saved")
    Set req.PlanId = plan.%Id()
    Do gate.OnGateRequest(req, .resp)
    Do $$$AssertEquals(resp.Outcome, "unknown", "a case without a snapshot is unknown")
    Do $$$AssertTrue(resp.Error [ "no snapshot", "and says so: " _ resp.Error)
}

/// The gate records its decision, and its summary names every check that did not pass.
Method TestDecisionIsRecorded()
{
    Set run = ..Run({"summary": {"validation": {"parsed": false, "error": "MSH-9 is empty"}}, "request": {"stage": "proposal"}})
    Set resp = run.response
    Do $$$AssertEquals(resp.Outcome, "block", "the outcome is the worst check")
    Do $$$AssertTrue(resp.Summary [ "conformance PARSE_FAILED", "the summary names the blocking check: " _ resp.Summary)
    Do $$$AssertTrue(resp.Summary [ ("policy " _ ##class(Shutter.Operation.Gate).#POLICYVERSION), "and the policy version")
    Set decision = ##class(Shutter.Store.GateDecision).%OpenId(resp.DecisionId)
    Do $$$AssertTrue($ISOBJECT(decision), "the decision is stored")
    If $ISOBJECT(decision) {
        Do $$$AssertEquals(decision.Outcome, "block", "with its outcome")
        Do $$$AssertEquals(decision.ChecksJSON, resp.ChecksJSON, "and its checks")
    }
}

/// The catalogue outcome each disposition follows from (CONTRACTS 6.3).
Method TestDispositionFor()
{
    For pair = "resend:resend", "resend_chain:resend", "resend_latest:resend", "reconcile:reconcile", "none:superseded", "escalate:escalate", "resend_unconditional:escalate", "correct_history:escalate", "anything:" {
        Do $$$AssertEquals(##class(Shutter.Operation.Gate).DispositionFor($PIECE(pair, ":", 1)), $PIECE(pair, ":", 2), $PIECE(pair, ":", 1))
    }
}

Method TestReversed()
{
    Do $$$AssertEquals(##class(Shutter.Operation.Gate).Reversed("cancel_admit"), "admission", "cancel_admit")
    Do $$$AssertEquals(##class(Shutter.Operation.Gate).Reversed("cancel_transfer"), "transfer", "cancel_transfer")
    Do $$$AssertEquals(##class(Shutter.Operation.Gate).Reversed("cancel_discharge"), "discharge", "cancel_discharge")
    Do $$$AssertEquals(##class(Shutter.Operation.Gate).Reversed("cancel_"), "event", "a bare prefix")
    Do $$$AssertEquals(##class(Shutter.Operation.Gate).Reversed("merge"), "merge", "any other word")
}

/// Every reason code the gate can give has a row in the table: the codes written in the gate's source, and the
/// approval's reasons (Shutter.Store.Approval.InvalidReason) as the gate words them.
/// A further message that reached the index after the snapshot: the dispatch gate reads again and stops the approved write, and
/// the connector, reading once more at the moment of the write, refuses it with nothing sent.
Method TestFurtherMessagesAreReadAgainBeforeTheWrite()
{
    Set row = ##class(Shutter.Index.Message).%New()
    Set row.DocId = "UT-GATE-FURTHER", row.PatientId = "MRN-UT1", row.PatientIdAuthority = "HOSP", row.VisitNumber = "ENC-UT-NEW", row.Event = "admit", row.MessageType = "ADT_A01"
    Set row.ControlId = "UT-NEW", row.EventTime = "2026-10-20T09:00:00Z", row.TimeCreated = "2099-01-01 00:00:00"
    Do $$$AssertStatusOK(row.%Save(), "the index's row is saved")
    Try {
        Set run = ..Run({"name": "the dispatch gate reads again", "approval": {}})
        Do $$$AssertEquals(..Found(run.checks, "ordering", "FURTHER_MOVEMENT"), "block", "the dispatch gate stops the write")
        Do $$$AssertTrue(..Detail(run.checks, "ordering", "FURTHER_MOVEMENT") [ "ENC-UT-NEW", "and names the new visit")
        Set case = ..NewCase({})
        Set request = ##class(Shutter.Msg.WardOperation).%New()
        Set request.Purpose = "recovery", request.CaseId = case.CaseId, request.OperationKey = case.OperationKey
        Set ward = ##class(Shutter.Operation.Ward).%New("UT Ward")
        Do $$$AssertStatusOK(ward.OnWardOperation(request, .response), "the connector answers")
        Do $$$AssertEquals(response.Outcome, "refused", "the connector refuses the write")
        Do $$$AssertEquals(response.ReasonCode, "further_movement", "for this reason")
        Do $$$AssertTrue(response.Error [ "ENC-UT-NEW", "and says what it found: " _ response.Error)
        Do $$$AssertEquals(response.HttpStatus, "", "nothing was sent")
    } Catch ex {
        Do $$$AssertTrue(0, "no error: " _ ex.DisplayString())
    }
    Do ##class(Shutter.Index.Message).%DeleteId(row.%Id())
}

/// The engine check through the gate itself: every answer, in the ordering group, and the outcome it makes.
Method TestEngine()
{
    Do ..RunRows("engine")
}

Method TestEveryReasonCodeHasARow()
{
    Set asserted = ""
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set it2 = row.expect.%GetIterator()
        While it2.%GetNext(.j, .e) { Set asserted(e.%Get(2)) = "" }
    }
    Set codes = ""
    For method = "OnGateRequest", "OutcomeConsistency", "BedConflictCheck" {
        Set source = ..Source("Shutter.Operation.Gate", method)
        Set m = ##class(%Regex.Matcher).%New("""([A-Z][A-Z_]*[A-Z])""", source)
        While m.Locate() { Set codes(m.Group(1)) = "" }
    }
    Set m = ##class(%Regex.Matcher).%New("Quit ""([a-z_]+)""", ..Source("Shutter.Store.Approval", "InvalidReason"))
    While m.Locate() { Set codes("APPROVAL_" _ $ZCONVERT(m.Group(1), "U")) = "" }
    // The two reasons the gate itself gives an automatic release.
    Set codes("POLICY_REQUIRES_APPROVAL") = "", codes("APPROVAL_PLAN_ORIGIN") = "", codes("APPROVAL_ORIGIN_NOT_PROVED") = ""
    Do $$$AssertTrue($DATA(codes("EXACT_OPERATION")) && $DATA(codes("APPROVAL_EXPIRED")), "the codes were read from the source")
    Set code = "", missing = ""
    For {
        Set code = $ORDER(codes(code))
        Quit:code=""
        If '$DATA(asserted(code)) Set missing = missing _ $SELECT(missing = "": "", 1: ", ") _ code
    }
    Do $$$AssertEquals(missing, "", "every reason code is asserted by a row" _ $SELECT(missing = "": "", 1: "; missing: " _ missing))
}

/// Runs the rows of one group and asserts each one's expectations.
Method RunRows(group As %String)
{
    Set n = 0
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Continue:(row.group '= group)
        Set n = n + 1
        Set run = ..Run(row)
        Set checks = run.checks
        Set it2 = row.expect.%GetIterator()
        While it2.%GetNext(.j, .e) {
            Set got = ..Found(checks, e.%Get(0), e.%Get(2))
            Do $$$AssertEquals(got, e.%Get(1), row.name _ ": " _ e.%Get(0) _ " " _ e.%Get(2) _ $SELECT(got = "": " (the check gave " _ ..Codes(checks, e.%Get(0)) _ ")", 1: ""))
        }
        If row.%IsDefined("absent") {
            Set it2 = row.absent.%GetIterator()
            While it2.%GetNext(.j, .e) {
                Do $$$AssertEquals(..Found(checks, e.%Get(0), e.%Get(1)), "", row.name _ ": no " _ e.%Get(0) _ " " _ e.%Get(1))
            }
        }
        If row.%IsDefined("contains") {
            Set it2 = row.contains.%GetIterator()
            While it2.%GetNext(.j, .e) {
                Set d = ..Detail(checks, e.%Get(0), e.%Get(1))
                Do $$$AssertTrue(d [ e.%Get(2), row.name _ ": " _ e.%Get(0) _ " " _ e.%Get(1) _ " says '" _ e.%Get(2) _ "'" _ $SELECT(d [ e.%Get(2): "", 1: " (it says: " _ d _ ")"))
            }
        }
        If row.%IsDefined("outcome") Do $$$AssertEquals(run.response.Outcome, row.outcome, row.name _ ": the outcome")
        Do $$$AssertEquals(run.response.Error, "", row.name _ ": the gate reported no error")
        // Each row's records go before the next row, so the profile and the cases of one row never meet another's.
        Do ..OnAfterOneTest()
    }
    Do $$$AssertTrue(n > 0, "the table has rows for " _ group)
}

/// Builds what a row describes and runs the gate on it. Returns {response, checks}.
Method Run(row As %DynamicObject) As %DynamicObject
{
    If row.%IsDefined("profile") Do ..ChangeProfile(row.profile)
    Set case = ..NewCase($SELECT(row.%IsDefined("case"): row.case, 1: {}))
    Set key = case.OperationKey
    // The incident an approval of the row stands on, when it has one: the case joins it.
    If row.%IsDefined("incident") {
        Set inc = ##class(Shutter.Store.Incident).%New()
        Set inc.IncidentId = "UT-GATE-I-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.Gate)
        Set inc.Receiver = case.Receiver, inc.Mode = "policy", inc.State = "releasing", inc.OpenedAt = case.OpenedAt
        Set inc.PlanDigest = ##class(Shutter.Util.Json).Str(row.incident, "plan_digest")
        If row.incident.%IsDefined("epoch") Set inc.ReceiverEpoch = row.incident.epoch
        Do $$$AssertStatusOK(inc.%Save(), row.name _ ": the incident is saved")
        Set i%MadeIncidents(inc.%Id()) = ""
        Do $$$AssertStatusOK(case.SetIncident(inc), row.name _ ": the case belongs to the incident")
    }
    // The summary the evidence collection would have made, with the row's changes.
    Set summary = ..Fill(..BaseSummary(), key)
    // A second case the row's summary names as "{other}" (v1.28: the case about a bed's occupant), in the state the row says.
    Set otherId = ""
    If row.%IsDefined("other_case") {
        Set other = ..NewCase({"encounter_id": "ENC-OCC"})
        Set other.State = ##class(Shutter.Util.Json).Str(row."other_case", "state", "escalated")
        Do $$$AssertStatusOK(other.%Save(), row.name _ ": the other case is saved")
        Set otherId = other.CaseId
    }
    If row.%IsDefined("summary") Do ..Merge(summary, ..Fill(##class(%DynamicAbstractObject).%FromJSON($REPLACE(row.summary.%ToJSON(), "{other}", otherId)), key))
    Set fresh = 300
    If row.%IsDefined("snapshot") Set fresh = +row.snapshot."fresh_seconds"
    Set snap = ##class(Shutter.Store.Snapshot).Begin(case, fresh)
    Set sc = snap.Seal(summary)
    Do $$$AssertStatusOK(sc, row.name _ ": the snapshot is sealed")
    // The current snapshot is written only through SetSnapshot: a whole save keeps the stored one.
    Do $$$AssertStatusOK(case.SetSnapshot(snap), row.name _ ": the snapshot is the case's current one")
    // The plan.
    Set planObj = ..Fill({"disposition": "resend", "action": {"type": "resend", "operation_key": "{key}", "expected_version": 3, "payload_digest": "sha256:ut"}, "summary": "Resend the transfer"}, key)
    If row.%IsDefined("plan") Do ..Merge(planObj, ..Fill(row.plan, key))
    Set createdBy = ##class(Shutter.Util.Json).Str(planObj, "created_by", "rules")
    Do planObj.%Remove("created_by")
    Set sc = ##class(Shutter.Store.Plan).Create(case, snap, planObj, createdBy, .plan)
    Do $$$AssertStatusOK(sc, row.name _ ": the plan is saved")
    // The request.
    Set r = $SELECT(row.%IsDefined("request"): row.request, 1: {})
    Set req = ##class(Shutter.Msg.GateRequest).%New()
    Set req.CaseId = case.CaseId, req.PlanId = plan.%Id()
    Set req.Stage = ##class(Shutter.Util.Json).Str(r, "stage", $SELECT(row.%IsDefined("approval"): "dispatch", 1: "proposal"))
    Set req.Receiver = $PARAMETER("Shutter.Production", "RECEIVER")
    Set req.ChainKind = ##class(Shutter.Util.Json).Str(r, "chain_kind", "single")
    If r.%IsDefined("receiver_version") Set req.ReceiverVersion = r."receiver_version"
    If r.%IsDefined("receiver_epoch") Set req.ReceiverEpoch = r."receiver_epoch"
    // The approval, made as the workflow makes it and then changed as the row says, bound to the rehearsal the row describes.
    If row.%IsDefined("approval") {
        Set a = row.approval
        Set rehearsal = ..NewRehearsal(case, snap, plan, $SELECT(row.%IsDefined("rehearsal"): row.rehearsal, 1: {}), row.name)
        Set sc = ##class(Shutter.Store.Approval).Create(case, plan, snap, ##class(Shutter.Operation.Gate).#POLICYVERSION, rehearsal, plan.ExpectedVersion, ##class(Shutter.Util.Json).Str(a, "approver", "user:ut"), ##class(Shutter.Util.Json).Str(a, "decision", "approved"), "unit test", "", +##class(Shutter.Util.Json).Str(a, "valid_seconds", 600), .approval, ##class(Shutter.Util.Json).Str(a, "epoch"))
        Do $$$AssertStatusOK(sc, row.name _ ": the approval is saved")
        If a.%IsDefined("expected_version") Set approval.ExpectedVersion = a."expected_version"
        If ##class(Shutter.Util.Json).Bool(a, "revoked") Set approval.Revoked = 1
        If a.%IsDefined("plan_digest") Set approval.PlanDigest = a."plan_digest"
        If a.%IsDefined("snapshot_digest") Set approval.SnapshotDigest = a."snapshot_digest"
        If a.%IsDefined("material_digest") Set approval.MaterialDigest = a."material_digest"
        If a.%IsDefined("policy_version") Set approval.PolicyVersion = a."policy_version"
        If a.%IsDefined("site_profile_version") Set approval.SiteProfileVersion = a."site_profile_version"
        Do approval.%Save()
        If a.%IsDefined("incident_plan_digest") Do $$$AssertStatusOK(approval.BindIncident(a."incident_plan_digest", ##class(Shutter.Util.Json).Str(a, "bound_entry"), ##class(Shutter.Util.Json).Str(a, "bound_outcome")), row.name _ ": the approval is bound to the incident's")
        Set req.ApprovalId = approval.%Id()
    }
    // A row's "engine" is what Shutter.Util.EngineCheck.Read would have found, since no production runs here.
    If row.%IsDefined("engine") Set ^||Shutter.Test.EngineFacts = row.engine.%ToJSON()
    Set gate = $CLASSMETHOD($SELECT(row.%IsDefined("engine"): "Shutter.Test.EngineGate", 1: "Shutter.Operation.Gate"), "%New", "Shutter Gate (unit test)")
    Set sc = gate.OnGateRequest(req, .resp)
    Do $$$AssertStatusOK(sc, row.name _ ": the gate ran")
    Set checks = ##class(%DynamicArray).%FromJSON($SELECT(resp.ChecksJSON = "": "[]", 1: resp.ChecksJSON))
    Quit {"response": (resp), "checks": (checks)}
}

/// A case as the feed opens one, with the row's changes: event, failure_kind, failure_text, encounter_id, patient_id,
/// patient_id_authority, event_time. The operation key is built from them.
Method NewCase(spec As %DynamicObject) As Shutter.Store.Case
{
    Set json = "Shutter.Util.Json"
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-GATE-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.Gate)
    Set case.Event = $CLASSMETHOD(json, "Str", spec, "event", "transfer")
    Set case.FailureKind = $CLASSMETHOD(json, "Str", spec, "failure_kind", "delivery_failed")
    Set case.FailureText = $CLASSMETHOD(json, "Str", spec, "failure_text", "Delivery unavailable (ward_unavailable), HTTP 503")
    Set case.EncounterId = $CLASSMETHOD(json, "Str", spec, "encounter_id", "ENC-UT1")
    Set case.PatientId = $CLASSMETHOD(json, "Str", spec, "patient_id", "MRN-UT1")
    Set case.PatientIdAuthority = $CLASSMETHOD(json, "Str", spec, "patient_id_authority", "HOSP")
    Set case.EventTime = $CLASSMETHOD(json, "Str", spec, "event_time", ..#EVENTTIME)
    Set case.SourceSystem = "PAS", case.Ward = $SELECT(case.Event = "transfer": "WARD-B", 1: "")
    Set case.Receiver = $PARAMETER("Shutter.Production", "RECEIVER")
    Set case.OperationKey = "PAS^HOSP^" _ case.PatientId _ "^" _ case.EncounterId _ "^" _ case.Event _ "^" _ case.EventTime
    Set case.State = "investigating", case.Mode = $CLASSMETHOD(json, "Str", spec, "mode", "rules")
    Set case.Scenario = $CLASSMETHOD(json, "Str", spec, "scenario"), case.ScenarioRecorded = $CLASSMETHOD(json, "Bool", spec, "scenario_recorded")
    Set case.SourceNamespace = $CLASSMETHOD(json, "Str", spec, "source_namespace"), case.OriginHeaderId = $CLASSMETHOD(json, "Str", spec, "origin_header_id")
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Set sc = case.%Save()
    Do $$$AssertStatusOK(sc, "the case " _ case.CaseId _ " is saved")
    Set i%Made(case.%Id()) = ""
    Quit case
}

/// The rehearsal an approval binds, as the workflow records one: a dry run of the plan that the receiver answered from the
/// spec's fields: would_apply (true), reason, receiver_version (the plan's expected version), epoch (1); what was sent
/// carries the plan's expected version and the payload_digest ("sha256:ut"). The spec's "plan" "other" makes the dry run
/// of a second plan of the case, and "none" makes none (the method then returns "").
Method NewRehearsal(case As Shutter.Store.Case, snap As Shutter.Store.Snapshot, plan As Shutter.Store.Plan, spec As %DynamicObject, name As %String) As Shutter.Store.Rehearsal
{
    Set json = "Shutter.Util.Json"
    Set which = $CLASSMETHOD(json, "Str", spec, "plan", "same")
    If which = "none" Quit ""
    Set of = plan
    If which = "other" {
        Set other = ..Fill({"disposition": "resend", "action": {"type": "resend", "operation_key": "{key}", "expected_version": 3, "payload_digest": "sha256:ut"}, "summary": "Another plan of the same case"}, case.OperationKey)
        Set sc = ##class(Shutter.Store.Plan).Create(case, snap, other, "rules", .of)
        Do $$$AssertStatusOK(sc, name _ ": the other plan is saved")
    }
    Set wouldApply = $CLASSMETHOD(json, "Bool", spec, "would_apply", 1)
    Set version = $SELECT(spec.%IsDefined("receiver_version"): spec."receiver_version", 1: plan.ExpectedVersion)
    Set response = {"rehearsal": true}
    Do response.%Set("would_apply", wouldApply, "boolean")
    If 'wouldApply Set response.reason = $CLASSMETHOD(json, "Str", spec, "reason", "invalid_transition")
    Set response."encounter_before" = {"version": (version)}
    Set response.epoch = $SELECT(spec.%IsDefined("epoch"): spec.epoch, 1: 1)
    Set sent = ##class(Shutter.Msg.WardOperation).%New()
    Set sent.Purpose = "rehearsal", sent.DryRun = 1, sent.OperationKey = case.OperationKey, sent.CaseId = case.CaseId
    Set sent.ExpectedVersion = of.ExpectedVersion
    Set sent.PayloadDigest = $CLASSMETHOD(json, "Str", spec, "payload_digest", "sha256:ut")
    Set sc = ##class(Shutter.Store.Rehearsal).Create(case, of, sent, 200, response, .r)
    Do $$$AssertStatusOK(sc, name _ ": the rehearsal is saved")
    Quit r
}

/// The evidence of a transfer that can be resent: the receiver knows the encounter (admitted, version 3, the case's
/// patient), holds no receipt, takes conditional writes, keeps receipts, offers a history and runs dry runs; the message
/// parses; nothing later.
ClassMethod BaseSummary() As %DynamicObject
{
    Quit {
        "operation": {"operation_key": "{key}", "payload_digest": "sha256:ut"},
        "ward_state_http_status": 200,
        "ward_state": {"patient_id": "MRN-UT1", "patient_id_authority": "HOSP", "state": "admitted", "ward": "WARD-A", "version": 3, "epoch": 1, "history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z", "ward": "WARD-A", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}]},
        "receipt_http_status": 404,
        "validation": {"parsed": true},
        "route": {"capabilities_http_status": 200, "conditional_writes": true, "receipts": true, "history": true, "dry_run": true},
        "timeline": []
    }
}

/// The object with "{key}" replaced by the operation key in every string.
ClassMethod Fill(obj As %DynamicObject, key As %String) As %DynamicObject
{
    Quit ##class(%DynamicAbstractObject).%FromJSON($REPLACE(obj.%ToJSON(), "{key}", key))
}

/// Merges a patch into an object: objects are merged key by key, null removes the key, anything else replaces it.
ClassMethod Merge(target As %DynamicObject, patch As %DynamicObject)
{
    Set iter = patch.%GetIterator()
    While iter.%GetNext(.k, .v) {
        Set type = patch.%GetTypeOf(k)
        If type = "null" {
            Do target.%Remove(k)
        } ElseIf (type = "object") && (target.%GetTypeOf(k) = "object") {
            Do ..Merge(target.%Get(k), v)
        } ElseIf type = "boolean" {
            Do target.%Set(k, v, "boolean")
        } Else {
            Do target.%Set(k, v)
        }
    }
}

/// The result of the check with that name and reason code, or "" when the gate gave none.
ClassMethod Found(checks As %DynamicArray, name As %String, code As %String) As %String
{
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) { If (c.check = name) && (c."reason_code" = code) Return c.result }
    Quit ""
}

/// The detail of the check with that name and reason code, or "" when the gate gave none.
ClassMethod Detail(checks As %DynamicArray, name As %String, code As %String) As %String
{
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) { If (c.check = name) && (c."reason_code" = code) Return c.detail }
    Quit ""
}

/// What a check gave, for a failure message: "result CODE" for each entry of that name.
ClassMethod Codes(checks As %DynamicArray, name As %String) As %String
{
    Set out = ""
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) { If c.check = name Set out = out _ $SELECT(out = "": "", 1: ", ") _ c.result _ " " _ c."reason_code" }
    Quit $SELECT(out = "": "nothing", 1: out)
}

/// Changes the stored site profile for one row, keeping its version so that approvals made in the row still match it.
/// The patch is merged at the top level; its "receiver" item is merged into the demo receiver's entry.
Method ChangeProfile(patch As %DynamicObject)
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..ProfileChanged {
        Set ..HadProfileRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: ""), ..ProfileChanged = 1
    }
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    Set receiver = patch.%Get("receiver")
    Do patch.%Remove("receiver")
    Do ..Merge(p, patch)
    If $ISOBJECT(receiver) {
        Set iter = p.receivers.%GetIterator()
        While iter.%GetNext(.i, .r) { If r.name = $PARAMETER("Shutter.Production", "RECEIVER") Do ..Merge(r, receiver) }
    }
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Version = version
    Set row.Json = p.%ToJSON()
    Set sc = row.%Save()
    Do $$$AssertStatusOK(sc, "the site profile is changed for the row")
}

Method RestoreProfile()
{
    Quit:'..ProfileChanged
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..HadProfileRow {
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    } ElseIf $ISOBJECT(row) {
        Set row.Json = ..SavedProfile
        Do row.%Save()
    }
    Set ..ProfileChanged = 0, ..SavedProfile = ""
}

/// Deletes a test case and everything the gate and the stores recorded for it.
ClassMethod Purge(id As %String)
{
    For table = "Shutter_Store.GateDecision", "Shutter_Store.Approval", "Shutter_Store.Rehearsal", "Shutter_Store.Plan", "Shutter_Store.CaseEvent" {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ table _ " WHERE ""Case"" = ?", id)
    }
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.SnapshotItem WHERE Snapshot IN (SELECT ID FROM Shutter_Store.Snapshot WHERE ""Case"" = ?)", id)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.Snapshot WHERE ""Case"" = ?", id)
    Do ##class(Shutter.Store.Case).%DeleteId(id)
    Kill ^Shutter.Counter("event", id), ^Shutter.Counter("plan", id), ^Shutter.Counter("snapshot", id)
}

/// Deletes a test incident; its cases are purged by their own rows.
ClassMethod PurgeIncident(id As %String)
{
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.IncidentEvent WHERE Incident = ?", id)
    Do ##class(Shutter.Store.Incident).%DeleteId(id)
    Kill ^Shutter.Counter("incidentEvent", id)
}

/// A method's source, as one string.
ClassMethod Source(class As %String, method As %String) As %String
{
    Set m = ##class(%Dictionary.MethodDefinition).%OpenId(class _ "||" _ method)
    If '$ISOBJECT(m) Quit ""
    Set out = ""
    Do m.Implementation.Rewind()
    While 'm.Implementation.AtEnd { Set out = out _ m.Implementation.ReadLine() _ $CHAR(10) }
    Quit out
}

ClassMethod Rows() As %DynamicArray
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Rows")
    Quit ##class(%DynamicArray).%FromJSON(xdata.Data)
}

/// The table: group (the test that runs the row), name, what the row changes, and the checks it expects as
/// [check, result, reason code]; "absent" lists [check, reason code] pairs the gate must not give; "contains" lists
/// [check, reason code, text] triples the check's detail must contain.
XData Rows [ MimeType = application/json ]
{
[
  {"group": "intent", "name": "a write to a receiver the site profile does not describe",
   "profile": {"receivers": [{"name": "Records Out", "tier": 2, "category": "history_of_record"}]},
   "expect": [["intent", "block", "RECEIVER_NOT_IN_PROFILE"]], "outcome": "block",
   "contains": [["intent", "RECEIVER_NOT_IN_PROFILE", "no entry for the receiver Downstream Out"], ["intent", "RECEIVER_NOT_IN_PROFILE", "read at the default receiver API"]]},
  {"group": "intent", "name": "a write to a receiver the site profile describes",
   "profile": {"receivers": [{"name": "Records Out", "tier": 2, "category": "history_of_record"}, {"name": "Downstream Out", "tier": 2, "category": "current_state"}]},
   "expect": [["intent", "pass", "EXACT_OPERATION"]], "absent": [["intent", "RECEIVER_NOT_IN_PROFILE"]], "outcome": "pass"},
  {"group": "intent", "name": "a plan that writes nothing, for a receiver the site profile does not describe",
   "profile": {"receivers": [{"name": "Records Out", "tier": 2, "category": "history_of_record"}]},
   "plan": {"disposition": "escalate", "action": null},
   "expect": [["intent", "pass", "NO_WRITE"]], "absent": [["intent", "RECEIVER_NOT_IN_PROFILE"]]},
  {"group": "intent", "name": "a write to a receiver whose category is orders_results",
   "profile": {"receivers": [{"name": "Downstream Out", "tier": 2, "category": "orders_results"}]},
   "expect": [["intent", "block", "RECEIVER_NOT_MODELLED"]], "outcome": "block"},
  {"group": "pass", "name": "a resend of the case's own operation, at proposal",
   "expect": [["identity", "pass", "IDENTITY_MATCHES"], ["conformance", "pass", "PARSED"], ["intent", "pass", "EXACT_OPERATION"], ["ordering", "pass", "NO_LATER_EVENT"], ["state_transition", "pass", "TRANSITION_ALLOWED"], ["effect", "pass", "NO_RECEIPT"], ["authorization", "pass", "NOT_YET_REQUIRED"], ["concurrency", "pass", "VERSION_MATCHES"], ["evidence", "pass", "FRESH"], ["capability", "pass", "CONNECTOR_CAPABLE"], ["catalogue", "pass", "NOT_CONFIGURED"]],
   "outcome": "pass"},
  {"group": "pass", "name": "the same resend at dispatch, with a valid approval",
   "approval": {},
   "expect": [["authorization", "pass", "APPROVAL_VALID"]], "outcome": "pass"},

  {"group": "identity", "name": "the receiver's encounter belongs to another patient",
   "summary": {"ward_state": {"patient_id": "MRN-OTHER"}},
   "expect": [["identity", "block", "PATIENT_MISMATCH"]], "outcome": "block"},
  {"group": "identity", "name": "the same patient number from another authority",
   "summary": {"ward_state": {"patient_id_authority": "OTHER"}},
   "expect": [["identity", "block", "PATIENT_MISMATCH"]]},
  {"group": "identity", "name": "a patient-level message names no encounter",
   "case": {"event": "update", "encounter_id": "-"}, "summary": {"ward_state_http_status": 404, "ward_state": null},
   "expect": [["identity", "pass", "NO_ENCOUNTER"], ["state_transition", "block", "PATIENT_LEVEL_WRITE"], ["concurrency", "block", "PATIENT_LEVEL_WRITE"]]},
  {"group": "identity", "name": "an admission the receiver does not know yet",
   "case": {"event": "admit"}, "summary": {"ward_state_http_status": 404, "ward_state": null}, "plan": {"action": {"expected_version": 0}},
   "expect": [["identity", "pass", "NEW_ENCOUNTER"], ["state_transition", "pass", "TRANSITION_ALLOWED"], ["concurrency", "pass", "VERSION_MATCHES"]], "contains": [["identity", "NEW_ENCOUNTER", "does not prove"]], "outcome": "pass"},
  {"group": "identity", "name": "a transfer of an encounter the receiver does not know",
   "summary": {"ward_state_http_status": 404, "ward_state": null},
   "expect": [["identity", "block", "UNKNOWN_ENCOUNTER"], ["state_transition", "unknown", "RECEIVER_UNREADABLE"], ["concurrency", "unknown", "RECEIVER_UNREADABLE"]]},
  {"group": "identity", "name": "the receiver's state could not be read",
   "summary": {"ward_state_http_status": 503, "ward_state": null},
   "expect": [["identity", "unknown", "RECEIVER_UNREADABLE"], ["state_transition", "unknown", "RECEIVER_UNREADABLE"], ["concurrency", "unknown", "RECEIVER_UNREADABLE"]], "contains": [["identity", "RECEIVER_UNREADABLE", "could not be read (HTTP 503)"]], "outcome": "unknown"},
  {"group": "identity", "name": "the receiver gave no answer to the read",
   "summary": {"ward_state_http_status": 0, "ward_state": null},
   "expect": [["identity", "unknown", "RECEIVER_UNREADABLE"]], "contains": [["identity", "RECEIVER_UNREADABLE", "could not be read (no answer)"]], "outcome": "unknown"},

  {"group": "conformance", "name": "the message does not parse",
   "summary": {"validation": {"parsed": false, "error": "MSH-9 is empty"}},
   "expect": [["conformance", "block", "PARSE_FAILED"]], "outcome": "block"},
  {"group": "conformance", "name": "a message that maps to no operation",
   "case": {"failure_kind": "unmappable", "failure_text": "ADT^A17 maps to no operation"},
   "expect": [["conformance", "block", "UNMAPPABLE"], ["conformance", "pass", "PARSED"]], "outcome": "block"},

  {"group": "intent", "name": "a merge withheld by the site's policy",
   "case": {"event": "merge", "failure_kind": "withheld"},
   "expect": [["intent", "block", "MERGE_WITHHELD"]], "outcome": "block"},
  {"group": "intent", "name": "a cancel withheld because the receiver cannot reverse it",
   "case": {"event": "cancel_transfer", "failure_kind": "withheld"},
   "expect": [["intent", "block", "CANCEL_UNSUPPORTED"]], "outcome": "block"},
  {"group": "intent", "name": "a disposition the gate does not know",
   "plan": {"disposition": "retry_later"},
   "expect": [["intent", "block", "UNKNOWN_DISPOSITION"]], "outcome": "block"},
  {"group": "intent", "name": "a merge resend while the site forbids merges",
   "case": {"event": "merge"}, "profile": {"merges": "forbidden"},
   "expect": [["intent", "block", "MERGE_WITHHELD"], ["intent", "pass", "EXACT_OPERATION"]], "outcome": "block"},
  {"group": "intent", "name": "a merge resend the site allows but the receiver's entry does not take",
   "case": {"event": "merge"}, "profile": {"merges": "allowed", "receiver": {"merges": false}},
   "expect": [["intent", "block", "MERGE_WITHHELD"]]},
  {"group": "intent", "name": "a merge resend the site and the receiver both allow",
   "case": {"event": "merge"}, "profile": {"merges": "allowed", "receiver": {"merges": true}},
   "expect": [["intent", "pass", "EXACT_OPERATION"], ["state_transition", "pass", "TRANSITION_ALLOWED"]],
   "absent": [["intent", "MERGE_WITHHELD"]], "outcome": "pass"},
  {"group": "intent", "name": "a cancel resend to a receiver whose entry cannot reverse it",
   "case": {"event": "cancel_discharge"}, "summary": {"ward_state": {"state": "discharged"}}, "profile": {"receiver": {"cancels": false}},
   "expect": [["intent", "block", "CANCEL_UNSUPPORTED"], ["state_transition", "pass", "TRANSITION_ALLOWED"]]},
  {"group": "intent", "name": "a cancel resend to a receiver whose entry reverses",
   "case": {"event": "cancel_discharge"}, "summary": {"ward_state": {"state": "discharged"}}, "profile": {"receiver": {"cancels": true}},
   "expect": [["intent", "pass", "EXACT_OPERATION"]], "absent": [["intent", "CANCEL_UNSUPPORTED"]], "outcome": "pass"},
  {"group": "intent", "name": "a plan that writes another operation",
   "plan": {"action": {"operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T09:30:00Z"}},
   "expect": [["intent", "block", "DIFFERENT_OPERATION"]], "outcome": "block"},
  {"group": "intent", "name": "a plan whose payload differs from the case's",
   "plan": {"action": {"payload_digest": "sha256:other"}},
   "expect": [["intent", "block", "PAYLOAD_CHANGED"]], "outcome": "block"},
  {"group": "intent", "name": "a plan that names no payload digest",
   "plan": {"action": {"payload_digest": null}},
   "expect": [["intent", "pass", "EXACT_OPERATION"]]},
  {"group": "intent", "name": "a plan that writes nothing",
   "plan": {"disposition": "escalate", "action": null},
   "expect": [["intent", "pass", "NO_WRITE"], ["ordering", "pass", "NOT_APPLICABLE"], ["state_transition", "pass", "NOT_APPLICABLE"], ["concurrency", "pass", "NOT_APPLICABLE"], ["capability", "pass", "NOT_APPLICABLE"]], "outcome": "pass"},

  {"group": "conformance", "name": "a message whose schema is not loaded here",
   "summary": {"validation": {"parsed": false, "schema_known": false, "schema_category": "2.5.1.HOSP", "schema_fix": "Import the schema, then reinvestigate the case", "error": "unknown schema"}},
   "expect": [["conformance", "block", "SCHEMA_UNKNOWN"]], "absent": [["conformance", "PARSE_FAILED"]], "outcome": "block"},
  {"group": "ordering", "name": "a cancel of another movement holds a write back",
   "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z", "ward": "WARD-A", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"event": "cancel_discharge", "event_time": "2026-10-19T11:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_discharge^2026-10-19T11:00:00Z"}]}},
   "expect": [["ordering", "block", "SUPERSEDED_BY_LATER_EVENT"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend while a newer message of the encounter is pending in Shutter",
   "summary": {"pending_messages": [{"event": "transfer", "event_time": "2026-10-19T10:00:00Z", "operation_key": "k-later", "control_id": "MSG-9", "ens_header_id": "77", "sent_at": "2026-10-19 09:01:00.000", "receiver": "Downstream Out", "where": "queued for the receiver, no answer yet"}]},
   "expect": [["ordering", "block", "NEWER_MESSAGE_PENDING"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend with a new admission for the patient on another visit stops and names both visits",
   "summary": {"further_messages": {"identifier": "read", "stops": [{"why": "other_visit", "event": "admit", "message_type": "ADT_A01", "visit_number": "ENC-OTHER", "event_time": "2026-10-19T10:00:00Z", "control_id": "MSG-9"}], "shows": [], "unread": ""}},
   "expect": [["ordering", "block", "FURTHER_MOVEMENT"]], "contains": [["ordering", "FURTHER_MOVEMENT", "visit ENC-OTHER"], ["ordering", "FURTHER_MOVEMENT", "visit ENC-UT1"]], "outcome": "block"},
  {"group": "ordering", "name": "a further movement comes before a pending message in the checks, so the workflow doesn't wait",
   "summary": {"further_messages": {"identifier": "read", "stops": [{"why": "cancel", "event": "cancel_transfer", "visit_number": "ENC-UT1", "event_time": "2026-10-19T10:00:00Z", "control_id": "MSG-9"}], "shows": [], "unread": ""}, "pending_messages": [{"event": "cancel_transfer", "event_time": "2026-10-19T10:00:00Z", "operation_key": "k-later", "control_id": "MSG-9", "ens_header_id": "77", "sent_at": "2026-10-19 09:01:00.000", "receiver": "Downstream Out", "where": "received, not yet delivered to the receiver"}]},
   "expect": [["ordering", "block", "FURTHER_MOVEMENT"], ["ordering", "block", "NEWER_MESSAGE_PENDING"]], "contains": [["ordering", "FURTHER_MOVEMENT", "cancel of the transfer"], ["ordering", "FURTHER_MOVEMENT", "MRN-UT1"]], "outcome": "block"},
  {"group": "ordering", "name": "an out-patient attendance on another visit passes and is counted",
   "summary": {"further_messages": {"identifier": "read", "stops": [], "shows": [{"why": "shown", "event": "register", "message_type": "ADT_A04", "visit_number": "ENC-OTHER", "event_time": "2026-10-19T10:00:00Z", "control_id": "MSG-9"}], "unread": ""}},
   "expect": [["ordering", "pass", "NO_FURTHER_MOVEMENT"]], "contains": [["ordering", "NO_FURTHER_MOVEMENT", "shown on the plan"]], "outcome": "pass"},
  {"group": "ordering", "name": "a patient identifier that can't be read blocks a write",
   "summary": {"further_messages": {"identifier": "unreadable", "stops": [], "shows": [], "unread": ""}},
   "expect": [["ordering", "block", "PATIENT_UNREADABLE"]], "outcome": "block"},
  {"group": "ordering", "name": "further messages that could not all be read block a write",
   "summary": {"further_messages": {"identifier": "read", "stops": [], "shows": [], "unread": "the read of HOSPITAL ran out of its 30 seconds with messages left"}},
   "expect": [["ordering", "block", "FURTHER_NOT_READ"]], "contains": [["ordering", "FURTHER_NOT_READ", "HOSPITAL"]], "outcome": "block"},
  {"group": "ordering", "name": "a further movement doesn't block a plan that writes nothing",
   "plan": {"disposition": "escalate", "action": null},
   "summary": {"further_messages": {"identifier": "read", "stops": [{"why": "other_visit", "event": "admit", "visit_number": "ENC-OTHER"}], "shows": [], "unread": ""}},
   "expect": [["ordering", "pass", "NOT_APPLICABLE"]], "absent": [["ordering", "FURTHER_MOVEMENT"]], "outcome": "pass"},
  {"group": "ordering", "name": "a resend into a bed whose occupant has left",
   "summary": {"catalogue": {"conditions": {"bed_conflict": "occupant_left"}}, "bed_conflict": {"refused": true, "ward": "WARD-B", "bed": "B2", "since": "2026-10-18T08:10:00Z", "status": "occupant_left", "note": "The occupant's encounter is discharged now, so the bed is free of them", "occupant": {"encounter_id": "ENC-OCC"}, "occupant_movement": {"event": "discharge", "delivery": "applied"}}},
   "expect": [["ordering", "pass", "OCCUPANT_MOVED_OUT"], ["ordering", "pass", "NO_LATER_EVENT"]]},
  {"group": "ordering", "name": "a resend into a bed whose occupant is leaving in a case still working",
   "summary": {"catalogue": {"conditions": {"bed_conflict": "occupant_leaving"}}, "bed_conflict": {"refused": true, "ward": "WARD-B", "bed": "B2", "since": "2026-10-18T08:10:00Z", "status": "occupant_leaving", "occupant": {"encounter_id": "ENC-OCC"}, "occupant_movement": {"event": "transfer", "ward": "WARD-C", "delivery": "failed", "case_id": "UT-NO-SUCH-CASE"}}},
   "expect": [["ordering", "block", "WAITING_FOR_OCCUPANT_CASE"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend into a bed whose occupant's movement has no case yet",
   "summary": {"catalogue": {"conditions": {"bed_conflict": "occupant_leaving"}}, "bed_conflict": {"refused": true, "ward": "WARD-B", "bed": "B2", "status": "occupant_leaving", "occupant": {"encounter_id": "ENC-OCC"}, "occupant_movement": {"event": "transfer", "ward": "WARD-C", "delivery": "pending"}}},
   "expect": [["ordering", "block", "WAITING_FOR_OCCUPANT_CASE"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend into a bed whose occupant's case ended without freeing it",
   "summary": {"catalogue": {"conditions": {"bed_conflict": "occupant_leaving"}}, "bed_conflict": {"refused": true, "ward": "WARD-B", "bed": "B2", "status": "occupant_leaving", "occupant": {"encounter_id": "ENC-OCC"}, "occupant_movement": {"event": "transfer", "ward": "WARD-C", "delivery": "failed", "case_id": "{other}"}}}, "other_case": {"state": "escalated"},
   "expect": [["ordering", "block", "OCCUPANT_CASE_FAILED"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend into a bed whose occupant stays",
   "summary": {"catalogue": {"conditions": {"bed_conflict": "occupant_staying"}}, "bed_conflict": {"refused": true, "ward": "WARD-B", "bed": "B2", "since": "2026-10-18T08:10:00Z", "status": "occupant_staying", "occupant": {"encounter_id": "ENC-OCC"}, "occupant_movement": null}},
   "expect": [["ordering", "block", "BED_OCCUPIED"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend into a bed whose occupant could not be read",
   "summary": {"catalogue": {"conditions": {"bed_conflict": "unknown"}}, "bed_conflict": {"refused": true, "ward": "WARD-B", "bed": "B2", "status": "unknown", "occupant": null, "occupant_movement": null}},
   "expect": [["ordering", "block", "BED_OCCUPIED"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend whose event time is in the future",
   "summary": {"catalogue": {"conditions": {"event_time": "future"}}},
   "expect": [["ordering", "block", "EVENT_TIME_IMPLAUSIBLE"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend whose event time is plausible",
   "summary": {"catalogue": {"conditions": {"event_time": "plausible"}}},
   "expect": [["ordering", "pass", "NO_LATER_EVENT"]]},
  {"group": "ordering", "name": "a resend after a later transfer was applied",
   "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z"}]},
   "expect": [["ordering", "block", "SUPERSEDED_BY_LATER_EVENT"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend after a later discharge the receiver already committed",
   "summary": {"timeline": [{"later": true, "outcome": "already_committed", "event": "discharge", "event_time": "2026-10-19T11:00:00Z"}]},
   "expect": [["ordering", "block", "SUPERSEDED_BY_LATER_EVENT"]]},
  {"group": "ordering", "name": "a later transfer the feed sent that failed too supersedes, outside a chain",
   "summary": {"timeline": [{"later": true, "source": "feed", "outcome": "failed", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z"}]},
   "expect": [["ordering", "block", "SUPERSEDED_BY_LATER_EVENT"]], "outcome": "block"},
  {"group": "ordering", "name": "the same failed later transfer in an ordered chain supersedes nothing: the incident sends the chain in order",
   "summary": {"timeline": [{"later": true, "source": "feed", "outcome": "failed", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z"}]},
   "request": {"chain_kind": "ordered"},
   "expect": [["ordering", "pass", "NO_LATER_EVENT"]]},
  {"group": "ordering", "name": "a later discharge the feed sent that failed too supersedes nothing",
   "summary": {"timeline": [{"later": true, "source": "feed", "outcome": "failed", "event": "discharge", "event_time": "2026-10-19T10:00:00Z"}]},
   "expect": [["ordering", "pass", "NO_LATER_EVENT"]]},
  {"group": "ordering", "name": "a later transfer found on another route, with no known outcome, supersedes nothing",
   "summary": {"timeline": [{"later": true, "source": "index", "outcome": "unknown", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z"}]},
   "expect": [["ordering", "pass", "NO_LATER_EVENT"]]},
  {"group": "ordering", "name": "a later update supersedes nothing",
   "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "update", "event_time": "2026-10-19T10:00:00Z"}]},
   "expect": [["ordering", "pass", "NO_LATER_EVENT"]]},
  {"group": "ordering", "name": "an earlier transfer in the message store supersedes nothing",
   "summary": {"timeline": [{"later": false, "outcome": "applied", "event": "transfer", "ward": "WARD-A", "event_time": "2026-10-19T08:00:00Z"}]},
   "expect": [["ordering", "pass", "NO_LATER_EVENT"]]},
  {"group": "ordering", "name": "an earlier transfer in the receiver's own history supersedes nothing",
   "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "transfer", "event_time": "2026-10-19T08:00:00Z", "ward": "WARD-A"}]}},
   "expect": [["ordering", "pass", "NO_LATER_EVENT"]]},
  {"group": "ordering", "name": "a transfer in the receiver's own history at the event's own time is not later",
   "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "transfer", "event_time": "2026-10-19T09:00:00Z", "ward": "WARD-A"}]}},
   "expect": [["ordering", "pass", "NO_LATER_EVENT"]]},
  {"group": "ordering", "name": "a later discharge in the receiver's own history",
   "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "discharge", "event_time": "2026-10-19T11:00:00Z"}]}},
   "expect": [["ordering", "block", "SUPERSEDED_BY_LATER_EVENT"]], "contains": [["ordering", "SUPERSEDED_BY_LATER_EVENT", "discharge at 2026-10-19T11:00:00Z (receiver history)"]]},
  {"group": "ordering", "name": "a resend after a later cancel of the event was applied",
   "summary": {"timeline": [{"later": false, "outcome": "applied", "event": "cancel_transfer", "event_time": "2026-10-19T09:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_transfer^2026-10-19T09:00:00Z"}]},
   "expect": [["ordering", "block", "SUPERSEDED_BY_LATER_EVENT"]], "contains": [["ordering", "SUPERSEDED_BY_LATER_EVENT", "A later event was applied: cancel of the event at 2026-10-19T09:00:00Z"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend after a later merge was applied",
   "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "merge", "event_time": "2026-10-19T12:00:00Z"}]},
   "expect": [["ordering", "block", "SUPERSEDED_BY_LATER_EVENT"]], "contains": [["ordering", "SUPERSEDED_BY_LATER_EVENT", "merge at 2026-10-19T12:00:00Z"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend after a later admission was applied",
   "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "admit", "ward": "WARD-A", "event_time": "2026-10-19T12:00:00Z"}]},
   "expect": [["ordering", "block", "SUPERSEDED_BY_LATER_EVENT"]], "contains": [["ordering", "SUPERSEDED_BY_LATER_EVENT", "admission at 2026-10-19T12:00:00Z"]], "outcome": "block"},
  {"group": "ordering", "name": "a resend after a later cancel the receiver did not apply",
   "summary": {"timeline": [{"later": false, "outcome": "failed", "event": "cancel_transfer", "event_time": "2026-10-19T09:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_transfer^2026-10-19T09:00:00Z"}]},
   "expect": [["ordering", "pass", "NO_LATER_EVENT"]]},
  {"group": "ordering", "name": "a write with both an undelivered later transfer and a discharge in the receiver's history names the history",
   "summary": {"timeline": [{"later": true, "source": "feed", "outcome": "failed", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z"}], "ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "discharge", "event_time": "2026-10-19T11:00:00Z"}]}},
   "expect": [["ordering", "block", "SUPERSEDED_BY_LATER_EVENT"]], "contains": [["ordering", "SUPERSEDED_BY_LATER_EVENT", "A later event was applied: discharge at 2026-10-19T11:00:00Z (receiver history)"]]},
  {"group": "ordering", "name": "the snapshot's chain kind outranks the request's: ordered in the conditions, single in the request",
   "summary": {"catalogue": {"conditions": {"chain": "ordered"}}, "timeline": [{"later": true, "source": "feed", "outcome": "failed", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z"}]},
   "request": {"chain_kind": "single"},
   "expect": [["ordering", "pass", "NO_LATER_EVENT"]]},
  {"group": "ordering", "name": "a later transfer timed after the evidence was taken supersedes nothing, and the doubt blocks",
   "summary": {"observed_at": "2026-10-19T13:00:00Z", "catalogue": {"conditions": {"event_time": "later_event_future"}}, "timeline": [{"later": true, "outcome": "applied", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T14:00:00Z"}]},
   "expect": [["ordering", "block", "EVENT_TIME_IMPLAUSIBLE"]], "absent": [["ordering", "SUPERSEDED_BY_LATER_EVENT"]], "outcome": "block"},
  {"group": "ordering", "name": "superseded, with a doubtful event time",
   "plan": {"disposition": "superseded", "action": null}, "summary": {"catalogue": {"conditions": {"event_time": "clock_change"}}, "timeline": [{"later": true, "outcome": "applied", "event": "transfer", "event_time": "2026-10-19T10:00:00Z"}]},
   "expect": [["ordering", "block", "EVENT_TIME_IMPLAUSIBLE"]], "outcome": "block"},
  {"group": "ordering", "name": "superseded, with the later transfer in evidence",
   "plan": {"disposition": "superseded", "action": null}, "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z"}]},
   "expect": [["ordering", "pass", "SUPERSEDED_BY_LATER_EVENT"]], "contains": [["ordering", "SUPERSEDED_BY_LATER_EVENT", "transfer to WARD-C at 2026-10-19T10:00:00Z"]], "outcome": "pass"},
  {"group": "ordering", "name": "superseded, with a later transfer the feed sent that failed too",
   "plan": {"disposition": "superseded", "action": null}, "summary": {"timeline": [{"later": true, "source": "feed", "outcome": "failed", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z"}]},
   "expect": [["ordering", "pass", "SUPERSEDED_BY_LATER_EVENT"]], "contains": [["ordering", "SUPERSEDED_BY_LATER_EVENT", "its own case recovers it"], ["ordering", "SUPERSEDED_BY_LATER_EVENT", "sent as PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z (its delivery failed or is uncertain"]], "outcome": "pass"},
  {"group": "ordering", "name": "superseded, with a later cancel alone: the closure rests on a transfer or a discharge",
   "plan": {"disposition": "superseded", "action": null}, "summary": {"timeline": [{"later": false, "outcome": "applied", "event": "cancel_transfer", "event_time": "2026-10-19T09:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_transfer^2026-10-19T09:00:00Z"}]},
   "expect": [["ordering", "block", "SUPERSESSION_UNSUPPORTED"]], "outcome": "block"},
  {"group": "ordering", "name": "superseded by a catalogue entry whose preferred outcome is none",
   "plan": {"disposition": "superseded", "action": null, "catalogue_entry": "E1", "outcome": "preferred"},
   "summary": {"catalogue": {"decision": "policy", "entry": "E1", "matches": [{"id": "E1", "preferred": {"outcome": "none"}, "alternatives": []}], "facts": {"other_source": ""}}},
   "expect": [["ordering", "pass", "CLOSED_BY_CATALOGUE"], ["catalogue", "pass", "ENTRY_MATCHED"]], "absent": [["catalogue", "OUTCOME_MISMATCH"]], "outcome": "pass"},
  {"group": "ordering", "name": "superseded by a catalogue alternative whose outcome is none",
   "plan": {"disposition": "superseded", "action": null, "catalogue_entry": "E9", "outcome": "alternative:1"},
   "summary": {"catalogue": {"decision": "board", "entry": "E9", "matches": [{"id": "E9", "preferred": {"outcome": "resend"}, "alternatives": [{"outcome": "none", "when": "always"}]}], "facts": {"other_source": ""}}},
   "expect": [["ordering", "pass", "CLOSED_BY_CATALOGUE"], ["catalogue", "pass", "OUTCOME_ALLOWED"]], "outcome": "pass"},
  {"group": "ordering", "name": "superseded, with nothing later and no catalogue entry",
   "plan": {"disposition": "superseded", "action": null},
   "expect": [["ordering", "block", "SUPERSESSION_UNSUPPORTED"]], "outcome": "block"},
  {"group": "ordering", "name": "superseded by a message of the encounter still on its way: the case waits, nobody is called",
   "plan": {"disposition": "superseded", "action": null},
   "summary": {"pending_messages": [{"event": "transfer", "event_time": "2026-10-19T10:00:00Z", "operation_key": "k-later", "control_id": "MSG-9", "ens_header_id": "77", "sent_at": "2026-10-19 09:01:00.000", "receiver": "Downstream Out", "where": "queued for the receiver, no answer yet"}]},
   "expect": [["ordering", "block", "NEWER_MESSAGE_PENDING"]], "absent": [["ordering", "SUPERSESSION_UNSUPPORTED"]], "contains": [["ordering", "NEWER_MESSAGE_PENDING", "still on its way"]], "outcome": "block"},

  {"group": "state_transition", "name": "a transfer of a discharged encounter",
   "summary": {"ward_state": {"state": "discharged"}},
   "expect": [["state_transition", "block", "INVALID_TRANSITION"]], "outcome": "block"},
  {"group": "state_transition", "name": "an admission of an encounter the receiver already holds",
   "case": {"event": "admit"},
   "expect": [["identity", "pass", "IDENTITY_MATCHES"], ["state_transition", "block", "INVALID_TRANSITION"]]},
  {"group": "state_transition", "name": "a cancelled discharge of an encounter still admitted",
   "case": {"event": "cancel_discharge"}, "profile": {"receiver": {"cancels": true}},
   "expect": [["state_transition", "block", "INVALID_TRANSITION"]]},
  {"group": "state_transition", "name": "a cancelled admission of an admitted encounter",
   "case": {"event": "cancel_admit"}, "profile": {"receiver": {"cancels": true}},
   "expect": [["state_transition", "pass", "TRANSITION_ALLOWED"]]},
  {"group": "state_transition", "name": "an event word the transition table does not hold",
   "case": {"event": "register"},
   "expect": [["state_transition", "block", "INVALID_TRANSITION"]]},

  {"group": "effect", "name": "reconcile, with the receiver's receipt",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "summary": {"receipt_http_status": 200, "receipt": {"operation_key": "{key}"}},
   "expect": [["effect", "pass", "RECEIPT_FOUND"]], "outcome": "pass"},
  {"group": "effect", "name": "reconcile, the receipt's digest the operation's own",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "summary": {"receipt_http_status": 200, "receipt": {"operation_key": "{key}", "payload_digest": "sha256:ut"}},
   "expect": [["effect", "pass", "RECEIPT_FOUND"]], "outcome": "pass"},
  {"group": "effect", "name": "reconcile, the receipt holding other content under the key",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "summary": {"receipt_http_status": 200, "receipt": {"operation_key": "{key}", "payload_digest": "sha256:other", "ward": "WARD-B"}, "operation": {"ward": "WARD-C"}},
   "expect": [["effect", "block", "RECEIPT_PAYLOAD_DIFFERS"]], "outcome": "block"},
  {"group": "effect", "name": "reconcile, the receipt naming another bed under the same digest",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "summary": {"receipt_http_status": 200, "receipt": {"operation_key": "{key}", "payload_digest": "sha256:ut", "bed": "B1"}, "operation": {"bed": "B2"}},
   "expect": [["effect", "block", "RECEIPT_PAYLOAD_DIFFERS"]], "outcome": "block"},
  {"group": "effect", "name": "reconcile, the receipt and the operation both with no bed",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "summary": {"receipt_http_status": 200, "receipt": {"operation_key": "{key}", "payload_digest": "sha256:ut", "bed": null}, "operation": {"bed": null}},
   "expect": [["effect", "pass", "RECEIPT_FOUND"]], "outcome": "pass"},
  {"group": "effect", "name": "reconcile, a site that reads this receiver's answers on status alone",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "profile": {"receiver": {"strict_answers": false}}, "summary": {"receipt_http_status": 200, "receipt": {"operation_key": "{key}", "payload_digest": "sha256:other"}},
   "expect": [["effect", "pass", "RECEIPT_FOUND"]], "outcome": "pass"},
  {"group": "effect", "name": "reconcile, a cancel recorded since: the receipt is not what stands",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "summary": {"receipt_http_status": 200, "receipt": {"operation_key": "{key}", "payload_digest": "sha256:ut"},
     "timeline": [{"event": "cancel_transfer", "event_time": "2026-10-19T10:00:00Z", "operation_key": "PAS^HOSP^MRN-UT^ENC-UT^cancel_transfer^2026-10-19T10:00:00Z", "outcome": "unknown", "source": "index"}]},
   "expect": [["effect", "block", "RECEIPT_THEN_CANCELLED"]], "outcome": "block"},
  {"group": "effect", "name": "a resend of an operation the receiver already committed",
   "summary": {"receipt_http_status": 200, "receipt": {"operation_key": "{key}"}},
   "expect": [["effect", "block", "ALREADY_COMMITTED"]], "outcome": "block"},
  {"group": "effect", "name": "an escalation with a receipt",
   "plan": {"disposition": "escalate", "action": null}, "summary": {"receipt_http_status": 200},
   "expect": [["effect", "pass", "RECEIPT_FOUND"]]},
  {"group": "effect", "name": "reconcile, with no receipt",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}},
   "expect": [["effect", "block", "NO_RECEIPT"]], "outcome": "block"},
  {"group": "effect", "name": "reconcile with a receiver that keeps no receipts, its history showing the operation",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "summary": {"receipt_http_status": -1, "ward_state": {"history": [{"event": "transfer", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "expect": [["effect", "pass", "RECEIPT_NOT_AVAILABLE"]]},
  {"group": "effect", "name": "reconcile with a receiver that keeps no receipts, its history silent",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "summary": {"receipt_http_status": -1},
   "expect": [["effect", "block", "RECEIPT_NOT_AVAILABLE"]], "outcome": "block"},
  {"group": "effect", "name": "a resend to a receiver that keeps no receipts",
   "summary": {"receipt_http_status": -1},
   "expect": [["effect", "pass", "RECEIPT_NOT_AVAILABLE"]]},
  {"group": "effect", "name": "the receipt lookup failed",
   "summary": {"receipt_http_status": 500},
   "expect": [["effect", "unknown", "RECEIPT_UNREADABLE"]], "contains": [["effect", "RECEIPT_UNREADABLE", "lookup failed (HTTP 500)"]], "outcome": "unknown"},
  {"group": "effect", "name": "the receipt lookup got no answer",
   "summary": {"receipt_http_status": 0},
   "expect": [["effect", "unknown", "RECEIPT_UNREADABLE"]], "contains": [["effect", "RECEIPT_UNREADABLE", "lookup failed (no answer)"]], "outcome": "unknown"},

  {"group": "authorization", "name": "at approval, with no approval",
   "request": {"stage": "approval"},
   "expect": [["authorization", "block", "NO_APPROVAL"]], "outcome": "block"},
  {"group": "authorization", "name": "an approval for exactly this plan",
   "approval": {},
   "expect": [["authorization", "pass", "APPROVAL_VALID"]], "outcome": "pass"},
  {"group": "authorization", "name": "a rejection",
   "approval": {"decision": "rejected"},
   "expect": [["authorization", "block", "APPROVAL_NOT_APPROVED"]], "outcome": "block"},
  {"group": "authorization", "name": "a revoked approval",
   "approval": {"revoked": true},
   "expect": [["authorization", "block", "APPROVAL_REVOKED"]]},
  {"group": "authorization", "name": "an expired approval",
   "approval": {"valid_seconds": -60},
   "expect": [["authorization", "block", "APPROVAL_EXPIRED"]]},
  {"group": "authorization", "name": "an approval of another plan version",
   "approval": {"plan_digest": "sha256:an-earlier-plan"},
   "expect": [["authorization", "block", "APPROVAL_PLAN_CHANGED"]]},
  {"group": "authorization", "name": "an approval of other evidence",
   "approval": {"snapshot_digest": "sha256:other-items", "material_digest": "sha256:other-evidence"},
   "expect": [["authorization", "block", "APPROVAL_SNAPSHOT_CHANGED"]]},
  {"group": "authorization", "name": "a refreshed snapshot with the same material evidence keeps the approval",
   "approval": {"snapshot_digest": "sha256:other-items"},
   "expect": [["authorization", "pass", "APPROVAL_VALID"]]},
  {"group": "authorization", "name": "an approval under an earlier gate policy",
   "approval": {"policy_version": "2026-01-01.1"},
   "expect": [["authorization", "block", "APPROVAL_POLICY_CHANGED"]]},
  {"group": "authorization", "name": "a plan made against an earlier catalogue",
   "summary": {"catalogue": {"catalogue_version": "E1@0"}}, "approval": {},
   "expect": [["authorization", "block", "APPROVAL_CATALOGUE_CHANGED"]]},
  {"group": "authorization", "name": "an approval under an earlier site profile",
   "approval": {"site_profile_version": "-1"},
   "expect": [["authorization", "block", "APPROVAL_SITE_PROFILE_CHANGED"]]},
  {"group": "authorization", "name": "the receiver moved on since the approval",
   "approval": {"expected_version": 3}, "request": {"receiver_version": 4},
   "expect": [["authorization", "block", "APPROVAL_RECEIVER_CHANGED"], ["concurrency", "block", "RECEIVER_CHANGED"]]},
  {"group": "authorization", "name": "the receiver was reset since the approval",
   "approval": {"epoch": 1}, "request": {"receiver_epoch": 2},
   "expect": [["authorization", "block", "APPROVAL_RECEIVER_RESET"]]},
  {"group": "authorization", "name": "an automatic release the site's policy allows, from the policy path",
   "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"}, "approval": {"approver": "policy"}, "request": {"chain_kind": "single"},
   "profile": {"policy": {"2": {"single": "automatic"}}},
   "expect": [["authorization", "pass", "APPROVAL_VALID"]]},
  {"group": "authorization", "name": "an automatic release where the site's policy asks for approval",
   "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"}, "approval": {"approver": "policy"}, "request": {"chain_kind": "ordered"},
   "profile": {"policy": {"2": {"ordered": "approval"}}},
   "expect": [["authorization", "block", "POLICY_REQUIRES_APPROVAL"]]},
  {"group": "authorization", "name": "an automatic release of a lost admission: the receiver's 404 proves nothing about a record entered by hand",
   "case": {"event": "admit"}, "summary": {"ward_state_http_status": 404, "ward_state": null},
   "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2", "action": {"expected_version": 0}}, "approval": {"approver": "policy"}, "request": {"chain_kind": "single"},
   "profile": {"policy": {"2": {"single": "automatic"}}},
   "expect": [["authorization", "block", "POLICY_REQUIRES_APPROVAL"]]},
  {"group": "authorization", "name": "the same release at a site whose profile lets policy take a lost admission",
   "case": {"event": "admit"}, "summary": {"ward_state_http_status": 404, "ward_state": null},
   "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2", "action": {"expected_version": 0}}, "approval": {"approver": "policy"}, "request": {"chain_kind": "single"},
   "profile": {"policy": {"2": {"single": "automatic"}}, "further_messages": {"admission_not_found": "policy"}},
   "expect": [["authorization", "pass", "APPROVAL_VALID"]]},
  {"group": "engine", "name": "the scope reads no: the check passes and reads nothing",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "no", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [], "effectiveAck": "", "ackReason": ""}, 
   "expect": [["ordering", "pass", "ENGINE_NOT_IN_SCOPE"]], "outcome": "pass"},
  {"group": "engine", "name": "the scope can't be read: a write never passes",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "unreadable", "why": "the item is not read", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [], "effectiveAck": "", "ackReason": ""}, 
   "expect": [["ordering", "unknown", "ENGINE_UNREADABLE"]], "outcome": "unknown"},
  {"group": "engine", "name": "a header in the engine's hands",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "engine", "status": "Delivered", "itemStatus": "Retry", "completedAt": "", "why": "", "attempts": ""}], "effectiveAck": "", "ackReason": ""}, "contains": [["ordering", "ENGINE_STILL_TRYING", "status Delivered, operation Retry"]],
   "expect": [["ordering", "block", "ENGINE_STILL_TRYING"]], "outcome": "block"},
  {"group": "engine", "name": "a subclass that overrides reply handling is read as the stock class is",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "base", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "engine", "status": "Queued", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": ""}], "effectiveAck": "", "ackReason": ""}, 
   "expect": [["ordering", "block", "ENGINE_STILL_TRYING"]], "outcome": "block"},
  {"group": "engine", "name": "the origin settled and a hand resend's copy in the engine's hands",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "never_opened"}, {"headerId": "18", "custody": "engine", "status": "Delivered", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": ""}], "effectiveAck": "", "ackReason": ""}, 
   "expect": [["ordering", "block", "ENGINE_STILL_TRYING"]], "outcome": "block"},
  {"group": "engine", "name": "a Completed header on an alert route, whenever it completed",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "delivered", "status": "Completed", "itemStatus": "OK", "completedAt": "2026-11-07 03:12:01.123", "why": "", "attempts": ""}], "effectiveAck": "connection", "ackReason": ""}, "contains": [["ordering", "ENGINE_DELIVERED", "nothing to resend"]],
   "expect": [["ordering", "block", "ENGINE_DELIVERED"]], "outcome": "block"},
  {"group": "engine", "name": "a Completed copy on an alert route",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "never_opened"}, {"headerId": "18", "custody": "delivered", "status": "Completed", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": ""}], "effectiveAck": "connection", "ackReason": ""}, 
   "expect": [["ordering", "block", "ENGINE_DELIVERED"]], "outcome": "block"},
  {"group": "engine", "name": "a Completed header where the reply actions complete a refusal",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "delivered", "status": "Completed", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": ""}], "effectiveAck": "not_established", "ackReason": ":?E=C"}, "contains": [["ordering", "ENGINE_DELIVERED", "Receiver acceptance has not been established"], ["ordering", "ENGINE_DELIVERED", ":?E=C"]],
   "expect": [["ordering", "block", "ENGINE_DELIVERED"]], "outcome": "block"},
  {"group": "engine", "name": "a Completed header on the acknowledgement feed",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": true, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "delivered", "status": "Completed", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": ""}], "effectiveAck": "", "ackReason": ""}, 
   "expect": [["ordering", "pass", "ENGINE_SETTLED"]], "outcome": "pass"},
  {"group": "engine", "name": "a settled header that never opened",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "never_opened"}], "effectiveAck": "", "ackReason": ""}, 
   "expect": [["ordering", "pass", "ENGINE_SETTLED"]], "outcome": "pass"},
  {"group": "engine", "name": "a settled header the receiver was reached on",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "reached_receiver"}], "effectiveAck": "", "ackReason": ""}, "contains": [["ordering", "RECEIVER_MAY_HOLD_IT", "the receiver's own screen"]],
   "expect": [["ordering", "block", "RECEIVER_MAY_HOLD_IT"]], "outcome": "block"},
  {"group": "engine", "name": "a settled header with words the table doesn't hold",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "unknown"}], "effectiveAck": "", "ackReason": ""}, 
   "expect": [["ordering", "block", "RECEIVER_MAY_HOLD_IT"]], "outcome": "block"},
  {"group": "engine", "name": "a settled header with no rows",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "no_rows"}], "effectiveAck": "", "ackReason": ""}, 
   "expect": [["ordering", "block", "RECEIVER_MAY_HOLD_IT"]], "outcome": "block"},
  {"group": "engine", "name": "a settled copy the receiver was reached on",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "never_opened"}, {"headerId": "18", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "reached_receiver"}], "effectiveAck": "", "ackReason": ""}, 
   "expect": [["ordering", "block", "RECEIVER_MAY_HOLD_IT"]], "outcome": "block"},
  {"group": "engine", "name": "a header whose status the table doesn't name",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "yes", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "unreadable", "status": "Discarded", "itemStatus": "OK", "completedAt": "", "why": "the header reads Discarded", "attempts": ""}], "effectiveAck": "", "ackReason": ""}, "contains": [["ordering", "ENGINE_UNREADABLE", "the header reads Discarded"]],
   "expect": [["ordering", "unknown", "ENGINE_UNREADABLE"]], "outcome": "unknown"},
  {"group": "engine", "name": "a watched case with no origin header never reaches the check",
   "case": {"source_namespace": "RIG"}, "engine": {"scope": "unreadable", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [], "effectiveAck": "", "ackReason": ""},
   "expect": [["ordering", "pass", "NO_LATER_EVENT"]], "absent": [["ordering", "ENGINE_UNREADABLE"], ["ordering", "ENGINE_NOT_IN_SCOPE"]]},
  {"group": "engine", "name": "a plan that writes nothing never reaches the check",
   "case": {"source_namespace": "RIG", "origin_header_id": "16"}, "engine": {"scope": "unreadable", "why": "", "namespace": "RIG", "item": "LIMS Out", "receiver": "LIMS Out", "ackRoute": false, "deliveryHeader": "17", "headers": [], "effectiveAck": "", "ackReason": ""}, "plan": {"disposition": "escalate", "action": {"type": "none"}},
   "expect": [["ordering", "pass", "NOT_APPLICABLE"]], "absent": [["ordering", "ENGINE_UNREADABLE"]]},
  {"group": "engine", "name": "the live read, at a namespace that does not exist, blocks",
   "case": {"source_namespace": "UTNOSUCHNAMESPACE", "origin_header_id": "1"},
   "expect": [["ordering", "unknown", "ENGINE_UNREADABLE"]], "outcome": "unknown"},
  {"group": "authorization", "name": "an automatic release of a case whose source cannot be proved",
   "case": {"source_namespace": "UTNOSUCHNAMESPACE", "origin_header_id": "1"}, "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"}, "approval": {"approver": "policy"}, "request": {"chain_kind": "single"},
   "profile": {"policy": {"2": {"single": "automatic"}}},
   "expect": [["authorization", "block", "APPROVAL_ORIGIN_NOT_PROVED"]]},
  {"group": "authorization", "name": "a person's approval of a case whose source cannot be proved",
   "case": {"source_namespace": "UTNOSUCHNAMESPACE", "origin_header_id": "1"}, "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"}, "approval": {},
   "expect": [["authorization", "pass", "APPROVAL_VALID"]]},
  {"group": "authorization", "name": "an automatic release of a board's plan",
   "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "run:1"}, "approval": {"approver": "policy"},
   "profile": {"policy": {"2": {"single": "automatic"}}},
   "expect": [["authorization", "block", "APPROVAL_PLAN_ORIGIN"]]},
  {"group": "authorization", "name": "an automatic release of a plan that names no entry",
   "plan": {"created_by": "policy:"}, "approval": {"approver": "policy"},
   "profile": {"policy": {"2": {"single": "automatic"}}},
   "expect": [["authorization", "block", "APPROVAL_PLAN_ORIGIN"]]},
  {"group": "authorization", "name": "an approval under an incident, for the item it bound",
   "incident": {"plan_digest": "sha256:ut-incident"}, "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"},
   "summary": {"catalogue": {"decision": "policy", "entry": "E2", "outcome": "resend", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}]}},
   "approval": {"incident_plan_digest": "sha256:ut-incident", "bound_entry": "E2", "bound_outcome": "resend"},
   "expect": [["authorization", "pass", "APPROVAL_VALID"], ["catalogue", "pass", "ENTRY_MATCHED"]], "outcome": "pass"},
  {"group": "authorization", "name": "an approval under an incident whose receiver was reset since the plan the person bound, the numbers matching",
   "incident": {"plan_digest": "sha256:ut-incident", "epoch": 1}, "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"},
   "summary": {"catalogue": {"decision": "policy", "entry": "E2", "outcome": "resend", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}]}},
   "approval": {"incident_plan_digest": "sha256:ut-incident", "bound_entry": "E2", "bound_outcome": "resend", "epoch": 2}, "rehearsal": {"epoch": 2}, "request": {"receiver_epoch": 2},
   "expect": [["authorization", "block", "APPROVAL_RECEIVER_RESET"]], "outcome": "block"},
  {"group": "authorization", "name": "an approval under an incident, the receiver at the epoch of the plan",
   "incident": {"plan_digest": "sha256:ut-incident", "epoch": 1}, "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"},
   "summary": {"catalogue": {"decision": "policy", "entry": "E2", "outcome": "resend", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}]}},
   "approval": {"incident_plan_digest": "sha256:ut-incident", "bound_entry": "E2", "bound_outcome": "resend", "epoch": 1}, "request": {"receiver_epoch": 1},
   "expect": [["authorization", "pass", "APPROVAL_VALID"]], "outcome": "pass"},
  {"group": "authorization", "name": "an approval under an incident whose plan recorded no epoch: a receiver that keeps none",
   "incident": {"plan_digest": "sha256:ut-incident"}, "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"},
   "summary": {"catalogue": {"decision": "policy", "entry": "E2", "outcome": "resend", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}]}},
   "approval": {"incident_plan_digest": "sha256:ut-incident", "bound_entry": "E2", "bound_outcome": "resend", "epoch": 1}, "request": {"receiver_epoch": 1},
   "expect": [["authorization", "pass", "APPROVAL_VALID"]], "outcome": "pass"},
  {"group": "authorization", "name": "an approval under an incident whose item now follows another entry",
   "incident": {"plan_digest": "sha256:ut-incident"}, "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"},
   "summary": {"catalogue": {"decision": "policy", "entry": "E2", "outcome": "resend", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}]}},
   "approval": {"incident_plan_digest": "sha256:ut-incident", "bound_entry": "E4", "bound_outcome": "resend_chain"},
   "expect": [["authorization", "block", "APPROVAL_ITEM_CHANGED"]], "outcome": "block"},
  {"group": "authorization", "name": "an approval under an incident whose fresh evidence no longer matches the bound entry",
   "incident": {"plan_digest": "sha256:ut-incident"}, "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"},
   "summary": {"catalogue": {"decision": "policy", "entry": "E3", "outcome": "reconcile", "matches": [{"id": "E3", "preferred": {"outcome": "reconcile"}}]}},
   "approval": {"incident_plan_digest": "sha256:ut-incident", "bound_entry": "E2", "bound_outcome": "resend"},
   "expect": [["authorization", "block", "APPROVAL_ITEM_CHANGED"]], "outcome": "block"},
  {"group": "authorization", "name": "an approval under an incident whose fresh evidence reads another outcome for the same entry",
   "incident": {"plan_digest": "sha256:ut-incident"}, "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"},
   "summary": {"catalogue": {"decision": "policy", "entry": "E2", "outcome": "resend_chain", "matches": [{"id": "E2", "preferred": {"outcome": "resend_chain"}}]}},
   "approval": {"incident_plan_digest": "sha256:ut-incident", "bound_entry": "E2", "bound_outcome": "resend"},
   "expect": [["authorization", "block", "APPROVAL_ITEM_CHANGED"]]},
  {"group": "authorization", "name": "an approval under an incident whose plan was built again",
   "incident": {"plan_digest": "sha256:ut-incident"}, "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"},
   "summary": {"catalogue": {"decision": "policy", "entry": "E2", "outcome": "resend", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}]}},
   "approval": {"incident_plan_digest": "sha256:an-earlier-incident-plan", "bound_entry": "E2", "bound_outcome": "resend"},
   "expect": [["authorization", "block", "APPROVAL_INCIDENT_PLAN_CHANGED"]], "outcome": "block"},
  {"group": "authorization", "name": "an approval under an incident the case no longer belongs to",
   "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "policy:E2"},
   "summary": {"catalogue": {"decision": "policy", "entry": "E2", "outcome": "resend", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}]}},
   "approval": {"incident_plan_digest": "sha256:ut-incident", "bound_entry": "E2", "bound_outcome": "resend"},
   "expect": [["authorization", "block", "APPROVAL_INCIDENT_PLAN_CHANGED"]]},

  {"group": "concurrency", "name": "a write that names no receiver version",
   "plan": {"action": {"expected_version": null}},
   "expect": [["concurrency", "block", "NO_EXPECTED_VERSION"]], "outcome": "block"},
  {"group": "concurrency", "name": "the receiver's version is not the one the plan expects",
   "summary": {"ward_state": {"version": 4}},
   "expect": [["concurrency", "block", "RECEIVER_CHANGED"]], "outcome": "block"},
  {"group": "concurrency", "name": "the version observed at dispatch is newer than the snapshot's",
   "request": {"receiver_version": 5},
   "expect": [["concurrency", "block", "RECEIVER_CHANGED"]]},
  {"group": "concurrency", "name": "an admission that expects a version other than 0",
   "case": {"event": "admit"}, "summary": {"ward_state_http_status": 404, "ward_state": null}, "plan": {"action": {"expected_version": 2}},
   "expect": [["concurrency", "block", "RECEIVER_CHANGED"]]},

  {"group": "evidence", "name": "the snapshot's observations have expired",
   "snapshot": {"fresh_seconds": -60},
   "expect": [["evidence", "unknown", "STALE_EVIDENCE"]], "outcome": "unknown"},

  {"group": "capability", "name": "the receiver's capability profile could not be read",
   "summary": {"route": {"capabilities_http_status": 503}},
   "expect": [["capability", "unknown", "CAPABILITIES_UNREADABLE"]], "outcome": "unknown"},
  {"group": "capability", "name": "a receiver without conditional writes",
   "summary": {"route": {"conditional_writes": false}},
   "expect": [["capability", "block", "CONNECTOR_INCAPABLE"]], "outcome": "block"},
  {"group": "capability", "name": "a receiver without receipts",
   "summary": {"route": {"receipts": false}},
   "expect": [["capability", "block", "CONNECTOR_INCAPABLE"]]},
  {"group": "capability", "name": "a receiver that declares no history",
   "summary": {"route": {"history": false}},
   "expect": [["capability", "block", "HISTORY_UNSUPPORTED"]], "absent": [["capability", "CONNECTOR_CAPABLE"]], "outcome": "block"},
  {"group": "capability", "name": "a route that says nothing about history, as an older snapshot's",
   "summary": {"route": {"history": null}},
   "expect": [["capability", "block", "HISTORY_UNSUPPORTED"]], "outcome": "block"},
  {"group": "capability", "name": "no conditional writes comes first and alone, whatever the history",
   "summary": {"route": {"conditional_writes": false, "history": false}},
   "expect": [["capability", "block", "CONNECTOR_INCAPABLE"]], "absent": [["capability", "HISTORY_UNSUPPORTED"]], "outcome": "block"},
  {"group": "capability", "name": "a read with no history from a receiver that declares one",
   "summary": {"ward_state": {"history": null}},
   "expect": [["capability", "unknown", "HISTORY_UNREADABLE"]], "absent": [["capability", "CONNECTOR_CAPABLE"]], "outcome": "unknown"},
  {"group": "capability", "name": "a read whose history is not an array",
   "summary": {"ward_state": {"history": {"note": "see elsewhere"}}},
   "expect": [["capability", "unknown", "HISTORY_UNREADABLE"]], "outcome": "unknown"},
  {"group": "capability", "name": "an empty history is a history",
   "summary": {"ward_state": {"history": []}},
   "expect": [["capability", "pass", "CONNECTOR_CAPABLE"]]},
  {"group": "capability", "name": "an admission the receiver does not know yet has no history to read",
   "case": {"event": "admit"}, "summary": {"ward_state_http_status": 404, "ward_state": {"error": "unknown_encounter", "history": null}},
   "expect": [["capability", "pass", "CONNECTOR_CAPABLE"]], "absent": [["capability", "HISTORY_UNREADABLE"]]},
  {"group": "capability", "name": "closing a case needs no history",
   "plan": {"disposition": "superseded", "action": {"type": "none"}}, "summary": {"route": {"history": false}},
   "expect": [["capability", "pass", "NOT_APPLICABLE"]]},
  {"group": "capability", "name": "reconciling needs no write capability",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "summary": {"receipt_http_status": 200, "route": {"conditional_writes": false}},
   "expect": [["capability", "pass", "NOT_APPLICABLE"]], "outcome": "pass"},

  {"group": "catalogue", "name": "the matcher had no catalogue",
   "summary": {"catalogue": {"decision": "not_configured", "matches": []}},
   "expect": [["catalogue", "pass", "NOT_CONFIGURED"]]},
  {"group": "catalogue", "name": "the matcher failed",
   "summary": {"catalogue": {"decision": "error", "error": "the pattern of E4 is not an object"}},
   "expect": [["catalogue", "unknown", "MATCHER_ERROR"]], "outcome": "unknown"},
  {"group": "catalogue", "name": "no entry matches the evidence",
   "summary": {"catalogue": {"decision": "new_pattern", "matches": []}},
   "expect": [["catalogue", "block", "NEW_PATTERN"]], "outcome": "block"},
  {"group": "catalogue", "name": "the plan names no entry while several match",
   "summary": {"catalogue": {"decision": "board", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}, {"id": "E9", "preferred": {"outcome": "resend"}}]}},
   "expect": [["catalogue", "pass", "ENTRY_NOT_NAMED"]]},
  {"group": "catalogue", "name": "Rules only's plan names no entry on an entry that stops, in a recorded scenario: the demonstration stays",
   "case": {"scenario": "S8", "scenario_recorded": true}, "summary": {"catalogue": {"decision": "board", "entry": "E7", "outcome": "escalate", "matches": [{"id": "E7", "preferred": {"outcome": "escalate"}}]}},
   "expect": [["catalogue", "pass", "ENTRY_NOT_NAMED"]]},
  {"group": "catalogue", "name": "Rules only on a case stamped by a live story, which the scenario runner did not play, gets no exemption",
   "case": {"scenario": "S8"}, "summary": {"catalogue": {"decision": "board", "entry": "E7", "outcome": "escalate", "matches": [{"id": "E7", "preferred": {"outcome": "escalate"}}]}},
   "expect": [["catalogue", "block", "ENTRY_NOT_NAMED_WRITE"]], "outcome": "block"},
  {"group": "catalogue", "name": "Rules only on a real case, which no scenario made, gets no exemption",
   "summary": {"catalogue": {"decision": "board", "entry": "E7", "outcome": "escalate", "matches": [{"id": "E7", "preferred": {"outcome": "escalate"}}]}},
   "expect": [["catalogue", "block", "ENTRY_NOT_NAMED_WRITE"]], "outcome": "block"},
  {"group": "catalogue", "name": "a board's plan writes and names no entry on an entry that stops",
   "case": {"mode": "board"}, "plan": {"created_by": "run:1"}, "summary": {"catalogue": {"decision": "board", "entry": "E7", "outcome": "escalate", "matches": [{"id": "E7", "preferred": {"outcome": "escalate"}}]}},
   "expect": [["catalogue", "block", "ENTRY_NOT_NAMED_WRITE"]], "outcome": "block", "contains": [["catalogue", "ENTRY_NOT_NAMED_WRITE", "E7"]]},
  {"group": "catalogue", "name": "a judge's board on a Rules only case writes and names no entry on an entry that stops",
   "plan": {"created_by": "run:1"}, "summary": {"catalogue": {"decision": "board", "entry": "E7", "outcome": "escalate", "matches": [{"id": "E7", "preferred": {"outcome": "escalate"}}]}},
   "expect": [["catalogue", "block", "ENTRY_NOT_NAMED_WRITE"]], "outcome": "block"},
  {"group": "catalogue", "name": "the rules path outside Rules only writes and names no entry on an entry that stops",
   "case": {"mode": "policy"}, "summary": {"catalogue": {"decision": "board", "entry": "E7", "outcome": "escalate", "matches": [{"id": "E7", "preferred": {"outcome": "escalate"}}]}},
   "expect": [["catalogue", "block", "ENTRY_NOT_NAMED_WRITE"]], "outcome": "block"},
  {"group": "catalogue", "name": "a follower's plan writes and names no entry when the site chose an outcome with no write",
   "case": {"mode": "board"}, "plan": {"created_by": "lead:C-1"}, "summary": {"catalogue": {"decision": "board", "entry": "E7", "outcome": "none", "outcome_ref": "alternative:1", "matches": [{"id": "E7", "preferred": {"outcome": "escalate"}}]}},
   "expect": [["catalogue", "block", "ENTRY_NOT_NAMED_WRITE"]], "outcome": "block"},
  {"group": "catalogue", "name": "a plan writes and names no entry while one of several matches stops",
   "case": {"mode": "board"}, "plan": {"created_by": "run:1"}, "summary": {"catalogue": {"decision": "board", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}, {"id": "E7", "preferred": {"outcome": "escalate"}}]}},
   "expect": [["catalogue", "block", "ENTRY_NOT_NAMED_WRITE"]], "outcome": "block", "contains": [["catalogue", "ENTRY_NOT_NAMED_WRITE", "E7"]]},
  {"group": "catalogue", "name": "a board's plan writes and names no entry on an entry that resends",
   "case": {"mode": "board"}, "plan": {"created_by": "run:1"}, "summary": {"catalogue": {"decision": "board", "entry": "E9", "outcome": "resend", "matches": [{"id": "E9", "preferred": {"outcome": "resend"}}]}},
   "expect": [["catalogue", "pass", "ENTRY_NOT_NAMED"]]},
  {"group": "catalogue", "name": "a plan that names no entry and writes nothing on an entry that stops",
   "case": {"mode": "board"}, "plan": {"created_by": "run:1", "disposition": "escalate", "action": {"type": "none"}}, "summary": {"catalogue": {"decision": "board", "entry": "E7", "outcome": "escalate", "matches": [{"id": "E7", "preferred": {"outcome": "escalate"}}]}},
   "expect": [["catalogue", "pass", "ENTRY_NOT_NAMED"]]},
  {"group": "catalogue", "name": "the plan follows an entry whose pattern does not hold",
   "plan": {"catalogue_entry": "E2", "outcome": "preferred"}, "summary": {"catalogue": {"decision": "policy", "entry": "E3", "matches": [{"id": "E3", "preferred": {"outcome": "reconcile"}}]}},
   "expect": [["catalogue", "block", "PATTERN_NOT_MATCHED"]], "outcome": "block"},
  {"group": "catalogue", "name": "the plan names an entry the catalogue does not have",
   "plan": {"catalogue_entry": "E999", "outcome": "preferred"}, "summary": {"catalogue": {"decision": "policy", "entry": "E2", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}]}},
   "expect": [["catalogue", "block", "ENTRY_UNKNOWN"]]},
  {"group": "catalogue", "name": "the plan follows the matched entry's preferred outcome",
   "plan": {"catalogue_entry": "E2", "outcome": "preferred"}, "summary": {"catalogue": {"decision": "policy", "entry": "E2", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}]}},
   "expect": [["catalogue", "pass", "ENTRY_MATCHED"]], "absent": [["catalogue", "OUTCOME_MISMATCH"]], "outcome": "pass"},
  {"group": "catalogue", "name": "the plan resends where the entry's outcome is to reconcile",
   "plan": {"catalogue_entry": "E3", "outcome": "preferred"}, "summary": {"catalogue": {"decision": "policy", "entry": "E3", "matches": [{"id": "E3", "preferred": {"outcome": "reconcile"}}]}},
   "expect": [["catalogue", "pass", "ENTRY_MATCHED"], ["catalogue", "block", "OUTCOME_MISMATCH"]], "outcome": "block"},
  {"group": "catalogue", "name": "an escalating entry allows asking for more evidence",
   "plan": {"disposition": "more_evidence", "action": null, "catalogue_entry": "E7", "outcome": "preferred"}, "summary": {"catalogue": {"decision": "board", "entry": "E7", "matches": [{"id": "E7", "preferred": {"outcome": "escalate"}}]}},
   "expect": [["catalogue", "pass", "ENTRY_MATCHED"]], "absent": [["catalogue", "OUTCOME_MISMATCH"]]},
  {"group": "catalogue", "name": "an alternative that holds always",
   "plan": {"catalogue_entry": "E5", "outcome": "alternative:1"}, "summary": {"catalogue": {"decision": "board", "entry": "E5", "matches": [{"id": "E5", "preferred": {"outcome": "resend_latest"}, "alternatives": [{"outcome": "resend", "when": "always"}]}], "facts": {"other_source": ""}}},
   "expect": [["catalogue", "pass", "OUTCOME_ALLOWED"]], "absent": [["catalogue", "OUTCOME_MISMATCH"]]},
  {"group": "catalogue", "name": "an alternative whose site flag holds",
   "plan": {"catalogue_entry": "E5", "outcome": "alternative:1"}, "profile": {"history_policy": "current"},
   "summary": {"catalogue": {"decision": "board", "entry": "E5", "matches": [{"id": "E5", "preferred": {"outcome": "resend_latest"}, "alternatives": [{"outcome": "resend", "when": "history_policy: current"}]}], "facts": {"other_source": ""}}},
   "expect": [["catalogue", "pass", "OUTCOME_ALLOWED"]]},
  {"group": "catalogue", "name": "an alternative for another source named authoritative, with no other source",
   "plan": {"catalogue_entry": "E9", "outcome": "alternative:1"},
   "summary": {"catalogue": {"decision": "board", "entry": "E9", "matches": [{"id": "E9", "preferred": {"outcome": "escalate"}, "alternatives": [{"outcome": "none", "when": "authoritative_source: other_source"}]}], "facts": {"other_source": ""}}},
   "expect": [["catalogue", "block", "OUTCOME_NOT_ALLOWED"]], "outcome": "block"},
  {"group": "catalogue", "name": "an alternative the entry does not have",
   "plan": {"catalogue_entry": "E5", "outcome": "alternative:3"}, "summary": {"catalogue": {"decision": "board", "entry": "E5", "matches": [{"id": "E5", "preferred": {"outcome": "resend_latest"}, "alternatives": [{"outcome": "resend", "when": "always"}]}]}},
   "expect": [["catalogue", "block", "OUTCOME_NOT_ALLOWED"]]},
  {"group": "catalogue", "name": "an allowed alternative the plan does not follow",
   "plan": {"catalogue_entry": "E5", "outcome": "alternative:1"}, "summary": {"catalogue": {"decision": "board", "entry": "E5", "matches": [{"id": "E5", "preferred": {"outcome": "resend_latest"}, "alternatives": [{"outcome": "reconcile", "when": "always"}]}]}},
   "expect": [["catalogue", "pass", "OUTCOME_ALLOWED"], ["catalogue", "block", "OUTCOME_MISMATCH"]]},

  {"group": "capability", "name": "a receiver without dry runs",
   "summary": {"route": {"dry_run": false}},
   "expect": [["capability", "block", "DRY_RUN_UNSUPPORTED"]], "outcome": "block"},
  {"group": "capability", "name": "a receiver without conditional writes or dry runs",
   "summary": {"route": {"conditional_writes": false, "dry_run": false}},
   "expect": [["capability", "block", "CONNECTOR_INCAPABLE"]], "absent": [["capability", "DRY_RUN_UNSUPPORTED"]], "outcome": "block"},
  {"group": "capability", "name": "reconciling needs no dry run either",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "summary": {"receipt_http_status": 200, "receipt": {"operation_key": "{key}"}, "route": {"dry_run": false}},
   "expect": [["capability", "pass", "NOT_APPLICABLE"]], "outcome": "pass"},

  {"group": "rehearsal", "name": "at the proposal nothing is rehearsed yet",
   "request": {"stage": "proposal"},
   "expect": [["rehearsal", "pass", "NOT_YET_REQUIRED"]], "outcome": "pass"},
  {"group": "rehearsal", "name": "the same resend at dispatch, with a valid approval bound to its dry run",
   "approval": {},
   "expect": [["rehearsal", "pass", "REHEARSED"], ["authorization", "pass", "APPROVAL_VALID"]], "outcome": "pass"},
  {"group": "rehearsal", "name": "no dry run bound to the approval",
   "approval": {}, "rehearsal": {"plan": "none"},
   "expect": [["rehearsal", "block", "DRY_RUN_MISSING"], ["authorization", "pass", "APPROVAL_VALID"]], "outcome": "block"},
  {"group": "rehearsal", "name": "a dry run of another plan",
   "approval": {}, "rehearsal": {"plan": "other"},
   "expect": [["rehearsal", "block", "DRY_RUN_MISSING"]], "outcome": "block"},
  {"group": "rehearsal", "name": "the dry run said it would not apply",
   "approval": {}, "rehearsal": {"would_apply": false, "reason": "invalid_transition"},
   "expect": [["rehearsal", "block", "DRY_RUN_FAILED"]], "outcome": "block"},
  {"group": "rehearsal", "name": "a dry run checked against another version",
   "approval": {}, "rehearsal": {"receiver_version": 2},
   "expect": [["rehearsal", "block", "DRY_RUN_STALE"], ["concurrency", "pass", "VERSION_MATCHES"]], "outcome": "block"},
  {"group": "rehearsal", "name": "a dry run from before a reset",
   "approval": {"epoch": 2}, "rehearsal": {"epoch": 1}, "request": {"receiver_epoch": 2},
   "expect": [["rehearsal", "block", "DRY_RUN_STALE"], ["authorization", "pass", "APPROVAL_VALID"]], "outcome": "block"},
  {"group": "rehearsal", "name": "a dry run of another payload",
   "approval": {}, "rehearsal": {"payload_digest": "sha256:other"},
   "expect": [["rehearsal", "block", "DRY_RUN_STALE"]], "outcome": "block"},
  {"group": "rehearsal", "name": "a reconcile needs no dry run",
   "plan": {"disposition": "reconcile", "action": {"type": "reconcile"}}, "summary": {"receipt_http_status": 200, "receipt": {"operation_key": "{key}"}}, "approval": {}, "rehearsal": {"plan": "none"},
   "expect": [["rehearsal", "pass", "NOT_APPLICABLE"]], "outcome": "pass"}
]
}

}
