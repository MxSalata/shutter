/// The verifier: reads the receiver's committed history and receipts after an attempt, or after
/// a non-write disposition, and says what holds. It never infers from a timeout or a missing
/// receipt that nothing was applied.
Class Shutter.Operation.Verify Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// The receiver whose paths are read when the case names none.
Property Receiver As %String(MAXLEN = 128) [ InitialExpression = {$PARAMETER("Shutter.Production", "RECEIVER")} ];

Parameter SETTINGS = "Receiver:Verify";

/// Whether the plan's catalogue entry closes the case with nothing to send on the case's evidence, as the gate judged.
ClassMethod ClosedByCatalogue(case As Shutter.Store.Case, plan As Shutter.Store.Plan) As %Boolean
{
    If '$ISOBJECT(plan) || '$ISOBJECT(case.CurrentSnapshot) Quit 0
    Set summary = case.CurrentSnapshot.SummaryObject()
    If '$ISOBJECT(summary) Quit 0
    Quit ##class(Shutter.Operation.Gate).ClosedByCatalogue(plan, summary)
}

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
    // -1: the receiver keeps no receipts; the committed history alone then shows the effect.
    If receiptPath = "" Set rstatus = -1
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
        } ElseIf rstatus = -1 {
            If (estatus = 200) && ..InHistory(encounter, case.OperationKey) {
                Set outcome = "verified"
                Set text = "Committed: the operation is in the receiver's history (the receiver keeps no receipts). Current state " _ ##class(Shutter.Util.Json).Str(encounter, "state") _ ", version " _ ##class(Shutter.Util.Json).Str(encounter, "version")
            } Else {
                Set text = "The receiver keeps no receipts and its history does not show the operation"
            }
        } Else {
            Set text = "The receipt lookup answered HTTP " _ rstatus
        }
    } ElseIf disposition = "superseded" {
        If estatus = 200 {
            Set later = ..LaterThan(encounter, case.EventTime)
            Set current = ##class(Shutter.Util.Json).Str(encounter, "ward")
            Set state = ##class(Shutter.Util.Json).Str(encounter, "state")
            If (later '= "") && ((rstatus = 404) || (rstatus = -1)) {
                Set outcome = "verified"
                Set text = "Nothing was resent; the receiver's history shows the later event (" _ later _ ") and no receipt for the stale operation. Current state " _ state _ $SELECT(current '= "": " in " _ current, 1: "")
            } ElseIf rstatus = 200 {
                Set text = "The stale operation has a receipt after all: it was committed"
                Set outcome = "failed"
            } ElseIf ..ClosedByCatalogue(case, plan) && '..InHistory(encounter, case.OperationKey) {
                // The gate passed the closure on the catalogue entry's say-so (CLOSED_BY_CATALOGUE): the receiver holds
                // neither a receipt nor the operation, which is what closing with nothing to send requires.
                Set outcome = "verified"
                Set text = "Nothing was resent; catalogue entry " _ plan.CatalogueEntry _ " closes the case with nothing to send, and the receiver holds neither a receipt nor the operation in its history. Current state " _ state _ $SELECT(current '= "": " in " _ current, 1: "")
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
ClassMethod InHistory(encounter As %DynamicObject, key As %String) As %Boolean
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
