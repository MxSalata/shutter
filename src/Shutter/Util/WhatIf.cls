/// What a case's outcome turned on in the site profile, and what the case would have done under the catalogue's
/// alternatives (CONTRACTS 14, v1.26): deterministic, from the case's snapshot and the profile alone, with no model. For
/// the matched entry, each alternative whose when names a profile flag becomes a fact: the setting it reads (for the
/// case's receiver when the flag is the receiver's), its current value, the value that would make the alternative hold,
/// the alternative's outcome and the disposition the gate maps it to, whether it holds now (then it is the setting behind
/// the outcome), and a typed suggested change validated against the profile schema. The tier's approval policy is a
/// fact too when the case wrote. The facts are what the case chat's agents may name, and nothing else.
Class Shutter.Util.WhatIf
{

/// {case_id, receiver, category, entry, outcome, outcome_ref, disposition, profile_version, facts: [..], note}.
ClassMethod ForCase(case As Shutter.Store.Case) As %DynamicObject
{
    Set json = "Shutter.Util.Json"
    Set out = {}
    Set out."case_id" = case.CaseId, out.receiver = case.Receiver
    Set out.category = ##class(Shutter.Store.SiteProfile).ReceiverCategory(case.Receiver)
    Set profile = ##class(Shutter.Store.SiteProfile).Current()
    Set out."profile_version" = +$CLASSMETHOD(json, "Str", profile, "version", 0)
    Set summary = $SELECT($ISOBJECT(case.CurrentSnapshot): case.CurrentSnapshot.SummaryObject(), 1: "")
    Set cat = $SELECT($ISOBJECT(summary): summary.%Get("catalogue"), 1: "")
    Set plan = case.CurrentPlan
    Set entry = $SELECT($ISOBJECT(plan) && (plan.CatalogueEntry '= ""): plan.CatalogueEntry, $ISOBJECT(cat): $CLASSMETHOD(json, "Str", cat, "entry"), 1: "")
    Set out.entry = entry
    Set out.disposition = $SELECT($ISOBJECT(plan): plan.Disposition, 1: "")
    Set out."outcome_ref" = $SELECT($ISOBJECT(plan) && (plan.Outcome '= ""): plan.Outcome, $ISOBJECT(cat): $CLASSMETHOD(json, "Str", cat, "outcome_ref", "preferred"), 1: "")
    Set facts = [], n = 0
    Set match = ..MatchFor(cat, entry)
    Set facts0 = $SELECT($ISOBJECT(cat) && $ISOBJECT(cat.%Get("facts")): cat.%Get("facts"), 1: {})
    If $ISOBJECT(match) {
        Set pref = match.%Get("preferred")
        Set out.outcome = ..ChosenOutcome(match, out."outcome_ref")
        Set alts = match.%Get("alternatives")
        If $ISOBJECT(alts) {
            Set ai = alts.%GetIterator()
            While ai.%GetNext(.i, .alt) {
                Continue:'$ISOBJECT(alt)
                Set when = $ZSTRIP($CLASSMETHOD(json, "Str", alt, "when"), "<>W")
                Continue:((when = "") || (when = "always") || (when '[ ":"))
                Set f = ..FlagFact(case, profile, facts0, alt, when, i + 1, out.disposition, out."outcome_ref")
                If $ISOBJECT(f) Set n = n + 1, f.id = "W" _ n Do facts.%Push(f)
            }
        }
    } Else {
        Set out.outcome = ""
    }
    // The tier's approval policy, when the case wrote or was to write: one step stricter.
    Set p = ..PolicyFact(case, profile, summary, out.disposition)
    If $ISOBJECT(p) Set n = n + 1, p.id = "W" _ n Do facts.%Push(p)
    Set out.facts = facts
    Set out.note = $SELECT(n = 0: "No profile setting bears on this case's outcome", 1: n _ " setting" _ $SELECT(n = 1: "", 1: "s") _ " bear" _ $SELECT(n = 1: "s", 1: "") _ " on this case; a change is a draft for the Site profile page, which an approver saves")
    Quit out
}

/// The matched entry's row in the snapshot's matches, by id, else the single match.
ClassMethod MatchFor(cat As %DynamicObject, entry As %String) As %DynamicObject [ Private ]
{
    If '$ISOBJECT(cat) || '$ISOBJECT(cat.%Get("matches")) Quit ""
    Set matches = cat.%Get("matches"), mi = matches.%GetIterator()
    While mi.%GetNext(, .m) { If $ISOBJECT(m) && (##class(Shutter.Util.Json).Str(m, "id") = entry) Return m }
    If (matches.%Size() = 1) && $ISOBJECT(matches.%Get(0)) Quit matches.%Get(0)
    Quit ""
}

/// The outcome the plan followed: the preferred one or alternative n.
ClassMethod ChosenOutcome(match As %DynamicObject, ref As %String) As %String [ Private ]
{
    Set json = "Shutter.Util.Json"
    If $EXTRACT(ref, 1, 12) = "alternative:" {
        Set alts = match.%Get("alternatives"), n = +$PIECE(ref, ":", 2)
        If $ISOBJECT(alts) && (n >= 1) && (n <= alts.%Size()) Quit $CLASSMETHOD(json, "Str", alts.%Get(n - 1), "outcome")
    }
    Quit $CLASSMETHOD(json, "Str", match.%Get("preferred"), "outcome")
}

/// A fact for an alternative whose when names a flag: the field behind it, the values, the alternative, the change.
ClassMethod FlagFact(case As Shutter.Store.Case, profile As %DynamicObject, facts0 As %DynamicObject, alt As %DynamicObject, when As %String, n As %Integer, disposition As %String, ref As %String) As %DynamicObject [ Private ]
{
    Set json = "Shutter.Util.Json"
    Set flag = $ZSTRIP($PIECE(when, ":", 1), "<>W"), value = $ZSTRIP($PIECE(when, ":", 2, *), "<>W")
    Set f = {}
    Set f.kind = "alternative", f.flag = flag
    Set altOutcome = $CLASSMETHOD(json, "Str", alt, "outcome")
    Set altDisposition = ##class(Shutter.Operation.Gate).DispositionFor(altOutcome)
    Set f.alternative = {"n": (n), "outcome": (altOutcome), "disposition": (altDisposition), "when": (when), "why": ($CLASSMETHOD(json, "Str", alt, "why"))}
    Set holds = (ref = ("alternative:" _ n))
    If flag = "history_policy" {
        // The receiver's own setting: its category decides it, so the change is the category (or the override).
        Set category = ##class(Shutter.Store.SiteProfile).ReceiverCategory(case.Receiver)
        Set current = ##class(Shutter.Store.SiteProfile).ReceiverHistoryPolicy(case.Receiver)
        Set f.receiver = case.Receiver
        If value = "correct" {
            Set f.field = "receivers[].category", f.from = category, f.to = "history_of_record", f.current = category
        } Else {
            Set f.field = "receivers[].history_policy", f.from = current, f.to = value, f.current = current
        }
        Set f.affects = [("every overtaken failure at " _ case.Receiver _ " (a later movement applied before the failed one could be resent)")]
    } ElseIf flag = "authoritative_source" {
        Set other = $CLASSMETHOD(json, "Str", facts0, "other_source")
        Set f.field = "authoritative_source", f.current = ##class(Shutter.Store.SiteProfile).Flag("authoritative_source")
        Set f.from = f.current, f.to = $SELECT(value = "other_source": other, 1: value)
        Set f.affects = ["every failure where another source system applied a movement for the encounter at the same time"]
        If f.to = "" Quit ""
    } Else {
        Set f.field = flag, f.current = ##class(Shutter.Store.SiteProfile).Flag(flag), f.from = f.current, f.to = value
        Set f.affects = ["every case the catalogue entry covers, at every receiver"]
    }
    Do f.%Set("holds_now", holds, "boolean")
    If holds {
        Set f.would = "This setting is behind the outcome: the case followed the alternative (" _ altDisposition _ ")"
        Set f.role = "setting"
    } Else {
        Set f.would = "The case would have " _ ..Verb(altDisposition) _ " instead of " _ ..Verb(disposition)
        Set f.role = "alternative"
    }
    // The change: the value that makes the alternative hold; when it holds already, the value that would undo it.
    Set change = {}
    Set change.field = f.field, change.from = f.current
    Set change.to = $SELECT('holds: f.to, 1: $CASE(f.field, "receivers[].category": "current_state", "receivers[].history_policy": "current", "authoritative_source": "", "unconditional_resend": "forbidden", "merges": "forbidden", : ""))
    If f.%IsDefined("receiver") Set change.receiver = f.receiver
    Set change.why = $SELECT(holds: "Undo: the case would then follow the entry's preferred outcome", 1: $CLASSMETHOD(json, "Str", alt, "why"))
    Set change.affects = f.affects
    Set problem = ..ValidateChange(profile, change)
    Do change.%Set("valid", problem = "", "boolean")
    If problem '= "" Set change.problem = problem
    Do change.%Set("stale", 'holds && (f.from '= f.current), "boolean")
    Set f."suggested_change" = change
    Quit f
}

/// The tier's approval policy for the case's chain kind, one step stricter, when the case had a write to make.
ClassMethod PolicyFact(case As Shutter.Store.Case, profile As %DynamicObject, summary As %DynamicObject, disposition As %String) As %DynamicObject [ Private ]
{
    Set json = "Shutter.Util.Json"
    If '$LISTFIND($LISTBUILD("resend", "reconcile"), disposition) Quit ""
    Set tier = ##class(Shutter.Store.SiteProfile).TierOf(case.Receiver)
    Set cat = $SELECT($ISOBJECT(summary): summary.%Get("catalogue"), 1: "")
    Set kind = $SELECT($ISOBJECT(cat) && $ISOBJECT(cat.%Get("conditions")): $CLASSMETHOD(json, "Str", cat.%Get("conditions"), "chain", "single"), 1: "single")
    Set current = ##class(Shutter.Store.SiteProfile).Policy(tier, kind)
    Set stricter = $CASE(current, "automatic": "approval", "approval": "board", "per_chain": "board", : "")
    If stricter = "" Quit ""
    Set f = {}
    Set f.kind = "policy", f.flag = "policy", f.field = "policy." _ tier _ "." _ kind, f.current = current, f.from = current, f.to = stricter
    Set f.would = $SELECT(stricter = "approval": "An approver would have been asked before the write", 1: "The board would have decided the case")
    Do f.%Set("holds_now", 0, "boolean")
    Set f.role = "policy"
    Set f.affects = [("every tier " _ tier _ " case of a " _ kind _ " chain")]
    Set change = {"field": (f.field), "from": (current), "to": (stricter), "why": ("A stricter policy for tier " _ tier _ ", " _ kind _ " chains"), "affects": (f.affects)}
    Set problem = ..ValidateChange(profile, change)
    Do change.%Set("valid", problem = "", "boolean")
    If problem '= "" Set change.problem = problem
    Do change.%Set("stale", 0, "boolean")
    Set f."suggested_change" = change
    Quit f
}

/// A change applied to a copy of the profile and run through the validator: "" when the profile would still pass, else
/// the validator's words. The fields a change may name: receivers[].category, receivers[].history_policy,
/// receivers[].tier, receivers[].cancels, receivers[].merges (with receiver), authoritative_source, unconditional_resend,
/// merges, policy.<tier>.<kind>.
ClassMethod ValidateChange(profile As %DynamicObject, change As %DynamicObject) As %String
{
    Set json = "Shutter.Util.Json"
    Set field = $CLASSMETHOD(json, "Str", change, "field"), to = change.%Get("to")
    Set copy = ##class(Shutter.Util.Json).Parse(profile.%ToJSON(), .sc)
    If $$$ISERR(sc) || '$ISOBJECT(copy) Quit "the profile could not be copied"
    If $EXTRACT(field, 1, 12) = "receivers[]." {
        Set name = $CLASSMETHOD(json, "Str", change, "receiver"), key = $EXTRACT(field, 13, *)
        If '$LISTFIND($LISTBUILD("category", "history_policy", "tier", "cancels", "merges"), key) Quit "the field " _ field _ " is not one a change may name"
        Set list = copy.%Get("receivers"), found = 0
        If $ISOBJECT(list) {
            Set li = list.%GetIterator()
            While li.%GetNext(, .r) { If $ISOBJECT(r) && ($CLASSMETHOD(json, "Str", r, "name") = name) Set found = 1 Do ..SetTyped(r, key, to) Quit }
        }
        If 'found Quit "the profile does not name the receiver " _ name
    } ElseIf $LISTFIND($LISTBUILD("authoritative_source", "unconditional_resend", "merges"), field) {
        Do copy.%Set(field, to)
    } ElseIf $PIECE(field, ".", 1) = "policy" {
        Set tier = $PIECE(field, ".", 2), kind = $PIECE(field, ".", 3)
        Set table = copy.%Get("policy")
        If '$ISOBJECT(table) Quit "the profile has no policy table"
        Set row = table.%Get(tier)
        If '$ISOBJECT(row) Quit "the policy table has no tier " _ tier
        Do row.%Set(kind, to)
    } Else {
        Quit "the field " _ field _ " is not one a change may name"
    }
    Quit ##class(Shutter.Store.SiteProfile).Validate(copy)
}

/// Sets a receiver entry's field with the type the validator expects.
ClassMethod SetTyped(r As %DynamicObject, key As %String, to) [ Private ]
{
    If key = "tier" Do r.%Set(key, +to, "number") Quit
    If (key = "cancels") || (key = "merges") Do r.%Set(key, ((to = 1) || (to = "true")), "boolean") Quit
    Do r.%Set(key, to)
}

/// A disposition as a past-tense phrase for a sentence.
ClassMethod Verb(disposition As %String) As %String [ Private ]
{
    Quit $CASE(disposition, "superseded": "closed as superseded with no write", "resend": "resent the message", "reconcile": "reconciled against the receipt with no write", "escalate": "escalated to a person", "more_evidence": "waited for more evidence", : "done " _ $SELECT(disposition = "": "nothing", 1: disposition))
}

}
