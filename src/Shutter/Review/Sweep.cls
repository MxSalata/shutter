/// The production review's deterministic pass (docs/CONTRACTS.md, section 13): which productions can be reviewed, one
/// run over one of them, the checks over the reader's data, the case aggregates, the configuration fingerprint, the
/// baseline rank and the annotations. It changes nothing anywhere: the review store (Shutter.Store.Review) is written by
/// the Case Review process, and a person applies any change in the Management Portal. Another namespace is read through
/// Shutter.Util.ProductionReader; everything here runs in Shutter's own namespace on the plain data it returns, and
/// Evaluate is a pure function of that data, so the unit tests fabricate it.
Class Shutter.Review.Sweep Extends %RegisteredObject
{

/// The HL7 operation classes the HL7 checks apply to by name, besides any class compiled here that extends
/// EnsLib.HL7.Operation.Standard.
Parameter HL7OPERATIONS = "EnsLib.HL7.Operation.Standard,EnsLib.HL7.Operation.ReplyStandard,EnsLib.HL7.Operation.TCPOperation,EnsLib.HL7.Operation.TCPAckOutOperation,EnsLib.HL7.Operation.FileOperation,EnsLib.HL7.Operation.FTPOperation,EnsLib.HL7.Operation.HTTPOperation,EnsLib.HL7.Operation.SOAPOperation";

/// The HL7 TCP operation classes (the framing check), besides any class compiled here that extends the first.
Parameter HL7TCPOPERATIONS = "EnsLib.HL7.Operation.TCPOperation,EnsLib.HL7.Operation.TCPAckOutOperation";

/// The HL7 TCP service classes (the framing check), besides any class compiled here that extends the first.
Parameter HL7TCPSERVICES = "EnsLib.HL7.Service.TCPService,EnsLib.HL7.Service.TCPAckInService";

/// The queue depth that is a backlog when the item sets no QueueCountAlert, and the depth above which it is high.
Parameter DEFAULTBACKLOG = 100;

Parameter HIGHBACKLOG = 1000;

/// How many of the newest case ids a finding and an aggregate carry.
Parameter LATESTCASES = 5;

/// The default and the longest review window, in days.
Parameter DEFAULTDAYS = 7;

Parameter MAXDAYS = 90;

// ---- targets ----

/// The productions a review may run on: Shutter's own, the hospital's (^Shutter.Config("hospitalNamespace"): its running
/// production, or every production defined there when none runs) and every production that has sent Shutter a case
/// (the distinct SourceNamespace, SourceProduction pairs), without repeats. [{namespace, production, productionState,
/// own, watched}].
ClassMethod Targets() As %DynamicArray
{
    Set out = []
    Kill seen
    Set ownNs = $NAMESPACE, ownProd = ##class(Shutter.Setup).ProductionName()
    Set states = ##class(Shutter.Util.ProductionReader).Productions(ownNs)
    Do ..AddTarget(out, .seen, ownNs, ownProd, ##class(Shutter.Util.ProductionReader).StateIn(states, ownProd), ownNs, ownProd)
    Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
    If (hospital '= "") && ($ZCONVERT(hospital, "U") '= $ZCONVERT(ownNs, "U")) {
        Set states = ##class(Shutter.Util.ProductionReader).Productions(hospital)
        Set running = 0
        Set iter = states.%GetIterator()
        While iter.%GetNext(.i, .p) {
            If p.state = "running" {
                Do ..AddTarget(out, .seen, hospital, p.production, p.state, ownNs, ownProd)
                Set running = 1
            }
        }
        If 'running {
            Set iter = states.%GetIterator()
            While iter.%GetNext(.i, .p) {
                // The namespace's own foundation production is not a feed.
                Continue:($PIECE(p.production, ".", $LENGTH(p.production, ".")) = "FoundationProduction")
                Do ..AddTarget(out, .seen, hospital, p.production, ##class(Shutter.Util.ProductionReader).StateIn(states, p.production), ownNs, ownProd)
            }
        }
    }
    Try {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT %EXACT(SourceNamespace) AS Ns, %EXACT(SourceProduction) AS Prod, COUNT(*) AS N FROM Shutter_Store.""Case"" WHERE SourceNamespace IS NOT NULL AND SourceNamespace <> '' AND SourceProduction IS NOT NULL AND SourceProduction <> '' GROUP BY %EXACT(SourceNamespace), %EXACT(SourceProduction)")
        While rs.%Next() {
            Set ns = rs.%Get("Ns"), prod = rs.%Get("Prod")
            Continue:((ns = "") || (prod = ""))
            Do ..AddTarget(out, .seen, ns, prod, ##class(Shutter.Util.ProductionReader).State(ns, prod), ownNs, ownProd)
        }
    } Catch ex {
    }
    Quit out
}

/// Whether a namespace and production pair is one of Targets() (the namespace compared without regard to case).
ClassMethod IsTarget(namespace As %String, production As %String) As %Boolean
{
    Set iter = ..Targets().%GetIterator()
    While iter.%GetNext(.i, .t) {
        If ($ZCONVERT(t.namespace, "U") = $ZCONVERT(namespace, "U")) && (t.production = production) Quit
    }
    Quit $ISOBJECT($GET(t)) && ($ZCONVERT(t.namespace, "U") = $ZCONVERT(namespace, "U")) && (t.production = production)
}

ClassMethod AddTarget(out As %DynamicArray, ByRef seen, namespace As %String, production As %String, state As %String, ownNs As %String, ownProd As %String) [ Private ]
{
    Set key = $ZCONVERT(namespace, "U") _ "|" _ production
    If $DATA(seen(key)) Quit
    Set seen(key) = ""
    Set t = {}
    Set t.namespace = namespace
    Set t.production = production
    Set t.productionState = state
    Set own = ($ZCONVERT(namespace, "U") = $ZCONVERT(ownNs, "U")) && (production = ownProd)
    Do t.%Set("own", own, "boolean")
    Do t.%Set("watched", 'own, "boolean")
    Do out.%Push(t)
}

/// The targets as JSON, for scripts that reach IRIS through SQL: SELECT Shutter_Review.Sweep_TargetsJSON().
ClassMethod TargetsJSON() As %String(MAXLEN = "") [ SqlProc ]
{
    Set out = ""
    Try {
        Set out = ..Targets().%ToJSON()
    } Catch ex {
        Set out = {"error": (ex.DisplayString())}.%ToJSON()
    }
    Quit out
}

// ---- one run ----

/// One run as JSON, for scripts that reach IRIS through SQL and for a check on an instance:
/// SELECT Shutter_Review.Sweep_RunJSON('HOSPITAL', 'Hospital.Production', 7). Nothing is stored. The namespace and
/// production default to Shutter's own; an argument SQL hands over as $CHAR(0) counts as empty.
ClassMethod RunJSON(namespace As %String = "", production As %String = "", windowDays As %Integer = 7) As %String(MAXLEN = "") [ SqlProc ]
{
    If namespace = $CHAR(0) Set namespace = ""
    If production = $CHAR(0) Set production = ""
    If windowDays = $CHAR(0) Set windowDays = 7
    If namespace = "" Set namespace = $NAMESPACE
    If production = "" Set production = ##class(Shutter.Setup).ProductionName()
    Set out = ""
    Try {
        Set sc = ..Run(namespace, production, +windowDays, .result)
        If $$$ISERR(sc) {
            Set out = {"error": ($SYSTEM.Status.GetErrorText(sc))}.%ToJSON()
        } Else {
            Set out = result.%ToJSON()
        }
    } Catch ex {
        Set out = {"error": (ex.DisplayString())}.%ToJSON()
    }
    Quit out
}

/// One review of one production over the last windowDays (1 to 90; 7 when out of range): the reader's data, the case
/// aggregates, the checks, the fingerprint, the baseline rank and the annotations. result = {namespace, production,
/// productionState, window: {days, from, to}, fingerprint, summary, findings, caseAggregates, readAt, unreadable}. A
/// namespace or production that cannot be read gives one finding, NAMESPACE_UNREADABLE, unreadable true and a good
/// status: the review is still a result.
ClassMethod Run(namespace As %String, production As %String, windowDays As %Integer = 7, Output result As %DynamicObject) As %Status
{
    Set days = +windowDays
    If (days < 1) || (days > ..#MAXDAYS) Set days = ..#DEFAULTDAYS
    Set to = ##class(Shutter.Util.Time).NowUTC()
    Set from = ##class(Shutter.Util.Time).FromNow(-86400 * days)
    Set own = ($ZCONVERT(namespace, "U") = $ZCONVERT($NAMESPACE, "U")) && (production = ##class(Shutter.Setup).ProductionName())
    Set result = {}
    Set result.namespace = namespace
    Set result.production = production
    Set result.productionState = ""
    Set window = {}
    Set window.days = days
    Set window.from = from
    Set window.to = to
    Set result.window = window
    Set cases = ..CaseAggregates(namespace, production, own, from)
    Set rsc = ##class(Shutter.Util.ProductionReader).Read(namespace, production, from, .data)
    Set unreadable = $$$ISERR(rsc)
    If unreadable {
        Set error = ""
        If $ISOBJECT($GET(data)) Set error = ##class(Shutter.Util.Json).Str(data, "error")
        If error = "" Set error = $SYSTEM.Status.GetErrorText(rsc)
        Set findings = []
        Do findings.%Push(##class(Shutter.Review.Checks).Finding("NAMESPACE_UNREADABLE", "", "", "", $EXTRACT(error, 1, 300), "observed"))
        Do ..AttachCases(findings, cases)
        Set result.productionState = "unknown"
        Set result.readAt = ##class(Shutter.Util.Time).NowUTC()
    } Else {
        Set findings = ..Evaluate(data, cases, window)
        Set result.productionState = data.productionState
        Set result.readAt = data.readAt
    }
    Set result.fingerprint = ..Fingerprint(findings)
    Do ..BaselineRank(findings)
    Do ..ApplyAnnotations(findings, namespace, production)
    Set result.summary = ..Summary(findings, $SELECT(unreadable: "", 1: data))
    Set result.findings = findings
    Set result.caseAggregates = cases
    Do result.%Set("unreadable", unreadable, "boolean")
    Quit $$$OK
}

/// The summary block: findings by severity, how many there are, how many carry an annotation, the items read, the
/// errors and the failed messages (status Error) in the window.
ClassMethod Summary(findings As %DynamicArray, data As %DynamicObject) As %DynamicObject [ Private ]
{
    Set s = {}
    Set by = {"high": 0, "medium": 0, "low": 0, "info": 0}
    Set intended = 0
    Set iter = findings.%GetIterator()
    While iter.%GetNext(.i, .f) {
        If by.%IsDefined(f.severity) Do by.%Set(f.severity, by.%Get(f.severity) + 1)
        If f.status '= "new" Set intended = intended + 1
    }
    Set s.bySeverity = by
    Set s.findings = findings.%Size()
    Set s.intended = intended
    Set s.items = 0, s.errorsInWindow = 0, s.messageErrorsInWindow = 0
    If $ISOBJECT(data) {
        Set s.items = data.items.%Size()
        Set iter = data.logErrors.%GetIterator()
        While iter.%GetNext(.i, .g) {
            Set s.errorsInWindow = s.errorsInWindow + g.count
        }
        Set iter = data.headerErrors.%GetIterator()
        While iter.%GetNext(.i, .h) {
            If h.status = 8 Set s.messageErrorsInWindow = s.messageErrorsInWindow + h.count
        }
    }
    Quit s
}

// ---- the checks ----

/// The checks of the design's section 3 over the reader's data: a pure function (no SQL, no namespace switch) of data,
/// the case aggregates (CaseAggregates, "" for none) and the window. Returns the findings unranked (ids empty), each in
/// the shape Shutter.Review.Checks.Finding gives, with its cases block filled from the aggregates.
ClassMethod Evaluate(data As %DynamicObject, cases As %DynamicObject, window As %DynamicObject) As %DynamicArray
{
    Set findings = []
    Set items = data.items
    If '$ISOBJECT(items) Set items = []
    // Categories are the operator's own grouping: when the production uses them, "Feed" marks the feed path; when no
    // item has one, every item is on it. HL7 items are on it either way.
    Set anyCategory = 0
    Set iter = items.%GetIterator()
    While iter.%GetNext(.i, .item) {
        If ##class(Shutter.Util.Json).Str(item, "category") '= "" Set anyCategory = 1
    }
    If '##class(Shutter.Util.Json).Bool(data, "alertItemPresent") {
        Do findings.%Push(##class(Shutter.Review.Checks).Finding("NO_ALERT_CONSUMER", "", "", "", "no Ens.Alert item", "observed"))
    }
    Set alerting = "", queueAlerts = ""
    Kill tcpOps, tcpSvcs
    Set iter = items.%GetIterator()
    While iter.%GetNext(.i, .item) {
        Set name = item.name, class = ##class(Shutter.Util.Json).Str(item, "className"), adapter = ##class(Shutter.Util.Json).Str(item, "adapterClassName")
        Set type = ##class(Shutter.Util.Json).Str(item, "businessType"), enabled = ##class(Shutter.Util.Json).Bool(item, "enabled", 1), pool = +##class(Shutter.Util.Json).Str(item, "poolSize", 0)
        Set feed = ..FeedPath(item, anyCategory)
        Set isOp = (type = "operation"), isProc = (type = "process"), isSvc = (type = "service")
        Set hl7Op = ..IsHL7Operation(class)
        // ITEM_DISABLED: a feed-path item that is switched off.
        If feed && 'enabled {
            Do findings.%Push(##class(Shutter.Review.Checks).Finding("ITEM_DISABLED", name, class, "Enabled", "0", "item"))
        }
        // RETRY_FOREVER and GIVES_UP_EARLY: the retry budget of an operation or process.
        If isOp || isProc {
            Set ft = ..Effective(data, item, "FailureTimeout", .ftSource)
            Set ri = ..Effective(data, item, "RetryInterval", .riSource)
            If (ft '= "") && (+ft = -1) {
                Do findings.%Push(##class(Shutter.Review.Checks).Finding("RETRY_FOREVER", name, class, "FailureTimeout", "-1", ftSource))
            } ElseIf (+ft > 0) && (+ri > 0) && (+ft < (2 * ri)) {
                Do findings.%Push(##class(Shutter.Review.Checks).Finding("GIVES_UP_EARLY", name, class, "FailureTimeout", "FailureTimeout " _ +ft _ " with RetryInterval " _ +ri, ftSource))
            }
        }
        // REPLY_CODES_LENIENT and REPLY_CODES_SUSPEND_UNWATCHED: how an HL7 operation takes a negative acknowledgement.
        If hl7Op {
            Set actions = ..Effective(data, item, "ReplyCodeActions", .rcaSource)
            Set documented = (actions = "")
            If documented Set actions = ##class(Shutter.Review.Checks).#DOCUMENTEDREPLYCODEACTIONS, rcaSource = "class_default"
            Set lenient = "", suspended = ""
            For code = "AE", "AR" {
                Set action = ..ReplyAction(actions, code)
                If ..IsLenient(action) Set lenient = lenient _ $SELECT(lenient = "": "", 1: ", ") _ code _ "=" _ action
                If action [ "S" Set suspended = suspended _ $SELECT(suspended = "": "", 1: ", ") _ code _ "=" _ action
            }
            Set note = $SELECT(documented: " (ReplyCodeActions not set: the documented default)", 1: "")
            If lenient '= "" {
                Do findings.%Push(##class(Shutter.Review.Checks).Finding("REPLY_CODES_LENIENT", name, class, "ReplyCodeActions", lenient _ note, rcaSource))
            } ElseIf (suspended '= "") && '+..Effective(data, item, "AlertOnError", .aoeSource) {
                Do findings.%Push(##class(Shutter.Review.Checks).Finding("REPLY_CODES_SUSPEND_UNWATCHED", name, class, "ReplyCodeActions", suspended _ note _ ", AlertOnError 0", rcaSource))
            }
        }
        // POOL_SIZE_REORDERS: more than one job on an ordered feed.
        If (hl7Op || (isProc && feed)) && (pool > 1) {
            Do findings.%Push(##class(Shutter.Review.Checks).Finding("POOL_SIZE_REORDERS", name, class, "PoolSize", pool, "item"))
        }
        // ARCHIVE_IO_ON: raw I/O kept.
        If +..Effective(data, item, "ArchiveIO", .aioSource) = 1 {
            Do findings.%Push(##class(Shutter.Review.Checks).Finding("ARCHIVE_IO_ON", name, class, "ArchiveIO", "1", aioSource))
        }
        // FEED_SILENCE_UNWATCHED: a feed service with a real inbound adapter and no inactivity timeout.
        If isSvc && feed && ($EXTRACT(class, 1, 8) '= "Shutter.") && (adapter '= "") && (adapter '= "Ens.InboundAdapter") {
            Set it = ..Effective(data, item, "InactivityTimeout", .itSource)
            If +it = 0 {
                Do findings.%Push(##class(Shutter.Review.Checks).Finding("FEED_SILENCE_UNWATCHED", name, class, "InactivityTimeout", "0", $SELECT(itSource = "": "class_default", 1: itSource)))
            }
        }
        // ALERTING_OFF, gathered into one finding: feed-path items that raise no alert or name no group.
        If feed {
            Set aoe = ..Effective(data, item, "AlertOnError", .aoeSource)
            Set groups = ..Effective(data, item, "AlertGroups", .agSource)
            If ('+aoe) || (groups = "") {
                Set alerting = alerting _ $SELECT(alerting = "": "", 1: "; ") _ name _ " (AlertOnError " _ +aoe _ $SELECT(aoeSource '= "": ", " _ $TRANSLATE(aoeSource, "_", " "), 1: "") _ $SELECT(groups = "": ", no AlertGroups", 1: "") _ ")"
            }
        }
        // QUEUE_ALERTS_OFF, gathered into one finding: feed-path operations with neither queue alert.
        Set qc = ..Effective(data, item, "QueueCountAlert", .qcSource)
        If isOp && feed {
            Set qw = ..Effective(data, item, "QueueWaitAlert", .qwSource)
            If ('+qc) && ('+qw) Set queueAlerts = queueAlerts _ $SELECT(queueAlerts = "": "", 1: "; ") _ name
        }
        // QUEUE_BACKLOG: the item's queue above its threshold (QueueCountAlert, or 100 when unset); high above 1000.
        Set depth = ..QueueDepth(data, name)
        If depth '= "" {
            Set threshold = $SELECT(+qc > 0: +qc, 1: ..#DEFAULTBACKLOG)
            If depth > threshold {
                Set f = ##class(Shutter.Review.Checks).Finding("QUEUE_BACKLOG", name, class, "QueueCountAlert", "queue " _ depth _ " above " _ threshold _ $SELECT(+qc > 0: "", 1: " (no QueueCountAlert set)"), $SELECT(+qc > 0: qcSource, 1: "observed"), depth)
                If depth > ..#HIGHBACKLOG Set f.severity = "high"
                Set f.evidence.latestAt = ..QueueCreated(data, name)
                Do findings.%Push(f)
            }
        }
        // The TCP pairs for FRAMING_MISMATCH.
        If ..IsHL7TCPOperation(class) {
            Set address = ..Effective(data, item, "IPAddress", .addressSource)
            Set port = ..Effective(data, item, "Port", .portSource)
            Set framing = ..Effective(data, item, "Framing", .framingSource)
            Set tcpOps(i) = $LISTBUILD(name, class, address, port, framing, framingSource)
        }
        If ..IsHL7TCPService(class) {
            Set port = ..Effective(data, item, "Port", .portSource)
            Set framing = ..Effective(data, item, "Framing", .framingSource)
            Set tcpSvcs(i) = $LISTBUILD(name, class, port, framing)
        }
    }
    If alerting '= "" {
        Do findings.%Push(##class(Shutter.Review.Checks).Finding("ALERTING_OFF", "", "", "AlertOnError", alerting, "item"))
    }
    If queueAlerts '= "" {
        Do findings.%Push(##class(Shutter.Review.Checks).Finding("QUEUE_ALERTS_OFF", "", "", "QueueCountAlert", queueAlerts, "class_default"))
    }
    // FRAMING_MISMATCH: an HL7 TCP operation that points at this instance, on the port of an HL7 TCP service here, with a
    // framing the service does not take (Flexible takes any).
    Set host = $ZCONVERT(##class(Shutter.Util.Json).Str(data, "host"), "L")
    Set oi = ""
    For {
        Set oi = $ORDER(tcpOps(oi), 1, op)
        Quit:oi=""
        Set address = $ZCONVERT($LIST(op, 3), "L"), port = $LIST(op, 4), framing = $LIST(op, 5)
        Continue:((port = "") || (framing = ""))
        Continue:'$LISTFIND($LISTBUILD("", "localhost", "127.0.0.1", "::1", "0.0.0.0", host), address)
        Set si = ""
        For {
            Set si = $ORDER(tcpSvcs(si), 1, svc)
            Quit:si=""
            Continue:(+$LIST(svc, 3) '= +port)
            Set svcFraming = $LIST(svc, 4)
            Continue:((svcFraming = "") || ($ZCONVERT(svcFraming, "L") = "flexible") || ($ZCONVERT(framing, "L") = "flexible"))
            Continue:($ZCONVERT(svcFraming, "L") = $ZCONVERT(framing, "L"))
            Do findings.%Push(##class(Shutter.Review.Checks).Finding("FRAMING_MISMATCH", $LIST(op, 1), $LIST(op, 2), "Framing", "operation Framing " _ framing _ ", service " _ $LIST(svc, 1) _ " Framing " _ svcFraming _ " on port " _ +port, $LIST(op, 6)))
        }
    }
    // The purge task of the namespace (null when %SYS could not be read: then nothing is said about it).
    Set purge = data.%Get("purgeTask")
    If $ISOBJECT(purge) {
        If '##class(Shutter.Util.Json).Bool(purge, "present") {
            Do findings.%Push(##class(Shutter.Review.Checks).Finding("PURGE_MISSING", "", "", "", "no Ens.Util.Tasks.Purge task for the namespace", "observed"))
        } Else {
            If ##class(Shutter.Util.Json).Bool(purge, "suspended") {
                Do findings.%Push(##class(Shutter.Review.Checks).Finding("PURGE_SUSPENDED", "", "", "Suspended", "1", "observed"))
            }
            Set days = ##class(Shutter.Util.Json).Str(purge, "daysToKeep")
            If (days '= "") && (+days < 7) {
                Do findings.%Push(##class(Shutter.Review.Checks).Finding("PURGE_SHORT", "", "", "NumberOfDaysToKeep", +days, "observed"))
            }
            If (days '= "") && (+days > 365) {
                Do findings.%Push(##class(Shutter.Review.Checks).Finding("PURGE_LONG", "", "", "NumberOfDaysToKeep", +days, "observed"))
            }
            If (purge.%GetTypeOf("bodiesToo") '= "null") && (purge.%GetTypeOf("bodiesToo") '= "unassigned") && '##class(Shutter.Util.Json).Bool(purge, "bodiesToo") {
                Do findings.%Push(##class(Shutter.Review.Checks).Finding("BODIES_KEPT", "", "", "BodiesToo", "0", "observed"))
            }
        }
    }
    // SUSPENDED_MESSAGES (status 5, one finding per target) and MESSAGE_ERRORS (status 8, and 7 aborted, per target and
    // source) from the headers in the window.
    Kill suspendedBy
    Set headerErrors = data.%Get("headerErrors")
    If '$ISOBJECT(headerErrors) Set headerErrors = []
    Set logErrors = data.%Get("logErrors")
    If '$ISOBJECT(logErrors) Set logErrors = []
    Set ruleErrors = data.%Get("ruleErrors")
    If '$ISOBJECT(ruleErrors) Set ruleErrors = []
    Set iter = headerErrors.%GetIterator()
    While iter.%GetNext(.i, .h) {
        Set target = ##class(Shutter.Util.Json).Str(h, "target"), source = ##class(Shutter.Util.Json).Str(h, "source")
        If h.status = 5 {
            // The subscript is prefixed: a header with no target would otherwise be an empty one.
            Set key = "|" _ target
            If '$DATA(suspendedBy(key)) Set suspendedBy(key) = $LISTBUILD(0, "", "")
            Set count = $LIST(suspendedBy(key), 1) + h.count
            Set latestId = $LIST(suspendedBy(key), 2), latestAt = $LIST(suspendedBy(key), 3)
            If +h.latestId > +latestId Set latestId = h.latestId, latestAt = h.latestAt
            Set suspendedBy(key) = $LISTBUILD(count, latestId, latestAt)
            Continue
        }
        Set word = $SELECT(h.status = 7: "aborted", 1: "in Error")
        Set f = ##class(Shutter.Review.Checks).Finding("MESSAGE_ERRORS", target, ..ClassOf(items, target), "", h.count _ " " _ word _ " from " _ $SELECT(source = "": "(no source)", 1: source), "observed", h.count)
        Set f.evidence.latestHeaderId = h.latestId, f.evidence.latestAt = h.latestAt
        Do findings.%Push(f)
    }
    Set key = ""
    For {
        Set key = $ORDER(suspendedBy(key), 1, agg)
        Quit:key=""
        Set target = $EXTRACT(key, 2, *)
        Set f = ##class(Shutter.Review.Checks).Finding("SUSPENDED_MESSAGES", target, ..ClassOf(items, target), "", $LIST(agg, 1) _ " suspended", "observed", $LIST(agg, 1))
        Set f.evidence.latestHeaderId = $LIST(agg, 2), f.evidence.latestAt = $LIST(agg, 3)
        Do findings.%Push(f)
    }
    // ERRORS_GROUPED: the event log's errors by item and signature; the example text stays in the evidence for the
    // operator's GET and never reaches the agent.
    Set iter = logErrors.%GetIterator()
    While iter.%GetNext(.i, .g) {
        Set configName = ##class(Shutter.Util.Json).Str(g, "configName"), signature = ##class(Shutter.Util.Json).Str(g, "signature")
        Set class = ..ClassOf(items, configName)
        Set f = ##class(Shutter.Review.Checks).Finding("ERRORS_GROUPED", configName, class, "", signature, "observed", g.count)
        // Errors logged outside any item (the production's own start and stop) are worth a look, not a medium.
        If configName = "" Set f.severity = "low"
        If configName = "" {
            Set f.why = f.why _ " The errors carry no item name: they are the production's own (a start, a stop, the director)."
        } ElseIf (class = "") && '..HasItem(items, configName) {
            Set f.why = f.why _ " The item is no longer in the production."
        }
        Set latestMessageId = ##class(Shutter.Util.Json).Str(g, "latestMessageId")
        Set f.evidence.latestHeaderId = $SELECT(latestMessageId '= "": latestMessageId, 1: ##class(Shutter.Util.Json).Str(g, "latestId"))
        Set f.evidence.latestAt = ##class(Shutter.Util.Json).Str(g, "latestAt")
        Set f.evidence.example = ##class(Shutter.Util.Json).Str(g, "exampleText")
        Do findings.%Push(f)
    }
    // RULE_ERRORS: the rule log's errors by rule; when the rule log has none, a transform named in an error text's stack
    // location (zTransform+N^My.Transform.1) is reported from the error text.
    Set ruleRows = 0
    Set iter = ruleErrors.%GetIterator()
    While iter.%GetNext(.i, .r) {
        Set ruleRows = ruleRows + 1
        Set ruleName = ##class(Shutter.Util.Json).Str(r, "ruleName"), ruleSet = ##class(Shutter.Util.Json).Str(r, "ruleSet")
        Set f = ##class(Shutter.Review.Checks).Finding("RULE_ERRORS", ruleName, ruleName, "", $SELECT(ruleSet '= "": "rule set " _ ruleSet, 1: "rule log"), "observed", r.count)
        Set f.evidence.latestHeaderId = ##class(Shutter.Util.Json).Str(r, "latestId")
        Set f.evidence.example = ##class(Shutter.Util.Json).Str(r, "errorMsg")
        Do findings.%Push(f)
    }
    If ruleRows = 0 {
        Kill transforms
        Set iter = logErrors.%GetIterator()
        While iter.%GetNext(.i, .g) {
            Set transform = ..TransformIn(##class(Shutter.Util.Json).Str(g, "exampleText"))
            Continue:transform=""
            If '$DATA(transforms(transform)) Set transforms(transform) = $LISTBUILD(0, "", "")
            Set count = $LIST(transforms(transform), 1) + g.count
            Set latestId = $LIST(transforms(transform), 2), example = $LIST(transforms(transform), 3)
            If +##class(Shutter.Util.Json).Str(g, "latestId") > +latestId Set latestId = g.latestId, example = ##class(Shutter.Util.Json).Str(g, "exampleText")
            Set transforms(transform) = $LISTBUILD(count, latestId, example)
        }
        Set transform = ""
        For {
            Set transform = $ORDER(transforms(transform), 1, agg)
            Quit:transform=""
            Set f = ##class(Shutter.Review.Checks).Finding("RULE_ERRORS", transform, transform, "", "from the error text", "observed", $LIST(agg, 1))
            Set f.evidence.latestHeaderId = $LIST(agg, 2), f.evidence.example = $LIST(agg, 3)
            Do findings.%Push(f)
        }
    }
    Do ..AttachCases(findings, cases)
    Quit findings
}

/// The effective value of a setting for an item, resolved in three explicit steps, and which one answered in source:
/// the item's own Settings list ("item"), a matching system default setting ("default_setting": the production or '*',
/// the item name or '*', the host or adapter class or '*', the nearest match first), the host or adapter class's
/// InitialExpression ("class_default"). "" with source "" when none has it.
ClassMethod Effective(data As %DynamicObject, item As %DynamicObject, setting As %String, Output source As %String) As %String
{
    Set source = ""
    Set settings = item.%Get("settings")
    If $ISOBJECT(settings) {
        Set iter = settings.%GetIterator()
        While iter.%GetNext(.i, .s) {
            If s.name = setting {
                Set source = "item"
                Quit
            }
        }
        If source = "item" Quit ##class(Shutter.Util.Json).Str(s, "value")
    }
    Set name = ##class(Shutter.Util.Json).Str(item, "name"), class = ##class(Shutter.Util.Json).Str(item, "className"), adapter = ##class(Shutter.Util.Json).Str(item, "adapterClassName")
    Set production = ##class(Shutter.Util.Json).Str(data, "production")
    Set rows = data.%Get("defaultSettings")
    If $ISOBJECT(rows) {
        Set best = -1, value = ""
        Set iter = rows.%GetIterator()
        While iter.%GetNext(.i, .r) {
            Continue:(##class(Shutter.Util.Json).Str(r, "settingName") '= setting)
            Set rp = ##class(Shutter.Util.Json).Str(r, "productionName", "*"), ri = ##class(Shutter.Util.Json).Str(r, "itemName", "*"), rc = ##class(Shutter.Util.Json).Str(r, "hostClassName", "*")
            Set rank = 0
            If rp = production { Set rank = rank + 1 } ElseIf rp '= "*" { Continue }
            If ri = name { Set rank = rank + 20 } ElseIf ri '= "*" { Continue }
            If (rc = class) || ((adapter '= "") && (rc = adapter)) { Set rank = rank + 10 } ElseIf rc '= "*" { Continue }
            If rank > best Set best = rank, value = ##class(Shutter.Util.Json).Str(r, "settingValue")
        }
        If best >= 0 {
            Set source = "default_setting"
            Quit value
        }
    }
    Set defaults = data.%Get("classDefaults")
    If $ISOBJECT(defaults) {
        For c = class, adapter {
            Continue:c=""
            Set d = defaults.%Get(c)
            Continue:'$ISOBJECT(d)
            If d.%IsDefined(setting) {
                Set source = "class_default"
                Quit
            }
        }
        If source = "class_default" Quit ##class(Shutter.Util.Json).Str(d, setting)
    }
    Quit ""
}

/// The action an HL7 operation's ReplyCodeActions gives a reply code (AE, AR, AA, ...): the first entry whose pattern
/// matches, in upper case; "" when none does. Patterns, with or without the leading colon: ?E (a two-letter code ending
/// in E), ?R, ?A, I? and T? (a code starting so), the code itself (AE), a bare letter (the code's second letter), *
/// (any other code); ~ (no reply) matches no code.
ClassMethod ReplyAction(actions As %String, code As %String) As %String
{
    Set code = $ZCONVERT(code, "U"), result = ""
    For i = 1:1:$LENGTH(actions, ",") {
        Set entry = $ZSTRIP($PIECE(actions, ",", i), "<>W")
        Continue:entry=""
        Set pattern = $ZCONVERT($ZSTRIP($PIECE(entry, "=", 1), "<>W"), "U"), action = $ZCONVERT($ZSTRIP($PIECE(entry, "=", 2), "<>W"), "U")
        If $EXTRACT(pattern, 1) = ":" Set pattern = $EXTRACT(pattern, 2, *)
        Continue:((pattern = "") || (pattern = "~"))
        Set match = 0
        If pattern = "*" {
            Set match = 1
        } ElseIf pattern = code {
            Set match = 1
        } ElseIf ($LENGTH(pattern) = 2) && ($EXTRACT(pattern, 1) = "?") {
            Set match = ($EXTRACT(code, 2) = $EXTRACT(pattern, 2))
        } ElseIf ($LENGTH(pattern) = 2) && ($EXTRACT(pattern, 2) = "?") {
            Set match = ($EXTRACT(code, 1) = $EXTRACT(pattern, 1))
        } ElseIf $LENGTH(pattern) = 1 {
            Set match = ($EXTRACT(code, 2) = pattern)
        }
        If match {
            Set result = action
            Quit
        }
    }
    Quit result
}

/// Whether a reply action treats the message as sent: C (completed) or W (a warning, then completed) with no S, F or D
/// beside it.
ClassMethod IsLenient(action As %String) As %Boolean
{
    Set action = $ZCONVERT(action, "U")
    If action = "" Quit 0
    If (action [ "S") || (action [ "F") || (action [ "D") Quit 0
    Quit (action [ "C") || (action [ "W")
}

/// The signature of an error text (Shutter.Util.ProductionReader.Signature): the text before its first colon, and before
/// a hash that does not start an error number.
ClassMethod Signature(text As %String) As %String
{
    Quit ##class(Shutter.Util.ProductionReader).Signature(text)
}

/// The transform class named in an error text's stack location (zTransform+12^My.Transform.1), "" when none.
ClassMethod TransformIn(text As %String) As %String
{
    If text = "" Quit ""
    Set pos = $LOCATE(text, "zTransform\+[0-9]+\^[A-Za-z%][A-Za-z0-9.]*\.1", 1, end, match)
    If pos = 0 Quit ""
    Set class = $PIECE(match, "^", 2)
    Quit $EXTRACT(class, 1, $LENGTH(class) - 2)
}

/// Whether an item is on the feed path: its Category names Feed, its class is an HL7 class, or no item of the production
/// has a category at all.
ClassMethod FeedPath(item As %DynamicObject, anyCategory As %Boolean) As %Boolean [ Private ]
{
    Set cat = "," _ $ZCONVERT($TRANSLATE(##class(Shutter.Util.Json).Str(item, "category"), " "), "L") _ ","
    If cat [ ",feed," Quit 1
    If $EXTRACT(##class(Shutter.Util.Json).Str(item, "className"), 1, 11) = "EnsLib.HL7." Quit 1
    Quit 'anyCategory
}

ClassMethod IsHL7Operation(class As %String) As %Boolean
{
    If class = "" Quit 0
    If $LISTFIND($LISTFROMSTRING(..#HL7OPERATIONS), class) Quit 1
    Quit ..ExtendsClass(class, "EnsLib.HL7.Operation.Standard")
}

ClassMethod IsHL7TCPOperation(class As %String) As %Boolean
{
    If class = "" Quit 0
    If $LISTFIND($LISTFROMSTRING(..#HL7TCPOPERATIONS), class) Quit 1
    Quit ..ExtendsClass(class, "EnsLib.HL7.Operation.TCPOperation")
}

ClassMethod IsHL7TCPService(class As %String) As %Boolean
{
    If class = "" Quit 0
    If $LISTFIND($LISTFROMSTRING(..#HL7TCPSERVICES), class) Quit 1
    Quit ..ExtendsClass(class, "EnsLib.HL7.Service.TCPService")
}

/// Whether a class compiled in this namespace extends another; 0 for a class that is not here.
ClassMethod ExtendsClass(class As %String, super As %String) As %Boolean [ Private ]
{
    Set yes = 0
    Try {
        If ##class(%Dictionary.CompiledClass).%ExistsId(class) Set yes = ''$CLASSMETHOD(class, "%Extends", super)
    } Catch ex {
        Set yes = 0
    }
    Quit yes
}

/// The class of the item of that name in the reader's items, "" when none.
ClassMethod ClassOf(items As %DynamicArray, name As %String) As %String [ Private ]
{
    If name = "" Quit ""
    Set iter = items.%GetIterator()
    While iter.%GetNext(.i, .item) {
        If item.name = name Quit
    }
    If $ISOBJECT($GET(item)) && (item.name = name) Quit ##class(Shutter.Util.Json).Str(item, "className")
    Quit ""
}

ClassMethod HasItem(items As %DynamicArray, name As %String) As %Boolean [ Private ]
{
    Set iter = items.%GetIterator()
    While iter.%GetNext(.i, .item) {
        If item.name = name Quit
    }
    Quit $ISOBJECT($GET(item)) && (item.name = name)
}

/// The depth of an item's queue from the reader's queues, "" when the item has none listed.
ClassMethod QueueDepth(data As %DynamicObject, name As %String) As %String [ Private ]
{
    Set queues = data.%Get("queues")
    If '$ISOBJECT(queues) Quit ""
    Set iter = queues.%GetIterator()
    While iter.%GetNext(.i, .q) {
        If q.name = name Return +q.count
    }
    Quit ""
}

ClassMethod QueueCreated(data As %DynamicObject, name As %String) As %String [ Private ]
{
    Set queues = data.%Get("queues")
    If '$ISOBJECT(queues) Quit ""
    Set iter = queues.%GetIterator()
    While iter.%GetNext(.i, .q) {
        If q.name = name Return ##class(Shutter.Util.Json).Str(q, "created")
    }
    Quit ""
}

/// Each finding's cases block from the aggregates: the item's, or the production's total for a finding about the
/// production or the namespace.
ClassMethod AttachCases(findings As %DynamicArray, cases As %DynamicObject) [ Private ]
{
    If '$ISOBJECT(cases) Quit
    Set iter = findings.%GetIterator()
    While iter.%GetNext(.i, .f) {
        // A finding about the production as a whole is not motivated by particular cases: the whole production's cases
        // stay in the aggregates for the agent, and the finding's own count stays 0, so it is ranked by its severity.
        Continue:f.item=""
        Set agg = cases.%Get(f.item)
        Continue:'$ISOBJECT(agg)
        Set f.cases.count = +agg.count
        Set f.cases.unique = +agg.unique
        Set f.cases.latest = $SELECT($ISOBJECT(agg.latest): agg.latest, 1: [])
    }
}

// ---- cases ----

/// The cases of the window tied to a production, per item, from Shutter's own store: for Shutter's own production the
/// cases its feed opened, by Receiver (the connector item); for a watched production the cases it forwarded, by
/// SourceRoute (the item that received the message there). {"<item>": {count, unique, byFailureKind, byOutcome,
/// byReasonCode, byState, latest: [caseId...]}, "_total": {...}}; unique counts distinct operations (a reopened case is
/// not a second patient). Never a case's text, its operation key or its failure text: counts and case ids only.
ClassMethod CaseAggregates(namespace As %String, production As %String, own As %Boolean, windowFrom As %String) As %DynamicObject
{
    Set out = {}
    Try {
        Set table = "Shutter_Store.""Case"""
        If own {
            Set col = "Receiver", scope = "(SourceNamespace IS NULL OR SourceNamespace = '') AND OpenedAt >= ?"
            Set args = 1, args(1) = windowFrom
        } Else {
            Set col = "SourceRoute", scope = "SourceNamespace = ? AND SourceProduction = ? AND OpenedAt >= ?"
            Set args = 3, args(1) = namespace, args(2) = production, args(3) = windowFrom
        }
        Set base = args
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT %EXACT(" _ col _ ") AS ItemName, COUNT(*) AS N, COUNT(DISTINCT OperationKey) AS U FROM " _ table _ " WHERE " _ scope _ " GROUP BY %EXACT(" _ col _ ")", args...)
        While rs.%Next() {
            Set a = ..NewAggregate()
            Set a.count = +rs.%Get("N"), a.unique = +rs.%Get("U")
            Do out.%Set(..AggKey(rs.%Get("ItemName")), a)
        }
        For dim = "FailureKind", "FailureOutcome", "FailureReasonCode", "State" {
            Set key = $CASE(dim, "FailureKind": "byFailureKind", "FailureOutcome": "byOutcome", "FailureReasonCode": "byReasonCode", : "byState")
            Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT %EXACT(" _ col _ ") AS ItemName, %EXACT(" _ dim _ ") AS V, COUNT(*) AS N FROM " _ table _ " WHERE " _ scope _ " GROUP BY %EXACT(" _ col _ "), %EXACT(" _ dim _ ")", args...)
            While rs.%Next() {
                Set a = out.%Get(..AggKey(rs.%Get("ItemName")))
                Continue:'$ISOBJECT(a)
                Do a.%Get(key).%Set(..AggKey(rs.%Get("V")), +rs.%Get("N"))
            }
        }
        Set total = ..NewAggregate()
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N, COUNT(DISTINCT OperationKey) AS U FROM " _ table _ " WHERE " _ scope, args...)
        If rs.%Next() Set total.count = +rs.%Get("N"), total.unique = +rs.%Get("U")
        Set iter = out.%GetIterator()
        While iter.%GetNext(.name, .a) {
            // The item's newest cases.
            Set args = base + 1, args(args) = $SELECT(name = "(none)": "", 1: name)
            Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ +..#LATESTCASES _ " CaseId FROM " _ table _ " WHERE " _ scope _ " AND " _ $SELECT(name = "(none)": "(" _ col _ " IS NULL OR " _ col _ " = ?)", 1: col _ " = ?") _ " ORDER BY OpenedAt DESC, ID DESC", args...)
            While rs.%Next() {
                Do a.latest.%Push(rs.%Get("CaseId"))
            }
            Kill args(args)
            Set args = base
            // The production's totals by dimension, summed from the items.
            For key = "byFailureKind", "byOutcome", "byReasonCode", "byState" {
                Set it2 = a.%Get(key).%GetIterator()
                While it2.%GetNext(.v, .n) {
                    Do total.%Get(key).%Set(v, +##class(Shutter.Util.Json).Str(total.%Get(key), v, 0) + n)
                }
            }
        }
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ +..#LATESTCASES _ " CaseId FROM " _ table _ " WHERE " _ scope _ " ORDER BY OpenedAt DESC, ID DESC", args...)
        While rs.%Next() {
            Do total.latest.%Push(rs.%Get("CaseId"))
        }
        Do out.%Set("_total", total)
    } Catch ex {
        Set out."_error" = ex.DisplayString()
        If out.%GetTypeOf("_total") '= "object" Do out.%Set("_total", ..NewAggregate())
    }
    Quit out
}

ClassMethod NewAggregate() As %DynamicObject [ Private ]
{
    Quit {"count": 0, "unique": 0, "byFailureKind": {}, "byOutcome": {}, "byReasonCode": {}, "byState": {}, "latest": []}
}

/// An aggregate's key: the value, or "(none)" for an empty one.
ClassMethod AggKey(value As %String) As %String [ Private ]
{
    Quit $SELECT(value = "": "(none)", 1: value)
}

// ---- fingerprint, rank, annotations ----

/// The configuration fingerprint: the SHA-256 (lower-case hex) of the sorted lines "code|item|setting|found" of the
/// findings whose confidence is confirmed or consistent, the volatile codes left out (Shutter.Review.Checks.VOLATILE),
/// so it moves with a setting value and never with counts, ids or times; "" when there is no such finding.
ClassMethod Fingerprint(findings As %DynamicArray) As %String
{
    Kill lines
    Set n = 0
    Set iter = findings.%GetIterator()
    While iter.%GetNext(.i, .f) {
        Continue:'$LISTFIND($LISTBUILD("confirmed", "consistent"), ##class(Shutter.Util.Json).Str(f, "confidence"))
        Continue:##class(Shutter.Review.Checks).IsVolatile(f.code)
        Set line = ..Line(f.code, f.item, f.setting, f.found)
        Set lines($EXTRACT(line, 1, 300), ..Hex(line)) = line, n = n + 1
    }
    If n = 0 Quit ""
    Set text = "", k1 = ""
    For {
        Set k1 = $ORDER(lines(k1))
        Quit:k1=""
        Set k2 = ""
        For {
            Set k2 = $ORDER(lines(k1, k2))
            Quit:k2=""
            Set text = text _ $SELECT(text = "": "", 1: $CHAR(10)) _ lines(k1, k2)
        }
    }
    Quit ..Hex(text)
}

/// The key an annotation binds to: the SHA-256 hex of "code|item|setting|found".
ClassMethod ValueFingerprint(code As %String, item As %String, setting As %String, found As %String) As %String
{
    Quit ..Hex(..Line(code, item, setting, found))
}

ClassMethod Line(code As %String, item As %String, setting As %String, found As %String) As %String [ Private ]
{
    Quit code _ "|" _ item _ "|" _ setting _ "|" _ found
}

/// The lower-case hex SHA-256 of a string.
ClassMethod Hex(text As %String) As %String [ Private ]
{
    Quit $PIECE(##class(Shutter.Util.Digest).SHA256Hex(text), ":", 2)
}

/// The findings sorted in place by severity tier (high, medium, low, info), then unique cases descending, then the
/// evidence's latest time descending, then code and item; each gets its id, F1 onwards, in that order.
ClassMethod BaselineRank(findings As %DynamicArray)
{
    Kill sorted
    Set n = findings.%Size()
    For i = 0:1:n - 1 {
        Set f = findings.%Get(i)
        Set tier = ##class(Shutter.Review.Checks).Tier(##class(Shutter.Util.Json).Str(f, "severity", "info"))
        Set unique = 0, latest = ""
        If $ISOBJECT(f.%Get("cases")) Set unique = +##class(Shutter.Util.Json).Str(f.cases, "unique", 0)
        If $ISOBJECT(f.%Get("evidence")) Set latest = ##class(Shutter.Util.Json).Str(f.evidence, "latestAt")
        Set seconds = ..Seconds(latest)
        // One composite key whose text order is the rank order: tier, then unique cases and recency descending, then code,
        // item and position (a procedure block's locals cannot be walked with $QUERY, so the key is flat).
        Set key = tier _ "|" _ $TRANSLATE($JUSTIFY(9999999 - unique, 7), " ", "0") _ "|" _ $TRANSLATE($JUSTIFY(99999999999 - +seconds, 11), " ", "0") _ "|" _ ##class(Shutter.Util.Json).Str(f, "code") _ "|" _ ##class(Shutter.Util.Json).Str(f, "item") _ "|" _ $TRANSLATE($JUSTIFY(i, 6), " ", "0")
        Set sorted(key) = i
    }
    Set ordered = []
    Set key = ""
    For {
        Set key = $ORDER(sorted(key))
        Quit:key=""
        Set f = findings.%Get(sorted(key))
        Set f.id = "F" _ (ordered.%Size() + 1)
        Do ordered.%Push(f)
    }
    While findings.%Size() > 0 {
        Do findings.%Remove(0)
    }
    For i = 0:1:ordered.%Size() - 1 {
        Do findings.%Push(ordered.%Get(i))
    }
}

/// Seconds since the epoch of an ISO UTC time (the ODBC form taken too), 0 for none.
ClassMethod Seconds(iso As %String) As %Integer [ Private ]
{
    If iso = "" Quit 0
    Set total = 0
    Try {
        Set h = $ZDATETIMEH($TRANSLATE($PIECE($EXTRACT(iso, 1, 19), "Z", 1), "T", " "), 3, 1)
        Set total = ($PIECE(h, ",", 1) * 86400) + ($PIECE(h, ",", 2) \ 1)
    } Catch ex {
        Set total = 0
    }
    Quit total
}

/// Each finding's status from the annotations: resolver.StatusFor(code, namespace, production, item, setting,
/// valueFingerprint, .annotationId) gives "" for none, else intended, accepted_risk or false_positive, and the finding
/// takes that status and the annotation's id. The resolver is Shutter.Store.ReviewAnnotation; nothing is annotated when
/// that class is not compiled (the tests pass a stub). Returns how many findings carry an annotation.
ClassMethod ApplyAnnotations(findings As %DynamicArray, namespace As %String, production As %String, resolver As %String = "Shutter.Store.ReviewAnnotation") As %Integer
{
    Set n = 0
    If (resolver = "") || '##class(%Dictionary.CompiledClass).%ExistsId(resolver) Quit 0
    Set iter = findings.%GetIterator()
    While iter.%GetNext(.i, .f) {
        Set annotationId = ""
        Set status = $CLASSMETHOD(resolver, "StatusFor", f.code, namespace, production, f.item, f.setting, ..ValueFingerprint(f.code, f.item, f.setting, f.found), .annotationId)
        If status = "" Continue
        Set f.status = status
        Set f.annotationId = annotationId
        Set n = n + 1
    }
    Quit n
}

}
