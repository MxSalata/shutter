/// An answer to a question about a case (CONTRACTS 14.2): the Explain agent's, and each board member's. The terminal
/// tool's argument, so the model sees this shape as the tool's JSON Schema; the core checks the cites against the model
/// view and the facts (Shutter.Store.CaseQuestion.CheckAnswer) before it stores the answer.
Class Shutter.Schema.Answer Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The answer in plain words, at most 1200 characters.
Property Answer As %String(%JSONFIELDNAME = "answer", MAXLEN = 1200) [ Required ];

/// The evidence ids of the model view (message, history[2], ...) and the fact ids (W1, W2, ...) the answer rests on.
Property Cites As list Of %String(%JSONFIELDNAME = "cites", MAXLEN = 64);

/// high, medium or low.
Property Confidence As %String(%JSONFIELDNAME = "confidence", MAXLEN = 8, VALUELIST = ",high,medium,low");

/// Problems with an answer object as JSON text, as an array of messages; empty when its shape is right and, when
/// <var>citeIds</var> is given (the case's evidence ids and the fact ids, comma separated), every cite's head is one of
/// them, as the core checks it again (Shutter.Store.CaseQuestion.CiteKnown).
ClassMethod Check(json As %String, citeIds As %String = "") As %DynamicArray
{
    Set problems = []
    Set o = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(o) || $$$ISERR(sc) Do problems.%Push("answer must be a JSON object") Quit problems
    Do ..CheckCommon(o, problems, citeIds)
    Quit problems
}

/// The fields an Explain answer and a board answer share: answer, cites and confidence.
ClassMethod CheckCommon(o As %DynamicObject, problems As %DynamicArray, citeIds As %String = "")
{
    Set answer = ##class(Shutter.Util.Json).Str(o, "answer")
    If $ISOBJECT(answer) Set answer = ""
    If $ZSTRIP(answer, "<>W") = "" {
        Do problems.%Push("answer needs the answer in plain words")
    } ElseIf $LENGTH(answer) > 1200 {
        Do problems.%Push("answer is longer than 1200 characters")
    }
    Set t = o.%GetTypeOf("cites")
    If (t '= "unassigned") && (t '= "null") {
        If t '= "array" {
            Do problems.%Push("cites must be an array of evidence ids and fact ids")
        } Else {
            Set cites = o.%Get("cites")
            Set ids = $LISTFROMSTRING(citeIds, ",")
            For i = 0:1:cites.%Size() - 1 {
                If (cites.%GetTypeOf(i) '= "string") || (cites.%Get(i) = "") Do problems.%Push("cites[" _ i _ "] must be an evidence id or a fact id (W1, W2, ...)") Continue
                Set c = $ZSTRIP(cites.%Get(i), "<>W"), head = $PIECE($PIECE($PIECE(c, ".", 1), "[", 1), ":", 1)
                If (citeIds '= "") && '$LISTFIND(ids, c) && '$LISTFIND(ids, head) Do problems.%Push("cites[" _ i _ "] """ _ c _ """ is not citable: cite an evidence id of the case section (" _ ..Sample(citeIds) _ ", alone or with a path such as history[2]) or a fact id W<n>; the plan, the gate's checks and the findings are not cited")
            }
        }
    }
    Set c = ##class(Shutter.Util.Json).Str(o, "confidence")
    If $ISOBJECT(c) || ((c '= "") && '$LISTFIND($LISTBUILD("high", "medium", "low"), c)) Do problems.%Push("confidence must be high, medium or low")
}

/// A few of the citable ids, for a refusal's message.
ClassMethod Sample(citeIds As %String) As %String [ Private ]
{
    Set out = "", n = 0
    For i = 1:1:$LENGTH(citeIds, ",") {
        Set id = $PIECE(citeIds, ",", i)
        Continue:(id = "")||(id ? 1"W"1.N)
        Set out = out _ $SELECT(out = "": "", 1: ", ") _ id, n = n + 1
        Quit:n=6
    }
    Quit out
}

}
