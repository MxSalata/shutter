/// A site's own catalogue entries through failure and upgrade (CONTRACTS 6.8): a reseed of the shipped catalogue leaves
/// them; an empty shipped catalogue still gives the site match; an active row that cannot be read makes the matcher
/// answer error, never skipping it; and after an upgrade an entry can only come out matching more (R14): a predicate
/// this release's vocabulary no longer knows, or whose value on the entry's own fixture reads differently now, is dropped
/// whole and the entry flagged. A change of the site profile that removes what an entry names flags it. No active brake
/// is ever skipped in silence.
Class Shutter.Test.SiteEntryUpgrade Extends %UnitTest.TestCase
{

Method OnBeforeOneTest() As %Status
{
    Do ##class(Shutter.Test.SiteKit).PurgeAll()
    Quit ##class(Shutter.Test.SiteKit).Reset()
}

Method OnAfterAllTests() As %Status
{
    Do ##class(Shutter.Test.SiteKit).PurgeAll()
    Quit ##class(Shutter.Test.SiteKit).Reset()
}

/// The installed catalogue file, or "" when this instance has none to reseed from.
ClassMethod CatalogueFile() As %String
{
    Set root = $GET(^Shutter.Config("root"))
    If root = "" Quit ""
    Set path = ##class(%File).NormalizeDirectory(root) _ "knowledge/catalogue/catalogue.json"
    Quit $SELECT(##class(%File).Exists(path): path, 1: "")
}

Method TestAReseedLeavesTheEntries()
{
    Set kit = "Shutter.Test.SiteKit"
    Set path = ..CatalogueFile()
    If path = "" Do $$$AssertSkipped("no installed catalogue file to reseed from") Quit
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set version = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    Kill ^Shutter.Catalogue.Site("checked")
    Do $$$AssertStatusOK(##class(Shutter.Catalogue.Entry).SeedFromFile(path, .count), "the shipped catalogue is seeded again")
    Do $$$AssertTrue(count > 0, count _ " shipped entries")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), version, "the version still carries the site entry")
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntry).ById(id).State, "active", "which is still active")
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), $PARAMETER("Shutter.Setup", "VERSION"), "and was rechecked by the seed, before any case is matched")
    Do $$$AssertNotTrue(##class(Shutter.Catalogue.SiteEntry).ById(id).NeedsReview, "with nothing to review")
    Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue.entry, id, "the case is still the site entry's")
    // A release that was never rechecked is rechecked by the first match under it.
    Set ^Shutter.Catalogue.Site("checked") = "0.0.0"
    Do $CLASSMETHOD(kit, "Snapshot", match)
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), $PARAMETER("Shutter.Setup", "VERSION"), "the first match under a new release rechecks first")
}

