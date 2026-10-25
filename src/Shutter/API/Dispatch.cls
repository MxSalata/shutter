/// The REST API for the web application (docs/CONTRACTS.md, section 5). Every route checks the
/// caller's resources on the server; changes need the CSRF header; the POSTs that change a case take
/// an Idempotency-Key. Everything the app shows comes through here.
Class Shutter.API.Dispatch Extends %CSP.REST
{

Parameter HandleCorsRequest = 0;

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "utf-8";

Parameter UseSession = 1;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/session" Method="POST" Call="Login"/>
  <Route Url="/session" Method="DELETE" Call="Logout"/>
  <Route Url="/me" Method="GET" Call="Me"/>
  <Route Url="/health" Method="GET" Call="Health"/>
  <Route Url="/scenarios" Method="GET" Call="Scenarios"/>
  <Route Url="/scenarios/reset" Method="POST" Call="ScenarioReset"/>
  <Route Url="/scenarios/:id/run" Method="POST" Call="ScenarioRun"/>
  <Route Url="/cases" Method="GET" Call="Cases"/>
  <Route Url="/cases/:caseId" Method="GET" Call="CaseGet"/>
  <Route Url="/cases/:caseId/events" Method="GET" Call="CaseEvents"/>
  <Route Url="/cases/:caseId/snapshot" Method="GET" Call="CaseSnapshot"/>
  <Route Url="/cases/:caseId/runs" Method="GET" Call="CaseRuns"/>
  <Route Url="/cases/:caseId/plan" Method="GET" Call="CasePlan"/>
  <Route Url="/cases/:caseId/approvals" Method="GET" Call="CaseApprovals"/>
  <Route Url="/cases/:caseId/approvals" Method="POST" Call="CaseApprove"/>
  <Route Url="/cases/:caseId/attempts" Method="GET" Call="CaseAttempts"/>
  <Route Url="/cases/:caseId/closure" Method="GET" Call="CaseClosure"/>
  <Route Url="/cases/:caseId/preview-blind-resend" Method="POST" Call="CasePreview"/>
  <Route Url="/cases/:caseId/blocked-reason" Method="GET" Call="CaseBlockedReason"/>
  <Route Url="/cases/:caseId/reinvestigate" Method="POST" Call="CaseReinvestigate"/>
  <Route Url="/cases/:caseId/close" Method="POST" Call="CaseClose"/>
  <Route Url="/cases/:caseId/abandon" Method="POST" Call="CaseAbandon"/>
  <Route Url="/intake" Method="POST" Call="Intake"/>
  <Route Url="/cases/:caseId/escalations" Method="GET" Call="CaseEscalations"/>
  <Route Url="/cases/:caseId/escalations" Method="POST" Call="CaseEscalationCreate"/>
  <Route Url="/cases/:caseId/escalations/:seq" Method="PATCH" Call="CaseEscalationPatch"/>
  <Route Url="/cases/:caseId/escalations/:seq/send" Method="POST" Call="CaseEscalationSend"/>
  <Route Url="/library" Method="GET" Call="Library"/>
  <Route Url="/library/:code" Method="PATCH" Call="LibraryPatch"/>
  <Route Url="/settings" Method="GET" Call="Settings"/>
  <Route Url="/site-profile" Method="GET" Call="SiteProfileGet"/>
  <Route Url="/site-profile" Method="PUT" Call="SiteProfilePut"/>
  <Route Url="/site-profile/history" Method="GET" Call="SiteProfileHistory"/>
  <Route Url="/index" Method="GET" Call="IndexStatus"/>
  <Route Url="/index/messages" Method="GET" Call="IndexMessages"/>
  <Route Url="/incidents" Method="GET" Call="Incidents"/>
  <Route Url="/incidents/:id" Method="GET" Call="IncidentGet"/>
  <Route Url="/incidents/:id/events" Method="GET" Call="IncidentEvents"/>
  <Route Url="/incidents/:id/approvals" Method="GET" Call="IncidentApprovals"/>
  <Route Url="/incidents/:id/approvals" Method="POST" Call="IncidentApprove"/>
  <Route Url="/incidents/:id/chains/:seq/approvals" Method="POST" Call="IncidentChainApprove"/>
  <Route Url="/costs" Method="GET" Call="Costs"/>
</Routes>
}

// ---- plumbing ----

/// The base class refuses anonymous callers before any route runs; here the sign-in route must run
/// for them, and every other route checks the caller's resources itself (Allow).
ClassMethod AccessCheck(Output pAuthorized As %Boolean = 0) As %Status
{
    Set pAuthorized = 1
    Quit $$$OK
}

/// Write a dynamic object or array as the response.
ClassMethod Json(obj As %DynamicAbstractObject, status As %String = "200 OK") As %Status
{
    Set %response.Status = status
    Set %response.ContentType = "application/json"
    Do obj.%ToJSON()
    Quit $$$OK
}

/// Write an error reply.
ClassMethod Fail(status As %String, code As %String, detail As %String = "", extra As %DynamicObject = "") As %Status
{
    Set o = {}
    If $ISOBJECT(extra) Set o = extra
    Set o.error = code
    If detail '= "" Set o.detail = detail
    Quit ..Json(o, status)
}

/// The signed-in user, or "" for an unauthenticated request.
ClassMethod User() As %String
{
    Quit $SELECT($USERNAME = "UnknownUser": "", 1: $USERNAME)
}

/// Check the caller holds a resource. Returns "" when allowed, else the error reply's status.
ClassMethod Require(resource As %String) As %String
{
    If ..User() = "" Quit "401 Unauthorized"
    If '$SYSTEM.Security.Check(resource, "USE") Quit "403 Forbidden"
    Quit ""
}

/// Guard a route: authentication, the resource, and for changes the CSRF header. Returns 1 when
/// the request may proceed; otherwise the error reply has been written.
ClassMethod Allow(resource As %String = "Shutter_Operate", change As %Boolean = 0) As %Boolean
{
    If ..User() = "" Do ..Fail("401 Unauthorized", "unauthenticated", "Sign in first") Quit 0
    If (resource '= "") && '$SYSTEM.Security.Check(resource, "USE") Do ..Fail("403 Forbidden", "forbidden", "This needs " _ resource) Quit 0
    If change && (%request.GetCgiEnv("HTTP_X_REQUESTED_WITH") '= "Shutter") Do ..Fail("403 Forbidden", "csrf", "Changes need the header X-Requested-With: Shutter") Quit 0
    Quit 1
}

/// The request body as a dynamic object (empty when absent or invalid).
ClassMethod Body() As %DynamicObject
{
    Set o = {}
    Try {
        If $ISOBJECT(%request.Content) {
            Set text = %request.Content.Read($$$MaxStringLength)
        } Else {
            Set text = $GET(%request.Content)
        }
        If $ZSTRIP($GET(text), "<>W") '= "" Set o = ##class(%DynamicObject).%FromJSON(text)
    } Catch ex {
        Set o = {}
    }
    Quit o
}

/// A persistent object's JSON projection as a dynamic object.
ClassMethod Project(obj As %JSON.Adaptor) As %DynamicObject
{
    If '$ISOBJECT(obj) Quit ""
    Set sc = obj.%JSONExportToString(.json)
    If $$$ISERR(sc) || ($GET(json) = "") {
        Set o = {}
        Set o.id = obj.%Id()
        Set o.error = "projection failed: " _ $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "empty")
        Quit o
    }
    Set o = ""
    Try {
        Set o = ##class(%DynamicObject).%FromJSON(json)
    } Catch {
        // A numeric property with no value (added after the row was saved) exports as an empty value,
        // which is not JSON: null takes its place, outside string literals only.
        Try {
            Set o = ##class(%DynamicObject).%FromJSON(##class(Shutter.Util.Json).NullEmptyValues(json))
        } Catch ex {
            Set o = {}
            Set o.error = "projection failed: " _ ex.DisplayString()
        }
    }
    Set o.id = obj.%Id()
    Quit o
}

/// The case for a public id, or "" after writing a 404.
ClassMethod CaseOr404(caseId As %String) As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Do ..Fail("404 Not Found", "not_found", "No case " _ caseId)
    Quit case
}

/// Serve an idempotent change: replay a stored reply, or run the handler and store its reply.
ClassMethod Idempotent(bodyText As %String, Output replayed As %Boolean) As %Integer
{
    Set replayed = 0
    Set key = %request.GetCgiEnv("HTTP_IDEMPOTENCY_KEY")
    If key = "" Quit 0
    If $LENGTH(key) > 128 Do ..Fail("400 Bad Request", "bad_request", "Idempotency-Key is longer than 128 characters") Set replayed = 1 Quit -1
    Set digest = ##class(Shutter.Util.Digest).SHA256Hex(bodyText)
    Set found = ##class(Shutter.Store.Idempotency).Lookup(..IdempotencyKey(key), digest, .status, .response)
    If found = -1 Do ..Fail("409 Conflict", "idempotency_key_reused", "This key was used with another body") Set replayed = 1 Quit -1
    If found = 1 {
        Set %response.Status = status
        Set %response.ContentType = "application/json"
        Write response
        Set replayed = 1
        Quit 1
    }
    Quit 0
}

ClassMethod Remember(bodyText As %String, status As %String, response As %String)
{
    Set key = %request.GetCgiEnv("HTTP_IDEMPOTENCY_KEY")
    Quit:(key="")
    Do ##class(Shutter.Store.Idempotency).Store(..IdempotencyKey(key), ##class(Shutter.Util.Digest).SHA256Hex(bodyText), status, response)
}

/// The stored key is scoped to the user, the method and the route, so the same client key on another route (or
/// another user's) is another request, never a replay of this one.
ClassMethod IdempotencyKey(key As %String) As %String
{
    Quit ..User() _ "|" _ %request.Method _ "|" _ %request.URL _ "|" _ key
}

/// Rows of a SQL query as projected objects of a class.
ClassMethod Rows(class As %String, sql As %String, args...) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql, args...)
    While rs.%Next() {
        Set obj = $CLASSMETHOD(class, "%OpenId", rs.%Get("ID"))
        Continue:'$ISOBJECT(obj)
        Do out.%Push(..Project(obj))
    }
    Quit out
}

