/// Installs and checks Shutter. Install() runs from the IPM module after the classes are loaded
/// and is idempotent; CreateNamespace() can be run first from any namespace to create a fresh one
/// with Interoperability enabled.
Class Shutter.Setup Extends %RegisteredObject
{

Parameter VERSION = "1.1.2";

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
/// the load) and what Install wraps. The housekeeping tasks read SHUTTER_MESSAGE_DAYS, SHUTTER_MESSAGE_PURGE and SHUTTER_ESCALATION_DAYS from
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
    // A namespace running a production of the site's: Shutter's own production would stop it (v1.42).
    Set problem = ..LiveNamespaceProblem()
    If problem '= "" Quit $$$ERROR($$$GeneralError, problem)
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
        // The day's model budget (Shutter.Util.Budget, v1.34): the cap from SHUTTER_DAILY_BUDGET_USD, 0 when unset, and each
        // user's share of it from SHUTTER_JUDGE_BUDGET_USD.
        Do ##class(Shutter.Util.Budget).Configure($SYSTEM.Util.GetEnviron("SHUTTER_DAILY_BUDGET_USD"))
        Do ##class(Shutter.Util.Budget).ConfigureShare($SYSTEM.Util.GetEnviron("SHUTTER_JUDGE_BUDGET_USD"))
        Do ##class(Shutter.Util.Budget).ConfigureDemoBudget($SYSTEM.Util.GetEnviron("SHUTTER_DEMO_BUDGET_USD"), $SYSTEM.Util.GetEnviron("SHUTTER_DEMO_BUDGET_PERIOD"))
        Set ^Shutter.Config("installedAt") = ##class(Shutter.Util.Time).NowUTC()
        Set ^Shutter.Config("version") = ..#VERSION
        If $GET(^Shutter.Config("mode")) = "" Set ^Shutter.Config("mode") = "board"
        Set sc = ..CreateFolders() Quit:$$$ISERR(sc)
        // The demo's records and hospital namespaces, before CreateSecurity reads them: an image's installer has made
        // them, a load on a stock instance has not. Making a namespace is not something IPM's transaction could undo.
        If demo && ('##class(Shutter.Installer).NamespaceExists("RECORDS") || '##class(Shutter.Installer).NamespaceExists("HOSPITAL")) {
            Do ..LeaveTransaction()
            Set sc = ##class(Shutter.Installer).EnsureDemoNamespaces(ns) Quit:$$$ISERR(sc)
        }
        Set sc = ..CreateSecurity(ns, demo) Quit:$$$ISERR(sc)
        Set sc = ..GrantSqlPrivileges(ns) Quit:$$$ISERR(sc)
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
            // The live hospital (CONTRACTS 4.4, v1.34; decided on 1 Nov 2026): its single cases at tier 2 wait for a person.
            Set sc = ..DemoProfilePolicy(root _ "knowledge/site/profile.json", demo) Quit:$$$ISERR(sc)
            Set sc = ..LiveProfilePolicy(root _ "knowledge/site/profile.json") Quit:$$$ISERR(sc)
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
        Set synced = ..SyncSecondParser("Shutter.Production")
        If $EXTRACT(synced, 1, 5) = "ERROR" Set sc = $$$ERROR($$$GeneralError, synced) Quit
        // A site runs the production with no feed of its own: the demo's items are switched off.
        If 'demo Set sc = ..DisableDemoItems() Quit:$$$ISERR(sc)
        // The compile above rewrote the definition from the package: the receivers' connector items go back (v1.42).
        If 'demo Set sc = ##class(Shutter.Util.Onboard).RestoreReceiverItems() Quit:$$$ISERR(sc)
        If demo Set sc = ..InstallDemoHospital(ns) Quit:$$$ISERR(sc)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    While $TLEVEL < tlevel { TSTART }
    Quit sc
}

