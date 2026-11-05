/// The feed: turns an ADT message into a downstream operation, delivers it through the connector, and
/// opens a case when the delivery failed or its outcome is uncertain. The delivery's failure is
/// reported as this message's error, so the trace shows it; the case is opened first.
/// Not every message is delivered (CONTRACTS 2): a registration, a pre-admission or a person update is recorded by
/// the index and answered OK with no case; a merge goes out only when the site allows merges and the receiver takes
/// them, a cancel only to a receiver that can reverse the event. Otherwise the operation is withheld: a case of kind
/// withheld is opened for a person, the message is handled (no error) and the feed goes on.
Class Shutter.Process.ADTToWard Extends Ens.BusinessProcess
{

/// The connector item.
Property WardTarget As %String(MAXLEN = 128) [ InitialExpression = {$PARAMETER("Shutter.Production", "RECEIVER")} ];

/// The case workflow item.
Property CaseTarget As %String(MAXLEN = 128) [ InitialExpression = "Case Workflow" ];

/// Seconds to wait for the connector.
Property DeliveryTimeout As %Integer [ InitialExpression = 60 ];

Parameter SETTINGS = "WardTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},CaseTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},DeliveryTimeout:Basic";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    If 'request.%IsA("EnsLib.HL7.Message") Quit $$$ERROR($$$GeneralError, "ADT to Downstream expects an HL7 message, got " _ $CLASSNAME(request))
    // The hold (v1.34, "prevent failures"; CONTRACTS 12): with the site's setting on, a message whose schema category is not
    // loaded here is held as a case of kind unreadable and nothing is delivered, since fields read by position from a schema
    // this namespace lacks could be the wrong fields. The case names the category and the fix, and the index's check
    // releases it once the schema is imported. The message is handled, not failed, so the feed goes on.
    If ##class(Shutter.Store.SiteProfile).PreventFailures() {
        Set category = ##class(Shutter.Util.Schemas).CategoryOf(request, ..%PrimaryRequestHeader.SourceConfigName)
        If '##class(Shutter.Util.Schemas).Known(category) {
            Set shown = $SELECT(category = "": "(none)", 1: category)
            Set op = ##class(Shutter.Util.OperationKey).FromCanonical(request, ..%PrimaryRequestHeader.%Id(), .csc)
            Set text = "Held: the schema " _ shown _ " is not loaded here; import it and set the inbound item's category, and the case is released"
            $$$TRACE(text _ $SELECT($$$ISERR(csc): " (the message could not be read as 2.5.1 either: " _ $SYSTEM.Status.GetErrorText(csc) _ ")", 1: ""))
            Do ..OpenCase(op, "unreadable", text, "", "schema_unknown", category)
            Quit $$$OK
        }
    }
    Set op = ##class(Shutter.Util.OperationKey).FromHL7(request, .sc)
    If $$$ISERR(sc) {
        // A message Shutter cannot map (an unsupported trigger, a missing identifier or time) is a case too: the
        // failure stands, and a person sees it with the message's fields rather than finding it only in the event log.
        Set text = "The message could not be mapped to an operation for the downstream system: " _ $SYSTEM.Status.GetErrorText(sc)
        Do ..OpenCase(##class(Shutter.Util.OperationKey).Unmapped(request, ..%PrimaryRequestHeader.%Id()), "unmappable", text, "", "")
        Quit sc
    }
    Set event = ##class(Shutter.Util.Json).Str(op, "event"), key = ##class(Shutter.Util.Json).Str(op, "operation_key")
    Set how = ##class(Shutter.Util.OperationKey).DeliveryOf(event)
    // Indexed only: the HL7 Index item records the message with its event word; nothing goes to the receiver.
    If how = "index" {
        $$$TRACE("Recorded, not delivered: " _ event _ " " _ key)
        Quit $$$OK
    }
    // A merge or a cancel the site or the receiver does not take is withheld, never sent: a person decides. The
    // withheld message is handled, not failed, so the feed goes on.
    If (how = "merge") || (how = "cancel") {
        Set entry = ##class(Shutter.Store.SiteProfile).Receiver(..WardTarget)
        If how = "merge" {
            Set allowed = ##class(Shutter.Store.SiteProfile).MergesAllowed() && ##class(Shutter.Util.Json).Bool(entry, "merges")
            Set text = "Withheld by the site's policy: merges go to the PAS team", code = "merge"
        } Else {
            Set allowed = ##class(Shutter.Util.Json).Bool(entry, "cancels")
            Set text = "Withheld: the receiver cannot reverse the " _ ##class(Shutter.Operation.Gate).Reversed(event), code = "cancel_unsupported"
        }
        If 'allowed {
            $$$TRACE(text _ " (" _ key _ ")")
            Do ..OpenCase(op, "withheld", text, "", code)
            Quit $$$OK
        }
    }
    Set wardOp = ##class(Shutter.Msg.WardOperation).FromOperation(op)
    Set wardOp.Purpose = "normal"
    Set wardOp.SourceHeaderId = ..%PrimaryRequestHeader.%Id()
    $$$TRACE("Operation " _ wardOp.OperationKey _ " (" _ wardOp.Event _ $SELECT(wardOp.Ward '= "": " to " _ wardOp.Ward, 1: "") _ $SELECT(wardOp.Bed '= "": " bed " _ wardOp.Bed, 1: "") _ ")")
    Set sc = ..SendRequestSync(..WardTarget, wardOp, .result, ..DeliveryTimeout)
    If $$$ISERR(sc) || '$ISOBJECT($GET(result)) {
        Set text = "The connector did not answer: " _ $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no response")
        Do ..OpenCase(op, "uncertain_outcome", text, "", "")
        Quit $$$ERROR($$$GeneralError, text)
    }
    Set response = result
    If result.IsInEffect() {
        $$$TRACE("Delivered: " _ result.Outcome _ " (HTTP " _ result.HttpStatus _ ", version " _ result.EncounterVersion _ ")")
        Quit $$$OK
    }
    Set kind = $CASE(result.Outcome, "uncertain": "uncertain_outcome", "unavailable": "delivery_failed", "error": "delivery_failed", : "rejected")
    Set text = "Delivery " _ result.Outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "") _ $SELECT(+result.HttpStatus: ", HTTP " _ result.HttpStatus, 1: "") _ $SELECT(result.Error '= "": ": " _ result.Error, 1: "")
    Set sent = ..OpenCase(op, kind, text, result, "")
    Quit $$$ERROR($$$GeneralError, text _ $SELECT(sent '= "": ". A case was opened", 1: ". No case could be opened"))
}

/// Send the intake to the case workflow asynchronously; returns the case id when the workflow
/// answered within a short wait, else "". reasonCode is the feed's own reason for a case with no connector answer
/// (merge, cancel_unsupported); the connector's reason code travels in the result.
Method OpenCase(op As %DynamicObject, kind As %String, text As %String, result As Shutter.Msg.WardResult, reasonCode As %String = "", heldSchema As %String = "") As %String
{
    Set intake = ##class(Shutter.Msg.CaseIntake).%New()
    Set intake.OperationJSON = op.%ToJSON()
    Set intake.FailureKind = kind
    Set intake.FailureText = text
    Set intake.FailureReasonCode = reasonCode
    Set intake.HeldSchema = heldSchema
    Set intake.SourceHeaderId = ..%PrimaryRequestHeader.%Id()
    Set intake.EnsSessionId = ..%SessionId
    Set intake.Mode = $GET(^Shutter.Config("mode"), "board")
    // The connector this process delivers to: the case's receiver, whose profile entry the evidence, the gate, the
    // rehearsal and the write read (v1.25: a second receiver is configuration).
    Set intake.Receiver = ..WardTarget
    If $ISOBJECT(result) {
        Set r = {}
        Set r."http_status" = result.HttpStatus, r.outcome = result.Outcome, r."reason_code" = result.ReasonCode
        Set r.response = result.ResponseObject(), r.error = result.Error
        If result.RetryAfterSeconds '= "" Set r."retry_after_seconds" = result.RetryAfterSeconds
        Set intake.WardResultJSON = r.%ToJSON()
    }
    // Asynchronous on purpose: the feed must never wait for an investigation.
    Set sc = ..SendRequestAsync(..CaseTarget, intake, 1, "intake")
    If $$$ISERR(sc) {
        $$$LOGWARNING("Could not open a case: " _ $SYSTEM.Status.GetErrorText(sc))
        Quit ""
    }
    $$$TRACE("Case intake sent to " _ ..CaseTarget)
    Quit "pending"
}

Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, completionkey As %String) As %Status
{
    If (completionkey = "intake") && $ISOBJECT(callresponse) && callresponse.%IsA("Shutter.Msg.CaseStarted") {
        $$$TRACE("Case " _ callresponse.CaseId _ $SELECT(callresponse.Opened: " opened", 1: " updated") _ ", state " _ callresponse.State)
    }
    Quit $$$OK
}

Storage Default
{
<Data name="ADTToWardDefaultData">
<Subscript>"ADTToWard"</Subscript>
<Value name="1">
<Value>WardTarget</Value>
</Value>
<Value name="2">
<Value>CaseTarget</Value>
</Value>
<Value name="3">
<Value>DeliveryTimeout</Value>
</Value>
</Data>
<DefaultData>ADTToWardDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
