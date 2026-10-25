/// The review agent's result: the terminal tool's argument, so the model sees this shape as the tool's JSON Schema
/// and the core stores exactly it (Shutter.Store.Review.RankingJSON). The findings are the sweep's; the agent orders
/// them within their severity tiers and explains each one.
Class Shutter.Schema.Review Extends (%RegisteredObject, %JSON.Adaptor)
{

/// Every finding of the review once, with its rank and its explanation.
Property Ranking As list Of Shutter.Schema.ReviewRank(%JSONFIELDNAME = "ranking") [ Required ];

/// The review in a few sentences: what stands out, what the case history supports, what it does not.
Property Summary As %String(%JSONFIELDNAME = "summary", MAXLEN = 600);

/// What the findings and the case aggregates do not decide.
Property Unknowns As list Of %String(%JSONFIELDNAME = "unknowns", MAXLEN = 600);

/// Problems with a review object as JSON text, as an array of messages; empty when its shape is right: a ranking that
/// names each finding id once, with ranks that are the integers 1 to n (n entries, each from 1 to n, none twice, so
/// none missing), an explanation for each within its length, and summary and unknowns of their types when present.
/// Whether the ids are the review's own and whether the order keeps the severity tiers is the business process's
/// check: it has the review, this method has the text.
ClassMethod Check(json As %String) As %DynamicArray
{
    Set problems = []
    Set o = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(o) || $$$ISERR(sc) Do problems.%Push("review must be a JSON object") Quit problems
    If o.%GetTypeOf("ranking") '= "array" Do problems.%Push("ranking must be an array of {finding_id, rank, explanation, confidence_note}") Quit problems
    Set ranking = o.%Get("ranking")
    Set n = ranking.%Size()
    If n = 0 Do problems.%Push("ranking must list every finding of the review")
    For i = 0:1:n - 1 {
        If ranking.%GetTypeOf(i) '= "object" Do problems.%Push("ranking[" _ i _ "] must be an object") Continue
        Set r = ranking.%Get(i)
        Set id = ##class(Shutter.Util.Json).Str(r, "finding_id")
        If id = "" {
            Do problems.%Push("ranking[" _ i _ "] needs a finding_id")
        } ElseIf $DATA(seen(id)) {
            Do problems.%Push("finding " _ id _ " is ranked more than once")
        } Else {
            Set seen(id) = i
        }
        Set rank = ##class(Shutter.Util.Json).Str(r, "rank")
        If $ISOBJECT(rank) Set rank = ""
        If (rank = "") || (rank '= +rank) || (+rank '= (+rank \ 1)) || (+rank < 1) || (+rank > n) {
            Do problems.%Push("ranking[" _ i _ "] rank must be an integer from 1 to " _ n _ ", the number of findings ranked")
        } ElseIf $DATA(taken(+rank)) {
            Do problems.%Push("rank " _ (+rank) _ " is given twice: ranks run 1 to " _ n _ " without a gap")
        } Else {
            Set taken(+rank) = i
        }
        // An object where text belongs counts as no text.
        Set explanation = ##class(Shutter.Util.Json).Str(r, "explanation")
        If $ISOBJECT(explanation) Set explanation = ""
        If $ZSTRIP(explanation, "<>W") = "" {
            Do problems.%Push("ranking[" _ i _ "] needs an explanation" _ $SELECT(id '= "": " for " _ id, 1: ""))
        } ElseIf $LENGTH(explanation) > 600 {
            Do problems.%Push("the explanation of " _ $SELECT(id '= "": id, 1: "ranking[" _ i _ "]") _ " is longer than 600 characters")
        }
        Set note = ##class(Shutter.Util.Json).Str(r, "confidence_note")
        If $ISOBJECT(note) Set note = ""
        If $LENGTH(note) > 300 Do problems.%Push("the confidence_note of " _ $SELECT(id '= "": id, 1: "ranking[" _ i _ "]") _ " is longer than 300 characters")
    }
    Set summary = ##class(Shutter.Util.Json).Str(o, "summary")
    If $ISOBJECT(summary) {
        Do problems.%Push("summary must be text")
    } ElseIf $LENGTH(summary) > 600 {
        Do problems.%Push("summary is longer than 600 characters")
    }
    If (o.%GetTypeOf("unknowns") '= "unassigned") && (o.%GetTypeOf("unknowns") '= "null") && (o.%GetTypeOf("unknowns") '= "array") Do problems.%Push("unknowns must be an array of strings")
    Quit problems
}

}
