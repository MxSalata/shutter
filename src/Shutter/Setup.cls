/// Installs and checks Shutter. Install() runs from the IPM module after the classes are loaded
/// and is idempotent; CreateNamespace() can be run first from any namespace to create a fresh one
/// with Interoperability enabled.
Class Shutter.Setup Extends %RegisteredObject
{

Parameter VERSION = "0.1.0";

/// Create a namespace with its own database and Interoperability enabled. Returns "ok" or the error.
ClassMethod CreateNamespace(ns As %String = "SHUTTER") As %String [ SqlProc ]
{
    Set sc = ..CreateNamespaceStatus(ns)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

ClassMethod CreateNamespaceStatus(ns As %String) As %Status
{
    Set sc = $$$OK
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set ns = $ZCONVERT(ns, "U")
        If '##class(Config.Namespaces).Exists(ns) {
            Set dir = ##class(%File).NormalizeDirectory(##class(%File).ManagerDirectory() _ $ZCONVERT(ns, "L"))
            If '##class(%File).DirectoryExists(dir) {
                If '##class(%File).CreateDirectoryChain(dir) Set sc = $$$ERROR($$$GeneralError, "Cannot create " _ dir) Quit
            }
            If '##class(Config.Databases).Exists(ns) {
                Set resource = "%DB_" _ ns
                If '##class(Security.Resources).Exists(resource) {
                    Set sc = ##class(Security.Resources).Create(resource, "The " _ ns _ " database", "")
                    Quit:$$$ISERR(sc)
                }
                If '##class(%File).Exists(dir _ "IRIS.DAT") {
                    Set sc = ##class(SYS.Database).CreateDatabase(dir, , , , resource)
                    Quit:$$$ISERR(sc)
                }
                Kill props
                Set props("Directory") = dir
                Set sc = ##class(Config.Databases).Create(ns, .props)
                Quit:$$$ISERR(sc)
            }
            Kill props
            Set props("Globals") = ns, props("Routines") = ns
            Set sc = ##class(Config.Namespaces).Create(ns, .props)
            Quit:$$$ISERR(sc)
        }
        Set sc = ##class(%EnsembleMgr).EnableNamespace(ns)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Install into the current namespace: resources, roles, demo users, credentials, folders, the
/// library, prices, recordings, the downstream system's installer when present, the web applications and the
/// production. The names from before the downstream system's rename are removed when they exist. root is the
/// module's directory (IPM passes ${root}); demo marks the instance as a demo (reset allowed, demo users created).
/// The module's manifest passes ${demo} (default 1; zpm "load <dir> -Ddemo=0" for a site). With demo = 0 nothing of
/// the demo is made: no demo users, nothing of the demo receiver's (its resource, role, web application, client user
/// and credential), no recorded runs, the message purge task only when SHUTTER_MESSAGE_PURGE is 1, and the
/// production's feed, downstream and scenario items switched off (DisableDemoItems). Returns "ok" or the error.
ClassMethod Install(root As %String = "", demo As %Boolean = 1, production As %String = "") As %String [ SqlProc ]
{
    Set sc = ..InstallStatus(root, demo, production)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

/// Refuses a module root that will not outlive the install. IPM 0.10.0 to 0.10.3 extract a packaged module (the
/// registry's or an archive's) into a folder under the instance's temporary directory and delete it when the install
/// ends, but /shutter serves www/ from the root and the scenarios read fixtures/ there afterwards: the install then
/// fails with the reason instead of leaving a web application that answers 404. IPM 0.10.4 and later keep the module
/// in their module root, and a module loaded from a folder (zpm "load <dir>") stays where it is.
ClassMethod RootStatus(root As %String = "") As %Status [ Private ]
{
    If ($GET(root) = "") || (root = $CHAR(0)) Quit $$$OK
    Set dir = $ZCONVERT(##class(%File).NormalizeDirectory(root), "L")
    Set temp = $ZCONVERT(##class(%File).NormalizeDirectory(##class(%SYS.System).TempDirectory()), "L")
    If $EXTRACT(dir, 1, $LENGTH(temp)) '= temp Quit $$$OK
    Quit $$$ERROR($$$GeneralError, "The module's files are in " _ root _ ", which IPM 0.10.0 to 0.10.3 delete when the install ends: install IPM 0.10.4 or later, or load the module from a folder (zpm ""load <dir>"")")
}

/// Install as a %Status: what the module's manifest invokes (the Invoke checks the status, so a failed install stops
/// the load) and what Install wraps. The housekeeping tasks read SHUTTER_MESSAGE_DAYS and SHUTTER_MESSAGE_PURGE from
/// the environment of the process that runs the install (EnsureRetentionTasks).
/// With a production named (IPM: -Dproduction=Your.Production), the install is shape B: Shutter's items go into that
/// production (InstallIntoStatus) and Shutter.Production is neither started nor made the auto-start production.
ClassMethod InstallStatus(root As %String = "", demo As %Boolean = 1, production As %String = "") As %Status
{
    // IPM runs the install inside a transaction of its own and commits it after the Activate phase, but starting a
    // production (Ens.Director) commits every open transaction: IPM's commit then fails (<COMMAND> *NoTransaction) and
    // a load or install that worked ends with an error. The level the install was called at is restored before it
    // returns; what was written up to the production's start is committed either way.
    Set tlevel = $TLEVEL
    Set sc = ..RootStatus(root) Quit:$$$ISERR(sc) sc
    Set production = $ZSTRIP($GET(production), "<>WC")
    If production '= "" {
        Set sc = ..InstallIntoStatus(production, root)
        While $TLEVEL < tlevel { TSTART }
        Quit sc
    }
    Set sc = $$$OK
    Try {
        Set ns = $NAMESPACE
        // SQL hands an empty argument to a procedure as $CHAR(0); an empty demo keeps the default.
        If root = $CHAR(0) Set root = ""
        If (demo = "") || (demo = $CHAR(0)) Set demo = 1
        Set demo = ''demo
        If root '= "" Set root = ##class(%File).NormalizeDirectory(root)
        Set ^Shutter.Config("root") = root
        Set ^Shutter.Config("demo") = demo
        Set ^Shutter.Config("installedAt") = ##class(Shutter.Util.Time).NowUTC()
        Set ^Shutter.Config("version") = ..#VERSION
        If $GET(^Shutter.Config("mode")) = "" Set ^Shutter.Config("mode") = "board"
        Set sc = ..CreateFolders() Quit:$$$ISERR(sc)
        Set sc = ..CreateSecurity(ns, demo) Quit:$$$ISERR(sc)
        Set sc = ..RemoveOldReceiverNames() Quit:$$$ISERR(sc)
        // The demo receiver's resource and role first: the production's client user gets the role at creation. A site
        // install makes nothing of the demo receiver's: no resource, role, client user or credential.
        If demo && ##class(%Dictionary.CompiledClass).%ExistsId("Downstream.Installer") {
            Set sc = $CLASSMETHOD("Downstream.Installer", "Install", demo)
            Quit:$$$ISERR(sc)
        }
        If demo Set sc = ..CreateCredentials(demo) Quit:$$$ISERR(sc)
        Set sc = ..CreateWorkflowRole(demo) Quit:$$$ISERR(sc)
        Set sc = ##class(Shutter.Store.BoardMember).Seed() Quit:$$$ISERR(sc)
        Set sc = ##class(Shutter.Store.ModelPrice).Seed() Quit:$$$ISERR(sc)
        If (root '= "") && ##class(%File).Exists(root _ "knowledge/block-reasons.json") {
            Set sc = ##class(Shutter.Store.BlockReason).SeedFromFile(root _ "knowledge/block-reasons.json", .reasons)
            Quit:$$$ISERR(sc)
            Set ^Shutter.Config("blockReasons") = reasons
        }
        If root '= "" {
            Set sc = ##class(Shutter.Store.SiteProfile).SeedFromFile(root _ "knowledge/site/profile.json") Quit:$$$ISERR(sc)
            Set sc = ##class(Shutter.Catalogue.Entry).SeedFromFile(root _ "knowledge/catalogue/catalogue.json", .entries) Quit:$$$ISERR(sc)
            Set ^Shutter.Config("catalogue", "entries") = $GET(entries, 0)
        }
        // The recorded agent runs are the demo's: a site's cases have none to replay (RefreshKnowledge skips them too).
        If demo && (root '= "") && ##class(%File).DirectoryExists(root _ "fixtures/records") {
            Set sc = ##class(Shutter.Bridge.Record).ImportDir(root _ "fixtures/records", .count)
            Quit:$$$ISERR(sc)
            Set ^Shutter.Config("recordsImported") = count
        }
        Set sc = ..CreateWebApps(ns, root, demo) Quit:$$$ISERR(sc)
        Set r = ..EnsureRetentionTasks(ns)
        If $EXTRACT(r, 1, 6) = "ERROR:" Set sc = $$$ERROR($$$GeneralError, "Retention tasks: " _ r) Quit
        // Replayed runs spend nothing; rows written before this rule held a recording's price.
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "UPDATE Shutter_Store.AgentRun SET CostUSD = 0 WHERE Mode = 'replay' AND CostUSD <> 0")
        Set sc = ..StartProduction() Quit:$$$ISERR(sc)
        // A site runs the production with no feed of its own: the demo's items are switched off.
        If 'demo Set sc = ..DisableDemoItems() Quit:$$$ISERR(sc)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    While $TLEVEL < tlevel { TSTART }
    Quit sc
}

