/// The intake's document path (docs/CONTRACTS.md 11.2), which the route takes before anything else reads the body: a forwarder's
/// metadata envelope, or a whole MDM T01 to T11, or ORU with an attachment, posted for a receiver with a document profile, whose
/// text is read here and dropped. Either way the case opens through the case workflow with no HL7 copy in this namespace and no text in the messages
/// stored for it. A receiver with no document profile gets the ordinary path: an envelope is answered 409 documents_off, and the
/// forwarder then sends the message as it always has.
Class Shutter.API.DocumentIntake
{

/// Whether the body is for this path. Nothing is decided for a message that is not an MDM.
ClassMethod Takes(body As %DynamicObject) As %Boolean
{
    If ##class(Shutter.Util.Json).Str(body, "kind") = "document_failure" Quit 1
    If body.%GetTypeOf("message") '= "string" Quit 0
    Set receiver = ##class(Shutter.Util.Json).Str(body, "receiver"), text = body.%Get("message")
    If ##class(Shutter.Util.DocumentFacts).IsDocumentText(text) Quit ##class(Shutter.Util.DocumentCase).Enabled(receiver)
    If '##class(Shutter.Util.DocumentCase).Enabled(receiver) Quit 0
    Quit ##class(Shutter.Util.DocumentFacts).IsReportText(text, .type) && ##class(Shutter.Util.DocumentCase).TakesReport(receiver, type)
}

/// The route's work: 202 {caseId, state, opened}, as the ordinary intake answers.
ClassMethod Post(body As %DynamicObject, bodyText As %String) As %Status
{
    Set d = "Shutter.API.Dispatch", json = "Shutter.Util.Json"
    Set receiver = $EXTRACT($CLASSMETHOD(json, "Str", body, "receiver"), 1, 128)
    If receiver = "" Quit $CLASSMETHOD(d, "Fail", "400 Bad Request", "bad_request", "receiver is required")
    If '##class(Shutter.Util.DocumentCase).Enabled(receiver) Quit $CLASSMETHOD(d, "Fail", "409 Conflict", "documents_off", "The receiver " _ receiver _ " has no document profile, so its messages take the ordinary intake")
    Set failure = $SELECT(body.%GetTypeOf("failure") = "object": body.failure, 1: "")
    If '$ISOBJECT(failure) Quit $CLASSMETHOD(d, "Fail", "400 Bad Request", "bad_request", "failure is required: an object with kind")
    Set kind = $CLASSMETHOD(json, "Str", failure, "kind")
    If '$LISTFIND($LISTBUILD("delivery_failed", "rejected", "uncertain_outcome", "unmappable", "unreadable"), kind) Quit $CLASSMETHOD(d, "Fail", "400 Bad Request", "bad_request", "failure.kind must be delivery_failed, rejected, uncertain_outcome, unmappable or unreadable")
    // A report the profile doesn't take goes the ordinary way, as a receiver with no profile does.
    If (body.%GetTypeOf("facts") = "object") && ($CLASSMETHOD(json, "Str", body.facts, "kind") = "report") && '##class(Shutter.Util.DocumentCase).TakesReport(receiver, $CLASSMETHOD(json, "Str", body.facts, "message_type")) Quit $CLASSMETHOD(d, "Fail", "409 Conflict", "documents_off", "The receiver " _ receiver _ "'s document profile does not take " _ $CLASSMETHOD(json, "Str", body.facts, "message_type") _ ", so it takes the ordinary intake")
    Set source = $SELECT(body.%GetTypeOf("source") = "object": body.source, 1: {})
    Set block = ..BlockFrom(body, receiver, source, .problem)
    If problem '= "" Quit $CLASSMETHOD(d, "Fail", "400 Bad Request", "bad_request", problem)
    Set r = $CLASSMETHOD(d, "Idempotent", bodyText, .replayed)
    If replayed Quit $$$OK
    Set outcome = $EXTRACT($CLASSMETHOD(json, "Str", failure, "outcome"), 1, 32), reason = $EXTRACT($CLASSMETHOD(json, "Str", failure, "reason_code"), 1, 100), status = $CLASSMETHOD(json, "Str", failure, "http_status")
    Set block.refusal = ##class(Shutter.Util.DocumentCase).Refusal(kind, outcome, reason, status, $CLASSMETHOD(json, "Str", failure, "text"))
    // What the case opens with, before the evidence reads the source again.
    Do ##class(Shutter.Util.DocumentCase).Conclude(block)
    Set op = ##class(Shutter.Util.DocumentCase).Operation(block)
    Set stage = ##class(Shutter.Util.DocumentCase).Stage(block)
    Set op."document_stage" = stage
    Set intake = ##class(Shutter.Msg.CaseIntake).%New()
    Set intake.OperationJSON = op.%ToJSON()
    Set intake.FailureKind = "unmappable"
    Set intake.FailureText = ##class(Shutter.Util.DocumentCase).FailureWords(block)
    Set intake.FailureReasonCode = reason
    If (outcome '= "") || (reason '= "") || (+status > 0) {
        Set w = {"outcome": (outcome), "reason_code": (reason)}
        If +status > 0 Do w.%Set("http_status", +status, "number")
        Set intake.WardResultJSON = w.%ToJSON()
    }
    Set intake.Mode = $GET(^Shutter.Config("watchedMode"), "policy")
    Set intake.Receiver = receiver
    Set intake.SourceNamespace = $EXTRACT($CLASSMETHOD(json, "Str", source, "namespace"), 1, 64), intake.SourceProduction = $EXTRACT($CLASSMETHOD(json, "Str", source, "production"), 1, 128)
    Set intake.SourceRoute = $EXTRACT($CLASSMETHOD(json, "Str", source, "route"), 1, 128), intake.OriginHeaderId = $EXTRACT($CLASSMETHOD(json, "Str", source, "header_id"), 1, 40)
    Set sc = ##class(Ens.Director).CreateBusinessService("Shutter API", .service)
    If $$$ISERR(sc) || '$ISOBJECT($GET(service)) {
        Do ##class(Shutter.Util.DocumentCase).Unstage(stage)
        Quit $CLASSMETHOD(d, "Fail", "503 Service Unavailable", "no_service", "The API service is not running: " _ $SYSTEM.Status.GetErrorText(sc))
    }
    Set service.Target = "Case Workflow", service.Async = 0
    Set sc = service.ProcessInput(intake, .started)
    // A further failure of an open case found it, so nothing took the stage.
    Do ##class(Shutter.Util.DocumentCase).Unstage(stage)
    If $$$ISERR(sc) Quit $CLASSMETHOD(d, "Fail", "503 Service Unavailable", "not_queued", "The case could not be opened: " _ $SYSTEM.Status.GetErrorText(sc))
    If '$ISOBJECT($GET(started)) || 'started.%IsA("Shutter.Msg.CaseStarted") Quit $CLASSMETHOD(d, "Fail", "503 Service Unavailable", "not_queued", "The case workflow did not answer")
    Set reply = {"caseId": (started.CaseId), "state": (started.State)}
    Do reply.%Set("opened", ''started.Opened, "boolean")
    Set text = reply.%ToJSON()
    Do $CLASSMETHOD(d, "Remember", bodyText, "202 Accepted", text)
    Set %response.Status = "202 Accepted"
    Write text
    Quit $$$OK
}

