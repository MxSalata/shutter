/// The roles and resources the install makes (Shutter.Setup.CreateSecurity; CONTRACTS 5 and 12, v1.33): the demo controls and
/// the site's writes are guarded by resources of their own, the operator and the approver hold them, and the public demo's
/// role holds neither while it approves. Read in %SYS after the install's refresh, which is repeatable.
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

ClassMethod ResourceExists(name As %String) As %Boolean
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Quit ##class(Security.Resources).Exists(name)
}

Method TestResourcesAndRoles()
{
    For res = "Shutter_Operate", "Shutter_Approve", "Shutter_Intake", "Shutter_Configure", "Shutter_Scenarios", "Shutter_LiveAgents" {
        Do $$$AssertTrue(..ResourceExists(res), res _ " exists")
    }
    Set op = ..Resources("Shutter_Operator")
    Do $$$AssertTrue((op [ "Shutter_Operate:U") && (op [ "Shutter_Scenarios:U") && '(op [ "Shutter_Configure"), "the operator runs scenarios and does not configure: " _ op)
    Set ap = ..Resources("Shutter_Approver")
    Do $$$AssertTrue((ap [ "Shutter_Approve:U") && (ap [ "Shutter_Configure:U") && (ap [ "Shutter_Scenarios:U"), "the approver approves, configures and runs scenarios: " _ ap)
    Do $$$AssertTrue(ap [ "%Ens_EventLog:U", "the approver reads the trace's events, or its diamonds answer that they are not permitted: " _ ap)
    Set demo = ..Resources("Shutter_Demo")
    Do $$$AssertTrue((demo [ "Shutter_Operate:U") && (demo [ "Shutter_Approve:U"), "the demo role reads and approves: " _ demo)
    Do $$$AssertTrue('(demo [ "Shutter_Configure") && '(demo [ "Shutter_Scenarios"), "and neither configures nor runs scenarios")
    Do $$$AssertTrue(demo [ "%Ens_MessageTrace:U", "it reads traces as the approver does")
    Do $$$AssertTrue((op [ "Shutter_LiveAgents:U") && (ap [ "Shutter_LiveAgents:U"), "operators and approvers may spend the model budget")
    Do $$$AssertNotTrue(demo [ "Shutter_LiveAgents", "the public demo's role never spends it")
    Set judge = ..Resources("Shutter_Judge")
    Do $$$AssertTrue((judge [ "Shutter_Operate:U") && (judge [ "Shutter_Approve:U") && (judge [ "Shutter_LiveAgents:U"), "a judge reads, approves and spends the budget: " _ judge)
    Do $$$AssertTrue('(judge [ "Shutter_Configure") && '(judge [ "Shutter_Scenarios"), "and neither configures nor runs scenarios")
    Set trace = ..Resources("Shutter_Trace")
    Do $$$AssertTrue((trace [ "%Ens_MessageTrace:U") && (trace [ "%Ens_Portal:U") && '(trace [ "Shutter_"), "the trace role sees traces and nothing of Shutter's: " _ trace)
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
        For table = "Shutter_Store.Case", "Shutter_Index.Message", "Ens_Config.Item" {
            Do $$$AssertTrue(..CanSelect(role, table), role _ " selects from " _ table)
        }
    }
    Do $$$AssertNotTrue(..CanSelect("Shutter_Trace", "Shutter_Store.Case"), "the trace role has no SELECT on the case store")
}

}
