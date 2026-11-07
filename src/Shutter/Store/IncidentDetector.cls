/// Detection and grouping (CONTRACTS 7.1): counts the failures to a receiver within the site's window, opens an
/// incident at the threshold, and makes the burst's cases join it. Called by the case workflow when a case opens.
Class Shutter.Store.IncidentDetector
{

/// Register a newly opened case for its receiver. Returns the incident the case joined, or "", and whether
/// this registration opened it. Uncertain outcomes keep their own cases: only delivery failures and refusals count.
ClassMethod Register(case As Shutter.Store.Case, receiver As %String, Output incident As Shutter.Store.Incident, Output openedNow As %Boolean) As %Status
{
    Set incident = "", openedNow = 0, sc = $$$OK
    If (case.FailureKind '= "delivery_failed") && (case.FailureKind '= "rejected") Quit sc
    Set incident = ##class(Shutter.Store.Incident).OpenFor(receiver)
    If $ISOBJECT(incident) {
        Set incident.LastFailureAt = ##class(Shutter.Util.Time).NowUTC()
        Set sc = incident.%Save()
        Quit:$$$ISERR(sc) sc
        Quit ..Join(case, incident)
    }
    Set threshold = ##class(Shutter.Store.SiteProfile).IncidentSetting("threshold", 5)
    Set window = ##class(Shutter.Store.SiteProfile).IncidentSetting("window_minutes", 10)
    Set since = ..Since(window)
    // The failures to this receiver within the window that no incident holds yet.
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store."Case" WHERE Receiver = :receiver AND OpenedAt >= :since AND FailureKind IN ('delivery_failed', 'rejected') AND Incident IS NULL)
    If +n < threshold Quit sc
    Set sc = ##class(Shutter.Store.Incident).Open(receiver, case.Mode, .incident)
    Quit:$$$ISERR(sc) sc
    Set openedNow = 1
    // The burst's earlier cases still before their proposal gate join too (settling, collecting or investigating);
    // a case already past its board keeps its own path.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.""Case"" WHERE Receiver = ? AND OpenedAt >= ? AND FailureKind IN ('delivery_failed', 'rejected') AND Incident IS NULL AND State IN ('detected', 'collecting', 'investigating') ORDER BY ID", receiver, since)
    While rs.%Next() {
        Set c = $SELECT(rs.%Get("ID") = case.%Id(): case, 1: ##class(Shutter.Store.Case).%OpenId(rs.%Get("ID")))
        Continue:'$ISOBJECT(c)
        Set sc = ..Join(c, incident)
        Quit:$$$ISERR(sc)
    }
    Quit:$$$ISERR(sc) sc
    // The opening case joins whatever its state.
    Quit ..Join(case, incident)
}

/// The start of the counting window: the later of the window's start and the last scenario reset, so a demo run never
/// counts the failures of the scenarios before it (a site without resets keeps the plain window).
ClassMethod Since(windowMinutes As %Integer) As %String
{
    Set since = ##class(Shutter.Util.Time).FromNow(-60 * windowMinutes)
    Set resetAt = $GET(^Shutter.Config("resetAt"))
    If (resetAt '= "") && (resetAt ]] since) Set since = resetAt
    Quit since
}

/// A case joins an incident: recorded on the case (the membership alone, so the case's own workflow and evidence keep
/// what they wrote meanwhile), noted on both.
ClassMethod Join(case As Shutter.Store.Case, incident As Shutter.Store.Incident) As %Status
{
    If $ISOBJECT(case.Incident) && (case.Incident.%Id() = incident.%Id()) Quit $$$OK
    Set sc = case.SetIncident(incident)
    Quit:$$$ISERR(sc) sc
    Set sc = case.Note("note", "Joined incident " _ incident.IncidentId _ " (" _ incident.Receiver _ "): the incident decides when this case is released", "system", "incident:" _ incident.IncidentId)
    Quit:$$$ISERR(sc) sc
    Quit incident.Note("note", "Case " _ case.CaseId _ " joined: " _ case.Event _ " for " _ case.EncounterId _ " at " _ case.EventTime _ " (" _ case.FailureKind _ ")", "system")
}

/// A case leaves an incident (it was not ready when the chains formed): it continues alone.
ClassMethod Leave(case As Shutter.Store.Case, incident As Shutter.Store.Incident, why As %String) As %Status
{
    // A case that parked meanwhile is ready after all, and stays: its stored state is read under the case's lock, which
    // the workflow's parking takes too (Shutter.Process.CaseWorkflow.Park).
    Set sc = case.SetIncident("", "grouped", .left)
    Quit:$$$ISERR(sc) sc
    If 'left Quit $$$OK
    Set sc = case.Note("note", "Left incident " _ incident.IncidentId _ ": " _ why _ ". The case continues on its own", "system", "incident:" _ incident.IncidentId)
    Quit:$$$ISERR(sc) sc
    Quit incident.Note("note", "Case " _ case.CaseId _ " left: " _ why, "system")
}

/// Whether the incident's intake can close: the quiet period has passed since the last failure.
ClassMethod QuietFor(incident As Shutter.Store.Incident) As %Boolean
{
    Set quiet = incident.QuietSeconds
    If quiet <= 0 Quit 1
    Quit ##class(Shutter.Util.Time).SecondsBetween(incident.LastFailureAt, ##class(Shutter.Util.Time).NowUTC()) >= quiet
}

/// Cases of the incident not yet parked (grouped) or closed: their evidence and match are not there yet.
ClassMethod NotReady(incident As Shutter.Store.Incident) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT CaseId FROM Shutter_Store.""Case"" WHERE Incident = ? AND State NOT IN ('grouped', 'resolved', 'blocked', 'escalated', 'failed') ORDER BY ID", incident.%Id())
    While rs.%Next() { Do out.%Push(rs.%Get("CaseId")) }
    Quit out
}

/// Group the incident's cases into chains per encounter, oldest event first, and classify each chain
/// (CONTRACTS 7.1 and 7.2). Replaces earlier chains. Closed cases (resolved or escalated before the incident
/// formed its chains) are left out.
ClassMethod Group(incident As Shutter.Store.Incident) As %Status
{
    Set sc = $$$OK
    // Clear earlier chains and items.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.Chain WHERE Incident = ?", incident.%Id())
    While rs.%Next() {
        Set cid = rs.%Get("ID")
        Set rs2 = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.ChainItem WHERE Chain = ?", cid)
        While rs2.%Next() { Do ##class(Shutter.Store.ChainItem).%DeleteId(rs2.%Get("ID")) }
        Do ##class(Shutter.Store.Chain).%DeleteId(cid)
    }
    // The cases, by encounter, in event order.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, EncounterId FROM Shutter_Store.""Case"" WHERE Incident = ? AND State = 'grouped' ORDER BY EncounterId, EventTime, ID", incident.%Id())
    Set seq = 0, last = "", chain = "", position = 0
    While rs.%Next() {
        Set c = ##class(Shutter.Store.Case).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(c)
        If (c.EncounterId '= last) || '$ISOBJECT(chain) {
            If $ISOBJECT(chain) Set sc = ..Classify(chain) Quit:$$$ISERR(sc)
            Set seq = seq + 1
            Set chain = ##class(Shutter.Store.Chain).%New()
            Set chain.Incident = incident, chain.Seq = seq, chain.EncounterId = c.EncounterId
            Set chain.PatientId = c.PatientId, chain.PatientIdAuthority = c.PatientIdAuthority
            Set sc = chain.%Save()
            Quit:$$$ISERR(sc)
            Set last = c.EncounterId, position = 0
        }
        Set position = position + 1
        Set item = ##class(Shutter.Store.ChainItem).%New()
        Set item.Chain = chain, item.Position = position, item.Case = c
        Set cat = ..CatalogueOf(c)
        If $ISOBJECT(cat) {
            Set item.Entry = ##class(Shutter.Util.Json).Str(cat, "entry"), item.CatalogueOutcome = ##class(Shutter.Util.Json).Str(cat, "outcome")
            Set item.Decides = ##class(Shutter.Util.Json).Str(cat, "decision")
        }
        Set sc = item.%Save()
        Quit:$$$ISERR(sc)
    }
    Quit:$$$ISERR(sc) sc
    If $ISOBJECT(chain) Set sc = ..Classify(chain)
    Quit sc
}

/// The chain's kind, who decides it and the site's policy for it, from its items. A single item is single;
/// several with no successful delivery for the encounter between them are ordered; otherwise interleaved. With the
/// kind known, every item is matched again with the chain condition set (7.1), so an ordered chain's items can match
/// an entry written for chains, which the first evidence (chain single) could not. Policy when the incident runs in
/// policy mode and every item's match decides by policy (never for an interleaved chain); person when any item asks
/// for a person; else board (the cases run their own path).
ClassMethod Classify(chain As Shutter.Store.Chain) As %Status
{
    Set n = chain.ItemCount()
    If n <= 1 {
        Set chain.Kind = "single"
    } ElseIf ..SuccessBetween(chain) {
        Set chain.Kind = "interleaved"
    } Else {
        Set chain.Kind = "ordered"
    }
    Set entries = "", decides = "policy", firstCase = "", proj = "", projWard = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Store.ChainItem WHERE Chain = ? ORDER BY Position", chain.%Id())
    While rs.%Next() {
        Set it = ##class(Shutter.Store.ChainItem).%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(it)
        Set c = it.Case
        // In an ordered chain the earlier items go first, so a later item is matched against the state they leave
        // (a transfer behind a lost admission sees "admitted", not the receiver's 404), when that state is known.
        If (chain.Kind = "ordered") && (it.Position > 1) && (proj '= "") {
            Set cat = ..Rematch(c, chain.Kind, proj, projWard)
            Do chain.Incident.Note("note", "Chain " _ chain.Seq _ " item " _ it.Position _ " (" _ c.CaseId _ ") matched against the state the earlier items leave: " _ proj _ $SELECT(projWard '= "": " at " _ projWard, 1: ""), "system")
        } Else {
            Set cat = ..Rematch(c, chain.Kind)
        }
        If it.Position = 1 Set proj = ..StateOf(c)
        Set proj = $CASE(c.Event, "admit": "admitted", "transfer": $SELECT(proj = "": "", 1: "admitted"), "discharge": $SELECT(proj = "": "", 1: "discharged"), : proj)
        If (c.Event = "admit") || (c.Event = "transfer") Set projWard = c.Ward
        If $ISOBJECT(cat) {
            Set it.Entry = ##class(Shutter.Util.Json).Str(cat, "entry"), it.CatalogueOutcome = ##class(Shutter.Util.Json).Str(cat, "outcome")
            Set it.Decides = ##class(Shutter.Util.Json).Str(cat, "decision")
            Do it.%Save()
        }
        Set entries = entries _ $SELECT(entries = "": "", 1: ",") _ $SELECT(it.Entry = "": "?", 1: it.Entry)
        If it.Decides = "person" Set decides = "person"
        If (it.Decides '= "policy") && (decides '= "person") Set decides = "board"
        If firstCase = "" Set firstCase = c
    }
    Set mode = $SELECT($ISOBJECT(chain.Incident): chain.Incident.Mode, 1: "board")
    // Outside policy mode the cases run their own path, whatever the catalogue says (6.3).
    If mode '= "policy" Set decides = "board"
    // Interleaved chains are the board's whatever the entries say (7.2).
    If (chain.Kind = "interleaved") && (decides = "policy") Set decides = "board"
    Set chain.Policy = "path"
    If decides = "policy" {
        Set tier = ##class(Shutter.Store.SiteProfile).TierOf(chain.Incident.Receiver)
        Set policy = ##class(Shutter.Store.SiteProfile).Policy(tier, chain.Kind)
        If policy = "board" { Set decides = "board" } Else { Set chain.Policy = policy }
    }
    Set chain.Entries = ##class(Shutter.Process.IncidentTaskText).ClipEntries(entries), chain.Decides = decides
    If $ISOBJECT(firstCase) Set chain.FirstExpectedVersion = ..VersionOf(firstCase)
    Quit chain.%Save()
}

/// The case's snapshot matched again with the chain condition set, and, when a projected state is given, with the
/// receiver's state replaced by the one the chain's earlier items leave; the snapshot's own match when the matcher fails.
ClassMethod Rematch(case As Shutter.Store.Case, chainKind As %String, projectedState As %String = "", projectedWard As %String = "") As %DynamicObject
{
    If '$ISOBJECT(case) || '$ISOBJECT(case.CurrentSnapshot) Quit ""
    Set summary = case.CurrentSnapshot.SummaryObject()
    If '$ISOBJECT(summary) Quit ""
    If projectedState '= "" {
        Set summary = ##class(%DynamicObject).%FromJSON(summary.%ToJSON())
        Do summary.%Set("ward_state_http_status", 200, "number")
        // The receiver's history, version and epoch stay as read; only the state and the ward are the projected ones.
        Set old = summary.%Get("ward_state")
        Set ws = $SELECT($ISOBJECT(old): ##class(%DynamicObject).%FromJSON(old.%ToJSON()), 1: {})
        Set ws.state = projectedState, ws.ward = projectedWard, ws."patient_id" = case.PatientId, ws."patient_id_authority" = case.PatientIdAuthority
        Do ws.%Set("projected", 1, "boolean")
        Set summary."ward_state" = ws
    }
    Try {
        Set cat = ##class(Shutter.Catalogue.Matcher).Match(##class(Shutter.Catalogue.Matcher).Conditions(case, summary, chainKind), ##class(Shutter.Catalogue.Matcher).Facts(summary, case))
    } Catch ex {
        Set cat = summary.%Get("catalogue")
    }
    Quit cat
}

/// Whether a successful delivery for the encounter sits between the chain's failures (from the last item's
/// snapshot timeline, which lists every operation sent for the encounter with its outcome).
ClassMethod SuccessBetween(chain As Shutter.Store.Chain) As %Boolean [ Private ]
{
    Set items = chain.Items()
    If items.%Size() < 2 Quit 0
    Set firstAt = ##class(Shutter.Util.Json).Str(items.%Get(0), "eventTime"), lastAt = ##class(Shutter.Util.Json).Str(items.%Get(items.%Size() - 1), "eventTime")
    Set c = ##class(Shutter.Store.Case).ByCaseId(##class(Shutter.Util.Json).Str(items.%Get(items.%Size() - 1), "caseId"))
    If '$ISOBJECT(c) || '$ISOBJECT(c.CurrentSnapshot) Quit 0
    Set timeline = c.CurrentSnapshot.SummaryObject().%Get("timeline")
    If '$ISOBJECT(timeline) Quit 0
    Set iter = timeline.%GetIterator()
    While iter.%GetNext(.i, .ev) {
        Set outcome = ##class(Shutter.Util.Json).Str(ev, "outcome")
        Continue:((outcome '= "applied") && (outcome '= "already_committed"))
        Set t = ##class(Shutter.Util.Json).Str(ev, "event_time")
        If (t ]] firstAt) && (lastAt ]] t) Return 1
    }
    Quit 0
}

/// The matcher's result stored in the case's snapshot, or "".
ClassMethod CatalogueOf(case As Shutter.Store.Case) As %DynamicObject
{
    If '$ISOBJECT(case.CurrentSnapshot) Quit ""
    Set summary = case.CurrentSnapshot.SummaryObject()
    If '$ISOBJECT(summary) Quit ""
    Quit summary.%Get("catalogue")
}

/// The receiver's version in the case's snapshot, or "".
ClassMethod VersionOf(case As Shutter.Store.Case) As %String
{
    If '$ISOBJECT(case) || '$ISOBJECT(case.CurrentSnapshot) Quit ""
    Set ward = case.CurrentSnapshot.SummaryObject().%Get("ward_state")
    If '$ISOBJECT(ward) Quit ""
    Quit ##class(Shutter.Util.Json).Str(ward, "version")
}

/// The receiver's encounter state in the case's snapshot (admitted, discharged), or "" when it could not be read or
/// the receiver does not know the encounter.
ClassMethod StateOf(case As Shutter.Store.Case) As %String
{
    If '$ISOBJECT(case) || '$ISOBJECT(case.CurrentSnapshot) Quit ""
    Set summary = case.CurrentSnapshot.SummaryObject()
    If ##class(Shutter.Util.Json).Str(summary, "ward_state_http_status") '= 200 Quit ""
    Set ward = summary.%Get("ward_state")
    If '$ISOBJECT(ward) Quit ""
    Quit ##class(Shutter.Util.Json).Str(ward, "state")
}

/// The receiver's epoch in the case's snapshot, or "".
ClassMethod EpochOf(case As Shutter.Store.Case) As %String
{
    If '$ISOBJECT(case) || '$ISOBJECT(case.CurrentSnapshot) Quit ""
    Quit ##class(Shutter.Util.Json).Str(case.CurrentSnapshot.SummaryObject(), "epoch")
}

}