ClassMethod PortalPath() As %String
{
    // The namespace's default web application: /csp/healthshare/<ns>/ on IRIS for Health, /csp/<ns>/ elsewhere.
    Set app = ""
    Try {
        Set app = $SYSTEM.CSP.GetDefaultApp($NAMESPACE)
    } Catch {
    }
    If app = "" Set app = "/csp/" _ $ZCONVERT($NAMESPACE, "L")
    If $EXTRACT(app, *) '= "/" Set app = app _ "/"
    Quit app
}

// ---- session ----

ClassMethod Login() As %Status
{
    Set body = ..Body()
    Set user = ##class(Shutter.Util.Json).Str(body, "username"), pwd = ##class(Shutter.Util.Json).Str(body, "password")
    If (user = "") || (pwd = "") Quit ..Fail("400 Bad Request", "bad_request", "username and password are required")
    Set ok = %session.Login(user, pwd)
    If 'ok Quit ..Fail("401 Unauthorized", "invalid_credentials", "The username or password is wrong")
    Quit ..Me()
}

ClassMethod Logout() As %Status
{
    Do %session.Logout()
    Quit ..Json({"signedOut": true})
}

ClassMethod Me() As %Status
{
    If ..User() = "" Quit ..Fail("401 Unauthorized", "unauthenticated", "Sign in first")
    Set o = {}
    Set o.username = ..User()
    Do o.%Set("operator", $SYSTEM.Security.Check("Shutter_Operate", "USE"), "boolean")
    Do o.%Set("approver", $SYSTEM.Security.Check("Shutter_Approve", "USE"), "boolean")
    Quit ..Json(o)
}

ClassMethod Health() As %Status
{
    Set full = ##class(%DynamicObject).%FromJSON(##class(Shutter.Setup).Doctor())
    If $SYSTEM.Security.Check("Shutter_Operate", "USE") Quit ..Json(full)
    // Anyone may ask whether the instance is up and whether it is the demo; the rest is for signed-in users.
    Set o = {}
    For key = "status", "ok", "demo", "version", "production", "production_state", "mode" { If full.%IsDefined(key) Do o.%Set(key, full.%Get(key), $SELECT(full.%GetTypeOf(key) = "boolean": "boolean", 1: "")) }
    Do o.%Set("ok", ##class(Shutter.Util.Json).Str(full, "production_state") = "running", "boolean")
    Quit ..Json(o)
}

// ---- scenarios ----

ClassMethod Scenarios() As %Status
{
    If '..Allow() Quit $$$OK
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Scenarios.Runner") Quit ..Json([])
    Set list = ##class(Shutter.Util.Json).Parse($CLASSMETHOD("Shutter.Scenarios.Runner", "List"), .sc)
    If '$ISOBJECT(list) Set list = []
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .sc) {
        Set id = ##class(Shutter.Util.Json).Str(sc, "id")
        Set cid = ""
        &sql(SELECT TOP 1 ID INTO :cid FROM Shutter_Store."Case" WHERE Scenario = :id ORDER BY ID DESC)
        If (SQLCODE = 0) && (cid '= "") {
            Set c = ##class(Shutter.Store.Case).%OpenId(cid)
            Set latest = {}
            Set latest.caseId = c.CaseId, latest.state = c.State, latest.disposition = c.Disposition, latest.headline = c.Headline, latest.updatedAt = c.UpdatedAt
            Set sc.latestCase = latest
        } Else {
            Do sc.%Set("latestCase", "", "null")
        }
    }
    Set out = {}
    Set out.scenarios = list
    Set run = ""
    If ##class(%Dictionary.CompiledMethod).%ExistsId("Shutter.Scenarios.Runner||Status") Set run = ##class(Shutter.Util.Json).Parse($CLASSMETHOD("Shutter.Scenarios.Runner", "Status"), .ssc)
    If $ISOBJECT(run) { Set out.run = run } Else { Do out.%Set("run", "", "null") }
    Quit ..Json(out)
}

/// True when the running production (Shutter's own, or the site's that InstallInto put Shutter's items in) has the
/// Scenario Player item enabled.
ClassMethod PlayerEnabled() As %Boolean
{
    Set n = 0, prod = ##class(Shutter.Setup).ProductionName()
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N FROM Ens_Config.Item WHERE Production = ? AND Name = ? AND Enabled = 1", prod, "Scenario Player")
        If rs.%Next() Set n = +rs.%Get("N")
    } Catch {
        Set n = 0
    }
    If n = 0 Quit 0
    Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
    Quit (state = 1) && (name = prod)
}

ClassMethod ScenarioRun(id As %String) As %Status
{
    If '..Allow("Shutter_Operate", 1) Quit $$$OK
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Scenarios.Runner") Quit ..Fail("503 Service Unavailable", "no_runner", "The scenario runner is not installed")
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) Set body = {}
    Set mode = ##class(Shutter.Util.Json).Str(body, "mode", "board")
    If '$LISTFIND($LISTBUILD("board", "single", "rules", "policy"), mode) Quit ..Fail("400 Bad Request", "bad_request", "mode must be board, single, rules or policy")
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    If ..PlayerEnabled() {
        // The production's own player plays the steps (one run at a time); the run record says queued
        // until it starts, then running, done or failed (GET /scenarios).
        Set status = ##class(Shutter.Scenarios.Runner).Status()
        Set run = ##class(Shutter.Util.Json).Parse(status, .psc)
        If $ISOBJECT(run) && (run.state = "queued") Quit ..Fail("409 Conflict", "wrong_state", "a run of " _ run.scenario _ " is queued", run)
        If ##class(Shutter.Scenarios.Runner).Running() Quit ..Fail("409 Conflict", "wrong_state", "a run of " _ run.scenario _ " is still playing", run)
        Set out = {"scenario": (id), "mode": (mode), "state": "queued", "files": [], "timeouts": []}
        Do out.%Set("running", 1, "boolean")
        Set out.queuedAt = ##class(Shutter.Util.Time).NowUTC()
        Set ^Shutter.Scenarios("run") = out.%ToJSON()
        Kill ^Shutter.Scenarios("run", "job")
        Set msg = ##class(Shutter.Msg.ScenarioRun).%New()
        Set msg.Scenario = id, msg.Mode = mode, msg.RequestedBy = $USERNAME
        Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .service)
        If $$$ISERR(sc) || '$ISOBJECT(service) Quit ..Fail("503 Service Unavailable", "no_service", "The API service is not running: " _ $SYSTEM.Status.GetErrorText(sc))
        Set service.Target = "Scenario Player", service.Async = 1
        Set sc = service.ProcessInput(msg)
        If $$$ISERR(sc) {
            Kill ^Shutter.Scenarios("run")
            Quit ..Fail("503 Service Unavailable", "not_queued", "The run could not be queued: " _ $SYSTEM.Status.GetErrorText(sc))
        }
    } Else {
        // Without the player: Start plays the steps in a background job and returns at once; Run is the synchronous fallback.
        Set method = $SELECT(##class(%Dictionary.CompiledMethod).%ExistsId("Shutter.Scenarios.Runner||Start"): "Start", 1: "Run")
        Set result = $CLASSMETHOD("Shutter.Scenarios.Runner", method, id, mode)
        Set out = ##class(Shutter.Util.Json).Parse(result, .sc)
        If '$ISOBJECT(out) Set out = {"result": (result)}
        If out.%GetTypeOf("error") '= "unassigned" Quit ..Fail("409 Conflict", "wrong_state", ##class(Shutter.Util.Json).Str(out, "detail", out.error), out)
    }
    Set text = out.%ToJSON()
    Do ..Remember(bodyText, "202 Accepted", text)
    Set %response.Status = "202 Accepted"
    Write text
    Quit $$$OK
}

ClassMethod ScenarioReset() As %Status
{
    If '..Allow("Shutter_Operate", 1) Quit $$$OK
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Scenarios.Runner") Quit ..Fail("503 Service Unavailable", "no_runner", "The scenario runner is not installed")
    Set result = $CLASSMETHOD("Shutter.Scenarios.Runner", "Reset")
    Set out = ##class(Shutter.Util.Json).Parse(result, .sc)
    If '$ISOBJECT(out) Set out = {"result": (result)}
    Set out.resetAt = $GET(^Shutter.Config("resetAt"))
    Quit ..Json(out)
}

// ---- cases ----

ClassMethod Cases() As %Status
{
    If '..Allow() Quit $$$OK
    Set state = $GET(%request.Data("state", 1)), scenario = $GET(%request.Data("scenario", 1))
    Set limit = +$GET(%request.Data("limit", 1), 50), offset = +$GET(%request.Data("offset", 1), 0)
    If limit < 1 Set limit = 50
    If limit > 500 Set limit = 500
    If offset < 0 Set offset = 0
    If offset > 100000 Set offset = 100000
    Set where = "", args = 0
    If state '= "" Set where = where _ " AND State = ?", args = args + 1, args(args) = state
    If scenario '= "" Set where = where _ " AND Scenario = ?", args = args + 1, args(args) = scenario
    Set total = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N FROM Shutter_Store.""Case"" WHERE 1=1" _ where, args...)
    If rs.%Next() Set total = rs.%Get("N")
    // One page: only the first offset + limit ids are read, newest first, and the offset is skipped (E8).
    // The current plan's origin comes with the ids, so the list opens no plan row for its one column.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ (offset + limit) _ " c.ID, p.CreatedBy AS PlanCreatedBy FROM Shutter_Store.""Case"" c LEFT JOIN Shutter_Store.Plan p ON c.CurrentPlan = p.ID WHERE 1=1" _ where _ " ORDER BY c.ID DESC", args...)
    Set items = [], n = 0
    While rs.%Next() {
        Set n = n + 1
        If n <= offset Continue
        Set c = ##class(Shutter.Store.Case).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Set o = ..Project(c)
        If $ISOBJECT(c.Incident) Set o.incidentId = c.Incident.IncidentId
        // Who made the current plan (the board's or the investigator's run, the site's policy, rules alone)
        If rs.%Get("PlanCreatedBy") '= "" Set o.planCreatedBy = rs.%Get("PlanCreatedBy")
        Do items.%Push(o)
    }
    Set out = {}
    Set out.items = items, out.total = total
    Quit ..Json(out)
}

