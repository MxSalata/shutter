/// The life of a site's own catalogue entry (CONTRACTS 6.8): a draft, a proof, a proposal, a second person's approval
/// of the exact action, version and digest, suspension by one approver, resumption and retirement by two, and what the
/// catalogue's version says at each step. The entries are the site's configuration: the store's purge leaves them and
/// the uninstall's step removes them.
Class Shutter.Test.SiteEntryLifecycle Extends %UnitTest.TestCase
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

/// A draft with its two fixtures; returns the entry's id.
Method Draft(Output match As Shutter.Store.Case, Output near As Shutter.Store.Case) As %String
{
    Set kit = "Shutter.Test.SiteKit"
    Set match = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO"}), near = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B"})
    Set code = ##class(Shutter.Catalogue.SiteEntry).Create($CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId), "ut-author", "api", .entry, .problems, .warnings)
    Do $$$AssertEquals(code, "", "the draft is made: " _ problems.%ToJSON())
    Quit $SELECT($ISOBJECT(entry): entry.EntryId, 1: "")
}

Method TestFromDraftToActive()
{
    Set site = "Shutter.Catalogue.SiteEntry"
    Set shipped = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    Do $$$AssertEquals(shipped, ##class(Shutter.Catalogue.Entry).ShippedVersion(), "a site that never had an entry keeps the shipped version string")
    Set id = ..Draft(.match, .near)
    Set entry = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertEquals(entry.ShownState(), "draft", "a draft")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), shipped, "a draft changes nothing")
    Do $$$AssertEquals(match.CurrentSnapshot.SummaryObject().catalogue.entry, "E2", "the matching case is E2's today")
    // No proof yet.
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "activate", "ut-author", "api", .entry, .detail), "no_proof", "no proposal without a proof: " _ detail)
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "activate", "ut-author", "api", .result, .detail), "", "the proof runs")
    Do $$$AssertTrue(result.passed, "and passes: " _ result.%ToJSON())
    Do $$$AssertEquals(result.fixtures.%Get(0).lead, id, "the entry leads on the matching case")
    Do $$$AssertEquals(result.fixtures.%Get(0).source, "evidence", "read from the stored evidence")
    Do $$$AssertTrue(result.fixtures.%Get(1).ok && 'result.fixtures.%Get(1).holds, "and leaves the near miss alone")
    Do $$$AssertTrue(result.impact.caught >= 1, "the impact counts the matching case: " _ result.impact.%ToJSON())
    Do $$$AssertTrue(result.impact.cases.%ToJSON() [ match.CaseId, "by its id")
    Do $$$AssertTrue(result.impact.cases.%ToJSON() '[ near.CaseId, "and not the near miss")
    Do $$$AssertEquals(result.context.release, $PARAMETER("Shutter.Setup", "VERSION"), "the proof is bound to the release")
    Do $$$AssertEquals(result.context."gate_policy", $PARAMETER("Shutter.Operation.Gate", "POLICYVERSION"), "and to the gate's policy")
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "activate", "ut-author", "api", .entry, .detail), "", "proposed: " _ detail)
    Do $$$AssertEquals(entry.ShownState(), "proposed", "the entry waits for approval")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), shipped, "a proposal changes nothing")
    // Frozen.
    Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, ##class(Shutter.Test.SiteKit).Body(match.CaseId, near.CaseId), "", "ut-author", "api", .e2, .problems, .warnings, .detail), "wrong_state", "a proposed version is frozen")
    Set digest = entry.ProposalDigest
    // The approval binds the action, the version and the digest, and needs a second person.
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, {"action": "retire", "version": 1, "digest": (digest), "decision": "approve", "reason": "ok"}, "ut-approver", "api", .e2, .detail, .extra), "digest_mismatch", "another action")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, {"action": "activate", "version": 2, "digest": (digest), "decision": "approve", "reason": "ok"}, "ut-approver", "api", .e2, .detail, .extra), "digest_mismatch", "another version")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, {"action": "activate", "version": 1, "digest": "sha256:other", "decision": "approve", "reason": "ok"}, "ut-approver", "api", .e2, .detail, .extra), "digest_mismatch", "another digest")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, {"action": "activate", "version": 1, "decision": "approve", "reason": "ok"}, "ut-approver", "api", .e2, .detail, .extra), "digest_mismatch", "no digest")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, {"action": "activate", "version": 1, "digest": (digest), "decision": "approve"}, "ut-approver", "api", .e2, .detail, .extra), "bad_request", "no reason")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, {"action": "activate", "version": 1, "digest": (digest), "decision": "approve", "reason": "ok"}, "ut-author", "api", .e2, .detail, .extra), "same_person", "the author cannot approve their own: " _ detail)
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), shipped, "nothing refused changed anything")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, {"action": "activate", "version": 1, "digest": (digest), "decision": "approve", "reason": "Agreed with infection control", "safetyReference": "HAZ-41"}, "ut-approver", "api", .e2, .detail, .extra), "", "a second person approves: " _ detail)
    Set entry = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertEquals(entry.State, "active", "active")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), shipped _ ";g1:" _ id _ "@1", "the catalogue's version carries the generation and the entry")
    Do $$$AssertEquals(extra.catalogueVersion, shipped _ ";g1:" _ id _ "@1", "the answer says so")
    Set v = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1)
    Do $$$AssertEquals(v.Status, "approved", "the version is approved")
    Do $$$AssertEquals(v.ApprovedBy, "ut-approver", "by the approver")
    Do $$$AssertEquals(v.SafetyReference, "HAZ-41", "with the site's safety reference")
    Do $$$AssertEquals(v.Release, $PARAMETER("Shutter.Setup", "VERSION"), "under this release")
    Do $$$AssertTrue(v.ProofId '= "", "on the proof run again at the approval")
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntryProof).%OpenId(v.ProofId).Origin, "approval", "which the approval ran")
    // The events, oldest first.
    Set kinds = "", it = ##class(Shutter.Catalogue.SiteEntryEvent).For(id).%GetIterator()
    While it.%GetNext(, .e) { Set kinds = e.kind _ $SELECT(kinds = "": "", 1: ",") _ kinds }
    Do $$$AssertEquals(kinds, "created,proved,proposed,approved,activated", "the events say what was done: " _ kinds)
    // The matcher now answers with the entry alone.
    Set snap = ##class(Shutter.Test.SiteKit).Snapshot(match)
    Set cat = snap.SummaryObject().catalogue
    Do $$$AssertEquals(cat.entry, id, "the matching case is the site entry's")
    Do $$$AssertEquals(cat.decision, "person", "a person decides")
    Do $$$AssertEquals(cat.outcome, "escalate", "escalate")
    Do $$$AssertEquals(cat.overridden.%Get(0).id, "E2", "E2 is shown as displaced")
    Do $$$AssertEquals(cat.overridden.%Get(0).outcome, "resend", "with what it would have done")
    Do $$$AssertEquals(##class(Shutter.Test.SiteKit).Snapshot(near).SummaryObject().catalogue.entry, "E2", "the near miss is still E2's")
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntry).CasesSent(id), 0, "no case sent to a person yet")
    // An approved version is never written again.
    Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, ##class(Shutter.Test.SiteKit).Body(match.CaseId, near.CaseId), $CLASSMETHOD(site, "ById", id).Revision, "ut-author", "api", .e2, .problems, .warnings, .detail), "", "a change of an active entry begins version 2 as a draft: " _ detail)
    Set entry = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertEquals(entry.DraftVersion, 2, "version 2")
    Do $$$AssertEquals(entry.ActiveVersion, 1, "beside the active version 1, which keeps applying")
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1).Digest, digest, "whose content is untouched")
}

