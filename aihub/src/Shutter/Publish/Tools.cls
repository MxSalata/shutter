/// The publisher's tools (docs/CONTRACTS.md, section 15, v1.35): read-only access to Shutter's cases, incidents,
/// evidence, plans and precedents for an MCP client, as an operator sees them in the app, with the patients'
/// identifiers replaced by the model view's tokens and no demographics or free text. Every public ClassMethod is a
/// stateless tool (%AI.Tool); nothing here writes anything but an audit row per call (Shutter.Store.PublishCall: the
/// tool, the case id and its version, never the answer). Shutter.Publish.Service serves them at /mcp/shutter.
Class Shutter.Publish.Tools Extends %AI.Tool
{

Property Name As %String [ InitialExpression = "Shutter publisher" ];

Property Description As %String(MAXLEN = "") [ InitialExpression = "Read-only access to Shutter's cases, incidents, evidence, plans and precedents, as an operator sees them, with the patients' identifiers replaced by tokens. Nothing here writes." ];

/// The cases, newest first: id, state, event, receiver, failure kind, times, version, incident and headline. Filter by state (for example awaiting_approval, blocked, escalated, resolved) and receiver; at most limit (200 at most).
/// state: a case state to filter by, or empty for every state
/// receiver: a receiver item name to filter by, or empty for every receiver
/// limit: how many cases at most, 20 by default
ClassMethod ListCases(state As %String = "", receiver As %String = "", limit As %Integer = 20) As %DynamicObject
{
    Set start = $ZHOROLOG
    Set out = {"cases": []}
    Set where = "", args = 0
    If state '= "" Set where = where _ " AND State = ?", args = args + 1, args(args) = state
    If receiver '= "" Set where = where _ " AND Receiver = ?", args = args + 1, args(args) = receiver
    Set n = $SELECT(+limit < 1: 20, +limit > 200: 200, 1: +limit)
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ n _ " ID FROM Shutter_Store.""Case"" WHERE 1=1" _ where _ " ORDER BY ID DESC", args...)
    While rs.%Next() {
        Set case = ##class(Shutter.Store.Case).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(case)
        Do out.cases.%Push(..CaseRow(case))
    }
    Set out.count = out.cases.%Size()
    Do ..Audit("ListCases", $SELECT(state '= "": state, 1: "all") _ $SELECT(receiver '= "": "@" _ receiver, 1: ""), "", start)
    Return out
}

/// One case: its public fields, its current plan (digest, disposition, summary), the approval of record, where it stands in its incident, and the precedents for its conditions at its receiver. The version lets a client see that the case changed between two reads.
/// caseId: the case identifier, for example C-000012
ClassMethod GetCase(caseId As %String) As %DynamicObject
{
    Set start = $ZHOROLOG
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Return ..Unknown(caseId)
    Set o = ..CaseRow(case)
    Set o.failureText = ..Text(case, case.FailureText)
    Set o.outcome = ..Text(case, case.Outcome)
    Set o.failureOutcome = case.FailureOutcome, o.failureReasonCode = case.FailureReasonCode
    If case.FailureHttpStatus '= "" Set o.failureHttpStatus = case.FailureHttpStatus
    Set o.disposition = case.Disposition, o.scenario = case.Scenario
    Set o.sourceNamespace = case.SourceNamespace, o.sourceProduction = case.SourceProduction, o.sourceRoute = case.SourceRoute
    Set o.closedAt = case.ClosedAt
    Set o.waitsOnCase = case.WaitsOnCase, o.heldSchema = case.HeldSchema, o.retryAfterUntil = case.RetryAfterUntil
    Set plan = case.CurrentPlan
    If $ISOBJECT(plan) {
        Set o.plan = {"digest": (plan.Digest), "version": (plan.Version), "disposition": (plan.Disposition), "actionType": (plan.ActionType), "expectedVersion": (plan.ExpectedVersion), "catalogueEntry": (plan.CatalogueEntry), "outcome": (plan.Outcome), "summary": (..Text(case, plan.Summary)), "createdBy": (plan.CreatedBy)}
    } Else {
        Do o.%Set("plan", "", "null")
    }
    Set a = case.CurrentApproval
    If $ISOBJECT(a) {
        Set o.approval = {"approver": (a.Approver), "decision": (a.Decision), "decidedAt": (a.DecidedAt), "expiresAt": (a.ExpiresAt), "planDigest": (a.PlanDigest), "policyVersion": (a.PolicyVersion), "siteProfileVersion": (a.SiteProfileVersion)}
        Do o.approval.%Set("revoked", ''a.Revoked, "boolean")
    } Else {
        Do o.%Set("approval", "", "null")
    }
    If $ISOBJECT(case.Incident) Set o.incident = ##class(Shutter.Store.ChainItem).IncidentContext(case)
    Set o.precedents = ##class(Shutter.Store.Precedent).SummaryFor(case)
    Do ..Audit("GetCase", case.CaseId, case.Version, start)
    Return o
}

