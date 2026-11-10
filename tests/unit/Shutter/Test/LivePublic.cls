/// The live hospital's public copy (CONTRACTS 4.4 and 12, 1.4.2): the anonymous GET /health of the hardened demo can't read
/// the hospital's database, so it reads the switch and the cadence from ^Shutter.Live("public"), which the player, the live
/// switch and LiveStatus write. The copy holds those two values and its time, nothing else of the player; a stale copy
/// counts as unknown. Every global a test touches is put back as it was.
Class Shutter.Test.LivePublic Extends %UnitTest.TestCase
{

Property Kept As %String [ MultiDimensional ];

Method OnBeforeOneTest(testname As %String) As %Status
{
    Kill ..Kept
    Merge ..Kept("public") = ^Shutter.Live("public")
    Merge ..Kept("config") = ^Hospital.Config
    Merge ..Kept("live") = ^Hospital.Live
    Kill ^Shutter.Live("public")
    Quit $$$OK
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Kill ^Shutter.Live("public"), ^Hospital.Config, ^Hospital.Live
    Merge ^Shutter.Live("public") = ..Kept("public")
    Merge ^Hospital.Config = ..Kept("config")
    Merge ^Hospital.Live = ..Kept("live")
    Kill ..Kept
    Quit $$$OK
}

/// The copy's own text: the switch, the cadence when it is a whole number above 0, and the time; no other key.
Method TestTheCopyHoldsTheTwoValuesAndItsTime()
{
    Set c = {}.%FromJSON(##class(Shutter.Util.LivePublic).CopyText(1, 7, 1000))
    Do $$$AssertEquals(c.%ToJSON(), "{""enabled"":true,""every_minutes"":7,""at"":1000}", "enabled, every_minutes and at")
    Set c = {}.%FromJSON(##class(Shutter.Util.LivePublic).CopyText(0, "", 1000))
    Do $$$AssertEquals(c.%ToJSON(), "{""enabled"":false,""at"":1000}", "no cadence known: no every_minutes")
    Set c = {}.%FromJSON(##class(Shutter.Util.LivePublic).CopyText(1, "0", 1000))
    Do $$$AssertEquals(c.%IsDefined("every_minutes"), 0, "a cadence of 0 is no cadence")
}

/// The reader gives enabled and every_minutes alone, never the time, while the copy is within three of its periods.
Method TestAFreshCopyReadsAsTheTwoValues()
{
    Set now = 1000000
    Set l = ##class(Shutter.Util.LivePublic).FromCopy("{""enabled"":true,""every_minutes"":7,""at"":" _ (now - 60) _ "}", now)
    Do $$$AssertTrue($ISOBJECT(l), "a copy a minute old is read")
    Do $$$AssertEquals(l.%ToJSON(), "{""enabled"":true,""every_minutes"":7}", "as the two values, without its time")
    Set l = ##class(Shutter.Util.LivePublic).FromCopy("{""enabled"":false,""every_minutes"":7,""at"":" _ now _ "}", now)
    Do $$$AssertEquals(l.%ToJSON(), "{""enabled"":false,""every_minutes"":7}", "a hospital switched off reads as off")
    Set l = ##class(Shutter.Util.LivePublic).FromCopy("{""enabled"":true,""at"":" _ now _ ",""scenarios"":""S2"",""last_played"":{}}", now)
    Do $$$AssertEquals(l.%ToJSON(), "{""enabled"":true}", "anything else in the text is never passed on")
}

/// A copy older than three of the player's periods is unknown: a player that has stopped advertises nothing.
Method TestAStaleCopyIsUnknown()
{
    Set now = 1000000
    Set edge = 3 * 7 * 60
    Set l = ##class(Shutter.Util.LivePublic).FromCopy("{""enabled"":true,""every_minutes"":7,""at"":" _ (now - edge) _ "}", now)
    Do $$$AssertTrue($ISOBJECT(l), "three periods old (21 minutes at 7): still good")
    Set l = ##class(Shutter.Util.LivePublic).FromCopy("{""enabled"":true,""every_minutes"":7,""at"":" _ (now - edge - 1) _ "}", now)
    Do $$$AssertEquals(l, "", "a second more: unknown")
    Set l = ##class(Shutter.Util.LivePublic).FromCopy("{""enabled"":true,""every_minutes"":2,""at"":" _ (now - 361) _ "}", now)
    Do $$$AssertEquals(l, "", "the period is the copy's own: 2 minutes goes stale after 6")
    Set l = ##class(Shutter.Util.LivePublic).FromCopy("{""enabled"":true,""at"":" _ (now - edge) _ "}", now)
    Do $$$AssertTrue($ISOBJECT(l), "no cadence: the shipped 7 minutes, so 21 minutes is still good")
    Set l = ##class(Shutter.Util.LivePublic).FromCopy("{""enabled"":true,""at"":" _ (now - edge - 1) _ "}", now)
    Do $$$AssertEquals(l, "", "and a second more is not")
    Set l = ##class(Shutter.Util.LivePublic).FromCopy("{""enabled"":false,""every_minutes"":7,""at"":" _ (now - edge - 1) _ "}", now)
    Do $$$AssertEquals(l, "", "a stale off is unknown too")
}

/// No copy, an unreadable one, one with no time or a time that is not a number: unknown.
Method TestAMissingOrBrokenCopyIsUnknown()
{
    For text = "", "   ", "not json", "[1,2]", "{""enabled"":true,""every_minutes"":7}", "{""enabled"":true,""at"":""soon""}" {
        Do $$$AssertEquals(##class(Shutter.Util.LivePublic).FromCopy(text, 1000000), "", "unknown: " _ text)
    }
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Read(), "", "no copy in this namespace: Read gives nothing")
}

/// The writer and the reader through the global, in this namespace by "" and by its name.
Method TestTheWriterAndTheReader()
{
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Write("", 1, 7), 1, "written")
    Set c = {}.%FromJSON(^Shutter.Live("public"))
    Do $$$AssertTrue((##class(Shutter.Util.Time).EpochSeconds() - c.at) < 5, "stamped now")
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Read().%ToJSON(), "{""enabled"":true,""every_minutes"":7}", "and read back as the two values")
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Write($NAMESPACE, 0, 5), 1, "written by the namespace's name")
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Read().%ToJSON(), "{""enabled"":false,""every_minutes"":5}", "the switch off reads at once")
    Do ##class(Shutter.Util.LivePublic).Write("", 1, 7, ##class(Shutter.Util.Time).EpochSeconds() - 3600)
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Read(), "", "an hour old at 7 minutes: unknown")
}

/// LiveStatus's refresh writes only when the copy says otherwise, so a reader never renews the player's heartbeat.
Method TestARefreshWritesOnlyOnAChange()
{
    Set old = ##class(Shutter.Util.Time).EpochSeconds() - 100
    Do ##class(Shutter.Util.LivePublic).Write("", 1, 7, old)
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Refresh({"enabled": true, "every_minutes": 7, "scenarios": "S2"}), 0, "the same values: nothing written")
    Do $$$AssertEquals({}.%FromJSON(^Shutter.Live("public")).at, old, "and the copy keeps its time")
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Refresh({"enabled": false, "every_minutes": 7}), 1, "switched off: written")
    Set c = {}.%FromJSON(^Shutter.Live("public"))
    Do $$$AssertEquals(c.enabled _ "|" _ c."every_minutes", "0|7", "as off")
    Do $$$AssertNotEquals(c.at, old, "stamped now")
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Refresh({"enabled": false, "every_minutes": 5}), 1, "a new cadence: written")
    Kill ^Shutter.Live("public")
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Refresh({"enabled": true}), 1, "no copy yet: written")
    Do $$$AssertEquals(^Shutter.Live("public") [ "every_minutes", 0, "with no cadence when the status had none")
    Set c = {}.%FromJSON(^Shutter.Live("public"))
    Do $$$AssertEquals(c.%Size(), 2, "only enabled and at")
}

