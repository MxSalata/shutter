/// The incident workflow (CONTRACTS 7): one instance per incident. It waits for the burst to go quiet, forms the
/// chains per encounter, writes the plan and its digest, asks for the approvals the site's policy requires, and
/// releases the chains one at a time and their items in order through each case's own dispatch, stopping a chain
/// at the first surprise. The instance keeps only identifiers; the store holds the record.
Class Shutter.Process.IncidentWorkflow Extends Ens.BusinessProcess
{

Property IncidentId As %String(MAXLEN = 32);

/// intake, ready, releasing, closed.
Property Phase As %String(MAXLEN = 16);

Property CurrentChainId As %String(MAXLEN = 20);

Property CurrentItemId As %String(MAXLEN = 20);

Property CurrentCaseId As %String(MAXLEN = 32);

Property Polls As %Integer [ InitialExpression = 0 ];

Property ReadyPolls As %Integer [ InitialExpression = 0 ];

/// Workflow tasks still open.
Property PendingTasks As %Integer [ InitialExpression = 0 ];

Property CaseTarget As %String(MAXLEN = 128) [ InitialExpression = "Case Workflow" ];

Property ApprovalTarget As %String(MAXLEN = 128) [ InitialExpression = "Shutter Approvers" ];

/// Seconds between checks of a released case's state (slower after the first minute).
Property PollSeconds As %Integer [ InitialExpression = 3 ];

/// How long to wait for every case to park (evidence collected) before the chains form without the laggards.
Property ReadyTimeoutSeconds As %Integer [ InitialExpression = 180 ];

Parameter SETTINGS = "CaseTarget:Targets,ApprovalTarget:Targets,PollSeconds:Timing,ReadyTimeoutSeconds:Timing";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    If 'request.%IsA("Shutter.Msg.IncidentIntake") Quit $$$ERROR($$$GeneralError, "Incident Workflow expects an incident intake, got " _ $CLASSNAME(request))
    Set incident = ##class(Shutter.Store.Incident).ByIncidentId(request.IncidentId)
    If '$ISOBJECT(incident) Quit $$$ERROR($$$GeneralError, "No incident " _ request.IncidentId)
    Set ..IncidentId = incident.IncidentId, ..Phase = "intake"
    Set incident.WorkflowSessionId = ..%SessionId
    Do incident.%Save()
    Do incident.Note("note", "Intake open: the chains form after " _ incident.QuietSeconds _ " s with no new failure to " _ incident.Receiver, "system")
    $$$TRACE("Incident " _ ..IncidentId _ " opened by case " _ request.CaseId)
    Quit ..Alarm(incident.QuietSeconds, "quiet")
}

Method Alarm(seconds As %Integer, key As %String) As %Status
{
    Set alarm = ##class(Ens.AlarmRequest).%New()
    Set alarm.Timeout = $SELECT(seconds < 1: 1, 1: seconds)
    Quit ..SendRequestAsync("Ens.Alarm", alarm, 1, key)
}

Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, completionkey As %String) As %Status
{
    Set sc = $$$OK
    Try {
        Set incident = ##class(Shutter.Store.Incident).ByIncidentId(..IncidentId)
        If '$ISOBJECT(incident) Quit
        If incident.State = "closed" { $$$TRACE("Incident " _ ..IncidentId _ " is closed; ignoring " _ completionkey) Quit }
        If completionkey = "quiet" { Set sc = ..OnQuiet(incident) Quit }
        If completionkey = "ready" { Set sc = ..OnReady(incident) Quit }
        If completionkey = "poll" { Set sc = ..OnPoll(incident) Quit }
        If completionkey = "approval" { Set sc = ..OnApproval(incident, "", callresponse) Quit }
        If $EXTRACT(completionkey, 1, 9) = "approval:" { Set sc = ..OnApproval(incident, $EXTRACT(completionkey, 10, *), callresponse) Quit }
        $$$LOGWARNING("Unexpected completion key " _ completionkey)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) {
        Set incident = ##class(Shutter.Store.Incident).ByIncidentId(..IncidentId)
        If $ISOBJECT(incident) && (incident.State '= "closed") {
            Do incident.Note("error", "Workflow error at " _ completionkey _ ": " _ $SYSTEM.Status.GetErrorText(sc), "system")
            Do ..Close(incident, "closed after a workflow error at " _ completionkey)
        }
    }
    Quit sc
}

