/// A FHIR R4 receiver's entry in the site profile (Shutter.FHIR.Profile and the readers of Shutter.Store.SiteProfile).
/// XData Entry is the entry as a site writes it; every row of XData Rows patches it (merged as Shutter.Test.SiteProfile
/// merges a patch: null removes a field, an array replaces one) and names the problem it expects after "receivers[i]",
/// "" for an entry that passes. XData Plain holds the demo's two receivers, which have no fhir block.
/// The validator is pure; a test that stores a profile puts the row back as it was.
Class Shutter.Test.FHIRProfile Extends %UnitTest.TestCase
{

Parameter NAME = "FHIR Ward Out";

/// The stored site profile's text before a test changed it, and whether there was a stored row at all.
Property SavedProfile As %String(MAXLEN = "");

Property ProfileChanged As %Boolean [ InitialExpression = 0 ];

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

Method OnAfterOneTest() As %Status
{
    Do ..RestoreProfile()
    Quit $$$OK
}

/// Every row: through the profile's validator, with the entry second in the list, and through the block's own.
Method TestEveryMessageOfTheTable()
{
    Set n = 0
    Set iter = ..Json("Rows").%GetIterator()
    While iter.%GetNext(.i, .row) {
        Set n = n + 1
        Set entry = ..Json("Entry")
        Do ##class(Shutter.Test.SiteProfile).Merge(entry, row.patch)
        Set p = ##class(Shutter.Store.SiteProfile).Default()
        Do p.receivers.%Push(entry)
        Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), $SELECT(row.expect = "": "", 1: "receivers[1]" _ row.expect), row.name)
        Do $$$AssertEquals(##class(Shutter.FHIR.Profile).SettingsProblem(entry, p.receivers, 1), row.expect, row.name _ ", from the block's own validator")
    }
    Do $$$AssertTrue(n > 40, "the table has its rows: " _ n)
    // The two ends of the map's size, which a table row would only hold at length.
    For size = 25, 26 {
        Set entry = ..Json("Entry"), map = []
        For j = 1:1:size { Do map.%Push({"ward": ("WARD-" _ j), "location": ("Location/ward-" _ j), "identifier": {"system": "urn:shutter:ward", "value": ("WARD-" _ j)}}) }
        Set entry.fhir."location_map" = map
        Set p = ##class(Shutter.Store.SiteProfile).Default()
        Do p.receivers.%Push(entry)
        Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), $SELECT(size = 25: "", 1: "receivers[1].fhir.location_map: must be an array of 2 to 25 wards"), "a map of " _ size _ " wards")
    }
    // The longest id a Location may have, and one more.
    For length = 64, 65 {
        Set entry = ..Json("Entry")
        Set entry.fhir."location_map".%Get(0).location = "Location/" _ $TRANSLATE($JUSTIFY("", length), " ", "a")
        Set p = ##class(Shutter.Store.SiteProfile).Default()
        Do p.receivers.%Push(entry)
        Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), $SELECT(length = 64: "", 1: "receivers[1].fhir.location_map[0].location: must be Location/{id}"), "a Location id of " _ length _ " characters")
    }
}

