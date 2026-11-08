/// Runs every exchange of <code>tests/conformance/fhir-facade-v1.json</code> whose targets include the test FHIR server,
/// in order, in process through <code>FHIRFacade.Service.Handle</code>, after its reset and with its clock fixed. The
/// exchanges are the S0 measurements of IRIS for Health's own FHIR server, so a pass says the test server answers as
/// IRIS was measured to. The cases are embedded below (XData Cases, written from the file by
/// <code>tests/conformance/embed.py</code>), because a stock-install container does not mount the repository; the second
/// test checks the copy against the file when the file can be read. <code>tests/conformance/fhir_conformance.py</code>
/// runs the same file over HTTP, against IRIS or the test server.
Class Shutter.Test.FHIRFacadeConformance Extends %UnitTest.TestCase
{

Parameter SERVICE = "FHIRFacade.Service";

Parameter BASE = "http://facade.test/fhir/r4";

Parameter CLOCK = "2026-11-08T02:31:53Z";

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

Method TestEveryFacadeExchange()
{
    If '..Loaded() {
        Do $$$AssertSkipped("FHIRFacade is not loaded on this instance")
        Quit
    }
    Set doc = ..Cases(), vars = {}, run = 0
    Set iter = doc.exchanges.%GetIterator()
    While iter.%GetNext(, .x) {
        Continue:'..Targets(x, "facade")
        Set run = run + 1
        Set got = ..Send(x.request, vars)
        Set problems = ..Check(x.expect, got, vars)
        Do $$$AssertEquals(problems.%Size(), 0, x.id _ $SELECT(problems.%Size() = 0: "", 1: ": " _ problems.%ToJSON()))
        Do ..Capture(x, got, vars)
    }
    Do $$$AssertTrue(run >= 60, run _ " exchanges ran against the test server")
}

/// The embedded copy is the file, when the file is where the unit runner was pointed.
Method TestEmbeddedCopyMatchesTheFile()
{
    Set file = $GET(^UnitTestRoot) _ "../conformance/fhir-facade-v1.json"
    If ($GET(^UnitTestRoot) = "") || '##class(%File).Exists(file) {
        Do $$$AssertSkipped("the conformance file is not on this instance (" _ file _ "); tests/conformance/embed.py --check compares them")
        Quit
    }
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(file)
    Set stream.TranslateTable = "UTF8"
    Set fromFile = {}.%FromJSON(stream)
    Do $$$AssertEquals(fromFile.%ToJSON(), ..Cases().%ToJSON(), "XData Cases is the conformance file")
}

Method Loaded() As %Boolean
{
    Quit ##class(%Dictionary.CompiledClass).%ExistsId(..#SERVICE)
}

ClassMethod Cases() As %DynamicObject
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Cases")
    Quit {}.%FromJSON(xdata.Data)
}

ClassMethod Targets(x As %DynamicObject, target As %String) As %Boolean
{
    Set iter = x.targets.%GetIterator()
    While iter.%GetNext(, .t) {
        Return:t=target 1
    }
    Quit 0
}

/// The run's values in place of {p}, {P} (both empty on the test server after its reset) and the captured names.
ClassMethod Subst(text As %String, vars As %DynamicObject) As %String
{
    Set text = $REPLACE($REPLACE(text, "{p}", ""), "{P}", "")
    Set iter = vars.%GetIterator()
    While iter.%GetNext(.name, .value) {
        Set text = $REPLACE(text, "{" _ name _ "}", value)
    }
    Quit text
}

