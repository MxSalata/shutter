/// Installs and checks Interlock. Install() runs from the IPM module after the classes are loaded
/// and is idempotent; CreateNamespace() can be run first from any namespace to create a fresh one
/// with Interoperability enabled.
Class Interlock.Setup Extends %RegisteredObject
{

Parameter VERSION = "0.1.0";

/// Create a namespace with its own database and Interoperability enabled. Returns "ok" or the error.
ClassMethod CreateNamespace(ns As %String = "INTERLOCK") As %String [ SqlProc ]
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
/// library, prices, recordings, the ward installer when present, the web applications and the
/// production. root is the module's directory (IPM passes ${root}); demo marks the instance as a
/// demo (reset allowed, demo users created).
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
        Set ^Interlock.Config("root") = root
        Set ^Interlock.Config("demo") = demo
        Set ^Interlock.Config("installedAt") = ##class(Interlock.Util.Time).NowUTC()
        Set ^Interlock.Config("version") = ..#VERSION
        If $GET(^Interlock.Config("mode")) = "" Set ^Interlock.Config("mode") = "board"
        Set sc = ..CreateFolders() Quit:$$$ISERR(sc)
        Set sc = ..CreateSecurity(ns, demo) Quit:$$$ISERR(sc)
        Set sc = ..CreateCredentials(demo) Quit:$$$ISERR(sc)
        Set sc = ..CreateWorkflowRole(demo) Quit:$$$ISERR(sc)
        Set sc = ##class(Interlock.Store.BoardMember).Seed() Quit:$$$ISERR(sc)
        Set sc = ##class(Interlock.Store.ModelPrice).Seed() Quit:$$$ISERR(sc)
        If ##class(%Dictionary.CompiledClass).%ExistsId("Wards.Installer") {
            Set sc = $CLASSMETHOD("Wards.Installer", "Install")
            Quit:$$$ISERR(sc)
        }
        If (root '= "") && ##class(%File).Exists(root _ "knowledge/block-reasons.json") {
            Set sc = ##class(Interlock.Store.BlockReason).SeedFromFile(root _ "knowledge/block-reasons.json", .reasons)
            Quit:$$$ISERR(sc)
            Set ^Interlock.Config("blockReasons") = reasons
        }
        If (root '= "") && ##class(%File).DirectoryExists(root _ "fixtures/records") {
            Set sc = ##class(Interlock.Bridge.Record).ImportDir(root _ "fixtures/records", .count)
            Quit:$$$ISERR(sc)
            Set ^Interlock.Config("recordsImported") = count
        }
        Set sc = ..CreateWebApps(ns, root) Quit:$$$ISERR(sc)
        Set sc = ..StartProduction() Quit:$$$ISERR(sc)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The inbound, archive and work folders under the manager directory.
ClassMethod CreateFolders() As %Status
{
    Set base = ##class(%File).NormalizeDirectory(##class(%File).ManagerDirectory() _ "interlock")
    For sub = "in", "archive", "work", "out" {
        Set dir = base _ sub _ "/"
        If '##class(%File).DirectoryExists(dir) {
            If '##class(%File).CreateDirectoryChain(dir) Quit $$$ERROR($$$GeneralError, "Cannot create " _ dir)
        }
        Set ^Interlock.Config("dir", sub) = dir
    }
    Set ^Interlock.Config("adtIn") = base _ "in/"
    Set ^Interlock.Config("adtArchive") = base _ "archive/"
    Set root = $GET(^Interlock.Config("root"))
    If root '= "" Set ^Interlock.Config("fixtures") = root _ "fixtures/"
    Quit $$$OK
}

