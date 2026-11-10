/// The roles and resources the install makes (Shutter.Setup.CreateSecurity; CONTRACTS 5 and 12, v1.33): the demo controls and
/// the site's writes are guarded by resources of their own, the operator and the approver hold them, and the public demo's
/// role holds neither while it approves. Since 1.4.3 running a scenario (Shutter_Scenarios) and resetting the shared demo
/// (Shutter_ScenarioReset, which the purge needs too) are two resources: the judges' role runs and never resets. Read in
/// %SYS after the install's refresh, which is repeatable.
Class Shutter.Test.Roles Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
    Quit ##class(Shutter.Setup).RefreshSecurity($NAMESPACE)
}

ClassMethod Resources(role As %String) As %String
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If '##class(Security.Roles).Exists(role) Quit "<no role>"
    Do ##class(Security.Roles).Get(role, .p)
    Quit $GET(p("Resources"))
}

/// Whether a role holds a resource with a permission (name:perm), from its own resources as Security.Roles keeps them.
ClassMethod Holds(role As %String, resource As %String) As %Boolean
{
    Quit ("," _ ..Resources(role) _ ",") [ ("," _ resource _ ",")
}

/// Whether a role names a resource at all, with any permission.
ClassMethod Names(role As %String, name As %String) As %Boolean
{
    Quit ("," _ ..Resources(role)) [ ("," _ name _ ":")
}

ClassMethod ResourceExists(name As %String) As %Boolean
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Quit ##class(Security.Resources).Exists(name)
}

Method TestResourcesAndRoles()
{
    For res = "Shutter_Operate", "Shutter_Approve", "Shutter_Intake", "Shutter_Configure", "Shutter_Scenarios", "Shutter_ScenarioReset", "Shutter_LiveAgents" {
        Do $$$AssertTrue(..ResourceExists(res), res _ " exists")
    }
    Set op = ..Resources("Shutter_Operator")
    Do $$$AssertTrue((op [ "Shutter_Operate:U") && (op [ "Shutter_Scenarios:U") && '(op [ "Shutter_Configure"), "the operator runs scenarios and does not configure: " _ op)
    Set ap = ..Resources("Shutter_Approver")
    Do $$$AssertTrue((ap [ "Shutter_Approve:U") && (ap [ "Shutter_Configure:U") && (ap [ "Shutter_Scenarios:U"), "the approver approves, configures and runs scenarios: " _ ap)
    Do $$$AssertTrue(ap [ "%Ens_EventLog:U", "the approver reads the trace's events, or its diamonds answer that they are not permitted: " _ ap)
    Set demo = ..Resources("Shutter_Demo")
    Do $$$AssertTrue((demo [ "Shutter_Operate:U") && (demo [ "Shutter_Approve:U"), "the demo role reads and approves: " _ demo)
    Do $$$AssertTrue('(demo [ "Shutter_Configure") && '..Names("Shutter_Demo", "Shutter_Scenarios") && '..Names("Shutter_Demo", "Shutter_ScenarioReset"), "and neither configures, runs scenarios nor resets")
    Do $$$AssertTrue(demo [ "%Ens_MessageTrace:U", "it reads traces as the approver does")
    Do $$$AssertTrue((op [ "Shutter_LiveAgents:U") && (ap [ "Shutter_LiveAgents:U"), "operators and approvers may spend the model budget")
    Do $$$AssertNotTrue(demo [ "Shutter_LiveAgents", "the public demo's role never spends it")
    Set judge = ..Resources("Shutter_Judge")
    Do $$$AssertTrue((judge [ "Shutter_Operate:U") && (judge [ "Shutter_Approve:U") && (judge [ "Shutter_LiveAgents:U"), "a judge reads, approves and spends the budget: " _ judge)
    Do $$$AssertTrue('(judge [ "Shutter_Configure"), "and does not configure")
    Do $$$AssertTrue(..Holds("Shutter_Judge", "Shutter_Scenarios:U"), "a judge runs the scenarios (1.4.3): " _ judge)
    Do $$$AssertNotTrue(..Names("Shutter_Judge", "Shutter_ScenarioReset"), "and never resets the shared demo or purges the store: " _ judge)
    Set trace = ..Resources("Shutter_Trace")
    Do $$$AssertTrue((trace [ "%Ens_MessageTrace:U") && (trace [ "%Ens_Portal:U") && '(trace [ "Shutter_"), "the trace role sees traces and nothing of Shutter's: " _ trace)
}

/// Running and resetting are two resources (1.4.3): the operator and the approver hold both, the judge runs only, and the
/// demo viewer neither; the routes and the purge check the resource the table says, read from their source.
Method TestRunAndResetAreSplit()
{
    For role = "Shutter_Operator", "Shutter_Approver" {
        Do $$$AssertTrue(..Holds(role, "Shutter_Scenarios:U") && ..Holds(role, "Shutter_ScenarioReset:U"), role _ " runs and resets: " _ ..Resources(role))
    }
    Do $$$AssertTrue(..Holds("Shutter_Judge", "Shutter_Scenarios:U") && '..Names("Shutter_Judge", "Shutter_ScenarioReset"), "the judge runs and does not reset")
    Do $$$AssertTrue('..Names("Shutter_Demo", "Shutter_Scenarios") && '..Names("Shutter_Demo", "Shutter_ScenarioReset"), "the demo viewer does neither")
    // The judge's granted roles add neither: %EnsRole_Monitor holds nothing of Shutter's.
    Do ##class(Shutter.Test.Roles).GrantedOf("Shutter_Judge", .granted)
    Do $$$AssertEquals(granted, "%EnsRole_Monitor", "the judge is granted %EnsRole_Monitor only")
    Do $$$AssertNotTrue(..Resources("%EnsRole_Monitor") [ "Shutter_", "which holds nothing of Shutter's")
    Do $$$AssertTrue(..Source("Shutter.API.Dispatch", "ScenarioRun") [ "Allow(""Shutter_Scenarios"", 1)", "POST /scenarios/{id}/run checks Shutter_Scenarios")
    Do $$$AssertNotTrue(..Source("Shutter.API.Dispatch", "ScenarioRun") [ "Shutter_ScenarioReset", "and only that")
    Do $$$AssertTrue(..Source("Shutter.API.Dispatch", "ScenarioReset") [ "Allow(""Shutter_ScenarioReset"", 1)", "POST /scenarios/reset checks Shutter_ScenarioReset")
    Do $$$AssertTrue(..Source("Shutter.Setup", "PurgeStore") [ "Check(""Shutter_ScenarioReset"", ""USE"")", "and so does the purge")
    Do $$$AssertNotTrue(..Source("Shutter.Setup", "PurgeStore") [ "Check(""Shutter_Scenarios""", "not the run's resource")
}

/// The source of a method, as its class definition holds it.
ClassMethod Source(class As %String, method As %String) As %String
{
    Set def = ##class(%Dictionary.MethodDefinition).%OpenId(class _ "||" _ method)
    If '$ISOBJECT(def) Quit ""
    Do def.Implementation.Rewind()
    Quit def.Implementation.Read(1000000)
}

/// A role's granted roles, as Security.Roles keeps them.
ClassMethod GrantedOf(role As %String, Output granted As %String)
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set granted = ""
    Quit:'##class(Security.Roles).Exists(role)
    Do ##class(Security.Roles).Get(role, .p)
    Set granted = $GET(p("GrantedRoles"))
}

/// An upgrade over 1.4.2 (or any 1.4.x before the split): the resource Shutter_ScenarioReset does not exist yet, the
/// operator and the approver hold Shutter_Scenarios only and reset with it, the judge holds neither. The install's refresh
/// creates the resource, gives it to the operator and the approver, so they keep resetting, and gives the judge
/// Shutter_Scenarios alone. The roles are put back by the same refresh, whatever the asserts found.
Method TestAnUpgradeFrom142KeepsTheResetWithTheOperatorAndTheApprover()
{
    Set sc = ..MakeRoles142()
    Do $$$AssertStatusOK(sc, "the roles as 1.4.2 left them")
    Do $$$AssertNotTrue(..ResourceExists("Shutter_ScenarioReset"), "1.4.2 had no Shutter_ScenarioReset")
    Do $$$AssertTrue(..Holds("Shutter_Operator", "Shutter_Scenarios:U") && '..Names("Shutter_Operator", "Shutter_ScenarioReset"), "1.4.2's operator: " _ ..Resources("Shutter_Operator"))
    Do $$$AssertNotTrue(..Names("Shutter_Judge", "Shutter_Scenarios"), "1.4.2's judge runs nothing: " _ ..Resources("Shutter_Judge"))
    Set sc = ##class(Shutter.Setup).RefreshSecurity($NAMESPACE)
    Do $$$AssertStatusOK(sc, "the install's refresh over 1.4.2's roles")
    Do $$$AssertTrue(..ResourceExists("Shutter_ScenarioReset"), "the upgrade creates Shutter_ScenarioReset")
    For role = "Shutter_Operator", "Shutter_Approver" {
        Do $$$AssertTrue(..Holds(role, "Shutter_ScenarioReset:U") && ..Holds(role, "Shutter_Scenarios:U"), role _ " still resets and runs after the upgrade: " _ ..Resources(role))
    }
    Do $$$AssertTrue(..Holds("Shutter_Judge", "Shutter_Scenarios:U") && '..Names("Shutter_Judge", "Shutter_ScenarioReset"), "the judge now runs and still does not reset: " _ ..Resources("Shutter_Judge"))
    Do $$$AssertTrue('..Names("Shutter_Demo", "Shutter_Scenarios") && '..Names("Shutter_Demo", "Shutter_ScenarioReset"), "the demo viewer gains nothing")
    Do $$$AssertEquals(..Description("Shutter_Scenarios"), "Shutter: run the demo's scenarios", "Shutter_Scenarios says what it guards now")
    // The uninstall takes every resource named as Shutter's (Shutter.Util.Uninstall, TakeResources), the new one included
    Do $$$AssertTrue(##class(Shutter.Util.Uninstall).OwnSecurityName("Shutter_ScenarioReset"), "the uninstall removes Shutter_ScenarioReset")
    // A second refresh changes nothing: the install is repeatable.
    Set before = ..Resources("Shutter_Operator") _ "|" _ ..Resources("Shutter_Approver") _ "|" _ ..Resources("Shutter_Judge")
    Do $$$AssertStatusOK(##class(Shutter.Setup).RefreshSecurity($NAMESPACE), "a second refresh")
    Do $$$AssertEquals(..Resources("Shutter_Operator") _ "|" _ ..Resources("Shutter_Approver") _ "|" _ ..Resources("Shutter_Judge"), before, "and the roles are the same")
}

/// 1.4.2's roles on this instance: Shutter_ScenarioReset taken out of every role and deleted, the judge without
/// Shutter_Scenarios, and Shutter_Scenarios with 1.4.2's description.
ClassMethod MakeRoles142() As %Status
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS", sc = $$$OK
    For role = "Shutter_Operator", "Shutter_Approver", "Shutter_Judge" {
        Continue:'##class(Security.Roles).Exists(role)
        Kill p
        Do ##class(Security.Roles).Get(role, .p)
        Set kept = "", list = $LISTFROMSTRING($GET(p("Resources")), ",")
        For i = 1:1:$LISTLENGTH(list) {
            Set one = $LIST(list, i), name = $PIECE(one, ":")
            Continue:(name = "Shutter_ScenarioReset")||((role = "Shutter_Judge") && (name = "Shutter_Scenarios"))
            Set kept = kept _ $SELECT(kept = "": "", 1: ",") _ one
        }
        Kill q
        Set q("Resources") = kept
        Set sc = ##class(Security.Roles).Modify(role, .q)
        Quit:$$$ISERR(sc)
    }
    Quit:$$$ISERR(sc) sc
    If ##class(Security.Resources).Exists("Shutter_ScenarioReset") Set sc = ##class(Security.Resources).Delete("Shutter_ScenarioReset")
    Quit:$$$ISERR(sc) sc
    Kill r
    Set r("Description") = "Shutter: run and reset the demo's scenarios and purge the store"
    Quit ##class(Security.Resources).Modify("Shutter_Scenarios", .r)
}

/// A resource's description.
ClassMethod Description(name As %String) As %String
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    If '##class(Security.Resources).Exists(name) Quit ""
    Do ##class(Security.Resources).Get(name, .p)
    Quit $GET(p("Description"))
}

/// Reset clears the live feed's bed map in the hospital's data database (Scenarios.Runner.ResetLive), so the two roles
/// that may press it write there, and in the demo records system's, which it resets too; the public demo's two roles, which
/// never reset, only read the hospital's and don't touch the records system. Needs a hospital.
Method TestWhoWritesTheHospital()
{
    Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
    If (hospital = "") || ($ZCONVERT(hospital, "U") = $ZCONVERT($NAMESPACE, "U")) {
        Do $$$AssertTrue(1, "no separate hospital namespace on this instance")
        Quit
    }
    Set data = ##class(Shutter.Setup).DatabaseResource(hospital)
    For role = "Shutter_Operator", "Shutter_Approver" {
        Do $$$AssertTrue(..Resources(role) [ (data _ ":RW"), role _ " writes " _ data _ ", or Reset answers 500: " _ ..Resources(role))
    }
    For role = "Shutter_Demo", "Shutter_Judge" {
        Do $$$AssertNotTrue(..Resources(role) [ (data _ ":RW"), role _ " does not write " _ data _ ": " _ ..Resources(role))
        Do $$$AssertTrue(..Resources(role) [ (data _ ":R"), role _ " still reads it")
    }
    If ##class(Shutter.Installer).NamespaceExists("RECORDS") {
        Set records = ##class(Shutter.Setup).DatabaseResource("RECORDS")
        For role = "Shutter_Operator", "Shutter_Approver" {
            Do $$$AssertTrue(..Resources(role) [ (records _ ":RW"), role _ " writes " _ records _ ": " _ ..Resources(role))
        }
        For role = "Shutter_Demo", "Shutter_Judge" {
            Do $$$AssertNotTrue(..Resources(role) [ records, role _ " does not touch " _ records)
        }
    }
}

/// SELECT on a table for a role, as the SQL engine checks it when a stale cached query is compiled again in the
/// caller's process (Shutter.Setup.GrantSqlPrivileges). Checked in this namespace, where the grants were made.
ClassMethod CanSelect(role As %String, table As %String) As %Boolean
{
    Quit $SYSTEM.SQL.Security.CheckPrivilege(role, 1, table, "s")
}

/// Every role that calls the API holds SQL SELECT on Shutter's schemas and on the production's configuration, the
/// public demo's roles included: a judge or a demo user whose read compiles a stale cached query again must not be the
/// one refused (SQLCODE -99). The trace role reads the Management Portal, never the API, and is granted nothing.
Method TestApiRolesHaveSqlSelect()
{
    For role = "Shutter_Operator", "Shutter_Approver", "Shutter_Demo", "Shutter_Judge" {
        For table = "Shutter_Store.Case", "Shutter_Index.Message", "Ens_Config.Item", "Ens.MessageHeader" {
            Do $$$AssertTrue(..CanSelect(role, table), role _ " selects from " _ table)
        }
    }
    Do $$$AssertNotTrue(..CanSelect("Shutter_Trace", "Shutter_Store.Case"), "the trace role has no SELECT on the case store")
}

/// The tables the cases list's queries name (Shutter.API.Dispatch Cases, which reads the page, and Technical, which
/// reads each row's facts; and PageIds and CaseRows where a build has them), read from their source.
ClassMethod ListTables() As %List
{
    Set tables = ""
    For method = "Cases", "Technical", "PageIds", "CaseRows" {
        Set def = ##class(%Dictionary.MethodDefinition).%OpenId("Shutter.API.Dispatch||" _ method)
        Continue:'$ISOBJECT(def)
        Do def.Implementation.Rewind()
        Set text = def.Implementation.Read(1000000), from = 1
        For {
            Set at = $LOCATE(text, "(FROM|JOIN|,) +(Ens|Shutter_[A-Za-z]+)\.(""""[A-Za-z]+""""|[A-Za-z]+)", from, from, match)
            Quit:at=0
            Set table = $TRANSLATE($PIECE(match, " ", *), """")
            If '$LISTFIND(tables, table) Set tables = tables _ $LISTBUILD(table)
        }
    }
    Quit tables
}

/// Every table the cases list reads is one the roles that call the API select from: the list's row query reads the
/// production's message headers, and on IRIS for Health 2026.2 a fresh instance refused it to the operator (SQLCODE -99)
/// when its cached query was compiled again in the operator's process, so the list came back empty beside its total.
Method TestTheCasesListReadsOnlyTablesTheRolesSelect()
{
    Set tables = ..ListTables()
    Do $$$AssertTrue($LISTFIND(tables, "Shutter_Store.Case"), "the case store is among the list's tables: " _ $LISTTOSTRING(tables))
    Do $$$AssertTrue($LISTFIND(tables, "Ens.MessageHeader"), "and the message headers: " _ $LISTTOSTRING(tables))
    For role = "Shutter_Operator", "Shutter_Approver", "Shutter_Demo", "Shutter_Judge" {
        For i = 1:1:$LISTLENGTH(tables) {
            Do $$$AssertTrue(..CanSelect(role, $LIST(tables, i)), role _ " selects from " _ $LIST(tables, i) _ ", which the cases list reads")
        }
    }
}

}