Method TestASecondFhirEntryIsRefused()
{
    Set c = "Shutter.Store.SiteProfile", message = ".fhir: one FHIR receiver per install in this version"
    Set p = $CLASSMETHOD(c, "Default")
    Do p.receivers.%Push(..Json("Entry"))
    Do $$$AssertEquals($CLASSMETHOD(c, "Validate", p), "", "one FHIR receiver passes")
    Set second = ..Json("Entry"), second.name = "FHIR Ward Out 2"
    Do p.receivers.%Push(second)
    Do $$$AssertEquals($CLASSMETHOD(c, "Validate", p), "receivers[2]" _ message, "a second one is refused, at its own place")
    // The first of the two can stand anywhere before it, with entries of another kind between.
    Set p = $CLASSMETHOD(c, "Default"), plain = p.receivers.%Get(0)
    Set p.receivers = [(..Json("Entry")), (plain), (second)]
    Do $$$AssertEquals($CLASSMETHOD(c, "Validate", p), "receivers[2]" _ message, "with a plain entry between the two")
    Do $$$AssertEquals(##class(Shutter.FHIR.Profile).SettingsProblem(second, p.receivers, 2), message, "the block's own validator says the same")
    Do $$$AssertEquals(##class(Shutter.FHIR.Profile).SettingsProblem(p.receivers.%Get(0), p.receivers, 0), "", "and the first of the two is not the one refused")
    // An earlier entry counts by having the key, whatever it holds: a later entry is still the second.
    Set p.receivers = [(plain), (second)]
    Do $$$AssertEquals($CLASSMETHOD(c, "Validate", p), "", "a FHIR entry after a plain one passes")
}

/// The demo's two receivers validate and read exactly as they did, alone and with a FHIR entry beside them.
Method TestAnEntryWithoutFhirIsUnmoved()
{
    Set c = "Shutter.Store.SiteProfile"
    Set plain = ..Json("Plain")
    Do ..ChangeProfile({"receivers": (plain)})
    Do $$$AssertEquals($CLASSMETHOD(c, "Validate", $CLASSMETHOD(c, "Current")), "", "the profile without a FHIR entry validates")
    Set iter = plain.%GetIterator()
    While iter.%GetNext(.i, .r) { Set before(r.name) = ..Readings(r.name) }
    Set with = ..Json("Plain")
    Do with.%Push(..Json("Entry"))
    Do ..ChangeProfile({"receivers": (with)})
    Do $$$AssertEquals($CLASSMETHOD(c, "Validate", $CLASSMETHOD(c, "Current")), "", "and with one it validates too")
    Set name = ""
    For {
        Set name = $ORDER(before(name), 1, was)
        Quit:name=""
        Do $$$AssertEquals(..Readings(name), was, name _ " reads the same beside a FHIR entry")
        Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverKind", name), "", name _ " has no kind")
    }
    // What the same was, in words, so that the two readings cannot both be wrong the same way.
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverPath", "Downstream Out", "state", "E 1"), "/downstream/api/encounters/E%201", "Downstream Out's state path")
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverPath", "Records Out", "receipt", "", "K1"), "/records/api/receipts/K1", "Records Out's receipt path")
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverFeatures", "Downstream Out").%ToJSON(), "{""conditional_writes"":true,""receipts"":true,""history"":true,""dry_run"":true}", "Downstream Out's features")
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverLabel", "Downstream Out"), "the demo bed-management system (/downstream/api)", "Downstream Out's label")
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverLabel", "Records Out"), "the demo patient records system (/records/api)", "Records Out's label")
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverCategory", "Downstream Out"), "current_state", "Downstream Out's category")
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverCategory", "Records Out"), "history_of_record", "Records Out's category")
    // An entry that declares features and no api, the plain receiver of before, keeps its own answer too.
    Do with.%Push({"name": "Plain Out", "system": "a plain system", "tier": 2, "features": {"conditional_writes": false, "receipts": false, "history": true, "dry_run": false}})
    Do ..ChangeProfile({"receivers": (with)})
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverFeatures", "Plain Out").history, 1, "declared features are still read as declared")
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverPath", "Plain Out", "state", "E1"), "", "and it still has no path")
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverLabel", "Plain Out"), "a plain system", "nor an address in its label")
}

Method TestKindPathFeaturesLabelOfAFhirEntry()
{
    Set c = "Shutter.Store.SiteProfile", name = ..#NAME
    Set list = ..Json("Plain")
    Do list.%Push(..Json("Entry"))
    Do ..ChangeProfile({"receivers": (list)})
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverKind", name), "fhir_r4", "the kind of an entry with a fhir block")
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverKind", "Not A Receiver"), "", "a receiver the profile does not name has no kind")
    For kind = "state", "receipt", "capabilities", "operations" {
        Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverPath", name, kind, "E1", "K1"), "", "no " _ kind _ " path")
    }
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverFeatures", name).%ToJSON(), "{""conditional_writes"":false,""receipts"":false,""history"":false,""dry_run"":false}", "all four features false")
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverLabel", name), "the ward system (FHIR R4)", "the label names the system and no address")
    Do $$$AssertEquals($CLASSMETHOD(c, "ReceiverCategory", name), "current_state", "a current_state receiver")
    Do $$$AssertEquals($CLASSMETHOD(c, "TierOf", name), 3, "at the tier its entry gives")
    Do $$$AssertEquals($PARAMETER("Shutter.FHIR.Profile", "POLICYVERSION"), "fhir-2026-11-14.1", "the gate's policy version")
    Do $$$AssertEquals($PARAMETER("Shutter.FHIR.Profile", "ITEMS"), "FHIR Receiver,FHIR Out,FHIR Gate,FHIR Verifier", "the four items")
}

Method TestTheReaders()
{
    Set c = "Shutter.FHIR.Profile", name = ..#NAME
    Set list = ..Json("Plain"), entry = ..Json("Entry")
    Do list.%Push(entry)
    Do ..ChangeProfile({"receivers": (list)})
    Set block = $CLASSMETHOD(c, "Block", name)
    Do $$$AssertTrue($ISOBJECT(block), "the block of the FHIR entry")
    Do $$$AssertEquals(block.base, "/fhir-facade/r4", "with its base")
    Do $$$AssertEquals($CLASSMETHOD(c, "Block", "Downstream Out"), "", "an entry without one has no block")
    Do $$$AssertEquals($CLASSMETHOD(c, "Block", "Not A Receiver"), "", "nor has a receiver the profile does not name")
    Do $$$AssertTrue($CLASSMETHOD(c, "Enabled", name), "recovery_enabled true reads as on")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Enabled", "Downstream Out"), "an entry without a block is off")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Enabled", "Not A Receiver"), "an unnamed receiver is off")
    // The map, both ways.
    Set e = $CLASSMETHOD(c, "LocationOf", block, "WARD-B")
    Do $$$AssertTrue($ISOBJECT(e), "WARD-B is in the map")
    Do $$$AssertEquals(e.location, "Location/ward-b", "with its Location")
    Do $$$AssertEquals(e.identifier.value, "WARD-B", "and the Location's identifier")
    Do $$$AssertEquals($CLASSMETHOD(c, "LocationOf", block, "WARD-Z"), "", "a ward the map does not hold")
    Do $$$AssertEquals($CLASSMETHOD(c, "LocationOf", block, "ward-b"), "", "a ward code is read exactly")
    Do $$$AssertEquals($CLASSMETHOD(c, "LocationOf", block, ""), "", "no ward")
    Do $$$AssertEquals($CLASSMETHOD(c, "LocationOf", "", "WARD-A"), "", "no block")
    Do $$$AssertEquals($CLASSMETHOD(c, "WardOf", block, "Location/ward-a"), "WARD-A", "the ward of a Location")
    Do $$$AssertEquals($CLASSMETHOD(c, "WardOf", block, "Location/ward-z"), "", "a Location the map does not hold")
    Do $$$AssertEquals($CLASSMETHOD(c, "WardOf", block, "ward-a"), "", "an id without Location/ is not a reference")
    Do $$$AssertEquals($CLASSMETHOD(c, "WardOf", block, ""), "", "no reference")
    Do $$$AssertEquals($CLASSMETHOD(c, "WardOf", "", "Location/ward-a"), "", "no block")
    // The digest is of the whole block, canonical, and moves with any of it.
    Set digest = $CLASSMETHOD(c, "MappingDigest", block)
    Do $$$AssertEquals(digest, ##class(Shutter.Util.Digest).OfObject(entry.fhir), "the digest of the block as the profile holds it")
    Do $$$AssertTrue($MATCH(digest, "sha256:[0-9a-f]{64}"), "a SHA-256 digest: " _ digest)
    Do $$$AssertEquals($CLASSMETHOD(c, "MappingDigest", $CLASSMETHOD(c, "Block", name)), digest, "the same for a second read")
    Set other = ..Json("Entry").fhir
    Set other."location_map".%Get(1).location = "Location/ward-c"
    Do $$$AssertNotEquals($CLASSMETHOD(c, "MappingDigest", other), digest, "another Location for a ward is another digest")
    Set other = ..Json("Entry").fhir
    Do other.%Set("recovery_enabled", 0, "boolean")
    Do $$$AssertNotEquals($CLASSMETHOD(c, "MappingDigest", other), digest, "and so is the switch")
    Do $$$AssertEquals($CLASSMETHOD(c, "MappingDigest", ""), "", "no block has no digest")
    // The switch: only a stored true is on.
    Do entry.fhir.%Set("recovery_enabled", 0, "boolean")
    Do ..ChangeProfile({"receivers": (list)})
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Enabled", name), "recovery_enabled false reads as off")
    Do entry.fhir.%Remove("recovery_enabled")
    Do ..ChangeProfile({"receivers": (list)})
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Enabled", name), "an absent switch reads as off")
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(c, "Block", name)), "and the block is still read")
}

