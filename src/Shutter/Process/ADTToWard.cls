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
    Set op = ##class(Shutter.Util.OperationKey).FromHL7(request, .sc)
    If $$$ISERR(sc) {
        // A message Shutter cannot map (an unsupported trigger, a missing identifier or time) is a case too: the
        // failure stands, and a person sees it with the message's fields rather than finding it only in the event log.
        Set text = "The message could not be mapped to an operation for the downstream system: " _ $SYSTEM.Status.GetErrorText(sc)
        Do ..OpenCase(..UnmappedOperation(request), "unmappable", text, "", "")
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
            Set cancelled = $PIECE(event, "_", 2)
            Set text = "Withheld: the receiver cannot reverse " _ $SELECT(cancelled = "admit": "an ", 1: "a ") _ cancelled, code = "cancel_unsupported"
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
    $$$TRACE("Operation " _ wardOp.OperationKey _ " (" _ wardOp.Event _ $SELECT(wardOp.Ward '= "": " to " _ wardOp.Ward, 1: "") _ ")")
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
    Set text = "Delivery " _ result.Outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "") _ $SELECT(result.HttpStatus '= "": ", HTTP " _ result.HttpStatus, 1: "") _ $SELECT(result.Error '= "": ": " _ result.Error, 1: "")
    Set sent = ..OpenCase(op, kind, text, result, "")
    Quit $$$ERROR($$$GeneralError, text _ $SELECT(sent '= "": ". A case was opened", 1: ". No case could be opened"))
}

/// The operation record of a message that does not map: what the message says, with a key of its own
/// (UNMAPPED^<header id>), so the case can hold it.
Method UnmappedOperation(request As EnsLib.HL7.Message) As %DynamicObject
{
    Set op = {}
    Set headerId = ..%PrimaryRequestHeader.%Id()
    Set op."operation_key" = "UNMAPPED^" _ headerId
    Set op."encounter_id" = ##class(Shutter.Util.OperationKey).Value(request, "PV1", "19.1")
    Set op."patient_id" = ##class(Shutter.Util.OperationKey).PatientIdentifier(request, .authority)
    Set op."patient_id_authority" = authority
    Set trigger = request.GetValueAt("MSH:9.2")
    Set op."event" = $SELECT(trigger = "": "", 1: trigger)
    Set ward = ##class(Shutter.Util.OperationKey).Value(request, "PV1", "3.1")
    If ward '= "" { Set op."ward" = ward } Else { Do op.%Set("ward", "", "null") }
    Set raw = request.GetValueAt("EVN:6.1")
    If raw = "" Set raw = request.GetValueAt("EVN:2.1")
    If raw = "" Set raw = request.GetValueAt("MSH:7.1")
    Set when = ##class(Shutter.Util.Time).FromHL7(raw)
    Set op."event_time" = $SELECT(when = "": ##class(Shutter.Util.Time).NowUTC(), 1: when)
    Set op."source_system" = request.GetValueAt("MSH:3.1")
    Set op."source_message_id" = request.GetValueAt("MSH:10")
    Set op."payload_digest" = ""
    Quit op
}

/// Send the intake to the case workflow asynchronously; returns the case id when the workflow
/// answered within a short wait, else "". reasonCode is the feed's own reason for a case with no connector answer
/// (merge, cancel_unsupported); the connector's reason code travels in the result.
Method OpenCase(op As %DynamicObject, kind As %String, text As %String, result As Shutter.Msg.WardResult, reasonCode As %String = "") As %String
{
    Set intake = ##class(Shutter.Msg.CaseIntake).%New()
    Set intake.OperationJSON = op.%ToJSON()
    Set intake.FailureKind = kind
    Set intake.FailureText = text
    Set intake.FailureReasonCode = reasonCode
    Set intake.SourceHeaderId = ..%PrimaryRequestHeader.%Id()
    Set intake.EnsSessionId = ..%SessionId
    Set intake.Mode = $GET(^Shutter.Config("mode"), "board")
    If $ISOBJECT(result) {
        Set r = {}
        Set r."http_status" = result.HttpStatus, r.outcome = result.Outcome, r."reason_code" = result.ReasonCode
        Set r.response = result.ResponseObject(), r.error = result.Error
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
