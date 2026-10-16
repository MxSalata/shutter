/// The REST API for the web application (docs/CONTRACTS.md, section 5). Every route checks the
/// caller's resources on the server; changes need the CSRF header; the two idempotent POSTs take
/// an Idempotency-Key. Everything the app shows comes through here.
Class Interlock.API.Dispatch Extends %CSP.REST
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
  <Route Url="/library" Method="GET" Call="Library"/>
  <Route Url="/library/:code" Method="PATCH" Call="LibraryPatch"/>
  <Route Url="/settings" Method="GET" Call="Settings"/>
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
ClassMethod Allow(resource As %String = "Interlock_Operate", change As %Boolean = 0) As %Boolean
{
    If ..User() = "" Do ..Fail("401 Unauthorized", "unauthenticated", "Sign in first") Quit 0
    If (resource '= "") && '$SYSTEM.Security.Check(resource, "USE") Do ..Fail("403 Forbidden", "forbidden", "This needs " _ resource) Quit 0
    If change && (%request.GetCgiEnv("HTTP_X_REQUESTED_WITH") '= "Interlock") Do ..Fail("403 Forbidden", "csrf", "Changes need the header X-Requested-With: Interlock") Quit 0
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
            Set o = ##class(%DynamicObject).%FromJSON(##class(Interlock.Util.Json).NullEmptyValues(json))
        } Catch ex {
            Set o = {}
            Set o.error = "projection failed: " _ ex.DisplayString()
        }
    }
    Set o.id = obj.%Id()
    Quit o
}

/// The case for a public id, or "" after writing a 404.
ClassMethod CaseOr404(caseId As %String) As Interlock.Store.Case
{
    Set case = ##class(Interlock.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Do ..Fail("404 Not Found", "not_found", "No case " _ caseId)
    Quit case
}

/// Serve an idempotent change: replay a stored reply, or run the handler and store its reply.
ClassMethod Idempotent(bodyText As %String, Output replayed As %Boolean) As %Integer
{
    Set replayed = 0
    Set key = %request.GetCgiEnv("HTTP_IDEMPOTENCY_KEY")
    If key = "" Quit 0
    Set digest = ##class(Interlock.Util.Digest).SHA256Hex(bodyText)
    Set found = ##class(Interlock.Store.Idempotency).Lookup(..User() _ "|" _ key, digest, .status, .response)
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
    Do ##class(Interlock.Store.Idempotency).Store(..User() _ "|" _ key, ##class(Interlock.Util.Digest).SHA256Hex(bodyText), status, response)
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
    Quit "/csp/" _ $ZCONVERT($NAMESPACE, "L") _ "/"
}

// ---- session ----

ClassMethod Login() As %Status
{
    Set body = ..Body()
    Set user = ##class(Interlock.Util.Json).Str(body, "username"), pwd = ##class(Interlock.Util.Json).Str(body, "password")
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
    Do o.%Set("operator", $SYSTEM.Security.Check("Interlock_Operate", "USE"), "boolean")
    Do o.%Set("approver", $SYSTEM.Security.Check("Interlock_Approve", "USE"), "boolean")
    Quit ..Json(o)
}

