/// Time zones through Embedded Python's zoneinfo (Shutter.Util.Time, CONTRACTS 6.4, v1.30): any IANA zone the IRIS image's
/// database knows gives timestamps without an offset their UTC reading, beside the native rules for UTC, Europe/London and
/// fixed offsets. On an image without Embedded Python or the database the native rules stand alone, and these tests say so
/// instead of failing.
Class Shutter.Test.Zones Extends %UnitTest.TestCase
{

Method TestZoneinfoOffsets()
{
    If '##class(Shutter.Util.Time).PythonZones() {
        Do $$$AssertTrue(1, "Embedded Python's zoneinfo does not answer on this image: the native rules stand alone, nothing more to test")
        Quit
    }
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("America/New_York", "2026-07-01T12:00:00"), "-0400", "New York in summer")
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("America/New_York", "2026-01-15T12:00:00"), "-0500", "New York in winter")
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("Australia/Sydney", "2026-01-15T12:00:00"), "+1100", "Sydney in its summer")
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("Australia/Sydney", "2026-07-01T12:00:00"), "+1000", "Sydney in its winter")
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("Asia/Kolkata", "2026-07-01T12:00:00"), "+0530", "a half-hour zone")
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("Europe/Paris", "2026-10-15T09:20:00"), "+0200", "Paris in summer time")
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("Europe/Paris", "2026-12-15T09:20:00"), "+0100", "Paris in winter")
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("Etc/UTC", "2026-07-01T12:00:00"), "", "a zone at UTC gives no offset")
    Do $$$AssertEquals(##class(Shutter.Util.Time).FromHL7("20261015092000", "Europe/Paris"), "2026-10-15T07:20:00Z", "an HL7 time read in Paris")
    Do $$$AssertEquals(##class(Shutter.Util.Time).FromHL7("20261015092000", "America/New_York"), "2026-10-15T13:20:00Z", "an HL7 time read in New York")
    Do $$$AssertEquals(##class(Shutter.Util.Time).FromHL7("20261015092000+0200", "America/New_York"), "2026-10-15T07:20:00Z", "a time with its own offset ignores the zone")
    Do $$$AssertTrue(##class(Shutter.Util.Time).KnownZone("America/New_York"), "New York is known")
    Do $$$AssertTrue(##class(Shutter.Util.Time).KnownZone("Europe/Paris"), "Paris is known")
}

Method TestNativeRulesStand()
{
    Do $$$AssertEquals(##class(Shutter.Util.Time).FromHL7("20261015092000", "Europe/London"), "2026-10-15T08:20:00Z", "London keeps its own rule")
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("Europe/London", "2026-03-29T01:30:00"), "+0100", "the skipped hour reads as summer time, as before")
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("+05:30", "2026-07-01T12:00:00"), "+0530", "a fixed offset")
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("UTC", "2026-07-01T12:00:00"), "", "UTC")
    Do $$$AssertNotTrue(##class(Shutter.Util.Time).KnownZone("Mars/Olympus"), "a zone nobody knows")
    Do $$$AssertEquals(##class(Shutter.Util.Time).ZoneOffset("Mars/Olympus", "2026-07-01T12:00:00"), "", "and it reads as UTC")
    Do $$$AssertNotTrue(##class(Shutter.Util.Time).KnownZone("Europe/Paris; drop table"), "a zone name with other characters is not looked up")
}

/// The site profile accepts any zone Shutter knows, and refuses one nobody does.
Method TestProfileValidation()
{
    Set profile = ##class(Shutter.Util.Json).Parse(##class(Shutter.Store.SiteProfile).Current().%ToJSON(), .sc)
    Do $$$AssertTrue($ISOBJECT(profile), "a profile is seeded")
    Set profile.feed."time_zone" = "Mars/Olympus"
    Set problem = ##class(Shutter.Store.SiteProfile).Validate(profile)
    Do $$$AssertTrue(problem [ "feed.time_zone", "an unknown zone is refused: " _ problem)
    Set profile.feed."time_zone" = "+01:00"
    Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(profile), "", "a fixed offset is accepted")
    Set profile.feed."time_zone" = "+15:00"
    Do $$$AssertTrue(##class(Shutter.Store.SiteProfile).Validate(profile) [ "feed.time_zone", "an offset beyond 14:00 is refused")
    If ##class(Shutter.Util.Time).PythonZones() {
        Set profile.feed."time_zone" = "Europe/Paris"
        Do $$$AssertEquals(##class(Shutter.Store.SiteProfile).Validate(profile), "", "an IANA zone the image knows is accepted")
    }
}

}
