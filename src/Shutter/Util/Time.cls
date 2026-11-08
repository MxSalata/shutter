/// Time helpers. Every timestamp Shutter stores or sends is ISO 8601 in UTC with a trailing Z,
/// for example 2026-10-15T09:20:00Z, so values compare as strings. A timestamp without an offset is read in the feed's
/// zone: UTC, Europe/London and fixed offsets by the rules here, and any other IANA zone through Embedded Python's
/// zoneinfo (v1.30), the IANA database the IRIS image carries; where Embedded Python or the database is missing, the
/// native rules stand alone and such a zone reads as UTC with a warning, as before.
Class Shutter.Util.Time Extends %RegisteredObject
{

/// The current time, UTC, to the second.
ClassMethod NowUTC() As %String
{
    Set ts = $ZTIMESTAMP
    Quit $ZDATE(ts, 3) _ "T" _ $ZTIME($PIECE(ts, ",", 2) \ 1, 1) _ "Z"
}

/// The current time, UTC, with milliseconds.
ClassMethod NowUTCms() As %String
{
    Set ts = $ZTIMESTAMP
    Set secs = $PIECE(ts, ",", 2)
    Set ms = $JUSTIFY((secs - (secs \ 1)) * 1000 \ 1, 3)
    Set ms = $TRANSLATE(ms, " ", "0")
    Quit $ZDATE(ts, 3) _ "T" _ $ZTIME(secs \ 1, 1) _ "." _ ms _ "Z"
}

/// Milliseconds from a to b, both ISO UTC times with or without a fraction ("2026-11-02T01:02:03.456Z"); "" when either is
/// empty or unreadable.
ClassMethod MillisBetween(a As %String, b As %String) As %Integer
{
    Set ma = ..EpochMillis(a), mb = ..EpochMillis(b)
    If (ma = "") || (mb = "") Quit ""
    Quit mb - ma
}

/// An ISO UTC time with milliseconds, moved by a number of milliseconds (negative values go back); "" when unreadable.
ClassMethod PlusMillis(iso As %String, millis As %Integer) As %String
{
    Set m = ..EpochMillis(iso)
    If m = "" Quit ""
    Set m = m + +millis
    Set secs = m \ 1000, frac = m # 1000
    If frac < 0 Set frac = frac + 1000, secs = secs - 1
    Set days = secs \ 86400, rest = secs # 86400
    If rest < 0 Set rest = rest + 86400, days = days - 1
    Quit $ZDATE(days, 3) _ "T" _ $ZTIME(rest, 1) _ "." _ $TRANSLATE($JUSTIFY(frac, 3), " ", "0") _ "Z"
}

/// Milliseconds since the IRIS epoch of an ISO UTC time, or "" when it does not read.
ClassMethod EpochMillis(iso As %String) As %Integer [ Private ]
{
    If $GET(iso) = "" Quit ""
    Set base = $PIECE(iso, "Z", 1), frac = $PIECE(base, ".", 2), base = $PIECE(base, ".", 1)
    Set h = ""
    Try { Set h = $ZDATETIMEH($TRANSLATE(base, "T", " "), 3, 1) } Catch ex { Set h = "" }
    If h = "" Quit ""
    Set ms = $SELECT(frac = "": 0, 1: +$EXTRACT(frac _ "000", 1, 3))
    Quit (($PIECE(h, ",", 1) * 86400) + ($PIECE(h, ",", 2) \ 1)) * 1000 + ms
}

/// Seconds since the IRIS epoch, from the clock: for intervals that need no formatting.
ClassMethod EpochSeconds() As %Integer
{
    Quit $PIECE($HOROLOG, ",", 1) * 86400 + $PIECE($HOROLOG, ",", 2)
}

/// An ISO UTC time a number of seconds from now (negative values go back).
ClassMethod FromNow(seconds As %Integer) As %String
{
    Set ts = $ZTIMESTAMP
    Set h = $ZDATETIMEH($ZDATETIME(ts, 3, 1), 3, 1)
    Set total = ($PIECE(h, ",", 1) * 86400) + ($PIECE(h, ",", 2) \ 1) + seconds
    Set days = total \ 86400, secs = total # 86400
    Quit $ZDATE(days, 3) _ "T" _ $ZTIME(secs, 1) _ "Z"
}

/// An HL7 timestamp as ISO 8601 UTC. A timestamp with an offset is shifted by it; one without is read in the feed's
/// time zone (the site profile's feed.time_zone; UTC when it does not say): "UTC", "Europe/London" (British Summer
/// Time from the last Sunday of March at 01:00 UTC to the last Sunday of October at 01:00 UTC) or a fixed offset such
/// as "+01:00". hadOffset says whether the timestamp carried one.
ClassMethod FromHL7(ts As %String, zone As %String = "", Output hadOffset As %Boolean) As %String
{
    Set hadOffset = 0
    Set ts = $ZSTRIP(ts, "<>WC")
    If ts = "" Quit ""
    // An HL7 DTM: YYYYMMDD[HH[MM[SS[.S...]]]][+/-ZZZZ]; the offset is always four digits at the end. Anything else is
    // no time at all ("", never an error on the feed's path).
    Set offset = ""
    If $MATCH(ts, "^[0-9]+(\.[0-9]+)?[+-][0-9]{4}$") Set offset = $EXTRACT(ts, * - 4, *), ts = $EXTRACT(ts, 1, * - 5)
    Set ts = $PIECE(ts, ".", 1)
    If '$MATCH(ts, "^[0-9]{8}([0-9]{2}){0,3}$") Quit ""
    Set y = $EXTRACT(ts, 1, 4), mo = $EXTRACT(ts, 5, 6), d = $EXTRACT(ts, 7, 8)
    Set hh = $EXTRACT(ts, 9, 10), mi = $EXTRACT(ts, 11, 12), ss = $EXTRACT(ts, 13, 14)
    If hh = "" Set hh = "00"
    If mi = "" Set mi = "00"
    If ss = "" Set ss = "00"
    Set iso = y _ "-" _ mo _ "-" _ d _ "T" _ hh _ ":" _ mi _ ":" _ ss
    // The digits must make a real date and time: 30 February, month 13 or 24:00:00 are no time at all. $ZDATETIMEH
    // has no error option in this position, so the Try is the only guard; h is the $HOROLOG form for the shift below.
    Set h = ""
    Try { Set h = $ZDATETIMEH(iso, 3, 1) } Catch ex { Set h = "" }
    If h = "" Quit ""
    If offset = "" {
        // SQL hands an empty string over as $CHAR(0): both mean the profile's zone.
        If ($GET(zone) = "") || (zone = $CHAR(0)) Set zone = $GET(^Shutter.Config("feedZone"))
        // A read in a watched namespace, which maps Shutter.Util and not Shutter's store or configuration: the zone the
        // caller took before it went there (Shutter.Util.FurtherMessages.ReadSource).
        If zone = "" Set zone = $GET(^||Shutter.FeedZone)
        If zone = "" Set zone = ##class(Shutter.Store.SiteProfile).FeedTimeZone()
        Set offset = ..ZoneOffset(zone, iso)
        If offset = "" Quit iso _ "Z"
    } Else {
        Set hadOffset = 1
    }
    // Apply the offset so the result is UTC.
    Set sign = $EXTRACT(offset, 1), oh = +$EXTRACT(offset, 2, 3), om = +$EXTRACT(offset, 4, 5)
    Set shift = (oh * 3600) + (om * 60)
    Set total = ($PIECE(h, ",", 1) * 86400) + $PIECE(h, ",", 2)
    Set total = $SELECT(sign = "+": total - shift, 1: total + shift)
    Quit $ZDATE(total \ 86400, 3) _ "T" _ $ZTIME(total # 86400, 1) _ "Z"
}

/// The offset ("+HHMM" or "-HHMM") a zone gives a local time; "" for UTC. "Europe/London": +0100 in British Summer
/// Time (an ambiguous or skipped local time at the change itself is read as summer time). A zone Shutter does not
/// know is read as UTC, and a warning says so in the event log, once per process and zone.
ClassMethod ZoneOffset(zone As %String, localIso As %String) As %String
{
    Set zone = $ZSTRIP(zone, "<>W")
    If (zone = "") || ($ZCONVERT(zone, "U") = "UTC") || ($ZCONVERT(zone, "U") = "Z") || (zone = "+00:00") Quit ""
    If $MATCH(zone, "^[+-][0-9]{2}:?[0-9]{2}$") Quit $EXTRACT(zone, 1) _ $TRANSLATE($EXTRACT(zone, 2, *), ":", "")
    If zone = "Europe/London" Quit $SELECT(..InBritishSummerTime(localIso, 1): "+0100", 1: "")
    // Any other IANA zone through Embedded Python's zoneinfo (v1.30): the database's own rules, summer time included.
    Set off = ..PythonZoneOffset(zone, localIso, .known)
    If known Quit off
    If '$DATA(^||Shutter.UnknownZone(zone)) {
        Set ^||Shutter.UnknownZone(zone) = ""
        Try {
            Do ##class(Ens.Util.Log).LogWarning($CLASSNAME(), "ZoneOffset", "The feed time zone '" _ zone _ "' is not one Shutter knows (UTC, Europe/London or a fixed offset such as +01:00): times without an offset are read as UTC")
        } Catch {
        }
    }
    Quit ""
}

/// Whether ZoneOffset knows a zone: empty (UTC), UTC, Z, Europe/London, a fixed offset, or an IANA zone name that
/// Embedded Python's zoneinfo knows on this IRIS (v1.30).
ClassMethod KnownZone(zone As %String) As %Boolean
{
    Set zone = $ZSTRIP(zone, "<>W")
    If (zone = "") || $LISTFIND($LISTBUILD("UTC", "Z"), $ZCONVERT(zone, "U")) || (zone = "Europe/London") Quit 1
    If $MATCH(zone, "^[+-][0-9]{2}:?[0-9]{2}$") Quit 1
    Quit ..PythonZoneKnown(zone)
}

// ---- IANA zones through Embedded Python (v1.30) ----

/// The offset a zone gives a local time, through Embedded Python's zoneinfo: "+HHMM", "-HHMM", "" for none; "unknown"
/// when the zone is not in the IANA database; "unavailable" when zoneinfo cannot be used here. A local time that does not
/// exist (the hour skipped at a clock change) or exists twice reads with the first offset the database gives it.
ClassMethod PyOffset(zone As %String, y As %Integer, mo As %Integer, d As %Integer, hh As %Integer, mi As %Integer, ss As %Integer) As %String [ Language = python ]
{
    try:
        import datetime, zoneinfo
    except Exception:
        return "unavailable"
    try:
        tz = zoneinfo.ZoneInfo(str(zone))
    except Exception:
        return "unknown"
    try:
        local = datetime.datetime(int(y), int(mo), int(d), int(hh), int(mi), int(ss), tzinfo=tz)
        delta = local.utcoffset()
    except Exception:
        return "unavailable"
    secs = int(delta.total_seconds())
    if secs == 0:
        return ""
    sign = "+" if secs > 0 else "-"
    secs = abs(secs)
    return "%s%02d%02d" % (sign, secs // 3600, (secs % 3600) // 60)
}

/// Whether Embedded Python's zoneinfo answers on this IRIS, probed once per process with a zone whose answer is known.
/// The IRIS images carry Python 3 and the IANA database; a site's own build may not, and then the native rules stand alone.
ClassMethod PythonZones() As %Boolean
{
    If $DATA(^||Shutter.PythonZones) Quit ^||Shutter.PythonZones
    Set ok = 0
    Try { Set ok = (..PyOffset("Europe/London", 2026, 7, 1, 12, 0, 0) = "+0100") } Catch { Set ok = 0 }
    Set ^||Shutter.PythonZones = ok
    Quit ok
}

/// The offset zoneinfo gives a zone at a local ISO time (yyyy-mm-ddThh:mm:ss), "" for none; known says whether the zone
/// is in the database. A zone name is letters, digits, "/", "_", "+" and "-" only; anything else is unknown without a lookup.
ClassMethod PythonZoneOffset(zone As %String, localIso As %String, Output known As %Boolean) As %String
{
    Set known = 0
    If '$MATCH(zone, "^[A-Za-z0-9_+/-]{1,64}$") Quit ""
    If '..PythonZones() Quit ""
    Set r = "unavailable"
    Try {
        Set r = ..PyOffset(zone, +$EXTRACT(localIso, 1, 4), +$EXTRACT(localIso, 6, 7), +$EXTRACT(localIso, 9, 10), +$EXTRACT(localIso, 12, 13), +$EXTRACT(localIso, 15, 16), +$EXTRACT(localIso, 18, 19))
    } Catch {
        Set r = "unavailable"
    }
    If (r = "unknown") || (r = "unavailable") Quit ""
    Set known = 1
    Quit r
}

/// Whether zoneinfo knows a zone, cached per process and zone.
ClassMethod PythonZoneKnown(zone As %String) As %Boolean
{
    If $DATA(^||Shutter.ZoneKnown(zone)) Quit ^||Shutter.ZoneKnown(zone)
    Do ..PythonZoneOffset(zone, "2026-01-15T12:00:00", .known)
    Set ^||Shutter.ZoneKnown(zone) = ''known
    Quit ''known
}

/// Whether a time is in British Summer Time. The time is UTC, or local London time when local is 1 (then the hour
/// skipped in March reads as summer time and the repeated hour in October as summer time).
ClassMethod InBritishSummerTime(iso As %String, local As %Boolean = 0) As %Boolean
{
    Set y = +$EXTRACT(iso, 1, 4)
    If y = 0 Quit 0
    Set start = ..LastSunday(y, 3) _ "T01:00:00", end = ..LastSunday(y, 10) _ "T01:00:00"
    Set t = $PIECE(iso, "Z", 1)
    If local {
        // Summer time is local 01:00:00 on the March Sunday (the skipped hour reads as summer) up to, not including,
        // local 02:00:00 on the October Sunday; the repeated hour 01:00 to 01:59 reads as summer, the second time round
        // included.
        Set octLocal = ..LastSunday(y, 10) _ "T02:00:00"
        Quit ((t ]] start) || (t = start)) && '((t ]] octLocal) || (t = octLocal))
    }
    Quit ((t ]] start) || (t = start)) && '((t ]] end) || (t = end))
}

