/// The demo's portal made read only (v1.38): the portal applications lose their MatchRoles and require Shutter_Portal,
/// which Shutter_Trace alone holds, and the trace role reads the databases the pages need and writes none. The test
/// applies it on this instance and puts the applications and the role back as they were.
Class Shutter.Test.Portal Extends %UnitTest.TestCase
{

Method TestHardenPortalAndRestore()
{
    If '$SYSTEM.Security.Check("%Admin_Secure", "USE") { Do $$$AssertTrue(1, "no %Admin_Secure here: nothing to try") Quit }
    Set before = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).PortalState(), .sc)
    Do $$$AssertStatusOK(sc, "the state reads: " _ before.%ToJSON())
    Set exists = 0
    Set it = before.apps.%GetIterator()
    While it.%GetNext(, .a) { If a.exists Set exists = exists + 1 }
    If exists = 0 { Do $$$AssertTrue(1, "this instance has no portal application for the namespaces: nothing to harden") Quit }
    Set roleWas = before."trace_role"
    Set out = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).HardenPortal(), .sc)
    Do $$$AssertTrue($ISOBJECT(out) && 'out.%IsDefined("errors"), "the portal is hardened without error: " _ out.%ToJSON())
    Set after = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).PortalState(), .sc)
    Do $$$AssertEquals(after.hardened, 1, "and the state says so: " _ after.%ToJSON())
    Set it = after.apps.%GetIterator()
    While it.%GetNext(, .a) {
        Continue:'a.exists
        Do $$$AssertEquals(a."match_roles" _ "|" _ a.resource, "|Shutter_Portal", a.name _ ": no MatchRoles, Shutter_Portal required")
    }
    Do $$$AssertTrue(after."trace_role" [ "Shutter_Portal:U", "the trace role holds the portal resource: " _ after."trace_role")
    Do $$$AssertTrue(after."trace_role" [ "%Ens_EventLog:U", "and the Event Log's: " _ after."trace_role")
    Set sqlState = after.sql.%Get($NAMESPACE)
    Do $$$AssertTrue($ISOBJECT(sqlState) && sqlState.reads, "the trace role reads the message tables through SQL: " _ $SELECT($ISOBJECT(sqlState): sqlState.%ToJSON(), 1: "none"))
    Do $$$AssertTrue($ISOBJECT(sqlState) && sqlState."writes_none", "and writes none of them")
    Do $$$AssertTrue($ISOBJECT(sqlState) && (sqlState."select_tables" >= 3), "SELECT on the message tables: " _ $SELECT($ISOBJECT(sqlState): sqlState."select_tables", 1: 0))
    Do $$$AssertTrue(after."trace_role" [ "%Ens_MessageTrace:U", "and keeps its Interoperability resources")
    Do $$$AssertTrue(after."trace_role" [ (##class(Shutter.Setup).DatabaseResource($NAMESPACE) _ ":R"), "and reads the data database")
    Do $$$AssertEquals($FIND(after."trace_role", ":RW"), 0, "and writes no database: " _ after."trace_role")
    Do $$$AssertEquals(##class(Shutter.Setup).HardenPortal(), ##class(Shutter.Setup).HardenPortal(), "hardening twice is the same")
    // Put it back: the applications' MatchRoles and resource, and the role's resources.
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set it = out.apps.%GetIterator()
    While it.%GetNext(, .a) {
        Kill props
        Set props("MatchRoles") = a."match_roles_were", props("Resource") = a."resource_was"
        Do $$$AssertStatusOK(##class(Security.Applications).Modify(a.name, .props), a.name _ " put back")
    }
    Kill props
    Set props("Resources") = roleWas
    Do $$$AssertStatusOK(##class(Security.Roles).Modify("Shutter_Trace", .props), "the role put back")
    Set $NAMESPACE = "SHUTTER"
    Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
    For n = $NAMESPACE, hospital { If n '= "" Do $$$AssertStatusOK(##class(Shutter.Setup).TraceSelectGrant(n, 0, .count, .problem), "the SELECT grants taken away again in " _ n _ " (" _ count _ "): " _ problem) }
    Set gone = ##class(Shutter.Setup).TraceSqlState($NAMESPACE)
    Do $$$AssertEquals(gone."select_tables", 0, "no SELECT grant left: " _ gone.%ToJSON())
    Set restored = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).PortalState(), .sc)
    Do $$$AssertEquals(restored."trace_role", roleWas, "the role's resources as before")
    Do $$$AssertEquals(restored.hardened, before.hardened, "and the state as before")
}

}
