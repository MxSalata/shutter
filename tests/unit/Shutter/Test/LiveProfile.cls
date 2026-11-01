/// The live hospital's profile policy (Shutter.Setup.LiveProfilePolicy; CONTRACTS 4.4, v1.34): told the live hospital is on,
/// the install sets the shipped profile's tier 2 single policy to approval and marks the source; a person's own profile is
/// left alone. The profile is put back as it was afterwards.
Class Shutter.Test.LiveProfile Extends %UnitTest.TestCase
{

Property SavedJson As %String(MAXLEN = "");

Property SavedSource As %String(MAXLEN = 500);

Method OnBeforeAllTests() As %Status
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If $ISOBJECT(row) Set ..SavedJson = row.Json, ..SavedSource = row.Source
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    If ..SavedJson '= "" Do ##class(Shutter.Store.SiteProfile).Store(..SavedJson, ..SavedSource, "test", "", .v)
    Quit $$$OK
}

Method TestLivePolicy()
{
    Set seed = "/tmp/shutter-test-seed/profile.json"
    // A shipped profile: the default, stored as the seed's.
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(##class(Shutter.Store.SiteProfile).Default().%ToJSON(), seed, "test", "", .v), "the shipped profile stored as the seed's")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "automatic", "tier 2 single is automatic as shipped")
    Do $$$AssertStatusOK(##class(Shutter.Setup).LiveProfilePolicy(seed, 0), "off: nothing to do")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "automatic", "and nothing changed")
    Do $$$AssertStatusOK(##class(Shutter.Setup).LiveProfilePolicy(seed, 1), "on: the live policy applies")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "approval", "tier 2 single waits for a person")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "ordered"), "approval", "the other kinds as shipped")
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Do $$$AssertEquals(row.Source, seed _ " (live hospital)", "the source says why: " _ row.Source)
    Set version = row.Version
    Do $$$AssertStatusOK(##class(Shutter.Setup).LiveProfilePolicy(seed, 1), "again: idempotent")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Version, version, "and the version did not move")
    // A person's own profile is theirs.
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "api", "approver", "", .v), "a profile a person saved")
    Do $$$AssertStatusOK(##class(Shutter.Setup).LiveProfilePolicy(seed, 1), "on, but not the seed's profile")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "automatic", "left alone")
}

}
