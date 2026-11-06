/// The matcher's condition vocabulary (Shutter.Catalogue.Matcher.Conditions, CONTRACTS 6.1): a pure function of the
/// case and the snapshot summary. Every row of the table in XData Rows changes a transfer whose evidence is plain (the
/// receiver unavailable, the encounter admitted, nothing later, the times in order) and names the conditions it expects;
/// "case" and "summary" are merged into the defaults as Shutter.Test.Gate merges them. The cases are never saved. The
/// table reaches every value of every condition, and the vocabulary is the one scripts/build-catalogue.py checks the
/// catalogue's patterns against.
Class Shutter.Test.Matcher Extends %UnitTest.TestCase
{

Parameter EVENTTIME = "2026-10-19T09:00:00Z";

/// The vocabulary, as scripts/build-catalogue.py has it (CONDITIONS).
ClassMethod Vocabulary() As %DynamicObject
{
    Quit {
        "event": ["admit", "transfer", "discharge", "update", "merge", "cancel", "other"],
        "delivery": ["failed", "rejected", "uncertain", "unmappable", "withheld", "unreadable"],
        "receiver_answer": ["unavailable", "timeout", "duplicate", "version_conflict", "refused", "none"],
        "receipt": ["present", "absent", "unreadable", "none"],
        "later_applied": ["none", "transfer", "discharge", "update", "admit", "cancelled", "cancel_other", "merge"],
        "later_delivery": ["applied", "sent", "none"],
        "event_time": ["plausible", "before_admission", "future", "far_from_recorded", "clock_change", "later_event_future"],
        "encounter_state": ["admitted", "discharged", "not_found", "unknown"],
        "transition": ["allowed", "invalid", "unknown"],
        "patient_match": ["yes", "no", "unknown"],
        "simultaneous_sources": ["yes", "no"],
        "conditional_writes": ["yes", "no", "unknown"],
        "free_text": ["yes", "no"],
        "chain": ["single", "ordered", "interleaved"],
        "receiver_category": ["current_state", "history_of_record", "orders_results"],
        "bed_conflict": ["none", "occupant_leaving", "occupant_left", "occupant_staying", "unknown"]
    }
}

/// The stored site profile's text before the tests added their receivers, and whether there was a stored row.
Property SavedProfile As %String;

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

/// Two receivers for the tests' duration, one of each category the default receiver is not: UT Records
/// (history_of_record) and UT Orders (orders_results), beside the profile's own receivers. Put back afterwards.
Method OnBeforeAllTests() As %Status
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set ..HadProfileRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: "")
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    Do p.receivers.%Push({"name": "UT Records", "system": "a records system for the tests", "category": "history_of_record", "tier": 2})
    Do p.receivers.%Push({"name": "UT Orders", "system": "an orders system for the tests", "category": "orders_results", "tier": 2})
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Version = version
    Set row.Json = p.%ToJSON()
    Quit row.%Save()
}

Method OnAfterAllTests() As %Status
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If ..HadProfileRow {
        If $ISOBJECT(row) Set row.Json = ..SavedProfile Do row.%Save()
    } ElseIf $ISOBJECT(row) {
        Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    }
    Quit $$$OK
}

Method TestDelivery()
{
    Do ..RunRows("delivery")
}

Method TestReceiverAnswer()
{
    Do ..RunRows("receiver_answer")
}

Method TestEvent()
{
    Do ..RunRows("event")
}

Method TestReceipt()
{
    Do ..RunRows("receipt")
}

Method TestLaterApplied()
{
    Do ..RunRows("later_applied")
}

Method TestEventTime()
{
    Do ..RunRows("event_time")
}

Method TestEncounterStateAndPatient()
{
    Do ..RunRows("encounter")
}

Method TestTransition()
{
    Do ..RunRows("transition")
}

Method TestSimultaneousSources()
{
    Do ..RunRows("simultaneous_sources")
}

/// The occupied bed (v1.28): the condition is the status of the section the evidence adds to a bed_occupied refusal, none
/// without one; the fact occupant_case names the case about the occupant's movement out.
Method TestBedConflict()
{
    Do ..RunRows("bed_conflict")
    Set case = ..Case({"failure_kind": "rejected"})
    Set summary = ..Summary({"summary": {"bed_conflict": {"refused": true, "status": "occupant_leaving", "occupant": {"encounter_id": "ENC-OCC"}, "occupant_movement": {"event": "transfer", "delivery": "failed", "case_id": "C-000041"}}}}, case)
    Set facts = ##class(Shutter.Catalogue.Matcher).Facts(summary, case)
    Do $$$AssertEquals(facts."occupant_case", "C-000041", "the fact names the occupant's case")
    Set facts = ##class(Shutter.Catalogue.Matcher).Facts(..Summary({"summary": {}}, case), case)
    Do $$$AssertEquals(facts."occupant_case", "", "and is empty without a conflict")
}

Method TestCapabilitiesFreeTextChain()
{
    Do ..RunRows("other")
}

/// An alert-only failure (the alert intake's reason code "alert", a 503 read from the alert's words) matches E4 in an
/// ordered chain, as a failure the connector recorded with ward_unavailable does: the reason code names no answer of the
/// receiver's, so the status decides and the case is not a new pattern.
Method TestAlertReasonReadsAsOutage()
{
    Set alert = ..Conditions({"chain": "ordered", "summary": {"failure": {"reason_code": "alert", "http_status": 503}}})
    Set recorded = ..Conditions({"chain": "ordered"})
    Do $$$AssertEquals(alert."receiver_answer", "unavailable", "the alert's 503 reads as the receiver unavailable")
    Do $$$AssertEquals(alert."receiver_answer", recorded."receiver_answer", "the same answer as the connector's ward_unavailable")
    Set alertMatch = ##class(Shutter.Catalogue.Matcher).Match(alert)
    Set recordedMatch = ##class(Shutter.Catalogue.Matcher).Match(recorded)
    Do $$$AssertEquals(recordedMatch.entry, "E4", "the recorded outage matches E4")
    Do $$$AssertEquals(alertMatch.entry, "E4", "the alert matches E4 too")
    Do $$$AssertEquals(alertMatch.decision, recordedMatch.decision, "the same decision")
    Do $$$AssertEquals(alertMatch.outcome, "resend_chain", "the resend chain")
}

