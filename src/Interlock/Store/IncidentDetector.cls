/// Detection and grouping (CONTRACTS 7.1): counts the failures to a receiver within the site's window, opens an
/// incident at the threshold, and makes the burst's cases join it. Called by the case workflow when a case opens.
Class Interlock.Store.IncidentDetector
{

/// Register a newly opened case for its receiver. Returns the incident the case joined, or "", and whether
/// this registration opened it. Uncertain outcomes keep their own cases: only delivery failures and refusals count.
ClassMethod Register(case As Interlock.Store.Case, receiver As %String, Output incident As Interlock.Store.Incident, Output openedNow As %Boolean) As %Status
{
    Set incident = "", openedNow = 0, sc = $$$OK
    If (case.FailureKind '= "delivery_failed") && (case.FailureKind '= "rejected") Quit sc
    Set incident = ##class(Interlock.Store.Incident).OpenFor(receiver)
    If $ISOBJECT(incident) {
        Set incident.LastFailureAt = ##class(Interlock.Util.Time).NowUTC()
        Set sc = incident.%Save()
        Quit:$$$ISERR(sc) sc
        Quit ..Join(case, incident)
    }
    Set threshold = ##class(Interlock.Store.SiteProfile).IncidentSetting("threshold", 5)
    Set window = ##class(Interlock.Store.SiteProfile).IncidentSetting("window_minutes", 10)
    Set since = ##class(Interlock.Util.Time).FromNow(-60 * window)
    // The failures to this receiver within the window that no incident holds yet.
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Interlock_Store."Case" WHERE Receiver = :receiver AND OpenedAt >= :since AND FailureKind IN ('delivery_failed', 'rejected') AND Incident IS NULL)
    If +n < threshold Quit sc
    Set sc = ##class(Interlock.Store.Incident).Open(receiver, case.Mode, .incident)
    Quit:$$$ISERR(sc) sc
    Set openedNow = 1
    // The burst's earlier cases still before their proposal gate join too (settling, collecting or investigating);
    // a case already past its board keeps its own path.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.""Case"" WHERE Receiver = ? AND OpenedAt >= ? AND FailureKind IN ('delivery_failed', 'rejected') AND Incident IS NULL AND State IN ('detected', 'collecting', 'investigating') ORDER BY ID", receiver, since)
    While rs.%Next() {
        Set c = $SELECT(rs.%Get("ID") = case.%Id(): case, 1: ##class(Interlock.Store.Case).%OpenId(rs.%Get("ID")))
        Continue:'$ISOBJECT(c)
        Set sc = ..Join(c, incident)
        Quit:$$$ISERR(sc)
    }
    Quit:$$$ISERR(sc) sc
    // The opening case joins whatever its state.
    Quit ..Join(case, incident)
}

/// A case joins an incident: recorded on the case, noted on both.
ClassMethod Join(case As Interlock.Store.Case, incident As Interlock.Store.Incident) As %Status
{
    If $ISOBJECT(case.Incident) && (case.Incident.%Id() = incident.%Id()) Quit $$$OK
    Set case.Incident = incident
    Set sc = case.%Save()
    Quit:$$$ISERR(sc) sc
    Set sc = case.Note("note", "Joined incident " _ incident.IncidentId _ " (" _ incident.Receiver _ "): the incident decides when this case is released", "system", "incident:" _ incident.IncidentId)
    Quit:$$$ISERR(sc) sc
    Quit incident.Note("note", "Case " _ case.CaseId _ " joined: " _ case.Event _ " for " _ case.EncounterId _ " at " _ case.EventTime _ " (" _ case.FailureKind _ ")", "system")
}

/// A case leaves an incident (it was not ready when the chains formed): it continues alone.
ClassMethod Leave(case As Interlock.Store.Case, incident As Interlock.Store.Incident, why As %String) As %Status
{
    Set case.Incident = ""
    Set sc = case.%Save()
    Quit:$$$ISERR(sc) sc
    Set sc = case.Note("note", "Left incident " _ incident.IncidentId _ ": " _ why _ ". The case continues on its own", "system", "incident:" _ incident.IncidentId)
    Quit:$$$ISERR(sc) sc
    Quit incident.Note("note", "Case " _ case.CaseId _ " left: " _ why, "system")
}

/// Whether the incident's intake can close: the quiet period has passed since the last failure.
ClassMethod QuietFor(incident As Interlock.Store.Incident) As %Boolean
{
    Set quiet = incident.QuietSeconds
    If quiet <= 0 Quit 1
    Quit ##class(Interlock.Util.Time).SecondsBetween(incident.LastFailureAt, ##class(Interlock.Util.Time).NowUTC()) >= quiet
}

/// Cases of the incident not yet parked (grouped) or closed: their evidence and match are not there yet.
ClassMethod NotReady(incident As Interlock.Store.Incident) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT CaseId FROM Interlock_Store.""Case"" WHERE Incident = ? AND State NOT IN ('grouped', 'resolved', 'blocked', 'escalated', 'failed') ORDER BY ID", incident.%Id())
    While rs.%Next() { Do out.%Push(rs.%Get("CaseId")) }
    Quit out
}