// ---- intake and grouping ----

/// The quiet period has passed, or a failure came in meanwhile and the wait starts again.
Method OnQuiet(incident As Shutter.Store.Incident) As %Status
{
    If '##class(Shutter.Store.IncidentDetector).QuietFor(incident) {
        Set elapsed = ##class(Shutter.Util.Time).SecondsBetween(incident.LastFailureAt, ##class(Shutter.Util.Time).NowUTC())
        $$$TRACE("Failures still arriving; waiting another " _ (incident.QuietSeconds - elapsed) _ " s")
        Quit ..Alarm(incident.QuietSeconds - elapsed, "quiet")
    }
    Set incident.IntakeClosedAt = ##class(Shutter.Util.Time).NowUTC()
    Set sc = incident.%Save()
    Quit:$$$ISERR(sc) sc
    Set sc = incident.Note("note", "Intake closed after " _ incident.QuietSeconds _ " s of quiet: " _ incident.CaseCount() _ " cases. New failures to " _ incident.Receiver _ " count towards a new incident", "system")
    Quit:$$$ISERR(sc) sc
    Set ..Phase = "ready"
    Quit ..OnReady(incident)
}

/// Every case must have parked (its evidence and match in the store) before the chains form.
Method OnReady(incident As Shutter.Store.Incident) As %Status
{
    Set sc = $$$OK
    Set notReady = ##class(Shutter.Store.IncidentDetector).NotReady(incident)
    If notReady.%Size() > 0 {
        If (..ReadyPolls * ..PollSeconds) < ..ReadyTimeoutSeconds {
            Set ..ReadyPolls = ..ReadyPolls + 1
            Quit ..Alarm(..PollSeconds, "ready")
        }
        // The laggards leave the incident and continue on their own.
        Set iter = notReady.%GetIterator()
        While iter.%GetNext(.i, .caseId) {
            Set c = ##class(Shutter.Store.Case).ByCaseId(caseId)
            Continue:'$ISOBJECT(c)
            Set sc = ##class(Shutter.Store.IncidentDetector).Leave(c, incident, "its evidence was not collected within " _ ..ReadyTimeoutSeconds _ " s of the intake closing")
            Quit:$$$ISERR(sc)
        }
        Quit:$$$ISERR(sc) sc
    }
    Quit ..Classify(incident)
}

