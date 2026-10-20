/// The demo hospital's feed process: turns an ADT message into a ward operation, delivers it through the hospital's
/// own connector, and hands Shutter the failure when the delivery failed, was rejected, ended uncertain, or the
/// message could not be mapped. The failure is reported as this message's error too, so the hospital's trace shows it.
/// The hospital has no policy of its own: a registration or a person update is answered OK and never sent (the ward
/// system takes no such word), and a merge or a cancel goes out as it is; what the ward system refuses becomes a case
/// in Shutter like any other refusal.
Class Hospital.Process.PASToDownstream Extends Ens.BusinessProcess
{

/// The ward system's connector item; its name is the receiver Shutter is told about.
Property WardTarget As %String(MAXLEN = 128) [ InitialExpression = "Downstream Out" ];

/// The item that hands a failed delivery to Shutter.
Property ForwarderTarget As %String(MAXLEN = 128) [ InitialExpression = "Shutter Forwarder" ];

/// The service this process receives from, reported to Shutter as the route. Empty: the failed message's own header says it.
Property RouteName As %String(MAXLEN = 128) [ InitialExpression = "PAS In" ];

/// Seconds to wait for the connector.
Property DeliveryTimeout As %Integer [ InitialExpression = 60 ];

Parameter SETTINGS = "WardTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},ForwarderTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},RouteName:Basic,DeliveryTimeout:Basic";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    If 'request.%IsA("EnsLib.HL7.Message") Quit $$$ERROR($$$GeneralError, "PAS to Downstream expects an HL7 message, got " _ $CLASSNAME(request))
    Set op = ##class(Shutter.Util.OperationKey).FromHL7(request, .sc)
    If $$$ISERR(sc) {
        Set text = "The message could not be mapped to a ward operation: " _ $SYSTEM.Status.GetErrorText(sc)
        Do ..HandToShutter("unmappable", text, "", "", "")
        Quit sc
    }
    Set event = ##class(Shutter.Util.Json).Str(op, "event"), key = ##class(Shutter.Util.Json).Str(op, "operation_key")
    // A registration, a pre-admission or a person update is not a ward movement: nothing goes to the ward system.
    If ##class(Shutter.Util.OperationKey).DeliveryOf(event) = "index" {
        $$$TRACE("Not for the ward system: " _ event _ " " _ key)
        Quit $$$OK
    }
    Set wardOp = ##class(Shutter.Msg.WardOperation).FromOperation(op)
    Set wardOp.Purpose = "normal"
    Set wardOp.SourceHeaderId = ..%PrimaryRequestHeader.%Id()
    $$$TRACE("Operation " _ key _ " (" _ event _ $SELECT(wardOp.Ward '= "": " to " _ wardOp.Ward, 1: "") _ ")")
    Set sc = ..SendRequestSync(..WardTarget, wardOp, .result, ..DeliveryTimeout)
    If $$$ISERR(sc) || '$ISOBJECT($GET(result)) {
        Set text = "The ward connector did not answer: " _ $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no response")
        Do ..HandToShutter("uncertain_outcome", text, "uncertain", "", "")
        Quit $$$ERROR($$$GeneralError, text)
    }
    Set response = result
    If result.IsInEffect() {
        $$$TRACE("Delivered: " _ result.Outcome _ " (HTTP " _ result.HttpStatus _ ", version " _ result.EncounterVersion _ ")")
        Quit $$$OK
    }
    // The same words as Shutter's own feed: an uncertain answer, no answer or an error, else a refusal.
    Set kind = $CASE(result.Outcome, "uncertain": "uncertain_outcome", "unavailable": "delivery_failed", "error": "delivery_failed", : "rejected")
    Set outcome = $SELECT(kind = "rejected": "rejected", 1: result.Outcome)
    Set text = "Delivery " _ result.Outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "") _ $SELECT(result.HttpStatus '= "": ", HTTP " _ result.HttpStatus, 1: "") _ $SELECT(result.Error '= "": ": " _ result.Error, 1: "")
    Set sent = ..HandToShutter(kind, text, outcome, result.HttpStatus, result.ReasonCode)
    Quit $$$ERROR($$$GeneralError, text _ $SELECT(sent '= "": ". Handed to Shutter", 1: ". Shutter could not be told"))
}

/// Send the failure to the forwarder asynchronously, with this message's header id as the one Shutter should fetch;
/// returns "pending", or "" when the forwarder could not be reached. The feed never waits for Shutter.
Method HandToShutter(kind As %String, text As %String, outcome As %String, httpStatus As %String, reasonCode As %String) As %String
{
    Set forward = ##class(Shutter.Intake.Forward).%New()
    Set forward.HeaderId = ..%PrimaryRequestHeader.%Id()
    Set forward.Receiver = ..WardTarget
    Set forward.FailureKind = kind
    Set forward.FailureText = text
    Set forward.FailureOutcome = outcome
    If httpStatus '= "" Set forward.FailureHttpStatus = +httpStatus
    Set forward.FailureReasonCode = reasonCode
    Set forward.Route = ..RouteName
    Set sc = ..SendRequestAsync(..ForwarderTarget, forward, 1, "forward")
    If $$$ISERR(sc) {
        $$$LOGWARNING("Could not hand the failure to Shutter: " _ $SYSTEM.Status.GetErrorText(sc))
        Quit ""
    }
    $$$TRACE("Failure handed to " _ ..ForwarderTarget)
    Quit "pending"
}

Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, completionkey As %String) As %Status
{
    If (completionkey = "forward") && $ISOBJECT(callresponse) && callresponse.%IsA("Shutter.Intake.Forwarded") {
        If callresponse.Error '= "" {
            $$$LOGWARNING("Shutter did not take the failure: " _ callresponse.Error)
        } Else {
            $$$TRACE("Shutter case " _ callresponse.CaseId _ $SELECT(callresponse.Opened: " opened", 1: " updated") _ ", state " _ callresponse.State)
        }
    }
    Quit $$$OK
}

Storage Default
{
<Data name="PASToDownstreamDefaultData">
<Subscript>"PASToDownstream"</Subscript>
<Value name="1">
<Value>WardTarget</Value>
</Value>
<Value name="2">
<Value>ForwarderTarget</Value>
</Value>
<Value name="3">
<Value>RouteName</Value>
</Value>
<Value name="4">
<Value>DeliveryTimeout</Value>
</Value>
</Data>
<DefaultData>PASToDownstreamDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}
}
