/// The verifier's verdict (Shutter.Operation.Verify.Judge, CONTRACTS 5.1): a pure function of what was read, so every
/// branch is a row of the table in XData Rows. Each row patches the base context (a resend of a transfer whose answer
/// was lost five seconds ago, the encounter at the version the write was conditional on, no receipt) as Shutter.Test.Gate
/// merges patches ("{key}" stands for the case's operation key, null removes a field) and names the outcome, the verdict,
/// whether another read could settle it, and what the text must or must not say. The superseded and reconcile rows pin
/// the wording the recorded scenarios (S1, S3, S6, S7, S11, S20) close with. Nothing is saved and no receiver is read;
/// the one test of Context builds a case in memory.
Class Shutter.Test.Verify Extends %UnitTest.TestCase
{

Parameter NOW = "2026-10-19T09:10:00Z";

Parameter EVENTTIME = "2026-10-19T09:00:00Z";

Method TestUncertainWrite()
{
    Do ..RunRows("uncertain")
}

Method TestAcknowledgedWrite()
{
    Do ..RunRows("acknowledged")
}

Method TestReceiverWithoutReceipts()
{
    Do ..RunRows("no_receipts")
}

Method TestUnreadableLookups()
{
    Do ..RunRows("unreadable")
}

Method TestReconcile()
{
    Do ..RunRows("reconcile")
}

Method TestSuperseded()
{
    Do ..RunRows("superseded")
}

Method TestOtherDispositions()
{
    Do ..RunRows("other")
}

/// "not committed" is written only when it is the verdict: no row's text says it with another outcome.
Method TestNotCommittedIsSaidOnlyWhenItIsTheVerdict()
{
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set r = ..Judge(row)
        Set says = ($ZCONVERT(r.text, "L") [ "not committed")
        Do $$$AssertEquals(says, r.outcome = "not_committed", row.name _ ": 'not committed' is written only as the verdict (" _ r.text _ ")")
    }
}

/// The rows reach every outcome, both answers of retry and every verdict.
Method TestEveryOutcomeIsReached()
{
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set r = ..Judge(row)
        Set seen("outcome", r.outcome) = "", seen("retry", ''r.detail.retry) = "", seen("verdict", r.detail.verdict) = ""
    }
    For outcome = "verified", "not_committed", "unresolved", "failed" { Do $$$AssertTrue($DATA(seen("outcome", outcome)), "an outcome " _ outcome) }
    For verdict = "committed", "not_committed", "unknown" { Do $$$AssertTrue($DATA(seen("verdict", verdict)), "a verdict " _ verdict) }
    Do $$$AssertTrue($DATA(seen("retry", 1)) && $DATA(seen("retry", 0)), "both answers of retry")
}

