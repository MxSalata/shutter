/// Many failures to one receiver, grouped (CONTRACTS 7): the incident opens at the site's threshold, adopts the
/// burst's cases, forms chains per encounter, and releases them in order through each case's own dispatch.
Class Interlock.Store.Incident Extends (%Persistent, %JSON.Adaptor)
{

/// I-nnnnnn
Property IncidentId As %String(%JSONFIELDNAME = "incidentId", MAXLEN = 32) [ Required ];

Index IncidentIdx On IncidentId [ Unique ];

/// The production item the failures went to.
Property Receiver As %String(%JSONFIELDNAME = "receiver", MAXLEN = 128);

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

Property PlanJSON As %String(%JSONFIELDNAME = "plan", MAXLEN = "");

Property ReceiverEpoch As %Integer(%JSONFIELDNAME = "receiverEpoch");

/// The policy the site applied to the incident's policy chains: automatic, approval or per_chain.
Property Policy As %String(%JSONFIELDNAME = "policy", MAXLEN = 16);

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

/// The open incident for a receiver (still taking cases), or "".
ClassMethod OpenFor(receiver As %String) As Interlock.Store.Incident
{
    Set rid = ""
    &sql(SELECT TOP 1 ID INTO :rid FROM Interlock_Store.Incident WHERE Receiver = :receiver AND State = 'open' ORDER BY ID DESC)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ..%OpenId(rid)
}

/// Open an incident for a receiver with the site's settings.
ClassMethod Open(receiver As %String, Output incident As Interlock.Store.Incident) As %Status
{
    Set incident = ..%New()
    Set incident.IncidentId = "I-" _ $TRANSLATE($JUSTIFY($INCREMENT(^Interlock.Counter("incident")), 6), " ", "0")
    Set incident.Receiver = receiver, incident.State = "open"
    Set incident.OpenedAt = ##class(Interlock.Util.Time).NowUTC(), incident.LastFailureAt = incident.OpenedAt
    Set incident.Threshold = ##class(Interlock.Store.SiteProfile).IncidentSetting("threshold", 5)
    Set incident.WindowMinutes = ##class(Interlock.Store.SiteProfile).IncidentSetting("window_minutes", 10)
    Set incident.QuietSeconds = ##class(Interlock.Store.SiteProfile).IncidentSetting("quiet_seconds", 60)
    Set sc = incident.%Save()
    Quit:$$$ISERR(sc) sc
    Quit incident.Note("state", "Incident opened for " _ receiver _ ": " _ incident.Threshold _ " failures within " _ incident.WindowMinutes _ " minutes", "system")
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

}
