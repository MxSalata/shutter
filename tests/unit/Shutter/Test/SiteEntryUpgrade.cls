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
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), ##class(Shutter.Catalogue.SiteEntry).CheckedMark(), "and was rechecked by the seed, before any case is matched")
    Do $$$AssertNotTrue(##class(Shutter.Catalogue.SiteEntry).ById(id).NeedsReview, "with nothing to review")
    Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue.entry, id, "the case is still the site entry's")
    // A release that was never rechecked is rechecked by the first match under it.
    Set ^Shutter.Catalogue.Site("checked") = "0.0.0"
    Do $CLASSMETHOD(kit, "Snapshot", match)
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), ##class(Shutter.Catalogue.SiteEntry).CheckedMark(), "the first match under a new release rechecks first")
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
/// predicate whole. The entry then matches more, never less, and is flagged; nothing is retired or narrowed. A release
/// that knows the condition again does not narrow it back: only a newly approved version does.
Method TestAnUnknownConditionWidensTheEntry()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set full = ##class(Shutter.Catalogue.Vocabulary).Current()
    For gone = "the condition", "one of its values" {
        Do $CLASSMETHOD(kit, "PurgeAll")
        Do $CLASSMETHOD(kit, "Reset")
        Set full = ##class(Shutter.Catalogue.Vocabulary).Current()
        Set match = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO"}), near = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B"})
        Set discharge = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "event": "discharge"})
        Set body = $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId)
        Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", body, .id), "", gone _ ": an entry for a failed transfer into the ward")
        Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", discharge).SummaryObject().catalogue.entry '= id, 1, gone _ ": a discharge from the ward is not its case")
        Set generation = $CLASSMETHOD(site, "Generation")
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
        // A widening is a change of the catalogue: plans made before it are not completed (R17), as after an activation.
        Do $$$AssertEquals($CLASSMETHOD(site, "Generation"), generation + 1, gone _ " gone: the generation rose")
        // The vocabulary back: nothing narrows by itself.
        Do ##class(Shutter.Catalogue.Vocabulary).Use(full)
        Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 1, gone _ " back: the entry is still flagged")
        Set e = $CLASSMETHOD(site, "ById", id)
        Do $$$AssertTrue(e.NeedsReview, gone _ " back: needs review")
        Do $$$AssertEquals(e.EffectiveJSON, "{""delivery"":[""failed"",""rejected"",""uncertain""]}", gone _ " back: the predicate stays dropped")
        Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", discharge).SummaryObject().catalogue.entry, id, gone _ " back: the discharge is still its case")
        Do $$$AssertEquals($CLASSMETHOD(site, "Generation"), generation + 1, gone _ " back: and the generation did not move again")
        // A new version, approved by a second person, is a person's review: the flag and the drop clear.
        Set body.title = "A failed transfer into the isolation ward, reviewed"
        Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, body, e.Revision, "ut-author", "api", .e2, .problems, .warnings, .detail), "", gone _ ": a new version: " _ detail _ problems.%ToJSON())
        Do $$$AssertEquals($CLASSMETHOD(kit, "Approve", id, "activate"), "", gone _ ": approved by a second person")
        Set e = $CLASSMETHOD(site, "ById", id)
        Do $$$AssertNotTrue(e.NeedsReview, gone _ ": the flag is cleared by the approval")
        Do $$$AssertEquals(e.EffectiveJSON, "", gone _ ": the new version's own pattern stands")
        Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", discharge).SummaryObject().catalogue.entry '= id, 1, gone _ ": the discharge is not its case under the new version")
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
    Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, body, e.Revision, "ut-author", "api", .e2, .problems, .warnings, .detail), "", "a new version without the predicate: " _ detail _ problems.%ToJSON())
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
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), ##class(Shutter.Catalogue.SiteEntry).CheckedMark(), "the save rechecked the entries")
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
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "profile", 0), 1, "with the team back the flag stays, until a new version is approved")
    Do $$$AssertTrue($CLASSMETHOD(site, "ById", id).ReviewWords() [ ("no longer names the team " _ team), "and so does what it was for")
}

/// A profile save whose own recheck cannot take the lock leaves the cause waiting: the catch-up recheck that the next
/// read runs (here GET /catalogue's) records its event under the profile save, not as an upgrade, and then nothing waits.
Method TestACatchUpRecheckNamesItsCause()
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
    Set body.team = team
    Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", body, .id), "", "an entry that names a team of the profile")
    Kill ^Shutter.Test.SiteLock
    Job ##class(Shutter.Test.SiteKit).HoldTheLock()
    For i = 1:1:50 { Quit:$GET(^Shutter.Test.SiteLock)="held"  Hang 0.1 }
    Do $$$AssertEquals($GET(^Shutter.Test.SiteLock), "held", "another process holds the site entries' lock")
    Do profile.%Remove("teams"), profile.%Remove("version")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(profile.%ToJSON(), "unit test", "ut", "", .now), "the profile is saved without its teams while the lock is held")
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("cause")), "profile", "the recheck it could not run waits, for the profile save")
    Set ^Shutter.Test.SiteLock = "release"
    For i = 1:1:50 { Quit:$GET(^Shutter.Test.SiteLock)="done"  Hang 0.1 }
    Kill ^Shutter.Test.SiteLock
    Set view = ##class(Shutter.API.SiteEntries).CatalogueView()
    Set event = ##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0)
    Do $$$AssertEquals(event.kind, "rechecked", "the read ran the recheck")
    Do $$$AssertEquals(event.source, "profile", "under the cause that left it waiting")
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("cause")), "", "and nothing waits any more")
    // The profile as it was
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set row.Json = saved, row.Version = version
    Do row.%Save()
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.SiteProfileVersion WHERE Version > ?", version)
    Kill ^Shutter.Config("feedZone"), ^Shutter.Config("preventFailures")
}