/// Every condition the matcher computes is in the vocabulary with one of its values, and the rows reach every value.
Method TestEveryValueIsReached()
{
    Set vocabulary = ..Vocabulary(), seen = "", stray = ""
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set c = ..Conditions(row)
        Set it2 = c.%GetIterator()
        While it2.%GetNext(.name, .value) {
            If '..InList(vocabulary.%Get(name), value) Set stray = stray _ $SELECT(stray = "": "", 1: ", ") _ name _ "=" _ value _ " (" _ row.name _ ")"
            Set seen(name, value) = ""
        }
        // Every name of the vocabulary is computed for every case.
        Set it2 = vocabulary.%GetIterator()
        While it2.%GetNext(.name, .values) { If 'c.%IsDefined(name) Set stray = stray _ $SELECT(stray = "": "", 1: ", ") _ name _ " missing (" _ row.name _ ")" }
    }
    Do $$$AssertEquals(stray, "", "every computed condition is a name and a value of the vocabulary" _ $SELECT(stray = "": "", 1: ": " _ stray))
    Set missing = ""
    Set iter = vocabulary.%GetIterator()
    While iter.%GetNext(.name, .values) {
        Set it2 = values.%GetIterator()
        While it2.%GetNext(.j, .value) { If '$DATA(seen(name, value)) Set missing = missing _ $SELECT(missing = "": "", 1: ", ") _ name _ "=" _ value }
    }
    Do $$$AssertEquals(missing, "", "the rows reach every value" _ $SELECT(missing = "": "", 1: "; not reached: " _ missing))
}

/// The vocabulary above is the one the catalogue's builder checks the entries against (read from the repository when
/// the tests run from it).
Method TestVocabularyIsTheBuilders()
{
    Set path = $PIECE($GET(^UnitTestRoot), "tests/unit/", 1) _ "scripts/build-catalogue.py"
    If ($GET(^UnitTestRoot) = "") || '##class(%File).Exists(path) {
        Do $$$LogMessage("scripts/build-catalogue.py is not on the mounted path; the vocabulary was not compared")
        Quit
    }
    Set file = ##class(%Stream.FileCharacter).%New()
    Set file.Filename = path
    Set builder = {}, inside = 0
    While 'file.AtEnd {
        Set line = file.ReadLine()
        If $EXTRACT(line, 1, 14) = "CONDITIONS = {" Set inside = 1 Continue
        Continue:'inside
        Quit:($EXTRACT(line, 1) = "}")
        Set m = ##class(%Regex.Matcher).%New("^\s*""(\w+)"": \{(.*)\},?\s*$", line)
        Continue:'m.Match()
        Set name = m.Group(1), values = [], v = ##class(%Regex.Matcher).%New("""(\w+)""", m.Group(2))
        While v.Locate() { Do values.%Push(v.Group(1)) }
        Do builder.%Set(name, values)
    }
    Do $$$AssertEquals(..Canonical(builder), ..Canonical(..Vocabulary()), "the builder's CONDITIONS and the test's vocabulary agree")
}