/// A stale proof is refused at the proposal and at the approval: the catalogue moved under it.
Method TestAStaleProofIsRefused()
{
    Set site = "Shutter.Catalogue.SiteEntry", kit = "Shutter.Test.SiteKit"
    Set id = ..Draft(.match, .near)
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "activate", "ut-author", "api", .result, .detail), "", "proved")
    // Another entry is activated meanwhile: the proof's context names the other active entries.
    Set other = $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId)
    Set other.title = "Another", other.priority = 50
    Do $$$AssertEquals($CLASSMETHOD(kit, "Activate", other, .otherId, "ut-author-2", "ut-approver"), "", "another entry is activated")
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "activate", "ut-author", "api", .entry, .detail), "no_proof", "the proof is stale at the proposal")
    Do $$$AssertTrue(detail [ "stale", "and says so: " _ detail)
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "activate", "ut-author", "api", .result, .detail), "", "proved again")
    Do $$$AssertTrue(result.passed, "it passes: the entry's priority 10 leads over 50")
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "activate", "ut-author", "api", .entry, .detail), "", "proposed")
    // And the other entry is suspended before the approval: stale again.
    Do $$$AssertEquals($CLASSMETHOD(site, "Suspend", otherId, "too broad", "ut-approver", "api", .e2, .detail), "", "the other is suspended")
    Set body = {"action": "activate", "version": 1, "digest": (entry.ProposalDigest), "decision": "approve", "reason": "ok"}
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, body, "ut-approver", "api", .e2, .detail, .extra), "proof_failed", "the approval refuses a stale proof: " _ detail)
    Do $$$AssertEquals($CLASSMETHOD(site, "ById", id).ShownState(), "proposed", "and the entry still waits")
    // The proof can be run again on a proposed version, whose content is frozen; then the approval goes through.
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "activate", "ut-author", "api", .result, .detail), "", "proved a third time")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, body, "ut-approver", "api", .e2, .detail, .extra), "", "approved on the proof run since: " _ detail)
    Do $$$AssertEquals($CLASSMETHOD(site, "ById", id).State, "active", "active")
}