/// Finding the widening once is enough: a fixture whose case is no longer stored narrows nothing, so a later recheck (here
/// after a save of the site profile) leaves the entry as widened and flagged.
Method TestAWideningIsKept()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set match = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO"}, .snap), near = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B"})
    Set body = $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId)
    Set body.pattern = {"event": "transfer", "delivery": ["failed", "rejected", "uncertain"], "receipt": "absent"}
    Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", body, .id), "", "an entry that also asks for no receipt")
    Set summary = snap.SummaryObject()
    Do summary.%Set("receipt_http_status", 200, "number")
    Set snap.Summary = summary.%ToJSON()
    Do $$$AssertStatusOK(snap.%Save(), "the stored evidence reads differently under the same digest")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 1, "the recheck widens and flags the entry")
    Set widened = $CLASSMETHOD(site, "ById", id).EffectiveJSON
    Do $$$AssertNotEquals(widened, "", "widened")
    // The retention purge takes the fixture's case; then the site profile is saved.
    Do $CLASSMETHOD(kit, "Purge", match.CaseId)
    Kill ^Shutter.Catalogue.Site("checked")
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    If $ISOBJECT(row) {
        Set saved = row.Json, version = row.Version
        Set profile = ##class(%DynamicObject).%FromJSON(saved)
        Do profile.%Remove("version")
        Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(profile.%ToJSON(), "unit test", "ut", "", .now), "the profile is saved")
        // Read before the profile is put back by hand, which is a save of its own.
        Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), ##class(Shutter.Catalogue.SiteEntry).CheckedMark(), "the save rechecked the entries")
        Set row = ##class(Shutter.Store.SiteProfile).Row()
        Set row.Json = saved, row.Version = version
        Do row.%Save()
        Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.SiteProfileVersion WHERE Version > ?", version)
        Kill ^Shutter.Config("feedZone"), ^Shutter.Config("preventFailures")
    } Else {
        Do $CLASSMETHOD(site, "Recheck", "profile", 0)
        Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), ##class(Shutter.Catalogue.SiteEntry).CheckedMark(), "the save rechecked the entries")
    }
    Set e = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertEquals(e.EffectiveJSON, widened, "the entry is still widened")
    Do $$$AssertTrue(e.NeedsReview, "and still flagged")
    Do $$$AssertTrue(e.ReviewWords() [ "receipt dropped", "the review still says what was dropped: " _ e.ReviewWords())
    Do $$$AssertTrue(e.ReviewWords() [ "is no longer stored", "and that the case is gone")
    Do $$$AssertNotTrue(##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0).text [ "nothing to review", "no event says there is nothing to review")
    Set same = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "summary": {"receipt_http_status": 200}})
    Do $$$AssertEquals(same.CurrentSnapshot.SummaryObject().catalogue.entry, id, "a case like the fixture as it now reads is still caught")
    // Suspended and resumed by two people, on the frozen copy of the purged fixture: the resumption keeps the widening.
    Do $$$AssertEquals($CLASSMETHOD(site, "Suspend", id, "unit test", "ut-approver", "api", .entry, .detail), "", "suspended: " _ detail)
    Do $$$AssertEquals($CLASSMETHOD(kit, "Approve", id, "resume"), "", "resumed by two people")
    Set e = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertEquals(e.State, "active", "it applies again")
    Do $$$AssertEquals(e.EffectiveJSON, widened, "still widened after the resumption")
    Do $$$AssertTrue(e.NeedsReview, "still flagged")
    Do $$$AssertTrue(e.ReviewWords() [ "receipt dropped", "and the review still says what was dropped")
    Set again = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "summary": {"receipt_http_status": 200}})
    Do $$$AssertEquals(again.CurrentSnapshot.SummaryObject().catalogue.entry, id, "a case like the fixture is still caught after the resumption")
}

