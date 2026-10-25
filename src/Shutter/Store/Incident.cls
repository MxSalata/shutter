/// Many failures to one receiver, grouped (CONTRACTS 7): the incident opens at the site's threshold, adopts the
/// burst's cases, forms chains per encounter, and releases them in order through each case's own dispatch.
Class Shutter.Store.Incident Extends (%Persistent, %JSON.Adaptor)
{

/// I-nnnnnn
Property IncidentId As %String(%JSONFIELDNAME = "incidentId", MAXLEN = 32) [ Required ];

Index IncidentIdx On IncidentId [ Unique ];

/// The production item the failures went to.
Property Receiver As %String(%JSONFIELDNAME = "receiver", MAXLEN = 128);

/// The investigation mode of the cases (board, single, rules, policy): only policy lets the catalogue settle chains.
Property Mode As %String(%JSONFIELDNAME = "mode", MAXLEN = 16);

/// open (taking cases), classified, awaiting_approval, releasing, closed.
Property State As %String(%JSONFIELDNAME = "state", MAXLEN = 32, VALUELIST = ",open,classified,awaiting_approval,releasing,closed") [ InitialExpression = "open" ];

Property OpenedAt As %String(%JSONFIELDNAME = "openedAt", MAXLEN = 30);

Property IntakeClosedAt As %String(%JSONFIELDNAME = "intakeClosedAt", MAXLEN = 30);

Property ClosedAt As %String(%JSONFIELDNAME = "closedAt", MAXLEN = 30);

Property Threshold As %Integer(%JSONFIELDNAME = "threshold");

Property WindowMinutes As %Integer(%JSONFIELDNAME = "windowMinutes");

Property QuietSeconds As %Integer(%JSONFIELDNAME = "quietSeconds");

/// The last failure's time, for the quiet period.
Property LastFailureAt As %String(%JSONFIELDNAME = "lastFailureAt", MAXLEN = 30);

/// The plan's digest (7.2): the SHA-256 of the recorded plan in canonical JSON (BuildPlan), which binds every chain and
/// item as listed (each item's case, operation key, payload digest, catalogue entry, outcome and the version it goes
/// at), the receiver's epoch and the catalogue, site profile and gate policy versions.
Property PlanDigest As %String(%JSONFIELDNAME = "planDigest", MAXLEN = 80);

Property PlanJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

Property ReceiverEpoch As %Integer(%JSONFIELDNAME = "receiverEpoch");

/// The catalogue's version string names every entry with its version (E1@1,E2@1,...), so it is long.
Property CatalogueVersion As %String(%JSONFIELDNAME = "catalogueVersion", MAXLEN = 2000);

Property ProfileVersion As %String(%JSONFIELDNAME = "profileVersion", MAXLEN = 32);

Property PolicyVersion As %String(%JSONFIELDNAME = "policyVersion", MAXLEN = 32);

/// How the policy chains were authorised: automatic, approval, per_chain, approval+per_chain, or none (no policy chain).
Property Policy As %String(%JSONFIELDNAME = "policy", MAXLEN = 24);

/// The approval of the incident's policy chains (policy approval): who, when, what they said.
Property ApprovedBy As %String(%JSONFIELDNAME = "approvedBy", MAXLEN = 100);

Property ApprovedAt As %String(%JSONFIELDNAME = "approvedAt", MAXLEN = 30);

Property ApprovalDecision As %String(%JSONFIELDNAME = "approvalDecision", MAXLEN = 16);

Property ApprovalComment As %String(%JSONFIELDNAME = "approvalComment", MAXLEN = 2000);

Property ApprovalTaskId As %String(%JSONFIELDNAME = "approvalTaskId", MAXLEN = 50);

Property WorkflowSessionId As %String(%JSONFIELDNAME = "workflowSessionId", MAXLEN = 20);

Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = 4000);

Property Version As %Integer(%JSONFIELDNAME = "version") [ InitialExpression = 0 ];

ClassMethod ByIncidentId(id As %String) As Shutter.Store.Incident
{
    Set rid = ""
    &sql(SELECT ID INTO :rid FROM Shutter_Store.Incident WHERE IncidentId = :id)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ..%OpenId(rid)
}

/// The incident still taking cases for a receiver (open, intake not closed, opened since the last scenario reset), or "".
ClassMethod OpenFor(receiver As %String) As Shutter.Store.Incident
{
    Set rid = "", resetAt = $GET(^Shutter.Config("resetAt"))
    &sql(SELECT TOP 1 ID INTO :rid FROM Shutter_Store.Incident WHERE Receiver = :receiver AND State = 'open' AND IntakeClosedAt IS NULL AND (OpenedAt >= :resetAt OR :resetAt IS NULL) ORDER BY ID DESC)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ..%OpenId(rid)
}

