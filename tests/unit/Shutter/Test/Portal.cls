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

/// The production's start applies the hardening when the environment asks for it (SHUTTER_DEMO_PORTAL=1, through
/// ApplyRuntime's portal argument): the portal is hardened, the time is recorded (an earlier start's errors cleared) and the
/// Doctor reports it; any other value leaves the portal alone. Put back as TestHardenPortalAndRestore does.
Method TestApplyRuntimeHardens()
{
    If '$SYSTEM.Security.Check("%Admin_Secure", "USE") { Do $$$AssertSkipped("no %Admin_Secure here: nothing to try") Quit }
    Set before = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).PortalState(), .sc)
    Do $$$AssertStatusOK(sc, "the state reads: " _ before.%ToJSON())
    Set exists = 0
    Set it = before.apps.%GetIterator()
    While it.%GetNext(, .a) { If a.exists Set exists = exists + 1 }
    If exists = 0 { Do $$$AssertSkipped("this instance has no portal application for the namespaces: nothing to harden") Quit }
    Set roleWas = before."trace_role", recordWas = $GET(^Shutter.Config("portalHardened")), errorsWere = $GET(^Shutter.Config("portalHardeningErrors"))
    // An earlier start that failed: no stamp, its errors recorded.
    Kill ^Shutter.Config("portalHardened")
    Set ^Shutter.Config("portalHardeningErrors") = "role: an earlier start's failure"
    // Any value but 1 leaves the portal and the record alone.
    Set applied = ##class(Shutter.Setup).ApplyRuntime("", "", "", "", "", "", 0, "", "", "", "", "0")
    Do $$$AssertTrue('applied.%IsDefined("portal") && '$DATA(^Shutter.Config("portalHardened")), "0 leaves the portal alone: " _ applied.%ToJSON())
    Do $$$AssertEquals($GET(^Shutter.Config("portalHardeningErrors")), "role: an earlier start's failure", "and the earlier errors as they were")
    Set applied = ##class(Shutter.Setup).ApplyRuntime("", "", "", "", "", "", 0, "", "", "", "", "1")
    Do $$$AssertTrue('applied.%IsDefined("errors"), "the environment applies the hardening without error: " _ applied.%ToJSON())
    Do $$$AssertTrue($ISOBJECT(applied.portal) && applied.portal.hardened, "and says so: " _ applied.%ToJSON())
    Set after = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).PortalState(), .sc)
    Do $$$AssertEquals(after.hardened, 1, "the portal is hardened: " _ after.%ToJSON())
    Set at = $GET(^Shutter.Config("portalHardened"))
    Do $$$AssertTrue(at ?4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1"Z", "the time is recorded: " _ at)
    Do $$$AssertEquals(applied.portal.at, at, "and returned")
    Do $$$AssertEquals($DATA(^Shutter.Config("portalHardeningErrors")), 0, "the earlier start's errors are cleared")
    Set doctor = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).Doctor(), .sc)
    Do $$$AssertEquals(doctor."portal_hardened", 1, "the Doctor reports it")
    Do $$$AssertEquals(doctor."portal_hardened_at", at, "with the time")
    Do $$$AssertEquals(doctor."portal_hardening_errors", "", "and no errors")
    // Put it back: the applications' MatchRoles and resource as the state read them before, the role's resources, the
    // SELECT grants and the record.
    New $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Set it = before.apps.%GetIterator()
    While it.%GetNext(, .a) {
        Continue:'a.exists
        Kill props
        Set props("MatchRoles") = a."match_roles", props("Resource") = a.resource
        Do $$$AssertStatusOK(##class(Security.Applications).Modify(a.name, .props), a.name _ " put back")
    }
    Kill props
    Set props("Resources") = roleWas
    Do $$$AssertStatusOK(##class(Security.Roles).Modify("Shutter_Trace", .props), "the role put back")
    Set $NAMESPACE = "SHUTTER"
    Set hospital = $GET(^Shutter.Config("hospitalNamespace"))
    For n = $NAMESPACE, hospital { If n '= "" Do $$$AssertStatusOK(##class(Shutter.Setup).TraceSelectGrant(n, 0, .count, .problem), "the SELECT grants taken away again in " _ n _ " (" _ count _ "): " _ problem) }
    If recordWas = "" { Kill ^Shutter.Config("portalHardened") } Else { Set ^Shutter.Config("portalHardened") = recordWas }
    If errorsWere = "" { Kill ^Shutter.Config("portalHardeningErrors") } Else { Set ^Shutter.Config("portalHardeningErrors") = errorsWere }
    Set restored = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).PortalState(), .sc)
    Do $$$AssertEquals(restored."trace_role", roleWas, "the role's resources as before")
    Do $$$AssertEquals(restored.hardened, before.hardened, "and the state as before")
    Set doctor = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).Doctor(), .sc)
    Do $$$AssertEquals(doctor."portal_hardened", recordWas '= "", "and the Doctor's record as before")
}

/// A start whose hardening fails leaves no stamp (the delta sweep of 3 Nov 2026): the record of an earlier success is
/// cleared before the attempt, the errors are kept beside it and the Doctor reports both, so a health page read after a
/// failed start never claims a hardened portal with the old time. The failure comes from Shutter.Test.FakeSetup, whose
/// HardenPortal refuses as the real one does without %Admin_Secure; the portal itself is not touched.
Method TestFailedHardeningLeavesNoStamp()
{
    Set recordWas = $GET(^Shutter.Config("portalHardened")), errorsWere = $GET(^Shutter.Config("portalHardeningErrors"))
    Set ^Shutter.Config("portalHardened") = "2026-11-03T00:00:00Z"
    Kill ^Shutter.Config("portalHardeningErrors")
    Set applied = ##class(Shutter.Test.FakeSetup).ApplyRuntime("", "", "", "", "", "", 0, "", "", "", "", "1")
    Do $$$AssertTrue('applied.%IsDefined("portal"), "a failed hardening is not reported as one: " _ applied.%ToJSON())
    Do $$$AssertTrue($ISOBJECT(applied.errors) && (applied.errors.%ToJSON() [ "portal: %Admin_Secure is required"), "the failure is returned: " _ applied.%ToJSON())
    Do $$$AssertEquals($DATA(^Shutter.Config("portalHardened")), 0, "the earlier success's stamp is cleared")
    Do $$$AssertEquals($GET(^Shutter.Config("portalHardeningErrors")), "%Admin_Secure is required", "and the errors are recorded")
    Set doctor = ##class(Shutter.Util.Json).Parse(##class(Shutter.Setup).Doctor(), .sc)
    Do $$$AssertEquals(doctor."portal_hardened", 0, "the Doctor no longer claims a hardened portal")
    Do $$$AssertEquals(doctor."portal_hardened_at", "", "nor the old time")
    Do $$$AssertEquals(doctor."portal_hardening_errors", "%Admin_Secure is required", "and shows the errors")
    If recordWas = "" { Kill ^Shutter.Config("portalHardened") } Else { Set ^Shutter.Config("portalHardened") = recordWas }
    If errorsWere = "" { Kill ^Shutter.Config("portalHardeningErrors") } Else { Set ^Shutter.Config("portalHardeningErrors") = errorsWere }
}

}
