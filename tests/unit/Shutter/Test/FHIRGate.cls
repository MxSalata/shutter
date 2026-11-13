/// The FHIR gate (Shutter.Operation.FHIRGate), row by row over its Decide, with hand-made facts: no production runs
/// and nothing is read from a FHIR server. Every row of XData Rows starts from a ward move that passes every check
/// (the plan builder's measured seed: Encounter enc-1 at version "1", open on WARD-A, moved to WARD-B) and changes only
/// what the row is about:
/// <ul>
/// <li>"case" and "plan" are merged into the defaults ("{key}" stands for the case's operation key, null removes a
/// field);</li>
/// <li>"base" is merged into the evidence before the snapshot is sealed, and "view" and "set" (a path with dots to a
/// value) change the view the gate is given, so at dispatch they are what changed since the approval;</li>
/// <li>"stage" is "dispatch" for a row at the dispatch gate: the binding is then sealed and tied to an approval as the
/// workflow does it, and "binding" and "approval" change them in memory ("none" leaves one out);</li>
/// <li>"entry" is merged into the receiver's entry, "proof" sets properties of the conformance proof, "engine" is what
/// the engine read would have found, "further" and "pending" the feed's reads, "body" names another Encounter body
/// ("none" leaves none), "unresolved" and "fresh" the two flags; "none" leaves an object out.</li>
/// </ul>
/// "expect" lists [check, result, reason code], "absent" [check, reason code] pairs the gate must not give, "contains"
/// [check, reason code, text] and "outcome" the worst check. The cases are named UT-FHIRGATE-..., never take a public
/// case number, and are deleted with everything recorded for them after each test.
Class Shutter.Test.FHIRGate Extends %UnitTest.TestCase
{

Parameter EVENTTIME = "2026-11-07T10:15:00Z";

Parameter RECEIVER = "FHIR Ward Out";

/// The checks every decision carries at least once; plan_shape alone may be left out, when its code was already given.
Parameter CHECKS = "identity,conformance,intent,enablement,representation,state_transition,ordering,mapping,concurrency,earlier_write,capability,history,authorization,evidence,catalogue,rehearsal";

Parameter WRITEWORDS = "No dry run exists for this receiver. Substituted: a complete versioned read, a bounded change, If-Match on the version read, this case's own approval by a person, and a search of the returned history for the marked version, read back by id when the answer named it.";

Parameter NOWRITEWORDS = "No dry run exists for this receiver. This plan sends nothing.";

/// The case rows made by the current test, for the clean-up.
Property Made As %String [ MultiDimensional ];

/// The stored site profile's text before a test changed it, and whether there was a stored row at all.
Property SavedProfile As %String;

Property ProfileChanged As %Boolean [ InitialExpression = 0 ];

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

/// The conformance proof row a test saved, for the clean-up.
Property ProofId As %String;

Method OnBeforeAllTests() As %Status
{
    // Rows a run that stopped half-way may have left.
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId %STARTSWITH 'UT-FHIRGATE-'")
    While rs.%Next() { Do ..Purge(rs.%Get("ID")) }
    Quit $$$OK
}

Method OnAfterOneTest() As %Status
{
    Do ..RestoreProfile()
    If ..ProofId '= "" Do ##class(Shutter.Store.FHIRProof).%DeleteId(..ProofId) Set ..ProofId = ""
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ..Purge(id)
    }
    Kill i%Made
    Quit $$$OK
}

/// A row for every code of the table, pass and fail.
Method TestTheTable()
{
    Do ..RunRows("table")
}

/// Every reason code written in the gate's source is asserted by a row, so no row of the gate goes untested.
Method TestEveryReasonCodeHasARow()
{
    Do ..Asserted(.asserted)
    Do ..SourceCodes(.codes)
    Do $$$AssertTrue($DATA(codes("FHIR_NO_DRY_RUN_SUBSTITUTED")) && $DATA(codes("FHIR_ENGINE_HOLDS_SUSPENDED")) && $DATA(codes("EXACT_OPERATION")), "the codes were read from the source")
    Set code = "", missing = "", n = 0
    For {
        Set code = $ORDER(codes(code))
        Quit:code=""
        Set n = n + 1
        If '$DATA(asserted(code)) Set missing = missing _ $SELECT(missing = "": "", 1: ", ") _ code
    }
    Do $$$AssertEquals(missing, "", "each of the " _ n _ " reason codes in the source is asserted by a row" _ $SELECT(missing = "": "", 1: "; missing: " _ missing))
}

