/// The shadow report: one row per case that reached Shutter in the period, with its latest observation, as CSV and as a
/// summary of counts. Its denominator is cases reaching Shutter, not all failed deliveries: a failure that never became a
/// case is not in it. A resend whose proposal gate passed is a candidate for rehearsal and nothing more: shadow mode tests
/// neither the rehearsal nor the dispatch. The report authorises nothing and writes nothing.
Class Shutter.Util.ShadowReport Extends %RegisteredObject
{

/// The most rows one report holds; a longer period says so in its summary.
Parameter MAXROWS = 5000;

Parameter COLUMNS = "report_id,deployment_id,version,report_cutoff_utc,case_id,opened_at_utc,observation_id,round,observed_at_utc,source_namespace,source_production,source_receiver_item,delivery_header_id,patient_reference,trigger,failure_kind,failure_reason_code,plan_origin,proposed_disposition,catalogue_entry,proposal_gate_result,blocking_reason_codes,candidate_for_rehearsal,rehearsal_performed,final_dispatch_tested,mode,control_generation,recovery_calls_sent,notification_deliveries";

/// The rows for cases opened from <var>from</var> to <var>to</var> (ISO times, either may be empty), optionally of one
/// receiver. truncated is set when there were more than MAXROWS.
ClassMethod Rows(from As %String = "", to As %String = "", receiver As %String = "", Output truncated As %Boolean) As %DynamicArray
{
    Set rows = [], truncated = 0
    Set cutoff = ##class(Shutter.Util.Time).NowUTC(), control = ##class(Shutter.Util.RecoveryControl).Control()
    Set reportId = "SR-" _ $TRANSLATE(cutoff, "-:TZ."), version = $GET(^Shutter.Config("version")), mode = ##class(Shutter.Util.RecoveryControl).Mode()
    // A host variable holding "" reads as NULL in embedded SQL, so an open end is a bound and the receiver is checked below.
    Set low = $SELECT(from = "": "0", 1: from), high = $SELECT(to = "": "9", 1: to)
    &sql(DECLARE ReportCases CURSOR FOR SELECT CaseId, OpenedAt, SourceNamespace, SourceProduction, Receiver, SourceHeaderId, PatientId, PatientIdAuthority, Event, FailureKind, FailureReasonCode, ID
        INTO :caseId, :openedAt, :ns, :prod, :rcv, :header, :patient, :authority, :event, :kind, :reason, :id
        FROM Shutter_Store."Case"
        WHERE OpenedAt >= :low AND OpenedAt <= :high
        ORDER BY OpenedAt, ID)
    &sql(OPEN ReportCases)
    Quit:SQLCODE'=0 rows
    For {
        &sql(FETCH ReportCases)
        Quit:SQLCODE'=0
        Continue:(receiver'="")&&(rcv'=receiver)
        If rows.%Size() >= ..#MAXROWS Set truncated = 1 Quit
        Set r = {}
        Set r."report_id" = reportId, r."deployment_id" = control.DeploymentId, r.version = version, r."report_cutoff_utc" = cutoff
        Set r."case_id" = caseId, r."opened_at_utc" = openedAt, r."source_namespace" = ns, r."source_production" = prod
        Set r."source_receiver_item" = rcv, r."delivery_header_id" = header
        Set r."patient_reference" = ..PatientReference(control.ReportKey, authority, patient)
        Set r.trigger = event, r."failure_kind" = kind, r."failure_reason_code" = reason
        Do ..AddObservation(r, caseId)
        Do ..AddCalls(r, caseId, id)
        Set r.mode = mode, r."control_generation" = $SELECT(r."control_generation" '= "": r."control_generation", 1: control.Generation)
        Do rows.%Push(r)
    }
    &sql(CLOSE ReportCases)
    Quit rows
}

/// A pilot-local token, never the identifier: the same patient reads the same within this deployment and no other. It is
/// keyed by a value the report doesn't print, or anyone holding the report could hash a list of hospital numbers against it.
ClassMethod PatientReference(key As %String, authority As %String, patient As %String) As %String
{
    If ($GET(patient) = "") || ($GET(key) = "") Quit ""
    Quit "P-" _ $EXTRACT(##class(Shutter.Util.Digest).SHA256Hex(key _ "|" _ authority _ "|" _ patient), 1, 16)
}

/// The latest observation of the case, when it has one: an open case that has none stays in the report, unobserved.
ClassMethod AddObservation(r As %DynamicObject, caseId As %String) [ Private ]
{
    For name = "observation_id", "round", "observed_at_utc", "plan_origin", "proposed_disposition", "catalogue_entry", "proposal_gate_result", "blocking_reason_codes", "control_generation" { Do r.%Set(name, "") }
    Set r."candidate_for_rehearsal" = "false"
    Set oid = ""
    &sql(SELECT TOP 1 ID INTO :oid FROM Shutter_Store.ShadowObservation WHERE CaseId = :caseId ORDER BY ID DESC)
    If (SQLCODE '= 0) || (oid = "") Quit
    Set o = ##class(Shutter.Store.ShadowObservation).%OpenId(oid)
    Quit:'$ISOBJECT(o)
    Set r."observation_id" = oid, r.round = o.Round, r."observed_at_utc" = o.ObservedAt, r."plan_origin" = o.PlanOrigin
    Set r."proposed_disposition" = o.Disposition, r."catalogue_entry" = o.CatalogueEntry, r."proposal_gate_result" = o.GateOutcome
    Set r."blocking_reason_codes" = o.BlockingCodes, r."control_generation" = o.ControlGeneration
    Set r."candidate_for_rehearsal" = $SELECT((o.Disposition = "resend") && (o.GateOutcome = "pass"): "true", 1: "false")
}

/// What actually went out for the case, counted from the permits and the escalations, not assumed from the mode.
ClassMethod AddCalls(r As %DynamicObject, caseId As %String, rowId As %String) [ Private ]
{
    Set rehearsals = 0, writes = 0, mails = 0
    &sql(SELECT COUNT(*) INTO :rehearsals FROM Shutter_Store.DispatchPermit WHERE CaseId = :caseId AND ActionKind = 'rehearsal')
    &sql(SELECT COUNT(*) INTO :writes FROM Shutter_Store.DispatchPermit WHERE CaseId = :caseId AND ActionKind = 'recovery')
    &sql(SELECT COUNT(*) INTO :mails FROM Shutter_Store.Escalation WHERE "Case" = :rowId AND State = 'sent')
    Set r."rehearsal_performed" = $SELECT(rehearsals > 0: "true", 1: "false"), r."final_dispatch_tested" = $SELECT(writes > 0: "true", 1: "false")
    Set r."recovery_calls_sent" = rehearsals + writes, r."notification_deliveries" = +mails
}

/// Counts and their denominators, from the rows.
ClassMethod Summary(rows As %DynamicArray, truncated As %Boolean = 0) As %DynamicObject
{
    Set proposed = {"resend": 0, "reconcile": 0, "superseded": 0, "escalate": 0, "more_evidence": 0}
    Set gate = {"pass": 0, "block": 0, "unknown": 0}
    Set observed = 0, candidates = 0, calls = 0, mails = 0, it = rows.%GetIterator()
    While it.%GetNext(, .r) {
        Set calls = calls + r."recovery_calls_sent", mails = mails + r."notification_deliveries"
        Continue:r."observation_id"=""
        Set observed = observed + 1, d = r."proposed_disposition", g = r."proposal_gate_result"
        If d '= "" Do proposed.%Set(d, +proposed.%Get(d) + 1)
        Set g = $SELECT(g = "pass": "pass", g = "": "unknown", g = "unknown": "unknown", 1: "block")
        Do gate.%Set(g, gate.%Get(g) + 1)
        If r."candidate_for_rehearsal" = "true" Set candidates = candidates + 1
    }
    Set o = {}
    Set o.denominator = "cases reaching Shutter"
    Set o.casesReachingShutter = rows.%Size(), o.withObservation = observed, o.unobserved = rows.%Size() - observed
    Set o.proposed = proposed, o.proposalGate = gate, o.candidatesForRehearsal = candidates
    Set o.recoveryCallsSent = calls, o.notificationDeliveries = mails
    Do o.%Set("truncated", ''truncated, "boolean")
    Set o.limits = "Failures that never became a case are not counted. A candidate for rehearsal is a resend proposal whose proposal gate passed: neither a rehearsal nor a dispatch was tested. Nobody has reviewed these proposals here, so this says nothing about whether they were right. This report authorises nothing."
    Quit o
}

/// The rows as CSV, with the header. A value a spreadsheet would read as a formula starts with an apostrophe.
ClassMethod Csv(rows As %DynamicArray) As %String
{
    Set columns = ..#COLUMNS, crlf = $CHAR(13, 10), out = columns _ crlf, it = rows.%GetIterator()
    While it.%GetNext(, .r) {
        Set line = ""
        For i = 1:1:$LENGTH(columns, ",") {
            Set line = line _ $SELECT(i = 1: "", 1: ",") _ ..Cell(r.%Get($PIECE(columns, ",", i)))
        }
        Set out = out _ line _ crlf
    }
    Quit out
}

ClassMethod Cell(value As %String) As %String
{
    Set v = $GET(value)
    If $LENGTH(v) && ("=+-@"_$CHAR(9, 13) [ $EXTRACT(v)) Set v = "'" _ v
    If (v [ ",") || (v [ """") || (v [ $CHAR(10)) || (v [ $CHAR(13)) Set v = """" _ $REPLACE(v, """", """""") _ """"
    Quit v
}

}
