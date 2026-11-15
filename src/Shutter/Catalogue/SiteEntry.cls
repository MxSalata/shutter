/// A site's own entry in the catalogue (CONTRACTS 6.8), id L<n>: a pattern, a scope and words, of one kind, stop. When
/// it matches a case, the case goes to a person with the site's words; it can never resend, close, reconcile or release,
/// because it has no field for who decides or the outcome: the matcher writes person and escalate for every site entry
/// it reads (Shutter.Catalogue.Matcher). This row is the entry's state; its content is in its versions
/// (Shutter.Catalogue.SiteEntryVersion), its proofs in Shutter.Catalogue.SiteEntryProof and what was done to it in
/// Shutter.Catalogue.SiteEntryEvent. The shipped seed never touches these tables.
///
/// The lifecycle: a draft (anyone with Shutter_Configure edits it and runs proofs), a proposal (frozen: the action, the
/// version and the digest are fixed and a passing proof of that digest is attached), active (a second person approved
/// it; the catalogue's version carries it), retired (history kept, the id never used again). One approver may suspend
/// an active entry at once; resuming and retiring are proposals like an activation.
Class Shutter.Catalogue.SiteEntry Extends (%Persistent, %JSON.Adaptor)
{

/// L1, L2, ...: given by Shutter, never reused, never an E id.
Property EntryId As %String(MAXLEN = 16) [ Required ];

Index EntryIdx On EntryId [ Unique ];

/// draft (never active yet), active, suspended or retired.
Property State As %String(MAXLEN = 16) [ InitialExpression = "draft" ];

Index StateIdx On State;

/// The version in force (or last in force, for a suspended or retired entry); 0 while there has been none.
Property ActiveVersion As %Integer [ InitialExpression = 0 ];

/// The open draft's version number, 0 when there is none. A draft beside an active version changes nothing until it
/// is approved.
Property DraftVersion As %Integer [ InitialExpression = 0 ];

/// The active version's priority: among site entries that match the same case, the lowest leads, then the older id.
Property Priority As %Integer [ InitialExpression = 100 ];

/// The open proposal, when ProposalAction is not empty: activate (the draft), retire or resume (the active version).
Property ProposalAction As %String(MAXLEN = 16);

Property ProposalVersion As %Integer;

Property ProposalDigest As %String(MAXLEN = 80);

Property ProposalBy As %String(MAXLEN = 160);

Property ProposalAt As %String(MAXLEN = 30);

Property ProposalProofId As %String(MAXLEN = 20);

/// Set by the recheck after an upgrade or a profile save (R14): the entry still applies, and a person should look.
Property NeedsReview As %Boolean [ InitialExpression = 0 ];

/// What the recheck found: {dropped: [{condition, why}], notes: [...], trigger, release, checked_at}.
Property ReviewJSON As %String(MAXLEN = "");

/// The pattern the matcher uses when the recheck dropped a predicate: the active version's without it, so the entry
/// matches more and never less. Empty when the version's own pattern stands. What a recheck dropped stays dropped until
/// a new version of the entry is approved.
Property EffectiveJSON As %String(MAXLEN = "");

/// The scope the matcher uses when the recheck dropped a scope fact (a fact the entry's own matching fixture reads
/// differently under this release): the active version's without it, so the entry matches more and never less. Empty
/// when the version's own scope stands; kept, as EffectiveJSON is, until a new version is approved.
Property EffectiveScopeJSON As %String(MAXLEN = "");

Property SuspendedBy As %String(MAXLEN = 160);

Property SuspendedAt As %String(MAXLEN = 30);

Property SuspendedReason As %String(MAXLEN = 1000);

/// Counts every change of the row, for expectedVersion on a change of the draft.
Property Revision As %Integer [ InitialExpression = 1 ];

Property CreatedBy As %String(MAXLEN = 160);

Property CreatedAt As %String(MAXLEN = 30);

Property UpdatedAt As %String(MAXLEN = 30);

// ---- reading ----

ClassMethod ById(id As %String) As Shutter.Catalogue.SiteEntry
{
    Set rid = ""
    &sql(SELECT ID INTO :rid FROM Shutter_Catalogue.SiteEntry WHERE EntryId = :id)
    If (SQLCODE '= 0) || (rid = "") Quit ""
    Quit ..%OpenId(rid)
}

/// Whether an id has the form of a site entry's.
ClassMethod IsSiteId(id As %String) As %Boolean
{
    Quit $MATCH(id, "L[1-9][0-9]*")
}

/// The generation: raised at every activation, suspension, resumption and retirement and never lowered, so an approval
/// voided by one change is not made valid again by undoing it. 0 on a site that never activated an entry.
ClassMethod Generation() As %Integer
{
    Quit +$GET(^Shutter.Catalogue.Site("generation"))
}

/// What the catalogue's version carries after the shipped list: "" on a site that never activated an entry (its
/// version string stays the shipped one), else ";g<generation>:" and the active entries' ids and versions. When the
/// entries can't be read the part after the generation is "unreadable", which no plan's version ever equals.
ClassMethod VersionSuffix() As %String
{
    Set generation = ..Generation()
    If generation = 0 Quit ""
    Set ids = ..ActiveIds(, .problem)
    Quit ";g" _ generation _ ":" _ $SELECT(problem '= "": "unreadable", 1: ids)
}

/// The active entries as "L1@2,L4@1", in the order they were made, leaving one out when asked. A query that fails sets
/// <var>problem</var>: the matcher then answers error (R13), never "no entries".
ClassMethod ActiveIds(exceptId As %String = "", Output problem As %String) As %String
{
    Set out = "", problem = ""
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT EntryId, ActiveVersion FROM Shutter_Catalogue.SiteEntry WHERE State = 'active' ORDER BY ID")
    If rs.%SQLCODE < 0 Set problem = "the active site entries cannot be listed (SQLCODE " _ rs.%SQLCODE _ ")" Quit ""
    Set sc = $$$OK
    Try {
        While rs.%Next(.sc) {
            Continue:(rs.%Get("EntryId") = exceptId)
            Set out = out _ $SELECT(out = "": "", 1: ",") _ rs.%Get("EntryId") _ "@" _ rs.%Get("ActiveVersion")
        }
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    If $$$ISERR(sc) || (rs.%SQLCODE < 0) Set problem = "the active site entries cannot be listed: " _ $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "SQLCODE " _ rs.%SQLCODE) Quit ""
    Quit out
}

/// How many entries are active, one left out when asked.
ClassMethod ActiveCount(exceptId As %String = "") As %Integer
{
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Catalogue.SiteEntry WHERE State = 'active' AND (:exceptId IS NULL OR EntryId <> :exceptId))
    Quit +n
}

/// One entry as the matcher reads it: what a stored row gives it and nothing else.
ClassMethod MatchItem(id As %String, version As %Integer, content As %DynamicObject, pattern As %DynamicObject, scope As %DynamicObject = "") As %DynamicObject
{
    Set json = "Shutter.Util.Json"
    Set m = {}
    Set m.id = id, m.version = +version, m.title = $CLASSMETHOD(json, "Str", content, "title")
    Do m.%Set("priority", +$CLASSMETHOD(json, "Str", content, "priority", 100), "number")
    Set m.scope = $SELECT($ISOBJECT(scope): scope, $ISOBJECT(content.%Get("scope")): content.%Get("scope"), 1: {})
    Set m.pattern = $SELECT($ISOBJECT(pattern): pattern, 1: {})
    Set m.why = $CLASSMETHOD(json, "Str", content, "why"), m.team = $CLASSMETHOD(json, "Str", content, "team")
    Set m.instructions = $CLASSMETHOD(json, "Str", content, "instructions"), m.prose = $CLASSMETHOD(json, "Str", content, "prose")
    Quit m
}

/// A list of match items with one more laid over it, in the matcher's order: the priority, then the id's number.
ClassMethod Ordered(list As %DynamicArray, extra As %DynamicObject = "") As %DynamicArray
{
    Set it = list.%GetIterator()
    While it.%GetNext(, .m) { Set sorted(+m.priority, +$EXTRACT(m.id, 2, *), m.id) = m }
    If $ISOBJECT(extra) Set sorted(+extra.priority, +$EXTRACT(extra.id, 2, *), extra.id) = extra
    Set out = [], p = ""
    For {
        Set p = $ORDER(sorted(p)) Quit:p=""
        Set n = ""
        For {
            Set n = $ORDER(sorted(p, n)) Quit:n=""
            Set id = ""
            For { Set id = $ORDER(sorted(p, n, id), 1, m) Quit:id=""  Do out.%Push(m) }
        }
    }
    Quit out
}

/// The active entries as the matcher reads them, in its order. After an upgrade they are rechecked first (R14), before
/// any case is matched. An active row that can't be read sets <var>problem</var>: the matcher then answers error, which
/// stops every write, and the entry is never skipped (R13). So does a site with active entries that no recheck has
/// completed under this release yet (one could not take the lock, or could not save what it found): the recheck is tried
/// again at every match until one completes, and until then no case is matched on entries that were not checked.
ClassMethod ActiveList(Output problem As %String, exceptId As %String = "") As %DynamicArray
{
    Set problem = "", list = []
    Set release = $PARAMETER("Shutter.Setup", "VERSION")
    If $GET(^Shutter.Catalogue.Site("checked")) '= release {
        // A caller that only reads (a role with no write access to the database) cannot complete the recheck: it gets
        // error too, until a process that can has run it.
        Set ok = 0
        Try { Do ..Recheck("upgrade", 1, .ok) } Catch ex { Set ok = 0 }
        If 'ok && (..ActiveCount() > 0) Set problem = "the site entries have not been rechecked under release " _ release _ " yet (the recheck is tried again at the next match)" Quit []
    }
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, EntryId FROM Shutter_Catalogue.SiteEntry WHERE State = 'active' ORDER BY ID")
    If rs.%SQLCODE < 0 Set problem = "the active site entries cannot be read (SQLCODE " _ rs.%SQLCODE _ ")" Quit []
    Set rsc = $$$OK
    Try {
        While rs.%Next(.rsc) {
            Set id = rs.%Get("EntryId")
            Continue:(id = exceptId)
            Set e = ..%OpenId(rs.%Get("ID"))
            If '$ISOBJECT(e) Set problem = "the row of site entry " _ id _ " cannot be opened" Quit
            Set v = ##class(Shutter.Catalogue.SiteEntryVersion).Find(e.EntryId, e.ActiveVersion)
            Set content = $SELECT($ISOBJECT(v): v.Content(), 1: "")
            If '$ISOBJECT(content) Set problem = "version " _ e.ActiveVersion _ " of site entry " _ id _ " cannot be read" Quit
            Set pattern = content.%Get("pattern")
            If e.EffectiveJSON '= "" Set pattern = ##class(Shutter.Util.Json).Parse(e.EffectiveJSON, .sc)
            If '$ISOBJECT(pattern) || 'pattern.%IsA("%Library.DynamicObject") Set problem = "the pattern of site entry " _ id _ " cannot be read" Quit
            Set scope = content.%Get("scope")
            If e.EffectiveScopeJSON '= "" {
                Set scope = ##class(Shutter.Util.Json).Parse(e.EffectiveScopeJSON, .sc)
                If '$ISOBJECT(scope) || 'scope.%IsA("%Library.DynamicObject") Set problem = "the widened scope of site entry " _ id _ " cannot be read" Quit
            }
            If $ISOBJECT(scope) && 'scope.%IsA("%Library.DynamicObject") Set problem = "the scope of site entry " _ id _ " cannot be read" Quit
            Do list.%Push(..MatchItem(e.EntryId, e.ActiveVersion, content, pattern, scope))
        }
    } Catch ex {
        Set rsc = ex.AsStatus()
    }
    // A row the query itself cannot read ends the listing early: it is a problem, never the end of the entries (R13).
    If (problem = "") && ($$$ISERR(rsc) || (rs.%SQLCODE < 0)) Set problem = "the active site entries cannot be read: " _ $SELECT($$$ISERR(rsc): $SYSTEM.Status.GetErrorText(rsc), 1: "SQLCODE " _ rs.%SQLCODE)
    If problem '= "" Quit []
    Quit ..Ordered(list)
}