/// Close every incident still taking cases: a scenario reset is the demo's new day, and an intake left open would
/// take the next run's failures. Returns how many were closed.
ClassMethod AbandonOpen(why As %String, actor As %String = "system") As %Integer [ SqlProc ]
{
    // The guard is for SQL callers (the terminal, the API's users); the production's own jobs (a scenario reset) run it freely.
    If $ISOBJECT($GET(%sqlcontext)) && '$SYSTEM.Security.Check("Shutter_Operate", "USE") Quit -1
    Set n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Incident WHERE State <> 'closed'")
    While rs.%Next() {
        Set inc = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(inc)
        If $$$ISOK(inc.Abandon(why, actor)) Set n = n + 1
    }
    Quit n
}

/// Open an incident for a receiver with the site's settings.
ClassMethod Open(receiver As %String, mode As %String, Output incident As Shutter.Store.Incident) As %Status
{
    Set incident = ..%New()
    Set incident.IncidentId = "I-" _ $TRANSLATE($JUSTIFY($INCREMENT(^Shutter.Counter("incident")), 6), " ", "0")
    Set incident.Receiver = receiver, incident.State = "open", incident.Mode = $SELECT(mode = "": "board", 1: mode)
    Set incident.OpenedAt = ##class(Shutter.Util.Time).NowUTC(), incident.LastFailureAt = incident.OpenedAt
    Set incident.Threshold = ##class(Shutter.Store.SiteProfile).IncidentSetting("threshold", 5)
    Set incident.WindowMinutes = ##class(Shutter.Store.SiteProfile).IncidentSetting("window_minutes", 10)
    Set incident.QuietSeconds = ##class(Shutter.Store.SiteProfile).IncidentSetting("quiet_seconds", 60)
    Set sc = incident.%Save()
    Quit:$$$ISERR(sc) sc
    Quit incident.Note("state", "Incident opened for " _ receiver _ ": " _ incident.Threshold _ " failures within " _ incident.WindowMinutes _ " minutes (mode " _ incident.Mode _ ")", "system")
}

/// Move to a state with an event.
Method Transition(toState As %String, text As %String, actor As %String = "system") As %Status
{
    Set ..State = toState, ..Version = ..Version + 1
    If toState = "closed" Set ..ClosedAt = ##class(Shutter.Util.Time).NowUTC()
    Set sc = ..%Save()
    Quit:$$$ISERR(sc) sc
    Quit ..Note("state", text, actor)
}

Method Note(kind As %String, text As %String, actor As %String = "system") As %Status
{
    Set e = ##class(Shutter.Store.IncidentEvent).%New()
    Set e.Incident = $THIS, e.At = ##class(Shutter.Util.Time).NowUTC(), e.Kind = kind, e.Text = $EXTRACT(text, 1, 4000), e.Actor = actor
    Set e.Seq = $INCREMENT(^Shutter.Counter("incidentEvent", ..%Id()))
    Quit e.%Save()
}

/// The incident's chains, in order, with their items.
Method Chains() As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Chain WHERE Incident = ? ORDER BY Seq", ..%Id())
    While rs.%Next() {
        Set c = ##class(Shutter.Store.Chain).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Do out.%Push(c.ToObject())
    }
    Quit out
}

/// The chain objects in order (not projected).
Method ChainList() As %ListOfObjects
{
    Set out = ##class(%ListOfObjects).%New()
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Chain WHERE Incident = ? ORDER BY Seq", ..%Id())
    While rs.%Next() {
        Set c = ##class(Shutter.Store.Chain).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Do out.Insert(c)
    }
    Quit out
}

/// The chain at a sequence number, or "".
Method ChainAt(seq As %Integer) As Shutter.Store.Chain
{
    Set iid = ..%Id(), rid = ""
    &sql(SELECT ID INTO :rid FROM Shutter_Store.Chain WHERE Incident = :iid AND Seq = :seq)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ##class(Shutter.Store.Chain).%OpenId(rid)
}

/// How many cases the incident holds.
Method CaseCount() As %Integer
{
    Set iid = ..%Id(), n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store."Case" WHERE Incident = :iid)
    Quit +n
}

