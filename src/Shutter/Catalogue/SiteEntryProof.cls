/// A proof of a site's own entry (CONTRACTS 6.8): stored evidence replayed through the real matcher, with nothing sent
/// and nothing stored on any case. P1: on each fixture expected to match, the entry's own scope and pattern hold, and
/// with the entry laid over the active ones it leads alone (person, escalate). P2: on each fixture expected to be left
/// alone, its own scope and pattern do not hold. P4: the last stored cases matched with and without it, counted by what
/// they would have done instead. P5: what the proof is bound to. Every run is kept, with words, codes and case ids only.
Class Shutter.Catalogue.SiteEntryProof Extends (%Persistent, %JSON.Adaptor)
{

Property EntryId As %String(%JSONFIELDNAME = "id", MAXLEN = 16) [ Required ];

Index EntryIdx On EntryId;

Property Version As %Integer(%JSONFIELDNAME = "version");

/// The digest of the content proved.
Property Digest As %String(%JSONFIELDNAME = "digest", MAXLEN = 80);

/// activate, retire or resume.
Property Action As %String(%JSONFIELDNAME = "action", MAXLEN = 16);

Property Passed As %Boolean(%JSONFIELDNAME = "passed") [ InitialExpression = 0 ];

/// The fixtures' rows, the counts and the impact.
Property ResultJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// What the proof is bound to (P5).
Property ContextJSON As %String(%JSONINCLUDE = "none", MAXLEN = "");

Property At As %String(%JSONFIELDNAME = "at", MAXLEN = 30);

Property By As %String(%JSONFIELDNAME = "by", MAXLEN = 160);

/// api (a person ran it) or approval (run again as the approval commits).
Property Origin As %String(%JSONFIELDNAME = "origin", MAXLEN = 16);

/// How many stored cases the impact reads at most, and for how long.
Parameter IMPACTCASES = 200;

Parameter IMPACTSECONDS = 10;

Method ToObject() As %DynamicObject
{
    Set o = ##class(Shutter.Util.Json).Project($THIS)
    Set o.result = ##class(Shutter.Util.Json).Parse($SELECT(..ResultJSON = "": "{}", 1: ..ResultJSON), .sc)
    Set o.context = ##class(Shutter.Util.Json).Parse($SELECT(..ContextJSON = "": "{}", 1: ..ContextJSON), .sc)
    Quit o
}

/// An entry's proofs, newest first.
ClassMethod For(entryId As %String, limit As %Integer = 20) As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ (+limit) _ " ID FROM Shutter_Catalogue.SiteEntryProof WHERE EntryId = ? ORDER BY ID DESC", entryId)
    While rs.%Next() {
        Set p = ..%OpenId(rs.%Get("ID"))
        If $ISOBJECT(p) Do out.%Push(p.ToObject())
    }
    Quit out
}