ClassMethod CaseGet(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set o = ..Project(case)
    If $ISOBJECT(case.CurrentPlan) Set o.planCreatedBy = case.CurrentPlan.CreatedBy
    // The case's place in its incident (CONTRACTS 7.5), when one holds it.
    If $ISOBJECT(case.Incident) Set o.incidentId = case.Incident.IncidentId, o.incident = ##class(Shutter.Store.ChainItem).IncidentContext(case)
    Set id = case.%Id()
    Set counts = {}
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.CaseEvent WHERE "Case" = :id)
    Set counts.events = +n
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.AgentRun WHERE "Case" = :id)
    Set counts.runs = +n
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.Finding WHERE "Case" = :id)
    Set counts.findings = +n
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.Plan WHERE "Case" = :id)
    Set counts.plans = +n
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.Approval WHERE "Case" = :id)
    Set counts.approvals = +n
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.ExecutionAttempt WHERE "Case" = :id)
    Set counts.attempts = +n
    Set o.counts = counts
    Set links = {}
    Set links.visualTrace = ..PortalPath() _ "EnsPortal.VisualTrace.zen?SESSIONID=" _ case.EnsSessionId
    Set links.workflowTrace = ..PortalPath() _ "EnsPortal.VisualTrace.zen?SESSIONID=" _ case.WorkflowSessionId
    Set o.links = links
    Quit ..Json(o)
}

ClassMethod CaseEvents(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Quit ..Json(case.Events())
}

ClassMethod CaseSnapshot(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set snap = case.CurrentSnapshot
    If '$ISOBJECT(snap) Quit ..Fail("404 Not Found", "no_snapshot", "The case has no snapshot yet")
    Set o = ..Project(snap)
    Set o.summary = snap.SummaryObject()
    Set o.items = snap.Items()
    Quit ..Json(o)
}

