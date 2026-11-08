/// Takes Shutter off an instance: everything the install and the onboarding added, in every namespace, and no production of
/// the site's is stopped. zpm "uninstall iris-shutter" runs it (the module's manifest) and then removes the classes, so a
/// failed run stops the uninstall with the classes still there, and running it again carries on.
/// What it decides by name alone (a role, a resource, a user's comment, an item) is in a small pure method, tested alone;
/// tests/e2e/uninstall_check.py compares a stock instance before the install with the same instance after the uninstall.
Class Shutter.Util.Uninstall
{

/// The prefixes of the globals, and so of the tables and configuration, that are Shutter's with the demo. Without it, only
/// the first is (GlobalPrefixes).
Parameter GLOBALS = "^Shutter.,^Downstream.,^Hospital.,^Wards.";

/// The comments Shutter's installers give the users they make. A user of the same name without one of them is the site's.
Parameter USERCOMMENTS = "Shutter demo user|Used by the production's HTTP operation|Shutter public demo user|Used by the Shutter Forwarder item of Hospital.Production";

/// The users Shutter's installers can make.
Parameter USERNAMES = "operator,approver,forwarder,downstream-client,demo,demo-trace,judge";

/// The credentials Shutter's installers can store in its own namespace.
Parameter CREDENTIALS = "DownstreamAPI,ShutterIntake";

/// The body classes whose messages are Shutter's own, wherever they are.
Parameter BODYCLASSES = "Shutter.,Hospital.,Downstream.";

/// What an uninstall would do here, changing nothing. Needs what the uninstall needs.
ClassMethod Plan() As %String [ SqlProc ]
{
    Set out = {"namespace": ($NAMESPACE), "removes": [], "keeps": [], "refused": ""}
    Set out.refused = ..Refusal()
    Set production = ##class(Shutter.Setup).ProductionName()
    Set ns = ""
    For { Set ns = $ORDER(^Shutter.Config("onboard", ns)) Quit:ns=""  Do out.removes.%Push("The onboarding of " _ ns _ ": its production " _ $GET(^Shutter.Config("onboard", ns)) _ " is updated and not stopped") }
    If production = "Shutter.Production" {
        Do out.removes.%Push("Shutter.Production, stopped, in " _ $NAMESPACE)
    } Else {
        Do out.removes.%Push("Shutter's items in " _ production _ ", which is updated and not stopped")
        Do out.removes.%Push("The definition of Shutter.Production, which never ran here")
    }
    Set demo = ..DemoNamespaces()
    For i = 1:1:$LISTLENGTH(demo) Do out.removes.%Push("The namespace " _ $LIST(demo, i) _ " and its databases, made for the demo")
    Set list = ..Applications()
    For i = 1:1:$LISTLENGTH(list) Do out.removes.%Push("The web application " _ $LIST(list, i))
    Set list = ..NamesLike("Security.Roles")
    For i = 1:1:$LISTLENGTH(list) Do out.removes.%Push("The role " _ $LIST(list, i))
    Set list = ..NamesLike("Security.Resources")
    For i = 1:1:$LISTLENGTH(list) Do out.removes.%Push("The resource " _ $LIST(list, i))
    For name = "Shutter retention", "Shutter message purge" { If ..TaskId(name) '= "" Do out.removes.%Push("The task " _ name) }
    Do ..UsersPlan(out)
    Do out.removes.%Push("Every case, approval, incident and setting of Shutter's, and the folders under " _ ..Folder() _ ": cases are not kept, so export what you must keep first")
    Do out.keeps.%Push("The namespace " _ $NAMESPACE _ " itself and its databases: it may hold other things, and removing it is yours to do")
    Do out.%Set("ok", out.refused = "", "boolean")
    Quit out.%ToJSON()
}

/// The uninstall the module's manifest invokes: its answer written out, an error when anything stayed that should have gone.
ClassMethod ModuleStatus() As %Status
{
    Set tlevel = $TLEVEL
    Set answer = ##class(%DynamicObject).%FromJSON(..Run())
    While $TLEVEL < tlevel { TSTART }
    Set it = answer.removed.%GetIterator()
    While it.%GetNext(, .line) { Write !, "  removed: ", line }
    Set it = answer.kept.%GetIterator()
    While it.%GetNext(, .line) { Write !, "  kept: ", line }
    Write !
    If answer.ok Quit $$$OK
    Quit $$$ERROR($$$GeneralError, "The uninstall stopped with Shutter's classes still in place, and can be run again: " _ answer.errors.%ToJSON())
}

/// Does it. Refused, with nothing changed, when a production Shutter did not wire still names one of its classes, since
/// that production would not start once the classes are gone. Returns {ok, removed, kept, errors} as JSON.
ClassMethod Run() As %String [ SqlProc ]
{
    Set out = {"namespace": ($NAMESPACE), "removed": [], "kept": [], "errors": []}
    Do out.%Set("ok", 0, "boolean")
    If '$SYSTEM.Security.Check("%Admin_Manage", "USE") || '$SYSTEM.Security.Check("%Admin_Secure", "USE") {
        Do out.errors.%Push("The uninstall changes the instance's configuration and security: it needs a user holding %Admin_Manage and %Admin_Secure")
        Quit out.%ToJSON()
    }
    Set refused = ..Refusal()
    If refused '= "" Do out.errors.%Push(refused) Quit out.%ToJSON()
    // Starting or stopping a production commits every open transaction; IPM's level is put back by ModuleStatus.
    While $TLEVEL { TCOMMIT }
    For step = "Watched", "Production", "Portal", "DemoNamespacesOff", "Workflow", "Messages", "Interop", "Provider", "Tasks", "Applications", "Grants", "Users", "Roles", "Resources", "Folders", "Globals" {
        Try {
            Do $CLASSMETHOD($CLASSNAME(), "Take" _ step, out)
        } Catch ex {
            Do out.errors.%Push(step _ ": " _ ex.DisplayString())
        }
    }
    Do out.%Set("ok", out.errors.%Size() = 0, "boolean")
    Quit out.%ToJSON()
}

/// Whether a role or resource is Shutter's, by its name alone.
ClassMethod OwnSecurityName(name As %String) As %Boolean
{
    Quit ($EXTRACT(name, 1, 8) = "Shutter_") || (name = "Downstream_API") || (name = "Downstream_Admin") || (name = "Wards_API")
}

/// Whether a user is one Shutter's installers made: its name and its comment. A site's own "operator" stays.
ClassMethod OwnUser(name As %String, comment As %String) As %Boolean
{
    If '$LISTFIND($LISTFROMSTRING(..#USERNAMES), name) Quit 0
    Quit $LISTFIND($LISTFROMSTRING(..#USERCOMMENTS, "|"), comment) > 0
}

/// Whether an item of the site's production is one Shutter's install put there: a listed name, and the class Shutter's own
/// production gives that name. A site's item that happens to share the name, with another class, stays.
ClassMethod OwnItem(name As %String, className As %String, ownClassName As %String) As %Boolean
{
    If ownClassName = "" Quit 0
    If '$LISTFIND($LISTFROMSTRING(##class(Shutter.Setup).#INSTALLITEMS), name) Quit 0
    Quit className = ownClassName
}

/// Whether a namespace with this name was made for the demo: it maps the demo's package from this namespace's own code
/// database. A site's namespace that is merely called HOSPITAL has no such mapping, and stays.
ClassMethod OwnNamespace(ns As %String, mappedFrom As %String, codeDatabase As %String) As %Boolean
{
    If '$LISTFIND($LISTBUILD("HOSPITAL", "RECORDS"), ns) Quit 0
    Quit (mappedFrom '= "") && ($ZCONVERT(mappedFrom, "U") = $ZCONVERT(codeDatabase, "U"))
}

/// The prefixes whose globals and tables go here: the demo's only where the demo was installed, in Shutter's own production.
/// Elsewhere a global called ^Hospital.Config or ^Wards.Beds is the site's.
ClassMethod GlobalPrefixes(demo As %Boolean, production As %String) As %String
{
    If demo && (production = "Shutter.Production") Quit ..#GLOBALS
    Quit $PIECE(..#GLOBALS, ",", 1)
}

/// Whether the uninstall takes this item out by itself, so that it need not refuse: in this namespace (ownProduction is "" in
/// any other), the whole of a production of the module's own, and in the production Shutter went into only an item OwnItem
/// accepts; in the production onboarded in its namespace, only an item the onboarding recorded. A second item a site added
/// by hand on one of Shutter's classes stays where it is, and could not start once the classes are gone.
ClassMethod TakenByUninstall(production As %String, name As %String, className As %String, ownProduction As %String, ownClassName As %String, onboarded As %String, recorded As %Boolean) As %Boolean
{
    If ownProduction '= "" {
        // The module's own production classes go whole: any Shutter. one, and Hospital.Production by its exact name, which
        // the module compiles wherever it is loaded. Another Hospital. production in a hospital's namespace is the site's.
        If ..OwnClass(production, ownProduction = "Shutter.Production") || (production = "Hospital.Production") Quit 1
        If (production = ownProduction) && ..OwnItem(name, className, ownClassName) Quit 1
    }
    Quit (production = onboarded) && recorded
}

/// The class prefixes that are Shutter's: all three in its own namespace running Shutter.Production, where the module put
/// them; elsewhere (a hospital's namespace, Shutter's items inside the site's production, or a watched one) only Shutter.,
/// since a class or production called Hospital. or Downstream. there is the site's.
ClassMethod ClassPrefixes(ownNamespace As %Boolean) As %String
{
    Quit $SELECT(ownNamespace: ..#BODYCLASSES, 1: $PIECE(..#BODYCLASSES, ",", 1))
}

/// Whether a class (or a production) is Shutter's in a namespace of that kind (ClassPrefixes).
ClassMethod OwnClass(className As %String, ownNamespace As %Boolean) As %Boolean
{
    Set prefixes = ..ClassPrefixes(ownNamespace)
    For i = 1:1:$LENGTH(prefixes, ",") {
        Set prefix = $PIECE(prefixes, ",", i)
        If $EXTRACT(className, 1, $LENGTH(prefix)) = prefix Return 1
    }
    Quit 0
}

/// A WHERE clause matching a column against ClassPrefixes.
ClassMethod PrefixWhere(column As %String, ownNamespace As %Boolean) As %String
{
    Set prefixes = ..ClassPrefixes(ownNamespace), where = ""
    For i = 1:1:$LENGTH(prefixes, ",") Set where = where _ $SELECT(where = "": "", 1: " OR ") _ column _ " %STARTSWITH '" _ $PIECE(prefixes, ",", i) _ "'"
    Quit where
}

/// Whether this namespace is Shutter's own, running Shutter.Production (ClassPrefixes).
ClassMethod OwnNamespaceHere() As %Boolean
{
    Quit ##class(Shutter.Setup).ProductionName() = "Shutter.Production"
}

/// Whether a body class is one of Shutter's.
ClassMethod OwnBodyClass(className As %String) As %Boolean
{
    For i = 1:1:$LENGTH(..#BODYCLASSES, ",") {
        Set prefix = $PIECE(..#BODYCLASSES, ",", i)
        If $EXTRACT(className, 1, $LENGTH(prefix)) = prefix Return 1
    }
    Quit 0
}

/// Productions that name a class of Shutter's and that the uninstall would not take it out of: a forwarder added by hand,
/// without the onboarding. "" when there are none. Every namespace with Interoperability is read.
ClassMethod Refusal() As %String
{
    Set found = "", here = $NAMESPACE, ownProduction = ##class(Shutter.Setup).ProductionName()
    Set demo = ..DemoNamespaces(), all = ..AllNamespaces()
    Do ..OwnItems(.own)
    For i = 1:1:$LISTLENGTH(all) {
        Set ns = $LIST(all, i)
        If '$LISTFIND(demo, ns) Do ..ForeignItems(ns, here, ownProduction, .own, .found)
    }
    If found = "" Quit ""
    Quit "These items use Shutter's classes and were not added by its onboarding, so their productions would not start once the classes are gone: " _ found _ ". Take them out first, then run this again"
}

/// Adds to found the items in one namespace that use Shutter's classes, outside what the uninstall takes out itself.
ClassMethod ForeignItems(ns As %String, here As %String, ownProduction As %String, ByRef own, ByRef found As %String) [ Private ]
{
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Quit:'##class(%Dictionary.CompiledClass).%ExistsId("Ens.Config.Item")
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Production, Name, ClassName FROM Ens_Config.Item WHERE " _ ..PrefixWhere("ClassName", (ns = here) && (ownProduction = "Shutter.Production")))
        While rs.%Next() {
            Set production = rs.%GetData(1), name = rs.%GetData(2)
            // A row in no production starts nothing.
            Continue:production=""
            Continue:..TakenByUninstall(production, name, rs.%GetData(3), $SELECT(ns = here: ownProduction, 1: ""), $GET(own(name)), $GET(^|here|Shutter.Config("onboard", ns)), $DATA(^|here|Shutter.Config("onboard", ns, "items", name)) > 0)
            Set one = name _ " in " _ production _ " (" _ ns _ ")"
            If '$FIND("; " _ found _ "; ", "; " _ one _ "; ") Set found = found _ $SELECT(found = "": "", 1: "; ") _ one
        }
    } Catch ex {
    }
}

/// Each namespace onboarded here, or still holding a mapping or credential from an earlier removal, taken off.
ClassMethod TakeWatched(out As %DynamicObject)
{
    // The categories the onboarding imported, read before the removal forgets them: the Interop step drops them.
    Set ns = ""
    For {
        Set ns = $ORDER(^Shutter.Config("onboard", ns)) Quit:ns=""
        Set cat = ""
        For { Set cat = $ORDER(^Shutter.Config("onboard", ns, "schemas", cat), 1, as) Quit:cat=""  Set ^Shutter.Config("uninstall", "schemas", $SELECT(as '= "": as, 1: cat)) = 1 }
        Set seen(ns) = 1
    }
    Set ns = ""
    For { Set ns = $ORDER(^Shutter.Config("onboardKept", ns)) Quit:ns=""  Set seen(ns) = 1 }
    Set ns = ""
    For { Set ns = $ORDER(^Shutter.Config("onboardMade", "credential", ns)) Quit:ns=""  Set seen(ns) = 1 }
    Set ns = ""
    For {
        Set ns = $ORDER(seen(ns)) Quit:ns=""
        // First the items, with the mappings kept while messages need their classes; then those messages; then the rest.
        If $DATA(^Shutter.Config("onboard", ns)) {
            Set first = ##class(Shutter.Util.Onboard).Remove(ns, {})
            If 'first.ok Do out.errors.%Push(ns _ ": " _ first.error) Continue
            Do ..Copy(first.removed, out.removed)
        }
        Set n = ..DeleteMessages(ns, "", .problem)
        If problem '= "" Do out.errors.%Push(ns _ ": " _ problem) Continue
        If n > 0 Do out.removed.%Push(n _ " messages of Shutter's classes in " _ ns)
        If $DATA(^Shutter.Config("onboardKept", ns)) || ($GET(^Shutter.Config("onboardMade", "credential", ns)) '= "") {
            Set final = ##class(Shutter.Util.Onboard).Remove(ns, {"unmap": true, "credential": true})
            If 'final.ok Do out.errors.%Push(ns _ ": " _ final.error) Continue
            Do ..Copy(final.removed, out.removed)
            Set it = final.kept.%GetIterator()
            While it.%GetNext(, .line) { Do:$EXTRACT(line, 1, 15)'="Shutter's cases" out.kept.%Push(line) }
        }
        Do ..PurgeQueries(ns)
    }
    // A user a credential step made, once nothing signs in with it.
    Set user = ""
    For {
        Set user = $ORDER(^Shutter.Config("onboardMade", "user", user)) Quit:user=""
        If ##class(Shutter.Util.Onboard).UserExists(user) {
            Set sc = ##class(Shutter.Util.Onboard).DropUser(user)
            If $$$ISERR(sc) Do out.errors.%Push("The user " _ user _ ": " _ $SYSTEM.Status.GetErrorText(sc)) Continue
            Do out.removed.%Push("The user " _ user)
        }
    }
}

/// Shutter.Production stopped and its definition removed; or Shutter's items taken out of the site's own, which is updated
/// in place. A site's production is never stopped.
ClassMethod TakeProduction(out As %DynamicObject)
{
    Set production = ##class(Shutter.Setup).ProductionName()
    Set sc = ##class(Ens.Director).GetProductionStatus(.running, .state)
    If production = "Shutter.Production" {
        If ($GET(running) = production) && ($GET(state) = 1) {
            Set sc = ##class(Ens.Director).StopProduction(60, 1)
            If $$$ISERR(sc) Do out.errors.%Push("Stopping Shutter.Production: " _ $SYSTEM.Status.GetErrorText(sc)) Quit
            Do out.removed.%Push("Shutter.Production stopped")
        }
        If $GET(^Ens.AutoStart) = production Do ##class(Ens.Director).SetAutoStart("")
    } Else {
        Set sc = ..TakeItemsFrom(production, .taken)
        If $$$ISERR(sc) Do out.errors.%Push("Shutter's items in " _ production _ ": " _ $SYSTEM.Status.GetErrorText(sc)) Quit
        If taken > 0 Do out.removed.%Push(taken _ " items of Shutter's in " _ production _ ", which was updated and not stopped")
    }
    // The definitions of the module's own production classes here: Shutter.Production's and the demo hospital's. In a
    // hospital's namespace a production called Hospital.<something> is the site's: only the module's own name goes.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Ens_Config.Production WHERE Name %STARTSWITH 'Shutter.' OR " _ $SELECT(production = "Shutter.Production": "Name %STARTSWITH 'Hospital.'", 1: "Name = 'Hospital.Production'"))
    While rs.%Next() { Set own(rs.%GetData(1)) = 1 }
    Set name = ""
    For {
        Set name = $ORDER(own(name)) Quit:name=""
        Set sc = ##class(Ens.Config.Production).%DeleteId(name)
        If $$$ISERR(sc) Do out.errors.%Push("The definition of " _ name _ ": " _ $SYSTEM.Status.GetErrorText(sc)) Continue
        Do out.removed.%Push("The definition of " _ name)
    }
}

/// Shutter.Production's items here: own(name) = class.
ClassMethod OwnItems(Output own) [ Private ]
{
    Kill own
    Set source = ##class(Ens.Config.Production).%OpenId("Shutter.Production")
    Quit:'$ISOBJECT(source)
    For i = 1:1:source.Items.Count() Set own(source.Items.GetAt(i).Name) = source.Items.GetAt(i).ClassName
}

/// The items AddItemsTo put in a production, and its class saved and the running production updated.
ClassMethod TakeItemsFrom(production As %String, Output taken As %Integer) As %Status
{
    Set taken = 0, sc = $$$OK
    Set target = ##class(Ens.Config.Production).%OpenId(production)
    If '$ISOBJECT(target) Quit sc
    Do ..OwnItems(.own)
    For i = target.Items.Count():-1:1 {
        Set item = target.Items.GetAt(i)
        Continue:'..OwnItem(item.Name, item.ClassName, $GET(own(item.Name)))
        Set id = item.%Id()
        Do target.Items.RemoveAt(i)
        If id '= "" Do ##class(Ens.Config.Item).%DeleteId(id)
        Set taken = taken + 1
    }
    Quit:taken=0 sc
    Set sc = target.%Save() Quit:$$$ISERR(sc) sc
    Set sc = target.SaveToClass() Quit:$$$ISERR(sc) sc
    Set sc = ##class(Ens.Director).GetProductionStatus(.running, .state) Quit:$$$ISERR(sc) sc
    If ($GET(running) = production) && ($GET(state) = 1) Set sc = ##class(Ens.Director).UpdateProduction(30, 0)
    Quit sc
}

/// The public demo's hardening of the Management Portal undone, on this namespace's portal application.
ClassMethod TakePortal(out As %DynamicObject)
{
    Set ns = $NAMESPACE
    Set app = ""
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Security.Applications WHERE Resource = 'Shutter_Portal'")
    While rs.%Next() {
        Set app = rs.%GetData(1)
        Set was = $GET(^|ns|Shutter.Config("portalWas", app))
        Kill props
        Set props("Resource") = $LISTGET(was, 2), props("MatchRoles") = $LISTGET(was, 1)
        Set sc = ##class(Security.Applications).Modify(app, .props)
        If $$$ISERR(sc) Do out.errors.%Push(app _ ": " _ $SYSTEM.Status.GetErrorText(sc)) Continue
        Do out.removed.%Push("The hardening of " _ app)
        If was = "" Do out.kept.%Push(app _ " has no resource now, and its match roles were not recorded when it was hardened: set them again if you changed them")
    }
}

/// The demo's two namespaces, when they are the demo's: their productions stopped, then the namespaces, their web
/// applications, their databases and the databases' resources and folders.
ClassMethod TakeDemoNamespacesOff(out As %DynamicObject)
{
    Set demo = ..DemoNamespaces()
    For i = 1:1:$LISTLENGTH(demo) {
        Set ns = $LIST(demo, i)
        Set sc = ..StopIn(ns)
        If $$$ISERR(sc) Do out.errors.%Push("The production in " _ ns _ ": " _ $SYSTEM.Status.GetErrorText(sc)) Continue
        Set problem = ..DropNamespace(ns)
        If problem '= "" Do out.errors.%Push("The namespace " _ ns _ ": " _ problem) Continue
        Do out.removed.%Push("The namespace " _ ns _ " and its databases")
    }
}

ClassMethod StopIn(ns As %String) As %Status
{
    Set sc = $$$OK
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Quit:'##class(%Dictionary.CompiledClass).%ExistsId("Ens.Director")
        Set sc = ##class(Ens.Director).GetProductionStatus(.running, .state)
        If $$$ISOK(sc) && ($GET(state) = 1) Set sc = ##class(Ens.Director).StopProduction(60, 1)
        Quit:$$$ISERR(sc)
        Do ##class(Ens.Director).SetAutoStart("")
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// A namespace and what was made for it. Returns "" or what stopped it.
ClassMethod DropNamespace(ns As %String) As %String
{
    New $NAMESPACE
    Set problem = ""
    Try {
        Set $NAMESPACE = "%SYS"
        Do ##class(Config.Namespaces).Get(ns, .props)
        Set dbs = $LISTBUILD($GET(props("Globals")), $GET(props("Routines")))
        Try { Do ##class(%EnsembleMgr).DisableNamespace(ns, 1) } Catch ex { }
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Security.Applications WHERE NameSpace = ?", ns)
        Kill apps
        While rs.%Next() { Set apps(rs.%GetData(1)) = 1 }
        Set app = ""
        For { Set app = $ORDER(apps(app)) Quit:app=""  Do ##class(Security.Applications).Delete(app) }
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Config.MapPackages WHERE Namespace = ?", ns)
        While rs.%Next() { Set maps(rs.%GetData(1)) = 1 }
        Set map = ""
        For { Set map = $ORDER(maps(map)) Quit:map=""  Do ##class(Config.MapPackages).Delete(ns, map) }
        Set sc = ##class(Config.Namespaces).Delete(ns)
        If $$$ISERR(sc) Set problem = $SYSTEM.Status.GetErrorText(sc) Quit
        // The two roles the engine gives a namespace when Interoperability is enabled there.
        For role = "%EnsRole_ProdPrivs_" _ ns, "%HS_DB_" _ ns {
            If ##class(Security.Roles).Exists(role) Do ##class(Security.Roles).Delete(role)
        }
        For i = 1:1:$LISTLENGTH(dbs) {
            Set name = $LIST(dbs, i)
            Continue:name=""
            Continue:$DATA(done(name))
            Set done(name) = 1
            Kill db
            Continue:$$$ISERR(##class(Config.Databases).Get(name, .db))
            Set dir = $GET(db("Directory"))
            Set sc = ##class(SYS.Database).DismountDatabase(dir)
            Set sc = ##class(Config.Databases).Delete(name)
            If $$$ISERR(sc) Set problem = problem _ $SYSTEM.Status.GetErrorText(sc) Continue
            Set sc = ##class(SYS.Database).DeleteDatabase(dir)
            Do ##class(%File).RemoveDirectoryTree(dir)
            Set resource = "%DB_" _ name
            If ##class(Security.Resources).Exists(resource) Do ##class(Security.Resources).Delete(resource)
        }
    } Catch ex {
        Set problem = ex.DisplayString()
    }
    Quit problem
}

/// The Workflow role, its tasks, and the Workflow users that were in no other role.
ClassMethod TakeWorkflow(out As %DynamicObject)
{
    Set role = "Shutter Approvers"
    Quit:'##class(EnsLib.Workflow.RoleDefinition).%ExistsId(role)
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE %RoleName = ?", role)
    While rs.%Next() { Do ##class(EnsLib.Workflow.TaskResponse).%DeleteId(rs.%GetData(1)) }
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT UserName FROM EnsLib_Workflow.RoleMembership WHERE RoleName = ?", role)
    While rs.%Next() { Set members(rs.%GetData(1)) = 1 }
    Set user = ""
    For {
        Set user = $ORDER(members(user)) Quit:user=""
        Do ##class(EnsLib.Workflow.RoleMembership).%DeleteId(role _ "||" _ user)
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) FROM EnsLib_Workflow.RoleMembership WHERE UserName = ?", user)
        If rs.%Next() && (rs.%GetData(1) = 0) Do ##class(EnsLib.Workflow.UserDefinition).%DeleteId(user)
    }
    Set sc = ##class(EnsLib.Workflow.RoleDefinition).%DeleteId(role)
    If $$$ISERR(sc) Do out.errors.%Push("The Workflow role: " _ $SYSTEM.Status.GetErrorText(sc)) Quit
    Do out.removed.%Push("The Workflow role " _ role)
}

/// Every message of Shutter's classes here, and what Shutter's own production's items carried.
ClassMethod TakeMessages(out As %DynamicObject)
{
    Set own = ..OwnNamespaceHere()
    Set n = ..DeleteMessages($NAMESPACE, own, .problem)
    If problem '= "" Do out.errors.%Push(problem) Quit
    If n > 0 Do out.removed.%Push(n _ " messages in " _ $NAMESPACE)
    // The event log's lines from Shutter's classes.
    Do ##class(%SQL.Statement).%ExecDirectNoPriv(, "DELETE %NOCHECK FROM Ens_Util.Log WHERE " _ ..PrefixWhere("SourceClass", own))
}

/// Deletes the messages of Shutter's body classes in a namespace, with their bodies, the rest of each session staying. When
/// wholeNamespace is 1 (Shutter's own namespace) the demo's body classes too, and every message that went through an item of
/// Shutter.Production: its feed's HL7 messages have the engine's own body class. Elsewhere a Hospital. or Downstream. body
/// is the site's and stays (ClassPrefixes). Returns how many.
ClassMethod DeleteMessages(ns As %String, wholeNamespace As %Boolean = 0, Output problem As %String) As %Integer
{
    Set problem = "", n = 0
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set where = ..PrefixWhere("MessageBodyClassName", wholeNamespace)
        If wholeNamespace {
            Set prod = ##class(Ens.Config.Production).%OpenId("Shutter.Production")
            If $ISOBJECT(prod) {
                Set names = ""
                For i = 1:1:prod.Items.Count() Set names = names _ $SELECT(names = "": "", 1: ",") _ "'" _ $REPLACE(prod.Items.GetAt(i).Name, "'", "''") _ "'"
                If names '= "" Set where = where _ " OR SourceConfigName IN (" _ names _ ") OR TargetConfigName IN (" _ names _ ")"
            }
        }
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE " _ where)
        While rs.%Next() {
            Set bodyClass = rs.%GetData(2), bodyId = rs.%GetData(3)
            If (bodyClass '= "") && (bodyId '= "") Try { Do $CLASSMETHOD(bodyClass, "%DeleteId", bodyId) } Catch ex { }
            Do ##class(Ens.MessageHeader).%DeleteId(rs.%GetData(1))
            Set n = n + 1
        }
    } Catch ex {
        Set problem = ex.DisplayString()
    }
    Quit n
}

/// The default settings the installers wrote, the credentials, the imported HL7 schema categories, the queues.
ClassMethod TakeInterop(out As %DynamicObject)
{
    Do ##class(%SQL.Statement).%ExecDirectNoPriv(, "DELETE %NOCHECK FROM Ens_Config.DefaultSettings WHERE Description = 'Set by Shutter.Setup' OR Description = 'Set by Hospital.Setup'")
    Set list = $LISTFROMSTRING(..#CREDENTIALS)
    For i = 1:1:$LISTLENGTH(list) {
        Set name = $LIST(list, i)
        Continue:'##class(Ens.Config.Credentials).%ExistsId(name)
        Set sc = ##class(Ens.Config.Credentials).%DeleteId(name)
        If $$$ISERR(sc) Do out.errors.%Push("The credential " _ name _ ": " _ $SYSTEM.Status.GetErrorText(sc)) Continue
        Do out.removed.%Push("The credential " _ name)
    }
    // The engine's note of the search table on HL7 messages, and of the production last open in the portal.
    Set doc = ""
    For {
        Set doc = $ORDER(^Ens.DocClassMap(doc)) Quit:doc=""
        Set table = ""
        For { Set table = $ORDER(^Ens.DocClassMap(doc, "st", table)) Quit:table=""  Kill:..OwnBodyClass(table) ^Ens.DocClassMap(doc, "st", table) }
    }
    For name = "Shutter.Production", "Hospital.Production" {
        Kill ^Ens.Configuration("csp", "Activity", name)
        If $GET(^Ens.Configuration("csp", "LastProduction")) = name Kill ^Ens.Configuration("csp", "LastProduction")
    }
    Set cat = ""
    For {
        Set cat = $ORDER(^Shutter.Config("uninstall", "schemas", cat)) Quit:cat=""
        Kill ^EnsHL7.Schema(cat), ^EnsHL7.Description(cat)
        Do out.removed.%Push("The HL7 schema category " _ cat _ ", imported by the onboarding")
    }
}

/// The provider's configuration, its wallet secret and the wallet's collection. Quiet where AI Hub is not there.
ClassMethod TakeProvider(out As %DynamicObject)
{
    Quit:'##class(%Dictionary.CompiledClass).%ExistsId("%Wallet.KeyValue")
    Do ##class(Shutter.Setup).ClearProvider()
    Try { Do $CLASSMETHOD("%Wallet.Collection", "Delete", "Shutter") } Catch ex { }
    Do out.removed.%Push("The provider's configuration and its key in the wallet, when there was one")
}

ClassMethod TakeTasks(out As %DynamicObject)
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    For name = "Shutter retention", "Shutter message purge" {
        Set id = ..TaskId(name)
        Continue:id=""
        Set sc = ##class(%SYS.Task).%DeleteId(id)
        If $$$ISERR(sc) { Do out.errors.%Push("The task " _ name _ ": " _ $SYSTEM.Status.GetErrorText(sc)) } Else { Do out.removed.%Push("The task " _ name) }
    }
}

ClassMethod TakeApplications(out As %DynamicObject)
{
    Set list = ..Applications()
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    For i = 1:1:$LISTLENGTH(list) {
        Set sc = ##class(Security.Applications).Delete($LIST(list, i))
        If $$$ISERR(sc) { Do out.errors.%Push($LIST(list, i) _ ": " _ $SYSTEM.Status.GetErrorText(sc)) } Else { Do out.removed.%Push("The web application " _ $LIST(list, i)) }
    }
}

/// The SQL grants to Shutter's roles, before the roles go: dropping a role does not reach another namespace's grants.
ClassMethod TakeGrants(out As %DynamicObject)
{
    For role = "Shutter_Operator", "Shutter_Approver", "Shutter_Demo", "Shutter_Judge", "Shutter_Forwarder" {
        For schema = "Shutter_Store", "Shutter_Index", "Shutter_Msg", "Shutter_Bridge", "Ens_Config" {
            Try { Do ##class(%SQL.Statement).%ExecDirect(, "REVOKE SELECT ON SCHEMA " _ schema _ " FROM " _ role) } Catch ex { }
        }
    }
    Try { Do ##class(Shutter.Setup).TraceSelectGrant($NAMESPACE, 0, .count, .problem) } Catch ex { }
}

/// The users the installers made. A user of the site keeps its login and loses only Shutter's roles (TakeRoles).
ClassMethod TakeUsers(out As %DynamicObject)
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set list = $LISTFROMSTRING(..#USERNAMES)
    For i = 1:1:$LISTLENGTH(list) {
        Set user = $LIST(list, i)
        Continue:'##class(Security.Users).Exists(user)
        Kill props
        Do ##class(Security.Users).Get(user, .props)
        If ..OwnUser(user, $GET(props("Comment"))) {
            Set sc = ##class(Security.Users).Delete(user)
            If $$$ISERR(sc) { Do out.errors.%Push("The user " _ user _ ": " _ $SYSTEM.Status.GetErrorText(sc)) } Else { Do out.removed.%Push("The user " _ user) }
        } ElseIf $LISTFIND($LISTFROMSTRING($GET(props("Roles"))), "Shutter_Operator") || $LISTFIND($LISTFROMSTRING($GET(props("Roles"))), "Shutter_Approver") || $LISTFIND($LISTFROMSTRING($GET(props("Roles"))), "Shutter_Forwarder") {
            Do out.kept.%Push("The user " _ user _ " was not made by Shutter's install, so it stays. Its password may be the demo's, which the install set: change it")
        }
    }
}

/// Shutter's roles: taken from every user and every other role first.
ClassMethod TakeRoles(out As %DynamicObject)
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set list = ..NamesLike("Security.Roles")
    Quit:list=""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Security.Users")
    While rs.%Next() {
        Set user = rs.%GetData(1)
        Kill props
        Continue:$$$ISERR(##class(Security.Users).Get(user, .props))
        Set left = ..Without($GET(props("Roles")), list)
        Continue:left=$GET(props("Roles"))
        Kill change
        Set change("Roles") = left
        Set sc = ##class(Security.Users).Modify(user, .change)
        If $$$ISERR(sc) Do out.errors.%Push("The roles of " _ user _ ": " _ $SYSTEM.Status.GetErrorText(sc))
    }
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Security.Roles")
    While rs.%Next() {
        Set role = rs.%GetData(1)
        Continue:..OwnSecurityName(role)
        Kill props
        Continue:$$$ISERR(##class(Security.Roles).Get(role, .props))
        Set left = ..Without($GET(props("GrantedRoles")), list)
        Continue:left=$GET(props("GrantedRoles"))
        Kill change
        Set change("GrantedRoles") = left
        Do ##class(Security.Roles).Modify(role, .change)
    }
    For i = 1:1:$LISTLENGTH(list) {
        Set sc = ##class(Security.Roles).Delete($LIST(list, i))
        If $$$ISERR(sc) { Do out.errors.%Push("The role " _ $LIST(list, i) _ ": " _ $SYSTEM.Status.GetErrorText(sc)) } Else { Do out.removed.%Push("The role " _ $LIST(list, i)) }
    }
}

/// A comma-separated list without the names in a %List.
ClassMethod Without(roles As %String, names As %List) As %String
{
    Set left = ""
    For i = 1:1:$LENGTH(roles, ",") {
        Set one = $PIECE(roles, ",", i)
        Continue:(one="")||$LISTFIND(names, one)
        Set left = left _ $SELECT(left = "": "", 1: ",") _ one
    }
    Quit left
}

ClassMethod TakeResources(out As %DynamicObject)
{
    Set list = ..NamesLike("Security.Resources")
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    For i = 1:1:$LISTLENGTH(list) {
        Set sc = ##class(Security.Resources).Delete($LIST(list, i))
        If $$$ISERR(sc) { Do out.errors.%Push("The resource " _ $LIST(list, i) _ ": " _ $SYSTEM.Status.GetErrorText(sc)) } Else { Do out.removed.%Push("The resource " _ $LIST(list, i)) }
    }
}

/// The folders under the manager directory. A database there (a namespace named SHUTTER has its own in this very folder,
/// and an image keeps its data under it) stays.
ClassMethod TakeFolders(out As %DynamicObject)
{
    Set base = ..Folder()
    Quit:'##class(%File).DirectoryExists(base)
    For sub = "in", "archive", "work", "out" {
        Do ##class(%File).RemoveDirectoryTree(##class(%File).NormalizeDirectory(base _ sub))
    }
    If ..HoldsDatabase(base) {
        Do out.kept.%Push("The folder " _ base _ " holds a database (a namespace named SHUTTER keeps its own there), so it stays with that database")
    } Else {
        Do ##class(%File).RemoveDirectoryTree(base)
    }
    Do out.removed.%Push("The folders under " _ base)
}

ClassMethod HoldsDatabase(dir As %String) As %Boolean
{
    Set rs = ##class(%ResultSet).%New("%File:FileSet")
    Do rs.Execute(dir, "*", , 1)
    While rs.Next() {
        Set name = rs.Get("Name")
        If rs.Get("Type") = "D" {
            If ..HoldsDatabase(name) Return 1
        } ElseIf ##class(%File).GetFilename(name) = "IRIS.DAT" {
            Return 1
        }
    }
    Quit 0
}

/// Last of all: every global of Shutter's in this namespace, the tables' data and the configuration with them.
ClassMethod TakeGlobals(out As %DynamicObject)
{
    Set ns = $NAMESPACE
    Set prefixes = ..GlobalPrefixes($GET(^Shutter.Config("demo")), ##class(Shutter.Setup).ProductionName())
    Do ..PurgeQueries(ns)
    // Tables on extent sets keep their rows under a hashed name, so they go by class. A class that extends an engine's
    // (a message body) loses only its own rows.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM %Dictionary.CompiledClass WHERE ClassType = 'persistent' AND (Name %STARTSWITH 'Shutter.' OR Name %STARTSWITH 'Hospital.' OR Name %STARTSWITH 'Downstream.')")
    While rs.%Next() {
        Set class = rs.%GetData(1)
        Continue:'$FIND("," _ prefixes _ ",", ",^" _ $PIECE(class, ".", 1) _ ".,")
        // A serial or generated class listed as persistent has no extent of its own to kill.
        Continue:'##class(%Dictionary.CompiledMethod).%ExistsId(class _ "||%KillExtent")
        Set sc = $CLASSMETHOD(class, "%KillExtent")
        If $$$ISERR(sc) Do out.errors.%Push("The rows of " _ class _ ": " _ $SYSTEM.Status.GetErrorText(sc))
    }
    // The extent manager's record of each class: removing a class leaves it, with every global the class named.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM %Dictionary.CompiledClass WHERE Name %STARTSWITH 'Shutter.' OR Name %STARTSWITH 'Hospital.' OR Name %STARTSWITH 'Downstream.'")
    While rs.%Next() { Do ##class(%ExtentMgr.Util).DeleteExtentDefinitionIfExists(rs.%GetData(1), "cls") }
    For i = 1:1:$LENGTH(prefixes, ",") {
        Set prefix = $PIECE(prefixes, ",", i)
        // $ORDER starts from a valid name, so the prefix without its dot.
        Set g = $PIECE(prefix, ".", 1)
        For {
            Set g = $ORDER(^$GLOBAL(g)) Quit:g=""
            Quit:$EXTRACT(g, 1, $LENGTH(prefix))'=prefix
            Set names(g) = 1
        }
    }
    // The configuration last: it says which prefixes go, should this be run again.
    Kill names("^Shutter.Config")
    Set g = ""
    For { Set g = $ORDER(names(g)) Quit:g=""  Kill @g }
    Kill ^Shutter.Config
    Do out.removed.%Push("Every case, approval, incident and setting of Shutter's in " _ ns)
}

ClassMethod PurgeQueries(ns As %String)
{
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Do $SYSTEM.SQL.Purge()
    } Catch ex {
    }
}

/// The folder the install made under the manager directory.
ClassMethod Folder() As %String
{
    Quit ##class(%File).NormalizeDirectory(##class(%File).ManagerDirectory() _ "shutter")
}

/// Shutter's web applications: those the install recorded, and any whose dispatch class is Shutter's or the demo receiver's.
ClassMethod Applications() As %List
{
    Set ns = $NAMESPACE, app = ""
    For { Set app = $ORDER(^Shutter.Config("webapp", app)) Quit:app=""  Set names(app) = 1 }
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Security.Applications WHERE DispatchClass %STARTSWITH 'Shutter.' OR DispatchClass %STARTSWITH 'Downstream.'")
    While rs.%Next() { Set names(rs.%GetData(1)) = 1 }
    Set out = "", app = ""
    For {
        Set app = $ORDER(names(app)) Quit:app=""
        If ##class(Security.Applications).Exists(app) Set out = out _ $LISTBUILD(app)
    }
    Quit out
}

/// The roles or resources (class Security.Roles or Security.Resources) whose names are Shutter's.
ClassMethod NamesLike(class As %String) As %List
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS", out = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM " _ class)
    While rs.%Next() { If ..OwnSecurityName(rs.%GetData(1)) Set out = out _ $LISTBUILD(rs.%GetData(1)) }
    Quit out
}

ClassMethod UsersPlan(out As %DynamicObject)
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set list = $LISTFROMSTRING(..#USERNAMES)
    For i = 1:1:$LISTLENGTH(list) {
        Set user = $LIST(list, i)
        Continue:'##class(Security.Users).Exists(user)
        Kill props
        Do ##class(Security.Users).Get(user, .props)
        If ..OwnUser(user, $GET(props("Comment"))) { Do out.removes.%Push("The user " _ user) } Else { Do out.keeps.%Push("The user " _ user _ ", not made by Shutter's install, without Shutter's roles") }
    }
}

ClassMethod TaskId(name As %String) As %String
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS", id = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM %SYS.Task WHERE Name = ?", name)
    If rs.%Next() Set id = rs.%GetData(1)
    Quit id
}

ClassMethod AllNamespaces() As %List
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS", out = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Config.Namespaces")
    While rs.%Next() { Set out = out _ $LISTBUILD(rs.%GetData(1)) }
    Quit out
}

/// The demo's namespaces on this instance, by OwnNamespace: their package mapped from this namespace's code database.
ClassMethod DemoNamespaces() As %List
{
    Set here = $NAMESPACE, out = ""
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Do ##class(Config.Namespaces).Get(here, .props)
    Set code = $GET(props("Routines"))
    For ns = "HOSPITAL", "RECORDS" {
        Continue:ns=here
        Continue:'##class(Config.Namespaces).Exists(ns)
        Set package = $CASE(ns, "HOSPITAL": "Hospital", : "Downstream")
        Kill map
        Set from = ""
        If ##class(Config.MapPackages).Get(ns, package, .map) Set from = $GET(map("Database"))
        If ..OwnNamespace(ns, from, code) Set out = out _ $LISTBUILD(ns)
    }
    Quit out
}

ClassMethod Copy(from As %DynamicArray, to As %DynamicArray)
{
    Set it = from.%GetIterator()
    While it.%GetNext(, .line) { Do to.%Push(line) }
}

}