/// A widened entry is retired and resumed as it is matched now: its proofs run on the pattern in force, so a resumption
/// is proved by the fixture whose new reading was the reason the condition was dropped (the case still stored), and a
/// retirement's impact counts a case only the widened pattern catches.
Method TestAWidenedEntryIsProvedAsItIsMatched()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set match = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO"}, .snap), near = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B"})
    Set body = $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId)
    Set body.pattern = {"event": "transfer", "delivery": ["failed", "rejected", "uncertain"], "receipt": "absent"}
    Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", body, .id), "", "an entry that also asks for no receipt")
    Set summary = snap.SummaryObject()
    Do summary.%Set("receipt_http_status", 200, "number")
    Set snap.Summary = summary.%ToJSON()
    Do $$$AssertStatusOK(snap.%Save(), "the fixture's evidence reads differently, its case still stored")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 1, "the recheck widens and flags the entry")
    Set widened = $CLASSMETHOD(site, "ById", id).EffectiveJSON
    Do $$$AssertNotEquals(widened, "", "widened")
    Set wide = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "summary": {"receipt_http_status": 200}})
    Do $$$AssertEquals(wide.CurrentSnapshot.SummaryObject().catalogue.entry, id, "a case only the widened pattern catches")
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "retire", "ut-author", "api", .retire, .detail), "", "a retirement is proved: " _ detail)
    Do $$$AssertTrue(retire.impact.caught > 0, "its impact counts what the entry catches now: " _ retire.impact.%ToJSON())
    Do $$$AssertEquals($CLASSMETHOD(site, "Suspend", id, "unit test", "ut-approver", "api", .entry, .detail), "", "suspended: " _ detail)
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "resume", "ut-author", "api", .resume, .detail), "", "a resumption is proved: " _ detail)
    Do $$$AssertTrue(resume.passed, "and passes on the fixture as it reads now: " _ resume.%ToJSON())
    Do $$$AssertEquals(resume.fixtures.%Get(0).source, "evidence", "read from the stored case")
    Do $$$AssertEquals($CLASSMETHOD(kit, "Approve", id, "resume"), "", "resumed by two people")
    Set e = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertEquals(e.State, "active", "it applies again")
    Do $$$AssertEquals(e.EffectiveJSON, widened, "still widened")
}

/// R14, the scope: a release that reads a scope fact of the entry's own matching fixture differently drops that fact, so
/// the entry matches more, and flags it. The scope fact here is the ward, as a release that read it with its facility
/// would give it.
Method TestAScopeFactThatReadsDifferentlyWidensTheEntry()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set match = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO"}), near = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B", "event": "discharge"})
    Set body = $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId)
    Set body.pattern = {"event": "transfer", "delivery": ["failed", "rejected", "uncertain"]}
    Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", body, .id), "", "an entry for the isolation ward, sent by PAS")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 0, "nothing to review while the fixture reads as it did")
    Set generation = $CLASSMETHOD(site, "Generation"), before = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    // The case's ward now reads with its facility.
    Set stored = ##class(Shutter.Store.Case).%OpenId(match.%Id())
    Set stored.Ward = "WARD-ISO^MAIN"
    Do $$$AssertStatusOK(stored.%Save(), "the ward reads differently")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 1, "the recheck flags the entry")
    Set e = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertTrue(e.NeedsReview, "needs review")
    Do $$$AssertEquals(e.EffectiveScopeJSON, "{""source_system"":[""PAS""]}", "the ward is dropped from the scope, the sending system kept")
    Do $$$AssertEquals(e.EffectiveJSON, "", "the pattern is untouched")
    Do $$$AssertTrue(e.ReviewWords() [ "the scope's ward dropped (case " _ match.CaseId _ " read WARD-ISO when the version was written and reads WARD-ISO^MAIN", "the review says what changed: " _ e.ReviewWords())
    Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", stored).SummaryObject().catalogue.entry, id, "the fixture's case is still caught")
    Set other = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO^MAIN"})
    Do $$$AssertEquals(other.CurrentSnapshot.SummaryObject().catalogue.entry, id, "and a case of the ward as it now reads")
    Do $$$AssertEquals($CLASSMETHOD(site, "ById", id).Describe().effectiveScope.%ToJSON(), "{""source_system"":[""PAS""]}", "the entry shows the scope it applies")
    Do $$$AssertEquals($CLASSMETHOD(site, "Generation"), generation + 1, "the widening raised the generation")
    Do $$$AssertNotEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), before, "so a plan made before it is under another version")
    // The ward back as it was: the scope does not narrow by itself.
    Set stored.Ward = "WARD-ISO"
    Do stored.%Save()
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 1, "still flagged")
    Do $$$AssertEquals($CLASSMETHOD(site, "ById", id).EffectiveScopeJSON, "{""source_system"":[""PAS""]}", "and still widened")
}

/// A recheck that cannot take the lock (an approval holds it) is not recorded: the next match tries again, and until one
/// completes under this release the matcher answers error for a site with active entries, never as if it had none.
Method TestARecheckThatCannotTakeTheLockIsTriedAgain()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Kill ^Shutter.Test.SiteLock
    Job ##class(Shutter.Test.SiteKit).HoldTheLock()
    For i = 1:1:50 { Quit:$GET(^Shutter.Test.SiteLock)="held"  Hang 0.1 }
    Do $$$AssertEquals($GET(^Shutter.Test.SiteLock), "held", "another process holds the site entries' lock")
    Try {
        Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "profile", 0, .ok), 0, "a recheck that cannot take the lock")
        Do $$$AssertNotTrue(ok, "does not complete")
        Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), "", "and the release is not recorded as checked")
        Set cat = $CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue
        Do $$$AssertEquals(cat.decision, "error", "the match answers error meanwhile")
        Do $$$AssertTrue(cat.error [ "rechecked", "saying why: " _ cat.error)
        Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", near).SummaryObject().catalogue.decision, "error", "for a case the entry does not match too")
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    Set ^Shutter.Test.SiteLock = "release"
    For i = 1:1:50 { Quit:$GET(^Shutter.Test.SiteLock)="done"  Hang 0.1 }
    Kill ^Shutter.Test.SiteLock
    Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue.entry, id, "once the lock is free the next match rechecks and the entry answers")
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), ##class(Shutter.Catalogue.SiteEntry).CheckedMark(), "and the release is recorded")
}