ClassMethod CaseRuns(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.AgentRun WHERE ""Case"" = ? ORDER BY ID", case.%Id())
    While rs.%Next() {
        Set run = ##class(Shutter.Store.AgentRun).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(run)
        Set o = ..Project(run)
        If run.ResultJSON '= "" Set o.result = ##class(Shutter.Util.Json).Parse(run.ResultJSON, .psc)
        Set m = ##class(Shutter.Store.BoardMember).ByCode(run.MemberCode)
        If $ISOBJECT(m) { Set mm = {} Set mm.code = m.Code, mm.name = m.Name, mm.perspective = m.Perspective Set o.member = mm } Else { Do o.%Set("member", "", "null") }
        Set fid = "", rid = run.%Id()
        &sql(SELECT TOP 1 ID INTO :fid FROM Shutter_Store.Finding WHERE Run = :rid)
        If (SQLCODE = 0) && (fid '= "") { Set o.finding = ..Project(##class(Shutter.Store.Finding).%OpenId(fid)) } Else { Do o.%Set("finding", "", "null") }
        Set o.toolCalls = ##class(Shutter.Bridge.ToolCall).ForRun(run.EnsMessageId)
        Set o.messageLink = ..PortalPath() _ "EnsPortal.MessageContents.zen?HeaderId=" _ run.EnsMessageId
        Do out.%Push(o)
    }
    Quit ..Json(out)
}

ClassMethod CasePlan(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set plan = case.CurrentPlan
    If '$ISOBJECT(plan) Quit ..Fail("404 Not Found", "no_plan", "The case has no plan yet")
    Set o = {}
    Set p = ..Project(plan)
    Set p.plan = plan.PlanObject()
    For f = "preconditions", "evidenceRefs", "disagreements" {
        If p.%GetTypeOf(f) = "string" Do p.%Set(f, ##class(Shutter.Util.Json).Parse(p.%Get(f), .psc))
    }
    Set o.plan = p
    Set o.gateDecisions = ..Rows("Shutter.Store.GateDecision", "SELECT ID FROM Shutter_Store.GateDecision WHERE Plan = ? ORDER BY ID", plan.%Id())
    Set iter = o.gateDecisions.%GetIterator()
    While iter.%GetNext(.i, .d) { If d.%GetTypeOf("checks") = "string" Set d.checks = ##class(Shutter.Util.Json).Parse(d.checks, .psc) }
    Set rid = "", planId = plan.%Id()
    &sql(SELECT TOP 1 ID INTO :rid FROM Shutter_Store.Rehearsal WHERE Plan = :planId ORDER BY ID DESC)
    If (SQLCODE = 0) && (rid '= "") {
        Set r = ..Project(##class(Shutter.Store.Rehearsal).%OpenId(rid))
        If r.%GetTypeOf("response") = "string" Set r.response = ##class(Shutter.Util.Json).Parse(r.response, .psc)
        Set o.rehearsal = r
    } Else { Do o.%Set("rehearsal", "", "null") }
    Quit ..Json(o)
}

ClassMethod CaseApprovals(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set o = {}
    Try {
        Set o.approvals = ..Rows("Shutter.Store.Approval", "SELECT ID FROM Shutter_Store.Approval WHERE ""Case"" = ? ORDER BY ID", case.%Id())
    } Catch ex {
        Set o.approvals = [], o.approvalsError = ex.DisplayString()
    }
    Try {
        Set o.tasks = ##class(Shutter.Util.Workflow).TasksFor(caseId)
    } Catch ex {
        Set o.tasks = [], o.tasksError = ex.DisplayString()
    }
    Quit ..Json(o)
}

ClassMethod CaseApprove(caseId As %String) As %Status
{
    If '..Allow("Shutter_Approve", 1) Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) Set body = {}
    Set decision = $ZCONVERT(##class(Shutter.Util.Json).Str(body, "decision"), "L")
    If '$LISTFIND($LISTBUILD("approve", "reject"), decision) Quit ..Fail("400 Bad Request", "bad_request", "decision must be approve or reject")
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    If case.State '= "awaiting_approval" Quit ..Fail("409 Conflict", "wrong_state", "The case is " _ case.State _ ", not awaiting approval")
    Set plan = case.CurrentPlan
    Set digest = ##class(Shutter.Util.Json).Str(body, "planDigest")
    If '$ISOBJECT(plan) || (digest '= plan.Digest) {
        Set extra = {} Set extra.currentDigest = $SELECT($ISOBJECT(plan): plan.Digest, 1: "")
        Quit ..Fail("409 Conflict", "stale_version", "planDigest is not the current plan's digest", extra)
    }
    Set expected = ##class(Shutter.Util.Json).Str(body, "expectedVersion")
    If (expected = "") || (+expected '= case.Version) {
        Set extra = {} Set extra.currentVersion = case.Version
        Quit ..Fail("409 Conflict", "stale_version", "expectedVersion is not the case's version", extra)
    }
    Set comment = ##class(Shutter.Util.Json).Str(body, "comment")
    // The decider is the signed-in user, never a name from the body; the task takes the digest the body named (CONTRACTS 5).
    Set result = ##class(Shutter.Util.Workflow).Decide(caseId, $SELECT(decision = "reject": "Reject", 1: "Approve"), digest, comment)
    Set out = ##class(Shutter.Util.Json).Parse(result, .psc)
    If '$ISOBJECT(out) Set out = {"result": (result)}
    If out.%GetTypeOf("error") '= "unassigned" {
        If $LISTFIND($LISTBUILD("not_in_role", "forbidden"), ##class(Shutter.Util.Json).Str(out, "code")) Quit ..Fail("403 Forbidden", "forbidden", out.error)
        Quit ..Fail("409 Conflict", "wrong_state", out.error)
    }
    Set reply = {}
    Set reply.taskId = out."task_id", reply.decision = decision, reply.caseId = caseId, reply.approver = out.user
    Set text = reply.%ToJSON()
    Do ..Remember(bodyText, "202 Accepted", text)
    Set %response.Status = "202 Accepted"
    Write text
    Quit $$$OK
}

ClassMethod CaseAttempts(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.ExecutionAttempt WHERE ""Case"" = ? ORDER BY ID", case.%Id())
    While rs.%Next() {
        Set a = ##class(Shutter.Store.ExecutionAttempt).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(a)
        Set pair = {}
        Set ap = ..Project(a)
        For f = "receipt", "response" { If ap.%GetTypeOf(f) = "string" Do ap.%Set(f, ##class(Shutter.Util.Json).Parse(ap.%Get(f), .psc)) }
        Set pair.attempt = ap
        Set vid = "", aid = a.%Id()
        &sql(SELECT TOP 1 ID INTO :vid FROM Shutter_Store.Verification WHERE Attempt = :aid ORDER BY ID DESC)
        If (SQLCODE = 0) && (vid '= "") {
            Set v = ..Project(##class(Shutter.Store.Verification).%OpenId(vid))
            If v.%GetTypeOf("detail") = "string" Set v.detail = ##class(Shutter.Util.Json).Parse(v.detail, .psc)
            Set pair.verification = v
        } Else { Do pair.%Set("verification", "", "null") }
        Do out.%Push(pair)
    }
    // Verifications without an attempt (non-write dispositions).
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Verification WHERE ""Case"" = ? AND Attempt IS NULL ORDER BY ID", case.%Id())
    While rs.%Next() {
        Set v = ..Project(##class(Shutter.Store.Verification).%OpenId(rs.%Get("ID")))
        If v.%GetTypeOf("detail") = "string" Set v.detail = ##class(Shutter.Util.Json).Parse(v.detail, .psc)
        Set pair = {} Do pair.%Set("attempt", "", "null") Set pair.verification = v
        Do out.%Push(pair)
    }
    Quit ..Json(out)
}

ClassMethod CaseClosure(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    If 'case.IsClosed() Quit ..Fail("404 Not Found", "not_closed", "The case is still " _ case.State)
    Set o = {}
    Set o.caseId = case.CaseId, o.state = case.State, o.disposition = case.Disposition, o.outcome = case.Outcome, o.closedAt = case.ClosedAt
    Set vid = "", id = case.%Id()
    &sql(SELECT TOP 1 ID INTO :vid FROM Shutter_Store.Verification WHERE "Case" = :id ORDER BY ID DESC)
    Set verified = [], unverified = []
    If (SQLCODE = 0) && (vid '= "") {
        Set v = ##class(Shutter.Store.Verification).%OpenId(vid)
        Set vp = ..Project(v)
        Set detail = ##class(Shutter.Util.Json).Parse(v.DetailJSON, .psc)
        If $ISOBJECT(detail) Set vp.detail = detail
        Set o.verification = vp
        If (v.Outcome = "verified") && $ISOBJECT(detail) {
            Set enc = detail.%Get("encounter")
            If $ISOBJECT(enc) Do verified.%Push("The downstream system holds encounter " _ case.EncounterId _ " as " _ ##class(Shutter.Util.Json).Str(enc, "state") _ $SELECT(##class(Shutter.Util.Json).Str(enc, "ward") '= "": " in " _ enc.ward, 1: "") _ " at version " _ ##class(Shutter.Util.Json).Str(enc, "version"))
            If detail.%GetTypeOf("receipt") = "object" && (##class(Shutter.Util.Json).Str(detail, "receipt_http_status") = 200) Do verified.%Push("A receipt exists for the operation key")
            If ##class(Shutter.Util.Json).Str(detail, "history_note") '= "" Do unverified.%Push(detail."history_note")
        }
    } Else { Do o.%Set("verification", "", "null") }
    Do unverified.%Push("Consumers beyond the downstream system are outside the production's view and are not verified")
    Set o.verifiedEffects = verified, o.unverified = unverified
    Set actors = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT DISTINCT %EXACT(Actor) AS Actor FROM Shutter_Store.CaseEvent WHERE ""Case"" = ? ORDER BY Actor", id)
    While rs.%Next() { Do actors.%Push(rs.%Get("Actor")) }
    Set o.actors = actors
    Set pv = ""
    &sql(SELECT TOP 1 PolicyVersion INTO :pv FROM Shutter_Store.GateDecision WHERE "Case" = :id ORDER BY ID DESC)
    Set o.policyVersion = $GET(pv)
    Quit ..Json(o)
}

ClassMethod CasePreview(caseId As %String) As %Status
{
    If '..Allow("Shutter_Operate", 1) Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    If case.IsClosed() Quit ..Fail("409 Conflict", "wrong_state", "The case is closed")
    // A preview is a dry run: it goes only to a receiver whose capability profile, as the case's evidence read it, reports one
    // (v1.19); to any other it would be a live write conditional on nothing, so nothing is sent.
    Set snap = case.CurrentSnapshot
    Set route = $SELECT($ISOBJECT(snap): snap.SummaryObject().%Get("route"), 1: "")
    If '$ISOBJECT(route) || (##class(Shutter.Util.Json).Str(route, "capabilities_http_status") '= 200) || '##class(Shutter.Util.Json).Bool(route, "dry_run") {
        Quit ..Fail("409 Conflict", "dry_run_unsupported", "The receiver's capability profile reports no dry run (or could not be read), so a preview cannot be made without writing; nothing was sent")
    }
    Set op = {}
    Set op."operation_key" = case.OperationKey, op."encounter_id" = case.EncounterId
    Set op."patient_id" = case.PatientId, op."patient_id_authority" = case.PatientIdAuthority
    Set op."event" = case.Event
    If case.Ward '= "" { Set op."ward" = case.Ward } Else { Do op.%Set("ward", "", "null") }
    Set op."event_time" = case.EventTime, op."source_system" = case.SourceSystem, op."source_message_id" = case.SourceMessageId
    Set w = ##class(Shutter.Msg.WardOperation).FromOperation(op)
    Set w.Purpose = "rehearsal", w.DryRun = 1, w.CaseId = case.CaseId
    Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .svc)
    If $$$ISERR(sc) || '$ISOBJECT($GET(svc)) Quit ..Fail("503 Service Unavailable", "no_production", "The production's API service is not running: " _ $SYSTEM.Status.GetErrorText(sc))
    Set svc.Target = $SELECT(case.Receiver '= "": case.Receiver, 1: $PARAMETER("Shutter.Production", "RECEIVER"))
    Set sc = svc.ProcessInput(w, .result)
    If $$$ISERR(sc) || '$ISOBJECT($GET(result)) Quit ..Fail("502 Bad Gateway", "ward_error", $SYSTEM.Status.GetErrorText(sc))
    Set resp = result.ResponseObject()
    Set applied = result.IsInEffect()
    Set rolledBack = (result.Outcome = "would_apply") || (result.Outcome = "would_not_apply")
    Set o = {}
    Do o.%Set("wouldApply", result.Outcome = "would_apply", "boolean")
    Set o.outcome = result.Outcome, o.reason = result.ReasonCode
    Set o.encounterAfter = resp.%Get("encounter_after")
    // What the dry run was checked against; a preview is conditional on nothing, so its expected version is null.
    Set checked = {}
    If result.EncounterVersion '= "" { Set checked.version = result.EncounterVersion } Else { Do checked.%Set("version", "", "null") }
    If result.Epoch '= "" { Set checked.epoch = result.Epoch } Else { Do checked.%Set("epoch", "", "null") }
    Set o.checkedAgainst = checked
    Do o.%Set("expectedVersion", "", "null")
    Do o.%Set("applied", applied, "boolean")
    Set against = $SELECT(result.EncounterVersion '= "": " at version " _ result.EncounterVersion, 1: "") _ $SELECT(result.Epoch '= "": " (epoch " _ result.Epoch _ ")", 1: "")
    If applied {
        // The receiver wrote the preview: it does not honour dry_run. The effect is on the case's record as an execution.
        Set o.note = "The receiver applied the preview (HTTP " _ result.HttpStatus _ "): it does not honour dry_run and the operation is now in effect"
        Do ##class(Ens.Util.Log).LogAlert($CLASSNAME(), "CasePreview", "Receiver " _ svc.Target _ " applied a blind-resend preview of " _ case.OperationKey _ " for " _ case.CaseId _ ": it does not honour dry_run")
        Do case.Note("execution", "The receiver applied the blind-resend preview requested by " _ ..User() _ " (HTTP " _ result.HttpStatus _ "): it does not honour dry_run and the operation is now in effect" _ against, ..User())
    } Else {
        Set o.note = $SELECT(rolledBack: "What a blind resend with no expected version would do at the downstream system now" _ against _ "; the dry run was rolled back and nothing was written", 1: "The downstream system did not answer the dry run as one (" _ result.Outcome _ $SELECT(result.Error '= "": ", " _ result.Error, 1: "") _ "); nothing is known to have been written")
        Do case.Note("note", "Blind-resend preview requested by " _ ..User() _ ": " _ result.Outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "") _ against, ..User())
    }
    Quit ..Json(o)
}

ClassMethod CaseBlockedReason(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    If '$LISTFIND($LISTBUILD("blocked", "escalated"), case.State) Quit ..Fail("404 Not Found", "not_blocked", "The case is " _ case.State)
    Set id = case.%Id(), did = ""
    &sql(SELECT TOP 1 ID INTO :did FROM Shutter_Store.GateDecision WHERE "Case" = :id AND Outcome <> 'pass' ORDER BY ID DESC)
    Set failing = [], code = ""
    If (SQLCODE = 0) && (did '= "") {
        Set d = ##class(Shutter.Store.GateDecision).%OpenId(did)
        Set checks = ##class(Shutter.Util.Json).Parse(d.ChecksJSON, .psc)
        If $ISOBJECT(checks) {
            Set iter = checks.%GetIterator()
            While iter.%GetNext(.i, .c) { If c.result '= "pass" { Do failing.%Push(c) If code = "" Set code = c."reason_code" } }
        }
    }
    If code = "" {
        Set text = ""
        &sql(SELECT TOP 1 Text INTO :text FROM Shutter_Store.CaseEvent WHERE "Case" = :id AND ToState IN ('blocked','escalated') ORDER BY Seq DESC)
        // A write whose answer was lost (Verify.Judge): not committed, or unknown after the last read, before the generic person clause.
        Set code = $SELECT(text [ "Rejected by": "REJECTED_BY_APPROVER", text [ "rehearsal": "REHEARSAL_WOULD_NOT_APPLY", text [ "refused": "DISPATCH_REFUSED", text [ "Not committed:": "WRITE_NOT_COMMITTED", (text [ "Not verified (unknown)") || (text [ "outcome of the resend is unknown"): "WRITE_OUTCOME_UNKNOWN", text [ "person": "ESCALATED", case.State = "escalated": "ESCALATED", 1: "BLOCKED")
    }
    Set o = {}
    Set o.code = code
    Set r = ##class(Shutter.Store.BlockReason).ByCode(code)
    If $ISOBJECT(r) { Set o.catalogue = ..Project(r) } Else { Do o.%Set("catalogue", "", "null") }
    Set o.failingChecks = failing
    Set o.state = case.State, o.headline = case.Headline
    Quit ..Json(o)
}

// ---- library, settings, costs ----

/// Reopen a blocked, escalated or failed case: a fresh instance collects fresh evidence and plans again.
// ---- escalations to the people who correct systems by hand (T29, S13) ----

/// The case's escalation drafts and sent emails, oldest first.
ClassMethod CaseEscalations(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Quit ..Json(##class(Shutter.Store.Escalation).ForCase(case))
}

/// A draft email for a team, built from the stored case without a model; a person edits and sends it.
ClassMethod CaseEscalationCreate(caseId As %String) As %Status
{
    If '..Allow("Shutter_Operate", 1) Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) Set body = {}
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    If 'case.IsClosed() || (case.State = "resolved") Quit ..Fail("409 Conflict", "wrong_state", "The case is " _ case.State _ "; only a blocked, escalated or failed case is escalated by email")
    Set sc = ##class(Shutter.Store.Escalation).Draft(case, $EXTRACT(##class(Shutter.Util.Json).Str(body, "teamId"), 1, 64), ..User(), .esc)
    If $$$ISERR(sc) Quit ..Fail("500 Internal Server Error", "draft_failed", $SYSTEM.Status.GetErrorText(sc))
    Set text = esc.ToObject().%ToJSON()
    Do ..Remember(bodyText, "201 Created", text)
    Set %response.Status = "201 Created"
    Set %response.ContentType = "application/json"
    Write text
    Quit $$$OK
}

/// Edit a draft (or a failed email): subject, body, to and cc; the body's digest moves with it.
ClassMethod CaseEscalationPatch(caseId As %String, seq As %String) As %Status
{
    If '..Allow("Shutter_Operate", 1) Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set esc = ##class(Shutter.Store.Escalation).BySeq(case, +seq)
    If '$ISOBJECT(esc) Quit ..Fail("404 Not Found", "not_found", "The case has no escalation " _ seq)
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) || $$$ISERR(psc) Quit ..Fail("400 Bad Request", "bad_request", "The body must be a JSON object with subject, body, to and cc")
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    // An escalation is edited only while its case still stands with the team (blocked, escalated or failed): after a
    // hand close or a reopening nothing more is written for the team to act on.
    If '$LISTFIND($LISTBUILD("blocked", "escalated", "failed"), case.State) Quit ..Fail("409 Conflict", "wrong_state", "The case is " _ case.State _ "; an escalation is edited only while the case is blocked, escalated or failed")
    Set json = "Shutter.Util.Json"
    For field = "subject", "body", "to", "cc" {
        If body.%IsDefined(field) && (body.%GetTypeOf(field) '= "string") Return ..Fail("400 Bad Request", "bad_request", "subject, body, to and cc must be strings")
    }
    Set subject = $SELECT(body.%IsDefined("subject"): $CLASSMETHOD(json, "Str", body, "subject"), 1: esc.Subject)
    Set text = $SELECT(body.%IsDefined("body"): $CLASSMETHOD(json, "Str", body, "body"), 1: esc.Body)
    Set to = $SELECT(body.%IsDefined("to"): $CLASSMETHOD(json, "Str", body, "to"), 1: esc.ToAddr)
    Set cc = $SELECT(body.%IsDefined("cc"): $CLASSMETHOD(json, "Str", body, "cc"), 1: esc.CcAddr)
    // The email as it would stand: the subject carries no line break, and the addresses a person types are bare
    // addresses inside the site's allowed domains (CONTRACTS 10).
    Set problem = ##class(Shutter.Store.Escalation).Problem(subject, to, cc, .field)
    If problem '= "" Quit ..EscalationRefused(field, problem)
    Set sc = esc.Edit(subject, text, to, cc, ..User())
    If $$$ISERR(sc) {
        Set why = $SYSTEM.Status.GetErrorText(sc)
        Set field = $SELECT($EXTRACT(why, 1, 9) = "subject: ": "subject", $EXTRACT(why, 1, 4) = "to: ": "to", $EXTRACT(why, 1, 4) = "cc: ": "cc", 1: "")
        If field '= "" Quit ..EscalationRefused(field, $PIECE(why, ": ", 2, *))
        If $ZCONVERT(why, "U") [ "MAXLEN" Quit ..Fail("400 Bad Request", "bad_request", "too long: the subject at most 500 characters, to and cc at most 2000")
        Quit ..Fail("409 Conflict", "wrong_state", why)
    }
    Set text = esc.ToObject().%ToJSON()
    Do ..Remember(bodyText, "200 OK", text)
    Set %response.ContentType = "application/json"
    Write text
    Quit $$$OK
}

/// The 422 of an escalation's subject or address the rules refuse (CONTRACTS 10): subject_not_allowed for the subject,
/// address_not_allowed for to and cc, the field named.
ClassMethod EscalationRefused(field As %String, problem As %String) As %Status [ Private ]
{
    Set extra = {} Set extra.field = field
    If field = "subject" Quit ..Fail("422 Unprocessable Entity", "subject_not_allowed", "The subject must not contain line breaks or control characters", extra)
    Quit ..Fail("422 Unprocessable Entity", "address_not_allowed", "The " _ field _ " address is not allowed: " _ problem, extra)
}

/// Send a draft: the body's digest must be the one the person read; the mail goes through the Escalation Mail
/// operation (the site's mail server, or an .eml file when none is set), and the answer is the queued escalation.
ClassMethod CaseEscalationSend(caseId As %String, seq As %String) As %Status
{
    If '..Allow("Shutter_Operate", 1) Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set esc = ##class(Shutter.Store.Escalation).BySeq(case, +seq)
    If '$ISOBJECT(esc) Quit ..Fail("404 Not Found", "not_found", "The case has no escalation " _ seq)
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) Set body = {}
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    // Sent only while the case still stands with the team: a case closed by hand or reopened takes no more email.
    If '$LISTFIND($LISTBUILD("blocked", "escalated", "failed"), case.State) Quit ..Fail("409 Conflict", "wrong_state", "The case is " _ case.State _ "; an escalation is sent only while the case is blocked, escalated or failed")
    Set digest = ##class(Shutter.Util.Json).Str(body, "bodyDigest")
    If digest = "" Quit ..Fail("400 Bad Request", "bad_request", "bodyDigest is required: the digest of the body as read")
    If esc.ToAddr = "" Quit ..Fail("409 Conflict", "no_recipient", "The escalation has no recipient; edit it with a team mailbox first")
    // Checked again at the send: the allowed domains may have changed since the draft was edited.
    Set problem = esc.Check(.field)
    If problem '= "" Quit ..EscalationRefused(field, problem)
    Set sc = esc.Queue(digest, ..User())
    If $$$ISERR(sc) {
        Set why = $SYSTEM.Status.GetErrorText(sc)
        Set field = $SELECT($EXTRACT(why, 1, 9) = "subject: ": "subject", $EXTRACT(why, 1, 4) = "to: ": "to", $EXTRACT(why, 1, 4) = "cc: ": "cc", 1: "")
        If field '= "" Quit ..EscalationRefused(field, $PIECE(why, ": ", 2, *))
        Set extra = {} Set extra.bodyDigest = esc.BodyDigest, extra.state = esc.State
        Quit ..Fail("409 Conflict", $SELECT($ZCONVERT(why, "L") [ "digest": "body_changed", 1: "wrong_state"), why, extra)
    }
    Set msg = ##class(Shutter.Msg.EscalationSend).%New()
    Set msg.EscalationId = esc.%Id()
    Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .service)
    If $$$ISERR(sc) || '$ISOBJECT(service) Quit ..Fail("503 Service Unavailable", "no_service", "The API service is not running: " _ $SYSTEM.Status.GetErrorText(sc))
    Set service.Target = "Escalation Mail", service.Async = 1
    Set sc = service.ProcessInput(msg)
    If $$$ISERR(sc) Quit ..Fail("503 Service Unavailable", "not_queued", "The email could not be queued: " _ $SYSTEM.Status.GetErrorText(sc))
    Set text = esc.ToObject().%ToJSON()
    Do ..Remember(bodyText, "202 Accepted", text)
    Set %response.Status = "202 Accepted"
    Set %response.ContentType = "application/json"
    Write text
    Quit $$$OK
}

ClassMethod CaseReinvestigate(caseId As %String) As %Status
{
    If '..Allow("Shutter_Operate", 1) Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) Set body = {}
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    If 'case.IsClosed() || (case.State = "resolved") Quit ..Fail("409 Conflict", "wrong_state", "The case is " _ case.State _ "; only a blocked, escalated or failed case can be reopened")
    Set msg = ##class(Shutter.Msg.Reinvestigate).%New()
    Set msg.CaseId = caseId, msg.RequestedBy = ..User(), msg.Reason = $EXTRACT(##class(Shutter.Util.Json).Str(body, "reason"), 1, 2000)
    Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .service)
    If $$$ISERR(sc) || '$ISOBJECT(service) Quit ..Fail("503 Service Unavailable", "no_service", "The API service is not running: " _ $SYSTEM.Status.GetErrorText(sc))
    Set service.Target = "Case Workflow", service.Async = 1
    Set sc = service.ProcessInput(msg)
    If $$$ISERR(sc) Quit ..Fail("503 Service Unavailable", "not_queued", "The case could not be reopened: " _ $SYSTEM.Status.GetErrorText(sc))
    Set reply = {}
    Set reply.caseId = caseId, reply.state = "reopening", reply.requestedBy = ..User()
    Set text = reply.%ToJSON()
    Do ..Remember(bodyText, "202 Accepted", text)
    Set %response.Status = "202 Accepted"
    Write text
    Quit $$$OK
}

/// Close a case the team handled by hand (T31, 2.6): an escalated, blocked or failed case resolves with disposition
/// handled_by_hand through the Case Workflow item, as a reopening runs through it, and its open approval task is
/// cancelled. Reinvestigate stays for a correction the receiver's state can prove. An operator closes it, unless the
/// site profile keeps the two-person rule (approvers.close_needs_approver), when only an approver does.
ClassMethod CaseClose(caseId As %String) As %Status
{
    If '..Allow("Shutter_Operate", 1) Quit $$$OK
    If ##class(Shutter.Store.SiteProfile).CloseNeedsApprover() && '$SYSTEM.Security.Check("Shutter_Approve", "USE") Quit ..Fail("403 Forbidden", "forbidden", "On this site closing a case by hand needs an approver (the site profile's approvers.close_needs_approver): ask an approver to mark it handled")
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) || $$$ISERR(psc) Quit ..Fail("400 Bad Request", "bad_request", "The body must be a JSON object with reason")
    If $CLASSNAME(body) '= "%Library.DynamicObject" Quit ..Fail("400 Bad Request", "bad_request", "The body must be a JSON object with reason")
    Set reason = ""
    If $LISTFIND($LISTBUILD("string", "number"), body.%GetTypeOf("reason")) Set reason = $ZSTRIP($EXTRACT(##class(Shutter.Util.Json).Str(body, "reason"), 1, 2000), "<>W")
    If reason = "" Quit ..Fail("400 Bad Request", "bad_request", "reason is required: what the team did")
    Set expected = ##class(Shutter.Util.Json).Str(body, "expectedVersion")
    If (expected '= "") && (+expected '= case.Version) {
        Set extra = {} Set extra.currentVersion = case.Version
        Quit ..Fail("409 Conflict", "stale_version", "expectedVersion is not the case's version", extra)
    }
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    If '$LISTFIND($LISTBUILD("escalated", "blocked", "failed"), case.State) Quit ..Fail("409 Conflict", "wrong_state", "The case is " _ case.State _ "; only an escalated, blocked or failed case can be marked handled")
    Set msg = ##class(Shutter.Msg.CaseClose).%New()
    Set msg.CaseId = caseId, msg.Reason = reason, msg.Actor = ..User()
    If expected '= "" Set msg.ExpectedVersion = +expected
    Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .service)
    If $$$ISERR(sc) || '$ISOBJECT(service) Quit ..Fail("503 Service Unavailable", "no_service", "The API service is not running: " _ $SYSTEM.Status.GetErrorText(sc))
    Set service.Target = "Case Workflow", service.Async = 1
    Set sc = service.ProcessInput(msg)
    If $$$ISERR(sc) Quit ..Fail("503 Service Unavailable", "not_queued", "The case could not be closed: " _ $SYSTEM.Status.GetErrorText(sc))
    Set reply = {}
    Set reply.caseId = caseId, reply.state = "closing", reply.requestedBy = ..User(), reply.reason = reason
    Set text = reply.%ToJSON()
    Do ..Remember(bodyText, "202 Accepted", text)
    Set %response.Status = "202 Accepted"
    Write text
    Quit $$$OK
}

/// Abandon a case the workflow left in a working state (CONTRACTS 5): an approver gives up a case whose instance
/// stopped moving (a restart in the middle of its work, an answer that never came), through the Case Workflow item as
/// a close runs through it, so it shows in the trace. Approver only, whatever the site profile says. Refused while the
/// case's workflow has a message in flight (409 busy, with what is in flight: Shutter.Store.Case.InFlight), so a case
/// that is merely waiting, on an approver among others, is not thrown away; a closed case is marked handled or
/// reopened instead (409 wrong_state).
ClassMethod CaseAbandon(caseId As %String) As %Status
{
    If '..Allow("Shutter_Approve", 1) Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) || $$$ISERR(psc) Quit ..Fail("400 Bad Request", "bad_request", "The body must be a JSON object with reason")
    If $CLASSNAME(body) '= "%Library.DynamicObject" Quit ..Fail("400 Bad Request", "bad_request", "The body must be a JSON object with reason")
    Set reason = ""
    If $LISTFIND($LISTBUILD("string", "number"), body.%GetTypeOf("reason")) Set reason = $ZSTRIP($EXTRACT(##class(Shutter.Util.Json).Str(body, "reason"), 1, 2000), "<>W")
    If reason = "" Quit ..Fail("400 Bad Request", "bad_request", "reason is required: why the case is given up")
    Set expected = ##class(Shutter.Util.Json).Str(body, "expectedVersion")
    If (expected '= "") && (+expected '= case.Version) {
        Set extra = {} Set extra.currentVersion = case.Version
        Quit ..Fail("409 Conflict", "stale_version", "expectedVersion is not the case's version", extra)
    }
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    If case.IsClosed() Quit ..Fail("409 Conflict", "wrong_state", "The case is " _ case.State _ "; a closed case is marked handled (POST /cases/" _ caseId _ "/close) or reopened (POST /cases/" _ caseId _ "/reinvestigate), not abandoned")
    Set minutes = ##class(Shutter.Store.Case).AbandonAfterMinutes()
    Set inFlight = ##class(Shutter.Store.Case).InFlight(case, minutes, .newestAt, .deferred, .session)
    If inFlight > 0 {
        Set extra = {}
        Set extra.state = case.State, extra.inFlight = inFlight
        If newestAt '= "" { Set extra.newestAt = newestAt } Else { Do extra.%Set("newestAt", "", "null") }
        Do extra.%Set("deferred", ''deferred, "boolean")
        If deferred {
            Set detail = "The case waits for a person: an approval task is open, so reject the plan (POST /cases/" _ caseId _ "/approvals) instead of abandoning the case"
        } ElseIf session = "" {
            Set detail = "The case moved at " _ newestAt _ " and has no workflow session yet; a case counts as left behind once nothing has moved for " _ minutes _ " minutes"
        } Else {
            Set detail = "The case's workflow has " _ inFlight _ " message" _ $SELECT(inFlight = 1: "", 1: "s") _ " in flight (newest " _ newestAt _ "); a case counts as left behind once nothing has moved for " _ minutes _ " minutes"
        }
        Quit ..Fail("409 Conflict", "busy", detail, extra)
    }
    Set msg = ##class(Shutter.Msg.CaseAbandon).%New()
    Set msg.CaseId = caseId, msg.Reason = reason, msg.Actor = ..User()
    If expected '= "" Set msg.ExpectedVersion = +expected
    Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .service)
    If $$$ISERR(sc) || '$ISOBJECT(service) Quit ..Fail("503 Service Unavailable", "no_service", "The API service is not running: " _ $SYSTEM.Status.GetErrorText(sc))
    Set service.Target = "Case Workflow", service.Async = 1
    Set sc = service.ProcessInput(msg)
    If $$$ISERR(sc) Quit ..Fail("503 Service Unavailable", "not_queued", "The case could not be abandoned: " _ $SYSTEM.Status.GetErrorText(sc))
    Set reply = {}
    Set reply.caseId = caseId, reply.state = "abandoning", reply.requestedBy = ..User(), reply.reason = reason
    Set text = reply.%ToJSON()
    Do ..Remember(bodyText, "202 Accepted", text)
    Set %response.Status = "202 Accepted"
    Write text
    Quit $$$OK
}

/// Open a case for a delivery that failed in another production (CONTRACTS 11): the forwarder in the watched
/// production posts the HL7 message's text with where it came from, the receiver and how the delivery failed. The
/// intake goes through the API service to the Case Intake item synchronously, so the answer carries the case id.
/// Shutter_Intake, the X-Requested-With header and an optional Idempotency-Key; 202 {caseId, state, opened}; 400
/// bad_request naming the field when the body is not a JSON object, message is missing or is not an HL7 message, or
/// failure.kind is not one of the four kinds.
ClassMethod Intake() As %Status
{
    If '..Allow("Shutter_Intake", 1) Quit $$$OK
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) || $$$ISERR(psc) Quit ..Fail("400 Bad Request", "bad_request", "The body must be a JSON object with message, failure, source and receiver")
    If $CLASSNAME(body) '= "%Library.DynamicObject" Quit ..Fail("400 Bad Request", "bad_request", "The body must be a JSON object with message, failure, source and receiver")
    Set message = ""
    If body.%GetTypeOf("message") = "string" Set message = body.%Get("message")
    If $ZSTRIP(message, "<>WC") = "" Quit ..Fail("400 Bad Request", "bad_request", "message is required: the HL7 message's text, segments separated by carriage returns")
    If $EXTRACT($ZSTRIP(message, "<WC"), 1, 3) '= "MSH" Quit ..Fail("400 Bad Request", "bad_request", "message must be an HL7 message: it does not start with MSH")
    If body.%GetTypeOf("failure") '= "object" Quit ..Fail("400 Bad Request", "bad_request", "failure is required: an object with kind")
    Set failure = body.failure
    Set kind = ##class(Shutter.Util.Json).Str(failure, "kind")
    If '$LISTFIND($LISTBUILD("delivery_failed", "rejected", "uncertain_outcome", "unmappable"), kind) Quit ..Fail("400 Bad Request", "bad_request", "failure.kind must be delivery_failed, rejected, uncertain_outcome or unmappable")
    Set mode = ##class(Shutter.Util.Json).Str(body, "mode")
    If (mode '= "") && '$LISTFIND($LISTBUILD("board", "single", "rules", "policy"), mode) Quit ..Fail("400 Bad Request", "bad_request", "mode must be board, single, rules or policy")
    Set source = $SELECT(body.%GetTypeOf("source") = "object": body.source, 1: {})
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    Set msg = ##class(Shutter.Msg.ExternalIntake).%New()
    Set msg.SourceNamespace = $EXTRACT(##class(Shutter.Util.Json).Str(source, "namespace"), 1, 64)
    Set msg.SourceProduction = $EXTRACT(##class(Shutter.Util.Json).Str(source, "production"), 1, 128)
    Set msg.SourceRoute = $EXTRACT(##class(Shutter.Util.Json).Str(source, "route"), 1, 128)
    Set msg.OriginHeaderId = $EXTRACT(##class(Shutter.Util.Json).Str(source, "header_id"), 1, 40)
    Set msg.Receiver = $EXTRACT(##class(Shutter.Util.Json).Str(body, "receiver"), 1, 128)
    Set msg.FailureKind = kind
    Set msg.FailureText = $EXTRACT(##class(Shutter.Util.Json).Str(failure, "text"), 1, 2000)
    Set msg.FailureOutcome = $EXTRACT(##class(Shutter.Util.Json).Str(failure, "outcome"), 1, 32)
    Set msg.FailureReasonCode = $EXTRACT(##class(Shutter.Util.Json).Str(failure, "reason_code"), 1, 100)
    Set status = ##class(Shutter.Util.Json).Str(failure, "http_status")
    If +status > 0 Set msg.FailureHttpStatus = +status
    Set msg.MessageText = message
    Set msg.SchemaCategory = $EXTRACT(##class(Shutter.Util.Json).Str(body, "schema_category", "2.5.1"), 1, 32)
    Set msg.Mode = mode
    Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .service)
    If $$$ISERR(sc) || '$ISOBJECT($GET(service)) Quit ..Fail("503 Service Unavailable", "no_service", "The API service is not running: " _ $SYSTEM.Status.GetErrorText(sc))
    Set service.Target = "Case Intake", service.Async = 0
    Set sc = service.ProcessInput(msg, .started)
    If $$$ISERR(sc) Quit ..Fail("503 Service Unavailable", "not_queued", "The case could not be opened: " _ $SYSTEM.Status.GetErrorText(sc))
    If '$ISOBJECT($GET(started)) || 'started.%IsA("Shutter.Msg.CaseStarted") Quit ..Fail("503 Service Unavailable", "not_queued", "The case intake did not answer")
    Set reply = {}
    Set reply.caseId = started.CaseId, reply.state = started.State
    Do reply.%Set("opened", ''started.Opened, "boolean")
    Set text = reply.%ToJSON()
    Do ..Remember(bodyText, "202 Accepted", text)
    Set %response.Status = "202 Accepted"
    Write text
    Quit $$$OK
}

ClassMethod Library() As %Status
{
    If '..Allow() Quit $$$OK
    Quit ..Json(..Rows("Shutter.Store.BoardMember", "SELECT ID FROM Shutter_Store.BoardMember ORDER BY Sort, Code"))
}

/// Change which agents sit on the board: by an approver, as the site profile is saved.
ClassMethod LibraryPatch(code As %String) As %Status
{
    If '..Allow("Shutter_Approve", 1) Quit $$$OK
    Set m = ##class(Shutter.Store.BoardMember).ByCode(code)
    If '$ISOBJECT(m) Quit ..Fail("404 Not Found", "not_found", "No library member " _ code)
    Set body = ..Body()
    Set iter = body.%GetIterator()
    Set bad = ""
    While iter.%GetNext(.key, .value) {
        If key = "enabled" { Set m.Enabled = ''value }
        ElseIf key = "inDefaultBoard" { Set m.InDefaultBoard = ''value }
        ElseIf key = "sort" { Set m.Sort = +value }
        Else { Set bad = key Quit }
    }
    If bad '= "" Quit ..Fail("400 Bad Request", "bad_request", bad _ " is code-defined and cannot be changed here")
    Set sc = m.%Save()
    If $$$ISERR(sc) Quit ..Fail("500 Internal Server Error", "save_failed", $SYSTEM.Status.GetErrorText(sc))
    Quit ..Json(..Project(m))
}

/// The current site profile (CONTRACTS 6.4) with its version and who set it.
ClassMethod SiteProfileGet() As %Status
{
    If '..Allow() Quit $$$OK
    Set o = {}
    Set o.profile = ##class(Shutter.Store.SiteProfile).Current()
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set o.version = $SELECT($ISOBJECT(row): row.Version, 1: 0)
    Set o.source = $SELECT($ISOBJECT(row): row.Source, 1: "defaults"), o.updatedAt = $SELECT($ISOBJECT(row): row.UpdatedAt, 1: ""), o.updatedBy = $SELECT($ISOBJECT(row): row.UpdatedBy, 1: "")
    Set o.catalogueEntries = ##class(Shutter.Catalogue.Entry).Count()
    Quit ..Json(o)
}

/// Replace the site profile: the questionnaire's answers, by an approver.
ClassMethod SiteProfilePut() As %Status
{
    If '..Allow("Shutter_Approve", 1) Quit $$$OK
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) || $$$ISERR(psc) Quit ..Fail("400 Bad Request", "bad_request", "The body must be the profile as a JSON object")
    // An optional expectedVersion guards against overwriting a change someone else made meanwhile (last write
    // would otherwise win): the stored version must still be the one the caller read.
    Set expected = ##class(Shutter.Util.Json).Str(body, "expectedVersion")
    If body.%IsDefined("expectedVersion") Do body.%Remove("expectedVersion")
    Set problem = ##class(Shutter.Store.SiteProfile).Validate(body)
    If problem '= "" Quit ..Fail("400 Bad Request", "bad_request", "The profile is not valid (CONTRACTS 6.4): " _ problem)
    // The store checks the version under its own lock, so the check and the write are one step.
    Set sc = ##class(Shutter.Store.SiteProfile).Store(body.%ToJSON(), "api", $USERNAME, expected, .current)
    If $$$ISERR(sc) && ($SYSTEM.Status.GetErrorText(sc) [ "stale_version") {
        Set extra = {} Set extra.currentVersion = +current
        Quit ..Fail("409 Conflict", "stale_version", "expectedVersion is not the stored profile's version", extra)
    }
    If $$$ISERR(sc) Quit ..Fail("500 Internal Server Error", "store_failed", $SYSTEM.Status.GetErrorText(sc))
    Quit ..SiteProfileGet()
}

/// Every version of the profile, newest first, with who stored it.
ClassMethod SiteProfileHistory() As %Status
{
    If '..Allow() Quit $$$OK
    Set limit = +$GET(%request.Data("limit", 1), 50)
    If limit < 1 Set limit = 50
    If limit > 500 Set limit = 500
    Quit ..Json(##class(Shutter.Store.SiteProfileVersion).History(limit))
}

// ---- the exact index (CONTRACTS 8) ----

/// Where the indexer's walk stands: rows, high-water mark, the newest header, the last pass.
ClassMethod IndexStatus() As %Status
{
    If '..Allow() Quit $$$OK
    Quit ..Json(##class(Shutter.Index.Indexer).Status())
}

/// The indexed messages for a visit number (?encounter=), a patient (?patient=) or an operation key (?key=), newest
/// event last; at most 500.
ClassMethod IndexMessages() As %Status
{
    If '..Allow() Quit $$$OK
    Set encounter = $GET(%request.Data("encounter", 1)), patient = $GET(%request.Data("patient", 1)), key = $GET(%request.Data("key", 1))
    If (encounter = "") && (patient = "") && (key = "") Quit ..Fail("400 Bad Request", "bad_request", "Give encounter, patient or key")
    Set where = "", args = 0
    If encounter '= "" Set where = where _ " AND VisitNumber = ?", args = args + 1, args(args) = encounter
    If patient '= "" Set where = where _ " AND PatientId = ?", args = args + 1, args(args) = patient
    If key '= "" Set where = where _ " AND OperationKey = ?", args = args + 1, args(args) = key
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 500 ID FROM Shutter_Index.Message WHERE 1=1" _ where _ " ORDER BY EventTime, ID", args...)
    Set items = []
    While rs.%Next() {
        Set r = ##class(Shutter.Index.Message).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(r)
        Do items.%Push(r.ToObject())
    }
    Set out = {}
    Set out.items = items, out.total = items.%Size()
    Quit ..Json(out)
}

// ---- incidents (CONTRACTS 7.5) ----

ClassMethod IncidentOr404(id As %String) As Shutter.Store.Incident
{
    Set inc = ##class(Shutter.Store.Incident).ByIncidentId(id)
    If '$ISOBJECT(inc) Do ..Fail("404 Not Found", "not_found", "No incident " _ id)
    Quit inc
}

ClassMethod IncidentSummary(inc As Shutter.Store.Incident) As %DynamicObject
{
    Set o = ..Project(inc)
    Set o.progress = inc.Progress()
    Quit o
}

/// The incidents, newest first: id, receiver, state, times, the plan's digest, and the chains counted by kind and state.
ClassMethod Incidents() As %Status
{
    If '..Allow() Quit $$$OK
    Set state = $GET(%request.Data("state", 1))
    Set limit = +$GET(%request.Data("limit", 1), 50)
    If limit < 1 Set limit = 50
    If limit > 500 Set limit = 500
    Set where = "", args = 0
    If state '= "" Set where = " AND State = ?", args = 1, args(1) = state
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Incident WHERE 1=1" _ where _ " ORDER BY ID DESC", args...)
    Set items = [], total = 0
    While rs.%Next() {
        Set total = total + 1
        Continue:(items.%Size() >= limit)
        Set inc = ##class(Shutter.Store.Incident).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(inc)
        Do items.%Push(..IncidentSummary(inc))
    }
    Set out = {}
    Set out.items = items, out.total = total
    Quit ..Json(out)
}

/// One incident: the chains with their items, the plan, the approvals, the Workflow tasks, progress and links.
ClassMethod IncidentGet(id As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set inc = ..IncidentOr404(id)
    If '$ISOBJECT(inc) Quit $$$OK
    Set o = ..IncidentSummary(inc)
    Set o.chains = inc.Chains()
    Set plan = ##class(Shutter.Util.Json).Parse(inc.PlanJSON, .psc)
    If $ISOBJECT(plan) { Set o.plan = plan } Else { Do o.%Set("plan", "", "null") }
    Set o.approvals = inc.Approvals()
    Set tasks = ##class(Shutter.Util.Workflow).TasksFor(inc.IncidentId)
    Set iter = o.chains.%GetIterator()
    While iter.%GetNext(.i, .ch) {
        Continue:(ch.%Get("policy") '= "per_chain")
        Set more = ##class(Shutter.Util.Workflow).TasksFor(inc.IncidentId _ "/" _ ch.%Get("seq"))
        Set it2 = more.%GetIterator()
        While it2.%GetNext(.j, .t) { Do tasks.%Push(t) }
    }
    Set o.tasks = tasks
    Set links = {}
    Set links.workflowTrace = ..PortalPath() _ "EnsPortal.VisualTrace.zen?SESSIONID=" _ inc.WorkflowSessionId
    Set o.links = links
    Quit ..Json(o)
}

ClassMethod IncidentEvents(id As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set inc = ..IncidentOr404(id)
    If '$ISOBJECT(inc) Quit $$$OK
    Quit ..Json(inc.Events())
}

ClassMethod IncidentApprovals(id As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set inc = ..IncidentOr404(id)
    If '$ISOBJECT(inc) Quit $$$OK
    Quit ..Json(inc.Approvals())
}

/// Approve or reject the incident's policy chains under one approval: the body names the plan digest it binds.
ClassMethod IncidentApprove(id As %String) As %Status
{
    Quit ..IncidentDecide(id, "")
}

/// Approve or reject one chain released under its own approval (policy per_chain).
ClassMethod IncidentChainApprove(id As %String, seq As %String) As %Status
{
    Quit ..IncidentDecide(id, seq)
}

ClassMethod IncidentDecide(id As %String, seq As %String) As %Status
{
    If '..Allow("Shutter_Approve", 1) Quit $$$OK
    Set inc = ..IncidentOr404(id)
    If '$ISOBJECT(inc) Quit $$$OK
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Shutter.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) Set body = {}
    Set decision = $ZCONVERT(##class(Shutter.Util.Json).Str(body, "decision", ##class(Shutter.Util.Json).Str(body, "action")), "L")
    If '$LISTFIND($LISTBUILD("approve", "reject"), decision) Quit ..Fail("400 Bad Request", "bad_request", "decision must be approve or reject")
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    // The incident keeps releasing its automatic and board chains while a task is open, so its state is not the test:
    // a chain must be awaiting this approval.
    If inc.State = "closed" Quit ..Fail("409 Conflict", "wrong_state", "The incident is closed")
    If seq = "" {
        Set waiting = 0, iid = inc.%Id()
        &sql(SELECT COUNT(*) INTO :waiting FROM Shutter_Store.Chain WHERE Incident = :iid AND State = 'awaiting_approval' AND Policy = 'approval')
        If +waiting = 0 Quit ..Fail("409 Conflict", "wrong_state", "No chain of " _ id _ " awaits the incident's approval (the incident is " _ inc.State _ ")")
    }
    If seq '= "" {
        Set chain = inc.ChainAt(seq)
        If '$ISOBJECT(chain) Quit ..Fail("404 Not Found", "not_found", "No chain " _ seq _ " in " _ id)
        If (chain.State '= "awaiting_approval") || (chain.Policy '= "per_chain") Quit ..Fail("409 Conflict", "wrong_state", "Chain " _ seq _ " is " _ chain.State _ " under policy " _ chain.Policy _ ", not awaiting its own approval")
    }
    Set digest = ##class(Shutter.Util.Json).Str(body, "planDigest")
    If digest '= inc.PlanDigest {
        Set extra = {} Set extra.currentDigest = inc.PlanDigest
        Quit ..Fail("409 Conflict", "plan_changed", "planDigest is not the incident plan's digest", extra)
    }
    Set comment = ##class(Shutter.Util.Json).Str(body, "comment")
    // The decider is the signed-in user, never a name from the body; the task takes the digest the body named (CONTRACTS 5).
    Set result = ##class(Shutter.Util.Workflow).Decide(id _ $SELECT(seq '= "": "/" _ seq, 1: ""), $SELECT(decision = "reject": "Reject", 1: "Approve"), digest, comment)
    Set out = ##class(Shutter.Util.Json).Parse(result, .psc)
    If '$ISOBJECT(out) Set out = {"result": (result)}
    If out.%GetTypeOf("error") '= "unassigned" {
        If $LISTFIND($LISTBUILD("not_in_role", "forbidden"), ##class(Shutter.Util.Json).Str(out, "code")) Quit ..Fail("403 Forbidden", "forbidden", out.error)
        Quit ..Fail("409 Conflict", "wrong_state", out.error)
    }
    Set reply = {}
    Set reply.taskId = out."task_id", reply.decision = decision, reply.incidentId = id, reply.approver = out.user
    If seq '= "" Set reply.chainSeq = +seq
    Set text = reply.%ToJSON()
    Do ..Remember(bodyText, "202 Accepted", text)
    Set %response.Status = "202 Accepted"
    Write text
    Quit $$$OK
}

ClassMethod Settings() As %Status
{
    If '..Allow() Quit $$$OK
    Set o = {}
    Set o.mode = $GET(^Shutter.Config("mode")), o.scenario = $GET(^Shutter.Config("scenario")), o.resetAt = $GET(^Shutter.Config("resetAt"))
    Do o.%Set("demo", ''$GET(^Shutter.Config("demo")), "boolean")
    // The API mimic's switch (CONTRACTS 4), read once for every item: while it is set, an item that resolves to live is
    // answered by the mimic, with no model, and the reply says so.
    Set mock = ##class(Shutter.Setup).MockConfig()
    Set items = []
    Set prod = ##class(Ens.Config.Production).%OpenId(##class(Shutter.Setup).ProductionName())
    If $ISOBJECT(prod) {
        For i = 1:1:prod.Items.Count() {
            Set item = prod.Items.GetAt(i)
            If item.ClassName '= "Shutter.Bridge.Operation.Agent" Continue
            Set a = {}
            Set a.name = item.Name
            Do a.%Set("enabled", ''item.Enabled, "boolean")
            For j = 1:1:item.Settings.Count() {
                Set st = item.Settings.GetAt(j)
                Set name = st.Name
                Do a.%Set($ZCONVERT($EXTRACT(name, 1), "L") _ $EXTRACT(name, 2, *), st.Value)
            }
            Set a.effectiveMode = ##class(Shutter.Bridge.Operation.Agent).ResolveMode(##class(Shutter.Util.Json).Str(a, "mode", "auto"), mock)
            // Who answers a run that goes to a model: the mimic while its switch is set, else the item's provider
            // configuration (a name of fewer than three parts is under AI.LLM, as the runner reads it), else the
            // instance's. A replaying item has none.
            If (mock '= "") && (a.effectiveMode = "live") {
                Set a.answeredBy = "the API mimic"
            } ElseIf (a.effectiveMode = "live") || (a.effectiveMode = "record") {
                Set by = ##class(Shutter.Util.Json).Str(a, "providerConfig")
                If (by '= "") && ($LENGTH(by, ".") < 3) Set by = "AI.LLM." _ by
                If by = "" Set by = $GET(^Shutter.Config("aihub", "provider"))
                If by '= "" Set a.answeredBy = by
            }
            Do items.%Push(a)
        }
    }
    Set o.agentItems = items
    Set o.agentMode = $GET(^Shutter.Config("aihub", "mode"), "auto")
    Do o.%Set("mock", mock '= "", "boolean")
    Set o.mockConfig = mock
    Set o.mockModel = $SELECT(mock '= "": $GET(^Shutter.Config("aihub", "mockModel")), 1: "")
    Do o.%Set("providerConfigured", ''##class(Shutter.Setup).ProviderConfigured(), "boolean")
    Set o.prices = ..Rows("Shutter.Store.ModelPrice", "SELECT ID FROM Shutter_Store.ModelPrice ORDER BY Model")
    Do o.%Set("aiHubPresent", ''##class(%Dictionary.CompiledClass).%ExistsId("%AI.Agent"), "boolean")
    Do o.%Set("liveRunnerPresent", ''##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Bridge.Runner.AIHub"), "boolean")
    Quit ..Json(o)
}

ClassMethod Costs() As %Status
{
    If '..Allow() Quit $$$OK
    Set since = $GET(%request.Data("since", 1)), until = $GET(%request.Data("until", 1))
    Set where = "", args = 0
    If since '= "" Set where = where _ " AND StartedAt >= ?", args = args + 1, args(args) = since
    If until '= "" Set where = where _ " AND StartedAt <= ?", args = args + 1, args(args) = until
    Set o = {}
    // Live and record runs spend money; a replay copies a recording's tokens and spends nothing, so the
    // rows carry the mode and replays sit apart, with their recorded tokens and a cost of 0.
    Set byModel = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT %EXACT(Model) AS Model, %EXACT(Mode) AS Mode, COUNT(*) AS Runs, SUM(PromptTokens) AS P, SUM(CompletionTokens) AS C, SUM(CacheReadTokens) AS R, SUM(CostUSD) AS Cost FROM Shutter_Store.AgentRun WHERE 1=1" _ where _ " GROUP BY %EXACT(Model), %EXACT(Mode) ORDER BY %EXACT(Model), %EXACT(Mode)", args...)
    While rs.%Next() { Set r = {} Set r.model = rs.%Get("Model"), r.mode = rs.%Get("Mode"), r.runs = +rs.%Get("Runs"), r.promptTokens = +rs.%Get("P"), r.completionTokens = +rs.%Get("C"), r.cacheReadTokens = +rs.%Get("R"), r.costUsd = $SELECT(rs.%Get("Mode") = "replay": 0, 1: +rs.%Get("Cost")) Do byModel.%Push(r) }
    // A run the API mimic answered (model mock, tests/mock) is counted apart: no model was called, and it cost 0.
    Set totals = {}
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT SUM(CASE WHEN Mode = 'replay' THEN 0 ELSE CostUSD END) AS Spent, SUM(CASE WHEN Mode = 'replay' THEN 1 ELSE 0 END) AS Replays, SUM(CASE WHEN Mode <> 'replay' AND Model = 'mock' THEN 1 ELSE 0 END) AS Mock, SUM(CASE WHEN Mode = 'replay' OR Model = 'mock' THEN 0 ELSE 1 END) AS Live FROM Shutter_Store.AgentRun WHERE 1=1" _ where, args...)
    If rs.%Next() Set totals.spentUsd = +rs.%Get("Spent"), totals.liveRuns = +rs.%Get("Live"), totals.replayedRuns = +rs.%Get("Replays"), totals.mockRuns = +rs.%Get("Mock")
    Set o.totals = totals
    Set byDay = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT SUBSTRING(StartedAt,1,10) AS Day, COUNT(*) AS Runs, SUM(CASE WHEN Mode = 'replay' THEN 1 ELSE 0 END) AS Replays, SUM(CASE WHEN Mode = 'replay' THEN 0 ELSE CostUSD END) AS Cost FROM Shutter_Store.AgentRun WHERE 1=1" _ where _ " GROUP BY SUBSTRING(StartedAt,1,10) ORDER BY Day", args...)
    While rs.%Next() { Set r = {} Set r.day = rs.%Get("Day"), r.runs = +rs.%Get("Runs"), r.replayedRuns = +rs.%Get("Replays"), r.costUsd = +rs.%Get("Cost") Do byDay.%Push(r) }
    Set byCase = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT %EXACT(c.CaseId) AS CaseId, COUNT(*) AS Runs, SUM(CASE WHEN a.Mode = 'replay' THEN 1 ELSE 0 END) AS Replays, SUM(CASE WHEN a.Mode = 'replay' THEN 0 ELSE a.CostUSD END) AS Cost FROM Shutter_Store.AgentRun a JOIN Shutter_Store.""Case"" c ON a.""Case"" = c.ID WHERE 1=1" _ where _ " GROUP BY %EXACT(c.CaseId) ORDER BY %EXACT(c.CaseId) DESC", args...)
    While rs.%Next() { Set r = {} Set r.caseId = rs.%Get("CaseId"), r.runs = +rs.%Get("Runs"), r.replayedRuns = +rs.%Get("Replays"), r.costUsd = +rs.%Get("Cost") Do byCase.%Push(r) }
    Set o.byModel = byModel, o.byDay = byDay, o.byCase = byCase
    Quit ..Json(o)
}

}
