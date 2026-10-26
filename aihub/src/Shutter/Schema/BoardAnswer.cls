/// The board's answer to a question about a case (CONTRACTS 14.2): the coordinator's synthesis of the members' answers.
/// The terminal tool's argument. setting, under_alternative and suggested_change name a fact of the question's what-if
/// facts by its id and nothing else: the tool refuses any other, and the core stores the fact's typed change.
Class Shutter.Schema.BoardAnswer Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The synthesis in plain words, at most 1200 characters.
Property Answer As %String(%JSONFIELDNAME = "answer", MAXLEN = 1200) [ Required ];

/// Each specialist's view, disagreements kept.
Property Perspectives As list Of Shutter.Schema.Perspective(%JSONFIELDNAME = "perspectives");

/// The setting that decided this case's outcome, as a fact id.
Property Setting As Shutter.Schema.FactRef(%JSONFIELDNAME = "setting");

/// What the case would have done under the alternative the person asked about, as a fact id.
Property UnderAlternative As Shutter.Schema.FactRef(%JSONFIELDNAME = "under_alternative");

/// A change to the site profile the person may want to make, as a fact id with why; a draft only, never applied.
Property SuggestedChange As Shutter.Schema.FactRef(%JSONFIELDNAME = "suggested_change");

/// The evidence ids and fact ids the answer rests on.
Property Cites As list Of %String(%JSONFIELDNAME = "cites", MAXLEN = 64);

/// high, medium or low.
Property Confidence As %String(%JSONFIELDNAME = "confidence", MAXLEN = 8, VALUELIST = ",high,medium,low");

/// Problems with a board answer as JSON text, as an array of messages; empty when its shape is right and every fact it
/// names is one of factIds (the ids of the question's whatif.facts, comma separated).
ClassMethod Check(json As %String, factIds As %String = "") As %DynamicArray
{
    Set problems = []
    Set o = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(o) || $$$ISERR(sc) Do problems.%Push("answer must be a JSON object") Quit problems
    Do ##class(Shutter.Schema.Answer).CheckCommon(o, problems)
    Set t = o.%GetTypeOf("perspectives")
    If (t '= "unassigned") && (t '= "null") {
        If t '= "array" {
            Do problems.%Push("perspectives must be an array of {member, view}")
        } Else {
            Set list = o.%Get("perspectives")
            For i = 0:1:list.%Size() - 1 {
                Set p = list.%Get(i)
                If '$ISOBJECT(p) Do problems.%Push("perspectives[" _ i _ "] must be an object") Continue
                If ##class(Shutter.Util.Json).Str(p, "member") = "" Do problems.%Push("perspectives[" _ i _ "] needs the member")
                Set view = ##class(Shutter.Util.Json).Str(p, "view")
                If $ISOBJECT(view) Set view = ""
                If $ZSTRIP(view, "<>W") = "" {
                    Do problems.%Push("perspectives[" _ i _ "] needs the member's view")
                } ElseIf $LENGTH(view) > 400 {
                    Do problems.%Push("perspectives[" _ i _ "] view is longer than 400 characters")
                }
            }
        }
    }
    Set ids = $LISTFROMSTRING(factIds, ",")
    For field = "setting", "under_alternative", "suggested_change" {
        Set t = o.%GetTypeOf(field)
        Continue:(t = "unassigned")||(t = "null")
        If t '= "object" Do problems.%Push(field _ " must be {fact: ""W<n>""}") Continue
        Set fact = ##class(Shutter.Util.Json).Str(o.%Get(field), "fact")
        If $ISOBJECT(fact) Set fact = ""
        If (fact = "") || '$LISTFIND(ids, fact) Do problems.%Push(field _ " names a setting or change that is not among the facts: name one of " _ $SELECT(factIds '= "": factIds, 1: "none (this question has no facts, so leave it out)"))
    }
    Quit problems
}

}