Method TestAnEmptyShippedCatalogueStillGivesTheSiteMatch()
{
    Set kit = "Shutter.Test.SiteKit"
    Set path = ..CatalogueFile()
    If path = "" Do $$$AssertSkipped("no installed catalogue file to put the catalogue back from") Quit
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Do $$$AssertStatusOK(##class(Shutter.Catalogue.Entry).%KillExtent(), "the shipped catalogue is emptied")
    Try {
        Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).Count(), 0, "no shipped entry")
        Set cat = $CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue
        Do $$$AssertEquals(cat.decision, "person", "the site entry still answers: a person decides")
        Do $$$AssertEquals(cat.entry, id, "naming it")
        Do $$$AssertEquals(cat.overridden.%Size(), 0, "having displaced nothing")
        Do $$$AssertEquals(cat."catalogue_version", ";g1:" _ id _ "@1", "and the version is the site's part alone")
        Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", near).SummaryObject().catalogue.decision, "not_configured", "a case it does not match is not_configured, as before")
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    Do $$$AssertStatusOK(##class(Shutter.Catalogue.Entry).SeedFromFile(path, .count), "the shipped catalogue is put back")
    Do $$$AssertTrue(##class(Shutter.Catalogue.Entry).Count() > 0, "with its entries")
}

/// A damaged active row: the matcher answers error, and so does the gate's catalogue check, for a case the entry would
/// not even match. Nothing is skipped.
Method TestADamagedRowIsNeverSkipped()
{
    Set kit = "Shutter.Test.SiteKit"
    For damage = "the version's content is not JSON", "the version's row is gone", "the widened pattern is not JSON", "the pattern is not a map" {
        Do $CLASSMETHOD(kit, "PurgeAll")
        Do $CLASSMETHOD(kit, "Reset")
        Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
        Do $$$AssertEquals(problem, "", damage _ ": an active entry")
        Set v = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1)
        If damage = "the version's content is not JSON" {
            Set v.Json = "{""id"": ""L1"", ""pattern"": {"
            Do v.%Save()
        } ElseIf damage = "the version's row is gone" {
            Set vid = v.%Id()
            Kill v
            Do ##class(Shutter.Catalogue.SiteEntryVersion).%DeleteId(vid)
        } ElseIf damage = "the widened pattern is not JSON" {
            Set e = ##class(Shutter.Catalogue.SiteEntry).ById(id)
            Set e.EffectiveJSON = "{broken"
            Do e.%Save()
        } Else {
            Set content = v.Content()
            Set content.pattern = "event: transfer"
            Set v.Json = content.%ToJSON()
            Do v.%Save()
        }
        For case = match, near {
            Set snap = $CLASSMETHOD(kit, "Snapshot", case)
            Set cat = snap.SummaryObject().catalogue
            Do $$$AssertEquals(cat.decision, "error", damage _ ", " _ case.Ward _ ": the matcher answers error")
            Do $$$AssertTrue(cat.error [ id, damage _ ": naming the entry: " _ cat.error)
            Do $$$AssertEquals(cat.matches.%Size(), 0, damage _ ": with no match")
            // The rules path's plain resend on it: the gate's catalogue check is unknown, so nothing is written.
            Set plan = {"disposition": "resend", "action": {"type": "resend", "operation_key": (case.OperationKey), "expected_version": 3, "payload_digest": "sha256:ut"}, "summary": "unit test"}
            Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, snap, plan, "rules", .p), damage _ ": a resend plan")
            Set req = ##class(Shutter.Msg.GateRequest).%New()
            Set req.CaseId = case.CaseId, req.PlanId = p.%Id(), req.Stage = "proposal", req.Receiver = case.Receiver, req.ChainKind = "single"
            Set gate = ##class(Shutter.Operation.Gate).%New("Shutter Gate (unit test)")
            Do $$$AssertStatusOK(gate.OnGateRequest(req, .resp), damage _ ": the gate ran")
            Do $$$AssertTrue(resp.Summary [ "MATCHER_ERROR", damage _ ": MATCHER_ERROR: " _ resp.Summary)
            Do $$$AssertNotEquals(resp.Outcome, "pass", damage _ ": and the plan does not pass")
        }
        // The list and the status still answer, so a person can see it and act.
        Do $$$AssertTrue(##class(Shutter.Catalogue.SiteEntry).List().%Size() >= 1, damage _ ": the list still answers")
    }
}

/// R14, the vocabulary: a release that no longer knows one of the entry's conditions, or one of its values, drops that
/// predicate whole. The entry then matches more, never less, and is flagged; nothing is retired or narrowed.
Method TestAnUnknownConditionWidensTheEntry()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set match = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO"}), near = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B"})
    Set discharge = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "event": "discharge"})
    Set body = $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId)
    Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", body, .id), "", "an entry for a failed transfer into the ward")
    Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", discharge).SummaryObject().catalogue.entry '= id, 1, "a discharge from the ward is not its case")
    Set full = ##class(Shutter.Catalogue.Vocabulary).Current()
    For gone = "the condition", "one of its values" {
        Set less = ##class(%DynamicObject).%FromJSON(full.%ToJSON())
        If gone = "the condition" { Do less.conditions.%Remove("event") } Else { Set less.conditions.event = ["admit", "discharge", "update", "merge", "cancel", "other", "movement"] }
        Do ##class(Shutter.Catalogue.Vocabulary).Use(less)
        Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 1, gone _ " gone: the recheck flags the entry")
        Set e = $CLASSMETHOD(site, "ById", id)
        Do $$$AssertTrue(e.NeedsReview, gone _ " gone: needs review")
        Do $$$AssertEquals(e.State, "active", gone _ " gone: it is still active")
        Do $$$AssertEquals(e.EffectiveJSON, "{""delivery"":[""failed"",""rejected"",""uncertain""]}", gone _ " gone: the event predicate is dropped whole, the rest kept")
        Do $$$AssertTrue(e.ReviewWords() [ "event dropped", gone _ " gone: the review says which: " _ e.ReviewWords())
        Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue.entry, id, gone _ " gone: it still catches its own case")
        Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", discharge).SummaryObject().catalogue.entry, id, gone _ " gone: and now the discharge too: it matches more")
        Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", near).SummaryObject().catalogue.entry, "E2", gone _ " gone: the scope still holds it to the ward")
        Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1).Content().pattern.%IsDefined("event"), 1, gone _ " gone: the approved version itself is untouched")
        Do $$$AssertTrue($CLASSMETHOD(site, "Status").warnings.%Get(0) [ "needs review", gone _ " gone: the status warns")
        Set kinds = ##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0)
        Do $$$AssertEquals(kinds.kind, "rechecked", gone _ " gone: with an event")
        Do $$$AssertEquals(kinds.source, "upgrade", gone _ " gone: from the upgrade")
        // The vocabulary back: the entry's own pattern stands again.
        Do ##class(Shutter.Catalogue.Vocabulary).Use(full)
        Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 0, gone _ " back: nothing is flagged")
        Do $$$AssertEquals($CLASSMETHOD(site, "ById", id).EffectiveJSON, "", gone _ " back: the entry's own pattern stands")
        Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", discharge).SummaryObject().catalogue.entry '= id, 1, gone _ " back: the discharge is not its case again")
    }
}

