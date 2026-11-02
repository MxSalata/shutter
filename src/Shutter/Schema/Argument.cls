/// How a tool argument reaches the terminal tools: decoded into the schema class, as a dynamic
/// object, or as JSON text. Not a tool class, so nothing here is offered to the model.
Class Shutter.Schema.Argument
{

/// The argument as JSON text, or "" with the reason in <var>err</var>.
ClassMethod AsJSON(ByRef value, Output err As %String) As %String
{
    Set err = ""
    If $ISOBJECT(value) {
        // The framework decodes a class-typed argument into an instance of the schema class (measured on
        // build 154); %IsA is not relied on, the export methods are tried in turn.
        Try {
            Set sc = value.%JSONExportToString(.json)
            If $$$ISOK(sc) && ($GET(json) '= "") Return json
            Set err = "The object could not be exported: " _ $SYSTEM.Status.GetErrorText(sc)
        } Catch {
        }
        Try {
            Return value.%ToJSON()
        } Catch {
        }
        If err = "" Set err = "Unexpected argument of class " _ $CLASSNAME(value)
        Return ""
    }
    Set text = $ZSTRIP($GET(value), "<>W")
    If $EXTRACT(text) = "{" Return text
    Set err = "The argument must be an object"
    Return ""
}

}