/// The newest proof of a digest and an action that a person ran, or "".
ClassMethod Latest(entryId As %String, digest As %String, action As %String) As Shutter.Catalogue.SiteEntryProof
{
    Set id = ""
    &sql(SELECT TOP 1 ID INTO :id FROM Shutter_Catalogue.SiteEntryProof WHERE EntryId = :entryId AND Digest = :digest AND Action = :action AND Origin = 'api' ORDER BY ID DESC)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// A fixture frozen from a stored, closed case: beside the case id and what is expected, the digest of the snapshot it
/// was read from, the chain kind the case had, and a copy of the conditions and the scope facts (words, no patient data).
/// "" with <var>why</var> when the case can't serve.
ClassMethod Freeze(caseId As %String, expect As %String, Output why As %String) As %DynamicObject
{
    Set why = ""
    Set case = ##class(Shutter.Store.Case).ByCaseId(caseId)
    If '$ISOBJECT(case) Set why = "there is no case " _ $EXTRACT(caseId, 1, 40) Quit ""
    If 'case.IsClosed() Set why = "case " _ caseId _ " is still being worked on (" _ case.State _ "): a fixture is a closed case, whose evidence no longer changes" Quit ""
    Set snap = case.CurrentSnapshot
    If '$ISOBJECT(snap) Set why = "case " _ caseId _ " has no evidence" Quit ""
    Set summary = snap.SummaryObject()
    If '$ISOBJECT(summary) Set why = "the evidence of case " _ caseId _ " cannot be read" Quit ""
    Set chain = ##class(Shutter.Store.ChainItem).KindFor(case)
    Set f = {}
    Set f.case = caseId, f.expect = expect, f."snapshot_digest" = snap.Digest, f.chain = chain
    Try {
        Set f.conditions = ##class(Shutter.Catalogue.Matcher).Conditions(case, summary, chain)
        Set f.scope = ##class(Shutter.Catalogue.Matcher).Scope(case, summary)
    } Catch ex {
        Set why = "the conditions of case " _ caseId _ " could not be computed: " _ ex.DisplayString()
    }
    If why '= "" Quit ""
    Quit f
}

/// A fixture read again now: the conditions and the scope facts computed by this release's matcher from the stored
/// snapshot the fixture was frozen from, with the chain kind it had (source "evidence"). When the case or that snapshot
/// is no longer stored (the retention task, a demo's reset) the frozen copy answers (source "frozen"): it then proves the
/// pattern's logic, not the reading of evidence. When the case and its snapshot are stored but this release cannot read
/// them (an exception computing the conditions, say), the source is "error" with the reason in <var>why</var>: that is
/// a failure to report, never taken for a case that is gone. Returns {conditions, scope, facts}.
ClassMethod Replay(fixture As %DynamicObject, Output source As %String, Output why As %String) As %DynamicObject
{
    Set json = "Shutter.Util.Json", source = "frozen", why = ""
    Set out = {}
    Set out.conditions = fixture.%Get("conditions"), out.scope = fixture.%Get("scope"), out.facts = {"other_source": ""}
    If '$ISOBJECT(out.conditions) Set out.conditions = {}
    If '$ISOBJECT(out.scope) Set out.scope = {}
    Set caseId = $CLASSMETHOD(json, "Str", fixture, "case"), digest = $CLASSMETHOD(json, "Str", fixture, "snapshot_digest")
    If (caseId = "") || (digest = "") Quit out
    // Only a case that is not there is a purge: a lookup that failed, or a row that is there and cannot be opened, is a
    // failure to report.
    Set cid = ""
    &sql(SELECT ID INTO :cid FROM Shutter_Store."Case" WHERE CaseId = :caseId)
    If SQLCODE < 0 Set source = "error", why = "it could not be looked up (SQLCODE " _ SQLCODE _ ")" Quit out
    If (SQLCODE '= 0) || (cid = "") Quit out
    Set case = ##class(Shutter.Store.Case).%OpenId(cid)
    If '$ISOBJECT(case) Set source = "error", why = "it cannot be opened" Quit out
    Set sid = ""
    &sql(SELECT TOP 1 ID INTO :sid FROM Shutter_Store.Snapshot WHERE "Case" = :cid AND Digest = :digest ORDER BY ID DESC)
    // Only a snapshot that is not there is a purge: a lookup that failed is a failure to report.
    If SQLCODE < 0 Set source = "error", why = "its stored evidence could not be looked up (SQLCODE " _ SQLCODE _ ")" Quit out
    If (SQLCODE '= 0) || (sid = "") Quit out
    Try {
        Set snap = ##class(Shutter.Store.Snapshot).%OpenId(sid)
        Set summary = $SELECT($ISOBJECT(snap): snap.SummaryObject(), 1: "")
        If '$ISOBJECT(summary) || 'summary.%IsA("%Library.DynamicObject") $$$ThrowStatus($$$ERROR($$$GeneralError, "snapshot " _ sid _ " does not read as evidence"))
        Set chain = $CLASSMETHOD(json, "Str", fixture, "chain", "single")
        Set live = {}
        Set live.conditions = ##class(Shutter.Catalogue.Matcher).Conditions(case, summary, chain)
        Set live.scope = ##class(Shutter.Catalogue.Matcher).Scope(case, summary)
        Set live.facts = ##class(Shutter.Catalogue.Matcher).Facts(summary, case)
        Set out = live, source = "evidence"
    } Catch ex {
        Set source = "error", why = "its stored evidence cannot be read under this release: " _ $EXTRACT(ex.DisplayString(), 1, 300)
    }
    Quit out
}

/// What a proof is bound to (P5): the action, the digest, the shipped catalogue's version, the other active site
/// entries, the gate's policy version, the site profile's version and the release.
ClassMethod Context(entryId As %String, action As %String, digest As %String) As %DynamicObject
{
    Set c = {}
    Set c.action = action, c.digest = digest
    Set c.shipped = ##class(Shutter.Catalogue.Entry).ShippedVersion()
    Set c.site = ##class(Shutter.Catalogue.SiteEntry).ActiveIds(entryId)
    Set c."gate_policy" = $PARAMETER("Shutter.Operation.Gate", "POLICYVERSION")
    Set c."profile_version" = ##class(Shutter.Util.Json).Str(##class(Shutter.Store.SiteProfile).Current(), "version", 0)
    Set c.release = $PARAMETER("Shutter.Setup", "VERSION")
    Quit c
}

/// Whether this proof's context is still the one in force: a proof made under another catalogue, profile, gate policy or
/// release is stale, and nobody proposes or approves on it.
Method Current() As %Boolean
{
    Set mine = ##class(Shutter.Util.Json).Parse($SELECT(..ContextJSON = "": "{}", 1: ..ContextJSON), .sc)
    If '$ISOBJECT(mine) Quit 0
    Quit ##class(Shutter.Util.Digest).Canonical(mine) = ##class(Shutter.Util.Digest).Canonical(..Context(..EntryId, ..Action, ..Digest))
}

/// Run a proof of <var>content</var> (an entry's version) for an action and keep it. activate and resume need every
/// fixture to answer as expected, with at least one match and at least one near miss (no_match); a retirement's proof is
/// its impact read the other way (the cases the entry catches, and what each would do without it) and passes when it
/// could be computed. <var>impact</var> 0 leaves P4 out (the run at an approval, which compares P1 and P2 alone).
/// <var>store</var> 0 keeps nothing (the preview): the result is the same, with no proofId.
ClassMethod Run(entryId As %String, version As %Integer, content As %DynamicObject, action As %String, by As %String, origin As %String = "api", impact As %Boolean = 1, Output proof As Shutter.Catalogue.SiteEntryProof, store As %Boolean = 1) As %DynamicObject
{
    Set json = "Shutter.Util.Json", matcher = "Shutter.Catalogue.Matcher"
    Set proof = "", result = {}, problems = []
    Set digest = ##class(Shutter.Catalogue.SiteEntryVersion).DigestOf(content)
    Set result.action = action, result.version = +version, result.digest = digest
    // What the proof is bound to, read before anything it evaluates and again at the end (P5): a catalogue or a profile
    // that changed while it ran is a problem, so the context kept is always the one it was evaluated under.
    Set started = ##class(Shutter.Util.Digest).Canonical(..Context(entryId, action, digest))
    Set others = ##class(Shutter.Catalogue.SiteEntry).ActiveList(.problem, entryId)
    If problem '= "" Do problems.%Push("The active site entries cannot be read: " _ problem) Set others = []
    Set mine = ##class(Shutter.Catalogue.SiteEntry).MatchItem(entryId, version, content, content.%Get("pattern"))
    Set with = ##class(Shutter.Catalogue.SiteEntry).Ordered(others, mine)
    Set rows = [], matchCount = 0, nearCount = 0, allOk = 1
    Set fixtures = content.%Get("fixtures")
    If '$ISOBJECT(fixtures) Set fixtures = []
    Set fi = fixtures.%GetIterator()
    While fi.%GetNext(, .f) {
        Set expect = $CLASSMETHOD(json, "Str", f, "expect")
        Set now = ..Replay(f, .source, .why)
        Set own = $CLASSMETHOD(matcher, "ScopeHolds", content.%Get("scope"), now.scope) && $CLASSMETHOD(matcher, "SiteHolds", content.%Get("pattern"), now.conditions)
        Set row = {}
        Set row.case = $CLASSMETHOD(json, "Str", f, "case"), row.expect = expect, row.source = source
        Do row.%Set("holds", own, "boolean")
        If source = "error" {
            // A stored case that cannot be read is no proof either way.
            Set row.why = why, row.text = "Case " _ row.case _ " is stored, but " _ why
            Do row.%Set("ok", 0, "boolean")
            Set allOk = 0
            Do problems.%Push("Case " _ row.case _ " is stored, but " _ why)
            If expect = "match" { Set matchCount = matchCount + 1 } Else { Set nearCount = nearCount + 1 }
            Do rows.%Push(row)
            Continue
        }
        If expect = "match" {
            Set matchCount = matchCount + 1
            Set r = $CLASSMETHOD(matcher, "MatchWith", now.conditions, now.facts, now.scope, with)
            Set lead = $CLASSMETHOD(json, "Str", r, "entry")
            If (lead = "") && (r.%GetTypeOf("matches") = "array") && (r.matches.%Size() > 0) Set lead = "several entries"
            Set row.lead = lead
            Set ok = own && (lead = entryId) && (r.decision = "person") && ($CLASSMETHOD(json, "Str", r, "outcome") = "escalate")
            Set row.text = $SELECT(ok: "The entry matches and leads alone: a person decides", 'own: "The entry's own scope and pattern do not hold on this case", 1: "The entry matches, but " _ $SELECT(lead = "": "nothing", 1: lead) _ " leads on this case")
        } Else {
            Set nearCount = nearCount + 1
            Set ok = 'own
            Set row.text = $SELECT(ok: "The entry leaves this case alone", 1: "The entry's own scope and pattern hold on this case, which it should leave alone")
        }
        Do row.%Set("ok", ok, "boolean")
        If 'ok Set allOk = 0
        Do rows.%Push(row)
    }
    Set result.fixtures = rows
    Set result.counts = {"match": (matchCount), "no_match": (nearCount)}
    If action '= "retire" {
        If matchCount = 0 Do problems.%Push("No fixture expects a match: the proof needs at least one stored case the entry must catch")
        If nearCount = 0 Do problems.%Push("No fixture expects no match: the proof needs at least one near miss the entry must leave alone")
        If 'allOk Do problems.%Push("A fixture did not answer as expected")
    }
    If impact {
        Try {
            Set result.impact = ..Impact(entryId, others, with)
            // A retirement stands on its impact alone: one no stored case could be read for is no proof.
            Set read = result.impact.scanned - result.impact.unread
            If (action = "retire") && (result.impact.scanned > 0) && (read = 0) Do problems.%Push("None of the " _ result.impact.scanned _ " stored cases could be read under this release, so what retiring the entry changes is not known")
            Set warnings = []
            If result.impact.unread > 0 Do warnings.%Push(result.impact.unread _ " of the " _ result.impact.scanned _ " stored cases could not be read, so they are not counted")
            If result.impact.capped Do warnings.%Push("The scan stopped at its time limit, after " _ result.impact.scanned _ " cases")
            If warnings.%Size() > 0 Set result.warnings = warnings
        } Catch ex {
            Do problems.%Push("The impact could not be computed: " _ ex.DisplayString())
        }
    }
    Set context = ..Context(entryId, action, digest)
    If ##class(Shutter.Util.Digest).Canonical(context) '= started Do problems.%Push("The catalogue, the site profile, the gate's policy or the release changed while the proof ran: run it again")
    Set result.problems = problems
    Set passed = (problems.%Size() = 0)
    Do result.%Set("passed", passed, "boolean")
    Set result.context = context
    If 'store Quit result
    Set proof = ..%New()
    Set proof.EntryId = entryId, proof.Version = +version, proof.Digest = digest, proof.Action = action, proof.Passed = passed
    Set proof.ResultJSON = result.%ToJSON(), proof.ContextJSON = context.%ToJSON()
    Set proof.At = ##class(Shutter.Util.Time).NowUTC(), proof.By = $EXTRACT(by, 1, 160), proof.Origin = origin
    Set sc = proof.%Save()
    If $$$ISERR(sc) {
        Do problems.%Push("The proof could not be stored: " _ $SYSTEM.Status.GetErrorText(sc))
        Do result.%Set("passed", 0, "boolean")
        Set proof = ""
    } Else {
        Set result.proofId = proof.%Id()
    }
    Quit result
}

/// P4: the last stored cases matched now with the entry and without it, so only the entry's effect shows. caught counts
/// the cases the entry would lead; groups says what each would have done without it: automatic_resend, approved_resend,
/// closure, board, person (a shipped entry already asks for one), new_pattern, other_site_entry; cases lists them by id.
ClassMethod Impact(entryId As %String, without As %DynamicArray, with As %DynamicArray) As %DynamicObject
{
    Set json = "Shutter.Util.Json", matcher = "Shutter.Catalogue.Matcher"
    Set out = {}, groups = {}, cases = {}, scanned = 0, caught = 0, unread = 0, capped = 0
    Set deadline = $ZHOROLOG + ..#IMPACTSECONDS
    // A query that fails, or stops at a row it cannot read, is no impact: it throws, and the proof says so (Run).
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP " _ ..#IMPACTCASES _ " ID FROM Shutter_Store.""Case"" WHERE CurrentSnapshot IS NOT NULL ORDER BY ID DESC")
    If rs.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$GeneralError, "the stored cases cannot be listed (SQLCODE " _ rs.%SQLCODE _ ")"))
    Set rsc = $$$OK
    While rs.%Next(.rsc) {
        If $ZHOROLOG > deadline Set capped = 1 Quit
        Set scanned = scanned + 1
        // A case that cannot be opened, or whose evidence cannot, is counted as unread, never left out.
        Set case = ##class(Shutter.Store.Case).%OpenId(rs.%Get("ID"))
        If '$ISOBJECT(case) || '$ISOBJECT(case.CurrentSnapshot) Set unread = unread + 1 Continue
        Try {
            Set summary = case.CurrentSnapshot.SummaryObject()
            Set chain = ##class(Shutter.Store.ChainItem).KindFor(case)
            Set conditions = $CLASSMETHOD(matcher, "Conditions", case, summary, chain)
            Set facts = $CLASSMETHOD(matcher, "Facts", summary, case), scope = $CLASSMETHOD(matcher, "Scope", case, summary)
            Set a = $CLASSMETHOD(matcher, "MatchWith", conditions, facts, scope, with)
            If $CLASSMETHOD(json, "Str", a, "entry") = entryId {
                Set b = $CLASSMETHOD(matcher, "MatchWith", conditions, facts, scope, without)
                Set group = ..GroupOf(b, case, chain)
                Set caught = caught + 1
                Do groups.%Set(group, +groups.%Get(group) + 1, "number")
                If cases.%GetTypeOf(group) '= "array" Do cases.%Set(group, [])
                Do cases.%Get(group).%Push(case.CaseId)
            }
        } Catch ex {
            Set unread = unread + 1
        }
    }
    If $$$ISERR(rsc) || (rs.%SQLCODE < 0) $$$ThrowStatus($SELECT($$$ISERR(rsc): rsc, 1: $$$ERROR($$$GeneralError, "the stored cases cannot be read (SQLCODE " _ rs.%SQLCODE _ ")")))
    Do out.%Set("scanned", scanned, "number"), out.%Set("caught", caught, "number"), out.%Set("unread", unread, "number")
    Do out.%Set("capped", capped, "boolean")
    Set out.groups = groups, out.cases = cases
    Quit out
}

/// The preview (POST /site-entries/preview): a body checked as a draft's is (R1 to R5 and R15), its fixtures frozen from
/// the stored cases they name, and P1, P2 and P4 run on them, with nothing stored anywhere: no entry, no version, no
/// proof, no event, nothing on any case. A body may name {fromCase} to start from a closed case, as a new draft can, and
/// {id} to preview a change of an existing entry (it is then left out of the others, as its own proof leaves it); a new
/// entry is previewed under the id the next draft would take. {action} is activate (the default), retire or resume. The
/// answer is {valid, problems, warnings, sentence, overlap, content, proof}; proof is "" when the body has no pattern to
/// prove. It decides nothing: what would lead and what each case would do are the matcher's answers.
ClassMethod Preview(body As %DynamicObject, Output result As %DynamicObject) As %String
{
    Set json = "Shutter.Util.Json", result = ""
    If '$ISOBJECT(body) || 'body.%IsA("%Library.DynamicObject") Quit "bad_request"
    Set given = ##class(%DynamicObject).%FromJSON(body.%ToJSON())
    Set action = $CLASSMETHOD(json, "Str", given, "action", "activate")
    If '$LISTFIND($LISTBUILD("activate", "retire", "resume"), action) Quit "bad_request"
    For key = "action", "expectedVersion" { If given.%IsDefined(key) Do given.%Remove(key) }
    Set problems = [], problem = ""
    Set entryId = $CLASSMETHOD(json, "Str", given, "id")
    If entryId '= "" {
        If '$ISOBJECT(##class(Shutter.Catalogue.SiteEntry).ById(entryId)) Quit "not_found"
    } Else {
        Set entryId = "L" _ ($GET(^Shutter.Catalogue.Site("next")) + 1)
    }
    If given.%IsDefined("fromCase") {
        Set given = ##class(Shutter.Catalogue.SiteEntry).FromCase($CLASSMETHOD(json, "Str", given, "fromCase"), given, .problem)
        If given.%IsDefined("fromCase") Do given.%Remove("fromCase")
    }
    Do ##class(Shutter.Catalogue.SiteEntryVersion).Normalise(given, entryId, .content, .found, .warnings, 1)
    If problem '= "" Do problems.%Push({"rule": "R1", "field": "fromCase", "text": (problem)})
    Set it = found.%GetIterator()
    While it.%GetNext(, .p) { Do problems.%Push(p) }
    Set result = {}
    Do result.%Set("valid", problems.%Size() = 0, "boolean")
    Set result.problems = problems, result.warnings = warnings, result.id = entryId, result.action = action
    Set result.sentence = ##class(Shutter.Catalogue.SiteEntryVersion).Sentence(content)
    Set result.overlap = ##class(Shutter.Catalogue.SiteEntryVersion).Overlap(content.%Get("pattern"))
    Set result.content = content
    // A pattern the rules refused whole leaves nothing to prove; missing words (a title, a why) do not stop the proof.
    Set pattern = content.%Get("pattern")
    If '$ISOBJECT(pattern) || (pattern.%Size() = 0) {
        Do result.%Set("proof", "", "null")
        Quit ""
    }
    Set result.proof = ..Run(entryId, 0, content, action, "", "preview", 1, , 0)
    Quit ""
}

