/// S14 and S26's own parts of the scenario runner: the two demo routes, which a site's production never gets, and the
/// schema the hold waits for, forgotten and imported again each time S26 plays.
Class Shutter.Test.ScenarioRoutes Extends %UnitTest.TestCase
{

Parameter CATEGORY = "MYSITE_2.5.1";

Parameter ROUTE = "Shutter.Scenarios.Route";

Parameter SITE = "Shutter.Scenarios.SiteSchema";

Method OnAfterAllTests() As %Status
{
    If ##class(%Dictionary.CompiledClass).%ExistsId(..#SITE) {
        Do $CLASSMETHOD(..#SITE, "PreventFailures", 0)
        Do $CLASSMETHOD(..#SITE, "Forget", ..#CATEGORY)
    }
    Quit $$$OK
}

/// A file under the fixtures, "" when they are not on this instance.
ClassMethod Fixture(relative As %String) As %String
{
    Set path = ##class(Shutter.Scenarios.Runner).FixturesDir() _ relative
    Quit $SELECT(##class(%File).Exists(path): path, 1: "")
}

Method TestTheRoutesAreForTheDemoAlone()
{
    Do $$$AssertTrue(##class(%Dictionary.CompiledClass).%ExistsId(..#ROUTE), "the route class is compiled")
    Set items = ##class(Shutter.Setup).#INSTALLITEMS
    Do $$$AssertNotTrue(items [ "Other Route In", "a site's production never gets the other route")
    Do $$$AssertNotTrue(items [ "Site Feed In", "nor the site's feed")
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId("Shutter.Production||ProductionDefinition")
    Set text = "" While 'xdata.Data.AtEnd { Set text = text _ xdata.Data.Read(32000) }
    Do $$$AssertTrue(text [ "<Setting Target=""Adapter"" Name=""Routes"">ADT In,Case Intake,Other Route In</Setting>", "the index watches the other route")
    Do $$$AssertTrue(text '[ "<Setting Target=""Host"" Name=""MessageSchemaCategory"">MYSITE", "no item names the category, so the Doctor reports nothing missing on a fresh install")
}

/// S14's message has to reach the index under its type, or the index's named paths may read nothing: a version loaded here
/// types the message, as ADT In's category would, and a schema not loaded leaves it untyped for the hold.
Method TestARouteTypesWhatIsLoadedHere()
{
    Set text = "MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015094500||ADT^A02^ADT_A02|UT1402|P|<v>" _ $CHAR(13) _ "EVN|A02|20261015094500||||20261015094500" _ $CHAR(13) _ "PID|1||MRNUT14^^^HOSP^MR||SYNTH^UT||19910606|F" _ $CHAR(13) _ "PV1|1|I|WARD-C^BAY1^07^HOSP|||WARD-B^BAY2^04^HOSP|||||||||||||ENC-UT14" _ $CHAR(13)
    Set known = ##class(EnsLib.HL7.Message).ImportFromString($REPLACE(text, "<v>", "2.5.1"), .sc)
    Do $$$AssertStatusOK(sc, "the message reads")
    Do $CLASSMETHOD(..#ROUTE, "Typed", known)
    Do $$$AssertEquals(known.DocTypeCategory, "2.5.1", "a version loaded here types it")
    Set op = ##class(Shutter.Util.OperationKey).FromHL7(known, .osc)
    Do $$$AssertStatusOK(osc, "the index's own mapping reads it")
    Do $$$AssertEquals($SELECT($ISOBJECT(op): op.%Get("encounter_id"), 1: ""), "ENC-UT14", "with its visit number")
    Do $CLASSMETHOD(..#SITE, "Forget", ..#CATEGORY)
    Set held = ##class(EnsLib.HL7.Message).ImportFromString($REPLACE(text, "<v>", ..#CATEGORY), .sc)
    Do $$$AssertStatusOK(sc, "the site's message reads")
    Do $CLASSMETHOD(..#ROUTE, "Typed", held)
    Do $$$AssertEquals(held.DocType, "", "a schema not loaded leaves it untyped, for the hold")
}

/// The index's route setting as a site's production gets it: Shutter.Production's, less the demo's route.
Method TestASiteIndexIsNotGivenTheDemoRoute()
{
    Do $$$AssertEquals(##class(Shutter.Setup).SiteRoutes("ADT In,Case Intake,Other Route In"), "ADT In,Case Intake", "the demo's route goes")
    Do $$$AssertEquals(##class(Shutter.Setup).SiteRoutes("ADT In,Case Intake"), "ADT In,Case Intake", "a list without it is left alone")
}

/// A wait may name more than one state, as S26's plan stops at approval in Rules only and goes through in Site policy.
Method TestAWaitCanNameTwoStates()
{
    Set runner = "Shutter.Scenarios.Runner"
    Do $$$AssertTrue($CLASSMETHOD(runner, "StateIs", "blocked", "blocked"), "one state, as every other scenario names")
    Do $$$AssertNotTrue($CLASSMETHOD(runner, "StateIs", "blocked", "resolved"), "not another")
    Do $$$AssertTrue($CLASSMETHOD(runner, "StateIs", "resolved", "awaiting_approval|resolved"), "either of two")
    Do $$$AssertNotTrue($CLASSMETHOD(runner, "StateIs", "approval", "awaiting_approval|resolved"), "not part of one")
    Do $$$AssertNotTrue($CLASSMETHOD(runner, "StateIs", "", "awaiting_approval|resolved"), "and no state is none of them")
}

Method TestARouteRefusesWhatItCannotPlay()
{
    If '##class(%Dictionary.CompiledClass).%ExistsId(..#ROUTE) { Do $$$AssertTrue(0, "no route class") Quit }
    Set error = $CLASSMETHOD(..#ROUTE, "Play", "Other Route In", "/no/such/file.hl7")
    Do $$$AssertTrue(error [ "/no/such/file.hl7", "a file that is not there is named: " _ error)
    Set path = ..Fixture("S14/S14-02-A02.hl7")
    If path = "" { Do $$$AssertTrue(1, "the fixtures are not on this instance") Quit }
    Set error = $CLASSMETHOD(..#ROUTE, "Play", "No Such Route UT", path)
    Do $$$AssertTrue(error [ "No Such Route UT", "an item that is not there is named: " _ error)
}

/// What S26 waits on: the category is absent, the held message's own MSH-12 names it, the import loads it, the message then
/// types and validates under it with its site segment, and forgetting it puts the instance back.
Method TestTheSchemaIsForgottenAndImported()
{
    If '##class(%Dictionary.CompiledClass).%ExistsId(..#SITE) { Do $$$AssertTrue(0, "no site schema class") Quit }
    Set file = ..Fixture("schemas/MYSITE_2.5.1.xml"), held = ..Fixture("S26/S26-02-A02.hl7")
    If (file = "") || (held = "") { Do $$$AssertTrue(1, "the fixtures are not on this instance") Quit }
    Set schemas = "Shutter.Util.Schemas"
    Do $CLASSMETHOD(..#SITE, "Forget", ..#CATEGORY)
    Do $$$AssertNotTrue($CLASSMETHOD(schemas, "Known", ..#CATEGORY), "forgotten, the category is not loaded")
    Set msg = $CLASSMETHOD(..#ROUTE, "Message", held, .error)
    Do $$$AssertEquals(error, "", "the held transfer reads")
    Do $$$AssertEquals($CLASSMETHOD(schemas, "CategoryOf", msg, "Site Feed In"), ..#CATEGORY, "and its MSH-12 names the category, its item naming none")
    Do $$$AssertEquals($CLASSMETHOD(..#SITE, "Import", file), "", "the import takes the fixture")
    Do $$$AssertTrue($CLASSMETHOD(schemas, "Known", ..#CATEGORY), "the category is loaded")
    Set type = ##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType(..#CATEGORY, msg.Name, .tsc)
    Do $$$AssertStatusOK(tsc, "the category has the transfer's structure")
    Do msg.PokeDocType(type)
    Do $$$AssertStatusOK(msg.Validate("dm"), "the transfer validates under it, its site segment included: " _ type)
    Do $CLASSMETHOD(..#SITE, "Forget", ..#CATEGORY)
    Do $$$AssertNotTrue($CLASSMETHOD(schemas, "Known", ..#CATEGORY), "forgotten again")
    Set bad = $CLASSMETHOD(..#SITE, "Import", "/no/such/schema.xml")
    Do $$$AssertTrue(bad '= "", "an import that fails says so: " _ bad)
}

/// The setting for one run: on for the run, then whatever the stored profile says, with the stored profile untouched.
Method TestPreventFailuresIsForTheRun()
{
    If '##class(%Dictionary.CompiledClass).%ExistsId(..#SITE) { Do $$$AssertTrue(0, "no site schema class") Quit }
    Set sp = "Shutter.Store.SiteProfile"
    Set before = $CLASSMETHOD(sp, "Current").%ToJSON(), stored = $CLASSMETHOD(sp, "PreventFailures")
    Do $CLASSMETHOD(..#SITE, "PreventFailures", 1)
    Do $$$AssertTrue($CLASSMETHOD(sp, "PreventFailures"), "on for the run")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Current").%ToJSON(), before, "the stored profile has not moved, so no approval is voided by it")
    Do $CLASSMETHOD(..#SITE, "PreventFailures", 0)
    Do $$$AssertEquals($CLASSMETHOD(sp, "PreventFailures"), stored, "and back to what the profile says")
}

}
