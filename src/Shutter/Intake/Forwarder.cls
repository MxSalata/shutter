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
/// Shutter.Util is the one other package the namespace needs.
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

Parameter SETTINGS = "IntakePath:Shutter,SourceProduction:Shutter,SourceNamespace:Shutter,SchemaCategory:Shutter";

Method OnForward(request As Shutter.Intake.Forward, Output response As Shutter.Intake.Forwarded) As %Status
{
    Set response = ##class(Shutter.Intake.Forwarded).%New()
    Set ..Retry = 0
    Set msg = ..OpenMessage(request.HeaderId, .header, .problem)
    If '$ISOBJECT(msg) Quit ..Refused(response, problem)
    Set osc = $$$OK
    Set text = msg.OutputToString(, , .osc)
    If $$$ISERR(osc) Quit ..Refused(response, "The HL7 message " _ header.MessageBodyId _ " could not be written out: " _ $SYSTEM.Status.GetErrorText(osc))
    Set route = request.Route
    If route = "" Set route = header.SourceConfigName
    Set category = ..SchemaCategory
    If category = "" Set category = msg.DocTypeCategory
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
    If status = "" {
        Quit ..Refused(response, "No answer from Shutter at " _ ..IntakePath _ ": " _ $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no response"))
    }
    Quit ..Refused(response, "HTTP " _ status _ " from Shutter: " _ $SELECT(answer '= "": $EXTRACT(answer, 1, 2000), 1: "empty body"))
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
    Set body.receiver = request.Receiver
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
</MapItems>
}

}
