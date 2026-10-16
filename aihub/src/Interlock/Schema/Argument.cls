/// How a tool argument reaches the terminal tools: decoded into the schema class, as a dynamic
/// object, or as JSON text. Not a tool class, so nothing here is offered to the model.
Class Interlock.Schema.Argument
{

/// The argument as JSON text, or "" with the reason in <var>err</var>.
ClassMethod AsJSON(ByRef value, Output err As %String) As %String
{
    Set err = ""
    If $ISOBJECT(value) {
        If value.%IsA("%JSON.Adaptor") {
            Set sc = value.%JSONExportToString(.json)
            If $$$ISERR(sc) Set err = "The object could not be read: " _ $SYSTEM.Status.GetErrorText(sc) Return ""
            Return json
        }
        If value.%IsA("%DynamicAbstractObject") Return value.%ToJSON()
        Set err = "Unexpected argument of class " _ $CLASSNAME(value)
        Return ""
    }
    Set text = $ZSTRIP($GET(value), "<>W")
    If $EXTRACT(text) = "{" Return text
    Set err = "The argument must be an object"
    Return ""
}

}
