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
    Set raw = "{""resourceType"" : ""Encounter"", ""id"" : ""enc-raw"", ""status"" : ""in-progress"", ""class"" : {""code"" : ""IMP""}, ""length"" : {""value"" : 1.50, ""unit"" : ""h""}, ""location"":[{""location"":{""reference"":""Location/ward-a""},""status"":""active"",""period"":{""start"" : ""2026-11-07T10:00:00.000+00:00""}}], ""extension"":[{""url"":""http://example.org/ext/d"",""valueDecimal"":1.0E2}]}"
    Do $$$AssertEquals(..Call("PUT", "Encounter/enc-raw", , raw).status, 201, "raw text with spaces")
    Set text = ..Get("Encounter/enc-raw").body
    Do $$$AssertTrue(text [ """length"":{""value"":1.50,""unit"":""h""}", "1.50 kept: " _ text)
    Do $$$AssertTrue(text [ """valueDecimal"":1.0E2", "1.0E2 kept: " _ text)
    Do $$$AssertTrue(text [ """start"":""2026-11-07T10:00:00.000+00:00""", "precision and offset kept: " _ text)
    Do $$$AssertTrue(text [ "}],""meta"":{""lastUpdated"":""" _ ..#CLOCK _ """,""versionId"":""1""}}", "meta appended at the end: " _ text)
    Do $$$AssertNotTrue(text [ " ", "whitespace removed")
    Set u = "{""resourceType"":""Encounter"",""id"":""enc-u"",""status"":""in-progress"",""class"":{""code"":""IMP""},""reasonCode"":[{""text"":""reason " _ $CHAR(233, 32, 8594) _ " unicode""}]}"
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

/// Bodies IRIS refuses with a 400 that lists every problem, each row's issues as IRIS gave them (2027.1.0AI Build 109U,
/// probed on 8 Nov 2026), and nothing written. The conformance file holds the whole measured set; these rows cover each
/// kind of check: codes, JSON types, nulls, required elements, arrays and objects, unknown elements at every depth, the
/// dateTime, date and instant forms.
Method TestStructureAsIris()
{
    Quit:'..Ready()
    Do ..Seed()
    Set rows = []
    Set e = ..Enc("st-1", "V2001"), e.status = "bogus"
    Do rows.%Push({"id": "st-1", "body": (e), "issues": "ValueNotInEnumeration", "expression": "Encounter.status", "text": "The value 'bogus' of Property 'status' of Type 'Encounter' must be one of (arrived,cancelled,entered-in-error,finished,in-progress,onleave,planned,triaged,unknown)"})
    Set e = ..Enc("st-2", "V2002")
    Do e.%Set("status", 5, "number")
    Do rows.%Push({"id": "st-2", "body": (e), "issues": "WrongJsonType,ValueNotInEnumeration", "expression": "Encounter.status", "text": "Property 'status' of Type 'Encounter' is type number but must be string"})
    Set e = ..Enc("st-3", "V2003")
    Do e.%Set("status", "", "null")
    Do rows.%Push({"id": "st-3", "body": (e), "issues": "EmptyValue,MissingRequiredProperty", "expression": "Encounter.status", "text": "Property 'status' of Type 'Encounter' cannot be null or an empty string."})
    Set e = ..Enc("st-4", "V2004")
    Do e.%Remove("status"), e.%Remove("class")
    Do rows.%Push({"id": "st-4", "body": (e), "issues": "MissingRequiredProperty,MissingRequiredProperty", "expression": "Encounter", "text": "The type 'Encounter' requires a property named 'class'"})
    Set e = ..Enc("st-5", "V2005"), e.status = ["in-progress"]
    Do rows.%Push({"id": "st-5", "body": (e), "issues": "UnexpectedArray", "expression": "Encounter.status", "text": "Property 'status' of Type 'Encounter' cannot be an Array"})
    Set e = ..Enc("st-6", "V2006")
    Do e.%Set("class", "IMP")
    Do rows.%Push({"id": "st-6", "body": (e), "issues": "NotAnObject", "expression": "Encounter.class", "text": "Property 'class' of Type 'Encounter' must be an Object"})
    Set e = ..Enc("st-7", "V2007")
    Do e.%Set("class", {"code": "IMP", "bogus": 1})
    Do rows.%Push({"id": "st-7", "body": (e), "issues": "UnexpectedPropertyName", "expression": "Encounter.class", "text": "The property name 'bogus' is not valid for type 'Coding'"})
    Set e = ..Enc("st-8", "V2008", [{"location": {"reference": "Location/ward-a"}, "status": "active", "notAnElement": 1}])
    Do rows.%Push({"id": "st-8", "body": (e), "issues": "UnexpectedPropertyName", "expression": "Encounter.location[0]", "text": "The property name 'notAnElement' is not valid for type 'Encounter.location'"})
    Set e = ..Enc("st-9", "V2009", [{"status": "active", "period": {"start": "2026-11-07T09:00:00Z"}}])
    Do rows.%Push({"id": "st-9", "body": (e), "issues": "MissingRequiredProperty", "expression": "Encounter.location[0]", "text": "The type 'Encounter.location' requires a property named 'location'"})
    Set e = ..Enc("st-10", "V2010", [{"location": {"reference": "Location/ward-a"}, "status": "active", "period": {"start": "2026-11-07 09:00"}}])
    Do rows.%Push({"id": "st-10", "body": (e), "issues": "MalformedValue", "expression": "Encounter.location[0].period.start", "text": "The value '2026-11-07 09:00' of Property 'start' of Type 'Period' is a malformed 'dateTime'. It should match the Regex '([0-9]([0-9]([0-9][1-9]|[1-9]0)|[1-9]00)|[1-9]000)(-(0[1-9]|1[0-2])(-(0[1-9]|[1-2][0-9]|3[0-1])(T([01][0-9]|2[0-3]):[0-5][0-9]:([0-5][0-9]|60)(\\.[0-9]+)?(Z|(\\+|-)((0[0-9]|1[0-3]):[0-5][0-9]|14:00)))?)?)?'"})
    Set e = ..Enc("st-11", "V2011"), e.identifier = {"system": (..#SYS), "value": "X"}
    Do rows.%Push({"id": "st-11", "body": (e), "issues": "NotAnArray", "expression": "Encounter.identifier", "text": "Property 'identifier' of Type 'Encounter' must be an Array"})
    Set e = ..Enc("st-12", "V2012"), e.identifier = [{"system": (..#SYS), "value": "X", "bogus": 1}]
    Do rows.%Push({"id": "st-12", "body": (e), "issues": "UnexpectedPropertyName", "expression": "Encounter.identifier[0]", "text": "The property name 'bogus' is not valid for type 'Identifier'"})
    Set e = ..Enc("st-13", "V2013")
    Do e.%Set("identifier,status", "x")
    Do rows.%Push({"id": "st-13", "body": (e), "issues": "UnexpectedPropertyName", "expression": "Encounter", "text": "The property name 'identifier,status' is not valid for type 'Encounter'"})
    Set dup = "{""resourceType"":""Encounter"",""id"":""st-14"",""status"":""in-progress"",""status"":""bogus"",""class"":{""code"":""IMP""}}"
    Do rows.%Push({"id": "st-14", "body": (dup), "issues": "ValueNotInEnumeration", "expression": "Encounter.status"})
    Set e = ..Enc("st-15", "V2015"), e.meta = [{"versionId": "1"}]
    Do rows.%Push({"id": "st-15", "body": (e), "issues": "UnexpectedArray", "expression": "Encounter.meta", "text": "Property 'meta' of Type 'Encounter' cannot be an Array"})
    Set e = ..Enc("st-16", "V2016"), e.meta = {"lastUpdated": 2001, "versionId": 77}
    Do rows.%Push({"id": "st-16", "body": (e), "issues": "WrongJsonType,MalformedValue,WrongJsonType", "expression": "Encounter.meta.lastUpdated", "text": "Property 'lastUpdated' of Type 'Meta' is type number but must be string"})
    Set e = ..Enc("st-17", "V2017"), e.meta = {"tag": [{"code": "x", "bogus": 1}]}
    Do rows.%Push({"id": "st-17", "body": (e), "issues": "UnexpectedPropertyName", "expression": "Encounter.meta.tag[0]", "text": "The property name 'bogus' is not valid for type 'Coding'"})
    Set e = ..Enc("st-18", "V2018"), e.extension = [{"valueString": "y"}]
    Do rows.%Push({"id": "st-18", "body": (e), "issues": "MissingRequiredProperty", "expression": "Encounter.extension[0]", "text": "The type 'Extension' requires a property named 'url'"})
    Set e = ..Enc("st-19", "V2019"), e.status = "bogus", e.notAnElement = 1
    Do rows.%Push({"id": "st-19", "body": (e), "issues": "ValueNotInEnumeration,UnexpectedPropertyName", "expression": "Encounter.status"})
    Do rows.%Push({"id": "pt-1", "type": "Patient", "body": ({"resourceType": "Patient", "id": "pt-1", "gender": "Male"}), "issues": "ValueNotInEnumeration", "expression": "Patient.gender", "text": "The value 'Male' of Property 'gender' of Type 'Patient' must be one of (female,male,other,unknown)"})
    Do rows.%Push({"id": "pt-2", "type": "Patient", "body": ({"resourceType": "Patient", "id": "pt-2", "birthDate": "08/11/2026"}), "issues": "MalformedValue", "expression": "Patient.birthDate", "text": "The value '08/11/2026' of Property 'birthDate' of Type 'Patient' is a malformed 'date'. It should match the Regex '([0-9]([0-9]([0-9][1-9]|[1-9]0)|[1-9]00)|[1-9]000)(-(0[1-9]|1[0-2])(-(0[1-9]|[1-2][0-9]|3[0-1]))?)?'"})
    Do rows.%Push({"id": "pt-3", "type": "Patient", "body": ({"resourceType": "Patient", "id": "pt-3", "active": "yes"}), "issues": "WrongJsonType", "expression": "Patient.active", "text": "Property 'active' of Type 'Patient' is type string but must be boolean"})
    Do rows.%Push({"id": "pt-4", "type": "Patient", "body": ({"resourceType": "Patient", "id": "pt-4", "name": [{"family": "X", "given": "Y"}]}), "issues": "NotAnArray", "expression": "Patient.name[0].given", "text": "Property 'given' of Type 'HumanName' must be an Array"})
    Do rows.%Push({"id": "lc-1", "type": "Location", "body": ({"resourceType": "Location", "id": "lc-1", "status": "bogus"}), "issues": "ValueNotInEnumeration", "expression": "Location.status", "text": "The value 'bogus' of Property 'status' of Type 'Location' must be one of (active,inactive,suspended)"})
    Do rows.%Push({"id": "lc-2", "type": "Location", "body": ({"resourceType": "Location", "id": "lc-2", "name": ""}), "issues": "EmptyValue", "expression": "Location.name", "text": "Property 'name' of Type 'Location' cannot be null or an empty string."})
    Set iter = rows.%GetIterator()
    While iter.%GetNext(, .row) {
        Set path = $SELECT(row.%IsDefined("type"): row.type, 1: "Encounter") _ "/" _ row.id
        Set body = $SELECT($ISOBJECT(row.body): row.body.%ToJSON(), 1: row.body)
        Set w = ..Call("PUT", path, {"Content-Type": "application/fhir+json"}, body)
        Do $$$AssertEquals(w.status, 400, row.id _ ": the status")
        Set issues = "", outcome = {}
        Try {
            Set outcome = {}.%FromJSON(w.body)
        } Catch {
        }
        Set:'$ISOBJECT(outcome) outcome = {}
        Set list = $SELECT($ISOBJECT(outcome.issue): outcome.issue, 1: [])
        Set each = list.%GetIterator()
        While each.%GetNext(, .issue) {
            Set issues = issues _ $SELECT(issues = "": "", 1: ",") _ $PIECE(issue.diagnostics, ">", 2)
        }
        Do $$$AssertEquals(issues, row.issues, row.id _ ": the issues, in order")
        Set first = list.%Get(0)
        If $ISOBJECT(first) {
            Do $$$AssertEquals(first.severity _ " " _ first.code, "error invalid", row.id _ ": severity and code")
            Do $$$AssertEquals($SELECT($ISOBJECT(first.expression): first.expression.%Get(0), 1: ""), row.expression, row.id _ ": the expression")
            Do:row.%IsDefined("text") $$$AssertEquals(first.details.text, row.text, row.id _ ": the text")
        }
        Do $$$AssertEquals(..Get(path).status, 404, row.id _ ": nothing written")
    }
    Set e = ..Enc("st-ok", "V2099", [{"location": {"reference": "Location/ward-a"}, "status": "active", "_status": {"id": "s"}, "period": {"start": "2026-11-07T09:00:00+01:00", "end": "2026-11-07T10:00:00.5Z"}}])
    Do e.%Set("meta", {"versionId": "7", "lastUpdated": "2026-11-07T09:00:00.123+01:00", "source": "#s", "tag": [{"system": "urn:shutter:recovery", "code": "op-1"}]})
    Do e.%Set("modifierExtension", [{"url": "http://example.org/m", "valueBoolean": true}])
    Do $$$AssertEquals(..Put("Encounter/st-ok", e).status, 201, "a body with every element Shutter writes is accepted")
}

/// Ids and type names as IRIS takes them: an id outside [A-Za-z0-9.-]{1,64} is 400 InvalidId on every interaction; an
/// empty id segment and a type name that is not a single name are an empty text/html 404; the path is decoded once,
/// by the web gateway, never again here.
Method TestIdsAndTypeNames()
{
    Quit:'..Ready()
    Do ..Seed()
    Set text = "The Id specified in the URL, 'bad_id!' is invalid. It can only contain alphanumerics, '.', or '-', and maximum length is 64."
    Set e = ..Enc("bad_id!", "V3001")
    Set w = ..Put("Encounter/bad_id!", e)
    Do $$$AssertEquals(w.status _ " " _ ..Issue(w).diagnostics, "400 <HSFHIRErr>InvalidId", "PUT an id with '_' and '!'")
    Do $$$AssertEquals(..Issue(w).details.text, text, "its text")
    Do $$$AssertEquals(..Issue(w).%IsDefined("expression"), 0, "with no expression")
    For request = $LISTBUILD("GET", "Encounter/bad_id!"), $LISTBUILD("DELETE", "Encounter/bad_id!"), $LISTBUILD("GET", "Encounter/bad_id!/_history"), $LISTBUILD("GET", "Encounter/bad_id!/_history/1") {
        Set w = ..Call($LISTGET(request, 1), $LISTGET(request, 2))
        Do $$$AssertEquals(w.status _ " " _ ..Issue(w).details.text, "400 " _ text, $LISTGET(request, 1) _ " " _ $LISTGET(request, 2))
    }
    Set long = $TRANSLATE($JUSTIFY("", 65), " ", "a")
    Set w = ..Put("Encounter/" _ long, ..Enc(long, "V3002"))
    Do $$$AssertEquals(w.status _ " " _ ..Issue(w).diagnostics, "400 <HSFHIRErr>InvalidId", "an id of 65 characters")
    Do $$$AssertEquals(..Get("Encounter/" _ $EXTRACT(long, 1, 64)).status, 404, "an id of 64 characters is an id")
    Do $$$AssertEquals(..Put("Encounter/enc.2-B", ..Enc("enc.2-B", "V3003")).status, 201, "letters, digits, '.' and '-'")
    Set w = ..Put("Encounter/a%41", ..Enc("a%41", "V3004"))
    Do $$$AssertEquals(..Issue(w).details.text, "The Id specified in the URL, 'a%41' is invalid. It can only contain alphanumerics, '.', or '-', and maximum length is 64.", "the path is not decoded a second time")
    Set w = ..Call("PUT", "Encounter,Location/c1", {"Content-Type": "application/fhir+json"}, "{""resourceType"":""Encounter,Location"",""id"":""c1""}")
    Do $$$AssertEquals(w.status _ " " _ $PIECE(w.headers.%Get("Content-Type"), ";") _ " [" _ w.body _ "]", "404 text/html []", "a PUT to the type 'Encounter,Location'")
    Do $$$AssertEquals(..Get("Encounter/c1").status, 404, "wrote nothing")
    Do $$$AssertEquals(..Get("Encounter,Location/c1").status, 404, "and nothing reads back")
    For path = "Encounter//_history", "Encounter//_history/1", "Encounter,Location/enc-1" {
        Set w = ..Get(path)
        Do $$$AssertEquals(w.status _ " " _ $PIECE(w.headers.%Get("Content-Type"), ";") _ " [" _ w.body _ "]", "404 text/html []", path)
    }
}

/// ignore_if_match: for the times it was set, an Encounter PUT with a stale or unknown If-Match is written as if it
/// matched; the malformed 405 stays; then the server compares again.
Method TestIgnoreIfMatchFiresTimesThenStops()
{
    Quit:'..Ready()
    Do ..Seed()
    Do $CLASSMETHOD(..#SERVICE, "SetFault", "ignore_if_match", 2)
    Do $$$AssertEquals(..FaultNow(" "), "ignore_if_match 2", "the fault is set")
    Set m = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), """7""")
    Do $$$AssertEquals(m.status, 405, "a malformed If-Match is still the 405")
    Do $$$AssertEquals(..Stats().%Get("fault_left"), 2, "and does not use the fault up")
    Do $$$AssertEquals(..Put("Location/ward-a", {"resourceType": "Location", "id": "ward-a", "status": "active", "name": "Ward A"}, "W/""7""").status, 412, "a Location is never touched by a fault")
    Do $$$AssertEquals(..Put("Encounter/enc-1", ..Enc("enc-1", "V1001")).status, 200, "nor is a PUT without If-Match")
    Do $$$AssertEquals(..Stats().%Get("fault_left"), 2, "neither uses the fault up")
    Set a = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""")
    Do $$$AssertEquals(a.status _ " " _ a.headers.ETag, "200 W/""3""", "a stale If-Match is written")
    Set b = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""99""")
    Do $$$AssertEquals(b.status _ " " _ b.headers.ETag, "200 W/""4""", "and an unknown one")
    Do $$$AssertEquals(..FaultNow("|"), "|0", "the fault is gone after its two times")
    Set c = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""")
    Do $$$AssertEquals(c.status, 412, "the third is compared again")
    Do $$$AssertEquals(..Versions("Encounter", "enc-1"), 4, "and wrote nothing")
}

/// commit_drop_response: the version is written and the answer is a 500 with an empty text/html body and no ETag.
Method TestCommitDropResponseWritesAndAnswers500()
{
    Quit:'..Ready()
    Do ..Seed()
    Do $CLASSMETHOD(..#SERVICE, "SetFault", "commit_drop_response")
    Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001", [{"location": {"reference": "Location/ward-b"}, "status": "active"}]), "W/""1""", "return=representation")
    Do $$$AssertEquals(w.status _ " " _ w.headers.%Get("Content-Type") _ " [" _ w.body _ "]", "500 text/html; charset=utf-8 []", "a 500 with an empty text/html body")
    Do $$$AssertEquals(w.headers.%IsDefined("ETag") + w.headers.%IsDefined("Location") + w.headers.%IsDefined("Last-Modified"), 0, "and no ETag, Location or Last-Modified")
    Set r = ..Get("Encounter/enc-1")
    Do $$$AssertEquals(r.headers.ETag, "W/""2""", "the version was written")
    Do $$$AssertEquals({}.%FromJSON(r.body).location.%Get(0).location.reference, "Location/ward-b", "with the body that was sent")
    Do $$$AssertEquals(..Stats().%Get("puts_refused"), 0, "it is not counted as refused")
    Set again = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""2""")
    Do $$$AssertEquals(again.status _ " " _ again.headers.ETag, "200 W/""3""", "once only: the next PUT is answered")
    // A PUT the server refuses is refused as ever, and the fault fired on it
    Do $CLASSMETHOD(..#SERVICE, "SetFault", "commit_drop_response")
    Do $$$AssertEquals(..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""").status, 412, "a stale PUT is the 412, with nothing to drop")
    Do $$$AssertEquals(..Stats().%Get("fault_left"), 0, "and it used the fault up")
}

/// second_writer_between_read_and_write: another writer's version lands first, so the request's ETag is stale: 412,
/// one more version, and it is the stored body again, not the request's.
Method TestSecondWriterMakesTheRequestStale()
{
    Quit:'..Ready()
    Do ..Seed()
    Do $CLASSMETHOD(..#SERVICE, "SetFault", "second_writer_between_read_and_write")
    Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001", [{"location": {"reference": "Location/ward-b"}, "status": "active"}]), "W/""1""")
    Do $$$AssertEquals(w.status, 412, "the request is stale")
    Do $$$AssertEquals(..Issue(w).details.text, "The version in the 'If-Match' header, '1', does not match the current version, '2'", "against the other writer's version")
    Do $$$AssertEquals(..Versions("Encounter", "enc-1"), 2, "one more version: the other writer's")
    Set one = {}.%FromJSON(..Get("Encounter/enc-1/_history/1").body), two = {}.%FromJSON(..Get("Encounter/enc-1/_history/2").body)
    Do $$$AssertEquals(two.meta.versionId, "2", "stamped as version 2")
    Do $$$AssertEquals(two.location.%ToJSON(), one.location.%ToJSON(), "with the stored body, not the request's")
    Do $$$AssertEquals(..Counts(), "5 1", "the other writer is not a PUT that arrived (four seeded, one sent)")
    Set next = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""2""")
    Do $$$AssertEquals(next.status, 200, "once only: the next PUT with the new ETag is written")
}

/// The modes combine: the second writer with ignore_if_match is a lost update, and with commit_drop_response as well
/// the client hears a 500 for it.
Method TestFaultsCombine()
{
    Quit:'..Ready()
    Do ..Seed()
    Do $CLASSMETHOD(..#SERVICE, "SetFault", "second_writer_between_read_and_write, ignore_if_match")
    Do $$$AssertEquals(..Stats().fault, "second_writer_between_read_and_write,ignore_if_match", "both are set")
    Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""")
    Do $$$AssertEquals(w.status _ " " _ w.headers.ETag, "200 W/""3""", "written over the other writer's version")
    Do $$$AssertEquals(..Stats().%Get("fault_left"), 0, "one firing for the two modes")
    Do $CLASSMETHOD(..#SERVICE, "SetFault", "ignore_if_match,commit_drop_response,second_writer_between_read_and_write")
    Set w = ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""")
    Do $$$AssertEquals(w.status _ " [" _ w.body _ "]", "500 []", "all three: written, and a 500")
    Do $$$AssertEquals(..Get("Encounter/enc-1").headers.ETag, "W/""5""", "two more versions")
    // A name that is not a mode is an error and leaves the fault as it was
    Do $CLASSMETHOD(..#SERVICE, "SetFault", "ignore_if_match", 3)
    Set thrown = 0
    Try {
        Do $CLASSMETHOD(..#SERVICE, "SetFault", "history_503")
    } Catch {
        Set thrown = 1
    }
    Do $$$AssertEquals(thrown, 1, "a mode that is not built is an error")
    Do $$$AssertEquals(..FaultNow(" "), "ignore_if_match 3", "and the fault stays as it was")
    Do $CLASSMETHOD(..#SERVICE, "SetFault", "")
    Do $$$AssertEquals(..FaultNow("|"), "|0", "an empty list clears it")
    // The admin route's body
    Set a = $CLASSMETHOD(..#SERVICE, "AdminFault", "{""modes"": [""commit_drop_response"", ""ignore_if_match""], ""times"": 2}")
    Do $$$AssertEquals(a.status, 200, "the admin route sets a fault")
    Set stats = {}.%FromJSON(a.body)
    Do $$$AssertEquals(stats.fault _ " " _ stats.%Get("fault_left"), "commit_drop_response,ignore_if_match 2", "and answers the stats")
    Do $$$AssertEquals($CLASSMETHOD(..#SERVICE, "AdminFault", "{""modes"": [""drop_meta_tag""]}").status, 400, "an unknown mode is refused")
    Do $$$AssertEquals($CLASSMETHOD(..#SERVICE, "AdminFault", "{""modes"": ""ignore_if_match""}").status, 400, "modes that are not an array")
    Do $$$AssertEquals($CLASSMETHOD(..#SERVICE, "AdminFault", "{""modes"": [""ignore_if_match""], ""times"": 0}").status, 400, "no times")
    Do $$$AssertEquals($CLASSMETHOD(..#SERVICE, "AdminFault", "[]").status, 400, "not an object")
    Do $$$AssertEquals(..FaultNow(" "), "commit_drop_response,ignore_if_match 2", "a refusal changes nothing")
    Do $$$AssertEquals({}.%FromJSON($CLASSMETHOD(..#SERVICE, "AdminFault", "{""modes"": []}").body).fault, "", "an empty list clears it")
    Do $$$AssertEquals({}.%FromJSON($CLASSMETHOD(..#SERVICE, "AdminStats").body).%Get("puts_received"), 6, "the stats route counts: four seeded, two sent")
}

/// Reset clears the fault and the counters with the resources, and keeps the clock.
Method TestResetClearsFaultAndStats()
{
    Quit:'..Ready()
    Do ..Seed()
    Do ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""9""")
    Do $CLASSMETHOD(..#SERVICE, "SetFault", "ignore_if_match", 5)
    Do $$$AssertEquals(..Stats().%ToJSON(), "{""puts_received"":5,""puts_refused"":1,""fault"":""ignore_if_match"",""fault_left"":5}", "before the reset")
    Do $$$AssertEquals($CLASSMETHOD(..#SERVICE, "Reset"), 1, "the reset")
    Do $$$AssertEquals(..Stats().%ToJSON(), "{""puts_received"":0,""puts_refused"":0,""fault"":"""",""fault_left"":0}", "after it")
    Do $$$AssertEquals($CLASSMETHOD(..#SERVICE, "Now"), ..#CLOCK, "the clock is kept")
    Do $CLASSMETHOD(..#SERVICE, "SetFault", "commit_drop_response")
    Do $CLASSMETHOD(..#SERVICE, "AdminReset", "")
    Do $$$AssertEquals(..Stats().fault, "", "the admin reset clears the fault too")
    // A reset waits for a write: while another process holds a resource, it gives up and clears nothing
    Do ..Seed()
    Job ##class(Shutter.Test.FHIRFacade).HoldALock($JOB)
    Set child = $ZCHILD
    Set got = $SYSTEM.Event.WaitMsg("", 10)
    Do $$$AssertEquals($LISTGET(got, 2), "held", "another process holds a resource's lock")
    Lock +^FHIRFacade.Data:0
    Set free = $TEST
    Lock:free -^FHIRFacade.Data
    Do $$$AssertEquals(free, 0, "so the whole store cannot be locked")
    Do $SYSTEM.Event.Signal(child, "go")
    Set got = $SYSTEM.Event.WaitMsg("", 10)
    Do $$$AssertEquals($CLASSMETHOD(..#SERVICE, "Reset"), 1, "once it lets go, the reset runs")
    Do $$$AssertEquals(..Get("Encounter/enc-1").status, 404, "and clears the store")
}

/// Takes one resource's lock as a write does, tells the parent, and lets go when told.
ClassMethod HoldALock(parent As %Integer)
{
    Do ##class(FHIRFacade.Store).Lock("Encounter", "enc-1")
    Do $SYSTEM.Event.Signal(parent, "held")
    Do $SYSTEM.Event.WaitMsg("", 20)
    Do ##class(FHIRFacade.Store).Unlock("Encounter", "enc-1")
    Do $SYSTEM.Event.Signal(parent, "freed")
}

/// Every PUT of a resource that arrives is counted, and one that wrote nothing is counted as refused too: the stale,
/// the malformed and the unstorable. Reads and deletes are not counted.
Method TestTheCounterCountsARefusedPut()
{
    Quit:'..Ready()
    Do $$$AssertEquals(..Stats().%ToJSON(), "{""puts_received"":0,""puts_refused"":0,""fault"":"""",""fault_left"":0}", "nothing yet")
    Do ..Seed()
    Do $$$AssertEquals(..Counts(), "4 0", "the seed's four PUTs")
    Do ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""")
    Do $$$AssertEquals(..Counts(), "5 0", "a PUT that was written")
    Do ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "W/""1""")
    Do $$$AssertEquals(..Counts(), "6 1", "a stale one, the 412")
    Do ..Put("Encounter/enc-1", ..Enc("enc-1", "V1001"), "2")
    Do $$$AssertEquals(..Counts(), "7 2", "a malformed If-Match, the 405")
    Do ..Call("PUT", "Encounter/enc-1", , "not json")
    Do $$$AssertEquals(..Counts(), "8 3", "a body that is not JSON, the 400")
    Do ..Put("Encounter/enc-2", ..Enc("enc-1", "V1001"))
    Do $$$AssertEquals(..Counts(), "9 4", "an id that is not the URL's")
    Do ..Get("Encounter/enc-1")
    Do ..Call("DELETE", "Encounter/enc-1")
    Do ..Call("PUT", "Encounter", , "{}")
    Do ..Call("POST", "Encounter", , "{}")
    Do $$$AssertEquals(..Counts(), "9 4", "a read, a delete, a conditional PUT and a POST are not PUTs of a resource")
}

/// The installer makes the two resources, the role, the user, the credential and the web application, and a second
/// run leaves them as they are. What this test made it takes away again.
Method TestTheInstallerTwice()
{
    Quit:'..Ready()
    If '##class(%Dictionary.CompiledClass).%ExistsId("FHIRFacade.Installer") Do $$$AssertSkipped("FHIRFacade.Installer is not loaded on this instance") Quit
    If '$SYSTEM.Security.Check("%Admin_Secure", "USE") Do $$$AssertSkipped("The installer needs %Admin_Secure") Quit
    Set ns = $NAMESPACE, app = "/fhir-facade/r4"
    Do ..Installed(.before)
    Set hadNode = $DATA(^Shutter.Config("webapp", app)), hadCredential = ##class(Ens.Config.Credentials).%ExistsId("FHIRFacade")
    Try {
        Do $$$AssertStatusOK($CLASSMETHOD("FHIRFacade.Installer", "Install", ns), "the first run")
        Do ..Installed(.first, .detail)
        Do $$$AssertEquals(first, "resource:FHIRFacade_API,resource:FHIRFacade_Admin,role,user,application", "everything is there")
        Do $$$AssertEquals(detail("role"), "FHIRFacade_API:RW", "the role holds the API resource, read and write")
        Do $$$AssertTrue(("," _ detail("user") _ ",") [ ",Shutter_FHIRFacadeClient,", "the user has the role: " _ detail("user"))
        Do $$$AssertTrue((("," _ detail("user") _ ",") [ ",Shutter_DownstreamClient,") || (("," _ detail("user") _ ",") [ ",Shutter_Operator,"), "and one that carries the database: " _ detail("user"))
        Do $$$AssertNotTrue(detail("userResources") [ "FHIRFacade_Admin", "never the controls")
        Do $$$AssertEquals(detail("comment"), "Used by the production's HTTP operation", "the comment the uninstall knows the user by")
        Do $$$AssertEquals(detail("application"), ns _ "|1|32|FHIRFacade.API|||2|/fhir-facade/r4/", "the web application: a password and nothing else")
        Do $$$AssertEquals(^Shutter.Config("webapp", app), 1, "recorded as Shutter's")
        Set credential = ##class(Ens.Config.Credentials).%OpenId("FHIRFacade")
        Do $$$AssertEquals($SELECT($ISOBJECT(credential): credential.Username, 1: ""), "fhir-client", "the credential names the user")
        Do $$$AssertStatusOK($CLASSMETHOD("FHIRFacade.Installer", "Install", ns), "the second run")
        Do ..Installed(.second, .again)
        Do $$$AssertEquals(second, first, "nothing more, nothing less")
        Do $$$AssertEquals(again("user") _ "#" _ again("role") _ "#" _ again("application"), detail("user") _ "#" _ detail("role") _ "#" _ detail("application"), "and nothing changed")
        Do $$$AssertEquals(ns, $NAMESPACE, "the namespace is the caller's again")
    } Catch ex {
        Do $$$AssertStatusOK(ex.AsStatus(), "the installer")
    }
    Set $NAMESPACE = ns
    // Only what was not there before goes
    If 'hadCredential Do ##class(Ens.Config.Credentials).%DeleteId("FHIRFacade")
    If 'hadNode Kill ^Shutter.Config("webapp", app)
    Set before = "," _ before _ ","
    Set $NAMESPACE = "%SYS"
    If before '[ ",application," Do ##class(Security.Applications).Delete(app)
    If before '[ ",user," Do ##class(Security.Users).Delete("fhir-client")
    If before '[ ",role," Do ##class(Security.Roles).Delete("Shutter_FHIRFacadeClient")
    If before '[ ",resource:FHIRFacade_API," Do ##class(Security.Resources).Delete("FHIRFacade_API")
    If before '[ ",resource:FHIRFacade_Admin," Do ##class(Security.Resources).Delete("FHIRFacade_Admin")
    Set $NAMESPACE = ns
}

/// What of the installer's is on the instance, as a comma list, and how each stands.
Method Installed(Output found As %String, Output detail)
{
    Kill detail
    Set found = "", ns = $NAMESPACE
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    For name = "FHIRFacade_API", "FHIRFacade_Admin" {
        Set:##class(Security.Resources).Exists(name) found = found _ ",resource:" _ name
    }
    If ##class(Security.Roles).Exists("Shutter_FHIRFacadeClient") {
        Kill props
        Do ##class(Security.Roles).Get("Shutter_FHIRFacadeClient", .props)
        Set found = found _ ",role", detail("role") = $GET(props("Resources"))
    }
    If ##class(Security.Users).Exists("fhir-client") {
        Kill props
        Do ##class(Security.Users).Get("fhir-client", .props)
        Set found = found _ ",user", detail("user") = $GET(props("Roles")), detail("comment") = $GET(props("Comment"))
        Set detail("userResources") = ""
        For i = 1:1:$LENGTH(detail("user"), ",") {
            Kill props
            Continue:$PIECE(detail("user"), ",", i)=""
            Continue:$$$ISERR(##class(Security.Roles).Get($PIECE(detail("user"), ",", i), .props))
            Set detail("userResources") = detail("userResources") _ "," _ $GET(props("Resources"))
        }
    }
    If ##class(Security.Applications).Exists("/fhir-facade/r4") {
        Kill props
        Do ##class(Security.Applications).Get("/fhir-facade/r4", .props)
        Set found = found _ ",application"
        Set detail("application") = $GET(props("NameSpace")) _ "|" _ $GET(props("Enabled")) _ "|" _ $GET(props("AutheEnabled")) _ "|" _ $GET(props("DispatchClass")) _ "|" _ $GET(props("Resource")) _ "|" _ $GET(props("MatchRoles")) _ "|" _ $GET(props("UseCookies")) _ "|" _ $GET(props("CookiePath"))
    }
    Set found = $EXTRACT(found, 2, *)
}

/// The fake adapter is the server in process: a read gives the ETag, a PUT with it is written, the same PUT again is
/// the 412 with the real adapter's error status, and every request is logged.
Method TestFakeFhirRoundTripWithAnEtag()
{
    Quit:'..Ready()
    Do ..Seed()
    Set http = ##class(Shutter.Test.FakeFhir).%New()
    Set http.Base = "/fhir-facade/r4"
    Set sc = http.SendFormDataArray(.resp, "GET", ..Ask(), "", "", "/fhir-facade/r4/Encounter/enc-1")
    Do $$$AssertStatusOK(sc, "the read")
    Do $$$AssertEquals(resp.StatusCode _ " " _ resp.GetHeader("ETag") _ " " _ resp.ContentType, "200 W/""1"" application/fhir+json; charset=UTF-8", "its status, ETag and content type")
    Do $$$AssertEquals(resp.GetHeader("Location"), "/fhir-facade/r4/Encounter/enc-1/_history/1", "the Location begins with the base")
    Set etag = resp.GetHeader("ETag"), read = {}.%FromJSON($ZCONVERT(resp.Data.Read(1000000), "I", "UTF8"))
    Do $$$AssertEquals(read.id, "enc-1", "the body is the Encounter")
    // A name above ASCII goes out as UTF-8 bytes and comes back as UTF-8 bytes
    Set name = "Zo" _ $CHAR(235) _ " " _ $CHAR(321) _ "uk"
    Set change = ..Enc("enc-1", "V1001")
    Do change.%Set("serviceProvider", {"display": (name)})
    Set put = ..Ask("W/""1""", $ZCONVERT(change.%ToJSON(), "O", "UTF8"))
    Set sc = http.SendFormDataArray(.resp, "PUT", put, "", "", "/fhir-facade/r4/Encounter/enc-1")
    Do $$$AssertStatusOK(sc, "the PUT with the ETag")
    Do $$$AssertEquals(resp.StatusCode _ " " _ resp.GetHeader("ETag") _ " [" _ resp.Data.Read() _ "]", "200 W/""2"" []", "written, with an empty body")
    Set sc = http.SendFormDataArray(.resp, "GET", ..Ask(), "", "", "/fhir-facade/r4/Encounter/enc-1/_history/2")
    Set bytes = resp.Data.Read(1000000)
    Do $$$AssertNotTrue($ZISWIDE(bytes), "a body is bytes")
    Do $$$AssertEquals({}.%FromJSON($ZCONVERT(bytes, "I", "UTF8")).serviceProvider.display, name, "and the name is whole")
    Set sc = http.SendFormDataArray(.resp, "PUT", ..Ask("W/""1""", change.%ToJSON()), "", "", "/fhir-facade/r4/Encounter/enc-1")
    Do $$$AssertTrue($SYSTEM.Status.GetErrorText(sc) [ "412", "the same PUT again is an error status, as the real adapter gives: " _ $SYSTEM.Status.GetErrorText(sc))
    Do $$$AssertEquals(resp.StatusCode, 412, "with the response")
    Do $$$AssertEquals({}.%FromJSON($ZCONVERT(resp.Data.Read(1000000), "I", "UTF8")).resourceType, "OperationOutcome", "and its OperationOutcome")
    Set sc = http.SendFormDataArray(.resp, "GET", ..Ask(), "", "", "/fhir-facade/r4/Encounter?identifier=" _ $ZCONVERT(..#SYS _ "|V1001", "O", "URL"))
    Do $$$AssertEquals({}.%FromJSON(resp.Data.Read(1000000)).total, 1, "a search's query reaches the server")
    Do $$$AssertEquals(http.Requests, 5, "five requests logged")
    Do $$$AssertEquals($LISTGET(http.Requests(1), 1) _ " " _ $LISTGET(http.Requests(1), 2) _ " [" _ $LISTGET(http.Requests(1), 3) _ "]", "GET Encounter/enc-1 []", "the read")
    Do $$$AssertEquals($LISTGET(http.Requests(2), 1) _ " " _ $LISTGET(http.Requests(2), 2) _ " " _ $LISTGET(http.Requests(2), 3), "PUT Encounter/enc-1 W/""1""", "the PUT and its If-Match")
    Do $$$AssertEquals({}.%FromJSON($LISTGET(http.Requests(2), 4)).serviceProvider.display, name, "its body, as characters")
    Do $$$AssertEquals({}.%FromJSON($LISTGET(http.Requests(4), 4)).serviceProvider.display, name, "also when it was sent as characters")
    Do $$$AssertEquals($PIECE($LISTGET(http.Requests(5), 2), "?", 1), "Encounter", "the search's path, with its query after it")
    Do $$$AssertEquals(..Counts(), "6 1", "and the server counted the two PUTs")
}

/// A canned answer comes instead of the server's: a page behind a 200, a plain 404, and no answer at all.
Method TestFakeFhirCannedAnswers()
{
    Quit:'..Ready()
    Do ..Seed()
    Set http = ##class(Shutter.Test.FakeFhir).%New()
    Set http.Base = "http://fhir.test/r4"
    Set http.Canned("GET", "Encounter/enc-1") = $LISTBUILD(200, "text/html; charset=utf-8", "", "", "<html><body>Sign in</body></html>")
    Set http.Canned("GET", "Patient/demo-p1") = $LISTBUILD(404, "text/plain", "", "", "Not Found")
    Set http.Canned("GET", "Encounter/enc-1/_history") = $LISTBUILD(0)
    Set http.Canned("PUT", "Encounter/enc-1") = $LISTBUILD(200, "text/html; charset=utf-8", "W/""41""", "http://fhir.test/r4/Encounter/enc-1/_history/41", "")
    Set sc = http.SendFormDataArray(.resp, "GET", ..Ask(), "", "", "http://fhir.test/r4/Encounter/enc-1")
    Do $$$AssertStatusOK(sc, "a page behind a 200")
    Do $$$AssertEquals(resp.StatusCode _ " " _ resp.ContentType _ " " _ resp.Data.Read(), "200 text/html; charset=utf-8 <html><body>Sign in</body></html>", "as it was canned")
    Do $$$AssertEquals(resp.GetHeader("ETag"), "", "with no ETag")
    Set sc = http.SendFormDataArray(.resp, "GET", ..Ask(), "", "", "http://fhir.test/r4/Patient/demo-p1")
    Do $$$AssertTrue($$$ISERR(sc), "a plain 404 is an error status")
    Do $$$AssertEquals(resp.StatusCode _ " " _ resp.ContentType _ " " _ resp.Data.Read(), "404 text/plain Not Found", "with its response")
    Set sc = http.SendFormDataArray(.resp, "GET", ..Ask(), "", "", "http://fhir.test/r4/Encounter/enc-1/_history")
    Do $$$AssertTrue($$$ISERR(sc), "no answer is an error status")
    Do $$$AssertEquals($ISOBJECT(resp), 0, "and no response")
    Set sc = http.SendFormDataArray(.resp, "PUT", ..Ask("W/""1""", ..Enc("enc-1", "V1001").%ToJSON()), "", "", "http://fhir.test/r4/Encounter/enc-1")
    Do $$$AssertEquals(resp.StatusCode _ " " _ resp.GetHeader("ETag") _ " " _ resp.GetHeader("Location"), "200 W/""41"" http://fhir.test/r4/Encounter/enc-1/_history/41", "a canned PUT, its ETag and Location")
    Do $$$AssertEquals(..Stats().%Get("puts_received"), 4, "which never reached the server (four seeded)")
    Set sc = http.SendFormDataArray(.resp, "GET", ..Ask(), "", "", "http://fhir.test/r4/Location/ward-a")
    Do $$$AssertEquals(resp.StatusCode, 200, "what is not canned is the server's")
    Do $$$AssertEquals(http.Requests, 5, "and canned requests are logged with the rest")
}

/// A request as the FHIR operations make one: the Accept header, and for a write the If-Match, the content type and
/// the body.
Method Ask(ifMatch As %String = "", body As %String = "") As %Net.HttpRequest
{
    Set http = ##class(%Net.HttpRequest).%New()
    Set http.ReadRawMode = 1
    Do http.SetHeader("Accept", "application/fhir+json")
    If ifMatch '= "" {
        Do http.SetHeader("If-Match", ifMatch)
        Do http.SetHeader("Prefer", "return=minimal")
        Set http.ContentType = "application/fhir+json"
        Set http.WriteRawMode = 1
        Do http.EntityBody.Write(body)
    }
    Quit http
}

/// The two counters, "received refused".
Method Counts() As %String
{
    Quit ..Stats().%Get("puts_received") _ " " _ ..Stats().%Get("puts_refused")
}

/// The fault and the times it has left, with <var>between</var> between them.
Method FaultNow(between As %String) As %String
{
    Quit ..Stats().fault _ between _ ..Stats().%Get("fault_left")
}

Method Stats() As %DynamicObject
{
    Quit $CLASSMETHOD(..#SERVICE, "Stats")
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
