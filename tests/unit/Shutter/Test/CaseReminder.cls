/// The reminder for cases left open (CONTRACTS 6.4, reminders): the deciding function as a table of cases, times and
/// settings, the site profile's rules, the digest's words at each level of patient detail, and the records it leaves on a
/// saved case, under its own id, UT-REMINDER, removed after each test.
Class Shutter.Test.CaseReminder Extends %UnitTest.TestCase
{

Parameter CASEID = "UT-REMINDER";

Property CaseRowId As %String;

Method OnBeforeAllTests() As %Status
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Shutter_Store.""Case"" WHERE CaseId = ?", ..#CASEID)
    While rs.%Next() { Do ..Purge(rs.%Get("ID")) }
    Quit $$$OK
}

Method OnBeforeOneTest(testname As %String) As %Status
{
    Set c = ##class(Shutter.Store.Case).%New()
    Set c.CaseId = ..#CASEID, c.OperationKey = "PAS^HOSP^MRN9004^ENC-9004^transfer^2026-10-15T08:20:00Z"
    Set c.Event = "transfer", c.EncounterId = "ENC-9004", c.PatientId = "MRN9004", c.PatientIdAuthority = "HOSP"
    Set c.FailureKind = "delivery_failed", c.Receiver = "Downstream Out"
    Set c.State = "blocked", c.OpenedAt = "1970-01-01T00:00:00Z", c.ClosedAt = "1970-01-01T00:00:00Z"
    Set sc = c.%Save()
    Set ..CaseRowId = c.%Id()
    Quit sc
}

Method OnAfterOneTest(testname As %String) As %Status
{
    Do ..Purge(..CaseRowId)
    Quit $$$OK
}

Method Purge(id As %String)
{
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseReminder WHERE ""Case"" = ?", id)
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.ReminderDigest WHERE Recipient LIKE '%@reminder.example.nhs.uk'")
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseEvent WHERE ""Case"" = ?", id)
    Do ##class(Shutter.Store.Case).%DeleteId(id)
    Kill ^Shutter.Reminder
}

/// One row of the table as a word for the assert: "to: case/threshold case/threshold; to: ...", with the addresses held
/// by the hourly limit and the count with nobody to send to after it.
ClassMethod Summary(r As %DynamicObject) As %String
{
    Set out = ""
    Set di = r.digests.%GetIterator()
    While di.%GetNext(, .d) {
        Set line = d.to _ ":"
        Set ii = d.items.%GetIterator()
        While ii.%GetNext(, .item) { Set line = line _ " " _ item.case.caseId _ "/" _ item.threshold }
        Set out = out _ $SELECT(out = "": "", 1: "; ") _ line
    }
    If r.held.%Size() > 0 {
        Set hi = r.held.%GetIterator()
        While hi.%GetNext(, .h) { Set out = out _ $SELECT(out = "": "", 1: "; ") _ "held " _ h }
    }
    If r."no_address" > 0 Set out = out _ $SELECT(out = "": "", 1: "; ") _ "nobody " _ r."no_address"
    Quit out
}

/// A row's settings over the defaults: on, with an officer, in UK time.
ClassMethod RowSettings(row As %DynamicObject) As %DynamicObject
{
    Set r = {"enabled": true, "officer_address": "officer@example.nhs.uk", "officer_name": "Test Officer"}
    Set over = row.%Get("settings")
    If $ISOBJECT(over) {
        Set it = over.%GetIterator()
        While it.%GetNext(.k, .v) { If $ISOBJECT(v) { Do r.%Set(k, v) } Else { Do r.%Set(k, v, over.%GetTypeOf(k)) } }
    }
    Set zone = $SELECT(row.%IsDefined("zone"): row.%Get("zone"), 1: "Europe/London")
    Quit ##class(Shutter.Util.CaseReminder).Settings({"reminders": (r), "feed": {"time_zone": (zone)}})
}

Method TestDecide()
{
    Set rows = ##class(%DynamicArray).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||DecideRows").Data)
    Set it = rows.%GetIterator()
    While it.%GetNext(, .row) {
        // Each case: a blocked case for the team's mailbox unless the row says otherwise.
        Set cases = [], ci = row.cases.%GetIterator()
        While ci.%GetNext(, .c) {
            If 'c.%IsDefined("caseId") Set c.caseId = "C-1"
            If 'c.%IsDefined("state") Set c.state = "blocked"
            If 'c.%IsDefined("teamAddress") Set c.teamAddress = "team@example.nhs.uk"
            Do cases.%Push(c)
        }
        Set last = $SELECT($ISOBJECT(row.%Get("last")): row.%Get("last"), 1: {})
        Set r = ##class(Shutter.Util.CaseReminder).Decide(cases, row.now, ..RowSettings(row), last)
        Do $$$AssertEquals(..Summary(r), row.expect, row.name)
    }
}

