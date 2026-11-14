/// The gate for a case whose receiver is a FHIR R4 server (CONTRACTS 20). It stands beside Shutter.Operation.Gate and
/// is never a subclass of it: a FHIR case is judged here and nowhere else. It checks, mechanically, what one update of
/// an Encounter's location needs: that one Encounter carries the visit number and belongs to the message's patient,
/// that the record was read whole and can be written conditionally, that nothing at the receiver or in the feed came
/// after the failed message, that the mapped Locations are the ones the site recorded, that the update built from the
/// read stays inside its bounds and, at dispatch, that the record, the Patient and the Locations are still at the
/// versions a person approved against. Each check is pass, block or unknown with a reason code, and an unknown blocks
/// a write as surely as a block does.
/// <p>The work is in two methods so that the table can be tested with no production: Facts makes every read, and
/// Decide gives the rows from those facts alone.</p>
/// <p>No dry run exists for a FHIR server. Every decision says so in its rehearsal row, written or not.</p>
Class Shutter.Operation.FHIRGate Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

/// How old the read made just before the write may be at the dispatch gate, in seconds.
Parameter DISPATCHSECONDS = 120;

/// A literal reference to a Patient, as the reader follows one.
Parameter LITERALPATIENT = "Patient/[A-Za-z0-9.\-]{1,64}";

Method OnGateRequest(request As Shutter.Msg.FHIRGateRequest, Output response As Shutter.Msg.GateResult) As %Status
{
    Set policy = ##class(Shutter.FHIR.Profile).#POLICYVERSION
    Set response = ##class(Shutter.Msg.GateResult).%New()
    Set response.PolicyVersion = policy
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Set response.Error = "Unknown case " _ request.CaseId, response.Outcome = "unknown" Quit $$$OK
    Set plan = $SELECT(request.PlanId = "": "", 1: ##class(Shutter.Store.Plan).%OpenId(request.PlanId))
    If '$ISOBJECT(plan) Set response.Error = "Unknown plan " _ request.PlanId, response.Outcome = "unknown" Quit $$$OK
    If plan.CaseGetObjectId() '= case.%Id() Set response.Error = "Plan " _ request.PlanId _ " is another case's", response.Outcome = "unknown" Quit $$$OK
    If '$ISOBJECT(case.CurrentSnapshot) Set response.Error = "The case has no snapshot", response.Outcome = "unknown" Quit $$$OK

    // Every read, then the rows. A read that fails leaves the outcome unknown and nothing decided.
    Set checks = ""
    Try {
        Set sc = ..Facts(request, case, plan, .facts)
        If $$$ISOK(sc) Set checks = ..Decide(request.Stage, case, plan, .facts)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) || '$ISOBJECT(checks) {
        Set response.Error = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "The FHIR gate gave no checks"), response.Outcome = "unknown"
        Quit $$$OK
    }

    // The outcome is the worst check, answered and stored as the gate does (Shutter.Operation.Gate, lines 386-402 of
    // version 1.4.4).
    Set outcome = "pass"
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) {
        If c.result = "block" Set outcome = "block"
        If (c.result = "unknown") && (outcome '= "block") Set outcome = "unknown"
    }
    Set blocks = ""
    Set iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) { If c.result '= "pass" Set blocks = blocks _ $SELECT(blocks = "": "", 1: ", ") _ c.check _ " " _ c."reason_code" }
    Set text = $CASE(outcome, "pass": "Every check passed", "block": "Blocked: " _ blocks, : "Unknown: " _ blocks) _ " (policy " _ policy _ ", stage " _ request.Stage _ ")"
    Set sc = ##class(Shutter.Store.GateDecision).Create(case, plan, request.Stage, policy, outcome, checks, text, .decision)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc)
    Set response.Outcome = outcome, response.ChecksJSON = checks.%ToJSON(), response.Summary = text
    If $ISOBJECT($GET(decision)) Set response.DecisionId = decision.%Id()
    Do case.Note("artifact", "FHIR gate (" _ request.Stage _ "): " _ text, "system", "gate:" _ response.DecisionId)
    $$$TRACE("FHIR gate " _ request.Stage _ " for " _ case.CaseId _ " plan v" _ plan.Version _ ": " _ outcome)
    Quit $$$OK
}

