/// Many failures to one receiver, grouped (CONTRACTS 7): the incident opens at the site's threshold, adopts the
/// burst's cases, forms chains per encounter, and releases them in order through each case's own dispatch.
Class Interlock.Store.Incident Extends (%Persistent, %JSON.Adaptor)
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

/// The plan's digest (7.2): the chains' operation keys in order, their payload digests, each chain's first
/// expected version, the receiver's epoch, the catalogue, site profile and gate policy versions.
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

ClassMethod ByIncidentId(id As %String) As Interlock.Store.Incident
{
    Set rid = ""
    &sql(SELECT ID INTO :rid FROM Interlock_Store.Incident WHERE IncidentId = :id)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ..%OpenId(rid)
}

/// The incident still taking cases for a receiver (open, intake not closed), or "".
ClassMethod OpenFor(receiver As %String) As Interlock.Store.Incident
{
    Set rid = ""
    &sql(SELECT TOP 1 ID INTO :rid FROM Interlock_Store.Incident WHERE Receiver = :receiver AND State = 'open' AND IntakeClosedAt IS NULL ORDER BY ID DESC)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ..%OpenId(rid)
}

/// Open an incident for a receiver with the site's settings.
ClassMethod Open(receiver As %String, mode As %String, Output incident As Interlock.Store.Incident) As %Status
{
    Set incident = ..%New()
    Set incident.IncidentId = "I-" _ $TRANSLATE($JUSTIFY($INCREMENT(^Interlock.Counter("incident")), 6), " ", "0")
    Set incident.Receiver = receiver, incident.State = "open", incident.Mode = $SELECT(mode = "": "board", 1: mode)
    Set incident.OpenedAt = ##class(Interlock.Util.Time).NowUTC(), incident.LastFailureAt = incident.OpenedAt
    Set incident.Threshold = ##class(Interlock.Store.SiteProfile).IncidentSetting("threshold", 5)
    Set incident.WindowMinutes = ##class(Interlock.Store.SiteProfile).IncidentSetting("window_minutes", 10)
    Set incident.QuietSeconds = ##class(Interlock.Store.SiteProfile).IncidentSetting("quiet_seconds", 60)
    Set sc = incident.%Save()
    Quit:$$$ISERR(sc) sc
    Quit incident.Note("state", "Incident opened for " _ receiver _ ": " _ incident.Threshold _ " failures within " _ incident.WindowMinutes _ " minutes (mode " _ incident.Mode _ ")", "system")
}

/// Move to a state with an event.
Method Transition(toState As %String, text As %String, actor As %String = "system") As %Status
{
    Set ..State = toState, ..Version = ..Version + 1
    If toState = "closed" Set ..ClosedAt = ##class(Interlock.Util.Time).NowUTC()
    Set sc = ..%Save()
    Quit:$$$ISERR(sc) sc
    Quit ..Note("state", text, actor)
}

Method Note(kind As %String, text As %String, actor As %String = "system") As %Status
{
    Set e = ##class(Interlock.Store.IncidentEvent).%New()
    Set e.Incident = $THIS, e.At = ##class(Interlock.Util.Time).NowUTC(), e.Kind = kind, e.Text = $EXTRACT(text, 1, 4000), e.Actor = actor
    Set e.Seq = $INCREMENT(^Interlock.Counter("incidentEvent", ..%Id()))
    Quit e.%Save()
}

/// The incident's chains, in order, with their items.
Method Chains() As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.Chain WHERE Incident = ? ORDER BY Seq", ..%Id())
    While rs.%Next() {
        Set c = ##class(Interlock.Store.Chain).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Do out.%Push(c.ToObject())
    }
    Quit out
}

/// The chain objects in order (not projected).
Method ChainList() As %ListOfObjects
{
    Set out = ##class(%ListOfObjects).%New()
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.Chain WHERE Incident = ? ORDER BY Seq", ..%Id())
    While rs.%Next() {
        Set c = ##class(Interlock.Store.Chain).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Do out.Insert(c)
    }
    Quit out
}

/// The chain at a sequence number, or "".
Method ChainAt(seq As %Integer) As Interlock.Store.Chain
{
    Set iid = ..%Id(), rid = ""
    &sql(SELECT ID INTO :rid FROM Interlock_Store.Chain WHERE Incident = :iid AND Seq = :seq)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ##class(Interlock.Store.Chain).%OpenId(rid)
}