/// The case's evidence snapshot as a board member sees it: the failed operation and the failure, the message's fields and validation, the receiver's state and history for the encounter, the receipt lookup, the timeline, the route and the catalogue match. Identifiers are tokens.
/// caseId: the case identifier
ClassMethod GetEvidence(caseId As %String) As %DynamicObject
{
    Set start = $ZHOROLOG
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Return ..Unknown(caseId)
    Set o = ##class(Shutter.Tools.Evidence).GetSnapshot(caseId)
    Do ..Audit("GetEvidence", case.CaseId, case.Version, start)
    Return o
}

/// How the delivery failed: the connector's answer and the operation that failed, from the evidence snapshot.
/// caseId: the case identifier
ClassMethod GetFailure(caseId As %String) As %DynamicObject
{
    Set start = $ZHOROLOG
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Return ..Unknown(caseId)
    Set o = ##class(Shutter.Tools.Evidence).GetFailure(caseId)
    Do ..Audit("GetFailure", case.CaseId, case.Version, start)
    Return o
}

/// Every operation the feed sent for the case's encounter, in order, with its delivery outcome and whether it came later than the failed one, from the evidence snapshot.
/// caseId: the case identifier
ClassMethod GetTimeline(caseId As %String) As %DynamicObject
{
    Set start = $ZHOROLOG
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Return ..Unknown(caseId)
    Set o = ##class(Shutter.Tools.Evidence).GetTimeline(caseId)
    Do ..Audit("GetTimeline", case.CaseId, case.Version, start)
    Return o
}

/// The case's current plan with the gate's decisions on it (proposal, approval, dispatch: pass, block or unknown with reason codes) and the rehearsal's outcome.
/// caseId: the case identifier
ClassMethod GetPlan(caseId As %String) As %DynamicObject
{
    Set start = $ZHOROLOG
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Return ..Unknown(caseId)
    Set plan = case.CurrentPlan
    If '$ISOBJECT(plan) Return {"caseId": (case.CaseId), "error": "no_plan", "detail": "The case has no plan yet"}
    Set o = {"caseId": (case.CaseId), "caseVersion": (case.Version)}
    Set o.plan = {"digest": (plan.Digest), "version": (plan.Version), "disposition": (plan.Disposition), "actionType": (plan.ActionType), "expectedVersion": (plan.ExpectedVersion), "payloadDigest": (plan.PayloadDigest), "catalogueEntry": (plan.CatalogueEntry), "outcome": (plan.Outcome), "summary": (..Text(case, plan.Summary)), "why": (..Text(case, plan.Why)), "createdBy": (plan.CreatedBy)}
    Set refs = ##class(Shutter.Util.Json).Parse(plan.EvidenceRefsJSON, .psc)
    If $ISOBJECT(refs) Set o.plan.evidenceRefs = refs
    Set o.gateDecisions = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.GateDecision WHERE Plan = ? ORDER BY ID", plan.%Id())
    While rs.%Next() {
        Set d = ##class(Shutter.Store.GateDecision).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(d)
        Set g = {"stage": (d.Stage), "outcome": (d.Outcome), "policyVersion": (d.PolicyVersion), "at": (d.At), "summary": (..Text(case, d.Summary))}
        Set checks = ##class(Shutter.Util.Json).Parse(d.ChecksJSON, .csc)
        If $ISOBJECT(checks) {
            Set g.checks = [], ci = checks.%GetIterator()
            While ci.%GetNext(, .c) { Do g.checks.%Push({"check": (c.%Get("check")), "result": (c.%Get("result")), "reason_code": (c.%Get("reason_code")), "detail": (..Text(case, c.%Get("detail")))}) }
        }
        Do o.gateDecisions.%Push(g)
    }
    Set rid = "", planId = plan.%Id()
    &sql(SELECT TOP 1 ID INTO :rid FROM Shutter_Store.Rehearsal WHERE Plan = :planId ORDER BY ID DESC)
    If (SQLCODE = 0) && (rid '= "") {
        Set r = ##class(Shutter.Store.Rehearsal).%OpenId(rid)
        If $ISOBJECT(r) { Set o.rehearsal = {"reason": (r.Reason), "httpStatus": (r.HttpStatus), "receiverVersion": (r.ReceiverVersion), "at": (r.At)} Do o.rehearsal.%Set("wouldApply", r.WouldApply, "boolean") }
    } Else {
        Do o.%Set("rehearsal", "", "null")
    }
    Do ..Audit("GetPlan", case.CaseId, case.Version, start)
    Return o
}

