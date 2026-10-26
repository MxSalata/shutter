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

/// Problems with an answer object as JSON text, as an array of messages; empty when its shape is right. Whether each
/// cite is an evidence id or a fact id of this question is the core's check: it has the model view and the facts.
ClassMethod Check(json As %String) As %DynamicArray
{
    Set problems = []
    Set o = ##class(Shutter.Util.Json).Parse(json, .sc)
    If '$ISOBJECT(o) || $$$ISERR(sc) Do problems.%Push("answer must be a JSON object") Quit problems
    Do ..CheckCommon(o, problems)
    Quit problems
}

/// The fields an Explain answer and a board answer share: answer, cites and confidence.
ClassMethod CheckCommon(o As %DynamicObject, problems As %DynamicArray)
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
            For i = 0:1:cites.%Size() - 1 {
                If (cites.%GetTypeOf(i) '= "string") || (cites.%Get(i) = "") Do problems.%Push("cites[" _ i _ "] must be an evidence id or a fact id (W1, W2, ...)")
            }
        }
    }
    Set c = ##class(Shutter.Util.Json).Str(o, "confidence")
    If $ISOBJECT(c) || ((c '= "") && '$LISTFIND($LISTBUILD("high", "medium", "low"), c)) Do problems.%Push("confidence must be high, medium or low")
}

}
