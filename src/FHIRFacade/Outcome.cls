/// The OperationOutcome bodies the test FHIR server answers with. Where IRIS for Health's own FHIR server was measured
/// (2026.2 Build 221U, 2026.3.0AI Build 154U, 2027.1.0AI Build 109U) the severity, code, diagnostics and text are its
/// own, byte for byte; the diagnostics of the answers that were not measured start <code>&lt;FacadeErr&gt;</code>, so
/// nobody takes them for IRIS's.
Class FHIRFacade.Outcome
{

/// One issue as a JSON string, with <var>expression</var> when given.
ClassMethod Issue(severity As %String, code As %String, diagnostics As %String, text As %String, expression As %String = "") As %String
{
    Set issue = {"severity": (severity), "code": (code), "diagnostics": (diagnostics), "details": {"text": (text)}}
    Do:expression'="" issue.%Set("expression", [(expression)])
    Quit {"resourceType": "OperationOutcome", "issue": [(issue)]}.%ToJSON()
}

ClassMethod NotFound(type As %String, id As %String) As %String
{
    Quit ..Issue("error", "not-found", "<HSFHIRErr>ResourceNotFound", "No resource with type '" _ type _ "' and id '" _ id _ "'")
}

ClassMethod VersionNotFound(type As %String, id As %String, vid As %String) As %String
{
    Quit ..Issue("error", "not-found", "<HSFHIRErr>ResourceVersionNotFound", "No resource with type '" _ type _ "', id '" _ id _ "' and version '" _ vid _ "'")
}

/// A read of a deleted resource (<var>vid</var> empty) or a vread of the delete's own version.
ClassMethod Deleted(type As %String, id As %String, vid As %String = "") As %String
{
    Quit ..Issue("error", "exception", "<HSFHIRErr>ResourceWasDeleted", "Resource was previously deleted (type='" _ type _ "', id='" _ id _ "', version='" _ vid _ "').")
}

ClassMethod InvalidIfMatch(sent As %String) As %String
{
    Quit ..Issue("error", "invalid", "<HSFHIRErr>InvalidIfMatch", "Invalid 'If-Match' header, '" _ sent _ "', must be formatted as 'W/""[versionId]""'")
}

ClassMethod IfMatchViolation(asked As %String, current As %String) As %String
{
    Quit ..Issue("error", "concurrency", "<HSFHIRErr>IfMatchViolation", "The version in the 'If-Match' header, '" _ asked _ "', does not match the current version, '" _ current _ "'")
}

ClassMethod InvalidUpdateId() As %String
{
    Quit ..Issue("error", "invalid", "<HSFHIRErr>InvalidUpdateId", "The id in the updated resource is missing or does not match the requested Id")
}

ClassMethod UnexpectedProperty(name As %String, type As %String) As %String
{
    Quit ..Issue("error", "invalid", "<HSFHIRErr>UnexpectedPropertyName", "The property name '" _ name _ "' is not valid for type '" _ type _ "'", type)
}

/// A code outside its value set: <var>owner</var> is the element's type as IRIS names it ("Encounter.location"),
/// <var>allowed</var> the codes in the order IRIS lists them, <var>expression</var> the element's path.
ClassMethod NotInEnumeration(value As %String, property As %String, owner As %String, allowed As %String, expression As %String) As %String
{
    Quit ..Issue("error", "invalid", "<HSFHIRErr>ValueNotInEnumeration", "The value '" _ value _ "' of Property '" _ property _ "' of Type '" _ owner _ "' must be one of (" _ allowed _ ")", expression)
}

/// A history <code>_count</code> of 0 or not a number (the closing quote and full stop are IRIS's).
ClassMethod InvalidCount(value As %String) As %String
{
    Quit ..Issue("warning", "value", "<HSFHIRErr>InvalidParameterValue", "The value '" _ value _ "' is invalid for the '_count' parameter'.")
}

ClassMethod InvalidSummary(value As %String) As %String
{
    Quit ..Issue("error", "invalid", "<HSFHIRErr>InvalidQueryParameterValue", "The value '" _ value _ "' is invalid for query parameter '_summary'.")
}

ClassMethod TypeHistory(type As %String) As %String
{
    Quit ..Issue("error", "not-supported", "<HSFHIRErr>InteractionNotSupported", "Interaction 'history-type' is not supported for resource type '" _ type _ "'.")
}

ClassMethod SystemHistory() As %String
{
    Quit ..Issue("error", "not-supported", "<HSFHIRErr>SystemInteractionNotSupported", "FHIR system-level 'history-system' interaction not supported on this end point")
}

/// A search parameter modifier (the text is IRIS's, its missing closing quote included).
ClassMethod UnsupportedModifier(modifier As %String, param As %String) As %String
{
    Quit ..Issue("error", "not-supported", "<HSFHIRErr>UnsupportedParameterModifier", "Unsupported modifier '" _ modifier _ "' on param '" _ param)
}

/// <code>$meta</code>, <code>$meta-add</code> and <code>$meta-delete</code> on an instance, which IRIS does not offer.
ClassMethod OperationNotSupported(operation As %String) As %String
{
    Quit ..Issue("error", "not-supported", "<HSFHIRErr>OperationNotSupported", "The operation '" _ operation _ "' is not supported for the 'Instance' scope.")
}

/// What IRIS implements and this server does not: create by POST, PATCH, transactions, conditional interactions,
/// other resource types, other operations and parameters.
ClassMethod NotImplemented(what As %String) As %String
{
    Quit ..Issue("error", "not-supported", "<FacadeErr>NotImplemented", what _ " is not implemented by the test FHIR server")
}

/// A body this server cannot store (not a JSON object, the wrong resourceType, meta not an object). Not measured on
/// IRIS.
ClassMethod Unreadable(why As %String) As %String
{
    Quit ..Issue("error", "structure", "<FacadeErr>InvalidResource", why)
}

/// A search page asked for a query id this server does not hold. Not measured on IRIS.
ClassMethod UnknownQuery(qid As %String) As %String
{
    Quit ..Issue("error", "not-found", "<FacadeErr>UnknownQuery", "No search with queryId '" _ qid _ "'")
}

/// Anything that went wrong inside this server.
ClassMethod Failure(text As %String) As %String
{
    Quit ..Issue("fatal", "exception", "<FacadeErr>Failure", text)
}

}