/// A recheck whose save fails is not recorded either, and leaves nothing half-done: here its event cannot be written
/// (a trigger word longer than the event's source allows), so the widening it found is rolled back with it. The next
/// recheck tries again.
Method TestARecheckThatCannotSaveLeavesTheReleaseUnchecked()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set full = ##class(Shutter.Catalogue.Vocabulary).Current()
    Set less = ##class(%DynamicObject).%FromJSON(full.%ToJSON())
    Do less.conditions.%Remove("event")
    Do ##class(Shutter.Catalogue.Vocabulary).Use(less)
    Set generation = $CLASSMETHOD(site, "Generation")
    Do $CLASSMETHOD(site, "Recheck", "an-upgrade-whose-event-cannot-be-written", 0, .ok)
    Do $$$AssertNotTrue(ok, "the recheck does not complete")
    // And it let the lock go: another process takes it at once.
    Kill ^Shutter.Test.SiteLock
    Job ##class(Shutter.Test.SiteKit).HoldTheLock()
    For i = 1:1:80 { Quit:(($GET(^Shutter.Test.SiteLock) = "held") || ($GET(^Shutter.Test.SiteLock) = "not held"))  Hang 0.1 }
    Do $$$AssertEquals($GET(^Shutter.Test.SiteLock), "held", "the lock is free after a recheck that failed")
    Set ^Shutter.Test.SiteLock = "release"
    For i = 1:1:50 { Quit:$GET(^Shutter.Test.SiteLock)="done"  Hang 0.1 }
    Kill ^Shutter.Test.SiteLock
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), "", "and the release is not recorded as checked")
    Set e = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertEquals(e.EffectiveJSON, "", "the widening is not saved without its event")
    Do $$$AssertNotEquals(##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0).kind, "rechecked", "and no event claims a recheck")
    Do $$$AssertEquals($CLASSMETHOD(site, "Generation"), generation, "nor is the generation raised by a recheck that did not land")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0, .ok), 1, "the next recheck tries again and flags the entry")
    Do $$$AssertTrue(ok, "completing")
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), ##class(Shutter.Catalogue.SiteEntry).CheckedMark(), "and the release is recorded")
    Do $$$AssertEquals($CLASSMETHOD(site, "ById", id).EffectiveJSON, "{""delivery"":[""failed"",""rejected"",""uncertain""]}", "with the widening saved")
    Do ##class(Shutter.Catalogue.Vocabulary).Use(full)
}

/// R13 for the query itself: a row the table's query cannot read (here the stored row is not a list at all) makes the
/// matcher answer error. Before, the listing stopped at it and the match went on as if the site had no entry.
Method TestARowTheQueryCannotReadIsNeverSkipped()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set rid = $CLASSMETHOD(site, "ById", id).%Id()
    Set node = ^Shutter.Catalogue.SiteEntryD(rid)
    Set ^Shutter.Catalogue.SiteEntryD(rid) = "not a list"
    Try {
        For case = match, near {
            Set cat = $CLASSMETHOD(kit, "Snapshot", case).SummaryObject().catalogue
            Do $$$AssertEquals(cat.decision, "error", case.Ward _ ": the matcher answers error: " _ cat.%ToJSON())
            Do $$$AssertEquals(cat.matches.%Size(), 0, case.Ward _ ": with no match")
        }
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    Set ^Shutter.Catalogue.SiteEntryD(rid) = node
    Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue.entry, id, "mended, the entry answers")
}

/// A fixture whose case is stored but whose evidence this release cannot read is a failure to report, not a case that
/// is gone: the recheck flags the entry, and a proof does not pass on the frozen copy. Before, both took it for a purge.
Method TestAFixtureThatCannotBeReadIsAFailure()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set match = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO"}, .snap), near = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B"})
    Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId), .id), "", "an active entry")
    Set snap.Summary = "{this release cannot read it"
    Do $$$AssertStatusOK(snap.%Save(), "the fixture's stored evidence no longer reads")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 1, "the recheck flags the entry")
    Set words = $CLASSMETHOD(site, "ById", id).ReviewWords()
    Do $$$AssertTrue(words [ ("Case " _ match.CaseId _ " is stored, but"), "saying the case could not be read: " _ words)
    Do $$$AssertNotTrue(words [ "no longer stored", "and not that it is gone")
    Set content = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1).Content()
    Set result = ##class(Shutter.Catalogue.SiteEntryProof).Run(id, 1, content, "activate", "ut-author", "api", 0, .proof)
    Do $$$AssertNotTrue(result.passed, "a proof does not pass")
    Do $$$AssertEquals(result.fixtures.%Get(0).source, "error", "its row says the case could not be read")
}

