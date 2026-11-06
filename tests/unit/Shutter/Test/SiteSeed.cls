/// What a non-demo install starts from (Shutter.Store.SiteProfile.ForSite): the seed's demo receivers are gone, nothing
/// is released with no person, and the demo's own seed is as it was. The profile and the demo flag are put back afterwards.
Class Shutter.Test.SiteSeed Extends %UnitTest.TestCase
{

Property SavedJson As %String(MAXLEN = "");

Property SavedSource As %String(MAXLEN = 500);

Property SavedVersion As %Integer [ InitialExpression = 0 ];

Property SavedDemo As %String;

Property SeedPath As %String(MAXLEN = 500);

Method OnBeforeAllTests() As %Status
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If $ISOBJECT(row) Set ..SavedJson = row.Json, ..SavedSource = row.Source, ..SavedVersion = row.Version
    Set ..SavedDemo = $GET(^Shutter.Config("demo"), "unset")
    Set ..SeedPath = ##class(%File).TempFilename("json")
    Quit $$$OK
}

/// The row as it was, written directly, and the history this class added taken away, so a test leaves no version behind.
Method OnAfterAllTests() As %Status
{
    If ..SavedDemo = "unset" { Kill ^Shutter.Config("demo") } Else { Set ^Shutter.Config("demo") = ..SavedDemo }
    Do ..HideProfile()
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.SiteProfileVersion WHERE Version > ?", ..SavedVersion)
    If ..SavedJson '= "" Do ..PutRow(..SavedJson, ..SavedSource, ..SavedVersion)
    Do ##class(%File).Delete(..SeedPath)
    Quit $$$OK
}

/// No stored profile. The history stays, so a test puts a row back with PutRow, never Store, which would number it 1.
Method HideProfile()
{
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If $ISOBJECT(row) Do ##class(Shutter.Store.SiteProfile).%DeleteId(row.%Id())
}

Method PutRow(json As %String, source As %String, version As %Integer)
{
    Do ..HideProfile()
    Set row = ##class(Shutter.Store.SiteProfile).%New()
    Set row.Json = json, row.Source = source, row.Version = version
    Do $$$AssertStatusOK(row.%Save(), "the row is put back")
}

/// As an install leaves it: the seed's own row, which SeedFromFile follows.
Method StoredAsTheSeed()
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(Version) AS v FROM Shutter_Store.SiteProfileVersion")
    Do rs.%Next()
    Do ..PutRow(##class(Shutter.Store.SiteProfile).Default().%ToJSON(), ..SeedPath, +rs.%Get("v"))
}

/// The shape of the shipped seed: both demo receivers, tier 2 single automatic, and a team that names one of them.
Method WriteSeed(extra As %String = "") As %String
{
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Do p.receivers.%Push({"name": "Records Out", "system": "the demo patient records system", "category": "history_of_record", "tier": 2, "applies": "arrival_order", "resend_timestamp": "original", "cancels": false, "merges": false, "api": {"base": "/records/api", "state": "/encounters/{encounter}", "receipt": "/receipts/{key}", "capabilities": "/capabilities", "operations": "/operations"}, "features": {"conditional_writes": true, "receipts": true, "history": true, "dry_run": true}, "demo": {"namespace": "RECORDS"}})
    If extra '= "" Do p.receivers.%Push({"name": (extra), "system": "a site's own system", "tier": 2})
    Set p.mail = {"allowed_domains": ["example.nhs.uk"]}
    Set p.teams = [{"id": "integration", "name": "Integration team", "mailbox": "integration@example.nhs.uk", "receivers": ["Downstream Out"]}]
    Set file = ##class(%Stream.FileCharacter).%New()
    Do file.LinkToFile(..SeedPath)
    Do file.Rewind()
    Do file.Write(p.%ToJSON())
    Do $$$AssertStatusOK(file.%Save(), "the seed is written")
    Quit p.%ToJSON()
}