/// The inbound, archive and work folders under the manager directory.
ClassMethod CreateFolders() As %Status
{
    Set base = ##class(%File).NormalizeDirectory(##class(%File).ManagerDirectory() _ "shutter")
    For sub = "in", "archive", "work", "out" {
        Set dir = base _ sub _ "/"
        If '##class(%File).DirectoryExists(dir) {
            If '##class(%File).CreateDirectoryChain(dir) Quit $$$ERROR($$$GeneralError, "Cannot create " _ dir)
        }
        Set ^Shutter.Config("dir", sub) = dir
    }
    Set ^Shutter.Config("adtIn") = base _ "in/"
    Set ^Shutter.Config("adtArchive") = base _ "archive/"
    Set root = $GET(^Shutter.Config("root"))
    If root '= "" Set ^Shutter.Config("fixtures") = root _ "fixtures/"
    Quit $$$OK
}

/// Resources, roles and the demo users. Runs in %SYS.
/// A demo user that already exists gets the demo password, is enabled and need not change it (run in %SYS).
ClassMethod ResetDemoUser(user As %String, password As %String) As %Status [ Private ]
{
    Set props("Password") = password, props("Enabled") = 1, props("ChangePassword") = 0, props("PasswordNeverExpires") = 1
    Quit ##class(Security.Users).Modify(user, .props)
}

ClassMethod CreateSecurity(ns As %String, demo As %Boolean) As %Status
{
    Set sc = $$$OK
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    For res = "Shutter_Operate", "Shutter_Approve", "Shutter_Intake" {
        If '##class(Security.Resources).Exists(res) {
            Set sc = ##class(Security.Resources).Create(res, "Shutter: " _ $CASE(res, "Shutter_Approve": "approve or reject recovery plans", "Shutter_Intake": "open a case from another production", : "view cases, run scenarios, start investigations"), "")
            Quit:$$$ISERR(sc)
        }
    }
    Quit:$$$ISERR(sc) sc
    // The namespace's data database read-write, and its code database read when it is another one (the image keeps the
    // code in the image and the data in the volume).
    Set db = ..DatabaseResource(ns), code = ..DatabaseResource(ns, 1)
    Set codeRead = $SELECT((code '= "") && (code '= db): "," _ code _ ":R", 1: "")
    // Each role is created, or brought to this definition when it exists, so an upgraded instance is tightened too.
    // The approver monitors (traces, messages, the Workflow inbox) and approves; it never starts, stops or purges:
    // %EnsRole_Monitor with the message trace, header and content viewing resources, not %EnsRole_Operator (E2).
    Set sc = ..EnsureRole("Shutter_Operator", "Shutter operator: cases, scenarios, investigations", "Shutter_Operate:U," _ db _ ":RW" _ codeRead _ ",%Ens_Portal:U", "")
    Quit:$$$ISERR(sc) sc
    Set sc = ..EnsureRole("Shutter_Approver", "Shutter approver: everything an operator can, plus approvals and the Workflow inbox", "Shutter_Operate:U,Shutter_Approve:U," _ db _ ":RW" _ codeRead _ ",%Ens_MessageTrace:U,%Ens_MessageHeader:U,%Ens_MessageContent:U", "Shutter_Operator,%EnsRole_Monitor")
    Quit:$$$ISERR(sc) sc
    // The production's client of the downstream API needs the database as well as the downstream system's own
    // resource (the Downstream_API role carries only that), or the web application answers 403.
    Set sc = ..EnsureRole("Shutter_DownstreamClient", "Shutter: the production's client of the downstream API, with the namespace's databases", db _ ":RW" _ codeRead, "")
    Quit:$$$ISERR(sc) sc
    // Every caller of the API web application gets read access to the namespace's databases, so
    // that the sign-in route can run for an anonymous session; data routes still check resources.
    Set sc = ..EnsureRole("Shutter_WebApp", "Shutter web application: read the namespace's databases (granted to every caller by the web application)", db _ ":R" _ codeRead, "")
    Quit:$$$ISERR(sc) sc
    // The forwarder in a watched production opens cases through POST /api/shutter/intake and nothing else (CONTRACTS
    // 11): the intake resource and the databases, so only the watched productions' credential can open cases.
    Set sc = ..EnsureRole("Shutter_Forwarder", "Shutter forwarder: open a case from another production through the intake route", "Shutter_Intake:U," _ db _ ":RW" _ codeRead, "")
    Quit:$$$ISERR(sc) sc
    If demo {
        Set password = $SYSTEM.Util.GetEnviron("SHUTTER_DEMO_PASSWORD")
        If password = "" Set password = "shutter"
        For user = "operator", "approver", "forwarder" {
            Set roles = $CASE(user, "approver": "Shutter_Approver", "forwarder": "Shutter_Forwarder", : "Shutter_Operator")
            If ##class(Security.Users).Exists(user) {
                // An upgraded demo instance: the user is brought to the demo's definition (its role, the demo
                // password, enabled), as the documentation promises for operator, approver and forwarder.
                Do ##class(Security.Users).AddRoles(user, roles)
                Set sc = ..ResetDemoUser(user, password)
            } Else {
                Set sc = ##class(Security.Users).Create(user, roles, password, "Shutter demo " _ user, ns, "", "", 0, 1, "Shutter demo user")
            }
            Quit:$$$ISERR(sc)
        }
    }
    Quit sc
}

/// A role with exactly these resources and granted roles: created when missing, modified when it exists. Runs in %SYS.
ClassMethod EnsureRole(name As %String, description As %String, resources As %String, grantedRoles As %String) As %Status [ Private ]
{
    If '##class(Security.Roles).Exists(name) Quit ##class(Security.Roles).Create(name, description, resources, grantedRoles)
    Set props("Description") = description, props("Resources") = resources, props("GrantedRoles") = grantedRoles
    Quit ##class(Security.Roles).Modify(name, .props)
}

/// Bring the resources, roles and demo users to the current definition on an existing instance (the installer does
/// it on every install). Returns "ok" or the error.
ClassMethod EnsureSecurity(ns As %String = "", demo As %Boolean = 1) As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("%Admin_Secure", "USE") Quit "%Admin_Secure is required"
    If ns = "" Set ns = $NAMESPACE
    Set sc = ..CreateSecurity(ns, demo)
    Quit $SELECT($$$ISOK(sc): "ok", 1: "ERROR: " _ $SYSTEM.Status.GetErrorText(sc))
}

/// The security resource of a namespace's data database (its globals), or with <var>code</var> of its code database
/// (its routines), for example %DB_SHUTTERDATA, %DB_SHUTTER or %DB_%DEFAULT. Runs in %SYS.
ClassMethod DatabaseResource(ns As %String, code As %Boolean = 0) As %String
{
    Set resource = "%DB_%DEFAULT"
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set sc = ##class(Config.Namespaces).Get(ns, .nsprops)
        Quit:$$$ISERR(sc)
        Set dbname = $GET(nsprops($SELECT(code: "Routines", 1: "Globals")))
        Quit:(dbname="")
        Set sc = ##class(Config.Databases).Get(dbname, .dbprops)
        Quit:$$$ISERR(sc)
        Set db = ##class(SYS.Database).%OpenId($GET(dbprops("Directory")))
        If $ISOBJECT(db) && (db.ResourceName '= "") Set resource = db.ResourceName
    } Catch ex {
    }
    Quit resource
}

/// The production's credentials for the demo receiver's API: a user with the Downstream_API role when the downstream
/// system's installer created it, otherwise the demo operator. Called on a demo install only: a site has no demo
/// receiver to call, so it gets no downstream-client user and no DownstreamAPI credential.
ClassMethod CreateCredentials(demo As %Boolean) As %Status
{
    Set sc = $$$OK
    Set password = $SYSTEM.Util.GetEnviron("SHUTTER_DEMO_PASSWORD")
    If password = "" Set password = "shutter"
    Set user = "downstream-client"
    New $NAMESPACE
    Set ns = $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set roles = $SELECT(##class(Security.Roles).Exists("Shutter_DownstreamClient"): "Shutter_DownstreamClient", 1: "Shutter_Operator")
    If ##class(Security.Roles).Exists("Downstream_API") Set roles = "Downstream_API," _ roles
    If '##class(Security.Users).Exists(user) {
        Set sc = ##class(Security.Users).Create(user, roles, password, "Shutter production client for the downstream API", ns, "", "", 0, 1, "Used by the production's HTTP operation")
        Quit:$$$ISERR(sc) sc
    } Else {
        Do ##class(Security.Users).AddRoles(user, roles)
        // On a demo instance the client's password is the demo's, whatever an earlier install left, so the stored
        // credential below always matches the user.
        If demo Set sc = ..ResetDemoUser(user, password) Quit:$$$ISERR(sc) sc
    }
    Set $NAMESPACE = ns
    If '##class(Ens.Config.Credentials).%ExistsId("DownstreamAPI") {
        Set sc = ##class(Ens.Config.Credentials).SetCredential("DownstreamAPI", user, password, 1)
    } ElseIf demo {
        Set sc = ##class(Ens.Config.Credentials).SetCredential("DownstreamAPI", user, password, 1)
    }
    Quit sc
}