/// Resources, roles and the demo users. Runs in %SYS.
ClassMethod CreateSecurity(ns As %String, demo As %Boolean) As %Status
{
    Set sc = $$$OK
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    For res = "Interlock_Operate", "Interlock_Approve" {
        If '##class(Security.Resources).Exists(res) {
            Set sc = ##class(Security.Resources).Create(res, "Interlock: " _ $SELECT(res [ "Approve": "approve or reject recovery plans", 1: "view cases, run scenarios, start investigations"), "")
            Quit:$$$ISERR(sc)
        }
    }
    Quit:$$$ISERR(sc) sc
    Set db = ..DatabaseResource(ns)
    If '##class(Security.Roles).Exists("Interlock_Operator") {
        Set sc = ##class(Security.Roles).Create("Interlock_Operator", "Interlock operator: cases, scenarios, investigations", "Interlock_Operate:U," _ db _ ":RW,%Ens_Portal:U", "")
        Quit:$$$ISERR(sc) sc
    }
    If '##class(Security.Roles).Exists("Interlock_Approver") {
        Set sc = ##class(Security.Roles).Create("Interlock_Approver", "Interlock approver: everything an operator can, plus approvals", "Interlock_Operate:U,Interlock_Approve:U," _ db _ ":RW", "Interlock_Operator,%EnsRole_Operator")
        Quit:$$$ISERR(sc) sc
    }
    // Every caller of the API web application gets read access to the namespace's database, so
    // that the sign-in route can run for an anonymous session; data routes still check resources.
    If '##class(Security.Roles).Exists("Interlock_WebApp") {
        Set sc = ##class(Security.Roles).Create("Interlock_WebApp", "Interlock web application: read the code database (granted to every caller by the web application)", db _ ":R", "")
        Quit:$$$ISERR(sc) sc
    }
    If demo {
        Set password = $SYSTEM.Util.GetEnviron("INTERLOCK_DEMO_PASSWORD")
        If password = "" Set password = "interlock"
        For user = "operator", "approver" {
            Continue:##class(Security.Users).Exists(user)
            Set roles = $SELECT(user = "approver": "Interlock_Approver", 1: "Interlock_Operator")
            Set sc = ##class(Security.Users).Create(user, roles, password, "Interlock demo " _ user, ns, "", "", 0, 1, "Interlock demo user")
            Quit:$$$ISERR(sc)
        }
    }
    Quit sc
}

/// The security resource of a namespace's default database, for example %DB_INTERLOCK or
/// %DB_%DEFAULT. Runs in %SYS.
ClassMethod DatabaseResource(ns As %String) As %String
{
    Set resource = "%DB_%DEFAULT"
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set sc = ##class(Config.Namespaces).Get(ns, .nsprops)
        Quit:$$$ISERR(sc)
        Set dbname = $GET(nsprops("Globals"))
        Quit:(dbname="")
        Set sc = ##class(Config.Databases).Get(dbname, .dbprops)
        Quit:$$$ISERR(sc)
        Set db = ##class(SYS.Database).%OpenId($GET(dbprops("Directory")))
        If $ISOBJECT(db) && (db.ResourceName '= "") Set resource = db.ResourceName
    } Catch ex {
    }
    Quit resource
}

/// The production's credentials for the ward API: a user with the Wards_API role when the ward
/// installer created it, otherwise the demo operator.
ClassMethod CreateCredentials(demo As %Boolean) As %Status
{
    Set sc = $$$OK
    Set password = $SYSTEM.Util.GetEnviron("INTERLOCK_DEMO_PASSWORD")
    If password = "" Set password = "interlock"
    Set user = "wards-client"
    New $NAMESPACE
    Set ns = $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If '##class(Security.Users).Exists(user) {
        Set roles = $SELECT(##class(Security.Roles).Exists("Wards_API"): "Wards_API", 1: "Interlock_Operator")
        Set sc = ##class(Security.Users).Create(user, roles, password, "Interlock production client for the ward API", ns, "", "", 0, 1, "Used by the production's HTTP operation")
        Quit:$$$ISERR(sc) sc
    } ElseIf ##class(Security.Roles).Exists("Wards_API") {
        Do ##class(Security.Users).AddRoles(user, "Wards_API")
    }
    Set $NAMESPACE = ns
    If '##class(Ens.Config.Credentials).%ExistsId("WardsAPI") {
        Set sc = ##class(Ens.Config.Credentials).SetCredential("WardsAPI", user, password, 1)
    }
    Quit sc
}