/// Which of the site's own entries stopped a case: the match its current evidence carries, when that match is a site
/// entry's (origin site; it is then the case's only match). {entry, title, instructions}, or "" for a case no site entry
/// matched. Read by the closures that run outside the case workflow (the outage close, the engine's delivery read and
/// the resend set), so that none of them settles such a case, or offers its message, without a person seeing the brake.
ClassMethod StoppedCase(case As Shutter.Store.Case) As %DynamicObject
{
    Set json = "Shutter.Util.Json"
    If '$ISOBJECT(case) Quit ""
    Set snap = case.CurrentSnapshot
    Set summary = $SELECT($ISOBJECT(snap): snap.SummaryObject(), 1: "")
    Set cat = $SELECT($ISOBJECT(summary): summary.%Get("catalogue"), 1: "")
    If '$ISOBJECT(cat) || (cat.%GetTypeOf("matches") '= "array") || (cat.%Get("matches").%Size() = 0) Quit ""
    Set m = cat.%Get("matches").%Get(0)
    If '$ISOBJECT(m) || ($CLASSMETHOD(json, "Str", m, "origin") '= "site") Quit ""
    Quit {"entry": ($CLASSMETHOD(json, "Str", m, "id")), "title": ($CLASSMETHOD(json, "Str", m, "title")), "instructions": ($CLASSMETHOD(json, "Str", m, "instructions"))}
}

/// The words for a case one of the site's own entries stopped: the entry, and its instructions when it has them.
ClassMethod StoppedWords(stopped As %DynamicObject) As %String
{
    Set words = "the site's own scenario " _ stopped.entry _ " asks a person"
    If stopped.instructions '= "" Set words = words _ ": " _ stopped.instructions
    Quit words
}

/// How many cases an entry sent to a person: the cases with a plan that names it, in all or since a number of days.
ClassMethod CasesSent(id As %String, days As %Integer = 0) As %Integer
{
    Set n = 0
    If days > 0 {
        Set since = ##class(Shutter.Util.Time).FromNow(-86400 * days)
        &sql(SELECT COUNT(DISTINCT "Case") INTO :n FROM Shutter_Store.Plan WHERE CatalogueEntry = :id AND CreatedAt >= :since)
    } Else {
        &sql(SELECT COUNT(DISTINCT "Case") INTO :n FROM Shutter_Store.Plan WHERE CatalogueEntry = :id)
    }
    Quit +n
}

