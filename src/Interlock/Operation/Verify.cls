/// The verifier: reads the receiver's committed history and receipts after an attempt, or after
/// a non-write disposition, and says what holds. It never infers from a timeout or a missing
/// receipt that nothing was applied.
Class Interlock.Operation.Verify Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

Method OnVerifyRequest(request As Interlock.Msg.VerifyRequest, Output response As Interlock.Msg.VerifyResult) As %Status
{
    Set response = ##class(Interlock.Msg.VerifyResult).%New()
    Set case = ##class(Interlock.Store.Case).ByCaseId(request.CaseId)
    If '$ISOBJECT(case) Set response.Error = "Unknown case " _ request.CaseId, response.Outcome = "failed" Quit $$$OK
    Set plan = ##class(Interlock.Store.Plan).%OpenId(request.PlanId)
    Set attempt = ##class(Interlock.Store.ExecutionAttempt).%OpenId(request.AttemptId)
    Set encounter = ..Get("/wards/api/encounters/" _ $ZCONVERT(case.EncounterId, "O", "URL"), .estatus)
    Set receipt = ..Get("/wards/api/receipts/" _ $ZCONVERT(case.OperationKey, "O", "URL"), .rstatus)
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
            Set current = ##class(Interlock.Util.Json).Str(encounter, "ward")
            Set state = ##class(Interlock.Util.Json).Str(encounter, "state")
            Set later = ..LaterThan(encounter, case.EventTime)
            // A receiver that reports no history at all: the receipt plus a consistent current
            // state is the best available evidence, and the detail says so.
            Set history = encounter.%Get("history")
            Set noHistory = '$ISOBJECT(history) || (history.%Size() = 0)
            If 'inHistory && noHistory {
                Set versionAfter = +##class(Interlock.Util.Json).Str(receipt, "version_after", 0)
                Set versionNow = +##class(Interlock.Util.Json).Str(encounter, "version", 0)
                Set consistent = (versionNow >= versionAfter) && $CASE(case.Event, "transfer": current = case.Ward, "admit": current = case.Ward, "discharge": state = "discharged", : 1)
                If consistent Set inHistory = 1, detail."history_note" = "The receiver reports no history; verified from the receipt and the current state"
            }
            If inHistory {
                If later '= "" {
                    Set outcome = "verified"
                    Set text = "Committed (receipt " _ $EXTRACT(##class(Interlock.Util.Json).Str(receipt, "applied_at"), 1, 19) _ ", version " _ ##class(Interlock.Util.Json).Str(receipt, "version_after") _ "); a later event followed: " _ later _ ". Current state " _ state _ $SELECT(current '= "": " in " _ current, 1: "")
                    Set detail."superseded_after" = later
                } Else {
                    Set outcome = "verified"
                    Set text = "Committed and current: receipt " _ $EXTRACT(##class(Interlock.Util.Json).Str(receipt, "applied_at"), 1, 19) _ ", version " _ ##class(Interlock.Util.Json).Str(receipt, "version_after") _ "; the encounter is " _ state _ $SELECT(current '= "": " in " _ current, 1: "")
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
            Set current = ##class(Interlock.Util.Json).Str(encounter, "ward")
            Set state = ##class(Interlock.Util.Json).Str(encounter, "state")
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
    Set sc = ##class(Interlock.Store.Verification).Create(case, attempt, outcome, text, detail, .v)
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
            Set parsed = ##class(Interlock.Util.Json).Parse(text, .psc)
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
    While iter.%GetNext(.i, .h) { If ##class(Interlock.Util.Json).Str(h, "operation_key") = key Quit }
    Quit $ISOBJECT($GET(h)) && (##class(Interlock.Util.Json).Str(h, "operation_key") = key)
}

/// The latest transfer or discharge in the history after a time, described, or "".
Method LaterThan(encounter As %DynamicObject, eventTime As %String) As %String [ Private ]
{
    Set found = ""
    Set history = encounter.%Get("history")
    If '$ISOBJECT(history) Quit ""
    Set iter = history.%GetIterator()
    While iter.%GetNext(.i, .h) {
        Set t = ##class(Interlock.Util.Json).Str(h, "event_time")
        If '(t ]] eventTime) Continue
        Set event = ##class(Interlock.Util.Json).Str(h, "event")
        If (event = "transfer") || (event = "discharge") Set found = event _ $SELECT(##class(Interlock.Util.Json).Str(h, "ward") '= "": " to " _ h.ward, 1: "") _ " at " _ t
    }
    Quit found
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Interlock.Msg.VerifyRequest">
    <Method>OnVerifyRequest</Method>
  </MapItem>
</MapItems>
}

}
