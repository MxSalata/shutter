/// The case intake from another production (CONTRACTS 11): an ExternalIntake carries a failed HL7 message as text,
/// where it came from and how its delivery failed. The message is parsed under the schema category the intake names
/// (2.5.1 when it names none) and sent to the store item, so it has an Ens.MessageHeader in this namespace as the
/// feed's own messages have (the evidence, the model view and the index read it there); it is mapped to an operation
/// as the feed maps its own; and the case is opened through the case workflow, synchronously, so this process's
/// answer is the workflow's CaseStarted and the REST route can return the case id. The failure kind is the source's
/// own judgement and is trusted (the route refuses an unknown one); a message that does not map becomes an unmappable
/// case, as in the feed, with the source's text kept.
Class Shutter.Process.Intake Extends Ens.BusinessProcess
{

/// The adapterless operation that receives the stored copy of the message.
Property StoreTarget As %String(MAXLEN = 128) [ InitialExpression = "Case Intake Store" ];

/// The case workflow item.
Property CaseTarget As %String(MAXLEN = 128) [ InitialExpression = "Case Workflow" ];

/// Seconds to wait for the store and for the case workflow's answer.
Property WaitSeconds As %Integer [ InitialExpression = 30 ];

Parameter SETTINGS = "StoreTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},CaseTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},WaitSeconds:Basic";

/// The investigation mode of a case from this intake (v1.38): the mode the request names; else, for a failure from a
/// watched production (CONTRACTS 11: the forwarder's and the alert intake's requests name their source namespace), the
/// site's watched mode, ^Shutter.Config("watchedMode"), policy unless a site sets another, so the catalogue and the site
/// profile settle such cases whatever mode the demo's scenarios run in (a scenario run sets the global mode, and a reset
/// puts it back to board); else the global mode of the scenario runs.
ClassMethod ModeFor(request As Shutter.Msg.ExternalIntake) As %String
{
    If request.Mode '= "" Quit request.Mode
    If request.SourceNamespace '= "" Quit $GET(^Shutter.Config("watchedMode"), "policy")
    Quit $GET(^Shutter.Config("mode"), "board")
}

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    If 'request.%IsA("Shutter.Msg.ExternalIntake") Quit $$$ERROR($$$GeneralError, "Case Intake expects an external intake, got " _ $CLASSNAME(request))
    // 1. Shutter's own copy of the message: parsed under the named category and sent to the store item, so it has a
    // message header in this namespace. The header of that send is the case's source header.
    Set msg = ..ParseMessage(request.MessageText, request.SchemaCategory, .sc)
    If $$$ISERR(sc) Quit sc
    Set sc = msg.%Save()
    If $$$ISERR(sc) Quit sc
    Set sc = ..SendRequestSync(..StoreTarget, msg, .stored, ..WaitSeconds)
    If $$$ISERR(sc) Quit $$$ERROR($$$GeneralError, "The message could not be stored: " _ $SYSTEM.Status.GetErrorText(sc))
    Set headerId = ..StoredHeaderId(msg)
    If headerId = "" Quit $$$ERROR($$$GeneralError, "The stored message has no header in session " _ ..%SessionId)
    $$$TRACE("Stored the message from " _ request.SourceNamespace _ " (" _ request.SourceProduction _ ", " _ request.SourceRoute _ ", header " _ request.OriginHeaderId _ ") as header " _ headerId)
    // 2. The operation, as the feed builds it. A message that does not map is a case too (the feed's rule): the kind
    // becomes unmappable and the text says why, with what the source reported after it.
    Set kind = request.FailureKind, text = request.FailureText
    // A message the source held for a schema it lacks (v1.34, "prevent failures") keeps its kind and the category it waits
    // for, so the index's check releases the case once that namespace has the schema.
    Set heldSchema = $SELECT((kind = "unreadable") && (request.FailureReasonCode = "schema_unknown"): request.SchemaCategory, 1: "")
    Set op = ##class(Shutter.Util.OperationKey).FromHL7(msg, .osc)
    If $$$ISERR(osc) || '$ISOBJECT(op) {
        Set op = ##class(Shutter.Util.OperationKey).Unmapped(msg, headerId)
        If kind '= "unreadable" {
            Set kind = "unmappable"
            Set text = "The message could not be mapped to an operation for the downstream system: " _ $SYSTEM.Status.GetErrorText(osc) _ $SELECT(text '= "": ". The source reported: " _ text, 1: "")
        }
    }
    // 3. The case, through the case workflow, synchronously: its CaseStarted is this process's answer.
    Set intake = ##class(Shutter.Msg.CaseIntake).%New()
    Set intake.OperationJSON = op.%ToJSON()
    Set intake.FailureKind = kind
    Set intake.FailureText = $EXTRACT(text, 1, 2000)
    Set intake.FailureReasonCode = request.FailureReasonCode
    Set intake.HeldSchema = heldSchema
    Set intake.SourceHeaderId = headerId
    Set intake.EnsSessionId = ..%SessionId
    Set intake.Mode = ..ModeFor(request)
    // The receiver's answer as the source saw it, structured, when it reported one: the matcher reads it, never prose.
    If (request.FailureOutcome '= "") || (request.FailureReasonCode '= "") || (request.FailureHttpStatus '= "") {
        Set r = {}
        Set r.outcome = request.FailureOutcome, r."reason_code" = request.FailureReasonCode
        If request.FailureHttpStatus '= "" Do r.%Set("http_status", +request.FailureHttpStatus, "number")
        Set intake.WardResultJSON = r.%ToJSON()
    }
    Set intake.Receiver = request.Receiver
    Set intake.SourceNamespace = request.SourceNamespace, intake.SourceProduction = request.SourceProduction
    Set intake.SourceRoute = request.SourceRoute, intake.OriginHeaderId = request.OriginHeaderId
    $$$TRACE("Case intake for " _ ##class(Shutter.Util.Json).Str(op, "operation_key") _ " (" _ kind _ ", receiver " _ request.Receiver _ ") sent to " _ ..CaseTarget)
    Set sc = ..SendRequestSync(..CaseTarget, intake, .started, ..WaitSeconds)
    If $$$ISERR(sc) Quit sc
    If '$ISOBJECT($GET(started)) || 'started.%IsA("Shutter.Msg.CaseStarted") Quit $$$ERROR($$$GeneralError, "The case workflow did not answer the intake")
    Set response = started
    $$$TRACE("Case " _ started.CaseId _ $SELECT(started.Opened: " opened", 1: " updated") _ ", state " _ started.State)
    Quit $$$OK
}