/// The proof run again at the approval must answer as the proposal's did: evidence that reads differently refuses it.
Method TestTheProofIsRunAgainAtApproval()
{
    Set site = "Shutter.Catalogue.SiteEntry", kit = "Shutter.Test.SiteKit"
    Set id = ..Draft(.match, .near)
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "activate", "ut-author", "api", .result, .detail), "", "proved")
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "activate", "ut-author", "api", .entry, .detail), "", "proposed")
    // The near miss's stored evidence is rewritten so that the entry now matches it (its digest kept).
    Set near.Ward = "WARD-ISO"
    Do $$$AssertStatusOK(near.%Save(), "the near case now names the isolation ward")
    Set body = {"action": "activate", "version": 1, "digest": (entry.ProposalDigest), "decision": "approve", "reason": "ok"}
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, body, "ut-approver", "api", .e2, .detail, .extra), "proof_failed", "the approval's own proof fails: " _ detail)
    Do $$$AssertEquals($CLASSMETHOD(site, "ById", id).State, "draft", "and nothing is activated")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), ##class(Shutter.Catalogue.Entry).ShippedVersion(), "the catalogue's version is the shipped one still")
}

/// R8 as amended: a match alone is not a proof; a near miss is required too.
Method TestAProofNeedsAMatchAndANearMiss()
{
    Set site = "Shutter.Catalogue.SiteEntry", kit = "Shutter.Test.SiteKit"
    Set match = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO"}), near = $CLASSMETHOD(kit, "Case", {"ward": "WARD-B"})
    Do $$$AssertEquals($CLASSMETHOD(site, "Create", $CLASSMETHOD(kit, "Body", match.CaseId), "ut-author", "api", .entry, .problems, .warnings), "", "a draft with a match only")
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", entry.EntryId, "activate", "ut-author", "api", .result, .detail), "", "the proof runs")
    Do $$$AssertNotTrue(result.passed, "and does not pass without a near miss")
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", entry.EntryId, "activate", "ut-author", "api", .e2, .detail), "no_proof", "so nothing is proposed")
    Do $$$AssertEquals($CLASSMETHOD(site, "Create", $CLASSMETHOD(kit, "Body", , near.CaseId), "ut-author", "api", .entry, .problems, .warnings), "", "a draft with a near miss only")
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", entry.EntryId, "activate", "ut-author", "api", .result, .detail), "", "the proof runs")
    Do $$$AssertNotTrue(result.passed, "and does not pass without a match")
    // A fixture that answers the wrong way.
    Set wrong = $CLASSMETHOD(kit, "Body", near.CaseId, match.CaseId)
    Do $$$AssertEquals($CLASSMETHOD(site, "Create", wrong, "ut-author", "api", .entry, .problems, .warnings), "", "a draft with the two the wrong way round")
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", entry.EntryId, "activate", "ut-author", "api", .result, .detail), "", "the proof runs")
    Do $$$AssertNotTrue(result.passed, "and does not pass")
    Do $$$AssertTrue('result.fixtures.%Get(0).ok && 'result.fixtures.%Get(1).ok, "neither fixture answers as expected")
}