/// Removes what the downstream system was called before its rename, quietly when absent: the /wards/api web
/// application and its install record, the wards-client user, the Shutter_WardClient role (taken from every user
/// first), the WardsAPI credential and the Wards package's classes. Downstream.Installer removes the Wards_API role
/// and resource. Data in the ^Wards.* globals is not migrated: an instance from before the rename starts afresh.
ClassMethod RemoveOldReceiverNames() As %Status
{
    Set sc = $$$OK
    Try {
        Kill ^Shutter.Config("webapp", "/wards/api")
        If ##class(Ens.Config.Credentials).%ExistsId("WardsAPI") {
            Set sc = ##class(Ens.Config.Credentials).%DeleteId("WardsAPI")
            Quit:$$$ISERR(sc)
        }
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS n FROM %Dictionary.ClassDefinition WHERE Name %STARTSWITH 'Wards.'")
        If rs.%Next() && (rs.%Get("n") > 0) {
            Set sc = $SYSTEM.OBJ.DeletePackage("Wards", "-d")
            Quit:$$$ISERR(sc)
        }
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        If ##class(Security.Applications).Exists("/wards/api") {
            Set sc = ##class(Security.Applications).Delete("/wards/api")
            Quit:$$$ISERR(sc)
        }
        If ##class(Security.Users).Exists("wards-client") {
            Set sc = ##class(Security.Users).Delete("wards-client")
            Quit:$$$ISERR(sc)
        }
        If ##class(Security.Roles).Exists("Shutter_WardClient") {
            Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name FROM Security.Users")
            While rs.%Next() {
                Set user = rs.%Get("Name")
                Kill props
                Continue:$$$ISERR(##class(Security.Users).Get(user, .props))
                Set roles = $LISTFROMSTRING($GET(props("Roles")), ","), at = $LISTFIND(roles, "Shutter_WardClient")
                Continue:'at
                Kill props
                Set props("Roles") = $LISTTOSTRING($LIST(roles, 1, at - 1) _ $LIST(roles, at + 1, *), ",")
                Set sc = ##class(Security.Users).Modify(user, .props)
                Quit:$$$ISERR(sc)
            }
            Quit:$$$ISERR(sc)
            Set sc = ##class(Security.Roles).Delete("Shutter_WardClient")
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The Workflow role that receives approval tasks, and the demo approver as its member.
ClassMethod CreateWorkflowRole(demo As %Boolean) As %Status
{
    Set sc = $$$OK
    Try {
        Set role = "Shutter Approvers"
        If '##class(EnsLib.Workflow.RoleDefinition).%ExistsId(role) {
            Set sc = ##class(EnsLib.Workflow.RoleDefinition).CreateRole(role)
            Quit:$$$ISERR(sc)
            Set r = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(role)
            If $ISOBJECT(r) Set r.Description = "Approve or reject Shutter recovery plans" Do r.%Save()
        }
        If demo {
            If '##class(EnsLib.Workflow.UserDefinition).%ExistsId("approver") {
                Set sc = ##class(EnsLib.Workflow.UserDefinition).CreateUser("approver", "Shutter demo approver")
                Quit:$$$ISERR(sc)
            }
            If '##class(EnsLib.Workflow.RoleMembership).%ExistsId(role _ "||approver") {
                Set sc = ##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(role, "approver", 1, "Approver")
            }
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// /api/shutter (REST, password) and /shutter (the web app's files, when root/www exists) on every install;
/// /downstream/api (the demo receiver's REST API) only on a demo install whose Downstream classes are installed.
ClassMethod CreateWebApps(ns As %String, root As %String, demo As %Boolean = 1) As %Status
{
    Set sc = $$$OK
    Set hasDownstream = demo && ##class(%Dictionary.CompiledClass).%ExistsId("Downstream.API")
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If hasDownstream {
        Kill props
        Set props("NameSpace") = ns
        Set props("Description") = "Shutter: the demo bed-management system's API (the downstream system)"
        Set props("Enabled") = 1
        Set props("AutheEnabled") = 32
        Set props("DispatchClass") = "Downstream.API"
        If ##class(Security.Resources).Exists("Downstream_API") Set props("Resource") = "Downstream_API"
        Set props("UseCookies") = 2
        Set props("CookiePath") = "/downstream/api/"
        If ##class(Security.Applications).Exists("/downstream/api") {
            Set sc = ##class(Security.Applications).Modify("/downstream/api", .props)
        } Else {
            Set sc = ##class(Security.Applications).Create("/downstream/api", .props)
        }
        Quit:$$$ISERR(sc) sc
        Set ^|ns|Shutter.Config("webapp", "/downstream/api") = 1
    }
    Kill props
    Set props("NameSpace") = ns
    Set props("Description") = "Shutter REST API"
    Set props("Enabled") = 1
    // Password (32) or unauthenticated (64): POST /session signs in; every other route checks
    // the caller's resources itself, so an anonymous request gets a JSON 401, not a browser dialog.
    Set props("AutheEnabled") = 96
    Set props("DispatchClass") = "Shutter.API.Dispatch"
    Set props("UseCookies") = 2
    Set props("CookiePath") = "/api/shutter/"
    Set props("MatchRoles") = ":Shutter_WebApp"
    If ##class(Security.Applications).Exists("/api/shutter") {
        Set sc = ##class(Security.Applications).Modify("/api/shutter", .props)
    } Else {
        Set sc = ##class(Security.Applications).Create("/api/shutter", .props)
    }
    Quit:$$$ISERR(sc) sc
    Set ^|ns|Shutter.Config("webapp", "/api/shutter") = 1
    Set www = $SELECT(root = "": "", 1: root _ "www/")
    If (www '= "") && ##class(%File).DirectoryExists(www) {
        Kill props
        Set props("NameSpace") = ns
        Set props("Description") = "Shutter web application"
        Set props("Enabled") = 1
        Set props("AutheEnabled") = 64
        Set props("Path") = www
        Set props("ServeFiles") = 1
        Set props("Recurse") = 1
        Set props("UseCookies") = 2
        Set props("CookiePath") = "/shutter/"
        Set props("MatchRoles") = ":Shutter_WebApp"
        If ##class(Security.Applications).Exists("/shutter") {
            Set sc = ##class(Security.Applications).Modify("/shutter", .props)
        } Else {
            Set sc = ##class(Security.Applications).Create("/shutter", .props)
        }
        Set:$$$ISOK(sc) ^|ns|Shutter.Config("webapp", "/shutter") = 1
    }
    Quit sc
}

/// The production Shutter's items live in: Shutter.Production, unless InstallInto recorded the site's own production
/// (shape B) in ^Shutter.Config("production").
ClassMethod ProductionName() As %String
{
    Set name = $GET(^Shutter.Config("production"))
    Quit $SELECT(name = "": "Shutter.Production", 1: name)
}

/// System default settings for the production: the folders and the downstream API's address, so the
/// production definition carries no paths of its own. Keyed to the named production: Shutter's own by default, or
/// the site's production InstallInto put Shutter's items in. In a site's production the feed's folders have no item,
/// and the receiver's address goes to Shutter's own items by name, never to every item: a "*" row would reach the
/// site's.
ClassMethod ApplyDefaultSettings(production As %String = "Shutter.Production") As %Status
{
    Set sc = $$$OK
    If production = "" Set production = "Shutter.Production"
    Set host = $GET(^Shutter.Config("downstreamHost"), $GET(^Shutter.Config("wardHost"), "127.0.0.1"))
    Set port = $GET(^Shutter.Config("downstreamPort"), $GET(^Shutter.Config("wardPort"), 52773))
    If production = "Shutter.Production" {
        Set values("ADT In", "FilePath") = $GET(^Shutter.Config("dir", "in"))
        Set values("ADT In", "ArchivePath") = $GET(^Shutter.Config("dir", "archive"))
        Set values("ADT In", "WorkPath") = $GET(^Shutter.Config("dir", "work"))
        Set values("*", "HTTPServer") = host, values("*", "HTTPPort") = port
    } Else {
        For item = "Evidence Collector", "Verifier" Set values(item, "HTTPServer") = host, values(item, "HTTPPort") = port
    }
    Set item = ""
    For {
        Set item = $ORDER(values(item))
        Quit:(item="")
        Set name = ""
        For {
            Set name = $ORDER(values(item, name), 1, value)
            Quit:(name="")
            Continue:(value="")
            Set id = production _ "||" _ item _ "||*||" _ name
            Set d = ##class(Ens.Config.DefaultSettings).%OpenId(id)
            If '$ISOBJECT(d) {
                Set d = ##class(Ens.Config.DefaultSettings).%New()
                Set d.ProductionName = production, d.ItemName = item, d.HostClassName = "*", d.SettingName = name
            }
            Set d.SettingValue = value
            Set d.Description = "Set by Shutter.Setup"
            Set sc = d.%Save()
            Quit:$$$ISERR(sc)
        }
        Quit:$$$ISERR(sc)
    }
    Quit sc
}