/// A FHIR receiver's history policy is current, always: the site-wide flag an older profile may still carry never
/// reaches an entry with a fhir block, whether or not the entry names its category.
Method TestTheSiteWideHistoryPolicyNeverReachesAFhirEntry()
{
    Set list = ..Json("Plain"), entry = ..Json("Entry")
    Do entry.%Remove("category")
    Do list.%Push(entry)
    Do ..ChangeProfile({"history_policy": "correct", "receivers": (list)})
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Flag("history_policy", "current"), "correct", "the profile carries the site-wide flag")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).ReceiverKind(..#NAME) _ " [" _ ##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Receiver(..#NAME), "category") _ "]", "fhir_r4 []", "and the FHIR entry names no category")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).ReceiverHistoryPolicy(..#NAME), "current", "its history policy is current all the same")
}

/// With an incident open and taking cases, a failure to a FHIR receiver stays outside it; the same failure to a
/// receiver of another kind is handed that receiver's incident. All of it in a transaction that is rolled back.
Method TestRegisterJoinsNoIncident()
{
    Set name = ..#NAME, other = "Downstream Out"
    TSTART
    Try {
        Set list = ..Json("Plain")
        Do list.%Push(..Json("Entry"))
        Do ..ChangeProfile({"receivers": (list)})
        Do $$$AssertStatusOK(##class(Shutter.Store.Incident).Open(name, "board", .open), "an incident is open for the FHIR receiver")
        Do $$$AssertTrue($ISOBJECT(##class(Shutter.Store.Incident).OpenFor(name)), "and takes cases")
        For kind = "delivery_failed", "rejected" {
            Set case = ##class(Shutter.Store.Case).%New(), case.FailureKind = kind
            Set incident = "unset", openedNow = "unset"
            Do $$$AssertStatusOK(##class(Shutter.Store.IncidentDetector).Register(case, name, .incident, .openedNow), "Register answers for a " _ kind _ " case")
            Do $$$AssertEquals(incident, "", "the case joins no incident")
            Do $$$AssertEquals(openedNow, 0, "and opens none")
            Do $$$AssertNotTrue($ISOBJECT(case.Incident), "the case holds no incident")
        }
        // The control: the same call for a receiver of another kind reaches its incident.
        Do $$$AssertStatusOK(##class(Shutter.Store.Incident).Open(other, "board", .open), "an incident is open for a receiver of another kind")
        Set case = ##class(Shutter.Store.Case).%New(), case.FailureKind = "delivery_failed"
        Set sc = ##class(Shutter.Store.IncidentDetector).Register(case, other, .incident, .openedNow)
        Do $$$AssertTrue($ISOBJECT(incident), "whose failure is handed that incident")
    } Catch ex {
        Do $$$AssertStatusOK(ex.AsStatus(), "nothing is thrown")
    }
    TROLLBACK
    Set ..ProfileChanged = 0
    Do $$$AssertNotTrue($ISOBJECT(##class(Shutter.Store.Incident).OpenFor(name)), "nothing of the test is left")
}

/// What the readers answer for one receiver, as one text.
Method Readings(name As %String) As %String
{
    Set c = "Shutter.Store.SiteProfile", out = ""
    For kind = "state", "receipt", "capabilities", "operations" { Set out = out _ $CLASSMETHOD(c, "ReceiverPath", name, kind, "E 1", "K/1") _ "|" }
    Quit out _ $CLASSMETHOD(c, "ReceiverFeatures", name).%ToJSON() _ "|" _ $CLASSMETHOD(c, "ReceiverLabel", name) _ "|" _ $CLASSMETHOD(c, "ReceiverCategory", name)
}

/// Changes the stored site profile for one test, keeping its version; the patch is merged at the top level.
Method ChangeProfile(patch As %DynamicObject)
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '..ProfileChanged {
        Set ..HadProfileRow = $ISOBJECT(row), ..SavedProfile = $SELECT($ISOBJECT(row): row.Json, 1: ""), ..ProfileChanged = 1
    }
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Set version = +p.version
    Do p.%Remove("version")
    Do ##class(Shutter.Test.SiteProfile).Merge(p, patch)
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New(), row.Version = version
    Set row.Json = p.%ToJSON()
    Do $$$AssertStatusOK(row.%Save(), "the site profile is changed for the test")
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

/// One of this class's JSON blocks, parsed afresh.
ClassMethod Json(name As %String) As %DynamicAbstractObject
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||" _ name)
    Quit ##class(%DynamicAbstractObject).%FromJSON(xdata.Data)
}

/// The entry as a site writes it.
XData Entry [ MimeType = application/json ]
{
{"name": "FHIR Ward Out", "system": "the ward system (FHIR R4)", "category": "current_state", "tier": 3,
 "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false,
 "fhir": {"base": "/fhir-facade/r4", "recovery_enabled": true,
          "encounter_identifier": {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49"},
          "patient_identifier": {"system": "urn:shutter:demo:mrn", "hl7_authority": "HOSP"},
          "marker": {"system": "urn:shutter:recovery"},
          "location_map": [
            {"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}},
            {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}
}

/// The demo's two receivers, neither with a fhir block.
XData Plain [ MimeType = application/json ]
{
[
 {"name": "Downstream Out", "system": "the demo bed-management system", "category": "current_state", "tier": 2, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "api": {"base": "/downstream/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}", "capabilities": "/capabilities", "operations": "/operations"}, "features": {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}},
 {"name": "Records Out", "system": "the demo patient records system", "category": "history_of_record", "tier": 2, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "api": {"base": "/records/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}", "capabilities": "/capabilities", "operations": "/operations"}, "features": {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}, "demo": {"namespace": "RECORDS"}}
]
}

/// The table: name, the patch merged into XData Entry, and the problem expected after "receivers[i]".
XData Rows [ MimeType = application/json ]
{
[
 {"name": "the entry as written passes", "patch": {}, "expect": ""},
 {"name": "recovery_enabled absent passes and reads false", "patch": {"fhir": {"recovery_enabled": null}}, "expect": ""},
 {"name": "recovery_enabled false passes", "patch": {"fhir": {"recovery_enabled": false}}, "expect": ""},
 {"name": "category absent passes", "patch": {"category": null}, "expect": ""},
 {"name": "engine_resend false passes", "patch": {"engine_resend": false}, "expect": ""},
 {"name": "strict_answers true passes", "patch": {"strict_answers": true}, "expect": ""},
 {"name": "history_policy current passes", "patch": {"history_policy": "current"}, "expect": ""},
 {"name": "fhir a string", "patch": {"fhir": "/fhir-facade/r4"}, "expect": ".fhir: must be an object"},
 {"name": "fhir an array", "patch": {"fhir": []}, "expect": ".fhir: must be an object"},
 {"name": "fhir true", "patch": {"fhir": true}, "expect": ".fhir: must be an object"},
 {"name": "an unknown key of fhir", "patch": {"fhir": {"port": 443}}, "expect": ".fhir.port: unknown setting"},
 {"name": "a credential in the block is an unknown key", "patch": {"fhir": {"credential": "ward"}}, "expect": ".fhir.credential: unknown setting"},
 {"name": "base absent", "patch": {"fhir": {"base": null}}, "expect": ".fhir.base: must be a path starting with /"},
 {"name": "base without its slash", "patch": {"fhir": {"base": "fhir-facade/r4"}}, "expect": ".fhir.base: must be a path starting with /"},
 {"name": "base a whole address", "patch": {"fhir": {"base": "https://ward.example/fhir/r4"}}, "expect": ".fhir.base: must be a path starting with /"},
 {"name": "base a number", "patch": {"fhir": {"base": 4}}, "expect": ".fhir.base: must be a path starting with /"},
 {"name": "recovery_enabled a string", "patch": {"fhir": {"recovery_enabled": "true"}}, "expect": ".fhir.recovery_enabled: must be true or false"},
 {"name": "recovery_enabled a number", "patch": {"fhir": {"recovery_enabled": 1}}, "expect": ".fhir.recovery_enabled: must be true or false"},
 {"name": "encounter_identifier absent", "patch": {"fhir": {"encounter_identifier": null}}, "expect": ".fhir.encounter_identifier.system: required"},
 {"name": "encounter_identifier a string", "patch": {"fhir": {"encounter_identifier": "urn:oid:1"}}, "expect": ".fhir.encounter_identifier.system: required"},
 {"name": "encounter_identifier.system empty", "patch": {"fhir": {"encounter_identifier": {"system": ""}}}, "expect": ".fhir.encounter_identifier.system: required"},
 {"name": "encounter_identifier.system a number", "patch": {"fhir": {"encounter_identifier": {"system": 18}}}, "expect": ".fhir.encounter_identifier.system: required"},
 {"name": "encounter_identifier with another key", "patch": {"fhir": {"encounter_identifier": {"value": "E1"}}}, "expect": ".fhir.encounter_identifier.value: unknown setting"},
 {"name": "patient_identifier absent", "patch": {"fhir": {"patient_identifier": null}}, "expect": ".fhir.patient_identifier.system: required"},
 {"name": "patient_identifier an array", "patch": {"fhir": {"patient_identifier": []}}, "expect": ".fhir.patient_identifier.system: required"},
 {"name": "patient_identifier.system absent", "patch": {"fhir": {"patient_identifier": {"system": null}}}, "expect": ".fhir.patient_identifier.system: required"},
 {"name": "patient_identifier.hl7_authority absent", "patch": {"fhir": {"patient_identifier": {"hl7_authority": null}}}, "expect": ".fhir.patient_identifier.hl7_authority: required"},
 {"name": "patient_identifier.hl7_authority empty", "patch": {"fhir": {"patient_identifier": {"hl7_authority": ""}}}, "expect": ".fhir.patient_identifier.hl7_authority: required"},
 {"name": "patient_identifier with another key", "patch": {"fhir": {"patient_identifier": {"use": "official"}}}, "expect": ".fhir.patient_identifier.use: unknown setting"},
 {"name": "marker absent", "patch": {"fhir": {"marker": null}}, "expect": ".fhir.marker.system: required"},
 {"name": "marker.system empty", "patch": {"fhir": {"marker": {"system": ""}}}, "expect": ".fhir.marker.system: required"},
 {"name": "marker with another key", "patch": {"fhir": {"marker": {"value": "x"}}}, "expect": ".fhir.marker.value: unknown setting"},
 {"name": "location_map absent", "patch": {"fhir": {"location_map": null}}, "expect": ".fhir.location_map: must be an array of 2 to 25 wards"},
 {"name": "location_map an object", "patch": {"fhir": {"location_map": {"WARD-A": "Location/ward-a"}}}, "expect": ".fhir.location_map: must be an array of 2 to 25 wards"},
 {"name": "location_map empty", "patch": {"fhir": {"location_map": []}}, "expect": ".fhir.location_map: must be an array of 2 to 25 wards"},
 {"name": "location_map with one ward", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}]}}, "expect": ".fhir.location_map: must be an array of 2 to 25 wards"},
 {"name": "location_map holding a string", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, "WARD-B"]}}, "expect": ".fhir.location_map: must be an array of 2 to 25 wards"},
 {"name": "a map entry with another key", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}, "bed": "B1"}]}}, "expect": ".fhir.location_map[1].bed: unknown setting"},
 {"name": "a map entry without its ward", "patch": {"fhir": {"location_map": [{"location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[0].ward: required"},
 {"name": "a map entry with an empty ward", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[1].ward: required"},
 {"name": "a ward twice", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-A", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[1].ward: must be unique"},
 {"name": "a map entry without its location", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[0].location: required"},
 {"name": "a location that is only an id", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[0].location: must be Location/{id}"},
 {"name": "a location that is a whole address", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "https://ward.example/fhir/r4/Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[1].location: must be Location/{id}"},
 {"name": "a location with a version after its id", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a/_history/2", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[0].location: must be Location/{id}"},
 {"name": "a location with an underscore in its id", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward_a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[0].location: must be Location/{id}"},
 {"name": "a location of another resource type", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Organization/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[0].location: must be Location/{id}"},
 {"name": "a location twice", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[1].location: must be unique"},
 {"name": "a map entry without its identifier", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a"}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[0].identifier.system: required"},
 {"name": "an identifier without its system", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[0].identifier.system: required"},
 {"name": "an identifier with an empty value", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": ""}}]}}, "expect": ".fhir.location_map[1].identifier.value: required"},
 {"name": "an identifier with another key", "patch": {"fhir": {"location_map": [{"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A", "use": "official"}}, {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}, "expect": ".fhir.location_map[0].identifier.use: unknown setting"},
 {"name": "an api beside fhir", "patch": {"api": {"base": "/downstream/api", "state": "/encounters/{encounter}", "operations": "/operations"}}, "expect": ".fhir: an entry with a fhir block has no api"},
 {"name": "features beside fhir", "patch": {"features": {"conditional_writes": true, "receipts": false, "history": true, "dry_run": false}}, "expect": ".fhir: capability is read from the server, so features is refused"},
 {"name": "features all false beside fhir", "patch": {"features": {"conditional_writes": false, "receipts": false, "history": false, "dry_run": false}}, "expect": ".fhir: capability is read from the server, so features is refused"},
 {"name": "engine_resend true beside fhir", "patch": {"engine_resend": true, "ack_level": "application"}, "expect": ".engine_resend: refused beside fhir, one write route per receiver"},
 {"name": "category history_of_record beside fhir", "patch": {"category": "history_of_record"}, "expect": ".category: must be current_state beside fhir"},
 {"name": "category orders_results beside fhir", "patch": {"category": "orders_results"}, "expect": ".category: must be current_state beside fhir"},
 {"name": "strict_answers false beside fhir", "patch": {"strict_answers": false}, "expect": ".strict_answers: refused beside fhir"},
 {"name": "documents beside fhir", "patch": {"documents": {}}, "expect": ".documents: refused beside fhir"},
 {"name": "history_policy correct beside fhir", "patch": {"history_policy": "correct"}, "expect": ".history_policy: refused beside fhir"}
]
}

}
