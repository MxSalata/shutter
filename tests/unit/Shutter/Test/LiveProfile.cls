/// The live hospital's profile policy (Shutter.Setup.LiveProfilePolicy; CONTRACTS 4.4, v1.34): told the live hospital is on,
/// the install sets the profile's tier 2 single policy to approval and marks the source, on the shipped table (approval
/// everywhere since v1.1.0) or the demo's own (Shutter.Setup.DemoProfilePolicy); a person's own profile is
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
    // Shipped (v1.1.0): approval at every tier for single and ordered chains, the board for interleaved ones.
    For tier = 1, 2, 3 {
        Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(tier, "single"), "approval", "tier " _ tier _ " single asks a person as shipped")
        Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(tier, "ordered"), "approval", "tier " _ tier _ " ordered asks a person as shipped")
        Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(tier, "interleaved"), "board", "tier " _ tier _ " interleaved is the board's")
    }
    // A site install keeps the shipped table; the live hospital's mark on a shipped profile makes no difference at tier 2.
    Do $$$AssertStatusOK(##class(Shutter.Setup).DemoProfilePolicy(seed, 0), "a site install: nothing to do")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Source, seed, "and the source is still the seed's")
    // A demo install keeps the demo's own table, labelled.
    Do $$$AssertStatusOK(##class(Shutter.Setup).DemoProfilePolicy(seed, 1), "a demo install: the demo's policy applies")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "automatic", "tier 2 single is the demo's automatic release")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(1, "ordered"), "automatic", "tier 1 ordered too")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(3, "ordered"), "per_chain", "tier 3 ordered per chain, as the demo had it")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Source, seed _ " (demo)", "the source says whose answers they are")
    Set version = ##class(Shutter.Store.SiteProfile).Row().Version
    Do $$$AssertStatusOK(##class(Shutter.Setup).DemoProfilePolicy(seed, 1), "again: idempotent")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Version, version, "and the version did not move")
    Do $$$AssertStatusOK(##class(Shutter.Setup).LiveProfilePolicy(seed, 0), "live off: nothing to do")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "automatic", "and nothing changed")
    Do $$$AssertStatusOK(##class(Shutter.Setup).LiveProfilePolicy(seed, 1), "on: the live policy applies on the demo's profile")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "approval", "tier 2 single waits for a person")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "ordered"), "approval", "the other kinds as the demo had them")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(1, "single"), "automatic", "tier 1 stays the demo's")
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Do $$$AssertEquals(row.Source, seed _ " (demo) (live hospital)", "the source says why: " _ row.Source)
    Set version = row.Version
    Do $$$AssertStatusOK(##class(Shutter.Setup).LiveProfilePolicy(seed, 1), "again: idempotent")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Version, version, "and the version did not move")
    // A person's own profile is theirs.
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "api", "approver", "", .v), "a profile a person saved")
    Do $$$AssertStatusOK(##class(Shutter.Setup).DemoProfilePolicy(seed, 1), "a demo install, but not the seed's profile")
    Do $$$AssertStatusOK(##class(Shutter.Setup).LiveProfilePolicy(seed, 1), "on, but not the seed's profile")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "approval", "left alone: the person's own answer stands")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Source, "api", "and the source is theirs")
}

}