/// Group, classify, write the plan and its digest, then decide each chain's authorisation (7.2, 7.3).
Method Classify(incident As Shutter.Store.Incident) As %Status
{
    Set sc = ##class(Shutter.Store.IncidentDetector).Group(incident)
    Quit:$$$ISERR(sc) sc
    Set sc = ..BuildPlan(incident)
    Quit:$$$ISERR(sc) sc
    Set chains = incident.ChainList()
    Set n = chains.Count(), kinds = ""
    For i = 1:1:n {
        Set ch = chains.GetAt(i)
        Set kinds = kinds _ $SELECT(kinds = "": "", 1: "; ") _ "chain " _ ch.Seq _ " " _ ch.EncounterId _ ": " _ ch.Kind _ ", " _ ch.ItemCount() _ " item(s), " _ ch.Entries _ ", " _ ch.Decides _ " decides" _ $SELECT(ch.Policy '= "path": " (" _ ch.Policy _ ")", 1: "")
    }
    Set sc = incident.Transition("classified", n _ " chain(s) formed; plan digest " _ $EXTRACT(incident.PlanDigest, 1, 19) _ ". " _ kinds, "system")
    Quit:$$$ISERR(sc) sc
    // Authorisation per chain (7.3).
    Set shared = 0, perChain = 0, automatic = 0, own = 0
    For i = 1:1:n {
        Set ch = chains.GetAt(i)
        If ch.Decides '= "policy" {
            Set ch.State = "approved", own = own + 1
        } ElseIf ch.Policy = "automatic" {
            Set ch.State = "approved", automatic = automatic + 1
        } ElseIf ch.Policy = "per_chain" {
            Set ch.State = "awaiting_approval", perChain = perChain + 1
        } Else {
            Set ch.State = "awaiting_approval", shared = shared + 1
        }
        Set sc = ch.%Save()
        Quit:$$$ISERR(sc)
    }
    Quit:$$$ISERR(sc) sc
    Set incident.Policy = $SELECT((shared > 0) && (perChain > 0): "approval+per_chain", shared > 0: "approval", perChain > 0: "per_chain", automatic > 0: "automatic", 1: "none")
    Set sc = incident.%Save()
    Quit:$$$ISERR(sc) sc
    Set sc = incident.Note("note", "Authorisation: " _ automatic _ " policy chain(s) automatic, " _ shared _ " under one approval, " _ perChain _ " approved one by one, " _ own _ " on their own path (board or person)", "system")
    Quit:$$$ISERR(sc) sc
    If shared > 0 {
        Set sc = ..AskApproval(incident, chains, "")
        Quit:$$$ISERR(sc) sc
    }
    For i = 1:1:n {
        Set ch = chains.GetAt(i)
        If (ch.State = "awaiting_approval") && (ch.Policy = "per_chain") {
            Set sc = ..AskApproval(incident, chains, ch.Seq)
            Quit:$$$ISERR(sc)
        }
    }
    Quit:$$$ISERR(sc) sc
    If ..PendingTasks > 0 {
        Set sc = incident.Transition("awaiting_approval", ..PendingTasks _ " approval task(s) raised for the Workflow role; the automatic and board chains proceed meanwhile", "system")
        Quit:$$$ISERR(sc) sc
    }
    Quit ..Advance(incident)
}

/// The plan (7.2) and its digest: the chains' operation keys and payload digests in order, each chain's first
/// expected version, the receiver's epoch, and the catalogue, site profile and gate policy versions.
Method BuildPlan(incident As Shutter.Store.Incident) As %Status
{
    Set json = "Shutter.Util.Json"
    Set profile = ##class(Shutter.Store.SiteProfile).Current()
    Set incident.CatalogueVersion = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    Set incident.ProfileVersion = $CLASSMETHOD(json, "Str", profile, "version", 0)
    Set incident.PolicyVersion = ##class(Shutter.Operation.Gate).#POLICYVERSION
    Set plan = {}
    Set plan."incident_id" = incident.IncidentId, plan.receiver = incident.Receiver, plan.mode = incident.Mode
    Set plan.chains = [], material = "", epoch = ""
    Set chains = incident.ChainList()
    For i = 1:1:chains.Count() {
        Set ch = chains.GetAt(i)
        Set co = {}
        Set co.seq = ch.Seq, co."encounter_id" = ch.EncounterId, co."patient_id" = ch.PatientId, co.kind = ch.Kind
        Set co.decides = ch.Decides, co.policy = ch.Policy, co.entries = ch.Entries
        Do co.%Set("first_expected_version", ch.FirstExpectedVersion, $SELECT(ch.FirstExpectedVersion = "": "null", 1: "number"))
        Set co.items = []
        Set material = material _ "chain " _ ch.Seq _ "@" _ ch.FirstExpectedVersion _ ":"
        Set items = ch.Items()
        Set it = items.%GetIterator()
        While it.%GetNext(.k, .item) {
            Set c = ##class(Shutter.Store.Case).ByCaseId(item.%Get("caseId"))
            Set summary = $SELECT($ISOBJECT(c) && $ISOBJECT(c.CurrentSnapshot): c.CurrentSnapshot.SummaryObject(), 1: {})
            Set payload = $CLASSMETHOD(json, "Str", summary.%Get("operation"), "payload_digest")
            If epoch = "" Set epoch = $CLASSMETHOD(json, "Str", summary, "epoch")
            Set io = {}
            Set io.position = item.%Get("position"), io."case_id" = item.%Get("caseId"), io."event" = item.%Get("event"), io."event_time" = item.%Get("eventTime")
            Set io."operation_key" = item.%Get("operationKey"), io."payload_digest" = payload, io.entry = item.%Get("entry"), io.outcome = item.%Get("outcome")
            Do co.items.%Push(io)
            Set material = material _ item.%Get("operationKey") _ "#" _ payload _ ";"
        }
        Do plan.chains.%Push(co)
        Set material = material _ "|"
    }
    Set material = material _ "epoch=" _ epoch _ "|catalogue=" _ incident.CatalogueVersion _ "|profile=" _ incident.ProfileVersion _ "|policy=" _ incident.PolicyVersion
    Do plan.%Set("receiver_epoch", epoch, $SELECT(epoch = "": "null", 1: "number"))
    Set plan."catalogue_version" = incident.CatalogueVersion, plan."site_profile_version" = incident.ProfileVersion, plan."gate_policy_version" = incident.PolicyVersion
    Set plan.digest = ##class(Shutter.Util.Digest).SHA256Hex(material)
    Set incident.PlanJSON = plan.%ToJSON(), incident.PlanDigest = plan.digest
    If epoch '= "" Set incident.ReceiverEpoch = epoch
    Quit incident.%Save()
}