/// Holds: every listed condition must have one of its allowed values; a pattern that is not an object never holds.
Method TestHolds()
{
    Set c = {"event": "transfer", "receipt": "absent", "chain": "single"}
    Do $$$AssertTrue(##class(Shutter.Catalogue.Matcher).Holds({"event": "transfer"}, c), "a single value")
    Do $$$AssertTrue(##class(Shutter.Catalogue.Matcher).Holds({"event": ["admit", "transfer"], "receipt": "absent"}, c), "a list and a value")
    Do $$$AssertNotTrue(##class(Shutter.Catalogue.Matcher).Holds({"event": ["admit", "discharge"]}, c), "a list without the value")
    Do $$$AssertNotTrue(##class(Shutter.Catalogue.Matcher).Holds({"event": "transfer", "receipt": "present"}, c), "one condition that does not hold")
    Do $$$AssertNotTrue(##class(Shutter.Catalogue.Matcher).Holds({"delivery": "failed"}, c), "a condition the case does not show")
    Do $$$AssertNotTrue(##class(Shutter.Catalogue.Matcher).Holds("", c), "no pattern")
}

/// WhenHolds: "always" or a site flag's value; "other_source" stands for the fact, and an empty one never holds.
Method TestWhenHolds()
{
    Do $$$AssertTrue(##class(Shutter.Catalogue.Matcher).WhenHolds("always", {}), "always")
    Do $$$AssertTrue(##class(Shutter.Catalogue.Matcher).WhenHolds("", {}), "no when")
    Do $$$AssertNotTrue(##class(Shutter.Catalogue.Matcher).WhenHolds("authoritative_source: other_source", {"other_source": ""}), "no other source")
    Set flag = ##class(Shutter.Store.SiteProfile).Flag("history_policy")
    If flag '= "" {
        Do $$$AssertTrue(##class(Shutter.Catalogue.Matcher).WhenHolds("history_policy: " _ flag, {}), "the site's own history policy")
        Do $$$AssertNotTrue(##class(Shutter.Catalogue.Matcher).WhenHolds("history_policy: not-" _ flag, {}), "another history policy")
    }
    // The facts carry the case's receiver's policy and category (v1.23), which answer before the site-wide flag.
    Do $$$AssertTrue(##class(Shutter.Catalogue.Matcher).WhenHolds("history_policy: correct", {"history_policy": "correct"}), "the receiver keeps its history: the when holds")
    Do $$$AssertNotTrue(##class(Shutter.Catalogue.Matcher).WhenHolds("history_policy: correct", {"history_policy": "current"}), "the receiver keeps what is current: it does not")
    Do $$$AssertTrue(##class(Shutter.Catalogue.Matcher).WhenHolds("receiver_category: history_of_record", {"receiver_category": "history_of_record"}), "the category as a when")
    Do $$$AssertNotTrue(##class(Shutter.Catalogue.Matcher).WhenHolds("receiver_category: history_of_record", {"receiver_category": "current_state"}), "another category")
}

/// The facts and the condition carry the case's receiver's category and policy (v1.23): a receiver the profile does not
/// name is current_state and current, and the conditions name the category.
Method TestReceiverFacts()
{
    Set case = ..Case({})
    Set case.Receiver = "UT Receiver Not In Profile"
    Set f = ##class(Shutter.Catalogue.Matcher).Facts(..Summary({}, case), case)
    Do $$$AssertEquals(f."history_policy", "current", "an unnamed receiver keeps what is current")
    Do $$$AssertEquals(f."receiver_category", "current_state", "and is a current_state system")
    Set c = ##class(Shutter.Catalogue.Matcher).Conditions(case, ..Summary({}, case))
    Do $$$AssertEquals(c."receiver_category", "current_state", "the condition names the category")
}

/// The correcting steps for a history_of_record receiver (v1.23): built from the case and the summary, naming the
/// missing movement, the later one that applied, the current placement, and eight ordered steps.
Method TestCorrectionSteps()
{
    Set row = {"case": {"event": "transfer"}, "summary": {"ward_state": {"state": "admitted", "ward": "WARD-C", "version": 3, "history": [
        {"event": "admit", "ward": "WARD-A", "event_time": "2026-10-19T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-19T08:00:00Z"},
        {"event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T09:30:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T09:30:00Z"}]}}}
    Set case = ..Case(row.case)
    Set case.Ward = "WARD-B", case.SourceMessageId = "MSG-UT-2", case.Receiver = "UT Receiver Not In Profile"
    Set steps = ##class(Shutter.Util.HistoryCorrection).Steps(case, ..Summary(row, case))
    Do $$$AssertEquals(steps.missing.ward, "WARD-B", "the missing movement's ward")
    Do $$$AssertEquals(steps.missing.after, "WARD-A", "it belongs after the admission to A")
    Do $$$AssertEquals(steps.current.ward, "WARD-C", "the current placement")
    Do $$$AssertEquals(steps.steps.%Size(), 8, "eight steps")
    Do $$$AssertTrue(steps.steps.%Get(0) [ "Do not resend", "the first step forbids the resend")
    Do $$$AssertTrue(steps.steps.%Get(4) [ "historic movement", "the insert is a historic movement")
    Do $$$AssertTrue(##class(Shutter.Util.HistoryCorrection).Headline(steps) [ "WARD-B", "the headline names the missing ward")
}

/// Facts: other_source is the other source system of an event the receiver holds at the failed event's own time.
Method TestFacts()
{
    Set row = {"case": {}, "summary": {"ward_state": {"history": [{"event": "transfer", "event_time": (..#EVENTTIME), "operation_key": ("EPR^HOSP^MRN-UT1^ENC-UT1^transfer^" _ ..#EVENTTIME)}]}}}
    Set case = ..Case(row.case)
    Set f = ##class(Shutter.Catalogue.Matcher).Facts(..Summary(row, case), case)
    Do $$$AssertEquals(f."other_source", "EPR", "the other source")
    Set f = ##class(Shutter.Catalogue.Matcher).Facts(..Summary({}, case), case)
    Do $$$AssertEquals(f."other_source", "", "none")
}

/// Runs the rows of one group and asserts each one's conditions.
Method RunRows(group As %String)
{
    Set n = 0
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Continue:(row.group '= group)
        Set n = n + 1
        Set c = ..Conditions(row)
        Set it2 = row.expect.%GetIterator()
        While it2.%GetNext(.name, .value) {
            Do $$$AssertEquals(c.%Get(name), value, row.name _ ": " _ name)
        }
    }
    Do $$$AssertTrue(n > 0, "the table has rows for " _ group)
}

/// The conditions for a row.
ClassMethod Conditions(row As %DynamicObject) As %DynamicObject
{
    Set case = ..Case($SELECT(row.%IsDefined("case"): row.case, 1: {}))
    Quit ##class(Shutter.Catalogue.Matcher).Conditions(case, ..Summary(row, case), $SELECT(row.%IsDefined("chain"): row.chain, 1: "single"))
}

/// A case in memory (never saved): event, failure_kind, event_time, patient_id, patient_id_authority, operation_key.
ClassMethod Case(spec As %DynamicObject) As Shutter.Store.Case
{
    Set json = "Shutter.Util.Json"
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-MATCHER"
    Set case.Event = $CLASSMETHOD(json, "Str", spec, "event", "transfer")
    Set case.FailureKind = $CLASSMETHOD(json, "Str", spec, "failure_kind", "delivery_failed")
    Set case.EventTime = $CLASSMETHOD(json, "Str", spec, "event_time", ..#EVENTTIME)
    Set case.PatientId = $CLASSMETHOD(json, "Str", spec, "patient_id", "MRN-UT1")
    Set case.PatientIdAuthority = $CLASSMETHOD(json, "Str", spec, "patient_id_authority", "HOSP")
    Set case.EncounterId = "ENC-UT1", case.SourceSystem = "PAS"
    Set case.OperationKey = $CLASSMETHOD(json, "Str", spec, "operation_key", "PAS^HOSP^" _ case.PatientId _ "^ENC-UT1^" _ case.Event _ "^" _ case.EventTime)
    Set case.Receiver = $CLASSMETHOD(json, "Str", spec, "receiver")
    Quit case
}

/// The summary for a row: a transfer the receiver could not take because it was unavailable, with the encounter
/// admitted the day before, nothing later, the message sent and recorded at the event's time with an offset, and the
/// evidence taken at 13:00, after every later event the rows add (a later event timed after the evidence settles no
/// order).
ClassMethod Summary(row As %DynamicObject, case As Shutter.Store.Case) As %DynamicObject
{
    Set s = {
        "failure": {"kind": "delivery_failed", "reason_code": "ward_unavailable", "http_status": 503},
        "ward_state_http_status": 200,
        "ward_state": {"patient_id": "MRN-UT1", "patient_id_authority": "HOSP", "state": "admitted", "version": 3, "history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^admit^2026-10-18T08:00:00Z"}]},
        "receipt_http_status": 404,
        "route": {"capabilities_http_status": 200, "capabilities": {"conditional_writes": true, "receipts": true}},
        "message": {"admit_time": "2026-10-18T08:00:00Z", "event_recorded": (..#EVENTTIME), "message_time": "2026-10-19T09:00:05Z", "event_time_had_offset": true, "feed_time_zone": "Europe/London", "notes": []},
        "observed_at": "2026-10-19T13:00:00Z",
        "timeline": []
    }
    If row.%IsDefined("summary") Do ##class(Shutter.Test.Gate).Merge(s, ##class(Shutter.Test.Gate).Fill(row.summary, case.OperationKey))
    Quit s
}

ClassMethod InList(list As %DynamicArray, value As %String) As %Boolean
{
    If '$ISOBJECT(list) Quit 0
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .v) { If v = value Return 1 }
    Quit 0
}

/// A vocabulary as text with its names and values sorted, to compare two of them.
ClassMethod Canonical(vocabulary As %DynamicObject) As %String
{
    Set iter = vocabulary.%GetIterator()
    While iter.%GetNext(.name, .values) {
        Set it2 = values.%GetIterator()
        While it2.%GetNext(.j, .v) { Set sorted(name, v) = "" }
    }
    Set out = "", name = ""
    For {
        Set name = $ORDER(sorted(name))
        Quit:name=""
        Set out = out _ name _ ":", v = ""
        For {
            Set v = $ORDER(sorted(name, v))
            Quit:v=""
            Set out = out _ v _ ","
        }
        Set out = out _ ";"
    }
    Quit out
}

ClassMethod Rows() As %DynamicArray
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Rows")
    Quit ##class(%DynamicArray).%FromJSON(xdata.Data)
}

/// The table: group (the test that runs the row), name, what the row changes, and the conditions it expects.
XData Rows [ MimeType = application/json ]
{
[
  {"group": "other", "name": "a receiver whose category is history_of_record", "case": {"receiver": "UT Records"}, "expect": {"receiver_category": "history_of_record"}},
  {"group": "other", "name": "a receiver whose category is orders_results", "case": {"receiver": "UT Orders"}, "expect": {"receiver_category": "orders_results"}},
  {"group": "other", "name": "a receiver the profile does not name", "case": {"receiver": "UT Nowhere"}, "expect": {"receiver_category": "current_state"}},
  {"group": "delivery", "name": "the plain case",
   "expect": {"delivery": "failed", "receiver_answer": "unavailable", "event": "transfer", "receipt": "absent", "later_applied": "none", "later_delivery": "none", "event_time": "plausible", "encounter_state": "admitted", "transition": "allowed", "patient_match": "yes", "simultaneous_sources": "no", "conditional_writes": "yes", "free_text": "no", "chain": "single", "receiver_category": "current_state"}},
  {"group": "delivery", "name": "a refusal", "case": {"failure_kind": "rejected"}, "expect": {"delivery": "rejected"}},
  {"group": "delivery", "name": "an uncertain outcome", "case": {"failure_kind": "uncertain_outcome"}, "expect": {"delivery": "uncertain"}},
  {"group": "delivery", "name": "a message held unread", "case": {"failure_kind": "unreadable"}, "expect": {"delivery": "unreadable"}},
  {"group": "delivery", "name": "an unmappable message", "case": {"failure_kind": "unmappable"}, "expect": {"delivery": "unmappable"}},
  {"group": "delivery", "name": "a withheld operation", "case": {"failure_kind": "withheld", "event": "merge"}, "expect": {"delivery": "withheld", "receiver_answer": "none", "event": "merge"}},
  {"group": "delivery", "name": "a case with no failure kind reads as failed", "case": {"failure_kind": ""}, "expect": {"delivery": "failed"}},

  {"group": "receiver_answer", "name": "a timeout reason", "summary": {"failure": {"reason_code": "timeout", "http_status": 0}}, "expect": {"receiver_answer": "timeout"}},
  {"group": "receiver_answer", "name": "a gateway timeout with no reason", "summary": {"failure": {"reason_code": null, "http_status": 504}}, "expect": {"receiver_answer": "timeout"}},
  {"group": "receiver_answer", "name": "a duplicate", "summary": {"failure": {"reason_code": "duplicate_message", "http_status": 409}}, "expect": {"receiver_answer": "duplicate"}},
  {"group": "receiver_answer", "name": "a version conflict", "summary": {"failure": {"reason_code": "version_conflict", "http_status": 409}}, "expect": {"receiver_answer": "version_conflict"}},
  {"group": "receiver_answer", "name": "any other reason is a refusal", "summary": {"failure": {"reason_code": "invalid_transition", "http_status": 422}}, "expect": {"receiver_answer": "refused"}},
  {"group": "receiver_answer", "name": "a 422 with no reason", "summary": {"failure": {"reason_code": null, "http_status": 422}}, "expect": {"receiver_answer": "refused"}},
  {"group": "receiver_answer", "name": "a 409 with no reason", "summary": {"failure": {"reason_code": null, "http_status": 409}}, "expect": {"receiver_answer": "refused"}},
  {"group": "receiver_answer", "name": "a 503 with no reason", "summary": {"failure": {"reason_code": null, "http_status": 503}}, "expect": {"receiver_answer": "unavailable"}},
  {"group": "receiver_answer", "name": "an uncertain outcome the connector gave a status for", "case": {"failure_kind": "uncertain_outcome"}, "summary": {"failure": {"reason_code": null, "http_status": 502, "outcome": "uncertain"}}, "expect": {"receiver_answer": "timeout"}},
  {"group": "receiver_answer", "name": "an uncertain outcome with no answer at all", "case": {"failure_kind": "uncertain_outcome"}, "summary": {"failure": {"reason_code": null, "http_status": null}}, "expect": {"delivery": "uncertain", "receiver_answer": "timeout"}},
  {"group": "receiver_answer", "name": "a failure with no answer", "summary": {"failure": {"reason_code": null, "http_status": null}}, "expect": {"receiver_answer": "none"}},
  {"group": "receiver_answer", "name": "an alert with a 503", "summary": {"failure": {"reason_code": "alert", "http_status": 503}}, "expect": {"receiver_answer": "unavailable"}},
  {"group": "receiver_answer", "name": "an alert with no status", "summary": {"failure": {"reason_code": "alert", "http_status": null}}, "expect": {"receiver_answer": "none"}},
  {"group": "receiver_answer", "name": "an uncertain alert with no status", "case": {"failure_kind": "uncertain_outcome"}, "summary": {"failure": {"reason_code": "alert", "http_status": null, "outcome": "uncertain"}}, "expect": {"delivery": "uncertain", "receiver_answer": "timeout"}},
  {"group": "receiver_answer", "name": "an alert that reads a 422", "summary": {"failure": {"reason_code": "alert", "http_status": 422}}, "expect": {"receiver_answer": "refused"}},
  {"group": "receiver_answer", "name": "no failure item", "summary": {"failure": null}, "expect": {"receiver_answer": "none"}},
  {"group": "receiver_answer", "name": "the receiver's answer as the connector recorded it", "summary": {"failure": {"reason_code": null, "http_status": null, "error": {"reason_code": "DUPLICATE", "http_status": 409}}}, "expect": {"receiver_answer": "duplicate"}},
  {"group": "receiver_answer", "name": "a refusal read from the failure text", "summary": {"failure": {"reason_code": null, "http_status": null, "text": "Delivery refused (duplicate_message), HTTP 409"}}, "expect": {"receiver_answer": "duplicate"}},
  {"group": "receiver_answer", "name": "an outage read from the failure text", "summary": {"failure": {"reason_code": null, "http_status": null, "text": "Delivery unavailable (ward_unavailable), HTTP 503: the ward system is down"}}, "expect": {"receiver_answer": "unavailable"}},
  {"group": "receiver_answer", "name": "an uncertain delivery read from the failure text", "summary": {"failure": {"reason_code": null, "http_status": null, "text": "Delivery uncertain, HTTP 504: no answer"}}, "expect": {"receiver_answer": "timeout"}},
  {"group": "receiver_answer", "name": "a parenthesis in the connector's own words is no reason code", "summary": {"failure": {"reason_code": null, "http_status": null, "text": "Delivery uncertain: The downstream system did not answer; the operation may have been applied (ERROR #5922: service unavailable)"}}, "expect": {"receiver_answer": "timeout"}},
  {"group": "receiver_answer", "name": "an uncertain outcome recorded on a failed delivery", "summary": {"failure": {"reason_code": null, "http_status": 502, "outcome": "uncertain"}}, "expect": {"delivery": "failed", "receiver_answer": "timeout"}},
  {"group": "receiver_answer", "name": "an uncertain outcome read from the failure text of a failed delivery", "summary": {"failure": {"reason_code": null, "http_status": null, "text": "Delivery uncertain, HTTP 502"}}, "expect": {"delivery": "failed", "receiver_answer": "timeout"}},
  {"group": "receiver_answer", "name": "a status read from failure text with no reason", "summary": {"failure": {"reason_code": null, "http_status": null, "text": "Delivery refused, HTTP 422"}}, "expect": {"receiver_answer": "refused"}},
  {"group": "receiver_answer", "name": "a withheld operation had no answer, whatever the failure says", "case": {"failure_kind": "withheld", "event": "cancel_transfer"}, "expect": {"delivery": "withheld", "receiver_answer": "none", "event": "cancel"}},

  {"group": "event", "name": "an admission", "case": {"event": "admit"}, "expect": {"event": "admit"}},
  {"group": "event", "name": "a discharge", "case": {"event": "discharge"}, "expect": {"event": "discharge"}},
  {"group": "event", "name": "an update", "case": {"event": "update"}, "expect": {"event": "update"}},
  {"group": "event", "name": "a merge", "case": {"event": "merge"}, "expect": {"event": "merge"}},
  {"group": "event", "name": "a cancelled admission", "case": {"event": "cancel_admit"}, "expect": {"event": "cancel"}},
  {"group": "event", "name": "a cancelled transfer", "case": {"event": "cancel_transfer"}, "expect": {"event": "cancel"}},
  {"group": "event", "name": "a cancelled discharge", "case": {"event": "cancel_discharge"}, "expect": {"event": "cancel"}},
  {"group": "event", "name": "an indexed-only word", "case": {"event": "register"}, "expect": {"event": "other"}},
  {"group": "event", "name": "an unmappable message's raw trigger", "case": {"event": "A17", "failure_kind": "unmappable"}, "expect": {"event": "other"}},

  {"group": "receipt", "name": "a receipt", "summary": {"receipt_http_status": 200}, "expect": {"receipt": "present"}},
  {"group": "receipt", "name": "a receiver that keeps no receipts", "summary": {"receipt_http_status": -1}, "expect": {"receipt": "none"}},
  {"group": "receipt", "name": "a receipt lookup that failed", "summary": {"receipt_http_status": 500}, "expect": {"receipt": "unreadable"}},
  {"group": "receipt", "name": "no receipt lookup", "summary": {"receipt_http_status": null}, "expect": {"receipt": "unreadable"}},

  {"group": "later_applied", "name": "a later transfer", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "transfer", "event_time": "2026-10-19T10:00:00Z"}]}, "expect": {"later_applied": "transfer", "later_delivery": "applied"}},
  {"group": "later_applied", "name": "a later transfer the feed sent that failed too, outside a chain", "summary": {"timeline": [{"later": true, "source": "feed", "outcome": "failed", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z"}]}, "expect": {"later_applied": "transfer", "later_delivery": "sent"}},
  {"group": "later_applied", "name": "the same failed later transfer in an ordered chain counts for nothing", "chain": "ordered", "summary": {"timeline": [{"later": true, "source": "feed", "outcome": "failed", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z"}]}, "expect": {"later_applied": "none", "later_delivery": "none", "chain": "ordered"}},
  {"group": "later_applied", "name": "an undelivered later transfer beside one the receiver applied: the word reached the receiver", "summary": {"timeline": [{"later": true, "source": "feed", "outcome": "failed", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T10:00:00Z"}], "ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "transfer", "ward": "WARD-D", "event_time": "2026-10-19T10:30:00Z", "applied_at": "2026-10-19T10:30:02Z"}]}}, "expect": {"later_applied": "transfer", "later_delivery": "applied"}},
  {"group": "later_applied", "name": "a later discharge the receiver already committed", "summary": {"timeline": [{"later": true, "outcome": "already_committed", "event": "discharge", "event_time": "2026-10-19T11:00:00Z"}]}, "expect": {"later_applied": "discharge"}},
  {"group": "later_applied", "name": "a discharge outranks a transfer", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "discharge", "event_time": "2026-10-19T11:00:00Z"}, {"later": true, "outcome": "applied", "event": "transfer", "event_time": "2026-10-19T10:00:00Z"}]}, "expect": {"later_applied": "discharge"}},
  {"group": "later_applied", "name": "a later update", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "update", "event_time": "2026-10-19T10:00:00Z"}]}, "expect": {"later_applied": "update"}},
  {"group": "later_applied", "name": "any other later word reads as an update", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "person_update", "event_time": "2026-10-19T10:00:00Z"}]}, "expect": {"later_applied": "update"}},
  {"group": "later_applied", "name": "a transfer followed by an update is a transfer", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "transfer", "event_time": "2026-10-19T10:00:00Z"}, {"later": true, "outcome": "applied", "event": "update", "event_time": "2026-10-19T10:30:00Z"}]}, "expect": {"later_applied": "transfer"}},
  {"group": "later_applied", "name": "a later admission", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "admit", "event_time": "2026-10-19T12:00:00Z"}]}, "expect": {"later_applied": "admit"}},
  {"group": "later_applied", "name": "an admission outranks an update", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "update", "event_time": "2026-10-19T10:00:00Z"}, {"later": true, "outcome": "applied", "event": "admit", "event_time": "2026-10-19T12:00:00Z"}]}, "expect": {"later_applied": "admit"}},
  {"group": "later_applied", "name": "a later merge", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "merge", "event_time": "2026-10-19T12:00:00Z"}]}, "expect": {"later_applied": "merge"}},
  {"group": "later_applied", "name": "a merge outranks a discharge", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "discharge", "event_time": "2026-10-19T11:00:00Z"}, {"later": true, "outcome": "applied", "event": "merge", "event_time": "2026-10-19T12:00:00Z"}]}, "expect": {"later_applied": "merge"}},
  {"group": "later_applied", "name": "a cancel carrying the failed event's own time", "summary": {"timeline": [{"later": false, "outcome": "applied", "event": "cancel_transfer", "event_time": "2026-10-19T09:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_transfer^2026-10-19T09:00:00Z"}]}, "expect": {"later_applied": "cancelled"}},
  {"group": "later_applied", "name": "a cancel outranks a merge", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "merge", "event_time": "2026-10-19T12:00:00Z"}, {"later": true, "outcome": "applied", "event": "cancel_admit", "event_time": "2026-10-19T12:30:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_admit^2026-10-19T12:30:00Z"}]}, "expect": {"later_applied": "cancel_other"}},
  {"group": "later_applied", "name": "a cancel of this movement outranks a merge", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "merge", "event_time": "2026-10-19T12:00:00Z"}, {"later": false, "outcome": "applied", "event": "cancel_transfer", "event_time": "2026-10-19T09:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_transfer^2026-10-19T09:00:00Z"}]}, "expect": {"later_applied": "cancelled"}},
  {"group": "later_applied", "name": "a later discharge and its cancel reverse nothing of this transfer: the patient is admitted again and a person looks", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "discharge", "event_time": "2026-10-19T11:00:00Z"}, {"event": "cancel_discharge", "event_time": "2026-10-19T11:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_discharge^2026-10-19T11:00:00Z"}]}}, "expect": {"later_applied": "cancel_other"}},
  {"group": "later_applied", "name": "a later transfer and its cancel in the timeline reverse nothing of this transfer", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "transfer", "event_time": "2026-10-19T10:00:00Z"}, {"later": true, "outcome": "applied", "event": "cancel_transfer", "event_time": "2026-10-19T10:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_transfer^2026-10-19T10:00:00Z"}]}, "expect": {"later_applied": "cancel_other"}},
  {"group": "later_applied", "name": "a cancel of another kind of event at this event's own time", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "cancel_admit", "event_time": "2026-10-19T09:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_admit^2026-10-19T09:00:00Z"}]}}, "expect": {"later_applied": "cancel_other"}},
  {"group": "later_applied", "name": "a cancel before the failed event counts for nothing", "summary": {"timeline": [{"later": false, "outcome": "applied", "event": "cancel_transfer", "event_time": "2026-10-19T08:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_transfer^2026-10-19T08:00:00Z"}]}, "expect": {"later_applied": "none"}},
  {"group": "later_applied", "name": "the case's own cancel counts for nothing", "case": {"event": "cancel_transfer"}, "summary": {"timeline": [{"later": false, "outcome": "applied", "event": "cancel_transfer", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}, "expect": {"later_applied": "none"}},
  {"group": "later_applied", "name": "a cancel with no time counts for nothing", "summary": {"timeline": [{"outcome": "applied", "event": "cancel_transfer", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_transfer^"}]}, "expect": {"later_applied": "none"}},
  {"group": "later_applied", "name": "a cancel that was not applied counts for nothing", "summary": {"timeline": [{"outcome": "failed", "event": "cancel_transfer", "event_time": "2026-10-19T10:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_transfer^2026-10-19T10:00:00Z"}]}, "expect": {"later_applied": "none"}},
  {"group": "later_applied", "name": "a later event that failed too", "summary": {"timeline": [{"later": true, "outcome": "failed", "event": "discharge", "event_time": "2026-10-19T11:00:00Z"}]}, "expect": {"later_applied": "none"}},
  {"group": "later_applied", "name": "an earlier applied event", "summary": {"timeline": [{"later": false, "outcome": "applied", "event": "transfer", "event_time": "2026-10-19T08:00:00Z"}]}, "expect": {"later_applied": "none"}},
  {"group": "later_applied", "name": "a later discharge in the receiver's history", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "discharge", "event_time": "2026-10-19T11:00:00Z"}]}}, "expect": {"later_applied": "discharge", "later_delivery": "applied"}},
  {"group": "later_applied", "name": "an event in the history at the failed event's own time is not later", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "transfer", "event_time": "2026-10-19T09:00:00Z", "operation_key": "EPR^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T09:00:00Z"}]}}, "expect": {"later_applied": "none", "simultaneous_sources": "yes"}},
  {"group": "later_applied", "name": "a cancel in the receiver's history at the failed event's time", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "cancel_transfer", "event_time": "2026-10-19T09:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_transfer^2026-10-19T09:00:00Z"}]}}, "expect": {"later_applied": "cancelled"}},
  {"group": "later_applied", "name": "a merge in the receiver's history", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "merge", "event_time": "2026-10-19T12:00:00Z"}]}}, "expect": {"later_applied": "merge"}},

  {"group": "event_time", "name": "a transfer before the admission the message names", "summary": {"message": {"admit_time": "2026-10-19T10:00:00Z"}}, "expect": {"event_time": "before_admission"}},
  {"group": "event_time", "name": "a transfer before the receiver's first admission", "summary": {"message": {"admit_time": null}, "ward_state": {"history": [{"event": "admit", "event_time": "2026-10-19T10:00:00Z"}]}}, "expect": {"event_time": "before_admission"}},
  {"group": "event_time", "name": "an admission is never before its own admission", "case": {"event": "admit"}, "summary": {"message": {"admit_time": "2026-10-19T10:00:00Z"}}, "expect": {"event_time": "plausible"}},
  {"group": "event_time", "name": "a history that does not start with an admission", "summary": {"message": {"admit_time": null}, "ward_state": {"history": [{"event": "transfer", "event_time": "2026-10-19T10:00:00Z"}]}}, "expect": {"event_time": "plausible", "later_applied": "transfer"}},
  {"group": "event_time", "name": "ten minutes after the message was sent", "summary": {"message": {"message_time": "2026-10-19T08:50:00Z"}}, "expect": {"event_time": "future"}},
  {"group": "event_time", "name": "four minutes after the message was sent", "summary": {"message": {"message_time": "2026-10-19T08:56:00Z"}}, "expect": {"event_time": "plausible"}},
  {"group": "event_time", "name": "ten minutes after the evidence was taken", "summary": {"observed_at": "2026-10-19T08:50:00Z", "message": {"message_time": null}}, "expect": {"event_time": "future"}},
  {"group": "event_time", "name": "evidence taken a day after the event", "summary": {"observed_at": "2026-10-20T09:00:00Z"}, "expect": {"event_time": "plausible"}},
  {"group": "event_time", "name": "a message sent an hour after the event", "summary": {"message": {"message_time": "2026-10-19T10:00:00Z"}}, "expect": {"event_time": "plausible"}},
  {"group": "event_time", "name": "before the admission outranks in the future", "summary": {"message": {"admit_time": "2026-10-19T10:00:00Z", "message_time": "2026-10-19T08:50:00Z"}}, "expect": {"event_time": "before_admission"}},
  {"group": "event_time", "name": "two days from when the event was recorded", "summary": {"message": {"event_recorded": "2026-10-17T09:00:00Z"}}, "expect": {"event_time": "far_from_recorded"}},
  {"group": "event_time", "name": "twenty-three hours from when the event was recorded", "summary": {"message": {"event_recorded": "2026-10-18T10:00:00Z"}}, "expect": {"event_time": "plausible"}},
  {"group": "event_time", "name": "within an hour of the October clock change, with no offset",
   "case": {"event_time": "2026-10-25T01:30:00Z"},
   "summary": {"observed_at": "2026-10-25T01:35:00Z", "message": {"admit_time": "2026-10-24T08:00:00Z", "event_recorded": "2026-10-25T01:30:00Z", "message_time": "2026-10-25T01:30:05Z", "event_time_had_offset": false}, "ward_state": {"history": [{"event": "admit", "event_time": "2026-10-24T08:00:00Z"}]}},
   "expect": {"event_time": "clock_change"}},
  {"group": "event_time", "name": "within an hour of the March clock change, with no offset",
   "case": {"event_time": "2026-03-29T00:30:00Z"},
   "summary": {"observed_at": "2026-03-29T00:35:00Z", "message": {"admit_time": "2026-03-28T08:00:00Z", "event_recorded": "2026-03-29T00:30:00Z", "message_time": "2026-03-29T00:30:05Z", "event_time_had_offset": false}, "ward_state": {"history": [{"event": "admit", "event_time": "2026-03-28T08:00:00Z"}]}},
   "expect": {"event_time": "clock_change"}},
  {"group": "event_time", "name": "near the clock change, with an offset",
   "case": {"event_time": "2026-10-25T01:30:00Z"},
   "summary": {"observed_at": "2026-10-25T01:35:00Z", "message": {"admit_time": "2026-10-24T08:00:00Z", "event_recorded": "2026-10-25T01:30:00Z", "message_time": "2026-10-25T01:30:05Z", "event_time_had_offset": true}, "ward_state": {"history": [{"event": "admit", "event_time": "2026-10-24T08:00:00Z"}]}},
   "expect": {"event_time": "plausible"}},
  {"group": "event_time", "name": "near the clock change, from a feed in UTC",
   "case": {"event_time": "2026-10-25T01:30:00Z"},
   "summary": {"observed_at": "2026-10-25T01:35:00Z", "message": {"admit_time": "2026-10-24T08:00:00Z", "event_recorded": "2026-10-25T01:30:00Z", "message_time": "2026-10-25T01:30:05Z", "event_time_had_offset": false, "feed_time_zone": "UTC"}, "ward_state": {"history": [{"event": "admit", "event_time": "2026-10-24T08:00:00Z"}]}},
   "expect": {"event_time": "plausible"}},
  {"group": "event_time", "name": "near the clock change, from evidence that does not say whether there was an offset",
   "case": {"event_time": "2026-10-25T01:30:00Z"},
   "summary": {"observed_at": "2026-10-25T01:35:00Z", "message": {"admit_time": "2026-10-24T08:00:00Z", "event_recorded": "2026-10-25T01:30:00Z", "message_time": "2026-10-25T01:30:05Z", "event_time_had_offset": null}, "ward_state": {"history": [{"event": "admit", "event_time": "2026-10-24T08:00:00Z"}]}},
   "expect": {"event_time": "plausible"}},
  {"group": "event_time", "name": "two hours after the clock change, with no offset",
   "case": {"event_time": "2026-10-25T03:00:00Z"},
   "summary": {"observed_at": "2026-10-25T03:05:00Z", "message": {"admit_time": "2026-10-24T08:00:00Z", "event_recorded": "2026-10-25T03:00:00Z", "message_time": "2026-10-25T03:00:05Z", "event_time_had_offset": false}, "ward_state": {"history": [{"event": "admit", "event_time": "2026-10-24T08:00:00Z"}]}},
   "expect": {"event_time": "plausible"}},
  {"group": "event_time", "name": "no message item", "summary": {"message": null}, "expect": {"event_time": "plausible", "free_text": "no"}},
  {"group": "event_time", "name": "no message item, with the evidence taken an hour before the event", "summary": {"message": null, "observed_at": "2026-10-19T08:00:00Z"}, "expect": {"event_time": "future"}},
  {"group": "event_time", "name": "a later transfer timed after the evidence was taken", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "transfer", "event_time": "2026-10-19T14:00:00Z"}]}, "expect": {"event_time": "later_event_future", "later_applied": "none"}},
  {"group": "event_time", "name": "a later update timed after the evidence was taken is no doubt", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "update", "event_time": "2026-10-19T14:00:00Z"}]}, "expect": {"event_time": "plausible", "later_applied": "none"}},
  {"group": "event_time", "name": "a doubtful later transfer behind a plausible later discharge is no doubt", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "discharge", "event_time": "2026-10-19T11:00:00Z"}, {"later": true, "outcome": "applied", "event": "transfer", "event_time": "2026-10-19T14:00:00Z"}]}, "expect": {"event_time": "plausible", "later_applied": "discharge"}},
  {"group": "event_time", "name": "a cancel with a doubtful time behind a plausible later discharge is a doubt: it may have reversed it", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "discharge", "event_time": "2026-10-19T11:00:00Z", "applied_at": "2026-10-19T11:00:02Z"}, {"event": "cancel_discharge", "event_time": "2026-10-20T11:00:00Z", "applied_at": "2026-10-19T11:30:02Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_discharge^2026-10-20T11:00:00Z"}]}}, "expect": {"event_time": "later_event_future", "later_applied": "discharge"}},
  {"group": "event_time", "name": "a second cancel with a doubtful time behind a plausible cancel changes nothing", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "cancel_transfer", "event_time": "2026-10-19T09:00:00Z", "applied_at": "2026-10-19T09:10:02Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_transfer^2026-10-19T09:00:00Z"}, {"event": "cancel_admit", "event_time": "2026-10-20T11:00:00Z", "applied_at": "2026-10-19T11:30:02Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^cancel_admit^2026-10-20T11:00:00Z"}]}}, "expect": {"event_time": "plausible", "later_applied": "cancelled"}},
  {"group": "event_time", "name": "a history time with an offset is not read as UTC", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "applied_at": "2026-10-19T09:00:00+01:00"}]}}, "expect": {"event_time": "plausible", "later_applied": "transfer"}},
  {"group": "event_time", "name": "a reference time the matcher cannot read skips its check", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "applied_at": "yesterday"}]}}, "expect": {"event_time": "plausible", "later_applied": "transfer"}},
  {"group": "event_time", "name": "a feed time with an offset is not read as UTC either", "summary": {"timeline": [{"later": true, "outcome": "applied", "event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00Z", "sent_at": "2026-10-19T09:00:00+01:00"}]}, "expect": {"event_time": "plausible", "later_applied": "transfer"}},
  {"group": "event_time", "name": "an event time the matcher cannot read supersedes nothing and asks for a person", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "transfer", "ward": "WARD-C", "event_time": "2026-10-19T10:00:00+01:00", "applied_at": "2026-10-19T09:00:02Z"}]}}, "expect": {"event_time": "later_event_future", "later_applied": "none"}},
  {"group": "event_time", "name": "a case with no event time", "case": {"event_time": ""}, "summary": {"message": {"admit_time": "2026-10-19T10:00:00Z"}}, "expect": {"event_time": "plausible"}},

  {"group": "encounter", "name": "a discharged encounter", "summary": {"ward_state": {"state": "discharged"}}, "expect": {"encounter_state": "discharged", "transition": "invalid"}},
  {"group": "encounter", "name": "an encounter the receiver does not know", "summary": {"ward_state_http_status": 404, "ward_state": null}, "expect": {"encounter_state": "not_found", "patient_match": "unknown", "transition": "unknown"}},
  {"group": "encounter", "name": "a receiver that did not answer", "summary": {"ward_state_http_status": 503, "ward_state": null}, "expect": {"encounter_state": "unknown", "patient_match": "unknown", "transition": "unknown"}},
  {"group": "encounter", "name": "an answer that names no state", "summary": {"ward_state": {"state": null}}, "expect": {"encounter_state": "unknown", "transition": "invalid"}},
  {"group": "encounter", "name": "the encounter of another patient", "summary": {"ward_state": {"patient_id": "MRN-OTHER"}}, "expect": {"patient_match": "no"}},
  {"group": "encounter", "name": "the same number from another authority", "summary": {"ward_state": {"patient_id_authority": "OTHER"}}, "expect": {"patient_match": "no"}},

  {"group": "transition", "name": "an admission of a known encounter", "case": {"event": "admit"}, "expect": {"transition": "invalid"}},
  {"group": "transition", "name": "an admission of an unknown encounter", "case": {"event": "admit"}, "summary": {"ward_state_http_status": 404, "ward_state": null}, "expect": {"transition": "allowed"}},
  {"group": "transition", "name": "a discharge of an admitted encounter", "case": {"event": "discharge"}, "expect": {"transition": "allowed"}},
  {"group": "transition", "name": "an update of a discharged encounter", "case": {"event": "update"}, "summary": {"ward_state": {"state": "discharged"}}, "expect": {"transition": "invalid"}},
  {"group": "transition", "name": "a merge into a discharged encounter", "case": {"event": "merge"}, "summary": {"ward_state": {"state": "discharged"}}, "expect": {"transition": "allowed"}},
  {"group": "transition", "name": "a merge into an encounter with no state", "case": {"event": "merge"}, "summary": {"ward_state": {"state": null}}, "expect": {"transition": "invalid"}},
  {"group": "transition", "name": "a cancelled discharge of a discharged encounter", "case": {"event": "cancel_discharge"}, "summary": {"ward_state": {"state": "discharged"}}, "expect": {"transition": "allowed"}},
  {"group": "transition", "name": "a cancelled discharge of an admitted encounter", "case": {"event": "cancel_discharge"}, "expect": {"transition": "invalid"}},
  {"group": "transition", "name": "a cancelled admission of an admitted encounter", "case": {"event": "cancel_admit"}, "expect": {"transition": "allowed"}},
  {"group": "transition", "name": "a transfer of an unknown encounter", "summary": {"ward_state_http_status": 404, "ward_state": null}, "expect": {"transition": "unknown"}},

  {"group": "simultaneous_sources", "name": "another source at the same time", "summary": {"ward_state": {"history": [{"event": "admit", "event_time": "2026-10-18T08:00:00Z"}, {"event": "transfer", "event_time": "2026-10-19T09:00:00Z", "operation_key": "EPR^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T09:00:00Z"}]}}, "expect": {"simultaneous_sources": "yes"}},
  {"group": "simultaneous_sources", "name": "the same source at the same time", "summary": {"ward_state": {"history": [{"event": "update", "event_time": "2026-10-19T09:00:00Z", "operation_key": "PAS^HOSP^MRN-UT1^ENC-UT1^update^2026-10-19T09:00:00Z"}]}}, "expect": {"simultaneous_sources": "no"}},
  {"group": "simultaneous_sources", "name": "the case's own operation in the history", "summary": {"ward_state": {"history": [{"event": "transfer", "event_time": "2026-10-19T09:00:00Z", "operation_key": "{key}"}]}}, "expect": {"simultaneous_sources": "no"}},
  {"group": "simultaneous_sources", "name": "another source at another time", "summary": {"ward_state": {"history": [{"event": "transfer", "event_time": "2026-10-19T09:01:00Z", "operation_key": "EPR^HOSP^MRN-UT1^ENC-UT1^transfer^2026-10-19T09:01:00Z"}]}}, "expect": {"simultaneous_sources": "no"}},
  {"group": "simultaneous_sources", "name": "no history", "summary": {"ward_state": {"history": null}}, "expect": {"simultaneous_sources": "no"}},
  {"group": "bed_conflict", "name": "no refusal for an occupied bed", "summary": {}, "expect": {"bed_conflict": "none"}},
  {"group": "bed_conflict", "name": "the occupant is leaving", "case": {"failure_kind": "rejected"}, "summary": {"failure": {"kind": "rejected", "reason_code": "bed_occupied", "http_status": 409}, "bed_conflict": {"refused": true, "ward": "WARD-B", "bed": "B2", "status": "occupant_leaving", "occupant": {"encounter_id": "ENC-OCC"}, "occupant_movement": {"event": "transfer", "delivery": "failed", "case_id": "C-000041"}}}, "expect": {"bed_conflict": "occupant_leaving", "receiver_answer": "refused", "delivery": "rejected"}},
  {"group": "bed_conflict", "name": "the occupant has left", "summary": {"bed_conflict": {"refused": true, "status": "occupant_left", "occupant": {"encounter_id": "ENC-OCC"}, "occupant_movement": {"event": "discharge", "delivery": "applied"}}}, "expect": {"bed_conflict": "occupant_left"}},
  {"group": "bed_conflict", "name": "two patients in one bed", "summary": {"bed_conflict": {"refused": true, "status": "occupant_staying", "occupant": {"encounter_id": "ENC-OCC"}, "occupant_movement": null}}, "expect": {"bed_conflict": "occupant_staying"}},
  {"group": "bed_conflict", "name": "the occupant could not be read", "summary": {"bed_conflict": {"refused": true, "status": "unknown", "occupant": null, "occupant_movement": null}}, "expect": {"bed_conflict": "unknown"}},

  {"group": "other", "name": "a receiver without conditional writes", "summary": {"route": {"capabilities": {"conditional_writes": false}}}, "expect": {"conditional_writes": "no"}},
  {"group": "other", "name": "a capability profile that does not say", "summary": {"route": {"capabilities": {"conditional_writes": null}}}, "expect": {"conditional_writes": "unknown"}},
  {"group": "other", "name": "no capability profile", "summary": {"route": {"capabilities_http_status": 503, "capabilities": null}}, "expect": {"conditional_writes": "unknown"}},
  {"group": "other", "name": "no route", "summary": {"route": null}, "expect": {"conditional_writes": "unknown"}},
  {"group": "other", "name": "notes in the message", "summary": {"message": {"notes": ["Patient moved early at the family's request"]}}, "expect": {"free_text": "yes"}},
  {"group": "other", "name": "an ordered chain", "chain": "ordered", "expect": {"chain": "ordered"}},
  {"group": "other", "name": "an interleaved chain", "chain": "interleaved", "expect": {"chain": "interleaved"}},
  {"group": "other", "name": "no chain kind reads as single", "chain": "", "expect": {"chain": "single"}}
]
}

}