/// One approver suspends at once; resuming and retiring take two people; the generation only ever rises.
Method TestSuspendResumeRetire()
{
    Set site = "Shutter.Catalogue.SiteEntry", kit = "Shutter.Test.SiteKit"
    Set shipped = ##class(Shutter.Catalogue.Entry).ShippedVersion()
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Do $$$AssertEquals($CLASSMETHOD(site, "Suspend", id, "", "ut-approver", "api", .entry, .detail), "bad_request", "a suspension needs a reason")
    Do $$$AssertEquals($CLASSMETHOD(site, "Suspend", id, "It floods the on-call with escalations", "ut-approver", "api", .entry, .detail), "", "one person suspends it")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), shipped _ ";g2:", "the version keeps the suffix with no entry active, at generation 2")
    Do $$$AssertEquals($CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue.entry, "E2", "the case is the shipped catalogue's again")
    Set status = $CLASSMETHOD(site, "Status")
    Do $$$AssertEquals(status.suspended.%Get(0), id, "the status lists the suspended entry")
    Do $$$AssertTrue(status.warnings.%Get(0) [ "suspended", "with a warning: " _ status.warnings.%Get(0))
    Do $$$AssertTrue(##class(%DynamicObject).%FromJSON(##class(Shutter.Setup).Doctor())."site_entries".warnings.%Get(0) [ "suspended", "which the Doctor shows")
    Do $$$AssertEquals($CLASSMETHOD(site, "Suspend", id, "again", "ut-approver", "api", .entry, .detail), "wrong_state", "a suspended entry is not suspended again")
    // Resuming is an approval: a proof, a proposal, a second person.
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "resume", "ut-approver", "api", .result, .detail), "", "the resumption is proved")
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "resume", "ut-approver", "api", .entry, .detail), "", "and proposed")
    Set body = {"action": "resume", "version": 1, "digest": (entry.ProposalDigest), "decision": "approve", "reason": "narrowed elsewhere"}
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, body, "ut-approver", "api", .e2, .detail, .extra), "same_person", "the proposer cannot approve it")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, body, "ut-author", "api", .e2, .detail, .extra), "", "another person does: " _ detail)
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), shipped _ ";g3:" _ id _ "@1", "generation 3: never the string of generation 1 again")
    Do $$$AssertEquals($CLASSMETHOD(site, "Status").warnings.%Size(), 0, "the warning is gone with the suspension")
    // A retirement's proof is its impact read the other way.
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "retire", "ut-author", "api", .entry, .detail), "no_proof", "a retirement needs its proof too")
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "retire", "ut-author", "api", .result, .detail), "", "the retirement is proved")
    Do $$$AssertTrue(result.passed, "it passes")
    Do $$$AssertTrue(result.impact.cases.%ToJSON() [ match.CaseId, "its impact lists the case the entry catches: " _ result.impact.%ToJSON())
    Do $$$AssertTrue(result.impact.groups.%Size() >= 1, "grouped by what it would do without it: " _ result.impact.groups.%ToJSON())
    Do $$$AssertEquals($CLASSMETHOD(kit, "Approve", id, "retire"), "", "proposed and approved by two people")
    Set entry = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertEquals(entry.State, "retired", "retired")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), shipped _ ";g4:", "generation 4")
    Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId), "", "ut-author", "api", .e2, .problems, .warnings, .detail), "wrong_state", "a retired entry is not changed again")
    // The id is never used again.
    Do $$$AssertEquals($CLASSMETHOD(site, "Create", $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId), "ut-author", "api", .next, .problems, .warnings), "", "a new draft")
    Do $$$AssertNotEquals(next.EntryId, id, "takes a new id: " _ next.EntryId)
    Do $$$AssertEquals(+$EXTRACT(next.EntryId, 2, *), +$EXTRACT(id, 2, *) + 1, "the next number")
}

