/// The hook a watched production gets (docs/CONTRACTS.md, section 11): a business operation that hands Shutter a
/// failed delivery through POST /api/shutter/intake, with the HL7 message's text and where the original lives (this
/// namespace, this production, the receiving service, the header id), so that Shutter opens a case for a production
/// it does not own.
/// How a production calls it: the process that delivers to a receiver sends, on a failed delivery, a
/// Shutter.Intake.Forward to this item, asynchronously so that the feed never waits for Shutter, with the failed
/// message's header id (..%PrimaryRequestHeader.%Id() in a business process), the item that delivered, the failure
/// kind (delivery_failed, rejected, uncertain_outcome or unmappable), its text, and the connector's outcome, HTTP
/// status and reason code. Hospital.Process.PASToDownstream is the worked example. The item's adapter settings name
/// Shutter's instance: HTTPServer, HTTPPort, SSLConfig and Credentials (a user holding the Shutter_Forwarder role);
/// Shutter.Util is the one other package the namespace needs (Shutter.Setup.OnboardApply maps both).
/// Since v1.34 ("prevent failures") the item is also an HL7 service's BadMessageHandler: a message the service refused
/// before routing it arrives as itself and is forwarded as a failure of kind unreadable, reason schema_unknown when its
/// schema category is not loaded in this namespace (Shutter holds the case and releases it once the schema is imported
/// here) or invalid_message when it does not validate against a schema that is loaded. Nothing was delivered: the engine
/// held the message. HeldReceiver names the receiver such a message was bound for; empty, Shutter's connector item.
/// It never retries and never fails the message: a refusal is in the response's Error and in the event log as a
/// warning; the sending process decides what to do with it.
Class Shutter.Intake.Forwarder Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// The intake route's path on Shutter's instance.
Property IntakePath As %String(MAXLEN = 200) [ InitialExpression = "/api/shutter/intake" ];

/// The name this production is reported under. Empty: the running production's name.
Property SourceProduction As %String(MAXLEN = 128);

/// The namespace this production is reported under. Empty: the namespace the forwarder runs in.
Property SourceNamespace As %String(MAXLEN = 64);

/// The HL7 schema category Shutter parses the message under. Empty: the message's own category, else 2.5.1.
Property SchemaCategory As %String(MAXLEN = 64);

/// The receiver a message refused by the service was bound for (v1.34), as the site profile names it. Empty: Shutter's
/// connector item.
Property HeldReceiver As %String(MAXLEN = 128);

/// Put in front of every receiver's name, with a space (v1.42), as the site profile names it: for a namespace whose item has the name of
/// another namespace's, since one name would pool their cases and incidents and give them one profile entry. Onboarding
/// sets it when a name is taken. Empty: the item's own name.
Property ReceiverPrefix As %String(MAXLEN = 64);

Parameter SETTINGS = "IntakePath:Shutter,SourceProduction:Shutter,SourceNamespace:Shutter,SchemaCategory:Shutter,HeldReceiver:Shutter,ReceiverPrefix:Shutter";

Method OnForward(request As Shutter.Intake.Forward, Output response As Shutter.Intake.Forwarded) As %Status
{
    Set response = ##class(Shutter.Intake.Forwarded).%New()
    Set ..Retry = 0
    Set msg = ..OpenMessage(request.HeaderId, .header, .problem)
    If '$ISOBJECT(msg) Quit ..Refused(response, problem)
    Quit ..Send(request, msg, header, response)
}

/// A message the receiving service refused before routing it (v1.34): the service's BadMessageHandler names this item and
/// the message arrives as itself, under the header of that send.
Method OnBadMessage(request As EnsLib.HL7.Message, Output response As Shutter.Intake.Forwarded) As %Status
{
    Set response = ##class(Shutter.Intake.Forwarded).%New()
    Set ..Retry = 0
    Set header = ..%RequestHeader
    If '$ISOBJECT(header) Quit ..Refused(response, "The refused message came with no header")
    Quit ..Send(..ForwardFor(request, header, ..HeldReceiver), request, header, response)
}

