/// The Settings screen's routes for watched namespaces (Shutter.API.Onboarding; CONTRACTS 11.1): options are checked before
/// they reach the plan, the plan's digest follows what a person was shown, an apply on an old plan is refused, the removal's
/// preview only reads the record, and the list offers no namespace that is Shutter's or the instance's own.
/// tests/e2e/onboard_api_check.py plays the routes on real productions.
Class Shutter.Test.OnboardApi Extends %UnitTest.TestCase
{

Parameter NS = "ONBAPITESTNS";

Method OnAfterAllTests() As %Status
{
    Kill ^Shutter.Config("onboard", ..#NS)
    Quit $$$OK
}

/// An option nobody knows is refused, so that a slip never runs on the defaults.
Method TestOptionsAreChecked()
{
    Set api = "Shutter.API.Onboarding"
    Set o = $CLASSMETHOD(api, "CleanOptions", "", .problem)
    Do $$$AssertEquals(problem, "", "none at all")
    Do $$$AssertEquals(o.%ToJSON(), "{}", "gives no options")
    Set o = $CLASSMETHOD(api, "CleanOptions", {"receivers": "LIMS Out", "ssl_config": "", "alert_on_error": true, "shutter_port": 52773}, .problem)
    Do $$$AssertEquals(problem, "", "known ones")
    Do $$$AssertEquals(o.receivers, "LIMS Out", "are kept")
    Do $$$AssertTrue('o.%IsDefined("ssl_config"), "an empty one is as if not given")
    Do $$$AssertEquals(o.%GetTypeOf("alert_on_error"), "boolean", "a flag stays a flag")
    Do $$$AssertEquals(o."shutter_port", 52773, "a port is kept")
    Do $CLASSMETHOD(api, "CleanOptions", {"recievers": "LIMS Out"}, .problem)
    Do $$$AssertTrue(problem [ "recievers", "a misspelt one is named: " _ problem)
    Do $CLASSMETHOD(api, "CleanOptions", [1], .problem)
    Do $$$AssertTrue(problem [ "JSON object", "an array is refused: " _ problem)
    Do $CLASSMETHOD(api, "CleanOptions", "plain words", .problem)
    Do $$$AssertTrue(problem [ "JSON object", "and so is a string: " _ problem)
}

/// The digest follows what the plan says and the options it was read with, in whichever order they were written.
Method TestDigestFollowsThePlanAndItsOptions()
{
    Set api = "Shutter.API.Onboarding"
    Set plan = {"production": "P", "actions": [{"do": "add_forwarder", "says": "Add"}], "warnings": [], "todo": ["Credential"]}
    Set one = $CLASSMETHOD(api, "Digest", plan, {"receivers": "A", "credential": "C"})
    Do $$$AssertEquals($LENGTH(one), 64, "a SHA-256 in hex")
    Do $$$AssertEquals($CLASSMETHOD(api, "Digest", plan, {"credential": "C", "receivers": "A"}), one, "the options' order does not matter")
    Do $$$AssertNotEquals($CLASSMETHOD(api, "Digest", plan, {"receivers": "A"}), one, "other options do")
    Set other = {"production": "P", "actions": [{"do": "add_forwarder", "says": "Add"}, {"do": "draft_receiver", "says": "Draft"}], "warnings": [], "todo": ["Credential"]}
    Do $$$AssertNotEquals($CLASSMETHOD(api, "Digest", other, {"receivers": "A", "credential": "C"}), one, "an action more does")
    Set warned = {"production": "P", "actions": [{"do": "add_forwarder", "says": "Add"}], "warnings": ["New"], "todo": ["Credential"]}
    Do $$$AssertNotEquals($CLASSMETHOD(api, "Digest", warned, {"receivers": "A", "credential": "C"}), one, "a warning more does")
}

/// The list takes off Shutter's own namespace, the instance's and those already watched.
Method TestOfferedNamespaces()
{
    Set api = "Shutter.API.Onboarding"
    Do $$$AssertEquals($CLASSMETHOD(api, "Offerable", "PATHOLOGY", "SHUTTER"), 1, "a hospital's")
    Do $$$AssertEquals($CLASSMETHOD(api, "Offerable", "SHUTTER", "SHUTTER"), 0, "not Shutter's own")
    For own = "%SYS", "HSLIB", "HSSYS", "HSCUSTOM", "ENSLIB" {
        Do $$$AssertEquals($CLASSMETHOD(api, "Offerable", own, "SHUTTER"), 0, "not the instance's own: " _ own)
    }
    Set list = $CLASSMETHOD(api, "Available", [{"namespace": ($NAMESPACE)}])
    Do $$$AssertTrue($ISOBJECT(list) && list.%IsA("%DynamicArray"), "the list is an array")
    Set it = list.%GetIterator(), found = 0
    While it.%GetNext(, .one) { If one.namespace = $NAMESPACE Set found = 1 }
    Do $$$AssertEquals(found, 0, "and leaves out this namespace")
}

/// What taking a namespace off would do, read from the record of what the apply did, changing nothing.
Method TestRemovalPreviewReadsTheRecord()
{
    Set api = "Shutter.API.Onboarding", ns = ..#NS
    Kill ^Shutter.Config("onboard", ns)
    Set p = $CLASSMETHOD(api, "RemovalPreview", ns)
    Do $$$AssertEquals(p.onboarded, 0, "nothing on record")
    Do $$$AssertEquals(p.items.%Size(), 0, "so no items")
    Set ^Shutter.Config("onboard", ns) = "A.Production"
    Set ^Shutter.Config("onboard", ns, "items", "Shutter Forwarder") = "added"
    Set ^Shutter.Config("onboard", ns, "items", "Ens.Alert") = "added"
    Set ^Shutter.Config("onboard", ns, "renamed") = "Site Alerts"
    Set ^Shutter.Config("onboard", ns, "alertOnError", "Out") = 1
    Set ^Shutter.Config("onboard", ns, "mappings", "Shutter.Util") = "SHUTTER-CODE"
    Set ^Shutter.Config("onboard", ns, "drafted", "Out") = 1
    Merge before = ^Shutter.Config("onboard", ns)
    Set p = $CLASSMETHOD(api, "RemovalPreview", ns)
    Do $$$AssertEquals(p.onboarded, 1, "on record")
    Do $$$AssertEquals(p.production, "A.Production", "the production")
    Do $$$AssertEquals(p.items.%ToJSON(), "[""Ens.Alert"",""Shutter Forwarder""]", "the items")
    Do $$$AssertEquals(p.renamed, "Site Alerts", "the renamed item")
    Do $$$AssertEquals(p.alertOnError.%ToJSON(), "[""Out""]", "the flags")
    Do $$$AssertEquals(p.mappings.%ToJSON(), "[""Shutter.Util""]", "the mappings")
    Do $$$AssertEquals(p.drafted.%ToJSON(), "[""Out""]", "the drafts")
    Merge after = ^Shutter.Config("onboard", ns)
    Do $$$AssertEquals($DATA(after("items", "Ens.Alert")) && $DATA(before("items", "Ens.Alert")), 1, "the record stays")
    Kill ^Shutter.Config("onboard", ns)
}

/// A plan of a namespace that is not there has a digest, and an apply with another is refused with the fresh plan.
Method TestStaleDigestIsRefusedBeforeAnythingRuns()
{
    Set api = "Shutter.API.Onboarding"
    Set stale = $CLASSMETHOD(api, "StalePlan", ..#NS, {}, "not the digest")
    Do $$$AssertTrue($ISOBJECT(stale), "an old digest answers the fresh plan")
    Do $$$AssertEquals(stale.plan.namespace, ..#NS, "of that namespace")
    Do $$$AssertEquals($LENGTH(stale.digest), 64, "and its digest")
    Do $$$AssertEquals($CLASSMETHOD(api, "StalePlan", ..#NS, {}, stale.digest), "", "the same digest is not old")
}

}