/// A save of the site profile while a recheck runs (or one whose own recheck could not take the lock) is never lost: the
/// recheck records what it read when it began, so the stored mark is another and the next match checks again. Before,
/// the racing recheck set the release as checked and the profile change was never rechecked.
Method TestAProfileSavedDuringARecheckIsCheckedAgain()
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
    Set body.team = team
    Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", body, .id), "", "an entry that names a team of the profile")
    Do $CLASSMETHOD(site, "Recheck", "upgrade", 0, .ok)
    // What a recheck that began before the save leaves when it ends.
    Set racing = $GET(^Shutter.Catalogue.Site("checked"))
    Kill ^Shutter.Test.SiteLock
    Job ##class(Shutter.Test.SiteKit).HoldTheLock()
    For i = 1:1:50 { Quit:$GET(^Shutter.Test.SiteLock)="held"  Hang 0.1 }
    Do $$$AssertEquals($GET(^Shutter.Test.SiteLock), "held", "a recheck holds the lock")
    Do profile.%Remove("teams"), profile.%Remove("version")
    Do $$$AssertStatusOK(##class(Shutter.Store.SiteProfile).Store(profile.%ToJSON(), "unit test", "ut", "", .now), "the profile is saved without its teams meanwhile")
    // The racing recheck ends after the save, and records what it checked.
    Set ^Shutter.Catalogue.Site("checked") = racing
    Set ^Shutter.Test.SiteLock = "release"
    For i = 1:1:50 { Quit:$GET(^Shutter.Test.SiteLock)="done"  Hang 0.1 }
    Kill ^Shutter.Test.SiteLock
    Try {
        Do $CLASSMETHOD(kit, "Snapshot", match)
        Set e = $CLASSMETHOD(site, "ById", id)
        Do $$$AssertTrue(e.NeedsReview, "the next match checked the entries again, and the entry is flagged")
        Do $$$AssertTrue(e.ReviewWords() [ ("no longer names the team " _ team), "for the team: " _ e.ReviewWords())
        Do $$$AssertTrue($CLASSMETHOD(site, "IsChecked"), "and the profile in force is recorded as checked")
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set row.Json = saved, row.Version = version
    Do $$$AssertStatusOK(row.%Save(), "the profile is put back")
    Do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM Shutter_Store.SiteProfileVersion WHERE Version > ?", version)
    Kill ^Shutter.Config("feedZone"), ^Shutter.Config("preventFailures")
}

/// Two entries in force for two wards: the second, for WARD-C.
ClassMethod Second(kit As %String, Output match2 As Shutter.Store.Case) As %String
{
    Set match2 = $CLASSMETHOD(kit, "Case", {"ward": "WARD-C"}), near2 = $CLASSMETHOD(kit, "Case", {"ward": "WARD-D"})
    Set body = $CLASSMETHOD(kit, "Body", match2.CaseId, near2.CaseId)
    Set body.title = "A failed transfer into ward C", body.scope.ward = ["WARD-C"]
    Set problem = $CLASSMETHOD(kit, "Activate", body, .id2)
    Quit $SELECT(problem = "": id2, 1: "")
}

/// A suspended entry is not in force: one whose row cannot be read is flagged on the Doctor and stops nothing. Before,
/// it kept the recheck from completing for ever, and every case on the site matched as error.
Method TestASuspendedEntryThatCannotBeReadStopsNothing()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "a first entry")
    Set id2 = ..Second(kit, .match2)
    Do $$$AssertNotEquals(id2, "", "a second entry")
    Do $$$AssertEquals($CLASSMETHOD(site, "Suspend", id, "unit test", "ut-approver", "api", .entry, .detail), "", "the first is suspended")
    Set rid = $CLASSMETHOD(site, "ById", id).%Id(), node = ^Shutter.Catalogue.SiteEntryD(rid)
    Set ^Shutter.Catalogue.SiteEntryD(rid) = "not a list"
    Kill ^Shutter.Catalogue.Site("checked")
    Try {
        Do $CLASSMETHOD(site, "Recheck", "upgrade", 0, .ok)
        Do $$$AssertTrue(ok, "the recheck completes")
        Set cat = $CLASSMETHOD(kit, "Snapshot", match2).SummaryObject().catalogue
        Do $$$AssertEquals(cat.entry, id2, "the entry in force answers, not error: " _ cat.%ToJSON())
        Set warnings = $CLASSMETHOD(site, "Status").warnings.%ToJSON()
        Do $$$AssertTrue(warnings [ ("Site entry " _ id _ " (suspended) could not be rechecked"), "the Doctor names the damaged one: " _ warnings)
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    Set ^Shutter.Catalogue.SiteEntryD(rid) = node
}

/// An active entry whose row cannot be read keeps every case at error (it cannot be told which cases it would catch),
/// with the Doctor naming it and the way out; an IRIS administrator sets it aside from the terminal, the row written again
/// as a suspended entry, recorded as an event, and the site's other entry applies again.
Method TestAnActiveEntryThatCannotBeRecheckedIsSetAside()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "a first entry")
    Set id2 = ..Second(kit, .match2)
    Do $$$AssertNotEquals(id2, "", "a second entry")
    Set rid = $CLASSMETHOD(site, "ById", id).%Id()
    Set ^Shutter.Catalogue.SiteEntryD(rid) = "not a list"
    Kill ^Shutter.Catalogue.Site("checked")
    Set cat = $CLASSMETHOD(kit, "Snapshot", match2).SummaryObject().catalogue
    Do $$$AssertEquals(cat.decision, "error", "every case is matched as error meanwhile")
    Do $$$AssertTrue(cat.error [ ("site entry " _ id _ " could not be rechecked"), "naming the entry: " _ cat.error)
    Set warnings = $CLASSMETHOD(site, "Status").warnings.%ToJSON()
    Do $$$AssertTrue(warnings [ "SiteEntriesSetAside", "the Doctor gives the way out: " _ warnings)
    Do $$$AssertEquals(##class(Shutter.Test.SiteEntryLifecycle).AwayFromTheTerminal("SiteEntriesSetAside", id), 1, "refused away from the terminal")
    Do $$$AssertNotEquals(##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0).kind, "set_aside", "and nothing was set aside")
    Do $$$AssertNotTrue(##class(%Dictionary.CompiledMethod).%OpenId("Shutter.Setup||SiteEntriesSetAside").SqlProc, "it is no SQL procedure")
    Set generation = $CLASSMETHOD(site, "Generation")
    Do $$$AssertEquals($CLASSMETHOD(site, "SetAside", id, "ut-admin", "its row is damaged", "terminal", .detail), "", "an administrator sets it aside: " _ detail)
    Set e = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertTrue($ISOBJECT(e), "its row reads again")
    If $ISOBJECT(e) {
        Do $$$AssertEquals(e.State, "suspended", "as a suspended entry")
        Do $$$AssertEquals(e.ActiveVersion, 1, "with its version in force")
        Do $$$AssertTrue(e.NeedsReview, "flagged for review")
        Do $$$AssertTrue(e.SuspendedReason [ "its row is damaged", "with the reason")
    }
    Do $$$AssertEquals(^Shutter.Catalogue.Site("damaged", rid), "not a list", "the damaged row is kept beside it")
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0).kind, "set_aside", "recorded as an event")
    Do $$$AssertEquals($CLASSMETHOD(site, "Generation"), generation + 1, "the generation rose")
    Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", match2).SummaryObject().catalogue.entry, id2, "the other entry applies again")
    Do $$$AssertNotEquals($CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue.entry, id, "and the one set aside does not")
    Do $$$AssertTrue($CLASSMETHOD(site, "Status").warnings.%ToJSON() [ (id _ " is suspended"), "it is warned about as a suspension")
}

/// A vocabulary file that is there but is not the vocabulary is never taken for the one in force: the recheck does not
/// complete, the release is not recorded as checked, and the matcher answers error until it loads. The catalogue's seed
/// does not record it either. Before, both checked the entries against the old vocabulary and recorded the release.
Method TestAVocabularyThatCannotBeLoadedLeavesTheReleaseUnchecked()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set root = $GET(^Shutter.Config("root")), file = ..CatalogueFile()
    Set dir = ##class(%File).NormalizeDirectory(##class(%File).GetDirectory(##class(%File).TempFilename("json")) _ "ut-site-vocabulary-" _ $JOB)
    Set folder = ##class(%File).NormalizeDirectory(dir _ "knowledge/catalogue")
    Do $$$AssertTrue(##class(%File).CreateDirectoryChain(folder), "a folder of its own")
    Set f = ##class(%Stream.FileCharacter).%New()
    Do f.LinkToFile(folder _ "vocabulary.json")
    Do f.Write("{this is not the vocabulary")
    Do $$$AssertStatusOK(f.%Save(), "a vocabulary file that does not read")
    Kill f
    Set ^Shutter.Config("root") = dir
    Try {
        Kill ^Shutter.Catalogue.Site("checked")
        Do $CLASSMETHOD(site, "Recheck", "upgrade", 1, .ok)
        Do $$$AssertNotTrue(ok, "the recheck does not complete")
        Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), "", "the release is not recorded as checked")
        Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue.decision, "error", "and the matcher answers error")
        If file '= "" {
            Do $$$AssertTrue(##class(%File).CopyFile(file, folder _ "catalogue.json"), "the catalogue beside it")
            Do $$$AssertStatusOK(##class(Shutter.Catalogue.Entry).SeedFromFile(folder _ "catalogue.json", .count), "the seed itself still runs")
            Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("checked")), "", "but records nothing as checked")
        } Else {
            Do $$$AssertSkipped("no installed catalogue file to seed from")
        }
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    Set ^Shutter.Config("root") = root
    Do ##class(%File).RemoveDirectoryTree(dir)
    If file '= "" Do ##class(Shutter.Catalogue.Entry).SeedFromFile(file, .count)
    Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue.entry, id, "with the vocabulary back the entry answers")
}

/// R14, the scope's own words: a release whose vocabulary no longer lists a scope fact the entry names drops that fact
/// whole, so the entry matches more, and flags it, even with every fixture's case purged.
Method TestAScopeFactTheVocabularyNoLongerKnowsIsDropped()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry for the ward and the sending system")
    Do $CLASSMETHOD(kit, "Purge", match.CaseId)
    Do $CLASSMETHOD(kit, "Purge", near.CaseId)
    Set full = ##class(Shutter.Catalogue.Vocabulary).Current()
    Set less = ##class(%DynamicObject).%FromJSON(full.%ToJSON())
    If '$ISOBJECT(less.site) Set less.site = {}
    Set less.site.scope = ["receiver", "ward", "reason_code"]
    Set generation = $CLASSMETHOD(site, "Generation")
    Do ##class(Shutter.Catalogue.Vocabulary).Use(less)
    Try {
        Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 1, "the recheck flags the entry")
        Set e = $CLASSMETHOD(site, "ById", id)
        Do $$$AssertEquals(e.EffectiveScopeJSON, "{""ward"":[""WARD-ISO""]}", "the sending system is dropped from the scope, the ward kept")
        Do $$$AssertTrue(e.ReviewWords() [ "the scope's source_system dropped (this release's vocabulary has no such scope fact)", "saying why: " _ e.ReviewWords())
        Do $$$AssertEquals($CLASSMETHOD(site, "Generation"), generation + 1, "the widening raised the generation")
        Set other = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "summary": {"operation": {"operation_key": "x", "payload_digest": "sha256:ut", "source_system": "OTHER"}}})
        Do $$$AssertEquals(other.CurrentSnapshot.SummaryObject().catalogue.entry, id, "a case of the ward from another sending system is caught")
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    Do ##class(Shutter.Catalogue.Vocabulary).Use(full)
}