/// One Workflow task for the incident's policy chains under a shared approval (seq ""), or for one chain (7.3).
Method AskApproval(incident As Shutter.Store.Incident, chains As %ListOfObjects, seq As %String) As %Status
{
    Set lines = "", count = 0
    For i = 1:1:chains.Count() {
        Set ch = chains.GetAt(i)
        Continue:(ch.State '= "awaiting_approval")
        If seq = "" { Continue:(ch.Policy '= "approval") } Else { Continue:(ch.Seq '= seq) }
        Set count = count + 1
        Set lines = lines _ $CHAR(10) _ "Chain " _ ch.Seq _ " (" _ ch.Kind _ ", " _ ch.Entries _ "): encounter " _ ch.EncounterId _ ", patient " _ ch.PatientId _ ", first at receiver version " _ ch.FirstExpectedVersion
        Set items = ch.Items()
        Set it = items.%GetIterator()
        While it.%GetNext(.k, .item) {
            Set lines = lines _ $CHAR(10) _ "  " _ item.%Get("position") _ ". " _ item.%Get("event") _ " at " _ item.%Get("eventTime") _ " (" _ item.%Get("caseId") _ ", " _ item.%Get("entry") _ " " _ item.%Get("outcome") _ ")"
        }
    }
    Set task = ##class(EnsLib.Workflow.TaskRequest).%New()
    Set task.%Actions = "Approve,Reject"
    Set task.%Subject = "Shutter " _ incident.IncidentId _ $SELECT(seq '= "": "/" _ seq, 1: "") _ ": approve the release of " _ count _ " chain(s) to " _ incident.Receiver
    Set msg = "Incident " _ incident.IncidentId _ ": " _ incident.CaseCount() _ " failures to " _ incident.Receiver _ " since " _ incident.OpenedAt _ "." _ lines _ $CHAR(10) _ $CHAR(10)
    Set msg = msg _ "Approving binds: resend these, in this order. Each one is rehearsed, gated and verified just before it goes; items after the first go at exactly the version the previous item's verified receipt reports; the chain stops at the first surprise, and the rest comes back to you." _ $CHAR(10)
    Set msg = msg _ "Plan digest: " _ incident.PlanDigest _ $CHAR(10) _ "Catalogue " _ incident.CatalogueVersion _ ", site profile v" _ incident.ProfileVersion _ ", gate policy " _ incident.PolicyVersion
    Set task.%Message = msg
    Set task.%Priority = 1
    Set task.%FormFields = "PlanDigest,Comment"
    Do task.%FormValues.SetAt(incident.PlanDigest, "PlanDigest")
    Set sc = ..SendRequestAsync(..ApprovalTarget, task, 1, $SELECT(seq = "": "approval", 1: "approval:" _ seq))
    Quit:$$$ISERR(sc) sc
    Set ..PendingTasks = ..PendingTasks + 1
    Quit incident.Note("note", "Approval task raised: " _ task.%Subject, "system")
}

/// A Workflow task answered: the chains it covered are approved, or rejected with their cases escalated.
Method OnApproval(incident As Shutter.Store.Incident, seq As %String, result As EnsLib.Workflow.TaskResponse) As %Status
{
    Set sc = $$$OK
    Set ..PendingTasks = ..PendingTasks - 1
    Set action = $ZCONVERT(result.%Action, "L"), user = result.%UserName
    Set comment = result.%FormValues.GetAt("Comment"), digest = result.%FormValues.GetAt("PlanDigest"), taskId = result.%Id()
    Set ok = (action = "approve") && (digest '= "") && (digest = incident.PlanDigest)
    Set why = $SELECT(action '= "approve": "rejected by " _ user _ $SELECT(comment '= "": ": " _ comment, 1: ""), digest = "": "the approval carried no plan digest, so it binds nothing", 1: "the approval named another plan digest (" _ $EXTRACT(digest, 1, 19) _ ")")
    Set chains = incident.ChainList(), now = ##class(Shutter.Util.Time).NowUTC()
    If seq = "" {
        Set incident.ApprovedBy = user, incident.ApprovedAt = now, incident.ApprovalDecision = $SELECT(ok: "approved", 1: "rejected")
        Set incident.ApprovalComment = $EXTRACT(comment, 1, 2000), incident.ApprovalTaskId = taskId
        Set sc = incident.%Save()
        Quit:$$$ISERR(sc) sc
    }
    For i = 1:1:chains.Count() {
        Set ch = chains.GetAt(i)
        Continue:(ch.State '= "awaiting_approval")
        If seq = "" { Continue:(ch.Policy '= "approval") } Else { Continue:(ch.Seq '= seq) }
        If seq '= "" {
            Set ch.ApprovedBy = user, ch.ApprovedAt = now, ch.ApprovalDecision = $SELECT(ok: "approved", 1: "rejected"), ch.ApprovalComment = $EXTRACT(comment, 1, 2000), ch.ApprovalTaskId = taskId
        }
        If ok {
            Set ch.State = "approved"
            Set sc = ch.%Save()
        } Else {
            Set ch.State = "rejected", ch.Outcome = "Not released: " _ why
            Set sc = ch.%Save()
            Quit:$$$ISERR(sc)
            Set sc = ch.StopRest("incident " _ incident.IncidentId _ ", chain " _ ch.Seq _ ", " _ why, user)
        }
        Quit:$$$ISERR(sc)
    }
    Quit:$$$ISERR(sc) sc
    Set sc = incident.Note("approval", $SELECT(ok: "Approved by " _ user _ " (task " _ taskId _ ", plan digest " _ $EXTRACT(digest, 1, 19) _ ")", 1: "Not approved: " _ why _ " (task " _ taskId _ ")") _ $SELECT(seq '= "": ", chain " _ seq, 1: ", the policy chains under one approval"), user)
    Quit:$$$ISERR(sc) sc
    Quit ..Advance(incident)
}

// ---- release ----

/// Release the next item: the lowest approved chain, its next pending item (7.4). With nothing approved and
/// tasks still open, wait; with nothing left, close.
Method Advance(incident As Shutter.Store.Incident) As %Status
{
    If ..CurrentCaseId '= "" Quit $$$OK
    Set chain = ""
    If ..CurrentChainId '= "" Set chain = ##class(Shutter.Store.Chain).%OpenId(..CurrentChainId)
    If $ISOBJECT(chain) && (chain.State '= "releasing") Set chain = ""
    If '$ISOBJECT(chain) {
        Set rid = "", iid = incident.%Id()
        &sql(SELECT TOP 1 ID INTO :rid FROM Shutter_Store.Chain WHERE Incident = :iid AND State = 'approved' ORDER BY Seq)
        If (SQLCODE '= 0) || (rid = "") {
            Set ..CurrentChainId = ""
            If ..PendingTasks > 0 Quit $$$OK
            Set n = 0
            &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store.Chain WHERE Incident = :iid AND State IN ('awaiting_approval', 'releasing'))
            If +n > 0 Quit $$$OK
            Quit ..Close(incident, "")
        }
        Set chain = ##class(Shutter.Store.Chain).%OpenId(rid)
        Set chain.State = "releasing"
        Set sc = chain.%Save()
        Quit:$$$ISERR(sc) sc
        Set ..CurrentChainId = chain.%Id()
        If incident.State '= "releasing" {
            Set sc = incident.Transition("releasing", "Releasing chain " _ chain.Seq _ " (" _ chain.Kind _ ", " _ chain.EncounterId _ ")", "system")
            Quit:$$$ISERR(sc) sc
        } Else {
            Do incident.Note("release", "Releasing chain " _ chain.Seq _ " (" _ chain.Kind _ ", " _ chain.EncounterId _ ")", "system")
        }
    }
    Set item = chain.NextPending()
    If '$ISOBJECT(item) {
        Set chain.State = "resolved", chain.Outcome = chain.ItemCount() _ " item(s) resolved in order"
        Set sc = chain.%Save()
        Quit:$$$ISERR(sc) sc
        Do incident.Note("release", "Chain " _ chain.Seq _ " resolved: " _ chain.Outcome, "system")
        Set ..CurrentChainId = ""
        Quit ..Advance(incident)
    }
    // The expected version: the previous item's verified version; for the first item the chain's, when a person
    // approved the chain; otherwise fresh evidence decides.
    Set expected = ""
    If item.Position > 1 {
        Set prev = chain.ItemAt(item.Position - 1)
        If $ISOBJECT(prev) Set expected = prev.VerifiedVersion
    } ElseIf (chain.Policy = "approval") || (chain.Policy = "per_chain") {
        Set expected = chain.FirstExpectedVersion
    }
    Set item.ExpectedVersion = expected, item.State = "released", item.ReleasedAt = ##class(Shutter.Util.Time).NowUTC()
    Set sc = item.%Save()
    Quit:$$$ISERR(sc) sc
    Set rel = ##class(Shutter.Msg.CaseRelease).%New()
    Set rel.CaseId = item.Case.CaseId, rel.IncidentId = incident.IncidentId, rel.ChainSeq = chain.Seq, rel.Position = item.Position
    Set rel.ChainKind = chain.Kind, rel.Decides = chain.Decides, rel.ExpectedVersion = expected, rel.PlanDigest = incident.PlanDigest
    Set rel.ReleasePolicy = $CASE(chain.Policy, "automatic": "automatic", "approval": "incident", "per_chain": "incident", : "path")
    If chain.Policy = "approval" Set rel.Approver = incident.ApprovedBy, rel.ApprovalRef = incident.ApprovalTaskId
    If chain.Policy = "per_chain" Set rel.Approver = chain.ApprovedBy, rel.ApprovalRef = chain.ApprovalTaskId
    Set ..CurrentItemId = item.%Id(), ..CurrentCaseId = rel.CaseId, ..Polls = 0
    Do incident.Note("release", "Chain " _ chain.Seq _ " item " _ item.Position _ ": case " _ rel.CaseId _ " released (" _ item.Case.Event _ " for " _ chain.EncounterId _ $SELECT(expected '= "": ", at expected version " _ expected, 1: ", fresh evidence decides") _ ", " _ rel.ReleasePolicy _ ")", "system")
    Set sc = ..SendRequestAsync(..CaseTarget, rel, 0)
    Quit:$$$ISERR(sc) sc
    Quit ..Alarm(..PollSeconds, "poll")
}

/// The released case's state: still running, resolved (the next item follows), or stopped (the chain stops).
Method OnPoll(incident As Shutter.Store.Incident) As %Status
{
    Set case = ##class(Shutter.Store.Case).ByCaseId(..CurrentCaseId)
    If '$ISOBJECT(case) Quit $$$ERROR($$$GeneralError, "Released case " _ ..CurrentCaseId _ " not found")
    If 'case.IsClosed() {
        Set ..Polls = ..Polls + 1
        Quit ..Alarm(..PollInterval(), "poll")
    }
    Set item = ##class(Shutter.Store.ChainItem).%OpenId(..CurrentItemId), chain = ##class(Shutter.Store.Chain).%OpenId(..CurrentChainId)
    Set item.ClosedAt = ##class(Shutter.Util.Time).NowUTC()
    // The match on the fresh evidence, beside the chain-time one the plan was built on.
    Set rcat = ##class(Shutter.Store.IncidentDetector).CatalogueOf(case)
    If $ISOBJECT(rcat) Set item.ReleaseEntry = ##class(Shutter.Util.Json).Str(rcat, "entry"), item.ReleaseOutcome = ##class(Shutter.Util.Json).Str(rcat, "outcome")
    If case.State = "resolved" {
        Set item.State = "resolved", item.VerifiedVersion = ..VersionAfter(case, item)
        Set sc = item.%Save()
        Quit:$$$ISERR(sc) sc
        Do incident.Note("release", "Chain " _ chain.Seq _ " item " _ item.Position _ ": case " _ case.CaseId _ " resolved (" _ case.Disposition _ "; receiver version " _ item.VerifiedVersion _ "). " _ $EXTRACT(case.Outcome, 1, 300), "system")
        Set ..CurrentCaseId = "", ..CurrentItemId = ""
        Quit ..Advance(incident)
    }
    // Blocked, escalated or failed: the chain stops here; the rest goes to a person (7.4).
    Set item.State = $CASE(case.State, "escalated": "escalated", "blocked": "blocked", : "failed")
    Set sc = item.%Save()
    Quit:$$$ISERR(sc) sc
    Set chain.StoppedAt = item.Position
    Set chain.State = $SELECT(case.State = "escalated": "escalated", 1: "stopped")
    Set chain.Outcome = $SELECT(case.State = "escalated": "Escalated", 1: "Stopped") _ " at item " _ item.Position _ " (case " _ case.CaseId _ " " _ case.State _ "): " _ $EXTRACT(case.Headline, 1, 500)
    Set sc = chain.%Save()
    Quit:$$$ISERR(sc) sc
    Set sc = chain.StopRest("chain " _ chain.Seq _ " of incident " _ incident.IncidentId _ " " _ chain.State _ " at item " _ item.Position _ " (" _ case.CaseId _ ": " _ $EXTRACT(case.Headline, 1, 200) _ ")")
    Quit:$$$ISERR(sc) sc
    Do incident.Note("release", "Chain " _ chain.Seq _ " " _ chain.State _ ": " _ chain.Outcome, "system")
    Set ..CurrentCaseId = "", ..CurrentItemId = "", ..CurrentChainId = ""
    Quit ..Advance(incident)
}

/// Every PollSeconds for the first minute, every 15 s for the next ten minutes, then every minute (a person
/// may be deciding a board chain's approval).
Method PollInterval() As %Integer
{
    If ..Polls <= 20 Quit ..PollSeconds
    If ..Polls <= 60 Quit 15
    Quit 60
}

/// The receiver's version after a resolved case: its last write's response, else the verification's read of the
/// encounter, else the version the item expected.
Method VersionAfter(case As Shutter.Store.Case, item As Shutter.Store.ChainItem) As %String
{
    Set json = "Shutter.Util.Json", cid = case.%Id(), v = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM Shutter_Store.ExecutionAttempt WHERE ""Case"" = ? AND Outcome IN ('applied', 'already_committed') ORDER BY ID DESC", cid)
    If rs.%Next() {
        Set a = ##class(Shutter.Store.ExecutionAttempt).%OpenId(rs.%Get("ID"))
        If $ISOBJECT(a) {
            Set r = $CLASSMETHOD(json, "Parse", a.ResponseJSON, .psc)
            If $ISOBJECT(r) Set v = $CLASSMETHOD(json, "Str", r, "version_after", $CLASSMETHOD(json, "Str", r, "version", $CLASSMETHOD(json, "Str", r, "encounter_version")))
        }
    }
    If v = "" {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM Shutter_Store.Verification WHERE ""Case"" = ? ORDER BY ID DESC", cid)
        If rs.%Next() {
            Set ver = ##class(Shutter.Store.Verification).%OpenId(rs.%Get("ID"))
            If $ISOBJECT(ver) {
                Set d = $CLASSMETHOD(json, "Parse", ver.DetailJSON, .psc)
                If $ISOBJECT(d) && $ISOBJECT(d.%Get("encounter")) Set v = $CLASSMETHOD(json, "Str", d.%Get("encounter"), "version")
            }
        }
    }
    If v = "" Set v = item.ExpectedVersion
    Quit v
}

/// Close the incident with each chain's outcome counted.
Method Close(incident As Shutter.Store.Incident, why As %String) As %Status
{
    Set iid = incident.%Id(), r = 0, s = 0, e = 0, j = 0, total = 0
    &sql(SELECT COUNT(*) INTO :total FROM Shutter_Store.Chain WHERE Incident = :iid)
    &sql(SELECT COUNT(*) INTO :r FROM Shutter_Store.Chain WHERE Incident = :iid AND State = 'resolved')
    &sql(SELECT COUNT(*) INTO :s FROM Shutter_Store.Chain WHERE Incident = :iid AND State = 'stopped')
    &sql(SELECT COUNT(*) INTO :e FROM Shutter_Store.Chain WHERE Incident = :iid AND State = 'escalated')
    &sql(SELECT COUNT(*) INTO :j FROM Shutter_Store.Chain WHERE Incident = :iid AND State = 'rejected')
    Set incident.Summary = total _ " chain(s): " _ r _ " resolved, " _ s _ " stopped, " _ e _ " escalated, " _ j _ " rejected" _ $SELECT(why '= "": "; " _ why, 1: "")
    Set ..Phase = "closed", ..CurrentCaseId = "", ..CurrentItemId = "", ..CurrentChainId = ""
    Quit incident.Transition("closed", "Closed: " _ incident.Summary, "system")
}

Storage Default
{
<Data name="IncidentWorkflowDefaultData">
<Subscript>"IncidentWorkflow"</Subscript>
<Value name="1">
<Value>IncidentId</Value>
</Value>
<Value name="2">
<Value>Phase</Value>
</Value>
<Value name="3">
<Value>CurrentChainId</Value>
</Value>
<Value name="4">
<Value>CurrentItemId</Value>
</Value>
<Value name="5">
<Value>CurrentCaseId</Value>
</Value>
<Value name="6">
<Value>Polls</Value>
</Value>
<Value name="7">
<Value>ReadyPolls</Value>
</Value>
<Value name="8">
<Value>PendingTasks</Value>
</Value>
<Value name="9">
<Value>CaseTarget</Value>
</Value>
<Value name="10">
<Value>ApprovalTarget</Value>
</Value>
<Value name="11">
<Value>PollSeconds</Value>
</Value>
<Value name="12">
<Value>ReadyTimeoutSeconds</Value>
</Value>
</Data>
<DefaultData>IncidentWorkflowDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