/// Whether a UTC time is within an hour of a British clock change (the order of two events across it is not safe).
ClassMethod NearBritishClockChange(iso As %String) As %Boolean
{
    Set y = +$EXTRACT(iso, 1, 4)
    If y = 0 Quit 0
    For change = ..LastSunday(y, 3) _ "T01:00:00Z", ..LastSunday(y, 10) _ "T01:00:00Z" {
        Set gap = ..SecondsBetween(change, iso)
        If (gap >= -3600) && (gap <= 3600) Quit
    }
    Quit (gap >= -3600) && (gap <= 3600)
}

/// Whether a UTC time is within an hour of a clock change in a zone, where a local time with no offset may be one that
/// night holds twice or not at all: London by its own rule, any other IANA zone through Embedded Python's zoneinfo, by
/// the offsets an hour either side. UTC, a fixed offset, a zone nobody knows and an IRIS without zoneinfo have no change
/// to be near.
ClassMethod NearClockChange(zone As %String, iso As %String) As %Boolean
{
    Set zone = $ZSTRIP(zone, "<>W")
    If (zone = "") || $LISTFIND($LISTBUILD("UTC", "Z"), $ZCONVERT(zone, "U")) || $MATCH(zone, "^[+-][0-9]{2}:?[0-9]{2}$") Quit 0
    If zone = "Europe/London" Quit ..NearBritishClockChange(iso)
    If '$MATCH(zone, "^[A-Za-z0-9_+/-]{1,64}$") || '$MATCH(iso, "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z") || '..PythonZones() Quit 0
    Set near = 0
    Try {
        Set near = ..PyNearChange(zone, +$EXTRACT(iso, 1, 4), +$EXTRACT(iso, 6, 7), +$EXTRACT(iso, 9, 10), +$EXTRACT(iso, 12, 13), +$EXTRACT(iso, 15, 16), +$EXTRACT(iso, 18, 19))
    } Catch {
        Set near = 0
    }
    Quit ''near
}