/// The state a person reads: proposed while a never-active entry waits for its approval, else the row's state.
Method ShownState() As %String
{
    Quit $SELECT((..State = "draft") && (..ProposalAction '= ""): "proposed", 1: ..State)
}

/// The entry for the API. <var>full</var> adds every version, the proofs and the events.
Method Describe(full As %Boolean = 0) As %DynamicObject
{
    Set json = "Shutter.Util.Json", versionClass = "Shutter.Catalogue.SiteEntryVersion"
    Set o = {}
    Set o.id = ..EntryId, o.state = ..ShownState(), o.kind = "stop"
    Do o.%Set("activeVersion", +..ActiveVersion, "number"), o.%Set("draftVersion", +..DraftVersion, "number"), o.%Set("revision", +..Revision, "number")
    Set active = $SELECT(..ActiveVersion > 0: $CLASSMETHOD(versionClass, "Find", ..EntryId, ..ActiveVersion), 1: "")
    Set draft = $SELECT(..DraftVersion > 0: $CLASSMETHOD(versionClass, "Find", ..EntryId, ..DraftVersion), 1: "")
    Set shown = $SELECT($ISOBJECT(active): active, 1: draft)
    Set content = $SELECT($ISOBJECT(shown): shown.Content(), 1: "")
    If $ISOBJECT(content) {
        Set o.title = $CLASSMETHOD(json, "Str", content, "title"), o.sentence = $CLASSMETHOD(versionClass, "Sentence", content)
        Set o.content = content, o.digest = shown.Digest
        Do o.%Set("version", +shown.Version, "number")
    } Else {
        Set o.title = "", o.sentence = "", o.unreadable = "This entry's content cannot be read"
    }
    If $ISOBJECT(active) Set o.approvedBy = active.ApprovedBy, o.approvedAt = active.ApprovedAt
    If $ISOBJECT(draft) && $ISOBJECT(active) {
        Set d = {}
        Do d.%Set("version", +draft.Version, "number")
        Set d.digest = draft.Digest, d.writtenBy = draft.WrittenBy, d.writtenAt = draft.WrittenAt
        Set dc = draft.Content()
        If $ISOBJECT(dc) Set d.content = dc, d.sentence = $CLASSMETHOD(versionClass, "Sentence", dc)
        Set o.draft = d
    }
    If ..ProposalAction '= "" {
        Set p = {}
        Set p.action = ..ProposalAction, p.digest = ..ProposalDigest, p.by = ..ProposalBy, p.at = ..ProposalAt, p.proofId = ..ProposalProofId
        Do p.%Set("version", +..ProposalVersion, "number")
        Set o.proposal = p
    }
    Do o.%Set("needsReview", ''..NeedsReview, "boolean")
    If ..ReviewJSON '= "" Set o.review = $CLASSMETHOD(json, "Parse", ..ReviewJSON, .sc)
    If ..EffectiveJSON '= "" Set o.effectivePattern = $CLASSMETHOD(json, "Parse", ..EffectiveJSON, .sc)
    If ..EffectiveScopeJSON '= "" Set o.effectiveScope = $CLASSMETHOD(json, "Parse", ..EffectiveScopeJSON, .sc)
    If ..State = "suspended" Set o.suspended = {"by": (..SuspendedBy), "at": (..SuspendedAt), "reason": (..SuspendedReason)}
    Do o.%Set("casesSent", ..CasesSent(..EntryId), "number"), o.%Set("casesSent30", ..CasesSent(..EntryId, 30), "number")
    Set o.createdBy = ..CreatedBy, o.createdAt = ..CreatedAt, o.updatedAt = ..UpdatedAt
    If full {
        Set versions = []
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Catalogue.SiteEntryVersion WHERE EntryId = ? ORDER BY Version DESC", ..EntryId)
        While rs.%Next() {
            Set v = $CLASSMETHOD(versionClass, "%OpenId", rs.%Get("ID"))
            If $ISOBJECT(v) Do versions.%Push(v.ToObject())
        }
        Set o.versions = versions
        Set o.proofs = ##class(Shutter.Catalogue.SiteEntryProof).For(..EntryId)
        Set o.events = ##class(Shutter.Catalogue.SiteEntryEvent).For(..EntryId)
    }
    Quit o
}

/// Every entry, the active ones first in the matcher's order, then the rest, newest first.
ClassMethod List() As %DynamicArray
{
    Set out = []
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Catalogue.SiteEntry ORDER BY CASE State WHEN 'active' THEN 0 WHEN 'suspended' THEN 1 WHEN 'draft' THEN 2 ELSE 3 END, Priority, ID")
    While rs.%Next() {
        Set e = ..%OpenId(rs.%Get("ID"))
        If $ISOBJECT(e) Do out.%Push(e.Describe())
    }
    Quit out
}

/// The site's entries as a whole: the counts, the generation, who lifted the two-person rule if anyone did, and the
/// warnings the page and the Doctor show for as long as they hold.
ClassMethod Status() As %DynamicObject
{
    Set o = {}, warnings = [], suspended = [], review = [], active = 0, proposed = 0
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT EntryId, State, NeedsReview, ProposalAction, SuspendedBy, SuspendedAt FROM Shutter_Catalogue.SiteEntry ORDER BY ID")
    While rs.%Next() {
        Set id = rs.%Get("EntryId"), state = rs.%Get("State")
        If state = "active" Set active = active + 1
        If rs.%Get("ProposalAction") '= "" Set proposed = proposed + 1
        If state = "suspended" {
            Do suspended.%Push(id)
            Do warnings.%Push("Site entry " _ id _ " is suspended (by " _ rs.%Get("SuspendedBy") _ ", " _ rs.%Get("SuspendedAt") _ "): its protection is off until a second person approves resuming it")
        }
        If rs.%Get("NeedsReview") && ((state = "active") || (state = "suspended")) {
            Do review.%Push(id)
            Do warnings.%Push("Site entry " _ id _ " needs review: an upgrade or a change of the site profile touched it. It still applies")
        }
    }
    Set one = ..OnePerson()
    If $ISOBJECT(one) Do warnings.%Push("The two-person rule for site entries is lifted (by " _ one.by _ ", " _ one.at _ "): one person may propose and approve their own entry")
    Do o.%Set("active", active, "number"), o.%Set("proposed", proposed, "number"), o.%Set("generation", ..Generation(), "number")
    Do o.%Set("limit", $PARAMETER("Shutter.Catalogue.SiteEntryVersion", "MAXACTIVE"), "number")
    Set o.suspended = suspended, o.needsReview = review
    If $ISOBJECT(one) { Set o.onePerson = one } Else { Do o.%Set("onePerson", "", "null") }
    Set o.warnings = warnings
    // What a downgrade costs, said where the person who plans one reads (docs/INSTALL.md).
    If active > 0 Set o.downgrade = active _ " site " _ $SELECT(active = 1: "entry", 1: "entries") _ " active: they stop applying below this release"
    Quit o
}

// ---- the two-person rule ----

/// Who lifted the two-person rule, as {by, at, reason}, or "" while it holds.
ClassMethod OnePerson() As %DynamicObject
{
    Set row = $GET(^Shutter.Catalogue.Site("onePerson"))
    If row = "" Quit ""
    Quit {"by": ($LISTGET(row, 1)), "at": ($LISTGET(row, 2)), "reason": ($LISTGET(row, 3))}
}

/// Lift or restore the two-person rule, recorded as an event. Called by Shutter.Setup.SiteEntriesOnePerson, which an
/// IRIS administrator runs from the terminal; no route and no SQL procedure reaches it.
ClassMethod SetOnePerson(on As %Boolean, who As %String, reason As %String) As %Status [ Internal ]
{
    If on {
        Set ^Shutter.Catalogue.Site("onePerson") = $LISTBUILD(who, ##class(Shutter.Util.Time).NowUTC(), reason)
        Quit ##class(Shutter.Catalogue.SiteEntryEvent).Record("", "", "two_person_lifted", who, "terminal", "The two-person rule for site entries is lifted: " _ reason)
    }
    Kill ^Shutter.Catalogue.Site("onePerson")
    Quit ##class(Shutter.Catalogue.SiteEntryEvent).Record("", "", "two_person_restored", who, "terminal", "The two-person rule for site entries holds again" _ $SELECT(reason '= "": ": " _ reason, 1: ""))
}

// ---- changes ----

ClassMethod Lock() As %Boolean [ Private ]
{
    LOCK +^Shutter.Catalogue.Site("lock"):5
    Quit $TEST
}

ClassMethod Unlock() [ Private ]
{
    LOCK -^Shutter.Catalogue.Site("lock")
}

Method Touch() As %Status [ Private ]
{
    Set ..Revision = ..Revision + 1, ..UpdatedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit ..%Save()
}

/// A body that starts from a stored case: the pattern is every condition the case showed (the reserved ones aside),
/// the scope its facts, and the case is the first fixture, expected to match. What the body itself gives stands.
ClassMethod FromCase(caseId As %String, body As %DynamicObject, Output problem As %String) As %DynamicObject
{
    Set problem = ""
    Set frozen = ##class(Shutter.Catalogue.SiteEntryProof).Freeze(caseId, "match", .problem)
    If '$ISOBJECT(frozen) Quit body
    Set out = ##class(%DynamicObject).%FromJSON(body.%ToJSON())
    Do out.%Remove("fromCase")
    Set vocabulary = ##class(Shutter.Catalogue.Vocabulary).Current()
    Set reserved = ##class(Shutter.Catalogue.Vocabulary).SiteList(vocabulary, "reserved_conditions")
    If 'out.%IsDefined("pattern") {
        Set pattern = {}, it = frozen.conditions.%GetIterator()
        While it.%GetNext(.name, .value) { If '##class(Shutter.Catalogue.Vocabulary).In(reserved, name) Do pattern.%Set(name, value) }
        Set out.pattern = pattern
    }
    If 'out.%IsDefined("scope") {
        Set scope = {}, it = frozen.scope.%GetIterator()
        While it.%GetNext(.name, .value) { If value '= "" Do scope.%Set(name, value) }
        Set out.scope = scope
    }
    If 'out.%IsDefined("fixtures") Set out.fixtures = [{"case": (caseId), "expect": "match"}]
    Quit out
}

/// Make a draft from a body (R1 to R5). Returns "" and the entry, or bad_request with the problems, or busy.
ClassMethod Create(body As %DynamicObject, actor As %String, source As %String, Output entry As Shutter.Catalogue.SiteEntry, Output problems As %DynamicArray, Output warnings As %DynamicArray) As %String
{
    Set entry = "", problems = [], warnings = []
    If $ISOBJECT(body) && body.%IsA("%Library.DynamicObject") && body.%IsDefined("fromCase") {
        Set body = ..FromCase(##class(Shutter.Util.Json).Str(body, "fromCase"), body, .problem)
        If problem '= "" Do problems.%Push({"rule": "R1", "field": "fromCase", "text": (problem)}) Quit "bad_request"
    }
    Do ##class(Shutter.Catalogue.SiteEntryVersion).Normalise(body, "", .content, .problems, .warnings)
    If problems.%Size() > 0 Quit "bad_request"
    If '..Lock() Quit "busy"
    Set code = ""
    Try {
        TSTART
        Set now = ##class(Shutter.Util.Time).NowUTC()
        Set entry = ..%New()
        Set entry.EntryId = "L" _ $INCREMENT(^Shutter.Catalogue.Site("next"))
        Set entry.State = "draft", entry.DraftVersion = 1, entry.CreatedBy = $EXTRACT(actor, 1, 160), entry.CreatedAt = now, entry.UpdatedAt = now
        Set content.id = entry.EntryId
        $$$ThrowOnError(entry.%Save())
        $$$ThrowOnError(..WriteDraft(entry.EntryId, 1, content, actor))
        $$$ThrowOnError(##class(Shutter.Catalogue.SiteEntryEvent).Record(entry.EntryId, 1, "created", actor, source, "Draft made: " _ ##class(Shutter.Util.Json).Str(content, "title")))
        TCOMMIT
    } Catch ex {
        If $TLEVEL > 0 TROLLBACK
        Set code = "failed", entry = ""
        Do problems.%Push({"rule": "", "field": "", "text": (ex.DisplayString())})
    }
    Do ..Unlock()
    Quit code
}

/// The draft's row written: a new one, or the open draft rewritten. An approved version is never written again.
ClassMethod WriteDraft(entryId As %String, version As %Integer, content As %DynamicObject, actor As %String) As %Status [ Private ]
{
    Set v = ##class(Shutter.Catalogue.SiteEntryVersion).Find(entryId, version)
    If '$ISOBJECT(v) Set v = ##class(Shutter.Catalogue.SiteEntryVersion).%New(), v.EntryId = entryId, v.Version = version
    If v.Status = "approved" Quit $$$ERROR($$$GeneralError, "Version " _ version _ " of " _ entryId _ " is approved and cannot be changed")
    Set v.Status = "draft"
    Set v.Json = ##class(Shutter.Util.Digest).Canonical(content), v.Digest = ##class(Shutter.Catalogue.SiteEntryVersion).DigestOf(content)
    Set v.WrittenBy = $EXTRACT(actor, 1, 160), v.WrittenAt = ##class(Shutter.Util.Time).NowUTC()
    Quit v.%Save()
}

/// Change the draft, or begin one beside the active version. expectedVersion is the revision the caller read, and is
/// required (stale_version when it is missing or not the entry's). The state, an open proposal and the revision are
/// read again under the lock, so a change racing a proposal never rewrites the version that was frozen.
ClassMethod Change(id As %String, body As %DynamicObject, expectedVersion As %String, actor As %String, source As %String, Output entry As Shutter.Catalogue.SiteEntry, Output problems As %DynamicArray, Output warnings As %DynamicArray, Output detail As %String) As %String
{
    Set problems = [], warnings = [], detail = ""
    Set entry = ..ById(id)
    If '$ISOBJECT(entry) Quit "not_found"
    Set code = ..Changeable(entry, expectedVersion, .detail)
    If code '= "" Quit code
    Do ##class(Shutter.Catalogue.SiteEntryVersion).Normalise(body, id, .content, .problems, .warnings)
    If problems.%Size() > 0 Quit "bad_request"
    If '..Lock() Quit "busy"
    Set code = ""
    Try {
        TSTART
        Set entry = ..ById(id)
        Set code = $SELECT('$ISOBJECT(entry): "not_found", 1: ..Changeable(entry, expectedVersion, .detail))
        If code = "" {
            If entry.DraftVersion = 0 Set entry.DraftVersion = ..NextVersion(id)
            $$$ThrowOnError(..WriteDraft(id, entry.DraftVersion, content, actor))
            $$$ThrowOnError(entry.Touch())
            $$$ThrowOnError(##class(Shutter.Catalogue.SiteEntryEvent).Record(id, entry.DraftVersion, "edited", actor, source, "Draft version " _ entry.DraftVersion _ " changed"))
        }
        TCOMMIT
    } Catch ex {
        If $TLEVEL > 0 TROLLBACK
        Set code = "failed", detail = ex.DisplayString()
        // The copy in memory is the stored row again, as the rollback left it.
        If $ISOBJECT($GET(entry)) {
            Try { Do entry.%Reload() } Catch reload { }
        }
    }
    Do ..Unlock()
    Quit code
}

/// Whether the entry's draft may be changed now by a caller who read <var>expectedVersion</var>: "" when it may, else
/// the code, with the words (or the revision, for stale_version) in <var>detail</var>.
ClassMethod Changeable(entry As Shutter.Catalogue.SiteEntry, expectedVersion As %String, Output detail As %String) As %String [ Private ]
{
    Set detail = ""
    If entry.State = "retired" Set detail = entry.EntryId _ " is retired: its history is kept and it is not changed again" Quit "wrong_state"
    If entry.ProposalAction = "activate" Set detail = "Version " _ entry.ProposalVersion _ " of " _ entry.EntryId _ " waits for approval and is frozen until it is approved or rejected" Quit "wrong_state"
    If ($ZSTRIP(expectedVersion, "<>W") = "") || (+expectedVersion '= +entry.Revision) Set detail = entry.Revision Quit "stale_version"
    Quit ""
}

/// The number the next version takes: one more than the highest the entry has had.
ClassMethod NextVersion(id As %String) As %Integer [ Private ]
{
    Set n = 0
    &sql(SELECT MAX(Version) INTO :n FROM Shutter_Catalogue.SiteEntryVersion WHERE EntryId = :id)
    Quit +n + 1
}

/// The version an action is about and why the action can't be taken now ("" when it can): activate is about the open
/// draft, retire and resume about the active version.
Method VersionFor(action As %String, Output why As %String) As Shutter.Catalogue.SiteEntryVersion
{
    Set why = ""
    If action = "activate" {
        If ..State = "retired" Set why = ..EntryId _ " is retired" Quit ""
        If ..DraftVersion = 0 Set why = ..EntryId _ " has no draft to activate" Quit ""
        Quit ##class(Shutter.Catalogue.SiteEntryVersion).Find(..EntryId, ..DraftVersion)
    }
    If action = "retire" {
        If (..State '= "active") && (..State '= "suspended") Set why = ..EntryId _ " is " _ ..State _ ": only an active or suspended entry is retired" Quit ""
        Quit ##class(Shutter.Catalogue.SiteEntryVersion).Find(..EntryId, ..ActiveVersion)
    }
    If action = "resume" {
        If ..State '= "suspended" Set why = ..EntryId _ " is " _ ..State _ ": only a suspended entry is resumed" Quit ""
        Quit ##class(Shutter.Catalogue.SiteEntryVersion).Find(..EntryId, ..ActiveVersion)
    }
    Set why = "The action is activate, retire or resume"
    Quit ""
}

/// Run a proof for an action (activate when none is named and a draft is open) and keep it.
ClassMethod Prove(id As %String, action As %String, actor As %String, source As %String, Output result As %DynamicObject, Output detail As %String) As %String
{
    Set result = "", detail = ""
    Set entry = ..ById(id)
    If '$ISOBJECT(entry) Quit "not_found"
    If action = "" Set action = "activate"
    Set v = entry.VersionFor(action, .detail)
    If '$ISOBJECT(v) Quit $SELECT(detail [ "The action is": "bad_request", 1: "wrong_state")
    Set content = v.Content()
    If '$ISOBJECT(content) Set detail = "Version " _ v.Version _ " of " _ id _ " cannot be read" Quit "wrong_state"
    Set result = ##class(Shutter.Catalogue.SiteEntryProof).Run(id, v.Version, content, action, actor, "api", 1, .proof)
    Do ##class(Shutter.Catalogue.SiteEntryEvent).Record(id, v.Version, "proved", actor, source, "Proof for " _ action _ ": " _ $SELECT(result.passed: "passed", 1: "did not pass"), $SELECT($ISOBJECT(proof): "proof:" _ proof.%Id(), 1: ""))
    Quit ""
}

/// Propose an action: the version and its digest are frozen for a second person, with a passing proof of that digest
/// made under the catalogue, profile, gate policy and release in force (409 no_proof otherwise).
ClassMethod Propose(id As %String, action As %String, actor As %String, source As %String, Output entry As Shutter.Catalogue.SiteEntry, Output detail As %String) As %String
{
    Set detail = ""
    If '..Lock() Quit "busy"
    Set code = ""
    Try {
        Set entry = ..ById(id)
        If '$ISOBJECT(entry) Set code = "not_found" Quit
        If entry.ProposalAction '= "" Set code = "wrong_state", detail = "A proposal to " _ entry.ProposalAction _ " " _ id _ " already waits for approval" Quit
        Set v = entry.VersionFor(action, .detail)
        If '$ISOBJECT(v) Set code = $SELECT(detail [ "The action is": "bad_request", 1: "wrong_state") Quit
        Set content = v.Content()
        If '$ISOBJECT(content) Set code = "wrong_state", detail = "Version " _ v.Version _ " of " _ id _ " cannot be read" Quit
        If action '= "retire" {
            Set detail = ..StillValid(content, id)
            If detail '= "" Set code = "bad_request" Quit
        }
        If (action = "activate") && (entry.State '= "active") && (..ActiveCount(id) >= $PARAMETER("Shutter.Catalogue.SiteEntryVersion", "MAXACTIVE")) Set code = "too_many", detail = "The site has its " _ $PARAMETER("Shutter.Catalogue.SiteEntryVersion", "MAXACTIVE") _ " active site entries already" Quit
        Set proof = ##class(Shutter.Catalogue.SiteEntryProof).Latest(id, v.Digest, action)
        If '$ISOBJECT(proof) Set code = "no_proof", detail = "No proof of this version's digest for " _ action _ ": run the proof first" Quit
        If 'proof.Passed Set code = "no_proof", detail = "The latest proof of this digest did not pass" Quit
        If 'proof.Current() Set code = "no_proof", detail = "The proof is stale: the catalogue, the site profile, the gate's policy or the release changed since it ran. Run it again" Quit
        // The proposal and its event together, or neither.
        TSTART
        Set entry.ProposalAction = action, entry.ProposalVersion = v.Version, entry.ProposalDigest = v.Digest
        Set entry.ProposalBy = $EXTRACT(actor, 1, 160), entry.ProposalAt = ##class(Shutter.Util.Time).NowUTC(), entry.ProposalProofId = proof.%Id()
        $$$ThrowOnError(entry.Touch())
        $$$ThrowOnError(##class(Shutter.Catalogue.SiteEntryEvent).Record(id, v.Version, "proposed", actor, source, "Proposed: " _ action _ " version " _ v.Version, v.Digest))
        TCOMMIT
    } Catch ex {
        If $TLEVEL > 0 TROLLBACK
        Set code = "failed", detail = ex.DisplayString()
        // The copy in memory is the stored row again, as the rollback left it.
        If $ISOBJECT($GET(entry)) {
            Try { Do entry.%Reload() } Catch reload { }
        }
    }
    Do ..Unlock()
    Quit code
}

/// Whether a content still passes the rules now (the site profile or the vocabulary may have changed since it was
/// written): "" or the first problem.
ClassMethod StillValid(content As %DynamicObject, id As %String) As %String [ Private ]
{
    Set body = ##class(%DynamicObject).%FromJSON(content.%ToJSON())
    // The fixtures were frozen when the draft was written; they are not read again here.
    Do body.%Remove("fixtures")
    Do ##class(Shutter.Catalogue.SiteEntryVersion).Normalise(body, id, .again, .problems, .warnings, 0)
    If problems.%Size() = 0 Quit ""
    Quit problems.%Get(0).text
}

/// A second person's decision on the open proposal (R6 to R8). The body is {action, version, digest, decision, reason,
/// safetyReference?}: the action, version and digest are the ones the approver read. On approve the proof is run again
/// (P1 and P2) and must answer as the proposal's did; then the change is made, the generation raised and the events
/// written, all or nothing. <var>extra</var> carries waitingPlans, the open cases whose plan was made under the old
/// catalogue version (none of them completes under it), and the new catalogueVersion.
ClassMethod Decide(id As %String, body As %DynamicObject, actor As %String, source As %String, Output entry As Shutter.Catalogue.SiteEntry, Output detail As %String, Output extra As %DynamicObject) As %String
{
    Set json = "Shutter.Util.Json", detail = "", extra = {}
    Set decision = $CLASSMETHOD(json, "Str", body, "decision"), reason = $ZSTRIP(##class(Shutter.Util.ModelView).Clean($CLASSMETHOD(json, "Str", body, "reason")), "<>W")
    If (decision '= "approve") && (decision '= "reject") Set detail = "decision is approve or reject" Quit "bad_request"
    If reason = "" Set detail = "A reason is required" Quit "bad_request"
    If '..Lock() Quit "busy"
    Set code = ""
    Try {
        Set entry = ..ById(id)
        If '$ISOBJECT(entry) Set code = "not_found" Quit
        If entry.ProposalAction = "" Set code = "wrong_state", detail = "No proposal waits for approval on " _ id Quit
        Set action = entry.ProposalAction
        If ($CLASSMETHOD(json, "Str", body, "action") '= action) || (+$CLASSMETHOD(json, "Str", body, "version") '= +entry.ProposalVersion) || ($CLASSMETHOD(json, "Str", body, "digest") '= entry.ProposalDigest) {
            Set code = "digest_mismatch", detail = "The proposal is to " _ action _ " version " _ entry.ProposalVersion _ " with digest " _ entry.ProposalDigest _ ": the action, version and digest sent are not all those"
            Quit
        }
        // A rejection returns the entry to its draft, and its event is written with it. It is taken even when the stored
        // version no longer has the digest proposed, so a proposal can never be left stuck.
        If decision = "reject" {
            Set version = entry.ProposalVersion, digest = entry.ProposalDigest
            TSTART
            Set entry.ProposalAction = "", entry.ProposalVersion = "", entry.ProposalDigest = "", entry.ProposalBy = "", entry.ProposalAt = "", entry.ProposalProofId = ""
            $$$ThrowOnError(entry.Touch())
            $$$ThrowOnError(##class(Shutter.Catalogue.SiteEntryEvent).Record(id, version, "rejected", actor, source, "Rejected (" _ action _ "): " _ reason, digest))
            TCOMMIT
            Quit
        }
        Set v = ##class(Shutter.Catalogue.SiteEntryVersion).Find(id, entry.ProposalVersion)
        Set content = $SELECT($ISOBJECT(v): v.Content(), 1: "")
        If '$ISOBJECT(content) || (v.Digest '= entry.ProposalDigest) Set code = "digest_mismatch", detail = "The proposed version is no longer the one proposed: reject the proposal, and the draft can be changed and proposed again" Quit
        // Two people (R6): the approver neither proposed this nor last changed the version, unless an IRIS administrator
        // lifted the rule from the terminal, which every such approval then says. A user name is the same person whatever
        // its letters' case, as IRIS reads it at sign-in.
        Set who = $ZCONVERT(actor, "U")
        Set alone = (who = $ZCONVERT(entry.ProposalBy, "U")) || ((action = "activate") && (who = $ZCONVERT(v.WrittenBy, "U")))
        If alone && '$ISOBJECT(..OnePerson()) Set code = "same_person", detail = "A second person approves a site entry: " _ actor _ " proposed this or wrote the version" Quit
        If action '= "retire" {
            Set detail = ..StillValid(content, id)
            If detail '= "" Set code = "bad_request" Quit
            Set detail = ""
        }
        If (action '= "retire") && (..ActiveCount(id) >= $PARAMETER("Shutter.Catalogue.SiteEntryVersion", "MAXACTIVE")) Set code = "too_many", detail = "The site has its " _ $PARAMETER("Shutter.Catalogue.SiteEntryVersion", "MAXACTIVE") _ " active site entries already" Quit
        // The proof again (R8, P5): nobody activates on a stale proof, or on one the evidence no longer bears out.
        // A proposal whose own proof went stale stands on the newest one a person ran of the same digest since, if any.
        Set proposed = ##class(Shutter.Catalogue.SiteEntryProof).%OpenId(entry.ProposalProofId)
        If '$ISOBJECT(proposed) || 'proposed.Passed || 'proposed.Current() Set proposed = ##class(Shutter.Catalogue.SiteEntryProof).Latest(id, v.Digest, action)
        If '$ISOBJECT(proposed) || 'proposed.Passed || 'proposed.Current() Set code = "proof_failed", detail = "The proof of this digest is stale: the catalogue, the site profile, the gate's policy or the release changed since it ran. Run the proof again" Quit
        Set again = ##class(Shutter.Catalogue.SiteEntryProof).Run(id, v.Version, content, action, actor, "approval", 0, .proofNow)
        If 'again.passed || '$ISOBJECT(proofNow) || (##class(Shutter.Util.Digest).Canonical(again.fixtures) '= ##class(Shutter.Util.Digest).Canonical(proposed.ToObject().result.%Get("fixtures"))) {
            Set code = "proof_failed", detail = "The proof run again at approval did not answer as the proposal's did"
            Set extra.proof = again
            Quit
        }
        Set before = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
        Set now = ##class(Shutter.Util.Time).NowUTC()
        TSTART
        If action = "activate" {
            Set v.Status = "approved", v.ApprovedBy = $EXTRACT(actor, 1, 160), v.ApprovedAt = now, v.Reason = $EXTRACT(reason, 1, 1000)
            Set v.SafetyReference = $EXTRACT($ZSTRIP(##class(Shutter.Util.ModelView).Clean($CLASSMETHOD(json, "Str", body, "safetyReference")), "<>W"), 1, 300)
            Set v.ProofId = proofNow.%Id(), v.Release = $PARAMETER("Shutter.Setup", "VERSION")
            $$$ThrowOnError(v.%Save())
            Set entry.ActiveVersion = v.Version, entry.DraftVersion = 0, entry.State = "active"
            Set entry.Priority = +$CLASSMETHOD(json, "Str", content, "priority", 100)
        } ElseIf action = "retire" {
            Set entry.State = "retired"
        } Else {
            Set entry.State = "active"
        }
        Set entry.SuspendedBy = "", entry.SuspendedAt = "", entry.SuspendedReason = ""
        Set entry.ProposalAction = "", entry.ProposalVersion = "", entry.ProposalDigest = "", entry.ProposalBy = "", entry.ProposalAt = "", entry.ProposalProofId = ""
        // A newly approved version is a person's review: what earlier rechecks dropped, and their flag, clear only here.
        // A resumption keeps them, since its version is the one they were found on.
        If (action = "activate") || (entry.State '= "active") Set entry.NeedsReview = 0, entry.ReviewJSON = "", entry.EffectiveJSON = "", entry.EffectiveScopeJSON = ""
        If entry.State = "active" Do entry.Review(##class(Shutter.Catalogue.Vocabulary).Current(), "approval")
        $$$ThrowOnError(entry.Touch())
        Set generation = $INCREMENT(^Shutter.Catalogue.Site("generation"))
        Set words = $SELECT(alone: " The same person proposed and approved it: the two-person rule is lifted.", 1: "")
        $$$ThrowOnError(##class(Shutter.Catalogue.SiteEntryEvent).Record(id, v.Version, "approved", actor, source, "Approved (" _ action _ "): " _ reason _ words, v.Digest))
        $$$ThrowOnError(##class(Shutter.Catalogue.SiteEntryEvent).Record(id, v.Version, $CASE(action, "activate": "activated", "retire": "retired", : "resumed"), actor, source, "Version " _ v.Version _ " " _ $CASE(action, "activate": "is active", "retire": "is retired", : "applies again") _ "; catalogue generation " _ generation, "proof:" _ proofNow.%Id()))
        TCOMMIT
        Do extra.%Set("waitingPlans", ..WaitingPlans(before), "number")
        Set extra.catalogueVersion = ##class(Shutter.Catalogue.Entry).CatalogueVersion()
    } Catch ex {
        If $TLEVEL > 0 TROLLBACK
        Set code = "failed", detail = ex.DisplayString()
        // The copy in memory is the stored row again, as the rollback left it.
        If $ISOBJECT($GET(entry)) {
            Try { Do entry.%Reload() } Catch reload { }
        }
    }
    Do ..Unlock()
    Quit code
}

/// The open cases whose current plan was made under a catalogue version: none of them completes under it (a write is
/// void at dispatch, a closure is planned again).
ClassMethod WaitingPlans(version As %String) As %Integer
{
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Store."Case" WHERE State IN ('proposed', 'gated', 'rehearsing', 'awaiting_approval', 'approved', 'executing', 'verifying') AND CurrentPlan->CatalogueVersion = :version)
    Quit +n
}

/// Suspend one active entry at once (R12): one person holding Shutter_Approve and Shutter_Configure, with a reason. The
/// site returns to the shipped catalogue and gate for the cases it caught; the generation rises, so plans made while it
/// applied do not complete; the suspension is recorded and warned about for as long as it lasts.
ClassMethod Suspend(id As %String, reason As %String, actor As %String, source As %String, Output entry As Shutter.Catalogue.SiteEntry, Output detail As %String) As %String
{
    Set detail = ""
    Set reason = $ZSTRIP(##class(Shutter.Util.ModelView).Clean(reason), "<>W")
    If reason = "" Set detail = "A reason is required" Quit "bad_request"
    If '..Lock() Quit "busy"
    Set code = ""
    Try {
        Set entry = ..ById(id)
        If '$ISOBJECT(entry) Set code = "not_found" Quit
        If entry.State '= "active" Set code = "wrong_state", detail = id _ " is " _ entry.State _ ": only an active entry is suspended" Quit
        TSTART
        Set entry.State = "suspended", entry.SuspendedBy = $EXTRACT(actor, 1, 160), entry.SuspendedAt = ##class(Shutter.Util.Time).NowUTC(), entry.SuspendedReason = $EXTRACT(reason, 1, 1000)
        $$$ThrowOnError(entry.Touch())
        Set generation = $INCREMENT(^Shutter.Catalogue.Site("generation"))
        $$$ThrowOnError(##class(Shutter.Catalogue.SiteEntryEvent).Record(id, entry.ActiveVersion, "suspended", actor, source, "Suspended: " _ reason _ "; catalogue generation " _ generation))
        TCOMMIT
    } Catch ex {
        If $TLEVEL > 0 TROLLBACK
        Set code = "failed", detail = ex.DisplayString()
        // The copy in memory is the stored row again, as the rollback left it.
        If $ISOBJECT($GET(entry)) {
            Try { Do entry.%Reload() } Catch reload { }
        }
    }
    Do ..Unlock()
    Quit code
}

// ---- the recheck (R14) ----

/// Check every active or suspended entry against the vocabulary and the site profile in force, and replay its fixtures:
/// after an upgrade (the catalogue's seed, or the first match under a new release) and after every save of the site
/// profile. Nothing is retired or narrowed: an entry can only come out matching more, flagged for a person, and what one
/// recheck dropped no later one restores. An entry that comes out widened raises the generation, so a plan made before
/// it is not completed, as after an activation. Returns how many entries are flagged; <var>ok</var> is 1 only when every
/// entry was checked and what changed was saved with its event, and only then is the release recorded as checked. A
/// recheck that could not take the lock or save is tried again at the next match, which answers error until one
/// completes (ActiveList). <var>reload</var> 0 keeps the vocabulary in force instead of reading the installed file.
ClassMethod Recheck(trigger As %String = "upgrade", reload As %Boolean = 1, Output ok As %Boolean) As %Integer
{
    Set flagged = 0, ok = 0
    If '..Lock() {
        Kill ^Shutter.Catalogue.Site("checked")
        Quit 0
    }
    Set complete = 1
    Try {
        Set root = $GET(^Shutter.Config("root"))
        If reload && (root '= "") Do ##class(Shutter.Catalogue.Vocabulary).Load(##class(%File).NormalizeDirectory(root) _ "knowledge/catalogue/vocabulary.json")
        Set vocabulary = ##class(Shutter.Catalogue.Vocabulary).Current()
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Catalogue.SiteEntry WHERE State IN ('active', 'suspended') ORDER BY ID")
        If rs.%SQLCODE < 0 $$$ThrowStatus($$$ERROR($$$GeneralError, "the site entries cannot be listed (SQLCODE " _ rs.%SQLCODE _ ")"))
        While rs.%Next() {
            Set e = ..%OpenId(rs.%Get("ID"))
            If '$ISOBJECT(e) Set complete = 0 Continue
            Set before = e.NeedsReview _ "|" _ e.EffectiveJSON _ "|" _ e.EffectiveScopeJSON _ "|" _ e.ReviewWords()
            Do e.Review(vocabulary, trigger, .widened)
            Set after = e.NeedsReview _ "|" _ e.EffectiveJSON _ "|" _ e.EffectiveScopeJSON _ "|" _ e.ReviewWords()
            If e.NeedsReview Set flagged = flagged + 1
            Continue:(before = after)
            Set level = $TLEVEL
            Try {
                TSTART
                $$$ThrowOnError(e.%Save())
                Set words = $SELECT(e.NeedsReview: "Needs review: " _ e.ReviewWords(), 1: "Rechecked: nothing to review")
                // The generation is raised last, once the row and its event are written: a rolled back transaction does not
                // undo an increment. Every change of the generation holds this lock, so the next value is known here.
                Set raise = widened && (e.State = "active")
                If raise Set words = words _ "; the entry matches more now, so the catalogue generation is " _ (..Generation() + 1)
                $$$ThrowOnError(##class(Shutter.Catalogue.SiteEntryEvent).Record(e.EntryId, e.ActiveVersion, "rechecked", "system", trigger, words))
                If raise Set generation = $INCREMENT(^Shutter.Catalogue.Site("generation"))
                TCOMMIT
            } Catch one {
                While $TLEVEL > level { TROLLBACK 1 }
                Set complete = 0
                Try { Do ##class(%SYS.System).WriteToConsoleLog("Shutter: the recheck of site entry " _ e.EntryId _ " could not be saved: " _ one.DisplayString(), 0, 1) } Catch ex2 { }
            }
        }
    } Catch ex {
        Set complete = 0
        Try { Do ##class(%SYS.System).WriteToConsoleLog("Shutter: the recheck of the site entries failed: " _ ex.DisplayString(), 0, 1) } Catch ex2 { }
    }
    If complete {
        Set ^Shutter.Catalogue.Site("checked") = $PARAMETER("Shutter.Setup", "VERSION"), ok = 1
    } Else {
        Kill ^Shutter.Catalogue.Site("checked")
    }
    Do ..Unlock()
    Quit flagged
}

/// What the last recheck found, in words.
Method ReviewWords() As %String
{
    If ..ReviewJSON = "" Quit ""
    Set r = ##class(Shutter.Util.Json).Parse(..ReviewJSON, .sc), out = ""
    If '$ISOBJECT(r) Quit ""
    For key = "dropped", "notes" {
        Set list = r.%Get(key)
        Continue:'$ISOBJECT(list)
        Set it = list.%GetIterator()
        While it.%GetNext(, .item) {
            If $ISOBJECT(item) {
                Set name = $SELECT(item.%Get("part") = "scope": "the scope's " _ item.condition, 1: item.condition)
                Set out = out _ $SELECT(out = "": "", 1: "; ") _ name _ " dropped (" _ item.why _ ")"
            } Else {
                Set out = out _ $SELECT(out = "": "", 1: "; ") _ item
            }
        }
    }
    Quit out
}

/// This entry checked (R14). A predicate that names a condition or a value the vocabulary no longer knows is dropped
/// whole, and so is a predicate whose value on one of the entry's own matching fixtures reads differently now than when
/// the version was written, and a scope fact (receiver, sending system, ward, reason word) that such a fixture reads
/// differently: the entry then matches more, never less, and is flagged. A matching fixture the entry no longer matches
/// as a whole, a receiver or a team the site profile no longer names, a near miss the entry now matches, and a shipped
/// entry that asks for a person on every case this one matches, are flagged and change nothing.
///
/// What an earlier recheck dropped stays dropped, and the flag stays set, until a new version is approved (Decide clears
/// them): a release that reads a fixture as it did before, or a fixture whose case is no longer stored, never narrows
/// the entry back. Sets NeedsReview, ReviewJSON, EffectiveJSON and EffectiveScopeJSON; <var>widened</var> says whether
/// this check dropped anything more. The caller saves.
Method Review(vocabulary As %DynamicObject, trigger As %String, Output widened As %Boolean) As %Boolean
{
    Set json = "Shutter.Util.Json", vocabularyClass = "Shutter.Catalogue.Vocabulary", matcher = "Shutter.Catalogue.Matcher"
    Set widened = 0
    Set v = ##class(Shutter.Catalogue.SiteEntryVersion).Find(..EntryId, ..ActiveVersion)
    Set content = $SELECT($ISOBJECT(v): v.Content(), 1: "")
    // A row that can't be read is not this method's to mend: the matcher answers error for it (R13).
    If '$ISOBJECT(content) || '$ISOBJECT(content.%Get("pattern")) Quit ..NeedsReview
    Set pattern = ##class(%DynamicObject).%FromJSON(content.%Get("pattern").%ToJSON())
    Set scope = $SELECT($ISOBJECT(content.%Get("scope")): ##class(%DynamicObject).%FromJSON(content.%Get("scope").%ToJSON()), 1: {})
    Set dropped = [], notes = []
    // What earlier rechecks found, carried over: their drops still apply, their notes still stand.
    Set old = $SELECT(..ReviewJSON '= "": $CLASSMETHOD(json, "Parse", ..ReviewJSON, .sc), 1: "")
    If $ISOBJECT(old) && $ISOBJECT(old.%Get("dropped")) {
        Set it = old.%Get("dropped").%GetIterator()
        While it.%GetNext(, .item) {
            Continue:'$ISOBJECT(item)
            Set part = $SELECT(item.%Get("part") = "scope": "scope", 1: "pattern"), name = $CLASSMETHOD(json, "Str", item, "condition")
            Continue:(name = "")||$DATA(seen(part, name))
            Set seen(part, name) = ""
            If part = "scope" { Do scope.%Remove(name) } Else { Do pattern.%Remove(name) }
            Do dropped.%Push(item)
        }
    }
    If $ISOBJECT(old) && $ISOBJECT(old.%Get("notes")) {
        Set it = old.%Get("notes").%GetIterator()
        While it.%GetNext(, .note) { Do ..AddNote(notes, .said, note) }
    }
    // The widened pattern and scope in force, read too, so a drop is kept even if the review's words were lost.
    For part = "pattern", "scope" {
        Set text = $SELECT(part = "pattern": ..EffectiveJSON, 1: ..EffectiveScopeJSON)
        Continue:text=""
        Set effective = $CLASSMETHOD(json, "Parse", text, .sc)
        Continue:'$ISOBJECT(effective)
        Set mine = $SELECT(part = "pattern": pattern, 1: scope), names = "", it = mine.%GetIterator()
        While it.%GetNext(.name) { Set names = names _ $LISTBUILD(name) }
        For i = 1:1:$LISTLENGTH(names) {
            Set name = $LIST(names, i)
            Continue:effective.%IsDefined(name)
            Do mine.%Remove(name)
            Set seen(part, name) = ""
            Do dropped.%Push({"condition": (name), "part": (part), "why": "an earlier recheck dropped it"})
        }
    }
    Set carried = dropped.%Size()
    If '$ISOBJECT(vocabulary) {
        Do ..AddNote(notes, .said, "No condition vocabulary is installed, so the pattern's words were not checked")
    } Else {
        Set it = content.%Get("pattern").%GetIterator()
        While it.%GetNext(.condition, .values) {
            Continue:'pattern.%IsDefined(condition)
            Set allowed = $CLASSMETHOD(vocabularyClass, "ValuesOf", vocabulary, condition)
            If '$ISOBJECT(allowed) Do pattern.%Remove(condition), dropped.%Push({"condition": (condition), "part": "pattern", "why": "this release's vocabulary has no such condition"}) Continue
            Set vi = values.%GetIterator()
            While vi.%GetNext(, .word) {
                If '$CLASSMETHOD(vocabularyClass, "In", allowed, word) Do pattern.%Remove(condition), dropped.%Push({"condition": (condition), "part": "pattern", "why": ("this release's vocabulary has no value " _ word _ " for it")}) Quit
            }
        }
    }
    Set fixtures = content.%Get("fixtures")
    If $ISOBJECT(fixtures) {
        Set fi = fixtures.%GetIterator()
        While fi.%GetNext(, .f) {
            Set caseId = $CLASSMETHOD(json, "Str", f, "case"), expect = $CLASSMETHOD(json, "Str", f, "expect")
            Set now = ##class(Shutter.Catalogue.SiteEntryProof).Replay(f, .source)
            If source = "frozen" Do ..AddNote(notes, .said, "Case " _ caseId _ " is no longer stored, so its evidence was not read again: only the vocabulary was checked for it") Continue
            If expect = "match" {
                Set frozen = f.%Get("conditions")
                If $ISOBJECT(frozen) {
                    Set names = "", pi = pattern.%GetIterator()
                    While pi.%GetNext(.condition) { Set names = names _ $LISTBUILD(condition) }
                    For i = 1:1:$LISTLENGTH(names) {
                        Set condition = $LIST(names, i)
                        Set was = $CLASSMETHOD(json, "Str", frozen, condition), is = $CLASSMETHOD(json, "Str", now.conditions, condition)
                        If was '= is Do pattern.%Remove(condition), dropped.%Push({"condition": (condition), "part": "pattern", "why": ("case " _ caseId _ " read " _ was _ " when the version was written and reads " _ $SELECT(is = "": "nothing", 1: is) _ " under this release")})
                    }
                }
                // The scope facts the entry names, as the fixture read them when it was frozen and as they read now.
                Set frozenScope = f.%Get("scope")
                If $ISOBJECT(frozenScope) {
                    Set names = "", si = scope.%GetIterator()
                    While si.%GetNext(.name) { Set names = names _ $LISTBUILD(name) }
                    For i = 1:1:$LISTLENGTH(names) {
                        Set name = $LIST(names, i)
                        Set was = $CLASSMETHOD(json, "Str", frozenScope, name), is = $CLASSMETHOD(json, "Str", now.scope, name)
                        If name = "reason_code" Set was = $ZCONVERT(was, "L"), is = $ZCONVERT(is, "L")
                        If was '= is Do scope.%Remove(name), dropped.%Push({"condition": (name), "part": "scope", "why": ("case " _ caseId _ " read " _ $SELECT(was = "": "nothing", 1: was) _ " when the version was written and reads " _ $SELECT(is = "": "nothing", 1: is) _ " under this release")})
                    }
                }
                // And the fixture as a whole: the entry, as it now stands, must still match the case it was approved on.
                If '($CLASSMETHOD(matcher, "ScopeHolds", scope, now.scope) && $CLASSMETHOD(matcher, "SiteHolds", pattern, now.conditions)) Do ..AddNote(notes, .said, "The entry no longer matches case " _ caseId _ ", which it was approved to match")
            } ElseIf $CLASSMETHOD(matcher, "ScopeHolds", scope, now.scope) && $CLASSMETHOD(matcher, "SiteHolds", pattern, now.conditions) {
                Do ..AddNote(notes, .said, "The entry now matches case " _ caseId _ ", which it was approved to leave alone")
            }
        }
    }
    // The site profile: a receiver or a team it no longer names silently disables that part of the entry.
    Set receivers = scope.%Get("receiver")
    If $ISOBJECT(receivers) {
        Set ri = receivers.%GetIterator()
        While ri.%GetNext(, .name) { If '$ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver(name)) Do ..AddNote(notes, .said, "The site profile no longer names the receiver " _ name _ ", so the entry matches no case of it") }
    }
    Set team = $CLASSMETHOD(json, "Str", content, "team")
    If (team '= "") && '##class(Shutter.Catalogue.SiteEntryVersion).TeamKnown(team) Do ..AddNote(notes, .said, "The site profile no longer names the team " _ team)
    Set oi = ##class(Shutter.Catalogue.SiteEntryVersion).Overlap(content.%Get("pattern")).%GetIterator()
    While oi.%GetNext(, .row) {
        If row.covers && (row.decides = "person") && 'row.leads Do ..AddNote(notes, .said, "The shipped entry " _ row.id _ " asks for a person on every case this pattern matches")
    }
    // The first note, of a vocabulary that is not installed, and a fixture no longer stored, flag nothing by themselves;
    // a flag once set stays until a new version is approved.
    Set flag = (dropped.%Size() > 0) || ..NeedsReview, ni = notes.%GetIterator()
    While ni.%GetNext(, .note) { If (note '[ "is no longer stored") && (note '[ "No condition vocabulary") Set flag = 1 }
    Set widened = (dropped.%Size() > carried)
    Set ..NeedsReview = flag
    Set anyPattern = 0, anyScope = 0, di = dropped.%GetIterator()
    While di.%GetNext(, .item) { If item.%Get("part") = "scope" { Set anyScope = 1 } Else { Set anyPattern = 1 } }
    Set ..EffectiveJSON = $SELECT(anyPattern: pattern.%ToJSON(), 1: "")
    Set ..EffectiveScopeJSON = $SELECT(anyScope: scope.%ToJSON(), 1: "")
    If (dropped.%Size() = 0) && (notes.%Size() = 0) {
        Set ..ReviewJSON = ""
    } Else {
        Set review = {}
        Set review.dropped = dropped, review.notes = notes, review.trigger = trigger, review.release = $PARAMETER("Shutter.Setup", "VERSION")
        Set ..ReviewJSON = review.%ToJSON()
    }
    Quit flag
}

/// A note added once.
ClassMethod AddNote(notes As %DynamicArray, ByRef said, note As %String) [ Private ]
{
    Set key = $EXTRACT(note, 1, 200) _ "|" _ $ZCRC(note, 7)
    If $DATA(said(key)) Quit
    Set said(key) = ""
    Do notes.%Push(note)
}

// ---- removal ----

/// Every site entry, version, proof and event removed, with the generation, the id counter and the two-person lift: the
/// uninstall's step, after it has named them (Shutter.Util.Uninstall), and the unit tests' way back to an instance that
/// never had one. It is not a route and not an SQL procedure, and it needs %Admin_Manage: there is no switch that turns
/// every site entry off together (R11).
ClassMethod RemoveAll() As %Status
{
    If '$SYSTEM.Security.Check("%Admin_Manage", "USE") Quit $$$ERROR($$$GeneralError, "%Admin_Manage is required to remove the site's entries")
    Set sc = $$$OK
    For class = "Shutter.Catalogue.SiteEntryEvent", "Shutter.Catalogue.SiteEntryProof", "Shutter.Catalogue.SiteEntryVersion", "Shutter.Catalogue.SiteEntry" {
        Set one = $CLASSMETHOD(class, "%KillExtent")
        If $$$ISERR(one) Set sc = one
    }
    Kill ^Shutter.Catalogue.Site
    Quit sc
}

/// The entries in one line, for the uninstall's plan.
ClassMethod CountLine() As %String
{
    Set n = 0, active = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Catalogue.SiteEntry)
    &sql(SELECT COUNT(*) INTO :active FROM Shutter_Catalogue.SiteEntry WHERE State = 'active')
    Quit "The site's own catalogue entries (Shutter.Catalogue.SiteEntry): " _ (+n) _ " in all, " _ (+active) _ " active, with their versions, proofs and events"
}

Storage Default
{
<Data name="SiteEntryDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>EntryId</Value>
</Value>
<Value name="3">
<Value>State</Value>
</Value>
<Value name="4">
<Value>ActiveVersion</Value>
</Value>
<Value name="5">
<Value>DraftVersion</Value>
</Value>
<Value name="6">
<Value>Priority</Value>
</Value>
<Value name="7">
<Value>ProposalAction</Value>
</Value>
<Value name="8">
<Value>ProposalVersion</Value>
</Value>
<Value name="9">
<Value>ProposalDigest</Value>
</Value>
<Value name="10">
<Value>ProposalBy</Value>
</Value>
<Value name="11">
<Value>ProposalAt</Value>
</Value>
<Value name="12">
<Value>ProposalProofId</Value>
</Value>
<Value name="13">
<Value>NeedsReview</Value>
</Value>
<Value name="14">
<Value>ReviewJSON</Value>
</Value>
<Value name="15">
<Value>EffectiveJSON</Value>
</Value>
<Value name="16">
<Value>SuspendedBy</Value>
</Value>
<Value name="17">
<Value>SuspendedAt</Value>
</Value>
<Value name="18">
<Value>SuspendedReason</Value>
</Value>
<Value name="19">
<Value>Revision</Value>
</Value>
<Value name="20">
<Value>CreatedBy</Value>
</Value>
<Value name="21">
<Value>CreatedAt</Value>
</Value>
<Value name="22">
<Value>UpdatedAt</Value>
</Value>
<Value name="23">
<Value>EffectiveScopeJSON</Value>
</Value>
</Data>
<DataLocation>^Shutter.Catalogue.SiteEntryD</DataLocation>
<DefaultData>SiteEntryDefaultData</DefaultData>
<IdLocation>^Shutter.Catalogue.SiteEntryD</IdLocation>
<IndexLocation>^Shutter.Catalogue.SiteEntryI</IndexLocation>
<StreamLocation>^Shutter.Catalogue.SiteEntryS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
