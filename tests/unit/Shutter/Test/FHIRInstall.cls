/// The FHIR items' install class (Shutter.FHIR.Install) on a scratch production that never runs: nothing here places
/// an item into the running production. The classes of the four items need not exist: the tests read the definition.
/// The record ^Shutter.Config("fhirItems"), the stored site profile and the proof rows go back as they were.
Class Shutter.Test.FHIRInstall Extends %UnitTest.TestCase
{

Parameter PRODUCTION = "ShutterTest.FhirInstall";

Parameter RECEIVER = "UT FHIR Install Out";

Property HadNode As %Boolean [ InitialExpression = 0 ];

Property Node As %String;

Property SavedProfile As %String(MAXLEN = "");

Property ProfileChanged As %Boolean [ InitialExpression = 0 ];

Property HadProfileRow As %Boolean [ InitialExpression = 0 ];

Property Made As %String [ MultiDimensional ];

Method OnBeforeOneTest() As %Status
{
    Set ..HadNode = $DATA(^Shutter.Config("fhirItems"), was), ..Node = $GET(was)
    Kill ^Shutter.Config("fhirItems")
    Quit ..MakeProduction()
}

Method OnAfterOneTest() As %Status
{
    Kill ^Shutter.Config("fhirItems")
    Set:..HadNode ^Shutter.Config("fhirItems") = ..Node
    Do ..RemoveProduction()
    Do ..RestoreProfile()
    Set id = ""
    For {
        Set id = $ORDER(i%Made(id))
        Quit:id=""
        Do ##class(Shutter.Store.Case).PurgeCase(id)
    }
    Kill i%Made
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.FHIRProof WHERE Receiver = ?", ..#RECEIVER)
    Quit $$$OK
}

Method TestNothingWithoutTheNode()
{
    Set c = "Shutter.FHIR.Install"
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, ..#PRODUCTION), "with no record")
    Do $$$AssertEquals(added, 0, "nothing is added")
    Do $$$AssertEquals(..ItemNames(), "Site Out", "the production is as it was")
    Do $$$AssertTrue(..ClassHolds("Site Out") && '..ClassHolds("FHIR Out"), "and so is its class")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added), "the install's own call, with no record")
    Do $$$AssertEquals(added, 0, "adds nothing to Shutter's production")
    Do $$$AssertEquals(..OwnFhirItems(), 0, "which has none of the four")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, "ShutterTest.NoSuchProduction"), "nor is the production looked for")
    Do $$$AssertEquals($DATA(^Shutter.Config("fhirItems")), 0, "no record is made")
}