/// The anonymous answer: from the hospital's status when it was read, with nothing of the player but the two values;
/// else from the copy; else nothing, so the route leaves the live key out.
Method TestTheAnonymousAnswer()
{
    Set full = {"enabled": true, "every_minutes": 7, "scenarios": "S2,S8", "last_played": {"scenario": "S2"}, "next": {"scenario": "S8"}, "last_ordinary": "x", "storm": {"state": "done"}}
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Anonymous(full, 1).%ToJSON(), "{""enabled"":true,""every_minutes"":7}", "read: the two values alone")
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Anonymous({"enabled": false}, 1).%ToJSON(), "{""enabled"":false}", "read and off, no player yet: enabled false")
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Anonymous({"enabled": false}, 0), "", "not read and no copy: nothing")
    Do ##class(Shutter.Util.LivePublic).Write("", 1, 7)
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Anonymous({"enabled": false}, 0).%ToJSON(), "{""enabled"":true,""every_minutes"":7}", "not read: the copy, so the hardened demo's sign-in page learns the hospital is on")
    Do ##class(Shutter.Util.LivePublic).Write("", 1, 7, ##class(Shutter.Util.Time).EpochSeconds() - 3600)
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Anonymous({"enabled": false}, 0), "", "not read and the copy stale: nothing")
}

