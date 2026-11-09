/// What each receiver in the site profile last answered, for the Doctor and the health route (CONTRACTS 12): from what the
/// connector's results and the evidence's reads already record. It never calls a receiver, so the time of the reading is
/// part of the answer: a receiver that died after its last reading still reads as it last answered, until something reads it.
/// The health route's ok stays the production's, since a container's health must not turn on another system's.
Class Shutter.Util.ReceiverHealth
{

/// How many of the connector's newest results are looked through, for the newest real attempt and the newest answer.
Parameter CONNECTORROWS = 10;

/// How many of the receiver's newest cases are looked through for the evidence's read.
Parameter EVIDENCECASES = 5;

/// How far back a delivery failure counts for a receiver with nothing else to go on, in seconds.
Parameter FAILUREWINDOW = 3600;

/// Adds to the Doctor's report: receivers, receivers_ok, receivers_state and watched_ok.
ClassMethod AddTo(report As %DynamicObject)
{
    Set health = ..Report()
    Set report.receivers = health.receivers, report."receivers_state" = health.state
    Set ok = health.ok
    If ok = "" { Do report.%Set("receivers_ok", "", "null") } Else { Do report.%Set("receivers_ok", ok, "boolean") }
    Do report.%Set("watched_ok", ..AllWell(report.%Get("watched_namespaces")), "boolean")
}

/// {receivers: [{name, has_api, state, at, http_status, from, error, last_answer_at, last_failure_at, failures_hour, incident}],
/// ok, state}. ok is "" when nothing is known: the reading failed, or no receiver has been read and none is failing. state is
/// "read", or "error: ...".
ClassMethod Report() As %DynamicObject
{
    Set out = {"receivers": [], "state": "read"}
    Set verdicts = ""
    Try {
        Set list = ##class(Shutter.Store.SiteProfile).Current().%Get("receivers")
        If $ISOBJECT(list) {
            Set it = list.%GetIterator()
            While it.%GetNext(, .entry) {
                Continue:'$ISOBJECT(entry)
                Set one = ..Receiver(##class(Shutter.Util.Json).Str(entry, "name"), $ISOBJECT(entry.%Get("api")))
                Do out.receivers.%Push(one)
                Set verdicts = verdicts _ $LISTBUILD(one.state)
            }
        }
    } Catch ex {
        Set out.state = "error: " _ ex.DisplayString(), verdicts = ""
    }
    Set out.ok = ..Overall(verdicts)
    Quit out
}

/// One receiver: its newest reading, what has failed since, and the incident holding its failures.
ClassMethod Receiver(name As %String, hasApi As %Boolean) As %DynamicObject
{
    Set one = {"name": (name), "at": "", "from": "", "error": "", "last_answer_at": "", "last_failure_at": "", "incident": ""}
    Do one.%Set("has_api", ''hasApi, "boolean"), one.%Set("http_status", "", "null")
    Set status = "", failures = 0
    Try {
        Do ..NewestReading(name, .at, .status, .from, .error, .answered)
        Set one.at = at, one.from = from, one.error = $EXTRACT(error, 1, 200), one."last_answer_at" = answered
        If at '= "" Do one.%Set("http_status", +status, "number")
        Set since = ##class(Shutter.Util.Time).FromNow(-..#FAILUREWINDOW)
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 OpenedAt FROM Shutter_Store.""Case"" WHERE Receiver = ? AND FailureKind = 'delivery_failed' ORDER BY ID DESC", name)
        If rs.%Next() Set one."last_failure_at" = rs.%Get("OpenedAt")
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N FROM Shutter_Store.""Case"" WHERE Receiver = ? AND FailureKind = 'delivery_failed' AND OpenedAt >= ?", name, since)
        If rs.%Next() Set failures = +rs.%Get("N")
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 IncidentId FROM Shutter_Store.Incident WHERE Receiver = ? AND State <> 'closed' ORDER BY ID DESC", name)
        If rs.%Next() Set one.incident = rs.%Get("IncidentId")
    } Catch ex {
        Set one.error = $EXTRACT(ex.DisplayString(), 1, 200)
    }
    Set one."failures_hour" = failures
    Set one.state = ..Judge(hasApi, one.at, status, one."last_failure_at", failures)
    Quit one
}

/// A receiver's state from its reading: no_answer, server_error, refused (401 or 403), failing (a delivery failed after its
/// newest answer, or in the last hour when nothing has read it), answering, not_read, or no_api (nothing can read it and nothing
/// has failed lately). Any other answer is an answer: a 404 for an unknown encounter, or a 409, came from a live receiver.
ClassMethod Judge(hasApi As %Boolean, at As %String, status As %String, lastFailureAt As %String, failuresHour As %Integer) As %String
{
    If at = "" Quit $SELECT(failuresHour > 0: "failing", hasApi: "not_read", 1: "no_api")
    If +status = 0 Quit "no_answer"
    If +status >= 500 Quit "server_error"
    If (+status = 401) || (+status = 403) Quit "refused"
    If lastFailureAt ] at Quit "failing"
    Quit "answering"
}

/// Whether the receivers are well: 0 when any is in trouble, 1 when none is and at least one answered, "" when nothing is known.
ClassMethod Overall(states As %List) As %String
{
    Set answering = 0, bad = 0
    For i = 1:1:$LISTLENGTH(states) {
        Set state = $LIST(states, i)
        If $LISTFIND($LISTBUILD("no_answer", "server_error", "refused", "failing"), state) Set bad = 1
        If state = "answering" Set answering = 1
    }
    Quit $SELECT(bad: 0, answering: 1, 1: "")
}

/// Whether every watched namespace reads ok: true with none.
ClassMethod AllWell(watched As %DynamicArray) As %Boolean
{
    If '$ISOBJECT(watched) Quit 1
    Set it = watched.%GetIterator()
    While it.%GetNext(, .w) { If $ISOBJECT(w) && 'w.ok Return 0 }
    Quit 1
}

/// The newest real reading of a receiver, by the connector or by the evidence, and the newest time either got an answer.
ClassMethod NewestReading(name As %String, Output at As %String, Output status As %String, Output from As %String, Output error As %String, Output answered As %String) [ Private ]
{
    Set (at, status, from, error, answered) = ""
    Do ..FromConnector(name, .at, .status, .error, .answered)
    If at '= "" Set from = "connector"
    Do ..FromEvidence(name, .eat, .estatus, .eerror, .eanswered)
    If eat ] at Set at = eat, status = estatus, error = eerror, from = "evidence"
    If eanswered ] answered Set answered = eanswered
}