Method TestPlaceOnAScratchProduction()
{
    Set c = "Shutter.FHIR.Install"
    Set ^Shutter.Config("fhirItems") = $LISTBUILD("fhir.example.org", 8443, "FHIRServer", "FHIRTLS")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, ..#PRODUCTION), "the four are placed")
    Do $$$AssertEquals(added, 4, "four added")
    Do $$$AssertEquals(..ItemNames(), "FHIR Gate,FHIR Out,FHIR Receiver,FHIR Verifier,Site Out", "beside the site's own")
    Do $$$AssertEquals(..ItemNames(), "FHIR Gate,FHIR Out,FHIR Receiver,FHIR Verifier,Site Out", "read again")
    For row = $LISTBUILD("FHIR Receiver", "Shutter.Operation.FHIRReceiver"), $LISTBUILD("FHIR Out", "Shutter.Operation.FHIRExecute"), $LISTBUILD("FHIR Gate", "Shutter.Operation.FHIRGate"), $LISTBUILD("FHIR Verifier", "Shutter.Operation.FHIRVerify") {
        Do $$$AssertEquals(..Shape($LIST(row, 1)), $LIST(row, 2) _ "|1|1|Recovery", $LIST(row, 1) _ ": its class, one job, enabled, in Recovery")
    }
    Set server = "Adapter:ConnectTimeout=5;Adapter:Credentials=FHIRServer;Adapter:HTTPPort=8443;Adapter:HTTPServer=fhir.example.org;Adapter:ResponseTimeout=15;Adapter:SSLConfig=FHIRTLS;Host:FailureTimeout=0"
    Do $$$AssertEquals(..Settings("FHIR Receiver"), server, "the reader's settings")
    Do $$$AssertEquals(..Settings("FHIR Out"), server, "the writer's are the same")
    Do $$$AssertEquals(..Settings("FHIR Gate"), "", "the gate has none")
    Do $$$AssertEquals(..Settings("FHIR Verifier"), "", "nor the verifier")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", ..#PRODUCTION), "", "no problem")
    Do $$$AssertTrue(..ClassHolds("FHIR Receiver") && ..ClassHolds("FHIR Out") && ..ClassHolds("FHIR Gate") && ..ClassHolds("FHIR Verifier"), "the definition is written to its class")
    Do $$$AssertEquals($PARAMETER("Shutter.FHIR.Profile", "ITEMS"), "FHIR Receiver,FHIR Out,FHIR Gate,FHIR Verifier", "the four names are the profile class's")
    // The call a site makes refuses a port that is none, and leaves the record alone.
    Set was = ^Shutter.Config("fhirItems")
    Set out = $CLASSMETHOD(c, "PlaceItems", "fhir.example.org", "https", "FHIRServer", "")
    Do $$$AssertNotTrue(out.ok, "a port that is no number is refused")
    Do $$$AssertTrue(out.error [ "port", "and said: " _ out.error)
    Do $$$AssertEquals(out.added _ "," _ out.updated, "0,0", "nothing added or updated")
    Do $$$AssertTrue(^Shutter.Config("fhirItems") = was, "the record is as it was")
    Do $$$AssertEquals(..OwnFhirItems(), 0, "and Shutter's production has none of the four")
    // Nor does it place an item whose class this install does not have.
    Set absent = 0
    For class = "Shutter.Operation.FHIRReceiver", "Shutter.Operation.FHIRExecute", "Shutter.Operation.FHIRGate", "Shutter.Operation.FHIRVerify" { Set:'##class(%Dictionary.CompiledClass).%ExistsId(class) absent = 1 }
    If absent {
        Set out = $CLASSMETHOD(c, "PlaceItems", "fhir.example.org", "8443", "FHIRServer", "")
        Do $$$AssertNotTrue(out.ok, "an install without the four classes places nothing")
        Do $$$AssertTrue(out.error [ "Nothing was changed", "and says so: " _ out.error)
        Do $$$AssertTrue(^Shutter.Config("fhirItems") = was, "the record is as it was")
        Do $$$AssertEquals(..OwnFhirItems(), 0, "and Shutter's production has none of the four")
    }
}

Method TestRestoreAfterTheItemsAreGone()
{
    Set c = "Shutter.FHIR.Install"
    // No credential and no TLS: those two settings are left out, as the adapter's own defaults.
    Set ^Shutter.Config("fhirItems") = $LISTBUILD("127.0.0.1", 52773, "", "")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, ..#PRODUCTION), "placed")
    Set plain = "Adapter:ConnectTimeout=5;Adapter:HTTPPort=52773;Adapter:HTTPServer=127.0.0.1;Adapter:ResponseTimeout=15;Host:FailureTimeout=0"
    Do $$$AssertEquals(..Settings("FHIR Out"), plain, "no Credentials and no SSLConfig row")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, ..#PRODUCTION), "a second time")
    Do $$$AssertEquals(added, 0, "adds nothing")
    // A load rewrites the production from its package: here two of the four go.
    Do ..DropItem("FHIR Out")
    Do ..DropItem("FHIR Gate")
    Do $$$AssertEquals(..ItemNames(), "FHIR Receiver,FHIR Verifier,Site Out", "two are gone")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, ..#PRODUCTION), "restored")
    Do $$$AssertEquals(added, 2, "the two come back")
    Do $$$AssertEquals(..ItemNames(), "FHIR Gate,FHIR Out,FHIR Receiver,FHIR Verifier,Site Out", "all four again")
    Do $$$AssertEquals(..Settings("FHIR Out"), plain, "with the recorded server")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", ..#PRODUCTION), "", "no problem")
    // All of them gone, as after a compile of the package's definition.
    For name = "FHIR Receiver", "FHIR Out", "FHIR Gate", "FHIR Verifier" Do ..DropItem(name)
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, ..#PRODUCTION), "restored whole")
    Do $$$AssertEquals(added, 4, "four come back")
    Do $$$AssertEquals(..Settings("FHIR Receiver"), plain, "the reader on the recorded server")
}

Method TestASecondPlaceRewritesBothEndpoints()
{
    Set c = "Shutter.FHIR.Install"
    Set ^Shutter.Config("fhirItems") = $LISTBUILD("old.example.org", 8443, "OldLogin", "OldTLS")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, ..#PRODUCTION), "placed on the first server")
    Do ..SetSetting("FHIR Out", "Host", "FailureTimeout", "30")
    Set ^Shutter.Config("fhirItems") = $LISTBUILD("new.example.org", 443, "NewLogin", "")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, ..#PRODUCTION), "a second call names another server")
    Do $$$AssertEquals(added, 0, "nothing is added")
    Set new = "Adapter:ConnectTimeout=5;Adapter:Credentials=NewLogin;Adapter:HTTPPort=443;Adapter:HTTPServer=new.example.org;Adapter:ResponseTimeout=15;Host:FailureTimeout="
    Do $$$AssertEquals(..Settings("FHIR Receiver"), new _ "0", "the reader is on the new server, with no TLS row")
    Do $$$AssertEquals(..Settings("FHIR Out"), new _ "30", "and so is the writer; a setting that names no server stays as the site left it")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", ..#PRODUCTION), "", "the two agree")
    // One of the two moved by hand in the portal: the next call brings it back.
    Do ..SetSetting("FHIR Out", "Adapter", "HTTPServer", "elsewhere.example.org")
    Do ..SetSetting("FHIR Out", "Adapter", "SSLConfig", "TheirTLS")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", ..#PRODUCTION), "FHIR Receiver and FHIR Out name different servers", "they differ")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, ..#PRODUCTION), "restored")
    Do $$$AssertEquals(..Settings("FHIR Out"), new _ "30", "the writer is back on the recorded server")
    Do $$$AssertEquals(..Settings("FHIR Receiver"), new _ "0", "the reader was not touched")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", ..#PRODUCTION), "", "and they agree again")
    Do $$$AssertEquals(..Settings("Site Out"), "Adapter:HTTPServer=their.example.org", "the site's own item on the writer's class keeps its server")
}

Method TestProblemNamesMissingDisabledAndDifferingServers()
{
    Set c = "Shutter.FHIR.Install", p = ..#PRODUCTION
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", "ShutterTest.NoSuchProduction"), "No production ShutterTest.NoSuchProduction", "no such production")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", p), "Missing from " _ p _ ": FHIR Receiver, FHIR Out, FHIR Gate, FHIR Verifier", "none placed")
    Set ^Shutter.Config("fhirItems") = $LISTBUILD("fhir.example.org", 8443, "FHIRServer", "")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, p), "placed")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", p), "", "all four, enabled, one server")
    Do ..DropItem("FHIR Gate")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", p), "Missing from " _ p _ ": FHIR Gate", "one missing")
    Do ..Enable("FHIR Verifier", 0)
    Do ..Enable("FHIR Out", 0)
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", p), "Missing from " _ p _ ": FHIR Gate. Disabled: FHIR Out, FHIR Verifier", "one missing, two disabled")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, p), "restored")
    Do $$$AssertEquals(added, 1, "the missing one comes back")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", p), "Disabled: FHIR Out, FHIR Verifier", "a disabled item is the site's choice and stays disabled")
    Do ..Enable("FHIR Verifier", 1)
    Do ..Enable("FHIR Out", 1)
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", p), "", "enabled again")
    For row = $LISTBUILD("HTTPServer", "other.example.org"), $LISTBUILD("HTTPPort", "8444"), $LISTBUILD("SSLConfig", "TheirTLS"), $LISTBUILD("Credentials", "Another") {
        Do ..SetSetting("FHIR Receiver", "Adapter", $LIST(row, 1), $LIST(row, 2))
        Do $$$AssertEquals($CLASSMETHOD(c, "Problem", p), "FHIR Receiver and FHIR Out name different servers", "another " _ $LIST(row, 1))
        Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, p), "restored")
        Do $$$AssertEquals($CLASSMETHOD(c, "Problem", p), "", "and the same again")
    }
    Do ..SetSetting("FHIR Receiver", "Adapter", "ResponseTimeout", "60")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", p), "", "a setting that names no server may differ")
    Do ..Enable("FHIR Receiver", 0)
    Do ..SetSetting("FHIR Out", "Adapter", "HTTPPort", "1")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", p), "Disabled: FHIR Receiver. FHIR Receiver and FHIR Out name different servers", "both said")
}

