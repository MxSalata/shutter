/// Scenario S35's parts: the kit's in-process run that gives a demo install its proof (FHIRFacade.Kit.Measure), the
/// demo's FHIR receiver entry added once to the demo's stored profile and never to a profile a person saved or a site's
/// (Shutter.FHIR.Install.DemoEntry), the entry kept off a site install (SiteProfile.ForSite), the runner's
/// "fhir_ward" route, and a scenario reset that resets and seeds the test FHIR server and settles what a FHIR case left
/// standing (Shutter.FHIR.Install.DemoReset). The stored profile, the runner's settings, the proof row and the cases made
/// here go back as they were.
Class Shutter.Test.FHIRScenario Extends %UnitTest.TestCase
{

Parameter RECEIVER = "UT FHIR Scenario Out";

Parameter INSTALL = "Shutter.FHIR.Install";

Parameter SERVICE = "FHIRFacade.Service";

Property Made As %String [ MultiDimensional ];

Property Kept As %String [ MultiDimensional ];

Property ProfileKept As %Boolean [ InitialExpression = 0 ];

Property SavedConfig As %String [ MultiDimensional ];

Property Scratch As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
    For node = "resetAt", "mode", "scenario", "demo", "fhirWardIn" { Merge ..SavedConfig(node) = ^Shutter.Config(node) }
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    For node = "resetAt", "mode", "scenario", "demo", "fhirWardIn" { Kill ^Shutter.Config(node) Merge ^Shutter.Config(node) = ..SavedConfig(node) }
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..RestoreProfile()
    For node = "demo", "fhirWardIn" { Kill ^Shutter.Config(node) Merge ^Shutter.Config(node) = ..SavedConfig(node) }
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ##class(Shutter.Store.Case).PurgeCase(id)
    }
    Kill i%Made
    Set path = ""
    For {
        Set path = $ORDER(i%Scratch(path), -1)
        Quit:path=""
        If ##class(%File).DirectoryExists(path) { Do ##class(%File).RemoveDirectoryTree(path) } Else { Do ##class(%File).Delete(path) }
    }
    Kill i%Scratch
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.FHIRProof WHERE Receiver = ?", ..#RECEIVER)
    Quit $$$OK
}

