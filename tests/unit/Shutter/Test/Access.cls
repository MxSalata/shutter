/// GET /access (Shutter.API.Access; CONTRACTS 5): each installed role's column comes from its resources in Security.Roles,
/// its granted roles' included, and reads as Shutter.Setup.CreateSecurity defines the role; the record the install writes
/// for callers who may not read Security.Roles matches a live read; the caller's own column comes from
/// $SYSTEM.Security.Check; a row this instance has nothing to hold for is false for everyone; and the reply names roles and
/// resources, never a user. Read in %SYS after the install's refresh, as Shutter.Test.Roles does.
Class Shutter.Test.Access Extends %UnitTest.TestCase
{

/// Whether this process could write the record (it needs %Admin_Secure, which the test runner's user has in CI).
Property Recorded As %Boolean [ InitialExpression = 0 ];

Method OnBeforeAllTests() As %Status
{
    Set sc = ##class(Shutter.Setup).RefreshSecurity($NAMESPACE)
    Quit:$$$ISERR(sc) sc
    Set ..Recorded = ##class(Shutter.API.Access).Record()
    Quit $$$OK
}

/// A role's resources with its granted roles' (to any depth), as pieces "name:perms" joined by commas, read in %SYS
/// without the class under test.
ClassMethod AllResources(role As %String) As %String
{
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set out = "", todo = $LISTBUILD(role), done = "", i = 0
    While i < $LISTLENGTH(todo) {
        Set i = i + 1, name = $LIST(todo, i)
        Continue:$LISTFIND(done, name)
        Set done = done _ $LISTBUILD(name)
        Continue:'##class(Security.Roles).Exists(name)
        Kill p
        Do ##class(Security.Roles).Get(name, .p)
        Set out = out _ $SELECT(out = "": "", 1: ",") _ $GET(p("Resources"))
        For j = 1:1:$LENGTH($GET(p("GrantedRoles")), ",") {
            Set g = $ZSTRIP($PIECE(p("GrantedRoles"), ",", j), "<>W")
            If (g '= "") && '$LISTFIND(todo, g) Set todo = todo _ $LISTBUILD(g)
        }
    }
    Quit out
}

/// Whether a resources string (AllResources) grants "name:P": the piece for the name carries the permission letter.
ClassMethod Has(all As %String, res As %String) As %Boolean
{
    Set name = $ZCONVERT($PIECE(res, ":", 1), "U"), perm = $PIECE(res, ":", 2), found = 0
    For j = 1:1:$LENGTH(all, ",") {
        Set piece = $ZSTRIP($PIECE(all, ",", j), "<>W")
        Continue:$ZCONVERT($PIECE(piece, ":", 1), "U")'=name
        If (perm = "") || ($PIECE(piece, ":", 2) [ perm) Set found = 1 Quit
    }
    Quit found
}

/// Whether the resources meet one of a row's alternatives (every resource of it), from the resources string alone.
ClassMethod MeetsAny(all As %String, needs As %DynamicArray) As %Boolean
{
    Set iter = needs.%GetIterator()
    While iter.%GetNext(.k, .alt) {
        Set ok = 1, inner = alt.%GetIterator()
        While inner.%GetNext(.n, .res) { If '..Has(all, res) Set ok = 0 Quit }
        If ok Quit
    }
    Quit +$GET(ok)
}

/// Every key and every string value of a dynamic object or array, at any depth, lower-cased, as subscripts.
ClassMethod Walk(node As %DynamicAbstractObject, ByRef fields, ByRef values)
{
    Set iter = node.%GetIterator()
    While iter.%GetNext(.key, .value, .type) {
        If node.%IsA("%DynamicObject") Set fields($ZCONVERT(key, "L")) = ""
        If $ISOBJECT(value) {
            Do ..Walk(value, .fields, .values)
        } ElseIf type = "string" {
            Set values($ZCONVERT(value, "L")) = ""
        }
    }
}

ClassMethod Row(report As %DynamicObject, id As %String) As %DynamicObject
{
    Set iter = report.rows.%GetIterator()
    While iter.%GetNext(.k, .row) { If row.id = id Quit }
    Quit row
}

ClassMethod Cell(report As %DynamicObject, id As %String, role As %String) As %Boolean
{
    Quit ''..Row(report, id).roles.%Get(role)
}

/// Every role's every cell, read now from Security.Roles, is what the role's resources (its granted roles' included) say
/// of the row's needs, and the single-resource rows name the resource the route checks.
Method TestEachRoleRowMatchesItsResources()
{
    Set report = ##class(Shutter.API.Access).Report(1)
    Do $$$AssertEquals(report.read, "now", "a caller who may read Security.Roles reads it now")
    Set checked = 0
    For role = "Shutter_Demo", "Shutter_Judge", "Shutter_Operator", "Shutter_Approver", "Shutter_Trace" {
        Set all = ..AllResources(role)
        Set rows = report.rows.%GetIterator()
        While rows.%GetNext(.k, .row) {
            Set expected = row.available && ..MeetsAny(all, row.needs)
            Do $$$AssertEquals(''row.roles.%Get(role), ''expected, role _ " " _ row.id _ " from " _ row.needs.%ToJSON() _ " against " _ all)
            Set checked = checked + 1
        }
    }
    Do $$$AssertTrue(checked >= 50, checked _ " cells checked (ten rows for five roles)")
    For id = "view", "approve", "scenarios", "reset", "liveAgents", "configure", "publisher" {
        Set res = $CASE(id, "view": "Shutter_Operate", "approve": "Shutter_Approve", "scenarios": "Shutter_Scenarios", "reset": "Shutter_ScenarioReset", "liveAgents": "Shutter_LiveAgents", "configure": "Shutter_Configure", : "Shutter_Publish")
        Do $$$AssertEquals(..Row(report, id).needs.%ToJSON(), "[[""" _ res _ ":U""]]", id _ " needs the resource the route checks")
    }
}

/// The roles as the install makes them (Shutter.Setup.CreateSecurity): the public demo's viewer approves but neither
/// runs scenarios, spends the model budget nor configures; the judge adds the model budget and running the scenarios
/// (1.4.3), never their reset; the operator runs and resets scenarios and publishes but neither approves nor configures; the approver does everything; the trace role does nothing
/// of Shutter's.
Method TestTheInstalledRolesAsSetupMakesThem()
{
    Set report = ##class(Shutter.API.Access).Report(1)
    Set iter = report.roles.%GetIterator()
    While iter.%GetNext(.k, .r) { Do $$$AssertTrue(r.installed, r.role _ " is installed") }
    Do $$$AssertEquals(report.roles.%Size(), 5, "five roles: the four a person signs in to Shutter with, and the trace role")
    Do $$$AssertTrue(..Cell(report, "view", "Shutter_Demo") && ..Cell(report, "approve", "Shutter_Demo"), "the demo viewer views and approves")
    Do $$$AssertNotTrue(..Cell(report, "scenarios", "Shutter_Demo") || ..Cell(report, "reset", "Shutter_Demo") || ..Cell(report, "liveAgents", "Shutter_Demo") || ..Cell(report, "configure", "Shutter_Demo"), "and neither runs or resets scenarios, spends the budget nor configures")
    Do $$$AssertTrue(..Cell(report, "liveAgents", "Shutter_Judge") && ..Cell(report, "scenarios", "Shutter_Judge"), "the judge spends the model budget and runs the scenarios")
    Do $$$AssertNotTrue(..Cell(report, "reset", "Shutter_Judge") || ..Cell(report, "configure", "Shutter_Judge"), "and, like the demo viewer, neither resets the demo nor configures")
    Do $$$AssertTrue(..Cell(report, "scenarios", "Shutter_Operator") && ..Cell(report, "reset", "Shutter_Operator") && ..Cell(report, "liveAgents", "Shutter_Operator"), "the operator runs and resets scenarios and spends the budget")
    Do $$$AssertNotTrue(..Cell(report, "approve", "Shutter_Operator") || ..Cell(report, "configure", "Shutter_Operator"), "and neither approves nor configures")
    For id = "view", "approve", "scenarios", "reset", "liveAgents", "configure" { Do $$$AssertTrue(..Cell(report, id, "Shutter_Approver"), "the approver: " _ id) }
    If ..Row(report, "publisher").available {
        Do $$$AssertTrue(..Cell(report, "publisher", "Shutter_Operator") && ..Cell(report, "publisher", "Shutter_Approver"), "the operator and the approver (through the operator's role) read the publisher")
        Do $$$AssertNotTrue(..Cell(report, "publisher", "Shutter_Demo") || ..Cell(report, "publisher", "Shutter_Judge"), "the public demo's roles do not")
    }
    For id = "view", "approve", "scenarios", "reset", "liveAgents", "configure", "publisher" { Do $$$AssertNotTrue(..Cell(report, id, "Shutter_Trace"), "the trace role has nothing of Shutter's: " _ id) }
}

/// The record the install, the portal's hardening and each start of the production write (Record) answers the same
/// cells as a live read, and says it is a record, with its time.
Method TestTheRecordMatchesALiveRead()
{
    If '..Recorded Do $$$AssertSkipped("this process may not read Security.Roles, so no record was written") Quit
    Set live = ##class(Shutter.API.Access).Report(1), recorded = ##class(Shutter.API.Access).Report(0)
    Do $$$AssertEquals(recorded.read, "recorded", "read from the record")
    Do $$$AssertTrue($LENGTH(recorded.recordedAt) >= 19, "with the time it was written: " _ recorded.recordedAt)
    Do $$$AssertNotTrue(live.%IsDefined("recordedAt"), "a live read carries no record time")
    Do $$$AssertEquals(recorded.roles.%ToJSON(), live.roles.%ToJSON(), "the same roles, installed alike")
    Set rows = live.rows.%GetIterator()
    While rows.%GetNext(.k, .row) {
        Do $$$AssertEquals(..Row(recorded, row.id).roles.%ToJSON(), row.roles.%ToJSON(), row.id _ ": the same cells from the record")
    }
}

/// Without a record, a caller who may not read Security.Roles sees no role installed and every role cell false, and the
/// reply says so (read "none"); the caller's own column still answers.
Method TestWithoutARecordNoRoleIsInstalled()
{
    If '..Recorded Do $$$AssertSkipped("this process may not read Security.Roles, so the record cannot be put back") Quit
    Merge saved = ^Shutter.Config("access")
    Kill ^Shutter.Config("access")
    Try {
        Set report = ##class(Shutter.API.Access).Report(0)
        Do $$$AssertEquals(report.read, "none", "no record yet")
        Do $$$AssertNotTrue(report.%IsDefined("recordedAt"), "and no time")
        Set iter = report.roles.%GetIterator()
        While iter.%GetNext(.k, .r) { Do $$$AssertNotTrue(r.installed, r.role _ " reads as not installed") }
        Do $$$AssertNotTrue(..Cell(report, "view", "Shutter_Approver"), "every role cell is false")
        Do $$$AssertEquals(''..Row(report, "view").you, ''$SYSTEM.Security.Check("Shutter_Operate", "USE"), "the caller's column still answers")
    } Catch ex {
        Do $$$AssertTrue(0, "Report without a record: " _ ex.DisplayString())
    }
    Kill ^Shutter.Config("access")
    Merge ^Shutter.Config("access") = saved
    Do $$$AssertTrue(##class(Shutter.API.Access).Record(), "the record is written again")
}

/// The caller's column comes from the resources this process holds, by $SYSTEM.Security.Check as GET /me reads them, and
/// a row the instance has nothing to hold for is false for the caller and for every role.
Method TestTheCallersColumn()
{
    Set report = ##class(Shutter.API.Access).Report()
    Set rows = report.rows.%GetIterator()
    While rows.%GetNext(.k, .row) {
        Set mine = 0, alts = row.needs.%GetIterator()
        While alts.%GetNext(.a, .alt) {
            Set ok = 1, inner = alt.%GetIterator()
            While inner.%GetNext(.n, .res) {
                Set perm = $CASE($PIECE(res, ":", 2), "R": "READ", "W": "WRITE", : "USE")
                If '$SYSTEM.Security.Check($PIECE(res, ":", 1), perm) Set ok = 0 Quit
            }
            If ok Set mine = 1 Quit
        }
        Do $$$AssertEquals(''row.you, ''(row.available && mine), row.id _ ": the caller's column from $SYSTEM.Security.Check")
        If 'row.available {
            Do $$$AssertNotTrue(row.you, row.id _ " is not on this instance, so not the caller's")
            Set cells = row.roles.%GetIterator()
            While cells.%GetNext(.role, .v) { Do $$$AssertNotTrue(v, row.id _ " is not on this instance, so not " _ role _ "'s") }
        }
    }
    Do $$$AssertEquals(''..Row(report, "view").you, ''$SYSTEM.Security.Check("Shutter_Operate", "USE"), "view is Shutter_Operate, as GET /me's operator")
    Do $$$AssertEquals(''..Row(report, "approve").you, ''$SYSTEM.Security.Check("Shutter_Approve", "USE"), "approve is Shutter_Approve, as GET /me's approver")
    Do $$$AssertEquals(''..Row(report, "guide").available, ''$GET(^Shutter.Config("demo")), "the Shutter in IRIS page is a demo instance's")
}

/// The reply names roles and resources: no user, no password, no name of anyone, and nothing but the fields the contract
/// lists.
Method TestNamesNoUser()
{
    Set report = ##class(Shutter.API.Access).Report()
    // Every key and every string value in the reply, at any depth.
    Do ..Walk(report, .fields, .values)
    For word = "username", "password", "user", "users", "caller", "name" {
        Do $$$AssertNotTrue($DATA(fields($ZCONVERT(word, "L"))), "no field " _ word)
    }
    For user = "demo", "judge", "operator", "approver", "demo-trace", "forwarder", "downstream-client", "_system", "superuser", $ZCONVERT($USERNAME, "L") {
        Do $$$AssertNotTrue($DATA(values($ZCONVERT(user, "L"))), "no user named: " _ user)
    }
    Set value = ""
    For {
        Set value = $ORDER(values(value))
        Quit:value=""
        Do $$$AssertTrue(($EXTRACT(value, 1, 8) = "shutter_") || ($EXTRACT(value) = "%") || (value [ ":") || ($LISTFIND($LISTBUILD("now", "recorded", "none", "view", "approve", "scenarios", "reset", "liveagents", "configure", "inbox", "guide", "trace", "publisher"), value) > 0) || (value ? 4N1"-"2N1"-"2N1"T".E), "a value is a role, a resource, a row, the read or a time: " _ value)
    }
    Set keys = "", iter = report.%GetIterator()
    While iter.%GetNext(.key, .v) { Set keys = keys _ "," _ key }
    Set keys = keys _ ","
    For key = "demo", "portalHardened", "read", "roles", "rows" { Do $$$AssertTrue(keys [ ("," _ key _ ","), "the field " _ key) }
    Set extra = $TRANSLATE(keys, ",", " ")
    For key = "demo", "portalHardened", "read", "recordedAt", "roles", "rows" { Set extra = $REPLACE(extra, " " _ key _ " ", " ") }
    Do $$$AssertEquals($ZSTRIP(extra, "<>W"), "", "and no other field: " _ keys)
    Set roles = report.roles.%GetIterator()
    While roles.%GetNext(.k, .r) {
        Do $$$AssertTrue($EXTRACT(r.role, 1, 8) = "Shutter_", "each column is a role Shutter installs: " _ r.role)
    }
}

/// The matching of a held set against what a row needs, on strings alone: the permission letters, a resource two roles
/// grant with both their permissions, and the alternatives.
Method TestHoldsAndMeets()
{
    Set held = ",Shutter_Operate:U,%DB_SHUTTER:RW,%Ens_Portal:U,"
    Do $$$AssertTrue(##class(Shutter.API.Access).Holds(held, "Shutter_Operate", "U"), "holds a USE")
    Do $$$AssertTrue(##class(Shutter.API.Access).Holds(held, "%db_shutter", "R") && ##class(Shutter.API.Access).Holds(held, "%DB_SHUTTER", "W"), "RW holds R and W, whatever the case of the name")
    Do $$$AssertNotTrue(##class(Shutter.API.Access).Holds(held, "%DB_SHUTTER", "U"), "RW does not hold USE")
    Do $$$AssertNotTrue(##class(Shutter.API.Access).Holds(held, "Shutter_Operat", "U"), "a prefix of a name is not the name")
    Do $$$AssertNotTrue(##class(Shutter.API.Access).Holds(held, "Shutter_Approve", ""), "a resource not held")
    Do $$$AssertTrue(##class(Shutter.API.Access).Meets([["Shutter_Portal:U"], ["Shutter_Operate:U", "%Ens_Portal:U"]], held), "the second alternative is met")
    Do $$$AssertNotTrue(##class(Shutter.API.Access).Meets([["Shutter_Portal:U"], ["Shutter_Operate:U", "Shutter_Approve:U"]], held), "neither alternative is met")
    Do $$$AssertNotTrue(##class(Shutter.API.Access).Meets([], held), "no alternative, nothing met")
    // The approver's held set carries the operator's resources through the granted role, with the publisher's resource.
    Set approver = ##class(Shutter.API.Access).Held("Shutter_Approver", .installed)
    Do $$$AssertTrue(installed && ##class(Shutter.API.Access).Holds(approver, "Shutter_Publish", "U") && ##class(Shutter.API.Access).Holds(approver, "Shutter_Approve", "U"), "the approver holds Shutter_Publish through Shutter_Operator and its own Shutter_Approve: " _ approver)
    Set none = ##class(Shutter.API.Access).Held("Shutter_NoSuchRole", .installed)
    Do $$$AssertTrue('installed && (none = ","), "a role that is not defined holds nothing and is not installed")
}

}