/// A near miss the entry now matches is a widening this release made: the generation rises once, so a plan made before it
/// is not completed, as for a drop. Before, only a note was added and the catalogue's version stayed the same.
Method TestANearMissNowMatchedRaisesTheGeneration()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 0, "nothing to review yet")
    Set generation = $CLASSMETHOD(site, "Generation"), before = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    Set stored = ##class(Shutter.Store.Case).%OpenId(near.%Id())
    Set stored.Ward = "WARD-ISO"
    Do $$$AssertStatusOK(stored.%Save(), "the near miss now reads as the entry's ward")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 1, "the recheck flags the entry")
    Do $$$AssertTrue($CLASSMETHOD(site, "ById", id).ReviewWords() [ "which it was approved to leave alone", "saying why")
    Do $$$AssertEquals($CLASSMETHOD(site, "Generation"), generation + 1, "the generation rose")
    Do $$$AssertNotEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), before, "so the catalogue's version is another")
    Do $CLASSMETHOD(site, "Recheck", "upgrade", 0)
    Do $$$AssertEquals($CLASSMETHOD(site, "Generation"), generation + 1, "found once, it does not rise again")
}

/// A fixture whose case is purged leaves only the vocabulary and its frozen copy to check it by: the Doctor says so for
/// the entry, though nothing is flagged.
Method TestAPurgedFixtureIsSaid()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Do $CLASSMETHOD(kit, "Purge", match.CaseId)
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 0, "nothing is flagged")
    Set warnings = $CLASSMETHOD(site, "Status").warnings.%ToJSON()
    Do $$$AssertTrue(warnings [ ("Site entry " _ id _ ": the case of one or more of its fixtures is no longer stored"), "the Doctor says the check is narrower: " _ warnings)
    Do $$$AssertTrue($CLASSMETHOD(site, "ById", id).Describe().review.notes.%ToJSON() [ "frozen copy", "and the entry's notes say what was checked")
}

/// R13 for a later row: one readable entry, then one whose row the query cannot read. The match is error even for a case
/// the readable one leaves alone, never the readable prefix taken for the whole list.
Method TestALaterRowTheQueryCannotReadIsNeverSkipped()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "a first entry")
    Set id2 = ..Second(kit, .match2)
    Do $$$AssertNotEquals(id2, "", "a second entry")
    Set rid = $CLASSMETHOD(site, "ById", id2).%Id(), node = ^Shutter.Catalogue.SiteEntryD(rid)
    Set ^Shutter.Catalogue.SiteEntryD(rid) = "not a list"
    Try {
        Set cat = $CLASSMETHOD(kit, "Snapshot", near).SummaryObject().catalogue
        Do $$$AssertEquals(cat.decision, "error", "a case neither entry matches is error: " _ cat.%ToJSON())
        Set cat = $CLASSMETHOD(kit, "Snapshot", match2).SummaryObject().catalogue
        Do $$$AssertEquals(cat.decision, "error", "and so is the damaged entry's own case")
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    Set ^Shutter.Catalogue.SiteEntryD(rid) = node
}