Method AssertNoAutomatic(when As %String)
{
    Set profile = "Shutter.Store.SiteProfile"
    For tier = 1:1:3 {
        For kind = "single", "ordered", "interleaved" {
            Do $$$AssertNotEquals($CLASSMETHOD(profile, "Policy", tier, kind), "automatic", when _ ": tier " _ tier _ " " _ kind _ " is not automatic")
        }
    }
}

Method AssertNoDemoReceiver(when As %String)
{
    Do $$$AssertTrue('$ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver("Downstream Out")), when _ ": Downstream Out is not named")
    Do $$$AssertTrue('$ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver("Records Out")), when _ ": Records Out is not named")
}

Method TestNonDemoSeed()
{
    Set ^Shutter.Config("demo") = 0
    Do ..StoredAsTheSeed()
    Do ..WriteSeed()
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).SeedFromFile(..SeedPath), "the seed is taken")
    Do ..AssertNoDemoReceiver("seeded")
    Do ..AssertNoAutomatic("seeded")
    Set p = ##class(Shutter.Store.SiteProfile).Current()
    Do $$$AssertEquals(p.receivers.%Size(), 1, "one receiver stands in")
    Do $$$AssertEquals(p.receivers.%Get(0).draft, 1, "and it is a draft, which is never written to")
    Do $$$AssertEquals(p.teams.%Get(0).receivers.%Size(), 0, "the team no longer names a demo receiver")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(p), "", "and the profile is valid, so a person can edit it")
    Set version = ##class(Shutter.Store.SiteProfile).Row().Version
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).SeedFromFile(..SeedPath), "seeded again")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Version, version, "a restart does not make a new version")
}

/// A site's own receiver in the file stays, with no stand-in beside it.
Method TestNonDemoSeedKeepsASitesReceiver()
{
    Set ^Shutter.Config("demo") = 0
    Do ..StoredAsTheSeed()
    Do ..WriteSeed("Bed Mgmt Out")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).SeedFromFile(..SeedPath), "the seed is taken")
    Do ..AssertNoDemoReceiver("a site's file")
    Do $$$AssertTrue($ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver("Bed Mgmt Out")), "its own receiver stays")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Current().receivers.%Size(), 1, "with no stand-in")
    Do ..AssertNoAutomatic("a site's file")
}

/// No profile stored at all (an install with no module root): the fallback is as careful as the seed.
Method TestNonDemoWithNoProfile()
{
    Set ^Shutter.Config("demo") = 0
    Do ..HideProfile()
    Do ..AssertNoDemoReceiver("no profile")
    Do ..AssertNoAutomatic("no profile")
}

/// An install of v1.0.0 still on the seed follows the seed; a profile a person saved is theirs, automatic included.
Method TestNonDemoUpgrade()
{
    Set ^Shutter.Config("demo") = 0
    Do ..StoredAsTheSeed()
    Set old = ..WriteSeed()
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(old, ..SeedPath, "install", "", .v), "the old seed, stored")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).SeedFromFile(..SeedPath), "the seed again")
    Do ..AssertNoDemoReceiver("upgraded")
    Do ..AssertNoAutomatic("upgraded")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(old, "api", "approver", "", .v), "a person's own profile")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).SeedFromFile(..SeedPath), "the seed again")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "automatic", "a person's choice stands")
    Do $$$AssertTrue($ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver("Downstream Out")), "and so does their list")
}

/// The demo's seed is exactly as it was.
Method TestDemoSeed()
{
    Set ^Shutter.Config("demo") = 1
    Do ..StoredAsTheSeed()
    Do ..WriteSeed()
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).SeedFromFile(..SeedPath), "the seed is taken")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "automatic", "tier 2 single stays automatic")
    Do $$$AssertTrue($ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver("Downstream Out")), "Downstream Out stays")
    Do $$$AssertTrue($ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver("Records Out")), "Records Out stays")
    Do ..HideProfile()
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "automatic", "and with no profile stored")
}

}
