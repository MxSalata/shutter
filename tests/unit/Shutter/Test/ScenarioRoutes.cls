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