Method TestRemoveItems()
{
    Set c = "Shutter.FHIR.Install", p = ..#PRODUCTION
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RemoveItems", p), "with none placed")
    Do $$$AssertEquals(..ItemNames(), "Site Out", "nothing is taken")
    Set ^Shutter.Config("fhirItems") = $LISTBUILD("fhir.example.org", 8443, "FHIRServer", "")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, p), "placed")
    Do $$$AssertEquals(..ItemNames(), "FHIR Gate,FHIR Out,FHIR Receiver,FHIR Verifier,Site Out", "four and the site's")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RemoveItems", p), "removed")
    Do $$$AssertEquals(..ItemNames(), "Site Out", "the four are gone and the site's item on the writer's class stays")
    Do $$$AssertEquals(..ItemRows("FHIR "), 0, "their rows are gone too")
    Do $$$AssertTrue(..ClassHolds("Site Out") && '..ClassHolds("FHIR Receiver") && '..ClassHolds("FHIR Gate"), "and they are gone from its class")
    Do $$$AssertTrue($DATA(^Shutter.Config("fhirItems")) > 0, "the record is Shutter's production's, and stays for another production")
    // A site's own item under one of the four names, on its own class, is not Shutter's.
    Do ..AddItem("FHIR Gate", "Site.TheirGate")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RemoveItems", p), "removed again")
    Do $$$AssertEquals(..ItemNames(), "FHIR Gate,Site Out", "it stays")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RestoreItems", .added, p), "and a restore")
    Do $$$AssertEquals(added, 3, "adds the three that are missing, never a second item of that name")
    Do $$$AssertEquals($CLASSMETHOD(c, "Problem", p), "Not on Shutter's class: FHIR Gate (Site.TheirGate)", "which the problem names")
    Do $$$AssertStatusOK($CLASSMETHOD(c, "RemoveItems", "ShutterTest.NoSuchProduction"), "a production that is not there is no error")
    Do $$$AssertEquals(..OwnFhirItems(), 0, "Shutter's production never had one")
}