/// The case's events, newest first: what happened, when, by whom (system, policy or a user), with the texts' identifiers as tokens; at most limit (500 at most).
/// caseId: the case identifier
/// limit: how many events at most, 50 by default
ClassMethod GetEvents(caseId As %String, limit As %Integer = 50) As %DynamicObject
{
    Set start = $ZHOROLOG
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Return ..Unknown(caseId)
    Set n = $SELECT(+limit < 1: 50, +limit > 500: 500, 1: +limit)
    Set rows = ##class(Shutter.Util.Json).Rows("Shutter.Store.CaseEvent", "SELECT TOP " _ n _ " ID FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? ORDER BY ID DESC", case.%Id())
    Set o = {"caseId": (case.CaseId), "caseVersion": (case.Version), "events": []}
    Set it = rows.%GetIterator()
    While it.%GetNext(, .e) {
        Set kept = {}
        For k = "seq", "kind", "at", "createdAt", "actor", "ref", "fromState", "toState", "state" {
            If e.%IsDefined(k) Do kept.%Set(k, e.%Get(k))
        }
        If e.%IsDefined("text") Set kept.text = ..Text(case, e.%Get("text"))
        Do o.events.%Push(kept)
    }
    Set o.count = o.events.%Size()
    Do ..Audit("GetEvents", case.CaseId, case.Version, start)
    Return o
}

