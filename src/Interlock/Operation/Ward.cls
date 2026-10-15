/// The connector to the ward system: one HTTP contract for normal traffic, rehearsals and
/// recovery writes (docs/CONTRACTS.md, section 1). It classifies what the receiver answered and
/// never retries on its own: an uncertain outcome is reported as such, and reconciliation by
/// operation key is the case workflow's job.
Class Interlock.Operation.Ward Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Parameter INVOCATION = "Queue";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

/// The operations endpoint's path on the ward system.
Property OperationsPath As %String(MAXLEN = 200) [ InitialExpression = "/wards/api/operations" ];

Parameter SETTINGS = "OperationsPath:Ward";

Method OnWardOperation(request As Interlock.Msg.WardOperation, Output response As Interlock.Msg.WardResult) As %Status
{
    Set response = ##class(Interlock.Msg.WardResult).%New()
    Set body = request.ToWardJSON()
    $$$TRACE($SELECT(request.DryRun: "Rehearsal", 1: "Operation") _ " " _ request.OperationKey _ $SELECT(request.ExpectedVersion '= "": ", expected version " _ request.ExpectedVersion, 1: ""))
    Set http = ##class(%Net.HttpRequest).%New()
    Set http.ContentType = "application/json"
    Do http.EntityBody.Write(body.%ToJSON())
    Set start = $ZHOROLOG
    Set sc = ..Adapter.SendFormDataArray(.httpResponse, "POST", http, "", "", ..OperationsPath)
    Set response.DurationMs = (($ZHOROLOG - start) * 1000) \ 1
    Set ..Retry = 0
    Set text = ""
    If $ISOBJECT($GET(httpResponse)) {
        Set response.HttpStatus = +httpResponse.StatusCode
        Set text = ""
        If $ISOBJECT(httpResponse.Data) {
            Do httpResponse.Data.Rewind()
            While 'httpResponse.Data.AtEnd { Set text = text _ httpResponse.Data.Read(32000) }
        }
        Set response.ResponseJSON = text
    }
    Set parsed = ##class(Interlock.Util.Json).Parse(text, .psc)
    If '$ISOBJECT(parsed) || $$$ISERR(psc) Set parsed = {}
    Do ..Classify(request, response, sc, parsed)
    $$$TRACE("Outcome " _ response.Outcome _ $SELECT(response.ReasonCode '= "": " (" _ response.ReasonCode _ ")", 1: "") _ ", HTTP " _ response.HttpStatus _ ", " _ response.DurationMs _ " ms")
    Quit $$$OK
}

/// Map the HTTP status, the adapter's status and the body to an outcome.
Method Classify(request As Interlock.Msg.WardOperation, response As Interlock.Msg.WardResult, sc As %Status, parsed As %DynamicObject) [ Private ]
{
    Set status = response.HttpStatus
    Set errorCode = ##class(Interlock.Util.Json).Str(parsed, "error")
    Set response.ReasonCode = errorCode
    If $ISOBJECT(parsed.%Get("receipt")) Set response.ReceiptJSON = parsed.%Get("receipt").%ToJSON()
    Set enc = parsed.%Get("encounter")
    If '$ISOBJECT(enc) Set enc = parsed.%Get("encounter_after")
    If $ISOBJECT(enc) Set response.EncounterVersion = ##class(Interlock.Util.Json).Str(enc, "version")
    If ##class(Interlock.Util.Json).Str(parsed, "current_version") '= "" Set response.EncounterVersion = parsed.%Get("current_version")
    If status = "" {
        // No HTTP response at all: refused connections never sent anything; anything else is unknown.
        Set msg = $SELECT($$$ISERR(sc): $SYSTEM.Status.GetErrorText(sc), 1: "no response")
        Set response.Error = msg
        Set lower = $ZCONVERT(msg, "L")
        If (lower [ "refused") || (lower [ "unable to connect") || (lower [ "connect failed") || (lower [ "<READ>" ) && 0 {
            Set response.Outcome = "unavailable"
        } ElseIf (lower [ "refused") || (lower [ "unable to connect") || (lower [ "connect failed") || (lower [ "no route") {
            Set response.Outcome = "unavailable"
        } Else {
            Set response.Outcome = "uncertain"
        }
        Quit
    }
    If status = 201 { Set response.Outcome = "applied" Quit }
    If status = 200 {
        If ##class(Interlock.Util.Json).Bool(parsed, "rehearsal") {
            Set response.Outcome = $SELECT(##class(Interlock.Util.Json).Bool(parsed, "would_apply"): "would_apply", 1: "would_not_apply")
            Set response.ReasonCode = ##class(Interlock.Util.Json).Str(parsed, "reason")
        } ElseIf ##class(Interlock.Util.Json).Str(parsed, "reason") = "already_committed" {
            Set response.Outcome = "already_committed"
        } Else {
            Set response.Outcome = $SELECT(##class(Interlock.Util.Json).Bool(parsed, "applied"): "applied", 1: "already_committed")
        }
        Quit
    }
    If status = 409 {
        Set response.Outcome = $SELECT(errorCode = "version_conflict": "version_conflict", 1: "refused")
        Quit
    }
    If status = 422 { Set response.Outcome = "refused" Quit }
    If status = 503 { Set response.Outcome = "unavailable" Set response.Error = "The ward system is unavailable" Quit }
    If status = 504 { Set response.Outcome = "uncertain" Set response.Error = "The ward system did not answer in time; the operation may have been applied" Quit }
    If (status = 401) || (status = 403) || (status = 404) {
        Set response.Outcome = "error"
        Set response.Error = "HTTP " _ status _ " from the ward system: " _ $SELECT(status = 404: "endpoint not found", 1: "not authorised")
        Quit
    }
    Set response.Outcome = $SELECT(status >= 500: "uncertain", 1: "error")
    Set response.Error = "HTTP " _ status _ $SELECT($$$ISERR(sc): ": " _ $SYSTEM.Status.GetErrorText(sc), 1: "")
    Quit
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Interlock.Msg.WardOperation">
    <Method>OnWardOperation</Method>
  </MapItem>
</MapItems>
}

}