Method TestDoctorWithAndWithoutAnEntry()
{
    Set c = "Shutter.FHIR.Install"
    Set profile = ##class(Shutter.Store.SiteProfile).Current(), has = 0
    Set li = profile.receivers.%GetIterator()
    While li.%GetNext(, .r) { If $ISOBJECT(r) && $ISOBJECT(r.%Get("fhir")) Set has = 1 }
    If has Do $$$AssertSkipped("this instance's profile already has a FHIR receiver") Quit
    Do $$$AssertEquals($CLASSMETHOD(c, "Doctor").%ToJSON(), "{""receivers"":[]}", "with no entry: no receivers, and nothing else")
    Set whole = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).Doctor(), .sc)
    Do $$$AssertStatusOK(sc, "the Doctor answers JSON")
    Do $$$AssertEquals(whole.fhir.%ToJSON(), "{""receivers"":[]}", "and carries the same under fhir")
    Do $$$AssertEquals(whole."missing_items".%Size(), 0, "its own item check is as it was")

    Set entry = ..Entry()
    Do profile.receivers.%Push(entry)
    Do ..ChangeProfile({"receivers": (profile.receivers)})
    Set d = $CLASSMETHOD(c, "Doctor")
    Do $$$AssertEquals(d."policy_version", $PARAMETER("Shutter.FHIR.Profile", "POLICYVERSION"), "the FHIR gate's policy version")
    Do $$$AssertTrue(d."items_problem" [ "Missing from", "the items are not placed: " _ d."items_problem")
    Do $$$AssertEquals(d.%GetTypeOf("endpoints_agree") _ d."endpoints_agree", "boolean0", "so no two endpoints agree")
    Do $$$AssertEquals(d.receivers.%Size(), 1, "one receiver")
    Set row = d.receivers.%Get(0)
    Do $$$AssertEquals(row.receiver, ..#RECEIVER, "by its name")
    Do $$$AssertEquals(row.%GetTypeOf("recovery_enabled") _ row."recovery_enabled", "boolean1", "recovery is on in the entry")
    Do $$$AssertEquals(row.proof, "none", "no conformance run on record")
    Do $$$AssertEquals(row."proof_measured_at", "", "so no time of one")
    Do $$$AssertEquals(row.%GetTypeOf("credential") _ row.credential, "boolean0", "and no credential")
    Do $$$AssertEquals(##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).Doctor(), .sc).fhir.receivers.%Get(0).receiver, ..#RECEIVER, "the Doctor carries it")

    Set proofDoc = ##class(Shutter.Test.FHIRStores).Proof()
    Do $$$AssertStatusOK(##class(Shutter.Store.FHIRProof).Import(..#RECEIVER, proofDoc.%ToJSON()), "a conformance run is imported")
    Do entry.fhir.%Set("recovery_enabled", 0, "boolean")
    Do ..ChangeProfile({"receivers": (profile.receivers)})
    Set row = $CLASSMETHOD(c, "Doctor").receivers.%Get(0)
    Do $$$AssertEquals(row.proof, "matches", "a run on record, and no read of the server that says otherwise")
    Do $$$AssertEquals(row."proof_measured_at", "2026-11-14T10:00:00Z", "with its time")
    Do $$$AssertEquals(row.%GetTypeOf("recovery_enabled") _ row."recovery_enabled", "boolean0", "recovery is off in the entry")

    // The server names its software in the evidence of the receiver's newest case.
    Do ..NewCase({"name": (proofDoc.software.name), "version": (proofDoc.software.version)})
    Do $$$AssertEquals($CLASSMETHOD(c, "Doctor").receivers.%Get(0).proof, "matches", "the software measured is the software read")
    Do ..NewCase({"name": (proofDoc.software.name), "version": "another-version"})
    Do $$$AssertEquals($CLASSMETHOD(c, "Doctor").receivers.%Get(0).proof, "other_software", "the server has since named another version")
    Set proof = ##class(Shutter.Store.FHIRProof).For(..#RECEIVER)
    Do $$$AssertEquals($CLASSMETHOD(c, "ProofWord", "", "a", "b"), "none", "no row")
    Do $$$AssertEquals($CLASSMETHOD(c, "ProofWord", proof, "Another server", proofDoc.software.version), "other_software", "another name")
    Do $$$AssertEquals($CLASSMETHOD(c, "ProofWord", proof, proofDoc.software.name, ""), "other_software", "a name with no version")

    // Before the items are placed, the credential is the one on record.
    Set ^Shutter.Config("fhirItems") = $LISTBUILD("fhir.example.org", 8443, "UT-FHIR-Install-None", "")
    Do $$$AssertNotTrue($CLASSMETHOD(c, "Doctor").receivers.%Get(0).credential, "a credential on record that is not stored")
    Set stored = ""
    &sql(SELECT TOP 1 ID INTO :stored FROM Ens_Config.Credentials)
    If stored '= "" {
        Set ^Shutter.Config("fhirItems") = $LISTBUILD("fhir.example.org", 8443, stored, "")
        Do $$$AssertTrue($CLASSMETHOD(c, "Doctor").receivers.%Get(0).credential, "one that is stored")
    }
    Kill ^Shutter.Config("fhirItems")
}

/// The entry of DESIGN 2.1 under this test's name.
ClassMethod Entry() As %DynamicObject
{
    Quit {"name": (..#RECEIVER), "system": "the ward system (FHIR R4)", "category": "current_state", "tier": 3,
        "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false,
        "fhir": {"base": "/fhir-facade/r4", "recovery_enabled": true,
            "encounter_identifier": {"system": "urn:oid:2.16.840.1.113883.2.1.3.2.4.18.49"},
            "patient_identifier": {"system": "urn:shutter:demo:mrn", "hl7_authority": "HOSP"},
            "marker": {"system": "urn:shutter:recovery"},
            "location_map": [
                {"ward": "WARD-A", "location": "Location/ward-a", "identifier": {"system": "urn:shutter:ward", "value": "WARD-A"}},
                {"ward": "WARD-B", "location": "Location/ward-b", "identifier": {"system": "urn:shutter:ward", "value": "WARD-B"}}]}}
}

/// A saved case of this test's receiver whose current evidence holds the software the server named.
Method NewCase(software As %DynamicObject)
{
    Set case = ##class(Shutter.Store.Case).%New()
    Set case.CaseId = "UT-FHIRIN-" _ $JOB _ "-" _ $INCREMENT(^||Shutter.Test.FHIRInstall)
    Set case.Event = "transfer", case.FailureKind = "delivery_failed", case.FailureText = "made up", case.EncounterId = "V1001"
    Set case.PatientId = "MRN-UT1", case.PatientIdAuthority = "HOSP", case.Receiver = ..#RECEIVER, case.State = "gated", case.Mode = "rules"
    Set case.OperationKey = "PAS^HOSP^MRN-UT1^V1001^transfer^" _ case.CaseId, case.Disposition = "resend"
    Set case.EventTime = "2026-11-14T10:30:00Z"
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Set case.OpenedAt = now, case.UpdatedAt = now
    Do $$$AssertStatusOK(case.%Save(), "the case is saved")
    Set i%Made(case.%Id()) = ""
    Set snapshot = ##class(Shutter.Store.Snapshot).Begin(case)
    Do $$$AssertStatusOK(snapshot.Seal({"fhir": {"kind": "fhir_r4", "capability": {"http_status": 200, "software": (software)}}}), "the snapshot is sealed")
    Do $$$AssertStatusOK(case.SetSnapshot(snapshot), "and is the case's current one")
}

/// A production that never runs, with one item of the site's own on the writer's class.
Method MakeProduction() As %Status
{
    Do ..RemoveProduction()
    Set p = ##class(Ens.Config.Production).%New()
    Set p.Name = ..#PRODUCTION
    Set i = ##class(Ens.Config.Item).%New()
    Set i.Name = "Site Out", i.ClassName = "Shutter.Operation.FHIRExecute", i.PoolSize = 1, i.Enabled = 1, i.Production = p
    Set s = ##class(Ens.Config.Setting).%New(), s.Target = "Adapter", s.Name = "HTTPServer", s.Value = "their.example.org"
    Do i.Settings.Insert(s)
    Do p.Items.Insert(i)
    Set sc = p.%Save() Quit:$$$ISERR(sc) sc
    // A production is a compiled class, as a site's is: the engine tells that class of every change after the first.
    Set sc = p.SaveToClass() Quit:$$$ISERR(sc) sc
    Kill p
    Quit $SYSTEM.OBJ.Compile(..#PRODUCTION, "ck-d")
}

/// Whether the scratch production's class holds an item of that name in its definition.
Method ClassHolds(name As %String) As %Boolean
{
    Set x = ##class(%Dictionary.XDataDefinition).%OpenId(..#PRODUCTION _ "||ProductionDefinition")
    Quit:'$ISOBJECT(x) 0
    Quit x.Data.Read(1000000) [ ("Name=""" _ name _ """")
}

Method RemoveProduction()
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    If $ISOBJECT(p) {
        For i = p.Items.Count():-1:1 {
            Set id = p.Items.GetAt(i).%Id()
            Do p.Items.RemoveAt(i)
            Do:id'="" ##class(Ens.Config.Item).%DeleteId(id)
        }
        Kill p
        Do ##class(Ens.Config.Production).%DeleteId(..#PRODUCTION)
    }
    If ##class(%Dictionary.ClassDefinition).%ExistsId(..#PRODUCTION) Do $SYSTEM.OBJ.Delete(..#PRODUCTION, "-d")
}

/// The scratch production's item, or "".
Method Item(p As Ens.Config.Production, name As %String) As Ens.Config.Item
{
    For i = 1:1:p.Items.Count() { If p.Items.GetAt(i).Name = name Return p.Items.GetAt(i) }
    Quit ""
}

/// The scratch production's item names, sorted.
Method ItemNames() As %String
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION), out = ""
    Quit:'$ISOBJECT(p) ""
    For i = 1:1:p.Items.Count() Set names(p.Items.GetAt(i).Name _ " " _ i) = p.Items.GetAt(i).Name
    Set key = ""
    For {
        Set key = $ORDER(names(key), 1, name)
        Quit:key=""
        Set out = out _ $SELECT(out = "": "", 1: ",") _ name
    }
    Quit out
}

/// An item's class, pool size, enabled flag and category.
Method Shape(name As %String) As %String
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    Set item = ..Item(p, name)
    Quit:'$ISOBJECT(item) ""
    Quit item.ClassName _ "|" _ item.PoolSize _ "|" _ item.Enabled _ "|" _ item.Category
}

/// An item's settings as "Target:Name=Value" joined by ";", sorted.
Method Settings(name As %String) As %String
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION), out = ""
    Set item = ..Item(p, name)
    Quit:'$ISOBJECT(item) "no item"
    For j = 1:1:item.Settings.Count() { Set one = item.Settings.GetAt(j), rows(one.Target _ ":" _ one.Name _ "=" _ one.Value _ $CHAR(1) _ j) = "" }
    Set key = ""
    For {
        Set key = $ORDER(rows(key))
        Quit:key=""
        Set out = out _ $SELECT(out = "": "", 1: ";") _ $PIECE(key, $CHAR(1))
    }
    Quit out
}

/// The rows of Ens_Config.Item the scratch production holds whose name starts so.
Method ItemRows(prefix As %String) As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Config.Item WHERE Production = ? AND Name %STARTSWITH ?", ..#PRODUCTION, prefix)
    Quit $SELECT(rs.%Next(): +rs.%GetData(1), 1: -1)
}

/// How many of the four items Shutter's own production holds: none, on an install where no site placed them.
Method OwnFhirItems() As %Integer
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens_Config.Item WHERE Production = ? AND Name IN ('FHIR Receiver', 'FHIR Out', 'FHIR Gate', 'FHIR Verifier')", ##class(Shutter.Setup).ProductionName())
    Quit $SELECT(rs.%Next(): +rs.%GetData(1), 1: -1)
}

/// Takes one item out of the scratch production, as a rewrite of the definition would.
Method DropItem(name As %String)
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    For i = p.Items.Count():-1:1 {
        Continue:p.Items.GetAt(i).Name'=name
        Set id = p.Items.GetAt(i).%Id()
        Do p.Items.RemoveAt(i)
        Do:id'="" ##class(Ens.Config.Item).%DeleteId(id)
    }
    Do $$$AssertStatusOK(p.%Save(), name _ " is taken out")
}

Method AddItem(name As %String, class As %String)
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    Set i = ##class(Ens.Config.Item).%New()
    Set i.Name = name, i.ClassName = class, i.PoolSize = 1, i.Enabled = 1, i.Production = p
    Do p.Items.Insert(i)
    Do $$$AssertStatusOK(p.%Save(), name _ " is added on " _ class)
}

Method Enable(name As %String, enabled As %Boolean)
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    Set item = ..Item(p, name)
    Set item.Enabled = enabled
    Do $$$AssertStatusOK(p.%Save(), name _ $SELECT(enabled: " is enabled", 1: " is disabled"))
}

/// Sets one setting of an item by hand, as a person does in the portal.
Method SetSetting(name As %String, target As %String, setting As %String, value As %String)
{
    Set p = ##class(Ens.Config.Production).%OpenId(..#PRODUCTION)
    Set item = ..Item(p, name)
    For j = item.Settings.Count():-1:1 {
        Set one = item.Settings.GetAt(j)
        If (one.Target = target) && (one.Name = setting) Do item.Settings.RemoveAt(j)
    }
    Set s = ##class(Ens.Config.Setting).%New(), s.Target = target, s.Name = setting, s.Value = value
    Do item.Settings.Insert(s)
    Do $$$AssertStatusOK(p.%Save(), name _ ": " _ setting _ " is set to " _ value)
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

}