/// The block from the envelope's facts, or from the whole text, which goes no further than this method.
ClassMethod BlockFrom(body As %DynamicObject, receiver As %String, source As %DynamicObject, Output problem As %String) As %DynamicObject [ Private ]
{
    Set problem = "", json = "Shutter.Util.Json", chain = ""
    If body.%GetTypeOf("message") = "string" {
        Set facts = ##class(Shutter.Util.DocumentFacts).FromText(body.%Get("message"), .fsc)
        If '$ISOBJECT(facts) Set problem = "message could not be read: " _ $SYSTEM.Status.GetErrorText(fsc) Quit ""
    } Else {
        Set facts = $SELECT(body.%GetTypeOf("facts") = "object": body.facts, 1: "")
        If '$ISOBJECT(facts) Set problem = "facts is required: an object" Quit ""
        If body.%GetTypeOf("chain") = "object" Set chain = body.chain
    }
    If (facts.kind = "report") && (facts.%GetTypeOf("report") '= "object") Set problem = "facts.report is required: an object" Quit ""
    If (facts.kind '= "report") && '##class(Shutter.Util.DocumentFacts).IsTrigger($CLASSMETHOD(json, "Str", facts, "trigger")) Set problem = "facts.trigger must be T01 to T11" Quit ""
    If facts.%GetTypeOf("document") '= "object" Set problem = "facts.document is required: an object" Quit ""
    If facts.%GetTypeOf("patient") '= "object" Set facts.patient = {"keys": [], "binding": ""}
    If facts.%GetTypeOf("digests") '= "object" Set facts.digests = {"body": "", "content": ""}
    If facts.%GetTypeOf("size") '= "object" Set facts.size = {}
    For k = "id", "parent", "completion", "confidentiality", "availability" {
        If facts.document.%GetTypeOf(k) '= "string" Do facts.document.%Set(k, "", "string")
    }
    Set item = $CLASSMETHOD(json, "Str", source, "item")
    If item = "" {
        // The whole-text path names the receiver as the profile does: a prefix of the namespace comes off.
        Set item = receiver, ns = $CLASSMETHOD(json, "Str", source, "namespace")
        If (ns '= "") && ($EXTRACT(receiver, 1, $LENGTH(ns) + 1) = (ns _ " ")) Set item = $EXTRACT(receiver, $LENGTH(ns) + 2, *)
    }
    Set src = {"namespace": ($CLASSMETHOD(json, "Str", source, "namespace")), "production": ($CLASSMETHOD(json, "Str", source, "production")), "route": ($CLASSMETHOD(json, "Str", source, "route")), "header_id": ($CLASSMETHOD(json, "Str", source, "header_id")), "item": (item)}
    Set block = facts
    Set block.receiver = receiver, block.source = src
    Do block.%Set("source_verified", 0, "boolean")
    Set block.delivery = $SELECT(body.%GetTypeOf("delivery") = "object": body.delivery, 1: {"header_id": (src."header_id"), "status": ""})
    Do block.%Set("restricted", ##class(Shutter.Util.DocumentCase).IsRestricted(block.document.confidentiality), "boolean")
    If $ISOBJECT(chain) {
        Set block.chain = chain
    } Else {
        Set block.chain = {"note": "Not read yet", "rows": []}
        Do block.chain.%Set("complete", 0, "boolean")
    }
    Quit block
}

}