XData DecideRows [ MimeType = application/json ]
{
[
 {"name": "a weekday in the window at the team's hours", "now": "2026-11-04T12:00:00Z", "cases": [{"openedAt": "2026-11-04T08:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team"},
 {"name": "a second short of the team's hours", "now": "2026-11-04T12:00:00Z", "cases": [{"openedAt": "2026-11-04T08:00:01Z"}], "expect": ""},
 {"name": "the officer's hours add the officer", "now": "2026-11-04T16:00:00Z", "cases": [{"openedAt": "2026-11-04T08:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team; officer@example.nhs.uk: C-1/officer"},
 {"name": "the window's first second, in winter", "now": "2026-11-04T08:00:00Z", "cases": [{"openedAt": "2026-11-03T20:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team; officer@example.nhs.uk: C-1/officer"},
 {"name": "a second before the window", "now": "2026-11-04T07:59:59Z", "cases": [{"openedAt": "2026-11-03T20:00:00Z"}], "expect": ""},
 {"name": "the window's last second", "now": "2026-11-04T17:59:59Z", "cases": [{"openedAt": "2026-11-04T10:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team"},
 {"name": "the window's end is outside it", "now": "2026-11-04T18:00:00Z", "cases": [{"openedAt": "2026-11-04T10:00:00Z"}], "expect": ""},
 {"name": "in summer 08:00 local is 07:00 UTC", "now": "2026-07-01T07:00:00Z", "cases": [{"openedAt": "2026-06-30T20:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team; officer@example.nhs.uk: C-1/officer"},
 {"name": "in summer 06:59:59 UTC is before the window", "now": "2026-07-01T06:59:59Z", "cases": [{"openedAt": "2026-06-30T20:00:00Z"}], "expect": ""},
 {"name": "in summer 17:00 UTC is the window's end", "now": "2026-07-01T17:00:00Z", "cases": [{"openedAt": "2026-07-01T10:00:00Z"}], "expect": ""},
 {"name": "a threshold passed overnight waits for the morning", "now": "2026-11-04T03:00:00Z", "cases": [{"openedAt": "2026-11-03T17:00:00Z"}], "expect": ""},
 {"name": "a case left overnight is in the first mail, at both thresholds", "now": "2026-11-04T08:00:00Z", "cases": [{"openedAt": "2026-11-03T17:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team; officer@example.nhs.uk: C-1/officer"},
 {"name": "Saturday", "now": "2026-11-07T12:00:00Z", "cases": [{"openedAt": "2026-11-06T12:00:00Z"}], "expect": ""},
 {"name": "Sunday", "now": "2026-11-08T12:00:00Z", "cases": [{"openedAt": "2026-11-06T12:00:00Z"}], "expect": ""},
 {"name": "Monday's first mail takes the weekend", "now": "2026-11-09T08:00:00Z", "cases": [{"openedAt": "2026-11-07T12:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team; officer@example.nhs.uk: C-1/officer"},
 {"name": "the Friday before the clocks go back is still summer time", "now": "2026-10-23T07:00:00Z", "cases": [{"openedAt": "2026-10-22T07:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team; officer@example.nhs.uk: C-1/officer"},
 {"name": "the Monday after they go back, 07:59 UTC is before the window", "now": "2026-10-26T07:59:59Z", "cases": [{"openedAt": "2026-10-24T07:00:00Z"}], "expect": ""},
 {"name": "the Monday after they go back, 08:00 UTC is in it", "now": "2026-10-26T08:00:00Z", "cases": [{"openedAt": "2026-10-24T07:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team; officer@example.nhs.uk: C-1/officer"},
 {"name": "the Monday after they go forward, 07:00 UTC is 08:00 local", "now": "2026-03-30T07:00:00Z", "cases": [{"openedAt": "2026-03-28T07:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team; officer@example.nhs.uk: C-1/officer"},
 {"name": "the Monday after they go forward, 06:59 UTC is before it", "now": "2026-03-30T06:59:59Z", "cases": [{"openedAt": "2026-03-28T07:00:00Z"}], "expect": ""},
 {"name": "open time is elapsed time across the change: eight hours though the clock moved seven", "now": "2026-10-25T08:30:00Z", "settings": {"days": ["sun"]}, "cases": [{"openedAt": "2026-10-25T00:30:00Z"}], "expect": "team@example.nhs.uk: C-1/team; officer@example.nhs.uk: C-1/officer"},
 {"name": "and across the spring change: seven hours though the clock moved eight", "now": "2026-03-29T08:30:00Z", "settings": {"days": ["sun"]}, "cases": [{"openedAt": "2026-03-29T01:30:00Z"}], "expect": "team@example.nhs.uk: C-1/team"},
 {"name": "a case closed between runs", "now": "2026-11-04T12:00:00Z", "cases": [{"openedAt": "2026-11-03T12:00:00Z", "state": "resolved"}], "expect": ""},
 {"name": "a case handled by hand", "now": "2026-11-04T12:00:00Z", "cases": [{"openedAt": "2026-11-03T12:00:00Z", "state": "resolved", "disposition": "handled_by_hand"}], "expect": ""},
 {"name": "an abandoned case", "now": "2026-11-04T12:00:00Z", "cases": [{"openedAt": "2026-11-03T12:00:00Z", "state": "failed", "disposition": "abandoned"}], "expect": ""},
 {"name": "a case Shutter is still working on", "now": "2026-11-04T12:00:00Z", "cases": [{"openedAt": "2026-11-03T12:00:00Z", "state": "investigating"}], "expect": ""},
 {"name": "the four states that need a person", "now": "2026-11-04T12:00:00Z", "settings": {"officer_address": ""}, "cases": [{"caseId": "C-1", "openedAt": "2026-11-04T08:00:00Z", "state": "awaiting_approval"}, {"caseId": "C-2", "openedAt": "2026-11-04T08:00:00Z", "state": "blocked"}, {"caseId": "C-3", "openedAt": "2026-11-04T08:00:00Z", "state": "escalated"}, {"caseId": "C-4", "openedAt": "2026-11-04T08:00:00Z", "state": "failed"}], "expect": "team@example.nhs.uk: C-1/team C-2/team C-3/team C-4/team"},
 {"name": "a case with no opening time", "now": "2026-11-04T12:00:00Z", "cases": [{"openedAt": ""}], "expect": ""},
 {"name": "the team's reminder already sent: the officer's next", "now": "2026-11-04T17:00:00Z", "cases": [{"openedAt": "2026-11-04T08:00:00Z", "reminded": ["team"]}], "expect": "officer@example.nhs.uk: C-1/officer"},
 {"name": "the team's reminder already sent, the officer's hours not reached", "now": "2026-11-04T13:00:00Z", "cases": [{"openedAt": "2026-11-04T08:00:00Z", "reminded": ["team"]}], "expect": ""},
 {"name": "both sent: nothing more, however long it stays open", "now": "2026-11-20T12:00:00Z", "cases": [{"openedAt": "2026-11-04T08:00:00Z", "reminded": ["team", "officer"]}], "expect": ""},
 {"name": "59 minutes after the last digest", "now": "2026-11-04T12:00:00Z", "last": {"team@example.nhs.uk": "2026-11-04T11:01:00Z"}, "cases": [{"openedAt": "2026-11-04T08:00:00Z"}], "expect": "held team@example.nhs.uk"},
 {"name": "an hour after the last digest", "now": "2026-11-04T12:00:00Z", "last": {"team@example.nhs.uk": "2026-11-04T11:00:00Z"}, "cases": [{"openedAt": "2026-11-04T08:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team"},
 {"name": "the hourly limit ignores the address's case", "now": "2026-11-04T12:00:00Z", "last": {"team@example.nhs.uk": "2026-11-04T11:30:00Z"}, "cases": [{"openedAt": "2026-11-04T08:00:00Z", "teamAddress": "Team@Example.NHS.uk"}], "expect": "held team@example.nhs.uk"},
 {"name": "the hourly limit is per recipient", "now": "2026-11-04T17:00:00Z", "last": {"team@example.nhs.uk": "2026-11-04T16:30:00Z"}, "cases": [{"openedAt": "2026-11-04T08:00:00Z"}], "expect": "officer@example.nhs.uk: C-1/officer; held team@example.nhs.uk"},
 {"name": "two teams get two digests", "now": "2026-11-04T12:00:00Z", "cases": [{"caseId": "C-1", "openedAt": "2026-11-04T08:00:00Z"}, {"caseId": "C-2", "openedAt": "2026-11-04T08:00:00Z", "teamAddress": "other@example.nhs.uk"}, {"caseId": "C-3", "openedAt": "2026-11-04T08:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team C-3/team; other@example.nhs.uk: C-2/team"},
 {"name": "the officer is the team's mailbox: one digest", "now": "2026-11-04T17:00:00Z", "settings": {"officer_address": "team@example.nhs.uk"}, "cases": [{"openedAt": "2026-11-04T08:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team C-1/officer"},
 {"name": "no officer address: the team's reminder alone, the rest counted", "now": "2026-11-04T17:00:00Z", "settings": {"officer_address": ""}, "cases": [{"openedAt": "2026-11-04T08:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team; nobody 1"},
 {"name": "no team mailbox: the officer's alone, the rest counted", "now": "2026-11-04T17:00:00Z", "cases": [{"openedAt": "2026-11-04T08:00:00Z", "teamAddress": ""}], "expect": "officer@example.nhs.uk: C-1/officer; nobody 1"},
 {"name": "off, the default", "now": "2026-11-04T17:00:00Z", "settings": {"enabled": false}, "cases": [{"openedAt": "2026-11-04T08:00:00Z"}], "expect": ""},
 {"name": "a site's own hours", "now": "2026-11-04T12:00:00Z", "settings": {"team_hours": 1, "officer_hours": 2}, "cases": [{"openedAt": "2026-11-04T10:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team; officer@example.nhs.uk: C-1/officer"},
 {"name": "a site's own window", "now": "2026-11-04T07:30:00Z", "settings": {"window_start": "07:00", "window_end": "19:30"}, "cases": [{"openedAt": "2026-11-04T03:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team"},
 {"name": "a site's own window's end", "now": "2026-11-04T19:30:00Z", "settings": {"window_start": "07:00", "window_end": "19:30"}, "cases": [{"openedAt": "2026-11-04T15:00:00Z"}], "expect": ""},
 {"name": "a site's own days", "now": "2026-11-07T12:00:00Z", "settings": {"days": ["sat"]}, "cases": [{"openedAt": "2026-11-07T08:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team"},
 {"name": "a site's own days leave Wednesday out", "now": "2026-11-04T12:00:00Z", "settings": {"days": ["sat"]}, "cases": [{"openedAt": "2026-11-04T08:00:00Z"}], "expect": ""},
 {"name": "a zone east of UTC: 02:30 UTC is 08:00 there", "now": "2026-11-04T02:30:00Z", "zone": "+05:30", "cases": [{"openedAt": "2026-11-03T22:30:00Z"}], "expect": "team@example.nhs.uk: C-1/team"},
 {"name": "a zone far east: Sunday 20:00 UTC is Monday 10:00 there", "now": "2026-11-08T20:00:00Z", "zone": "+14:00", "cases": [{"openedAt": "2026-11-08T16:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team"},
 {"name": "a zone far west: Saturday 02:00 UTC is Friday 16:00 there", "now": "2026-11-07T02:00:00Z", "zone": "-10:00", "settings": {"officer_address": ""}, "cases": [{"openedAt": "2026-11-06T22:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team"},
 {"name": "and Friday 20:00 UTC is Saturday 10:00 far east, a weekend", "now": "2026-11-06T20:00:00Z", "zone": "+14:00", "cases": [{"openedAt": "2026-11-06T12:00:00Z"}], "expect": ""},
 {"name": "UTC", "now": "2026-07-01T08:00:00Z", "zone": "UTC", "cases": [{"openedAt": "2026-07-01T04:00:00Z"}], "expect": "team@example.nhs.uk: C-1/team"}
]
}

/// An IANA zone through Embedded Python, when this IRIS has it: 08:00 in New York in January is 13:00 UTC.
Method TestAnIANAZone()
{
    If '##class(Shutter.Util.Time).PythonZones() Do $$$AssertSkipped("Embedded Python's zoneinfo is not here") Quit
    Set s = ##class(Shutter.Util.CaseReminder).Settings({"reminders": {"enabled": true}, "feed": {"time_zone": "America/New_York"}})
    Do $$$AssertEquals(##class(Shutter.Util.CaseReminder).InWindow("2026-01-14T13:00:00Z", s), 1, "08:00 there in January")
    Do $$$AssertEquals(##class(Shutter.Util.CaseReminder).InWindow("2026-01-14T12:59:59Z", s), 0, "07:59 there in January")
    Do $$$AssertEquals(##class(Shutter.Util.CaseReminder).InWindow("2026-07-14T12:00:00Z", s), 1, "08:00 there in July")
}

Method TestProfileRules()
{
    Set rows = ##class(%DynamicArray).%FromJSON(##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||ProfileRows").Data)
    Set profile = ##class(Shutter.Store.SiteProfile).Default()
    Set profile.mail = {"allowed_domains": ["example.nhs.uk"]}
    Set it = rows.%GetIterator()
    While it.%GetNext(, .row) {
        Do profile.%Set("reminders", row.value)
        Set problem = ##class(Shutter.Store.SiteProfile).Validate(profile)
        Do $$$AssertEquals(problem, row.expect, row.name)
    }
}

XData ProfileRows [ MimeType = application/json ]
{
[
 {"name": "nothing set is off and passes", "value": {}, "expect": ""},
 {"name": "the whole setting", "value": {"enabled": true, "team_hours": 4, "officer_hours": 8, "officer_name": "Test Officer", "officer_address": "officer@example.nhs.uk", "window_start": "08:00", "window_end": "18:00", "days": ["mon", "tue", "wed", "thu", "fri"], "patient_detail": "identifiers", "sign_in_url": "https://shutter.example.nhs.uk/shutter/"}, "expect": ""},
 {"name": "not an object", "value": [], "expect": "reminders: must be an object"},
 {"name": "an unknown setting", "value": {"enable": true}, "expect": "reminders.enable: unknown setting"},
 {"name": "enabled as a word", "value": {"enabled": "yes"}, "expect": "reminders.enabled: must be true or false"},
 {"name": "hours of zero", "value": {"team_hours": 0}, "expect": "reminders.team_hours: must be a whole number of hours from 1 to 720"},
 {"name": "hours in part", "value": {"team_hours": 1.5}, "expect": "reminders.team_hours: must be a whole number of hours from 1 to 720"},
 {"name": "hours as text", "value": {"officer_hours": "8"}, "expect": "reminders.officer_hours: must be a whole number of hours from 1 to 720"},
 {"name": "the officer no later than the team", "value": {"team_hours": 8, "officer_hours": 8}, "expect": "reminders.officer_hours: must be later than team_hours"},
 {"name": "the officer before the default team hours", "value": {"officer_hours": 2}, "expect": "reminders.officer_hours: must be later than team_hours"},
 {"name": "a window start with no minutes", "value": {"window_start": "8"}, "expect": "reminders.window_start: must be a time such as 08:00"},
 {"name": "an hour past the day", "value": {"window_end": "24:00"}, "expect": "reminders.window_end: must be a time such as 08:00"},
 {"name": "a window that ends before it starts", "value": {"window_start": "18:00", "window_end": "08:00"}, "expect": "reminders.window_end: must be later than window_start"},
 {"name": "a day that is none", "value": {"days": ["mon", "funday"]}, "expect": "reminders.days[1]: must be mon, tue, wed, thu, fri, sat or sun"},
 {"name": "no days", "value": {"days": []}, "expect": "reminders.days: must name at least one day"},
 {"name": "days as text", "value": {"days": "mon"}, "expect": "reminders.days: must name at least one day"},
 {"name": "a patient detail that is none", "value": {"patient_detail": "full_name"}, "expect": "reminders.patient_detail: must be none, identifiers or identifiers_initial"},
 {"name": "an officer outside the domains", "value": {"officer_address": "a@evil.com"}, "expect": "reminders.officer_address: not in the allowed domains"},
 {"name": "a header injected in the officer's address", "value": {"officer_address": "a@example.nhs.uk\r\nBcc: e@evil.com"}, "expect": "reminders.officer_address: must not contain line breaks or control characters"},
 {"name": "a display name in the officer's address", "value": {"officer_address": "Officer <a@example.nhs.uk>"}, "expect": "reminders.officer_address: must be a bare address, local@domain, with no display name, brackets or spaces"},
 {"name": "a line break in the officer's name", "value": {"officer_name": "A\r\nB"}, "expect": "reminders.officer_name: must not contain line breaks or control characters"},
 {"name": "a sign-in address that is not one", "value": {"sign_in_url": "javascript:alert(1)"}, "expect": "reminders.sign_in_url: must be an address starting http:// or https://, with no spaces"},
 {"name": "a sign-in address with a space", "value": {"sign_in_url": "https://a b/"}, "expect": "reminders.sign_in_url: must be an address starting http:// or https://, with no spaces"}
]
}

/// A case for the digest's words: fields that must never reach it sit beside the ones that may.
ClassMethod Item(caseId As %String, threshold As %String, ageHours As %Integer, receiver As %String = "Downstream Out", kind As %String = "delivery_failed") As %DynamicObject
{
    Set c = {"caseId": (caseId), "receiver": (receiver), "failureKind": (kind), "patientId": "MRN77", "patientIdAuthority": "HOSP", "encounterId": "ENC-77", "initial": "J", "name": "JONES^JANE", "dob": "1970-01-02", "nhs": "9434765919", "address": "1 High Street"}
    Quit {"threshold": (threshold), "ageSeconds": (ageHours * 3600), "case": (c)}
}

ClassMethod Compose(detail As %String, items As %DynamicArray, Output subject As %String, Output body As %String, url As %String = "https://shutter.example.nhs.uk/")
{
    Set s = ##class(Shutter.Util.CaseReminder).Settings({"reminders": {"enabled": true, "patient_detail": (detail), "sign_in_url": (url)}})
    Do ##class(Shutter.Util.CaseReminder).Compose({"to": "team@example.nhs.uk", "toName": "Bed team", "items": (items)}, s, .subject, .body)
}

Method TestTheDigestsWords()
{
    Do ..Compose("identifiers", [(..Item("C-1", "team", 5)), (..Item("C-2", "officer", 27, "Records Out", "rejected"))], .subject, .body)
    Do $$$AssertEquals(subject, "Shutter: 2 cases need a person, the oldest open 27 hours", "the subject")
    For want = "To Bed team,", "2 cases in Shutter need a person.", "nobody reviewed it", "changed nothing", "First reminder, open 4 hours or more: 1", "Later reminder, open 8 hours or more: 1", "The oldest has been open 27 hours.", "Downstream Out, delivery failed: 1", "Records Out, rejected: 1", "https://shutter.example.nhs.uk/" {
        Do $$$AssertTrue(body [ want, "the digest says: " _ want)
    }
    Do ..Compose("identifiers", [(..Item("C-1", "team", 1))], .subject, .body, "")
    Do $$$AssertEquals(subject, "Shutter: 1 case needs a person, the oldest open 1 hour", "one case")
    Do $$$AssertTrue(body [ "Sign in to Shutter to see it.", "no address: says where to go in words")
}

Method TestPatientDetail()
{
    Set items = [(..Item("C-1", "team", 5))]
    Do ..Compose("none", items, .subject, .none)
    Do $$$AssertTrue(none [ "C-1", "none: the case number")
    Do $$$AssertNotTrue(none [ "MRN77", "none: no hospital number")
    Do $$$AssertNotTrue(none [ "ENC-77", "none: no visit")
    Do ..Compose("identifiers", items, .subject, .ids)
    Do $$$AssertTrue(ids [ "C-1, hospital number MRN77 (HOSP), visit ENC-77", "identifiers")
    Do $$$AssertNotTrue(ids [ "first name", "identifiers: no initial")
    Do ..Compose("identifiers_initial", items, .subject, .initial)
    Do $$$AssertTrue(initial [ "C-1, hospital number MRN77 (HOSP), visit ENC-77, first name J", "identifiers and the initial")
    // Never, whatever the setting, and never in the subject.
    For detail = "none", "identifiers", "identifiers_initial" {
        Do ..Compose(detail, items, .subject, .body)
        For never = "JONES", "JANE", "1970", "9434765919", "High Street" {
            Do $$$AssertNotTrue(body [ never, detail _ ": the body never has " _ never)
            Do $$$AssertNotTrue(subject [ never, detail _ ": the subject never has " _ never)
        }
        Do $$$AssertNotTrue(subject [ "MRN77", detail _ ": the subject has no identifier")
    }
}

/// The hospital number is PID-3 typed MR, else the first repetition: with no MR it can be the NHS number.
Method TestAnNHSNumberIsNeverShown()
{
    For row = $LISTBUILD("9434765919", "HOSP"), $LISTBUILD("943 476 5919", "HOSP"), $LISTBUILD("12345", "NHS"), $LISTBUILD("12345", "nhs number") {
        Set item = ..Item("C-1", "team", 5)
        Set item.case.patientId = $LIST(row, 1), item.case.patientIdAuthority = $LIST(row, 2)
        Do ..Compose("identifiers", [(item)], .subject, .body)
        Do $$$AssertNotTrue(body [ $LIST(row, 1), "not shown: " _ $LIST(row, 1))
        Do $$$AssertTrue(body [ "hospital number not shown", "and says so")
    }
    // Ten digits that fail the check digit are a hospital's own number.
    Set item = ..Item("C-1", "team", 5), item.case.patientId = "1234567890"
    Do ..Compose("identifiers", [(item)], .subject, .body)
    Do $$$AssertTrue(body [ "1234567890", "not an NHS number: shown")
}

Method TestWhatTheFeedSentCannotBreakTheMail()
{
    Set item = ..Item("C-1", "team", 5, "Out"_$CHAR(13,10)_"Bcc: e@evil.com", "x")
    Set item.case.patientId = "M"_$CHAR(10)_"Sign in at http://evil", item.case.encounterId = "-", item.case.initial = "7"
    Do ..Compose("identifiers_initial", [(item)], .subject, .body)
    Do $$$AssertNotTrue(body [ ("Out"_$CHAR(13,10)_"Bcc"), "a line break in the receiver goes")
    Do $$$AssertNotTrue(body [ ("M"_$CHAR(10)), "a line break in the identifier goes")
    Do $$$AssertNotTrue(body [ "visit", "the literal - is no visit")
    Do $$$AssertNotTrue(body [ "first name", "an initial that is no letter is not shown")
}

Method TestALongListIsCut()
{
    Set items = []
    For i = 1:1:105 { Do items.%Push(..Item("C-" _ i, "team", 5)) }
    Do ..Compose("none", items, .subject, .body)
    Do $$$AssertTrue(subject [ "105 cases", "all are counted")
    Do $$$AssertTrue(body [ "C-100", "the hundredth is listed")
    Do $$$AssertNotTrue(body [ "C-101", "the next is not")
    Do $$$AssertTrue(body [ "and 5 more", "and the rest are counted")
}

/// A case with two thresholds in one digest is one case in the counts and one line.
Method TestOneCaseTwiceInADigest()
{
    Do ..Compose("none", [(..Item("C-1", "team", 9)), (..Item("C-1", "officer", 9))], .subject, .body)
    Do $$$AssertTrue(subject [ "1 case needs", "counted once")
    Do $$$AssertEquals($LENGTH(body, "C-1") - 1, 1, "listed once")
    Do $$$AssertTrue(body [ "Downstream Out, delivery failed: 1", "by receiver once")
}

Method Digest(threshold As %String = "team") As Shutter.Store.ReminderDigest
{
    Set items = [{"id": (..CaseRowId), "caseId": (..#CASEID), "threshold": (threshold), "hours": 4}]
    Set sc = ##class(Shutter.Store.ReminderDigest).Create("team@reminder.example.nhs.uk", "Shutter: 1 case", "MRN9004", items, "2026-11-04T12:00:00Z", .row)
    Do $$$AssertStatusOK(sc, "the digest is stored")
    Quit row
}

Method TestASentReminderIsRecordedAndChangesNothing()
{
    Set before = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set version = before.Version, updated = before.UpdatedAt, state = before.State
    Set row = ..Digest()
    Do $$$AssertEquals(row.State, "queued", "queued")
    Do $$$AssertEquals(##class(Shutter.Store.CaseReminder).Thresholds(..CaseRowId).%Size(), 0, "not recorded until it goes")
    Do $$$AssertStatusOK(row.MarkSent("Accepted by relay", "2026-11-04T12:01:00Z"), "sent")
    Do $$$AssertEquals(row.State, "sent", "sent")
    Do $$$AssertEquals(row.Body, "", "the text with the identifiers goes")
    Do $$$AssertEquals(##class(Shutter.Store.CaseReminder).Thresholds(..CaseRowId).%ToJSON(), "[""team""]", "recorded")
    // A new process reads the same: the record is a table, so a restart keeps it.
    Set after = ##class(Shutter.Store.Case).%OpenId(..CaseRowId, 0)
    Do after.%Reload()
    Do $$$AssertEquals(after.Version, version, "the case's version does not move")
    Do $$$AssertEquals(after.UpdatedAt, updated, "the case's time does not move")
    Do $$$AssertEquals(after.State, state, "the state does not move")
    Set events = after.Events(), found = ""
    Set it = events.%GetIterator()
    While it.%GetNext(, .e) { If e.ref [ "reminder:" Set found = e }
    Do $$$AssertTrue($ISOBJECT(found), "the audit trail has it")
    If $ISOBJECT(found) {
        Do $$$AssertEquals(found.kind, "note", "as a note")
        Do $$$AssertTrue(found.text [ "team@reminder.example.nhs.uk", "with who it went to")
        Do $$$AssertNotTrue(found.text [ "MRN9004", "and no identifier")
    }
    // The same threshold in a second digest records nothing twice.
    Set again = ..Digest()
    Do $$$AssertStatusOK(again.MarkSent("Accepted by relay", "2026-11-04T13:01:00Z"), "a second send of the same threshold is no error")
    Do $$$AssertEquals(##class(Shutter.Store.CaseReminder).Thresholds(..CaseRowId).%Size(), 1, "still one record")
}

Method TestAFailedSendIsRetriedAtTheNextRun()
{
    Set row = ..Digest()
    Do $$$AssertStatusOK(row.MarkFailed("Connection refused"), "failed")
    Do $$$AssertEquals(row.State, "failed", "failed")
    Do $$$AssertEquals(row.Body, "", "the text goes")
    Do $$$AssertEquals(row.Result, "Connection refused", "the reason stays")
    Do $$$AssertEquals(##class(Shutter.Store.CaseReminder).Thresholds(..CaseRowId).%Size(), 0, "no reminder is recorded")
    Do $$$AssertNotTrue(##class(Shutter.Store.ReminderDigest).LastSent("2026-11-04T12:00:00Z").%IsDefined("team@reminder.example.nhs.uk"), "and it does not count against the hour")
}

Method TestTheHourlyLimitCountsSentAndQueued()
{
    Set row = ..Digest()
    Do $$$AssertEquals(##class(Shutter.Store.ReminderDigest).LastSent("2026-11-04T12:00:00Z").%Get("team@reminder.example.nhs.uk"), "2026-11-04T12:00:00Z", "queued counts")
    Do row.MarkSent("ok", "2026-11-04T12:05:00Z")
    Do $$$AssertEquals(##class(Shutter.Store.ReminderDigest).LastSent("2026-11-04T12:10:00Z").%Get("team@reminder.example.nhs.uk"), "2026-11-04T12:05:00Z", "sent counts")
}

Method TestAStuckDigestExpires()
{
    Set row = ..Digest()
    Do ##class(Shutter.Store.ReminderDigest).ExpireStale("2026-11-04T12:29:59Z")
    Do row.%Reload()
    Do $$$AssertEquals(row.State, "queued", "under half an hour it waits")
    Do ##class(Shutter.Store.ReminderDigest).ExpireStale("2026-11-04T12:30:00Z")
    Do row.%Reload()
    Do $$$AssertEquals(row.State, "failed", "at half an hour it fails, so the next run builds it afresh")
    Do $$$AssertEquals(row.Body, "", "with its text gone")
}

/// The operation's last check: a digest late out of a stopped production never goes outside the window or stale.
Method TestTheLastCheckBeforeSending()
{
    Set row = ..Digest()
    Set on = ##class(Shutter.Util.CaseReminder).Settings({"reminders": {"enabled": true}, "feed": {"time_zone": "UTC"}, "mail": {"allowed_domains": ["reminder.example.nhs.uk"]}})
    Do $$$AssertEquals(row.SendProblem("2026-11-04T12:10:00Z", on, $LISTBUILD("reminder.example.nhs.uk")), "", "fine")
    Do $$$AssertTrue(row.SendProblem("2026-11-04T12:31:00Z", on, $LISTBUILD("reminder.example.nhs.uk")) [ "half an hour", "too old")
    Do $$$AssertTrue(row.SendProblem("2026-11-04T18:00:00Z", on, $LISTBUILD("reminder.example.nhs.uk")) '= "", "outside the window")
    Do $$$AssertTrue(row.SendProblem("2026-11-04T12:10:00Z", on, $LISTBUILD("other.example.nhs.uk")) [ "not in the allowed domains", "a domain taken off the list")
    Set off = ##class(Shutter.Util.CaseReminder).Settings({"reminders": {"enabled": false}, "feed": {"time_zone": "UTC"}})
    Do $$$AssertTrue(row.SendProblem("2026-11-04T12:10:00Z", off, $LISTBUILD("reminder.example.nhs.uk")) [ "off", "switched off since")
}

/// The gathering reads the stored case: its state, its team, what has been sent.
Method TestGatherReadsTheStore()
{
    Set s = ##class(Shutter.Util.CaseReminder).Settings({"reminders": {"enabled": true, "officer_address": "officer@reminder.example.nhs.uk"}, "feed": {"time_zone": "UTC"}})
    Set mine = ..Gathered(s)
    Do $$$AssertTrue($ISOBJECT(mine), "a blocked case is gathered")
    If $ISOBJECT(mine) {
        Do $$$AssertEquals(mine.state, "blocked", "its state")
        Do $$$AssertEquals(mine.patientId, "MRN9004", "its hospital number")
        Do $$$AssertEquals(mine.reminded.%Size(), 0, "nothing sent yet")
    }
    Do ..Digest().MarkSent("ok", "2026-11-04T12:01:00Z")
    Set mine = ..Gathered(s)
    Do $$$AssertEquals(mine.reminded.%ToJSON(), "[""team""]", "a new read sees what was sent")
}

/// The store's times are to the second: a case exactly at the threshold is gathered, as Decide counts it.
Method TestGatherIncludesACaseExactlyAtTheThreshold()
{
    Set s = ##class(Shutter.Util.CaseReminder).Settings({"reminders": {"enabled": true}, "feed": {"time_zone": "UTC"}})
    Set case = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set case.OpenedAt = "2026-11-04T08:00:00Z"
    Do $$$AssertStatusOK(case.%Save(), "opened exactly four hours before")
    Do $$$AssertTrue($ISOBJECT(..Gathered(s)), "gathered")
}

/// Outside the window it reads no case at all, and a case with every reminder it can get is not read again.
Method TestGatherReadsOnlyWhatCanGo()
{
    Set officer = ##class(Shutter.Util.CaseReminder).Settings({"reminders": {"enabled": true, "officer_address": "officer@reminder.example.nhs.uk"}, "feed": {"time_zone": "UTC"}})
    Set alone = ##class(Shutter.Util.CaseReminder).Settings({"reminders": {"enabled": true}, "feed": {"time_zone": "UTC"}})
    Do $$$AssertEquals(##class(Shutter.Util.CaseReminderTask).Gather(officer, "2026-11-04T07:59:59Z").%Size(), 0, "the window is shut: nothing is read")
    Do $$$AssertTrue($ISOBJECT(..Gathered(officer)), "the window is open: it is read")
    // The officer's record alone: the team's mail was refused or held, so the team's reminder is still to go.
    Do ..Digest("officer").MarkSent("ok", "2026-11-04T12:01:00Z")
    Do $$$AssertEquals(..Gathered(officer).reminded.%ToJSON(), "[""officer""]", "the officer's record alone leaves the team's to go")
    Do ..Digest("team").MarkSent("ok", "2026-11-04T12:02:00Z")
    Do $$$AssertNotTrue($ISOBJECT(..Gathered(officer)), "both recorded: not read again")
    Do $$$AssertNotTrue($ISOBJECT(..Gathered(alone)), "and with no officer set, the team's is all it can get")
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.CaseReminder WHERE ""Case"" = ?", ..CaseRowId)
    Do ##class(Shutter.Store.Case).%OpenId(..CaseRowId, 0).%Reload()
    Do $$$AssertTrue($ISOBJECT(..Gathered(officer)), "no record: read")
    Set case = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set case.Disposition = "abandoned"
    Do $$$AssertStatusOK(case.%Save(), "abandoned")
    Do $$$AssertNotTrue($ISOBJECT(..Gathered(officer)), "an abandoned case is not read")
}

Method Gathered(s As %DynamicObject) As %DynamicObject
{
    Set it = ##class(Shutter.Util.CaseReminderTask).Gather(s, "2026-11-04T12:00:00Z").%GetIterator()
    While it.%GetNext(, .c) { If c.caseId = ..#CASEID Return c }
    Quit ""
}

/// The first letter comes from the stored message and nothing else of it; a message gone gives none.
Method TestTheInitialIsReadFromTheMessage()
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString("MSH|^~\&|PAS|H|B|H|20261015082000||ADT^A02|M1|P|2.4"_$CHAR(13)_"PID|1||MRN9004^^^HOSP^MR||Jones^jane^^^Ms||19700102|F"_$CHAR(13))
    Do $$$AssertStatusOK(msg.%Save(), "the message")
    Set header = ##class(Ens.MessageHeader).%New()
    Set header.MessageBodyClassName = "EnsLib.HL7.Message", header.MessageBodyId = msg.%Id()
    Do $$$AssertStatusOK(header.%Save(), "its header")
    Set case = ##class(Shutter.Store.Case).%OpenId(..CaseRowId)
    Set case.SourceHeaderId = header.%Id()
    Do $$$AssertStatusOK(case.%Save(), "the case names it")
    Do $$$AssertEquals(##class(Shutter.Util.CaseReminderTask).Initial(..CaseRowId), "j", "the first letter of the first name")
    Do ##class(Ens.MessageHeader).%DeleteId(header.%Id())
    Do ##class(EnsLib.HL7.Message).%DeleteId(msg.%Id())
    Do $$$AssertEquals(##class(Shutter.Util.CaseReminderTask).Initial(..CaseRowId), "", "none when the message has gone")
}

/// The Doctor's words: off says nothing; on names what is missing.
Method TestTheDoctorsWarnings()
{
    Set off = ##class(Shutter.Util.CaseReminder).Warnings({"enabled": false}, "", "", 0, 0)
    Do $$$AssertEquals(off.%Size(), 0, "off: no warnings")
    Set none = ##class(Shutter.Util.CaseReminder).Warnings({"enabled": true, "officer_address": "", "sign_in_url": ""}, "", "", 0, 0)
    Set text = none.%ToJSON()
    For want = "mail server", "allowed mail domain", "officer", "team", "sign-in", "task" { Do $$$AssertTrue(text [ want, "warns of " _ want) }
    Set all = ##class(Shutter.Util.CaseReminder).Warnings({"enabled": true, "officer_address": "a@x.nhs.uk", "sign_in_url": "https://x/"}, "relay", $LISTBUILD("x.nhs.uk"), 1, 1)
    Do $$$AssertEquals(all.%Size(), 0, "with everything set: none")
}

}