/// The HL7 message from its text, with its DocType set for the category (2.5.1 when the intake names none; the
/// default category again when the named one does not resolve). Segments may arrive separated by CR, CRLF or LF: the
/// parser wants CR. An unknown category or structure leaves the type unset: the message is kept and mapped all the
/// same, and the evidence's validation says so.
Method ParseMessage(text As %String, category As %String, Output sc As %Status) As EnsLib.HL7.Message
{
    Set sc = $$$OK
    Set text = $REPLACE(text, $CHAR(13, 10), $CHAR(13))
    If '(text [ $CHAR(13)) Set text = $TRANSLATE(text, $CHAR(10), $CHAR(13))
    If $ZSTRIP(text, "<>WC") = "" Set sc = $$$ERROR($$$GeneralError, "The intake carries no message") Quit ""
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString(text, .sc)
    If $$$ISERR(sc) Quit ""
    If '$ISOBJECT($GET(msg)) Set sc = $$$ERROR($$$GeneralError, "The message could not be parsed") Quit ""
    If $ZSTRIP(category, "<>W") = "" Set category = "2.5.1"
    Set docType = ""
    Try {
        Set docType = ##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType(category, msg.Name, .dsc)
        If ($$$ISERR(dsc) || (docType = "")) && (category '= "2.5.1") Set docType = ##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType("2.5.1", msg.Name, .dsc)
        If $$$ISERR(dsc) Set docType = ""
    } Catch ex {
        Set docType = ""
    }
    If docType '= "" Do msg.PokeDocType(docType)
    Quit msg
}

/// The Ens.MessageHeader id of the copy this process sent to the store in this session (the newest when there are
/// several), or "".
Method StoredHeaderId(msg As EnsLib.HL7.Message) As %String
{
    Set bodyId = msg.%Id(), sid = ..%SessionId, id = ""
    If bodyId = "" Quit ""
    &sql(SELECT TOP 1 ID INTO :id FROM Ens.MessageHeader WHERE MessageBodyClassName = 'EnsLib.HL7.Message' AND MessageBodyId = :bodyId AND SessionId = :sid ORDER BY ID DESC)
    If SQLCODE '= 0 Quit ""
    Quit id
}

Storage Default
{
<Data name="IntakeDefaultData">
<Subscript>"Intake"</Subscript>
<Value name="1">
<Value>StoreTarget</Value>
</Value>
<Value name="2">
<Value>CaseTarget</Value>
</Value>
<Value name="3">
<Value>WaitSeconds</Value>
</Value>
</Data>
<DefaultData>IntakeDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