/// Why this namespace must not take Shutter's own production: another production runs here, and starting Shutter's would
/// stop it. "" when nothing stands in the way. Upgrades pass: there the running production is Shutter's.
ClassMethod LiveNamespaceProblem(running As %String = "", state As %String = "") As %String
{
    If (running = "") && (state = "") {
        Try { Do ##class(Ens.Director).GetProductionStatus(.running, .state) } Catch ex { Set running = "", state = "" }
    }
    If (running = "") || (running = "Shutter.Production") || (+state '= 1) Quit ""
    Quit "This namespace runs the production " _ running _ ", and installing Shutter here would stop it. Create a namespace for Shutter (SELECT Shutter.Setup_CreateNamespace('SHUTTER')) and load there, or name this production to put Shutter's items inside it (-Dproduction=" _ running _ ")"
}

/// The demo hospital's production, in its namespace, once Shutter's classes are compiled and mapped there. An image
/// build leaves it to iris.script (SHUTTER_BUILD=1), which runs it after the load; a load on a stock instance has no such
/// script. Running it again is safe (Hospital.Setup).
ClassMethod InstallDemoHospital(ns As %String) As %Status [ Private ]
{
    If $SYSTEM.Util.GetEnviron("SHUTTER_BUILD") = "1" Quit $$$OK
    If $ZCONVERT(ns, "U") = "HOSPITAL" Quit $$$OK
    If '##class(%Dictionary.CompiledClass).%ExistsId("Hospital.Setup") Quit $$$OK
    If '##class(Shutter.Installer).NamespaceExists("HOSPITAL") Quit $$$OK
    Do ..LeaveTransaction()
    New $NAMESPACE
    Set $NAMESPACE = "HOSPITAL"
    Set r = ##class(Hospital.Setup).Install(ns)
    Quit $SELECT(r = "ok": $$$OK, 1: $$$ERROR($$$GeneralError, "The demo hospital: " _ r))
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
    // The watched hospital's namespace (Hospital.Setup records it): the operator and the approver read its databases, so
    // GET /production-reviews/targets can list its productions and their state for them, and write its data database,
    // since their Reset clears the live feed's bed map there. The demo's roles read it only: they never reset.
    Set hospital = $GET(^|ns|Shutter.Config("hospitalNamespace"))
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    For res = "Shutter_Operate", "Shutter_Approve", "Shutter_Intake", "Shutter_Configure", "Shutter_Scenarios", "Shutter_LiveAgents", "Shutter_Publish" {
        If '##class(Security.Resources).Exists(res) {
            Set sc = ##class(Security.Resources).Create(res, "Shutter: " _ $CASE(res, "Shutter_Approve": "approve or reject recovery plans", "Shutter_Intake": "open a case from another production", "Shutter_Publish": "read cases, incidents, evidence and plans through the MCP publisher", "Shutter_LiveAgents": "spend the model budget: live questions and convening the board", "Shutter_Configure": "change the site: the site profile, the agent library, the schemas, the review annotations", "Shutter_Scenarios": "run and reset the demo's scenarios and purge the store", : "view cases, run scenarios, start investigations"), "")
            Quit:$$$ISERR(sc)
        }
    }
    Quit:$$$ISERR(sc) sc
    // The namespace's data database read-write, and its code database read when it is another one (the image keeps the
    // code in the image and the data in the volume).
    Set db = ..DatabaseResource(ns), code = ..DatabaseResource(ns, 1)
    Set codeRead = $SELECT((code '= "") && (code '= db): "," _ code _ ":R", 1: "")
    // The demo records system's databases (v1.25): the production's client of the receivers' APIs writes to it through
    // /records/api, so its role takes that namespace's data read-write and its code read, as it has Shutter's. The operator
    // and the approver take them too (v1.42): their Reset resets that receiver in its own namespace.
    Set recordsRW = ""
    If ##class(Config.Namespaces).Exists("RECORDS") {
        Set rdb = ..DatabaseResource("RECORDS"), rcode = ..DatabaseResource("RECORDS", 1)
        If (rdb '= "") && (rdb '= db) Set recordsRW = recordsRW _ "," _ rdb _ ":RW"
        If (rcode '= "") && (rcode '= rdb) && (rcode '= db) && (rcode '= code) Set recordsRW = recordsRW _ "," _ rcode _ ":R"
    }
    Set watchRead = "", watchReset = ""
    If (hospital '= "") && ($ZCONVERT(hospital, "U") '= $ZCONVERT(ns, "U")) && ##class(Config.Namespaces).Exists(hospital) {
        Set hospitalData = ..DatabaseResource(hospital)
        For res = hospitalData, ..DatabaseResource(hospital, 1) {
            If (res '= "") && (res '= db) && (res '= code) && (("," _ watchRead _ ",") '[ ("," _ res _ ":R,")) {
                Set watchRead = watchRead _ "," _ res _ ":R"
                Set watchReset = watchReset _ "," _ res _ $SELECT(res = hospitalData: ":RW", 1: ":R")
            }
        }
    }
    // Each role is created, or brought to this definition when it exists, so an upgraded instance is tightened too.
    // The approver monitors (traces, messages, the Workflow inbox) and approves; it never starts, stops or purges:
    // %EnsRole_Monitor with the message trace, header and content viewing resources, not %EnsRole_Operator (E2).
    Set sc = ..EnsureRole("Shutter_Operator", "Shutter operator: cases, scenarios, investigations", "Shutter_Operate:U,Shutter_Scenarios:U,Shutter_LiveAgents:U,Shutter_Publish:U," _ db _ ":RW" _ codeRead _ watchReset _ recordsRW _ ",%Ens_Portal:U", "")
    Quit:$$$ISERR(sc) sc
    // What an approver and the public demo's role share (v1.34): reading, approving, the traces; the approver adds the site's
    // writes (Shutter_Configure) and the demo controls (Shutter_Scenarios), which the demo role never holds.
    Set approverCore = "Shutter_Operate:U,Shutter_Approve:U," _ db _ ":RW" _ codeRead
    Set traces = ",%Ens_MessageTrace:U,%Ens_MessageHeader:U,%Ens_MessageContent:U"
    Set approverRes = approverCore _ watchRead _ traces
    Set sc = ..EnsureRole("Shutter_Approver", "Shutter approver: everything an operator can, plus approvals, the site's settings and the Workflow inbox", approverCore _ watchReset _ recordsRW _ traces _ ",%Ens_EventLog:U,Shutter_Configure:U,Shutter_Scenarios:U,Shutter_LiveAgents:U", "Shutter_Operator,%EnsRole_Monitor")
    Quit:$$$ISERR(sc) sc
    Set sc = ..EnsureRole("Shutter_Demo", "Shutter public demo: reads everything, reinvestigates, approves and asks; cannot run or reset scenarios, save the site profile or the library, or import a schema", approverRes _ ",%Ens_Portal:U", "%EnsRole_Monitor")
    Quit:$$$ISERR(sc) sc
    // A judge (v1.34, decided on 1 Nov 2026): the public demo's role plus the live agents, under the model budget and
    // a share of their own; the demo role never spends.
    Set sc = ..EnsureRole("Shutter_Judge", "Shutter judge: the public demo's role plus the live agents (live questions, convening the board), under the model budget", approverRes _ ",%Ens_Portal:U,Shutter_LiveAgents:U", "%EnsRole_Monitor")
    Quit:$$$ISERR(sc) sc
    // The Management Portal user of the public demo sees the Visual Trace and the messages, nothing of Shutter's and nothing it
    // could change.
    Set sc = ..EnsureRole("Shutter_Trace", "Shutter public demo: the Visual Trace and the messages in the Management Portal, read only", "%Ens_MessageTrace:U,%Ens_MessageHeader:U,%Ens_MessageContent:U,%Ens_EventLog:U,%Ens_Portal:U,%Ens_Dashboard:U,%Ens_ProductionConfig:R,%Service_WebGateway:U," _ db _ ":R" _ codeRead, "")
    Quit:$$$ISERR(sc) sc
    // The production's client of the downstream API needs the database as well as the downstream system's own
    // resource (the Downstream_API role carries only that), or the web application answers 403.
    Set sc = ..EnsureRole("Shutter_DownstreamClient", "Shutter: the production's client of the downstream API, with the namespace's databases", db _ ":RW" _ codeRead _ recordsRW, "")
    Quit:$$$ISERR(sc) sc
    // Every caller of the API web application gets read access to the namespace's databases, so
    // that the sign-in route can run for an anonymous session; data routes still check resources.
    // Embedded Python asks for this resource on the AI Hub builds (2026.2 has none): without it a web caller reads only
    // UTC, Europe/London and fixed offsets (Time.PythonZones), though the production, with all rights, reads every zone.
    Set python = $SELECT(##class(Security.Resources).Exists("%Service_EmbeddedPython"): ",%Service_EmbeddedPython:U", 1: "")
    Set sc = ..EnsureRole("Shutter_WebApp", "Shutter web application: read the namespace's databases (granted to every caller by the web application)", db _ ":R" _ codeRead _ python, "")
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
    Quit:$$$ISERR(sc) sc
    // The public demo's logins (the live hospital, v1.34): made, or brought back to their definition, only when the install is
    // told their passwords; never a documented one. The production's start applies the container's environment the same way
    // (ApplyEnvironment), so `docker compose up` with the variables in .env makes them without a build argument.
    Quit ..EnsurePublicUsers(ns, $SYSTEM.Util.GetEnviron("SHUTTER_PUBLIC_DEMO_PASSWORD"), $SYSTEM.Util.GetEnviron("SHUTTER_TRACE_PASSWORD"), $SYSTEM.Util.GetEnviron("SHUTTER_JUDGE_PASSWORD"))
}

/// The public demo's three logins, each made (or brought back to its definition) when its password is given, left alone
/// when it is empty. Runs in %SYS.
ClassMethod EnsurePublicUsers(ns As %String, publicPw As %String, tracePw As %String, judgePw As %String) As %Status [ Private ]
{
    Set sc = $$$OK
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If publicPw '= "" Set sc = ..EnsureUser("demo", "Shutter_Demo", publicPw, "Shutter public demo", ns)
    Quit:$$$ISERR(sc) sc
    If tracePw '= "" Set sc = ..EnsureUser("demo-trace", "Shutter_Trace", tracePw, "Shutter public demo: the Visual Trace", ns)
    Quit:$$$ISERR(sc) sc
    If judgePw '= "" Set sc = ..EnsureUser("judge", "Shutter_Judge", judgePw, "Shutter judge: the live agents", ns)
    Quit sc
}

/// The bound on one model call (v1.35): the seconds the provider's HTTP client waits for a reply before the call fails,
/// from ^Shutter.Config("providerTimeoutSeconds") (SHUTTER_PROVIDER_TIMEOUT_SECONDS at a start), 120 when unset, held to 10
/// to 600. The AI Hub runner passes it to the provider as http_config.request_timeout_secs unless the provider's own
/// configuration sets one, so a hung model call ends in a run error instead of holding a board member until the board's
/// timeout. Below the board's 600 s by design.
ClassMethod ProviderTimeoutSeconds() As %Integer
{
    Set v = +$GET(^Shutter.Config("providerTimeoutSeconds"))
    If v <= 0 Quit 120
    Quit $SELECT(v < 10: 10, v > 600: 600, 1: v)
}

/// Sets the bound; "" or 0 puts the default back. Returns the value in force.
ClassMethod ConfigureProviderTimeout(seconds As %String) As %Integer
{
    Set seconds = $ZSTRIP(seconds, "<>W")
    If (seconds = "") || (+seconds <= 0) { Kill ^Shutter.Config("providerTimeoutSeconds") } Else { Set ^Shutter.Config("providerTimeoutSeconds") = +seconds }
    Quit ..ProviderTimeoutSeconds()
}

/// The container's environment applied to a running instance (v1.34): the model budget (SHUTTER_DAILY_BUDGET_USD,
/// SHUTTER_JUDGE_BUDGET_USD), the public demo's logins (SHUTTER_PUBLIC_DEMO_PASSWORD, SHUTTER_TRACE_PASSWORD,
/// SHUTTER_JUDGE_PASSWORD), the live hospital (SHUTTER_LIVE) and the public demo's portal (SHUTTER_DEMO_PORTAL, v1.39: 1
/// hardens the Management Portal at every start, HardenPortal). Shutter.Production's OnStart calls it, so what .env says
/// reaches an instance started with `docker compose up` without a build argument (and a changed cap or password takes effect
/// on the next start); SELECT Shutter.Setup_ApplyEnvironment() applies it by hand. A variable that is empty or unset leaves
/// its setting as it is (the install's own reading, or what an approver set since). Returns JSON: what was applied, and
/// an error when one step failed (the others still run).
ClassMethod ApplyEnvironment(wait As %Integer = 0) As %String [ SqlProc ]
{
    Set out = ..ApplyRuntime($SYSTEM.Util.GetEnviron("SHUTTER_DAILY_BUDGET_USD"), $SYSTEM.Util.GetEnviron("SHUTTER_JUDGE_BUDGET_USD"), $SYSTEM.Util.GetEnviron("SHUTTER_PUBLIC_DEMO_PASSWORD"), $SYSTEM.Util.GetEnviron("SHUTTER_TRACE_PASSWORD"), $SYSTEM.Util.GetEnviron("SHUTTER_JUDGE_PASSWORD"), $SYSTEM.Util.GetEnviron("SHUTTER_LIVE"), wait, $SYSTEM.Util.GetEnviron("SHUTTER_PROVIDER_TIMEOUT_SECONDS"), $SYSTEM.Util.GetEnviron("SHUTTER_DEMO_BUDGET_USD"), $SYSTEM.Util.GetEnviron("SHUTTER_DEMO_BUDGET_PERIOD"), $SYSTEM.Util.GetEnviron("SHUTTER_LIVE_SCENARIOS"), $SYSTEM.Util.GetEnviron("SHUTTER_DEMO_PORTAL"))
    // The credential checks' cache, from this privileged process (v1.38): the anonymous health report only reads it.
    Set out.credentials = ..RefreshCredentialCache(1)
    Quit out.%ToJSON()
}

/// ApplyEnvironment's work on values, so a test can give them: each applied when not empty. live is "1" for on, any other
/// non-empty value for off; wait is how many seconds the live hospital's item may be left to a background job while the
/// hospital's production is still starting (the production's own start passes 120; by hand, 0 applies it at once). portal is
/// "1" to harden the Management Portal (HardenPortal) and record it as ^Shutter.Config("portalHardened"), the time, or on a
/// failure the errors as ^Shutter.Config("portalHardeningErrors"), the stamp of an earlier start cleared either way; any
/// other value leaves the portal as it is. Never a reading of the demo flag: a local demo keeps the portal as IRIS made it.
ClassMethod ApplyRuntime(dailyUsd As %String, judgeUsd As %String, publicPw As %String, tracePw As %String, judgePw As %String, live As %String, wait As %Integer = 0, providerTimeout As %String = "", demoUsd As %String = "", demoPeriod As %String = "", liveScenarios As %String = "", portal As %String = "") As %DynamicObject
{
    Set out = {}, errors = []
    Set ns = $NAMESPACE
    Try {
        If $ZSTRIP(dailyUsd, "<>W") '= "" Set out.dailyBudgetUsd = ##class(Shutter.Util.Budget).Configure(dailyUsd)
        If $ZSTRIP(judgeUsd, "<>W") '= "" Set out.judgeBudgetUsd = ##class(Shutter.Util.Budget).ConfigureShare(judgeUsd)
        // The bound on one model call (v1.35).
        If $ZSTRIP(providerTimeout, "<>W") '= "" Set out.providerTimeoutSeconds = ..ConfigureProviderTimeout(providerTimeout)
        // The demo's budget note for the live banner (v1.37).
        If $ZSTRIP(demoUsd, "<>W") '= "" Set out.demoBudget = ##class(Shutter.Util.Budget).ConfigureDemoBudget(demoUsd, demoPeriod)
        // The live hospital's rotation (v1.38).
        If $ZSTRIP(liveScenarios, "<>W") '= "" Set out.liveScenarios = ..ConfigureLiveScenarios(liveScenarios)
    } Catch ex {
        Do errors.%Push("budget: " _ ex.DisplayString())
    }
    Try {
        If (publicPw '= "") || (tracePw '= "") || (judgePw '= "") {
            Set sc = ..EnsurePublicUsers(ns, publicPw, tracePw, judgePw)
            If $$$ISERR(sc) Do errors.%Push("users: " _ $SYSTEM.Status.GetErrorText(sc))
            Set users = []
            If publicPw '= "" Do users.%Push("demo")
            If tracePw '= "" Do users.%Push("demo-trace")
            If judgePw '= "" Do users.%Push("judge")
            Set out.users = users
            // The Workflow role takes the demo's and the judge's users once they exist (approvals).
            If $$$ISOK(sc) Set sc = ..CreateWorkflowRole(''$GET(^Shutter.Config("demo")))
            If $$$ISERR(sc) Do errors.%Push("workflow role: " _ $SYSTEM.Status.GetErrorText(sc))
        }
    } Catch ex {
        Do errors.%Push("users: " _ ex.DisplayString())
    }
    Try {
        If $ZSTRIP(live, "<>W") '= "" {
            Set on = ($ZSTRIP(live, "<>W") = "1")
            Do out.%Set("live", on, "boolean")
            Set root = $GET(^Shutter.Config("root"))
            If on && (root '= "") {
                Set sc = ..LiveProfilePolicy(root _ "knowledge/site/profile.json", 1)
                If $$$ISERR(sc) Do errors.%Push("live profile: " _ $SYSTEM.Status.GetErrorText(sc))
            }
            Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
            If hospital '= "" Set out.hospital = ..ApplyLive(hospital, on, wait)
        }
    } Catch ex {
        Do errors.%Push("live: " _ ex.DisplayString())
    }
    Set portalOn = ($ZSTRIP(portal, "<>W") = "1"), problem = ""
    Try {
        // The public demo's portal (v1.39): the hardening lives in IRISSYS, which no volume keeps, so a recreated container
        // would come back with the portal open to the demo users; applied again at every start when the environment asks.
        // The record stands for the latest start alone (the delta sweep of 3 Nov 2026): both nodes are cleared before the
        // attempt, so a start whose hardening fails leaves no stamp from an earlier success, and its errors beside it for
        // the Doctor (portal_hardening_errors).
        If portalOn {
            Kill ^Shutter.Config("portalHardened"), ^Shutter.Config("portalHardeningErrors")
            Set hardened = ##class(Shutter.Util.Json).Parse(..HardenPortal(), .sc)
            If $$$ISERR(sc) || '$ISOBJECT(hardened) {
                Set problem = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no answer")
            } ElseIf hardened.%IsDefined("error") {
                Set problem = hardened.error
            } ElseIf hardened.%IsDefined("errors") {
                Set problem = hardened.errors.%ToJSON()
            } Else {
                Set ^Shutter.Config("portalHardened") = ##class(Shutter.Util.Time).NowUTC()
                Set out.portal = {"hardened": true, "at": (^Shutter.Config("portalHardened"))}
            }
        }
    } Catch ex {
        Set problem = ex.DisplayString()
    }
    If problem '= "" {
        Do errors.%Push("portal: " _ problem)
        If portalOn Set ^Shutter.Config("portalHardeningErrors") = problem
    }
    If errors.%Size() > 0 Set out.errors = errors
    Quit out
}

/// The production's stored credentials against the users they name (v1.38; the v0.2.1 demo rehearsal: a rebuild that
/// kept the data volume while the users got a new password left ShutterIntake and DownstreamAPI with the old one, so every
/// forward and delivery answered 401 and no case opened). Each credential the install makes, DownstreamAPI here on a demo
/// install and the demo hospital's DownstreamAPI and ShutterIntake, is tried by a login as the user and password it stores,
/// in a short background job of this instance (no web request, no CSP session, no licence held): {namespace, name, user,
/// status, ok, detail}, ok false when the login is refused or the credential is missing.
///
/// The result lives in ^Shutter.Health("credentials") for ten minutes (CACHESECONDS), and only a process that may write
/// the database computes it: the production's start (ApplyEnvironment) and the Case Releaser's sweep, which recomputes it
/// when stale. A request that cannot write (the hardened demo's anonymous GET /health runs as UnknownUser, with no roles,
/// and a write there answered <PROTECT> on 3 Nov 2026) only reads: the cache as it stands, stale or not, or nothing when
/// there is none yet. state says which: fresh, refreshed, stale or unchecked. refresh recomputes now when the caller may.
/// The Doctor carries the list as credentials, with credentials_ok, credentials_state and credentials_checked_at; GET
/// /health?refresh=1 recomputes for an operator who may write.
ClassMethod CredentialChecks(refresh As %Boolean = 0, Output state As %String, canWrite As %Integer = -1) As %DynamicArray
{
    Set state = "unchecked"
    Set at = $GET(^Shutter.Health("credentials", "at")), now = ##class(Shutter.Util.Time).EpochSeconds()
    Set cached = "", fresh = (at '= "") && ((now - at) < ..#CACHESECONDS)
    If at '= "" Try { Set cached = ##class(%DynamicArray).%FromJSON($GET(^Shutter.Health("credentials", "json"), "[]")) } Catch ex { Set cached = "" }
    If canWrite = -1 Set canWrite = ..CanWriteHealth()
    If $ISOBJECT(cached) && fresh && ('refresh || 'canWrite) Set state = "fresh" Quit cached
    If 'canWrite {
        If $ISOBJECT(cached) Set state = "stale" Quit cached
        Quit []
    }
    Set out = []
    If $GET(^Shutter.Config("demo")) Do out.%Push(..CredentialCheck($NAMESPACE, "DownstreamAPI"))
    Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
    If hospital '= "" {
        Do out.%Push(..CredentialCheck(hospital, "DownstreamAPI"))
        Do out.%Push(..CredentialCheck(hospital, "ShutterIntake"))
    }
    // Each onboarded namespace's forwarder (v1.42), and the credential a receiver's connector item names.
    Set onboarded = ""
    For {
        Set onboarded = $ORDER(^Shutter.Config("onboard", onboarded)) Quit:onboarded=""
        Continue:onboarded=hospital
        Do out.%Push(..CredentialCheck(onboarded, $GET(^Shutter.Config("onboard", onboarded, "credential"), "ShutterIntake")))
    }
    Set item = ""
    For {
        Set item = $ORDER(^Shutter.Config("receiverItems", item), 1, was) Quit:item=""
        Continue:$DATA(checked($LIST(was, 3)))
        Set checked($LIST(was, 3)) = 1
        Do out.%Push(..CredentialCheck($NAMESPACE, $LIST(was, 3)))
    }
    Try {
        Set ^Shutter.Health("credentials", "json") = out.%ToJSON(), ^Shutter.Health("credentials", "at") = ##class(Shutter.Util.Time).EpochSeconds()
        Set ^Shutter.Health("credentials", "iso") = ##class(Shutter.Util.Time).NowUTC()
        Set state = "refreshed"
    } Catch ex {
        // A process that passed the probe but cannot write after all: the result is served, not kept.
        Set state = "uncached"
    }
    Quit out
}

