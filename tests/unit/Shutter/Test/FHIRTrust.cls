/// FHIR Receiver's reads and the trust rules (Shutter.Operation.FHIRReceiver, Shutter.FHIR.Trust). The operation runs
/// in process with the test FHIR server as its adapter (Shutter.Test.FakeFhir), so every request it makes is in that
/// adapter's log; a canned answer stands for what a gateway in front of the receiver would say. A test that stores a
/// profile puts the row back as it was, and every case it saved is purged.
Class Shutter.Test.FHIRTrust Extends %UnitTest.TestCase
{

Parameter SERVICE = "FHIRFacade.Service";

Parameter RECEIVER = "UT FHIR Trust Out";

Parameter BASE = "/ut-fhir/r4";

Parameter SYS = "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49";

Parameter FHIRJSON = "application/fhir+json; charset=UTF-8";

/// The search FHIR Receiver makes for visit V1001, as the adapter logs it.
Parameter SEARCH = "Encounter?identifier=urn%3Aoid%3A2.16.840.1.113883.2.1.3.2.4.18.49%7CV1001";

Parameter OUTOFTIME = "not read: the request ran out of time";

Parameter PLAIN404 = "HTTP 404 that is not the receiver's answer (as the endpoint answers a missing or refused login)";

Property Made As %String [ MultiDimensional ];

Property SavedProfile As %String(MAXLEN = "");

Property ProfileChanged As %Boolean [ InitialExpression = 0 ];

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    If ..Loaded() Do $CLASSMETHOD(..#SERVICE, "Reset")
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    If ..Loaded() Do $CLASSMETHOD(..#SERVICE, "Reset")
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ##class(Shutter.Store.Case).PurgeCase(id)
    }
    Kill i%Made
    Do ..RestoreProfile()
    Quit $$$OK
}

/// A sign-in page behind a 200 is not the Encounter: the trusted status is 0, what came stays beside it.
Method TestAPageBehindA200IsUntrusted()
{
    Quit:'..Ready()
    Set op = ..Op(.http)
    Set http.Canned("GET", "Encounter/enc-1") = $LISTBUILD(200, "text/html; charset=utf-8", "", "", "<html><body>Sign in</body></html>")
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Do $$$AssertEquals(parts.encounter."http_status" _ " " _ parts.encounter."raw_status", "0 200", "the page's 200 is not trusted")
    Do $$$AssertEquals(parts.encounter.error, "HTTP 200 that is not the receiver's answer: the media type is not FHIR JSON", "and the part says why")
    Do $$$AssertEquals(parts.patient.error, "not read: no Patient reference to ask for", "no Patient is asked for from a page")
    Do $$$AssertEquals(parts.search."http_status" _ " " _ parts.history."http_status", "200 200", "the other parts are read as they are")
    // The same page under a FHIR media type, and under each kind
    For kind = "encounter", "patient", "location", "vread", "search", "history", "metadata" {
        Set part = ..P(200, ..#FHIRJSON, "<html><body>Sign in</body></html>")
        Do ##class(Shutter.FHIR.Trust).Part(kind, part, "", "enc-1")
        Do $$$AssertEquals(part."http_status" _ " " _ part.error, "0 HTTP 200 that is not the receiver's answer: the body is not a JSON object", "a page as " _ kind)
    }
    // A JSON array and an empty body are no resource either
    For body = "[]", "", "42" {
        Set part = ..P(200, ..#FHIRJSON, body)
        Do ##class(Shutter.FHIR.Trust).Part("encounter", part, "Encounter", "enc-1")
        Do $$$AssertEquals(part."http_status", 0, "the body '" _ body _ "'")
    }
    // No answer at all
    Set part = ..P(0, "", "")
    Do ##class(Shutter.FHIR.Trust).Part("encounter", part, "Encounter", "enc-1")
    Do $$$AssertEquals(part."http_status" _ " " _ part.error, "0 no answer", "no answer is 0")
    // Any other status passes through as it came
    For status = 401, 403, 500, 503 {
        Set part = ..P(status, "text/html", "<html></html>")
        Do ##class(Shutter.FHIR.Trust).Part("encounter", part, "Encounter", "enc-1")
        Do $$$AssertEquals(part."http_status" _ " " _ part.error, status _ " ", "HTTP " _ status _ " passes through")
    }
}

/// A plain 404 never says that the receiver has no such resource; the receiver's own 404 does.
Method TestAPlain404IsNeverNotFound()
{
    Quit:'..Ready()
    Set op = ..Op(.http)
    Set http.Canned("GET", "Patient/demo-p1") = $LISTBUILD(404, "text/plain", "", "", "Not Found")
    Set http.Canned("GET", "Location/ward-a") = $LISTBUILD(404, "application/json", "", "", "{""error"":""Not Found""}")
    Set http.Canned("GET", "Encounter/enc-1/_history") = $LISTBUILD(404, "text/html", "", "", "<html>Not Found</html>")
    Set http.Canned("GET", "metadata") = $LISTBUILD(404, "", "", "", "")
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Do $$$AssertEquals(parts.patient."http_status" _ " " _ parts.patient."raw_status", "0 404", "a plain Not Found for the Patient")
    Do $$$AssertEquals(parts.patient.error, ..#PLAIN404, "in the words of the rule")
    Do $$$AssertEquals(parts.locations.%Get(0)."http_status" _ " " _ parts.locations.%Get(0).error, "0 " _ ..#PLAIN404, "a JSON 404 that is no OperationOutcome")
    Do $$$AssertEquals(parts.history."http_status" _ " " _ parts.history.error, "0 " _ ..#PLAIN404, "a page for the history")
    Do $$$AssertEquals(parts.metadata."http_status" _ " " _ parts.metadata.error, "0 " _ ..#PLAIN404, "an empty 404 for the statement")
    // The receiver's own 404: an OperationOutcome
    Do $CLASSMETHOD(..#SERVICE, "Reset")
    Do ..Seed(0)
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "dispatch", "enc-1", "Patient/nobody", "[""Location/ward-z""]")
    Do $$$AssertEquals(parts.patient."http_status" _ " " _ parts.patient.error, "404 ", "the receiver's own 404 for a Patient it does not hold")
    Do $$$AssertEquals(parts.locations.%Get(0)."http_status" _ " " _ parts.locations.%Get(0).reference, "404 Location/ward-z", "and for a Location")
    // A 410 by the same rule
    Set part = ..P(410, ..#FHIRJSON, "{""resourceType"":""OperationOutcome"",""issue"":[]}")
    Do ##class(Shutter.FHIR.Trust).Part("encounter", part, "Encounter", "enc-1")
    Do $$$AssertEquals(part."http_status", 410, "a 410 with an OperationOutcome")
    Set part = ..P(410, "text/plain", "Gone")
    Do ##class(Shutter.FHIR.Trust).Part("vread", part, "Encounter", "enc-1")
    Do $$$AssertEquals(part."http_status" _ " " _ part.error, "0 HTTP 410 that is not the receiver's answer (as the endpoint answers a missing or refused login)", "a plain 410")
    Set part = ..P(404, "text/plain", "{""resourceType"":""OperationOutcome"",""issue"":[]}")
    Do ##class(Shutter.FHIR.Trust).Part("encounter", part, "Encounter", "enc-1")
    Do $$$AssertEquals(part."http_status", 0, "an OperationOutcome under another media type")
}

/// A 200 counts only as FHIR JSON or JSON, whatever the case and the parameters; another charset is not read.
Method TestAnotherMediaTypeIsUntrusted()
{
    Quit:'..Ready()
    Set body = ..Enc("enc-1", "V1001").%ToJSON()
    For type = "text/plain", "application/xml", "application/fhir+xml", "text/json", "", "application/json+fhir" {
        Set part = ..P(200, type, body)
        Do ##class(Shutter.FHIR.Trust).Part("encounter", part, "Encounter", "enc-1")
        Do $$$AssertEquals(part."http_status" _ " " _ part.error, "0 HTTP 200 that is not the receiver's answer: the media type is not FHIR JSON", "the media type '" _ type _ "'")
    }
    For type = "application/fhir+json", "Application/FHIR+JSON; charset=utf-8", " application/json ;q=1", "APPLICATION/JSON" {
        Set part = ..P(200, type, body)
        Do ##class(Shutter.FHIR.Trust).Part("encounter", part, "Encounter", "enc-1")
        Do $$$AssertEquals(part."http_status" _ " " _ part.error, "200 ", "the media type '" _ type _ "'")
    }
    // Through the reader: the right body under text/plain, and under a charset that is not UTF-8
    Set op = ..Op(.http)
    Set http.Canned("GET", "Encounter/enc-1") = $LISTBUILD(200, "text/plain", "W/""1""", "", body)
    Set http.Canned("GET", "Patient/demo-p1") = $LISTBUILD(200, "application/fhir+json; charset=ISO-8859-1", "W/""1""", "", "{""resourceType"":""Patient"",""id"":""demo-p1""}")
    Set http.Canned("GET", "Location/ward-a") = $LISTBUILD(200, "application/fhir+json; charset=""utf-8""", "W/""1""", "", "{""resourceType"":""Location"",""id"":""ward-a""}")
    Set http.Canned("GET", "Location/ward-b") = $LISTBUILD(200, "application/fhir+json", "W/""1""", "", "{""resourceType"":""Location"",""id"":""ward-b""}")
    Set parts = ..Run(op, ..NewCase(), "dispatch", "enc-1", "Patient/demo-p1", "[""Location/ward-a"",""Location/ward-b""]")
    Do $$$AssertEquals(parts.encounter."http_status" _ " " _ parts.encounter."raw_status", "0 200", "the Encounter as text/plain")
    Do $$$AssertEquals(parts.patient."http_status" _ " " _ parts.patient.error _ " " _ parts.patient.body, "0 the answer's charset is not UTF-8 ", "another charset is not decoded")
    Do $$$AssertEquals(parts.locations.%Get(0)."http_status" _ " " _ parts.locations.%Get(1)."http_status", "200 200", "UTF-8 named in quotes, and no charset named")
}

/// The body must be the resource that was asked for: its type and its id.
Method TestTheWrongResourceTypeOrId()
{
    Quit:'..Ready()
    Set t = "Shutter.FHIR.Trust", wrong = "0 HTTP 200 that is not the receiver's answer: the body is not the "
    Set part = ..P(200, ..#FHIRJSON, "{""resourceType"":""Patient"",""id"":""enc-1""}")
    Do $CLASSMETHOD(t, "Part", "encounter", part, "Encounter", "enc-1")
    Do $$$AssertEquals(part."http_status" _ " " _ part.error, wrong _ "Encounter asked for", "a Patient for an Encounter")
    Set part = ..P(200, ..#FHIRJSON, "{""resourceType"":""Encounter"",""id"":""enc-2""}")
    Do $CLASSMETHOD(t, "Part", "encounter", part, "Encounter", "enc-1")
    Do $$$AssertEquals(part."http_status" _ " " _ part.error, wrong _ "Encounter asked for", "another Encounter")
    Set part = ..P(200, ..#FHIRJSON, "{""resourceType"":""Encounter"",""id"":""ENC-1""}")
    Do $CLASSMETHOD(t, "Part", "vread", part, "Encounter", "enc-1")
    Do $$$AssertEquals(part."http_status", 0, "an id in another case")
    Set part = ..P(200, ..#FHIRJSON, "{""resourceType"":""Encounter"",""id"":1}")
    Do $CLASSMETHOD(t, "Part", "encounter", part, "Encounter", "1")
    Do $$$AssertEquals(part."http_status", 0, "an id that is a number")
    Set part = ..P(200, ..#FHIRJSON, "{""resourceType"":""Encounter""}")
    Do $CLASSMETHOD(t, "Part", "encounter", part, "Encounter", "")
    Do $$$AssertEquals(part."http_status", 0, "no id asked for and none given")
    Set part = ..P(200, ..#FHIRJSON, "{""resourceType"":""OperationOutcome"",""issue"":[]}")
    Do $CLASSMETHOD(t, "Part", "patient", part, "Patient", "demo-p1")
    Do $$$AssertEquals(part."http_status" _ " " _ part.error, wrong _ "Patient asked for", "an OperationOutcome behind a 200")
    Set part = ..P(200, ..#FHIRJSON, "{""resourceType"":""Location"",""id"":""ward-a""}")
    Do $CLASSMETHOD(t, "Part", "location", part, "", "ward-a")
    Do $$$AssertEquals(part."http_status" _ " " _ part.error, "200 ", "the Location asked for, the type taken from the kind")
    // The Bundles and the statement by their own types
    For row = $LISTBUILD("search", "{""resourceType"":""Bundle"",""type"":""searchset""}", 200), $LISTBUILD("search", "{""resourceType"":""Bundle"",""type"":""history""}", 0), $LISTBUILD("search", "{""resourceType"":""Bundle"",""type"":""collection""}", 0), $LISTBUILD("history", "{""resourceType"":""Bundle"",""type"":""history""}", 200), $LISTBUILD("history", "{""resourceType"":""Bundle"",""type"":""searchset""}", 0), $LISTBUILD("history", "{""resourceType"":""Encounter"",""id"":""enc-1""}", 0), $LISTBUILD("metadata", "{""resourceType"":""CapabilityStatement""}", 200), $LISTBUILD("metadata", "{""resourceType"":""Bundle"",""type"":""searchset""}", 0) {
        Set part = ..P(200, ..#FHIRJSON, $LIST(row, 2))
        Do $CLASSMETHOD(t, "Part", $LIST(row, 1), part)
        Do $$$AssertEquals(part."http_status", $LIST(row, 3), $LIST(row, 1) _ ": " _ $LIST(row, 2))
    }
    // Through the reader: the server answers the read of enc-1 with another Encounter
    Set op = ..Op(.http)
    Set http.Canned("GET", "Encounter/enc-1") = $LISTBUILD(200, ..#FHIRJSON, "W/""1""", "", ..Enc("enc-2", "V1001").%ToJSON())
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Do $$$AssertEquals(parts.encounter."http_status" _ " " _ parts.encounter.error, wrong _ "Encounter asked for", "the reader asks by the id it searched")
}

/// A Location header, when there is one, must name the version of the ETag.
Method TestALocationHeaderNamingAnotherVersion()
{
    Quit:'..Ready()
    Set t = "Shutter.FHIR.Trust", body = "{""resourceType"":""Encounter"",""id"":""enc-1""}"
    Set other = "0 HTTP 200 whose Location header names another version than its ETag"
    For row = $LISTBUILD("W/""2""", "/r4/Encounter/enc-1/_history/2", "200 "), $LISTBUILD("W/""2""", "", "200 "), $LISTBUILD("", "", "200 "), $LISTBUILD("W/""2""", "/r4/Encounter/enc-1/_history/1", other), $LISTBUILD("W/""2""", "/r4/Encounter/enc-1/_history/22", other), $LISTBUILD("W/""2""", "/r4/Encounter/enc-1", other), $LISTBUILD("W/""2""", "/r4/Encounter/enc-1/_history/2/", other), $LISTBUILD("""2""", "/r4/Encounter/enc-1/_history/2", other), $LISTBUILD("", "/r4/Encounter/enc-1/_history/2", other), $LISTBUILD("W/""""", "/r4/Encounter/enc-1/_history/", other) {
        Set part = ..P(200, ..#FHIRJSON, body, $LIST(row, 1), $LIST(row, 2))
        Do $CLASSMETHOD(t, "Part", "encounter", part, "Encounter", "enc-1")
        Do $$$AssertEquals(part."http_status" _ " " _ part.error, $LIST(row, 3), "ETag " _ $LIST(row, 1) _ " with Location '" _ $LIST(row, 2) _ "'")
    }
    // Through the reader: the server's own Location passes, a canned one for another version does not
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Do $$$AssertEquals(parts.encounter."http_status" _ " " _ parts.encounter.etag _ " " _ parts.encounter.location, "200 W/""1"" " _ ..#BASE _ "/Encounter/enc-1/_history/1", "the ETag and the Location are carried as they came")
    Set op = ..Op(.http)
    Set http.Canned("GET", "Encounter/enc-1") = $LISTBUILD(200, ..#FHIRJSON, "W/""3""", ..#BASE _ "/Encounter/enc-1/_history/1", ..Enc("enc-1", "V1001").%ToJSON())
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Do $$$AssertEquals(parts.encounter."http_status" _ " " _ parts.encounter.error, other, "a Location for version 1 beside the ETag of version 3")
    Do $$$AssertEquals(parts.encounter.etag _ " " _ parts.encounter."raw_status", "W/""3"" 200", "what came stays on the part")
}

/// Only entries whose search.mode is match, or that have none, are matches; the reader reads the single match.
Method TestSearchCountsMatchEntriesOnly()
{
    Quit:'..Ready()
    Set t = "Shutter.FHIR.Trust"
    Set bundle = {"resourceType": "Bundle", "type": "searchset", "entry": []}
    Do bundle.entry.%Push({"resource": {"resourceType": "Patient", "id": "demo-p1"}, "search": {"mode": "include"}})
    Do bundle.entry.%Push({"resource": (..Enc("enc-1", "V1001")), "search": {"mode": "match"}})
    Do bundle.entry.%Push({"resource": {"resourceType": "OperationOutcome", "issue": []}, "search": {"mode": "outcome"}})
    Set matches = $CLASSMETHOD(t, "Matches", bundle)
    Do $$$AssertEquals(matches.%Size() _ " " _ matches.%Get(0).id, "1 enc-1", "one match among an include and an outcome")
    Do bundle.entry.%Push({"resource": (..Enc("enc-7", "V1001"))})
    Do bundle.entry.%Push({"resource": (..Enc("enc-8", "V1001")), "search": {}})
    Do bundle.entry.%Push({"resource": (..Enc("enc-9", "V1001")), "search": {"mode": "Match"}})
    Do bundle.entry.%Push({"search": {"mode": "match"}})
    Set matches = $CLASSMETHOD(t, "Matches", bundle)
    Do $$$AssertEquals(matches.%Size() _ " " _ matches.%Get(1).id _ " " _ matches.%Get(2).id _ " '" _ matches.%Get(3) _ "'", "4 enc-7 enc-8 ''", "an entry with no mode counts, another spelling does not, a match with no resource counts")
    Do $$$AssertEquals($CLASSMETHOD(t, "Matches", {"resourceType": "Bundle", "type": "searchset"}).%Size() _ " " _ $CLASSMETHOD(t, "Matches", "").%Size(), "0 0", "no entries, no Bundle")

    // The reader: one match beside an included resource is the Encounter it reads
    Set one = {"resourceType": "Bundle", "type": "searchset", "entry": []}
    Do one.entry.%Push({"resource": (..Enc("enc-9", "V9")), "search": {"mode": "include"}})
    Do one.entry.%Push({"resource": (..Enc("enc-1", "V1001")), "search": {"mode": "match"}})
    Set op = ..Op(.http)
    Set http.Canned("GET", ..#SEARCH) = $LISTBUILD(200, ..#FHIRJSON, "", "", one.%ToJSON())
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Do $$$AssertEquals(parts.encounter."http_status" _ " " _ ..J(parts.encounter.body).id, "200 enc-1", "the match is read, the include is not")
    Do $$$AssertNotTrue(..Log(http) [ "enc-9", "no request names the included Encounter")
    // Two matches: no Encounter is asked for
    Do one.entry.%Push({"resource": (..Enc("enc-9", "V1001"))})
    Set op = ..Op(.http)
    Set http.Canned("GET", ..#SEARCH) = $LISTBUILD(200, ..#FHIRJSON, "", "", one.%ToJSON())
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Do $$$AssertEquals(parts.search."http_status", 200, "the search itself is trusted")
    Do $$$AssertEquals(parts.encounter."http_status" _ " " _ parts.encounter.error, "0 not read: the search gave 2 matches", "two matches")
    Do $$$AssertEquals(parts.history.error _ " " _ parts.patient.error, "not read: the search gave 2 matches not read: no Patient reference to ask for", "nor its history or its Patient")
    Do $$$AssertEquals(..Log(http), "metadata | " _ ..#SEARCH _ " | Location/ward-a | Location/ward-b", "the requests that were made")
    // No match at all, from the server itself
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase("V4040"), "evidence")
    Do $$$AssertEquals(parts.search."http_status" _ " " _ parts.encounter.error, "200 not read: the search gave 0 matches", "no match")
    // A case with no visit number searches nothing
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase("-"), "evidence")
    Do $$$AssertEquals(parts.search."http_status" _ " " _ parts.encounter.error, "0 not read: the search was not read", "no visit number")
    Do $$$AssertNotTrue(..Log(http) [ "identifier", "and no search is sent")
}

/// Evidence: the statement, the search, the Encounter, its Patient, every mapped Location and the history, once each.
Method TestEvidenceReadsEachPartOnce()
{
    Quit:'..Ready()
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Do $$$AssertEquals(..Log(http), "metadata | " _ ..#SEARCH _ " | Encounter/enc-1 | Patient/demo-p1 | Location/ward-a | Location/ward-b | Encounter/enc-1/_history", "each part is read once, in this order")
    Do $$$AssertEquals(..Keys(parts), "observed_at,base,metadata,search,encounter,patient,locations,history", "the parts of an evidence read")
    Do $$$AssertEquals(parts.base, ..#BASE, "the base is the entry's")
    Do $$$AssertTrue(parts."observed_at" ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "observed_at is a UTC time: " _ parts."observed_at")
    Set all = parts.metadata."http_status" _ " " _ parts.search."http_status" _ " " _ parts.encounter."http_status" _ " " _ parts.patient."http_status" _ " " _ parts.locations.%Get(0)."http_status" _ " " _ parts.locations.%Get(1)."http_status" _ " " _ parts.history."http_status"
    Do $$$AssertEquals(all, "200 200 200 200 200 200 200", "every part is trusted")
    Do $$$AssertEquals(..Keys(parts.encounter), "http_status,raw_status,etag,location,content_type,body,error", "the shape of a part")
    Do $$$AssertEquals(..Keys(parts.locations.%Get(1)), "http_status,raw_status,etag,location,content_type,body,error,reference", "a location part also has its reference")
    Do $$$AssertEquals(parts.locations.%Get(0).reference _ " " _ parts.locations.%Get(1).reference, "Location/ward-a Location/ward-b", "in the map's order")
    Do $$$AssertEquals(parts.encounter."content_type" _ " " _ parts.encounter.etag, ..#FHIRJSON _ " W/""1""", "the content type and the ETag verbatim")
    Do $$$AssertEquals(..J(parts.history.body).type _ " " _ ..J(parts.search.body).type, "history searchset", "the Bundles are carried whole")
}

/// Dispatch: the statement and the reads by id; no search.
Method TestDispatchReadsMetadataAndNoSearch()
{
    Quit:'..Ready()
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "dispatch", "enc-1", "Patient/demo-p1", "[""Location/ward-b""]")
    Do $$$AssertEquals(..Log(http), "metadata | Encounter/enc-1 | Patient/demo-p1 | Location/ward-b | Encounter/enc-1/_history", "the requests of a dispatch read")
    Do $$$AssertEquals(..Keys(parts), "observed_at,base,metadata,encounter,patient,locations,history", "no search part and no vread part")
    Do $$$AssertEquals(parts.locations.%Size() _ " " _ parts.locations.%Get(0).reference _ " " _ parts.locations.%Get(0)."http_status", "1 Location/ward-b 200", "only the Locations the request names")
    // With no Patient reference the Encounter's own literal subject is read; a reference that is not literal is not
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "dispatch", "enc-1", "", "[]")
    Do $$$AssertEquals(..Log(http), "metadata | Encounter/enc-1 | Patient/demo-p1 | Encounter/enc-1/_history", "the subject of the Encounter that was read")
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "dispatch", "enc-1", "Patient/demo-p1/_history/1", "[""http://other.test/Location/ward-a"", ""Location/ward a"", 7]")
    Do $$$AssertEquals(parts.patient.error, "not read: the Patient reference is not a literal Patient/{id}", "a versioned reference is not asked for")
    Do $$$AssertEquals(parts.locations.%Get(0).error _ " " _ parts.locations.%Get(0).reference, "not read: the Location reference is not a literal Location/{id} http://other.test/Location/ward-a", "nor an absolute one")
    Do $$$AssertEquals(parts.locations.%Get(1)."http_status" _ " " _ parts.locations.%Get(2).reference, "0 ", "nor one with a space or a number")
    Do $$$AssertEquals(..Log(http), "metadata | Encounter/enc-1 | Encounter/enc-1/_history", "and nothing is sent for them")
    // An id that cannot be asked for sends nothing for the Encounter
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "dispatch", "enc-1/../Patient", "Patient/demo-p1", "[]")
    Do $$$AssertEquals(parts.encounter.error _ " | " _ ..Log(http), "not read: no Encounter id that can be asked for | metadata | Patient/demo-p1", "an id with a slash")
}

/// Verify: the reads by id and no statement; the read of one version only when the request names it.
Method TestVerifyReadsTheVreadOnlyWithAVid()
{
    Quit:'..Ready()
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "verify", "enc-1", "Patient/demo-p1", "[""Location/ward-a"",""Location/ward-b""]")
    Do $$$AssertEquals(..Log(http), "Encounter/enc-1 | Patient/demo-p1 | Location/ward-a | Location/ward-b | Encounter/enc-1/_history", "no statement, no search, no version read")
    Do $$$AssertEquals(..Keys(parts), "observed_at,base,encounter,patient,locations,history", "the parts of a verify read with no version")
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "verify", "enc-1", "Patient/demo-p1", "[""Location/ward-b""]", "1")
    Do $$$AssertEquals(..Log(http), "Encounter/enc-1 | Patient/demo-p1 | Location/ward-b | Encounter/enc-1/_history | Encounter/enc-1/_history/1", "the version is read last")
    Do $$$AssertEquals(..Keys(parts), "observed_at,base,encounter,patient,locations,history,vread", "with its part")
    Do $$$AssertEquals(parts.vread."http_status" _ " " _ parts.vread.etag _ " " _ ..J(parts.vread.body).id, "200 W/""1"" enc-1", "the version asked for")
    // A version the receiver does not hold is its own 404; one that cannot be asked for is not sent
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "verify", "enc-1", "Patient/demo-p1", "[]", "9")
    Do $$$AssertEquals(parts.vread."http_status", 404, "an unknown version")
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "verify", "enc-1", "Patient/demo-p1", "[]", "1/../2")
    Do $$$AssertEquals(parts.vread.error _ " | " _ ..Log(http), "not read: the version id cannot be asked for | Encounter/enc-1 | Patient/demo-p1 | Encounter/enc-1/_history", "a version id with a slash")
    // A dispatch read never reads a version, whatever the request says
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "dispatch", "enc-1", "Patient/demo-p1", "[]", "1")
    Do $$$AssertNotTrue(parts.%IsDefined("vread") || (..Log(http) [ "_history/1"), "no version read on a dispatch read")
}

/// The statement's part carries what is read out of it and never the statement itself.
Method TestMetadataCarriesNoBody()
{
    Quit:'..Ready()
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Do $$$AssertEquals(..Keys(parts.metadata), "http_status,raw_status,etag,location,content_type,error,statement", "no body in the metadata part")
    Do $$$AssertEquals(parts.metadata.statement.%ToJSON(), "{""software"":{""name"":""Shutter test FHIR server"",""version"":""facade-v1""},""fhir_version"":""4.0.1"",""versioning"":""versioned-update"",""interactions"":[""read"",""vread"",""create"",""update"",""patch"",""delete"",""history-instance"",""search-type""],""read_history"":true,""update_create"":true}", "the statement as the reader extracts it")
    // A statement that is not the receiver's has no body either, and no statement
    Set op = ..Op(.http)
    Set http.Canned("GET", "metadata") = $LISTBUILD(200, "text/html", "", "", "<html>Sign in</html>")
    Set parts = ..Run(op, ..NewCase(), "dispatch", "enc-1", "Patient/demo-p1", "[]")
    Do $$$AssertEquals(..Keys(parts.metadata) _ " " _ parts.metadata."http_status", "http_status,raw_status,etag,location,content_type,error 0", "a page for the statement")
    // What is read is of the rest entry of mode server and the Encounter type only
    Set cs = {"resourceType": "CapabilityStatement", "fhirVersion": "4.0.1", "software": {"name": "S", "version": 7}, "rest": [{"mode": "client", "resource": [{"type": "Encounter", "versioning": "no-version", "readHistory": true, "updateCreate": true, "interaction": [{"code": "delete"}]}]}, {"mode": "server", "resource": [{"type": "Patient", "versioning": "versioned", "readHistory": true, "updateCreate": true, "interaction": [{"code": "patch"}]}, {"type": "Encounter", "versioning": "versioned", "readHistory": "true", "interaction": [{"code": "read"}, {"code": 5}, "update", {"code": "update"}]}]}]}
    Set st = ##class(Shutter.Operation.FHIRReceiver).Statement(cs.%ToJSON())
    Do $$$AssertEquals(st.%ToJSON(), "{""software"":{""name"":""S"",""version"":""""},""fhir_version"":""4.0.1"",""versioning"":""versioned"",""interactions"":[""read"",""update""],""read_history"":false,""update_create"":false}", "only the server's Encounter entry, and only values of the right type")
    Do $$$AssertEquals(##class(Shutter.Operation.FHIRReceiver).Statement("{""resourceType"":""CapabilityStatement""}").%ToJSON(), "{""software"":{""name"":"""",""version"":""""},""fhir_version"":"""",""versioning"":"""",""interactions"":[],""read_history"":false,""update_create"":false}", "a statement that says nothing")
}

/// A body arrives as UTF-8 bytes and is carried as characters. Of a Location only what the checks read is carried,
/// so the text above ASCII is in an identifier's value: its name is not carried at all.
Method TestADisplayAboveAsciiIsDecoded()
{
    Quit:'..Ready()
    Set name = "Zo" _ $CHAR(235) _ " " _ $CHAR(321) _ "uk Ward"
    Do $CLASSMETHOD(..#SERVICE, "Seed", [{"resourceType": "Location", "id": "ward-a", "identifier": [{"system": "urn:shutter:ward", "value": "WARD-A"}, {"system": "urn:shutter:ward-name", "value": (name)}], "status": "active", "name": (name)}])
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Set location = parts.locations.%Get(0)
    Do $$$AssertEquals(location."http_status" _ " " _ ..J(location.body).identifier.%Get(1).value, "200 " _ name, "the value is read as its characters")
    Do $$$AssertEquals(..J(location.body).%GetTypeOf("name"), "unassigned", "and the Location's name is not carried")
    Do $$$AssertEquals(location.etag, "W/""2""", "of the version that holds it")
}

/// A body over the limit is not trusted, and answers that are together too large give one error and no parts.
Method TestTooLargeAnswersGiveAnError()
{
    Quit:'..Ready()
    Set op = ..Op(.http)
    Do $$$AssertEquals(op.MaxBody _ " " _ op.MaxTotal, "1000000 1500000", "the bounds of the design")
    Set big = ..Enc("enc-1", "V1001")
    Do big.%Set("text", {"status": "generated", "div": ($TRANSLATE($JUSTIFY("", 2000), " ", "x"))})
    Set http.Canned("GET", "Encounter/enc-1") = $LISTBUILD(200, ..#FHIRJSON, "W/""1""", "", big.%ToJSON())
    Set op.MaxBody = 1500
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Do $$$AssertEquals(parts.encounter."http_status" _ " " _ parts.encounter."raw_status" _ " " _ parts.encounter.error _ " '" _ parts.encounter.body _ "'", "0 200 the answer's body is over 1500 characters ''", "a body over the limit is not carried")
    Do $$$AssertEquals(parts.history."http_status", 200, "the parts under it are")
    // Together too large: one error, no parts, and the reads stop there
    Set op = ..Op(.http)
    Set http.Canned("GET", "Encounter/enc-1") = $LISTBUILD(200, ..#FHIRJSON, "W/""1""", "", big.%ToJSON())
    Set op.MaxTotal = 2500
    Set parts = ..Run(op, ..NewCase(), "evidence", , , , , .response)
    Do $$$AssertEquals(response.Error, "the receiver's answers are together too large to carry", "the error of the design")
    Do $$$AssertEquals(response.PartsJSON, "", "and no parts")
    Do $$$AssertEquals(..Log(http), "metadata | " _ ..#SEARCH _ " | Encounter/enc-1", "nothing is read after the bound is passed")
    // The statement's body is dropped, so it does not count; the parts as carried are what is bounded
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "evidence", , , , , .response)
    Set size = $LENGTH(response.PartsJSON)
    Do $$$AssertTrue((response.Error = "") && (size > 0), "an ordinary read is carried: " _ size _ " characters")
    Set op = ..Op(.http)
    Set op.MaxTotal = size - 1
    Set parts = ..Run(op, ..NewCase(), "evidence", , , , , .response)
    Do $$$AssertEquals(response.Error _ "|" _ response.PartsJSON, "the receiver's answers are together too large to carry|", "one character under what the parts take")
    Set op = ..Op(.http)
    Set op.MaxTotal = size
    Set parts = ..Run(op, ..NewCase(), "evidence", , , , , .response)
    Do $$$AssertEquals(response.Error _ "|" _ $LENGTH(response.PartsJSON), "|" _ size, "exactly what the parts take")
}

/// A request reads for its time and no longer: what was not read says so.
Method TestTheRequestGivesUpAfterItsTime()
{
    Quit:'..Ready()
    Set op = ..Op(.http)
    Do $$$AssertEquals(op.Budget, 45, "45 seconds by the design")
    Set op.Budget = 0
    Set parts = ..Run(op, ..NewCase(), "dispatch", "enc-1", "Patient/demo-p1", "[""Location/ward-a""]")
    Do $$$AssertEquals(..Log(http), "", "with no time nothing is sent")
    For key = "metadata", "encounter", "patient", "history" {
        Do $$$AssertEquals(parts.%Get(key)."http_status" _ " " _ parts.%Get(key).error, "0 " _ ..#OUTOFTIME, "the " _ key _ " part")
    }
    Do $$$AssertEquals(parts.locations.%Get(0).error _ " " _ parts.locations.%Get(0).reference, ..#OUTOFTIME _ " Location/ward-a", "a location part, with its reference")
    Do $$$AssertNotTrue(parts.metadata.%IsDefined("body"), "the unread statement has no body either")
    // The time runs out between two reads: what was read stays, the rest says so
    Set op = ..Op(.http)
    Set op.Budget = 3600
    Set op.Started = $ZHOROLOG
    Set first = op.Get(..#BASE _ "/Encounter/enc-1", "encounter", "Encounter", "enc-1")
    Set op.Started = $ZHOROLOG - 3600
    Set second = op.Get(..#BASE _ "/Patient/demo-p1", "patient", "Patient", "demo-p1")
    Do $$$AssertEquals(first."http_status" _ " " _ second."http_status" _ " " _ second.error, "200 0 " _ ..#OUTOFTIME, "the read after the time is not made")
    Do $$$AssertEquals(..Log(http), "Encounter/enc-1", "one request in the log")
    // The adapter waits no longer than the time that is left, and has its own setting back afterwards
    Set op = ..Op(.http)
    Set http.ResponseTimeout = 30
    Set op.Budget = 10
    Set parts = ..Run(op, ..NewCase(), "verify", "enc-1", "Patient/demo-p1", "[]")
    Do $$$AssertEquals(http.ResponseTimeout, 30, "the adapter's own timeout is put back")
}

/// The request names no receiver: the address is the fhir block's of the case's own receiver.
Method TestNoRequestNamesAReceiver()
{
    Quit:'..Ready()
    Set names = ""
    For class = "Shutter.Msg.FHIRRead", "Shutter.Msg.FHIRReadResult" {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Name FROM %Dictionary.CompiledProperty WHERE parent = ? AND Origin = ? ORDER BY Name", class, class)
        While rs.%Next() { Set names = names _ rs.%Get("Name") _ " " }
    }
    Do $$$AssertEquals(names, "CaseId EncounterId LocationRefsJSON PatientRef Purpose Vid Error PartsJSON ", "the properties of the request and its answer")
    // Every address begins with the base of the case's receiver; the fake adapter takes its own base off the log
    Set op = ..Op(.http)
    Set http.Base = ""
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Set n = 0
    For i = 1:1:+$GET(http.Requests) {
        Set:$EXTRACT($LIST(http.Requests(i), 2), 1, $LENGTH(..#BASE) - 1)=$EXTRACT(..#BASE, 2, *) n = n + 1
    }
    Do $$$AssertEquals(n _ " of " _ +$GET(http.Requests), "4 of 4", "every request begins with the entry's base")
    // The base changes with the entry, a slash at its end is dropped
    Do ..ChangeEntry({"base": "/other/base/"})
    Set op = ..Op(.http)
    Set http.Base = "/other/base"
    Set parts = ..Run(op, ..NewCase(), "evidence")
    Do $$$AssertEquals(parts.base _ " " _ parts.encounter."http_status" _ " " _ parts.encounter.location, "/other/base 200 /other/base/Encounter/enc-1/_history/1", "the entry's new base")
    // A case of a receiver with no fhir block, an unknown case and an unknown purpose read nothing
    For row = $LISTBUILD("Ward Out", "evidence", "the case's receiver has no fhir block in the site profile"), $LISTBUILD("No Such Receiver", "evidence", "the case's receiver has no fhir block in the site profile"), $LISTBUILD(..#RECEIVER, "write", "unknown purpose of a FHIR read") {
        Set op = ..Op(.http)
        Set request = ##class(Shutter.Msg.FHIRRead).%New()
        Set request.CaseId = ..NewCase("V1001", $LIST(row, 1)).CaseId, request.EncounterId = "enc-1"
        Set request.Purpose = $LIST(row, 2)
        Do $$$AssertStatusOK(op.OnRead(request, .response), "the request is answered")
        Do $$$AssertEquals(response.Error _ "|" _ response.PartsJSON _ "|" _ +$GET(http.Requests), $LIST(row, 3) _ "||0", "receiver " _ $LIST(row, 1) _ ", purpose " _ $LIST(row, 2))
    }
    Set op = ..Op(.http)
    Set request = ##class(Shutter.Msg.FHIRRead).%New()
    Set request.CaseId = "UT-NO-SUCH-CASE", request.Purpose = "evidence"
    Do $$$AssertStatusOK(op.OnRead(request, .response), "the request is answered")
    Do $$$AssertEquals(response.Error _ "|" _ response.PartsJSON _ "|" _ +$GET(http.Requests), "unknown case UT-NO-SUCH-CASE||0", "an unknown case")
    // References that are not a list
    Set op = ..Op(.http)
    Set parts = ..Run(op, ..NewCase(), "dispatch", "enc-1", "", "{""a"":1}", , .response)
    Do $$$AssertEquals(response.Error _ "|" _ +$GET(http.Requests), "the Location references of the request are not a list of at most 25|0", "Location references that are an object")
}

// ---- helpers ----

Method Loaded() As %Boolean
{
    Quit ##class(%Dictionary.CompiledClass).%ExistsId(..#SERVICE)
}

/// Whether the test can run: the test FHIR server is loaded. Seeds it and puts this class's receiver in the profile.
Method Ready() As %Boolean
{
    If '..Loaded() {
        Do $$$AssertSkipped("FHIRFacade is not loaded on this instance")
        Quit 0
    }
    Do ..Seed()
    Do ..ChangeEntry("")
    Quit 1
}

/// Two wards, a patient and enc-1 at Ward A for visit V1001.
Method Seed(assert As %Boolean = 1)
{
    Set seed = []
    Do seed.%Push({"resourceType": "Location", "id": "ward-a", "identifier": [{"system": "urn:shutter:ward", "value": "WARD-A"}], "status": "active", "name": "Ward A"})
    Do seed.%Push({"resourceType": "Location", "id": "ward-b", "identifier": [{"system": "urn:shutter:ward", "value": "WARD-B"}], "status": "active", "name": "Ward B"})
    Do seed.%Push({"resourceType": "Patient", "id": "demo-p1", "identifier": [{"system": "urn:shutter:demo:mrn", "value": "MRN-UT1"}], "active": true})
    Do seed.%Push(..Enc("enc-1", "V1001"))
    Set out = $CLASSMETHOD(..#SERVICE, "Seed", seed)
    If assert Do $$$AssertEquals(out.%Get(3).status, 201, "the seed is written")
}

Method Enc(id As %String, value As %String) As %DynamicObject
{
    Quit {"resourceType": "Encounter", "id": (id), "status": "in-progress", "identifier": [{"system": (..#SYS), "value": (value)}], "class": {"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IMP"}, "subject": {"reference": "Patient/demo-p1"}, "location": [{"location": {"reference": "Location/ward-a"}, "status": "active", "period": {"start": "2026-11-07T09:00:00Z"}}]}
}

/// The operation with the test FHIR server as its adapter.
Method Op(Output http As Shutter.Test.FakeFhir) As Shutter.Operation.FHIRReceiver
{
    Set op = ##class(Shutter.Operation.FHIRReceiver).%New("FHIR Receiver (unit test)")
    Set http = ##class(Shutter.Test.FakeFhir).%New()
    Set http.Base = ..#BASE
    Set op.Adapter = http
    Quit op
}

/// One request through the operation: the parts, or "" with the error on the response. Every request it made is a GET.
Method Run(op As Shutter.Operation.FHIRReceiver, case As Shutter.Store.Case, purpose As %String, encounterId As %String = "", patientRef As %String = "", refs As %String = "", vid As %String = "", Output response As Shutter.Msg.FHIRReadResult) As %DynamicObject
{
    Set request = ##class(Shutter.Msg.FHIRRead).%New()
    Set request.CaseId = case.CaseId, request.Purpose = purpose, request.EncounterId = encounterId
    Set request.PatientRef = patientRef, request.LocationRefsJSON = refs, request.Vid = vid
    Do $$$AssertStatusOK(op.OnRead(request, .response), "the " _ purpose _ " read is answered")
    Set http = op.Adapter, others = ""
    For i = 1:1:+$GET(http.Requests) {
        Set verb = $LIST(http.Requests(i), 1)
        Set:(verb'="GET")||($LIST(http.Requests(i), 3)'="")||($LIST(http.Requests(i), 4)'="") others = others _ verb _ " " _ $LIST(http.Requests(i), 2) _ "; "
    }
    Do $$$AssertEquals(others, "", "no request other than a GET with no body and no If-Match (" _ +$GET(http.Requests) _ " requests)")
    If response.PartsJSON = "" Quit ""
    Quit ..J(response.PartsJSON)
}

/// The paths of the requests the adapter saw, in order.
Method Log(http As Shutter.Test.FakeFhir) As %String
{
    Set out = ""
    For i = 1:1:+$GET(http.Requests) {
        Set out = out _ $SELECT(i > 1: " | ", 1: "") _ $LIST(http.Requests(i), 2)
    }
    Quit out
}

/// A body as its JSON object.
ClassMethod J(text As %String) As %DynamicObject
{
    Quit ##class(%DynamicAbstractObject).%FromJSON(text)
}

/// The keys of an object, in its order.
ClassMethod Keys(obj As %DynamicObject) As %String
{
    Set out = "", it = obj.%GetIterator()
    While it.%GetNext(.key) { Set out = out _ $SELECT(out = "": "", 1: ",") _ key }
    Quit out
}

/// A part as the reader hands it to the trust rule.
ClassMethod P(status As %Integer, contentType As %String, body As %String, etag As %String = "", location As %String = "") As %DynamicObject
{
    Set part = {"http_status": (status), "raw_status": (status), "error": ""}
    Do part.%Set("etag", etag, "string")
    Do part.%Set("location", location, "string")
    Do part.%Set("content_type", contentType, "string")
    Do part.%Set("body", body, "string")
    Quit part
}

/// A saved case of this class's receiver (or another), for visit <var>visit</var>.
Method NewCase(visit As %String = "V1001", receiver As %String = "") As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-FHIRTR-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.FHIRTrust)
    Set case.Event = "transfer", case.FailureKind = "delivery_failed", case.FailureText = "made up", case.EncounterId = visit
    Set case.PatientId = "MRN-UT1", case.PatientIdAuthority = "HOSP", case.Receiver = $SELECT(receiver = "": ..#RECEIVER, 1: receiver), case.State = "collecting", case.Mode = "rules"
    Set case.OperationKey = "PAS^HOSP^MRN-UT1^" _ visit _ "^transfer^" _ case.CaseId
    Set case.EventTime = "2026-11-14T10:30:00Z"
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Do $$$AssertStatusOK(case.%Save(), "the case is saved")
    Set i%Made(case.%Id()) = ""
    Quit case
}

/// Puts this class's receiver into the stored profile (once per test), with <var>patch</var> set over its fhir block.
Method ChangeEntry(patch As %DynamicObject)
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..ProfileChanged {
        Set ..HadProfileRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: ""), ..ProfileChanged = 1
    }
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    Set entry = {"name": (..#RECEIVER), "system": "the ward system (FHIR R4)", "category": "current_state", "tier": 3, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "fhir": {"base": (..#BASE), "recovery_enabled": true, "encounter_identifier": {"system": (..#SYS)}, "patient_identifier": {"system": "urn:shutter:demo:mrn", "hl7_authority": "HOSP"}, "marker": {"system": "urn:shutter:recovery"}, "location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}
    If $ISOBJECT(patch) {
        Set it = patch.%GetIterator()
        While it.%GetNext(.key, .value) { Do entry.fhir.%Set(key, value) }
    }
    // Every other entry stays as it is, but for another FHIR entry (a profile holds one, and an entry behind another
    // is none a save takes); an earlier copy of this one is replaced
    Set kept = [], list = p.%Get("receivers")
    If $ISOBJECT(list) {
        Set it = list.%GetIterator()
        While it.%GetNext(.i, .r) { Do:'($ISOBJECT(r)&&((r.%Get("name")=..#RECEIVER)||r.%IsDefined("fhir"))) kept.%Push(r) }
    }
    Do kept.%Push(entry)
    Do p.%Set("receivers", kept)
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Name = "current", row.Version = version
    Set row.Json = p.%ToJSON()
    Do $$$AssertStatusOK(row.%Save(), "the site profile holds the test's receiver")
}

Method RestoreProfile()
{
    Quit:'..ProfileChanged
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..HadProfileRow {
        If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
    } ElseIf $ISOBJECT(row) {
        Set row.Json = ..SavedProfile
        Do row.%Save()
    }
    Set ..ProfileChanged = 0
}

}