/// 1 when a zone's offset differs between an hour before and an hour after a UTC time, else 0, and 0 for a zone or a time
/// that can't be read.
ClassMethod PyNearChange(zone As %String, y As %Integer, mo As %Integer, d As %Integer, hh As %Integer, mi As %Integer, ss As %Integer) As %Integer [ Language = python ]
{
    try:
        import datetime, zoneinfo
        tz = zoneinfo.ZoneInfo(str(zone))
        at = datetime.datetime(int(y), int(mo), int(d), int(hh), int(mi), int(ss), tzinfo=datetime.timezone.utc)
        hour = datetime.timedelta(hours=1)
        return 1 if (at - hour).astimezone(tz).utcoffset() != (at + hour).astimezone(tz).utcoffset() else 0
    except Exception:
        return 0
}

/// The last Sunday of a month, as YYYY-MM-DD.
ClassMethod LastSunday(year As %Integer, month As %Integer) As %String
{
    Set last = $ZDATEH(year _ "-" _ $SELECT(month = 12: "12-31", 1: $TRANSLATE($JUSTIFY(month + 1, 2), " ", "0") _ "-01"), 3)
    If month '= 12 Set last = last - 1
    // $ZDATE(h, 10) is the day of the week, 0 for Sunday.
    Set dow = +$ZDATE(last, 10)
    Quit $ZDATE(last - dow, 3)
}

