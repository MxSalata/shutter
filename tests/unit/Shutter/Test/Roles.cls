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

}
