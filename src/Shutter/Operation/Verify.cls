/// The verifier: reads the receiver's committed history and receipts after an attempt, or after
/// a non-write disposition, and says what holds. It never infers from a timeout or a missing
/// receipt that nothing was applied.
Class Shutter.Operation.Verify Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// The receiver whose paths are read when the case names none.
Property Receiver As %String(MAXLEN = 128) [ InitialExpression = "Ward Out" ];

Parameter SETTINGS = "Receiver:Verify";

Method OnVerifyRequest(request As Shutter.Msg.VerifyRequest, Output response As Shutter.Msg.VerifyResult) As %Status
{
    Set response = ##class(Shutter.Msg.VerifyResult).%New()
    Set case = ##class(Shutter.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Set response.Error = "Unknown case " _ request.CaseId, response.Outcome = "failed" Quit $$$OK
    Set plan = ##class(Shutter.Store.Plan).%OpenId(request.PlanId)
    Set attempt = ##class(Shutter.Store.ExecutionAttempt).%OpenId(request.AttemptId)
    Set receiver = $SELECT(case.Receiver '= "": case.Receiver, 1: ..Receiver)
    Set encounter = ..Get(##class(Shutter.Store.SiteProfile).ReceiverPath(receiver, "state", case.EncounterId), .estatus)
    Set receiptPath = ##class(Shutter.Store.SiteProfile).ReceiverPath(receiver, "receipt", "", case.OperationKey)
    Set receipt = $SELECT(receiptPath = "": {}, 1: ..Get(receiptPath, .rstatus))
    If receiptPath = "" Set rstatus = 0
    Set detail = {}
    Set detail."encounter_http_status" = estatus, detail.encounter = encounter
    Set detail."receipt_http_status" = rstatus, detail.receipt = receipt
    Set disposition = $SELECT($ISOBJECT(plan): plan.Disposition, 1: case.Disposition)
    Set detail.disposition = disposition
    Set outcome = "unresolved", text = ""
    If (estatus = 0) || (rstatus = 0) {
        Set text = "The receiver could not be read; nothing is established"
    } ElseIf (disposition = "resend") || (disposition = "reconcile") {
        If rstatus = 200 {
            Set inHistory = ..InHistory(encounter, case.OperationKey)
            Set current = ##class(Shutter.Util.Json).Str(encounter, "ward")
            Set state = ##class(Shutter.Util.Json).Str(encounter, "state")
            Set later = ..LaterThan(encounter, case.EventTime)
            If inHistory {
                If later '= "" {
                    Set outcome = "verified"
                    Set text = "Committed (receipt " _ $EXTRACT(##class(Shutter.Util.Json).Str(receipt, "applied_at"), 1, 19) _ ", version " _ ##class(Shutter.Util.Json).Str(receipt, "version_after") _ "); a later event followed: " _ later _ ". Current state " _ state _ $SELECT(current '= "": " in " _ current, 1: "")
                    Set detail."superseded_after" = later
                } Else {
                    Set outcome = "verified"
                    Set text = "Committed and current: receipt " _ $EXTRACT(##class(Shutter.Util.Json).Str(receipt, "applied_at"), 1, 19) _ ", version " _ ##class(Shutter.Util.Json).Str(receipt, "version_after") _ "; the encounter is " _ state _ $SELECT(current '= "": " in " _ current, 1: "")
                }
            } Else {
                Set text = "A receipt exists but the operation is missing from the committed history"
            }
        } ElseIf rstatus = 404 {
            Set text = "The receiver holds no receipt for the operation: it was not committed"
            Set outcome = "failed"
        } Else {
            Set text = "The receipt lookup answered HTTP " _ rstatus
        }
    } ElseIf disposition = "superseded" {
        If estatus = 200 {
            Set later = ..LaterThan(encounter, case.EventTime)
            Set current = ##class(Shutter.Util.Json).Str(encounter, "ward")
            Set state = ##class(Shutter.Util.Json).Str(encounter, "state")
            If (later '= "") && (rstatus = 404) {
                Set outcome = "verified"
                Set text = "Nothing was resent; the receiver's history shows the later event (" _ later _ ") and no receipt for the stale operation. Current state " _ state _ $SELECT(current '= "": " in " _ current, 1: "")
            } ElseIf rstatus = 200 {
                Set text = "The stale operation has a receipt after all: it was committed"
                Set outcome = "failed"
            } Else {
                Set text = "No later event in the receiver's history supports the supersession"
            }
        } Else {
            Set text = "The receiver's encounter could not be read (HTTP " _ estatus _ ")"
        }
    } Else {
        Set outcome = "unresolved"
        Set text = "Disposition " _ disposition _ ": nothing to verify at the receiver"
    }
    Set sc = ##class(Shutter.Store.Verification).Create(case, attempt, outcome, text, detail, .v)
    If $$$ISERR(sc) Set response.Error = $SYSTEM.Status.GetErrorText(sc)
    Set response.Outcome = outcome, response.Summary = text, response.DetailJSON = detail.%ToJSON()
    If $ISOBJECT($GET(v)) Set response.VerificationId = v.%Id()
    Do case.Note("artifact", "Verification: " _ outcome _ ". " _ text, "system", "verification:" _ response.VerificationId)
    $$$TRACE("Verification for " _ case.CaseId _ ": " _ outcome)
    Quit $$$OK
}

Method Get(path As %String, Output status As %Integer) As %DynamicObject [ Private ]
{
    Set status = 0, body = {}
    Try {
        Set http = ##class(%Net.HttpRequest).%New()
        Set sc = ..Adapter.SendFormDataArray(.resp, "GET", http, "", "", path)
        Set ..Retry = 0
        If $ISOBJECT($GET(resp)) {
            Set status = +resp.StatusCode
            Set text = ""
            If $ISOBJECT(resp.Data) { Do resp.Data.Rewind() While 'resp.Data.AtEnd { Set text = text _ resp.Data.Read(32000) } }
            Set parsed = ##class(Shutter.Util.Json).Parse(text, .psc)
            If $ISOBJECT(parsed) && $$$ISOK(psc) Set body = parsed
        } ElseIf $$$ISERR(sc) {
            Set body.error = $SYSTEM.Status.GetErrorText(sc)
        }
    } Catch ex {
        Set body.error = ex.DisplayString()
    }
    Quit body
}

/// True when the encounter's history has an entry for the operation key.
Method InHistory(encounter As %DynamicObject, key As %String) As %Boolean [ Private ]
{
    Set history = encounter.%Get("history")
    If '$ISOBJECT(history) Quit 0
    Set iter = history.%GetIterator()
    While iter.%GetNext(.i, .h) { If ##class(Shutter.Util.Json).Str(h, "operation_key") = key Quit }
    Quit $ISOBJECT($GET(h)) && (##class(Shutter.Util.Json).Str(h, "operation_key") = key)
}

/// The latest transfer or discharge in the history after a time, described, or "".
Method LaterThan(encounter As %DynamicObject, eventTime As %String) As %String [ Private ]
{
    Set found = ""
    Set history = encounter.%Get("history")
    If '$ISOBJECT(history) Quit ""
    Set iter = history.%GetIterator()
    While iter.%GetNext(.i, .h) {
        Set t = ##class(Shutter.Util.Json).Str(h, "event_time")
        If '(t ]] eventTime) Continue
        Set event = ##class(Shutter.Util.Json).Str(h, "event")
        If (event = "transfer") || (event = "discharge") Set found = event _ $SELECT(##class(Shutter.Util.Json).Str(h, "ward") '= "": " to " _ h.ward, 1: "") _ " at " _ t
    }
    Quit found
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Shutter.Msg.VerifyRequest">
    <Method>OnVerifyRequest</Method>
  </MapItem>
</MapItems>
}

}
