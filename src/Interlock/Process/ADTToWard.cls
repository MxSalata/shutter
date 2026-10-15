/// The feed: turns an ADT message into a ward operation, delivers it through the connector, and
/// opens a case when the delivery failed or its outcome is uncertain. The delivery's failure is
/// reported as this message's error, so the trace shows it; the case is opened first.
Class Interlock.Process.ADTToWard Extends Ens.BusinessProcess
{

/// The connector item.
Property WardTarget As %String(MAXLEN = 128) [ InitialExpression = "Ward Out" ];

/// The case workflow item.
Property CaseTarget As %String(MAXLEN = 128) [ InitialExpression = "Case Workflow" ];

/// Seconds to wait for the connector.
Property DeliveryTimeout As %Integer [ InitialExpression = 60 ];

Parameter SETTINGS = "WardTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},CaseTarget:Basic:selector?context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},DeliveryTimeout:Basic";

Method OnRequest(request As %Library.Persistent, Output response As %Library.Persistent) As %Status
{
    Set response = ""
    If 'request.%IsA("EnsLib.HL7.Message") Quit $$$ERROR($$$GeneralError, "ADT to Ward expects an HL7 message, got " _ $CLASSNAME(request))
    Set op = ##class(Interlock.Util.OperationKey).FromHL7(request, .sc)
    If $$$ISERR(sc) Quit sc
    Set wardOp = ##class(Interlock.Msg.WardOperation).FromOperation(op)
    Set wardOp.Purpose = "normal"
    Set wardOp.SourceHeaderId = ..%PrimaryRequestHeader.%Id()
    $$$TRACE("Operation " _ wardOp.OperationKey _ " (" _ wardOp.Event _ $SELECT(wardOp.Ward '= "": " to " _ wardOp.Ward, 1: "") _ ")")
    Set sc = ..SendRequestSync(..WardTarget, wardOp, .result, ..DeliveryTimeout)
    If $$$ISERR(sc) || '$ISOBJECT($GET(result)) {
        Set text = "The connector did not answer: " _ $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no response")
        Do ..OpenCase(op, "uncertain_outcome", text, "")
        Quit $$$ERROR($$$GeneralError, text)
    }
    Set response = result
    If result.IsInEffect() {
        $$$TRACE("Delivered: " _ result.Outcome _ " (HTTP " _ result.HttpStatus _ ", version " _ result.EncounterVersion _ ")")
        Quit $$$OK
    }
    Set kind = $CASE(result.Outcome, "uncertain": "uncertain_outcome", "unavailable": "delivery_failed", "error": "delivery_failed", : "rejected")
    Set text = "Delivery " _ result.Outcome _ $SELECT(result.ReasonCode '= "": " (" _ result.ReasonCode _ ")", 1: "") _ $SELECT(result.HttpStatus '= "": ", HTTP " _ result.HttpStatus, 1: "") _ $SELECT(result.Error '= "": ": " _ result.Error, 1: "")
    Set caseId = ..OpenCase(op, kind, text, result)
    Quit $$$ERROR($$$GeneralError, text _ $SELECT(caseId '= "": ". Case " _ caseId _ " opened", 1: ""))
}

/// Send the intake to the case workflow asynchronously; returns the case id when the workflow
/// answered within a short wait, else "".
Method OpenCase(op As %DynamicObject, kind As %String, text As %String, result As Interlock.Msg.WardResult) As %String
{
    Set intake = ##class(Interlock.Msg.CaseIntake).%New()
    Set intake.OperationJSON = op.%ToJSON()
    Set intake.FailureKind = kind
    Set intake.FailureText = text
    Set intake.SourceHeaderId = ..%PrimaryRequestHeader.%Id()
    Set intake.EnsSessionId = ..%SessionId
    Set intake.Mode = $GET(^Interlock.Config("mode"), "board")
    If $ISOBJECT(result) {
        Set r = {}
        Set r."http_status" = result.HttpStatus, r.outcome = result.Outcome, r."reason_code" = result.ReasonCode
        Set r.response = result.ResponseObject(), r.error = result.Error
        Set intake.WardResultJSON = r.%ToJSON()
    }
    Set sc = ..SendRequestSync(..CaseTarget, intake, .started, 10)
    If $$$ISERR(sc) {
        $$$LOGWARNING("Could not open a case: " _ $SYSTEM.Status.GetErrorText(sc))
        Quit ""
    }
    If '$ISOBJECT($GET(started)) Quit ""
    $$$TRACE("Case " _ started.CaseId _ $SELECT(started.Opened: " opened", 1: " updated"))
    Quit started.CaseId
}

Method OnResponse(request As %Library.Persistent, ByRef response As %Library.Persistent, callrequest As %Library.Persistent, callresponse As %Library.Persistent, completionkey As %String) As %Status
{
    Quit $$$OK
}

}