/// The kit's whole facade list runs in process and gives the very document the HTTP runner writes with --proof, which
/// the proof store accepts; the test server is left empty, with its clock free.
Method TestKitMeasuresTheFacadeInProcess()
{
    If '..FacadeLoaded() Do $$$AssertSkipped("FHIRFacade is not loaded on this instance") Quit
    Set sc = ##class(FHIRFacade.Kit).Measure(.doc)
    Do $$$AssertStatusOK(sc, "the in-process run measured every exchange as IRIS was measured to answer")
    If '$ISOBJECT(doc) Do $$$AssertTrue(0, "Measure gave no document") Quit
    Set keys = "", iter = doc.%GetIterator()
    While iter.%GetNext(.key) { Set keys = keys _ $SELECT(keys = "": "", 1: ",") _ key }
    Do $$$AssertEquals(keys, "kit,kit_sha256,target,base,measured_at,software,fhir_version,exchanges,differ,measurements", "the proof document's members, in the HTTP runner's order")
    Do $$$AssertEquals(doc.kit, $PARAMETER("Shutter.Store.FHIRProof", "KITNAME"), "the kit file's name")
    Do $$$AssertEquals(doc."kit_sha256", $PARAMETER("Shutter.Store.FHIRProof", "KITSHA256"), "and its digest")
    Do $$$AssertEquals(doc.target, "facade", "the test server's list")
    Do $$$AssertEquals(doc.base, "in-process:FHIRFacade.Service", "measured in process")
    Do $$$AssertEquals(doc.%GetTypeOf("exchanges") _ " " _ doc.exchanges, "number " _ $PARAMETER("Shutter.Store.FHIRProof", "KITFACADE"), "every exchange of the facade's list ran")
    Do $$$AssertEquals(doc.%GetTypeOf("differ") _ " " _ doc.differ, "number 0", "and none differed")
    Do $$$AssertTrue(doc."measured_at" ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "measured at a UTC time: " _ doc."measured_at")
    Do $$$AssertTrue(doc."measured_at" '= $PARAMETER("FHIRFacade.Kit", "CLOCK"), "the time of the run, not the test server's fixed clock")
    Set statement = {}.%FromJSON(..Fhir("GET", "metadata").body)
    Do $$$AssertEquals(doc.software.%ToJSON(), {"name": (statement.software.name), "version": (statement.software.version)}.%ToJSON(), "the software the test server names: " _ doc.software.%ToJSON())
    Do $$$AssertEquals(doc."fhir_version", statement.fhirVersion, "and its FHIR version")
    Do $$$AssertEquals(doc.measurements.%ToJSON(), {"if_match_stale_refused": {"exchange": "m3-update-stale", "passed": true}, "if_match_unknown_id_refused": {"exchange": "m5-if-match-unknown-id", "passed": true}, "tags_kept": {"exchange": "m8-history-tags", "passed": true}}.%ToJSON(), "the three measurements, each on its own exchange")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRProof).Import(..#RECEIVER, doc.%ToJSON(), .p), "the proof store accepts the document")
    Do $$$AssertEquals($SELECT($ISOBJECT(p): p.MeasuredBase _ " " _ p.Exchanges, 1: ""), "in-process:FHIRFacade.Service " _ doc.exchanges, "and records where and how much was measured")
    For type = "Encounter", "Location", "Patient" {
        Do $$$AssertEquals(##class(FHIRFacade.Store).Ids(type).%Size(), 0, "no " _ type _ " is left on the test server")
    }
    Do $$$AssertEquals(##class(FHIRFacade.Store).Clock(), "", "and its clock is free again")
}

/// On a demo whose stored profile is the seed's (here under the demo's mark), the entry is added once, keeping the
/// source; a profile a person saved and a site install are left alone.
Method TestDemoEntryOnceOnTheDemosProfile()
{
    Set c = ..#INSTALL, name = $PARAMETER(c, "DEMORECEIVER")
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '$ISOBJECT(row) Do $$$AssertSkipped("no stored site profile on this instance") Quit
    Do ..KeepProfile()
    Set seedPath = $GET(^Shutter.Config("root")) _ "knowledge/site/profile.json"
    Set p = ..WithoutFHIR(##class(Shutter.Store.SiteProfile).Current())
    Set ^Shutter.Config("demo") = 1
    Do ..StoreRaw(p, seedPath _ " (demo)")
    Set before = ##class(Shutter.Store.SiteProfile).Row().Version

    Do $$$AssertStatusOK($CLASSMETHOD(c, "DemoEntry", seedPath), "the demo's profile takes the entry")
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Do $$$AssertEquals(row.Version, before + 1, "as one new version")
    Do $$$AssertEquals(row.Source, seedPath _ " (demo)", "under the source it had")
    Set entry = ##class(Shutter.Store.SiteProfile).Receiver(name)
    Do $$$AssertEquals($SELECT($ISOBJECT(entry): entry.%ToJSON(), 1: ""), $CLASSMETHOD(c, "DemoReceiverEntry").%ToJSON(), "the entry is the demo's FHIR receiver")
    Set now = ##class(Shutter.Store.SiteProfile).Current()
    Do now.%Remove("version")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(now), "", "and the profile with it passes the profile's checks")

    Do $$$AssertStatusOK($CLASSMETHOD(c, "DemoEntry", seedPath), "a second run")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Version, before + 1, "stores no version")

    Do ..StoreRaw(p, "approver")
    Set before = ##class(Shutter.Store.SiteProfile).Row().Version
    Do $$$AssertStatusOK($CLASSMETHOD(c, "DemoEntry", seedPath), "a profile a person saved")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Version, before, "is not touched")
    Do $$$AssertNotTrue($ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver(name)), "and has no entry of the demo's")

    Do ..StoreRaw(p, seedPath)
    Set ^Shutter.Config("demo") = 0
    Do $$$AssertStatusOK($CLASSMETHOD(c, "DemoEntry", seedPath), "a site install")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Version, before, "stores no version")
    Do $$$AssertNotTrue($ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver(name)), "and has no entry of the demo's")
}