/// Counts of chains by kind and by state, and of cases.
Method Progress() As %DynamicObject
{
    Set o = {}, byKind = {}, byState = {}, n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Kind, State FROM Shutter_Store.Chain WHERE Incident = ?", ..%Id())
    While rs.%Next() {
        Set n = n + 1
        Set k = $SELECT(rs.%Get("Kind") = "": "unclassified", 1: rs.%Get("Kind")), st = rs.%Get("State")
        Do byKind.%Set(k, byKind.%Get(k) + 1), byState.%Set(st, byState.%Get(st) + 1)
    }
    Set o.chains = n, o.cases = ..CaseCount(), o.byKind = byKind, o.byState = byState
    Quit o
}

/// The plan (CONTRACTS 7.2) and its digest. The plan lists every chain with its kind, who decides it, its policy, its
/// entries and its items in order (case id, operation key, payload digest, catalogue entry, outcome, who decides, and
/// the receiver version the item goes at: the chain's first expected version for the first item of a chain a person
/// approves, null otherwise, since the rest go at the version the previous item verifies and an automatic or board
/// chain's first item goes on fresh evidence), with the receiver's epoch and the catalogue, site profile and gate
/// policy versions. The digest is the SHA-256 of that plan as recorded, in canonical JSON (Shutter.Util.Digest.OfObject,
/// as the case plan's digest is made), so GET /incidents/{id}.plan without its digest member recomputes it and every
/// item's case, entry and outcome are bound. Built once the chains are classified, before their states are decided.
Method BuildPlan(policyVersion As %String) As %Status
{
    Set json = "Shutter.Util.Json"
    Set profile = ##class(Shutter.Store.SiteProfile).Current()
    Set ..CatalogueVersion = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    Set ..ProfileVersion = $CLASSMETHOD(json, "Str", profile, "version", 0)
    Set ..PolicyVersion = policyVersion
    Set plan = {}
    Set plan."incident_id" = ..IncidentId, plan.receiver = ..Receiver, plan.mode = ..Mode
    Set plan.chains = [], epoch = ""
    Set chains = ..ChainList()
    For i = 1:1:chains.Count() {
        Set ch = chains.GetAt(i)
        Set co = {}
        Set co.seq = ch.Seq, co."encounter_id" = ch.EncounterId, co."patient_id" = ch.PatientId, co.kind = ch.Kind
        Set co.decides = ch.Decides, co.policy = ch.Policy, co.entries = ch.Entries
        Do co.%Set("first_expected_version", ch.FirstExpectedVersion, $SELECT(ch.FirstExpectedVersion = "": "null", 1: "number"))
        Set co.items = []
        // The first item of a chain a person approves goes at the chain's first expected version (7.4); every other
        // item goes at the version the previous one verifies, or on fresh evidence, which the plan cannot know yet.
        Set first = $SELECT((ch.Policy = "approval") || (ch.Policy = "per_chain"): ch.FirstExpectedVersion, 1: "")
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
            Set io.decides = item.%Get("decides")
            Set expected = $SELECT(item.%Get("position") = 1: first, 1: "")
            Do io.%Set("expected_version", expected, $SELECT(expected = "": "null", 1: "number"))
            Do co.items.%Push(io)
        }
        Do plan.chains.%Push(co)
    }
    Do plan.%Set("receiver_epoch", epoch, $SELECT(epoch = "": "null", 1: "number"))
    Set plan."catalogue_version" = ..CatalogueVersion, plan."site_profile_version" = ..ProfileVersion, plan."gate_policy_version" = ..PolicyVersion
    // The digest is of the plan without itself; the plan then records it.
    Set plan.digest = ##class(Shutter.Util.Digest).OfObject(plan)
    Set ..PlanJSON = plan.%ToJSON(), ..PlanDigest = plan.digest
    If epoch '= "" Set ..ReceiverEpoch = epoch
    Quit ..%Save()
}

/// The approvals given: the incident's own and each chain's.
Method Approvals() As %DynamicArray
{
    Set out = []
    If ..ApprovalDecision '= "" {
        Do out.%Push({"scope": "incident", "by": (..ApprovedBy), "at": (..ApprovedAt), "decision": (..ApprovalDecision), "comment": (..ApprovalComment), "taskId": (..ApprovalTaskId), "planDigest": (..PlanDigest)})
    }
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Chain WHERE Incident = ? AND ApprovalDecision IS NOT NULL ORDER BY Seq", ..%Id())
    While rs.%Next() {
        Set c = ##class(Shutter.Store.Chain).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Do out.%Push({"scope": "chain", "seq": (c.Seq), "by": (c.ApprovedBy), "at": (c.ApprovedAt), "decision": (c.ApprovalDecision), "comment": (c.ApprovalComment), "taskId": (c.ApprovalTaskId), "planDigest": (..PlanDigest)})
    }
    Quit out
}

