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

/// A UTC time within an hour of a clock change, in any zone: the hour either side of it reads a different offset. A fixed
/// offset, UTC and a zone Shutter doesn't know have no clock change to be near; London needs no Embedded Python.
Method TestNearClockChange()
{
    Set t = "Shutter.Util.Time"
    Do $$$AssertTrue($CLASSMETHOD(t, "NearClockChange", "Europe/London", "2026-10-25T01:30:00Z"), "London, by its own rule")
    Do $$$AssertNotTrue($CLASSMETHOD(t, "NearClockChange", "Europe/London", "2026-10-25T03:00:00Z"), "London, two hours after")
    Do $$$AssertNotTrue($CLASSMETHOD(t, "NearClockChange", "UTC", "2026-10-25T01:30:00Z"), "UTC")
    Do $$$AssertNotTrue($CLASSMETHOD(t, "NearClockChange", "", "2026-10-25T01:30:00Z"), "no zone")
    Do $$$AssertNotTrue($CLASSMETHOD(t, "NearClockChange", "+01:00", "2026-10-25T01:30:00Z"), "a fixed offset")
    Do $$$AssertNotTrue($CLASSMETHOD(t, "NearClockChange", "Mars/Olympus", "2026-10-25T01:30:00Z"), "a zone nobody knows")
    Do $$$AssertNotTrue($CLASSMETHOD(t, "NearClockChange", "Europe/Paris; drop table", "2026-10-25T01:30:00Z"), "a zone name with other characters is not looked up")
    If '$CLASSMETHOD(t, "PythonZones") {
        Do $$$AssertTrue(1, "Embedded Python's zoneinfo does not answer on this image: the native rules stand alone, nothing more to test")
        Quit
    }
    // New York's clocks go back at 06:00Z on 1 November 2026: local 01:10 the second time reads as 05:10Z with the first offset.
    Do $$$AssertEquals($CLASSMETHOD(t, "FromHL7", "20261101011000", "America/New_York"), "2026-11-01T05:10:00Z", "the repeated hour reads with the first offset")
    Do $$$AssertTrue($CLASSMETHOD(t, "NearClockChange", "America/New_York", "2026-11-01T05:10:00Z"), "New York, the repeated hour")
    Do $$$AssertTrue($CLASSMETHOD(t, "NearClockChange", "America/New_York", "2026-11-01T06:30:00Z"), "New York, after the change")
    Do $$$AssertNotTrue($CLASSMETHOD(t, "NearClockChange", "America/New_York", "2026-11-01T08:10:00Z"), "New York, two hours after")
    Do $$$AssertNotTrue($CLASSMETHOD(t, "NearClockChange", "America/New_York", "2026-07-01T12:00:00Z"), "New York in summer")
    Do $$$AssertTrue($CLASSMETHOD(t, "NearClockChange", "America/New_York", "2026-03-08T07:30:00Z"), "New York, the skipped hour")
    Do $$$AssertTrue($CLASSMETHOD(t, "NearClockChange", "Europe/Paris", "2026-10-25T00:30:00Z"), "Paris, the repeated hour")
    Do $$$AssertTrue($CLASSMETHOD(t, "NearClockChange", "Europe/Paris", "2026-03-29T01:30:00Z"), "Paris, the skipped hour")
    Do $$$AssertTrue($CLASSMETHOD(t, "NearClockChange", "Australia/Sydney", "2026-04-04T15:30:00Z"), "Sydney, the repeated hour of its autumn")
    Do $$$AssertTrue($CLASSMETHOD(t, "NearClockChange", "Europe/Belfast", "2026-10-25T00:30:00Z"), "another name for British time")
    Do $$$AssertNotTrue($CLASSMETHOD(t, "NearClockChange", "Asia/Kolkata", "2026-10-25T00:30:00Z"), "a zone with no clock change")
    Do $$$AssertNotTrue($CLASSMETHOD(t, "NearClockChange", "Etc/UTC", "2026-10-25T00:30:00Z"), "UTC under its zone name")
    Do $$$AssertNotTrue($CLASSMETHOD(t, "NearClockChange", "Europe/Paris", "not a time"), "a time that doesn't read")
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

/// Digits that make no date or time (30 February, a thirteenth month, 24:00:00) read as no time at all, "", in every
/// zone and with an offset of their own, never as an error; the interval helpers answer "" for them too.
/// In a watched namespace neither the cached zone nor the site profile is there: the zone the caller set before it moved
/// (^||Shutter.FeedZone) is read instead, so a time without an offset reads in the feed's zone and the read doesn't fail.
Method TestTheZoneCarriedIntoAWatchedNamespace()
{
    Set cached = $GET(^Shutter.Config("feedZone"))
    Kill ^Shutter.Config("feedZone")
    Set ^||Shutter.FeedZone = "UTC"
    Do $$$AssertEquals(##class(Shutter.Util.Time).FromHL7("20260715100000"), "2026-07-15T10:00:00Z", "read in the carried zone, UTC")
    Set ^||Shutter.FeedZone = "Europe/London"
    Do $$$AssertEquals(##class(Shutter.Util.Time).FromHL7("20260715100000"), "2026-07-15T09:00:00Z", "read in the carried zone, London in summer")
    Set ^Shutter.Config("feedZone") = "UTC"
    Do $$$AssertEquals(##class(Shutter.Util.Time).FromHL7("20260715100000"), "2026-07-15T10:00:00Z", "the namespace's own cached zone comes first")
    Kill ^||Shutter.FeedZone
    If cached = "" { Kill ^Shutter.Config("feedZone") } Else { Set ^Shutter.Config("feedZone") = cached }
}

Method TestImpossibleDateReadsAsNoTime()
{
    For ts = "20260230120000", "20261301120000", "20260701240000" {
        Do $$$AssertEquals(##class(Shutter.Util.Time).FromHL7(ts, "UTC"), "", ts _ " in UTC")
        Do $$$AssertEquals(##class(Shutter.Util.Time).FromHL7(ts, "Europe/London"), "", ts _ " in Europe/London")
        Do $$$AssertEquals(##class(Shutter.Util.Time).FromHL7(ts _ "+0100", "UTC", .had), "", ts _ " with its own offset")
        Do $$$AssertNotTrue(had, ts _ " with its own offset reports none")
    }
    Do $$$AssertEquals(##class(Shutter.Util.Time).FromHL7("20260228235959", "UTC"), "2026-02-28T23:59:59Z", "the last second of February still reads")
    Do $$$AssertEquals(##class(Shutter.Util.Time).SecondsBetween("2026-02-30T12:00:00Z", "2026-03-01T12:00:00Z"), "", "no seconds from a date that does not exist")
    Do $$$AssertEquals(##class(Shutter.Util.Time).SecondsBetween("2026-03-01T12:00:00Z", "not a time"), "", "nor to text that is no time")
    Do $$$AssertEquals(##class(Shutter.Util.Time).SecondsBetween("2026-03-01T12:00:00Z", "2026-03-01T12:00:30Z"), 30, "a real interval still counts")
    Do $$$AssertEquals(##class(Shutter.Util.Time).MillisBetween("2026-02-30T12:00:00Z", "2026-03-01T12:00:00Z"), "", "no milliseconds from it either")
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
