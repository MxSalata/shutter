/// The safety property of a site's own catalogue entries (CONTRACTS 6.8), checked over the matcher itself: for any
/// conditions and any site entry, where the entry does not match, the matcher's result is the one it gives with no site
/// entries; where it matches, the result is that entry alone, person, escalate, with no alternatives; and a death on the
/// message still answers first. A site entry can therefore only ever send a case to a person. The conditions are every
/// row of the matcher's own table (Shutter.Test.Matcher), one set built from each shipped entry's pattern, and seeded
/// random sets over the vocabulary; the entries are every single condition and value of the vocabulary, and seeded
/// random conjunctions with scopes. Then stored rows that claim to decide by policy or to resend, written straight into
/// the tables, and the gate on each shape of write on a case a site entry matched.
Class Shutter.Test.SiteSafety Extends %UnitTest.TestCase
{

Method OnBeforeAllTests() As %Status
{
    Do ##class(Shutter.Test.SiteKit).PurgeAll()
    Quit ##class(Shutter.Test.SiteKit).Reset()
}

Method OnAfterAllTests() As %Status
{
    Do ##class(Shutter.Test.SiteKit).PurgeAll()
    Quit ##class(Shutter.Test.SiteKit).Reset()
}

/// The conditions the property is checked on, each {conditions, scope}.
ClassMethod Samples() As %DynamicArray
{
    Set out = [], matcher = "Shutter.Catalogue.Matcher"
    Set vocabulary = ##class(Shutter.Catalogue.Vocabulary).Current().conditions
    Set scopes = [{"receiver": "Downstream Out", "source_system": "PAS", "ward": "WARD-ISO", "reason_code": "ward_unavailable"}, {"receiver": "Records Out", "source_system": "LAB", "ward": "WARD-B", "reason_code": "bed_occupied"}, {}]
    // Every row of the matcher's own table.
    Set it = ##class(Shutter.Test.Matcher).Rows().%GetIterator()
    While it.%GetNext(.i, .row) {
        Try { Do out.%Push({"conditions": (##class(Shutter.Test.Matcher).Conditions(row)), "scope": (scopes.%Get(i # 3))}) } Catch ex { }
    }
    // One set from each shipped entry's pattern: its first allowed value for each condition it names, the vocabulary's
    // first value for the rest, so that every shipped entry is matched by a sample.
    Set ei = ##class(Shutter.Catalogue.Entry).All().%GetIterator()
    While ei.%GetNext(.i, .e) {
        Set c = {}, vi = vocabulary.%GetIterator()
        While vi.%GetNext(.name, .values) {
            Set named = e.pattern.%Get(name)
            Do c.%Set(name, $SELECT($ISOBJECT(named): named.%Get(0), e.pattern.%IsDefined(name): named, name = "death_recorded": "no", 1: values.%Get(0)))
        }
        Do out.%Push({"conditions": (c), "scope": (scopes.%Get(i # 3))})
    }
    // Seeded random sets.
    Set seed = 20261115
    For n = 1:1:120 {
        Set c = {}, vi = vocabulary.%GetIterator()
        While vi.%GetNext(.name, .values) {
            Set seed = ((seed * 1103515245) + 12345) # 2147483648
            Do c.%Set(name, values.%Get(seed # values.%Size()))
        }
        Do out.%Push({"conditions": (c), "scope": (scopes.%Get(n # 3))})
    }
    Quit out
}

/// The site entries the property is checked with, as the matcher reads one.
ClassMethod Entries() As %DynamicArray
{
    Set out = []
    Set vocabulary = ##class(Shutter.Catalogue.Vocabulary).Current().conditions
    Set n = 0, vi = vocabulary.%GetIterator()
    While vi.%GetNext(.name, .values) {
        Continue:(name = "death_recorded")
        Set wi = values.%GetIterator()
        While wi.%GetNext(, .word) {
            Set n = n + 1
            Do out.%Push({"id": ("L" _ n), "version": 1, "title": (name _ " " _ word), "priority": 100, "scope": {}, "pattern": ({}.%Set(name, [(word)])), "why": "unit test", "team": "", "instructions": "", "prose": ""})
        }
    }
    // Seeded random conjunctions of two or three conditions, half of them with a scope.
    Set seed = 49, names = ""
    Set vi = vocabulary.%GetIterator()
    While vi.%GetNext(.name) { If name '= "death_recorded" Set names = names _ $LISTBUILD(name) }
    For k = 1:1:40 {
        Set pattern = {}
        For j = 1:1:(2 + (k # 2)) {
            Set seed = ((seed * 1103515245) + 12345) # 2147483648
            Set name = $LIST(names, (seed # $LISTLENGTH(names)) + 1), values = vocabulary.%Get(name)
            Set seed = ((seed * 1103515245) + 12345) # 2147483648
            Set list = [(values.%Get(seed # values.%Size()))]
            If values.%Size() > 1 Do list.%Push(values.%Get((seed + 1) # values.%Size()))
            Do pattern.%Set(name, list)
        }
        Set scope = $SELECT(k # 2: {"ward": ["WARD-ISO"], "source_system": ["PAS"]}, 1: {})
        Set n = n + 1
        Do out.%Push({"id": ("L" _ n), "version": 1, "title": ("conjunction " _ k), "priority": 100, "scope": (scope), "pattern": (pattern), "why": "unit test", "team": "", "instructions": "ring", "prose": ""})
    }
    Quit out
}

Method TestASiteEntryOnlyEverSendsACaseToAPerson()
{
    Set matcher = "Shutter.Catalogue.Matcher", digest = "Shutter.Util.Digest"
    Do $$$AssertTrue(##class(Shutter.Catalogue.Entry).Count() > 0, "the catalogue is installed")
    Set samples = ..Samples(), entries = ..Entries()
    Do $$$AssertTrue(samples.%Size() > 150, "the samples: " _ samples.%Size())
    Do $$$AssertTrue(entries.%Size() > 100, "the entries: " _ entries.%Size())
    Set checked = 0, matched = 0, same = 0, death = 0, wrong = ""
    Set si = samples.%GetIterator()
    While si.%GetNext(.sn, .sample) {
        Set base = $CLASSMETHOD(matcher, "MatchWith", sample.conditions, "", sample.scope, [])
        Set baseText = $CLASSMETHOD(digest, "Canonical", base)
        Set led = (base.entry = "E19")
        Set seen(base.decision) = 1
        // Each sample meets a third of the entries, a different third from its neighbours', so every sample and every
        // entry is checked many times and the whole stays a few seconds' work.
        Set ei = entries.%GetIterator()
        While ei.%GetNext(.en, .e) {
            Continue:((en + sn) # 3)
            Set r = $CLASSMETHOD(matcher, "MatchWith", sample.conditions, "", sample.scope, [(e)])
            Set own = $CLASSMETHOD(matcher, "ScopeHolds", e.scope, sample.scope) && $CLASSMETHOD(matcher, "SiteHolds", e.pattern, sample.conditions)
            Set checked = checked + 1
            If own && 'led {
                Set matched = matched + 1
                Set m = $SELECT(r.matches.%Size() = 1: r.matches.%Get(0), 1: {})
                Set ok = (r.matches.%Size() = 1) && (m.id = e.id) && (m.origin = "site") && (m.decides = "person") && (m.preferred.outcome = "escalate") && (m.alternatives.%Size() = 0) && (r.decision = "person") && (r.entry = e.id) && (r.outcome = "escalate") && (r."outcome_ref" = "preferred")
                // What it displaced is exactly what the shipped catalogue matched.
                Set ok = ok && (r.overridden.%Size() = base.matches.%Size())
            } Else {
                If own Set death = death + 1
                Set same = same + 1
                Set ok = ($CLASSMETHOD(digest, "Canonical", r) = baseText)
            }
            If 'ok && ($LENGTH(wrong) < 600) Set wrong = wrong _ "sample " _ sn _ " with " _ e.title _ ": " _ $EXTRACT(r.%ToJSON(), 1, 200) _ "; "
        }
    }
    Do $$$AssertEquals(wrong, "", "the property holds on every sample and entry")
    Do $$$AssertTrue(matched > 500, "the entry matched in " _ matched _ " of " _ checked _ " checks")
    Do $$$AssertTrue(same > 500, "and did not in " _ same)
    Do $$$AssertTrue(death > 0, "E19 answered before a site entry that matched in " _ death)
    For decision = "policy", "board", "person", "new_pattern" { Do $$$AssertTrue($DATA(seen(decision)), "the samples reach a shipped decision of " _ decision) }
}

/// Two site entries that match: the lower priority number leads, then the older id; the other is shown beside it.
Method TestThePriorityLeads()
{
    Set matcher = "Shutter.Catalogue.Matcher"
    Set c = ##class(Shutter.Test.Matcher).Conditions({})
    Set a = {"id": "L1", "version": 1, "title": "first made", "priority": 50, "scope": {}, "pattern": {"event": ["transfer"]}, "why": "a", "team": "", "instructions": "do a", "prose": ""}
    Set b = {"id": "L2", "version": 3, "title": "second made", "priority": 10, "scope": {}, "pattern": {"event": ["transfer"]}, "why": "b", "team": "pas", "instructions": "do b", "prose": ""}
    Set r = $CLASSMETHOD(matcher, "MatchWith", c, "", {}, ##class(Shutter.Catalogue.SiteEntry).Ordered([(a), (b)]))
    Do $$$AssertEquals(r.entry, "L2", "the lower priority number leads")
    Do $$$AssertEquals(r.matches.%Get(0).instructions, "do b", "with its instructions")
    Do $$$AssertEquals(r."site_also".%Get(0).id, "L1", "the other is shown beside it")
    Do $$$AssertEquals(r."site_also".%Get(0).instructions, "do a", "with its instructions too")
    Set b.priority = 50
    Set r = $CLASSMETHOD(matcher, "MatchWith", c, "", {}, ##class(Shutter.Catalogue.SiteEntry).Ordered([(b), (a)]))
    Do $$$AssertEquals(r.entry, "L1", "at the same priority the older id leads")
    Set ten = {"id": "L10", "version": 1, "title": "tenth", "priority": 50, "scope": {}, "pattern": {"event": ["transfer"]}, "why": "c", "team": "", "instructions": "", "prose": ""}
    Set r = $CLASSMETHOD(matcher, "MatchWith", c, "", {}, ##class(Shutter.Catalogue.SiteEntry).Ordered([(ten), (b)]))
    Do $$$AssertEquals(r.entry, "L2", "by its number, not its spelling: L2 before L10")
}

/// The scope: every fact listed must hold, a fact the case does not have never holds, and the reason word is read
/// whatever its case.
Method TestTheScope()
{
    Set matcher = "Shutter.Catalogue.Matcher"
    Set facts = {"receiver": "Downstream Out", "source_system": "PAS", "ward": "WARD-ISO", "reason_code": "bed_occupied"}
    Do $$$AssertTrue($CLASSMETHOD(matcher, "ScopeHolds", {}, facts), "no scope holds everywhere")
    Do $$$AssertTrue($CLASSMETHOD(matcher, "ScopeHolds", "", facts), "as does none at all")
    Do $$$AssertTrue($CLASSMETHOD(matcher, "ScopeHolds", {"ward": ["WARD-A", "WARD-ISO"], "receiver": ["Downstream Out"]}, facts), "every fact listed holds")
    Do $$$AssertNotTrue($CLASSMETHOD(matcher, "ScopeHolds", {"ward": ["WARD-ISO"], "receiver": ["Records Out"]}, facts), "one that does not, and the scope does not")
    Do $$$AssertNotTrue($CLASSMETHOD(matcher, "ScopeHolds", {"ward": ["ward-iso"]}, facts), "a ward is read exactly")
    Do $$$AssertTrue($CLASSMETHOD(matcher, "ScopeHolds", {"reason_code": ["BED_OCCUPIED"]}, facts), "the reason word whatever its case")
    Do $$$AssertNotTrue($CLASSMETHOD(matcher, "ScopeHolds", {"ward": ["WARD-ISO"]}, {"receiver": "Downstream Out"}), "a fact the case does not have never holds")
    Do $$$AssertNotTrue($CLASSMETHOD(matcher, "ScopeHolds", {"ward": ["WARD-ISO"]}, ""), "nor with no facts at all")
    // The facts of a case, as the matcher computes them.
    Set case = ##class(Shutter.Test.SiteKit).Case({"ward": "WARD-ISO"}, .snap)
    Set scope = $CLASSMETHOD(matcher, "Scope", case, snap.SummaryObject())
    Do $$$AssertEquals(scope.receiver, case.Receiver, "the receiver")
    Do $$$AssertEquals(scope."source_system", "PAS", "the sending application")
    Do $$$AssertEquals(scope.ward, "WARD-ISO", "the ward the message names")
    Do $$$AssertEquals(scope."reason_code", "ward_unavailable", "the receiver's reason word")
    Do $$$AssertNotTrue(snap.SummaryObject().catalogue.%IsDefined("scope"), "which the result does not carry while no site entry matched")
}

/// A site entry's pattern, read as the matcher reads it: every condition listed must have one of its values, a single
/// value is one value, a condition the case does not carry at all is passed over (R14: the entry then matches more), and
/// a pattern that is not there holds nowhere.
Method TestThePattern()
{
    Set matcher = "Shutter.Catalogue.Matcher"
    Set conditions = {"event": "transfer", "delivery": "failed", "receipt": "absent"}
    Do $$$AssertTrue($CLASSMETHOD(matcher, "SiteHolds", {"delivery": ["failed", "rejected"]}, conditions), "a value in the list holds")
    Do $$$AssertNotTrue($CLASSMETHOD(matcher, "SiteHolds", {"delivery": ["rejected", "uncertain"]}, conditions), "none in the list, and it does not")
    Do $$$AssertTrue($CLASSMETHOD(matcher, "SiteHolds", {"event": "transfer"}, conditions), "a single value that is the case's")
    Do $$$AssertNotTrue($CLASSMETHOD(matcher, "SiteHolds", {"event": "admit"}, conditions), "a single value that is not")
    Do $$$AssertTrue($CLASSMETHOD(matcher, "SiteHolds", {"event": "transfer", "delivery": ["failed"]}, conditions), "every condition holds")
    Do $$$AssertNotTrue($CLASSMETHOD(matcher, "SiteHolds", {"event": "transfer", "receipt": ["present"]}, conditions), "one does not, and the pattern does not")
    Do $$$AssertTrue($CLASSMETHOD(matcher, "SiteHolds", {"event": "transfer", "later_applied": ["none"]}, conditions), "a condition the case does not carry is passed over")
    Do $$$AssertNotTrue($CLASSMETHOD(matcher, "SiteHolds", "", conditions), "no pattern holds nowhere")
    Do $$$AssertTrue($CLASSMETHOD(matcher, "SiteHolds", {}, conditions), "an empty pattern holds (the rules refuse one: R3)")
}

/// A stored row cannot decide. Rows that claim to decide by policy, to resend, to offer alternatives or to be another
/// kind are written straight into the tables, past every rule: the matcher still answers person, escalate, no
/// alternatives for each.
Method TestStoredRowsThatClaimToDecide()
{
    Set kit = "Shutter.Test.SiteKit"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    Set v = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, 1)
    Set content = v.Content()
    Set content.decides = "policy", content.kind = "permit", content.outcome = "resend"
    Set content.preferred = {"outcome": "resend", "why": "it is safe"}
    Set content.alternatives = [{"outcome": "none", "why": "close it", "when": "always"}]
    Set content.origin = "shipped", content.checks = []
    Set v.Json = content.%ToJSON()
    Do $$$AssertStatusOK(v.%Save(), "the active version's row is overwritten with a row that claims to resend by policy")
    // The overwritten row alone, leading on its own case.
    Set cat = $CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue
    Do $$$AssertEquals(cat.entry, id, "the overwritten entry leads on its case")
    Do $$$AssertEquals(cat.decision, "person", "the overwritten entry: a person decides")
    Do $$$AssertEquals(cat.outcome, "escalate", "the overwritten entry: escalate")
    Do $$$AssertEquals(cat.matches.%Size(), 1, "the overwritten entry: one match")
    Do $$$AssertEquals(cat.matches.%Get(0).decides, "person", "the overwritten entry: the match says person")
    Do $$$AssertEquals(cat.matches.%Get(0).preferred.outcome, "escalate", "the overwritten entry: and escalate")
    Do $$$AssertEquals(cat.matches.%Get(0).alternatives.%Size(), 0, "the overwritten entry: with no alternatives")
    // And a row nobody approved, inserted beside it.
    Set e = ##class(Shutter.Catalogue.SiteEntry).%New()
    Set e.EntryId = "L77", e.State = "active", e.ActiveVersion = 1, e.Priority = 1
    Do $$$AssertStatusOK(e.%Save(), "an entry's row inserted as active")
    Set v2 = ##class(Shutter.Catalogue.SiteEntryVersion).%New()
    Set v2.EntryId = "L77", v2.Version = 1, v2.Status = "approved"
    Set v2.Json = {"id": "L77", "kind": "resend", "title": "inserted", "priority": 1, "pattern": {"event": ["transfer"]}, "decides": "policy", "preferred": {"outcome": "resend_unconditional", "why": "x"}, "alternatives": [{"outcome": "resend", "when": "always"}], "why": "inserted"}.%ToJSON()
    Do $$$AssertStatusOK(v2.%Save(), "with a version that claims an unconditional resend")
    For case = match, near {
        Set cat = $CLASSMETHOD(kit, "Snapshot", case).SummaryObject().catalogue
        Do $$$AssertEquals(cat.decision, "person", case.Ward _ ": a person decides")
        Do $$$AssertEquals(cat.outcome, "escalate", case.Ward _ ": escalate")
        Do $$$AssertEquals(cat.matches.%Size(), 1, case.Ward _ ": one match")
        Set m = cat.matches.%Get(0)
        Do $$$AssertEquals(m.id, "L77", case.Ward _ ": the inserted row leads by its priority")
        Do $$$AssertEquals(m.decides, "person", case.Ward _ ": the match says person")
        Do $$$AssertEquals(m.preferred.outcome, "escalate", case.Ward _ ": and escalate")
        Do $$$AssertEquals(m.alternatives.%Size(), 0, case.Ward _ ": with no alternatives")
        Do $$$AssertEquals(##class(Shutter.Operation.Gate).EntriesThatStop(cat), "L77", case.Ward _ ": the gate reads it as an entry that stops")
    }
    Set also = $CLASSMETHOD(kit, "Snapshot", match).SummaryObject().catalogue."site_also"
    Do $$$AssertEquals(also.%Get(0).id, id, "the overwritten entry matches the isolation ward's case beside it")
    Do $$$AssertNotTrue(also.%Get(0).%IsDefined("decides") || also.%Get(0).%IsDefined("preferred"), "and carries nothing that decides")
    Do $$$AssertStatusOK($CLASSMETHOD(kit, "Reset"), "removed")
}

/// The gate, unchanged, on a case a site entry matched: the escalate plan that names the entry passes its catalogue
/// check, and every shape of write is blocked: naming the entry, naming nothing, naming another entry, naming a site
/// entry whose pattern does not hold, naming one that does not exist.
Method TestTheGateBlocksEveryWrite()
{
    Set kit = "Shutter.Test.SiteKit"
    Set id = $CLASSMETHOD(kit, "ActiveEntry", .match, .near, .problem)
    Do $$$AssertEquals(problem, "", "an active entry")
    // A second site entry, a draft whose pattern does not hold on the case.
    Set other = $CLASSMETHOD(kit, "Body")
    Set other.pattern = {"event": "discharge"}
    Do $$$AssertEquals(##class(Shutter.Catalogue.SiteEntry).Create(other, "ut-author", "api", .draft, .problems, .warnings), "", "a second entry, a draft")
    Set rows = [
        {"name": "the escalate plan naming the entry", "plan": {"disposition": "escalate", "action": {"type": "none"}, "catalogue_entry": (id), "outcome": "preferred"}, "by": ("policy:" _ id), "expect": "ENTRY_MATCHED", "result": "pass", "absent": "OUTCOME_MISMATCH"},
        {"name": "a write naming the entry", "plan": {"catalogue_entry": (id), "outcome": "preferred"}, "by": "run:1", "expect": "OUTCOME_MISMATCH", "result": "block"},
        {"name": "a write naming nothing", "plan": {}, "by": "run:1", "expect": "ENTRY_NOT_NAMED_WRITE", "result": "block"},
        {"name": "the rules path's write naming nothing", "plan": {}, "by": "rules", "expect": "ENTRY_NOT_NAMED_WRITE", "result": "block"},
        {"name": "a write naming the shipped entry it displaced", "plan": {"catalogue_entry": "E2", "outcome": "preferred"}, "by": "run:1", "expect": "PATTERN_NOT_MATCHED", "result": "block"},
        {"name": "a write naming a site entry whose pattern does not hold", "plan": {"catalogue_entry": (draft.EntryId), "outcome": "preferred"}, "by": "run:1", "expect": "PATTERN_NOT_MATCHED", "result": "block"},
        {"name": "a write naming a site entry that does not exist", "plan": {"catalogue_entry": "L999", "outcome": "preferred"}, "by": "run:1", "expect": "ENTRY_UNKNOWN", "result": "block"},
        {"name": "a closure naming the entry", "plan": {"disposition": "superseded", "action": {"type": "none"}, "catalogue_entry": (id), "outcome": "preferred"}, "by": "run:1", "expect": "OUTCOME_MISMATCH", "result": "block"}
    ]
    Set it = rows.%GetIterator()
    While it.%GetNext(, .row) {
        Set case = $CLASSMETHOD(kit, "Case", {"ward": "WARD-ISO", "state": "investigating", "mode": "board"}, .snap)
        Do $$$AssertEquals(snap.SummaryObject().catalogue.entry, id, row.name _ ": the case is the site entry's")
        Set plan = {"disposition": "resend", "action": {"type": "resend", "operation_key": (case.OperationKey), "expected_version": 3, "payload_digest": "sha256:ut"}, "summary": "unit test"}
        Set pi = row.plan.%GetIterator()
        While pi.%GetNext(.key, .value) { Do plan.%Set(key, value) }
        Do $$$AssertStatusOK(##class(Shutter.Store.Plan).Create(case, snap, plan, row.by, .p), row.name _ ": the plan")
        Set req = ##class(Shutter.Msg.GateRequest).%New()
        Set req.CaseId = case.CaseId, req.PlanId = p.%Id(), req.Stage = "proposal", req.Receiver = case.Receiver, req.ChainKind = "single"
        Set gate = ##class(Shutter.Operation.Gate).%New("Shutter Gate (unit test)")
        Do $$$AssertStatusOK(gate.OnGateRequest(req, .resp), row.name _ ": the gate ran")
        Set found = "", absent = 1, ci = ##class(%DynamicArray).%FromJSON(resp.ChecksJSON).%GetIterator()
        While ci.%GetNext(, .c) {
            Continue:(c.check '= "catalogue")
            If c."reason_code" = row.expect Set found = c.result
            If row.%IsDefined("absent") && (c."reason_code" = row.absent) Set absent = 0
        }
        Do $$$AssertEquals(found, row.result, row.name _ ": catalogue " _ row.expect _ " (" _ resp.Summary _ ")")
        Do $$$AssertTrue(absent, row.name _ ": and nothing else of the catalogue's")
        If row.result = "block" Do $$$AssertEquals(resp.Outcome, "block", row.name _ ": the gate blocks")
    }
    Do $$$AssertStatusOK($CLASSMETHOD(kit, "Reset"), "removed")
}

}
