/// One version of a site's own entry (CONTRACTS 6.8): its content as canonical JSON, the digest an approver reads, who
/// wrote it and who approved it. A draft is rewritten until it is proposed; an approved version is never changed. The
/// class also holds what is true of a version's content alone: the rules R1 to R5 and R15, the sentence that says it in
/// plain words, and the report of the shipped entries it can displace.
Class Shutter.Catalogue.SiteEntryVersion Extends (%Persistent, %JSON.Adaptor)
{

Property EntryId As %String(%JSONFIELDNAME = "id", MAXLEN = 16) [ Required ];

Property Version As %Integer(%JSONFIELDNAME = "version") [ Required ];

Index EntryVersionIdx On (EntryId, Version) [ Unique ];

/// draft or approved.
Property Status As %String(%JSONFIELDNAME = "status", MAXLEN = 16) [ InitialExpression = "draft" ];

/// The content, canonical JSON (Shutter.Util.Digest.Canonical): id, kind, title, priority, scope, pattern, why, team,
/// instructions, prose and fixtures.
Property Json As %String(%JSONINCLUDE = "none", MAXLEN = "");

/// SHA-256 of Json.
Property Digest As %String(%JSONFIELDNAME = "digest", MAXLEN = 80);

Property WrittenBy As %String(%JSONFIELDNAME = "writtenBy", MAXLEN = 160);

Property WrittenAt As %String(%JSONFIELDNAME = "writtenAt", MAXLEN = 30);

Property ApprovedBy As %String(%JSONFIELDNAME = "approvedBy", MAXLEN = 160);

Property ApprovedAt As %String(%JSONFIELDNAME = "approvedAt", MAXLEN = 30);

/// The approver's reason.
Property Reason As %String(%JSONFIELDNAME = "reason", MAXLEN = 1000);

/// The trust's own safety record for the change (a hazard log entry, say): stored, and nothing is checked.
Property SafetyReference As %String(%JSONFIELDNAME = "safetyReference", MAXLEN = 300);

/// The proof the version was activated on (Shutter.Catalogue.SiteEntryProof).
Property ProofId As %String(%JSONFIELDNAME = "proofId", MAXLEN = 20);

/// The release that approved it.
Property Release As %String(%JSONFIELDNAME = "release", MAXLEN = 32);

Parameter MAXTITLE = 200;

Parameter MAXWHY = 500;

Parameter MAXINSTRUCTIONS = 2000;

Parameter MAXPROSE = 4000;

/// At most this many site entries are active at once (R15), so the catalogue's version stays within a plan's field.
Parameter MAXACTIVE = 50;

Parameter MAXFIXTURES = 20;

ClassMethod Find(entryId As %String, version As %Integer) As Shutter.Catalogue.SiteEntryVersion
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Shutter_Catalogue.SiteEntryVersion WHERE EntryId = :entryId AND Version = :version)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// The content, parsed; "" when the row's JSON cannot be read (a damaged row).
Method Content() As %DynamicObject
{
    If ..Json = "" Quit ""
    Set o = ##class(Shutter.Util.Json).Parse(..Json, .sc)
    If '$ISOBJECT(o) || $$$ISERR(sc) || 'o.%IsA("%Library.DynamicObject") Quit ""
    Quit o
}

/// The row with its content, for the API.
Method ToObject() As %DynamicObject
{
    Set o = ##class(Shutter.Util.Json).Project($THIS)
    Set content = ..Content()
    If $ISOBJECT(content) {
        Set o.content = content
        Set o.sentence = ..Sentence(content)
    }
    Quit o
}

/// The digest of a content object.
ClassMethod DigestOf(content As %DynamicObject) As %String
{
    Quit ##class(Shutter.Util.Digest).OfObject(content)
}