/// The incidents (bursts of failures to one receiver), newest first: id, receiver, state, when it opened and closed, threshold and window, the policy and who approved. Filter by state (open, classified, awaiting_approval, releasing, closed); at most limit (200 at most).
/// state: an incident state to filter by, or empty for every state
/// limit: how many incidents at most, 20 by default
ClassMethod ListIncidents(state As %String = "", limit As %Integer = 20) As %DynamicObject
{
    Set start = $ZHOROLOG
    Set out = {"incidents": []}
    Set where = "", args = 0
    If state '= "" Set where = " AND State = ?", args = 1, args(1) = state
    Set n = $SELECT(+limit < 1: 20, +limit > 200: 200, 1: +limit)
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ n _ " ID FROM Shutter_Store.Incident WHERE 1=1" _ where _ " ORDER BY ID DESC", args...)
    While rs.%Next() {
        Set inc = ##class(Shutter.Store.Incident).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(inc)
        Do out.incidents.%Push(..IncidentRow(inc))
    }
    Set out.count = out.incidents.%Size()
    Do ..Audit("ListIncidents", $SELECT(state '= "": state, 1: "all"), "", start)
    Return out
}

/// One incident with its chains: each chain's sequence, state and policy, and its cases in order (case id, state, event). Identifiers are tokens.
/// incidentId: the incident identifier, for example I-000003
ClassMethod GetIncident(incidentId As %String) As %DynamicObject
{
    Set start = $ZHOROLOG
    Set inc = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Incident WHERE IncidentId = ?", incidentId)
    If rs.%Next() Set inc = ##class(Shutter.Store.Incident).%OpenId(rs.%Get("ID"))
    If '$ISOBJECT(inc) Return {"incidentId": (incidentId), "error": "not_found", "detail": ("No incident " _ incidentId)}
    Set o = ..IncidentRow(inc)
    Set o.chains = []
    Set chains = inc.Chains()
    If $ISOBJECT(chains) {
        Set ci = chains.%GetIterator()
        While ci.%GetNext(, .ch) {
            Set kept = {}
            For k = "seq", "state", "policy", "kind", "decides", "entry", "outcome", "releasedAt", "approvedBy" {
                If ch.%IsDefined(k) Do kept.%Set(k, ch.%Get(k))
            }
            Set kept.items = []
            Set items = ch.%Get("items")
            If $ISOBJECT(items) {
                Set ii = items.%GetIterator()
                While ii.%GetNext(, .item) {
                    Set row = {}
                    For k = "caseId", "caseState", "state", "event", "position", "seq" {
                        If item.%IsDefined(k) Do row.%Set(k, item.%Get(k))
                    }
                    Do kept.items.%Push(row)
                }
            }
            Do o.chains.%Push(kept)
        }
    }
    Do ..Audit("GetIncident", inc.IncidentId, "", start)
    Return o
}

/// What approvers decided before on the same conditions at the same receiver as this case (the precedents): the counts, the last decision, and the rows, newest first.
/// caseId: the case identifier
ClassMethod GetPrecedents(caseId As %String) As %DynamicObject
{
    Set start = $ZHOROLOG
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Return ..Unknown(caseId)
    Set o = {"caseId": (case.CaseId), "caseVersion": (case.Version), "receiver": (case.Receiver)}
    Set o.summary = ##class(Shutter.Store.Precedent).SummaryFor(case)
    Set o.precedents = ##class(Shutter.Store.Precedent).RowsFor(case)
    Do ..Audit("GetPrecedents", case.CaseId, case.Version, start)
    Return o
}

/// Shutter's state: the edition (aihub or core), the production and its mode, how many cases are open and awaiting approval, how many incidents are open, and the publisher's own call count today.
ClassMethod Health() As %DynamicObject
{
    Set start = $ZHOROLOG
    Set o = {}
    Try {
        Set d = ##class(%DynamicObject).%FromJSON(##class(Shutter.Setup).Doctor())
        For k = "edition", "production", "production_running", "mode", "namespace", "policy_version", "catalogue_version", "last_live_run", "release_sweep", "live" {
            If d.%IsDefined(k) Do o.%Set(k, d.%Get(k))
        }
    } Catch ex {
        Set o.doctorError = ex.DisplayString()
    }
    Set open = 0, awaiting = 0, incidents = 0
    &sql(SELECT COUNT(*) INTO :open FROM Shutter_Store."Case" WHERE State NOT IN ('resolved', 'blocked', 'escalated', 'failed'))
    &sql(SELECT COUNT(*) INTO :awaiting FROM Shutter_Store."Case" WHERE State = 'awaiting_approval')
    &sql(SELECT COUNT(*) INTO :incidents FROM Shutter_Store.Incident WHERE State <> 'closed')
    Set o.casesOpen = +open, o.casesAwaitingApproval = +awaiting, o.incidentsOpen = +incidents
    Set o.publisherCallsToday = ##class(Shutter.Store.PublishCall).CountSince($EXTRACT(##class(Shutter.Util.Time).NowUTC(), 1, 10) _ "T00:00:00Z")
    Do ..Audit("Health", "", "", start)
    Return o
}

/// A case's public row: no patient or encounter identifier, the texts with the model view's tokens.
ClassMethod CaseRow(case As Shutter.Store.Case) As %DynamicObject [ Private ]
{
    Set o = {}
    Set o.caseId = case.CaseId, o.state = case.State, o.mode = case.Mode, o.event = case.Event, o.receiver = case.Receiver
    Set o.failureKind = case.FailureKind, o.openedAt = case.OpenedAt, o.updatedAt = case.UpdatedAt, o.version = case.Version
    Set o.eventTime = case.EventTime
    Set o.headline = ..Text(case, case.Headline)
    If $ISOBJECT(case.Incident) { Set o.incidentId = case.Incident.IncidentId } Else { Do o.%Set("incidentId", "", "null") }
    Return o
}

/// An incident's public row.
ClassMethod IncidentRow(inc As Shutter.Store.Incident) As %DynamicObject [ Private ]
{
    Set o = {}
    Set o.incidentId = inc.IncidentId, o.receiver = inc.Receiver, o.mode = inc.Mode, o.state = inc.State
    Set o.openedAt = inc.OpenedAt, o.intakeClosedAt = inc.IntakeClosedAt, o.closedAt = inc.ClosedAt, o.lastFailureAt = inc.LastFailureAt
    Set o.threshold = inc.Threshold, o.windowMinutes = inc.WindowMinutes, o.quietSeconds = inc.QuietSeconds
    Set o.policy = inc.Policy, o.approvedBy = inc.ApprovedBy, o.approvedAt = inc.ApprovedAt, o.planDigest = inc.PlanDigest
    Set o.policyVersion = inc.PolicyVersion, o.profileVersion = inc.ProfileVersion
    Return o
}

/// A text with the case's identifiers replaced by the model view's tokens (CONTRACTS 9), and nothing else of it changed.
ClassMethod Text(case As Shutter.Store.Case, text As %String) As %String [ Private ]
{
    If text = "" Return ""
    Try { Return ##class(Shutter.Util.ModelView).Tokenise(case, text) } Catch ex { Return "" }
}

ClassMethod Unknown(caseId As %String) As %DynamicObject [ Private ]
{
    Return {"caseId": (caseId), "error": "not_found", "detail": ("No case " _ caseId)}
}

/// The audit row: who called which tool on what, at which version, how long it took; never the answer.
ClassMethod Audit(tool As %String, target As %String, version As %String, start As %Numeric) [ Private ]
{
    Try { Do ##class(Shutter.Store.PublishCall).Record(tool, target, version, (($ZHOROLOG - start) * 1000) \ 1) } Catch ex {}
}

}