/// Every code a row gives as a block or an unknown has its words in the reason store, as does the rehearsal row's.
Method TestEveryEmittedCodeHasAReason()
{
    Do ..Asserted(.asserted)
    Set code = "", missing = "", n = 0
    For {
        Set code = $ORDER(asserted(code))
        Quit:code=""
        Continue:('$DATA(asserted(code, "block")) && '$DATA(asserted(code, "unknown")) && (code '= "FHIR_NO_DRY_RUN_SUBSTITUTED"))
        Set n = n + 1
        If '$ISOBJECT(##class(Shutter.Store.BlockReason).ByCode(code)) Set missing = missing _ $SELECT(missing = "": "", 1: ", ") _ code
    }
    Do $$$AssertTrue(n > 60, "the rows give " _ n _ " codes as a block or an unknown")
    Do $$$AssertEquals(missing, "", "each has a reason in the store" _ $SELECT(missing = "": "", 1: "; missing: " _ missing))
}

/// ETags are compared as strings: W/"3" is not "3", "10" is not "9", "1e2" is not "100", and an opaque one matches
/// only itself.
Method TestEtagsCompareAsStrings()
{
    Do ..RunRows("etags")
}

/// No source header, an item that is no stock HL7 TCP operation and a subclass of one are each unknown, where the
/// gate of an ADT case passes or reads on.
Method TestScopeNoBaseAndNoSourceHeaderAreUnknown()
{
    Do ..RunRows("scope")
}

/// A header the engine delivered and a header it holds suspended each block, where the gate of an ADT case passes.
Method TestADeliveredOrSuspendedHeaderBlocks()
{
    Do ..RunRows("engine")
    // The row as the gate gives it carries the four keys of a check and nothing of the engine's own.
    Set row = ##class(Shutter.Operation.FHIRGate).EngineRow(..Engine({"headers": [{"headerId": "17", "custody": "engine", "status": "Delivered", "itemStatus": "Retry", "completedAt": "", "why": "", "attempts": ""}]}))
    Do $$$AssertEquals(row."reason_code", "ENGINE_STILL_TRYING", "a header in the engine's hands is the engine check's own block")
    Do $$$AssertEquals(row.%GetTypeOf("engine"), "unassigned", "and carries nothing for Settle, which this gate never calls")
}

Method TestNoProofOtherSoftwareOrAFailedMeasurementBlocks()
{
    Do ..RunRows("proof")
}

/// The rehearsal row is on every decision, once, as a pass, with the words for a plan that writes or for one that
/// does not: a write, an escalate plan, both stages.
Method TestTheRehearsalRowIsOnEveryDecision()
{
    Set n = 0
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Continue:(row.group '= "rehearsal")
        Set n = n + 1
        Set run = ..Run(row)
        Set count = 0, detail = "", result = ""
        Set it2 = run.checks.%GetIterator()
        While it2.%GetNext(.j, .c) {
            Continue:(c.check '= "rehearsal")
            Set count = count + 1, detail = c.detail, result = c.result _ " " _ c."reason_code"
        }
        Do $$$AssertEquals(count, 1, row.name _ ": one rehearsal row")
        Do $$$AssertEquals(result, "pass FHIR_NO_DRY_RUN_SUBSTITUTED", row.name _ ": a pass that says no dry run exists")
        Do $$$AssertEquals(detail, $SELECT(run.plan.IsWrite(): ..#WRITEWORDS, 1: ..#NOWRITEWORDS), row.name _ ": with the words for " _ $SELECT(run.plan.IsWrite(): "a write", 1: "a plan that sends nothing"))
        Do $$$AssertEquals(run.checks.%Get(run.checks.%Size() - 1).check, "rehearsal", row.name _ ": it is the last row")
        Do ..OnAfterOneTest()
    }
    Do $$$AssertEquals(n, 4, "a write and an escalate plan, at both stages")
    // And on every other row of the table, whatever else it says.
    Set iter = ..Rows().%GetIterator(), all = 0, with = 0
    While iter.%GetNext(.i, .row) {
        Continue:(row.group '= "table")
        Set run = ..Run(row), all = all + 1
        If ..Found(run.checks, "rehearsal", "FHIR_NO_DRY_RUN_SUBSTITUTED") = "pass" Set with = with + 1
        Do ..OnAfterOneTest()
    }
    Do $$$AssertEquals(with, all, "each of the " _ all _ " rows of the table carries it")
}

Method TestAnEarlierUnresolvedWriteIsUnknown()
{
    Do ..RunRows("earlier")
}

Method TestFailureKindAndBed()
{
    Do ..RunRows("kind")
}

Method TestAnApprovalThatIsNotPersonal()
{
    Do ..RunRows("personal")
}

Method TestAnExpiredApprovalAtDispatch()
{
    Do ..RunRows("expired")
}

/// The rows this gate copies from the gate of an ADT case give the same answers: for the rows of Shutter.Test.Gate's
/// own table about conformance, the catalogue and the ordering, the same case, summary and plan go through both gates
/// and give equal [check, result, reason code] for conformance, the catalogue and, for a plan that writes, the
/// further messages, the pending messages and the later events. The engine row is left out, since it differs by design.
Method TestEquivalentDecisionsWithMainsGate()
{
    Set main = "Shutter.Test.Gate", n = 0, compared = 0
    Set iter = $CLASSMETHOD(main, "Rows").%GetIterator()
    While iter.%GetNext(.i, .row) {
        Continue:'$LISTFIND($LISTBUILD("conformance", "catalogue", "ordering"), row.group)
        // Rows that need what this test does not build: an approval, an incident, the index, another profile.
        Set skip = 0
        For key = "approval", "engine", "index", "incident", "other_case", "request", "snapshot", "profile" { If row.%IsDefined(key) Set skip = 1 }
        Continue:skip
        Set n = n + 1
        Set case = ..NewCase($SELECT(row.%IsDefined("case"): row.case, 1: {}), 0)
        Set key = case.OperationKey
        Set summary = $CLASSMETHOD(main, "Fill", $CLASSMETHOD(main, "BaseSummary"), key)
        If row.%IsDefined("summary") Do ..Merge(summary, $CLASSMETHOD(main, "Fill", row.summary, key))
        If row.%IsDefined("release") {
            Set digest = $SELECT(row.release = "the rows": ##class(Shutter.Util.FurtherMessages).RowsDigest(summary.%Get("further_messages")), 1: row.release)
            Set case.FurtherReleaseJSON = {"digest": (digest), "by": "user:ut", "at": "2026-10-19T10:00:00Z", "reason": "unit test"}.%ToJSON()
            Do $$$AssertStatusOK(case.%Save(), row.name _ ": the release is recorded")
        }
        Set snap = ##class(Shutter.Store.Snapshot).Begin(case, 300)
        Do $$$AssertStatusOK(snap.Seal(summary), row.name _ ": the snapshot is sealed")
        Do $$$AssertStatusOK(case.SetSnapshot(snap), row.name _ ": the snapshot is the case's current one")
        Set planObj = $CLASSMETHOD(main, "Fill", {"disposition": "resend", "action": {"type": "resend", "operation_key": "{key}", "expected_version": 3, "payload_digest": "sha256:ut"}, "summary": "Resend the transfer"}, key)
        If row.%IsDefined("plan") Do ..Merge(planObj, $CLASSMETHOD(main, "Fill", row.plan, key))
        Set createdBy = ##class(Shutter.Util.Json).Str(planObj, "created_by", "rules")
        Do planObj.%Remove("created_by")
        Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, snap, planObj, createdBy, .plan), row.name _ ": the plan is saved")

        // The gate of an ADT case, in process.
        Set req = ##class(Shutter.Msg.GateRequest).%New()
        Set req.CaseId = case.CaseId, req.PlanId = plan.%Id(), req.Stage = "proposal"
        Set req.Receiver = case.Receiver, req.ChainKind = "single"
        Set sc = ##class(Shutter.Operation.Gate).%New("Shutter Gate (unit test)").OnGateRequest(req, .resp)
        Do $$$AssertStatusOK(sc, row.name _ ": the gate ran")
        Set theirs = ##class(%DynamicArray).%FromJSON($SELECT(resp.ChecksJSON = "": "[]", 1: resp.ChecksJSON))

        // The FHIR gate's rows from the same summary.
        Kill facts
        Set view = snap.SummaryObject()
        Set facts("view") = view, facts("further") = view.%Get("further_messages"), facts("pending") = view.%Get("pending_messages")
        Set facts("chain_kind") = "single", facts("fresh") = 1
        Set ours = ##class(Shutter.Operation.FHIRGate).Decide("proposal", case, plan, .facts)

        Set want = ..Comparable(theirs, plan.IsWrite(), .seen), got = ..Comparable(ours, plan.IsWrite())
        Set compared = compared + $LENGTH(want, ";")
        Do $$$AssertEquals(got, want, row.name _ ": the copied rows are equal")
        Do ..OnAfterOneTest()
    }
    Do $$$AssertTrue(n >= 40, n _ " rows of the gate's table went through both gates")
    Do $$$AssertTrue(compared >= 80, compared _ " rows were compared")
    Set missing = ""
    For code = "UNMAPPABLE", "SCHEMA_UNKNOWN", "PARSE_FAILED", "NEW_PATTERN", "MATCHER_ERROR", "ENTRY_NOT_NAMED_WRITE", "PATTERN_NOT_MATCHED", "ENTRY_UNKNOWN", "OUTCOME_MISMATCH", "OUTCOME_NOT_ALLOWED", "FURTHER_MOVEMENT", "PATIENT_UNREADABLE", "FURTHER_NOT_READ", "NEWER_MESSAGE_PENDING", "SUPERSEDED_BY_LATER_EVENT", "NO_LATER_EVENT" {
        If '$DATA(seen(code)) Set missing = missing _ " " _ code
    }
    Do $$$AssertEquals(missing, "", "among them every kind of copied row")
}

/// The handler answers and stores as the gate does: the worst check, the summary with the FHIR policy version and
/// the stage, the decision, a note on the case, and checks of four keys each. The case names no visit number, so its
/// evidence has no fhir view and no sealed read is looked for.
Method TestTheHandlerAnswersAndStoresAsTheGateDoes()
{
    Set policy = ##class(Shutter.FHIR.Profile).#POLICYVERSION
    Set case = ..NewCase({"encounter_id": "-"})
    Set view = ..Fill(..BaseView(), case.OperationKey)
    Do view.%Remove("fhir")
    Set snap = ##class(Shutter.Store.Snapshot).Begin(case, 300)
    Do $$$AssertStatusOK(snap.Seal(view), "the snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snap), "the snapshot is the case's current one")
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, snap, ..Fill(..BasePlan(), case.OperationKey), "rules", .plan), "the plan is saved")
    Set req = ##class(Shutter.Msg.FHIRGateRequest).%New()
    Set req.CaseId = case.CaseId, req.PlanId = plan.%Id(), req.Stage = "proposal", req.ChainKind = "single"
    Set gate = ##class(Shutter.Operation.FHIRGate).%New("Shutter FHIR Gate (unit test)")
    Do $$$AssertStatusOK(gate.OnGateRequest(req, .resp), "the gate ran")
    Do $$$AssertEquals(resp.Error, "", "with no error")
    Do $$$AssertEquals(resp.Outcome, "block", "a message with no visit number is blocked")
    Do $$$AssertEquals(resp.PolicyVersion, policy, "under the FHIR policy version")
    Do $$$AssertEquals($PIECE(resp.Summary, ",", 1), "Blocked: identity FHIR_ENCOUNTER_NOT_FOUND", "the summary names the failing checks, the first first (" _ resp.Summary _ ")")
    Do $$$AssertTrue(resp.Summary [ ("(policy " _ policy _ ", stage proposal)"), "and ends with the policy and the stage")
    Do $$$AssertNotTrue(resp.Summary [ "(FHIR_", "with no code in brackets, which a stop's own text carries")
    Set checks = ##class(%DynamicArray).%FromJSON(resp.ChecksJSON)
    Do $$$AssertEquals(..Found(checks, "identity", "FHIR_ENCOUNTER_NOT_FOUND"), "block", "the identity check stops it")
    Do $$$AssertEquals(..Found(checks, "rehearsal", "FHIR_NO_DRY_RUN_SUBSTITUTED"), "pass", "and the rehearsal row is there")
    Do $$$AssertEquals(..Shape(checks), "", "every check has its four keys and one of three results")
    Set decision = ##class(Shutter.Store.GateDecision).%OpenId(resp.DecisionId)
    Do $$$AssertTrue($ISOBJECT(decision), "the decision is stored")
    If $ISOBJECT(decision) {
        Do $$$AssertEquals(decision.Stage _ " " _ decision.Outcome _ " " _ decision.PolicyVersion, "proposal block " _ policy, "with its stage, outcome and policy version")
        Do $$$AssertEquals(decision.ChecksJSON, resp.ChecksJSON, "and the checks as answered")
        Do $$$AssertEquals(decision.PlanGetObjectId(), plan.%Id(), "for this plan")
    }
    Set noted = 0
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Text FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", case.%Id())
    While rs.%Next() { If $EXTRACT(rs.%Get("Text"), 1, 22) = "FHIR gate (proposal): " Set noted = 1 }
    Do $$$AssertTrue(noted, "the case is noted ""FHIR gate (proposal): ...""")
}

/// Both stages through the handler and its reads, for a receiver the site profile describes, with a conformance proof
/// on file: the sealed read and the read made just before the write reach the rows through Shutter.FHIR.Reader. On an
/// instance where that class is not compiled the reads fail, and the gate must then decide nothing.
Method TestBothStagesThroughTheHandlerAndItsReads()
{
    Set policy = ##class(Shutter.FHIR.Profile).#POLICYVERSION, receiver = "UT FHIR Gate Out"
    Set entry = ..Entry()
    Set entry.name = receiver
    Do ..AddReceiver(entry)
    Set proof = ..Proof()
    Set proof.Receiver = receiver
    Do $$$AssertStatusOK(proof.%Save(), "the conformance proof is on file")
    Set ..ProofId = proof.%Id()
    Set case = ..NewCase({"receiver": (receiver)})
    Set body = ..Seed(), view = ..Fill(..BaseView(), case.OperationKey)
    Set snap = ##class(Shutter.Store.Snapshot).Begin(case, 300)
    Do $$$AssertStatusOK(snap.Seal(view), "the snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snap), "the snapshot is the case's current one")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRSealedRead).Keep(case, snap.%Id(), body), "the sealed read is kept")
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, snap, ..Fill(..BasePlan(), case.OperationKey), "rules", .plan), "the plan is saved")
    Set gate = ##class(Shutter.Operation.FHIRGate).%New("Shutter FHIR Gate (unit test)")
    Set req = ##class(Shutter.Msg.FHIRGateRequest).%New()
    Set req.CaseId = case.CaseId, req.PlanId = plan.%Id(), req.Stage = "proposal", req.ChainKind = "single"
    Do $$$AssertStatusOK(gate.OnGateRequest(req, .resp), "the proposal gate ran")

    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.FHIR.Reader") {
        // No reader on this instance: the sealed read cannot be fetched, so nothing is decided.
        Do $$$AssertEquals(resp.Outcome, "unknown", "without the reader the outcome is unknown")
        Do $$$AssertTrue(resp.Error [ "Shutter.FHIR.Reader", "the error names what is missing (" _ resp.Error _ ")")
        Do $$$AssertEquals(resp.DecisionId _ resp.ChecksJSON, "", "and nothing is decided")
        Quit
    }

    // The proposal: every check passes but the engine's, since this case has no source header to read the engine by.
    Do $$$AssertEquals(resp.Error, "", "the proposal gate reported no error")
    Do $$$AssertEquals(resp.Summary, "Unknown: ordering FHIR_ENGINE_NOT_IN_SCOPE (policy " _ policy _ ", stage proposal)", "only the engine's row stops a case with no source header")
    Set checks = ##class(%DynamicArray).%FromJSON(resp.ChecksJSON)
    Do $$$AssertEquals(..Found(checks, "plan_shape", "FHIR_PLAN_BOUNDED"), "pass", "the update is built from the snapshot's sealed read (" _ ..Codes(checks, "plan_shape") _ ")")
    Do $$$AssertEquals(..Found(checks, "enablement", "FHIR_RECOVERY_ENABLED"), "pass", "the entry is read from the site profile")
    Do $$$AssertEquals(..Found(checks, "capability", "FHIR_CAPABLE"), "pass", "and the proof from its store (" _ ..Codes(checks, "capability") _ ")")

    // The dispatch: the binding sealed and tied to a person's approval, then the read made just before the write.
    Do $$$AssertEquals(##class(Shutter.FHIR.Proposal).Prepare(case, plan.Digest, view.fhir, body, entry, .prepared), "", "the update is prepared for the seal")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan, prepared, .binding), "the binding is sealed")
    Do $$$AssertStatusOK(##class(Shutter.Store.Approval).Create(case, plan, snap, policy, "", "", "user:ut", "approved", "unit test", "", 600, .approval), "the approval is saved")
    Do $$$AssertStatusOK(binding.Bind(approval.%Id()), "and the binding is tied to it")
    For age = 0, 600 {
        Set read = ##class(Shutter.Msg.FHIRReadResult).%New()
        Set read.PartsJSON = ..Parts(##class(Shutter.Util.Time).FromNow(-age)).%ToJSON()
        Do $$$AssertStatusOK(read.%Save(), "the read before the write is saved")
        Set req = ##class(Shutter.Msg.FHIRGateRequest).%New()
        Set req.CaseId = case.CaseId, req.PlanId = plan.%Id(), req.Stage = "dispatch", req.ChainKind = "single"
        Set req.ApprovalId = approval.%Id(), req.ReadId = read.%Id()
        Do $$$AssertStatusOK(gate.OnGateRequest(req, .resp), "the dispatch gate ran")
        Do ##class(Shutter.Msg.FHIRReadResult).%DeleteId(read.%Id())
        Do $$$AssertEquals(resp.Error, "", "the dispatch gate reported no error")
        Set checks = ##class(%DynamicArray).%FromJSON($SELECT(resp.ChecksJSON = "": "[]", 1: resp.ChecksJSON))
        Do $$$AssertEquals(..Found(checks, "evidence", $SELECT(age: "STALE_EVIDENCE", 1: "FRESH")), $SELECT(age: "unknown", 1: "pass"), "a read " _ age _ " seconds old is " _ $SELECT(age: "too old", 1: "fresh") _ " (" _ ..Codes(checks, "evidence") _ ")")
        Do $$$AssertEquals(..Found(checks, "identity", "FHIR_IDENTITY_MATCHES"), "pass", "the read's Encounter and Patient are the message's (" _ ..Codes(checks, "identity") _ ")")
        Do $$$AssertEquals(..Found(checks, "concurrency", "FHIR_VERSION_MATCHES"), "pass", "at the versions the binding sealed (" _ ..Codes(checks, "concurrency") _ ")")
        Do $$$AssertEquals(..Found(checks, "authorization", "APPROVAL_VALID"), "pass", "on the person's approval (" _ ..Codes(checks, "authorization") _ ")")
        Do $$$AssertEquals(..Found(checks, "history", "FHIR_HISTORY_READ"), "pass", "with the history read whole (" _ ..Codes(checks, "history") _ ")")
        Do $$$AssertEquals(..Found(checks, "capability", "FHIR_CAPABLE"), "pass", "and the statement the read itself brought (" _ ..Codes(checks, "capability") _ ")")
        Set decision = ##class(Shutter.Store.GateDecision).%OpenId(resp.DecisionId)
        Do $$$AssertTrue($ISOBJECT(decision) && (decision.Stage = "dispatch") && (decision.PolicyVersion = policy), "the dispatch decision is stored")
    }
}

/// What is missing decides nothing: an unknown case, an unknown plan, another case's plan and a case with no snapshot
/// each answer unknown with an error, and no decision is stored.
Method TestMissingInputsDecideNothing()
{
    Set gate = ##class(Shutter.Operation.FHIRGate).%New("Shutter FHIR Gate (unit test)")
    Set case = ..NewCase({}), other = ..NewCase({})
    Set snap = ##class(Shutter.Store.Snapshot).Begin(other, 300)
    Do $$$AssertStatusOK(snap.Seal(..Fill(..BaseView(), other.OperationKey)), "the other case's snapshot is sealed")
    Do $$$AssertStatusOK(other.SetSnapshot(snap), "and is its current one")
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(other, snap, ..Fill(..BasePlan(), other.OperationKey), "rules", .plan), "the other case's plan is saved")
    For which = "case", "plan", "owner", "snapshot" {
        Set req = ##class(Shutter.Msg.FHIRGateRequest).%New()
        Set req.Stage = "proposal", req.CaseId = $CASE(which, "case": "UT-FHIRGATE-NOBODY", "owner": case.CaseId, "snapshot": case.CaseId, : other.CaseId)
        Set req.PlanId = $CASE(which, "plan": "999999999", : plan.%Id())
        // A case with no snapshot is asked about its own plan, made without one.
        If which = "snapshot" {
            Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, "", ..Fill(..BasePlan(), case.OperationKey), "rules", .own), "a plan with no snapshot is saved")
            Set req.PlanId = own.%Id()
        }
        Do $$$AssertStatusOK(gate.OnGateRequest(req, .resp), which _ ": the gate ran")
        Do $$$AssertEquals(resp.Outcome, "unknown", which _ ": the outcome is unknown")
        Do $$$AssertTrue(resp.Error '= "", which _ ": with an error (" _ resp.Error _ ")")
        Do $$$AssertEquals(resp.DecisionId _ resp.ChecksJSON, "", which _ ": and nothing decided")
    }
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) AS N FROM Shutter_Store.GateDecision WHERE ""Case"" IN (?, ?)", case.%Id(), other.%Id())
    Do rs.%Next()
    Do $$$AssertEquals(rs.%Get("N"), 0, "no decision is stored")
}

/// Runs the rows of a group and asserts what each expects.
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
        If row.%IsDefined("outcome") Do $$$AssertEquals(run.outcome, row.outcome, row.name _ ": the outcome (" _ run.failing _ ")")
        Set shape = ..Shape(checks)
        Do $$$AssertEquals(shape, "", row.name _ ": every check has its four keys, and every check is there" _ $SELECT(shape = "": "", 1: " (" _ shape _ ")"))
        // Each row's records go before the next row.
        Do ..OnAfterOneTest()
    }
    Do $$$AssertTrue(n > 0, "the table has rows for " _ group)
}

/// Builds what a row describes and gives it to Decide. Returns {checks, outcome, failing, plan}.
Method Run(row As %DynamicObject) As %DynamicObject
{
    Set json = "Shutter.Util.Json"
    Set case = ..NewCase($SELECT(row.%IsDefined("case"): row.case, 1: {}))
    Set key = case.OperationKey
    Set stage = $CLASSMETHOD(json, "Str", row, "stage", "proposal")
    Set entry = ..Entry(), body = ..Seed()

    // The evidence as it was sealed, and the Encounter body it rests on.
    Set base = ..Fill(..BaseView(), key)
    If row.%IsDefined("base") Do ..Merge(base, ..Fill(row.base, key))
    Set snap = ##class(Shutter.Store.Snapshot).Begin(case, 300)
    Do $$$AssertStatusOK(snap.Seal(base), row.name _ ": the snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snap), row.name _ ": the snapshot is the case's current one")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRSealedRead).Keep(case, snap.%Id(), body), row.name _ ": the sealed read is kept")

    Set planObj = ..Fill(..BasePlan(), key)
    If row.%IsDefined("plan") Do ..Merge(planObj, ..Fill(row.plan, key))
    Set createdBy = $CLASSMETHOD(json, "Str", planObj, "created_by", "rules")
    Do planObj.%Remove("created_by")
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, snap, planObj, createdBy, .plan), row.name _ ": the plan is saved")

    // At dispatch: the approval as the workflow makes one for a FHIR case (no rehearsal, no expected version), and the
    // binding sealed from the builder's own output and tied to that approval.
    Set approval = "", binding = ""
    If stage = "dispatch" {
        Set a = $SELECT(row.%GetTypeOf("approval") = "object": row.approval, 1: {})
        If $CLASSMETHOD(json, "Str", row, "approval") '= "none" {
            Set sc = ##class(Shutter.Store.Approval).Create(case, plan, snap, $CLASSMETHOD(json, "Str", a, "policy_version", ##class(Shutter.FHIR.Profile).#POLICYVERSION), "", "", $CLASSMETHOD(json, "Str", a, "approver", "user:ut"), $CLASSMETHOD(json, "Str", a, "decision", "approved"), "unit test", "", +$CLASSMETHOD(json, "Str", a, "valid_seconds", 600), .approval)
            Do $$$AssertStatusOK(sc, row.name _ ": the approval is saved")
            If $CLASSMETHOD(json, "Bool", a, "revoked") Set approval.Revoked = 1
            If a.%IsDefined("plan_digest") Set approval.PlanDigest = a."plan_digest"
            If a.%IsDefined("incident_plan_digest") Set approval.IncidentPlanDigest = a."incident_plan_digest"
        }
        If plan.IsWrite() && ($CLASSMETHOD(json, "Str", row, "binding") '= "none") {
            Set code = ##class(Shutter.FHIR.Proposal).Prepare(case, plan.Digest, base.fhir, body, entry, .prepared)
            Do $$$AssertEquals(code, "", row.name _ ": the update is prepared for the seal")
            Do $$$AssertStatusOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan, prepared, .binding), row.name _ ": the binding is sealed")
            If $ISOBJECT(approval) Do $$$AssertStatusOK(binding.Bind(approval.%Id()), row.name _ ": and tied to the approval")
            Set b = $SELECT(row.%GetTypeOf("binding") = "object": row.binding, 1: {})
            If b.%IsDefined("expected_etag") Set binding.ExpectedEtag = b."expected_etag"
            If b.%IsDefined("approved_body_digest") Set binding.ApprovedBodyDigest = b."approved_body_digest"
            If b.%IsDefined("approval_id") Set binding.ApprovalId = b."approval_id"
        }
    }

    // The facts: the view with the row's changes, and what the other reads would have found.
    Set view = ##class(%DynamicObject).%FromJSON(base.%ToJSON())
    If row.%IsDefined("view") Do ..Merge(view, ..Fill(row.view, key))
    If row.%IsDefined("set") {
        Set it = row.set.%GetIterator()
        While it.%GetNext(.path, .value) { Do ..Put(view, path, row.set, path) }
    }
    If row.%GetTypeOf("entry") = "object" Do ..Merge(entry, row.entry)
    Set proof = ..Proof()
    If row.%GetTypeOf("proof") = "object" {
        Set it = row.proof.%GetIterator()
        While it.%GetNext(.name, .value) { Set $PROPERTY(proof, name) = value }
    }
    Kill facts
    Set facts("view") = view
    Set facts("body") = $CASE($CLASSMETHOD(json, "Str", row, "body"), "": body, "none": "", : ..Body(row.body))
    Set facts("entry") = $SELECT($CLASSMETHOD(json, "Str", row, "entry") = "none": "", 1: entry)
    Set facts("binding") = binding, facts("approval") = approval
    Set facts("proof") = $SELECT($CLASSMETHOD(json, "Str", row, "proof") = "none": "", 1: proof)
    Set facts("engine") = $SELECT(row.%GetTypeOf("engine") = "object": ..Engine(row.engine), $CLASSMETHOD(json, "Str", row, "engine") = "none": "", 1: ..Engine({}))
    Set facts("further") = $SELECT(row.%IsDefined("further"): row.further, 1: {"identifier": "read", "stops": [], "shows": [], "unread": ""})
    Set facts("pending") = $SELECT(row.%IsDefined("pending"): row.pending, 1: [])
    Set facts("unresolved") = $CLASSMETHOD(json, "Bool", row, "unresolved")
    Set facts("fresh") = $CLASSMETHOD(json, "Bool", row, "fresh", 1)
    Set facts("chain_kind") = "single"
    If row.%IsDefined("release") {
        Set case.FurtherReleaseJSON = {"digest": (##class(Shutter.Util.FurtherMessages).RowsDigest(facts("further"))), "by": "user:ut", "at": "2026-11-07T11:00:00Z", "reason": "unit test"}.%ToJSON()
    }

    Set checks = ##class(Shutter.Operation.FHIRGate).Decide(stage, case, plan, .facts)
    Set outcome = "pass", failing = ""
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) {
        If c.result = "block" Set outcome = "block"
        If (c.result = "unknown") && (outcome '= "block") Set outcome = "unknown"
        If c.result '= "pass" Set failing = failing _ $SELECT(failing = "": "", 1: ", ") _ c.check _ " " _ c.result _ " " _ c."reason_code"
    }
    Quit {"checks": (checks), "outcome": (outcome), "failing": (failing), "plan": (plan)}
}

/// A case as the feed opens one, with the row's changes. For this gate's own rows (<var>fhir</var>) it is a ward move
/// of visit V1001 to the FHIR receiver at the seed's event time; otherwise it is the case Shutter.Test.Gate makes.
Method NewCase(spec As %DynamicObject, fhir As %Boolean = 1) As Shutter.Store.Case
{
    Set json = "Shutter.Util.Json"
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-FHIRGATE-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.FHIRGate)
    Set case.Event = $CLASSMETHOD(json, "Str", spec, "event", "transfer")
    Set case.FailureKind = $CLASSMETHOD(json, "Str", spec, "failure_kind", "delivery_failed")
    Set case.FailureText = $CLASSMETHOD(json, "Str", spec, "failure_text", "Delivery unavailable (ward_unavailable), HTTP 503")
    Set case.EncounterId = $CLASSMETHOD(json, "Str", spec, "encounter_id", $SELECT(fhir: "V1001", 1: "ENC-UT1"))
    Set case.PatientId = $CLASSMETHOD(json, "Str", spec, "patient_id", "MRN-UT1")
    Set case.PatientIdAuthority = $CLASSMETHOD(json, "Str", spec, "patient_id_authority", "HOSP")
    Set case.EventTime = $CLASSMETHOD(json, "Str", spec, "event_time", $SELECT(fhir: ..#EVENTTIME, 1: $PARAMETER("Shutter.Test.Gate", "EVENTTIME")))
    Set case.SourceSystem = "PAS", case.Ward = $SELECT(case.Event = "transfer": "WARD-B", 1: ""), case.Bed = $CLASSMETHOD(json, "Str", spec, "bed")
    Set case.Receiver = $CLASSMETHOD(json, "Str", spec, "receiver", $SELECT(fhir: ..#RECEIVER, 1: $PARAMETER("Shutter.Production", "RECEIVER")))
    Set case.OperationKey = "PAS^HOSP^" _ case.PatientId _ "^" _ case.EncounterId _ "^" _ case.Event _ "^" _ case.EventTime
    Set case.State = "investigating", case.Mode = $CLASSMETHOD(json, "Str", spec, "mode", "rules")
    Set case.Scenario = $CLASSMETHOD(json, "Str", spec, "scenario"), case.ScenarioRecorded = $CLASSMETHOD(json, "Bool", spec, "scenario_recorded")
    Set case.SourceNamespace = $CLASSMETHOD(json, "Str", spec, "source_namespace"), case.OriginHeaderId = $CLASSMETHOD(json, "Str", spec, "origin_header_id")
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Do $$$AssertStatusOK(case.%Save(), "the case " _ case.CaseId _ " is saved")
    Set i%Made(case.%Id()) = ""
    Quit case
}

/// The evidence of a ward move that can be written: one Encounter under the visit number, in progress and open on
/// WARD-A since before the event, its Patient and both mapped Locations read, the history read whole with the version
/// read at its head, a server that states versioned updates and the four interactions, the message parsed, nothing
/// later. The Encounter's digest is the seed's.
ClassMethod BaseView() As %DynamicObject
{
    Set view = ##class(%DynamicObject).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||View").Data)
    Set view.fhir.encounter."body_digest" = ##class(Shutter.FHIR.Plan).BodyDigest(..Seed())
    Quit view
}

/// The plan the workflow makes for a FHIR case: a resend of the case's own operation, with no expected version.
ClassMethod BasePlan() As %DynamicObject
{
    Quit {"disposition": "resend", "action": {"type": "resend", "operation_key": "{key}", "payload_digest": "sha256:ut"}, "summary": "One update of the Encounter's location with If-Match on the version read"}
}

/// The receiver's entry of the site profile, as the demo has it.
ClassMethod Entry() As %DynamicObject
{
    Quit {"name": "FHIR Ward Out", "category": "current_state", "tier": 3, "cancels": false, "merges": false,
        "fhir": {"base": "/fhir-facade/r4", "recovery_enabled": true,
            "encounter_identifier": {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49"},
            "patient_identifier": {"system": "urn:shutter:demo:mrn", "hl7_authority": "HOSP"},
            "marker": {"system": "urn:shutter:recovery"},
            "location_map": [
                {"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}},
                {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}
}

/// A conformance proof for the software the base view's statement names, with its three measurements passed. Not saved.
ClassMethod Proof() As Shutter.Store.FHIRProof
{
    Set p = ##class(Shutter.Store.FHIRProof).%New()
    Set p.Receiver = ..#RECEIVER, p.SoftwareName = "Shutter test FHIR server", p.SoftwareVersion = "facade-v1"
    Set p.IfMatchStaleRefused = 1, p.IfMatchUnknownIdRefused = 1, p.TagsKept = 1
    Quit p
}

/// What the engine read would have found: a stock HL7 TCP operation whose one header settled with every attempt
/// failing before a connection opened, with the row's changes over it.
ClassMethod Engine(patch As %DynamicObject) As %DynamicObject
{
    Set engine = {"scope": "yes", "why": "", "namespace": "HOSPITAL", "item": "FHIR Ward Out", "receiver": "FHIR Ward Out", "ackRoute": false, "deliveryHeader": "17", "headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "never_opened"}], "effectiveAck": "", "ackReason": ""}
    Do ..Merge(engine, patch)
    Quit engine
}

/// The Encounter as it was read: the plan builder's measured seed.
ClassMethod Seed() As %String
{
    Quit ##class(Shutter.Test.FHIRPlan).Text("Seed")
}

/// Another Encounter body by name: "two_open" is the seed with a second open location.
ClassMethod Body(name As %String) As %String
{
    Set enc = ##class(%DynamicObject).%FromJSON(..Seed())
    If name = "two_open" Do enc.location.%Push({"location": {"reference": "Location/ward-b"}, "status": "active", "period": {"start": "2026-11-07T09:30:00Z"}})
    Quit enc.%ToJSON()
}

/// The parts of a read made just before the write, as the FHIR Receiver answers them (CONTRACTS 20): the statement,
/// the seed Encounter, its Patient, both mapped Locations and a history of one version, observed at that time.
ClassMethod Parts(observedAt As %String) As %DynamicObject
{
    Set seed = ..Seed()
    Set parts = {"observed_at": (observedAt), "base": "/fhir-facade/r4"}
    Set parts.metadata = {"http_status": 200, "raw_status": 200, "content_type": "application/fhir+json", "error": "",
        "statement": {"software": {"name": "Shutter test FHIR server", "version": "facade-v1"}, "fhir_version": "4.0.1", "versioning": "versioned-update",
            "interactions": ["read", "vread", "update", "history-instance"], "read_history": true, "update_create": true}}
    Set parts.encounter = ..Part(seed)
    Set parts.patient = ..Part({"resourceType": "Patient", "id": "demo-p1", "active": true, "identifier": [{"system": "urn:shutter:demo:mrn", "value": "MRN-UT1"}], "meta": {"versionId": "1"}}.%ToJSON())
    Set parts.locations = []
    For ward = "a", "b" {
        Set location = ..Part({"resourceType": "Location", "id": ("ward-" _ ward), "status": "active", "identifier": [{"system": "urn:shutter:ward", "value": ("WARD-" _ $ZCONVERT(ward, "U"))}], "meta": {"versionId": "1"}}.%ToJSON())
        Set location.reference = "Location/ward-" _ ward
        Do parts.locations.%Push(location)
    }
    Set parts.history = ..Part({"resourceType": "Bundle", "type": "history", "total": 1, "entry": [{"fullUrl": "Encounter/enc-1", "resource": (##class(%DynamicObject).%FromJSON(seed)), "request": {"method": "POST", "url": "Encounter"}, "response": {"status": "201"}}]}.%ToJSON())
    Do parts.history.%Remove("etag")
    Quit parts
}

/// One part of a read: a trusted 200 with that body, at ETag W/"1".
ClassMethod Part(body As %String) As %DynamicObject
{
    Set part = {"http_status": 200, "raw_status": 200, "location": "", "content_type": "application/fhir+json", "error": ""}
    Set part.etag = "W/""1""", part.body = body
    Quit part
}

/// Adds a receiver's entry to the stored site profile for one test, keeping the profile's version.
Method AddReceiver(entry As %DynamicObject)
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..ProfileChanged {
        Set ..HadProfileRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: ""), ..ProfileChanged = 1
    }
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    If '$ISOBJECT(p.%Get("receivers")) Set p.receivers = []
    Do p.receivers.%Push(entry)
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Version = version
    Set row.Json = p.%ToJSON()
    Do $$$AssertStatusOK(row.%Save(), "the receiver is added to the site profile for the test")
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

/// The comparable rows of a decision as one string: every conformance and catalogue row and, for a plan that writes,
/// the ordering rows this gate copies. <var>seen</var> collects their reason codes.
ClassMethod Comparable(checks As %DynamicArray, isWrite As %Boolean, ByRef seen) As %String
{
    Set copied = $LISTBUILD("PATIENT_UNREADABLE", "FURTHER_MOVEMENT_RELEASED", "FURTHER_MOVEMENT", "FURTHER_NOT_READ", "FURTHER_MOVEMENT_NEW", "NO_FURTHER_MOVEMENT", "NEWER_MESSAGE_PENDING", "EVENT_TIME_IMPLAUSIBLE", "NO_LATER_EVENT", "SUPERSEDED_BY_LATER_EVENT")
    Set out = "", iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) {
        Set take = (c.check = "conformance") || (c.check = "catalogue") || (isWrite && (c.check = "ordering") && ($LISTFIND(copied, c."reason_code") > 0))
        Continue:'take
        Set out = out _ $SELECT(out = "": "", 1: ";") _ c.check _ " " _ c.result _ " " _ c."reason_code"
        Set seen(c."reason_code") = ""
    }
    Quit out
}

/// The codes the rows assert, each with the results it is asserted with: asserted(code, result).
ClassMethod Asserted(ByRef asserted)
{
    Kill asserted
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set it2 = row.expect.%GetIterator()
        While it2.%GetNext(.j, .e) { Set asserted(e.%Get(2)) = "", asserted(e.%Get(2), e.%Get(1)) = "" }
    }
}

/// Every reason code written as a literal in the gate's source, whatever method holds it.
ClassMethod SourceCodes(ByRef codes)
{
    Kill codes
    Set def = ##class(%Dictionary.ClassDefinition).%OpenId("Shutter.Operation.FHIRGate")
    If '$ISOBJECT(def) Quit
    For i = 1:1:def.Methods.Count() {
        Set m = def.Methods.GetAt(i), source = ""
        Do m.Implementation.Rewind()
        While 'm.Implementation.AtEnd { Set source = source _ m.Implementation.ReadLine() _ $CHAR(10) }
        Set matcher = ##class(%Regex.Matcher).%New("""([A-Z][A-Z_]*[A-Z])""", source)
        While matcher.Locate() { Set codes(matcher.Group(1)) = "" }
    }
}

/// What is wrong with the shape of a decision, or "": a check without exactly its four keys, a result that is not
/// one of three, or a check of the list that is missing.
ClassMethod Shape(checks As %DynamicArray) As %String
{
    Set problem = "", iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) {
        Set keys = "", it2 = c.%GetIterator()
        While it2.%GetNext(.k, .v) { Set keys = keys _ $SELECT(keys = "": "", 1: ",") _ k }
        If keys '= "check,result,reason_code,detail" Set problem = problem _ " row " _ i _ " has keys " _ keys _ ";"
        If '$LISTFIND($LISTBUILD("pass", "block", "unknown"), c.result) Set problem = problem _ " row " _ i _ " has result " _ c.result _ ";"
        If (c.detail = "") || (c."reason_code" = "") Set problem = problem _ " row " _ i _ " has no code or no detail;"
        Set have(c.check) = ""
    }
    For i = 1:1:$LENGTH(..#CHECKS, ",") {
        If '$DATA(have($PIECE(..#CHECKS, ",", i))) Set problem = problem _ " no " _ $PIECE(..#CHECKS, ",", i) _ " row;"
    }
    Quit problem
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

/// Sets the value under <var>key</var> of <var>source</var> at a path with dots into <var>target</var>; a piece that
/// meets an array is an index. A null removes what is there.
ClassMethod Put(target As %DynamicAbstractObject, path As %String, source As %DynamicObject, key As %String)
{
    Set node = target, n = $LENGTH(path, ".")
    For i = 1:1:n - 1 {
        Set piece = $PIECE(path, ".", i)
        Set node = node.%Get($SELECT(node.%IsA("%Library.DynamicArray"): +piece, 1: piece))
    }
    Set last = $PIECE(path, ".", n)
    If node.%IsA("%Library.DynamicArray") Set last = +last
    Set type = source.%GetTypeOf(key)
    If type = "null" {
        Do node.%Remove(last)
    } ElseIf type = "boolean" {
        Do node.%Set(last, source.%Get(key), "boolean")
    } Else {
        Do node.%Set(last, source.%Get(key))
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

/// Deletes a test case and everything the gate and the stores recorded for it.
ClassMethod Purge(id As %String)
{
    For table = "Shutter_Store.FHIRAttempt", "Shutter_Store.FHIRBinding", "Shutter_Store.FHIRSealedRead", "Shutter_Store.GateDecision", "Shutter_Store.Approval", "Shutter_Store.Plan", "Shutter_Store.CaseEvent" {
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM " _ table _ " WHERE ""Case"" = ?", id)
    }
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.SnapshotItem WHERE Snapshot IN (SELECT ID FROM Shutter_Store.Snapshot WHERE ""Case"" = ?)", id)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.Snapshot WHERE ""Case"" = ?", id)
    Do ##class(Shutter.Store.Case).%DeleteId(id)
    Kill ^Shutter.Counter("event", id), ^Shutter.Counter("plan", id), ^Shutter.Counter("snapshot", id)
}

ClassMethod Rows() As %DynamicArray
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Rows")
    Quit ##class(%DynamicArray).%FromJSON(xdata.Data)
}

/// The evidence BaseView starts from (its Encounter's body_digest is filled in there).
XData View [ MimeType = application/json ]
{
{
  "operation": {"operation_key": "{key}", "payload_digest": "sha256:ut"},
  "validation": {"parsed": true},
  "timeline": [],
  "ward_state_http_status": 200,
  "ward_state": {"encounter_id": "V1001", "fhir_id": "enc-1", "patient_id": "MRN-UT1", "patient_id_authority": "HOSP", "state": "admitted", "ward": "WARD-A", "version": "1", "epoch": "",
    "history": [{"event": "transfer", "event_time": "2026-11-07T09:00:00Z", "ward": "WARD-A", "operation_key": "fhir^enc-1^ward-a^2026-11-07T09:00:00Z", "applied_at": "2026-11-07T09:00:00Z", "version": ""}]},
  "receipt_http_status": 404,
  "receipt": {"error": "no_receipt", "kind": "fhir"},
  "fhir": {"kind": "fhir_r4", "base": "/fhir-facade/r4", "mapping_digest": "sha256:ut",
    "message": {"prior_ward": "WARD-A", "target_ward": "WARD-B", "event_time": "2026-11-07T10:15:00Z"},
    "capability": {"http_status": 200, "software": {"name": "Shutter test FHIR server", "version": "facade-v1"}, "fhir_version": "4.0.1",
      "versioning": "versioned-update", "interactions": ["read", "vread", "update", "history-instance"], "read_history": true, "update_create": true},
    "search": {"http_status": 200, "matches": 1, "next": false},
    "encounter": {"http_status": 200, "id": "enc-1", "etag": "W/\"1\"", "version_id": "1", "etag_usable": true, "status": "in-progress", "subject": "Patient/demo-p1",
      "identifier_ok": true, "subsetted": false, "modifier_extension": false, "narrative": false, "security": false, "body_digest": "",
      "locations": [{"reference": "Location/ward-a", "ward": "WARD-A", "status": "active", "start": "2026-11-07T09:00:00Z", "start_utc": "2026-11-07T09:00:00Z", "end": ""}]},
    "patient": {"http_status": 200, "reference": "Patient/demo-p1", "etag": "W/\"1\"", "identifier_ok": true, "link": false, "active": true},
    "locations": [{"reference": "Location/ward-a", "ward": "WARD-A", "http_status": 200, "etag": "W/\"1\"", "status": "active", "identifier_ok": true},
      {"reference": "Location/ward-b", "ward": "WARD-B", "http_status": 200, "etag": "W/\"1\"", "status": "active", "identifier_ok": true}],
    "history": {"http_status": 200, "next": false, "entries": 1, "head_version_id": "1", "sent_marker_version": ""}}
}
}

/// The table: group (the test that runs the row), name, what the row changes, and what it expects.
XData Rows [ MimeType = application/json ]
{
[
  {"group": "table", "name": "a ward move that passes every check at the proposal",
   "expect": [["identity", "pass", "FHIR_IDENTITY_MATCHES"], ["conformance", "pass", "PARSED"], ["intent", "pass", "EXACT_OPERATION"], ["enablement", "pass", "FHIR_RECOVERY_ENABLED"],
     ["representation", "pass", "FHIR_REPRESENTATION_WHOLE"], ["state_transition", "pass", "TRANSITION_ALLOWED"], ["ordering", "pass", "ENGINE_SETTLED"], ["ordering", "pass", "NO_FURTHER_MOVEMENT"],
     ["ordering", "pass", "NO_LATER_EVENT"], ["ordering", "pass", "FHIR_ORDER_HOLDS"], ["mapping", "pass", "FHIR_LOCATIONS_CHECKED"], ["plan_shape", "pass", "FHIR_PLAN_BOUNDED"],
     ["concurrency", "pass", "NOT_YET_REQUIRED"], ["earlier_write", "pass", "FHIR_NO_EARLIER_WRITE"], ["capability", "pass", "FHIR_CAPABLE"], ["history", "pass", "FHIR_HISTORY_READ"],
     ["authorization", "pass", "NOT_YET_REQUIRED"], ["evidence", "pass", "FRESH"], ["catalogue", "pass", "NOT_CONFIGURED"], ["rehearsal", "pass", "FHIR_NO_DRY_RUN_SUBSTITUTED"]],
   "contains": [["intent", "EXACT_OPERATION", "The plan makes the one change the failed message asked for; the HL7 message is not sent again"]], "outcome": "pass"},
  {"group": "table", "name": "the same move at dispatch, on a person's approval tied to the sealed binding", "stage": "dispatch",
   "expect": [["identity", "pass", "FHIR_IDENTITY_MATCHES"], ["plan_shape", "pass", "FHIR_PLAN_BOUNDED"], ["concurrency", "pass", "FHIR_VERSION_MATCHES"], ["authorization", "pass", "APPROVAL_VALID"],
     ["evidence", "pass", "FRESH"], ["history", "pass", "FHIR_HISTORY_READ"], ["capability", "pass", "FHIR_CAPABLE"]], "outcome": "pass"},
  {"group": "table", "name": "a plan that writes nothing: the checks of a write do not apply", "plan": {"disposition": "escalate", "action": null}, "engine": "none",
   "expect": [["intent", "pass", "NO_WRITE"], ["enablement", "pass", "NOT_APPLICABLE"], ["representation", "pass", "NOT_APPLICABLE"], ["state_transition", "pass", "NOT_APPLICABLE"],
     ["ordering", "pass", "NOT_APPLICABLE"], ["mapping", "pass", "NOT_APPLICABLE"], ["plan_shape", "pass", "NOT_APPLICABLE"], ["concurrency", "pass", "NOT_APPLICABLE"],
     ["earlier_write", "pass", "NOT_APPLICABLE"], ["capability", "pass", "NOT_APPLICABLE"], ["history", "pass", "NOT_APPLICABLE"], ["identity", "pass", "FHIR_IDENTITY_MATCHES"]],
   "absent": [["ordering", "FHIR_ENGINE_NOT_IN_SCOPE"]], "outcome": "pass"},

  {"group": "table", "name": "identity: a message that names no visit number has no fhir view", "case": {"encounter_id": "-"}, "view": {"fhir": null},
   "expect": [["identity", "block", "FHIR_ENCOUNTER_NOT_FOUND"], ["representation", "unknown", "FHIR_ENCOUNTER_NOT_FOUND"], ["state_transition", "unknown", "FHIR_ENCOUNTER_NOT_FOUND"],
     ["ordering", "unknown", "FHIR_ENCOUNTER_NOT_FOUND"], ["plan_shape", "unknown", "FHIR_ENCOUNTER_NOT_FOUND"], ["history", "unknown", "FHIR_ENCOUNTER_NOT_FOUND"],
     ["capability", "unknown", "FHIR_CAPABILITIES_UNREADABLE"]],
   "contains": [["identity", "FHIR_ENCOUNTER_NOT_FOUND", "names no visit number"]], "outcome": "block"},
  {"group": "table", "name": "identity: the search found no Encounter", "set": {"fhir.search.matches": 0},
   "expect": [["identity", "block", "FHIR_ENCOUNTER_NOT_FOUND"]], "contains": [["identity", "FHIR_ENCOUNTER_NOT_FOUND", "V1001"]], "outcome": "block"},
  {"group": "table", "name": "identity: the search was not answered", "set": {"fhir.search.http_status": 0},
   "expect": [["identity", "unknown", "FHIR_RECEIVER_UNREADABLE"], ["representation", "unknown", "FHIR_RECEIVER_UNREADABLE"], ["history", "unknown", "FHIR_RECEIVER_UNREADABLE"]], "outcome": "unknown"},
  {"group": "table", "name": "identity: the search answered 503", "set": {"fhir.search.http_status": 503},
   "expect": [["identity", "unknown", "FHIR_RECEIVER_UNREADABLE"]], "contains": [["identity", "FHIR_RECEIVER_UNREADABLE", "HTTP 503"]], "outcome": "unknown"},
  {"group": "table", "name": "identity: the Encounter read gave no trusted answer", "set": {"fhir.encounter.http_status": 0},
   "expect": [["identity", "unknown", "FHIR_RECEIVER_UNREADABLE"], ["plan_shape", "unknown", "FHIR_RECEIVER_UNREADABLE"]], "outcome": "unknown"},
  {"group": "table", "name": "identity: the Encounter read answered 500", "set": {"fhir.encounter.http_status": 500},
   "expect": [["identity", "unknown", "FHIR_RECEIVER_UNREADABLE"]], "outcome": "unknown"},
  {"group": "table", "name": "identity: the Encounter the search named is gone", "set": {"fhir.encounter.http_status": 404},
   "expect": [["identity", "block", "FHIR_ENCOUNTER_NOT_FOUND"]], "outcome": "block"},
  {"group": "table", "name": "identity: two Encounters carry the visit number", "set": {"fhir.search.matches": 2},
   "expect": [["identity", "block", "FHIR_ENCOUNTER_AMBIGUOUS"]], "outcome": "block"},
  {"group": "table", "name": "identity: one match, but the search came in pages", "set": {"fhir.search.next": true},
   "expect": [["identity", "unknown", "FHIR_ENCOUNTER_AMBIGUOUS"]], "absent": [["identity", "FHIR_IDENTITY_MATCHES"]], "outcome": "unknown"},
  {"group": "table", "name": "identity: the patient identifier comes from another assigning authority", "case": {"patient_id_authority": "OTHER"},
   "expect": [["identity", "block", "FHIR_IDENTIFIER_UNMAPPED"]], "contains": [["identity", "FHIR_IDENTIFIER_UNMAPPED", "OTHER"]], "outcome": "block"},
  {"group": "table", "name": "identity: the Encounter read does not carry the visit number searched", "set": {"fhir.encounter.identifier_ok": false},
   "expect": [["identity", "block", "FHIR_IDENTIFIER_UNMAPPED"]], "outcome": "block"},
  {"group": "table", "name": "identity: the subject is no literal Patient reference", "set": {"fhir.encounter.subject": "Patient?identifier=urn:shutter:demo:mrn|MRN-UT1"},
   "expect": [["identity", "block", "FHIR_SUBJECT_UNRESOLVED"]], "outcome": "block"},
  {"group": "table", "name": "identity: the Patient could not be read", "set": {"fhir.patient.http_status": 0},
   "expect": [["identity", "unknown", "FHIR_SUBJECT_UNRESOLVED"]], "outcome": "unknown"},
  {"group": "table", "name": "identity: the Patient that was read is not the Encounter's subject", "set": {"fhir.patient.reference": "Patient/demo-p2"},
   "expect": [["identity", "unknown", "FHIR_SUBJECT_UNRESOLVED"]], "contains": [["identity", "FHIR_SUBJECT_UNRESOLVED", "Patient/demo-p2"]], "outcome": "unknown"},
  {"group": "table", "name": "identity: the Patient does not carry the message's identifier", "set": {"fhir.patient.identifier_ok": false},
   "expect": [["identity", "block", "FHIR_PATIENT_MISMATCH"]], "outcome": "block"},
  {"group": "table", "name": "identity: the Patient is linked to another", "set": {"fhir.patient.link": true},
   "expect": [["identity", "block", "FHIR_PATIENT_LINKED"]], "contains": [["identity", "FHIR_PATIENT_LINKED", "linked"]], "outcome": "block"},
  {"group": "table", "name": "identity: the Patient is not active", "set": {"fhir.patient.active": false},
   "expect": [["identity", "block", "FHIR_PATIENT_LINKED"]], "contains": [["identity", "FHIR_PATIENT_LINKED", "not active"]], "outcome": "block"},
  {"group": "table", "name": "identity: a Patient view that does not say whether it is linked is read as linked", "set": {"fhir.patient.link": null},
   "expect": [["identity", "block", "FHIR_PATIENT_LINKED"]], "outcome": "block"},

  {"group": "table", "name": "conformance: the message does not parse", "view": {"validation": {"parsed": false, "error": "PV1 is missing"}},
   "expect": [["conformance", "block", "PARSE_FAILED"]], "outcome": "block"},
  {"group": "table", "name": "conformance: a message that maps to no operation", "case": {"failure_kind": "unmappable", "failure_text": "No operation for this trigger"},
   "expect": [["conformance", "block", "UNMAPPABLE"], ["intent", "block", "FHIR_FAILURE_KIND_UNSUPPORTED"]], "outcome": "block"},
  {"group": "table", "name": "conformance: a schema this namespace does not hold",
   "view": {"validation": {"parsed": false, "schema_known": false, "schema_category": "2.5.1.HOSP", "schema_fix": "Import the schema, then reinvestigate the case", "error": "unknown schema"}},
   "expect": [["conformance", "block", "SCHEMA_UNKNOWN"]], "absent": [["conformance", "PARSE_FAILED"]], "outcome": "block"},

  {"group": "table", "name": "intent: a merge the site withheld", "case": {"event": "merge", "failure_kind": "withheld"},
   "expect": [["intent", "block", "MERGE_WITHHELD"], ["intent", "block", "FHIR_EVENT_UNSUPPORTED"], ["intent", "block", "FHIR_FAILURE_KIND_UNSUPPORTED"]], "outcome": "block"},
  {"group": "table", "name": "intent: a cancel the receiver's entry cannot reverse", "case": {"event": "cancel_transfer"},
   "expect": [["intent", "block", "CANCEL_UNSUPPORTED"], ["intent", "block", "FHIR_EVENT_UNSUPPORTED"]], "contains": [["intent", "CANCEL_UNSUPPORTED", "cancels: false"]], "outcome": "block"},
  {"group": "table", "name": "intent: a disposition the gate does not know", "plan": {"disposition": "mystery"},
   "expect": [["intent", "block", "UNKNOWN_DISPOSITION"]], "outcome": "block"},
  {"group": "table", "name": "intent: the plan names another operation", "plan": {"action": {"operation_key": "PAS^HOSP^MRN-UT1^V1001^transfer^2026-11-07T10:16:00Z"}},
   "expect": [["intent", "block", "DIFFERENT_OPERATION"]], "absent": [["intent", "EXACT_OPERATION"]], "outcome": "block"},
  {"group": "table", "name": "intent: the plan's payload digest is not the evidence's", "plan": {"action": {"payload_digest": "sha256:other"}},
   "expect": [["intent", "block", "PAYLOAD_CHANGED"]], "outcome": "block"},
  {"group": "table", "name": "intent: a discharge is not a ward move", "case": {"event": "discharge"},
   "expect": [["intent", "block", "FHIR_EVENT_UNSUPPORTED"], ["intent", "pass", "EXACT_OPERATION"]], "contains": [["intent", "FHIR_EVENT_UNSUPPORTED", "discharge"]], "outcome": "block"},

  {"group": "table", "name": "enablement: the entry turns recovery off", "entry": {"fhir": {"recovery_enabled": false}},
   "expect": [["enablement", "block", "FHIR_RECOVERY_DISABLED"]], "outcome": "block"},
  {"group": "table", "name": "enablement: the entry does not say", "entry": {"fhir": {"recovery_enabled": null}},
   "expect": [["enablement", "block", "FHIR_RECOVERY_DISABLED"]], "outcome": "block"},
  {"group": "table", "name": "enablement: a word is not a yes", "entry": {"fhir": {"recovery_enabled": "true"}},
   "expect": [["enablement", "block", "FHIR_RECOVERY_DISABLED"]], "outcome": "block"},
  {"group": "table", "name": "enablement: the profile has no entry for the receiver", "entry": "none",
   "expect": [["enablement", "block", "FHIR_RECOVERY_DISABLED"], ["identity", "block", "FHIR_IDENTIFIER_UNMAPPED"], ["mapping", "block", "FHIR_LOCATION_UNMAPPED"]], "outcome": "block"},

  {"group": "table", "name": "representation: a reduced copy", "set": {"fhir.encounter.subsetted": true},
   "expect": [["representation", "block", "FHIR_REPRESENTATION_PARTIAL"]], "outcome": "block"},
  {"group": "table", "name": "representation: a modifierExtension", "set": {"fhir.encounter.modifier_extension": true},
   "expect": [["representation", "block", "FHIR_MODIFIER_EXTENSION"]], "outcome": "block"},
  {"group": "table", "name": "representation: a narrative", "set": {"fhir.encounter.narrative": true},
   "expect": [["representation", "block", "FHIR_NARRATIVE_PRESENT"]], "outcome": "block"},
  {"group": "table", "name": "representation: a security label", "set": {"fhir.encounter.security": true},
   "expect": [["representation", "block", "FHIR_RESTRICTED"]], "outcome": "block"},
  {"group": "table", "name": "representation: no ETag that names the version", "set": {"fhir.encounter.etag_usable": false},
   "expect": [["representation", "block", "FHIR_NO_ETAG"]], "outcome": "block"},
  {"group": "table", "name": "representation: the first of several is the one given", "set": {"fhir.encounter.subsetted": true, "fhir.encounter.security": true, "fhir.encounter.etag_usable": false},
   "expect": [["representation", "block", "FHIR_REPRESENTATION_PARTIAL"]], "absent": [["representation", "FHIR_RESTRICTED"], ["representation", "FHIR_NO_ETAG"]], "outcome": "block"},
  {"group": "table", "name": "representation: a view that does not say whether the copy is whole is read as reduced", "set": {"fhir.encounter.subsetted": null},
   "expect": [["representation", "block", "FHIR_REPRESENTATION_PARTIAL"]], "outcome": "block"},

  {"group": "table", "name": "state transition: the Encounter is finished", "set": {"fhir.encounter.status": "finished"},
   "expect": [["state_transition", "block", "FHIR_STATUS_NOT_IN_PROGRESS"]], "contains": [["state_transition", "FHIR_STATUS_NOT_IN_PROGRESS", "finished"]], "outcome": "block"},
  {"group": "table", "name": "state transition: the patient is on the target ward already",
   "set": {"fhir.encounter.locations": [{"reference": "Location/ward-a", "ward": "WARD-A", "status": "completed", "start": "2026-11-07T09:00:00Z", "start_utc": "2026-11-07T09:00:00Z", "end": "2026-11-07T09:40:00Z"}, {"reference": "Location/ward-b", "ward": "WARD-B", "status": "active", "start": "2026-11-07T09:40:00Z", "start_utc": "2026-11-07T09:40:00Z", "end": ""}]},
   "expect": [["state_transition", "block", "FHIR_ALREADY_THERE"], ["ordering", "block", "FHIR_PRIOR_LOCATION_DIFFERS"]], "contains": [["state_transition", "FHIR_ALREADY_THERE", "WARD-B"]], "outcome": "block"},

  {"group": "table", "name": "ordering: a new admission for the patient on another visit",
   "further": {"identifier": "read", "stops": [{"why": "other_visit", "event": "admit", "message_type": "ADT_A01", "visit_number": "ENC-OTHER", "event_time": "2026-11-07T10:30:00Z", "control_id": "MSG-9"}], "shows": [], "unread": ""},
   "expect": [["ordering", "block", "FURTHER_MOVEMENT"]], "contains": [["ordering", "FURTHER_MOVEMENT", "visit ENC-OTHER"]], "absent": [["ordering", "NO_FURTHER_MOVEMENT"]], "outcome": "block"},
  {"group": "table", "name": "ordering: that stop released by a person who read these rows", "release": true,
   "further": {"identifier": "read", "stops": [{"why": "other_visit", "event": "admit", "message_type": "ADT_A01", "visit_number": "ENC-OTHER", "event_time": "2026-11-07T10:30:00Z", "control_id": "MSG-9"}], "shows": [], "unread": ""},
   "expect": [["ordering", "pass", "FURTHER_MOVEMENT_RELEASED"]], "absent": [["ordering", "FURTHER_MOVEMENT"]], "outcome": "pass"},
  {"group": "table", "name": "ordering: a patient identifier that could not be read", "further": {"identifier": "unreadable", "stops": [], "shows": [], "unread": ""},
   "expect": [["ordering", "block", "PATIENT_UNREADABLE"]], "outcome": "block"},
  {"group": "table", "name": "ordering: further messages that could not all be read", "further": {"identifier": "read", "stops": [], "shows": [], "unread": "the read of HOSPITAL ran out of its 30 seconds with messages left"},
   "expect": [["ordering", "block", "FURTHER_NOT_READ"]], "contains": [["ordering", "FURTHER_NOT_READ", "HOSPITAL"]], "outcome": "block"},
  {"group": "table", "name": "ordering: another visit's movement the snapshot did not show, read at dispatch", "stage": "dispatch",
   "further": {"identifier": "read", "stops": [], "shows": [{"why": "other_visit", "event": "admit", "message_type": "ADT_A01", "visit_number": "ENC-NEW", "event_time": "2026-11-07T10:40:00Z", "control_id": "MSG-12"}], "unread": ""},
   "expect": [["ordering", "unknown", "FURTHER_MOVEMENT_NEW"]], "contains": [["ordering", "FURTHER_MOVEMENT_NEW", "visit ENC-NEW"]], "absent": [["ordering", "NO_FURTHER_MOVEMENT"]], "outcome": "unknown"},
  {"group": "table", "name": "ordering: a newer message of the encounter is pending in Shutter",
   "pending": [{"event": "transfer", "event_time": "2026-11-07T10:45:00Z", "operation_key": "k-later", "control_id": "MSG-9", "ens_header_id": "77", "sent_at": "2026-11-07 10:46:00.000", "receiver": "FHIR Ward Out", "where": "queued for the receiver, no answer yet"}],
   "expect": [["ordering", "block", "NEWER_MESSAGE_PENDING"]], "outcome": "block"},
  {"group": "table", "name": "ordering: the event's time lies in the future", "view": {"catalogue": {"decision": "not_configured", "conditions": {"event_time": "future"}}},
   "expect": [["ordering", "block", "EVENT_TIME_IMPLAUSIBLE"]], "contains": [["ordering", "EVENT_TIME_IMPLAUSIBLE", "it lies in the future"]], "absent": [["ordering", "NO_LATER_EVENT"]], "outcome": "block"},
  {"group": "table", "name": "ordering: a later discharge was applied in the feed",
   "view": {"timeline": [{"event": "discharge", "event_time": "2026-11-07T10:50:00Z", "operation_key": "PAS^HOSP^MRN-UT1^V1001^discharge^2026-11-07T10:50:00Z", "outcome": "applied", "later": true, "source": "feed", "sent_at": "2026-11-07 10:50:05.000"}]},
   "expect": [["ordering", "block", "SUPERSEDED_BY_LATER_EVENT"]], "contains": [["ordering", "SUPERSEDED_BY_LATER_EVENT", "A later event was applied"]], "outcome": "block"},
  {"group": "table", "name": "ordering: a location whose start is a date alone", "set": {"fhir.encounter.locations.0.start": "2026-11-07", "fhir.encounter.locations.0.start_utc": ""},
   "expect": [["ordering", "unknown", "FHIR_TIME_UNREADABLE"]], "contains": [["ordering", "FHIR_TIME_UNREADABLE", "Location/ward-a"]], "absent": [["ordering", "FHIR_ORDER_HOLDS"]], "outcome": "unknown"},
  {"group": "table", "name": "ordering: a location with no start", "set": {"fhir.encounter.locations.0.start": ""},
   "expect": [["ordering", "unknown", "FHIR_TIME_UNREADABLE"]], "contains": [["ordering", "FHIR_TIME_UNREADABLE", "has no start"]], "outcome": "unknown"},
  {"group": "table", "name": "ordering: the message's own event time cannot be ordered", "case": {"event_time": "2026-11-07 10:15"},
   "expect": [["ordering", "unknown", "FHIR_TIME_UNREADABLE"]], "contains": [["ordering", "FHIR_TIME_UNREADABLE", "event time"]], "absent": [["ordering", "FHIR_ORDER_HOLDS"]], "outcome": "block"},
  {"group": "table", "name": "ordering: a location that starts at the event time", "set": {"fhir.encounter.locations.0.start": "2026-11-07T10:15:00Z"},
   "expect": [["ordering", "block", "FHIR_LATER_MOVE_AT_RECEIVER"]], "outcome": "block"},
  {"group": "table", "name": "ordering: a start with an offset is ordered as an instant, later", "set": {"fhir.encounter.locations.0.start": "2026-11-07T11:20:00+01:00"},
   "expect": [["ordering", "block", "FHIR_LATER_MOVE_AT_RECEIVER"]], "contains": [["ordering", "FHIR_LATER_MOVE_AT_RECEIVER", "2026-11-07T11:20:00+01:00"]], "outcome": "block"},
  {"group": "table", "name": "ordering: a start with an offset is ordered as an instant, earlier though its text sorts later", "set": {"fhir.encounter.locations.0.start": "2026-11-07T11:10:00+01:00"},
   "expect": [["ordering", "pass", "FHIR_ORDER_HOLDS"]], "absent": [["ordering", "FHIR_LATER_MOVE_AT_RECEIVER"]], "outcome": "pass"},
  {"group": "table", "name": "ordering: a fraction of a second after the event time is later", "set": {"fhir.encounter.locations.0.start": "2026-11-07T10:15:00.001Z"},
   "expect": [["ordering", "block", "FHIR_LATER_MOVE_AT_RECEIVER"]], "outcome": "block"},
  {"group": "table", "name": "ordering: the open location is not the ward the message says the patient came from", "set": {"fhir.encounter.locations.0.ward": "WARD-C"},
   "expect": [["ordering", "block", "FHIR_PRIOR_LOCATION_DIFFERS"]], "contains": [["ordering", "FHIR_PRIOR_LOCATION_DIFFERS", "WARD-C"]], "absent": [["ordering", "FHIR_ORDER_HOLDS"]], "outcome": "block"},
  {"group": "table", "name": "ordering: the message names no ward the patient came from", "set": {"fhir.message.prior_ward": ""},
   "expect": [["ordering", "unknown", "FHIR_PRIOR_LOCATION_DIFFERS"], ["mapping", "block", "FHIR_LOCATION_UNMAPPED"]], "absent": [["plan_shape", "FHIR_LOCATION_UNMAPPED"]], "outcome": "block"},
  {"group": "table", "name": "ordering: no open location at all", "set": {"fhir.encounter.locations.0.end": "2026-11-07T09:50:00Z"},
   "expect": [["ordering", "block", "FHIR_PRIOR_LOCATION_DIFFERS"]], "contains": [["ordering", "FHIR_PRIOR_LOCATION_DIFFERS", "no open location"]], "outcome": "block"},

  {"group": "table", "name": "mapping: the target ward has no Location in the map", "set": {"fhir.message.target_ward": "WARD-Z"},
   "expect": [["mapping", "block", "FHIR_LOCATION_UNMAPPED"]], "contains": [["mapping", "FHIR_LOCATION_UNMAPPED", "WARD-Z"]], "absent": [["plan_shape", "FHIR_LOCATION_UNMAPPED"], ["plan_shape", "FHIR_PLAN_BOUNDED"]], "outcome": "block"},
  {"group": "table", "name": "mapping: a mapped Location could not be read", "set": {"fhir.locations.1.http_status": 0},
   "expect": [["mapping", "unknown", "FHIR_LOCATION_UNREADABLE"]], "contains": [["mapping", "FHIR_LOCATION_UNREADABLE", "Location/ward-b"]], "outcome": "unknown"},
  {"group": "table", "name": "mapping: a map entry with no read at all",
   "set": {"fhir.locations": [{"reference": "Location/ward-a", "ward": "WARD-A", "http_status": 200, "etag": "W/\"1\"", "status": "active", "identifier_ok": true}]},
   "expect": [["mapping", "unknown", "FHIR_LOCATION_UNREADABLE"]], "outcome": "unknown"},
  {"group": "table", "name": "mapping: a mapped Location is not active", "set": {"fhir.locations.1.status": "inactive"},
   "expect": [["mapping", "block", "FHIR_LOCATION_MISMATCH"]], "contains": [["mapping", "FHIR_LOCATION_MISMATCH", "not active"]], "outcome": "block"},
  {"group": "table", "name": "mapping: a mapped Location does not carry its recorded identifier", "set": {"fhir.locations.0.identifier_ok": false},
   "expect": [["mapping", "block", "FHIR_LOCATION_MISMATCH"]], "outcome": "block"},
  {"group": "table", "name": "mapping: one Location unread and another wrong are both said", "set": {"fhir.locations.0.http_status": 503, "fhir.locations.1.status": "suspended"},
   "expect": [["mapping", "unknown", "FHIR_LOCATION_UNREADABLE"], ["mapping", "block", "FHIR_LOCATION_MISMATCH"]], "outcome": "block"},

  {"group": "table", "name": "plan shape: the Encounter has two open locations", "body": "two_open",
   "expect": [["plan_shape", "block", "FHIR_SHAPE_UNSUPPORTED"]], "absent": [["plan_shape", "FHIR_PLAN_BOUNDED"]], "outcome": "block"},
  {"group": "table", "name": "plan shape: the Encounter as read is not on file", "body": "none",
   "expect": [["plan_shape", "unknown", "FHIR_RECEIVER_UNREADABLE"]], "contains": [["plan_shape", "FHIR_RECEIVER_UNREADABLE", "not on file"]], "outcome": "unknown"},
  {"group": "table", "name": "plan shape: the update built at dispatch is not the one approved", "stage": "dispatch", "binding": {"approved_body_digest": "0000000000000000000000000000000000000000000000000000000000000000"},
   "expect": [["plan_shape", "block", "FHIR_BODY_CHANGED"]], "absent": [["plan_shape", "FHIR_PLAN_BOUNDED"]], "outcome": "block"},

  {"group": "table", "name": "concurrency: no binding at dispatch", "stage": "dispatch", "binding": "none",
   "expect": [["concurrency", "block", "FHIR_NO_BINDING"], ["authorization", "block", "FHIR_NO_BINDING"]], "outcome": "block"},
  {"group": "table", "name": "concurrency: the Encounter is at another version than the one approved against", "stage": "dispatch",
   "set": {"fhir.encounter.etag": "W/\"2\"", "fhir.encounter.version_id": "2", "fhir.history.head_version_id": "2"},
   "expect": [["concurrency", "block", "FHIR_RECEIVER_CHANGED"], ["plan_shape", "block", "FHIR_BODY_CHANGED"]], "contains": [["concurrency", "FHIR_RECEIVER_CHANGED", "W/\"2\""], ["concurrency", "FHIR_RECEIVER_CHANGED", "W/\"1\""]],
   "absent": [["concurrency", "FHIR_VERSION_MATCHES"]], "outcome": "block"},
  {"group": "table", "name": "concurrency: the Patient changed after the approval", "stage": "dispatch", "set": {"fhir.patient.etag": "W/\"2\""},
   "expect": [["concurrency", "block", "FHIR_PATIENT_CHANGED"]], "outcome": "block"},
  {"group": "table", "name": "concurrency: a mapped Location changed after the approval", "stage": "dispatch", "set": {"fhir.locations.1.etag": "W/\"7\""},
   "expect": [["concurrency", "block", "FHIR_LOCATION_CHANGED"]], "contains": [["concurrency", "FHIR_LOCATION_CHANGED", "Location/ward-b"]], "outcome": "block"},
  {"group": "table", "name": "concurrency: a part was not read just before the write", "stage": "dispatch", "set": {"fhir.locations.0.http_status": 0},
   "expect": [["concurrency", "unknown", "FHIR_RECEIVER_UNREADABLE"], ["mapping", "unknown", "FHIR_LOCATION_UNREADABLE"]], "absent": [["concurrency", "FHIR_VERSION_MATCHES"]], "outcome": "unknown"},
  {"group": "table", "name": "concurrency: an unread Patient does not hide a changed Encounter", "stage": "dispatch", "set": {"fhir.patient.http_status": 0, "fhir.encounter.etag": "W/\"2\""},
   "expect": [["concurrency", "unknown", "FHIR_RECEIVER_UNREADABLE"], ["concurrency", "block", "FHIR_RECEIVER_CHANGED"]], "outcome": "block"},

  {"group": "table", "name": "capability: the CapabilityStatement could not be read", "set": {"fhir.capability.http_status": 0},
   "expect": [["capability", "unknown", "FHIR_CAPABILITIES_UNREADABLE"]], "outcome": "unknown"},
  {"group": "table", "name": "capability: no version read", "set": {"fhir.capability.interactions": ["read", "update", "history-instance"]},
   "expect": [["capability", "block", "FHIR_NO_HISTORY"]], "contains": [["capability", "FHIR_NO_HISTORY", "vread"]], "outcome": "block"},
  {"group": "table", "name": "capability: no instance history", "set": {"fhir.capability.interactions": ["read", "vread", "update", "history-type"]},
   "expect": [["capability", "block", "FHIR_NO_HISTORY"]], "outcome": "block"},
  {"group": "table", "name": "capability: readHistory is not true", "set": {"fhir.capability.read_history": false},
   "expect": [["capability", "block", "FHIR_NO_HISTORY"]], "outcome": "block"},
  {"group": "table", "name": "capability: the server does not state versioned updates", "set": {"fhir.capability.versioning": "versioned"},
   "expect": [["capability", "block", "FHIR_VERSIONING_UNPROVEN"]], "contains": [["capability", "FHIR_VERSIONING_UNPROVEN", "versioned-update"]], "outcome": "block"},

  {"group": "table", "name": "history: the history could not be read", "set": {"fhir.history.http_status": 0},
   "expect": [["history", "unknown", "FHIR_HISTORY_UNAVAILABLE"]], "outcome": "unknown"},
  {"group": "table", "name": "history: the history came in pages", "set": {"fhir.history.next": true},
   "expect": [["history", "unknown", "FHIR_HISTORY_UNAVAILABLE"]], "contains": [["history", "FHIR_HISTORY_UNAVAILABLE", "pages"]], "outcome": "unknown"},
  {"group": "table", "name": "history: its newest version is not the one read", "set": {"fhir.history.head_version_id": "2"},
   "expect": [["history", "block", "FHIR_HISTORY_HEAD_DIFFERS"]], "absent": [["history", "FHIR_HISTORY_READ"]], "outcome": "block"},
  {"group": "table", "name": "history: a version carries the marker of an update this case sent", "set": {"fhir.history.sent_marker_version": "1"},
   "expect": [["history", "block", "FHIR_ALREADY_WRITTEN"]], "absent": [["history", "FHIR_HISTORY_READ"]], "outcome": "block"},

  {"group": "table", "name": "authorization: no approval at dispatch", "stage": "dispatch", "approval": "none",
   "expect": [["authorization", "block", "NO_APPROVAL"]], "outcome": "block"},
  {"group": "table", "name": "authorization: the approval was revoked", "stage": "dispatch", "approval": {"revoked": true},
   "expect": [["authorization", "block", "APPROVAL_REVOKED"]], "outcome": "block"},
  {"group": "table", "name": "authorization: a rejection is no approval", "stage": "dispatch", "approval": {"decision": "rejected"},
   "expect": [["authorization", "block", "APPROVAL_NOT_APPROVED"]], "outcome": "block"},
  {"group": "table", "name": "authorization: the approval is of another plan", "stage": "dispatch", "approval": {"plan_digest": "sha256:another"},
   "expect": [["authorization", "block", "APPROVAL_PLAN_CHANGED"]], "outcome": "block"},
  {"group": "table", "name": "authorization: an approval given under the policy version of the gate for ADT cases", "stage": "dispatch", "approval": {"policy_version": "2026-11-07.1"},
   "expect": [["authorization", "block", "APPROVAL_POLICY_CHANGED"]], "outcome": "block"},
  {"group": "table", "name": "authorization: the binding is tied to another approval", "stage": "dispatch", "binding": {"approval_id": "999999999"},
   "expect": [["authorization", "block", "FHIR_NO_BINDING"]], "absent": [["authorization", "APPROVAL_VALID"]], "outcome": "block"},
  {"group": "table", "name": "authorization: the binding is tied to no approval", "stage": "dispatch", "binding": {"approval_id": ""},
   "expect": [["authorization", "block", "FHIR_NO_BINDING"]], "outcome": "block"},

  {"group": "table", "name": "evidence: the snapshot has expired at the proposal", "fresh": false,
   "expect": [["evidence", "unknown", "STALE_EVIDENCE"]], "outcome": "unknown"},
  {"group": "table", "name": "evidence: the read before the write is too old at dispatch", "stage": "dispatch", "fresh": false,
   "expect": [["evidence", "unknown", "STALE_EVIDENCE"]], "contains": [["evidence", "STALE_EVIDENCE", "120 seconds"]], "outcome": "unknown"},

  {"group": "table", "name": "catalogue: the matcher failed", "view": {"catalogue": {"decision": "error", "error": "the pattern of E4 is not an object"}},
   "expect": [["catalogue", "unknown", "MATCHER_ERROR"]], "outcome": "unknown"},
  {"group": "table", "name": "catalogue: no entry matches the evidence", "view": {"catalogue": {"decision": "new_pattern", "matches": []}},
   "expect": [["catalogue", "block", "NEW_PATTERN"]], "outcome": "block"},
  {"group": "table", "name": "catalogue: the plan names no entry while several match",
   "view": {"catalogue": {"decision": "board", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}, {"id": "E9", "preferred": {"outcome": "resend"}}]}},
   "expect": [["catalogue", "pass", "ENTRY_NOT_NAMED"]], "outcome": "pass"},
  {"group": "table", "name": "catalogue: a plan that writes and names no entry on an entry that stops", "case": {"mode": "board"}, "plan": {"created_by": "run:1"},
   "view": {"catalogue": {"decision": "board", "entry": "E7", "outcome": "escalate", "matches": [{"id": "E7", "preferred": {"outcome": "escalate"}}]}},
   "expect": [["catalogue", "block", "ENTRY_NOT_NAMED_WRITE"]], "contains": [["catalogue", "ENTRY_NOT_NAMED_WRITE", "E7"]], "outcome": "block"},
  {"group": "table", "name": "catalogue: the plan follows an entry whose pattern does not hold", "plan": {"catalogue_entry": "E2", "outcome": "preferred"},
   "view": {"catalogue": {"decision": "policy", "entry": "E3", "matches": [{"id": "E3", "preferred": {"outcome": "reconcile"}}]}},
   "expect": [["catalogue", "block", "PATTERN_NOT_MATCHED"]], "outcome": "block"},
  {"group": "table", "name": "catalogue: the plan names an entry the catalogue does not have", "plan": {"catalogue_entry": "E999", "outcome": "preferred"},
   "view": {"catalogue": {"decision": "policy", "entry": "E2", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}]}},
   "expect": [["catalogue", "block", "ENTRY_UNKNOWN"]], "outcome": "block"},
  {"group": "table", "name": "catalogue: the plan follows the matched entry's preferred outcome", "plan": {"catalogue_entry": "E2", "outcome": "preferred"},
   "view": {"catalogue": {"decision": "policy", "entry": "E2", "matches": [{"id": "E2", "preferred": {"outcome": "resend"}}]}},
   "expect": [["catalogue", "pass", "ENTRY_MATCHED"]], "absent": [["catalogue", "OUTCOME_MISMATCH"]], "outcome": "pass"},
  {"group": "table", "name": "catalogue: the plan resends where the entry's outcome is to reconcile", "plan": {"catalogue_entry": "E3", "outcome": "preferred"},
   "view": {"catalogue": {"decision": "policy", "entry": "E3", "matches": [{"id": "E3", "preferred": {"outcome": "reconcile"}}]}},
   "expect": [["catalogue", "pass", "ENTRY_MATCHED"], ["catalogue", "block", "OUTCOME_MISMATCH"]], "outcome": "block"},
  {"group": "table", "name": "catalogue: an alternative that holds always", "plan": {"catalogue_entry": "E5", "outcome": "alternative:1"},
   "view": {"catalogue": {"decision": "board", "entry": "E5", "matches": [{"id": "E5", "preferred": {"outcome": "resend_latest"}, "alternatives": [{"outcome": "resend", "when": "always"}]}], "facts": {"other_source": ""}}},
   "expect": [["catalogue", "pass", "OUTCOME_ALLOWED"]], "absent": [["catalogue", "OUTCOME_MISMATCH"]], "outcome": "pass"},
  {"group": "table", "name": "catalogue: an alternative the entry does not have", "plan": {"catalogue_entry": "E5", "outcome": "alternative:3"},
   "view": {"catalogue": {"decision": "board", "entry": "E5", "matches": [{"id": "E5", "preferred": {"outcome": "resend_latest"}, "alternatives": [{"outcome": "resend", "when": "always"}]}]}},
   "expect": [["catalogue", "block", "OUTCOME_NOT_ALLOWED"]], "outcome": "block"},

  {"group": "etags", "name": "an opaque ETag matches itself", "stage": "dispatch", "base": {"fhir": {"encounter": {"etag": "\"a1b2-opaque\"", "version_id": "a1b2-opaque"}, "history": {"head_version_id": "a1b2-opaque"}}},
   "expect": [["concurrency", "pass", "FHIR_VERSION_MATCHES"], ["plan_shape", "pass", "FHIR_PLAN_BOUNDED"]], "contains": [["concurrency", "FHIR_VERSION_MATCHES", "a1b2-opaque"]], "outcome": "pass"},
  {"group": "etags", "name": "W/\"3\" is not \"3\"", "stage": "dispatch", "base": {"fhir": {"encounter": {"etag": "W/\"3\"", "version_id": "3"}, "history": {"head_version_id": "3"}}},
   "set": {"fhir.encounter.etag": "\"3\""},
   "expect": [["concurrency", "block", "FHIR_RECEIVER_CHANGED"]], "absent": [["concurrency", "FHIR_VERSION_MATCHES"]], "outcome": "block"},
  {"group": "etags", "name": "\"10\" is not \"9\"", "stage": "dispatch", "base": {"fhir": {"encounter": {"etag": "\"9\"", "version_id": "9"}, "history": {"head_version_id": "9"}}},
   "set": {"fhir.encounter.etag": "\"10\"", "fhir.encounter.version_id": "10", "fhir.history.head_version_id": "10"},
   "expect": [["concurrency", "block", "FHIR_RECEIVER_CHANGED"]], "outcome": "block"},
  {"group": "etags", "name": "a number written another way is another string", "stage": "dispatch", "binding": {"expected_etag": "100"},
   "set": {"fhir.encounter.etag": "1e2"},
   "expect": [["concurrency", "block", "FHIR_RECEIVER_CHANGED"]], "outcome": "block"},
  {"group": "etags", "name": "nor is a number with a trailing zero", "stage": "dispatch", "binding": {"expected_etag": "3"},
   "set": {"fhir.encounter.etag": "3.0"},
   "expect": [["concurrency", "block", "FHIR_RECEIVER_CHANGED"]], "outcome": "block"},
  {"group": "etags", "name": "a Location's weak and strong forms differ too", "stage": "dispatch", "set": {"fhir.locations.0.etag": "\"1\""},
   "expect": [["concurrency", "block", "FHIR_LOCATION_CHANGED"]], "outcome": "block"},
  {"group": "etags", "name": "the history's head is compared with the version read as a string", "set": {"fhir.history.head_version_id": "01"},
   "expect": [["history", "block", "FHIR_HISTORY_HEAD_DIFFERS"]], "outcome": "block"},

  {"group": "scope", "name": "a case with no source header: there is nothing to read the engine by", "engine": "none",
   "expect": [["ordering", "unknown", "FHIR_ENGINE_NOT_IN_SCOPE"]], "contains": [["ordering", "FHIR_ENGINE_NOT_IN_SCOPE", "no source header"]], "outcome": "unknown"},
  {"group": "scope", "name": "the item is no stock HL7 TCP operation", "engine": {"scope": "no", "headers": []},
   "expect": [["ordering", "unknown", "FHIR_ENGINE_NOT_IN_SCOPE"]], "absent": [["ordering", "ENGINE_NOT_IN_SCOPE"]], "outcome": "unknown"},
  {"group": "scope", "name": "the item is a subclass of the stock operation, whatever its header says",
   "engine": {"scope": "base", "headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "never_opened"}]},
   "expect": [["ordering", "unknown", "FHIR_ENGINE_SUBCLASS_UNPROVEN"]], "absent": [["ordering", "ENGINE_SETTLED"]], "outcome": "unknown"},
  {"group": "scope", "name": "the scope could not be read", "engine": {"scope": "unreadable", "why": "the item is not read", "headers": []},
   "expect": [["ordering", "unknown", "ENGINE_UNREADABLE"]], "outcome": "unknown"},
  {"group": "scope", "name": "facts with no headers at all are unreadable, not settled", "engine": {"scope": "yes", "headers": null},
   "expect": [["ordering", "unknown", "ENGINE_UNREADABLE"]], "outcome": "unknown"},
  {"group": "scope", "name": "a stock operation whose header settled before a connection opened passes",
   "expect": [["ordering", "pass", "ENGINE_SETTLED"]], "outcome": "pass"},

  {"group": "engine", "name": "the engine is still trying the message",
   "engine": {"headers": [{"headerId": "17", "custody": "engine", "status": "Delivered", "itemStatus": "Retry", "completedAt": "", "why": "", "attempts": ""}]},
   "expect": [["ordering", "block", "ENGINE_STILL_TRYING"]], "outcome": "block"},
  {"group": "engine", "name": "a settled header the receiver was reached on",
   "engine": {"headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "reached_receiver"}]},
   "expect": [["ordering", "block", "RECEIVER_MAY_HOLD_IT"]], "outcome": "block"},
  {"group": "engine", "name": "a header the engine delivered on an alert route is the engine check's own block",
   "engine": {"effectiveAck": "connection", "headers": [{"headerId": "17", "custody": "delivered", "status": "Completed", "itemStatus": "OK", "completedAt": "2026-11-07 10:16:01.123", "why": "", "attempts": ""}]},
   "expect": [["ordering", "block", "ENGINE_DELIVERED"]], "outcome": "block"},
  {"group": "engine", "name": "a header the engine delivered on the acknowledgement route, which the gate of an ADT case passes",
   "engine": {"ackRoute": true, "headers": [{"headerId": "17", "custody": "delivered", "status": "Completed", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": ""}]},
   "expect": [["ordering", "block", "FHIR_ENGINE_DELIVERED"]], "contains": [["ordering", "FHIR_ENGINE_DELIVERED", "header 17"]], "absent": [["ordering", "ENGINE_SETTLED"]], "outcome": "block"},
  {"group": "engine", "name": "a delivered copy beside a settled origin, on the acknowledgement route",
   "engine": {"ackRoute": true, "headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "never_opened"}, {"headerId": "18", "custody": "delivered", "status": "Completed", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": ""}]},
   "expect": [["ordering", "block", "FHIR_ENGINE_DELIVERED"]], "contains": [["ordering", "FHIR_ENGINE_DELIVERED", "header 18"]], "outcome": "block"},
  {"group": "engine", "name": "a header the engine holds suspended, which the gate of an ADT case reads as settled",
   "engine": {"headers": [{"headerId": "17", "custody": "settled", "status": "Suspended", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "never_opened"}]},
   "expect": [["ordering", "block", "FHIR_ENGINE_HOLDS_SUSPENDED"]], "contains": [["ordering", "FHIR_ENGINE_HOLDS_SUSPENDED", "header 17"]], "absent": [["ordering", "ENGINE_SETTLED"]], "outcome": "block"},
  {"group": "engine", "name": "a suspended copy beside a settled origin",
   "engine": {"headers": [{"headerId": "17", "custody": "settled", "status": "Error", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "never_opened"}, {"headerId": "19", "custody": "settled", "status": "Suspended", "itemStatus": "OK", "completedAt": "", "why": "", "attempts": "never_opened"}]},
   "expect": [["ordering", "block", "FHIR_ENGINE_HOLDS_SUSPENDED"]], "contains": [["ordering", "FHIR_ENGINE_HOLDS_SUSPENDED", "header 19"]], "outcome": "block"},

  {"group": "proof", "name": "no conformance run is recorded for the receiver", "proof": "none",
   "expect": [["capability", "block", "FHIR_VERSIONING_UNPROVEN"]], "contains": [["capability", "FHIR_VERSIONING_UNPROVEN", "no conformance run"]], "outcome": "block"},
  {"group": "proof", "name": "the server now names another version than the run measured", "set": {"fhir.capability.software.version": "facade-v2"},
   "expect": [["capability", "block", "FHIR_VERSIONING_UNPROVEN"]], "contains": [["capability", "FHIR_VERSIONING_UNPROVEN", "facade-v2"], ["capability", "FHIR_VERSIONING_UNPROVEN", "facade-v1"]], "outcome": "block"},
  {"group": "proof", "name": "the server now names other software", "set": {"fhir.capability.software.name": "Another FHIR server"},
   "expect": [["capability", "block", "FHIR_VERSIONING_UNPROVEN"]], "outcome": "block"},
  {"group": "proof", "name": "the server names no software at all", "set": {"fhir.capability.software": null},
   "expect": [["capability", "block", "FHIR_VERSIONING_UNPROVEN"]], "outcome": "block"},
  {"group": "proof", "name": "the software's name is compared exactly, letter case included", "proof": {"SoftwareName": "shutter test fhir server"},
   "expect": [["capability", "block", "FHIR_VERSIONING_UNPROVEN"]], "outcome": "block"},
  {"group": "proof", "name": "the run did not show a stale If-Match refused", "proof": {"IfMatchStaleRefused": 0},
   "expect": [["capability", "block", "FHIR_VERSIONING_UNPROVEN"]], "contains": [["capability", "FHIR_VERSIONING_UNPROVEN", "three measurements"]], "outcome": "block"},
  {"group": "proof", "name": "the run did not show an unknown If-Match refused", "proof": {"IfMatchUnknownIdRefused": 0},
   "expect": [["capability", "block", "FHIR_VERSIONING_UNPROVEN"]], "outcome": "block"},
  {"group": "proof", "name": "the run did not show a version's tags kept", "proof": {"TagsKept": 0},
   "expect": [["capability", "block", "FHIR_VERSIONING_UNPROVEN"]], "outcome": "block"},
  {"group": "proof", "name": "a run that matches the software the server names, at dispatch too", "stage": "dispatch",
   "expect": [["capability", "pass", "FHIR_CAPABLE"]], "contains": [["capability", "FHIR_CAPABLE", "Shutter test FHIR server facade-v1"]], "outcome": "pass"},

  {"group": "rehearsal", "name": "a write at the proposal", "expect": []},
  {"group": "rehearsal", "name": "a write at dispatch", "stage": "dispatch", "expect": []},
  {"group": "rehearsal", "name": "an escalate plan at the proposal", "plan": {"disposition": "escalate", "action": null}, "expect": []},
  {"group": "rehearsal", "name": "an escalate plan at dispatch", "stage": "dispatch", "plan": {"disposition": "escalate", "action": null}, "expect": []},

  {"group": "earlier", "name": "an earlier update on this version with no known outcome, at the proposal", "unresolved": true,
   "expect": [["earlier_write", "unknown", "FHIR_EARLIER_WRITE_UNRESOLVED"]], "absent": [["earlier_write", "FHIR_NO_EARLIER_WRITE"]], "outcome": "unknown"},
  {"group": "earlier", "name": "and at dispatch", "stage": "dispatch", "unresolved": true,
   "expect": [["earlier_write", "unknown", "FHIR_EARLIER_WRITE_UNRESOLVED"]], "contains": [["earlier_write", "FHIR_EARLIER_WRITE_UNRESOLVED", "may yet land"]], "outcome": "unknown"},
  {"group": "earlier", "name": "a plan that writes nothing is not held by it", "unresolved": true, "plan": {"disposition": "escalate", "action": null},
   "expect": [["earlier_write", "pass", "NOT_APPLICABLE"]], "outcome": "pass"},

  {"group": "kind", "name": "a delivery that failed is repaired", "case": {"failure_kind": "delivery_failed"},
   "expect": [["intent", "pass", "EXACT_OPERATION"]], "absent": [["intent", "FHIR_FAILURE_KIND_UNSUPPORTED"]], "outcome": "pass"},
  {"group": "kind", "name": "a delivery whose outcome is uncertain is repaired", "case": {"failure_kind": "uncertain_outcome"},
   "expect": [["intent", "pass", "EXACT_OPERATION"]], "absent": [["intent", "FHIR_FAILURE_KIND_UNSUPPORTED"]], "outcome": "pass"},
  {"group": "kind", "name": "a message the receiver rejected is not", "case": {"failure_kind": "rejected"},
   "expect": [["intent", "block", "FHIR_FAILURE_KIND_UNSUPPORTED"]], "contains": [["intent", "FHIR_FAILURE_KIND_UNSUPPORTED", "rejected"]], "outcome": "block"},
  {"group": "kind", "name": "nor one that could not be read", "case": {"failure_kind": "unreadable"},
   "expect": [["intent", "block", "FHIR_FAILURE_KIND_UNSUPPORTED"]], "outcome": "block"},
  {"group": "kind", "name": "a plan that writes nothing is not judged by the failure's kind", "case": {"failure_kind": "rejected"}, "plan": {"disposition": "escalate", "action": null},
   "expect": [["intent", "pass", "NO_WRITE"]], "absent": [["intent", "FHIR_FAILURE_KIND_UNSUPPORTED"]], "outcome": "pass"},
  {"group": "kind", "name": "a message that names a bed is not written as a ward move", "case": {"bed": "B-12"},
   "expect": [["plan_shape", "block", "FHIR_BED_MOVE_UNSUPPORTED"]], "contains": [["plan_shape", "FHIR_BED_MOVE_UNSUPPORTED", "PV1-3"]], "absent": [["plan_shape", "FHIR_PLAN_BOUNDED"]], "outcome": "block"},

  {"group": "personal", "name": "an approval given by the policy", "stage": "dispatch", "approval": {"approver": "policy"},
   "expect": [["authorization", "block", "FHIR_APPROVAL_NOT_PERSONAL"]], "contains": [["authorization", "FHIR_APPROVAL_NOT_PERSONAL", "a policy"]], "absent": [["authorization", "APPROVAL_VALID"]], "outcome": "block"},
  {"group": "personal", "name": "an approval given under an incident's plan", "stage": "dispatch", "approval": {"incident_plan_digest": "sha256:incident"},
   "expect": [["authorization", "block", "FHIR_APPROVAL_NOT_PERSONAL"]], "contains": [["authorization", "FHIR_APPROVAL_NOT_PERSONAL", "an incident"]], "absent": [["authorization", "APPROVAL_INCIDENT_PLAN_CHANGED"]], "outcome": "block"},
  {"group": "personal", "name": "a person's own approval of this case", "stage": "dispatch", "approval": {"approver": "user:ward-lead"},
   "expect": [["authorization", "pass", "APPROVAL_VALID"]], "contains": [["authorization", "APPROVAL_VALID", "user:ward-lead"]], "outcome": "pass"},

  {"group": "expired", "name": "an approval that has expired", "stage": "dispatch", "approval": {"valid_seconds": -60},
   "expect": [["authorization", "block", "APPROVAL_EXPIRED"]], "contains": [["authorization", "APPROVAL_EXPIRED", "expired"]], "absent": [["authorization", "APPROVAL_VALID"]], "outcome": "block"},
  {"group": "expired", "name": "an approval still within its time", "stage": "dispatch", "approval": {"valid_seconds": 600},
   "expect": [["authorization", "pass", "APPROVAL_VALID"]], "outcome": "pass"}
]
}

}
