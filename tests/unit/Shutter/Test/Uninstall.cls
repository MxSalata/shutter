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

/// A namespace that cannot be read for items refuses the uninstall with the reason: it is never taken for one with none.
Method TestAnUnreadNamespaceRefuses()
{
    Set refused = ##class(Shutter.Util.Uninstall).Refusal($LISTBUILD("SHUTTERNOSUCHNS"))
    Do $$$AssertTrue(refused [ "could not be read", "refused: " _ refused)
    Do $$$AssertTrue(refused [ "SHUTTERNOSUCHNS (", "the namespace named with the reason")
}

/// A namespace that cannot be entered by design is skipped, while a query that fails in one that was entered still refuses.
Method TestAnUnenterableNamespaceIsSkipped()
{
    Set u = "Shutter.Util.Uninstall"
    Do $$$AssertEquals($CLASSMETHOD(u, "Unenterable", "%ALL"), 1, "the configuration's %ALL")
    Do $$$AssertEquals($CLASSMETHOD(u, "Unenterable", "%SYS"), 0, "a mounted namespace is read")
    Do $$$AssertEquals($CLASSMETHOD(u, "EntrySkipped", 1, "<NAMESPACE>"), 1, "a configured one that cannot be entered")
    Do $$$AssertEquals($CLASSMETHOD(u, "EntrySkipped", 0, "<NAMESPACE>"), 0, "one that is not configured")
    Do $$$AssertEquals($CLASSMETHOD(u, "EntrySkipped", 1, "<PROTECT>"), 0, "an entry this user is refused")
    // The refusal may still name the suite's own Downstream.Test classes when they are loaded beside the product; %ALL adds nothing to it.
    Do $$$AssertNotTrue(##class(Shutter.Util.Uninstall).Refusal($LISTBUILD("%ALL")) [ "%ALL", "%ALL is not read, so no namespace is refused")
    Kill own
    Set found = ""
    Set problem = $CLASSMETHOD(u, "ForeignItems", $NAMESPACE, $NAMESPACE, "Shutter.Production", .own, .found, "SELECT Production, Name, ClassName FROM Shutter_Test.NoSuchTable")
    Do $$$AssertTrue(problem [ "SQLCODE", "a failed query in an entered namespace refuses: " _ problem)
    Set found = ""
    Do $$$AssertEquals($CLASSMETHOD(u, "ForeignItems", "%ALL", $NAMESPACE, "Shutter.Production", .own, .found), "", "and %ALL gives no reason")
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

/// The demo's class prefixes are Shutter's only in its own namespace running Shutter.Production. In a hospital's namespace
/// (Shutter's items inside the site's production, or a watched one) a class or production called Hospital. or Downstream.
/// is the site's: its messages, its log lines and its production stay.
Method TestClassPrefixesInAHospitalsNamespace()
{
    Set u = "Shutter.Util.Uninstall"
    Do $$$AssertEquals($CLASSMETHOD(u, "ClassPrefixes", 1), "Shutter.,Hospital.,Downstream.", "Shutter's own namespace")
    Do $$$AssertEquals($CLASSMETHOD(u, "ClassPrefixes", 0), "Shutter.", "a hospital's namespace")
    Do $$$AssertEquals($CLASSMETHOD(u, "OwnClass", "Hospital.ADT.Message", 0), 0, "a hospital's message class there")
    Do $$$AssertEquals($CLASSMETHOD(u, "OwnClass", "Shutter.Intake.Forward", 0), 1, "the forward, anywhere")
    Do $$$AssertEquals($CLASSMETHOD(u, "OwnClass", "Hospital.Production", 1), 1, "the demo hospital's, in Shutter's namespace")
    Do $$$AssertEquals($CLASSMETHOD(u, "PrefixWhere", "SourceClass", 0), "SourceClass %STARTSWITH 'Shutter.'", "the query in a hospital's namespace")
    Do $$$AssertEquals($CLASSMETHOD(u, "PrefixWhere", "X", 1), "X %STARTSWITH 'Shutter.' OR X %STARTSWITH 'Hospital.' OR X %STARTSWITH 'Downstream.'", "the query in Shutter's own")
    // A site production called Hospital. that Shutter's items went into is not taken whole, so a hand-added gate there refuses.
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Hospital.Path.Production", "My Gate", "Shutter.Operation.Gate", "Hospital.Path.Production", "", "", 0), 0, "a hospital's production named like the demo's")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Hospital.Production", "Gate", "Hospital.Router", "Shutter.Production", "", "", 0), 1, "the demo hospital's definition in Shutter's namespace")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakenByUninstall", "Hospital.Production", "Shutter Forwarder", "Shutter.Intake.Forwarder", "Site.Production", "", "", 0), 1, "the module's own Hospital.Production, compiled in a hospital's namespace")
}

/// The package manager removes the Hospital and Downstream packages whole, so a class of the site's in either would go with
/// them: the uninstall refuses over it. Only a class the module's tree has, or one generated from such a class, is the module's.
Method TestSiteClassesInTheDemoPackages()
{
    Set u = "Shutter.Util.Uninstall"
    Set module("Hospital.Production") = 1, module("Downstream.API") = 1
    Do $$$AssertEquals($CLASSMETHOD(u, "SiteClass", "Hospital.SiteNote", "", .module), 1, "a site's class in the Hospital package")
    Do $$$AssertEquals($CLASSMETHOD(u, "SiteClass", "Downstream.Mine.Thing", "", .module), 1, "and in a package under Downstream")
    Do $$$AssertEquals($CLASSMETHOD(u, "SiteClass", "Hospital.Production", "", .module), 0, "the module's own")
    Do $$$AssertEquals($CLASSMETHOD(u, "SiteClass", "Hospital.Production.Thread1", "Hospital.Production.CLS", .module), 0, "one generated from the module's")
    Do $$$AssertEquals($CLASSMETHOD(u, "SiteClass", "Hospital.SiteNote.Thread1", "Hospital.SiteNote.CLS", .module), 1, "one generated from the site's")
    Do $$$AssertEquals($CLASSMETHOD(u, "SiteClass", "HospitalTrust.Note", "", .module), 0, "a package that begins alike")
    Do $$$AssertEquals($CLASSMETHOD(u, "SiteClass", "Site.Note", "", .module), 0, "another package: the package manager leaves it")
}

/// The module's demo classes are known whether or not the tree it was loaded from is still on disk, and every one is compiled.
Method TestModuleClassesAreKnown()
{
    Set u = "Shutter.Util.Uninstall"
    Do $CLASSMETHOD(u, "ModuleClasses", .module)
    Do $$$AssertTrue($DATA(module("Hospital.Production")) && $DATA(module("Downstream.API")) && $DATA(module("Hospital.Operation.DownstreamOut")), "the tree's classes, subpackages too")
    Set list = $LISTFROMSTRING($PARAMETER(u, "DEMOCLASSES")), missing = ""
    For i = 1:1:$LISTLENGTH(list) If '##class(%Dictionary.CompiledClass).%ExistsId($LIST(list, i)) Set missing = missing _ " " _ $LIST(list, i)
    Do $$$AssertEquals(missing, "", "every class the fallback list names is compiled")
    Set name = ""
    For { Set name = $ORDER(module(name)) Quit:name=""  If '$LISTFIND(list, name) Set missing = missing _ " " _ name }
    Do $$$AssertEquals(missing, "", "the fallback list names every demo class of the tree")
}

/// What goes with the uninstall's two writes outside the messages (a search table's registration, an extent definition): in
/// a hospital's namespace only Shutter.'s classes and the module's own demo classes, never a site's called Hospital. there.
Method TestWhatTheExtentAndSearchTableStepsTake()
{
    Set u = "Shutter.Util.Uninstall"
    Set module("Hospital.Production") = 1
    Do $$$AssertEquals($CLASSMETHOD(u, "TakesClass", "Hospital.SiteSearch", 0, .module), 0, "a site's search table in a hospital's namespace")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakesClass", "Hospital.Production", 0, .module), 1, "the module's own class there")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakesClass", "Shutter.Index.HL7", 0, .module), 1, "Shutter's, anywhere")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakesClass", "Hospital.Anything", 1, .module), 1, "the demo's prefixes in Shutter's own namespace")
    Do $$$AssertEquals($CLASSMETHOD(u, "TakesClass", "EnsLib.HL7.SearchTable", 1, .module), 0, "the engine's, never")
}

/// The messages that go with Shutter's items: to or from one of them, by name, a quote in a name kept as data.
Method TestItemWhere()
{
    Set u = "Shutter.Util.Uninstall"
    Do $$$AssertEquals($CLASSMETHOD(u, "ItemWhere", ""), "", "no items, nothing more")
    Do $$$AssertEquals($CLASSMETHOD(u, "ItemWhere", $LISTBUILD("Case Workflow", "Shutter Approvers")), " OR SourceConfigName IN ('Case Workflow','Shutter Approvers') OR TargetConfigName IN ('Case Workflow','Shutter Approvers')", "both ends of a message")
    Do $$$AssertEquals($CLASSMETHOD(u, "ItemWhere", $LISTBUILD("It's")), " OR SourceConfigName IN ('It''s') OR TargetConfigName IN ('It''s')", "a quote doubled")
}

/// In a site's production a message to an item named like Shutter's goes only in one of Shutter's sessions: a header of
/// another production with the same item name stays. Rows of the test's own, in two sessions of their own.
Method TestMessagesOfAnotherProductionStay()
{
    Set u = "Shutter.Util.Uninstall", base = 2000000000 + $RANDOM(100000000)
    Set ids = ""
    For row = $LISTBUILD(base, "Shutter.Msg.GateRequest", "Shutter API", "Gate"), $LISTBUILD(base, "EnsLib.HL7.Message", "Case Intake", "Gate"), $LISTBUILD(base + 1, "EnsLib.HL7.Message", "Site Router", "Gate") {
        Set h = ##class(Ens.MessageHeader).%New()
        Set h.SessionId = $LIST(row, 1), h.MessageBodyClassName = $LIST(row, 2), h.SourceConfigName = $LIST(row, 3), h.TargetConfigName = $LIST(row, 4)
        Do $$$AssertStatusOK(h.%Save(), "a header of the test's")
        Set ids = ids _ $LISTBUILD(h.%Id())
    }
    Set selected = ""
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Ens.MessageHeader WHERE ID IN (" _ $LISTTOSTRING(ids) _ ") AND (" _ $CLASSMETHOD(u, "MessageWhere", 0, $LISTBUILD("Gate")) _ ") ORDER BY ID")
    Do $$$AssertTrue(rs.%SQLCODE >= 0, "the clause runs: " _ rs.%SQLCODE _ " " _ rs.%Message)
    While rs.%Next() { Set selected = selected _ $LISTBUILD(rs.%GetData(1)) }
    Do $$$AssertEquals($LISTTOSTRING(selected), $LISTTOSTRING($LIST(ids, 1, 2)), "Shutter's session only, not another production's Gate")
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM Ens.MessageHeader WHERE ID IN (" _ $LISTTOSTRING(ids) _ ") AND (" _ $CLASSMETHOD(u, "MessageWhere", 1, $LISTBUILD("Gate")) _ ")")
    Do rs.%Next()
    Do $$$AssertEquals(rs.%GetData(1), 3, "in Shutter's own namespace, by the name alone")
    For i = 1:1:$LISTLENGTH(ids) Do ##class(Ens.MessageHeader).%DeleteId($LIST(ids, i))
}

/// The rows of Shutter's business processes are chosen by class in SQL, none opened: a run of Shutter's and a router's,
/// rows of the test's own, and only the first is selected.
Method TestProcessesSelectedByClass()
{
    Set u = "Shutter.Util.Uninstall"
    Do $$$AssertEquals($CLASSMETHOD(u, "RowClass", "~Shutter.Process.CaseWorkflow~"), "Shutter.Process.CaseWorkflow", "the row's class")
    Do $$$AssertEquals($CLASSMETHOD(u, "RowClass", "~Ens.BusinessProcessBPL~Site.Process~"), "Site.Process", "the last of a chain")
    Set ours = ##class(Shutter.Process.CaseWorkflow).%New("Case Workflow"), router = ##class(EnsLib.MsgRouter.RoutingEngine).%New("Site Router")
    Do $$$AssertStatusOK(ours.%Save(), "a run of Shutter's")
    Do $$$AssertStatusOK(router.%Save(), "a router's")
    Set selected = "", t0 = $ZHOROLOG
    Set rs = ##class(%SQL.Statement).%ExecDirect(, $CLASSMETHOD(u, "ProcessQuery", 0))
    Do $$$AssertTrue(rs.%SQLCODE >= 0, "the query runs: " _ rs.%SQLCODE _ " " _ rs.%Message)
    While rs.%Next() { Set:$LISTFIND($LISTBUILD(ours.%Id(), router.%Id()), rs.%GetData(1)) selected = selected _ $LISTBUILD(rs.%GetData(1)) }
    Do $$$LogMessage("ProcessQuery read the table in " _ ($ZHOROLOG - t0) _ " s")
    Do $$$AssertEquals($LISTTOSTRING(selected), ours.%Id(), "Shutter's run only")
    Do ##class(Ens.BusinessProcess).%DeleteId(ours.%Id()), ##class(Ens.BusinessProcess).%DeleteId(router.%Id())
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

/// A step that fails stops the run there: the steps after it, the Globals step last of all, are not run, so the
/// configuration a run again reads stays, and the answer names the step. Stub steps of this class, on a marker of the test's.
Method TestAFailedStepStopsTheRun()
{
    Set u = "Shutter.Util.Uninstall"
    Set ^Shutter.Config("uninstallTest") = 1
    Set out = {"removed": [], "kept": [], "errors": [], "stopped": ""}
    Do $CLASSMETHOD(u, "RunSteps", out, $LISTBUILD("Fine", "Fails", "Globals"), $CLASSNAME())
    Do $$$AssertEquals(out.stopped, "Fails", "the failed step is named")
    Do $$$AssertEquals(out.errors.%Get(0), "Fails: the stub step failed", "and why")
    Do $$$AssertEquals($GET(^Shutter.Config("uninstallTest")), 1, "the configuration survives: the Globals step did not run")
    Do $$$AssertEquals(out.removed.%Size(), 1, "the step before it ran")
    Do $$$AssertTrue(out.kept.%Get(0) [ "Globals", "the steps left are said")
    Set out = {"removed": [], "kept": [], "errors": [], "stopped": ""}
    Do $CLASSMETHOD(u, "RunSteps", out, $LISTBUILD("Thrown", "Globals"), $CLASSNAME())
    Do $$$AssertEquals(out.stopped, "Thrown", "a step that throws stops it too")
    Do $$$AssertEquals($GET(^Shutter.Config("uninstallTest")), 1, "and the configuration survives")
    Set out = {"removed": [], "kept": [], "errors": [], "stopped": ""}
    Do $CLASSMETHOD(u, "RunSteps", out, $LISTBUILD("Fine", "Globals"), $CLASSNAME())
    Do $$$AssertEquals(out.stopped, "", "with no failure nothing is named")
    Do $$$AssertEquals($DATA(^Shutter.Config("uninstallTest")), 0, "and the last step ran")
    Kill ^Shutter.Config("uninstallTest")
}

/// The plan names the alert intake's global in each watched namespace that holds it, and the embedding model's folder
/// under Shutter's own, and changes neither. Another namespace (Watched) stands in for a watched one, with a row and a
/// folder of the test's.
Method TestThePlanListsTheIntakeAndTheCache()
{
    Set u = "Shutter.Util.Uninstall", ns = ..Watched()
    Set watched = $DATA(^Shutter.Config("onboardKept", ns))
    Set:'watched ^Shutter.Config("onboardKept", ns) = 1
    Set ^|ns|Shutter.AlertIntake("seen", 999999981, "Uninstall Test") = 1
    Set cache = $CLASSMETHOD(u, "CacheFolder"), made = 0
    If '##class(%File).DirectoryExists(cache) Set made = ##class(%File).CreateDirectoryChain(cache)
    Set plan = ##class(%DynamicObject).%FromJSON($CLASSMETHOD(u, "Plan"))
    Set removes = "", it = plan.removes.%GetIterator()
    While it.%GetNext(, .line) { Set removes = removes _ $LISTBUILD(line) }
    Do $$$AssertTrue($LISTFIND(removes, "The global ^Shutter.AlertIntake in " _ ns), "the intake's global in the watched namespace")
    Do $$$AssertTrue($LISTFIND(removes, "The folder " _ cache), "the embedding model's folder")
    Do $$$AssertEquals($GET(^|ns|Shutter.AlertIntake("seen", 999999981, "Uninstall Test")), 1, "the row is still there")
    Do $$$AssertTrue(##class(%File).DirectoryExists(cache), "and so is the folder")
    Kill ^|ns|Shutter.AlertIntake("seen", 999999981, "Uninstall Test")
    Kill:'watched ^Shutter.Config("onboardKept", ns)
    Do:made ##class(%File).RemoveDirectory(cache)
}

/// A run's intake step in a watched namespace takes the alert intake's global and nothing else there: another of
/// Shutter's names and a site's global stay. Another namespace (Watched) stands in for it, through a stub step.
Method TestAStubRunTakesTheIntakeOnly()
{
    Set ns = ..Watched()
    Set ^|ns|Shutter.AlertIntake("handed", 999999982, "Uninstall Test|CTL0001") = 1
    Set ^|ns|Shutter.UninstallTestKeep = 1, ^|ns|UninstallTestKeep = 1
    Set out = {"removed": [], "kept": [], "errors": [], "stopped": ""}
    Do ##class(Shutter.Util.Uninstall).RunSteps(out, $LISTBUILD("Intake"), $CLASSNAME())
    Do $$$AssertEquals(out.stopped, "", "the step ran")
    Do $$$AssertEquals($DATA(^|ns|Shutter.AlertIntake), 0, "the intake's global is gone")
    Do $$$AssertEquals(out.removed.%Get(0), "The global ^Shutter.AlertIntake in " _ ns, "and said")
    Do $$$AssertEquals($GET(^|ns|Shutter.UninstallTestKeep), 1, "another global under Shutter's name stays")
    Do $$$AssertEquals($GET(^|ns|UninstallTestKeep), 1, "and the site's")
    Kill ^|ns|Shutter.UninstallTestKeep, ^|ns|UninstallTestKeep
}

/// The plan names the page question store, with how many questions it holds, and takes none of them.
Method TestThePlanListsThePageQuestionStore()
{
    Set u = "Shutter.Util.Uninstall", t = "Shutter.Test.PageQuestionPurge"
    Set qid = $CLASSMETHOD(t, "Ask", "u", "1900-01-01T00:00:00Z", .key)
    Set plan = ##class(%DynamicObject).%FromJSON($CLASSMETHOD(u, "Plan"))
    Set removes = "", it = plan.removes.%GetIterator()
    While it.%GetNext(, .line) { Set removes = removes _ $LISTBUILD(line) }
    Do $$$AssertTrue($LISTFIND(removes, $CLASSMETHOD(u, "PageQuestionsLine", $CLASSMETHOD(u, "PageQuestionCount"))), "the page question store")
    Do $$$AssertEquals($CLASSMETHOD(t, "Left", qid, key), "1|1|1", "and the question, its run and its tool call are still there")
    Do $CLASSMETHOD(t, "Clear", $LISTBUILD(qid), $LISTBUILD(key))
}

/// A run's page question step takes the questions with their runs and tool calls: through a stub step that takes only those
/// asked before 1900-01-02, an old question of the test's goes and a new one stays.
Method TestAStubRunTakesThePageQuestions()
{
    Set u = "Shutter.Util.Uninstall", t = "Shutter.Test.PageQuestionPurge"
    Set old = $CLASSMETHOD(t, "Ask", "x", "1900-01-01T00:00:00Z", .oldKey)
    Set new = $CLASSMETHOD(t, "Ask", "y", ##class(Shutter.Util.Time).NowUTC(), .newKey)
    Set out = {"removed": [], "kept": [], "errors": [], "stopped": ""}
    Do $CLASSMETHOD(u, "RunSteps", out, $LISTBUILD("PageQuestions"), $CLASSNAME())
    Do $$$AssertEquals(out.stopped, "", "the step ran")
    Do $$$AssertEquals(out.removed.%Get(0), $CLASSMETHOD(u, "PageQuestionsLine", 1), "and said what it took")
    Do $$$AssertEquals($CLASSMETHOD(t, "Left", old, oldKey), "0|0|0", "the question, its run and its tool call are gone")
    Do $$$AssertEquals($CLASSMETHOD(t, "Left", new, newKey), "1|1|1", "the one the stub leaves stays")
    Do $CLASSMETHOD(t, "Clear", $LISTBUILD(old, new), $LISTBUILD(oldKey, newKey))
}

/// The stub of the page question step: only questions asked before 1900-01-02, the test's own.
ClassMethod TakePageQuestions(out As %DynamicObject)
{
    Do ##class(Shutter.Util.Uninstall).TakePageQuestions(out, "1900-01-02T00:00:00Z")
}

/// A namespace other than the test's own, to stand in for a watched one.
ClassMethod Watched() As %String
{
    Quit $SELECT($NAMESPACE '= "USER": "USER", 1: "%SYS")
}

/// The stub of the intake step, in that namespace.
ClassMethod TakeIntake(out As %DynamicObject)
{
    Do ##class(Shutter.Util.Uninstall).TakeIntake(..Watched(), out)
}

ClassMethod TakeFine(out As %DynamicObject)
{
    Do out.removed.%Push("fine")
}

ClassMethod TakeFails(out As %DynamicObject)
{
    Do out.errors.%Push("Fails: the stub step failed")
}

ClassMethod TakeThrown(out As %DynamicObject)
{
    Throw ##class(%Exception.General).%New("the stub step threw")
}

/// The stub of the last step: only the test's marker goes.
ClassMethod TakeGlobals(out As %DynamicObject)
{
    Kill ^Shutter.Config("uninstallTest")
}

}
