/// Will Shutter work here? A report from the integration guide's list (docs/INSTALL.md, "Before you install"), for an instance
/// that has no Shutter on it yet. It changes nothing: it reads the instance and each namespace named, through
/// Shutter.Util.Onboard's Read, and the last week's failed messages. Two classes loaded alone run it, in any namespace, and
/// it needs nothing else of Shutter's: SiteCheck.cls and Onboard.cls. Answers JSON, or plain lines from Print. Once Shutter is
/// installed, the Doctor and the onboarding plan say more.
Class Shutter.Util.SiteCheck
{

/// The first version the core installs on, as major.minor.
Parameter COREVERSION = 2026.2;

/// The first version the whole package installs on, with the agents.
Parameter AIHUBVERSION = 2026.3;

/// How many of a namespace's failed messages are read, newest first.
Parameter FAILEDROWS = 2000;

/// The days of failed messages read.
Parameter FAILEDDAYS = 7;

/// The report as JSON. namespaces is a comma-separated list; empty means every namespace with Interoperability and a production.
ClassMethod Report(namespaces As %String = "") As %String [ SqlProc ]
{
    Quit ..Build(namespaces).%ToJSON()
}

/// The report in plain lines, for a terminal.
ClassMethod Print(namespaces As %String = "")
{
    Set r = ..Build(namespaces)
    Write !, r.says, !
    Do ..PrintChecks(r.checks)
    Set it = r.namespaces.%GetIterator()
    While it.%GetNext(, .n) {
        Write !, n.namespace, $SELECT(n.production '= "": " (" _ n.production _ ", " _ n."production_state" _ ")", 1: ""), !
        Do ..PrintChecks(n.checks)
        Set oi = n.operations.%GetIterator()
        While oi.%GetNext(, .o) {
            Write "  - ", o.name, ": ", o."failed_days", " days: ", o.failed, " failed, ", o."failed_adt", " of them ADT", !
        }
    }
    Write !, "Not checked:", !
    Set it = r."not_checked".%GetIterator()
    While it.%GetNext(, .line) { Write "  ", line, ! }
}

ClassMethod PrintChecks(checks As %DynamicArray) [ Private ]
{
    Set it = checks.%GetIterator()
    While it.%GetNext(, .c) {
        Write "  ", $ZCONVERT(c.result, "U"), " ", c.says, $SELECT(c.guide '= "": " (guide " _ c.guide _ ")", 1: ""), !
    }
}

/// {verdict, says, instance, checks, namespaces: [{namespace, production, production_state, checks, operations, verdict}], not_checked}.
/// verdict: blocked (a check fails), changes_needed (a check warns), or works. A result is pass, warn, fail or info.
ClassMethod Build(namespaces As %String = "") As %DynamicObject
{
    Set r = {"instance": {}, "checks": [], "namespaces": []}
    Do ..Instance(r.instance, r.checks)
    Set list = $ZSTRIP(namespaces, "*W")
    If list = "" Set list = ..WatchableNamespaces()
    If list = "" Do r.checks.%Push(..Check("namespaces", "warn", "No namespace here has Interoperability on and a production, so there is nothing yet to watch", "9"))
    Set verdicts = $LISTBUILD(..Worst(r.checks))
    For i = 1:1:$LENGTH(list, ",") {
        Set ns = $ZCONVERT($PIECE(list, ",", i), "U")
        Continue:ns=""
        Set read = ##class(Shutter.Util.Onboard).Read(ns)
        Set one = ..Namespace(read, ..Failed(ns))
        Do r.namespaces.%Push(one)
        Set verdicts = verdicts _ $LISTBUILD(one.verdict)
    }
    Set r.verdict = $SELECT($LISTFIND(verdicts, "blocked"): "blocked", $LISTFIND(verdicts, "changes_needed"): "changes_needed", 1: "works")
    Set r.says = $CASE(r.verdict, "blocked": "Blocked: fix what fails below before installing.", "changes_needed": "Shutter can go here, with the changes below.", : "Nothing found against installing Shutter here.")
    Set r."not_checked" = ["Whether a receiver has an API that meets the contract (CONTRACTS 1): only a receiver with one can be resent to, and only ADT", "What a green message means at each receiver beyond its settings (guide 9.9): send a test message and see what comes back", "Whether the data database is on storage the trust backs up (guide 3.1)", "A first case: after the apply, SELECT Shutter.Setup_OnboardTest('<namespace>') opens one with nothing sent"]
    Quit r
}

/// The instance's own checks: its version and edition, the caller's rights, IPM, the licence, and whether Shutter is here already.
ClassMethod Instance(instance As %DynamicObject, checks As %DynamicArray)
{
    Set instance.version = $SYSTEM.Version.GetNumber()
    Do instance.%Set("ai_hub_present", ''##class(%Dictionary.CompiledClass).%ExistsId("%AI.Agent"), "boolean")
    Do checks.%Push(..VersionCheck($SYSTEM.Version.GetMajor(), $SYSTEM.Version.GetMinor(), instance."ai_hub_present"))
    Do instance.%Set("may_manage", ''$SYSTEM.Security.Check("%Admin_Manage", "USE"), "boolean")
    Do checks.%Push($SELECT(instance."may_manage": ..Check("rights", "pass", "This user holds %Admin_Manage", "9"), 1: ..Check("rights", "warn", "This user does not hold %Admin_Manage: the install and the apply need it, with every namespace's database. Run this as _SYSTEM or in a terminal on the server to see all of it", "9")))
    Do instance.%Set("ipm", ''##class(%Dictionary.CompiledClass).%ExistsId("%IPM.Main"), "boolean")
    Do checks.%Push($SELECT(instance.ipm: ..Check("ipm", "pass", "IPM is in this namespace", "3.1"), 1: ..Check("ipm", "info", "IPM is not in this namespace: it goes into Shutter's namespace first. The repository holds a copy in vendor/ipm", "3.1")))
    Set port = ##class(Shutter.Util.Onboard).WebPort()
    Set instance."web_port" = port
    Do checks.%Push(..Check("web_port", "info", "This instance's web server is on port " _ port _ ", the forwarder's target by default. On a licensed instance give the Web Gateway's", "9.1"))
    Try {
        Set instance."licence_units_available" = +$SYSTEM.License.LUAvailable()
        If instance."licence_units_available" < 5 {
            Do checks.%Push(..Check("licence", "warn", "Only " _ instance."licence_units_available" _ " licence units are free: the web application and each forward sign in, and a refused sign-in loses the forward", "10"))
        } Else {
            Do checks.%Push(..Check("licence", "pass", instance."licence_units_available" _ " licence units are free", ""))
        }
    } Catch ex {
        Do checks.%Push(..Check("licence", "info", "The licence could not be read here", ""))
    }
    Try {
        Set instance."shutter_namespace" = ''##class(%SYS.Namespace).Exists("SHUTTER")
        If instance."shutter_namespace" Do checks.%Push(..Check("shutter_namespace", "info", "A namespace SHUTTER is here already. Shape A puts Shutter there; check it holds nothing else", "3.1"))
    } Catch ex {
    }
}

/// The version and which package fits it.
ClassMethod VersionCheck(major As %Integer, minor As %Integer, aiHub As %Boolean) As %DynamicObject
{
    Set number = +major + (+minor / 10), word = major _ "." _ minor
    If number < ..#COREVERSION Quit ..Check("version", "fail", "IRIS " _ word _ " is too old: Shutter's core needs " _ ..#COREVERSION _ " or later, with Interoperability", "2")
    If (number >= ..#AIHUBVERSION) && aiHub Quit ..Check("version", "pass", "IRIS " _ word _ " with AI Hub: the whole package fits (zpm ""install iris-shutter"")", "2")
    Quit ..Check("version", "pass", "IRIS " _ word _ " without AI Hub: the core fits (zpm ""load <repository>/core -Ddemo=0""), and the agents replay recordings", "2")
}

/// A namespace's checks from Onboard.Read's answer and its failed messages (Failed), changing nothing and reading nothing itself.
ClassMethod Namespace(read As %DynamicObject, failed As %DynamicObject = "") As %DynamicObject
{
    If '$ISOBJECT(failed) Set failed = {}
    Set out = {"namespace": (read.namespace), "production": (read.production), "production_state": (read.state), "checks": [], "operations": []}
    Set checks = out.checks
    If 'read.exists Do checks.%Push(..Check("namespace", "fail", read.error, "9"))
    If read.exists && 'read.interoperability Do checks.%Push(..Check("interoperability", "fail", read.error _ ". Enable it first", "9"))
    If read.exists && read.interoperability && (read.error '= "") Do checks.%Push(..Check("production", "fail", read.error, "9.1"))
    If read.production = "" Set out.verdict = ..Worst(checks) Quit out
    Do checks.%Push($SELECT(read.state = "running": ..Check("production", "pass", "The production " _ read.production _ " is running; onboarding updates it and stops nothing", "9.2"), 1: ..Check("production", "warn", "The production " _ read.production _ " is " _ read.state _ ": the definition changes, and the items start when you start it", "9.1")))
    Do ..AlertChecks(read, checks)
    Set hl7 = 0, others = 0, it = read.items.%GetIterator()
    While it.%GetNext(, .item) {
        If item.kind = "hl7_operation" {
            Set hl7 = hl7 + 1
            Do out.operations.%Push(..Operation(item, failed, checks))
        } ElseIf (item.kind = "operation") && (item.class '= "Shutter.Intake.Forwarder") {
            Set others = others + 1, otherNames(item.name) = ""
        }
    }
    If 'hl7 {
        Set names = "", name = ""
        For { Set name = $ORDER(otherNames(name)) Quit:name=""  Set names = names _ $SELECT(names = "": "", 1: ", ") _ name }
        Do checks.%Push(..Check("receivers", "warn", "No stock HL7 operation here" _ $SELECT(others: ": name your connectors in the option receivers (" _ names _ ")", 1: ", so nothing to watch"), "9.1"))
    }
    Do ..SchemaChecks(read, checks)
    Do checks.%Push(..Check("what_you_get", "info", "A failed delivery here opens a case with its evidence. Only ADT to a receiver whose API you describe can be resent; everything else escalates to a person", "9"))
    Set out.verdict = ..Worst(checks)
    Quit out
}

/// The alert item: none is simple, the site's own is renamed and kept, and two of them or a taken name stop the apply.
ClassMethod AlertChecks(read As %DynamicObject, checks As %DynamicArray) [ Private ]
{
    Set alert = read.alert, taken = 0, it = read.items.%GetIterator()
    While it.%GetNext(, .item) { If item.name = "Site Alerts" Set taken = 1 }
    If +read.%Get("alert_items") > 1 {
        Do checks.%Push(..Check("alert_item", "fail", "Two items are named Ens.Alert in " _ read.production _ ": the engine uses one and ignores the other. Rename one before onboarding", "9.2"))
    } ElseIf '$ISOBJECT(alert) {
        Do checks.%Push(..Check("alert_item", "pass", "No item named Ens.Alert: the apply adds Shutter's", "9.2"))
    } ElseIf alert."is_shutter" {
        Do checks.%Push(..Check("alert_item", "info", "Ens.Alert is Shutter's intake already", "9.2"))
    } ElseIf taken {
        Do checks.%Push(..Check("alert_item", "fail", "An item is named Site Alerts, the name your Ens.Alert (" _ alert.class _ ") would take: rename it before onboarding", "9.2"))
    } Else {
        Do checks.%Push(..Check("alert_item", "info", "Your Ens.Alert (" _ alert.class _ ") becomes Site Alerts and still gets every alert first", "9.2"))
        If +read.%Get("alert_default_settings") > 0 Do checks.%Push(..Check("alert_defaults", "warn", "System default settings are keyed to the name Ens.Alert: move them to Site Alerts", "9.1"))
    }
}

/// One HL7 operation: what it must have for a failure to reach Shutter, and what failed there lately.
ClassMethod Operation(item As %DynamicObject, failed As %DynamicObject, checks As %DynamicArray) As %DynamicObject [ Private ]
{
    Set o = {"name": (item.name), "class": (item.class), "failure_timeout": (item."failure_timeout"), "failed": 0, "failed_adt": 0, "failed_days": (..#FAILEDDAYS)}
    Do o.%Set("alert_on_error", item."alert_on_error", "boolean"), o.%Set("enabled", item.enabled, "boolean")
    Set seen = failed.%Get(item.name)
    If $ISOBJECT(seen) Set o.failed = +seen.all, o."failed_adt" = +seen.adt
    If 'item."alert_on_error" Do checks.%Push(..Check("alert_on_error", "warn", item.name _ " raises no alert on an error, so Shutter hears nothing from it: turn AlertOnError on, or pass alert_on_error to the apply", "9.2"))
    If item."failure_timeout" = "-1" Do checks.%Push(..Check("failure_timeout", "warn", item.name _ " retries forever (FailureTimeout -1): a case opens on the first failure, even in a short outage, and stays open while the engine delivers later", "10"))
    If item.%GetTypeOf("get_reply") = "boolean" {
        If 'item."get_reply" Do checks.%Push(..Check("get_reply", "warn", item.name _ " has GetReply off: a completed message proves only that it was written to the connection, and a lost one raises nothing", "9.9"))
    } Else {
        Do checks.%Push(..Check("get_reply", "info", item.name _ " is not on the TCP adapter, and nothing has been measured there: test what a completed message means", "9.9"))
    }
    Quit o
}

/// The categories the services name: one not loaded there is a warning, and a custom one is copied at the apply.
ClassMethod SchemaChecks(read As %DynamicObject, checks As %DynamicArray) [ Private ]
{
    Set it = read.items.%GetIterator()
    While it.%GetNext(, .item) {
        Continue:item.kind'="hl7_service"
        Set ci = item.categories.%GetIterator()
        While ci.%GetNext(, .cat) {
            Continue:$DATA(said(cat))
            Set said(cat) = 1, here = read.categories.%Get(cat)
            If '$ISOBJECT(here) {
                Do checks.%Push(..Check("schema", "warn", "The category " _ cat _ ", named by " _ item.name _ ", is not loaded in " _ read.namespace _ ": import it there first", "7"))
            } ElseIf 'here.standard {
                Do checks.%Push(..Check("schema", "info", "The custom category " _ cat _ " is copied into Shutter's namespace at the apply", "9.2"))
            }
        }
    }
}

/// The namespace's newest failed messages (the engine's status Error, in the last FAILEDDAYS days, at most FAILEDROWS) by target:
/// {target: {all, adt}}. {} when they cannot be read. Calls only Ens, %SQL and EnsLib classes while it is there.
ClassMethod Failed(ns As %String) As %DynamicObject
{
    Set out = {}
    New $NAMESPACE
    Try {
        Set $NAMESPACE = ns
        Set since = $ZDATETIME($ZTIMESTAMP - ..#FAILEDDAYS, 3, 1)
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP "_(+..#FAILEDROWS)_" h.TargetConfigName AS T, m.Name AS N FROM Ens.MessageHeader h LEFT JOIN EnsLib_HL7.Message m ON h.MessageBodyClassName = 'EnsLib.HL7.Message' AND m.ID = h.MessageBodyId WHERE h.Status = 8 AND h.TimeCreated >= ? ORDER BY h.ID DESC", since)
        While rs.%Next() {
            Set target = rs.%Get("T"), one = out.%Get(target)
            If '$ISOBJECT(one) Set one = {"all": 0, "adt": 0}
            Set one.all = one.all + 1
            If $EXTRACT(rs.%Get("N"), 1, 3) = "ADT" Set one.adt = one.adt + 1
            Do out.%Set(target, one)
        }
    } Catch ex {
    }
    Quit out
}

/// Every namespace with Interoperability on and a production, comma-separated, without IRIS's own.
ClassMethod WatchableNamespaces() As %String
{
    Set out = "", ns = ""
    Do ##class(%SYS.Namespace).ListAll(.list)
    For {
        Set ns = $ORDER(list(ns)) Quit:ns=""
        Continue:$EXTRACT(ns)="%"
        Continue:(ns = "HSLIB") || (ns = "HSSYS") || (ns = "HSCUSTOM") || (ns = "HSAALIB") || (ns = "ENSLIB") || (ns = "ENSEMBLE") || (ns = "DOCBOOK") || (ns = "SAMPLES")
        Continue:ns["^"
        Try {
            Continue:'##class(%EnsembleMgr).IsEnsembleNamespace(ns)
            If ##class(Shutter.Util.Onboard).Read(ns).production '= "" Set out = out _ $SELECT(out = "": "", 1: ",") _ ns
        } Catch ex {
        }
    }
    Quit out
}

/// A check's verdict over a list: blocked by a fail, changes_needed by a warn, else works.
ClassMethod Worst(checks As %DynamicArray) As %String
{
    Set verdict = "works", it = checks.%GetIterator()
    While it.%GetNext(, .c) {
        If c.result = "fail" Return "blocked"
        If c.result = "warn" Set verdict = "changes_needed"
    }
    Quit verdict
}

ClassMethod Check(id As %String, result As %String, says As %String, guide As %String = "") As %DynamicObject
{
    Quit {"id": (id), "result": (result), "says": (says), "guide": (guide)}
}

}
