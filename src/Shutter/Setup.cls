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
ClassMethod Install(root As %String = "", demo As %Boolean = 1) As %String [ SqlProc ]
{
    Set sc = ..InstallStatus(root, demo)
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

ClassMethod InstallStatus(root As %String = "", demo As %Boolean = 1) As %Status
{
    Set sc = $$$OK
    Try {
        Set ns = $NAMESPACE
        If root '= "" Set root = ##class(%File).NormalizeDirectory(root)
        Set ^Shutter.Config("root") = root
        Set ^Shutter.Config("demo") = demo
        Set ^Shutter.Config("installedAt") = ##class(Shutter.Util.Time).NowUTC()
        Set ^Shutter.Config("version") = ..#VERSION
        If $GET(^Shutter.Config("mode")) = "" Set ^Shutter.Config("mode") = "board"
        Set sc = ..CreateFolders() Quit:$$$ISERR(sc)
        Set sc = ..CreateSecurity(ns, demo) Quit:$$$ISERR(sc)
        Set sc = ..RemoveOldReceiverNames() Quit:$$$ISERR(sc)
        // The downstream system's resource and role first: the production's client user gets the role at creation.
        If ##class(%Dictionary.CompiledClass).%ExistsId("Downstream.Installer") {
            Set sc = $CLASSMETHOD("Downstream.Installer", "Install")
            Quit:$$$ISERR(sc)
        }
        Set sc = ..CreateCredentials(demo) Quit:$$$ISERR(sc)
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
        If (root '= "") && ##class(%File).DirectoryExists(root _ "fixtures/records") {
            Set sc = ##class(Shutter.Bridge.Record).ImportDir(root _ "fixtures/records", .count)
            Quit:$$$ISERR(sc)
            Set ^Shutter.Config("recordsImported") = count
        }
        Set sc = ..CreateWebApps(ns, root) Quit:$$$ISERR(sc)
        Set r = ..EnsureRetentionTasks(ns)
        If $EXTRACT(r, 1, 6) = "ERROR:" Set sc = $$$ERROR($$$GeneralError, "Retention tasks: " _ r) Quit
        // Replayed runs spend nothing; rows written before this rule held a recording's price.
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "UPDATE Shutter_Store.AgentRun SET CostUSD = 0 WHERE Mode = 'replay' AND CostUSD <> 0")
        Set sc = ..StartProduction() Quit:$$$ISERR(sc)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
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
    For res = "Shutter_Operate", "Shutter_Approve" {
        If '##class(Security.Resources).Exists(res) {
            Set sc = ##class(Security.Resources).Create(res, "Shutter: " _ $SELECT(res [ "Approve": "approve or reject recovery plans", 1: "view cases, run scenarios, start investigations"), "")
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
    If demo {
        Set password = $SYSTEM.Util.GetEnviron("SHUTTER_DEMO_PASSWORD")
        If password = "" Set password = "shutter"
        For user = "operator", "approver" {
            Set roles = $SELECT(user = "approver": "Shutter_Approver", 1: "Shutter_Operator")
            If ##class(Security.Users).Exists(user) {
                // An upgraded demo instance: the user is brought to the demo's definition (its role, the demo
                // password, enabled), as the documentation promises for operator and approver.
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

/// The production's credentials for the downstream API: a user with the Downstream_API role when the downstream
/// system's installer created it, otherwise the demo operator.
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

/// /api/shutter (REST, password), /downstream/api (the downstream system's REST API, when its classes
/// are installed) and /shutter (the web app's files, when root/www exists).
ClassMethod CreateWebApps(ns As %String, root As %String) As %Status
{
    Set sc = $$$OK
    Set hasDownstream = ##class(%Dictionary.CompiledClass).%ExistsId("Downstream.API")
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

/// System default settings for the production: the folders and the downstream API's address, so the
/// production definition carries no paths of its own.
ClassMethod ApplyDefaultSettings() As %Status
{
    Set sc = $$$OK
    Set values("ADT In", "FilePath") = $GET(^Shutter.Config("dir", "in"))
    Set values("ADT In", "ArchivePath") = $GET(^Shutter.Config("dir", "archive"))
    Set values("ADT In", "WorkPath") = $GET(^Shutter.Config("dir", "work"))
    Set values("*", "HTTPServer") = $GET(^Shutter.Config("downstreamHost"), $GET(^Shutter.Config("wardHost"), "127.0.0.1"))
    Set values("*", "HTTPPort") = $GET(^Shutter.Config("downstreamPort"), $GET(^Shutter.Config("wardPort"), 52773))
    Set item = ""
    For {
        Set item = $ORDER(values(item))
        Quit:(item="")
        Set name = ""
        For {
            Set name = $ORDER(values(item, name), 1, value)
            Quit:(name="")
            Continue:(value="")
            Set id = "Shutter.Production||" _ item _ "||*||" _ name
            Set d = ##class(Ens.Config.DefaultSettings).%OpenId(id)
            If '$ISOBJECT(d) {
                Set d = ##class(Ens.Config.DefaultSettings).%New()
                Set d.ProductionName = "Shutter.Production", d.ItemName = item, d.HostClassName = "*", d.SettingName = name
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

/// Make Shutter.Production the namespace's production and start it, when the class is compiled.
ClassMethod StartProduction() As %Status
{
    Set sc = $$$OK
    Set prod = "Shutter.Production"
    If '##class(%Dictionary.CompiledClass).%ExistsId(prod) Quit sc
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

/// Empty Shutter's own tables (cases and everything attached to them, recordings excepted) on a
/// demo instance. Refused elsewhere. Returns the number of tables emptied or the error.
/// The two daily housekeeping tasks (A14), created once: "Shutter message purge" (the standard Ens.Util.Tasks.Purge,
/// 30 days, bodies too, keeping sessions whole) and "Shutter retention" (Shutter.Util.RetentionTask). Returns "ok",
/// "exists" or the error.
ClassMethod EnsureRetentionTasks(ns As %String = "") As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("%Admin_Task", "USE") && '$SYSTEM.Security.Check("Shutter_Operate", "USE") Quit "Shutter_Operate is required"
    If ns = "" Set ns = $NAMESPACE
    Set out = ""
    Set sc = ..EnsureTask("Shutter message purge", ns, "Ens.Util.Tasks.Purge", "Shutter: purge messages, logs and traces older than 30 days, sessions kept whole", $LISTBUILD("NumberOfDaysToKeep", 30, "BodiesToo", 1, "KeepIntegrity", 1, "TypesToPurge", "all"), 9600, .made)
    If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
    Set out = out _ "message purge " _ $SELECT(made: "created", 1: "exists")
    Set sc = ..EnsureTask("Shutter retention", ns, "Shutter.Util.RetentionTask", "Shutter: idempotency keys older than a day, and closed cases past the retention when switched on", $LISTBUILD("RetentionDays", 30, "PurgeClosedCases", 0), 9900, .made)
    If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
    Quit out _ "; retention " _ $SELECT(made: "created", 1: "exists")
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
    Set sc = ..StartProduction()
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
    Do r.%Set("production_class", ''##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Production"), "boolean")
    Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
    Set r.production = name, r."production_state" = $CASE(state, 1: "running", 2: "stopped", 3: "suspended", 4: "troubled", 5: "network stopped", : state)
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
        Set r."webapps_checked" = "live"
    } Catch ex {
        // A caller without %SYS access gets what the install recorded.
        Do r.%Set("api_webapp", ''$GET(^Shutter.Config("webapp", "/api/shutter")), "boolean")
        Do r.%Set("ui_webapp", ''$GET(^Shutter.Config("webapp", "/shutter")), "boolean")
        Do r.%Set("wards_webapp", ''$GET(^Shutter.Config("webapp", "/downstream/api")), "boolean")
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

/// The resource guarding the wallet collection, with public Use so the production's jobs can
/// resolve the secret through the Config Store. Tighten for a shared instance.
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
    Set files("records") = root _ "fixtures/records"
    Set name = ""
    For {
        Set name = $ORDER(files(name)) Quit:name=""
        Set path = files(name), isDir = (name = "records")
        If isDir { Continue:'##class(%File).DirectoryExists(path) } Else { Continue:'##class(%File).Exists(path) }
        Set stamp = $SELECT(isDir: ..DirectoryStamp(path), 1: ##class(%File).GetFileDateModified(path, 1) _ ":" _ ##class(%File).GetFileSize(path))
        Continue:($GET(^Shutter.Config("stamp", name)) = stamp)
        Set sc = ..ReseedOne(name, path, .n)
        If $$$ISOK(sc) {
            Set ^Shutter.Config("stamp", name) = stamp
            Do out.%Set(name, $SELECT($GET(n) = "": "reread", 1: n))
        } Else {
            Do out.%Set(name, "error: " _ $SYSTEM.Status.GetErrorText(sc))
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