ClassMethod Health() As %Status
{
    Quit ..Json(##class(%DynamicObject).%FromJSON(##class(Interlock.Setup).Doctor()))
}

// ---- scenarios ----

ClassMethod Scenarios() As %Status
{
    If '..Allow() Quit $$$OK
    If '##class(%Dictionary.CompiledClass).%ExistsId("Interlock.Scenarios.Runner") Quit ..Json([])
    Set list = ##class(Interlock.Util.Json).Parse($CLASSMETHOD("Interlock.Scenarios.Runner", "List"), .sc)
    If '$ISOBJECT(list) Set list = []
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .sc) {
        Set id = ##class(Interlock.Util.Json).Str(sc, "id")
        Set cid = ""
        &sql(SELECT TOP 1 ID INTO :cid FROM Interlock_Store."Case" WHERE Scenario = :id ORDER BY ID DESC)
        If (SQLCODE = 0) && (cid '= "") {
            Set c = ##class(Interlock.Store.Case).%OpenId(cid)
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
    If ##class(%Dictionary.CompiledMethod).%ExistsId("Interlock.Scenarios.Runner||Status") Set run = ##class(Interlock.Util.Json).Parse($CLASSMETHOD("Interlock.Scenarios.Runner", "Status"), .ssc)
    If $ISOBJECT(run) { Set out.run = run } Else { Do out.%Set("run", "", "null") }
    Quit ..Json(out)
}

/// True when the running production has the Scenario Player item enabled.
ClassMethod PlayerEnabled() As %Boolean
{
    Set n = 0
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N FROM Ens_Config.Item WHERE Production = ? AND Name = ? AND Enabled = 1", "Interlock.Production", "Scenario Player")
        If rs.%Next() Set n = +rs.%Get("N")
    } Catch {
        Set n = 0
    }
    If n = 0 Quit 0
    Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
    Quit (state = 1) && (name = "Interlock.Production")
}

ClassMethod ScenarioRun(id As %String) As %Status
{
    If '..Allow("Interlock_Operate", 1) Quit $$$OK
    If '##class(%Dictionary.CompiledClass).%ExistsId("Interlock.Scenarios.Runner") Quit ..Fail("503 Service Unavailable", "no_runner", "The scenario runner is not installed")
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Interlock.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) Set body = {}
    Set mode = ##class(Interlock.Util.Json).Str(body, "mode", "board")
    If '$LISTFIND($LISTBUILD("board", "single", "rules"), mode) Quit ..Fail("400 Bad Request", "bad_request", "mode must be board, single or rules")
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    If ..PlayerEnabled() {
        // The production's own player plays the steps (one run at a time); the run record says queued
        // until it starts, then running, done or failed (GET /scenarios).
        Set status = ##class(Interlock.Scenarios.Runner).Status()
        Set run = ##class(Interlock.Util.Json).Parse(status, .psc)
        If $ISOBJECT(run) && (run.state = "queued") Quit ..Fail("409 Conflict", "wrong_state", "a run of " _ run.scenario _ " is queued", run)
        If ##class(Interlock.Scenarios.Runner).Running() Quit ..Fail("409 Conflict", "wrong_state", "a run of " _ run.scenario _ " is still playing", run)
        Set out = {"scenario": (id), "mode": (mode), "state": "queued", "files": [], "timeouts": []}
        Do out.%Set("running", 1, "boolean")
        Set out.queuedAt = ##class(Interlock.Util.Time).NowUTC()
        Set ^Interlock.Scenarios("run") = out.%ToJSON()
        Kill ^Interlock.Scenarios("run", "job")
        Set msg = ##class(Interlock.Msg.ScenarioRun).%New()
        Set msg.Scenario = id, msg.Mode = mode, msg.RequestedBy = $USERNAME
        Set sc = ##class(Ens.Director).CreateBusinessService("Interlock API", .service)
        If $$$ISERR(sc) || '$ISOBJECT(service) Quit ..Fail("503 Service Unavailable", "no_service", "The API service is not running: " _ $SYSTEM.Status.GetErrorText(sc))
        Set service.Target = "Scenario Player", service.Async = 1
        Set sc = service.ProcessInput(msg)
        If $$$ISERR(sc) {
            Kill ^Interlock.Scenarios("run")
            Quit ..Fail("503 Service Unavailable", "not_queued", "The run could not be queued: " _ $SYSTEM.Status.GetErrorText(sc))
        }
    } Else {
        // Without the player: Start plays the steps in a background job and returns at once; Run is the synchronous fallback.
        Set method = $SELECT(##class(%Dictionary.CompiledMethod).%ExistsId("Interlock.Scenarios.Runner||Start"): "Start", 1: "Run")
        Set result = $CLASSMETHOD("Interlock.Scenarios.Runner", method, id, mode)
        Set out = ##class(Interlock.Util.Json).Parse(result, .sc)
        If '$ISOBJECT(out) Set out = {"result": (result)}
        If out.%GetTypeOf("error") '= "unassigned" Quit ..Fail("409 Conflict", "wrong_state", ##class(Interlock.Util.Json).Str(out, "detail", out.error), out)
    }
    Set text = out.%ToJSON()
    Do ..Remember(bodyText, "202 Accepted", text)
    Set %response.Status = "202 Accepted"
    Write text
    Quit $$$OK
}

ClassMethod ScenarioReset() As %Status
{
    If '..Allow("Interlock_Operate", 1) Quit $$$OK
    If '##class(%Dictionary.CompiledClass).%ExistsId("Interlock.Scenarios.Runner") Quit ..Fail("503 Service Unavailable", "no_runner", "The scenario runner is not installed")
    Set result = $CLASSMETHOD("Interlock.Scenarios.Runner", "Reset")
    Set out = ##class(Interlock.Util.Json).Parse(result, .sc)
    If '$ISOBJECT(out) Set out = {"result": (result)}
    Set out.resetAt = $GET(^Interlock.Config("resetAt"))
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
    Set where = "", args = 0
    If state '= "" Set where = where _ " AND State = ?", args = args + 1, args(args) = state
    If scenario '= "" Set where = where _ " AND Scenario = ?", args = args + 1, args(args) = scenario
    Set total = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N FROM Interlock_Store.""Case"" WHERE 1=1" _ where, args...)
    If rs.%Next() Set total = rs.%Get("N")
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.""Case"" WHERE 1=1" _ where _ " ORDER BY ID DESC", args...)
    Set items = [], n = 0
    While rs.%Next() {
        Set n = n + 1
        If n <= offset Continue
        If items.%Size() >= limit Quit
        Set c = ##class(Interlock.Store.Case).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Do items.%Push(..Project(c))
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
    Set id = case.%Id()
    Set counts = {}
    &sql(SELECT COUNT(*) INTO :n FROM Interlock_Store.CaseEvent WHERE "Case" = :id)
    Set counts.events = +n
    &sql(SELECT COUNT(*) INTO :n FROM Interlock_Store.AgentRun WHERE "Case" = :id)
    Set counts.runs = +n
    &sql(SELECT COUNT(*) INTO :n FROM Interlock_Store.Finding WHERE "Case" = :id)
    Set counts.findings = +n
    &sql(SELECT COUNT(*) INTO :n FROM Interlock_Store.Plan WHERE "Case" = :id)
    Set counts.plans = +n
    &sql(SELECT COUNT(*) INTO :n FROM Interlock_Store.Approval WHERE "Case" = :id)
    Set counts.approvals = +n
    &sql(SELECT COUNT(*) INTO :n FROM Interlock_Store.ExecutionAttempt WHERE "Case" = :id)
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
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.AgentRun WHERE ""Case"" = ? ORDER BY ID", case.%Id())
    While rs.%Next() {
        Set run = ##class(Interlock.Store.AgentRun).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(run)
        Set o = ..Project(run)
        If run.ResultJSON '= "" Set o.result = ##class(Interlock.Util.Json).Parse(run.ResultJSON, .psc)
        Set m = ##class(Interlock.Store.BoardMember).ByCode(run.MemberCode)
        If $ISOBJECT(m) { Set mm = {} Set mm.code = m.Code, mm.name = m.Name, mm.perspective = m.Perspective Set o.member = mm } Else { Do o.%Set("member", "", "null") }
        Set fid = "", rid = run.%Id()
        &sql(SELECT TOP 1 ID INTO :fid FROM Interlock_Store.Finding WHERE Run = :rid)
        If (SQLCODE = 0) && (fid '= "") { Set o.finding = ..Project(##class(Interlock.Store.Finding).%OpenId(fid)) } Else { Do o.%Set("finding", "", "null") }
        Set o.toolCalls = ##class(Interlock.Bridge.ToolCall).ForRun(run.EnsMessageId)
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
        If p.%GetTypeOf(f) = "string" Do p.%Set(f, ##class(Interlock.Util.Json).Parse(p.%Get(f), .psc))
    }
    Set o.plan = p
    Set o.gateDecisions = ..Rows("Interlock.Store.GateDecision", "SELECT ID FROM Interlock_Store.GateDecision WHERE Plan = ? ORDER BY ID", plan.%Id())
    Set iter = o.gateDecisions.%GetIterator()
    While iter.%GetNext(.i, .d) { If d.%GetTypeOf("checks") = "string" Set d.checks = ##class(Interlock.Util.Json).Parse(d.checks, .psc) }
    Set rid = "", planId = plan.%Id()
    &sql(SELECT TOP 1 ID INTO :rid FROM Interlock_Store.Rehearsal WHERE Plan = :planId ORDER BY ID DESC)
    If (SQLCODE = 0) && (rid '= "") {
        Set r = ..Project(##class(Interlock.Store.Rehearsal).%OpenId(rid))
        If r.%GetTypeOf("response") = "string" Set r.response = ##class(Interlock.Util.Json).Parse(r.response, .psc)
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
        Set o.approvals = ..Rows("Interlock.Store.Approval", "SELECT ID FROM Interlock_Store.Approval WHERE ""Case"" = ? ORDER BY ID", case.%Id())
    } Catch ex {
        Set o.approvals = [], o.approvalsError = ex.DisplayString()
    }
    Try {
        Set o.tasks = ##class(Interlock.Util.Workflow).TasksFor(caseId)
    } Catch ex {
        Set o.tasks = [], o.tasksError = ex.DisplayString()
    }
    Quit ..Json(o)
}

ClassMethod CaseApprove(caseId As %String) As %Status
{
    If '..Allow("Interlock_Approve", 1) Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    Set bodyText = $SELECT($ISOBJECT(%request.Content): %request.Content.Read($$$MaxStringLength), 1: $GET(%request.Content))
    Set body = ##class(Interlock.Util.Json).Parse(bodyText, .psc)
    If '$ISOBJECT(body) Set body = {}
    Set decision = $ZCONVERT(##class(Interlock.Util.Json).Str(body, "decision"), "L")
    If '$LISTFIND($LISTBUILD("approve", "reject"), decision) Quit ..Fail("400 Bad Request", "bad_request", "decision must be approve or reject")
    Set r = ..Idempotent(bodyText, .replayed)
    If replayed Quit $$$OK
    If case.State '= "awaiting_approval" Quit ..Fail("409 Conflict", "wrong_state", "The case is " _ case.State _ ", not awaiting approval")
    Set plan = case.CurrentPlan
    Set digest = ##class(Interlock.Util.Json).Str(body, "planDigest")
    If '$ISOBJECT(plan) || (digest '= plan.Digest) {
        Set extra = {} Set extra.currentDigest = $SELECT($ISOBJECT(plan): plan.Digest, 1: "")
        Quit ..Fail("409 Conflict", "stale_version", "planDigest is not the current plan's digest", extra)
    }
    Set expected = ##class(Interlock.Util.Json).Str(body, "expectedVersion")
    If (expected = "") || (+expected '= case.Version) {
        Set extra = {} Set extra.currentVersion = case.Version
        Quit ..Fail("409 Conflict", "stale_version", "expectedVersion is not the case's version", extra)
    }
    Set comment = ##class(Interlock.Util.Json).Str(body, "comment")
    Set result = ##class(Interlock.Util.Workflow).Decide(caseId, $SELECT(decision = "reject": "Reject", 1: "Approve"), ..User(), comment)
    Set out = ##class(Interlock.Util.Json).Parse(result, .psc)
    If '$ISOBJECT(out) Set out = {"result": (result)}
    If out.%GetTypeOf("error") '= "unassigned" Quit ..Fail("409 Conflict", "wrong_state", out.error)
    Set reply = {}
    Set reply.taskId = out."task_id", reply.decision = decision, reply.caseId = caseId
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
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.ExecutionAttempt WHERE ""Case"" = ? ORDER BY ID", case.%Id())
    While rs.%Next() {
        Set a = ##class(Interlock.Store.ExecutionAttempt).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(a)
        Set pair = {}
        Set ap = ..Project(a)
        For f = "receipt", "response" { If ap.%GetTypeOf(f) = "string" Do ap.%Set(f, ##class(Interlock.Util.Json).Parse(ap.%Get(f), .psc)) }
        Set pair.attempt = ap
        Set vid = "", aid = a.%Id()
        &sql(SELECT TOP 1 ID INTO :vid FROM Interlock_Store.Verification WHERE Attempt = :aid ORDER BY ID DESC)
        If (SQLCODE = 0) && (vid '= "") {
            Set v = ..Project(##class(Interlock.Store.Verification).%OpenId(vid))
            If v.%GetTypeOf("detail") = "string" Set v.detail = ##class(Interlock.Util.Json).Parse(v.detail, .psc)
            Set pair.verification = v
        } Else { Do pair.%Set("verification", "", "null") }
        Do out.%Push(pair)
    }
    // Verifications without an attempt (non-write dispositions).
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.Verification WHERE ""Case"" = ? AND Attempt IS NULL ORDER BY ID", case.%Id())
    While rs.%Next() {
        Set v = ..Project(##class(Interlock.Store.Verification).%OpenId(rs.%Get("ID")))
        If v.%GetTypeOf("detail") = "string" Set v.detail = ##class(Interlock.Util.Json).Parse(v.detail, .psc)
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
    &sql(SELECT TOP 1 ID INTO :vid FROM Interlock_Store.Verification WHERE "Case" = :id ORDER BY ID DESC)
    Set verified = [], unverified = []
    If (SQLCODE = 0) && (vid '= "") {
        Set v = ##class(Interlock.Store.Verification).%OpenId(vid)
        Set vp = ..Project(v)
        Set detail = ##class(Interlock.Util.Json).Parse(v.DetailJSON, .psc)
        If $ISOBJECT(detail) Set vp.detail = detail
        Set o.verification = vp
        If (v.Outcome = "verified") && $ISOBJECT(detail) {
            Set enc = detail.%Get("encounter")
            If $ISOBJECT(enc) Do verified.%Push("The ward system holds encounter " _ case.EncounterId _ " as " _ ##class(Interlock.Util.Json).Str(enc, "state") _ $SELECT(##class(Interlock.Util.Json).Str(enc, "ward") '= "": " in " _ enc.ward, 1: "") _ " at version " _ ##class(Interlock.Util.Json).Str(enc, "version"))
            If detail.%GetTypeOf("receipt") = "object" && (##class(Interlock.Util.Json).Str(detail, "receipt_http_status") = 200) Do verified.%Push("A receipt exists for the operation key")
            If ##class(Interlock.Util.Json).Str(detail, "history_note") '= "" Do unverified.%Push(detail."history_note")
        }
    } Else { Do o.%Set("verification", "", "null") }
    Do unverified.%Push("Consumers downstream of the ward system are outside the production's view and are not verified")
    Set o.verifiedEffects = verified, o.unverified = unverified
    Set actors = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT DISTINCT %EXACT(Actor) AS Actor FROM Interlock_Store.CaseEvent WHERE ""Case"" = ? ORDER BY Actor", id)
    While rs.%Next() { Do actors.%Push(rs.%Get("Actor")) }
    Set o.actors = actors
    Set pv = ""
    &sql(SELECT TOP 1 PolicyVersion INTO :pv FROM Interlock_Store.GateDecision WHERE "Case" = :id ORDER BY ID DESC)
    Set o.policyVersion = $GET(pv)
    Quit ..Json(o)
}

ClassMethod CasePreview(caseId As %String) As %Status
{
    If '..Allow("Interlock_Operate", 1) Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    If case.IsClosed() Quit ..Fail("409 Conflict", "wrong_state", "The case is closed")
    Set op = {}
    Set op."operation_key" = case.OperationKey, op."encounter_id" = case.EncounterId
    Set op."patient_id" = case.PatientId, op."patient_id_authority" = case.PatientIdAuthority
    Set op."event" = case.Event
    If case.Ward '= "" { Set op."ward" = case.Ward } Else { Do op.%Set("ward", "", "null") }
    Set op."event_time" = case.EventTime, op."source_system" = case.SourceSystem, op."source_message_id" = case.SourceMessageId
    Set w = ##class(Interlock.Msg.WardOperation).FromOperation(op)
    Set w.Purpose = "rehearsal", w.DryRun = 1, w.CaseId = case.CaseId
    Set sc = ##class(Ens.Director).CreateBusinessService("Interlock API", .svc)
    If $$$ISERR(sc) || '$ISOBJECT($GET(svc)) Quit ..Fail("503 Service Unavailable", "no_production", "The production's API service is not running: " _ $SYSTEM.Status.GetErrorText(sc))
    Set svc.Target = "Ward Out"
    Set sc = svc.ProcessInput(w, .result)
    If $$$ISERR(sc) || '$ISOBJECT($GET(result)) Quit ..Fail("502 Bad Gateway", "ward_error", $SYSTEM.Status.GetErrorText(sc))
    Set resp = result.ResponseObject()
    Set o = {}
    Do o.%Set("wouldApply", result.Outcome = "would_apply", "boolean")
    Set o.outcome = result.Outcome, o.reason = result.ReasonCode
    Set o.encounterAfter = resp.%Get("encounter_after")
    Set o.note = "What a blind resend with no expected version would do at the ward system now; the dry run was rolled back and nothing was written"
    Do case.Note("note", "Blind-resend preview requested by " _ ..User() _ ": " _ result.Outcome, ..User())
    Quit ..Json(o)
}

ClassMethod CaseBlockedReason(caseId As %String) As %Status
{
    If '..Allow() Quit $$$OK
    Set case = ..CaseOr404(caseId)
    If '$ISOBJECT(case) Quit $$$OK
    If '$LISTFIND($LISTBUILD("blocked", "escalated"), case.State) Quit ..Fail("404 Not Found", "not_blocked", "The case is " _ case.State)
    Set id = case.%Id(), did = ""
    &sql(SELECT TOP 1 ID INTO :did FROM Interlock_Store.GateDecision WHERE "Case" = :id AND Outcome <> 'pass' ORDER BY ID DESC)
    Set failing = [], code = ""
    If (SQLCODE = 0) && (did '= "") {
        Set d = ##class(Interlock.Store.GateDecision).%OpenId(did)
        Set checks = ##class(Interlock.Util.Json).Parse(d.ChecksJSON, .psc)
        If $ISOBJECT(checks) {
            Set iter = checks.%GetIterator()
            While iter.%GetNext(.i, .c) { If c.result '= "pass" { Do failing.%Push(c) If code = "" Set code = c."reason_code" } }
        }
    }
    If code = "" {
        Set text = ""
        &sql(SELECT TOP 1 Text INTO :text FROM Interlock_Store.CaseEvent WHERE "Case" = :id AND ToState IN ('blocked','escalated') ORDER BY Seq DESC)
        Set code = $SELECT(text [ "Rejected by": "REJECTED_BY_APPROVER", text [ "rehearsal": "REHEARSAL_WOULD_NOT_APPLY", text [ "refused": "DISPATCH_REFUSED", text [ "person": "ESCALATED", case.State = "escalated": "ESCALATED", 1: "BLOCKED")
    }
    Set o = {}
    Set o.code = code
    Set r = ##class(Interlock.Store.BlockReason).ByCode(code)
    If $ISOBJECT(r) { Set o.catalogue = ..Project(r) } Else { Do o.%Set("catalogue", "", "null") }
    Set o.failingChecks = failing
    Set o.state = case.State, o.headline = case.Headline
    Quit ..Json(o)
}

// ---- library, settings, costs ----

ClassMethod Library() As %Status
{
    If '..Allow() Quit $$$OK
    Quit ..Json(..Rows("Interlock.Store.BoardMember", "SELECT ID FROM Interlock_Store.BoardMember ORDER BY Sort, Code"))
}

ClassMethod LibraryPatch(code As %String) As %Status
{
    If '..Allow("Interlock_Operate", 1) Quit $$$OK
    Set m = ##class(Interlock.Store.BoardMember).ByCode(code)
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

ClassMethod Settings() As %Status
{
    If '..Allow() Quit $$$OK
    Set o = {}
    Set o.mode = $GET(^Interlock.Config("mode")), o.scenario = $GET(^Interlock.Config("scenario")), o.resetAt = $GET(^Interlock.Config("resetAt"))
    Do o.%Set("demo", ''$GET(^Interlock.Config("demo")), "boolean")
    Set items = []
    Set prod = ##class(Ens.Config.Production).%OpenId("Interlock.Production")
    If $ISOBJECT(prod) {
        For i = 1:1:prod.Items.Count() {
            Set item = prod.Items.GetAt(i)
            If item.ClassName '= "Interlock.Bridge.Operation.Agent" Continue
            Set a = {}
            Set a.name = item.Name
            Do a.%Set("enabled", ''item.Enabled, "boolean")
            For j = 1:1:item.Settings.Count() {
                Set st = item.Settings.GetAt(j)
                Set name = st.Name
                Do a.%Set($ZCONVERT($EXTRACT(name, 1), "L") _ $EXTRACT(name, 2, *), st.Value)
            }
            Set a.effectiveMode = ##class(Interlock.Bridge.Operation.Agent).ResolveMode(##class(Interlock.Util.Json).Str(a, "mode", "auto"))
            Do items.%Push(a)
        }
    }
    Set o.agentItems = items
    Set o.agentMode = $GET(^Interlock.Config("aihub", "mode"), "auto")
    Do o.%Set("providerConfigured", ''##class(Interlock.Setup).ProviderConfigured(), "boolean")
    Set o.prices = ..Rows("Interlock.Store.ModelPrice", "SELECT ID FROM Interlock_Store.ModelPrice ORDER BY Model")
    Do o.%Set("aiHubPresent", ''##class(%Dictionary.CompiledClass).%ExistsId("%AI.Agent"), "boolean")
    Do o.%Set("liveRunnerPresent", ''##class(%Dictionary.CompiledClass).%ExistsId("Interlock.Bridge.Runner.AIHub"), "boolean")
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
    Set byModel = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT %EXACT(Model) AS Model, COUNT(*) AS Runs, SUM(PromptTokens) AS P, SUM(CompletionTokens) AS C, SUM(CacheReadTokens) AS R, SUM(CostUSD) AS Cost FROM Interlock_Store.AgentRun WHERE 1=1" _ where _ " GROUP BY %EXACT(Model) ORDER BY %EXACT(Model)", args...)
    While rs.%Next() { Set r = {} Set r.model = rs.%Get("Model"), r.runs = +rs.%Get("Runs"), r.promptTokens = +rs.%Get("P"), r.completionTokens = +rs.%Get("C"), r.cacheReadTokens = +rs.%Get("R"), r.costUsd = +rs.%Get("Cost") Do byModel.%Push(r) }
    Set byDay = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT SUBSTRING(StartedAt,1,10) AS Day, COUNT(*) AS Runs, SUM(CostUSD) AS Cost FROM Interlock_Store.AgentRun WHERE 1=1" _ where _ " GROUP BY SUBSTRING(StartedAt,1,10) ORDER BY Day", args...)
    While rs.%Next() { Set r = {} Set r.day = rs.%Get("Day"), r.runs = +rs.%Get("Runs"), r.costUsd = +rs.%Get("Cost") Do byDay.%Push(r) }
    Set byCase = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT %EXACT(c.CaseId) AS CaseId, COUNT(*) AS Runs, SUM(a.CostUSD) AS Cost FROM Interlock_Store.AgentRun a JOIN Interlock_Store.""Case"" c ON a.""Case"" = c.ID WHERE 1=1" _ where _ " GROUP BY %EXACT(c.CaseId) ORDER BY %EXACT(c.CaseId) DESC", args...)
    While rs.%Next() { Set r = {} Set r.caseId = rs.%Get("CaseId"), r.runs = +rs.%Get("Runs"), r.costUsd = +rs.%Get("Cost") Do byCase.%Push(r) }
    Set o.byModel = byModel, o.byDay = byDay, o.byCase = byCase
    Quit ..Json(o)
}

}