/// A body checked against R1 to R5 and R15 and brought to the stored form. <var>content</var> is that form when no
/// problem was found: {id, kind, title, priority, scope, pattern, why, team, instructions, prose, fixtures}, the scope's
/// and the pattern's values as lists, the words cleaned as stored model text is, and each fixture frozen
/// (Shutter.Catalogue.SiteEntryProof.Freeze). <var>problems</var> and <var>warnings</var> are arrays of {rule, field,
/// text}. Nothing is stored. <var>entryId</var> is the id the content takes; <var>freeze</var> 0 leaves the fixtures
/// as {case, expect} (the validate route, which reads no evidence).
ClassMethod Normalise(body As %DynamicObject, entryId As %String, Output content As %DynamicObject, Output problems As %DynamicArray, Output warnings As %DynamicArray, freeze As %Boolean = 1)
{
    Set json = "Shutter.Util.Json", vocabularyClass = "Shutter.Catalogue.Vocabulary"
    Set content = {}, problems = [], warnings = []
    If '$ISOBJECT(body) || 'body.%IsA("%Library.DynamicObject") {
        Do ..Add(problems, "R1", "", "The body must be a site entry as a JSON object")
        Quit
    }
    Set vocabulary = $CLASSMETHOD(vocabularyClass, "Current")
    If '$ISOBJECT(vocabulary) Do ..Add(problems, "R3", "pattern", "No condition vocabulary is installed here (knowledge/catalogue/vocabulary.json), so no pattern can be checked")
    // No field sets who decides or the outcome: a body that carries one is refused, not ignored (R1).
    Set known = $LISTBUILD("id", "version", "kind", "title", "priority", "scope", "pattern", "why", "team", "instructions", "prose", "fixtures")
    Set it = body.%GetIterator()
    While it.%GetNext(.key) {
        If $LISTFIND($LISTBUILD("decides", "preferred", "alternatives", "checks", "outcome", "scenarios", "origin"), key) {
            Do ..Add(problems, "R1", key, "A site entry has no """ _ key _ """: it sends a case to a person and nothing else, so who decides and the outcome are not fields")
        } ElseIf '$LISTFIND(known, key) {
            Do ..Add(problems, "R1", key, "A site entry has no field """ _ key _ """")
        }
    }
    If body.%IsDefined("id") && (entryId '= "") && ($CLASSMETHOD(json, "Str", body, "id") '= entryId) Do ..Add(problems, "R1", "id", "The id is given by Shutter (" _ entryId _ ") and cannot be changed")
    Set content.id = entryId
    Set kind = $CLASSMETHOD(json, "Str", body, "kind", "stop")
    If '$CLASSMETHOD(vocabularyClass, "In", $CLASSMETHOD(vocabularyClass, "SiteList", vocabulary, "kinds"), kind) Do ..Add(problems, "R1", "kind", "The only kind is stop: " _ $EXTRACT(kind, 1, 40) _ " is not one")
    Set content.kind = "stop"
    // The words (R5).
    For field = "title", "why", "instructions", "prose" {
        Set max = $CASE(field, "title": ..#MAXTITLE, "why": ..#MAXWHY, "instructions": ..#MAXINSTRUCTIONS, : ..#MAXPROSE)
        Set type = body.%GetTypeOf(field)
        If (type '= "unassigned") && (type '= "string") && (type '= "null") Do ..Add(problems, "R5", field, "The " _ field _ " must be plain text") Do content.%Set(field, "") Continue
        Set text = $ZSTRIP(##class(Shutter.Util.ModelView).Clean($CLASSMETHOD(json, "Str", body, field)), "<>W")
        If $LENGTH(text) > max Do ..Add(problems, "R5", field, "The " _ field _ " is " _ $LENGTH(text) _ " characters; at most " _ max)
        If ((field = "title") || (field = "why")) && (text = "") Do ..Add(problems, "R5", field, "The " _ field _ " is required")
        Do ..Digits(text, field, problems, warnings)
        Do content.%Set(field, text)
    }
    If content.instructions = "" Do ..Add(warnings, "R5", "instructions", "No instructions: the person the case goes to is told only why")
    // The priority: among site entries that match the same case, whose words lead.
    Set priority = 100
    If body.%IsDefined("priority") {
        Set priority = body.%Get("priority")
        If (body.%GetTypeOf("priority") '= "number") || (priority '= (priority \ 1)) || (priority < 1) || (priority > 999) Do ..Add(problems, "R1", "priority", "The priority is a whole number from 1 to 999") Set priority = 100
    }
    Do content.%Set("priority", +priority, "number")
    // The scope (R4): facts of the case fixed when it opens, each one listed must hold.
    Set scope = {}, scopeKeys = $CLASSMETHOD(vocabularyClass, "SiteList", vocabulary, "scope")
    Set given = body.%Get("scope")
    If body.%IsDefined("scope") && (body.%GetTypeOf("scope") '= "null") {
        If '$ISOBJECT(given) || 'given.%IsA("%Library.DynamicObject") {
            Do ..Add(problems, "R4", "scope", "The scope is a map of facts to the values allowed")
        } Else {
            Set si = given.%GetIterator()
            While si.%GetNext(.fact, .value) {
                If '$CLASSMETHOD(vocabularyClass, "In", scopeKeys, fact) Do ..Add(problems, "R4", "scope." _ fact, "The scope names only receiver, source_system, ward and reason_code") Continue
                Set list = ..AsList(value, .bad)
                If bad || (list.%Size() = 0) || (list.%Size() > 20) Do ..Add(problems, "R4", "scope." _ fact, "The scope's " _ fact _ " is one value or a list of 1 to 20 values, each a word of at most 100 characters") Continue
                If fact = "receiver" {
                    Set li = list.%GetIterator()
                    While li.%GetNext(, .name) { If '$ISOBJECT(##class(Shutter.Store.SiteProfile).Receiver(name)) Do ..Add(problems, "R4", "scope.receiver", "The site profile names no receiver " _ name) }
                }
                Do scope.%Set(fact, list)
            }
        }
    }
    Set content.scope = scope
    Set team = $ZSTRIP($CLASSMETHOD(json, "Str", body, "team"), "<>W")
    If (team '= "") && '..TeamKnown(team) Do ..Add(problems, "R4", "team", "The site profile names no team " _ $EXTRACT(team, 1, 60))
    Set content.team = team
    // The pattern (R3): the vocabulary's conditions and values and nothing else, at least one condition.
    Set pattern = {}
    Set given = body.%Get("pattern")
    If '$ISOBJECT(given) || 'given.%IsA("%Library.DynamicObject") || (given.%Size() = 0) {
        Do ..Add(problems, "R3", "pattern", "The pattern names at least one condition")
    } ElseIf $ISOBJECT(vocabulary) {
        Set reserved = $CLASSMETHOD(vocabularyClass, "SiteList", vocabulary, "reserved_conditions")
        Set pi = given.%GetIterator()
        While pi.%GetNext(.condition, .value) {
            If $CLASSMETHOD(vocabularyClass, "In", reserved, condition) Do ..Add(problems, "R3", "pattern." _ condition, "A site entry cannot name " _ condition _ ": the shipped entry for it answers first, whatever a site entry says") Continue
            Set allowed = $CLASSMETHOD(vocabularyClass, "ValuesOf", vocabulary, condition)
            If '$ISOBJECT(allowed) Do ..Add(problems, "R3", "pattern." _ condition, condition _ " is not a condition of the vocabulary (CONTRACTS 6.1)") Continue
            Set list = ..AsList(value, .bad)
            If bad || (list.%Size() = 0) Do ..Add(problems, "R3", "pattern." _ condition, condition _ " takes one value or a list of values") Continue
            Set li = list.%GetIterator(), fine = 1
            While li.%GetNext(, .word) {
                If '$CLASSMETHOD(vocabularyClass, "In", allowed, word) Set fine = 0 Do ..Add(problems, "R3", "pattern." _ condition, condition _ " cannot be " _ $EXTRACT(word, 1, 40) _ " (allowed: " _ ..Words(allowed, ", ", ", ") _ ")")
            }
            If fine Do pattern.%Set(condition, list)
        }
    }
    Set content.pattern = pattern
    // The fixtures: stored cases of this site's own, each expected to match or to be left alone.
    Set fixtures = []
    Set given = body.%Get("fixtures")
    If body.%IsDefined("fixtures") && (body.%GetTypeOf("fixtures") '= "null") {
        If '$ISOBJECT(given) || 'given.%IsA("%Library.DynamicArray") {
            Do ..Add(problems, "R1", "fixtures", "The fixtures are a list of {case, expect}")
        } ElseIf given.%Size() > ..#MAXFIXTURES {
            Do ..Add(problems, "R1", "fixtures", "At most " _ ..#MAXFIXTURES _ " fixtures")
        } Else {
            Set fi = given.%GetIterator()
            While fi.%GetNext(.n, .f) {
                Set caseId = $SELECT($ISOBJECT(f): $CLASSMETHOD(json, "Str", f, "case"), 1: ""), expect = $SELECT($ISOBJECT(f): $CLASSMETHOD(json, "Str", f, "expect"), 1: "")
                If (caseId = "") || ((expect '= "match") && (expect '= "no_match")) Do ..Add(problems, "R1", "fixtures", "Fixture " _ (n + 1) _ " needs a case and expect: match or no_match") Continue
                If $DATA(seen(caseId)) Do ..Add(problems, "R1", "fixtures", "Case " _ caseId _ " is listed twice") Continue
                Set seen(caseId) = 1
                If 'freeze Do fixtures.%Push({"case": (caseId), "expect": (expect)}) Continue
                Set frozen = ##class(Shutter.Catalogue.SiteEntryProof).Freeze(caseId, expect, .why)
                If '$ISOBJECT(frozen) Do ..Add(problems, "R1", "fixtures", "Fixture " _ (n + 1) _ ": " _ why) Continue
                Do fixtures.%Push(frozen)
            }
        }
    }
    Set content.fixtures = fixtures
    // R15: one more active entry than the limit is refused at activation; said here so nobody proves one for nothing.
    If ##class(Shutter.Catalogue.SiteEntry).ActiveCount(entryId) >= ..#MAXACTIVE Do ..Add(problems, "R15", "", ..#MAXACTIVE _ " site entries are active already, the most a site may have: retire one first")
}

/// A value, or a list of values, as a list of trimmed words; bad when anything in it is not a word of 1 to 100 characters.
ClassMethod AsList(value, Output bad As %Boolean) As %DynamicArray [ Private ]
{
    Set bad = 0, out = []
    If $ISOBJECT(value) {
        If 'value.%IsA("%Library.DynamicArray") Set bad = 1 Quit out
        Set it = value.%GetIterator()
        While it.%GetNext(.i, .v) {
            If $ISOBJECT(v) || (value.%GetTypeOf(i) = "null") Set bad = 1 Continue
            Set word = $ZSTRIP("" _ v, "<>W")
            If (word = "") || ($LENGTH(word) > 100) || ##class(Shutter.Catalogue.Vocabulary).In(out, word) Set bad = 1 Continue
            Do out.%Push(word)
        }
        Quit out
    }
    Set word = $ZSTRIP("" _ value, "<>W")
    If (word = "") || ($LENGTH(word) > 100) Set bad = 1 Quit out
    Do out.%Push(word)
    Quit out
}

ClassMethod Add(list As %DynamicArray, rule As %String, field As %String, text As %String) [ Private ]
{
    Set o = {}
    Set o.rule = rule, o.field = field, o.text = text
    Do list.%Push(o)
}

/// Whether the site profile names a team of this id.
ClassMethod TeamKnown(team As %String) As %Boolean
{
    Set it = ##class(Shutter.Store.SiteProfile).Teams().%GetIterator()
    While it.%GetNext(, .t) { If $ISOBJECT(t) && (##class(Shutter.Util.Json).Str(t, "id") = team) Return 1 }
    Quit 0
}

/// The digit runs of a text (R5), read as Set up the site's text rule reads a long number (ProfileSetup.TextProblem):
/// every Unicode space as a space and every dash as a hyphen (ProfileSetup.Spaces), and up to three spaces, hyphens,
/// dots or brackets between digits read as one number. A valid NHS number is a problem, since the words can reach a
/// model; any other run of six or more digits is a warning.
ClassMethod Digits(text As %String, field As %String, problems As %DynamicArray, warnings As %DynamicArray) [ Private ]
{
    Set text = ##class(Shutter.Util.ProfileSetup).Spaces(text)
    Set run = "", warned = 0, refused = 0, i = 0
    While i <= $LENGTH(text) {
        Set i = i + 1, c = $EXTRACT(text, i)
        If c ? 1N Set run = run _ c Continue
        // Up to three separators inside a number, as an NHS or telephone number is often written: 943 476 5919,
        // 943.476.5919, (020) 7946 0958, 943 - 476 - 5919.
        If run '= "" {
            Set j = i
            While (j < (i + 3)) && (" ().-" [ $EXTRACT(text, j + 1)) && ($EXTRACT(text, j + 1) '= "") { Set j = j + 1 }
            If (" ().-" [ c) && ($EXTRACT(text, j + 1) ? 1N) Set i = j Continue
        }
        If $LENGTH(run) >= 10 {
            For at = 1:1:($LENGTH(run) - 9) {
                If ##class(Shutter.Util.CaseReminder).LooksLikeNHSNumber($EXTRACT(run, at, at + 9)) Set refused = 1 Quit
            }
        }
        If ($LENGTH(run) >= 6) Set warned = 1
        Set run = ""
    }
    If refused Do ..Add(problems, "R5", field, "The " _ field _ " holds a valid NHS number: the words of an entry can reach a model, so no patient is named in them") Quit
    If warned Do ..Add(warnings, "R5", field, "The " _ field _ " holds a run of six or more digits: check it identifies no patient")
}

/// A list's words joined: "a, b or c" with sep ", " and last " or ".
ClassMethod Words(list As %DynamicArray, sep As %String = ", ", last As %String = " or ") As %String
{
    Set out = "", n = $SELECT($ISOBJECT(list): list.%Size(), 1: 0)
    For i = 0:1:(n - 1) { Set out = out _ $SELECT(i = 0: "", i = (n - 1): last, 1: sep) _ list.%Get(i) }
    Quit out
}

/// The entry in one sentence, for a person: "When a transfer to Downstream Out from PAS fails, is rejected or gets no
/// answer, and the ward is WARD-ISO: a person decides."
ClassMethod Sentence(content As %DynamicObject) As %String
{
    If '$ISOBJECT(content) Quit ""
    Set pattern = content.%Get("pattern"), scope = content.%Get("scope")
    If '$ISOBJECT(pattern) Set pattern = {}
    If '$ISOBJECT(scope) Set scope = {}
    Set events = pattern.%Get("event")
    Set what = "a message"
    If $ISOBJECT(events) && (events.%Size() > 0) {
        Set named = [], it = events.%GetIterator()
        While it.%GetNext(, .e) { Do named.%Push($CASE(e, "admit": "an admission", "update": "an update", "other": "another kind of message", : "a " _ e)) }
        Set what = ..Words(named)
    }
    Set text = "When " _ what
    If $ISOBJECT(scope.%Get("receiver")) Set text = text _ " to " _ ..Words(scope.%Get("receiver"))
    If $ISOBJECT(scope.%Get("source_system")) Set text = text _ " from " _ ..Words(scope.%Get("source_system"))
    Set delivery = pattern.%Get("delivery")
    If $ISOBJECT(delivery) && (delivery.%Size() > 0) {
        Set verbs = [], it = delivery.%GetIterator()
        While it.%GetNext(, .d) { Do verbs.%Push($CASE(d, "failed": "fails", "rejected": "is rejected", "uncertain": "gets no answer", "unmappable": "cannot be mapped", "withheld": "is withheld", "unreadable": "is held unread", : d)) }
        Set text = text _ " " _ ..Words(verbs)
    } Else {
        Set text = text _ " is not delivered"
    }
    Set it = pattern.%GetIterator()
    While it.%GetNext(.condition, .values) {
        Continue:((condition = "event") || (condition = "delivery"))
        Set text = text _ ", and " _ $TRANSLATE(condition, "_", " ") _ " is " _ ..Words(values)
    }
    If $ISOBJECT(scope.%Get("ward")) Set text = text _ ", and the ward is " _ ..Words(scope.%Get("ward"))
    If $ISOBJECT(scope.%Get("reason_code")) Set text = text _ ", and the receiver's reason is " _ ..Words(scope.%Get("reason_code"))
    Quit text _ ": a person decides"
}

/// The shipped entries a pattern can displace, decided condition by condition: an entry is listed when, for every
/// condition both name, they share a value (a condition only one names leaves it open). Each row is {id, title, decides,
/// outcome, conditions: [{condition, site, shipped, shared}], covers} where covers says every case the site entry
/// matches the shipped one matches too (the scope aside), and leads is true for the entry that answers before any site
/// entry (a death on the message).
ClassMethod Overlap(pattern As %DynamicObject) As %DynamicArray
{
    Set out = [], json = "Shutter.Util.Json"
    If '$ISOBJECT(pattern) Quit out
    Set it = ##class(Shutter.Catalogue.Entry).All().%GetIterator()
    While it.%GetNext(, .e) {
        Set shipped = e.%Get("pattern")
        Continue:'$ISOBJECT(shipped)
        Set rows = [], compatible = 1, covers = 1
        Set si = shipped.%GetIterator()
        While si.%GetNext(.condition, .allowed) {
            Set theirs = ..AsList(allowed, .bad)
            If pattern.%GetTypeOf(condition) '= "array" Set covers = 0 Continue
            Set mine = pattern.%Get(condition), shared = [], mi = mine.%GetIterator()
            While mi.%GetNext(, .word) { If ##class(Shutter.Catalogue.Vocabulary).In(theirs, word) { Do shared.%Push(word) } Else { Set covers = 0 } }
            If shared.%Size() = 0 Set compatible = 0
            Do rows.%Push({"condition": (condition), "site": (mine), "shipped": (theirs), "shared": (shared)})
        }
        Continue:'compatible
        Set row = {}
        Set row.id = e.id, row.title = e.title, row.decides = e.decides
        Set row.outcome = $CLASSMETHOD(json, "Str", e.%Get("preferred"), "outcome"), row.conditions = rows
        Do row.%Set("covers", covers, "boolean")
        Do row.%Set("leads", shipped.%IsDefined("death_recorded"), "boolean")
        Do out.%Push(row)
    }
    Quit out
}

Storage Default
{
<Data name="SiteEntryVersionDefaultData">
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
<Value>Status</Value>
</Value>
<Value name="5">
<Value>Json</Value>
</Value>
<Value name="6">
<Value>Digest</Value>
</Value>
<Value name="7">
<Value>WrittenBy</Value>
</Value>
<Value name="8">
<Value>WrittenAt</Value>
</Value>
<Value name="9">
<Value>ApprovedBy</Value>
</Value>
<Value name="10">
<Value>ApprovedAt</Value>
</Value>
<Value name="11">
<Value>Reason</Value>
</Value>
<Value name="12">
<Value>SafetyReference</Value>
</Value>
<Value name="13">
<Value>ProofId</Value>
</Value>
<Value name="14">
<Value>Release</Value>
</Value>
</Data>
<DataLocation>^Shutter.Ca5ADA.SiteEntryVe8572D</DataLocation>
<DefaultData>SiteEntryVersionDefaultData</DefaultData>
<IdLocation>^Shutter.Ca5ADA.SiteEntryVe8572D</IdLocation>
<IndexLocation>^Shutter.Ca5ADA.SiteEntryVe8572I</IndexLocation>
<StreamLocation>^Shutter.Ca5ADA.SiteEntryVe8572S</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
