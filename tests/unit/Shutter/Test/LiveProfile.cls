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
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).FurtherMovement(), "show", "a site install lets another visit's movement show, as shipped")
    // A demo install keeps the demo's own table, labelled.
    Do $$$AssertStatusOK(##class(Shutter.Setup).DemoProfilePolicy(seed, 1), "a demo install: the demo's policy applies")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "automatic", "tier 2 single is the demo's automatic release")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(1, "ordered"), "automatic", "tier 1 ordered too")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(3, "ordered"), "per_chain", "tier 3 ordered per chain, as the demo had it")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Source, seed _ " (demo)", "the source says whose answers they are")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).FurtherMovement(), "stop", "the demo keeps the stop for another visit's movement, as it had it")
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
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).FurtherMovement(), "stop", "and the live hospital keeps the demo's stop")
    Set version = row.Version
    Do $$$AssertStatusOK(##class(Shutter.Setup).LiveProfilePolicy(seed, 1), "again: idempotent")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Version, version, "and the version did not move")
    // A demo profile stored before the demo kept its own stop (the demo's policy, no further_messages): a reinstall adds it.
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Set p.policy = ##class(Shutter.Store.SiteProfile).DemoPolicy()
    Do p.%Remove("further_messages")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), seed _ " (demo)", "test", "", .v), "an older demo profile")
    Set demo = $GET(^Shutter.Config("demo")), ^Shutter.Config("demo") = 1
    Set reading = ##class(Shutter.Store.SiteProfile).FurtherMovement()
    If demo = "" { Kill ^Shutter.Config("demo") } Else { Set ^Shutter.Config("demo") = demo }
    Do $$$AssertEquals(reading, "stop", "a demo instance reads stop even before the install writes it")
    Do $$$AssertStatusOK(##class(Shutter.Setup).DemoProfilePolicy(seed, 1), "a reinstall of the demo")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).FurtherMovement(), "stop", "and the demo's stop is back")
    // An older live hospital's profile (its own tier 2, no further_messages): a reinstall adds the demo's stop and nothing else.
    Set tier2 = p.policy.%Get("2"), tier2.single = "approval"
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), seed _ " (demo) (live hospital)", "test", "", .v), "an older live hospital's profile")
    Do $$$AssertStatusOK(##class(Shutter.Setup).DemoProfilePolicy(seed, 1), "a reinstall of the live hospital")
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).FurtherMovement(), "stop", "the demo's stop is back")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "approval", "and the live hospital's tier 2 stands")
    Do $$$AssertEquals(row.Source, seed _ " (demo) (live hospital)", "with its mark")
    Set version = row.Version
    Do $$$AssertStatusOK(##class(Shutter.Setup).DemoProfilePolicy(seed, 1), "again: idempotent")
    Do $$$AssertStatusOK(##class(Shutter.Setup).LiveProfilePolicy(seed, 1), "and the live policy after it")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Version, version, "the version did not move")
    // A person's own profile is theirs.
    Set p = ##class(Shutter.Store.SiteProfile).Default()
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(p.%ToJSON(), "api", "approver", "", .v), "a profile a person saved")
    Do $$$AssertStatusOK(##class(Shutter.Setup).DemoProfilePolicy(seed, 1), "a demo install, but not the seed's profile")
    Do $$$AssertStatusOK(##class(Shutter.Setup).LiveProfilePolicy(seed, 1), "on, but not the seed's profile")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Policy(2, "single"), "approval", "left alone: the person's own answer stands")
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Row().Source, "api", "and the source is theirs")
}

/// Existing sites keep stop (1.2.0, Shutter.Setup.KeepStopOnUpgrade): an install over a site from before 1.2.0 whose stored
/// profile does not name further_messages.in_patient_movement stores stop, with the source saying why; the seed then keeps
/// it; a profile that names the setting, a new install, a reinstall of 1.2.0 and a demo install are left as they were.
Method TestKeepStopOnUpgrade()
{
    Set sp = "Shutter.Store.SiteProfile", setup = "Shutter.Setup"
    Set kept = $PARAMETER(sp, "KEPTSTOP")
    Set row = $CLASSMETHOD(sp, "Row")
    Set savedVersion = $SELECT($ISOBJECT(row): row.Version, 1: 0), savedJson = $SELECT($ISOBJECT(row): row.Json, 1: ""), savedSource = $SELECT($ISOBJECT(row): row.Source, 1: "")
    Set demo = $GET(^Shutter.Config("demo")), ^Shutter.Config("demo") = 0
    Set dir = ##class(%File).NormalizeDirectory(##class(%SYS.System).TempDirectory() _ "shutter-keep-stop")
    Do ##class(%File).CreateDirectoryChain(dir)
    Set seed = dir _ "profile.json"
    // The 1.2.0 seed: the shipped profile, which says show.
    Set file = ##class(%Stream.FileCharacter).%New()
    Do file.LinkToFile(seed)
    Do file.Write(##class(Shutter.Store.SiteProfile).Default().%ToJSON())
    Do $$$AssertStatusOK(file.%Save(), "the 1.2.0 seed written")
    Kill file
    // A 1.1.1 site: the seed's profile of then, which did not name the setting and so read stop.
    Set old = ##class(Shutter.Store.SiteProfile).Default()
    Do old.%Remove("further_messages")
    Do $$$AssertStatusOK($CLASSMETHOD(sp, "Store", old.%ToJSON(), seed, "test", "", .v), "a 1.1.1 seed's profile without the setting")
    Do $$$AssertEquals($CLASSMETHOD(sp, "FurtherMovement"), "show", "read by 1.2.0 before the install step it would show")
    Set before = $CLASSMETHOD(sp, "Row").Version
    Do $$$AssertStatusOK($CLASSMETHOD(setup, "KeepStopOnUpgrade", "1.1.1", 0), "the install step over 1.1.1")
    Set row = $CLASSMETHOD(sp, "Row")
    Do $$$AssertEquals($CLASSMETHOD(sp, "FurtherMovement"), "stop", "the upgraded site keeps its stop")
    Do $$$AssertEquals(row.Source, seed _ kept, "the source says why: " _ row.Source)
    Do $$$AssertEquals(row.Version, before + 1, "a new version")
    Set hist = ##class(Shutter.Store.SiteProfileVersion).VersionIdxOpen(row.Version)
    Do $$$AssertEquals($SELECT($ISOBJECT(hist): hist.Source, 1: ""), seed _ kept, "kept in the history with its source")
    Do $$$AssertStatusOK($CLASSMETHOD(setup, "KeepStopOnUpgrade", "1.1.1", 0), "again")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Row").Version, row.Version, "the setting is named now, so nothing moves")
    // The seed that follows on the same install still follows its file, and keeps the stop.
    Do $$$AssertStatusOK($CLASSMETHOD(sp, "SeedFromFile", seed), "the 1.2.0 seed over the kept profile")
    Set row = $CLASSMETHOD(sp, "Row")
    Do $$$AssertEquals($CLASSMETHOD(sp, "FurtherMovement"), "stop", "the seed keeps the stop")
    Do $$$AssertEquals(row.Source, seed _ kept, "and the source")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Current").%Get("further_messages").%Get("admission_not_found"), "person", "and takes the rest of the seed")
    // A profile a person saved before 1.2.0 without the setting keeps its stop too.
    Do $$$AssertStatusOK($CLASSMETHOD(sp, "Store", old.%ToJSON(), "api", "approver", "", .v), "a person's 1.1.1 profile without the setting")
    Do $$$AssertStatusOK($CLASSMETHOD(setup, "KeepStopOnUpgrade", "", 0), "the install step over an install that recorded no version")
    Do $$$AssertEquals($CLASSMETHOD(sp, "FurtherMovement"), "stop", "the person's site keeps its stop")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Row").Source, "api" _ kept, "with their source and why")
    // A reinstall of 1.2.0: nothing to keep.
    Do $$$AssertStatusOK($CLASSMETHOD(sp, "Store", old.%ToJSON(), "api", "approver", "", .v), "a profile without the setting saved on 1.2.0")
    Set before = $CLASSMETHOD(sp, "Row").Version
    Do $$$AssertStatusOK($CLASSMETHOD(setup, "KeepStopOnUpgrade", "1.2.0", 0), "a reinstall of 1.2.0")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Row").Version, before, "left alone")
    Do $$$AssertEquals($CLASSMETHOD(sp, "FurtherMovement"), "show", "and it reads the shipped show")
    // A stored profile that says show keeps show.
    Set shows = ##class(Shutter.Store.SiteProfile).Default()
    Do $$$AssertStatusOK($CLASSMETHOD(sp, "Store", shows.%ToJSON(), "api", "approver", "", .v), "a profile that says show")
    Set before = $CLASSMETHOD(sp, "Row").Version
    Do $$$AssertStatusOK($CLASSMETHOD(setup, "KeepStopOnUpgrade", "1.1.1", 0), "the install step over 1.1.1")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Row").Version, before, "left alone")
    Do $$$AssertEquals($CLASSMETHOD(sp, "FurtherMovement"), "show", "it keeps show")
    // A demo install changes nothing here, and the demo still reads stop.
    Do $$$AssertStatusOK($CLASSMETHOD(sp, "Store", old.%ToJSON(), seed _ " (demo)", "test", "", .v), "a demo's profile without the setting")
    Set before = $CLASSMETHOD(sp, "Row").Version
    Do $$$AssertStatusOK($CLASSMETHOD(setup, "KeepStopOnUpgrade", "1.1.1", 1), "a demo install")
    Do $$$AssertEquals($CLASSMETHOD(sp, "Row").Version, before, "nothing stored by this step")
    Set ^Shutter.Config("demo") = 1
    Do $$$AssertEquals($CLASSMETHOD(sp, "FurtherMovement"), "stop", "the demo reads stop")
    Set ^Shutter.Config("demo") = 0
    // A new install: no stored profile, so nothing is written, and the shipped show applies.
    Set row = $CLASSMETHOD(sp, "Row")
    Do $CLASSMETHOD(sp, "%DeleteId", row.%Id())
    Do $$$AssertStatusOK($CLASSMETHOD(setup, "KeepStopOnUpgrade", "", 0), "the install step on a new instance")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(sp, "Row")), "nothing stored")
    Do $$$AssertEquals($CLASSMETHOD(sp, "FurtherMovement"), "show", "a new install reads the shipped show")
    // Put the profile back as it was, at the history's last version, so the next store is a new version.
    Set row = $CLASSMETHOD(sp, "Row")
    If '$ISOBJECT(row) Set row = ##class(Shutter.Store.SiteProfile).%New()
    Set last = 0
    &sql(SELECT MAX(Version) INTO :last FROM Shutter_Store.SiteProfileVersion)
    Set row.Version = $SELECT(+last > savedVersion: +last, 1: savedVersion), row.Json = savedJson, row.Source = savedSource
    If savedJson '= "" Do $$$AssertStatusOK(row.%Save(), "the profile put back")
    If demo = "" { Kill ^Shutter.Config("demo") } Else { Set ^Shutter.Config("demo") = demo }
    Do ##class(%File).Delete(seed)
}

}