/// The Workflow role that receives approval tasks, and the demo approver as its member.
ClassMethod CreateWorkflowRole(demo As %Boolean) As %Status
{
    Set sc = $$$OK
    Try {
        Set role = "Interlock Approvers"
        If '##class(EnsLib.Workflow.RoleDefinition).%ExistsId(role) {
            Set sc = ##class(EnsLib.Workflow.RoleDefinition).CreateRole(role)
            Quit:$$$ISERR(sc)
            Set r = ##class(EnsLib.Workflow.RoleDefinition).%OpenId(role)
            If $ISOBJECT(r) Set r.Description = "Approve or reject Interlock recovery plans" Do r.%Save()
        }
        If demo {
            If '##class(EnsLib.Workflow.UserDefinition).%ExistsId("approver") {
                Set sc = ##class(EnsLib.Workflow.UserDefinition).CreateUser("approver", "Interlock demo approver")
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

/// /api/interlock (REST, password), /wards/api (the ward system's REST API, when its classes are
/// installed) and /interlock (the web app's files, when root/www exists).
ClassMethod CreateWebApps(ns As %String, root As %String) As %Status
{
    Set sc = $$$OK
    Set hasWards = ##class(%Dictionary.CompiledClass).%ExistsId("Wards.API")
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If hasWards {
        Kill props
        Set props("NameSpace") = ns
        Set props("Description") = "Interlock: the synthetic ward system's API"
        Set props("Enabled") = 1
        Set props("AutheEnabled") = 32
        Set props("DispatchClass") = "Wards.API"
        If ##class(Security.Resources).Exists("Wards_API") Set props("Resource") = "Wards_API"
        Set props("UseCookies") = 2
        Set props("CookiePath") = "/wards/api/"
        If ##class(Security.Applications).Exists("/wards/api") {
            Set sc = ##class(Security.Applications).Modify("/wards/api", .props)
        } Else {
            Set sc = ##class(Security.Applications).Create("/wards/api", .props)
        }
        Quit:$$$ISERR(sc) sc
    }
    Kill props
    Set props("NameSpace") = ns
    Set props("Description") = "Interlock REST API"
    Set props("Enabled") = 1
    // Password (32) or unauthenticated (64): POST /session signs in; every other route checks
    // the caller's resources itself, so an anonymous request gets a JSON 401, not a browser dialog.
    Set props("AutheEnabled") = 96
    Set props("DispatchClass") = "Interlock.API.Dispatch"
    Set props("UseCookies") = 2
    Set props("CookiePath") = "/api/interlock/"
    Set props("MatchRoles") = ":Interlock_WebApp"
    If ##class(Security.Applications).Exists("/api/interlock") {
        Set sc = ##class(Security.Applications).Modify("/api/interlock", .props)
    } Else {
        Set sc = ##class(Security.Applications).Create("/api/interlock", .props)
    }
    Quit:$$$ISERR(sc) sc
    Set www = $SELECT(root = "": "", 1: root _ "www/")
    If (www '= "") && ##class(%File).DirectoryExists(www) {
        Kill props
        Set props("NameSpace") = ns
        Set props("Description") = "Interlock web application"
        Set props("Enabled") = 1
        Set props("AutheEnabled") = 64
        Set props("Path") = www
        Set props("ServeFiles") = 1
        Set props("Recurse") = 1
        Set props("UseCookies") = 2
        Set props("CookiePath") = "/interlock/"
        Set props("MatchRoles") = ":Interlock_WebApp"
        If ##class(Security.Applications).Exists("/interlock") {
            Set sc = ##class(Security.Applications).Modify("/interlock", .props)
        } Else {
            Set sc = ##class(Security.Applications).Create("/interlock", .props)
        }
    }
    Quit sc
}

