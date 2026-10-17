/// Detection and grouping (CONTRACTS 7.1): counts the failures to a receiver within the site's window, opens an
/// incident at the threshold, and makes the burst's cases join it. Called by the case workflow when a case opens.
Class Interlock.Store.IncidentDetector
{

/// Register a newly opened case for its receiver. Returns the incident the case joined, or "".
/// Uncertain outcomes keep their own cases: only delivery failures and refusals count.
ClassMethod Register(case As Interlock.Store.Case, receiver As %String, Output incident As Interlock.Store.Incident) As %Status
{
    Set incident = "", sc = $$$OK
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
    // The burst's cases: opened within the window, failed or rejected, not yet past their proposal gate.
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Interlock_Store."Case" WHERE OpenedAt >= :since AND FailureKind IN ('delivery_failed', 'rejected') AND State IN ('detected', 'collecting', 'investigating', 'proposed'))
    If +n < threshold Quit sc
    Set sc = ##class(Interlock.Store.Incident).Open(receiver, .incident)
    Quit:$$$ISERR(sc) sc
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Interlock_Store.""Case"" WHERE OpenedAt >= ? AND FailureKind IN ('delivery_failed', 'rejected') AND State IN ('detected', 'collecting', 'investigating', 'proposed') ORDER BY ID", since)
    While rs.%Next() {
        Set c = ##class(Interlock.Store.Case).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        Set sc = ..Join(c, incident)
        Quit:$$$ISERR(sc)
    }
    Quit sc
}

/// A case joins an incident: recorded on the case, noted on both.
ClassMethod Join(case As Interlock.Store.Case, incident As Interlock.Store.Incident) As %Status
{
    If $ISOBJECT(case.Incident) && (case.Incident.%Id() = incident.%Id()) Quit $$$OK
    Set case.Incident = incident
    Set sc = case.%Save()
    Quit:$$$ISERR(sc) sc
    Set sc = case.Note("note", "Joined incident " _ incident.IncidentId _ " (" _ incident.Receiver _ "): the incident decides when this case is released", "system", "incident:" _ incident.%Id())
    Quit:$$$ISERR(sc) sc
    Quit incident.Note("note", "Case " _ case.CaseId _ " joined: " _ case.Event _ " for " _ case.EncounterId _ " at " _ case.EventTime, "system")
}

/// Whether the incident's intake can close: the quiet period has passed since the last failure.
ClassMethod QuietFor(incident As Interlock.Store.Incident) As %Boolean
{
    Set quiet = incident.QuietSeconds
    If quiet <= 0 Quit 1
    Quit ##class(Interlock.Util.Time).SecondsBetween(incident.LastFailureAt, ##class(Interlock.Util.Time).NowUTC()) >= quiet
}

/// Group the incident's cases into chains per encounter, oldest event first, and classify each chain
/// (CONTRACTS 7.1 and 7.2). Replaces earlier chains. Returns the chains.
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
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, EncounterId FROM Interlock_Store.""Case"" WHERE Incident = ? ORDER BY EncounterId, EventTime, ID", incident.%Id())
    Set seq = 0, last = "", chain = ""
    While rs.%Next() {
        Set c = ##class(Interlock.Store.Case).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        If c.EncounterId '= last {
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

/// The chain's kind and who decides it, from its items. A single item is single; several with no successful
/// delivery for the encounter between them are ordered; otherwise interleaved. Policy when every item's match
/// decides by policy; person when any item asks for a person; else board.
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
    If n <= 1 {
        Set chain.Kind = "single"
    } ElseIf ..SuccessBetween(chain) {
        Set chain.Kind = "interleaved"
    } Else {
        Set chain.Kind = "ordered"
    }
    // Interleaved chains are the board's whatever the entries say (7.2).
    If (chain.Kind = "interleaved") && (decides = "policy") Set decides = "board"
    Set chain.Entries = entries, chain.Decides = decides
    If $ISOBJECT(first) {
        Set c = ##class(Interlock.Store.Case).ByCaseId(##class(Interlock.Util.Json).Str(first, "caseId"))
        Set chain.FirstExpectedVersion = ..VersionOf(c)
    }
    Quit chain.%Save()
}

/// Whether a successful delivery for the encounter sits between the chain's failures (from the first item's
/// snapshot timeline, which lists every operation sent for the encounter with its outcome).
ClassMethod SuccessBetween(chain As Interlock.Store.Chain) As %Boolean [ Private ]
{
    Set items = chain.Items()
    If items.%Size() < 2 Quit 0
    Set firstAt = ##class(Interlock.Util.Json).Str(items.%Get(0), "eventTime"), lastAt = ##class(Interlock.Util.Json).Str(items.%Get(items.%Size() - 1), "eventTime")
    Set c = ##class(Interlock.Store.Case).ByCaseId(##class(Interlock.Util.Json).Str(items.%Get(0), "caseId"))
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

}