/// How many cases the incident holds.
Method CaseCount() As %Integer
{
    Set iid = ..%Id(), n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Interlock_Store."Case" WHERE Incident = :iid)
    Quit +n
}

/// Counts of chains by kind and by state, and of cases.
Method Progress() As %DynamicObject
{
    Set o = {}, byKind = {}, byState = {}, n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Kind, State FROM Interlock_Store.Chain WHERE Incident = ?", ..%Id())
    While rs.%Next() {
        Set n = n + 1
        Set k = $SELECT(rs.%Get("Kind") = "": "unclassified", 1: rs.%Get("Kind")), st = rs.%Get("State")
        Do byKind.%Set(k, byKind.%Get(k) + 1), byState.%Set(st, byState.%Get(st) + 1)
    }
    Set o.chains = n, o.cases = ..CaseCount(), o.byKind = byKind, o.byState = byState
    Quit o
}

/// The approvals given: the incident's own and each chain's.
Method Approvals() As %DynamicArray
{
    Set out = []
    If ..ApprovalDecision '= "" {
        Do out.%Push({"scope": "incident", "by": (..ApprovedBy), "at": (..ApprovedAt), "decision": (..ApprovalDecision), "comment": (..ApprovalComment), "taskId": (..ApprovalTaskId), "planDigest": (..PlanDigest)})
    }
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.Chain WHERE Incident = ? AND ApprovalDecision IS NOT NULL ORDER BY Seq", ..%Id())
    While rs.%Next() {
        Set c = ##class(Interlock.Store.Chain).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Do out.%Push({"scope": "chain", "seq": (c.Seq), "by": (c.ApprovedBy), "at": (c.ApprovedAt), "decision": (c.ApprovalDecision), "comment": (c.ApprovalComment), "taskId": (c.ApprovalTaskId), "planDigest": (..PlanDigest)})
    }
    Quit out
}

/// Close an incident whose workflow is gone (it died, or the production was reset): the chains still open are
/// stopped and the cases it holds are failed with the reason, so nothing waits forever.
Method Abandon(why As %String, actor As %String = "operator") As %Status
{
    Set sc = $$$OK
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.Chain WHERE Incident = ? AND State IN ('pending', 'awaiting_approval', 'approved', 'releasing')", ..%Id())
    While rs.%Next() {
        Set ch = ##class(Interlock.Store.Chain).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(ch)
        Set ch.State = "stopped", ch.Outcome = "Abandoned: " _ why
        Set sc = ch.%Save()
        Quit:$$$ISERR(sc)
    }
    Quit:$$$ISERR(sc) sc
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.""Case"" WHERE Incident = ? AND State NOT IN ('resolved', 'blocked', 'escalated', 'failed')", ..%Id())
    While rs.%Next() {
        Set c = ##class(Interlock.Store.Case).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Set c.Headline = "Abandoned with incident " _ ..IncidentId _ ": " _ why
        Set sc = c.Transition("failed", "Abandoned with incident " _ ..IncidentId _ ": " _ why, actor, "incident:" _ ..IncidentId)
        Quit:$$$ISERR(sc)
    }
    Quit:$$$ISERR(sc) sc
    Set ..Summary = "Abandoned: " _ why
    Quit ..Transition("closed", "Abandoned by " _ actor _ ": " _ why, actor)
}

/// Abandon an incident by its public id (for the terminal and SQL); returns the status text.
ClassMethod AbandonById(id As %String, why As %String, actor As %String = "operator") As %String [ SqlProc ]
{
    Set inc = ..ByIncidentId(id)
    If '$ISOBJECT(inc) Quit "no incident " _ id
    If inc.State = "closed" Quit id _ " is already closed"
    Set sc = inc.Abandon(why, actor)
    Quit $SELECT($$$ISOK(sc): id _ " closed", 1: $SYSTEM.Status.GetErrorText(sc))
}

Method Events() As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.IncidentEvent WHERE Incident = ? ORDER BY Seq", ..%Id())
    While rs.%Next() {
        Set e = ##class(Interlock.Store.IncidentEvent).%OpenId(rs.%Get("ID"))
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
<DataLocation>^Interlock.Store.IncidentD</DataLocation>
<DefaultData>IncidentDefaultData</DefaultData>
<IdLocation>^Interlock.Store.IncidentD</IdLocation>
<IndexLocation>^Interlock.Store.IncidentI</IndexLocation>
<StreamLocation>^Interlock.Store.IncidentS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
