/// What the uninstall decides by name alone: whose a role, a user, an item, a namespace or a message is. A site's own things
/// that share a name stay. tests/e2e/uninstall_check.py plays the whole of it on a stock instance.
Class Shutter.Test.Uninstall Extends %UnitTest.TestCase
{

Method TestRolesAndResources()
{
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnSecurityName("Shutter_Operator"), 1, "Shutter's role")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnSecurityName("Shutter_Portal"), 1, "the public demo's resource")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnSecurityName("Downstream_API"), 1, "the demo receiver's")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnSecurityName("Shutterbug_Reader"), 0, "a site's that begins alike")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnSecurityName("%All"), 0, "the system's")
}

/// A user goes only with the name and the comment Shutter's installers gave it.
Method TestUsers()
{
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnUser("operator", "Shutter demo user"), 1, "the demo's operator")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnUser("downstream-client", "Used by the production's HTTP operation"), 1, "the demo's client")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnUser("judge", "Shutter public demo user"), 1, "the public demo's")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnUser("forwarder", "Used by the Shutter Forwarder item of Hospital.Production"), 1, "the hospital's forwarder")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnUser("operator", ""), 0, "a site's operator, with no comment")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnUser("operator", "The night shift"), 0, "a site's operator, with its own")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnUser("somebody", "Shutter demo user"), 0, "another name")
}

/// An item goes from a site's production only with a listed name and the class Shutter's production gives that name.
Method TestItems()
{
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnItem("Gate", "Shutter.Operation.Gate", "Shutter.Operation.Gate"), 1, "Shutter's item")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnItem("Shutter Approvers", "EnsLib.Workflow.Operation", "EnsLib.Workflow.Operation"), 1, "one on the engine's own class")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnItem("Gate", "Site.TheirGate", "Shutter.Operation.Gate"), 0, "a site's item of that name")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnItem("LIMS Out", "EnsLib.HL7.Operation.TCPOperation", "EnsLib.HL7.Operation.TCPOperation"), 0, "a name not listed")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnItem("Gate", "Shutter.Operation.Gate", ""), 0, "nothing to compare with")
}

/// The refusal leaves alone only what the uninstall takes: not a second item a site added on one of Shutter's classes.
Method TestWhatTheRefusalLeaves()
{
    Set u = "Shutter.Util.Uninstall"
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Shutter.Production", "My Gate", "Shutter.Operation.Gate", "Shutter.Production", "", "", 0), 1, "a production of the module's own goes whole")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Site.Production", "Gate", "Shutter.Operation.Gate", "Site.Production", "Shutter.Operation.Gate", "", 0), 1, "Shutter's item in the production it went into")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Site.Production", "My Gate", "Shutter.Operation.Gate", "Site.Production", "", "", 0), 0, "a site's second gate there")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Site.Other", "Gate", "Shutter.Operation.Gate", "Site.Production", "Shutter.Operation.Gate", "", 0), 0, "the same name in another production")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Site.Production", "Fwd", "Shutter.Intake.Forwarder", "", "", "Site.Production", 1), 1, "the forwarder the onboarding recorded")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Site.Production", "Second", "Shutter.Intake.Forwarder", "", "", "Site.Production", 0), 0, "a second forwarder by hand beside it")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Site.Other", "Fwd", "Shutter.Intake.Forwarder", "", "", "Site.Production", 1), 0, "a name the onboarding recorded, in another production")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Shutter.Production", "Gate", "Shutter.Operation.Gate", "", "", "", 0), 0, "a production of that name in another namespace")
}

/// The demo's global prefixes go only where the demo was installed, in Shutter's own production.
Method TestGlobalPrefixes()
{
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).GlobalPrefixes(1, "Shutter.Production"), ##class(Shutter.Util.Uninstall).#GLOBALS, "the demo")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).GlobalPrefixes(0, "Shutter.Production"), "^Shutter.", "a site install in a namespace of its own")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).GlobalPrefixes(0, "Site.Production"), "^Shutter.", "into a site's production")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).GlobalPrefixes(1, "Site.Production"), "^Shutter.", "never a site's own, whatever the flag says")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).GlobalPrefixes("", "Shutter.Production"), "^Shutter.", "no flag: nothing says the demo was here")
}

/// A namespace goes only when it is the demo's: its package mapped from Shutter's own code database.
Method TestNamespaces()
{
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnNamespace("HOSPITAL", "USER", "USER"), 1, "the demo's")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnNamespace("HOSPITAL", "", "USER"), 0, "a site's, merely called that")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnNamespace("HOSPITAL", "OTHER", "USER"), 0, "mapped from elsewhere")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnNamespace("PATHOLOGY", "USER", "USER"), 0, "never a watched one")
}

Method TestBodyClasses()
{
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnBodyClass("Shutter.Intake.Forward"), 1, "the forward")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnBodyClass("EnsLib.HL7.Message"), 0, "a site's")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).OwnBodyClass("ShutterTrust.Message"), 0, "a site's that begins alike")
}

Method TestWithout()
{
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).Without("%Developer,Shutter_Approver", $LISTBUILD("Shutter_Approver")), "%Developer", "the site's stays")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).Without("Shutter_Approver", $LISTBUILD("Shutter_Approver")), "", "none left")
    Do $$$AssertEquals(##class(Shutter.Util.Uninstall).Without("%Developer", $LISTBUILD("Shutter_Approver")), "%Developer", "nothing to take")
}

/// A plan changes nothing and answers.
Method TestPlanAnswersAndChangesNothing()
{
    Set before = $GET(^Shutter.Config("version"))
    Set plan = ##class(%DynamicObject).%FromJSON(##class(Shutter.Util.Uninstall).Plan())
    Do $$$AssertTrue(plan.removes.%Size() > 0, "it says what would go")
    Do $$$AssertTrue(plan.keeps.%Size() > 0, "and what stays")
    Do $$$AssertEquals($GET(^Shutter.Config("version")), before, "nothing changed")
}

}