/// What a case would do on a match that no site entry leads, in one word.
ClassMethod GroupOf(match As %DynamicObject, case As Shutter.Store.Case, chain As %String) As %String [ Private ]
{
    Set json = "Shutter.Util.Json"
    Set decision = $CLASSMETHOD(json, "Str", match, "decision"), outcome = $CLASSMETHOD(json, "Str", match, "outcome")
    Set matches = match.%Get("matches")
    If $ISOBJECT(matches) && (matches.%Size() = 1) && ($CLASSMETHOD(json, "Str", matches.%Get(0), "origin") = "site") Quit "other_site_entry"
    If decision = "policy" {
        If $LISTFIND($LISTBUILD("resend", "resend_chain", "resend_latest", "resend_after_occupant"), outcome) {
            Set policy = ##class(Shutter.Store.SiteProfile).Policy(##class(Shutter.Store.SiteProfile).TierOf(case.Receiver), chain)
            Quit $SELECT(policy = "automatic": "automatic_resend", policy = "board": "board", 1: "approved_resend")
        }
        If (outcome = "none") || (outcome = "reconcile") Quit "closure"
        Quit "person"
    }
    Quit $CASE(decision, "board": "board", "person": "person", "new_pattern": "new_pattern", : "other")
}

Storage Default
{
<Data name="SiteEntryProofDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>EntryId</Value>
</Value>
<Value name="3">
<Value>Version</Value>
</Value>
<Value name="4">
<Value>Digest</Value>
</Value>
<Value name="5">
<Value>Action</Value>
</Value>
<Value name="6">
<Value>Passed</Value>
</Value>
<Value name="7">
<Value>ResultJSON</Value>
</Value>
<Value name="8">
<Value>ContextJSON</Value>
</Value>
<Value name="9">
<Value>At</Value>
</Value>
<Value name="10">
<Value>By</Value>
</Value>
<Value name="11">
<Value>Origin</Value>
</Value>
</Data>
<DataLocation>^Shutter.Cat5ADA.SiteEntryProofD</DataLocation>
<DefaultData>SiteEntryProofDefaultData</DefaultData>
<IdLocation>^Shutter.Cat5ADA.SiteEntryProofD</IdLocation>
<IndexLocation>^Shutter.Cat5ADA.SiteEntryProofI</IndexLocation>
<StreamLocation>^Shutter.Cat5ADA.SiteEntryProofS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
