/// A production of the site's whose name the module's own packages could take: the install into it is refused, and the
/// uninstall never removes the definition of the production Shutter's items went into.
Class Shutter.Test.SiteProduction Extends %UnitTest.TestCase
{

/// In shape B the uninstall removes Shutter's own production definitions and the demo hospital's, but never the one
/// ProductionName() gives, even when it is called Hospital.Production.
Method TestUninstallKeepsTheProductionShutterWentInto()
{
    Set c = "Shutter.Util.SiteProduction"
    Do $$$AssertEquals($CLASSMETHOD(c, "DefinitionGoes", "Hospital.Production", "Hospital.Production"), 0, "the site's own Hospital.Production, which Shutter's items went into")
    Do $$$AssertEquals($CLASSMETHOD(c, "DefinitionGoes", "Shutter.Production", "Hospital.Production"), 1, "Shutter.Production beside it")
    Do $$$AssertEquals($CLASSMETHOD(c, "DefinitionGoes", "Hospital.Production", "Site.Production"), 1, "the module's Hospital.Production beside another site production")
    Do $$$AssertEquals($CLASSMETHOD(c, "DefinitionGoes", "Hospital.Feed", "Site.Production"), 0, "another Hospital. production in a site's namespace")
    Do $$$AssertEquals($CLASSMETHOD(c, "DefinitionGoes", "Site.Production", "Site.Production"), 0, "the site's production")
    Do $$$AssertEquals($CLASSMETHOD(c, "DefinitionGoes", "Hospital.Production", "Shutter.Production"), 1, "the demo hospital's in Shutter's own namespace")
    Do $$$AssertEquals($CLASSMETHOD(c, "DefinitionGoes", "Hospital.Feed", "Shutter.Production"), 1, "any Hospital. production in Shutter's own namespace")
    Do $$$AssertEquals($CLASSMETHOD(c, "DefinitionGoes", "Shutter.Production", "Shutter.Production"), 1, "Shutter's own production in its own namespace")
    Do $$$AssertEquals($CLASSMETHOD(c, "DefinitionGoes", "Site.Production", "Shutter.Production"), 0, "a site's production in Shutter's namespace")
}

/// The refusal check reads the production Shutter went into as the site's, item by item, even when it is called
/// Hospital.Production: a second gate added there by hand is not taken out, so it is not taken for granted either.
Method TestHandItemInTheSitesHospitalProductionIsNotTaken()
{
    Set u = "Shutter.Util.Uninstall"
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Hospital.Production", "My Gate", "Shutter.Operation.Gate", "Hospital.Production", "", "", 0), 0, "a hand-added item in the site's Hospital.Production")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Hospital.Production", "Gate", "Shutter.Operation.Gate", "Hospital.Production", "Shutter.Operation.Gate", "", 0), 1, "Shutter's own item there")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Hospital.Production", "Shutter Forwarder", "Shutter.Intake.Forwarder", "Site.Production", "", "", 0), 1, "the module's own Hospital.Production beside a site production")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Shutter.Production", "Gate", "Shutter.Operation.Gate", "Shutter.Production", "", "", 0), 1, "Shutter's own production in its own namespace")
}

/// InstallInto and InstallStatus refuse a production in one of the module's packages, before anything is written.
Method TestInstallRefusesTheModulesPackages()
{
    For name = "Hospital.SiteFeedX", "Downstream.SiteFeedX", "hospital.SiteFeedX", "Shutter.SiteFeedX" {
        Set before = $GET(^Shutter.Config("production"))
        Set text = ##class(Shutter.Setup).InstallInto(name, "")
        Do $$$AssertTrue(text [ "package of your own", "InstallInto refuses " _ name _ ": " _ text)
        Set sc = ##class(Shutter.Setup).InstallStatus("", 0, name)
        Do $$$AssertTrue($$$ISERR(sc) && ($SYSTEM.Status.GetErrorText(sc) [ "package of your own"), "InstallStatus refuses " _ name _ ": " _ $SYSTEM.Status.GetErrorText(sc))
        Do $$$AssertEquals($GET(^Shutter.Config("production")), before, "nothing recorded for " _ name)
    }
    Do $$$AssertEquals($CLASSMETHOD("Shutter.Util.SiteProduction", "InstallRefusal", "Site.Production"), "", "a production in a package of the site's")
    Do $$$AssertEquals($CLASSMETHOD("Shutter.Util.SiteProduction", "InstallRefusal", "HospitalFeed.Production"), "", "a package that only begins alike")
}

}