/// R14, the fixture: a release that reads the entry's own matching fixture differently (here the stored evidence is
/// rewritten under the same digest, as a changed computation would read it) drops the predicate whose value changed.
Method TestAFixtureThatReadsDifferentlyWidensTheEntry()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set match = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO"}, .snap), near = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B"})
    Set body = $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId)
    Set body.pattern = {"event": "transfer", "delivery": ["failed", "rejected", "uncertain"], "receipt": "absent"}
    Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", body, .id), "", "an entry that also asks for no receipt")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 0, "nothing to review while the fixture reads as it did")
    // The same snapshot, read differently: the receipt lookup now reads as present.
    Set summary = snap.SummaryObject()
    Do summary.%Set("receipt_http_status", 200, "number")
    Set snap.Summary = summary.%ToJSON()
    Do $$$AssertStatusOK(snap.%Save(), "the stored evidence reads differently under the same digest")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 1, "the recheck flags the entry")
    Set e = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertEquals(e.EffectiveJSON, "{""delivery"":[""failed"",""rejected"",""uncertain""],""event"":[""transfer""]}", "the receipt predicate is dropped, the rest kept")
    Do $$$AssertTrue(e.ReviewWords() [ "read absent when the version was written and reads present", "the review says what changed: " _ e.ReviewWords())
    // The entry still catches a case like its fixture, which its own pattern would now miss.
    Set same = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "summary": {"receipt_http_status": 200}})
    Do $$$AssertEquals(same.CurrentSnapshot.SummaryObject().catalogue.entry, id, "a case that reads as the fixture now does is still caught")
    // A new approved version clears the flag: a person has looked.
    Set body.pattern = {"event": "transfer", "delivery": ["failed", "rejected", "uncertain"]}
    Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, body, "", "ut-author", "api", .e2, .problems, .warnings, .detail), "", "a new version without the predicate: " _ detail _ problems.%ToJSON())
    Do $$$AssertEquals($CLASSMETHOD(kit, "Approve", id, "activate"), "", "approved by a second person")
    Set e = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertNotTrue(e.NeedsReview, "the flag is cleared")
    Do $$$AssertEquals(e.ActiveVersion, 2, "version 2 is active")
    Do $$$AssertEquals(e.EffectiveJSON, "", "with its own pattern")
}

/// After a save of the site profile the entries are checked: a receiver or a team the profile no longer names flags the
/// entry that names it. It still applies.
Method TestAProfileChangeFlagsTheEntry()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If '$ISOBJECT(row) Do $$$AssertSkipped("no stored site profile on this instance") Quit
    Set saved = row.Json, version = row.Version
    Set profile = ##class(%DynamicObject).%FromJSON(saved)
    If '$ISOBJECT(profile.teams) || (profile.teams.%Size() = 0) Do $$$AssertSkipped("the stored site profile names no team") Quit
    Set team = profile.teams.%Get(0).id
    Set match = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO"}), near = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B"})
    Set body = $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId)
    Set body.team = team, body.scope.receiver = [(match.Receiver)]
    Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", body, .id), "", "an entry that names a receiver and a team of the profile")
    Kill ^Shutter.Catalogue.Site("checked")
    // The profile is saved without its teams, through the store's own save.
    Do profile.%Remove("teams"), profile.%Remove("version")
    Set sc = ##class(Shutter.Store.SiteProfile).Store(profile.%ToJSON(), "unit test", "ut", "", .now)
    Do $$$AssertStatusOK(sc, "the profile is saved without its teams")
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), $PARAMETER("Shutter.Setup", "VERSION"), "the save rechecked the entries")
    Set e = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertTrue(e.NeedsReview, "the entry is flagged")
    Do $$$AssertTrue(e.ReviewWords() [ ("no longer names the team " _ team), "for the team: " _ e.ReviewWords())
    Do $$$AssertEquals(e.State, "active", "and still applies")
    Do $$$AssertEquals(e.EffectiveJSON, "", "unchanged")
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0).source, "profile", "the event names the profile save")
    // The profile as it was: the row's text and version put back, and the history row this test added removed.
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set row.Json = saved, row.Version = version
    Do $$$AssertStatusOK(row.%Save(), "the profile is put back")
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.SiteProfileVersion WHERE Version > ?", version)
    Kill ^Shutter.Config("feedZone"), ^Shutter.Config("preventFailures")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "profile", 0), 0, "with the team back nothing is flagged")
}

}