ClassMethod Send(request As %DynamicObject, vars As %DynamicObject) As %DynamicObject
{
    If request.method = "RESET" {
        Do $CLASSMETHOD(..#SERVICE, "Reset")
        Quit {"status": 200, "headers": {}, "body": ""}
    }
    Set path = ..Subst(request.path, vars), query = ""
    If path [ "?" {
        Set query = $PIECE(path, "?", 2, *), path = $PIECE(path, "?", 1)
    }
    Set headers = {}
    Set iter = request.headers.%GetIterator()
    While iter.%GetNext(.name, .value) {
        Do headers.%Set(name, ..Subst(value, vars))
    }
    Set body = $SELECT(request.%IsDefined("body"): ..Subst(request.body, vars), 1: "")
    Quit $CLASSMETHOD(..#SERVICE, "Handle", {"method": (request.method), "path": (path), "query": (query), "headers": (headers), "body": (body), "base": (..#BASE)})
}

ClassMethod Capture(x As %DynamicObject, got As %DynamicObject, vars As %DynamicObject)
{
    Quit:'x.%IsDefined("capture")
    Set iter = x.capture.%GetIterator()
    While iter.%GetNext(.name, .how) {
        If how = "etag_vid" {
            Do vars.%Set(name, $CLASSMETHOD(..#SERVICE, "EtagVersion", ..Header(got, "ETag")))
        } ElseIf how = "body" {
            Do vars.%Set(name, got.body)
        } ElseIf how = "link_next" {
            Set url = ""
            Try {
                Set links = {}.%FromJSON(got.body).link.%GetIterator()
                While links.%GetNext(, .link) {
                    Set:link.relation="next" url = link.url
                }
            } Catch {
            }
            Set:$EXTRACT(url, 1, $LENGTH(..#BASE) + 1)=(..#BASE_"/") url = $EXTRACT(url, $LENGTH(..#BASE) + 2, *)
            Do vars.%Set(name, url)
        }
    }
}

ClassMethod Header(got As %DynamicObject, name As %String) As %String
{
    Set want = $ZCONVERT(name, "L")
    Set iter = got.headers.%GetIterator()
    While iter.%GetNext(.key, .value) {
        Return:$ZCONVERT(key, "L")=want value
    }
    Quit ""
}

/// What differs from the expectation, one line each; empty when the answer is as measured.
ClassMethod Check(expect As %DynamicObject, got As %DynamicObject, vars As %DynamicObject) As %DynamicArray
{
    Set problems = []
    If expect.%IsDefined("status") && (got.status '= expect.status) {
        Do problems.%Push("status " _ got.status _ ", expected " _ expect.status _ ": " _ $EXTRACT(got.body, 1, 300))
    }
    If expect.%IsDefined("headers") {
        Set iter = expect.headers.%GetIterator()
        While iter.%GetNext(.name, .want) {
            Set actual = ..Header(got, name)
            If $ISOBJECT(want) {
                Do:want.absent&&(actual'="") problems.%Push(name _ " is " _ actual _ ", expected none")
                Do:want.present&&(actual="") problems.%Push(name _ " is missing")
                If want.%IsDefined("endswith") {
                    Set end = ..Subst(want.endswith, vars)
                    Do:$EXTRACT(actual, *-$LENGTH(end)+1, *)'=end problems.%Push(name _ " is " _ actual _ ", expected it to end " _ end)
                }
            } ElseIf name = "Content-Type" {
                Do:$ZCONVERT($ZSTRIP($PIECE(actual, ";", 1), "<>W"), "L")'=$ZCONVERT(want, "L") problems.%Push(name _ " is " _ actual _ ", expected " _ want)
            } Else {
                Do:actual'=..Subst(want, vars) problems.%Push(name _ " is " _ actual _ ", expected " _ ..Subst(want, vars))
            }
        }
    }
    Quit:'expect.%IsDefined("body") problems
    Do ..CheckBody(expect.body, got.body, vars, problems)
    Quit problems
}

ClassMethod CheckBody(want As %DynamicObject, raw As %String, vars As %DynamicObject, problems As %DynamicArray)
{
    If want.empty && (raw '= "") Do problems.%Push("the body is not empty: " _ $EXTRACT(raw, 1, 200))
    If want.%IsDefined("contains") {
        Set iter = want.contains.%GetIterator()
        While iter.%GetNext(, .text) {
            Set text = ..Subst(text, vars)
            Do:raw'[text problems.%Push("the body does not contain " _ text _ ": " _ $EXTRACT(raw, 1, 600))
        }
    }
    If want.%IsDefined("same_as") && (raw '= vars.%Get(want.%Get("same_as"))) {
        Do problems.%Push("the body differs from " _ want.%Get("same_as") _ ": " _ $EXTRACT(raw, 1, 300))
    }
    Set needsJson = 0
    For key = "outcome", "has", "absent", "keys", "resource", "bundle", "capability" {
        Set:want.%IsDefined(key) needsJson = 1
    }
    Quit:'needsJson
    Set json = ""
    Try {
        Set json = {}.%FromJSON(raw)
    } Catch {
        Set json = ""
    }
    If '$ISOBJECT(json) {
        Do problems.%Push("the body is not JSON: " _ $EXTRACT(raw, 1, 200))
        Quit
    }
    If want.%IsDefined("outcome") {
        Set issue = ..Walk(json, "issue[0]", .found)
        If 'found {
            Do problems.%Push("no OperationOutcome issue: " _ $EXTRACT(raw, 1, 200))
        } Else {
            Set iter = want.outcome.%GetIterator()
            While iter.%GetNext(.key, .value) {
                If key = "text" {
                    Set actual = ..Walk(issue, "details.text")
                } ElseIf key = "expression" {
                    Set actual = ..Canon(..Walk(issue, "expression"))
                    Set value = ..Canon(value, vars)
                } Else {
                    Set actual = issue.%Get(key)
                }
                Set:'$ISOBJECT(value) value = ..Subst(value, vars)
                Do:actual'=value problems.%Push("issue " _ key _ " is " _ actual _ ", expected " _ value)
            }
        }
    }
    If want.%IsDefined("has") {
        Set iter = want.has.%GetIterator()
        While iter.%GetNext(.path, .value) {
            Set actual = ..Walk(json, path, .found)
            If 'found {
                Do problems.%Push(path _ " is missing")
            } ElseIf $ISOBJECT(value) {
                Do:..Canon(actual)'=..Canon(value, vars) problems.%Push(path _ " is " _ ..Canon(actual) _ ", expected " _ ..Canon(value, vars))
            } ElseIf $ISOBJECT(actual) || (actual '= ..Subst(value, vars)) {
                Do problems.%Push(path _ " is " _ $SELECT($ISOBJECT(actual): ..Canon(actual), 1: actual) _ ", expected " _ ..Subst(value, vars))
            }
        }
    }
    If want.%IsDefined("absent") {
        Set iter = want.absent.%GetIterator()
        While iter.%GetNext(, .path) {
            Do ..Walk(json, path, .found)
            Do:found problems.%Push(path _ " is present")
        }
    }
    If want.%IsDefined("keys") {
        Set actual = ..Keys(json), expected = ..Join(want.keys)
        Do:actual'=expected problems.%Push("the keys are " _ actual _ ", expected " _ expected)
    }
    If want.%IsDefined("resource") {
        Set meta = json.%Get("meta")
        Do:$ISOBJECT(meta)&&meta.%IsDefined("lastUpdated") meta.%Set("lastUpdated", "*")
        Set actual = json.%ToJSON(), expected = ..Canon(want.resource, vars)
        Do:actual'=expected problems.%Push("the resource is " _ actual _ ", expected " _ expected)
    }
    Do:want.%IsDefined("bundle") ..CheckBundle(want.bundle, json, vars, problems)
    If want.%IsDefined("capability") {
        Set iter = want.capability.%GetIterator()
        While iter.%GetNext(.type, .fields) {
            Set entry = ""
            Set resources = ..Walk(json, "rest[0].resource")
            If $ISOBJECT(resources) {
                Set each = resources.%GetIterator()
                While each.%GetNext(, .r) {
                    Set:r.type=type entry = r
                }
            }
            If '$ISOBJECT(entry) {
                Do problems.%Push("the CapabilityStatement has no " _ type)
                Continue
            }
            Set f = fields.%GetIterator()
            While f.%GetNext(.name, .value) {
                If name = "interaction" {
                    Set codes = []
                    Set list = entry.%Get("interaction")
                    If $ISOBJECT(list) {
                        Set c = list.%GetIterator()
                        While c.%GetNext(, .i) {
                            Do codes.%Push(i.code)
                        }
                    }
                    Do:..Join(codes)'=..Join(value) problems.%Push(type _ " interaction is " _ ..Join(codes) _ ", expected " _ ..Join(value))
                } Else {
                    Do:(entry.%Get(name)_"")'=(value_"") problems.%Push(type _ " " _ name _ " is " _ entry.%Get(name) _ ", expected " _ value)
                }
            }
        }
    }
}

ClassMethod CheckBundle(want As %DynamicObject, json As %DynamicObject, vars As %DynamicObject, problems As %DynamicArray)
{
    Do:want.%IsDefined("type")&&(json.type'=want.type) problems.%Push("Bundle type " _ json.type _ ", expected " _ want.type)
    Do:want.%IsDefined("total")&&(json.total'=want.total) problems.%Push("Bundle total " _ json.total _ ", expected " _ want.total)
    Set entries = $SELECT($ISOBJECT(json.entry): json.entry, 1: [])
    Do:want.%IsDefined("count")&&(entries.%Size()'=want.count) problems.%Push("Bundle has " _ entries.%Size() _ " entries, expected " _ want.count)
    If want.%IsDefined("links") {
        Set relations = []
        If $ISOBJECT(json.link) {
            Set iter = json.link.%GetIterator()
            While iter.%GetNext(, .link) {
                Do relations.%Push(link.relation)
            }
        }
        Do:..Join(relations)'=..Join(want.links) problems.%Push("Bundle links " _ ..Join(relations) _ ", expected " _ ..Join(want.links))
    }
    Quit:'want.%IsDefined("entries")
    Set iter = want.entries.%GetIterator()
    While iter.%GetNext(.i, .w) {
        Set entry = entries.%Get(i)
        If '$ISOBJECT(entry) {
            Do problems.%Push("entry " _ i _ " is missing")
            Continue
        }
        Set f = w.%GetIterator()
        While f.%GetNext(.name, .value) {
            If name = "id" {
                Set actual = ..Walk(entry, "resource.id")
            } ElseIf name = "versionId" {
                Set actual = ..Walk(entry, "resource.meta.versionId")
            } ElseIf name = "method" {
                Set actual = ..Walk(entry, "request.method")
            } ElseIf name = "url" {
                Set actual = ..Walk(entry, "request.url")
            } ElseIf name = "status" {
                Set actual = ..Walk(entry, "response.status")
            } ElseIf name = "mode" {
                Set actual = ..Walk(entry, "search.mode")
            } ElseIf name = "etag" {
                Set actual = $ISOBJECT(entry.response) && entry.response.%IsDefined("etag")
            } ElseIf name = "tags" {
                Set actual = ..Tags(entry)
            } ElseIf (name = "resource") || (name = "fullUrl") {
                Set actual = entry.%IsDefined(name)
            } Else {
                Set actual = "?"
            }
            If name = "tags" {
                Set value = ..Join(value)
            } ElseIf '$ISOBJECT(value) {
                Set value = ..Subst(value, vars)
            }
            Do:(actual_"")'=(value_"") problems.%Push("entry " _ i _ " " _ name _ " is " _ actual _ ", expected " _ value)
        }
    }
}

ClassMethod Tags(entry As %DynamicObject) As %String
{
    Set out = [], tags = ..Walk(entry, "resource.meta.tag")
    If $ISOBJECT(tags) {
        Set iter = tags.%GetIterator()
        While iter.%GetNext(, .tag) {
            Do out.%Push(tag.system _ "|" _ tag.code)
        }
    }
    Quit ..Join(out)
}

/// The value at a path such as <code>meta.tag[0].code</code>, and whether it is there.
ClassMethod Walk(json, path As %String, Output found As %Boolean) As %String
{
    Set found = 0, here = json
    For i = 1:1:$LENGTH(path, ".") {
        Set part = $PIECE(path, ".", i), name = $PIECE(part, "["), index = $SELECT(part [ "[": +$PIECE(part, "[", 2), 1: "")
        Return:'$ISOBJECT(here) ""
        If name '= "" {
            Return:'here.%IsA("%Library.DynamicObject") ""
            Return:'here.%IsDefined(name) ""
            Set here = here.%Get(name)
        }
        If index '= "" {
            Return:'$ISOBJECT(here) ""
            Return:'here.%IsA("%Library.DynamicArray") ""
            Return:index>=here.%Size() ""
            Set here = here.%Get(index)
        }
    }
    Set found = 1
    Quit here
}

/// A JSON value as text, after the run's substitutions when <var>vars</var> is given.
ClassMethod Canon(value, vars As %DynamicObject = "") As %String
{
    Quit:'$ISOBJECT(value) value
    Set text = value.%ToJSON()
    Quit:'$ISOBJECT(vars) text
    Set text = ..Subst(text, vars)
    Quit $SELECT(value.%IsA("%Library.DynamicArray"): [].%FromJSON(text).%ToJSON(), 1: {}.%FromJSON(text).%ToJSON())
}

ClassMethod Keys(json As %DynamicObject) As %String
{
    Set out = []
    Set iter = json.%GetIterator()
    While iter.%GetNext(.key) {
        Do out.%Push(key)
    }
    Quit ..Join(out)
}

ClassMethod Join(list As %DynamicArray) As %String
{
    Set out = ""
    Quit:'$ISOBJECT(list) ""
    Set iter = list.%GetIterator()
    While iter.%GetNext(, .item) {
        Set out = out _ $SELECT(out = "": "", 1: ",") _ item
    }
    Quit out
}

XData Cases [ MimeType = application/json ]
{
{"version":1,"about":"Exchanges with a FHIR R4 server, in order, from a store holding none of the ids they use. Each was measured on IRIS for Health's own FHIR server (JsonAdvSQL, R4 core); targets says which servers a runner sends it to: the test FHIR server (facade), IRIS (iris), or both. {p} in a path, header or body is the run's id prefix and {P} the same in capitals (empty for the test server after its reset); {v:name}, {body:name} and {link:name} are values captured by an earlier exchange.","measured_on":["IRIS for Health 2026.2 Build 221U","IRIS for Health 2026.3.0AI Build 154U","IRIS for Health 2027.1.0AI Build 109U"],"exchanges":[
{"id":"seed-location-a","targets":["facade","iris"],"request":{"method":"PUT","path":"Location/{p}ward-a","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Location\",\"id\":\"{p}ward-a\",\"identifier\":[{\"system\":\"urn:shutter:ward\",\"value\":\"WARD-A\"}],\"status\":\"active\",\"name\":\"Ward A\"}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"seed-location-b","targets":["facade","iris"],"request":{"method":"PUT","path":"Location/{p}ward-b","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Location\",\"id\":\"{p}ward-b\",\"identifier\":[{\"system\":\"urn:shutter:ward\",\"value\":\"WARD-B\"}],\"status\":\"active\",\"name\":\"Ward B\"}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"seed-patient","targets":["facade","iris"],"request":{"method":"PUT","path":"Patient/{p}demo-p1","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Patient\",\"id\":\"{p}demo-p1\",\"identifier\":[{\"system\":\"https://fhir.nhs.uk/Id/nhs-number\",\"value\":\"{p}9990000001\"}],\"active\":true}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"seed-encounter","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true},"Location":{"endswith":"/Encounter/{p}enc-1/_history/1"}},"body":{"empty":true}}},
{"id":"m1-read","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-1","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"1\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-1/_history/1"},"Last-Modified":{"present":true}},"body":{"has":{"meta.versionId":"1"},"keys":["resourceType","id","status","identifier","class","subject","location","meta"]}}},
{"id":"m1-update-representation","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"1\"","Prefer":"return=representation"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":200,"headers":{"ETag":"W/\"2\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-1/_history/2"},"Last-Modified":{"present":true}},"body":{"has":{"meta.versionId":"2"}}}},
{"id":"m1-vread-2","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-1/_history/2","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"2\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-1/_history/2"},"Last-Modified":{"present":true}},"body":{"has":{"meta.versionId":"2"}}}},
{"id":"m1-vread-1","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-1/_history/1","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"1\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-1/_history/1"},"Last-Modified":{"present":true}},"body":{"has":{"meta.versionId":"1"}}}},
{"id":"m1-history","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-1/_history","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"history","total":2,"count":2,"links":["self"],"entries":[{"versionId":"2","method":"PUT","url":"Encounter/{p}enc-1","status":"200","resource":true,"fullUrl":false,"etag":false},{"versionId":"1","method":"PUT","url":"Encounter/{p}enc-1","status":"200","resource":true,"fullUrl":false,"etag":false}]}}}},
{"id":"m1-if-match-quoted","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json","If-Match":"\"2\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":405,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"invalid","diagnostics":"<HSFHIRErr>InvalidIfMatch","text":"Invalid 'If-Match' header, '\"2\"', must be formatted as 'W/\"[versionId]\"'"}}}},
{"id":"m1-if-match-bare","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json","If-Match":"2"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":405,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"invalid","diagnostics":"<HSFHIRErr>InvalidIfMatch","text":"Invalid 'If-Match' header, '2', must be formatted as 'W/\"[versionId]\"'"}}}},
{"id":"m1-if-match-weak-no-quotes","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json","If-Match":"W/2"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":405,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"invalid","diagnostics":"<HSFHIRErr>InvalidIfMatch","text":"Invalid 'If-Match' header, 'W/2', must be formatted as 'W/\"[versionId]\"'"}}}},
{"id":"m1-if-match-lower-w","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json","If-Match":"w/\"2\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":405,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"invalid","diagnostics":"<HSFHIRErr>InvalidIfMatch","text":"Invalid 'If-Match' header, 'w/\"2\"', must be formatted as 'W/\"[versionId]\"'"}}}},
{"id":"m1-if-match-star","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json","If-Match":"*"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":405,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"invalid","diagnostics":"<HSFHIRErr>InvalidIfMatch","text":"Invalid 'If-Match' header, '*', must be formatted as 'W/\"[versionId]\"'"}}}},
{"id":"m1-read-after-forms","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-1","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"2\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-1/_history/2"},"Last-Modified":{"present":true}},"body":{"has":{"meta.versionId":"2"}}},"note":"none of the five malformed forms wrote a version"},
{"id":"m3-update-current","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"2\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":200,"headers":{"ETag":"W/\"3\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m3-update-stale","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"2\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":412,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"concurrency","diagnostics":"<HSFHIRErr>IfMatchViolation","text":"The version in the 'If-Match' header, '2', does not match the current version, '3'"}}}},
{"id":"m3-update-future","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"99\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":412,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"concurrency","diagnostics":"<HSFHIRErr>IfMatchViolation","text":"The version in the 'If-Match' header, '99', does not match the current version, '3'"}}}},
{"id":"m3-read-unchanged","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-1","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"3\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-1/_history/3"},"Last-Modified":{"present":true}},"body":{"has":{"meta.versionId":"3"}}}},
{"id":"m4-update-without-if-match","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":200,"headers":{"ETag":"W/\"4\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m5-if-match-unknown-id","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-unknown-1","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"1\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-unknown-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1999\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":412,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"concurrency","diagnostics":"<HSFHIRErr>IfMatchViolation","text":"The version in the 'If-Match' header, '1', does not match the current version, ''"}}}},
{"id":"m5-read-unknown-id","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-unknown-1","headers":{}},"expect":{"status":404,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"not-found","diagnostics":"<HSFHIRErr>ResourceNotFound","text":"No resource with type 'Encounter' and id '{p}enc-unknown-1'"}}}},
{"id":"m5-update-as-create","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-unknown-2","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-unknown-2\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1998\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m6-create","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-del","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-del\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1003\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m6-delete","targets":["facade","iris"],"request":{"method":"DELETE","path":"Encounter/{p}enc-del","headers":{}},"expect":{"status":204,"headers":{"ETag":"W/\"2\""},"body":{"empty":true}}},
{"id":"m6-read-deleted","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-del","headers":{}},"expect":{"status":410,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"exception","diagnostics":"<HSFHIRErr>ResourceWasDeleted","text":"Resource was previously deleted (type='Encounter', id='{p}enc-del', version='')."}}}},
{"id":"m6-vread-before-delete","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-del/_history/1","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"1\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-del/_history/1"},"Last-Modified":{"present":true}},"body":{"has":{"meta.versionId":"1"}}}},
{"id":"m6-vread-the-delete","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-del/_history/2","headers":{}},"expect":{"status":410,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"exception","diagnostics":"<HSFHIRErr>ResourceWasDeleted","text":"Resource was previously deleted (type='Encounter', id='{p}enc-del', version='2')."}}}},
{"id":"m6-history-deleted","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-del/_history","headers":{}},"expect":{"status":200,"headers":{"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"history","total":2,"count":2,"links":["self"],"entries":[{"method":"DELETE","url":"Encounter/{p}enc-del","status":"200","resource":false},{"versionId":"1","method":"PUT","resource":true}]}}}},
{"id":"m6-update-pre-delete-etag","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-del","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"1\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-del\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1003\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":412,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"concurrency","diagnostics":"<HSFHIRErr>IfMatchViolation","text":"The version in the 'If-Match' header, '1', does not match the current version, '2'"}}}},
{"id":"m6-update-with-the-delete-etag","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-del","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"2\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-del\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1003\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":200,"headers":{"ETag":"W/\"3\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}},"note":"brought back as an update, not a 201"},
{"id":"m6-read-resurrected","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-del","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"3\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-del/_history/3"},"Last-Modified":{"present":true}},"body":{"has":{"meta.versionId":"3"}}}},
{"id":"m7-create-with-client-meta","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-rich","headers":{"Content-Type":"application/fhir+json","Prefer":"return=representation"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-rich\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1004\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\",\"display\":\"Ward A\"},\"status\":\"completed\",\"period\":{\"start\":\"2026-11-07T08:00:00+00:00\",\"end\":\"2026-11-07T09:00:00.000Z\"}},{\"location\":{\"reference\":\"Location/{p}ward-b\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}],\"meta\":{\"tag\":[{\"system\":\"urn:example:other\",\"code\":\"keep-me\"}],\"security\":[{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-Confidentiality\",\"code\":\"N\"}],\"profile\":[\"http://example.org/StructureDefinition/enc\"],\"source\":\"urn:example:src\",\"versionId\":\"77\",\"lastUpdated\":\"2001-01-01T00:00:00Z\"},\"extension\":[{\"url\":\"http://example.org/ext/a\",\"valueString\":\"x\"}],\"period\":{\"start\":\"2026-11-07T08:00:00Z\"},\"serviceType\":{\"coding\":[{\"system\":\"urn:example:st\",\"code\":\"GEN\"}],\"text\":\"General\"},\"priority\":{\"coding\":[{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActPriority\",\"code\":\"R\"}]},\"reasonCode\":[{\"text\":\"reason \u00e9 \u2192 unicode\"}],\"length\":{\"value\":1.5,\"unit\":\"h\"},\"hospitalization\":{\"admitSource\":{\"text\":\"GP\"}}}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"application/fhir+json"},"body":{"resource":{"resourceType":"Encounter","id":"{p}enc-rich","status":"in-progress","identifier":[{"system":"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49","value":"{p}V1004"}],"class":{"system":"http://terminology.hl7.org/CodeSystem/v3-ActCode","code":"IMP"},"subject":{"reference":"Patient/{p}demo-p1"},"location":[{"location":{"reference":"Location/{p}ward-a","display":"Ward A"},"status":"completed","period":{"start":"2026-11-07T08:00:00+00:00","end":"2026-11-07T09:00:00.000Z"}},{"location":{"reference":"Location/{p}ward-b"},"status":"active","period":{"start":"2026-11-07T09:00:00Z"}}],"meta":{"tag":[{"system":"urn:example:other","code":"keep-me"}],"security":[{"system":"http://terminology.hl7.org/CodeSystem/v3-Confidentiality","code":"N"}],"profile":["http://example.org/StructureDefinition/enc"],"source":"urn:example:src","versionId":"1","lastUpdated":"*"},"extension":[{"url":"http://example.org/ext/a","valueString":"x"}],"period":{"start":"2026-11-07T08:00:00Z"},"serviceType":{"coding":[{"system":"urn:example:st","code":"GEN"}],"text":"General"},"priority":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ActPriority","code":"R"}]},"reasonCode":[{"text":"reason \u00e9 \u2192 unicode"}],"length":{"value":1.5,"unit":"h"},"hospitalization":{"admitSource":{"text":"GP"}}}}},"note":"the client's versionId 77 and lastUpdated 2001 are overwritten silently, in place; nothing else changes"},
{"id":"m7-unchanged-put","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-rich","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"1\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-rich\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1004\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\",\"display\":\"Ward A\"},\"status\":\"completed\",\"period\":{\"start\":\"2026-11-07T08:00:00+00:00\",\"end\":\"2026-11-07T09:00:00.000Z\"}},{\"location\":{\"reference\":\"Location/{p}ward-b\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}],\"meta\":{\"tag\":[{\"system\":\"urn:example:other\",\"code\":\"keep-me\"}],\"security\":[{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-Confidentiality\",\"code\":\"N\"}],\"profile\":[\"http://example.org/StructureDefinition/enc\"],\"source\":\"urn:example:src\",\"versionId\":\"1\",\"lastUpdated\":\"2026-11-08T02:31:53Z\"},\"extension\":[{\"url\":\"http://example.org/ext/a\",\"valueString\":\"x\"}],\"period\":{\"start\":\"2026-11-07T08:00:00Z\"},\"serviceType\":{\"coding\":[{\"system\":\"urn:example:st\",\"code\":\"GEN\"}],\"text\":\"General\"},\"priority\":{\"coding\":[{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActPriority\",\"code\":\"R\"}]},\"reasonCode\":[{\"text\":\"reason \u00e9 \u2192 unicode\"}],\"length\":{\"value\":1.5,\"unit\":\"h\"},\"hospitalization\":{\"admitSource\":{\"text\":\"GP\"}}}"},"expect":{"status":200,"headers":{"ETag":"W/\"2\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m7-vread-unchanged","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-rich/_history/2","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"2\"","Content-Type":"application/fhir+json"},"body":{"resource":{"resourceType":"Encounter","id":"{p}enc-rich","status":"in-progress","identifier":[{"system":"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49","value":"{p}V1004"}],"class":{"system":"http://terminology.hl7.org/CodeSystem/v3-ActCode","code":"IMP"},"subject":{"reference":"Patient/{p}demo-p1"},"location":[{"location":{"reference":"Location/{p}ward-a","display":"Ward A"},"status":"completed","period":{"start":"2026-11-07T08:00:00+00:00","end":"2026-11-07T09:00:00.000Z"}},{"location":{"reference":"Location/{p}ward-b"},"status":"active","period":{"start":"2026-11-07T09:00:00Z"}}],"meta":{"tag":[{"system":"urn:example:other","code":"keep-me"}],"security":[{"system":"http://terminology.hl7.org/CodeSystem/v3-Confidentiality","code":"N"}],"profile":["http://example.org/StructureDefinition/enc"],"source":"urn:example:src","versionId":"2","lastUpdated":"*"},"extension":[{"url":"http://example.org/ext/a","valueString":"x"}],"period":{"start":"2026-11-07T08:00:00Z"},"serviceType":{"coding":[{"system":"urn:example:st","code":"GEN"}],"text":"General"},"priority":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ActPriority","code":"R"}]},"reasonCode":[{"text":"reason \u00e9 \u2192 unicode"}],"length":{"value":1.5,"unit":"h"},"hospitalization":{"admitSource":{"text":"GP"}}}}},"note":"differs from what was sent only in meta.versionId and meta.lastUpdated"},
{"id":"m7-create-raw-text","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-raw","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\" : \"Encounter\", \"id\" : \"{p}enc-raw\", \"status\" : \"in-progress\", \"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1020\"}], \"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"}, \"subject\":{\"reference\":\"Patient/{p}demo-p1\"}, \"length\" : {\"value\" : 1.50, \"unit\" : \"h\"}, \"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\" : \"2026-11-07T10:00:00.000+00:00\"}}], \"priority\":{\"text\":\"x\"}, \"extension\":[{\"url\":\"http://example.org/ext/d\",\"valueDecimal\":1.0E2}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m7-read-raw-text","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-raw","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"1\""},"body":{"contains":["\"length\":{\"value\":1.50,\"unit\":\"h\"}","\"start\":\"2026-11-07T10:00:00.000+00:00\"","\"extension\":[{\"url\":\"http://example.org/ext/d\",\"valueDecimal\":1.0E2}],\"meta\":{\"lastUpdated\":\""],"keys":["resourceType","id","status","identifier","class","subject","length","location","priority","extension","meta"]}},"note":"decimal text, datetime precision and offset kept, whitespace removed, meta appended at the end"},
{"id":"m8-create","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-tag","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-tag\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1005\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"completed\",\"period\":{\"start\":\"2026-11-07T10:00:00Z\",\"end\":\"2026-11-07T11:00:00Z\"}},{\"location\":{\"reference\":\"Location/{p}ward-b\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T11:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m8-read-1","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-tag","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"1\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-tag/_history/1"},"Last-Modified":{"present":true}},"body":{"absent":["meta.tag"]}},"capture":{"body:tag1":"body"}},
{"id":"m8-put-marker","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-tag","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"1\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-tag\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1005\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"completed\",\"period\":{\"start\":\"2026-11-07T10:00:00Z\",\"end\":\"2026-11-07T11:00:00Z\"}},{\"location\":{\"reference\":\"Location/{p}ward-b\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T11:00:00Z\"}}],\"meta\":{\"lastUpdated\":\"2026-11-08T02:31:53Z\",\"versionId\":\"1\",\"tag\":[{\"system\":\"urn:shutter:recovery\",\"code\":\"op-3f9a\"}]}}"},"expect":{"status":200,"headers":{"ETag":"W/\"2\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m8-read-marked","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-tag","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"2\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-tag/_history/2"},"Last-Modified":{"present":true}},"body":{"has":{"meta.tag":[{"system":"urn:shutter:recovery","code":"op-3f9a"}]}}}},
{"id":"m8-put-meta-without-tag","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-tag","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"2\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-tag\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1005\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"completed\",\"period\":{\"start\":\"2026-11-07T10:00:00Z\",\"end\":\"2026-11-07T11:00:00Z\"}},{\"location\":{\"reference\":\"Location/{p}ward-b\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T11:00:00Z\"}}],\"meta\":{\"lastUpdated\":\"2026-11-08T02:31:53Z\",\"versionId\":\"2\"},\"priority\":{\"text\":\"later writer\"}}"},"expect":{"status":200,"headers":{"ETag":"W/\"3\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m8-read-tag-gone","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-tag","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"3\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-tag/_history/3"},"Last-Modified":{"present":true}},"body":{"absent":["meta.tag"]}},"note":"no carry-over"},
{"id":"m8-put-no-meta","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-tag","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"3\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-tag\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1005\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"completed\",\"period\":{\"start\":\"2026-11-07T10:00:00Z\",\"end\":\"2026-11-07T11:00:00Z\"}},{\"location\":{\"reference\":\"Location/{p}ward-b\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T11:00:00Z\"}}],\"priority\":{\"text\":\"writer without meta\"}}"},"expect":{"status":200,"headers":{"ETag":"W/\"4\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m8-put-other-tag","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-tag","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"4\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-tag\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1005\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"completed\",\"period\":{\"start\":\"2026-11-07T10:00:00Z\",\"end\":\"2026-11-07T11:00:00Z\"}},{\"location\":{\"reference\":\"Location/{p}ward-b\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T11:00:00Z\"}}],\"meta\":{\"lastUpdated\":\"2026-11-08T02:31:53Z\",\"versionId\":\"4\",\"tag\":[{\"system\":\"urn:example:other\",\"code\":\"x\"}]},\"priority\":{\"text\":\"writer without meta\"}}"},"expect":{"status":200,"headers":{"ETag":"W/\"5\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m8-history-tags","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-tag/_history","headers":{}},"expect":{"status":200,"body":{"bundle":{"type":"history","total":5,"count":5,"links":["self"],"entries":[{"versionId":"5","tags":["urn:example:other|x"]},{"versionId":"4","tags":[]},{"versionId":"3","tags":[]},{"versionId":"2","tags":["urn:shutter:recovery|op-3f9a"]},{"versionId":"1","tags":[]}]}}},"note":"the marker stays only on the version that sent it"},
{"id":"m8-meta-operation","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-tag/$meta","headers":{}},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"not-supported","diagnostics":"<HSFHIRErr>OperationNotSupported","text":"The operation 'meta' is not supported for the 'Instance' scope."}}}},
{"id":"m11-vread-1-after-four-updates","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-tag/_history/1","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"1\""},"body":{"same_as":"body:tag1"}},"note":"byte-identical to the read of version 1 before the updates"},
{"id":"m9-type-history","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/_history","headers":{}},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"not-supported","diagnostics":"<HSFHIRErr>InteractionNotSupported","text":"Interaction 'history-type' is not supported for resource type 'Encounter'."}}},"note":"as 154 and 109 answer; 2026.2 says InteractionsNotSupported"},
{"id":"m9-system-history","targets":["facade","iris"],"request":{"method":"GET","path":"_history","headers":{}},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"not-supported","diagnostics":"<HSFHIRErr>SystemInteractionNotSupported","text":"FHIR system-level 'history-system' interaction not supported on this end point"}}},"note":"as 154 and 109 answer; 2026.2 answers 500"},
{"id":"m10-create","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-many","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-many\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1006\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m10-update-2","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-many","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"1\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-many\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1006\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":200,"headers":{"ETag":"W/\"2\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m10-update-3","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-many","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"2\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-many\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1006\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":200,"headers":{"ETag":"W/\"3\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m10-update-4","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-many","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"3\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-many\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1006\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":200,"headers":{"ETag":"W/\"4\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m10-update-5","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-many","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"4\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-many\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1006\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":200,"headers":{"ETag":"W/\"5\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m10-history-count-ignored","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-many/_history?_count=2","headers":{}},"expect":{"status":200,"body":{"bundle":{"type":"history","total":5,"count":5,"links":["self"],"entries":[{"versionId":"5"},{"versionId":"4"},{"versionId":"3"},{"versionId":"2"},{"versionId":"1"}]}}},"note":"a positive _count is ignored: the whole history, newest first, no next link"},
{"id":"m10-history-count-zero","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-many/_history?_count=0","headers":{}},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"warning","code":"value","diagnostics":"<HSFHIRErr>InvalidParameterValue","text":"The value '0' is invalid for the '_count' parameter'."}}}},
{"id":"m10-history-count-text","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-many/_history?_count=abc","headers":{}},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"warning","code":"value","diagnostics":"<HSFHIRErr>InvalidParameterValue","text":"The value 'abc' is invalid for the '_count' parameter'."}}}},
{"id":"m10-history-since","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-many/_history?_since=2000-01-01T00:00:00Z","headers":{}},"expect":{"status":200,"body":{"bundle":{"type":"history","total":5,"count":5,"links":["self"]}}}},
{"id":"m12-prefer-minimal","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-many","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"5\"","Prefer":"return=minimal"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-many\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1006\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":200,"headers":{"ETag":"W/\"6\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m12-prefer-outcome","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-many","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"6\"","Prefer":"return=OperationOutcome"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-many\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1006\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":200,"headers":{"ETag":"W/\"7\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m12-prefer-representation","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-many","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"7\"","Prefer":"return=representation"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-many\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1006\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":200,"headers":{"ETag":"W/\"8\"","Content-Type":"application/fhir+json"},"body":{"has":{"meta.versionId":"8","id":"{p}enc-many"}}}},
{"id":"m12-stale-minimal","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-many","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"1\"","Prefer":"return=minimal"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-many\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1006\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":412,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"concurrency","diagnostics":"<HSFHIRErr>IfMatchViolation","text":"The version in the 'If-Match' header, '1', does not match the current version, '8'"}}},"note":"a refusal carries the full OperationOutcome whatever Prefer says"},
{"id":"m13-summary-true","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-rich?_summary=true","headers":{}},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"invalid","diagnostics":"<HSFHIRErr>InvalidQueryParameterValue","text":"The value 'true' is invalid for query parameter '_summary'."}}}},
{"id":"m13-elements","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-rich?_elements=id,location","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"2\"","Content-Type":"application/fhir+json"},"body":{"keys":["resourceType","id","location","meta"],"has":{"meta":{"tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED","display":"Resource content reduced because _elements search parameter"}]},"location":[{"location":{"reference":"Location/{p}ward-a","display":"Ward A"},"status":"completed","period":{"start":"2026-11-07T08:00:00+00:00","end":"2026-11-07T09:00:00.000Z"}},{"location":{"reference":"Location/{p}ward-b"},"status":"active","period":{"start":"2026-11-07T09:00:00Z"}}]}}},"note":"meta holds only the SUBSETTED tag; the ETag is still sent"},
{"id":"m13-summary-data","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-rich?_summary=data","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"2\""},"body":{"has":{"meta.versionId":"2"},"absent":["meta.tag[1]"]}}},
{"id":"m14-create-dup-a","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-dup-a","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-dup-a\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V2000\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m14-create-dup-b","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-dup-b","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-dup-b\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V2000\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m14-create-case","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-case","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-case\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}AbC-77\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m14-create-other-system","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-other-sys","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-other-sys\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:example:other-system\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m14-create-run-a","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-run-a","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-run-a\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:example:run{p}\",\"value\":\"{p}A\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m14-create-run-b","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-run-b","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-run-b\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:example:run{p}\",\"value\":\"{p}B\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m14-search-exact","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49|{p}V1001","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":1,"count":1,"links":["self"],"entries":[{"id":"{p}enc-1","mode":"match","fullUrl":true}]}}}},
{"id":"m14-search-two","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49|{p}V2000","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":2,"count":2,"links":["self"],"entries":[{"id":"{p}enc-dup-a","mode":"match","fullUrl":true},{"id":"{p}enc-dup-b","mode":"match","fullUrl":true}]}}}},
{"id":"m14-search-none","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49|{p}V9999","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":0,"count":0,"links":["self"],"entries":[]}}}},
{"id":"m14-search-value-as-stored","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49|{p}AbC-77","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":1,"count":1,"links":["self"],"entries":[{"id":"{p}enc-case","mode":"match","fullUrl":true}]}}}},
{"id":"m14-search-value-lower","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49|{p}abc-77","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":1,"count":1,"links":["self"],"entries":[{"id":"{p}enc-case","mode":"match","fullUrl":true}]}}}},
{"id":"m14-search-value-upper","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49|{P}ABC-77","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":1,"count":1,"links":["self"],"entries":[{"id":"{p}enc-case","mode":"match","fullUrl":true}]}}}},
{"id":"m14-search-system-upper","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=URN:OID:2.16.840.1.113883.2.1.3.2.4.18.49|{p}V1001","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":0,"count":0,"links":["self"],"entries":[]}}}},
{"id":"m14-search-prefix","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49|{p}V100","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":0,"count":0,"links":["self"],"entries":[]}}}},
{"id":"m14-search-bare-value","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier={p}V1001","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":2,"count":2,"links":["self"],"entries":[{"id":"{p}enc-1","mode":"match","fullUrl":true},{"id":"{p}enc-other-sys","mode":"match","fullUrl":true}]}}}},
{"id":"m14-search-no-system","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=|{p}V1001","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":0,"count":0,"links":["self"],"entries":[]}}}},
{"id":"m14-search-every-value","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=urn:example:run{p}|","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":2,"count":2,"links":["self"],"entries":[{"id":"{p}enc-run-a","mode":"match","fullUrl":true},{"id":"{p}enc-run-b","mode":"match","fullUrl":true}]}}}},
{"id":"m14-search-other-system","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=urn:example:other-system|{p}V1001","headers":{}},"expect":{"status":200,"headers":{"ETag":{"absent":true},"Content-Type":"application/fhir+json"},"body":{"bundle":{"type":"searchset","total":1,"count":1,"links":["self"],"entries":[{"id":"{p}enc-other-sys","mode":"match","fullUrl":true}]}}}},
{"id":"m14-search-exact-modifier","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier:exact=urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49|{p}abc-77","headers":{}},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"not-supported","diagnostics":"<HSFHIRErr>UnsupportedParameterModifier","text":"Unsupported modifier 'exact' on param 'identifier"}}}},
{"id":"m10-search-pages","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter?identifier=urn:example:run{p}|&_count=1","headers":{}},"expect":{"status":200,"body":{"bundle":{"type":"searchset","total":2,"count":1,"links":["first","self","next","last"],"entries":[{"id":"{p}enc-run-a","mode":"match"}]}}},"capture":{"link:next":"link_next"},"note":"search pages, history does not"},
{"id":"m10-search-page-2","targets":["facade"],"request":{"method":"GET","path":"{link:next}","headers":{}},"expect":{"status":200,"body":{"bundle":{"type":"searchset","total":2,"count":1,"entries":[{"id":"{p}enc-run-b","mode":"match"}]}}},"note":"the second page's links were not measured on IRIS"},
{"id":"m15-create-locations","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-loc","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-loc\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1008\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-c\"},\"status\":\"completed\",\"period\":{\"start\":\"2026-11-07T07:00:00Z\",\"end\":\"2026-11-07T08:00:00Z\"}},{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"completed\",\"period\":{\"start\":\"2026-11-07T08:00:00Z\",\"end\":\"2026-11-07T09:00:00Z\"}},{\"location\":{\"reference\":\"Location/{p}ward-b\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00+01:00\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m15-read-locations","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-loc","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"1\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-loc/_history/1"},"Last-Modified":{"present":true}},"body":{"has":{"location":[{"location":{"reference":"Location/{p}ward-c"},"status":"completed","period":{"start":"2026-11-07T07:00:00Z","end":"2026-11-07T08:00:00Z"}},{"location":{"reference":"Location/{p}ward-a"},"status":"completed","period":{"start":"2026-11-07T08:00:00Z","end":"2026-11-07T09:00:00Z"}},{"location":{"reference":"Location/{p}ward-b"},"status":"active","period":{"start":"2026-11-07T09:00:00+01:00"}}]}}},"note":"stored as sent, in order, offsets kept"},
{"id":"m15-missing-location-reference","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-badref","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-badref\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1009\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}does-not-exist\"},\"status\":\"active\"}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m15-invalid-location-status","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-badstatus","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-badstatus\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1011\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"occupied\"}]}"},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"invalid","diagnostics":"<HSFHIRErr>ValueNotInEnumeration","text":"The value 'occupied' of Property 'status' of Type 'Encounter.location' must be one of (active,completed,planned,reserved)","expression":["Encounter.location[0].status"]}}}},
{"id":"m15-unknown-element","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-badelem","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-badelem\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1012\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\"}],\"notAnElement\":1}"},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"invalid","diagnostics":"<HSFHIRErr>UnexpectedPropertyName","text":"The property name 'notAnElement' is not valid for type 'Encounter'","expression":["Encounter"]}}}},
{"id":"m15-modifier-extension","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-modext","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-modext\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1013\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\"}],\"modifierExtension\":[{\"url\":\"http://example.org/mod\",\"valueBoolean\":true}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"m15-read-modifier-extension","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-modext","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"1\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-modext/_history/1"},"Last-Modified":{"present":true}},"body":{"has":{"modifierExtension":[{"url":"http://example.org/mod","valueBoolean":true}]}}}},
{"id":"m15-id-differs-from-url","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-idmismatch-url","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-idmismatch-body\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1014\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"invalid","diagnostics":"<HSFHIRErr>InvalidUpdateId","text":"The id in the updated resource is missing or does not match the requested Id"}}}},
{"id":"m15-no-id","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-noid","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1015\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"invalid","diagnostics":"<HSFHIRErr>InvalidUpdateId","text":"The id in the updated resource is missing or does not match the requested Id"}}}},
{"id":"narrative-create","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-narr","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-narr\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1016\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}],\"text\":{\"status\":\"generated\",\"div\":\"<div xmlns=\\\"http://www.w3.org/1999/xhtml\\\">In Ward A</div>\"}}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"narrative-move-text-unchanged","targets":["facade","iris"],"request":{"method":"PUT","path":"Encounter/{p}enc-narr","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"1\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-narr\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1016\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"completed\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\",\"end\":\"2026-11-07T11:00:00Z\"}},{\"location\":{\"reference\":\"Location/{p}ward-b\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T11:00:00Z\"}}],\"text\":{\"status\":\"generated\",\"div\":\"<div xmlns=\\\"http://www.w3.org/1999/xhtml\\\">In Ward A</div>\"}}"},"expect":{"status":200,"headers":{"ETag":"W/\"2\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}}},
{"id":"narrative-not-regenerated","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-narr","headers":{}},"expect":{"status":200,"headers":{"ETag":"W/\"2\"","Content-Type":"application/fhir+json","Location":{"endswith":"/Encounter/{p}enc-narr/_history/2"},"Last-Modified":{"present":true}},"body":{"has":{"text":{"status":"generated","div":"<div xmlns=\"http://www.w3.org/1999/xhtml\">In Ward A</div>"}}}}},
{"id":"narrative-never-added","targets":["facade","iris"],"request":{"method":"GET","path":"Encounter/{p}enc-1","headers":{}},"expect":{"status":200,"body":{"absent":["text"]}}},
{"id":"m2-capability","targets":["facade","iris"],"request":{"method":"GET","path":"metadata","headers":{}},"expect":{"status":200,"headers":{"Content-Type":"application/fhir+json"},"body":{"has":{"resourceType":"CapabilityStatement","fhirVersion":"4.0.1"},"capability":{"Encounter":{"versioning":"versioned-update","readHistory":true,"updateCreate":true,"conditionalUpdate":true,"interaction":["read","vread","create","update","patch","delete","history-instance","search-type"]},"Patient":{"versioning":"versioned-update","readHistory":true,"updateCreate":true,"conditionalUpdate":true,"interaction":["read","vread","create","update","patch","delete","history-instance","search-type"]},"Location":{"versioning":"versioned-update","readHistory":true,"updateCreate":true,"conditionalUpdate":true,"interaction":["read","vread","create","update","patch","delete","history-instance","search-type"]}}}}},
{"id":"facade-software","targets":["facade"],"request":{"method":"GET","path":"metadata","headers":{}},"expect":{"status":200,"body":{"has":{"software":{"name":"Shutter test FHIR server","version":"facade-v1"}}}},"note":"the test server never names an IRIS build"},
{"id":"facade-no-create-by-post","targets":["facade"],"request":{"method":"POST","path":"Encounter","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}ignored\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1017\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"not-supported","diagnostics":"<FacadeErr>NotImplemented","text":"Create by POST is not implemented by the test FHIR server"}}}},
{"id":"facade-no-conditional-update","targets":["facade"],"request":{"method":"PUT","path":"Encounter?identifier=urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49|{p}V3000","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}ignored\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V3000\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"not-supported","diagnostics":"<FacadeErr>NotImplemented","text":"A conditional PUT is not implemented by the test FHIR server"}}}},
{"id":"facade-no-other-types","targets":["facade"],"request":{"method":"GET","path":"Observation/x","headers":{}},"expect":{"status":400,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"not-supported","diagnostics":"<FacadeErr>NotImplemented","text":"The resource type 'Observation' is not implemented by the test FHIR server"}}}},
{"id":"iris-conditional-update-no-match","targets":["iris"],"request":{"method":"PUT","path":"Encounter?identifier=urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49|{p}V3000","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V3000\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201},"note":"conditional update is a different interaction; the test server does not offer it"},
{"id":"m17-reset","targets":["facade"],"request":{"method":"RESET","path":"","headers":{}},"expect":{"status":200}},
{"id":"m17-pre-reset-etag","targets":["facade"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json","If-Match":"W/\"4\""},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":412,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"concurrency","diagnostics":"<HSFHIRErr>IfMatchViolation","text":"The version in the 'If-Match' header, '4', does not match the current version, ''"}}}},
{"id":"m17-read-after-reset","targets":["facade"],"request":{"method":"GET","path":"Encounter/{p}enc-1","headers":{}},"expect":{"status":404,"headers":{"Content-Type":"application/fhir+json","ETag":{"absent":true}},"body":{"outcome":{"severity":"error","code":"not-found","diagnostics":"<HSFHIRErr>ResourceNotFound","text":"No resource with type 'Encounter' and id '{p}enc-1'"}}}},
{"id":"m17-versions-restart","targets":["facade"],"request":{"method":"PUT","path":"Encounter/{p}enc-1","headers":{"Content-Type":"application/fhir+json"},"body":"{\"resourceType\":\"Encounter\",\"id\":\"{p}enc-1\",\"status\":\"in-progress\",\"identifier\":[{\"system\":\"urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49\",\"value\":\"{p}V1001\"}],\"class\":{\"system\":\"http://terminology.hl7.org/CodeSystem/v3-ActCode\",\"code\":\"IMP\"},\"subject\":{\"reference\":\"Patient/{p}demo-p1\"},\"location\":[{\"location\":{\"reference\":\"Location/{p}ward-a\"},\"status\":\"active\",\"period\":{\"start\":\"2026-11-07T09:00:00Z\"}}]}"},"expect":{"status":201,"headers":{"ETag":"W/\"1\"","Content-Type":"text/html","Last-Modified":{"present":true}},"body":{"empty":true}},"note":"an id written again after a reset starts at W/\"1\": an old ETag can match a new incarnation"}
]}
}

}