/// expectedVersion on a change, as the site profile has it.
Method TestAChangeChecksTheRevision()
{
    Set site = "Shutter.Catalogue.SiteEntry", kit = "Shutter.Test.SiteKit"
    Set id = ..Draft(.match, .near)
    Set entry = $CLASSMETHOD(site, "ById", id)
    Set body = $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId)
    Set body.title = "A changed title"
    Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, body, entry.Revision + 5, "ut-author-2", "api", .e2, .problems, .warnings, .detail), "stale_version", "a revision that is not the entry's")
    Do $$$AssertEquals(+detail, +entry.Revision, "the refusal carries the current one")
    Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, body, entry.Revision, "ut-author-2", "api", .e2, .problems, .warnings, .detail), "", "the right one")
    Set v = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1)
    Do $$$AssertEquals(v.Content().title, "A changed title", "the draft is rewritten")
    Do $$$AssertEquals(v.WrittenBy, "ut-author-2", "by who changed it last")
    // The person who last changed the version cannot approve it, whoever proposes.
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "activate", "ut-author", "api", .result, .detail), "", "proved")
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "activate", "ut-author", "api", .entry, .detail), "", "proposed by another")
    Set approve = {"action": "activate", "version": 1, "digest": (entry.ProposalDigest), "decision": "approve", "reason": "ok"}
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, approve, "ut-author-2", "api", .e2, .detail, .extra), "same_person", "who wrote the version does not approve it")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, approve, "ut-author", "api", .e2, .detail, .extra), "same_person", "nor who proposed it")
    // A rejection, with its reason, makes it a draft again; either of them may reject.
    Set reject = {"action": "activate", "version": 1, "digest": (entry.ProposalDigest), "decision": "reject", "reason": "Too broad: name the receiver"}
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, reject, "ut-author", "api", .e2, .detail, .extra), "", "rejected: " _ detail)
    Do $$$AssertEquals($CLASSMETHOD(site, "ById", id).ShownState(), "draft", "a draft again")
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0).kind, "rejected", "with the event")
    Do $$$AssertTrue(##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0).text [ "Too broad", "and the reason")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, reject, "ut-author", "api", .e2, .detail, .extra), "wrong_state", "no proposal is left to decide")
}