/// Every read the rows rest on, into <var>facts</var>:
/// <ul>
/// <li>"view": the evidence as a summary. At the proposal it is the summary of the case's current snapshot. At the
/// dispatch its fhir, ward_state and receipt are the projection of the read made just before the write (the
/// Shutter.Msg.FHIRReadResult the request names), and every other key is still the snapshot's.</li>
/// <li>"body": the Encounter as it was read, as characters: the snapshot's sealed read, or the dispatch read's.</li>
/// <li>"entry": the receiver's entry of the site profile, or "".</li>
/// <li>"binding": the plan's Shutter.Store.FHIRBinding, or "".</li>
/// <li>"approval": the Shutter.Store.Approval the request names, or "".</li>
/// <li>"proof": the receiver's Shutter.Store.FHIRProof, or "".</li>
/// <li>"engine": what Shutter.Util.EngineCheck's Read found, or "" for a case with no source header to read it by.</li>
/// <li>"further", "pending": the further messages for the patient and the newer messages of the encounter still
/// pending: the snapshot's at the proposal, read again at the dispatch.</li>
/// <li>"unresolved": whether an earlier update of this case, conditional on the Encounter's ETag as read, has no known
/// outcome.</li>
/// <li>"fresh": at the proposal whether the snapshot is fresh, at the dispatch whether the read is no older than
/// DISPATCHSECONDS.</li>
/// <li>"chain_kind": the request's chain kind, which the later events fall back to when the evidence names none.</li>
/// </ul>
Method Facts(request As Shutter.Msg.FHIRGateRequest, case As Shutter.Store.Case, plan As Shutter.Store.Plan, ByRef facts) As %Status
{
    Kill facts
    Set sc = $$$OK, json = "Shutter.Util.Json"
    Try {
        Set snapshot = case.CurrentSnapshot
        If '$ISOBJECT(snapshot) Set sc = $$$ERROR($$$GeneralError, "The case has no snapshot") Quit
        Set view = snapshot.SummaryObject()
        Set sealed = view.%Get("fhir")
        If '..IsObject(sealed) Set sealed = ""
        Set entry = ##class(Shutter.Store.SiteProfile).Receiver(case.Receiver)
        Set facts("entry") = entry
        Set facts("chain_kind") = request.ChainKind
        Set facts("binding") = ##class(Shutter.Store.FHIRBinding).ForPlan(plan.%Id())
        Set facts("approval") = $SELECT(request.ApprovalId = "": "", 1: ##class(Shutter.Store.Approval).%OpenId(request.ApprovalId))
        Set facts("proof") = ##class(Shutter.Store.FHIRProof).For(case.Receiver)
        // A case with no source header has nothing to read the engine by.
        Set facts("engine") = $SELECT((case.SourceNamespace '= "") && (case.OriginHeaderId '= ""): ##class(Shutter.Util.EngineCheck).Read(case), 1: "")
        If request.Stage = "proposal" {
            Set facts("body") = $SELECT($ISOBJECT(sealed): ##class(Shutter.FHIR.Reader).SealedBody(snapshot), 1: "")
            Set facts("further") = view.%Get("further_messages"), facts("pending") = view.%Get("pending_messages")
            Set facts("fresh") = snapshot.IsFresh()
        } Else {
            // The read made just before the write, projected again; the search alone is still the snapshot's.
            Set read = $SELECT(request.ReadId = "": "", 1: ##class(Shutter.Msg.FHIRReadResult).%OpenId(request.ReadId))
            If '$ISOBJECT(read) Set sc = $$$ERROR($$$GeneralError, "Unknown read " _ request.ReadId) Quit
            If read.Error '= "" Set sc = $$$ERROR($$$GeneralError, "The read before the write failed: " _ read.Error) Quit
            Set parts = $SELECT(read.PartsJSON = "": "", 1: $CLASSMETHOD(json, "Parse", read.PartsJSON))
            If '..IsObject(parts) Set sc = $$$ERROR($$$GeneralError, "The read before the write holds no parts") Quit
            Set priorWard = ##class(Shutter.FHIR.Reader).PriorWard(case)
            Set sentIds = ##class(Shutter.Store.FHIRAttempt).SentOperationIds(case)
            Set projection = ##class(Shutter.FHIR.Reader).Project(parts, entry, case, priorWard, sentIds, sealed)
            If '..IsObject(projection) Set sc = $$$ERROR($$$GeneralError, "The read before the write could not be projected") Quit
            For key = "fhir", "ward_state", "ward_state_http_status", "receipt", "receipt_http_status" {
                Do view.%Remove(key)
                If projection.%GetTypeOf(key) '= "unassigned" Do view.%Set(key, projection.%Get(key))
            }
            Set facts("body") = $CLASSMETHOD(json, "Str", projection, "encounter_body")
            Set facts("further") = ##class(Shutter.Util.FurtherMessages).Find(case)
            Set facts("pending") = ##class(Shutter.Util.ResendGuard).Pending(case)
            Set age = ##class(Shutter.Util.Time).SecondsBetween($CLASSMETHOD(json, "Str", parts, "observed_at"), ##class(Shutter.Util.Time).NowUTC())
            Set facts("fresh") = (age '= "") && (age >= 0) && (age <= ..#DISPATCHSECONDS)
        }
        Set facts("view") = view
        Set etag = $CLASSMETHOD(json, "Str", ..Obj(..Obj(view, "fhir"), "encounter"), "etag")
        Set facts("unresolved") = ##class(Shutter.Store.FHIRAttempt).UnresolvedAt(case, etag)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The rows, in order, from <var>facts</var> alone (Facts lists its keys). <var>stage</var> is "proposal" or
/// "dispatch". A row marked "for a write" below is pass NOT_APPLICABLE for a plan that writes nothing.
/// <ul>
/// <li>identity: one Encounter carries the visit number and belongs to the message's patient.</li>
/// <li>conformance and intent: as the gate judges them, and for a write only a ward move whose delivery failed or is
/// uncertain.</li>
/// <li>enablement, representation, state_transition, ordering, mapping, plan_shape, concurrency, earlier_write,
/// capability, history: for a write.</li>
/// <li>authorization, evidence, catalogue.</li>
/// <li>rehearsal: FHIR_NO_DRY_RUN_SUBSTITUTED, on every decision.</li>
/// </ul>
ClassMethod Decide(stage As %String, case As Shutter.Store.Case, plan As Shutter.Store.Plan, ByRef facts) As %DynamicArray
{
    Set checks = [], json = "Shutter.Util.Json"
    Set view = $GET(facts("view"))
    If '..IsObject(view) Set view = {}
    Set fhir = ..Obj(view, "fhir")
    Set entry = $GET(facts("entry"))
    Set block = ..Obj(entry, "fhir")
    Set binding = $GET(facts("binding")), approval = $GET(facts("approval"))
    Set isWrite = plan.IsWrite(), atProposal = (stage = "proposal")
    Set policy = ##class(Shutter.FHIR.Profile).#POLICYVERSION

    // Identity. What it could not establish (no Encounter read) is what every row that needs the Encounter then says.
    Set noEncounter = ..Identity(checks, case, fhir, block)
    Set enc = ..Obj(fhir, "encounter")

    Do ..Conformance(checks, case, view)
    Do ..Intent(checks, case, plan, view)

    // Enablement: the receiver's entry turns recovery on, as Shutter.FHIR.Profile's Enabled reads it.
    If 'isWrite {
        Do ..NotApplicable(checks, "enablement")
    } ElseIf $ISOBJECT(block) && (block.%GetTypeOf("recovery_enabled") = "boolean") && block.%Get("recovery_enabled") {
        Do ..Check(checks, "enablement", "pass", "FHIR_RECOVERY_ENABLED", "The receiver's entry in the site profile turns recovery on")
    } Else {
        Do ..Check(checks, "enablement", "block", "FHIR_RECOVERY_DISABLED", "The receiver's entry in the site profile does not turn recovery on (fhir.recovery_enabled), so nothing is written to it")
    }

    // Representation: the record was read whole, unlabelled, and with an ETag that names its version.
    If 'isWrite {
        Do ..NotApplicable(checks, "representation")
    } ElseIf noEncounter '= "" {
        Do ..Unread(checks, "representation", noEncounter, "whether the record was read whole")
    } ElseIf $CLASSMETHOD(json, "Bool", enc, "subsetted", 1) {
        Do ..Check(checks, "representation", "block", "FHIR_REPRESENTATION_PARTIAL", "The server returned a reduced copy of the Encounter (marked SUBSETTED); a change built on part of a record would remove the rest")
    } ElseIf $CLASSMETHOD(json, "Bool", enc, "modifier_extension", 1) {
        Do ..Check(checks, "representation", "block", "FHIR_MODIFIER_EXTENSION", "The Encounter carries a modifierExtension, which can change what its other fields mean")
    } ElseIf $CLASSMETHOD(json, "Bool", enc, "narrative", 1) {
        Do ..Check(checks, "representation", "block", "FHIR_NARRATIVE_PRESENT", "The Encounter carries a narrative text, which the server does not regenerate; after the move it would describe the old ward")
    } ElseIf $CLASSMETHOD(json, "Bool", enc, "security", 1) {
        Do ..Check(checks, "representation", "block", "FHIR_RESTRICTED", "The Encounter carries a security label (meta.security)")
    } ElseIf '$CLASSMETHOD(json, "Bool", enc, "etag_usable") {
        Do ..Check(checks, "representation", "block", "FHIR_NO_ETAG", "The read came with no ETag, or one that does not name the version read, so a write could not be made conditional on it")
    } Else {
        Do ..Check(checks, "representation", "pass", "FHIR_REPRESENTATION_WHOLE", "The Encounter was read whole, with an ETag that names version " _ $CLASSMETHOD(json, "Str", enc, "version_id"))
    }

    // State transition: a ward move applies to an Encounter in progress that is not on the target ward already.
    Set message = ..Obj(fhir, "message")
    Set priorWard = $CLASSMETHOD(json, "Str", message, "prior_ward"), targetWard = $CLASSMETHOD(json, "Str", message, "target_ward")
    If 'isWrite {
        Do ..NotApplicable(checks, "state_transition")
    } ElseIf noEncounter '= "" {
        Do ..Unread(checks, "state_transition", noEncounter, "the Encounter's status and ward")
    } ElseIf $CLASSMETHOD(json, "Str", enc, "status") '= "in-progress" {
        Do ..Check(checks, "state_transition", "block", "FHIR_STATUS_NOT_IN_PROGRESS", "The Encounter's status is '" _ $CLASSMETHOD(json, "Str", enc, "status") _ "', not in-progress, so a ward move no longer applies to it")
    } ElseIf ..OnWard(enc, targetWard) {
        Do ..Check(checks, "state_transition", "block", "FHIR_ALREADY_THERE", "The Encounter already shows the patient on " _ targetWard _ ", the ward the message moves them to. Who made that change is not known, so nothing is sent")
    } Else {
        Do ..Check(checks, "state_transition", "pass", "TRANSITION_ALLOWED", "The Encounter is in progress and not on " _ $SELECT(targetWard = "": "the target ward", 1: targetWard))
    }

    // Ordering: the engine's hands, the feed's later messages, then the receiver's own later moves.
    If 'isWrite {
        Do ..NotApplicable(checks, "ordering")
    } Else {
        Do checks.%Push(..EngineRow($GET(facts("engine"))))
        Do ..Feed(checks, stage, case, view, $GET(facts("further")), $GET(facts("pending")), $GET(facts("chain_kind")))
        If noEncounter '= "" {
            Do ..Unread(checks, "ordering", noEncounter, "what the Encounter's locations show after the event")
        } Else {
            Do ..ReceiverOrder(checks, case, enc, priorWard)
        }
    }

    // Mapping: both wards have a Location in the map, and every mapped Location was read, is active and carries the
    // identifier the site recorded for it.
    If 'isWrite {
        Do ..NotApplicable(checks, "mapping")
    } Else {
        Do ..Mapping(checks, fhir, block, priorWard, targetWard)
    }

    // Plan shape: the update built from this read, by the builder every stage and the binding's seal use.
    Set prepared = ""
    If 'isWrite {
        Do ..NotApplicable(checks, "plan_shape")
    } ElseIf noEncounter '= "" {
        Do ..Unread(checks, "plan_shape", noEncounter, "the update, which is built from the Encounter as read")
    } ElseIf $GET(facts("body")) = "" {
        Do ..Check(checks, "plan_shape", "unknown", "FHIR_RECEIVER_UNREADABLE", "The Encounter as it was read is not on file with the evidence, so the update could not be built; fresh evidence reads it again")
    } Else {
        Set code = ##class(Shutter.FHIR.Proposal).Prepare(case, plan.Digest, fhir, facts("body"), entry, .prepared)
        If code '= "" {
            // A code another row already gave is not repeated.
            If '..Has(checks, code) Do ..Check(checks, "plan_shape", "block", code, "The update was not built: " _ $CLASSMETHOD(json, "Str", prepared, "reason", "refused") _ $SELECT($CLASSMETHOD(json, "Str", prepared, "path") '= "": " at " _ $CLASSMETHOD(json, "Str", prepared, "path"), 1: ""))
        } ElseIf 'atProposal && $ISOBJECT(binding) && ($CLASSMETHOD(json, "Str", prepared, "body_digest") '= binding.ApprovedBodyDigest) {
            Do ..Check(checks, "plan_shape", "block", "FHIR_BODY_CHANGED", "The update built from the read made just before the write is not the one the person approved (its digest is " _ $EXTRACT($CLASSMETHOD(json, "Str", prepared, "body_digest"), 1, 12) _ ", the approved one's " _ $EXTRACT(binding.ApprovedBodyDigest, 1, 12) _ ")")
        } Else {
            Do ..Check(checks, "plan_shape", "pass", "FHIR_PLAN_BOUNDED", "The update closes the open location, opens the target one and adds its marker, and changes nothing else")
        }
    }

    // Concurrency: at dispatch the Encounter, the Patient and every bound Location are at the versions the binding
    // sealed. ETags are compared as strings, exactly.
    If 'isWrite {
        Do ..NotApplicable(checks, "concurrency")
    } ElseIf atProposal {
        Do ..Check(checks, "concurrency", "pass", "NOT_YET_REQUIRED", "The versions are sealed once this gate passes and compared at dispatch")
    } Else {
        Do ..Concurrency(checks, fhir, binding)
    }

    // An earlier update of this case on this same version that may yet land.
    If 'isWrite {
        Do ..NotApplicable(checks, "earlier_write")
    } ElseIf +$GET(facts("unresolved")) {
        Do ..Check(checks, "earlier_write", "unknown", "FHIR_EARLIER_WRITE_UNRESOLVED", "An earlier update of this case, conditional on this same version, has no known outcome and may yet land. Nothing is sent until the record moves on or a person settles it")
    } Else {
        Do ..Check(checks, "earlier_write", "pass", "FHIR_NO_EARLIER_WRITE", "No earlier update of this case is outstanding on this version")
    }

    // Capability: what the server states now, and the conformance run recorded for that same software.
    If 'isWrite {
        Do ..NotApplicable(checks, "capability")
    } Else {
        Do ..Capability(checks, fhir, $GET(facts("proof")))
    }

    // History: read whole, its newest version the one read, and no version carrying this case's marker.
    Set hist = ..Obj(fhir, "history")
    If 'isWrite {
        Do ..NotApplicable(checks, "history")
    } ElseIf noEncounter '= "" {
        Do ..Unread(checks, "history", noEncounter, "the Encounter's history")
    } ElseIf (+$CLASSMETHOD(json, "Str", hist, "http_status", 0) '= 200) || $CLASSMETHOD(json, "Bool", hist, "next", 1) {
        Do ..Check(checks, "history", "unknown", "FHIR_HISTORY_UNAVAILABLE", "The Encounter's history could not be read whole (" _ $SELECT(+$CLASSMETHOD(json, "Str", hist, "http_status", 0) = 200: "it came in pages", +$CLASSMETHOD(json, "Str", hist, "http_status", 0): "HTTP " _ +$CLASSMETHOD(json, "Str", hist, "http_status", 0), 1: "no answer") _ ")")
    } Else {
        Set head = $CLASSMETHOD(json, "Str", hist, "head_version_id"), read = $CLASSMETHOD(json, "Str", enc, "version_id")
        Set marked = $CLASSMETHOD(json, "Str", hist, "sent_marker_version")
        If (head = "") || (head '= read) Do ..Check(checks, "history", "block", "FHIR_HISTORY_HEAD_DIFFERS", "The newest version in the Encounter's history is " _ $SELECT(head = "": "not named", 1: head) _ ", and the version read is " _ read)
        If marked '= "" Do ..Check(checks, "history", "block", "FHIR_ALREADY_WRITTEN", "Version " _ marked _ " in the Encounter's history carries the marker of an update this case already sent. Nothing is sent again")
        If (head '= "") && (head = read) && (marked = "") Do ..Check(checks, "history", "pass", "FHIR_HISTORY_READ", "The history was read whole, its newest version is the one read (" _ read _ "), and no version carries this case's marker")
    }

    // Authorization: at dispatch, a person's own approval of this plan, tied to the sealed binding.
    If atProposal {
        Do ..Check(checks, "authorization", "pass", "NOT_YET_REQUIRED", "Authorization is checked at dispatch")
    } ElseIf '$ISOBJECT(approval) {
        Do ..Check(checks, "authorization", "block", "NO_APPROVAL", "No approval for this plan")
    } ElseIf (approval.Approver = "policy") || (approval.IncidentPlanDigest '= "") {
        // The named line that refuses automatic, tier and incident release.
        Do ..Check(checks, "authorization", "block", "FHIR_APPROVAL_NOT_PERSONAL", "A FHIR update goes only on a person's approval of this one case; this approval came from " _ $SELECT(approval.Approver = "policy": "a policy", 1: "an incident"))
    } Else {
        Set why = approval.InvalidReason(plan, case.CurrentSnapshot, policy, "", "")
        If why '= "" {
            Do ..Check(checks, "authorization", "block", "APPROVAL_" _ $ZCONVERT(why, "U"), "The approval no longer authorises this dispatch: " _ why)
        } ElseIf isWrite && ('$ISOBJECT(binding) || (binding.ApprovalId = "") || (binding.ApprovalId '= approval.%Id())) {
            Do ..Check(checks, "authorization", "block", "FHIR_NO_BINDING", "The approval is not tied to a sealed record of what it approved (the version, the body, the Locations), so it authorises nothing")
        } Else {
            Do ..Check(checks, "authorization", "pass", "APPROVAL_VALID", "Approved by " _ approval.Approver _ " for plan digest " _ $EXTRACT(approval.PlanDigest, 1, 19))
        }
    }

    // Evidence: the snapshot at the proposal, the read made just before the write at dispatch.
    Set fresh = +$GET(facts("fresh"))
    If atProposal {
        Set snapshot = case.CurrentSnapshot
        Do ..Check(checks, "evidence", $SELECT(fresh: "pass", 1: "unknown"), $SELECT(fresh: "FRESH", 1: "STALE_EVIDENCE"), $SELECT('$ISOBJECT(snapshot): $SELECT(fresh: "The snapshot's observations are fresh", 1: "The snapshot's observations have expired"), fresh: "Observed at " _ snapshot.TakenAt _ ", fresh until " _ snapshot.FreshUntil, 1: "The snapshot's observations expired at " _ snapshot.FreshUntil))
    } Else {
        Do ..Check(checks, "evidence", $SELECT(fresh: "pass", 1: "unknown"), $SELECT(fresh: "FRESH", 1: "STALE_EVIDENCE"), $SELECT(fresh: "The read before the write is no older than " _ ..#DISPATCHSECONDS _ " seconds", 1: "The read before the write is older than " _ ..#DISPATCHSECONDS _ " seconds, or carries no time"))
    }

    Do ..Catalogue(checks, case, plan, view, isWrite)

    // Rehearsal: no dry run exists for this receiver, and every decision says what stands in its place.
    Do ..Check(checks, "rehearsal", "pass", "FHIR_NO_DRY_RUN_SUBSTITUTED", $SELECT(isWrite: "No dry run exists for this receiver. Substituted: a complete versioned read, a bounded change, If-Match on the version read, this case's own approval by a person, and a search of the returned history for the marked version, read back by id when the answer named it.", 1: "No dry run exists for this receiver. This plan sends nothing."))
    Quit checks
}

/// The identity row. Returns "" once one Encounter was read (whatever the row then says of its patient), else the
/// reason code that says why none was: the rows that need the Encounter give that code as an unknown.
ClassMethod Identity(checks As %DynamicArray, case As Shutter.Store.Case, fhir As %DynamicObject, block As %DynamicObject) As %String [ Private ]
{
    Set json = "Shutter.Util.Json"
    If '$ISOBJECT(fhir) {
        Do ..Check(checks, "identity", "block", "FHIR_ENCOUNTER_NOT_FOUND", $SELECT((case.EncounterId = "") || (case.EncounterId = "-"): "The message names no visit number, so there is no Encounter to look for", 1: "The evidence holds no read of the FHIR server for visit number " _ case.EncounterId))
        Quit "FHIR_ENCOUNTER_NOT_FOUND"
    }
    Set search = ..Obj(fhir, "search"), enc = ..Obj(fhir, "encounter")
    Set searched = +$CLASSMETHOD(json, "Str", search, "http_status", 0)
    If (searched '= 200) && (searched '= 404) {
        Do ..Check(checks, "identity", "unknown", "FHIR_RECEIVER_UNREADABLE", "The search for the Encounter was not answered by the FHIR server (" _ $SELECT(searched: "HTTP " _ searched, 1: "no answer it could be trusted as") _ ")")
        Quit "FHIR_RECEIVER_UNREADABLE"
    }
    Set matches = +$CLASSMETHOD(json, "Str", search, "matches", 0)
    If (searched = 200) && (matches > 1) {
        Do ..Check(checks, "identity", "block", "FHIR_ENCOUNTER_AMBIGUOUS", matches _ " Encounters carry visit number " _ case.EncounterId _ ", so which record the message meant is not known")
        Quit "FHIR_ENCOUNTER_AMBIGUOUS"
    }
    If (searched = 200) && $CLASSMETHOD(json, "Bool", search, "next", 1) {
        Do ..Check(checks, "identity", "unknown", "FHIR_ENCOUNTER_AMBIGUOUS", "The search for visit number " _ case.EncounterId _ " came in pages, so whether one Encounter alone carries it is not known")
        Quit "FHIR_ENCOUNTER_AMBIGUOUS"
    }
    If (searched = 404) || (matches < 1) {
        Do ..Check(checks, "identity", "block", "FHIR_ENCOUNTER_NOT_FOUND", "No Encounter carries visit number " _ case.EncounterId _ " under the identifier system the site profile names")
        Quit "FHIR_ENCOUNTER_NOT_FOUND"
    }
    Set status = +$CLASSMETHOD(json, "Str", enc, "http_status", 0)
    If status = 404 {
        Do ..Check(checks, "identity", "block", "FHIR_ENCOUNTER_NOT_FOUND", "The Encounter the search named is no longer at the FHIR server")
        Quit "FHIR_ENCOUNTER_NOT_FOUND"
    }
    If status '= 200 {
        Do ..Check(checks, "identity", "unknown", "FHIR_RECEIVER_UNREADABLE", "The Encounter could not be read (" _ $SELECT(status: "HTTP " _ status, 1: "no answer it could be trusted as") _ ")")
        Quit "FHIR_RECEIVER_UNREADABLE"
    }

    // One Encounter was read. Whose it is:
    Set authority = $CLASSMETHOD(json, "Str", ..Obj(block, "patient_identifier"), "hl7_authority")
    Set subject = $CLASSMETHOD(json, "Str", enc, "subject")
    Set pat = ..Obj(fhir, "patient")
    Set patStatus = +$CLASSMETHOD(json, "Str", pat, "http_status", 0), patRef = $CLASSMETHOD(json, "Str", pat, "reference")
    If (authority = "") || (case.PatientIdAuthority '= authority) {
        Do ..Check(checks, "identity", "block", "FHIR_IDENTIFIER_UNMAPPED", "The message's patient identifier comes from assigning authority '" _ case.PatientIdAuthority _ "', which is not the one the site profile maps to the FHIR identifier system" _ $SELECT(authority = "": "", 1: " (" _ authority _ ")"))
    } ElseIf '$CLASSMETHOD(json, "Bool", enc, "identifier_ok") {
        Do ..Check(checks, "identity", "block", "FHIR_IDENTIFIER_UNMAPPED", "The Encounter read does not carry visit number " _ case.EncounterId _ " under the mapped identifier system, or carries another beside it")
    } ElseIf '$MATCH(subject, ..#LITERALPATIENT) {
        Do ..Check(checks, "identity", "block", "FHIR_SUBJECT_UNRESOLVED", "The Encounter's subject is not a literal reference to a Patient")
    } ElseIf patStatus '= 200 {
        Do ..Check(checks, "identity", "unknown", "FHIR_SUBJECT_UNRESOLVED", "The Encounter's Patient " _ subject _ " could not be read (" _ $SELECT(patStatus: "HTTP " _ patStatus, 1: "no answer it could be trusted as") _ ")")
    } ElseIf (patRef '= "") && (patRef '= subject) {
        Do ..Check(checks, "identity", "unknown", "FHIR_SUBJECT_UNRESOLVED", "The Patient that was read (" _ patRef _ ") is not the Encounter's subject (" _ subject _ "), so that Patient has not been read")
    } ElseIf '$CLASSMETHOD(json, "Bool", pat, "identifier_ok") {
        Do ..Check(checks, "identity", "block", "FHIR_PATIENT_MISMATCH", "The Encounter belongs to a Patient who does not carry the message's patient identifier " _ case.PatientId)
    } ElseIf $CLASSMETHOD(json, "Bool", pat, "link", 1) || '$CLASSMETHOD(json, "Bool", pat, "active") {
        Do ..Check(checks, "identity", "block", "FHIR_PATIENT_LINKED", "The Patient record " _ $SELECT($CLASSMETHOD(json, "Bool", pat, "link", 1): "is linked to another", 1: "is not active") _ ", which often means a merge. A person decides")
    } Else {
        Do ..Check(checks, "identity", "pass", "FHIR_IDENTITY_MATCHES", "One Encounter carries visit number " _ case.EncounterId _ ", and its Patient " _ subject _ " carries " _ case.PatientId _ " (" _ case.PatientIdAuthority _ ")")
    }
    Quit ""
}

