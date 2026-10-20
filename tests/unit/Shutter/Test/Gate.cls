/// The deterministic gate (Shutter.Operation.Gate), check by check: every row of the table in XData Rows builds a case,
/// an evidence snapshot, a plan and, when the row has "approval", an approval, runs the gate's OnGateRequest in process
/// with no production running it, and asserts the checks the row names (check, result, reason code). The rows start
/// from a resend that passes every check and change only what the row is about: "case", "summary" and "plan" are merged
/// into the defaults ("{key}" stands for the case's operation key, null removes a field), "approval" makes an approval
/// for the plan (the request is then at dispatch, otherwise at proposal), "request" sets the gate request's fields (its
/// "stage" names another stage), "profile" changes the site profile for the row only. The cases
/// are named UT-GATE-..., never take a public case number, and are deleted with everything the gate recorded for them
/// after each test; the site profile is put back as it was.
Class Shutter.Test.Gate Extends %UnitTest.TestCase
{

Parameter EVENTTIME = "2026-10-19T09:00:00Z";

/// The case rows made by the current test, for the clean-up.
Property Made As %String [ MultiDimensional ];

/// The stored site profile's text before a row changed it, and whether there was a stored row at all.
Property SavedProfile As %String;

Property ProfileChanged As %Boolean [ InitialExpression = 0 ];

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

Method OnBeforeAllTests() As %Status
{
    // Rows a run that stopped half-way may have left.
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId %STARTSWITH 'UT-GATE-'")
    While rs.%Next() { Do ..Purge(rs.%Get("ID")) }
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

Method TestCatalogue()
{
    Do ..RunRows("catalogue")
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
Method TestEveryReasonCodeHasARow()
{
    Set asserted = ""
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set it2 = row.expect.%GetIterator()
        While it2.%GetNext(.j, .e) { Set asserted(e.%Get(2)) = "" }
    }
    Set codes = ""
    For method = "OnGateRequest", "OutcomeConsistency" {
        Set source = ..Source("Shutter.Operation.Gate", method)
        Set m = ##class(%Regex.Matcher).%New("""([A-Z][A-Z_]*[A-Z])""", source)
        While m.Locate() { Set codes(m.Group(1)) = "" }
    }
    Set m = ##class(%Regex.Matcher).%New("Quit ""([a-z_]+)""", ..Source("Shutter.Store.Approval", "InvalidReason"))
    While m.Locate() { Set codes("APPROVAL_" _ $ZCONVERT(m.Group(1), "U")) = "" }
    // The two reasons the gate itself gives an automatic release.
    Set codes("POLICY_REQUIRES_APPROVAL") = "", codes("APPROVAL_PLAN_ORIGIN") = ""
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
    // The summary the evidence collection would have made, with the row's changes.
    Set summary = ..Fill(..BaseSummary(), key)
    If row.%IsDefined("summary") Do ..Merge(summary, ..Fill(row.summary, key))
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
    // The approval, made as the workflow makes it and then changed as the row says.
    If row.%IsDefined("approval") {
        Set a = row.approval
        Set sc = ##class(Shutter.Store.Approval).Create(case, plan, snap, ##class(Shutter.Operation.Gate).#POLICYVERSION, "", plan.ExpectedVersion, ##class(Shutter.Util.Json).Str(a, "approver", "user:ut"), ##class(Shutter.Util.Json).Str(a, "decision", "approved"), "unit test", "", +##class(Shutter.Util.Json).Str(a, "valid_seconds", 600), .approval, ##class(Shutter.Util.Json).Str(a, "epoch"))
        Do $$$AssertStatusOK(sc, row.name _ ": the approval is saved")
        If a.%IsDefined("expected_version") Set approval.ExpectedVersion = a."expected_version"
        If ##class(Shutter.Util.Json).Bool(a, "revoked") Set approval.Revoked = 1
        If a.%IsDefined("plan_digest") Set approval.PlanDigest = a."plan_digest"
        If a.%IsDefined("snapshot_digest") Set approval.SnapshotDigest = a."snapshot_digest"
        If a.%IsDefined("material_digest") Set approval.MaterialDigest = a."material_digest"
        If a.%IsDefined("policy_version") Set approval.PolicyVersion = a."policy_version"
        If a.%IsDefined("site_profile_version") Set approval.SiteProfileVersion = a."site_profile_version"
        Do approval.%Save()
        Set req.ApprovalId = approval.%Id()
    }
    Set gate = ##class(Shutter.Operation.Gate).%New("Shutter Gate (unit test)")
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
    Set case.State = "investigating", case.Mode = "rules"
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Set sc = case.%Save()
    Do $$$AssertStatusOK(sc, "the case " _ case.CaseId _ " is saved")
    Set i%Made(case.%Id()) = ""
    Quit case
}

/// The evidence of a transfer that can be resent: the receiver knows the encounter (admitted, version 3, the case's
/// patient), holds no receipt, takes conditional writes and keeps receipts; the message parses; nothing later.
ClassMethod BaseSummary() As %DynamicObject
{
    Quit {
        "operation": {"operation_key": "{key}", "payload_digest": "sha256:ut"},
        "ward_state_http_status": 200,
        "ward_state": {"patient_id": "MRN-UT1", "patient_id_authority": "HOSP", "state": "admitted", "ward": "WARD-A", "version": 3, "epoch": 1, "history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z", "ward": "WARD-A", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}]},
        "receipt_http_status": 404,
        "validation": {"parsed": true},
        "route": {"capabilities_http_status": 200, "conditional_writes": true, "receipts": true},
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
    For table = "Shutter_Store.GateDecision", "Shutter_Store.Approval", "Shutter_Store.Plan", "Shutter_Store.CaseEvent" {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ table _ " WHERE ""Case"" = ?", id)
    }
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.SnapshotItem WHERE Snapshot IN (SELECT ID FROM Shutter_Store.Snapshot WHERE ""Case"" = ?)", id)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.Snapshot WHERE ""Case"" = ?", id)
    Do ##class(Shutter.Store.Case).%DeleteId(id)
    Kill ^Shutter.Counter("event", id), ^Shutter.Counter("plan", id), ^Shutter.Counter("snapshot", id)
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
/// [check, result, reason code]; "absent" lists [check, reason code] pairs the gate must not give.
XData Rows [ MimeType = application/json ]
{
[
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
   "expect": [["identity", "pass", "NEW_ENCOUNTER"], ["state_transition", "pass", "TRANSITION_ALLOWED"], ["concurrency", "pass", "VERSION_MATCHES"]], "outcome": "pass"},
  {"group": "identity", "name": "a transfer of an encounter the receiver does not know",
   "summary": {"ward_state_http_status": 404, "ward_state": null},
   "expect": [["identity", "block", "UNKNOWN_ENCOUNTER"], ["state_transition", "unknown", "RECEIVER_UNREADABLE"], ["concurrency", "unknown", "RECEIVER_UNREADABLE"]]},
  {"group": "identity", "name": "the receiver's state could not be read",
   "summary": {"ward_state_http_status": 503, "ward_state": null},
   "expect": [["identity", "unknown", "RECEIVER_UNREADABLE"], ["state_transition", "unknown", "RECEIVER_UNREADABLE"], ["concurrency", "unknown", "RECEIVER_UNREADABLE"]], "outcome": "unknown"},

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
  {"group": "ordering", "name": "a later transfer that failed too supersedes nothing",
   "summary": {"timeline": [{"later": true, "outcome": "failed", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z"}]},
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
   "expect": [["ordering", "block", "SUPERSEDED_BY_LATER_EVENT"]]},
  {"group": "ordering", "name": "superseded, with a doubtful event time",
   "plan": {"disposition": "superseded", "action": null}, "summary": {"catalogue": {"conditions": {"event_time": "clock_change"}}, "timeline": [{"later": true, "outcome": "applied", "event": "transfer", "event_time": "2026-10-19T10:00:00Z"}]},
   "expect": [["ordering", "block", "EVENT_TIME_IMPLAUSIBLE"]], "outcome": "block"},
  {"group": "ordering", "name": "superseded, with the later transfer in evidence",
   "plan": {"disposition": "superseded", "action": null}, "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z"}]},
   "expect": [["ordering", "pass", "SUPERSEDED_BY_LATER_EVENT"]], "outcome": "pass"},
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
   "expect": [["effect", "unknown", "RECEIPT_UNREADABLE"]], "outcome": "unknown"},

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
  {"group": "authorization", "name": "an automatic release of a board's plan",
   "plan": {"catalogue_entry": "E2", "outcome": "preferred", "created_by": "run:1"}, "approval": {"approver": "policy"},
   "profile": {"policy": {"2": {"single": "automatic"}}},
   "expect": [["authorization", "block", "APPROVAL_PLAN_ORIGIN"]]},
  {"group": "authorization", "name": "an automatic release of a plan that names no entry",
   "plan": {"created_by": "policy:"}, "approval": {"approver": "policy"},
   "profile": {"policy": {"2": {"single": "automatic"}}},
   "expect": [["authorization", "block", "APPROVAL_PLAN_ORIGIN"]]},

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
   "expect": [["catalogue", "pass", "OUTCOME_ALLOWED"], ["catalogue", "block", "OUTCOME_MISMATCH"]]}
]
}

}