/// Whether this process may write the health cache: a probe write in ^Shutter.Health, since a request may run as a user
/// with no roles (a read of the security tables would be refused the same way).
ClassMethod CanWriteHealth() As %Boolean
{
    Try {
        Set ^Shutter.Health("probe", $JOB) = 1
        Kill ^Shutter.Health("probe", $JOB)
        Return 1
    } Catch ex {
        Return 0
    }
    Quit 0
}

/// Keeps the credential checks' cache fresh from a process that may write: the production's start and the Case
/// Releaser's sweep call it; it recomputes only when the cache is older than CACHESECONDS, and never throws.
ClassMethod RefreshCredentialCache(force As %Boolean = 0) As %String
{
    Set state = ""
    Try { Do ..CredentialChecks(force, .state) } Catch ex { Set state = "error: " _ ex.DisplayString() }
    Quit state
}

/// How long the credential checks' result is kept, in seconds.
Parameter CACHESECONDS = 600;

/// One stored credential tried: a login as its user and password, in a background job.
ClassMethod CredentialCheck(ns As %String, name As %String) As %DynamicObject
{
    Set c = {}
    Set c.namespace = ns, c.name = name, c.user = "", c.status = "", c.detail = ""
    Do c.%Set("ok", 0, "boolean")
    Try {
        If '..StoredCredential(ns, name, .user, .password) {
            Set c.status = "missing", c.detail = "no credential " _ name _ " in " _ ns
        } Else {
            Set c.user = user
            If ..TryLogin(user, password, .reason) {
                Set c.status = "ok", c.detail = user _ " signs in with the stored password"
                Do c.%Set("ok", 1, "boolean")
            } Else {
                Set c.status = $SELECT(reason [ "did not answer": "error", 1: "refused")
                Set c.detail = $SELECT(c.status = "refused": user _ " does not sign in with the stored password (" _ reason _ "): the credential and the user disagree, as after a rebuild that kept the data volume while the users got a new password", 1: reason)
            }
        }
    } Catch ex {
        Set c.status = "error", c.detail = ex.DisplayString()
    }
    Quit c
}

/// The user and password a namespace's credential stores; 0 when there is none.
ClassMethod StoredCredential(ns As %String, name As %String, Output user As %String, Output password As %String) As %Boolean
{
    Set user = "", password = ""
    New $NAMESPACE
    Set $NAMESPACE = ns
    Set cred = ##class(Ens.Config.Credentials).%OpenId(name)
    If '$ISOBJECT(cred) Quit 0
    Set user = cred.Username, password = cred.Password
    Quit 1
}

/// Whether a user and password sign in to this instance: a background job logs in as them and reports through
/// ^Shutter.Health("login", key), so this process keeps its own identity and no web session is made. Up to five seconds.
ClassMethod TryLogin(user As %String, password As %String, Output reason As %String) As %Boolean
{
    Set reason = "", key = $JOB _ "." _ $ZHOROLOG
    Kill ^Shutter.Health("login", key)
    Job ##class(Shutter.Setup).LoginJob(user, password, key)
    For i = 1:1:100 { Quit:$DATA(^Shutter.Health("login", key))  Hang 0.05 }
    Set r = $GET(^Shutter.Health("login", key))
    Kill ^Shutter.Health("login", key)
    If r = "" Set reason = "the check did not answer within 5 s" Quit 0
    Set reason = $PIECE(r, "|", 2, *)
    Quit +$PIECE(r, "|", 1)
}

/// The background job of TryLogin: logs in as the user and writes 1 or 0 with the reason.
ClassMethod LoginJob(user As %String, password As %String, key As %String)
{
    Set ok = 0, why = ""
    Try {
        Set ok = ''$SYSTEM.Security.Login(user, password)
        If 'ok Set why = "the password is not the user's, or the user is disabled"
    } Catch ex {
        Set why = ex.DisplayString()
    }
    Set ^Shutter.Health("login", key) = ok _ "|" _ why
}

/// The demo's Management Portal, read only (v1.38; the demo portal review of 3 Nov 2026). The portal web applications of
/// Shutter's and the demo hospital's namespaces (/csp/healthshare/<namespace>, as IRIS for Health makes them) add roles to
/// every user who signs in (MatchRoles: %HS_DB_<namespace>, with the data database read and write, and the HealthShare
/// databases) and require no resource, so demo-trace can write what the portal's pages save (saved searches, the Event
/// Log's defaults, the Visual Trace's settings), the Production Monitor can switch items off, and demo and judge can sign
/// in to the portal too. For a public demo only (the demo's harden script calls it; a local install keeps the portal as
/// IRIS made it, since an approver following the "In IRIS" links relies on those roles): the applications' MatchRoles are
/// cleared and each requires the resource Shutter_Portal, which Shutter_Trace alone holds; Shutter_Trace keeps its
/// Interoperability resources and reads the HealthShare databases and both namespaces' code and data databases, writing
/// none. Needs %Admin_Secure. Returns JSON: the applications changed, the role's resources, errors. PortalState shows it.
ClassMethod HardenPortal(hospital As %String = "") As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("%Admin_Secure", "USE") Quit {"error": "%Admin_Secure is required"}.%ToJSON()
    If (hospital = "") || (hospital = $CHAR(0)) Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
    Set ns = $NAMESPACE, out = {}, errors = [], apps = []
    Set reads = ..PortalReads(ns, hospital)
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        If '##class(Security.Resources).Exists("Shutter_Portal") {
            Set sc = ##class(Security.Resources).Create("Shutter_Portal", "Shutter public demo: the Management Portal's pages, for demo-trace alone", "")
            If $$$ISERR(sc) Do errors.%Push("resource: " _ $SYSTEM.Status.GetErrorText(sc))
        }
        // The trace role: its own resources kept, every database resource replaced by the reads, the portal resource added.
        Set sc = ##class(Security.Roles).Get("Shutter_Trace", .rp)
        If $$$ISERR(sc) {
            Do errors.%Push("role: " _ $SYSTEM.Status.GetErrorText(sc))
        } Else {
            Set kept = ""
            For i = 1:1:$LENGTH($GET(rp("Resources")), ",") {
                Set r = $PIECE(rp("Resources"), ",", i)
                Continue:r=""
                Continue:$EXTRACT(r, 1, 4)="%DB_"
                Continue:$PIECE(r, ":", 1)="Shutter_Portal"
                Set kept = kept _ $SELECT(kept = "": "", 1: ",") _ r
            }
            If '$FIND(kept, "%Ens_EventLog:") Set kept = kept _ $SELECT(kept = "": "", 1: ",") _ "%Ens_EventLog:U"
            Set resources = kept _ $SELECT(kept = "": "", 1: ",") _ reads _ ",Shutter_Portal:U"
            Kill props
            Set props("Resources") = resources
            Set sc = ##class(Security.Roles).Modify("Shutter_Trace", .props)
            If $$$ISERR(sc) Do errors.%Push("role: " _ $SYSTEM.Status.GetErrorText(sc))
            Set out.role = resources
        }
        // The pages read through SQL too (the Message Viewer's search and contents, the Event Log): SELECT alone on the
        // message tables of both namespaces, since the MatchRoles that carried it are gone; never a %DB_ role.
        Set grants = {}
        For n = ns, hospital {
            Continue:(n="")||(n=$CHAR(0))
            Set r = ..TraceSelectGrant(n, 1, .count, .problem)
            Do grants.%Set(n, count, "number")
            If problem '= "" Do errors.%Push(n _ " grants: " _ problem)
        }
        Set out."select_grants" = grants
        For app = ..PortalApp(ns), ..PortalApp(hospital) {
            Continue:app=""
            Continue:'##class(Security.Applications).Exists(app)
            Kill ap
            Do ##class(Security.Applications).Get(app, .ap)
            Set a = {}
            Set a.name = app, a."match_roles_were" = $GET(ap("MatchRoles")), a."resource_was" = $GET(ap("Resource"))
            // What the uninstall puts back (Shutter.Util.Uninstall.TakePortal). A later start finds it hardened already.
            If $GET(ap("Resource")) '= "Shutter_Portal" Set ^|ns|Shutter.Config("portalWas", app) = $LISTBUILD($GET(ap("MatchRoles")), $GET(ap("Resource")))
            Kill props
            Set props("MatchRoles") = "", props("Resource") = "Shutter_Portal"
            Set sc = ##class(Security.Applications).Modify(app, .props)
            If $$$ISERR(sc) Do errors.%Push(app _ ": " _ $SYSTEM.Status.GetErrorText(sc))
            Do apps.%Push(a)
        }
    } Catch ex {
        Do errors.%Push(ex.DisplayString())
    }
    Set out.apps = apps
    If errors.%Size() > 0 Set out.errors = errors
    Quit out.%ToJSON()
}

/// The tables the portal's pages read through SQL in a namespace: the Interoperability tables (the message headers, the
/// event log, the configuration, the alerts), the HL7 messages, and the productions' own message bodies.
ClassMethod TraceSelectTables(ns As %String) As %List
{
    Set out = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ns
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TABLE_SCHEMA, TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' AND (TABLE_SCHEMA = 'Ens' OR TABLE_SCHEMA %STARTSWITH 'Ens_' OR TABLE_SCHEMA %STARTSWITH 'EnsLib_HL7' OR TABLE_SCHEMA IN ('Shutter_Msg', 'Shutter_Bridge_Msg', 'Shutter_Intake', 'Hospital_Msg', 'Downstream_Msg')) ORDER BY TABLE_SCHEMA, TABLE_NAME")
        While rs.%Next() { Set out = out _ $LISTBUILD(rs.%Get("TABLE_SCHEMA") _ "." _ rs.%Get("TABLE_NAME")) }
    } Catch ex {
    }
    Quit out
}

/// SELECT on TraceSelectTables for the role Shutter_Trace in a namespace (grant 1), or taken away again (grant 0, for
/// the tests). count is how many tables were done; problem the first failure.
ClassMethod TraceSelectGrant(ns As %String, grant As %Boolean = 1, Output count As %Integer, Output problem As %String) As %Status [ SqlProc ]
{
    Set count = 0, problem = "", sc = $$$OK
    Set tables = ..TraceSelectTables(ns)
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ns
        For i = 1:1:$LISTLENGTH(tables) {
            Set t = $LIST(tables, i)
            Set one = $SELECT(grant: $SYSTEM.SQL.Security.GrantPrivilege("SELECT", t, "TABLE", "Shutter_Trace"), 1: $SYSTEM.SQL.Security.RevokePrivilege("SELECT", t, "TABLE", "Shutter_Trace"))
            If $$$ISOK(one) { Set count = count + 1 } ElseIf problem = "" { Set problem = t _ ": " _ $SYSTEM.Status.GetErrorText(one), sc = one }
        }
    } Catch ex {
        Set problem = ex.DisplayString(), sc = ex.AsStatus()
    }
    Quit sc
}

/// The trace role's SQL privileges in a namespace, asked table by table ($SYSTEM.SQL.Security.CheckPrivilege, which
/// answers for a role): reads (SELECT on Ens.MessageHeader, Ens_Util.Log and the HL7 message table), writes_none (no
/// INSERT, UPDATE or DELETE on any of the tables the pages read), and the counts.
ClassMethod TraceSqlState(ns As %String) As %DynamicObject
{
    Set o = {}
    Do o.%Set("reads", 0, "boolean"), o.%Set("writes_none", 1, "boolean")
    Set o."select_tables" = 0, o."write_privileges" = 0
    Try {
        Set tables = ..TraceSelectTables(ns), key = 0
        For i = 1:1:$LISTLENGTH(tables) {
            Set t = $LIST(tables, i)
            If $SYSTEM.SQL.Security.CheckPrivilege("Shutter_Trace", 1, t, "s", ns) {
                Set o."select_tables" = o."select_tables" + 1
                If $LISTFIND($LISTBUILD("Ens.MessageHeader", "Ens_Util.Log", "EnsLib_HL7.Message"), t) Set key = key + 1
            }
            For a = "i", "u", "d" { If $SYSTEM.SQL.Security.CheckPrivilege("Shutter_Trace", 1, t, a, ns) Set o."write_privileges" = o."write_privileges" + 1 }
        }
        Do o.%Set("reads", key = 3, "boolean")
        Do o.%Set("writes_none", o."write_privileges" = 0, "boolean")
    } Catch ex {
        Set o.error = ex.DisplayString()
        Do o.%Set("reads", 0, "boolean")
    }
    Quit o
}

/// The portal web application of a namespace, as IRIS for Health names it; "" for no namespace.
ClassMethod PortalApp(ns As %String) As %String
{
    If (ns = "") || (ns = $CHAR(0)) Quit ""
    Quit "/csp/healthshare/" _ $ZCONVERT(ns, "L")
}