/// Close an incident whose workflow is gone (it died, or the production was reset): the chains still open are
/// stopped and the cases it still holds (adopted or parked, not yet released) are failed with the reason, so nothing
/// waits forever. A released case is driven by its own workflow instance past the board and is left to finish.
Method Abandon(why As %String, actor As %String = "operator") As %Status
{
    Set sc = $$$OK
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Chain WHERE Incident = ? AND State IN ('pending', 'awaiting_approval', 'approved', 'releasing')", ..%Id())
    While rs.%Next() {
        Set ch = ##class(Shutter.Store.Chain).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(ch)
        Set ch.State = "stopped", ch.Outcome = $EXTRACT("Abandoned: " _ why, 1, 2000)
        Set sc = ch.%Save()
        Quit:$$$ISERR(sc)
    }
    Quit:$$$ISERR(sc) sc
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.""Case"" WHERE Incident = ? AND State IN ('detected', 'collecting', 'investigating', 'grouped')", ..%Id())
    While rs.%Next() {
        Set c = ##class(Shutter.Store.Case).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Set c.Headline = $EXTRACT("Abandoned with incident " _ ..IncidentId _ ": " _ why, 1, 500)
        Set sc = c.Transition("failed", "Abandoned with incident " _ ..IncidentId _ ": " _ why, actor, "incident:" _ ..IncidentId)
        Quit:$$$ISERR(sc)
    }
    Quit:$$$ISERR(sc) sc
    Set ..Summary = $EXTRACT("Abandoned: " _ why, 1, 4000)
    Quit ..Transition("closed", "Abandoned by " _ actor _ ": " _ why, actor)
}

/// Abandon an incident by its public id (for the terminal and SQL); returns the status text.
ClassMethod AbandonById(id As %String, why As %String, actor As %String = "operator") As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("Shutter_Operate", "USE") Quit "Shutter_Operate is required"
    Set inc = ..ByIncidentId(id)
    If '$ISOBJECT(inc) Quit "no incident " _ id
    If inc.State = "closed" Quit id _ " is already closed"
    Set sc = inc.Abandon(why, actor)
    Quit $SELECT($$$ISOK(sc): id _ " closed", 1: $SYSTEM.Status.GetErrorText(sc))
}

Method Events() As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.IncidentEvent WHERE Incident = ? ORDER BY Seq", ..%Id())
    While rs.%Next() {
        Set e = ##class(Shutter.Store.IncidentEvent).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(e)
        Do out.%Push({"at": (e.At), "kind": (e.Kind), "text": (e.Text), "actor": (e.Actor)})
    }
    Quit out
}

Storage Default
{
<Data name="IncidentDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>IncidentId</Value>
</Value>
<Value name="3">
<Value>Receiver</Value>
</Value>
<Value name="4">
<Value>Mode</Value>
</Value>
<Value name="5">
<Value>State</Value>
</Value>
<Value name="6">
<Value>OpenedAt</Value>
</Value>
<Value name="7">
<Value>IntakeClosedAt</Value>
</Value>
<Value name="8">
<Value>ClosedAt</Value>
</Value>
<Value name="9">
<Value>Threshold</Value>
</Value>
<Value name="10">
<Value>WindowMinutes</Value>
</Value>
<Value name="11">
<Value>QuietSeconds</Value>
</Value>
<Value name="12">
<Value>LastFailureAt</Value>
</Value>
<Value name="13">
<Value>PlanDigest</Value>
</Value>
<Value name="14">
<Value>PlanJSON</Value>
</Value>
<Value name="15">
<Value>ReceiverEpoch</Value>
</Value>
<Value name="16">
<Value>CatalogueVersion</Value>
</Value>
<Value name="17">
<Value>ProfileVersion</Value>
</Value>
<Value name="18">
<Value>PolicyVersion</Value>
</Value>
<Value name="19">
<Value>Policy</Value>
</Value>
<Value name="20">
<Value>ApprovedBy</Value>
</Value>
<Value name="21">
<Value>ApprovedAt</Value>
</Value>
<Value name="22">
<Value>ApprovalDecision</Value>
</Value>
<Value name="23">
<Value>ApprovalComment</Value>
</Value>
<Value name="24">
<Value>ApprovalTaskId</Value>
</Value>
<Value name="25">
<Value>WorkflowSessionId</Value>
</Value>
<Value name="26">
<Value>Summary</Value>
</Value>
<Value name="27">
<Value>Version</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.IncidentD</DataLocation>
<DefaultData>IncidentDefaultData</DefaultData>
<IdLocation>^Shutter.Store.IncidentD</IdLocation>
<IndexLocation>^Shutter.Store.IncidentI</IndexLocation>
<StreamLocation>^Shutter.Store.IncidentS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
