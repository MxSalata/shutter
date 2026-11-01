/// The live hospital's feed logic (Shutter.Util.LiveFeed; CONTRACTS 4.4, v1.34) on text alone: synthetic patients with valid
/// NHS numbers, a scenario's messages rewritten for them at present times with their intervals kept, the fault keys, and the
/// ordinary messages a working hospital sends. The counters it moves are the live feed's own and are put back.
Class Shutter.Test.LiveFeed Extends %UnitTest.TestCase
{

Property Saved As %String [ MultiDimensional ];

Method OnBeforeAllTests() As %Status
{
    Merge ..Saved = ^Hospital.Live
    Kill ^Hospital.Live
    Quit $$$OK
}

Method OnAfterAllTests() As %Status
{
    Kill ^Hospital.Live
    Merge ^Hospital.Live = ..Saved
    Quit $$$OK
}

ClassMethod Fixture(name As %String) As %String
{
    Set path = $GET(^Shutter.Config("root")) _ "fixtures/S1/" _ name
    Set stream = ##class(%Stream.FileCharacter).%New()
    If $$$ISERR(stream.LinkToFile(path)) Quit ""
    Set text = ""
    While 'stream.AtEnd { Set text = text _ stream.Read(32000) }
    Quit text
}

Method TestPatients()
{
    Set p = ##class(Shutter.Util.LiveFeed).NewPatient(), q = ##class(Shutter.Util.LiveFeed).NewPatient()
    Do $$$AssertTrue($MATCH(p.mrn, "^MRN5[0-9]{5}$") && (p.mrn '= q.mrn), "fresh hospital numbers from the live range: " _ p.mrn)
    Do $$$AssertTrue($MATCH(p.enc, "^ENC-5[0-9]{5}$"), "a fresh encounter: " _ p.enc)
    Do $$$AssertTrue($MATCH(p.nhs, "^999[0-9]{7}$"), "an NHS number in the test range: " _ p.nhs)
    Set sum = 0
    For i = 1:1:9 { Set sum = sum + ($EXTRACT(p.nhs, i) * (11 - i)) }
    Do $$$AssertEquals((11 - (sum # 11)) # 11, +$EXTRACT(p.nhs, 10), "with a valid check digit")
    Do $$$AssertTrue((p.given '= "") && (p.family '= "") && $MATCH(p.dob, "^(19|20)[0-9]{6}$") && ((p.sex = "M") || (p.sex = "F")), "a name, a date of birth and a sex")
    Do $$$AssertEquals(##class(Shutter.Util.LiveFeed).NhsNumber("MRN1001"), "9991001018", "the fixtures' own numbering (fixtures/generate.py)")
}

Method TestShift()
{
    Do $$$AssertEquals(##class(Shutter.Util.LiveFeed).Shift("20261015092000", 3600), "20261015102000", "an hour on")
    Do $$$AssertEquals(##class(Shutter.Util.LiveFeed).Shift("20261015092000", -86400 * 20), "20260925092000", "twenty days back")
    Do $$$AssertEquals(##class(Shutter.Util.LiveFeed).Shift("202610150920", 60), "202610150921", "a shorter form keeps its length")
    Do $$$AssertEquals(##class(Shutter.Util.LiveFeed).Shift("", 60), "", "nothing stays nothing")
}

Method TestRewriteAScenario()
{
    Set a = ..Fixture("S1-01-A01.hl7"), b = ..Fixture("S1-02-A02.hl7"), c = ..Fixture("S1-03-A02.hl7")
    If a = "" { Do $$$AssertTrue(1, "the fixtures are not on this instance (no root); nothing to rewrite") Quit }
    Set texts = [(a), (b), (c)]
    Set map = ##class(Shutter.Util.LiveFeed).MapPatients(texts)
    Do $$$AssertEquals(map.patients.%Size(), 1, "one patient in S1")
    Set p = map.patients.%Get("MRN1001")
    Do $$$AssertTrue($ISOBJECT(p), "mapped by the fixture's hospital number")
    Do $$$AssertEquals(map.encounters.%Get("ENC-1001"), p.enc, "its encounter takes the patient's")
    Set delta = ##class(Shutter.Util.LiveFeed).DeltaFor(texts, "20261101120000")
    Set out = ##class(Shutter.Util.LiveFeed).Rewrite(c, map, delta, "BAY7", "LIVE1-03")
    Set msh = ##class(Shutter.Util.LiveFeed).Segment(out, "MSH"), pid = ##class(Shutter.Util.LiveFeed).Segment(out, "PID"), pv1 = ##class(Shutter.Util.LiveFeed).Segment(out, "PV1"), evn = ##class(Shutter.Util.LiveFeed).Segment(out, "EVN")
    Do $$$AssertEquals($PIECE(msh, "|", 10), "LIVE1-03", "a fresh control id")
    Do $$$AssertEquals($PIECE(evn, "|", 7), "20261101120000", "the last event of the scenario lands at now")
    Set first = ##class(Shutter.Util.LiveFeed).Rewrite(a, map, delta, "BAY7", "LIVE1-01")
    Do $$$AssertEquals($PIECE(##class(Shutter.Util.LiveFeed).Segment(first, "EVN"), "|", 7), "20261101111500", "the first event 45 minutes before, the interval kept")
    Do $$$AssertEquals($PIECE($PIECE($PIECE(pid, "|", 4), "~", 1), "^", 1), p.mrn, "the patient's hospital number")
    Do $$$AssertEquals($PIECE($PIECE($PIECE(pid, "|", 4), "~", 2), "^", 1), p.nhs, "and NHS number")
    Do $$$AssertEquals($PIECE(pid, "|", 6), p.family _ "^" _ p.given, "the name")
    Do $$$AssertEquals($PIECE($PIECE(pv1, "|", 20), "^", 1), p.enc, "the encounter")
    Do $$$AssertEquals($PIECE($PIECE(pv1, "|", 4), "^", 2), "BAY7", "the room of the play")
    Do $$$AssertEquals($PIECE($PIECE(pv1, "|", 4), "^", 1), "WARD-C", "the ward is the fixture's")
    Do $$$AssertEquals($PIECE($PIECE(pv1, "|", 7), "^", 2), "BAY7", "and the prior location's room too")
    // The fixtures' keys were made in Europe/London (09:20 BST is 08:20Z); the live profile reads the feed in UTC, so the
    // shifted message's 11:35 is the key's 11:35Z, and the hour the clocks changed in between does not move the fault.
    Set key = ##class(Shutter.Util.LiveFeed).RewriteKey("PAS^HOSP^MRN1001^ENC-1001^transfer^2026-10-15T08:20:00Z", map, delta, texts, "Europe/London", "UTC")
    Do $$$AssertEquals($PIECE(key, "^", 3) _ "|" _ $PIECE(key, "^", 4), p.mrn _ "|" _ p.enc, "a fault key names the mapped patient")
    Do $$$AssertEquals($PIECE(key, "^", 6), "2026-11-01T11:35:00Z", "at the shifted message's time as the live profile reads it")
    Set key = ##class(Shutter.Util.LiveFeed).RewriteKey("PAS^HOSP^MRN1001^ENC-1001^transfer^2026-10-15T08:20:00Z", map, delta, texts, "Europe/London", "Europe/London")
    Do $$$AssertEquals($PIECE(key, "^", 6), "2026-11-01T11:35:00Z", "the same under a London live profile in GMT")
    Set key = ##class(Shutter.Util.LiveFeed).RewriteKey("PAS^HOSP^MRN1001^ENC-1001^transfer^2026-10-15T08:21:00Z", map, delta, texts, "Europe/London", "UTC")
    Do $$$AssertEquals($PIECE(key, "^", 6), "2026-11-01T11:36:00Z", "a time no message carries is shifted with the zones' offsets")
    Do $$$AssertEquals(##class(Shutter.Util.LiveFeed).OffsetSeconds("Europe/London", "2026-10-15T09:20:00"), 3600, "BST is an hour")
    Do $$$AssertEquals(##class(Shutter.Util.LiveFeed).OffsetSeconds("UTC", "2026-11-01T12:00:00"), 0, "UTC none")
    Do $$$AssertTrue($MATCH(##class(Shutter.Util.LiveFeed).LocalNow("UTC"), "^20[0-9]{12}$"), "now as a DTM")
}

Method TestOrdinaryFeed()
{
    Set kinds = ""
    For i = 1:1:12 {
        Set text = ##class(Shutter.Util.LiveFeed).Ordinary("LIVEO-" _ i, .kind)
        Set kinds = kinds _ $LISTBUILD(kind)
        Set msh = ##class(Shutter.Util.LiveFeed).Segment(text, "MSH"), pv1 = ##class(Shutter.Util.LiveFeed).Segment(text, "PV1")
        Do $$$AssertTrue(($PIECE(msh, "|", 10) = "LIVEO-" _ i) && ($PIECE(msh, "|", 9) [ "ADT^A0"), "message " _ i _ " is an ADT with its control id: " _ $PIECE(msh, "|", 9))
        Do $$$AssertTrue($PIECE($PIECE(pv1, "|", 4), "^", 2) [ "LIVE", "placed in a live room: " _ $PIECE(pv1, "|", 4))
        Do $$$AssertTrue($PIECE($PIECE(pv1, "|", 20), "^", 1) '= "", "with an encounter")
        Do $$$AssertTrue($MATCH($PIECE(pv1, "|", 45), "^20[0-9]{12}$"), "and an admission time in PV1-44: " _ $PIECE(pv1, "|", 45))
        If kind = "discharge" Do $$$AssertTrue($MATCH($PIECE(pv1, "|", 46), "^20[0-9]{12}$"), "a discharge carries PV1-45")
    }
    Do $$$AssertTrue($LISTFIND(kinds, "admit") && $LISTFIND(kinds, "transfer"), "admissions and transfers among twelve messages: " _ $LISTTOSTRING(kinds))
    // Beds are held once: no two admitted patients share one.
    Set seen = "", clash = 0, mrn = ""
    For { Set mrn = $ORDER(^Hospital.Live("adm", mrn)) Quit:mrn=""  Set adm = ^Hospital.Live("adm", mrn), slot = $LIST(adm, 2) _ "/" _ $LIST(adm, 3) _ "/" _ $LIST(adm, 4) If $LISTFIND(seen, slot) Set clash = 1  Set seen = seen _ $LISTBUILD(slot) }
    Do $$$AssertNotTrue(clash, "no two live patients share a bed")
}

}