/// The read resources the portal's pages need: the HealthShare databases that exist here and both namespaces' code and
/// data databases, each :R.
ClassMethod PortalReads(ns As %String, hospital As %String = "") As %String
{
    Set list = ""
    For r = "%DB_HSLIB", "%DB_HSSYS", "%DB_HSCUSTOM" { If ..ResourceExists(r) Set list = list _ $SELECT(list = "": "", 1: ",") _ r _ ":R" }
    For n = ns, hospital {
        Continue:(n="")||(n=$CHAR(0))
        For code = 0, 1 {
            Set r = ..DatabaseResource(n, code)
            If (r '= "") && (r '= "%DB_%DEFAULT") && '$FIND(list, r _ ":") Set list = list _ $SELECT(list = "": "", 1: ",") _ r _ ":R"
        }
    }
    Quit list
}

/// Whether a security resource exists (asked in %SYS).
ClassMethod ResourceExists(name As %String) As %Boolean
{
    Set exists = 0
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set exists = ''##class(Security.Resources).Exists(name)
    } Catch ex {
    }
    Quit exists
}

/// The portal's state for the demo's checks: each namespace's portal application (exists, MatchRoles, the required
/// resource), the trace role's resources, and hardened (every existing application cleared and gated, the role writing
/// no database). Needs %Admin_Secure to read the security tables; otherwise it says so.
ClassMethod PortalState(hospital As %String = "") As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("%Admin_Secure", "USE") Quit {"error": "%Admin_Secure is required"}.%ToJSON()
    If (hospital = "") || (hospital = $CHAR(0)) Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
    Set ns = $NAMESPACE, out = {}, apps = [], hardened = 1, any = 0
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        For app = ..PortalApp(ns), ..PortalApp(hospital) {
            Continue:app=""
            Set a = {}
            Set a.name = app
            Do a.%Set("exists", ''##class(Security.Applications).Exists(app), "boolean")
            If a.exists {
                Kill ap
                Do ##class(Security.Applications).Get(app, .ap)
                Set a."match_roles" = $GET(ap("MatchRoles")), a.resource = $GET(ap("Resource")), any = 1
                If (a."match_roles" '= "") || (a.resource '= "Shutter_Portal") Set hardened = 0
            }
            Do apps.%Push(a)
        }
        Set sc = ##class(Security.Roles).Get("Shutter_Trace", .rp)
        Set out."trace_role" = $SELECT($$$ISOK(sc): $GET(rp("Resources")), 1: "")
        If $$$ISERR(sc) Set hardened = 0
        If $$$ISOK(sc) {
            For i = 1:1:$LENGTH($GET(rp("Resources")), ",") {
                Set r = $PIECE(rp("Resources"), ",", i)
                If ($EXTRACT(r, 1, 4) = "%DB_") && ($PIECE(r, ":", 2) [ "W") Set hardened = 0
            }
            If '$FIND($GET(rp("Resources")), "Shutter_Portal:U") Set hardened = 0
            If '$FIND($GET(rp("Resources")), "%Ens_EventLog:U") Set hardened = 0
        }
        // The SQL side (v1.38): SELECT on the message tables, and no INSERT, UPDATE or DELETE anywhere, in each namespace.
        Set sql = {}
        For n = ns, hospital {
            Continue:(n="")||(n=$CHAR(0))
            Set one = ..TraceSqlState(n)
            Do sql.%Set(n, one)
            If 'one.reads || 'one."writes_none" Set hardened = 0
        }
        Set out.sql = sql
    } Catch ex {
        Set out.error = ex.DisplayString(), hardened = 0
    }
    Set out.apps = apps
    Do out.%Set("hardened", hardened && any, "boolean")
    Quit out.%ToJSON()
}

/// The live hospital's rotation from the build (SHUTTER_LIVE_SCENARIOS, v1.38): the scenario ids, comma-separated, each
/// an S and a number with an optional letter (S23a), in the order to play; "default" or no valid id clears the override, and
/// the player's own Scenarios setting applies again. Written as ^Hospital.Config("liveScenarios") in the hospital's
/// namespace, which Hospital.LivePlayer.ScenarioList reads first. Returns the list set, "default", or "no hospital".
ClassMethod ConfigureLiveScenarios(value As %String) As %String
{
    Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
    If hospital = "" Quit "no hospital"
    Set list = ""
    For i = 1:1:$LENGTH($GET(value), ",") {
        Set s = $ZSTRIP($PIECE(value, ",", i), "<>W")
        If s = "" Continue
        Set s = $ZCONVERT($EXTRACT(s, 1), "U") _ $EXTRACT(s, 2, *)
        If s ? 1"S"1.N.1L Set list = list _ $SELECT(list = "": "", 1: ",") _ s
    }
    If list = "" Kill ^|hospital|Hospital.Config("liveScenarios") Quit "default"
    Set ^|hospital|Hospital.Config("liveScenarios") = list
    Quit list
}

/// The live hospital's switch in the hospital's namespace (Hospital.Setup.SetLive): at once when its production is running
/// or wait is 0; else from a background job that waits up to wait seconds for the production, since Shutter's production
/// starts beside the hospital's at an instance start and an item cannot be switched in a production that is still starting.
ClassMethod ApplyLive(hospital As %String, on As %Boolean, wait As %Integer = 0) As %String
{
    Set running = 0, problem = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = hospital
        Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
        Set running = $$$ISOK(sc) && (state = 1) && (name = "Hospital.Production")
    } Catch ex {
        Set problem = "error: " _ ex.DisplayString()
    }
    If problem '= "" Quit problem
    If running || (wait <= 0) {
        Set r = ""
        Try {
            New $NAMESPACE
            Set $NAMESPACE = hospital
            Set r = ##class(Hospital.Setup).SetLive(on)
        } Catch ex {
            Set r = "error: " _ ex.DisplayString()
        }
        Quit r
    }
    Job ..ApplyLiveLater(hospital, on, wait)
    Quit "queued: the hospital's production is still starting; a background job applies live=" _ on _ " within " _ wait _ " s"
}

/// The background half of ApplyLive: waits for the hospital's production, then switches the live hospital; logs the result.
ClassMethod ApplyLiveLater(hospital As %String, on As %Boolean, wait As %Integer)
{
    Set deadline = $ZHOROLOG + wait, r = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = hospital
        For {
            Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
            Quit:($$$ISOK(sc) && (state = 1) && (name = "Hospital.Production"))
            Quit:($ZHOROLOG > deadline)
            Hang 2
        }
        Set r = ##class(Hospital.Setup).SetLive(on)
    } Catch ex {
        Set r = "error: " _ ex.DisplayString()
    }
    Try { Do ##class(Ens.Util.Log).LogInfo($CLASSNAME(), "ApplyLiveLater", "SHUTTER_LIVE applied to " _ hospital _ " (live=" _ on _ "): " _ r) } Catch {}
}

/// Whether a user exists, read in %SYS (Security.Users is not visible from the namespace).
ClassMethod UserExists(user As %String) As %Boolean [ Private ]
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Quit ''##class(Security.Users).Exists(user)
}

/// A user with one role and a password, made or brought back to that definition (enabled, the role, the password).
ClassMethod EnsureUser(user As %String, role As %String, password As %String, fullName As %String, ns As %String) As %Status [ Private ]
{
    If ##class(Security.Users).Exists(user) {
        Do ##class(Security.Users).AddRoles(user, role)
        Quit ..ResetDemoUser(user, password)
    }
    Quit ##class(Security.Users).Create(user, role, password, fullName, ns, "", "", 0, 1, "Shutter public demo user")
}

/// SQL SELECT on Shutter's schemas for the roles that call the API. The API reads with %ExecDirectNoPriv, which skips the
/// privilege check when a statement is prepared, but not when the caller's own process has to compile the cached query
/// again: a query marked stale (the table's statistics were gathered after it was made, or its plan is chosen at run
/// time) is regenerated by whoever runs it next, and that regeneration checks SELECT on the table as the caller. On a
/// fresh instance the operator was the first to list the production reviews and got SQLCODE -99 "not privileged" while
/// every other read worked (CI, 25 October 2026); with these grants the regeneration passes whoever triggers it. The
/// public demo's roles (Shutter_Demo, Shutter_Judge) read the same routes and hold neither of the others, so they are
/// granted too; the trace role never calls the API. A schema grant covers the tables made later in the schema too.
/// Runs in the namespace; the installer has the privileges.
ClassMethod GrantSqlPrivileges(ns As %String) As %Status
{
    Set sc = $$$OK
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ns
        For role = "Shutter_Operator", "Shutter_Approver", "Shutter_Demo", "Shutter_Judge" {
            For schema = "Shutter_Store", "Shutter_Index", "Shutter_Msg", "Shutter_Bridge", "Ens_Config" {
                Set rs = ##class(%SQL.Statement).%ExecDirect(, "GRANT SELECT ON SCHEMA " _ schema _ " TO " _ role)
                If rs.%SQLCODE < 0 Set sc = $$$ERROR($$$GeneralError, "GRANT SELECT ON SCHEMA " _ schema _ " TO " _ role _ " failed: SQLCODE " _ rs.%SQLCODE _ ": " _ rs.%Message) Quit
            }
            Quit:$$$ISERR(sc)
        }
        Quit:$$$ISERR(sc)
        // The forwarder opens cases through the intake route, which reads the case and idempotency stores.
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "GRANT SELECT ON SCHEMA Shutter_Store TO Shutter_Forwarder")
        If rs.%SQLCODE < 0 Set sc = $$$ERROR($$$GeneralError, "GRANT SELECT ON SCHEMA Shutter_Store TO Shutter_Forwarder failed: SQLCODE " _ rs.%SQLCODE _ ": " _ rs.%Message)
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// The roles brought to their definition again and the SQL grants renewed, for a change that widens them after the
/// install: Hospital.Setup calls it once the hospital's namespace is recorded, so the operator and the approver can read
/// it. demo is read from the namespace's configuration.
ClassMethod RefreshSecurity(ns As %String) As %Status
{
    Set sc = ..CreateSecurity(ns, ''$GET(^|ns|Shutter.Config("demo"), 1))
    Quit:$$$ISERR(sc) sc
    Quit ..GrantSqlPrivileges(ns)
}