/// Group the incident's cases into chains per encounter, oldest event first, and classify each chain
/// (CONTRACTS 7.1 and 7.2). Replaces earlier chains. Closed cases (resolved or escalated before the incident
/// formed its chains) are left out.
ClassMethod Group(incident As Interlock.Store.Incident) As %Status
{
    Set sc = $$$OK
    // Clear earlier chains and items.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.Chain WHERE Incident = ?", incident.%Id())
    While rs.%Next() {
        Set cid = rs.%Get("ID")
        Set rs2 = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.ChainItem WHERE Chain = ?", cid)
        While rs2.%Next() { Do ##class(Interlock.Store.ChainItem).%DeleteId(rs2.%Get("ID")) }
        Do ##class(Interlock.Store.Chain).%DeleteId(cid)
    }
    // The cases, by encounter, in event order.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, EncounterId FROM Interlock_Store.""Case"" WHERE Incident = ? AND State = 'grouped' ORDER BY EncounterId, EventTime, ID", incident.%Id())
    Set seq = 0, last = "", chain = "", position = 0
    While rs.%Next() {
        Set c = ##class(Interlock.Store.Case).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        If (c.EncounterId '= last) || '$ISOBJECT(chain) {
            If $ISOBJECT(chain) Set sc = ..Classify(chain) Quit:$$$ISERR(sc)
            Set seq = seq + 1
            Set chain = ##class(Interlock.Store.Chain).%New()
            Set chain.Incident = incident, chain.Seq = seq, chain.EncounterId = c.EncounterId
            Set chain.PatientId = c.PatientId, chain.PatientIdAuthority = c.PatientIdAuthority
            Set sc = chain.%Save()
            Quit:$$$ISERR(sc)
            Set last = c.EncounterId, position = 0
        }
        Set position = position + 1
        Set item = ##class(Interlock.Store.ChainItem).%New()
        Set item.Chain = chain, item.Position = position, item.Case = c
        Set cat = ..CatalogueOf(c)
        If $ISOBJECT(cat) {
            Set item.Entry = ##class(Interlock.Util.Json).Str(cat, "entry"), item.CatalogueOutcome = ##class(Interlock.Util.Json).Str(cat, "outcome")
            Set item.Decides = ##class(Interlock.Util.Json).Str(cat, "decision")
        }
        Set sc = item.%Save()
        Quit:$$$ISERR(sc)
    }
    Quit:$$$ISERR(sc) sc
    If $ISOBJECT(chain) Set sc = ..Classify(chain)
    Quit sc
}