/// The player writes the copy on every round, beside its status; the live switch's helper writes the switch as it stands
/// with the cadence of the player's last status. Both into the namespace named (here this one).
Method TestThePlayerAndTheSwitchWriteTheCopy()
{
    Kill ^Hospital.Config, ^Hospital.Live
    Set ^Hospital.Config("live") = 1, ^Hospital.Config("liveScenarios") = "S2,S8"
    Set player = ##class(Hospital.LivePlayer).%New("Live PAS")
    Set player.ShutterNamespace = $NAMESPACE, player.EveryMinutes = 5
    Do player.WriteStatus()
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Read().%ToJSON(), "{""enabled"":true,""every_minutes"":5}", "the player's round wrote the copy")
    Set status = {}.%FromJSON(^Hospital.Live("status"))
    Do $$$AssertEquals(status.scenarios, "S2,S8", "beside its own status, as before")
    Set ^Hospital.Config("live") = 0
    Do $$$AssertEquals(##class(Hospital.Setup).WritePublicLive($NAMESPACE), 1, "the switch's helper wrote")
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Read().%ToJSON(), "{""enabled"":false,""every_minutes"":5}", "off at once, the cadence from the player's status")
    Kill ^Hospital.Live("status")
    Set ^Hospital.Config("live") = 1
    Do ##class(Hospital.Setup).WritePublicLive($NAMESPACE)
    Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Read().%ToJSON(), "{""enabled"":true}", "no status yet: on, with no cadence")
}

/// LiveStatus says whether it read the hospital: not with no hospital namespace recorded; and when it reads one, it
/// refreshes the copy. The hospital here is this namespace, with its globals set by the test.
Method TestLiveStatusSaysWhetherItReadTheHospital()
{
    Set hospital = $GET(^Shutter.Config("hospitalNamespace")), had = $DATA(^Shutter.Config("hospitalNamespace"))
    Try {
        Kill ^Shutter.Config("hospitalNamespace")
        Set s = ##class(Shutter.Setup).LiveStatus(.read)
        Do $$$AssertEquals(read _ "|" _ s.%ToJSON(), "0|{""enabled"":false}", "no hospital: not read, enabled false")
        Set ^Shutter.Config("hospitalNamespace") = "NO_SUCH_NAMESPACE_142"
        Set s = ##class(Shutter.Setup).LiveStatus(.read)
        Do $$$AssertEquals(read, 0, "a hospital that can't be read: not read")
        Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Read(), "", "and no copy written")
        Kill ^Hospital.Config, ^Hospital.Live
        Set ^Shutter.Config("hospitalNamespace") = $NAMESPACE
        Set ^Hospital.Config("live") = 1, ^Hospital.Live("status") = "{""enabled"":true,""every_minutes"":7,""scenarios"":""S2""}"
        Set s = ##class(Shutter.Setup).LiveStatus(.read, 0)
        Do $$$AssertEquals(read _ "|" _ s."every_minutes", "1|7", "read, with the player's status")
        Do $$$AssertEquals(##class(Shutter.Util.LivePublic).Read().%ToJSON(), "{""enabled"":true,""every_minutes"":7}", "and the copy written from it")
    } Catch ex {
        Do $$$AssertFailure("LiveStatus threw: " _ ex.DisplayString())
    }
    Kill ^Shutter.Config("hospitalNamespace")
    If had Set ^Shutter.Config("hospitalNamespace") = hospital
}

}