/// The demo records system's web application, /records/api, on the RECORDS namespace with the demo receiver package's
/// dispatch class and resource, and its demo flag (^Downstream.Config("demo") in that namespace), so the scenario
/// runner can reset it and set its faults (CONTRACTS 12, v1.25). shutterNs records the application for Uninstall.
ClassMethod InstallRecords(recordsNs As %String = "RECORDS", shutterNs As %String = "") As %Status
{
    Set sc = $$$OK
    If shutterNs = "" Set shutterNs = $NAMESPACE
    Try {
        Set ^|recordsNs|Downstream.Config("demo") = 1
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        If '##class(Config.Namespaces).Exists(recordsNs) Set sc = $$$ERROR($$$GeneralError, "The records namespace " _ recordsNs _ " does not exist") Quit
        Kill props
        Set props("NameSpace") = recordsNs
        Set props("Description") = "Shutter: the demo patient records system's API (the second demo receiver)"
        Set props("Enabled") = 1
        Set props("AutheEnabled") = 32
        Set props("DispatchClass") = "Downstream.API"
        If ##class(Security.Resources).Exists("Downstream_API") Set props("Resource") = "Downstream_API"
        Set props("UseCookies") = 2
        Set props("CookiePath") = "/records/api/"
        If ##class(Security.Applications).Exists("/records/api") {
            Set sc = ##class(Security.Applications).Modify("/records/api", .props)
        } Else {
            Set sc = ##class(Security.Applications).Create("/records/api", .props)
        }
        Quit:$$$ISERR(sc)
        Set ^|shutterNs|Shutter.Config("webapp", "/records/api") = 1
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit:$$$ISERR(sc) sc
    // The roles take the records databases (CreateSecurity reads the namespace), and the SQL grants are renewed.
    Quit ..RefreshSecurity(shutterNs)
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
        // The public demo's user approves through the same Workflow role (v1.34), when the install (or the environment at a
        // start, ApplyEnvironment) made it.
        If $$$ISOK(sc) && ..UserExists("demo") {
            If '##class(EnsLib.Workflow.UserDefinition).%ExistsId("demo") Set sc = ##class(EnsLib.Workflow.UserDefinition).CreateUser("demo", "Shutter public demo")
            If $$$ISOK(sc) && '##class(EnsLib.Workflow.RoleMembership).%ExistsId(role _ "||demo") Set sc = ##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(role, "demo", 1, "Demo")
        }
        // And the judge's (v1.34), who approves as the demo's user does.
        If $$$ISOK(sc) && ..UserExists("judge") {
            If '##class(EnsLib.Workflow.UserDefinition).%ExistsId("judge") Set sc = ##class(EnsLib.Workflow.UserDefinition).CreateUser("judge", "Shutter judge")
            If $$$ISOK(sc) && '##class(EnsLib.Workflow.RoleMembership).%ExistsId(role _ "||judge") Set sc = ##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(role, "judge", 1, "Judge")
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
        // The demo records system (v1.25), when its namespace is there (the image's installer makes it before the load).
        If ##class(Config.Namespaces).Exists("RECORDS") Set sc = ..InstallRecords("RECORDS", ns) Quit:$$$ISERR(sc)
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
/// The demo's release policy (v1.1.0): a demo install (demo 1, or ^Shutter.Config("demo") when -1) whose profile is still the seed's stores
/// Shutter.Store.SiteProfile.DemoPolicy() as the policy, with the seed's path and " (demo)" as the source, which the seed
/// leaves alone on a reinstall and the Site profile page labels as the demo's answers, and keeps the demo's stop for another
/// visit's in-patient movement (further_messages.in_patient_movement: stop; shipped as show since v1.47), on the live
/// hospital's profile too. A site install (demo 0) keeps the shipped table, approval everywhere, and the shipped show. A profile a person saved is never touched. Returns a status; nothing changes when
/// the policy already reads so.
ClassMethod DemoProfilePolicy(seedPath As %String, demo As %Integer = -1) As %Status
{
    If demo = -1 Set demo = +$GET(^Shutter.Config("demo"))
    Quit:'demo $$$OK
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Quit:'$ISOBJECT(row) $$$OK
    Set demoSource = seedPath _ " (demo)", liveDemo = demoSource _ " (live hospital)"
    Quit:((row.Source '= seedPath) && (row.Source '= demoSource) && (row.Source '= liveDemo)) $$$OK
    Set p = ##class(Shutter.Util.Json).Parse(row.Json, .sc)
    Quit:('$ISOBJECT(p) || $$$ISERR(sc)) $$$OK
    Set want = ##class(Shutter.Store.SiteProfile).DemoPolicy()
    // The live hospital's profile (LiveProfilePolicy) keeps its own policy; only the demo's stop is added to it.
    Set isLive = (row.Source = liveDemo)
    Set policyOk = isLive || ($ISOBJECT(p.%Get("policy")) && (p.%Get("policy").%ToJSON() = want.%ToJSON()))
    // The demo keeps the stop for another visit's in-patient movement that it had before v1.47 relaxed the shipped default.
    Set fm = p.%Get("further_messages")
    Set stopOk = $ISOBJECT(fm) && (##class(Shutter.Util.Json).Str(fm, "in_patient_movement") = "stop")
    Quit:(policyOk && stopOk && (row.Source '= seedPath)) $$$OK
    If 'isLive Do p.%Set("policy", want)
    If '$ISOBJECT(fm) || fm.%IsA("%Library.DynamicArray") Set fm = {} Do p.%Set("further_messages", fm)
    Set fm."in_patient_movement" = "stop"
    Quit ##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), $SELECT(isLive: liveDemo, 1: demoSource), "install", "", .version)
}

/// The live hospital's policy (CONTRACTS 4.4, v1.34; decided on 1 Nov 2026, "single cases at tier 2 wait for an
/// approval in the live hospital"): when the install is told SHUTTER_LIVE=1 (or on is 1), the shipped profile's policy for
/// tier 2, single chains becomes approval, so the demo's visitors always have a case to approve, and the profile is stored
/// with the seed's path and " (live hospital)" as its source, which the seed then leaves alone on a reinstall. A profile a
/// person saved (another source) is never touched. Returns a status; nothing changes when the setting already reads so.
ClassMethod LiveProfilePolicy(seedPath As %String, on As %Integer = -1) As %Status
{
    // -1: as the environment says (SHUTTER_LIVE=1); a test passes 0 or 1.
    If on = -1 Set on = ($SYSTEM.Util.GetEnviron("SHUTTER_LIVE") = "1")
    Quit:'on $$$OK
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Quit:'$ISOBJECT(row) $$$OK
    // The seed's profile, or the demo's (DemoProfilePolicy), or either with the live hospital's mark already on it.
    Set demoSource = seedPath _ " (demo)"
    Set liveSource = $SELECT((row.Source = demoSource) || (row.Source = demoSource _ " (live hospital)"): demoSource _ " (live hospital)", 1: seedPath _ " (live hospital)")
    Quit:((row.Source '= seedPath) && (row.Source '= demoSource) && (row.Source '= liveSource)) $$$OK
    Set p = ##class(Shutter.Util.Json).Parse(row.Json, .sc)
    Quit:('$ISOBJECT(p) || $$$ISERR(sc)) $$$OK
    Set policy = p.%Get("policy")
    Quit:'$ISOBJECT(policy) $$$OK
    Set tier2 = policy.%Get("2")
    If '$ISOBJECT(tier2) Set tier2 = {} Do policy.%Set("2", tier2)
    Quit:(##class(Shutter.Util.Json).Str(tier2, "single") = "approval") $$$OK
    Set tier2.single = "approval"
    Quit ##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), liveSource, "install", "", .version)
}

/// The Second Parser item follows its jar (CONTRACTS 6.7, v1.34): enabled in the production's definition when
/// shutter-pex.jar is installed (pex/build.sh), disabled when it is not, so a site without Java, or the replay edition, logs
/// no gateway errors and the evidence simply carries no second opinion. The item's classpath is its own business
/// (Shutter.Operation.SecondParser sets it at start), so nothing is written into the definition that a recompile would drop.
/// A running production is updated in place. Safe to run again; a production without the item is left alone. Returns
/// "ok: <enabled|disabled>" or "ERROR: ..."; from SQL, SELECT Shutter.Setup_SyncSecondParser().
ClassMethod SyncSecondParser(production As %String = "Shutter.Production") As %String [ SqlProc ]
{
    Set out = "ok: no item"
    Try {
        If (production = "") || (production = $CHAR(0)) Set production = "Shutter.Production"
        Set prod = ##class(Ens.Config.Production).%OpenId(production)
        If '$ISOBJECT(prod) Quit
        Set want = ##class(Shutter.Util.SecondParser).Available(), changed = 0
        For i = 1:1:prod.Items.Count() {
            Set item = prod.Items.GetAt(i)
            Continue:(item.Name '= ##class(Shutter.Util.SecondParser).#ITEM)
            If item.Enabled '= want Set item.Enabled = want, changed = 1
            Set out = "ok: " _ $SELECT(want: "enabled", 1: "disabled")
        }
        Quit:'changed
        Set sc = prod.%Save()
        If $$$ISERR(sc) Set out = "ERROR: " _ $SYSTEM.Status.GetErrorText(sc) Quit
        Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
        If $$$ISOK(sc) && (state = 1) && (name = production) Set sc = ##class(Ens.Director).UpdateProduction()
        If $$$ISERR(sc) Set out = "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
    } Catch ex {
        Set out = "ERROR: " _ ex.DisplayString()
    }
    Quit out
}

/// Commits the transaction IPM runs the install in, before the first call to Ens.Director. A lock released inside a
/// transaction stays held until the commit, so GetProductionStatus leaves this process holding ^Ens.Runtime("ConfigItem"),
/// and StartProduction then waits its 30 seconds and fails with ErrCanNotAcquireRuntimeLock: a load on a stock instance
/// stopped there. An image build never reaches this (SHUTTER_BUILD=1 starts nothing). InstallStatus restores the level
/// it was called at, so IPM's own commit still has a transaction to close.
ClassMethod LeaveTransaction() [ Private ]
{
    While $TLEVEL { TCOMMIT }
}

ClassMethod StartProduction() As %Status
{
    Set sc = $$$OK
    Set prod = "Shutter.Production"
    If '##class(%Dictionary.CompiledClass).%ExistsId(prod) Quit sc
    If ..ProductionName() '= prod Quit sc
    // The production definition (Ens.Config.Production) lives in the data database, which an upgraded container keeps from
    // before, while the class came with the image: compiling the class here runs its projection and brings the definition
    // up to the class, so items new in this image (the Second Parser of v1.34, say) exist before the production is updated.
    Set sc = $SYSTEM.OBJ.Compile(prod, "ck-d")
    Quit:$$$ISERR(sc) sc
    Set sc = ..ApplyDefaultSettings()
    Quit:$$$ISERR(sc) sc
    Try {
        Do ##class(Ens.Director).SetAutoStart(prod)
        // While an image is built (SHUTTER_BUILD=1) the instance stops right after: the production
        // starts with the container instead, so nothing is started here.
        If $SYSTEM.Util.GetEnviron("SHUTTER_BUILD") = "1" Quit
        Do ..LeaveTransaction()
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
/// with no feed of its own: "ADT In", "ADT to Downstream", "Downstream Out", "ADT to Records", "Records Out" and
/// "Scenario Player". A site adds its own feed items or uses the intake route. The definition is saved, and a running
/// production takes the change at once. A demo install leaves the items as the class defines them; a reinstall compiles
/// the class afresh (the items enabled again) and switches them off again.
ClassMethod DisableDemoItems() As %Status
{
    Set sc = $$$OK
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Production") Quit sc
    Try {
        Set prod = ##class(Ens.Config.Production).%OpenId("Shutter.Production", , .sc)
        If '$ISOBJECT(prod) Quit
        Set demoItems = $LISTBUILD("ADT In", "ADT to Downstream", "Downstream Out", "ADT to Records", "Records Out", "Scenario Player"), changed = 0
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
        Set refusal = ##class(Shutter.Util.SiteProduction).InstallRefusal(production) If refusal '= "" Set sc = $$$ERROR($$$GeneralError, refusal) Quit
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
/// the board, never the feed or the demo (ADT In, ADT to Downstream, Downstream Out, ADT to Records, Records Out,
/// Scenario Player). Case Intake and Case Intake Store are added once Shutter.Production defines them. A new recovery
/// item is listed here too.
Parameter INSTALLITEMS = "HL7 Index,Case Releaser,Receiver Watch,Escalation Mail,Case Workflow,Case Review,Case Question,Incident Workflow,Evidence Collector,Agent Conformance,Agent Encounter,Agent Impact,Agent Coordinator,Agent Board,Gate,Shutter Approvers,Shutter API,Verifier,Case Intake,Case Intake Store,Second Parser";

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
        Do ..LeaveTransaction()
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
/// idempotency keys older than a day, the text and .eml file of each escalation email escalationDays days after its
/// case closed, closed cases past the retention only when switched on). The retention task is
/// always made; the purge task only when purge is 1, keeping days days of messages, because a namespace-wide purge
/// belongs only in a namespace that holds nothing but Shutter. The defaults come from the environment of the process
/// that runs the install (the shell that runs zpm, not the running container): days from SHUTTER_MESSAGE_DAYS (90 when
/// unset or not a positive whole number), purge from SHUTTER_MESSAGE_PURGE (1 or 0; when unset, 1 on a demo instance
/// and 0 otherwise, read from ^Shutter.Config("demo")), escalationDays from SHUTTER_ESCALATION_DAYS (the message days
/// when unset or not a whole number; 0 keeps the texts). Each task is made once: on an instance that already has it,
/// change the days or remove the purge in the Task Manager (System Operation > Task Manager); this method leaves an
/// existing task as it is, whatever the arguments say (a retention task made before EscalationDays existed runs the
/// class default, 90). Returns "message purge created (N days)|exists|off; retention created (escalation texts N
/// days|kept)|exists", or "ERROR: ..." . From SQL with no arguments (SELECT Shutter.Setup_EnsureRetentionTasks()) the
/// defaults above apply.
ClassMethod EnsureRetentionTasks(ns As %String = "", days As %String = "", purge As %String = "", escalationDays As %String = "") As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("%Admin_Task", "USE") && '$SYSTEM.Security.Check("Shutter_Operate", "USE") Quit "Shutter_Operate is required"
    // SQL hands an empty argument to a procedure as $CHAR(0).
    If ns = $CHAR(0) Set ns = ""
    If days = $CHAR(0) Set days = ""
    If purge = $CHAR(0) Set purge = ""
    If escalationDays = $CHAR(0) Set escalationDays = ""
    If ns = "" Set ns = $NAMESPACE
    Set days = ..MessageDays(days), purge = ..MessagePurge(purge), escalationDays = ..EscalationDays(escalationDays, days)
    Set exists = (..TaskId("Shutter message purge") '= ""), made = 0
    If purge && 'exists {
        Set sc = ..EnsureTask("Shutter message purge", ns, "Ens.Util.Tasks.Purge", "Shutter: purge messages, logs and traces older than " _ days _ " days, sessions kept whole", $LISTBUILD("NumberOfDaysToKeep", days, "BodiesToo", 1, "KeepIntegrity", 1, "TypesToPurge", "all"), 9600, .made)
        If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
        If made Set exists = 1, ^|ns|Shutter.Config("messageDays") = days
    }
    // The install's record, for a Doctor report by a caller without access to the Task Manager.
    Set ^|ns|Shutter.Config("purgeTask") = exists
    Set out = "message purge " _ $SELECT(made: "created (" _ days _ " days)", exists: "exists", 1: "off")
    Set texts = $SELECT(escalationDays > 0: "escalation emails' text " _ escalationDays _ " days after their case closed, ", 1: "")
    Set sc = ..EnsureTask("Shutter retention", ns, "Shutter.Util.RetentionTask", "Shutter: idempotency keys older than a day, " _ texts _ "and closed cases past the retention when switched on", $LISTBUILD("RetentionDays", 30, "PurgeClosedCases", 0, "EscalationDays", escalationDays), 9900, .made)
    If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
    // The install's record, for a Doctor report by a caller without access to the Task Manager.
    If made Set ^|ns|Shutter.Config("escalationDays") = escalationDays
    Quit out _ "; retention " _ $SELECT(made: "created (escalation texts " _ $SELECT(escalationDays > 0: escalationDays _ " days", 1: "kept") _ ")", 1: "exists")
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

/// The days after a case closes before its escalation emails' text and .eml files go: the argument, else
/// SHUTTER_ESCALATION_DAYS, else the message days, so one knob governs both by default; 0 keeps the texts; a value that
/// is not a whole number counts as unset.
ClassMethod EscalationDays(days As %String = "", messageDays As %Integer = 90) As %Integer [ Private ]
{
    Set days = $ZSTRIP(days, "<>W")
    If days = "" Set days = $ZSTRIP($SYSTEM.Util.GetEnviron("SHUTTER_ESCALATION_DAYS"), "<>W")
    If days '?1.N Quit +messageDays
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

/// Empty Shutter's own tables (cases and everything attached to them, their escalation emails and the .eml files of
/// those rows included, the precedents and board leads that name them, recordings excepted) on a demo instance, reset
/// the counters so the next case is C-000001 again, and stamp ^Shutter.Config("resetAt") with the time of the purge, as a
/// scenario reset does, so nothing from before it is read as this instance's history. Refused elsewhere. Returns the
/// number of tables emptied or the error.
ClassMethod PurgeStore() As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("Shutter_Scenarios", "USE") Quit "Shutter_Scenarios is required"
    If '$GET(^Shutter.Config("demo")) Quit "ERROR: not a demo instance"
    Set n = 0
    // The .eml files of the escalations about to go, by the paths their rows hold: never the folder, which may hold
    // another instance's files.
    Set emails = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Seq, Result FROM Shutter_Store.Escalation WHERE Transport = 'file'")
    While emails.%Next() { Do ##class(Shutter.Store.Escalation).RemoveFile(emails.%Get("Result"), emails.%Get("Seq")) }
    For cls = "Shutter.Store.CaseToken", "Shutter.Store.ChainItem", "Shutter.Store.Chain", "Shutter.Store.IncidentEvent", "Shutter.Store.Incident", "Shutter.Store.Verification", "Shutter.Store.ExecutionAttempt", "Shutter.Store.Approval", "Shutter.Store.Rehearsal", "Shutter.Store.GateDecision", "Shutter.Store.Plan", "Shutter.Store.Finding", "Shutter.Store.CaseQuestion", "Shutter.Store.AgentRun", "Shutter.Store.SnapshotItem", "Shutter.Store.Snapshot", "Shutter.Store.CaseEvent", "Shutter.Store.Escalation", "Shutter.Store.Case", "Shutter.Store.Precedent", "Shutter.Store.BoardLead", "Shutter.Store.ReviewAnnotation", "Shutter.Store.Review", "Shutter.Store.Idempotency", "Shutter.Bridge.ToolCall", "Shutter.Store.OutageEvent", "Shutter.Store.Outage", "Shutter.Store.ReceiverReading" {
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
    // The counters start again, so a new case may carry a purged case's id: the reset stamp keeps a lead begun before
    // the purge from being followed, and the evidence collector from reading older message-store events.
    Set ^Shutter.Config("resetAt") = ##class(Shutter.Util.Time).NowUTC()
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
ClassMethod Doctor(refresh As %Boolean = 0) As %String [ SqlProc ]
{
    Set r = {}
    Set r.namespace = $NAMESPACE
    Set r.version = $GET(^Shutter.Config("version"))
    Set r."installed_at" = $GET(^Shutter.Config("installedAt"))
    Do r.%Set("demo", ''$GET(^Shutter.Config("demo")), "boolean")
    Set r.mode = $GET(^Shutter.Config("mode"))
    Set r."adt_in" = $GET(^Shutter.Config("adtIn"))
    Do r.%Set("interoperability", ''##class(%EnsembleMgr).IsEnsembleNamespace($NAMESPACE), "boolean")
    // Whether IANA zones beyond UTC, Europe/London and fixed offsets can be read (Embedded Python's zoneinfo, v1.30).
    Do r.%Set("python_zoneinfo", ''##class(Shutter.Util.Time).PythonZones(), "boolean")
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
    // The edition in one word (v1.35): aihub (the package and the module), core (neither: the replay edition), or broken when
    // one is there without the other, which an install should never leave.
    Set r.edition = $SELECT(r."ai_hub_present" && r."aihub_runner": "aihub", 'r."ai_hub_present" && 'r."aihub_runner": "core", r."ai_hub_present": "broken: AI Hub is present but the aihub module is not loaded", 1: "broken: the aihub module is loaded on an image without AI Hub")
    // The API mimic's switch as set (tests/mock), "" when off; it counts on a demo instance only (MockConfig).
    Set r."mock_config" = $GET(^Shutter.Config("aihub", "mock"))
    // The provider the record names, and whether the instance still holds what it names (v1.39): the wallet secret and
    // the Config Store configuration, each true or false, or null where its class is absent (the core edition) or this
    // process may not read it (the wallet's Shutter_Secrets, the Config Store's %Admin_ConfigStore: an operator or a
    // judge without them is told nothing, not "gone"). A recorded provider with a missing secret is what a container
    // recreated on the same volume shows until the production's next start writes the key again (ProviderNeedsRewrite).
    Set r.provider = $GET(^Shutter.Config("aihub", "provider"))
    Set state = ..WalletSecretState()
    If state = "" { Do r.%Set("wallet_secret", "", "null") } Else { Do r.%Set("wallet_secret", state, "boolean") }
    Set state = ..ProviderConfigState()
    If state = "" { Do r.%Set("provider_config", "", "null") } Else { Do r.%Set("provider_config", state, "boolean") }
    &sql(SELECT COUNT(*) INTO :members FROM Shutter_Store.BoardMember WHERE Enabled = 1)
    Set r."board_members" = +members
    &sql(SELECT COUNT(*) INTO :records FROM Shutter_Bridge.Record)
    Set r.recordings = +records
    &sql(SELECT COUNT(*) INTO :cases FROM Shutter_Store."Case")
    Set r.cases = +cases
    // The cases still in a working state, and the quiet minutes after which an approver may abandon one (CONTRACTS 5, 12).
    &sql(SELECT COUNT(*) INTO :working FROM Shutter_Store."Case" WHERE State NOT IN ('resolved', 'blocked', 'escalated', 'failed'))
    Set r."working_cases" = +working, r."abandon_after_minutes" = ##class(Shutter.Store.Case).AbandonAfterMinutes()
    // The stored credentials against the users they name (v1.38): the cache, which the production keeps fresh; a caller
    // that may write may refresh it. Never a reason for the Doctor to fail: a request with no roles only reads.
    Try {
        Set checks = ..CredentialChecks(refresh, .cstate), allOk = 1
        Set cit = checks.%GetIterator()
        While cit.%GetNext(, .check) { If 'check.ok Set allOk = 0 }
    } Catch ex {
        Set checks = [], allOk = 1, cstate = "error: " _ ex.DisplayString()
    }
    Set r.credentials = checks, r."credentials_state" = cstate
    Do r.%Set("credentials_ok", allOk, "boolean")
    Set r."credentials_checked_at" = $GET(^Shutter.Health("credentials", "iso"))
    // The public demo's portal (v1.39): whether the production's start hardened it (SHUTTER_DEMO_PORTAL), and when; the
    // record alone, since reading the portal's own state (PortalState) needs %Admin_Secure. The latest start's errors when
    // its hardening failed (the stamp cleared then), or "".
    Do r.%Set("portal_hardened", $GET(^Shutter.Config("portalHardened")) '= "", "boolean")
    Set r."portal_hardened_at" = $GET(^Shutter.Config("portalHardened"))
    Set r."portal_hardening_errors" = $GET(^Shutter.Config("portalHardeningErrors"))
    // The pieces of the builds since 25 Oct (CONTRACTS 12, v1.31), so a fresh install and an upgrade show the same: every item
    // of INSTALLITEMS in the production and enabled, the gate's policy version, the catalogue's entries, the records namespace
    // of a demo install, the index's adapter, the questions.
    Set missing = [], disabled = []
    For i = 1:1:$LENGTH(..#INSTALLITEMS, ",") {
        Set item = $PIECE(..#INSTALLITEMS, ",", i), enabled = ""
        &sql(SELECT Enabled INTO :enabled FROM Ens_Config.Item WHERE Production = :prod AND Name = :item)
        // The Second Parser is off by design where its jar is not installed (v1.34): not a disabled item then.
        If SQLCODE '= 0 { Do missing.%Push(item) } ElseIf 'enabled { If (item '= "Second Parser") || ##class(Shutter.Util.SecondParser).Available() Do disabled.%Push(item) }
    }
    Set r."missing_items" = missing, r."disabled_items" = disabled
    Set r."gate_policy_version" = $PARAMETER("Shutter.Operation.Gate", "POLICYVERSION")
    Set entries = 0, ids = ""
    Set ers = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT EntryId FROM Shutter_Catalogue.Entry ORDER BY LENGTH(EntryId), EntryId")
    While ers.%Next() { Set entries = entries + 1, ids = ids _ $SELECT(ids = "": "", 1: ",") _ ers.%Get("EntryId") }
    Set r."catalogue_entries" = entries, r."catalogue_ids" = ids
    Do r.%Set("records_namespace", ''##class(%SYS.Namespace).Exists("RECORDS"), "boolean")
    Set r."index_adapter" = $PARAMETER("Shutter.Index.Indexer", "ADAPTER")
    &sql(SELECT COUNT(*) INTO :questions FROM Shutter_Store.CaseQuestion)
    Set r.questions = +questions
    // The HL7 schemas this namespace holds against those the production's services and the recent messages name (v1.32).
    Set r."hl7_schemas" = ##class(Shutter.Util.Schemas).Report()
    // Each watched namespace, read there (v1.42), and the receivers whose connector item a site has yet to add.
    Set r."watched_namespaces" = ##class(Shutter.Util.Onboard).Watched()
    Set r."receivers_without_item" = ##class(Shutter.Util.Onboard).ReceiversWithoutItem()
    // The receivers' outages (CONTRACTS 17): what each watched item's settings read, the set gate's and the hold's lines when
    // the build has them, and the blocks a profile declares that no part of this build acts on.
    Try { Set r.outages = ..OutageDoctor() } Catch ex { Set r.outages = {"error": (ex.DisplayString())} }
    // The hold for a schema not loaded (v1.34, "prevent failures"): the profile's setting and the held cases by category.
    Do r.%Set("prevent_failures", ##class(Shutter.Store.SiteProfile).PreventFailures(), "boolean")
    Set r."held_messages" = ##class(Shutter.Util.Schemas).Held()
    // The live hospital's player, when the watched hospital has one (v1.34).
    Set r.live = ..LiveStatus()
    // The day's model budget and what the live runs spent today (v1.34).
    Set r.budget = ##class(Shutter.Util.Budget).Status()
    // The bound on one model call (v1.35): the provider's request timeout the runner sets.
    Set r."provider_timeout_seconds" = ..ProviderTimeoutSeconds()
    // The newest run that reached a model (v1.35), beside the configured mode: what was last observed.
    Set last = ##class(Shutter.Store.AgentRun).LastLive()
    If $ISOBJECT(last) { Set r."last_live_run" = last } Else { Do r.%Set("last_live_run", "", "null") }
    // The Case Releaser's sweep (8.1, v1.35): when it last ran, and its last run with candidates.
    Try { Set r."release_sweep" = ##class(Shutter.Operation.Releaser).Status() } Catch ex { Set r."release_sweep" = {"error": (ex.DisplayString())} }
    // The Second Parser (v1.34): the jar, and whether the Java gateway answers a probe.
    Set r."second_parser" = ##class(Shutter.Util.SecondParser).Status()
    Set r.license = ##class(%DynamicObject).%FromJSON(..LicenseInfo())
    // Before the switch to %SYS below: New $NAMESPACE inside a Try lasts to the end of the method.
    Set r."precedent_days" = ##class(Shutter.Store.Precedent).Days()
    Set r."storm_cooldown_minutes" = ..StormCooldownMinutes()
    Set r."lead_window_seconds" = ##class(Shutter.Store.BoardLead).WindowSeconds()
    // The publisher (15, v1.35): whether this build has it, its web application, and today's calls.
    Set pub = {}
    Do pub.%Set("available", ##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Publish.Service"), "boolean")
    Do pub.%Set("webapp", ''$GET(^Shutter.Config("webapp", "/mcp/shutter")), "boolean")
    Try { Set pub."calls_today" = ##class(Shutter.Store.PublishCall).CountSince($EXTRACT(##class(Shutter.Util.Time).NowUTC(), 1, 10) _ "T00:00:00Z") } Catch ex { Set pub."calls_today" = 0 }
    Set r.publish = pub
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Do r.%Set("api_webapp", ''##class(Security.Applications).Exists("/api/shutter"), "boolean")
        Do r.%Set("ui_webapp", ''##class(Security.Applications).Exists("/shutter"), "boolean")
        Do r.%Set("wards_webapp", ''##class(Security.Applications).Exists("/downstream/api"), "boolean")
        Do r.%Set("records_webapp", ''##class(Security.Applications).Exists("/records/api"), "boolean")
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
        // The retention task's escalation days (the escalation emails' text goes that long after the case closed; 0
        // keeps it): the task's setting, or the class default, 90, which a task made before the setting existed runs.
        Set taskId = ..TaskId("Shutter retention")
        If taskId '= "" {
            Set r."escalation_days" = 90
            Set task = ##class(%SYS.Task).%OpenId(taskId)
            If $ISOBJECT(task) && $LISTVALID(task.Settings) {
                For i = 1:2:$LISTLENGTH(task.Settings) {
                    If $LISTGET(task.Settings, i) = "EscalationDays" Set r."escalation_days" = +$LISTGET(task.Settings, i + 1)
                }
            }
        }
        Set r."webapps_checked" = "live"
    } Catch ex {
        // A caller without %SYS access gets what the install recorded.
        Do r.%Set("api_webapp", ''$GET(^Shutter.Config("webapp", "/api/shutter")), "boolean")
        Do r.%Set("ui_webapp", ''$GET(^Shutter.Config("webapp", "/shutter")), "boolean")
        Do r.%Set("wards_webapp", ''$GET(^Shutter.Config("webapp", "/downstream/api")), "boolean")
        Do r.%Set("records_webapp", ''$GET(^Shutter.Config("webapp", "/records/api")), "boolean")
        Do r.%Set("purge_task", ''$GET(^Shutter.Config("purgeTask")), "boolean")
        If $GET(^Shutter.Config("purgeTask")) && ($GET(^Shutter.Config("messageDays")) '= "") Set r."message_days" = +^Shutter.Config("messageDays")
        If $GET(^Shutter.Config("escalationDays")) '= "" Set r."escalation_days" = +^Shutter.Config("escalationDays")
        Set r."webapps_checked" = "install record"
    }
    Quit r.%ToJSON()
}

/// The Doctor's outage lines (CONTRACTS 17): { open, by_state, receivers: [ per watched item ], policy_version,
/// set_policy_version, hold, approvers_missing, routers_validating, alert_on_error_off, declared_not_in_build }. receivers is
/// empty on a profile with no watch block. The watched items' settings come from the Receiver Watch's stored reading, which its
/// production job wrote; SaveReplies, the routers and AlertOnError are read in the watched namespace, and where this process
/// may not switch there they read unknown with the reason. set_policy_version and hold are "" when the build has no set gate or
/// no hold.
ClassMethod OutageDoctor() As %DynamicObject
{
    Set out = {}
    Set open = 0, states = {}
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT State, COUNT(*) AS N FROM Shutter_Store.Outage GROUP BY State")
    While rs.%Next() {
        Do states.%Set(rs.%Get("State"), +rs.%Get("N"))
        If rs.%Get("State") '= "closed" Set open = open + rs.%Get("N")
    }
    Set out.open = open, out."by_state" = states
    Set receivers = [], missing = [], namespaces = ""
    Set iter = ##class(Shutter.Store.SiteProfile).WatchedReceivers().%GetIterator()
    While iter.%GetNext(.i, .entry) {
        Set name = entry.%Get("name"), watch = entry.%Get("watch")
        Set ns = watch.%Get("namespace"), item = watch.%Get("item")
        Set reading = ##class(Shutter.Store.ReceiverReading).Last(name)
        Set line = {"receiver": (name), "namespace": (ns), "item": (item), "reading": (reading.reading)}
        For key = "checkedAt", "defCharEncoding", "replyCodeActions", "replyCodeActionsStock", "failureTimeout", "retry", "getReply" {
            Do line.%Set(key, reading.%Get(key), $CASE(reading.%GetTypeOf(key), "null": "null", "boolean": "boolean", "number": "number", : "string"))
        }
        If (reading.%GetTypeOf("replyCodeActionsStock") = "boolean") && 'reading.replyCodeActionsStock && (##class(Shutter.API.Outages).S(reading, "replyCodeActions") '= "") {
            Set line."reply_actions_note" = "this operation's reply actions are the site's own: what an AE, AR or timeout does here follows this string"
        }
        Set line.settingSources = reading.settingSources
        Set save = ..WatchedSetting(ns, item, "SaveReplies")
        Set line.saveReplies = save.value, line.saveRepliesSource = save.source
        If save.why '= "" Set line.saveRepliesWhy = save.why
        Do receivers.%Push(line)
        If ##class(Shutter.Store.Outage).ApproversOf(entry).%Size() = 0 Do missing.%Push(name)
        If (ns '= "") && '$LISTFIND(namespaces, ns) Set namespaces = namespaces _ $LISTBUILD(ns)
    }
    Set out.receivers = receivers, out."approvers_missing" = missing
    Set out."policy_version" = $PARAMETER("Shutter.Operation.Gate", "POLICYVERSION")
    Set out."set_policy_version" = $SELECT(##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Util.ResendSet"): $PARAMETER("Shutter.Util.ResendSet", "SETPOLICYVERSION"), 1: "")
    Set out.hold = ..HoldLine()
    Set routers = [], quiet = []
    Set ptr = 0
    While $LISTNEXT(namespaces, ptr, ns) { Do ..NamespaceLines(ns, routers, quiet) }
    Set out."routers_validating" = routers, out."alert_on_error_off" = quiet
    Set out."declared_not_in_build" = ..DeclaredNotInBuild()
    Quit out
}

/// One setting of a watched item through the shared read, or unknown with the reason when it can't be read here.
ClassMethod WatchedSetting(ns As %String, item As %String, setting As %String) As %DynamicObject
{
    Try {
        Set answer = ##class(Shutter.Util.EngineRead).ItemSetting(ns, item, setting, ##class(Shutter.Util.EngineScope).IsStockTcp(ns, item))
    } Catch ex {
        Set answer = {"source": "unknown", "value": "", "why": (ex.DisplayString())}
    }
    Quit answer
}

/// The hold's line, through the hold's own store when this build has it: "" otherwise, so nothing claims a hold that isn't there.
ClassMethod HoldLine() As %DynamicAbstractObject
{
    Set class = "Shutter.Store.HoldEntry"
    If '##class(%Dictionary.CompiledClass).%ExistsId(class) Quit ""
    If '##class(%Dictionary.CompiledMethod).%ExistsId(class _ "||DoctorLine") Quit {"error": "the hold's store has no DoctorLine"}
    Try {
        Set line = $CLASSMETHOD(class, "DoctorLine")
    } Catch ex {
        Set line = {"error": (ex.DisplayString())}
    }
    Quit line
}

/// In one watched namespace: the HL7 routers with validation on, and the operations and routers with AlertOnError off, so a
/// failure the intake never hears is named. Where the namespace can't be read here, one entry says so.
ClassMethod NamespaceLines(ns As %String, routers As %DynamicArray, quiet As %DynamicArray)
{
    Try {
        New $NAMESPACE
        Set $NAMESPACE = ns
        Set production = ##class(Ens.Director).GetActiveProductionName()
        If production = "" Do quiet.%Push({"namespace": (ns), "unknown": "no current production"}) Quit
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Name, ClassName FROM Ens_Config.Item WHERE Production = ? AND Enabled = 1", production)
        While rs.%Next() {
            Set name = rs.%Get("Name"), class = rs.%Get("ClassName")
            Continue:'##class(%Dictionary.CompiledClass).%ExistsId(class)
            Set router = $CLASSMETHOD(class, "%Extends", "EnsLib.HL7.MsgRouter.RoutingEngine")
            Continue:'router&&'$CLASSMETHOD(class, "%Extends", "Ens.BusinessOperation")
            If router {
                Set sc = $$$OK, v = ##class(Ens.Director).GetItemSettingValue(name, "Host", "Validation", .sc)
                If $$$ISOK(sc) && (v '= "") Do routers.%Push({"namespace": (ns), "item": (name), "validation": (v)})
            }
            Set sc = $$$OK, v = ##class(Ens.Director).GetItemSettingValue(name, "Host", "AlertOnError", .sc)
            If $$$ISOK(sc) && 'v Do quiet.%Push({"namespace": (ns), "item": (name)})
        }
    } Catch ex {
        Do quiet.%Push({"namespace": (ns), "unknown": (ex.DisplayString())})
    }
}

/// The receivers whose profile entry declares engine_resend, hold or mail, each with whether this build has the part that acts
/// on it: "declared; not in this build" when it doesn't, so a block never appears to enable recovery.
ClassMethod DeclaredNotInBuild(list As %DynamicArray = "") As %DynamicArray
{
    Set out = []
    If '$ISOBJECT(list) Set list = ##class(Shutter.Store.SiteProfile).Current().%Get("receivers")
    If '$ISOBJECT(list) Quit out
    Set iter = list.%GetIterator()
    While iter.%GetNext(.i, .r) {
        Continue:'$ISOBJECT(r)
        For block = "engine_resend", "hold", "mail" {
            Continue:'r.%IsDefined(block)
            Continue:(block = "engine_resend")&&'r.%Get(block)
            Set class = $CASE(block, "engine_resend": "Shutter.Operation.EngineResend", "hold": "Shutter.Store.HoldEntry", : "Shutter.Operation.OutageMail")
            Set here = ##class(%Dictionary.CompiledClass).%ExistsId(class)
            Do out.%Push({"receiver": (r.%Get("name")), "block": (block), "state": ($SELECT(here: "declared; in this build", 1: "declared; not in this build"))})
        }
    }
    Quit out
}

/// The live hospital's status as its player writes it in the hospital's namespace (CONTRACTS 4.4, v1.34): {enabled,
/// every_minutes, scenarios, last_played, next, last_ordinary}; {enabled: false} when there is no hospital or no player.
ClassMethod LiveStatus() As %DynamicObject
{
    Set s = {}
    Do s.%Set("enabled", 0, "boolean")
    Try {
        Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
        Quit:(hospital = "")
        Set text = $GET(^|hospital|Hospital.Live("status"))
        If text '= "" Set s = ##class(%DynamicObject).%FromJSON(text)
        Do s.%Set("enabled", ''$GET(^|hospital|Hospital.Config("live")), "boolean")
        // The storm (4.4, v1.35): the player's record as it stands (the status above is rewritten only after each call,
        // and a storm is played within one), a press the player has not picked up yet before it, with Shutter's own view
        // of it: the incident and the case counts.
        Set record = $GET(^|hospital|Hospital.Live("storm"))
        If record '= "" Set s.storm = ##class(%DynamicObject).%FromJSON(record)
        Set pending = $GET(^Shutter.Live("storm", "request"))
        If pending '= "" Set s.storm = ##class(%DynamicObject).%FromJSON(pending)
        Set storm = s.%Get("storm")
        If $ISOBJECT(storm) Do ..StormCounts(storm)
    } Catch ex {
    }
    Quit s
}

/// Adds to a storm record what Shutter's store knows: the incident opened for Downstream Out since the press (incidentId
/// and incidentState, null when none yet), the storm's cases and how many resolved, and when the cooldown ends.
ClassMethod StormCounts(storm As %DynamicObject)
{
    Try {
        Set since = storm.%Get("startedAt")
        Set cases = 0, resolved = 0
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N, SUM(CASE WHEN State = 'resolved' THEN 1 ELSE 0 END) AS R FROM Shutter_Store.""Case"" WHERE Scenario = 'storm' AND OpenedAt >= ?", since)
        If rs.%Next() Set cases = +rs.%Get("N"), resolved = +rs.%Get("R")
        Set storm.cases = cases, storm.resolved = resolved
        // The incident the storm's cases joined: one the detector opened for them, or one already open for the receiver.
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 i.IncidentId, i.State FROM Shutter_Store.""Case"" c JOIN Shutter_Store.Incident i ON c.Incident = i.ID WHERE c.Scenario = 'storm' AND c.OpenedAt >= ? ORDER BY c.ID DESC", since)
        If rs.%Next() {
            Set storm.incidentId = rs.%Get("IncidentId"), storm.incidentState = rs.%Get("State")
        } Else {
            Do storm.%Set("incidentId", "", "null")
        }
        If since '= "" {
            Set elapsed = ##class(Shutter.Util.Time).SecondsBetween(since, ##class(Shutter.Util.Time).NowUTC())
            Set storm.cooldownUntil = ##class(Shutter.Util.Time).FromNow((..StormCooldownMinutes() * 60) - elapsed)
        }
    } Catch ex {
    }
}

/// Minutes between storms, measured from a storm's start: ^Shutter.Config("stormCooldownMinutes"), 0 to 1440, 10 by default.
ClassMethod StormCooldownMinutes() As %Integer
{
    Set m = $GET(^Shutter.Config("stormCooldownMinutes"))
    If (m '? 1.N) || (m > 1440) Quit 10
    Quit +m
}

/// Why a storm may not be pressed now, or "" when it may (CONTRACTS 4.4): the live hospital off; a storm still playing
/// (any state but done or failed); or the cooldown since the last storm's start. The answer carries the reply's status,
/// error and detail, with the storm's id, start and end, or the cooldown's end and the seconds left.
ClassMethod StormRefusal(liveOn As %Boolean, stormJson As %String, cooldownMinutes As %Integer = 10) As %DynamicObject
{
    If 'liveOn Quit {"status": "409 Conflict", "error": "live_off", "detail": "The live hospital is off; the storm plays in it"}
    Set storm = ##class(Shutter.Util.Json).Parse(stormJson, .sc)
    If '$ISOBJECT(storm) Quit ""
    Set state = storm.%Get("state"), endsAt = storm.%Get("endsAt")
    // A storm still marked as playing after its span is over was cut off (the player stopped): it blocks nothing.
    Set stale = (endsAt '= "") && (##class(Shutter.Util.Time).SecondsBetween(endsAt, ##class(Shutter.Util.Time).NowUTC()) >= 0)
    If (state '= "") && (state '= "done") && (state '= "failed") && 'stale {
        Quit {"status": "409 Conflict", "error": "storm_in_progress", "detail": ("Storm " _ storm.%Get("stormId") _ " is " _ state), "stormId": (storm.%Get("stormId")), "startedAt": (storm.%Get("startedAt")), "endsAt": (endsAt), "state": (state)}
    }
    Set started = storm.%Get("startedAt")
    If started '= "" {
        Set elapsed = ##class(Shutter.Util.Time).SecondsBetween(started, ##class(Shutter.Util.Time).NowUTC())
        Set left = (cooldownMinutes * 60) - elapsed
        If left > 0 Quit {"status": "409 Conflict", "error": "cooldown", "detail": ("The last storm started " _ elapsed _ " s ago; the next may start in " _ left _ " s"), "until": (##class(Shutter.Util.Time).FromNow(left)), "retryAfterSeconds": (left)}
    }
    Quit ""
}

/// Import a site's HL7 schema (an .xml export) through IRIS's own importer, for an approver (CONTRACTS 12, v1.32). Returns
/// JSON: {ok, category, loaded: [...], error}.
ClassMethod ImportSchema(path As %String) As %String [ SqlProc ]
{
    Set out = {}
    If '$SYSTEM.Security.Check("Shutter_Approve", "USE") {
        Do out.%Set("ok", 0, "boolean") Set out.error = "Shutter_Approve is required"
        Quit out.%ToJSON()
    }
    Set sc = ##class(Shutter.Util.Schemas).Import(path, .category)
    Do out.%Set("ok", $$$ISOK(sc), "boolean")
    Set out.category = category
    If $$$ISERR(sc) Set out.error = $SYSTEM.Status.GetErrorText(sc)
    Set out.loaded = ##class(Shutter.Util.Schemas).Categories()
    Quit out.%ToJSON()
}

// ---- onboarding a namespace (Shutter.Util.Onboard; INSTALL 9, CONTRACTS 11.1) ----

/// What onboarding a namespace would do, changing nothing: JSON. options is a JSON object or empty (Shutter.Util.Onboard.Plan).
ClassMethod OnboardPlan(ns As %String, options As %String = "") As %String [ SqlProc ]
{
    Set o = ##class(Shutter.Util.Onboard).Options(options, .refused)
    If refused '= "" Quit refused
    Quit ##class(Shutter.Util.Onboard).Plan(ns, o).%ToJSON()
}

/// Carries out that plan and answers what changed. Idempotent; never stops a production. Needs %Admin_Manage.
ClassMethod OnboardApply(ns As %String, options As %String = "") As %String [ SqlProc ]
{
    Set o = ##class(Shutter.Util.Onboard).Options(options, .refused)
    If refused '= "" Quit refused
    Quit ##class(Shutter.Util.Onboard).Apply(ns, o).%ToJSON()
}

/// A marked test failure through the namespace's forwarder settings: a case opens, and nothing goes to a receiver.
ClassMethod OnboardTest(ns As %String) As %String [ SqlProc ]
{
    Quit ##class(Shutter.Util.Onboard).Test(ns).%ToJSON()
}

/// Takes off what the apply added, and says what stays. Needs %Admin_Manage.
ClassMethod OnboardRemove(ns As %String, options As %String = "") As %String [ SqlProc ]
{
    Set o = ##class(Shutter.Util.Onboard).Options(options, .refused)
    If refused '= "" Quit refused
    Quit ##class(Shutter.Util.Onboard).Remove(ns, o).%ToJSON()
}

/// A connector item for a receiver the site profile gives an API, kept across upgrades. Needs %Admin_Manage.
ClassMethod OnboardReceiverItem(name As %String, host As %String = "", port As %String = "", credential As %String = "", ssl As %String = "") As %String [ SqlProc ]
{
    If '$SYSTEM.Security.Check("%Admin_Manage", "USE") Quit "{""ok"":false,""error"":""This changes Shutter's production: it needs %Admin_Manage""}"
    Quit ##class(Shutter.Util.Onboard).ReceiverItem(name, host, port, credential, ssl).%ToJSON()
}

/// The forwarder's sign-in for a namespace, in a terminal: with no password it asks for one with the echo off, and it never
/// prints it. Not an SQL procedure, so no password passes through a statement. Makes the user when it does not exist.
ClassMethod OnboardCredential(ns As %String, user As %String = "shutter-fwd", password As %String = "", credential As %String = "")
{
    If password = "" {
        Write "Password for ", user, ": "
        Use $PRINCIPAL:(:"+S")
        Read password
        Use $PRINCIPAL:(:"-S")
        Write !
    }
    Write ##class(Shutter.Util.Onboard).Credential(ns, user, password, credential).%ToJSON(), !
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
        // The publisher (15, v1.35): its web application, where IRIS's MCP gateway and the publisher's classes are compiled.
        Set out.publish = ..EnsurePublishApp($NAMESPACE)
        Set ^Shutter.Config("aihub", "installedAt") = ##class(Shutter.Util.Time).NowUTC()
        Set ^Shutter.Config("aihub", "root") = root
    } Catch ex {
        Set out.error = ex.DisplayString()
    }
    Quit out.%ToJSON()
}

/// The publisher's web application /mcp/shutter (CONTRACTS 15, v1.35): password authentication, dispatch to
/// Shutter.Publish.Service (IRIS's MCP gateway with the publisher's tools), the resource Shutter_Publish on the
/// application too. Made only where %AI.MCP.Service and the publisher's classes are compiled (the AI Hub build); elsewhere
/// it says so and makes nothing. Returns a short status.
ClassMethod EnsurePublishApp(ns As %String = "") As %String
{
    If ns = "" Set ns = $NAMESPACE
    If '##class(%Dictionary.CompiledClass).%ExistsId("%AI.MCP.Service") Quit "no MCP gateway on this build (%AI.MCP.Service)"
    If '##class(%Dictionary.CompiledClass).%ExistsId("Shutter.Publish.Service") Quit "the publisher's classes are not compiled"
    Set out = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = "%SYS"
        Set props("NameSpace") = ns
        Set props("Description") = "Shutter publisher: read-only MCP tools"
        Set props("Enabled") = 1
        // Password authentication: iris-mcp-server passes the MCP client's HTTP Basic credentials through, and the engine signs
        // the caller in; the resource on the application and the service's own check both require Shutter_Publish.
        Set props("AutheEnabled") = 32
        Set props("DispatchClass") = "Shutter.Publish.Service"
        Set props("Resource") = "Shutter_Publish"
        Set props("MatchRoles") = ""
        // An MCP Server application (Type bit 4, with the CSP/REST bit): what the portal's "Edit MCP Server" page makes, and
        // what iris-mcp-server trusts; a plain web application at the same path fails its identity check.
        Set props("Type") = 18
        If ##class(Security.Applications).Exists("/mcp/shutter") {
            Set sc = ##class(Security.Applications).Modify("/mcp/shutter", .props)
            Set out = "updated"
        } Else {
            Set sc = ##class(Security.Applications).Create("/mcp/shutter", .props)
            Set out = "created"
        }
        If $$$ISERR(sc) Set out = "failed: " _ $SYSTEM.Status.GetErrorText(sc) Quit
        Set ^|ns|Shutter.Config("webapp", "/mcp/shutter") = 1
    } Catch ex {
        Set out = "failed: " _ ex.DisplayString()
    }
    Quit out _ " /mcp/shutter"
}

/// InstallAIHub as a %Status: what the aihub module's manifest invokes (the Invoke checks the status, so an install
/// that stopped at an error stops the load, and the image build with it). Writes InstallAIHub's JSON, which holds no
/// secret. What fails the install: an error InstallAIHub caught, and a key in the environment (ANTHROPIC_API_KEY) whose
/// provider could not be configured (a provider line not starting "ok"). A knowledge base that did not build, and an
/// environment with no key (the agents replay), are reported there and do not fail it.
ClassMethod InstallAIHubStatus(root As %String = "") As %Status
{
    Set sc = $$$OK
    Try {
        Set json = ..InstallAIHub(root)
        Write !, "aihub install: ", json, !
        Set out = ##class(%DynamicObject).%FromJSON(json)
        If out.error '= "" Set sc = $$$ERROR($$$GeneralError, "The aihub install: " _ out.error)
        If $$$ISOK(sc) && ($SYSTEM.Util.GetEnviron("ANTHROPIC_API_KEY") '= "") && ($EXTRACT(out.provider, 1, 2) '= "ok") Set sc = $$$ERROR($$$GeneralError, "The aihub install: the provider was not configured from ANTHROPIC_API_KEY: " _ out.provider)
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
/// account needs a role that grants Shutter_Secrets. Public so that a test makes the collection as ConfigureProvider does.
ClassMethod EnsureSecretResource() As %Status
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
/// to decide (live when a provider is configured, else replay). Returns what applies. Record is refused while the
/// API mimic is on (MockConfig), and the mode is left as it was, so nothing the mimic answers becomes a recording.
ClassMethod RecordAgentMode(mode As %String) As %String [ SqlProc ]
{
    Set mode = $ZCONVERT($ZSTRIP(mode, "<>W"), "L")
    If (mode = "record") && (..MockConfig() '= "") Quit "refused: the API mimic is on"
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

/// Whether the production's start must write the provider configuration from the environment's key again, with the
/// reason in <var>reason</var> ("" when it need not): no provider is recorded, or the record's digest is of another key
/// (the .env changed), or the wallet secret or the Config Store configuration the record names is gone. The record
/// (^Shutter.Config) is in the data database, which the container's volume keeps; the wallet and the Config Store are
/// instance state in IRISSYS, which the image brings, so a container recreated on the same volume keeps the record and
/// loses the secret, and the record alone would say that nothing needs writing while every live run failed at the
/// provider. Each probe (WalletSecretState, ProviderConfigState) says nothing where its class is absent (the core
/// edition) or this process may not read it (the production's own process may: it wrote them), and the answer then
/// comes from the record alone; <var>probe</var> 0 skips them, which is what a core edition's answer amounts to.
ClassMethod ProviderNeedsRewrite(key As %String, Output reason As %String, probe As %Boolean = 1) As %Boolean
{
    Set reason = ""
    If '..ProviderConfigured() Set reason = "no provider is configured" Quit 1
    If '..ProviderKeyMatches(key) Set reason = "the provider was configured from another key" Quit 1
    If probe {
        If ..WalletSecretState() = 0 Set reason = "the wallet secret Shutter.Anthropic is gone" Quit 1
        If ..ProviderConfigState() = 0 Set reason = "the Config Store configuration AI.LLM.Shutter is gone" Quit 1
    }
    Quit 0
}

/// Whether the wallet holds the secret Shutter.Anthropic: 1 or 0, or "" where the wallet class is absent (the core
/// edition) or this process may not read the wallet. The collection's use resource is Shutter_Secrets, and the wallet
/// answers a caller without it as if the secret were not there (0 from Exists, no error; AI Hub build 109), so the
/// resource is checked first: a signed-in reader of the Doctor without it is told nothing rather than "gone".
/// <var>mayRead</var> stands in for that check in a test; -1 reads the process's own right.
ClassMethod WalletSecretState(mayRead As %Integer = -1) As %String
{
    If mayRead = -1 Set mayRead = $SYSTEM.Security.Check("Shutter_Secrets", "USE")
    If 'mayRead Return ""
    Try {
        Return ''$CLASSMETHOD("%Wallet.KeyValue", "Exists", "Shutter.Anthropic")
    } Catch ex {
        Return ""
    }
}

/// Whether the Config Store holds the configuration AI.LLM.Shutter (read as the live runner reads it, with no secret
/// resolved): 1 or 0, or "" where the Config Store class is absent (the core edition) or this process may not read it.
/// The Config Store refuses a reader without %Admin_ConfigStore:USE (error 790), which would read as "gone", so the
/// resource is checked first. <var>mayRead</var> stands in for that check in a test; -1 reads the process's own right.
ClassMethod ProviderConfigState(mayRead As %Integer = -1) As %String
{
    If mayRead = -1 Set mayRead = $SYSTEM.Security.Check("%Admin_ConfigStore", "USE")
    If 'mayRead Return ""
    Try {
        Set sc = $CLASSMETHOD("%ConfigStore.Configuration", "GetDetails", "AI.LLM.Shutter", .details, 0, 0)
        Return ''$$$ISOK(sc)
    } Catch ex {
        Return ""
    }
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

/// The Config Store configuration of the API mimic while it is switched on, else "". The mimic is a test fixture
/// (tests/mock, in neither module nor the image) that answers the live runner's model calls without a model: while
/// it is on, every live run goes to it and is labelled model mock at cost 0, and record mode is refused. It counts on
/// a demo instance only (^Shutter.Config("demo")): on a site the switch is ignored, so this answers "" there whatever
/// the global holds (Shutter.Production OnStart warns about such a switch, and Doctor's mock_config shows it).
ClassMethod MockConfig() As %String
{
    If '$GET(^Shutter.Config("demo")) Quit ""
    Quit $GET(^Shutter.Config("aihub", "mock"))
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
