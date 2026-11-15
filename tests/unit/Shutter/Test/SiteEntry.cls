/// The rules a site's own catalogue entry is checked against before anything is stored (CONTRACTS 6.8, R1 to R5 and
/// R15), one row per refusal; the sentence that says an entry in plain words; and the report of the shipped entries a
/// pattern can displace, against the shipped catalogue. Nothing here activates an entry.
Class Shutter.Test.SiteEntry Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
    Quit ##class(Shutter.Test.SiteKit).Reset()
}

Method OnAfterAllTests() As %Status
{
    Do ##class(Shutter.Test.SiteKit).PurgeAll()
    Quit ##class(Shutter.Test.SiteKit).Reset()
}

/// A body's problems as "rule field" words, one per line.
ClassMethod Problems(body As %DynamicObject, Output warnings As %DynamicArray, Output content As %DynamicObject) As %String
{
    Do ##class(Shutter.Catalogue.SiteEntryVersion).Normalise(body, "", .content, .problems, .warnings, 0)
    Set out = "", it = problems.%GetIterator()
    While it.%GetNext(, .p) { Set out = out _ p.rule _ " " _ p.field _ $CHAR(10) }
    Quit out
}

Method TestAPlainEntryIsValid()
{
    Set body = ##class(Shutter.Test.SiteKit).Body()
    Set problems = ..Problems(body, .warnings, .content)
    Do $$$AssertEquals(problems, "", "no problem: " _ problems)
    Do $$$AssertEquals(warnings.%Size(), 0, "and no warning")
    Do $$$AssertEquals(content.kind, "stop", "the kind is stop")
    Do $$$AssertEquals(content.pattern.event.%ToJSON(), "[""transfer""]", "a single value is stored as a list")
    Do $$$AssertEquals(content.scope.ward.%ToJSON(), "[""WARD-ISO""]", "the scope's values are lists")
    Do $$$AssertTrue('content.%IsDefined("decides") && 'content.%IsDefined("preferred") && 'content.%IsDefined("alternatives"), "the stored form has no field for who decides or the outcome")
}

/// One row per refusal. Each changes the plain entry and names the rule and field that must refuse it.
Method TestEveryRefusal()
{
    Set long = ""
    For i = 1:1:210 { Set long = long _ "word " }
    Set rows = [
        {"name": "a kind other than stop", "set": {"kind": "permit"}, "expect": "R1 kind"},
        {"name": "who decides", "set": {"decides": "policy"}, "expect": "R1 decides"},
        {"name": "a preferred outcome", "set": {"preferred": {"outcome": "resend", "why": "it is safe"}}, "expect": "R1 preferred"},
        {"name": "alternatives", "set": {"alternatives": []}, "expect": "R1 alternatives"},
        {"name": "gate checks", "set": {"checks": ["ordering"]}, "expect": "R1 checks"},
        {"name": "an outcome", "set": {"outcome": "none"}, "expect": "R1 outcome"},
        {"name": "a field nobody knows", "set": {"colour": "red"}, "expect": "R1 colour"},
        {"name": "a priority that is not a number from 1 to 999", "set": {"priority": 0}, "expect": "R1 priority"},
        {"name": "no pattern", "remove": "pattern", "expect": "R3 pattern"},
        {"name": "an empty pattern", "set": {"pattern": {}}, "expect": "R3 pattern"},
        {"name": "a condition the vocabulary does not have", "set": {"pattern": {"weather": "rain"}}, "expect": "R3 pattern.weather"},
        {"name": "a value the condition does not take", "set": {"pattern": {"event": "teleport"}}, "expect": "R3 pattern.event"},
        {"name": "the condition a shipped entry answers first", "set": {"pattern": {"event": "transfer", "death_recorded": "yes"}}, "expect": "R3 pattern.death_recorded"},
        {"name": "a scope fact that is not one of the four", "set": {"scope": {"patient": ["MRN1"]}}, "expect": "R4 scope.patient"},
        {"name": "a scope that is not a map", "set": {"scope": ["WARD-ISO"]}, "expect": "R4 scope"},
        {"name": "a receiver the site profile does not name", "set": {"scope": {"receiver": ["No Such Receiver"]}}, "expect": "R4 scope.receiver"},
        {"name": "a team the site profile does not name", "set": {"team": "no-such-team"}, "expect": "R4 team"},
        {"name": "no title", "set": {"title": ""}, "expect": "R5 title"},
        {"name": "no why", "remove": "why", "expect": "R5 why"},
        {"name": "a title over 200 characters", "set": {"title": (long)}, "expect": "R5 title"},
        {"name": "words that are not text", "set": {"instructions": ["ring the ward"]}, "expect": "R5 instructions"},
        {"name": "a valid NHS number in the instructions", "set": {"instructions": "Ring about 999 100 1018 first"}, "expect": "R5 instructions"},
        {"name": "a valid NHS number in the why", "set": {"why": "As for 9991001018"}, "expect": "R5 why"},
        {"name": "a fixture that expects neither", "set": {"fixtures": [{"case": "C-000001", "expect": "maybe"}]}, "expect": "R1 fixtures"}
    ]
    Set it = rows.%GetIterator()
    While it.%GetNext(, .row) {
        Set body = ##class(Shutter.Test.SiteKit).Body()
        If row.%IsDefined("remove") Do body.%Remove(row.remove)
        If row.%IsDefined("set") {
            Set si = row.set.%GetIterator()
            While si.%GetNext(.key, .value) { Do body.%Set(key, value) }
        }
        Set problems = ..Problems(body)
        Do $$$AssertTrue(($CHAR(10) _ problems) [ ($CHAR(10) _ row.expect _ $CHAR(10)), row.name _ " is refused as " _ row.expect _ " (got: " _ $TRANSLATE(problems, $CHAR(10), ";") _ ")")
    }
}

/// A run of six or more digits that is no NHS number warns and refuses nothing; an entry with no instructions warns.
Method TestWarnings()
{
    Set body = ##class(Shutter.Test.SiteKit).Body()
    Set body.instructions = "Ring extension 555 0100"
    Do $$$AssertEquals(..Problems(body, .warnings), "", "a telephone number is no problem")
    Do $$$AssertEquals(warnings.%Size(), 1, "and warns once")
    Do $$$AssertEquals(warnings.%Get(0).rule, "R5", "under R5")
    Set body = ##class(Shutter.Test.SiteKit).Body()
    Do body.%Remove("instructions")
    Do $$$AssertEquals(..Problems(body, .warnings), "", "no instructions is no problem")
    Do $$$AssertEquals(warnings.%Get(0).field, "instructions", "and warns")
}

/// The words are cleaned as stored model text is: nothing invisible is kept.
Method TestWordsAreCleaned()
{
    Set body = ##class(Shutter.Test.SiteKit).Body()
    Set body.title = "A failed" _ $CHAR(8203) _ " transfer" _ $CHAR(7)
    Do ..Problems(body, , .content)
    Do $$$AssertEquals(content.title, "A failed transfer", "zero-width and control characters are gone")
}

/// A fixture is a stored, closed case; a case that is not there, or is still worked on, is refused when the draft is made.
Method TestFixturesAreStoredClosedCases()
{
    Set kit = "Shutter.Test.SiteKit"
    Set open = $CLASSMETHOD(kit, "Case", {"state": "awaiting_approval"})
    Set code = ##class(Shutter.Catalogue.SiteEntry).Create($CLASSMETHOD(kit, "Body", "UT-NO-SUCH-CASE"), "ut-author", "api", .entry, .problems, .warnings)
    Do $$$AssertEquals(code, "bad_request", "a case that is not there")
    Set code = ##class(Shutter.Catalogue.SiteEntry).Create($CLASSMETHOD(kit, "Body", open.CaseId), "ut-author", "api", .entry, .problems, .warnings)
    Do $$$AssertEquals(code, "bad_request", "a case still being worked on")
    Do $$$AssertTrue(problems.%Get(0).text [ "still being worked on", "says why: " _ problems.%Get(0).text)
    Set closed = $CLASSMETHOD(kit, "Case", {})
    Set code = ##class(Shutter.Catalogue.SiteEntry).Create($CLASSMETHOD(kit, "Body", closed.CaseId), "ut-author", "api", .entry, .problems, .warnings)
    Do $$$AssertEquals(code, "", "a closed case serves: " _ problems.%ToJSON())
    Set content = ##class(Shutter.Catalogue.SiteEntryVersion).Find(entry.EntryId, 1).Content()
    Set f = content.fixtures.%Get(0)
    Do $$$AssertEquals(f."snapshot_digest", closed.CurrentSnapshot.Digest, "the fixture keeps the snapshot's digest")
    Do $$$AssertEquals(f.conditions.event, "transfer", "a copy of the conditions")
    Do $$$AssertEquals(f.scope.ward, "WARD-ISO", "and of the scope facts")
    Do $$$AssertEquals(f.chain, "single", "and the chain kind")
    Do $$$AssertTrue(f.%ToJSON() '[ closed.PatientId, "with no patient identifier in it")
    Do $$$AssertEquals(entry.EntryId, "L1", "the first entry is L1")
    Do $$$AssertStatusOK($CLASSMETHOD(kit, "Reset"), "removed")
}

/// A draft made from a case: every condition the case showed (the reserved one aside), its scope facts, and the case
/// as the first fixture.
Method TestADraftFromACase()
{
    Set kit = "Shutter.Test.SiteKit"
    Set c = $CLASSMETHOD(kit, "Case", {})
    Set body = {"fromCase": (c.CaseId), "title": "From a case", "why": "The site says so."}
    Set code = ##class(Shutter.Catalogue.SiteEntry).Create(body, "ut-author", "api", .entry, .problems, .warnings)
    Do $$$AssertEquals(code, "", "made: " _ problems.%ToJSON())
    Set content = ##class(Shutter.Catalogue.SiteEntryVersion).Find(entry.EntryId, 1).Content()
    Do $$$AssertEquals(content.pattern.event.%Get(0), "transfer", "the event the case showed")
    Do $$$AssertEquals(content.pattern.delivery.%Get(0), "failed", "and its delivery")
    Do $$$AssertNotTrue(content.pattern.%IsDefined("death_recorded"), "never the reserved condition")
    Do $$$AssertEquals(content.scope.ward.%Get(0), "WARD-ISO", "the ward as scope")
    Do $$$AssertEquals(content.scope.receiver.%Get(0), c.Receiver, "and the receiver")
    Do $$$AssertEquals(content.fixtures.%Get(0).case, c.CaseId, "the case is the first fixture")
    Do $$$AssertEquals(content.fixtures.%Get(0).expect, "match", "expected to match")
    Do $$$AssertStatusOK($CLASSMETHOD(kit, "Reset"), "removed")
}

Method TestTheSentence()
{
    Do ..Problems(##class(Shutter.Test.SiteKit).Body(), , .content)
    Set sentence = ##class(Shutter.Catalogue.SiteEntryVersion).Sentence(content)
    Do $$$AssertEquals(sentence, "When a transfer from PAS fails, is rejected or gets no answer, and the ward is WARD-ISO: a person decides", "the entry in one sentence")
}

/// Which shipped entries a pattern can displace, condition by condition, against the shipped catalogue: a failed
/// transfer can displace E2 (they share failed and uncertain), never an entry for a delivery it does not name, and E19
/// is listed as the one that leads.
Method TestTheOverlapReport()
{
    Do $$$AssertTrue(##class(Shutter.Catalogue.Entry).Count() > 0, "the catalogue is installed")
    Do ..Problems(##class(Shutter.Test.SiteKit).Body(), , .content)
    Set overlap = ##class(Shutter.Catalogue.SiteEntryVersion).Overlap(content.pattern)
    Set it = overlap.%GetIterator()
    While it.%GetNext(, .row) { Set found(row.id) = row }
    Do $$$AssertTrue($DATA(found("E2")), "E2 can be displaced")
    Set shared = ""
    If $DATA(found("E2")) {
        Set ci = found("E2").conditions.%GetIterator()
        While ci.%GetNext(, .c) { If c.condition = "delivery" Set shared = c.shared.%ToJSON() }
    }
    Do $$$AssertEquals(shared, "[""failed"",""uncertain""]", "by the deliveries they share")
    Do $$$AssertTrue($DATA(found("E19")) && found("E19").leads, "E19 is listed as the entry that leads")
    // Every listed row shares a value on every condition both name; an entry that names a delivery the pattern does not
    // is not listed.
    Set entries = ##class(Shutter.Catalogue.Entry).All(), ei = entries.%GetIterator()
    While ei.%GetNext(, .e) {
        Set delivery = e.pattern.%Get("delivery"), event = e.pattern.%Get("event")
        Set can = 1
        If e.pattern.%IsDefined("delivery") {
            Set can = 0
            For word = "failed", "rejected", "uncertain" { If $SELECT($ISOBJECT(delivery): delivery.%ToJSON() [ ("""" _ word _ """"), 1: delivery = word) Set can = 1 }
        }
        If can && e.pattern.%IsDefined("event") Set can = $SELECT($ISOBJECT(event): event.%ToJSON() [ """transfer""", 1: event = "transfer")
        Do $$$AssertEquals($DATA(found(e.id)) > 0, can, e.id _ " is " _ $SELECT(can: "", 1: "not ") _ "listed")
    }
}

/// R15: with the most a site may have active, one more is refused.
Method TestAtMostFiftyActive()
{
    Set max = $PARAMETER("Shutter.Catalogue.SiteEntryVersion", "MAXACTIVE")
    Do $$$AssertEquals(max, 50, "the limit is 50")
    For i = 1:1:max {
        Set e = ##class(Shutter.Catalogue.SiteEntry).%New()
        Set e.EntryId = "L" _ (900 + i), e.State = "active", e.ActiveVersion = 1
        Do e.%Save()
    }
    Set problems = ..Problems(##class(Shutter.Test.SiteKit).Body())
    Do $$$AssertTrue(problems [ "R15", "one more is refused under R15: " _ problems)
    Set version = ##class(Shutter.Catalogue.Entry).ShippedVersion() _ ";g1:" _ ##class(Shutter.Catalogue.SiteEntry).ActiveIds()
    Do $$$AssertTrue($LENGTH(version) < 2000, "and the version string of a full site fits a plan's field: " _ $LENGTH(version) _ " characters")
    Do $$$AssertStatusOK(##class(Shutter.Test.SiteKit).Reset(), "removed")
    Do $$$AssertEquals(..Problems(##class(Shutter.Test.SiteKit).Body()), "", "and with none active the entry is valid again")
}

/// The catalogue is not replaced from any JSON on a site: SeedFromJSON answers on a demo instance only.
Method TestSeedFromJSONIsADemosTool()
{
    Set demo = $GET(^Shutter.Config("demo"))
    Set before = ##class(Shutter.Catalogue.Entry).ShippedVersion()
    Set ^Shutter.Config("demo") = 0
    Set answer = ##class(Shutter.Catalogue.Entry).SeedFromJSON("[{""id"": ""E1"", ""version"": 99, ""title"": ""x"", ""pattern"": {""event"": ""transfer""}, ""decides"": ""policy"", ""preferred"": {""outcome"": ""resend"", ""why"": ""x""}}]")
    Set ^Shutter.Config("demo") = demo
    Do $$$AssertTrue(answer [ "not a demo instance", "refused off a demo: " _ answer)
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).ShippedVersion(), before, "and the catalogue is as it was")
}

/// A shipped entry is E<n>: the seed refuses a file that names any other id, so no file can put a row where a site's
/// own entry is looked up.
Method TestTheSeedRefusesAnIdThatIsNotShipped()
{
    Set before = ##class(Shutter.Catalogue.Entry).ShippedVersion()
    Set path = ##class(%File).TempFilename("json")
    Set stream = ##class(%Stream.FileCharacter).%New()
    Do stream.LinkToFile(path)
    Do stream.Write("[{""id"": ""L7"", ""version"": 1, ""title"": ""x"", ""pattern"": {""event"": ""transfer""}, ""decides"": ""policy"", ""preferred"": {""outcome"": ""resend"", ""why"": ""x""}}]")
    Do stream.%Save()
    Set sc = ##class(Shutter.Catalogue.Entry).SeedFromFile(path, .count)
    Do ##class(%File).Delete(path)
    Do $$$AssertStatusNotOK(sc, "the seed refuses L7")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).ShippedVersion(), before, "and the catalogue is as it was")
    Do $$$AssertNotTrue($ISOBJECT(##class(Shutter.Catalogue.Entry).ById("L7")), "no L7 is there")
}

}