/// The forward a refused message gets (a class method, so a test can read it): kind unreadable; reason schema_unknown and
/// a "Held:" text when the message's schema category (Shutter.Util.Schemas.CategoryOf) is not loaded in this namespace,
/// else invalid_message; the route is the service that refused it, the receiver the one given.
ClassMethod ForwardFor(msg As EnsLib.HL7.Message, header As Ens.MessageHeader, receiver As %String = "") As Shutter.Intake.Forward
{
    Set f = ##class(Shutter.Intake.Forward).%New()
    Set f.HeaderId = header.%Id()
    Set f.Route = header.SourceConfigName
    Set f.Receiver = receiver
    Set f.FailureKind = "unreadable", f.FailureOutcome = ""
    Set category = ##class(Shutter.Util.Schemas).CategoryOf(msg, header.SourceConfigName)
    Set shown = $SELECT(category = "": "(none)", 1: category)
    If '##class(Shutter.Util.Schemas).Known(category) {
        Set f.FailureReasonCode = "schema_unknown"
        Set f.FailureText = "Held: the schema " _ shown _ " is not loaded in " _ $NAMESPACE _ "; import it there and set the inbound item's category, and the case is released"
    } Else {
        Set f.FailureReasonCode = "invalid_message"
        Set f.FailureText = "Refused by the receiving service: the message does not validate against the " _ shown _ " schema, so nothing was delivered"
    }
    Quit f
}

/// The forward itself: the message's text and where it lives, posted to Shutter's intake; the answer into the response.
Method Send(request As Shutter.Intake.Forward, msg As EnsLib.HL7.Message, header As Ens.MessageHeader, response As Shutter.Intake.Forwarded) As %Status [ Private ]
{
    Set osc = $$$OK
    Set text = msg.OutputToString(, , .osc)
    If $$$ISERR(osc) Quit ..Refused(response, "The HL7 message " _ header.MessageBodyId _ " could not be written out: " _ $SYSTEM.Status.GetErrorText(osc))
    Set route = request.Route
    If route = "" Set route = header.SourceConfigName
    Set category = ..SchemaCategory
    If category = "" Set category = msg.DocTypeCategory
    // A refused message (v1.34) names the category it was held for, which its route may never have set.
    If (category = "") && (request.FailureKind = "unreadable") Set category = ##class(Shutter.Util.Schemas).CategoryOf(msg, header.SourceConfigName)
    If category = "" Set category = "2.5.1"
    Set body = ..IntakeBody(request, ..ReportedNamespace(), ..ReportedProduction(), route, text, category)
    $$$TRACE("Forwarding header " _ request.HeaderId _ " (" _ request.FailureKind _ " at " _ request.Receiver _ ") to " _ ..IntakePath)
    Set http = ##class(%Net.HttpRequest).%New()
    Set http.ContentType = "application/json"
    Do http.SetHeader("X-Requested-With", "Shutter")
    Do http.EntityBody.Write(body.%ToJSON())
    Set sc = ..Adapter.SendFormDataArray(.httpResponse, "POST", http, "", "", ..IntakePath)
    Set ..Retry = 0
    Set status = "", answer = ""
    If $ISOBJECT($GET(httpResponse)) {
        Set status = +httpResponse.StatusCode
        If $ISOBJECT(httpResponse.Data) {
            Do httpResponse.Data.Rewind()
            While 'httpResponse.Data.AtEnd { Set answer = answer _ httpResponse.Data.Read(32000) }
        }
    }
    Set parsed = ##class(Shutter.Util.Json).Parse(answer, .psc)
    If '$ISOBJECT(parsed) || $$$ISERR(psc) || 'parsed.%IsA("%DynamicObject") Set parsed = {}
    If status = 202 {
        Set response.CaseId = ##class(Shutter.Util.Json).Str(parsed, "caseId")
        Set response.State = ##class(Shutter.Util.Json).Str(parsed, "state")
        Set response.Opened = ##class(Shutter.Util.Json).Bool(parsed, "opened")
        $$$TRACE("Shutter case " _ response.CaseId _ $SELECT(response.Opened: " opened", 1: " updated") _ ", state " _ response.State)
        Quit $$$OK
    }
    Quit ..Refused(response, ..RefusalWords(status, sc, answer, ..IntakePath))
}