/// expectedVersion is required: a change that does not say which revision it read is refused, as a stale one is.
Method TestAChangeNeedsTheRevision()
{
    Set site = "Shutter.Catalogue.SiteEntry", kit = "Shutter.Test.SiteKit"
    Set id = ..Draft(.match, .near)
    Set entry = $CLASSMETHOD(site, "ById", id)
    Set body = $CLASSMETHOD(kit, "Body", match.CaseId, near.CaseId)
    Set body.title = "A changed title"
    For none = "", " " {
        Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, body, none, "ut-author-2", "api", .e2, .problems, .warnings, .detail), "stale_version", "no revision given (""" _ none _ """)")
        Do $$$AssertEquals(+detail, +entry.Revision, "the refusal carries the current one")
    }
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1).Content().title, $CLASSMETHOD(kit, "Body").title, "and the draft is unchanged")
}

/// A proposal whose frozen version was rewritten under it (a change that raced the proposal) is never approved, and can
/// always be rejected back to a draft, so the entry is never stuck.
Method TestARewrittenProposalCanBeRejected()
{
    Set site = "Shutter.Catalogue.SiteEntry"
    Set id = ..Draft(.match, .near)
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "activate", "ut-author", "api", .result, .detail), "", "proved")
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "activate", "ut-author", "api", .entry, .detail), "", "proposed")
    Set digest = entry.ProposalDigest
    // The frozen version rewritten, as a change that slipped past the proposal would leave it.
    Set v = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1)
    Set content = v.Content()
    Set content.title = "Rewritten after the proposal"
    Set v.Json = ##class(Shutter.Util.Digest).Canonical(content), v.Digest = ##class(Shutter.Catalogue.SiteEntryVersion).DigestOf(content)
    Do $$$AssertStatusOK(v.%Save(), "the frozen version is rewritten")
    Set approve = {"action": "activate", "version": 1, "digest": (digest), "decision": "approve", "reason": "ok"}
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, approve, "ut-approver", "api", .e2, .detail, .extra), "digest_mismatch", "it is not approved")
    Set reject = {"action": "activate", "version": 1, "digest": (digest), "decision": "reject", "reason": "The version changed after it was proposed"}
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, reject, "ut-approver", "api", .e2, .detail, .extra), "", "it is rejected: " _ detail)
    Set entry = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertEquals(entry.ShownState(), "draft", "a draft again")
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0).kind, "rejected", "with the event")
    Do $$$AssertEquals($CLASSMETHOD(site, "Change", id, ##class(Shutter.Test.SiteKit).Body(match.CaseId, near.CaseId), entry.Revision, "ut-author", "api", .e2, .problems, .warnings, .detail), "", "and the draft can be changed again: " _ detail)
}

/// The two-person rule reads a user name whatever its letters' case: IRIS signs in ALICE and alice as one user.
Method TestTheTwoPersonRuleIgnoresTheLettersCase()
{
    Set site = "Shutter.Catalogue.SiteEntry"
    Set id = ..Draft(.match, .near)
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "activate", "ut-author", "api", .result, .detail), "", "proved")
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "activate", "ut-proposer", "api", .entry, .detail), "", "proposed by another")
    Set approve = {"action": "activate", "version": 1, "digest": (entry.ProposalDigest), "decision": "approve", "reason": "ok"}
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, approve, "UT-PROPOSER", "api", .e2, .detail, .extra), "same_person", "the proposer in capitals is the proposer")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, approve, "Ut-Author", "api", .e2, .detail, .extra), "same_person", "the version's author in mixed case is its author")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, approve, "ut-approver", "api", .e2, .detail, .extra), "", "a second person approves: " _ detail)
}

/// A proposal and a rejection are each written with their event, or not at all: here the event cannot be written (a
/// source word longer than the event allows), and the entry is left as it was.
Method TestAProposalAndARejectionKeepTheirEvent()
{
    Set site = "Shutter.Catalogue.SiteEntry", long = "a-source-longer-than-an-event-takes"
    Set id = ..Draft(.match, .near)
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "activate", "ut-author", "api", .result, .detail), "", "proved")
    Set revision = $CLASSMETHOD(site, "ById", id).Revision
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "activate", "ut-author", long, .entry, .detail), "failed", "a proposal whose event fails")
    Set entry = $CLASSMETHOD(site, "ById", id)
    Do $$$AssertEquals(entry.ProposalAction, "", "is not made")
    Do $$$AssertEquals(entry.Revision, revision, "and the row is as it was")
    Do $$$AssertNotEquals(##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0).kind, "proposed", "with no event")
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "activate", "ut-author", "api", .entry, .detail), "", "proposed")
    Set reject = {"action": "activate", "version": 1, "digest": (entry.ProposalDigest), "decision": "reject", "reason": "Too broad"}
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, reject, "ut-approver", long, .e2, .detail, .extra), "failed", "a rejection whose event fails")
    Do $$$AssertEquals($CLASSMETHOD(site, "ById", id).ProposalAction, "activate", "is not made: the proposal still waits")
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntryEvent).For(id).%Get(0).kind, "proposed", "and its event is the last")
}

/// The two-person rule is lifted only from the terminal by an IRIS administrator: never over SQL or a route. With it
/// lifted, one person's approval of their own entry is recorded as such, and the status says so for as long as it holds.
Method TestOnlyAnAdministratorLiftsTheTwoPersonRule()
{
    Set site = "Shutter.Catalogue.SiteEntry", kit = "Shutter.Test.SiteKit"
    // The suite runs through an SQL procedure, which is not the terminal.
    If $ISOBJECT($GET(%sqlcontext)) || $ISOBJECT($GET(%request)) {
        Do $$$AssertTrue(##class(Shutter.Setup).SiteEntriesOnePerson(1, "unit test") [ "terminal only", "refused away from the terminal")
        Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(site, "OnePerson")), "and nothing is lifted")
    }
    Do $$$AssertNotTrue(##class(%Dictionary.CompiledMethod).%OpenId("Shutter.Setup||SiteEntriesOnePerson").SqlProc, "it is no SQL procedure")
    Set id = ..Draft(.match, .near)
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "activate", "ut-author", "api", .result, .detail), "", "proved")
    Do $$$AssertEquals($CLASSMETHOD(site, "Propose", id, "activate", "ut-author", "api", .entry, .detail), "", "proposed")
    Set approve = {"action": "activate", "version": 1, "digest": (entry.ProposalDigest), "decision": "approve", "reason": "the only approver"}
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, approve, "ut-author", "api", .e2, .detail, .extra), "same_person", "refused while the rule holds")
    Do $$$AssertStatusOK($CLASSMETHOD(site, "SetOnePerson", 1, "ut-admin", "One approver this month, change record CR-12"), "an administrator lifts it")
    Do $$$AssertTrue($CLASSMETHOD(site, "Status").warnings.%Get(0) [ "two-person rule", "the status warns for as long as it holds")
    Do $$$AssertEquals($CLASSMETHOD(site, "Decide", id, approve, "ut-author", "api", .e2, .detail, .extra), "", "the same person approves: " _ detail)
    Set text = "", it = ##class(Shutter.Catalogue.SiteEntryEvent).For(id).%GetIterator()
    While it.%GetNext(, .e) { If e.kind = "approved" Set text = e.text }
    Do $$$AssertTrue(text [ "same person", "and the approval's event says so: " _ text)
    Do $$$AssertStatusOK($CLASSMETHOD(site, "SetOnePerson", 0, "ut-admin", ""), "the rule is restored")
    Do $$$AssertEquals($CLASSMETHOD(site, "Status").warnings.%Size(), 0, "and the warning goes")
    Set kinds = "", it = ##class(Shutter.Catalogue.SiteEntryEvent).For("").%GetIterator()
    While it.%GetNext(, .e) { Set kinds = kinds _ e.kind _ " " }
    Do $$$AssertTrue((kinds [ "two_person_lifted") && (kinds [ "two_person_restored"), "both are events: " _ kinds)
}

/// The entries are the site's configuration, as the site profile is: the store's purge leaves them, and the uninstall's
/// step names and removes them. A fixture whose case went with a purge answers from its frozen copy.
Method TestThePurgeLeavesThemAndTheUninstallTakesThem()
{
    Set site = "Shutter.Catalogue.SiteEntry", kit = "Shutter.Test.SiteKit"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set version = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    // The purge's own list of classes and the scenario reset name none of the site's tables.
    For method = "Shutter.Setup||PurgeStore", "Shutter.Scenarios.Runner||Reset" {
        Set code = ##class(%Dictionary.MethodDefinition).%OpenId(method).Implementation.Read(1000000)
        Do $$$AssertTrue(code '[ "Shutter.Catalogue.Site", $PIECE(method, "||", 2) _ " does not touch the site's entries")
    }
    // The cases go, as a purge takes them: the fixtures fall back to their frozen conditions.
    Set matchId = match.CaseId
    Kill match, near
    Do $CLASSMETHOD(kit, "PurgeAll")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), version, "the entry is still active")
    Do $$$AssertEquals($CLASSMETHOD(site, "Prove", id, "resume", "ut-author", "api", .result, .detail), "wrong_state", "(an active entry is not resumed)")
    Set content = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1).Content()
    Set result = ##class(Shutter.Catalogue.SiteEntryProof).Run(id, 1, content, "activate", "ut-author", "api", 0, .proof)
    Do $$$AssertTrue(result.passed, "the proof still passes: " _ result.%ToJSON())
    Do $$$AssertEquals(result.fixtures.%Get(0).source, "frozen", "from the frozen conditions, and it says so")
    Do $$$AssertEquals(result.fixtures.%Get(0).case, matchId, "for the case that is gone")
    Do $$$AssertEquals($CLASSMETHOD(site, "Recheck", "upgrade", 0), 0, "a recheck flags nothing for a purged fixture")
    Set review = $CLASSMETHOD(site, "ById", id).ReviewWords()
    Do $$$AssertTrue(review [ "no longer stored", "and says its evidence was not read again: " _ review)
    // The uninstall names them, then removes them.
    Set out = {"removed": [], "errors": []}
    Do ##class(Shutter.Util.Uninstall).TakeSiteEntries(out)
    Do $$$AssertEquals(out.errors.%Size(), 0, "the uninstall's step runs")
    Do $$$AssertTrue(out.removed.%Get(0) [ "1 in all, 1 active", "and names what it took: " _ out.removed.%Get(0))
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(site, "ById", id)), "the entry is gone")
    Do $$$AssertEquals(##class(Shutter.Catalogue.Entry).CatalogueVersion(), ##class(Shutter.Catalogue.Entry).ShippedVersion(), "and the catalogue's version is the shipped one")
}

/// The administrator's lift of the two-person rule and its event are written together: when the event cannot be
/// written (here a source word longer than the event takes), the rule still holds and the call says so.
Method TestTheLiftIsWrittenWithItsEvent()
{
    Set site = "Shutter.Catalogue.SiteEntry"
    Set sc = $CLASSMETHOD(site, "SetOnePerson", 1, "ut-admin", "One approver this month", "a-source-longer-than-an-event-takes")
    Do $$$AssertNotTrue($SYSTEM.Status.IsOK(sc), "the lift whose event fails is refused")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(site, "OnePerson")), "and the rule still holds")
    Do $$$AssertStatusOK($CLASSMETHOD(site, "SetOnePerson", 1, "ut-admin", "One approver this month"), "lifted, with its event")
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(site, "OnePerson")), "lifted")
    Set sc = $CLASSMETHOD(site, "SetOnePerson", 0, "ut-admin", "", "a-source-longer-than-an-event-takes")
    Do $$$AssertNotTrue($SYSTEM.Status.IsOK(sc), "a restore whose event fails is refused")
    Do $$$AssertTrue($ISOBJECT($CLASSMETHOD(site, "OnePerson")), "and the lift is as it was")
    Do $$$AssertStatusOK($CLASSMETHOD(site, "SetOnePerson", 0, "ut-admin", ""), "restored")
    Do $$$AssertNotTrue($ISOBJECT($CLASSMETHOD(site, "OnePerson")), "the rule holds again")
}

/// A retirement stands on its impact alone, so one for which no stored case could be read does not pass.
Method TestARetirementNeedsAReadableImpact()
{
    Set kit = "Shutter.Test.SiteKit", site = "Shutter.Catalogue.SiteEntry"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    // Every stored case this proof would scan becomes unreadable, and is put back after.
    Set saved = 0
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 200 c.ID AS cid, c.CurrentSnapshot AS sid FROM Shutter_Store.""Case"" c WHERE c.CurrentSnapshot IS NOT NULL ORDER BY c.ID DESC")
    While rs.%Next() {
        Set snap = ##class(Shutter.Store.Snapshot).%OpenId(rs.%Get("sid"))
        Continue:'$ISOBJECT(snap)
        Set saved = saved + 1, saved(saved) = $LISTBUILD(snap.%Id(), snap.Summary)
        Set snap.Summary = "{unreadable"
        Do snap.%Save()
    }
    Try {
        Set content = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1).Content()
        Set result = ##class(Shutter.Catalogue.SiteEntryProof).Run(id, 1, content, "retire", "ut-author", "api", 1, .proof)
        Do $$$AssertEquals(result.impact.unread, result.impact.scanned, "no case could be read: " _ result.impact.%ToJSON())
        Do $$$AssertNotTrue(result.passed, "the retirement's proof does not pass")
        Do $$$AssertTrue(result.problems.%ToJSON() [ "could be read", "saying why: " _ result.problems.%ToJSON())
    } Catch ex {
        Do $$$AssertTrue(0, "failed: " _ ex.DisplayString())
    }
    For i = 1:1:saved {
        Set snap = ##class(Shutter.Store.Snapshot).%OpenId($LIST(saved(i), 1))
        Set snap.Summary = $LIST(saved(i), 2)
        Do snap.%Save()
    }
    Set result = ##class(Shutter.Catalogue.SiteEntryProof).Run(id, 1, ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1).Content(), "retire", "ut-author", "api", 1, .proof)
    Do $$$AssertTrue(result.passed, "with the cases readable again it passes")
}

}
