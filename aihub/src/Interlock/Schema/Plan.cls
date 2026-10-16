/// The coordinator's plan: the terminal tool's argument, so the model sees this shape as the tool's
/// JSON Schema and the core stores exactly it (Interlock.Store.Plan).
Class Interlock.Schema.Plan Extends (%RegisteredObject, %JSON.Adaptor)
{

/// One of resend, reconcile, superseded, more_evidence, escalate.
Property Disposition As %String(%JSONFIELDNAME = "disposition", MAXLEN = 32) [ Required ];

/// The plan in a few sentences: what holds, what is proposed, what it depends on.
Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = 4000) [ Required ];

/// The one action: type resend, reconcile or none.
Property Action As Interlock.Schema.PlanAction(%JSONFIELDNAME = "action") [ Required ];

/// What must still hold at dispatch; the gate checks what it can.
Property Preconditions As list Of %String(%JSONFIELDNAME = "preconditions", MAXLEN = 1000);

/// Snapshot item kinds or identifiers the plan rests on.
Property EvidenceRefs As list Of %String(%JSONFIELDNAME = "evidence_refs", MAXLEN = 200);

/// The specialists' views the plan does not follow, kept.
Property Disagreements As list Of Interlock.Schema.Disagreement(%JSONFIELDNAME = "disagreements");

/// Problems with a plan object as JSON text, as an array of messages; empty when it is valid.
ClassMethod Check(json As %String) As %DynamicArray
{
    Set problems = []
    Set o = ##class(Interlock.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(o) || $$$ISERR(sc) Do problems.%Push("plan must be a JSON object") Quit problems
    Set d = ##class(Interlock.Util.Json).Str(o, "disposition")
    If ##class(Interlock.Schema.Findings).#DISPOSITIONS '[ ("," _ d _ ",") Do problems.%Push("disposition must be one of resend, reconcile, superseded, more_evidence, escalate")
    If ##class(Interlock.Util.Json).Str(o, "summary") = "" Do problems.%Push("summary is required")
    Set action = o.%Get("action")
    If '$ISOBJECT(action) {
        Do problems.%Push("action is required: {type: resend | reconcile | none, operation_key, expected_version}")
    } Else {
        Set t = ##class(Interlock.Util.Json).Str(action, "type")
        If ",resend,reconcile,none," '[ ("," _ t _ ",") Do problems.%Push("action.type must be resend, reconcile or none")
        If (t = "resend") {
            If ##class(Interlock.Util.Json).Str(action, "operation_key") = "" Do problems.%Push("a resend names the case's operation_key")
            Set ev = ##class(Interlock.Util.Json).Str(action, "expected_version")
            If (ev = "") || (ev '= +ev) Do problems.%Push("a resend carries expected_version, the receiver's current version")
            If d '= "resend" Do problems.%Push("action.type resend needs disposition resend")
        }
        If (t = "none") && (d = "resend") Do problems.%Push("disposition resend needs action.type resend")
    }
    If o.%GetTypeOf("evidence_refs") '= "array" Do problems.%Push("evidence_refs must list the evidence used")
    If (o.%GetTypeOf("disagreements") '= "unassigned") && (o.%GetTypeOf("disagreements") '= "array") Do problems.%Push("disagreements must be an array of {member, said, why_kept}")
    Quit problems
}

}