/// System default settings for the production: the folders and the ward API's address, so the
/// production definition carries no paths of its own.
ClassMethod ApplyDefaultSettings() As %Status
{
    Set sc = $$$OK
    Set values("ADT In", "FilePath") = $GET(^Interlock.Config("dir", "in"))
    Set values("ADT In", "ArchivePath") = $GET(^Interlock.Config("dir", "archive"))
    Set values("ADT In", "WorkPath") = $GET(^Interlock.Config("dir", "work"))
    Set values("*", "HTTPServer") = $GET(^Interlock.Config("wardHost"), "127.0.0.1")
    Set values("*", "HTTPPort") = $GET(^Interlock.Config("wardPort"), 52773)
    Set item = ""
    For {
        Set item = $ORDER(values(item))
        Quit:(item="")
        Set name = ""
        For {
            Set name = $ORDER(values(item, name), 1, value)
            Quit:(name="")
            Continue:(value="")
            Set id = "Interlock.Production||" _ item _ "||*||" _ name
            Set d = ##class(Ens.Config.DefaultSettings).%OpenId(id)
            If '$ISOBJECT(d) {
                Set d = ##class(Ens.Config.DefaultSettings).%New()
                Set d.ProductionName = "Interlock.Production", d.ItemName = item, d.HostClassName = "*", d.SettingName = name
            }
            Set d.SettingValue = value
            Set d.Description = "Set by Interlock.Setup"
            Set sc = d.%Save()
            Quit:$$$ISERR(sc)
        }
        Quit:$$$ISERR(sc)
    }
    Quit sc
}

/// Make Interlock.Production the namespace's production and start it, when the class is compiled.
ClassMethod StartProduction() As %Status
{
    Set sc = $$$OK
    Set prod = "Interlock.Production"
    If '##class(%Dictionary.CompiledClass).%ExistsId(prod) Quit sc
    Set sc = ..ApplyDefaultSettings()
    Quit:$$$ISERR(sc) sc
    Try {
        Do ##class(Ens.Director).SetAutoStart(prod)
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

/// Restart the production so that recompiled business hosts pick up their new code. Returns "ok"
/// or the error.
ClassMethod RestartProduction() As %String [ SqlProc ]
{
    Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
    If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
    If state = 1 {
        Set sc = ##class(Ens.Director).StopProduction(60, 0)
        If $$$ISERR(sc) Quit $SYSTEM.Status.GetErrorText(sc)
    }
    Set sc = ..StartProduction()
    Quit $SELECT($$$ISOK(sc): "ok", 1: $SYSTEM.Status.GetErrorText(sc))
}

/// A readiness report as JSON: what is installed, what runs, what is missing.
ClassMethod Doctor() As %String [ SqlProc ]
{
    Set r = {}
    Set r.namespace = $NAMESPACE
    Set r.version = $GET(^Interlock.Config("version"))
    Set r."installed_at" = $GET(^Interlock.Config("installedAt"))
    Set r.demo = ''$GET(^Interlock.Config("demo"))
    Set r.mode = $GET(^Interlock.Config("mode"))
    Set r."adt_in" = $GET(^Interlock.Config("adtIn"))
    Set r.interoperability = ''##class(%EnsembleMgr).IsEnsembleNamespace($NAMESPACE)
    Set r."production_class" = ''##class(%Dictionary.CompiledClass).%ExistsId("Interlock.Production")
    Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
    Set r.production = name, r."production_state" = $CASE(state, 1: "running", 2: "stopped", 3: "suspended", 4: "troubled", 5: "network stopped", : state)
    Set r."ward_classes" = ''##class(%Dictionary.CompiledClass).%ExistsId("Wards.API")
    Set r."aihub_runner" = ''##class(%Dictionary.CompiledClass).%ExistsId("Interlock.Bridge.Runner.AIHub")
    Set r."ai_hub_present" = ''##class(%Dictionary.CompiledClass).%ExistsId("%AI.Agent")
    &sql(SELECT COUNT(*) INTO :members FROM Interlock_Store.BoardMember WHERE Enabled = 1)
    Set r."board_members" = +members
    &sql(SELECT COUNT(*) INTO :records FROM Interlock_Bridge.Record)
    Set r.recordings = +records
    &sql(SELECT COUNT(*) INTO :cases FROM Interlock_Store."Case")
    Set r.cases = +cases
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set r."api_webapp" = ''##class(Security.Applications).Exists("/api/interlock")
        Set r."ui_webapp" = ''##class(Security.Applications).Exists("/interlock")
        Set r."wards_webapp" = ''##class(Security.Applications).Exists("/wards/api")
    } Catch ex {
        // A caller without %SYS access gets the rest of the report.
        Do r.%Set("api_webapp", "", "null"), r.%Set("ui_webapp", "", "null"), r.%Set("wards_webapp", "", "null")
    }
    Quit r.%ToJSON()
}

}
