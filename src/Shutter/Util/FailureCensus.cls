/// The failure coverage census (docs/CONTRACTS.md, section 19): on demand, off unless the site profile's failure_census.enabled is
/// true, it compares the deliveries a watched receiver's item failed, as the engine shows them, with Shutter's cases, and reports
/// which have a traceable case, which have none and which cannot be told. It reads the source and writes only its own report: it
/// never opens or closes a case and never sends anything. A cap hit or a purge makes it incomplete, and a source it cannot read
/// makes it unknown, never zero.
Class Shutter.Util.FailureCensus Extends %RegisteredObject
{

/// The CSV's header line.
Parameter CSVCOLUMNS = "record_type,run_id,receiver,source_namespace,target,delivery_header_id,session_id,origin_header_id,time_created,source_status,body_class,message_family,resend_of,link_quality,case_ids,eligibility,explanation";

/// What the report says it is, wherever it is shown.
Parameter STATEMENT = "This compares engine-visible delivery failures with Shutter cases. It does not detect a message the engine completed but the receiving application later lost.";

/// What the profile's failure_census block may hold, and its limits: name, least, most.
Parameter LIMITS = "max_window_hours,1,744;max_headers,1,1000000;retention_days,1,3650;settle_seconds,0,86400";

/// The census's settings in a profile (given, else the current one), every limit filled in. Off unless the profile says on.
ClassMethod Settings(profile As %DynamicObject = "") As %DynamicObject
{
    If '$ISOBJECT(profile) Set profile = ##class(Shutter.Store.SiteProfile).Current()
    Set block = profile.%Get("failure_census")
    Set s = {"max_window_hours": 24, "max_headers": 10000, "retention_days": 30, "settle_seconds": 120}
    Do s.%Set("enabled", 0, "boolean")
    If '$ISOBJECT(block) Quit s
    If block.%GetTypeOf("enabled") = "boolean" Do s.%Set("enabled", block.%Get("enabled"), "boolean")
    For k = "max_window_hours", "max_headers", "retention_days", "settle_seconds" {
        If block.%GetTypeOf(k) = "number" Do s.%Set(k, block.%Get(k), "number")
    }
    Quit s
}

/// What is wrong with a profile's failure_census block, or "" (Shutter.Store.SiteProfile.Validate).
ClassMethod ProfileProblem(profile As %DynamicObject) As %String
{
    If 'profile.%IsDefined("failure_census") Quit ""
    Set block = profile.%Get("failure_census")
    If '$ISOBJECT(block) || block.%IsA("%Library.DynamicArray") Quit "failure_census: must be an object"
    Set iter = block.%GetIterator()
    While iter.%GetNext(.k, .v) {
        If k = "enabled" {
            If block.%GetTypeOf(k) '= "boolean" Return "failure_census.enabled: must be true or false"
            Continue
        }
        Set found = 0
        For i = 1:1:$LENGTH(..#LIMITS, ";") {
            Set one = $PIECE(..#LIMITS, ";", i)
            If $PIECE(one, ",", 1) '= k Continue
            Set found = 1
            If (block.%GetTypeOf(k) '= "number") || (v '= (v \ 1)) || (v < $PIECE(one, ",", 2)) || (v > $PIECE(one, ",", 3)) Return "failure_census." _ k _ ": must be a whole number from " _ $PIECE(one, ",", 2) _ " to " _ $PIECE(one, ",", 3)
        }
        If 'found Return "failure_census." _ k _ ": unknown setting"
    }
    Quit ""
}

/// The receivers a census can run on: [{receiver, namespace, item}]. Only what onboarding registered, or a profile entry that
/// names its namespace and item; never Shutter's own namespace, whose feed has no source to compare.
ClassMethod Scopes() As %DynamicArray
{
    Set out = [], ns = ""
    For {
        Set ns = $ORDER(^Shutter.Config("onboard", ns)) Quit:ns=""
        Continue:ns=$NAMESPACE
        Set item = ""
        For {
            Set item = $ORDER(^Shutter.Config("onboard", ns, "receivers", item), 1, reported) Quit:item=""
            Set reported = $SELECT($GET(reported) = "": item, 1: reported)
            If '$DATA(seen(reported)) Set seen(reported) = "" Do out.%Push({"receiver": (reported), "namespace": (ns), "item": (item)})
        }
    }
    Set iter = ##class(Shutter.Store.SiteProfile).ReceiverNames().%GetIterator()
    While iter.%GetNext(.i, .name) {
        Continue:$DATA(seen(name))
        Set entry = ##class(Shutter.Store.SiteProfile).Receiver(name)
        Continue:'$ISOBJECT(entry)
        Set ns = ##class(Shutter.Util.Json).Str(entry, "namespace"), item = ##class(Shutter.Util.Json).Str(entry, "item")
        Continue:(ns="")||(item="")||($ZCONVERT(ns, "U")=$NAMESPACE)
        Do out.%Push({"receiver": (name), "namespace": (ns), "item": (item)})
    }
    Quit out
}

/// Whether a receiver is registered, with its namespace and item.
ClassMethod ScopeOf(receiver As %String, Output ns As %String, Output item As %String) As %Boolean
{
    Set ns = "", item = ""
    Set iter = ..Scopes().%GetIterator()
    While iter.%GetNext(.i, .s) {
        If s.receiver = receiver Set ns = s.namespace, item = s.item Return 1
    }
    Quit 0
}

/// What is wrong with a window, or "": whole ISO UTC times, in order, inside the limit, and over by now.
ClassMethod WindowProblem(from As %String, to As %String, settings As %DynamicObject) As %String
{
    Set form = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z$"
    If '$MATCH(from, form) Quit "from must be an ISO UTC time, as 2026-11-06T09:00:00Z"
    If '$MATCH(to, form) Quit "to must be an ISO UTC time, as 2026-11-06T09:00:00Z"
    Set seconds = ##class(Shutter.Util.Time).SecondsBetween(from, to)
    If seconds = "" Quit "from and to must be real dates and times"
    If seconds <= 0 Quit "to must be after from"
    If seconds > (settings."max_window_hours" * 3600) Quit "The window may be at most " _ settings."max_window_hours" _ " hours"
    If ##class(Shutter.Util.Time).SecondsBetween(##class(Shutter.Util.Time).NowUTC(), to) > 60 Quit "to must not be in the future: a window still open has no final count"
    Quit ""
}

/// A run from the route: refused (with the words) when the census is off, the receiver is not registered or the window is bad;
/// otherwise a stored run, whatever it found.
ClassMethod Run(receiver As %String, from As %String, to As %String, user As %String, Output run As Shutter.Store.CensusRun, Output refused As %String) As %Status
{
    Set run = "", refused = ""
    Set settings = ..Settings()
    If 'settings.%Get("enabled") Set refused = "The census is off: the site profile's failure_census.enabled is not true" Quit $$$OK
    If '..ScopeOf(receiver, .ns, .item) Set refused = receiver _ " is not a registered receiver in a watched namespace" Quit $$$OK
    Set refused = ..WindowProblem(from, to, settings)
    If refused '= "" Quit $$$OK
    Do ##class(Shutter.Store.CensusRun).PurgeOlder(settings."retention_days")
    Quit ..RunScope(receiver, ns, item, from, to, user, settings, .run)
}

/// The run itself: Shutter's side, then the source, then the comparison, stored whatever it found.
ClassMethod RunScope(receiver As %String, ns As %String, item As %String, from As %String, to As %String, user As %String, settings As %DynamicObject, Output run As Shutter.Store.CensusRun) As %Status
{
    Set run = ##class(Shutter.Store.CensusRun).Begin(receiver, ns, item, from, to, user, settings."max_headers", .sc)
    If $$$ISERR(sc) Quit sc
    Try {
        Set cands = ..Candidates(ns, receiver, from, to, settings."max_headers", .capped)
        Kill seen
        Set ids = [], iter = cands.%GetIterator()
        While iter.%GetNext(.i, .c) {
            If '$DATA(seen(c.origin)) Set seen(c.origin) = "" Do ids.%Push(c.origin)
        }
        Set data = ##class(Shutter.Util.CensusReader).Read(ns, item, ..Odbc(from), ..Odbc(to), settings."max_headers", ids)
        Do data.%Set("candidatesCapped", capped, "boolean")
        Do data.%Set("ownMessagesPurged", ..OwnMessagesPurged(from), "boolean")
        Set run.CutoffUTC = ##class(Shutter.Util.Time).NowUTC()
        Set out = ..Compare(data, cands, settings, run.CutoffUTC)
        Set sc = ..Store(run, data, out, ns, item)
    } Catch ex {
        Set run.SourceError = $EXTRACT(ex.DisplayString(), 1, 400)
        Set run.ReasonsJson = ["census_failed"].%ToJSON()
        Set run.FinishedAt = ##class(Shutter.Util.Time).NowUTC()
        Set sc = run.%Save()
    }
    Quit sc
}

/// The cases Shutter holds for a receiver's failures since the window opened: [{origin, caseId, inWindow}], each header id
/// a forward named. From the case rows, and from the intake's own messages, since a further failure of an open case's operation
/// goes on that case and leaves its row naming only the first. capped says a cap stopped the read.
ClassMethod Candidates(ns As %String, receiver As %String, from As %String, to As %String, cap As %Integer, Output capped As %Boolean) As %DynamicArray
{
    Set out = [], capped = 0, n = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT CaseId, OriginHeaderId, OpenedAt, Receiver FROM Shutter_Store.""Case"" WHERE SourceNamespace = ? AND Receiver = ? AND OpenedAt >= ? ORDER BY ID", ns, receiver, from)
    If rs.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(rs.%SQLCODE, rs.%Message)
    While rs.%Next() {
        Continue:(rs.%Get("OriginHeaderId")="")||(rs.%Get("Receiver")'=receiver)
        If n >= cap Set capped = 1 Quit
        Set n = n + 1, opened = rs.%Get("OpenedAt")
        Set c = {"origin": (rs.%Get("OriginHeaderId")), "caseId": (rs.%Get("CaseId"))}
        Do c.%Set("inWindow", (opened ']] to), "boolean")
        Do out.%Push(c)
        Set seen(c.origin, c.caseId) = ""
    }
    If capped Quit out
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT MessageBodyId, SessionId, TimeCreated FROM Ens.MessageHeader WHERE MessageBodyClassName = 'Shutter.Msg.ExternalIntake' AND Type = 1 AND TimeCreated >= ? ORDER BY ID", ..Odbc(from))
    If rs.%SQLCODE < 0 Throw ##class(%Exception.SQL).CreateFromSQLCODE(rs.%SQLCODE, rs.%Message)
    While rs.%Next() {
        Set body = rs.%Get("MessageBodyId"), session = rs.%Get("SessionId"), when = rs.%Get("TimeCreated")
        Set row = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT SourceNamespace, Receiver, OriginHeaderId FROM Shutter_Msg.ExternalIntake WHERE ID = ?", body)
        Continue:'row.%Next()
        Set origin = row.%Get("OriginHeaderId")
        Continue:(origin="")||($ZCONVERT(row.%Get("SourceNamespace"), "U")'=$ZCONVERT(ns, "U"))||(row.%Get("Receiver")'=receiver)
        Set caseId = ..CaseOfIntakeSession(session)
        Continue:caseId=""||$DATA(seen(origin, caseId))
        If n >= cap Set capped = 1 Quit
        Set n = n + 1, seen(origin, caseId) = ""
        Set c = {"origin": (origin), "caseId": (caseId)}
        Do c.%Set("inWindow", (..Iso(when) ']] to), "boolean")
        Do out.%Push(c)
    }
    Quit out
}

/// The case the workflow answered in an intake's session, or "" when it answered none (Shutter refused the forward).
ClassMethod CaseOfIntakeSession(session As %String) As %String [ Private ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ? AND MessageBodyClassName = 'Shutter.Msg.CaseStarted' ORDER BY ID", session)
    While rs.%Next() {
        Set row = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT CaseId FROM Shutter_Msg.CaseStarted WHERE ID = ?", rs.%Get("MessageBodyId"))
        If row.%Next() && (row.%Get("CaseId") '= "") Return row.%Get("CaseId")
    }
    Quit ""
}

/// Whether Shutter's own message store no longer reaches back to the window's start, so a further failure's trail may be gone.
ClassMethod OwnMessagesPurged(from As %String) As %Boolean [ Private ]
{
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID, TimeCreated FROM Ens.MessageHeader ORDER BY ID")
    If 'rs.%Next() Quit 0
    Quit (rs.%Get("ID") > 1) && (rs.%Get("TimeCreated") ]] ..Odbc(from))
}

/// The delivery header a case's origin establishes. Today it is the origin itself: a forward that names the delivery's own header
/// is exact, and one that names the session's first header establishes only the session. This is the one place a delivery-header
/// resolver goes in, for a forward that names some other header of the delivery's session.
ClassMethod ResolvedDelivery(origin As %String, caseId As %String) As %String
{
    Quit origin
}

/// The link of a failed delivery to the cases: {quality, code, cases}. A case's origin is the delivery itself: exact. In its
/// session, and the session sent the target this one message: exact. In its session, and the session sent the target several:
/// ambiguous, and the candidates are named rather than one guessed. Anything else: none. A control id plays no part.
/// cands are the receiver's own, so a case at another receiver is never among them.
ClassMethod Link(delivery As %String, session As %String, toTarget As %Integer, cands As %DynamicArray, origins As %DynamicObject) As %DynamicObject
{
    Set own = [], same = []
    Set iter = cands.%GetIterator()
    While iter.%GetNext(.i, .c) {
        If ..ResolvedDelivery(c.origin, c.caseId) = delivery {
            Do own.%Push(c.caseId)
        } ElseIf (session '= "") && (origins.%Get(c.origin) = session) {
            Do same.%Push(c.caseId)
        }
    }
    If own.%Size() > 0 Quit {"quality": "exact", "code": "origin_is_this_delivery", "cases": (own)}
    If same.%Size() = 0 Quit {"quality": "none", "code": "no_case", "cases": []}
    If toTarget = 1 Quit {"quality": "exact", "code": "only_delivery_in_session", "cases": (same)}
    Quit {"quality": "ambiguous", "code": "several_deliveries_in_session", "cases": (same)}
}

/// The comparison, on plain data: {completeness, reasons, totals, items}. data is the reader's. now is the read's time, for a
/// failure too new to say it has no case; empty, nothing is that new. An unreadable source has no totals at all.
ClassMethod Compare(data As %DynamicObject, cands As %DynamicArray, settings As %DynamicObject, now As %String = "") As %DynamicObject
{
    Set out = {"completeness": "unknown", "reasons": [], "items": []}
    If 'data.%Get("readable") {
        Do out.reasons.%Push("source_unreadable")
        Do out.%Set("totals", "", "null")
        Quit out
    }
    Set exact = 0, none = 0, ambiguous = 0, excluded = 0, unknown = 0, failed = 0, bodies = 0, settling = 0, orphans = 0
    Set iter = data.failures.%GetIterator()
    While iter.%GetNext(.i, .f) {
        Set failed = failed + 1
        Set link = ..Link(f.id, f.session, f.toTarget, cands, data.origins)
        Set eligibility = "in_scope", code = link.code
        If 'f.%Get("hl7InSession") {
            Set eligibility = "excluded", code = "no_hl7_in_session", excluded = excluded + 1
        } ElseIf (link.quality = "none") && 'f.%Get("bodyPresent") {
            Set eligibility = "unknown", code = "body_missing", unknown = unknown + 1, bodies = bodies + 1
        } ElseIf (link.quality = "none") && (now '= "") && (settings."settle_seconds" > 0) && (##class(Shutter.Util.Time).SecondsBetween(..Iso(f.time), now) < settings."settle_seconds") {
            Set eligibility = "unknown", code = "settling", unknown = unknown + 1, settling = settling + 1
        } Else {
            If link.quality = "exact" Set exact = exact + 1
            If link.quality = "none" Set none = none + 1
            If link.quality = "ambiguous" Set ambiguous = ambiguous + 1
            Set caseIter = link.cases.%GetIterator()
            While caseIter.%GetNext(.j, .caseId) { Set distinct(caseId) = "" }
        }
        Do out.items.%Push({"deliveryHeaderId": (f.id), "sessionId": (f.session), "originHeaderId": "", "timeCreated": (f.time), "sourceStatus": (..StatusWord(f.status)), "bodyClass": (f.bodyClass), "family": (f.family), "resendOf": (f.resendOf), "caseIds": (..Joined(link.cases)), "linkQuality": (link.quality), "eligibility": (eligibility), "explanation": (code)})
    }
    // A case whose origin is gone: the evidence is, not the case.
    Set iter = cands.%GetIterator()
    While iter.%GetNext(.i, .c) {
        Continue:'c.%Get("inWindow")
        Continue:data.origins.%Get(c.origin)'=""
        Continue:$DATA(orphan(c.origin, c.caseId))
        Set orphan(c.origin, c.caseId) = "", orphans = orphans + 1
        Do out.items.%Push({"deliveryHeaderId": "", "sessionId": "", "originHeaderId": (c.origin), "timeCreated": "", "sourceStatus": "", "bodyClass": "", "family": "", "resendOf": "", "caseIds": (c.caseId), "linkQuality": "none", "eligibility": "unknown", "explanation": "case_origin_purged"})
    }
    Set cases = 0, k = ""
    For { Set k = $ORDER(distinct(k)) Quit:k=""  Set cases = cases + 1 }
    Set eligible = exact + none + ambiguous
    Set t = {"deliveries": (data.scanned), "completed": (data.completed), "notFinished": (data.notFinished), "failures": (failed), "eligible": (eligible), "exact": (exact), "none": (none), "ambiguous": (ambiguous), "excluded": (excluded), "unassessable": (unknown + orphans), "missingIds": (data.missingIds), "evidenceGaps": (data.missingIds + orphans + bodies), "distinctCases": (cases)}
    Do out.%Set("totals", t)
    If data.%Get("truncated") Do out.reasons.%Push("header_cap_hit")
    If data.%Get("candidatesCapped") Do out.reasons.%Push("case_cap_hit")
    If data.missingIds > 0 Do out.reasons.%Push("header_ids_missing")
    If data.%Get("reachesBack") Do out.reasons.%Push("window_older_than_kept_headers")
    If data.%Get("ownMessagesPurged") Do out.reasons.%Push("own_messages_purged")
    If orphans > 0 Do out.reasons.%Push("case_origin_purged")
    If bodies > 0 Do out.reasons.%Push("body_missing")
    If settling > 0 Do out.reasons.%Push("settling")
    Set out.completeness = $SELECT(out.reasons.%Size() > 0: "incomplete", 1: "complete")
    Quit out
}

/// The result on the run, and a row per item.
ClassMethod Store(run As Shutter.Store.CensusRun, data As %DynamicObject, out As %DynamicObject, ns As %String, item As %String) As %Status [ Private ]
{
    Set run.SourceRead = $SELECT(data.%Get("readable"): "ok", 1: "unavailable")
    Set run.SourceError = $EXTRACT(data.error, 1, 400)
    Set run.Completeness = out.completeness
    Set run.ReasonsJson = out.reasons.%ToJSON()
    If data.%Get("readable") {
        Set run.Scanned = data.scanned
        Set run.TotalsJson = out.totals.%ToJSON()
    }
    Set run.Truncated = ''data.%Get("truncated")
    Set run.ConfigVersion = ##class(Shutter.Store.SiteProfile).Current().%Get("version")
    Set run.ProductVersion = ##class(Shutter.Setup).#VERSION
    Set sc = run.%Save()
    If $$$ISERR(sc) Quit sc
    Set iter = out.items.%GetIterator()
    While iter.%GetNext(.i, .o) {
        Set row = ##class(Shutter.Store.CensusItem).%New()
        Set row.Run = run, row.SourceNamespace = ns, row.Target = item
        Set row.DeliveryHeaderId = o.deliveryHeaderId, row.SessionId = o.sessionId, row.OriginHeaderId = o.originHeaderId, row.TimeCreated = ..Iso(o.timeCreated)
        Set row.SourceStatus = o.sourceStatus, row.BodyClass = o.bodyClass, row.Family = o.family, row.ResendOf = o.resendOf
        Set row.CaseIds = o.caseIds, row.LinkQuality = o.linkQuality, row.Eligibility = o.eligibility, row.Explanation = o.explanation
        Set sc = row.%Save()
        If $$$ISERR(sc) Quit
    }
    If $$$ISERR(sc) Quit sc
    Set run.FinishedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit run.%Save()
}

/// The report: the run, its totals (null when the source could not be read) and, unless told not to, its rows.
ClassMethod Report(run As Shutter.Store.CensusRun, items As %Boolean = 1) As %DynamicObject
{
    Set r = {"runId": (run.RunId), "receiver": (run.Receiver), "namespace": (run.Namespace), "item": (run.Item), "window": {"from": (run.FromUTC), "to": (run.ToUTC)}, "cutoff": (run.CutoffUTC), "sourceRead": (run.SourceRead), "sourceError": (run.SourceError), "completeness": (run.Completeness), "maxHeaders": (run.MaxHeaders), "configVersion": (run.ConfigVersion), "productVersion": (run.ProductVersion), "requestedBy": (run.RequestedBy), "startedAt": (run.StartedAt), "finishedAt": (run.FinishedAt), "statement": (..#STATEMENT)}
    Do r.%Set("complete", (run.Completeness = "complete"), "boolean")
    Do r.%Set("truncated", ''run.Truncated, "boolean")
    Set r.reasons = $SELECT(run.ReasonsJson = "": [], 1: ##class(%DynamicArray).%FromJSON(run.ReasonsJson))
    If run.TotalsJson '= "" {
        Do r.%Set("scanned", run.Scanned, "number")
        Do r.%Set("totals", ##class(%DynamicObject).%FromJSON(run.TotalsJson))
    } Else {
        Do r.%Set("scanned", "", "null")
        Set t = {}
        For name = "deliveries", "completed", "notFinished", "failures", "eligible", "exact", "none", "ambiguous", "excluded", "unassessable", "missingIds", "evidenceGaps", "distinctCases" { Do t.%Set(name, "", "null") }
        Do r.%Set("totals", t)
    }
    If items {
        Set list = []
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT DeliveryHeaderId, SessionId, OriginHeaderId, Target, SourceNamespace, TimeCreated, SourceStatus, BodyClass, Family, ResendOf, CaseIds, LinkQuality, Eligibility, Explanation FROM Shutter_Store.CensusItem WHERE Run = ? ORDER BY ID", run.%Id())
        While rs.%Next() {
            Set row = {"sourceNamespace": (rs.%Get("SourceNamespace")), "target": (rs.%Get("Target")), "timeCreated": (rs.%Get("TimeCreated")), "sourceStatus": (rs.%Get("SourceStatus")), "bodyClass": (rs.%Get("BodyClass")), "family": (rs.%Get("Family")), "caseIds": (rs.%Get("CaseIds")), "linkQuality": (rs.%Get("LinkQuality")), "eligibility": (rs.%Get("Eligibility")), "explanation": (rs.%Get("Explanation"))}
            // Ids are text in the report, as the app reads them, though they look like numbers.
            Do row.%Set("deliveryHeaderId", rs.%Get("DeliveryHeaderId"), "string"), row.%Set("sessionId", rs.%Get("SessionId"), "string")
            Do row.%Set("originHeaderId", rs.%Get("OriginHeaderId"), "string"), row.%Set("resendOf", rs.%Get("ResendOf"), "string")
            Do list.%Push(row)
        }
        Set r.items = list
    }
    Quit r
}

/// The CSV: its columns, one run row that carries the completeness and the reasons (so a file read alone says what it is worth),
/// and one row per item.
ClassMethod Csv(run As Shutter.Store.CensusRun) As %Stream.TmpCharacter
{
    Set s = ##class(%Stream.TmpCharacter).%New()
    Set crlf = $CHAR(13, 10)
    Do s.Write(..#CSVCOLUMNS _ crlf)
    Set reasons = $SELECT(run.ReasonsJson = "": [], 1: ##class(%DynamicArray).%FromJSON(run.ReasonsJson))
    Do s.Write(..Row($LISTBUILD("run", run.RunId, run.Receiver, run.Namespace, run.Item, "", "", "", run.CutoffUTC, run.SourceRead, "", "", "", "", "", run.Completeness, ..Joined(reasons, ";"))) _ crlf)
    Set r = ..Report(run)
    Set iter = r.items.%GetIterator()
    While iter.%GetNext(.i, .o) {
        Do s.Write(..Row($LISTBUILD("item", run.RunId, run.Receiver, o.sourceNamespace, o.target, o.deliveryHeaderId, o.sessionId, o.originHeaderId, o.timeCreated, o.sourceStatus, o.bodyClass, o.family, o.resendOf, o.linkQuality, o.caseIds, o.eligibility, o.explanation)) _ crlf)
    }
    Do s.Rewind()
    Quit s
}

ClassMethod Row(cells As %List) As %String [ Private ]
{
    Set out = ""
    For i = 1:1:$LISTLENGTH(cells) { Set out = out _ $SELECT(i > 1: ",", 1: "") _ ..Cell($LISTGET(cells, i)) }
    Quit out
}

/// One CSV cell: quoted when it must be, and a value a spreadsheet would run as a formula is defused. An item's name is a site's
/// own words.
ClassMethod Cell(value As %String) As %String
{
    Set v = value
    If $CASE($EXTRACT(v, 1), "=": 1, "+": 1, "-": 1, "@": 1, $CHAR(9): 1, $CHAR(13): 1, : 0) Set v = "'" _ v
    If (v [ ",") || (v [ """") || (v [ $CHAR(10)) || (v [ $CHAR(13)) Quit """" _ $REPLACE(v, """", """""") _ """"
    Quit v
}

ClassMethod Joined(list As %DynamicArray, by As %String = ",") As %String [ Private ]
{
    Set out = "", iter = list.%GetIterator()
    While iter.%GetNext(.i, .v) { Set out = out _ $SELECT(out = "": "", 1: by) _ v }
    Quit out
}

/// The word for an Ens.MessageHeader status.
ClassMethod StatusWord(status As %Integer) As %String [ Private ]
{
    Quit $CASE(+status, 1: "created", 2: "queued", 3: "delivered", 4: "discarded", 5: "suspended", 6: "deferred", 7: "aborted", 8: "error", 9: "completed", : "unknown")
}

/// An ISO UTC time in the message store's form.
ClassMethod Odbc(iso As %String) As %String [ Private ]
{
    Quit $TRANSLATE($PIECE(iso, "Z", 1), "T", " ")
}

/// A message store time as ISO UTC, to the second.
ClassMethod Iso(odbc As %String) As %String [ Private ]
{
    If odbc = "" Quit ""
    Quit $TRANSLATE($PIECE(odbc, ".", 1), " ", "T") _ "Z"
}

}
