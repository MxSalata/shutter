/// The FHIR verifier's decision (Shutter.FHIR.Judge): a pure function of what was read, so every branch is a row of the
/// table in XData Rows. Each row builds its context from the base one, F1 on the shapes IRIS for Health returned when it
/// was measured: the base version "6" of Encounter enc-1 (WARD-A active), Shutter's version "7" (WARD-A completed at the
/// event time, WARD-B appended, the marker added), ETags W/"n", a history newest first whose entries carry no ETag, the
/// answer 200 with W/"7" and its Location, and the current resource "7". A row names further versions (each a copy of
/// another with a patch, and its own version id), the history's entries by name ("DELETE" for a delete entry, or a raw
/// entry), the current read and the vread, a shorthand for the attempt, and a patch for the rest; "@D", "@A0", "@Ac",
/// "@B", "@Bc" and "@C" in an array stand for the location entries of Entry. Rows marked adversarial must never verify,
/// whatever their expected outcome says (TestNoAdversarialRowVerifies). Nothing is saved and nothing is read.
Class Shutter.Test.FHIRJudge Extends %UnitTest.TestCase
{

Parameter OPID = "3f9a0c1d2e4b5a69788776655443322a";

Parameter EVENTTIME = "2026-11-08T09:00:00Z";

Method TestPositiveControls()
{
    Do ..RunRows("positive")
}

Method TestAdversarialContexts()
{
    Do ..RunRows("adversarial")
}

Method TestNotCommitted()
{
    Do ..RunRows("not_committed")
}

Method TestContexts()
{
    Do ..RunRows("context")
}

/// What a returned history cannot show: these rows pin the answer and say why it is what it is.
Method TestWhatTheHistoryCannotShow()
{
    Do ..RunRows("limitation")
}

/// The meta-test: no adversarial row is verified or verified_continued, whatever its own expectation says.
Method TestNoAdversarialRowVerifies()
{
    Set iter = ..Rows().%GetIterator(), n = 0
    While iter.%GetNext(.i, .row) {
        Continue:'row.adversarial
        Set n = n + 1, r = ..Judge(row)
        Do $$$AssertTrue((r.outcome '= "verified") && (r.outcome '= "verified_continued"), row.name _ ": never verified (it gave " _ r.outcome _ " " _ r.detail.reason _ ")")
    }
    Do $$$AssertTrue(n >= 60, "the adversarial rows are there (" _ n _ ")")
}

/// The words: "Verified" only for the two verified outcomes, the not-found sentence only for not_found, the unknown
/// sentence only for unknown, and the case codes as the design names them.
Method TestWordsFollowTheOutcome()
{
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set r = ..Judge(row), o = r.outcome
        Do $$$AssertEquals(($ZCONVERT(r.text, "L") [ "verified"), (o = "verified") || (o = "verified_continued"), row.name _ ": 'verified' is said only when it is the outcome (" _ r.text _ ")")
        Do $$$AssertEquals((r.text [ "No version of this update was found"), (o = "not_found"), row.name _ ": the not-found words only for not_found")
        Do $$$AssertEquals((r.text [ "outcome is unknown"), (o = "unknown"), row.name _ ": the unknown words only for unknown")
        Do $$$AssertEquals(r.detail."case_code", $CASE(o, "not_found": "WRITE_NOT_COMMITTED", "unknown": "WRITE_OUTCOME_UNKNOWN", : ""), row.name _ ": the case code")
        Do $$$AssertNotTrue(r.text [ """ of ", row.name _ ": no 'version n of m' count (" _ r.text _ ")")
        Do $$$AssertTrue($LISTFIND($LISTFROMSTRING(##class(Shutter.FHIR.Judge).#OUTCOMES), o), row.name _ ": a known outcome " _ o)
    }
}

/// Every outcome and every reason code of the specification is reached by some row.
Method TestEveryReasonIsReached()
{
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set r = ..Judge(row)
        Set seen(r.outcome) = "", seen(r.outcome, r.detail.reason) = ""
    }
    Set want("unknown") = "context_invalid,history_unavailable,history_paged,history_entry_unreadable,base_not_in_history,base_differs,history_delete_between,projection_without_marker,head_is_base,settling,vread_unavailable,vread_differs,etag_not_version,location_header_differs,field_differs,identity_differs"
    Set want("failed") = "update_created,marker_on_base,applied_version_absent,introducing_predecessor_not_base,introducing_not_projection,conflict_but_committed"
    Set want("not_found") = "no_committed_version"
    Set want("committed_review") = "current_deleted,current_unreadable,current_not_in_history,entry_gone,entry_closed_at_own_start,entered_in_error,prior_active_again,overlapping_periods,unfamiliar_shape,identity_differs,patient_changed,location_changed"
    Set want("verified") = "committed_current"
    Set want("verified_continued") = "committed_continued"
    Set o = ""
    For {
        Set o = $ORDER(want(o))
        Quit:o=""
        Do $$$AssertTrue($DATA(seen(o)), "the outcome " _ o _ " is reached")
        For k = 1:1:$LENGTH(want(o), ",") {
            Set reason = $PIECE(want(o), ",", k)
            Do $$$AssertTrue($DATA(seen(o, reason)), "the reason " _ o _ " " _ reason _ " is reached")
        }
    }
}

/// Purity: the same context twice gives the same outcome, text and detail, and the context is unchanged afterwards.
Method TestPurity()
{
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set ctx = ..Context(row), before = ctx.%ToJSON()
        Set o1 = ##class(Shutter.FHIR.Judge).Judge(ctx, .t1, .d1)
        Set o2 = ##class(Shutter.FHIR.Judge).Judge(ctx, .t2, .d2)
        Do $$$AssertEquals(o1 _ "|" _ t1 _ "|" _ d1.%ToJSON(), o2 _ "|" _ t2 _ "|" _ d2.%ToJSON(), row.name _ ": the same answer twice")
        Do $$$AssertEquals(ctx.%ToJSON(), before, row.name _ ": the context is unchanged")
    }
}

/// A context that is not one never throws: no object, an empty object, an array, a string.
Method TestNeverThrows()
{
    Set cases = ["", {}, [], "not a context", {"binding": "x"}, {"binding": {}, "attempt": []}]
    Set iter = cases.%GetIterator()
    While iter.%GetNext(.i, .ctx) {
        Set outcome = ##class(Shutter.FHIR.Judge).Judge(ctx, .text, .detail)
        Do $$$AssertEquals(outcome, "unknown", "unknown for " _ $SELECT($ISOBJECT(ctx): ctx.%ToJSON(), 1: """" _ ctx _ """"))
        Do $$$AssertEquals(detail.reason, "context_invalid", "as context_invalid")
        Do $$$AssertNotTrue(detail.retry, "and no retry")
    }
}

/// ETagVid: only W/"..." exactly has a version id, kept as the characters between the quotes.
Method TestETagVid()
{
    Set judge = "Shutter.FHIR.Judge"
    Do $$$AssertTrue($CLASSMETHOD(judge, "ETagVid", "W/""7""", .v) && (v = "7"), "W/""7""")
    Do $$$AssertTrue($CLASSMETHOD(judge, "ETagVid", "W/""zz-1""", .v) && (v = "zz-1"), "an opaque id")
    Do $$$AssertTrue($CLASSMETHOD(judge, "ETagVid", "W/""007""", .v) && (v = "007"), "kept as text, never as a number")
    For bad = """7""", "7", "w/""7""", "W/7", " W/""7""", "W/""7"" ", "W/""""", "W/""7""8""", "" {
        Do $$$AssertNotTrue($CLASSMETHOD(judge, "ETagVid", bad, .v), "no version id in [" _ bad _ "]")
    }
}

/// Instant: offsets normalised to UTC, a date or a time without an offset unreadable.
Method TestInstant()
{
    Set judge = "Shutter.FHIR.Judge"
    Do $$$AssertTrue($CLASSMETHOD(judge, "Instant", "2026-11-08T11:30:00+01:00", .a) && $CLASSMETHOD(judge, "Instant", "2026-11-08T10:30:00Z", .b), "two readable instants")
    Do $$$AssertEquals(a, b, "+01:00 is an hour ahead of UTC")
    Do $$$AssertTrue($CLASSMETHOD(judge, "Instant", "2026-11-08T10:30:00.500-00:30", .c) && (c = (b + 1800.5)), "fractions and negative offsets")
    Do $$$AssertTrue($CLASSMETHOD(judge, "Instant", "2026-11-09T00:30:00+01:00", .d) && $CLASSMETHOD(judge, "Instant", "2026-11-08T23:30:00Z", .e) && (d = e), "across midnight")
    For bad = "2026-11-08", "2026-11-08T10:30:00", "2026-11-08T10:30Z", "2026-13-08T10:30:00Z", "2026-02-30T10:30:00Z", "2026-11-08T24:00:00Z", "2026-11-08T10:30:00+15:00", "", "2026-11-08T10:30:60Z", "2026-11-08T10:30:00.1234567890Z", "2026-11-08T10:30:00+14:30" {
        Do $$$AssertNotTrue($CLASSMETHOD(judge, "Instant", bad, .x), "unreadable: [" _ bad _ "]")
    }
}

/// Runs the rows of one group and asserts each one's expectations.
Method RunRows(group As %String)
{
    Set n = 0
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Continue:(row.group '= group)
        Set n = n + 1
        Set r = ..Judge(row)
        Set got = r.outcome _ " " _ r.detail.reason
        Do $$$AssertEquals(got, row.outcome _ " " _ row.reason, row.name _ $SELECT(got = (row.outcome _ " " _ row.reason): "", 1: " (" _ r.text _ " " _ r.detail.%ToJSON() _ ")"))
        If row.%IsDefined("retry") Do $$$AssertEquals(''r.detail.retry, ''row.retry, row.name _ ": retry")
        If row.%IsDefined("path") Do $$$AssertEquals(r.detail.path, row.path, row.name _ ": the path")
        If row.%IsDefined("detail") {
            Set it2 = row.detail.%GetIterator()
            While it2.%GetNext(.k, .v) { Do $$$AssertEquals(r.detail.%Get(k), v, row.name _ ": detail " _ k) }
        }
        If row.%IsDefined("contains") {
            Set it2 = row.contains.%GetIterator()
            While it2.%GetNext(.j, .s) { Do $$$AssertTrue(r.text [ s, row.name _ ": the text says '" _ s _ "' (it says: " _ r.text _ ")") }
        }
        If row.%IsDefined("equals") Do $$$AssertEquals(r.text, row.equals, row.name _ ": the text")
    }
    Do $$$AssertTrue(n > 0, "the table has rows for " _ group)
}

/// Judge on the row's context: {outcome, text, detail}.
ClassMethod Judge(row As %DynamicObject) As %DynamicObject
{
    Set outcome = ##class(Shutter.FHIR.Judge).Judge(..Context(row), .text, .detail)
    Quit {"outcome": (outcome), "text": (text), "detail": (detail)}
}

/// The row's context: the named bodies, then the reads built from them, then the row's patch.
ClassMethod Context(row As %DynamicObject) As %DynamicObject
{
    Set merge = "Shutter.Test.Gate"
    Set vids = $SELECT(row.%IsDefined("vids"): row.vids, 1: {})
    Set versions = $SELECT(row.%IsDefined("versions"): ..Expand(row.versions), 1: {})
    Set bodies = {}
    // The base, Shutter's expected body built from it, Shutter's version and an older one.
    Set base = ..BaseBody(), base.meta.versionId = ..Vid(vids, "base", "6")
    If versions.%IsDefined("base") Do $CLASSMETHOD(merge, "Merge", base, versions.base.patch)
    Set expected = ..Project(base)
    If versions.%IsDefined("expected") Do $CLASSMETHOD(merge, "Merge", expected, versions.expected.patch)
    Set v = ..Copy(expected), v.meta.versionId = ..Vid(vids, "V", "7"), v.meta.lastUpdated = "2026-11-08T09:10:02Z"
    If versions.%IsDefined("V") Do $CLASSMETHOD(merge, "Merge", v, versions.V.patch)
    Set v5 = ..Copy(base), v5.meta.versionId = ..Vid(vids, "v5", "5"), v5.meta.lastUpdated = "2026-11-07T09:00:05Z"
    Set v5.location = [{"location": {"reference": "Location/ward-d"}, "status": "active", "period": {"start": "2026-11-06T20:00:00Z"}}]
    Do bodies.%Set("base", base), bodies.%Set("expected", expected), bodies.%Set("V", v), bodies.%Set("v5", v5)
    // The row's own versions, in the order given.
    Set iter = versions.%GetIterator(), stamp = 0
    While iter.%GetNext(.name, .def) {
        Continue:((name = "base") || (name = "expected") || (name = "V"))
        Set from = $SELECT(def.%IsDefined("from"): def.from, 1: "V")
        Set body = ..Copy(bodies.%Get(from)), stamp = stamp + 1
        If def.%IsDefined("patch") Do $CLASSMETHOD(merge, "Merge", body, def.patch)
        If def.%IsDefined("vid") {
            If '$ISOBJECT(body.%Get("meta")) Set body.meta = {}
            Set body.meta.versionId = def.vid, body.meta.lastUpdated = "2026-11-08T10:" _ $JUSTIFY(stamp, 2) _ ":00Z"
            Set body.meta.lastUpdated = $TRANSLATE(body.meta.lastUpdated, " ", "0")
        }
        Do bodies.%Set(name, body)
    }
    Set vidV = ..VersionOf(bodies.V), vidBase = ..VersionOf(base)
    Set ctx = {"binding": (..Binding()), "settle_final_seconds": 70}
    Set ctx.binding."base_version_id" = vidBase, ctx.binding."expected_etag" = "W/""" _ vidBase _ """"
    Set ctx."base_body" = base.%ToJSON(), ctx."expected_body" = expected.%ToJSON()
    // The attempt.
    Set kind = $SELECT(row.%IsDefined("attempt"): row.attempt, 1: "applied")
    Set attempt = {"outcome": "applied", "http_status": 200, "response_etag": ("W/""" _ vidV _ """"), "response_location": ("http://ward.example/fhir/r4/Encounter/enc-1/_history/" _ vidV), "seconds_since": 0}
    If kind = "lost" Set attempt = {"outcome": "uncertain", "http_status": 0}
    If kind = "conflict" Set attempt = {"outcome": "version_conflict", "http_status": 412}
    If kind = "refused" Set attempt = {"outcome": "refused", "http_status": 422}
    If kind = "created" Set attempt."http_status" = 201
    Set attempt."seconds_since" = $SELECT(row.%IsDefined("seconds"): row.seconds, 1: 0)
    Set ctx.attempt = attempt
    // The reads.
    Set vread = $SELECT(row.%IsDefined("vread"): row.vread, (kind = "lost") || (kind = "conflict") || (kind = "refused"): "", 1: "V")
    If row.%GetTypeOf("vread") = "null" Set vread = ""
    If vread '= "" Set ctx.vread = ..Read(bodies.%Get(vread))
    Set names = $SELECT(row.%IsDefined("history"): ..Expand(row.history), 1: ["V", "base", "v5"])
    Set bundle = {"resourceType": "Bundle", "id": "b-1", "type": "history", "timestamp": "2026-11-08T09:10:05Z", "link": [{"relation": "self", "url": "http://ward.example/fhir/r4/Encounter/enc-1/_history"}], "entry": []}
    Set it2 = names.%GetIterator()
    While it2.%GetNext(.j, .nm) {
        If $ISOBJECT(nm) { Do bundle.entry.%Push(nm) Continue }
        If nm = "DELETE" { Do bundle.entry.%Push({"request": {"method": "DELETE", "url": "Encounter/enc-1"}, "response": {"status": "200", "lastModified": "2026-11-08T09:20:00Z"}}) Continue }
        Do bundle.entry.%Push({"resource": (bodies.%Get(nm)), "request": {"method": "PUT", "url": "Encounter/enc-1"}, "response": {"status": "200", "lastModified": "2026-11-08T09:20:00Z"}})
    }
    Set bundle.total = bundle.entry.%Size()
    If row.%IsDefined("bundle") Do $CLASSMETHOD(merge, "Merge", bundle, row.bundle)
    Set ctx.history = {"http_status": 200, "content_type": "application/fhir+json; charset=UTF-8", "body": (bundle.%ToJSON())}
    Set current = $SELECT(row.%IsDefined("current"): row.current, 1: "V")
    Set ctx.current = ..Read(bodies.%Get(current))
    Set patient = ..PatientBody()
    If row.%IsDefined("patient_patch") Do $CLASSMETHOD(merge, "Merge", patient, row."patient_patch")
    Set ctx.patient = {"http_status": 200, "body": (patient.%ToJSON())}
    // One read per bound Location. location_read patches a read ("absent" leaves it out); location_twice adds a second
    // read of a Location, its body patched.
    Set ctx.locations = []
    Set reads = $SELECT(row.%IsDefined("location_read"): row."location_read", 1: {})
    For ward = "a", "b", "c" {
        Set ref = "Location/ward-" _ ward, loc = ..LocationBody(ward)
        If row.%IsDefined("location_patch") && row."location_patch".%IsDefined(ref) Do $CLASSMETHOD(merge, "Merge", loc, row."location_patch".%Get(ref))
        Set read = {"reference": (ref), "http_status": 200, "body": (loc.%ToJSON())}
        If reads.%GetTypeOf(ref) = "string" Continue
        If reads.%GetTypeOf(ref) = "object" Do $CLASSMETHOD(merge, "Merge", read, reads.%Get(ref))
        Do ctx.locations.%Push(read)
        If row.%IsDefined("location_twice") && row."location_twice".%IsDefined(ref) {
            Set again = ..LocationBody(ward)
            Do $CLASSMETHOD(merge, "Merge", again, row."location_twice".%Get(ref))
            Do ctx.locations.%Push({"reference": (ref), "http_status": 200, "body": (again.%ToJSON())})
        }
    }
    If row.%IsDefined("ctx") Do $CLASSMETHOD(merge, "Merge", ctx, ..Expand(row.ctx))
    Quit ctx
}

/// A read of a body: 200, its ETag W/"vid", FHIR JSON.
ClassMethod Read(body As %DynamicObject) As %DynamicObject
{
    Quit {"http_status": 200, "etag": ("W/""" _ ..VersionOf(body) _ """"), "content_type": "application/fhir+json; charset=UTF-8", "body": (body.%ToJSON())}
}

ClassMethod VersionOf(body As %DynamicObject) As %String
{
    Set meta = body.%Get("meta")
    Quit $SELECT($ISOBJECT(meta): meta.%Get("versionId"), 1: "")
}

ClassMethod Vid(vids As %DynamicObject, name As %String, default As %String) As %String
{
    Quit $SELECT(vids.%IsDefined(name): vids.%Get(name), 1: default)
}

/// The base Encounter as IRIS for Health returns it (meta last), WARD-A active since the day before.
ClassMethod BaseBody() As %DynamicObject
{
    Quit {"resourceType": "Encounter", "id": "enc-1", "status": "in-progress",
        "identifier": [{"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49", "value": "V1001"}],
        "class": {"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IMP"},
        "subject": {"reference": "Patient/demo-p1"},
        "location": [(..Entry("D")), (..Entry("A0"))],
        "meta": {"lastUpdated": "2026-11-08T08:59:10Z", "versionId": "6"}}
}

/// Shutter's change applied to a body, as the plan builder makes it: the open WARD-A entry completed at the event time,
/// WARD-B appended active from it, the marker appended to meta.tag.
ClassMethod Project(base As %DynamicObject) As %DynamicObject
{
    Set e = ..Copy(base), out = []
    Set iter = e.location.%GetIterator()
    While iter.%GetNext(.i, .l) {
        If (l.location.reference = "Location/ward-a") && (l.%Get("status") = "active") && '(($ISOBJECT(l.%Get("period"))) && l.period.%IsDefined("end")) {
            Set l.status = "completed"
            If '$ISOBJECT(l.%Get("period")) Set l.period = {}
            Set l.period.end = ..#EVENTTIME
        }
        Do out.%Push(l)
    }
    Do out.%Push(..Entry("B"))
    Set e.location = out
    If '$ISOBJECT(e.%Get("meta")) Set e.meta = {}
    If '$ISOBJECT(e.meta.%Get("tag")) Set e.meta.tag = []
    Do e.meta.tag.%Push(..Marker())
    Quit e
}

ClassMethod Marker() As %DynamicObject
{
    Quit {"system": "urn:shutter:recovery", "code": (..#OPID)}
}

/// The location entries rows name: D (an older ward, completed), A0 (WARD-A open, the base's), Ac (WARD-A completed at
/// the event time), B (WARD-B open from the event time, Shutter's), Bc (Shutter's, completed at 10:30 UTC written with
/// an offset), C (WARD-C open from 10:30 UTC, written with an offset).
ClassMethod Entry(name As %String) As %DynamicObject
{
    Quit:name="D" {"location": {"reference": "Location/ward-d"}, "status": "completed", "period": {"start": "2026-11-06T20:00:00Z", "end": "2026-11-07T09:00:00Z"}}
    Quit:name="A0" {"location": {"reference": "Location/ward-a"}, "status": "active", "period": {"start": "2026-11-07T09:00:00Z"}}
    Quit:name="Ac" {"location": {"reference": "Location/ward-a"}, "status": "completed", "period": {"start": "2026-11-07T09:00:00Z", "end": (..#EVENTTIME)}}
    Quit:name="B" {"location": {"reference": "Location/ward-b"}, "status": "active", "period": {"start": (..#EVENTTIME)}}
    Quit:name="Bc" {"location": {"reference": "Location/ward-b"}, "status": "completed", "period": {"start": (..#EVENTTIME), "end": "2026-11-08T11:30:00+01:00"}}
    Quit:name="C" {"location": {"reference": "Location/ward-c"}, "status": "active", "period": {"start": "2026-11-08T11:30:00+01:00"}}
    Quit ""
}

/// A copy with every array element "@name" replaced by that location entry and "#OPID" by the operation id.
ClassMethod Expand(obj As %DynamicAbstractObject) As %DynamicAbstractObject
{
    Set json = $REPLACE(obj.%ToJSON(), "#OPID", ..#OPID)
    Set copy = ##class(%DynamicAbstractObject).%FromJSON(json)
    Do ..ExpandInto(copy)
    Quit copy
}

ClassMethod ExpandInto(obj As %DynamicAbstractObject)
{
    Set isArray = obj.%IsA("%DynamicArray")
    Set iter = obj.%GetIterator()
    While iter.%GetNext(.k, .v) {
        If $ISOBJECT(v) { Do ..ExpandInto(v) Continue }
        If isArray && (obj.%GetTypeOf(k) = "string") && ($EXTRACT(v) = "@") Do obj.%Set(k, ..Entry($EXTRACT(v, 2, *)))
    }
}

ClassMethod Binding() As %DynamicObject
{
    Quit {"expected_etag": "W/\"6\"", "base_version_id": "6", "operation_id": (..#OPID), "marker_system": "urn:shutter:recovery",
        "encounter_id": "enc-1", "encounter_identifier": {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49", "value": "V1001"},
        "patient": {"reference": "Patient/demo-p1", "identifier": {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.48", "value": "MRN-Ab77"}},
        "prior_location": "Location/ward-a", "target_location": "Location/ward-b",
        "locations": [{"reference": "Location/ward-a", "checked_identifier": "WARD-A"}, {"reference": "Location/ward-b", "checked_identifier": "WARD-B"}, {"reference": "Location/ward-c", "checked_identifier": "WARD-C"}],
        "event_time": (..#EVENTTIME), "server_owned_fields": []}
}

ClassMethod PatientBody() As %DynamicObject
{
    Quit {"resourceType": "Patient", "id": "demo-p1", "identifier": [{"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.48", "value": "MRN-Ab77"}], "active": true, "meta": {"lastUpdated": "2026-11-07T08:00:00Z", "versionId": "1"}}
}

ClassMethod LocationBody(ward As %String) As %DynamicObject
{
    Quit {"resourceType": "Location", "id": ("ward-" _ ward), "status": "active", "identifier": [{"system": "urn:shutter:demo:ward", "value": ("WARD-" _ $ZCONVERT(ward, "U"))}], "meta": {"lastUpdated": "2026-11-07T08:00:00Z", "versionId": "1"}}
}

ClassMethod Copy(obj As %DynamicAbstractObject) As %DynamicAbstractObject
{
    Quit ##class(%DynamicAbstractObject).%FromJSON(obj.%ToJSON())
}

ClassMethod Rows() As %DynamicArray
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Rows")
    Quit ##class(%DynamicArray).%FromJSON(xdata.Data)
}

/// The table: group, name, adversarial (must never verify), how the context differs from the base one (vids, versions,
/// history, current, vread, attempt, seconds, bundle, patient_patch, location_patch, ctx), and what Judge must give
/// (outcome, reason, retry, path, detail, contains, equals).
XData Rows [ MimeType = application/json ]
{
[
  {"group": "positive", "name": "applied, and Shutter's version is current", "outcome": "verified", "reason": "committed_current", "retry": false,
   "detail": {"committed_version": "7", "current_version": "7", "base_version": "6"},
   "equals": "Verified in Encounter version \"7\": the approved location update is present, carrying Shutter's marker; no other field changed from version \"6\", the version the write was conditional on."},
  {"group": "positive", "name": "a lost answer, the marked version right after the base (F3)", "attempt": "lost", "seconds": 10,
   "outcome": "verified", "reason": "committed_current"},
  {"group": "positive", "name": "a lost answer read at once still verifies on the first read", "attempt": "lost", "seconds": 0,
   "outcome": "verified", "reason": "committed_current"},
  {"group": "positive", "name": "a later writer moved the patient on to WARD-C and sent no marker (the IRIS default)",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", "@C"], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W",
   "outcome": "verified_continued", "reason": "committed_continued", "detail": {"committed_version": "7", "current_version": "8"},
   "contains": ["Verified in Encounter version \"7\"", "The current resource is version \"8\"; a later change followed."]},
  {"group": "positive", "name": "a later writer echoed Shutter's meta, so the marker is on the current version too",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", "@C"]}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "verified_continued", "reason": "committed_continued"},
  {"group": "positive", "name": "a later writer replaced the tags with its own and moved the patient on",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", "@C"], "meta": {"tag": [{"system": "urn:other:writer", "code": "x1"}]}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "verified_continued", "reason": "committed_continued"},
  {"group": "positive", "name": "a later writer changed only the type, Shutter's entry still the open one",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"type": [{"text": "inpatient"}], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "verified_continued", "reason": "committed_continued"},
  {"group": "positive", "name": "two later versions, the patient moved on in the first",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", "@C"], "meta": {"tag": null}}},
                "W2": {"from": "W", "vid": "9", "patch": {"type": [{"text": "inpatient"}]}}},
   "history": ["W2", "W", "V", "base", "v5"], "current": "W2", "outcome": "verified_continued", "reason": "committed_continued", "detail": {"current_version": "9"}},
  {"group": "positive", "name": "finished after Shutter's version, every entry completed",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"status": "finished", "location": ["@D", "@Ac", "@Bc"], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "verified_continued", "reason": "committed_continued"},
  {"group": "positive", "name": "opaque version ids", "vids": {"base": "a9f", "V": "zz-1", "v5": "q"},
   "outcome": "verified", "reason": "committed_current", "detail": {"committed_version": "zz-1", "base_version": "a9f"}},
  {"group": "positive", "name": "\"10\" after \"9\" is the next version, never a smaller number", "vids": {"base": "9", "V": "10", "v5": "8"},
   "outcome": "verified", "reason": "committed_current", "detail": {"committed_version": "10"}},
  {"group": "positive", "name": "\"9\" after \"10\": the list's order decides, never the numbers", "vids": {"base": "10", "V": "9", "v5": "11"},
   "outcome": "verified", "reason": "committed_current", "detail": {"committed_version": "9"}},
  {"group": "positive", "name": "another operation's tag under the marker's system on the base is kept and is not the marker",
   "versions": {"base": {"patch": {"meta": {"tag": [{"system": "urn:shutter:recovery", "code": "00000000000000000000000000000001"}]}}}},
   "outcome": "verified", "reason": "committed_current"},
  {"group": "positive", "name": "a history with no older version than the base", "history": ["V", "base"], "outcome": "verified", "reason": "committed_current"},
  {"group": "positive", "name": "a server-owned field the binding lists (as a measurement would) is set aside, and nothing else",
   "versions": {"V": {"patch": {"meta": {"source": "urn:server:node-2"}}}}, "ctx": {"binding": {"server_owned_fields": ["meta.source"]}},
   "outcome": "verified", "reason": "committed_current"},
  {"group": "adversarial", "adversarial": true, "name": "the same server-set field when the binding lists none (IRIS: none measured)",
   "versions": {"V": {"patch": {"meta": {"source": "urn:server:node-2"}}}}, "outcome": "unknown", "reason": "field_differs", "path": "/meta/source"},

  {"group": "adversarial", "adversarial": true, "name": "a lost update (If-Match ignored): another writer's version between the base and Shutter's",
   "vids": {"V": "8"}, "versions": {"X": {"from": "base", "vid": "7", "patch": {"type": [{"text": "clerk edit"}]}}},
   "history": ["V", "X", "base", "v5"], "outcome": "failed", "reason": "introducing_predecessor_not_base", "detail": {"committed_version": "8"}},
  {"group": "adversarial", "adversarial": true, "name": "a lost update whose answer was lost too",
   "vids": {"V": "8"}, "versions": {"X": {"from": "base", "vid": "7", "patch": {"type": [{"text": "clerk edit"}]}}},
   "history": ["V", "X", "base", "v5"], "attempt": "lost", "seconds": 70, "outcome": "failed", "reason": "introducing_predecessor_not_base"},
  {"group": "adversarial", "adversarial": true, "name": "another writer made the same change, without the marker (second_writer_same_change)",
   "versions": {"S": {"from": "V", "vid": "7", "patch": {"meta": {"tag": null}}}},
   "history": ["S", "base", "v5"], "current": "S", "attempt": "lost", "seconds": 70, "outcome": "unknown", "reason": "projection_without_marker"},
  {"group": "adversarial", "adversarial": true, "name": "the same change by another writer while Shutter's answer named its version",
   "versions": {"S": {"from": "V", "vid": "7", "patch": {"meta": {"tag": null}}}},
   "history": ["S", "base", "v5"], "current": "S", "vread": "S", "outcome": "unknown", "reason": "projection_without_marker"},
  {"group": "adversarial", "adversarial": true, "name": "the writing version lost the marker (drop_meta_tag)",
   "versions": {"V": {"patch": {"meta": {"tag": null}}}}, "outcome": "unknown", "reason": "projection_without_marker"},
  {"group": "adversarial", "adversarial": true, "name": "the marker replaced by another code under the marker's system",
   "versions": {"V": {"patch": {"meta": {"tag": [{"system": "urn:shutter:recovery", "code": "ffffffffffffffffffffffffffffffff"}]}}}},
   "outcome": "unknown", "reason": "projection_without_marker"},
  {"group": "adversarial", "adversarial": true, "name": "the marker's code matched only case-insensitively",
   "versions": {"V": {"patch": {"meta": {"tag": [{"system": "urn:shutter:recovery", "code": "3F9A0C1D2E4B5A69788776655443322A"}]}}}},
   "outcome": "unknown", "reason": "projection_without_marker"},
  {"group": "adversarial", "adversarial": true, "name": "the marker's system matched only case-insensitively",
   "versions": {"V": {"patch": {"meta": {"tag": [{"system": "urn:Shutter:recovery", "code": "#OPID"}]}}}},
   "outcome": "unknown", "reason": "projection_without_marker"},
  {"group": "adversarial", "adversarial": true, "name": "a later writer added the marker to a version after another writer's same change",
   "versions": {"S": {"from": "V", "vid": "7", "patch": {"meta": {"tag": null}}}, "M": {"from": "V", "vid": "8"}},
   "history": ["M", "S", "base", "v5"], "current": "M", "vread": "M", "outcome": "failed", "reason": "introducing_predecessor_not_base"},
  {"group": "adversarial", "adversarial": true, "name": "a truncated history: the base is not in it", "history": ["V"], "outcome": "unknown", "reason": "base_not_in_history"},
  {"group": "adversarial", "adversarial": true, "name": "a history with no entries (HardDelete of every version)", "history": [], "outcome": "unknown", "reason": "base_not_in_history"},
  {"group": "adversarial", "adversarial": true, "name": "the history answered 503", "ctx": {"history": {"http_status": 503, "content_type": "text/html", "body": "<html>Service Unavailable</html>"}},
   "outcome": "unknown", "reason": "history_unavailable", "retry": true},
  {"group": "adversarial", "adversarial": true, "name": "the history answered 500, as system history did on 2026.2", "seconds": 70,
   "ctx": {"history": {"http_status": 500, "body": "{\"resourceType\":\"OperationOutcome\",\"issue\":[{\"severity\":\"error\",\"code\":\"exception\",\"diagnostics\":\"<SUBSCRIPT>RequireAllowedResourceInteracti+3\"}]}"}},
   "outcome": "unknown", "reason": "history_unavailable", "retry": false},
  {"group": "adversarial", "adversarial": true, "name": "the history answered 400",
   "ctx": {"history": {"http_status": 400, "body": "{\"resourceType\":\"OperationOutcome\",\"issue\":[{\"severity\":\"error\",\"code\":\"not-supported\"}]}"}},
   "outcome": "unknown", "reason": "history_unavailable"},
  {"group": "adversarial", "adversarial": true, "name": "an HTML page with 200 instead of the history", "ctx": {"history": {"content_type": "text/html; charset=utf-8", "body": "<html><body>Sign in</body></html>"}},
   "outcome": "unknown", "reason": "history_unavailable"},
  {"group": "adversarial", "adversarial": true, "name": "the history's body under an HTML content type", "ctx": {"history": {"content_type": "text/html; charset=utf-8"}},
   "outcome": "unknown", "reason": "history_unavailable"},
  {"group": "adversarial", "adversarial": true, "name": "a searchset Bundle where the history should be", "bundle": {"type": "searchset"},
   "outcome": "unknown", "reason": "history_unavailable"},
  {"group": "adversarial", "adversarial": true, "name": "a history with a next link", "bundle": {"link": [{"relation": "self", "url": "x"}, {"relation": "next", "url": "y"}]},
   "outcome": "unknown", "reason": "history_paged"},
  {"group": "adversarial", "adversarial": true, "name": "a delete between the base and Shutter's version, the resource brought back with the delete's ETag",
   "vids": {"V": "8"}, "history": ["V", "DELETE", "base", "v5"], "outcome": "unknown", "reason": "history_delete_between"},
  {"group": "adversarial", "adversarial": true, "name": "a delete after the base and a re-created resource without the marker, the answer lost",
   "versions": {"R": {"from": "base", "vid": "8"}}, "history": ["R", "DELETE", "base", "v5"], "current": "R", "attempt": "lost", "seconds": 70,
   "outcome": "unknown", "reason": "history_delete_between"},
  {"group": "adversarial", "adversarial": true, "name": "a delete after Shutter's version, the current read 410",
   "history": ["DELETE", "V", "base", "v5"],
   "ctx": {"current": {"http_status": 410, "etag": null, "body": "{\"resourceType\":\"OperationOutcome\",\"issue\":[{\"severity\":\"error\",\"code\":\"deleted\",\"diagnostics\":\"<HSFHIRErr>ResourceWasDeleted\"}]}"}},
   "outcome": "committed_review", "reason": "current_deleted", "detail": {"committed_version": "7"}},
  {"group": "adversarial", "adversarial": true, "name": "a delete after Shutter's version and a re-created resource as the current one",
   "versions": {"R": {"from": "V", "vid": "9"}}, "history": ["R", "DELETE", "V", "base", "v5"], "current": "R",
   "outcome": "committed_review", "reason": "history_delete_between"},
  {"group": "adversarial", "adversarial": true, "name": "reset and re-seeded: the history's version \"6\" is another body",
   "versions": {"R6": {"from": "base", "vid": "6", "patch": {"location": [{"location": {"reference": "Location/ward-a"}, "status": "active", "period": {"start": "2026-11-08T08:00:00Z"}}]}}},
   "history": ["V", "R6"], "outcome": "unknown", "reason": "base_differs", "path": "/location/0/location/reference"},
  {"group": "adversarial", "adversarial": true, "name": "HardDelete and re-create: the new incarnation has only version \"1\"",
   "versions": {"N1": {"from": "base", "vid": "1"}}, "history": ["N1"], "current": "N1", "attempt": "lost", "seconds": 70,
   "outcome": "unknown", "reason": "base_not_in_history"},
  {"group": "adversarial", "adversarial": true, "name": "a history entry with a resource but no version id",
   "history": ["V", {"resource": {"resourceType": "Encounter", "id": "enc-1", "status": "in-progress"}, "request": {"method": "PUT", "url": "Encounter/enc-1"}, "response": {"status": "200"}}, "base"],
   "outcome": "unknown", "reason": "history_entry_unreadable"},
  {"group": "adversarial", "adversarial": true, "name": "a version id twice in the history", "history": ["V", "V", "base", "v5"], "outcome": "unknown", "reason": "history_entry_unreadable"},
  {"group": "adversarial", "adversarial": true, "name": "a history entry of another Encounter",
   "versions": {"O": {"from": "base", "vid": "3", "patch": {"id": "enc-2"}}}, "history": ["V", "base", "O"], "outcome": "unknown", "reason": "history_entry_unreadable"},
  {"group": "adversarial", "adversarial": true, "name": "a history entry that is neither a version nor a delete",
   "history": ["V", {"request": {"method": "GET", "url": "Encounter/enc-1"}, "response": {"status": "200"}}, "base"], "outcome": "unknown", "reason": "history_entry_unreadable"},
  {"group": "adversarial", "adversarial": true, "name": "a delete entry that carries a resource",
   "history": ["V", {"resource": {"resourceType": "Encounter", "id": "enc-1", "meta": {"versionId": "x"}}, "request": {"method": "DELETE", "url": "Encounter/enc-1"}}, "base"], "outcome": "unknown", "reason": "history_entry_unreadable"},
  {"group": "adversarial", "adversarial": true, "name": "the marker already on the base (a reused code)",
   "versions": {"base": {"patch": {"meta": {"tag": [{"system": "urn:shutter:recovery", "code": "#OPID"}]}}}, "expected": {"patch": {"meta": {"tag": [{"system": "urn:shutter:recovery", "code": "#OPID"}]}}}},
   "outcome": "failed", "reason": "marker_on_base"},
  {"group": "adversarial", "adversarial": true, "name": "the marker on a version older than the base",
   "versions": {"M5": {"from": "v5", "patch": {"meta": {"tag": [{"system": "urn:shutter:recovery", "code": "#OPID"}]}}}},
   "history": ["V", "base", "M5"], "outcome": "failed", "reason": "marker_on_base"},
  {"group": "adversarial", "adversarial": true, "name": "the vread's ETag names \"7\" while its body is version \"8\"",
   "versions": {"V8": {"from": "V", "vid": "8"}}, "vread": "V8", "ctx": {"vread": {"etag": "W/\"7\""}}, "outcome": "unknown", "reason": "etag_not_version"},
  {"group": "adversarial", "adversarial": true, "name": "a strong ETag on the answer", "ctx": {"attempt": {"response_etag": "\"7\""}, "vread": null},
   "outcome": "unknown", "reason": "etag_not_version"},
  {"group": "adversarial", "adversarial": true, "name": "a lower-case weak ETag on the answer", "ctx": {"attempt": {"response_etag": "w/\"7\""}, "vread": null},
   "outcome": "unknown", "reason": "etag_not_version"},
  {"group": "adversarial", "adversarial": true, "name": "the answer's ETag names another version than the marked one", "ctx": {"attempt": {"response_etag": "W/\"9\""}, "vread": null},
   "outcome": "unknown", "reason": "etag_not_version"},
  {"group": "adversarial", "adversarial": true, "name": "the vread's ETag is strong", "ctx": {"vread": {"etag": "\"7\""}}, "outcome": "unknown", "reason": "etag_not_version"},
  {"group": "adversarial", "adversarial": true, "name": "the answer's Location names _history/8 beside ETag W/\"7\"",
   "ctx": {"attempt": {"response_location": "http://ward.example/fhir/r4/Encounter/enc-1/_history/8"}}, "outcome": "unknown", "reason": "location_header_differs"},
  {"group": "adversarial", "adversarial": true, "name": "the answer's Location names no version",
   "ctx": {"attempt": {"response_location": "http://ward.example/fhir/r4/Encounter/enc-1"}}, "outcome": "unknown", "reason": "location_header_differs"},
  {"group": "adversarial", "adversarial": true, "name": "the vread answered 410", "ctx": {"vread": {"http_status": 410}}, "outcome": "unknown", "reason": "vread_unavailable"},
  {"group": "adversarial", "adversarial": true, "name": "the vread answered 404", "ctx": {"vread": {"http_status": 404}}, "outcome": "unknown", "reason": "vread_unavailable"},
  {"group": "adversarial", "adversarial": true, "name": "the vread differs from the history's entry for the same version",
   "versions": {"Vx": {"from": "V", "patch": {"class": {"code": "EMER"}}}}, "vread": "Vx", "outcome": "unknown", "reason": "vread_differs", "path": "/class/code"},
  {"group": "adversarial", "adversarial": true, "name": "a field outside the location changed on write (normalise_body)",
   "versions": {"V": {"patch": {"class": {"code": "EMER"}}}}, "outcome": "unknown", "reason": "field_differs", "path": "/class/code",
   "contains": ["differs from the approved body at /class/code"]},
  {"group": "adversarial", "adversarial": true, "name": "meta.security added on write",
   "versions": {"V": {"patch": {"meta": {"security": [{"system": "http://terminology.hl7.org/CodeSystem/v3-Confidentiality", "code": "R"}]}}}},
   "outcome": "unknown", "reason": "field_differs", "path": "/meta/security"},
  {"group": "adversarial", "adversarial": true, "name": "another tag dropped on write",
   "versions": {"base": {"patch": {"meta": {"tag": [{"system": "urn:other", "code": "keep"}]}}}, "V": {"patch": {"meta": {"tag": [{"system": "urn:shutter:recovery", "code": "#OPID"}]}}}},
   "outcome": "unknown", "reason": "field_differs"},
  {"group": "adversarial", "adversarial": true, "name": "a subject changed on write", "versions": {"V": {"patch": {"subject": {"reference": "Patient/demo-p2"}}}},
   "outcome": "unknown", "reason": "field_differs", "path": "/subject/reference"},
  {"group": "adversarial", "adversarial": true, "name": "a modifierExtension added on write", "versions": {"V": {"patch": {"modifierExtension": [{"url": "urn:x", "valueBoolean": true}]}}},
   "outcome": "unknown", "reason": "field_differs", "path": "/modifierExtension"},
  {"group": "adversarial", "adversarial": true, "name": "a context that asks to ignore subject", "ctx": {"binding": {"server_owned_fields": ["subject"]}},
   "outcome": "unknown", "reason": "context_invalid"},
  {"group": "adversarial", "adversarial": true, "name": "a context that asks to ignore meta.tag", "ctx": {"binding": {"server_owned_fields": ["meta.tag"]}},
   "outcome": "unknown", "reason": "context_invalid"},
  {"group": "adversarial", "adversarial": true, "name": "a context that asks to ignore a modifier extension", "ctx": {"binding": {"server_owned_fields": ["location.modifierExtension"]}},
   "outcome": "unknown", "reason": "context_invalid"},
  {"group": "adversarial", "adversarial": true, "name": "the marked version's previous entry completed at another time",
   "versions": {"V": {"patch": {"location": ["@D", {"location": {"reference": "Location/ward-a"}, "status": "completed", "period": {"start": "2026-11-07T09:00:00Z", "end": "2026-11-08T09:30:00Z"}}, "@B"]}}},
   "outcome": "failed", "reason": "introducing_not_projection", "path": "/location/1/period/end"},
  {"group": "adversarial", "adversarial": true, "name": "the marked version has a third new location entry",
   "versions": {"V": {"patch": {"location": ["@D", "@Ac", "@B", "@C"]}}}, "outcome": "failed", "reason": "introducing_not_projection", "path": "/location/3"},
  {"group": "adversarial", "adversarial": true, "name": "the marked version moved the patient elsewhere",
   "versions": {"V": {"patch": {"location": ["@D", "@Ac", {"location": {"reference": "Location/ward-c"}, "status": "active", "period": {"start": "2026-11-08T09:00:00Z"}}]}}},
   "outcome": "failed", "reason": "introducing_not_projection"},
  {"group": "adversarial", "adversarial": true, "name": "the marker twice on the marked version",
   "versions": {"V": {"patch": {"meta": {"tag": [{"system": "urn:shutter:recovery", "code": "#OPID"}, {"system": "urn:shutter:recovery", "code": "#OPID"}]}}}},
   "outcome": "failed", "reason": "introducing_not_projection", "path": "/meta/tag"},
  {"group": "adversarial", "adversarial": true, "name": "an expected body that is not the base's shape cannot vouch for itself",
   "versions": {"expected": {"patch": {"location": ["@D", "@A0", "@B"]}}}, "outcome": "failed", "reason": "introducing_not_projection"},
  {"group": "adversarial", "adversarial": true, "name": "an expected body with another field changed cannot vouch for itself",
   "versions": {"expected": {"patch": {"class": {"code": "EMER"}}}}, "outcome": "failed", "reason": "introducing_not_projection", "path": "/class/code"},
  {"group": "adversarial", "adversarial": true, "name": "an Encounter identifier matched only case-insensitively (the search is case-insensitive on IRIS)",
   "versions": {"base": {"patch": {"identifier": [{"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49", "value": "abc-77"}]}}},
   "ctx": {"binding": {"encounter_identifier": {"value": "AbC-77"}}}, "outcome": "unknown", "reason": "identity_differs", "path": "/identifier"},
  {"group": "adversarial", "adversarial": true, "name": "the Encounter carries a second value under the bound system",
   "versions": {"base": {"patch": {"identifier": [{"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49", "value": "V1001"}, {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49", "value": "V1002"}]}}},
   "outcome": "unknown", "reason": "identity_differs"},
  {"group": "adversarial", "adversarial": true, "name": "the Encounter's subject is not the bound Patient", "ctx": {"binding": {"patient": {"reference": "Patient/demo-p2"}}},
   "outcome": "unknown", "reason": "identity_differs", "path": "/subject"},
  {"group": "adversarial", "adversarial": true, "name": "the Patient read again differs only by case", "patient_patch": {"identifier": [{"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.48", "value": "MRN-AB77"}]},
   "outcome": "committed_review", "reason": "patient_changed"},
  {"group": "adversarial", "adversarial": true, "name": "the Patient read again has a link (merged)", "patient_patch": {"link": [{"other": {"reference": "Patient/demo-p9"}, "type": "replaced-by"}]},
   "outcome": "committed_review", "reason": "patient_changed"},
  {"group": "adversarial", "adversarial": true, "name": "the Patient read again is inactive", "patient_patch": {"active": false}, "outcome": "committed_review", "reason": "patient_changed"},
  {"group": "adversarial", "adversarial": true, "name": "the Patient could not be read again", "ctx": {"patient": {"http_status": 404, "body": "Not Found"}},
   "outcome": "committed_review", "reason": "patient_changed", "retry": true},
  {"group": "adversarial", "adversarial": true, "name": "the target Location read again is inactive", "location_patch": {"Location/ward-b": {"status": "inactive"}},
   "outcome": "committed_review", "reason": "location_changed"},
  {"group": "adversarial", "adversarial": true, "name": "the target Location's identifier changed", "location_patch": {"Location/ward-b": {"identifier": [{"system": "urn:shutter:demo:ward", "value": "WARD-B2"}]}},
   "outcome": "committed_review", "reason": "location_changed"},
  {"group": "adversarial", "adversarial": true, "name": "the target Location's identifier differs only by case", "location_patch": {"Location/ward-b": {"identifier": [{"system": "urn:shutter:demo:ward", "value": "ward-b"}]}},
   "outcome": "committed_review", "reason": "location_changed"},
  {"group": "adversarial", "adversarial": true, "name": "a bound Location could not be read again", "location_read": {"Location/ward-b": {"http_status": 0, "body": ""}},
   "outcome": "committed_review", "reason": "location_changed", "retry": true, "detail": {"note": "Location/ward-b was not read"}},
  {"group": "adversarial", "adversarial": true, "name": "the target Location answered 404 when read again", "location_read": {"Location/ward-b": {"http_status": 404, "body": "Not Found"}},
   "outcome": "committed_review", "reason": "location_changed", "retry": true, "detail": {"note": "Location/ward-b was not read"}},
  {"group": "context", "adversarial": true, "name": "no Location bound and none read: nothing would be read again", "ctx": {"binding": {"locations": []}, "locations": []},
   "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "the target left out of the bound Locations while it is now inactive",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": "WARD-A"}, {"reference": "Location/ward-c", "checked_identifier": "WARD-C"}]}},
   "location_patch": {"Location/ward-b": {"status": "inactive"}}, "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "the prior left out of the bound Locations",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-b", "checked_identifier": "WARD-B"}, {"reference": "Location/ward-c", "checked_identifier": "WARD-C"}]}},
   "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "a bound Location with no read at all (a walk that skipped it)", "location_read": {"Location/ward-c": "absent"},
   "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "a bound Location read twice, the second read inactive", "location_twice": {"Location/ward-b": {"status": "inactive"}},
   "outcome": "unknown", "reason": "context_invalid"},
  {"group": "adversarial", "adversarial": true, "name": "a later writer added a modifierExtension to the Encounter",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", "@C"], "meta": {"tag": null}, "modifierExtension": [{"url": "http://example.org/fhir/StructureDefinition/encounter-void", "valueBoolean": true}]}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape", "path": "/modifierExtension"},
  {"group": "adversarial", "adversarial": true, "name": "a later writer put a modifierExtension on Shutter's still-open entry",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", {"location": {"reference": "Location/ward-b"}, "status": "active", "period": {"start": "2026-11-08T09:00:00Z"}, "modifierExtension": [{"url": "http://example.org/fhir/StructureDefinition/entry-void", "valueBoolean": true}]}], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape", "path": "/location/2/modifierExtension"},
  {"group": "adversarial", "adversarial": true, "name": "a later writer put a modifierExtension on a participant",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"participant": [{"modifierExtension": [{"url": "urn:x", "valueBoolean": true}], "individual": {"reference": "Practitioner/p1"}}], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape", "path": "/participant/0/modifierExtension"},
  {"group": "adversarial", "adversarial": true, "name": "a later writer set implicitRules",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"implicitRules": "http://example.org/rules", "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape", "path": "/implicitRules"},
  {"group": "adversarial", "adversarial": true, "name": "Shutter's entry ends at 10:30 and the next ward opens at 14:00: a gap, not a continuation",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", {"location": {"reference": "Location/ward-c"}, "status": "active", "period": {"start": "2026-11-08T14:00:00Z"}}], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape", "path": "/location/3"},
  {"group": "adversarial", "adversarial": true, "name": "finished, the next ward completed but opened after a gap",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"status": "finished", "location": ["@D", "@Ac", "@Bc", {"location": {"reference": "Location/ward-c"}, "status": "completed", "period": {"start": "2026-11-08T14:00:00Z", "end": "2026-11-08T16:00:00Z"}}], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape", "path": "/location/3"},
  {"group": "adversarial", "adversarial": true, "name": "a later move through a location outside the map, then on to WARD-C",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", {"location": {"reference": "Location/ward-b"}, "status": "completed", "period": {"start": "2026-11-08T09:00:00Z", "end": "2026-11-08T10:00:00Z"}}, {"location": {"reference": "Location/ward-x"}, "status": "completed", "period": {"start": "2026-11-08T10:00:00Z", "end": "2026-11-08T10:30:00Z"}}, "@C"], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape"},
  {"group": "adversarial", "adversarial": true, "name": "finished after a move back to the prior ward, completed",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"status": "finished", "location": ["@D", "@Ac", "@Bc", {"location": {"reference": "Location/ward-a"}, "status": "completed", "period": {"start": "2026-11-08T10:30:00Z", "end": "2026-11-08T12:00:00Z"}}], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape", "path": "/location/3"},
  {"group": "positive", "name": "the next ward opens exactly at Shutter's end, the two instants written with different offsets",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", {"location": {"reference": "Location/ward-b"}, "status": "completed", "period": {"start": "2026-11-08T09:00:00Z", "end": "2026-11-08T10:30:00Z"}}, "@C"], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "verified_continued", "reason": "committed_continued"},
  {"group": "positive", "name": "finished after a move on to WARD-C that starts at Shutter's end",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"status": "finished", "location": ["@D", "@Ac", "@Bc", {"location": {"reference": "Location/ward-c"}, "status": "completed", "period": {"start": "2026-11-08T10:30:00Z", "end": "2026-11-08T12:00:00Z"}}], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "verified_continued", "reason": "committed_continued"},
  {"group": "adversarial", "adversarial": true, "name": "a later writer moved the patient back to WARD-A",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", {"location": {"reference": "Location/ward-a"}, "status": "active", "period": {"start": "2026-11-08T10:30:00Z"}}], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "prior_active_again", "detail": {"current_version": "8"}},
  {"group": "adversarial", "adversarial": true, "name": "a blind overwrite from a stale read: the base's body written again (the move undone)",
   "versions": {"W": {"from": "base", "vid": "8"}}, "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "entry_gone",
   "contains": ["The approved update is present in version \"7\"", "no longer shows the move"]},
  {"group": "adversarial", "adversarial": true, "name": "a later writer removed Shutter's entry",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@C"]}}}, "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "entry_gone"},
  {"group": "adversarial", "adversarial": true, "name": "a later writer completed Shutter's entry at its own start",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", {"location": {"reference": "Location/ward-b"}, "status": "completed", "period": {"start": "2026-11-08T09:00:00Z", "end": "2026-11-08T10:00:00+01:00"}}, {"location": {"reference": "Location/ward-c"}, "status": "active", "period": {"start": "2026-11-08T09:00:00Z"}}]}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "entry_closed_at_own_start"},
  {"group": "adversarial", "adversarial": true, "name": "a later writer set the Encounter entered-in-error",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"status": "entered-in-error"}}}, "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "entered_in_error"},
  {"group": "adversarial", "adversarial": true, "name": "a later writer left two open entries",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@B", "@C"]}}}, "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "overlapping_periods"},
  {"group": "adversarial", "adversarial": true, "name": "a later move that starts before Shutter's entry ends",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", {"location": {"reference": "Location/ward-b"}, "status": "completed", "period": {"start": "2026-11-08T09:00:00Z", "end": "2026-11-08T11:00:00Z"}}, "@C"]}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "overlapping_periods"},
  {"group": "adversarial", "adversarial": true, "name": "a later open entry that starts before Shutter's move",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", {"location": {"reference": "Location/ward-c"}, "status": "active", "period": {"start": "2026-11-08T08:00:00Z"}}]}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "overlapping_periods"},
  {"group": "adversarial", "adversarial": true, "name": "a later writer's times without a time of day",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", {"location": {"reference": "Location/ward-b"}, "status": "completed", "period": {"start": "2026-11-08T09:00:00Z", "end": "2026-11-08"}}, {"location": {"reference": "Location/ward-c"}, "status": "active", "period": {"start": "2026-11-08"}}]}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape"},
  {"group": "adversarial", "adversarial": true, "name": "a later move to a location outside the map",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", {"location": {"reference": "Location/ward-x"}, "status": "active", "period": {"start": "2026-11-08T10:30:00Z"}}]}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape"},
  {"group": "adversarial", "adversarial": true, "name": "a later move by display text only, no literal reference",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", {"location": {"display": "Ward C"}, "status": "active", "period": {"start": "2026-11-08T10:30:00Z"}}]}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape"},
  {"group": "adversarial", "adversarial": true, "name": "in progress with no open entry after a later writer",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc"]}}}, "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape"},
  {"group": "adversarial", "adversarial": true, "name": "finished with an entry still open",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"status": "finished"}}}, "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape"},
  {"group": "adversarial", "adversarial": true, "name": "a later status this check does not judge (cancelled)",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"status": "cancelled"}}}, "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "unfamiliar_shape"},
  {"group": "adversarial", "adversarial": true, "name": "a later writer changed the subject",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"subject": {"reference": "Patient/demo-p2"}}}}, "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "committed_review", "reason": "identity_differs"},
  {"group": "adversarial", "adversarial": true, "name": "the current read is ahead of the history (another replica)",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", "@C"]}}}, "current": "W", "outcome": "committed_review", "reason": "current_not_in_history", "retry": true},
  {"group": "adversarial", "adversarial": true, "name": "the current read claims Shutter's version with another body",
   "versions": {"Vx": {"from": "V", "patch": {"location": ["@D", "@A0"]}}}, "current": "Vx", "outcome": "committed_review", "reason": "current_not_in_history"},
  {"group": "adversarial", "adversarial": true, "name": "the current read is Shutter's version while the history shows a later one",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@A0"]}}}, "history": ["W", "V", "base", "v5"], "current": "V",
   "outcome": "committed_review", "reason": "current_not_in_history"},
  {"group": "adversarial", "adversarial": true, "name": "the current read's body is not the history's head",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", "@C"]}}, "Wx": {"from": "W", "patch": {"location": ["@D", "@A0"]}}},
   "history": ["W", "V", "base", "v5"], "current": "Wx", "outcome": "committed_review", "reason": "current_not_in_history"},
  {"group": "adversarial", "adversarial": true, "name": "the current read with a strong ETag", "ctx": {"current": {"etag": "\"7\""}}, "outcome": "committed_review", "reason": "current_unreadable", "retry": true},
  {"group": "adversarial", "adversarial": true, "name": "the current read an HTML 200 at the last read", "seconds": 70, "attempt": "lost",
   "ctx": {"current": {"content_type": "text/html", "body": "<html></html>"}}, "outcome": "committed_review", "reason": "current_unreadable", "retry": false},
  {"group": "adversarial", "adversarial": true, "name": "the current read 404 in plain text (a refused login on IRIS)",
   "ctx": {"current": {"http_status": 404, "content_type": "text/html; charset=UTF-8", "body": "Not Found"}}, "outcome": "committed_review", "reason": "current_unreadable"},
  {"group": "adversarial", "adversarial": true, "name": "applied with W/\"7\" while the complete history shows another writer's \"8\" and no \"7\"",
   "versions": {"X": {"from": "base", "vid": "8", "patch": {"type": [{"text": "clerk edit"}]}}}, "history": ["X", "base", "v5"], "current": "X",
   "outcome": "failed", "reason": "applied_version_absent"},
  {"group": "adversarial", "adversarial": true, "name": "Shutter's version committed, overwritten, then left out of the history (its answer kept)",
   "versions": {"W": {"from": "base", "vid": "8"}}, "history": ["W", "base", "v5"], "current": "W", "vread": null,
   "outcome": "failed", "reason": "applied_version_absent"},
  {"group": "adversarial", "adversarial": true, "name": "Shutter's version committed, overwritten, then left out of the history (its answer lost)",
   "versions": {"W": {"from": "base", "vid": "8"}}, "history": ["W", "base", "v5"], "current": "W", "attempt": "lost", "seconds": 70,
   "outcome": "not_found", "reason": "no_committed_version", "detail": {"head_version": "8", "base_version": "6"}},
  {"group": "adversarial", "adversarial": true, "name": "applied with W/\"7\" while the history still ends at the base", "history": ["base", "v5"], "current": "base", "vread": null,
   "outcome": "unknown", "reason": "head_is_base", "retry": true},
  {"group": "adversarial", "adversarial": true, "name": "a 201 on the PUT", "attempt": "created", "outcome": "failed", "reason": "update_created"},
  {"group": "adversarial", "adversarial": true, "name": "a 412 and yet the marked, correct version is there", "attempt": "conflict", "seconds": 70,
   "outcome": "failed", "reason": "conflict_but_committed"},
  {"group": "adversarial", "adversarial": true, "name": "a refusal with an OperationOutcome and yet the marked version is there", "attempt": "refused",
   "outcome": "failed", "reason": "conflict_but_committed"},
  {"group": "adversarial", "adversarial": true, "name": "a lost answer, the head still the base, at 0 s", "attempt": "lost", "seconds": 0, "history": ["base", "v5"], "current": "base",
   "outcome": "unknown", "reason": "head_is_base", "retry": true},
  {"group": "adversarial", "adversarial": true, "name": "a lost answer, the head still the base, at 10 s", "attempt": "lost", "seconds": 10, "history": ["base", "v5"], "current": "base",
   "outcome": "unknown", "reason": "head_is_base", "retry": true},
  {"group": "adversarial", "adversarial": true, "name": "a lost answer, the head still the base, at 30 s", "attempt": "lost", "seconds": 30, "history": ["base", "v5"], "current": "base",
   "outcome": "unknown", "reason": "head_is_base", "retry": true},
  {"group": "adversarial", "adversarial": true, "name": "a lost answer, the head still the base, at 70 s: unknown, never not committed", "attempt": "lost", "seconds": 70, "history": ["base", "v5"], "current": "base",
   "outcome": "unknown", "reason": "head_is_base", "retry": false, "contains": ["may yet land"]},

  {"group": "not_committed", "adversarial": true, "name": "a 412 at 70 s, another writer's \"8\" after the base, no marker and no projection",
   "attempt": "conflict", "seconds": 70, "versions": {"X": {"from": "base", "vid": "8", "patch": {"type": [{"text": "clerk edit"}]}}},
   "history": ["X", "base", "v5"], "current": "X", "outcome": "not_found", "reason": "no_committed_version", "detail": {"head_version": "8", "base_version": "6"},
   "equals": "No version of this update was found in the history the receiver returned, from version \"8\" back to the base \"6\"; the receiver's history is not a proof that none was committed."},
  {"group": "not_committed", "adversarial": true, "name": "the same at 10 s: still settling",
   "attempt": "conflict", "seconds": 10, "versions": {"X": {"from": "base", "vid": "8", "patch": {"type": [{"text": "clerk edit"}]}}},
   "history": ["X", "base", "v5"], "current": "X", "outcome": "unknown", "reason": "settling", "retry": true},
  {"group": "not_committed", "adversarial": true, "name": "a lost answer at 70 s, another writer's \"8\" after the base",
   "attempt": "lost", "seconds": 70, "versions": {"X": {"from": "base", "vid": "8", "patch": {"type": [{"text": "clerk edit"}]}}},
   "history": ["X", "base", "v5"], "current": "X", "outcome": "not_found", "reason": "no_committed_version"},
  {"group": "not_committed", "adversarial": true, "name": "a socket that never opened, at 70 s, another writer's \"8\" after the base",
   "attempt": "lost", "seconds": 70, "ctx": {"attempt": {"outcome": "error"}}, "versions": {"X": {"from": "base", "vid": "8", "patch": {"type": [{"text": "clerk edit"}]}}},
   "history": ["X", "base", "v5"], "current": "X", "outcome": "not_found", "reason": "no_committed_version"},

  {"group": "context", "adversarial": true, "name": "every body missing", "ctx": {"base_body": null, "expected_body": null, "history": null, "current": null, "patient": null, "vread": null},
   "outcome": "unknown", "reason": "context_invalid", "retry": false},
  {"group": "context", "adversarial": true, "name": "an operation id that is not 32 lower-case hex", "ctx": {"binding": {"operation_id": "3F9A"}}, "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "the base body's version is not the binding's", "ctx": {"binding": {"base_version_id": "5", "expected_etag": "W/\"5\""}}, "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "the expected ETag is not the base version's", "ctx": {"binding": {"expected_etag": "\"6\""}}, "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "an expected body without the marker", "versions": {"expected": {"patch": {"meta": {"tag": null}}}}, "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "an applied attempt without its answer's ETag", "ctx": {"attempt": {"response_etag": null}}, "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "an attempt outcome the connector never records", "ctx": {"attempt": {"outcome": "ok"}}, "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "an event time without an offset", "ctx": {"binding": {"event_time": "2026-11-08T09:00:00"}}, "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "a base body of another Encounter", "ctx": {"binding": {"encounter_id": "enc-2"}}, "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "an attempt without its age", "ctx": {"attempt": {"seconds_since": "10"}}, "outcome": "unknown", "reason": "context_invalid"},

  {"group": "limitation", "name": "If-Match ignored and the other writer's version left out of the history: indistinguishable from a clean write, so it verifies; the words name the history as the assumption",
   "vids": {"V": "8"}, "outcome": "verified", "reason": "committed_current"},
  {"group": "limitation", "name": "an intermediate version after Shutter's left out of the history: Shutter's version still follows the base",
   "versions": {"W": {"from": "V", "vid": "9", "patch": {"location": ["@D", "@Ac", "@Bc", "@C"], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "outcome": "verified_continued", "reason": "committed_continued"},
  {"group": "positive", "name": "the bound Locations checked by system and value, each carrying the exact pair",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}, {"reference": "Location/ward-c", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-C"}}]}},
   "outcome": "verified", "reason": "committed_current", "retry": false},
  {"group": "positive", "name": "one bound Location checked by the pair and the others by the value alone",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": "WARD-A"}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}, {"reference": "Location/ward-c", "checked_identifier": "WARD-C"}]}},
   "outcome": "verified", "reason": "committed_current"},
  {"group": "adversarial", "adversarial": true, "name": "checked by the pair, the target Location carries the value under another system",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}, {"reference": "Location/ward-c", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-C"}}]}}, "location_patch": {"Location/ward-b": {"identifier": [{"system": "urn:another:ward", "value": "WARD-B"}]}},
   "outcome": "committed_review", "reason": "location_changed", "retry": false, "detail": {"committed_version": "7"}},
  {"group": "adversarial", "adversarial": true, "name": "checked by the pair, the prior Location carries the system with another value",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}, {"reference": "Location/ward-c", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-C"}}]}}, "location_patch": {"Location/ward-a": {"identifier": [{"system": "urn:shutter:demo:ward", "value": "WARD-Z"}]}},
   "outcome": "committed_review", "reason": "location_changed"},
  {"group": "adversarial", "adversarial": true, "name": "checked by the pair, the value in another letter case",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}, {"reference": "Location/ward-c", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-C"}}]}}, "location_patch": {"Location/ward-c": {"identifier": [{"system": "urn:shutter:demo:ward", "value": "ward-c"}]}},
   "outcome": "committed_review", "reason": "location_changed"},
  {"group": "adversarial", "adversarial": true, "name": "checked by the pair, the system and the value on two different identifiers",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}, {"reference": "Location/ward-c", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-C"}}]}}, "location_patch": {"Location/ward-b": {"identifier": [{"system": "urn:shutter:demo:ward", "value": "WARD-Q"}, {"system": "urn:another:ward", "value": "WARD-B"}]}},
   "outcome": "committed_review", "reason": "location_changed"},
  {"group": "adversarial", "adversarial": true, "name": "checked by the pair, the target Location carries a second value under the mapped system",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}, {"reference": "Location/ward-c", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-C"}}]}}, "location_patch": {"Location/ward-b": {"identifier": [{"system": "urn:shutter:demo:ward", "value": "WARD-B"}, {"system": "urn:shutter:demo:ward", "value": "WARD-C"}]}},
   "outcome": "committed_review", "reason": "location_changed", "retry": false, "detail": {"committed_version": "7", "note": "Location/ward-b no longer carries the identifier WARD-B and no other under its system"}},
  {"group": "adversarial", "adversarial": true, "name": "checked by the pair, the prior Location carries another value under the mapped system before its own",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}, {"reference": "Location/ward-c", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-C"}}]}}, "location_patch": {"Location/ward-a": {"identifier": [{"system": "urn:shutter:demo:ward", "value": "WARD-Z"}, {"system": "urn:shutter:demo:ward", "value": "WARD-A"}]}},
   "outcome": "committed_review", "reason": "location_changed", "retry": false},
  {"group": "positive", "name": "checked by the pair, a Location carrying another system's identifier beside the mapped pair",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}, {"reference": "Location/ward-c", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-C"}}]}}, "location_patch": {"Location/ward-b": {"identifier": [{"system": "urn:another:ward", "value": "WARD-Q"}, {"system": "urn:shutter:demo:ward", "value": "WARD-B"}]}},
   "outcome": "verified", "reason": "committed_current"},
  {"group": "positive", "name": "checked by the value alone, a Location carrying a second value under the same system (the value is looked for under any system)",
   "location_patch": {"Location/ward-b": {"identifier": [{"system": "urn:shutter:demo:ward", "value": "WARD-B"}, {"system": "urn:shutter:demo:ward", "value": "WARD-C"}]}},
   "outcome": "verified", "reason": "committed_current"},
  {"group": "context", "adversarial": true, "name": "a checked identifier pair with no system",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": {"value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}, {"reference": "Location/ward-c", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-C"}}]}},
   "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "a checked identifier pair with an empty value",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": ""}}, {"reference": "Location/ward-c", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-C"}}]}},
   "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "a checked identifier that is a list",
   "ctx": {"binding": {"locations": [{"reference": "Location/ward-a", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-A"}}, {"reference": "Location/ward-b", "checked_identifier": {"system": "urn:shutter:demo:ward", "value": "WARD-B"}}, {"reference": "Location/ward-c", "checked_identifier": ["WARD-C"]}]}},
   "outcome": "unknown", "reason": "context_invalid"},
  {"group": "context", "adversarial": true, "name": "applied with a usable ETag and no vread in the context (the version was never read by id)", "vread": null,
   "outcome": "unknown", "reason": "context_invalid", "retry": false, "detail": {"committed_version": "7"}},
  {"group": "context", "adversarial": true, "name": "a usable ETag and no vread, with a later writer's supported continuation as the current version",
   "versions": {"W": {"from": "V", "vid": "8", "patch": {"location": ["@D", "@Ac", "@Bc", "@C"], "meta": {"tag": null}}}},
   "history": ["W", "V", "base", "v5"], "current": "W", "vread": null, "outcome": "unknown", "reason": "context_invalid"},
  {"group": "positive", "name": "a lost answer has no ETag, so no vread is asked for", "attempt": "lost", "seconds": 70, "vread": null,
   "outcome": "verified", "reason": "committed_current"}
]
}

}
