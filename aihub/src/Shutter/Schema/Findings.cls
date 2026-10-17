/// A specialist's findings: the terminal tool's argument, so the model sees this shape as the tool's
/// JSON Schema and the core stores exactly it (Shutter.Store.Finding).
Class Shutter.Schema.Findings Extends (%RegisteredObject, %JSON.Adaptor)
{

/// One of resend, reconcile, superseded, more_evidence, escalate.
Property Disposition As %String(%JSONFIELDNAME = "disposition", MAXLEN = 32) [ Required ];

/// 0 to 1.
Property Confidence As %Float(%JSONFIELDNAME = "confidence", MAXVAL = 1, MINVAL = 0) [ Required ];

/// What was established, in a few sentences, with the evidence it rests on.
Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = 4000) [ Required ];

/// Contract clauses the message or the situation breaks; empty when none.
Property Violations As list Of %String(%JSONFIELDNAME = "violations", MAXLEN = 1000);

/// What could not be established from the evidence.
Property Unknowns As list Of %String(%JSONFIELDNAME = "unknowns", MAXLEN = 1000);

/// Snapshot item kinds or identifiers the findings rest on (message, validation, ward_state, receipt, timeline, route, error).
Property EvidenceRefs As list Of %String(%JSONFIELDNAME = "evidence_refs", MAXLEN = 200);

/// The dispositions a finding or a plan may carry.
Parameter DISPOSITIONS = ",resend,reconcile,superseded,more_evidence,escalate,";

/// Problems with a findings object as JSON text, as an array of messages; empty when it is valid.
ClassMethod Check(json As %String) As %DynamicArray
{
    Set problems = []
    Set o = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(o) || $$$ISERR(sc) Do problems.%Push("findings must be a JSON object") Quit problems
    Set d = ##class(Shutter.Util.Json).Str(o, "disposition")
    If ..#DISPOSITIONS '[ ("," _ d _ ",") Do problems.%Push("disposition must be one of resend, reconcile, superseded, more_evidence, escalate")
    Set c = ##class(Shutter.Util.Json).Str(o, "confidence")
    If (c = "") || (c '= +c) || (c < 0) || (c > 1) Do problems.%Push("confidence must be a number from 0 to 1")
    If ##class(Shutter.Util.Json).Str(o, "summary") = "" Do problems.%Push("summary is required")
    For f = "violations", "unknowns", "evidence_refs" {
        If (o.%GetTypeOf(f) '= "unassigned") && (o.%GetTypeOf(f) '= "array") Do problems.%Push(f _ " must be an array of strings")
    }
    If o.%GetTypeOf("evidence_refs") '= "array" Do problems.%Push("evidence_refs must list the evidence used")
    Quit problems
}

}
