/// The reminder for cases left open (CONTRACTS 6.4, reminders), as pure functions of cases, the time and the settings:
/// which cases are due for whom, whether the window is open in the site's own feed time zone, what a digest says, and what
/// the site profile may hold. They read no table and no profile; Shutter.Util.CaseReminderTask brings those. Open time is
/// elapsed time since the case opened, so a threshold passes overnight or at the weekend and the case is in the first mail
/// of the next window. A site's bank holidays are not known here.
Class Shutter.Util.CaseReminder Extends %RegisteredObject
{

/// The states that need a person, whatever else they mean to the workflow.
Parameter NEEDSPERSON = "awaiting_approval,blocked,escalated,failed";

/// At most one digest in this many seconds to one recipient.
Parameter HOURSECONDS = 3600;

/// The case numbers a digest lists; the rest are counted.
Parameter MAXLINES = 100;

/// The settings as stored over their defaults, with the zone from the feed's: UTC when the profile does not answer, as
/// Shutter.Store.SiteProfile.FeedTimeZone reads it. Off unless the profile says true.
ClassMethod Settings(profile As %DynamicObject) As %DynamicObject
{
    Set s = {"team_hours": 4, "officer_hours": 8, "officer_name": "", "officer_address": "", "window_start": "08:00", "window_end": "18:00", "days": ["mon", "tue", "wed", "thu", "fri"], "patient_detail": "identifiers", "sign_in_url": ""}
    Do s.%Set("enabled", 0, "boolean")
    Set r = $SELECT($ISOBJECT(profile): profile.%Get("reminders"), 1: "")
    If $ISOBJECT(r) && r.%IsA("%DynamicObject") {
        Set it = r.%GetIterator()
        While it.%GetNext(.k, .v) { If $ISOBJECT(v) { Do s.%Set(k, v) } Else { Do s.%Set(k, v, r.%GetTypeOf(k)) } }
    }
    Set feed = $SELECT($ISOBJECT(profile): profile.%Get("feed"), 1: "")
    Set s.zone = $SELECT($ISOBJECT(feed): ##class(Shutter.Util.Json).Str(feed, "time_zone"), 1: "")
    If s.zone = "" Set s.zone = "UTC"
    Quit s
}

/// What is wrong with the profile's reminders, with the field named, or "".
ClassMethod ProfileProblem(r, domains As %List) As %String
{
    If '$ISOBJECT(r) || 'r.%IsA("%DynamicObject") Quit "reminders: must be an object"
    Set it = r.%GetIterator()
    While it.%GetNext(.k, .v) {
        If '$LISTFIND($LISTBUILD("enabled", "team_hours", "officer_hours", "officer_name", "officer_address", "window_start", "window_end", "days", "patient_detail", "sign_in_url"), k) Return "reminders." _ k _ ": unknown setting"
    }
    If r.%IsDefined("enabled") && (r.%GetTypeOf("enabled") '= "boolean") Quit "reminders.enabled: must be true or false"
    For k = "team_hours", "officer_hours" {
        Continue:'r.%IsDefined(k)
        Set n = r.%Get(k)
        If (r.%GetTypeOf(k) '= "number") || (n '= (n \ 1)) || (n < 1) || (n > 720) Return "reminders." _ k _ ": must be a whole number of hours from 1 to 720"
    }
    Set s = ..Settings({"reminders": (r)})
    If s."officer_hours" <= s."team_hours" Quit "reminders.officer_hours: must be later than team_hours"
    For k = "window_start", "window_end" {
        If (r.%IsDefined(k) && (r.%GetTypeOf(k) '= "string")) || '$MATCH(s.%Get(k), "^([01][0-9]|2[0-3]):[0-5][0-9]$") Return "reminders." _ k _ ": must be a time such as 08:00"
    }
    If '(s."window_end" ] s."window_start") Quit "reminders.window_end: must be later than window_start"
    If r.%IsDefined("days") {
        Set days = r.%Get("days")
        If '$ISOBJECT(days) || 'days.%IsA("%DynamicArray") || (days.%Size() = 0) Quit "reminders.days: must name at least one day"
        Set di = days.%GetIterator()
        While di.%GetNext(.j, .d) {
            If '$LISTFIND($LISTBUILD("mon", "tue", "wed", "thu", "fri", "sat", "sun"), d) Return "reminders.days[" _ j _ "]: must be mon, tue, wed, thu, fri, sat or sun"
        }
    }
    If '$LISTFIND($LISTBUILD("none", "identifiers", "identifiers_initial"), s."patient_detail") Quit "reminders.patient_detail: must be none, identifiers or identifiers_initial"
    For k = "officer_name", "officer_address", "sign_in_url" {
        If r.%IsDefined(k) && (r.%GetTypeOf(k) '= "string") Return "reminders." _ k _ ": must be text"
    }
    Set problem = ##class(Shutter.Util.Mail).ControlProblem(s."officer_name")
    If problem '= "" Quit "reminders.officer_name: " _ problem
    If s."officer_address" '= "" {
        Set problem = ##class(Shutter.Util.Mail).AddressProblem(s."officer_address", domains)
        If problem '= "" Quit "reminders.officer_address: " _ problem
    }
    If (s."sign_in_url" '= "") && '$MATCH(s."sign_in_url", "^https?://[^\s\x00-\x1f\x7f-\x9f]+$") Quit "reminders.sign_in_url: must be an address starting http:// or https://, with no spaces"
    Quit ""
}

/// Seconds an offset of ZoneOffset's form adds to UTC ("+0100" is 3600; "" is 0).
ClassMethod OffsetSeconds(offset As %String) As %Integer [ Private ]
{
    If offset = "" Quit 0
    Set secs = ($EXTRACT(offset, 2, 3) * 3600) + ($EXTRACT(offset, 4, 5) * 60)
    Quit $SELECT($EXTRACT(offset, 1) = "-": -secs, 1: secs)
}

/// A UTC time moved by seconds, as the ISO form without its Z; "" when it does not read.
ClassMethod Shifted(iso As %String, seconds As %Integer) As %String [ Private ]
{
    Set h = ""
    Try { Set h = $ZDATETIMEH($TRANSLATE($PIECE(iso, "Z", 1), "T", " "), 3, 1) } Catch ex { Set h = "" }
    If h = "" Quit ""
    Set total = ($PIECE(h, ",", 1) * 86400) + ($PIECE(h, ",", 2) \ 1) + seconds
    Quit $ZDATE(total \ 86400, 3) _ "T" _ $ZTIME(total # 86400, 1)
}

/// A UTC time as local time in the zone, "yyyy-mm-ddThh:mm:ss". London by its exact rule on the UTC time; another zone
/// asks Shutter.Util.Time.ZoneOffset of a local time, so it is asked twice to land on the right side of a change.
ClassMethod LocalTime(now As %String, zone As %String) As %String
{
    If zone = "Europe/London" Quit ..Shifted(now, $SELECT(##class(Shutter.Util.Time).InBritishSummerTime(now): 3600, 1: 0))
    Set first = ..Shifted(now, ..OffsetSeconds(##class(Shutter.Util.Time).ZoneOffset(zone, $PIECE(now, "Z", 1))))
    Quit ..Shifted(now, ..OffsetSeconds(##class(Shutter.Util.Time).ZoneOffset(zone, first)))
}

/// Whether the window is open at a UTC time: a listed day, from the start up to but not including the end, local time.
ClassMethod InWindow(now As %String, settings As %DynamicObject) As %Boolean
{
    Set local = ..LocalTime(now, settings.zone)
    If local = "" Quit 0
    Set day = $PIECE("sun,mon,tue,wed,thu,fri,sat", ",", $ZDATE($ZDATEH($EXTRACT(local, 1, 10), 3), 10) + 1)
    Set listed = 0, it = settings.days.%GetIterator()
    While it.%GetNext(, .d) { If d = day Set listed = 1 }
    If 'listed Quit 0
    Set time = $EXTRACT(local, 12, 16)
    Quit '(settings."window_start" ] time) && (settings."window_end" ] time)
}

/// Who is due what at a time. cases: objects with caseId, state, disposition, openedAt, teamAddress, teamName, reminded
/// (the thresholds already sent) and whatever the digest will show. lastSent: the time of the last digest per lowercased
/// address (Shutter.Store.ReminderDigest.LastSent). The answer: digests, one per address with its items (threshold,
/// ageSeconds, case); held, the addresses the hourly limit keeps back; no_address, the thresholds due with nobody to send
/// to. Pure: the same arguments give the same answer, and nothing is written.
ClassMethod Decide(cases As %DynamicArray, now As %String, settings As %DynamicObject, lastSent As %DynamicObject) As %DynamicObject
{
    Set out = {"digests": [], "held": [], "no_address": 0}
    Do out.%Set("open", 0, "boolean")
    If 'settings.enabled Quit out
    If '..InWindow(now, settings) Quit out
    Do out.%Set("open", 1, "boolean")
    Set states = $LISTFROMSTRING(..#NEEDSPERSON)
    Set it = cases.%GetIterator()
    While it.%GetNext(, .c) {
        Continue:'$LISTFIND(states, c.state)
        Continue:c.disposition="abandoned"
        Set age = ##class(Shutter.Util.Time).SecondsBetween(c.openedAt, now)
        Continue:age=""
        Set sent = ""
        If $ISOBJECT(c.reminded) {
            Set ri = c.reminded.%GetIterator()
            While ri.%GetNext(, .r) { Set sent = sent _ $LISTBUILD(r) }
        }
        For threshold = "team", "officer" {
            Continue:$LISTFIND(sent, threshold)
            Continue:age<(settings.%Get(threshold _ "_hours") * 3600)
            Set address = $SELECT(threshold = "team": c.teamAddress, 1: settings."officer_address")
            If address = "" Set out."no_address" = out."no_address" + 1 Continue
            Set key = $ZCONVERT(address, "L")
            If '$DATA(at(key)) {
                Set last = lastSent.%Get(key), gap = $SELECT(last = "": "", 1: ##class(Shutter.Util.Time).SecondsBetween(last, now))
                If (gap '= "") && (gap < ..#HOURSECONDS) {
                    Set at(key) = 0
                    Do out.held.%Push(key)
                } Else {
                    Set name = $SELECT(threshold = "team": c.teamName, 1: settings."officer_name")
                    Do out.digests.%Push({"to": (key), "toName": (name), "items": []})
                    Set at(key) = out.digests.%Size()
                }
            }
            Continue:'at(key)
            Do out.digests.%Get(at(key) - 1).items.%Push({"threshold": (threshold), "ageSeconds": (age), "case": (c)})
        }
    }
    Quit out
}

/// Whether a number is an NHS number by its shape: ten digits, spaces and hyphens aside, with a good check digit.
ClassMethod LooksLikeNHSNumber(id As %String) As %Boolean
{
    Set d = $TRANSLATE(id, " -", "")
    If d '? 10N Quit 0
    Set sum = 0
    For i = 1:1:9 { Set sum = sum + ($EXTRACT(d, i) * (11 - i)) }
    Set check = 11 - (sum # 11)
    If check = 11 Set check = 0
    Quit (check '= 10) && (check = +$EXTRACT(d, 10))
}

/// Text from the feed or the profile as one line of the mail.
ClassMethod Line(text As %String) As %String [ Private ]
{
    Quit $ZSTRIP(##class(Shutter.Util.Mail).HeaderValue(text), "<>W")
}

/// A number of hours in words.
ClassMethod Hours(seconds As %Integer) As %String [ Private ]
{
    Set h = seconds \ 3600
    Quit h _ $SELECT(h = 1: " hour", 1: " hours")
}

/// A case's line at the site's level of patient detail. Reads only the fields named here: a name, a date of birth, an
/// address or an NHS number has no way in, whatever the setting. A hospital number that is an NHS number by its shape or
/// its authority is left out: the case carries PID-3's first repetition when none is typed MR.
ClassMethod CaseLine(c As %DynamicObject, detail As %String) As %String
{
    Set line = ..Line(c.caseId)
    If detail = "none" Quit line
    Set id = ..Line(c.patientId), authority = ..Line(c.patientIdAuthority)
    If (id '= "") && (..LooksLikeNHSNumber(id) || ($ZCONVERT(authority, "U") [ "NHS")) {
        Set line = line _ ", hospital number not shown"
    } ElseIf id '= "" {
        Set line = line _ ", hospital number " _ id _ $SELECT(authority '= "": " (" _ authority _ ")", 1: "")
    }
    Set visit = ..Line(c.encounterId)
    If (visit '= "") && (visit '= "-") Set line = line _ ", visit " _ visit
    If detail = "identifiers_initial" {
        Set initial = $ZCONVERT($EXTRACT(..Line(c.initial), 1), "U")
        If initial ? 1A Set line = line _ ", first name " _ initial
    }
    Quit line
}

/// The subject and text of a digest. No identifier goes in the subject. One case in two thresholds is one case.
ClassMethod Compose(digest As %DynamicObject, settings As %DynamicObject, Output subject As %String, Output body As %String)
{
    Set nl = $CHAR(13, 10), oldest = 0, team = 0, officer = 0, cases = 0, lines = "", more = 0
    Set it = digest.items.%GetIterator()
    While it.%GetNext(, .item) {
        If item.threshold = "officer" { Set officer = officer + 1 } Else { Set team = team + 1 }
        If item.ageSeconds > oldest Set oldest = item.ageSeconds
        Set c = item.case
        Continue:$DATA(seen(c.caseId))
        Set seen(c.caseId) = "", cases = cases + 1
        Set receiver = ..Line(c.receiver), kind = ..Line($TRANSLATE(c.failureKind, "_", " "))
        Set group = $SELECT(receiver '= "": receiver, 1: "the downstream system") _ ", " _ $SELECT(kind '= "": kind, 1: "no failure type recorded")
        If '$DATA(count(group)) Set order($INCREMENT(order)) = group, count(group) = 0
        Set count(group) = count(group) + 1
        If cases <= ..#MAXLINES { Set lines = lines _ ..CaseLine(c, settings."patient_detail") _ nl } Else { Set more = more + 1 }
    }
    Set they = $SELECT(cases = 1: "1 case needs", 1: cases _ " cases need")
    Set subject = "Shutter: " _ they _ " a person, the oldest open " _ ..Hours(oldest)
    Set name = ..Line(digest.toName)
    Set body = $SELECT(name '= "": "To " _ name _ ",", 1: "Hello,") _ nl _ nl
    Set body = body _ $SELECT(cases = 1: "1 case in Shutter needs", 1: cases _ " cases in Shutter need") _ " a person. This reminder went out by itself and nobody reviewed it. Sending it changed no case's state." _ nl _ nl
    If team > 0 Set body = body _ "First reminder, open " _ settings."team_hours" _ " hours or more: " _ team _ nl
    If officer > 0 Set body = body _ "Later reminder, open " _ settings."officer_hours" _ " hours or more: " _ officer _ nl
    Set body = body _ "The oldest has been open " _ ..Hours(oldest) _ "." _ nl _ nl
    For i = 1:1:$GET(order) { Set body = body _ order(i) _ ": " _ count(order(i)) _ nl }
    Set body = body _ nl _ lines
    If more > 0 Set body = body _ "and " _ more _ " more" _ nl
    Set url = settings."sign_in_url", see = $SELECT(cases = 1: "it", 1: "them")
    Set body = body _ nl _ $SELECT(url '= "": "Sign in to see " _ see _ ": " _ url, 1: "Sign in to Shutter to see " _ see _ ".") _ nl
}

/// The Doctor's warnings for settings as they stand, as an array of sentences: none while off.
ClassMethod Warnings(settings As %DynamicObject, mailServer As %String, domains As %List, teams As %Integer, task As %Boolean) As %DynamicArray
{
    Set out = []
    If 'settings.enabled Quit out
    If mailServer = "" Do out.%Push("No mail server is set on the Escalation Mail operation, so no reminder can go")
    If $LISTLENGTH(domains) = 0 Do out.%Push("No allowed mail domain is set, so no address can be used")
    If settings."officer_address" = "" Do out.%Push("No officer address is set, so the later reminder goes to nobody")
    If +teams = 0 Do out.%Push("No team is set, so the first reminder goes to nobody")
    If settings."sign_in_url" = "" Do out.%Push("No sign-in address is set, so the mail has no link")
    If 'task Do out.%Push("The task Shutter case reminders is missing, so nothing runs")
    Quit out
}

}
