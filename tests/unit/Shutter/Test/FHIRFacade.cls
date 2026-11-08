/// The test FHIR server (FHIRFacade.Service) in process, with its clock fixed: each test holds it to an answer IRIS for
/// Health's own FHIR server gave when it was measured on 2026.2, 2026.3.0AI.154 and 2027.1.0AI.109 (the JsonAdvSQL
/// strategy, R4 core). The conformance class runs the measured exchanges one by one; these tests look at the same
/// behaviour from the side of the store (what was written, what was not) and at the cases the exchanges do not cover.
/// The 403 for a caller without FHIRFacade_API belongs to FHIRFacade.API and the web application, so it is not here.
Class Shutter.Test.FHIRFacade Extends %UnitTest.TestCase
{

Parameter SERVICE = "FHIRFacade.Service";

Parameter BASE = "http://facade.test/fhir/r4";

Parameter CLOCK = "2026-11-08T02:31:53Z";

Parameter SYS = "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49";

Method OnBeforeOneTest(testname As %String) As %Status
{
    If ..Loaded() {
        Do $CLASSMETHOD(..#SERVICE, "Reset")
        Do $CLASSMETHOD(..#SERVICE, "SetClock", ..#CLOCK)
    }
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    If ..Loaded() {
        Do $CLASSMETHOD(..#SERVICE, "Reset")
        Do $CLASSMETHOD(..#SERVICE, "SetClock", "")
    }
    Quit $$$OK
}

/// Read, vread and history of a seeded Encounter carry IRIS's headers: the weak ETag of meta.versionId, the version's
/// Location, an HTTP date, and the FHIR JSON content type with its charset.
Method TestReadVreadHistoryHeaders()
{
    Quit:'..Ready()
    Do ..Seed()
    Set r = ..Get("Encounter/enc-1")
    Do $$$AssertEquals(r.status, 200, "read")
    Do $$$AssertEquals(r.headers.ETag, "W/""1""", "the ETag")
    Do $$$AssertEquals(r.headers.Location, ..#BASE _ "/Encounter/enc-1/_history/1", "the Location")
    Do $$$AssertEquals(r.headers.%Get("Last-Modified"), "Sun, 08 Nov 2026 02:31:53 GMT", "Last-Modified as an HTTP date")
    Do $$$AssertEquals(r.headers.%Get("Content-Type"), "application/fhir+json; charset=UTF-8", "the content type")
    Set body = {}.%FromJSON(r.body)
    Do $$$AssertEquals(body.meta.versionId, "1", "meta.versionId")
    Do $$$AssertEquals(body.meta.lastUpdated, ..#CLOCK, "meta.lastUpdated from the clock, to the second")
    Set v = ..Get("Encounter/enc-1/_history/1")
    Do $$$AssertEquals(v.status, 200, "vread")
    Do $$$AssertEquals(v.body, r.body, "the vread is the read")
    Set h = ..Get("Encounter/enc-1/_history")
    Do $$$AssertEquals(h.status, 200, "history")
    Do $$$AssertEquals(h.headers.%IsDefined("ETag"), 0, "a history answer has no ETag")
    Do $$$AssertEquals({}.%FromJSON(h.body).type, "history", "a history Bundle")
}

/// On every answer that names a version (create, update, read, vread) the ETag is W/" + meta.versionId + ".
Method TestEtagIsAlwaysTheVersionId()
{
    Quit:'..Ready()
    Do ..Seed()
    For i = 1:1:4 {
        Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "", "return=representation")
        Do $$$AssertEquals(w.headers.ETag, "W/""" _ {}.%FromJSON(w.body).meta.versionId _ """", "update " _ i)
        Set r = ..Get("Encounter/enc-1")
        Do $$$AssertEquals(r.headers.ETag, "W/""" _ {}.%FromJSON(r.body).meta.versionId _ """", "read after update " _ i)
        Set v = ..Get("Encounter/enc-1/_history/" _ (i + 1))
        Do $$$AssertEquals(v.headers.ETag, "W/""" _ (i + 1) _ """", "vread " _ (i + 1))
    }
}

/// The five forms IRIS refuses are 405 with its text and write nothing; spaces around the header are dropped, as HTTP
/// drops them (IRIS took W/"2" with a trailing space).
Method TestMalformedIfMatchIs405AndWritesNothing()
{
    Quit:'..Ready()
    Do ..Seed()
    Do ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""")
    For form = """2""", "2", "W/2", "w/""2""", "*" {
        Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), form)
        Do $$$AssertEquals(w.status, 405, form)
        Do $$$AssertEquals(..Issue(w).diagnostics, "<HSFHIRErr>InvalidIfMatch", form)
        Do $$$AssertEquals(..Issue(w).details.text, "Invalid 'If-Match' header, '" _ form _ "', must be formatted as 'W/""[versionId]""'", form)
        Do $$$AssertEquals(..Versions("Encounter", "enc-1"), 2, "nothing written by " _ form)
    }
    Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""2"" ")
    Do $$$AssertEquals(w.status, 200, "a trailing space is not part of the value")
    Do $$$AssertEquals(w.headers.ETag, "W/""3""", "and the write is version 3")
}

/// A stale If-Match is 412 with IRIS's text and writes nothing; no If-Match on an existing id is an unguarded 200;
/// If-Match on an id never written is 412 with current version '' and the id stays unknown; without If-Match it is
/// created (201).
Method TestStaleUnknownAndUnguardedWrites()
{
    Quit:'..Ready()
    Do ..Seed()
    Do ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""")
    Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""")
    Do $$$AssertEquals(w.status, 412, "stale")
    Do $$$AssertEquals(..Issue(w).code, "concurrency", "stale code")
    Do $$$AssertEquals(..Issue(w).details.text, "The version in the 'If-Match' header, '1', does not match the current version, '2'", "stale text")
    Do $$$AssertEquals(w.headers.%Get("Content-Type"), "application/fhir+json; charset=UTF-8", "a refusal is FHIR JSON")
    Do $$$AssertEquals(..Versions("Encounter", "enc-1"), 2, "nothing written by the stale PUT")
    Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"))
    Do $$$AssertEquals(w.status, 200, "no If-Match on an existing id")
    Do $$$AssertEquals(w.headers.ETag, "W/""3""", "a new version")
    Set w = ..Put("Encounter/enc-new", ..Enc("enc-new", "V1999"), "W/""1""")
    Do $$$AssertEquals(w.status, 412, "If-Match on an unknown id")
    Do $$$AssertEquals(..Issue(w).details.text, "The version in the 'If-Match' header, '1', does not match the current version, ''", "current version ''")
    Do $$$AssertEquals(..Get("Encounter/enc-new").status, 404, "the unknown id stays unknown")
    Do $$$AssertEquals(..Issue(..Get("Encounter/enc-new")).details.text, "No resource with type 'Encounter' and id 'enc-new'", "404 text")
    Set w = ..Put("Encounter/enc-new", ..Enc("enc-new", "V1999"))
    Do $$$AssertEquals(w.status, 201, "update as create without If-Match")
    Do $$$AssertEquals(w.headers.ETag, "W/""1""", "version 1")
}

/// Delete takes a version; the read and the delete's vread are 410; the version before stays readable; the pre-delete
/// ETag is stale; the delete's own ETag brings the resource back as an update (200); the history's delete entry has no
/// resource.
Method TestDeleteAndResurrection()
{
    Quit:'..Ready()
    Do ..Seed()
    Set d = ..Call("DELETE", "Encounter/enc-1")
    Do $$$AssertEquals(d.status, 204, "delete")
    Do $$$AssertEquals(d.headers.ETag, "W/""2""", "the delete's ETag")
    Do $$$AssertEquals(d.body, "", "no body")
    Set r = ..Get("Encounter/enc-1")
    Do $$$AssertEquals(r.status, 410, "read of a deleted resource")
    Do $$$AssertEquals(..Issue(r).details.text, "Resource was previously deleted (type='Encounter', id='enc-1', version='').", "410 text")
    Do $$$AssertEquals(..Get("Encounter/enc-1/_history/1").status, 200, "the version before the delete")
    Set v = ..Get("Encounter/enc-1/_history/2")
    Do $$$AssertEquals(v.status, 410, "vread of the delete")
    Do $$$AssertEquals(..Issue(v).details.text, "Resource was previously deleted (type='Encounter', id='enc-1', version='2').", "410 vread text")
    Set h = {}.%FromJSON(..Get("Encounter/enc-1/_history").body)
    Do $$$AssertEquals(h.entry.%Get(0).request.method, "DELETE", "the delete entry first")
    Do $$$AssertEquals(h.entry.%Get(0).%IsDefined("resource"), 0, "with no resource")
    Do $$$AssertEquals(h.entry.%Get(0).response.status, "200", "and status 200")
    Do $$$AssertEquals(..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""").status, 412, "the pre-delete ETag is stale")
    Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""2""")
    Do $$$AssertEquals(w.status, 200, "the delete's ETag brings it back as an update")
    Do $$$AssertEquals(w.headers.ETag, "W/""3""", "version 3")
    Do $$$AssertEquals(..Get("Encounter/enc-1").status, 200, "readable again")
    Do $$$AssertEquals(..Call("DELETE", "Encounter/enc-unknown").status, 404, "delete of an id never written")
}

/// An unchanged PUT makes a new version that differs from what was sent only in meta.versionId and meta.lastUpdated;
/// the client's own values are overwritten in place; with no meta, meta is appended at the end; key order, decimal
/// text, datetime precision and offsets are kept.
Method TestUnchangedPutAndClientMeta()
{
    Quit:'..Ready()
    Do ..Seed()
    Set sent = ..Enc("enc-rich", "V1004")
    Do sent.%Set("meta", {"tag": [{"system": "urn:example:other", "code": "keep-me"}], "versionId": "77", "lastUpdated": "2001-01-01T00:00:00Z"})
    Do sent.%Set("priority", {"text": "x"})
    Do ..Put("Encounter/enc-rich", sent)
    Set stored = {}.%FromJSON(..Get("Encounter/enc-rich").body)
    Do $$$AssertEquals(stored.meta.versionId, "1", "the client's versionId is overwritten")
    Do $$$AssertEquals(stored.meta.lastUpdated, ..#CLOCK, "the client's lastUpdated is overwritten")
    Do $$$AssertEquals(..Keys(stored.meta), "tag,versionId,lastUpdated", "in place, inside meta")
    Do $$$AssertEquals(..Keys(stored), "resourceType,id,status,identifier,class,subject,location,meta,priority", "and meta where it was sent")
    Do $CLASSMETHOD(..#SERVICE, "SetClock", "2026-11-08T02:32:10Z")
    Do ..Put("Encounter/enc-rich", stored, "W/""1""")
    Set again = {}.%FromJSON(..Get("Encounter/enc-rich/_history/2").body)
    Do $$$AssertEquals(again.meta.versionId, "2", "an unchanged PUT makes a version")
    Do $$$AssertEquals(again.meta.lastUpdated, "2026-11-08T02:32:10Z", "with its own time")
    Do again.meta.%Set("versionId", "1"), again.meta.%Set("lastUpdated", ..#CLOCK)
    Do $$$AssertEquals(again.%ToJSON(), stored.%ToJSON(), "and nothing else differs")
    Set raw = "{""resourceType"" : ""Encounter"", ""id"" : ""enc-raw"", ""status"" : ""in-progress"", ""length"" : {""value"" : 1.50, ""unit"" : ""h""}, ""location"":[{""location"":{""reference"":""Location/ward-a""},""status"":""active"",""period"":{""start"" : ""2026-11-07T10:00:00.000+00:00""}}], ""extension"":[{""url"":""http://example.org/ext/d"",""valueDecimal"":1.0E2}]}"
    Do $$$AssertEquals(..Call("PUT", "Encounter/enc-raw", , raw).status, 201, "raw text with spaces")
    Set text = ..Get("Encounter/enc-raw").body
    Do $$$AssertTrue(text [ """length"":{""value"":1.50,""unit"":""h""}", "1.50 kept: " _ text)
    Do $$$AssertTrue(text [ """valueDecimal"":1.0E2", "1.0E2 kept: " _ text)
    Do $$$AssertTrue(text [ """start"":""2026-11-07T10:00:00.000+00:00""", "precision and offset kept: " _ text)
    Do $$$AssertTrue(text [ "}],""meta"":{""lastUpdated"":""" _ ..#CLOCK _ """,""versionId"":""1""}}", "meta appended at the end: " _ text)
    Do $$$AssertNotTrue(text [ " ", "whitespace removed")
    Set u = "{""resourceType"":""Encounter"",""id"":""enc-u"",""status"":""in-progress"",""reasonCode"":[{""text"":""reason " _ $CHAR(233, 32, 8594) _ " unicode""}]}"
    Do ..Call("PUT", "Encounter/enc-u", , u)
    Do $$$AssertTrue(..Get("Encounter/enc-u").body [ ("reason " _ $CHAR(233, 32, 8594) _ " unicode"), "characters outside ASCII kept")
}

/// meta.tag is stored exactly as each PUT sends it, over five versions as on IRIS: the marker stays only on the version
/// that sent it.
Method TestTagReplacementOverFiveVersions()
{
    Quit:'..Ready()
    Do ..Seed()
    Set marker = {"system": "urn:shutter:recovery", "code": "op-3f9a"}
    Set e = ..Enc("enc-tag", "V1005")
    Do ..Put("Encounter/enc-tag", e)
    Set e = {}.%FromJSON(..Get("Encounter/enc-tag").body)
    Do e.meta.%Set("tag", [(marker)])
    Do ..Put("Encounter/enc-tag", e, "W/""1""")
    Set e = {}.%FromJSON(..Get("Encounter/enc-tag").body)
    Do e.meta.%Remove("tag")
    Do ..Put("Encounter/enc-tag", e, "W/""2""")
    Do e.%Remove("meta")
    Do ..Put("Encounter/enc-tag", e, "W/""3""")
    Do e.%Set("meta", {"tag": [{"system": "urn:example:other", "code": "x"}]})
    Do ..Put("Encounter/enc-tag", e, "W/""4""")
    Set expected = $LISTBUILD("", "urn:shutter:recovery|op-3f9a", "", "", "urn:example:other|x")
    For v = 1:1:5 {
        Set body = {}.%FromJSON(..Get("Encounter/enc-tag/_history/" _ v).body)
        Do $$$AssertEquals(..TagList(body), $LISTGET(expected, v), "version " _ v)
    }
    Set h = {}.%FromJSON(..Get("Encounter/enc-tag/_history").body)
    For i = 0:1:4 {
        Do $$$AssertEquals(..TagList(h.entry.%Get(i).resource), $LISTGET(expected, 5 - i), "history entry " _ i)
    }
}

/// History: newest first, response.status "200" everywhere, no fullUrl or etag, no next link with _count=5 (whole),
/// 400 for _count=0 and _count=abc with IRIS's text, 404 for an id never written. The vread of version 1 is
/// byte-identical after four updates.
Method TestHistoryShapeAndStableVread()
{
    Quit:'..Ready()
    Do ..Seed()
    Set first = ..Get("Encounter/enc-1/_history/1").body
    For v = 1:1:6 {
        Do ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""" _ v _ """")
    }
    Set h = {}.%FromJSON(..Get("Encounter/enc-1/_history", "_count=5").body)
    Do $$$AssertEquals(h.total, 7, "total")
    Do $$$AssertEquals(h.entry.%Size(), 7, "the whole history whatever _count says")
    Do $$$AssertEquals(h.link.%Size(), 1, "one link")
    Do $$$AssertEquals(h.link.%Get(0).relation, "self", "self only, no next")
    For i = 0:1:6 {
        Set entry = h.entry.%Get(i)
        Do $$$AssertEquals(entry.resource.meta.versionId, (7 - i) _ "", "newest first, entry " _ i)
        Do $$$AssertEquals(entry.response.status, "200", "status 200, entry " _ i)
        Do $$$AssertEquals(entry.%IsDefined("fullUrl") + entry.response.%IsDefined("etag"), 0, "no fullUrl or etag, entry " _ i)
        Do $$$AssertEquals(entry.request.url, "Encounter/enc-1", "request.url, entry " _ i)
    }
    For value = "0", "abc" {
        Set r = ..Get("Encounter/enc-1/_history", "_count=" _ value)
        Do $$$AssertEquals(r.status, 400, "_count=" _ value)
        Do $$$AssertEquals(..Issue(r).severity, "warning", "_count=" _ value _ " severity")
        Do $$$AssertEquals(..Issue(r).details.text, "The value '" _ value _ "' is invalid for the '_count' parameter'.", "_count=" _ value _ " text")
    }
    Do $$$AssertEquals(..Get("Encounter/enc-none/_history").status, 404, "history of an unknown id")
    Do $$$AssertEquals(..Get("Encounter/enc-1/_history/1").body, first, "vread of version 1 unchanged after the updates")
    Do $$$AssertEquals(..Get("Encounter/_history").status, 400, "type history refused")
    Do $$$AssertEquals(..Get("_history").status, 400, "system history refused")
}

/// Prefer: return=minimal, none and return=OperationOutcome give the empty text/html 200 IRIS gives; representation
/// gives the stored resource; a stale PUT returns the full OperationOutcome whatever Prefer says.
Method TestPrefer()
{
    Quit:'..Ready()
    Do ..Seed()
    Set v = 1
    For prefer = "return=minimal", "", "return=OperationOutcome" {
        Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""" _ v _ """", prefer)
        Set v = v + 1
        Do $$$AssertEquals(w.status, 200, prefer)
        Do $$$AssertEquals(w.body, "", prefer _ ": empty")
        Do $$$AssertEquals(w.headers.%Get("Content-Type"), "text/html; charset=utf-8", prefer _ ": labelled text/html")
        Do $$$AssertEquals(w.headers.ETag, "W/""" _ v _ """", prefer _ ": ETag")
        Do $$$AssertEquals(w.headers.Location, ..#BASE _ "/Encounter/enc-1/_history/" _ v, prefer _ ": Location")
    }
    Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""4""", "return=representation")
    Do $$$AssertEquals(w.headers.%Get("Content-Type"), "application/fhir+json; charset=UTF-8", "representation: FHIR JSON")
    Do $$$AssertEquals(w.body, ..Get("Encounter/enc-1").body, "representation: the stored text")
    Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""", "return=minimal")
    Do $$$AssertEquals(w.status, 412, "stale with minimal")
    Do $$$AssertEquals(..Issue(w).diagnostics, "<HSFHIRErr>IfMatchViolation", "the full OperationOutcome")
}

/// _summary=true is 400; _summary=data the full body; _elements=id,location the measured shape: resourceType, id,
/// location and a meta with only the SUBSETTED tag, the ETag still sent.
Method TestSummaryAndElements()
{
    Quit:'..Ready()
    Do ..Seed()
    Set e = ..Enc("enc-1", "V1001")
    Do e.%Set("meta", {"tag": [{"system": "urn:example:other", "code": "keep-me"}]})
    Do ..Put("Encounter/enc-1", e, "W/""1""")
    Set r = ..Get("Encounter/enc-1", "_summary=true")
    Do $$$AssertEquals(r.status, 400, "_summary=true")
    Do $$$AssertEquals(..Issue(r).details.text, "The value 'true' is invalid for query parameter '_summary'.", "its text")
    Do $$$AssertEquals(..Get("Encounter/enc-1", "_summary=data").body, ..Get("Encounter/enc-1").body, "_summary=data is the full body")
    Set r = ..Get("Encounter/enc-1", "_elements=id,location")
    Do $$$AssertEquals(r.status, 200, "_elements")
    Do $$$AssertEquals(r.headers.ETag, "W/""2""", "the ETag still sent")
    Set body = {}.%FromJSON(r.body)
    Do $$$AssertEquals(..Keys(body), "resourceType,id,location,meta", "the named elements and meta")
    Do $$$AssertEquals(body.meta.%ToJSON(), "{""tag"":[{""system"":""http://terminology.hl7.org/CodeSystem/v3-ObservationValue"",""code"":""SUBSETTED"",""display"":""Resource content reduced because _elements search parameter""}]}", "meta is only SUBSETTED")
    Do $$$AssertEquals(..Get("Encounter/enc-1", "_format=json").status, 400, "_format is not implemented")
}

/// Identifier search as measured on IRIS: the value without regard to case, the system with it, no prefix; a bare value
/// matches any system, |value only identifiers without one, system| every value; :exact is 400; two matches are
/// reachable; only search.mode match entries; pages with first, next and last.
Method TestIdentifierSearch()
{
    Quit:'..Ready()
    Do ..Seed()
    Do ..Put("Encounter/enc-dup-a", ..Enc("enc-dup-a", "V2000"))
    Do ..Put("Encounter/enc-dup-b", ..Enc("enc-dup-b", "V2000"))
    Do ..Put("Encounter/enc-case", ..Enc("enc-case", "AbC-77"))
    Set other = ..Enc("enc-other-sys", "V1001")
    Do other.identifier.%Get(0).%Set("system", "urn:example:other-system")
    Do ..Put("Encounter/enc-other-sys", other)
    Set none = ..Enc("enc-no-sys", "V1001")
    Do none.identifier.%Get(0).%Remove("system")
    Do ..Put("Encounter/enc-no-sys", none)
    Set s = ..#SYS
    Set rows = $LISTBUILD($LISTBUILD(s _ "|V1001", "enc-1"), $LISTBUILD(s _ "|V2000", "enc-dup-a,enc-dup-b"), $LISTBUILD(s _ "|V9999", ""))
    Set rows = rows _ $LISTBUILD($LISTBUILD(s _ "|AbC-77", "enc-case"), $LISTBUILD(s _ "|abc-77", "enc-case"), $LISTBUILD(s _ "|ABC-77", "enc-case"))
    Set rows = rows _ $LISTBUILD($LISTBUILD($ZCONVERT(s, "U") _ "|V1001", ""), $LISTBUILD(s _ "|V100", ""), $LISTBUILD("V1001", "enc-1,enc-other-sys,enc-no-sys"))
    Set rows = rows _ $LISTBUILD($LISTBUILD("|V1001", "enc-no-sys"), $LISTBUILD(s _ "|", "enc-1,enc-dup-a,enc-dup-b,enc-case"), $LISTBUILD("urn:example:other-system|V1001", "enc-other-sys"))
    For n = 1:1:$LISTLENGTH(rows) {
        Set row = $LISTGET(rows, n)
        Set r = ..Get("Encounter", "identifier=" _ $LISTGET(row, 1))
        Set b = {}.%FromJSON(r.body)
        Do $$$AssertEquals(..Ids(b), $LISTGET(row, 2), "identifier=" _ $LISTGET(row, 1))
        Do $$$AssertEquals(b.total, $SELECT($LISTGET(row, 2) = "": 0, 1: $LENGTH($LISTGET(row, 2), ",")), "total for " _ $LISTGET(row, 1))
    }
    Set b = {}.%FromJSON(..Get("Encounter", "identifier=urn%3Aoid%3A2.16.840.1.113883.2.1.3.2.4.18.49%7CV1001").body)
    Do $$$AssertEquals(..Ids(b), "enc-1", "an escaped query")
    Do $$$AssertEquals(b.entry.%Get(0).fullUrl, ..#BASE _ "/Encounter/enc-1", "fullUrl")
    Do $$$AssertEquals(b.entry.%Get(0).search.mode, "match", "search.mode")
    Set r = ..Get("Encounter", "identifier:exact=" _ s _ "|abc-77")
    Do $$$AssertEquals(r.status, 400, ":exact")
    Do $$$AssertEquals(..Issue(r).details.text, "Unsupported modifier 'exact' on param 'identifier", ":exact text")
    Do $$$AssertEquals(..Get("Encounter", "_include=Encounter:subject").status, 400, "_include is not implemented")
    Set b = {}.%FromJSON(..Get("Encounter", "identifier=" _ s _ "|&_count=2").body)
    Do $$$AssertEquals(b.total, 4, "paged total")
    Do $$$AssertEquals(..Ids(b), "enc-1,enc-dup-a", "page 1")
    Do $$$AssertEquals(..Relations(b), "first,self,next,last", "page 1 links")
    Set next = ""
    For i = 0:1:b.link.%Size() - 1 {
        Set:b.link.%Get(i).relation="next" next = b.link.%Get(i).url
    }
    Do $$$AssertTrue(next [ "page=2&queryId=", "the next link carries page and queryId: " _ next)
    Set b = {}.%FromJSON(..Get("Encounter", $PIECE(next, "?", 2)).body)
    Do $$$AssertEquals(..Ids(b), "enc-dup-b,enc-case", "page 2")
    Do $$$AssertEquals(..Relations(b), "first,self,previous,last", "page 2 links")
    Do ..Call("DELETE", "Encounter/enc-dup-a")
    Do $$$AssertEquals(..Ids({}.%FromJSON(..Get("Encounter", "identifier=" _ s _ "|V2000").body)), "enc-dup-b", "a deleted resource is not found")
}

/// The location array is stored as sent; a reference to a missing Location is accepted; modifierExtension is stored;
/// a bad location.status and an unknown element are 400 with IRIS's diagnostics; an id missing or not the URL's is 400;
/// none of the refusals writes anything.
Method TestLocationsReferencesAndStructure()
{
    Quit:'..Ready()
    Do ..Seed()
    Set locations = [{"location": {"reference": "Location/ward-c"}, "status": "completed", "period": {"start": "2026-11-07T07:00:00Z", "end": "2026-11-07T08:00:00Z"}}, {"location": {"reference": "Location/ward-b"}, "status": "active", "period": {"start": "2026-11-07T09:00:00+01:00"}}]
    Do ..Put("Encounter/enc-loc", ..Enc("enc-loc", "V1008", locations))
    Do $$$AssertEquals({}.%FromJSON(..Get("Encounter/enc-loc").body).location.%ToJSON(), locations.%ToJSON(), "stored as sent")
    Do $$$AssertEquals(..Put("Encounter/enc-badref", ..Enc("enc-badref", "V1009", [{"location": {"reference": "Location/does-not-exist"}, "status": "active"}])).status, 201, "a missing Location is accepted")
    Set e = ..Enc("enc-modext", "V1013")
    Do e.%Set("modifierExtension", [{"url": "http://example.org/mod", "valueBoolean": true}])
    Do ..Put("Encounter/enc-modext", e)
    Do $$$AssertEquals({}.%FromJSON(..Get("Encounter/enc-modext").body).modifierExtension.%Get(0).url, "http://example.org/mod", "modifierExtension stored")
    Set w = ..Put("Encounter/enc-bad", ..Enc("enc-bad", "V1011", [{"location": {"reference": "Location/ward-a"}, "status": "occupied"}]))
    Do $$$AssertEquals(w.status, 400, "bad location.status")
    Do $$$AssertEquals(..Issue(w).details.text, "The value 'occupied' of Property 'status' of Type 'Encounter.location' must be one of (active,completed,planned,reserved)", "its text")
    Do $$$AssertEquals(..Issue(w).expression.%Get(0), "Encounter.location[0].status", "its expression")
    Set e = ..Enc("enc-bad", "V1012")
    Do e.%Set("notAnElement", 1)
    Set w = ..Put("Encounter/enc-bad", e)
    Do $$$AssertEquals(..Issue(w).diagnostics, "<HSFHIRErr>UnexpectedPropertyName", "unknown element")
    Set e = ..Enc("enc-bad", "V1012")
    Do e.%Set("_status", {"extension": [{"url": "http://example.org/x", "valueString": "y"}]})
    Do $$$AssertEquals(..Put("Encounter/enc-ext", e).status, 400, "the id must be the URL's")
    Do e.%Set("id", "enc-ext")
    Do $$$AssertEquals(..Put("Encounter/enc-ext", e).status, 201, "a primitive's extension sibling is an element")
    Set e = ..Enc("enc-bad", "V1014")
    Do e.%Remove("id")
    Do $$$AssertEquals(..Issue(..Put("Encounter/enc-bad", e)).diagnostics, "<HSFHIRErr>InvalidUpdateId", "no id")
    Do $$$AssertEquals(..Get("Encounter/enc-bad").status, 404, "no refusal wrote anything")
    Set p = {"resourceType": "Patient", "id": "p-x", "name": [{"family": "X"}], "notAPatientElement": true}
    Do $$$AssertEquals(..Issue(..Put("Patient/p-x", p)).details.text, "The property name 'notAPatientElement' is not valid for type 'Patient'", "Patient elements")
    Do $$$AssertEquals(..Call("PUT", "Encounter/enc-x", , "not json").status, 400, "a body that is not JSON")
    Do $$$AssertEquals(..Put("Encounter/enc-x", {"resourceType": "Patient", "id": "enc-x"}).status, 400, "a resourceType that is not the URL's")
}

/// Reset leaves nothing: reads are 404, ids start again at version 1, and a PUT with a pre-reset ETag is 412 with
/// current version ''. The admin reset seeds a JSON array and refuses anything else without resetting.
Method TestResetAndAdminSeed()
{
    Quit:'..Ready()
    Do ..Seed()
    For v = 1:1:3 {
        Do ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""" _ v _ """")
    }
    Do $CLASSMETHOD(..#SERVICE, "Reset")
    Do $$$AssertEquals(..Get("Encounter/enc-1").status, 404, "gone after the reset")
    Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""4""")
    Do $$$AssertEquals(w.status, 412, "the pre-reset ETag")
    Do $$$AssertEquals(..Issue(w).details.text, "The version in the 'If-Match' header, '4', does not match the current version, ''", "current version ''")
    Do $$$AssertEquals(..Put("Encounter/enc-1", ..Enc("enc-1", "V1001")).headers.ETag, "W/""1""", "version ids restart")
    Set a = $CLASSMETHOD(..#SERVICE, "AdminReset", "[" _ ..Enc("enc-9", "V9").%ToJSON() _ "]")
    Do $$$AssertEquals(a.status, 200, "admin reset")
    Do $$$AssertEquals({}.%FromJSON(a.body).seeded.%Get(0).status, 201, "seeded")
    Do $$$AssertEquals(..Get("Encounter/enc-1").status, 404, "the reset ran first")
    Do $$$AssertEquals(..Get("Encounter/enc-9").status, 200, "the seed is there")
    Do $$$AssertEquals($CLASSMETHOD(..#SERVICE, "AdminReset", "{""not"": ""an array""}").status, 400, "not an array")
    Do $$$AssertEquals(..Get("Encounter/enc-9").status, 200, "and nothing was reset")
}

/// What IRIS offers and this server does not is refused with a 400 that says so, never an answer that pretends.
Method TestWhatIsNotImplementedSaysSo()
{
    Quit:'..Ready()
    Do ..Seed()
    For row = $LISTBUILD("POST", "Encounter"), $LISTBUILD("PATCH", "Encounter/enc-1"), $LISTBUILD("POST", ""), $LISTBUILD("PUT", "Encounter"), $LISTBUILD("GET", "Observation/x"), $LISTBUILD("GET", "Encounter/enc-1/$everything") {
        Set r = ..Call($LISTGET(row, 1), $LISTGET(row, 2), , "{}")
        Do $$$AssertEquals(r.status, 400, $LISTGET(row, 1) _ " " _ $LISTGET(row, 2))
        Do $$$AssertEquals(..Issue(r).diagnostics, "<FacadeErr>NotImplemented", $LISTGET(row, 1) _ " " _ $LISTGET(row, 2) _ " diagnostics")
        Do $$$AssertTrue(..Issue(r).details.text [ "is not implemented by the test FHIR server", $LISTGET(row, 1) _ " " _ $LISTGET(row, 2) _ " text")
    }
    Set r = ..Get("Encounter/enc-1/$meta")
    Do $$$AssertEquals(..Issue(r).details.text, "The operation 'meta' is not supported for the 'Instance' scope.", "$meta as IRIS answers it")
    Set m = {}.%FromJSON(..Get("metadata").body)
    Do $$$AssertEquals(m.software.name, "Shutter test FHIR server", "the statement names this server")
    Do $$$AssertNotTrue(m.%ToJSON() [ "Build", "and no IRIS build")
}

/// A write between another writer's read and write is refused: two PUTs with the same If-Match, one wins.
Method TestOneOfTwoWritersWins()
{
    Quit:'..Ready()
    Do ..Seed()
    Set a = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""")
    Set b = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""")
    Do $$$AssertEquals(a.status _ "," _ b.status, "200,412", "the second is refused")
    Do $$$AssertEquals(..Versions("Encounter", "enc-1"), 2, "one version written")
}

Method Ready() As %Boolean
{
    Quit:..Loaded() 1
    Do $$$AssertSkipped("FHIRFacade is not loaded on this instance")
    Quit 0
}

Method Loaded() As %Boolean
{
    Quit ##class(%Dictionary.CompiledClass).%ExistsId(..#SERVICE)
}

/// The S0 seed: two wards, a patient and enc-1 at Ward A.
Method Seed()
{
    Set seed = []
    Do seed.%Push({"resourceType": "Location", "id": "ward-a", "identifier": [{"system": "urn:shutter:ward", "value": "WARD-A"}], "status": "active", "name": "Ward A"})
    Do seed.%Push({"resourceType": "Location", "id": "ward-b", "identifier": [{"system": "urn:shutter:ward", "value": "WARD-B"}], "status": "active", "name": "Ward B"})
    Do seed.%Push({"resourceType": "Patient", "id": "demo-p1", "identifier": [{"system": "https://fhir.nhs.uk/Id/nhs-number", "value": "9990000001"}], "active": true})
    Do seed.%Push(..Enc("enc-1", "V1001"))
    Set out = $CLASSMETHOD(..#SERVICE, "Seed", seed)
    Do $$$AssertEquals(out.%Get(3).status, 201, "the seed is written")
}

Method Enc(id As %String, value As %String, locations As %DynamicArray = "") As %DynamicObject
{
    Set e = {"resourceType": "Encounter", "id": (id), "status": "in-progress", "identifier": [{"system": (..#SYS), "value": (value)}], "class": {"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IMP"}, "subject": {"reference": "Patient/demo-p1"}}
    If '$ISOBJECT(locations) Set locations = [{"location": {"reference": "Location/ward-a"}, "status": "active", "period": {"start": "2026-11-07T09:00:00Z"}}]
    Do e.%Set("location", locations)
    Quit e
}

Method Call(method As %String, path As %String, headers As %DynamicObject = "", body As %String = "", query As %String = "") As %DynamicObject
{
    Set:'$ISOBJECT(headers) headers = {}
    Quit $CLASSMETHOD(..#SERVICE, "Handle", {"method": (method), "path": (path), "query": (query), "headers": (headers), "body": (body), "base": (..#BASE)})
}

Method Get(path As %String, query As %String = "") As %DynamicObject
{
    Quit ..Call("GET", path, , , query)
}

Method Put(path As %String, resource As %DynamicObject, ifMatch As %String = "", prefer As %String = "") As %DynamicObject
{
    Set headers = {"Content-Type": "application/fhir+json"}
    Do:ifMatch'="" headers.%Set("If-Match", ifMatch)
    Do:prefer'="" headers.%Set("Prefer", prefer)
    Quit ..Call("PUT", path, headers, resource.%ToJSON())
}

Method Issue(answer As %DynamicObject) As %DynamicObject
{
    Set issue = {}
    Try {
        Set issue = {}.%FromJSON(answer.body).issue.%Get(0)
    } Catch {
    }
    Quit $SELECT($ISOBJECT(issue): issue, 1: {})
}

/// How many versions the store holds for an id: the count of history entries.
Method Versions(type As %String, id As %String) As %Integer
{
    Quit {}.%FromJSON(..Get(type _ "/" _ id _ "/_history").body).entry.%Size()
}

Method Keys(object As %DynamicObject) As %String
{
    Set out = "", iter = object.%GetIterator()
    While iter.%GetNext(.key) {
        Set out = out _ $SELECT(out = "": "", 1: ",") _ key
    }
    Quit out
}

Method TagList(resource As %DynamicObject) As %String
{
    Set out = ""
    Quit:'$ISOBJECT(resource.meta) ""
    Quit:'$ISOBJECT(resource.meta.tag) ""
    Set iter = resource.meta.tag.%GetIterator()
    While iter.%GetNext(, .tag) {
        Set out = out _ $SELECT(out = "": "", 1: ",") _ tag.system _ "|" _ tag.code
    }
    Quit out
}

Method Ids(bundle As %DynamicObject) As %String
{
    Set out = ""
    Quit:'$ISOBJECT(bundle.entry) ""
    Set iter = bundle.entry.%GetIterator()
    While iter.%GetNext(, .entry) {
        Set out = out _ $SELECT(out = "": "", 1: ",") _ entry.resource.id
    }
    Quit out
}

Method Relations(bundle As %DynamicObject) As %String
{
    Set out = "", iter = bundle.link.%GetIterator()
    While iter.%GetNext(, .link) {
        Set out = out _ $SELECT(out = "": "", 1: ",") _ link.relation
    }
    Quit out
}

}
