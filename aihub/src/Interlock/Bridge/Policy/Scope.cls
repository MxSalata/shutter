Include %AI

/// Holds an agent run to its own case and to the tools its role may use. Attached by the runner as
/// the global authorization policy, so the model cannot read another case's evidence or submit
/// a result for it, whatever the prompt says.
Class Interlock.Bridge.Policy.Scope Extends %AI.Policy.Authorization
{

/// The case the run is for.
Property CaseId As %String(MAXLEN = 32);

/// Comma-separated tool names the run may call; empty allows every registered tool.
Property Allowed As %String(MAXLEN = 1000);

/// Calls denied, for the response.
Property Denied As %Integer [ InitialExpression = 0 ];

Method %CanExecute(toolref As %String, call As %DynamicObject, metadata As %DynamicObject) As %Status
{
    Set name = ..ToolName(call)
    If (..Allowed '= "") && ((("," _ ..Allowed _ ",") '[ ("," _ name _ ","))) {
        Set ..Denied = ..Denied + 1
        Return $$$ERROR($$$AICoreToolAccessDenied, "The tool " _ name _ " is not available to this role")
    }
    Set args = ..Arguments(call)
    If $ISOBJECT(args) && (..CaseId '= "") {
        For key = "caseId", "case_id" {
            If args.%IsDefined(key) && (args.%Get(key) '= ..CaseId) {
                Set ..Denied = ..Denied + 1
                Return $$$ERROR($$$AICoreToolAccessDenied, "This run is for case " _ ..CaseId _ " only")
            }
        }
    }
    Return $$$OK
}

/// The bare tool name, whatever prefix the framework uses.
ClassMethod ToolName(call As %DynamicObject) As %String
{
    Set name = $SELECT($ISOBJECT(call): ##class(Interlock.Util.Json).Str(call, "name"), 1: "")
    If name [ ":" Set name = $PIECE(name, ":", *)
    Quit name
}

/// The call's arguments as a dynamic object, whether the framework passes them decoded or as text.
ClassMethod Arguments(call As %DynamicObject) As %DynamicObject
{
    If '$ISOBJECT(call) Quit ""
    Set args = call.%Get("arguments")
    If $ISOBJECT(args) Quit args
    If $EXTRACT($ZSTRIP(args, "<W")) = "{" Quit ##class(Interlock.Util.Json).Parse(args, .sc)
    Quit ""
}

}