/// Context reads the later events as the matcher does: the snapshot's timeline against the encounter as read now, with
/// the snapshot's chain kind, so a later transfer the feed sent whose delivery failed supports a superseded closure
/// outside a chain and counts for nothing inside an ordered one.
Method TestContextReadsTheSnapshotsTimeline()
{
    Set case = ..Case()
    Set key = "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z"
    Set summary = {"observed_at": "2026-10-19T13:00:00Z", "catalogue": {"conditions": {"chain": "single"}}}
    Set summary.timeline = [{"later": true, "source": "feed", "outcome": "failed", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "operation_key": (key), "sent_at": "2026-10-19 10:00:00.500", "this_case": false}]
    Set encounter = ..Base().encounter, none = {"error": "no_receipt"}
    Set ctx = ##class(Shutter.Operation.Verify).Context(case, "", "", summary, 200, encounter, 404, none, ..#NOW, 30)
    Do $$$AssertEquals(ctx.disposition, "superseded", "the case's disposition when there is no plan")
    Do $$$AssertEquals(ctx.%GetTypeOf("attempt"), "null", "no attempt")
    Do $$$AssertNotTrue(ctx."closed_by_catalogue", "no plan, so no catalogue closure")
    Do $$$AssertEquals(ctx."settle_seconds", 30, "the settle window")
    Do $$$AssertEquals(ctx.later.%Size(), 1, "the later transfer from the snapshot's timeline")
    If ctx.later.%Size() = 1 {
        Do $$$AssertEquals(ctx.later.%Get(0)."operation_key", key, "named by the key it was sent as")
        Do $$$AssertNotTrue(ctx.later.%Get(0).delivered, "and marked as not delivered")
    }
    Set outcome = ##class(Shutter.Operation.Verify).Judge(ctx, .text, .detail)
    Do $$$AssertEquals(outcome, "verified", "the closure is supported: " _ text)
    Do $$$AssertTrue(text [ "its own case recovers it", "with the gate's wording")
    Do $$$AssertEquals(##class(Shutter.Util.Json).Str(detail.%Get("superseded_by"), "operation_key"), key, "and the detail names the key")
    // The attempt, when the plan wrote.
    Set attempt = ##class(Shutter.Store.ExecutionAttempt).%New()
    Set attempt.Outcome = "uncertain", attempt.At = "2026-10-19T09:09:55Z", attempt.ExpectedVersion = 1, attempt.HttpStatus = 0
    Set ctx = ##class(Shutter.Operation.Verify).Context(case, "", attempt, summary, 200, encounter, 404, none, ..#NOW, 30)
    Do $$$AssertEquals(ctx.attempt.outcome _ " " _ ctx.attempt.at _ " " _ ctx.attempt."expected_version", "uncertain 2026-10-19T09:09:55Z 1", "the attempt's outcome, time and expected version")
    // In an ordered chain the incident sends both in order: the undelivered transfer counts for nothing.
    Set summary.catalogue.conditions.chain = "ordered"
    Set ctx = ##class(Shutter.Operation.Verify).Context(case, "", "", summary, 200, encounter, 404, none, ..#NOW, 30)
    Do $$$AssertEquals(ctx.later.%Size(), 0, "nothing later in an ordered chain")
    Do $$$AssertEquals(##class(Shutter.Operation.Verify).Judge(ctx, .text, .detail), "unresolved", "so nothing supports the supersession: " _ text)
}

/// LaterThan: the latest transfer or discharge after a time, as the committed path cites what followed a write.
Method TestLaterThan()
{
    Set encounter = {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z"}, {"event": "update", "event_time": "2026-10-19T09:30:00Z"}, {"event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z"}]}
    Do $$$AssertEquals(##class(Shutter.Operation.Verify).LaterThan(encounter, ..#EVENTTIME), "transfer to WARD-C at 2026-10-19T10:00:00Z", "the later transfer, not the update")
    Do $$$AssertEquals(##class(Shutter.Operation.Verify).LaterThan(encounter, "2026-10-19T10:00:00Z"), "", "nothing after the last one")
    Do $$$AssertEquals(##class(Shutter.Operation.Verify).LaterThan({}, ..#EVENTTIME), "", "no history")
}

/// Runs the rows of one group and asserts each one's expectations.
Method RunRows(group As %String)
{
    Set json = "Shutter.Util.Json", n = 0
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Continue:(row.group '= group)
        Set n = n + 1
        Set r = ..Judge(row)
        Do $$$AssertEquals(r.outcome, row.outcome, row.name _ ": the outcome" _ $SELECT(r.outcome = row.outcome: "", 1: " (the text: " _ r.text _ ")"))
        If row.%IsDefined("verdict") Do $$$AssertEquals(r.detail.verdict, row.verdict, row.name _ ": the verdict")
        If row.%IsDefined("retry") Do $$$AssertEquals(''r.detail.retry, ''row.retry, row.name _ ": retry")
        If row.%IsDefined("equals") Do $$$AssertEquals(r.text, row.equals, row.name _ ": the text")
        If row.%IsDefined("contains") {
            Set it2 = row.contains.%GetIterator()
            While it2.%GetNext(.j, .s) { Do $$$AssertTrue(r.text [ s, row.name _ ": the text says '" _ s _ "'" _ $SELECT(r.text [ s: "", 1: " (it says: " _ r.text _ ")")) }
        }
        If row.%IsDefined("not_contains") {
            Set it2 = row."not_contains".%GetIterator()
            While it2.%GetNext(.j, .s) { Do $$$AssertNotTrue($ZCONVERT(r.text, "L") [ $ZCONVERT(s, "L"), row.name _ ": the text does not say '" _ s _ "' (it says: " _ r.text _ ")") }
        }
        If row.%IsDefined("detail") {
            Set it2 = row.detail.%GetIterator()
            While it2.%GetNext(.k, .v) {
                If row.detail.%GetTypeOf(k) = "object" {
                    Set inner = r.detail.%Get(k), it3 = v.%GetIterator()
                    While it3.%GetNext(.k2, .v2) { Do $$$AssertEquals($CLASSMETHOD(json, "Str", inner, k2), v2, row.name _ ": detail " _ k _ "." _ k2) }
                } Else {
                    Do $$$AssertEquals($CLASSMETHOD(json, "Str", r.detail, k), v, row.name _ ": detail " _ k)
                }
            }
        }
    }
    Do $$$AssertTrue(n > 0, "the table has rows for " _ group)
}

/// The default window: long enough that a write the receiver commits a minute after the connector gave up is not called
/// not committed, and short enough that the last read, at 10 + 20 + 40 s, can still settle it.
Method TestDefaultSettleWindow()
{
    Set window = +##class(%Dictionary.PropertyDefinition).%OpenId("Shutter.Operation.Verify||UncertainSettleSeconds").InitialExpression
    Do $$$AssertEquals(window, 60, "the default settle window")
    Do $$$AssertTrue(window <= (10 + 20 + 40), "the last read comes after it")
}

/// Judge on the base context with the row's patch: {outcome, text, detail}.
ClassMethod Judge(row As %DynamicObject) As %DynamicObject
{
    Set ctx = ..Base()
    If row.%IsDefined("ctx") Do ##class(Shutter.Test.Gate).Merge(ctx, ##class(Shutter.Test.Gate).Fill(row.ctx, ctx."operation_key"))
    Set outcome = ##class(Shutter.Operation.Verify).Judge(ctx, .text, .detail)
    Quit {"outcome": (outcome), "text": (text), "detail": (detail)}
}

/// The base context: a resend of a transfer whose answer was lost five seconds ago (HTTP status none), conditional on
/// version 1; the receiver holds the encounter admitted in WARD-A at version 1 with the admission alone in its history,
/// and no receipt; nothing later; a settle window of 30 s.
ClassMethod Base() As %DynamicObject
{
    Set key = "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^" _ ..#EVENTTIME
    Set ctx = {
        "disposition": "resend", "event": "transfer", "event_time": (..#EVENTTIME), "operation_key": (key), "encounter_id": "ENC-UT1", "catalogue_entry": "",
        "attempt": {"outcome": "uncertain", "at": "2026-10-19T09:09:55Z", "expected_version": 1, "http_status": 0},
        "encounter_http_status": 200,
        "encounter": {"encounter_id": "ENC-UT1", "patient_id": "MRN-UT1", "patient_id_authority": "HOSP", "state": "admitted", "ward": "WARD-A", "version": 1, "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "applied_at": "2026-10-18T08:00:02Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}]},
        "receipt_http_status": 404, "receipt": {"error": "no_receipt"},
        "closed_by_catalogue": false, "later": [],
        "now": (..#NOW), "settle_seconds": 30
    }
    Quit ctx
}

/// A case in memory (never saved): the base context's transfer, superseded.
ClassMethod Case() As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-VERIFY", case.Event = "transfer", case.FailureKind = "delivery_failed", case.EventTime = ..#EVENTTIME
    Set case.PatientId = "MRN-UT1", case.PatientIdAuthority = "HOSP", case.EncounterId = "ENC-UT1", case.SourceSystem = "PAS", case.Ward = "WARD-B"
    Set case.OperationKey = "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^" _ ..#EVENTTIME
    Set case.Disposition = "superseded"
    Quit case
}

ClassMethod Rows() As %DynamicArray
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Rows")
    Quit ##class(%DynamicArray).%FromJSON(xdata.Data)
}

/// The table: group (the test that runs the row), name, the patch to the base context (ctx), and what Judge must give:
/// outcome, verdict, retry, the text (equals, contains, not_contains) and detail fields.
XData Rows [ MimeType = application/json ]
{
[
  {"group": "uncertain", "name": "no receipt straight after a write whose answer was lost is unknown, and read again",
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["may still be in flight", "5 s after"], "not_contains": ["not committed"],
   "detail": {"attempt_outcome": "uncertain", "seconds_since_attempt": 5, "version_moved": false}},
  {"group": "uncertain", "name": "no receipt after the settle window, the version unchanged, is not committed",
   "ctx": {"attempt": {"at": "2026-10-19T09:09:15Z"}},
   "outcome": "not_committed", "verdict": "not_committed", "retry": false, "contains": ["Not committed: by the last read, 45 s after", "still at version 1", "Nothing shows it was applied", "a slower receiver can still commit it"], "not_contains": ["nothing was applied"],
   "detail": {"seconds_since_attempt": 45, "version_moved": false}},
  {"group": "uncertain", "name": "the version moved past the expected one without our key: not committed",
   "ctx": {"attempt": {"at": "2026-10-19T09:09:15Z"}, "encounter": {"version": 2, "ward": "WARD-D", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-D", "event_time": "2026-10-19T09:05:00Z", "operation_key": "EPR^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T09:05:00Z"}]}},
   "outcome": "not_committed", "verdict": "not_committed", "retry": false, "contains": ["moved from version 1 to 2 by something else", "can no longer apply"],
   "detail": {"version_moved": true}},
  {"group": "uncertain", "name": "inside the window but the version moved: not committed at once",
   "ctx": {"encounter": {"version": 2}},
   "outcome": "not_committed", "verdict": "not_committed", "retry": false, "detail": {"version_moved": true, "seconds_since_attempt": 5}},
  {"group": "uncertain", "name": "a lost answer (HTTP 504) whose receipt is there after all is committed on the first read",
   "ctx": {"attempt": {"http_status": 504}, "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:09:50Z", "version_before": 1, "version_after": 2, "status": "committed"}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "verified", "verdict": "committed", "retry": false, "equals": "Committed and current: receipt 2026-10-19T09:09:50, version 2; the encounter is admitted in WARD-B"},
  {"group": "uncertain", "name": "a committed write followed by a later transfer",
   "ctx": {"receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:09:50Z", "version_before": 1, "version_after": 2, "status": "committed"}, "encounter": {"version": 3, "ward": "WARD-C", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}, {"version_after": 3, "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T09:30:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T09:30:00Z"}]}},
   "outcome": "verified", "verdict": "committed", "equals": "Committed (receipt 2026-10-19T09:09:50, version 2); a later event followed: transfer to WARD-C at 2026-10-19T09:30:00Z. Current state admitted in WARD-C",
   "detail": {"superseded_after": "transfer to WARD-C at 2026-10-19T09:30:00Z"}},
  {"group": "uncertain", "name": "an admission of an encounter the receiver has not got yet: unknown inside the window",
   "ctx": {"event": "admit", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-19T09:00:00Z", "attempt": {"expected_version": 0}, "encounter_http_status": 404, "encounter": {"error": "not_found"}},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "detail": {"version_moved": false}},
  {"group": "uncertain", "name": "the same admission after the window: not committed",
   "ctx": {"event": "admit", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-19T09:00:00Z", "attempt": {"expected_version": 0, "at": "2026-10-19T09:09:15Z"}, "encounter_http_status": 404, "encounter": {"error": "not_found"}},
   "outcome": "not_committed", "verdict": "not_committed", "retry": false, "contains": ["still at version 0"]},
  {"group": "uncertain", "name": "a transfer whose encounter the receiver no longer knows is a person's question",
   "ctx": {"attempt": {"at": "2026-10-19T09:09:15Z"}, "encounter_http_status": 404, "encounter": {"error": "not_found"}},
   "outcome": "unresolved", "verdict": "unknown", "retry": false, "contains": ["no longer knows the encounter"]},
  {"group": "uncertain", "name": "an attempt without a time is never not committed",
   "ctx": {"attempt": {"at": ""}},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["time is not recorded"], "detail": {"seconds_since_attempt": ""}},
  {"group": "uncertain", "name": "an attempt without a time stays unknown even when the version moved",
   "ctx": {"attempt": {"at": ""}, "encounter": {"version": 2}},
   "outcome": "unresolved", "verdict": "unknown", "retry": true},
  {"group": "uncertain", "name": "the settle window is the verifier's setting",
   "ctx": {"attempt": {"at": "2026-10-19T09:09:15Z"}, "settle_seconds": 60},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["45 s after a write whose answer was lost"]},
  {"group": "uncertain", "name": "with that window, the case's last read, at about 70 s, judges",
   "ctx": {"attempt": {"at": "2026-10-19T09:08:50Z"}, "settle_seconds": 60},
   "outcome": "not_committed", "verdict": "not_committed", "retry": false, "contains": ["Not committed: by the last read, 70 s after"]},
  {"group": "uncertain", "name": "a resend with no attempt recorded",
   "ctx": {"attempt": null},
   "outcome": "unresolved", "verdict": "unknown", "retry": false, "contains": ["No attempt is recorded"]},

  {"group": "acknowledged", "name": "an acknowledged write (HTTP 201) without a receipt is a contradiction, never not committed",
   "ctx": {"attempt": {"outcome": "applied", "http_status": 201}},
   "outcome": "failed", "verdict": "unknown", "retry": false, "contains": ["acknowledged the write (HTTP 201)", "contradicts itself"], "not_contains": ["not committed"]},
  {"group": "acknowledged", "name": "an already committed answer without a receipt is a contradiction too",
   "ctx": {"attempt": {"outcome": "already_committed", "http_status": 200}},
   "outcome": "failed", "verdict": "unknown", "retry": false, "contains": ["contradicts itself"]},
  {"group": "acknowledged", "name": "a resend answered already committed, whose receipt names another bed: the write did not take this bed",
   "ctx": {"bed": "B2", "payload_digest": "sha256:ours", "attempt": {"outcome": "already_committed", "http_status": 200}, "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:00:30Z", "version_after": 2, "bed": "B1", "payload_digest": "sha256:ours"}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "failed", "verdict": "unknown", "contains": ["other content", "bed B1"]},
  {"group": "acknowledged", "name": "the history holds the key with another ward than was sent: never verified",
   "ctx": {"ward": "WARD-C", "attempt": {"outcome": "applied", "http_status": 201}, "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:00:30Z", "version_after": 2}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "failed", "verdict": "unknown", "contains": ["history", "WARD-B", "WARD-C", "a person must check"]},
  {"group": "acknowledged", "name": "the history stores the arrival time, not the event's: committed, and it says what was stored",
   "ctx": {"ward": "WARD-B", "attempt": {"outcome": "applied", "http_status": 201}, "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:40:00Z", "version_after": 2}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:40:00Z", "operation_key": "{key}"}]}},
   "outcome": "verified", "verdict": "committed", "contains": ["stored its event time as 2026-10-19T09:40:00Z, not 2026-10-19T09:00:00Z"], "not_contains": ["a later event followed"]},
  {"group": "acknowledged", "name": "a receipt whose operation is missing from the history",
   "ctx": {"attempt": {"outcome": "applied", "http_status": 201}, "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:09:50Z", "version_after": 2}},
   "outcome": "failed", "verdict": "unknown", "retry": false, "contains": ["missing from the committed history"]},
  {"group": "acknowledged", "name": "the history shows the operation but the receiver holds no receipt for it",
   "ctx": {"attempt": {"outcome": "applied", "http_status": 201}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "failed", "verdict": "unknown", "retry": false, "contains": ["history shows the operation but it holds no receipt"]},

  {"group": "no_receipts", "name": "a receiver that keeps no receipts, its history showing the operation: committed",
   "ctx": {"receipt_http_status": -1, "receipt": {}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "verified", "verdict": "committed", "retry": false, "equals": "Committed: the operation is in the receiver's history (the receiver keeps no receipts). Current state admitted, version 2"},
  {"group": "no_receipts", "name": "a receiver that keeps no receipts, its history silent inside the window: unknown",
   "ctx": {"receipt_http_status": -1, "receipt": {}},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["may still be in flight"]},
  {"group": "no_receipts", "name": "a receiver that keeps no receipts, its history silent after the window: not committed",
   "ctx": {"receipt_http_status": -1, "receipt": {}, "attempt": {"at": "2026-10-19T09:09:15Z"}},
   "outcome": "not_committed", "verdict": "not_committed", "retry": false},

  {"group": "unreadable", "name": "the encounter lookup did not answer",
   "ctx": {"encounter_http_status": 0, "encounter": {"error": "connection refused"}},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["could not be read"]},
  {"group": "unreadable", "name": "the receipt lookup did not answer",
   "ctx": {"receipt_http_status": 0, "receipt": {"error": "connection refused"}},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["could not be read"]},
  {"group": "unreadable", "name": "the receipt lookup failed with a status",
   "ctx": {"receipt_http_status": 503, "receipt": {"error": "unavailable"}},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["answered HTTP 503"]},
  {"group": "unreadable", "name": "the encounter lookup failed with a status",
   "ctx": {"encounter_http_status": 503, "encounter": {"error": "unavailable"}},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["could not be read (HTTP 503)"]},
  {"group": "unreadable", "name": "a receipt in hand but the encounter unreadable is read again, not judged",
   "ctx": {"encounter_http_status": 503, "encounter": {"error": "unavailable"}, "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:09:50Z", "version_after": 2}},
   "outcome": "unresolved", "verdict": "unknown", "retry": true},

  {"group": "reconcile", "name": "reconcile, with the receipt and the history agreeing",
   "ctx": {"disposition": "reconcile", "attempt": null, "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:00:30Z", "version_before": 1, "version_after": 2, "status": "committed"}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "verified", "verdict": "committed", "retry": false, "equals": "Committed and current: receipt 2026-10-19T09:00:30, version 2; the encounter is admitted in WARD-B"},
  {"group": "reconcile", "name": "reconcile whose receipt is gone says nothing about what was committed",
   "ctx": {"disposition": "reconcile", "attempt": null},
   "outcome": "failed", "verdict": "unknown", "retry": false, "contains": ["Nothing to reconcile", "though the evidence showed one"], "not_contains": ["not committed"]},
  {"group": "reconcile", "name": "reconcile with a receiver that keeps no receipts and a history that no longer shows the operation",
   "ctx": {"disposition": "reconcile", "attempt": null, "receipt_http_status": -1, "receipt": {}},
   "outcome": "failed", "verdict": "unknown", "retry": false, "contains": ["Nothing to reconcile", "keeps no receipts"]},
  {"group": "reconcile", "name": "reconcile, the receipt's digest the case's own: committed",
   "ctx": {"disposition": "reconcile", "attempt": null, "payload_digest": "sha256:ours", "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:00:30Z", "version_after": 2, "payload_digest": "sha256:ours"}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "verified", "verdict": "committed"},
  {"group": "reconcile", "name": "reconcile, the receipt holding other content under the key: never verified",
   "ctx": {"disposition": "reconcile", "attempt": null, "ward": "WARD-C", "payload_digest": "sha256:ours", "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:00:30Z", "version_after": 2, "ward": "WARD-B", "payload_digest": "sha256:theirs"}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "failed", "verdict": "unknown", "retry": false, "contains": ["other content", "WARD-B", "WARD-C", "a person must check"], "not_contains": ["Committed and current", "not committed"]},
  {"group": "reconcile", "name": "reconcile, the receipt naming another bed under the same digest: never verified",
   "ctx": {"disposition": "reconcile", "attempt": null, "bed": "B2", "payload_digest": "sha256:ours", "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:00:30Z", "version_after": 2, "bed": "B1", "payload_digest": "sha256:ours"}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "failed", "verdict": "unknown", "retry": false, "contains": ["other content", "bed B1", "B2"]},
  {"group": "reconcile", "name": "a site that asks for answers on status alone: the digests are not compared",
   "ctx": {"disposition": "reconcile", "attempt": null, "strict_answers": false, "payload_digest": "sha256:ours", "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:00:30Z", "version_after": 2, "payload_digest": "sha256:theirs"}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "verified", "verdict": "committed"},
  {"group": "reconcile", "name": "a receipt with no digest and no bed has nothing to compare: committed, as before",
   "ctx": {"disposition": "reconcile", "attempt": null, "payload_digest": "sha256:ours", "bed": "B2", "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:00:30Z", "version_after": 2}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "verified", "verdict": "committed"},
  {"group": "reconcile", "name": "reconcile with a receiver that keeps no receipts, its history showing the operation",
   "ctx": {"disposition": "reconcile", "attempt": null, "receipt_http_status": -1, "receipt": {}, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}},
   "outcome": "verified", "verdict": "committed"},

  {"group": "superseded", "name": "superseded, the receiver's history showing the later transfer and no receipt (S1, S7, S11, S20)",
   "ctx": {"disposition": "superseded", "attempt": null, "encounter": {"ward": "WARD-C", "version": 2},
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "from": "history", "delivered": true, "plausible": true, "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z"}]},
   "outcome": "verified", "verdict": "not_committed", "retry": false, "equals": "Nothing was resent; the receiver's history shows the later event (transfer to WARD-C at 2026-10-19T10:00:00Z) and no receipt for the stale operation. Current state admitted in WARD-C"},
  {"group": "superseded", "name": "superseded, the receiver's history showing a later discharge (S6)",
   "ctx": {"disposition": "superseded", "attempt": null, "encounter": {"state": "discharged", "ward": "", "version": 2},
           "later": [{"word": "discharge", "event": "discharge", "ward": "", "event_time": "2026-10-19T11:00:00Z", "from": "history", "delivered": true, "plausible": true, "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^discharge^2026-10-19T11:00:00Z"}]},
   "outcome": "verified", "verdict": "not_committed", "equals": "Nothing was resent; the receiver's history shows the later event (discharge at 2026-10-19T11:00:00Z) and no receipt for the stale operation. Current state discharged"},
  {"group": "superseded", "name": "the last plausible later movement in the history is the one cited",
   "ctx": {"disposition": "superseded", "attempt": null,
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "from": "history", "delivered": true, "plausible": true}, {"word": "transfer", "event": "transfer", "ward": "WARD-D", "event_time": "2026-10-19T10:30:00Z", "from": "history", "delivered": true, "plausible": true}, {"word": "transfer", "event": "transfer", "ward": "WARD-E", "event_time": "2026-10-20T10:30:00Z", "from": "history", "delivered": true, "plausible": false}]},
   "outcome": "verified", "contains": ["(transfer to WARD-D at 2026-10-19T10:30:00Z)"]},
  {"group": "superseded", "name": "superseded, but the stale operation has a receipt after all",
   "ctx": {"disposition": "superseded", "attempt": null, "receipt_http_status": 200, "receipt": {"operation_key": "{key}", "applied_at": "2026-10-19T09:00:30Z", "version_after": 2},
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "from": "history", "delivered": true, "plausible": true}]},
   "outcome": "failed", "verdict": "committed", "retry": false, "equals": "The stale operation has a receipt after all: it was committed"},
  {"group": "superseded", "name": "a catalogue entry closes the case with nothing to send (CLOSED_BY_CATALOGUE)",
   "ctx": {"disposition": "superseded", "attempt": null, "closed_by_catalogue": true, "catalogue_entry": "E6"},
   "outcome": "verified", "verdict": "not_committed", "retry": false, "equals": "Nothing was resent; catalogue entry E6 closes the case with nothing to send, and the receiver holds neither a receipt nor the operation in its history. Current state admitted in WARD-A"},
  {"group": "superseded", "name": "a later transfer the feed sent whose delivery failed supports the closure, in the gate's words",
   "ctx": {"disposition": "superseded", "attempt": null,
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "from": "timeline", "delivered": false, "plausible": true, "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z"}]},
   "outcome": "verified", "verdict": "not_committed", "retry": false,
   "equals": "Nothing was resent; the receiver's history shows no later event, but the feed sent one after it: transfer to WARD-C at 2026-10-19T10:00:00Z, sent as PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z (its delivery failed or is uncertain; its own case recovers it). The receiver holds no receipt for the stale operation. Current state admitted in WARD-A",
   "detail": {"superseded_by": {"operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z", "case_id": ""}}},
  {"group": "superseded", "name": "the undelivered later transfer's case is named when it is known",
   "ctx": {"disposition": "superseded", "attempt": null,
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "from": "timeline", "delivered": false, "plausible": true, "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z", "case_id": "C-000099"}]},
   "outcome": "verified", "contains": ["its case C-000099 recovers it"], "detail": {"superseded_by": {"case_id": "C-000099"}}},
  {"group": "superseded", "name": "the undelivered later transfer is cited before the catalogue closure, in the gate's order",
   "ctx": {"disposition": "superseded", "attempt": null, "closed_by_catalogue": true, "catalogue_entry": "E1",
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "from": "timeline", "delivered": false, "plausible": true, "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z"}]},
   "outcome": "verified", "contains": ["its own case recovers it"], "not_contains": ["catalogue entry E1"]},
  {"group": "superseded", "name": "an undelivered later transfer whose time is not plausible supports nothing",
   "ctx": {"disposition": "superseded", "attempt": null,
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-20T10:00:00Z", "from": "timeline", "delivered": false, "plausible": false, "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-20T10:00:00Z"}]},
   "outcome": "unresolved", "verdict": "unknown", "retry": false, "equals": "No later event in the receiver's history supports the supersession"},
  {"group": "superseded", "name": "a later transfer in the history whose time is not plausible supports nothing, as the gate refused it",
   "ctx": {"disposition": "superseded", "attempt": null,
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-20T10:00:00Z", "from": "history", "delivered": true, "plausible": false}]},
   "outcome": "unresolved", "retry": false},
  {"group": "superseded", "name": "a later transfer applied in the timeline but absent from the receiver's history as read now supports nothing",
   "ctx": {"disposition": "superseded", "attempt": null,
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "from": "timeline", "delivered": true, "plausible": true}]},
   "outcome": "unresolved", "retry": false},
  {"group": "superseded", "name": "a later cancel alone supports no superseded closure: the closure rests on a transfer or a discharge",
   "ctx": {"disposition": "superseded", "attempt": null,
           "later": [{"word": "cancelled", "event": "cancel_transfer", "ward": "", "event_time": "2026-10-19T09:00:00Z", "from": "history", "delivered": true, "plausible": true}]},
   "outcome": "unresolved", "retry": false},
  {"group": "superseded", "name": "an undelivered later transfer while the stale operation is in the history after all",
   "ctx": {"disposition": "superseded", "attempt": null, "encounter": {"version": 2, "ward": "WARD-B", "history": [{"version_after": 1, "event": "admit", "ward": "WARD-A", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}, {"version_after": 2, "event": "transfer", "ward": "WARD-B", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]},
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "from": "timeline", "delivered": false, "plausible": true}]},
   "outcome": "unresolved", "retry": false},
  {"group": "superseded", "name": "superseded, with the encounter unreadable: read again",
   "ctx": {"disposition": "superseded", "attempt": null, "encounter_http_status": 503, "encounter": {"error": "unavailable"}},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["could not be read (HTTP 503)"]},
  {"group": "superseded", "name": "superseded, with an encounter the receiver does not know: a person decides",
   "ctx": {"disposition": "superseded", "attempt": null, "encounter_http_status": 404, "encounter": {"error": "not_found"}},
   "outcome": "unresolved", "retry": false},
  {"group": "superseded", "name": "a patient-level case names no encounter to verify against",
   "ctx": {"disposition": "superseded", "attempt": null, "encounter_id": "-", "encounter_http_status": 404, "encounter": {"note": "Not applicable: the case names no encounter"}},
   "outcome": "unresolved", "retry": false, "contains": ["patient-level"]},

  {"group": "other", "name": "an escalation has nothing to verify at the receiver",
   "ctx": {"disposition": "escalate", "attempt": null},
   "outcome": "unresolved", "verdict": "unknown", "retry": false, "equals": "Disposition escalate: nothing to verify at the receiver"},
  {"group": "other", "name": "the receiver could not be read at all, whatever the disposition",
   "ctx": {"disposition": "escalate", "attempt": null, "receipt_http_status": 0},
   "outcome": "unresolved", "retry": true}
]
}

}
  {"group": "superseded", "name": "a catalogue closure with the receipt lookup failing is read again, and says no receipt nowhere",
   "ctx": {"disposition": "superseded", "attempt": null, "closed_by_catalogue": true, "catalogue_entry": "E6", "receipt_http_status": 503, "receipt": {"error": "unavailable"}},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["answered HTTP 503"], "not_contains": ["no receipt", "neither a receipt"]},
  {"group": "superseded", "name": "an undelivered later transfer with the receipt lookup failing is read again",
   "ctx": {"disposition": "superseded", "attempt": null, "receipt_http_status": 503, "receipt": {"error": "unavailable"},
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "from": "timeline", "delivered": false, "plausible": true, "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z"}]},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["answered HTTP 503"], "not_contains": ["no receipt"]},
  {"group": "superseded", "name": "a later transfer in the history with the receipt lookup failing is read again, not told there is no later event",
   "ctx": {"disposition": "superseded", "attempt": null, "receipt_http_status": 503, "receipt": {"error": "unavailable"},
           "later": [{"word": "transfer", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "from": "history", "delivered": true, "plausible": true}]},
   "outcome": "unresolved", "verdict": "unknown", "retry": true, "contains": ["answered HTTP 503"], "not_contains": ["No later event"]},
