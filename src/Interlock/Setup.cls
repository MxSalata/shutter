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
        // The ward system's resource and role first: the production's client user gets the role at creation.
        If ##class(%Dictionary.CompiledClass).%ExistsId("Wards.Installer") {
            Set sc = $CLASSMETHOD("Wards.Installer", "Install")
            Quit:$$$ISERR(sc)
        }
        Set sc = ..CreateCredentials(demo) Quit:$$$ISERR(sc)
        Set sc = ..CreateWorkflowRole(demo) Quit:$$$ISERR(sc)
        Set sc = ##class(Interlock.Store.BoardMember).Seed() Quit:$$$ISERR(sc)
        Set sc = ##class(Interlock.Store.ModelPrice).Seed() Quit:$$$ISERR(sc)
        If (root '= "") && ##class(%File).Exists(root _ "knowledge/block-reasons.json") {
            Set sc = ##class(Interlock.Store.BlockReason).SeedFromFile(root _ "knowledge/block-reasons.json", .reasons)
            Quit:$$$ISERR(sc)
            Set ^Interlock.Config("blockReasons") = reasons
        }
        If root '= "" {
            Set sc = ##class(Interlock.Store.SiteProfile).SeedFromFile(root _ "knowledge/site/profile.json") Quit:$$$ISERR(sc)
            Set sc = ##class(Interlock.Catalogue.Entry).SeedFromFile(root _ "knowledge/catalogue/catalogue.json", .entries) Quit:$$$ISERR(sc)
            Set ^Interlock.Config("catalogue", "entries") = $GET(entries, 0)
        }
        If (root '= "") && ##class(%File).DirectoryExists(root _ "fixtures/records") {
            Set sc = ##class(Interlock.Bridge.Record).ImportDir(root _ "fixtures/records", .count)
            Quit:$$$ISERR(sc)
            Set ^Interlock.Config("recordsImported") = count
        }
        Set sc = ..CreateWebApps(ns, root) Quit:$$$ISERR(sc)
        // Replayed runs spend nothing; rows written before this rule held a recording's price.
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "UPDATE Interlock_Store.AgentRun SET CostUSD = 0 WHERE Mode = 'replay' AND CostUSD <> 0")
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
    // The production's client of the ward API needs the database as well as the ward's own resource
    // (the Wards_API role carries only that), or the web application answers 403.
    If '##class(Security.Roles).Exists("Interlock_WardClient") {
        Set sc = ##class(Security.Roles).Create("Interlock_WardClient", "Interlock: the production's client of the ward API, with the namespace's database", db _ ":RW", "")
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
    Set roles = $SELECT(##class(Security.Roles).Exists("Interlock_WardClient"): "Interlock_WardClient", 1: "Interlock_Operator")
    If ##class(Security.Roles).Exists("Wards_API") Set roles = "Wards_API," _ roles
    If '##class(Security.Users).Exists(user) {
        Set sc = ##class(Security.Users).Create(user, roles, password, "Interlock production client for the ward API", ns, "", "", 0, 1, "Used by the production's HTTP operation")
        Quit:$$$ISERR(sc) sc
    } Else {
        Do ##class(Security.Users).AddRoles(user, roles)
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
        Set ^|ns|Interlock.Config("webapp", "/wards/api") = 1
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
    Set ^|ns|Interlock.Config("webapp", "/api/interlock") = 1
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
        Set:$$$ISOK(sc) ^|ns|Interlock.Config("webapp", "/interlock") = 1
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
        // While an image is built (INTERLOCK_BUILD=1) the instance stops right after: the production
        // starts with the container instead, so nothing is started here.
        If $SYSTEM.Util.GetEnviron("INTERLOCK_BUILD") = "1" Quit
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

/// Empty Interlock's own tables (cases and everything attached to them, recordings excepted) on a
/// demo instance. Refused elsewhere. Returns the number of tables emptied or the error.
ClassMethod PurgeStore() As %String [ SqlProc ]
{
    If '$GET(^Interlock.Config("demo")) Quit "ERROR: not a demo instance"
    Set n = 0
    For cls = "Interlock.Store.Verification", "Interlock.Store.ExecutionAttempt", "Interlock.Store.Approval", "Interlock.Store.Rehearsal", "Interlock.Store.GateDecision", "Interlock.Store.Plan", "Interlock.Store.Finding", "Interlock.Store.AgentRun", "Interlock.Store.SnapshotItem", "Interlock.Store.Snapshot", "Interlock.Store.CaseEvent", "Interlock.Store.Case", "Interlock.Store.Idempotency", "Interlock.Bridge.ToolCall" {
        Set sc = $CLASSMETHOD(cls, "%KillExtent")
        If $$$ISERR(sc) Quit
        Set n = n + 1
    }
    If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
    Kill ^Interlock.Counter
    Quit n
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
        Job ##class(Interlock.Setup).NoOp()::5
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
    Set r.version = $GET(^Interlock.Config("version"))
    Set r."installed_at" = $GET(^Interlock.Config("installedAt"))
    Do r.%Set("demo", ''$GET(^Interlock.Config("demo")), "boolean")
    Set r.mode = $GET(^Interlock.Config("mode"))
    Set r."adt_in" = $GET(^Interlock.Config("adtIn"))
    Do r.%Set("interoperability", ''##class(%EnsembleMgr).IsEnsembleNamespace($NAMESPACE), "boolean")
    Do r.%Set("production_class", ''##class(%Dictionary.CompiledClass).%ExistsId("Interlock.Production"), "boolean")
    Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
    Set r.production = name, r."production_state" = $CASE(state, 1: "running", 2: "stopped", 3: "suspended", 4: "troubled", 5: "network stopped", : state)
    Do r.%Set("ward_classes", ''##class(%Dictionary.CompiledClass).%ExistsId("Wards.API"), "boolean")
    Do r.%Set("aihub_runner", ''##class(%Dictionary.CompiledClass).%ExistsId("Interlock.Bridge.Runner.AIHub"), "boolean")
    Do r.%Set("ai_hub_present", ''##class(%Dictionary.CompiledClass).%ExistsId("%AI.Agent"), "boolean")
    &sql(SELECT COUNT(*) INTO :members FROM Interlock_Store.BoardMember WHERE Enabled = 1)
    Set r."board_members" = +members
    &sql(SELECT COUNT(*) INTO :records FROM Interlock_Bridge.Record)
    Set r.recordings = +records
    &sql(SELECT COUNT(*) INTO :cases FROM Interlock_Store."Case")
    Set r.cases = +cases
    Set r.license = ##class(%DynamicObject).%FromJSON(..LicenseInfo())
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Do r.%Set("api_webapp", ''##class(Security.Applications).Exists("/api/interlock"), "boolean")
        Do r.%Set("ui_webapp", ''##class(Security.Applications).Exists("/interlock"), "boolean")
        Do r.%Set("wards_webapp", ''##class(Security.Applications).Exists("/wards/api"), "boolean")
        Set r."webapps_checked" = "live"
    } Catch ex {
        // A caller without %SYS access gets what the install recorded.
        Do r.%Set("api_webapp", ''$GET(^Interlock.Config("webapp", "/api/interlock")), "boolean")
        Do r.%Set("ui_webapp", ''$GET(^Interlock.Config("webapp", "/interlock")), "boolean")
        Do r.%Set("wards_webapp", ''$GET(^Interlock.Config("webapp", "/wards/api")), "boolean")
        Set r."webapps_checked" = "install record"
    }
    Quit r.%ToJSON()
}

// ---- the aihub module ----

/// Installs the aihub module's runtime pieces: the provider configuration from the environment
/// when ANTHROPIC_API_KEY is set (the model from INTERLOCK_MODEL), and the knowledge bases from
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
            Set out.provider = ..ConfigureProvider(key, $SYSTEM.Util.GetEnviron("INTERLOCK_MODEL"))
        } Else {
            Set out.provider = $SELECT(..ProviderConfigured(): "configured earlier", 1: "no key in the environment: the agents replay recordings")
        }
        Set kdir = ""
        If (root '= "") && ##class(%File).DirectoryExists(root _ "knowledge/") Set kdir = root _ "knowledge/"
        If (kdir = "") && ($GET(^Interlock.Config("root")) '= "") && ##class(%File).DirectoryExists(^Interlock.Config("root") _ "knowledge/") Set kdir = ^Interlock.Config("root") _ "knowledge/"
        If (kdir '= "") && ##class(%Dictionary.CompiledClass).%ExistsId("Interlock.Knowledge.Library") {
            Set out.knowledge = ##class(%DynamicObject).%FromJSON($CLASSMETHOD("Interlock.Knowledge.Library", "BuildAll", kdir))
        } Else {
            Set out.knowledge = $SELECT(kdir = "": "no knowledge folder found", 1: "no library class")
        }
        Set out.mode = ..RecordAgentMode($SYSTEM.Util.GetEnviron("INTERLOCK_AGENT_MODE"))
        Set ^Interlock.Config("aihub", "installedAt") = ##class(Interlock.Util.Time).NowUTC()
        Set ^Interlock.Config("aihub", "root") = root
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out.%ToJSON()
}

/// Puts the provider key in the IRIS wallet (collection Interlock, secret Anthropic) and writes the
/// Config Store configuration AI.LLM.Interlock that the agents name, with the model (default
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
            Do $CLASSMETHOD("%Wallet.Collection", "Create", "Interlock", {"UseResource": "Interlock_Secrets", "EditResource": "Interlock_Secrets"})
        } Catch {
        }
        Try {
            Do $CLASSMETHOD("%Wallet.KeyValue", "Delete", "Interlock.Anthropic")
        } Catch {
        }
        Set sc = $CLASSMETHOD("%Wallet.KeyValue", "Create", "Interlock.Anthropic", {"Usage": "CUSTOM", "Secret": {"key": (key)}})
        If $$$ISERR(sc) Return "wallet: " _ $SYSTEM.Status.GetErrorText(sc)
        Try {
            Do $CLASSMETHOD("%ConfigStore.Configuration", "Delete", "AI.LLM.Interlock")
        } Catch {
        }
        Set config = {"model_provider": "anthropic", "model": (model), "api_key": "secret://Interlock.Anthropic#key"}
        Set sc = $CLASSMETHOD("%ConfigStore.Configuration", "Create", "AI", "LLM", "", "Interlock", config)
        If $$$ISERR(sc) Return "config store: " _ $SYSTEM.Status.GetErrorText(sc)
        Set ^Interlock.Config("aihub", "provider") = "AI.LLM.Interlock"
        Set ^Interlock.Config("aihub", "model") = model
        Set ^Interlock.Config("aihub", "providerConfiguredAt") = ##class(Interlock.Util.Time).NowUTC()
        Return "ok: AI.LLM.Interlock, model " _ model
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
        If '##class(Security.Resources).Exists("Interlock_Secrets") {
            Set sc = ##class(Security.Resources).Create("Interlock_Secrets", "Interlock: the provider key in the wallet", "U")
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
        Set ^Interlock.Config("aihub", "mode") = mode
        Quit mode
    }
    Kill ^Interlock.Config("aihub", "mode")
    Quit "auto"
}

/// Whether ConfigureProvider has written AI.LLM.Interlock. Read from the module's own record, so that
/// callers without the right to read the Config Store (the API's users, the production's jobs) get the
/// same answer as those with it.
ClassMethod ProviderConfigured() As %Boolean
{
    Quit $GET(^Interlock.Config("aihub", "provider")) '= ""
}

/// Forgets the provider configuration: removes AI.LLM.Interlock and the wallet secret, and the record.
/// The agents replay recordings again. Returns a short status.
ClassMethod ClearProvider() As %String [ SqlProc ]
{
    Try {
        Do $CLASSMETHOD("%ConfigStore.Configuration", "Delete", "AI.LLM.Interlock")
    } Catch {
    }
    Try {
        Do $CLASSMETHOD("%Wallet.KeyValue", "Delete", "Interlock.Anthropic")
    } Catch {
    }
    Kill ^Interlock.Config("aihub", "provider"), ^Interlock.Config("aihub", "model"), ^Interlock.Config("aihub", "providerConfiguredAt")
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
ClassMethod ClearStartupAlerts(lines As %Integer = 400) As %String [ SqlProc ]
{
    Try {
        Set before = $SYSTEM.Monitor.State()
        Set log = ..TailLog(lines)
        // Only this start: the image's log also holds the lines of the IRIS run during the build.
        Set total = $LENGTH(log, $CHAR(10)), from = 1
        For i = 1:1:total {
            If $PIECE(log, $CHAR(10), i) [ "Startup of InterSystems IRIS" Set from = i
        }
        Set severe = 0, known = 0, other = ""
        For i = from:1:total {
            Set line = $PIECE(log, $CHAR(10), i)
            // "mm/dd/yy-hh:mm:ss:mmm (pid) <severity> [Source] text"
            Set sev = $PIECE($PIECE(line, ") ", 2), " ", 1)
            If (sev '= "2") && (sev '= "3") Continue
            Set severe = severe + 1
            If (line [ "failed over from node") || (line [ "Sharding") {
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