/// A fixture whose case is stored but whose row cannot be opened is a failure, never taken for a case that is gone:
/// its replay says error, the proof does not pass and the recheck flags the entry. Before, the frozen copy answered.
Method TestAFixtureWhoseCaseCannotBeOpenedIsAFailure()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry", proofClass = "Shutter.Catalogue.SiteEntryProof"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set content = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1).Content(), fixture = ""
    Set it = content.fixtures.%GetIterator()
    While it.%GetNext(, .f) { If f.expect = "match" Set fixture = f Quit }
    Do $$$AssertTrue($ISOBJECT(fixture), "its matching fixture")
    Set cid = match.%Id(), caseId = match.CaseId
    Kill match, near
    Set node = ^Shutter.Store.CaseD(cid)
    Set ^Shutter.Store.CaseD(cid) = "not a list"
    Try {
        Do $CLASSMETHOD(proofClass, "Replay", fixture, .source, .why)
        Do $$$AssertEquals(source, "error", "the replay says the case could not be read: " _ why)
        Set result = $CLASSMETHOD(proofClass, "Run", id, 1, content, "activate", "ut-author", "api", 0, .proof)
        Do $$$AssertNotTrue(result.passed, "a proof does not pass")
        Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 1, "the recheck flags the entry")
        Set words = $CLASSMETHOD(site, "ById", id).ReviewWords()
        Do $$$AssertTrue(words [ ("Case " _ caseId _ " is stored, but"), "saying the case could not be read: " _ words)
        Do $$$AssertNotTrue(words [ "no longer stored", "and not that it is gone")
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    Set ^Shutter.Store.CaseD(cid) = node
}

/// A save of the site profile that committed and was never counted (its process ended between the two) is still
/// checked before the next case is matched: the profile's own version is part of what a recheck records. Before, the
/// entries were taken as checked and the change was never rechecked.
Method TestAProfileSaveThatWasNotCountedIsCheckedAgain()
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
    Set body.team = team
    Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", body, .id), "", "an entry that names a team of the profile")
    Do $CLASSMETHOD(site, "Recheck", "upgrade", 0, .ok)
    Do $$$AssertTrue($CLASSMETHOD(site, "IsChecked"), "the entries are checked")
    // The row as a save writes it, committed, and nothing counted after it.
    Do profile.%Remove("teams"), profile.%Remove("version")
    Set row.Json = profile.%ToJSON(), row.Version = version + 1
    Do $$$AssertStatusOK(row.%Save(), "the profile is saved without its teams, and the save is not counted")
    Kill ^Shutter.Config("feedZone"), ^Shutter.Config("preventFailures")
    Try {
        Do $$$AssertNotTrue($CLASSMETHOD(site, "IsChecked"), "the committed save is not taken for one already checked")
        Do $CLASSMETHOD(kit, "Snapshot", match)
        Set e = $CLASSMETHOD(site, "ById", id)
        Do $$$AssertTrue(e.NeedsReview, "the next match checked the entries again, and the entry is flagged")
        Do $$$AssertTrue(e.ReviewWords() [ ("no longer names the team " _ team), "for the team: " _ e.ReviewWords())
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    Set row = ##class(Shutter.Store.SiteProfile).Row()
    Set row.Json = saved, row.Version = version
    Do $$$AssertStatusOK(row.%Save(), "the profile is put back")
    Kill ^Shutter.Config("feedZone"), ^Shutter.Config("preventFailures")
}

/// A suspended entry whose version in force cannot be read is not in force, and is never taken for one that was checked:
/// the recheck completes, flags it and names it on the Doctor. Before, the recheck passed over it in silence.
Method TestASuspendedEntryWhoseVersionCannotBeReadIsFlagged()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Do $$$AssertEquals($CLASSMETHOD(site, "Suspend", id, "unit test", "ut-approver", "api", .entry, .detail), "", "suspended")
    Set e = $CLASSMETHOD(site, "ById", id)
    Do e.%Reload()
    Do $$$AssertNotTrue(e.NeedsReview, "not flagged yet")
    Set v = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1)
    Set json = v.Json, v.Json = "{""id"": ""L1"", ""pattern"": {"
    Do $$$AssertStatusOK(v.%Save(), "its version no longer reads")
    Kill ^Shutter.Catalogue.Site("checked")
    Try {
        Do $CLASSMETHOD(site, "Recheck", "upgrade", 0, .ok)
        Do $$$AssertTrue(ok, "the recheck completes: the entry is not in force")
        Do e.%Reload()
        Do $$$AssertTrue(e.NeedsReview, "the entry is flagged")
        Set warnings = $CLASSMETHOD(site, "Status").warnings.%ToJSON()
        Do $$$AssertTrue(warnings [ ("Site entry " _ id _ " (suspended) could not be rechecked"), "the Doctor names it: " _ warnings)
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    Set v.Json = json
    Do v.%Save()
}

/// Setting aside an entry whose copy this process already holds reads the row again from the disk: a row that cannot be
/// read is written again from its versions and events, never saved over from the copy in memory, and its note says what
/// earlier rechecks dropped cannot be told. Before, the copy in memory was saved.
Method TestASetAsideReadsAHeldCopyAgain()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set held = $CLASSMETHOD(site, "ById", id), rid = held.%Id(), node = ^Shutter.Catalogue.SiteEntryD(rid)
    Set ^Shutter.Catalogue.SiteEntryD(rid) = "not a list"
    Do $$$AssertEquals($CLASSMETHOD(site, "SetAside", id, "ut-admin", "its row is damaged", "terminal", .detail), "", "an administrator sets it aside: " _ detail)
    Do $$$AssertEquals($GET(^Shutter.Catalogue.Site("damaged", rid)), "not a list", "the damaged row is kept beside it")
    Do $$$AssertStatusOK(held.%Reload(), "the row reads again")
    Do $$$AssertEquals(held.State, "suspended", "as a suspended entry")
    Set words = held.ReviewWords()
    Do $$$AssertTrue(words [ "written again from its versions and events", "written again, not from the copy in memory: " _ words)
    Do $$$AssertTrue(words [ "cannot be told", "saying what earlier rechecks dropped cannot be told")
    If $GET(^Shutter.Catalogue.SiteEntryD(rid)) = "not a list" Set ^Shutter.Catalogue.SiteEntryD(rid) = node
}

}
