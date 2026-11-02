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
ClassMethod Check(json As %String, citeIds As %String = "") As %DynamicArray
{
    Set problems = []
    Set o = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(o) || $$$ISERR(sc) Do problems.%Push("findings must be a JSON object") Quit problems
    Set d = ##class(Shutter.Util.Json).Str(o, "disposition")
    If ..#DISPOSITIONS '[ ("," _ d _ ",") Do problems.%Push("disposition must be one of resend, reconcile, superseded, more_evidence, escalate")
    Set c = ##class(Shutter.Util.Json).Str(o, "confidence")
    If (c = "") || (c '= +c) || (c < 0) || (c > 1) Do problems.%Push("confidence must be a number from 0 to 1")
    Set summary = ##class(Shutter.Util.Json).Str(o, "summary")
    If summary = "" Do problems.%Push("summary is required")
    If $LENGTH(summary) > 2000 Do problems.%Push("summary must be at most 2000 characters; it is " _ $LENGTH(summary))
    For f = "violations", "unknowns", "evidence_refs" {
        If (o.%GetTypeOf(f) '= "unassigned") && (o.%GetTypeOf(f) '= "array") Do problems.%Push(f _ " must be an array of strings")
    }
    If o.%GetTypeOf("evidence_refs") '= "array" Do problems.%Push("evidence_refs must list the evidence used")
    Do ..CheckRefs(o, citeIds, problems)
    Quit problems
}

/// Every evidence_refs entry must name evidence the run was given (v1.35): a key of the context's evidence, or a key one
/// level down in it, as the runner lists them in citeIds (comma separated); "" leaves the list unchecked. An unknown name
/// is a problem the model repairs in the same run, so a finding never cites evidence that is not there.
ClassMethod CheckRefs(o As %DynamicObject, citeIds As %String, ByRef problems As %DynamicArray)
{
    If (citeIds = "") || '$ISOBJECT(o) || (o.%GetTypeOf("evidence_refs") '= "array") Quit
    Set known = "," _ citeIds _ ",", bad = ""
    Set it = o."evidence_refs".%GetIterator()
    While it.%GetNext(, .ref) {
        If $ISOBJECT(ref) || (ref = "") Set bad = bad _ $SELECT(bad = "": "", 1: ", ") _ "(not a name)" Continue
        If known '[ ("," _ ref _ ",") Set bad = bad _ $SELECT(bad = "": "", 1: ", ") _ ref
    }
    If bad '= "" Do problems.%Push("evidence_refs names evidence that was not given: " _ bad _ "; cite the keys of the evidence you received (" _ $EXTRACT(citeIds, 1, 400) _ ")")
}

}