/// The entry is DESIGN 2.1's, verbatim.
Method TestTheEntryIsTheDesigns()
{
    Set design = {"name": "FHIR Ward Out", "system": "the ward system (FHIR R4)", "category": "current_state", "tier": 3,
        "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false,
        "fhir": {"base": "/fhir-facade/r4", "recovery_enabled": true,
            "encounter_identifier": {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49"},
            "patient_identifier": {"system": "urn:shutter:demo:mrn", "hl7_authority": "HOSP"},
            "marker": {"system": "urn:shutter:recovery"},
            "location_map": [
                {"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}},
                {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}
    Do $$$AssertEquals($CLASSMETHOD(..#INSTALL, "DemoReceiverEntry").%ToJSON(), design.%ToJSON(), "the demo's FHIR receiver entry is DESIGN 2.1's")
    Do $$$AssertEquals($PARAMETER(..#INSTALL, "DEMORECEIVER"), "FHIR Ward Out", "named after the demo hospital's stock TCP operation")
}

/// A site install starts from a profile with no demo receiver, the FHIR one included.
Method TestForSiteStripsTheDemoFHIRReceiver()
{
    Set own = {"name": "UT Site Out", "system": "a site's own", "tier": 3, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false}
    Set p = {"receivers": [($CLASSMETHOD(..#INSTALL, "DemoReceiverEntry")), (own)], "teams": [{"name": "UT team", "receivers": ["FHIR Ward Out", "UT Site Out"]}]}
    Set p = ##class(Shutter.Store.SiteProfile).ForSite(p)
    Set names = "", iter = p.receivers.%GetIterator()
    While iter.%GetNext(, .r) { Set names = names _ $SELECT(names = "": "", 1: ",") _ r.name }
    Do $$$AssertEquals(names, "UT Site Out", "the demo's FHIR receiver is taken out, the site's own stays")
    Do $$$AssertEquals(p.teams.%Get(0).receivers.%ToJSON(), "[""UT Site Out""]", "and out of a team's list")
}

/// A file step with the route "fhir_ward" drops into the demo hospital's FHIR ward feed, and says so; without the feed
/// it stops with the words below.
Method TestRouteFhirWard()
{
    Set r = "Shutter.Scenarios.Runner"
    Set source = ..ScratchDir("src") _ "S35-01-A02.hl7", target = ..ScratchDir("in")
    Set f = ##class(%Stream.FileCharacter).%New()
    Do f.LinkToFile(source)
    Do f.Write("MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015092000||ADT^A02^ADT_A02|UT35|P|2.5.1" _ $CHAR(13))
    Do $$$AssertStatusOK(f.%Save(), "a scratch fixture")
    Set step = {"file": "S35-01-A02.hl7", "path": (source), "route": "fhir_ward", "expect": "delivery_fails"}
    Set found = {"steps": [(step)]}
    Kill ^Shutter.Config("fhirWardIn")
    Set out = $CLASSMETHOD(r, "Play", found, "UT-S35", "policy", ##class(Shutter.Util.Time).NowUTC(), "")
    Do $$$AssertEquals(out.%Get("error"), "the step's route is the demo hospital's FHIR ward feed, which is not installed (^Shutter.Config(""fhirWardIn"") is not set)", "no feed: the run stops with why")
    Do $$$AssertNotTrue(##class(%File).Exists(target _ "S35-01-A02.hl7"), "and nothing is dropped")
    Set ^Shutter.Config("fhirWardIn") = target
    Set out = $CLASSMETHOD(r, "Play", found, "UT-S35", "policy", ##class(Shutter.Util.Time).NowUTC(), "")
    Do $$$AssertEquals(out.%Get("error"), "", "with the feed recorded, the step plays")
    Do $$$AssertEquals($SELECT($ISOBJECT(out.files): out.files.%ToJSON(), 1: ""), "[""S35-01-A02.hl7""]", "its file")
    Do $$$AssertTrue(##class(%File).Exists(target _ "S35-01-A02.hl7"), "into the feed's folder")
    Do $$$AssertEquals($CLASSMETHOD(r, "Describe", step), "delivering S35-01-A02.hl7 to the demo hospital's FHIR ward feed", "the step in words")
}

/// A scenario reset on a demo with S35's receiver resets and seeds the test FHIR server, revokes a standing approval of
/// an open FHIR case, marks a sent update with no answer uncertain, and leaves a closed case's approval as it was.
Method TestResetSeedsAndSettles()
{
    If '$GET(^Shutter.Config("demo")) Do $$$AssertSkipped("not a demo instance: the scenarios do not reset here") Quit
    Set name = $PARAMETER(..#INSTALL, "DEMORECEIVER")
    If '..FacadeLoaded() || (##class(Shutter.Store.SiteProfile).ReceiverKind(name) '= "fhir_r4") Do $$$AssertSkipped("this demo has no FHIR receiver " _ name) Quit
    Set open = ..NewCase("approved"), closed = ..NewCase("resolved")
    Set standing = ..Approved(open, .fence), done = ..Approved(closed)
    Do $$$AssertTrue(fence.MarkSent(), "the open case's update is sent, and no answer came")
    Set answer = ""
    Try {
        Set answer = ##class(%DynamicObject).%FromJSON(##class(Shutter.Scenarios.Runner).Reset())
    } Catch ex {
        Do $$$AssertTrue(0, "Reset threw: " _ ex.DisplayString())
    }
    Quit:'$ISOBJECT(answer)
    Set fhir = $SELECT($ISOBJECT(answer.receivers): answer.receivers.%Get(name), 1: "")
    Do $$$AssertTrue($ISOBJECT(fhir), "the reset answers for " _ name _ " under receivers")
    Quit:'$ISOBJECT(fhir)
    Do $$$AssertEquals(fhir.%GetTypeOf("reset") _ " " _ fhir.reset, "boolean 1", "the test FHIR server was reset")
    Do $$$AssertEquals(fhir.seeded, 4, "and seeded with S35's four resources")
    Do $$$AssertTrue(fhir.revoked >= 1, "an approval or more was revoked: " _ fhir.%ToJSON())
    Do $$$AssertTrue(fhir.settled >= 1, "a sent update or more was settled: " _ fhir.%ToJSON())
    Do $$$AssertTrue($ISOBJECT(answer.ward), "the downstream system's answer is there as before")
    If ##class(Shutter.Store.SiteProfile).ReceiverNames().%ToJSON() [ """Records Out""" {
        Do $$$AssertTrue($ISOBJECT(answer.receivers.%Get("Records Out")) && 'answer.receivers.%Get("Records Out").%IsDefined("error"), "and so is the records system's")
    }

    Set got = ..Fhir("GET", "Encounter/enc-1035")
    Do $$$AssertEquals(got.status, 200, "the seeded Encounter reads")
    Set enc = {}.%FromJSON(got.body), etag = ""
    Set iter = got.headers.%GetIterator()
    While iter.%GetNext(.k, .v) { Set:$ZCONVERT(k, "L")="etag" etag = v }
    Do $$$AssertEquals(etag, "W/""1""", "at version 1")
    Do $$$AssertEquals(enc.location.%Size() _ " " _ enc.location.%Get(0).location.reference _ " " _ enc.location.%Get(0).status, "1 Location/ward-a active", "open at Ward A")
    Do $$$AssertEquals(enc.location.%Get(0).period.%IsDefined("end"), 0, "with no end")

    Set a = ##class(Shutter.Store.Approval).%OpenId(standing, 0)
    Do $$$AssertEquals(a.Revoked _ " " _ a.RevokedBy, "1 system: scenario reset", "the open case's standing approval is revoked")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT State, Outcome, ""Diagnostics"" AS D FROM Shutter_Store.FHIRAttempt WHERE ID = ?", fence.%Id())
    Do $$$AssertTrue(rs.%Next(), "its fence row is there")
    Do $$$AssertEquals(rs.%Get("State") _ " " _ rs.%Get("Outcome"), "sent uncertain", "sent, and uncertain now")
    Do $$$AssertTrue(rs.%Get("D") [ "reset by the scenario runner", "saying why: " _ rs.%Get("D"))
    Set b = ##class(Shutter.Store.Approval).%OpenId(done, 0)
    Do $$$AssertEquals(+b.Revoked, 0, "a closed case's approval is left as it was")
}

/// In process, one request to the test FHIR server.
Method Fhir(method As %String, path As %String) As %DynamicObject
{
    Quit $CLASSMETHOD(..#SERVICE, "Handle", {"method": (method), "path": (path), "query": "", "headers": {}, "body": "", "base": ""})
}

Method FacadeLoaded() As %Boolean
{
    Quit ##class(%Dictionary.CompiledClass).%ExistsId(..#SERVICE) && ##class(%Dictionary.CompiledClass).%ExistsId("FHIRFacade.Kit")
}

/// A saved case of the demo's FHIR receiver in <var>state</var>; a resolved one is closed.
Method NewCase(state As %String) As Shutter.Store.Case
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-FHIRSC-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.FHIRScenario)
    Set case.Event = "transfer", case.FailureKind = "delivery_failed", case.FailureText = "made up", case.EncounterId = "ENC-UT35"
    Set case.PatientId = "MRN-UT35", case.PatientIdAuthority = "HOSP", case.Receiver = $PARAMETER(..#INSTALL, "DEMORECEIVER"), case.State = state, case.Mode = "policy"
    Set case.OperationKey = "PAS^HOSP^MRN-UT35^ENC-UT35^transfer^" _ case.CaseId, case.Disposition = "resend"
    Set case.EventTime = "2026-10-15T08:20:00Z"
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Set:state="resolved" case.ClosedAt = now
    Do $$$AssertStatusOK(case.%Save(), "a " _ state _ " case is saved")
    Set i%Made(case.%Id()) = ""
    Set snapshot = ##class(Shutter.Store.Snapshot).Begin(case)
    Do $$$AssertStatusOK(snapshot.Seal({"fhir": {"kind": "fhir_r4"}}), "its snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snapshot), "and is its current one")
    Quit case
}

/// A plan of the case, its binding sealed and tied to a person's approval, and the fence row of that approval. Returns
/// the approval's id.
Method Approved(case As Shutter.Store.Case, Output fence As Shutter.Store.FHIRAttempt) As %String
{
    Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, case.CurrentSnapshot, {"disposition": "resend", "action": {"type": "resend"}}, "policy", .plan), "a plan is saved")
    Set a = ##class(Shutter.Store.Approval).%New()
    Do a.CaseSetObjectId(case.%Id()), a.PlanSetObjectId(plan.%Id())
    Set a.Approver = "approver", a.Decision = "approved", a.DecidedAt = ##class(Shutter.Util.Time).NowUTC()
    Do $$$AssertStatusOK(a.%Save(), "a person's approval is saved")
    Set body = "{""resourceType"":""Encounter"",""id"":""enc-1035"",""meta"":{""versionId"":""1""},""status"":""in-progress""}"
    Set digest = "Shutter.FHIR.Plan", etag = "W/""1"""
    Set operation = $EXTRACT($CLASSMETHOD(digest, "BodyDigest", case.CaseId _ "|" _ plan.%Id() _ "|" _ etag), 1, 32)
    Set prepared = {"view": {"prior_location": "Location/ward-a", "target_location": "Location/ward-b"}, "detail": {},
        "fhir": {"kind": "fhir_r4", "mapping_digest": "sha256:ut-mapping",
            "encounter": {"http_status": 200, "id": "enc-1035", "version_id": "1"},
            "patient": {"http_status": 200, "reference": "Patient/pat-1035", "etag": "W/\"1\""},
            "locations": [{"reference": "Location/ward-a", "etag": "W/\"1\""}, {"reference": "Location/ward-b", "etag": "W/\"1\""}]},
        "entry": ($CLASSMETHOD(..#INSTALL, "DemoReceiverEntry"))}
    Set prepared.fhir.encounter.etag = etag, prepared.fhir.encounter."body_digest" = $CLASSMETHOD(digest, "BodyDigest", body)
    Set prepared."event_time" = case.EventTime, prepared."operation_id" = operation
    Set prepared.marker = {"system": "urn:shutter:recovery", "code": (operation)}
    Set prepared.body = body, prepared."body_digest" = $CLASSMETHOD(digest, "BodyDigest", body)
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRBinding).Seal(case, plan, prepared, .binding), "its binding is sealed")
    Do $$$AssertStatusOK(binding.Bind(a.%Id()), "and tied to the approval")
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRAttempt).Open(case, binding, .fence, .created), "the fence row opens")
    Quit a.%Id()
}

/// The profile without any receiver that has a fhir block.
Method WithoutFHIR(p As %DynamicObject) As %DynamicObject
{
    Do p.%Remove("version")
    Set keep = [], iter = p.receivers.%GetIterator()
    While iter.%GetNext(, .r) { Do:'($ISOBJECT(r) && $ISOBJECT(r.%Get("fhir"))) keep.%Push(r) }
    Set p.receivers = keep
    Quit p
}

/// The stored row's text and source, written as they are (no new version), for one step of a test.
Method StoreRaw(p As %DynamicObject, source As %String)
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set row.Json = p.%ToJSON(), row.Source = source
    Do $$$AssertStatusOK(row.%Save(), "the stored profile is set for the test, source " _ source)
}

/// The stored row as it is, put back after the test with the versions the test stored taken out of the history.
Method KeepProfile()
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set ..Kept("json") = row.Json, ..Kept("source") = row.Source, ..Kept("version") = row.Version
    Set ..Kept("at") = row.UpdatedAt, ..Kept("by") = row.UpdatedBy, ..ProfileKept = 1
}

Method RestoreProfile()
{
    Quit:'..ProfileKept
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set row.Json = ..Kept("json"), row.Source = ..Kept("source"), row.Version = ..Kept("version")
    Set row.UpdatedAt = ..Kept("at"), row.UpdatedBy = ..Kept("by")
    Do row.%Save()
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.SiteProfileVersion WHERE Version > ?", ..Kept("version"))
    Kill ^Shutter.Config("feedZone"), ^Shutter.Config("preventFailures")
    Set ..ProfileKept = 0
    Kill i%Kept
}

/// A scratch folder of this test's, removed after it.
Method ScratchDir(name As %String) As %String
{
    Set dir = ##class(%File).NormalizeDirectory(##class(%File).ManagerDirectory() _ "Temp/ut-fhirscenario-" _ $JOB _ "-" _ name)
    Do ##class(%File).CreateDirectoryChain(dir)
    Set i%Scratch(dir) = ""
    Quit dir
}

}
