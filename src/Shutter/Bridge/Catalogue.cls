/// The tool catalogue an agent run may offer the model (CONTRACTS 9, v1.38): the names declared here for each toolset,
/// the run's terminal tool and the knowledge collections attached, and nothing else. The AI Hub runner asks the framework
/// what it discovered (%Discover) after the tools are added and before any model call, and a run whose catalogue is not
/// exactly the declared one ends with the status catalogue_mismatch, so an inherited, added or renamed tool never reaches
/// a model unnoticed. Pure functions, in the core, so the comparison is tested without the %AI package.
Class Shutter.Bridge.Catalogue
{

/// The evidence toolset's tools, as the framework names them (the class's public methods).
Parameter EVIDENCETOOLS = "GetSnapshot,GetMessage,GetValidation,GetWardState,GetReceipt,GetTimeline,GetRoute,GetFailure";

/// The terminal tools a run may carry, one each, named as their classes are.
Parameter TERMINALS = "SubmitFindings,SubmitPlan,SubmitAnswer,SubmitBoardAnswer,SubmitReview";

/// The tool names a knowledge collection adds when attached (%AI.RAG.KnowledgeBase.AddToAgent): search_<collection>.
Parameter KNOWLEDGEPREFIX = "search_";

/// The names expected: the toolsets (comma-separated class names; only Shutter.Tools.Evidence is known), the terminal
/// tool (one of TERMINALS; "" for none) and the knowledge collections attached (comma-separated). An unknown toolset or
/// terminal is a name expected of nothing, so the check fails and says so.
ClassMethod Expected(toolsets As %String = "", terminal As %String = "", collections As %String = "") As %List
{
    Set out = ""
    For i = 1:1:$LENGTH(toolsets, ",") {
        Set ts = $ZSTRIP($PIECE(toolsets, ",", i), "<>W")
        Continue:ts=""
        If ts = "Shutter.Tools.Evidence" {
            For j = 1:1:$LENGTH(..#EVIDENCETOOLS, ",") Set out = out _ $LISTBUILD($PIECE(..#EVIDENCETOOLS, ",", j))
        } Else {
            Set out = out _ $LISTBUILD("?" _ ts)
        }
    }
    If terminal '= "" Set out = out _ $LISTBUILD($SELECT($LISTFIND($LISTFROMSTRING(..#TERMINALS, ","), terminal): terminal, 1: "?" _ terminal))
    For i = 1:1:$LENGTH(collections, ",") {
        Set c = $ZSTRIP($PIECE(collections, ",", i), "<>W")
        If c '= "" Set out = out _ $LISTBUILD(..#KNOWLEDGEPREFIX _ c)
    }
    Quit out
}

/// Whether the discovered names are exactly the expected ones (order free, case free); problem names what is missing
/// and what was not expected.
ClassMethod Check(expected As %List, discovered As %List, Output problem As %String) As %Boolean
{
    Set problem = ""
    Kill want, have
    For i = 1:1:$LISTLENGTH(expected) { Set n = $LISTGET(expected, i) If n '= "" Set want($ZCONVERT(n, "U")) = n }
    For i = 1:1:$LISTLENGTH(discovered) { Set n = $LISTGET(discovered, i) If n '= "" Set have($ZCONVERT(n, "U")) = n }
    Set missing = "", extra = "", k = ""
    For { Set k = $ORDER(want(k)) Quit:k=""  If '$DATA(have(k)) Set missing = missing _ $SELECT(missing = "": "", 1: ", ") _ want(k) }
    Set k = ""
    For { Set k = $ORDER(have(k)) Quit:k=""  If '$DATA(want(k)) Set extra = extra _ $SELECT(extra = "": "", 1: ", ") _ have(k) }
    If (missing = "") && (extra = "") Quit 1
    Set problem = $SELECT(missing '= "": "missing " _ missing, 1: "") _ $SELECT((missing '= "") && (extra '= ""): "; ", 1: "") _ $SELECT(extra '= "": "not declared " _ extra, 1: "")
    Quit 0
}

/// The names of %Discover's answer (an array of tool descriptions with a name each), as a list.
ClassMethod NamesOf(tools As %DynamicArray) As %List
{
    Set out = ""
    If '$ISOBJECT(tools) Quit out
    Set iter = tools.%GetIterator()
    While iter.%GetNext(, .t) {
        Set name = $SELECT($ISOBJECT(t): ##class(Shutter.Util.Json).Str(t, "name"), 1: "" _ t)
        If name '= "" Set out = out _ $LISTBUILD(name)
    }
    Quit out
}

}