/// The connector's own results, through the header table: a result that made no call (a refused dry run, a guard's refusal
/// before the write) says nothing about the receiver.
ClassMethod FromConnector(name As %String, Output at As %String, Output status As %String, Output error As %String, Output answered As %String) [ Private ]
{
    Set (at, status, error, answered) = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP "_(+..#CONNECTORROWS)_" h.TimeCreated AS T, w.HttpStatus AS S, w.Outcome AS O, w.ReasonCode AS R, w.Error AS E FROM Ens.MessageHeader h, Shutter_Msg.WardResult w WHERE h.SourceConfigName = ? AND h.MessageBodyClassName = 'Shutter.Msg.WardResult' AND w.ID = h.MessageBodyId ORDER BY h.ID DESC", name)
    While rs.%Next() {
        If (rs.%Get("O") = "refused") && $LISTFIND($LISTBUILD("dry_run_unsupported", "newer_message_pending"), rs.%Get("R")) Continue
        Set when = $TRANSLATE($EXTRACT(rs.%Get("T"), 1, 19), " ", "T") _ "Z"
        If at = "" Set at = when, status = +rs.%Get("S"), error = rs.%Get("E")
        If +rs.%Get("S") > 0 { Set answered = when Quit }
    }
}

/// The evidence's read of the encounter (the snapshot's ward_state item) on the receiver's newest cases, by its status alone: the
/// body is a patient's state and goes no further. A case with no encounter, or a profile with no state path, read nothing.
ClassMethod FromEvidence(name As %String, Output at As %String, Output status As %String, Output error As %String, Output answered As %String) [ Private ]
{
    Set (at, status, error, answered) = ""
    Set cases = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP "_(+..#EVIDENCECASES)_" ID FROM Shutter_Store.""Case"" WHERE Receiver = ? ORDER BY ID DESC", name)
    While cases.%Next() {
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 i.ObservedAt AS T, i.Json AS J FROM Shutter_Store.SnapshotItem i, Shutter_Store.Snapshot s WHERE i.Snapshot = s.ID AND s.""Case"" = ? AND i.Kind = 'ward_state' ORDER BY s.Seq DESC", cases.%Get("ID"))
        Continue:'rs.%Next()
        Set item = ##class(Shutter.Util.Json).Parse(rs.%Get("J"), .psc)
        Continue:'$ISOBJECT(item)
        Continue:##class(Shutter.Util.Json).Bool(item, "not_applicable", 0)
        Set code = +##class(Shutter.Util.Json).Str(item, "http_status"), said = ""
        Set body = item.%Get("body")
        If $ISOBJECT(body) && 'code Set said = ##class(Shutter.Util.Json).Str(body, "error")
        Continue:said["no state endpoint"
        Set when = rs.%Get("T")
        If when ] at Set at = when, status = code, error = said
        If code && (when ] answered) Set answered = when
    }
}

}