/// Why a forward did not open a case. A request nobody answered reads 0 here, since status is +StatusCode, and an empty
/// status when there was no response object at all; both keep the adapter's reason.
ClassMethod RefusalWords(status As %String, sc As %Status, answer As %String, path As %String) As %String
{
    If +status = 0 Quit "No answer from Shutter at " _ path _ ": " _ $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no response")
    Quit "HTTP " _ status _ " from Shutter: " _ $SELECT(answer '= "": $EXTRACT(answer, 1, 2000), 1: "empty body")
}

/// The HL7 message behind a header id, or "" with the problem said. The body must be an EnsLib.HL7.Message or a
/// class that extends it.
Method OpenMessage(headerId As %String, Output header As Ens.MessageHeader, Output problem As %String) As EnsLib.HL7.Message [ Private ]
{
    Set header = "", problem = ""
    If headerId = "" Set problem = "No header id on the forward request" Quit ""
    Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
    If '$ISOBJECT(header) Set problem = "No message header " _ headerId _ " in " _ $NAMESPACE Quit ""
    Set cls = header.MessageBodyClassName
    Set msg = ""
    Try {
        If (cls '= "") && $CLASSMETHOD(cls, "%Extends", "EnsLib.HL7.Message") Set msg = $CLASSMETHOD(cls, "%OpenId", header.MessageBodyId)
    } Catch ex {
        Set msg = ""
    }
    If '$ISOBJECT(msg) Set problem = "Header " _ headerId _ " carries " _ $SELECT(cls = "": "no body", 1: "a " _ cls _ " body (id " _ header.MessageBodyId _ ")") _ ", not an HL7 message that can be opened"
    Quit msg
}

/// The intake request's body (CONTRACTS 11), field for field.
Method IntakeBody(request As Shutter.Intake.Forward, namespace As %String, production As %String, route As %String, text As %String, category As %String) As %DynamicObject [ Private ]
{
    Set body = {}
    Set source = {}
    Set source.namespace = namespace
    Set source.production = production
    Set source.route = route
    Set source."header_id" = request.HeaderId
    Set body.source = source
    Set body.receiver = ..ReportedReceiver(request.Receiver, ..ReceiverPrefix)
    Set failure = {}
    Set failure.kind = request.FailureKind
    Set failure.text = request.FailureText
    Set failure.outcome = request.FailureOutcome
    If request.FailureHttpStatus '= "" { Do failure.%Set("http_status", +request.FailureHttpStatus, "number") } Else { Do failure.%Set("http_status", "", "null") }
    Set failure."reason_code" = request.FailureReasonCode
    Set body.failure = failure
    Set body.message = text
    Set body."schema_category" = category
    Quit body
}

/// The receiver as the site profile names it: the prefix and a space in front of the item's name, an empty name left empty (Shutter's
/// connector item then).
ClassMethod ReportedReceiver(receiver As %String, prefix As %String = "") As %String
{
    If (receiver = "") || (prefix = "") Quit receiver
    Quit prefix _ " " _ receiver
}

/// The namespace reported as the source: the setting, else the one this item runs in.
Method ReportedNamespace() As %String [ Private ]
{
    If ..SourceNamespace '= "" Quit ..SourceNamespace
    Quit $NAMESPACE
}

/// The production reported as the source: the setting, else the running production's name.
Method ReportedProduction() As %String [ Private ]
{
    If ..SourceProduction '= "" Quit ..SourceProduction
    Set name = ""
    Set sc = ##class(Ens.Director).GetProductionStatus(.name, .state)
    Quit $GET(name)
}

/// Shutter took nothing: the reason goes into the response and the event log; the message itself is not failed.
Method Refused(response As Shutter.Intake.Forwarded, reason As %String) As %Status [ Private ]
{
    Set response.Error = reason
    $$$LOGWARNING("Shutter did not take the failure: " _ reason)
    Quit $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Intake.Forward">
    <Method>OnForward</Method>
  </MapItem>
  <MapItem MessageType="EnsLib.HL7.Message">
    <Method>OnBadMessage</Method>
  </MapItem>
</MapItems>
}

}