/// A probe for tests and the terminal: how a timestamp reads in a zone, the zone a time without an offset is read in and
/// whether Shutter knows it, and the clock-change facts, as JSON.
ClassMethod Probe(ts As %String, zone As %String = "") As %String [ SqlProc ]
{
    Set iso = ..FromHL7(ts, zone, .had)
    // The zone FromHL7 applied to a time without an offset: an empty one is the namespace's cached zone, then the profile's.
    If (zone = "") || (zone = $CHAR(0)) Set zone = $GET(^Shutter.Config("feedZone"))
    If zone = "" Set zone = ##class(Shutter.Store.SiteProfile).FeedTimeZone()
    Set o = {}
    Set o.iso = iso
    Do o.%Set("had_offset", ''had, "boolean")
    Set o.zone = zone
    Do o.%Set("zone_known", ..KnownZone(zone), "boolean")
    Do o.%Set("python_zones", ..PythonZones(), "boolean")
    Set o."zone_offset" = ..ZoneOffset(zone, $PIECE(iso, "Z", 1))
    Do o.%Set("bst", ..InBritishSummerTime(iso), "boolean")
    Do o.%Set("near_clock_change", ..NearBritishClockChange(iso), "boolean")
    Set y = +$EXTRACT(iso, 1, 4)
    If y > 0 Set o."last_sunday_march" = ..LastSunday(y, 3), o."last_sunday_october" = ..LastSunday(y, 10)
    Quit o.%ToJSON()
}

/// Seconds between two ISO UTC timestamps (b minus a). Returns "" when either is empty or unreadable (a date that does
/// not exist, or text that is no time), never an error.
ClassMethod SecondsBetween(a As %String, b As %String) As %Integer
{
    If (a = "") || (b = "") Quit ""
    Set ha = "", hb = ""
    Try {
        Set ha = $ZDATETIMEH($TRANSLATE($PIECE(a, "Z", 1), "T", " "), 3, 1)
        Set hb = $ZDATETIMEH($TRANSLATE($PIECE(b, "Z", 1), "T", " "), 3, 1)
    } Catch ex {
        Set ha = "", hb = ""
    }
    If (ha = "") || (hb = "") Quit ""
    Quit (($PIECE(hb, ",", 1) - $PIECE(ha, ",", 1)) * 86400) + ($PIECE(hb, ",", 2) \ 1 - $PIECE(ha, ",", 2) \ 1)
}

}