/// The conformance rows, as the gate gives them (Shutter.Operation.Gate, lines 51-65 of version 1.4.4).
ClassMethod Conformance(checks As %DynamicArray, case As Shutter.Store.Case, view As %DynamicObject) [ Private ]
{
    Set validation = view.%Get("validation")
    Set parsed = ##class(Shutter.Util.Json).Bool(validation, "parsed")
    If (case.FailureKind = "unmappable") || ($EXTRACT(case.OperationKey, 1, 9) = "UNMAPPED^") Do ..Check(checks, "conformance", "block", "UNMAPPABLE", $SELECT(case.NotModelled(): "There is no operation to resend. ", 1: "The message could not be mapped to an operation for the downstream system: ") _ $EXTRACT(##class(Shutter.Store.Case).ShownFailureText(case.FailureText), 1, 300))
    If (case.FailureKind = "unreadable") && (case.HeldSchema '= "") && (case.SourceNamespace '= "") && $ISOBJECT(validation) && ##class(Shutter.Util.Json).Bool(validation, "schema_known", 1) && '##class(Shutter.Util.Schemas).KnownIn(case.SourceNamespace, case.HeldSchema) {
        Do ..Check(checks, "conformance", "block", "SCHEMA_UNKNOWN", "The message was held in " _ case.SourceNamespace _ ": its schema category " _ case.HeldSchema _ " is not loaded there, so the production that received it cannot read it; import the schema in that namespace and set the inbound item's category, and the case is released")
    }
    If $ISOBJECT(validation) && validation.%IsDefined("schema_known") && '##class(Shutter.Util.Json).Bool(validation, "schema_known", 1) {
        Do ..Check(checks, "conformance", "block", "SCHEMA_UNKNOWN", "The message's schema category " _ ##class(Shutter.Util.Json).Str(validation, "schema_category", "(none)") _ " is not loaded in this namespace, so it could not be validated" _ ##class(Shutter.Util.SecondParser).Verdict(validation) _ "; " _ ##class(Shutter.Util.Json).Str(validation, "schema_fix", "import the schema and reinvestigate"))
    } Else {
        Do ..Check(checks, "conformance", $SELECT(parsed: "pass", 1: "block"), $SELECT(parsed: "PARSED", 1: "PARSE_FAILED"), $SELECT(parsed: "The message parses against its schema", 1: "The message does not parse: " _ ##class(Shutter.Util.Json).Str(validation, "error") _ ##class(Shutter.Util.SecondParser).Verdict(validation)))
    }
}

/// The intent rows, as the gate gives them (Shutter.Operation.Gate, lines 70-99 of version 1.4.4) without its two
/// lines about a receiver the profile does not describe or does not model, and with two of this gate's own for a
/// write: only a ward move, and only one whose delivery failed or is uncertain.
ClassMethod Intent(checks As %DynamicArray, case As Shutter.Store.Case, plan As Shutter.Store.Plan, view As %DynamicObject) [ Private ]
{
    Set gate = "Shutter.Operation.Gate"
    If case.FailureKind = "withheld" Do ..Check(checks, "intent", "block", $SELECT(case.Event = "merge": "MERGE_WITHHELD", 1: "CANCEL_UNSUPPORTED"), $SELECT(case.Event = "merge": "Withheld by the site's policy: a merge goes to the PAS team", 1: "Withheld: the receiver cannot reverse the " _ $CLASSMETHOD(gate, "Reversed", case.Event)))
    Set okDisp = $LISTFIND($LISTBUILD("resend", "reconcile", "superseded", "more_evidence", "escalate"), plan.Disposition) > 0
    If 'okDisp {
        Do ..Check(checks, "intent", "block", "UNKNOWN_DISPOSITION", "Disposition '" _ plan.Disposition _ "' is not one the gate knows")
    } ElseIf plan.IsWrite() {
        If (case.FailureKind '= "withheld") && (case.Event = "merge") {
            Set siteAllows = ##class(Shutter.Store.SiteProfile).MergesAllowed(), receiverTakes = ##class(Shutter.Store.SiteProfile).ReceiverFlag(case.Receiver, "merges")
            If '(siteAllows && receiverTakes) Do ..Check(checks, "intent", "block", "MERGE_WITHHELD", "A merge is not sent through Shutter: " _ $SELECT('siteAllows: "the site's policy forbids merges (merges: forbidden)", 1: "the receiver's entry does not take merges") _ "; the PAS team decides it")
        } ElseIf (case.FailureKind '= "withheld") && ($EXTRACT(case.Event, 1, 7) = "cancel_") {
            If '##class(Shutter.Store.SiteProfile).ReceiverFlag(case.Receiver, "cancels") Do ..Check(checks, "intent", "block", "CANCEL_UNSUPPORTED", "The receiver's entry says it cannot reverse a " _ $CLASSMETHOD(gate, "Reversed", case.Event) _ " (cancels: false)")
        }
        If case.Event '= "transfer" Do ..Check(checks, "intent", "block", "FHIR_EVENT_UNSUPPORTED", "Over FHIR Shutter makes one kind of change, a ward move on an existing Encounter; this message's event is '" _ case.Event _ "'")
        If (case.FailureKind '= "delivery_failed") && (case.FailureKind '= "uncertain_outcome") Do ..Check(checks, "intent", "block", "FHIR_FAILURE_KIND_UNSUPPORTED", "Over FHIR Shutter repairs only a delivery that failed or whose outcome is uncertain; this message's failure is '" _ case.FailureKind _ "', so the receiver or the site already said no to it")
        Set exact = (plan.OperationKey = case.OperationKey)
        Set op = view.%Get("operation")
        Set digestOk = (plan.PayloadDigest = "") || (plan.PayloadDigest = ##class(Shutter.Util.Json).Str(op, "payload_digest"))
        Do ..Check(checks, "intent", $SELECT(exact && digestOk: "pass", 1: "block"), $SELECT(exact && digestOk: "EXACT_OPERATION", 'exact: "DIFFERENT_OPERATION", 1: "PAYLOAD_CHANGED"), $SELECT('exact || 'digestOk: "The plan's action is not the case's operation unchanged", 1: "The plan makes the one change the failed message asked for; the HL7 message is not sent again"))
    } Else {
        Do ..Check(checks, "intent", "pass", "NO_WRITE", "The plan writes nothing to the receiver")
    }
}

/// The ordering row for what the engine shows about the case's message, from what Shutter.Util.EngineCheck's Read
/// found. No source header, an item that is no stock HL7 TCP operation and a subclass of one are each unknown here,
/// where the gate passes or reads on. Otherwise the row is EngineCheck's Judge, with two refusals laid over a pass,
/// because the FHIR update is a second route to a system the engine can still reach: a header the engine delivered,
/// and a header it holds suspended, which anyone can send again after the update. Settle is never called.
ClassMethod EngineRow(engine As %DynamicObject) As %DynamicObject
{
    Set json = "Shutter.Util.Json"
    If '..IsObject(engine) Quit ..Row("ordering", "unknown", "FHIR_ENGINE_NOT_IN_SCOPE", "The case has no source header to read the engine by, so whether the engine is still trying this message cannot be read. Unknown is not nothing pending")
    Set scope = $CLASSMETHOD(json, "Str", engine, "scope")
    If scope = "no" Quit ..Row("ordering", "unknown", "FHIR_ENGINE_NOT_IN_SCOPE", "The delivery that failed did not go through a stock HL7 TCP operation, so whether the engine is still trying it cannot be read. Unknown is not nothing pending")
    If scope = "base" Quit ..Row("ordering", "unknown", "FHIR_ENGINE_SUBCLASS_UNPROVEN", "The delivery went through a subclass of the stock HL7 TCP operation. What the engine's record proves was measured for the stock class only")
    Set judged = ""
    Try {
        Set judged = ##class(Shutter.Util.EngineCheck).Judge(engine)
    } Catch ex {
        Set judged = ""
    }
    If '..IsObject(judged) Quit ..Row("ordering", "unknown", "ENGINE_UNREADABLE", "The engine's record of this message could not be read, so whether it is still trying it is not known. Nothing is sent")
    Set result = $CLASSMETHOD(json, "Str", judged, "result"), code = $CLASSMETHOD(json, "Str", judged, "reason_code"), detail = $CLASSMETHOD(json, "Str", judged, "detail")
    If result '= "pass" Quit ..Row("ordering", $SELECT(result = "block": "block", 1: "unknown"), code, detail)
    Set headers = engine.%Get("headers"), delivered = "", suspended = ""
    If $ISOBJECT(headers) && headers.%IsA("%Library.DynamicArray") {
        Set iter = headers.%GetIterator()
        While iter.%GetNext(.i, .h) {
            Continue:'..IsObject(h)
            If ($CLASSMETHOD(json, "Str", h, "custody") = "delivered") && (delivered = "") Set delivered = $CLASSMETHOD(json, "Str", h, "headerId", "?")
            If ($CLASSMETHOD(json, "Str", h, "status") = "Suspended") && (suspended = "") Set suspended = $CLASSMETHOD(json, "Str", h, "headerId", "?")
        }
    }
    If delivered '= "" Quit ..Row("ordering", "block", "FHIR_ENGINE_DELIVERED", "The engine delivered this message over HL7 (header " _ delivered _ "). Whatever the receiver then answered, it was handed the move once, so it is not written again over FHIR")
    If suspended '= "" Quit ..Row("ordering", "block", "FHIR_ENGINE_HOLDS_SUSPENDED", "The engine holds this message suspended (header " _ suspended _ "), and anyone can send it again. Discard it in the source production, then reinvestigate")
    Quit ..Row("ordering", "pass", code, detail)
}

/// The ordering rows the feed gives a write: further messages for the patient, a newer message of the encounter still
/// pending, and a later event. Copied from Shutter.Operation.Gate, lines 132-149 and 155-165 of version 1.4.4, whose
/// class is not edited; <var>further</var> and <var>pending</var> come from the facts in place of its reads.
ClassMethod Feed(checks As %DynamicArray, stage As %String, case As Shutter.Store.Case, view As %DynamicObject, further, pending, chainKind As %String) [ Private ]
{
    If ##class(Shutter.Util.FurtherMessages).Unreadable(further) {
        Do ..Check(checks, "ordering", "block", "PATIENT_UNREADABLE", "The case's patient identifier could not be read, so what else has happened to this patient is not known; a person decides")
    } ElseIf ##class(Shutter.Util.FurtherMessages).Released(case, further) {
        Do ..Check(checks, "ordering", "pass", "FURTHER_MOVEMENT_RELEASED", "Another visit's movement, released by a person who read these rows; this read gives the same ones. " _ ##class(Shutter.Util.FurtherMessages).Describe(case, further))
    } ElseIf ##class(Shutter.Util.FurtherMessages).Count(further, "stops") > 0 {
        Do ..Check(checks, "ordering", "block", "FURTHER_MOVEMENT", ##class(Shutter.Util.FurtherMessages).Describe(case, further) _ ". Nothing is sent; a person reads both and decides" _ $SELECT(case.FurtherReleaseJSON '= "": ". An earlier release no longer holds: these aren't the rows that person read", 1: ""))
    } ElseIf ##class(Shutter.Util.FurtherMessages).Unread(further) '= "" {
        Do ..Check(checks, "ordering", "block", "FURTHER_NOT_READ", "Further messages for this patient could not all be read: " _ ##class(Shutter.Util.FurtherMessages).Unread(further) _ ". Nothing is sent until they can be, or a person decides")
    } ElseIf (stage '= "proposal") && (##class(Shutter.Util.FurtherNew).Rows(further, view.%Get("further_messages")).%Size() > 0) {
        Do ..Check(checks, "ordering", "unknown", "FURTHER_MOVEMENT_NEW", ##class(Shutter.Util.FurtherNew).Describe(case, further, view.%Get("further_messages")) _ ". Nothing is sent on this approval: the evidence is read again and the plan made afresh with it shown, or a person decides")
    } ElseIf $ISOBJECT(further) {
        Do ..Check(checks, "ordering", "pass", "NO_FURTHER_MOVEMENT", $SELECT(##class(Shutter.Util.FurtherMessages).Count(further, "shows") > 0: "No further message stops this write for this patient; " _ ##class(Shutter.Util.FurtherMessages).Count(further, "shows") _ " other message(s) on file, shown on the plan", 1: "No further in-patient movement for this patient"))
    }
    If $ISOBJECT(pending) && (pending.%Size() > 0) Do ..Check(checks, "ordering", "block", "NEWER_MESSAGE_PENDING", "A newer message of this encounter is pending in Shutter: " _ ##class(Shutter.Util.ResendGuard).Describe(pending) _ ". The resend waits for its delivery and the case is planned again on fresh evidence")

    // The event's time and the later events, by the matcher's own reading and with the chain kind the evidence used.
    Set cat = view.%Get("catalogue"), conds = $SELECT($ISOBJECT(cat): cat.%Get("conditions"), 1: "")
    Set eventTime = $SELECT($ISOBJECT(conds): ##class(Shutter.Util.Json).Str(conds, "event_time"), 1: "")
    Set timeDoubt = (eventTime '= "") && (eventTime '= "plausible")
    Set whose = $SELECT(eventTime = "later_event_future": "A later event's time", 1: "The event's time")
    Set kind = $SELECT($ISOBJECT(conds): ##class(Shutter.Util.Json).Str(conds, "chain"), 1: "")
    If kind = "" Set kind = chainKind
    Set superseding = ..Superseding(view, case, kind, .delivered)
    If timeDoubt {
        Do ..Check(checks, "ordering", "block", "EVENT_TIME_IMPLAUSIBLE", whose _ " is not plausible (" _ eventTime _ "): " _ $CASE(eventTime, "before_admission": "it precedes the admission", "future": "it lies in the future", "far_from_recorded": "it is more than a day from when the event was recorded", "clock_change": "it lies within an hour of a clock change and came without an offset", "later_event_future": "it lies in the future, so it cannot settle the order", : eventTime) _ "; a person decides")
    } ElseIf superseding = "" {
        Do ..Check(checks, "ordering", "pass", "NO_LATER_EVENT", "No later transfer or discharge was applied for this encounter, nor a later cancel, merge or admission")
    } ElseIf delivered {
        Do ..Check(checks, "ordering", "block", "SUPERSEDED_BY_LATER_EVENT", "A later event was applied: " _ superseding)
    } Else {
        Do ..Check(checks, "ordering", "block", "SUPERSEDED_BY_LATER_EVENT", "A later movement was sent after it: " _ superseding)
    }
}

/// A later event that supersedes the case's operation, described, or "". Copied from Shutter.Operation.Gate's
/// Superseding, lines 510-527 of version 1.4.4, as it reads for a write: a later applied transfer, discharge, cancel,
/// merge or admission supersedes, and one whose time is not plausible supersedes nothing.
ClassMethod Superseding(view As %DynamicObject, case As Shutter.Store.Case, chainKind As %String, Output delivered As %Boolean) As %String [ Private ]
{
    Set found = "", delivered = 1
    Set later = ##class(Shutter.Catalogue.Matcher).Later(view, case, chainKind)
    Set words = $LISTBUILD("transfer", "discharge", "cancelled", "cancel_other", "merge", "admit")
    For pass = $LISTBUILD("timeline", 1), $LISTBUILD("history", 1), $LISTBUILD("timeline", 0) {
        Set from = $LIST(pass, 1), want = $LIST(pass, 2)
        Set iter = later.%GetIterator()
        While iter.%GetNext(.i, .ev) {
            Continue:((ev.from '= from) || (ev.delivered '= want) || 'ev.plausible)
            Continue:'$LISTFIND(words, ev.word)
            Set found = ##class(Shutter.Catalogue.Matcher).Describe(ev)
            Set delivered = want
        }
        Quit:found'=""
    }
    Quit found
}

/// The ordering rows the receiver's own record gives a write: a location entry whose start cannot be ordered against
/// the event time (unknown), one that starts at or after it (block), and an open location that is not the ward the
/// message says the patient came from (block; unknown when the message names none). Each that applies is given.
ClassMethod ReceiverOrder(checks As %DynamicArray, case As Shutter.Store.Case, enc As %DynamicObject, priorWard As %String) [ Private ]
{
    Set json = "Shutter.Util.Json", before = checks.%Size()
    Set locations = enc.%Get("locations")
    If '$ISOBJECT(locations) || 'locations.%IsA("%Library.DynamicArray") {
        Do ..Check(checks, "ordering", "unknown", "FHIR_RECEIVER_UNREADABLE", "The evidence does not list the Encounter's locations, so what came after the event at the receiver is not known")
        Quit
    }
    Set event = ##class(Shutter.Util.Time).FromFHIR(case.EventTime, .eventSeconds)
    Set unreadable = "", later = "", open = 0, openWard = ""
    Set iter = locations.%GetIterator()
    While iter.%GetNext(.i, .l) {
        Continue:'..IsObject(l)
        Set start = $CLASSMETHOD(json, "Str", l, "start"), reference = $CLASSMETHOD(json, "Str", l, "reference", "an entry with no reference")
        If ##class(Shutter.Util.Time).FromFHIR(start, .seconds) = "" {
            Set:unreadable="" unreadable = reference _ $SELECT(start = "": " has no start", 1: " starts at '" _ start _ "'")
        } ElseIf (event '= "") && (seconds >= eventSeconds) {
            Set:later="" later = reference _ " starts at " _ start
        }
        If ..IsOpen(l) Set open = open + 1, openWard = $CLASSMETHOD(json, "Str", l, "ward")
    }
    If event = "" Do ..Check(checks, "ordering", "unknown", "FHIR_TIME_UNREADABLE", "The message's event time '" _ case.EventTime _ "' is not a time with an offset, so the Encounter's locations cannot be ordered against it")
    If (event '= "") && (unreadable '= "") Do ..Check(checks, "ordering", "unknown", "FHIR_TIME_UNREADABLE", "A location entry's start is not a time with an offset that can be ordered against the event time: " _ unreadable)
    If later '= "" Do ..Check(checks, "ordering", "block", "FHIR_LATER_MOVE_AT_RECEIVER", "The Encounter shows a location that starts at or after the failed message's event time (" _ case.EventTime _ "): " _ later _ ". Sending the older move would undo it")
    If priorWard = "" {
        Do ..Check(checks, "ordering", "unknown", "FHIR_PRIOR_LOCATION_DIFFERS", "The message names no ward the patient came from, so the Encounter's open location cannot be compared with it")
    } ElseIf (open '= 1) || (openWard '= priorWard) {
        Do ..Check(checks, "ordering", "block", "FHIR_PRIOR_LOCATION_DIFFERS", "The message says the patient came from " _ priorWard _ ", and the Encounter " _ $SELECT(open = 0: "has no open location", open > 1: "has " _ open _ " open locations", openWard = "": "is open at a Location the site's map does not hold", 1: "is open on " _ openWard))
    }
    If checks.%Size() = before Do ..Check(checks, "ordering", "pass", "FHIR_ORDER_HOLDS", "Every location of the Encounter starts before the event time, and its one open location is " _ priorWard _ ", the ward the message says the patient came from")
}

/// The mapping rows: a ward of the message with no Location in the map (block), a mapped Location that was not read
/// (unknown), and one that is not active or does not carry the identifier the site recorded (block).
ClassMethod Mapping(checks As %DynamicArray, fhir As %DynamicObject, block As %DynamicObject, priorWard As %String, targetWard As %String) [ Private ]
{
    Set json = "Shutter.Util.Json", before = checks.%Size()
    Set unmapped = ""
    For ward = priorWard, targetWard {
        If '$ISOBJECT(##class(Shutter.FHIR.Profile).LocationOf(block, ward)) Set unmapped = unmapped _ $SELECT(unmapped = "": "", 1: ", ") _ $SELECT(ward = "": "(no ward named)", 1: ward)
    }
    If unmapped '= "" Do ..Check(checks, "mapping", "block", "FHIR_LOCATION_UNMAPPED", "No Location in the site profile's map for: " _ unmapped)
    // Every map entry's Location, as it was read.
    Set map = $SELECT($ISOBJECT(block): block.%Get("location_map"), 1: ""), reads = $SELECT($ISOBJECT(fhir): fhir.%Get("locations"), 1: "")
    Set unread = "", wrong = ""
    If $ISOBJECT(map) && map.%IsA("%Library.DynamicArray") {
        Set iter = map.%GetIterator()
        While iter.%GetNext(.i, .m) {
            Continue:'..IsObject(m)
            Set reference = $CLASSMETHOD(json, "Str", m, "location"), read = ..ByReference(reads, reference)
            If +$CLASSMETHOD(json, "Str", read, "http_status", 0) '= 200 {
                Set unread = unread _ $SELECT(unread = "": "", 1: ", ") _ reference
            } ElseIf ($CLASSMETHOD(json, "Str", read, "status") '= "active") || '$CLASSMETHOD(json, "Bool", read, "identifier_ok") {
                Set wrong = wrong _ $SELECT(wrong = "": "", 1: ", ") _ reference _ $SELECT($CLASSMETHOD(json, "Str", read, "status") '= "active": " is not active", 1: " does not carry the recorded identifier")
            }
        }
    }
    If unread '= "" Do ..Check(checks, "mapping", "unknown", "FHIR_LOCATION_UNREADABLE", "A mapped Location could not be read, so it could not be checked: " _ unread)
    If wrong '= "" Do ..Check(checks, "mapping", "block", "FHIR_LOCATION_MISMATCH", "A mapped Location is not the one the site profile recorded: " _ wrong)
    If checks.%Size() = before Do ..Check(checks, "mapping", "pass", "FHIR_LOCATIONS_CHECKED", "Both wards have a Location in the map, and every mapped Location was read, is active and carries its recorded identifier")
}

/// The concurrency rows at dispatch: no binding (block); a part that was not read, or a Patient or a bound Location
/// that came with no ETag, which is no version to compare (unknown); the Encounter, the Patient or a bound Location at
/// another ETag than the binding sealed (block). ETags are compared as strings.
ClassMethod Concurrency(checks As %DynamicArray, fhir As %DynamicObject, binding As Shutter.Store.FHIRBinding) [ Private ]
{
    Set json = "Shutter.Util.Json", before = checks.%Size()
    If '$ISOBJECT(binding) {
        Do ..Check(checks, "concurrency", "block", "FHIR_NO_BINDING", "The plan has no sealed record of the version, the body and the Locations it was approved against")
        Quit
    }
    Set unread = ""
    Set enc = ..Obj(fhir, "encounter"), pat = ..Obj(fhir, "patient"), reads = $SELECT($ISOBJECT(fhir): fhir.%Get("locations"), 1: "")
    If +$CLASSMETHOD(json, "Str", enc, "http_status", 0) '= 200 {
        Set unread = "the Encounter"
    } ElseIf ..Differs($CLASSMETHOD(json, "Str", enc, "etag"), binding.ExpectedEtag) {
        Do ..Check(checks, "concurrency", "block", "FHIR_RECEIVER_CHANGED", "The Encounter's ETag is " _ $CLASSMETHOD(json, "Str", enc, "etag", "(none)") _ "; the person approved against " _ binding.ExpectedEtag _ ". The approval is void")
    }
    Set bound = ##class(Shutter.Util.Json).Parse(binding.PatientJSON)
    If +$CLASSMETHOD(json, "Str", pat, "http_status", 0) '= 200 {
        Set unread = unread _ $SELECT(unread = "": "", 1: ", ") _ "the Patient"
    } ElseIf $CLASSMETHOD(json, "Str", pat, "etag") = "" {
        // No ETag is no version: two empty ones compare as equal and say nothing.
        Set unread = unread _ $SELECT(unread = "": "", 1: ", ") _ "the Patient (it came with no ETag)"
    } ElseIf ..Differs($CLASSMETHOD(json, "Str", pat, "etag"), $CLASSMETHOD(json, "Str", bound, "etag")) {
        Do ..Check(checks, "concurrency", "block", "FHIR_PATIENT_CHANGED", "The Patient's ETag is " _ $CLASSMETHOD(json, "Str", pat, "etag", "(none)") _ "; the person approved against " _ $CLASSMETHOD(json, "Str", bound, "etag", "(none)") _ ". The approval is void")
    }
    Set changed = "", list = ##class(Shutter.Util.Json).Parse($SELECT(binding.LocationsJSON = "": "[]", 1: binding.LocationsJSON))
    If $ISOBJECT(list) && list.%IsA("%Library.DynamicArray") {
        Set iter = list.%GetIterator()
        While iter.%GetNext(.i, .b) {
            Continue:'..IsObject(b)
            Set reference = $CLASSMETHOD(json, "Str", b, "reference"), read = ..ByReference(reads, reference)
            If +$CLASSMETHOD(json, "Str", read, "http_status", 0) '= 200 {
                Set unread = unread _ $SELECT(unread = "": "", 1: ", ") _ reference
            } ElseIf $CLASSMETHOD(json, "Str", read, "etag") = "" {
                Set unread = unread _ $SELECT(unread = "": "", 1: ", ") _ reference _ " (it came with no ETag)"
            } ElseIf ..Differs($CLASSMETHOD(json, "Str", read, "etag"), $CLASSMETHOD(json, "Str", b, "etag")) {
                Set changed = changed _ $SELECT(changed = "": "", 1: ", ") _ reference
            }
        }
    }
    If changed '= "" Do ..Check(checks, "concurrency", "block", "FHIR_LOCATION_CHANGED", "A mapped Location changed after the approval: " _ changed _ ". The approval is void")
    If unread '= "" Do ..Check(checks, "concurrency", "unknown", "FHIR_RECEIVER_UNREADABLE", "Just before the write these could not be read, so their versions are not known: " _ unread)
    If checks.%Size() = before Do ..Check(checks, "concurrency", "pass", "FHIR_VERSION_MATCHES", "The Encounter is at " _ binding.ExpectedEtag _ ", the version approved against, and the Patient and the mapped Locations are unchanged")
}

/// The capability row: the server's statement as read now (unknown when it was not), the interactions a write is
/// checked by, and the conformance run recorded for the software the statement names.
ClassMethod Capability(checks As %DynamicArray, fhir As %DynamicObject, proof As Shutter.Store.FHIRProof) [ Private ]
{
    Set json = "Shutter.Util.Json"
    Set cap = ..Obj(fhir, "capability")
    If +$CLASSMETHOD(json, "Str", cap, "http_status", 0) '= 200 {
        Do ..Check(checks, "capability", "unknown", "FHIR_CAPABILITIES_UNREADABLE", "The server's CapabilityStatement could not be read, so what it guarantees is not known")
        Quit
    }
    Set interactions = cap.%Get("interactions"), lacks = ""
    For name = "read", "vread", "update", "history-instance" {
        Set has = 0
        If $ISOBJECT(interactions) && interactions.%IsA("%Library.DynamicArray") {
            Set iter = interactions.%GetIterator()
            While iter.%GetNext(.i, .v) { If v = name Set has = 1 }
        }
        If 'has Set lacks = lacks _ $SELECT(lacks = "": "", 1: ", ") _ name
    }
    If (lacks '= "") || '$CLASSMETHOD(json, "Bool", cap, "read_history") {
        Do ..Check(checks, "capability", "block", "FHIR_NO_HISTORY", "The server does not offer read, version read, update and instance history for Encounters (" _ $SELECT(lacks '= "": "missing: " _ lacks, 1: "readHistory is not true") _ "), so a write could not be checked afterwards")
        Quit
    }
    Set software = ..Obj(cap, "software")
    Set name = $CLASSMETHOD(json, "Str", software, "name"), version = $CLASSMETHOD(json, "Str", software, "version")
    Set why = ""
    If $CLASSMETHOD(json, "Str", cap, "versioning") '= "versioned-update" {
        Set why = "the server states versioning '" _ $CLASSMETHOD(json, "Str", cap, "versioning") _ "', not versioned-update"
    } ElseIf '$ISOBJECT(proof) {
        Set why = "no conformance run is recorded for this receiver"
    } ElseIf 'proof.Matches(name, version) {
        Set why = "the server now names " _ $SELECT(name = "": "no software", 1: name) _ " " _ version _ ", and the run measured " _ proof.SoftwareName _ " " _ proof.SoftwareVersion
    } ElseIf '(proof.IfMatchStaleRefused && proof.IfMatchUnknownIdRefused && proof.TagsKept) {
        Set why = "the recorded run does not show all three measurements: a stale If-Match refused, an unknown If-Match refused, a version's tags kept"
    }
    If why '= "" {
        Do ..Check(checks, "capability", "block", "FHIR_VERSIONING_UNPROVEN", "It is not proven that this server refuses a changed version: " _ why)
    } Else {
        Do ..Check(checks, "capability", "pass", "FHIR_CAPABLE", "The server offers read, version read, update and instance history with versioned updates, and the conformance run recorded for " _ name _ " " _ version _ " shows it refuses a stale and an unknown If-Match and keeps a version's tags")
    }
}

/// The catalogue rows: the plan's entry and outcome against the matcher's result in the evidence. Copied from
/// Shutter.Operation.Gate, lines 351-383 of version 1.4.4.
ClassMethod Catalogue(checks As %DynamicArray, case As Shutter.Store.Case, plan As Shutter.Store.Plan, view As %DynamicObject, isWrite As %Boolean) [ Private ]
{
    Set gate = "Shutter.Operation.Gate"
    Set cat = view.%Get("catalogue")
    Set decision = $SELECT($ISOBJECT(cat): ##class(Shutter.Util.Json).Str(cat, "decision"), 1: "")
    If (decision = "") || (decision = "not_configured") {
        Do ..Check(checks, "catalogue", "pass", "NOT_CONFIGURED", "No catalogue is installed, or the matcher gave no result")
    } ElseIf decision = "error" {
        Do ..Check(checks, "catalogue", "unknown", "MATCHER_ERROR", "The matcher failed on this evidence: " _ $EXTRACT(##class(Shutter.Util.Json).Str(cat, "error"), 1, 200))
    } ElseIf decision = "new_pattern" {
        Do ..Check(checks, "catalogue", "block", "NEW_PATTERN", "No catalogue entry matches this evidence: a candidate entry for a reviewer")
    } ElseIf (plan.CatalogueEntry = "") && isWrite && '((case.Mode = "rules") && (plan.CreatedBy = "rules") && case.ScenarioRecorded) && ($CLASSMETHOD(gate, "EntriesThatStop", cat) '= "") {
        Do ..Check(checks, "catalogue", "block", "ENTRY_NOT_NAMED_WRITE", "The plan writes and names no catalogue entry, but the evidence matched " _ $CLASSMETHOD(gate, "EntriesThatStop", cat) _ ", which calls for no resend")
    } ElseIf plan.CatalogueEntry = "" {
        Do ..Check(checks, "catalogue", "pass", "ENTRY_NOT_NAMED", "The plan names no catalogue entry; the evidence matched " _ $SELECT(##class(Shutter.Util.Json).Str(cat, "entry") '= "": ##class(Shutter.Util.Json).Str(cat, "entry"), 1: "several entries"))
    } Else {
        Set matched = "", mi = cat.%Get("matches").%GetIterator()
        While mi.%GetNext(.i, .m) { If ##class(Shutter.Util.Json).Str(m, "id") = plan.CatalogueEntry Set matched = m Quit }
        If '$ISOBJECT(matched) {
            Set exists = $ISOBJECT(##class(Shutter.Catalogue.Entry).ById(plan.CatalogueEntry))
            Do ..Check(checks, "catalogue", "block", $SELECT(exists: "PATTERN_NOT_MATCHED", 1: "ENTRY_UNKNOWN"), $SELECT(exists: "The plan follows " _ plan.CatalogueEntry _ ", but its pattern does not hold on this evidence", 1: "The plan names " _ plan.CatalogueEntry _ ", which is not in the catalogue"))
        } ElseIf $EXTRACT(plan.Outcome, 1, 12) = "alternative:" {
            Set n = +$PIECE(plan.Outcome, ":", 2), alts = matched.%Get("alternatives")
            Set alt = $SELECT($ISOBJECT(alts) && (n >= 1) && (n <= alts.%Size()): alts.%Get(n - 1), 1: "")
            Set when = $SELECT($ISOBJECT(alt): ##class(Shutter.Util.Json).Str(alt, "when", "always"), 1: "")
            Set allowed = $ISOBJECT(alt) && ##class(Shutter.Catalogue.Matcher).WhenHolds(when, cat.%Get("facts"))
            Do ..Check(checks, "catalogue", $SELECT(allowed: "pass", 1: "block"), $SELECT(allowed: "OUTCOME_ALLOWED", 1: "OUTCOME_NOT_ALLOWED"), $SELECT(allowed: "Entry " _ plan.CatalogueEntry _ " matches and the site allows alternative " _ n, 1: "Entry " _ plan.CatalogueEntry _ "'s alternative " _ n _ " is not allowed for this site (" _ when _ ")"))
            If allowed Do ..OutcomeConsistency(checks, plan, ##class(Shutter.Util.Json).Str(alt, "outcome"))
        } Else {
            Do ..Check(checks, "catalogue", "pass", "ENTRY_MATCHED", "Entry " _ plan.CatalogueEntry _ " matches the evidence; the preferred outcome")
            Do ..OutcomeConsistency(checks, plan, ##class(Shutter.Util.Json).Str(matched.%Get("preferred"), "outcome"))
        }
    }
}

/// A plan that follows an entry's outcome must act accordingly, or it is blocked with OUTCOME_MISMATCH. Copied from
/// Shutter.Operation.Gate's OutcomeConsistency, lines 495-501 of version 1.4.4.
ClassMethod OutcomeConsistency(checks As %DynamicArray, plan As Shutter.Store.Plan, outcome As %String) [ Private ]
{
    Set allowed = ##class(Shutter.Operation.Gate).DispositionFor(outcome)
    If (allowed = "") || (plan.Disposition = allowed) Quit
    If (allowed = "escalate") && (plan.Disposition = "more_evidence") Quit
    Do ..Check(checks, "catalogue", "block", "OUTCOME_MISMATCH", "The outcome " _ outcome _ " calls for " _ allowed _ ", but the plan's disposition is " _ plan.Disposition)
}

/// True when an open location entry of the Encounter view is on that ward.
ClassMethod OnWard(enc As %DynamicObject, ward As %String) As %Boolean [ Private ]
{
    If ward = "" Quit 0
    Set locations = $SELECT($ISOBJECT(enc): enc.%Get("locations"), 1: "")
    If '$ISOBJECT(locations) || 'locations.%IsA("%Library.DynamicArray") Quit 0
    Set found = 0, iter = locations.%GetIterator()
    While iter.%GetNext(.i, .l) { If ..IsObject(l) && ..IsOpen(l) && (##class(Shutter.Util.Json).Str(l, "ward") = ward) Set found = 1 }
    Quit found
}

/// True for a location entry of the Encounter view that is open: its status is active or absent and it has no end,
/// as the plan builder reads an open entry.
ClassMethod IsOpen(l As %DynamicObject) As %Boolean [ Private ]
{
    Set status = ##class(Shutter.Util.Json).Str(l, "status")
    Quit ((status = "") || (status = "active")) && (##class(Shutter.Util.Json).Str(l, "end") = "")
}

/// The entry of a list of reads whose reference is that one, or "".
ClassMethod ByReference(reads, reference As %String) As %DynamicObject [ Private ]
{
    If (reference = "") || '$ISOBJECT(reads) || 'reads.%IsA("%Library.DynamicArray") Quit ""
    Set found = "", iter = reads.%GetIterator()
    While iter.%GetNext(.i, .r) { If ..IsObject(r) && (##class(Shutter.Util.Json).Str(r, "reference") = reference) Set found = r }
    Quit found
}

/// True when two ETags are not the same string, character for character. Nothing is read as a number, so W/"3" is not
/// "3" and "10" is not "9"; the leading space makes the comparison one of strings whatever the values look like.
ClassMethod Differs(a As %String, b As %String) As %Boolean [ Private ]
{
    Quit (" " _ a) '= (" " _ b)
}

/// True when a check already carries that reason code.
ClassMethod Has(checks As %DynamicArray, code As %String) As %Boolean [ Private ]
{
    Set found = 0, iter = checks.%GetIterator()
    While iter.%GetNext(.i, .c) { If c."reason_code" = code Set found = 1 }
    Quit found
}

/// The row of a check that needs the Encounter when none was read: unknown, with the code the identity row gave.
ClassMethod Unread(checks As %DynamicArray, name As %String, code As %String, what As %String) [ Private ]
{
    Do ..Check(checks, name, "unknown", code, "No Encounter was read (see the identity check), so this could not be checked: " _ what)
}

/// The row of a check that applies to a write only, for a plan that writes nothing.
ClassMethod NotApplicable(checks As %DynamicArray, name As %String) [ Private ]
{
    Do ..Check(checks, name, "pass", "NOT_APPLICABLE", "No write proposed")
}

/// The JSON object under a key, or "" when the parent is no object or the key holds anything else.
ClassMethod Obj(parent, key As %String) As %DynamicObject [ Private ]
{
    If '..IsObject(parent) Quit ""
    Set value = parent.%Get(key)
    Quit $SELECT(..IsObject(value): value, 1: "")
}

/// True for a JSON object (not an array, not a string).
ClassMethod IsObject(value) As %Boolean [ Private ]
{
    Quit $ISOBJECT(value) && value.%IsA("%Library.DynamicObject")
}

ClassMethod Row(name As %String, result As %String, code As %String, detail As %String) As %DynamicObject [ Private ]
{
    Set c = {}
    Set c.check = name, c.result = result, c."reason_code" = code, c.detail = detail
    Quit c
}

ClassMethod Check(checks As %DynamicArray, name As %String, result As %String, code As %String, detail As %String) [ Private ]
{
    Do checks.%Push(..Row(name, result, code, detail))
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.FHIRGateRequest">
    <Method>OnGateRequest</Method>
  </MapItem>
</MapItems>
}

}
