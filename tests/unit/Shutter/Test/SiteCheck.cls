/// The will-this-work-here report (Shutter.Util.SiteCheck; docs/INSTALL.md, "Before you install"): each check from the shape of
/// Onboard.Read's answer, the version and which package fits it, the verdict, and that the report changes nothing on this
/// instance. tests/e2e/doctor_check.py runs it on a stock instance with no Shutter on it.
Class Shutter.Test.SiteCheck Extends %UnitTest.TestCase
{

/// A read of a running production with one well-set HL7 operation and no alert item.
Method Read() As %DynamicObject [ Private ]
{
    Set op = {"name": "Lab Out", "class": "EnsLib.HL7.Operation.TCPOperation", "kind": "hl7_operation", "categories": [], "alert_on_error": true, "enabled": true, "failure_timeout": "0", "get_reply": true}
    Set svc = {"name": "PAS In", "class": "EnsLib.HL7.Service.TCPService", "kind": "hl7_service", "categories": ["2.5.1"], "alert_on_error": false, "enabled": true}
    Set r = {"namespace": "PAS", "production": "Site.Production", "state": "running", "items": [(svc), (op)], "categories": {"2.5.1": {"standard": true, "base": ""}}, "error": "", "exists": true, "interoperability": true, "alert_default_settings": 0}
    Do r.%Set("alert", "", "null")
    Quit r
}

/// The checks of an answer with a given id.
Method Ids(answer As %DynamicObject, id As %String) As %DynamicArray [ Private ]
{
    Set out = [], it = answer.checks.%GetIterator()
    While it.%GetNext(, .c) { If c.id = id Do out.%Push(c) }
    Quit out
}

Method TestAWellSetNamespaceWorks()
{
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(..Read(), {"Lab Out": {"all": 12, "adt": 9}})
    Do $$$AssertEquals(a.verdict, "works", "nothing against it: " _ a.%ToJSON())
    Do $$$AssertEquals(a.operations.%Size(), 1, "its one operation")
    Do $$$AssertEquals(a.operations.%Get(0).failed, 12, "with its failed messages")
    Do $$$AssertEquals(a.operations.%Get(0)."failed_adt", 9, "and how many are ADT")
    Do $$$AssertEquals(..Ids(a, "what_you_get").%Size(), 1, "and it says what a namespace gets")
}

Method TestWhatStopsANamespace()
{
    Set gone = {"namespace": "NOPE", "production": "", "state": "", "items": [], "categories": {}, "error": "No namespace NOPE on this instance", "exists": false, "interoperability": false}
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(gone)
    Do $$$AssertEquals(a.verdict, "blocked", "no namespace")
    Do $$$AssertTrue(a.checks.%Get(0).says [ "No namespace", a.%ToJSON())
    Set off = {"namespace": "OFF", "production": "", "state": "", "items": [], "categories": {}, "error": "Interoperability is not enabled in OFF", "exists": true, "interoperability": false}
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(off)
    Do $$$AssertEquals(a.verdict, "blocked", "Interoperability off")
    Do $$$AssertTrue(a.checks.%Get(0).says [ "Enable it", a.%ToJSON())
    Set none = {"namespace": "EMPTY", "production": "", "state": "", "items": [], "categories": {}, "error": "No production in EMPTY", "exists": true, "interoperability": true}
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(none)
    Do $$$AssertEquals(a.verdict, "blocked", "no production")
    Set r = ..Read()
    Set r."alert_items" = 2
    Set r.alert = {"item": "Ens.Alert", "class": "Site.Alerts", "is_shutter": false}
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(r)
    Do $$$AssertEquals(a.verdict, "blocked", "two items named Ens.Alert")
    Set r = ..Read()
    Set r.alert = {"item": "Ens.Alert", "class": "Site.Alerts", "is_shutter": false}
    Do r.items.%Push({"name": "Site Alerts", "class": "Site.Other", "kind": "other", "categories": []})
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(r)
    Do $$$AssertEquals(a.verdict, "blocked", "the name Site Alerts taken")
}

Method TestWhatNeedsAChange()
{
    Set r = ..Read()
    Set r.state = "stopped"
    Do $$$AssertEquals(##class(Shutter.Util.SiteCheck).Namespace(r).verdict, "changes_needed", "a stopped production")
    Set r = ..Read(), r.items.%Get(1)."alert_on_error" = 0
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(r)
    Do $$$AssertEquals(..Ids(a, "alert_on_error").%Size(), 1, "AlertOnError off: " _ a.%ToJSON())
    Do $$$AssertTrue(..Ids(a, "alert_on_error").%Get(0).says [ "Lab Out", "by name")
    Do $$$AssertEquals(a.verdict, "changes_needed", "needs a change")
    Set r = ..Read(), r.items.%Get(1)."failure_timeout" = "-1"
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(r)
    Do $$$AssertEquals(..Ids(a, "failure_timeout").%Size(), 1, "retrying forever: " _ a.%ToJSON())
    Set r = ..Read()
    Do r.items.%Get(1).%Set("get_reply", 0, "boolean")
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(r)
    Do $$$AssertEquals(a.verdict, "changes_needed", "GetReply off")
    Do $$$AssertTrue(..Ids(a, "get_reply").%Get(0).says [ "written to the connection", a.%ToJSON())
    Set r = ..Read()
    Set r.alert = {"item": "Ens.Alert", "class": "Site.Alerts", "is_shutter": false}, r."alert_default_settings" = 1
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(r)
    Do $$$AssertEquals(..Ids(a, "alert_defaults").%Size(), 1, "default settings keyed to Ens.Alert: " _ a.%ToJSON())
    Set r = ..Read()
    Set r.items.%Get(0).categories = ["LOCALX"]
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(r)
    Do $$$AssertTrue(..Ids(a, "schema").%Get(0).says [ "not loaded", "a category not loaded there: " _ a.%ToJSON())
    Do $$$AssertEquals(a.verdict, "changes_needed", "needs a change")
    Set r = ..Read()
    Set r.items = [{"name": "Own Out", "class": "Site.Own", "kind": "operation", "categories": []}]
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(r)
    Do $$$AssertTrue(..Ids(a, "receivers").%Get(0).says [ "Own Out", "a site's own connector, by name: " _ a.%ToJSON())
}

Method TestTheAlertItemAsItStands()
{
    Set r = ..Read()
    Set r.alert = {"item": "Ens.Alert", "class": "Site.Alerts", "is_shutter": false}
    Set a = ##class(Shutter.Util.SiteCheck).Namespace(r)
    Do $$$AssertEquals(a.verdict, "works", "the site's own is kept under another name: " _ a.%ToJSON())
    Do $$$AssertTrue(..Ids(a, "alert_item").%Get(0).says [ "Site Alerts", "and it says so")
}

Method TestTheVersions()
{
    Set c = "Shutter.Util.SiteCheck"
    Set v = $CLASSMETHOD(c, "VersionCheck", 2025, 1, 0)
    Do $$$AssertEquals(v.result, "fail", "2025.1 is too old: " _ v.says)
    Set v = $CLASSMETHOD(c, "VersionCheck", 2026, 1, 0)
    Do $$$AssertEquals(v.result, "fail", "2026.1 too: " _ v.says)
    Set v = $CLASSMETHOD(c, "VersionCheck", 2026, 2, 0)
    Do $$$AssertTrue((v.result = "pass") && (v.says [ "core"), "2026.2 takes the core: " _ v.says)
    Set v = $CLASSMETHOD(c, "VersionCheck", 2026, 3, 1)
    Do $$$AssertTrue((v.result = "pass") && (v.says [ "whole package"), "2026.3 with AI Hub the whole package: " _ v.says)
    Set v = $CLASSMETHOD(c, "VersionCheck", 2027, 1, 1)
    Do $$$AssertTrue((v.result = "pass") && (v.says [ "whole package"), "2027.1 with AI Hub too: " _ v.says)
    Set v = $CLASSMETHOD(c, "VersionCheck", 2027, 1, 0)
    Do $$$AssertTrue((v.result = "pass") && (v.says [ "core"), "a later version without AI Hub takes the core: " _ v.says)
}

Method TestTheWholeReportOnThisInstance()
{
    Set r = ##class(%DynamicObject).%FromJSON(##class(Shutter.Util.SiteCheck).Report("NOSUCHNS"))
    Do $$$AssertEquals(r.verdict, "blocked", "a namespace not there blocks: " _ r.%ToJSON())
    Do $$$AssertEquals(r.namespaces.%Get(0).namespace, "NOSUCHNS", "and it is named")
    Do $$$AssertTrue(r."not_checked".%Size() >= 1, "it says what it did not check")
    Do $$$AssertTrue(r.instance.version '= "", "the instance's version: " _ r.instance.version)
    Do $$$AssertTrue(r.checks.%Size() >= 4, "the instance's checks")
}

/// The report writes nothing: the production item count and the config global stay as they were.
Method TestItChangesNothing()
{
    &sql(SELECT COUNT(*) INTO :before FROM Ens_Config.Item)
    Set config = $GET(^Shutter.Config("version")) _ "|" _ $DATA(^Shutter.Config("onboard"))
    Do ##class(Shutter.Util.SiteCheck).Report($NAMESPACE)
    &sql(SELECT COUNT(*) INTO :after FROM Ens_Config.Item)
    Do $$$AssertEquals(after, before, "no item added")
    Do $$$AssertEquals($GET(^Shutter.Config("version")) _ "|" _ $DATA(^Shutter.Config("onboard")), config, "nothing recorded")
}

}