/// Make Shutter.Production the namespace's production and start it, when the class is compiled. When InstallInto
/// put Shutter's items in the site's own production, there is nothing of Shutter's to start, and that production is
/// never stopped here.
ClassMethod StartProduction() As %Status
{
    Set sc = $$$OK
    Set prod = "Shutter.Production"
    If '##class(%Dictionary.CompiledClass).%ExistsId(prod) Quit sc
    If ..ProductionName() '= prod Quit sc
    Set sc = ..ApplyDefaultSettings()
    Quit:$$$ISERR(sc) sc
    Try {
        Do ##class(Ens.Director).SetAutoStart(prod)
        // While an image is built (SHUTTER_BUILD=1) the instance stops right after: the production
        // starts with the container instead, so nothing is started here.
        If $SYSTEM.Util.GetEnviron("SHUTTER_BUILD") = "1" Quit
        Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
        Quit:$$$ISERR(sc)
        If state = 1 {
            If name '= prod {
                Set sc = ##class(Ens.Director).StopProduction(30, 0)
                Quit:$$$ISERR(sc)
                Set sc = ##class(Ens.Director).StartProduction(prod)
            } Else {
                Set sc = ##class(Ens.Director).UpdateProduction()
            }
        } Else {
            Set sc = ##class(Ens.Director).StartProduction(prod)
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// On a site install (demo = 0): the demo's items of Shutter.Production are switched off, so the production runs
/// with no feed of its own: "ADT In", "ADT to Downstream", "Downstream Out" and "Scenario Player". A site adds its
/// own feed items or uses the intake route. The definition is saved, and a running production takes the change at
/// once. A demo install leaves the items as the class defines them; a reinstall compiles the class afresh (the items
/// enabled again) and switches them off again.
ClassMethod DisableDemoItems() As %Status
{
    Set sc = $$$OK
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Production") Quit sc
    Try {
        Set prod = ##class(Ens.Config.Production).%OpenId("Shutter.Production", , .sc)
        If '$ISOBJECT(prod) Quit
        Set demoItems = $LISTBUILD("ADT In", "ADT to Downstream", "Downstream Out", "Scenario Player"), changed = 0
        For i = 1:1:prod.Items.Count() {
            Set item = prod.Items.GetAt(i)
            If $LISTFIND(demoItems, item.Name) && item.Enabled {
                Set item.Enabled = 0, changed = changed + 1
            }
        }
        If 'changed Quit
        Set sc = prod.%Save()
        Quit:$$$ISERR(sc)
        Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
        Quit:$$$ISERR(sc)
        If (state = 1) && (name = "Shutter.Production") Set sc = ##class(Ens.Director).UpdateProduction()
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

// ---- shape B: Shutter's items inside a site's own production ----

/// Shutter's items inside a production the site already runs, in the current namespace. Does what Install does at
/// namespace level with no demo (the folders, the resources and roles, the Workflow role, the seeds, the web
/// applications, the retention task without the message purge; no demo users, no demo receiver, no credential),
/// records the production's name in ^Shutter.Config("production"), adds Shutter's recovery items to that production
/// (AddItemsTo), writes the default settings keyed to it and, when it is running, updates it in place. It never stops
/// a production and never sets the auto-start production: a production that is not running is left for the site to
/// start. root is the module's directory (IPM's ${root}), for the seeds and the web application's files. Run again
/// after an upgrade, it adds the items that are new. Returns "ok" or the error text.
ClassMethod InstallInto(production As %String, root As %String = "") As %String [ SqlProc ]
{
    Set sc = ..InstallIntoStatus(production, root)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

ClassMethod InstallIntoStatus(production As %String, root As %String = "") As %Status
{
    Set sc = $$$OK
    Try {
        // SQL hands an empty argument over as $CHAR(0): a control character, stripped with the blanks.
        Set production = $ZSTRIP($GET(production), "<>WC")
        If production = "" Set sc = $$$ERROR($$$GeneralError, "InstallInto needs the name of the production Shutter's items go into") Quit
        If '##class(Ens.Config.Production).%ExistsId(production) Set sc = $$$ERROR($$$GeneralError, "No production " _ production _ " in " _ $NAMESPACE) Quit
        Set ns = $NAMESPACE
        If root '= "" Set root = ##class(%File).NormalizeDirectory(root)
        Set ^Shutter.Config("root") = root
        Set ^Shutter.Config("demo") = 0
        Set ^Shutter.Config("production") = production
        Set ^Shutter.Config("installedAt") = ##class(Shutter.Util.Time).NowUTC()
        Set ^Shutter.Config("version") = ..#VERSION
        If $GET(^Shutter.Config("mode")) = "" Set ^Shutter.Config("mode") = "board"
        Set sc = ..CreateFolders() Quit:$$$ISERR(sc)
        Set sc = ..CreateSecurity(ns, 0) Quit:$$$ISERR(sc)
        Set sc = ..CreateWorkflowRole(0) Quit:$$$ISERR(sc)
        Set sc = ..SeedAll(root) Quit:$$$ISERR(sc)
        Set sc = ..CreateWebApps(ns, root, 0) Quit:$$$ISERR(sc)
        // The retention task only: the site's own purge rules govern the messages of its production.
        Set r = ..EnsureRetentionTasks(ns, "", 0)
        If $EXTRACT(r, 1, 6) = "ERROR:" Set sc = $$$ERROR($$$GeneralError, "Retention tasks: " _ r) Quit
        Set sc = ..AddItemsTo(production, .added) Quit:$$$ISERR(sc)
        Set ^Shutter.Config("production", "itemsAdded") = added
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The seeds: the board members, the model prices and, from the module's root, the block reasons, the site profile,
/// the catalogue and the recorded runs. The same list as Install's.
ClassMethod SeedAll(root As %String) As %Status [ Private ]
{
    Set sc = ##class(Shutter.Store.BoardMember).Seed() Quit:$$$ISERR(sc) sc
    Set sc = ##class(Shutter.Store.ModelPrice).Seed() Quit:$$$ISERR(sc) sc
    If (root '= "") && ##class(%File).Exists(root _ "knowledge/block-reasons.json") {
        Set sc = ##class(Shutter.Store.BlockReason).SeedFromFile(root _ "knowledge/block-reasons.json", .reasons)
        Quit:$$$ISERR(sc) sc
        Set ^Shutter.Config("blockReasons") = reasons
    }
    If root '= "" {
        Set sc = ##class(Shutter.Store.SiteProfile).SeedFromFile(root _ "knowledge/site/profile.json") Quit:$$$ISERR(sc) sc
        Set sc = ##class(Shutter.Catalogue.Entry).SeedFromFile(root _ "knowledge/catalogue/catalogue.json", .entries) Quit:$$$ISERR(sc) sc
        Set ^Shutter.Config("catalogue", "entries") = $GET(entries, 0)
    }
    If (root '= "") && ##class(%File).DirectoryExists(root _ "fixtures/records") {
        Set sc = ##class(Shutter.Bridge.Record).ImportDir(root _ "fixtures/records", .count)
        Quit:$$$ISERR(sc) sc
        Set ^Shutter.Config("recordsImported") = count
    }
    Quit $$$OK
}

/// The items InstallInto adds to a site's production, in Shutter.Production's order: the recovery side, the index and
/// the board, never the feed or the demo (ADT In, ADT to Downstream, Downstream Out, Scenario Player). Case Intake and
/// Case Intake Store are added once Shutter.Production defines them. A new recovery item is listed here too.
Parameter INSTALLITEMS = "HL7 Index,Escalation Mail,Case Workflow,Incident Workflow,Evidence Collector,Agent Conformance,Agent Encounter,Agent Impact,Agent Coordinator,Agent Board,Gate,Shutter Approvers,Shutter API,Verifier,Case Intake,Case Intake Store";

/// Adds Shutter's items (INSTALLITEMS) to the named production, each as Shutter.Production's compiled definition has
/// it (class, pool size, enabled, foreground, comment, category, trace flag, schedule and settings), when the
/// production has no item of that name; an item whose class is not compiled here is skipped. Then saves the
/// definition, writes the default settings keyed to the production (ApplyDefaultSettings) and, when that production
/// is running, updates it in place; a stopped one is left for the site to start. added is the number of items created.
ClassMethod AddItemsTo(production As %String, Output added As %Integer) As %Status
{
    Set sc = $$$OK, added = 0
    Try {
        If production = "" Set sc = $$$ERROR($$$GeneralError, "No production named") Quit
        Set source = ##class(Ens.Config.Production).%OpenId("Shutter.Production")
        If '$ISOBJECT(source) Set sc = $$$ERROR($$$GeneralError, "Shutter.Production is not compiled in " _ $NAMESPACE _ ": nothing to copy the items from") Quit
        Set target = ##class(Ens.Config.Production).%OpenId(production)
        If '$ISOBJECT(target) Set sc = $$$ERROR($$$GeneralError, "No production " _ production _ " in " _ $NAMESPACE) Quit
        // Shutter's own production has them all already (the same id opens the same object).
        If target '= source {
            For i = 1:1:target.Items.Count() Set have(target.Items.GetAt(i).Name) = i
            For i = 1:1:source.Items.Count() Set from(source.Items.GetAt(i).Name) = i
            Set names = ..#INSTALLITEMS
            For n = 1:1:$LENGTH(names, ",") {
                Set name = $PIECE(names, ",", n)
                If '$DATA(have(name)) && $DATA(from(name)) {
                    Set item = source.Items.GetAt(from(name))
                    If ##class(%Dictionary.CompiledClass).%ExistsId(item.ClassName) {
                        Set sc = ..CopyItem(item, target) Quit:$$$ISERR(sc)
                        Set added = added + 1
                    }
                }
            }
            Quit:$$$ISERR(sc)
            If added > 0 {
                // The class definition (what a start reads) and the configuration rows (what the portal and SQL read).
                Set sc = target.SaveToClass() Quit:$$$ISERR(sc)
                Set sc = target.%Save() Quit:$$$ISERR(sc)
            }
        }
        Set sc = ..ApplyDefaultSettings(production) Quit:$$$ISERR(sc)
        Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state) Quit:$$$ISERR(sc)
        If (state = 1) && (name = production) Set sc = ##class(Ens.Director).UpdateProduction()
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// One item of Shutter.Production copied into another production's definition.
ClassMethod CopyItem(item As Ens.Config.Item, target As Ens.Config.Production) As %Status [ Private ]
{
    Set copy = ##class(Ens.Config.Item).%New(item.ClassName)
    Set copy.Name = item.Name, copy.ClassName = item.ClassName, copy.PoolSize = item.PoolSize, copy.Enabled = item.Enabled
    Set copy.Foreground = item.Foreground, copy.Comment = item.Comment, copy.Category = item.Category
    Set copy.LogTraceEvents = item.LogTraceEvents, copy.Schedule = item.Schedule
    For j = 1:1:item.Settings.Count() {
        Set s = item.Settings.GetAt(j)
        Set t = ##class(Ens.Config.Setting).%New()
        Set t.Target = s.Target, t.Name = s.Name, t.Value = s.Value
        Do copy.Settings.Insert(t)
    }
    Quit target.Items.Insert(copy)
}

/// The two daily housekeeping tasks (A14): "Shutter message purge" (the standard Ens.Util.Tasks.Purge: every message
/// type in the namespace, bodies too, sessions kept whole) and "Shutter retention" (Shutter.Util.RetentionTask:
/// idempotency keys older than a day, closed cases past the retention only when switched on). The retention task is
/// always made; the purge task only when purge is 1, keeping days days of messages, because a namespace-wide purge
/// belongs only in a namespace that holds nothing but Shutter. The defaults come from the environment of the process
/// that runs the install (the shell that runs zpm, not the running container): days from SHUTTER_MESSAGE_DAYS (90 when
/// unset or not a positive whole number), purge from SHUTTER_MESSAGE_PURGE (1 or 0; when unset, 1 on a demo instance
/// and 0 otherwise, read from ^Shutter.Config("demo")). Each task is made once: on an instance that already has it,
/// change the days or remove the purge in the Task Manager (System Operation > Task Manager); this method leaves an
/// existing task as it is, whatever the arguments say. Returns "message purge created (N days)|exists|off; retention
/// created|exists", or "ERROR: ..." . From SQL with no arguments (SELECT Shutter.Setup_EnsureRetentionTasks()) the
/// defaults above apply.
ClassMethod EnsureRetentionTasks(ns As %String = "", days As %String = "", purge As %String = "") As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("%Admin_Task", "USE") && '$SYSTEM.Security.Check("Shutter_Operate", "USE") Quit "Shutter_Operate is required"
    // SQL hands an empty argument to a procedure as $CHAR(0).
    If ns = $CHAR(0) Set ns = ""
    If days = $CHAR(0) Set days = ""
    If purge = $CHAR(0) Set purge = ""
    If ns = "" Set ns = $NAMESPACE
    Set days = ..MessageDays(days), purge = ..MessagePurge(purge)
    Set exists = (..TaskId("Shutter message purge") '= ""), made = 0
    If purge && 'exists {
        Set sc = ..EnsureTask("Shutter message purge", ns, "Ens.Util.Tasks.Purge", "Shutter: purge messages, logs and traces older than " _ days _ " days, sessions kept whole", $LISTBUILD("NumberOfDaysToKeep", days, "BodiesToo", 1, "KeepIntegrity", 1, "TypesToPurge", "all"), 9600, .made)
        If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
        If made Set exists = 1, ^|ns|Shutter.Config("messageDays") = days
    }
    // The install's record, for a Doctor report by a caller without access to the Task Manager.
    Set ^|ns|Shutter.Config("purgeTask") = exists
    Set out = "message purge " _ $SELECT(made: "created (" _ days _ " days)", exists: "exists", 1: "off")
    Set sc = ..EnsureTask("Shutter retention", ns, "Shutter.Util.RetentionTask", "Shutter: idempotency keys older than a day, and closed cases past the retention when switched on", $LISTBUILD("RetentionDays", 30, "PurgeClosedCases", 0), 9900, .made)
    If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
    Quit out _ "; retention " _ $SELECT(made: "created", 1: "exists")
}

/// The days of messages the purge task keeps: the argument, else SHUTTER_MESSAGE_DAYS, else 90; a value that is not a
/// positive whole number counts as unset.
ClassMethod MessageDays(days As %String = "") As %Integer [ Private ]
{
    Set days = $ZSTRIP(days, "<>W")
    If days = "" Set days = $ZSTRIP($SYSTEM.Util.GetEnviron("SHUTTER_MESSAGE_DAYS"), "<>W")
    If (days '?1.N) || (+days < 1) Quit 90
    Quit +days
}

/// Whether the message purge task is wanted: the argument, else SHUTTER_MESSAGE_PURGE, each 1 or 0; anything else
/// means 1 on a demo instance and 0 otherwise.
ClassMethod MessagePurge(purge As %String = "") As %Boolean [ Private ]
{
    Set purge = $ZSTRIP(purge, "<>W")
    If purge = "" Set purge = $ZSTRIP($SYSTEM.Util.GetEnviron("SHUTTER_MESSAGE_PURGE"), "<>W")
    If (purge = "1") || (purge = "0") Quit +purge
    Quit ''$GET(^Shutter.Config("demo"))
}

/// The id of the Task Manager task of this name, or "" when there is none (or the caller cannot read %SYS).
ClassMethod TaskId(name As %String) As %String [ Private ]
{
    Set id = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM %SYS.Task WHERE Name = ?", name)
        If rs.%Next() Set id = rs.%Get("ID")
    } Catch ex {
        Set id = ""
    }
    Quit id
}

/// A daily task by name, created when none of that name exists (startSeconds after midnight, local time).
ClassMethod EnsureTask(name As %String, ns As %String, class As %String, description As %String, settings As %List, startSeconds As %Integer, Output made As %Boolean) As %Status [ Private ]
{
    Set made = 0, sc = $$$OK
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM %SYS.Task WHERE Name = ?", name)
        If rs.%Next() Quit
        Set task = ##class(%SYS.Task).%New()
        Set task.Name = name, task.NameSpace = ns, task.TaskClass = class, task.Description = description
        Set task.TimePeriod = 0, task.TimePeriodEvery = 1, task.DailyFrequency = 0
        Set task.DailyStartTime = startSeconds, task.DailyEndTime = 0
        Set task.RunAsUser = $USERNAME
        Set task.Settings = settings
        Set sc = task.%Save()
        If $$$ISOK(sc) Set made = 1
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Empty Shutter's own tables (cases and everything attached to them, recordings excepted) on a
/// demo instance. Refused elsewhere. Returns the number of tables emptied or the error.
ClassMethod PurgeStore() As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("Shutter_Operate", "USE") Quit "Shutter_Operate is required"
    If '$GET(^Shutter.Config("demo")) Quit "ERROR: not a demo instance"
    Set n = 0
    For cls = "Shutter.Store.CaseToken", "Shutter.Store.ChainItem", "Shutter.Store.Chain", "Shutter.Store.IncidentEvent", "Shutter.Store.Incident", "Shutter.Store.Verification", "Shutter.Store.ExecutionAttempt", "Shutter.Store.Approval", "Shutter.Store.Rehearsal", "Shutter.Store.GateDecision", "Shutter.Store.Plan", "Shutter.Store.Finding", "Shutter.Store.AgentRun", "Shutter.Store.SnapshotItem", "Shutter.Store.Snapshot", "Shutter.Store.CaseEvent", "Shutter.Store.Case", "Shutter.Store.Idempotency", "Shutter.Bridge.ToolCall" {
        Set sc = $CLASSMETHOD(cls, "%KillExtent")
        If $$$ISERR(sc) Quit
        Set n = n + 1
    }
    If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
    // The Workflow tasks of the purged cases and incidents (T31b): the engine keeps them, and with the counters reset a
    // new I-000001 would list every earlier I-000001's tasks. Each task's worklist rows go first, then the task.
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM EnsLib_Workflow.TaskResponse WHERE ""%Subject"" LIKE 'Shutter %'")
    While rs.%Next() {
        Set id = rs.%Get("ID")
        Do ##class(%SQL.Statement).%ExecDirectNoPriv(, "DELETE FROM EnsLib_Workflow.Worklist WHERE Task = ?", id)
        Do ##class(EnsLib.Workflow.TaskResponse).%DeleteId(id)
    }
    // Worklist rows whose task is gone (a task deleted by hand) would show as broken entries in the inbox.
    Do ##class(%SQL.Statement).%ExecDirectNoPriv(, "DELETE FROM EnsLib_Workflow.Worklist WHERE Task NOT IN (SELECT ID FROM EnsLib_Workflow.TaskResponse)")
    Kill ^Shutter.Counter, ^Shutter.Scenarios
    Quit n
}

/// Restart the production so that recompiled business hosts pick up their new code. Returns "ok"
/// or the error.
ClassMethod RestartProduction() As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("%Ens_ProductionRun", "USE") Quit "%Ens_ProductionRun is required"
    Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
    If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
    If state = 1 {
        Set sc = ##class(Ens.Director).StopProduction(60, 0)
        If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
    }
    // The site's own production (InstallInto) is started again as it was; Shutter's own through StartProduction.
    Set prod = ..ProductionName()
    If prod '= "Shutter.Production" {
        Set sc = ##class(Ens.Director).StartProduction(prod)
    } Else {
        Set sc = ..StartProduction()
    }
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

/// The instance's licence counters, for the readiness report and for diagnosing refused jobs.
ClassMethod LicenseInfo() As %String [ SqlProc ]
{
    Set o = {}
    Try {
        Set o."license_type" = $SYSTEM.License.KeyLicenseType()
        Set o."units_consumed" = $SYSTEM.License.LUConsumed()
        Set o."units_available" = $SYSTEM.License.LUAvailable()
        Set o."max_connections" = $SYSTEM.License.MaxConnections()
    } Catch ex {
        Set o.error = ex.DisplayString()
    }
    Quit o.%ToJSON()
}

/// Can this process start a background job? For diagnosing a runner that cannot.
ClassMethod TestJob() As %String [ SqlProc ]
{
    Set o = {}
    Try {
        Job ##class(Shutter.Setup).NoOp()::5
        Do o.%Set("started", $TEST, "boolean")
        Set o.child = $ZCHILD
    } Catch ex {
        Set o.error = ex.DisplayString()
    }
    Set o.user = $USERNAME, o.roles = $ROLES, o.namespace = $NAMESPACE
    Quit o.%ToJSON()
}

ClassMethod NoOp()
{
    Hang 1
}

/// The last lines of the instance's messages.log, for diagnosis through SQL.
ClassMethod TailLog(lines As %Integer = 40) As %String [ SqlProc ]
{
    Set path = ##class(%File).ManagerDirectory() _ "messages.log"
    Set f = ##class(%Stream.FileCharacter).%New()
    Set f.Filename = path
    Set n = 0
    While 'f.AtEnd { Set n = n + 1, buf(n # lines) = f.ReadLine() }
    Set out = "", i = n # lines
    For k = 1:1:lines {
        Set i = (i + 1) # lines
        If $DATA(buf(i)) Set out = out _ buf(i) _ $CHAR(10)
    }
    Quit out
}

/// A readiness report as JSON: what is installed, what runs, what is missing.
ClassMethod Doctor() As %String [ SqlProc ]
{
    Set r = {}
    Set r.namespace = $NAMESPACE
    Set r.version = $GET(^Shutter.Config("version"))
    Set r."installed_at" = $GET(^Shutter.Config("installedAt"))
    Do r.%Set("demo", ''$GET(^Shutter.Config("demo")), "boolean")
    Set r.mode = $GET(^Shutter.Config("mode"))
    Set r."adt_in" = $GET(^Shutter.Config("adtIn"))
    Do r.%Set("interoperability", ''##class(%EnsembleMgr).IsEnsembleNamespace($NAMESPACE), "boolean")
    // The production Shutter's items live in: its own, or the site's that InstallInto put them in.
    Set prod = ..ProductionName()
    Set r."shutter_production" = prod
    Do r.%Set("production_class", ''##class(%Dictionary.CompiledClass).%ExistsId(prod), "boolean")
    Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
    Set text = $CASE(state, 1: "running", 2: "stopped", 3: "suspended", 4: "troubled", 5: "network stopped", : state)
    // Another production running in the namespace leaves Shutter's items without jobs: not "running" for Shutter.
    If (state = 1) && (name '= prod) Set text = "another production running"
    Set r.production = name, r."production_state" = text
    Do r.%Set("ward_classes", ''##class(%Dictionary.CompiledClass).%ExistsId("Downstream.API"), "boolean")
    Do r.%Set("aihub_runner", ''##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Bridge.Runner.AIHub"), "boolean")
    Do r.%Set("ai_hub_present", ''##class(%Dictionary.CompiledClass).%ExistsId("%AI.Agent"), "boolean")
    &sql(SELECT COUNT(*) INTO :members FROM Shutter_Store.BoardMember WHERE Enabled = 1)
    Set r."board_members" = +members
    &sql(SELECT COUNT(*) INTO :records FROM Shutter_Bridge.Record)
    Set r.recordings = +records
    &sql(SELECT COUNT(*) INTO :cases FROM Shutter_Store."Case")
    Set r.cases = +cases
    Set r.license = ##class(%DynamicObject).%FromJSON(..LicenseInfo())
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Do r.%Set("api_webapp", ''##class(Security.Applications).Exists("/api/shutter"), "boolean")
        Do r.%Set("ui_webapp", ''##class(Security.Applications).Exists("/shutter"), "boolean")
        Do r.%Set("wards_webapp", ''##class(Security.Applications).Exists("/downstream/api"), "boolean")
        // The message purge task (a demo instance has one; a site only when SHUTTER_MESSAGE_PURGE said so) and the days
        // it keeps, read from the Task Manager so a change made there shows.
        Set taskId = ..TaskId("Shutter message purge")
        Do r.%Set("purge_task", taskId '= "", "boolean")
        If taskId '= "" {
            Set task = ##class(%SYS.Task).%OpenId(taskId)
            If $ISOBJECT(task) && $LISTVALID(task.Settings) {
                For i = 1:2:$LISTLENGTH(task.Settings) {
                    If $LISTGET(task.Settings, i) = "NumberOfDaysToKeep" Set r."message_days" = +$LISTGET(task.Settings, i + 1)
                }
            }
        }
        Set r."webapps_checked" = "live"
    } Catch ex {
        // A caller without %SYS access gets what the install recorded.
        Do r.%Set("api_webapp", ''$GET(^Shutter.Config("webapp", "/api/shutter")), "boolean")
        Do r.%Set("ui_webapp", ''$GET(^Shutter.Config("webapp", "/shutter")), "boolean")
        Do r.%Set("wards_webapp", ''$GET(^Shutter.Config("webapp", "/downstream/api")), "boolean")
        Do r.%Set("purge_task", ''$GET(^Shutter.Config("purgeTask")), "boolean")
        If $GET(^Shutter.Config("purgeTask")) && ($GET(^Shutter.Config("messageDays")) '= "") Set r."message_days" = +^Shutter.Config("messageDays")
        Set r."webapps_checked" = "install record"
    }
    Quit r.%ToJSON()
}

// ---- the aihub module ----

/// Installs the aihub module's runtime pieces: the provider configuration from the environment
/// when ANTHROPIC_API_KEY is set (the model from SHUTTER_MODEL), and the knowledge bases from
/// the module's knowledge/ folder. Returns JSON. Prints no secret.
ClassMethod InstallAIHub(root As %String = "") As %String [ SqlProc ]
{
    Set out = {}
    Try {
        If root '= "" Set root = ##class(%File).NormalizeDirectory(root)
        Do out.%Set("ai_hub_present", ''##class(%Dictionary.CompiledClass).%ExistsId("%AI.Agent"), "boolean")
        Do out.%Set("descriptor_registry", ..RebuildDescriptorRegistry(), "boolean")
        Set key = $SYSTEM.Util.GetEnviron("ANTHROPIC_API_KEY")
        If key '= "" {
            Set out.provider = ..ConfigureProvider(key, $SYSTEM.Util.GetEnviron("SHUTTER_MODEL"))
        } Else {
            Set out.provider = $SELECT(..ProviderConfigured(): "configured earlier", 1: "no key in the environment: the agents replay recordings")
        }
        Set kdir = ""
        If (root '= "") && ##class(%File).DirectoryExists(root _ "knowledge/") Set kdir = root _ "knowledge/"
        If (kdir = "") && ($GET(^Shutter.Config("root")) '= "") && ##class(%File).DirectoryExists(^Shutter.Config("root") _ "knowledge/") Set kdir = ^Shutter.Config("root") _ "knowledge/"
        If (kdir '= "") && ##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Knowledge.Library") {
            Set out.knowledge = ##class(%DynamicObject).%FromJSON($CLASSMETHOD("Shutter.Knowledge.Library", "BuildAll", kdir))
        } Else {
            Set out.knowledge = $SELECT(kdir = "": "no knowledge folder found", 1: "no library class")
        }
        Set out.mode = ..RecordAgentMode($SYSTEM.Util.GetEnviron("SHUTTER_AGENT_MODE"))
        Set ^Shutter.Config("aihub", "installedAt") = ##class(Shutter.Util.Time).NowUTC()
        Set ^Shutter.Config("aihub", "root") = root
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out.%ToJSON()
}

/// InstallAIHub as a %Status: what the aihub module's manifest invokes (the Invoke checks the status, so an install
/// that stopped at an error stops the load, and the image build with it). Writes InstallAIHub's JSON, which holds no
/// secret. A knowledge base that did not build is reported there and does not fail the install.
ClassMethod InstallAIHubStatus(root As %String = "") As %Status
{
    Set sc = $$$OK
    Try {
        Set json = ..InstallAIHub(root)
        Write !, "aihub install: ", json, !
        Set out = ##class(%DynamicObject).%FromJSON(json)
        If out.error '= "" Set sc = $$$ERROR($$$GeneralError, "The aihub install: " _ out.error)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Puts the provider key in the IRIS wallet (collection Shutter, secret Anthropic) and writes the
/// Config Store configuration AI.LLM.Shutter that the agents name, with the model (default
/// claude-opus-5-5). Replaces an earlier key. Returns a short status; never the key.
ClassMethod ConfigureProvider(key As %String, model As %String = "") As %String [ SqlProc ]
{
    If model = "" Set model = "claude-opus-5-5"
    If $ZSTRIP(key, "<>W") = "" Quit "no key given"
    Set key = $ZSTRIP(key, "<>W")
    Try {
        Set sc = ..EnsureSecretResource()
        If $$$ISERR(sc) Return "resource: " _ $SYSTEM.Status.GetErrorText(sc)
        // A fresh AI Hub instance has an empty Config Store descriptor registry, and AI.LLM configurations
        // fail validation ("No descriptor found for AI.LLM") until it is rebuilt.
        Do ..RebuildDescriptorRegistry()
        Try {
            Do $CLASSMETHOD("%Wallet.Collection", "Create", "Shutter", {"UseResource": "Shutter_Secrets", "EditResource": "Shutter_Secrets"})
        } Catch {
        }
        Try {
            Do $CLASSMETHOD("%Wallet.KeyValue", "Delete", "Shutter.Anthropic")
        } Catch {
        }
        Set sc = $CLASSMETHOD("%Wallet.KeyValue", "Create", "Shutter.Anthropic", {"Usage": "CUSTOM", "Secret": {"key": (key)}})
        If $$$ISERR(sc) Return "wallet: " _ $SYSTEM.Status.GetErrorText(sc)
        Try {
            Do $CLASSMETHOD("%ConfigStore.Configuration", "Delete", "AI.LLM.Shutter")
        } Catch {
        }
        Set config = {"model_provider": "anthropic", "model": (model), "api_key": "secret://Shutter.Anthropic#key"}
        Set sc = $CLASSMETHOD("%ConfigStore.Configuration", "Create", "AI", "LLM", "", "Shutter", config)
        If $$$ISERR(sc) Return "config store: " _ $SYSTEM.Status.GetErrorText(sc)
        Set ^Shutter.Config("aihub", "provider") = "AI.LLM.Shutter"
        Set ^Shutter.Config("aihub", "model") = model
        // A digest of the key, never the key: a later start compares the environment's key against it.
        Set ^Shutter.Config("aihub", "keyDigest") = ##class(Shutter.Util.Digest).SHA256Hex(key)
        Set ^Shutter.Config("aihub", "providerConfiguredAt") = ##class(Shutter.Util.Time).NowUTC()
        Return "ok: AI.LLM.Shutter, model " _ model
    } Catch ex {
        Return "error: " _ ex.DisplayString()
    }
}

/// Registers the Config Store descriptors AI Hub ships (AI.LLM, AI.MCP) in this namespace; a fresh
/// instance has none. Harmless when they are there already or when the class is absent.
ClassMethod RebuildDescriptorRegistry() As %Boolean
{
    Try {
        If '##class(%Dictionary.CompiledClass).%ExistsId("%ConfigStore.DescriptorManager") Return 0
        Do $CLASSMETHOD("%ConfigStore.DescriptorManager", "RebuildRegistry")
        Return 1
    } Catch ex {
        Return 0
    }
}

/// The resource guarding the wallet collection, created with no public permission. The production's jobs run as
/// _Ensemble, whose role %All holds every resource, so they resolve the secret through the Config Store; any other
/// account needs a role that grants Shutter_Secrets.
ClassMethod EnsureSecretResource() As %Status [ Private ]
{
    Set sc = $$$OK
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        If '##class(Security.Resources).Exists("Shutter_Secrets") {
            Set sc = ##class(Security.Resources).Create("Shutter_Secrets", "Shutter: the provider key in the wallet", "")
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Records the agents' mode for items set to auto (live, record or replay); anything else leaves auto
/// to decide (live when a provider is configured, else replay). Returns what applies.
ClassMethod RecordAgentMode(mode As %String) As %String [ SqlProc ]
{
    Set mode = $ZCONVERT($ZSTRIP(mode, "<>W"), "L")
    If $LISTFIND($LISTBUILD("live", "record", "replay"), mode) {
        Set ^Shutter.Config("aihub", "mode") = mode
        Quit mode
    }
    Kill ^Shutter.Config("aihub", "mode")
    Quit "auto"
}

/// Whether the configured provider was written from this key (by its digest).
ClassMethod ProviderKeyMatches(key As %String) As %Boolean
{
    // No digest yet (a configuration from before it was recorded): answer no, so the start writes the key again and
    // stamps it once.
    Set stored = $GET(^Shutter.Config("aihub", "keyDigest"))
    If stored = "" Quit 0
    Quit stored = ##class(Shutter.Util.Digest).SHA256Hex($ZSTRIP(key, "<>W"))
}

/// Re-reads the knowledge files that changed since they were last read (by their modification stamps): the block
/// reasons, the catalogue, the site profile seed and the recordings. Run at production start, so a rebuilt image's
/// knowledge reaches the data a volume kept. Returns a JSON object naming what was re-read.
ClassMethod RefreshKnowledge(root As %String = "") As %String [ SqlProc ]
{
    Set out = {}
    // From SQL, another root than the installed one needs the approver's right: it replaces the knowledge wholesale.
    If (root '= "") && $ISOBJECT($GET(%sqlcontext)) && '$SYSTEM.Security.Check("Shutter_Approve", "USE") {
        Set out.error = "Shutter_Approve is required to refresh the knowledge from another root"
        Quit out.%ToJSON()
    }
    If root = "" Set root = $GET(^Shutter.Config("root"))
    If root = "" Quit out.%ToJSON()
    Set root = ##class(%File).NormalizeDirectory(root)
    Set files("blockReasons") = root _ "knowledge/block-reasons.json"
    Set files("catalogue") = root _ "knowledge/catalogue/catalogue.json"
    Set files("siteProfile") = root _ "knowledge/site/profile.json"
    // The recorded runs are the demo's (InstallStatus imports them only with demo = 1): a site instance skips them.
    If $GET(^Shutter.Config("demo")) Set files("records") = root _ "fixtures/records"
    Set name = ""
    For {
        Set name = $ORDER(files(name)) Quit:name=""
        Set path = files(name), isDir = (name = "records")
        If isDir { Continue:'##class(%File).DirectoryExists(path) } Else { Continue:'##class(%File).Exists(path) }
        Set stamp = $SELECT(isDir: ..DirectoryStamp(path), 1: ##class(%File).GetFileDateModified(path, 1) _ ":" _ ##class(%File).GetFileSize(path))
        // The recordings were once imported without UTF-8 (an arrow read as mojibake): the reader's version in the stamp
        // makes an instance that kept its data import them again, once, though their files have not changed.
        If name = "records" Set stamp = "utf8:" _ stamp
        Continue:($GET(^Shutter.Config("stamp", name)) = stamp)
        Set sc = ..ReseedOne(name, path, .n)
        If $$$ISOK(sc) {
            Set ^Shutter.Config("stamp", name) = stamp
            Do out.%Set(name, $SELECT($GET(n) = "": "reread", 1: n))
        } Else {
            Do out.%Set(name, "error: " _ $SYSTEM.Status.GetErrorText(sc))
        }
    }
    // The aihub module's search collections (the contract, lifecycle, effects and playbooks the agents search): rebuilt
    // when their files change, as the rest is, so a new image's knowledge reaches the collections a volume kept
    If ##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Knowledge.Library") {
        Set kdir = root _ "knowledge/", stamp = "", list = $PARAMETER("Shutter.Knowledge.Library", "COLLECTIONS")
        For i = 1:1:$LENGTH(list, ",") {
            Set coll = $PIECE(list, ",", i)
            If ##class(%File).DirectoryExists(kdir _ coll) Set stamp = stamp _ coll _ "=" _ ..DirectoryStamp(kdir _ coll) _ ";"
        }
        If (stamp '= "") && ($GET(^Shutter.Config("stamp", "searchKnowledge")) '= stamp) {
            Try {
                Set built = ##class(%DynamicObject).%FromJSON($CLASSMETHOD("Shutter.Knowledge.Library", "BuildAll", kdir))
                // A collection that failed to build ("unavailable: ...", "failed: ...") is tried again at the next start
                Set ok = 1, it = built.%GetIterator()
                While it.%GetNext(, .v) { If '$ISOBJECT(v) && (v '= "no folder") Set ok = 0 }
                If ok Set ^Shutter.Config("stamp", "searchKnowledge") = stamp
                Do out.%Set("searchKnowledge", built)
            } Catch ex {
                Do out.%Set("searchKnowledge", "error: " _ ex.DisplayString())
            }
        }
    }
    Quit out.%ToJSON()
}

/// One knowledge file re-read; n is what it counted, when it counts.
ClassMethod ReseedOne(name As %String, path As %String, Output n As %String) As %Status [ Private ]
{
    Set n = "", sc = $$$OK
    Try {
        If name = "blockReasons" {
            Set sc = ##class(Shutter.Store.BlockReason).SeedFromFile(path, .n)
            If $$$ISOK(sc) Set ^Shutter.Config("blockReasons") = n
        } ElseIf name = "catalogue" {
            Set sc = ##class(Shutter.Catalogue.Entry).SeedFromFile(path, .n)
            If $$$ISOK(sc) Set ^Shutter.Config("catalogue", "entries") = $GET(n, 0)
        } ElseIf name = "siteProfile" {
            Set sc = ##class(Shutter.Store.SiteProfile).SeedFromFile(path)
        } Else {
            Set sc = ##class(Shutter.Bridge.Record).ImportDir(path, .n)
            If $$$ISOK(sc) Set ^Shutter.Config("recordsImported") = n
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// A stamp of a folder's files: each name with its modification time and size.
ClassMethod DirectoryStamp(dir As %String) As %String [ Private ]
{
    Set stamp = ""
    Set rs = ##class(%ResultSet).%New("%File:FileSet")
    Do rs.Execute(dir, "*", "Name")
    While rs.Next() {
        Set stamp = stamp _ "|" _ rs.Get("ItemName") _ ":" _ rs.Get("DateModified") _ ":" _ rs.Get("Size")
    }
    Quit ##class(Shutter.Util.Digest).SHA256Hex(stamp)
}

/// Whether ConfigureProvider has written AI.LLM.Shutter. Read from the module's own record, so that
/// callers without the right to read the Config Store (the API's users, the production's jobs) get the
/// same answer as those with it.
ClassMethod ProviderConfigured() As %Boolean
{
    Quit $GET(^Shutter.Config("aihub", "provider")) '= ""
}

/// Forgets the provider configuration: removes AI.LLM.Shutter and the wallet secret, and the record.
/// The agents replay recordings again. Returns a short status.
ClassMethod ClearProvider() As %String [ SqlProc ]
{
    Try {
        Do $CLASSMETHOD("%ConfigStore.Configuration", "Delete", "AI.LLM.Shutter")
    } Catch {
    }
    Try {
        Do $CLASSMETHOD("%Wallet.KeyValue", "Delete", "Shutter.Anthropic")
    } Catch {
    }
    Kill ^Shutter.Config("aihub", "provider"), ^Shutter.Config("aihub", "model"), ^Shutter.Config("aihub", "providerConfiguredAt"), ^Shutter.Config("aihub", "keyDigest")
    Quit "ok: no provider configured; the agents replay recordings"
}

/// The system monitor's state: 0 ok, 1 warn, 2 alert (what Docker's health check reads through iris qlist).
ClassMethod MonitorState() As %Integer [ SqlProc ]
{
    Quit $SYSTEM.Monitor.State()
}

/// After a container starts: clears the system monitor's alerts, which Docker's health check reads, when
/// every severe line in the messages log is one of the two known startup alerts: "failed over from node"
/// (the image ran IRIS during its build, under the build host's name) and the AI Hub preview's own startup
/// error (Sharding, METHOD DOES NOT EXIST). Any other severe line leaves the state as it is. Returns what
/// it did. Called by after-start.sh.
/// A messages.log line's time ("mm/dd/yy-hh:mm:ss:mmm ...") in seconds, or "" when it has none or it cannot be read.
ClassMethod LogSeconds(line As %String) As %String [ Private ]
{
    Set out = ""
    Try {
        Set stamp = $PIECE(line, " ", 1)
        If $LENGTH(stamp, "-") '= 2 Quit
        Set d = $PIECE(stamp, "-", 1), t = $PIECE($PIECE(stamp, "-", 2), ":", 1, 3)
        Set mm = $PIECE(d, "/", 1), dd = $PIECE(d, "/", 2), yy = $PIECE(d, "/", 3)
        If (mm = "") || (dd = "") || (yy = "") || ($LENGTH(t, ":") '= 3) Quit
        If $LENGTH(yy) = 2 Set yy = 2000 + yy
        Set h = $ZDATETIMEH(yy _ "-" _ $TRANSLATE($JUSTIFY(mm, 2), " ", "0") _ "-" _ $TRANSLATE($JUSTIFY(dd, 2), " ", "0") _ " " _ t, 3, 1)
        Set out = ($PIECE(h, ",", 1) * 86400) + $PIECE(h, ",", 2)
    } Catch ex {
        Set out = ""
    }
    Quit out
}

ClassMethod ClearStartupAlerts(lines As %Integer = 400) As %String [ SqlProc ]
{
    Try {
        Set before = $SYSTEM.Monitor.State()
        Set log = ..TailLog(lines)
        // Only this start: the image's log also holds the lines of the IRIS run during the build.
        Set total = $LENGTH(log, $CHAR(10)), from = 1, startedAt = ""
        For i = 1:1:total {
            If $PIECE(log, $CHAR(10), i) [ "Startup of InterSystems IRIS" Set from = i, startedAt = ..LogSeconds($PIECE(log, $CHAR(10), i))
        }
        Set severe = 0, known = 0, other = ""
        For i = from:1:total {
            Set line = $PIECE(log, $CHAR(10), i)
            // "mm/dd/yy-hh:mm:ss:mmm (pid) <severity> [Source] text"
            Set sev = $PIECE($PIECE(line, ") ", 2), " ", 1)
            If (sev '= "2") && (sev '= "3") Continue
            Set severe = severe + 1
            // Known only within three minutes of the start: a genuine failover or sharding alert later is never masked.
            Set at = ..LogSeconds(line)
            Set early = (startedAt = "") || (at = "") || ((at - startedAt) <= 180)
            If early && ((line [ "failed over from node") || (line [ "Sharding")) {
                Set known = known + 1
            } Else {
                Set other = other _ $SELECT(other = "": "", 1: " | ") _ $EXTRACT(line, 1, 160)
            }
        }
        If (severe > 0) && (known = severe) {
            Do $SYSTEM.Monitor.Clear()
            Do $SYSTEM.Monitor.SetState(0)
            Return "cleared " _ known _ " known startup alert(s); state " _ before _ " -> " _ $SYSTEM.Monitor.State()
        }
        If severe = 0 Return "no severe lines; state " _ before
        Return "left as is: " _ (severe - known) _ " other severe line(s): " _ other
    } Catch ex {
        Return "error: " _ ex.DisplayString()
    }
}

}
