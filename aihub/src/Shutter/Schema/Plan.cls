/// The coordinator's plan: the terminal tool's argument, so the model sees this shape as the tool's
/// JSON Schema and the core stores exactly it (Shutter.Store.Plan).
Class Shutter.Schema.Plan Extends (%RegisteredObject, %JSON.Adaptor)
{

/// One of resend, reconcile, superseded, more_evidence, escalate.
Property Disposition As %String(%JSONFIELDNAME = "disposition", MAXLEN = 32) [ Required ];

/// The plan in a few sentences: what holds, what is proposed, what it depends on.
Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = 4000) [ Required ];

/// The one action: type resend, reconcile or none.
Property Action As Shutter.Schema.PlanAction(%JSONFIELDNAME = "action") [ Required ];

/// What must still hold at dispatch; the gate checks what it can.
Property Preconditions As list Of %String(%JSONFIELDNAME = "preconditions", MAXLEN = 1000);

/// Snapshot item kinds or identifiers the plan rests on.
Property EvidenceRefs As list Of %String(%JSONFIELDNAME = "evidence_refs", MAXLEN = 200);

/// The specialists' views the plan does not follow, kept.
Property Disagreements As list Of Shutter.Schema.Disagreement(%JSONFIELDNAME = "disagreements");

/// The catalogue entry the plan follows (E1, E2, ...), from the evidence's catalogue matches; empty when none fits.
Property CatalogueEntry As %String(%JSONFIELDNAME = "catalogue_entry", MAXLEN = 16);

/// The entry's outcome chosen: "preferred", or "alternative:<n>" (1-based); empty when no entry is named.
Property Outcome As %String(%JSONFIELDNAME = "outcome", MAXLEN = 32);

/// Why that entry and that outcome, in a sentence.
Property Why As %String(%JSONFIELDNAME = "why", MAXLEN = 1000);

/// Problems with a plan object as JSON text, as an array of messages; empty when it is valid.
ClassMethod Check(json As %String, citeIds As %String = "") As %DynamicArray
{
    Set problems = []
    Set o = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(o) || $$$ISERR(sc) Do problems.%Push("plan must be a JSON object") Quit problems
    Set d = ##class(Shutter.Util.Json).Str(o, "disposition")
    If ##class(Shutter.Schema.Findings).#DISPOSITIONS '[ ("," _ d _ ",") Do problems.%Push("disposition must be one of resend, reconcile, superseded, more_evidence, escalate")
    If ##class(Shutter.Util.Json).Str(o, "summary") = "" Do problems.%Push("summary is required")
    Set action = o.%Get("action")
    If '$ISOBJECT(action) {
        Do problems.%Push("action is required: {type: resend | reconcile | none, operation_key, expected_version}")
    } Else {
        Set t = ##class(Shutter.Util.Json).Str(action, "type")
        If ",resend,reconcile,none," '[ ("," _ t _ ",") Do problems.%Push("action.type must be resend, reconcile or none")
        If (t = "resend") {
            If ##class(Shutter.Util.Json).Str(action, "operation_key") = "" Do problems.%Push("a resend names the case's operation_key")
            Set ev = ##class(Shutter.Util.Json).Str(action, "expected_version")
            If (ev = "") || (ev '= +ev) Do problems.%Push("a resend carries expected_version, the receiver's current version")
            If d '= "resend" Do problems.%Push("action.type resend needs disposition resend")
        }
        If (t = "none") && (d = "resend") Do problems.%Push("disposition resend needs action.type resend")
    }
    If o.%GetTypeOf("evidence_refs") '= "array" Do problems.%Push("evidence_refs must list the evidence used")
    // The refs must name evidence the run was given (v1.35), as for findings.
    Do ##class(Shutter.Schema.Findings).CheckRefs(o, citeIds, problems)
    If (o.%GetTypeOf("disagreements") '= "unassigned") && (o.%GetTypeOf("disagreements") '= "array") Do problems.%Push("disagreements must be an array of {member, said, why_kept}")
    Set entry = ##class(Shutter.Util.Json).Str(o, "catalogue_entry"), outcome = ##class(Shutter.Util.Json).Str(o, "outcome")
    If (entry '= "") && (outcome '= "preferred") && ($EXTRACT(outcome, 1, 12) '= "alternative:") Do problems.%Push("outcome must be preferred or alternative:<n> when a catalogue_entry is named")
    If (entry = "") && (outcome '= "") Do problems.%Push("outcome needs a catalogue_entry")
    Quit problems
}

}