/// The chain's kind, who decides it and the site's policy for it, from its items. A single item is single;
/// several with no successful delivery for the encounter between them are ordered; otherwise interleaved.
/// Policy when the incident runs in policy mode and every item's match decides by policy (never for an
/// interleaved chain); person when any item asks for a person; else board (the cases run their own path).
ClassMethod Classify(chain As Interlock.Store.Chain) As %Status
{
    Set items = chain.Items()
    Set n = items.%Size()
    Set entries = "", decides = "policy", first = ""
    Set iter = items.%GetIterator()
    While iter.%GetNext(.i, .it) {
        Set entries = entries _ $SELECT(entries = "": "", 1: ",") _ ##class(Interlock.Util.Json).Str(it, "entry", "?")
        Set d = ##class(Interlock.Util.Json).Str(it, "decides")
        If d = "person" Set decides = "person"
        If (d '= "policy") && (decides '= "person") Set decides = "board"
        If first = "" Set first = it
    }
    Set mode = $SELECT($ISOBJECT(chain.Incident): chain.Incident.Mode, 1: "board")
    // Outside policy mode the cases run their own path, whatever the catalogue says (6.3).
    If mode '= "policy" Set decides = "board"
    If n <= 1 {
        Set chain.Kind = "single"
    } ElseIf ..SuccessBetween(chain) {
        Set chain.Kind = "interleaved"
    } Else {
        Set chain.Kind = "ordered"
    }
    // Interleaved chains are the board's whatever the entries say (7.2).
    If (chain.Kind = "interleaved") && (decides = "policy") Set decides = "board"
    Set chain.Policy = "path"
    If decides = "policy" {
        Set tier = ##class(Interlock.Store.SiteProfile).TierOf(chain.Incident.Receiver)
        Set policy = ##class(Interlock.Store.SiteProfile).Policy(tier, chain.Kind)
        If policy = "board" { Set decides = "board" } Else { Set chain.Policy = policy }
    }
    Set chain.Entries = entries, chain.Decides = decides
    If $ISOBJECT(first) {
        Set c = ##class(Interlock.Store.Case).ByCaseId(##class(Interlock.Util.Json).Str(first, "caseId"))
        Set chain.FirstExpectedVersion = ..VersionOf(c)
    }
    Quit chain.%Save()
}

/// Whether a successful delivery for the encounter sits between the chain's failures (from the last item's
/// snapshot timeline, which lists every operation sent for the encounter with its outcome).
ClassMethod SuccessBetween(chain As Interlock.Store.Chain) As %Boolean [ Private ]
{
    Set items = chain.Items()
    If items.%Size() < 2 Quit 0
    Set firstAt = ##class(Interlock.Util.Json).Str(items.%Get(0), "eventTime"), lastAt = ##class(Interlock.Util.Json).Str(items.%Get(items.%Size() - 1), "eventTime")
    Set c = ##class(Interlock.Store.Case).ByCaseId(##class(Interlock.Util.Json).Str(items.%Get(items.%Size() - 1), "caseId"))
    If '$ISOBJECT(c) || '$ISOBJECT(c.CurrentSnapshot) Quit 0
    Set timeline = c.CurrentSnapshot.SummaryObject().%Get("timeline")
    If '$ISOBJECT(timeline) Quit 0
    Set iter = timeline.%GetIterator()
    While iter.%GetNext(.i, .ev) {
        Set outcome = ##class(Interlock.Util.Json).Str(ev, "outcome")
        Continue:((outcome '= "applied") && (outcome '= "already_committed"))
        Set t = ##class(Interlock.Util.Json).Str(ev, "event_time")
        If (t ]] firstAt) && (lastAt ]] t) Return 1
    }
    Quit 0
}

/// The matcher's result stored in the case's snapshot, or "".
ClassMethod CatalogueOf(case As Interlock.Store.Case) As %DynamicObject
{
    If '$ISOBJECT(case.CurrentSnapshot) Quit ""
    Set summary = case.CurrentSnapshot.SummaryObject()
    If '$ISOBJECT(summary) Quit ""
    Quit summary.%Get("catalogue")
}

/// The receiver's version in the case's snapshot, or "".
ClassMethod VersionOf(case As Interlock.Store.Case) As %String
{
    If '$ISOBJECT(case) || '$ISOBJECT(case.CurrentSnapshot) Quit ""
    Set ward = case.CurrentSnapshot.SummaryObject().%Get("ward_state")
    If '$ISOBJECT(ward) Quit ""
    Quit ##class(Interlock.Util.Json).Str(ward, "version")
}

/// The receiver's epoch in the case's snapshot, or "".
ClassMethod EpochOf(case As Interlock.Store.Case) As %String
{
    If '$ISOBJECT(case) || '$ISOBJECT(case.CurrentSnapshot) Quit ""
    Quit ##class(Interlock.Util.Json).Str(case.CurrentSnapshot.SummaryObject(), "epoch")
}

}
